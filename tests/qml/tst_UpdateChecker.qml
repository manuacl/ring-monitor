import QtQuick
import QtTest
import "../../contents/ui/core" as Ui

// Smoke tests for UpdateChecker.qml — verifies the public surface and
// the dependency-injected reactivity (configStore changes propagate to
// updateAvailable / remoteVersion). The XMLHttpRequest path is NOT
// exercised: setting checkForUpdatesEnabled: false on the mock store
// short-circuits the auto-check in Component.onCompleted so no actual
// network call fires during the test run.

Item {
    id: root
    width: 100
    height: 100

    // Plain QtObject mock standing in for ConfigStore. UpdateChecker
    // only reads the four props + calls the two writers; we capture
    // the writer args in spies below.
    QtObject {
        id: mockStore
        property string localVersion: "0.4.0"
        property string latestKnownVersion: ""
        property string acknowledgedVersion: ""
        property bool checkForUpdatesEnabled: false   // suppress the XHR
        property double lastUpdateCheck: Date.now()   // fresh → would skip anyway

        property var lastRecordCall: null
        property var lastAcknowledgeCall: null
        function recordUpdateCheck(version, timestampMs) {
            lastRecordCall = {
                version: version,
                timestampMs: timestampMs
            };
            latestKnownVersion = version;
            lastUpdateCheck = timestampMs;
        }
        function acknowledgeVersion(version) {
            lastAcknowledgeCall = version;
            acknowledgedVersion = version;
        }
    }

    Ui.UpdateChecker {
        id: checker
        configStore: mockStore
    }

    TestCase {
        name: "UpdateChecker"
        when: windowShown

        function init() {
            mockStore.localVersion = "0.4.0";
            mockStore.latestKnownVersion = "";
            mockStore.acknowledgedVersion = "";
            mockStore.lastRecordCall = null;
            mockStore.lastAcknowledgeCall = null;
        }

        function test_initial_state_no_update() {
            // Fresh store, no remote known yet → no badge.
            verify(!checker.updateAvailable);
            compare(checker.remoteVersion, "");
        }

        function test_remote_equal_to_local_no_update() {
            mockStore.latestKnownVersion = "v0.4.0";
            verify(!checker.updateAvailable);
        }

        function test_remote_newer_than_local_update_available() {
            mockStore.latestKnownVersion = "v0.5.0";
            verify(checker.updateAvailable);
            compare(checker.remoteVersion, "v0.5.0");
        }

        function test_acknowledged_version_hides_badge() {
            mockStore.latestKnownVersion = "v0.5.0";
            verify(checker.updateAvailable);
            mockStore.acknowledgedVersion = "v0.5.0";
            verify(!checker.updateAvailable);
        }

        function test_acknowledge_writes_through_configstore() {
            mockStore.latestKnownVersion = "v0.5.0";
            checker.acknowledge();
            compare(mockStore.lastAcknowledgeCall, "v0.5.0");
        }

        function test_acknowledge_is_a_noop_without_remote() {
            // No remote known → don't persist a phantom acknowledgement.
            checker.acknowledge();
            compare(mockStore.lastAcknowledgeCall, null);
        }

        function test_public_url_properties_are_exposed() {
            // Both URLs are readonly knobs the standalone build could
            // override. Sanity-check they're non-empty.
            verify(checker.releasesApiUrl.toString().length > 0);
            verify(checker.storePageUrl.toString().length > 0);
        }

        function test_cache_ttl_is_24_hours() {
            // 24h in ms — the chosen value is documented in CLAUDE.md
            // section "Common pitfalls" and in docs/components.md.
            compare(checker.cacheTtlMs, 24 * 60 * 60 * 1000);
        }
    }
}
