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
//   releaseScope(tag)              - "-p" → "plasma", "-s" → "standalone",
//                                    none → "both" (see issue #89)
//   pickRelevantRelease(releases, platform) - newest scope-relevant tag in a
//                                    GitHub /releases list (skips drafts /
//                                    prereleases / other-platform releases)
//   shouldRecheck(lastMs, now, ttl) - cache TTL gate
//   shouldNotify(local, remote, acknowledged, platform) - true when there's a
//                                    new version, the user hasn't dismissed it
//                                    via "Got it", and the release is in scope
//                                    for `platform`
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

// Scope of a release, read from a suffix on the git tag / GitHub release
// name (issue #89): `v0.8.0-p` = Plasma-only, `v0.8.0-s` = standalone-only,
// `v0.8.0` (no suffix) = both. The suffix lives on the tag ONLY, never in
// metadata.json — so `parseSemver` (not end-anchored) still compares the
// numeric core. A tag with any other trailer (`-rc1`, …) is "both" — the
// safe default that notifies every platform.
function releaseScope(tag) {
    if (typeof tag !== "string") return "both";
    var m = tag.match(/^v?\d+\.\d+\.\d+-([ps])$/);
    if (!m) return "both";
    return m[1] === "p" ? "plasma" : "standalone";
}

// Is a release of `scope` relevant to a build running on `platform`?
// "both" is relevant everywhere; a single-platform scope only matches its
// own platform. An empty/falsy `platform` disables the filter (relevant to
// all) — the dormant default while no tag carries a suffix.
function scopeRelevant(scope, platform) {
    if (!platform) return true;
    return scope === "both" || scope === platform;
}

// Pick the newest scope-relevant tag from a GitHub `/releases` LIST.
// We query the list (not `/releases/latest`) because, with a single shared
// counter, the highest tag may be scoped to the OTHER platform (e.g. a
// `-p` release above an intermediate `-s` one a standalone user needs);
// `/releases/latest` returns only that single highest tag and would miss
// the relevant intermediate release. Drafts and prereleases are skipped to
// match `/releases/latest` semantics. Returns "" when nothing qualifies.
function pickRelevantRelease(releases, platform) {
    if (!Array.isArray(releases)) return "";
    var best = "";
    var bestParsed = null;
    for (var i = 0; i < releases.length; i++) {
        var rel = releases[i];
        if (!rel || rel.draft || rel.prerelease) continue;
        var parsed = parseSemver(rel.tag_name);
        if (!parsed) continue;
        if (!scopeRelevant(releaseScope(rel.tag_name), platform)) continue;
        if (!bestParsed || compareSemver(parsed, bestParsed) > 0) {
            best = rel.tag_name;
            bestParsed = parsed;
        }
    }
    return best;
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
function shouldNotify(localTag, remoteTag, acknowledgedTag, platform) {
    if (!isNewerVersion(localTag, remoteTag)) return false;
    // Scope gate (issue #89): a release scoped to the other platform never
    // notifies this build. Belt-and-suspenders with the list-selection
    // filter in UpdateChecker.qml — `remoteTag` is normally already
    // scope-relevant, but gating here keeps the badge honest if a foreign
    // tag ever reaches this function (e.g. a stale persisted value).
    if (!scopeRelevant(releaseScope(remoteTag), platform)) return false;
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
        releaseScope: releaseScope,
        pickRelevantRelease: pickRelevantRelease,
        shouldRecheck: shouldRecheck,
        shouldNotify: shouldNotify,
    };
}
