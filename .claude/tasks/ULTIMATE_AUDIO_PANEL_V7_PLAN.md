# Ultimate Audio Panel V7 — Detaljan Plan

> ⚠️ **DEPRECATED:** V7 je zamenjen sa **V8 — Game Flow Organization**.
> Pogledaj: `.claude/architecture/ULTIMATE_AUDIO_PANEL_V8_SPEC.md`

**Datum:** 2026-01-25
**Status:** DEPRECATED → See V8
**Verzija:** 2.0 (UI + Spins + Reels kombinovano)

---

## VIZIJA

Eliminacija Edit Mode-a. Korisnik samo prevuče audio u levi panel i odmah radi sa slot mašinom.

---

## KLJUČNE FUNKCIONALNOSTI

### 1. FOLDER DROP → AUTO-DISTRIBUTE

Korisnik:
1. Selektuje 10 audio fajlova u browser-u
2. Prevuče ceo folder na grupu "Reel Stops"
3. Sistem automatski prepoznaje:
   - `reel_stop_1.wav` → REEL_STOP_0
   - `reel_stop_2.wav` → REEL_STOP_1
   - `reel_stop_3.wav` → REEL_STOP_2
   - `reel_stop_4.wav` → REEL_STOP_3
   - `reel_stop_5.wav` → REEL_STOP_4
   - `spin_start.wav` → (unmatched - belongs to different group within same section)
4. Sistem prikazuje rezultat: "5 matched, 1 unmatched"
5. Audio odmah radi u slot mašini

### 2. SINGLE FILE DROP

Korisnik može i pojedinačno prevući audio na specifičan slot.

### 3. INSTANT PLAYBACK

Nema potrebe za Edit Mode → audio odmah radi nakon drop-a.

---

## PANEL STRUKTURA (V7 — 5 SEKCIJA)

```
┌─────────────────────────────────────────────────────────────────┐
│ 🎵 Audio Panel                                    [24 assigned] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ 📁 UI & SPINS & REELS                                  [▼] [12] │
│ ├─ 🔄 Spin Controls                          [DROP ZONE] [2/7]  │
│ │   ├─ Spin Press      [spin_click.wav             ] [×]       │
│ │   ├─ Spin End        [Drop audio...              ]           │
│ │   ├─ Stop Press      [Drop audio...              ]           │
│ │   ├─ AutoSpin On     [Drop audio...              ]           │
│ │   ├─ AutoSpin Off    [Drop audio...              ]           │
│ │   ├─ Turbo On        [turbo_on.wav               ] [×]       │
│ │   └─ Turbo Off       [Drop audio...              ]           │
│ ├─ 🛑 Reel Stops                             [DROP ZONE] [5/6]  │
│ │   ├─ Generic Stop    [Drop audio...              ]           │
│ │   ├─ Reel 1 Stop     [reel_stop_1.wav            ] [×]       │
│ │   ├─ Reel 2 Stop     [reel_stop_2.wav            ] [×]       │
│ │   ├─ Reel 3 Stop     [reel_stop_3.wav            ] [×]       │
│ │   ├─ Reel 4 Stop     [reel_stop_4.wav            ] [×]       │
│ │   └─ Reel 5 Stop     [reel_stop_5.wav            ] [×]       │
│ ├─ 🔃 Reel Spin                              [DROP ZONE] [0/4]  │
│ │   ├─ Spin Loop       [Drop audio...              ]           │
│ │   ├─ Spinning        [Drop audio...              ]           │
│ │   ├─ Anticipation Start [Drop audio...           ]           │
│ │   └─ Anticipation End   [Drop audio...           ]           │
│ ├─ 💰 Betting                                [DROP ZONE] [0/5]  │
│ │   ├─ Max Bet         [Drop audio...              ]           │
│ │   ├─ Bet Up          [Drop audio...              ]           │
│ │   └─ ...                                                     │
│ └─ 📋 Menu & Info                            [DROP ZONE] [1/8]  │
│     ├─ Menu Open       [menu_open.wav              ] [×]       │
│     └─ ...                                                     │
│                                                                 │
│ 📁 SYMBOLS                                             [▼] [6]  │
│ ├─ ✨ Special Symbols                        [DROP ZONE] [2/6]  │
│ │   ├─ Wild Land       [wild_land.wav              ] [×]       │
│ │   ├─ Wild Win        [wild_win.wav               ] [×]       │
│ │   ├─ Scatter Land    [Drop audio...              ]           │
│ │   ├─ Scatter Win     [Drop audio...              ]           │
│ │   ├─ Bonus Land      [Drop audio...              ]           │
│ │   └─ Bonus Win       [Drop audio...              ]           │
│ ├─ 💎 High Pay                               [DROP ZONE] [0/8]  │
│ │   ├─ HP1 Land        [Drop audio...              ]           │
│ │   └─ ... (HP1-HP4 × Land/Win)                                │
│ └─ ♠️ Low Pay                                [DROP ZONE] [0/12] │
│     ├─ LP1 Land        [Drop audio...              ]           │
│     └─ ... (LP1-LP6 × Land/Win)                                │
│                                                                 │
│ 📁 WINS                                                [▼] [4]  │
│ ├─ 🎖️ Win Tiers                              [DROP ZONE] [3/6]  │
│ │   ├─ Small Win       [win_small.wav              ] [×]       │
│ │   ├─ Big Win         [win_big.wav                ] [×]       │
│ │   ├─ Super Win       [Drop audio...              ]           │
│ │   ├─ Mega Win        [win_mega.wav               ] [×]       │
│ │   ├─ Epic Win        [Drop audio...              ]           │
│ │   └─ Ultra Win       [Drop audio...              ]           │
│ ├─ 🎉 Big Win (≥20x)                         [DROP ZONE] [0/2]  │
│ │   ├─ BIG_WIN_LOOP    [Drop audio...              ]           │
│ │   └─ BIG_WIN_COINS   [Drop audio...              ]           │
│ ├─ 📊 Win Lines                              [DROP ZONE] [0/4]  │
│ ├─ 🔢 Rollup / Counter                       [DROP ZONE] [1/5]  │
│ └─ 💎 Jackpots                               [DROP ZONE] [0/6]  │
│                                                                 │
│ 📁 FEATURES                                            [▼] [0]  │
│ ├─ 🎁 Free Spins                             [DROP ZONE] [0/6]  │
│ ├─ 🎲 Bonus Game                             [DROP ZONE] [0/5]  │
│ ├─ 💧 Cascade / Tumble                       [DROP ZONE] [0/4]  │
│ ├─ 🔒 Hold & Win                             [DROP ZONE] [0/6]  │
│ ├─ ✖️ Multiplier                             [DROP ZONE] [0/2]  │
│ └─ 🃏 Gamble                                 [DROP ZONE] [0/4]  │
│                                                                 │
│ 📁 MUSIC                                               [▼] [2]  │
│ ├─ 🎹 Base Game                              [DROP ZONE] [2/5]  │
│ │   ├─ Base Music      [base_music.wav             ] [×]       │
│ │   ├─ Intro           [intro.wav                  ] [×]       │
│ │   ├─ Layer 1         [Drop audio...              ]           │
│ │   ├─ Layer 2         [Drop audio...              ]           │
│ │   └─ Layer 3         [Drop audio...              ]           │
│ └─ 🔇 Attract / Idle                         [DROP ZONE] [0/2]  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## SEKCIJE I GRUPE — DETALJNA LISTA (V7)

### SECTION 1: UI & SPINS & REELS (🎰) — Blue #4A9EFF

**KOMBINOVANA SEKCIJA** — Sve kontrole spin-a, reel-ova i UI elementa na jednom mestu.

| Grupa | Ikonica | Slotovi |
|-------|---------|---------|
| **Spin Controls** | 🔄 | Spin Press, Spin End, Stop Press, AutoSpin On, AutoSpin Off, Turbo On, Turbo Off |
| **Reel Stops** | 🛑 | Generic Stop, Reel 1-5 Stop (6 total) |
| **Reel Spin** | 🔃 | Spin Loop, Spinning, Anticipation Start, Anticipation End |
| **Betting** | 💰 | Max Bet, Bet Up, Bet Down, Line Up, Line Down |
| **Menu & Info** | 📋 | Menu Open, Menu Close, Paytable Open, Paytable Close, Settings Open, History Open, Button Press, Button Hover |

**Stage Pattern:**
- `SPIN_START`, `SPIN_END`, `UI_STOP_PRESS`
- `AUTOPLAY_START`, `AUTOPLAY_STOP`
- `UI_TURBO_ON`, `UI_TURBO_OFF`
- `REEL_STOP` (generic), `REEL_STOP_0` ... `REEL_STOP_4` (per-reel)
- `REEL_SPIN`, `REEL_SPINNING`
- `ANTICIPATION_ON`, `ANTICIPATION_OFF`
- `UI_BET_MAX`, `UI_BET_UP`, `UI_BET_DOWN`
- `MENU_OPEN`, `MENU_CLOSE`
- `UI_PAYTABLE_OPEN`, `UI_PAYTABLE_CLOSE`
- `UI_BUTTON_PRESS`, `UI_BUTTON_HOVER`

**Total slots in section:** 30

---

### SECTION 2: SYMBOLS (🎰) — Purple #9370DB

| Grupa | Ikonica | Slotovi |
|-------|---------|---------|
| **Special Symbols** | ✨ | Wild Land, Wild Win, Scatter Land, Scatter Win, Bonus Land, Bonus Win, Multiplier Land, Multiplier Win |
| **High Pay** | 💎 | HP1 Land, HP1 Win, HP2 Land, HP2 Win, HP3 Land, HP3 Win, HP4 Land, HP4 Win |
| **Low Pay** | ♠️ | LP1-LP6 × (Land, Win) = 12 slotova |

**Stage Pattern:**
- Land: `SYMBOL_LAND_{SYMBOL_ID}` → npr. `SYMBOL_LAND_HP1`
- Win: `WIN_SYMBOL_HIGHLIGHT_{SYMBOL_ID}` → npr. `WIN_SYMBOL_HIGHLIGHT_HP1`

---

### SECTION 3: WINS (🏆) — Gold #FFD700

| Grupa | Ikonica | Slotovi |
|-------|---------|---------|
| **Win Tiers** | 🎖️ | Small, Big, Super, Mega, Epic, Ultra (6 total) |
| **Big Win (≥20x)** | 🎉 | BIG_WIN_LOOP, BIG_WIN_COINS (2 total) |
| **Win Lines** | 📊 | Line Show, Line Hide, Symbol Highlight, Win Evaluate |
| **Rollup / Counter** | 🔢 | Rollup Start, Rollup Tick, Rollup End, Coin Burst, Coin Drop |
| **Jackpots** | 💎 | JP Trigger, JP Mini, JP Minor, JP Major, JP Grand, JP Award |

**Stage Pattern:**
- `WIN_PRESENT_SMALL`, `WIN_PRESENT_BIG`, ... `WIN_PRESENT_ULTRA`
- `BIG_WIN_LOOP` (≥20x, looping music, ducks base), `BIG_WIN_COINS` (SFX)
- `WIN_LINE_SHOW`, `WIN_LINE_HIDE`
- `WIN_SYMBOL_HIGHLIGHT`, `WIN_EVAL`
- `ROLLUP_START`, `ROLLUP_TICK`, `ROLLUP_END`
- `COIN_BURST`, `COIN_DROP`
- `JACKPOT_TRIGGER`, `JACKPOT_MINI`, `JACKPOT_MINOR`, `JACKPOT_MAJOR`, `JACKPOT_GRAND`, `JACKPOT_AWARD`

---

### SECTION 4: FEATURES (⭐) — Green #40FF90

| Grupa | Ikonica | Slotovi |
|-------|---------|---------|
| **Free Spins** | 🎁 | FS Trigger, FS Start, FS Spin, FS End, FS Retrigger, FS Music |
| **Bonus Game** | 🎲 | Bonus Trigger, Bonus Enter, Bonus Step, Bonus Exit, Bonus Music |
| **Cascade / Tumble** | 💧 | Cascade Start, Cascade Step, Cascade Pop, Cascade End |
| **Hold & Win** | 🔒 | Hold Trigger, Hold Start, Hold Spin, Hold Lock, Hold End, Hold Music |
| **Multiplier** | ✖️ | Multi Increase, Multi Apply |
| **Gamble** | 🃏 | Gamble Enter, Gamble Win, Gamble Lose, Gamble Exit |

**Stage Pattern:**
- `FREESPIN_TRIGGER`, `FREESPIN_START`, `FREESPIN_SPIN`, `FREESPIN_END`, `FREESPIN_RETRIGGER`, `FREESPIN_MUSIC`
- `BONUS_TRIGGER`, `BONUS_ENTER`, `BONUS_STEP`, `BONUS_EXIT`, `BONUS_MUSIC`
- `CASCADE_START`, `CASCADE_STEP`, `CASCADE_POP`, `CASCADE_END`
- `HOLD_TRIGGER`, `HOLD_START`, `HOLD_SPIN`, `HOLD_LOCK`, `HOLD_END`, `HOLD_MUSIC`
- `MULTIPLIER_INCREASE`, `MULTIPLIER_APPLY`
- `GAMBLE_ENTER`, `GAMBLE_WIN`, `GAMBLE_LOSE`, `GAMBLE_EXIT`

---

### SECTION 5: MUSIC (🎵) — Cyan #40C8FF

| Grupa | Ikonica | Slotovi |
|-------|---------|---------|
| **Base Game** | 🎹 | Base Music, Intro, Layer 1, Layer 2, Layer 3 |
| **Free Spins Music** | 🎁 | (generated from contexts) |
| **Bonus Music** | 🎲 | (generated from contexts) |
| **Hold & Win Music** | 🔒 | (generated from contexts) |
| **Attract / Idle** | 🔇 | Attract Loop, Game Start |

**Stage Pattern:**
- `MUSIC_BASE`, `MUSIC_INTRO`
- `MUSIC_LAYER_1`, `MUSIC_LAYER_2`, `MUSIC_LAYER_3`
- `MUSIC_{CONTEXT}_L1` ... `MUSIC_{CONTEXT}_L5`
- `ATTRACT_LOOP`, `GAME_START`

---

## AUTO-DISTRIBUTION ALGORITHM

### Matching Engine (StageGroupService)

1. **Normalizacija fajlnema:**
   ```
   "Reel_Stop-01.wav" → "reelstop01"
   ```

2. **Keyword matching:**
   ```
   "reelstop01" contains:
   - "reel" ✓
   - "stop" ✓
   - "01" → number 1 → index offset detection
   ```

3. **Intent detection:**
   - `spin` + `button/press/click` → SPIN_START
   - `spin` + `loop/reel` → REEL_SPIN
   - `stop` + number → REEL_STOP_N

4. **Index convention detection:**
   - Files with 1-5 numbers → 1-indexed, subtract 1
   - Files with 0-4 numbers → 0-indexed, keep as-is

5. **Confidence scoring:**
   - 3+ keywords → high confidence (0.6+)
   - 2 keywords → medium (0.4-0.6)
   - 1 keyword → low (0.2-0.4)
   - 0 keywords → no match

---

## TODO — IMPLEMENTACIJA

### FAZA 1: Core Widget (DONE ✅)
- [x] Kreirati `ultimate_audio_panel.dart`
- [x] Implementirati 5 sekcija (UI+Spins+Reels kombinovano)
- [x] Implementirati grupe unutar sekcija
- [x] Implementirati pojedinačne slotove
- [x] Implementirati GROUP-level drop zone
- [x] Implementirati AUTO-DISTRIBUTE logiku

### FAZA 2: Integracija sa SlotLab Screen
- [ ] Zameniti `SymbolStripWidget` sa `UltimateAudioPanel`
- [ ] Povezati `audioAssignments` sa MiddlewareProvider
- [ ] Povezati `onAudioAssign` → kreiraj event u EventRegistry
- [ ] Povezati `onAudioClear` → obriši event iz EventRegistry
- [ ] Testirati pojedinačni drop
- [ ] Testirati folder drop (multi-select)

### FAZA 3: EventRegistry Integration
- [ ] Kreirati helper za stage → AudioEvent konverziju
- [ ] Auto-kreiranje eventa pri drop-u
- [ ] Auto-playback bez Edit Mode
- [ ] Sinhronizacija sa MiddlewareProvider.compositeEvents

### FAZA 4: Persistence
- [ ] Čuvanje audioAssignments u SlotLabProjectProvider
- [ ] Učitavanje pri mount-u
- [ ] JSON serialization

### FAZA 5: Polish
- [ ] Animacija pri hover-u na GROUP
- [ ] Sound preview pri hover-u na slot
- [ ] Keyboard shortcuts (Ctrl+Z undo)
- [ ] Context menu (Clear Group, Clear Section)

### FAZA 6: Edit Mode Deprecation
- [ ] Označi Edit Mode kao "Legacy"
- [ ] Dodaj migraciju: stari eventi → nova struktura
- [ ] Opciono: potpuno ukloni Edit Mode

---

## DATOTEKE

| Fajl | Status | Opis |
|------|--------|------|
| `ultimate_audio_panel.dart` | ✅ DONE | Glavni widget (5 sekcija) |
| `slot_lab_screen.dart` | 🔄 TODO | Zameni SymbolStripWidget |
| `slot_lab_project_provider.dart` | 🔄 TODO | Dodaj audioAssignments storage |
| `event_registry.dart` | 🔄 TODO | Helper za auto-event kreiranje |
| `symbol_strip_widget.dart` | ⚠️ LEGACY | Mark as deprecated |

---

## TESTIRANJE

### Test Case 1: Single File Drop
1. Prevuci `spin_start.wav` na "Spin Press" slot
2. Očekivano: Slot prikazuje "spin_start.wav", event kreiran u registry

### Test Case 2: Folder Drop on Group
1. Selektuj 5 fajlova: `reel_stop_1.wav` ... `reel_stop_5.wav`
2. Prevuci na "Reel Stops" grupu
3. Očekivano:
   - Popup: "5 matched, 0 unmatched"
   - Svi slotovi popunjeni
   - Eventi kreirani

### Test Case 3: Mixed Folder Drop
1. Selektuj 7 fajlova: 5× reel stops + `win_big.wav` + `random_noise.wav`
2. Prevuci na "Reel Stops" grupu
3. Očekivano:
   - Popup: "5 matched, 2 unmatched"
   - `win_big.wav` → suggestion: "WIN_PRESENT_BIG (different group)"
   - `random_noise.wav` → no suggestion

### Test Case 4: Instant Playback
1. Drop audio na SPIN_START slot
2. Klikni Spin dugme na slot mašini
3. Očekivano: Audio svira odmah, bez Edit Mode

---

## SEKCIJA SUMMARY

| # | Sekcija | Boja | Grupe | Total Slots |
|---|---------|------|-------|-------------|
| 1 | UI & SPINS & REELS | #4A9EFF | 5 | 30 |
| 2 | SYMBOLS | #9370DB | 3 | Dynamic (based on symbols) |
| 3 | WINS | #FFD700 | 5 | 23 (includes Big Win group) |
| 4 | FEATURES | #40FF90 | 6 | 27 |
| 5 | MUSIC | #40C8FF | 2+ | 7+ (based on contexts) |

---

*Autor: Claude (Principal Engineer)*
*Verzija: 2.0*
*Ažurirano: 2026-01-25*
