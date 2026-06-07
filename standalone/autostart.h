#pragma once

// XDG-autostart helper exposed to QML. Writes / removes
// `~/.config/autostart/dev.manuacl.ringmonitor.desktop` so the
// standalone widget can offer a "Start automatically on login"
// toggle in the Settings dialog.
//
// On AppImage installs, `Exec=` points at the stable copy
// (`desktop_entry::stableExecPath()`, refreshed from the running
// AppImage — see desktop_entry.h for why a version-stamped path
// can't be referenced directly, #136); on dev / source builds it
// points at `QCoreApplication::applicationFilePath()`. Either way,
// the line is prefixed with `env QT_QPA_PLATFORM=xcb` so the
// Conky-style window flags applied in `desktop_hints.cpp` actually
// take effect — the layer-shell native path that would remove the
// need lands in PR C2.
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

    // True iff the autostart .desktop file exists. On AppImage installs the
    // Exec line is kept fresh by the constructor (stable-copy refresh +
    // refreshIfStale — an update is re-pointed on the next launch, and
    // login always finds the stable copy meanwhile, #126/#136); a
    // fixed-path build has nothing to drift. Either way this need only
    // report presence.
    bool isEnabled() const;

    // Creates (true) or removes (false) the autostart file. No-op if
    // already in the requested state.
    Q_INVOKABLE void setEnabled(bool on);

signals:
    void enabledChanged();

private:
    QString desktopFilePath() const;

    // The Exec= line (incl. AppImage resolution + XDG quoting) is
    // shared with MenuEntry — see standalone/desktop_entry.h.
    QString buildDesktopFileContent() const;
};
