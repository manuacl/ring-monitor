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
            showDelay.restart();
        } else {
            showDelay.stop();
            root._show = false;
        }
    }

    // Reset the width high-water mark on dismiss, so a one-off wide sample doesn't
    // pin the popup wide for every later hover; the next show re-measures.
    on_DisplayedChanged: if (!root._displayed)
        root._maxContentWidth = 0

    QQC2.ToolTip {
        id: tip
        parent: root
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
        Component.onCompleted: if (tip.popupType !== undefined)
            tip.popupType = QQC2.Popup.Window
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
        // Edge-aware placement: prefer below-and-right of the ring, but FLIP to
        // the opposite side when that side would run off the screen, so the
        // tooltip stays fully visible wherever the widget sits (the standalone
        // anchors top-RIGHT by default, where growing right/down overflows).
        // mapToGlobal gives the ring's on-screen position; Screen.virtual* +
        // Screen.width/height bound the current monitor. (No Plasma dep — these
        // are plain QtQuick.) Re-evaluates when the tooltip's width/height
        // settle after layout.
        x: {
            var gx = root.mapToGlobal(0, 0).x;
            var screenRight = root.Screen.virtualX + root.Screen.width;
            if (gx + width > screenRight)
                return root.width - width;  // overflow right → right-align (grow left)
            return 0;                       // default → left-align (grow right)
        }
        y: {
            var gy = root.mapToGlobal(0, 0).y;
            var screenBottom = root.Screen.virtualY + root.Screen.height;
            if (gy + root.height + height > screenBottom)
                return -height;             // overflow bottom → above the ring
            return root.height;             // default → below the ring
        }

        contentItem: ColumnLayout {
            id: col
            spacing: Kirigami.Units.smallSpacing
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
