import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

// Hover-driven "top processes" tooltip for a ring (issue #69). The popup chrome
// (Window-popup guard, grow-only width, edge-aware placement, show-delay) lives
// in the shared HoverTooltip base; this supplies only the ranked-list body and
// the metric inputs. Generic over the ranked metric — the CPU ring wires it for
// CPU%, a RAM-ring tooltip can reuse it by injecting a different title /
// formatValue / footerText (Open/Closed — no edit here).
//
// Presentational only: it renders the ranked list (name + dimmed ·PID + a
// right-aligned value the parent formats) plus an optional footer. Pure QtQuick
// + Kirigami — no platform imports, no metric-specific logic.
HoverTooltip {
    id: root

    // ── Inputs ───────────────────────────────────────────────────────
    // Ranked [{pid, name, ...}] from backend.topProcesses.
    property var processes: []
    // Header line, e.g. qsTr("Top processes — CPU").
    property string title: ""
    // Per-row right-column formatter: function(process) → display string.
    property var formatValue: null
    // Footer line (empty → no footer). The parent formats it (e.g. load avg).
    property string footerText: ""

    // Test hooks (underscore = internal) — read off the loaded body root.
    readonly property int _rowCount: root.contentItem ? root.contentItem.rowCount : 0
    readonly property string _footerText: root.contentItem ? root.contentItem.footerLabelText : ""

    contentComponent: ColumnLayout {
        id: col
        readonly property alias rowCount: rowRepeater.count
        readonly property alias footerLabelText: footerLabel.text
        spacing: root.contentSpacing

        QQC2.Label {
            text: root.title
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
                    text: root.formatValue ? root.formatValue(procRow.modelData) : ""
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
            visible: root.footerText.length > 0
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
        }

        QQC2.Label {
            id: footerLabel
            visible: root.footerText.length > 0
            text: root.footerText
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
    }
}
