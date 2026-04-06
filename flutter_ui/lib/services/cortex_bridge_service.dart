// file: flutter_ui/lib/services/cortex_bridge_service.dart
/// CORTEX Bridge Service — Unified Flutter↔Rust communication layer.
///
/// Provides:
/// - Intent-based routing through typed requests
/// - Bidirectional streaming (Rust→Flutter events + Flutter→Rust intents)
/// - Correlation ID tracking with timeout support
/// - Batch command support (N commands in one FFI call)
/// - Zero-copy audio ring buffer access
/// - Bridge diagnostics and stats
///
/// Usage:
/// ```dart
/// final bridge = CortexBridgeService.instance;
///
/// // Single intent
/// final response = bridge.submit(
///   target: IntentTarget.mixer,
///   payload: {'type': 'SetVolume', 'track_id': 0, 'volume': 0.8},
/// );
///
/// // Batch
/// final batchResp = bridge.submitBatch([
///   BridgeIntent.setVolume(trackId: 0, volume: 0.5),
///   BridgeIntent.setMute(trackId: 1, muted: true),
/// ]);
///
/// // Event stream
/// bridge.eventStream.listen((event) {
///   if (event.type == 'CortexHealth') { ... }
/// });
/// ```

import 'dart:async';
import 'dart:convert';

import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Intent classification — why is this request being sent.
enum CommandIntent {
  userInteraction,
  automationPlayback,
  cortexHealing,
  presetLoad,
  recovery,
  script,
  slotLabEvent,
  mlInference,
  system;

  String get value => name.substring(0, 1).toUpperCase() + name.substring(1);
}

/// Target module for routing.
enum IntentTarget {
  audioEngine,
  dsp,
  mixer,
  slotLab,
  project,
  cortex,
  ml,
  plugin,
  video,
  script,
  auto;

  String get value {
    switch (this) {
      case IntentTarget.audioEngine:
        return 'AudioEngine';
      case IntentTarget.dsp:
        return 'Dsp';
      case IntentTarget.mixer:
        return 'Mixer';
      case IntentTarget.slotLab:
        return 'SlotLab';
      case IntentTarget.project:
        return 'Project';
      case IntentTarget.cortex:
        return 'Cortex';
      case IntentTarget.ml:
        return 'Ml';
      case IntentTarget.plugin:
        return 'Plugin';
      case IntentTarget.video:
        return 'Video';
      case IntentTarget.script:
        return 'Script';
      case IntentTarget.auto:
        return 'Auto';
    }
  }
}

/// Bridge response status.
enum ResponseStatus {
  ok,
  accepted,
  error,
  timeout,
  unavailable,
  partialSuccess;

  static ResponseStatus fromString(String s) {
    switch (s) {
      case 'Ok':
        return ResponseStatus.ok;
      case 'Accepted':
        return ResponseStatus.accepted;
      case 'Error':
        return ResponseStatus.error;
      case 'Timeout':
        return ResponseStatus.timeout;
      case 'Unavailable':
        return ResponseStatus.unavailable;
      case 'PartialSuccess':
        return ResponseStatus.partialSuccess;
      default:
        return ResponseStatus.error;
    }
  }
}

/// A typed response from Rust.
class BridgeResponse {
  final int correlationId;
  final ResponseStatus status;
  final String error;
  final Map<String, dynamic> payload;
  final int processingUs;
  final int commandsExecuted;

  BridgeResponse({
    required this.correlationId,
    required this.status,
    this.error = '',
    this.payload = const {},
    this.processingUs = 0,
    this.commandsExecuted = 0,
  });

  bool get isOk => status == ResponseStatus.ok || status == ResponseStatus.accepted;
  bool get isError => status == ResponseStatus.error;

  factory BridgeResponse.fromJson(Map<String, dynamic> json) {
    return BridgeResponse(
      correlationId: json['correlation_id'] as int? ?? 0,
      status: ResponseStatus.fromString(json['status'] as String? ?? 'Error'),
      error: json['error'] as String? ?? '',
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      processingUs: json['processing_us'] as int? ?? 0,
      commandsExecuted: json['commands_executed'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'BridgeResponse(cid=$correlationId, status=$status, '
      '${isError ? "error=$error, " : ""}elapsed=${processingUs}μs)';
}

/// An event pushed from Rust to Flutter.
class BridgeEvent {
  final String eventType;
  final int sequence;
  final int timestampMs;
  final Map<String, dynamic> payload;

  BridgeEvent({
    required this.eventType,
    required this.sequence,
    required this.timestampMs,
    this.payload = const {},
  });

  factory BridgeEvent.fromJson(Map<String, dynamic> json) {
    return BridgeEvent(
      eventType: json['event_type'] as String? ?? 'Unknown',
      sequence: json['sequence'] as int? ?? 0,
      timestampMs: json['timestamp_ms'] as int? ?? 0,
      payload: json['payload'] as Map<String, dynamic>? ?? {},
    );
  }

  bool get isCortexHealth => eventType == 'CortexHealth';
  bool get isMetering => eventType == 'Metering';
  bool get isTransport => eventType == 'Transport';
  bool get isFileChange => eventType == 'FileChange';
  bool get isHealing => eventType == 'CortexHealing';
}

/// Bridge statistics.
class BridgeStats {
  final int totalRequests;
  final int totalResponses;
  final int totalEvents;
  final int totalTimeouts;
  final int totalBatchCommands;
  final int pendingResponses;
  final int pendingEvents;
  final int uptimeMs;
  final int audioRingSequence;

  BridgeStats({
    this.totalRequests = 0,
    this.totalResponses = 0,
    this.totalEvents = 0,
    this.totalTimeouts = 0,
    this.totalBatchCommands = 0,
    this.pendingResponses = 0,
    this.pendingEvents = 0,
    this.uptimeMs = 0,
    this.audioRingSequence = 0,
  });

  factory BridgeStats.fromJson(Map<String, dynamic> json) {
    return BridgeStats(
      totalRequests: json['total_requests'] as int? ?? 0,
      totalResponses: json['total_responses'] as int? ?? 0,
      totalEvents: json['total_events'] as int? ?? 0,
      totalTimeouts: json['total_timeouts'] as int? ?? 0,
      totalBatchCommands: json['total_batch_commands'] as int? ?? 0,
      pendingResponses: json['pending_responses'] as int? ?? 0,
      pendingEvents: json['pending_events'] as int? ?? 0,
      uptimeMs: json['uptime_ms'] as int? ?? 0,
      audioRingSequence: json['audio_ring_sequence'] as int? ?? 0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTENT BUILDERS — Convenience constructors for common operations
// ═══════════════════════════════════════════════════════════════════════════════

/// Fluent builder for bridge intents.
class BridgeIntent {
  final CommandIntent intent;
  final IntentTarget target;
  final Map<String, dynamic> payload;
  final int timeoutMs;

  const BridgeIntent({
    this.intent = CommandIntent.userInteraction,
    this.target = IntentTarget.auto,
    required this.payload,
    this.timeoutMs = 0,
  });

  Map<String, dynamic> toJson(int correlationId) => {
        'correlation_id': correlationId,
        'intent': intent.value,
        'target': target.value,
        'timeout_ms': timeoutMs,
        'payload': payload,
      };

  // ── Transport ────────────────────────────────────────────────────────
  static BridgeIntent play() => const BridgeIntent(
        target: IntentTarget.audioEngine,
        payload: {'type': 'Play'},
      );

  static BridgeIntent stop() => const BridgeIntent(
        target: IntentTarget.audioEngine,
        payload: {'type': 'Stop'},
      );

  static BridgeIntent pause() => const BridgeIntent(
        target: IntentTarget.audioEngine,
        payload: {'type': 'Pause'},
      );

  static BridgeIntent seek(double positionSeconds) => BridgeIntent(
        target: IntentTarget.audioEngine,
        payload: {'type': 'Seek', 'position_seconds': positionSeconds},
      );

  static BridgeIntent setTempo(double bpm) => BridgeIntent(
        target: IntentTarget.audioEngine,
        payload: {'type': 'SetTempo', 'bpm': bpm},
      );

  static BridgeIntent setLoop({
    required bool enabled,
    required double start,
    required double end,
  }) =>
      BridgeIntent(
        target: IntentTarget.audioEngine,
        payload: {'type': 'SetLoop', 'enabled': enabled, 'start': start, 'end': end},
      );

  // ── Mixer ────────────────────────────────────────────────────────────
  static BridgeIntent setVolume({required int trackId, required double volume}) => BridgeIntent(
        target: IntentTarget.mixer,
        payload: {'type': 'SetVolume', 'track_id': trackId, 'volume': volume},
      );

  static BridgeIntent setPan({required int trackId, required double pan}) => BridgeIntent(
        target: IntentTarget.mixer,
        payload: {'type': 'SetPan', 'track_id': trackId, 'pan': pan},
      );

  static BridgeIntent setMute({required int trackId, required bool muted}) => BridgeIntent(
        target: IntentTarget.mixer,
        payload: {'type': 'SetMute', 'track_id': trackId, 'muted': muted},
      );

  static BridgeIntent setSolo({required int trackId, required bool solo}) => BridgeIntent(
        target: IntentTarget.mixer,
        payload: {'type': 'SetSolo', 'track_id': trackId, 'solo': solo},
      );

  static BridgeIntent setBusRoute({required int trackId, required int busIndex}) => BridgeIntent(
        target: IntentTarget.mixer,
        payload: {'type': 'SetBusRoute', 'track_id': trackId, 'bus_index': busIndex},
      );

  // ── DSP ──────────────────────────────────────────────────────────────
  static BridgeIntent dspCommand(String commandJson) => BridgeIntent(
        target: IntentTarget.dsp,
        payload: {'type': 'DspCommand', 'command_json': commandJson},
      );

  // ── CORTEX ───────────────────────────────────────────────────────────
  static BridgeIntent queryHealth() => const BridgeIntent(
        intent: CommandIntent.system,
        target: IntentTarget.cortex,
        payload: {'type': 'QueryHealth'},
      );

  static BridgeIntent queryAwareness() => const BridgeIntent(
        intent: CommandIntent.system,
        target: IntentTarget.cortex,
        payload: {'type': 'QueryAwareness'},
      );

  static BridgeIntent queryPatterns() => const BridgeIntent(
        intent: CommandIntent.system,
        target: IntentTarget.cortex,
        payload: {'type': 'QueryPatterns'},
      );

  static BridgeIntent emitSignal({
    required String origin,
    required String urgency,
    required String kindJson,
  }) =>
      BridgeIntent(
        target: IntentTarget.cortex,
        payload: {'type': 'EmitSignal', 'origin': origin, 'urgency': urgency, 'kind_json': kindJson},
      );

  // ── Project ──────────────────────────────────────────────────────────
  static BridgeIntent undo() => const BridgeIntent(
        target: IntentTarget.project,
        payload: {'type': 'Undo'},
      );

  static BridgeIntent redo() => const BridgeIntent(
        target: IntentTarget.project,
        payload: {'type': 'Redo'},
      );

  // ── System ───────────────────────────────────────────────────────────
  static BridgeIntent ping(int clientTimestampMs) => BridgeIntent(
        intent: CommandIntent.system,
        target: IntentTarget.cortex,
        payload: {'type': 'Ping', 'client_timestamp_ms': clientTimestampMs},
      );

  static BridgeIntent watchPath(String path, {bool recursive = true}) => BridgeIntent(
        intent: CommandIntent.system,
        target: IntentTarget.auto,
        payload: {'type': 'WatchPath', 'path': path, 'recursive': recursive},
      );

  static BridgeIntent unwatchPath(String path) => BridgeIntent(
        intent: CommandIntent.system,
        target: IntentTarget.auto,
        payload: {'type': 'UnwatchPath', 'path': path},
      );

  static BridgeIntent freeCaches() => const BridgeIntent(
        intent: CommandIntent.system,
        target: IntentTarget.auto,
        payload: {'type': 'Raw', 'json': '{"action":"free_caches"}'},
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// CORTEX BRIDGE SERVICE — Singleton
// ═══════════════════════════════════════════════════════════════════════════════

/// Unified bridge service — all Flutter↔Rust communication goes through here.
class CortexBridgeService {
  static CortexBridgeService? _instance;
  static CortexBridgeService get instance => _instance ??= CortexBridgeService._();

  final NativeFFI _ffi = NativeFFI.instance;

  /// Correlation ID counter (Dart side).
  int _nextCorrelationId = 1;

  /// Event stream — widgets listen to this for Rust→Flutter events.
  final _eventController = StreamController<BridgeEvent>.broadcast();
  Stream<BridgeEvent> get eventStream => _eventController.stream;

  /// Health-specific stream (filtered from eventStream).
  Stream<BridgeEvent> get healthStream =>
      eventStream.where((e) => e.isCortexHealth);

  /// Transport-specific stream.
  Stream<BridgeEvent> get transportStream =>
      eventStream.where((e) => e.isTransport);

  /// Metering-specific stream (high frequency — ~20Hz).
  Stream<BridgeEvent> get meteringStream =>
      eventStream.where((e) => e.isMetering);

  /// File change stream.
  Stream<BridgeEvent> get fileChangeStream =>
      eventStream.where((e) => e.isFileChange);

  /// Healing action stream.
  Stream<BridgeEvent> get healingStream =>
      eventStream.where((e) => e.isHealing);

  /// Event poll timer.
  Timer? _pollTimer;

  /// Stats cache.
  BridgeStats _lastStats = BridgeStats();

  /// Total latency measurements (for average).
  final List<int> _latencyMeasurements = [];

  CortexBridgeService._();

  // ─── Lifecycle ─────────────────────────────────────────────────────

  /// Start the event polling loop (~20Hz by default).
  void start({Duration pollInterval = const Duration(milliseconds: 50)}) {
    stop();
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollEvents());
  }

  /// Stop the event polling loop.
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Dispose everything.
  void dispose() {
    stop();
    _eventController.close();
  }

  // ─── Submit Intent ─────────────────────────────────────────────────

  /// Submit a single intent. Returns typed response.
  BridgeResponse submit(BridgeIntent intent) {
    final cid = _nextCorrelationId++;
    final json = jsonEncode(intent.toJson(cid));
    final responseJson = _ffi.intentSubmit(json);

    try {
      final decoded = jsonDecode(responseJson) as Map<String, dynamic>;
      return BridgeResponse.fromJson(decoded);
    } catch (e) {
      return BridgeResponse(
        correlationId: cid,
        status: ResponseStatus.error,
        error: 'Failed to parse response: $e',
      );
    }
  }

  /// Submit a batch of intents atomically. Returns batch response.
  BridgeResponse submitBatch(List<BridgeIntent> intents) {
    final requests = intents.map((i) {
      final cid = _nextCorrelationId++;
      return i.toJson(cid);
    }).toList();

    final json = jsonEncode(requests);
    final responseJson = _ffi.intentSubmitBatch(json);

    try {
      final decoded = jsonDecode(responseJson) as Map<String, dynamic>;
      return BridgeResponse.fromJson(decoded);
    } catch (e) {
      return BridgeResponse(
        correlationId: 0,
        status: ResponseStatus.error,
        error: 'Failed to parse batch response: $e',
      );
    }
  }

  // ─── Convenience Submitters ────────────────────────────────────────

  /// Transport: play.
  BridgeResponse play() => submit(BridgeIntent.play());

  /// Transport: stop.
  BridgeResponse stop_() => submit(BridgeIntent.stop());

  /// Transport: pause.
  BridgeResponse pause() => submit(BridgeIntent.pause());

  /// Transport: seek.
  BridgeResponse seek(double seconds) => submit(BridgeIntent.seek(seconds));

  /// Mixer: set volume (0.0-2.0 linear).
  BridgeResponse setVolume(int trackId, double volume) =>
      submit(BridgeIntent.setVolume(trackId: trackId, volume: volume));

  /// Mixer: set pan (-1.0 to 1.0).
  BridgeResponse setPan(int trackId, double pan) =>
      submit(BridgeIntent.setPan(trackId: trackId, pan: pan));

  /// Mixer: set mute.
  BridgeResponse setMute(int trackId, bool muted) =>
      submit(BridgeIntent.setMute(trackId: trackId, muted: muted));

  /// Mixer: set solo.
  BridgeResponse setSolo(int trackId, bool solo) =>
      submit(BridgeIntent.setSolo(trackId: trackId, solo: solo));

  /// CORTEX: query health.
  BridgeResponse queryHealth() => submit(BridgeIntent.queryHealth());

  /// CORTEX: query awareness.
  BridgeResponse queryAwareness() => submit(BridgeIntent.queryAwareness());

  /// CORTEX: query patterns.
  BridgeResponse queryPatterns() => submit(BridgeIntent.queryPatterns());

  /// Measure bridge latency (round-trip).
  Future<int> measureLatency() async {
    final clientTs = DateTime.now().millisecondsSinceEpoch;
    final response = submit(BridgeIntent.ping(clientTs));
    final serverTs = response.payload['server_timestamp_ms'] as int? ?? 0;
    final latency = DateTime.now().millisecondsSinceEpoch - clientTs;
    _latencyMeasurements.add(latency);
    if (_latencyMeasurements.length > 100) {
      _latencyMeasurements.removeAt(0);
    }
    return latency;
  }

  /// Average latency in ms.
  double get averageLatencyMs {
    if (_latencyMeasurements.isEmpty) return 0;
    return _latencyMeasurements.reduce((a, b) => a + b) / _latencyMeasurements.length;
  }

  // ─── Batch Helpers ─────────────────────────────────────────────────

  /// Set multiple track volumes in one FFI call.
  BridgeResponse batchSetVolumes(Map<int, double> trackVolumes) {
    return submitBatch(trackVolumes.entries
        .map((e) => BridgeIntent.setVolume(trackId: e.key, volume: e.value))
        .toList());
  }

  /// Mute multiple tracks in one FFI call.
  BridgeResponse batchSetMutes(Map<int, bool> trackMutes) {
    return submitBatch(trackMutes.entries
        .map((e) => BridgeIntent.setMute(trackId: e.key, muted: e.value))
        .toList());
  }

  // ─── Stats ─────────────────────────────────────────────────────────

  /// Get bridge statistics.
  BridgeStats get stats {
    try {
      final json = _ffi.intentStats();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      _lastStats = BridgeStats.fromJson(decoded);
    } catch (_) {}
    return _lastStats;
  }

  /// Number of pending events.
  int get pendingEvents => _ffi.intentPendingEvents();

  /// Audio ring sequence.
  int get audioRingSequence => _ffi.intentAudioRingSequence();

  // ─── File Watching ─────────────────────────────────────────────────

  /// Watch a path for changes (FSEvents on macOS, inotify on Linux).
  BridgeResponse watchPath(String path, {bool recursive = true}) =>
      submit(BridgeIntent.watchPath(path, recursive: recursive));

  /// Stop watching a path.
  BridgeResponse unwatchPath(String path) =>
      submit(BridgeIntent.unwatchPath(path));

  // ─── Internal: Event Polling ───────────────────────────────────────

  void _pollEvents() {
    final pending = _ffi.intentPendingEvents();
    if (pending == 0) return;

    final eventsJson = _ffi.intentDrainEvents(max: 64);
    try {
      final events = jsonDecode(eventsJson) as List<dynamic>;
      for (final eventMap in events) {
        if (eventMap is Map<String, dynamic>) {
          _eventController.add(BridgeEvent.fromJson(eventMap));
        }
      }
    } catch (_) {
      // Silently skip malformed events
    }
  }
}
