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
  // Reel stops (core gameplay)
  'REEL_STOP',
  'REEL_STOP_0',
  'REEL_STOP_1',
  'REEL_STOP_2',
  'REEL_STOP_3',
  'REEL_STOP_4',
  'REEL_STOP_5',
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

  // Currently playing instances
  final List<_PlayingInstance> _playingInstances = [];

  // Preloaded paths (for tracking)
  final Set<String> _preloadedPaths = {};

  // Audio pool for rapid-fire events
  bool _useAudioPool = true;

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

  String get lastTriggeredEventName => _lastTriggeredEventName;
  String get lastTriggeredStage => _lastTriggeredStage;
  List<String> get lastTriggeredLayers => _lastTriggeredLayers;
  bool get lastTriggerSuccess => _lastTriggerSuccess;
  String get lastTriggerError => _lastTriggerError;
  ContainerType get lastContainerType => _lastContainerType;
  String? get lastContainerName => _lastContainerName;
  int get lastContainerChildCount => _lastContainerChildCount;

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
  /// Stops any playing instances before replacing to prevent stale audio
  void registerEvent(AudioEvent event) {
    // Stop any playing instances of this event before replacing
    // This prevents old audio from continuing to play after layer changes
    final existingEvent = _events[event.id];
    if (existingEvent != null) {
      // Event exists - stop all playing instances SYNCHRONOUSLY
      _stopEventSync(event.id);
      debugPrint('[EventRegistry] Stopping existing instances before update: ${event.name}');
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

    notifyListeners();
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
      notifyListeners();
      return;
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

    // P1.3: Add to recent items for quick access
    _addToRecent(event);

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
      final activeSection = UnifiedPlaybackController.instance.activeSection;
      final source = switch (activeSection) {
        PlaybackSection.daw => PlaybackSource.daw,
        PlaybackSection.slotLab => PlaybackSource.slotlab,
        PlaybackSection.middleware => PlaybackSource.middleware,
        PlaybackSection.browser => PlaybackSource.browser,
        null => PlaybackSource.slotlab, // Default to slotlab for EventRegistry
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
