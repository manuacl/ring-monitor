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

typedef nvmlReturn_t (*fn_init_t)(void);                                  // nvmlInit_v2
typedef nvmlReturn_t (*fn_shutdown_t)(void);                             // nvmlShutdown
typedef nvmlReturn_t (*fn_handle_t)(unsigned int, nvmlDevice_t *);       // nvmlDeviceGetHandleByIndex_v2
typedef nvmlReturn_t (*fn_util_t)(nvmlDevice_t, nvmlUtilization_t *);    // nvmlDeviceGetUtilizationRates
typedef nvmlReturn_t (*fn_temp_t)(nvmlDevice_t, int, unsigned int *);    // nvmlDeviceGetTemperature

} // namespace

bool NvmlReader::ensureInit()
{
    if (_tried)
        return _ready;
    _tried = true;

    // SONAME, not the dev ".so" symlink — ".so.1" ships with the driver.
    // Absent on non-NVIDIA hosts → dlopen fails → GPU reports unavailable
    // (the binary still runs; this is not a hard dependency).
    _lib = dlopen("libnvidia-ml.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!_lib) {
        qWarning() << "NvmlReader: libnvidia-ml.so.1 not loadable — GPU "
                      "metrics unavailable (expected on non-NVIDIA hosts)";
        return false;
    }

    auto init = reinterpret_cast<fn_init_t>(dlsym(_lib, "nvmlInit_v2"));
    auto handle = reinterpret_cast<fn_handle_t>(dlsym(_lib, "nvmlDeviceGetHandleByIndex_v2"));
    _fnShutdown = dlsym(_lib, "nvmlShutdown");
    _fnGetUtil = dlsym(_lib, "nvmlDeviceGetUtilizationRates");
    _fnGetTemp = dlsym(_lib, "nvmlDeviceGetTemperature");

    if (!init || !handle || !_fnGetUtil || !_fnGetTemp) {
        qWarning() << "NvmlReader: required NVML symbols missing — GPU metrics unavailable";
        dlclose(_lib);
        _lib = nullptr;
        return false;
    }

    if (init() != kNvmlSuccess) {
        qWarning() << "NvmlReader: nvmlInit failed — GPU metrics unavailable";
        dlclose(_lib);
        _lib = nullptr;
        return false;
    }

    nvmlDevice_t dev = nullptr;
    if (handle(0, &dev) != kNvmlSuccess || !dev) {
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

QVariantMap NvmlReader::sample()
{
    QVariantMap out{
        { QStringLiteral("available"), false },
        { QStringLiteral("usage"), 0 },
        { QStringLiteral("tempC"), 0 },
    };
    if (!ensureInit())
        return out;

    out[QStringLiteral("available")] = true;

    // Each field independently — a transient query failure on one leaves
    // the other intact (and 0 for the failed one) rather than dropping
    // the whole sample.
    nvmlUtilization_t util{ 0, 0 };
    if (reinterpret_cast<fn_util_t>(_fnGetUtil)(_device, &util) == kNvmlSuccess)
        out[QStringLiteral("usage")] = static_cast<int>(util.gpu);

    unsigned int temp = 0;
    if (reinterpret_cast<fn_temp_t>(_fnGetTemp)(_device, kNvmlTemperatureGpu, &temp) == kNvmlSuccess)
        out[QStringLiteral("tempC")] = static_cast<int>(temp);

    return out;
}

NvmlReader::~NvmlReader()
{
    if (_ready && _fnShutdown)
        reinterpret_cast<fn_shutdown_t>(_fnShutdown)();
    if (_lib)
        dlclose(_lib);
}
