import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "GpuTooltipModel.js" as Model

// Hover tooltip for the GPU ring (issue #71). Shows per-device stat rows
// (Model, Usage, VRAM, Temperature, Power, Clock) from the pure
// GpuTooltipModel, plus a ranked list of GPU processes when the backend
// supplies them (NVIDIA only; AMD/Intel/Plasma aggregate → no process section).
//
// The popup CHROME (popup-type heuristic, show-delay, grow-only width mark,
// edge anchor) lives in the shared TooltipBehavior helper (#149). The BODY
// stays here as the popup's DIRECT contentItem — a Window-type popup renders
// wrong with a Loader contentItem, so the body is never factored out. See
// core/CLAUDE.md § "The body must be the popup's DIRECT contentItem".
//
// Inputs (MainContent wires these on the GPU ring):
//   armed     - true only on the GPU ring; gates the HoverHandler.
//   detail    - metrics.gpuDetail object for one device (see GpuTooltipModel
//               header for the contract: model, usagePercent, vramUsedBytes,
//               vramTotalBytes, tempC, powerW, clockMhz — all optional).
//   processes - metrics.gpuProcesses raw records (NVIDIA only). Empty array
//               on AMD/Intel/Plasma aggregate → process section hidden.
//   title     - header label (defaults to qsTr("GPU")).
//   openRight - forwarded to TooltipBehavior for Window-popup side selection.
// Output:
//   samplingActive - true the instant the pointer enters (armed-gated); the
//                    parent binds metrics.gpuTooltipActive to it.
//
// Known multi-GPU limitation (Plasma): when >1 GPU is present, the Plasma
// ksysguard sensors expose aggregate VRAM (gpu/all/usedVram,totalVram) while
// power, clock, and model name come from device 0. The "Model" stat row
// identifies which device's name is shown. Single-aggregate-panel is the
// chosen design for the MVP; a per-device carousel is a future follow-up.
Item {
    id: root

    // ── Inputs ───────────────────────────────────────────────────────
    // Only the owning ring arms the tooltip; every other ring leaves it inert.
    property bool armed: false
    // One GPU device detail object from the backend; absent fields are skipped.
    property var detail: ({})
    // Raw GPU process records (NVIDIA only); [] on AMD/Intel/Plasma aggregate.
    property var processes: []
    // Header line shown at the top of the tooltip.
    property string title: qsTr("GPU")
    // Which side of the ring the (Window-popup) tooltip opens toward — forwarded
    // to the shared behavior. See TooltipBehavior / core/CLAUDE.md.
    property bool openRight: false

    // ── Output ───────────────────────────────────────────────────────
    // The parent binds the backend's sampling gate to this (armed-gated).
    readonly property bool samplingActive: behavior.samplingActive

    // Test hooks (underscore = internal) — forward the chrome state the
    // rendering tests drive from the shared behavior.
    readonly property alias _statRowCount: statRepeater.count
    readonly property alias _procRowCount: procRepeater.count
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
        // Paired with the transparent-for-input popup window (see contentItem):
        // a grabbing Window popup would steal the pointer from the ring's
        // HoverHandler and flicker (QTBUG-38084). See core/CLAUDE.md.
        closePolicy: QQC2.Popup.NoAutoClose
        // Close instantly (no fade) — see ProcessTooltip: a fading popup lingers
        // empty (rows → 0) and steals the next ring's hover.
        exit: Transition {}
        // popupType set per-show via behavior._applyPopupType() (Window only on
        // a small host window; in-scene on a full-screen host so x/y are honored).
        // popupType is Qt 6.8+ but the floor is 6.6 — only touched when present.
        visible: root.armed && behavior._show
        // Content-driven width, bound explicitly (a Window popup won't auto-adopt
        // it) AND grow-only via the high-water mark — but the mark applies ONLY to
        // the Window popup (standalone). On the in-scene (Plasma) path the box must
        // equal its content so the text stays glued to the ring when placed left
        // (see ProcessTooltip's width comment). Height stays implicit.
        width: (tip.popupType === QQC2.Popup.Window ? Math.max(behavior._maxContentWidth, col.implicitWidth) : col.implicitWidth) + leftPadding + rightPadding
        // In-scene (Plasma) placement, centralized in the shared behavior: beside
        // the ring, centred on it, flipped/clamped to the screen. A Window popup
        // (standalone) ignores x/y and is placed via behavior.anchorMarker instead.
        x: behavior.inSceneX
        y: behavior.inSceneY

        contentItem: ColumnLayout {
            id: col
            spacing: Kirigami.Units.smallSpacing
            // Mark the separate Window popup transparent-for-input so it can't
            // grab the pointer from the ring's HoverHandler and flicker
            // (QTBUG-38084). The tooltip is non-interactive. Guarded to the
            // separate popup window. Wayland honors the post-creation flag; X11
            // keeps a faint first-show flash (needs a pre-map C++ fix). See
            // core/CLAUDE.md.
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
                id: statRepeater
                model: Model.buildStatRows(root.detail)

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.Label {
                        text: modelData.label
                        opacity: 0.7
                        Layout.fillWidth: true
                    }
                    QQC2.Label {
                        text: modelData.value
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }

            // Placeholder for the ~one-tick warm-up before the first sample.
            QQC2.Label {
                visible: statRepeater.count === 0
                text: qsTr("Gathering…")
                opacity: 0.6
            }

            // Process section — only rendered when the backend provides records
            // (NVIDIA only; absent on AMD/Intel and Plasma aggregate mode).
            Kirigami.Separator {
                visible: procRepeater.count > 0
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }

            QQC2.Label {
                visible: procRepeater.count > 0
                text: qsTr("GPU processes")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }

            Repeater {
                id: procRepeater
                model: Model.rankProcesses(root.processes, Model.DEFAULT_LIMIT)

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    QQC2.Label {
                        text: modelData.name
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        // Cap so one long name can't stretch the tooltip absurdly
                        // wide; comm names are ≤15 chars so this rarely bites.
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                    }
                    QQC2.Label {
                        text: "·" + modelData.pid
                        opacity: 0.45
                        font: Kirigami.Theme.smallFont
                    }
                    QQC2.Label {
                        text: Model.formatProcessVram(modelData.vramBytes)
                        horizontalAlignment: Text.AlignRight
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
                    }
                }
            }
        }
    }
}
