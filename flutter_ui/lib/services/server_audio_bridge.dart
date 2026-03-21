/// Server Audio Bridge — Routes server events to EventRegistry and RTPC
///
/// Bridges WebSocket messages from game server to FluxForge audio systems:
/// - `trigger` → EventRegistry.triggerEvent() for audio playback
/// - `rtpc` → RtpcSystemProvider.setRtpc() for parameter control
/// - `state` → Batch RTPC preset for game phase transitions
/// - `preload` / `unload` → Asset management
///
/// Does NOT own the WebSocket connection — receives parsed messages
/// from LiveEngineService or UltimateWebSocketClient.

import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';

import '../providers/subsystems/rtpc_system_provider.dart';

/// Overlap policy when same event triggers while already playing
enum TriggerOverlapPolicy { replace, overlap, queue, reject }

/// Server audio bridge configuration
class ServerBridgeConfig {
  /// RTPC name→ID mapping (server sends names, we need local IDs)
  final Map<String, int> rtpcNameMap;

  /// Event overlap policies per event ID
  final Map<String, TriggerOverlapPolicy> overlapPolicies;

  /// Default overlap policy
  final TriggerOverlapPolicy defaultOverlap;

  /// State→RTPC preset mapping (game phase → batch RTPC values)
  final Map<String, Map<String, double>> statePresets;

  /// RTPC interpolation default (ms)
  final int defaultInterpolationMs;

  /// Jitter buffer size (ms) for RTPC smoothing
  final int jitterBufferMs;

  const ServerBridgeConfig({
    this.rtpcNameMap = const {},
    this.overlapPolicies = const {},
    this.defaultOverlap = TriggerOverlapPolicy.overlap,
    this.statePresets = const {},
    this.defaultInterpolationMs = 200,
    this.jitterBufferMs = 50,
  });
}

/// Buffered RTPC value with timestamp for jitter smoothing
class _RtpcBufferEntry {
  final int rtpcId;
  final double value;
  final int interpolationMs;
  final int timestampMs;

  _RtpcBufferEntry({
    required this.rtpcId,
    required this.value,
    required this.interpolationMs,
    required this.timestampMs,
  });
}

/// Server Audio Bridge — singleton service
class ServerAudioBridge with ChangeNotifier {
  ServerAudioBridge._();
  static final instance = ServerAudioBridge._();

  ServerBridgeConfig _config = const ServerBridgeConfig();
  RtpcSystemProvider? _rtpcProvider;

  // Jitter buffer for RTPC values
  final Queue<_RtpcBufferEntry> _rtpcBuffer = Queue();
  Timer? _jitterFlushTimer;

  // Stats
  int _triggerCount = 0;
  int _rtpcCount = 0;
  int _stateCount = 0;
  int _errorCount = 0;
  String? _lastError;
  String _currentState = '';

  // Getters for monitoring UI
  int get triggerCount => _triggerCount;
  int get rtpcCount => _rtpcCount;
  int get stateCount => _stateCount;
  int get errorCount => _errorCount;
  String? get lastError => _lastError;
  String get currentState => _currentState;

  /// Initialize with config and RTPC provider reference
  void init(ServerBridgeConfig config, RtpcSystemProvider rtpcProvider) {
    _config = config;
    _rtpcProvider = rtpcProvider;

    // Start jitter buffer flush timer
    _jitterFlushTimer?.cancel();
    _jitterFlushTimer = Timer.periodic(
      Duration(milliseconds: _config.jitterBufferMs),
      (_) => _flushRtpcBuffer(),
    );
  }

  /// Dispose resources
  @override
  void dispose() {
    _jitterFlushTimer?.cancel();
    _rtpcBuffer.clear();
    super.dispose();
  }

  int _batchDepth = 0;
  static const _maxBatchDepth = 3;

  /// Process a parsed server message. Called by WebSocket listener.
  void processMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'trigger':
        _handleTrigger(msg);
      case 'rtpc':
        _handleRtpc(msg);
      case 'state':
        _handleState(msg);
      case 'batch':
        _handleBatch(msg);
      case 'snapshot':
        _handleSnapshot(msg);
      case 'preload':
        _handlePreload(msg);
      case 'unload':
        _handleUnload(msg);
      default:
        // Unknown type — ignore silently (forward compat)
        break;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // TRIGGER: Server event → EventRegistry
  // ═══════════════════════════════════════════════════════════════════

  void _handleTrigger(Map<String, dynamic> msg) {
    final eventId = msg['event'] as String?;
    if (eventId == null || eventId.isEmpty) {
      _logError('trigger: missing event ID');
      return;
    }

    // Apply params as RTPC before triggering (e.g., set win_tier before playing win sound)
    final params = msg['params'] as Map<String, dynamic>?;
    if (params != null) {
      for (final entry in params.entries) {
        final rtpcId = _config.rtpcNameMap[entry.key];
        if (rtpcId != null && entry.value is num) {
          _rtpcProvider?.setRtpc(rtpcId, (entry.value as num).toDouble());
        }
      }
    }

    // Trigger audio event via EventRegistry (if wired)
    try {
      if (EventRegistryLocator._instance == null) return;
      EventRegistryLocator.instance.triggerEvent(eventId);
      _triggerCount++;
      notifyListeners();
    } catch (e) {
      _logError('trigger "$eventId" failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // RTPC: Server parameter → existing RTPC system
  // ═══════════════════════════════════════════════════════════════════

  void _handleRtpc(Map<String, dynamic> msg) {
    final paramName = msg['param'] as String?;
    final value = (msg['value'] as num?)?.toDouble();
    if (paramName == null || value == null) {
      _logError('rtpc: missing param or value');
      return;
    }

    final rtpcId = _config.rtpcNameMap[paramName];
    if (rtpcId == null) {
      _logError('rtpc: unknown param "$paramName" (not in name→ID map)');
      return;
    }

    final interpolationMs = (msg['duration_ms'] as num?)?.toInt()
        ?? _config.defaultInterpolationMs;
    final timestampMs = (msg['ts'] as num?)?.toInt()
        ?? DateTime.now().millisecondsSinceEpoch;

    // Buffer for jitter smoothing
    _rtpcBuffer.addLast(_RtpcBufferEntry(
      rtpcId: rtpcId,
      value: value,
      interpolationMs: interpolationMs,
      timestampMs: timestampMs,
    ));
    _rtpcCount++;
  }

  /// Flush jitter buffer — apply buffered RTPC values in timestamp order
  void _flushRtpcBuffer() {
    if (_rtpcBuffer.isEmpty || _rtpcProvider == null) return;

    // Sort by timestamp (should already be mostly ordered)
    final sorted = _rtpcBuffer.toList()
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    _rtpcBuffer.clear();

    // Deduplicate: keep only latest value per RTPC ID
    final latest = <int, _RtpcBufferEntry>{};
    for (final entry in sorted) {
      latest[entry.rtpcId] = entry;
    }

    // Apply
    for (final entry in latest.values) {
      _rtpcProvider!.setRtpc(
        entry.rtpcId,
        entry.value,
        interpolationMs: entry.interpolationMs,
      );
    }

    if (latest.isNotEmpty) notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  // STATE: Game phase → batch RTPC preset
  // ═══════════════════════════════════════════════════════════════════

  void _handleState(Map<String, dynamic> msg) {
    final stateName = msg['state'] as String?;
    if (stateName == null) {
      _logError('state: missing state name');
      return;
    }

    _currentState = stateName;
    _stateCount++;

    // Look up preset for this state
    final preset = _config.statePresets[stateName];
    if (preset != null) {
      // Apply all RTPC values in preset
      final interpolation = (msg['transition_ms'] as num?)?.toInt() ?? 500;
      for (final entry in preset.entries) {
        final rtpcId = _config.rtpcNameMap[entry.key];
        if (rtpcId != null) {
          _rtpcProvider?.setRtpc(rtpcId, entry.value, interpolationMs: interpolation);
        }
      }
    }

    // Also trigger a state event if EventRegistry has one
    if (EventRegistryLocator._instance != null) {
      try {
        EventRegistryLocator.instance.triggerEvent('state_$stateName');
      } catch (_) {
        // State event is optional — no error if not found
      }
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  // BATCH: Multiple events in one message
  // ═══════════════════════════════════════════════════════════════════

  void _handleBatch(Map<String, dynamic> msg) {
    if (_batchDepth >= _maxBatchDepth) {
      _logError('batch: max depth $_maxBatchDepth exceeded');
      return;
    }
    final events = msg['events'] as List?;
    if (events == null) return;
    _batchDepth++;
    try {
      for (final event in events) {
        if (event is Map<String, dynamic>) {
          processMessage(event);
        }
      }
    } finally {
      _batchDepth--;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // SNAPSHOT: Full state recovery after reconnect
  // ═══════════════════════════════════════════════════════════════════

  void _handleSnapshot(Map<String, dynamic> msg) {
    // Apply all RTPC values from snapshot (no interpolation — instant)
    final state = msg['state'] as Map<String, dynamic>?;
    if (state != null) {
      for (final entry in state.entries) {
        final rtpcId = _config.rtpcNameMap[entry.key];
        if (rtpcId != null && entry.value is num) {
          _rtpcProvider?.setRtpc(rtpcId, (entry.value as num).toDouble(), interpolationMs: 0);
        }
      }
    }

    // Set current game state
    final gameState = msg['game_state'] as String?;
    if (gameState != null) {
      _currentState = gameState;
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  // ASSET MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════

  void _handlePreload(Map<String, dynamic> msg) {
    // TODO: Pre-load audio assets based on server request
    // final assets = msg['assets'] as List<String>?;
  }

  void _handleUnload(Map<String, dynamic> msg) {
    // TODO: Unload audio assets to free memory
    // final assets = msg['assets'] as List<String>?;
  }

  // ═══════════════════════════════════════════════════════════════════
  // ERROR & LOGGING
  // ═══════════════════════════════════════════════════════════════════

  void _logError(String message) {
    _errorCount++;
    _lastError = message;
    // No debugPrint — CLAUDE.md: "korisnik nema konzolu"
    // Error visible via lastError getter in monitoring UI
    notifyListeners();
  }

  /// Reset stats
  void resetStats() {
    _triggerCount = 0;
    _rtpcCount = 0;
    _stateCount = 0;
    _errorCount = 0;
    _lastError = null;
    notifyListeners();
  }

  /// Serialize config for project save
  Map<String, dynamic> toJson() => {
    'rtpcNameMap': _config.rtpcNameMap,
    'statePresets': _config.statePresets,
    'overlapPolicies': _config.overlapPolicies.map((k, v) => MapEntry(k, v.index)),
    'defaultOverlap': _config.defaultOverlap.index,
    'defaultInterpolationMs': _config.defaultInterpolationMs,
    'jitterBufferMs': _config.jitterBufferMs,
  };

  /// Load config from project
  void loadFromJson(Map<String, dynamic> json) {
    _config = ServerBridgeConfig(
      rtpcNameMap: (json['rtpcNameMap'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as int)) ?? {},
      statePresets: (json['statePresets'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as Map<String, dynamic>)
              .map((pk, pv) => MapEntry(pk, (pv as num).toDouble())))) ?? {},
      overlapPolicies: (json['overlapPolicies'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k,
              TriggerOverlapPolicy.values[(v as int).clamp(0, 3)])) ?? {},
      defaultOverlap: TriggerOverlapPolicy.values[
          (json['defaultOverlap'] as int? ?? 1).clamp(0, 3)],
      defaultInterpolationMs: json['defaultInterpolationMs'] as int? ?? 200,
      jitterBufferMs: json['jitterBufferMs'] as int? ?? 50,
    );
  }
}

/// Locator for EventRegistry (avoids circular dependency)
class EventRegistryLocator {
  static dynamic _instance;
  static dynamic get instance => _instance!;
  static set instance(dynamic registry) => _instance = registry;
}
