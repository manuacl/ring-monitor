import QtQuick
import QtTest
import "../../contents/ui/platform" as Platform

// Smoke test for the ConfigStore adapter.
//
// Limitations of this test compared to tst_Theme:
//   - ConfigStore reads from `Plasmoid.configuration`, which is a
//     context property injected by the Plasma shell. qmltestrunner
//     does NOT run inside a plasmoid host, so the property values
//     resolve to undefined at runtime.
//   - We assert that the adapter loads without errors and that each
//     declared property is accessible (typo guard). Asserting actual
//     values would require an in-process Plasma shell, which is out
//     of scope for this test runner.
//
// Real-world coverage of ConfigStore values happens via the manual
// post-PR walkthrough documented in
// docs/plasma-isolation/plan.md § PR 2.

Item {
    id: root
    width: 50
    height: 50

    Platform.ConfigStore {
        id: configStore
    }

    TestCase {
        name: "ConfigStore"
        when: windowShown

        function test_adapter_loads_and_exposes_all_keys() {
            verify(configStore !== null, "ConfigStore Item must instantiate");
            // Property name typo guard. Reading a missing property returns
            // undefined and would also throw a warning at runtime; reading
            // a declared property whose binding errors is silent. We only
            // check that the *names* exist on the object (catches a typo
            // like `arcOpacty` slipping in).
            const expected = ["metricOrder", "enabledMetrics", "showCpuCores", "orientation", "textOpacity", "trackOpacity", "arcOpacity"];
            for (const key of expected) {
                verify(configStore.hasOwnProperty(key), "ConfigStore must declare " + key);
            }
        }
    }
}
