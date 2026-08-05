// Custom hardware temperature sensor discovery for the standalone build
// (issue #164): enumerates EVERY hwmon temperature input — not just the
// CPU one, which stays CpuTempDiscovery.js's job — and gives each a
// STABLE id the settings dialog can persist and the backend can resolve
// back to the current-boot sysfs path at runtime.
//
// Id grammar (frozen with the Plasma side, whose lmsensors/<chip-bus>/
// tempN ids are equally hwmonN-free):
//   <chipName>/temp<N>            e.g. "nvme/temp1", "k10temp/temp2"
//   <chipName>@<device>/temp<N>   when two hwmon dirs share a chip name
//                                 (two NVMe drives both report "nvme");
//                                 <device> = basename of the hwmonN/device
//                                 symlink target, e.g. "0000:04:00.0".
// The hwmonN numbering is allocation-order and CHANGES ACROSS BOOTS, so
// it never appears in the id: the id is the persisted handle, and each
// runtime enumeration rebuilds the id → current-path map.
//
// Same split as CpuTempDiscovery.js: the QML adapters (MetricsBackend /
// HwmonTempSensors) do the sysfs I/O through ProcReader and hand this
// module the enumerated raw data; every decision lives here and is
// Node-tested. Dual-loaded by QML and Node (module.exports shim at the
// bottom). No `.pragma library`.

// parseTempCelsius / isTempInput / tempIndexFromInput are verbatim
// copies of the CpuTempDiscovery one-liners: dual-loaded modules can't
// import each other (QML's `.import` is a hard syntax error under Node
// `require`, and Node's `require` doesn't exist in QML) — the same
// duplication GpuDiscovery.js already carries.
function parseTempCelsius(raw) {
    if (raw === undefined || raw === null) return NaN;
    var n = parseInt(String(raw).trim(), 10);
    if (!isFinite(n)) return NaN;
    return n / 1000;
}

function isTempInput(name) {
    return /^temp\d+_input$/.test(String(name));
}

function tempIndexFromInput(name) {
    var m = /^temp(\d+)_input$/.exec(String(name));
    return m ? parseInt(m[1], 10) : NaN;
}

// "temp3_input" → "temp3" — the label fallback when the chip exposes no
// tempN_label file (many virtual chips don't).
function _inputBaseName(input) {
    return String(input).replace(/_input$/, "");
}

// Deterministic catalog order: chip name, then device (so colliding
// chips keep a stable order), then numeric sensor index. The chips
// arrive in arbitrary readdir order, so sorting must happen here, not
// in the adapter.
function _compareChips(a, b) {
    var an = String(a.name || "");
    var bn = String(b.name || "");
    if (an !== bn) return an < bn ? -1 : 1;
    var ad = String(a.device || "");
    var bd = String(b.device || "");
    if (ad !== bd) return ad < bd ? -1 : 1;
    return 0;
}

function _compareSensors(a, b) {
    return tempIndexFromInput(a.input) - tempIndexFromInput(b.input);
}

// "nvme@0000:04:00.0/temp1" → "nvme@0000:04:00.0" — the id's chip
// segment, used as the picker-label suffix on collisions.
function _stemOf(id) {
    return String(id).replace(/\/[^/]+$/, "");
}

// Every picker label carries its chip stem — the raw sysfs names are
// too generic to pick from ("Composite (nvme)", "Tctl (k10temp)",
// "temp1 (acpitz)"). It also keeps twins selectable: two drives both
// reporting "Composite" land on distinct stems, where a bare duplicate
// label would make the combo's text-to-id mapping take the FIRST match
// (review finding, #167 — mirrors the Plasma TempSensorCatalog). A
// duplicated stem-form (same label twice on ONE chip) falls back to the
// full id, unique by construction.
function _disambiguateLabels(entries) {
    var forms = [];
    var formCount = {};
    var i;
    for (i = 0; i < entries.length; i++) {
        forms[i] = entries[i].label + " (" + _stemOf(entries[i].id) + ")";
        formCount[forms[i]] = (formCount[forms[i]] || 0) + 1;
    }
    for (i = 0; i < entries.length; i++) {
        entries[i].label = formCount[forms[i]] > 1 ? entries[i].label + " (" + entries[i].id + ")" : forms[i];
    }
}

// Build the full temperature catalog from enumerated raw data:
//   chips: [{ dir: "hwmon3", name: "nvme", device: "0000:04:00.0",
//             sensors: [{ input: "temp1_input", label: "Composite" }] }]
// `device` is "" when the symlink can't be resolved; `sensors` may be
// empty — a sensorless chip still counts for name-collision detection
// so an id doesn't change shape when a sensor appears after a late
// modprobe.
// Returns [{ id, label, path }] sorted chip-name then sensor index.
// `path` is the CURRENT-boot sysfs file (it embeds hwmonN); only `id`
// is stable enough to persist.
function buildCatalog(chips) {
    if (!chips || typeof chips.length !== "number")
        return [];
    var nameCount = {};
    for (var i = 0; i < chips.length; i++) {
        var n = String(chips[i].name || "");
        if (n)
            nameCount[n] = (nameCount[n] || 0) + 1;
    }
    var sorted = chips.slice().sort(_compareChips);
    var out = [];
    for (i = 0; i < sorted.length; i++) {
        var chip = sorted[i];
        var name = String(chip.name || "");
        if (!name || !chip.sensors || typeof chip.sensors.length !== "number")
            continue;
        var stem = name;
        var device = String(chip.device || "");
        // A colliding chip whose device symlink is unresolvable falls
        // back to the bare name (duplicate ids possible — resolveSensorPath
        // returns the first match): still better than baking the unstable
        // hwmonN dir into a persisted id.
        if (nameCount[name] > 1 && device)
            stem = name + "@" + device;
        var sensors = chip.sensors.slice().sort(_compareSensors);
        for (var j = 0; j < sensors.length; j++) {
            var s = sensors[j];
            if (!isTempInput(s.input))
                continue;
            var label = String(s.label || "").trim();
            out.push({
                "id": stem + "/" + _inputBaseName(s.input),
                "label": label || _inputBaseName(s.input),
                "path": "/sys/class/hwmon/" + chip.dir + "/" + s.input,
            });
        }
    }
    _disambiguateLabels(out);
    return out;
}

// Map a persisted sensor id back to the current-boot sysfs path, or ""
// when the id isn't in the catalog (sensor gone, or enumeration hasn't
// run yet). `catalog` may be a QML list rather than a real JS Array, so
// guard array-likeness instead of calling Array.isArray.
function resolveSensorPath(catalog, id) {
    if (!catalog || typeof catalog.length !== "number")
        return "";
    var wanted = String(id || "");
    if (!wanted)
        return "";
    for (var i = 0; i < catalog.length; i++) {
        if (catalog[i].id === wanted)
            return catalog[i].path;
    }
    return "";
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parseTempCelsius: parseTempCelsius,
        isTempInput: isTempInput,
        tempIndexFromInput: tempIndexFromInput,
        buildCatalog: buildCatalog,
        resolveSensorPath: resolveSensorPath,
    };
}
