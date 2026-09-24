import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import "RestartPending.js" as RestartPending

// Plasma adapter: is a newer package installed than the one plasmashell
// is running (#172)? Reads the package's own metadata.json through
// plasma5support's executable engine (a QML XMLHttpRequest on file:// is
// blocked in plasmashell, see MountInfo.qml) and compares it with
// Plasmoid.metaData.version, which stays on the loaded version until the
// shell restarts.
//
// Public surface:
//   readonly property bool restartPending
//   property bool active    - when false no subprocess runs
//   property int pollMs     - re-read cadence
//   function restartPlasma()

Item {
    id: root

    readonly property bool restartPending: RestartPending.isRestartPending(root._running, root._installed)
    property bool active: true
    property int pollMs: 300000

    readonly property string _running: (Plasmoid.metaData && Plasmoid.metaData.version) || ""
    property string _installed: ""
    // This file sits at <package>/contents/ui/platforms/plasma/.
    readonly property string _command: RestartPending.readCommand(Qt.resolvedUrl("../../../../metadata.json"))

    function restartPlasma() {
        executable.connectSource(RestartPending.RESTART_COMMAND);
    }

    P5Support.DataSource {
        id: executable

        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            executable.disconnectSource(source);
            if (source === root._command && data["exit code"] === 0)
                root._installed = RestartPending.parseInstalledVersion(data["stdout"] || "");
        }
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: root.active && root._command !== ""
        triggeredOnStart: true
        onTriggered: executable.connectSource(root._command)
    }
}
