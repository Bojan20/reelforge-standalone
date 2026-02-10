/// Voice Steal Profiler Service
///
/// P1-09: Voice Steal Statistics
///
/// Tracks which events get their voices stolen most frequently,
/// helping identify voice pool sizing issues and priority conflicts.
///
/// Voice stealing occurs when:
/// 1. All voice slots are full (48 max)
/// 2. New high-priority event needs a voice
/// 3. Lowest-priority active voice is stolen
///
/// This helps answer:
/// - Which events suffer most from voice stealing?
/// - Are there priority conflicts (high-priority events getting stolen)?
/// - Is the voice pool size adequate?
/// - Which stages trigger most steals?

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

/// Voice steal event
class VoiceStealEvent {
  /// Timestamp (microseconds)
  final int timestampUs;

  /// Voice ID that was stolen
  final int stolenVoiceId;

  /// Event/stage that was stolen
  final String stolenSource;

  /// Priority of stolen voice
  final int stolenPriority;

  /// Event/stage that triggered the steal (stole the voice)
  final String stealerSource;

  /// Priority of stealing voice
  final int stealerPriority;

  /// Bus ID of stolen voice
  final int busId;

  /// Time the stolen voice had been playing (microseconds)
  final int playDurationUs;

  VoiceStealEvent({
    required this.timestampUs,
    required this.stolenVoiceId,
    required this.stolenSource,
    required this.stolenPriority,
    required this.stealerSource,
    required this.stealerPriority,
    required this.busId,
    required this.playDurationUs,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'timestampUs': timestampUs,
    'stolenVoiceId': stolenVoiceId,
    'stolenSource': stolenSource,
    'stolenPriority': stolenPriority,
    'stealerSource': stealerSource,
    'stealerPriority': stealerPriority,
    'busId': busId,
    'playDurationUs': playDurationUs,
    'playDurationMs': playDurationMs,
  };

  /// Play duration in milliseconds
  double get playDurationMs => playDurationUs / 1000.0;

  /// Priority delta (positive = higher priority stole lower priority)
  int get priorityDelta => stealerPriority - stolenPriority;

  /// Is this an abnormal steal? (lower priority stole higher priority)
  bool get isAbnormal => priorityDelta < 0;
}

/// Voice steal statistics for a source
class SourceStealStats {
  /// Source name (event or stage)
  final String source;

  /// Times this source was stolen
  int stolenCount = 0;

  /// Times this source stole another voice
  int stealerCount = 0;

  /// Average play duration before being stolen (microseconds)
  double avgPlayDurationUs = 0.0;

  /// Min play duration before being stolen
  int minPlayDurationUs = 0;

  /// Max play duration before being stolen
  int maxPlayDurationUs = 0;

  /// Abnormal steals (lower priority stole this)
  int abnormalSteals = 0;

  SourceStealStats(this.source);

  /// Steal rate (steals per occurrence)
  double get stealRate {
    final total = stolenCount + stealerCount;
    return total > 0 ? stolenCount / total : 0.0;
  }

  /// Average play duration in milliseconds
  double get avgPlayDurationMs => avgPlayDurationUs / 1000.0;
}

/// Voice Steal Profiler
class VoiceStealProfiler extends ChangeNotifier {
  // ─── Singleton ─────────────────────────────────────────────────────────────
  static VoiceStealProfiler? _instance;
  static VoiceStealProfiler get instance => _instance ??= VoiceStealProfiler._();

  VoiceStealProfiler._();

  // ─── State ─────────────────────────────────────────────────────────────────
  final NativeFFI _ffi = NativeFFI.instance;

  /// All steal events (limited history)
  final List<VoiceStealEvent> _stealEvents = [];

  /// Per-source statistics
  final Map<String, SourceStealStats> _sourceStats = {};

  /// Max steal events to keep
  static const int maxHistory = 5000;

  /// Is profiling enabled?
  bool _enabled = false;

  /// Polling timer for FFI steal events
  Timer? _pollTimer;

  // ─── Getters ───────────────────────────────────────────────────────────────

  /// Is profiling enabled?
  bool get enabled => _enabled;

  /// Total steal events recorded
  int get totalSteals => _stealEvents.length;

  /// Get all steal events
  List<VoiceStealEvent> get stealEvents => List.unmodifiable(_stealEvents);

  /// Get recent steal events
  List<VoiceStealEvent> getRecentSteals(int count) {
    return _stealEvents.reversed.take(count).toList();
  }

  /// Get per-source statistics
  Map<String, SourceStealStats> get sourceStats => Map.unmodifiable(_sourceStats);

  /// Get top stolen sources (sorted by steal count)
  List<SourceStealStats> getTopStolenSources(int count) {
    final sorted = _sourceStats.values.toList()
      ..sort((a, b) => b.stolenCount.compareTo(a.stolenCount));
    return sorted.take(count).toList();
  }

  /// Get sources with abnormal steals (lower priority stole higher)
  List<SourceStealStats> getAbnormalStealSources() {
    return _sourceStats.values.where((s) => s.abnormalSteals > 0).toList()
      ..sort((a, b) => b.abnormalSteals.compareTo(a.abnormalSteals));
  }

  // ─── Control ───────────────────────────────────────────────────────────────

  /// Enable voice steal profiling
  void enable() {
    if (_enabled) return;
    _enabled = true;
    _startPolling();
    notifyListeners();
  }

  /// Disable voice steal profiling
  void disable() {
    if (!_enabled) return;
    _enabled = false;
    _stopPolling();
    notifyListeners();
  }

  /// Clear all statistics
  void clear() {
    _stealEvents.clear();
    _sourceStats.clear();
    notifyListeners();
  }

  // ─── Polling ───────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    // Poll every 100ms for steal events from engine
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pollStealEvents();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _pollStealEvents() {
    // TODO: FFI function to get pending steal events
    // For now, this is a placeholder for when Rust FFI is implemented
    //
    // Expected FFI function:
    // List<VoiceStealEvent> getVoiceStealEvents();
    //
    // This would return all steal events since last poll
  }

  // ─── Recording ─────────────────────────────────────────────────────────────

  /// Record a voice steal event
  ///
  /// This should be called from EventRegistry or AudioPlaybackService
  /// when a voice allocation fails and triggers a steal.
  void recordSteal({
    required int stolenVoiceId,
    required String stolenSource,
    required int stolenPriority,
    required String stealerSource,
    required int stealerPriority,
    required int busId,
    required int playDurationUs,
  }) {
    if (!_enabled) return;

    final event = VoiceStealEvent(
      timestampUs: DateTime.now().microsecondsSinceEpoch,
      stolenVoiceId: stolenVoiceId,
      stolenSource: stolenSource,
      stolenPriority: stolenPriority,
      stealerSource: stealerSource,
      stealerPriority: stealerPriority,
      busId: busId,
      playDurationUs: playDurationUs,
    );

    // Add to history
    _stealEvents.add(event);
    if (_stealEvents.length > maxHistory) {
      _stealEvents.removeAt(0);
    }

    // Update source statistics
    _updateSourceStats(event);

    // Log abnormal steals
    if (event.isAbnormal) {
    }

    notifyListeners();
  }

  void _updateSourceStats(VoiceStealEvent event) {
    // Update stolen source stats
    final stolenStats = _sourceStats.putIfAbsent(
      event.stolenSource,
      () => SourceStealStats(event.stolenSource),
    );

    stolenStats.stolenCount++;

    // Update average play duration
    final totalDuration = stolenStats.avgPlayDurationUs * (stolenStats.stolenCount - 1);
    stolenStats.avgPlayDurationUs = (totalDuration + event.playDurationUs) / stolenStats.stolenCount;

    // Update min/max
    if (stolenStats.minPlayDurationUs == 0 || event.playDurationUs < stolenStats.minPlayDurationUs) {
      stolenStats.minPlayDurationUs = event.playDurationUs;
    }
    if (event.playDurationUs > stolenStats.maxPlayDurationUs) {
      stolenStats.maxPlayDurationUs = event.playDurationUs;
    }

    // Count abnormal steals
    if (event.isAbnormal) {
      stolenStats.abnormalSteals++;
    }

    // Update stealer source stats
    final stealerStats = _sourceStats.putIfAbsent(
      event.stealerSource,
      () => SourceStealStats(event.stealerSource),
    );

    stealerStats.stealerCount++;
  }

  // ─── Export ────────────────────────────────────────────────────────────────

  /// Export steal events to JSON
  String exportToJson() {
    final data = {
      'enabled': _enabled,
      'totalSteals': totalSteals,
      'stealEvents': _stealEvents.map((e) => e.toJson()).toList(),
      'sourceStats': _sourceStats.map((key, value) => MapEntry(key, {
        'source': value.source,
        'stolenCount': value.stolenCount,
        'stealerCount': value.stealerCount,
        'avgPlayDurationMs': value.avgPlayDurationMs,
        'abnormalSteals': value.abnormalSteals,
        'stealRate': value.stealRate,
      })),
    };

    return data.toString();
  }

  /// Export to CSV
  String exportToCsv() {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('timestamp_us,stolen_voice_id,stolen_source,stolen_priority,'
        'stealer_source,stealer_priority,bus_id,play_duration_us,play_duration_ms,abnormal');

    // Data rows
    for (final event in _stealEvents) {
      buffer.writeln(
        '${event.timestampUs},'
        '${event.stolenVoiceId},'
        '"${event.stolenSource}",'
        '${event.stolenPriority},'
        '"${event.stealerSource}",'
        '${event.stealerPriority},'
        '${event.busId},'
        '${event.playDurationUs},'
        '${event.playDurationMs.toStringAsFixed(2)},'
        '${event.isAbnormal ? "YES" : "NO"}'
      );
    }

    return buffer.toString();
  }
}
