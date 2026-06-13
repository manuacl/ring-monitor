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
// The popup chrome here is DUPLICATED from ProcessTooltip (#69), not shared:
// extracting it into a HoverTooltip base required injecting the body via a
// Loader contentItem, and a Window-type QQC2 popup renders WRONG with a Loader
// contentItem (in-scene/clipped instead of a floating surface — caught live on
// Qt 6.10, both rings). The body must be the popup's DIRECT contentItem. The
// default-property alternative captures this file's own HoverHandler. So the
// two tooltips each own their chrome; keep them in sync. See core/CLAUDE.md
// § "QQC2 popup over the widget…".
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
    // Which side the Window-popup tooltip opens toward (see ProcessTooltip): left-
    // anchored widget opens RIGHT, right-anchored opens LEFT (default). Keep in sync.
    property bool openRight: false

    readonly property bool samplingActive: hover.hovered

    // Presentational rows from the pure model (label, subLabel, usageText,
    // freeText, iconName, removable); zipped with `colors` by index in the view.
    readonly property var _rows: Model.buildRows(root.details)
    // Test hooks (underscore = internal).
    readonly property alias _rowCount: rowRepeater.count
    property bool _show: false
    // Grow-only width high-water mark — see the popup's `width`. Reset on the
    // dismiss edge so a one-off wide sample doesn't pin every later hover.
    property real _maxContentWidth: 0
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

    // popupType decided per-show: a separate-surface Window popup ONLY when the host
    // window is too small to contain the tooltip in-scene (the standalone window,
    // sized to the rings). On a full-screen host (Plasma desktop view) an in-scene
    // popup isn't clipped AND honors the item-relative x/y above — a Window popup
    // ignores x/y and auto-places (Qt 6.11). Set while hidden (hover-enter) so the
    // type is stable before open. Mirrors ProcessTooltip — keep the two in sync.
    function _applyPopupType() {
        if (tip.popupType === undefined)
            return;   // Qt < 6.8 — in-scene only (fine: Plasma overlay is large)
        var win = root.Window.window;
        var hostTooSmall = !win || win.width < root.Screen.width * 0.6 || win.height < root.Screen.height * 0.6;
        tip.popupType = hostTooSmall ? QQC2.Popup.Window : QQC2.Popup.Item;
    }

    on_DisplayedChanged: if (!root._displayed)
        root._maxContentWidth = 0

    // Anchor for the Window-popup placement — mirrors ProcessTooltip. A Window-type
    // QQC2 popup ignores its own x/y on Wayland; the compositor anchors it to the
    // popup's PARENT-ITEM rect (top-right corner → anchor's left/bottom, growing
    // left+down). Parenting to a 1×1 marker at the ring's top-left pins the tooltip's
    // top-right corner to the ring's top-left (beside the ring, top-aligned). The
    // in-scene path is unaffected: the marker sits at the ring origin.
    Item {
        id: anchorMarker
        // Anchor at the ring's interior-facing top corner; the compositor grows the
        // popup inward (gravity flips at the screen edge). Right-anchored widget →
        // anchor at ring top-left (grows left); left-anchored (openRight) → ring
        // top-right (grows right). The shift applies ONLY to a Window popup (an in-scene
        // Item popup keeps the marker at the ring origin so its own x/y flip stays
        // correct; safe on Qt < 6.8 where popupType is undefined). Mirrors ProcessTooltip.
        x: (root.openRight && tip.popupType === QQC2.Popup.Window) ? root.width : 0
        y: 0
        width: 1
        height: 1
    }

    QQC2.ToolTip {
        id: tip
        parent: anchorMarker
        // popupType set per-show via root._applyPopupType() (Window only on a small
        // host window; in-scene on a full-screen host so x/y are honored). `popupType`
        // is Qt 6.8+ but the floor is 6.6 — only touched when present. core/CLAUDE.md.
        // Hover-driven only + transparent-for-input popup window (see contentItem): a
        // grabbing Window popup would steal the pointer from the ring's HoverHandler
        // and flicker (QTBUG-38084). Keep in sync with ProcessTooltip.
        closePolicy: QQC2.Popup.NoAutoClose
        visible: root.armed && root._show
        // Content-driven width, bound explicitly (a Window popup won't auto-adopt
        // it) AND grow-only via the high-water mark. Height stays implicit.
        width: Math.max(root._maxContentWidth, col.implicitWidth) + leftPadding + rightPadding
        // Edge-aware: beside the ring (right), top-aligned with it; FLIP on overflow.
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
            // Mark the separate Window popup transparent-for-input so it can't grab
            // the pointer from the ring's HoverHandler and flicker (QTBUG-38084). The
            // tooltip is non-interactive. Guarded to the separate popup window. Wayland
            // honors the post-creation flag; X11 keeps a faint first-show flash (needs a
            // pre-map C++ fix). Keep in sync with ProcessTooltip.
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
