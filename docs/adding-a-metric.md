# Adding a metric

The catalog is intentionally small: each metric is registered once in
`core/MetricsCatalog.js`, plus a `Sensors.Sensor` instance in
`platforms/plasma/MetricsBackend.qml` and a description string in
`core/MetricsBody.qml`. No other file needs editing.

## Step 1: pick a sensor id

List available sensors on your machine:

```bash
busctl --user call org.kde.ksystemstats1 /org/kde/ksystemstats1 \
    org.kde.ksystemstats1 allSensors | tr "}" "\n" \
    | grep -oE '"[a-z]+/[^"]+"' | sort -u
```

Common ones:

- `cpu/all/usage`, `cpu/all/averageTemperature`, `cpu/cpu0/usage` …
- `memory/physical/usedPercent`, `memory/swap/usedPercent`
- `gpu/all/usage`, `gpu/all/usedVram`, `gpu/all/totalVram`
- `disk/all/usedPercent`, `disk/all/read`, `disk/all/write`
- `network/all/download`, `network/all/upload` (rates — see caveat below)
- `pressure/cpu/someTotal`, `pressure/memory/someTotal`, `pressure/io/someTotal`

## Step 2: register in the catalog

`contents/ui/core/MetricsCatalog.js`:

```js
var METRIC_IDS = ["cpu", "ram", "swap", "gpu", "disk", "net"];

var METRIC_LABELS = {
    // ... existing ...
    net: "NET",
};

var METRIC_SENSOR_IDS = {
    // ... existing ...
    net: "network/all/download",
};
```

If the label needs i18n, fall back to the QML side: add a `descriptions`
entry in `core/MetricsBody.qml` and look it up by id.

## Step 3: declare the sensor in `platforms/plasma/MetricsBackend.qml`

```qml
Sensors.Sensor { id: netSensor; sensorId: Catalog.sensorIdFor("net") }
```

and add to `sensorMap`:

```qml
readonly property var sensorMap: ({
    // ...
    net: netSensor,
})
```

## Step 4: description in `core/MetricsBody.qml`

```qml
readonly property var metricDescriptions: ({
    // ...
    net: i18n("Network download rate"),
})
```

## Step 5: update the schema default (optional)

If you want the new metric to appear pre-ordered in `cfg_metricOrder`,
update `contents/config/main.xml`:

```xml
<entry name="metricOrder" type="String">
    <default>cpu,ram,swap,gpu,disk,net</default>
</entry>
```

Existing users will keep their old order (KConfig preserves user values
over schema defaults); only fresh installs see the new default.

## Step 6: optional child sub-option

If the new metric has a per-metric setting (like CPU's "show cores as
concentric rings"), wire it as a child of the metric's row instead of
sticking it elsewhere in the dialog.

1. Add a `cfg_<key>` property + a `cfg_<key>Default` placeholder on
   `configMetrics.qml` (and an `<entry>` in `main.xml`).
2. Define a Component at page scope:
   ```qml
   Component {
       id: netLimitToggle
       QQC2.CheckBox {
           text: i18n("Use rolling max instead of fixed 100 Mbit/s")
           checked: page.cfg_netUseRollingMax
           onClicked: page.cfg_netUseRollingMax = checked
       }
   }
   ```
3. In `rowContent`, pass it as `extraContent` only when the row is yours:
   ```qml
   extraContent: _metricId === "net" ? netLimitToggle : null
   ```

`MetricRow` handles the rest: indent, height growth, and — when the
master CPU/NET/etc. checkbox is unticked — the child controls inherit
`enabled: false` (Qt cascades it, theme renders them disabled). See
`docs/components.md` → `MetricRow.qml` for the contract.

## Caveat: non-percent sensors

`Ring.qml` assumes the input is 0–100. Sensors that report bytes/s,
temperatures, or absolute values need to be converted to a percentage of
some `max`:

- For rates: a configurable max (e.g. "100 Mbit/s baseline") or a
  rolling max from a small history — the disk-I/O ring takes the rolling-max
  route (see "Pattern: rate metric" below).
- For temperatures: clamp into a sensible range
  (`MetricsCatalog.tempToPercent` defaults to 30–90 °C → 0–100%).

## Pattern: rate metric (disk I/O throughput, issue #77)

The disk-I/O ring is the canonical example of an **unbounded byte/s rate**
mapped onto the arc. It differs from a percent metric in three ways, all
generalisable to a future network-rate ring:

1. **Auto-scaling peak, not a fixed max.** `core/DiskIoScale.js` keeps a
   decaying rolling peak per component and fills the arc to `rate / peak`
   (`updatePeak` + `rateToPercent`). The numeric label always shows the real
   MB/s via `formatRate` — arc scale and displayed value are decoupled, the
   same `value` vs `rawValue` split temperature uses.
2. **A gated sampler child, not the sensor map.** Each platform has a
   `DiskIoSampler.qml` (standalone: `/proc/diskstats` deltas; Plasma:
   `disk/all/{read,write}` sensors) gated on an `active` property, so an
   off-screen ring polls nothing. `MetricsBackend` forwards a reactive `io`
   snapshot + the `diskIoSamplingActive` gate; `MainContent` drives the gate
   from whether the ring is in the enabled list. Classify the id in
   `MetricsCatalog.RATE_METRIC_IDS` (`isRateMetric`) so `MainContent`
   special-cases it like the disk multi-partition ring — it does **not** go
   through `metricValue` / the sensor map.
3. **A preformatted label via `Ring.valueOverride`.** Because the MB/s string
   (`formatRate`) carries a decimal `Math.round(rawValue) + unit` can't, the
   delegate passes `valueOverride` (and `splitValueOverride` for the split
   write half) instead of `rawValue`. Combined R+W is the default arc; the
   `splitDiskIo` toggle reuses split mode to show read|write.

## Pattern: split mode (CPU / GPU temperature)

The temperature half-arc on CPU and GPU is the canonical example of a
non-percent sensor wired through the split-mode pattern. Reuse it for
any metric that has both a primary % and a secondary value the user
wants on the same ring:

1. Add a temperature (or other secondary) sensor id to
   `METRIC_TEMP_SENSOR_IDS` in `MetricsCatalog.js`.
2. Declare the sensor in `MetricsBackend.qml`, add it to
   `tempSensorMap`. `metricRawTemp(id)` and `metricTempPercent(id)`
   pick it up automatically via `Catalog.valueFromSensorMap`.
3. Add a `<entry name="showXxxTemp" type="Bool">` to `main.xml` +
   the readonly alias on `ConfigStore.qml`.
4. In `MetricsBody.qml`, render a CheckBox under the metric's row via
   `extraContent` (the CPU row's `cpuExtras` ColumnLayout shows how to
   combine multiple sub-options for the same metric).
5. In `MainContent.qml`, the Ring delegate flips into split mode when
   the toggle is on and forwards `splitValue` / `splitRawValue`.

See `docs/components.md` → "Ring.qml" → "Split mode" for the geometry
contract.
