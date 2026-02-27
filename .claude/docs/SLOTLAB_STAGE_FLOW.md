## 🎰 SLOTLAB STAGE FLOW (2026-01-24) ✅

### Kompletan Stage Flow

Redosled stage-ova generisan u `crates/rf-slot-lab/src/spin.rs`:

```
SPIN_START
    ↓
REEL_SPIN_LOOP (jedan loop za sve reel-ove)
    ↓
[ANTICIPATION_ON] (opciono, na reel-ove 1+ kad 2+ scattera — NIKAD na reel 0)
    ↓
[ANTICIPATION_TENSION_R{1-4}_L{1-4}] (per-reel tension escalation, počinje od reel 1)
    ↓
REEL_STOP_0 → REEL_STOP_1 → ... → REEL_STOP_N (per-reel sa stereo pan)
    ↓
[ANTICIPATION_OFF] (ako je bio uključen)
    ↓
EVALUATE_WINS
    ↓
[WIN_PRESENT] (ako ima win)
    ↓
[WIN_LINE_SHOW × N] (za svaku win liniju, max 3)
    ↓
[BIG_WIN_TIER] (ako win_ratio >= threshold)
    ↓
[ROLLUP_START → ROLLUP_TICK × N → ROLLUP_END]
    ↓
[CASCADE_STAGES] (ako ima cascade)
    ↓
[FEATURE_STAGES] (ako je trigerovan feature)
    ↓
SPIN_END
```

**Važna pravila:**
- `REEL_SPIN_LOOP` je **jedan audio loop za sve reel-ove** (ne per-reel)
- `REEL_STOP_0..N` su **per-reel sa automatskim stereo pan-om** (-0.8 do +0.8)
- **Anticipation NIKAD ne trigeruje na reel 0** — počinje tek od reel 1 (kad su 2+ scattera)

### Visual-Sync Mode

**Problem:** Rust timing i Flutter animacija nisu sinhronizovani.

**Rešenje:** `_useVisualSyncForReelStop = true`

Kada je uključen Visual-Sync mode:
- REEL_STOP stage-ovi se **NE triggeruju** iz provider timing-a
- Umesto toga, triggeruju se iz **animacionog callback-a**
- Svaki reel ima svoj callback kada završi animaciju

```dart
// U slot_lab_provider.dart, linija 911-914:
if (_useVisualSyncForReelStop && stage.stageType == 'reel_stop') {
  debugPrint('[SlotLabProvider] 🔇 Skipping REEL_STOP (visual-sync mode)');
  return;  // Audio se triggeruje iz animacije, ne iz providera
}
```

**Callback iz animacije:**
```dart
// professional_reel_animation.dart
onReelStopped: (reelIndex) {
  widget.provider.onReelVisualStop(reelIndex);
}
```

### Reel Faze (ReelPhase enum)

| Faza | Trajanje | Opis |
|------|----------|------|
| `idle` | — | Mirovanje, čeka spin |
| `accelerating` | ~200ms | Ubrzavanje na punu brzinu |
| `spinning` | varijabilno | Puna brzina rotacije |
| `decelerating` | ~300ms | Usporavanje pre zaustavljanja |
| `bouncing` | ~150ms | Bounce efekat na zaustavljanje |
| `stopped` | — | Reel stao, čeka sledeći spin |

### Industry-Standard Anticipation System (2026-01-30) ✅

Per-reel anticipation sa tension level escalation — identično IGT, Pragmatic Play, NetEnt, Play'n GO.

**Kompletna dokumentacija:** `.claude/architecture/ANTICIPATION_SYSTEM.md`

**Trigger Logic:**
- 2+ scattera → anticipacija na SVIM preostalim reelovima
- Svaki sledeći reel ima VIŠI tension level (L1→L2→L3→L4)

**Stage Format:**
```
ANTICIPATION_TENSION_R{reel}_L{level}
// Fallback: R2_L3 → R2 → ANTICIPATION_TENSION → ANTICIPATION_ON
```

**Tension Escalation:**
| Level | Color | Volume | Pitch |
|-------|-------|--------|-------|
| L1 | Gold #FFD700 | 0.6x | +1st |
| L2 | Orange #FFA500 | 0.7x | +2st |
| L3 | Red-Orange #FF6347 | 0.8x | +3st |
| L4 | Red #FF4500 | 0.9x | +4st |

**GPU Shader:** `flutter_ui/shaders/anticipation_glow.frag` — Pulsing per-reel glow effect

---

### Win Tier Thresholds (Industry Standard — 2026-01-24)

**VAŽNO:** BIG WIN je **PRVI major tier** po industry standardu (Zynga, NetEnt, Pragmatic Play).

| Tier | Win Ratio | Stage | Plaque Label |
|------|-----------|-------|--------------|
| SMALL | < 5x | WIN_PRESENT_SMALL | "WIN!" |
| **BIG** | **5x - 15x** | WIN_PRESENT_BIG | **"BIG WIN!"** |
| SUPER | 15x - 30x | WIN_PRESENT_SUPER | "SUPER WIN!" |
| MEGA | 30x - 60x | WIN_PRESENT_MEGA | "MEGA WIN!" |
| EPIC | 60x - 100x | WIN_PRESENT_EPIC | "EPIC WIN!" |
| ULTRA | 100x+ | WIN_PRESENT_ULTRA | "ULTRA WIN!" |

**Industry Sources:** Wizard of Oz Slots (Zynga), Know Your Slots, NetEnt, Pragmatic Play

### P5 Win Tier System (2026-01-31) ✅ COMPLETE

Konfigurisljiv win tier sistem sa 100% dynamic labels — NO hardcoded "MEGA WIN!" etc.

**Arhitektura:**
```
Regular Wins (< threshold):    Big Wins (≥ threshold):
├── WIN_LOW   (< 1x)           ├── BIG_WIN_TIER_1 (20x-50x)
├── WIN_EQUAL (= 1x)           ├── BIG_WIN_TIER_2 (50x-100x)
├── WIN_1     (1x-2x)          ├── BIG_WIN_TIER_3 (100x-250x)
├── WIN_2     (2x-5x)          ├── BIG_WIN_TIER_4 (250x-500x)
├── WIN_3     (5x-8x)          └── BIG_WIN_TIER_5 (500x+)
├── WIN_4     (8x-12x)
├── WIN_5     (12x-16x)
└── WIN_6     (16x-20x)
```

**Key Files:**

| File | LOC | Description |
|------|-----|-------------|
| `flutter_ui/lib/models/win_tier_config.dart` | ~1,350 | All data models + 4 presets |
| `flutter_ui/lib/widgets/slot_lab/win_tier_editor_panel.dart` | ~1,225 | UI editor panel |
| `flutter_ui/lib/providers/slot_lab_project_provider.dart` | +225 | Provider integration + constructor |
| `flutter_ui/lib/services/gdd_import_service.dart` | +180 | GDD import conversion |
| `flutter_ui/lib/services/stage_configuration_service.dart` | +120 | Stage registration |
| `crates/rf-slot-lab/src/model/win_tiers.rs` | ~1,030 | Rust engine + 12 tests |
| `flutter_ui/test/models/win_tier_config_test.dart` | ~350 | 25 unit tests |

**Presets (SlotWinConfigurationPresets):**
- `standard` — Balanced for most slots (7 regular tiers, 20x threshold)
- `highVolatility` — Higher thresholds, longer celebrations (25x threshold)
- `jackpotFocus` — Emphasis on big wins, streamlined regular tiers (15x threshold)
- `mobileOptimized` — Faster celebrations for mobile sessions (20x threshold)

**Provider API:**
```dart
// Get current configuration
final config = projectProvider.winConfiguration;
final regularTiers = projectProvider.regularWinConfig;
final bigWinConfig = projectProvider.bigWinConfig;

// Apply preset
projectProvider.applyWinTierPreset(SlotWinConfigurationPresets.highVolatility);

// Export/Import JSON
final json = projectProvider.exportWinConfigurationJson();
projectProvider.importWinConfigurationJson(json);

// Evaluate win
final result = projectProvider.getWinTierForAmount(winAmount, betAmount);
if (result?.isBigWin == true) {
  // Trigger big win celebration
}
```

**GDD Import Integration:**
```dart
// Automatic conversion from GDD volatility
final winConfig = convertGddWinTiersToP5(gdd.math);
// - very_high/extreme → 25x threshold
// - high → 20x threshold
// - medium → 15x threshold
// - low → 10x threshold
```

**Dynamic Stage Names:**
```dart
// Regular: WIN_LOW, WIN_EQUAL, WIN_1, WIN_2, ...
tier.stageName           // "WIN_3"
tier.presentStageName    // "WIN_PRESENT_3"
tier.rollupStartStageName // "ROLLUP_START_3"

// Big Win: BIG_WIN_INTRO, BIG_WIN_TIER_1, ...
bigTier.stageName        // "BIG_WIN_TIER_2"
bigTier.presentStageName // "BIG_WIN_PRESENT_2"
```

**Stage Registration (2026-01-31):**
- `SlotLabProjectProvider()` constructor auto-registers all P5 stages
- `_syncWinTierStages()` calls `StageConfigurationService.registerWinTierStages()`
- Pooled stages: `ROLLUP_TICK_*`, `BIG_WIN_ROLLUP_TICK` (rapid-fire)
- Priority range: 40-90 based on tier importance

**Dokumentacija:** `.claude/specs/WIN_TIER_SYSTEM_SPEC.md`, `.claude/tasks/P5_WIN_TIER_COMPLETE_2026_01_31.md`

### Big Win Celebration System (2026-01-25) ✅

Dedicirani audio sistem za Big Win celebracije (≥20x bet).

**Komponente:**
| Stage | Bus | Priority | Loop | Opis |
|-------|-----|----------|------|------|
| `BIG_WIN_LOOP` | Music (1) | 90 | ✅ Da | Looping celebration muzika, ducks base music |
| `BIG_WIN_COINS` | SFX (2) | 75 | Ne | Coin particle zvuk efekti |

**Trigger Logic (`slot_preview_widget.dart`):**
```dart
final bet = widget.provider.betAmount;
final winRatio = bet > 0 ? result.totalWin / bet : 0.0;
if (winRatio >= 20) {
  eventRegistry.triggerStage('BIG_WIN_LOOP');
  eventRegistry.triggerStage('BIG_WIN_COINS');
}
```

**Auto-Stop (`slot_lab_provider.dart`):**
```dart
void setWinPresentationActive(bool active) {
  if (!active) {
    eventRegistry.stopEvent('BIG_WIN_LOOP');  // Stop loop when win ends
  }
}
```

**UltimateAudioPanel V8.1 (2026-01-31) ✅ CURRENT:**

Game Flow-based slot audio panel sa **~408 audio slotova** organizovanih u **12 sekcija** po toku igre.

| # | Sekcija | Tier | Slots | Boja |
|---|---------|------|-------|------|
| 1 | Base Game Loop | Primary | 44 | #4A9EFF |
| 2 | Symbols & Lands | Primary | 46 | #9370DB |
| 3 | Win Presentation | Primary | 41 | #FFD700 |
| 4 | Cascading Mechanics | Secondary | 24 | #FF6B6B |
| 5 | Multipliers | Secondary | 18 | #FF9040 |
| 6 | Free Spins | Feature | 24 | #40FF90 |
| 7 | Bonus Games | Feature | 32 | #9370DB |
| 8 | Hold & Win | Feature | 23 | #40C8FF |
| 9 | Jackpots | Premium 🏆 | 26 | #FFD700 |
| 10 | Gamble | Optional | 16 | #FF6B6B |
| 11 | Music & Ambience | Background | 25 | #40C8FF |
| 12 | UI & System | Utility | 18 | #808080 |

**V8.1 Ključne promene (P9 Consolidation):**
- **Duplikati uklonjeni** — 7 redundantnih stage-ova uklonjeno
- **Stage konsolidacija** — `REEL_SPIN` + `REEL_SPINNING` → `REEL_SPIN_LOOP`
- **Novi stage-ovi** — `ATTRACT_EXIT`, `IDLE_TO_ACTIVE`, `SPIN_CANCEL`
- **Game Flow organizacija** — Sekcije prate tok igre (Spin→Stop→Win→Feature)
- **Pooled eventi označeni** — ⚡ ikona za rapid-fire (ROLLUP_TICK, CASCADE_STEP, REEL_STOP)
- **Jackpot izdvojen** — 🏆 Premium sekcija sa validation badge
- **Quick Assign Mode (P3-19)** — Click slot → Click audio = Done! workflow

**Quick Assign Mode API (P3-19):**
```dart
// Widget parameters (ultimate_audio_panel.dart)
UltimateAudioPanel(
  quickAssignMode: bool,                            // Whether mode is active
  quickAssignSelectedSlot: String?,                 // Currently selected slot stage
  onQuickAssignSlotSelected: (String stage) {...},  // Callback on slot click
  // Signal '__TOGGLE__' = toggle mode, else = slot selection
)

// Parent integration (slot_lab_screen.dart)
bool _quickAssignMode = false;
String? _quickAssignSelectedSlot;

// UltimateAudioPanel callback
onQuickAssignSlotSelected: (stage) {
  if (stage == '__TOGGLE__') {
    setState(() {
      _quickAssignMode = !_quickAssignMode;
      if (!_quickAssignMode) _quickAssignSelectedSlot = null;
    });
  } else {
    setState(() => _quickAssignSelectedSlot = stage);
  }
},

// EventsPanelWidget audio click callback
onAudioClicked: (audioPath) {
  if (_quickAssignMode && _quickAssignSelectedSlot != null) {
    _handleQuickAssign(audioPath, _quickAssignSelectedSlot!, provider);
    setState(() => _quickAssignSelectedSlot = null);
  }
},
```

**Workflow:**
1. Klikni **Quick Assign** toggle u header → zeleni glow
2. Klikni audio slot → **SELECTED** badge + zeleni border
3. Klikni audio fajl u Audio Browser → **ASSIGNED** sa ⚡ SnackBar

**Persistence:** All expanded states and audio assignments saved via `SlotLabProjectProvider`

**Timeline Bridge (2026-02-14) ✅:**

All audio assignments from UltimateAudioPanel are now bridged to `MiddlewareProvider.compositeEvents` via centralized method `_ensureCompositeEventForStage(stage, audioPath)`. This ensures:
- Timeline in Lower Zone shows events with proper duration bars
- Events Folder reflects all assigned audio
- Auto-detected `durationSeconds` via `NativeFFI.getAudioFileDuration()`

Three assignment paths ALL converge on this bridge:
1. Quick Assign (`_handleQuickAssign`) → `_ensureCompositeEventForStage()`
2. Drag-drop (`onAudioAssign`) → `_ensureCompositeEventForStage()`
3. Mount sync (`_syncPersistedAudioAssignments`) → `_ensureCompositeEventForStage()`

**Dokumentacija:** `.claude/architecture/ULTIMATE_AUDIO_PANEL_V8_SPEC.md`, `.claude/architecture/EVENT_SYNC_SYSTEM.md`

### Anticipation Logic

Anticipation se aktivira kada:
1. Scatter/Bonus simboli se pojave na prva 2-3 reel-a
2. Potencijalni big win je moguć
3. Near-miss situacija

```rust
// U spin.rs
if let Some(ref antic) = self.anticipation {
    if antic.reels.contains(&reel) {
        events.push(StageEvent::new(
            Stage::AnticipationOn { reel_index: reel, reason: Some(antic.reason.clone()) },
            antic_time,
        ));
    }
}
```

### Timing Konfiguracija

Definisano u `crates/rf-slot-lab/src/timing.rs`:

| Profile | Reel Stop Interval | Anticipation Duration | Rollup Speed |
|---------|--------------------|-----------------------|--------------|
| Normal | 400ms | 800ms | 1.0x |
| Turbo | 200ms | 400ms | 2.0x |
| Mobile | 350ms | 600ms | 1.2x |
| Studio | 500ms | 1000ms | 0.8x |

### Ključni Fajlovi

| Fajl | Opis |
|------|------|
| `crates/rf-slot-lab/src/spin.rs` | Stage generacija (Rust) |
| `crates/rf-slot-lab/src/timing.rs` | Timing konfiguracija |
| `flutter_ui/lib/providers/slot_lab_provider.dart` | Stage triggering |
| `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` | Spin UI + animacija |
| `flutter_ui/lib/widgets/slot_lab/professional_reel_animation.dart` | Reel animacija |

---

## 🎯 SLOTLAB TIMELINE DRAG SYSTEM (2026-01-21) ✅

### Arhitektura

SlotLab timeline koristi **apsolutno pozicioniranje** za layer drag operacije.

**Ključne komponente:**

| Komponenta | Fajl | Opis |
|------------|------|------|
| **TimelineDragController** | `flutter_ui/lib/controllers/slot_lab/timeline_drag_controller.dart` | Centralizovani state machine za drag operacije |
| **SlotLabScreen** | `flutter_ui/lib/screens/slot_lab_screen.dart` | Timeline UI sa layer renderingom |
| **MiddlewareProvider** | `flutter_ui/lib/providers/middleware_provider.dart` | Source of truth za layer.offsetMs |

### Drag Flow (Apsolutno Pozicioniranje)

```
1. onHorizontalDragStart:
   - Čita offsetMs direktno iz providera (source of truth)
   - Pretvara u sekunde: absoluteOffsetSeconds = offsetMs / 1000
   - Poziva controller.startLayerDrag(absoluteOffsetSeconds)

2. onHorizontalDragUpdate:
   - Računa timeDelta = dx / pixelsPerSecond
   - Poziva controller.updateLayerDrag(timeDelta)
   - Controller akumulira: _layerDragDelta += timeDelta

3. Vizualizacija tokom drag-a:
   - controller.getAbsolutePosition() vraća apsolutnu poziciju
   - Relativna pozicija za prikaz = absolutePosition - region.start
   - offsetPixels = relativePosition * pixelsPerSecond

4. onHorizontalDragEnd:
   - newAbsoluteOffsetMs = controller.getAbsolutePosition() * 1000
   - provider.setLayerOffset(eventId, layerId, newAbsoluteOffsetMs)
```

### Controller State

```dart
class TimelineDragController {
  double _absoluteStartSeconds;  // Apsolutna pozicija na početku drag-a
  double _layerDragDelta;        // Akumulirani delta tokom drag-a

  double getAbsolutePosition() {
    return (_absoluteStartSeconds + _layerDragDelta).clamp(0.0, infinity);
  }
}
```

### Zašto Apsolutno Pozicioniranje?

**Problem sa relativnim offsetom:**
- `layer.offset` = pozicija relativno na `region.start`
- `region.start` se dinamički menja (prati najraniji layer)
- Pri drugom drag-u, `region.start` može biti drugačiji
- Rezultat: layer "skače" na pogrešnu poziciju

**Rešenje:**
- Uvek čitaj `offsetMs` direktno iz providera
- Controller čuva apsolutnu poziciju
- Relativni offset se računa samo za vizualizaciju
- `region.start` nije uključen u drag kalkulacije

### Event Log Deduplikacija

Event Log prikazuje **jedan entry po stage-u**:
- 🎵 za stage-ove sa audio eventom
- ⚠️ za stage-ove bez audio eventa

**Implementacija:**
- `EventRegistry.triggerStage()` uvek poziva `notifyListeners()`
- Event Log sluša EventRegistry, ne SlotLabProvider direktno
- Sprečava duple entries kad se stage i audio trigeruju istovremeno

### Commits (2026-01-21)

| Commit | Opis |
|--------|------|
| `e1820b0c` | Event log deduplication + captured values pattern |
| `97d8723f` | Absolute positioning za layer drag |

---

Za detalje: `.claude/project/fluxforge-studio.md`

---

