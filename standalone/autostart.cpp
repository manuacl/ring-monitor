#include "autostart.h"

#include "desktop_entry.h"

#include <QFileInfo>

Autostart::Autostart(QObject *parent) : QObject(parent)
{
    // Self-heal a stale autostart entry: after an AppImage update the
    // versioned filename changes, so a previously written Exec= points at
    // the OLD binary and login keeps launching it (#126). Rewrite to the
    // current path on construction — parity with MenuEntry. refreshIfStale
    // is a no-op when the entry is absent, already current, or we're a
    // fixed-path dev build (so a source run can't hijack the entry).
    //
    // The stable-copy refresh comes first so refreshIfStale renders an
    // Exec= against an up-to-date copy (#136). Gated on the entry
    // existing: a launch with both toggles off must not create the copy.
    // Pre-copy installs migrate here — their entry exists with an
    // absolute Exec=, so this creates the copy and refreshIfStale
    // rewrites the entry to it.
    if (QFileInfo::exists(desktopFilePath()))
        desktop_entry::ensureStableCopy();
    desktop_entry::refreshIfStale(desktopFilePath(), buildDesktopFileContent());
}

QString Autostart::desktopFilePath() const
{
    return desktop_entry::autostartFilePath();
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

    if (on) {
        // Copy first: buildDesktopFileContent() points Exec= at the stable
        // copy only once it exists (#136).
        desktop_entry::ensureStableCopy();
        desktop_entry::writeDesktopFile(path, buildDesktopFileContent());
    } else {
        desktop_entry::removeDesktopFile(path);
        desktop_entry::removeStableCopyIfOrphaned();
    }

    // Emit regardless of write success so an observer (the Settings
    // checkbox) re-syncs to the real on-disk state — a failed write must
    // not leave the toggle showing "enabled". Shared shape with MenuEntry.
    Q_EMIT enabledChanged();
}
