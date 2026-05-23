# Ring Monitor

A modern minimal circular system monitor widget for KDE Plasma 6.

## Features

- Clean ring gauges using QtQuick.Shapes (no external dependencies beyond Plasma 6 + KSysGuard)
- Live data via Plasma 6's `org.kde.ksysguard.sensors` framework
- Themed via KDE color scheme (Kirigami.Theme)
- Currently displays: CPU usage, RAM usage

## Development

```bash
# Symlink for live dev
ln -s ~/projects/ring-monitor ~/.local/share/plasma/plasmoids/dev.manuacl.ringmonitor

# Preview standalone
plasmawindowed dev.manuacl.ringmonitor

# Install for desktop use
kpackagetool6 -t Plasma/Applet -i .
```

## License

GPL-3.0+
