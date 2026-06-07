#include "menu_entry.h"

#include "desktop_entry.h"

#include <QFileInfo>

MenuEntry::MenuEntry(QObject *parent) : QObject(parent)
{
    // Self-heal a stale launcher: if the AppImage was moved / re-downloaded
    // to a new path, the stored Exec= no longer matches and the menu entry
    // would silently launch a dead path. Rewriting it on construction (the
    // Settings dialog instantiates us) refreshes Exec= to the current
    // binary with no user action — closes the "toggle claims healthy while
    // broken" trap. No-op when the file is absent or already current.
    //
    // Async stable-copy refresh, gated on the entry existing — same
    // shape and rationale as the Autostart ctor (#136).
    if (QFileInfo::exists(desktopFilePath()))
        desktop_entry::ensureStableCopyAsync();
    desktop_entry::refreshIfStale(desktopFilePath(), buildDesktopFileContent());
}

QString MenuEntry::desktopFilePath() const
{
    return desktop_entry::menuFilePath();
}

QString MenuEntry::buildDesktopFileContent() const
{
    // Template lives in desktop_entry so the async copy worker can
    // re-render the entry from its thread without touching this QObject.
    return desktop_entry::menuFileContent();
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

    // Emit regardless of write success. The checkbox optimistically flips
    // on the user's click; re-evaluating `enabled` here re-syncs it to the
    // real on-disk state, so a failed write un-ticks the box instead of
    // leaving it lying that an entry was created.
    Q_EMIT enabledChanged();
}
