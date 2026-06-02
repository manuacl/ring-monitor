import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "MountInfo.js" as MountInfo
import "../../core/DiskMetrics.js" as DiskMetrics

// Plasma adapter: the live set of mounted filesystems, with removable
// classification — the data ksysguard does NOT provide (it exposes only the
// volume label + usedPercent per UUID, no mountpoint, no removable flag).
//
// We get it by running `findmnt` through plasma5support's executable
// DataSource. findmnt's UUID is exactly ksysguard's disk/<uuid> key, so a
// consumer can join this onto the per-partition sensors to know which
// partitions are removable (and currently mounted) without reopening Settings.
//
// Reading mount state ourselves also sidesteps issue #58: the long-lived
// ksysguard SensorTreeModel freezes on unmount (no rowsRemoved, status stays
// Ready, a re-walk still lists the gone UUID), whereas re-running findmnt always
// reflects reality — so this set self-heals on unplug. findmnt reads the kernel
// mount table, so it lists every mount (including btrfs subvolumes lsblk's
// singular MOUNTPOINT can miss); that completeness is what lets the consumer
// gate trust "absent here ⇒ unmounted" without dropping a still-mounted disk.
//
// Why a subprocess and not a file read: QML XMLHttpRequest on file:///proc/...
// is blocked in plasmashell, and there is no org.kde.solid QML import on the
// target. plasma5support's executable engine is the remaining native path. The
// command is bare (`findmnt`, no hardcoded directory) on purpose — the engine
// runs it with the session PATH, so pinning an absolute path would only hurt
// portability across distros (the no-absolute-path rule). If findmnt isn't
// installed the source is simply empty and the fixed disks (driven by
// ksysguard) are unaffected.
//
// Public surface:
//   readonly property var mounted  - [{uuid, label, mountpoint, fstype, removable}],
//                                    one per mounted filesystem with a UUID.
//   property int pollMs            - re-scan cadence (unplug-detection latency).
//   property bool active           - when false the poll Timer is stopped, so no
//                                    subprocess runs. The consumer gates this on
//                                    "is the disk ring actually on screen" so a
//                                    collapsed / disk-disabled widget spawns
//                                    nothing (#59 review finding 1).

Item {
    id: root

    readonly property var mounted: _mounted
    property var _mounted: []
    property int pollMs: 2000
    property bool active: true

    // Drop the last-good set when tracking is turned off, so a removable
    // unplugged WHILE the disk ring was disabled can't briefly resurface as a
    // ghost ring on re-enable (the Timer's triggeredOnStart re-scan is async, so
    // without this the stale UUID would render for the round-trip window).
    // Distinct from the keep-last-good-on-failed-run guard in onNewData (#59
    // finding 2): that holds across a transient error mid-polling; this clears on
    // an explicit deactivation, where the re-scan on reactivation refills it.
    onActiveChanged: if (!root.active)
        root._mounted = []

    // `-P` (key="value" pairs) is robust against spaces in label / target.
    // FSTYPE feeds the disk-ring tooltip's per-partition fs label (#68).
    readonly property string _command: "findmnt -P -o UUID,TARGET,LABEL,FSTYPE"

    P5Support.DataSource {
        id: mountSource
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            mountSource.disconnectSource(source); // one-shot per poll
            // A failed run (findmnt missing, a transient error mid hotplug)
            // comes back with a nonzero exit and empty stdout — don't let that
            // wipe the last-good set to [] and blink every removable ring away
            // for a cycle. A genuine "nothing mounted" can't happen (there is
            // always a root mount), and findmnt's listing mode exits 0.
            if (data["exit code"] !== 0)
                return;
            var rows = MountInfo.parseMountPairs(data["stdout"] || "");
            var next = rows.map(function (r) {
                return {
                    "uuid": r.uuid,
                    "label": r.label,
                    "mountpoint": r.mountpoint,
                    "fstype": r.fstype,
                    "removable": DiskMetrics.isRemovableMount(r.mountpoint)
                };
            });
            if (JSON.stringify(next) !== JSON.stringify(root._mounted))
                root._mounted = next;
        }
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: root.active
        triggeredOnStart: true // re-scan immediately when tracking (re)activates
        onTriggered: mountSource.connectSource(root._command)
    }
}
