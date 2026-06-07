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
    // The stable-copy refresh (#136) is asynchronous: the AppImage copy
    // (>100 MB) must not block the GUI thread during QML construction,
    // so refreshIfStale below heals with the best CURRENTLY renderable
    // Exec= (the stable copy if present, else the live path) and the
    // worker converges both entries to the stable path on completion.
    // Gated on the entry existing: a launch with both toggles off must
    // not create the copy. Pre-copy installs migrate here.
    if (QFileInfo::exists(desktopFilePath()))
        desktop_entry::ensureStableCopyAsync();
    desktop_entry::refreshIfStale(desktopFilePath(), buildDesktopFileContent());
}

QString Autostart::desktopFilePath() const
{
    return desktop_entry::autostartFilePath();
}

QString Autostart::buildDesktopFileContent() const
{
    // Template lives in desktop_entry so the async copy worker can
    // re-render the entry from its thread without touching this QObject.
    return desktop_entry::autostartFileContent();
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
        // The entry is written immediately with the best currently
        // renderable Exec= (stable copy if it already exists, else the
        // live path); the async worker re-points it at the fresh copy
        // when the copy lands (#136).
        desktop_entry::ensureStableCopyAsync();
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
