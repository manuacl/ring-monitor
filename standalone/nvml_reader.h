#pragma once

// QML-callable NVIDIA GPU reader for the standalone build, backed by
// NVML (the NVIDIA Management Library, libnvidia-ml) — the same C
// library `nvidia-smi` itself wraps, and what nvtop / btop / Conky /
// KDE's ksystemstats use. We DON'T shell out to `nvidia-smi`: a per-poll
// process spawn is ~20ms (a dropped frame at 60fps) and churns
// fork/exec; NVML calls are microseconds and run synchronously in the
// 2 Hz sampler with no GUI-thread jank.
//
// The library is loaded with `dlopen("libnvidia-ml.so.1")` at runtime
// (the SONAME, always shipped with the driver — not the dev `.so`
// symlink), so there is:
//   - no build-time dependency on the CUDA/NVML headers (the handful of
//     NVML symbols + types are self-declared in nvml_reader.cpp, the
//     btop/conky approach), and
//   - no hard link against libnvidia-ml: on an AMD/Intel-only box where
//     the library is absent, `dlopen` simply fails and `sample()`
//     reports `available:false` instead of the binary failing to start.
//
// Registered to QML via `QML_ELEMENT` (picked up by
// `qt_add_qml_module(... SOURCES nvml_reader.cpp …)`), exactly like
// `ProcReader`. Available in QML as
// `import RingMonitor.Standalone; NvmlReader { id: gpu }`.

#include <QObject>
#include <QVariantMap>
#include <QtQmlIntegration/QtQmlIntegration>

// Global scope (not in `ringmonitor::`) for the same reason as
// `ProcReader`: Qt's `QML_ELEMENT` auto-registration emits
// `qmlRegisterTypesAndRevisions<NvmlReader>(…)` without
// namespace-qualifying the type. See proc_reader.h for the full
// rationale.
class NvmlReader : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit NvmlReader(QObject *parent = nullptr) : QObject(parent) {}
    ~NvmlReader() override;

    // One GPU sample for device 0. Returns:
    //   { "available": bool, "usage": int (0-100 %), "tempC": int (°C) }
    // When detailed == true, also returns (each only on query success):
    //   "model"          QString  GPU product name (e.g. "NVIDIA GeForce RTX 4090")
    //   "vramUsedBytes"  qulonglong  bytes currently allocated on the GPU
    //   "vramTotalBytes" qulonglong  total framebuffer capacity in bytes
    //   "powerW"         double   power draw in watts (NVML gives milliwatts)
    //   "clockMhz"       int      SM (shader) clock in MHz
    // `available` is false when NVML can't be loaded or initialised (no
    // NVIDIA driver / library) — callers treat that like a sensor that
    // isn't present. When available, fields are present only for the
    // queries that succeeded this tick: a transient per-field failure
    // OMITS that key so the caller keeps its last-good value instead of
    // glitching to 0.
    // NVML is lazily initialised (one-time ~150ms driver handshake) and
    // the device handle is cached; subsequent calls are microsecond-cheap,
    // safe to invoke from the GUI thread each tick. The first-call
    // handshake is a one-time GUI-thread stall during warm-up — accepted
    // deliberately over the lifetime/sync complexity of an off-thread init
    // for a single ~150ms hitch that overlaps the startup sweep.
    Q_INVOKABLE QVariantMap sample(bool detailed = false);

private:
    bool ensureInit();   // dlopen + dlsym + nvmlInit; returns _ready

    void *_lib = nullptr;      // dlopen handle for libnvidia-ml.so.1
    void *_device = nullptr;   // cached nvmlDevice_t for index 0
    bool _ready = false;       // NVML loaded + initialised + device handle ok
    // Bounded init retry. The nvidia driver / libnvidia-ml can land a few
    // seconds AFTER the widget autostarts at login (same late-modprobe
    // race the CPU-temp re-resolve in MetricsBackend handles). ensureInit
    // re-attempts for _kMaxInitAttempts ticks, then gives up so a
    // non-NVIDIA host doesn't dlopen every tick for the whole session.
    int _initAttempts = 0;
    static constexpr int kMaxInitAttempts = 60;  // ~30s at the 2 Hz Timer

    // Resolved NVML entry points (typed in the .cpp to keep NVML's
    // self-declared typedefs out of the header).
    void *_fnShutdown = nullptr;
    void *_fnGetUtil = nullptr;
    void *_fnGetTemp = nullptr;
    // Detail-mode entry points — optional. Older drivers may lack some;
    // ensureInit() resolves them best-effort and leaves them null if absent.
    // sample(detailed=true) guards each with `if (_fnGetXxx)` before calling.
    void *_fnGetMem = nullptr;
    void *_fnGetPower = nullptr;
    void *_fnGetClock = nullptr;
    void *_fnGetName = nullptr;
};
