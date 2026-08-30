# Battery ring — implementation spec

> Working document for issue #94 / PR #158. Produced by a scoping
> interview; the decision summary also lives as a comment on #94.
> **Delete this file when #158 merges** — the durable parts move to
> `docs/components.md` and `docs/logic-modules.md`. Same role as
> `docs/plasma-isolation/plan.md`.

## 1. Overview

### 1.1 Problem

On a laptop the battery is one of the most-glanced-at metrics, and the
widget has no ring for it. On a desktop there is no system battery, but
wireless peripherals (mouse, keyboard, headset) do carry one and their
charge is just as glanceable — and just as invisible today.

### 1.2 Solution

One `battery` metric that adapts its shape to the machine:

| Machine | Layout | Centre |
|---|---|---|
| System battery present (laptop) | System battery as the main arc; each selected peripheral as a thin concentric arc inside it | Charge %, plus a charge-state glyph |
| No system battery (desktop) | One equal-thickness ring per peripheral | Empty — arcs only, hover for detail |

Both layouts reuse mechanisms `Ring.qml` already has (`nestedValues` for
the CPU-cores layout, `equalValues` for the disk-partition layout), so
the feature adds no new drawing code.

### 1.3 Success criteria

- A laptop shows its charge % and a visible charging cue, identically on
  the Plasma and standalone hosts.
- A battery-less desktop with wireless peripherals shows one ring per
  peripheral, and never a fake system-battery ring.
- A desktop with no battery of any kind never shows the metric at all
  (availability interface, #52).
- Switching a peripheral off does not reshuffle the ring strip.

### 1.4 Non-goals

- Time-to-empty / time-to-full and power draw in watts — #94 already
  defers these to a follow-up tooltip issue (à la #70/#71).
- Low-battery notifications or any alerting.
- Per-battery rings for a multi-battery *system* pack: those fold into
  one value (§3.2). Only peripherals get one arc each.
- Charge-state reporting for peripherals (§3.3).

## 2. Users and use cases

| User | Machine | What they want at a glance |
|---|---|---|
| Laptop user | System battery, maybe a wireless mouse | Remaining charge; whether it is charging |
| Desktop user | No system battery, 1–4 wireless peripherals | Which peripheral is about to die |
| Dual-battery laptop user | Internal + slice pack | One honest overall percentage |

## 3. Functional requirements

### 3.1 Device discovery and classification

Devices split into two classes, and the split drives the whole layout.

**Plasma (ksystemstats).** Sensors live under `power/<udi>/…`. Verified
against the live daemon on the dev box (a desktop with no system
battery):

```
power/de-cb-a3-43/name = "Logitech G502"     capacity=0 design=0 charge=0 chargePercentage=58
power/98-fc-86-a2/name = "Logitech G915 TKL" capacity=0 design=0 charge=0 chargePercentage=67
```

Peripherals report `capacity`, `design` and `charge` as `0`. So:

- `design > 0` ⇒ system battery, and `design` is the weight for §3.2.
- `design == 0` ⇒ peripheral.
- Label comes from `power/<udi>/name`.

This is a *negative* test, which makes the degraded mode safe: a system
battery that reported `design == 0` would render as a peripheral arc
rather than vanish. **First implementation task: confirm on real laptop
hardware that a system battery reports `design > 0` through
ksystemstats.** If it does not, the spec needs a different discriminant
before the Plasma side can be written.

Sensor ids must be matched with an anchored regex
(`/^power\/[A-Za-z0-9_-]+\/chargePercentage$/`), not a substring test:
`SensorTreeModel` also surfaces regex *matcher* nodes, which is why
`classifyDiscoveredIds` anchors its patterns (see the
`disk/(?!all).*/usedPercent` SCENARIO test).

**Standalone (sysfs).** `/sys/class/power_supply/<dev>/` gives the split
directly:

- `type == "Battery"` and `scope` absent or `System` ⇒ system battery.
- `scope == "Device"` ⇒ peripheral.
- Label from `model_name`; weight from `energy_full`, else `charge_full`.

`scope` replaces the `BAT*` name filter the branch currently uses — it
is the declared meaning rather than a naming convention.

### 3.2 Multi-battery folding

Several *system* batteries fold into one value with a **capacity-weighted
mean**, on both hosts. Weights: `design` on Plasma, `energy_full` (else
`charge_full`) on standalone.

Two rules the current `BatteryAggregate.js` gets wrong:

- **One unit family per fold.** `energy_full` (µWh) and `charge_full`
  (µAh) are not comparable. If the batteries in one fold do not agree on
  a unit family, fall back to an unweighted mean for the whole fold
  rather than mixing magnitudes.
- **An invalid weight degrades the whole fold, not one record.** Today a
  record whose weight cannot be parsed gets `effectiveW = 0`, so it
  contributes nothing while still counting as valid — a 3 Wh + 72 Wh pack
  where one side lacks the file reports essentially the other battery
  alone. Any invalid weight ⇒ unweighted mean across every record.

`charging` is an OR across system batteries (unchanged).

Peripherals are never folded: each is its own arc.

### 3.3 Charge state

**Plasma reads the `org.kde.plasma.powermanagement` DataEngine through
plasma5support**, for its real state enum (`Charging` / `Discharging` /
`NoCharge`) and its AC Adapter source.

This replaces the branch's `chargeRate >= 0` heuristic, which is not
sound: `Solid::Battery::chargeRate()` derives from UPower's
`EnergyRate`, which upower normalises with `fabs()`, and ksystemstats
does not export `State`. On the dev box every `power/*/chargeRate` reads
`0`, which the heuristic reports as "charging". It also removes the
residual edge the branch documents (a battery idle at rest off AC
reading as charging), so the SCENARIO guard pinning that behaviour goes
away with it.

Standalone keeps `status` from sysfs (`Charging` / `Discharging` /
`Full`).

**Peripherals never carry a charge state.** Their reported status is not
trustworthy: both hidpp devices on the dev box sit at
`status=Discharging` permanently, at rest, on a charged battery.

### 3.4 Charge glyph

A lightning glyph rides **next to the centre number**, inside the centre
readout block, on the system battery only:

```
      ╱────────╲
    ╱            ╲
   │    78%⚡     │
    ╲            ╱
      ╲        ╱
         ───
```

Two states: charging, and a distinct mark for **full on AC**. Nothing is
drawn while discharging — absence is the discharging signal.

Constraints this placement inherits:

- The centre text already shrinks to 75% of `valuePx` in split mode and
  is offset by `Geom.splitReadoutOffset`. The glyph must follow the same
  offsets, and must not crowd the second readout in split mode.
- It must stay legible at the smallest ring size.
- The glyph is **not** an opacity change. The branch's dimming is
  removed: `0.55` is exactly `Ring.qml`'s `arcOpacityFactor` for
  subordinate nested arcs, so a discharging battery read as a sub-ring —
  and dropping it frees that opacity for the peripheral arcs, which
  *are* legitimately subordinate.

### 3.5 Selection, order and persistence

Peripherals get the same apparatus as disk partitions: a reorderable
list, a checkbox per device, a colour swatch per device, and a cap on
displayed rings (`Geom.DISK_MAX_RING_COUNT` = 6, or a battery-specific
equivalent).

**Defaults depend on the detected shape:**

- System battery present ⇒ the system battery only; peripherals are
  opt-in. Enabling "Battery" on a laptop gives exactly what #94 promises:
  a charge ring.
- No system battery ⇒ every discovered peripheral is on by default —
  otherwise the metric would render empty and report itself unavailable.

**A device seen once keeps its slot.** Switched off, it renders empty
rather than stale, and the user can forget it explicitly. This is the
existing stale-partition mechanism: `PartitionRow`'s `available: false`
variant is already a greyed row with a "not connected" tag and a trash
button.

### 3.6 Availability

`battery` is available when at least one device — system or peripheral —
is discovered. On a machine with neither, the metric never appears in
the picker and never renders a ring (#52).

### 3.7 Tooltip

Hovering the ring lists one row per shown device: label, percentage,
and the row tinted to that ring's colour. This is `DiskTooltip.qml`
retargeted; it already renders exactly this shape for partitions and
already samples **only while hovered**.

On the desktop layout the tooltip is load-bearing, not a nicety: with an
empty centre it is the only thing that says which arc is the mouse.

## 4. Architecture

### 4.1 What is reused

| Need | Existing component | Change |
|---|---|---|
| Peripheral arcs on a laptop | `Ring.nestedValues` | none |
| Peripheral rings on a desktop | `Ring.equalValues` + `equalColors` | none |
| Device picker | `DiskPartitionPicker.qml` (98 lines) | new sibling on the same pattern |
| Device row, incl. the disconnected variant | `PartitionRow.qml` | reuse; it is label-driven, not partition-specific |
| Drag-reorder | `DraggableList.qml` | none |
| Per-device tooltip | `DiskTooltip.qml` + `DiskTooltipModel.js` | retarget |
| Order / opt-out / stale / label cache / colours | `DiskMetrics.js` | **extract** (§4.2) |

### 4.2 New and changed modules

```
core/DeviceSelection.js      NEW — generic id/order/opt-out/stale/label-cache/colour
                                   machinery extracted from DiskMetrics.js;
                                   used by both partitions and batteries
core/BatteryAggregate.js     CHANGED — weighted fold fixes (§3.2)
core/MetricsCatalog.js       CHANGED — `battery` id, label, isBatteryMetric()
platforms/plasma/…           CHANGED — BatterySampler: anchored ids, design>0 split,
                                   PowerManagement state via plasma5support
platforms/standalone/…       CHANGED — scope-based split, cached discovery
```

`DiskMetrics.js` keeps only genuinely disk-specific logic (mount
semantics, removable detection, `buildPartitionDetail`) and delegates the
rest to `DeviceSelection.js`.

### 4.3 The 500-line cap is the binding constraint

Every file this feature touches is at or near the cap:

| File | Lines | Headroom |
|---|---|---|
| `core/Ring.qml` | 499 | 1 |
| `core/MainContent.qml` | 497 | 3 |
| `core/DiskMetrics.js` | 474 | 26 |
| `core/MetricsBody.qml` | 412 | 88 |

So extraction is a mechanical prerequisite, not a tidiness preference —
and `qmlformat` expands inline JS object literals, so a `.qml` file can
breach the cap on reformat alone. Plan each touched file's split before
writing code, not after CI fails.

### 4.4 Host contract

Both adapters expose the same surface to `core/`:

```
battery: {
    available:  bool,          // any device discovered
    hasSystem:  bool,          // drives which layout renders
    percent:    real,          // folded system charge (§3.2); NaN when !hasSystem
    state:      "charging" | "discharging" | "full-ac" | "unknown",
    devices:    [ { id, label, percent } ]   // peripherals, discovery order
}
```

`core/` never learns which host it is on — the layout switch reads
`hasSystem`, nothing else.

## 5. Edge cases

| Scenario | Expected behaviour |
|---|---|
| Desktop, no battery at all | Metric unavailable; absent from the picker and the strip |
| Desktop, all peripherals switched off | Slots reserved, rings render empty; the metric stays available |
| Peripheral switched on mid-session | Appears at the next spaced rescan (§6), not only on widget restart |
| Laptop, system battery reports `design == 0` | Classified as a peripheral — degraded but visible, never a vanished ring |
| Multi-battery pack, one weight unparseable | Unweighted mean across the whole fold (§3.2) |
| Multi-battery pack, mixed unit families | Unweighted mean across the whole fold (§3.2) |
| More peripherals than the ring cap | Capped like disks; the picker decides which ones |
| Warm-up sweep | The glyph does not render while `metrics.loading`; the battery ring behaves like every other ring on the first frame |
| Device forgotten via the trash button | Dropped from order, selection, label cache and colour map together |

## 6. Sampling

Discovery is resolved once and cached, the way `_resolveCpuTempPath`
caches the CPU-temperature path; only the percentages are read on the
main tick. A **spaced periodic rescan** picks up a device that comes
online.

The aggregate must not be reassigned when nothing changed: a fresh `var`
object notifies unconditionally, and `availableMetrics` reads
`battery.available`, so an unconditional assignment hands `MainContent` a
new array twice a second and rebuilds the whole ring strip.

**Both already hold on the branch** as of `29664db` (unpushed): standalone
sampling moved into `platforms/standalone/BatterySampler.qml` with cached
discovery, and availability gates on a change-gated scalar. The rule is
recorded here because the peripheral work re-enters the same code — a
per-tick device list would reintroduce it.

## 7. Testing

| Level | Scope |
|---|---|
| `node --test` | `DeviceSelection.js` (order, opt-out, stale, colours), `BatteryAggregate.js` (weighted fold, mixed units, invalid weight, all-invalid fallback), the sysfs and ksystemstats classifiers |
| `qmltestrunner` | The device picker rows, the two ring layouts, the glyph states, tooltip rows |
| SCENARIO guards | Peripherals must not be counted as system batteries; the strip must not rebuild on an unchanged sample |

`DeviceSelection.js` is extracted from code that already ships disk
behaviour, so the existing `DiskMetrics` tests are the safety net for
that refactor — run them before and after the extraction, unchanged.

Text-level Node guards apply to any QML file importing Plasma
(`tests/CLAUDE.md`).

## 8. Delivery

Everything lands in **PR #158**, which also carries the fixes from its
review and a rebase onto `main` (0.16.0 added the `sensorTemp` metric, so
`METRIC_IDS` conflicts and the catalog/`tst_MetricsBody` counts move from
9 to 10, with `battery` after `sensorTemp`). Recheck the CHANGELOG entry
lands under `## [Unreleased]` after that rebase.

**Baseline.** The local branch is one commit ahead of `origin`
(`29664db`, review follow-ups): standalone sampling extracted with cached
discovery, the 2 Hz strip rebuild gone, the Plasma `Instantiator`
restructured to hold both per-battery sensors in one delegate, and
`parseCapacity` clamped at the parse boundary. Steps below assume that
commit. Note it carries a `Co-Authored-By:` AI trailer, which the root
`CLAUDE.md` forbids — amend before it is pushed.

Suggested internal order, each step green before the next:

1. Verify `design > 0` on real laptop hardware (§3.1). Blocks the rest of Plasma.
2. Rebase onto `main`; fix the catalog counts and the CHANGELOG placement.
3. Extract `core/DeviceSelection.js`, disk behaviour unchanged, tests unchanged.
4. Fix `BatteryAggregate.js` weighting (§3.2).
5. Host adapters: classification, cached discovery, the §4.4 surface.
6. Plasma charge state via plasma5support.
7. Rendering: the two layouts, the glyph, the loading gate.
8. Picker, defaults, persistence, forget-a-device.
9. Tooltip.

### Risks

| Risk | Impact | Mitigation |
|---|---|---|
| `design` is not a reliable discriminant on real laptops | Blocks strict host parity | Step 1 verifies it first; the negative test degrades safely |
| The `DeviceSelection.js` extraction regresses shipped disk behaviour | High — touches a working feature | Existing `DiskMetrics` tests unchanged as the net; extract before adding battery callers |
| Touched files are at the 500-line cap | Churn, late CI failures | Plan each split up front (§4.3) |
| PR #158 grows large | Slower review | Internal ordering above keeps each step reviewable |

## 9. Open questions

- Glyph rendering technique: styled text inside `_composeReadout`, or an
  icon anchored to `valueText`? The centre readout is `Text.StyledText`,
  which constrains the options.
- `Ring.qml` currently always renders the centre readout in `equalValues`
  mode (it shows `rawValue`). The empty-centre desktop layout needs a way
  to suppress it — a `showReadout` bool is the smallest addition, but
  `Ring.qml` has 1 line of headroom.
- Whether the peripheral ring cap should be `DISK_MAX_RING_COUNT` or its
  own constant.
