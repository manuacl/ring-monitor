// Pure logic for the update-notification flow.
//
// MetricsBackend.qml-style separation: this file holds only pure JS
// helpers (dual-loadable by QML and Node). The QML-side runner lives
// in core/UpdateChecker.qml (XMLHttpRequest, timers, ConfigStore wiring).
//
// Public surface:
//   parseSemver(tag)               - "v0.4.0" / "0.4.0" → [0,4,0] | null
//   compareSemver(a, b)            - 3-way numeric compare on [maj,min,pat]
//   isNewerVersion(local, remote)  - both strings; remote strictly > local
//   shouldRecheck(lastMs, now, ttl) - cache TTL gate
//   shouldNotify(local, remote, acknowledged) - true when there's a new
//                                    version AND the user hasn't already
//                                    dismissed it via "Got it"
//
// Dual-loaded by QML (`import "UpdateCheck.js" as UC`) and Node (via
// the module.exports shim at the bottom).

function parseSemver(tag) {
    if (typeof tag !== "string") return null;
    var m = tag.match(/^v?(\d+)\.(\d+)\.(\d+)/);
    if (!m) return null;
    return [parseInt(m[1], 10), parseInt(m[2], 10), parseInt(m[3], 10)];
}

function compareSemver(a, b) {
    if (!a || !b) return 0;
    for (var i = 0; i < 3; i++) {
        if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
    }
    return 0;
}

function isNewerVersion(localTag, remoteTag) {
    var l = parseSemver(localTag);
    var r = parseSemver(remoteTag);
    if (!l || !r) return false;
    return compareSemver(r, l) > 0;
}

// Cache gate: should the network call fire? `lastCheckMs` is when the
// last successful check landed (0 = never). `nowMs` is now. `ttlMs` is
// the cache TTL (typically 24h = 86_400_000).
function shouldRecheck(lastCheckMs, nowMs, ttlMs) {
    if (!isFinite(lastCheckMs) || lastCheckMs <= 0) return true;
    if (!isFinite(nowMs) || nowMs <= 0) return false;
    if (!isFinite(ttlMs) || ttlMs <= 0) return true;
    return (nowMs - lastCheckMs) >= ttlMs;
}

// "Should the badge / config-dialog row show right now?" — true iff
// remote is strictly newer than local AND the user hasn't already
// acknowledged that specific remote version. Acknowledging a version
// snoozes the notification until an even newer version appears.
function shouldNotify(localTag, remoteTag, acknowledgedTag) {
    if (!isNewerVersion(localTag, remoteTag)) return false;
    if (!acknowledgedTag) return true;
    if (!parseSemver(acknowledgedTag)) return true;  // malformed → no-ack
    // Acknowledged covers anything up to and including itself; we only
    // re-notify when the remote leaps past the acknowledged version.
    return isNewerVersion(acknowledgedTag, remoteTag);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parseSemver: parseSemver,
        compareSemver: compareSemver,
        isNewerVersion: isNewerVersion,
        shouldRecheck: shouldRecheck,
        shouldNotify: shouldNotify,
    };
}
