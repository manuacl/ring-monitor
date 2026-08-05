// Pure decisions behind the sensorTemp picker's Celsius-sensor
// discovery (issue #164). The Plasma MetricsBackend probes in two
// phases — a cheap SensorTreeModel walk, then a live Sensors.Sensor
// per candidate — and both sides of that seam defer to this module so
// the logic stays Node-testable:
//
//   isTempCandidate(display)        — phase 1 pre-filter: does a tree
//                                     DisplayRole string look like a
//                                     temperature leaf ("Composite (°C)")?
//                                     The localized name carries the unit
//                                     suffix; regex/group nodes don't.
//   buildTempSensorEntries(probed)  — phase 2: from probed candidates
//                                     [{id, name, unit, ready}] keep the
//                                     Celsius + Ready ones and shape the
//                                     [{id, label}] picker list
//                                     (duplicate names disambiguated,
//                                     sorted by label).
//
// Dual-loaded by QML (`import "TempSensorCatalog.js" as
// TempSensorCatalog`) and Node (via the module.exports shim at the
// bottom).

// KSysGuard::Unit::UnitCelsius as an int, as reported by
// Sensors.Sensor.unit — the Unit enum is not exposed to QML, so the
// literal is compared here. Value verified by live probe (#164).
var UNIT_CELSIUS = 1000;

function isTempCandidate(display) {
    return typeof display === "string" && /\(°C\)\s*$/.test(display);
}

// The device/chip part of a sensor id ("lmsensors/nct6775-isa-0290/temp1"
// → "nct6775", "cpu/cpu0/temperature" → "cpu0"). The bus/address tail
// ("-isa-0290", "-pci-0100") is noise in a picker label, so it is
// stripped; ids without a middle segment fall back to the first one.
function disambiguationSegment(id) {
    var parts = String(id).split("/");
    var segment = parts.length >= 2 ? parts[1] : parts[0];
    return segment.replace(/-(isa|pci|acpi|platform|virtual|spi)-[0-9a-z.]+$/i, "");
}

function buildTempSensorEntries(probed) {
    var entries = [];
    if (!probed || !probed.length)
        return entries;

    // Array-likeness by contract (.length + indexing) — never
    // Array.isArray, per the repo's QML-list-property rule.
    var kept = [];
    for (var i = 0; i < probed.length; i++) {
        var s = probed[i];
        if (s && s.ready && s.unit === UNIT_CELSIUS)
            kept.push({ id: String(s.id), name: String(s.name) });
    }

    // A name shared by several sensors (two chips both exposing
    // "Température 1") gets the chip segment appended; if even that
    // collides, the full id — unique by construction.
    var nameCounts = {};
    for (var j = 0; j < kept.length; j++)
        nameCounts[kept[j].name] = (nameCounts[kept[j].name] || 0) + 1;
    for (var k = 0; k < kept.length; k++) {
        var label = kept[k].name;
        if (nameCounts[label] > 1)
            label = label + " (" + disambiguationSegment(kept[k].id) + ")";
        entries.push({ id: kept[k].id, label: label });
    }
    var labelCounts = {};
    for (var m = 0; m < entries.length; m++)
        labelCounts[entries[m].label] = (labelCounts[entries[m].label] || 0) + 1;
    for (var n = 0; n < entries.length; n++) {
        if (labelCounts[entries[n].label] > 1)
            entries[n].label = kept[n].name + " (" + entries[n].id + ")";
    }

    // Locale-aware by label, then id, so the picker order is stable
    // across discovery refreshes.
    entries.sort(function (a, b) {
        var byLabel = a.label.localeCompare(b.label);
        return byLabel !== 0 ? byLabel : a.id.localeCompare(b.id);
    });
    return entries;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        UNIT_CELSIUS: UNIT_CELSIUS,
        isTempCandidate: isTempCandidate,
        disambiguationSegment: disambiguationSegment,
        buildTempSensorEntries: buildTempSensorEntries,
    };
}
