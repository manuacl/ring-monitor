# Architecture

Ring Monitor is a KDE Plasma 6 widget. It uses the QML/QtQuick stack with
the KSysGuard sensor framework for live data and KConfig for persisted
settings.

## File layout

```
ring-monitor/
├── metadata.json                       — KPlugin descriptor (Plasma build)
├── CMakeLists.txt                      — standalone build (Qt 6 executable)
├── standalone/
│   └── main.cpp                        — C++ entry for the standalone binary
├── contents/
│   ├── config/
│   │   ├── main.xml                    — config schema (KConfigXT)
│   │   └── config.qml                  — config dialog category list (Plasma)
│   └── ui/
│       ├── main.qml                    — Plasmoid host (wraps Core.MainContent + 3 adapters)
│       ├── configMetrics.qml           — Plasma wrapper (cfg_* aliases → Core.MetricsBody)
│       ├── configAppearance.qml        — Plasma wrapper (cfg_* aliases → Core.AppearanceBody)
│       ├── core/                       — portable subset (no org.kde.* imports — enforced)
│       │   ├── MainContent.qml         — body of the widget
│       │   ├── Ring.qml                — visual: one circular gauge (leaf)
│       │   ├── MetricRow.qml           — visual: one row of the metrics list (leaf)
│       │   ├── DraggableList.qml       — reusable drag-to-reorder ListView (uses Platform.ThemedIcon)
│       │   ├── MetricsBody.qml         — body of the Metrics page
│       │   ├── AppearanceBody.qml      — body of the Appearance page
│       │   ├── ReorderLogic.js         — pure: drag math (testable)
│       │   ├── MetricsCatalog.js       — pure: metric data + CSV helpers
│       │   ├── RingGeometry.js         — pure: ring stroke/radius/sweep math
│       │   └── SensorPicking.js        — pure: first-ready-wins sensor picking
│       └── platforms/                  — host-specific adapters (one subdir per target)
│           ├── plasma/                  — Plasma adapters (single home of org.kde.* imports)
│           │   ├── Theme.qml            — re-exposes Kirigami theme tokens
│           │   ├── ThemedIcon.qml       — wraps Kirigami.Icon
│           │   ├── ConfigStore.qml      — re-exposes Plasmoid.configuration as typed properties
│           │   └── MetricsBackend.qml   — wraps KSysGuard sensor instances
│           └── standalone/              — standalone adapters (no Plasma deps; /proc + sysfs)
│               └── Main.qml             — frameless transparent Window root (placeholder for now)
├── tests/
│   ├── reorder-logic.test.mjs
│   ├── metrics-catalog.test.mjs
│   ├── ring-geometry.test.mjs
│   ├── sensor-picking.test.mjs
│   ├── config-store.test.mjs          — text-level guard (no Plasma runtime in CI)
│   └── metrics-backend.test.mjs       — text-level guard (no Plasma runtime in CI)
├── docs/                               — you are here
└── CLAUDE.md                           — short briefing for AI assistants
```

The Plasma build is loaded by `plasmashell` directly from the source
tree via the symlink at `~/.local/share/plasma/plasmoids/dev.manuacl.ringmonitor`.
The standalone build is produced by `cmake -B build && cmake --build
build`, emitting a single `build/ring-monitor-standalone` binary that
embeds the QML as a compiled resource (no runtime filesystem
lookup). See [`docs/plasma-isolation/plan.md`](plasma-isolation/plan.md)
for the multi-PR standalone roadmap.

## Layering rule

Three directional rules:

1. **Views import from `.js` modules, never the reverse.**
2. **Nothing under `contents/ui/core/` imports `org.kde.*`.** This is
   the load-bearing invariant of the plasma-isolation seam, checked
   by the `finish-branch` skill on every branch. `core/` consumes
   theme tokens through explicit properties on a `theme: var` prop;
   the parent (`main.qml`, `configMetrics.qml`, `configAppearance.qml`)
   instantiates `platforms/plasma/Theme.qml` and passes the values
   down. `core/DraggableList.qml` uses `Platform.ThemedIcon` via the
   relative import `import "../platforms/plasma" as Platform` — Plasma is
   still hidden from `core/`, since the adapter file itself wraps the
   `Kirigami.Icon`.
3. **Top-level wrappers (`main.qml`, `configAppearance.qml`,
   `configMetrics.qml`) are the Plasma-specific shell.** They use
   `cfg_*` magic property bridges + `KCM.SimpleKCM` / `PlasmoidItem`,
   instantiate the three platform adapters, and pass them as `var`
   props down to `core/`. The bodies use `qsTr()` for i18n (works in
   both Plasma and standalone) and expose plain QML properties.

Together: the plasma-isolation seam — see
[`docs/plasma-isolation/plan.md`](plasma-isolation/plan.md).

```
config/*.xml        — schema (no logic)
       │
       ▼
configAppearance.qml ─┐
configMetrics.qml   ──┤── Plasma wrappers (cfg_* bridges)
main.qml          ────┘
       │
       ▼
core/MainContent.qml ─┐
core/MetricsBody.qml  ┤── portable view layer (no org.kde.*)
core/AppearanceBody.qml │
core/Ring.qml        ─┤
core/DraggableList.qml ┘
       │
       ▼
core/ReorderLogic.js
core/MetricsCatalog.js  — pure logic (JS, testable in Node)
core/RingGeometry.js
```

A QML view may compose other QML views (e.g. `configMetrics.qml` uses
`DraggableList.qml`). A `.js` module **must not import a `.qml` file** —
that would couple logic to Qt-only types and break Node testing.

## Data flow

```
ksysguard ──▶ platforms/plasma/MetricsBackend.qml ──▶ core/MainContent.qml ──▶ core/Ring.qml
                                                              ▲
                                                              │
              KConfig ──▶ platforms/plasma/ConfigStore.qml ──┘ (textOpacity, etc.)
                  │
                  │ cfg_metricOrder
                  │ cfg_enabledMetrics
                  ▼   (via property alias)
            configMetrics.qml ──▶ core/MetricsBody.qml ──▶ orderModel ──▶ core/DraggableList.qml
                                                                                 │
                                                                                 ▼
                                                                        core/ReorderLogic.js
```

Sensors are read-only push streams. The user-mutable state is in
`cfg_metricOrder` (CSV) and `cfg_enabledMetrics` (CSV); everything else
derives from them via `MetricsCatalog.filterByOrder` and friends.

## Why pure-JS helpers

QML's declarative bindings make it tempting to inline everything, but two
things go badly when logic lives only in QML:

1. **No tests.** QML scripts can be exercised by `qmltestrunner`, but
   that needs a running Qt + display server, and the surface is the whole
   component (visual + logic). Hard regressions to lock down.
2. **No reasoning across files.** The same metric metadata (label,
   sensor id) was duplicated in `main.qml` and `configMetrics.qml` until
   it was centralized in `core/MetricsCatalog.js` — easy to drift.

Pure JS modules with `module.exports` shims are dual-loadable: QML consumes
them as namespaces, Node consumes them as CommonJS. The shim doesn't fire
in QML because the runtime has no `module` global. Tests are then
millisecond-fast and run in CI without a display.
