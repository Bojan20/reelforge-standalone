/// Slot Stage Provider — Stage event management
///
/// Part of P12.1.7 SlotLabProvider decomposition.
/// Handles:
/// - Stage recording (start/stop/clear)
/// - Stage playback (trigger stages, manage timing)
/// - Stage history (lastStages, stage count)
/// - Stage validation
/// - Event callbacks (onStageEvent, etc.)
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../models/stage_models.dart';
import '../../src/rust/native_ffi.dart' show SlotLabStageEvent;
import '../../services/event_registry.dart';
import '../../services/unified_playback_controller.dart';
import '../ale_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// P3.1: STAGE EVENT POOL — Reduce allocation during spin sequences
// ═══════════════════════════════════════════════════════════════════════════

/// Mutable wrapper for stage event data (reusable from pool)
class PooledStageEvent {
  String stageType = '';
  double timestampMs = 0.0;
  Map<String, dynamic> payload = const {};
  Map<String, dynamic> rawStage = const {};
  bool _inUse = false;

  void reset({
    required String stageType,
    required double timestampMs,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> rawStage,
  }) {
    this.stageType = stageType;
    this.timestampMs = timestampMs;
    this.payload = payload;
    this.rawStage = rawStage;
    _inUse = true;
  }

  void release() {
    _inUse = false;
    stageType = '';
    timestampMs = 0.0;
    payload = const {};
    rawStage = const {};
  }

  void fromStageEvent(SlotLabStageEvent event) {
    reset(
      stageType: event.stageType,
      timestampMs: event.timestampMs,
      payload: event.payload,
      rawStage: event.rawStage,
    );
  }
}

/// Object pool for stage events to reduce GC pressure
class StageEventPool {
  static final StageEventPool instance = StageEventPool._();
  StageEventPool._();

  static const int _initialPoolSize = 64;
  static const int _maxPoolSize = 256;

  final List<PooledStageEvent> _pool = [];
  int _acquiredCount = 0;
  int _poolHits = 0;
  int _poolMisses = 0;

  void init() {
    if (_pool.isEmpty) {
      for (int i = 0; i < _initialPoolSize; i++) {
        _pool.add(PooledStageEvent());
      }
      debugPrint('[StageEventPool] Initialized with $_initialPoolSize objects');
    }
  }

  PooledStageEvent acquire() {
    for (final event in _pool) {
      if (!event._inUse) {
        event._inUse = true;
        _acquiredCount++;
        _poolHits++;
        return event;
      }
    }

    _poolMisses++;
    if (_pool.length < _maxPoolSize) {
      final newEvent = PooledStageEvent();
      newEvent._inUse = true;
      _pool.add(newEvent);
      _acquiredCount++;
      return newEvent;
    }

    final temp = PooledStageEvent();
    temp._inUse = true;
    return temp;
  }

  PooledStageEvent acquireFrom(SlotLabStageEvent source) {
    final pooled = acquire();
    pooled.fromStageEvent(source);
    return pooled;
  }

  void release(PooledStageEvent event) {
    event.release();
    if (_acquiredCount > 0) _acquiredCount--;
  }

  void releaseAll() {
    for (final event in _pool) {
      event.release();
    }
    _acquiredCount = 0;
  }

  double get hitRate => _poolHits + _poolMisses > 0
      ? _poolHits / (_poolHits + _poolMisses)
      : 1.0;

  String get statsString =>
      'Pool: ${_pool.length}/$_maxPoolSize, Acquired: $_acquiredCount, '
      'Hits: $_poolHits, Misses: $_poolMisses, Hit Rate: ${(hitRate * 100).toStringAsFixed(1)}%';

  void resetStats() {
    _poolHits = 0;
    _poolMisses = 0;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE VALIDATION — Uses types from stage_models.dart
// StageValidationType, StageValidationSeverity, StageValidationIssue
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// P7.2.3: ANTICIPATION CONFIGURATION TYPE
// ═══════════════════════════════════════════════════════════════════════════

enum AnticipationConfigType {
  tipA,
  tipB,
}

// ═══════════════════════════════════════════════════════════════════════════
// SLOT STAGE PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for stage event management
class SlotStageProvider extends ChangeNotifier {
  // ─── Stage State ──────────────────────────────────────────────────────────
  List<SlotLabStageEvent> _lastStages = [];
  final List<PooledStageEvent> _pooledStages = [];
  String? _cachedStagesSpinId;

  // ─── Stage Playback ──────────────────────────────────────────────────────
  Timer? _stagePlaybackTimer;
  Timer? _audioPreTriggerTimer;
  int _currentStageIndex = 0;
  bool _isPlayingStages = false;
  bool _isPaused = false;
  int _playbackGeneration = 0;
  int _scheduledNextStageTimeMs = 0;
  int _pausedRemainingDelayMs = 0;
  int _pausedAtTimestampMs = 0;

  // ─── Reel State ──────────────────────────────────────────────────────────
  bool _isReelsSpinning = false;
  bool _isWinPresentationActive = false;
  bool _baseMusicStarted = false;
  int _totalReels = 5;
  bool _useVisualSyncForReelStop = true;

  // ─── Recording ──────────────────────────────────────────────────────────
  bool _isRecordingStages = false;

  // ─── Rollup Tracking ─────────────────────────────────────────────────────
  double _rollupStartTimestampMs = 0.0;
  double _rollupEndTimestampMs = 0.0;
  int _rollupTickCount = 0;
  int _rollupTotalTicks = 0;

  // ─── Validation ──────────────────────────────────────────────────────────
  List<StageValidationIssue> _lastValidationIssues = [];

  // ─── Anticipation Configuration ──────────────────────────────────────────
  AnticipationConfigType _anticipationConfigType = AnticipationConfigType.tipA;
  int _scatterSymbolId = 12;
  int _bonusSymbolId = 11;
  List<int> _tipBAllowedReels = [0, 2, 4];

  // ─── Skip Presentation State ─────────────────────────────────────────────
  VoidCallback? _pendingSkipCallback;
  bool _skipRequested = false;

  // ─── Dependencies ────────────────────────────────────────────────────────
  AleProvider? _aleProvider;
  bool _aleAutoSync = true;
  double _betAmount = 1.0;

  // ─── Callbacks ──────────────────────────────────────────────────────────
  void Function(int reelIndex, String reason, {int tensionLevel})? onAnticipationStart;
  void Function(int reelIndex)? onAnticipationEnd;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  List<SlotLabStageEvent> get lastStages => _lastStages;
  List<PooledStageEvent> get pooledStages => List.unmodifiable(_pooledStages);
  String? get cachedStagesSpinId => _cachedStagesSpinId;
  String get stagePoolStats => StageEventPool.instance.statsString;

  bool get isPlayingStages => _isPlayingStages;
  int get currentStageIndex => _currentStageIndex;
  bool get isPaused => _isPaused;
  bool get isActivelyPlaying => _isPlayingStages && !_isPaused;

  bool get isReelsSpinning => _isReelsSpinning;
  bool get isWinPresentationActive => _isWinPresentationActive;
  bool get useVisualSyncForReelStop => _useVisualSyncForReelStop;
  set useVisualSyncForReelStop(bool value) => _useVisualSyncForReelStop = value;

  bool get isRecordingStages => _isRecordingStages;
  bool get skipRequested => _skipRequested;

  List<StageValidationIssue> get lastValidationIssues => _lastValidationIssues;
  bool get stagesValid => _lastValidationIssues.isEmpty;

  AnticipationConfigType get anticipationConfigType => _anticipationConfigType;
  int get scatterSymbolId => _scatterSymbolId;
  int get bonusSymbolId => _bonusSymbolId;
  List<int> get tipBAllowedReels => List.unmodifiable(_tipBAllowedReels);

  bool get aleAutoSync => _aleAutoSync;

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  void setTotalReels(int reels) {
    _totalReels = reels;
  }

  void setBetAmount(double bet) {
    _betAmount = bet;
  }

  void setAnticipationConfigType(AnticipationConfigType type) {
    _anticipationConfigType = type;
    debugPrint('[SlotStageProvider] Anticipation config type: ${type.name}');
    notifyListeners();
  }

  void setScatterSymbolId(int symbolId) {
    _scatterSymbolId = symbolId;
    notifyListeners();
  }

  void setBonusSymbolId(int symbolId) {
    _bonusSymbolId = symbolId;
    notifyListeners();
  }

  void setTipBAllowedReels(List<int> reels) {
    _tipBAllowedReels = List.from(reels)..sort();
    notifyListeners();
  }

  void connectAle(AleProvider ale) {
    _aleProvider = ale;
    debugPrint('[SlotStageProvider] ALE provider connected');
  }

  void setAleAutoSync(bool enabled) {
    _aleAutoSync = enabled;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANTICIPATION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool canTriggerAnticipation(int symbolId) {
    const wildSymbolId = 10;
    if (symbolId == wildSymbolId) return false;
    return symbolId == _scatterSymbolId || symbolId == _bonusSymbolId;
  }

  bool shouldTriggerAnticipation(Set<int> triggerReels) {
    if (triggerReels.length < 2) return false;

    if (_anticipationConfigType == AnticipationConfigType.tipB) {
      if (_tipBAllowedReels.length < 2) return false;
      final firstTwo = _tipBAllowedReels.take(2).toSet();
      return firstTwo.every((r) => triggerReels.contains(r));
    } else {
      return triggerReels.length >= 2;
    }
  }

  List<int> getAnticipationReels(Set<int> triggerReels, int totalReels) {
    final result = <int>[];

    if (_anticipationConfigType == AnticipationConfigType.tipB) {
      for (final reel in _tipBAllowedReels) {
        if (!triggerReels.contains(reel) && reel < totalReels) {
          result.add(reel);
        }
      }
    } else {
      for (int r = 0; r < totalReels; r++) {
        if (!triggerReels.contains(r)) {
          result.add(r);
        }
      }
    }

    return result..sort();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE PLAYBACK
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set stages and optionally start playback
  void setStages(List<SlotLabStageEvent> stages, {
    String? spinId,
    bool autoPlay = false,
  }) {
    _lastStages = stages;
    _cachedStagesSpinId = spinId;
    _populatePooledStages();

    if (autoPlay && stages.isNotEmpty) {
      _playStagesSequentially();
    }

    notifyListeners();
  }

  /// Play stages sequentially with timing
  void _playStagesSequentially() {
    if (_lastStages.isEmpty) return;

    debugPrint('╔══════════════════════════════════════════════════════════════╗');
    debugPrint('║ STAGE PLAYBACK — ${_lastStages.length} stages                 ');
    debugPrint('╚══════════════════════════════════════════════════════════════╝');

    final controller = UnifiedPlaybackController.instance;
    if (!controller.acquireSection(PlaybackSection.slotLab)) {
      debugPrint('[SlotStageProvider] Failed to acquire SlotLab section');
      return;
    }

    controller.ensureStreamRunning();

    _stagePlaybackTimer?.cancel();
    _audioPreTriggerTimer?.cancel();
    _playbackGeneration++;
    _currentStageIndex = 0;
    _isPlayingStages = true;

    _triggerStage(_lastStages[0]);

    if (_lastStages.length > 1) {
      _scheduleNextStage();
    } else {
      _isPlayingStages = false;
    }

    notifyListeners();
  }

  void _scheduleNextStage() {
    if (_currentStageIndex >= _lastStages.length - 1) {
      _isPlayingStages = false;
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.slotLab);
      notifyListeners();
      return;
    }

    final currentStage = _lastStages[_currentStageIndex];
    final nextStage = _lastStages[_currentStageIndex + 1];
    int delayMs = (nextStage.timestampMs - currentStage.timestampMs).toInt();

    final generation = _playbackGeneration;
    final actualDelayMs = delayMs.clamp(10, 5000);
    _scheduledNextStageTimeMs = DateTime.now().millisecondsSinceEpoch + actualDelayMs;

    _stagePlaybackTimer = Timer(Duration(milliseconds: actualDelayMs), () {
      if (!_isPlayingStages || _playbackGeneration != generation || _isPaused) {
        return;
      }

      _currentStageIndex++;
      _triggerStage(_lastStages[_currentStageIndex]);
      notifyListeners();

      _scheduleNextStage();
    });
  }

  /// Stop stage playback (full reset)
  void stopStagePlayback() {
    _stagePlaybackTimer?.cancel();
    _audioPreTriggerTimer?.cancel();
    _isPlayingStages = false;
    _isReelsSpinning = false;
    _isPaused = false;
    _pausedAtTimestampMs = 0;
    _pausedRemainingDelayMs = 0;
    _currentStageIndex = 0;
    UnifiedPlaybackController.instance.releaseSection(PlaybackSection.slotLab);
    debugPrint('[SlotStageProvider] Stage playback STOPPED');
    notifyListeners();
  }

  void stopAllPlayback() => stopStagePlayback();

  // ═══════════════════════════════════════════════════════════════════════════
  // PAUSE/RESUME SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  void pauseStages() {
    if (!_isPlayingStages || _isPaused) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    _pausedAtTimestampMs = now;

    if (_scheduledNextStageTimeMs > now) {
      _pausedRemainingDelayMs = _scheduledNextStageTimeMs - now;
    } else {
      _pausedRemainingDelayMs = 0;
    }

    _stagePlaybackTimer?.cancel();
    _audioPreTriggerTimer?.cancel();

    _isPaused = true;
    UnifiedPlaybackController.instance.pause();

    debugPrint('[SlotStageProvider] Stages PAUSED at index $_currentStageIndex');
    notifyListeners();
  }

  void resumeStages() {
    if (!_isPlayingStages || !_isPaused) return;

    _isPaused = false;
    UnifiedPlaybackController.instance.play();

    if (_pausedRemainingDelayMs > 0 && _currentStageIndex < _lastStages.length - 1) {
      _scheduleNextStageWithDelay(_pausedRemainingDelayMs);
    } else if (_currentStageIndex < _lastStages.length - 1) {
      _scheduleNextStage();
    } else {
      _isPlayingStages = false;
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.slotLab);
    }

    _pausedRemainingDelayMs = 0;
    _pausedAtTimestampMs = 0;

    notifyListeners();
  }

  void togglePauseResume() {
    if (_isPaused) {
      resumeStages();
    } else if (_isPlayingStages) {
      pauseStages();
    }
  }

  void _scheduleNextStageWithDelay(int delayMs) {
    if (_currentStageIndex >= _lastStages.length - 1) {
      _isPlayingStages = false;
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.slotLab);
      notifyListeners();
      return;
    }

    final generation = _playbackGeneration;
    _scheduledNextStageTimeMs = DateTime.now().millisecondsSinceEpoch + delayMs;

    _stagePlaybackTimer = Timer(Duration(milliseconds: delayMs.clamp(10, 5000)), () {
      if (!_isPlayingStages || _playbackGeneration != generation || _isPaused) {
        return;
      }

      _currentStageIndex++;
      _triggerStage(_lastStages[_currentStageIndex]);
      _scheduleNextStage();
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE RECORDING
  // ═══════════════════════════════════════════════════════════════════════════

  void startStageRecording() {
    if (_isRecordingStages) return;
    _isRecordingStages = true;
    debugPrint('[SlotStageProvider] Stage recording STARTED');
    notifyListeners();
  }

  void stopStageRecording() {
    if (!_isRecordingStages) return;
    _isRecordingStages = false;
    debugPrint('[SlotStageProvider] Stage recording STOPPED');
    notifyListeners();
  }

  void clearStages() {
    _lastStages = [];
    _currentStageIndex = 0;
    _cachedStagesSpinId = null;
    debugPrint('[SlotStageProvider] Stages cleared');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN PRESENTATION STATE
  // ═══════════════════════════════════════════════════════════════════════════

  void setWinPresentationActive(bool active) {
    if (_isWinPresentationActive != active) {
      _isWinPresentationActive = active;

      if (!active) {
        eventRegistry.stopEvent('BIG_WIN_LOOP');
      }

      notifyListeners();
    }
  }

  void onAllReelsVisualStop() {
    if (_isReelsSpinning) {
      _isReelsSpinning = false;
      notifyListeners();
    }
  }

  void requestSkipPresentation(VoidCallback onComplete) {
    if (!_isWinPresentationActive) {
      onComplete();
      return;
    }

    _skipRequested = true;
    _pendingSkipCallback = onComplete;
    notifyListeners();
  }

  void onSkipComplete() {
    _skipRequested = false;
    final callback = _pendingSkipCallback;
    _pendingSkipCallback = null;
    setWinPresentationActive(false);
    callback?.call();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE TRIGGERING
  // ═══════════════════════════════════════════════════════════════════════════

  void triggerStageManually(int stageIndex) {
    if (stageIndex >= 0 && stageIndex < _lastStages.length) {
      _triggerStage(_lastStages[stageIndex]);
    }
  }

  void _triggerStage(SlotLabStageEvent stage) {
    final stageType = stage.stageType.toUpperCase();
    final reelIndex = stage.rawStage['reel_index'];
    Map<String, dynamic> context = {
      ...stage.payload,
      ...stage.rawStage,
      'timestamp_ms': stage.timestampMs,
    };

    // Skip REEL_STOP in visual-sync mode
    if (_useVisualSyncForReelStop && stageType == 'REEL_STOP') {
      debugPrint('[Stage] REEL_STOP [$reelIndex] -> SKIPPED (visual-sync)');
      return;
    }

    // Skip win presentation stages (handled by widget)
    if (_isWinPresentationStage(stageType)) {
      debugPrint('[Stage] $stageType -> SKIPPED (widget handles)');
      return;
    }

    // Handle anticipation callbacks
    if (stageType.startsWith('ANTICIPATION_ON')) {
      final reelIdx = _extractReelIndexFromStage(stageType);
      final reason = stage.payload['reason'] as String? ??
          stage.rawStage['reason'] as String? ?? 'scatter';
      final tensionLevel = reelIdx.clamp(1, 4);
      onAnticipationStart?.call(reelIdx, reason, tensionLevel: tensionLevel);
    } else if (stageType.startsWith('ANTICIPATION_OFF')) {
      final reelIdx = _extractReelIndexFromStage(stageType);
      onAnticipationEnd?.call(reelIdx);
    }

    // Determine effective stage name
    String effectiveStage = stageType;

    if (stageType == 'REEL_STOP' && reelIndex != null) {
      effectiveStage = 'REEL_STOP_$reelIndex';
      context['fade_out_spin_reel'] = reelIndex;
    }

    // Handle rollup tracking
    _handleRollupTracking(stageType, stage, context);

    // Trigger through EventRegistry
    if (eventRegistry.hasEventForStage(effectiveStage)) {
      eventRegistry.triggerStage(effectiveStage, context: context);
    } else if (effectiveStage != stageType && eventRegistry.hasEventForStage(stageType)) {
      eventRegistry.triggerStage(stageType, context: context);
    } else {
      eventRegistry.triggerStage(stageType, context: context);
    }

    // Handle SPIN_START
    if (stageType == 'SPIN_START') {
      _isReelsSpinning = true;

      if (eventRegistry.hasEventForStage('REEL_SPIN_LOOP')) {
        eventRegistry.triggerStage('REEL_SPIN_LOOP', context: context);
      } else if (eventRegistry.hasEventForStage('REEL_SPIN')) {
        eventRegistry.triggerStage('REEL_SPIN', context: context);
      }

      if (!_baseMusicStarted) {
        if (eventRegistry.hasEventForStage('MUSIC_BASE')) {
          eventRegistry.triggerStage('MUSIC_BASE', context: context);
          _baseMusicStarted = true;
        }
        if (eventRegistry.hasEventForStage('GAME_START')) {
          eventRegistry.triggerStage('GAME_START', context: context);
          _baseMusicStarted = true;
        }
      }

      notifyListeners();
    }

    // Handle REEL_STOP — stop spin loop
    if (stageType == 'REEL_STOP') {
      final int? reelIdx = reelIndex is int ? reelIndex : null;
      bool shouldStopReelSpin = false;

      if (reelIdx != null) {
        shouldStopReelSpin = reelIdx >= _totalReels - 1;
      } else {
        final currentIdx = _lastStages.indexWhere((s) =>
          s.timestampMs == stage.timestampMs && s.stageType.toUpperCase() == 'REEL_STOP');
        if (currentIdx >= 0 && currentIdx < _lastStages.length - 1) {
          final nextStage = _lastStages[currentIdx + 1];
          shouldStopReelSpin = nextStage.stageType.toUpperCase() != 'REEL_STOP';
        } else {
          shouldStopReelSpin = true;
        }
      }

      if (shouldStopReelSpin) {
        eventRegistry.stopEvent('REEL_SPIN_LOOP');
        eventRegistry.stopEvent('REEL_SPIN');
        if (eventRegistry.hasEventForStage('SPIN_END')) {
          eventRegistry.triggerStage('SPIN_END', context: context);
        }
      }
    }

    // Handle SPIN_END
    if (stageType == 'SPIN_END') {
      eventRegistry.stopEvent('REEL_SPIN_LOOP');
      eventRegistry.stopEvent('REEL_SPIN');
    }

    // Sync ALE signals
    _syncAleSignals(stage);
  }

  bool _isWinPresentationStage(String stageType) {
    const exactMatches = {
      'WIN_LINE_SHOW', 'WIN_LINE_HIDE',
      'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END',
      'BIG_WIN_INTRO', 'BIG_WIN_END',
    };

    if (exactMatches.contains(stageType)) return true;

    const prefixes = ['WIN_SYMBOL_HIGHLIGHT', 'WIN_PRESENT', 'WIN_TIER'];
    for (final prefix in prefixes) {
      if (stageType == prefix || stageType.startsWith('${prefix}_')) {
        return true;
      }
    }

    return false;
  }

  void _handleRollupTracking(String stageType, SlotLabStageEvent stage, Map<String, dynamic> context) {
    if (stageType == 'ROLLUP_START') {
      _rollupStartTimestampMs = stage.timestampMs;
      _rollupTickCount = 0;
      _rollupTotalTicks = 0;

      for (final s in _lastStages) {
        final sType = s.stageType.toUpperCase();
        if (sType == 'ROLLUP_TICK') _rollupTotalTicks++;
        if (sType == 'ROLLUP_END') {
          _rollupEndTimestampMs = s.timestampMs;
        }
      }
    } else if (stageType == 'ROLLUP_TICK') {
      _rollupTickCount++;

      double progress = 0.0;
      if (_rollupTotalTicks > 0) {
        progress = _rollupTickCount / _rollupTotalTicks;
      } else if (_rollupEndTimestampMs > _rollupStartTimestampMs) {
        final elapsed = stage.timestampMs - _rollupStartTimestampMs;
        final total = _rollupEndTimestampMs - _rollupStartTimestampMs;
        progress = (elapsed / total).clamp(0.0, 1.0);
      }

      context['progress'] = progress;
    } else if (stageType == 'ROLLUP_END') {
      _rollupStartTimestampMs = 0.0;
      _rollupEndTimestampMs = 0.0;
      _rollupTickCount = 0;
      _rollupTotalTicks = 0;
    }
  }

  int _extractReelIndexFromStage(String stageType) {
    final parts = stageType.split('_');
    if (parts.length >= 3) {
      final lastPart = parts.last;
      final idx = int.tryParse(lastPart);
      if (idx != null) return idx;
    }
    return 0;
  }

  void _syncAleSignals(SlotLabStageEvent stage) {
    if (!_aleAutoSync || _aleProvider == null || !_aleProvider!.initialized) {
      return;
    }
    // ALE sync handled by coordinator
  }

  void _populatePooledStages() {
    final pool = StageEventPool.instance;

    for (final pooled in _pooledStages) {
      pool.release(pooled);
    }
    _pooledStages.clear();

    for (final stage in _lastStages) {
      final pooled = pool.acquireFrom(stage);
      _pooledStages.add(pooled);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE VALIDATION
  // ═══════════════════════════════════════════════════════════════════════════

  List<StageValidationIssue> validateStageSequence() {
    final issues = <StageValidationIssue>[];
    if (_lastStages.isEmpty) {
      issues.add(StageValidationIssue(
        type: StageValidationType.missingStage,
        message: 'No stages present',
        severity: StageValidationSeverity.error,
      ));
      _lastValidationIssues = issues;
      return issues;
    }

    final stageTypes = _lastStages.map((s) => s.stageType.toUpperCase()).toList();

    // SPIN_START must be first
    if (stageTypes.isNotEmpty && stageTypes.first != 'SPIN_START') {
      issues.add(StageValidationIssue(
        type: StageValidationType.orderViolation,
        message: 'SPIN_START must be first stage',
        severity: StageValidationSeverity.error,
        stageIndex: 0,
      ));
    }

    // SPIN_END should be last
    if (stageTypes.isNotEmpty && stageTypes.last != 'SPIN_END') {
      issues.add(StageValidationIssue(
        type: StageValidationType.orderViolation,
        message: 'SPIN_END should be last stage',
        severity: StageValidationSeverity.warning,
        stageIndex: stageTypes.length - 1,
      ));
    }

    // Timestamps must be monotonically increasing
    for (int i = 1; i < _lastStages.length; i++) {
      if (_lastStages[i].timestampMs < _lastStages[i - 1].timestampMs) {
        issues.add(StageValidationIssue(
          type: StageValidationType.timestampViolation,
          message: 'Timestamp decreased at stage $i',
          severity: StageValidationSeverity.error,
          stageIndex: i,
        ));
      }
    }

    // Required stages check
    const requiredStages = {'SPIN_START', 'SPIN_END'};
    for (final required in requiredStages) {
      if (!stageTypes.contains(required)) {
        issues.add(StageValidationIssue(
          type: StageValidationType.missingStage,
          message: 'Required stage missing: $required',
          severity: StageValidationSeverity.error,
        ));
      }
    }

    if (issues.isEmpty) {
      debugPrint('[SlotStageProvider] Stage sequence VALID');
    } else {
      debugPrint('[SlotStageProvider] Stage sequence INVALID (${issues.length} issues)');
    }

    _lastValidationIssues = issues;
    notifyListeners();
    return issues;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _stagePlaybackTimer?.cancel();
    _audioPreTriggerTimer?.cancel();
    super.dispose();
  }
}
