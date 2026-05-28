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

test("NvmlReader is a QML_ELEMENT and includes <dlfcn.h>", () => {
    assert.match(HEADER, /QML_ELEMENT/, "header must declare QML_ELEMENT");
    assert.match(SRC, /#include\s*<dlfcn\.h>/, "must include <dlfcn.h> for dlopen/dlsym");
});

test("nvml_reader includes no Plasma headers (standalone isolation)", () => {
    assert.doesNotMatch(SRC, /#include\s*<plasma\//, "nvml_reader.cpp must not include Plasma headers");
    assert.doesNotMatch(HEADER, /#include\s*<plasma\//, "nvml_reader.h must not include Plasma headers");
});
