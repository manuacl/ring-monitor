import QtQuick
import QtTest
import "../../contents/ui/core" as Ui
import "../../contents/ui/core/MetricsCatalog.js" as Catalog

// Tests for MainContent.qml — the portable body of the widget mounted
// as Plasma's fullRepresentation (with no Layout.preferredWidth/Height
// override), so its implicitWidth/Height drive the panel allocation
// directly. Regression guard for the "horizontal strip collapses to a
// single-ring slot" class of bug. Also covers the split-mode /
// dedicated-ring temperature bounds wiring (#164).

Item {
    id: root
    width: 800
    height: 800

    // Stub adapters with the property surface MainContent consumes.
    // No rendering is exercised — we only assert the GridLayout's
    // implicit dimensions, computed automatically from the Ring
    // delegates' Layout.preferredWidth/Height bindings.
    QtObject {
        id: themeStub
        property bool isDarkMode: false
        property color highlightColor: "#3daee9"
        property color textColor: "#000000"
    }

    QtObject {
        id: configStub
        property string enabledMetrics: "cpu,ram,gpu,disk"
        property string metricOrder: "cpu,ram,gpu,disk"
        property string orientation: "horizontal"
        property int ringSize: 180
        property int ringSpacingPercent: 7
        property bool mergeCpuTemp: false
        property bool mergeGpuTemp: false
        property string tempUnit: "celsius"
        property real textOpacity: 1.0
        property real trackOpacity: 0.2
        property real arcOpacity: 1.0
        property bool showCpuCores: false
        property string colorTheme: "system"
        property string colorMode: "system"
        property int sensorTempMinC: 20
        property int sensorTempMaxC: 60
        property int cpuTempMinC: 30
        property int cpuTempMaxC: 90
        property int gpuTempMinC: 30
        property int gpuTempMaxC: 90
        property color customColorLight: "#000000"
        property color customColorDark: "#ffffff"
        property string textColorMode: "system"
        property color customTextColorLight: "#000000"
        property color customTextColorDark: "#ffffff"
        property string diskPartitionColors: ""
        property bool splitDiskIo: false
    }

    QtObject {
        id: metricsStub
        property bool loading: false
        property var coreValues: []
        // null = availability unknown → MainContent shows the full configured
        // strip (filterByAvailable passes through). Individual tests set a
        // concrete list to exercise the drop-unavailable path.
        property var availableMetrics: null
        // Per-id return values for metricValue / metricRawTemp; tests
        // reassign the whole map (a property notify re-evaluates the
        // delegate bindings that call through these).
        property var stubValues: ({})
        property var stubRawTemps: ({})
        function metricValue(id) {
            return stubValues[id] !== undefined ? stubValues[id] : 0;
        }
        function metricTempPercent(_id) {
            return 0;
        }
        function metricRawTemp(id) {
            return stubRawTemps[id] !== undefined ? stubRawTemps[id] : 0;
        }
        // Disk-I/O surface (issue #77): a reactive snapshot + the on-screen gate
        // MainContent drives. Defaults to idle; a test mutates them.
        property var diskIo: ({
                "readBps": 0,
                "writeBps": 0,
                "combinedBps": 0,
                "readPercent": 0,
                "writePercent": 0,
                "combinedPercent": 0
            })
        property bool diskIoSamplingActive: false
        // Process sampling gate (issue #70): MainContent drives this from the
        // OR of the cpu / ram tooltip hover booleans.
        property bool processSamplingActive: false
        // Memory total/used: used by the ram tooltip footerText and the
        // formatValue closure. Zero default = sensors not yet delivered.
        property real memTotalKb: 0
        property real memUsedKb: 0
    }

    QtObject {
        id: updateCheckerStub
        property bool updateAvailable: false
    }

    Ui.MainContent {
        id: content
        theme: themeStub
        configStore: configStub
        metrics: metricsStub
        updateChecker: updateCheckerStub
    }

    TestCase {
        name: "MainContent"
        when: windowShown

        // Reset configStub to a known baseline before each test so
        // ordering between cases is irrelevant (qmltestrunner runs
        // them alphabetically by default, but we don't depend on it).
        function init() {
            configStub.orientation = "horizontal";
            configStub.enabledMetrics = "cpu,ram,gpu,disk";
            configStub.metricOrder = "cpu,ram,gpu,disk";
            configStub.ringSize = 180;
            configStub.ringSpacingPercent = 7;
            metricsStub.loading = false;
            metricsStub.availableMetrics = null;
            configStub.mergeCpuTemp = false;
            configStub.mergeGpuTemp = false;
            configStub.splitDiskIo = false;
            configStub.cpuTempMinC = 30;
            configStub.cpuTempMaxC = 90;
            metricsStub.stubValues = ({});
            metricsStub.stubRawTemps = ({});
            metricsStub.diskIoSamplingActive = false;
            metricsStub.processSamplingActive = false;
            metricsStub.memTotalKb = 0;
            metricsStub.memUsedKb = 0;
            content._cpuTooltipHovered = false;
            content._memTooltipHovered = false;
        }

        // ── Disk-I/O sampling gate (issue #77) ──────────────────────
        // MainContent drives metrics.diskIoSamplingActive from whether a
        // diskIo ring is on screen, so the backend only polls /proc/diskstats
        // (or subscribes ksysguard) while the ring is enabled.
        function test_diskIo_sampling_gate_follows_enabled_list() {
            configStub.metricOrder = "cpu,ram,diskIo";
            configStub.enabledMetrics = "cpu,ram";
            tryCompare(metricsStub, "diskIoSamplingActive", false);
            configStub.enabledMetrics = "cpu,ram,diskIo";
            tryCompare(metricsStub, "diskIoSamplingActive", true);
            configStub.enabledMetrics = "cpu,ram";
            tryCompare(metricsStub, "diskIoSamplingActive", false);
        }

        // SCENARIO (#77): an upgrading user's persisted metricOrder predates
        // diskIo (and the loadOrder merge only updates the picker, not the
        // persisted order until a drag). filterByOrder must still surface an
        // enabled id missing from the order — MainContent mergeWithCatalogs the
        // order before filtering, so enabling diskIo renders the ring without a
        // manual reorder. Without the merge the gate would stay false here.
        function test_diskIo_renders_when_enabled_but_absent_from_metricOrder() {
            configStub.metricOrder = "cpu,ram";          // stale (pre-diskIo)
            configStub.enabledMetrics = "cpu,ram,diskIo";
            tryCompare(metricsStub, "diskIoSamplingActive", true);
        }

        // QQuickLayout reflows its implicit dimensions on a deferred
        // polish pass, so the implicit isn't always settled by the
        // time the synchronous bindings have updated. tryCompare
        // polls up to 5s, which is enough for the layout to converge.

        // ── Horizontal orientation ──────────────────────────────────
        //
        // Bounding box: width = N*ringSize + (N-1)*spacing, height =
        // ringSize. The historical regression dropped the `* count`
        // multiplier on width and divided height by count, squashing
        // every ring in a Plasma horizontal panel with N>=2 metrics.

        function test_horizontal_4_metrics_default_size() {
            compare(content.count, 4);
            // 4*180 + 3*round(180*0.07) = 720 + 3*13 = 759
            tryCompare(content, "implicitWidth", 759);
            tryCompare(content, "implicitHeight", 180);
        }

        function test_horizontal_single_metric() {
            configStub.enabledMetrics = "cpu";
            tryCompare(content, "count", 1);
            // No spacing applied when N=1.
            tryCompare(content, "implicitWidth", 180);
            tryCompare(content, "implicitHeight", 180);
        }

        function test_horizontal_height_stays_ringSize() {
            // SCENARIO: PR #35 review #2 — horizontal implicitHeight
            // used to divide by count, collapsing to 80px for N=3+.
            // Height must equal ringSize regardless of count.
            configStub.enabledMetrics = "cpu,ram,gpu";
            configStub.ringSize = 240;
            tryCompare(content, "implicitHeight", 240);
        }

        // ── Vertical orientation ────────────────────────────────────
        //
        // Bounding box: width = ringSize, height = N*ringSize +
        // (N-1)*spacing. Symmetric with the horizontal case.

        function test_vertical_3_metrics() {
            configStub.orientation = "vertical";
            configStub.enabledMetrics = "cpu,ram,gpu";
            tryCompare(content, "count", 3);
            tryCompare(content, "implicitWidth", 180);
            // 3*180 + 2*round(180*0.07) = 540 + 26 = 566
            tryCompare(content, "implicitHeight", 566);
        }

        // ── Spacing % scales with ringSize ──────────────────────────
        //
        // Spacing is `round(ringSize * spacingPercent / 100)`. Doubles
        // when ringSize doubles, vanishes at 0%.

        function test_horizontal_zero_spacing() {
            configStub.ringSize = 200;
            configStub.ringSpacingPercent = 0;
            // 4*200 + 3*0 = 800
            tryCompare(content, "implicitWidth", 800);
            tryCompare(content, "implicitHeight", 200);
        }

        function test_spacing_scales_with_ringSize() {
            configStub.enabledMetrics = "cpu,ram";
            configStub.ringSize = 300;
            configStub.ringSpacingPercent = 10;  // → 30px spacing
            // 2*300 + 1*30 = 630
            tryCompare(content, "implicitWidth", 630);
        }

        // ── Availability filtering ──────────────────────────────────
        //
        // enabledList drops any enabled metric the backend doesn't report
        // in availableMetrics (GPU on a non-NVIDIA box, etc.), so the dead
        // 0% ring never renders.

        function test_unavailable_metric_dropped_from_enabledList() {
            configStub.enabledMetrics = "cpu,ram,gpu,disk";
            configStub.metricOrder = "cpu,ram,gpu,disk";
            // No gpu in the backend's available set → gpu ring drops.
            metricsStub.availableMetrics = ["cpu", "ram", "disk"];
            tryCompare(content, "count", 3);
            compare(content.enabledList, ["cpu", "ram", "disk"]);
        }

        function test_availability_filter_preserves_user_order() {
            configStub.enabledMetrics = "gpu,cpu,ram";
            configStub.metricOrder = "gpu,cpu,ram";
            metricsStub.availableMetrics = ["cpu", "ram", "gpu"];
            tryCompare(content, "count", 3);
            // Enabled order, not availableMetrics order.
            compare(content.enabledList, ["gpu", "cpu", "ram"]);
        }

        function test_warmup_keeps_full_strip_even_if_unavailable() {
            // During loading the backend hasn't resolved sensors yet — show
            // the configured strip (warming-up sweep) rather than blanking
            // rings that will become available a tick later.
            configStub.enabledMetrics = "cpu,ram,gpu,disk";
            configStub.metricOrder = "cpu,ram,gpu,disk";
            metricsStub.availableMetrics = ["cpu"];
            metricsStub.loading = true;
            tryCompare(content, "count", 4);
        }

        function test_unknown_availability_shows_full_strip() {
            // availableMetrics null (host predates the surface / not reported)
            // → filterByAvailable passes through, nothing dropped.
            configStub.enabledMetrics = "cpu,ram,gpu";
            configStub.metricOrder = "cpu,ram,gpu";
            metricsStub.availableMetrics = null;
            tryCompare(content, "count", 3);
            compare(content.enabledList, ["cpu", "ram", "gpu"]);
        }

        // ── Split-mode / dedicated-ring temperature bounds (#164) ────
        //
        // The merged cpu ring's right half-arc (splitValue) maps the raw
        // °C through Catalog.tempToPercent with the cpuTempMinC/cpuTempMaxC
        // config (via _tempBounds(modelData + "Temp")) — the backend's
        // metricTempPercent only knows the catalog 30/90 defaults, so the
        // mapping lives in MainContent. A regression to the default bounds
        // or a wrong _tempBounds key fails silently without this guard.
        // The dedicated cpuTemp ring's `value` uses the same bounds.

        // Ring delegates are the GridLayout's only visual children
        // (the Repeater parents them to content); find one by modelData.
        function ringDelegateFor(id) {
            for (var i = 0; i < content.children.length; i++) {
                var child = content.children[i];
                if (child.modelData === id)
                    return child;
            }
            return null;
        }

        function test_split_half_arc_uses_custom_temp_bounds() {
            configStub.enabledMetrics = "cpu,cpuTemp";
            configStub.metricOrder = "cpu,cpuTemp";
            configStub.mergeCpuTemp = true;
            // Non-default bounds so the 30/90 catalog defaults give a
            // different percent — tempToPercent(70, 40, 80) = 75 vs 66.67.
            configStub.cpuTempMinC = 40;
            configStub.cpuTempMaxC = 80;
            metricsStub.stubRawTemps = ({
                    "cpu": 70
                });
            tryCompare(content, "count", 1);  // cpuTemp merged into the cpu ring
            const ring = ringDelegateFor("cpu");
            verify(ring, "cpu ring delegate exists");
            tryCompare(ring, "splitMode", true);
            tryCompare(ring, "splitValue", Catalog.tempToPercent(70, 40, 80));
            verify(ring.splitValue !== Catalog.tempToPercent(70, Catalog.TEMP_MIN_C, Catalog.TEMP_MAX_C), "splitValue must not use the catalog default bounds");
        }

        function test_split_half_arc_warmup_forces_100() {
            // During loading every arc sweeps to 100% (the warming-up cue),
            // including the merged temp half — bounds are irrelevant then.
            configStub.enabledMetrics = "cpu,cpuTemp";
            configStub.metricOrder = "cpu,cpuTemp";
            configStub.mergeCpuTemp = true;
            configStub.cpuTempMinC = 40;
            configStub.cpuTempMaxC = 80;
            metricsStub.stubRawTemps = ({
                    "cpu": 70
                });
            tryCompare(content, "count", 1);
            const ring = ringDelegateFor("cpu");
            verify(ring, "cpu ring delegate exists");
            metricsStub.loading = true;
            tryCompare(ring, "splitValue", 100);
        }

        function test_dedicated_temp_ring_uses_custom_bounds() {
            // mergeCpuTemp stays false → cpuTemp renders as its own ring,
            // value = raw °C mapped with the same custom bounds.
            configStub.enabledMetrics = "cpu,cpuTemp";
            configStub.metricOrder = "cpu,cpuTemp";
            configStub.cpuTempMinC = 40;
            configStub.cpuTempMaxC = 80;
            metricsStub.stubValues = ({
                    "cpuTemp": 70
                });
            tryCompare(content, "count", 2);
            const ring = ringDelegateFor("cpuTemp");
            verify(ring, "cpuTemp ring delegate exists");
            tryCompare(ring, "value", Catalog.tempToPercent(70, 40, 80));
            verify(ring.value !== Catalog.tempToPercent(70, Catalog.TEMP_MIN_C, Catalog.TEMP_MAX_C), "value must not use the catalog default bounds");
        }

        // ── Process sampling gate: delegate-destroy-while-hovered (#70) ──

        // SCENARIO_destroy_cpu_delegate_while_hovered_releases_sampling_gate:
        // If the cpu ring is unchecked in settings while its tooltip is open,
        // the Repeater destroys the delegate. Binding destruction does NOT
        // restore its target value, so without Component.onDestruction the
        // content-scope _cpuTooltipHovered stays true and
        // metrics.processSamplingActive never goes false — background process
        // polling runs forever with no tooltip. The fix: onDestruction resets
        // the latch so the OR Binding drops to false.
        function test_SCENARIO_destroy_cpu_delegate_while_hovered_releases_sampling_gate() {
            // Baseline: cpu ring is on screen, gate is idle.
            configStub.enabledMetrics = "cpu,ram";
            configStub.metricOrder = "cpu,ram";
            tryCompare(content, "count", 2);
            tryCompare(metricsStub, "processSamplingActive", false);

            // Simulate tooltip hover-enter by directly setting the latch.
            content._cpuTooltipHovered = true;
            tryCompare(metricsStub, "processSamplingActive", true);

            // User unchecks the cpu metric → Repeater destroys the cpu delegate
            // (Component.onDestruction must reset _cpuTooltipHovered to false).
            configStub.enabledMetrics = "ram";
            tryCompare(content, "count", 1);

            // Gate must fall back to false — no permanent background sampling.
            tryCompare(metricsStub, "processSamplingActive", false);
            compare(content._cpuTooltipHovered, false);
        }

        // ── _tooltipOpenRight derivation (tooltip placement wiring) ────
        //
        // windowAnchorCorner drives which side the Window-popup tooltip opens
        // toward. Left-anchored corners ("top-left", "bottom-left") make
        // _tooltipOpenRight true so the tooltip grows into the screen.
        // Right-anchored corners and the default "" keep it false.
        //
        // These tests exercise the live QML binding; the text guard in
        // main-content-tooltip-wiring.test.mjs covers the structural wiring.

        function init_corner() {
            content.windowAnchorCorner = "";
        }

        function test_tooltipOpenRight_default_empty_is_false() {
            content.windowAnchorCorner = "";
            compare(content._tooltipOpenRight, false);
        }

        function test_tooltipOpenRight_top_left_is_true() {
            content.windowAnchorCorner = "top-left";
            compare(content._tooltipOpenRight, true);
        }

        function test_tooltipOpenRight_bottom_left_is_true() {
            content.windowAnchorCorner = "bottom-left";
            compare(content._tooltipOpenRight, true);
        }

        function test_tooltipOpenRight_top_right_is_false() {
            content.windowAnchorCorner = "top-right";
            compare(content._tooltipOpenRight, false);
        }

        function test_tooltipOpenRight_bottom_right_is_false() {
            content.windowAnchorCorner = "bottom-right";
            compare(content._tooltipOpenRight, false);
        }

        function test_tooltipOpenRight_reacts_when_corner_changes() {
            // The binding is reactive: switching from a left corner to a right
            // corner must update _tooltipOpenRight without any manual poke.
            content.windowAnchorCorner = "top-left";
            compare(content._tooltipOpenRight, true);
            content.windowAnchorCorner = "top-right";
            compare(content._tooltipOpenRight, false);
            content.windowAnchorCorner = "bottom-left";
            compare(content._tooltipOpenRight, true);
            content.windowAnchorCorner = "";
            compare(content._tooltipOpenRight, false);
        }
    }
}
