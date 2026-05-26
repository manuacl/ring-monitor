import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC2
import RingMonitor.Standalone
import "../../core" as Core

// Standalone root window — counterpart to the PlasmoidItem in
// contents/ui/main.qml. Frameless, transparent, sized to the rings'
// implicit content size.
//
// Scope at this stage (PR F2): the three platform adapters
// (ConfigStore via Qt.labs.settings, Theme + ThemedIcon as Kirigami
// passthroughs) are in place, so Core.MainContent renders the actual
// rings. SettingsDialog wraps the same three core bodies the Plasma
// side reuses — opened via the right-click context menu or the
// update-available badge.
//
// Compositor-specific behaviour (always-on-bottom, EWMH hints,
// click-through input region) sits in `standalone/desktop_hints.cpp`
// — see PR C.

Window {
    id: root

    title: "ring-monitor"
    // Window dimensions are computed HERE (not via MainContent's
    // implicit) because the GridLayout's auto-implicit derived from
    // its children's natural sizes would overpower an `implicitWidth`
    // set on the layout itself. Computing on the parent Window side
    // gives us authoritative control.
    //
    // `ringSize` is the per-ring side length. Rings are square; the
    // window's extent along the stack axis is `count` rings plus the
    // GridLayout's row/column spacings. The perpendicular extent
    // equals `ringSize`.
    //
    //   vertical:   width = ringSize
    //               height = ringSize × count + (count-1) × spacing
    //   horizontal: width  = ringSize × count + (count-1) × spacing
    //               height = ringSize
    //
    // Both dimensions capped at the screen size so a wild slider /
    // metric-count combo never pushes the window off-screen.
    readonly property int _ringSize: Math.max(80, (configStoreAdapter.ringSize || 180))
    readonly property int _ringSpacingPercent: (configStoreAdapter.ringSpacingPercent !== undefined) ? configStoreAdapter.ringSpacingPercent : 7
    readonly property int _gridSpacing: Math.round(_ringSize * _ringSpacingPercent / 100)
    readonly property int _stripLength: _ringSize * content.count + (content.count - 1) * _gridSpacing
    // Screen-edge inset (px). Subtracts from the available cap so the
    // window fits within `Screen - 2*margin` along each axis and the
    // anchor leaves `margin` pixels of wallpaper between the rings and
    // the closest screen edge (top + right).
    readonly property int _windowMargin: (configStoreAdapter.windowMargin !== undefined) ? configStoreAdapter.windowMargin : 0
    readonly property int _targetWidth: Math.min(content.vertical ? _ringSize : _stripLength, Screen.width - 2 * _windowMargin)
    readonly property int _targetHeight: Math.min(content.vertical ? _stripLength : _ringSize, Screen.height - 2 * _windowMargin)
    visible: true

    // Top-right anchored at the very edge of the screen (y = 0) — the
    // window is always-on-bottom so any Plasma panel at the top draws
    // over the first few rows of pixels; the user accepted this
    // trade-off ("toujours à 0px du haut") to maximise vertical room.
    //
    // Geometry has to be applied as one atomic xcb_configure_window
    // (X|Y|WIDTH|HEIGHT mask + StaticGravity) — see QTBUG-57608 and
    // window_anchor.h. Per-property setters (which is what QML
    // `x:`/`y:`/`width:`/`height:` bindings emit) generate multiple
    // ConfigureRequests that KWin processes with NorthWestGravity,
    // gravity-shifting the window between each request → the
    // slider-driven resize ended up off-anchor (top edge above y=0).
    // We deliberately DO NOT bind `width:`/`height:` (which would
    // issue setWidth/setHeight per-property setters before our
    // callback fires, producing a visible gravity-shift flicker). The
    // _target* properties hold the desired size; `_anchor()` reads
    // them and pushes everything in one atomic setGeometry call via
    // `WindowAnchor.setGeometry` → QWindow::setGeometry(QRect), the
    // only Qt entry point that sends a single ConfigureRequest with
    // StaticGravity. Qt.callLater coalesces consecutive slider
    // firings so we send exactly one update per tick.
    function _anchor() {
        WindowAnchor.setGeometry(root, Screen.width - root._targetWidth - root._windowMargin, root._windowMargin, root._targetWidth, root._targetHeight);
    }
    Component.onCompleted: _anchor()
    // Connections (rather than `on_TargetWidthChanged:`) — handlers
    // for underscore-prefixed properties are awkward to spell in QML
    // (`on_TargetWidthChanged`, mixing leading underscore + capital).
    // A `Connections { target: root }` block stays readable and lets
    // both inputs share one slot.
    Connections {
        target: root
        function on_TargetWidthChanged() {
            Qt.callLater(root._anchor);
        }
        function on_TargetHeightChanged() {
            Qt.callLater(root._anchor);
        }
        // `_windowMargin` shifts the anchor (x/y origin) without
        // necessarily changing _target{Width,Height} — at the default
        // ringSize the screen-cap doesn't kick in, so the width/height
        // signals never fire. Listen to the margin directly so a
        // slider move always re-anchors.
        function on_WindowMarginChanged() {
            Qt.callLater(root._anchor);
        }
    }

    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint
    color: "transparent"

    // ── Platform adapters ───────────────────────────────────────────
    // IDs are *Adapter-suffixed to avoid shadowing the same-named
    // properties on MainContent (same name-resolution trap as in
    // contents/ui/main.qml — Plasma side). Documented in
    // ../../core/CLAUDE.md § "Don't reuse a property name as an id".
    Theme {
        id: themeAdapter
    }

    ConfigStore {
        id: configStoreAdapter
    }

    MetricsBackend {
        id: metricsAdapter
    }

    Core.UpdateChecker {
        id: updateCheckerAdapter
        configStore: configStoreAdapter
    }

    SettingsDialog {
        id: settingsDialog
        configStore: configStoreAdapter
        theme: themeAdapter
        updateChecker: updateCheckerAdapter
    }

    // ── Right-click context menu ────────────────────────────────────
    //
    // MouseArea only captures right-click so left-click on the
    // (future) interactive parts of the rings stays free. The
    // popup() coordinates are local to the MouseArea, which fills
    // the window — Menu positions itself at the cursor.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: mouse => contextMenu.popup()
    }

    QQC2.Menu {
        id: contextMenu
        QQC2.MenuItem {
            text: qsTr("Settings…")
            onTriggered: settingsDialog.show()
        }
        QQC2.MenuSeparator {}
        QQC2.MenuItem {
            text: qsTr("Quit")
            onTriggered: Qt.quit()
        }
    }

    // ── Portable body ───────────────────────────────────────────────
    Core.MainContent {
        id: content
        // Edge-to-edge: rings render at 100% of the window width — no
        // padding. anchors.fill (instead of centerIn) so the rings
        // honour the capped Window size; when implicit would exceed
        // Screen, the GridLayout delegates downsize via their
        // Layout.fillWidth / fillHeight constraints.
        anchors.fill: parent
        theme: themeAdapter
        configStore: configStoreAdapter
        metrics: metricsAdapter
        updateChecker: updateCheckerAdapter
        // The update-badge click opens the same dialog as the
        // right-click menu — discoverable nudge for users who haven't
        // found the right-click yet.
        onConfigureRequested: settingsDialog.show()
    }
}
