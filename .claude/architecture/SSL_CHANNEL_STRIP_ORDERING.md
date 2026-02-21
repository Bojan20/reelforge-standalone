# SSL Channel Strip — Signal Flow Architecture

**Created:** 2026-02-21
**Status:** ✅ IMPLEMENTED (2026-02-21)
**File:** `flutter_ui/lib/widgets/layout/channel_inspector_panel.dart` (~2256 LOC)

---

## 1. SSL Console Analysis

### 1.1 SSL 4000E (1979) — The Original

**Physical Layout (Top to Bottom):**
```
┌─────────────────────┐
│  INPUT SELECT       │  ← Mic/Line, Pad, Phase, 48V
│  (top of strip)     │
├─────────────────────┤
│  DYNAMICS           │  ← Comp + Gate (pre-EQ default)
│  (above EQ)         │
├─────────────────────┤
│  EQ                 │  ← 4-band parametric, bypass
│  (center of strip)  │
├─────────────────────┤
│  AUX SENDS          │  ← 8 sends (4 pre, 4 post)
│                     │
├─────────────────────┤
│  SMALL FADER        │  ← Mix/Multitrack routing
│  (to tape/mix bus)  │
├─────────────────────┤
│  PAN                │  ← Post-fader
├─────────────────────┤
│  MUTE / SOLO        │
├─────────────────────┤
│  LARGE FADER        │  ← 100mm VCA fader
│  (main fader)       │
└─────────────────────┘
```

**Default Signal Flow:**
```
Input → Dynamics → EQ → Fader → Pan → Mix Bus
```

### 1.2 SSL 4000G (1987) — The Standard

**Signal Flow (Default):**
```
Input → HPF/LPF → Dynamics (pre-EQ) → EQ → Insert Point → VCA Fader → Pan → Sends → Mix Bus
```

**Key Addition:** Insert point between EQ and Fader. HPF/LPF filters added separately from parametric EQ.

**Switchable:** DYN→EQ or EQ→DYN button on each channel.

### 1.3 SSL 9000J (1995) — The Pinnacle

**Physical Layout:**
```
┌─────────────────────┐
│  INPUT              │  ← Mic/Line, Pad, Phase, 48V
├─────────────────────┤
│  FILTERS            │  ← HPF/LPF + Filter Shape
├─────────────────────┤
│  DYNAMICS           │  ← Comp/Limiter + Gate/Expander
│                     │     (switchable pre/post EQ)
├─────────────────────┤
│  EQ                 │  ← 4-band fully parametric
│                     │     (variable Q on all bands)
├─────────────────────┤
│  INSERT POINTS      │  ← A/B insert switching
├─────────────────────┤
│  AUX SENDS          │  ← 12 sends (pre/post selectable)
├─────────────────────┤
│  PAN                │  ← Dual (L/R for stereo)
├─────────────────────┤
│  ROUTING            │  ← Direct Out + Mix Bus
├─────────────────────┤
│  FADER              │  ← 100mm VCA
└─────────────────────┘
```

**Signal Flow:**
```
Input → Filters → Dynamics → EQ → Insert A/B → Fader → Pan → Sends → Direct Out / Mix Bus
```

### 1.4 SSL Duality (2007) — The Hybrid

**6 Insert Configurations:**
```
Config 1: Input → Dyn → EQ → Insert → Fader
Config 2: Input → EQ → Dyn → Insert → Fader
Config 3: Input → Insert → Dyn → EQ → Fader
Config 4: Input → Dyn → Insert → EQ → Fader
Config 5: Input → EQ → Insert → Dyn → Fader
Config 6: Input → Insert → EQ → Dyn → Fader
```

**Key Innovation:** Complete flexibility in insert point positioning relative to dynamics and EQ.

---

## 2. Cross-Console Comparison

| Feature | 4000E | 4000G | 9000J | Duality |
|---------|-------|-------|-------|---------|
| Input at top | ✅ | ✅ | ✅ | ✅ |
| Filters separate | ❌ | ✅ | ✅ | ✅ |
| Dynamics pre-EQ | Default | Switchable | Switchable | 6 configs |
| Insert points | ❌ | 1 | 2 (A/B) | 6 positions |
| Sends pre/post | 4/4 | Switchable | Per-send | Per-send |
| Fader at bottom | ✅ | ✅ | ✅ | ✅ |
| Pan post-fader | ✅ | ✅ | ✅ | ✅ |
| Routing at bottom | ✅ | ✅ | ✅ | ✅ |

### Universal Constants (ALL SSL consoles):

1. **INPUT is ALWAYS at the top** — first thing in signal chain
2. **FADER is ALWAYS near the bottom** — main level control
3. **PAN is ALWAYS post-fader** — affects stereo placement after level
4. **SENDS are post-EQ** — processed signal to aux buses
5. **ROUTING/OUTPUT is at the bottom** — last thing before mix bus
6. **Inserts are BETWEEN input processing and fader** — pre-fader effects

---

## 3. Current ChannelInspectorPanel Layout (WRONG)

**File:** `channel_inspector_panel.dart`, `build()` method (lines 89-162)

```dart
// Current order — BREAKS SSL signal flow:
Column(children: [
  _buildChannelHeader(),        // 1. Header ← OK
  _buildChannelControls(),      // 2. FADER + Pan + M/S/R/I/Ø ← WRONG POSITION
  _buildInsertsSection(),       // 3. Pre+Post inserts together ← WRONG: below fader
  _buildSendsSection(),         // 4. Sends ← OK
  _buildRoutingSection(),       // 5. Input+Output together ← WRONG: Input should be at top
  // divider
  _buildClipSection(),          // 6. Clip ← OK
  _buildClipGainSection(),      // 7. Clip Gain ← OK
  _buildClipTimeStretchSection(), // 8. Time Stretch ← OK
])
```

### Problems Identified:

| # | Problem | SSL Standard | Current |
|---|---------|-------------|---------|
| 1 | **Fader too early** | Near bottom, after inserts | Position 2 (above inserts) |
| 2 | **Inserts below fader** | Pre-fader inserts ABOVE fader | Position 3 (all below fader) |
| 3 | **Input at bottom** | Always at TOP | Grouped with Output in position 5 |
| 4 | **Pre/Post inserts not split** | Clear physical separation | Grouped in one section |
| 5 | **No dedicated Input section** | Separate with Gain/Pad/48V/Ø | Scattered across sections |

---

## 4. New Layout (SSL-Based, 10 Sections)

```dart
Column(children: [
  // ═══ CHANNEL STRIP SECTION ═══
  _buildChannelHeader(),          // 1. Name, type, color, peak meter
  _buildInputSection(),           // 2. Input source + Gain + Pad + 48V + Phase (Ø)
  _buildPreFaderInserts(),        // 3. Pre-fader DSP slots
  _buildFaderPanSection(),        // 4. Volume fader + Pan + M/S/R/I buttons
  _buildPostFaderInserts(),       // 5. Post-fader DSP slots
  _buildSendsSection(),           // 6. Aux sends (pre/post toggle per send)
  _buildOutputRoutingSection(),   // 7. Output bus assignment ONLY

  // ═══ CLIP INSPECTOR SECTION ═══
  if (widget.selectedClip != null) ...[
    Divider(),
    _buildClipSection(),            // 8. Position, Duration, Source
    _buildClipGainSection(),        // 9. Non-destructive clip gain
    _buildClipTimeStretchSection(), // 10. Elastic Pro Time Stretch
  ],
])
```

### Signal Flow Diagram (New):

```
                    ┌─────────────────────────┐
                    │  1. CHANNEL HEADER       │
                    │     Name, Type, Color    │
                    ├─────────────────────────┤
                    │  2. INPUT               │  ← Source selector
INPUT ──────────────│     Gain Trim ± 20dB    │     Pad, 48V, Phase Ø
                    │     Input Monitor (I)    │
                    ├─────────────────────────┤
                    │  3. INSERTS (PRE-FADER) │  ← Dynamics, EQ, etc.
                    │     Slot 0..N           │     (before fader)
                    ├─────────────────────────┤
                    │  4. FADER + PAN         │  ← Main level control
FADER ──────────────│     Volume Fader        │     Unity @ 75% (Cubase law)
                    │     Pan Knob(s)         │     M/S/R/I buttons
                    ├─────────────────────────┤
                    │  5. INSERTS (POST-FADER)│  ← Post-fader effects
                    │     Slot 0..N           │     (after fader)
                    ├─────────────────────────┤
                    │  6. SENDS               │  ← Aux sends
SENDS ──────────────│     Send 1..N           │     Level + Pre/Post toggle
                    │     Destination + Mute  │
                    ├─────────────────────────┤
                    │  7. OUTPUT ROUTING      │  ← Bus assignment
OUTPUT ─────────────│     Output Bus          │     (Master/Bus 1-6)
                    │     Direct Out          │
                    └─────────────────────────┘
```

---

## 5. Implementation Plan

### Step 1: Extract Input Section (~50 LOC new)

**From `_buildRoutingSection()` extract:**
- Input source selector dropdown
- Move to new `_buildInputSection()`

**From `_buildChannelControls()` extract:**
- Input Gain trim slider
- Phase Invert (Ø) button
- Input Monitor (I) button

**New `_buildInputSection()` contents:**
```
┌────────────────────────────────────┐
│ INPUT                          ▼  │
├────────────────────────────────────┤
│ Source: [Analog 1 ▼]              │
│ Gain:  ──────●────── +3.5 dB     │
│ [48V] [Pad] [Ø] [I]              │
└────────────────────────────────────┘
```

### Step 2: Split Inserts Section

**Current `_buildInsertsSection()` (lines 499-555):**
- Already has `_preFaderInserts` and `_postFaderInserts` lists
- Just needs to be split into TWO separate builder methods

**`_buildPreFaderInserts():`**
```
┌────────────────────────────────────┐
│ INSERTS (PRE-FADER)           [+] │
├────────────────────────────────────┤
│ [1] FF-Q 64      [B] [E]         │
│ [2] FF-C         [B] [E]         │
│ [3] (empty)                       │
└────────────────────────────────────┘
```

**`_buildPostFaderInserts():`**
```
┌────────────────────────────────────┐
│ INSERTS (POST-FADER)          [+] │
├────────────────────────────────────┤
│ [1] FF-L         [B] [E]         │
│ [2] (empty)                       │
└────────────────────────────────────┘
```

### Step 3: Relocate Fader + Pan

Move `_buildFaderPanSection()` from position 2 to position 4 (between pre and post inserts).

**Contents (from current `_buildChannelControls()` minus Input items):**
```
┌────────────────────────────────────┐
│ FADER                              │
├────────────────────────────────────┤
│        │                           │
│   -6   │ ══════════════ │ 0 dB    │
│        │                           │
│ Pan: ──────●────── C              │
│ [M] [S] [R]                       │
└────────────────────────────────────┘
```

### Step 4: Output-Only Routing

Rename and simplify `_buildRoutingSection()` to `_buildOutputRoutingSection()`.
Remove input selector (moved to Step 1).

```
┌────────────────────────────────────┐
│ OUTPUT                             │
├────────────────────────────────────┤
│ Bus: [Master ▼]                   │
│ Direct Out: [Off ▼]              │
└────────────────────────────────────┘
```

---

## 6. Method Refactoring Summary

| Current Method | Action | New Method(s) |
|----------------|--------|---------------|
| `_buildChannelControls()` | **SPLIT** | `_buildInputSection()` (Gain/Pad/48V/Ø/I) + `_buildFaderPanSection()` (Volume/Pan/M/S/R) |
| `_buildInsertsSection()` | **SPLIT** | `_buildPreFaderInserts()` + `_buildPostFaderInserts()` |
| `_buildRoutingSection()` | **SPLIT** | Input part → `_buildInputSection()`, Output part → `_buildOutputRoutingSection()` |
| `_buildSendsSection()` | **KEEP** | No changes |
| `_buildClipSection()` | **KEEP** | No changes |
| `_buildClipGainSection()` | **KEEP** | No changes |
| `_buildClipTimeStretchSection()` | **REWRITTEN** | Now uses ElasticPro track-based API (mode, formant, transient controls) |

**Net change:** 3 methods split into 6 → total 10 builder methods (from 8)

---

## 7. Competitive DAW Channel Strip Comparison

| DAW | Signal Flow Order | Notes |
|-----|-------------------|-------|
| **Pro Tools** | Input → Insert A-E → Fader → Insert F-J → Sends → Output | Explicit pre/post split |
| **Cubase** | Input → Strip (EQ/Comp/Gate) → Insert (Pre) → Fader → Insert (Post) → Sends → Output | Channel Strip module |
| **Logic Pro** | Input → Insert → Fader → Send → Output | Simpler model |
| **Studio One** | Input → Insert → Fader → Post-Fader → Send → Output | Dedicated post section |
| **Reaper** | Input → FX Chain → Fader → Post-FX → Send → Output | Fully flexible |
| **SSL 9000J** | Input → Filters → Dynamics → EQ → Insert → Fader → Pan → Sends → Output | The gold standard |

**FluxForge (Proposed):** Input → Insert (Pre) → Fader → Insert (Post) → Sends → Output

This matches Pro Tools (A-E pre, F-J post) and SSL Duality (configurable insert points).

---

## 8. Data Model Impact

**No model changes required.** All data already exists in `ChannelStripData` (`layout_models.dart`):

| Field | Used In Section |
|-------|----------------|
| `inputSource` | Input (new) |
| `inputGain` | Input (new) |
| `phaseInverted` | Input (moved from Channel Controls) |
| `inputMonitor` | Input (moved from Channel Controls) |
| `volume` | Fader + Pan |
| `pan`, `panRight`, `isStereo` | Fader + Pan |
| `muted`, `soloed`, `recordArmed` | Fader + Pan |
| `inserts` (List\<InsertSlot\>) | Pre-Fader Inserts + Post-Fader Inserts |
| `sends` (List\<SendSlot\>) | Sends |
| `outputBus` | Output Routing |

**InsertSlot already has `isPreFader` field** — the data model already supports the split.

---

## 9. Estimated Effort

| Task | LOC Change | Effort |
|------|-----------|--------|
| Extract `_buildInputSection()` | +60, -20 from controls/routing | Low |
| Split `_buildPreFaderInserts()` / `_buildPostFaderInserts()` | +30, -10 | Low |
| Relocate `_buildFaderPanSection()` | ~0 (just reorder in build()) | Trivial |
| Rename `_buildOutputRoutingSection()` | +5, -5 | Trivial |
| Update `build()` method order | ~10 lines | Trivial |
| **Total** | ~+100, -35 = +65 net | **~1-2 hours** |

---

## References

- [SSL 4000 Series History](https://www.solidstatelogic.com/about/history)
- [SSL 9000 J Manual — Signal Flow](https://www.solidstatelogic.com/studio/9000j)
- [SSL Duality — 6 Insert Configurations](https://www.solidstatelogic.com/studio/duality)
- [Pro Tools Reference — Channel Strip Signal Flow](https://resources.avid.com/)
- [Cubase Pro — MixConsole Channel Settings](https://steinberg.help/)
