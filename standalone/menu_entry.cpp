#include "menu_entry.h"

#include "desktop_entry.h"

#include <QFileInfo>
#include <QStandardPaths>

MenuEntry::MenuEntry(QObject *parent) : QObject(parent)
{
    // Self-heal a stale launcher: if the AppImage was moved / re-downloaded
    // to a new path, the stored Exec= no longer matches and the menu entry
    // would silently launch a dead path. Rewriting it on construction (the
    // Settings dialog instantiates us) refreshes Exec= to the current
    // binary with no user action — closes the "toggle claims healthy while
    // broken" trap. No-op when the file is absent or already current.
    desktop_entry::refreshIfStale(desktopFilePath(), buildDesktopFileContent());
}

QString MenuEntry::desktopFilePath() const
{
    // XDG: per-user application launchers live under
    // $XDG_DATA_HOME/applications (writableLocation(ApplicationsLocation)
    // resolves to ~/.local/share/applications on a default profile).
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);
    return dir + QLatin1Char('/') + QLatin1String(desktop_entry::kDesktopFileName);
}

QString MenuEntry::buildDesktopFileContent() const
{
    // Icon=utilities-system-monitor is a stock freedesktop icon name —
    // same choice as the autostart entry, so no icon file has to be
    // extracted from the AppImage and cleaned up on removal.
    //
    // StartupWMClass ties the launched window back to this entry so the
    // taskbar groups it under the launcher icon. The standalone window's
    // WM_CLASS is the binary basename (the value the docs' KWin window
    // rule matches); a non-matching StartupWMClass is simply ignored by
    // the shell, so this only ever helps.
    return QStringLiteral("[Desktop Entry]\n"
                          "Type=Application\n"
                          "Name=Ring Monitor\n"
                          "Comment=Modern minimal circular system monitor\n"
                          "Exec=%1\n"
                          "Icon=utilities-system-monitor\n"
                          "Categories=System;Monitor;\n"
                          "Terminal=false\n"
                          "StartupWMClass=ring-monitor-standalone\n")
        .arg(desktop_entry::execLine());
}

bool MenuEntry::isEnabled() const
{
    return QFileInfo::exists(desktopFilePath());
}

void MenuEntry::setEnabled(bool on)
{
    const QString path = desktopFilePath();
    const bool wasEnabled = QFileInfo::exists(path);
    if (on == wasEnabled)
        return;

    if (on)
        desktop_entry::writeDesktopFile(path, buildDesktopFileContent());
    else
        desktop_entry::removeDesktopFile(path);

    // Emit regardless of write success. The checkbox optimistically flips
    // on the user's click; re-evaluating `enabled` here re-syncs it to the
    // real on-disk state, so a failed write un-ticks the box instead of
    // leaving it lying that an entry was created.
    Q_EMIT enabledChanged();
}
