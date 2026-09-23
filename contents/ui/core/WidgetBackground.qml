import QtQuick
import QtQuick.Effects
import "BackgroundStyle.js" as BackgroundStyle

// Optional panel painted behind the rings (issue #170), so the widget
// can sit on a tinted plate instead of straight on the wallpaper.
// Off by default — the historic look is a fully transparent widget.
//
// Both hosts (contents/ui/main.qml, platforms/standalone/Main.qml)
// mount one of these under their MainContent, filling the same box, and
// hand it the layout as `rings`: the plate is a stadium around the drawn
// rings, not the host's rectangle. Portable: the
// colour, the directional fade and the edge softness come from plain
// properties the host forwards from its ConfigStore, and the math lives
// in BackgroundStyle.js.

Item {
    id: widgetBackground

    property bool backgroundEnabled: false
    property color backgroundColor: "#000000"
    property real backgroundOpacity: 0.5
    // Edge the plate fades out toward — see BackgroundStyle.DIRECTIONS.
    property string backgroundGradient: "none"
    // Blur applied to all four edges, as a percent of the shorter side.
    // 0 = the crisp rectangle.
    property int backgroundEdgeSoftness: 0

    // The ring layout (MainContent). Must share this item's coordinate
    // space, which both hosts get by filling the same parent. Null = no
    // rings to follow, the plate fills the item.
    property Item rings: null

    visible: widgetBackground.backgroundEnabled

    // Read in the binding so it tracks every cell's geometry and the
    // Repeater adding or dropping rings. Only Ring delegates carry `size`.
    readonly property var _box: {
        var cells = [];
        var kids = widgetBackground.rings ? widgetBackground.rings.children : [];
        for (var i = 0; i < kids.length; i++) {
            if (kids[i].visible && kids[i].size !== undefined)
                cells.push({
                    "x": kids[i].x,
                    "y": kids[i].y,
                    "width": kids[i].width,
                    "height": kids[i].height
                });
        }
        return BackgroundStyle.ringBounds(cells) || {
            "x": 0,
            "y": 0,
            "width": widgetBackground.width,
            "height": widgetBackground.height,
            "radius": 0
        };
    }

    readonly property int _feather: BackgroundStyle.featherPixels(widgetBackground.backgroundEdgeSoftness, widgetBackground._box.width, widgetBackground._box.height)

    function _stopColor(alpha) {
        return Qt.rgba(widgetBackground.backgroundColor.r, widgetBackground.backgroundColor.g, widgetBackground.backgroundColor.b, alpha);
    }

    // Inset by the feather so the blur fades out at the rings' outer edge
    // instead of being clipped by a window sized to the strip: the effect
    // below bleeds back out over the inset. The caps shrink by the same
    // amount so they stay concentric with the end rings.
    Rectangle {
        id: plate

        objectName: "backgroundPlate"
        x: widgetBackground._box.x + widgetBackground._feather
        y: widgetBackground._box.y + widgetBackground._feather
        width: Math.max(0, widgetBackground._box.width - 2 * widgetBackground._feather)
        height: Math.max(0, widgetBackground._box.height - 2 * widgetBackground._feather)
        radius: Math.max(0, widgetBackground._box.radius - widgetBackground._feather)
        // Painted by the gradient below in every case: "none" just yields
        // two stops of the same alpha, i.e. a flat fill.
        color: "transparent"

        gradient: Gradient {
            orientation: BackgroundStyle.isHorizontal(widgetBackground.backgroundGradient) ? Gradient.Horizontal : Gradient.Vertical

            GradientStop {
                position: 0.0
                color: widgetBackground._stopColor(BackgroundStyle.startAlpha(widgetBackground.backgroundGradient, widgetBackground.backgroundOpacity))
            }
            GradientStop {
                position: 1.0
                color: widgetBackground._stopColor(BackgroundStyle.endAlpha(widgetBackground.backgroundGradient, widgetBackground.backgroundOpacity))
            }
        }
    }

    // A linear Gradient only fades along one axis, so the soft edge is a
    // blur. The effect is instantiated unconditionally and switched by
    // `blurEnabled` rather than by `visible`: MultiEffect hides its source
    // item itself, so toggling the effect's visibility would take the
    // plate with it. Disabled, it draws the source unchanged.
    MultiEffect {
        id: feathering

        objectName: "backgroundFeathering"
        anchors.fill: plate
        source: plate
        autoPaddingEnabled: true
        blurEnabled: widgetBackground._feather > 0
        blur: 1.0
        blurMax: Math.max(2, widgetBackground._feather)
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _plate: plate
    readonly property alias _feathering: feathering
}
