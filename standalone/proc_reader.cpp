#include "proc_reader.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QTextStream>

#include <sys/statvfs.h>

QString ProcReader::read(const QString &path) const
{
    // Allowlist guard. `Q_INVOKABLE` exposes this method to every QML
    // context, and the QML side is on a hot-reload path during dev.
    // The widget runs as the user (not root), so this is not a
    // privilege boundary — the file-read surface is whatever the
    // user could already `cat`. The allowlist exists to keep the
    // QML side honest: a dev-time typo like `reader.read("/etc/passwd")`
    // fails fast and greppably (`qWarning`) instead of silently
    // returning data; the comment in the header doesn't lie about
    // what's reachable. The legitimate callers per the standalone
    // `CLAUDE.md` are `/proc/stat` and `/proc/meminfo`; `/sys/` is
    // reserved for upcoming hwmon sensors.
    //
    // `QDir::cleanPath` normalises `..` lexically before the prefix
    // check so the allowlist applies to the *resolved* path. Without
    // it, `reader.read("/proc/../etc/passwd")` would pass the prefix
    // gate and the kernel would resolve to `/etc/passwd` — the
    // comment claiming the allowlist blocks that would be a lie.
    // No `realpath(3)` / symlink resolution: this is a dev-time sanity
    // check, not a sandbox.
    const QString cleaned = QDir::cleanPath(path);
    if (!cleaned.startsWith(QStringLiteral("/proc/")) &&
        !cleaned.startsWith(QStringLiteral("/sys/"))) {
        qWarning() << "ProcReader::read refused path outside /proc/ or "
                      "/sys/ allowlist (after cleanPath):"
                   << path;
        return {};
    }
    QFile file(cleaned);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    QTextStream stream(&file);
    return stream.readAll();
}

QStringList ProcReader::listDir(const QString &path) const
{
    // Same allowlist + cleanPath rationale as read() above — this is a
    // dev-time sanity check, not a privilege boundary (the widget runs
    // as the user; `ls /sys/...` reaches the same entries). Refusing a
    // path outside /proc//sys keeps a QML typo greppable in the journal.
    const QString cleaned = QDir::cleanPath(path);
    if (!cleaned.startsWith(QStringLiteral("/proc/")) &&
        !cleaned.startsWith(QStringLiteral("/sys/"))) {
        qWarning() << "ProcReader::listDir refused path outside /proc/ or "
                      "/sys/ allowlist (after cleanPath):"
                   << path;
        return {};
    }
    QDir dir(cleaned);
    if (!dir.exists())
        return {};
    // AllEntries follows symlinks (the hwmonN / thermal_zoneN entries
    // under /sys/class/* are symlinks into the device tree), so they
    // surface as dirs; the tempN_input files surface as files.
    return dir.entryList(QDir::AllEntries | QDir::NoDotAndDotDot);
}

QVariantMap ProcReader::statvfs(const QString &path) const
{
    // No allowlist on this side: `statvfs(3)` is a filesystem-metadata
    // probe (size / free / available) and `df -h /any/path` from the
    // user's terminal returns the same numbers. The asymmetry with
    // `read()` is intentional — `read()` has an allowlist to keep
    // the documented "only /proc and /sys" contract honest, not as a
    // security boundary. If a future per-mount selector lands, the
    // input still goes through `realpath(3)` on the QML side for
    // display purposes (see standalone/CLAUDE.md "Disk metric")
    // rather than via a syscall-side allowlist.
    struct ::statvfs s;
    if (::statvfs(path.toLocal8Bit().constData(), &s) != 0)
        return {};
    // f_bfree (all free blocks, including root-reserved) is exposed
    // alongside f_blocks and f_bavail so the QML side can compute
    // df(1)'s "Use%" formula — (blocks - bfree) / (blocks - bfree +
    // bavail) — instead of the naive (blocks - bavail) / blocks
    // which counts the root reservation as "used" and reports ~5%
    // used on a freshly-formatted empty ext4 root. See
    // MemInfoParser.diskUsagePercent.
    return {
        { QStringLiteral("total"),     static_cast<qulonglong>(s.f_blocks) * s.f_frsize },
        { QStringLiteral("free"),      static_cast<qulonglong>(s.f_bfree)  * s.f_frsize },
        { QStringLiteral("available"), static_cast<qulonglong>(s.f_bavail) * s.f_frsize },
    };
}
