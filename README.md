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

### KDE Plasma 6 (recommended: KDE Store)

The easiest way — no terminal, and Plasma will offer updates:

1. Right-click the desktop or a panel → **Add Widgets…**
2. Click **Get New Widgets… → Download New Plasma Widgets**.
3. Search for **Ring Monitor**, then **Install**.

It's then available in the **Add Widgets** panel. The widget is published
on the KDE Store at <https://www.opendesktop.org/p/2360410> — you can also
browse the page there directly.

#### Manual install (from source)

If you've cloned the repo (e.g. to run an unreleased version), install the
package straight from the working tree:

```bash
kpackagetool6 -t Plasma/Applet -i .
```

Then add "Ring Monitor" via Plasma's "Add Widgets" panel. Use
`kpackagetool6 -t Plasma/Applet -u .` to update an existing install.

### Standalone (non-KDE desktops)

A native Qt/QML build runs the same rings as a frameless desktop widget
on non-KDE desktops, with no Plasma shell, `libksysguard`, or `KConfig`
dependency (issue [#7](https://github.com/manuacl/ring-monitor/issues/7)).
It reads metrics directly from `/proc`, sysfs, and NVML.

> **Status: work in progress.** There is no packaged release yet — build
> from source as below. Supported desktops are EWMH stacking environments
> (KDE/KWin, GNOME/Mutter, XFCE/Xfwm4); tiling WMs and pure-Wayland
> compositors are out of scope for now. GPU is NVIDIA-only so far
> (AMD/Intel via sysfs is planned).

**Build dependencies:** CMake ≥ 3.16, a C++17 compiler, Qt 6.5+
(`Core Gui Qml Quick QuickControls2`), `xcb` (dev headers) and
`pkg-config`. NVIDIA GPU support needs no build dependency — the standalone
binary `dlopen`s `libnvidia-ml.so.1` at runtime (absent → the GPU ring
simply stays at 0, so the build runs on AMD/Intel boxes too).

```bash
# Fedora
sudo dnf install cmake gcc-c++ qt6-qtdeclarative-devel qt6-qtbase-devel libxcb-devel pkgconf
# Debian / Ubuntu
sudo apt install cmake g++ qt6-declarative-dev qt6-base-dev libxcb1-dev pkg-config
# Arch
sudo pacman -S cmake gcc qt6-declarative qt6-base libxcb pkgconf
```

**Build and run:**

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/ring-monitor-standalone
```

Right-click the widget for settings. To start it on login, enable
**"Start on login"** in those settings — it writes
`~/.config/autostart/dev.manuacl.ringmonitor.desktop` (no system-wide
install step is required).

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
`qmlformat`, and `qmltestrunner`. Windowed Plasma preview (still the
Plasma build, not the [standalone binary](#standalone-non-kde-desktops)):

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
