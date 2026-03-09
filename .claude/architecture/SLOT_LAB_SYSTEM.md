# FluxForge Slot Lab — System Documentation

> Synthetic Slot Engine za audio dizajn i testiranje slot igara.

**Related:**
- [EVENT_SYNC_SYSTEM.md](./EVENT_SYNC_SYSTEM.md) — Bidirekciona sinhronizacija eventa

---

## Overview

Slot Lab je fullscreen audio sandbox za slot game audio dizajn:
- **Synthetic Slot Engine** (rf-slot-lab) — Generisanje slot spinova, wins, stages
- **Stage-Based Audio Triggering** — Automatski audio eventi na osnovu stage-ova
- **Wwise/FMOD-Style Middleware** — Bus routing, RTPC, State/Switch
- **Premium UI/UX** — Casino-grade vizuali, animacije, real-time feedback

---

## Architecture

```
Flutter UI (Slot Lab Screen)
    │
    ▼
SlotLabCoordinator (ChangeNotifier)
  - spin() / spinForced()
  - lastResult, lastStages
  - _playStagesSequentially() → triggers EventRegistry
    │
    │ FFI
    ▼
Rust (rf-bridge/slot_lab_ffi.rs)
  - slot_lab_init/shutdown/spin/spin_forced
  - slot_lab_get_spin_result_json / get_stages_json
    │
    ▼
Rust (rf-slot-lab crate)
  - engine.rs, symbols.rs, paytable.rs, timing.rs, spin.rs, stages.rs, config.rs
```

---

## Rust Crate: rf-slot-lab

**Location:** `crates/rf-slot-lab/src/`

### Key Types

- **SyntheticSlotEngine** — config, symbols, paytable, timing, rng, stats
- **SpinResult** — spin_id, grid, bet, total_win, win_ratio, line_wins, big_win_tier, feature_triggered, near_miss, cascades, free_spin_info, multiplier
- **StageEvent** — stage_type, timestamp_ms, payload
- **StageType** — SpinStart, ReelSpinning, ReelStop, AnticipationOn/Off, AnticipationTensionLayer, EvaluateWins, WinPresent, WinLineShow, RollupStart/Tick/End, BigWinTier, FeatureEnter/Step/Exit, CascadeStart/Step/End, JackpotTrigger/Present, SpinEnd
- **ForcedOutcome** — Lose, SmallWin, MediumWin, BigWin, MegaWin, EpicWin, UltraWin, FreeSpins, JackpotMini/Minor/Major/Grand, NearMiss, Cascade

### Volatility Profiles

| Preset | RTP | Hit Rate | Max Win |
|--------|-----|----------|---------|
| low | 96% | 35% | 5000x |
| medium | 95% | 28% | 10000x |
| high | 94% | 22% | 25000x |
| studio | 100% | 50% | 1000x (testing) |

### Timing Profiles

Presets: `normal()`, `turbo()`, `mobile()`, `studio()`

### Anticipation Config

Per-reel anticipation sa tension level escalation (L1-L4).

| Level | Color | Volume | Pitch |
|-------|-------|--------|-------|
| L1 | Gold #FFD700 | 0.6x | +1st |
| L2 | Orange #FFA500 | 0.7x | +2st |
| L3 | Red-Orange #FF6347 | 0.8x | +3st |
| L4 | Red #FF4500 | 0.9x | +4st |

---

## FFI Bridge: slot_lab_ffi.rs

**Location:** `crates/rf-bridge/src/slot_lab_ffi.rs`

### Global State

- `SLOT_ENGINE: Lazy<RwLock<Option<SyntheticSlotEngine>>>`
- `LAST_RESULT: Lazy<RwLock<Option<SpinResult>>>`
- `LAST_STAGES: Lazy<RwLock<Vec<StageEvent>>>`

### Exported Functions

| Category | Functions |
|----------|-----------|
| Lifecycle | `slot_lab_init()`, `slot_lab_init_audio_test()`, `slot_lab_shutdown()`, `slot_lab_is_initialized()` |
| Spin | `slot_lab_spin()`, `slot_lab_spin_forced(outcome: i32)` |
| Results | `slot_lab_get_spin_result_json()`, `slot_lab_get_stages_json()`, `slot_lab_get_stats_json()` |
| Accessors | `slot_lab_last_spin_is_win()`, `_total_win()`, `_win_ratio()`, `_cascade_count()` |
| Config | `slot_lab_set_bet()`, `slot_lab_set_volatility()`, `slot_lab_set_timing_profile()` |
| Memory | `slot_lab_free_string()` |

### Outcome Mapping (i32)

0=Lose, 1=SmallWin, 2=MediumWin, 3=BigWin, 4=MegaWin, 5=EpicWin, 6=UltraWin, 7=FreeSpins, 8-11=Jackpot(Mini/Minor/Major/Grand), 12=NearMiss, 13=Cascade

---

## Flutter: Provider Hierarchy

**IMPORTANT:** `SlotLabProvider` u `providers/slot_lab_provider.dart` je MRTAV KOD. `typedef SlotLabProvider = SlotLabCoordinator;` u `slot_lab_coordinator.dart`.

P12.1.7 decomposition:
- `SlotEngineProvider` — `spin()` (line 391)
- `SlotStageProvider` — `_triggerStage()` (line 590)
- `SlotAudioProvider` — audio integration

### Key State

- Engine: `_initialized`, `_isSpinning`
- Spin data: `_lastResult`, `_lastStages`
- Stage playback: `_currentStageIndex`, `_isPlayingStages`
- Config: `_betAmount`, `_autoTriggerAudio`
- Connected: `MiddlewareProvider`, `StageAudioMapper`

### Stage Playback Flow

```
spin() → FFI slot_lab_spin() → parse result/stages
  → if autoTriggerAudio: _playStagesSequentially()
    → for each stage: _triggerStage(stage)
      → reelIndex from stage.rawStage['reel_index']
      → effectiveStage = 'REEL_STOP_$reelIndex'
      → eventRegistry.triggerStage(effectiveStage)
      → wait (nextStage.timestamp - currentStage.timestamp)
```

---

## Data Models

**Location:** `flutter_ui/lib/src/rust/native_ffi.dart`

### SlotLabStageEvent

```dart
class SlotLabStageEvent {
  final String stageType;
  final double timestampMs;
  final Map<String, dynamic> payload;   // General context (win amounts, bet)
  final Map<String, dynamic> rawStage;  // Stage-specific fields from Rust
}
// CRITICAL: Stage data is in rawStage, NOT payload!
// reel_index, symbols, reason → stage.rawStage[...]
```

---

## Stage System Rules

### Stage → Audio Event Mapping

| Stage Type | Middleware Event ID |
|------------|-------------------|
| spin_start | slot_spin_start |
| reel_stop | slot_reel_stop |
| anticipation_on | slot_anticipation |
| win_present | slot_win_present |
| rollup_start/tick/end | slot_rollup_start/tick/end |
| bigwin_tier | slot_bigwin_{tier} |
| feature_enter/step/exit | slot_feature_enter/step/exit |
| cascade_start/step/end | slot_cascade_start/step/end |
| jackpot_trigger/present | slot_jackpot_trigger/present |
| spin_end | slot_spin_end |

### Complete Stage Sequence

```
SPIN_START
  → REEL_SPINNING × N
  → [ANTICIPATION_TENSION] (opciono)
  → REEL_STOP_0 → REEL_STOP_1 → ... → REEL_STOP_N
  → [ANTICIPATION_MISS]
  → EVALUATE_WINS
  → [WIN_PRESENT] (ako ima win)
  → [WIN_LINE_SHOW × N] (max 3)
  → [BIG_WIN_TIER]
  → [ROLLUP_START → ROLLUP_TICK × N → ROLLUP_END]
  → [CASCADE_STAGES]
  → [FEATURE_STAGES]
  → SPIN_END
```

### Visual-Sync Mode (default)

Kada `useVisualSyncForReelStop = true`:
- REEL_STOP stage-ovi se **NE triggeruju** iz provider timing-a
- Triggeruju se iz **animacionog callback-a** (bouncing phase = visual landing moment)

### Reel Animation Phases

idle → accelerating (~200ms) → spinning (var) → decelerating (~300ms) → bouncing (~150ms) → stopped

Audio fires at `bouncing` phase (visual landing moment), NOT at `stopped`.

---

## Win Tier System

### Thresholds (Industry Standard)

| Tier | Win Ratio | Plaque Label | Audio Stage |
|------|-----------|--------------|-------------|
| SMALL | < 5x | "WIN!" | WIN_PRESENT_SMALL |
| BIG | 5x - 15x | "BIG WIN!" | WIN_PRESENT_BIG |
| SUPER | 15x - 30x | "SUPER WIN!" | WIN_PRESENT_SUPER |
| MEGA | 30x - 60x | "MEGA WIN!" | WIN_PRESENT_MEGA |
| EPIC | 60x - 100x | "EPIC WIN!" | WIN_PRESENT_EPIC |
| ULTRA | 100x+ | "ULTRA WIN!" | WIN_PRESENT_ULTRA |

### 3-Phase Win Presentation

**Phase 1: Symbol Highlight (1050ms)** — 3x350ms pulse cycles, WIN_SYMBOL_HIGHLIGHT stages

**Phase 2: Win Plaque + Rollup** — Tier-based duration (SMALL=1500ms, BIG=2500ms, SUPER=4000ms, MEGA=7000ms, EPIC=12000ms, ULTRA=20000ms)

**Phase 3: Win Line Presentation** — Starts AFTER Phase 2 ends, plaque hides, 1500ms per line

**Skip:** Allowed after tier-specific delay. On skip: stop all win audio, trigger END stages (ROLLUP_END, COIN_SHOWER_END, BIG_WIN_TICK_END, BIG_WIN_END, WIN_PRESENT_END, WIN_COLLECT), fade out plaque.

---

## Audio Features (Implemented)

### Symbol-Specific Audio (P1.1)

Priority: WILD > SCATTER > SEVEN > generic
Stage naming: `REEL_STOP_0_WILD`, `REEL_STOP_2_SCATTER`, `REEL_STOP_0` (fallback)

### Per-Reel Spin Loops (P0.20)

| Pattern | Purpose |
|---------|---------|
| `REEL_SPINNING_START_0..4` | Start spin loop per reel |
| `REEL_SPINNING_STOP_0..4` | Early fade-out PRE visual stop |

### Anticipation System

Stage format: `ANTICIPATION_TENSION_R{reel}_L{level}`
Fallback chain: `R2_L3 → R2 → ANTICIPATION_TENSION`
Trigger: 2+ scatters → anticipation on all remaining reels

### Near Miss Escalation (P1.2)

Intensity = intensity × reelFactor × missingFactor
- > 0.8 → ANTICIPATION_CRITICAL (vol 1.0)
- > 0.5 → ANTICIPATION_HIGH (vol 0.9)
- else → ANTICIPATION_TENSION (vol 0.7-0.85)

### Win Line Panning (P1.3)

Pan = average X position mapped to -1.0..+1.0

### Big Win Layered Audio (P0.7)

4 layers: Impact Hit (bus SFX, 0ms) → Coin Shower (SFX, 100-150ms) → Music Swell (Music, 0ms) → Voice Over (Voice, 300-700ms)

### CASCADE_STEP Escalation (P0.21)

+5% pitch per step, +4% volume per step (starting at 90%)

### Jackpot Sequence (P1.5)

6 phases: TRIGGER (500ms) → BUILDUP (2000ms) → REVEAL (1000ms) → PRESENT (5000ms) → CELEBRATION (loop) → END

### Big Win Celebration (≥20x bet)

Stages: COIN_SHOWER_START/END, BIG_WIN_TICK_START/END

---

## Adaptive Layer Engine (ALE) Integration

ALE = data-driven, context-aware, metric-reactive music system.

### Signal Mapping

| Slot Lab Event | ALE Signal | Range |
|----------------|------------|-------|
| Spin result | winTier | 0-5 |
| Win/bet ratio | winXbet | 0.0+ |
| Consecutive wins/losses | consecutiveWins/Losses | 0-255 |
| Free spins progress | featureProgress | 0.0-1.0 |
| Cascade depth | cascadeDepth | 0-255 |
| Near miss | nearMissIntensity | 0.0-1.0 |

### Context Mapping

BASE, FREESPINS, HOLDWIN, PICKEM, WHEEL, CASCADE, JACKPOT

**Full ALE spec:** `.claude/architecture/ADAPTIVE_LAYER_ENGINE.md`

---

## UI Widgets

**Location:** `flutter_ui/lib/widgets/slot_lab/`

| Widget | Purpose |
|--------|---------|
| StageTraceWidget | Animated timeline sa stage markers, playhead, color-coded zones |
| SlotPreviewWidget | Premium slot machine preview, reel animations, win lines |
| PremiumSlotPreview | Full premium slot UI (~3600 LOC), fullscreen + embedded mode |
| EventLogPanel | Real-time log, timestamped, color-coded, filterable |
| ForcedOutcomePanel | Test buttons for forced outcomes (keyboard 1-0) |
| AudioBrowserPanel | Audio browser sa hover preview, waveform, drag-to-timeline |

### Stage Colors

spin_start=Blue, reel_stop=Purple, anticipation_on=Orange, win_present=Green, rollup_start=Gold, bigwin_tier=Pink, feature_enter=Cyan, jackpot_trigger=Gold

### SPACE Key Architecture

- **Embedded mode** (`isFullscreen=false`): Global handler in `slot_lab_screen.dart` handles SPACE
- **Fullscreen mode** (`isFullscreen=true`): Focus handler in `premium_slot_preview.dart` handles SPACE

Only ONE handler processes SPACE to prevent double-spin bug.

---

## Double-Spin Prevention

Two guard flags in `slot_preview_widget.dart`:
- `_spinFinalized` — blocks re-trigger after finalize
- `_lastProcessedSpinId` — tracks already-processed spinId

---

## Troubleshooting: Audio Not Playing

1. **EventRegistry empty at mount** — `_syncAllEventsToRegistry()` in initState postFrameCallback
2. **Case mismatch** — `triggerStage()` does `toUpperCase().trim()` normalization
3. **No AudioEvents created** — Create events in SlotLab UI, drag .wav files
4. **FFI not loaded** — Full rebuild: `cargo build --release` + copy dylibs + xcodebuild

---

## Testing

```bash
cargo test -p rf-slot-lab     # 20 tests (engine, paytable, symbols, timing, config, spin)
cargo test -p rf-bridge slot_lab  # 2 tests (lifecycle, forced outcomes)
cd flutter_ui && flutter analyze  # Must be 0 errors
```

---

## Timing Profiles

| Profile | Reel Stop | Anticipation | Rollup |
|---------|-----------|--------------|--------|
| Normal | 400ms | 800ms | 1.0x |
| Turbo | 200ms | 400ms | 2.0x |
| Mobile | 350ms | 600ms | 1.2x |
| Studio | 370ms | 500ms | 0.8x |
