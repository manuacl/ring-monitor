#include "proc_reader.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QPointer>
#include <QTextStream>

#include <sys/statvfs.h>

#include <thread>

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
    // The bare roots "/proc" and "/sys" are allowed (cleanPath strips the
    // trailing slash, so "/proc/" arrives as "/proc" and would miss the
    // "/proc/" prefix test): process enumeration for the CPU-ring tooltip
    // needs to list "/proc" itself to discover the pid dirs (#69). Both
    // roots are still ls-able by the user, same as the deeper paths.
    const QString cleaned = QDir::cleanPath(path);
    if (cleaned != QStringLiteral("/proc") && cleaned != QStringLiteral("/sys") &&
        !cleaned.startsWith(QStringLiteral("/proc/")) &&
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

// The blocking syscall, factored out as a free function so the async
// worker thread can call it without dereferencing the (possibly
// destroyed) ProcReader. It touches no member state, so it's safe to
// run off the GUI thread.
//
// No allowlist on this side: `statvfs(3)` is a filesystem-metadata
// probe (size / free / available) and `df -h /any/path` from the
// user's terminal returns the same numbers. The asymmetry with
// `read()` is intentional — `read()` has an allowlist to keep
// the documented "only /proc and /sys" contract honest, not as a
// security boundary.
static QVariantMap statvfsBytes(const QString &path)
{
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

QVariantMap ProcReader::statvfs(const QString &path) const
{
    return statvfsBytes(path);
}

void ProcReader::requestStatvfs(const QString &mount)
{
    if (mount.isEmpty() || m_statvfsInFlight.contains(mount))
        return; // dedup: a worker is already (or still) reading this mount

    const qint64 now = m_clock.elapsed();
    const auto last = m_statvfsLastDoneMs.constFind(mount);
    if (last != m_statvfsLastDoneMs.constEnd() && now - last.value() < kStatvfsMinIntervalMs)
        return; // throttle: refreshed too recently to bother re-reading

    m_statvfsInFlight.insert(mount);

    // Detached worker: blocks in statvfs() off the GUI thread, then hops
    // the result back via the event loop. The QPointer guards the rare
    // case of ProcReader being torn down before the queued call runs
    // (checked on the GUI thread, where the object also lives — no data
    // race). The result is delivered through the live QCoreApplication
    // instance: re-read it inside the worker and bail if it's gone, so a
    // worker that finishes mid-shutdown (qApp already destroyed) drops the
    // result instead of dereferencing a null context.
    QPointer<ProcReader> self(this);
    try {
        std::thread([self, mount]() {
            const QVariantMap result = statvfsBytes(mount);
            QCoreApplication *app = QCoreApplication::instance();
            if (!app)
                return; // app tearing down — process is exiting, drop the result
            QMetaObject::invokeMethod(app, [self, mount, result]() {
                if (self)
                    self->onStatvfsDone(mount, result);
            });
        }).detach();
    } catch (const std::system_error &) {
        // Thread creation failed (resource/FD exhaustion). Clear the
        // in-flight flag so the mount is retried next tick rather than
        // stuck forever, and never let the exception unwind into the QML
        // binding evaluation that called this Q_INVOKABLE.
        m_statvfsInFlight.remove(mount);
    }
}

void ProcReader::onStatvfsDone(const QString &mount, const QVariantMap &result)
{
    m_statvfsInFlight.remove(mount);
    m_statvfsCache.insert(mount, result);
    m_statvfsLastDoneMs.insert(mount, m_clock.elapsed());
    emit statvfsReady(mount);
}

QVariantMap ProcReader::cachedStatvfs(const QString &mount) const
{
    return m_statvfsCache.value(mount);
}

// udev escapes characters that are not safe in a /dev path (spaces,
// slashes, …) as `\xNN` hex in the by-uuid / by-label symlink names.
// Decode them back so a label like "My Disk" shows with its space
// rather than "My\x20Disk".
static QString decodeUdevName(const QString &name)
{
    QString out;
    out.reserve(name.size());
    for (int i = 0; i < name.size(); ++i) {
        if (name[i] == QLatin1Char('\\') && i + 3 < name.size() && name[i + 1] == QLatin1Char('x')) {
            bool ok = false;
            const int code = QStringView(name).mid(i + 2, 2).toInt(&ok, 16);
            if (ok) {
                out.append(QChar(code));
                i += 3;
                continue;
            }
        }
        out.append(name[i]);
    }
    return out;
}

QVariantMap ProcReader::blockDeviceInfo() const
{
    // Metadata-only, no allowlist — same rationale as statvfs(). We walk
    // the /dev/disk symlink farm and resolve each link to its device path,
    // building device → { uuid, label }. The by-uuid pass runs first so a
    // device that also has a label ends up with both keys.
    QVariantMap out;
    const struct {
        const char *dir;
        const char *key;
    } sources[] = {
        { "/dev/disk/by-uuid", "uuid" },
        { "/dev/disk/by-label", "label" },
    };
    for (const auto &src : sources) {
        QDir dir(QString::fromLatin1(src.dir));
        if (!dir.exists())
            continue;
        const QStringList names = dir.entryList(QDir::NoDotAndDotDot | QDir::AllEntries | QDir::System);
        for (const QString &name : names) {
            const QString device = QFileInfo(dir.absoluteFilePath(name)).canonicalFilePath();
            if (device.isEmpty())
                continue;
            QVariantMap info = out.value(device).toMap();
            info.insert(QString::fromLatin1(src.key), decodeUdevName(name));
            out.insert(device, info);
        }
    }
    return out;
}

QString ProcReader::canonicalHome() const
{
    return QFileInfo(QDir::homePath()).canonicalFilePath();
}
