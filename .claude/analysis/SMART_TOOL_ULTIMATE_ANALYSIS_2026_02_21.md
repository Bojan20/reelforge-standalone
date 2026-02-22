# Smart Tool Ultimate Analysis — Cubase + Pro Tools + Logic Pro X
## Combined Best-of-All for FluxForge Studio

**Date:** 2026-02-21 (Updated 2026-02-22)
**Purpose:** Extract the best smart tool features from all 3 industry leaders, design FluxForge's ultimate smart tool

**Implementation Status (2026-02-22):**
- ✅ 10 tools + 5 edit modes — `SmartToolProvider` + `TimelineEditToolbar`
- ✅ Keyboard shortcuts: 1-0 (tools), F1-F5 (edit modes) — `main_layout.dart`
- ✅ Commands Focus Mode: E/T/F/Z — `main.dart` → `SmartToolProvider`
- ✅ Duplicate UI removed from control_bar.dart (`_SmartToolButton` + `_ProEditModes`)
- ✅ Single SmartToolProvider instance (no more `EditModeProProvider` conflicts)

---

## 1. COMPARISON TABLE — Zone Systems

### 1.1 Pro Tools Smart Tool (6-Zone System)

```
┌──────────────────────────────────────┐
│  ◢ FADE IN              FADE OUT ◣   │  ← Top corners (fade handles)
│                                      │
│         SELECTOR (I-beam)            │  ← Upper half (time selection)
│                                      │
├──────────────────────────────────────┤  ← Midpoint divider
│                                      │
│          GRABBER (hand)              │  ← Lower half (move clip)
│                                      │
│ ◣ TRIM ◢                    ◢ TRIM ◣ │  ← Bottom edges (trim handles)
└──────────────────────────────────────┘
        ↕ CROSSFADE (between clips)       ← Bottom zone at clip boundaries
```

**Zones (6):**
| Zone | Location | Cursor | Action |
|------|----------|--------|--------|
| Selector | Upper 50% | I-beam | Time/range selection |
| Grabber | Lower 50% | Hand | Move clip |
| Trim L | Left edge (bottom) | ←\| | Trim start |
| Trim R | Right edge (bottom) | \|→ | Trim end |
| Fade In | Top-left corner | Curve | Adjust fade in |
| Fade Out | Top-right corner | Curve | Adjust fade out |
| Crossfade | Between clips (bottom) | X | Create/edit crossfade |

**Edit Modes (4):**
| Mode | Behavior | Key |
|------|----------|-----|
| Shuffle | Ripple — move pushes all right, delete closes gap | F1 |
| Slip | Free — no constraints, overlap allowed | F2 |
| Spot | Dialog — popup asks timecode position | F3 |
| Grid | Snap — absolute or relative to grid | F4 |

**Sub-Modes:**
- Trimmer: Standard / TCE (time-compress/expand) / Loop / Scrub
- Grabber: Time / Separation (auto-splits at selection) / Object (non-contiguous multi-select)

**Key Shortcuts:**
- Tab = Jump to next transient
- Opt+Tab = Jump to next transient backwards
- B = Separate clip at selection
- Ctrl+click in selector zone = Scrub

---

### 1.2 Cubase Combined Selection Tools

```
┌──────────────────────────────────────┐
│ ◢ FADE IN    ● VOLUME    FADE OUT ◣  │  ← Top: fades at corners, volume at center
│                                      │
│        RANGE SELECTION               │  ← Upper half (range/time selection)
│                                      │
├──────────────────────────────────────┤
│                                      │
│        OBJECT SELECTION              │  ← Lower half (object select/move)
│                                      │
│ ◣ RESIZE ◢                  ◢ RESIZE ◣│  ← Bottom corners (resize)
└──────────────────────────────────────┘
```

**Zones (7):**
| Zone | Location | Cursor | Action |
|------|----------|--------|--------|
| Range Select | Upper 50% | Crosshair | Range/time selection |
| Object Select | Lower 50% | Arrow | Select/move clip |
| Resize L | Bottom-left corner | ←\| | Resize from left |
| Resize R | Bottom-right corner | \|→ | Resize from right |
| Fade In | Top-left corner | Curve | Adjust fade in length |
| Fade Out | Top-right corner | Curve | Adjust fade out length |
| Volume | Top-center edge | ↕ | Adjust clip volume |

**Sizing Sub-Modes (3) — UNIQUE to Cubase:**
| Mode | Behavior |
|------|----------|
| Normal Sizing | Resize trims audio (reveals/hides content) |
| Sizing Moves Contents | Resize moves audio start point within clip |
| Sizing Applies Time Stretch | Resize time-stretches the audio |

**Snap Types (8):**
| Type | Behavior |
|------|----------|
| Grid | Snap to nearest grid line |
| Grid Relative | Maintain relative offset while snapping |
| Events | Snap to other clip edges |
| Shuffle | Swap position with adjacent events |
| Magnetic Cursor | Snap to playhead position |
| Grid + Events | Both simultaneously |
| Grid + Cursor | Both simultaneously |
| Grid + Events + Cursor | All three simultaneously |

**Modifier Keys:**
| Key | Action |
|-----|--------|
| Alt + drag | Copy clip (object mode) |
| Alt + click | Split at cursor position (object mode) |
| Alt + Shift + drag | Slip content (move audio within clip boundaries) |
| Shift + drag | Constrain to horizontal |
| Ctrl + drag | Fine adjustment (bypass snap) |

---

### 1.3 Logic Pro X Pointer Tool

```
┌──────────────────────────────────────┐
│ ◢ FADE IN                 FADE OUT ◣ │  ← Upper corners (fade handles)
│                                      │
│            MOVE                      │  ← Upper body (move region)
│                                      │
├──────────────────────────────────────┤
│                                      │
│          MARQUEE SELECT              │  ← Lower body (marquee selection)
│                                      │
│ ◣ TRIM ◢         ● LOOP     ◢ TRIM ◣│  ← Bottom: trim at edges, loop at mid-right
└──────────────────────────────────────┘
     ↕ JUNCTION RESIZE                    ← Between adjacent regions
```

**Zones (7):**
| Zone | Location | Cursor | Action |
|------|----------|--------|--------|
| Move | Upper 60% body | Arrow | Move region |
| Marquee | Lower 40% body | Crosshair | Sub-region selection (when click zones enabled) |
| Trim L | Lower-left edge | ←\| | Trim start |
| Trim R | Lower-right edge | \|→ | Trim end |
| Fade In | Upper-left corner | Curve | Adjust fade in |
| Fade Out | Upper-right corner | Curve | Adjust fade out |
| Loop | Mid-right edge | Loop icon | Toggle/adjust loop region |
| Junction | Between adjacent regions | ↔ | Resize boundary between two regions |

**Drag Modes (5):**
| Mode | Behavior |
|------|----------|
| Overlap | Default — clip can overlap others |
| No Overlap | Pushing — clip pushes adjacent right |
| X-Fade | Auto-crossfade — overlap creates automatic crossfade |
| Shuffle R | Ripple right — insert pushes all right clips |
| Shuffle L | Ripple left — insert pushes all left clips |

**Snap Modes:**
| Mode | Behavior |
|------|----------|
| Smart | Adaptive to zoom level (bar at far zoom, tick at close zoom) |
| Bar | Snap to bar boundaries |
| Beat | Snap to beat boundaries |
| Division | Snap to beat subdivisions |
| Ticks | Finest resolution |
| Frames | SMPTE frame boundaries |
| Quarter Frames | Sub-frame resolution |
| Samples | Sample-level precision |
| Absolute | Snap to exact grid positions |
| Relative | Maintain offset from grid |

**Dual Tool System:**
- Primary tool (left-click) — Usually Pointer
- Secondary tool (Cmd+click) — User-configurable (often Marquee or Scissors)
- T = cycle through tools

---

## 2. FEATURE EXTRACTION — Best of Each

### From Pro Tools (ADOPT):

| Feature | Why | Priority |
|---------|-----|----------|
| **6-zone hit detection** | Most intuitive zone layout, industry muscle memory | P0 |
| **Crossfade zone between clips** | Essential for editing workflow | P0 |
| **Tab to Transient** | Fast navigation, huge time saver | P1 |
| **Separation Grabber** | Auto-split at selection boundaries | P2 |
| **Scrub by Ctrl+click in selector** | Quick auditioning without tool change | P1 |
| **Shuffle mode = true ripple** | Delete closes gap, insert pushes — correct behavior | P0 |

### From Cubase (ADOPT):

| Feature | Why | Priority |
|---------|-----|----------|
| **Volume handle (top-center)** | Direct clip gain editing without opening inspector | P0 |
| **3 sizing sub-modes** | Normal/MovesContents/TimeStretch — massive flexibility | P1 |
| **Alt+click = Split** | No tool switch needed for splits | P0 |
| **Alt+Shift = Slip content** | Move audio within clip boundaries with modifier | P0 |
| **Grid Relative snap** | Maintains offset — essential for moved clips | P0 |
| **Magnetic Cursor snap** | Snap to playhead position | P1 |
| **Events snap** | Snap to other clip edges | P0 |

### From Logic Pro X (ADOPT):

| Feature | Why | Priority |
|---------|-----|----------|
| **Loop handle (mid-right edge)** | Toggle/create loop regions from clip directly | P1 |
| **Auto-Crossfade mode** | Overlap automatically creates crossfade | P1 |
| **Smart Snap (adaptive to zoom)** | Zoom level determines snap resolution automatically | P0 |
| **Junction resize** | Resize boundary between two adjacent clips | P1 |
| **Marquee sub-selection** | Select within a clip for partial operations | P2 |

### From All Three (UNIVERSAL PATTERNS):

| Pattern | All 3 DAWs | FluxForge Status |
|---------|------------|------------------|
| Fade handles at top corners | ✅ | ✅ Already implemented |
| Trim handles at edges | ✅ | ✅ Already implemented |
| Upper/lower zone split | ✅ | ✅ Already implemented |
| Modifier keys (Alt, Shift, Ctrl) | ✅ | ✅ Already implemented |
| Multiple edit modes | ✅ | ✅ Already implemented (4 modes) |
| Snap to grid | ✅ | ✅ Already implemented |

---

## 3. FLUXFORGE ULTIMATE SMART TOOL DESIGN

### 3.1 Zone Map — 9-Zone Hybrid

Combining Pro Tools' clarity, Cubase's volume handle, and Logic's loop handle:

```
┌──────────────────────────────────────────────────────┐
│ ◢ FADE IN        ● VOLUME HANDLE         FADE OUT ◣  │  ← Zone 1-3: Top row
│                                                      │     (20% height)
│                                                      │
│              RANGE SELECT / SCRUB                    │  ← Zone 4: Upper body
│              (I-beam cursor)                         │     (30% height)
│                                                      │
├──────────────────────────────────────────────────────┤  ← 50% midpoint
│                                                      │
│              MOVE / SELECT                           │  ← Zone 5: Lower body
│              (Arrow/Hand cursor)                     │     (30% height)
│                                                      │
│ ◣ TRIM L ◢              ● LOOP      ◢ TRIM R ◣      │  ← Zone 6-8: Bottom row
│                                                      │     (20% height)
└──────────────────────────────────────────────────────┘
                    ↕ CROSSFADE                           ← Zone 9: Between clips
```

**Zone Definitions:**

| # | Zone | Location | Width | Height | Cursor | Action |
|---|------|----------|-------|--------|--------|--------|
| 1 | Fade In | Top-left corner | 20% | 20% | `FadeIn` curve | Drag = adjust fade in duration |
| 2 | Volume | Top-center | 60% | 15% | `↕` vertical | Drag vertical = clip gain |
| 3 | Fade Out | Top-right corner | 20% | 20% | `FadeOut` curve | Drag = adjust fade out duration |
| 4 | Range Select | Upper body | 100% | 30% | `I-beam` | Click+drag = time/range selection |
| 5 | Move/Select | Lower body | 100% | 30% | `Arrow` | Click = select, drag = move |
| 6 | Trim Left | Bottom-left | 15% | 20% | `←\|` | Drag = trim start |
| 7 | Loop | Bottom-center-right | 15% | 20% | `↻` loop | Click = toggle loop, drag = set loop length |
| 8 | Trim Right | Bottom-right | 15% | 20% | `\|→` | Drag = trim end |
| 9 | Crossfade | Between adjacent clips | auto | 20% | `X` cross | Drag = crossfade duration/curve |

### 3.2 Zone Priority (Hit Testing Order)

```
HIGHEST PRIORITY (smallest, most specific):
  1. Fade In handle (top-left corner)
  2. Fade Out handle (top-right corner)
  3. Volume handle (top-center edge)
  4. Trim Left (bottom-left edge)
  5. Trim Right (bottom-right edge)
  6. Loop handle (bottom-center-right)
  7. Crossfade zone (between clips)
  8. Range Select (upper body)
  9. Move/Select (lower body)
LOWEST PRIORITY (largest, catch-all)
```

### 3.3 Modifier Keys — Combined Best

| Modifier | Context | Action | Source |
|----------|---------|--------|--------|
| **Alt + drag** (Move zone) | Move/Select | **Copy clip** | Cubase + Pro Tools |
| **Alt + click** (Move zone) | Move/Select | **Split at cursor** | Cubase |
| **Alt + Shift + drag** (Move zone) | Move/Select | **Slip content** (move audio within boundaries) | Cubase |
| **Shift + drag** (any) | Any drag | **Constrain to axis** (H or V dominant) | All 3 DAWs |
| **Ctrl/Cmd + drag** (any) | Any drag | **Fine mode** (bypass snap) | All 3 DAWs |
| **Ctrl + click** (Range zone) | Range Select | **Scrub audio** at cursor position | Pro Tools |
| **Shift + click** (Move zone) | Move/Select | **Extend selection** (add to selection) | All 3 DAWs |
| **Alt + drag** (Trim zone) | Trim | **Sizing Moves Contents** (Cubase sub-mode) | Cubase |
| **Alt + Shift + drag** (Trim zone) | Trim | **Time Stretch** (resize stretches audio) | Cubase |
| **Double-click** (Move zone) | Move/Select | **Open clip in editor** / Select all on track | Cubase |

### 3.4 Edit Modes — Enhanced 5-Mode System

Combining Pro Tools' 4 modes + Logic's auto-crossfade:

| Mode | Key | Behavior | Source |
|------|-----|----------|--------|
| **Shuffle** | F1 | True ripple: move pushes adjacent, delete closes gap | Pro Tools |
| **Slip** | F2 | Free movement, overlap allowed | Pro Tools |
| **Spot** | F3 | Timecode dialog popup for exact positioning | Pro Tools |
| **Grid** | F4 | Snap to grid (absolute or relative sub-mode) | Pro Tools + Cubase |
| **X-Fade** | F5 | Like Slip but overlap auto-creates crossfade | Logic Pro X |

**Grid Sub-Modes:**
| Sub-Mode | Behavior |
|----------|----------|
| Absolute | Clip snaps TO grid line |
| Relative | Clip maintains offset FROM grid (Grid Relative from Cubase) |

### 3.5 Snap System — Combined Best

**Snap Targets (cumulative, toggleable):**

| Target | Key | Behavior | Source |
|--------|-----|----------|--------|
| Grid | G | Snap to grid lines | All 3 |
| Events | E | Snap to other clip edges | Cubase |
| Cursor | C | Snap to playhead position | Cubase |
| Markers | M | Snap to markers/cue points | All 3 |
| Transients | T | Snap to detected transients | Pro Tools |

**Snap Resolution (adaptive — Logic's Smart Snap):**

| Zoom Level | Resolution |
|------------|------------|
| Very far (< 10 px/bar) | Bar |
| Far (10-30 px/bar) | Beat |
| Medium (30-100 px/bar) | Sub-beat |
| Close (100-300 px/bar) | Tick |
| Very close (> 300 px/bar) | Sample |

### 3.6 Trim Sub-Modes

| Sub-Mode | Modifier | Behavior | Source |
|----------|----------|----------|--------|
| Standard Trim | (none) | Reveals/hides audio content | All 3 |
| Content Move | Alt | Resize moves content start (Cubase: Sizing Moves Contents) | Cubase |
| Time Stretch | Alt+Shift | Resize time-stretches audio | Cubase |
| Loop Trim | Ctrl | Extends clip by looping content | Pro Tools |

### 3.7 Navigation — Tab to Transient

From Pro Tools, essential for editing:

| Key | Action |
|-----|--------|
| Tab | Jump playhead to next transient |
| Shift+Tab | Jump playhead to previous transient |
| Alt+Tab | Jump to next clip edge |
| Alt+Shift+Tab | Jump to previous clip edge |

**Transient Detection:**
- Use existing `rf-dsp` FFI for onset detection
- Cache transient positions per clip
- Visual markers (small triangles above waveform)

### 3.8 Crossfade System

When clips overlap (in Slip or X-Fade mode):

| Feature | Behavior |
|---------|----------|
| Default crossfade | Equal power curve, 50ms |
| Drag to resize | Adjust crossfade length |
| Double-click crossfade | Open Crossfade Editor dialog |
| Crossfade curve types | Linear, Equal Power, S-Curve, Exponential |
| Asymmetric crossfades | Independent fade-in and fade-out curves |

### 3.9 Volume Handle (Cubase Exclusive — ADOPT)

**Why:** Fastest way to adjust clip gain without opening inspector.

| Interaction | Behavior |
|-------------|----------|
| Hover top-center | Show dB value tooltip |
| Drag up/down | Adjust clip volume (0.1 dB steps) |
| Shift+drag | Fine mode (0.01 dB steps) |
| Double-click | Reset to 0 dB |
| Visual | Horizontal line across clip at gain level |

### 3.10 Loop Handle (Logic Exclusive — ADOPT)

**Why:** Quick loop creation without separate tool.

| Interaction | Behavior |
|-------------|----------|
| Hover mid-right edge | Show loop icon |
| Click | Toggle loop on/off |
| Drag right | Extend loop repetitions |
| Visual | Dashed vertical lines at loop boundaries |

---

## 4. IMPLEMENTATION PLAN

### Phase 1: Zone System Upgrade (P0)

**Current:** 4 zones (fade, trim, select, crossfade)
**Target:** 9 zones (add volume, loop, range/select split, crossfade between clips)

| Task | Description | LOC Est. |
|------|-------------|----------|
| 4.1.1 | Add Volume zone (top-center hit detection) | ~50 |
| 4.1.2 | Add Loop zone (bottom-center-right hit detection) | ~50 |
| 4.1.3 | Split body into Range Select (upper) / Move (lower) | ~80 |
| 4.1.4 | Crossfade zone between adjacent clips | ~100 |
| 4.1.5 | Update zone priority ordering | ~30 |
| 4.1.6 | Update cursor mapping for new zones | ~40 |

### Phase 2: Modifier Key Enhancements (P0)

| Task | Description | LOC Est. |
|------|-------------|----------|
| 4.2.1 | Alt+click = Split at cursor | ~40 |
| 4.2.2 | Alt+Shift+drag = Slip content | ~60 |
| 4.2.3 | Alt+drag in trim zone = Content Move | ~50 |
| 4.2.4 | Ctrl+click in range zone = Scrub | ~80 |

### Phase 3: Edit Mode Improvements (P0)

| Task | Description | LOC Est. |
|------|-------------|----------|
| 4.3.1 | Shuffle = true ripple (delete closes gap) | ~100 |
| 4.3.2 | Add X-Fade mode (auto-crossfade on overlap) | ~120 |
| 4.3.3 | Grid sub-modes: Absolute / Relative | ~60 |

### Phase 4: Snap System Upgrade (P0)

| Task | Description | LOC Est. |
|------|-------------|----------|
| 4.4.1 | Smart Snap (adaptive to zoom level) | ~80 |
| 4.4.2 | Events snap (to other clip edges) | ~60 |
| 4.4.3 | Cursor snap (to playhead) | ~30 |
| 4.4.4 | Transients snap target | ~100 |

### Phase 5: Volume & Loop Handles (P1)

| Task | Description | LOC Est. |
|------|-------------|----------|
| 4.5.1 | Volume handle drag + visual line | ~120 |
| 4.5.2 | Volume dB tooltip | ~40 |
| 4.5.3 | Loop handle click toggle + drag extend | ~100 |
| 4.5.4 | Loop visual indicators (dashed lines) | ~60 |

### Phase 6: Tab to Transient (P1)

| Task | Description | LOC Est. |
|------|-------------|----------|
| 4.6.1 | Transient detection FFI integration | ~80 |
| 4.6.2 | Tab/Shift+Tab keyboard handlers | ~60 |
| 4.6.3 | Transient visual markers | ~50 |

### Phase 7: Crossfade System (P1)

| Task | Description | LOC Est. |
|------|-------------|----------|
| 4.7.1 | Crossfade creation on overlap | ~100 |
| 4.7.2 | Crossfade editor dialog | ~200 |
| 4.7.3 | 4 crossfade curve types | ~80 |
| 4.7.4 | Visual crossfade rendering | ~80 |

### Phase 8: Trim Sub-Modes (P2)

| Task | Description | LOC Est. |
|------|-------------|----------|
| 4.8.1 | Content Move trim (Alt+trim) | ~80 |
| 4.8.2 | Time Stretch trim (Alt+Shift+trim) | ~120 |
| 4.8.3 | Loop trim (Ctrl+trim) | ~80 |

**Total Estimated:** ~2,380 LOC across 8 phases

---

## 5. KEYBOARD SHORTCUT MAP

### Tool Selection (Number Keys)

| Key | Tool | Cursor |
|-----|------|--------|
| 1 | Smart Tool (combined) | Context-dependent |
| 2 | Object Select | Arrow |
| 3 | Range Select | Crosshair |
| 4 | Split/Scissors | Scissors ✂ |
| 5 | Glue | Glue tube |
| 6 | Erase | Eraser |
| 7 | Zoom | Magnifier |
| 8 | Mute | Speaker off |
| 9 | Draw/Pencil | Pencil |
| 0 | Play/Audition | Speaker |

### Edit Mode Selection

| Key | Mode |
|-----|------|
| F1 | Shuffle |
| F2 | Slip |
| F3 | Spot |
| F4 | Grid |
| F5 | X-Fade |

### Navigation

| Key | Action |
|-----|--------|
| Tab | Next transient |
| Shift+Tab | Previous transient |
| Alt+Tab | Next clip edge |
| Alt+Shift+Tab | Previous clip edge |

### Snap Targets (Toggle)

| Key | Target |
|-----|--------|
| Ctrl+G | Toggle grid snap |
| Ctrl+E | Toggle event snap |
| Ctrl+Shift+C | Toggle cursor snap |

---

## 6. VISUAL DESIGN — Zone Indicators

### Hover Feedback

When smart tool is active and cursor hovers over a clip:

```
Zone-specific cursor + subtle zone highlight:

┌──────────────────────────────────┐
│ ◢ GLOW                    GLOW ◣ │  ← Fade handles: small circles with glow
│         ─── 0 dB ───           │  ← Volume line: horizontal dashed line
│                                  │
│         █████████████           │  ← Range zone: slight crosshair tint
│                                  │
│         ▓▓▓▓▓▓▓▓▓▓▓▓▓           │  ← Move zone: slight highlight
│                                  │
│ ◣ GLOW ◢         ↻      ◢ GLOW ◣ │  ← Trim: edge glow, Loop: icon
└──────────────────────────────────┘
```

**Zone Colors:**
| Zone | Hover Color | Active Color |
|------|-------------|--------------|
| Fade handles | `#4a9eff33` (blue 20%) | `#4a9eff66` (blue 40%) |
| Volume handle | `#ff904033` (orange 20%) | `#ff904066` (orange 40%) |
| Range Select | `#40ff9020` (green 12%) | `#40ff9040` (green 25%) |
| Move | transparent | `#ffffff10` (white 6%) |
| Trim edges | `#40c8ff33` (cyan 20%) | `#40c8ff66` (cyan 40%) |
| Loop | `#9370db33` (purple 20%) | `#9370db66` (purple 40%) |
| Crossfade | `#ffff4033` (yellow 20%) | `#ffff4066` (yellow 40%) |

---

## 7. STATE MACHINE — Complete Drag Flow

```
                    ┌──────────┐
                    │   IDLE   │
                    └────┬─────┘
                         │ onPointerDown
                         ▼
                    ┌──────────┐
                    │ HIT TEST │ ← Determine zone from position
                    └────┬─────┘
                         │
              ┌──────────┼──────────────┬──────────────┐
              ▼          ▼              ▼              ▼
         ┌────────┐ ┌────────┐    ┌────────┐    ┌────────┐
         │FADE_DRG│ │TRIM_DRG│    │MOVE_DRG│    │RANGE_DRG│
         └───┬────┘ └───┬────┘    └───┬────┘    └───┬────┘
             │          │             │              │
             │    Check modifiers:    │              │
             │    Alt = Content Move  │              │
             │    A+S = Time Stretch  │              │
             │    Ctrl = Loop Trim    │              │
             │          │             │              │
             │    Check modifiers:    │              │
             │          │       Alt = Copy           │
             │          │       Alt+click = Split    │
             │          │       A+S = Slip content   │
             │          │       Shift = Constrain    │
             │          │             │              │
             ▼          ▼             ▼              ▼
         ┌────────────────────────────────────────────┐
         │              APPLY EDIT MODE               │
         │  Shuffle / Slip / Spot / Grid / X-Fade     │
         └────────────────────────┬───────────────────┘
                                  │ onPointerUp
                                  ▼
                            ┌──────────┐
                            │  COMMIT  │ → Update provider, add to undo stack
                            └──────────┘
```

---

## 8. COMPARISON SUMMARY

### What FluxForge Already Has ✅

| Feature | Status |
|---------|--------|
| Smart tool zone detection (fade, trim, select) | ✅ Done |
| 4 edit modes (Shuffle, Slip, Spot, Grid) | ✅ Done |
| Modifier keys (Shift, Alt, Cmd) | ✅ Done |
| 10 discrete tools | ✅ Done |
| Grid snap | ✅ Done |
| Clip move, trim, fade | ✅ Done |
| Crossfade (basic) | ✅ Done |

### What FluxForge Needs (Gap Analysis)

| Feature | Priority | Source | Effort |
|---------|----------|--------|--------|
| **Volume handle (top-center)** | P0 | Cubase | Low |
| **Range/Move zone split (upper/lower body)** | P0 | Pro Tools | Medium |
| **Alt+click = Split** | P0 | Cubase | Low |
| **Alt+Shift = Slip content** | P0 | Cubase | Low |
| **Smart Snap (zoom-adaptive)** | P0 | Logic | Medium |
| **Events snap (to clip edges)** | P0 | Cubase | Medium |
| **Grid Relative snap** | P0 | Cubase | Low |
| **True ripple (Shuffle closes gaps)** | P0 | Pro Tools | Medium |
| **X-Fade edit mode** | P1 | Logic | Medium |
| **Loop handle (mid-right)** | P1 | Logic | Medium |
| **Tab to Transient** | P1 | Pro Tools | Medium |
| **Crossfade editor dialog** | P1 | All 3 | High |
| **Cursor snap (to playhead)** | P1 | Cubase | Low |
| **Trim sub-modes (Content Move, Time Stretch)** | P2 | Cubase | Medium |
| **Loop trim** | P2 | Pro Tools | Medium |
| **Marquee sub-selection** | P2 | Logic | High |
| **Junction resize (between clips)** | P2 | Logic | Medium |

### Unique FluxForge Advantages (KEEP)

| Feature | Note |
|---------|------|
| Integrated slot lab audio | No other DAW has this |
| DSP insert chain per track | FabFilter-quality built-in |
| Middleware integration | Wwise/FMOD-style events |
| ALE adaptive layering | Unique to FluxForge |

---

## 9. FINAL RECOMMENDATION

### Implementation Order

```
PHASE 1 (P0 — Core zones + modifiers):
  ├── Volume handle zone
  ├── Range/Move body split
  ├── Alt+click = Split
  ├── Alt+Shift = Slip content
  ├── Smart Snap (adaptive)
  ├── Events snap + Grid Relative
  └── True ripple Shuffle

PHASE 2 (P1 — Advanced features):
  ├── X-Fade edit mode
  ├── Loop handle
  ├── Tab to Transient
  ├── Crossfade editor
  └── Cursor snap

PHASE 3 (P2 — Polish):
  ├── Trim sub-modes
  ├── Loop trim
  ├── Junction resize
  └── Marquee selection
```

**Estimated Total:** ~2,380 LOC across 3 phases
**Timeline:** Phase 1 in this session, Phase 2-3 later

---

*Document: FluxForge Studio Smart Tool Ultimate Analysis*
*Sources: Cubase 14 Pro, Pro Tools 2025, Logic Pro X 11*
*Author: Claude (Principal Engine Architect)*
