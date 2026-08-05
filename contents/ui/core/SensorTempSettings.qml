import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "MetricsCatalog.js" as Catalog

// The sensorTemp sub-option (issue #164): a discoverable temperature
// sensor picker with live validation, plus the ring-label editor and
// the shared min/max editor (TempRangeSettings). Stateless: values
// come in as properties and every edit emits a dedicated signal.
//
// The picker is an EDITABLE combo backed by `availableSensors`:
// picking an entry commits its sensor id, while typing stays possible
// as the free-text fallback for custom or regex ids. `sensorId` remains
// the single source of truth for the text.
//
// The bounds are STORED in °C (the sensor reports Celsius kernel-side,
// and the ring maps that range onto the sweep) but DISPLAYED/EDITED in
// the user's temperature unit — the labels, spinbox values and the live
// reading follow `tempUnit`, resolved like the rings do
// (Catalog.resolveTempMode: "auto" → the system locale's measurement
// system).
ColumnLayout {
    id: root

    required property string sensorId
    required property string sensorLabel
    required property int minC
    required property int maxC
    // "auto" / "celsius" / "fahrenheit" — same value as the page's
    // TemperatureUnitSettings radios.
    property string tempUnit: "auto"
    // [{id, label}] of discovered Celsius sensors, injected by the
    // platform wrapper; empty where discovery is unavailable, in which
    // case the combo degrades to a plain id field.
    property var availableSensors: []
    // Live validation feed: whether `sensorId` currently resolves to a
    // sensor, and its raw °C reading (formatted here via `tempUnit`).
    property bool sensorResolved: false
    property real sensorLiveValue: NaN

    signal sensorIdEdited(string value)
    signal sensorLabelEdited(string value)
    signal minCEdited(int value)
    signal maxCEdited(int value)

    readonly property string _mode: Catalog.resolveTempMode(root.tempUnit, Qt.locale().measurementSystem)

    // Array-likeness guard: `availableSensors` may arrive as a non-Array
    // QML list — count/index it, never Array.isArray it.
    function _entryCount() {
        return root.availableSensors ? root.availableSensors.length : 0;
    }

    function _labelForId(id) {
        for (var i = 0; i < root._entryCount(); i++) {
            var entry = root.availableSensors[i];
            if (entry && entry.id === id)
                return entry.label;
        }
        return "";
    }

    function _idForText(text) {
        for (var i = 0; i < root._entryCount(); i++) {
            var entry = root.availableSensors[i];
            if (entry && entry.label === text)
                return entry.id;
        }
        return text;
    }

    onSensorIdChanged: sensorCombo.syncEditText()
    // Deferred: on a model change the control rewrites editText itself
    // (to the first entry's label) AFTER property-change handlers run —
    // an immediate sync would be overwritten. Verified by live probe.
    onAvailableSensorsChanged: Qt.callLater(sensorCombo.syncEditText)
    Component.onCompleted: sensorCombo.syncEditText()

    spacing: Kirigami.Units.smallSpacing

    QQC2.Label {
        text: qsTr("Temperature sensor")
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    QQC2.ComboBox {
        id: sensorCombo
        objectName: "sensorIdCombo"
        Layout.fillWidth: true
        editable: true
        model: root.availableSensors
        textRole: "label"

        // editText can't carry a binding (the first keystroke would
        // destroy it), so the sensorId → display-text sync is imperative:
        // a listed id shows its friendly label, anything else shows the
        // raw id.
        function syncEditText() {
            var label = root._labelForId(root.sensorId);
            var text = label.length > 0 ? label : root.sensorId;
            if (editText !== text)
                editText = text;
        }

        // Picking from the popup commits the entry's id — the label is
        // display text, never the persisted value.
        onActivated: function (index) {
            var entry = index >= 0 && index < root._entryCount() ? root.availableSensors[index] : null;
            if (entry && entry.id !== root.sensorId)
                root.sensorIdEdited(entry.id);
        }

        // Tag the stock editable combo's inner TextField so tests reach
        // it via findChild (tests/CLAUDE.md leaf-hook pattern) without
        // replacing the contentItem.
        Component.onCompleted: sensorCombo.contentItem.objectName = "sensorIdField"
    }

    // Typing commits verbatim (mapping a fully-typed label back to its
    // id): the editable combo doubles as the free-text fallback for
    // custom or regex sensor ids. Hooked on the inner TextField's
    // textEdited — user edits only — because the control rewrites
    // editText itself on model changes, which an editText-based commit
    // would echo back as phantom edits. Note editText lags one keystroke
    // behind inside this handler, so the field's own text is read.
    Connections {
        target: sensorCombo.contentItem
        function onTextEdited() {
            var committed = root._idForText(sensorCombo.contentItem.text);
            if (committed !== root.sensorId)
                root.sensorIdEdited(committed);
        }
    }

    QQC2.Label {
        objectName: "sensorHelpLabel"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        font: Kirigami.Theme.smallFont
        text: qsTr("Pick a discovered sensor, or type a sensor ID directly. The metric becomes available once the sensor is detected.")
    }

    // Live validation: resolved → the current reading; unresolved → an
    // error; empty id → neither (just the help line above).
    QQC2.Label {
        objectName: "sensorStatusLabel"
        Layout.fillWidth: true
        visible: root.sensorId.length > 0 && root.sensorResolved && isFinite(root.sensorLiveValue)
        text: {
            var reading = Catalog.convertTemp(root.sensorLiveValue, root._mode);
            return qsTr("Currently %1 %2").arg(reading.value.toFixed(1)).arg(reading.unit);
        }
    }

    Kirigami.InlineMessage {
        objectName: "sensorErrorMessage"
        Layout.fillWidth: true
        type: Kirigami.MessageType.Error
        visible: root.sensorId.length > 0 && !root.sensorResolved
        text: qsTr("Sensor not found. Pick one from the list or check the ID.")
    }

    // Entering an id is what makes the metric available, so the rest of
    // the form stays collapsed until one is set.
    ColumnLayout {
        objectName: "sensorExtraSection"
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        visible: root.sensorId.length > 0

        QQC2.Label {
            text: qsTr("Ring label")
        }

        QQC2.TextField {
            Layout.fillWidth: true
            objectName: "sensorLabelField"
            placeholderText: qsTr("SENSOR")
            text: root.sensorLabel
            maximumLength: 16
            onTextEdited: root.sensorLabelEdited(text)
        }

        // The min/max editor is shared with the cpuTemp/gpuTemp rows
        // (issue #164 section 5) — the objectNames the tests hook live
        // inside TempRangeSettings.
        TempRangeSettings {
            Layout.fillWidth: true
            minC: root.minC
            maxC: root.maxC
            tempUnit: root.tempUnit
            onMinCEdited: function (value) {
                root.minCEdited(value);
            }
            onMaxCEdited: function (value) {
                root.maxCEdited(value);
            }
        }
    }
}
