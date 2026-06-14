import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC2
import RingMonitor.Standalone
import "../../core" as Core
import "WindowPlacement.js" as WindowPlacement

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
// Compositor-specific behaviour sits in C++: the X11/XWayland EWMH
// hints in `standalone/desktop_hints.cpp` (PR C) and the native
// wlr-layer-shell bottom-layer surface in `standalone/wayland_layer_shell.cpp`
// (PR C2). `WaylandLayerShell.active` selects which path `_anchor()` takes.

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
    // Window placement: which screen corner to anchor to, plus the
    // per-axis inset (px) from that corner's edges, and which monitor to
    // land on (empty = follow the window's current screen). The cap
    // subtracts the anchored-axis margin so the window always fits between
    // the corner and the opposite edge. Defaults (top-right, 0, 0, "")
    // reproduce the historic anchor. Math lives in WindowPlacement.js.
    readonly property string _corner: configStoreAdapter.windowAnchorCorner || "top-right"
    readonly property int _marginX: (configStoreAdapter.windowMarginX !== undefined) ? configStoreAdapter.windowMarginX : 0
    readonly property int _marginY: (configStoreAdapter.windowMarginY !== undefined) ? configStoreAdapter.windowMarginY : 0
    // _targetScreen: non-null when the user has chosen a specific monitor.
    // Null means "follow the window's current screen". Re-resolves
    // automatically on monitor hot-plug/unplug via Qt.application.screens.
    readonly property var _targetScreen: WindowPlacement.pickScreen(Qt.application.screens, configStoreAdapter.windowScreen || "")
    readonly property int _screenW: _targetScreen ? _targetScreen.width : Screen.width
    readonly property int _screenH: _targetScreen ? _targetScreen.height : Screen.height
    readonly property int _screenVX: _targetScreen ? _targetScreen.virtualX : Screen.virtualX
    readonly property int _screenVY: _targetScreen ? _targetScreen.virtualY : Screen.virtualY
    readonly property int _targetWidth: Math.min(content.vertical ? _ringSize : _stripLength, _screenW - _marginX)
    readonly property int _targetHeight: Math.min(content.vertical ? _stripLength : _ringSize, _screenH - _marginY)
    // On the native-Wayland (layer-shell) path the window must stay
    // hidden until its layer surface is configured — the wlr-layer-shell
    // role is assigned when the wl_surface is created on show(), so
    // `_anchor()` configures first and flips `visible` true afterwards.
    // On X11 / XWayland (active === false) this is a constant `true`, so
    // the window shows during load exactly as before.
    visible: !WaylandLayerShell.active

    // Anchored to a user-chosen screen corner (default top-right) with a
    // per-axis margin (issue #98) — the window is always-on-bottom so any
    // Plasma panel along an anchored edge draws over the first few rows of
    // pixels; the user accepted that trade-off to maximise room.
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
        if (WaylandLayerShell.active) {
            // Native Wayland: the compositor positions the surface from
            // the layer-shell anchors + margins, so there's no x/y and
            // none of the QTBUG-57608 atomic-setGeometry gravity dance
            // (that's an X11-only problem). The corner picks which edges
            // to anchor to; margins inset from them. Configure while still
            // hidden, then show. Re-runs (slider drag, screen reconfig)
            // re-commit live — `visible = true` is then a harmless no-op.
            // When the target screen changed, hide first so the layer
            // surface is re-created on the correct wl_output. Compare by
            // name, not object identity: Window.screen and the entries of
            // Qt.application.screens can wrap the same QScreen in distinct
            // QML objects, so `!==` may hold on the same physical screen —
            // which would re-run the destroy/recreate cycle (a visible
            // blink) on every re-anchor while pinned.
            if (root._targetScreen && (!root.screen || root.screen.name !== root._targetScreen.name)) {
                root.visible = false;
                root.screen = root._targetScreen;
            }
            var spec = WindowPlacement.cornerToAnchorSpec(root._corner);
            WaylandLayerShell.configure(root, spec.left, spec.top, root._marginX, root._marginY, root._targetWidth, root._targetHeight);
            root.visible = true;
            return;
        }
        var origin = WindowPlacement.computeX11Origin(root._corner, root._screenW, root._screenH, root._targetWidth, root._targetHeight, root._marginX, root._marginY, root._screenVX, root._screenVY);
        WindowAnchor.setGeometry(root, origin.x, origin.y, root._targetWidth, root._targetHeight);
    }
    // Defer the first anchor so `applyDesktopWindowHints` (called
    // from main.cpp right after `engine.loadFromModule` returns) has
    // a chance to swap the window-type to `_NET_WM_WINDOW_TYPE_NORMAL`
    // BEFORE we issue the first setGeometry. The synchronous order is:
    //   1. engine.loadFromModule → Component.onCompleted fires
    //   2. applyDesktopWindowHints(window) sets the NORMAL type
    //   3. app.exec() — event loop starts, Qt.callLater fires
    // Calling `_anchor()` directly in step 1 issued the first
    // configure-request against Qt's default frameless override-redirect
    // window-type — exactly the gravity-shift scenario the WindowAnchor
    // pattern exists to avoid, surfacing as the brief jump on first
    // show. Qt.callLater queues it to step 3 instead.
    Component.onCompleted: Qt.callLater(_anchor)
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
        // Corner + margins shift the anchor (x/y origin) without
        // necessarily changing _target{Width,Height} — at the default
        // ringSize the screen-cap doesn't kick in, so the width/height
        // signals never fire. Listen to each directly so a placement
        // change always re-anchors.
        function on_CornerChanged() {
            Qt.callLater(root._anchor);
        }
        function on_MarginXChanged() {
            Qt.callLater(root._anchor);
        }
        function on_MarginYChanged() {
            Qt.callLater(root._anchor);
        }
        // Covers both a settings change (user picks a different monitor)
        // and hot-plug re-resolution (chosen screen disappears/reappears
        // via Qt.application.screens).
        function on_TargetScreenChanged() {
            Qt.callLater(root._anchor);
        }
    }
    // Re-anchor on display reconfig: user plugging in a 4K external,
    // KDE switching the primary, or any System Settings → Displays
    // change. Without this, the existing _target* signals won't fire
    // (at typical ringSize the screen-cap branch is inert) and the
    // window stays at the OLD monitor's right edge — now mid-screen
    // or off-screen on the new primary. `root.Screen` is the Qt
    // attached property reflecting the screen the Window currently
    // sits on; its width/height change when the screen resolution
    // changes OR when the window migrates to a different screen.
    Connections {
        target: root.Screen
        function onWidthChanged() {
            Qt.callLater(root._anchor);
        }
        function onHeightChanged() {
            Qt.callLater(root._anchor);
        }
    }
    // `onScreenChanged` fires when the Window itself moves between
    // physical screens (e.g. KDE drags it to follow the primary).
    // Width/height may stay identical across two same-resolution
    // monitors, so the above Connections wouldn't fire — this handler
    // covers that case.
    onScreenChanged: Qt.callLater(root._anchor)

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
        platform: "standalone"
    }

    // A second launch (single-instance IPC, issues #103 / #104) routes its
    // intent here instead of stacking a new window:
    //   • --open-settings → open the IN-PROCESS dialog, so the edit applies live
    //   • same-version relaunch → no-op (the widget is already visible)
    //   • different-version launch → quit so the new build takes over the socket
    Connections {
        target: SingleInstance
        function onOpenSettingsRequested() {
            settingsDialog.show();
        }
        function onSupersededRequested() {
            Qt.quit();
        }
    }

    SettingsDialog {
        id: settingsDialog
        configStore: configStoreAdapter
        theme: themeAdapter
        updateChecker: updateCheckerAdapter
        // Live availability so the picker greys metrics with no data source;
        // `null` while loading (= unknown → all enable-able) so a dialog opened
        // mid-warm-up doesn't grey rows about to resolve.
        availableMetrics: metricsAdapter.loading ? null : metricsAdapter.availableMetrics
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
        // So the ring tooltips open into the screen, not off the anchored edge.
        windowAnchorCorner: root._corner
        // The update-badge click opens the same dialog as the
        // right-click menu — discoverable nudge for users who haven't
        // found the right-click yet.
        onConfigureRequested: settingsDialog.show()
    }
}
