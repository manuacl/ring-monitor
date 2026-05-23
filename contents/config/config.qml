import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("Config header", "Metrics")
        icon: "view-list-icons"
        source: "configMetrics.qml"
    }
    ConfigCategory {
        name: i18nc("Config header", "Appearance")
        icon: "preferences-desktop-color"
        source: "configAppearance.qml"
    }
}
