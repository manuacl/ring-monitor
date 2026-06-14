import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "DiskTooltipModel.js" as Model

// Hover tooltip for the disk ring(s) (issue #68): one line per shown disk —
// a removable/fixed icon tinted to that ring's colour, the volume label with a
// dimmed `mountpoint · fstype` sub-line, the usage % + used/total, and the free
// space. All strings come from the pure DiskTooltipModel so this view stays
// presentational.
//
// The popup CHROME (popup-type heuristic, show-delay, grow-only width mark, edge
// anchor) lives in the shared TooltipBehavior helper (#149). The BODY stays here
// as the popup's DIRECT contentItem — a Window-type popup renders wrong with a
// Loader contentItem, so the body is never factored out. See core/CLAUDE.md
// § "The body must be the popup's DIRECT contentItem".
//
// Inputs (the parent — MainContent — wires them on the disk ring delegate):
//   armed   - true only on the disk ring; gates the HoverHandler.
//   details - [partitionDetail] in ring order, each metrics.partitionDetail(id).
//   colors  - per-ring colours aligned to `details` (MainContent._diskColors).
//   fallbackColor - the shared ring colour, for a row with no colour.
// Output:
//   samplingActive - true the instant the pointer enters (armed-gated); the
//                    parent binds metrics.diskTooltipActive to it.
Item {
    id: root

    property bool armed: false
    property var details: []
    property var colors: []
    property color fallbackColor: Kirigami.Theme.highlightColor
    property string title: qsTr("Disks")
    // Which side the (Window-popup) tooltip opens toward — forwarded to the shared
    // behavior. See TooltipBehavior / core/CLAUDE.md.
    property bool openRight: false

    readonly property bool samplingActive: behavior.samplingActive

    // Presentational rows from the pure model (label, subLabel, usageText,
    // freeText, iconName, removable); zipped with `colors` by index in the view.
    readonly property var _rows: Model.buildRows(root.details)
    // Test hooks (underscore = internal) — forward the chrome state the rendering
    // tests drive from the shared behavior.
    readonly property alias _rowCount: rowRepeater.count
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
        // popupType set per-show via behavior._applyPopupType() (Window only on a
        // small host window; in-scene on a full-screen host so x/y are honored).
        // popupType is Qt 6.8+ but the floor is 6.6 — only touched when present.
        // Hover-driven only + transparent-for-input popup window (see contentItem):
        // a grabbing Window popup would steal the pointer from the ring's
        // HoverHandler and flicker (QTBUG-38084). See core/CLAUDE.md.
        closePolicy: QQC2.Popup.NoAutoClose
        // Close instantly (no fade) — see ProcessTooltip: a fading popup lingers
        // empty (rows → 0) and steals the next ring's hover.
        exit: Transition {}
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
                model: root._rows

                delegate: RowLayout {
                    id: diskRow
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing

                    // Removable/fixed glyph, tinted to this ring's colour (isMask
                    // recolours the monochrome icon) so the line maps to its gauge.
                    Kirigami.Icon {
                        source: diskRow.modelData.iconName
                        isMask: true
                        color: (root.colors && root.colors[diskRow.index]) ? root.colors[diskRow.index] : root.fallbackColor
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        QQC2.Label {
                            text: diskRow.modelData.label
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.maximumWidth: Kirigami.Units.gridUnit * 12
                        }
                        QQC2.Label {
                            text: diskRow.modelData.subLabel
                            visible: text.length > 0
                            font: Kirigami.Theme.smallFont
                            opacity: 0.55
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    ColumnLayout {
                        spacing: 0
                        Layout.alignment: Qt.AlignRight
                        QQC2.Label {
                            text: diskRow.modelData.usageText
                            horizontalAlignment: Text.AlignRight
                            Layout.alignment: Qt.AlignRight
                        }
                        QQC2.Label {
                            text: diskRow.modelData.freeText
                            visible: text.length > 0
                            font: Kirigami.Theme.smallFont
                            opacity: 0.55
                            horizontalAlignment: Text.AlignRight
                            Layout.alignment: Qt.AlignRight
                        }
                    }
                }
            }

            // ~one-tick warm-up before the first partitionDetail resolves.
            QQC2.Label {
                visible: rowRepeater.count === 0
                text: qsTr("Gathering…")
                opacity: 0.6
            }
        }
    }
}
