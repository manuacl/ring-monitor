import QtQuick
import org.kde.plasma.configuration
import org.kde.plasma.plasmoid
import "../ui/core/UpdateCheck.js" as UC

ConfigModel {
    // Plasma 6's config dialog has no public "open-at-category" API
    // (verified against develop.kde.org/docs/plasma/widget/setup and
    // plasmaconfigplugin.qmltypes). The first ConfigCategory is the
    // default landing tab. To land the in-widget update badge on the
    // About page when an update is unacknowledged — without forcing
    // every other config-open to also start there — we use ConfigCategory's
    // `visible` property to swap About between first and last position
    // dynamically: first when there's an update to notify about, last
    // otherwise. Both entries point at the same source so behaviour
    // is identical, only the sidebar position changes.
    //
    // String compare won't do here: KConfig stores the GitHub tag
    // verbatim ("v0.4.0") while Plasmoid.metaData.version drops the
    // leading "v" ("0.4.0"). UC.shouldNotify parses both sides as
    // semver and only returns true when the remote is strictly newer.
    readonly property bool _hasUnseenUpdate: UC.shouldNotify(Plasmoid.metaData.version, Plasmoid.configuration.latestKnownVersion, Plasmoid.configuration.acknowledgedVersion)

    ConfigCategory {
        // Same source as the bottom-position "Release" below; the
        // label shifts to "New release" so the user immediately knows
        // what this top-of-sidebar tab is for. The bottom "Release"
        // stays available for ambient discovery when there's nothing
        // new. Both names lean into the "release info" framing rather
        // than the generic "About" — Plasma already ships a built-in
        // About page on every plasmoid (auto-rendered from
        // metadata.json), and a second "About" would be confusing.
        name: i18nc("Config header", "New release")
        icon: "system-software-update"
        source: "configAbout.qml"
        visible: _hasUnseenUpdate
    }
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
    ConfigCategory {
        name: i18nc("Config header", "Release")
        icon: "package-x-generic"
        source: "configAbout.qml"
        visible: !_hasUnseenUpdate
    }
}
