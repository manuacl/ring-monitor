// Text-level guards for the standalone `NvmlReader` C++ helper.
// `standalone/nvml_reader.cpp` reads NVIDIA GPU usage + temperature via
// NVML (libnvidia-ml), loaded with dlopen. Same text-guard pattern as
// proc-reader.test.mjs / autostart.test.mjs (the standalone C++ isn't
// compiled in the Fedora CI container, so we assert the source contract
// as text rather than runtime behaviour).
//
// The contract these guards lock in:
//
//   1. NVML is dlopen'd by SONAME ("libnvidia-ml.so.1"), NOT linked at
//      build time and NOT loaded via the dev ".so" symlink — so the
//      binary builds and runs on machines without the NVIDIA driver.
//
//   2. A missing/unloadable library is handled gracefully (returns an
//      unavailable sample, no crash), so a non-NVIDIA host just sees the
//      GPU metric stay at 0 instead of the app aborting.
//
//   3. Registered to QML via QML_ELEMENT (like ProcReader).
//
//   4. No CUDA/NVML headers and no Plasma headers are included.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = readFileSync(join(__dirname, "..", "standalone", "nvml_reader.cpp"), "utf8");
const HEADER = readFileSync(join(__dirname, "..", "standalone", "nvml_reader.h"), "utf8");

test("NvmlReader dlopens the NVML SONAME, not the dev symlink", () => {
    // The .so.1 SONAME ships with the driver; the bare .so is a dev
    // symlink that may be absent. Using .so.1 is what btop/nvtop do.
    assert.match(SRC, /dlopen\s*\(\s*"libnvidia-ml\.so\.1"/, "must dlopen libnvidia-ml.so.1");
    assert.doesNotMatch(SRC, /dlopen\s*\(\s*"libnvidia-ml\.so"\s*[,)]/, "must NOT dlopen the bare .so dev symlink");
});

test("NvmlReader does not link NVML or include its headers at build time", () => {
    // dlopen means no build-time NVIDIA dependency. A #include of nvml.h
    // (or a CUDA header) would reintroduce one and break builds on boxes
    // without the toolkit.
    assert.doesNotMatch(SRC, /#include\s*[<"]nvml\.h[>"]/, "must not include nvml.h (types are self-declared)");
    assert.doesNotMatch(SRC, /#include\s*[<"]cuda/, "must not include CUDA headers");
    assert.doesNotMatch(HEADER, /#include\s*[<"]nvml\.h[>"]/, "header must not include nvml.h");
});

test("NvmlReader degrades gracefully when the library/driver is absent", () => {
    // dlopen failure must return (not crash) and warn — the GPU metric
    // then stays unavailable on a non-NVIDIA host.
    assert.match(SRC, /if\s*\(\s*!\s*_lib\s*\)/, "must check the dlopen result before use");
    assert.match(SRC, /qWarning\(\)[\s\S]*?unavailable/, "must warn (not abort) when NVML is unavailable");
    // The sample() return must default available:false so callers treat
    // a missing GPU like a missing sensor.
    assert.match(SRC, /"available"\s*\)\s*,\s*false/, "sample() must default available:false");
});

test("NvmlReader resolves NVML entry points by name via dlsym", () => {
    for (const sym of ["nvmlInit_v2", "nvmlShutdown", "nvmlDeviceGetHandleByIndex_v2", "nvmlDeviceGetUtilizationRates", "nvmlDeviceGetTemperature"]) {
        assert.match(SRC, new RegExp(`dlsym\\s*\\(\\s*_lib\\s*,\\s*"${sym}"`), `must dlsym ${sym}`);
    }
});

test("NvmlReader resolves detail-mode NVML symbols via dlsym", () => {
    // These four symbols enable the tooltip detail view (model name, VRAM,
    // power draw, SM clock). They are optional — older drivers may lack some —
    // so they must be resolved but NOT added to the required-symbol fatal guard.
    for (const sym of ["nvmlDeviceGetMemoryInfo", "nvmlDeviceGetPowerUsage", "nvmlDeviceGetClockInfo", "nvmlDeviceGetName"]) {
        assert.match(SRC, new RegExp(`dlsym\\s*\\(\\s*_lib\\s*,\\s*"${sym}"`), `must dlsym ${sym}`);
    }
});

test("NvmlReader detail symbols are NOT in the required-symbol fatal guard", () => {
    // The fatal guard must remain limited to init/handle/util/temp — a driver
    // missing e.g. GetPowerUsage must still serve usage + temp. Assert the
    // guard line lists exactly the four required symbols and none of the detail ones.
    const guardMatch = SRC.match(/if\s*\(\s*!init\s*\|\|[^)]+\)/);
    assert.ok(guardMatch, "required-symbol guard must be present");
    const guardLine = guardMatch[0];
    assert.match(guardLine, /_fnGetUtil/, "guard must include _fnGetUtil");
    assert.match(guardLine, /_fnGetTemp/, "guard must include _fnGetTemp");
    assert.doesNotMatch(guardLine, /_fnGetMem/, "guard must NOT include _fnGetMem (non-fatal)");
    assert.doesNotMatch(guardLine, /_fnGetPower/, "guard must NOT include _fnGetPower (non-fatal)");
    assert.doesNotMatch(guardLine, /_fnGetClock/, "guard must NOT include _fnGetClock (non-fatal)");
    assert.doesNotMatch(guardLine, /_fnGetName/, "guard must NOT include _fnGetName (non-fatal)");
});

test("NvmlReader sample() accepts a detailed parameter", () => {
    // The QML tooltip caller passes sample(true) for the detail view.
    assert.match(SRC, /sample\s*\(\s*bool\s+detailed/, "sample() must accept a bool detailed parameter");
    assert.match(HEADER, /sample\s*\(\s*bool\s+detailed\s*=\s*false\s*\)/, "header must declare sample(bool detailed = false)");
});

test("NvmlReader detail typedefs cover all four new entry points", () => {
    // Self-declared ABI — same subset nvtop/conky use.
    assert.match(SRC, /fn_mem_t/, "must declare fn_mem_t typedef");
    assert.match(SRC, /fn_power_t/, "must declare fn_power_t typedef");
    assert.match(SRC, /fn_clock_t/, "must declare fn_clock_t typedef");
    assert.match(SRC, /fn_name_t/, "must declare fn_name_t typedef");
    assert.match(SRC, /struct nvmlMemory_t/, "must self-declare nvmlMemory_t struct");
});

test("NvmlReader powerW converts milliwatts to watts by dividing by 1000", () => {
    // NVML GetPowerUsage returns milliwatts; the contract key is watts (a
    // double) so the tooltip can display "X.X W" without a conversion step.
    assert.match(SRC, /mw\s*\/\s*1000\.0/, "powerW must divide mW by 1000.0 to get watts");
});

test("NvmlReader is a QML_ELEMENT and includes <dlfcn.h>", () => {
    assert.match(HEADER, /QML_ELEMENT/, "header must declare QML_ELEMENT");
    assert.match(SRC, /#include\s*<dlfcn\.h>/, "must include <dlfcn.h> for dlopen/dlsym");
});

test("nvml_reader includes no Plasma headers (standalone isolation)", () => {
    assert.doesNotMatch(SRC, /#include\s*<plasma\//, "nvml_reader.cpp must not include Plasma headers");
    assert.doesNotMatch(HEADER, /#include\s*<plasma\//, "nvml_reader.h must not include Plasma headers");
});

test("NvmlReader resolves process-enumeration symbols via dlsym (non-fatal)", () => {
    // _v2 symbols require R460+; older drivers leave them null and
    // runningProcesses() returns an empty list — graceful degrade.
    assert.match(SRC, /dlsym\s*\(\s*_lib\s*,\s*"nvmlDeviceGetComputeRunningProcesses_v2"/, "must dlsym nvmlDeviceGetComputeRunningProcesses_v2");
    assert.match(SRC, /dlsym\s*\(\s*_lib\s*,\s*"nvmlDeviceGetGraphicsRunningProcesses_v2"/, "must dlsym nvmlDeviceGetGraphicsRunningProcesses_v2");
});

test("NvmlReader process symbols are NOT in the required-symbol fatal guard", () => {
    // The fatal guard must stay limited to init/handle/util/temp — a driver
    // missing process enumeration must still serve usage + temp + detail fields.
    const guardMatch = SRC.match(/if\s*\(\s*!init\s*\|\|[^)]+\)/);
    assert.ok(guardMatch, "required-symbol guard must be present");
    const guardLine = guardMatch[0];
    assert.doesNotMatch(guardLine, /_fnComputeProcs/, "guard must NOT include _fnComputeProcs (non-fatal)");
    assert.doesNotMatch(guardLine, /_fnGraphicsProcs/, "guard must NOT include _fnGraphicsProcs (non-fatal)");
});

test("NvmlReader declares runningProcesses Q_INVOKABLE", () => {
    // runningProcesses() must be callable from QML/JS so the tooltip model
    // can query it without bridging through sample().
    assert.match(HEADER, /Q_INVOKABLE\s+QVariantList\s+runningProcesses\s*\(\s*\)/, "header must declare Q_INVOKABLE QVariantList runningProcesses()");
    assert.match(SRC, /QVariantList\s+NvmlReader::runningProcesses\s*\(\s*\)/, "cpp must implement NvmlReader::runningProcesses()");
});

test("NvmlReader declares kNvmlErrorInsufficientSize", () => {
    // Two-pass protocol: NVML returns 7 on the probe call when processes exist
    // but the buffer is null — the implementation must recognise this code.
    assert.match(SRC, /kNvmlErrorInsufficientSize/, "must define kNvmlErrorInsufficientSize");
    assert.match(SRC, /constexpr int kNvmlErrorInsufficientSize\s*=\s*7/, "kNvmlErrorInsufficientSize must equal 7");
});

test("NvmlReader self-declares nvmlProcessInfo_v2_t struct", () => {
    // _v2 struct layout is stable NVML ABI (R460+), same approach as
    // nvmlMemory_t / nvmlUtilization_t already self-declared above.
    assert.match(SRC, /struct nvmlProcessInfo_v2_t/, "must self-declare nvmlProcessInfo_v2_t");
    assert.match(SRC, /fn_procs_t/, "must declare fn_procs_t typedef");
});

test("NvmlReader runningProcesses uses two-pass count-then-fill protocol", () => {
    // Pass 1: query count with null buffer; pass 2: fill a sized vector.
    // The guard on kNvmlErrorInsufficientSize is what distinguishes
    // "zero processes" from "processes exist, need a buffer".
    assert.match(SRC, /fn\s*\(\s*_device\s*,\s*&count\s*,\s*nullptr\s*\)/, "must make probe call with null buffer");
    assert.match(SRC, /kNvmlErrorInsufficientSize/, "must check kNvmlErrorInsufficientSize on probe result");
    assert.match(SRC, /std::vector<nvmlProcessInfo_v2_t>/, "must allocate a vector for the fill pass");
});
