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

var METRIC_IDS = ["cpu", "ram", "swap", "gpu", "disk"];

var METRIC_LABELS = {
    cpu: "CPU",
    ram: "RAM",
    swap: "SWAP",
    gpu: "GPU",
    disk: "DISK",
};

var METRIC_SENSOR_IDS = {
    cpu:  "cpu/all/usage",
    ram:  "memory/physical/usedPercent",
    swap: "memory/swap/usedPercent",
    gpu:  "gpu/all/usage",
    disk: "disk/all/usedPercent",
};

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

function labelFor(id) {
    return METRIC_LABELS[id] || String(id).toUpperCase();
}

function sensorIdFor(id) {
    return METRIC_SENSOR_IDS[id] || "";
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
        parseCsv: parseCsv,
        filterByOrder: filterByOrder,
        labelFor: labelFor,
        sensorIdFor: sensorIdFor,
        toggleEnabled: toggleEnabled,
        valueFromSensorMap: valueFromSensorMap,
    };
}
