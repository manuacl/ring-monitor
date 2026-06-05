import QtQuick
import "platforms/plasma" as Platform
import "core" as Core
import "core/ColorThemes.js" as ColorThemes

// Plasma-side wrapper for the Metrics config page. All of the
// rendering, the orderModel, and the toggle/reorder logic live in
// MetricsBody.qml — this file's only job is to bridge Plasma's cfg_*
// magic property convention to the body's plain properties via
// `property alias` declarations. The KDE-484541 placeholders for keys
// handled on other pages come from the PlaceholderKCM base.

Platform.PlaceholderKCM {
    id: page

    // ── Bidirectional bridge: cfg_<key> ↔ body.<property> ────────────
    property alias cfg_metricOrder: body.metricOrderCsv
    property alias cfg_enabledMetrics: body.enabledMetricsCsv
    property alias cfg_enabledPartitions: body.enabledPartitionsCsv
    property alias cfg_partitionOrder: body.partitionOrderCsv
    property alias cfg_partitionOptOut: body.partitionOptOutCsv
    property alias cfg_partitionLabels: body.partitionLabelsJson
    property alias cfg_diskPartitionColors: body.partitionColorsJson
    property alias cfg_showCpuCores: body.showCpuCores
    property alias cfg_mergeCpuTemp: body.mergeCpuTemp
    property alias cfg_mergeGpuTemp: body.mergeGpuTemp
    property alias cfg_splitDiskIo: body.splitDiskIo
    property alias cfg_tempUnit: body.tempUnit

    // ColorPicker is platform-specific (Plasma wraps KQuickControls.ColorButton);
    // the body takes it as a Component so it stays free of any Platform import —
    // same injection as configAppearance.qml. Used by the per-partition disk
    // color swatch in the picker.
    Component {
        id: colorPickerComponent
        Platform.ColorPicker {}
    }

    // ID is *Adapter-suffixed to avoid shadowing MetricsBody's
    // `theme` property — same QML name-resolution trap as in main.qml.
    Platform.Theme {
        id: themeAdapter
    }

    // The KCM page can't read the running widget's backend, so it runs its
    // own as the partition + availability source for the picker (no Timer on
    // the Plasma backend → cheap probe). See docs/components.md § MetricsBackend.
    Platform.MetricsBackend {
        id: metricsAdapter
        // Run the findmnt poll while the dialog is open so the picker can gate
        // out partitions ksysguard still lists after unmount (#58 frozen tree).
        removableTrackingActive: true
    }

    Core.MetricsBody {
        id: body
        theme: themeAdapter
        colorPickerComponent: colorPickerComponent
        // Resolve the actual shared ring color so a partition's "inherited"
        // swatch previews what the ring really shows. The color config lives on
        // the Appearance page, but KDE bug 484541 means Plasma sets every cfg_*
        // on this page too — so the placeholders above carry the live values.
        sharedRingColor: ColorThemes.resolveSharedRingColor(page.cfg_colorTheme || "system", page.cfg_colorMode || "auto", themeAdapter.isDarkMode, themeAdapter.highlightColor, page.cfg_customColorLight || ColorThemes.DEFAULT_HIGHLIGHT, page.cfg_customColorDark || ColorThemes.DEFAULT_HIGHLIGHT)
        // Mount-gated list (not the raw availablePartitions): an unplugged disk
        // ksysguard still lists (#58 frozen tree) drops from the selectable
        // picker and, if still configured, surfaces as a greyed stale row.
        diskPartitions: metricsAdapter.mountedAvailablePartitions
        removablePartitions: metricsAdapter.removablePartitions
        // Gate the destructive stale-row removal on the adapter's debounced
        // discovery signal — the SensorTreeModel walk populates incrementally.
        partitionsReady: metricsAdapter.partitionsReady
        // `null` (= unknown → all enable-able) during warm-up, else the real
        // list — without the gate the freshly-spun-up backend would grey every
        // row until its Sensors resolve. Mirrors MainContent's loading gate.
        availableMetrics: metricsAdapter.loading ? null : metricsAdapter.availableMetrics
    }
}
