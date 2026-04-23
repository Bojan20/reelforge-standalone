/// Batch Simulation Service — T2.3 + T2.4
///
/// Dart-side wrapper for the rf-ab-sim Rust engine.
/// Provides:
/// - Start/cancel async simulations
/// - Poll progress
/// - Parse BatchSimResult from JSON
/// - Notify listeners when simulation completes

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DATA MODELS (mirrors Rust BatchSimResult)
// ═══════════════════════════════════════════════════════════════════════════════

/// Frequency stats for one audio event
class EventFrequency {
  final int count;
  final double avgPer1000Spins;
  final int peakConcurrent;
  final int minGapMs;
  final int maxGapMs;
  final double gapStddevMs;

  const EventFrequency({
    required this.count,
    required this.avgPer1000Spins,
    this.peakConcurrent = 1,
    this.minGapMs = 0,
    this.maxGapMs = 0,
    this.gapStddevMs = 0.0,
  });

  factory EventFrequency.fromJson(Map<String, dynamic> j) => EventFrequency(
    count: (j['count'] as int?) ?? 0,
    avgPer1000Spins: (j['avg_per_1000_spins'] as num?)?.toDouble() ?? 0.0,
    peakConcurrent: (j['peak_concurrent'] as int?) ?? 1,
    minGapMs: (j['min_gap_ms'] as int?) ?? 0,
    maxGapMs: (j['max_gap_ms'] as int?) ?? 0,
    gapStddevMs: (j['gap_stddev_ms'] as num?)?.toDouble() ?? 0.0,
  );
}

/// Dry spell analysis
class DrySpellAnalysis {
  final int maxDrySpins;
  final double avgDrySpins;
  final double deadSpinPct;
  final Map<int, int> histogram;

  const DrySpellAnalysis({
    this.maxDrySpins = 0,
    this.avgDrySpins = 0.0,
    this.deadSpinPct = 0.0,
    this.histogram = const {},
  });

  factory DrySpellAnalysis.fromJson(Map<String, dynamic> j) {
    final histJson = j['dry_spell_histogram'] as Map<String, dynamic>? ?? {};
    return DrySpellAnalysis(
      maxDrySpins: (j['max_dry_spins'] as int?) ?? 0,
      avgDrySpins: (j['avg_dry_spins'] as num?)?.toDouble() ?? 0.0,
      deadSpinPct: (j['dead_spin_pct'] as num?)?.toDouble() ?? 0.0,
      histogram: histJson.map((k, v) => MapEntry(int.tryParse(k) ?? 0, (v as num).toInt())),
    );
  }
}

/// Voice budget prediction
class VoiceBudgetInfo {
  final int peakVoices;
  final int voiceBudget;
  final double budgetExceededFraction;
  final int budgetExceededCount;
  final double avgUtilization;

  const VoiceBudgetInfo({
    this.peakVoices = 0,
    this.voiceBudget = 48,
    this.budgetExceededFraction = 0.0,
    this.budgetExceededCount = 0,
    this.avgUtilization = 0.0,
  });

  factory VoiceBudgetInfo.fromJson(Map<String, dynamic> j) => VoiceBudgetInfo(
    peakVoices: (j['peak_voices'] as int?) ?? 0,
    voiceBudget: (j['voice_budget'] as int?) ?? 48,
    budgetExceededFraction:
        (j['budget_exceeded_fraction'] as num?)?.toDouble() ?? 0.0,
    budgetExceededCount: (j['budget_exceeded_count'] as int?) ?? 0,
    avgUtilization: (j['avg_utilization'] as num?)?.toDouble() ?? 0.0,
  );

  bool get isOverBudget => peakVoices > voiceBudget;
  double get utilizationPct => voiceBudget > 0 ? peakVoices / voiceBudget : 0.0;
}

/// Win distribution per tier
class WinDistribution {
  final Map<String, int> perTierCount;
  final Map<String, double> perTierRtpContribution;
  final int totalWins;
  final int totalLosses;
  final double actualRtp;

  const WinDistribution({
    this.perTierCount = const {},
    this.perTierRtpContribution = const {},
    this.totalWins = 0,
    this.totalLosses = 0,
    this.actualRtp = 0.0,
  });

  factory WinDistribution.fromJson(Map<String, dynamic> j) {
    final countJson = j['per_tier_count'] as Map<String, dynamic>? ?? {};
    final rtpJson = j['per_tier_rtp_contribution'] as Map<String, dynamic>? ?? {};
    return WinDistribution(
      perTierCount: countJson.map((k, v) => MapEntry(k, (v as num).toInt())),
      perTierRtpContribution: rtpJson.map((k, v) => MapEntry(k, (v as num).toDouble())),
      totalWins: (j['total_wins'] as int?) ?? 0,
      totalLosses: (j['total_losses'] as int?) ?? 0,
      actualRtp: (j['actual_rtp'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Timeline sample (point-in-time snapshot)
class TimelineSample {
  final int spinNumber;
  final List<String> events;
  final int activeVoices;
  final double cumulativeRtp;
  final int consecutiveDry;

  const TimelineSample({
    required this.spinNumber,
    this.events = const [],
    this.activeVoices = 0,
    this.cumulativeRtp = 0.0,
    this.consecutiveDry = 0,
  });

  factory TimelineSample.fromJson(Map<String, dynamic> j) => TimelineSample(
    spinNumber: (j['spin_number'] as int?) ?? 0,
    events: ((j['events'] as List?) ?? []).cast<String>(),
    activeVoices: (j['active_voices'] as int?) ?? 0,
    cumulativeRtp: (j['cumulative_rtp'] as num?)?.toDouble() ?? 0.0,
    consecutiveDry: (j['consecutive_dry'] as int?) ?? 0,
  );
}

/// Complete batch simulation result
class BatchSimResult {
  final double actualRtp;
  final double targetRtp;
  final double rtpDelta;
  final int spinCount;
  final int simDurationMs;
  final Map<String, EventFrequency> eventFrequencyMap;
  final VoiceBudgetInfo voiceBudget;
  final DrySpellAnalysis drySpellAnalysis;
  final WinDistribution winDistribution;
  final List<TimelineSample> timelineSamples;
  final List<String> warnings;

  const BatchSimResult({
    required this.actualRtp,
    required this.targetRtp,
    required this.rtpDelta,
    required this.spinCount,
    this.simDurationMs = 0,
    this.eventFrequencyMap = const {},
    required this.voiceBudget,
    required this.drySpellAnalysis,
    required this.winDistribution,
    this.timelineSamples = const [],
    this.warnings = const [],
  });

  factory BatchSimResult.fromJson(Map<String, dynamic> j) {
    final freqJson = j['event_frequency_map'] as Map<String, dynamic>? ?? {};
    final samplesJson = j['timeline_samples'] as List? ?? [];
    return BatchSimResult(
      actualRtp: (j['actual_rtp'] as num?)?.toDouble() ?? 0.0,
      targetRtp: (j['target_rtp'] as num?)?.toDouble() ?? 0.0,
      rtpDelta: (j['rtp_delta'] as num?)?.toDouble() ?? 0.0,
      spinCount: (j['spin_count'] as int?) ?? 0,
      simDurationMs: (j['sim_duration_ms'] as int?) ?? 0,
      eventFrequencyMap: freqJson.map(
        (k, v) => MapEntry(k, EventFrequency.fromJson(v as Map<String, dynamic>)),
      ),
      voiceBudget: VoiceBudgetInfo.fromJson(
        j['voice_budget'] as Map<String, dynamic>? ?? {},
      ),
      drySpellAnalysis: DrySpellAnalysis.fromJson(
        j['dry_spell_analysis'] as Map<String, dynamic>? ?? {},
      ),
      winDistribution: WinDistribution.fromJson(
        j['win_distribution'] as Map<String, dynamic>? ?? {},
      ),
      timelineSamples: samplesJson
          .map((e) => TimelineSample.fromJson(e as Map<String, dynamic>))
          .toList(),
      warnings: ((j['warnings'] as List?) ?? []).cast<String>(),
    );
  }

  bool get hasWarnings => warnings.isNotEmpty;
}

// ═══════════════════════════════════════════════════════════════════════════════
// TASK HANDLE
// ═══════════════════════════════════════════════════════════════════════════════

/// A running (or completed) batch simulation task
class BatchSimTask {
  final int taskId;
  final int spinCount;
  final DateTime startTime;

  BatchSimTask._({
    required this.taskId,
    required this.spinCount,
    required this.startTime,
  });

  /// Poll current progress (0.0–1.0). Returns -1.0 if task is invalid.
  double get progress {
    return NativeFFI.instance.slotLabBatchSimProgress(taskId);
  }

  bool get isDone => progress >= 1.0;

  /// Try to consume the result. Returns null if not ready.
  /// Once consumed, the task is cleaned up from Rust side.
  BatchSimResult? consumeResult() {
    final json = NativeFFI.instance.slotLabBatchSimResult(taskId);
    if (json == null) return null;
    try {
      return BatchSimResult.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Cancel the simulation
  void cancel() {
    NativeFFI.instance.slotLabBatchSimCancel(taskId);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BATCH SIM CONFIG BUILDER
// ═══════════════════════════════════════════════════════════════════════════════

/// Fluent builder for BatchSimConfig JSON
class BatchSimConfigBuilder {
  int _spinCount = 100000;
  int _voiceBudget = 48;
  int _threads = 0;
  int? _seed;
  int _timelineSampleRate = 1000;
  double _targetRtp = 0.0;
  final List<Map<String, dynamic>> _audioEvents = [];

  BatchSimConfigBuilder spinCount(int count) {
    _spinCount = count;
    return this;
  }

  BatchSimConfigBuilder voiceBudget(int budget) {
    _voiceBudget = budget;
    return this;
  }

  BatchSimConfigBuilder threads(int n) {
    _threads = n;
    return this;
  }

  BatchSimConfigBuilder deterministic(int seed) {
    _seed = seed;
    return this;
  }

  BatchSimConfigBuilder targetRtp(double rtp) {
    _targetRtp = rtp;
    return this;
  }

  BatchSimConfigBuilder addEvent(
    String name, {
    int voiceCount = 2,
    int durationMs = 1000,
    bool canOverlap = true,
    int priority = 5,
  }) {
    _audioEvents.add({
      'event_name': name,
      'voice_count': voiceCount,
      'duration_ms': durationMs,
      'can_overlap': canOverlap,
      'priority': priority,
    });
    return this;
  }

  String build(String gameModelJson) {
    return jsonEncode({
      'game_model': jsonDecode(gameModelJson),
      'spin_count': _spinCount,
      'voice_budget': _voiceBudget,
      'threads': _threads,
      if (_seed != null) 'seed': _seed,
      'timeline_sample_rate': _timelineSampleRate,
      'target_rtp': _targetRtp,
      'audio_events': _audioEvents,
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Batch Simulation Service
class BatchSimService extends ChangeNotifier {
  BatchSimTask? _currentTask;
  BatchSimTask? get currentTask => _currentTask;

  BatchSimResult? _lastResult;
  BatchSimResult? get lastResult => _lastResult;

  bool get isRunning => _currentTask != null && !_currentTask!.isDone;

  String? _lastError;
  String? get lastError => _lastError;

  Timer? _pollTimer;

  /// Start a simulation with the given config JSON.
  /// Returns false if another simulation is already running.
  bool startSimulation(String configJson) {
    if (isRunning) return false;

    final taskId = NativeFFI.instance.slotLabBatchSimStart(configJson);
    if (taskId == 0) {
      _lastError = 'Failed to start simulation — invalid config';
      notifyListeners();
      return false;
    }

    _currentTask = BatchSimTask._(
      taskId: taskId,
      spinCount: _extractSpinCount(configJson),
      startTime: DateTime.now(),
    );
    _lastError = null;
    notifyListeners();

    // Start polling
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _poll();
    });

    return true;
  }

  /// Cancel the current simulation
  void cancelSimulation() {
    _currentTask?.cancel();
    _pollTimer?.cancel();
    _pollTimer = null;
    _currentTask = null;
    notifyListeners();
  }

  /// Clear the last result
  void clearResult() {
    _lastResult = null;
    notifyListeners();
  }

  void _poll() {
    final task = _currentTask;
    if (task == null) {
      _pollTimer?.cancel();
      return;
    }

    final progress = task.progress;
    if (progress >= 1.0) {
      final result = task.consumeResult();
      if (result != null) {
        _lastResult = result;
        _currentTask = null;
        _pollTimer?.cancel();
        _pollTimer = null;
        notifyListeners();
      }
    } else {
      // Still running — just notify for progress update
      notifyListeners();
    }
  }

  int _extractSpinCount(String configJson) {
    try {
      final j = jsonDecode(configJson) as Map<String, dynamic>;
      return (j['spin_count'] as int?) ?? 100000;
    } catch (_) {
      return 100000;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _currentTask?.cancel();
    super.dispose();
  }
}
