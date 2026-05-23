# Ring Monitor

[![CI](https://github.com/manuacl/ring-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/manuacl/ring-monitor/actions/workflows/ci.yml)

A modern minimal circular system monitor widget for KDE Plasma 6.

Clean 270° ring gauges driven by KSysGuard sensors, themed via the
current Plasma color scheme. Built from scratch as a learning project
for QML/Qt Quick.

## Metrics

- CPU usage (optional per-core concentric inner rings)
- RAM, SWAP, GPU, Disk

Order and visibility are user-configurable through the widget's config
dialog (drag to reorder, click to toggle).

## Install

```bash
kpackagetool6 -t Plasma/Applet -i .
```

Then add "Ring Monitor" via Plasma's "Add Widgets" panel.

## Develop

Symlink the repo into Plasma's plasmoid path so edits hot-reload:

```bash
ln -s "$PWD" ~/.local/share/plasma/plasmoids/dev.manuacl.ringmonitor
```

Enable the pre-commit hook (qmlformat + qmllint + 500-line size cap):

```bash
git config core.hooksPath .githooks
```

Run the test suite (Node logic + QML runtime):

```bash
tests/run-all.sh
```

You need `qt6-qtdeclarative-devel` + `kf6-kirigami` for `qmllint`,
`qmlformat`, and `qmltestrunner`. Standalone preview:

```bash
plasmawindowed dev.manuacl.ringmonitor
```

## Documentation

In-depth docs live under [`docs/`](docs/):

- [`architecture.md`](docs/architecture.md) — file roles, layering rule
- [`components.md`](docs/components.md) — `Ring`, `MetricRow`, `DraggableList`
- [`logic-modules.md`](docs/logic-modules.md) — pure JS modules
- [`config-dialog.md`](docs/config-dialog.md) — Plasma config gotchas
- [`adding-a-metric.md`](docs/adding-a-metric.md) — step-by-step
- [`testing.md`](docs/testing.md) — Node + QML test runners
- [`development.md`](docs/development.md) — symlink, journal, tooling

## License

[GPL-3.0-or-later](LICENSE).
