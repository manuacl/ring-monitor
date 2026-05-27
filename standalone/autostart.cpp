#include "autostart.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QTextStream>

namespace {

// Single source of truth for the autostart filename. Matches the
// plasmoid id so KDE recognises the entry as ours in System
// Settings → Startup applications.
constexpr auto kDesktopFileName = "dev.manuacl.ringmonitor.desktop";

} // namespace

Autostart::Autostart(QObject *parent) : QObject(parent) {}

QString Autostart::desktopFilePath() const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
                        + QStringLiteral("/autostart");
    return dir + QLatin1Char('/') + QLatin1String(kDesktopFileName);
}

QString Autostart::currentExecPath() const
{
    // AppImage runtime sets $APPIMAGE to the .AppImage file path and
    // $APPDIR to the mount root (e.g. /tmp/.mount_xxx). Use $APPIMAGE
    // ONLY when our own binary lives inside $APPDIR — otherwise we
    // inherited the env vars from a parent process that itself runs
    // in an AppImage (e.g. the user's terminal or editor wrapper) and
    // pointing autostart at THAT AppImage would launch the wrong app
    // on next login. Surfaced as a bug during PR G manual testing
    // (Limux terminal had $APPIMAGE pointing at its own .AppImage).
    const QString self = QCoreApplication::applicationFilePath();
    const QByteArray appImage = qgetenv("APPIMAGE");
    const QByteArray appDir = qgetenv("APPDIR");
    if (!appImage.isEmpty() && !appDir.isEmpty()
        && self.startsWith(QString::fromLocal8Bit(appDir))) {
        return QString::fromLocal8Bit(appImage);
    }
    return self;
}

QString Autostart::quoteExecArg(const QString &arg)
{
    // Per the XDG Desktop Entry Spec §"The Exec key", any argument
    // containing a reserved character (space, tab, newline, quote,
    // backslash, `>`, `<`, `~`, `|`, `&`, `;`, `$`, `*`, `?`, `#`,
    // `(`, `)`, backtick) must be double-quoted, and inside double
    // quotes the four chars `"`, `\`, `$`, `` ` `` must be escaped
    // with a leading backslash. We quote unconditionally — the cost
    // is one extra pair of quotes for the common case, the win is
    // that paths with spaces (e.g. `~/Applications/Ring Monitor.AppImage`
    // under AppImageLauncher) survive XDG launcher tokenisation
    // instead of being parsed as two argv tokens.
    //
    // Backslashes are escaped first so subsequent inserted backslashes
    // don't get doubled by a later replace pass.
    QString escaped = arg;
    escaped.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
    escaped.replace(QLatin1Char('"'), QStringLiteral("\\\""));
    escaped.replace(QLatin1Char('$'), QStringLiteral("\\$"));
    escaped.replace(QLatin1Char('`'), QStringLiteral("\\`"));
    return QLatin1Char('"') + escaped + QLatin1Char('"');
}

QString Autostart::buildDesktopFileContent() const
{
    // env QT_QPA_PLATFORM=xcb forces XWayland under Wayland sessions
    // so the EWMH hints in desktop_hints.cpp (sticky / skip-taskbar
    // / skip-pager / below) actually apply. Harmless on X11. Drop
    // when native layer-shell support lands (PR C2).
    //
    // Only the executable path is quoted: `env` and the
    // `KEY=VALUE` assignment are fixed identifiers free of reserved
    // characters, so they're left bare (the spec allows unquoted
    // tokens). The path is the only piece a user can introduce
    // spaces / special chars into.
    const QString exec = QStringLiteral("env QT_QPA_PLATFORM=xcb ")
                         + quoteExecArg(currentExecPath());
    return QStringLiteral("[Desktop Entry]\n"
                          "Type=Application\n"
                          "Name=Ring Monitor\n"
                          "Comment=Modern minimal circular system monitor\n"
                          "Exec=%1\n"
                          "Icon=utilities-system-monitor\n"
                          "Categories=System;Monitor;\n"
                          "X-GNOME-Autostart-enabled=true\n")
        .arg(exec);
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
        // Make sure ~/.config/autostart/ exists — fresh user
        // profiles do not have it by default.
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
            return;
        QTextStream out(&f);
        out << buildDesktopFileContent();
    } else {
        QFile::remove(path);
    }
    Q_EMIT enabledChanged();
}
