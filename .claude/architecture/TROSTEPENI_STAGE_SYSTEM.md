# Trostepeni Stage System — SlotLab Architecture

> Feature Composer + Pacing Engine + Compact Layout
> Created: 2026-02-28

---

## Overview

Trostepeni (three-tier) stage sistem razdvaja SlotLab lifecycle u tri jasno definisana sloja:

```
┌─────────────────────────────────────────────────────────────┐
│  LAYER 1: ENGINE CORE                                       │
│  Locked lifecycle stages — non-editable, universal          │
│  SPIN_START → REEL_STOP → WIN_EVAL → SPIN_END              │
├─────────────────────────────────────────────────────────────┤
│  LAYER 2: FEATURE COMPOSER                                  │
│  Project-derived stages — auto-generated from mechanics     │
│  User selects: ☑ Cascading  ☑ Hold&Win  ☐ Megaways         │
│  → System composes state machine with transitions           │
├─────────────────────────────────────────────────────────────┤
│  LAYER 3: AUDIO MAPPING                                     │
│  Sound assignments, RTPC hooks, ducking, fade rules         │
│  Per-stage audio slots with bus routing + priority           │
└─────────────────────────────────────────────────────────────┘
         ↓                    ↓                    ↓
    [Existing Middleware Pipeline: StateGate → Trigger → Priority → Orchestration]
```

---

## Layer 1: ENGINE CORE (Locked)

Fiksiran skup stage-ova koji postoje u SVAKOM slot game-u. Ne može se menjati.

### Stage List

| Stage | Hook | Description |
|-------|------|-------------|
| `GAME_INIT` | `onSessionStart` | Session begins |
| `IDLE` | — | Waiting for player input |
| `SPIN_START` | `onSpinStart` | Bet placed, reels start |
| `REEL_STOP_0..N` | `onReelStop_r1..r5` | Individual reel stops (per-reel) |
| `SYMBOL_LAND` | `onSymbolLand` | All reels stopped, symbols evaluated |
| `WIN_EVALUATE` | `onWinEvaluate_tier1..5` | Win tier determination |
| `COUNTUP` | `onCountUpTick/End` | Win amount rollup |
| `SPIN_END` | — | Cycle complete → back to IDLE |

### Transition Map (State Gate)

```
IDLE → SPIN_START → REEL_STOP → SYMBOL_LAND → WIN_EVALUATE → COUNTUP → SPIN_END → IDLE
                                     ↓ (if cascade)
                                  CASCADE_*
                                     ↓ (if feature)
                                  FEATURE_*
```

### Pravilo
- Engine Core stages su **read-only** u UI — prikazani su kao zaključani (🔒)
- Korisnik ih ne može brisati, menjati redosled, niti modifikovati hook mapiranje
- Audio assignment je dozvoljen (Layer 3)

---

## Layer 2: FEATURE COMPOSER

Dinamičko generisanje stage-ova na osnovu odabranih game mehanika.

### Concept

Korisnik bira mehanike kroz checkbox UI:

```
☑ Cascading Wins      → generise CASCADE_START, CASCADE_STEP, CASCADE_END
☑ Free Spins          → generise FEATURE_ENTER, FEATURE_LOOP, FEATURE_EXIT
☑ Hold & Win          → generise HOLD_WIN_LOCK, HOLD_WIN_SPIN, HOLD_WIN_REVEAL
☑ Pick Bonus          → generise PICK_START, PICK_REVEAL, PICK_END
☑ Jackpot (4 tiera)   → generise JACKPOT_MINI, JACKPOT_MINOR, JACKPOT_MAJOR, JACKPOT_GRAND
☐ Megaways            → (disabled, no stages generated)
☐ Gamble              → (disabled)
☑ Nudge/Respin        → generise REEL_NUDGE, RESPIN_START
```

### FeatureComposerProvider

```dart
class FeatureComposerProvider extends ChangeNotifier {
  /// Currently enabled mechanics
  final Map<SlotMechanic, bool> _enabledMechanics = {};

  /// Get all composed stages (Engine Core + Feature-derived)
  List<ComposedStage> get composedStages;

  /// Get only feature-derived stages
  List<ComposedStage> get featureStages;

  /// Enable/disable a mechanic
  void setMechanic(SlotMechanic mechanic, bool enabled);

  /// Which Layer 1 transitions are unlocked by enabled mechanics
  Set<String> get activeTransitions;
}
```

### SlotMechanic Enum

```dart
enum SlotMechanic {
  cascading,
  freeSpins,
  holdAndWin,
  pickBonus,
  wheelBonus,
  jackpot,
  gamble,
  megaways,
  nudgeRespin,
  expandingWilds,
  stickyWilds,
  multiplierTrail,
}
```

### ComposedStage Model

```dart
class ComposedStage {
  final String id;              // e.g. 'CASCADE_STEP'
  final String displayName;     // e.g. 'Cascade Step'
  final StageLayer layer;       // engineCore | featureDerived
  final SlotMechanic? mechanic; // null for Engine Core
  final List<String> hooks;     // mapped hooks for middleware
  final bool locked;            // Engine Core = true
  final int sortOrder;          // display ordering
}
```

### State Machine Composition

Kada korisnik uključi mehaniku, Feature Composer:

1. **Dodaje stage-ove** iz definicije te mehanike
2. **Registruje hook mappings** u TriggerLayerProvider
3. **Ažurira State Gate** sa novim validnim tranzicijama
4. **Generiše audio slotove** za Layer 3 (UltimateAudioPanel)

```
User enables "Cascading"
    → FeatureComposerProvider adds CASCADE_START, CASCADE_STEP, CASCADE_END
    → TriggerLayerProvider gets onCascadeStart → CASCADE_START binding
    → StateGateProvider gets REEL_STOP → CASCADE valid transition
    → UltimateAudioPanel shows CASCADE group in Phase 2 (WINS)
```

---

## Layer 3: AUDIO MAPPING (Existing — Enhanced)

Audio assignment ostaje u UltimateAudioPanel (V10+), ali sa key promenom:
- **Faze se dinamički filtriraju** prema omogućenim mehanikama iz Layer 2
- Neaktivne mehanike → faza se ne prikazuje (ne zauzima prostor)
- Engine Core faze su uvek vidljive

### Existing Infrastructure (no changes needed)
- `EventRegistry` — stage→AudioEvent binding
- `StageConfigurationService` — loop/overlap/crossfade per stage
- `MiddlewareProvider` — composite events for timeline
- Bus routing (SFX/Music/Reels/VO/UI/Ambience)

---

## PACING ENGINE (Generate Audio Map From Math)

Matematički model koji generiše audio parametre iz game matematike.

### Concept

```
INPUTS (Game Math):
  RTP: 96.5%
  Volatility: HIGH (0.85)
  Hit Frequency: 28%
  Max Win: 10,000x
  Feature Frequency: 1/180

OUTPUTS (OrchestrationContext Presets):
  → Base tension: 0.3 (low hit = more anticipation)
  → Escalation curve: exponential (high volatility = sharp peaks)
  → Session fatigue rate: 0.015/min (high frequency = faster fatigue)
  → Win magnitude thresholds: [5x, 15x, 50x, 200x, 1000x]
  → Anticipation intensity: L3-L4 by reel 4 (low frequency)
```

### PacingEngineProvider

```dart
class PacingEngineProvider extends ChangeNotifier {
  // Math Inputs
  double _rtp = 0.965;
  double _volatility = 0.5;
  double _hitFrequency = 0.30;
  double _maxWin = 5000.0;
  double _featureFrequency = 180.0;  // 1 in N spins

  /// Compute emotional template from math inputs
  PacingTemplate get template;

  /// Feed template into OrchestrationContext
  OrchestrationContext toOrchestrationContext();
}
```

### PacingTemplate Model

```dart
class PacingTemplate {
  final double baseTension;          // 0.0-1.0
  final double escalationCurve;      // linear=1.0, exponential=2.0+
  final double sessionFatigueRate;   // per-minute fatigue growth
  final List<double> winThresholds;  // bet multipliers for tier boundaries
  final int anticipationStartReel;   // which reel begins anticipation
  final double maxAnticipationLevel; // L1-L4
}
```

### Integration Point

Pacing Engine NE menja runtime. Generiše **preset** koji se učita u OrchestrationContext:

```
PacingEngine.toOrchestrationContext()
    → OrchestrationEngineProvider.updateContext(context)
    → Middleware pipeline uses these values during playback
```

---

## LEFT PANEL LAYOUT REDESIGN (V11)

### Problem
Trenutni panel (V10) prikazuje svih 7 faza uvek, čak i kad neke mehanike nisu aktivne.
Na malom ekranu previše scrollovanja za prazne sekcije.

### Solution: Dynamic Phase Filtering

```
BEFORE (V10):                    AFTER (V11):
┌──────────────────────┐        ┌──────────────────────┐
│ [ALL][CORE][WINS]... │        │ [STAGES] [PACING]    │  ← Two modes
├──────────────────────┤        ├──────────────────────┤
│ 🔒 CORE LOOP         │        │ 🔒 ENGINE CORE ──── │  ← Always visible
│   Spin Start    🔊   │        │   Spin Start    🔊  │
│   Reel Stop 1   🔊   │        │   Reel Stops    🔊  │  ← Grouped
│   Reel Stop 2   🔊   │        │   Symbol Land   🔊  │
│   Reel Stop 3   🔊   │        │   Win Evaluate  🔊  │
│   ...                 │        │                      │
│ 🏅 WINS              │        │ ☑ CASCADING ──────── │  ← Feature (active)
│   Win Line      🔊   │        │   Cascade Start 🔊  │
│   ...                 │        │   Cascade Step  🔊  │
│ 🎁 FEATURES          │        │   Cascade End   🔊  │
│   (empty)             │        │                      │
│ 🏆 JACKPOTS          │        │ ☑ FREE SPINS ────── │  ← Feature (active)
│   (empty)             │        │   Feature Enter 🔊  │
│ 🎲 GAMBLE            │        │   Feature Loop  🔊  │
│   (empty)             │        │   Feature Exit  🔊  │
│ 🎵 MUSIC & AMB       │        │                      │
│   ...                 │        │ 🎵 MUSIC & AMBIENCE  │  ← Always visible
│ 🖥 UI                │        │   ...                │
│   ...                 │        │ 🖥 UI & SYSTEM       │  ← Always visible
└──────────────────────┘        └──────────────────────┘
                                 Inactive mechanics hidden
```

### Key Changes

1. **Engine Core** — uvek vidljiv, zaključan, kompaktan
   - Grupisani reel stops (REEL_STOP_0..4 → jedan colapsibilan red)

2. **Feature Mechanics** — samo aktivne se prikazuju
   - Checkbox u header-u → enable/disable mechanic
   - Prazne mehanike = sakrivene potpuno

3. **Music & UI** — uvek vidljive (ne zavise od mehanika)

4. **Two-tab top bar**:
   - `STAGES` — audio assignment (current UltimateAudioPanel behavior)
   - `PACING` — PacingEngine inputs (RTP, volatility, etc.)

5. **Compact reel grouping**:
   - Umesto 5 pojedinačnih REEL_STOP slotova → jedan "Reel Stops" koji se expand-uje
   - Smanjuje vertikalni prostor za 4 reda

---

## Integration Map

```
┌─────────────────────────────────────────────────────────┐
│                    LEFT PANEL (V11)                       │
│  ┌─────────────────────────────────────────────────┐    │
│  │ [STAGES]  [PACING]                               │    │
│  ├─────────────────────────────────────────────────┤    │
│  │                                                   │    │
│  │  STAGES tab:                 PACING tab:          │    │
│  │  - Engine Core (locked)      - RTP slider         │    │
│  │  - Active mechanics          - Volatility slider  │    │
│  │  - Music & UI                - Hit Frequency      │    │
│  │  - Audio drop zones          - Max Win            │    │
│  │                              - Feature Frequency  │    │
│  │                              - [Generate Template]│    │
│  └─────────────────────────────────────────────────┘    │
└─────────┬──────────────────────────┬────────────────────┘
          ↓                          ↓
   FeatureComposerProvider    PacingEngineProvider
          ↓                          ↓
   TriggerLayerProvider      OrchestrationEngineProvider
          ↓                          ↓
   StateGateProvider         EmotionalStateProvider
          ↓                          ↓
          └──────────┬───────────────┘
                     ↓
            SlotLabCoordinator.processHook()
                     ↓
              [Existing Pipeline]
```

---

## Implementation Order

1. **FeatureComposerProvider** — novi provider, GetIt Layer 6
2. **PacingEngineProvider** — novi provider, GetIt Layer 6
3. **UltimateAudioPanel V11** — dynamic filtering, grouped reels, two-tab layout
4. **Wire providers** — composer→trigger/gate, pacing→orchestration

---

## Files to Create/Modify

### New Files
- `flutter_ui/lib/providers/slot_lab/feature_composer_provider.dart`
- `flutter_ui/lib/providers/slot_lab/pacing_engine_provider.dart`

### Modified Files
- `flutter_ui/lib/widgets/slot_lab/ultimate_audio_panel.dart` — V11 layout
- `flutter_ui/lib/screens/slot_lab_screen.dart` — pass new providers
- `flutter_ui/lib/services/service_locator.dart` — register new providers at Layer 6
