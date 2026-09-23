import QtQuick
import QtQuick.Shapes
import "BackgroundStyle.js" as BackgroundStyle

// Optional halo painted behind the rings (issue #170), so the widget can
// sit on a tinted glow instead of straight on the wallpaper. Off by
// default — the historic look is a fully transparent widget.
//
// Both hosts (contents/ui/main.qml, platforms/standalone/Main.qml) mount
// one of these under their MainContent, filling the same box, and hand it
// the layout as `rings`: the halo is a stadium around the drawn rings, not
// the host's rectangle. Portable: colour, size and edge softness come from
// plain properties the host forwards from its ConfigStore, and the math
// lives in BackgroundStyle.js.

Item {
    id: widgetBackground

    property bool backgroundEnabled: false
    property color backgroundColor: "#000000"
    property real backgroundOpacity: 0.5
    // Extra halo around the rings, as a percent of the ring radius.
    // 0 = hugging the rings.
    property int backgroundSpread: 0
    // Fade-to-transparent band along the halo's edge, as a percent of its
    // shorter side. 0 = a crisp edge.
    property int backgroundEdgeSoftness: 0
    // The ring layout (MainContent). Must share this item's coordinate
    // space, which both hosts get by filling the same parent. Null = no
    // rings to follow, the halo starts from the item's own box.
    property Item rings: null

    visible: widgetBackground.backgroundEnabled

    // Read in the binding so it tracks every cell's geometry and the
    // Repeater adding or dropping rings. Only Ring delegates carry `size`.
    readonly property var _ringBox: {
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
            "radius": Math.min(widgetBackground.width, widgetBackground.height) / 2
        };
    }
    readonly property var _box: BackgroundStyle.spreadBounds(widgetBackground._ringBox, widgetBackground.backgroundSpread)
    readonly property int _feather: BackgroundStyle.featherPixels(widgetBackground.backgroundEdgeSoftness, widgetBackground._box.width, widgetBackground._box.height)
    readonly property var _halo: BackgroundStyle.haloGeometry(widgetBackground._box.width, widgetBackground._box.height, widgetBackground._feather)

    readonly property color _core: Qt.rgba(widgetBackground.backgroundColor.r, widgetBackground.backgroundColor.g, widgetBackground.backgroundColor.b, BackgroundStyle.clampOpacity(widgetBackground.backgroundOpacity))
    readonly property color _edge: Qt.rgba(widgetBackground.backgroundColor.r, widgetBackground.backgroundColor.g, widgetBackground.backgroundColor.b, BackgroundStyle.clampOpacity(widgetBackground.backgroundOpacity) * widgetBackground._halo.edgeAlpha)

    // Whole-pixel origin keeps the path seams on pixel boundaries (see
    // BackgroundStyle.haloGeometry). May sit at negative coordinates: a
    // spread halo is drawn past the host's edge.
    Shape {
        id: halo

        objectName: "backgroundHalo"
        x: Math.round(widgetBackground._box.x)
        y: Math.round(widgetBackground._box.y)
        width: widgetBackground._box.width
        height: widgetBackground._box.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: body

            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: widgetBackground._halo.across.start.x
                y1: widgetBackground._halo.across.start.y
                x2: widgetBackground._halo.across.end.x
                y2: widgetBackground._halo.across.end.y

                GradientStop {
                    position: 0
                    color: widgetBackground._edge
                }
                GradientStop {
                    position: widgetBackground._halo.fadeStop
                    color: widgetBackground._core
                }
                GradientStop {
                    position: 1 - widgetBackground._halo.fadeStop
                    color: widgetBackground._core
                }
                GradientStop {
                    position: 1
                    color: widgetBackground._edge
                }
            }
            startX: widgetBackground._halo.body[0].x
            startY: widgetBackground._halo.body[0].y

            PathLine {
                x: widgetBackground._halo.body[1].x
                y: widgetBackground._halo.body[1].y
            }
            PathLine {
                x: widgetBackground._halo.body[2].x
                y: widgetBackground._halo.body[2].y
            }
            PathLine {
                x: widgetBackground._halo.body[3].x
                y: widgetBackground._halo.body[3].y
            }
        }

        HaloCap {
            cap: widgetBackground._halo.capA
            radius: widgetBackground._halo.r
            capStop: widgetBackground._halo.capStop
            coreColor: widgetBackground._core
            edgeColor: widgetBackground._edge
        }
        HaloCap {
            cap: widgetBackground._halo.capB
            radius: widgetBackground._halo.r
            capStop: widgetBackground._halo.capStop
            coreColor: widgetBackground._core
            edgeColor: widgetBackground._edge
        }
    }

    // ── Test hooks ──────────────────────────────────────────────────
    readonly property alias _shape: halo
    readonly property alias _body: body
}
