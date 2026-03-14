/// Slot Audio Provider — Audio playback orchestration
///
/// Part of P12.1.7 SlotLabProvider decomposition.
/// Handles:
/// - Section management (acquire/release playback section)
/// - Event triggering (via EventRegistry)
/// - Audio settings (volumes, mutes)
/// - Playback state (auto trigger, etc.)
/// - ALE signal sync
/// - Dynamic music layer switching (MusicLayerController)
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../models/slot_lab_models.dart';
import '../../services/event_registry.dart';
import '../../services/audio_playback_service.dart';
import '../../services/audio_asset_manager.dart';
import '../../src/rust/native_ffi.dart';
import '../middleware_provider.dart';
import '../ale_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SLOT AUDIO PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for audio playback orchestration in SlotLab
class SlotAudioProvider extends ChangeNotifier {
  final NativeFFI _ffi = NativeFFI.instance;

  // ─── Dependencies ────────────────────────────────────────────────────────
  MiddlewareProvider? _middleware;
  AleProvider? _aleProvider;

  // ─── Configuration ──────────────────────────────────────────────────────
  bool _autoTriggerAudio = true;
  bool _aleAutoSync = true;
  double _betAmount = 1.0;
  int _totalReels = 5;

  // ─── Dynamic Music Layer Controller ───────────────────────────────────
  final MusicLayerController _musicLayerController = MusicLayerController();

  // ─── Persistent UI State ────────────────────────────────────────────────
  /// Audio pool now comes from AudioAssetManager (single source of truth)
  List<Map<String, dynamic>> get persistedAudioPool =>
      AudioAssetManager.instance.toMapList();

  set persistedAudioPool(List<Map<String, dynamic>> value) {
    for (final map in value) {
      AudioAssetManager.instance.addFromMap(map);
    }
  }

  List<Map<String, dynamic>> persistedCompositeEvents = [];
  List<Map<String, dynamic>> persistedTracks = [];
  Map<String, String> persistedEventToRegionMap = {};

  // ─── Lower Zone Tab State ───────────────────────────────────────────────
  int _persistedLowerZoneTabIndex = 1;
  bool _persistedLowerZoneExpanded = false;
  double _persistedLowerZoneHeight = 250.0;

  // ─── Waveform Cache ─────────────────────────────────────────────────────
  final Map<String, List<double>> waveformCache = {};
  final Map<String, int> clipIdCache = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get autoTriggerAudio => _autoTriggerAudio;
  bool get aleAutoSync => _aleAutoSync;
  MusicLayerController get musicLayerController => _musicLayerController;

  int get persistedLowerZoneTabIndex => _persistedLowerZoneTabIndex;
  bool get persistedLowerZoneExpanded => _persistedLowerZoneExpanded;
  double get persistedLowerZoneHeight => _persistedLowerZoneHeight;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Connect middleware for audio triggering
  void connectMiddleware(MiddlewareProvider middleware) {
    _middleware = middleware;
  }

  /// Connect ALE provider for signal sync
  void connectAle(AleProvider ale) {
    _aleProvider = ale;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  void setAutoTriggerAudio(bool enabled) {
    _autoTriggerAudio = enabled;
    notifyListeners();
  }

  void setAleAutoSync(bool enabled) {
    _aleAutoSync = enabled;
    notifyListeners();
  }

  void setBetAmount(double bet) {
    _betAmount = bet;
  }

  void setTotalReels(int reels) {
    _totalReels = reels;
  }

  // ─── Lower Zone State ───────────────────────────────────────────────────

  void setLowerZoneTabIndex(int index) {
    if (_persistedLowerZoneTabIndex != index) {
      _persistedLowerZoneTabIndex = index;
    }
  }

  void setLowerZoneExpanded(bool expanded) {
    _persistedLowerZoneExpanded = expanded;
  }

  void setLowerZoneHeight(double height) {
    _persistedLowerZoneHeight = height;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ALE SIGNAL SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync Slot Lab state to ALE signals + evaluate dynamic music layers
  void syncAleSignals(SlotLabSpinResult? result, double hitRate, bool inFreeSpins, int freeSpinsRemaining, int spinCount, double volatilitySlider, List<SlotLabStageEvent> lastStages) {
    if (result == null) return;

    // Dynamic music layer evaluation — independent of ALE
    // For win spins: defer evaluation until win presentation ends (plaque dismissed)
    // For non-win spins: evaluate immediately (no presentation to wait for)
    if (result.isWin) {
      _musicLayerController._parentNotify = notifyListeners;
      _musicLayerController.deferEvaluation(result.winRatio);
    } else {
      _musicLayerController.evaluateAfterSpin(result.winRatio, notifyListeners);
    }

    // ALE signal sync
    if (!_aleAutoSync || _aleProvider == null || !_aleProvider!.initialized) {
      return;
    }

    final signals = <String, double>{
      'winTier': _calculateWinTier(result.winRatio),
      'momentum': _calculateMomentum(hitRate, result.isWin, inFreeSpins),
      'volatility': volatilitySlider,
      'sessionProgress': (spinCount / 100.0).clamp(0.0, 1.0),
      'featureProgress': inFreeSpins
          ? 1.0 - (freeSpinsRemaining / 15.0).clamp(0.0, 1.0)
          : 0.0,
      'betMultiplier': (_betAmount / 10.0).clamp(0.0, 1.0),
      'recentWinRate': hitRate,
      'timeSinceWin': result.isWin ? 0.0 : 5000.0,
      'comboCount': _countCascades(lastStages).toDouble(),
      'nearMissRate': _calculateNearMissRate(lastStages),
    };

    _aleProvider!.updateSignals(signals);
    _syncAleContext(result, inFreeSpins);
  }

  double _calculateWinTier(double winRatio) {
    if (winRatio <= 0) return 0.0;
    if (winRatio < 2) return 1.0;
    if (winRatio < 5) return 2.0;
    if (winRatio < 15) return 3.0;
    if (winRatio < 50) return 4.0;
    return 5.0;
  }

  double _calculateMomentum(double hitRate, bool isWin, bool inFreeSpins) {
    final baseMomentum = hitRate;
    final winBoost = isWin ? 0.3 : 0.0;
    final featureBoost = inFreeSpins ? 0.2 : 0.0;
    return (baseMomentum + winBoost + featureBoost).clamp(0.0, 1.0);
  }

  int _countCascades(List<SlotLabStageEvent> stages) {
    return stages.where((s) =>
        s.stageType.toUpperCase() == 'CASCADE_STEP').length;
  }

  double _calculateNearMissRate(List<SlotLabStageEvent> stages) {
    final anticipations = stages.where((s) =>
        s.stageType.toUpperCase().startsWith('ANTICIPATION_TENSION')).length;
    return (anticipations / 5.0).clamp(0.0, 1.0);
  }

  void _syncAleContext(SlotLabSpinResult result, bool inFreeSpins) {
    if (_aleProvider == null) return;

    final currentContext = _aleProvider!.state.activeContextId;

    String targetContext;
    if (inFreeSpins) {
      targetContext = 'FREESPINS';
    } else if (result.bigWinTier != null &&
               result.bigWinTier != SlotLabWinTier.none) {
      targetContext = 'BIGWIN';
    } else {
      targetContext = 'BASE';
    }

    if (currentContext != targetContext) {
      _aleProvider!.enterContext(targetContext);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYMBOL DETECTION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if symbols list contains a Wild
  bool containsWild(List<dynamic>? symbols) {
    if (symbols == null || symbols.isEmpty) return false;
    return symbols.any((s) => s == 0 || s == 10);
  }

  /// Check if symbols list contains a Scatter
  bool containsScatter(List<dynamic>? symbols) {
    if (symbols == null || symbols.isEmpty) return false;
    return symbols.contains(9);
  }

  /// Check if symbols list contains a Seven
  bool containsSeven(List<dynamic>? symbols) {
    if (symbols == null || symbols.isEmpty) return false;
    return symbols.contains(7);
  }

  /// Check if symbols list contains a high-paying symbol
  bool containsHighPaySymbol(List<dynamic>? symbols) {
    if (symbols == null || symbols.isEmpty) return false;
    return symbols.any((s) => s == 0 || s == 7 || s == 8 || s == 10);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN LINE AUDIO PANNING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculate pan value based on win line positions
  double calculateWinLinePan(int lineIndex, SlotLabSpinResult? result) {
    if (result == null) return 0.0;

    final lineWin = result.lineWins.firstWhere(
      (lw) => lw.lineIndex == lineIndex,
      orElse: () => const LineWin(
        lineIndex: -1,
        symbolId: 0,
        symbolName: '',
        matchCount: 0,
        winAmount: 0.0,
        positions: [],
      ),
    );

    if (lineWin.lineIndex == -1 || lineWin.positions.isEmpty) {
      return 0.0;
    }

    double sumX = 0.0;
    for (final pos in lineWin.positions) {
      if (pos.isNotEmpty) {
        sumX += pos[0].toDouble();
      }
    }
    final avgX = sumX / lineWin.positions.length;

    if (_totalReels <= 1) return 0.0;

    final normalizedX = avgX / (_totalReels - 1);
    final pan = (normalizedX * 2.0) - 1.0;

    return pan.clamp(-1.0, 1.0);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANTICIPATION ESCALATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculate anticipation escalation based on near miss info
  ({String effectiveStage, double volumeMultiplier}) calculateAnticipationEscalation(
    SlotLabStageEvent stage,
    int totalReels,
  ) {
    final intensity = (stage.payload['intensity'] as num?)?.toDouble() ?? 0.5;
    final missingSymbols = stage.payload['missing'] as int? ?? 2;
    final triggerReel = stage.rawStage['reel_index'] as int? ??
        stage.payload['trigger_reel'] as int? ?? 2;

    final reelFactor = (triggerReel + 1) / totalReels;

    final missingFactor = switch (missingSymbols) {
      1 => 1.0,
      2 => 0.75,
      _ => 0.5,
    };

    final combinedIntensity = (intensity * reelFactor * missingFactor).clamp(0.0, 1.0);

    String effectiveStage;
    double volumeMultiplier;

    if (combinedIntensity >= 0.8) {
      if (eventRegistry.hasEventForStage('ANTICIPATION_MAX')) {
        effectiveStage = 'ANTICIPATION_MAX';
      } else if (eventRegistry.hasEventForStage('ANTICIPATION_HIGH')) {
        effectiveStage = 'ANTICIPATION_HIGH';
      } else {
        effectiveStage = 'ANTICIPATION_TENSION';
      }
      volumeMultiplier = 1.0;
    } else if (combinedIntensity >= 0.5) {
      if (eventRegistry.hasEventForStage('ANTICIPATION_HIGH')) {
        effectiveStage = 'ANTICIPATION_HIGH';
      } else {
        effectiveStage = 'ANTICIPATION_TENSION';
      }
      volumeMultiplier = 0.9;
    } else {
      effectiveStage = 'ANTICIPATION_TENSION';
      volumeMultiplier = 0.7 + (combinedIntensity * 0.3);
    }

    return (effectiveStage: effectiveStage, volumeMultiplier: volumeMultiplier);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DYNAMIC MUSIC LAYER CONTROL
  // ═══════════════════════════════════════════════════════════════════════════

  /// Load music layer config (from project load) — resets runtime state
  void loadMusicLayerConfig(MusicLayerConfig config) {
    _musicLayerController.reset();
    _musicLayerController.loadConfig(config);
    notifyListeners();
  }

  /// Update music layer config (from UI)
  void updateMusicLayerConfig(MusicLayerConfig config) {
    _musicLayerController.loadConfig(config);
    notifyListeners();
  }

  /// BIG_WIN_START: fadeout and stop all base game layers
  int _fadeOutGeneration = 0;
  void fadeOutBaseGameLayers({int fadeMs = 500}) {
    final playback = AudioPlaybackService.instance;
    final gen = ++_fadeOutGeneration;
    // Fade both GAME_START composite voices and standalone MUSIC_BASE_L voices
    for (int i = 1; i <= 5; i++) {
      for (final layerId in ['game_start_l$i', 'layer_MUSIC_BASE_L$i']) {
        final voices = playback.activeVoices.where((v) => v.layerId == layerId).toList();
        if (voices.isNotEmpty) {
          playback.fadeLayerVolume(layerId, 0.0, fadeMs: fadeMs);
        }
      }
    }
    // Stop voices after fade completes (guarded by generation to avoid killing new voices)
    Future.delayed(Duration(milliseconds: fadeMs + 50), () {
      if (_fadeOutGeneration != gen) return; // New restart happened — don't stop
      for (int i = 1; i <= 5; i++) {
        playback.stopLayer('game_start_l$i');
        playback.stopLayer('layer_MUSIC_BASE_L$i');
      }
      // Stop EventRegistry standalone instances AFTER fade completes
      try {
        EventRegistry.instance.stopEventsByPrefix('MUSIC_BASE_L');
      } catch (_) {}
    });
  }

  /// BIG_WIN_END: restart all base game layers at volume 0.0 (silent, ready for fade-in)
  void restartBaseGameLayersSilent() {
    _fadeOutGeneration++; // Cancel any pending fadeOut stop
    final registry = EventRegistry.instance;
    final playback = AudioPlaybackService.instance;
    final gsEvent = registry.getEventForStage('GAME_START');
    if (gsEvent == null) return;

    // Stop any leftover voices first
    for (int i = 1; i <= 5; i++) {
      playback.stopLayer('game_start_l$i');
      playback.stopLayer('layer_MUSIC_BASE_L$i');
    }
    registry.stopEvent('audio_GAME_START');

    // Launch all layers at volume 0.0
    for (final layer in gsEvent.layers) {
      if (layer.audioPath.isEmpty || layer.actionType != 'Play') continue;
      playback.layerVolumes[layer.id] = 0.0;
      playback.playLoopingToBus(
        layer.audioPath,
        volume: 0.0,
        busId: layer.busId,
        eventId: gsEvent.id,
        layerId: layer.id,
      );
    }
  }

  /// Defer reset to base layer (L1) — called after BIG_WIN_END.
  /// When plaque dismissed: fade in ONLY L1 to 1.0, others stay at 0.0.
  void resetMusicLayerToBase() {
    _musicLayerController._pendingWinRatio = null;
    _musicLayerController._pendingResetToBase = true;
  }

  /// Reset music layer state (on new session / pool reset)
  void resetMusicLayerState() {
    _musicLayerController.reset();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PERSISTED STATE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Clear all persisted UI state
  void clearPersistedState() {
    AudioAssetManager.instance.clear();
    persistedCompositeEvents.clear();
    persistedTracks.clear();
    persistedEventToRegionMap.clear();
    _musicLayerController.reset();
    notifyListeners();
  }

}

// ═══════════════════════════════════════════════════════════════════════════════
// MUSIC LAYER CONTROLLER
// ═══════════════════════════════════════════════════════════════════════════════
//
// Manages dynamic music layer switching based on win thresholds.
// Architecture:
//   - All MUSIC_BASE_L1-L5 start simultaneously via GAME_START composite
//     (L1 at full volume, L2-L5 at volume 0)
//   - This controller adjusts volumes via EventRegistry.setLayerVolume()
//   - Escalation: when winRatio exceeds a threshold, crossfade to higher layer
//   - De-escalation: after N spins without meeting threshold, revert to previous
//   - Uses equal power crossfade for perceptually smooth transitions
// ═══════════════════════════════════════════════════════════════════════════════

class MusicLayerController extends ChangeNotifier {
  // ─── State ─────────────────────────────────────────────────────────────
  MusicLayerConfig _config = const MusicLayerConfig();
  int _activeLayer = 1;
  int _previousLayer = 1;
  int _spinsSinceEscalation = 0;
  bool _isEscalated = false;

  // ─── Seconds-based revert timer ────────────────────────────────────────
  Timer? _revertTimer;

  // ─── History for UI visualization ──────────────────────────────────────
  final List<MusicLayerEvent> _history = [];

  // ─── Pending evaluation (deferred until win presentation ends) ─────────
  double? _pendingWinRatio;
  bool _pendingResetToBase = false;
  VoidCallback? _parentNotify;

  /// Defer evaluation until win presentation ends
  void deferEvaluation(double winRatio) {
    _pendingWinRatio = winRatio;
    final ts = DateTime.now().millisecondsSinceEpoch % 100000;
    _lastCrossfadeDiag = 'DEFERRED wr=$winRatio t=$ts (waiting for flush)';
    notifyListeners();
  }

  /// Flush pending evaluation — called by coordinator when win flow ends
  void flushPendingCrossfade() {
    if (_pendingResetToBase) {
      _pendingResetToBase = false;
      _pendingWinRatio = null; // Clear any pending eval — BIG_WIN_END overrides
      // Reset controller state to L1
      _activeLayer = 1;
      _previousLayer = 1;
      _spinsSinceEscalation = 0;
      _isEscalated = false;
      // Fade in ONLY L1, fade out all others to 0.0 in engine (not just cache)
      final playback = AudioPlaybackService.instance;
      _cancelRevertTimer();
      final fadeMs = _config.downshiftFadeMs;
      for (int i = 1; i <= 5; i++) {
        final layerId = 'game_start_l$i';
        if (i == 1) {
          playback.layerVolumes[layerId] = 0.0; // Start from 0.0 (silent)
          playback.fadeLayerVolume(layerId, 1.0, fadeMs: fadeMs);
        } else {
          // Fade to 0.0 in engine — not just cache, in case voice still has old volume
          playback.fadeLayerVolume(layerId, 0.0, fadeMs: fadeMs);
        }
      }
      _addHistoryEvent(MusicLayerTransition(
        fromLayer: 0,
        toLayer: 1,
        reason: MusicLayerTransitionReason.revert,
        winRatio: 0.0,
        crossfadeMs: fadeMs,
      ));
      notifyListeners();
      return;
    }

    // Flush deferred evaluation — evaluate NOW (after win presentation)
    final winRatio = _pendingWinRatio;
    if (winRatio != null) {
      _pendingWinRatio = null;
      // Diagnostics: capture caller for debugging
      final ts = DateTime.now().millisecondsSinceEpoch % 100000;
      final caller = StackTrace.current.toString().split('\n').take(5).join('\n');
      _lastCrossfadeDiag = 'FLUSH eval wr=$winRatio t=$ts\n$caller';
      evaluateAfterSpin(winRatio, _parentNotify ?? () {});
    }
  }

  // ─── Diagnostics ────────────────────────────────────────────────────────
  String _lastCrossfadeDiag = '';
  String get lastCrossfadeDiag => _lastCrossfadeDiag;

  // ─── Getters ───────────────────────────────────────────────────────────
  MusicLayerConfig get config => _config;
  int get activeLayer => _activeLayer;
  int get previousLayer => _previousLayer;
  int get spinsSinceEscalation => _spinsSinceEscalation;
  bool get isEscalated => _isEscalated;
  List<MusicLayerEvent> get history => List.unmodifiable(_history);

  /// Human-readable label for the current active layer
  String get activeLayerLabel {
    final threshold = _config.thresholds
        .where((t) => t.layer == _activeLayer)
        .firstOrNull;
    return threshold?.label ?? 'L$_activeLayer';
  }

  /// How many assigned layers exist in config
  int get configuredLayerCount => _config.thresholds.length;

  /// Whether the controller has a valid config with 2+ layers
  bool get hasMultipleLayers => _config.thresholds.length >= 2 && _config.enabled;

  // ─── Configuration ─────────────────────────────────────────────────────

  void loadConfig(MusicLayerConfig config) {
    _config = config;
    notifyListeners();
  }

  void reset() {
    _activeLayer = 1;
    _previousLayer = 1;
    _spinsSinceEscalation = 0;
    _isEscalated = false;
    _pendingWinRatio = null;
    _pendingResetToBase = false;
    _cancelRevertTimer();
    _history.clear();
    notifyListeners();
  }

  /// Reset to base layer (L1) state — called after BIG_WIN_END.
  /// BIG_WIN_END composite event restarts all layers with correct volumes
  /// (L1=1.0, L2-L5=0.0), so this only resets controller STATE.
  /// Also resets _layerVolumes so next crossfade knows correct start volumes.
  void resetToBaseLayer() {
    final previousActive = _activeLayer;
    _previousLayer = _activeLayer;
    _activeLayer = 1;
    _spinsSinceEscalation = 0;
    _isEscalated = false;

    // Reset layerVolumes to match restarted state (L1=1.0, rest=0.0)
    final playback = AudioPlaybackService.instance;
    for (final threshold in _config.thresholds) {
      final layerId = 'game_start_l${threshold.layer}';
      playback.layerVolumes[layerId] = threshold.layer == 1 ? 1.0 : 0.0;
    }

    if (previousActive != 1) {
      _addHistoryEvent(MusicLayerTransition(
        fromLayer: previousActive,
        toLayer: 1,
        reason: MusicLayerTransitionReason.revert,
        winRatio: 0.0,
        crossfadeMs: 0,
      ));
    }
    notifyListeners();
  }

  // ─── Core Evaluation — called after every spin ─────────────────────────

  /// Evaluate whether to switch music layer based on winRatio.
  /// Returns the layer transition if one occurred, null otherwise.
  /// [parentNotify] is called to propagate notifyListeners to SlotAudioProvider.
  MusicLayerTransition? evaluateAfterSpin(double winRatio, VoidCallback parentNotify) {
    if (!_config.enabled || _config.thresholds.length < 2) return null;

    // Sort thresholds descending by minWinRatio to find highest eligible layer
    final sorted = List<MusicLayerThreshold>.from(_config.thresholds)
      ..sort((a, b) => b.minWinRatio.compareTo(a.minWinRatio));

    // Find the highest layer whose threshold is met
    int targetLayer = 1; // Default: L1
    for (final threshold in sorted) {
      if (winRatio >= threshold.minWinRatio) {
        targetLayer = threshold.layer;
        break;
      }
    }

    final previousActive = _activeLayer;

    if (targetLayer > _activeLayer) {
      // ── ESCALATION ──
      _previousLayer = _activeLayer;
      _activeLayer = targetLayer;
      _spinsSinceEscalation = 0;
      _isEscalated = true;

      final transition = MusicLayerTransition(
        fromLayer: previousActive,
        toLayer: targetLayer,
        reason: MusicLayerTransitionReason.escalation,
        winRatio: winRatio,
        crossfadeMs: _config.upshiftFadeMs,
      );

      _addHistoryEvent(transition);
      _applyCrossfade(transition);
      // Reset revert timer on escalation (seconds mode)
      _cancelRevertTimer();
      _startRevertTimerIfNeeded(parentNotify);
      notifyListeners();
      parentNotify();
      return transition;

    } else if (_isEscalated) {
      // Currently escalated — check if threshold is still met
      final activeThreshold = _config.thresholds
          .where((t) => t.layer == _activeLayer)
          .firstOrNull;

      if (activeThreshold != null && winRatio >= activeThreshold.minWinRatio) {
        // Threshold still met — reset spin counter + reset timer
        _spinsSinceEscalation = 0;
        _cancelRevertTimer();
        _startRevertTimerIfNeeded(parentNotify);
        _addHistoryEvent(MusicLayerTransition(
          fromLayer: _activeLayer,
          toLayer: _activeLayer,
          reason: MusicLayerTransitionReason.sustained,
          winRatio: winRatio,
          crossfadeMs: 0,
        ));
        notifyListeners();
        parentNotify();
        return null;
      }

      // Threshold NOT met
      if (_config.revertMode == 'spins') {
        // ── SPIN-BASED REVERT ──
        _spinsSinceEscalation++;

        if (_spinsSinceEscalation >= _config.revertSpinCount) {
          return _doDeEscalation(previousActive, winRatio, parentNotify);
        }

        // Still counting down — no transition
        _addHistoryEvent(MusicLayerTransition(
          fromLayer: _activeLayer,
          toLayer: _activeLayer,
          reason: MusicLayerTransitionReason.countdown,
          winRatio: winRatio,
          crossfadeMs: 0,
          spinsRemaining: _config.revertSpinCount - _spinsSinceEscalation,
        ));
      } else {
        // ── SECONDS-BASED REVERT — timer handles de-escalation ──
        // Just log countdown, timer will fire when time's up
        _addHistoryEvent(MusicLayerTransition(
          fromLayer: _activeLayer,
          toLayer: _activeLayer,
          reason: MusicLayerTransitionReason.countdown,
          winRatio: winRatio,
          crossfadeMs: 0,
        ));
      }
      notifyListeners();
      parentNotify();
    } else {
      // ── IDLE — no escalation, no de-escalation ──
      // Covers targetLayer == _activeLayer (normal idle)
      // and targetLayer < _activeLayer with !_isEscalated (defensive)
      _addHistoryEvent(MusicLayerTransition(
        fromLayer: _activeLayer,
        toLayer: _activeLayer,
        reason: MusicLayerTransitionReason.idle,
        winRatio: winRatio,
        crossfadeMs: 0,
      ));
      notifyListeners();
      parentNotify();
    }

    return null;
  }

  // ─── De-escalation helper ─────────────────────────────────────────────

  MusicLayerTransition _doDeEscalation(int previousActive, double winRatio, VoidCallback parentNotify) {
    final revertTo = _activeLayer - 1;
    _previousLayer = _activeLayer;
    _activeLayer = revertTo;
    _spinsSinceEscalation = 0;
    _isEscalated = revertTo > 1;

    final transition = MusicLayerTransition(
      fromLayer: previousActive,
      toLayer: revertTo,
      reason: MusicLayerTransitionReason.revert,
      winRatio: winRatio,
      crossfadeMs: _config.downshiftFadeMs,
    );

    _addHistoryEvent(transition);
    _applyCrossfade(transition);
    _cancelRevertTimer();
    // If still escalated after stepping down, start new timer
    if (_isEscalated) {
      _startRevertTimerIfNeeded(parentNotify);
    }
    notifyListeners();
    parentNotify();
    return transition;
  }

  // ─── Revert Timer (seconds mode) ─────────────────────────────────────

  void _startRevertTimerIfNeeded(VoidCallback parentNotify) {
    if (_config.revertMode != 'seconds' || !_isEscalated) return;
    _cancelRevertTimer();
    final ms = (_config.revertSeconds * 1000).round();
    _revertTimer = Timer(Duration(milliseconds: ms), () {
      if (!_isEscalated) return;
      _doDeEscalation(_activeLayer, 0.0, parentNotify);
    });
  }

  void _cancelRevertTimer() {
    _revertTimer?.cancel();
    _revertTimer = null;
  }

  // ─── Crossfade Application ─────────────────────────────────────────────

  void _applyCrossfade(MusicLayerTransition transition) {
    final registry = EventRegistry.instance;
    final playback = AudioPlaybackService.instance;

    final hasGameStart = registry.hasEventForStage('GAME_START');
    final gameStartVoices = playback.voiceCountForLayer('game_start_l1');

    // Check if GAME_START composite voices exist
    if (gameStartVoices > 0) {
      _applyCrossfadeDirectly(transition, path: 'GAME_START voices=$gameStartVoices');
      return;
    }

    // No GAME_START voices — launch all layers directly via playLoopingToBus.
    // Start each layer at its CURRENT volume (fromLayer=1.0, others=0.0),
    // then let _applyCrossfadeDirectly crossfade to target volumes.
    //
    // Stop ALL existing music voices first (both standalone and previous GAME_START)
    registry.stopEventsByPrefix('MUSIC_BASE_L');
    registry.stopEvent('audio_GAME_START');
    for (int i = 1; i <= 5; i++) {
      playback.stopLayer('layer_MUSIC_BASE_L$i');
      playback.stopLayer('game_start_l$i');
    }

    final gsEvent = registry.getEventForStage('GAME_START');
    if (gsEvent == null) {
      _applyCrossfadeDirectly(transition, path: 'NO GAME_START event');
      return;
    }

    final diagParts = <String>[];
    for (final layer in gsEvent.layers) {
      if (layer.audioPath.isEmpty || layer.actionType != 'Play') continue;
      // Start at CURRENT state: fromLayer at 1.0, all others at 0.0
      final startVol = layer.id == 'game_start_l${transition.fromLayer}' ? 1.0 : 0.0;
      playback.layerVolumes[layer.id] = startVol;
      final voiceId = playback.playLoopingToBus(
        layer.audioPath,
        volume: startVol,
        busId: layer.busId,
        eventId: gsEvent.id,
        layerId: layer.id,
      );
      diagParts.add('${layer.id}=v$voiceId@$startVol');
    }

    // Now crossfade from current to target
    _applyCrossfadeDirectly(transition, path: 'DIRECT ${diagParts.join(", ")}');
  }

  /// Direct crossfade — finds actual voice IDs and sets volume via FFI.
  void _applyCrossfadeDirectly(MusicLayerTransition transition, {String path = ''}) {
    final playback = AudioPlaybackService.instance;
    final fadeMs = transition.crossfadeMs;
    final diagBuf = StringBuffer();
    diagBuf.writeln('PATH: $path');
    diagBuf.writeln('XF L${transition.fromLayer}→L${transition.toLayer} fade=${fadeMs}ms');
    diagBuf.writeln('activeVoices: ${playback.activeVoices.length} total');

    // Sync layerVolumes cache with actual engine state (all 5 layers).
    for (int i = 1; i <= 5; i++) {
      final layerId = 'game_start_l$i';
      if (!playback.layerVolumes.containsKey(layerId)) {
        final initVol = i == _previousLayer
            ? 1.0
            : (i == 1 ? 1.0 : 0.0);
        playback.layerVolumes[layerId] = initVol;
        diagBuf.writeln('  INIT $layerId=$initVol');
      }
    }

    // Log all active voice layerIds for debugging
    final layerIds = playback.activeVoices.map((v) => '${v.layerId}(v${v.voiceId})').toSet();
    diagBuf.writeln('voices: ${layerIds.join(', ')}');

    // Iterate ALL 5 possible layers (not just config thresholds) to ensure
    // no orphaned voice stays at wrong volume
    for (int layer = 1; layer <= 5; layer++) {
      final layerId = 'game_start_l$layer';
      final targetVolume = layer == transition.toLayer ? 1.0 : 0.0;
      final startVol = playback.layerVolumes[layerId] ?? -1.0;

      // Find voice by layerId directly in active voices
      final voices = playback.activeVoices
          .where((v) => v.layerId == layerId)
          .toList();

      if (voices.isNotEmpty) {
        diagBuf.writeln('  L$layer: ${voices.length}v start=$startVol→$targetVolume');
        if (fadeMs > 0) {
          playback.fadeLayerVolume(layerId, targetVolume, fadeMs: fadeMs);
        } else {
          for (final v in voices) {
            playback.setVoiceVolume(v.voiceId, targetVolume);
          }
          playback.layerVolumes[layerId] = targetVolume;
        }
      } else {
        diagBuf.writeln('  L$layer: NO VOICES → cache=$targetVolume');
        playback.layerVolumes[layerId] = targetVolume;
      }
    }

    _lastCrossfadeDiag = diagBuf.toString();
    notifyListeners();
  }

  // ─── History ───────────────────────────────────────────────────────────

  void _addHistoryEvent(MusicLayerTransition transition) {
    _history.add(MusicLayerEvent(
      timestamp: DateTime.now(),
      transition: transition,
      activeLayer: _activeLayer,
      spinsSinceEscalation: _spinsSinceEscalation,
    ));
    // Keep last 100 entries
    if (_history.length > 100) {
      _history.removeRange(0, _history.length - 100);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MUSIC LAYER DATA TYPES
// ═══════════════════════════════════════════════════════════════════════════════

enum MusicLayerTransitionReason {
  /// Win threshold exceeded — escalate to higher layer
  escalation,
  /// Threshold no longer met after N spins — revert to previous
  revert,
  /// Threshold still met — reset countdown
  sustained,
  /// Threshold not met — counting down to revert
  countdown,
  /// No change — winRatio below all escalation thresholds (base layer)
  idle,
}

class MusicLayerTransition {
  final int fromLayer;
  final int toLayer;
  final MusicLayerTransitionReason reason;
  final double winRatio;
  final int crossfadeMs;
  final int? spinsRemaining;

  const MusicLayerTransition({
    required this.fromLayer,
    required this.toLayer,
    required this.reason,
    required this.winRatio,
    required this.crossfadeMs,
    this.spinsRemaining,
  });
}

class MusicLayerEvent {
  final DateTime timestamp;
  final MusicLayerTransition transition;
  final int activeLayer;
  final int spinsSinceEscalation;

  const MusicLayerEvent({
    required this.timestamp,
    required this.transition,
    required this.activeLayer,
    required this.spinsSinceEscalation,
  });
}
