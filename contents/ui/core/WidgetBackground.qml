import QtQuick
import "BackgroundStyle.js" as BackgroundStyle

// Optional panel painted behind the rings (issue #170), so the widget
// can sit on a tinted plate instead of straight on the wallpaper.
// Off by default — the historic look is a fully transparent widget.
//
// Both hosts (contents/ui/main.qml, platforms/standalone/Main.qml)
// mount one of these anchored under their MainContent. Portable: the
// colour and the fade come from plain properties the host forwards
// from its ConfigStore, and the two-stop math lives in
// BackgroundStyle.js.

Rectangle {
    id: widgetBackground

    property bool backgroundEnabled: false
    property color backgroundColor: "#000000"
    property real backgroundOpacity: 0.5
    // Edge the plate fades out toward — see BackgroundStyle.DIRECTIONS.
    property string backgroundGradient: "none"

    visible: widgetBackground.backgroundEnabled
    // Painted by the gradient below in every case: "none" just yields
    // two stops of the same alpha, i.e. a flat fill.
    color: "transparent"

    function _stopColor(alpha) {
        return Qt.rgba(widgetBackground.backgroundColor.r, widgetBackground.backgroundColor.g, widgetBackground.backgroundColor.b, alpha);
    }

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
