import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Non-visual placement + show/hide state machine shared by the ring hover
// tooltips (ProcessTooltip #69, DiskTooltip #68). Issue #149: the popup CHROME
// (popup-type heuristic, show-delay, grow-only width mark, edge anchor) is
// identical across tooltips and was previously copy-pasted; it lives here once.
//
// What is NOT shared: the tooltip BODY. A Window-type QQC2 popup renders WRONG
// when its contentItem is a Loader (in-scene/clipped instead of floating —
// caught live on Qt 6.10, both rings) and the default-property alternative
// captures this helper's own HoverHandler. So each tooltip keeps its QQC2.ToolTip
// with an INLINE contentItem and only delegates the chrome here. See
// core/CLAUDE.md § "The body must be the popup's DIRECT contentItem".
//
// Usage (from a tooltip's root Item, anchored to fill the ring):
//   TooltipBehavior { id: behavior; armed: root.armed; openRight: root.openRight; tip: tip }
//   QQC2.ToolTip { id: tip; parent: behavior.anchorMarker
//                  visible: behavior.armed && behavior._show
//                  width: Math.max(behavior._maxContentWidth, col.implicitWidth) + ... }
Item {
    id: behavior

    // ── Inputs ───────────────────────────────────────────────────────
    // Only the owning ring arms its tooltip; every other ring leaves it inert.
    property bool armed: false
    // Which side the Window popup opens toward, so it grows into the screen:
    // left-anchored widget → openRight (grows right), right-anchored → default
    // (grows left). Only affects the Window-popup anchorMarker; see core/CLAUDE.md.
    property bool openRight: false
    // The owning tooltip's QQC2.ToolTip, injected so this helper can drive its
    // popupType. `var` (not the QQC2.ToolTip type) keeps the null-before-bind
    // window benign — every read below guards on it.
    property var tip: null

    // ── Outputs / state ──────────────────────────────────────────────
    // The parent binds the backend's sampling gate to this (armed-gated, so it
    // stays false on every non-owning ring). Sampling warms up DURING showDelay.
    readonly property bool samplingActive: hover.hovered
    // Whether the show-delay has elapsed; paired with `armed` for the tip's
    // visibility. Public (no underscore-private enforcement) so the tooltip and
    // its tests can drive it.
    property bool _show: false
    // Grow-only width high-water mark (see the tip's width bind). Reset on the
    // dismiss edge so a one-off wide sample doesn't pin every later hover.
    property real _maxContentWidth: 0
    // Mirrors the tip's visibility condition; resets the mark on its false edge so
    // dismissal by EITHER term (pointer leaves → _show false; ring disarms →
    // armed false) re-measures next show. (Tracked as a derived flag because a
    // Window-popup's visibility isn't observable headlessly — see tests/CLAUDE.md.)
    readonly property bool _displayed: behavior.armed && behavior._show

    // The 1×1 anchor the owning tooltip parents its ToolTip to.
    property alias anchorMarker: anchorMarker

    // Bumped on every hover-enter to re-trigger the placement bindings. inSceneX/Y
    // call mapToGlobal(), which is a plain function — NOT a reactive binding
    // dependency — so moving the widget (without changing the tooltip's content,
    // i.e. its width) would otherwise leave the side decision computed against the
    // ring's STALE global position (a wide tooltip then opening on the wrong side,
    // detached). The ring is settled by hover time, so re-reading then is correct.
    property int _placeNonce: 0

    anchors.fill: parent

    HoverHandler {
        id: hover
        enabled: behavior.armed
    }

    Timer {
        id: showDelay
        interval: 500
        onTriggered: behavior._show = true
    }

    onSamplingActiveChanged: {
        if (samplingActive) {
            behavior._applyPopupType();
            behavior._placeNonce++;        // re-read mapToGlobal for this show
            showDelay.restart();
        } else {
            showDelay.stop();
            behavior._show = false;
        }
    }

    // popupType is decided per-show (not once at completion): a separate-surface
    // Window popup ONLY when the host window is too small to contain the tooltip
    // in-scene (the standalone window, sized to the rings). On a full-screen host
    // (the Plasma desktop view) an in-scene popup isn't clipped AND honors the
    // tip's item-relative x/y — a Window popup ignores x/y and auto-places
    // (Qt 6.11). Set while hidden (hover-enter, 500 ms before show) so the type is
    // stable before open. Guarded: popupType is Qt 6.8+ and the floor is 6.6, so
    // touch it only when present (see core/CLAUDE.md).
    function _applyPopupType() {
        if (!behavior.tip || behavior.tip.popupType === undefined)
            return;   // Qt < 6.8 — in-scene only (fine: Plasma overlay is large)
        var win = behavior.Window.window;
        var hostTooSmall = !win || win.width < behavior.Screen.width * 0.6 || win.height < behavior.Screen.height * 0.6;
        behavior.tip.popupType = hostTooSmall ? QQC2.Popup.Window : QQC2.Popup.Item;
    }

    on_DisplayedChanged: if (!behavior._displayed)
        behavior._maxContentWidth = 0

    // In-scene (Item popup) placement, bound by each tooltip's QQC2.ToolTip as
    // `x: behavior.inSceneX; y: behavior.inSceneY`. ONLY the in-scene path uses
    // these — a Window popup ignores its own x/y and is placed by the compositor
    // via anchorMarker (so the standalone host, always a Window popup, is
    // unaffected). On Plasma (full-screen host → in-scene popup) they put the
    // tooltip beside the ring with a small gap, vertically centred on it, flipping
    // side / clamping to keep it on the current monitor. mapToGlobal + Screen.*
    // (plain QtQuick, no Plasma dep) bound the monitor; behavior fills the ring, so
    // its origin and size match the ring's.
    readonly property int _gap: Kirigami.Units.smallSpacing
    readonly property real inSceneX: {
        behavior._placeNonce;            // re-read fresh mapToGlobal on each show
        if (!behavior.tip)
            return 0;
        var w = behavior.tip.width;
        var gx = behavior.mapToGlobal(0, 0).x;
        var screenRight = behavior.Screen.virtualX + behavior.Screen.width;
        var spaceRight = screenRight - (gx + behavior.width);
        // Glue the tooltip's ring-facing edge to the ring with a small gap:
        // right side → left edge at the ring's outer edge; left side → right
        // edge at the ring's left edge (offset by THIS tooltip's own width).
        var rightX = behavior.width + _gap;
        var leftX = -w - _gap;
        // Open toward the right when this tooltip actually fits there; otherwise
        // flip left. The test is THIS tooltip's width (not a fixed reference), so
        // a tooltip never lands half-off-screen and its ring-facing edge stays
        // glued either way (on the in-scene path the popup box equals its
        // content — see each tooltip's `width` bind — so there's no surplus to
        // detach the text from the ring).
        return spaceRight >= w + _gap ? rightX : leftX;
    }
    readonly property real inSceneY: {
        behavior._placeNonce;            // re-read fresh mapToGlobal on each show
        if (!behavior.tip)
            return 0;
        var h = behavior.tip.height;
        var gy = behavior.mapToGlobal(0, 0).y;
        var screenTop = behavior.Screen.virtualY;
        var screenBottom = behavior.Screen.virtualY + behavior.Screen.height;
        // Centre a short tooltip on the ring; but a tall one (a 20-row process
        // list dwarfs the ring) would centre to ABOVE the ring top, so floor it at
        // a small top inset — never higher than just below the ring's top edge.
        var centered = (behavior.height - h) / 2;
        var yy = Math.max(Kirigami.Units.gridUnit, centered);
        if (gy + yy + h > screenBottom)
            yy = screenBottom - gy - h;             // clamp up to stay on-screen
        if (gy + yy < screenTop)
            yy = screenTop - gy;                    // clamp down to stay on-screen
        return yy;
    }

    // Anchor for the Window-popup placement. A Window-type QQC2 popup ignores its
    // own x/y on Wayland (Qt 6.11, verified live) — the compositor places it via an
    // xdg_positioner whose anchor rect is the popup's PARENT-ITEM bounding box, with
    // the popup's top-right corner landing at the anchor rect's (left, bottom) and
    // growing left+down. Parenting the tip to this 1×1 marker at the ring's
    // interior-facing top corner therefore pins the tooltip beside the ring,
    // top-aligned. The shift applies ONLY to a Window popup (which ignores its own
    // x/y, so the marker is the sole lever); an in-scene Item popup keeps the marker
    // at the ring origin so the tip's item-relative x/y flip stays correct (openRight
    // is moot there). Safe on Qt < 6.8: popupType is undefined → never Window → 0.
    Item {
        id: anchorMarker
        x: (behavior.openRight && behavior.tip && behavior.tip.popupType === QQC2.Popup.Window) ? behavior.width : 0
        y: 0
        width: 1
        height: 1
    }
}
