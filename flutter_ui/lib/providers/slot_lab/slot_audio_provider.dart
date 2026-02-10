/// Slot Audio Provider — Audio playback orchestration
///
/// Part of P12.1.7 SlotLabProvider decomposition.
/// Handles:
/// - Section management (acquire/release playback section)
/// - Event triggering (via EventRegistry)
/// - Audio settings (volumes, mutes)
/// - Playback state (auto trigger, etc.)
/// - ALE signal sync
library;

import 'package:flutter/foundation.dart';

import '../../services/event_registry.dart';
import '../../services/audio_asset_manager.dart';
import '../../services/stage_audio_mapper.dart';
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
  StageAudioMapper? _audioMapper;
  AleProvider? _aleProvider;

  // ─── Configuration ──────────────────────────────────────────────────────
  bool _autoTriggerAudio = true;
  bool _aleAutoSync = true;
  double _betAmount = 1.0;
  int _totalReels = 5;

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

  int get persistedLowerZoneTabIndex => _persistedLowerZoneTabIndex;
  bool get persistedLowerZoneExpanded => _persistedLowerZoneExpanded;
  double get persistedLowerZoneHeight => _persistedLowerZoneHeight;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Connect middleware for audio triggering
  void connectMiddleware(MiddlewareProvider middleware) {
    _middleware = middleware;
    _audioMapper = StageAudioMapper(middleware, _ffi);
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

  /// Sync Slot Lab state to ALE signals
  void syncAleSignals(SlotLabSpinResult? result, double hitRate, bool inFreeSpins, int freeSpinsRemaining, int spinCount, double volatilitySlider, List<SlotLabStageEvent> lastStages) {
    if (!_aleAutoSync || _aleProvider == null || !_aleProvider!.initialized) {
      return;
    }

    if (result == null) return;

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
        s.stageType.toUpperCase() == 'ANTICIPATION_ON').length;
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
        effectiveStage = 'ANTICIPATION_ON';
      }
      volumeMultiplier = 1.0;
    } else if (combinedIntensity >= 0.5) {
      if (eventRegistry.hasEventForStage('ANTICIPATION_HIGH')) {
        effectiveStage = 'ANTICIPATION_HIGH';
      } else {
        effectiveStage = 'ANTICIPATION_ON';
      }
      volumeMultiplier = 0.9;
    } else {
      effectiveStage = 'ANTICIPATION_ON';
      volumeMultiplier = 0.7 + (combinedIntensity * 0.3);
    }

    return (effectiveStage: effectiveStage, volumeMultiplier: volumeMultiplier);
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
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    super.dispose();
  }
}
