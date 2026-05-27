import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Tests for MainContent.qml — the portable body of the widget mounted
// as Plasma's fullRepresentation (with no Layout.preferredWidth/Height
// override), so its implicitWidth/Height drive the panel allocation
// directly. Regression guard for the "horizontal strip collapses to a
// single-ring slot" class of bug.

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
        property color customColorLight: "#000000"
        property color customColorDark: "#ffffff"
        property string textColorMode: "system"
        property color customTextColorLight: "#000000"
        property color customTextColorDark: "#ffffff"
    }

    QtObject {
        id: metricsStub
        property bool loading: false
        property var coreValues: []
        function metricValue(_id) { return 0; }
        function metricTempPercent(_id) { return 0; }
        function metricRawTemp(_id) { return 0; }
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
    }
}
