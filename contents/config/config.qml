import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18nc("Config header", "Apparence")
        icon: "preferences-desktop-color"
        source: "configAppearance.qml"
    }
}
