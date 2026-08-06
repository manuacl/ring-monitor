import QtQuick
import RingMonitor.Standalone
import "HwmonTempDiscovery.js" as HwmonTemp

// hwmon temperature-sensor probe for the SETTINGS DIALOG, which has no
// MetricsBackend (SettingsOnlyRoot hosts only the dialog). Enumerates
// every hwmon temperature input once (plus on demand via enumerate()),
// falling back to /sys/class/thermal zones when hwmon has none (ARM
// boards / VMs), and, while `active`, refreshes all readings at 2 Hz so
// the picker can show a live value next to each candidate sensor.
//
// Thin I/O adapter: every decision (id grammar, collision disambiguation,
// label fallback, sorting) lives in the pure HwmonTempDiscovery.js
// module — this file only walks sysfs through ProcReader.
//
// MetricsBackend also instantiates this probe (with active: false) to
// share the enumeration glue: the backend resolves its configured id
// against `catalog` and does its own one-file-per-tick read.
//
// Public surface:
//   active      - gate for the 2 Hz live-reading refresh (default off).
//   tempSensors - [{ id, label }] of every discovered input, sorted chip
//                 then index; rebuilt only by enumerate().
//   catalog     - [{ id, label, path }] incl. the current-boot sysfs
//                 paths (hwmonN-based — resolve at runtime, never persist).
//   valueFor(id) - latest cached °C reading of a catalog id, NaN when
//                 never read. Reads _tick so bindings stay live.
//   enumerate() - re-run the full sysfs walk (startup retry window).

Item {
    id: probe

    property bool active: false

    readonly property var tempSensors: probe._tempSensors
    readonly property var catalog: probe._catalog

    function valueFor(id) {
        probe._tick;
        var v = probe._readings[id];
        return v === undefined ? NaN : v;
    }

    // Re-run the full hwmon walk and rebuild the catalog. Called once at
    // startup; the backend additionally calls it within its bounded
    // warm-up window so a late-modprobed driver still shows up.
    function enumerate() {
        var base = "/sys/class/hwmon";
        var dirs = reader.listDir(base);
        var chips = [];
        for (var i = 0; i < dirs.length; i++) {
            if (!/^hwmon\d+$/.test(dirs[i]))
                continue;
            var chip = base + "/" + dirs[i];
            var name = reader.read(chip + "/name").trim();
            if (!name)
                continue;
            // Basename of the device symlink target = the stable
            // disambiguator when two hwmon dirs share a chip name (the
            // hwmonN number itself changes across boots).
            var target = reader.readLink(chip + "/device");
            var device = target ? target.split("/").pop() : "";
            var files = reader.listDir(chip);
            var sensors = [];
            for (var j = 0; j < files.length; j++) {
                if (!HwmonTemp.isTempInput(files[j]))
                    continue;
                var labelFile = files[j].replace("_input", "_label");
                sensors.push({
                    "input": files[j],
                    "label": reader.read(chip + "/" + labelFile).trim()
                });
            }
            // Sensorless chips are kept: they still count for the
            // name-collision detection inside buildCatalog.
            chips.push({
                "dir": dirs[i],
                "name": name,
                "device": device,
                "sensors": sensors
            });
        }
        var catalog = HwmonTemp.buildCatalog(chips);
        // Fallback when hwmon exposes NO temperature input: some ARM
        // boards / VMs register temps only with the thermal framework.
        // On x86 the zones mirror hwmon chips, so the walk runs only on
        // an empty hwmon catalog — mixing both would double the list.
        if (catalog.length === 0)
            catalog = probe._enumerateThermalZones();
        var picker = [];
        for (var k = 0; k < catalog.length; k++) {
            picker.push({
                "id": catalog[k].id,
                "label": catalog[k].label
            });
        }
        probe._catalog = catalog;
        probe._tempSensors = picker;
    }

    // /sys/class/thermal walk — the fallback source when hwmon has no
    // temperature input at all. Decisions (id grammar, collisions,
    // sorting) live in HwmonTemp.buildThermalCatalog; here only I/O.
    function _enumerateThermalZones() {
        var base = "/sys/class/thermal";
        var dirs = reader.listDir(base);
        var zones = [];
        for (var i = 0; i < dirs.length; i++) {
            if (!/^thermal_zone\d+$/.test(dirs[i]))
                continue;
            var zone = base + "/" + dirs[i];
            var type = reader.read(zone + "/type").trim();
            if (!type)
                continue;
            var target = reader.readLink(zone + "/device");
            zones.push({
                "dir": dirs[i],
                "type": type,
                "device": target ? target.split("/").pop() : ""
            });
        }
        return HwmonTemp.buildThermalCatalog(zones);
    }

    property var _catalog: []
    property var _tempSensors: []
    property var _readings: ({})
    property int _tick: 0

    ProcReader {
        id: reader
    }

    function _refresh() {
        var readings = {};
        for (var i = 0; i < probe._catalog.length; i++) {
            var entry = probe._catalog[i];
            readings[entry.id] = HwmonTemp.parseTempCelsius(reader.read(entry.path));
        }
        probe._readings = readings;
        probe._tick++;
    }

    Component.onCompleted: probe.enumerate()

    Timer {
        // 500 ms (2 Hz) — the same cadence the backend and the Plasma
        // ksysguard daemon use, so the picker's live values step in sync
        // with the rings.
        interval: 500
        running: probe.active
        repeat: true
        triggeredOnStart: true
        onTriggered: probe._refresh()
    }
}
