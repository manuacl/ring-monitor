#include "autostart.h"

#include "desktop_entry.h"

#include <QFileInfo>
#include <QStandardPaths>

Autostart::Autostart(QObject *parent) : QObject(parent) {}

QString Autostart::desktopFilePath() const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
                        + QStringLiteral("/autostart");
    return dir + QLatin1Char('/') + QLatin1String(desktop_entry::kDesktopFileName);
}

QString Autostart::buildDesktopFileContent() const
{
    return QStringLiteral("[Desktop Entry]\n"
                          "Type=Application\n"
                          "Name=Ring Monitor\n"
                          "Comment=Modern minimal circular system monitor\n"
                          "Exec=%1\n"
                          "Icon=utilities-system-monitor\n"
                          "Categories=System;Monitor;\n"
                          "X-GNOME-Autostart-enabled=true\n")
        .arg(desktop_entry::execLine());
}

bool Autostart::isEnabled() const
{
    return QFileInfo::exists(desktopFilePath());
}

void Autostart::setEnabled(bool on)
{
    const QString path = desktopFilePath();
    const bool wasEnabled = QFileInfo::exists(path);
    if (on == wasEnabled)
        return;

    if (on)
        desktop_entry::writeDesktopFile(path, buildDesktopFileContent());
    else
        desktop_entry::removeDesktopFile(path);

    // Emit regardless of write success so an observer (the Settings
    // checkbox) re-syncs to the real on-disk state — a failed write must
    // not leave the toggle showing "enabled". Shared shape with MenuEntry.
    Q_EMIT enabledChanged();
}
