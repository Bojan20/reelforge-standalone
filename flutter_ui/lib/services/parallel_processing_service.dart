/// Parallel Processing Service — P2-DAW-1
///
/// Enables A/B parallel processing paths for tracks:
/// - Duplicate processing chain per track (Chain A / Chain B)
/// - A/B comparison mode with instant switching
/// - Blend control (0-100%) between chains
/// - Copy chain settings between A/B
///
/// Usage:
///   final service = ParallelProcessingService.instance;
///   service.enableParallelProcessing(trackId, true);
///   service.setActiveChain(trackId, ParallelChain.b);
///   service.setBlend(trackId, 0.5); // 50% blend
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../src/rust/native_ffi.dart';
import '../providers/dsp_chain_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARALLEL CHAIN TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Which parallel chain is active
enum ParallelChain {
  /// Chain A (primary)
  a,

  /// Chain B (comparison)
  b,

  /// Both chains blended
  blend,
}

extension ParallelChainExtension on ParallelChain {
  String get displayName {
    switch (this) {
      case ParallelChain.a:
        return 'Chain A';
      case ParallelChain.b:
        return 'Chain B';
      case ParallelChain.blend:
        return 'Blend';
    }
  }

  String get shortName {
    switch (this) {
      case ParallelChain.a:
        return 'A';
      case ParallelChain.b:
        return 'B';
      case ParallelChain.blend:
        return 'A+B';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PARALLEL TRACK CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for parallel processing on a track
class ParallelTrackConfig {
  final int trackId;
  final bool enabled;
  final ParallelChain activeChain;
  final double blend; // 0.0 = 100% A, 1.0 = 100% B
  final DspChain chainA;
  final DspChain chainB;
  final bool abLocked; // Lock A/B to same settings
  final DateTime lastSwitchTime;

  const ParallelTrackConfig({
    required this.trackId,
    this.enabled = false,
    this.activeChain = ParallelChain.a,
    this.blend = 0.0,
    required this.chainA,
    required this.chainB,
    this.abLocked = false,
    required this.lastSwitchTime,
  });

  ParallelTrackConfig copyWith({
    bool? enabled,
    ParallelChain? activeChain,
    double? blend,
    DspChain? chainA,
    DspChain? chainB,
    bool? abLocked,
    DateTime? lastSwitchTime,
  }) {
    return ParallelTrackConfig(
      trackId: trackId,
      enabled: enabled ?? this.enabled,
      activeChain: activeChain ?? this.activeChain,
      blend: blend ?? this.blend,
      chainA: chainA ?? this.chainA,
      chainB: chainB ?? this.chainB,
      abLocked: abLocked ?? this.abLocked,
      lastSwitchTime: lastSwitchTime ?? this.lastSwitchTime,
    );
  }

  /// Get the currently active chain
  DspChain get currentChain =>
      activeChain == ParallelChain.b ? chainB : chainA;

  /// Calculate effective blend value based on mode
  double get effectiveBlend {
    switch (activeChain) {
      case ParallelChain.a:
        return 0.0;
      case ParallelChain.b:
        return 1.0;
      case ParallelChain.blend:
        return blend;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// A/B COMPARISON RESULT
// ═══════════════════════════════════════════════════════════════════════════

/// Result of an A/B comparison session
class ABComparisonResult {
  final int trackId;
  final Duration sessionDuration;
  final int switchCount;
  final Duration timeOnA;
  final Duration timeOnB;
  final ParallelChain? preferredChain;
  final DateTime timestamp;

  ABComparisonResult({
    required this.trackId,
    required this.sessionDuration,
    required this.switchCount,
    required this.timeOnA,
    required this.timeOnB,
    this.preferredChain,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Percentage of time spent on Chain A
  double get percentageOnA =>
      sessionDuration.inMilliseconds > 0
          ? timeOnA.inMilliseconds / sessionDuration.inMilliseconds
          : 0.0;

  /// Percentage of time spent on Chain B
  double get percentageOnB =>
      sessionDuration.inMilliseconds > 0
          ? timeOnB.inMilliseconds / sessionDuration.inMilliseconds
          : 0.0;
}

// ═══════════════════════════════════════════════════════════════════════════
// PARALLEL PROCESSING SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for managing parallel A/B processing chains per track
class ParallelProcessingService extends ChangeNotifier {
  ParallelProcessingService._();
  static final instance = ParallelProcessingService._();

  final NativeFFI _ffi = NativeFFI.instance;

  // Track configs: trackId -> config
  final Map<int, ParallelTrackConfig> _configs = {};

  // A/B comparison tracking
  final Map<int, Stopwatch> _sessionStopwatches = {};
  final Map<int, Duration> _timeOnA = {};
  final Map<int, Duration> _timeOnB = {};
  final Map<int, int> _switchCounts = {};
  final Map<int, DateTime> _lastSwitchTimes = {};

  // Callbacks
  void Function(int trackId, ParallelChain chain)? onChainSwitched;
  void Function(int trackId, ABComparisonResult result)? onComparisonComplete;

  /// Get all configured tracks
  List<int> get configuredTracks => _configs.keys.toList();

  /// Check if parallel processing is enabled for a track
  bool isEnabled(int trackId) => _configs[trackId]?.enabled ?? false;

  /// Get config for a track
  ParallelTrackConfig? getConfig(int trackId) => _configs[trackId];

  /// Get active chain for a track
  ParallelChain getActiveChain(int trackId) =>
      _configs[trackId]?.activeChain ?? ParallelChain.a;

  /// Get blend value for a track (0.0-1.0)
  double getBlend(int trackId) => _configs[trackId]?.blend ?? 0.0;

  // ─────────────────────────────────────────────────────────────────────────
  // ENABLE/DISABLE
  // ─────────────────────────────────────────────────────────────────────────

  /// Enable or disable parallel processing for a track
  Future<bool> enableParallelProcessing(int trackId, bool enable) async {
    try {
      if (enable && !_configs.containsKey(trackId)) {
        // Create new config with duplicated chain
        final dspProvider = DspChainProvider.instance;
        final originalChain = dspProvider.getChain(trackId);

        _configs[trackId] = ParallelTrackConfig(
          trackId: trackId,
          enabled: true,
          chainA: originalChain,
          chainB: originalChain.copyWith(), // Duplicate
          lastSwitchTime: DateTime.now(),
        );

        // Initialize tracking
        _sessionStopwatches[trackId] = Stopwatch()..start();
        _timeOnA[trackId] = Duration.zero;
        _timeOnB[trackId] = Duration.zero;
        _switchCounts[trackId] = 0;

      } else if (!enable && _configs.containsKey(trackId)) {
        // Finalize comparison and disable
        _finalizeComparison(trackId);
        _configs.remove(trackId);
        _cleanupTracking(trackId);

      } else if (enable && _configs.containsKey(trackId)) {
        // Just update enabled state
        _configs[trackId] = _configs[trackId]!.copyWith(enabled: true);
      }

      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHAIN SWITCHING
  // ─────────────────────────────────────────────────────────────────────────

  /// Set the active chain for a track
  Future<bool> setActiveChain(int trackId, ParallelChain chain) async {
    final config = _configs[trackId];
    if (config == null || !config.enabled) return false;

    try {
      final previousChain = config.activeChain;

      // Update time tracking
      _updateTimeTracking(trackId, previousChain);

      // Update config
      _configs[trackId] = config.copyWith(
        activeChain: chain,
        lastSwitchTime: DateTime.now(),
      );

      _switchCounts[trackId] = (_switchCounts[trackId] ?? 0) + 1;
      _lastSwitchTimes[trackId] = DateTime.now();

      // Apply chain to engine
      await _applyChainToEngine(trackId, chain);

      onChainSwitched?.call(trackId, chain);
      notifyListeners();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Toggle between Chain A and Chain B
  Future<bool> toggleChain(int trackId) async {
    final current = getActiveChain(trackId);
    final next = current == ParallelChain.a ? ParallelChain.b : ParallelChain.a;
    return setActiveChain(trackId, next);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BLEND CONTROL
  // ─────────────────────────────────────────────────────────────────────────

  /// Set blend amount between Chain A and Chain B
  /// 0.0 = 100% Chain A, 1.0 = 100% Chain B
  Future<bool> setBlend(int trackId, double blend) async {
    final config = _configs[trackId];
    if (config == null || !config.enabled) return false;

    final clampedBlend = blend.clamp(0.0, 1.0);

    try {
      _configs[trackId] = config.copyWith(
        blend: clampedBlend,
        activeChain: ParallelChain.blend,
      );

      // Apply blend to engine
      await _applyBlendToEngine(trackId, clampedBlend);

      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHAIN OPERATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Copy Chain A settings to Chain B
  Future<bool> copyAToB(int trackId) async {
    final config = _configs[trackId];
    if (config == null) return false;

    _configs[trackId] = config.copyWith(
      chainB: config.chainA.copyWith(),
    );

    notifyListeners();
    return true;
  }

  /// Copy Chain B settings to Chain A
  Future<bool> copyBToA(int trackId) async {
    final config = _configs[trackId];
    if (config == null) return false;

    _configs[trackId] = config.copyWith(
      chainA: config.chainB.copyWith(),
    );

    notifyListeners();
    return true;
  }

  /// Swap Chain A and Chain B
  Future<bool> swapChains(int trackId) async {
    final config = _configs[trackId];
    if (config == null) return false;

    _configs[trackId] = config.copyWith(
      chainA: config.chainB,
      chainB: config.chainA,
    );

    notifyListeners();
    return true;
  }

  /// Lock/unlock A/B to same settings
  void setABLocked(int trackId, bool locked) {
    final config = _configs[trackId];
    if (config == null) return;

    _configs[trackId] = config.copyWith(abLocked: locked);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMPARISON SESSION
  // ─────────────────────────────────────────────────────────────────────────

  /// End comparison session and get results
  ABComparisonResult? endComparison(int trackId, {ParallelChain? preferred}) {
    final config = _configs[trackId];
    if (config == null) return null;

    return _finalizeComparison(trackId, preferredChain: preferred);
  }

  /// Get current comparison stats
  Map<String, dynamic> getComparisonStats(int trackId) {
    final stopwatch = _sessionStopwatches[trackId];
    final timeA = _timeOnA[trackId] ?? Duration.zero;
    final timeB = _timeOnB[trackId] ?? Duration.zero;
    final switches = _switchCounts[trackId] ?? 0;

    return {
      'sessionDuration': stopwatch?.elapsed ?? Duration.zero,
      'timeOnA': timeA,
      'timeOnB': timeB,
      'switchCount': switches,
      'percentageOnA':
          stopwatch != null && stopwatch.elapsedMilliseconds > 0
              ? timeA.inMilliseconds / stopwatch.elapsedMilliseconds
              : 0.0,
      'percentageOnB':
          stopwatch != null && stopwatch.elapsedMilliseconds > 0
              ? timeB.inMilliseconds / stopwatch.elapsedMilliseconds
              : 0.0,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRIVATE METHODS
  // ─────────────────────────────────────────────────────────────────────────

  void _updateTimeTracking(int trackId, ParallelChain previousChain) {
    final lastSwitch = _lastSwitchTimes[trackId];
    if (lastSwitch == null) return;

    final elapsed = DateTime.now().difference(lastSwitch);

    if (previousChain == ParallelChain.a) {
      _timeOnA[trackId] = (_timeOnA[trackId] ?? Duration.zero) + elapsed;
    } else if (previousChain == ParallelChain.b) {
      _timeOnB[trackId] = (_timeOnB[trackId] ?? Duration.zero) + elapsed;
    } else {
      // Blend mode - split time proportionally
      final blend = _configs[trackId]?.blend ?? 0.5;
      final timeA = Duration(
        milliseconds: (elapsed.inMilliseconds * (1 - blend)).round(),
      );
      final timeB = Duration(
        milliseconds: (elapsed.inMilliseconds * blend).round(),
      );
      _timeOnA[trackId] = (_timeOnA[trackId] ?? Duration.zero) + timeA;
      _timeOnB[trackId] = (_timeOnB[trackId] ?? Duration.zero) + timeB;
    }
  }

  ABComparisonResult? _finalizeComparison(
    int trackId, {
    ParallelChain? preferredChain,
  }) {
    final stopwatch = _sessionStopwatches[trackId];
    if (stopwatch == null) return null;

    stopwatch.stop();

    // Update final time tracking
    final config = _configs[trackId];
    if (config != null) {
      _updateTimeTracking(trackId, config.activeChain);
    }

    final result = ABComparisonResult(
      trackId: trackId,
      sessionDuration: stopwatch.elapsed,
      switchCount: _switchCounts[trackId] ?? 0,
      timeOnA: _timeOnA[trackId] ?? Duration.zero,
      timeOnB: _timeOnB[trackId] ?? Duration.zero,
      preferredChain: preferredChain,
    );

    onComparisonComplete?.call(trackId, result);
    return result;
  }

  void _cleanupTracking(int trackId) {
    _sessionStopwatches.remove(trackId);
    _timeOnA.remove(trackId);
    _timeOnB.remove(trackId);
    _switchCounts.remove(trackId);
    _lastSwitchTimes.remove(trackId);
  }

  Future<void> _applyChainToEngine(int trackId, ParallelChain chain) async {
    final config = _configs[trackId];
    if (config == null) return;

    // Get the appropriate chain
    final dspChain =
        chain == ParallelChain.b ? config.chainB : config.chainA;

    // Apply each node to the engine
    for (int i = 0; i < dspChain.nodes.length; i++) {
      final node = dspChain.nodes[i];

      // Set bypass state based on chain selection
      final bypass = chain == ParallelChain.blend
          ? false
          : (chain == ParallelChain.a
              ? node.bypass
              : dspChain.nodes[i].bypass);

      _ffi.insertSetBypass(trackId, i, bypass);
    }
  }

  Future<void> _applyBlendToEngine(int trackId, double blend) async {
    // In blend mode, we use wet/dry mix on the processors
    // blend = 0.0 means Chain A, blend = 1.0 means Chain B
    // For now, we'll set the mix parameter on supported processors

    final config = _configs[trackId];
    if (config == null) return;

    // Apply blend via parallel mix parameter
    // This would typically be done via a dedicated parallel blend FFI
    // For now, we simulate by adjusting wet/dry on the chain
    _ffi.insertSetParam(trackId, 0, 5, blend); // Mix param index
  }
}
