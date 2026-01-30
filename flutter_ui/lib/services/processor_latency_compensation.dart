/// Processor Latency Compensation Service (P2-01)
///
/// Automatically compensates for DSP processor latency to maintain
/// time alignment across tracks.
///
/// Example:
/// - Track 1: Reverb plugin (200ms latency)
/// - Track 2: No effects (0ms latency)
/// → System delays Track 2 by +200ms for alignment

import 'package:flutter/foundation.dart';

/// Processor with latency info
class ProcessorLatencyInfo {
  final String processorId;
  final String processorName;
  final int latencySamples;
  final double latencyMs;

  const ProcessorLatencyInfo({
    required this.processorId,
    required this.processorName,
    required this.latencySamples,
    required this.latencyMs,
  });

  factory ProcessorLatencyInfo.fromSamples(
    String id,
    String name,
    int samples,
    double sampleRate,
  ) {
    return ProcessorLatencyInfo(
      processorId: id,
      processorName: name,
      latencySamples: samples,
      latencyMs: (samples / sampleRate) * 1000,
    );
  }
}

/// Track latency state
class TrackLatencyState {
  final int trackId;
  final int totalLatencySamples;
  final double totalLatencyMs;
  final List<ProcessorLatencyInfo> processors;
  final int compensationDelay; // Additional delay added for alignment

  const TrackLatencyState({
    required this.trackId,
    required this.totalLatencySamples,
    required this.totalLatencyMs,
    required this.processors,
    this.compensationDelay = 0,
  });

  TrackLatencyState copyWith({
    int? compensationDelay,
  }) {
    return TrackLatencyState(
      trackId: trackId,
      totalLatencySamples: totalLatencySamples,
      totalLatencyMs: totalLatencyMs,
      processors: processors,
      compensationDelay: compensationDelay ?? this.compensationDelay,
    );
  }
}

/// Processor Latency Compensation Service
class ProcessorLatencyCompensation extends ChangeNotifier {
  static final ProcessorLatencyCompensation instance = ProcessorLatencyCompensation._();
  ProcessorLatencyCompensation._();

  final Map<int, TrackLatencyState> _trackStates = {};
  bool _autoCompensationEnabled = true;
  double _sampleRate = 48000.0;

  bool get autoCompensationEnabled => _autoCompensationEnabled;
  double get sampleRate => _sampleRate;

  /// Enable/disable automatic latency compensation
  void setAutoCompensation(bool enabled) {
    if (_autoCompensationEnabled == enabled) return;
    _autoCompensationEnabled = enabled;

    if (enabled) {
      _recalculateAllCompensation();
    } else {
      _clearAllCompensation();
    }

    notifyListeners();
  }

  /// Update track latency from processor chain
  void updateTrackLatency(
    int trackId,
    List<ProcessorLatencyInfo> processors,
  ) {
    final totalSamples = processors.fold<int>(
      0,
      (sum, p) => sum + p.latencySamples,
    );

    final totalMs = (totalSamples / _sampleRate) * 1000;

    _trackStates[trackId] = TrackLatencyState(
      trackId: trackId,
      totalLatencySamples: totalSamples,
      totalLatencyMs: totalMs,
      processors: processors,
    );

    if (_autoCompensationEnabled) {
      _recalculateAllCompensation();
    }

    notifyListeners();
  }

  /// Get track latency state
  TrackLatencyState? getTrackState(int trackId) => _trackStates[trackId];

  /// Get maximum latency across all tracks
  int getMaxLatency() {
    if (_trackStates.isEmpty) return 0;
    return _trackStates.values
        .map((s) => s.totalLatencySamples)
        .reduce((a, b) => a > b ? a : b);
  }

  /// Recalculate compensation delays for all tracks
  void _recalculateAllCompensation() {
    final maxLatency = getMaxLatency();

    for (final trackId in _trackStates.keys) {
      final state = _trackStates[trackId]!;
      final compensation = maxLatency - state.totalLatencySamples;

      _trackStates[trackId] = state.copyWith(compensationDelay: compensation);

      // Apply compensation via FFI (TODO: Add FFI function)
      // NativeFFI.instance.trackSetCompensationDelay(trackId, compensation);
      debugPrint('[PDC] Track $trackId: ${state.totalLatencyMs}ms → compensate +${(compensation / _sampleRate) * 1000}ms');
    }
  }

  /// Clear all compensation delays
  void _clearAllCompensation() {
    for (final trackId in _trackStates.keys) {
      _trackStates[trackId] = _trackStates[trackId]!.copyWith(compensationDelay: 0);

      // Remove compensation via FFI
      // NativeFFI.instance.trackSetCompensationDelay(trackId, 0);
    }
  }

  /// Get compensation summary for all tracks
  Map<int, String> getCompensationSummary() {
    final summary = <int, String>{};

    for (final entry in _trackStates.entries) {
      final trackId = entry.key;
      final state = entry.value;
      final delayMs = (state.compensationDelay / _sampleRate) * 1000;

      if (state.compensationDelay > 0) {
        summary[trackId] = '+${delayMs.toStringAsFixed(1)}ms';
      } else {
        summary[trackId] = '${state.totalLatencyMs.toStringAsFixed(1)}ms (max)';
      }
    }

    return summary;
  }

  /// Clear track latency (when processor removed)
  void clearTrack(int trackId) {
    _trackStates.remove(trackId);
    notifyListeners();
  }

  /// Clear all tracks
  void clearAll() {
    _trackStates.clear();
    notifyListeners();
  }
}
