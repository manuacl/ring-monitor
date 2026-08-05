import org.kde.kcmutils as KCM

// Shared base for every Plasma config page (KDE bug 484541): Plasma
// sets every cfg_<key> — plus the auto-generated cfg_<key>Default for
// "Reset to defaults" — on every page it opens, and a page missing one
// logs "Setting initial properties failed" per key per open. This base
// declares the full main.xml key set ONCE; each page extends it and
// overrides only the keys it actually bridges with `property alias`
// (overriding a base `property var` with an alias is legal QML).
// Adding a config key = one entry pair here + the owning page's alias,
// instead of a placeholder edit on every other page.
// Guarded by tests/config-pages-placeholders.test.mjs (key set derived
// from main.xml; every page must extend this base). Rationale:
// docs/config-dialog.md § Gotcha 1.
KCM.SimpleKCM {
    property var cfg_metricOrder
    property var cfg_metricOrderDefault
    property var cfg_enabledMetrics
    property var cfg_enabledMetricsDefault
    property var cfg_enabledPartitions
    property var cfg_enabledPartitionsDefault
    property var cfg_partitionOrder
    property var cfg_partitionOrderDefault
    property var cfg_partitionOptOut
    property var cfg_partitionOptOutDefault
    property var cfg_partitionLabels
    property var cfg_partitionLabelsDefault
    property var cfg_diskPartitionColors
    property var cfg_diskPartitionColorsDefault
    property var cfg_showCpuCores
    property var cfg_showCpuCoresDefault
    property var cfg_mergeCpuTemp
    property var cfg_mergeCpuTempDefault
    property var cfg_mergeGpuTemp
    property var cfg_mergeGpuTempDefault
    property var cfg_splitDiskIo
    property var cfg_splitDiskIoDefault
    property var cfg_sensorTempId
    property var cfg_sensorTempIdDefault

    property var cfg_sensorTempLabel
    property var cfg_sensorTempLabelDefault

    property var cfg_sensorTempMinC
    property var cfg_sensorTempMinCDefault

    property var cfg_sensorTempMaxC
    property var cfg_sensorTempMaxCDefault

    property var cfg_cpuTempMinC
    property var cfg_cpuTempMinCDefault

    property var cfg_cpuTempMaxC
    property var cfg_cpuTempMaxCDefault

    property var cfg_gpuTempMinC
    property var cfg_gpuTempMinCDefault

    property var cfg_gpuTempMaxC
    property var cfg_gpuTempMaxCDefault

    property var cfg_orientation
    property var cfg_orientationDefault
    property var cfg_ringSize
    property var cfg_ringSizeDefault
    property var cfg_ringSpacingPercent
    property var cfg_ringSpacingPercentDefault
    property var cfg_windowAnchorCorner
    property var cfg_windowAnchorCornerDefault
    property var cfg_windowMarginX
    property var cfg_windowMarginXDefault
    property var cfg_windowMarginY
    property var cfg_windowMarginYDefault
    property var cfg_textOpacity
    property var cfg_textOpacityDefault
    property var cfg_trackOpacity
    property var cfg_trackOpacityDefault
    property var cfg_arcOpacity
    property var cfg_arcOpacityDefault
    property var cfg_colorTheme
    property var cfg_colorThemeDefault
    property var cfg_colorMode
    property var cfg_colorModeDefault
    property var cfg_customColorLight
    property var cfg_customColorLightDefault
    property var cfg_customColorDark
    property var cfg_customColorDarkDefault
    property var cfg_textColorMode
    property var cfg_textColorModeDefault
    property var cfg_customTextColorLight
    property var cfg_customTextColorLightDefault
    property var cfg_customTextColorDark
    property var cfg_customTextColorDarkDefault
    property var cfg_tempUnit
    property var cfg_tempUnitDefault
    property var cfg_checkForUpdatesEnabled
    property var cfg_checkForUpdatesEnabledDefault
    property var cfg_lastUpdateCheck
    property var cfg_lastUpdateCheckDefault
    property var cfg_latestKnownVersion
    property var cfg_latestKnownVersionDefault
    property var cfg_acknowledgedVersion
    property var cfg_acknowledgedVersionDefault
}
