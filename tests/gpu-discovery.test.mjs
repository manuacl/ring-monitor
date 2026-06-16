import { test } from "node:test";
import assert from "node:assert/strict";
import {
    VENDOR_AMD,
    VENDOR_INTEL,
    VENDOR_NVIDIA,
    discoverGpu,
    parseTempCelsius,
    _sortedDrmCards,
    _drmHwmonDir,
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

// Minimal fake filesystem factory.
// vendors:   { cardN: vendorHex }
// hwmons:    { cardN: ["hwmonM", ...] }
// busy:      { cardN: "value\n" }     — gpu_busy_percent
// vramUsed:  { cardN: "value\n" }     — mem_info_vram_used
// vramTotal: { cardN: "value\n" }     — mem_info_vram_total
// power:     { cardN: "value\n" }     — hwmonM/power1_input (per-card; the
//                                       factory assumes the first hwmon entry)
function makeFs({ vendors = {}, hwmons = {}, busy = {}, vramUsed = {}, vramTotal = {}, power = {} } = {}) {
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
            for (const [card, val] of Object.entries(vramUsed)) {
                if (path === `/sys/class/drm/${card}/device/mem_info_vram_used`)
                    return val;
            }
            for (const [card, val] of Object.entries(vramTotal)) {
                if (path === `/sys/class/drm/${card}/device/mem_info_vram_total`)
                    return val;
            }
            // power1_input lives inside the first hwmon dir for the card
            for (const [card, val] of Object.entries(power)) {
                const hwmonEntries = hwmons[card] || [];
                if (hwmonEntries.length > 0) {
                    const hwmonDir = `/sys/class/drm/${card}/device/hwmon/${hwmonEntries[0]}`;
                    if (path === `${hwmonDir}/power1_input`)
                        return val;
                }
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

test("discoverGpu NVIDIA-only host falls back to nouveau temp-only (issue #106)", () => {
    // Proprietary-driver NVIDIA never reaches here (NVML takes priority in
    // MetricsBackend). On the nouveau driver NVML is unavailable, so we expose
    // the hwmon temperature; usage has no sysfs counter → busyPath null.
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_NVIDIA },
        hwmons: { card0: ["hwmon4"] },
    });
    assert.deepEqual(discoverGpu(listDir, read), {
        vendor: "nouveau",
        busyPath: null,
        tempPath: "/sys/class/drm/card0/device/hwmon/hwmon4/temp1_input",
    });
});

test("discoverGpu nouveau: tempPath is null when no hwmon dir present", () => {
    // A nouveau card without a registered hwmon yields no usable path → the
    // GPU-temp ring stays hidden (correct for a genuinely absent sensor).
    const { listDir, read } = makeFs({ vendors: { card0: VENDOR_NVIDIA } });
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.equal(result.vendor, "nouveau");
    assert.equal(result.busyPath, null);
    assert.equal(result.tempPath, null);
});

test("discoverGpu returns null when /sys/class/drm has no GPU card", () => {
    // Neither AMD/Intel nor NVIDIA present → nothing to discover.
    const { listDir, read } = makeFs({ vendors: { card0: "0x1234" } });
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

test("discoverGpu prefers AMD over a lower-numbered nouveau card (usage wins)", () => {
    // Mixed host: card0 = NVIDIA-nouveau, card1 = AMD. AMD exposes usage + temp,
    // nouveau only temp — so AMD wins even though it's the higher card number.
    // nouveau is a temp-only fallback, used only when no AMD/Intel card exists.
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_NVIDIA, card1: VENDOR_AMD },
        hwmons: { card0: ["hwmon0"], card1: ["hwmon3"] },
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

// ── _drmHwmonDir ──────────────────────────────────────────────────────────

test("_drmHwmonDir returns the full hwmonN dir path for the first entry", () => {
    const listDir = (p) => (p.endsWith("/hwmon") ? ["hwmon3"] : []);
    assert.equal(
        _drmHwmonDir("/sys/class/drm/card0/device/hwmon", listDir),
        "/sys/class/drm/card0/device/hwmon/hwmon3",
    );
});

test("_drmHwmonDir returns null when hwmon dir is empty or absent", () => {
    assert.equal(_drmHwmonDir("/sys/class/drm/card0/device/hwmon", () => []), null);
    assert.equal(_drmHwmonDir("/sys/class/drm/card0/device/hwmon", () => null), null);
});

// ── AMD VRAM and power path discovery ─────────────────────────────────────

test("discoverGpu AMD: vramUsedPath and vramTotalPath set when sysfs nodes present", () => {
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_AMD },
        hwmons:  { card0: ["hwmon2"] },
        busy:    { card0: "50\n" },
        vramUsed:  { card0: "4294967296\n" },
        vramTotal: { card0: "8589934592\n" },
    });
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.equal(result.vramUsedPath,  "/sys/class/drm/card0/device/mem_info_vram_used");
    assert.equal(result.vramTotalPath, "/sys/class/drm/card0/device/mem_info_vram_total");
});

test("discoverGpu AMD: powerPath set when power1_input present in hwmon dir", () => {
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_AMD },
        hwmons:  { card0: ["hwmon2"] },
        busy:    { card0: "50\n" },
        power:   { card0: "45000000\n" },  // 45 W in µW
    });
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.equal(result.powerPath, "/sys/class/drm/card0/device/hwmon/hwmon2/power1_input");
});

test("discoverGpu AMD: vram and power keys absent when sysfs nodes missing (graceful degrade)", () => {
    // SCENARIO: older amdgpu kernel or minimal driver build without VRAM/power
    // accounting; busyPath and tempPath must still resolve correctly.
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_AMD },
        hwmons:  { card0: ["hwmon2"] },
        busy:    { card0: "30\n" },
        // no vramUsed, vramTotal, or power entries
    });
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.equal(result.vendor, "amd");
    assert.ok(result.busyPath !== null, "busyPath must still resolve");
    assert.ok(result.tempPath !== null, "tempPath must still resolve");
    assert.equal(result.vramUsedPath,  undefined, "vramUsedPath must be absent");
    assert.equal(result.vramTotalPath, undefined, "vramTotalPath must be absent");
    assert.equal(result.powerPath,     undefined, "powerPath must be absent");
});

test("discoverGpu AMD: power absent when no hwmon dir present, vram still resolves", () => {
    // Card has VRAM nodes in device/ but no hwmon (unusual but possible during
    // late driver init). powerPath must be absent; vram paths must be present.
    const { listDir, read } = makeFs({
        vendors:   { card0: VENDOR_AMD },
        busy:      { card0: "10\n" },
        vramUsed:  { card0: "2147483648\n" },
        vramTotal: { card0: "8589934592\n" },
        // no hwmons → no hwmon dir → no tempPath, no powerPath
    });
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.equal(result.tempPath,  null,      "tempPath must be null without hwmon");
    assert.equal(result.powerPath, undefined, "powerPath must be absent without hwmon");
    assert.equal(result.vramUsedPath,  "/sys/class/drm/card0/device/mem_info_vram_used");
    assert.equal(result.vramTotalPath, "/sys/class/drm/card0/device/mem_info_vram_total");
});

test("discoverGpu Intel: no vram or power fields added (Intel branch unchanged)", () => {
    const { listDir, read } = makeFs({
        vendors: { card0: VENDOR_INTEL },
        hwmons:  { card0: ["hwmon1"] },
    });
    const result = discoverGpu(listDir, read);
    assert.ok(result);
    assert.equal(result.vendor, "intel");
    assert.equal(result.vramUsedPath,  undefined);
    assert.equal(result.vramTotalPath, undefined);
    assert.equal(result.powerPath,     undefined);
});
