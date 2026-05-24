# Architecture

Ring Monitor is a KDE Plasma 6 widget. It uses the QML/QtQuick stack with
the KSysGuard sensor framework for live data and KConfig for persisted
settings.

## File layout

```
ring-monitor/
├── metadata.json                       — KPlugin descriptor
├── contents/
│   ├── config/
│   │   ├── main.xml                    — config schema (KConfigXT)
│   │   └── config.qml                  — config dialog category list
│   └── ui/
│       ├── main.qml                    — widget entry point
│       ├── Ring.qml                    — visual: one circular gauge (leaf, no Kirigami)
│       ├── MetricRow.qml               — visual: one row of the metrics list (leaf, no Kirigami)
│       ├── DraggableList.qml           — reusable drag-to-reorder ListView (leaf, no Kirigami)
│       ├── configMetrics.qml           — config page: enable/order
│       ├── configAppearance.qml        — config page: orientation + opacity
│       ├── ReorderLogic.js             — pure: drag math (testable)
│       ├── MetricsCatalog.js           — pure: metric data + CSV helpers
│       ├── RingGeometry.js             — pure: ring stroke/radius/sweep math
│       └── platform/                   — Plasma adapters (single home of org.kde.* imports)
│           ├── Theme.qml               — re-exposes Kirigami theme tokens
│           ├── ThemedIcon.qml          — wraps Kirigami.Icon
│           └── ConfigStore.qml         — re-exposes Plasmoid.configuration as typed properties
├── tests/
│   ├── reorder-logic.test.mjs
│   ├── metrics-catalog.test.mjs
│   └── ring-geometry.test.mjs
├── docs/                               — you are here
└── CLAUDE.md                           — short briefing for AI assistants
```

## Layering rule

Two directional rules:

1. **Views import from `.js` modules, never the reverse.**
2. **Leaf components (`Ring.qml`, `MetricRow.qml`, `DraggableList.qml`)
   never import `org.kde.*`.** They consume theme tokens through
   explicit properties; the parent (`main.qml`, `configMetrics.qml`)
   instantiates `platform/Theme.qml` and passes the values down.
   This is the plasma-isolation seam — see
   [`docs/plasma-isolation/plan.md`](plasma-isolation/plan.md).

```
config/*.xml        — schema (no logic)
       │
       ▼
configAppearance.qml ─┐
configMetrics.qml   ──┤
main.qml          ────┤── view layer (QML)
Ring.qml           ───┤
DraggableList.qml  ───┘
       │
       ▼
ReorderLogic.js
MetricsCatalog.js   — pure logic (JS, testable in Node)
RingGeometry.js
```

A QML view may compose other QML views (e.g. `configMetrics.qml` uses
`DraggableList.qml`). A `.js` module **must not import a `.qml` file** —
that would couple logic to Qt-only types and break Node testing.

## Data flow

```
ksysguard ──▶ Sensors.Sensor (main.qml) ──▶ Ring.qml (value binding)
                                              ▲
                                              │
              KConfig (cfg_*) ──────────────  │ (textOpacity, etc.)
                  │
                  │            cfg_metricOrder
                  ▼            cfg_enabledMetrics
            configMetrics.qml ──▶ orderModel ──▶ DraggableList.qml
                                                     │
                                                     ▼
                                            ReorderLogic.js
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
   the refactor — easy to drift.

Pure JS modules with `module.exports` shims are dual-loadable: QML consumes
them as namespaces, Node consumes them as CommonJS. The shim doesn't fire
in QML because the runtime has no `module` global. Tests are then
millisecond-fast and run in CI without a display.
