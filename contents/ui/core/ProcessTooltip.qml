import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Hover-driven "top processes" tooltip for a ring (issue #69). Generic over the
// ranked metric: the CPU ring wires it for CPU%, and the companion RAM-ring
// tooltip can reuse it as-is by injecting a memory `title` / `formatValue` /
// `footerText` (Open/Closed — no edit here). Dropped in as a child of the ring
// in MainContent; it:
//   - exposes `samplingActive` (true the instant the pointer enters) so the
//     parent binds the backend's sampling gate to it — sampling warms up DURING
//     the show-delay below, so data is ready by the time the tooltip appears;
//   - shows the QQC2.ToolTip only after a short delay, so a quick mouse
//     pass-over doesn't flash it (or spin up enumeration pointlessly).
//
// Presentational only beyond that: it renders the ranked list (name + dimmed
// ·PID + a right-aligned value the parent formats) plus an optional footer.
// Pure QtQuick + Kirigami — no platform imports, no metric-specific logic.
//
// The popup chrome (Window-popup guard, grow-only width high-water mark,
// edge-aware placement, show-delay) is DUPLICATED in DiskTooltip (#68), NOT
// shared: a Window-type QQC2 popup renders WRONG with a Loader contentItem, so
// the body must be the popup's DIRECT contentItem. Keep the two in sync. See
// core/CLAUDE.md § "The body must be the popup's DIRECT contentItem".
Item {
    id: root

    // ── Inputs ───────────────────────────────────────────────────────
    // Only the owning ring arms the tooltip; every other ring leaves it inert.
    property bool armed: false
    // Ranked [{pid, name, ...}] from backend.topProcesses.
    property var processes: []
    // Header line, e.g. qsTr("Top processes — CPU").
    property string title: ""
    // Per-row right-column formatter: function(process) → display string. The
    // parent injects the metric (CPU%: p => formatCpuPercent(p.cpuPercent)).
    property var formatValue: null
    // Footer line (empty → no footer). The parent formats it (e.g. load avg).
    property string footerText: ""
    // Which side of the ring the (Window-popup) tooltip opens toward. The parent sets
    // it from the widget's screen edge so the tooltip grows into the screen, not off it:
    // a left-anchored widget opens RIGHT, a right-anchored one opens LEFT (default).
    // Only affects the Window-popup placement (see anchorMarker); the in-scene Plasma
    // path keeps its own screen-overflow flip below.
    property bool openRight: false

    // ── Output ───────────────────────────────────────────────────────
    // The parent binds the backend's sampling gate to this (gated on its ring).
    // hover.enabled is armed-gated, so this stays false on every other ring.
    readonly property bool samplingActive: hover.hovered

    // Test hooks (underscore = internal).
    readonly property alias _rowCount: rowRepeater.count
    readonly property alias _footerText: footerLabel.text
    property bool _show: false
    // Width high-water mark — see the popup's `width` binding. Grow-only, so the
    // popup never shrinks while shown.
    property real _maxContentWidth: 0
    // Whether the popup is actually displayed — mirrors `tip.visible`'s condition
    // (armed && _show). The mark resets on its false edge, so dismissal by EITHER
    // term (pointer leaves → _show false; ring disarms → armed false) re-measures
    // next show. (We track this derived flag rather than `tip.visible` because a
    // Window-popup's visibility isn't observable headlessly — see tst_/CLAUDE.md.)
    readonly property bool _displayed: root.armed && root._show

    anchors.fill: parent

    HoverHandler {
        id: hover
        enabled: root.armed
    }

    Timer {
        id: showDelay
        interval: 500
        onTriggered: root._show = true
    }

    onSamplingActiveChanged: {
        if (samplingActive) {
            root._applyPopupType();
            showDelay.restart();
        } else {
            showDelay.stop();
            root._show = false;
        }
    }

    // popupType is decided per-show (not once at completion) because it depends on
    // the host window, which must be a separate-surface Window popup ONLY when it's
    // too small to contain the tooltip in-scene (the standalone window, sized to the
    // rings). On a full-screen host (the Plasma desktop view) an in-scene popup isn't
    // clipped AND honors the item-relative x/y above — a Window popup ignores x/y and
    // auto-places (Qt 6.11), so it can't be positioned beside/top-aligned. Set while
    // hidden (hover-enter, 500 ms before show) so the type is stable before open.
    function _applyPopupType() {
        if (tip.popupType === undefined)
            return;   // Qt < 6.8 — in-scene only (fine: Plasma overlay is large)
        var win = root.Window.window;
        var hostTooSmall = !win || win.width < root.Screen.width * 0.6 || win.height < root.Screen.height * 0.6;
        tip.popupType = hostTooSmall ? QQC2.Popup.Window : QQC2.Popup.Item;
    }

    // Reset the width high-water mark on dismiss, so a one-off wide sample doesn't
    // pin the popup wide for every later hover; the next show re-measures.
    on_DisplayedChanged: if (!root._displayed)
        root._maxContentWidth = 0

    // Anchor for the Window-popup placement. A Window-type QQC2 popup ignores its
    // own x/y on Wayland (verified live, Qt 6.11) — the compositor places it via an
    // xdg_positioner whose anchor rect is the popup's PARENT-ITEM bounding box, with
    // the popup's top-right corner landing at the anchor rect's (left, bottom) and
    // growing left+down. Parenting to a 1×1 marker at the ring's top-left therefore
    // pins the tooltip's top-right corner to the ring's top-left corner (beside the
    // ring, top-aligned) instead of the default bottom-left. The in-scene (Plasma)
    // path is unaffected: the marker sits at the ring origin, so the item-relative
    // x/y below resolve to the same scene point as parenting to the ring did.
    Item {
        id: anchorMarker
        // Anchor at the ring's interior-facing top corner; the compositor grows the
        // popup into the screen from there (it flips gravity at the screen edge). Widget
        // right-anchored → anchor at the ring's top-left, popup grows left. Widget
        // left-anchored (openRight) → anchor at the ring's top-right, popup grows right.
        // Either way the tooltip ends up beside the ring, top-aligned. The shift applies
        // ONLY to a Window popup (which ignores its own x/y, so the marker is the sole
        // lever); an in-scene Item popup keeps the marker at the ring origin so the
        // item-relative x/y flip below stays correct (openRight is moot there, and the
        // flip handles screen overflow). Safe on Qt < 6.8: popupType is undefined →
        // never equals Window → marker stays at 0.
        x: (root.openRight && tip.popupType === QQC2.Popup.Window) ? root.width : 0
        y: 0
        width: 1
        height: 1
    }

    QQC2.ToolTip {
        id: tip
        parent: anchorMarker
        // Hover-driven only: visibility is `armed && _show` below, never auto-close.
        // Paired with the transparent-for-input popup window (see contentItem): an
        // input-grabbing Window popup would steal the pointer from the ring's
        // HoverHandler and flicker (QTBUG-38084); a non-auto-closing, input-transparent
        // popup leaves hover with the ring, so show/hide stays purely hover-gated.
        closePolicy: QQC2.Popup.NoAutoClose
        // A Window-type popup so it ISN'T clipped to the host window: the
        // standalone window is sized to the rings (tiny), so an in-scene (Item)
        // popup — the pre-6.8 default — gets cropped to that rect and only a
        // sliver shows. A Window popup is a separate surface the compositor keeps
        // on screen.
        //
        // `popupType` is Qt 6.8+, but the project floor is Qt 6.6 (CMakeLists) —
        // and a DECLARATIVE `popupType:` is a hard load error on < 6.8 ("Cannot
        // assign to non-existent property"), which would take down the whole
        // widget (this is in core/, loaded by both hosts). So set it imperatively
        // + guarded: on Qt ≥ 6.8 → Window popup; on 6.6/6.7 the component still
        // loads with the in-scene default — fine on Plasma's large overlay,
        // clipped on the small standalone window (the AppImage bundles Qt ≥ 6.8,
        // so shipped standalone gets the Window popup). See core/CLAUDE.md.
        // popupType set per-show via root._applyPopupType() (Window only on a small
        // host window; in-scene on a full-screen host so x/y are honored).
        visible: root.armed && root._show
        // Content-driven width, bound explicitly, AND grow-only. A Window-type
        // popup does NOT auto-adopt its contentItem's implicitWidth the way an
        // in-scene popup does, so the window collapsed to a sliver and names
        // elided to "k…" (PR #99 live test) — hence the explicit bind. But the
        // ranked list churns every sample (rows enter/leave, the widest name
        // changes), so binding straight to col.implicitWidth made the popup
        // yoyo wider/narrower tick-to-tick. So col feeds a high-water mark
        // (_maxContentWidth, grow-only — a narrower sample is ignored), reset on
        // hide so a one-off wide sample doesn't pin every later hover. We bind to
        // max(mark, live implicitWidth): the mark blocks shrinking, while the
        // live term sizes the FIRST frame — the mark starts at 0 and the tracker
        // only updates it on a *change*, so a bare-mark bind rendered the popup
        // one-char-wide until the next layout tick. No loop: a Layout's
        // implicitWidth is its natural content size, independent of the width we
        // assign back. The name's maximumWidth caps how far one long name can
        // stretch it. Height stays implicit.
        width: Math.max(root._maxContentWidth, col.implicitWidth) + leftPadding + rightPadding
        // Edge-aware placement: beside the ring (right) and top-aligned with it,
        // but FLIP to the opposite side when it would run off the screen, so the
        // tooltip stays fully visible wherever the widget sits (the standalone
        // anchors top-RIGHT by default, where growing right overflows).
        // mapToGlobal gives the ring's on-screen position; Screen.virtual* +
        // Screen.width/height bound the current monitor. (No Plasma dep — these
        // are plain QtQuick.) Re-evaluates when the tooltip's width/height
        // settle after layout.
        // In-scene popups honor item-relative x/y (a Window popup ignores them and
        // auto-places — see _applyPopupType). Beside the ring, top-aligned, flip on
        // screen overflow. mapToGlobal only feeds the overflow test, not the value.
        x: {
            var gx = root.mapToGlobal(0, 0).x;
            var screenRight = root.Screen.virtualX + root.Screen.width;
            if (gx + root.width + width > screenRight)
                return -width;              // overflow right → left of the ring
            return root.width;              // default → right of the ring
        }
        y: {
            var gy = root.mapToGlobal(0, 0).y;
            var screenBottom = root.Screen.virtualY + root.Screen.height;
            if (gy + height > screenBottom)
                return Math.min(0, screenBottom - gy - height);  // clamp up to stay on-screen
            return 0;                       // default → top aligned with the ring
        }

        contentItem: ColumnLayout {
            id: col
            spacing: Kirigami.Units.smallSpacing
            // When this content is reparented into a separate Window popup, mark that
            // window transparent-for-input. A normal Window popup grabs the pointer on
            // open (xdg_popup grab on Wayland) and steals it from the ring's
            // HoverHandler → hover drops → the popup hides → reopens → flicker
            // (QTBUG-38084). The tooltip is non-interactive, so dropping its input lets
            // the pointer stay with the ring and the show/hide stays stable. Guarded to
            // the separate popup window (in-scene popups share the host window). Works on
            // Wayland (flags re-read after creation); on X11/XWayland flags are fixed at
            // creation and there's no QML hook before Qt maps the popup, so a faint
            // first-show flash remains (the 500 ms show-delay absorbs most of it) — a
            // full X11 fix needs the flag set pre-map in the C++ platform layer.
            onWindowChanged: {
                var w = col.Window.window;
                if (w && w !== root.Window.window)
                    w.flags = w.flags | Qt.WindowTransparentForInput;
            }
            // Feed the grow-only width high-water mark; never let it shrink.
            onImplicitWidthChanged: if (implicitWidth > root._maxContentWidth)
                root._maxContentWidth = implicitWidth

            QQC2.Label {
                text: root.title
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                Layout.fillWidth: true
                Layout.bottomMargin: Kirigami.Units.smallSpacing
            }

            Repeater {
                id: rowRepeater
                model: root.processes

                delegate: RowLayout {
                    id: procRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.Label {
                        text: procRow.modelData.name
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        // Cap so one long name can't stretch the tooltip absurdly
                        // wide; comm names are ≤15 chars so this rarely bites.
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                    }
                    QQC2.Label {
                        text: "·" + procRow.modelData.pid
                        opacity: 0.45
                        font: Kirigami.Theme.smallFont
                    }
                    QQC2.Label {
                        text: root.formatValue ? root.formatValue(procRow.modelData) : ""
                        horizontalAlignment: Text.AlignRight
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
                    }
                }
            }

            // Placeholder for the ~one-tick warm-up before the first sample.
            QQC2.Label {
                visible: rowRepeater.count === 0
                text: qsTr("Gathering…")
                opacity: 0.6
            }

            Kirigami.Separator {
                visible: root.footerText.length > 0
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }

            QQC2.Label {
                id: footerLabel
                visible: root.footerText.length > 0
                text: root.footerText
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }
    }
}
