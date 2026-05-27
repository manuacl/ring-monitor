#pragma once

// XDG-autostart helper exposed to QML. Writes / removes
// `~/.config/autostart/dev.manuacl.ringmonitor.desktop` so the
// standalone widget can offer a "Start automatically on login"
// toggle in the Settings dialog.
//
// On AppImage installs, `Exec=` points at the AppImage path
// (resolved via the `APPIMAGE` env var that the AppImage runtime
// sets); on dev / source builds it points at
// `QCoreApplication::applicationFilePath()`. Either way, the line
// is prefixed with `env QT_QPA_PLATFORM=xcb` so the Conky-style
// window flags applied in `desktop_hints.cpp` actually take effect
// — the layer-shell native path that would remove the need lands
// in PR C2.
//
// Registered to QML via QML_ELEMENT so SettingsDialog can
// instantiate it as `Autostart { id: autostart }`.

#include <QObject>
#include <QString>
#include <QtQmlIntegration/QtQmlIntegration>

// Lives at global scope rather than `ringmonitor::` for the same
// reason ProcReader does — Qt's QML auto-registration codegen does
// not namespace-qualify the type. See standalone/proc_reader.h for
// the full rationale.
class Autostart : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool enabled READ isEnabled NOTIFY enabledChanged)

public:
    explicit Autostart(QObject *parent = nullptr);

    // True iff the autostart .desktop file exists in the user's
    // XDG_CONFIG_HOME/autostart/. Does not validate the Exec line
    // against the current binary path — a stale Exec from a
    // previous install will silently re-resolve at login time, and
    // the user can toggle off / on to refresh it.
    bool isEnabled() const;

    // Creates (true) or removes (false) the autostart file. No-op
    // if the file is already in the requested state. Emits
    // enabledChanged() on actual transitions.
    Q_INVOKABLE void setEnabled(bool on);

signals:
    void enabledChanged();

private:
    QString desktopFilePath() const;
    QString currentExecPath() const;
    QString buildDesktopFileContent() const;

    // XDG-spec encoding for the Exec= argument. Static so the impl
    // is independent of `this` — purely a string transform.
    static QString quoteExecArg(const QString &arg);
};
