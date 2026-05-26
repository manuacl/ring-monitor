import QtQuick
import QtQuick.Window

// Standalone root window — counterpart to the PlasmoidItem in
// contents/ui/main.qml. Frameless, transparent, fixed size for now.
//
// Scope at this stage (PR B1): a coloured placeholder so we can
// confirm the window opens, takes its compositor flags, and renders
// QML. The actual metric body (Core.MainContent) lands in PR D once
// the standalone MetricsBackend can feed it.
//
// All compositor-specific behaviour (always-on-bottom, layer-shell
// anchoring, EWMH hints, click-through input region) is intentionally
// absent here — PR C wires it through `flags:` and native window
// handle attributes per platform.

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

    // Placeholder body. Replaced by `Core.MainContent` in PR D once
    // the standalone MetricsBackend exists. The dashed border and
    // text make it obvious this is the standalone build (not a
    // misrendered Plasma widget) when running both side-by-side.
    Rectangle {
        anchors.fill: parent
        color: "#332266aa"
        border.color: "white"
        border.width: 2

        Column {
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "ring-monitor"
                color: "white"
                font.pixelSize: 24
                font.weight: Font.Light
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "standalone (B1 placeholder)"
                color: "white"
                opacity: 0.7
                font.pixelSize: 12
            }
        }
    }
}
