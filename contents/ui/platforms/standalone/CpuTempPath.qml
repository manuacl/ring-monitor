import QtQuick
import "CpuTempDiscovery.js" as CpuTemp

// Resolves the sysfs file holding the CPU temperature, extracted from
// `MetricsBackend.qml` to keep that file under the 500-line cap (same
// split as GpuSampler / BatterySampler / HwmonTempSensors).
//
// Pure I/O glue: it walks /sys/class/hwmon and falls back to
// /sys/class/thermal, and every "which entry is the CPU" decision is
// deferred to the pure CpuTempDiscovery helpers. Stateless — the caller
// owns the resolved path and the bounded warm-up retry, because the
// retry window is a property of the polling tick, not of the walk.
//
// `reader` is the ProcReader injected by the parent (DIP: this leaf
// takes what it needs rather than reaching for a global).

Item {
    id: resolver

    property var reader

    // The sysfs file to read each tick, or "" when no CPU sensor exists.
    function resolve() {
        var fromHwmon = resolver._resolveFromHwmon();
        if (fromHwmon)
            return fromHwmon;
        return resolver._resolveFromThermalZones();
    }

    function _resolveFromHwmon() {
        var base = "/sys/class/hwmon";
        var dirs = resolver.reader.listDir(base);
        var entries = [];
        for (var i = 0; i < dirs.length; i++) {
            var name = resolver.reader.read(base + "/" + dirs[i] + "/name").trim();
            if (name)
                entries.push({
                    "dir": dirs[i],
                    "name": name
                });
        }
        var cpuDir = CpuTemp.pickCpuHwmonDir(entries);
        if (!cpuDir)
            return "";
        var chip = base + "/" + cpuDir;
        var files = resolver.reader.listDir(chip);
        var sensors = [];
        for (var j = 0; j < files.length; j++) {
            if (!CpuTemp.isTempInput(files[j]))
                continue;
            var labelFile = files[j].replace("_input", "_label");
            sensors.push({
                "input": files[j],
                "label": resolver.reader.read(chip + "/" + labelFile).trim()
            });
        }
        var input = CpuTemp.pickCpuTempInput(sensors);
        return input ? chip + "/" + input : "";
    }

    function _resolveFromThermalZones() {
        var base = "/sys/class/thermal";
        var dirs = resolver.reader.listDir(base);
        var zones = [];
        for (var i = 0; i < dirs.length; i++) {
            if (!/^thermal_zone\d+$/.test(dirs[i]))
                continue;
            zones.push({
                "dir": dirs[i],
                "type": resolver.reader.read(base + "/" + dirs[i] + "/type").trim()
            });
        }
        var zone = CpuTemp.pickCpuThermalZone(zones);
        return zone ? base + "/" + zone + "/temp" : "";
    }
}
