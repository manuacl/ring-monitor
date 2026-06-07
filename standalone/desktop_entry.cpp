#include "desktop_entry.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>
#include <QString>

#include <atomic>
#include <cstdio>
#include <thread>

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
    // a launch-time-healed Exec= beats a dangling one. (The async
    // worker re-renders the entries once the copy lands, so a fallback
    // written here converges to the stable path moments later.)
    const QString stable = stableExecPath();
    const bool useStableCopy = runningAsAppImage() && QFileInfo::exists(stable);
    const QString target = useStableCopy ? stable : currentExecPath();
    return QStringLiteral("env QT_QPA_PLATFORM=xcb ") + quoteExecArg(target);
}

QString autostartFileContent()
{
    // X-GNOME-Autostart-enabled is the autostart-only key; the menu
    // entry must not carry it.
    return QStringLiteral("[Desktop Entry]\n"
                          "Type=Application\n"
                          "Name=Ring Monitor\n"
                          "Comment=Modern minimal circular system monitor\n"
                          "Exec=%1\n"
                          "Icon=utilities-system-monitor\n"
                          "Categories=System;Monitor;\n"
                          "X-GNOME-Autostart-enabled=true\n")
        .arg(execLine());
}

QString menuFileContent()
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
        .arg(execLine());
}

namespace {

// True when the stable copy must be (re)created from `src`. Stat-cheap —
// safe on the GUI thread at every launch.
bool stableCopyStale(const QFileInfo &src, const QFileInfo &dst)
{
    // Running FROM the copy (a login launch): the copy IS the source.
    // Canonical compare so a symlinked ~/.local/bin still matches.
    if (dst.exists() && src.canonicalFilePath() == dst.canonicalFilePath())
        return false;
    // Freshness on (size, mtime): the copy preserves the source mtime,
    // so an unchanged AppImage is a cheap stat no-op while a re-download
    // or different build re-triggers.
    if (dst.exists() && dst.size() == src.size()
        && dst.lastModified() == src.lastModified())
        return false;
    return true;
}

// The copy payload: copy + chmod + mtime + atomic rename. Runs on the
// worker thread. Every failure path warns — a silent failure would
// either strand the .desktop entries on the version-stamped fallback
// (#136 reappears with no journal trace) or, for the mtime step,
// re-trigger the full copy on every later launch.
bool writeStableCopy(const QString &sourcePath, const QDateTime &sourceMtime,
                     const QString &stablePath)
{
    if (!QDir().mkpath(QFileInfo(stablePath).absolutePath())) {
        qWarning("ring-monitor: cannot create the stable-copy dir for %s",
                 qPrintable(stablePath));
        return false;
    }
    // Copy to a sibling temp, then rename(2) over the destination — the
    // QSaveFile pattern, hand-rolled because the payload is a whole-file
    // copy, not a buffer write. Atomicity matters here: a still-running
    // login instance may have the old copy FUSE-mounted, and rename keeps
    // its inode alive while new launches see the fresh file. (QFile::rename
    // refuses an existing destination, hence POSIX rename directly.)
    const QString tmp = stablePath + QStringLiteral(".part");
    QFile::remove(tmp);
    if (!QFile::copy(sourcePath, tmp)) {
        qWarning("ring-monitor: stable-copy write failed (%s -> %s)",
                 qPrintable(sourcePath), qPrintable(tmp));
        return false;
    }
    // Browsers strip +x from downloads; the copy must be executable on
    // its own. A chmod failure ABORTS the swap: a non-executable copy
    // behind Exec= would make login fail with EACCES and no visible
    // error, while keeping the previous copy (or none) stays launchable.
    if (!QFile::setPermissions(tmp,
                               QFile::permissions(tmp) | QFileDevice::ExeOwner
                                   | QFileDevice::ExeGroup | QFileDevice::ExeOther)) {
        qWarning("ring-monitor: cannot make the stable copy executable, keeping the previous one");
        QFile::remove(tmp);
        return false;
    }
    {
        // Preserve the source mtime — the staleness check depends on it.
        // ReadWrite, NOT WriteOnly: for QFile, WriteOnly implies Truncate
        // and would wipe the bytes just copied; setFileTime only needs an
        // open handle. A failure here is survivable (the copy works, it
        // just re-copies on the next launch), so warn and continue.
        QFile f(tmp);
        if (!f.open(QIODevice::ReadWrite)
            || !f.setFileTime(sourceMtime, QFileDevice::FileModificationTime)) {
            qWarning("ring-monitor: cannot preserve the stable copy's mtime; "
                     "it will re-copy on the next launch");
        }
    }
    if (::rename(QFile::encodeName(tmp).constData(),
                 QFile::encodeName(stablePath).constData()) != 0) {
        qWarning("ring-monitor: stable-copy rename failed for %s", qPrintable(stablePath));
        QFile::remove(tmp);
        return false;
    }
    return true;
}

} // namespace

void ensureStableCopyAsync()
{
    // AppImage installs only: a dev / source build has a fixed
    // applicationFilePath() — nothing drifts, nothing to copy, and a
    // throwaway build binary must never shadow a real install's copy.
    if (!runningAsAppImage())
        return;
    const QFileInfo src(currentExecPath());
    const QFileInfo dst(stableExecPath());
    if (!stableCopyStale(src, dst))
        return;
    // In-flight dedup: a second request while the worker runs is dropped,
    // so a copy hung on a dead mount freezes exactly one thread, never a
    // pile (same shape as ProcReader's statvfs guard).
    static std::atomic<bool> inFlight{false};
    if (inFlight.exchange(true))
        return;
    // Detached, not pooled: a QThreadPool dtor would block process exit
    // until the copy finishes — a stuck copy must not wedge quit. The
    // detached thread is reaped by the OS instead (statvfs precedent in
    // proc_reader.cpp). The AppImage copy itself (potentially >100 MB)
    // is exactly the work that must NOT run on the GUI thread: inline it
    // froze the first post-upgrade launch for the whole copy duration.
    std::thread([source = src.absoluteFilePath(), mtime = src.lastModified()] {
        if (writeStableCopy(source, mtime, stableExecPath())) {
            // The entries were rendered before the fresh copy existed —
            // re-render both so Exec= converges to the stable path now
            // rather than on the next launch. Plain atomic file I/O; a
            // concurrent GUI-thread write renders identical content, so
            // last-wins is benign.
            refreshIfStale(autostartFilePath(), autostartFileContent());
            refreshIfStale(menuFilePath(), menuFileContent());
            // A disable that raced the copy (both toggles turned off
            // while the worker ran) would otherwise leak the
            // just-written copy with nothing referencing it.
            removeStableCopyIfOrphaned();
        }
        inFlight.store(false);
    }).detach();
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
