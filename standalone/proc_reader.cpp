#include "proc_reader.h"

#include <QFile>
#include <QTextStream>

#include <sys/statvfs.h>

QString ProcReader::read(const QString &path) const
{
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
    return {
        { QStringLiteral("total"),     static_cast<qulonglong>(s.f_blocks) * s.f_frsize },
        { QStringLiteral("available"), static_cast<qulonglong>(s.f_bavail) * s.f_frsize },
    };
}
