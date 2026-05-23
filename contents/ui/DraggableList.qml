pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "ReorderLogic.js" as Logic

// Reusable vertical list with drag-to-reorder behaviour.
//
// Usage:
//
//     DraggableList {
//         model: myListModel
//         rowHeight: 40
//         rowContent: Component {
//             RowLayout {
//                 // The rowContent root MUST declare these two properties —
//                 // they are filled by DraggableList for each row:
//                 property var rowModel       // ListModel role object
//                 property int rowIndex       // 0-based row position
//                 // ... your row content here ...
//             }
//         }
//         onReordered: (from, to) => { ... commit your new order ... }
//     }
//
// Implementation notes:
//   - We do NOT use QML's Drag/DropArea. They're hard to reason about (state
//     persists across drags, hit-testing depends on Drag.hotSpot in opaque
//     ways). Instead we track mouseY manually via a single MouseArea over
//     the handle and compute the hit row arithmetically.
//   - The dragged row floats by reparenting `rowBg` to the ListView root
//     and binding its y to a shared `draggedY` property.
//   - Other rows shift via a Translate transform computed by
//     Logic.computeYShift() — covered by tests in tests/reorder-logic.test.mjs.

ListView {
    id: root

    // ── Public API ──────────────────────────────────────────────────────
    property real rowHeight: Kirigami.Units.gridUnit * 2
    property real rowSpacing: 4
    property Component rowContent     // user-provided content for each row
    property bool showHandle: true    // visual move icon on the left

    // Emitted on drop when the order actually changed.
    signal reordered(int from, int to)

    // ── Internal state ──────────────────────────────────────────────────
    property int _dragSource: -1
    property int _dropTarget: -1
    property real _draggedY: 0   // y of the floating row's CENTER in content coords
    readonly property real _step: rowHeight + rowSpacing

    // ── ListView config ─────────────────────────────────────────────────
    spacing: rowSpacing
    interactive: false
    implicitHeight: Math.max(1, count) * _step
    boundsBehavior: Flickable.StopAtBounds

    // Animate rows that get pushed aside by the model `move()` on drop.
    // (Pre-drop animation is handled by the per-row Translate's Behavior.)
    moveDisplaced: Transition {
        NumberAnimation {
            properties: "y"
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    delegate: Item {
        id: row

        // Bound mode (pragma above) requires every delegate-scope name to be
        // explicit. `model` carries ListModel roles; `index` is the row's
        // position. Both must be declared `required` so the QML compiler
        // knows where they come from.
        required property var model
        required property int index

        width: ListView.view.width
        height: root.rowHeight

        readonly property bool held: root._dragSource === row.index
        readonly property int rowIndex: row.index

        // Visual shift to "make room" for the dragged item. Applied to
        // rowBg only — NOT to `row` itself, so the handle MouseArea (a
        // sibling of rowBg) stays at the row's model position, which keeps
        // the mouseY hit-testing intuitive.
        readonly property real yShift: Logic.computeYShift(row.index, root._dragSource, root._dropTarget, root._step)

        Rectangle {
            id: rowBg
            width: row.width
            height: row.height
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            radius: 4
            color: row.held ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.35) : (hoverHandler.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
            border.width: row.held ? 0 : 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            z: row.held ? 100 : 0

            // Translate is the *only* visual displacement during a drag.
            // When held → no Translate (the ParentChange + y in the State
            // takes over). When not held → Translate applies yShift, with
            // a smooth Behavior so it eases into / out of position.
            transform: Translate {
                y: row.held ? 0 : row.yShift
                Behavior on y {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }

            states: State {
                when: row.held
                ParentChange {
                    target: rowBg
                    parent: root
                    x: 0
                    y: root._draggedY - row.height / 2
                }
                AnchorChanges {
                    target: rowBg
                    anchors.horizontalCenter: undefined
                    anchors.verticalCenter: undefined
                }
            }

            HoverHandler {
                id: hoverHandler
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: "transform-move"
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                    opacity: 0.5
                    visible: root.showHandle
                }

                Loader {
                    id: contentLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: root.rowContent
                    // The rowContent Component lives in another file; with
                    // `pragma ComponentBehavior: Bound` it cannot reach into
                    // this delegate's scope. Forward `model` and `index`
                    // explicitly — the rowContent root must declare matching
                    // `property var rowModel` / `property int rowIndex`.
                    Binding {
                        target: contentLoader.item
                        property: "rowModel"
                        value: row.model
                        when: contentLoader.item !== null
                        restoreMode: Binding.RestoreNone
                    }
                    Binding {
                        target: contentLoader.item
                        property: "rowIndex"
                        value: row.index
                        when: contentLoader.item !== null
                        restoreMode: Binding.RestoreNone
                    }
                }
            }
        }

        // The drag handle MouseArea is a SIBLING of rowBg — anchored to
        // `row` (the delegate Item), so it does NOT move when rowBg gets
        // reparented to the ListView during a drag.
        MouseArea {
            id: handleArea
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Kirigami.Units.iconSizes.small + 12
            cursorShape: Qt.SizeVerCursor
            hoverEnabled: true

            onPressed: function (mouse) {
                const p = mapToItem(root.contentItem, mouse.x, mouse.y);
                root._dragSource = row.index;
                root._dropTarget = row.index;
                root._draggedY = p.y;
            }
            onPositionChanged: function (mouse) {
                if (!pressed)
                    return;
                const p = mapToItem(root.contentItem, mouse.x, mouse.y);
                root._draggedY = p.y;
                // Hit-test arithmetically — no DropArea involved. The result
                // is the model index the cursor is over right now.
                root._dropTarget = Logic.computeDropTarget(p.y, root._step, root.count);
            }
            onReleased: {
                const src = root._dragSource;
                const tgt = root._dropTarget;
                // Reset state BEFORE emitting the signal so the parent's
                // model edit happens with the drag already cleared. This
                // avoids any race where bindings briefly see (src, tgt)
                // pointing into a freshly-mutated model.
                root._dragSource = -1;
                root._dropTarget = -1;
                if (src >= 0 && tgt >= 0 && src !== tgt) {
                    root.reordered(src, tgt);
                }
            }
            // If the press is cancelled (window loses focus etc.), don't
            // leave the list in a stuck "dragging" state.
            onCanceled: {
                root._dragSource = -1;
                root._dropTarget = -1;
            }
        }
    }
}
