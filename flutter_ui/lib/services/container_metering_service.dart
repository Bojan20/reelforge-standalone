/// Container Real-Time Metering Service
///
/// Provides real-time performance metrics for container evaluation:
/// - Blend: RTPC evaluation time, crossfade calculations
/// - Random: Selection time, weight calculations
/// - Sequence: Tick timing, step transitions
///
/// Used by container panels for performance visualization.

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Performance metrics for a single container evaluation
class ContainerEvaluationMetrics {
  final int containerId;
  final ContainerType type;
  final DateTime timestamp;
  final int evaluationTimeMicros;
  final Map<String, dynamic> specificMetrics;

  ContainerEvaluationMetrics({
    required this.containerId,
    required this.type,
    required this.timestamp,
    required this.evaluationTimeMicros,
    required this.specificMetrics,
  });

  double get evaluationTimeMs => evaluationTimeMicros / 1000.0;
}

enum ContainerType {
  blend,
  random,
  sequence,
}

/// Aggregated statistics for a container over time
class ContainerMeteringStats {
  final int containerId;
  final ContainerType type;

  // Evaluation timing
  double avgEvaluationMs = 0.0;
  double minEvaluationMs = double.infinity;
  double maxEvaluationMs = 0.0;
  int evaluationCount = 0;

  // Rolling window (last 100 samples)
  final List<double> recentEvaluations = [];
  static const int _maxSamples = 100;

  // Type-specific metrics
  Map<String, dynamic> typeSpecificStats = {};

  ContainerMeteringStats({
    required this.containerId,
    required this.type,
  });

  void recordEvaluation(ContainerEvaluationMetrics metrics) {
    evaluationCount++;

    final timeMs = metrics.evaluationTimeMs;
    minEvaluationMs = minEvaluationMs > timeMs ? timeMs : minEvaluationMs;
    maxEvaluationMs = maxEvaluationMs < timeMs ? timeMs : maxEvaluationMs;

    // Update rolling average
    recentEvaluations.add(timeMs);
    if (recentEvaluations.length > _maxSamples) {
      recentEvaluations.removeAt(0);
    }

    avgEvaluationMs = recentEvaluations.fold<double>(0.0, (sum, val) => sum + val) / recentEvaluations.length;

    // Update type-specific stats
    _updateTypeSpecificStats(metrics);
  }

  void _updateTypeSpecificStats(ContainerEvaluationMetrics metrics) {
    switch (type) {
      case ContainerType.blend:
        _updateBlendStats(metrics);
        break;
      case ContainerType.random:
        _updateRandomStats(metrics);
        break;
      case ContainerType.sequence:
        _updateSequenceStats(metrics);
        break;
    }
  }

  void _updateBlendStats(ContainerEvaluationMetrics metrics) {
    // Track RTPC value distribution
    final rtpcValue = metrics.specificMetrics['rtpc_value'] as double?;
    if (rtpcValue != null) {
      final distribution = typeSpecificStats['rtpc_distribution'] as List<double>? ?? [];
      distribution.add(rtpcValue);
      if (distribution.length > _maxSamples) {
        distribution.removeAt(0);
      }
      typeSpecificStats['rtpc_distribution'] = distribution;
    }

    // Track active children count
    final activeCount = metrics.specificMetrics['active_children'] as int?;
    if (activeCount != null) {
      typeSpecificStats['avg_active_children'] =
        ((typeSpecificStats['avg_active_children'] as double? ?? 0.0) * (evaluationCount - 1) + activeCount) / evaluationCount;
    }
  }

  void _updateRandomStats(ContainerEvaluationMetrics metrics) {
    // Track selection distribution
    final selectedId = metrics.specificMetrics['selected_child_id'] as int?;
    if (selectedId != null) {
      final selectionCounts = typeSpecificStats['selection_counts'] as Map<int, int>? ?? {};
      selectionCounts[selectedId] = (selectionCounts[selectedId] ?? 0) + 1;
      typeSpecificStats['selection_counts'] = selectionCounts;
    }

    // Track variance from expected weight
    final weightVariance = metrics.specificMetrics['weight_variance'] as double?;
    if (weightVariance != null) {
      final variances = typeSpecificStats['weight_variances'] as List<double>? ?? [];
      variances.add(weightVariance);
      if (variances.length > _maxSamples) {
        variances.removeAt(0);
      }
      typeSpecificStats['weight_variances'] = variances;
    }
  }

  void _updateSequenceStats(ContainerEvaluationMetrics metrics) {
    // Track step duration accuracy
    final stepDuration = metrics.specificMetrics['step_duration_ms'] as double?;
    final expectedDuration = metrics.specificMetrics['expected_duration_ms'] as double?;

    if (stepDuration != null && expectedDuration != null) {
      final deviation = (stepDuration - expectedDuration).abs();
      final deviations = typeSpecificStats['timing_deviations'] as List<double>? ?? [];
      deviations.add(deviation);
      if (deviations.length > _maxSamples) {
        deviations.removeAt(0);
      }
      typeSpecificStats['timing_deviations'] = deviations;
    }

    // Track loop completions
    final loopCompleted = metrics.specificMetrics['loop_completed'] as bool?;
    if (loopCompleted == true) {
      typeSpecificStats['loop_count'] = (typeSpecificStats['loop_count'] as int? ?? 0) + 1;
    }
  }

  double get p50Latency {
    if (recentEvaluations.isEmpty) return 0.0;
    final sorted = List<double>.from(recentEvaluations)..sort();
    return sorted[sorted.length ~/ 2];
  }

  double get p95Latency {
    if (recentEvaluations.isEmpty) return 0.0;
    final sorted = List<double>.from(recentEvaluations)..sort();
    final index = (sorted.length * 0.95).floor();
    return sorted[index < sorted.length ? index : sorted.length - 1];
  }

  double get p99Latency {
    if (recentEvaluations.isEmpty) return 0.0;
    final sorted = List<double>.from(recentEvaluations)..sort();
    final index = (sorted.length * 0.99).floor();
    return sorted[index < sorted.length ? index : sorted.length - 1];
  }
}

/// Singleton service for tracking container performance metrics
class ContainerMeteringService extends ChangeNotifier {
  static final ContainerMeteringService instance = ContainerMeteringService._();

  ContainerMeteringService._();

  final Map<int, ContainerMeteringStats> _stats = {};
  final StreamController<ContainerEvaluationMetrics> _metricsStream =
    StreamController<ContainerEvaluationMetrics>.broadcast();

  Stream<ContainerEvaluationMetrics> get metricsStream => _metricsStream.stream;

  /// Record a container evaluation
  void recordEvaluation(ContainerEvaluationMetrics metrics) {
    final stats = _stats.putIfAbsent(
      metrics.containerId,
      () => ContainerMeteringStats(
        containerId: metrics.containerId,
        type: metrics.type,
      ),
    );

    stats.recordEvaluation(metrics);
    _metricsStream.add(metrics);
    notifyListeners();
  }

  /// Get stats for a specific container
  ContainerMeteringStats? getStats(int containerId) => _stats[containerId];

  /// Get all tracked containers
  List<int> get trackedContainers => _stats.keys.toList();

  /// Clear stats for a container
  void clearStats(int containerId) {
    _stats.remove(containerId);
    notifyListeners();
  }

  /// Clear all stats
  void clearAll() {
    _stats.clear();
    notifyListeners();
  }

  /// Get summary statistics across all containers
  Map<String, dynamic> getSummary() {
    if (_stats.isEmpty) {
      return {
        'total_containers': 0,
        'total_evaluations': 0,
        'avg_latency_ms': 0.0,
      };
    }

    int totalEvaluations = 0;
    double avgLatency = 0.0;

    for (final stat in _stats.values) {
      totalEvaluations += stat.evaluationCount;
      avgLatency += stat.avgEvaluationMs * stat.evaluationCount;
    }

    avgLatency /= totalEvaluations;

    return {
      'total_containers': _stats.length,
      'total_evaluations': totalEvaluations,
      'avg_latency_ms': avgLatency,
      'by_type': {
        'blend': _stats.values.where((s) => s.type == ContainerType.blend).length,
        'random': _stats.values.where((s) => s.type == ContainerType.random).length,
        'sequence': _stats.values.where((s) => s.type == ContainerType.sequence).length,
      },
    };
  }

  @override
  void dispose() {
    _metricsStream.close();
    super.dispose();
  }
}
