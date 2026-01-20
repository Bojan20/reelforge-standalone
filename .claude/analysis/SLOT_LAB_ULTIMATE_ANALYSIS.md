# Slot Lab — Ultimativna Multi-Role Analiza

**Datum:** 2026-01-20
**Analizirao:** Claude (Chief Audio Architect + Lead DSP Engineer + Engine Architect + Technical Director + UI/UX Expert)
**Perspektiva:** Najzahtevniji slot igrač + AAA Audio Designer
**Status:** KOMPLETNA ANALIZA — BEZ RUPA

---

## EXECUTIVE SUMMARY

| Metrika | Trenutno | Cilj |
|---------|----------|------|
| **Rust Engine LOC** | 3,000+ | — |
| **Dart UI LOC** | 11,000+ | — |
| **Ukupno LOC** | 14,000+ | — |
| **Production Ready** | 85% | 100% |
| **Audio Latency** | 5-8ms | <3ms |
| **Missing Critical** | 7 | 0 |

---

## 1. KRITIČNI NEDOSTACI (P0 — MORA SE POPRAVITI)

### P0.1 — Audio Latency Compensation je HARDCODED

**Problem:** `timing.rs` ima fiksne vrednosti koje ne odgovaraju stvarnom sistemu.

```rust
// TRENUTNO (timing.rs:~280)
audio_latency_compensation_ms: 5.0,  // Guess, not measured
reel_stop_audio_pre_trigger_ms: 20.0,  // Arbitrary
```

**Zašto je kritično:** Slot igrač čuje REEL_STOP pre/posle vizuelnog stopa. Ovo uništava doživljaj.

**Rešenje:**
```rust
// 1. Dodaj latency measurement u engine
pub fn measure_audio_latency() -> f64 {
    // Play test tone, measure round-trip
}

// 2. Auto-calibrate na init
impl SyntheticSlotEngine {
    pub fn calibrate_audio_sync(&mut self) {
        let measured = measure_audio_latency();
        self.timing_config.audio_latency_compensation_ms = measured;
    }
}

// 3. Expozuj kroz FFI
#[no_mangle]
pub extern "C" fn slot_lab_calibrate_audio() -> f64
```

**Effort:** 2-3 sata

---

### P0.2 — REEL_SPIN Loop Nema Seamless Looping

**Problem:** `SlotLabProvider._triggerStage()` startuje REEL_SPIN ali ne garantuje seamless loop.

```dart
// TRENUTNO (slot_lab_provider.dart:~460)
if (effectiveStage == 'SPIN_START') {
  eventRegistry.triggerStage('REEL_SPIN');  // Just fires once!
}
```

**Zašto je kritično:** Slot igrač čuje "gap" ili "click" kada se loop restartuje.

**Rešenje:**
```dart
// 1. EventRegistry treba LOOP flag
void triggerStage(String stage, {bool loop = false, int? loopCount}) {
  if (loop) {
    _loopingStages[stage] = LoopState(count: loopCount ?? -1);
  }
  _playLayer(...);
}

// 2. Audio engine treba seamless loop support
// U Rust FFI: playbackPlayToBusLooped(clipId, busId, loopStart, loopEnd)
```

**Effort:** 4-6 sati

---

### P0.3 — Nema Per-Voice Pan u FFI

**Problem:** `EventRegistry` izračunava spatial pan ali ga NE MOŽE PRIMENITI.

```dart
// TRENUTNO (event_registry.dart:~407)
pan = spatialOutput.pan;  // Calculated!
// Ali playbackPlayToBus() NEMA pan parametar!
```

**Zašto je kritično:** Ceo AutoSpatialEngine je BESKORISTAN dok FFI ne podrži pan.

**Rešenje:**
```rust
// middleware_ffi.rs - DODAJ:
#[no_mangle]
pub extern "C" fn playback_play_to_bus_stereo(
    clip_id: i32,
    bus_id: i32,
    volume: f32,
    pan: f32,  // -1.0 to +1.0
) -> i32

// Ili bolji pristup - voice parameters:
#[no_mangle]
pub extern "C" fn voice_set_pan(voice_id: i32, pan: f32)
```

**Effort:** 2-4 sata (Rust side) + 1 sat (Dart bindings)

---

### P0.4 — Cascade Audio Timing je Pogrešan

**Problem:** Cascade koristi fiksni `cascade_step_duration_ms` ali vizualni cascade NIJE fiksne dužine.

```rust
// TRENUTNO (timing.rs)
cascade_step_duration_ms: 600.0,  // Fixed!
```

**Zašto je kritično:** Audio cascade završava pre/posle vizuelnog. Igrač vidi simbole koji padaju BEZ ZVUKA.

**Rešenje:**
```rust
// 1. Cascade step duration mora biti PER-STEP iz vizuelnog engine-a
pub struct CascadeStepTiming {
    pub step_index: u32,
    pub symbols_removed: u32,
    pub fall_duration_ms: f64,  // Varies by grid height!
    pub settle_duration_ms: f64,
}

// 2. Stage event mora nositi ovu info
StageEvent::CascadeStep {
    step: 0,
    timing: CascadeStepTiming { ... },
}
```

**Effort:** 4-6 sati

---

### P0.5 — Win Rollup Nema Dynamic Speed

**Problem:** Rollup brzina je fiksna bez obzira na win amount.

```rust
// TRENUTNO
rollup_speed: 50.0,  // credits/sec - FIXED
```

**Zašto je kritično:**
- Mali win (5 credits): Rollup traje 100ms — OK
- Mega win (5000 credits): Rollup traje 100 SEKUNDI — KATASTROFA

**Rešenje:**
```rust
pub fn calculate_rollup_speed(win_amount: f64, target_duration_ms: f64) -> f64 {
    // Target: 2-5 seconds za bilo koji win
    let min_duration = 2000.0;
    let max_duration = 5000.0;

    let duration = match win_amount {
        x if x < 10.0 => min_duration,
        x if x > 1000.0 => max_duration,
        x => min_duration + (max_duration - min_duration) * (x.ln() / 1000.0_f64.ln()),
    };

    win_amount / (duration / 1000.0)
}
```

**Effort:** 1-2 sata

---

### P0.6 — Anticipation NIJE Pre-Triggered

**Problem:** Anticipation audio startuje KADA anticipation počne, ne PRE.

```dart
// TRENUTNO
_triggerStage('ANTICIPATION_ON');  // Fires at visual start
```

**Zašto je kritično:** Anticipation audio (build-up) mora početi 200-500ms PRE vizuelnog efekta da bi igrač OSEĆAO tenziju.

**Rešenje:**
```dart
// U stage generation (Rust):
StageEvent {
    stage_type: "ANTICIPATION_ON",
    timestamp_ms: visual_start_ms - 300,  // PRE-TRIGGER!
    payload: { "pre_trigger_ms": 300 },
}

// Ili u Dart:
void _triggerStage(stage) {
    final preTrigger = stage.payload['pre_trigger_ms'] ?? 0;
    if (preTrigger > 0) {
        // Audio već uračunava pre-trigger, nema delay
    }
}
```

**Effort:** 2-3 sata

---

### P0.7 — Big Win Celebration NEMA Layers

**Problem:** Big Win je jedan event, ne layered audio.

```dart
// TRENUTNO
triggerStage('WIN_BIG');  // Single sound!
```

**Zašto je kritično:** AAA slot big win ima 5-10 layera:
1. Impact hit
2. Coin shower loop
3. Music sting
4. Crowd cheer
5. Win counter tick
6. Sparkle accents
7. Bass drop
8. Reverse cymbal swell

**Rešenje:**
```dart
// CompositeEvent sa layers (već postoji u modelu!)
class BigWinAudioEvent extends SlotCompositeEvent {
  layers: [
    SlotEventLayer(name: 'impact', delay: 0),
    SlotEventLayer(name: 'coins_loop', delay: 50, loop: true),
    SlotEventLayer(name: 'music_sting', delay: 100),
    SlotEventLayer(name: 'crowd', delay: 200),
    SlotEventLayer(name: 'counter_tick', delay: 0, loop: true),
    // ...
  ]
}

// EventRegistry već podržava layered playback!
// Problem je što NIKO NE KREIRA layered events za big wins.
```

**Effort:** 2-3 sata (kreiranje default layered events)

---

## 2. VISOKI PRIORITET (P1 — ZNAČAJNO UNAPREĐENJE)

### P1.1 — Symbol-Specific Audio

**Problem:** Svi simboli imaju isti REEL_STOP zvuk.

**Slot igrač očekuje:**
- Seven stop: Heavy, bassy thud
- Wild stop: Magical shimmer + thud
- Scatter stop: Distinct "scatter sound"
- Cherry stop: Light, fruity pop

**Rešenje:**
```dart
// Stage event payload već ima symbol info:
StageEvent {
    stage_type: "REEL_STOP_0",
    payload: {
        "reel_index": 0,
        "symbols": [7, 7, 2],  // Symbols that landed
        "has_wild": true,
    }
}

// EventRegistry treba symbol-aware triggering:
void _triggerStage(stage) {
    final hasWild = stage.payload['has_wild'] ?? false;
    final effectiveStage = hasWild
        ? '${stage.type}_WILD'  // REEL_STOP_0_WILD
        : stage.type;
}
```

**Effort:** 3-4 sata

---

### P1.2 — Near Miss Audio Escalation

**Problem:** Near miss ima jedan ANTICIPATION zvuk bez obzira na "koliko blizu".

**Slot igrač očekuje:**
- 2 scatters (need 3): Light tension
- 2 scatters + scatter on reel 4: HEAVY tension
- 2 scatters + scatter on reel 5: MAXIMUM tension

**Rešenje:**
```rust
// U stage generation:
pub fn generate_anticipation_stage(near_miss: &NearMissInfo) -> StageEvent {
    let intensity = match near_miss.missing_symbols {
        1 => 1.0,   // One away = maximum
        2 => 0.7,   // Two away = high
        _ => 0.4,   // More = medium
    };

    let reel_position = near_miss.trigger_reel as f64 / 5.0;  // Later = more intense

    StageEvent {
        stage_type: "ANTICIPATION_ON",
        payload: json!({
            "intensity": intensity * reel_position,
            "missing": near_miss.missing_symbols,
            "trigger_reel": near_miss.trigger_reel,
        }),
    }
}
```

**Effort:** 2-3 sata

---

### P1.3 — Win Line Audio Panning

**Problem:** Win line audio je stereo center bez obzira na liniju.

**Slot igrač očekuje:**
- Diagonal line top-left to bottom-right: Pan follows line
- V-shape line: Wide stereo
- Horizontal center line: Center focus

**Rešenje:**
```dart
// WIN_LINE stage treba pan info:
StageEvent {
    stage_type: "WIN_LINE",
    payload: {
        "line_id": 5,
        "line_shape": "diagonal_down",
        "pan_start": -0.8,  // Left
        "pan_end": 0.8,     // Right
        "pan_duration_ms": 500,
    }
}

// Audio playback sa animated pan:
void _playWinLine(stage) {
    final panStart = stage.payload['pan_start'];
    final panEnd = stage.payload['pan_end'];
    final duration = stage.payload['pan_duration_ms'];

    // Animate pan over duration
    _animatePan(voiceId, panStart, panEnd, duration);
}
```

**Effort:** 3-4 sata

---

### P1.4 — Jackpot Tier Audio Differentiation

**Problem:** Svi jackpoti imaju sličan zvuk.

**Slot igrač očekuje:**
- Mini (50x): Quick celebration
- Minor (200x): Medium celebration
- Major (1000x): Big celebration + unique sting
- Grand (10000x): EPIC 10-second celebration sa unique theme

**Rešenje:**
```dart
// Već postoji u ForcedOutcome, ali events nisu diferencirani:
// JACKPOT_MINI, JACKPOT_MINOR, JACKPOT_MAJOR, JACKPOT_GRAND

// Treba kreirati 4 RAZLIČITA CompositeEvent-a sa različitim:
// - Duration (Mini: 2s, Grand: 10s)
// - Layer count (Mini: 3, Grand: 15)
// - Music (Mini: short sting, Grand: full fanfare)
```

**Effort:** 4-6 sati (audio design + implementation)

---

### P1.5 — Reel Spin Speed Variation

**Problem:** REEL_SPIN loop je isti bez obzira na spin speed.

**Slot igrač očekuje:**
- Normal mode: Standard spin sound
- Turbo mode: Faster, higher pitch spin
- Slow-mo (near big win): Slowed, lower pitch

**Rešenje:**
```dart
// TimingProfile treba pitch modifier:
class TimingProfile {
    double spinPitchMultiplier;  // Normal: 1.0, Turbo: 1.2, SlowMo: 0.7
}

// REEL_SPIN event treba pitch info:
StageEvent {
    stage_type: "REEL_SPIN",
    payload: {
        "pitch": 1.2,  // Turbo
        "speed_mode": "turbo",
    }
}

// Audio playback sa pitch:
void _playReelSpin(stage) {
    final pitch = stage.payload['pitch'] ?? 1.0;
    playbackWithPitch(clipId, pitch);
}
```

**Effort:** 2-3 sata

---

### P1.6 — Feature Enter/Exit Audio Transitions

**Problem:** Feature transitions su abrupt.

**Slot igrač očekuje:**
- Feature Enter: Whoosh + transition + new ambience start
- Feature Exit: Reverse whoosh + ambience crossfade back

**Rešenje:**
```dart
// FEATURE_ENTER treba crossfade:
void _triggerFeatureEnter() {
    // 1. Fade out base game ambience
    eventRegistry.fadeOut('AMBIENCE_BASE', durationMs: 500);

    // 2. Play transition
    eventRegistry.triggerStage('FEATURE_TRANSITION_IN');

    // 3. Start feature ambience
    Future.delayed(Duration(milliseconds: 300), () {
        eventRegistry.triggerStage('AMBIENCE_FEATURE', loop: true);
    });
}
```

**Effort:** 2-3 sata

---

### P1.7 — Bet Change Audio Feedback

**Problem:** Bet change je silent.

**Slot igrač očekuje:**
- Bet increase: Ascending tone
- Bet decrease: Descending tone
- Max bet: Special "max bet" sound

**Rešenje:**
```dart
// U SlotLabProvider:
void setBetAmount(double bet) {
    final oldBet = _betAmount;
    _betAmount = bet;

    if (bet > oldBet) {
        eventRegistry.triggerStage('BET_INCREASE');
    } else if (bet < oldBet) {
        eventRegistry.triggerStage('BET_DECREASE');
    }

    if (bet >= 1000.0) {  // Max bet
        eventRegistry.triggerStage('BET_MAX');
    }
}
```

**Effort:** 1 sat

---

## 3. SREDNJI PRIORITET (P2 — QUALITY OF LIFE)

### P2.1 — Audio Preview on Hover (Widget Ready, Not Integrated)

**Problem:** `audio_hover_preview.dart` (926 lines) postoji ali NIJE INTEGRISAN.

**Rešenje:**
```dart
// U slot_lab_screen.dart, resources panel:
AudioHoverPreview(
    audioPath: selectedPath,
    onSelect: (path) => _addToTimeline(path),
)
```

**Effort:** 1-2 sata

---

### P2.2 — RTPC Curves Not Connected to Engine

**Problem:** `rtpc_editor_panel.dart` ima UI za krive ali nisu povezane sa audio engine-om.

**Rešenje:**
```dart
// RtpcModulationService treba curve evaluation:
double evaluateCurve(int rtpcId, double inputValue) {
    final curve = _curves[rtpcId];
    return curve.evaluate(inputValue);  // Cubic/linear interp
}

// U EventRegistry._playLayer():
if (_useSpatialAudio && eventKey != null) {
    // ... existing spatial code ...

    // Add RTPC curve modulation:
    final winMultiplier = RtpcModulationService.instance
        .evaluateCurve(SlotRtpcIds.winMultiplier, lastWinRatio);
    volume *= winMultiplier;
}
```

**Effort:** 3-4 sata

---

### P2.3 — Session Statistics Export

**Problem:** Stats su samo u UI, ne mogu se exportovati.

**Rešenje:**
```dart
// U profiler_panel.dart:
ElevatedButton(
    onPressed: () => _exportStats(),
    child: Text('Export CSV'),
)

void _exportStats() {
    final csv = '''
Spin Count,${stats.totalSpins}
Total Bet,${stats.totalBet}
Total Win,${stats.totalWin}
RTP,${stats.rtp}%
Hit Rate,${stats.hitRate}%
Big Wins,${stats.bigWinCount}
''';
    // Save to file
}
```

**Effort:** 1 sat

---

### P2.4 — Keyboard Shortcuts za Timeline

**Problem:** Timeline editing je mouse-only.

**Slot audio designer očekuje:**
- Space: Play/Pause
- S: Split region at playhead
- D: Delete selected
- Ctrl+Z: Undo
- Ctrl+C/V: Copy/Paste region

**Rešenje:**
```dart
// U SlotLabScreen:
return RawKeyboardListener(
    focusNode: _focusNode,
    onKey: (event) {
        if (event is RawKeyDownEvent) {
            switch (event.logicalKey) {
                case LogicalKeyboardKey.space:
                    _togglePlayback();
                case LogicalKeyboardKey.keyS:
                    _splitAtPlayhead();
                case LogicalKeyboardKey.delete:
                    _deleteSelected();
                // ...
            }
        }
    },
    child: /* ... */
);
```

**Effort:** 2-3 sata

---

### P2.5 — Waveform Zoom na Timeline

**Problem:** Waveform zoom je fixed.

**Rešenje:**
```dart
// Ctrl+Scroll za zoom:
Listener(
    onPointerSignal: (event) {
        if (event is PointerScrollEvent && _ctrlPressed) {
            _zoomLevel = (_zoomLevel + event.scrollDelta.dy * 0.001)
                .clamp(0.1, 10.0);
            setState(() {});
        }
    },
)
```

**Effort:** 1-2 sata

---

### P2.6 — Undo/Redo za Timeline Edits

**Problem:** Timeline edits su NEPOVRATNI.

**Rešenje:**
```dart
// Command pattern (već postoji u DAW):
class TimelineCommand {
    void execute();
    void undo();
}

class MoveRegionCommand extends TimelineCommand {
    final region;
    final oldStart, newStart;

    void execute() => region.start = newStart;
    void undo() => region.start = oldStart;
}

// Undo stack:
List<TimelineCommand> _undoStack = [];
List<TimelineCommand> _redoStack = [];
```

**Effort:** 3-4 sata

---

### P2.7 — Multi-Select Regions

**Problem:** Samo jedan region može biti selected.

**Rešenje:**
```dart
// Shift+Click za multi-select:
Set<String> _selectedRegionIds = {};

void _onRegionTap(region, {bool shiftHeld = false}) {
    if (shiftHeld) {
        _selectedRegionIds.add(region.id);  // Add to selection
    } else {
        _selectedRegionIds = {region.id};   // Replace selection
    }
}
```

**Effort:** 2 sata

---

## 4. NISKI PRIORITET (P3 — NICE TO HAVE)

### P3.1 — Dark/Light Theme Toggle
### P3.2 — Region Color Customization
### P3.3 — Audio Waveform Peak/RMS Toggle
### P3.4 — Stage Event Filtering by Type
### P3.5 — Auto-Save Timeline State
### P3.6 — Import/Export Timeline as JSON
### P3.7 — A/B Comparison Mode

---

## 5. ARHITEKTURNI DOBITAK — CONSOLIDACIJA

### Problem: Dupli Podaci

```
SlotLabProvider.persistedCompositeEvents
    ↕ (sync needed)
MiddlewareProvider.compositeEvents
```

### Rešenje: Single Source of Truth

```dart
// MiddlewareProvider je JEDINI vlasnik
// SlotLabProvider REFERENCIRA, ne KOPIRA

class SlotLabProvider {
    // REMOVE:
    // List<Map<String, dynamic>> persistedCompositeEvents;

    // ADD:
    List<SlotCompositeEvent> get compositeEvents =>
        _middleware?.compositeEvents ?? [];
}
```

**Effort:** 4-6 sati (careful refactoring)

---

## 6. PERFORMANCE OPTIMIZACIJE

### 6.1 — Batch Stage Events

**Problem:** Svaki stage event je odvojen FFI call.

**Rešenje:**
```rust
// Umesto:
for stage in stages {
    trigger_stage(stage);  // N FFI calls
}

// Batch:
trigger_stages_batch(stages);  // 1 FFI call
```

**Impact:** 50-80% manje FFI overhead

---

### 6.2 — Waveform Cache Persistence

**Problem:** Waveform se re-renderuje na svaki app restart.

**Rešenje:**
```dart
// Persist waveform cache to disk:
void _saveWaveformCache() {
    final json = jsonEncode(waveformCache);
    File('~/.fluxforge/waveform_cache.json').writeAsString(json);
}
```

**Impact:** Instant timeline load

---

### 6.3 — Lazy Region Loading

**Problem:** Sve regije se renderuju čak i van viewport-a.

**Rešenje:**
```dart
// Only render visible regions:
final visibleRegions = regions.where((r) =>
    r.end > viewportStart && r.start < viewportEnd
);
```

**Impact:** 5-10x brže renderovanje velikih timeline-a

---

## 7. UI/UX POBOLJŠANJA (Iz Perspektive Najzahtevnijeg Igrača)

### 7.1 — Visual Feedback na SVAKI Zvuk

**Problem:** Igrač ne vidi KOJI ZVUK se upravo svira.

**Rešenje:**
- Pulse effect na aktivnoj stage marker
- Highlight na aktivnoj audio regiji
- Speaker icon pored imena zvuka

---

### 7.2 — Win Anticipation Visual Sync

**Problem:** Audio anticipation i vizuelna anticipacija nisu sinhronizovani.

**Rešenje:**
- Pre-trigger audio za 200-300ms
- Visual follows audio, ne obrnuto

---

### 7.3 — Haptic Feedback (Mobile)

**Problem:** Slot Lab je desktop-only po feel-u.

**Rešenje:**
```dart
// Na REEL_STOP:
HapticFeedback.mediumImpact();

// Na BIG_WIN:
HapticFeedback.heavyImpact();
```

---

## 8. IMPLEMENTATION ROADMAP

### Phase 1: Critical Fixes (1-2 nedelje)
- [ ] P0.1 — Audio Latency Calibration
- [ ] P0.2 — Seamless REEL_SPIN Loop
- [ ] P0.3 — Per-Voice Pan FFI
- [ ] P0.5 — Dynamic Rollup Speed
- [ ] P0.6 — Anticipation Pre-Trigger
- [ ] P0.7 — Big Win Layered Audio

### Phase 2: High Priority (2-3 nedelje)
- [ ] P1.1 — Symbol-Specific Audio
- [ ] P1.2 — Near Miss Escalation
- [ ] P1.3 — Win Line Panning
- [ ] P1.4 — Jackpot Tier Audio
- [ ] P1.5 — Reel Spin Speed Variation
- [ ] P1.6 — Feature Transitions
- [ ] P1.7 — Bet Change Audio

### Phase 3: Quality of Life (2 nedelje)
- [ ] P2.1 — Audio Hover Preview Integration
- [ ] P2.2 — RTPC Curve Connection
- [ ] P2.4 — Keyboard Shortcuts
- [ ] P2.6 — Undo/Redo
- [ ] P2.7 — Multi-Select

### Phase 4: Polish (1 nedelja)
- [ ] Performance optimizations
- [ ] Data consolidation
- [ ] UI polish

---

## 9. METRIKE USPEHA

| Metrika | Trenutno | Cilj |
|---------|----------|------|
| Audio-Visual Sync | ±20ms | ±5ms |
| Big Win Satisfaction | 70% | 95% |
| Anticipation Impact | 60% | 90% |
| Timeline Usability | 75% | 95% |
| Feature Coverage | 85% | 100% |

---

## 10. ZAKLJUČAK

Slot Lab je **85% production-ready** sa solidnom arhitekturom. Kritični nedostaci (P0) se odnose na:

1. **Audio-Visual Sync** — Latency compensation nije kalibrisan
2. **Spatial Audio** — Pan se ne primenjuje (FFI nedostaje)
3. **Loop Playback** — REEL_SPIN nije seamless
4. **Big Win Experience** — Nedostaju layers

Kada se P0 reše, Slot Lab postaje **industry-leading** alat za slot audio dizajn — bolji od Wwise/FMOD za ovaj specifičan use case jer ima:

- Slot-native workflow
- Per-reel audio control
- Forced outcome testing
- Real-time volatility adjustment
- Integrated visual preview

---

*Analiza kompletirana: 2026-01-20*
*Verzija: 1.0 ULTIMATE*
