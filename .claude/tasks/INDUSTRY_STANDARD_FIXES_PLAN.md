# Industry Standard Fixes — Implementacioni Plan

**Datum:** 2026-01-25
**Prioritet:** P0 fixes critical, P1 nice-to-have

---

## Overview

Ovaj dokument opisuje tačne izmene potrebne za usklađivanje SlotLab audio flow-a sa industry standardom (IGT, NetEnt, Pragmatic Play).

**Fajlovi koji će biti izmenjeni:**

| Fajl | Izmene |
|------|--------|
| `crates/rf-slot-lab/src/spin.rs` | Per-reel spin stages |
| `flutter_ui/lib/services/event_registry.dart` | Spin loop fade-out, win pre-trigger |
| `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` | Anticipation sync, symbol wave |
| `flutter_ui/lib/providers/slot_lab_provider.dart` | Anticipation callback |
| `crates/rf-stage/src/lib.rs` | New ReelSpinning variant |

---

## P0.1: Per-Reel Spin Loop sa Fade-Out

### Problem
Trenutno REEL_SPINNING je JEDAN unified stage. Kada reel stane, spin loop i dalje svira za sve reele.

### Rešenje
Generisati PER-REEL spin stages i automatski fade-out na REEL_STOP.

### Izmene

#### 1. `crates/rf-stage/src/lib.rs` — Dodaj ReelSpinningStart/Stop

```rust
/// Stage events for slot games
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Stage {
    // ... existing variants ...

    /// Single reel starts spinning (for per-reel audio control)
    ReelSpinningStart { reel_index: u8 },

    /// Single reel stops spinning (triggers fade-out of spin loop)
    ReelSpinningStop { reel_index: u8 },
}
```

#### 2. `crates/rf-slot-lab/src/spin.rs` — Generate per-reel stages

```rust
// Line ~150, replace unified REEL_SPINNING with per-reel
// OLD:
// events.push(StageEvent::new(
//     Stage::ReelSpinning { reel_index: 0 },
//     timing.reel_spin(0),
// ));

// NEW:
for reel in 0..reel_count {
    // Each reel starts spinning with slight stagger (50ms)
    events.push(StageEvent::new(
        Stage::ReelSpinningStart { reel_index: reel },
        timing.reel_spin(reel),
    ));
}

// Later, in reel stop section (line ~185):
// After each REEL_STOP, emit REEL_SPINNING_STOP
events.push(StageEvent::new(
    Stage::ReelSpinningStop { reel_index: reel },
    timing.reel_stop(reel), // Same time as REEL_STOP
));
events.push(StageEvent::new(
    Stage::ReelStop { reel_index: reel, symbols },
    timing.reel_stop(reel),
));
```

#### 3. `flutter_ui/lib/services/event_registry.dart` — Handle spin loop lifecycle

```dart
// Add tracking for active spin loops
final Map<int, String> _activeSpinLoops = {}; // reel_index → voice_id

void triggerStage(String stage, {double? timestampMs, ...}) {
  // ... existing code ...

  // Handle per-reel spin start
  if (stage.startsWith('REEL_SPINNING_START_')) {
    final reelIndex = int.tryParse(stage.split('_').last) ?? 0;
    _startReelSpinLoop(reelIndex);
    return;
  }

  // Handle per-reel spin stop (fade out)
  if (stage.startsWith('REEL_SPINNING_STOP_') || stage.startsWith('REEL_STOP_')) {
    final reelIndex = int.tryParse(stage.split('_').last) ?? 0;
    _fadeOutReelSpinLoop(reelIndex);
    // Continue to process REEL_STOP audio below...
  }

  // ... rest of existing triggerStage logic ...
}

void _startReelSpinLoop(int reelIndex) {
  // Calculate per-reel pan: -0.8 → +0.8
  final pan = (reelIndex - 2) * 0.4;

  // Find REEL_SPINNING event and play looping
  final event = _stageToEvent['REEL_SPINNING'] ?? _stageToEvent['REEL_SPIN'];
  if (event == null) return;

  final layer = event.layers.firstOrNull;
  if (layer == null) return;

  final voiceId = AudioPlaybackService.instance.playLoopingToBus(
    layer.audioPath,
    layer.volume * 0.7, // Slightly quieter per-reel
    pan,
    1, // Reels bus
    PlaybackSource.slotLab,
  );

  _activeSpinLoops[reelIndex] = voiceId;
  debugPrint('[EventRegistry] 🔊 Started spin loop for reel $reelIndex (pan: $pan)');
}

void _fadeOutReelSpinLoop(int reelIndex, {int fadeMs = 100}) {
  final voiceId = _activeSpinLoops.remove(reelIndex);
  if (voiceId == null) return;

  // Fade out over 100ms
  NativeFFI.instance.startFadeOut(voiceId, fadeMs);
  debugPrint('[EventRegistry] 🔇 Fading out spin loop for reel $reelIndex');
}

// Also add cleanup on SPIN_END
void _cleanupAllSpinLoops() {
  for (final entry in _activeSpinLoops.entries) {
    NativeFFI.instance.stopVoice(entry.value);
  }
  _activeSpinLoops.clear();
}
```

#### 4. Audio Designer Setup

Potreban je SAMO JEDAN audio fajl za spin loop:
- `REEL_SPINNING` ili `REEL_SPIN` event sa jednim layer-om
- Sistem automatski klonira za svaki reel sa pan modifikacijom

---

## P0.2: Eliminacija Dead Silence Pre Win Reveal

### Problem
50-100ms tišina između poslednjeg REEL_STOP i WIN_SYMBOL_HIGHLIGHT.

### Rešenje
Pre-trigger WIN_SYMBOL_HIGHLIGHT na REEL_STOP_4 (poslednji reel) ako postoji win.

### Izmene

#### `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart`

```dart
// In _onReelStopVisual(), after triggering REEL_STOP audio:

void _onReelStopVisual(int reelIndex) {
  // ... existing buffer logic ...

  // After flushing the reel stop:
  if (reelIndex == widget.reels - 1) {
    // Last reel stopped - check for win IMMEDIATELY
    final result = widget.provider.lastResult;
    if (result != null && result.isWin) {
      // ═══════════════════════════════════════════════════════════════════
      // P0.2 FIX: Pre-trigger shimmer on LAST reel stop
      // This eliminates the 50-100ms "dead silence" gap
      // WIN_SYMBOL_HIGHLIGHT starts at the EXACT moment of final reel stop
      // ═══════════════════════════════════════════════════════════════════
      eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT');
      debugPrint('[SlotPreview] 🔊 PRE-TRIGGER: WIN_SYMBOL_HIGHLIGHT (instant on last reel)');

      // Start visual pulse immediately too
      _startSymbolPulseAnimation();
    }
  }
}
```

**NAPOMENA:** Ovo znači da `_finalizeSpin()` više NE treba da triggeruje WIN_SYMBOL_HIGHLIGHT. Treba dodati guard:

```dart
void _finalizeSpin(SlotLabSpinResult result) {
  // ... existing code ...

  if (result.isWin) {
    // ═══════════════════════════════════════════════════════════════════
    // PHASE 1: SYMBOL HIGHLIGHT
    // NOTE: If pre-triggered in _onReelStopVisual, skip here
    // ═══════════════════════════════════════════════════════════════════
    if (!_symbolHighlightPreTriggered) {
      eventRegistry.triggerStage('WIN_SYMBOL_HIGHLIGHT');
      _startSymbolPulseAnimation();
    }
    _symbolHighlightPreTriggered = false; // Reset for next spin

    // ... rest of win flow ...
  }
}
```

---

## P0.3: Anticipation Visual-Audio Sync

### Problem
ANTICIPATION_ON audio triggeruje se iz Rust timing-a, ali visual (screen dim, reel slowdown) nije sinhronizovan.

### Rešenje
Dodati callback u SlotLabProvider koji notifikuje UI o anticipation stages.

### Izmene

#### 1. `flutter_ui/lib/providers/slot_lab_provider.dart` — Dodaj anticipation callbacks

```dart
class SlotLabProvider extends ChangeNotifier {
  // ... existing code ...

  // Anticipation callbacks
  void Function(int reelIndex, String reason)? onAnticipationStart;
  void Function(int reelIndex)? onAnticipationEnd;

  void _playStage(SlotLabStageEvent stage) {
    // ... existing stage processing ...

    // Notify UI about anticipation
    if (stage.stageType.startsWith('anticipation_on')) {
      final reelIndex = _extractReelIndex(stage.stageType);
      final reason = stage.payload?['reason'] as String? ?? 'unknown';
      onAnticipationStart?.call(reelIndex, reason);
    } else if (stage.stageType.startsWith('anticipation_off')) {
      final reelIndex = _extractReelIndex(stage.stageType);
      onAnticipationEnd?.call(reelIndex);
    }

    // ... existing EventRegistry trigger ...
  }

  int _extractReelIndex(String stageType) {
    // Extract reel index from stage type: "anticipation_on_3" → 3
    final parts = stageType.split('_');
    return int.tryParse(parts.last) ?? 0;
  }
}
```

#### 2. `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` — React to anticipation

```dart
@override
void initState() {
  super.initState();
  // ... existing init ...

  // Listen to anticipation events
  widget.provider.onAnticipationStart = _onAnticipationStart;
  widget.provider.onAnticipationEnd = _onAnticipationEnd;
}

void _onAnticipationStart(int reelIndex, String reason) {
  debugPrint('[SlotPreview] 🎯 ANTICIPATION START: reel $reelIndex ($reason)');

  setState(() {
    _isAnticipation = true;
    _anticipationReels = {reelIndex};
  });

  // Slow down the reel animation
  _reelAnimController.setReelSpeedMultiplier(reelIndex, 0.3); // 30% speed

  // Dim background
  _anticipationOverlayController.forward();
}

void _onAnticipationEnd(int reelIndex) {
  debugPrint('[SlotPreview] 🎯 ANTICIPATION END: reel $reelIndex');

  setState(() {
    _anticipationReels.remove(reelIndex);
    if (_anticipationReels.isEmpty) {
      _isAnticipation = false;
    }
  });

  // Resume normal speed
  _reelAnimController.setReelSpeedMultiplier(reelIndex, 1.0);

  // Remove dim
  if (_anticipationReels.isEmpty) {
    _anticipationOverlayController.reverse();
  }
}
```

#### 3. `professional_reel_animation.dart` — Add speed multiplier support

```dart
class ProfessionalReelAnimationController {
  // ... existing code ...

  final Map<int, double> _reelSpeedMultipliers = {};

  void setReelSpeedMultiplier(int reelIndex, double multiplier) {
    _reelSpeedMultipliers[reelIndex] = multiplier.clamp(0.1, 2.0);
  }

  double _getReelSpeed(int reelIndex) {
    final baseSpeed = _config.spinSpeed;
    final multiplier = _reelSpeedMultipliers[reelIndex] ?? 1.0;
    return baseSpeed * multiplier;
  }
}
```

---

## P1.1: RTPC Rollup Tick Pitch Rise

### Problem
ROLLUP_TICK ima konstantan pitch. Industry standard koristi pitch rise tokom rollupa.

### Rešenje
Koristiti RTPC binding za `rollup_progress` → `pitch` modifikator.

### Izmene

#### 1. `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart`

```dart
void _startTierBasedRollup(String tier) {
  // ... existing code ...

  int tickCount = 0;
  final totalTicks = (duration / tickIntervalMs).round();

  _rollupTickTimer = Timer.periodic(Duration(milliseconds: tickIntervalMs), (timer) {
    // ... existing guards ...

    tickCount++;
    final progress = tickCount / totalTicks; // 0.0 → 1.0

    // ═══════════════════════════════════════════════════════════════════
    // P1.1: Update RTPC for pitch modulation
    // Pitch rises from 1.0 to 1.2 during rollup (20% increase)
    // ═══════════════════════════════════════════════════════════════════
    final pitch = 1.0 + (progress * 0.2);
    NativeFFI.instance.setRtpcValue('rollup_pitch', pitch);

    eventRegistry.triggerStage('ROLLUP_TICK');
  });
}
```

#### 2. RTPC Setup (Provider)
Dodati `rollup_pitch` RTPC definiciju sa binding-om na pitch parameter.

---

## P1.2: Animated Win Line "Grow" Effect

### Problem
Win line se crta instant. Industry standard: line "grows" od prvog simbola.

### Rešenje
Animacija progress-a od 0.0 → 1.0 tokom 200-300ms.

### Izmene

#### `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart`

```dart
// Add animation controller for line growth
late AnimationController _lineGrowController;
double _lineDrawProgress = 0.0;

@override
void initState() {
  super.initState();
  _lineGrowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..addListener(() {
    setState(() {
      _lineDrawProgress = _lineGrowController.value;
    });
  });
}

void _showCurrentWinLine({bool triggerAudio = true}) {
  // ... existing position setup ...

  // Reset and animate line growth
  _lineGrowController.forward(from: 0);

  if (triggerAudio) {
    eventRegistry.triggerStage('WIN_LINE_SHOW');
  }
}

// In _WinLinePainter:
void paint(Canvas canvas, Size size) {
  // Use _lineDrawProgress to draw partial line
  // 0.0 = no line, 0.5 = half line, 1.0 = full line

  // Calculate how many segments to draw
  final totalSegments = positions.length - 1;
  final segmentsToDraw = (totalSegments * progress).ceil();

  for (int i = 0; i < segmentsToDraw; i++) {
    // Draw segment from positions[i] to positions[i+1]
    // Last segment may be partial based on progress
  }
}
```

---

## P1.3: Sequential Symbol Highlight Wave

### Problem
Svi winning simboli se skaliraju uniformno. Industry standard: sekvencijalni L→R wave.

### Rešenje
Per-position delay (100ms offset) u pulse animation.

### Izmene

#### `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart`

```dart
void _startSymbolPulseAnimation() {
  _symbolPulseCount = 0;

  // ═══════════════════════════════════════════════════════════════════
  // P1.3: Sequential wave - each position starts 100ms after previous
  // ═══════════════════════════════════════════════════════════════════
  for (int i = 0; i < _winningPositions.length; i++) {
    Future.delayed(Duration(milliseconds: i * 100), () {
      if (mounted) {
        _startSinglePositionPulse(_winningPositions.elementAt(i));
      }
    });
  }
}

// Track per-position pulse state
final Map<String, double> _positionPulseScale = {};

void _startSinglePositionPulse(String position) {
  // Animate scale for this specific position
  // ... individual pulse logic ...
}

// In build(), check per-position scale:
double _getSymbolScale(String position) {
  return _positionPulseScale[position] ?? 1.0;
}
```

---

## P1.4: Cascade Pitch Escalation

### Problem
CASCADE_STEP koristi isti zvuk za sve korake.

### Rešenje
RTPC binding za `cascade_step` → `pitch` sa inkrementalnim rastom.

### Izmene

#### `flutter_ui/lib/services/event_registry.dart`

```dart
void triggerStage(String stage, {double? timestampMs, ...}) {
  // ... existing code ...

  // P1.4: Cascade pitch escalation
  if (stage.startsWith('CASCADE_STEP')) {
    final stepIndex = _extractStepIndex(stage);
    // Pitch rises 5% per step (step 0 = 1.0, step 5 = 1.25)
    final pitch = 1.0 + (stepIndex * 0.05);
    NativeFFI.instance.setRtpcValue('cascade_pitch', pitch);
  }

  // ... rest of triggerStage ...
}

int _extractStepIndex(String stage) {
  // "CASCADE_STEP_3" → 3
  final match = RegExp(r'CASCADE_STEP_(\d+)').firstMatch(stage);
  return int.tryParse(match?.group(1) ?? '0') ?? 0;
}
```

---

## P1.5: Expanded Jackpot Audio Sequence

### Problem
Jackpot stages imaju basic audio. Industry standard: multi-layer dramatična sekvenca.

### Rešenje
Proširiti jackpot stages sa više granularnosti.

### Nove Stage Definicije

```
JACKPOT_TRIGGER       → Alert tone (500ms)
JACKPOT_BUILDUP       → Rising tension (2000ms) ← NEW
JACKPOT_REVEAL        → Tier reveal ("GRAND!") (1000ms) ← NEW
JACKPOT_PRESENT       → Main fanfare + amount (5000ms)
JACKPOT_CELEBRATION   → Looping celebration (until dismiss) ← NEW
JACKPOT_END           → Fade out
```

Ovo zahteva izmene u `spin.rs` za generisanje dodatnih stages.

---

## Implementacioni Redosled

### Phase 1: P0 Critical (Estimated: 2-3h)

1. **P0.2** — Najbrži fix, 15 min
2. **P0.1** — Medium effort, 1h
3. **P0.3** — Medium effort, 1h

### Phase 2: P1 Improvements (Estimated: 3-4h)

4. **P1.1** — Rollup pitch, 30 min
5. **P1.3** — Symbol wave, 45 min
6. **P1.4** — Cascade pitch, 30 min
7. **P1.2** — Win line grow, 1h
8. **P1.5** — Jackpot expansion, 1.5h (includes Rust changes)

---

## Testing Checklist

### P0 Tests

- [ ] Spin sa 5 reela → Čuje se 5 odvojenih spin loop-ova
- [ ] Svaki reel stop → Odgovarajući spin loop fade-out
- [ ] Poslednji reel stop sa win → Instant shimmer (0ms gap)
- [ ] Anticipation → Screen dim + reel slowdown sinhronizovani

### P1 Tests

- [ ] Rollup → Pitch raste od 1.0 do 1.2
- [ ] Win line → "Grows" od prvog simbola (250ms)
- [ ] Symbol highlight → Wave effect L→R
- [ ] Cascade → Pitch raste sa svakim stepom

---

## Rollback Plan

Svaka izmena je izolovana u svom fajlu. Ako fix uzrokuje regresiju:

1. Git revert specifičnog commita
2. Ili: feature flag u kodu (`_usePerReelSpinLoops = false`)

---

**Dokument Kraj**
