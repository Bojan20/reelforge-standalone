# FluxForge Studio — API Reference

**Version:** 0.1.0
**Date:** 2026-01-22

---

## Table of Contents

1. [Rust FFI API](#rust-ffi-api)
2. [Dart Providers](#dart-providers)
3. [Services](#services)
4. [Models](#models)

---

## 1. Rust FFI API

### Engine Control

```rust
// Initialize engine
engine_init() -> bool

// Shutdown engine
engine_shutdown()

// Get engine state
engine_is_running() -> bool
```

### Transport

```rust
// Playback control
engine_play()
engine_pause()
engine_stop()
engine_seek(position_frames: u64)

// Get position
engine_get_position() -> u64
engine_get_position_seconds() -> f64

// Loop control
engine_set_loop_enabled(enabled: bool)
engine_set_loop_region(start: u64, end: u64)
```

### Track Management

```rust
// Create/delete tracks
engine_create_track() -> u64
engine_delete_track(track_id: u64)

// Track parameters
engine_set_track_volume(track_id: u64, volume: f64)
engine_set_track_pan(track_id: u64, pan: f64)
engine_set_track_mute(track_id: u64, muted: bool)
engine_set_track_solo(track_id: u64, soloed: bool)

// Batch operations (P1.12)
engine_batch_set_track_volumes(ids: *const u64, volumes: *const f64, count: usize)
engine_batch_set_track_pans(ids: *const u64, pans: *const f64, count: usize)
engine_batch_set_track_params(
    ids: *const u64,
    volumes: *const f64,
    pans: *const f64,
    mutes: *const bool,
    solos: *const bool,
    count: usize
)
```

### Bus System

```rust
// Bus control (0=SFX, 1=Music, 2=Voice, 3=Ambience, 4=Aux, 5=Master)
engine_set_bus_volume(bus_id: u32, volume: f64)
engine_set_bus_pan(bus_id: u32, pan: f64)
engine_set_bus_mute(bus_id: u32, muted: bool)
engine_set_bus_solo(bus_id: u32, soloed: bool)
```

### Metering

```rust
// Master metering
engine_get_peak_l() -> f64
engine_get_peak_r() -> f64
engine_get_rms_l() -> f64
engine_get_rms_r() -> f64
engine_get_lufs_momentary() -> f64
engine_get_lufs_short() -> f64
engine_get_lufs_integrated() -> f64
engine_get_true_peak_l() -> f64
engine_get_true_peak_r() -> f64
engine_get_correlation() -> f64

// Track metering (batch - P1.14)
engine_write_all_track_meters_to_buffers(
    out_ids: *mut u64,
    out_peak_l: *mut f64,
    out_peak_r: *mut f64,
    out_rms_l: *mut f64,
    out_rms_r: *mut f64,
    out_corr: *mut f64,
    max_count: usize
) -> usize
```

### One-Shot Playback

```rust
// Play audio file to bus
engine_play_one_shot(
    audio_path: *const c_char,
    bus_id: u32,
    volume: f64,
    pan: f64,
    source: u8  // 0=DAW, 1=SlotLab, 2=Middleware, 3=Browser
) -> u64  // Returns voice ID

// Play looping sound
engine_play_looping(
    audio_path: *const c_char,
    bus_id: u32,
    volume: f64
) -> u64

// Stop voice
engine_stop_voice(voice_id: u64)
engine_stop_all_voices()

// Section-based filtering
engine_set_active_section(section: u8)  // 0=DAW, 1=SlotLab, 2=Middleware
```

### Container FFI (P2/P3)

```rust
// Blend containers
container_create_blend(config_json: *const c_char) -> u64
container_evaluate_blend(id: u64, rtpc_value: f64, out_results: *mut BlendEvalResult, max: usize) -> usize
container_set_blend_rtpc_target(id: u64, target: f64)  // P3.4: Smoothed RTPC

// Random containers
container_create_random(config_json: *const c_char) -> u64
container_select_random(id: u64, out_result: *mut RandomSelectResult) -> bool

// Sequence containers
container_create_sequence(config_json: *const c_char) -> u64
container_tick_sequence(id: u64, out_result: *mut SequenceTickResult) -> bool
container_start_sequence(id: u64)
container_stop_sequence(id: u64)

// Container groups (P3.3C)
container_create_group(config_json: *const c_char) -> u64
container_evaluate_group(id: u64, out_results: *mut GroupEvalResult, max: usize) -> usize

// Cleanup
container_delete(id: u64)
```

### Waveform Cache

```rust
// Cache management
wave_cache_get_or_build(
    audio_path: *const c_char,
    sample_rate: u32,
    channels: u8,
    total_frames: u64
) -> *mut WaveCacheResult

// Query tiles
wave_cache_query_tiles(
    audio_path: *const c_char,
    start_frame: u64,
    end_frame: u64,
    pixels_per_second: f64,
    sample_rate: u32
) -> *mut TileQueryResult
```

---

## 2. Dart Providers

### MiddlewareProvider

Central state management for middleware systems.

```dart
class MiddlewareProvider extends ChangeNotifier {
  // State Groups
  List<StateGroup> get stateGroups;
  void addStateGroup(StateGroup group);
  void setActiveState(String groupId, String stateId);
  String? getActiveState(String groupId);

  // Switch Groups
  List<SwitchGroup> get switchGroups;
  void addSwitchGroup(SwitchGroup group);
  void setObjectSwitch(String groupId, String objectId, String switchId);

  // RTPC
  List<RtpcDefinition> get rtpcDefinitions;
  void addRtpcDefinition(RtpcDefinition def);
  void setRtpcValue(String rtpcId, double value);
  double getRtpcValue(String rtpcId);

  // Ducking
  List<DuckingRule> get duckingRules;
  void addDuckingRule(DuckingRule rule);
  void removeDuckingRule(String ruleId);

  // Containers
  List<BlendContainer> get blendContainers;
  List<RandomContainer> get randomContainers;
  List<SequenceContainer> get sequenceContainers;

  // Composite Events
  Map<String, SlotCompositeEvent> get compositeEvents;
  void addCompositeEvent(SlotCompositeEvent event);
  void addLayerToEvent(String eventId, AudioLayer layer);
  void removeLayerFromEvent(String eventId, String layerId);
}
```

### SlotLabProvider

Slot machine simulation and stage event management.

```dart
class SlotLabProvider extends ChangeNotifier {
  // Spin control
  Future<void> spin();
  Future<void> spinForced(ForcedOutcome outcome);

  // Results
  SpinResult? get lastResult;
  List<StageEvent> get lastStages;
  bool get isPlayingStages;

  // Configuration
  void setTimingProfile(TimingProfile profile);
  void setVolatility(VolatilityProfile volatility);

  // Event playback
  void triggerStage(String stage);
  void stopAllStages();
}
```

### ALEProvider

Adaptive Layer Engine state management.

```dart
class ALEProvider extends ChangeNotifier {
  // Signals
  void updateSignal(String signalId, double value);
  double getSignalNormalized(String signalId);
  Map<String, double> get currentSignals;

  // Contexts
  void enterContext(String contextId);
  void exitContext(String contextId);
  String? get activeContext;

  // Levels
  int get currentLevel;  // 1-5
  void setLevel(int level);
  void stepUp();
  void stepDown();

  // Layer volumes
  Map<int, double> get layerVolumes;  // level -> volume (0.0-1.0)

  // Profile
  Future<void> loadProfile(String path);
  Future<void> exportProfile(String path);
}
```

### MixerProvider

DAW mixer state (separate from MixerDSPProvider).

```dart
class MixerProvider extends ChangeNotifier {
  // Track control
  void setTrackVolume(int trackId, double volume);
  void setTrackPan(int trackId, double pan);
  void setTrackMute(int trackId, bool muted);
  void setTrackSolo(int trackId, bool soloed);

  // Bus control
  void setBusVolume(int busId, double volume);
  void setBusPan(int busId, double pan);
  void setBusMute(int busId, bool muted);
  void setBusSolo(int busId, bool soloed);

  // Routing
  void setTrackOutput(int trackId, int busId);
}
```

---

## 3. Services

### EventRegistry

Central audio event trigger system.

```dart
class EventRegistry {
  static final instance = EventRegistry._();

  // Event registration
  void registerEvent(AudioEvent event);
  void unregisterEvent(String eventId);

  // Stage triggering
  void triggerStage(String stage, {Map<String, dynamic>? context});
  void stopStage(String stage);
  void stopAll();

  // Queries
  AudioEvent? getEventForStage(String stage);
  List<String> getStagesForEvent(String eventId);
  int get registeredEventCount;
}
```

### ContainerService

Container evaluation and playback.

```dart
class ContainerService {
  static final instance = ContainerService._();

  // Blend containers
  Future<List<BlendEvalResult>> evaluateBlend(String containerId, double rtpcValue);
  void triggerBlendContainer(String containerId, double rtpcValue);

  // Random containers
  Future<RandomSelectResult?> selectRandom(String containerId);
  void triggerRandomContainer(String containerId);

  // Sequence containers
  void startSequence(String containerId);
  void stopSequence(String containerId);

  // Sync to Rust (P2)
  void syncBlendToRust(BlendContainer container);
  void syncRandomToRust(RandomContainer container);
  void syncSequenceToRust(SequenceContainer container);
}
```

### AudioPlaybackService

Low-level audio playback via FFI.

```dart
class AudioPlaybackService {
  static final instance = AudioPlaybackService._();

  // One-shot playback
  Future<int> playFileToBus(
    String audioPath,
    int busId, {
    double volume = 1.0,
    double pan = 0.0,
    PlaybackSource source = PlaybackSource.daw,
  });

  // Looping playback
  Future<int> playLoopingToBus(String audioPath, int busId, {double volume = 1.0});

  // Stop
  void stopVoice(int voiceId);
  void stopAllVoices();
}
```

### UnifiedPlaybackController

Section-based playback isolation.

```dart
class UnifiedPlaybackController {
  static final instance = UnifiedPlaybackController._();

  // Section control
  bool acquireSection(PlaybackSection section);
  void releaseSection(PlaybackSection section);
  PlaybackSection get activeSection;

  // Status
  bool get isDawPlaying;
  bool get isSlotLabPlaying;
  bool get isMiddlewarePlaying;
}

enum PlaybackSection { daw, slotLab, middleware, browser }
```

---

## 4. Models

### AudioEvent

```dart
class AudioEvent {
  final String id;
  final String name;
  final String stage;          // Stage trigger (e.g., "SPIN_START")
  final List<AudioLayer> layers;
  final double durationMs;
  final bool loop;
  final int priority;          // 0-100
  final ContainerType containerType;
  final String? containerId;
}
```

### AudioLayer

```dart
class AudioLayer {
  final String id;
  final String audioPath;
  final double volume;         // 0.0-1.5
  final double pan;            // -1.0 to 1.0
  final double delayMs;        // Start delay
  final double offsetMs;       // Skip into audio
  final int busId;             // Target bus
}
```

### StateGroup

```dart
class StateGroup {
  final String id;
  final String name;
  final List<StateDefinition> states;
  final String defaultStateId;
}

class StateDefinition {
  final String id;
  final String name;
  final Map<String, dynamic> properties;
}
```

### RtpcDefinition

```dart
class RtpcDefinition {
  final String id;
  final String name;
  final double minValue;
  final double maxValue;
  final double defaultValue;
  final RtpcCurve curve;
}

enum RtpcCurve { linear, logarithmic, exponential, sCurve }
```

### BlendContainer

```dart
class BlendContainer {
  final String id;
  final String name;
  final String rtpcId;
  final List<BlendChild> children;
  final double smoothingMs;    // P3.4: Parameter smoothing
}

class BlendChild {
  final String id;
  final String audioPath;
  final double rangeMin;
  final double rangeMax;
  final double volumeAtMin;
  final double volumeAtMax;
}
```

### RandomContainer

```dart
class RandomContainer {
  final String id;
  final String name;
  final List<RandomChild> children;
  final RandomMode mode;       // random, shuffle, roundRobin
  final double pitchVariation;
  final double volumeVariation;
}

class RandomChild {
  final String id;
  final String audioPath;
  final double weight;         // Selection weight
}
```

### SequenceContainer

```dart
class SequenceContainer {
  final String id;
  final String name;
  final List<SequenceStep> steps;
  final SequenceMode mode;     // loop, hold, pingPong, oneShot
  final double bpm;
}

class SequenceStep {
  final String id;
  final String audioPath;
  final double durationBeats;
  final double delayBeats;
}
```

---

## Appendix: Bus IDs

| ID | Name | Constant |
|----|------|----------|
| 0 | SFX | `BusId.sfx` |
| 1 | Music | `BusId.music` |
| 2 | Voice | `BusId.voice` |
| 3 | Ambience | `BusId.ambience` |
| 4 | Aux | `BusId.aux` |
| 5 | Master | `BusId.master` |

## Appendix: Playback Sources

| ID | Name | Filtering |
|----|------|-----------|
| 0 | DAW | Always plays |
| 1 | SlotLab | Filtered when section inactive |
| 2 | Middleware | Filtered when section inactive |
| 3 | Browser | Always plays (isolated) |

---

*Generated by Claude Code — FluxForge Studio API Reference*
