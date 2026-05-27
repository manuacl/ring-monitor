#include "proc_reader.h"

#include <QDebug>
#include <QFile>
#include <QTextStream>

#include <sys/statvfs.h>

QString ProcReader::read(const QString &path) const
{
    // Allowlist guard. `Q_INVOKABLE` exposes this method to every QML
    // context in the standalone build, and the QML side is on a hot
    // reload path during development — a future leaf component that
    // forgot the surface is wide could turn this into a free
    // `cat /etc/shadow` if it ran as root, or just exfiltrate arbitrary
    // user-readable files. The only legitimate callers per the
    // standalone `CLAUDE.md` are `/proc/stat` and `/proc/meminfo`;
    // `/sys/` is reserved for upcoming temperature / battery sensors.
    if (!path.startsWith(QStringLiteral("/proc/")) &&
        !path.startsWith(QStringLiteral("/sys/"))) {
        qWarning() << "ProcReader::read refused path outside /proc/ or "
                      "/sys/ allowlist:"
                   << path;
        return {};
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    QTextStream stream(&file);
    return stream.readAll();
}

QVariantMap ProcReader::statvfs(const QString &path) const
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
