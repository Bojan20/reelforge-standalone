/// Memory Leak Detector Service
///
/// P2-09: Detects memory leaks in audio system:
/// - Unreleased voices
/// - Orphaned timers
/// - Unclosed streams
/// - Retained event listeners
/// - Voice pool exhaustion
///
/// Usage:
/// ```dart
/// MemoryLeakDetector.instance.startMonitoring();
/// // ... run audio operations ...
/// final report = MemoryLeakDetector.instance.generateReport();
/// print(report);
/// ```

import 'dart:async';

/// Memory leak type
enum LeakType {
  /// Voice not released after playback
  unreleasedVoice,

  /// Timer not cancelled
  orphanedTimer,

  /// Stream not closed
  unclosedStream,

  /// Event listener not removed
  retainedListener,

  /// Voice pool exhausted
  voicePoolExhaustion,

  /// Large object not disposed
  largeObjectRetention,
}

/// Memory leak detection entry
class LeakDetectionEntry {
  final LeakType type;
  final String description;
  final DateTime detectedAt;
  final String? source; // Where leak was created
  final int? objectId; // ID of leaked object
  final Map<String, dynamic>? metadata;

  const LeakDetectionEntry({
    required this.type,
    required this.description,
    required this.detectedAt,
    this.source,
    this.objectId,
    this.metadata,
  });

  Duration get age => DateTime.now().difference(detectedAt);

  @override
  String toString() => '[$type] $description (age: ${age.inSeconds}s)';
}

/// Memory leak detector
class MemoryLeakDetector {
  static final MemoryLeakDetector _instance = MemoryLeakDetector._();
  static MemoryLeakDetector get instance => _instance;

  MemoryLeakDetector._();

  bool _monitoring = false;
  final List<LeakDetectionEntry> _detectedLeaks = [];

  // Tracked objects
  final Map<int, DateTime> _trackedVoices = {}; // voiceId → creation time
  final Map<int, DateTime> _trackedTimers = {}; // timerId → creation time
  final Map<int, DateTime> _trackedStreams = {}; // streamId → creation time
  final Map<int, DateTime> _trackedListeners = {}; // listenerId → creation time

  // Thresholds
  static const Duration _voiceLeakThreshold = Duration(seconds: 30);
  static const Duration _timerLeakThreshold = Duration(minutes: 5);
  static const Duration _streamLeakThreshold = Duration(minutes: 1);
  static const Duration _listenerLeakThreshold = Duration(minutes: 10);

  // Monitoring timer
  Timer? _monitoringTimer;

  /// Start monitoring for leaks
  void startMonitoring({Duration scanInterval = const Duration(seconds: 5)}) {
    if (_monitoring) return;

    _monitoring = true;
    _monitoringTimer?.cancel();
    _monitoringTimer = Timer.periodic(scanInterval, (_) => _scanForLeaks());

  }

  /// Stop monitoring
  void stopMonitoring() {
    _monitoring = false;
    _monitoringTimer?.cancel();
    _monitoringTimer = null;

  }

  /// Track voice creation
  void trackVoiceCreated(int voiceId, {String? source}) {
    if (!_monitoring) return;
    _trackedVoices[voiceId] = DateTime.now();
  }

  /// Track voice release
  void trackVoiceReleased(int voiceId) {
    _trackedVoices.remove(voiceId);
  }

  /// Track timer creation
  void trackTimerCreated(int timerId, {String? source}) {
    if (!_monitoring) return;
    _trackedTimers[timerId] = DateTime.now();
  }

  /// Track timer cancellation
  void trackTimerCancelled(int timerId) {
    _trackedTimers.remove(timerId);
  }

  /// Track stream creation
  void trackStreamCreated(int streamId, {String? source}) {
    if (!_monitoring) return;
    _trackedStreams[streamId] = DateTime.now();
  }

  /// Track stream closure
  void trackStreamClosed(int streamId) {
    _trackedStreams.remove(streamId);
  }

  /// Track listener registration
  void trackListenerAdded(int listenerId, {String? source}) {
    if (!_monitoring) return;
    _trackedListeners[listenerId] = DateTime.now();
  }

  /// Track listener removal
  void trackListenerRemoved(int listenerId) {
    _trackedListeners.remove(listenerId);
  }

  /// Scan for leaks
  void _scanForLeaks() {
    final now = DateTime.now();

    // Check voices
    _trackedVoices.forEach((voiceId, createdAt) {
      final age = now.difference(createdAt);
      if (age > _voiceLeakThreshold) {
        _detectedLeaks.add(LeakDetectionEntry(
          type: LeakType.unreleasedVoice,
          description: 'Voice $voiceId not released after ${age.inSeconds}s',
          detectedAt: now,
          objectId: voiceId,
          metadata: {'createdAt': createdAt.toIso8601String()},
        ));
        _trackedVoices.remove(voiceId);
      }
    });

    // Check timers
    _trackedTimers.forEach((timerId, createdAt) {
      final age = now.difference(createdAt);
      if (age > _timerLeakThreshold) {
        _detectedLeaks.add(LeakDetectionEntry(
          type: LeakType.orphanedTimer,
          description: 'Timer $timerId not cancelled after ${age.inSeconds}s',
          detectedAt: now,
          objectId: timerId,
        ));
        _trackedTimers.remove(timerId);
      }
    });

    // Check streams
    _trackedStreams.forEach((streamId, createdAt) {
      final age = now.difference(createdAt);
      if (age > _streamLeakThreshold) {
        _detectedLeaks.add(LeakDetectionEntry(
          type: LeakType.unclosedStream,
          description: 'Stream $streamId not closed after ${age.inSeconds}s',
          detectedAt: now,
          objectId: streamId,
        ));
        _trackedStreams.remove(streamId);
      }
    });

    // Check listeners
    _trackedListeners.forEach((listenerId, createdAt) {
      final age = now.difference(createdAt);
      if (age > _listenerLeakThreshold) {
        _detectedLeaks.add(LeakDetectionEntry(
          type: LeakType.retainedListener,
          description: 'Listener $listenerId not removed after ${age.inSeconds}s',
          detectedAt: now,
          objectId: listenerId,
        ));
        _trackedListeners.remove(listenerId);
      }
    });
  }

  /// Get all detected leaks
  List<LeakDetectionEntry> get leaks => List.unmodifiable(_detectedLeaks);

  /// Get leak count
  int get leakCount => _detectedLeaks.length;

  /// Get leaks by type
  List<LeakDetectionEntry> getLeaksByType(LeakType type) {
    return _detectedLeaks.where((l) => l.type == type).toList();
  }

  /// Clear detected leaks
  void clearLeaks() {
    _detectedLeaks.clear();
  }

  /// Generate report
  String generateReport() {
    final sb = StringBuffer();
    sb.writeln('=== Memory Leak Detection Report ===');
    sb.writeln('Monitoring: ${_monitoring ? 'ON' : 'OFF'}');
    sb.writeln('Detected Leaks: ${_detectedLeaks.length}');
    sb.writeln('');

    if (_detectedLeaks.isEmpty) {
      sb.writeln('✅ No leaks detected');
    } else {
      // Group by type
      final byType = <LeakType, List<LeakDetectionEntry>>{};
      for (final leak in _detectedLeaks) {
        byType.putIfAbsent(leak.type, () => []).add(leak);
      }

      for (final entry in byType.entries) {
        sb.writeln('${entry.key.name}: ${entry.value.length}');
        for (final leak in entry.value) {
          sb.writeln('  • $leak');
        }
        sb.writeln('');
      }
    }

    sb.writeln('Currently Tracked:');
    sb.writeln('  Voices: ${_trackedVoices.length}');
    sb.writeln('  Timers: ${_trackedTimers.length}');
    sb.writeln('  Streams: ${_trackedStreams.length}');
    sb.writeln('  Listeners: ${_trackedListeners.length}');

    return sb.toString();
  }

  /// Export to JSON
  Map<String, dynamic> toJson() {
    return {
      'monitoring': _monitoring,
      'leakCount': _detectedLeaks.length,
      'leaks': _detectedLeaks.map((l) => {
        'type': l.type.name,
        'description': l.description,
        'detectedAt': l.detectedAt.toIso8601String(),
        'ageSeconds': l.age.inSeconds,
        'objectId': l.objectId,
        'source': l.source,
        'metadata': l.metadata,
      }).toList(),
      'tracked': {
        'voices': _trackedVoices.length,
        'timers': _trackedTimers.length,
        'streams': _trackedStreams.length,
        'listeners': _trackedListeners.length,
      },
    };
  }
}
