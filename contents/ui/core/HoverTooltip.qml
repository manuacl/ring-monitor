import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Shared hover-driven tooltip CHROME for a ring (extracted from ProcessTooltip,
// issue #69, so the disk tooltip #68 reuses the hard-won popup mechanics instead
// of duplicating them). It owns ONLY the popup plumbing — the metric-specific
// body is injected as `contentComponent` (a ColumnLayout, loaded into the
// popup). ProcessTooltip and DiskTooltip each supply their own body.
//
// What lives here (all four cost live-debug iterations on #69 — see
// core/CLAUDE.md § "A QQC2 popup over the widget…"):
//   - Window-type popup, set GUARDED (Qt 6.8+) so it isn't clipped to the tiny
//     standalone window, yet still loads on the Qt 6.6 floor.
//   - explicit, grow-only `width` high-water mark (a Window popup doesn't adopt
//     its content's implicitWidth, and live-resampling content would yoyo it).
//   - edge-aware x/y placement (flip sides on screen overflow).
//   - a show-delay so a quick pass-over doesn't flash it (and so the owner can
//     warm up sampling DURING the delay via `samplingActive`).
//
// Why a Component/Loader and not a default-property content slot: the content
// must land in the popup's ColumnLayout, but this file's own HoverHandler MUST
// stay a child of the root (it handles the ring's hover area) — a default alias
// to the inner column would capture the HoverHandler too. The Loader keeps the
// two separate; the injected Component's bindings resolve in the CONSUMER's
// lexical scope (the standard delegate pattern), so it reads the owner's props.
//
// Inputs:
//   armed            - only the owning ring arms it; every other leaves it inert.
//   contentComponent - the body (a ColumnLayout); loaded as the popup content.
// Output:
//   samplingActive   - true the instant the pointer enters (armed-gated). The
//                      owner binds its backend sampling gate to this so data is
//                      ready by the time the (delayed) popup shows.
//   contentItem      - the loaded body root, so the consumer can expose test
//                      hooks (row count, footer text) off it.
Item {
    id: root

    property bool armed: false
    property Component contentComponent: null
    readonly property bool samplingActive: hover.hovered
    // The loaded body root (a ColumnLayout) — consumers read test hooks off it.
    readonly property alias contentItem: contentLoader.item
    // Spacing the injected body should use between its rows (so the look matches
    // across tooltips without each re-deciding).
    readonly property real contentSpacing: Kirigami.Units.smallSpacing

    property bool _show: false
    // Width high-water mark — see the popup's `width`. Grow-only so it never
    // shrinks while shown; reset on the dismiss edge so a one-off wide sample
    // doesn't pin every later hover.
    property real _maxContentWidth: 0
    // Whether the popup is actually displayed — mirrors `tip.visible`'s condition
    // (armed && _show). The mark resets on its false edge, so dismissal by EITHER
    // term re-measures next show. (Tracked rather than `tip.visible` because a
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
            showDelay.restart();
        } else {
            showDelay.stop();
            root._show = false;
        }
    }

    on_DisplayedChanged: if (!root._displayed)
        root._maxContentWidth = 0

    // Feed the grow-only mark from the loaded body's implicitWidth (the target is
    // dynamic — the Loader swaps it in once it loads — so a Connections, not a
    // direct onImplicitWidthChanged handler).
    Connections {
        target: contentLoader.item
        ignoreUnknownSignals: true
        function onImplicitWidthChanged() {
            if (contentLoader.item.implicitWidth > root._maxContentWidth)
                root._maxContentWidth = contentLoader.item.implicitWidth;
        }
    }

    QQC2.ToolTip {
        id: tip
        parent: root
        // A Window-type popup so it ISN'T clipped to the host window. `popupType`
        // is Qt 6.8+ but the floor is 6.6 — a declarative `popupType:` is a hard
        // load error on < 6.8 (takes the whole widget down, this is core/). Set it
        // imperatively + guarded. Full rationale: core/CLAUDE.md.
        Component.onCompleted: if (tip.popupType !== undefined)
            tip.popupType = QQC2.Popup.Window
        visible: root.armed && root._show
        // Content-driven width, bound explicitly (a Window popup won't auto-adopt
        // it) AND grow-only via the high-water mark (live-resampling content would
        // otherwise yoyo it). The live term sizes the first frame; the mark blocks
        // shrinking. Height stays implicit.
        width: Math.max(root._maxContentWidth, contentLoader.item ? contentLoader.item.implicitWidth : 0) + leftPadding + rightPadding
        // Edge-aware: prefer below-and-right, FLIP on screen overflow so the popup
        // stays fully visible wherever the widget sits. mapToGlobal + Screen.* are
        // plain QtQuick (no Plasma dep).
        x: {
            var gx = root.mapToGlobal(0, 0).x;
            var screenRight = root.Screen.virtualX + root.Screen.width;
            if (gx + width > screenRight)
                return root.width - width;
            return 0;
        }
        y: {
            var gy = root.mapToGlobal(0, 0).y;
            var screenBottom = root.Screen.virtualY + root.Screen.height;
            if (gy + root.height + height > screenBottom)
                return -height;
            return root.height;
        }

        contentItem: Loader {
            id: contentLoader
            sourceComponent: root.contentComponent
        }
    }
}
