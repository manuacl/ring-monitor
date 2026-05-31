# Config dialog

## Schema (`contents/config/main.xml`)

`KConfigXT` declares the persisted keys, grouped by category:

```xml
<group name="Metrics">
    <entry name="metricOrder"       type="String"> <default>cpu,ram,swap,gpu,disk</default> </entry>
    <entry name="enabledMetrics"    type="String"> <default>cpu,ram</default> </entry>
    <entry name="enabledPartitions" type="String"> <default></default> </entry>
    <entry name="partitionOrder"    type="String"> <default></default> </entry>
    <entry name="partitionLabels"   type="String"> <default></default> </entry>
    <entry name="diskPartitionColors" type="String"> <default></default> </entry>
    <entry name="showCpuCores"      type="Bool">   <default>true</default> </entry>
</group>
<group name="Appearance">
    <entry name="orientation"          type="String"> <default>horizontal</default> </entry>
    <entry name="ringSize"             type="Int">    <default>180</default> ... </entry>
    <entry name="textOpacity"          type="Double"> <default>1.0</default> ... </entry>
    <entry name="trackOpacity"         type="Double"> <default>0.15</default> ... </entry>
    <entry name="arcOpacity"           type="Double"> <default>1.0</default> ... </entry>
    <entry name="colorTheme"           type="String"> <default>system</default> </entry>
    <entry name="colorMode"            type="String"> <default>auto</default> </entry>
    <entry name="customColorLight"     type="Color">  <default>#3daee9</default> </entry>
    <entry name="customColorDark"      type="Color">  <default>#3daee9</default> </entry>
    <entry name="textColorMode"        type="String"> <default>system</default> </entry>
    <entry name="customTextColorLight" type="Color">  <default>#232629</default> </entry>
    <entry name="customTextColorDark"  type="Color">  <default>#fcfcfc</default> </entry>
</group>
```

`enabledPartitions` is the disk multi-ring selection (CSV of checked
partition ids). Empty = the backend default: the `disk/all` aggregate
ring on Plasma (ksysguard exposes no mountpoint, so a "`$HOME` partition"
default isn't computable there), the `$HOME`-bearing filesystem on
standalone. `partitionOrder` is the **display order** of all discovered
partitions (CSV); first = outermost ring, last = innermost. Empty =
alphabetical by volume label. The picker is a **`DraggableList` nested in
the disk row** (`MetricsBody`) — drag a handle to reorder, which rewrites
`partitionOrder`. The checkbox no longer maps 1:1 to `enabledPartitions`:
it reflects **ring visibility** (`DiskMetrics.isPartitionShown`). A mounted
**removable** auto-shows a ring (#60) so its box is checked by default;
unchecking it adds the UUID to the **`partitionOptOut`** key (CSV) to hide it
(re-checking removes it). A **fixed** disk's box still toggles
`enabledPartitions`. Removables are kept out of `enabledPartitions` — they're
governed by `partitionOptOut` only. Same behaviour on standalone, which now
also auto-shows mounted removables.
The partition list is fed by `MetricsBody.diskPartitions`, which the
Plasma config wrapper populates from the shared `platforms/plasma/DiskPartitions.qml`
adapter (the KCM page has no `MetricsBackend` of its own). The pair mirrors
`metricOrder` + `enabledMetrics` exactly. `partitionLabels` is a JSON UUID→label
cache so a partition the user selected and then unplugged still shows its
last-known name on the picker's greyed "no longer connected" stale row (issue
#49) instead of a bare UUID.

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

## Update-check group (added in 0.5)

Four keys back the in-widget "new release" badge + the "Release" /
"New release" config page (see
[components.md](components.md#update-notification-flow) for the flow):

| Key | Type | Default | Written by |
|---|---|---|---|
| `checkForUpdatesEnabled` | `Bool` | `true` | the "Check for updates automatically" checkbox on the Release / New release config page (SimpleKCM `cfg_*` magic) |
| `lastUpdateCheck` | `Int64` | `0` | `core/UpdateChecker.qml` after a successful GitHub fetch — runtime path, not a config dialog |
| `latestKnownVersion` | `String` | `""` | same as above |
| `acknowledgedVersion` | `String` | `""` | the "Got it" button on the New release config page → `ConfigStore.acknowledgeVersion()` |

The last three are the **single exception** to the "writes go through
SimpleKCM `cfg_*`" rule documented above: they're persisted from the
widget's runtime path (the periodic update check) and from a button
inside the AboutBody, not from a typed config dialog. `ConfigStore.qml`
exposes two thin writers (`recordUpdateCheck`, `acknowledgeVersion`)
that keep the Plasma seam clean — see
[components.md → `ConfigStore.qml`](components.md#configstoreqml) for
the surface.

## Dynamic ConfigCategory ordering for the "New release" tab

Plasma 6's config dialog has **no "open-at-category" API** (verified
against `develop.kde.org/docs/plasma/widget/setup` and
`plasmaconfigplugin.qmltypes` — `ConfigCategory` only exposes
`name`, `icon`, `source`, `visible`). The first `ConfigCategory` is
always the default landing tab.

To land the in-widget update badge on the About page **without**
forcing every other config-open to also start there, `config.qml`
declares two `ConfigCategory` entries pointing at the same source
(`configAbout.qml`):

- top of sidebar, named **"New release"**, `visible: _hasUnseenUpdate`
- bottom of sidebar, named **"Release"**, `visible: !_hasUnseenUpdate`

`_hasUnseenUpdate` reads the persisted state through
`UpdateCheck.shouldNotify` — semver-aware so the tag-vs-version mismatch
(`"v0.4.0"` from KConfig, `"0.4.0"` from `Plasmoid.metaData.version`)
doesn't permanently pin the tab at the top.
