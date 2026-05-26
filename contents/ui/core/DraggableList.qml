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
//             Item {
//                 // Row data is forwarded by DraggableList onto the Loader
//                 // that hosts this Component — read it via `parent`:
//                 readonly property string fooId: parent && parent.rowModel
//                                                 ? parent.rowModel.fooId
//                                                 : ""
//                 // ... your row content here ...
//             }
//         }
//         onReordered: (from, to) => { ... commit your new order ... }
//     }
//
// Implementation — based on Qt 6's Dynamic View Ordering tutorial:
// https://doc.qt.io/qt-6/qtquick-tutorials-dynamicview-dynamicview2-example.html
//
//   - The drag handle is a MouseArea on the left strip; it uses Qt's native
//     `drag.target` to move the row's content Rectangle along the Y axis.
//     Qt's mouse-grab and coordinate handling does the heavy lifting — no
//     manual mapToItem / mouseY tracking.
//   - The content Rectangle's `Drag.active` mirrors the MouseArea's drag,
//     which lights up the per-row `DropArea`s. When a DropArea fires
//     `onEntered`, we record the target index — that's how reorder works
//     without poking the model directly during the drag.
//   - Other rows shift visually via a Translate transform driven by
//     `Logic.computeYShift()` (pure JS, tested in tests/reorder-logic.test.mjs).
//   - On release the parent commits the move via the `reordered` signal.

ListView {
    id: root

    // ── Public API ──────────────────────────────────────────────────────
    property real rowHeight: 36
    property real rowSpacing: 4
    property Component rowContent     // user-provided content for each row
    property bool showHandle: true    // visual move icon on the left

    // Theme tokens — injected by the parent via the platform/Theme adapter.
    // Sensible defaults match Kirigami's typical values for standalone use.
    property color highlightColor: "#3daee9"
    property color backgroundColor: "#1e1e1e"
    property real smallSpacing: 4
    property real iconSize: 16

    // Emitted on drop when the order actually changed.
    signal reordered(int from, int to)

    // ── Internal state ──────────────────────────────────────────────────
    property int _dragSource: -1
    property int _dropTarget: -1
    readonly property real _step: rowHeight + rowSpacing

    // ── ListView config ─────────────────────────────────────────────────
    spacing: rowSpacing
    interactive: false
    // contentHeight = sum of delegate heights + spacing — handles
    // variable-height rows (e.g. MetricRow with extraContent visible).
    implicitHeight: Math.max(_step, contentHeight)
    boundsBehavior: Flickable.StopAtBounds

    moveDisplaced: Transition {
        NumberAnimation {
            properties: "y"
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    delegate: Item {
        id: row
        width: ListView.view.width
        // Row height = max(rowHeight floor, rowContent's intrinsic height).
        // Allows variable-height rows when rowContent has an extraContent
        // sub-section (e.g. MetricRow with the CPU-cores toggle).
        height: contentLoader.item ? Math.max(root.rowHeight, contentLoader.item.implicitHeight + 4) : root.rowHeight

        readonly property bool held: handleArea.drag.active
        // The visual "make room" shift is the SOURCE row's height + spacing
        // (the space it vacates as it leaves to land on the target).
        readonly property real _srcExtent: {
            const src = root.itemAtIndex(root._dragSource);
            return src ? src.height + root.rowSpacing : root._step;
        }
        readonly property real yShift: Logic.computeYShift(index, root._dragSource, root._dropTarget, row._srcExtent)

        // The row's visible content. While dragging it reparents to the
        // ListView contentItem so it can float above the other rows.
        Rectangle {
            id: content
            width: row.width
            height: row.height
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            radius: 4
            // Opaque background while dragged so the floating row doesn't
            // show the static rows underneath through transparency.
            color: row.held ? Qt.tint(root.backgroundColor, Qt.rgba(root.highlightColor.r, root.highlightColor.g, root.highlightColor.b, 0.18)) : (hoverHandler.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
            border.width: row.held ? 2 : 1
            border.color: row.held ? root.highlightColor : Qt.rgba(1, 1, 1, 0.08)
            z: row.held ? 100 : 0

            // Light up the drag-and-drop signaling system whenever the
            // handle's MouseArea drag is active. Without this the DropAreas
            // never get onEntered events.
            Drag.active: handleArea.drag.active
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2
            Drag.source: row

            // Visual "make room" shift for non-dragged rows.
            transform: Translate {
                y: row.held ? 0 : row.yShift
                Behavior on y {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // While the handle is dragging, free `content` from its anchors
            // and reparent it to the contentItem so it floats above siblings.
            // Qt's drag.target binding moves it from there.
            states: State {
                when: row.held
                ParentChange {
                    target: content
                    parent: root.contentItem
                }
                AnchorChanges {
                    target: content
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
                spacing: root.smallSpacing

                Kirigami.Icon {
                    source: "transform-move"
                    implicitWidth: root.iconSize
                    implicitHeight: root.iconSize
                    opacity: 0.5
                    visible: root.showHandle
                    // Stay next to the main checkbox row, not floating
                    // when the row grows for extraContent.
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: (root.rowHeight - implicitHeight) / 2
                }

                Loader {
                    id: contentLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    sourceComponent: root.rowContent

                    // Forward row data to the rowContent Component. The
                    // loaded Item reads these via `parent.rowModel` etc. —
                    // QML's implicit context-property propagation through
                    // Loader is unreliable across Qt versions.
                    property var rowModel: model
                    property int rowIndex: index
                }
            }
        }

        // The drag handle. Drives `content` via Qt's native drag.target so
        // the cursor and the floating row stay in sync automatically — no
        // mapToItem, no manual y bookkeeping.
        MouseArea {
            id: handleArea
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.iconSize + 12
            cursorShape: Qt.SizeVerCursor
            hoverEnabled: true

            drag.target: content
            drag.axis: Drag.YAxis
            drag.smoothed: false

            onPressed: {
                root._dragSource = index;
                root._dropTarget = index;
            }
            onReleased: {
                const src = root._dragSource;
                const tgt = root._dropTarget;
                root._dragSource = -1;
                root._dropTarget = -1;
                if (src >= 0 && tgt >= 0 && src !== tgt) {
                    root.reordered(src, tgt);
                }
            }
            onCanceled: {
                root._dragSource = -1;
                root._dropTarget = -1;
            }
        }

        // Hit-test area: stays at the row's model position regardless of
        // visual shifts. When the dragged Rectangle's hotspot enters it,
        // we record this row as the current drop target.
        //
        // onExited rewinds the target to the source. This handles the
        // "drag away then back to origin" case — when the cursor leaves
        // a row, we don't want `_dropTarget` to stay stuck at that row's
        // index until another DropArea fires. Without this the source
        // row's DropArea wouldn't refire `onEntered` reliably on return,
        // and the no-op drop on origin would emit a (src,wrong) reorder.
        // See SCENARIO test in tests/qml/tst_DraggableList.qml.
        DropArea {
            anchors.fill: parent
            onEntered: root._dropTarget = index
            onExited: root._dropTarget = root._dragSource
        }
    }
}
