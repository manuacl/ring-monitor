import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import RingMonitor.Standalone
import "DiskDiscovery.js" as DiskDiscovery
import "../../core/DiskMetrics.js" as DiskMetrics
import "../../core/ColorThemes.js" as ColorThemes
import "../../core" as Core

// Standalone counterpart of the Plasma config dialog
// (contents/ui/config*.qml hosted in System Settings → Plasma's panel
// applet config). Tabbed Window wrapping the same three bodies the
// Plasma side reuses: MetricsBody, AppearanceBody, AboutBody.
//
// Two-way binding pattern. The Plasma side uses SimpleKCM's `cfg_*`
// magic + bidirectional `property alias` to bridge body properties
// to KConfig. Standalone has no SimpleKCM — we bridge by hand:
//
//   1. _pullFromStore() copies configStore.X → body.X at open time
//   2. The body's onXChanged handler (wired in Component.onCompleted
//      via `body.XChanged.connect(...)`) writes back to configStore.X
//
// Because Qt.labs.settings persists Settings property writes on the
// next event-loop pass, write-back is immediate and durable. No
// explicit "Apply" button needed — live editing matches the Plasma
// SimpleKCM behaviour from the user's point of view.
//
// Wired by Main.qml: instantiated once at startup; the right-click
// "Settings…" menu item calls dialog.show().

Window {
    id: dialog

    // Injected by Main.qml.
    property var configStore
    property var theme
    property var updateChecker
    // The running backend's availableMetrics — injected (not re-probed)
    // because Main.qml's MetricsBackend keeps sampling while the dialog is
    // open, so the picker greys/un-greys rows live as sources resolve.
    property var availableMetrics: null

    title: qsTr("ring-monitor settings")
    width: 640
    height: 540
    visible: false
    // Track the Kirigami theme so the dialog blends with the user's
    // system colour scheme. Without this the Window defaults to the
    // platform's "no colour set" white, which clashes with a dark
    // Plasma scheme.
    color: dialog.theme ? dialog.theme.backgroundColor : Kirigami.Theme.backgroundColor

    // Centre on the actual destination screen — NOT at
    // Component.onCompleted. The `Screen` attached property reads
    // the screen the Window currently lives on, but a hidden Window
    // hasn't been assigned a screen yet — so at onCompleted it
    // resolves to the primary screen even when the widget that opens
    // the dialog lives on a secondary monitor. Recenter on the
    // FIRST hidden→visible transition: at that moment Qt has decided
    // which screen to map us on and `Screen.*` reflects it.
    // `Screen.virtualX/Y` puts the dialog in the screen's own
    // coordinate space (a multi-monitor `Window.x = N` is virtual-
    // desktop-absolute on X11, so a bare centring formula would land
    // on the leftmost screen even when the destination Screen is the
    // rightmost).
    //
    // `_centered` gates the recenter to the FIRST open only. Without
    // the gate, every close-then-reopen wipes any user-dragged
    // position — the dialog is instantiated once in Main.qml and
    // `show()` reuses the same instance, so subsequent opens would
    // snap back to centre regardless of where the user had moved it.
    // Qt's QWindow already preserves the last position on hide+show,
    // which is what users expect from a window-managed dialog.
    property bool _centered: false
    function _recenterOnCurrentScreen() {
        dialog.x = Screen.virtualX + (Screen.width - dialog.width) / 2;
        dialog.y = Screen.virtualY + (Screen.height - dialog.height) / 2;
    }
    onVisibleChanged: {
        if (dialog.visible && !dialog._centered) {
            dialog._recenterOnCurrentScreen();
            dialog._centered = true;
        }
        // Re-enumerate filesystems each time the dialog opens so a disk
        // plugged since the last open shows up in the partition picker.
        if (dialog.visible)
            dialog._refreshDiskPartitions();
    }

    Component.onCompleted: dialog._wireBridges()

    // Disk partition discovery for the picker. The dialog has no
    // MetricsBackend, so it runs the same pure DiskDiscovery over its own
    // ProcReader to enumerate mounted filesystems ([{id, label}]). Values
    // aren't needed here — only the selectable list.
    ProcReader {
        id: partitionReader
    }
    property var _diskPartitions: []
    // Currently-mounted removable filesystems ([{id,label}]) — the auto-show set
    // the picker uses to distinguish opt-out rows from manual-selection rows.
    property var _removablePartitions: []
    // The $HOME-bearing filesystem — the default the picker seeds when the
    // user hasn't chosen any partition (mirrors the backend's defaultPartitionIds).
    property var _defaultPartitionIds: []
    function _refreshDiskPartitions() {
        var mounts = DiskDiscovery.parseMounts(partitionReader.read("/proc/mounts"));
        var parts = DiskDiscovery.buildPartitions(mounts, partitionReader.blockDeviceInfo());
        var out = [];
        var removable = [];
        for (let i = 0; i < parts.length; i++) {
            out.push({
                "id": parts[i].id,
                "label": parts[i].label
            });
            if (DiskMetrics.isRemovableMount(parts[i].mountpoint))
                removable.push({
                    "id": parts[i].id,
                    "label": parts[i].label
                });
        }
        dialog._diskPartitions = out;
        dialog._removablePartitions = removable;
        // Same helper as the backend so the seeded default matches the
        // widget's rendered default (incl. the first-partition fallback).
        dialog._defaultPartitionIds = DiskDiscovery.defaultOrFirst(mounts, parts, partitionReader.canonicalHome());
    }

    // ColorPicker injected into AppearanceBody as a Component — the
    // body stays platform-agnostic; the standalone ColorPicker wraps
    // a plain Button + QtQuick.Dialogs.ColorDialog instead of
    // KQuickControls.ColorButton (Plasma side).
    Component {
        id: colorPickerComponent
        ColorPicker {}
    }

    // Autostart helper — manages ~/.config/autostart/<id>.desktop.
    // Wired into AboutBody so the "Start automatically on login"
    // toggle reads its current state and writes back on user click.
    // Plasma users don't see this toggle (plasmashell handles it
    // via the panel layout); AboutBody gates the row on
    // `autostartAvailable`, which only this side sets to true.
    //
    // Load-bearing for #126/#136: this dialog is constructed eagerly by
    // both standalone roots (Main.qml + SettingsOnlyRoot.qml), so building
    // it also builds Autostart on every startup — and Autostart's ctor
    // self-heals a stale Exec= AND kicks the async stable-copy refresh
    // after an AppImage update. If this dialog is ever made lazy (a
    // Loader), both stop firing on launch; restore an explicit startup
    // refresh then (refreshIfStale + ensureStableCopyAsync, see
    // standalone/desktop_entry.h).
    Autostart {
        id: autostartHelper
    }

    // Menu-entry helper — manages ~/.local/share/applications/<id>.desktop.
    // Wired into AboutBody so "Show in application menu" reflects and
    // writes the launcher state. Plasma users get a menu entry from the
    // .plasmoid install, so AboutBody gates the row on
    // `menuEntryAvailable`, which only this side sets to true.
    MenuEntry {
        id: menuEntryHelper
    }

    // ── Layout ──────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing

        QQC2.TabBar {
            id: tabBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            QQC2.TabButton {
                text: qsTr("Metrics")
            }
            QQC2.TabButton {
                text: qsTr("Appearance")
            }
            QQC2.TabButton {
                text: qsTr("About")
            }
        }

        StackLayout {
            anchors.top: tabBar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Kirigami.Units.smallSpacing
            currentIndex: tabBar.currentIndex

            // ScrollView.availableWidth is content-area width minus
            // the vertical scrollbar — the idiomatic input for a
            // single-child Flickable body's `width`. The previous
            // `parent.parent.width` walked through ScrollView's
            // internal Flickable to read StackLayout.width, which
            // Qt has reorganised across 6.x point releases (e.g.
            // QQC2 ScrollView's internal hierarchy changed in 6.4
            // → 6.5). Bind to the documented public property
            // instead so a future Qt shuffle doesn't silently break
            // the widths.
            QQC2.ScrollView {
                id: metricsScroll
                Core.MetricsBody {
                    id: metricsBody
                    theme: dialog.theme
                    colorPickerComponent: colorPickerComponent
                    // Actual shared ring color so an un-overridden partition's
                    // swatch previews what the ring shows (issue #67).
                    sharedRingColor: dialog.configStore && dialog.theme ? ColorThemes.resolveSharedRingColor(dialog.configStore.colorTheme, dialog.configStore.colorMode, dialog.theme.isDarkMode, dialog.theme.highlightColor, dialog.configStore.customColorLight, dialog.configStore.customColorDark) : ColorThemes.DEFAULT_HIGHLIGHT
                    diskPartitions: dialog._diskPartitions
                    removablePartitions: dialog._removablePartitions
                    defaultPartitionIds: dialog._defaultPartitionIds
                    availableMetrics: dialog.availableMetrics
                    // Standalone discovery (_refreshDiskPartitions) is synchronous
                    // and complete in one shot — no incremental enumeration, so
                    // discovery is trustworthy immediately (no debounce needed).
                    partitionsReady: true
                    width: metricsScroll.availableWidth
                }
            }

            QQC2.ScrollView {
                id: appearanceScroll
                Core.AppearanceBody {
                    id: appearanceBody
                    width: appearanceScroll.availableWidth
                    colorPickerComponent: colorPickerComponent
                    // Only the standalone host shows these controls:
                    //
                    //   window placement (anchor corner + X/Y margins)
                    //   is consumed by the standalone Window anchoring
                    //   code only (plasmashell positions the Plasma panel
                    //   slot itself).
                    //
                    //   `ringSpacing` IS read on both hosts, but on
                    //   Plasma the desktop frame is user-dragged-fixed
                    //   and rings shrink to compensate — the visible
                    //   effect is dominated by the frame, not the
                    //   spacing. On standalone the Window auto-sizes
                    //   to rings × count + spacings, so the slider
                    //   has obvious visual feedback.
                    //
                    //   `ringSize` likewise drives the rings' implicit
                    //   size; on the Plasma desktop containment the
                    //   dragged frame overrides it (slider looks inert
                    //   once placed), but the standalone Window
                    //   auto-sizes to it, so the slider is meaningful.
                    //
                    // Same gate convention as `autostartAvailable` on
                    // AboutBody.
                    windowPlacementVisible: true
                    ringSpacingVisible: true
                    ringSizeVisible: true
                }
            }

            QQC2.ScrollView {
                id: aboutScroll
                Core.AboutBody {
                    id: aboutBody
                    width: aboutScroll.availableWidth
                    localVersion: dialog.configStore ? dialog.configStore.localVersion : ""
                    remoteVersion: dialog.updateChecker ? dialog.updateChecker.remoteVersion : ""
                    updateAvailable: dialog.updateChecker ? dialog.updateChecker.updateAvailable : false
                    checkForUpdatesEnabled: dialog.configStore ? dialog.configStore.checkForUpdatesEnabled : true
                    autostartAvailable: true
                    autostartEnabled: autostartHelper.enabled
                    menuEntryAvailable: true
                    menuEntryEnabled: menuEntryHelper.enabled

                    onAcknowledgeClicked: dialog.updateChecker && dialog.updateChecker.acknowledge()
                    onOpenStorePageClicked: dialog.updateChecker && dialog.updateChecker.openStorePage()
                    onCheckForUpdatesToggled: on => {
                        if (dialog.configStore)
                            dialog.configStore.checkForUpdatesEnabled = on;
                    }
                    onAutostartToggled: on => autostartHelper.setEnabled(on)
                    onMenuEntryToggled: on => menuEntryHelper.setEnabled(on)
                }
            }
        }
    }

    // ── Two-way binding wiring ──────────────────────────────────────
    //
    // Each entry is [body, bodyProp, storeProp]. storeProp defaults
    // to bodyProp when it's the same on both sides; the two CSV
    // properties on MetricsBody have to declare the rename
    // explicitly. The list is the single source of truth — adding a
    // new persisted key means appending one line here AND declaring
    // it in ConfigStore.qml (the standalone-config-store.test.mjs
    // guard catches drift between main.xml and ConfigStore but does
    // not catch drift between ConfigStore and this dialog — see the
    // standalone-settings-dialog.test.mjs text guard for that).
    //
    // Pull order is load-bearing for partitionLabels: it must come
    // AFTER the partition CSVs. Its change handler resyncs the staged
    // label cache (MetricsBody._stagedLabelsJson) from the saved value,
    // clobbering any merge the CSV pulls just triggered; the dialog's
    // show-refresh (_refreshDiskPartitions) re-merges discovery right
    // after wiring, which only heals the staged copy because labels
    // were pulled last (issue #132 staging seam).
    readonly property var _bridgeMap: [
        // MetricsBody
        [metricsBody, "metricOrderCsv", "metricOrder"], [metricsBody, "enabledMetricsCsv", "enabledMetrics"], [metricsBody, "enabledPartitionsCsv", "enabledPartitions"], [metricsBody, "partitionOrderCsv", "partitionOrder"], [metricsBody, "partitionLabelsJson", "partitionLabels"], [metricsBody, "partitionOptOutCsv", "partitionOptOut"], [metricsBody, "partitionColorsJson", "diskPartitionColors"], [metricsBody, "showCpuCores", "showCpuCores"], [metricsBody, "mergeCpuTemp", "mergeCpuTemp"], [metricsBody, "mergeGpuTemp", "mergeGpuTemp"], [metricsBody, "splitDiskIo", "splitDiskIo"], [metricsBody, "tempUnit", "tempUnit"],
        // AppearanceBody
        [appearanceBody, "orientation", "orientation"], [appearanceBody, "ringSize", "ringSize"], [appearanceBody, "ringSpacingPercent", "ringSpacingPercent"], [appearanceBody, "windowAnchorCorner", "windowAnchorCorner"], [appearanceBody, "windowMarginX", "windowMarginX"], [appearanceBody, "windowMarginY", "windowMarginY"], [appearanceBody, "windowScreen", "windowScreen"], [appearanceBody, "textOpacity", "textOpacity"], [appearanceBody, "trackOpacity", "trackOpacity"], [appearanceBody, "arcOpacity", "arcOpacity"], [appearanceBody, "colorTheme", "colorTheme"], [appearanceBody, "colorMode", "colorMode"], [appearanceBody, "customColorLight", "customColorLight"], [appearanceBody, "customColorDark", "customColorDark"], [appearanceBody, "textColorMode", "textColorMode"], [appearanceBody, "customTextColorLight", "customTextColorLight"], [appearanceBody, "customTextColorDark", "customTextColorDark"]]

    function _wireBridges() {
        if (!dialog.configStore)
            return;
        for (let i = 0; i < _bridgeMap.length; i++) {
            let body = _bridgeMap[i][0];
            let bodyProp = _bridgeMap[i][1];
            let storeProp = _bridgeMap[i][2];
            // 1. Initial pull from the store.
            body[bodyProp] = dialog.configStore[storeProp];
            // 2. Write-back on body change. Closing over loop vars via
            //    an IIFE so each handler captures its own pair.
            (function (b, bp, sp) {
                    b[bp + "Changed"].connect(function () {
                        dialog.configStore[sp] = b[bp];
                    });
                })(body, bodyProp, storeProp);
        }
        // MetricsBody needs an explicit loadOrder() after metricOrderCsv
        // is set — that's what populates the displayed ListModel.
        metricsBody.loadOrder();
    }
}
