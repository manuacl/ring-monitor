# Config dialog

## Schema (`contents/config/main.xml`)

`KConfigXT` declares the persisted keys, grouped by category:

```xml
<group name="Metrics">
    <entry name="metricOrder"    type="String"> <default>cpu,ram,swap,gpu,disk</default> </entry>
    <entry name="enabledMetrics" type="String"> <default>cpu,ram</default> </entry>
    <entry name="showCpuCores"   type="Bool">   <default>true</default> </entry>
</group>
<group name="Appearance">
    <entry name="orientation"  type="String"> <default>horizontal</default> </entry>
    <entry name="textOpacity"  type="Double"> <default>1.0</default> ... </entry>
    <entry name="trackOpacity" type="Double"> <default>0.15</default> ... </entry>
    <entry name="arcOpacity"   type="Double"> <default>1.0</default> ... </entry>
</group>
```

For each `<entry name="X">`, Plasma exposes:

- `Plasmoid.configuration.X` — read/write in the widget at runtime
- `cfg_X` — magic property bound to the persisted value, used in config
  pages

## Categories (`contents/config/config.qml`)

```qml
ConfigModel {
    ConfigCategory { name: i18n("Metrics");    source: "configMetrics.qml" }
    ConfigCategory { name: i18n("Appearance"); source: "configAppearance.qml" }
}
```

Each `source` is a `KCM.SimpleKCM` instance.

## Gotcha 1: KDE bug 484541 (cross-page cfg_* placeholders)

Plasma tries to set EVERY `cfg_<key>` from `main.xml` on EVERY config
page, not just the keys that page handles. If a page doesn't declare a
property for a key, the journal logs:

```
QML SimpleKCM: Setting initial properties failed: ConfigMetrics does not
have a property called cfg_orientation
```

In bad cases, the entire page fails to render.

Plasma 6 ALSO auto-generates `cfg_<key>Default` for the "Reset to
defaults" feature — placeholders are needed for those too.

**Fix:** in EVERY config page, declare empty placeholders for every
config key it doesn't handle, AND for the `Default` variant of every
key (including its own).

```qml
KCM.SimpleKCM {
    // Keys we actually handle
    property string cfg_orientation
    property alias  cfg_textOpacity: textSlider.value
    // ...

    // HACK: KDE bug 484541
    property var cfg_metricOrder
    property var cfg_metricOrderDefault
    property var cfg_enabledMetrics
    property var cfg_enabledMetricsDefault
    property var cfg_showCpuCores
    property var cfg_showCpuCoresDefault
    property var cfg_orientationDefault
    property var cfg_textOpacityDefault
    // ... etc
}
```

## Gotcha 2: `KCM.SimpleKCM` can't have `anchors.fill: parent` content

The child of `SimpleKCM` must size itself implicitly. Using
`anchors.fill: parent` on a `ColumnLayout` child triggers:

```
QQuickItem::createGraphicalObject: Created graphical object was not
placed in the graphics scene.
```

…and the page renders blank.

**Fix:** use `Layout.fillWidth: true` on the layout child and let it size
vertically by its content.

## Gotcha 3: `AnchorChanges` does NOT support `anchors.fill`

When toggling layouts in a State, you have to undo each of the four
anchors that `fill` implicitly sets — you cannot write
`anchors.fill: undefined`.

```qml
AnchorChanges {
    target: someItem
    anchors.top: undefined
    anchors.bottom: undefined
    anchors.left: undefined
    anchors.right: undefined
}
```

Writing `anchors.fill: undefined` triggers "Cannot assign to non-existent
property 'fill'" and the whole QML file fails to load.

## Gotcha 4: schema changes need a plasmashell restart

After editing `main.xml`, you must restart plasmashell for the new keys
to be picked up:

```bash
systemctl --user restart plasma-plasmashell.service
```

Editing QML alone is hot-reloaded by the symlink (see
[development.md](development.md)), but config schema changes are not.
