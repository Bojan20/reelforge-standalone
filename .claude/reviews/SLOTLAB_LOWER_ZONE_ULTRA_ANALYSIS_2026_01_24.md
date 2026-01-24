# SlotLab Lower Zone — Ultra Analysis

**Date:** 2026-01-24
**Analyst Roles:** Chief Audio Architect, UI/UX Expert, Engine Architect, Technical Director

---

## PART 1: COMPLETE DOCUMENTATION

### 1.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ SPIN CONTROL BAR (32px)                                                      │
│ [Outcome ▼] [Volatility ▼] [Timing ▼] [Grid ▼] [Spin] [▶/⏸] [⏹] [X/Y]      │
├─────────────────────────────────────────────────────────────────────────────┤
│ CONTEXT BAR (60px expanded / 32px collapsed)                                 │
│ SUPER-TABS: [1-STAGES] [2-EVENTS] [3-MIX] [4-DSP] [5-BAKE]                   │
│ SUB-TABS:   [Q-Trace] [W-Timeline] [E-Symbols] [R-Timing]                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                         CONTENT PANEL (flexible)                             │
│                         150-600px height range                               │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│ ACTION STRIP (36px)                                                          │
│ [Context Actions...] ─────────────────────────────── Status: Stages: X       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 File Structure

| File | LOC | Purpose |
|------|-----|---------|
| `slotlab_lower_zone_widget.dart` | ~2350 | Main widget + all panel implementations |
| `slotlab_lower_zone_controller.dart` | ~242 | State management, keyboard, persistence |
| `lower_zone_types.dart` | ~1216 | Enums, state classes, shared widgets |

### 1.3 Tab Hierarchy

```
SLOTLAB LOWER ZONE
├── 1-STAGES
│   ├── Q-Trace      → StageTraceWidget
│   ├── W-Timeline   → _buildCompactEventTimeline()
│   ├── E-Symbols    → _buildCompactSymbolsPanel()
│   └── R-Timing     → ProfilerPanel
├── 2-EVENTS
│   ├── Q-Folder     → _buildCompactEventFolder()
│   ├── W-Editor     → _buildCompactCompositeEditor()
│   ├── E-Layers     → EventLogPanel
│   └── R-Pool       → _buildCompactVoicePool()
├── 3-MIX
│   ├── Q-Buses      → BusHierarchyPanel
│   ├── W-Sends      → AuxSendsPanel
│   ├── E-Pan        → _buildCompactPanPanel()
│   └── R-Meter      → RealTimeBusMeters
├── 4-DSP
│   ├── Q-Chain      → _buildCompactDspChain()
│   ├── W-EQ         → FabFilterEqPanel
│   ├── E-Comp       → FabFilterCompressorPanel
│   └── R-Reverb     → FabFilterReverbPanel
└── 5-BAKE
    ├── Q-Export     → SlotLabBatchExportPanel
    ├── W-Stems      → _buildCompactStemsPanel()
    ├── E-Variations → _buildCompactVariationsPanel()
    └── R-Package    → _buildCompactPackagePanel()
```

---

## PART 2: CONNECTION ANALYSIS

### Legend
- ✅ **CONNECTED** — Fully wired to provider/FFI, functional
- ⚠️ **PARTIAL** — Connected but incomplete functionality
- ❌ **NOT CONNECTED** — UI only, no backend integration
- 🔧 **HARDCODED** — Uses static/mock data instead of real state

---

### 2.1 SPIN CONTROL BAR

| Element | Type | Connection Status | Details |
|---------|------|-------------------|---------|
| **Outcome Dropdown** | DropdownButton | ⚠️ PARTIAL | Values hardcoded, callback `widget.onOutcomeChanged` exists but not always wired |
| **Volatility Dropdown** | DropdownButton | ⚠️ PARTIAL | Values hardcoded, callback exists |
| **Timing Dropdown** | DropdownButton | ⚠️ PARTIAL | Values hardcoded, callback exists |
| **Grid Dropdown** | DropdownButton | ⚠️ PARTIAL | Values hardcoded, callback exists |
| **Spin Button** | GestureDetector | ✅ CONNECTED | `widget.onSpin` callback |
| **Play/Pause Button** | GestureDetector | ✅ CONNECTED | `widget.onPause`, `widget.onResume`, reads `provider.isPlayingStages`, `provider.isPaused` |
| **Stop Button** | GestureDetector | ✅ CONNECTED | `widget.onStop` callback |
| **Stage Progress** | Text | ✅ CONNECTED | `provider.currentStageIndex + 1 / provider.lastStages.length` |

**Issues Found:**
1. Dropdowns have callbacks but parent widget doesn't always pass handlers
2. No validation that dropdown values match `TimingProfile` enum in Rust
3. Grid dropdown values don't match any backend model

---

### 2.2 STAGES TAB

#### 2.2.1 Trace Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| StageTraceWidget | ✅ CONNECTED | `provider: SlotLabProvider`, `onAudioDropped` callback |
| Height | ✅ CONNECTED | LayoutBuilder dynamic height |

#### 2.2.2 Timeline Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| Stage List | ✅ CONNECTED | `SlotLabProvider.lastStages` |
| Stage Count Badge | ✅ CONNECTED | `stages.length` |
| Stage Items | ✅ CONNECTED | `stage.name`, `stage.timestamp` |
| Play Icon per Stage | ❌ NOT CONNECTED | Icon exists but no onTap handler |

**Issues Found:**
1. Play icon on each stage has no functionality — should trigger stage preview

#### 2.2.3 Symbols Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| Symbol List | 🔧 HARDCODED | Static list: `WILD, SCATTER, BONUS, 7, CHERRY, BELL, BAR, GRAPE, ORANGE, PLUM` |
| Has Audio Check | ✅ CONNECTED | Checks `MiddlewareProvider.compositeEvents` for `SYMBOL_LAND_$symbol` stages |
| Mapped Count | ✅ CONNECTED | `mappedSymbols.length / symbols.length` |
| Symbol Cards | ❌ NOT CONNECTED | No click handler, no drag-drop target |

**Issues Found:**
1. Symbol list is hardcoded — should come from `SlotLabProjectProvider.symbols`
2. Symbol cards are not interactive — can't click to assign audio
3. No drag-drop support for audio assignment

#### 2.2.4 Timing Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| ProfilerPanel | ✅ CONNECTED | External widget with FFI integration |

---

### 2.3 EVENTS TAB

#### 2.3.1 Folder Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| Event List | ✅ CONNECTED | `MiddlewareProvider.compositeEvents` |
| Category Tree | ✅ CONNECTED | Grouped by `event.category` |
| Category Selection | ✅ CONNECTED | Local state `_selectedCategory` |
| Event Selection | ✅ CONNECTED | `middleware.selectCompositeEvent(event.id)` |
| New Event Button | ✅ CONNECTED | `middleware.createCompositeEvent()` |
| Event Play Button | ❌ NOT CONNECTED | `// TODO: Connect to preview playback` comment in code |
| Event Color Dot | ✅ CONNECTED | `event.color` |
| Layer Count Badge | ✅ CONNECTED | `event.layers.length` |
| Trigger Stages | ✅ CONNECTED | `event.triggerStages.take(2)` |

**Issues Found:**
1. Play button on events does nothing — critical missing feature
2. No delete event functionality in this panel
3. No rename event functionality
4. No drag-drop reordering of events

#### 2.3.2 Editor Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| Event Dropdown | ✅ CONNECTED | Lists all events, `_selectedEventId` state |
| Event Header | ✅ CONNECTED | `selectedEvent.name`, layer count |
| Layer List | ✅ CONNECTED | `selectedEvent.layers` |
| Layer Audio Path | ✅ CONNECTED | `layer.audioPath.split('/').last` |
| Layer Delay | ✅ CONNECTED | `layer.offsetMs` (display only) |
| Layer Volume | ✅ CONNECTED | `layer.volume` (display only) |
| Drag Handle | ❌ NOT CONNECTED | Icon only, no drag functionality |
| Layer Play Button | ❌ NOT CONNECTED | Icon only, no handler |

**Issues Found:**
1. Layer parameters are DISPLAY ONLY — cannot edit delay/volume
2. Drag handle doesn't work — can't reorder layers
3. Layer play button doesn't work — can't preview individual layers
4. No add layer button in this panel
5. No delete layer button
6. Doesn't sync with `middleware.selectedCompositeEvent`

#### 2.3.3 Event Log Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| EventLogPanel | ✅ CONNECTED | External widget, requires both providers |

#### 2.3.4 Voice Pool Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| Total Voices | ✅ CONNECTED | `middleware.getVoicePoolStats().maxVoices` |
| Active Voices | ✅ CONNECTED | `stats.activeVoices` |
| Virtual Voices | ✅ CONNECTED | `stats.virtualVoices` |
| Steal Count | ✅ CONNECTED | `stats.stealCount` |
| Usage Bar | ✅ CONNECTED | Calculated percentage |
| Per-Bus Stats | 🔧 HARDCODED | **FAKE DATA** — uses hardcoded percentages: SFX=35%, Music=15%, etc. |

**Issues Found:**
1. **CRITICAL:** Per-bus voice stats are FAKE — calculated from total using hardcoded ratios
2. No real per-bus tracking from engine
3. No voice stealing mode selector
4. No priority visualization

---

### 2.4 MIX TAB

#### 2.4.1 Buses Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| BusHierarchyPanel | ✅ CONNECTED | External widget |

#### 2.4.2 Sends Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| AuxSendsPanel | ✅ CONNECTED | External widget |

#### 2.4.3 Pan Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| Channel List | 🔧 HARDCODED | Static: SFX, Music, Voice, Ambient |
| Pan Values | 🔧 HARDCODED | Static values: 0.0, 0.0, 0.1, 0.0 |
| Pan Indicator | ❌ NOT CONNECTED | Visual only, not draggable |

**Issues Found:**
1. **CRITICAL:** Pan values are completely hardcoded — NOT reading from any provider
2. Pan indicator is not interactive — can't drag to change pan
3. Missing bus list from actual engine
4. No FFI calls to set pan values

#### 2.4.4 Meter Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| RealTimeBusMeters | ✅ CONNECTED | External widget with FFI |

---

### 2.5 DSP TAB

#### 2.5.1 Chain Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| Node List | 🔧 HARDCODED | Static: IN → EQ → COMP → LIM → REV → OUT |
| Active States | 🔧 HARDCODED | Static: EQ=active, COMP=active, LIM=inactive, REV=active |
| Node Click | ❌ NOT CONNECTED | No click handler |

**Issues Found:**
1. **CRITICAL:** DSP chain is completely hardcoded — NOT reading from `DspChainProvider`
2. Node active states are fake
3. Nodes are not clickable — can't toggle bypass
4. No drag-drop reordering
5. No add/remove processor functionality

#### 2.5.2 EQ Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| FabFilterEqPanel | ✅ CONNECTED | `trackId: 0` (master), connects to DspChainProvider |

#### 2.5.3 Compressor Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| FabFilterCompressorPanel | ✅ CONNECTED | `trackId: 0` |

#### 2.5.4 Reverb Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| FabFilterReverbPanel | ✅ CONNECTED | `trackId: 0` |

---

### 2.6 BAKE TAB

#### 2.6.1 Export Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| SlotLabBatchExportPanel | ✅ CONNECTED | External widget |

#### 2.6.2 Stems Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| Bus List | 🔧 HARDCODED | Static: SFX, Music, Voice, Ambience, UI, Master |
| Selected States | 🔧 HARDCODED | Static selection pattern |
| Checkbox Toggle | ❌ NOT CONNECTED | No setState, no callback |
| Export Stems Button | ❌ NOT CONNECTED | Empty `onTap: () {}` |

**Issues Found:**
1. **CRITICAL:** Bus list hardcoded — should come from `MixerDSPProvider`
2. Checkboxes don't work — clicking does nothing
3. Export button does nothing

#### 2.6.3 Variations Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| Variation Count | ✅ CONNECTED | `randomContainers.fold(sum + children.length)` |
| Pitch Slider | 🔧 HARDCODED | Static value 0.1 |
| Volume Slider | 🔧 HARDCODED | Static value 0.05 |
| Pan Slider | 🔧 HARDCODED | Static value 0.2 |
| Delay Slider | 🔧 HARDCODED | Static value 0.15 |
| Refresh Button | ❌ NOT CONNECTED | Empty `onTap: () {}` |
| Generate Button | ❌ NOT CONNECTED | Empty `onTap: () {}` |

**Issues Found:**
1. All slider values are hardcoded — not editable
2. No actual variation generation logic
3. Buttons do nothing

#### 2.6.4 Package Panel
| Element | Connection Status | Details |
|---------|-------------------|---------|
| Event Count | ✅ CONNECTED | `middleware.compositeEvents.length` |
| Est. Size | ✅ CONNECTED | Calculated from event count |
| Platform Option | 🔧 HARDCODED | Static "All" |
| Compression Option | 🔧 HARDCODED | Static "Vorbis Q6" |
| Build Package Button | ❌ NOT CONNECTED | Empty `onTap: () {}` |

**Issues Found:**
1. Platform/Compression not selectable
2. Build button does nothing
3. No actual package building logic

---

### 2.7 ACTION STRIP

| Super-Tab | Action | Connection Status | Details |
|-----------|--------|-------------------|---------|
| **STAGES** | Record | ✅ CONNECTED | `slotLab.startStageRecording()` |
| **STAGES** | Stop | ✅ CONNECTED | `slotLab.stopStageRecording()` |
| **STAGES** | Clear | ✅ CONNECTED | `slotLab.clearStages()` |
| **STAGES** | Export | ⚠️ PARTIAL | `debugPrint` only, TODO comment |
| **EVENTS** | Add Layer | ⚠️ PARTIAL | `debugPrint` only |
| **EVENTS** | Remove | ✅ CONNECTED | `middleware.removeLayerFromEvent()` |
| **EVENTS** | Duplicate | ✅ CONNECTED | `middleware.duplicateCompositeEvent()` |
| **EVENTS** | Preview | ✅ CONNECTED | `middleware.previewCompositeEvent()` |
| **MIX** | Mute | ❌ NOT CONNECTED | `debugPrint` only |
| **MIX** | Solo | ❌ NOT CONNECTED | `debugPrint` only |
| **MIX** | Reset | ❌ NOT CONNECTED | `debugPrint` only |
| **MIX** | Meters | ✅ CONNECTED | `controller.setSubTabIndex(3)` |
| **DSP** | Insert | ❌ NOT CONNECTED | `debugPrint` only |
| **DSP** | Remove | ❌ NOT CONNECTED | `debugPrint` only |
| **DSP** | Reorder | ❌ NOT CONNECTED | `debugPrint` only |
| **DSP** | Copy Chain | ❌ NOT CONNECTED | `debugPrint` only |
| **BAKE** | Validate | ❌ NOT CONNECTED | `debugPrint` only |
| **BAKE** | Bake All | ❌ NOT CONNECTED | `debugPrint` only |
| **BAKE** | Package | ❌ NOT CONNECTED | `debugPrint` only |

---

## PART 3: CONNECTION SUMMARY

### Statistics

| Category | Connected | Partial | Not Connected | Hardcoded |
|----------|-----------|---------|---------------|-----------|
| Spin Control Bar | 4 | 4 | 0 | 0 |
| STAGES Tab | 6 | 0 | 2 | 1 |
| EVENTS Tab | 14 | 0 | 6 | 1 |
| MIX Tab | 2 | 0 | 1 | 2 |
| DSP Tab | 3 | 0 | 1 | 2 |
| BAKE Tab | 2 | 0 | 4 | 6 |
| Action Strip | 6 | 2 | 9 | 0 |
| **TOTAL** | **37** | **6** | **23** | **12** |

### Connection Rate: **47%** (37/78 elements fully connected)

---

## PART 4: UI/UX ANALYSIS

### 4.1 Role: UI/UX Expert (DAW Workflows, Pro Audio UX)

#### 4.1.1 Information Architecture

| Aspect | Rating | Analysis |
|--------|--------|----------|
| **Tab Organization** | ⭐⭐⭐⭐ (4/5) | Logical grouping: Stages→Events→Mix→DSP→Bake follows audio production workflow |
| **Sub-tab Naming** | ⭐⭐⭐ (3/5) | "Layers" should be "Log" (it's EventLogPanel), "Pool" is technical jargon |
| **Discoverability** | ⭐⭐ (2/5) | Keyboard shortcuts not visible without documentation |
| **Consistency** | ⭐⭐⭐ (3/5) | Inconsistent panel layouts — some use grids, some use lists |

#### 4.1.2 Interaction Design

| Aspect | Rating | Analysis |
|--------|--------|----------|
| **Clickability** | ⭐⭐ (2/5) | Many visual elements look clickable but aren't (layer play buttons, symbol cards) |
| **Drag-Drop** | ⭐ (1/5) | Drag handles exist but don't work; no drop zones in most panels |
| **Feedback** | ⭐⭐⭐ (3/5) | Selection highlights work, but no feedback on non-functional clicks |
| **Error States** | ⭐⭐ (2/5) | "No provider" fallback exists, but no error feedback for failed actions |

#### 4.1.3 Visual Design

| Aspect | Rating | Analysis |
|--------|--------|----------|
| **Density** | ⭐⭐⭐⭐ (4/5) | Good information density for pro users |
| **Color Coding** | ⭐⭐⭐⭐ (4/5) | Consistent accent color, warning colors for high usage |
| **Typography** | ⭐⭐⭐ (3/5) | Font sizes are small (8-10px) — may be hard to read |
| **Spacing** | ⭐⭐⭐ (3/5) | Compact but sometimes cramped |

#### 4.1.4 Workflow Analysis

**Positive:**
1. Tab structure follows logical audio design workflow
2. Stage trace → Event creation → Mixing → Export is correct sequence
3. Keyboard shortcuts (1-5, Q-R) enable fast navigation

**Negative:**
1. **Dead Ends:** User clicks play on event → nothing happens → confusion
2. **Broken Workflows:**
   - Can't edit layer parameters in Editor panel
   - Can't reorder layers via drag
   - Can't assign audio to symbols directly
3. **Missing Feedback:** No indication that buttons are non-functional
4. **Context Loss:** Selecting event in Folder doesn't sync with Editor dropdown

---

### 4.2 Role: Chief Audio Architect

#### 4.2.1 Audio Integration Analysis

| Feature | Status | Impact |
|---------|--------|--------|
| **Stage-to-Audio Mapping** | ✅ Working | EventRegistry handles stage→event→audio flow |
| **Voice Pool Monitoring** | ⚠️ Fake Data | Per-bus stats are calculated, not real — misleading |
| **Bus Routing Visibility** | ✅ Working | BusHierarchyPanel and AuxSendsPanel are connected |
| **DSP Chain State** | ❌ Broken | Chain panel shows fake data, not actual insert chain |
| **Real-time Metering** | ✅ Working | RealTimeBusMeters has FFI integration |
| **Spatial Panning** | ❌ Broken | Pan panel is completely static |

#### 4.2.2 Critical Audio Issues

1. **Voice Pool Fake Stats:** Designer sees "SFX: 5/16" but this is calculated from total using hardcoded ratios — not real engine data. This could lead to wrong mixing decisions.

2. **DSP Chain Disconnect:** FabFilter panels work, but Chain visualization shows hardcoded data. User might think LIM is bypassed when it's actually active.

3. **Pan Panel Non-functional:** Audio designer cannot adjust per-bus panning from this panel — must go elsewhere or use code.

---

### 4.3 Role: Engine Architect

#### 4.3.1 Provider Integration Analysis

| Provider | Usage in SlotLab LZ | Connection Quality |
|----------|---------------------|-------------------|
| `SlotLabProvider` | Stages, playback state | ✅ Good |
| `MiddlewareProvider` | Events, containers, pool stats | ✅ Good |
| `DspChainProvider` | Should power Chain panel | ❌ Not Used |
| `MixerDSPProvider` | Should power Pan/Stems | ❌ Not Used |
| `SlotLabProjectProvider` | Should power Symbols | ❌ Not Used |

#### 4.3.2 Performance Concerns

1. **Rebuild Frequency:** Multiple `Consumer` widgets could cause excessive rebuilds
2. **LayoutBuilder Usage:** Good — allows dynamic sizing without hardcoding
3. **ListView shrinkWrap:** Used correctly to avoid infinite height issues

#### 4.3.3 State Management Issues

1. **Local State Conflicts:**
   - `_selectedCategory` in Folder panel
   - `_selectedEventId` in Editor panel
   - These don't sync with provider selection state

2. **Missing Provider Connections:**
   - `DspChainProvider` exists but Chain panel ignores it
   - `SlotLabProjectProvider.symbols` exists but Symbols panel uses hardcoded list

---

### 4.4 Role: Technical Director

#### 4.4.1 Technical Debt Assessment

| Category | Debt Level | Description |
|----------|------------|-------------|
| **Hardcoded Data** | 🔴 HIGH | 12 elements use static data |
| **Dead Code Paths** | 🟡 MEDIUM | 23 elements have no functionality |
| **Provider Misuse** | 🔴 HIGH | 3 major providers not integrated |
| **State Sync** | 🟡 MEDIUM | Local state doesn't sync with global |

#### 4.4.2 Architecture Violations

1. **Single Source of Truth Violation:**
   - Symbols list hardcoded vs `SlotLabProjectProvider.symbols`
   - Pan values hardcoded vs `MixerDSPProvider` state

2. **Provider Bypass:**
   - `_buildCompactDspChain()` ignores `DspChainProvider`
   - `_buildCompactStemsPanel()` ignores `MixerDSPProvider.buses`

3. **Callback Hell:**
   - Multiple `onTap: () {}` empty handlers indicate incomplete implementation

---

## PART 5: CRITICAL ISSUES RANKED

### 🔴 P0 — CRITICAL (Must Fix)

| # | Issue | Location | Impact |
|---|-------|----------|--------|
| 1 | DSP Chain shows fake data | `_buildCompactDspChain()` | User sees wrong processor states |
| 2 | Per-bus voice stats are fake | `_buildCompactVoicePool()` | Wrong mixing decisions |
| 3 | Pan panel completely static | `_buildCompactPanPanel()` | Can't adjust spatial |
| 4 | Stems panel non-functional | `_buildCompactStemsPanel()` | Export broken |
| 5 | Event play buttons don't work | Folder + Editor panels | Can't preview audio |

### 🟠 P1 — HIGH (Should Fix)

| # | Issue | Location | Impact |
|---|-------|----------|--------|
| 6 | Layer parameters not editable | `_buildCompactCompositeEditor()` | Can't adjust timing/volume |
| 7 | Symbols list hardcoded | `_buildCompactSymbolsPanel()` | Doesn't reflect project |
| 8 | Action Strip mostly dead | `_buildActionStrip()` | 9/17 actions do nothing |
| 9 | Variations panel static | `_buildCompactVariationsPanel()` | Can't generate variations |
| 10 | Package panel non-functional | `_buildCompactPackagePanel()` | Can't build packages |

### 🟡 P2 — MEDIUM (Nice to Have)

| # | Issue | Location | Impact |
|---|-------|----------|--------|
| 11 | Drag-drop not working | Layer items | Workflow friction |
| 12 | Symbol cards not clickable | Symbols panel | Can't assign audio directly |
| 13 | Stage play buttons missing | Timeline panel | Can't preview individual stages |
| 14 | Editor/Folder selection desync | Event panels | Confusing state |
| 15 | Keyboard shortcuts not visible | Context bar | Discoverability |

---

## PART 6: RECOMMENDED FIXES

### 6.1 P0 Fixes (Critical)

#### Fix #1: DSP Chain — Connect to DspChainProvider
```dart
Widget _buildCompactDspChain() {
  return Consumer<DspChainProvider>(
    builder: (context, dspChain, _) {
      final chain = dspChain.getChain(0); // Master bus
      if (chain.isEmpty) {
        return _buildEmptyChain();
      }
      return _buildChainFromNodes(chain);
    },
  );
}
```

#### Fix #2: Voice Pool — Get Real Per-Bus Stats
```dart
// Requires FFI addition:
// int getVoiceCountForBus(int busId)
final busStats = <String, (int, int)>{
  'SFX': (ffi.getVoiceCountForBus(0), 16),
  'Music': (ffi.getVoiceCountForBus(1), 8),
  // ...
};
```

#### Fix #3: Pan Panel — Connect to MixerDSPProvider
```dart
Widget _buildCompactPanPanel() {
  return Consumer<MixerDSPProvider>(
    builder: (context, mixer, _) {
      return Row(
        children: mixer.buses.map((bus) =>
          _buildInteractivePanChannel(bus.name, bus.pan, (newPan) {
            mixer.setBusPan(bus.id, newPan);
          })
        ).toList(),
      );
    },
  );
}
```

#### Fix #4: Stems Panel — Connect and Make Functional
```dart
Widget _buildCompactStemsPanel() {
  return Consumer<MixerDSPProvider>(
    builder: (context, mixer, _) {
      return StatefulBuilder(
        builder: (context, setState) {
          return ListView(
            children: mixer.buses.map((bus) =>
              CheckboxListTile(
                value: _selectedBuses.contains(bus.id),
                onChanged: (v) => setState(() {
                  if (v!) _selectedBuses.add(bus.id);
                  else _selectedBuses.remove(bus.id);
                }),
                title: Text(bus.name),
              )
            ).toList(),
          );
        },
      );
    },
  );
}
```

#### Fix #5: Event Play Buttons — Add Preview Handler
```dart
GestureDetector(
  onTap: () {
    middleware.previewCompositeEvent(event.id);
  },
  child: Icon(Icons.play_arrow, size: 14),
)
```

### 6.2 P1 Fixes Summary

| Fix | Approach |
|-----|----------|
| Layer editing | Add inline text fields for delay/volume with debounced updates |
| Symbols from provider | Use `context.watch<SlotLabProjectProvider>().symbols` |
| Action Strip | Implement remaining handlers or remove dead buttons |
| Variations | Add sliders with state, connect to batch generator service |
| Package | Implement export workflow with progress dialog |

---

## PART 7: UI/UX RECOMMENDATIONS

### 7.1 Immediate Improvements

1. **Remove Non-Functional Elements:**
   - If play button doesn't work, don't show it
   - If drag handle doesn't work, don't show it
   - Prevents user frustration

2. **Add Visual Feedback:**
   - Disabled state for non-functional buttons
   - Loading indicators for async operations
   - Success/error toasts for actions

3. **Improve Discoverability:**
   - Add tooltip with keyboard shortcut to each tab
   - Add "?" button showing all shortcuts
   - Show shortcut in tab label: "Trace (Q)"

### 7.2 Workflow Improvements

1. **Event Workflow:**
   - Click event in Folder → Auto-select in Editor dropdown
   - Double-click layer → Open audio file picker
   - Right-click event → Context menu (rename, delete, duplicate)

2. **Symbol Workflow:**
   - Click symbol → Show audio assignment dialog
   - Drag audio onto symbol → Auto-create SYMBOL_LAND event
   - Color code: Green=mapped, Gray=unmapped, Orange=multiple

3. **Export Workflow:**
   - One-click "Export All" with progress
   - Presets for common configurations
   - Validation errors shown inline

### 7.3 Pro Audio UX Patterns

1. **Meter Standards:**
   - Follow K-System metering (K-14 for games)
   - Show peak hold with decay
   - Add clip indicators

2. **DSP Chain:**
   - Match DAW insert chain UX
   - Drag to reorder
   - Double-click to open processor
   - Bypass via icon click

3. **Voice Pool:**
   - Real-time voice activity visualization
   - Click voice to solo/locate
   - Show stealing events

---

## PART 8: CONCLUSIONS

### Overall Assessment

| Aspect | Score | Notes |
|--------|-------|-------|
| **Functionality** | 47% | Less than half of elements work |
| **UI Polish** | 65% | Visually consistent but many dead ends |
| **Architecture** | 55% | Good structure but poor provider integration |
| **Workflow** | 40% | Many broken paths |
| **Production Ready** | ❌ NO | Too many critical issues |

### Key Findings

1. **Good Foundation:** Tab structure, keyboard navigation, and provider architecture are solid
2. **Implementation Gap:** Many panels are "UI shells" without backend connection
3. **Hardcoding Problem:** 12 elements use static data instead of real state
4. **Dead Code:** 23 UI elements have no functionality

### Recommended Priority

1. **Week 1:** Fix P0 issues (5 critical)
2. **Week 2:** Fix P1 issues (5 high)
3. **Week 3:** UX polish and P2 issues
4. **Week 4:** Testing and refinement

### Final Verdict

SlotLab Lower Zone has excellent visual design and logical organization. After P0 fixes (2026-01-24), **~65% of the UI is now functional** (up from 47%).

**Remaining work:** SL-P1 (6 items) and SL-P2 (10 items) for full completion.

**Update (2026-01-24):** P0.1-P0.5 fixes connected DspChainProvider, MixerDSPProvider, and critical playback buttons.

---

---

## PART 9: TODO AUDIT

### 9.0 P0 FIXES APPLIED (2026-01-24)

| # | Issue | File | Status |
|---|-------|------|--------|
| P0.1 | DSP Chain hardcoded | `slotlab_lower_zone_widget.dart` | ✅ FIXED — Now reads from DspChainProvider |
| P0.2 | Voice Pool fake ratios | `slotlab_lower_zone_widget.dart` | ✅ FIXED — Now uses NativeFFI.getVoicePoolStats() |
| P0.3 | Pan panel static | `slotlab_lower_zone_widget.dart` | ✅ FIXED — Connected to MixerDSPProvider |
| P0.4 | Stems checkboxes non-functional | `slotlab_lower_zone_widget.dart` | ✅ FIXED — Added _selectedStemBusIds state |
| P0.5 | Event play button empty | `slotlab_lower_zone_widget.dart:1269` | ✅ FIXED — Calls middleware.previewCompositeEvent() |

**Connection rate improved: 47% → 65%** (estimated after P0 fixes)

### 9.1 TODO Comments Found in Codebase

**Total: 18 TODO comments across SlotLab Lower Zone and related files**

#### SlotLab Lower Zone Widget (2)

| Line | TODO | Priority | Status |
|------|------|----------|--------|
| **1269** | `// TODO: Connect to preview playback` | 🔴 P0 | Event play button does nothing |
| **2192** | `// TODO: Show export dialog` | 🟠 P1 | Stage export only debugPrints |

#### FabFilter Panels (5)

| File | Line | TODO | Priority |
|------|------|------|----------|
| `fabfilter_limiter_panel.dart` | 241 | `// TODO: Add insert_get_limiter_gr() and insert_get_limiter_true_peak() FFI` | 🟠 P1 |
| `fabfilter_limiter_panel.dart` | 258 | `// TODO: Connect to PLAYBACK_ENGINE loudness metering` | 🟠 P1 |
| `fabfilter_compressor_panel.dart` | 454 | `// TODO: Connect to DSP chain bypass when insert chain is implemented` | 🟠 P1 |
| `fabfilter_compressor_panel.dart` | 462 | `// TODO: Add insert_get_compressor_gr() FFI function for real-time GR metering` | 🟠 P1 |
| `fabfilter_compressor_panel.dart` | 466 | `// TODO: Connect to real metering via track meter FFI` | 🟠 P1 |

#### Event Log Panel (1)

| Line | TODO | Priority |
|------|------|----------|
| **267** | `// TODO: Add event history tracking to MiddlewareProvider if needed` | 🟡 P2 |

#### DAW Lower Zone Widget (6)

| Line | TODO | Priority |
|------|------|----------|
| **607** | `volume: 1.0, // TODO: Get from selected track` | 🟡 P2 |
| **1094** | `// TODO: Insert into track slot` | 🟠 P1 |
| **1662** | `bpm: 120.0, // TODO: Get from TimelinePlaybackProvider` | 🟡 P2 |
| **1691** | `fadeIn: 0.0, // TODO: Add fadeIn to TimelineClipData` | 🟡 P2 |
| **1692** | `fadeOut: 0.0, // TODO: Add fadeOut to TimelineClipData` | 🟡 P2 |
| **2843** | `// TODO: Apply pan law to MixerProvider when FFI is ready` | 🟠 P1 |

#### Middleware Widgets (3)

| File | Line | TODO | Priority |
|------|------|------|----------|
| `music_transition_preview_panel.dart` | 689 | `// TODO: Save transition profile to ALE provider` | 🟡 P2 |
| `blend_container_panel.dart` | 469 | `// TODO: Preview blend at current RTPC value` | 🟡 P2 |
| `events_folder_panel.dart` | 1171 | `// TODO: Integrate with PreviewEngine` | 🟡 P2 |

#### Export Panels (1)

| Line | TODO | Priority |
|------|------|----------|
| **98** | `// TODO: Pass actual audio buffer from project` | 🟡 P2 |

### 9.2 TODO Summary

| Priority | Count | % |
|----------|-------|---|
| 🔴 P0 Critical | 1 | 6% |
| 🟠 P1 High | 7 | 39% |
| 🟡 P2 Medium | 10 | 55% |
| **Total** | **18** | 100% |

### 9.3 Critical TODO: Event Preview (Line 1269)

**Current Code:**
```dart
GestureDetector(
  onTap: () {
    // Trigger preview playback
    // TODO: Connect to preview playback
  },
  child: Icon(Icons.play_arrow, size: 14),
)
```

**Fixed Code:**
```dart
GestureDetector(
  onTap: () {
    final middleware = context.read<MiddlewareProvider>();
    middleware.previewCompositeEvent(event.id);
  },
  child: Icon(Icons.play_arrow, size: 14),
)
```

**Impact:** This single line fix enables audio preview in the Event Folder panel.

### 9.4 FFI Gaps (FabFilter Panels)

Missing Rust FFI functions needed for real-time metering:

| Function | Purpose | Panel |
|----------|---------|-------|
| `insert_get_limiter_gr()` | Gain reduction value | Limiter |
| `insert_get_limiter_true_peak()` | True peak level | Limiter |
| `insert_get_compressor_gr()` | Gain reduction value | Compressor |

**Estimated work:** 2-3 hours Rust + 1 hour Dart bindings

---

## APPENDIX: FILE REFERENCES

### Primary Files

| File | LOC | Purpose |
|------|-----|---------|
| `slotlab_lower_zone_widget.dart` | ~2350 | Main widget with all panel implementations |
| `slotlab_lower_zone_controller.dart` | ~242 | State management, keyboard shortcuts |
| `lower_zone_types.dart` | ~1216 | Enums, state classes, shared widgets |

### External Widgets Used

| Widget | File | Used In |
|--------|------|---------|
| `StageTraceWidget` | `widgets/slot_lab/stage_trace_widget.dart` | STAGES→Trace |
| `ProfilerPanel` | `widgets/profiler/profiler_panel.dart` | STAGES→Timing |
| `EventLogPanel` | `widgets/slot_lab/event_log_panel.dart` | EVENTS→Layers |
| `BusHierarchyPanel` | `widgets/middleware/bus_hierarchy_panel.dart` | MIX→Buses |
| `AuxSendsPanel` | `widgets/middleware/aux_sends_panel.dart` | MIX→Sends |
| `RealTimeBusMeters` | `widgets/metering/real_time_bus_meters.dart` | MIX→Meter |
| `FabFilterEqPanel` | `widgets/fabfilter/fabfilter_eq_panel.dart` | DSP→EQ |
| `FabFilterCompressorPanel` | `widgets/fabfilter/fabfilter_compressor_panel.dart` | DSP→Comp |
| `FabFilterReverbPanel` | `widgets/fabfilter/fabfilter_reverb_panel.dart` | DSP→Reverb |
| `SlotLabBatchExportPanel` | `widgets/lower_zone/export_panels.dart` | BAKE→Export |

### Providers Referenced (Updated 2026-01-24)

| Provider | Used For | Connected? |
|----------|----------|------------|
| `SlotLabProvider` | Stages, playback state | ✅ Yes |
| `MiddlewareProvider` | Events, containers, stats | ✅ Yes |
| `DspChainProvider` | DSP chain state | ✅ Yes (P0.1 fix) |
| `MixerDSPProvider` | Bus volumes, panning | ✅ Yes (P0.3 fix) |
| `SlotLabProjectProvider` | Symbols, contexts | ❌ NO — should power Symbols panel (SL-P1.2) |

---

*Analysis completed: 2026-01-24*
*Updated: 2026-01-24 (P0.1-P0.5, P1.2, P1.3 fixes applied)*
*Roles: Chief Audio Architect, UI/UX Expert, Engine Architect, Technical Director*
*Document: SLOTLAB_LOWER_ZONE_ULTRA_ANALYSIS_2026_01_24.md*
