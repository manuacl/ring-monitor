#include "proc_reader.h"

#include <QFile>
#include <QTextStream>

QString ProcReader::read(const QString &path) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    QTextStream stream(&file);
    return stream.readAll();
}
