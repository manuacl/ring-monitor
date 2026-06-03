#include "desktop_entry.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QString>

namespace desktop_entry {

bool runningAsAppImage()
{
    // AppImage runtime sets $APPIMAGE to the .AppImage file path and
    // $APPDIR to the mount root (e.g. /tmp/.mount_xxx). Treat ourselves as
    // an AppImage run ONLY when our own binary lives inside $APPDIR —
    // otherwise we inherited the env vars from a parent process that itself
    // runs in an AppImage (e.g. the user's terminal or editor wrapper) and
    // pointing Exec= at THAT AppImage would launch the wrong app. Surfaced
    // as a bug during PR G manual testing (Limux terminal had $APPIMAGE
    // pointing at its own .AppImage).
    const QString self = QCoreApplication::applicationFilePath();
    const QByteArray appImage = qgetenv("APPIMAGE");
    const QByteArray appDir = qgetenv("APPDIR");
    // Compare with `appDir + "/"`, not a bare startsWith(): a sibling
    // mount (APPDIR=/tmp/.mount_limuxAB vs our binary under
    // /tmp/.mount_limuxABCDE) would falsely prefix-match and point
    // Exec= at the wrong AppImage.
    return !appImage.isEmpty() && !appDir.isEmpty()
        && self.startsWith(QString::fromLocal8Bit(appDir) + QLatin1Char('/'));
}

QString currentExecPath()
{
    if (runningAsAppImage())
        return QString::fromLocal8Bit(qgetenv("APPIMAGE"));
    return QCoreApplication::applicationFilePath();
}

QString quoteExecArg(const QString &arg)
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

QString execLine()
{
    // env QT_QPA_PLATFORM=xcb forces XWayland under Wayland sessions
    // so the EWMH hints in desktop_hints.cpp (sticky / skip-taskbar
    // / skip-pager / below) actually apply. Harmless on X11. Drop
    // when native layer-shell support lands (PR C2).
    //
    // Only the path is quoted: `env` and the `KEY=VALUE` token are
    // fixed identifiers free of reserved chars, the path is the only
    // piece a user can introduce spaces / special chars into.
    return QStringLiteral("env QT_QPA_PLATFORM=xcb ") + quoteExecArg(currentExecPath());
}

bool writeDesktopFile(const QString &path, const QString &content)
{
    // Fresh profiles may lack the parent dir (~/.config/autostart or
    // ~/.local/share/applications).
    if (!QDir().mkpath(QFileInfo(path).absolutePath()))
        return false;
    // QSaveFile commits via an atomic rename, so a crash mid-write never
    // leaves a half-written launcher — the previous file (if any) stays
    // intact until commit() succeeds.
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return false;
    const QByteArray bytes = content.toUtf8();
    if (f.write(bytes) != bytes.size())
        return false; // QSaveFile is discarded (not committed) on dtor
    return f.commit();
}

bool removeDesktopFile(const QString &path)
{
    QFile::remove(path);
    return !QFileInfo::exists(path);
}

bool refreshIfStale(const QString &path, const QString &content)
{
    // Self-heal is for AppImage installs only. An AppImage update changes
    // the versioned filename (Ring_Monitor-0.8.0 → -0.11.0), so a stored
    // Exec= goes stale and login launches the old binary (#126). A dev /
    // source build, by contrast, has a FIXED applicationFilePath() — it
    // never drifts, and rewriting an existing entry to it would hijack the
    // user's installed-AppImage launcher to a throwaway build path. Gate
    // here (not at each caller) so every self-heal site is covered at once.
    if (!runningAsAppImage())
        return false;
    if (!QFileInfo::exists(path))
        return false;
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return false;
    const QString existing = QString::fromUtf8(f.readAll());
    f.close();
    // The Exec= line is the only part that can go stale (it embeds the
    // AppImage path). Compare the whole rendered content: if anything
    // drifted from what we'd write today, rewrite.
    if (existing == content)
        return false;
    return writeDesktopFile(path, content);
}

} // namespace desktop_entry
