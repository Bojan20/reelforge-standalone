# Adaptive Layer Engine — Ultimate Architecture v2.0

> **Paradigm Shift:** From "play sound X" to "game is in emotional state Y"

---

## Executive Summary

The Adaptive Layer Engine (ALE) is a **data-driven, context-aware, metric-reactive, musically-intelligent** audio system that transforms game audio from a reactive jukebox into an emotional dramaturg.

**What makes it ultimate:**

| Aspect | Standard Approach | ALE Ultimate |
|--------|-------------------|--------------|
| **Logic** | Hardcoded events | Data-driven rules |
| **Timing** | Immediate cuts | Beat/phrase/bar sync |
| **Transitions** | Simple crossfade | Multi-curve, ducking-aware |
| **Stability** | None | 7 mechanisms (cooldown, hysteresis, inertia, hold, decay, momentum, prediction) |
| **Performance** | Blocking locks | Lock-free, SIMD, zero-alloc RT |
| **Visualization** | None | GPU-accelerated real-time |
| **Persistence** | None | Version-controlled profiles |
| **Integration** | Single game | Universal adapter layer |

---

## Part I: Core Philosophy

### The Mental Model

ALE doesn't know what a "big win" is. It doesn't know what "free spins" are. It only knows:

1. **Context** — Which narrative chapter the game is in (emotional world)
2. **Layer** — Current intensity level within that world (energy axis)
3. **Signals** — Numeric values from the game state
4. **Rules** — Conditions that trigger transitions

Everything else — music, layers, transitions, ducking — is **data you define**.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GAME STATE MACHINE                                 │
│  (Slot Engine, Middleware, External Game)                                   │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 │ Metric Signals (normalized)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        ADAPTIVE LAYER ENGINE                                 │
│                                                                              │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐ │
│  │Signal Intake │──▶│Rule Evaluator│──▶│ Stability    │──▶│Transition    │ │
│  │& Normalizer  │   │& Prioritizer │   │ Governor     │   │Orchestrator  │ │
│  └──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘ │
│         │                  │                  │                  │          │
│         ▼                  ▼                  ▼                  ▼          │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                        CONTEXT MANAGER                                │  │
│  │  Active: FREESPINS │ Level: L4 (Drive) │ Target: L5 │ Transition: 45%│  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│         │                                                                   │
│         ▼                                                                   │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                      PLAYBACK ORCHESTRATOR                            │  │
│  │                                                                       │  │
│  │  ┌─ Layer Stack ───────────────────────────────────────────────────┐ │  │
│  │  │ L5: [climax_fanfare 0.0] [victory_perc 0.0] [max_energy 0.0]   │ │  │
│  │  │ L4: [drive_loop 1.0]▶ [bass_drive 0.9]▶ [perc_full 0.8]▶       │ │  │
│  │  │ L3: [tension_build ↘0.2] [energy_overlay ↘0.1]                 │ │  │
│  │  │ L2: [main_loop ○] [bass ○] [perc_light ○]                      │ │  │
│  │  │ L1: [ambient_pad ○] [subtle_texture ○]                         │ │  │
│  │  └─────────────────────────────────────────────────────────────────┘ │  │
│  │                                                                       │  │
│  │  ▶ = Playing  ↘ = Fading out  ↗ = Fading in  ○ = Stopped            │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                                 │
                                 │ Multi-bus Audio Output
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            BUS HIERARCHY                                     │
│  [Layer Bus L1-L5] ──▶ [Music Submix] ──▶ [Master] ──▶ Output               │
│                              │                                               │
│                              ├── Ducking from SFX                           │
│                              └── Sidechain from VO                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part II: Signal System (Ultimate)

### Signal Types & Normalization

The game emits raw signals. ALE normalizes them to consistent ranges for rule evaluation.

| Signal | Raw Type | Normalized | Range | Description |
|--------|----------|------------|-------|-------------|
| `winTier` | int | int | 0-6 | Win tier enum (NONE=0, SMALL=1, MED=2, BIG=3, MEGA=4, EPIC=5, ULTRA=6) |
| `winXbet` | float | float | 0-∞ | Win amount / bet size |
| `winXbetNorm` | derived | float | 0-1 | Sigmoid-normalized winXbet |
| `consecutiveWins` | int | int | 0-∞ | Win streak counter |
| `consecutiveWinsNorm` | derived | float | 0-1 | Sigmoid(consecutiveWins, midpoint=3) |
| `spinsSinceWin` | int | int | 0-∞ | Lose streak counter |
| `spinsSinceWinNorm` | derived | float | 0-1 | Sigmoid(spinsSinceWin, midpoint=5) |
| `featureProgress` | float | float | 0-1 | Progress through bonus |
| `anticipationLevel` | float | float | 0-1 | Near-miss intensity |
| `anticipationReels` | int | int | 0-5 | Which reel(s) showing anticipation |
| `timeInContext` | float | float | 0-∞ | Seconds in current context |
| `timeInContextNorm` | derived | float | 0-1 | Asymptotic normalization |
| `momentum` | derived | float | 0-1 | Weighted rolling average of win intensity |
| `velocity` | derived | float | -1 to +1 | Rate of change of momentum |
| `playerSpeedMode` | enum | int | 0-2 | NORMAL=0, TURBO=1, AUTO=2 |
| `betLevel` | float | float | 0-1 | Normalized bet within range |
| `sessionDuration` | float | float | 0-∞ | Total session time in seconds |
| `totalWinSession` | float | float | 0-∞ | Session total win |
| `custom.*` | any | float | 0-1 | User-defined signals |

### Derived Signal Computations

```rust
/// Sigmoid normalization for unbounded values
fn sigmoid_normalize(value: f64, midpoint: f64, steepness: f64) -> f64 {
    1.0 / (1.0 + (-steepness * (value - midpoint)).exp())
}

/// Momentum calculation (exponential moving average)
fn calculate_momentum(
    previous: f64,
    new_win_intensity: f64,
    decay_factor: f64,  // 0.85 typical
) -> f64 {
    previous * decay_factor + new_win_intensity * (1.0 - decay_factor)
}

/// Velocity (rate of change)
fn calculate_velocity(
    current_momentum: f64,
    previous_momentum: f64,
    delta_time: f64,
) -> f64 {
    (current_momentum - previous_momentum) / delta_time
}
```

### Signal Emission (Dart Integration)

```dart
/// Comprehensive metric emitter
class MetricSignalEmitter {
  final LayerEngineProvider _engine;

  // Rolling state
  double _momentum = 0.0;
  double _previousMomentum = 0.0;
  int _consecutiveWins = 0;
  int _spinsSinceWin = 0;
  DateTime _contextEntryTime = DateTime.now();
  DateTime _sessionStart = DateTime.now();
  double _totalWinSession = 0.0;

  /// Called on every spin result
  void onSpinResult(SpinResult result, double betAmount) {
    // Update streaks
    if (result.isWin) {
      _consecutiveWins++;
      _spinsSinceWin = 0;
      _totalWinSession += result.winAmount;
    } else {
      _consecutiveWins = 0;
      _spinsSinceWin++;
    }

    // Calculate normalized win intensity (0-1 based on winXbet)
    final winIntensity = _sigmoidNormalize(
      result.winAmount / betAmount,
      midpoint: 20.0,  // 20x bet = 0.5 intensity
      steepness: 0.1,
    );

    // Update momentum
    _previousMomentum = _momentum;
    _momentum = _calculateMomentum(_momentum, winIntensity, 0.85);

    // Emit all signals
    _engine.updateSignals({
      'winTier': result.winTier,
      'winXbet': result.winAmount / betAmount,
      'winXbetNorm': _sigmoidNormalize(result.winAmount / betAmount, 50, 0.05),
      'consecutiveWins': _consecutiveWins,
      'consecutiveWinsNorm': _sigmoidNormalize(_consecutiveWins.toDouble(), 3, 0.5),
      'spinsSinceWin': _spinsSinceWin,
      'spinsSinceWinNorm': _sigmoidNormalize(_spinsSinceWin.toDouble(), 5, 0.3),
      'momentum': _momentum,
      'velocity': _calculateVelocity(),
      'totalWinSession': _totalWinSession,
    });
  }

  /// Called on feature progress updates
  void onFeatureProgress({
    required int remaining,
    required int total,
    bool isRetrigger = false,
  }) {
    _engine.updateSignals({
      'featureProgress': 1.0 - (remaining / total),
      'featureRemaining': remaining,
      'featureTotal': total,
      if (isRetrigger) 'retriggerOccurred': 1.0,
    });
  }

  /// Called on anticipation detection
  void onAnticipation({
    required double intensity,
    required int missingSymbols,
    required int reelIndex,
    required List<int> anticipatingReels,
  }) {
    // Combined intensity based on:
    // - Base intensity from detection
    // - How many symbols needed (1 = higher tension)
    // - Which reel (later reels = higher tension)
    final positionFactor = reelIndex / 4.0;  // 0-1 for reels 0-4
    final symbolFactor = 1.0 - (missingSymbols - 1) * 0.2;  // 1 needed = 1.0, 2 needed = 0.8

    final combinedIntensity = intensity * symbolFactor * (0.5 + positionFactor * 0.5);

    _engine.updateSignals({
      'anticipationLevel': combinedIntensity,
      'anticipationReels': anticipatingReels.fold(0, (a, b) => a | (1 << b)),
      'anticipationMissing': missingSymbols,
    });
  }

  /// Called on context changes
  void onContextChange(String newContext, {String? triggerType}) {
    _contextEntryTime = DateTime.now();
    _engine.switchContext(newContext, trigger: triggerType);
  }

  /// Called every frame to update time-based signals
  void tick() {
    final timeInContext = DateTime.now().difference(_contextEntryTime).inMilliseconds / 1000.0;
    final sessionDuration = DateTime.now().difference(_sessionStart).inMilliseconds / 1000.0;

    _engine.updateSignals({
      'timeInContext': timeInContext,
      'timeInContextNorm': _asymptotic(timeInContext, halflife: 30.0),
      'sessionDuration': sessionDuration,
    });
  }

  double _sigmoidNormalize(double value, double midpoint, double steepness) {
    return 1.0 / (1.0 + exp(-steepness * (value - midpoint)));
  }

  double _calculateMomentum(double previous, double newIntensity, double decay) {
    return previous * decay + newIntensity * (1.0 - decay);
  }

  double _calculateVelocity() {
    // Velocity per second (assuming ~1 spin per 3 seconds)
    return (_momentum - _previousMomentum) * 3.0;
  }

  double _asymptotic(double value, {required double halflife}) {
    return 1.0 - exp(-value * 0.693 / halflife);
  }
}
```

---

## Part III: Context System (Ultimate)

### Context as Emotional Worlds

A context is not a "mode" — it's a distinct **emotional world** with its own:

- Sound palette (different instruments, textures, key)
- Energy range (min/max layers)
- Transition behavior (how it enters/exits)
- Rule set (what triggers level changes)
- Narrative arc (how intensity evolves over time)

### Built-in Context Templates

| Context ID | Name | Typical Layers | Min | Max | Arc Pattern |
|------------|------|----------------|-----|-----|-------------|
| `BASE` | Base Game | 4 | L1 | L4 | Reactive to wins |
| `FREESPINS` | Free Spins | 5 | L2 | L5 | Build to climax |
| `HOLDWIN` | Hold & Win | 4 | L2 | L4 | Tension→release cycles |
| `PICK` | Pick Bonus | 3 | L2 | L3 | Steady anticipation |
| `WHEEL` | Wheel Bonus | 4 | L2 | L4 | Spin→result cycle |
| `JACKPOT` | Jackpot Round | 5 | L3 | L5 | Maximum celebration |
| `GAMBLE` | Gamble/Risk | 3 | L2 | L4 | High tension |
| `IDLE` | Attract Mode | 2 | L1 | L2 | Minimal, ambient |
| `INTRO` | Game Intro | 3 | L1 | L3 | Build brand identity |

### Complete Context Definition Schema

```json
{
  "id": "FREESPINS",
  "name": "Free Spins Feature",
  "description": "Triggered bonus round with awarded free spins",

  "audio_identity": {
    "key": "E minor",
    "tempo_bpm": 128,
    "energy_character": "epic_fantasy",
    "reference_track": "assets/references/fs_reference.wav"
  },

  "layer_count": 5,
  "layers": {
    "L1": {
      "name": "Ethereal",
      "description": "Soft pad, distant sparkles",
      "energy": 0.15,
      "tracks": [
        {
          "id": "fs_ambient_pad",
          "path": "music/fs/L1_ambient.wav",
          "volume": 0.7,
          "pan": 0.0,
          "bus": "music_layer_1",
          "loop": true,
          "sync_group": "fs_music",
          "fade_in_bars": 2,
          "fade_out_bars": 4
        },
        {
          "id": "fs_sparkle_texture",
          "path": "music/fs/L1_sparkle.wav",
          "volume": 0.3,
          "pan": 0.0,
          "bus": "music_layer_1",
          "loop": true,
          "sync_group": "fs_music"
        }
      ]
    },
    "L2": {
      "name": "Foundation",
      "description": "Main loop establishes, light rhythm",
      "energy": 0.35,
      "tracks": [
        {
          "id": "fs_main_loop",
          "path": "music/fs/L2_main.wav",
          "volume": 0.9,
          "loop": true,
          "sync_group": "fs_music"
        },
        {
          "id": "fs_bass",
          "path": "music/fs/L2_bass.wav",
          "volume": 0.6,
          "loop": true,
          "sync_group": "fs_music"
        },
        {
          "id": "fs_perc_light",
          "path": "music/fs/L2_perc.wav",
          "volume": 0.4,
          "loop": true,
          "sync_group": "fs_music"
        }
      ]
    },
    "L3": {
      "name": "Tension",
      "description": "Energy builds, anticipation rises",
      "energy": 0.55,
      "tracks": [
        { "id": "fs_main_loop", "volume": 1.0 },
        { "id": "fs_bass", "volume": 0.8 },
        {
          "id": "fs_energy_overlay",
          "path": "music/fs/L3_energy.wav",
          "volume": 0.7,
          "loop": true,
          "sync_group": "fs_music"
        },
        {
          "id": "fs_tension_riser",
          "path": "music/fs/L3_riser.wav",
          "volume": 0.5,
          "loop": true,
          "sync_group": "fs_music",
          "pitch_follow_progress": true
        }
      ]
    },
    "L4": {
      "name": "Drive",
      "description": "Full energy, celebration ready",
      "energy": 0.80,
      "tracks": [
        {
          "id": "fs_main_intense",
          "path": "music/fs/L4_main.wav",
          "volume": 1.0,
          "loop": true,
          "sync_group": "fs_music"
        },
        {
          "id": "fs_bass_drive",
          "path": "music/fs/L4_bass.wav",
          "volume": 0.9,
          "loop": true,
          "sync_group": "fs_music"
        },
        {
          "id": "fs_perc_full",
          "path": "music/fs/L4_perc.wav",
          "volume": 0.8,
          "loop": true,
          "sync_group": "fs_music"
        },
        {
          "id": "fs_celebration_bed",
          "path": "music/fs/L4_celeb.wav",
          "volume": 0.6,
          "loop": true,
          "sync_group": "fs_music"
        }
      ]
    },
    "L5": {
      "name": "Climax",
      "description": "Maximum intensity, victory fanfare",
      "energy": 1.0,
      "tracks": [
        { "id": "fs_main_intense", "volume": 1.0 },
        { "id": "fs_bass_drive", "volume": 1.0 },
        { "id": "fs_perc_full", "volume": 1.0 },
        {
          "id": "fs_climax_layer",
          "path": "music/fs/L5_climax.wav",
          "volume": 0.9,
          "loop": true,
          "sync_group": "fs_music"
        },
        {
          "id": "fs_victory_fanfare",
          "path": "music/fs/L5_fanfare.wav",
          "volume": 0.7,
          "loop": false,
          "one_shot_on_enter": true,
          "retrigger_on_hold": 8000
        }
      ]
    }
  },

  "entry_policy": {
    "type": "trigger_strength_mapping",
    "default_level": 2,
    "inherit_momentum": true,
    "momentum_level_bonus": 0.5,

    "trigger_mapping": {
      "3_scatters": {
        "start_level": 2,
        "entry_transition": "feature_enter_normal"
      },
      "4_scatters": {
        "start_level": 3,
        "entry_transition": "feature_enter_energetic"
      },
      "5_scatters": {
        "start_level": 4,
        "entry_transition": "feature_enter_epic"
      },
      "retrigger": {
        "start_level": "current + 1",
        "max_level": 5,
        "entry_transition": "retrigger_celebration"
      }
    },

    "entry_stinger": {
      "audio_path": "stingers/fs_entry.wav",
      "duck_music_db": -12,
      "duck_duration_ms": 2000
    }
  },

  "exit_policy": {
    "type": "gradual_return",
    "return_context": "BASE",
    "return_level": 2,

    "wind_down": {
      "enabled": true,
      "start_at_progress": 0.9,
      "target_level": 3,
      "spins_before_exit": 2
    },

    "final_transition": {
      "profile": "feature_exit",
      "fade_duration_ms": 2500,
      "crossfade_overlap_ms": 500
    },

    "summary_stinger": {
      "enabled": true,
      "total_win_thresholds": {
        "small": "stingers/fs_exit_small.wav",
        "big": "stingers/fs_exit_big.wav",
        "mega": "stingers/fs_exit_mega.wav"
      },
      "duck_music_db": -9
    },

    "cooldown_before_retrigger_ms": 10000
  },

  "constraints": {
    "min_level": 2,
    "max_level": 5,
    "level_change_cooldown_ms": 1500,
    "max_level_changes_per_spin": 2
  },

  "narrative_arc": {
    "enabled": true,
    "type": "build_to_climax",

    "phases": [
      {
        "progress_range": [0.0, 0.3],
        "name": "opening",
        "level_bias": 0,
        "rule_modifier": "standard"
      },
      {
        "progress_range": [0.3, 0.7],
        "name": "development",
        "level_bias": 0,
        "rule_modifier": "reactive"
      },
      {
        "progress_range": [0.7, 0.9],
        "name": "build",
        "level_bias": +1,
        "rule_modifier": "escalate",
        "min_level_override": 3
      },
      {
        "progress_range": [0.9, 1.0],
        "name": "climax",
        "level_bias": +2,
        "rule_modifier": "maximum",
        "min_level_override": 4
      }
    ]
  },

  "ducking_overrides": {
    "win_sfx_duck_db": -6,
    "symbol_sfx_duck_db": -3,
    "vo_duck_db": -9
  },

  "tempo_follow": {
    "enabled": false,
    "source": "featureProgress",
    "range_bpm": [120, 140]
  }
}
```

### Context Transition Orchestration

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      CONTEXT TRANSITION FLOW                              │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  BASE (L3) ─────────[FS TRIGGER: 5 scatters]─────────▶ FREESPINS (L4)   │
│                                                                          │
│  Step 1: Entry Stinger                                                   │
│    ├── Play fs_entry.wav (one-shot)                                      │
│    ├── Duck current music -12dB over 200ms                              │
│    └── Hold duck for 2000ms                                              │
│                                                                          │
│  Step 2: Context Switch                                                  │
│    ├── Mark old context as "exiting"                                     │
│    ├── Begin fade-out of BASE L3 tracks (2000ms)                        │
│    └── Calculate entry level from trigger mapping (5 scatters → L4)     │
│                                                                          │
│  Step 3: New Context Fade-In                                             │
│    ├── Wait for next bar boundary (beat_sync)                           │
│    ├── Load FREESPINS L4 tracks                                         │
│    ├── Begin fade-in (1500ms)                                            │
│    └── Crossfade overlap with outgoing (500ms)                          │
│                                                                          │
│  Step 4: Stabilization                                                   │
│    ├── Mark new context as "active"                                      │
│    ├── Start cooldown timer (2000ms)                                     │
│    ├── Start hold timer (3000ms)                                         │
│    └── Reset timeInContext signal                                        │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Part IV: Rule System (Ultimate)

### Rule Structure

Rules are the power tool. They define when and how layers change.

```json
{
  "id": "fs_big_win_escalation",
  "name": "Big Win Escalation",
  "description": "Escalate on significant wins during free spins",

  "enabled": true,
  "contexts": ["FREESPINS"],
  "priority": 100,

  "condition": {
    "type": "OR",
    "conditions": [
      {
        "signal": "winTier",
        "operator": ">=",
        "value": 3
      },
      {
        "type": "AND",
        "conditions": [
          { "signal": "winXbet", "operator": ">=", "value": 15 },
          { "signal": "consecutiveWins", "operator": ">=", "value": 2 }
        ]
      }
    ]
  },

  "action": {
    "type": "step_up",
    "steps": 1,
    "max_level": 5,
    "allow_skip_levels": false
  },

  "transition": "upshift_energetic",

  "timing": {
    "sync_mode": "beat",
    "max_wait_ms": 500
  },

  "stability": {
    "cooldown_ms": 2000,
    "hold_ms": 4000,
    "requires_hold_expired": true
  },

  "side_effects": {
    "trigger_stinger": {
      "enabled": true,
      "path": "stingers/win_escalation.wav",
      "volume": 0.7,
      "condition": { "signal": "winTier", "operator": ">=", "value": 4 }
    },
    "emit_event": "ALE_LEVEL_UP",
    "update_momentum": 0.2
  },

  "debug": {
    "log_evaluation": true,
    "highlight_in_ui": true
  }
}
```

### Condition Language (Complete)

#### Operators

| Operator | Symbol | Example | Description |
|----------|--------|---------|-------------|
| Equal | `==`, `eq` | `winTier == 3` | Exact match |
| Not Equal | `!=`, `neq` | `winTier != 0` | Not match |
| Greater | `>`, `gt` | `winXbet > 10` | Greater than |
| Greater Equal | `>=`, `gte` | `consecutiveWins >= 3` | Greater or equal |
| Less | `<`, `lt` | `featureProgress < 0.2` | Less than |
| Less Equal | `<=`, `lte` | `momentum <= 0.3` | Less or equal |
| In Set | `in` | `winTier in [2,3,4]` | Value in set |
| Not In Set | `not_in` | `winTier not_in [0,1]` | Value not in set |
| Between | `between` | `winXbet between [5, 50]` | Inclusive range |
| Changed | `changed` | `winTier changed` | Value changed this tick |
| Increased | `increased` | `momentum increased` | Value increased |
| Decreased | `decreased` | `spinsSinceWin decreased` | Value decreased (reset) |
| Crossed Above | `crossed_above` | `momentum crossed_above 0.7` | Just crossed threshold up |
| Crossed Below | `crossed_below` | `momentum crossed_below 0.3` | Just crossed threshold down |
| Duration | `held_for` | `anticipationLevel > 0.5 held_for 500` | Condition held for N ms |

#### Compound Conditions

```json
// AND: All must be true
{
  "type": "AND",
  "conditions": [
    { "signal": "winTier", "operator": ">=", "value": 3 },
    { "signal": "consecutiveWins", "operator": ">=", "value": 2 },
    { "signal": "momentum", "operator": ">", "value": 0.6 }
  ]
}

// OR: Any must be true
{
  "type": "OR",
  "conditions": [
    { "signal": "winXbet", "operator": ">=", "value": 100 },
    { "signal": "winTier", "operator": ">=", "value": 5 }
  ]
}

// NOT: Inverts condition
{
  "type": "NOT",
  "condition": { "signal": "anticipationLevel", "operator": ">", "value": 0 }
}

// Nested
{
  "type": "AND",
  "conditions": [
    { "signal": "featureProgress", "operator": ">=", "value": 0.8 },
    {
      "type": "OR",
      "conditions": [
        { "signal": "winTier", "operator": ">=", "value": 2 },
        { "signal": "momentum", "operator": ">", "value": 0.7 }
      ]
    }
  ]
}

// Temporal: Condition held for duration
{
  "type": "HELD_FOR",
  "duration_ms": 500,
  "condition": { "signal": "anticipationLevel", "operator": ">", "value": 0.7 }
}

// Sequence: Conditions in order within time window
{
  "type": "SEQUENCE",
  "window_ms": 5000,
  "conditions": [
    { "signal": "winTier", "operator": ">=", "value": 2 },
    { "signal": "winTier", "operator": ">=", "value": 3 },
    { "signal": "winTier", "operator": ">=", "value": 4 }
  ]
}
```

### Action Types

| Action | Parameters | Description |
|--------|------------|-------------|
| `step_up` | `steps`, `max_level`, `allow_skip` | Increase level by N |
| `step_down` | `steps`, `min_level`, `allow_skip` | Decrease level by N |
| `set_level` | `level` | Set to exact level |
| `hold` | `duration_ms`, `level` | Hold current/specified level |
| `release` | — | Release any active hold |
| `nudge` | `amount`, `max`, `min` | Small continuous adjustment |
| `pulse` | `target_level`, `return_after_ms` | Temporary spike then return |
| `context_switch` | `context_id`, `trigger` | Switch to different context |
| `noop` | — | Explicitly do nothing (for blocking) |

### Rule Priority & Evaluation

```rust
/// Rule evaluation algorithm
fn evaluate_rules(&mut self, signals: &MetricSignals) {
    // 1. Filter by context
    let context_rules: Vec<_> = self.rules.iter()
        .filter(|r| r.enabled)
        .filter(|r| r.contexts.contains(&self.current_context))
        .collect();

    // 2. Evaluate conditions
    let triggered: Vec<_> = context_rules.iter()
        .filter(|r| r.condition.evaluate(signals, &self.signal_history))
        .collect();

    // 3. Filter by stability (cooldowns, holds)
    let allowed: Vec<_> = triggered.iter()
        .filter(|r| !self.stability.is_rule_on_cooldown(&r.id))
        .filter(|r| !r.stability.requires_hold_expired || !self.stability.has_active_hold())
        .collect();

    // 4. Sort by priority (highest first)
    let mut sorted = allowed;
    sorted.sort_by(|a, b| b.priority.cmp(&a.priority));

    // 5. Execute highest priority rule (or first N if allow_concurrent)
    if let Some(rule) = sorted.first() {
        self.execute_rule(rule);
    }
}
```

### Example Rule Sets by Context

#### BASE Context Rules

```json
{
  "context": "BASE",
  "rules": [
    {
      "id": "base_win_escalation",
      "priority": 100,
      "condition": {
        "type": "OR",
        "conditions": [
          { "signal": "winTier", "operator": ">=", "value": 2 },
          { "signal": "winXbet", "operator": ">=", "value": 20 }
        ]
      },
      "action": { "type": "step_up", "steps": 1, "max_level": 4 },
      "transition": "upshift",
      "stability": { "cooldown_ms": 1500, "hold_ms": 3000 }
    },
    {
      "id": "base_big_win",
      "priority": 120,
      "condition": {
        "type": "OR",
        "conditions": [
          { "signal": "winTier", "operator": ">=", "value": 4 },
          { "signal": "winXbet", "operator": ">=", "value": 100 }
        ]
      },
      "action": { "type": "set_level", "level": 4 },
      "transition": "upshift_energetic",
      "stability": { "cooldown_ms": 0, "hold_ms": 6000 }
    },
    {
      "id": "base_calm_down",
      "priority": 50,
      "condition": { "signal": "spinsSinceWin", "operator": ">=", "value": 4 },
      "action": { "type": "step_down", "steps": 1, "min_level": 1 },
      "transition": "downshift",
      "stability": { "cooldown_ms": 2000, "requires_hold_expired": true }
    },
    {
      "id": "base_momentum_decay",
      "priority": 40,
      "condition": {
        "type": "AND",
        "conditions": [
          { "signal": "momentum", "operator": "<", "value": 0.2 },
          { "signal": "spinsSinceWin", "operator": ">=", "value": 6 }
        ]
      },
      "action": { "type": "set_level", "level": 1 },
      "transition": "slow_fade",
      "stability": { "requires_hold_expired": true }
    },
    {
      "id": "base_anticipation",
      "priority": 80,
      "condition": { "signal": "anticipationLevel", "operator": ">", "value": 0.7 },
      "action": { "type": "set_level", "level": 3 },
      "transition": "tension_build",
      "stability": { "hold_ms": 0 }
    },
    {
      "id": "base_anticipation_release",
      "priority": 79,
      "condition": {
        "type": "AND",
        "conditions": [
          { "signal": "anticipationLevel", "operator": "crossed_below", "value": 0.1 },
          { "signal": "winTier", "operator": "==", "value": 0 }
        ]
      },
      "action": { "type": "step_down", "steps": 2, "min_level": 1 },
      "transition": "disappointment",
      "stability": { "cooldown_ms": 500 }
    },
    {
      "id": "base_streak",
      "priority": 90,
      "condition": { "signal": "consecutiveWins", "operator": ">=", "value": 3 },
      "action": { "type": "step_up", "steps": 1, "max_level": 4 },
      "transition": "upshift",
      "stability": { "cooldown_ms": 1000, "hold_ms": 4000 }
    }
  ]
}
```

#### FREESPINS Context Rules

```json
{
  "context": "FREESPINS",
  "rules": [
    {
      "id": "fs_entry_stabilize",
      "priority": 200,
      "condition": { "signal": "timeInContext", "operator": "<", "value": 3 },
      "action": { "type": "hold", "duration_ms": 3000 },
      "stability": { "cooldown_ms": 0 }
    },
    {
      "id": "fs_win_escalation",
      "priority": 100,
      "condition": {
        "type": "OR",
        "conditions": [
          { "signal": "winTier", "operator": ">=", "value": 2 },
          { "signal": "winXbet", "operator": ">=", "value": 10 }
        ]
      },
      "action": { "type": "step_up", "steps": 1, "max_level": 5 },
      "transition": "upshift",
      "stability": { "cooldown_ms": 1500, "hold_ms": 3000 }
    },
    {
      "id": "fs_multiplier_boost",
      "priority": 110,
      "condition": { "signal": "custom.multiplier", "operator": ">=", "value": 5 },
      "action": { "type": "set_level", "level": 4 },
      "transition": "upshift_energetic",
      "stability": { "hold_ms": 5000 }
    },
    {
      "id": "fs_final_spins_build",
      "priority": 120,
      "condition": { "signal": "featureProgress", "operator": ">=", "value": 0.85 },
      "action": { "type": "step_up", "steps": 1 },
      "transition": "upshift",
      "stability": { "hold_ms": 10000 }
    },
    {
      "id": "fs_retrigger_celebration",
      "priority": 150,
      "condition": { "signal": "custom.retriggerOccurred", "operator": "==", "value": 1 },
      "action": { "type": "set_level", "level": 5 },
      "transition": "celebration",
      "stability": { "hold_ms": 8000 },
      "side_effects": {
        "trigger_stinger": { "path": "stingers/fs_retrigger.wav" },
        "reset_signal": "custom.retriggerOccurred"
      }
    },
    {
      "id": "fs_constraint_min_l2",
      "priority": 1000,
      "condition": {
        "type": "AND",
        "conditions": [
          { "signal": "_currentLevel", "operator": "<", "value": 2 },
          { "signal": "timeInContext", "operator": ">", "value": 1 }
        ]
      },
      "action": { "type": "set_level", "level": 2 },
      "transition": "immediate"
    }
  ]
}
```

---

## Part V: Transition System (Ultimate)

### Transition Profiles

Transitions control HOW layer changes sound musically.

```json
{
  "id": "upshift_energetic",
  "name": "Energetic Upshift",
  "description": "Fast, punchy transition for win escalation",

  "timing": {
    "sync_mode": "beat",
    "quantize_to": "quarter",
    "max_wait_ms": 750,
    "lookahead_beats": 2
  },

  "fade": {
    "in": {
      "duration_ms": 250,
      "curve": "ease_out_quad",
      "start_volume": 0.0,
      "delay_ms": 0
    },
    "out": {
      "duration_ms": 200,
      "curve": "ease_in_quad",
      "end_volume": 0.0
    },
    "crossfade_overlap_ms": 100
  },

  "track_behavior": {
    "shared_tracks": "blend",
    "exclusive_incoming": "fade_in",
    "exclusive_outgoing": "fade_out",
    "volume_interpolation": "smooth"
  },

  "effects": {
    "ducking": {
      "enabled": true,
      "target_buses": ["sfx", "vo"],
      "amount_db": -4,
      "attack_ms": 30,
      "release_ms": 200
    },
    "filter_sweep": {
      "enabled": false,
      "type": "lowpass",
      "start_freq": 500,
      "end_freq": 20000,
      "duration_ms": 300
    },
    "pitch_glide": {
      "enabled": false
    }
  },

  "stinger": {
    "enabled": false,
    "path": null,
    "volume": 0.6,
    "delay_ms": 0
  }
}
```

### Sync Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `immediate` | No sync, start now | Emergency, tight timing |
| `beat` | Next beat boundary | Most transitions |
| `bar` | Next bar boundary | Major changes |
| `phrase` | Next phrase (4/8 bars) | Context switches |
| `next_downbeat` | Next measure downbeat | Musical emphasis |
| `custom` | User-defined beat multiple | Special cases |

### Fade Curves

| Curve | Description | Formula |
|-------|-------------|---------|
| `linear` | Straight line | `t` |
| `ease_in_quad` | Slow start | `t²` |
| `ease_out_quad` | Slow end | `1-(1-t)²` |
| `ease_in_out_quad` | Slow both | S-curve |
| `ease_in_cubic` | Slower start | `t³` |
| `ease_out_cubic` | Slower end | `1-(1-t)³` |
| `ease_in_out_cubic` | Slower both | S-curve³ |
| `equal_power` | Constant loudness | `sqrt(t)` crossfade |
| `logarithmic` | Perceptual linear | `log(1 + t*9) / log(10)` |
| `s_curve` | Classic crossfade | `t² * (3 - 2t)` |

### Transition Execution (Detailed)

```rust
pub struct TransitionExecutor {
    active_transition: Option<ActiveTransition>,
    beat_tracker: BeatTracker,
}

impl TransitionExecutor {
    pub fn begin_transition(
        &mut self,
        from_level: u8,
        to_level: u8,
        profile: &TransitionProfile,
        playback: &mut PlaybackState,
    ) {
        // 1. Calculate sync point
        let sync_point = match profile.timing.sync_mode {
            SyncMode::Immediate => self.beat_tracker.now(),
            SyncMode::Beat => self.beat_tracker.next_beat(profile.timing.lookahead_beats),
            SyncMode::Bar => self.beat_tracker.next_bar(),
            SyncMode::Phrase => self.beat_tracker.next_phrase(),
        };

        // 2. Determine track changes
        let from_tracks = playback.get_layer_tracks(from_level);
        let to_tracks = playback.get_layer_tracks(to_level);

        let fade_out_tracks: Vec<_> = from_tracks.iter()
            .filter(|t| !to_tracks.contains(t))
            .collect();

        let fade_in_tracks: Vec<_> = to_tracks.iter()
            .filter(|t| !from_tracks.contains(t))
            .collect();

        let shared_tracks: Vec<_> = from_tracks.iter()
            .filter(|t| to_tracks.contains(t))
            .collect();

        // 3. Pre-load incoming tracks (during wait period)
        for track in &fade_in_tracks {
            playback.preload_track(track.id);
        }

        // 4. Create active transition
        self.active_transition = Some(ActiveTransition {
            sync_point,
            from_level,
            to_level,
            profile: profile.clone(),
            fade_out_tracks: fade_out_tracks.into_iter().cloned().collect(),
            fade_in_tracks: fade_in_tracks.into_iter().cloned().collect(),
            shared_tracks: shared_tracks.into_iter().cloned().collect(),
            phase: TransitionPhase::Waiting,
            start_time: None,
        });
    }

    pub fn tick(&mut self, now: Instant, playback: &mut PlaybackState) {
        let transition = match &mut self.active_transition {
            Some(t) => t,
            None => return,
        };

        match transition.phase {
            TransitionPhase::Waiting => {
                if now >= transition.sync_point {
                    transition.phase = TransitionPhase::Executing;
                    transition.start_time = Some(now);

                    // Start fade-in tracks
                    for track in &transition.fade_in_tracks {
                        playback.start_track(track.id, 0.0);  // Start at 0 volume
                    }

                    // Apply ducking
                    if transition.profile.effects.ducking.enabled {
                        self.apply_ducking(&transition.profile.effects.ducking);
                    }
                }
            }

            TransitionPhase::Executing => {
                let elapsed = now.duration_since(transition.start_time.unwrap());
                let profile = &transition.profile;

                // Calculate fade progress
                let fade_in_progress = (elapsed.as_millis() as f32 / profile.fade.in.duration_ms as f32).min(1.0);
                let fade_out_progress = (elapsed.as_millis() as f32 / profile.fade.out.duration_ms as f32).min(1.0);

                // Apply curves
                let fade_in_volume = apply_curve(fade_in_progress, &profile.fade.in.curve);
                let fade_out_volume = 1.0 - apply_curve(fade_out_progress, &profile.fade.out.curve);

                // Update fade-in tracks
                for track in &transition.fade_in_tracks {
                    let target_volume = playback.get_layer_track_volume(transition.to_level, track.id);
                    playback.set_track_volume(track.id, target_volume * fade_in_volume);
                }

                // Update fade-out tracks
                for track in &transition.fade_out_tracks {
                    let original_volume = playback.get_layer_track_volume(transition.from_level, track.id);
                    playback.set_track_volume(track.id, original_volume * fade_out_volume);
                }

                // Update shared tracks (volume blend)
                for track in &transition.shared_tracks {
                    let from_vol = playback.get_layer_track_volume(transition.from_level, track.id);
                    let to_vol = playback.get_layer_track_volume(transition.to_level, track.id);
                    let blend_progress = apply_curve(fade_in_progress, &Curve::SCurve);
                    let blended = from_vol + (to_vol - from_vol) * blend_progress;
                    playback.set_track_volume(track.id, blended);
                }

                // Check if complete
                let max_duration = profile.fade.in.duration_ms.max(profile.fade.out.duration_ms);
                if elapsed.as_millis() >= max_duration as u128 {
                    transition.phase = TransitionPhase::Complete;

                    // Stop faded-out tracks
                    for track in &transition.fade_out_tracks {
                        playback.stop_track(track.id);
                    }

                    // Release ducking
                    self.release_ducking();
                }
            }

            TransitionPhase::Complete => {
                self.active_transition = None;
            }
        }
    }
}
```

---

## Part VI: Stability System (Ultimate 7 Mechanisms)

Professional systems need sophisticated stability to prevent audio chaos.

### 1. Cooldown (Per-Rule)

After a rule fires, it cannot fire again for a specified duration.

```json
{
  "cooldown_ms": 1500,
  "global_cooldown_ms": 500
}
```

**Purpose:** Prevent rule spam from rapid signals.

### 2. Hold (Per-Level)

When reaching a level, maintain it for a minimum duration before allowing changes.

```json
{
  "L3_hold_ms": 2000,
  "L4_hold_ms": 4000,
  "L5_hold_ms": 6000
}
```

**Purpose:** Give each level time to establish musically.

### 3. Hysteresis (Threshold Separation)

Different thresholds for escalation vs de-escalation.

```json
{
  "win_escalation": {
    "up_threshold": { "winXbet": 20 },
    "down_threshold": { "spinsSinceWin": 4 }
  }
}
```

**Purpose:** Prevent oscillation at boundary conditions.

### 4. Level Inertia (Stickiness)

Higher levels are harder to leave. Multiplier on de-escalation requirements.

```json
{
  "L1_inertia": 1.0,
  "L2_inertia": 1.0,
  "L3_inertia": 1.3,
  "L4_inertia": 1.6,
  "L5_inertia": 2.0
}
```

At L4, a rule requiring "spinsSinceWin >= 4" effectively requires ">= 6.4" (rounded to 7).

**Purpose:** Higher energy states feel more "earned" and stable.

### 5. Decay (Automatic Regression)

Without positive signals, levels automatically decay over time.

```json
{
  "decay": {
    "enabled": true,
    "rate_per_second": 0.1,
    "floor_level": 1,
    "pause_during_transition": true,
    "pause_during_anticipation": true
  }
}
```

**Purpose:** Natural return to calm when nothing exciting happens.

### 6. Momentum Buffer (Signal Smoothing)

Rapid signal changes are smoothed through exponential moving average.

```json
{
  "momentum": {
    "decay_factor": 0.85,
    "min_change_threshold": 0.05,
    "sample_window_ms": 500
  }
}
```

**Purpose:** Prevent single outlier events from causing jarring changes.

### 7. Prediction (Look-Ahead)

Anticipate likely future states to pre-load and smooth transitions.

```json
{
  "prediction": {
    "enabled": true,
    "horizon_ms": 2000,
    "confidence_threshold": 0.7,
    "preload_probable_tracks": true
  }
}
```

Based on current momentum and velocity, predict likely level in 2 seconds.
- If confidence > 70%, pre-load those tracks.
- Enables smoother transitions when prediction is correct.

**Purpose:** Reduce latency on predictable transitions.

### Stability State Machine

```rust
pub struct StabilityState {
    // Cooldowns
    global_cooldown_until: Option<Instant>,
    rule_cooldowns: HashMap<String, Instant>,

    // Holds
    level_hold_until: Option<Instant>,
    forced_hold_level: Option<u8>,

    // Inertia
    level_inertia_factors: [f32; 5],  // L1-L5

    // Decay
    last_decay_tick: Instant,
    decay_paused: bool,

    // Momentum
    momentum_buffer: CircularBuffer<f32, 10>,
    current_momentum: f32,

    // Prediction
    predicted_level: Option<u8>,
    prediction_confidence: f32,
}

impl StabilityState {
    pub fn can_execute_rule(&self, rule: &LayerRule, now: Instant) -> bool {
        // Check global cooldown
        if let Some(until) = self.global_cooldown_until {
            if now < until {
                return false;
            }
        }

        // Check rule-specific cooldown
        if let Some(until) = self.rule_cooldowns.get(&rule.id) {
            if now < *until {
                return false;
            }
        }

        // Check hold requirement
        if rule.stability.requires_hold_expired {
            if let Some(until) = self.level_hold_until {
                if now < until {
                    return false;
                }
            }
        }

        true
    }

    pub fn apply_inertia(&self, threshold: f64, current_level: u8) -> f64 {
        let inertia = self.level_inertia_factors[current_level as usize];
        threshold * inertia as f64
    }

    pub fn tick_decay(&mut self, current_level: &mut u8, delta_seconds: f32) {
        if self.decay_paused || self.level_hold_until.is_some() {
            return;
        }

        // Accumulate decay
        let decay_amount = delta_seconds * DECAY_RATE_PER_SECOND;
        // ... apply decay logic
    }

    pub fn update_prediction(&mut self, momentum: f32, velocity: f32) {
        // Simple linear extrapolation
        let predicted_momentum = momentum + velocity * PREDICTION_HORIZON_SECONDS;

        self.predicted_level = Some(momentum_to_level(predicted_momentum));
        self.prediction_confidence = 1.0 - (velocity.abs() * 2.0).min(1.0);
    }
}
```

---

## Part VII: Playback Orchestrator (Real-Time)

### Track State Machine

Each track in a layer has its own state:

```rust
pub enum TrackState {
    Stopped,
    Loading,
    Ready,
    FadingIn { progress: f32, target_volume: f32 },
    Playing { volume: f32 },
    FadingOut { progress: f32, from_volume: f32 },
    Releasing,
}

pub struct TrackInstance {
    id: String,
    path: PathBuf,
    state: TrackState,
    current_volume: f32,
    pan: f32,
    voice_id: Option<u32>,
    loop_enabled: bool,
    sync_group: Option<String>,
}
```

### Sync Groups

Tracks in the same sync group maintain sample-accurate synchronization:

```rust
pub struct SyncGroup {
    id: String,
    master_position: u64,  // In samples
    tempo_bpm: f32,
    time_signature: (u8, u8),
    bar_length_samples: u64,
    phrase_length_bars: u8,
}

impl SyncGroup {
    pub fn get_next_beat(&self, now_samples: u64) -> u64 {
        let beat_length = self.bar_length_samples / self.time_signature.1 as u64;
        let current_beat = now_samples / beat_length;
        (current_beat + 1) * beat_length
    }

    pub fn get_next_bar(&self, now_samples: u64) -> u64 {
        let current_bar = now_samples / self.bar_length_samples;
        (current_bar + 1) * self.bar_length_samples
    }

    pub fn get_position_in_bar(&self, now_samples: u64) -> f32 {
        (now_samples % self.bar_length_samples) as f32 / self.bar_length_samples as f32
    }
}
```

### Bus Routing

Layer tracks route through dedicated buses:

```
┌──────────────────────────────────────────────────────────────────┐
│                         BUS STRUCTURE                            │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  L1 Tracks ──▶ [Layer 1 Bus] ──┐                                │
│  L2 Tracks ──▶ [Layer 2 Bus] ──┼──▶ [Music Submix] ──┐          │
│  L3 Tracks ──▶ [Layer 3 Bus] ──┤                      │          │
│  L4 Tracks ──▶ [Layer 4 Bus] ──┤                      ├──▶ Master│
│  L5 Tracks ──▶ [Layer 5 Bus] ──┘                      │          │
│                                                        │          │
│  SFX ────────────────────────────────────────────────┤          │
│  VO ─────────────────────────────────────────────────┤          │
│  Ambience ───────────────────────────────────────────┘          │
│                                                                  │
│  Sidechain: Music Submix ◀── SFX Bus (ducking)                  │
│  Sidechain: Music Submix ◀── VO Bus (ducking)                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Part VIII: Performance Architecture (Real-Time Safe)

### Lock-Free Design

```rust
/// Real-time safe engine core
pub struct AdaptiveLayerEngineRT {
    // Atomic current state
    current_level: AtomicU8,
    current_context_hash: AtomicU32,
    transition_progress: AtomicU32,  // Fixed-point 0-65536 = 0.0-1.0

    // Lock-free command queue (UI → RT)
    command_rx: rtrb::Consumer<EngineCommand>,

    // Lock-free state output (RT → UI)
    state_tx: rtrb::Producer<EngineState>,

    // Pre-allocated buffers
    track_volumes: [AtomicU32; MAX_TRACKS],  // Fixed-point
    track_states: [AtomicU8; MAX_TRACKS],

    // Signal buffer (triple-buffered)
    signals: TripleBuffer<MetricSignals>,
}

pub enum EngineCommand {
    UpdateSignals(MetricSignals),
    SwitchContext { context_hash: u32, trigger: Option<u32> },
    ForceLevel { level: u8 },
    Pause,
    Resume,
}

impl AdaptiveLayerEngineRT {
    /// Called from audio thread - must be lock-free
    #[inline(always)]
    pub fn process_audio(&mut self, buffer: &mut [f32]) {
        // 1. Drain command queue (non-blocking)
        while let Ok(cmd) = self.command_rx.pop() {
            self.handle_command(cmd);
        }

        // 2. Read current signals (lock-free triple buffer)
        let signals = self.signals.read();

        // 3. Tick stability (no allocations)
        self.tick_stability();

        // 4. Evaluate rules (pre-compiled, no allocations)
        if let Some(action) = self.evaluate_rules_fast(signals) {
            self.queue_action(action);
        }

        // 5. Process transitions (no allocations)
        self.tick_transitions();

        // 6. Mix layer tracks to output
        self.mix_layers_to_buffer(buffer);

        // 7. Publish state to UI (non-blocking)
        let _ = self.state_tx.push(self.capture_state());
    }
}
```

### SIMD Track Mixing

```rust
#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2")]
unsafe fn mix_tracks_simd(
    output: &mut [f32],
    track_buffers: &[&[f32]],
    volumes: &[f32],
) {
    use std::arch::x86_64::*;

    let len = output.len();
    let simd_len = len - (len % 8);

    // Process 8 samples at a time
    for i in (0..simd_len).step_by(8) {
        let mut sum = _mm256_setzero_ps();

        for (track, &volume) in track_buffers.iter().zip(volumes.iter()) {
            let samples = _mm256_loadu_ps(track.as_ptr().add(i));
            let vol = _mm256_set1_ps(volume);
            let scaled = _mm256_mul_ps(samples, vol);
            sum = _mm256_add_ps(sum, scaled);
        }

        _mm256_storeu_ps(output.as_mut_ptr().add(i), sum);
    }

    // Handle remainder
    for i in simd_len..len {
        let mut sample = 0.0f32;
        for (track, &volume) in track_buffers.iter().zip(volumes.iter()) {
            sample += track[i] * volume;
        }
        output[i] = sample;
    }
}
```

### Memory Budget

```rust
pub struct MemoryConfig {
    /// Maximum loaded contexts
    max_contexts: usize,         // 8

    /// Maximum layers per context
    max_layers_per_context: usize,  // 6

    /// Maximum tracks per layer
    max_tracks_per_layer: usize,    // 8

    /// Maximum total tracks loaded
    max_total_tracks: usize,        // 64

    /// Track buffer pool size
    track_buffer_pool_mb: usize,    // 128 MB

    /// Pre-allocated rule capacity
    max_rules: usize,               // 256

    /// Signal history depth
    signal_history_depth: usize,    // 100 samples
}

// Total pre-allocated memory: ~150 MB
// No allocations during playback
```

---

## Part IX: UI/UX Design (Professional DAW)

### Main Panel Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ADAPTIVE LAYER ENGINE                                            [•] [≡] [×]│
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ ┌─ CONTEXT ─────────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  [BASE ▾]  ──────────▶  FREESPINS  ──────────▶  [return to BASE]     │  │
│ │                         ▲ ACTIVE                                      │  │
│ │  Progress: ████████████████████░░░░░ 80%   Spins: 8/10              │  │
│ │  Time: 45.2s   Entry: 4 scatters   Trigger Level: L4                 │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ LAYER STACK ─────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  L5 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ Climax        │  │
│ │  L4 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░ Drive ◀ ACTIVE │  │
│ │  L3 ▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ Tension ↘     │  │
│ │  L2 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ Normal        │  │
│ │  L1 ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ Ethereal      │  │
│ │                                                                       │  │
│ │  ▓ = Active   ▒ = Fading   ░ = Inactive   ◀ = Current   ↘ = Out     │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ SIGNAL MONITOR ──────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  winTier         ████████░░░░░░░░░░░░ 4 (MEGA)        ▲ +1           │  │
│ │  winXbet         ████████████████████ 156.3x          ▲ +89.2        │  │
│ │  consecutiveWins ████░░░░░░░░░░░░░░░░ 2                              │  │
│ │  featureProgress ████████████████░░░░ 0.80            → steady       │  │
│ │  momentum        ███████████████░░░░░ 0.78            ▲ +0.12        │  │
│ │  velocity        ██████████░░░░░░░░░░ +0.31           ▲ accelerating │  │
│ │                                                                       │  │
│ │  [Show All] [Edit Signals] [Record]                                   │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ ACTIVE TRACKS ───────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  L4 ▶ fs_main_intense    ████████████████░░░░ 1.0   [S] [M]          │  │
│ │  L4 ▶ fs_bass_drive      ██████████████░░░░░░ 0.9   [S] [M]          │  │
│ │  L4 ▶ fs_perc_full       ████████████░░░░░░░░ 0.8   [S] [M]          │  │
│ │  L4 ▶ fs_celebration_bed ██████████░░░░░░░░░░ 0.6   [S] [M]          │  │
│ │  L3 ↘ fs_energy_overlay  ████░░░░░░░░░░░░░░░░ 0.2   [S] [M] fading   │  │
│ │                                                                       │  │
│ │  Total: 5 tracks   CPU: 2.3%   Memory: 45 MB                         │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ RULE ACTIVITY ───────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  ✓ fs_big_win_escalation      fired 1.2s ago    cooldown: 0.8s      │  │
│ │  ○ fs_final_spins_build       waiting (progress < 0.85)              │  │
│ │  ○ fs_multiplier_boost        waiting (multiplier < 5)               │  │
│ │  ◌ fs_retrigger_celebration   inactive                               │  │
│ │  ● HOLD ACTIVE                3.2s remaining                         │  │
│ │                                                                       │  │
│ │  [Show All Rules] [Edit Rules] [Rule Debugger]                        │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ STABILITY ───────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  Global Cooldown: ░░░░░░░░░░ inactive                                │  │
│ │  Level Hold:      ████████░░ 3.2s remaining (L4)                     │  │
│ │  Level Inertia:   1.6x (at L4)                                       │  │
│ │  Decay:           paused (hold active)                               │  │
│ │  Prediction:      L5 → 67% confidence in 2s                          │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ TOOLBAR ─────────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  [▶ Play] [⏸ Pause] [⏹ Stop] │ [↺ Reset] │ [Edit Profile] [Export]  │  │
│ │                                                                       │  │
│ │  Manual Override: [L1] [L2] [L3] [L4] [L5]    [Auto ✓]               │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Context Editor (Full)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ CONTEXT EDITOR — FREESPINS                                      [Save] [×]  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ ┌─ IDENTITY ────────────────────────────────────────────────────────────┐  │
│ │  Name: [Free Spins Feature          ]                                 │  │
│ │  ID:   [FREESPINS                   ]  (readonly)                     │  │
│ │  Description: [Triggered bonus round with awarded free spins    ]     │  │
│ │                                                                       │  │
│ │  Audio Character:                                                      │  │
│ │  Key: [E minor ▾]  Tempo: [128    ] BPM  Energy: [Epic Fantasy ▾]    │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ LAYERS ──────────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  ┌─ L1: Ethereal ─────────────────────────────────────────────────┐  │  │
│ │  │  Energy: 0.15  │  + Add Track                                   │  │  │
│ │  │                                                                 │  │  │
│ │  │  fs_ambient_pad    music/fs/L1_ambient.wav    0.7  [Edit] [×]  │  │  │
│ │  │  fs_sparkle        music/fs/L1_sparkle.wav    0.3  [Edit] [×]  │  │  │
│ │  └─────────────────────────────────────────────────────────────────┘  │  │
│ │                                                                       │  │
│ │  ┌─ L2: Foundation ───────────────────────────────────────────────┐  │  │
│ │  │  Energy: 0.35  │  + Add Track                                   │  │  │
│ │  │                                                                 │  │  │
│ │  │  fs_main_loop      music/fs/L2_main.wav       0.9  [Edit] [×]  │  │  │
│ │  │  fs_bass           music/fs/L2_bass.wav       0.6  [Edit] [×]  │  │  │
│ │  │  fs_perc_light     music/fs/L2_perc.wav       0.4  [Edit] [×]  │  │  │
│ │  └─────────────────────────────────────────────────────────────────┘  │  │
│ │                                                                       │  │
│ │  ┌─ L3: Tension ──────────────────────────────────────────────────┐  │  │
│ │  │  ... (collapsed)                                                │  │  │
│ │  └─────────────────────────────────────────────────────────────────┘  │  │
│ │                                                                       │  │
│ │  ┌─ L4: Drive ────────────────────────────────────────────────────┐  │  │
│ │  │  ... (collapsed)                                                │  │  │
│ │  └─────────────────────────────────────────────────────────────────┘  │  │
│ │                                                                       │  │
│ │  ┌─ L5: Climax ───────────────────────────────────────────────────┐  │  │
│ │  │  ... (collapsed)                                                │  │  │
│ │  └─────────────────────────────────────────────────────────────────┘  │  │
│ │                                                                       │  │
│ │  [+ Add Layer]                                                        │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ ENTRY POLICY ────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  Type: [Trigger Strength Mapping ▾]                                   │  │
│ │  Default Level: [2 ▾]   Inherit Momentum: [✓]                        │  │
│ │                                                                       │  │
│ │  ┌─ Trigger Mapping ────────────────────────────────────────────┐    │  │
│ │  │  Trigger          Start Level    Transition                  │    │  │
│ │  │  [3_scatters    ] [L2 ▾]         [feature_enter_normal ▾]   │    │  │
│ │  │  [4_scatters    ] [L3 ▾]         [feature_enter_energetic ▾]│    │  │
│ │  │  [5_scatters    ] [L4 ▾]         [feature_enter_epic ▾]     │    │  │
│ │  │  [retrigger     ] [current+1   ] [retrigger_celebration ▾]  │    │  │
│ │  │  [+ Add Mapping]                                             │    │  │
│ │  └──────────────────────────────────────────────────────────────┘    │  │
│ │                                                                       │  │
│ │  Entry Stinger: [✓] [fs_entry.wav        ] Duck: [-12 ]dB            │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ EXIT POLICY ─────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  Return To: [BASE ▾]  At Level: [L2 ▾]                               │  │
│ │                                                                       │  │
│ │  Wind-Down:                                                           │  │
│ │  [✓] Enabled  Start at: [90 ]% progress  Target: [L3 ▾]             │  │
│ │  Spins before exit: [2  ]                                             │  │
│ │                                                                       │  │
│ │  Final Transition: [feature_exit ▾]  Fade: [2500]ms  Overlap: [500]ms│  │
│ │                                                                       │  │
│ │  Summary Stinger: [✓]                                                 │  │
│ │    Small Win: [fs_exit_small.wav ]                                    │  │
│ │    Big Win:   [fs_exit_big.wav   ]                                    │  │
│ │    Mega Win:  [fs_exit_mega.wav  ]                                    │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ CONSTRAINTS ─────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  Min Level: [L2 ▾]    Max Level: [L5 ▾]                              │  │
│ │  Level Change Cooldown: [1500]ms    Max Changes/Spin: [2 ]           │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ NARRATIVE ARC ───────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  [✓] Enable Narrative Arc    Type: [Build to Climax ▾]               │  │
│ │                                                                       │  │
│ │  ┌─ Timeline ───────────────────────────────────────────────────┐    │  │
│ │  │  0%        30%        70%        90%       100%              │    │  │
│ │  │  ├──────────┼──────────┼──────────┼──────────┤              │    │  │
│ │  │  │ OPENING  │ DEVELOP  │  BUILD   │ CLIMAX  │              │    │  │
│ │  │  │ bias: 0  │ bias: 0  │ bias: +1 │ bias: +2│              │    │  │
│ │  │  │          │          │ min: L3  │ min: L4 │              │    │  │
│ │  │  └──────────┴──────────┴──────────┴──────────┘              │    │  │
│ │  └──────────────────────────────────────────────────────────────┘    │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│                                                                             │
│ [Revert Changes]                        [Test Context] [Save & Close]      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Rule Editor (Visual)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ RULE EDITOR — fs_big_win_escalation                             [Save] [×]  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ ┌─ IDENTITY ────────────────────────────────────────────────────────────┐  │
│ │  Name: [Big Win Escalation                    ]                       │  │
│ │  ID:   fs_big_win_escalation  (readonly)                              │  │
│ │  [✓] Enabled    Priority: [100    ]                                   │  │
│ │                                                                       │  │
│ │  Contexts: [FREESPINS ×] [+ Add Context]                             │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ CONDITION (Visual Builder) ──────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  ┌──────────────────────────────────────────────────────────────┐    │  │
│ │  │                           OR                                  │    │  │
│ │  │  ┌─────────────────────┐   ┌───────────────────────────────┐ │    │  │
│ │  │  │ winTier >= 3        │   │             AND               │ │    │  │
│ │  │  │                     │   │ ┌─────────────┐ ┌───────────┐ │ │    │  │
│ │  │  │ [Edit] [×]          │   │ │winXbet >= 15│ │consec >= 2│ │ │    │  │
│ │  │  └─────────────────────┘   │ │[Edit] [×]   │ │[Edit] [×] │ │ │    │  │
│ │  │                            │ └─────────────┘ └───────────┘ │ │    │  │
│ │  │                            │     [+ Add]                   │ │    │  │
│ │  │                            └───────────────────────────────┘ │    │  │
│ │  │                               [+ Add Branch]                  │    │  │
│ │  └──────────────────────────────────────────────────────────────┘    │  │
│ │                                                                       │  │
│ │  [Switch to JSON] [Validate]                                          │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ ACTION ──────────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  Type: [Step Up ▾]                                                    │  │
│ │  Steps: [1  ]    Max Level: [L5 ▾]    [✓] Allow Skip Levels          │  │
│ │                                                                       │  │
│ │  Preview: Current L3 → Target L4                                      │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ TRANSITION ──────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  Profile: [upshift_energetic ▾]   [Edit Profile]                     │  │
│ │                                                                       │  │
│ │  Sync Mode: [Beat ▾]    Max Wait: [500 ]ms                           │  │
│ │                                                                       │  │
│ │  Preview:                                                              │  │
│ │  ├─ Fade In: 250ms ease_out_quad                                      │  │
│ │  ├─ Fade Out: 200ms ease_in_quad                                      │  │
│ │  ├─ Overlap: 100ms                                                     │  │
│ │  └─ Ducking: SFX -4dB                                                  │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ STABILITY ───────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  Cooldown: [2000]ms    Hold: [4000]ms                                │  │
│ │  [✓] Requires Hold Expired                                            │  │
│ │                                                                       │  │
│ │  Timeline:                                                             │  │
│ │  ├───[FIRE]───[========HOLD (4s)========]───[==COOLDOWN (2s)==]──▶   │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ SIDE EFFECTS ────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  [✓] Trigger Stinger (when winTier >= 4)                             │  │
│ │      Path: [stingers/win_escalation.wav]  Volume: [0.7 ]             │  │
│ │                                                                       │  │
│ │  [✓] Emit Event: [ALE_LEVEL_UP        ]                              │  │
│ │                                                                       │  │
│ │  [ ] Update Momentum: [    ]                                          │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ ┌─ DEBUG ───────────────────────────────────────────────────────────────┐  │
│ │                                                                       │  │
│ │  [✓] Log Evaluation    [✓] Highlight in UI    [ ] Break on Fire      │  │
│ │                                                                       │  │
│ └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│ [Duplicate Rule] [Delete Rule]               [Test Rule] [Save & Close]    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Part X: Data Persistence & Versioning

### Profile File Format

```json
{
  "version": "2.0",
  "format": "ale_profile",
  "created": "2026-01-20T14:30:00Z",
  "modified": "2026-01-20T16:45:00Z",
  "author": "Audio Designer",

  "metadata": {
    "game_name": "Mystic Treasures",
    "game_id": "mystic_treasures_001",
    "target_platform": ["desktop", "mobile"],
    "audio_budget_mb": 150
  },

  "contexts": { ... },
  "rules": [ ... ],
  "transitions": { ... },
  "stability": { ... },

  "asset_manifest": {
    "tracks": [
      { "id": "fs_main_loop", "path": "music/fs/L2_main.wav", "size_bytes": 4521984 },
      ...
    ],
    "stingers": [
      { "id": "fs_entry", "path": "stingers/fs_entry.wav", "size_bytes": 245760 },
      ...
    ]
  }
}
```

### Version Migration

```rust
pub fn migrate_profile(json: &str) -> Result<Profile, MigrationError> {
    let raw: serde_json::Value = serde_json::from_str(json)?;

    let version = raw["version"].as_str().unwrap_or("1.0");

    match version {
        "1.0" => migrate_v1_to_v2(raw),
        "2.0" => Ok(serde_json::from_value(raw)?),
        _ => Err(MigrationError::UnknownVersion(version.to_string())),
    }
}

fn migrate_v1_to_v2(mut v1: serde_json::Value) -> Result<Profile, MigrationError> {
    // Add new required fields with defaults
    if v1["stability"]["prediction"].is_null() {
        v1["stability"]["prediction"] = serde_json::json!({
            "enabled": false,
            "horizon_ms": 2000,
            "confidence_threshold": 0.7
        });
    }

    // Rename deprecated fields
    if let Some(old_name) = v1["contexts"]["BASE"]["fade_time_ms"].take() {
        v1["contexts"]["BASE"]["transition"]["fade"]["in"]["duration_ms"] = old_name;
    }

    v1["version"] = serde_json::json!("2.0");

    Ok(serde_json::from_value(v1)?)
}
```

---

## Part XI: Testing & Validation

### Signal Simulation

```dart
class SignalSimulator {
  final LayerEngineProvider _engine;

  /// Simulate a typical base game session
  Future<void> simulateBaseGameSession() async {
    // Spin 1: Small win
    _engine.updateSignals({'winTier': 1, 'winXbet': 2.5});
    await Future.delayed(Duration(seconds: 3));

    // Spin 2: Loss
    _engine.updateSignals({'winTier': 0, 'winXbet': 0, 'spinsSinceWin': 1});
    await Future.delayed(Duration(seconds: 3));

    // Spin 3: Loss
    _engine.updateSignals({'spinsSinceWin': 2});
    await Future.delayed(Duration(seconds: 3));

    // Spin 4: Big win
    _engine.updateSignals({
      'winTier': 3,
      'winXbet': 45.0,
      'spinsSinceWin': 0,
      'consecutiveWins': 1,
    });
    await Future.delayed(Duration(seconds: 5));

    // ... continue simulation
  }

  /// Simulate free spins feature
  Future<void> simulateFreeSpins({int totalSpins = 10}) async {
    _engine.switchContext('FREESPINS', trigger: '4_scatters');

    for (int i = 0; i < totalSpins; i++) {
      final progress = (i + 1) / totalSpins;
      final hasWin = Random().nextDouble() < 0.45;

      _engine.updateSignals({
        'featureProgress': progress,
        'winTier': hasWin ? Random().nextInt(4) + 1 : 0,
        'winXbet': hasWin ? Random().nextDouble() * 50 : 0,
      });

      await Future.delayed(Duration(seconds: 3));
    }
  }
}
```

### Automated Tests

```dart
void main() {
  group('Rule Evaluation', () {
    test('win_escalation fires on big win', () {
      final engine = TestableLayerEngine();
      engine.loadProfile(testProfile);
      engine.setContext('BASE');
      engine.setLevel(2);

      engine.updateSignals({'winTier': 3, 'winXbet': 25.0});
      engine.tick();

      expect(engine.currentLevel, equals(3));
      expect(engine.lastFiredRule, equals('win_escalation'));
    });

    test('cooldown prevents rapid firing', () {
      final engine = TestableLayerEngine();
      engine.loadProfile(testProfile);
      engine.setContext('BASE');
      engine.setLevel(2);

      // First trigger
      engine.updateSignals({'winTier': 3});
      engine.tick();
      expect(engine.currentLevel, equals(3));

      // Immediate second trigger (should be blocked)
      engine.updateSignals({'winTier': 4});
      engine.tick();
      expect(engine.currentLevel, equals(3)); // Still 3, cooldown active

      // After cooldown
      engine.advanceTime(Duration(milliseconds: 2000));
      engine.updateSignals({'winTier': 4});
      engine.tick();
      expect(engine.currentLevel, equals(4)); // Now 4
    });

    test('hold prevents downward movement', () {
      final engine = TestableLayerEngine();
      engine.loadProfile(testProfile);
      engine.setContext('BASE');
      engine.setLevel(3);
      engine.setHold(Duration(seconds: 5));

      engine.updateSignals({'spinsSinceWin': 10});
      engine.tick();

      expect(engine.currentLevel, equals(3)); // Hold active, no change
    });
  });

  group('Transitions', () {
    test('beat_sync waits for next beat', () {
      final engine = TestableLayerEngine();
      engine.setBpm(120); // 500ms per beat
      engine.setBeatPosition(0.7); // 70% through current beat

      final transition = engine.createTransition(
        from: 2,
        to: 3,
        profile: 'upshift',
      );

      expect(transition.waitTime.inMilliseconds, closeTo(150, 20)); // ~30% of beat
    });
  });
}
```

---

## Part XII: Integration API

### FFI Bridge (Complete)

```c
// Lifecycle
int32_t ale_init();
void ale_shutdown();
int32_t ale_is_initialized();

// Profile Management
int32_t ale_load_profile_json(const char* json);
int32_t ale_load_profile_file(const char* path);
char* ale_get_profile_json();
char* ale_validate_profile(const char* json);

// Context
void ale_switch_context(const char* context_id, const char* trigger);
char* ale_get_current_context();
char* ale_list_contexts();

// Signals
void ale_update_signals_json(const char* json);
void ale_update_signal(const char* name, double value);
char* ale_get_signals_json();

// Level Control
void ale_force_level(int32_t level);
int32_t ale_get_current_level();
int32_t ale_get_target_level();
double ale_get_transition_progress();

// Playback State
char* ale_get_active_tracks_json();
char* ale_get_layer_state_json();

// Rules
char* ale_get_rules_json();
char* ale_get_rule_activity_json();
int32_t ale_test_rule(const char* rule_json, const char* signals_json);

// Stability
char* ale_get_stability_state_json();
void ale_pause_decay();
void ale_resume_decay();

// Debug
void ale_enable_debug_logging(int32_t enabled);
char* ale_get_debug_log();
void ale_set_manual_override(int32_t enabled);
```

### Dart Provider

```dart
class AdaptiveLayerProvider extends ChangeNotifier {
  // State
  String _currentContext = 'BASE';
  int _currentLevel = 2;
  int _targetLevel = 2;
  double _transitionProgress = 0.0;
  Map<String, double> _signals = {};
  List<ActiveTrack> _activeTracks = [];
  List<RuleActivity> _ruleActivity = [];
  StabilityState _stability = StabilityState();

  // Getters
  String get currentContext => _currentContext;
  int get currentLevel => _currentLevel;
  int get targetLevel => _targetLevel;
  double get transitionProgress => _transitionProgress;
  bool get isTransitioning => _transitionProgress > 0 && _transitionProgress < 1;
  Map<String, double> get signals => Map.unmodifiable(_signals);
  List<ActiveTrack> get activeTracks => List.unmodifiable(_activeTracks);
  List<RuleActivity> get ruleActivity => List.unmodifiable(_ruleActivity);
  StabilityState get stability => _stability;

  // Profile Management
  Future<bool> loadProfile(String json) async { ... }
  Future<bool> loadProfileFromFile(String path) async { ... }
  String exportProfile() { ... }
  ValidationResult validateProfile(String json) { ... }

  // Context Control
  void switchContext(String contextId, {String? trigger}) {
    _nativeFfi.ale_switch_context(contextId, trigger);
    _pollState();
  }

  // Signal Updates
  void updateSignals(Map<String, double> updates) {
    _nativeFfi.ale_update_signals_json(jsonEncode(updates));
    _signals.addAll(updates);
    _pollState();
    notifyListeners();
  }

  void updateSignal(String name, double value) {
    _nativeFfi.ale_update_signal(name, value);
    _signals[name] = value;
    _pollState();
    notifyListeners();
  }

  // Manual Override
  void forceLevel(int level) {
    _nativeFfi.ale_force_level(level);
    _pollState();
  }

  // Polling (call from tick)
  void _pollState() {
    final stateJson = _nativeFfi.ale_get_layer_state_json();
    final state = jsonDecode(stateJson);

    _currentContext = state['context'];
    _currentLevel = state['level'];
    _targetLevel = state['target_level'];
    _transitionProgress = state['transition_progress'];

    _activeTracks = (state['active_tracks'] as List)
        .map((t) => ActiveTrack.fromJson(t))
        .toList();

    _ruleActivity = (state['rule_activity'] as List)
        .map((r) => RuleActivity.fromJson(r))
        .toList();

    _stability = StabilityState.fromJson(state['stability']);

    notifyListeners();
  }
}
```

---

## Summary

The Adaptive Layer Engine v2.0 is the **ultimate slot-native layering system**:

### Completeness Checklist

| Category | Feature | Status |
|----------|---------|--------|
| **Signals** | 18+ built-in signals | ✅ |
| **Signals** | Derived/normalized signals | ✅ |
| **Signals** | Custom user signals | ✅ |
| **Signals** | Signal history tracking | ✅ |
| **Contexts** | 9 built-in templates | ✅ |
| **Contexts** | Custom context definition | ✅ |
| **Contexts** | Entry/Exit policies | ✅ |
| **Contexts** | Narrative arc system | ✅ |
| **Contexts** | Stinger support | ✅ |
| **Layers** | 1-6 layers per context | ✅ |
| **Layers** | Track-level control | ✅ |
| **Layers** | Sync groups | ✅ |
| **Layers** | Per-layer bus routing | ✅ |
| **Rules** | 16 condition operators | ✅ |
| **Rules** | Compound conditions (AND/OR/NOT) | ✅ |
| **Rules** | Temporal conditions | ✅ |
| **Rules** | Sequence detection | ✅ |
| **Rules** | 6 action types | ✅ |
| **Rules** | Priority system | ✅ |
| **Rules** | Side effects | ✅ |
| **Transitions** | 6 sync modes | ✅ |
| **Transitions** | 10 fade curves | ✅ |
| **Transitions** | Ducking integration | ✅ |
| **Transitions** | Filter/pitch effects | ✅ |
| **Stability** | Cooldown | ✅ |
| **Stability** | Hold | ✅ |
| **Stability** | Hysteresis | ✅ |
| **Stability** | Level inertia | ✅ |
| **Stability** | Decay | ✅ |
| **Stability** | Momentum buffer | ✅ |
| **Stability** | Prediction | ✅ |
| **Performance** | Lock-free RT core | ✅ |
| **Performance** | SIMD mixing | ✅ |
| **Performance** | Zero-alloc playback | ✅ |
| **Performance** | Pre-allocated memory | ✅ |
| **UI** | Main panel | ✅ |
| **UI** | Context editor | ✅ |
| **UI** | Rule editor (visual) | ✅ |
| **UI** | Real-time visualization | ✅ |
| **Persistence** | JSON profile format | ✅ |
| **Persistence** | Version migration | ✅ |
| **Testing** | Signal simulation | ✅ |
| **Testing** | Unit tests | ✅ |
| **Integration** | FFI bridge (30+ functions) | ✅ |
| **Integration** | Dart provider | ✅ |
| **Integration** | Slot Lab integration | ✅ |

### What This Enables

1. **Audio designers** can create sophisticated reactive music without code
2. **Game developers** only emit signals — ALE handles the rest
3. **QA teams** can test deterministically with signal simulation
4. **Localization** — same profiles work across games (data-driven)
5. **Performance** — professional lock-free real-time architecture

### The Ultimate Transformation

**Before ALE:**
```
IF scatter_count >= 3 THEN play("fs_music.wav")
IF win_amount > 100 THEN play("big_win.wav")
```

**After ALE:**
```
SIGNALS → RULES → STABILITY → TRANSITIONS → LAYERS
```

You no longer think about **what to play**.
You think about **what the game feels like**.

And the system makes it sound right.

---

**This is the ultimate. There is no further to go.**
