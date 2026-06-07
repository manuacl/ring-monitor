#include "desktop_entry.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>
#include <QString>

#include <cstdio>

namespace desktop_entry {

QString autostartFilePath()
{
    return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
        + QStringLiteral("/autostart/") + QLatin1String(kDesktopFileName);
}

QString menuFilePath()
{
    // XDG: per-user application launchers live under
    // $XDG_DATA_HOME/applications (writableLocation(ApplicationsLocation)
    // resolves to ~/.local/share/applications on a default profile).
    return QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation)
        + QLatin1Char('/') + QLatin1String(kDesktopFileName);
}

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

QString stableExecPath()
{
    // ~/.local/bin is the systemd file-hierarchy location for user
    // executables. The basename is fixed (no version stamp) — that
    // permanence is the whole point (#136).
    return QDir::homePath() + QStringLiteral("/.local/bin/ring-monitor.AppImage");
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
    //
    // AppImage runs prefer the stable copy when it exists: the
    // downloaded file's version-stamped name dies on every upgrade,
    // the copy's path never does (#136). Falls back to the live path
    // when the copy couldn't be created (unwritable ~/.local/bin) —
    // a launch-time-healed Exec= beats a dangling one.
    const bool useStableCopy = runningAsAppImage() && QFileInfo::exists(stableExecPath());
    const QString target = useStableCopy ? stableExecPath() : currentExecPath();
    return QStringLiteral("env QT_QPA_PLATFORM=xcb ") + quoteExecArg(target);
}

bool ensureStableCopy()
{
    // AppImage installs only: a dev / source build has a fixed
    // applicationFilePath() — nothing drifts, nothing to copy, and a
    // throwaway build binary must never shadow a real install's copy.
    if (!runningAsAppImage())
        return false;
    const QFileInfo src(currentExecPath());
    const QFileInfo dst(stableExecPath());
    // Running FROM the copy (a login launch): the copy IS the source.
    // Canonical compare so a symlinked ~/.local/bin still matches.
    if (dst.exists() && src.canonicalFilePath() == dst.canonicalFilePath())
        return false;
    // Freshness on (size, mtime): the copy below preserves the source
    // mtime, so an unchanged AppImage is a cheap stat no-op while a
    // re-download or different build re-triggers.
    if (dst.exists() && dst.size() == src.size()
        && dst.lastModified() == src.lastModified())
        return false;
    if (!QDir().mkpath(dst.absolutePath()))
        return false;
    // Copy to a sibling temp, then rename(2) over the destination — the
    // QSaveFile pattern, hand-rolled because the payload is a whole file
    // copy, not a buffer write. Atomicity matters here: a still-running
    // login instance may have the old copy FUSE-mounted, and rename keeps
    // its inode alive while new launches see the fresh file. (QFile::rename
    // refuses an existing destination, hence POSIX rename directly.)
    const QString tmp = stableExecPath() + QStringLiteral(".part");
    QFile::remove(tmp);
    if (!QFile::copy(src.absoluteFilePath(), tmp))
        return false;
    // Browsers strip +x from downloads; the user chmod'ed their original
    // to run it, but the copy must be executable on its own.
    QFile::setPermissions(tmp,
                          QFile::permissions(tmp) | QFileDevice::ExeOwner
                              | QFileDevice::ExeGroup | QFileDevice::ExeOther);
    {
        // Preserve the source mtime — the freshness check above depends
        // on it. setFileTime needs an open handle (WriteOnly is enough).
        QFile f(tmp);
        if (f.open(QIODevice::ReadWrite))
            f.setFileTime(src.lastModified(), QFileDevice::FileModificationTime);
    }
    if (::rename(QFile::encodeName(tmp).constData(),
                 QFile::encodeName(stableExecPath()).constData()) != 0) {
        QFile::remove(tmp);
        return false;
    }
    return true;
}

void removeStableCopyIfOrphaned()
{
    // The copy exists to be referenced by the .desktop entries; once
    // both toggles are off nothing points at it, and an AppImage has no
    // uninstaller to clean it up later.
    if (QFileInfo::exists(autostartFilePath()) || QFileInfo::exists(menuFilePath()))
        return;
    QFile::remove(stableExecPath());
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
