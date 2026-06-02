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

// The fully-formed `Exec=` value: `env QT_QPA_PLATFORM=xcb "<path>"`.
// `<path>` is the AppImage when we run inside one, else our own binary,
// XDG-quoted so paths with spaces survive launcher tokenisation.
QString execLine();

// Absolute path the .desktop should launch. Prefers `$APPIMAGE` only
// when our binary actually lives under `$APPDIR` — otherwise we
// inherited those env vars from a parent that is itself an AppImage
// (e.g. a terminal) and must fall back to applicationFilePath().
QString currentExecPath();

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
// rewrite it with `content`. No-op if the file is absent or already
// current. Returns true iff a rewrite happened. Lets a writer refresh a
// stale launcher on startup so it never silently points at a dead path.
bool refreshIfStale(const QString &path, const QString &content);

} // namespace desktop_entry
