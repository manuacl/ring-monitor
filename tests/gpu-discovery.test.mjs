import { test } from "node:test";
import assert from "node:assert/strict";
import {
    VENDOR_AMD,
    VENDOR_INTEL,
    discoverGpu,
    parseTempCelsius,
    _sortedDrmCards,
    _drmHwmonTempPath,
} from "../contents/ui/platforms/standalone/GpuDiscovery.js";

// Pure sysfs GPU discovery for the standalone build. The QML adapter does the
// I/O (ProcReader.listDir + read); these functions decide which DRM card to
// use and which sysfs files to read each tick. Vendor-agnostic path — see
// GpuDiscovery.js header.

// ── parseTempCelsius ──────────────────────────────────────────────────────

test("parseTempCelsius converts millidegrees to °C", () => {
    assert.equal(parseTempCelsius("75000"), 75);
    assert.equal(parseTempCelsius("75000\n"), 75);   // trailing newline from sysfs
    assert.equal(parseTempCelsius(" 52500 "), 52.5);
    assert.equal(parseTempCelsius("0"), 0);
    assert.equal(parseTempCelsius("-5000"), -5);     // physically possible
});

test("parseTempCelsius returns NaN for empty / garbage input", () => {
    assert.ok(Number.isNaN(parseTempCelsius("")));
    assert.ok(Number.isNaN(parseTempCelsius(null)));
    assert.ok(Number.isNaN(parseTempCelsius(undefined)));
    assert.ok(Number.isNaN(parseTempCelsius("N/A")));
});

// ── _sortedDrmCards ───────────────────────────────────────────────────────

test("_sortedDrmCards filters to card\\d+ and sorts numerically", () => {
    const entries = ["card1", "renderD128", "card0", "card1-DP-1", "version"];
    assert.deepEqual(_sortedDrmCards(entries), ["card0", "card1"]);
});

test("_sortedDrmCards sorts multi-digit card numbers numerically not lexically", () => {
    // card9 < card10 by number; lexically "card10" < "card9" — must be numeric.
    assert.deepEqual(_sortedDrmCards(["card10", "card9", "card1"]), ["card1", "card9", "card10"]);
});

test("_sortedDrmCards returns empty list when no card entries present", () => {
    assert.deepEqual(_sortedDrmCards(["renderD128", "version"]), []);
    assert.deepEqual(_sortedDrmCards([]), []);
    assert.deepEqual(_sortedDrmCards(null), []);
});

// ── _drmHwmonTempPath ─────────────────────────────────────────────────────

test("_drmHwmonTempPath returns temp1_input inside the first hwmonN entry", () => {
    const listDir = (p) => (p.endsWith("/hwmon") ? ["hwmon3"] : []);
    assert.equal(
        _drmHwmonTempPath("/sys/class/drm/card0/device/hwmon", listDir),
        "/sys/class/drm/card0/device/hwmon/hwmon3/temp1_input",
    );
});

test("_drmHwmonTempPath picks the lowest hwmonN when multiple are present", () => {
    // Multiple hwmon entries — the loop picks the first one (index order from
    // listDir, which mirrors the readdir order returned by QDir / ProcReader).
    const listDir = () => ["hwmon5", "hwmon2"];
    const result = _drmHwmonTempPath("/sys/class/drm/card0/device/hwmon", listDir);
    assert.ok(result.endsWith("/temp1_input"));
    // First entry in list wins regardless of numbering.
    assert.ok(result.includes("hwmon5"));
});

test("_drmHwmonTempPath returns null when hwmon dir is empty or absent", () => {
    assert.equal(_drmHwmonTempPath("/sys/class/drm/card0/device/hwmon", () => []), null);
    assert.equal(_drmHwmonTempPath("/sys/class/drm/card0/device/hwmon", () => null), null);
});

// ── discoverGpu ───────────────────────────────────────────────────────────

// Minimal fake filesystem factory: vendor map + optional hwmon + busy-percent.
function makeFs({ vendors = {}, hwmons = {}, busy = {} } = {}) {
    return {
        listDir(path) {
            if (path === "/sys/class/drm")
                return Object.keys(vendors);
            for (const [card, entries] of Object.entries(hwmons)) {
                if (path === `/sys/class/drm/${card}/device/hwmon`)
                    return entries;
            }
            return [];
        },
        read(path) {
            for (const [card, vendor] of Object.entries(vendors)) {
                if (path === `/sys/class/drm/${card}/device/vendor`)
                    return vendor + "\n";
            }
            for (const [card, val] of Object.entries(busy)) {
                if (path === `/sys/class/drm/${card}/device/gpu_busy_percent`)
                    return val;
            }
            return "";
        },
    };
}

test("discoverGpu detects AMD card — returns vendor, busyPath, and tempPath", () => {
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_AMD },
        hwmons: { card0: ["hwmon2"] },
        busy: { card0: "42\n" },
    });
    assert.deepEqual(discoverGpu(listDir, read), {
        vendor: "amd",
        busyPath: "/sys/class/drm/card0/device/gpu_busy_percent",
        tempPath: "/sys/class/drm/card0/device/hwmon/hwmon2/temp1_input",
    });
});

test("discoverGpu AMD: busyPath is null when gpu_busy_percent absent (older kernel)", () => {
    // SCENARIO: kernel < 4.19 amdgpu has no gpu_busy_percent; the ring should
    // not show GPU usage but can still show temperature if hwmon is available.
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_AMD },
        hwmons: { card0: ["hwmon2"] },
        // no busy entry → read returns "" for the file → busyPath set to null
    });
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.equal(result.vendor, "amd");
    assert.equal(result.busyPath, null);
    assert.equal(result.tempPath, "/sys/class/drm/card0/device/hwmon/hwmon2/temp1_input");
});

test("discoverGpu AMD: tempPath is null when no hwmon dir present", () => {
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_AMD },
        busy: { card0: "30\n" },
        // no hwmons entry → listDir returns [] for the hwmon dir
    });
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.ok(result.busyPath !== null);
    assert.equal(result.tempPath, null);
});

test("discoverGpu detects Intel card — busyPath null, tempPath present", () => {
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_INTEL },
        hwmons: { card0: ["hwmon1"] },
    });
    assert.deepEqual(discoverGpu(listDir, read), {
        vendor: "intel",
        busyPath: null,
        tempPath: "/sys/class/drm/card0/device/hwmon/hwmon1/temp1_input",
    });
});

test("discoverGpu returns null for NVIDIA-only host", () => {
    // NVIDIA is handled by NvmlReader, not sysfs — discoverGpu must skip it.
    const { listDir, read } = makeFs({ vendors: { card1: "0x10de" } });
    assert.equal(discoverGpu(listDir, read), null);
});

test("discoverGpu returns null when /sys/class/drm is empty", () => {
    assert.equal(discoverGpu(() => [], () => ""), null);
});

test("discoverGpu picks the lowest-numbered card when multiple AMD cards present", () => {
    // card0 must win over card1 for a stable result across boots.
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_AMD, card1: VENDOR_AMD },
        hwmons: { card0: ["hwmon0"], card1: ["hwmon1"] },
        busy: { card0: "55\n", card1: "60\n" },
    });
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.ok(result.busyPath.includes("card0"), "should pick card0, not card1");
});

test("discoverGpu skips NVIDIA and picks the AMD card behind it", () => {
    // Mixed host: card0 = NVIDIA, card1 = AMD (e.g. iGPU + dGPU).
    const { listDir, read } = makeFs({
        vendors: { card0: "0x10de", card1: VENDOR_AMD },
        hwmons: { card1: ["hwmon3"] },
        busy: { card1: "20\n" },
    });
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.equal(result.vendor, "amd");
    assert.ok(result.busyPath.includes("card1"));
});

test("vendor string is matched case-insensitively", () => {
    // The kernel always emits lowercase, but guard against a future variant.
    const listDir = (p) => (p === "/sys/class/drm" ? ["card0"] : []);
    const read = (p) => {
        if (p === "/sys/class/drm/card0/device/vendor") return "0X1002\n"; // uppercase
        if (p === "/sys/class/drm/card0/device/gpu_busy_percent") return "10\n";
        return "";
    };
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.equal(result.vendor, "amd");
});
