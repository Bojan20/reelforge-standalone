/// Session Replay Models
///
/// Data structures for recording and replaying SlotLab sessions
/// with deterministic audio playback.
///
/// Created: 2026-01-30 (P4.9)

import 'dart:convert';

import 'stage_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SESSION RECORDING
// ═══════════════════════════════════════════════════════════════════════════

/// State of the session recorder
enum RecordingState {
  idle,
  recording,
  paused,
  stopped;

  String get displayName => switch (this) {
        idle => 'Idle',
        recording => 'Recording',
        paused => 'Paused',
        stopped => 'Stopped',
      };

  bool get isActive => this == recording;
  bool get canRecord => this == idle || this == stopped;
  bool get canPause => this == recording;
  bool get canResume => this == paused;
  bool get canStop => this == recording || this == paused;
}

/// State of the session replay
enum ReplayState {
  idle,
  loading,
  playing,
  paused,
  seeking,
  stopped,
  error;

  String get displayName => switch (this) {
        idle => 'Idle',
        loading => 'Loading',
        playing => 'Playing',
        paused => 'Paused',
        seeking => 'Seeking',
        stopped => 'Stopped',
        error => 'Error',
      };

  bool get isActive => this == playing;
  bool get canPlay => this == idle || this == paused || this == stopped;
  bool get canPause => this == playing;
  bool get canSeek => this == playing || this == paused || this == stopped;
  bool get canStop => this == playing || this == paused;
}

/// Playback speed multiplier
enum ReplaySpeed {
  quarter(0.25, '0.25x'),
  half(0.5, '0.5x'),
  normal(1.0, '1x'),
  oneAndHalf(1.5, '1.5x'),
  twice(2.0, '2x'),
  quadruple(4.0, '4x');

  final num multiplier;
  final String label;

  const ReplaySpeed(this.multiplier, this.label);

  static ReplaySpeed fromMultiplier(num m) {
    if (m <= 0.25) return quarter;
    if (m <= 0.5) return half;
    if (m <= 1.0) return normal;
    if (m <= 1.5) return oneAndHalf;
    if (m <= 2.0) return twice;
    return quadruple;
  }
}

/// A single recorded spin within a session
class RecordedSpin {
  final String spinId;
  final int spinIndex;
  final DateTime timestamp;
  final double betAmount;
  final double winAmount;
  final List<List<int>>? reelGrid;
  final StageTrace trace;
  final List<SeedSnapshot> seedSnapshots;
  final Map<String, dynamic> metadata;

  const RecordedSpin({
    required this.spinId,
    required this.spinIndex,
    required this.timestamp,
    required this.betAmount,
    required this.winAmount,
    this.reelGrid,
    required this.trace,
    this.seedSnapshots = const [],
    this.metadata = const {},
  });

  double get winRatio => betAmount > 0 ? winAmount / betAmount : 0.0;

  bool get isWin => winAmount > 0;

  bool get hasFeature => trace.hasFeature;

  bool get hasJackpot => trace.hasJackpot;

  Duration get duration => Duration(milliseconds: trace.durationMs.toInt());

  factory RecordedSpin.fromJson(Map<String, dynamic> json) => RecordedSpin(
        spinId: json['spin_id'] as String? ?? '',
        spinIndex: json['spin_index'] as int? ?? 0,
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : DateTime.now(),
        betAmount: (json['bet_amount'] as num?)?.toDouble() ?? 0.0,
        winAmount: (json['win_amount'] as num?)?.toDouble() ?? 0.0,
        reelGrid: (json['reel_grid'] as List<dynamic>?)
            ?.map((row) => (row as List<dynamic>).cast<int>().toList())
            .toList(),
        trace: StageTrace.fromJson(json['trace'] as Map<String, dynamic>),
        seedSnapshots: (json['seed_snapshots'] as List<dynamic>?)
                ?.map((e) => SeedSnapshot.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'spin_id': spinId,
        'spin_index': spinIndex,
        'timestamp': timestamp.toIso8601String(),
        'bet_amount': betAmount,
        'win_amount': winAmount,
        if (reelGrid != null) 'reel_grid': reelGrid,
        'trace': trace.toJson(),
        if (seedSnapshots.isNotEmpty)
          'seed_snapshots': seedSnapshots.map((s) => s.toJson()).toList(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  RecordedSpin copyWith({
    String? spinId,
    int? spinIndex,
    DateTime? timestamp,
    double? betAmount,
    double? winAmount,
    List<List<int>>? reelGrid,
    StageTrace? trace,
    List<SeedSnapshot>? seedSnapshots,
    Map<String, dynamic>? metadata,
  }) =>
      RecordedSpin(
        spinId: spinId ?? this.spinId,
        spinIndex: spinIndex ?? this.spinIndex,
        timestamp: timestamp ?? this.timestamp,
        betAmount: betAmount ?? this.betAmount,
        winAmount: winAmount ?? this.winAmount,
        reelGrid: reelGrid ?? this.reelGrid,
        trace: trace ?? this.trace,
        seedSnapshots: seedSnapshots ?? this.seedSnapshots,
        metadata: metadata ?? this.metadata,
      );
}

/// Snapshot of RNG seed state for deterministic replay
class SeedSnapshot {
  final int tick;
  final int containerId;
  final String containerName;
  final String seedBefore;
  final String seedAfter;
  final int selectedChildId;
  final double pitchOffset;
  final double volumeOffset;

  const SeedSnapshot({
    required this.tick,
    required this.containerId,
    this.containerName = '',
    required this.seedBefore,
    required this.seedAfter,
    required this.selectedChildId,
    this.pitchOffset = 0.0,
    this.volumeOffset = 0.0,
  });

  int get seedBeforeInt => int.tryParse(seedBefore, radix: 16) ?? 0;
  int get seedAfterInt => int.tryParse(seedAfter, radix: 16) ?? 0;

  factory SeedSnapshot.fromJson(Map<String, dynamic> json) => SeedSnapshot(
        tick: json['tick'] as int? ?? 0,
        containerId: json['container_id'] as int? ?? 0,
        containerName: json['container_name'] as String? ?? '',
        seedBefore: json['seed_before'] as String? ?? '0',
        seedAfter: json['seed_after'] as String? ?? '0',
        selectedChildId: json['selected_child_id'] as int? ?? 0,
        pitchOffset: (json['pitch_offset'] as num?)?.toDouble() ?? 0.0,
        volumeOffset: (json['volume_offset'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'tick': tick,
        'container_id': containerId,
        if (containerName.isNotEmpty) 'container_name': containerName,
        'seed_before': seedBefore,
        'seed_after': seedAfter,
        'selected_child_id': selectedChildId,
        if (pitchOffset != 0.0) 'pitch_offset': pitchOffset,
        if (volumeOffset != 0.0) 'volume_offset': volumeOffset,
      };
}

/// Audio event recorded during session
class RecordedAudioEvent {
  final String eventId;
  final String stageName;
  final double timestampMs;
  final String? audioPath;
  final int? voiceId;
  final int busId;
  final double volume;
  final double pan;
  final int latencyUs;
  final Map<String, dynamic> parameters;

  const RecordedAudioEvent({
    required this.eventId,
    required this.stageName,
    required this.timestampMs,
    this.audioPath,
    this.voiceId,
    this.busId = 0,
    this.volume = 1.0,
    this.pan = 0.0,
    this.latencyUs = 0,
    this.parameters = const {},
  });

  factory RecordedAudioEvent.fromJson(Map<String, dynamic> json) =>
      RecordedAudioEvent(
        eventId: json['event_id'] as String? ?? '',
        stageName: json['stage_name'] as String? ?? '',
        timestampMs: (json['timestamp_ms'] as num?)?.toDouble() ?? 0.0,
        audioPath: json['audio_path'] as String?,
        voiceId: json['voice_id'] as int?,
        busId: json['bus_id'] as int? ?? 0,
        volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
        pan: (json['pan'] as num?)?.toDouble() ?? 0.0,
        latencyUs: json['latency_us'] as int? ?? 0,
        parameters: (json['parameters'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'stage_name': stageName,
        'timestamp_ms': timestampMs,
        if (audioPath != null) 'audio_path': audioPath,
        if (voiceId != null) 'voice_id': voiceId,
        'bus_id': busId,
        'volume': volume,
        'pan': pan,
        if (latencyUs > 0) 'latency_us': latencyUs,
        if (parameters.isNotEmpty) 'parameters': parameters,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// FULL SESSION
// ═══════════════════════════════════════════════════════════════════════════

/// Complete recorded session containing multiple spins
class RecordedSession {
  static const int schemaVersion = 1;

  final String sessionId;
  final String gameId;
  final String gameName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<RecordedSpin> spins;
  final List<RecordedAudioEvent> audioEvents;
  final SessionConfig config;
  final SessionStatistics statistics;
  final Map<String, dynamic> metadata;

  const RecordedSession({
    required this.sessionId,
    required this.gameId,
    this.gameName = '',
    required this.startedAt,
    this.endedAt,
    this.spins = const [],
    this.audioEvents = const [],
    required this.config,
    required this.statistics,
    this.metadata = const {},
  });

  int get spinCount => spins.length;

  Duration get duration => endedAt != null
      ? endedAt!.difference(startedAt)
      : DateTime.now().difference(startedAt);

  double get totalBet => spins.fold(0.0, (sum, s) => sum + s.betAmount);

  double get totalWin => spins.fold(0.0, (sum, s) => sum + s.winAmount);

  double get rtp => totalBet > 0 ? (totalWin / totalBet) * 100 : 0.0;

  int get winCount => spins.where((s) => s.isWin).length;

  double get hitRate => spinCount > 0 ? winCount / spinCount : 0.0;

  factory RecordedSession.fromJson(Map<String, dynamic> json) => RecordedSession(
        sessionId: json['session_id'] as String? ?? '',
        gameId: json['game_id'] as String? ?? '',
        gameName: json['game_name'] as String? ?? '',
        startedAt: json['started_at'] != null
            ? DateTime.parse(json['started_at'] as String)
            : DateTime.now(),
        endedAt: json['ended_at'] != null
            ? DateTime.parse(json['ended_at'] as String)
            : null,
        spins: (json['spins'] as List<dynamic>?)
                ?.map((e) => RecordedSpin.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        audioEvents: (json['audio_events'] as List<dynamic>?)
                ?.map((e) =>
                    RecordedAudioEvent.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        config: SessionConfig.fromJson(
            json['config'] as Map<String, dynamic>? ?? {}),
        statistics: SessionStatistics.fromJson(
            json['statistics'] as Map<String, dynamic>? ?? {}),
        metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'session_id': sessionId,
        'game_id': gameId,
        if (gameName.isNotEmpty) 'game_name': gameName,
        'started_at': startedAt.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
        'spins': spins.map((s) => s.toJson()).toList(),
        if (audioEvents.isNotEmpty)
          'audio_events': audioEvents.map((e) => e.toJson()).toList(),
        'config': config.toJson(),
        'statistics': statistics.toJson(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  String toJsonString({bool pretty = false}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(toJson());
  }

  static RecordedSession fromJsonString(String jsonStr) {
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return RecordedSession.fromJson(json);
  }

  RecordedSession copyWith({
    String? sessionId,
    String? gameId,
    String? gameName,
    DateTime? startedAt,
    DateTime? endedAt,
    List<RecordedSpin>? spins,
    List<RecordedAudioEvent>? audioEvents,
    SessionConfig? config,
    SessionStatistics? statistics,
    Map<String, dynamic>? metadata,
  }) =>
      RecordedSession(
        sessionId: sessionId ?? this.sessionId,
        gameId: gameId ?? this.gameId,
        gameName: gameName ?? this.gameName,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        spins: spins ?? this.spins,
        audioEvents: audioEvents ?? this.audioEvents,
        config: config ?? this.config,
        statistics: statistics ?? this.statistics,
        metadata: metadata ?? this.metadata,
      );
}

/// Session configuration at recording time
class SessionConfig {
  final int reels;
  final int rows;
  final String volatility;
  final TimingProfile timingProfile;
  final double baseBet;
  final bool turboMode;
  final bool deterministicMode;
  final Map<String, dynamic> gameConfig;

  const SessionConfig({
    this.reels = 5,
    this.rows = 3,
    this.volatility = 'medium',
    this.timingProfile = TimingProfile.normal,
    this.baseBet = 1.0,
    this.turboMode = false,
    this.deterministicMode = true,
    this.gameConfig = const {},
  });

  factory SessionConfig.fromJson(Map<String, dynamic> json) => SessionConfig(
        reels: json['reels'] as int? ?? 5,
        rows: json['rows'] as int? ?? 3,
        volatility: json['volatility'] as String? ?? 'medium',
        timingProfile:
            TimingProfile.fromJson(json['timing_profile']) ?? TimingProfile.normal,
        baseBet: (json['base_bet'] as num?)?.toDouble() ?? 1.0,
        turboMode: json['turbo_mode'] as bool? ?? false,
        deterministicMode: json['deterministic_mode'] as bool? ?? true,
        gameConfig: (json['game_config'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'reels': reels,
        'rows': rows,
        'volatility': volatility,
        'timing_profile': timingProfile.toJson(),
        'base_bet': baseBet,
        'turbo_mode': turboMode,
        'deterministic_mode': deterministicMode,
        if (gameConfig.isNotEmpty) 'game_config': gameConfig,
      };
}

/// Statistics computed from session
class SessionStatistics {
  final int totalSpins;
  final double totalBet;
  final double totalWin;
  final double maxWin;
  final double maxWinRatio;
  final int featureCount;
  final int jackpotCount;
  final int bigWinCount;
  final int megaWinCount;
  final int epicWinCount;
  final double avgSpinDurationMs;
  final int totalAudioEvents;
  final double avgLatencyUs;

  const SessionStatistics({
    this.totalSpins = 0,
    this.totalBet = 0.0,
    this.totalWin = 0.0,
    this.maxWin = 0.0,
    this.maxWinRatio = 0.0,
    this.featureCount = 0,
    this.jackpotCount = 0,
    this.bigWinCount = 0,
    this.megaWinCount = 0,
    this.epicWinCount = 0,
    this.avgSpinDurationMs = 0.0,
    this.totalAudioEvents = 0,
    this.avgLatencyUs = 0.0,
  });

  double get rtp => totalBet > 0 ? (totalWin / totalBet) * 100 : 0.0;

  double get hitRate => totalSpins > 0 ? (totalWin > 0 ? 1.0 : 0.0) : 0.0;

  factory SessionStatistics.fromJson(Map<String, dynamic> json) =>
      SessionStatistics(
        totalSpins: json['total_spins'] as int? ?? 0,
        totalBet: (json['total_bet'] as num?)?.toDouble() ?? 0.0,
        totalWin: (json['total_win'] as num?)?.toDouble() ?? 0.0,
        maxWin: (json['max_win'] as num?)?.toDouble() ?? 0.0,
        maxWinRatio: (json['max_win_ratio'] as num?)?.toDouble() ?? 0.0,
        featureCount: json['feature_count'] as int? ?? 0,
        jackpotCount: json['jackpot_count'] as int? ?? 0,
        bigWinCount: json['big_win_count'] as int? ?? 0,
        megaWinCount: json['mega_win_count'] as int? ?? 0,
        epicWinCount: json['epic_win_count'] as int? ?? 0,
        avgSpinDurationMs:
            (json['avg_spin_duration_ms'] as num?)?.toDouble() ?? 0.0,
        totalAudioEvents: json['total_audio_events'] as int? ?? 0,
        avgLatencyUs: (json['avg_latency_us'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'total_spins': totalSpins,
        'total_bet': totalBet,
        'total_win': totalWin,
        'max_win': maxWin,
        'max_win_ratio': maxWinRatio,
        'feature_count': featureCount,
        'jackpot_count': jackpotCount,
        'big_win_count': bigWinCount,
        'mega_win_count': megaWinCount,
        'epic_win_count': epicWinCount,
        'avg_spin_duration_ms': avgSpinDurationMs,
        'total_audio_events': totalAudioEvents,
        'avg_latency_us': avgLatencyUs,
      };

  /// Compute statistics from a list of spins
  factory SessionStatistics.compute(
    List<RecordedSpin> spins,
    List<RecordedAudioEvent> audioEvents,
  ) {
    if (spins.isEmpty) {
      return const SessionStatistics();
    }

    double totalBet = 0.0;
    double totalWin = 0.0;
    double maxWin = 0.0;
    double maxWinRatio = 0.0;
    int featureCount = 0;
    int jackpotCount = 0;
    int bigWinCount = 0;
    int megaWinCount = 0;
    int epicWinCount = 0;
    double totalDurationMs = 0.0;

    for (final spin in spins) {
      totalBet += spin.betAmount;
      totalWin += spin.winAmount;
      if (spin.winAmount > maxWin) maxWin = spin.winAmount;
      if (spin.winRatio > maxWinRatio) maxWinRatio = spin.winRatio;
      if (spin.hasFeature) featureCount++;
      if (spin.hasJackpot) jackpotCount++;

      final tier = spin.trace.maxBigWinTier;
      if (tier != null) {
        if (tier.minRatio >= 100) {
          epicWinCount++;
        } else if (tier.minRatio >= 30) {
          megaWinCount++;
        } else if (tier.minRatio >= 5) {
          bigWinCount++;
        }
      }

      totalDurationMs += spin.trace.durationMs;
    }

    double totalLatencyUs = 0.0;
    for (final event in audioEvents) {
      totalLatencyUs += event.latencyUs;
    }

    return SessionStatistics(
      totalSpins: spins.length,
      totalBet: totalBet,
      totalWin: totalWin,
      maxWin: maxWin,
      maxWinRatio: maxWinRatio,
      featureCount: featureCount,
      jackpotCount: jackpotCount,
      bigWinCount: bigWinCount,
      megaWinCount: megaWinCount,
      epicWinCount: epicWinCount,
      avgSpinDurationMs: totalDurationMs / spins.length,
      totalAudioEvents: audioEvents.length,
      avgLatencyUs:
          audioEvents.isNotEmpty ? totalLatencyUs / audioEvents.length : 0.0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REPLAY POSITION
// ═══════════════════════════════════════════════════════════════════════════

/// Current position in replay
class ReplayPosition {
  final int spinIndex;
  final int stageIndex;
  final double timeMs;
  final double progress;

  const ReplayPosition({
    this.spinIndex = 0,
    this.stageIndex = 0,
    this.timeMs = 0.0,
    this.progress = 0.0,
  });

  factory ReplayPosition.fromJson(Map<String, dynamic> json) => ReplayPosition(
        spinIndex: json['spin_index'] as int? ?? 0,
        stageIndex: json['stage_index'] as int? ?? 0,
        timeMs: (json['time_ms'] as num?)?.toDouble() ?? 0.0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'spin_index': spinIndex,
        'stage_index': stageIndex,
        'time_ms': timeMs,
        'progress': progress,
      };

  ReplayPosition copyWith({
    int? spinIndex,
    int? stageIndex,
    double? timeMs,
    double? progress,
  }) =>
      ReplayPosition(
        spinIndex: spinIndex ?? this.spinIndex,
        stageIndex: stageIndex ?? this.stageIndex,
        timeMs: timeMs ?? this.timeMs,
        progress: progress ?? this.progress,
      );

  bool get isAtStart => spinIndex == 0 && stageIndex == 0 && timeMs == 0.0;
}

/// Session summary for list display
class SessionSummary {
  final String sessionId;
  final String gameId;
  final String gameName;
  final DateTime startedAt;
  final int spinCount;
  final double totalWin;
  final double rtp;
  final Duration duration;
  final bool hasFeature;
  final bool hasJackpot;

  const SessionSummary({
    required this.sessionId,
    required this.gameId,
    this.gameName = '',
    required this.startedAt,
    required this.spinCount,
    required this.totalWin,
    required this.rtp,
    required this.duration,
    this.hasFeature = false,
    this.hasJackpot = false,
  });

  factory SessionSummary.fromSession(RecordedSession session) => SessionSummary(
        sessionId: session.sessionId,
        gameId: session.gameId,
        gameName: session.gameName,
        startedAt: session.startedAt,
        spinCount: session.spinCount,
        totalWin: session.totalWin,
        rtp: session.rtp,
        duration: session.duration,
        hasFeature: session.spins.any((s) => s.hasFeature),
        hasJackpot: session.spins.any((s) => s.hasJackpot),
      );

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
        sessionId: json['session_id'] as String? ?? '',
        gameId: json['game_id'] as String? ?? '',
        gameName: json['game_name'] as String? ?? '',
        startedAt: json['started_at'] != null
            ? DateTime.parse(json['started_at'] as String)
            : DateTime.now(),
        spinCount: json['spin_count'] as int? ?? 0,
        totalWin: (json['total_win'] as num?)?.toDouble() ?? 0.0,
        rtp: (json['rtp'] as num?)?.toDouble() ?? 0.0,
        duration: Duration(milliseconds: json['duration_ms'] as int? ?? 0),
        hasFeature: json['has_feature'] as bool? ?? false,
        hasJackpot: json['has_jackpot'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'game_id': gameId,
        if (gameName.isNotEmpty) 'game_name': gameName,
        'started_at': startedAt.toIso8601String(),
        'spin_count': spinCount,
        'total_win': totalWin,
        'rtp': rtp,
        'duration_ms': duration.inMilliseconds,
        'has_feature': hasFeature,
        'has_jackpot': hasJackpot,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// VALIDATION
// ═══════════════════════════════════════════════════════════════════════════

/// Result of replay validation
class ReplayValidationResult {
  final bool isValid;
  final List<ReplayValidationIssue> issues;
  final int matchedStages;
  final int totalStages;
  final int matchedSeeds;
  final int totalSeeds;

  const ReplayValidationResult({
    required this.isValid,
    this.issues = const [],
    this.matchedStages = 0,
    this.totalStages = 0,
    this.matchedSeeds = 0,
    this.totalSeeds = 0,
  });

  double get stageMatchRate =>
      totalStages > 0 ? matchedStages / totalStages : 0.0;

  double get seedMatchRate => totalSeeds > 0 ? matchedSeeds / totalSeeds : 0.0;

  factory ReplayValidationResult.fromJson(Map<String, dynamic> json) =>
      ReplayValidationResult(
        isValid: json['is_valid'] as bool? ?? false,
        issues: (json['issues'] as List<dynamic>?)
                ?.map((e) =>
                    ReplayValidationIssue.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        matchedStages: json['matched_stages'] as int? ?? 0,
        totalStages: json['total_stages'] as int? ?? 0,
        matchedSeeds: json['matched_seeds'] as int? ?? 0,
        totalSeeds: json['total_seeds'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'is_valid': isValid,
        'issues': issues.map((i) => i.toJson()).toList(),
        'matched_stages': matchedStages,
        'total_stages': totalStages,
        'matched_seeds': matchedSeeds,
        'total_seeds': totalSeeds,
      };
}

/// A single validation issue
class ReplayValidationIssue {
  final ReplayValidationSeverity severity;
  final String message;
  final int? spinIndex;
  final int? stageIndex;
  final String? expected;
  final String? actual;

  const ReplayValidationIssue({
    required this.severity,
    required this.message,
    this.spinIndex,
    this.stageIndex,
    this.expected,
    this.actual,
  });

  factory ReplayValidationIssue.fromJson(Map<String, dynamic> json) =>
      ReplayValidationIssue(
        severity: ReplayValidationSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => ReplayValidationSeverity.warning,
        ),
        message: json['message'] as String? ?? '',
        spinIndex: json['spin_index'] as int?,
        stageIndex: json['stage_index'] as int?,
        expected: json['expected'] as String?,
        actual: json['actual'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'severity': severity.name,
        'message': message,
        if (spinIndex != null) 'spin_index': spinIndex,
        if (stageIndex != null) 'stage_index': stageIndex,
        if (expected != null) 'expected': expected,
        if (actual != null) 'actual': actual,
      };
}

/// Severity of validation issue
enum ReplayValidationSeverity {
  info,
  warning,
  error;

  String get displayName => switch (this) {
        info => 'Info',
        warning => 'Warning',
        error => 'Error',
      };
}
