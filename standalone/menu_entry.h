#pragma once

// Application-menu helper exposed to QML. Writes / removes
// `~/.local/share/applications/dev.manuacl.ringmonitor.desktop` so the
// standalone widget can offer a "Show in application menu" toggle in
// the Settings dialog.
//
// Why this exists: a downloaded AppImage shows up in no launcher, and
// on XFCE / Thunar a double-click does nothing (no default handler for
// `application/vnd.appimage`). Writing a per-app launcher that points
// `Exec=` at the AppImage gives users a menu entry without root or a
// system-wide MIME default. Issues #101 / #102.
//
// The Exec= line (AppImage-path resolution + XDG quoting + the
// `env QT_QPA_PLATFORM=xcb` prefix) is shared with Autostart via
// standalone/desktop_entry.h, so the two writers can't drift.
//
// Registered to QML via QML_ELEMENT so SettingsDialog can instantiate
// it as `MenuEntry { id: menuEntry }`.

#include <QObject>
#include <QString>
#include <QtQmlIntegration/QtQmlIntegration>

// Lives at global scope rather than `ringmonitor::` for the same
// reason ProcReader / Autostart do — Qt's QML auto-registration
// codegen does not namespace-qualify the type.
class MenuEntry : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool enabled READ isEnabled NOTIFY enabledChanged)

public:
    explicit MenuEntry(QObject *parent = nullptr);

    // True iff the menu .desktop file exists. On AppImage installs the
    // Exec line is kept fresh by the constructor (stable-copy refresh +
    // refreshIfStale, #126/#136); a fixed-path build has nothing to
    // drift. Either way this need only report presence.
    bool isEnabled() const;

    // Creates (true) or removes (false) the menu entry. No-op if
    // already in the requested state.
    Q_INVOKABLE void setEnabled(bool on);

signals:
    void enabledChanged();

private:
    QString desktopFilePath() const;
    QString buildDesktopFileContent() const;
};
