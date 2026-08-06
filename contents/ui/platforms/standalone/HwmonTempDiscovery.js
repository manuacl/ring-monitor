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
// segment, appended to every picker label (unless the label IS the
// stem — thermal zones, see _disambiguateLabels).
function _stemOf(id) {
    return String(id).replace(/\/[^/]+$/, "");
}

// Every picker label carries its chip stem — the raw sysfs names are
// too generic to pick from ("Composite (nvme)", "Tctl (k10temp)",
// "temp1 (acpitz)"). It also keeps twins selectable: two drives both
// reporting "Composite" land on distinct stems, where a bare duplicate
// label would make the combo's text-to-id mapping take the FIRST match
// (review finding, #167 — mirrors the Plasma TempSensorCatalog). A
// label already EQUAL to its stem stays bare (thermal zones, whose only
// name is the type — "acpitz (acpitz)" would be noise). A duplicated
// stem-form (same label twice on ONE chip) falls back to the full id,
// unique by construction.
function _disambiguateLabels(entries) {
    var forms = [];
    var formCount = {};
    var i;
    for (i = 0; i < entries.length; i++) {
        var stem = _stemOf(entries[i].id);
        forms[i] = entries[i].label === stem ? entries[i].label : entries[i].label + " (" + stem + ")";
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

// THERMAL-ZONE catalog from /sys/class/thermal — merged into the picker
// alongside hwmon after filterMirroredZones drops the zones a hwmon chip
// already exposes (the adapter, HwmonTempSensors.enumerate, always calls
// both). Zones without a hwmon counterpart keep boot-stable ids even if a
// driver late-modprobes at the next boot (review finding, #167).
//   zones: [{ dir: "thermal_zone3", type: "x86_pkg_temp",
//             device: "LNXSYSTM:00" }]
// Same stable-id grammar as hwmon: "<type>/temp", or
// "<type>@<device>/temp" on type collision (the device basename is stable,
// the zone NUMBER is registration-order and never persisted — except as
// the LAST resort "<type>@<zone-dir>/temp" when colliding types have no
// resolvable device: an unstable suffix beats a duplicated id, which the
// picker's text→id first-match would render unreachable). Zones have no
// label file: the type is the name, and _disambiguateLabels leaves it
// bare (label == stem).
function buildThermalCatalog(zones) {
    if (!zones || typeof zones.length !== "number")
        return [];
    var typeCount = {};
    for (var i = 0; i < zones.length; i++) {
        var t = String(zones[i].type || "");
        if (t)
            typeCount[t] = (typeCount[t] || 0) + 1;
    }
    var out = [];
    for (i = 0; i < zones.length; i++) {
        var z = zones[i];
        var type = String(z.type || "").trim();
        if (!type || !z.dir)
            continue;
        var stem = type;
        var device = String(z.device || "");
        if (typeCount[type] > 1)
            stem = type + "@" + (device || z.dir);
        out.push({
            "id": stem + "/temp",
            "label": type,
            "path": "/sys/class/thermal/" + z.dir + "/temp",
        });
    }
    // Deterministic order (readdir is arbitrary): the id embeds type +
    // device, so an id sort is the chip/device sort of buildCatalog.
    out.sort(function (a, b) {
        if (a.id < b.id) return -1;
        if (a.id > b.id) return 1;
        return 0;
    });
    _disambiguateLabels(out);
    return out;
}

// Drop the thermal zones a hwmon chip ALREADY exposes, so the merged
// picker list doesn't double entries. The kernel links a thermal-backed
// hwmon chip to its zone through the `device` symlink: its basename IS
// the zone dir (`hwmon0 acpitz_0` → device `../../thermal_zone0`). A chip
// with an unresolvable device symlink never mirrors (no link to compare
// against). With no chips at all (ARM boards / VMs whose temps live only
// in the thermal framework) every zone is kept — the union then equals
// the old fallback catalog.
//   chips: [{ device: "thermal_zone0", … }] — same shape as buildCatalog's
//   zones: [{ dir: "thermal_zone0", … }]  — same shape as buildThermalCatalog's
function filterMirroredZones(chips, zones) {
    if (!zones || typeof zones.length !== "number")
        return [];
    if (!chips || typeof chips.length !== "number")
        return zones;
    var mirrored = {};
    for (var i = 0; i < chips.length; i++) {
        var device = String(chips[i].device || "");
        if (device)
            mirrored[device] = true;
    }
    var out = [];
    for (i = 0; i < zones.length; i++) {
        if (!mirrored[String(zones[i].dir || "")])
            out.push(zones[i]);
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parseTempCelsius: parseTempCelsius,
        isTempInput: isTempInput,
        tempIndexFromInput: tempIndexFromInput,
        buildCatalog: buildCatalog,
        buildThermalCatalog: buildThermalCatalog,
        filterMirroredZones: filterMirroredZones,
        resolveSensorPath: resolveSensorPath,
    };
}
