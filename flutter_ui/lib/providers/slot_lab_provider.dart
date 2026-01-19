/// Slot Lab Provider — State management for Synthetic Slot Engine
///
/// Integrates rf-slot-lab Rust crate with Flutter UI:
/// - Engine lifecycle (init/shutdown)
/// - Spin execution and results
/// - Stage event generation and audio triggering
/// - Session statistics
/// - Configuration (volatility, timing, features)
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/stage_models.dart';
import '../services/stage_audio_mapper.dart';
import '../services/event_registry.dart';
import '../src/rust/native_ffi.dart';
import 'middleware_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SLOT LAB PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for Synthetic Slot Engine state management
class SlotLabProvider extends ChangeNotifier {
  final NativeFFI _ffi = NativeFFI.instance;

  // ─── Engine State ──────────────────────────────────────────────────────────
  bool _initialized = false;
  bool _isSpinning = false;
  int _spinCount = 0;

  // ─── Last Spin Result ──────────────────────────────────────────────────────
  SlotLabSpinResult? _lastResult;
  List<SlotLabStageEvent> _lastStages = [];

  // ─── Session Stats ─────────────────────────────────────────────────────────
  SlotLabStats? _stats;
  double _rtp = 0.0;
  double _hitRate = 0.0;

  // ─── Configuration ─────────────────────────────────────────────────────────
  double _volatilitySlider = 0.5;
  VolatilityPreset _volatilityPreset = VolatilityPreset.medium;
  TimingProfileType _timingProfile = TimingProfileType.normal;
  double _betAmount = 1.0;
  bool _cascadesEnabled = true;
  bool _freeSpinsEnabled = true;
  bool _jackpotEnabled = true;

  // ─── Free Spins State ──────────────────────────────────────────────────────
  bool _inFreeSpins = false;
  int _freeSpinsRemaining = 0;

  // ─── Audio Integration ─────────────────────────────────────────────────────
  MiddlewareProvider? _middleware;
  StageAudioMapper? _audioMapper;
  bool _autoTriggerAudio = true;

  // ─── Stage Event Playback ──────────────────────────────────────────────────
  Timer? _stagePlaybackTimer;
  int _currentStageIndex = 0;
  bool _isPlayingStages = false;

  // ─── Persistent UI State (survives screen switches) ───────────────────────
  List<Map<String, dynamic>> persistedAudioPool = [];
  List<Map<String, dynamic>> persistedCompositeEvents = [];
  List<Map<String, dynamic>> persistedTracks = [];
  Map<String, String> persistedEventToRegionMap = {};

  // ─── Waveform Cache (survives screen switches) ────────────────────────────
  /// Cache of waveform data by audio path - persists across navigation
  final Map<String, List<double>> waveformCache = {};
  /// Cache of FFI clip IDs by audio path - persists across navigation
  final Map<String, int> clipIdCache = {};

  /// Clear all persisted UI state (use when data is corrupted)
  void clearPersistedState() {
    persistedAudioPool.clear();
    persistedCompositeEvents.clear();
    persistedTracks.clear();
    persistedEventToRegionMap.clear();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get initialized => _initialized;
  bool get isSpinning => _isSpinning;
  int get spinCount => _spinCount;

  SlotLabSpinResult? get lastResult => _lastResult;
  List<SlotLabStageEvent> get lastStages => _lastStages;

  SlotLabStats? get stats => _stats;
  double get rtp => _rtp;
  double get hitRate => _hitRate;

  double get volatilitySlider => _volatilitySlider;
  VolatilityPreset get volatilityPreset => _volatilityPreset;
  TimingProfileType get timingProfile => _timingProfile;
  double get betAmount => _betAmount;
  bool get cascadesEnabled => _cascadesEnabled;
  bool get freeSpinsEnabled => _freeSpinsEnabled;
  bool get jackpotEnabled => _jackpotEnabled;

  bool get inFreeSpins => _inFreeSpins;
  int get freeSpinsRemaining => _freeSpinsRemaining;

  bool get autoTriggerAudio => _autoTriggerAudio;
  bool get isPlayingStages => _isPlayingStages;
  int get currentStageIndex => _currentStageIndex;

  /// Get the current grid (5x3 symbol IDs)
  List<List<int>>? get currentGrid => _lastResult?.grid;

  /// Check if last spin was a win
  bool get lastSpinWasWin => _lastResult?.isWin ?? false;

  /// Get last win amount
  double get lastWinAmount => _lastResult?.totalWin ?? 0.0;

  /// Get last win ratio (multiplier)
  double get lastWinRatio => _lastResult?.winRatio ?? 0.0;

  /// Get big win tier from last spin
  SlotLabWinTier? get lastBigWinTier => _lastResult?.bigWinTier;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize the slot engine
  bool initialize({bool audioTestMode = false}) {
    if (_initialized) {
      debugPrint('[SlotLabProvider] Already initialized');
      return true;
    }

    final success = audioTestMode
        ? _ffi.slotLabInitAudioTest()
        : _ffi.slotLabInit();

    if (success) {
      _initialized = true;
      _updateStats();
      debugPrint('[SlotLabProvider] Engine initialized (audioTest: $audioTestMode)');
      notifyListeners();
    } else {
      debugPrint('[SlotLabProvider] Failed to initialize engine');
    }

    return success;
  }

  /// Shutdown the engine
  void shutdown() {
    if (!_initialized) return;

    _stagePlaybackTimer?.cancel();
    _ffi.slotLabShutdown();
    _initialized = false;
    _lastResult = null;
    _lastStages = [];
    _stats = null;
    _spinCount = 0;
    debugPrint('[SlotLabProvider] Engine shutdown');
    notifyListeners();
  }

  /// Connect middleware for audio triggering
  void connectMiddleware(MiddlewareProvider middleware) {
    _middleware = middleware;
    _audioMapper = StageAudioMapper(middleware, _ffi);
    debugPrint('[SlotLabProvider] Middleware connected');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set volatility by slider (0.0 = low, 1.0 = high)
  void setVolatilitySlider(double value) {
    _volatilitySlider = value.clamp(0.0, 1.0);
    if (_initialized) {
      _ffi.slotLabSetVolatilitySlider(_volatilitySlider);
    }
    notifyListeners();
  }

  /// Set volatility preset
  void setVolatilityPreset(VolatilityPreset preset) {
    _volatilityPreset = preset;
    if (_initialized) {
      _ffi.slotLabSetVolatilityPreset(preset);
    }
    // Update slider to match
    _volatilitySlider = preset.value / 3.0;
    notifyListeners();
  }

  /// Set timing profile
  void setTimingProfile(TimingProfileType profile) {
    _timingProfile = profile;
    if (_initialized) {
      _ffi.slotLabSetTimingProfile(profile);
    }
    notifyListeners();
  }

  /// Set bet amount
  void setBetAmount(double bet) {
    _betAmount = bet.clamp(0.01, 1000.0);
    if (_initialized) {
      _ffi.slotLabSetBet(_betAmount);
    }
    notifyListeners();
  }

  /// Enable/disable cascades
  void setCascadesEnabled(bool enabled) {
    _cascadesEnabled = enabled;
    if (_initialized) {
      _ffi.slotLabSetCascadesEnabled(enabled);
    }
    notifyListeners();
  }

  /// Enable/disable free spins
  void setFreeSpinsEnabled(bool enabled) {
    _freeSpinsEnabled = enabled;
    if (_initialized) {
      _ffi.slotLabSetFreeSpinsEnabled(enabled);
    }
    notifyListeners();
  }

  /// Enable/disable jackpot
  void setJackpotEnabled(bool enabled) {
    _jackpotEnabled = enabled;
    if (_initialized) {
      _ffi.slotLabSetJackpotEnabled(enabled);
    }
    notifyListeners();
  }

  /// Set auto audio triggering
  void setAutoTriggerAudio(bool enabled) {
    _autoTriggerAudio = enabled;
    notifyListeners();
  }

  /// Seed RNG for reproducible results
  void seedRng(int seed) {
    if (_initialized) {
      _ffi.slotLabSeedRng(seed);
      debugPrint('[SlotLabProvider] RNG seeded: $seed');
    }
  }

  /// Reset session stats
  void resetStats() {
    if (_initialized) {
      _ffi.slotLabResetStats();
      _updateStats();
      _spinCount = 0;
    }
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPIN EXECUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Execute a random spin
  Future<SlotLabSpinResult?> spin() async {
    if (!_initialized || _isSpinning) return null;

    _isSpinning = true;
    notifyListeners();

    try {
      final spinId = _ffi.slotLabSpin();
      if (spinId == 0) {
        _isSpinning = false;
        notifyListeners();
        return null;
      }

      _spinCount++;
      _lastResult = _ffi.slotLabGetSpinResult();
      _lastStages = _ffi.slotLabGetStages();
      _updateFreeSpinsState();
      _updateStats();

      debugPrint('[SlotLabProvider] Spin #$_spinCount: win=${_lastResult?.isWin}, '
          'amount=${_lastResult?.totalWin.toStringAsFixed(2)}, '
          'stages=${_lastStages.length}');

      // Auto-trigger audio if enabled
      if (_autoTriggerAudio && _lastStages.isNotEmpty) {
        _playStagesSequentially();
      }

      _isSpinning = false;
      notifyListeners();
      return _lastResult;
    } catch (e) {
      debugPrint('[SlotLabProvider] Spin error: $e');
      _isSpinning = false;
      notifyListeners();
      return null;
    }
  }

  /// Execute a forced spin with specific outcome
  Future<SlotLabSpinResult?> spinForced(ForcedOutcome outcome) async {
    if (!_initialized || _isSpinning) return null;

    _isSpinning = true;
    notifyListeners();

    try {
      final spinId = _ffi.slotLabSpinForced(outcome);
      if (spinId == 0) {
        _isSpinning = false;
        notifyListeners();
        return null;
      }

      _spinCount++;
      _lastResult = _ffi.slotLabGetSpinResult();
      _lastStages = _ffi.slotLabGetStages();
      _updateFreeSpinsState();
      _updateStats();

      debugPrint('[SlotLabProvider] Forced spin #$_spinCount (${outcome.name}): '
          'win=${_lastResult?.isWin}, stages=${_lastStages.length}');

      // Auto-trigger audio if enabled
      if (_autoTriggerAudio && _lastStages.isNotEmpty) {
        _playStagesSequentially();
      }

      _isSpinning = false;
      notifyListeners();
      return _lastResult;
    } catch (e) {
      debugPrint('[SlotLabProvider] Forced spin error: $e');
      _isSpinning = false;
      notifyListeners();
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE PLAYBACK & AUDIO TRIGGERING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Play stages sequentially with timing
  void _playStagesSequentially() {
    if (_lastStages.isEmpty) return;

    _stagePlaybackTimer?.cancel();
    _currentStageIndex = 0;
    _isPlayingStages = true;

    debugPrint('[SlotLabProvider] Playing ${_lastStages.length} stages sequentially');

    // Trigeruj prvi stage odmah
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
      notifyListeners();
      return;
    }

    final currentStage = _lastStages[_currentStageIndex];
    final nextStage = _lastStages[_currentStageIndex + 1];
    final delayMs = (nextStage.timestampMs - currentStage.timestampMs).toInt();

    _stagePlaybackTimer = Timer(Duration(milliseconds: delayMs.clamp(10, 5000)), () {
      if (!_isPlayingStages) return;

      _currentStageIndex++;
      _triggerStage(_lastStages[_currentStageIndex]);
      notifyListeners();

      _scheduleNextStage();
    });
  }

  /// Trigger audio for a stage event
  /// CRITICAL: Uses ONLY EventRegistry. Legacy systems DISABLED to prevent duplicate audio.
  void _triggerStage(SlotLabStageEvent stage) {
    final stageType = stage.stageType.toUpperCase();
    final reelIndex = stage.payload['reel_index'];

    debugPrint('[SlotLabProvider] _triggerStage: $stageType ${reelIndex != null ? "(reel $reelIndex)" : ""} @ ${stage.timestampMs.toStringAsFixed(0)}ms');

    // ═══════════════════════════════════════════════════════════════════════════
    // CENTRALNI EVENT REGISTRY — JEDINI izvor audio playback-a
    // Legacy sistemi (Middleware postEvent, StageAudioMapper) su ONEMOGUĆENI
    // jer izazivaju dupli audio playback
    // ═══════════════════════════════════════════════════════════════════════════

    // Za REEL_STOP, koristi specifičan stage po reel-u: REEL_STOP_0, REEL_STOP_1, itd.
    String effectiveStage = stageType;
    if (stageType == 'REEL_STOP' && reelIndex != null) {
      effectiveStage = 'REEL_STOP_$reelIndex';
    }

    // Probaj specifičan stage prvo, pa fallback na generički
    if (eventRegistry.hasEventForStage(effectiveStage)) {
      eventRegistry.triggerStage(effectiveStage, context: stage.payload);
      debugPrint('[SlotLabProvider] Registry trigger: $effectiveStage');
    } else if (effectiveStage != stageType && eventRegistry.hasEventForStage(stageType)) {
      // Fallback na generički REEL_STOP ako nema specifičnog
      eventRegistry.triggerStage(stageType, context: stage.payload);
      debugPrint('[SlotLabProvider] Registry trigger (fallback): $stageType');
    } else if (eventRegistry.hasEventForStage(stageType)) {
      eventRegistry.triggerStage(stageType, context: stage.payload);
      debugPrint('[SlotLabProvider] Registry trigger: $stageType');
    } else {
      debugPrint('[SlotLabProvider] No registry event for: $effectiveStage');
    }

    // Za SPIN_START, trigeruj i REEL_SPIN (loop audio dok se vrti)
    if (stageType == 'SPIN_START' && eventRegistry.hasEventForStage('REEL_SPIN')) {
      eventRegistry.triggerStage('REEL_SPIN', context: stage.payload);
      debugPrint('[SlotLabProvider] Registry trigger: REEL_SPIN (started)');
    }

    // Za poslednji REEL_STOP (reel 4), zaustavi REEL_SPIN
    if (stageType == 'REEL_STOP' && reelIndex == 4) {
      eventRegistry.stopEvent('REEL_SPIN');
      debugPrint('[SlotLabProvider] REEL_SPIN stopped (last reel landed)');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LEGACY SISTEMI — ONEMOGUĆENI (uzrokuju dupli audio)
    // ═══════════════════════════════════════════════════════════════════════════
    // DISABLED: Middleware postEvent causes duplicate audio playback
    // if (_middleware != null) {
    //   final eventId = _mapStageToEventId(stage);
    //   if (eventId != null) {
    //     final context = _buildStageContext(stage);
    //     _middleware!.postEvent(eventId, context: context);
    //   }
    // }

    // DISABLED: StageAudioMapper causes duplicate audio playback
    // final stageEvent = _convertToStageEvent(stage);
    // if (stageEvent != null) {
    //   _audioMapper?.mapAndTrigger(stageEvent);
    // }
  }

  /// Convert SlotLabStageEvent to StageEvent (for StageAudioMapper)
  StageEvent? _convertToStageEvent(SlotLabStageEvent slotLabStage) {
    final stageObj = _mapStageType(slotLabStage.stageType, slotLabStage.rawStage);
    if (stageObj == null) return null;

    return StageEvent(
      stage: stageObj,
      timestampMs: slotLabStage.timestampMs,
      payload: StagePayload(
        winAmount: slotLabStage.payload['win_amount'] as double?,
        betAmount: _betAmount,
        winRatio: slotLabStage.payload['win_ratio'] as double?,
      ),
    );
  }

  Stage? _mapStageType(String type, Map<String, dynamic> data) {
    // Use Stage.fromJson which handles the sealed class types
    return Stage.fromTypeName(type, data);
  }

  String? _mapStageToEventId(SlotLabStageEvent stage) {
    // Map stage types to middleware event IDs
    switch (stage.stageType) {
      case 'spin_start': return 'slot_spin_start';
      case 'reel_spinning': return 'slot_reel_spin';
      case 'reel_stop': return 'slot_reel_stop';
      case 'evaluate_wins': return null; // Internal, no audio
      case 'spin_end': return 'slot_spin_end';
      case 'anticipation_on': return 'slot_anticipation_on';
      case 'anticipation_off': return 'slot_anticipation_off';
      case 'win_present': return 'slot_win_present';
      case 'win_line_show': return 'slot_win_line';
      case 'rollup_start': return 'slot_rollup_start';
      case 'rollup_tick': return 'slot_rollup_tick';
      case 'rollup_end': return 'slot_rollup_end';
      case 'bigwin_tier':
        // Get tier from raw stage data
        final tierData = stage.rawStage['tier'];
        if (tierData is String) {
          switch (tierData) {
            case 'win': return 'slot_bigwin_tier_nice';
            case 'big_win': return 'slot_bigwin_tier_super';
            case 'mega_win': return 'slot_bigwin_tier_mega';
            case 'epic_win': return 'slot_bigwin_tier_epic';
            case 'ultra_win': return 'slot_bigwin_tier_ultra';
          }
        }
        return 'slot_bigwin';
      case 'feature_enter': return 'slot_feature_start';
      case 'feature_step': return 'slot_feature_spin';
      case 'feature_exit': return 'slot_feature_end';
      case 'cascade_start': return 'slot_cascade_start';
      case 'cascade_step': return 'slot_cascade_step';
      case 'cascade_end': return 'slot_cascade_end';
      case 'jackpot_trigger': return 'slot_jackpot_trigger';
      case 'jackpot_present': return 'slot_jackpot_present';
      default: return null;
    }
  }

  Map<String, dynamic> _buildStageContext(SlotLabStageEvent stage) {
    final context = <String, dynamic>{
      'bet_amount': _betAmount,
      'stage_type': stage.stageType,
      'timestamp_ms': stage.timestampMs,
    };

    // Add result data if available
    if (_lastResult != null) {
      context['win_amount'] = _lastResult!.totalWin;
      context['win_ratio'] = _lastResult!.winRatio;
      context['is_win'] = _lastResult!.isWin;
    }

    // Add payload data
    context.addAll(stage.payload);

    return context;
  }

  /// Stop stage playback
  void stopStagePlayback() {
    _stagePlaybackTimer?.cancel();
    _isPlayingStages = false;
    notifyListeners();
  }

  /// Manually trigger a specific stage event
  void triggerStageManually(int stageIndex) {
    if (stageIndex >= 0 && stageIndex < _lastStages.length) {
      _triggerStage(_lastStages[stageIndex]);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _updateStats() {
    if (!_initialized) return;

    _stats = _ffi.slotLabGetStats();
    _rtp = _ffi.slotLabGetRtp();
    _hitRate = _ffi.slotLabGetHitRate();
  }

  void _updateFreeSpinsState() {
    if (!_initialized) return;

    _inFreeSpins = _ffi.slotLabInFreeSpins();
    _freeSpinsRemaining = _ffi.slotLabFreeSpinsRemaining();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIG EXPORT/IMPORT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Export current config as JSON
  String? exportConfig() {
    if (!_initialized) return null;
    return _ffi.slotLabExportConfig();
  }

  /// Import config from JSON
  bool importConfig(String json) {
    if (!_initialized) return false;
    final success = _ffi.slotLabImportConfig(json);
    if (success) {
      notifyListeners();
    }
    return success;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _stagePlaybackTimer?.cancel();
    shutdown();
    super.dispose();
  }
}
