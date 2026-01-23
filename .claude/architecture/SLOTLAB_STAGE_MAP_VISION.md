# SlotLab Stage Map Vision — V3

**Date:** 2026-01-23
**Status:** V6 Implementation Complete
**Version:** 3.3

> **🚀 V6 Implementation Status (2026-01-23): COMPLETE**
> - ✅ Phase 1: Tab Reorganization (15 → 7 + menu)
> - ✅ Phase 2-5: SymbolStripWidget, EventsPanelWidget, Plus Menu
> - ✅ Phase 6: Data Models (slot_lab_models.dart, SlotLabProjectProvider)
> - ✅ Phase 7: Layout Integration (3-panel: Symbol Strip | Center | Events Panel)
> - ✅ Phase 8: Provider Registration
> - ✅ Phase 9: FFI Integration (Symbol→EventRegistry, Music→ALE profile)
> - See: `.claude/tasks/SLOTLAB_V6_IMPLEMENTATION.md`

> **📌 Implementation:** Core drop zone functionality documented in [SLOTLAB_DROP_ZONE_SPEC.md](./SLOTLAB_DROP_ZONE_SPEC.md). This document describes the Unified Slot Preview + Symbol Strip concept.

---

## VIZIJA V3: Unified Slot Preview + Symbol Strip

### Ključni Koncept

**Slot Preview služi dve svrhe:**
- **PLAY mode:** Pravi slot sa animiranim rilovima, dugmićima koji rade
- **EDIT mode:** Isti elementi postaju drop zone-ovi za audio

**Symbol Strip:** Poseban panel za symbol-specifične audio evente.

---

## 1. LAYOUT PREGLED

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ HEADER                                           [▶ PLAY] [✏️ EDIT]            │
├─────────────────────────────────────────────────────────────────────────────────┤
│ [🎰 Base] [⭐ Free Spins] [🔒 Hold&Win] [🎁 Bonus] [💎 Jackpot]   ← State Tabs │
├──────────────┬──────────────────────────────────────────────────────────────────┤
│              │                                                                  │
│   SYMBOL     │                    SLOT PREVIEW                                  │
│   STRIP      │    ┌───────────────────────────────────┐                        │
│              │    │                                   │                        │
│  ┌────────┐  │    │   ┌───┬───┬───┬───┬───┐          │                        │
│  │🃏 WILD │  │    │   │ A │ 👑│ 💎│ ⭐│ K │          │                        │
│  │ ├─Land │  │    │   ├───┼───┼───┼───┼───┤          │                        │
│  │ ├─Win  │  │    │   │ 🃏│ A │ K │ 👑│ 💎│          │  PLAY: Animira        │
│  │ └─Expand│ │    │   ├───┼───┼───┼───┼───┤          │  EDIT: Drop targets   │
│  ├────────┤  │    │   │ K │ ⭐│ 🃏│ A │ 👑│          │                        │
│  │⭐ SCATR│  │    │   └───┴───┴───┴───┴───┘          │                        │
│  │ ├─1x   │  │    │                                   │                        │
│  │ ├─2x   │  │    │      [ SPIN ]  $1,234.56          │                        │
│  │ ├─3x   │  │    │                                   │                        │
│  │ └─Trig │  │    └───────────────────────────────────┘                        │
│  ├────────┤  │                                                                  │
│  │👑 HIGH1│  │    TRANSITIONS: [Base→FS] [FS→Base] [Base→H&W] [H&W→Base] ...   │
│  │...     │  │                                                                  │
│  └────────┘  ├──────────────────────────────────────────────────────────────────┤
│              │                         TIMELINE                                 │
│  [+ Add]     │    [SPIN_START: spin.wav] [REEL_STOP_0: stop1.wav] ...          │
│              │                                                                  │
└──────────────┴──────────────────────────────────────────────────────────────────┘
```

---

## 2. PLAY/EDIT MODE TOGGLE

### 2.1 Mode Definicije

| Mode | Slot Preview | Symbol Strip | Transitions | Timeline |
|------|--------------|--------------|-------------|----------|
| **PLAY** | Animira, spin radi | Disabled (dimmed) | Disabled | Read-only |
| **EDIT** | Statičan, drop targets | Active, drop targets | Active, drop targets | Editable |

### 2.2 PLAY Mode Behavior

```
- Rilovi se vrte na klik SPIN
- Win amount se prikazuje
- Dugmići (AUTO, MAX BET) rade
- Prelazi između state-ova su animirani
- Audio se pušta po EventRegistry
```

### 2.3 EDIT Mode Behavior

```
- Rilovi su statični
- Svaki element ima dashed border (drop target)
- Audio Browser se prikazuje
- Hover na element = highlight
- Drop audio = kreira event + dodaje u timeline
- Symbol Strip je aktivan
```

---

## 3. STATE TABS (5 Game States)

### 3.1 State Definicije

| Tab | State | Screen Content | Unique Elements |
|-----|-------|----------------|-----------------|
| **🎰 Base Game** | `base` | 5 reels + spin + win | Standard gameplay |
| **⭐ Free Spins** | `freespins` | Reels + FS counter + multiplier | Spin counter, total win |
| **🔒 Hold & Win** | `holdwin` | 15-cell grid + respin counter | Locked symbols, jackpot cells |
| **🎁 Bonus** | `bonus` | Pick game (8 items) | Prize reveals |
| **💎 Jackpot** | `jackpot` | 4-tier display + celebration | Mini/Minor/Major/Grand |

### 3.2 State-Specific Drop Targets

**Base Game:**
```
- SPIN_START, SPIN_END
- REEL_STOP_0..4, REEL_SPIN_LOOP
- WIN_PRESENT, WIN_AMOUNT_SHOW
- AUTOPLAY_START, MAX_BET_SELECT
```

**Free Spins:**
```
- FS_SPIN_START, FS_SPIN_END
- FS_REEL_STOP_0..4
- FS_MULTIPLIER_CHANGE, FS_MULTIPLIER_MAX
- FS_TOTAL_WIN_UPDATE
- FS_SPIN_COUNT_UPDATE
- FS_RETRIGGER
```

**Hold & Win:**
```
- HW_RESPIN
- HW_SYMBOL_LOCK, HW_SYMBOL_LOCK_VALUE
- HW_CELL_EMPTY, HW_NEW_SYMBOL
- HW_RESPIN_COUNT_UPDATE
- HW_GRID_FULL, HW_COLLECT
```

**Bonus:**
```
- BONUS_PICK_REVEAL
- BONUS_PRIZE_WIN
- BONUS_PICK_WRONG
- BONUS_PICK_END
- BONUS_COLLECT
```

**Jackpot:**
```
- JACKPOT_MINI, JACKPOT_MINOR
- JACKPOT_MAJOR, JACKPOT_GRAND
- JACKPOT_CELEBRATION
- JACKPOT_COLLECT
```

### 3.3 Transition Zones

Transition zones su uvek vidljive na dnu slot preview-a:

```
TRANSITIONS:
┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐
│ Base → FS   │ FS → Base   │ Base → H&W  │ H&W → Base  │ Base → Bonus │
├──────────────┼──────────────┼──────────────┼──────────────┼──────────────┤
│ Bonus → Base│ Any → JP    │ JP → Base   │ FS → H&W    │ H&W → Bonus  │
└──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘
```

**Transition Stages:**
- `TRANS_BASE_TO_FS` — Entering free spins
- `TRANS_FS_TO_BASE` — Exiting free spins
- `TRANS_BASE_TO_HW` — Entering hold & win
- `TRANS_HW_TO_BASE` — Exiting hold & win
- `TRANS_BASE_TO_BONUS` — Entering bonus
- `TRANS_BONUS_TO_BASE` — Exiting bonus
- `TRANS_ANY_TO_JP` — Any state to jackpot
- `TRANS_JP_TO_BASE` — Jackpot collect back to base

---

## 4. SYMBOL STRIP (NOVO U V3)

### 4.1 Filozofija

**Simboli su TIPOVI, ne POZICIJE.**

Kada Wild padne na Reel 3, Row 2 — zvuk je `WILD_LAND`, ne `position_3_2`.
Pozicija samo određuje PAN (auto-kalkulisan).

### 4.2 Symbol Strip Layout

```
┌──────────────────────────────────┐
│ SYMBOLS                  [+ Add] │
├──────────────────────────────────┤
│                                  │
│ ▼ 🃏 WILD               [SPECIAL]│
│   ├─ Land         [○]           │
│   ├─ Win Line     [○]           │
│   ├─ Expand       [○]           │
│   ├─ Stack        [○]           │
│   └─ ☑ Per-Reel Pan (auto)      │
│                                  │
│ ▼ ⭐ SCATTER            [SPECIAL]│
│   ├─ [1x] [2x] [3x] [4x] [5x]   │  ← Quantity variants
│   ├─ Trigger      [●]           │
│   └─ ☑ Per-Reel Pan (auto)      │
│                                  │
│ ▶ 👑 HIGH PAY 1          [HIGH] │
│ ▶ 💎 HIGH PAY 2          [HIGH] │
│ ▶ 🅰️ LOW PAY (A)          [LOW] │
│ ▶ 🅺 LOW PAY (K)          [LOW] │
│ ▶ 🆀 LOW PAY (Q)          [LOW] │
│ ▶ 🅹 LOW PAY (J)          [LOW] │
│ ▶ 🔟 LOW PAY (10)         [LOW] │
│                                  │
│ ▶ 💰 BONUS SYMBOL      [SPECIAL]│
│ ▶ 🪙 COIN SYMBOL       [SPECIAL]│
│ ▶ ❓ MYSTERY SYMBOL    [SPECIAL]│
│                                  │
└──────────────────────────────────┘

[○] = Empty (no audio)
[●] = Has audio assigned
```

### 4.3 Symbol Contexts

Svaki simbol ima kontekste za audio assignment:

| Symbol Type | Contexts |
|-------------|----------|
| **Wild** | Land, Win Line, Expand, Stack, Multiply, Walk, Stick |
| **Scatter** | Land (1-5x), Trigger, Near Miss |
| **Bonus** | Land, Highlight, Collect |
| **High Pay** | Land, Win Line |
| **Low Pay** | Land, Win Line |
| **Coin** | Land, Value Reveal, Collect |
| **Mystery** | Reveal, Transform |

### 4.4 Quantity Variants (Scatter)

Scatter ima poseban tretman — različiti zvukovi za različit broj scatter-a:

```
SCATTER QUANTITIES:
┌─────┬─────┬─────┬─────┬─────┐
│ 1x  │ 2x  │ 3x  │ 4x  │ 5x  │
│[○]  │[○]  │[●]  │[●]  │[●]  │
└─────┴─────┴─────┴─────┴─────┘
  │      │      │      │      │
  │      │      │      │      └── SCATTER_LAND_5 (ultra trigger)
  │      │      │      └────────── SCATTER_LAND_4 (mega trigger)
  │      │      └───────────────── SCATTER_LAND_3 (trigger)
  │      └──────────────────────── SCATTER_LAND_2 (anticipation)
  └─────────────────────────────── SCATTER_LAND_1 (single land)
```

### 4.5 Per-Reel Pan (Auto-Calculation)

Kada je `☑ Per-Reel Pan` uključen:

| Reel Position | Pan Value | Stereo Position |
|---------------|-----------|-----------------|
| Reel 0 | -0.8 | Far Left |
| Reel 1 | -0.4 | Left |
| Reel 2 | 0.0 | Center |
| Reel 3 | +0.4 | Right |
| Reel 4 | +0.8 | Far Right |

**Implementacija:**
```dart
double calculatePanFromReel(int reelIndex, int totalReels) {
  if (totalReels <= 1) return 0.0;
  final normalized = reelIndex / (totalReels - 1); // 0.0 to 1.0
  return (normalized * 2.0 - 1.0) * 0.8; // -0.8 to +0.8
}
```

### 4.6 Symbol Registry

Korisnik može definisati custom simbole:

```dart
class SymbolDefinition {
  final String id;           // 'wild', 'scatter', 'high1', etc.
  final String name;         // Human-readable
  final String emoji;        // Display icon
  final SymbolType type;     // special, high, low
  final List<SymbolContext> contexts;  // Available contexts
}

enum SymbolType { special, high, low, bonus }

class SymbolContext {
  final String id;           // 'land', 'win', 'expand', etc.
  final String label;        // Display name
  final String? audioPath;   // Assigned audio (null = empty)
}
```

---

## 5. DROP FLOW (V3 Updated)

### 5.1 Drop on Slot Element

```
1. User drags audio from Audio Browser
2. Hovers over SPIN button (in EDIT mode)
3. SPIN button highlights with dashed border
4. User drops audio
5. System:
   a. Creates event named "Spin Start"
   b. Assigns stage: SPIN_START
   c. Assigns bus: sfx
   d. Adds to timeline
   e. Syncs to MiddlewareProvider
   f. Syncs to EventRegistry
```

### 5.2 Drop on Symbol Context

```
1. User drags audio from Audio Browser
2. Hovers over Wild → Land context (in EDIT mode)
3. Context row highlights
4. User drops audio
5. System:
   a. Creates event named "Wild Land"
   b. Assigns stage: WILD_LAND
   c. Assigns bus: symbols
   d. If Per-Reel Pan enabled: creates 5 variants with auto-pan
   e. Adds to timeline
   f. Syncs to MiddlewareProvider
```

### 5.3 Drop on Scatter Quantity

```
1. User drags audio to Scatter → 3x
2. System creates event:
   - Name: "Scatter Land 3"
   - Stage: SCATTER_LAND_3
   - Bus: symbols
   - Priority: 70 (escalating with quantity)
```

### 5.4 Drop on Transition Zone

```
1. User drags audio to "Base → FS" transition
2. System creates event:
   - Name: "Enter Free Spins"
   - Stage: TRANS_BASE_TO_FS
   - Bus: transitions
   - Duration: auto-detected from audio
```

---

## 6. TIMELINE INTEGRATION

### 6.1 State-Filtered Timeline

Timeline prikazuje SAMO evente relevantne za trenutni state tab:

| State Tab | Shows Events With Stages |
|-----------|--------------------------|
| Base Game | `SPIN_*`, `REEL_*`, `WIN_*`, `SYMBOL_*` |
| Free Spins | `FS_*` |
| Hold & Win | `HW_*`, `HOLD_*` |
| Bonus | `BONUS_*`, `PICK_*` |
| Jackpot | `JACKPOT_*`, `JP_*` |

### 6.2 Timeline Event Display

```
┌───────────────────────────────────────────────────────────────────────┐
│ TIMELINE — Base Game                                        [Filter ▼]│
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  [SPIN]           [REEL]           [REEL]           [WIN]            │
│  SPIN_START       REEL_STOP_0      REEL_STOP_1      WIN_PRESENT      │
│  spin_whoosh.wav  stop_thud.wav    stop_thud.wav    win_jingle.wav   │
│                                                                       │
│  [SYMBOL]         [SYMBOL]         [TRANSITION]                       │
│  WILD_LAND        SCATTER_LAND_3   TRANS_BASE_TO_FS                  │
│  wild_bling.wav   scatter_hit.wav  fs_enter.wav                      │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 7. AUDIO BROWSER INTEGRATION

### 7.1 Audio Browser Visibility

- PLAY mode: Hidden
- EDIT mode: Visible (floating panel, right side)

### 7.2 Audio Browser Content

```
┌─────────────────────────────┐
│ 🎵 AUDIO FILES              │
├─────────────────────────────┤
│ 🔍 [Search...]              │
├─────────────────────────────┤
│ 📁 Spin Sounds              │
│   🔊 spin_whoosh.wav        │
│   🔊 spin_turbo.wav         │
├─────────────────────────────┤
│ 📁 Reel Sounds              │
│   🔊 reel_stop_thud.wav     │
│   🔊 reel_slam_heavy.wav    │
├─────────────────────────────┤
│ 📁 Symbol Sounds            │
│   🔊 wild_land_bling.wav    │
│   🔊 scatter_hit.wav        │
├─────────────────────────────┤
│ 📁 Win Sounds               │
│   🔊 win_small.wav          │
│   🔊 win_big_fanfare.wav    │
└─────────────────────────────┘
```

---

## 8. IMPLEMENTATION CHECKLIST (V3)

### Phase 1: Core UI Structure
- [ ] PLAY/EDIT mode toggle
- [ ] State tabs (5 states)
- [ ] Slot preview component per state
- [ ] Symbol Strip component

### Phase 2: Symbol Strip
- [ ] Symbol Registry (define symbols)
- [ ] Symbol contexts (Land, Win, Expand, etc.)
- [ ] Quantity variants (Scatter 1-5x)
- [ ] Per-Reel Pan toggle
- [ ] Expand/collapse per symbol

### Phase 3: Drop System
- [ ] Drop on slot elements
- [ ] Drop on symbol contexts
- [ ] Drop on quantity variants
- [ ] Drop on transition zones
- [ ] Multi-audio drop (layers)

### Phase 4: State Management
- [ ] State-specific screens
- [ ] State-filtered timeline
- [ ] Transition zone events
- [ ] State→Stage mapping

### Phase 5: Integration
- [ ] MiddlewareProvider sync
- [ ] EventRegistry sync
- [ ] Audio playback preview
- [ ] Undo/Redo support

### Phase 6: Polish
- [ ] Keyboard shortcuts
- [ ] Symbol import from GDD
- [ ] Bulk audio assignment
- [ ] Export symbol mappings

---

## 9. MOCKUP FILES

| File | Version | Description | Status |
|------|---------|-------------|--------|
| `slotlab_tab_timeline_mockup.html` | V1 | Basic tab timeline concept | ✅ Done |
| `slotlab_tab_timeline_v2.html` | V2 | Timeline top + Stage Map | ✅ Done |
| `slotlab_unified_v3.html` | V3 | PLAY/EDIT + State tabs + Transitions | ✅ Done |
| `slotlab_unified_v4.html` | V4 | Symbol Strip + Slot Preview | ✅ Done |
| `slotlab_unified_v5.html` | V5 | Music Layers + ALE Lower Zone | ✅ Done |
| `slotlab_unified_v6.html` | V6 | **Complete Layout: 3 Panels + 7 Tabs** | ✅ Done |

---

## 10. MUSIC LAYER SYSTEM (ALE Integration)

### 10.1 Filozofija: Hybrid A + Lower Zone

**Problem:** Muzika zahteva i DROP targets (kao simboli) i kompleksnu logiku (rules, signals).

**Rešenje:**
- **Symbol Strip** → MUSIC sekcija sa L1-L5 drop targets
- **Lower Zone** → ALE Editor za rules, signals, transitions

### 10.2 Music Section u Symbol Strip

```
SYMBOL STRIP
├── 🃏 WILD
│   ├─ Land    [○]
│   ├─ Win     [○]
│   └─ Expand  [○]
├── ⭐ SCATTER
│   └─ ...
├── 👑 HIGH PAY 1
│   └─ ...
├── ─────────────────
│
├── 🎵 MUSIC LAYERS        ◀── Nova sekcija
│   │
│   ├── ▼ BASE_GAME
│   │   ├─ L1 Ambient   [○]   ← Drop target
│   │   ├─ L2 Main      [●]   ← Has audio
│   │   ├─ L3 Energy    [○]
│   │   ├─ L4 Drive     [○]
│   │   └─ L5 Climax    [○]
│   │
│   ├── ▶ FREE_SPINS (collapsed)
│   │   ├─ L1 ... L5
│   │
│   ├── ▶ HOLD_WIN (collapsed)
│   │   ├─ L1 ... L5
│   │
│   ├── ▶ BIG_WIN (collapsed)
│   │   ├─ L1 ... L5
│   │
│   └── ▶ BONUS (collapsed)
│       ├─ L1 ... L5
│
└── [+ Add Context]
```

### 10.3 ALE Editor u Lower Zone

Kada korisnik klikne na MUSIC sekciju, Lower Zone prikazuje ALE Editor:

```
┌────────────────────────────────────────────────────────────────────────────┐
│ LOWER ZONE — ALE MUSIC EDITOR                                              │
├────────────────────────────────────────────────────────────────────────────┤
│ [Rules] [Signals] [Transitions] [Stability] [Preview]                      │
├────────────────────────────────────────────────────────────────────────────┤
│                                                                            │
│  RULES for BASE_GAME:                                   [+ Add Rule]       │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │ IF  winXbet > 20        THEN  step_up         [Edit] [Delete]       │ │
│  │ IF  momentum > 0.8      THEN  set_level(L5)   [Edit] [Delete]       │ │
│  │ IF  consecutiveWins > 3 THEN  step_up         [Edit] [Delete]       │ │
│  │ IF  idle > 10s          THEN  step_down       [Edit] [Delete]       │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                            │
│  SIGNALS MONITOR:                                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │ momentum:    ████████░░░░ 0.78    winXbet:     ██░░░░░░░░░░ 2.5     │ │
│  │ winTier:     ███░░░░░░░░░ 3       consecutiveWins: ████░░░░░░░░ 4   │ │
│  │ idle:        ░░░░░░░░░░░░ 0.0s    featureProgress: ░░░░░░░░░░░░ 0%  │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                            │
│  CURRENT STATE:  Context: BASE_GAME  │  Level: L3  │  Target: L4 (↑)      │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 10.4 Layer Tabs u Lower Zone

| Tab | Sadržaj |
|-----|---------|
| **Rules** | Lista pravila (IF condition THEN action) |
| **Signals** | Real-time signal monitor + test sliders |
| **Transitions** | Sync mode (beat/bar/phrase), fade curves |
| **Stability** | Cooldown, hysteresis, inertia, hold, decay |
| **Preview** | Audio player, layer visualization, test controls |

### 10.5 Drop Flow za Muziku

```
1. User scrolluje Symbol Strip, vidi MUSIC sekciju
2. Expand-uje BASE_GAME
3. Vidi L1-L5 slots (empty ili filled)
4. Prevuče audio fajl iz Audio Browser-a
5. Drop-uje na L2 slot
6. System:
   a. Creates music layer entry
   b. Associates audio with BASE_GAME.L2
   c. Updates ALE provider
   d. Lower Zone refresh (if visible)
```

### 10.6 Layer Behavior

| Layer | Emotional State | Typical Audio |
|-------|-----------------|---------------|
| **L1** | Calm, Ambient | Pad, subtle texture |
| **L2** | Normal, Main | Main loop, bass |
| **L3** | Elevated, Energy | Percussion, overlay |
| **L4** | High, Drive | Full drums, bass drive |
| **L5** | Maximum, Climax | Fanfare, celebration |

### 10.7 Context Transitions

Kada se menja context (Base → Free Spins), muzika:
1. Fade out current context layers
2. Crossfade to new context L1 (ili set by rule)
3. Rules u novom kontekstu preuzimaju kontrolu

```
BASE_GAME.L3 ──(Scatter Trigger)──▶ FREE_SPINS.L1
                                         │
                                         ▼
                                   (Rules evaluate)
                                         │
                                         ▼
                                   FREE_SPINS.L3
```

### 10.8 UX Benefits

| Benefit | Explanation |
|---------|-------------|
| **Unified Workflow** | Simboli i muzika u istom panelu |
| **Consistent Gesture** | Drop audio = assign (za sve) |
| **No Tab Switching** | Scroll, ne navigate |
| **Progressive Disclosure** | Lower Zone za advanced |
| **Industry Standard** | Wwise/FMOD pattern |

---

## 11. DYNAMIC ARCHITECTURE (Data-Driven)

### 11.1 Princip: Nema Hardcoded Podataka

Sve u SlotLab UI-u se dinamički popunjava iz registrija. Mockupi prikazuju EXAMPLE data — prava implementacija koristi `forEach(registry)`.

### 11.2 Registry System

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SLOTLAB PROJECT                                    │
│                                                                              │
│  ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐            │
│  │ SymbolRegistry  │   │ ContextRegistry │   │ SignalRegistry  │            │
│  │                 │   │                 │   │                 │            │
│  │ [User defines]  │   │ [User defines]  │   │ [Built-in +     │            │
│  │ symbols +       │   │ game states +   │   │  Custom]        │            │
│  │ contexts        │   │ music contexts  │   │                 │            │
│  └────────┬────────┘   └────────┬────────┘   └────────┬────────┘            │
│           │                     │                     │                      │
│           ▼                     ▼                     ▼                      │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     UI POPULATES DYNAMICALLY                          │   │
│  │                                                                       │   │
│  │  Symbol Strip:        State Tabs:           Lower Zone:               │   │
│  │  forEach(symbols)     forEach(contexts)     forEach(signals)          │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 11.3 Šta je Dinamičko

| Komponenta | Izvor | Primer |
|------------|-------|--------|
| **Symbols** | SymbolRegistry | `[{id: 'pharaoh', type: 'wild', contexts: ['land','expand']}]` |
| **State Tabs** | ContextRegistry | `['BASE', 'PYRAMID_FS', 'TOMB_BONUS']` |
| **Music Contexts** | ContextRegistry | Isti kao State Tabs |
| **Layers (L1-L5)** | LayerConfig | `{count: 5, labels: ['Ambient','Main','Energy','Drive','Climax']}` |
| **Signals** | SignalRegistry | `['winXbet', 'momentum', 'custom.jackpotMeter']` |
| **Rules** | RuleRegistry | User-created per context |
| **Transitions** | TransitionRegistry | User-defined context pairs |

### 11.4 Data Models

```dart
/// Symbol definition (user-created or GDD import)
class SymbolDefinition {
  final String id;              // 'pharaoh', 'scarab', 'ankh'
  final String name;            // 'Pharaoh', 'Scarab', 'Ankh'
  final String emoji;           // '🦅', '🪲', '☥'
  final SymbolType type;        // wild, scatter, high, low, bonus
  final List<String> contexts;  // ['land', 'win', 'expand', 'stick']
}

/// Context definition (game state / music context)
class ContextDefinition {
  final String id;              // 'BASE_GAME', 'PYRAMID_FS'
  final String displayName;     // 'Base Game', 'Pyramid Free Spins'
  final String icon;            // '🎰', '🏛️'
  final ContextType type;       // base, freeSpins, holdWin, bonus, bigWin
}

/// Layer configuration
class LayerConfig {
  final int count;              // 5 (default)
  final List<String> labels;    // ['Ambient', 'Main', 'Energy', 'Drive', 'Climax']

  factory LayerConfig.default5() => LayerConfig(
    count: 5,
    labels: ['Ambient', 'Main', 'Energy', 'Drive', 'Climax'],
  );
}

/// Signal definition
class SignalDefinition {
  final String id;              // 'winXbet', 'momentum', 'custom.jackpotMeter'
  final String displayName;     // 'Win × Bet', 'Momentum'
  final SignalType type;        // builtIn, custom
  final double min;             // 0.0
  final double max;             // 1.0 or Infinity
  final NormalizationMode norm; // linear, sigmoid, asymptotic
}
```

### 11.5 Project Container

```dart
class SlotLabProject {
  final String name;
  final SymbolRegistry symbols;
  final ContextRegistry contexts;
  final LayerConfig layerConfig;
  final SignalRegistry signals;
  final Map<String, List<Rule>> rulesPerContext;
  final Map<String, Map<int, String>> musicAssignments; // context → layer → audioPath
  final Map<String, String> transitionAudio;            // 'BASE→FS' → audioPath

  /// Load from saved project JSON
  factory SlotLabProject.fromJson(Map<String, dynamic> json) { ... }

  /// Start with empty project
  factory SlotLabProject.empty(String name) => SlotLabProject(
    name: name,
    symbols: SymbolRegistry.empty(),
    contexts: ContextRegistry.withDefaults(['BASE_GAME']),
    layerConfig: LayerConfig.default5(),
    signals: SignalRegistry.builtIn(),
    rulesPerContext: {},
    musicAssignments: {},
    transitionAudio: {},
  );

  /// Import from GDD
  factory SlotLabProject.fromGDD(GameDesignDocument gdd) { ... }
}
```

### 11.6 UI Rendering (Dynamic)

**Symbol Strip:**
```dart
Widget buildSymbolStrip(SlotLabProject project) {
  return ListView(children: [
    // Symbols section - from registry
    SectionHeader('SYMBOLS'),
    ...project.symbols.all.map((symbol) => SymbolItem(
      symbol: symbol,
      onContextDrop: (ctx, audio) => _assignSymbolAudio(symbol, ctx, audio),
    )),

    // Divider
    StripDivider(),

    // Music section - from context registry
    SectionHeader('MUSIC LAYERS'),
    ...project.contexts.all.map((context) => MusicContextItem(
      context: context,
      layerConfig: project.layerConfig,
      assignments: project.musicAssignments[context.id] ?? {},
      onLayerDrop: (layer, audio) => _assignMusicLayer(context, layer, audio),
    )),

    // Add context button
    AddContextButton(onAdd: _addNewContext),
  ]);
}
```

**State Tabs:**
```dart
Widget buildStateTabs(SlotLabProject project) {
  return Row(children: [
    ...project.contexts.all.map((ctx) => StateTab(
      label: ctx.displayName,
      icon: ctx.icon,
      isActive: ctx.id == _currentContext,
      onTap: () => _switchContext(ctx.id),
    )),
    AddStateButton(onAdd: _addNewContext),
  ]);
}
```

**Signals Monitor:**
```dart
Widget buildSignalsMonitor(SlotLabProject project) {
  return GridView(children: [
    ...project.signals.all.map((signal) => SignalMonitorTile(
      signal: signal,
      currentValue: _signalValues[signal.id] ?? 0.0,
      onTestValueChange: (v) => _setTestSignalValue(signal.id, v),
    )),
  ]);
}
```

### 11.7 GDD Import → Auto-Populate

Kada korisnik importuje GDD (Game Design Document):

```json
{
  "name": "Egyptian Riches",
  "grid": { "reels": 5, "rows": 3 },
  "symbols": [
    { "id": "pharaoh", "name": "Pharaoh", "type": "wild" },
    { "id": "scarab", "name": "Scarab", "type": "scatter" },
    { "id": "ankh", "name": "Ankh", "type": "high" },
    { "id": "eye", "name": "Eye of Ra", "type": "high" },
    { "id": "A", "name": "Ace", "type": "low" }
  ],
  "features": [
    { "id": "fs", "name": "Pyramid Free Spins", "type": "freeSpins" },
    { "id": "bonus", "name": "Tomb Bonus", "type": "pickBonus" }
  ]
}
```

**System auto-creates:**

```
SymbolRegistry:
├── pharaoh (Wild) → contexts: [land, win, expand, stick]
├── scarab (Scatter) → contexts: [land_1, land_2, land_3, land_4, land_5, trigger]
├── ankh (High) → contexts: [land, win]
├── eye (High) → contexts: [land, win]
└── A (Low) → contexts: [land, win]

ContextRegistry:
├── BASE_GAME (auto)
├── PYRAMID_FREE_SPINS (from fs feature)
└── TOMB_BONUS (from bonus feature)

TransitionRegistry:
├── BASE → PYRAMID_FREE_SPINS
├── PYRAMID_FREE_SPINS → BASE
├── BASE → TOMB_BONUS
└── TOMB_BONUS → BASE
```

### 11.8 Empty Project vs GDD Import

| Scenario | Šta se dešava |
|----------|---------------|
| **New Empty Project** | BASE_GAME context, no symbols, built-in signals, empty rules |
| **GDD Import** | Auto-populated symbols, contexts, transitions from GDD |
| **Manual Add** | User clicks [+ Add Symbol] or [+ Add Context] |

### 11.9 Persistence

```dart
/// Save project to JSON
Future<void> saveProject(SlotLabProject project) async {
  final json = project.toJson();
  await File('${project.name}.slotlab').writeAsString(jsonEncode(json));
}

/// Load project from JSON
Future<SlotLabProject> loadProject(String path) async {
  final json = jsonDecode(await File(path).readAsString());
  return SlotLabProject.fromJson(json);
}
```

### 11.10 Validation

```dart
class ProjectValidator {
  List<ValidationIssue> validate(SlotLabProject project) {
    final issues = <ValidationIssue>[];

    // Check: At least one context
    if (project.contexts.isEmpty) {
      issues.add(ValidationIssue.error('No contexts defined'));
    }

    // Check: Music layers assigned
    for (final ctx in project.contexts.all) {
      final layers = project.musicAssignments[ctx.id] ?? {};
      if (layers.isEmpty) {
        issues.add(ValidationIssue.warning('No music for ${ctx.displayName}'));
      }
    }

    // Check: Transitions have audio
    for (final trans in project.getRequiredTransitions()) {
      if (!project.transitionAudio.containsKey(trans)) {
        issues.add(ValidationIssue.warning('No audio for transition $trans'));
      }
    }

    return issues;
  }
}
```

---

## 12. LOWER ZONE REORGANIZATION (V6)

### 12.1 Problem: Previše Tabova

Trenutna implementacija ima **15 tabova** u Lower Zone:
```
timeline, busHierarchy, profiler, rtpc, resources, auxSends,
eventLog, gameModel, scenarios, gddImport, commandBuilder,
eventList, meters, autoSpatial, stageIngest
```

**Problem:** Cognitive overload — korisnik gubi vreme tražeći pravi tab.

### 12.2 Rešenje: 7 Core Tabova + [+] Menu

```
┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬─────┐
│ Timeline │  Events  │  Mixer   │Music/ALE │  Meters  │  Debug   │  Engine  │ [+] │
└──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴─────┘
```

### 12.3 Tab Definicije

| # | Tab | Sadrži | Keyboard | Primarne Uloge |
|---|-----|--------|----------|----------------|
| 1 | **Timeline** | Audio regions, waveforms, layer positioning | T | Audio Designer, UX |
| 2 | **Events** | Event list, RTPC bindings, stages | E | Audio Designer, Middleware |
| 3 | **Mixer** | Bus hierarchy + Aux sends | M | Audio Designer, DSP |
| 4 | **Music/ALE** | Music layers rules, signals, transitions | A | Audio Designer |
| 5 | **Meters** | LUFS, peak, correlation | - | Audio Designer, DSP |
| 6 | **Debug** | Event log, trace history, latency | L | Engine Dev, QA |
| 7 | **Engine** | Profiler, resources, stage ingest | - | Engine Dev |
| + | **[+] Menu** | Game Config, AutoSpatial, Scenarios | - | Game Designer |

### 12.4 Grupisanje Starih Tabova

| Novi Tab | Stari Tabovi |
|----------|--------------|
| **Mixer** | busHierarchy + auxSends |
| **Debug** | eventLog |
| **Engine** | profiler + resources + stageIngest |
| **[+] → Game Config** | gameModel + gddImport |
| **[+] → Scenarios** | scenarios |
| **[+] → AutoSpatial** | autoSpatial |
| **[+] → Command Builder** | commandBuilder |

### 12.5 Desni Panel Struktura

```
┌─────────────────────────────┐
│ ▼ EVENTS FOLDER             │
│   📁 Spin Sounds (3)        │
│   📁 Win Sounds (8)         │
│   📁 Feature Sounds (12)    │
├─────────────────────────────┤
│ ▼ SELECTED EVENT            │
│   Name: [Spin Start     ]   │
│   Stage: SPIN_START         │
│   LAYERS:                   │
│   🔊 spin_whoosh.wav        │
│   + Add Layer               │
├─────────────────────────────┤
│ ▼ AUDIO BROWSER             │
│   📁 /Audio/Slot/Spins/     │
│   🔊 spin_01.wav            │
│   🔊 spin_02.wav            │
└─────────────────────────────┘
```

### 12.6 Kompletni Layout (V6)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ HEADER: [Logo] Project Name           [▶ PLAY] [✏️ EDIT]        [⚙️] [?] [X]            │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ STATE TABS: [🎰 Base] [⭐ Free Spins] [🔒 Hold&Win] [🎁 Bonus] [💎 Jackpot] [+]        │
├──────────────┬─────────────────────────────────────────────────────────────┬────────────┤
│              │                                                             │            │
│  SYMBOL      │                      SLOT PREVIEW                           │   EVENTS   │
│  STRIP       │                                                             │   PANEL    │
│              │   ┌─────────────────────────────────────────┐               │            │
│  SYMBOLS     │   │  [Reels 5×3]                            │               │  📁 Folders│
│  🦅 Wild     │   │                                         │               │            │
│  🪲 Scatter  │   │  [SPIN]    Balance                      │               │  Selected  │
│  ☥ Ankh     │   └─────────────────────────────────────────┘               │  Event     │
│              │                                                             │            │
│  ───────────│   TRANSITIONS: [Base→FS] [FS→Base] ...                     │  Audio     │
│              │                                                             │  Browser   │
│  MUSIC       │                                                             │            │
│  🎵 BASE     │                                                             │            │
│    L1-L5     │                                                             │            │
│  🎵 FS       │                                                             │            │
│              │                                                             │            │
├──────────────┴─────────────────────────────────────────────────────────────┴────────────┤
│ LOWER ZONE                                                                              │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│ [Timeline] [Events] [Mixer] [Music/ALE] [Meters] [Debug] [Engine] [+]                   │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  Timeline tracks with audio regions...                                                  │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐   │
│  │ SPIN_START   [████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]                         │   │
│  │ REEL_STOP_0  [░░░░░░████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░]                         │   │
│  │ WIN_PRESENT  [░░░░░░░░░░░░░░░░░░████████████░░░░░░░░░░]                         │   │
│  └──────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 12.7 Analiza po Ulogama

Detaljna analiza nalazi se u:
`.claude/architecture/SLOTLAB_LOWER_ZONE_ANALYSIS.md`

---

## 13. REFERENCE

- **Stage Catalog:** `.claude/domains/slot-audio-events-master.md` (490 stages)
- **Drop Zone Spec:** `.claude/architecture/SLOTLAB_DROP_ZONE_SPEC.md`
- **Slot Lab System:** `.claude/architecture/SLOT_LAB_SYSTEM.md`
- **Adaptive Layer Engine:** `.claude/architecture/ADAPTIVE_LAYER_ENGINE.md`
- **GDD Import Wizard:** `.claude/docs/P3_CRITICAL_WEAKNESSES_2026_01_23.md` (P3.4)
- **Lower Zone Analysis:** `.claude/architecture/SLOTLAB_LOWER_ZONE_ANALYSIS.md`

---

*Document updated: 2026-01-23*
*Version: 3.3 — V6 Implementation Complete*

---

## 14. V6 IMPLEMENTATION COMPLETE (2026-01-23)

### Final Component Summary

| Component | File | LOC | Status |
|-----------|------|-----|--------|
| **SymbolStripWidget** | `widgets/slot_lab/symbol_strip_widget.dart` | ~488 | ✅ |
| **EventsPanelWidget** | `widgets/slot_lab/events_panel_widget.dart` | ~500 | ✅ |
| **SlotLabProjectProvider** | `providers/slot_lab_project_provider.dart` | ~447 | ✅ |
| **slot_lab_models.dart** | `models/slot_lab_models.dart` | ~524 | ✅ |
| **Layout Integration** | `screens/slot_lab_screen.dart` | ~300 added | ✅ |

### Key Integrations Working

1. **Symbol Audio → EventRegistry**
   - Drop audio on symbol context → creates AudioEvent → instant playback

2. **Music Layer → ALE Profile**
   - `generateAleProfile()` creates ALE-compatible JSON
   - `getContextAudioPaths()` returns layer→path mapping

3. **GetIt Service Locator**
   - SlotLabProjectProvider registered at Layer 5.5
   - Available via `sl<SlotLabProjectProvider>()`

### Architecture Diagram (Final)

```
┌────────────────────────────────────────────────────────────────────────┐
│                        SlotLab V6 Architecture                          │
├────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────┐                                                   │
│  │ SlotLabProject   │─────────────────────────────────────────────┐    │
│  │    Provider      │                                              │    │
│  └────────┬─────────┘                                              │    │
│           │                                                        │    │
│           ▼                                                        ▼    │
│  ┌──────────────────┐    ┌──────────────────┐    ┌────────────────┐    │
│  │  SymbolStrip     │    │   slot_lab_      │    │  EventsPanel   │    │
│  │    Widget        │    │     screen       │    │    Widget      │    │
│  │                  │    │                  │    │                │    │
│  │ • Symbols        │    │ • 3-panel layout │    │ • Folder tree  │    │
│  │ • Music Layers   │    │ • State tabs     │    │ • Event editor │    │
│  │ • Drop targets   │    │ • Lower zone     │    │ • Audio browser│    │
│  └────────┬─────────┘    └──────────────────┘    └────────┬───────┘    │
│           │                                               │             │
│           └───────────────────┬───────────────────────────┘             │
│                               │                                         │
│                               ▼                                         │
│                    ┌──────────────────────┐                             │
│                    │   EventRegistry      │                             │
│                    │                      │                             │
│                    │ • Stage → Event map  │                             │
│                    │ • Instant playback   │                             │
│                    │ • Voice pooling      │                             │
│                    └──────────────────────┘                             │
│                                                                         │
└────────────────────────────────────────────────────────────────────────┘
```

### What's Next

- [ ] Runtime testing with real audio files
- [ ] GDD import wizard for auto-symbol creation
- [ ] Dead code cleanup (_buildLeftPanel, _buildRightPanel)
- [ ] Responsive layout testing
