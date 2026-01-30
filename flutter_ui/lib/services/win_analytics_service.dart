/// Win Analytics Service — Tracks win presentation events for analysis
///
/// Provides analytics tracking for:
/// - Win tier distribution (how often each tier is triggered)
/// - Rollup timing (duration per tier)
/// - Skip behavior (how often users skip presentation)
/// - Session metrics (total wins, biggest win, etc.)
///
/// This service is designed to be lightweight and non-blocking.
/// Events are buffered and can be exported for analysis.
library;

import 'dart:convert';

/// Analytics event types for win presentation
enum WinAnalyticsEventType {
  /// Win tier triggered (BIG, SUPER, MEGA, EPIC, ULTRA)
  winTierTriggered,

  /// Rollup started
  rollupStarted,

  /// Rollup completed (not skipped)
  rollupCompleted,

  /// Rollup skipped by user
  rollupSkipped,

  /// Win line shown
  winLineShown,

  /// Symbol highlight completed
  symbolHighlightCompleted,

  /// Skip requested during presentation
  skipRequested,

  /// Skip completed (fade out finished)
  skipCompleted,

  /// Tier progression step (for BIG+ wins)
  tierProgressionStep,

  /// Session started
  sessionStarted,

  /// Session ended
  sessionEnded,
}

/// Single analytics event with timestamp and metadata
class WinAnalyticsEvent {
  final DateTime timestamp;
  final WinAnalyticsEventType type;
  final Map<String, dynamic> data;

  const WinAnalyticsEvent({
    required this.timestamp,
    required this.type,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'data': data,
      };

  factory WinAnalyticsEvent.fromJson(Map<String, dynamic> json) {
    return WinAnalyticsEvent(
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: WinAnalyticsEventType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => WinAnalyticsEventType.winTierTriggered,
      ),
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }
}

/// Session statistics summary
class WinSessionStats {
  final DateTime sessionStart;
  DateTime? sessionEnd;

  int totalSpins = 0;
  int totalWins = 0;
  int skippedPresentations = 0;
  double totalWinAmount = 0.0;
  double biggestWin = 0.0;
  String biggestWinTier = '';

  /// Tier counts
  final Map<String, int> tierCounts = {
    'SMALL': 0,
    'BIG': 0,
    'SUPER': 0,
    'MEGA': 0,
    'EPIC': 0,
    'ULTRA': 0,
  };

  /// Average rollup duration per tier (in ms)
  final Map<String, List<int>> rollupDurations = {};

  WinSessionStats({required this.sessionStart});

  /// Calculate average rollup duration for a tier
  double getAverageRollupDuration(String tier) {
    final durations = rollupDurations[tier];
    if (durations == null || durations.isEmpty) return 0;
    return durations.reduce((a, b) => a + b) / durations.length;
  }

  /// Get skip rate (0.0 to 1.0)
  double get skipRate => totalWins > 0 ? skippedPresentations / totalWins : 0;

  /// Get win rate (0.0 to 1.0)
  double get winRate => totalSpins > 0 ? totalWins / totalSpins : 0;

  Map<String, dynamic> toJson() => {
        'sessionStart': sessionStart.toIso8601String(),
        'sessionEnd': sessionEnd?.toIso8601String(),
        'totalSpins': totalSpins,
        'totalWins': totalWins,
        'skippedPresentations': skippedPresentations,
        'totalWinAmount': totalWinAmount,
        'biggestWin': biggestWin,
        'biggestWinTier': biggestWinTier,
        'tierCounts': tierCounts,
        'skipRate': skipRate,
        'winRate': winRate,
        'averageRollupDurations': rollupDurations.map(
          (k, v) => MapEntry(k, getAverageRollupDuration(k)),
        ),
      };
}

/// Win Analytics Service — Singleton
///
/// Usage:
/// ```dart
/// WinAnalyticsService.instance.startSession();
/// WinAnalyticsService.instance.trackWinTier('BIG', winAmount: 500.0, betAmount: 10.0);
/// WinAnalyticsService.instance.trackRollupStarted('BIG', targetAmount: 500.0);
/// WinAnalyticsService.instance.trackRollupCompleted('BIG', durationMs: 2500);
/// WinAnalyticsService.instance.trackSkipRequested('BIG', progressPercent: 0.3);
/// final stats = WinAnalyticsService.instance.getSessionStats();
/// ```
class WinAnalyticsService {
  static final WinAnalyticsService instance = WinAnalyticsService._();
  WinAnalyticsService._();

  /// Maximum events to keep in buffer
  static const int _maxEventBuffer = 1000;

  /// Event buffer
  final List<WinAnalyticsEvent> _events = [];

  /// Current session stats
  WinSessionStats? _currentSession;

  /// All historical sessions (for trend analysis)
  final List<WinSessionStats> _historicalSessions = [];

  /// Get current session stats (or null if no session)
  WinSessionStats? get currentSession => _currentSession;

  /// Get historical sessions
  List<WinSessionStats> get historicalSessions =>
      List.unmodifiable(_historicalSessions);

  /// Get all buffered events
  List<WinAnalyticsEvent> get events => List.unmodifiable(_events);

  /// Start a new analytics session
  void startSession() {
    // End previous session if exists
    if (_currentSession != null) {
      endSession();
    }

    _currentSession = WinSessionStats(sessionStart: DateTime.now());
    _addEvent(WinAnalyticsEventType.sessionStarted, {});
  }

  /// End the current session
  void endSession() {
    if (_currentSession != null) {
      _currentSession!.sessionEnd = DateTime.now();
      _historicalSessions.add(_currentSession!);
      _addEvent(WinAnalyticsEventType.sessionEnded, _currentSession!.toJson());
      _currentSession = null;
    }
  }

  /// Track a spin (for win rate calculation)
  void trackSpin() {
    _currentSession?.totalSpins++;
  }

  /// Track a win tier triggered
  void trackWinTier(
    String tier, {
    required double winAmount,
    required double betAmount,
  }) {
    final xBet = betAmount > 0 ? winAmount / betAmount : 0.0;

    _addEvent(WinAnalyticsEventType.winTierTriggered, {
      'tier': tier,
      'winAmount': winAmount,
      'betAmount': betAmount,
      'xBet': xBet,
    });

    // Update session stats
    if (_currentSession != null) {
      _currentSession!.totalWins++;
      _currentSession!.totalWinAmount += winAmount;

      // Update tier count
      final tierKey = tier.isEmpty ? 'SMALL' : tier;
      _currentSession!.tierCounts[tierKey] =
          (_currentSession!.tierCounts[tierKey] ?? 0) + 1;

      // Track biggest win
      if (winAmount > _currentSession!.biggestWin) {
        _currentSession!.biggestWin = winAmount;
        _currentSession!.biggestWinTier = tierKey;
      }
    }
  }

  /// Track rollup started
  void trackRollupStarted(String tier, {required double targetAmount}) {
    _addEvent(WinAnalyticsEventType.rollupStarted, {
      'tier': tier,
      'targetAmount': targetAmount,
      'startTime': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Track rollup completed (not skipped)
  void trackRollupCompleted(String tier, {required int durationMs}) {
    _addEvent(WinAnalyticsEventType.rollupCompleted, {
      'tier': tier,
      'durationMs': durationMs,
    });

    // Update session rollup durations
    if (_currentSession != null) {
      final tierKey = tier.isEmpty ? 'SMALL' : tier;
      _currentSession!.rollupDurations.putIfAbsent(tierKey, () => []);
      _currentSession!.rollupDurations[tierKey]!.add(durationMs);
    }
  }

  /// Track rollup skipped by user
  void trackRollupSkipped(String tier, {required double progressPercent}) {
    _addEvent(WinAnalyticsEventType.rollupSkipped, {
      'tier': tier,
      'progressPercent': progressPercent,
    });

    _currentSession?.skippedPresentations++;
  }

  /// Track skip requested
  void trackSkipRequested(String tier, {required double progressPercent}) {
    _addEvent(WinAnalyticsEventType.skipRequested, {
      'tier': tier,
      'progressPercent': progressPercent,
    });
  }

  /// Track skip completed
  void trackSkipCompleted(String tier, {required int fadeOutDurationMs}) {
    _addEvent(WinAnalyticsEventType.skipCompleted, {
      'tier': tier,
      'fadeOutDurationMs': fadeOutDurationMs,
    });
  }

  /// Track win line shown
  void trackWinLineShown({required int lineIndex, required int symbolCount}) {
    _addEvent(WinAnalyticsEventType.winLineShown, {
      'lineIndex': lineIndex,
      'symbolCount': symbolCount,
    });
  }

  /// Track symbol highlight completed
  void trackSymbolHighlightCompleted({required int symbolCount}) {
    _addEvent(WinAnalyticsEventType.symbolHighlightCompleted, {
      'symbolCount': symbolCount,
    });
  }

  /// Track tier progression step (for BIG+ wins)
  void trackTierProgressionStep({
    required String fromTier,
    required String toTier,
    required int stepIndex,
  }) {
    _addEvent(WinAnalyticsEventType.tierProgressionStep, {
      'fromTier': fromTier,
      'toTier': toTier,
      'stepIndex': stepIndex,
    });
  }

  /// Get session statistics summary
  WinSessionStats? getSessionStats() => _currentSession;

  /// Export all events as JSON
  String exportEventsAsJson() {
    return jsonEncode(_events.map((e) => e.toJson()).toList());
  }

  /// Export session summary as JSON
  String exportSessionSummaryAsJson() {
    return jsonEncode({
      'currentSession': _currentSession?.toJson(),
      'historicalSessions': _historicalSessions.map((s) => s.toJson()).toList(),
    });
  }

  /// Clear all events
  void clearEvents() {
    _events.clear();
  }

  /// Clear historical sessions
  void clearHistory() {
    _historicalSessions.clear();
  }

  /// Internal: Add event to buffer
  void _addEvent(WinAnalyticsEventType type, Map<String, dynamic> data) {
    // Trim buffer if too large
    if (_events.length >= _maxEventBuffer) {
      _events.removeRange(0, _events.length ~/ 2);
    }

    _events.add(WinAnalyticsEvent(
      timestamp: DateTime.now(),
      type: type,
      data: data,
    ));
  }
}
