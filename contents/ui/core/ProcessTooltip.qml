import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "ProcessRanking.js" as ProcessRanking

// Hover-driven CPU-ring process tooltip (issue #69). Dropped in as a child of
// the CPU Ring in MainContent; it detects hover over the parent ring and:
//   - exposes `samplingActive` (true the instant the pointer enters) so the
//     parent binds the backend's processSamplingActive to it — sampling warms
//     up DURING the show-delay below, so data is ready by the time the tooltip
//     appears;
//   - shows the QQC2.ToolTip only after a short delay, so a quick mouse
//     pass-over doesn't flash it (or spin up /proc enumeration pointlessly).
//
// Presentational only beyond that: it renders the ranked list (name + dimmed
// ·PID, CPU% right-aligned) plus a load-average footer. All formatting is the
// shared core/ProcessRanking.js. Pure QtQuick + Kirigami — no platform imports.
Item {
    id: root

    // ── Inputs ───────────────────────────────────────────────────────
    // Only the CPU ring arms the tooltip; every other ring leaves it inert.
    property bool armed: false
    // Ranked [{pid, name, cpuPercent}] from backend.topProcesses.
    property var processes: []
    // [1, 5, 15]-min load averages from backend.loadAverages.
    property var loadAverages: [0, 0, 0]

    // ── Output ───────────────────────────────────────────────────────
    // The parent binds backend.processSamplingActive to this (gated on the CPU
    // ring). hover.enabled is armed-gated, so this stays false on other rings.
    readonly property bool samplingActive: hover.hovered

    // Test hooks (underscore = internal).
    readonly property alias _rowCount: rowRepeater.count
    readonly property alias _footerText: footerLabel.text
    property bool _show: false

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
            showDelay.restart();
        } else {
            showDelay.stop();
            root._show = false;
        }
    }

    QQC2.ToolTip {
        id: tip
        parent: root
        // A Window-type popup so it ISN'T clipped to the host window. The
        // standalone window is sized to the rings (tiny), so an in-scene
        // (Item) popup — the pre-6.8 default — gets cropped to that rect and
        // only a sliver shows. A Window popup is a separate surface the
        // compositor keeps on screen. (Qt 6.8+; harmless on Plasma.)
        popupType: QQC2.Popup.Window
        visible: root.armed && root._show
        // Content-driven width, bound explicitly. A Window-type popup does NOT
        // auto-adopt its contentItem's implicitWidth the way an in-scene popup
        // does, so the window collapsed to a sliver and names elided to "k…"
        // (PR #99 live test). Binding width to col.implicitWidth sizes the
        // window to the widest row (no loop: a Layout's implicitWidth is its
        // natural content size, independent of the width we assign back). The
        // name's maximumWidth caps how far one long name can stretch it. Height
        // stays implicit (it sized fine).
        width: col.implicitWidth + leftPadding + rightPadding
        // Edge-aware placement: prefer below-and-right of the ring, but FLIP to
        // the opposite side when that side would run off the screen, so the
        // tooltip stays fully visible wherever the widget sits (the standalone
        // anchors top-RIGHT by default, where growing right/down overflows).
        // mapToGlobal gives the ring's on-screen position; Screen.virtual* +
        // Screen.width/height bound the current monitor. (No Plasma dep — these
        // are plain QtQuick.) Re-evaluates when the tooltip's width/height
        // settle after layout.
        x: {
            var gx = root.mapToGlobal(0, 0).x;
            var screenRight = root.Screen.virtualX + root.Screen.width;
            if (gx + width > screenRight)
                return root.width - width;  // overflow right → right-align (grow left)
            return 0;                       // default → left-align (grow right)
        }
        y: {
            var gy = root.mapToGlobal(0, 0).y;
            var screenBottom = root.Screen.virtualY + root.Screen.height;
            if (gy + root.height + height > screenBottom)
                return -height;             // overflow bottom → above the ring
            return root.height;             // default → below the ring
        }

        contentItem: ColumnLayout {
            id: col
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: qsTr("Top processes — CPU")
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
                        text: ProcessRanking.formatCpuPercent(procRow.modelData.cpuPercent)
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
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
            }

            QQC2.Label {
                id: footerLabel
                text: qsTr("load") + "  " + ProcessRanking.formatLoadAverages(root.loadAverages)
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }
    }
}
