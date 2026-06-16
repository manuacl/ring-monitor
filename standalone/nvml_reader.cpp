#include "nvml_reader.h"

#include <QDebug>

#include <dlfcn.h>

// ── Minimal self-declared NVML ABI ──────────────────────────────────
// We declare only the handful of entry points + types we call, so the
// build needs no CUDA/NVML headers and no link against libnvidia-ml.
// These signatures and the nvmlUtilization_t layout are stable NVML ABI
// (the same subset btop / nvtop / conky self-declare).
namespace {

typedef int nvmlReturn_t;          // 0 == NVML_SUCCESS
typedef void *nvmlDevice_t;        // opaque handle (pointer-sized)

struct nvmlUtilization_t {
    unsigned int gpu;              // % of the sampling period the GPU was busy
    unsigned int memory;          // % of the period GPU memory was accessed
};

constexpr int kNvmlSuccess = 0;
constexpr int kNvmlTemperatureGpu = 0;  // nvmlTemperatureSensors_t
constexpr int kNvmlClockSm = 1;         // nvmlClockType_t: GRAPHICS=0, SM=1, MEM=2

typedef nvmlReturn_t (*fn_init_t)(void);                                  // nvmlInit_v2
typedef nvmlReturn_t (*fn_shutdown_t)(void);                             // nvmlShutdown
typedef nvmlReturn_t (*fn_handle_t)(unsigned int, nvmlDevice_t *);       // nvmlDeviceGetHandleByIndex_v2
typedef nvmlReturn_t (*fn_util_t)(nvmlDevice_t, nvmlUtilization_t *);    // nvmlDeviceGetUtilizationRates
typedef nvmlReturn_t (*fn_temp_t)(nvmlDevice_t, int, unsigned int *);    // nvmlDeviceGetTemperature

// Detail-mode types — stable NVML ABI, same subset nvtop/conky self-declare.
struct nvmlMemory_t {            // nvmlDeviceGetMemoryInfo (v1)
    unsigned long long total;
    unsigned long long free;
    unsigned long long used;
};
typedef nvmlReturn_t (*fn_mem_t)(nvmlDevice_t, nvmlMemory_t *);           // nvmlDeviceGetMemoryInfo
typedef nvmlReturn_t (*fn_power_t)(nvmlDevice_t, unsigned int *);         // nvmlDeviceGetPowerUsage (milliwatts)
typedef nvmlReturn_t (*fn_clock_t)(nvmlDevice_t, int, unsigned int *);    // nvmlDeviceGetClockInfo (MHz)
typedef nvmlReturn_t (*fn_name_t)(nvmlDevice_t, char *, unsigned int);    // nvmlDeviceGetName

} // namespace

bool NvmlReader::ensureInit()
{
    if (_ready)
        return true;
    // Bounded retry (see header): the driver can load seconds after
    // autostart, so re-attempt for kMaxInitAttempts ticks then latch
    // off — a non-NVIDIA host must not dlopen every tick all session.
    // qWarning only on the FINAL attempt: a GPU-less host logs once, a
    // late-loading driver that eventually succeeds logs nothing.
    if (_initAttempts >= kMaxInitAttempts)
        return false;
    const bool lastAttempt = (++_initAttempts >= kMaxInitAttempts);

    // SONAME, not the dev ".so" symlink — ".so.1" ships with the driver.
    // Absent on non-NVIDIA hosts → dlopen fails → GPU reports unavailable
    // (the binary still runs; this is not a hard dependency).
    _lib = dlopen("libnvidia-ml.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!_lib) {
        if (lastAttempt)
            qWarning() << "NvmlReader: libnvidia-ml.so.1 not loadable — GPU "
                          "metrics unavailable (expected on non-NVIDIA hosts)";
        return false;
    }

    auto init = reinterpret_cast<fn_init_t>(dlsym(_lib, "nvmlInit_v2"));
    auto handle = reinterpret_cast<fn_handle_t>(dlsym(_lib, "nvmlDeviceGetHandleByIndex_v2"));
    _fnShutdown = dlsym(_lib, "nvmlShutdown");
    _fnGetUtil = dlsym(_lib, "nvmlDeviceGetUtilizationRates");
    _fnGetTemp = dlsym(_lib, "nvmlDeviceGetTemperature");

    // Detail-mode symbols — non-fatal if absent on older drivers. The
    // required-symbol guard below stays limited to init/handle/util/temp;
    // a driver that lacks e.g. GetPowerUsage still serves usage + temp.
    _fnGetMem   = dlsym(_lib, "nvmlDeviceGetMemoryInfo");
    _fnGetPower = dlsym(_lib, "nvmlDeviceGetPowerUsage");
    _fnGetClock = dlsym(_lib, "nvmlDeviceGetClockInfo");
    _fnGetName  = dlsym(_lib, "nvmlDeviceGetName");

    if (!init || !handle || !_fnGetUtil || !_fnGetTemp) {
        if (lastAttempt)
            qWarning() << "NvmlReader: required NVML symbols missing — GPU metrics unavailable";
        dlclose(_lib);
        _lib = nullptr;
        return false;
    }

    if (init() != kNvmlSuccess) {
        if (lastAttempt)
            qWarning() << "NvmlReader: nvmlInit failed — GPU metrics unavailable";
        dlclose(_lib);
        _lib = nullptr;
        return false;
    }

    nvmlDevice_t dev = nullptr;
    if (handle(0, &dev) != kNvmlSuccess || !dev) {
        if (lastAttempt)
            qWarning() << "NvmlReader: no NVML device 0 — GPU metrics unavailable";
        if (_fnShutdown)
            reinterpret_cast<fn_shutdown_t>(_fnShutdown)();
        dlclose(_lib);
        _lib = nullptr;
        return false;
    }

    _device = dev;
    _ready = true;
    return true;
}

QVariantMap NvmlReader::sample(bool detailed)
{
    QVariantMap out{
        { QStringLiteral("available"), false },
    };
    if (!ensureInit())
        return out;

    out[QStringLiteral("available")] = true;

    // Each field is committed ONLY on a successful query, and its key is
    // OMITTED otherwise — so a transient per-field failure leaves the
    // caller's last-good value untouched rather than overwriting it with
    // 0 (a one-tick ring glitch), and an unread temperature stays the
    // caller's NaN sentinel instead of a real-looking 0 °C.
    nvmlUtilization_t util{ 0, 0 };
    if (reinterpret_cast<fn_util_t>(_fnGetUtil)(_device, &util) == kNvmlSuccess)
        out[QStringLiteral("usage")] = static_cast<int>(util.gpu);

    unsigned int temp = 0;
    if (reinterpret_cast<fn_temp_t>(_fnGetTemp)(_device, kNvmlTemperatureGpu, &temp) == kNvmlSuccess)
        out[QStringLiteral("tempC")] = static_cast<int>(temp);

    if (detailed) {
        // Same omit-on-failure discipline: each key appears only when its
        // query succeeds. An older driver missing one of these entry points
        // is handled by the _fnGetXxx null-check before cast+call.
        if (_fnGetName) {
            char buf[96] = {};
            if (reinterpret_cast<fn_name_t>(_fnGetName)(_device, buf, sizeof(buf)) == kNvmlSuccess)
                out[QStringLiteral("model")] = QString::fromUtf8(buf);
        }

        if (_fnGetMem) {
            nvmlMemory_t mem{ 0, 0, 0 };
            if (reinterpret_cast<fn_mem_t>(_fnGetMem)(_device, &mem) == kNvmlSuccess) {
                out[QStringLiteral("vramUsedBytes")]  = static_cast<qulonglong>(mem.used);
                out[QStringLiteral("vramTotalBytes")] = static_cast<qulonglong>(mem.total);
            }
        }

        if (_fnGetPower) {
            unsigned int mw = 0;
            // NVML reports power in milliwatts; divide by 1000 for watts.
            if (reinterpret_cast<fn_power_t>(_fnGetPower)(_device, &mw) == kNvmlSuccess)
                out[QStringLiteral("powerW")] = mw / 1000.0;
        }

        if (_fnGetClock) {
            unsigned int mhz = 0;
            if (reinterpret_cast<fn_clock_t>(_fnGetClock)(_device, kNvmlClockSm, &mhz) == kNvmlSuccess)
                out[QStringLiteral("clockMhz")] = static_cast<int>(mhz);
        }
    }

    return out;
}

NvmlReader::~NvmlReader()
{
    if (_ready && _fnShutdown)
        reinterpret_cast<fn_shutdown_t>(_fnShutdown)();
    if (_lib)
        dlclose(_lib);
}
