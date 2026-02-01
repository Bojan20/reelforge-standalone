/// Slot Engine Provider — Synthetic Slot Engine state management
///
/// Part of P12.1.7 SlotLabProvider decomposition.
/// Handles:
/// - Engine lifecycle (init/shutdown)
/// - Spin execution (spin, spinForced, spinP5)
/// - Grid configuration (updateGridSize, setVolatility)
/// - Game model (GDD import, config)
/// - Session statistics
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../models/stage_models.dart';
import '../../models/win_tier_config.dart';
import '../../services/audio_pool.dart';
import '../../services/win_analytics_service.dart';
import '../../src/rust/native_ffi.dart';
import '../../src/rust/slot_lab_v2_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SLOT ENGINE PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for Synthetic Slot Engine state management
/// Handles engine lifecycle, spin execution, and configuration.
class SlotEngineProvider extends ChangeNotifier {
  final NativeFFI _ffi = NativeFFI.instance;

  // ─── Engine State ──────────────────────────────────────────────────────────
  bool _initialized = false;
  bool _isSpinning = false;
  int _spinCount = 0;

  // ─── Last Spin Result ──────────────────────────────────────────────────────
  SlotLabSpinResult? _lastResult;
  List<SlotLabStageEvent> _lastStages = [];
  String? _cachedStagesSpinId;

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

  // ─── Win Tier Configuration ────────────────────────────────────────────────
  WinTierConfig _winTierConfig = DefaultWinTierConfigs.standard;

  // ─── Audio Timing Configuration ─────────────────────────────────────────────
  SlotLabTimingConfig? _timingConfig;
  int _anticipationPreTriggerMs = 0;
  int _reelStopPreTriggerMs = 0;

  // ─── P5 Win Tier Integration ─────────────────────────────────────────────────
  bool _useP5WinTier = true;

  // ─── Free Spins State ──────────────────────────────────────────────────────
  bool _inFreeSpins = false;
  int _freeSpinsRemaining = 0;

  // ─── Grid Configuration ─────────────────────────────────────────────────────
  int _totalReels = 5;
  int _totalRows = 3;

  // ─── Engine V2 State ──────────────────────────────────────────────────────
  bool _engineV2Initialized = false;
  Map<String, dynamic>? _currentGameModel;
  List<ScenarioInfo> _availableScenarios = [];
  String? _loadedScenarioId;

  // ─── Callbacks ──────────────────────────────────────────────────────────────
  /// Callback when grid dimensions change (P0 WF-03)
  void Function(int newReelCount)? onGridDimensionsChanged;

  /// Callback when spin completes — coordinator uses this to trigger stage playback
  void Function(SlotLabSpinResult result, List<SlotLabStageEvent> stages)? onSpinComplete;

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get initialized => _initialized;
  bool get isSpinning => _isSpinning;
  int get spinCount => _spinCount;

  SlotLabSpinResult? get lastResult => _lastResult;
  List<SlotLabStageEvent> get lastStages => _lastStages;
  String? get cachedStagesSpinId => _cachedStagesSpinId;

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

  WinTierConfig get winTierConfig => _winTierConfig;
  SlotLabTimingConfig? get timingConfig => _timingConfig;
  int get anticipationPreTriggerMs => _anticipationPreTriggerMs;
  int get reelStopPreTriggerMs => _reelStopPreTriggerMs;
  double get totalAudioOffsetMs => _timingConfig?.totalAudioOffsetMs ?? 5.0;

  bool get useP5WinTier => _useP5WinTier;
  bool get inFreeSpins => _inFreeSpins;
  int get freeSpinsRemaining => _freeSpinsRemaining;

  int get totalReels => _totalReels;
  int get totalRows => _totalRows;

  bool get engineV2Initialized => _engineV2Initialized;
  Map<String, dynamic>? get currentGameModel => _currentGameModel;
  List<ScenarioInfo> get availableScenarios => _availableScenarios;
  String? get loadedScenarioId => _loadedScenarioId;

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
      debugPrint('[SlotEngineProvider] Already initialized');
      return true;
    }

    final success = audioTestMode
        ? _ffi.slotLabInitAudioTest()
        : _ffi.slotLabInit();

    if (success) {
      _initialized = true;
      _updateStats();
      _loadTimingConfig();

      // Configure AudioPool for Slot Lab rapid-fire events
      AudioPool.instance.configure(AudioPoolConfig.slotLabConfig);
      AudioPool.instance.preloadSlotLabEvents();

      debugPrint('[SlotEngineProvider] Engine initialized (audioTest: $audioTestMode)');
      notifyListeners();
    } else {
      debugPrint('[SlotEngineProvider] Failed to initialize engine');
    }

    return success;
  }

  /// Shutdown the engine
  void shutdown() {
    if (!_initialized) return;

    _ffi.slotLabShutdown();
    _initialized = false;
    _lastResult = null;
    _lastStages = [];
    _stats = null;
    _spinCount = 0;
    debugPrint('[SlotEngineProvider] Engine shutdown');
    notifyListeners();
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
    _volatilitySlider = preset.value / 3.0;
    notifyListeners();
  }

  /// Set timing profile
  void setTimingProfile(TimingProfileType profile) {
    _timingProfile = profile;
    if (_initialized) {
      _ffi.slotLabSetTimingProfile(profile);
      _loadTimingConfig();
    }
    notifyListeners();
  }

  /// Load timing configuration from Rust engine
  void _loadTimingConfig() {
    _timingConfig = _ffi.slotLabGetTimingConfig();
    if (_timingConfig != null) {
      _anticipationPreTriggerMs = _timingConfig!.anticipationAudioPreTriggerMs.round();
      _reelStopPreTriggerMs = _timingConfig!.reelStopAudioPreTriggerMs.round();
      debugPrint('[SlotEngineProvider] Timing config loaded: '
          'latency=${_timingConfig!.audioLatencyCompensationMs}ms, '
          'syncOffset=${_timingConfig!.visualAudioSyncOffsetMs}ms');
    } else {
      _timingConfig = SlotLabTimingConfig.studio();
      debugPrint('[SlotEngineProvider] Using default studio timing config');
    }
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

  /// Set win tier configuration
  void setWinTierConfig(WinTierConfig config) {
    _winTierConfig = config;
    notifyListeners();
  }

  /// Enable/disable P5 win tier evaluation
  void setUseP5WinTier(bool enabled) {
    _useP5WinTier = enabled;
    debugPrint('[SlotEngineProvider] P5 Win Tier mode: ${enabled ? "ENABLED" : "DISABLED"}');
    notifyListeners();
  }

  /// Set anticipation pre-trigger offset in ms
  void setAnticipationPreTriggerMs(int ms) {
    _anticipationPreTriggerMs = ms.clamp(0, 200);
    debugPrint('[SlotEngineProvider] Anticipation pre-trigger: ${_anticipationPreTriggerMs}ms');
    notifyListeners();
  }

  /// Seed RNG for reproducible results
  void seedRng(int seed) {
    if (_initialized) {
      _ffi.slotLabSeedRng(seed);
      debugPrint('[SlotEngineProvider] RNG seeded: $seed');
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

  // ─── Grid Configuration ─────────────────────────────────────────────────────

  /// Update grid dimensions (called from Feature Builder)
  void updateGridSize(int reels, int rows) {
    if (reels != _totalReels || rows != _totalRows) {
      _totalReels = reels;
      _totalRows = rows;
      debugPrint('[SlotEngineProvider] Grid updated: ${reels}x$rows');

      if (_initialized) {
        _reinitializeEngine();
      }

      notifyListeners();
    }
  }

  /// Reinitialize the Rust engine with current configuration
  void _reinitializeEngine() {
    try {
      debugPrint('[SlotEngineProvider] Engine will use new grid on next spin');
    } catch (e) {
      debugPrint('[SlotEngineProvider] Engine reinitialization error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WIN TIER HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get the visual tier name for a win amount
  String getVisualTierForWin(double winAmount) {
    if (_betAmount <= 0) return '';
    final tier = _winTierConfig.getTierForWin(winAmount, _betAmount);
    if (tier == null) return '';

    switch (tier.tier) {
      case WinTier.noWin:
      case WinTier.smallWin:
      case WinTier.mediumWin:
        return '';
      case WinTier.bigWin:
        return 'BIG_WIN_TIER_1';
      case WinTier.megaWin:
        return 'BIG_WIN_TIER_2';
      case WinTier.epicWin:
        return 'BIG_WIN_TIER_3';
      case WinTier.ultraWin:
        return 'BIG_WIN_TIER_4';
      case WinTier.jackpotMini:
        return 'JACKPOT MINI';
      case WinTier.jackpotMinor:
        return 'JACKPOT MINOR';
      case WinTier.jackpotMajor:
        return 'JACKPOT MAJOR';
      case WinTier.jackpotGrand:
        return 'JACKPOT GRAND';
    }
  }

  /// Get RTPC value for a win amount (0.0 to 1.0)
  double getRtpcForWin(double winAmount) {
    return _winTierConfig.getRtpcForWin(winAmount, _betAmount);
  }

  /// Check if a win should trigger celebration animation
  bool shouldTriggerCelebration(double winAmount) {
    final tier = _winTierConfig.getTierForWin(winAmount, _betAmount);
    return tier?.triggerCelebration ?? false;
  }

  /// Get rollup duration multiplier for a win
  double getRollupMultiplier(double winAmount) {
    final tier = _winTierConfig.getTierForWin(winAmount, _betAmount);
    return tier?.rollupDurationMultiplier ?? 1.0;
  }

  /// Get the stage to trigger for a win
  String? getTriggerStageForWin(double winAmount) {
    final tier = _winTierConfig.getTierForWin(winAmount, _betAmount);
    return tier?.triggerStage;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPIN EXECUTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Execute a random spin
  Future<SlotLabSpinResult?> spin() async {
    debugPrint('[SlotEngineProvider] spin() called: initialized=$_initialized, isSpinning=$_isSpinning');

    if (!_initialized || _isSpinning) {
      debugPrint('[SlotEngineProvider] spin() BLOCKED');
      return null;
    }

    _isSpinning = true;
    notifyListeners();

    try {
      final int spinId;
      if (_engineV2Initialized) {
        debugPrint('[SlotEngineProvider] Calling FFI slotLabV2Spin()...');
        spinId = _ffi.slotLabV2Spin();
      } else if (_useP5WinTier) {
        debugPrint('[SlotEngineProvider] Calling FFI slotLabSpinP5()...');
        spinId = _ffi.slotLabSpinP5();
      } else {
        debugPrint('[SlotEngineProvider] Calling FFI slotLabSpin()...');
        spinId = _ffi.slotLabSpin();
      }

      if (spinId == 0) {
        debugPrint('[SlotEngineProvider] spinId=0, aborting');
        _isSpinning = false;
        notifyListeners();
        return null;
      }

      _spinCount++;
      WinAnalyticsService.instance.trackSpin();

      // Get results from appropriate engine
      if (_engineV2Initialized) {
        _lastResult = _convertV2Result(_ffi.slotLabV2GetSpinResult());
        _lastStages = _convertV2Stages(_ffi.slotLabV2GetStages());
      } else {
        _lastResult = _ffi.slotLabGetSpinResult();
        _lastStages = _ffi.slotLabGetStages();
      }

      _cachedStagesSpinId = _lastResult?.spinId;
      _updateFreeSpinsState();
      _updateStats();

      final win = _lastResult?.totalWin ?? 0;
      final isWin = _lastResult?.isWin ?? false;
      debugPrint('[Spin #$_spinCount] ${isWin ? "WIN \$${win.toStringAsFixed(2)}" : "no win"} | ${_lastStages.length} stages');

      // Notify coordinator to trigger stage playback
      if (_lastResult != null) {
        onSpinComplete?.call(_lastResult!, _lastStages);
      }

      _isSpinning = false;
      notifyListeners();
      return _lastResult;
    } catch (e) {
      debugPrint('[SlotEngineProvider] Spin error: $e');
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
      final int spinId;
      if (_engineV2Initialized) {
        spinId = _ffi.slotLabV2SpinForced(outcome.index);
      } else if (_useP5WinTier) {
        spinId = _ffi.slotLabSpinForcedP5(outcome);
      } else {
        spinId = _ffi.slotLabSpinForced(outcome);
      }

      if (spinId == 0) {
        _isSpinning = false;
        notifyListeners();
        return null;
      }

      _spinCount++;

      if (_engineV2Initialized) {
        _lastResult = _convertV2Result(_ffi.slotLabV2GetSpinResult());
        _lastStages = _convertV2Stages(_ffi.slotLabV2GetStages());
      } else {
        _lastResult = _ffi.slotLabGetSpinResult();
        _lastStages = _ffi.slotLabGetStages();
      }

      _cachedStagesSpinId = _lastResult?.spinId;
      _updateFreeSpinsState();
      _updateStats();

      final win = _lastResult?.totalWin ?? 0;
      final isWin = _lastResult?.isWin ?? false;
      debugPrint('[Spin #$_spinCount ${outcome.name}] ${isWin ? "WIN \$${win.toStringAsFixed(2)}" : "no win"} | ${_lastStages.length} stages');

      if (_lastResult != null) {
        onSpinComplete?.call(_lastResult!, _lastStages);
      }

      _isSpinning = false;
      notifyListeners();
      return _lastResult;
    } catch (e) {
      debugPrint('[SlotEngineProvider] Forced spin error: $e');
      _isSpinning = false;
      notifyListeners();
      return null;
    }
  }

  /// Execute a forced spin with EXACT target win multiplier
  Future<SlotLabSpinResult?> spinForcedWithMultiplier(
    ForcedOutcome outcome,
    double targetMultiplier,
  ) async {
    if (!_initialized || _isSpinning) return null;

    _isSpinning = true;
    notifyListeners();

    try {
      debugPrint('[SlotEngineProvider] spinForcedWithMultiplier: ${outcome.name} @ ${targetMultiplier}x');

      final int spinId = _ffi.slotLabSpinForcedWithMultiplier(outcome, targetMultiplier);

      if (spinId == 0) {
        debugPrint('[SlotEngineProvider] spinForcedWithMultiplier FAILED: spinId=0');
        _isSpinning = false;
        notifyListeners();
        return null;
      }

      _spinCount++;

      _lastResult = _ffi.slotLabGetSpinResult();
      _lastStages = _ffi.slotLabGetStages();

      _cachedStagesSpinId = _lastResult?.spinId;
      _updateFreeSpinsState();
      _updateStats();

      final win = _lastResult?.totalWin ?? 0;
      final isWin = _lastResult?.isWin ?? false;
      final tierName = _lastResult?.winTierName ?? 'unknown';
      debugPrint('[Spin #$_spinCount ${outcome.name}@${targetMultiplier}x] '
          '${isWin ? "WIN \$${win.toStringAsFixed(2)} ($tierName)" : "no win"} | ${_lastStages.length} stages');

      if (_lastResult != null) {
        onSpinComplete?.call(_lastResult!, _lastStages);
      }

      _isSpinning = false;
      notifyListeners();
      return _lastResult;
    } catch (e) {
      debugPrint('[SlotEngineProvider] spinForcedWithMultiplier error: $e');
      _isSpinning = false;
      notifyListeners();
      return null;
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
  // ENGINE V2 — GameModel-driven engine
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize Engine V2 with default model
  bool initEngineV2() {
    if (_engineV2Initialized) return true;

    final success = _ffi.slotLabV2Init();
    if (success) {
      _engineV2Initialized = true;
      _currentGameModel = _ffi.slotLabV2GetModel();
      _refreshScenarioList();
      debugPrint('[SlotEngineProvider] Engine V2 initialized');
      notifyListeners();
    }
    return success;
  }

  /// Initialize Engine V2 from GDD JSON
  bool initEngineFromGdd(String gddJson) {
    if (_engineV2Initialized) {
      _ffi.slotLabV2Shutdown();
      _engineV2Initialized = false;
    }

    final success = _ffi.slotLabV2InitFromGdd(gddJson);
    if (success) {
      _engineV2Initialized = true;
      _currentGameModel = _ffi.slotLabV2GetModel();
      _refreshScenarioList();
      debugPrint('[SlotEngineProvider] Engine V2 initialized from GDD');
      notifyListeners();
    }
    return success;
  }

  /// Update game model (re-initializes engine)
  bool updateGameModel(Map<String, dynamic> model) {
    final oldGrid = _currentGameModel?['grid'] as Map<String, dynamic>?;
    final oldReels = oldGrid?['reels'] as int? ?? 5;

    if (_engineV2Initialized) {
      _ffi.slotLabV2Shutdown();
      _engineV2Initialized = false;
    }

    final modelJson = model.toString();
    final success = _ffi.slotLabV2InitWithModelJson(modelJson);
    if (success) {
      _engineV2Initialized = true;
      _currentGameModel = _ffi.slotLabV2GetModel();

      final newGrid = model['grid'] as Map<String, dynamic>?;
      final newReels = newGrid?['reels'] as int? ?? 5;

      if (newReels != oldReels) {
        debugPrint('[SlotEngineProvider] Grid changed: $oldReels -> $newReels reels');
        onGridDimensionsChanged?.call(newReels);
      }

      debugPrint('[SlotEngineProvider] Game model updated');
      notifyListeners();
    }
    return success;
  }

  /// Shutdown Engine V2
  void shutdownEngineV2() {
    if (!_engineV2Initialized) return;
    _ffi.slotLabV2Shutdown();
    _engineV2Initialized = false;
    _currentGameModel = null;
    notifyListeners();
  }

  /// Convert V2 spin result Map to SlotLabSpinResult
  SlotLabSpinResult? _convertV2Result(Map<String, dynamic>? v2Result) {
    if (v2Result == null) return null;
    return SlotLabSpinResult.fromJson(v2Result);
  }

  /// Convert V2 stages List to List of [SlotLabStageEvent]
  List<SlotLabStageEvent> _convertV2Stages(List<Map<String, dynamic>> v2Stages) {
    return v2Stages.map((s) => SlotLabStageEvent.fromJson(s)).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCENARIO SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  void _refreshScenarioList() {
    _availableScenarios = _ffi.slotLabScenarioList();
  }

  /// Load a scenario for playback
  bool loadScenario(String scenarioId) {
    final success = _ffi.slotLabScenarioLoad(scenarioId);
    if (success) {
      _loadedScenarioId = scenarioId;
      debugPrint('[SlotEngineProvider] Loaded scenario: $scenarioId');
      notifyListeners();
    }
    return success;
  }

  /// Unload current scenario
  void unloadScenario() {
    _ffi.slotLabScenarioUnload();
    _loadedScenarioId = null;
    notifyListeners();
  }

  /// Register a custom scenario from Map
  bool registerScenario(Map<String, dynamic> scenarioJson) {
    final jsonStr = scenarioJson.toString();
    final success = _ffi.slotLabScenarioRegister(jsonStr);
    if (success) {
      _refreshScenarioList();
      debugPrint('[SlotEngineProvider] Registered custom scenario');
      notifyListeners();
    }
    return success;
  }

  /// Register a custom scenario from DemoScenario object
  bool registerScenarioFromDemoScenario(DemoScenario scenario) {
    final jsonStr = jsonEncode(scenario.toJson());
    final success = _ffi.slotLabScenarioRegister(jsonStr);
    if (success) {
      _refreshScenarioList();
      debugPrint('[SlotEngineProvider] Registered scenario: ${scenario.id}');
      notifyListeners();
    }
    return success;
  }

  /// Get scenario progress (current, total)
  (int, int) get scenarioProgress => _ffi.slotLabScenarioProgress();

  /// Check if scenario is complete
  bool get scenarioIsComplete => _ffi.slotLabScenarioIsComplete();

  /// Reset scenario to beginning
  void resetScenario() {
    _ffi.slotLabScenarioReset();
    notifyListeners();
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
    shutdownEngineV2();
    shutdown();
    super.dispose();
  }
}
