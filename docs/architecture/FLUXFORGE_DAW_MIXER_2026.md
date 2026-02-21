# FLUXFORGE DAW MIXER 2026 — ULTIMATE ARCHITECTURE SPEC

Status: AUTHORITATIVE IMPLEMENTATION BLUEPRINT
Scope: DAW Section (NOT Slot Middleware Mixer)
Target: Pro Tools 2026–Class Mixer
Audience: Claude / Any Provider / Future Core Devs

---

# 0. PURPOSE

This document defines the complete architectural, behavioral, state, UI, routing,
undo, and performance specification for the FluxForge DAW Mixer.

It is written so that any provider can implement without ambiguity.

---

# 1. FUNDAMENTAL DESIGN DECISIONS

## 1.1 Dedicated Mixer Screen

The DAW mixer is NOT inline and NOT docked.

```
enum AppViewMode {
  edit,
  mixer,
}
```

Edit and Mixer share engine state but render different UI trees.

**Toggle:** `Cmd+=` (macOS) / `Ctrl+=` (Windows/Linux) switches between Edit and Mixer views instantly. No animation, no transition — immediate swap of the center zone widget tree.

**Shared State:**
- MixerProvider (channels, routing, levels)
- DspChainProvider (insert chains)
- Timeline state (playhead, transport)
- Selection state (selected track syncs between views)

**Independent State:**
- Scroll position (mixer has its own horizontal scroll)
- Strip width mode (narrow/regular per-view)
- View filter (which sections are visible)
- Spill state (only exists in mixer view)

---

# 2. ENGINE ORCHESTRATION LAYER

New module:

```
crates/rf-engine/src/daw_mixer/
```

Module structure:

```
daw_mixer/
 ├── mod.rs
 ├── session_graph.rs      // Coordinates TrackManager + Routing + InsertChain + AudioGraph
 ├── solo_engine.rs        // SIP/AFL/PFL with Listen Bus
 ├── folder_engine.rs      // Folder-as-Bus with summing + grouping
 ├── vca_engine.rs         // VCA remote-control fader logic
 ├── spill_engine.rs       // Spill/unspill for folders and VCAs
 ├── layout_snapshot.rs    // Undo snapshots for mixer layout state
 ├── group_engine.rs       // Mix/Edit group attribute following
```

SessionGraph coordinates TrackManager, Routing, InsertChain and AudioGraph.

---

# 3. CHANNEL TYPES

## 3.1 Type Definitions

| Type | Audio Path | Inserts | Sends | Fader | Meter | Pan | Record | I/O Selectors |
|------|-----------|---------|-------|-------|-------|-----|--------|--------------|
| **Audio** | ✅ Yes | 10 (A-J) | 10 (A-J) | ✅ | ✅ Pre/Post | ✅ | ✅ | Input + Output |
| **Aux Input** | ✅ Yes (receives bus) | 10 (A-J) | 10 (A-J) | ✅ | ✅ Pre/Post | ✅ | ❌ | Input (bus) + Output |
| **Bus (Subgroup)** | ✅ Yes (sum of routed) | 10 (A-J) | 10 (A-J) | ✅ | ✅ Pre/Post | ✅ | ❌ | — + Output |
| **Folder** | ✅ Yes (Routing Folder) | 10 (A-J) | 10 (A-J) | ✅ | ✅ Pre/Post | ✅ | ❌ | — + Output |
| **VCA Master** | ❌ No (control only) | ❌ | ❌ | ✅ | ✅ (loudest member) | ❌ | ❌ | — |
| **Instrument** | ✅ Yes | 10 (A-J) | 10 (A-J) | ✅ | ✅ Pre/Post | ✅ | ✅ (MIDI) | MIDI In + Audio Out |
| **Master Fader** | ✅ Yes (sum bus) | 10 (A-J, POST-fader!) | ❌ | ✅ | ✅ Pre/Post | ❌ | ❌ | — + Output |

### Key Behavioral Rules

- **Master Fader inserts are POST-fader** (all other types are PRE-fader). This is the Pro Tools convention and critical for mastering chain placement.
- **VCA Master** does not pass audio. Its fader remotely controls the faders of all group member tracks. The VCA meter displays the level of the loudest member track, NOT a sum.
- **Folder** behaves as both a visual group container AND an Aux Input (Routing Folder). Children are summed into the folder's bus.
- **Instrument** combines MIDI input with audio output in one strip. The instrument plugin sits in the first insert slot.

## 3.2 Strip Color Coding

Each channel type has a distinct default strip color (user-overridable):

| Type | Default Color | Hex |
|------|--------------|-----|
| Audio | Blue | `#4A9EFF` |
| Aux | Yellow | `#FFD700` |
| Bus | Green | `#40FF90` |
| Folder | Purple | `#9370DB` |
| VCA | Orange | `#FF9040` |
| Instrument | Cyan | `#40C8FF` |
| Master | Red | `#FF4060` |

Color is shown as:
- 4px left border on the entire strip height
- Track name background tint (10% opacity)
- I/O selector nameplates can use path-specific colors (Pro Tools 2023.12+)

---

# 4. SOLO ENGINE

## 4.1 Solo Modes

| Mode | Abbreviation | Behavior |
|------|-------------|----------|
| **Solo In Place** | SIP | Mutes all non-soloed tracks. Default mode. Solo button = yellow. |
| **After Fader Listen** | AFL | Routes post-insert, post-pan, post-fader signal to dedicated Listen Bus. Solo = blue. |
| **Pre Fader Listen** | PFL | Routes post-insert, pre-pan, pre-fader signal to Listen Bus. Solo = green. |

## 4.2 Solo Safe

- **Activation:** Cmd+Click (Mac) / Ctrl+Click (Win) on Solo button
- **Visual:** Solo button outline becomes gray/dimmed
- **Behavior:** Track is excluded from muting when other tracks are soloed (SIP mode)
- **Use Case:** Keep reverb returns, sidechain sources, and submix buses audible during solo
- **Note:** Solo Safe is NOT available in AFL/PFL modes (redundant — those modes don't mute)

## 4.3 Listen Bus

- Dedicated stereo bus for AFL/PFL monitoring
- Separate volume control (Listen Bus Level)
- Routed to monitor output, bypasses main output
- AFL level is affected by track fader; PFL level is independent of fader
- AFL/PFL solo on a track routes to Listen Bus, NOT to main stereo out

## 4.4 Requirements

- Listen Bus exists as engine-level construct (not a user-created bus)
- Solo recompute is deterministic: same state → same result
- Zero allocation in audio thread during solo toggle
- Solo/unsolo is instant (no fade, no ramp)
- Multiple tracks can be soloed simultaneously (additive)
- Cmd+Click on already-soloed button = exclusive solo (unsolo all others)

---

# 5. SEND FLEXIBILITY

## 5.1 Send Count and Organization

- **10 sends per channel** organized as Sends A–E and Sends F–J
- Each group of 5 can be independently shown/hidden via View menu
- Sends can route to any Bus or physical Output

## 5.2 Send Tap Positions

Each send independently selects its tap point:

| Tap Position | Signal Source |
|-------------|--------------|
| **PreInsert** | Raw input signal, before any insert processing |
| **PostInsert** | After all insert processing, before fader |
| **PreFader** | After inserts, before fader (most common for cue mixes) |
| **PostFader** | After fader, before pan |
| **PostPan** | After fader AND pan (default, most common for FX sends) |

## 5.3 Send Controls (per send)

| Control | Type | Range | Default |
|---------|------|-------|---------|
| **Destination** | Selector (popup) | Any Bus or Output | unassigned |
| **Level** | Fader/Knob | -∞ to +6 dB | -∞ (off) |
| **Pan** | Knob | L100 – C – R100 | Center |
| **Mute** | Toggle | On/Off | Off |
| **Pre/Post** | Toggle (P button) | Pre-fader / Post-fader | Post |

## 5.4 Send Display in Strip

**Compact view (in strip):**
- Send assignment name (abbreviated)
- Mini level indicator (horizontal bar)
- Pre/Post indicator ("P" lit blue = pre-fader)

**Expanded view (floating window):**
- Click on send assignment → opens floating Send window
- Full-size fader, pan knob, meter, pre/post toggle, mute button
- Send window stays open, follows selection if "Follow Track Selection" enabled

## 5.5 Send Shortcuts

| Shortcut | Action |
|----------|--------|
| Shift+Q | Mute all sends on selected tracks |
| Shift+4 | Mute sends A-E on selected tracks |
| Shift+5 | Mute sends F-J on selected tracks |
| Click diamond (◆) | Show mini faders for that send across ALL tracks |
| Option+Shift+Click send | Assign same send to all selected tracks |

---

# 6. INSERT SYSTEM

## 6.1 Insert Count and Organization

- **10 inserts per channel** organized as Inserts A–E (pre-fader) and Inserts F–J (pre-fader)
- Exception: Master Fader inserts are ALL post-fader
- Each group of 5 can be independently shown/hidden via View menu
- Signal flow is serial: A → B → C → D → E → F → G → H → I → J → Fader

## 6.2 Insert Types

| Type | Description |
|------|-------------|
| **Plugin** | Software processor (EQ, compressor, etc.) |
| **Hardware Insert** | External I/O loop (send → outboard → return) |
| **Instrument** | Virtual instrument (only in first slot of Instrument tracks) |

## 6.3 Insert Slot States

| State | Visual | CPU | Audio Processing |
|-------|--------|-----|-----------------|
| **Active** | Normal | ✅ Uses CPU | ✅ Processes audio |
| **Bypassed** | Blue highlight on slot | ✅ Uses CPU | ❌ Signal passes through unchanged |
| **Inactive** | Grayed out / italic text | ❌ No CPU | ❌ No processing, removed from chain |
| **Empty** | Blank slot | — | — |

## 6.4 Insert Interactions

| Action | Behavior |
|--------|----------|
| Click empty slot | Opens plugin selector popup (categorized: EQ, Dynamics, Delay, Reverb, etc.) |
| Click filled slot | Opens plugin editor window |
| Drag slot → other slot | Reorder insert (move) |
| Option/Alt+Drag | Copy insert to other slot |
| Cmd+Click filled slot | Toggle bypass |
| Ctrl+Cmd+Click | Toggle inactive (removes from chain, preserves settings) |
| Right-click filled slot | Context menu: Open, Bypass, Make Inactive, Copy, Paste, Move, Remove |
| Shift+2 | Toggle bypass on Inserts A-E for selected tracks |
| Shift+3 | Toggle bypass on Inserts F-J for selected tracks |
| Shift+2 + Shift+3 | A/B comparison: bypass one set, enable other |

## 6.5 Insert Display in Strip

- Plugin name (abbreviated to fit strip width)
- Color-coded slot background based on plugin category
- Bypass indicator (blue dot or highlight)
- Inactive indicator (grayed out text)

---

# 7. GLOBAL UNDO

All mixer changes go through AppTransactionManager.

Undo includes:
- Fader position changes
- Pan changes
- Mute/Solo/Record arm toggles
- Insert add/remove/reorder/bypass/inactive
- Send assignments and levels
- Routing changes (I/O assignments)
- Track creation/deletion
- Track reordering
- Group creation/modification
- VCA assignments
- Spill state changes
- View/layout changes (strip width, section visibility)
- Automation mode changes

**Undo granularity:**
- Fader moves are coalesced: continuous drag = one undo step
- Discrete actions (mute toggle, insert add) = individual undo steps
- Group attribute changes = one undo step per action, even if affecting multiple tracks

---

# 8. UI STRUCTURE

## 8.1 Overall Layout

```
MixerScreen
 ├── MixerTopBar (44px fixed)
 │   ├── View Toggles (section visibility checkboxes)
 │   ├── Strip Width Toggle (Narrow / Regular)
 │   ├── Section Filters (show/hide: Tracks, Buses, Auxes, VCAs, Instruments, Master)
 │   ├── Solo Mode Selector (SIP / AFL / PFL)
 │   ├── Metering Mode (Peak / RMS / VU / K-14 / K-20)
 │   ├── Pre/Post Fader Metering Toggle
 │   ├── Master LUFS Display (integrated / short-term / momentary)
 │   ├── Groups Popup
 │   └── Search / Filter Tracks
 │
 ├── MixerBody (fills remaining height)
 │   ├── ScrollableStripZone (horizontal scroll, virtualized)
 │   │   ├── [Section: TRACKS] ── separator ── [labeled divider]
 │   │   │   ├── AudioStrip × N
 │   │   │   └── InstrumentStrip × N
 │   │   ├── [Section: BUSES] ── separator
 │   │   │   └── BusStrip × N
 │   │   ├── [Section: AUX] ── separator
 │   │   │   └── AuxStrip × N
 │   │   └── [Section: VCA] ── separator
 │   │       └── VCAStrip × N
 │   │
 │   └── PinnedZone (right side, always visible, not scrollable)
 │       └── MasterStrip (wider: 120px regular / 90px narrow)
 │
 └── MixerStatusBar (24px fixed, bottom)
     ├── Track Count ("48 tracks, 8 buses, 4 aux, 2 VCA")
     ├── DSP Load Indicator
     ├── Sample Rate / Buffer Size
     ├── Delay Compensation Status
     └── Session Clock (timecode / bars|beats)
```

## 8.2 Section Dividers

Between each channel type section, a labeled divider:

```
┌────────────────────────────────────────────────────────────┐
│ ▼ TRACKS (12)  │  ▼ BUSES (4)  │  ▼ AUX (3)  │  ▼ VCA (2)  ║ MASTER │
└────────────────────────────────────────────────────────────┘
```

- Click section label → collapse/expand that section
- Track count shown in parentheses
- Section order is fixed: Tracks → Buses → Aux → VCA → (Master pinned)
- Sections can be hidden entirely via TopBar filter buttons

## 8.3 Strip Virtualization

- Only strips visible in the viewport are rendered (+ 2 strips buffer on each side)
- Horizontal scroll via mouse wheel (Shift+scroll), trackpad gesture, or scrollbar
- Scroll position persists across Edit↔Mixer view switches

---

# 9. CHANNEL STRIP ANATOMY

## 9.1 Strip Layout (Top to Bottom)

The strip is divided into configurable sections. Each section can be shown/hidden independently via View menu.

```
┌──────────────────────┐
│ [Track Color] (4px)  │ ← Full-width color bar, click to change color
├──────────────────────┤
│ [Track Number] (16px)│ ← "#01", "#02", etc. Sequential numbering
├──────────────────────┤
│ ╔══════════════════╗ │
│ ║ INPUT SELECTOR   ║ │ ← Click → popup menu (inputs, buses)
│ ╚══════════════════╝ │
├──────────────────────┤
│ ╔══════════════════╗ │
│ ║ OUTPUT SELECTOR  ║ │ ← Click → popup menu (outputs, buses)
│ ╚══════════════════╝ │
├──────────────────────┤
│ ╔══════════════════╗ │
│ ║ AUTOMATION MODE  ║ │ ← "off" / "read" / "tch" / "ltch" / "wrt" / "t/l" / "trim"
│ ╚══════════════════╝ │
├──────────────────────┤
│ ╔══════════════════╗ │
│ ║ GROUP ID         ║ │ ← "a", "b", "a,c" — group membership letters
│ ╚══════════════════╝ │
├──────────────────────┤  ─── SECTION: INSERTS A-E ───
│ ┌──────────────────┐ │
│ │ Insert A         │ │ ← Plugin name, click to open, Cmd+click = bypass
│ │ Insert B         │ │
│ │ Insert C         │ │
│ │ Insert D         │ │
│ │ Insert E         │ │
│ └──────────────────┘ │
├──────────────────────┤  ─── SECTION: INSERTS F-J ───
│ ┌──────────────────┐ │
│ │ Insert F         │ │
│ │ Insert G         │ │
│ │ Insert H         │ │
│ │ Insert I         │ │
│ │ Insert J         │ │
│ └──────────────────┘ │
├──────────────────────┤  ─── SECTION: SENDS A-E ───
│ ┌──────────────────┐ │
│ │ Send A [◆] [P]   │ │ ← Assignment + mini meter + pre/post
│ │ Send B [◆] [P]   │ │
│ │ Send C [◆] [P]   │ │
│ │ Send D [◆] [P]   │ │
│ │ Send E [◆] [P]   │ │
│ └──────────────────┘ │
├──────────────────────┤  ─── SECTION: SENDS F-J ───
│ ┌──────────────────┐ │
│ │ Send F [◆] [P]   │ │
│ │ Send G [◆] [P]   │ │
│ │ Send H [◆] [P]   │ │
│ │ Send I [◆] [P]   │ │
│ │ Send J [◆] [P]   │ │
│ └──────────────────┘ │
├──────────────────────┤  ─── SECTION: EQ CURVE ───
│ ┌──────────────────┐ │
│ │                  │ │ ← Miniature EQ frequency response curve
│ │   ~~~\/~~~       │ │   (from first EQ plugin in insert chain)
│ │                  │ │   Click to open EQ plugin editor
│ └──────────────────┘ │
├──────────────────────┤  ─── SECTION: DELAY COMPENSATION ───
│ ┌──────────────────┐ │
│ │ dly: 1024 smp    │ │ ← Plugin-induced delay (samples)
│ │ cmp: 1024 smp    │ │ ← Compensation applied by engine
│ └──────────────────┘ │   Colors: green=OK, orange=slowest, red=not compensated
├──────────────────────┤  ─── SECTION: COMMENTS ───
│ ┌──────────────────┐ │
│ │ "Kick drum, SM57"│ │ ← User text notes, editable
│ └──────────────────┘ │
├──────────────────────┤  ─── ALWAYS VISIBLE BELOW ───
│                      │
│    ┌──┐  ┌────────┐  │
│    │  │  │ ██████ │  │ ← Pan knob + pan value display
│    └──┘  │ ██████ │  │   Stereo: dual pan (L/R independent)
│          │ ██████ │  │
│  ┌────┐  │ ██████ │  │ ← Fader + Meter (side by side)
│  │fade│  │ ██████ │  │   Fader: -∞ to +12 dB
│  │ r  │  │ ██████ │  │   Meter: dual-bar (L/R) with peak hold
│  │    │  │ ██████ │  │   dB scale marks on fader track
│  │    │  │ ██████ │  │
│  │ ── │  │ ██  ██ │  │ ← Unity (0dB) mark at 75% fader travel
│  │    │  │ ██  ██ │  │
│  │    │  │ █    █ │  │
│  └────┘  └────────┘  │
│                      │
│  ┌──────────────────┐│
│  │ -12.4 dB         ││ ← Numeric fader value display
│  └──────────────────┘│
│                      │
│  ┌──┐ ┌──┐ ┌──┐     │
│  │ M│ │ S│ │ R│     │ ← Mute (green) / Solo (yellow) / Record (red)
│  └──┘ └──┘ └──┘     │
│                      │
│  ┌──────────────────┐│
│  │ TRACK NAME       ││ ← Editable, shows track color behind
│  └──────────────────┘│
│                      │
│  ┌──────────────────┐│
│  │ Mono / Stereo    ││ ← Channel format badge
│  └──────────────────┘│
└──────────────────────┘
```

## 9.2 Strip Width Modes

| Mode | Width | Fader Width | Meter Width | Use Case |
|------|-------|-------------|-------------|----------|
| **Narrow** | 56px | 20px | 12px (single bar) | Large sessions (100+ tracks) |
| **Regular** | 90px | 32px | 24px (dual L/R bars) | Normal mixing |

**Toggle:** `Ctrl+Alt+M` or View menu → "Narrow Mix"

**Per-strip width is NOT supported** (Pro Tools convention: all strips same width). This keeps visual alignment clean.

## 9.3 Fader Specifications

| Property | Value |
|----------|-------|
| Range | -∞ to +12 dB |
| Unity position | 75% of fader travel (0 dB) |
| Default | 0 dB (unity) |
| Curve | 5-segment logarithmic (Cubase-style, already implemented) |
| Resolution | Fine mode: hold Cmd/Ctrl while dragging for 0.1 dB increments |
| Reset | Option+Click = reset to 0 dB |
| dB Scale Marks | +12, +6, 0, -6, -12, -20, -30, -40, -50, -∞ |
| Numeric Display | Below fader, shows current dB value (1 decimal) |

## 9.4 Meter Specifications

| Property | Value |
|----------|-------|
| Type | Peak (default), RMS, VU, K-14, K-20 |
| Tap Point | Pre-fader or Post-fader (global toggle) |
| Channels | Mono: single bar. Stereo: dual bar (L/R) |
| Peak Hold | Falling segment, decay = 0.92/frame, auto-clear after 3s |
| Clip Indicator | Red bar at top, click to clear |
| Noise Floor Gate | -80 dB (below = meter invisible) |
| Refresh Rate | 30 fps (metering tick, NOT tied to UI frame rate) |
| Color Gradient | `#40c8ff → #40ff90 → #ffff40 → #ff9040 → #ff4040` |

**Pro Tools Meter Types (global selection, except Master):**

| Type | Scale | Ballistics | Best For |
|------|-------|------------|----------|
| **Sample Peak** | Linear, -40 to 0 dBFS | Instant | Tracking, mixing |
| **RMS** | Average signal level | 300ms integration | Level matching |
| **VU** | -23 to +3 VU (extended to -40) | 300ms rise, 300ms fall | Analog-style mixing |
| **K-14** | 0 dB = -14 dBFS | RMS-based | Pop/rock mixing |
| **K-20** | 0 dB = -20 dBFS | RMS-based | Film/classical mixing |

Master Fader can have its own metering type independent of global setting.

## 9.5 Pan Specifications

| Channel Format | Pan UI |
|---------------|--------|
| **Mono** | Single pan knob (L100 – C – R100) |
| **Stereo** | Dual pan knobs (L pan + R pan, Pro Tools-style independent) |

| Action | Behavior |
|--------|----------|
| Click+drag | Adjust pan |
| Option+Click | Reset to center |
| Cmd+drag | Fine adjust (0.1 increments) |
| Shift+Click | Link/unlink stereo pan knobs |

---

# 10. I/O SELECTORS

## 10.1 Input Selector

- Located near top of strip (below track number)
- Click → popup menu with:
  - Physical inputs (Mic/Line from interface)
  - Bus inputs (internal routing)
  - "No Input" option
- Shows abbreviated path name when assigned
- Color-coded nameplates (matches I/O Setup colors)

## 10.2 Output Selector

- Located below input selector
- Click → popup menu with:
  - Physical outputs
  - Bus outputs
  - Multiple outputs (Ctrl+Click adds secondary output, "+" prefix shown)
- Shows abbreviated path name
- Color-coded nameplates

## 10.3 Modifier Key Routing Shortcuts

| Modifier | Action |
|----------|--------|
| Click | Assign output for this track only |
| Ctrl+Click (Cmd+Click Mac) | Add additional output ("+Out 1-2") |
| Option+Shift+Click | Assign same output to ALL selected tracks |
| Cmd+Option+Click | Cascade assignments (sequential bus assignment across selected tracks) |

---

# 11. AUTOMATION SYSTEM

## 11.1 Automation Modes

| Mode | Abbreviation | Strip Display | Behavior |
|------|-------------|---------------|----------|
| **Off** | off | "off" (dim) | Ignores all existing automation |
| **Read** | read | "read" (green) | Plays back existing automation, no writing |
| **Touch** | tch | "tch" (yellow) | Writes while touching, reverts on release |
| **Latch** | ltch | "ltch" (orange) | Writes while touching, holds new value on release until stop |
| **Touch/Latch** | t/l | "t/l" (yellow/orange) | Volume = Touch, all other params = Latch |
| **Write** | wrt | "wrt" (RED) | Overwrites ALL automation from play start. DANGEROUS. |
| **Trim** | trim | "trim" (purple) | Offsets existing automation (adds delta, not absolute). Pro Tools Ultimate only. |

## 11.2 Automation Mode Selector

- Located below Output Selector on strip
- Click → popup menu with all modes
- Color-coded text indicates current mode
- **Safety:** After Write pass, auto-switch to Touch or Latch (configurable in preferences)

## 11.3 Automatable Parameters

| Parameter | Category |
|-----------|----------|
| Volume fader | Level |
| Pan | Level |
| Mute | Switch |
| Send levels (A-J) | Level |
| Send pans (A-J) | Level |
| Send mutes (A-J) | Switch |
| Plugin parameters (all) | Level/Switch |

---

# 12. GROUP SYSTEM

## 12.1 Group Types

| Type | Scope | Affects |
|------|-------|---------|
| **Edit Group** | Edit window only | Clip selection, trimming, moving |
| **Mix Group** | Mix window only | Fader, pan, mute, solo, sends, inserts |
| **Edit/Mix Group** | Both windows | All of the above |

## 12.2 Group Attributes (Mix Groups)

When a group is active, these attributes follow (configurable per group):

| Attribute | Default |
|-----------|---------|
| Volume | ✅ Yes |
| Mute | ✅ Yes |
| Solo | ✅ Yes |
| Send Levels | ✅ Yes |
| Send Mutes | ✅ Yes |
| Pan | ❌ No (optional) |
| Record Enable | ❌ No (optional) |
| Insert Bypass | ❌ No (optional) |

## 12.3 Group ID Display

- Each group gets a letter: a, b, c, d, ... (up to 26)
- Strip shows group membership in Group ID field: "a", "b,d", "a,c,f"
- Active group letters = bold. Suspended = italic/dim.
- Click group ID → opens Group management popup

## 12.4 Group Actions

| Action | Behavior |
|--------|----------|
| Cmd+G | Create new group from selected tracks |
| Shift+Cmd+G | Suspend/resume all groups |
| Click group letter | Toggle that group active/suspended |

---

# 13. VCA MASTER TRACKS

## 13.1 VCA Behavior

- VCA fader adjusts the level of ALL member tracks proportionally
- VCA does NOT sum audio — it's a remote control
- Moving VCA fader from 0 dB to -6 dB → all member faders move down 6 dB from their current positions
- VCA solo → solos all member tracks
- VCA mute → mutes all member tracks

## 13.2 VCA Meter

- Shows the level of the **loudest member track** (not sum)
- This is intentional — it shows peak exposure across the group

## 13.3 VCA Strip Layout

Simplified strip (no I/O, no inserts, no sends, no pan):

```
┌──────────────────────┐
│ [Track Color] (4px)  │
│ [Track Number]       │
│ [Group ID]           │
│                      │
│  Fader + Meter       │ ← VCA fader controls members
│                      │
│  -6.0 dB             │ ← VCA offset value
│                      │
│  [M] [S]             │ ← Mute/Solo (apply to all members)
│                      │
│  VCA NAME            │
│  [Spill ▼]           │ ← Click to spill (show member tracks)
└──────────────────────┘
```

## 13.4 Spill

- **Spill** = clicking a VCA or Folder temporarily shows only its member tracks
- Spill button on VCA/Folder strip (▼ triangle or dedicated button)
- During spill: non-member tracks are hidden, VCA strip highlighted
- "Unspill" button or Escape to return to full view
- Spill is display-only — does NOT affect audio routing
- Nested spill: spilling into a folder that contains another folder

---

# 14. METERING MODES

## 14.1 Global Metering Options

Set via TopBar selector, affects ALL channels (except Master if overridden):

| Mode | Description | Scale |
|------|-------------|-------|
| **Sample Peak** | Instantaneous sample values | -40 to 0 dBFS, linear |
| **Pro Tools Classic** | Legacy peak with slower ballistics | -60 to +6 dBFS |
| **RMS** | Average signal level (300ms window) | -60 to 0 dBFS |
| **VU** | Classic VU ballistics (300ms rise/fall) | -40 to +3 VU |
| **K-14** | Bob Katz K-System, 0 = -14 dBFS | Centered at -14 dBFS |
| **K-20** | Bob Katz K-System, 0 = -20 dBFS | Centered at -20 dBFS |

## 14.2 Pre/Post Fader Metering

- Global toggle in TopBar
- **Pre-Fader:** Shows level before fader — best for tracking (see true input level)
- **Post-Fader:** Shows level after fader — best for mixing (see what listener hears)

## 14.3 Meter Width

- Adjustable by holding Ctrl+Option+Cmd (Mac) and clicking any meter
- Cycles through: thin (8px) → normal (16px) → wide (24px)
- Global change — all meters resize together

---

# 15. VIEW SYSTEM (Mix Window Views)

## 15.1 Toggleable Sections

Via `View → Mix Window Views` menu, each section can be independently shown/hidden:

| Section | Default | Description |
|---------|---------|-------------|
| **Mic Preamps** | Hidden | Hardware preamp gain controls |
| **Instruments** | Hidden | Instrument plugin display |
| **Inserts A-E** | Shown | First 5 insert slots |
| **Inserts F-J** | Hidden | Last 5 insert slots |
| **Sends A-E** | Shown | First 5 send slots |
| **Sends F-J** | Hidden | Last 5 send slots |
| **EQ Curve** | Hidden | Miniature EQ response curve |
| **Delay Compensation** | Hidden | dly/cmp values with color coding |
| **Track Color** | Shown | Color bar at top of strip |
| **Comments** | Hidden | User text notes |
| **All** | — | Show everything |
| **None** | — | Hide all optional sections |

## 15.2 View Presets

- Save current view configuration as named preset
- Quick recall: "Mixing" (inserts + sends A-E), "Tracking" (I/O + comments), "Debug" (all + delay comp)
- FluxForge-specific: presets stored in MixerLayoutSnapshot

---

# 16. KEYBOARD SHORTCUTS

## 16.1 Window Navigation

| Shortcut | Action |
|----------|--------|
| **Cmd+=** | Toggle between Edit and Mix window |
| **Cmd+M** | Minimize mix window |
| **Option+Shift+M** | Narrow/Regular strip width toggle |

## 16.2 Channel Operations

| Shortcut | Action |
|----------|--------|
| **Cmd+Click Solo** | Exclusive solo (unsolo all others) |
| **Cmd+Click Solo** (when soloed) | Solo safe toggle |
| **Option+Click Fader** | Reset fader to 0 dB |
| **Option+Click Pan** | Reset pan to center |
| **Cmd+Drag Fader** | Fine adjust (0.1 dB increments) |
| **Option+S** | Clear all solos |
| **Ctrl+Click Mute** | Mute all tracks |

## 16.3 Insert/Send Shortcuts

| Shortcut | Action |
|----------|--------|
| **Shift+2** | Bypass Inserts A-E on selected tracks |
| **Shift+3** | Bypass Inserts F-J on selected tracks |
| **Shift+Q** | Mute all sends on selected tracks |
| **Shift+4** | Mute sends A-E on selected tracks |
| **Shift+5** | Mute sends F-J on selected tracks |

## 16.4 Group Shortcuts

| Shortcut | Action |
|----------|--------|
| **Cmd+G** | Create group from selection |
| **Shift+Cmd+G** | Suspend/resume all groups |
| **Cmd+Shift+Click Solo** | Solo safe toggle |

## 16.5 Routing Shortcuts

| Shortcut | Action |
|----------|--------|
| **Option+Shift+Click I/O** | Assign same I/O to all selected tracks |
| **Cmd+Option+Click I/O** | Cascade I/O assignments across selected tracks |
| **Ctrl+Click Output** | Add additional output (+) |

## 16.6 Automation Shortcuts

| Shortcut | Action |
|----------|--------|
| **Cmd+4** | Set automation mode: Off |
| **Cmd+5** | Set automation mode: Read |
| **Cmd+6** | Set automation mode: Touch |
| **Cmd+7** | Set automation mode: Latch |

---

# 17. MASTER STRIP

## 17.1 Master Strip Differences

The Master Fader strip differs from regular tracks:

| Feature | Regular Track | Master Fader |
|---------|--------------|--------------|
| Insert position | Pre-fader | **Post-fader** |
| Pan | Yes | **No** |
| Sends | Yes | **No** |
| Record | Yes | **No** |
| Input selector | Yes | **No** |
| Width | Regular (90px) | **Wider (120px)** |
| LUFS display | No | **Yes** (integrated, short-term, momentary) |
| Meter | Standard | **Wider + True Peak indicator** |
| Label | Track name | **"STEREO OUT"** or output path name |

## 17.2 Master Strip Layout

```
┌────────────────────────────┐
│ [STEREO OUT] (label)       │
├────────────────────────────┤
│ ╔════════════════════════╗ │
│ ║ OUTPUT SELECTOR        ║ │
│ ╚════════════════════════╝ │
├────────────────────────────┤
│ ┌────────────────────────┐ │
│ │ Insert A (POST-fader!) │ │
│ │ Insert B               │ │
│ │ Insert C               │ │
│ │ Insert D               │ │
│ │ Insert E               │ │
│ │ ── divider ──          │ │
│ │ Insert F               │ │
│ │ Insert G               │ │
│ │ Insert H               │ │
│ │ Insert I               │ │
│ │ Insert J               │ │
│ └────────────────────────┘ │
├────────────────────────────┤
│                            │
│   ┌─────┐  ┌───────────┐  │
│   │     │  │ ████ ████ │  │ ← Wider fader + dual meter
│   │     │  │ ████ ████ │  │
│   │ fdr │  │ ████ ████ │  │
│   │     │  │ ████ ████ │  │
│   │ ──  │  │ ██    ██  │  │ ← 0 dB mark
│   │     │  │ ██    ██  │  │
│   │     │  │ █      █  │  │
│   └─────┘  └───────────┘  │
│                            │
│  ┌────────────────────────┐│
│  │ -0.2 dB               ││ ← Fader value
│  ├────────────────────────┤│
│  │ LUFS: -14.2 I          ││ ← Integrated LUFS
│  │       -12.8 S          ││ ← Short-term LUFS
│  │       -10.5 M          ││ ← Momentary LUFS
│  │ TP:    -1.2 dBTP       ││ ← True Peak
│  └────────────────────────┘│
│                            │
│  ┌──┐                      │
│  │ M│                      │ ← Mute only (no Solo, no Record)
│  └──┘                      │
│                            │
│  ┌────────────────────────┐│
│  │ STEREO OUT             ││
│  └────────────────────────┘│
└────────────────────────────┘
```

---

# 18. FOLDER TRACKS

## 18.1 Routing Folder Behavior

A Routing Folder combines:
- **Visual grouping** (child tracks nested under folder)
- **Audio summing** (child tracks route through folder's bus)
- **Insert processing** (folder has its own insert chain, applied post-sum)
- **Level control** (folder fader controls sum level)

## 18.2 Folder Strip

Similar to Aux Input strip, plus:
- **Spill button** (▼) to show only child tracks
- **Collapse/expand arrow** in strip header
- **Child count badge** ("5 tracks")
- **Slightly different background** (subtle gradient to distinguish from regular tracks)

## 18.3 Folder vs VCA

| Feature | Routing Folder | VCA Master |
|---------|---------------|------------|
| Passes audio | ✅ Yes (sum bus) | ❌ No |
| Inserts | ✅ Yes (post-sum) | ❌ No |
| Pan | ✅ Yes | ❌ No |
| Can process group | ✅ Yes (apply EQ to group) | ❌ No (just gain) |
| Track membership | Hierarchical (parent/child) | Non-hierarchical (any track) |
| Multiple membership | ❌ No (one parent) | ✅ Yes (any number of VCAs) |
| Spill | ✅ Yes | ✅ Yes |

---

# 19. PERFORMANCE REQUIREMENTS

| Metric | Target |
|--------|--------|
| Strip render time | < 2ms per strip (60fps budget) |
| Virtualization | Only visible strips + 2 buffer strips rendered |
| Fader drag latency | < 16ms (1 frame at 60fps) |
| Meter refresh | 30 Hz (independent of UI frame rate) |
| Scroll performance | 60fps during horizontal scroll with 200+ strips |
| View switch (Edit↔Mixer) | < 100ms |
| Solo recompute | < 1ms for 200 tracks |
| Memory per strip | < 50KB widget overhead |

---

# 20. IMPLEMENTATION PHASES

## Phase 1: Core Mixer Screen (P0)

- [ ] `AppViewMode` enum + Cmd+= toggle
- [ ] `MixerScreen` widget with TopBar + Body + StatusBar
- [ ] Channel strip widget with fader + meter + pan + M/S/R
- [ ] Strip virtualization (horizontal scroll)
- [ ] Master strip (pinned right)
- [ ] Section dividers (Tracks, Master)
- [ ] Wire existing `MixerProvider` channels + master
- [ ] Existing FFI metering integration

## Phase 2: I/O, Inserts, Sends (P1)

- [ ] Input/Output selectors with popup menus
- [ ] Insert slots A-E display (from DspChainProvider)
- [ ] Send slots A-E display
- [ ] Automation mode selector
- [ ] Track number display
- [ ] Strip color bar
- [ ] Group ID display
- [ ] Narrow/Regular width toggle

## Phase 3: Buses, Aux, VCA (P1) ✅ (commit `5f99ff53`)

- [x] Wire buses from MixerProvider (currently `const []`)
- [x] Wire auxes from MixerProvider
- [x] VCA strip implementation
- [x] VCA fader remote-control logic
- [x] Spill functionality (SpillController — Dart-only, no FFI)
- [x] Section show/hide (collapsed indicators with count, clickable headers)

## Phase 4: Advanced Features (P2)

- [ ] Solo engine (SIP/AFL/PFL) in Rust
- [ ] Listen Bus implementation
- [ ] Solo Safe
- [ ] Group system (create, attributes, suspend)
- [ ] Folder track (Routing Folder)
- [ ] View presets
- [ ] Inserts F-J, Sends F-J
- [ ] EQ curve display
- [ ] Delay compensation display
- [ ] Comments section
- [ ] All metering modes (VU, K-14, K-20)

## Phase 5: Polish (P3)

- [ ] Global undo for all mixer operations
- [ ] Trim automation mode
- [ ] Hardware insert support
- [ ] Floating send windows
- [ ] Cascade I/O assignment
- [ ] Per-strip context menus
- [ ] Keyboard shortcut parity with Pro Tools
- [ ] View switch animation refinement

---

# 21. FILE STRUCTURE (Flutter)

```
flutter_ui/lib/
├── screens/
│   └── mixer_screen.dart              # NEW: Dedicated mixer view
├── widgets/
│   └── mixer/
│       ├── ultimate_mixer.dart         # EXISTING: Refactor for reuse
│       ├── mixer_strip.dart            # NEW: Full Pro Tools-style strip
│       ├── mixer_master_strip.dart     # NEW: Master fader strip
│       ├── mixer_vca_strip.dart        # NEW: VCA-specific strip
│       ├── mixer_folder_strip.dart     # NEW: Folder/Routing strip
│       ├── mixer_top_bar.dart          # NEW: View toggles, meters, filters
│       ├── mixer_status_bar.dart       # NEW: Track count, DSP load
│       ├── mixer_section_divider.dart  # NEW: Section headers
│       ├── io_selector_popup.dart      # NEW: I/O assignment popup
│       ├── send_slot_widget.dart       # NEW: Send display in strip
│       ├── insert_slot_widget.dart     # EXISTING: Refactor
│       ├── automation_mode_badge.dart  # NEW: Mode selector widget
│       ├── group_id_badge.dart         # NEW: Group membership display
│       ├── eq_curve_thumbnail.dart     # NEW: Mini EQ curve
│       └── delay_comp_display.dart     # NEW: PDC indicator
├── controllers/
│   └── mixer/
│       ├── mixer_view_controller.dart  # NEW: View state (sections, width, scroll)
│       └── spill_controller.dart       # NEW: Spill state management
└── models/
    └── mixer_view_models.dart          # NEW: View-specific models
```

---

# 22. REFERENCES

Architecture informed by analysis of:

- [Pro Tools Mix Window Education](https://protoolsedu.weebly.com/mix-window.html)
- [Emerson College — What's in the Mix Window](https://support.emerson.edu/hc/en-us/articles/21708868557979-What-s-in-the-Mix-Window)
- [Product London — How to Use the Mix Window](https://www.productlondon.com/use-mix-window-pro-tools-guide/)
- [Pro Tools Solo Modes — Sound On Sound](https://www.soundonsound.com/techniques/pro-tools-solo-modes)
- [AFL/PFL Solo — Production Expert](https://www.production-expert.com/home-page/2018/10/26/aflpfl-solo-in-pro-tools-ultimate-may-sound-dull-but-is-exactly-what-you-need-when-tracking-or-soloing-bus-auxes)
- [Pro Tools Automation Modes — ProToolsTraining](https://www.protoolstraining.com/blog-help/pro-tools-blog/tips-and-tricks/463-automation-modes-in-pro-tools)
- [Pro Tools Automation — Production Expert](https://www.production-expert.com/production-expert-1/pro-tools-automation-everything-you-need-to-know)
- [Pro Tools Metering Options — Sound On Sound](https://www.soundonsound.com/techniques/pro-tools-metering-options)
- [Pro Tools 9 Track Types — Production Expert](https://www.production-expert.com/production-expert-1/the-9-pro-tools-track-types-what-they-are-and-how-they-are-used)
- [Using VCA Masters — Sound On Sound](https://www.soundonsound.com/techniques/how-use-vca-groups)
- [Pro Tools Folder Tracks — Sound On Sound](https://www.soundonsound.com/techniques/pro-tools-folder-tracks)
- [Pro Tools Shortcuts Guide 2023.3](https://resources.avid.com/SupportFiles/PT/Pro_Tools_Shortcuts_2023.3.pdf)
- [Inserts & Sends — Emerson College](https://support.emerson.edu/hc/en-us/articles/21708955934875-Inserts-Sends)
- [Pro Tools Using Sends — Sound On Sound](https://www.soundonsound.com/techniques/pro-tools-using-sends)
- [Pro Tools Routing Audio — Sound On Sound](https://www.soundonsound.com/techniques/pro-tools-routing-audio)
- [Pro Tools Groups vs Folder Tracks — Sound On Sound](https://www.soundonsound.com/techniques/pro-tools-groups-vs-folder-tracks)
- [Mix Window EQ Curve — Production Expert](https://www.production-expert.com/home-page/2019/2/22/theres-a-reason-for-using-the-new-pro-tools-mix-window-eq-curve-in-that-no-one-is-talking-about-expert-tutorial)

---

# 23. IMPLEMENTATION PLAN — EXACT FILE OPERATIONS

## FFI Audit Summary (121+ Functions)

| Category | Count | Status |
|----------|-------|--------|
| Solo System (SIP/AFL/PFL) | 6 | ✅ EXISTS |
| VCA Faders | 14 | ✅ EXISTS |
| Groups (9 linkable params) | 10 | ✅ EXISTS |
| Folder Tracks | 4 | ✅ EXISTS |
| Metering (Peak/RMS/LUFS/TP/Psychoacoustic) | 25+ | ✅ EXISTS |
| Control Room (Monitor/Cue/Talkback) | 23 | ✅ EXISTS |
| Routing (Create/Delete/Send/Output) | 14 | ✅ EXISTS |
| Track Ops (Vol/Pan/Mute/Solo/Batch) | 13 | ✅ EXISTS |
| DSP Inserts | 12 | ✅ EXISTS |
| **Spill System** | 0 | ❌ NEEDS BUILD |
| **Automation Modes FFI** | 0 | ❌ NEEDS BUILD |
| **K-System/VU Ballistics FFI** | 0 | ❌ NEEDS BUILD |

**Conclusion:** 90% of engine work is DONE. This is primarily a UI refactor.

---

## Current File Inventory

### KEEP (reuse models/logic)

| File | LOC | Reuse |
|------|-----|-------|
| `providers/mixer_provider.dart` | 2232 | **100%** — SSoT for all mixer state, 55+ methods, 20+ FFI calls, undo, groups, VCA, reorder |
| `widgets/mixer/ultimate_mixer.dart` | 2307 | **Models 100%, Widget 30%** — ChannelType, SendData, InsertData, InputSection, UltimateMixerChannel are production-ready. Widget needs refactor |
| `widgets/mixer/vca_strip.dart` | 1463 | **Models 100%** — VcaData, VcaMemberTrack, VcaLinkMode. Widget: partial reuse |
| `widgets/mixer/control_room_panel.dart` | 684 | **100%** — Clean Provider pattern, 30Hz metering |
| `widgets/mixer/group_manager_panel.dart` | 676 | **100%** — CRUD, color presets |
| `widgets/mixer/plugin_selector.dart` | 628 | **100%** — DSP type selection popups |
| `widgets/mixer/mixer_undo_widget.dart` | 521 | **100%** — Undo/redo UI |
| `widgets/mixer/sidechain_routing_panel.dart` | 474 | **100%** — Sidechain config |
| `widgets/mixer/knob.dart` | 295 | **100%** — Reusable knob widget |
| `widgets/mixer/bus_color_picker.dart` | 231 | **100%** — Color picker |
| `models/layout_models.dart` | — | **100%** — ChannelStripData, InsertSlot, SendSlot, EQBand, LUFSData |

### REFACTOR (significant changes)

| File | LOC | Changes |
|------|-----|---------|
| `widgets/mixer/ultimate_mixer.dart` | 2307 | Strip UI rebuilt to Pro Tools anatomy. Models stay. Layout changes from current to vertical scroll strip + horizontal track scroll |
| `widgets/mixer/channel_strip.dart` | 1152 | Merge InsertSlot (missing-plugin state) and SendSlot (per-send pan) into canonical models. Rebuild UI to match spec Section 9 |
| `screens/engine_connected_layout.dart` | ~10000 | Add `AppViewMode` enum, `Cmd+=` toggle, wire MixerScreen, populate buses/auxes/vcas from provider |
| `widgets/mixer/mixer_panel.dart` | 256 | Simplify — becomes thin wrapper that passes through to UltimateMixer |
| `widgets/lower_zone/daw/mix/mini_mixer_view.dart` | 796 | Keep as compact Lower Zone mixer; sync with refactored models |

### DELETE (dead/duplicate code)

| File | LOC | Reason |
|------|-----|--------|
| `widgets/mixer/pro_mixer_strip.dart` | 1710 | Duplicate of UltimateMixer + channel_strip. Models already merged |

### NEW FILES

| File | Est. LOC | Purpose |
|------|----------|---------|
| `screens/mixer_screen.dart` | ~350 | Dedicated full-height mixer view (TopBar + Body + StatusBar) |
| `widgets/mixer/mixer_top_bar.dart` | ~300 | View toggles, track filter, section show/hide, metering mode |
| `widgets/mixer/mixer_status_bar.dart` | ~150 | Track count, DSP load %, latency display |
| `widgets/mixer/mixer_section_divider.dart` | ~80 | Section headers (Tracks, Buses, Aux, VCA, Master) |
| `widgets/mixer/io_selector_popup.dart` | ~400 | I/O assignment popup (input source, output bus) |
| `widgets/mixer/send_slot_widget.dart` | ~250 | Individual send display in strip (destination, level knob, pre/post, mute) |
| `widgets/mixer/automation_mode_badge.dart` | ~120 | Mode selector (Off, Read, Touch, Write, Latch, Touch/Latch, Trim) |
| `widgets/mixer/group_id_badge.dart` | ~80 | Group membership display with color dot |
| `widgets/mixer/eq_curve_thumbnail.dart` | ~200 | Mini EQ frequency response in strip |
| `widgets/mixer/delay_comp_display.dart` | ~80 | PDC samples/ms display |
| `controllers/mixer/mixer_view_controller.dart` | ~300 | View state (scroll, sections visible, strip width, spill) |
| `controllers/mixer/spill_controller.dart` | ~200 | Spill state for VCA/Folder tracks |
| `models/mixer_view_models.dart` | ~200 | View-specific models (MixerSection, StripWidthMode, ViewPreset) |

---

## Phase 1: Core Mixer Screen (P0) — ✅ COMPLETE (2026-02-20, commit `60700ded`)

### Dependency Order

```
1. models/mixer_view_models.dart        (no deps)
2. controllers/mixer/mixer_view_controller.dart  (depends on: 1)
3. widgets/mixer/mixer_section_divider.dart       (no deps)
4. widgets/mixer/mixer_status_bar.dart            (depends on: MixerProvider)
5. widgets/mixer/mixer_top_bar.dart               (depends on: 2)
6. screens/mixer_screen.dart                      (depends on: 2,3,4,5 + UltimateMixer)
7. screens/engine_connected_layout.dart           (MODIFY: add AppViewMode + Cmd+=)
8. widgets/mixer/ultimate_mixer.dart              (MODIFY: strip layout refactor)
```

### Step-by-Step

**Step 1.1: Models** — NEW `models/mixer_view_models.dart`
```
- enum StripWidthMode { narrow, regular }     // 56px vs 90px
- enum MixerSection { tracks, buses, auxes, vcas, master }
- class MixerViewPreset { name, visibleSections, stripWidth }
- class MixerViewState { scrollOffset, visibleSections, stripWidthMode, spillTarget }
```

**Step 1.2: View Controller** — NEW `controllers/mixer/mixer_view_controller.dart`
```
- MixerViewController extends ChangeNotifier
- Fields: scrollOffset, visibleSections, stripWidthMode, spillTargetId
- Methods: toggleSection(), setStripWidth(), setSpillTarget(), clearSpill()
- Persistence: SharedPreferences for section visibility + strip width
```

**Step 1.3: Section Divider** — NEW `widgets/mixer/mixer_section_divider.dart`
```
- Simple header bar: label + show/hide chevron + track count
- Callback: onToggle
- Colors match section type (track=blue, bus=green, aux=purple, vca=orange)
```

**Step 1.4: Status Bar** — NEW `widgets/mixer/mixer_status_bar.dart`
```
- Consumer<MixerProvider> for track count
- DSP load from NativeFFI.profilerGetCurrentLoad()
- Total latency from insertGetTotalLatency()
- Sample rate display
```

**Step 1.5: Top Bar** — NEW `widgets/mixer/mixer_top_bar.dart`
```
- Strip width toggle (N/R)
- Section show/hide buttons (Tracks, Buses, Aux, VCA)
- Track filter search field
- Metering mode dropdown (Peak, RMS, LUFS)
- "Edit" button → switch back to Edit view
```

**Step 1.6: Mixer Screen** — NEW `screens/mixer_screen.dart`
```
- Column: TopBar + Expanded(MixerBody) + StatusBar
- MixerBody = horizontal scroll of strips organized by section
- Master strip pinned to right edge (not in scroll)
- Virtualization: only render visible strips + 2 buffer
- Consumer<MixerProvider> + Consumer<MixerViewController>
```

**Step 1.7: AppViewMode** — MODIFY `screens/engine_connected_layout.dart`
```
- Add: enum AppViewMode { edit, mixer }
- Add: _currentViewMode state variable
- Add: RawKeyboardListener for Cmd+= / Ctrl+= toggle
- In build(): if (_currentViewMode == AppViewMode.mixer) return MixerScreen()
- CRITICAL: Both views share same providers (no re-initialization)
```

**Step 1.8: Strip Refactor** — MODIFY `widgets/mixer/ultimate_mixer.dart`
```
- Refactor strip layout to match spec Section 9 (top-to-bottom):
  1. Track Name + Color bar (top)
  2. I/O selectors (compact)
  3. Insert slots A-E
  4. Send slots A-E
  5. Automation mode badge
  6. Group ID
  7. Pan knob (or dual-pan)
  8. Meter (Peak/RMS, vertical)
  9. Fader (vertical, 200px+ travel)
  10. M/S/R buttons (bottom)
  11. Track number
- Keep: Cubase fader law (5-segment logarithmic, unity at 75%)
- Keep: All existing callbacks (onVolumeChange, onPanChange, etc.)
- Add: Strip width modes (56px narrow, 90px regular)
- Wire: buses, auxes, vcas from MixerProvider (remove const [])
```

### Phase 1 FFI Requirements

| Need | Exists? | Action |
|------|---------|--------|
| Track volume/pan/mute/solo | ✅ | Already wired in MixerProvider |
| Peak/RMS metering per track | ✅ | Already wired (SharedMeterBuffer) |
| Master volume/pan | ✅ | Already wired |
| Bus creation/routing | ✅ | Wire MixerProvider.buses to mixer |
| Track count | ✅ | MixerProvider.channels.length |
| DSP load | ✅ | profilerGetCurrentLoad() |
| **NO new FFI needed for Phase 1** | | |

### Phase 1 Verification

```
1. flutter analyze → 0 errors                                    ✅
2. Cmd+= toggles between Edit and Mixer views                   ✅
3. All channels visible with fader + meter + pan + M/S/R         ✅
4. Master strip pinned right                                      ✅
5. Horizontal scroll smooth at 60fps                              ✅
6. Section dividers show Tracks / Master                          ✅
7. Strip width toggle N/R works                                   ✅
8. Volume/Pan/Mute/Solo callbacks still work                      ✅
9. Metering animates at 30Hz                                      ✅
```

### Phase 1 Implementation Notes

**New Files Created (5):**

| File | LOC | Description |
|------|-----|-------------|
| `models/mixer_view_models.dart` | ~200 | StripWidthMode, MixerSection, AppViewMode enums; MixerViewPreset, SectionState models |
| `controllers/mixer/mixer_view_controller.dart` | ~300 | View state: scroll, sections, strip width, spill; SharedPreferences persistence |
| `widgets/mixer/mixer_top_bar.dart` | ~250 | Section toggles, strip width N/R, track filter, metering mode, "Edit" button |
| `widgets/mixer/mixer_status_bar.dart` | ~150 | Track count, DSP load, total latency, sample rate display |
| `screens/mixer_screen.dart` | ~400 | Full mixer screen: TopBar + scrollable strips + pinned master + StatusBar |

**Modified Files:**

| File | Changes |
|------|---------|
| `screens/engine_connected_layout.dart` | Added `AppViewMode` state, `Cmd+=` keyboard shortcut, conditional rendering of MixerScreen vs Edit view |
| `widgets/mixer/ultimate_mixer.dart` | Strip layout refactored to match spec Section 9 (top-to-bottom order); strip width modes (56px/90px); Cubase fader law preserved |

---

## Phase 2: I/O, Inserts, Sends (P1) — ✅ COMPLETE (2026-02-21, commit `aa84ed0d`)

### Dependency Order

```
1. widgets/mixer/io_selector_popup.dart           (depends on: MixerProvider routing)
2. widgets/mixer/send_slot_widget.dart             (depends on: SendData model)
3. widgets/mixer/automation_mode_badge.dart        (no deps)
4. widgets/mixer/group_id_badge.dart               (depends on: MixerProvider groups)
5. widgets/mixer/ultimate_mixer.dart               (MODIFY: integrate 1-4 into strip)
6. models: SendData                                (MODIFY: add pan field)
7. models: InsertData                              (MODIFY: add missing-plugin fields)
```

### Step-by-Step

**Step 2.1: I/O Selector** — NEW `widgets/mixer/io_selector_popup.dart`
```
- PopupMenuButton with available inputs (hardware inputs, buses, none)
- PopupMenuButton with available outputs (buses, master, hardware outs)
- Uses routing FFI: routing_get_all_channels(), routing_set_output()
- Visual: compact dropdown in strip, shows current route name
```

**Step 2.2: Send Slot Widget** — NEW `widgets/mixer/send_slot_widget.dart`
```
- Compact row: destination label + level knob + pre/post indicator + mute button
- Knob: 20px FabFilterKnob for send level
- Destination: PopupMenuButton with available buses
- Pre/Post: tiny toggle (P = pre, green; blank = post)
- FFI: engine_set_send_level(), engine_set_send_destination(), engine_set_send_pre_fader()
```

**Step 2.3: Automation Mode** — NEW `widgets/mixer/automation_mode_badge.dart`
```
- PopupMenuButton showing current mode
- Modes: Off, Read, Touch, Write, Latch, Touch/Latch, Trim
- Color coded: Off=grey, Read=green, Write=red, Touch=blue, Latch=yellow
- NOTE: No FFI for automation modes yet — UI-only state in Phase 2, FFI in Phase 4
```

**Step 2.4: Group ID Badge** — NEW `widgets/mixer/group_id_badge.dart`
```
- Small colored dot + group letter (a-z)
- Tooltip shows group name
- Click opens GroupManagerPanel
- Data from MixerProvider.getGroupForChannel(channelId)
```

**Step 2.5: Model Updates** — MODIFY `ultimate_mixer.dart` models
```
SendData:
  + pan: double (-1.0 to 1.0, default 0.0)        // Per-send pan
  + tapPoint: SendTapPoint (default: postFader)     // 5 positions

InsertData:
  + isInstalled: bool (default true)                // Plugin availability
  + hasStatePreserved: bool (default false)          // Saved plugin state
  + hasFreezeAudio: bool (default false)             // Freeze fallback exists
  + pdcSamples: int (default 0)                     // Latency compensation

enum SendTapPoint { preFader, postFader, preMute, postMute, postPan }
```

**Step 2.6: Strip Integration** — MODIFY `ultimate_mixer.dart`
```
- Add Insert slots A-E display (from DspChainProvider)
- Add Send slots A-E display (using SendSlotWidget)
- Add I/O selectors at top of strip
- Add Automation mode badge below sends
- Add Group ID badge
- Strip color bar at very top (channel type color)
- Track number at very bottom
```

### Phase 2 FFI Requirements

| Need | Exists? | Action |
|------|---------|--------|
| Send level/destination/pre-post | ✅ | engine_set_send_level/destination/pre_fader |
| Insert display (loaded processors) | ✅ | DspChainProvider already wired |
| Routing channels list | ✅ | routing_get_all_channels() |
| Set output routing | ✅ | routing_set_output() |
| Group membership query | ✅ | group_get_linked_tracks() |
| **NO new FFI needed for Phase 2** | | |

### Phase 2 Verification

```
1. flutter analyze → 0 errors                                    ✅
2. Insert slots A-E show loaded processors with bypass toggle    ✅
3. Send slots A-E show destination + level knob + pre/post       ✅
4. I/O selectors open popup with available routes                ✅
5. Automation mode badge changes color per mode                  ✅
6. Group ID badge shows colored dot when channel is in group     ✅
7. Strip color bar matches channel type                          ✅
8. Track number visible at bottom                                ✅
9. Narrow mode (56px) hides labels, shows icons only             ✅
```

### Phase 2 Implementation Notes

**New Files Created (4):**

| File | LOC | Description |
|------|-----|-------------|
| `widgets/mixer/io_selector_popup.dart` | ~240 | IoRoute model, IoRouteType enum, grouped popup menu, format badges (M/St/5.1/7.1) |
| `widgets/mixer/send_slot_widget.dart` | ~180 | Compact row: destination + level knob + pre/post + mute, dB conversion via dart:math |
| `widgets/mixer/automation_mode_badge.dart` | ~165 | AutomationMode enum (7 modes), color-coded PopupMenuButton |
| `widgets/mixer/group_id_badge.dart` | ~160 | GroupColors 26-color palette (a-z), multi-group dot display |

**Modified Files:**

| File | Changes |
|------|---------|
| `widgets/mixer/ultimate_mixer.dart` | Replaced 3 inline methods (AutomationBadge, GroupBadge, SendSection) with widget integrations; added `onOutputChange` callback to `_UltimateChannelStrip`; removed dead `_SendSlot` (~170 LOC) and `_MiniSendLevel` (~35 LOC) classes |

**Key Design Decisions:**
- `SendTapPoint` enum: `preFader, postFader, preMute, postMute, postPan` (5 positions)
- `AutomationMode`: UI-only state in Phase 2 — FFI wiring deferred to Phase 4
- `IoSelectorPopup`: Hardcoded route lists (placeholder for Phase 4 FFI)
- Send slots labeled A-J matching Pro Tools convention
- `_linearToDb()` uses proper `20.0 * math.log(linear) / math.ln10` formula

---

## Phase 3: Buses, Aux, VCA (P1)

### Dependency Order

```
1. controllers/mixer/spill_controller.dart         (depends on: MixerProvider)
2. widgets/mixer/ultimate_mixer.dart               (MODIFY: bus/aux/vca strip variants)
3. screens/engine_connected_layout.dart            (MODIFY: populate buses/auxes/vcas)
4. providers/mixer_provider.dart                   (MODIFY: populate buses/auxes from engine)
```

### Step-by-Step

**Step 3.1: Spill Controller** — NEW `controllers/mixer/spill_controller.dart`
```
- SpillController extends ChangeNotifier
- Fields: spillTargetId (String?), spilledChannelIds (Set<String>)
- Methods: spillVca(vcaId), spillFolder(folderId), unspill()
- Logic: When VCA spilled → show only member tracks
  When Folder spilled → show only child tracks
- Integration: MixerViewController reads spill state for filtering
```

**Step 3.2: Populate Buses/Auxes/VCAs** — MODIFY `engine_connected_layout.dart`
```
- Remove: buses: const [], auxes: const [], vcas: const []
- Add: buses from MixerProvider (query routing_get_channels_json for bus type)
- Add: auxes from MixerProvider (query routing_get_channels_json for aux type)
- Add: vcas from MixerProvider._vcas
- Each bus/aux becomes UltimateMixerChannel with appropriate ChannelType
```

**Step 3.3: Bus/Aux Strip Variant** — MODIFY `ultimate_mixer.dart`
```
- Bus strip: no input selector, no record arm, output selector only
- Aux strip: input from bus selector, output selector, no record arm
- VCA strip: no inserts, no sends, no pan, fader + mute/solo + spill button
- Master strip: POST-fader inserts (reverse order), no sends, no pan, no record
- Spill button on VCA: click → SpillController.spillVca(vcaId)
```

**Step 3.4: Section Show/Hide** — MODIFY `mixer_view_controller.dart`
```
- Wire toggleSection() to MixerTopBar buttons
- Sections collapse with animation (150ms)
- Section divider shows collapsed track count ("Buses (3)")
```

### Phase 3 FFI Requirements

| Need | Exists? | Action |
|------|---------|--------|
| VCA create/delete/assign | ✅ | vca_create/delete/add_track/remove_track |
| VCA level/mute/solo | ✅ | vca_set_level/mute/solo |
| VCA members query | ✅ | vca_get_members() |
| Folder create/add child | ✅ | folder_create/add_child |
| Bus volume/pan/mute/solo | ✅ | setBusVolume/Pan, mixerSetBusMute/Solo |
| **Spill logic** | ❌ | **Dart-only** — no engine FFI needed; spill is UI filtering |

### Phase 3 Verification

```
1. flutter analyze → 0 errors
2. Buses section appears with real buses (not empty)
3. Aux section appears with aux inputs
4. VCA strip has fader + M/S + spill button (no inserts/sends/pan)
5. Spill click on VCA → only member tracks visible
6. Click elsewhere or "Unspill" → all tracks return
7. Master strip: inserts are POST-fader (spec Section 3)
8. Section dividers can collapse/expand
9. Bus strip: no input selector, no record arm
```

---

## Phase 4: Advanced Features (P2)

### Dependency Order

```
1. Solo engine wiring (Dart → existing FFI)
2. widgets/mixer/eq_curve_thumbnail.dart           (NEW)
3. widgets/mixer/delay_comp_display.dart           (NEW)
4. Inserts F-J, Sends F-J expansion
5. View presets
6. All metering modes
```

### Step-by-Step

**Step 4.1: Solo Engine** — MODIFY `mixer_provider.dart`
```
- Wire control_room_set_solo_mode() for SIP/AFL/PFL switching
- Wire control_room_solo_channel() / unsolo_channel()
- Add solo safe per channel (UI flag, prevents unsolo when clearing)
- Listen Bus: control_room_set_monitor_source() for AFL/PFL output
- Top bar gets solo mode selector (SIP | AFL | PFL)
```

**Step 4.2: Solo Safe** — MODIFY `mixer_provider.dart` + `ultimate_mixer.dart`
```
- MixerChannel model: + soloSafe: bool
- UI: Alt+click solo button → toggle solo safe (orange indicator)
- Logic: When clearAllSolos() → skip channels with soloSafe=true
```

**Step 4.3: EQ Curve Thumbnail** — NEW `widgets/mixer/eq_curve_thumbnail.dart`
```
- CustomPainter, 80×30px mini frequency response
- Data from DspChainProvider.getChain(trackId) → EQ node parameters
- Render: straight line if no EQ, curve if EQ bands exist
- Click: opens full EQ editor (InternalProcessorEditorWindow)
```

**Step 4.4: Delay Comp Display** — NEW `widgets/mixer/delay_comp_display.dart`
```
- Shows total insert chain latency in samples and ms
- Data: insertGetTotalLatency(trackId)
- Format: "128 smp / 2.9ms"
- Yellow if >256, Red if >1024
```

**Step 4.5: Inserts/Sends F-J** — MODIFY `ultimate_mixer.dart`
```
- Toggle: A-E / F-J view (like Pro Tools)
- Total 10 insert slots, 10 send slots per channel
- SendData/InsertData arrays extended to length 10
- Insert slots 0-4 = A-E (pre-fader), 5-9 = F-J (post-fader)
- Send slots 0-4 = A-E, 5-9 = F-J
```

**Step 4.6: Group System UI** — MODIFY `group_manager_panel.dart`
```
- Wire group_create/delete/add_track/remove_track FFI
- Group attributes: link volume, pan, mute, solo, record, monitor, insert bypass, send level, automation
- Suspend group (temporarily disable linking)
- Group selection from strip (click group badge → popup)
```

**Step 4.7: Folder Track** — MODIFY `ultimate_mixer.dart`
```
- Folder strip with expand/collapse children
- Folder = Routing Folder (children sum into folder bus)
- Folder has own inserts/sends/fader
- Spill on folder → show children only
```

**Step 4.8: View Presets** — MODIFY `mixer_view_controller.dart`
```
- Save current view as preset (sections, strip width, scroll position)
- Load preset by name
- 5 built-in presets: All, Tracks Only, Buses+Master, Submix, Recording
- SharedPreferences persistence
```

**Step 4.9: Metering Modes** — NEW FFI + UI
```
- Need new FFI for VU and K-System ballistics
- VU: 300ms integration, -20 VU = 0 dBFS (or configurable)
- K-14: 14 dB headroom above reference
- K-20: 20 dB headroom above reference
- PPM: fast attack (5ms), slow decay (1.7s)
- TopBar dropdown: Peak, RMS, VU, K-14, K-20, PPM
```

### Phase 4 FFI Requirements

| Need | Exists? | Action |
|------|---------|--------|
| Solo modes (SIP/AFL/PFL) | ✅ | Wire control_room_set_solo_mode() |
| Solo per channel | ✅ | Wire control_room_solo_channel() |
| Monitor source for listen bus | ✅ | Wire control_room_set_monitor_source() |
| Group create/delete/link | ✅ | Wire group_create/delete/toggle_link |
| Folder create/add child | ✅ | Wire folder_create/add_child |
| EQ parameters for thumbnail | ✅ | Via DspChainProvider → insertGetParam() |
| Insert latency | ✅ | insertGetTotalLatency() |
| **VU/K-System ballistics** | ❌ | **NEW:** expose rf-dsp VU/K-System via FFI |
| **Automation modes** | ❌ | **NEW:** automation_set_mode(track_id, mode) |

### New Rust FFI Needed (Phase 4)

```rust
// crates/rf-engine/src/ffi.rs — NEW functions

// VU Metering
pub extern "C" fn metering_set_mode(track_id: u32, mode: u32) -> i32;
// mode: 0=Peak, 1=RMS, 2=VU, 3=K14, 4=K20, 5=PPM

pub extern "C" fn metering_get_vu(track_id: u32, out_left: *mut f64, out_right: *mut f64) -> i32;
pub extern "C" fn metering_get_k_system(track_id: u32, k_level: u32, out_left: *mut f64, out_right: *mut f64) -> i32;

// Automation Modes
pub extern "C" fn automation_set_mode(track_id: u64, mode: u8) -> i32;
// mode: 0=Off, 1=Read, 2=Touch, 3=Write, 4=Latch, 5=TouchLatch, 6=Trim
pub extern "C" fn automation_get_mode(track_id: u64) -> u8;
```

### Phase 4 Verification

```
1. flutter analyze → 0 errors
2. Solo mode selector in top bar switches SIP/AFL/PFL
3. AFL solo → audio routed to listen bus
4. Solo safe → channel not unsoloed when clear all
5. EQ curve thumbnail shows mini frequency response
6. PDC display shows latency in samples + ms
7. Insert/Send A-E ↔ F-J toggle works
8. Group create → members linked → fader move propagates
9. Group suspend temporarily stops linking
10. Folder collapse/expand works
11. Metering mode dropdown (Peak, RMS, VU, K-14, K-20)
12. View presets save/load
```

---

## Phase 5: Polish (P3)

### Step-by-Step

**Step 5.1: Global Undo** — Already exists in MixerProvider (WithUndo methods)
- Verify all new operations (group, VCA, folder) have undo
- Add undo for view state changes

**Step 5.2: Trim Automation** — MODIFY `automation_mode_badge.dart`
- Trim mode: offsets from existing automation data
- Requires automation_set_mode() FFI from Phase 4

**Step 5.3: Floating Send Windows** — NEW popup
- Double-click send slot → floating window with send details
- Shows: destination, level fader, pan knob, pre/post, mute
- Multiple windows can be open simultaneously

**Step 5.4: Per-Strip Context Menu** — MODIFY `ultimate_mixer.dart`
- Right-click on strip → context menu
- Options: Rename, Color, Duplicate, Delete, Solo Safe, Make Inactive, Add to Group, Assign to VCA

**Step 5.5: Keyboard Shortcuts** — Wire to RawKeyboardListener
```
Cmd+=     Toggle Edit/Mixer
Cmd+S     Solo selected
Cmd+M     Mute selected
Ctrl+Alt+Click  Solo Safe toggle
Shift+Click Solo  Clear all others, solo this
Cmd+Shift+N   Narrow all strips
```

### Phase 5 Verification

```
1. flutter analyze → 0 errors
2. Ctrl+Z undoes any mixer operation
3. Right-click context menu on every strip type
4. All keyboard shortcuts from spec Section 18 work
5. Floating send window opens/closes
6. Full run-through: create track → route → insert EQ → send to bus → solo → record
```

---

## Model Consolidation Plan

### Before Implementation — Merge Duplicates

| Duplicate | Canonical Location | Action |
|-----------|-------------------|--------|
| `ChannelType` in channel_strip.dart | `ultimate_mixer.dart` | DELETE from channel_strip.dart, import from ultimate_mixer |
| `InsertSlotData` in channel_strip.dart | `layout_models.dart:InsertSlot` | DELETE from channel_strip, use InsertSlot |
| `SendSlotData` in channel_strip.dart | `layout_models.dart:SendSlot` | DELETE from channel_strip, use SendSlot |
| `ProInsertSlot` in pro_mixer_strip.dart | `layout_models.dart:InsertSlot` | DELETE entire pro_mixer_strip.dart |
| `ProSendSlot` in pro_mixer_strip.dart | `layout_models.dart:SendSlot` | DELETE entire pro_mixer_strip.dart |

### Canonical Models (Post-Merge)

**`ultimate_mixer.dart` exports:**
- `ChannelType` enum (audio, instrument, bus, aux, vca, master, folder)
- `UltimateMixerChannel` (full channel state)
- `SendData` (+ pan, tapPoint fields)
- `InsertData` (+ isInstalled, hasStatePreserved, hasFreezeAudio, pdcSamples)
- `InputSection`
- `SendTapPoint` enum

**`vca_strip.dart` exports:**
- `VcaData`, `VcaMemberTrack`, `VcaLinkMode`

**`layout_models.dart` exports:**
- `ChannelStripData`, `InsertSlot`, `SendSlot`, `EQBand`, `LUFSData`

**`mixer_view_models.dart` exports (NEW):**
- `StripWidthMode`, `MixerSection`, `MixerViewPreset`, `MixerViewState`

---

## Critical Path Summary

```
Phase 1 (P0):  8 steps, ~1560 LOC new, 0 new FFI
Phase 2 (P1):  6 steps, ~850 LOC new, 0 new FFI
Phase 3 (P1):  4 steps, ~200 LOC new, 0 new FFI (spill = Dart-only)
Phase 4 (P2):  9 steps, ~280 LOC new, 5 new FFI functions
Phase 5 (P3):  5 steps, ~300 LOC new, 0 new FFI

Total NEW code:  ~3190 LOC
Total NEW FFI:   5 functions (metering modes + automation)
Files to DELETE: 1 (pro_mixer_strip.dart, 1710 LOC)
Files to CREATE: 13
Files to MODIFY: 5
```

**Order of execution: Phase 1 → 2 → 3 → 4 → 5 (strictly sequential)**

Each phase is independently shippable — mixer works after each phase, just with fewer features.
