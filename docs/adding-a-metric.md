# Adding a metric

The catalog is intentionally small: each metric is registered once in
`MetricsCatalog.js`, plus a `Sensors.Sensor` instance in `main.qml` and a
description string in `configMetrics.qml`. No other file needs editing.

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

`contents/ui/MetricsCatalog.js`:

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
entry in `configMetrics.qml` and look it up by id.

## Step 3: declare the sensor in `main.qml`

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

## Step 4: description in `configMetrics.qml`

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

## Caveat: non-percent sensors

`Ring.qml` assumes the input is 0–100. Sensors that report bytes/s,
temperatures, or absolute values need to be converted to a percentage of
some `max`:

- For rates: a configurable max (e.g. "100 Mbit/s baseline") or a
  rolling max from a small history.
- For temperatures: clamp into a sensible range (e.g. 30–90 °C maps to
  0–100%).

This isn't wired up yet — see the open question in `CLAUDE.md` for the
design sketch.
