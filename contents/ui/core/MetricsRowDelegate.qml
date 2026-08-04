import QtQuick

MetricRow {
    id: root

    required property var controller
    required property var subOptions

    // DraggableList exposes the current row through the Loader parent.
    readonly property string currentMetricId: parent && parent.rowModel ? parent.rowModel.metricId : ""

    metricId: currentMetricId
    enabled: controller.isEnabled(currentMetricId)
    available: controller.isMetricAvailable(currentMetricId)
    extraContentEnabled: currentMetricId === "sensorTemp" || enabled
    description: controller.metricDescriptions[currentMetricId] || ""

    unit: controller.theme ? controller.theme.unit : 18
    smallSpacing: controller.theme ? controller.theme.smallSpacing : 4

    onToggled: function (on) {
        controller.setEnabled(currentMetricId, on);
    }

    extraContent: {
        if (currentMetricId === "cpu")
            return subOptions.cpuCoresToggle;
        if (currentMetricId === "cpuTemp")
            return subOptions.cpuTempMergeToggle;
        if (currentMetricId === "gpuTemp")
            return subOptions.gpuTempMergeToggle;
        if (currentMetricId === "disk")
            return subOptions.diskPartitionsPicker;
        if (currentMetricId === "diskIo")
            return subOptions.diskIoSplitToggle;
        if (currentMetricId === "sensorTemp")
            // Undefined (minimal test controllers) counts as supported;
            // only an explicit false (standalone) drops the editor.
            return controller.sensorTempSupported !== false ? subOptions.sensorTempSettings : null;
        return null;
    }
}
