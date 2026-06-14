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
//     the show-delay, so data is ready by the time the tooltip appears;
//   - shows the QQC2.ToolTip only after a short delay, so a quick mouse
//     pass-over doesn't flash it (or spin up enumeration pointlessly).
//
// Presentational only beyond that: it renders the ranked list (name + dimmed
// ·PID + a right-aligned value the parent formats) plus an optional footer.
// Pure QtQuick + Kirigami — no platform imports, no metric-specific logic.
//
// The popup CHROME (popup-type heuristic, show-delay, grow-only width mark, edge
// anchor) lives in the shared TooltipBehavior helper (#149). The BODY stays here
// as the popup's DIRECT contentItem — a Window-type popup renders wrong with a
// Loader contentItem, so the body is never factored out. See core/CLAUDE.md
// § "The body must be the popup's DIRECT contentItem".
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
    // Which side of the ring the (Window-popup) tooltip opens toward — forwarded
    // to the shared behavior. See TooltipBehavior / core/CLAUDE.md.
    property bool openRight: false

    // ── Output ───────────────────────────────────────────────────────
    // The parent binds the backend's sampling gate to this (gated on its ring).
    readonly property bool samplingActive: behavior.samplingActive

    // Test hooks (underscore = internal) — forward the chrome state the rendering
    // tests drive (show-delay flag + grow-only width mark) from the behavior.
    readonly property alias _rowCount: rowRepeater.count
    readonly property alias _footerText: footerLabel.text
    property alias _show: behavior._show
    property alias _maxContentWidth: behavior._maxContentWidth
    readonly property alias _displayed: behavior._displayed

    anchors.fill: parent

    TooltipBehavior {
        id: behavior
        armed: root.armed
        openRight: root.openRight
        tip: tip
    }

    QQC2.ToolTip {
        id: tip
        parent: behavior.anchorMarker
        // Hover-driven only: visibility is `armed && _show`, never auto-close.
        // Paired with the transparent-for-input popup window (see contentItem): an
        // input-grabbing Window popup would steal the pointer from the ring's
        // HoverHandler and flicker (QTBUG-38084); a non-auto-closing, input-transparent
        // popup leaves hover with the ring, so show/hide stays purely hover-gated.
        closePolicy: QQC2.Popup.NoAutoClose
        // Close instantly (no fade): a fading-out popup lingers as an overlay one
        // more frame with its content already emptied (rows → 0 on hover-leave) —
        // both an empty-tooltip flash AND, overlapping the neighbour ring, a hover
        // thief that makes the next ring's tooltip open-then-immediately-close.
        exit: Transition {}
        // popupType set per-show via behavior._applyPopupType() (Window only on a
        // small host window; in-scene on a full-screen host so x/y are honored).
        // popupType is Qt 6.8+ but the floor is 6.6 — only touched when present.
        // See core/CLAUDE.md § "A QQC2 popup over the widget…".
        visible: root.armed && behavior._show
        // Content-driven width, bound explicitly (a Window popup won't auto-adopt
        // its contentItem's implicitWidth) AND grow-only via the high-water mark,
        // so the re-sampling list doesn't yoyo the width tick-to-tick. We bind to
        // max(mark, live implicitWidth): the mark blocks shrinking, the live term
        // sizes the first frame before the tracker fires. Height stays implicit.
        // The grow-only mark applies ONLY to the Window popup (standalone): there
        // the popup can't auto-size and the mark prevents yoyo. On the in-scene
        // (Plasma) path the box must equal its content exactly — a marked surplus
        // would leave empty space on the ring-facing side when placed left (the
        // name column is maximumWidth-capped) and detach the text from the ring.
        width: (tip.popupType === QQC2.Popup.Window ? Math.max(behavior._maxContentWidth, col.implicitWidth) : col.implicitWidth) + leftPadding + rightPadding
        // In-scene (Plasma) placement, centralized in the shared behavior: beside
        // the ring, centred on it, flipped/clamped to the screen. A Window popup
        // (standalone) ignores x/y and is placed via behavior.anchorMarker instead.
        x: behavior.inSceneX
        y: behavior.inSceneY

        contentItem: ColumnLayout {
            id: col
            spacing: Kirigami.Units.smallSpacing
            // Mark the separate Window popup transparent-for-input so it can't grab
            // the pointer from the ring's HoverHandler and flicker (QTBUG-38084). The
            // tooltip is non-interactive. Guarded to the separate popup window. Wayland
            // honors the post-creation flag; X11 keeps a faint first-show flash (needs a
            // pre-map C++ fix). See core/CLAUDE.md.
            onWindowChanged: {
                var w = col.Window.window;
                if (w && w !== root.Window.window)
                    w.flags = w.flags | Qt.WindowTransparentForInput;
            }
            // Feed the grow-only width high-water mark; never let it shrink.
            onImplicitWidthChanged: if (implicitWidth > behavior._maxContentWidth)
                behavior._maxContentWidth = implicitWidth

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
