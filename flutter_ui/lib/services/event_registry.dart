/// FluxForge Event Registry — Centralni Audio Event System
///
/// Wwise/FMOD-style arhitektura:
/// - Event je DEFINICIJA (layers, timing, parameters)
/// - Stage je TRIGGER (kada se pušta)
/// - Registry POVEZUJE stage → event
///
/// Prednosti:
/// - Jedan event može biti triggerovan iz više izvora
/// - Timeline editor samo definiše zvuk
/// - Game engine šalje samo stage name
/// - Hot-reload audio bez restarta
///
/// Audio playback koristi Rust engine preko FFI (unified audio stack)
///
/// AudioPool Integration:
/// - Rapid-fire events (CASCADE_STEP, ROLLUP_TICK) use voice pooling
/// - Pool hit = instant playback, Pool miss = new voice allocation
/// - Configurable via AudioPoolConfig for different scenarios

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../spatial/auto_spatial.dart';
import '../src/rust/native_ffi.dart';
import 'audio_playback_service.dart';
import 'audio_pool.dart';
import 'container_service.dart';
import 'ducking_service.dart';
import 'recent_favorites_service.dart';
import 'rtpc_modulation_service.dart';
import 'stage_configuration_service.dart';
import 'unified_playback_controller.dart';

// =============================================================================
// AUDIO LAYER — Pojedinačni zvuk u eventu
// =============================================================================

class AudioLayer {
  final String id;
  final String audioPath;
  final String name;
  final double volume;
  final double pan;
  final double delay; // Delay pre početka (ms)
  final double offset; // Offset unutar timeline-a (seconds)
  final int busId;

  const AudioLayer({
    required this.id,
    required this.audioPath,
    required this.name,
    this.volume = 1.0,
    this.pan = 0.0,
    this.delay = 0.0,
    this.offset = 0.0,
    this.busId = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'audioPath': audioPath,
    'name': name,
    'volume': volume,
    'pan': pan,
    'delay': delay,
    'offset': offset,
    'busId': busId,
  };

  factory AudioLayer.fromJson(Map<String, dynamic> json) => AudioLayer(
    id: json['id'] as String,
    audioPath: json['audioPath'] as String,
    name: json['name'] as String,
    volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
    pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
    delay: (json['delay'] as num?)?.toDouble() ?? 0.0,
    offset: (json['offset'] as num?)?.toDouble() ?? 0.0,
    busId: json['busId'] as int? ?? 0,
  );
}

// =============================================================================
// CONTAINER TYPE — Enum za tip kontejnera
// =============================================================================

/// Container type for AudioEvent delegation
enum ContainerType {
  none,      // Direct layer playback (default)
  blend,     // BlendContainer — RTPC-based crossfade
  random,    // RandomContainer — Weighted random selection
  sequence,  // SequenceContainer — Timed sound sequence
}

extension ContainerTypeExtension on ContainerType {
  String get displayName {
    switch (this) {
      case ContainerType.none: return 'None (Direct)';
      case ContainerType.blend: return 'Blend Container';
      case ContainerType.random: return 'Random Container';
      case ContainerType.sequence: return 'Sequence Container';
    }
  }

  int get value => index;

  static ContainerType fromValue(int v) {
    if (v < 0 || v >= ContainerType.values.length) return ContainerType.none;
    return ContainerType.values[v];
  }
}

// =============================================================================
// AUDIO EVENT — Kompletna definicija zvučnog eventa
// =============================================================================

class AudioEvent {
  final String id;
  final String name;
  final String stage; // Koji stage trigeruje ovaj event
  final List<AudioLayer> layers;
  final double duration; // Ukupno trajanje eventa (seconds)
  final bool loop;
  final int priority; // Viši priority prekida niži

  // Container integration fields
  final ContainerType containerType;  // Type of container to use
  final int? containerId;             // ID of the container (if using container)

  const AudioEvent({
    required this.id,
    required this.name,
    required this.stage,
    required this.layers,
    this.duration = 0.0,
    this.loop = false,
    this.priority = 0,
    this.containerType = ContainerType.none,
    this.containerId,
  });

  /// Returns true if this event uses a container instead of direct layers
  bool get usesContainer => containerType != ContainerType.none && containerId != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'stage': stage,
    'layers': layers.map((l) => l.toJson()).toList(),
    'duration': duration,
    'loop': loop,
    'priority': priority,
    'containerType': containerType.value,
    'containerId': containerId,
  };

  factory AudioEvent.fromJson(Map<String, dynamic> json) => AudioEvent(
    id: json['id'] as String,
    name: json['name'] as String,
    stage: json['stage'] as String,
    layers: (json['layers'] as List<dynamic>)
        .map((l) => AudioLayer.fromJson(l as Map<String, dynamic>))
        .toList(),
    duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
    loop: json['loop'] as bool? ?? false,
    priority: json['priority'] as int? ?? 0,
    containerType: ContainerTypeExtension.fromValue(json['containerType'] as int? ?? 0),
    containerId: json['containerId'] as int?,
  );

  /// Create a copy with modified fields
  AudioEvent copyWith({
    String? id,
    String? name,
    String? stage,
    List<AudioLayer>? layers,
    double? duration,
    bool? loop,
    int? priority,
    ContainerType? containerType,
    int? containerId,
  }) {
    return AudioEvent(
      id: id ?? this.id,
      name: name ?? this.name,
      stage: stage ?? this.stage,
      layers: layers ?? this.layers,
      duration: duration ?? this.duration,
      loop: loop ?? this.loop,
      priority: priority ?? this.priority,
      containerType: containerType ?? this.containerType,
      containerId: containerId ?? this.containerId,
    );
  }
}

// =============================================================================
// P1.4: TRIGGER HISTORY ENTRY — For UI display and debugging
// =============================================================================

class TriggerHistoryEntry {
  final DateTime timestamp;
  final String stage;
  final String eventName;
  final List<String> layerNames;
  final bool success;
  final String? error;
  final ContainerType? containerType;

  const TriggerHistoryEntry({
    required this.timestamp,
    required this.stage,
    required this.eventName,
    required this.layerNames,
    required this.success,
    this.error,
    this.containerType,
  });
}

// =============================================================================
// PLAYING INSTANCE — Aktivna instanca eventa (using Rust engine)
// =============================================================================

class _PlayingInstance {
  final String eventId;
  final List<int> voiceIds; // Rust voice IDs from PlaybackEngine one-shots
  final DateTime startTime;

  _PlayingInstance({
    required this.eventId,
    required this.voiceIds,
    required this.startTime,
  });

  Future<void> stop() async {
    try {
      // Stop each voice individually through bus routing
      for (final voiceId in voiceIds) {
        NativeFFI.instance.playbackStopOneShot(voiceId);
      }
    } catch (e) {
      debugPrint('[EventRegistry] Stop error: $e');
    }
  }
}

// =============================================================================
// EVENT REGISTRY — Centralni sistem
// =============================================================================

/// Events that benefit from voice pooling (rapid-fire playback)
/// These are short, frequently triggered sounds that need instant response
const _pooledEventStages = {
  // Reel stops (core gameplay, 0-indexed for 5-reel slots)
  'REEL_STOP',
  'REEL_STOP_0',
  'REEL_STOP_1',
  'REEL_STOP_2',
  'REEL_STOP_3',
  'REEL_STOP_4',
  'REEL_STOP_SOFT',
  'REEL_QUICK_STOP',
  'REEL_STOP_TICK',
  // Cascade/Tumble (rapid sequence)
  'CASCADE_STEP',
  'CASCADE_SYMBOL_POP',
  'CASCADE_SYMBOL_POP_0',
  'CASCADE_SYMBOLS_FALL',
  'CASCADE_SYMBOLS_LAND',
  'TUMBLE_DROP',
  'TUMBLE_LAND',
  // Rollup counter (very rapid)
  'ROLLUP_TICK',
  'ROLLUP_TICK_SLOW',
  'ROLLUP_TICK_FAST',
  // Win evaluation (rapid highlighting)
  'WIN_LINE_SHOW',
  'WIN_LINE_FLASH',
  'WIN_LINE_TRACE',
  'WIN_SYMBOL_HIGHLIGHT',
  'WIN_CLUSTER_HIGHLIGHT',
  // UI clicks (instant response needed)
  'UI_BUTTON_PRESS',
  'UI_BUTTON_HOVER',
  'UI_BET_UP',
  'UI_BET_DOWN',
  'UI_TAB_SWITCH',
  // Symbol lands (rapid sequence during stop)
  'SYMBOL_LAND',
  'SYMBOL_LAND_LOW',
  'SYMBOL_LAND_MID',
  'SYMBOL_LAND_HIGH',
  // Wheel ticks
  'WHEEL_TICK',
  'WHEEL_TICK_FAST',
  'WHEEL_TICK_SLOW',
  // Trail steps
  'TRAIL_MOVE_STEP',
  // Hold & Spin
  'HOLD_RESPIN_STOP',
  // Progressive meter
  'PROGRESSIVE_TICK',
  'PROGRESSIVE_CONTRIBUTION',
};

class EventRegistry extends ChangeNotifier {
  // Stage → Event mapping
  final Map<String, AudioEvent> _stageToEvent = {};

  // Event ID → Event
  final Map<String, AudioEvent> _events = {};

  // P1.3: Constructor starts cleanup timer
  EventRegistry() {
    _startCleanupTimer();
  }

  /// P1.3: Start periodic cleanup timer
  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) => _cleanupStaleInstances());
  }

  /// P1.3: Remove instances older than _instanceMaxAge
  void _cleanupStaleInstances() {
    final now = DateTime.now();
    final toRemove = <_PlayingInstance>[];

    for (final instance in _playingInstances) {
      final age = now.difference(instance.startTime);
      if (age > _instanceMaxAge) {
        toRemove.add(instance);
      }
    }

    if (toRemove.isNotEmpty) {
      for (final instance in toRemove) {
        // Stop any still-playing voices
        for (final voiceId in instance.voiceIds) {
          try {
            NativeFFI.instance.playbackStopOneShot(voiceId);
          } catch (_) {}
        }
      }
      _playingInstances.removeWhere((i) => toRemove.contains(i));
      _cleanedInstances += toRemove.length;
      debugPrint('[EventRegistry] 🧹 Cleaned up ${toRemove.length} stale instance(s)');
    }
  }

  // Currently playing instances
  final List<_PlayingInstance> _playingInstances = [];

  // Preloaded paths (for tracking)
  final Set<String> _preloadedPaths = {};

  // Audio pool for rapid-fire events
  bool _useAudioPool = true;

  // P1.2: Voice limit per event (prevents runaway voice spawning)
  // Increased from 8 to 32 — with auto-cleanup, this should rarely be hit
  static const int _maxVoicesPerEvent = 32;
  int _voiceLimitRejects = 0;
  int get voiceLimitRejects => _voiceLimitRejects;

  // P1.3: Instance cleanup timer (removes stale playing instances)
  // Reduced from 30s to 10s — most slot sounds are < 3 seconds
  static const Duration _instanceMaxAge = Duration(seconds: 10);
  static const Duration _cleanupInterval = Duration(seconds: 5);
  Timer? _cleanupTimer;
  int _cleanedInstances = 0;
  int get cleanedInstances => _cleanedInstances;

  // P1.4: Trigger history ring buffer (for UI debugging)
  static const int _maxHistoryEntries = 100;
  final List<TriggerHistoryEntry> _triggerHistory = [];

  // P0: Per-reel spin loop voice tracking
  // Maps reel index (0-4) to voice ID for individual fade-out on REEL_STOP_N
  final Map<int, int> _reelSpinLoopVoices = {};
  static const int _spinLoopFadeMs = 50; // Fade duration for smooth stop

  /// P0: Fade out a specific reel's spin loop with smooth crossfade
  void _fadeOutReelSpinLoop(int reelIndex) {
    final voiceId = _reelSpinLoopVoices[reelIndex];
    if (voiceId != null && voiceId > 0) {
      debugPrint('[EventRegistry] P0: Fading out REEL_SPIN loop for reel $reelIndex (voice $voiceId, ${_spinLoopFadeMs}ms)');
      AudioPlaybackService.instance.fadeOutVoice(voiceId, fadeMs: _spinLoopFadeMs);
      _reelSpinLoopVoices.remove(reelIndex);
    }
  }

  /// P0: Track a spin loop voice for later fade-out
  void _trackReelSpinLoopVoice(int reelIndex, int voiceId) {
    // Stop any existing loop on this reel first
    final existingVoiceId = _reelSpinLoopVoices[reelIndex];
    if (existingVoiceId != null && existingVoiceId != voiceId) {
      debugPrint('[EventRegistry] P0: Replacing existing spin loop on reel $reelIndex');
      AudioPlaybackService.instance.fadeOutVoice(existingVoiceId, fadeMs: _spinLoopFadeMs);
    }
    _reelSpinLoopVoices[reelIndex] = voiceId;
    debugPrint('[EventRegistry] P0: Tracking REEL_SPIN loop: reel=$reelIndex, voice=$voiceId');
  }

  /// P0: Stop all spin loops (called when spin ends abruptly)
  void stopAllSpinLoops() {
    for (final entry in _reelSpinLoopVoices.entries) {
      debugPrint('[EventRegistry] P0: Stopping spin loop: reel=${entry.key}, voice=${entry.value}');
      AudioPlaybackService.instance.fadeOutVoice(entry.value, fadeMs: _spinLoopFadeMs);
    }
    _reelSpinLoopVoices.clear();
  }

  /// P1.4: Get recent trigger history (newest first)
  List<TriggerHistoryEntry> get triggerHistory => List.unmodifiable(_triggerHistory.reversed.toList());

  /// P1.4: Get last N history entries
  List<TriggerHistoryEntry> getRecentHistory(int count) {
    final entries = _triggerHistory.reversed.take(count).toList();
    return entries;
  }

  /// P1.4: Clear history
  void clearHistory() {
    _triggerHistory.clear();
    notifyListeners();
  }

  /// P1.4: Record a trigger in history
  void _recordTrigger({
    required String stage,
    required String eventName,
    required List<String> layerNames,
    required bool success,
    String? error,
    ContainerType? containerType,
  }) {
    final entry = TriggerHistoryEntry(
      timestamp: DateTime.now(),
      stage: stage,
      eventName: eventName,
      layerNames: layerNames,
      success: success,
      error: error,
      containerType: containerType,
    );

    _triggerHistory.add(entry);

    // Ring buffer: remove oldest if over limit
    while (_triggerHistory.length > _maxHistoryEntries) {
      _triggerHistory.removeAt(0);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AUTO SPATIAL ENGINE — UI-driven spatial audio positioning
  // ═══════════════════════════════════════════════════════════════════════════
  final AutoSpatialEngine _spatialEngine = AutoSpatialEngine();
  bool _useSpatialAudio = true;

  /// Get spatial engine for external anchor registration
  AutoSpatialEngine get spatialEngine => _spatialEngine;

  /// Enable/disable spatial audio positioning
  void setUseSpatialAudio(bool enabled) {
    _useSpatialAudio = enabled;
    debugPrint('[EventRegistry] Spatial audio: ${enabled ? "ENABLED" : "DISABLED"}');
  }

  /// Check if spatial audio is enabled
  bool get useSpatialAudio => _useSpatialAudio;

  // Stats
  int _triggerCount = 0;
  int _pooledTriggers = 0;
  int _spatialTriggers = 0;
  int get triggerCount => _triggerCount;
  int get pooledTriggers => _pooledTriggers;
  int get spatialTriggers => _spatialTriggers;

  // Last triggered event info (for Event Log display)
  String _lastTriggeredEventName = '';
  String _lastTriggeredStage = '';
  List<String> _lastTriggeredLayers = [];
  bool _lastTriggerSuccess = false;
  String _lastTriggerError = '';
  // Container info for last triggered event
  ContainerType _lastContainerType = ContainerType.none;
  String? _lastContainerName;
  int _lastContainerChildCount = 0;
  // Stage timestamp from Rust (for correct ordering in Event Log)
  double _lastStageTimestampMs = 0.0;

  String get lastTriggeredEventName => _lastTriggeredEventName;
  String get lastTriggeredStage => _lastTriggeredStage;
  List<String> get lastTriggeredLayers => _lastTriggeredLayers;
  bool get lastTriggerSuccess => _lastTriggerSuccess;
  String get lastTriggerError => _lastTriggerError;
  ContainerType get lastContainerType => _lastContainerType;
  String? get lastContainerName => _lastContainerName;
  int get lastContainerChildCount => _lastContainerChildCount;
  double get lastStageTimestampMs => _lastStageTimestampMs;

  /// Get all registered stages (for debugging)
  Iterable<String> get registeredStages => _stageToEvent.keys;

  /// Enable/disable audio pooling for rapid-fire events
  void setUseAudioPool(bool enabled) {
    _useAudioPool = enabled;
    debugPrint('[EventRegistry] Audio pooling: ${enabled ? "ENABLED" : "DISABLED"}');
  }

  /// Check if a stage should use pooling
  /// Now delegated to StageConfigurationService for centralized configuration
  bool _shouldUsePool(String stage) {
    if (!_useAudioPool) return false;
    return StageConfigurationService.instance.isPooled(stage);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.1 SECURITY: Audio Path Validation
  // Prevents path traversal attacks (../../etc/passwd)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Allowed audio file extensions
  static const _allowedAudioExtensions = {'.wav', '.mp3', '.ogg', '.flac', '.aiff', '.aif'};

  /// Validate audio path for security
  /// Returns true if path is safe, false otherwise
  bool _validateAudioPath(String path) {
    if (path.isEmpty) return false;

    // Check for path traversal attempts
    if (path.contains('..')) {
      debugPrint('[EventRegistry] ⛔ SECURITY: Path traversal attempt blocked: $path');
      return false;
    }

    // Check for null bytes (injection attempt)
    if (path.contains('\x00')) {
      debugPrint('[EventRegistry] ⛔ SECURITY: Null byte in path blocked: $path');
      return false;
    }

    // Check file extension
    final lowerPath = path.toLowerCase();
    final hasValidExtension = _allowedAudioExtensions.any((ext) => lowerPath.endsWith(ext));
    if (!hasValidExtension) {
      debugPrint('[EventRegistry] ⚠️ Invalid audio extension: $path');
      return false;
    }

    // Check for suspicious patterns
    if (path.contains('\n') || path.contains('\r') || path.contains('|') || path.contains(';')) {
      debugPrint('[EventRegistry] ⛔ SECURITY: Suspicious characters in path blocked: $path');
      return false;
    }

    return true;
  }

  /// Get priority level for a stage (0-100, higher = more important)
  /// Now delegated to StageConfigurationService for centralized configuration
  int _stageToPriority(String stage) {
    return StageConfigurationService.instance.getPriority(stage);
  }

  /// Map stage name to SpatialBus
  /// Now delegated to StageConfigurationService for centralized configuration
  SpatialBus _stageToBus(String stage, int busId) {
    final serviceBus = StageConfigurationService.instance.getBus(stage);
    // If service returns default and busId is provided, use busId for fallback
    if (busId > 0) {
      return switch (busId) {
        1 => SpatialBus.music,
        2 => SpatialBus.sfx,
        3 => SpatialBus.vo,
        4 => SpatialBus.ui,
        5 => SpatialBus.ambience,
        _ => serviceBus,
      };
    }
    return serviceBus;
  }

  /// Get spatial intent from stage name (maps to SlotIntentRules)
  /// Now delegated to StageConfigurationService for centralized configuration
  String _stageToIntent(String stage) {
    return StageConfigurationService.instance.getSpatialIntent(stage);
  }

  // ==========================================================================
  // REGISTRATION
  // ==========================================================================

  /// Registruj event za stage
  /// CRITICAL: This REPLACES any existing event with same ID or stage
  /// Stops any playing instances ONLY if the event data has changed
  void registerEvent(AudioEvent event) {
    final existingEvent = _events[event.id];

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL FIX: Only stop audio if the event data has ACTUALLY CHANGED
    // This prevents audio cutoff during sync operations that re-register
    // the same event with identical data.
    // ═══════════════════════════════════════════════════════════════════════════
    if (existingEvent != null) {
      // Check if event data has changed (layers, duration, etc.)
      final hasChanged = !_eventsAreEquivalent(existingEvent, event);
      if (hasChanged) {
        // Event data changed - stop all playing instances SYNCHRONOUSLY
        _stopEventSync(event.id);
        debugPrint('[EventRegistry] Event changed - stopping existing instances: ${event.name}');
      } else {
        // Event data is identical - skip update, keep playing
        debugPrint('[EventRegistry] Event unchanged - skipping re-registration: ${event.name}');
        return; // Don't re-register if identical
      }
    }

    // Also check if another event has this stage (shouldn't happen but defensive)
    final existingByStage = _stageToEvent[event.stage];
    if (existingByStage != null && existingByStage.id != event.id) {
      _stopEventSync(existingByStage.id);
      _events.remove(existingByStage.id);
      debugPrint('[EventRegistry] Removed conflicting event for stage: ${event.stage}');
    }

    _events[event.id] = event;
    _stageToEvent[event.stage] = event;

    // Log layer details for debugging
    final layerPaths = event.layers.map((l) => l.audioPath.split('/').last).join(', ');
    debugPrint('[EventRegistry] Registered: ${event.name} → ${event.stage} (${event.layers.length} layers: $layerPaths)');

    // Update preloaded paths
    for (final layer in event.layers) {
      if (layer.audioPath.isNotEmpty) {
        _preloadedPaths.add(layer.audioPath);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AUTO-EXPAND: Generic stage → Per-index events
    // When user creates REEL_STOP (generic), auto-create REEL_STOP_0..4
    // Each per-reel event has the same audio but different stereo panning
    // ═══════════════════════════════════════════════════════════════════════════
    _autoExpandToPerIndexEvents(event);

    notifyListeners();
  }

  /// Auto-expand generic stages to per-index events with stereo panning
  /// e.g., REEL_STOP → REEL_STOP_0, REEL_STOP_1, ..., REEL_STOP_4
  void _autoExpandToPerIndexEvents(AudioEvent event) {
    final stage = event.stage.toUpperCase();

    // Patterns that should auto-expand with stereo panning
    const expandableWithPanning = {
      'REEL_STOP': 5,      // 5 reels
      'REEL_LAND': 5,      // Alternative name
      'WIN_LINE_SHOW': 5,  // Win line highlights per reel
      'WIN_LINE_HIDE': 5,
    };

    // Patterns that should auto-expand WITHOUT panning
    const expandableNoPanning = {
      'CASCADE_STEP': 5,
      'SYMBOL_LAND': 5,
    };

    // Check if this is a generic stage (no trailing _N)
    if (RegExp(r'_\d+$').hasMatch(stage)) {
      return; // Already specific (e.g., REEL_STOP_0), don't expand
    }

    // Check expandable patterns
    final countWithPanning = expandableWithPanning[stage];
    final countNoPanning = expandableNoPanning[stage];
    final count = countWithPanning ?? countNoPanning;
    final applyPanning = countWithPanning != null;

    if (count == null) {
      return; // Not an expandable pattern
    }

    // Get audio path from first layer
    if (event.layers.isEmpty || event.layers.first.audioPath.isEmpty) {
      return; // No audio to expand
    }
    final audioPath = event.layers.first.audioPath;

    debugPrint('[EventRegistry] 🔄 Auto-expanding $stage → ${stage}_0..${count - 1}');

    // Create per-index events
    for (int i = 0; i < count; i++) {
      // Skip if already exists
      final specificStage = '${stage}_$i';
      if (_stageToEvent.containsKey(specificStage)) {
        continue;
      }

      // Pan calculation: distribute across stereo field
      // -0.8, -0.4, 0.0, +0.4, +0.8 for 5 reels
      final pan = applyPanning && count > 1
          ? (i - (count - 1) / 2) * (2.0 / (count - 1)) * 0.8
          : 0.0;

      final specificEvent = AudioEvent(
        id: '${event.id}_$i',
        name: '${event.name} ${i + 1}',
        stage: specificStage,
        layers: [
          AudioLayer(
            id: '${event.layers.first.id}_$i',
            audioPath: audioPath,
            name: '${event.layers.first.name} (Reel $i)',
            volume: event.layers.first.volume,
            pan: pan,
            delay: event.layers.first.delay,
            offset: event.layers.first.offset,
            busId: event.layers.first.busId,
          ),
        ],
        duration: event.duration,
        loop: event.loop,
        priority: event.priority,
      );

      // Register directly to avoid recursion
      _events[specificEvent.id] = specificEvent;
      _stageToEvent[specificEvent.stage] = specificEvent;

      debugPrint('[EventRegistry] 🎰 Auto: $specificStage (pan: ${pan.toStringAsFixed(2)})');
    }
  }

  /// Synchronous stop - for use in registerEvent
  void _stopEventSync(String eventIdOrStage) {
    final eventByStage = _stageToEvent[eventIdOrStage];
    final targetEventId = eventByStage?.id ?? eventIdOrStage;

    final toRemove = <_PlayingInstance>[];
    for (final instance in _playingInstances) {
      if (instance.eventId == targetEventId) {
        // Stop each voice via bus routing (synchronous calls)
        try {
          for (final voiceId in instance.voiceIds) {
            NativeFFI.instance.playbackStopOneShot(voiceId);
          }
        } catch (e) {
          debugPrint('[EventRegistry] Stop error: $e');
        }
        toRemove.add(instance);
      }
    }

    _playingInstances.removeWhere((i) => toRemove.contains(i));
    if (toRemove.isNotEmpty) {
      debugPrint('[EventRegistry] Sync stopped ${toRemove.length} instance(s) of: $eventIdOrStage');
    }
  }

  /// Check if two AudioEvents are equivalent (same layers, same audio data)
  /// Used to avoid stopping playback when re-registering identical events
  bool _eventsAreEquivalent(AudioEvent a, AudioEvent b) {
    // Compare basic fields
    if (a.name != b.name || a.stage != b.stage || a.duration != b.duration ||
        a.loop != b.loop || a.priority != b.priority ||
        a.containerType != b.containerType || a.containerId != b.containerId) {
      return false;
    }

    // Compare layers count
    if (a.layers.length != b.layers.length) {
      return false;
    }

    // Compare each layer (order-dependent)
    for (int i = 0; i < a.layers.length; i++) {
      final layerA = a.layers[i];
      final layerB = b.layers[i];
      if (layerA.id != layerB.id ||
          layerA.audioPath != layerB.audioPath ||
          layerA.volume != layerB.volume ||
          layerA.pan != layerB.pan ||
          layerA.delay != layerB.delay ||
          layerA.offset != layerB.offset ||
          layerA.busId != layerB.busId) {
        return false;
      }
    }

    return true;
  }

  // ==========================================================================
  // AUTO-CREATE PER-REEL EVENTS
  // ==========================================================================

  /// Automatski kreira 5 REEL_STOP eventa (REEL_STOP_0 do REEL_STOP_4)
  /// sa odgovarajućim pan vrednostima za svaki reel.
  ///
  /// Pan vrednosti (5-reel grid):
  /// - REEL_STOP_0: pan = -0.8 (levo)
  /// - REEL_STOP_1: pan = -0.4
  /// - REEL_STOP_2: pan = 0.0 (centar)
  /// - REEL_STOP_3: pan = +0.4
  /// - REEL_STOP_4: pan = +0.8 (desno)
  ///
  /// [audioPath] — putanja do audio fajla
  /// [reelCount] — broj rilova (default 5)
  /// [baseName] — bazno ime eventa (default 'Reel Stop')
  ///
  /// Vraća listu kreiranih event ID-eva
  List<String> createPerReelEvents({
    required String audioPath,
    int reelCount = 5,
    String baseName = 'Reel Stop',
  }) {
    final createdIds = <String>[];

    for (int i = 0; i < reelCount; i++) {
      // Pan kalkulacija: (i - (reelCount-1)/2) * (2.0 / (reelCount-1))
      // Za 5 rilova: -0.8, -0.4, 0.0, +0.4, +0.8
      final pan = reelCount > 1
          ? (i - (reelCount - 1) / 2) * (2.0 / (reelCount - 1)) * 0.8
          : 0.0;

      final stage = 'REEL_STOP_$i';
      final eventId = 'auto_reel_stop_$i';
      final eventName = '$baseName ${i + 1}'; // 1-indexed for display

      final event = AudioEvent(
        id: eventId,
        name: eventName,
        stage: stage,
        layers: [
          AudioLayer(
            id: 'layer_$i',
            audioPath: audioPath,
            name: 'Reel $i Audio',
            volume: 1.0,
            pan: pan,
            delay: 0.0,
            offset: 0.0,
            busId: 1, // SFX bus
          ),
        ],
        duration: 500, // Default 500ms, will be overridden by actual audio
        loop: false,
        priority: 80,
      );

      registerEvent(event);
      createdIds.add(eventId);

      debugPrint('[EventRegistry] 🎰 Auto-created: $stage (pan: ${pan.toStringAsFixed(2)})');
    }

    debugPrint('[EventRegistry] ✅ Created $reelCount per-reel REEL_STOP events from: ${audioPath.split('/').last}');
    return createdIds;
  }

  /// Automatski kreira per-reel evente za bilo koji stage pattern
  /// Generička verzija za REEL_STOP, CASCADE_STEP, WIN_LINE_SHOW, itd.
  ///
  /// [baseStage] — bazni stage (npr. 'REEL_STOP', 'CASCADE_STEP')
  /// [audioPath] — putanja do audio fajla
  /// [count] — broj eventa za kreiranje
  /// [applyPanning] — da li se primenjuje stereo panning (default true za REEL_STOP)
  List<String> createPerIndexEvents({
    required String baseStage,
    required String audioPath,
    required int count,
    bool applyPanning = true,
  }) {
    final createdIds = <String>[];
    final upperStage = baseStage.toUpperCase();

    for (int i = 0; i < count; i++) {
      // Pan kalkulacija samo ako je panning uključen
      final pan = applyPanning && count > 1
          ? (i - (count - 1) / 2) * (2.0 / (count - 1)) * 0.8
          : 0.0;

      final stage = '${upperStage}_$i';
      final eventId = 'auto_${baseStage.toLowerCase()}_$i';
      final eventName = '${_humanize(baseStage)} ${i + 1}';

      final event = AudioEvent(
        id: eventId,
        name: eventName,
        stage: stage,
        layers: [
          AudioLayer(
            id: 'layer_$i',
            audioPath: audioPath,
            name: '$baseStage $i Audio',
            volume: 1.0,
            pan: pan,
            delay: 0.0,
            offset: 0.0,
            busId: 1, // SFX bus
          ),
        ],
        duration: 500,
        loop: false,
        priority: 80,
      );

      registerEvent(event);
      createdIds.add(eventId);
    }

    debugPrint('[EventRegistry] ✅ Created $count ${upperStage}_N events');
    return createdIds;
  }

  /// Humanize stage name: REEL_STOP → Reel Stop
  String _humanize(String stage) {
    return stage
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }

  /// Ukloni event
  /// CRITICAL: Stops any playing instances before removing
  void unregisterEvent(String eventId) {
    // Stop any playing instances first (synchronous)
    _stopEventSync(eventId);

    final event = _events.remove(eventId);
    if (event != null) {
      _stageToEvent.remove(event.stage);
      debugPrint('[EventRegistry] Unregistered: ${event.name} (stopped all instances)');
      notifyListeners();
    }
  }

  /// Dobij sve registrovane evente
  List<AudioEvent> get allEvents => _events.values.toList();

  /// Dobij event po stage-u
  AudioEvent? getEventForStage(String stage) => _stageToEvent[stage];

  /// Dobij event po ID-u
  AudioEvent? getEventById(String eventId) => _events[eventId];

  /// Proveri da li je stage registrovan
  bool hasEventForStage(String stage) => _stageToEvent.containsKey(stage);

  /// Proveri da li se event trenutno reprodukuje
  bool isEventPlaying(String eventId) =>
      _playingInstances.any((i) => i.eventId == eventId);

  /// P1.2: Count active voices for a specific event
  int _countActiveVoices(String eventId) {
    return _playingInstances
        .where((i) => i.eventId == eventId)
        .fold(0, (sum, i) => sum + i.voiceIds.length);
  }

  // ==========================================================================
  // FALLBACK STAGE RESOLUTION
  // ==========================================================================

  /// Get fallback stage for specific stage
  /// e.g., REEL_STOP_0 → REEL_STOP, CASCADE_STEP_3 → CASCADE_STEP
  /// Returns null if no fallback pattern applies
  String? _getFallbackStage(String stage) {
    // Pattern: STAGE_NAME_N → STAGE_NAME (remove trailing _N)
    // Examples:
    // - REEL_STOP_0 → REEL_STOP
    // - REEL_STOP_4 → REEL_STOP
    // - CASCADE_STEP_1 → CASCADE_STEP
    // - WIN_LINE_SHOW_3 → WIN_LINE_SHOW
    // - SYMBOL_LAND_5 → SYMBOL_LAND

    // Check if stage ends with _N where N is 0-9
    final match = RegExp(r'^(.+)_(\d+)$').firstMatch(stage);
    if (match != null) {
      final baseName = match.group(1)!;
      // Only provide fallback for known patterns
      const fallbackablePatterns = {
        'REEL_STOP',
        'CASCADE_STEP',
        'WIN_LINE_SHOW',
        'WIN_LINE_HIDE',
        'SYMBOL_LAND',
        'ROLLUP_TICK',
        'WHEEL_TICK',
        'TRAIL_MOVE_STEP',
      };

      if (fallbackablePatterns.contains(baseName)) {
        return baseName;
      }
    }

    return null;
  }

  // ==========================================================================
  // TRIGGERING
  // ==========================================================================

  /// Trigeruj event po stage-u
  /// FIXED: Case-insensitive lookup — normalizes stage to UPPERCASE
  ///
  /// Input validation:
  /// - Max 128 characters
  /// - Only A-Z, 0-9, underscore allowed
  /// - Empty strings rejected
  Future<void> triggerStage(String stage, {Map<String, dynamic>? context}) async {
    // ═══════════════════════════════════════════════════════════════════════════
    // P0: PER-REEL SPIN LOOP FADE-OUT — Fade out this reel's loop before playing stop sound
    // ═══════════════════════════════════════════════════════════════════════════
    final fadeOutReelIndex = context?['fade_out_spin_reel'];
    if (fadeOutReelIndex != null && fadeOutReelIndex is int) {
      _fadeOutReelSpinLoop(fadeOutReelIndex);
    }

    // P0: AUTO-DETECT REEL_STOP_X stages and fade out corresponding spin loop
    // Supports: REEL_STOP_0, REEL_STOP_1, REEL_STOP_2, REEL_STOP_3, REEL_STOP_4
    final upperStage = stage.toUpperCase();
    final reelStopMatch = RegExp(r'^REEL_STOP_(\d+)$').firstMatch(upperStage);
    if (reelStopMatch != null) {
      final reelIndex = int.tryParse(reelStopMatch.group(1) ?? '');
      if (reelIndex != null) {
        debugPrint('[EventRegistry] P0: Auto-detected REEL_STOP_$reelIndex → Fading spin loop');
        _fadeOutReelSpinLoop(reelIndex);
      }
    }

    // P0: AUTO-DETECT REEL_SPINNING_X stages and set up per-reel spin loop context
    // Supports: REEL_SPINNING_0, REEL_SPINNING_1, REEL_SPINNING_2, REEL_SPINNING_3, REEL_SPINNING_4
    // Also matches generic REEL_SPINNING (for shared loop sound)
    Map<String, dynamic> enhancedContext = context != null ? Map.from(context) : {};
    final reelSpinMatch = RegExp(r'^REEL_SPINNING_(\d+)$').firstMatch(upperStage);
    if (reelSpinMatch != null) {
      final reelIndex = int.tryParse(reelSpinMatch.group(1) ?? '');
      if (reelIndex != null) {
        debugPrint('[EventRegistry] P0: Auto-detected REEL_SPINNING_$reelIndex → Setting up spin loop');
        enhancedContext['is_reel_spin_loop'] = true;
        enhancedContext['reel_index'] = reelIndex;
      }
    } else if (upperStage == 'REEL_SPINNING' || upperStage == 'REEL_SPIN_LOOP') {
      // Generic spin loop (reel index 0 for single shared loop)
      debugPrint('[EventRegistry] P0: Auto-detected generic REEL_SPINNING → Setting up shared spin loop');
      enhancedContext['is_reel_spin_loop'] = true;
      enhancedContext['reel_index'] = 0;
    }
    context = enhancedContext.isNotEmpty ? enhancedContext : context;

    // ═══════════════════════════════════════════════════════════════════════════
    // INPUT VALIDATION (P1.2 Security Fix)
    // ═══════════════════════════════════════════════════════════════════════════
    if (stage.isEmpty) {
      debugPrint('[EventRegistry] ⚠️ Empty stage name rejected');
      return;
    }
    if (stage.length > 128) {
      debugPrint('[EventRegistry] ⚠️ Stage name too long (${stage.length} > 128): "${stage.substring(0, 32)}..."');
      return;
    }
    // Allow only alphanumeric + underscore (prevent injection)
    final validChars = RegExp(r'^[A-Za-z0-9_]+$');
    if (!validChars.hasMatch(stage)) {
      debugPrint('[EventRegistry] ⚠️ Stage name contains invalid characters: "$stage"');
      return;
    }

    final normalizedStage = stage.toUpperCase().trim();

    // Try exact match first, then normalized
    var event = _stageToEvent[stage];
    event ??= _stageToEvent[normalizedStage];

    // If still not found, try case-insensitive search through all keys
    if (event == null) {
      for (final key in _stageToEvent.keys) {
        if (key.toUpperCase() == normalizedStage) {
          event = _stageToEvent[key];
          break;
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FALLBACK: If specific stage not found, try generic version
    // e.g., REEL_STOP_0 → REEL_STOP, CASCADE_STEP_3 → CASCADE_STEP
    // ═══════════════════════════════════════════════════════════════════════════
    if (event == null) {
      final fallbackStage = _getFallbackStage(normalizedStage);
      if (fallbackStage != null) {
        event = _stageToEvent[fallbackStage];
        if (event != null) {
          debugPrint('[EventRegistry] 🔄 Using fallback: $normalizedStage → $fallbackStage');
        }
      }
    }

    if (event == null) {
      // More detailed logging for debugging
      final registeredStages = _stageToEvent.keys.take(10).join(', ');
      final suffix = _stageToEvent.length > 10 ? '...(+${_stageToEvent.length - 10} more)' : '';
      debugPrint('[EventRegistry] ❌ No event for stage: "$stage" (normalized: "$normalizedStage")');
      debugPrint('[EventRegistry] 📋 Registered stages (${_stageToEvent.length}): $registeredStages$suffix');

      // STILL increment counter and notify listeners so Event Log can show the stage
      _triggerCount++;
      _lastTriggeredEventName = '(no audio)';
      _lastTriggeredStage = normalizedStage;
      _lastTriggeredLayers = [];
      _lastTriggerSuccess = false;
      _lastTriggerError = 'No audio event configured';
      // Extract stage timestamp from context (for correct Event Log ordering)
      _lastStageTimestampMs = (context?['timestamp_ms'] as num?)?.toDouble() ?? 0.0;

      // P1.4: Record in history
      _recordTrigger(
        stage: normalizedStage,
        eventName: '(no audio)',
        layerNames: [],
        success: false,
        error: 'No audio event configured',
      );

      notifyListeners();
      return;
    }

    // DEBUG: Log found event for REEL_STOP stages
    if (normalizedStage.contains('REEL_STOP')) {
      debugPrint('[EventRegistry] ✅ FOUND event for $normalizedStage:');
      debugPrint('  eventId = ${event.id}');
      debugPrint('  eventName = ${event.name}');
      debugPrint('  eventStage = ${event.stage}');
      debugPrint('  layers = ${event.layers.map((l) => l.audioPath.split('/').last).join(', ')}');
    }

    await triggerEvent(event.id, context: context);
  }

  /// Trigeruj event po ID-u
  Future<void> triggerEvent(String eventId, {Map<String, dynamic>? context}) async {
    // Input validation
    if (eventId.isEmpty || eventId.length > 256) {
      debugPrint('[EventRegistry] ⚠️ Invalid eventId length');
      return;
    }

    final event = _events[eventId];
    if (event == null) {
      debugPrint('[EventRegistry] Event not found: $eventId');
      return;
    }

    _triggerCount++;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONTAINER DELEGATION — Route to container playback if configured
    // ═══════════════════════════════════════════════════════════════════════════
    if (event.usesContainer) {
      await _triggerViaContainer(event, context);
      notifyListeners();
      return;
    }

    // Store last triggered event info for Event Log display
    _lastTriggeredEventName = event.name;
    _lastTriggeredStage = event.stage;
    _lastTriggeredLayers = event.layers
        .where((l) => l.audioPath.isNotEmpty)
        .map((l) => l.audioPath.split('/').last) // Just filename
        .toList();
    // Extract stage timestamp from context (for correct Event Log ordering)
    _lastStageTimestampMs = (context?['timestamp_ms'] as num?)?.toDouble() ?? 0.0;
    // Reset container info (not using container for this event)
    _lastContainerType = ContainerType.none;
    _lastContainerName = null;
    _lastContainerChildCount = 0;

    // Check if event has playable layers
    if (_lastTriggeredLayers.isEmpty) {
      _lastTriggerSuccess = false;
      _lastTriggerError = 'No audio layers';
      debugPrint('[EventRegistry] ⚠️ Event "${event.name}" has no playable audio layers!');
      notifyListeners();
      return;
    }

    // Check if this event should use pooling
    final usePool = _shouldUsePool(event.stage);
    final poolStr = usePool ? ' [POOLED]' : '';

    // Debug: Log all layer paths
    final layerPaths = event.layers.map((l) => l.audioPath).toList();
    debugPrint('[EventRegistry] Triggering: ${event.name} (${event.layers.length} layers)$poolStr');
    debugPrint('[EventRegistry] Layer paths: $layerPaths');

    // Reset success tracking
    _lastTriggerSuccess = true;
    _lastTriggerError = '';

    // ═══════════════════════════════════════════════════════════════════════════
    // FIX: For looping events, stop existing instances before starting new one
    // This prevents voice accumulation (e.g., REEL_SPIN hitting limit after 8 spins)
    // ═══════════════════════════════════════════════════════════════════════════
    if (event.loop) {
      final existingInstances = _playingInstances.where((i) => i.eventId == eventId).toList();
      if (existingInstances.isNotEmpty) {
        debugPrint('[EventRegistry] 🔄 Stopping ${existingInstances.length} existing loop instance(s) of "${event.name}"');
        for (final instance in existingInstances) {
          for (final voiceId in instance.voiceIds) {
            try {
              NativeFFI.instance.playbackStopOneShot(voiceId);
            } catch (_) {}
          }
        }
        _playingInstances.removeWhere((i) => i.eventId == eventId);
      }
    }

    // P1.2: Check voice limit before spawning new voices
    final activeVoices = _countActiveVoices(eventId);
    if (activeVoices >= _maxVoicesPerEvent) {
      _voiceLimitRejects++;
      _lastTriggerSuccess = false;
      _lastTriggerError = 'Voice limit reached ($activeVoices/$_maxVoicesPerEvent)';
      debugPrint('[EventRegistry] ⚠️ Voice limit reached for "${event.name}": $activeVoices active (max $_maxVoicesPerEvent)');
      notifyListeners();
      return;
    }

    // Kreiraj playing instance
    final voiceIds = <int>[];
    final instance = _PlayingInstance(
      eventId: eventId,
      voiceIds: voiceIds,
      startTime: DateTime.now(),
    );
    _playingInstances.add(instance);

    // Pokreni sve layer-e sa njihovim delay-ima
    for (final layer in event.layers) {
      _playLayer(
        layer,
        voiceIds,
        context,
        usePool: usePool,
        eventKey: event.stage,
        loop: event.loop, // P0.2: Pass loop flag for seamless looping (REEL_SPIN)
      );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL FIX: Auto-cleanup for ONE-SHOT (non-looping) events
    // Without this, voice slots accumulate and hit limit after ~8 spins
    // One-shot sounds typically finish in < 3 seconds, no need to hold for 30s
    // ═══════════════════════════════════════════════════════════════════════════
    if (!event.loop) {
      // Use event duration with 500ms buffer, or default 3 seconds if not specified
      final cleanupDelayMs = event.duration > 0
          ? ((event.duration * 1000) + 500).toInt()
          : 3000;

      Timer(Duration(milliseconds: cleanupDelayMs), () {
        if (_playingInstances.contains(instance)) {
          _playingInstances.remove(instance);
          debugPrint('[EventRegistry] 🧹 Auto-cleaned one-shot: "${event.name}" (after ${cleanupDelayMs}ms)');
        }
      });
    }

    // P1.3: Add to recent items for quick access
    _addToRecent(event);

    // P1.4: Record in trigger history
    _recordTrigger(
      stage: event.stage,
      eventName: event.name,
      layerNames: _lastTriggeredLayers,
      success: _lastTriggerSuccess,
      error: _lastTriggerSuccess ? null : _lastTriggerError,
    );

    notifyListeners();
  }

  /// Add triggered event to RecentFavoritesService for quick access
  void _addToRecent(AudioEvent event) {
    RecentFavoritesService.instance.addRecent(
      RecentItem.event(
        eventId: event.id,
        name: event.name,
        stageName: event.stage.isNotEmpty ? event.stage : null,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTAINER DELEGATION — Play via Blend/Random/Sequence containers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Route playback through container instead of direct layers
  Future<void> _triggerViaContainer(AudioEvent event, Map<String, dynamic>? context) async {
    final containerId = event.containerId;
    if (containerId == null) {
      debugPrint('[EventRegistry] ⚠️ Container event "${event.name}" has no containerId');
      return;
    }

    // Determine bus from stage (use default bus 0 for container playback)
    final busId = _stageToBus(event.stage, 0).index;
    final containerService = ContainerService.instance;

    // Update tracking for Event Log
    _lastTriggeredEventName = event.name;
    _lastTriggeredStage = event.stage;
    _lastTriggerSuccess = true;
    _lastTriggerError = '';
    _lastContainerType = event.containerType;

    switch (event.containerType) {
      case ContainerType.blend:
        // Get container info for logging
        final blendContainer = containerService.getBlendContainer(containerId);
        _lastContainerName = blendContainer?.name ?? 'Unknown';
        _lastContainerChildCount = blendContainer?.children.length ?? 0;

        final voiceIds = await containerService.triggerBlendContainer(
          containerId,
          busId: busId,
          context: context,
        );
        _lastTriggeredLayers = ['blend:${voiceIds.length} children'];
        if (voiceIds.isEmpty) {
          _lastTriggerSuccess = false;
          _lastTriggerError = 'No active blend children';
        }
        debugPrint('[EventRegistry] ✅ Blend container triggered: ${voiceIds.length} voices');
        break;

      case ContainerType.random:
        // Get container info for logging
        final randomContainer = containerService.getRandomContainer(containerId);
        _lastContainerName = randomContainer?.name ?? 'Unknown';
        _lastContainerChildCount = randomContainer?.children.length ?? 0;

        final voiceId = await containerService.triggerRandomContainer(
          containerId,
          busId: busId,
          context: context,
        );
        _lastTriggeredLayers = voiceId > 0 ? ['random:selected'] : [];
        if (voiceId < 0) {
          _lastTriggerSuccess = false;
          _lastTriggerError = 'Random selection failed';
        }
        debugPrint('[EventRegistry] ✅ Random container triggered: voice $voiceId');
        break;

      case ContainerType.sequence:
        // Get container info for logging
        final seqContainer = containerService.getSequenceContainer(containerId);
        _lastContainerName = seqContainer?.name ?? 'Unknown';
        _lastContainerChildCount = seqContainer?.steps.length ?? 0;

        final instanceId = await containerService.triggerSequenceContainer(
          containerId,
          busId: busId,
          context: context,
        );
        _lastTriggeredLayers = instanceId > 0 ? ['sequence:instance $instanceId'] : [];
        if (instanceId < 0) {
          _lastTriggerSuccess = false;
          _lastTriggerError = 'Sequence start failed';
        }
        debugPrint('[EventRegistry] ✅ Sequence container triggered: instance $instanceId');
        break;

      case ContainerType.none:
        // Should not happen (usesContainer was true)
        _lastContainerName = null;
        _lastContainerChildCount = 0;
        debugPrint('[EventRegistry] ⚠️ ContainerType.none but usesContainer was true');
        break;
    }

    // P1.4: Record container trigger in history
    _recordTrigger(
      stage: event.stage,
      eventName: event.name,
      layerNames: _lastTriggeredLayers,
      success: _lastTriggerSuccess,
      error: _lastTriggerSuccess ? null : _lastTriggerError,
      containerType: event.containerType,
    );
  }

  Future<void> _playLayer(
    AudioLayer layer,
    List<int> voiceIds,
    Map<String, dynamic>? context, {
    bool usePool = false,
    String? eventKey,
    bool loop = false, // P0.2: Seamless loop support
  }) async {
    if (layer.audioPath.isEmpty) {
      debugPrint('[EventRegistry] ⚠️ Skipping layer "${layer.name}" — empty audioPath');
      return;
    }

    // P1.1 SECURITY: Validate audio path before playback
    if (!_validateAudioPath(layer.audioPath)) {
      debugPrint('[EventRegistry] ⛔ BLOCKED: Invalid audio path for layer "${layer.name}"');
      _lastTriggerSuccess = false;
      _lastTriggerError = 'Invalid audio path (security)';
      return;
    }

    debugPrint('[EventRegistry] 🔊 Playing layer "${layer.name}" | path: ${layer.audioPath}');

    // Delay pre početka
    final totalDelayMs = (layer.delay + layer.offset * 1000).round();
    if (totalDelayMs > 0) {
      await Future.delayed(Duration(milliseconds: totalDelayMs));
    }

    try {
      // Apply volume (može se modulirati context-om)
      double volume = layer.volume;
      if (context != null && context.containsKey('volumeMultiplier')) {
        volume *= (context['volumeMultiplier'] as num).toDouble();
      }

      // Apply RTPC modulation if layer/event has bindings
      final eventId = eventKey ?? layer.id;
      if (RtpcModulationService.instance.hasMapping(eventId)) {
        volume = RtpcModulationService.instance.getModulatedVolume(eventId, volume);
      }

      // ═══════════════════════════════════════════════════════════════════════
      // P1.2: ROLLUP PITCH DYNAMICS — Volume escalation based on rollup progress
      // Applied to ROLLUP_TICK and similar stages for exciting build-up
      // Progress comes from stage context (0.0 → 1.0 as rollup completes)
      // ═══════════════════════════════════════════════════════════════════════
      if (eventKey != null && eventKey.contains('ROLLUP') && context != null) {
        final progress = context['progress'] as double?;
        if (progress != null) {
          final escalation = RtpcModulationService.instance.getRollupVolumeEscalation(progress);
          volume *= escalation;
          debugPrint('[EventRegistry] P1.2 Rollup modulation: progress=${progress.toStringAsFixed(2)}, volume=${(volume).toStringAsFixed(2)}');
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // SPATIAL AUDIO POSITIONING (AutoSpatialEngine integration)
      // P1.3: Context pan takes priority over layer pan, spatial engine overrides both
      // ═══════════════════════════════════════════════════════════════════════
      double pan = layer.pan; // Default to layer's configured pan

      // P1.3: Context pan (from win line panning etc.) overrides layer pan
      if (context != null && context.containsKey('pan')) {
        pan = (context['pan'] as num).toDouble().clamp(-1.0, 1.0);
      }

      if (_useSpatialAudio && eventKey != null) {
        final spatialEventId = '${eventKey}_${layer.id}_${DateTime.now().millisecondsSinceEpoch}';
        final intent = _stageToIntent(eventKey);
        final bus = _stageToBus(eventKey, layer.busId);

        // Create spatial event
        final spatialEvent = SpatialEvent(
          id: spatialEventId,
          name: layer.name,
          intent: intent,
          bus: bus,
          timeMs: DateTime.now().millisecondsSinceEpoch,
          lifetimeMs: 500, // Track for 500ms
          importance: 0.8,
        );

        // Register with spatial engine
        _spatialEngine.onEvent(spatialEvent);

        // Update engine and get output
        final outputs = _spatialEngine.update();
        final spatialOutput = outputs[spatialEventId];

        if (spatialOutput != null) {
          // Apply spatial pan (overrides layer pan)
          pan = spatialOutput.pan;
          // Could also apply volume attenuation from distance
          // volume *= spatialOutput.distanceGain;
          _spatialTriggers++;
        }
      }

      // Notify DuckingService that this bus is playing
      DuckingService.instance.notifyBusActive(layer.busId);

      // Determine correct PlaybackSource from active section in UnifiedPlaybackController
      // CRITICAL FIX: If no section is active, auto-acquire SlotLab section first
      // This ensures the Rust engine knows about the active section for voice filtering
      var activeSection = UnifiedPlaybackController.instance.activeSection;
      if (activeSection == null) {
        // Auto-acquire SlotLab section (EventRegistry defaults to SlotLab)
        UnifiedPlaybackController.instance.acquireSection(PlaybackSection.slotLab);
        // Also ensure audio stream is running
        UnifiedPlaybackController.instance.ensureStreamRunning();
        activeSection = PlaybackSection.slotLab;
        debugPrint('[EventRegistry] Auto-acquired SlotLab section for playback');
      }

      final source = switch (activeSection) {
        PlaybackSection.daw => PlaybackSource.daw,
        PlaybackSection.slotLab => PlaybackSource.slotlab,
        PlaybackSection.middleware => PlaybackSource.middleware,
        PlaybackSection.browser => PlaybackSource.browser,
      };

      debugPrint('[EventRegistry] _playLayer: activeSection=$activeSection, source=$source, path=${layer.audioPath}');

      int voiceId;

      // Use bus routing for middleware/slotlab, preview engine for browser/daw
      if (source == PlaybackSource.browser) {
        // Browser uses isolated PreviewEngine
        voiceId = AudioPlaybackService.instance.previewFile(
          layer.audioPath,
          volume: volume.clamp(0.0, 1.0),
          source: source,
        );
      } else if (usePool && eventKey != null) {
        // Use AudioPool for rapid-fire events (CASCADE_STEP, ROLLUP_TICK, etc.)
        voiceId = AudioPool.instance.acquire(
          eventKey: eventKey,
          audioPath: layer.audioPath,
          busId: layer.busId,
          volume: volume.clamp(0.0, 1.0),
          pan: pan.clamp(-1.0, 1.0),
        );
        _pooledTriggers++;
      } else if (loop) {
        // P0.2: Seamless looping for REEL_SPIN and similar events
        voiceId = AudioPlaybackService.instance.playLoopingToBus(
          layer.audioPath,
          volume: volume.clamp(0.0, 1.0),
          pan: pan.clamp(-1.0, 1.0),
          busId: layer.busId,
          source: source,
        );
      } else {
        // Standard bus routing through PlaybackEngine
        voiceId = AudioPlaybackService.instance.playFileToBus(
          layer.audioPath,
          volume: volume.clamp(0.0, 1.0),
          pan: pan.clamp(-1.0, 1.0),
          busId: layer.busId,
          source: source,
        );
      }

      if (voiceId >= 0) {
        voiceIds.add(voiceId);
        final poolStr = usePool ? ' [POOLED]' : '';
        final loopStr = loop ? ' [LOOP]' : '';
        final spatialStr = (_useSpatialAudio && pan != layer.pan) ? ' [SPATIAL pan=${pan.toStringAsFixed(2)}]' : '';
        // Store voice info for debug display
        _lastTriggerError = 'voice=$voiceId, bus=${layer.busId}, section=$activeSection';
        debugPrint('[EventRegistry] ✅ Playing: ${layer.name} (voice $voiceId, source: $source, bus: ${layer.busId})$poolStr$loopStr$spatialStr');

        // ═══════════════════════════════════════════════════════════════════════
        // P0: Track per-reel spin loop voices for individual fade-out on REEL_STOP
        // ═══════════════════════════════════════════════════════════════════════
        if (loop && context != null && context['is_reel_spin_loop'] == true) {
          final reelIndex = context['reel_index'] as int?;
          if (reelIndex != null) {
            _trackReelSpinLoopVoice(reelIndex, voiceId);
          }
        }
      } else {
        // Voice ID -1 means playback failed - get error from AudioPlaybackService
        final ffiError = AudioPlaybackService.instance.lastPlaybackToBusError;
        _lastTriggerSuccess = false;
        _lastTriggerError = 'FAILED: $ffiError';
        debugPrint('[EventRegistry] ❌ FAILED to play: ${layer.name} | path: ${layer.audioPath} | error: $ffiError');
      }
    } catch (e) {
      debugPrint('[EventRegistry] Error playing layer ${layer.name}: $e');
    }
  }

  // ==========================================================================
  // STOPPING
  // ==========================================================================

  /// Zaustavi sve instance eventa po ID-u ili stage-u
  Future<void> stopEvent(String eventIdOrStage) async {
    final toRemove = <_PlayingInstance>[];

    // Prvo probaj naći event po stage-u
    final eventByStage = _stageToEvent[eventIdOrStage];
    final targetEventId = eventByStage?.id ?? eventIdOrStage;

    for (final instance in _playingInstances) {
      if (instance.eventId == targetEventId) {
        await instance.stop();
        toRemove.add(instance);
      }
    }

    _playingInstances.removeWhere((i) => toRemove.contains(i));
    if (toRemove.isNotEmpty) {
      debugPrint('[EventRegistry] Stopped ${toRemove.length} instance(s) of: $eventIdOrStage');
    }
    notifyListeners();
  }

  /// Zaustavi sve
  Future<void> stopAll() async {
    // Stop all one-shot voices via bus routing
    AudioPlaybackService.instance.stopAllOneShots();

    for (final instance in _playingInstances) {
      await instance.stop();
    }
    _playingInstances.clear();
    notifyListeners();
  }

  // ==========================================================================
  // PRELOADING (Rust engine handles actual caching)
  // ==========================================================================

  /// Preload audio za brži playback
  Future<void> preloadEvent(String eventId) async {
    final event = _events[eventId];
    if (event == null) return;

    for (final layer in event.layers) {
      if (layer.audioPath.isEmpty) continue;
      _preloadedPaths.add(layer.audioPath);
      debugPrint('[EventRegistry] Marked for preload: ${layer.name}');
    }
  }

  /// Preload sve registrovane evente
  Future<void> preloadAll() async {
    for (final eventId in _events.keys) {
      await preloadEvent(eventId);
    }
  }

  // ==========================================================================
  // P0.7: BIG WIN LAYERED AUDIO TEMPLATES
  // ==========================================================================

  /// Create a template Big Win event with layered audio structure
  /// Layers include: Impact, Coin Shower, Music Swell, Voice Over
  /// Each tier has different timing and intensity
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

    final timing = timingMap[tier] ?? timingMap['nice']!;
    final layers = <AudioLayer>[];

    // Layer 1: Impact Hit (immediate)
    layers.add(AudioLayer(
      id: '${tier}_impact',
      audioPath: impactPath,
      name: 'Impact Hit',
      volume: 1.0,
      pan: 0.0,
      delay: 0,
      busId: 2, // SFX bus
    ));

    // Layer 2: Coin Shower (delayed)
    if (coinShowerPath != null && coinShowerPath.isNotEmpty) {
      layers.add(AudioLayer(
        id: '${tier}_coins',
        audioPath: coinShowerPath,
        name: 'Coin Shower',
        volume: 0.8,
        pan: 0.0,
        delay: timing.coinDelay.toDouble(),
        busId: 2, // SFX bus
      ));
    }

    // Layer 3: Music Swell (simultaneous or slightly delayed)
    if (musicSwellPath != null && musicSwellPath.isNotEmpty) {
      layers.add(AudioLayer(
        id: '${tier}_music',
        audioPath: musicSwellPath,
        name: 'Music Swell',
        volume: 0.9,
        pan: 0.0,
        delay: timing.musicDelay.toDouble(),
        busId: 1, // Music bus
      ));
    }

    // Layer 4: Voice Over (most delayed)
    if (voiceOverPath != null && voiceOverPath.isNotEmpty) {
      layers.add(AudioLayer(
        id: '${tier}_vo',
        audioPath: voiceOverPath,
        name: 'Voice Over',
        volume: 1.0,
        pan: 0.0,
        delay: timing.voDelay.toDouble(),
        busId: 3, // Voice bus
      ));
    }

    return AudioEvent(
      id: 'slot_bigwin_tier_$tier',
      name: 'Big Win - ${tier[0].toUpperCase()}${tier.substring(1)}',
      stage: stageMap[tier] ?? 'BIGWIN_TIER',
      layers: layers,
      priority: tier == 'ultra' ? 100 : (tier == 'epic' ? 80 : (tier == 'mega' ? 60 : 40)),
    );
  }

  /// Register default Big Win events with placeholder paths
  /// Call this to set up the event structure, then update paths via UI
  void registerDefaultBigWinEvents() {
    const tiers = ['nice', 'super', 'mega', 'epic', 'ultra'];

    for (final tier in tiers) {
      final event = createBigWinTemplate(
        tier: tier,
        impactPath: '', // User will fill these via Audio Pool
        coinShowerPath: '',
        musicSwellPath: '',
        voiceOverPath: '',
      );
      registerEvent(event);
      debugPrint('[EventRegistry] P0.7: Registered Big Win template: ${event.id}');
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
    final eventId = 'slot_bigwin_tier_$tier';
    final existing = _events[eventId];
    if (existing == null) {
      debugPrint('[EventRegistry] Big Win event not found: $eventId');
      return;
    }

    // Create new event with updated paths
    final event = createBigWinTemplate(
      tier: tier,
      impactPath: impactPath ?? existing.layers.firstWhere((l) => l.id.contains('impact'), orElse: () => const AudioLayer(id: '', audioPath: '', name: '')).audioPath,
      coinShowerPath: coinShowerPath ?? existing.layers.where((l) => l.id.contains('coins')).firstOrNull?.audioPath,
      musicSwellPath: musicSwellPath ?? existing.layers.where((l) => l.id.contains('music')).firstOrNull?.audioPath,
      voiceOverPath: voiceOverPath ?? existing.layers.where((l) => l.id.contains('vo')).firstOrNull?.audioPath,
    );

    registerEvent(event);
    debugPrint('[EventRegistry] P0.7: Updated Big Win event: $eventId');
  }

  // ==========================================================================
  // SERIALIZATION
  // ==========================================================================

  Map<String, dynamic> toJson() => {
    'events': _events.values.map((e) => e.toJson()).toList(),
  };

  void loadFromJson(Map<String, dynamic> json) {
    _events.clear();
    _stageToEvent.clear();

    final events = json['events'] as List<dynamic>? ?? [];
    for (final eventJson in events) {
      final event = AudioEvent.fromJson(eventJson as Map<String, dynamic>);
      registerEvent(event);
    }
  }

  // ==========================================================================
  // POOL & SPATIAL STATS
  // ==========================================================================

  /// Get combined stats from EventRegistry, AudioPool, and SpatialEngine
  String get statsString {
    final poolStats = AudioPool.instance.statsString;
    final spatialStats = _spatialEngine.getStats();
    return 'EventRegistry: triggers=$_triggerCount, pooled=$_pooledTriggers, spatial=$_spatialTriggers | '
        '$poolStats | Spatial: active=${spatialStats.activeEvents}, processed=${spatialStats.totalEventsProcessed}';
  }

  /// Get spatial engine stats directly
  AutoSpatialStats get spatialStats => _spatialEngine.getStats();

  /// Reset all stats
  void resetStats() {
    _triggerCount = 0;
    _pooledTriggers = 0;
    _spatialTriggers = 0;
    AudioPool.instance.reset();
    _spatialEngine.clear();
  }

  // ==========================================================================
  // CLEANUP
  // ==========================================================================

  @override
  void dispose() {
    _cleanupTimer?.cancel(); // P1.3: Stop cleanup timer
    stopAll();
    _preloadedPaths.clear();
    _spatialEngine.dispose();
    super.dispose();
  }
}

// =============================================================================
// GLOBAL SINGLETON
// =============================================================================

final eventRegistry = EventRegistry();
