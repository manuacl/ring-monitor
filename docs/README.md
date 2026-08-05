# Ring Monitor — Technical Documentation

Reference docs for contributors and future-Claude. Reads top-to-bottom or
as a directory.

- [Architecture](architecture.md) — high-level structure, file roles,
  data flow
- [Logic modules](logic-modules.md) — pure JS helpers in `contents/ui/core/*.js`
  and what they each do
- [Visual components](components.md) — `Ring.qml`, `DraggableList.qml`
- [Config dialog](config-dialog.md) — Plasma 6 config schema, KCM
  gotchas, KDE bug 484541
- [Adding a metric](adding-a-metric.md) — step-by-step
- [Testing](testing.md) — running and writing tests
- [Development workflow](development.md) — copy-based dev install,
  restarting plasmashell, using `plasmawindowed`, debugging
- [Releasing](releasing.md) — release flow (`version.yml` / `release.yml`),
  `bump:*` PR labels, KDE Store upload
- [Plasma-isolation plan](plasma-isolation/plan.md) — active multi-PR refactor
  isolating Plasma deps behind the `platforms/plasma/` adapter layer

The repo also ships a [CLAUDE.md](../CLAUDE.md) at the root — that's the
short briefing AI assistants load first. It points here for depth.
