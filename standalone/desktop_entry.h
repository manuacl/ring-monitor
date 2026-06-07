#pragma once

// Shared helpers for the two XDG `.desktop` files the standalone build
// writes: the autostart entry (Autostart) and the application-menu
// entry (MenuEntry). Both need the SAME `Exec=` line — resolved to the
// AppImage path on AppImage installs, XDG-quoted, and prefixed with
// `env QT_QPA_PLATFORM=xcb` so the Conky-style window flags in
// desktop_hints.cpp apply under Wayland. Keeping the resolution in one
// place stops the two writers from drifting (the `$APPIMAGE`/`$APPDIR`
// bootstrap and the XDG escape order are both subtle — see the impl).
// The file-write/remove plumbing and the self-heal are shared here too,
// so a fix to one (atomic write, stale-Exec refresh) lands for both.

#include <QString>

namespace desktop_entry {

// The .desktop basename, shared by both writers (matches the plugin id
// so KDE recognises the entry as ours). Single source so a plugin-id
// rename can't leave one writer pointing at a stale basename.
inline constexpr auto kDesktopFileName = "dev.manuacl.ringmonitor.desktop";

// The two .desktop locations the writers manage. Centralised here so
// the orphan check in removeStableCopyIfOrphaned() can probe both
// without reaching into the writer classes.
QString autostartFilePath();  // ~/.config/autostart/<kDesktopFileName>
QString menuFilePath();       // ~/.local/share/applications/<kDesktopFileName>

// The fully-formed `Exec=` value: `env QT_QPA_PLATFORM=xcb "<path>"`.
// `<path>` is the stable copy when it exists (see stableExecPath), else
// the AppImage when we run inside one, else our own binary — XDG-quoted
// so paths with spaces survive launcher tokenisation.
QString execLine();

// Fixed, version-independent path of the stable AppImage copy:
// `~/.local/bin/ring-monitor.AppImage`. Release AppImages are
// version-stamped (Ring_Monitor-X.Y.Z-…), so an Exec= pointing at the
// downloaded file dies on every upgrade — even with the launch-time
// self-heal, an upgrade followed by a re-login (never launching the new
// file) boots to nothing (#136). The .desktop entries reference this
// copy instead: it always exists, so login always starts SOME install,
// and the next launch of a newer AppImage refreshes it.
QString stableExecPath();

// The full rendered .desktop contents for the two writers. Centralised
// here (not in the writer classes) so the async copy worker below can
// re-render both entries once the stable copy lands, without touching
// any QObject from its thread.
QString autostartFileContent();
QString menuFileContent();

// Create or refresh the stable copy from the running AppImage,
// asynchronously. The cheap staleness stats run on the caller's thread;
// no-op when not an AppImage run (a dev build must not shadow a real
// install), when running FROM the copy itself, or when the copy is
// already current (size + mtime match — the copy preserves the source
// mtime so this stays a cheap stat). When work is needed, the actual
// copy runs on a DETACHED worker thread (a copy stuck on a hung mount
// must not block GUI startup or process exit — same rationale as
// ProcReader's statvfs worker), with an in-flight guard so a hung copy
// freezes one thread, never a pile. On success the worker re-renders
// BOTH .desktop entries (their Exec= converges to the stable path
// without waiting for the next launch) and re-runs the orphan check in
// case a disable raced the copy. The replace is atomic (sibling temp
// file + rename(2)) because a login-launched instance may have the old
// copy FUSE-mounted while we swap it.
void ensureStableCopyAsync();

// Remove the stable copy once neither .desktop entry references it
// (both toggles off) — an AppImage has no uninstaller to clean it up
// later. No-op while either entry exists.
void removeStableCopyIfOrphaned();

// Absolute path the .desktop should launch. Prefers `$APPIMAGE` only
// when our binary actually lives under `$APPDIR` — otherwise we
// inherited those env vars from a parent that is itself an AppImage
// (e.g. a terminal) and must fall back to applicationFilePath().
QString currentExecPath();

// True iff we run from inside our OWN AppImage (`$APPIMAGE` set and our
// binary under `$APPDIR`). The stale-Exec self-heal (refreshIfStale) is
// gated on this so a dev / source build never rewrites the user's
// installed launcher to point at the throwaway build binary. See #126.
bool runningAsAppImage();

// XDG Desktop Entry §"The Exec key" encoding: wrap in double quotes,
// escaping `\` first (so later-inserted backslashes aren't doubled),
// then `"`, `$`, and backtick.
QString quoteExecArg(const QString &arg);

// Atomically write `content` to `path` (mkpath the parent first). Uses
// QSaveFile so a crash / power loss mid-write can't leave a truncated
// half-launcher — the old file stays until the new one is complete.
// Returns false on failure (unwritable dir, full disk) without touching
// any existing file.
bool writeDesktopFile(const QString &path, const QString &content);

// Remove `path`. Returns true if it no longer exists afterwards.
bool removeDesktopFile(const QString &path);

// Self-heal: if `path` exists but its `Exec=` line no longer matches
// `execLine()` (the AppImage was moved / re-downloaded to a new path),
// rewrite it with `content`. No-op if the file is absent, already
// current, or we're not running as an AppImage (runningAsAppImage() —
// a fixed-path dev build must not hijack the installed launcher).
// Returns true iff a rewrite happened. Lets a writer refresh a stale
// launcher on startup so it never silently points at a dead path.
bool refreshIfStale(const QString &path, const QString &content);

} // namespace desktop_entry
