/// HookGraphService — Central orchestrator for the Dynamic Hook Graph System.
///
/// Bridges Flutter game events to audio behavior through graph-based execution:
///
/// ```
///  GameFlowProvider / SlotLab Events
///      │  emitEvent("freespins_start", data)
///      ▼
///  HookGraphService
///      │  HookGraphRegistry.resolve(eventId)
///      │  ControlRateExecutor.trigger(graph)
///      │  Ticker.tick() → executor.tick() → List<AudioCommand>
///      ▼
///  AudioCommand dispatch:
///    StartVoiceCommand  → NativeFFI.enginePlaybackPlayToBus(...)
///    StopVoiceCommand   → NativeFFI.playbackStopOneShot(voiceId)
///    SetParamCommand    → NativeFFI.hookGraphSetRtpc(paramId, value)
///      ▼
///  Rust HookGraphEngine (audio thread)
/// ```
///
/// ## Usage
/// ```dart
/// // In any widget or provider:
/// sl<HookGraphService>().emitEvent('spin_start');
/// sl<HookGraphService>().emitEvent('reel_stop_2', data: {'reelIndex': 2});
/// sl<HookGraphService>().setRtpc('excitement', 0.8);
/// ```

import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../../src/rust/native_ffi.dart';
import '../../models/hook_graph/graph_definition.dart';
import 'hook_graph_registry.dart';
import 'graph_executor.dart';
import 'rtpc_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
// BUS ID CONSTANTS (must match OutputBus in Rust ffi)
// ═══════════════════════════════════════════════════════════════════════════

/// Bus IDs matching rf-engine OutputBus enum
abstract class AudioBusId {
  static const int sfx = 0;
  static const int music = 1;
  static const int voice = 2;
  static const int ambience = 3;
  static const int aux = 4;
  static const int master = 5;
}

/// Playback source IDs matching rf-engine PlaybackSource enum
abstract class PlaybackSource {
  static const int daw = 0;
  static const int slotLab = 1;
  static const int middleware = 2;
  static const int browser = 3;
}

// ═══════════════════════════════════════════════════════════════════════════

/// Active voice tracking (voice_id → metadata)
class _ActiveVoice {
  final int voiceId;
  final String assetPath;
  final String eventId;
  final DateTime startTime;

  _ActiveVoice({
    required this.voiceId,
    required this.assetPath,
    required this.eventId,
  }) : startTime = DateTime.now();
}

/// HookGraphService singleton
class HookGraphService {
  HookGraphService._();
  static final HookGraphService instance = HookGraphService._();

  // ── Internal state ──────────────────────────────────────────────────────
  final HookGraphRegistry _registry = HookGraphRegistry();
  final ControlRateExecutor _executor = ControlRateExecutor();
  final RTPCManager _rtpcManager = RTPCManager();

  /// Active voices started by hook graphs (voice_id → metadata)
  final Map<int, _ActiveVoice> _activeVoices = {};

  /// Ticker driving the ~60Hz control-rate tick
  Ticker? _ticker;

  /// Last tick time (for delta-time calculations)
  Duration _lastTick = Duration.zero;

  /// Whether service is initialized
  bool _initialized = false;

  /// Current game states (for state-scoped graph resolution)
  Map<String, String> _activeStates = {};

  // ── Diagnostics ─────────────────────────────────────────────────────────
  int _totalEventsEmitted = 0;
  int _totalGraphsTriggered = 0;
  int _totalVoicesStarted = 0;

  // ═════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═════════════════════════════════════════════════════════════════════════

  /// Initialize the service and start the control-rate ticker.
  /// Safe to call multiple times (idempotent).
  void initialize() {
    if (_initialized) return;
    _initialized = true;

    _ticker = Ticker(_onTick)..start();
  }

  /// Dispose resources (call when app shuts down).
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _initialized = false;
  }

  // ═════════════════════════════════════════════════════════════════════════
  // GRAPH REGISTRATION
  // ═════════════════════════════════════════════════════════════════════════

  /// Register a graph definition.
  void registerGraph(HookGraphDefinition graph) {
    _registry.registerGraph(graph);
  }

  /// Bind an event pattern to a graph.
  void bind(HookGraphBinding binding) {
    _registry.bind(binding);
  }

  /// Register a graph and bind it in one call.
  void registerAndBind(
    HookGraphDefinition graph, {
    required String eventPattern,
    int priority = 0,
    bool exclusive = false,
    String? stateGroup,
    String? stateValue,
  }) {
    _registry.registerGraph(graph);
    _registry.bind(HookGraphBinding(
      eventPattern: eventPattern,
      graphId: graph.id,
      priority: priority,
      exclusive: exclusive,
      stateGroup: stateGroup,
      stateValue: stateValue,
    ));
  }

  // ═════════════════════════════════════════════════════════════════════════
  // EVENT EMISSION — main entry point for SlotLab integration
  // ═════════════════════════════════════════════════════════════════════════

  /// Emit a game event and trigger all matching hook graphs.
  ///
  /// This is the primary method called by GameFlowProvider, reel physics,
  /// win detection, and any other game system.
  ///
  /// [eventId]   — event identifier (e.g. 'spin_start', 'reel_stop_2', 'freespins_enter')
  /// [data]      — optional event data forwarded to graph EventEntry nodes
  void emitEvent(String eventId, {Map<String, dynamic>? data}) {
    _totalEventsEmitted++;

    final bindings = _registry.resolve(eventId, activeStates: _activeStates);
    if (bindings.isEmpty) return;

    for (final resolved in bindings) {
      _executor.trigger(
        resolved.graph,
        eventId: eventId,
        eventData: data,
      );
      _totalGraphsTriggered++;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RTPC CONTROL
  // ═════════════════════════════════════════════════════════════════════════

  /// Set an RTPC (Real-Time Parameter Control) value.
  ///
  /// Drives audio parameters from gameplay metrics:
  /// - excitement → reverb send level, filter cutoff
  /// - winMultiplier → music layer density
  /// - betLevel → overall mix energy
  void setRtpc(String paramId, double value) {
    final paramHash = paramId.hashCode & 0xFFFFFFFF;
    NativeFFI.instance.hookGraphSetRtpc(paramHash, value);
    _rtpcManager.setValue(paramId, value);
  }

  /// Convenience: set multiple RTPC values at once
  void setRtpcBatch(Map<String, double> values) {
    values.forEach(setRtpc);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // STATE MANAGEMENT
  // ═════════════════════════════════════════════════════════════════════════

  /// Update the current game state (used for state-scoped graph resolution).
  ///
  /// Example:
  ///   setGameState('gameMode', 'freeSpins');
  ///   setGameState('winTier', 'bigWin');
  void setGameState(String group, String value) {
    _activeStates[group] = value;
  }

  /// Clear a state group (revert to "any state" matching).
  void clearGameState(String group) {
    _activeStates.remove(group);
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DIRECT VOICE CONTROL
  // ═════════════════════════════════════════════════════════════════════════

  /// Manually stop all voices associated with a specific event.
  void stopEventVoices(String eventId, {double fadeMs = 100}) {
    final toStop = _activeVoices.entries
        .where((e) => e.value.eventId == eventId)
        .map((e) => e.key)
        .toList();

    for (final voiceId in toStop) {
      NativeFFI.instance.playbackStopOneShot(voiceId);
      _activeVoices.remove(voiceId);
    }
  }

  /// Stop all hook graph voices.
  void stopAllVoices({double fadeMs = 100}) {
    for (final voiceId in _activeVoices.keys.toList()) {
      NativeFFI.instance.playbackStopOneShot(voiceId);
    }
    _activeVoices.clear();
  }

  // ═════════════════════════════════════════════════════════════════════════
  // DIAGNOSTICS
  // ═════════════════════════════════════════════════════════════════════════

  int get totalEventsEmitted => _totalEventsEmitted;
  int get totalGraphsTriggered => _totalGraphsTriggered;
  int get totalVoicesStarted => _totalVoicesStarted;
  int get activeVoiceCount => _activeVoices.length;
  int get activeExecutorCount => _executor.activeCount;
  bool get isInitialized => _initialized;

  HookGraphRegistry get registry => _registry;

  // ═════════════════════════════════════════════════════════════════════════
  // INTERNAL — CONTROL RATE TICK (~60Hz)
  // ═════════════════════════════════════════════════════════════════════════

  void _onTick(Duration elapsed) {
    if (!_initialized) return;

    // Throttle: only process if enough time has passed (~60Hz = ~16ms)
    final delta = elapsed - _lastTick;
    if (delta < const Duration(milliseconds: 14)) return;
    _lastTick = elapsed;

    // Process one tick of all active graph executions
    final commands = _executor.tick();

    // Dispatch audio commands to Rust engine
    for (final cmd in commands) {
      _dispatchAudioCommand(cmd);
    }

    // Poll feedback from Rust (voice_started, voice_stopped, graph_done)
    _pollFeedback();
  }

  void _dispatchAudioCommand(AudioCommand cmd) {
    final ffi = NativeFFI.instance;

    switch (cmd) {
      case StartVoiceCommand():
        if (cmd.assetPath.isEmpty) return;

        // Map bus name → bus ID
        final busId = _busNameToId(cmd.bus);

        // Use extended play API for fade-in support
        final voiceId = ffi.playbackPlayToBus(
          cmd.assetPath,
          volume: cmd.volume,
          pan: 0.0, // center — spatial positioning via SpatialManager if needed
          busId: busId,
          source: PlaybackSource.slotLab,
        );

        if (voiceId > 0) {
          _activeVoices[voiceId] = _ActiveVoice(
            voiceId: voiceId,
            assetPath: cmd.assetPath,
            eventId: 'hook_graph',
          );
          _totalVoicesStarted++;
        }

      case StopVoiceCommand():
        ffi.playbackStopOneShot(cmd.voiceId);
        _activeVoices.remove(cmd.voiceId);

      case SetParamCommand():
        final paramHash = cmd.paramName.hashCode & 0xFFFFFFFF;
        ffi.hookGraphSetRtpc(paramHash, cmd.value);
    }
  }

  void _pollFeedback() {
    // Poll Rust for feedback events (voice lifecycle, graph completion)
    // Maximum 16 events per tick to avoid spending too long in feedback loop
    final jsonStr = NativeFFI.instance.hookGraphPollFeedback(16);
    if (jsonStr == null || jsonStr == '[]') return;

    try {
      // Simple manual parse for the known JSON format
      // Avoids importing dart:convert in hot path
      _processFeedbackJson(jsonStr);
    } catch (_) {
      // Feedback parsing is best-effort — never throw
    }
  }

  void _processFeedbackJson(String json) {
    // Parse events: [{"type":"voice_stopped","voice_id":42},...]
    // Format is strictly controlled from Rust side — simple string search is safe
    if (!json.contains('"voice_stopped"')) return;

    // Remove stopped voices from tracking
    final stoppedRe = RegExp(r'"voice_id":(\d+)');
    final typeRe = RegExp(r'"type":"([^"]+)"');

    // Split array elements by "}," pattern
    final items = json.replaceAll('[', '').replaceAll(']', '').split('},');

    for (final item in items) {
      final typeMatch = typeRe.firstMatch(item);
      if (typeMatch == null) continue;

      final type = typeMatch.group(1);
      if (type == 'voice_stopped') {
        final idMatch = stoppedRe.firstMatch(item);
        if (idMatch != null) {
          final voiceId = int.tryParse(idMatch.group(1) ?? '');
          if (voiceId != null) {
            _activeVoices.remove(voiceId);
          }
        }
      }
    }
  }

  int _busNameToId(String name) {
    switch (name.toLowerCase()) {
      case 'sfx':
        return AudioBusId.sfx;
      case 'music':
        return AudioBusId.music;
      case 'voice':
        return AudioBusId.voice;
      case 'ambience':
      case 'amb':
        return AudioBusId.ambience;
      case 'aux':
        return AudioBusId.aux;
      case 'master':
        return AudioBusId.master;
      default:
        return AudioBusId.sfx;
    }
  }
}
