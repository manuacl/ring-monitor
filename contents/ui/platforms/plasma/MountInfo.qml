import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "MountInfo.js" as MountInfo
import "../../core/DiskMetrics.js" as DiskMetrics

// Plasma adapter: the live set of mounted filesystems, with removable
// classification — the data ksysguard does NOT provide (it exposes only the
// volume label + usedPercent per UUID, no mountpoint, no removable flag).
//
// We get it by running `lsblk` through plasma5support's executable
// DataSource. lsblk's UUID is exactly ksysguard's disk/<uuid> key, so a
// consumer can join this onto the per-partition sensors to know which
// partitions are removable (and currently mounted) without reopening Settings.
//
// Reading mount state ourselves also sidesteps issue #58: the long-lived
// ksysguard SensorTreeModel freezes on unmount (no rowsRemoved, status stays
// Ready, a re-walk still lists the gone UUID), whereas re-running lsblk always
// reflects reality — so this set self-heals on unplug.
//
// Why a subprocess and not a file read: QML XMLHttpRequest on file:///proc/...
// is blocked in plasmashell, and there is no org.kde.solid QML import on the
// target. plasma5support's executable engine is the remaining native path. The
// command is bare (`lsblk`, no hardcoded directory) on purpose — the engine
// runs it with the session PATH, so pinning an absolute path would only hurt
// portability across distros (the no-absolute-path rule). If lsblk isn't
// installed the source is simply empty and the fixed disks (driven by
// ksysguard) are unaffected.
//
// Public surface:
//   readonly property var mounted  - [{uuid, label, mountpoint, removable}],
//                                    one per mounted filesystem with a UUID.
//   property int pollMs            - re-scan cadence (unplug-detection latency).

Item {
    id: root

    readonly property var mounted: _mounted
    property var _mounted: []
    property int pollMs: 2000

    // `-P` (key="value" pairs) is robust against spaces in label / mountpoint.
    readonly property string _command: "lsblk -P -o UUID,MOUNTPOINT,LABEL"

    P5Support.DataSource {
        id: lsblk
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            lsblk.disconnectSource(source); // one-shot per poll
            // A failed run (lsblk missing, a transient udev/sysfs error mid
            // hotplug) comes back with a nonzero exit and empty stdout — don't
            // let that wipe the last-good set to [] and blink every removable
            // ring away for a cycle. A genuine "nothing mounted" still exits 0.
            if (data["exit code"] !== 0)
                return;
            var rows = MountInfo.parseLsblkPairs(data["stdout"] || "");
            var next = rows.map(function (r) {
                return {
                    "uuid": r.uuid,
                    "label": r.label,
                    "mountpoint": r.mountpoint,
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
        running: true
        triggeredOnStart: true
        onTriggered: lsblk.connectSource(root._command)
    }
}
