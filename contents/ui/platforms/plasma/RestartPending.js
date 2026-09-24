// Pure logic for detecting an installed-but-not-loaded update (#172).
//
// plasmashell keeps running the widget version it loaded at startup: a
// KDE Store / Discover update replaces the package on disk, but the
// running widget (and `Plasmoid.metaData.version`) stay on the old one
// until the shell restarts — verified live on Plasma 6.7.5. Comparing
// that in-memory version with the on-disk metadata.json tells us a
// restart is pending.
//
// Public surface:
//   readCommand(fileUrl)             - shell command printing the package's
//                                      metadata.json ("" for a non-file URL)
//   parseInstalledVersion(stdout)    - KPlugin.Version from that JSON, or ""
//   isRestartPending(running, disk)  - both known and different
//   RESTART_COMMAND                  - restarts plasmashell
//
// Dual-loaded by QML and Node (module.exports shim at the bottom).

// systemd restarts the shell independently of us: the executable engine
// kills its child when plasmashell exits, which would cut a
// quit-then-start sequence in half. Sessions not started by systemd fall
// back to a detached `plasmashell --replace`.
var RESTART_COMMAND = "systemctl --user restart plasma-plasmashell.service || setsid -f plasmashell --replace";

// The engine runs commands through a shell (KProcess::setShellCommand),
// and the install path can hold spaces or quotes: single-quote it.
function readCommand(fileUrl) {
    var url = String(fileUrl || "");
    if (url.indexOf("file://") !== 0) return "";
    var path = decodeURIComponent(url.slice("file://".length));
    return "cat '" + path.replace(/'/g, "'\\''") + "'";
}

function parseInstalledVersion(stdout) {
    try {
        var version = JSON.parse(stdout).KPlugin.Version;
        return typeof version === "string" ? version : "";
    } catch (e) {
        return "";
    }
}

// Any difference counts, not just a newer disk version: a downgrade also
// leaves the old code running.
function isRestartPending(running, installed) {
    return !!running && !!installed && running !== installed;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        RESTART_COMMAND: RESTART_COMMAND,
        readCommand: readCommand,
        parseInstalledVersion: parseInstalledVersion,
        isRestartPending: isRestartPending,
    };
}
