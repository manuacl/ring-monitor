import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import "ReorderLogic.js" as Logic
import "MetricsCatalog.js" as Catalog
import "DiskMetrics.js" as DiskMetrics
import "ColorThemes.js" as ColorThemes

// Body of the Metrics config page. Owns the reorderable list, the internal
// ListModel, and the per-row UI (CheckBox + drag handle + sub-toggles).
//
// Bidirectional state is exposed as plain QML properties; the wrapper
// (configMetrics.qml) bridges them to Plasma's cfg_* magic via `property
// alias` declarations — the body never touches Plasma APIs directly.
//
// i18n strings use qsTr() rather than Plasma's i18n() — see
// docs/plasma-isolation/plan.md for the rationale (works on both hosts).

ColumnLayout {
    id: body

    // ── Adapter input ───────────────────────────────────────────────
    property var theme
    // Platform-injected ColorPicker Component (same contract as
    // AppearanceBody.colorPickerComponent), drives the per-partition swatch.
    property Component colorPickerComponent
    // The actual shared ring color (resolved from colorTheme/colorMode/custom in
    // the config wrapper, which has both the Theme adapter and the color config).
    // Seeds a partition's "inherited" swatch so the preview matches the real ring
    // even when colorTheme != system (issue #67). Falls back to the theme
    // highlight until a wrapper injects the resolved value.
    property color sharedRingColor: body.theme ? body.theme.highlightColor : ColorThemes.DEFAULT_HIGHLIGHT
    // Metric ids with a live data source, injected by the platform wrapper.
    // null = unknown → every row enable-able (see isMetricAvailable).
    property var availableMetrics: null
    // Discovered disk partitions ([{id, label}]) injected by the platform
    // wrapper (Plasma: configMetrics via DiskPartitions; standalone:
    // SettingsDialog via the backend). Drives the per-partition checkboxes
    // under the disk row.
    property var diskPartitions: []
    // [{id,label}] of currently-mounted REMOVABLE filesystems (auto-show set). The picker
    // uses it to know which rows are governed by the opt-out list vs the manual selection.
    property var removablePartitions: []
    // The backend's default partition selection (standalone: the $HOME-bearing
    // filesystem; Plasma: [] = aggregate). When the user hasn't selected
    // anything yet, the picker seeds enabledPartitions with this so the
    // default renders as a real, checked, editable row instead of showing the
    // widget's $HOME ring with every checkbox unchecked.
    property var defaultPartitionIds: []

    // ── Bridged via aliases in the wrapper (cfg_metricOrder ↔ body.metricOrderCsv, etc.) ──
    property string metricOrderCsv: ""
    property string enabledMetricsCsv: ""
    property string enabledPartitionsCsv: ""
    property string partitionOrderCsv: ""
    // Removable partitions opted out of auto-show (CSV of UUIDs), bridged to cfg_partitionOptOut.
    property string partitionOptOutCsv: ""
    // UUID→label JSON cache so a disconnected partition shows its last-known
    // volume name on the stale row instead of a bare UUID. Staged seam
    // (issue #132): discovery merges land in _stagedLabelsJson (the display
    // copy stalePartitionList reads); _flushLabelCache persists it from
    // user-gesture paths only. Rule: core/CLAUDE.md § cfg-bridged properties.
    property string partitionLabelsJson: ""
    property string _stagedLabelsJson: ""
    onPartitionLabelsJsonChanged: _stagedLabelsJson = partitionLabelsJson
    // JSON partition-id→custom-color map, bridged to cfg_diskPartitionColors;
    // no entry = inherit the shared ring color (issue #67). Same staged seam
    // as the label cache above (issue #134): the housekeeping prune lands in
    // _stagedColorsJson (the display copy partitionColor reads), flushed by
    // _flushColorMap on user gesture.
    property string partitionColorsJson: ""
    property string _stagedColorsJson: ""
    onPartitionColorsJsonChanged: _stagedColorsJson = partitionColorsJson
    property bool showCpuCores: false
    property bool mergeCpuTemp: false
    property bool mergeGpuTemp: false
    property bool splitDiskIo: false
    property string tempUnit: "auto"
    property string sensorTempId: ""
    property string sensorTempLabel: "SENSOR"
    property int sensorTempMinC: 20
    property int sensorTempMaxC: 60
    property int cpuTempMinC: 30
    property int cpuTempMaxC: 90
    property int gpuTempMinC: 30
    property int gpuTempMaxC: 90
    // sensorTemp picker feed (issue #164), injected by the platform
    // wrapper: the discovered Celsius sensors ([{id, label}]) plus the
    // live resolution state of the configured id. Plain inputs — not
    // cfg-bridged, so the staged-seam rules above don't apply; empty /
    // false / NaN on platforms without discovery.
    property var tempSensors: []
    property bool sensorTempResolved: false
    property real sensorTempLive: NaN

    // ── Internal — the displayed order is a ListModel built from metricOrderCsv ──
    ListModel {
        id: orderModel
    }

    // Parallel model for the disk partition reorder list (built from
    // partitionOrderCsv merged with the discovered diskPartitions).
    ListModel {
        id: partitionOrderModel
    }

    // Descriptions are owned by the body so it stays self-contained.
    // The wrapper does not need to know about per-metric copy.
    readonly property var metricDescriptions: ({
            cpu: qsTr("Overall processor usage"),
            cpuTemp: qsTr("CPU temperature"),
            ram: qsTr("Physical memory used"),
            swap: qsTr("Swap usage"),
            gpu: qsTr("GPU usage"),
            gpuTemp: qsTr("GPU temperature"),
            disk: qsTr("Disk space per selected partition"),
            diskIo: qsTr("Disk read/write throughput"),
            sensorTemp: qsTr("Custom hardware temperature")
        })

    function currentOrder() {
        const arr = [];
        for (let i = 0; i < orderModel.count; i++)
            arr.push(orderModel.get(i).metricId);
        return arr;
    }

    function loadOrder() {
        orderModel.clear();
        // mergeWithCatalog appends any catalog id missing from the persisted
        // CSV — a release adding new metrics populates existing users' config
        // list without a manual migration (e.g. 0.4 → cpuTemp / gpuTemp).
        const ids = Catalog.mergeWithCatalog(Catalog.parseCsv(body.metricOrderCsv));
        for (let i = 0; i < ids.length; i++) {
            orderModel.append({
                metricId: ids[i]
            });
        }
    }

    function commitOrder() {
        body.metricOrderCsv = currentOrder().join(",");
    }

    function isEnabled(id) {
        return Catalog.parseCsv(body.enabledMetricsCsv).indexOf(id) !== -1;
    }

    // Availability unknown (null) → every metric is enable-able. Otherwise
    // a metric is available only if the backend lists it.
    function isMetricAvailable(id) {
        return !body.availableMetrics || body.availableMetrics.indexOf(id) !== -1;
    }

    function setEnabled(id, on) {
        body.enabledMetricsCsv = Catalog.toggleEnabled(Catalog.parseCsv(body.enabledMetricsCsv), id, on).join(",");
        // Mirror of the auto-enable behaviour in the merge checkboxes:
        // disabling the base ring removes its merge target, so drop the
        // merge toggle too instead of leaving a misleading checkmark.
        if (!on && id === "cpu" && body.mergeCpuTemp)
            body.mergeCpuTemp = false;
        if (!on && id === "gpu" && body.mergeGpuTemp)
            body.mergeGpuTemp = false;
        _flushStaged();
    }

    function _removableIds() {
        return (body.removablePartitions || []).map(function (p) {
            return p.id;
        });
    }

    function isPartitionEnabled(id) {
        return DiskMetrics.isPartitionShown(id, body._removableIds(), Catalog.parseCsv(body.enabledPartitionsCsv), Catalog.parseCsv(body.partitionOptOutCsv));
    }

    function setPartitionEnabled(id, on) {
        if (body._removableIds().indexOf(id) !== -1) {
            // Removable: governed by the opt-out list, never the manual selection.
            if (Catalog.parseCsv(body.enabledPartitionsCsv).indexOf(id) !== -1)
                body.enabledPartitionsCsv = Catalog.toggleEnabled(Catalog.parseCsv(body.enabledPartitionsCsv), id, false).join(",");
            // on=true → remove from opt-out (auto-show), on=false → add to opt-out (hide).
            body.partitionOptOutCsv = Catalog.toggleEnabled(Catalog.parseCsv(body.partitionOptOutCsv), id, !on).join(",");
        } else {
            body.enabledPartitionsCsv = Catalog.toggleEnabled(Catalog.parseCsv(body.enabledPartitionsCsv), id, on).join(",");
        }
        _flushStaged();
    }

    // Per-partition custom ring color (issue #67). "" = no override → inherit
    // the shared ring color. The setters are user gestures → flush immediately.
    function partitionColor(id) {
        return DiskMetrics.colorFor(body._stagedColorsJson, id);
    }
    function setPartitionColor(id, color) {
        body._stagedColorsJson = DiskMetrics.withColor(body._stagedColorsJson, id, color);
        _flushStaged();
    }
    function clearPartitionColor(id) {
        body._stagedColorsJson = DiskMetrics.withoutColor(body._stagedColorsJson, id);
        _flushStaged();
    }

    // Bound the staged color map so a custom color can't outlive its
    // partition. Keep-set = enabled ∪ order ∪ discovered; only an entry whose
    // partition is BOTH gone AND unreferenced is pruned — full rationale:
    // docs/components.md § MetricsBody.
    function _refreshColorMap() {
        // Prune only once discovery settles (same gate as stalePartitionList):
        // at Component.onCompleted diskPartitions is still [], so the keep-set
        // would lack its discovered half and drop colors (issue #134).
        if (!body.partitionsReady || !body.diskPartitions || body.diskPartitions.length === 0)
            return;
        const discovered = body.diskPartitions.map(function (p) {
            return p.id;
        });
        body._stagedColorsJson = body._settledMap(body._stagedColorsJson, DiskMetrics.pruneMap(body._stagedColorsJson, body._referencedPartitionIds().concat(discovered)));
    }

    // Persist the staged color map; see _flushLabelCache for the rationale.
    function _flushColorMap() {
        _refreshColorMap();
        body.partitionColorsJson = body._settledMap(body.partitionColorsJson, body._stagedColorsJson);
    }

    // One flush point for every staged map (labels + colors); user-gesture only.
    function _flushStaged() {
        _flushLabelCache();
        _flushColorMap();
    }

    function currentPartitionOrder() {
        const arr = [];
        for (let i = 0; i < partitionOrderModel.count; i++)
            arr.push(partitionOrderModel.get(i).partId);
        return arr;
    }

    // Rebuild the partition reorder model: saved order first, then
    // newly-discovered partitions appended alphabetically (the default).
    function loadPartitionOrder() {
        partitionOrderModel.clear();
        const ordered = DiskMetrics.orderPartitions(body.partitionOrderCsv, body.diskPartitions || []);
        for (let i = 0; i < ordered.length; i++) {
            partitionOrderModel.append({
                partId: ordered[i].id,
                partLabel: ordered[i].label
            });
        }
    }

    function commitPartitionOrder() {
        body.partitionOrderCsv = currentPartitionOrder().join(",");
        _flushStaged();
    }

    // Wrapper-injected "discovery settled" gate. Default false → no stale
    // rows until a wrapper confirms readiness (Plasma populates diskPartitions
    // incrementally; the trash action is destructive). Full rationale:
    // docs/components.md § MetricsBody.
    property bool partitionsReady: false

    // Configured partitions that are no longer discovered (unplugged disk).
    // Empty until discovery is ready (see partitionsReady) or nothing is
    // discovered yet.
    readonly property var stalePartitionList: {
        if (!body.partitionsReady || !body.diskPartitions || body.diskPartitions.length === 0)
            return [];
        return DiskMetrics.stalePartitions(body.enabledPartitionsCsv, body.partitionOrderCsv, body.diskPartitions, body._stagedLabelsJson);
    }

    // The set of ids whose label is worth caching: everything currently
    // selected or ordered (so an unplugged one keeps its friendly name).
    function _referencedPartitionIds() {
        return Catalog.parseCsv(body.enabledPartitionsCsv).concat(Catalog.parseCsv(body.partitionOrderCsv));
    }

    // Settle a recomputed UUID→string map against the current value: treat the
    // unset "" as equal to "{}" and an unchanged map as a no-op, so a
    // housekeeping recompute (or a flush with nothing staged) never produces
    // a spurious write. Shared by the label-cache and color-map paths.
    function _settledMap(current, next) {
        if (next === current || (next === "{}" && current === ""))
            return current;
        return next;
    }

    function _refreshLabelCache() {
        body._stagedLabelsJson = body._settledMap(body._stagedLabelsJson, DiskMetrics.mergeLabelCache(body._stagedLabelsJson, body.diskPartitions || [], body._referencedPartitionIds()));
    }

    // Persist the staged cache. User-gesture paths only — the page is already
    // legitimately dirty there, so the cache write rides along (issue #132).
    function _flushLabelCache() {
        _refreshLabelCache();
        body.partitionLabelsJson = body._settledMap(body.partitionLabelsJson, body._stagedLabelsJson);
    }

    // Trash action on a stale row: drop the id from the selection, the order,
    // the label cache, and any custom color. The explicit clearPartitionColor
    // is load-bearing, NOT redundant with the prune: the enabled-change hook
    // refreshes while the id is still in partitionOrderCsv (still referenced),
    // the order-change hook doesn't refresh colors, and the prune is gated off
    // when nothing is discovered. It also flushes both staged maps, and runs
    // after both CSV writes — the label refresh sees the id unreferenced.
    function removeStalePartition(id) {
        body.enabledPartitionsCsv = Catalog.toggleEnabled(Catalog.parseCsv(body.enabledPartitionsCsv), id, false).join(",");
        body.partitionOrderCsv = Catalog.toggleEnabled(Catalog.parseCsv(body.partitionOrderCsv), id, false).join(",");
        clearPartitionColor(id);
    }

    // Seed the selection with the backend default when nothing is chosen yet,
    // so the picker shows what the widget actually renders as a checked row.
    // Empty selection = always the default; to hide it, disable the metric.
    function _seedDefaultIfEmpty() {
        if (body.enabledPartitionsCsv === "" && body.defaultPartitionIds && body.defaultPartitionIds.length > 0)
            body.enabledPartitionsCsv = body.defaultPartitionIds.join(",");
    }

    onMetricOrderCsvChanged: loadOrder()
    onPartitionOrderCsvChanged: loadPartitionOrder()
    onDiskPartitionsChanged: {
        loadPartitionOrder();
        _seedDefaultIfEmpty();
        _refreshLabelCache();
        _refreshColorMap();
    }
    onEnabledPartitionsCsvChanged: {
        _refreshLabelCache();
        _refreshColorMap();
    }
    onDefaultPartitionIdsChanged: _seedDefaultIfEmpty()
    Component.onCompleted: {
        loadOrder();
        loadPartitionOrder();
        _seedDefaultIfEmpty();
        _refreshLabelCache();
        _refreshColorMap();
    }

    Layout.fillWidth: true
    spacing: body.theme ? body.theme.smallSpacing : 4

    QQC2.Label {
        text: qsTr("Toggle metrics to display. Drag a row by the handle on the left to reorder.")
        wrapMode: Text.WordWrap
        opacity: 0.7
        Layout.fillWidth: true
    }

    DraggableList {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        model: orderModel
        rowHeight: body.theme ? body.theme.unit * 2 : 36

        smallSpacing: body.theme ? body.theme.smallSpacing : 4
        iconSize: body.theme ? body.theme.iconSize : 16
        highlightColor: body.theme ? body.theme.highlightColor : "#3daee9"
        backgroundColor: body.theme ? body.theme.backgroundColor : "#1e1e1e"

        rowContent: Component {
            MetricsRowDelegate {
                controller: body
                subOptions: metricSubOptions
            }
        }

        onReordered: function (from, to) {
            // Apply the move through the pure helper, then sync the
            // ListModel + commit back to the CSV (which propagates to
            // cfg_metricOrder via the wrapper's alias).
            const next = Logic.applyMove(body.currentOrder(), from, to);
            orderModel.clear();
            for (let i = 0; i < next.length; i++) {
                orderModel.append({
                    metricId: next[i]
                });
            }
            body.commitOrder();
        }
    }

    MetricSubOptions {
        id: metricSubOptions
        controller: body
    }

    TemperatureUnitSettings {
        id: temperatureUnitSettings

        Layout.fillWidth: true
        Layout.topMargin: body.theme ? body.theme.smallSpacing : 4

        visible: body.isEnabled("cpuTemp") || body.isEnabled("gpuTemp") || body.isEnabled("sensorTemp")

        tempUnit: body.tempUnit

        onTempUnitEdited: function (value) {
            body.tempUnit = value;
        }
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _orderModel: orderModel
    readonly property alias _partitionOrderModel: partitionOrderModel
    readonly property alias _list: list
    // The temp-unit radios carry objectNames (tempUnit*Radio) — tests
    // reach them via findChild(body, …), per tests/CLAUDE.md's
    // leaf-control hook rule.
}
