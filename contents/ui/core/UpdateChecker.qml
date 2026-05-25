import QtQuick
import "UpdateCheck.js" as UC

// Runtime side of the update-check flow. Pure-QtQuick (XMLHttpRequest,
// Timer, Qt.openUrlExternally) so it stays in `core/` — the Plasma
// adapter ConfigStore.qml provides the read/write surface for the
// persisted state.
//
// Public surface (read by MainContent's first-ring delegate + by
// AboutBody):
//   readonly property bool  updateAvailable
//   readonly property string remoteVersion
//   function check()         - force a network probe (bypasses TTL)
//   function acknowledge()   - persist "Got it" on the current remote
//   function openReleasePage() - Qt.openUrlExternally to the release URL
//
// All persistence goes through `configStore` (injected) so the standalone
// build's ConfigStore can satisfy the same surface backed by
// Qt.labs.settings instead of the Plasma config store.

Item {
    id: checker

    // ── Inputs (injected by the parent) ─────────────────────────────
    property var configStore

    // ── Tunables ────────────────────────────────────────────────────
    readonly property url releasesApiUrl: "https://api.github.com/repos/manuacl/ring-monitor/releases/latest"
    // User-facing "where to update from" page. The KDE Store is where
    // most users installed the widget originally, so that's the
    // natural place to send them for an update — the page carries the
    // changelog (maintained by the maintainer) and the install button.
    // The GitHub releases page is dev-oriented (PR titles, source
    // tarballs); we link to it only from the "Installation methods"
    // section for users who built from source.
    readonly property url storePageUrl: "https://www.opendesktop.org/p/2360410"
    // 24h cache TTL. Under GitHub's 60 req/h unauthenticated cap, we
    // burn 0.04 req/h — three orders of magnitude of headroom.
    readonly property int cacheTtlMs: 24 * 60 * 60 * 1000

    // ── Derived (reactive) ──────────────────────────────────────────
    readonly property string localVersion: checker.configStore ? checker.configStore.localVersion : ""
    readonly property string remoteVersion: checker.configStore ? checker.configStore.latestKnownVersion : ""
    readonly property string acknowledgedVersion: checker.configStore ? checker.configStore.acknowledgedVersion : ""
    readonly property bool updateAvailable: UC.shouldNotify(localVersion, remoteVersion, acknowledgedVersion)

    // ── Public functions ────────────────────────────────────────────
    function acknowledge() {
        if (checker.configStore && checker.remoteVersion) {
            checker.configStore.acknowledgeVersion(checker.remoteVersion);
        }
    }

    function openStorePage() {
        Qt.openUrlExternally(checker.storePageUrl);
    }

    function check() {
        if (!checker.configStore)
            return;
        var xhr = new XMLHttpRequest();
        xhr.open("GET", checker.releasesApiUrl);
        xhr.setRequestHeader("Accept", "application/vnd.github+json");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            // Tolerate any failure silently — a network blip should
            // not surface to the user. The cached version stays put.
            if (xhr.status !== 200)
                return;
            try {
                var data = JSON.parse(xhr.responseText);
                var tag = data && data.tag_name;
                if (typeof tag === "string" && tag.length > 0) {
                    checker.configStore.recordUpdateCheck(tag, Date.now());
                }
            } catch (e) {
                // Malformed JSON — ignore, retry next TTL cycle.
            }
        };
        xhr.send();
    }

    // Fire-and-forget gate at load time. When the cache has expired
    // (or never populated) we kick a check; otherwise we ride the
    // cached `latestKnownVersion` until the next TTL window.
    Component.onCompleted: {
        if (!checker.configStore)
            return;
        if (!checker.configStore.checkForUpdatesEnabled)
            return;
        if (UC.shouldRecheck(checker.configStore.lastUpdateCheck, Date.now(), checker.cacheTtlMs)) {
            checker.check();
        }
    }
}
