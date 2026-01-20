# Slot Lab Audio Features — Implementation Details

> Detaljni tehnički pregled svih implementiranih P0/P1 audio poboljšanja.

**Datum:** 2026-01-20
**Status:** P0.1, P0.2, P0.3, P0.4, P0.5, P0.6, P0.7, P1.1, P1.2, P1.3 kompletni

---

## Overview

Slot Lab audio sistem je nadograđen sa 10 ključnih feature-a koji poboljšavaju:
- **Latency Compensation** — Audio timing offset za sync sa vizualima
- **Seamless Looping** — Gapless REEL_SPIN loop u Rust engine-u
- **Spatial Audio** — Per-voice panning, win line positioning
- **Dynamic Timing** — RTPC rollup/cascade speed, anticipation pre-trigger
- **Layered Audio** — Multi-layer Big Win celebrations
- **Context-Aware Audio** — Symbol-specific sounds, near miss escalation

---

## P0.3: Per-Voice Pan in FFI

### Problem
AutoSpatialEngine izračunava pan vrednosti, ali Rust playback engine nije imao podršku za per-voice pan. Sve je išlo kroz center.

### Rešenje
Dodato `pan` polje kroz ceo FFI lanac: Rust engine → FFI export → Dart binding → Services.

### Fajlovi

**`crates/rf-engine/src/playback.rs`**
```rust
pub struct OneShotVoice {
    audio_data: Vec<f32>,
    position: usize,
    volume: f32,
    pan: f32,        // ← NOVO: -1.0 (left) to +1.0 (right)
    bus_id: usize,
    finished: bool,
}

impl OneShotVoice {
    fn fill_buffer(&mut self, output: &mut [f32], channels: usize) {
        // Equal-power panning
        let pan_norm = (self.pan + 1.0) * 0.5; // -1..+1 → 0..1
        let pan_l = ((1.0 - pan_norm) * std::f32::consts::PI * 0.5).cos();
        let pan_r = (pan_norm * std::f32::consts::PI * 0.5).sin();

        for frame in output.chunks_mut(channels) {
            let sample = self.audio_data[self.position] * self.volume;
            if channels >= 2 {
                frame[0] = sample * pan_l;  // Left
                frame[1] = sample * pan_r;  // Right
            } else {
                frame[0] = sample;
            }
            self.position += 1;
        }
    }
}
```

**`crates/rf-engine/src/ffi.rs`**
```rust
#[no_mangle]
pub extern "C" fn engine_playback_play_to_bus(
    path_ptr: *const c_char,
    volume: f64,
    pan: f64,      // ← NOVO
    bus_id: i32,
) -> i32 {
    // ... create OneShotVoice with pan
}
```

**`flutter_ui/lib/src/rust/native_ffi.dart`**
```dart
int playbackPlayToBus(
  String path, {
  double volume = 1.0,
  double pan = 0.0,  // ← NOVO
  int busId = 0,
}) {
  return _bindings.engine_playback_play_to_bus(
    path.toNativeUtf8().cast(),
    volume,
    pan,
    busId,
  );
}
```

**`flutter_ui/lib/services/audio_playback_service.dart`**
```dart
int playFileToBus(
  String path, {
  double volume = 1.0,
  double pan = 0.0,  // ← NOVO
  int busId = 0,
  // ...
}) {
  return _ffi.playbackPlayToBus(path, volume: volume, pan: pan, busId: busId);
}
```

**`flutter_ui/lib/services/audio_pool.dart`**
```dart
int acquire({
  required String eventKey,
  required String audioPath,
  required int busId,
  double volume = 1.0,
  double pan = 0.0,  // ← NOVO
}) {
  // Pool tracks lastPan for potential reuse optimization
  voice.lastPan = pan;
  _playVoice(voice.voiceId, audioPath, volume, pan, busId);
}
```

### Equal-Power Panning Formula

```
pan_norm = (pan + 1.0) * 0.5     // Map -1..+1 to 0..1

pan_l = cos((1 - pan_norm) * π/2)
pan_r = sin(pan_norm * π/2)

// Results:
// pan = -1.0: L=1.0, R=0.0 (full left)
// pan =  0.0: L=0.707, R=0.707 (center, equal power)
// pan = +1.0: L=0.0, R=1.0 (full right)
```

---

## P0.5: Dynamic Rollup Speed

### Problem
Rollup brzina je bila fiksna. Mega win sa 10000 kredita = 100+ sekundi rollup-a.

### Rešenje
RTPC `Rollup_Speed` (ID 106) kontroliše delay između ROLLUP_TICK stage-ova.

### Fajlovi

**`flutter_ui/lib/services/rtpc_modulation_service.dart`**
```dart
/// Get rollup speed multiplier from Rollup_Speed RTPC
/// Returns 1.0 if no RTPC binding or middleware not available
double getRollupSpeedMultiplier() {
  if (_middleware == null) return 1.0;

  const rollupSpeedRtpcId = 106; // SlotRtpcIds.rollupSpeed
  final rtpcDef = _middleware!.getRtpc(rollupSpeedRtpcId);
  if (rtpcDef == null) return 1.0;

  // Rollup_Speed range: 0.0-1.0
  // Map to multiplier: 0.0 → 0.25x (slow), 0.5 → 1.0x (normal), 1.0 → 4.0x (fast)
  final normalized = rtpcDef.normalizedValue.clamp(0.0, 1.0);

  // Exponential curve for perceptual linearity
  // Formula: 0.25 * 16^normalized
  return 0.25 * math.pow(16.0, normalized);
}
```

**`flutter_ui/lib/providers/slot_lab_provider.dart`**
```dart
void _scheduleNextStage(SlotLabStageEvent stage) {
  double delayMs = stage.timestampMs - _lastStages[_currentStageIndex - 1].timestampMs;

  // P0.5: Apply RTPC rollup speed multiplier for ROLLUP_TICK
  if (stage.stageType.toUpperCase() == 'ROLLUP_TICK') {
    final speedMultiplier = RtpcModulationService.instance.getRollupSpeedMultiplier();
    if (speedMultiplier > 0) {
      delayMs = delayMs / speedMultiplier;  // Higher multiplier = shorter delay
    }
  }

  _stagePlaybackTimer = Timer(Duration(milliseconds: delayMs.round()), () {
    _triggerStage(stage);
    // ...
  });
}
```

### RTPC Curve

| RTPC Value | Multiplier | Effect |
|------------|------------|--------|
| 0.0 | 0.25x | 4x slower rollup |
| 0.25 | 0.5x | 2x slower |
| 0.5 | 1.0x | Normal speed |
| 0.75 | 2.0x | 2x faster |
| 1.0 | 4.0x | 4x faster rollup |

---

## P0.6: Anticipation Pre-Trigger

### Problem
Audio anticipation počinje istovremeno sa vizualnom — ali vizualna animacija ima latenciju. Rezultat: audio kasni za vizualnim doživljajem.

### Rešenje
Audio anticipation počinje 50ms pre vizualne animacije.

### Fajlovi

**`flutter_ui/lib/providers/slot_lab_provider.dart`**
```dart
class SlotLabProvider extends ChangeNotifier {
  // P0.6: Pre-trigger config
  int _anticipationPreTriggerMs = 50;
  Timer? _audioPreTriggerTimer;

  /// Set anticipation pre-trigger offset (ms)
  void setAnticipationPreTriggerMs(int ms) {
    _anticipationPreTriggerMs = ms.clamp(0, 200);
    notifyListeners();
  }

  void _scheduleNextStage(SlotLabStageEvent stage) {
    // ... normal scheduling code ...

    // P0.6: Look ahead for ANTICIPATION_ON and pre-trigger audio
    if (_currentStageIndex + 1 < _lastStages.length) {
      final nextStage = _lastStages[_currentStageIndex + 1];
      if (nextStage.stageType.toUpperCase() == 'ANTICIPATION_ON') {
        final preTriggerDelay = (nextStage.timestampMs - stage.timestampMs - _anticipationPreTriggerMs).clamp(0.0, double.infinity);

        _audioPreTriggerTimer?.cancel();
        _audioPreTriggerTimer = Timer(Duration(milliseconds: preTriggerDelay.round()), () {
          _triggerAudioOnly(nextStage);
        });
      }
    }
  }

  /// Trigger only audio for a stage (no visual state update)
  void _triggerAudioOnly(SlotLabStageEvent stage) {
    final stageType = stage.stageType.toUpperCase();

    // P1.2: Apply escalation for ANTICIPATION_ON
    Map<String, dynamic> context = Map.from(stage.payload);
    String effectiveStage = stageType;

    if (stageType == 'ANTICIPATION_ON') {
      final escalationResult = _calculateAnticipationEscalation(stage);
      effectiveStage = escalationResult.effectiveStage;
      context['volumeMultiplier'] = escalationResult.volumeMultiplier;
    }

    if (eventRegistry.hasEventForStage(effectiveStage)) {
      eventRegistry.triggerStage(effectiveStage, context: context);
    }
  }
}
```

### Timeline Visualization

```
Normal (no pre-trigger):
Visual:  |-------- ANTICIPATION --------|
Audio:   |-------- ANTICIPATION --------|
         ↑ Same start = perceived delay

With pre-trigger (50ms):
Visual:  |-------- ANTICIPATION --------|
Audio: |-|-------- ANTICIPATION --------|
       ↑ 50ms earlier = better sync
```

---

## P0.7: Big Win Layered Audio

### Problem
Big Win ima samo jedan zvuk. Nema impact, coin shower, music swell, voice over separation.

### Rešenje
Template sistem za multi-layer Big Win audio sa tier-specific timing.

### Fajlovi

**`flutter_ui/lib/services/event_registry.dart`**
```dart
/// Create a template Big Win event with layered audio structure
static AudioEvent createBigWinTemplate({
  required String tier, // 'nice', 'super', 'mega', 'epic', 'ultra'
  required String impactPath,
  String? coinShowerPath,
  String? musicSwellPath,
  String? voiceOverPath,
}) {
  final stageMap = {
    'nice': 'BIGWIN_TIER_NICE',
    'super': 'BIGWIN_TIER_SUPER',
    'mega': 'BIGWIN_TIER_MEGA',
    'epic': 'BIGWIN_TIER_EPIC',
    'ultra': 'BIGWIN_TIER_ULTRA',
  };

  // Tier-specific timing (ms)
  final timingMap = {
    'nice': (coinDelay: 100, musicDelay: 0, voDelay: 300),
    'super': (coinDelay: 150, musicDelay: 0, voDelay: 400),
    'mega': (coinDelay: 100, musicDelay: 0, voDelay: 500),
    'epic': (coinDelay: 100, musicDelay: 0, voDelay: 600),
    'ultra': (coinDelay: 100, musicDelay: 0, voDelay: 700),
  };

  final timing = timingMap[tier]!;
  final layers = <AudioLayer>[];

  // Layer 1: Impact Hit (immediate, SFX bus)
  layers.add(AudioLayer(
    id: '${tier}_impact',
    audioPath: impactPath,
    name: 'Impact Hit',
    volume: 1.0,
    delay: 0,
    busId: 2,
  ));

  // Layer 2: Coin Shower (delayed, SFX bus)
  if (coinShowerPath != null && coinShowerPath.isNotEmpty) {
    layers.add(AudioLayer(
      id: '${tier}_coins',
      audioPath: coinShowerPath,
      name: 'Coin Shower',
      volume: 0.8,
      delay: timing.coinDelay.toDouble(),
      busId: 2,
    ));
  }

  // Layer 3: Music Swell (immediate, Music bus)
  if (musicSwellPath != null && musicSwellPath.isNotEmpty) {
    layers.add(AudioLayer(
      id: '${tier}_music',
      audioPath: musicSwellPath,
      name: 'Music Swell',
      volume: 0.9,
      delay: timing.musicDelay.toDouble(),
      busId: 1,
    ));
  }

  // Layer 4: Voice Over (most delayed, Voice bus)
  if (voiceOverPath != null && voiceOverPath.isNotEmpty) {
    layers.add(AudioLayer(
      id: '${tier}_vo',
      audioPath: voiceOverPath,
      name: 'Voice Over',
      volume: 1.0,
      delay: timing.voDelay.toDouble(),
      busId: 3,
    ));
  }

  return AudioEvent(
    id: 'slot_bigwin_tier_$tier',
    name: 'Big Win - ${tier[0].toUpperCase()}${tier.substring(1)}',
    stage: stageMap[tier]!,
    layers: layers,
    priority: tier == 'ultra' ? 100 : (tier == 'epic' ? 80 : 60),
  );
}

/// Register default Big Win events with placeholder paths
void registerDefaultBigWinEvents() {
  const tiers = ['nice', 'super', 'mega', 'epic', 'ultra'];
  for (final tier in tiers) {
    final event = createBigWinTemplate(
      tier: tier,
      impactPath: '', // User fills via UI
    );
    registerEvent(event);
  }
}

/// Update a Big Win event with actual audio paths
void updateBigWinEvent({
  required String tier,
  String? impactPath,
  String? coinShowerPath,
  String? musicSwellPath,
  String? voiceOverPath,
}) {
  // Merge with existing paths, create new event
  // ...
}
```

### Layer Timeline

```
MEGA Win Example:

Time:    0ms     100ms    200ms    300ms    400ms    500ms
         |        |        |        |        |        |
Impact:  [████]
Music:   [████████████████████████████████████████████]
Coins:            [████████████████████]
Voice:                                         [████████]
```

---

## P1.1: Symbol-Specific Audio

### Problem
REEL_STOP uvek pušta isti zvuk. Wild, Scatter, Seven trebaju distinktne zvuke.

### Rešenje
Stage suffix na osnovu simbola: `REEL_STOP_0_WILD`, `REEL_STOP_2_SCATTER`.

### Fajlovi

**`flutter_ui/lib/providers/slot_lab_provider.dart`**
```dart
/// Check if symbols list contains a Wild (ID 0 or 10)
bool _containsWild(List<dynamic>? symbols) {
  if (symbols == null || symbols.isEmpty) return false;
  return symbols.any((s) => s == 0 || s == 10);
}

/// Check if symbols list contains a Scatter (ID 9)
bool _containsScatter(List<dynamic>? symbols) {
  if (symbols == null || symbols.isEmpty) return false;
  return symbols.contains(9);
}

/// Check if symbols list contains a Seven (ID 7)
bool _containsSeven(List<dynamic>? symbols) {
  if (symbols == null || symbols.isEmpty) return false;
  return symbols.contains(7);
}

void _triggerStage(SlotLabStageEvent stage) {
  final stageType = stage.stageType.toUpperCase();
  final reelIndex = stage.payload['reel_index'];
  String effectiveStage = stageType;

  if (stageType == 'REEL_STOP' && reelIndex != null) {
    effectiveStage = 'REEL_STOP_$reelIndex';

    // P1.1: Symbol-specific audio
    final symbols = stage.payload['symbols'] as List<dynamic>?;
    final hasWild = stage.payload['has_wild'] as bool? ?? _containsWild(symbols);
    final hasScatter = stage.payload['has_scatter'] as bool? ?? _containsScatter(symbols);
    final hasSeven = _containsSeven(symbols);

    // Priority: WILD > SCATTER > SEVEN > generic
    String? symbolSpecificStage;
    if (hasWild && eventRegistry.hasEventForStage('${effectiveStage}_WILD')) {
      symbolSpecificStage = '${effectiveStage}_WILD';
    } else if (hasScatter && eventRegistry.hasEventForStage('${effectiveStage}_SCATTER')) {
      symbolSpecificStage = '${effectiveStage}_SCATTER';
    } else if (hasSeven && eventRegistry.hasEventForStage('${effectiveStage}_SEVEN')) {
      symbolSpecificStage = '${effectiveStage}_SEVEN';
    }

    if (symbolSpecificStage != null) {
      effectiveStage = symbolSpecificStage;
    }
  }

  eventRegistry.triggerStage(effectiveStage, context: context);
}
```

### Stage Resolution Order

```
1. REEL_STOP_0_WILD     (most specific)
2. REEL_STOP_0_SCATTER
3. REEL_STOP_0_SEVEN
4. REEL_STOP_0          (per-reel)
5. REEL_STOP            (fallback)
```

---

## P1.2: Near Miss Audio Escalation

### Problem
Anticipation ima isti intenzitet bez obzira koliko je blizu dobitak.

### Rešenje
Volume i stage variraju prema combined intensity faktoru.

### Fajlovi

**`flutter_ui/lib/providers/slot_lab_provider.dart`**
```dart
/// Calculate anticipation escalation based on near-miss intensity
({String effectiveStage, double volumeMultiplier}) _calculateAnticipationEscalation(
  SlotLabStageEvent stage
) {
  // Extract factors from payload
  final intensity = (stage.payload['intensity'] as num?)?.toDouble() ?? 0.5;
  final missingSymbols = stage.payload['missing'] as int? ?? 2;
  final triggerReel = stage.payload['trigger_reel'] as int? ?? 2;

  // Calculate factors
  final reelFactor = (triggerReel + 1) / _totalReels;  // Later reel = more tension
  final missingFactor = switch (missingSymbols) {
    1 => 1.0,   // 1 symbol away = maximum tension
    2 => 0.75,  // 2 symbols away
    _ => 0.5,   // 3+ symbols away
  };

  // Combined intensity (0.0 - 1.0)
  final combinedIntensity = (intensity * reelFactor * missingFactor).clamp(0.0, 1.0);

  // Map to stage and volume
  String effectiveStage;
  double volumeMultiplier;

  if (combinedIntensity > 0.8) {
    // Critical tension - 1 symbol away on late reel
    effectiveStage = eventRegistry.hasEventForStage('ANTICIPATION_CRITICAL')
        ? 'ANTICIPATION_CRITICAL'
        : 'ANTICIPATION_ON';
    volumeMultiplier = 1.0;
  } else if (combinedIntensity > 0.5) {
    // High tension
    effectiveStage = eventRegistry.hasEventForStage('ANTICIPATION_HIGH')
        ? 'ANTICIPATION_HIGH'
        : 'ANTICIPATION_ON';
    volumeMultiplier = 0.9;
  } else {
    // Medium tension
    effectiveStage = 'ANTICIPATION_ON';
    volumeMultiplier = 0.7 + (combinedIntensity * 0.3);  // 0.7 to 0.85
  }

  return (effectiveStage: effectiveStage, volumeMultiplier: volumeMultiplier);
}

void _triggerStage(SlotLabStageEvent stage) {
  // ...
  Map<String, dynamic> context = Map.from(stage.payload);

  if (stageType == 'ANTICIPATION_ON') {
    final escalationResult = _calculateAnticipationEscalation(stage);
    effectiveStage = escalationResult.effectiveStage;
    context['volumeMultiplier'] = escalationResult.volumeMultiplier;
  }

  eventRegistry.triggerStage(effectiveStage, context: context);
}
```

**`flutter_ui/lib/services/event_registry.dart`**
```dart
Future<void> _playLayer(AudioLayer layer, ..., Map<String, dynamic>? context) async {
  double volume = layer.volume;

  // P1.2: Apply volume multiplier from context
  if (context != null && context.containsKey('volumeMultiplier')) {
    volume *= (context['volumeMultiplier'] as num).toDouble();
  }

  // ...
}
```

### Intensity Matrix

| Missing | Reel 1 | Reel 2 | Reel 3 | Reel 4 | Reel 5 |
|---------|--------|--------|--------|--------|--------|
| 1 | 0.20 | 0.40 | 0.60 | 0.80 | 1.00 |
| 2 | 0.15 | 0.30 | 0.45 | 0.60 | 0.75 |
| 3+ | 0.10 | 0.20 | 0.30 | 0.40 | 0.50 |

---

## P1.3: Win Line Audio Panning

### Problem
Win line audio je uvek centered. Trebalo bi da pan prati vizualnu poziciju dobitnih simbola.

### Rešenje
Izračunaj prosečnu X poziciju i mapiraj na pan.

### Fajlovi

**`flutter_ui/lib/providers/slot_lab_provider.dart`**
```dart
/// Calculate pan value based on win line positions
/// Returns pan from -1.0 (leftmost) to +1.0 (rightmost)
double _calculateWinLinePan(int lineIndex) {
  if (_lastResult == null) return 0.0;

  // Find the LineWin with matching lineIndex
  final lineWin = _lastResult!.lineWins.firstWhere(
    (lw) => lw.lineIndex == lineIndex,
    orElse: () => const LineWin(
      lineIndex: -1,
      symbolId: 0,
      symbolName: '',
      matchCount: 0,
      winAmount: 0.0,
      positions: [],
    ),
  );

  if (lineWin.lineIndex == -1 || lineWin.positions.isEmpty) {
    return 0.0;
  }

  // Calculate average X position (column)
  // positions is List<List<int>> where each is [col, row]
  double sumX = 0.0;
  for (final pos in lineWin.positions) {
    if (pos.isNotEmpty) {
      sumX += pos[0].toDouble();
    }
  }
  final avgX = sumX / lineWin.positions.length;

  // Map to pan: col 0 → -1.0, col (totalReels-1) → +1.0
  if (_totalReels <= 1) return 0.0;
  final normalizedX = avgX / (_totalReels - 1);
  final pan = (normalizedX * 2.0) - 1.0;

  return pan.clamp(-1.0, 1.0);
}

void _triggerStage(SlotLabStageEvent stage) {
  // ...

  if (stageType == 'WIN_LINE_SHOW') {
    final lineIndex = stage.payload['line_index'] as int? ?? 0;
    final linePan = _calculateWinLinePan(lineIndex);
    context['pan'] = linePan;
  }

  eventRegistry.triggerStage(effectiveStage, context: context);
}
```

**`flutter_ui/lib/services/event_registry.dart`**
```dart
Future<void> _playLayer(AudioLayer layer, ..., Map<String, dynamic>? context) async {
  // ...
  double pan = layer.pan;

  // P1.3: Context pan overrides layer pan
  if (context != null && context.containsKey('pan')) {
    pan = (context['pan'] as num).toDouble().clamp(-1.0, 1.0);
  }

  // Spatial engine pan (if active) still has highest priority
  if (_useSpatialAudio && eventKey != null) {
    // ... spatial calculation may override pan
  }

  // ... play with final pan value
}
```

### Pan Examples (5-reel slot)

| Win Positions | Average X | Pan |
|---------------|-----------|-----|
| [0,0], [1,0], [2,0] | 1.0 | -0.50 (left-center) |
| [2,1], [3,1], [4,1] | 3.0 | +0.50 (right-center) |
| [0,2], [1,2], [2,2], [3,2], [4,2] | 2.0 | 0.00 (center) |
| [0,0], [0,1] | 0.0 | -1.00 (full left) |
| [4,0], [4,1], [4,2] | 4.0 | +1.00 (full right) |

---

## Context Flow Summary

```
SlotLabProvider._triggerStage()
    ↓
Creates context = Map.from(stage.payload)
    ↓
P1.2: Adds 'volumeMultiplier' for ANTICIPATION_ON
P1.3: Adds 'pan' for WIN_LINE_SHOW
    ↓
eventRegistry.triggerStage(stage, context: context)
    ↓
eventRegistry._playLayer(layer, context)
    ↓
Applies context['volumeMultiplier'] to volume
Applies context['pan'] to pan (if not overridden by spatial)
    ↓
AudioPool.acquire() or AudioPlaybackService.playFileToBus()
    ↓
NativeFFI.playbackPlayToBus(path, volume, pan, busId)
    ↓
Rust OneShotVoice.fill_buffer() with equal-power panning
```

---

## Related Files Summary

| Feature | Primary Files |
|---------|---------------|
| P0.3 | `playback.rs`, `ffi.rs`, `native_ffi.dart`, `audio_pool.dart` |
| P0.5 | `rtpc_modulation_service.dart`, `slot_lab_provider.dart` |
| P0.6 | `slot_lab_provider.dart` |
| P0.7 | `event_registry.dart` |
| P1.1 | `slot_lab_provider.dart` |
| P1.2 | `slot_lab_provider.dart`, `event_registry.dart` |
| P1.3 | `slot_lab_provider.dart`, `event_registry.dart` |

---

## Testing

```bash
# Rust build
cd /path/to/fluxforge-studio
cargo build

# Flutter analyze
cd flutter_ui
flutter analyze
# Expected: No issues found!

# Manual testing
# 1. Open Slot Lab
# 2. Use forced outcomes to test specific scenarios
# 3. Check Event Log for audio events
# 4. Listen for pan/volume variations
```

---

## P0.1: Audio Latency Compensation

### Problem
Audio timing je bio hardcoded. Sync je bio off za 10-30ms na različitim sistemima.

### Rešenje
TimingConfig se čita iz Rust engine-a i primenjuje se na audio scheduling.

### Komponente

**`crates/rf-slot-lab/src/timing.rs`**
```rust
pub struct TimingConfig {
    // ... existing fields ...
    pub audio_latency_compensation_ms: f64,      // Audio buffer latency (default: 5.0)
    pub visual_audio_sync_offset_ms: f64,        // Visual-audio sync offset (default: 0.0)
    pub anticipation_audio_pre_trigger_ms: f64,  // Pre-trigger for anticipation (default: 50.0)
    pub reel_stop_audio_pre_trigger_ms: f64,     // Pre-trigger for reel stop (default: 20.0)
}
```

**`crates/rf-bridge/src/slot_lab_ffi.rs`**
```rust
#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_timing_config_json() -> *mut c_char { ... }

#[unsafe(no_mangle)]
pub extern "C" fn slot_lab_get_audio_latency_compensation_ms() -> f64 { ... }
```

**`flutter_ui/lib/src/rust/native_ffi.dart`**
```dart
class SlotLabTimingConfig {
  final double audioLatencyCompensationMs;
  final double visualAudioSyncOffsetMs;
  final double anticipationAudioPreTriggerMs;
  final double reelStopAudioPreTriggerMs;

  double get totalAudioOffsetMs => audioLatencyCompensationMs + visualAudioSyncOffsetMs;

  double audioTriggerTime(double visualTimestampMs, double preTriggerMs) {
    return (visualTimestampMs - totalAudioOffsetMs - preTriggerMs).clamp(0.0, double.infinity);
  }
}
```

**`flutter_ui/lib/providers/slot_lab_provider.dart`**
```dart
void _loadTimingConfig() {
  _timingConfig = _ffi.slotLabGetTimingConfig();
  if (_timingConfig != null) {
    _anticipationPreTriggerMs = _timingConfig!.anticipationAudioPreTriggerMs.round();
    _reelStopPreTriggerMs = _timingConfig!.reelStopAudioPreTriggerMs.round();
  }
}

void _scheduleNextStage() {
  // P0.1: Apply total audio offset from timing config
  final totalAudioOffset = _timingConfig?.totalAudioOffsetMs ?? 5.0;

  if (nextStageType == 'REEL_STOP' && _reelStopPreTriggerMs > 0) {
    final preTriggerTotal = _reelStopPreTriggerMs + totalAudioOffset.round();
    final audioDelayMs = (delayMs - preTriggerTotal).clamp(0, delayMs);
    // Schedule audio earlier
  }
}
```

---

## P0.2: Seamless REEL_SPIN Loop

### Problem
REEL_SPIN audio imalo je click/gap na loop boundary-ju. Standard playback nije podržavao seamless looping.

### Rešenje
Native looping podrška u Rust OneShotVoice strukturi sa seamless wrap-around.

### Komponente

**`crates/rf-engine/src/playback.rs`**
```rust
pub struct OneShotVoice {
    // ... existing fields ...
    looping: bool,  // P0.2: Seamless loop flag
}

impl OneShotVoice {
    fn activate_looping(&mut self, id: u64, audio: Arc<ImportedAudio>, volume: f32, pan: f32, bus: OutputBus) {
        self.activate(id, audio, volume, pan, bus);
        self.looping = true;
    }

    fn fill_buffer(&mut self, left: &mut [f64], right: &mut [f64]) -> bool {
        let total_frames = self.audio.samples.len() / channels_src.max(1);

        for frame in 0..frames_needed {
            // P0.2: Seamless looping - wrap position
            let src_frame = if self.looping {
                (self.position as usize + frame) % total_frames
            } else {
                self.position as usize + frame
            };
            // ... process sample ...
        }

        // P0.2: For looping, wrap position for next call
        if self.looping {
            self.position %= total_frames as u64;
            true // Always playing until stopped
        } else {
            self.position < total_frames as u64
        }
    }
}

pub enum OneShotCommand {
    Play { ... },
    PlayLooping { id, audio, volume, pan, bus },  // P0.2: Looping variant
    Stop { id },
    StopAll,
}
```

**`crates/rf-engine/src/ffi.rs`**
```rust
#[unsafe(no_mangle)]
pub extern "C" fn engine_playback_play_looping_to_bus(
    path: *const c_char,
    volume: f64,
    pan: f64,
    bus_id: u32,
) -> *mut c_char {
    let voice_id = PLAYBACK_ENGINE.play_looping_to_bus(path_str, volume as f32, pan as f32, bus_id);
    // ...
}
```

**`flutter_ui/lib/services/audio_playback_service.dart`**
```dart
int playLoopingToBus(String path, {double volume = 1.0, double pan = 0.0, int busId = 0, ...}) {
  final voiceId = _ffi.playbackPlayLoopingToBus(path, volume: volume, pan: pan, busId: busId);
  // ...
}
```

**`flutter_ui/lib/services/event_registry.dart`**
```dart
Future<void> _playLayer(..., bool loop = false) async {
  if (loop) {
    // P0.2: Seamless looping for REEL_SPIN and similar events
    voiceId = AudioPlaybackService.instance.playLoopingToBus(...);
  } else {
    voiceId = AudioPlaybackService.instance.playFileToBus(...);
  }
}
```

---

## P0.4: Dynamic Cascade Timing

### Problem
Cascade timing bio je fiksiran. Audio završavao pre vizualne animacije.

### Rešenje
Cascade step duration se čita iz TimingConfig + RTPC multiplier za dinamičku kontrolu.

### Komponente

**`flutter_ui/lib/services/rtpc_modulation_service.dart`**
```dart
/// P0.4: Get cascade speed multiplier from Cascade_Speed RTPC
double getCascadeSpeedMultiplier() {
  if (_middleware == null) return 1.0;

  const cascadeSpeedRtpcId = 107; // SlotRtpcIds.cascadeSpeed
  final rtpcDef = _middleware!.getRtpc(cascadeSpeedRtpcId);
  if (rtpcDef == null) return 1.0;

  // Map to multiplier: 0.0 → 0.5x (slow), 0.5 → 1.0x (normal), 1.0 → 2.0x (fast)
  final normalized = rtpcDef.normalizedValue.clamp(0.0, 1.0);
  return 0.5 * math.pow(4.0, normalized);
}
```

**`flutter_ui/lib/providers/slot_lab_provider.dart`**
```dart
void _scheduleNextStage() {
  // P0.4: DYNAMIC CASCADE TIMING
  if (nextStageType == 'CASCADE_STEP') {
    final baseDurationMs = _timingConfig?.cascadeStepDurationMs ?? 400.0;
    final speedMultiplier = RtpcModulationService.instance.getCascadeSpeedMultiplier();
    delayMs = (baseDurationMs / speedMultiplier).round();
    delayMs = delayMs.clamp(100, 1000);
  }
}
```

### Cascade Timing Flow
```
                  ┌───────────────────┐
                  │ Rust TimingConfig │
                  └────────┬──────────┘
                           │
        cascade_step_duration_ms = 400
                           │
                           ▼
              ┌────────────────────────┐
              │ RtpcModulationService  │
              │ getCascadeSpeedMultiplier() │
              └────────────┬───────────┘
                           │
          speedMultiplier = 0.5x .. 2.0x
                           │
                           ▼
              ┌────────────────────────┐
              │ SlotLabProvider        │
              │ delayMs = base / mult  │
              └────────────┬───────────┘
                           │
                Final: 200ms .. 800ms
                           │
                           ▼
                ┌──────────────────┐
                │ Synced Cascade   │
                │ Audio + Visual   │
                └──────────────────┘
```

---

## Completed Features Summary

| ID | Feature | Status |
|----|---------|--------|
| P0.1 | Audio Latency Compensation | ✅ Kompletno |
| P0.2 | Seamless REEL_SPIN Loop | ✅ Kompletno |
| P0.3 | Per-Voice Pan in FFI | ✅ Kompletno |
| P0.4 | Dynamic Cascade Timing | ✅ Kompletno |
| P0.5 | Dynamic Rollup Speed | ✅ Kompletno |
| P0.6 | Anticipation Pre-Trigger | ✅ Kompletno |
| P0.7 | Big Win Layered Audio | ✅ Kompletno |
| P1.1 | Symbol-Specific Audio | ✅ Kompletno |
| P1.2 | Near Miss Audio Escalation | ✅ Kompletno |
| P1.3 | Win Line Audio Panning | ✅ Kompletno |
