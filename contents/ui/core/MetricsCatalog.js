// Static catalog of metrics + pure helpers for the order/enable CSV state.
//
// What lives here:
//   - METRIC_IDS         — canonical display order (also the default)
//   - METRIC_LABELS      — short labels (no i18n: they're abbreviations)
//   - METRIC_SENSOR_IDS  — ksysguard sensor IDs per metric
//   - parseCsv / filterByOrder — turn the cfg_* CSV strings into clean arrays
//
// What does NOT live here:
//   - i18n descriptions (those need i18n() at the call site for xgettext
//     extraction; they stay inline in the QML page that displays them)
//   - Sensor *instances* (Sensors.Sensor is a QML type, so they must be
//     declared in QML — main.qml exposes a sensorMap to map id → instance)
//
// Dual-loaded by QML (`import "MetricsCatalog.js" as Catalog`) and Node
// (via the module.exports shim at the bottom). No `.pragma library` for
// Node compatibility.

// Canonical metric order. Temperature variants sit next to their
// usage counterpart so fresh installs see related rings adjacent.
var METRIC_IDS = ["cpu", "cpuTemp", "ram", "swap", "gpu", "gpuTemp", "disk"];

var METRIC_LABELS = {
    cpu: "CPU",
    cpuTemp: "CPU T",
    ram: "RAM",
    swap: "SWAP",
    gpu: "GPU",
    gpuTemp: "GPU T",
    disk: "DISKS",
};

// METRIC_SENSOR_IDS maps the catalog id to its ksysguard sensor. For
// the temperature metrics the value is a raw °C reading — MainContent
// runs it through tempToPercent for the sweep angle and convertTemp
// for the display text.
var METRIC_SENSOR_IDS = {
    cpu:      "cpu/all/usage",
    cpuTemp:  "cpu/all/averageTemperature",
    ram:      "memory/physical/usedPercent",
    swap:     "memory/swap/usedPercent",
    gpu:      "gpu/all/usage",
    gpuTemp:  "gpu/gpu1/temperature",
    disk:     "disk/all/usedPercent",
};

// Metric ids whose `metricValue` returns a raw °C reading rather than
// a 0-100 percent. Callers must apply tempToPercent before driving the
// ring sweep, and convertTemp before displaying the value.
var TEMP_METRIC_IDS = { cpuTemp: true, gpuTemp: true };

function isTempMetric(id) {
    return TEMP_METRIC_IDS[id] === true;
}

// Optional temperature sensors per metric. ksysguard exposes
// `cpu/all/averageTemperature` but no `gpu/all/temperature` aggregate —
// the per-GPU sensor `gpu/gpu1/temperature` is used on the dev machine
// (same hardcoding pattern as the per-core CPU usage sensors).
var METRIC_TEMP_SENSOR_IDS = {
    cpu: "cpu/all/averageTemperature",
    gpu: "gpu/gpu1/temperature",
};

// Range in °C mapped to 0-100% on the temperature half-arc. 30° → 0%
// (idle), 90° → 100% (thermal alarm territory for most consumer CPUs).
// Keep these as constants — a configurable range is a future option
// (see docs/adding-a-metric.md "non-percent sensors" caveat).
//
// Note: the range stays in Celsius regardless of the user's display
// unit choice. The sensor reports Celsius (kernel-side), and the
// thermal perception "idle / hot" is universal; only the *displayed*
// value gets converted to °F when requested. See convertTemp below.
var TEMP_MIN_C = 30;
var TEMP_MAX_C = 90;

// Match Qt's QLocale::MeasurementSystem enum values. Mirrored here so
// the pure module stays loadable from Node tests (where Qt is absent).
var MEASUREMENT_METRIC = 0;
var MEASUREMENT_IMPERIAL_US = 1;
var MEASUREMENT_IMPERIAL_UK = 2;

function parseCsv(csv) {
    if (!csv) return [];
    return String(csv).split(",").filter(function(x) { return x; });
}

function filterByOrder(ids, order) {
    var set = {};
    for (var i = 0; i < ids.length; i++) set[ids[i]] = true;
    var out = [];
    for (var j = 0; j < order.length; j++) {
        if (set[order[j]]) out.push(order[j]);
    }
    return out;
}

// Order-preserving intersection of `enabledIds` with `availableIds` —
// drops any enabled metric the backend isn't currently reporting a data
// source for (GPU on a non-NVIDIA box, swap on a swapless host, an
// unresolved CPU-temp sensor). Keeps the `enabledIds` order so the strip
// layout is unchanged for the surviving rings.
//
// `availableIds` null/undefined means "availability unknown" (the backend
// hasn't reported yet, or a host that predates the availableMetrics
// surface): pass `enabledIds` through untouched so the warm-up keeps
// showing the configured rings instead of blanking the widget.
function filterByAvailable(enabledIds, availableIds) {
    if (!availableIds) return enabledIds.slice();
    var set = {};
    for (var i = 0; i < availableIds.length; i++) set[availableIds[i]] = true;
    var out = [];
    for (var j = 0; j < enabledIds.length; j++) {
        if (set[enabledIds[j]]) out.push(enabledIds[j]);
    }
    return out;
}

// Append any catalog metric id missing from `currentIds`, preserving
// the existing order. Used in MetricsBody.loadOrder so that a release
// introducing a new metric (e.g. cpuTemp / gpuTemp in 0.4) auto-shows
// up in existing users' config list without an explicit migration.
function mergeWithCatalog(currentIds) {
    var seen = {};
    for (var i = 0; i < currentIds.length; i++) seen[currentIds[i]] = true;
    var out = currentIds.slice();
    for (var j = 0; j < METRIC_IDS.length; j++) {
        if (!seen[METRIC_IDS[j]]) out.push(METRIC_IDS[j]);
    }
    return out;
}

// Drop cpuTemp / gpuTemp from the displayed list when the user asked
// to merge them into the cpu / gpu ring AND both metrics are enabled
// (no base ring → no merge target → temp metric stays as a full ring).
function applyMergedTempMode(enabledIds, mergeCpuTemp, mergeGpuTemp) {
    var has = {};
    for (var i = 0; i < enabledIds.length; i++) has[enabledIds[i]] = true;
    var cpuMerged = mergeCpuTemp && has.cpu && has.cpuTemp;
    var gpuMerged = mergeGpuTemp && has.gpu && has.gpuTemp;
    if (!cpuMerged && !gpuMerged) return enabledIds.slice();
    var out = [];
    for (var j = 0; j < enabledIds.length; j++) {
        var id = enabledIds[j];
        if (cpuMerged && id === "cpuTemp") continue;
        if (gpuMerged && id === "gpuTemp") continue;
        out.push(id);
    }
    return out;
}

// Whether the cpu (or gpu) ring should render in split mode given the
// current enabled list + merge toggles. Mirrors the filter logic in
// applyMergedTempMode — kept as a separate helper so MainContent's
// delegate can ask the question per-ring without re-deriving the set.
// Natural-order comparator so cpu10 sorts after cpu9 (default string
// sort would put cpu10 between cpu1 and cpu2).
function _naturalCompareSensorIds(a, b) {
    var ra = /(\d+)/.exec(a);
    var rb = /(\d+)/.exec(b);
    if (ra && rb) {
        var na = parseInt(ra[1], 10);
        var nb = parseInt(rb[1], 10);
        if (na !== nb) return na - nb;
    }
    if (a < b) return -1;
    if (a > b) return 1;
    return 0;
}

// Classify a flat list of ksysguard sensor ids into the variable-arity
// buckets the backend cares about. Pure — the Plasma walk in
// MetricsBackend.qml feeds the discovered ids in, this function says
// which are cpu cores, gpu temps, etc.
//
// The remaining catalog metrics (cpu/all/usage, memory/*, disk/*,
// cpu/all/averageTemperature) have stable single ids and stay
// hardcoded in METRIC_SENSOR_IDS.
function classifyDiscoveredIds(allIds) {
    var cores = [];
    var gpuTemps = [];
    var gpuUsages = [];
    var diskParts = [];
    for (var i = 0; i < allIds.length; i++) {
        var id = allIds[i];
        if (/^cpu\/cpu\d+\/usage$/.test(id)) cores.push(id);
        else if (/^gpu\/gpu\d+\/temperature$/.test(id)) gpuTemps.push(id);
        else if (/^gpu\/gpu\d+\/usage$/.test(id)) gpuUsages.push(id);
        // Per-filesystem usage. ksysguard keys these by UUID
        // (disk/<uuid>/usedPercent) and only emits them for mounted
        // filesystems — physical disks (disk/sda/...) have no usedPercent.
        // The middle segment is restricted to id chars ([A-Za-z0-9_-]) so
        // the regex SUBSCRIPTION node the SensorTreeModel also exposes —
        // `disk/(?!all).*/usedPercent`, the matcher behind the disk/all
        // aggregate — is NOT mistaken for a real partition. Exclude the
        // disk/all aggregate too (kept as a static sensor).
        else if (/^disk\/[A-Za-z0-9_-]+\/usedPercent$/.test(id) && id !== "disk/all/usedPercent") diskParts.push(id);
    }
    cores.sort(_naturalCompareSensorIds);
    gpuTemps.sort(_naturalCompareSensorIds);
    gpuUsages.sort(_naturalCompareSensorIds);
    diskParts.sort(_naturalCompareSensorIds);
    return {
        coreUsageIds: cores,
        gpuTempIds: gpuTemps,
        gpuUsageIds: gpuUsages,
        diskPartitionUsageIds: diskParts,
    };
}

function isSplitForBase(baseId, enabledIds, mergeCpuTemp, mergeGpuTemp) {
    var has = {};
    for (var i = 0; i < enabledIds.length; i++) has[enabledIds[i]] = true;
    if (baseId === "cpu") return Boolean(mergeCpuTemp && has.cpu && has.cpuTemp);
    if (baseId === "gpu") return Boolean(mergeGpuTemp && has.gpu && has.gpuTemp);
    return false;
}

function labelFor(id) {
    return METRIC_LABELS[id] || String(id).toUpperCase();
}

function sensorIdFor(id) {
    return METRIC_SENSOR_IDS[id] || "";
}

function tempSensorIdFor(id) {
    return METRIC_TEMP_SENSOR_IDS[id] || "";
}

// Map a raw °C reading onto 0-100% for the temperature half-arc.
// Out-of-range inputs clamp; non-finite → 0.
function tempToPercent(tempC, min, max) {
    if (min === undefined) min = TEMP_MIN_C;
    if (max === undefined) max = TEMP_MAX_C;
    if (!isFinite(tempC)) return 0;
    if (max <= min) return 0;
    var pct = (tempC - min) * 100 / (max - min);
    if (pct < 0) return 0;
    if (pct > 100) return 100;
    return pct;
}

// Resolve the user's "auto" / "celsius" / "fahrenheit" preference into
// the effective unit, using the system's QLocale.measurementSystem
// when "auto". Only Imperial-US uses Fahrenheit for temperature; UK
// has been metric for temperatures since ~1965, so ImperialUKSystem
// → celsius like the rest of the metric world.
function resolveTempMode(userMode, measurementSystem) {
    if (userMode === "celsius") return "celsius";
    if (userMode === "fahrenheit") return "fahrenheit";
    return measurementSystem === MEASUREMENT_IMPERIAL_US ? "fahrenheit" : "celsius";
}

// Convert an internal °C value to the user-facing { value, unit } pair.
// Non-finite input falls back to 0 in the requested unit.
function convertTemp(celsius, mode) {
    var unit = mode === "fahrenheit" ? "°F" : "°C";
    if (!isFinite(celsius)) return { value: 0, unit: unit };
    if (mode === "fahrenheit") return { value: celsius * 9 / 5 + 32, unit: unit };
    return { value: celsius, unit: unit };
}

// Return a new array with `id` toggled on/off. Preserves the order of the
// other ids and appends `id` at the end when enabling.
function toggleEnabled(currentIds, id, on) {
    var out = [];
    for (var i = 0; i < currentIds.length; i++) {
        if (currentIds[i] !== id) out.push(currentIds[i]);
    }
    if (on) out.push(id);
    return out;
}

// Read a sensor's value out of the id→Sensor map main.qml maintains.
// Returns 0 for unknown ids or for sensors that haven't reported yet
// (Sensors.Sensor leaves .value at undefined/NaN before the first tick).
// Pure logic — tested standalone, then used by `main.qml.metricValue()`.
function valueFromSensorMap(sensorMap, id) {
    if (!sensorMap) return 0;
    var s = sensorMap[id];
    if (!s) return 0;
    var v = s.value;
    if (v === undefined || v === null) return 0;
    if (typeof v === "number" && isNaN(v)) return 0;
    return v;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        METRIC_IDS: METRIC_IDS,
        METRIC_LABELS: METRIC_LABELS,
        METRIC_SENSOR_IDS: METRIC_SENSOR_IDS,
        METRIC_TEMP_SENSOR_IDS: METRIC_TEMP_SENSOR_IDS,
        TEMP_METRIC_IDS: TEMP_METRIC_IDS,
        isTempMetric: isTempMetric,
        mergeWithCatalog: mergeWithCatalog,
        applyMergedTempMode: applyMergedTempMode,
        classifyDiscoveredIds: classifyDiscoveredIds,
        isSplitForBase: isSplitForBase,
        TEMP_MIN_C: TEMP_MIN_C,
        TEMP_MAX_C: TEMP_MAX_C,
        MEASUREMENT_METRIC: MEASUREMENT_METRIC,
        MEASUREMENT_IMPERIAL_US: MEASUREMENT_IMPERIAL_US,
        MEASUREMENT_IMPERIAL_UK: MEASUREMENT_IMPERIAL_UK,
        parseCsv: parseCsv,
        filterByOrder: filterByOrder,
        filterByAvailable: filterByAvailable,
        labelFor: labelFor,
        sensorIdFor: sensorIdFor,
        tempSensorIdFor: tempSensorIdFor,
        tempToPercent: tempToPercent,
        resolveTempMode: resolveTempMode,
        convertTemp: convertTemp,
        toggleEnabled: toggleEnabled,
        valueFromSensorMap: valueFromSensorMap,
    };
}
