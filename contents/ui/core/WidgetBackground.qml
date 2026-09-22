import QtQuick
import QtQuick.Effects
import "BackgroundStyle.js" as BackgroundStyle

// Optional panel painted behind the rings (issue #170), so the widget
// can sit on a tinted plate instead of straight on the wallpaper.
// Off by default — the historic look is a fully transparent widget.
//
// Both hosts (contents/ui/main.qml, platforms/standalone/Main.qml)
// mount one of these anchored under their MainContent. Portable: the
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

    visible: widgetBackground.backgroundEnabled

    readonly property int _feather: BackgroundStyle.featherPixels(widgetBackground.backgroundEdgeSoftness, widgetBackground.width, widgetBackground.height)

    function _stopColor(alpha) {
        return Qt.rgba(widgetBackground.backgroundColor.r, widgetBackground.backgroundColor.g, widgetBackground.backgroundColor.b, alpha);
    }

    // Inset by the feather so the blur fades out INSIDE the widget: the
    // effect below is anchored to the plate and bleeds back out over the
    // margin. At softness 0 the margin is 0 and the plate fills as before.
    Rectangle {
        id: plate

        objectName: "backgroundPlate"
        anchors.fill: parent
        anchors.margins: widgetBackground._feather
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
