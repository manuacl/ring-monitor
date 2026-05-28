#pragma once

// Tiny QML-callable helper for reading text files from the standalone
// build (currently used to pull `/proc/stat`, `/proc/meminfo`, etc.).
//
// Why a C++ helper instead of QML's XMLHttpRequest with `file://`:
// since Qt 6.5 only the file scheme is exposed and the QML loading
// context has to itself live under file:// for the read to be
// allowed. Our QML is loaded from the compiled qrc:// resource (via
// `qt_add_qml_module` + `loadFromModule`), so file:// XHR is
// blocked. A dedicated `Q_INVOKABLE` doesn't carry that restriction.
//
// Registered to QML via the `QML_ELEMENT` macro picked up by
// `qt_add_qml_module(... SOURCES proc_reader.cpp …)`. Available in
// QML as `import RingMonitor.Standalone; ProcReader { id: reader }`.

#include <QElapsedTimer>
#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QtQmlIntegration/QtQmlIntegration>

// Lives at global scope rather than in `ringmonitor::` because
// Qt 6's `QML_ELEMENT` auto-registration generates code calling
// `qmlRegisterTypesAndRevisions<ProcReader>(…)` without
// namespace-qualifying the type — a namespaced class needs
// `QML_FOREIGN_NAMESPACE` boilerplate to register cleanly. The
// helper is a thin one-method utility, so the lower-friction
// global-scope path is the right trade-off.

class ProcReader : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit ProcReader(QObject *parent = nullptr) : QObject(parent)
    {
        // Monotonic clock backing the per-mount throttle in
        // requestStatvfs(). Started here so the first request always
        // sees an elapsed() well past the throttle window.
        m_clock.start();
    }

    // Synchronous read. Returns the file contents on success, an
    // empty string on any failure (missing file, no read permission,
    // I/O error, **or path outside the `/proc/` / `/sys/` allowlist
    // after `QDir::cleanPath` normalises `..`**). Callers (typically
    // a `Timer.onTriggered` in QML) are expected to tolerate empty /
    // partial input — the `ProcStatParser` helpers in `core/` do.
    //
    // The widget runs as the user, so this isn't a privilege boundary:
    // any file `reader.read(...)` could return is also a file the
    // user can `cat` directly. The allowlist exists to keep the QML
    // side honest at dev time — a typo'd path emits `qWarning` instead
    // of silently leaking unrelated data. See `proc_reader.cpp` for
    // the full rationale.
    Q_INVOKABLE QString read(const QString &path) const;

    // statvfs(3) wrapper. Returns { "total": <bytes>, "free":
    // <bytes>, "available": <bytes> } on success; empty map on any
    // failure (path missing, not mounted, EACCES). All three fields
    // are in bytes (`f_X * f_frsize`):
    //   - `total`     = f_blocks (filesystem-wide size, includes
    //                   root reservation)
    //   - `free`      = f_bfree  (all unused blocks, including the
    //                   root reservation)
    //   - `available` = f_bavail (unused blocks reachable by an
    //                   unprivileged user; matches `df`'s "Avail")
    //
    // Both `free` and `available` are exposed so QML can compute
    // df(1)'s "Use%" formula `(total - free) / (total - free +
    // available)` via `MemInfoParser.diskUsagePercent`. The naive
    // `(total - available) / total` would count the ~5% ext4 root
    // reservation as "used" and report a non-zero usage on a
    // freshly-formatted empty filesystem.
    Q_INVOKABLE QVariantMap statvfs(const QString &path) const;

    // Async, non-blocking counterpart of statvfs() for the disk
    // multi-partition rings. The synchronous statvfs() above blocks
    // (uninterruptibly) on an unresponsive mount — a stale NFS/CIFS
    // export, a hung autofs, a spun-down removable disk — so calling
    // it from the 2 Hz `_sample` tick froze the GUI thread for the
    // syscall's duration (issue #48). These two move the syscall off
    // the render thread:
    //
    //   - requestStatvfs(mount) kicks a background read on a detached
    //     worker thread and returns immediately. Idempotent: a mount
    //     already in flight is not re-launched (so a hung mount freezes
    //     exactly one worker, never a pile), and a mount refreshed
    //     within kStatvfsMinIntervalMs is skipped (so re-evaluating the
    //     QML binding every render doesn't spin the syscall). When the
    //     read finishes the result is cached and statvfsReady(mount) is
    //     emitted on the GUI thread.
    //   - cachedStatvfs(mount) returns the last-good result (same
    //     { total, free, available } shape as statvfs()), or an empty
    //     map until the first read for that mount lands. Never blocks.
    //
    // The QML side calls requestStatvfs() + cachedStatvfs() from
    // partitionValue() and bumps a tick on statvfsReady to re-render —
    // an unresponsive mount then just holds its last-good ring value
    // instead of freezing the whole widget.
    //
    // The worker thread is detached (not pooled): a QThreadPool's dtor
    // waitForDone() would block process exit forever on a mount stuck
    // in an uninterruptible statvfs. A detached thread is reaped by the
    // OS at exit instead — so quitting the widget never hangs even with
    // a dead NFS export selected.
    Q_INVOKABLE void requestStatvfs(const QString &mount);
    Q_INVOKABLE QVariantMap cachedStatvfs(const QString &mount) const;

    // Directory listing. Returns the entry names (not full paths) of
    // `path` — both subdirectories and files, excluding `.` and `..` —
    // on success; an empty list on any failure (missing directory, no
    // permission, **or path outside the `/proc/` / `/sys/` allowlist
    // after `QDir::cleanPath`**). Same dev-time-sanity rationale and
    // allowlist as `read()`: the widget runs as the user, so `ls`
    // reaches the same entries — the guard just keeps a typo'd path
    // greppable instead of silently enumerating elsewhere.
    //
    // Exists for CPU-temperature discovery: the sysfs path of the CPU
    // sensor is not fixed (the `hwmonN` numbering and which chip owns
    // the CPU temperature both vary by machine), so the QML side
    // enumerates `/sys/class/hwmon` + `/sys/class/thermal` and resolves
    // the right `tempN_input` through the pure `CpuTempDiscovery`
    // helpers in `core/`. Reused later by GPU discovery (`/sys/class/drm`).
    Q_INVOKABLE QStringList listDir(const QString &path) const;

    // Block-device identity map for the disk multi-partition selector.
    // Returns { "<device-path>": { "uuid": <fs-uuid>, "label": <volume
    // label> }, … } by enumerating /dev/disk/by-uuid + /dev/disk/by-label
    // and resolving each symlink to its device (e.g. /dev/sda3). A device
    // with no label simply omits the "label" key. Empty map on any failure.
    //
    // Used by DiskDiscovery.js to give each mounted filesystem a stable id
    // (the UUID, matching ksysguard's Plasma-side keying) and a friendly
    // label (the volume label, e.g. "bazzite") instead of a raw mountpoint.
    //
    // Metadata-only (like statvfs): no read() allowlist. It enumerates the
    // /dev/disk symlink farm — the same listing `ls -l /dev/disk/by-label`
    // gives any user — and resolves to device paths, not file contents.
    Q_INVOKABLE QVariantMap blockDeviceInfo() const;

    // Canonical (symlink-resolved) path of the user's home directory.
    // On rpm-ostree hosts $HOME is /home/<user>, a symlink to
    // /var/home/<user>; DiskDiscovery needs the resolved path to match
    // it against the real mountpoints in /proc/mounts when picking the
    // default partition. Empty string if home can't be resolved.
    Q_INVOKABLE QString canonicalHome() const;

signals:
    // Emitted on the GUI thread once an async requestStatvfs(mount)
    // completes and its cached value has been updated.
    void statvfsReady(const QString &mount);

private:
    // Runs on the GUI thread (posted from the worker via
    // QMetaObject::invokeMethod): commit the cache, clear the in-flight
    // flag, stamp the throttle clock, and emit statvfsReady.
    void onStatvfsDone(const QString &mount, const QVariantMap &result);

    // Mounts with a worker thread currently blocked in statvfs() — used
    // to dedup requests so a hung mount can't accumulate threads.
    QSet<QString> m_statvfsInFlight;
    // Last-good { total, free, available } per mount.
    QHash<QString, QVariantMap> m_statvfsCache;
    // elapsed() ms of the last completed read per mount (throttle gate).
    QHash<QString, qint64> m_statvfsLastDoneMs;
    QElapsedTimer m_clock;
    // Minimum spacing between two real reads of the same mount. Below
    // the 500 ms poll Timer so each tick still refreshes, but high
    // enough that a statvfsReady-driven re-render doesn't re-launch.
    static constexpr int kStatvfsMinIntervalMs = 250;
};
