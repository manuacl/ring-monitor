import QtQuick
import QtQuick.Window

// Standalone root window — counterpart to the PlasmoidItem in
// contents/ui/main.qml. Frameless, transparent, fixed size for now.
//
// Scope at this stage: PR D wires the `MetricsBackend` so the
// window shows live CPU usage numbers (aggregate + per-core). It's
// a smoke-test layout, not the final visual — `Core.MainContent`
// (the ring gauges) lands once we have `Theme` and `ConfigStore`
// adapters in PR F.
//
// Compositor-specific behaviour (always-on-bottom, EWMH hints,
// click-through input region) sits in `standalone/desktop_hints.cpp`
// — see PR C.

Window {
    id: root

    title: "ring-monitor"
    width: 320
    height: 480
    visible: true

    // Frameless + transparent so the eventual ring gauges sit on the
    // wallpaper without a window chrome of their own. Plasma achieves
    // the same via `Plasmoid.backgroundHints: NoBackground` — we get
    // it explicitly here.
    //
    // WindowStaysOnBottomHint translates to `_NET_WM_STATE_BELOW`
    // under X11/XWayland. The other EWMH states the Conky-style
    // widget needs (sticky, skip-taskbar, skip-pager) are set by
    // `standalone/desktop_hints.cpp` after the window is mapped —
    // Qt has no direct flag for them.
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint
    color: "transparent"

    MetricsBackend {
        id: metrics
    }

    // Smoke-test readout. Replaced by `Core.MainContent` (the ring
    // gauges) once Theme + ConfigStore adapters exist (PR F). For now
    // we just need the numbers visible to confirm `/proc/stat` reads
    // are landing and the deltas compute correctly.
    Rectangle {
        anchors.fill: parent
        color: "#332266aa"
        border.color: "white"
        border.width: 2

        Column {
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "ring-monitor"
                color: "white"
                font.pixelSize: 24
                font.weight: Font.Light
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: metrics.loading ? "loading…" : "CPU: " + metrics.metricValue("cpu").toFixed(1) + "%"
                color: "white"
                font.pixelSize: 18
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: metrics.loading ? "" : "cores: " + metrics.coreValues.map(function (v) {
                    return v.toFixed(0);
                }).join(", ")
                color: "white"
                opacity: 0.8
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                width: root.width - 40
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
