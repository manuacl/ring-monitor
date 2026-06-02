import QtQuick
import QtQuick.Layouts
import "MetricsCatalog.js" as Catalog
import "ColorThemes.js" as ColorThemes
import "DiskMetrics.js" as DiskMetrics
import "DiskIoScale.js" as DiskIo
import "RingGeometry.js" as Geom
import "ProcessRanking.js" as ProcessRanking

// Body of the plasmoid's fullRepresentation. Renders the active rings
// in a horizontal or vertical strip based on configStore.orientation.
//
// Decoupled from Plasma: receives the three platform adapters (theme,
// configStore, metrics) as object properties so the parent
// PlasmoidItem (or a future standalone Window) wires them in. This
// file imports zero org.kde.* modules — that's the seam.
//
// The 3 adapters are typed `var` (not a specific QML type) because the
// standalone build will swap them for differently-implemented Items
// that expose the same property surface. See
// docs/plasma-isolation/plan.md.

GridLayout {
    id: content

    // ── Adapter inputs (injected by the parent) ──────────────────────
    property var theme
    property var configStore
    property var metrics
    // UpdateChecker (also injected) — exposes updateAvailable and the
    // openReleasePage / acknowledge / configureRequested actions used
    // by the in-widget badge.
    property var updateChecker
    signal configureRequested

    // ── Derived ──────────────────────────────────────────────────────
    //
    // The full enabled list = (CSV ∩ ordered). On top of that,
    // applyMergedTempMode drops cpuTemp / gpuTemp from the strip when
    // the user asked to merge them into the cpu / gpu ring AND both
    // sides are enabled (a merge with nothing to merge into stays a
    // standalone temperature ring).
    //
    // mergeWithCatalog the order before filtering: filterByOrder only keeps
    // enabled ids that appear in `metricOrder`, so a catalog metric missing
    // from the persisted order (a fresh metric an upgrading user hasn't
    // drag-reordered yet, or a host whose default order predates it) would be
    // enabled-but-never-rendered. Merging appends any missing catalog id (in
    // canonical order) so enabling it always shows the ring — same merge the
    // config picker applies in MetricsBody.loadOrder. Idempotent when the
    // order is already complete. (diskIo, #77, was the first opt-in metric to
    // expose this.)
    readonly property var _rawEnabledList: Catalog.filterByOrder(Catalog.parseCsv(content.configStore.enabledMetrics), Catalog.mergeWithCatalog(Catalog.parseCsv(content.configStore.metricOrder)))
    // Drop metrics with no live data source, but only after warm-up
    // (`loading` keeps the full strip during the 100% sweep), and BEFORE
    // applyMergedTempMode so split-mode never engages on an unavailable temp
    // metric. Full derivation chain: docs/components.md § MainContent.
    readonly property var _availableEnabledList: content.metrics.loading ? content._rawEnabledList : Catalog.filterByAvailable(content._rawEnabledList, content.metrics.availableMetrics)
    readonly property var enabledList: Catalog.applyMergedTempMode(content._availableEnabledList, content.configStore.mergeCpuTemp, content.configStore.mergeGpuTemp)
    readonly property bool vertical: content.configStore.orientation === "vertical"
    readonly property int count: Math.max(1, content.enabledList.length)

    // Effective temperature mode: "celsius" or "fahrenheit", resolved
    // from the user's preference + the system locale's measurement
    // system. Computed once at this layer and forwarded to delegates so
    // every ring uses the same unit.
    readonly property string _tempMode: Catalog.resolveTempMode(content.configStore.tempUnit, Qt.locale().measurementSystem)

    // Effective light/dark, resolved once at this layer from the
    // user's colorMode (auto/light/dark) against the live theme.
    // Both the ring-color and text-color bindings on every delegate
    // need it; computing it here means one `effectiveIsDark` call per
    // theme/mode change instead of 2×N (N = ring count) — and the
    // two delegate bindings below stay readable.
    readonly property bool _isDark: ColorThemes.effectiveIsDark(content.configStore.colorMode, content.theme.isDarkMode)

    // The shared ring color, resolved once here (identical for every ring).
    // It's also the fallback for disk partitions without a custom color.
    readonly property color _ringColor: ColorThemes.resolveSharedRingColor(content.configStore.colorTheme, content.configStore.colorMode, content.theme.isDarkMode, content.theme.highlightColor, content.configStore.customColorLight, content.configStore.customColorDark)

    // Disk multi-partition selection, resolved once here and shared by the
    // disk ring delegate. Partition ids in the user's configured display
    // order (first = outermost ring); order comes from
    // configStore.partitionOrder (default alphabetical), membership from
    // enabledPartitions. Empty selection → the platform default
    // (the $HOME filesystem on standalone, [] = aggregate on Plasma).
    readonly property var _orderedPartitionIds: DiskMetrics.orderPartitions(content.configStore.partitionOrder, content.metrics.availablePartitions || []).map(function (p) {
        return p.id;
    })
    // The user's explicit checkbox selection, in display order (enabled ∩
    // ordered; filterByOrder keeps the order).
    readonly property var _manualPartitionIds: Catalog.filterByOrder(Catalog.parseCsv(content.configStore.enabledPartitions), content._orderedPartitionIds)
    // Final disk-ring set = manual selection ∪ currently-mounted removable media
    // (auto-show), minus opt-outs, falling back to the platform default when
    // empty ($HOME FS on standalone, [] = aggregate on Plasma), capped at
    // DISK_MAX_RING_COUNT so the concentric stack stays readable and every radius
    // stays positive at the minimum ringSize. The manual ids are gated on
    // `metrics.mountedPartitionIds` (the live mount set) so an unmounted
    // partition's ring self-heals away even though ksysguard's tree freezes on
    // unmount (#58). `metrics.removablePartitions` / `mountedPartitionIds` exist
    // only on Plasma — the `|| []` (and undefined mountedIds) keep standalone
    // rendering exactly as before until Phase 4 ports them. The opt-out list comes
    // from configStore.partitionOptOut (parseCsv("") = []). See DiskMetrics.resolveDiskRingIds.
    readonly property var _diskSelectedIds: DiskMetrics.resolveDiskRingIds(content._manualPartitionIds, content.metrics.removablePartitions || [], Catalog.parseCsv(content.configStore.partitionOptOut), content.metrics.defaultPartitionIds || [], Geom.DISK_MAX_RING_COUNT, content.metrics.mountedPartitionIds)
    // Per-partition ring colors aligned to _diskSelectedIds (outermost first):
    // each partition's custom color, or the shared _ringColor when it has none
    // (issue #67). diskPartitionColors only exists once both adapters expose it;
    // the `|| ""` keeps older configStores rendering on the shared color.
    readonly property var _diskColors: DiskMetrics.resolveRingColors(content._diskSelectedIds, content.configStore.diskPartitionColors || "", content._ringColor)

    columns: vertical ? 1 : count
    // Spacing between rings is configurable as a percentage of
    // ringSize (default 7% — evaluates to 12px at the default
    // ringSize=180, matching the previous hardcoded value).
    // Proportional spacing keeps the visual balance whether the user
    // picked tiny or huge rings. Same formula in Main.qml for the
    // Window autosize.
    readonly property int _ringSize: (content.configStore && content.configStore.ringSize) || 180
    readonly property int _ringSpacingPercent: (content.configStore && content.configStore.ringSpacingPercent !== undefined) ? content.configStore.ringSpacingPercent : 7
    readonly property int _ringSpacing: Math.round(_ringSize * _ringSpacingPercent / 100)
    rowSpacing: _ringSpacing
    columnSpacing: _ringSpacing
    // The Plasma host (contents/ui/main.qml) mounts this Item as
    // `fullRepresentation` with no Layout.preferredWidth/Height
    // override, so the panel allocation is driven entirely by the
    // GridLayout's auto-implicit dimensions — i.e. the sum of
    // delegate Layout.preferredWidth/Height plus row/column spacing.
    // The Ring delegates below set `Layout.preferredWidth: _ringSize`
    // (and likewise for height), which naturally yields:
    //   horizontal: implicitWidth  = N*_ringSize + (N-1)*_ringSpacing
    //               implicitHeight = _ringSize
    //   vertical:   implicitWidth  = _ringSize
    //               implicitHeight = N*_ringSize + (N-1)*_ringSpacing
    // Do not try to override `implicitWidth/Height` on the GridLayout
    // directly — QQuickLayout silently overwrites those bindings from
    // its own children pass. The PR #35 review caught the symptom
    // (horizontal strip collapsing to a single-ring slot) and the
    // initial fix attempt of binding the formula on the layout was
    // ignored by Qt; the supported escape hatch is the per-delegate
    // preferred* properties. See tst_MainContent.qml for the
    // regression coverage.

    Repeater {
        id: ringRepeater
        model: content.enabledList

        delegate: Ring {
            id: ringDelegate
            required property string modelData
            required property int index

            // Three flavours of ring share this delegate:
            //   1. usage rings (cpu/ram/swap/gpu/disk) — value is a %
            //      → drives both sweep and centre text via `value`.
            //   2. temperature rings (cpuTemp/gpuTemp) — sensor reports
            //      raw °C → value = tempToPercent(°C) for sweep,
            //      rawValue = converted °C/°F for the centre text.
            //   3. merged cpu/gpu — usage on the left half, temp on
            //      the right half (split mode), triggered by the
            //      merge* config when both sides are enabled.
            readonly property bool _isTemp: Catalog.isTempMetric(modelData)
            readonly property bool _splitOn: Catalog.isSplitForBase(modelData, content._availableEnabledList, content.configStore.mergeCpuTemp, content.configStore.mergeGpuTemp)
            // Disk I/O throughput ring: a raw byte/s rate, not a %. The backend
            // exposes it via the `diskIo` property snapshot {readBps, writeBps,
            // combinedBps, readPercent, writePercent, combinedPercent}; the arc
            // uses the *Percent (auto-scaled), the centre label the *Bps through
            // DiskIo.formatRate. splitDiskIo renders read|write as two half-arcs
            // (reusing split mode), else a single combined arc.
            readonly property bool _isDiskIo: Catalog.isRateMetric(modelData)
            readonly property bool _diskIoSplit: _isDiskIo && content.configStore.splitDiskIo
            readonly property var _io: _isDiskIo ? (content.metrics.diskIo || null) : null
            // Disk multi-partition: one equal-thickness ring per selected
            // filesystem, centre = their average. Empty when not the disk
            // ring or when nothing resolved (→ aggregate single ring via the
            // normal `value` binding below). During loading every ring
            // sweeps to 100% like the others.
            readonly property bool _isDisk: modelData === "disk"
            readonly property var _diskValues: {
                if (!_isDisk)
                    return [];
                var ids = content._diskSelectedIds;
                if (content.metrics.loading)
                    return ids.map(function () {
                        return 100;
                    });
                return ids.map(function (id) {
                    return content.metrics.partitionValue(id);
                });
            }
            // Raw °C for the secondary readout (split right half OR
            // dedicated temp metric). Cheap query — always evaluated
            // for the metrics that have a temperature sensor.
            readonly property real _rawTempC: _isTemp ? content.metrics.metricValue(modelData) : (_splitOn ? content.metrics.metricRawTemp(modelData) : 0)
            // { value, unit } in the user's selected unit. Reused by
            // both the dedicated-temp-metric path and the split-mode
            // right-half path.
            readonly property var _tempInfo: (_isTemp || _splitOn) ? Catalog.convertTemp(_rawTempC, content._tempMode) : null

            // Layout.preferredWidth/Height drive the GridLayout's
            // auto-implicit dimensions (Layout silently ignores an
            // explicit `implicitWidth` set on itself, so the only
            // supported way to size the parent layout is via the
            // delegates' preferred*). fillWidth/fillHeight let the
            // rings expand when the host gives the widget more room
            // (e.g. standalone Window dragged wider); minimum*
            // protects against squashing below 80px.
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: content._ringSize
            Layout.preferredHeight: content._ringSize
            Layout.minimumWidth: 80
            Layout.minimumHeight: 80

            label: Catalog.labelFor(modelData)
            // During loading every ring sweeps to 100% — a "warming
            // up" visual cue. Once metrics.loading flips false (first
            // ksysguard tick lands), values animate down to actuals
            // via the existing Behavior on displayValue (400ms easing).
            // rawValue stays NaN during loading so the centre text
            // shows the same 100 → actual reveal as the sweep.
            //
            // For usage rings: value is the % directly. For temperature
            // rings: value drives the sweep so it must be the mapped
            // percent; the actual °C goes into rawValue below.
            // In disk equal mode the main arc is hidden, so `value` is never
            // rendered — skip metricValue("disk") to avoid an extra read whose
            // result is unused (on standalone it would kick an async statvfs
            // request for the home partition that nothing displays).
            value: {
                if (content.metrics.loading)
                    return 100;
                if (_isDisk && _diskValues.length > 0)
                    return 0;
                if (_isTemp)
                    return Catalog.tempToPercent(_rawTempC);
                // diskIo arc: left/read half in split mode, else the combined
                // sweep. The right/write half is splitValue below.
                if (_isDiskIo) {
                    if (!_io)
                        return 0;
                    return _diskIoSplit ? _io.readPercent : _io.combinedPercent;
                }
                return content.metrics.metricValue(modelData);
            }
            // Centre text: disk equal mode shows the partition average; temp
            // rings show the °C/°F reading; everything else falls back to
            // `value` (NaN sentinel). During loading rawValue stays NaN so
            // the centre reveals 100 → actual alongside the sweep.
            rawValue: {
                if (_isDisk && _diskValues.length > 0)
                    return content.metrics.loading ? NaN : DiskMetrics.averagePercent(_diskValues);
                if (!content.metrics.loading && _isTemp && _tempInfo)
                    return _tempInfo.value;
                return NaN;
            }
            unit: _isTemp && _tempInfo ? _tempInfo.unit : "%"
            nestedValues: modelData === "cpu" && content.configStore.showCpuCores ? content.metrics.coreValues : []
            // Equal-thickness concentric rings for the selected disk
            // partitions ([] for every other ring → normal single arc).
            equalValues: _diskValues
            // Per-partition custom colors (aligned to equalValues); a partition
            // without an override falls back to ringColor inside Ring. [] for
            // every non-disk ring.
            equalColors: ringDelegate._isDisk ? content._diskColors : []
            splitMode: _splitOn || _diskIoSplit
            // splitValue stays a percentage (0-100) so the geometry math
            // and tempToPercent threshold work in °C regardless of the
            // display unit; only splitRawValue / splitUnit change. For the
            // diskIo split it's the write half's auto-scaled percent.
            splitValue: {
                if (content.metrics.loading)
                    return 100;
                if (_diskIoSplit)
                    return _io ? _io.writePercent : 0;
                return _splitOn ? content.metrics.metricTempPercent(modelData) : 0;
            }
            splitRawValue: !content.metrics.loading && _splitOn && _tempInfo ? _tempInfo.value : 0
            splitUnit: _splitOn && _tempInfo ? _tempInfo.unit : ""
            // Preformatted MB/s centre labels for the diskIo ring (empty for
            // every other ring → the normal Math.round(rawValue)+unit path).
            // Combined → single label; split → read on the left (valueOverride),
            // write on the right (splitValueOverride). Empty during loading so
            // the warm-up shows the 100% sweep like the others.
            valueOverride: {
                if (!_isDiskIo || content.metrics.loading || !_io)
                    return "";
                return DiskIo.formatRate(_diskIoSplit ? _io.readBps : _io.combinedBps);
            }
            splitValueOverride: (_isDiskIo && _diskIoSplit && !content.metrics.loading && _io) ? DiskIo.formatRate(_io.writeBps) : ""
            // Shared color for every ring; disk partitions with a custom
            // color override it per-ring via equalColors above.
            ringColor: content._ringColor
            textColor: ColorThemes.resolveTextColor(content.configStore.textColorMode, content._isDark, content.theme.textColor, content.configStore.customTextColorLight, content.configStore.customTextColorDark)
            textOpacity: content.configStore.textOpacity
            trackOpacity: content.configStore.trackOpacity
            arcOpacity: content.configStore.arcOpacity

            // Update-available badge only on the first ring of the strip
            // — one notification per widget, anchored where the user's
            // eye lands first.
            showUpdateBadge: index === 0 && content.updateChecker !== undefined && content.updateChecker.updateAvailable
            onUpdateBadgeClicked: content.configureRequested()

            // CPU ring: hover reveals the top-processes tooltip (#69). Only
            // the cpu delegate is armed; the tooltip drives the backend's
            // processSamplingActive so /proc (standalone) / ProcessDataModel
            // (Plasma) runs ONLY while the tooltip is hovered — no background
            // process polling. Sampling starts on hover-enter so data is ready
            // by the time the (delayed) tooltip shows.
            ProcessTooltip {
                id: cpuTooltip
                armed: ringDelegate.modelData === "cpu"
                title: qsTr("Top processes — CPU")
                processes: content.metrics.topProcesses
                formatValue: function (p) {
                    return ProcessRanking.formatCpuPercent(p.cpuPercent);
                }
                footerText: qsTr("load") + "  " + ProcessRanking.formatLoadAverages(content.metrics.loadAverages)
            }
            Binding {
                target: content.metrics
                property: "processSamplingActive"
                value: cpuTooltip.samplingActive
                when: ringDelegate.modelData === "cpu"
            }
        }
    }

    // Disk-I/O sampling runs only while a diskIo ring is on screen: the backend
    // gates its /proc/diskstats poll (standalone) / ksysguard subscription
    // (Plasma) on this. Driven once at content scope (not per-delegate) since
    // there's a single diskIo ring. `when` guards a backend that predates the
    // surface (the alias is absent → the Binding is inert).
    Binding {
        target: content.metrics
        property: "diskIoSamplingActive"
        value: content.enabledList.indexOf("diskIo") >= 0
        when: content.metrics !== undefined && content.metrics.diskIoSamplingActive !== undefined
    }
}
