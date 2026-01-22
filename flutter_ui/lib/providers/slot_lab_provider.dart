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
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/stage_models.dart';
import '../services/stage_audio_mapper.dart';
import '../services/event_registry.dart';
import '../services/audio_pool.dart';
import '../services/audio_asset_manager.dart';
import '../services/rtpc_modulation_service.dart';
import '../services/unified_playback_controller.dart';
import '../src/rust/native_ffi.dart';
import '../src/rust/slot_lab_v2_ffi.dart';
import 'middleware_provider.dart';
import 'ale_provider.dart';

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

  // ─── Audio Timing Configuration ─────────────────────────────────────────────
  /// P0.1: Timing configuration from Rust engine
  /// Contains audio latency compensation and pre-trigger offsets
  SlotLabTimingConfig? _timingConfig;

  /// P0.6: Pre-trigger offset for anticipation audio (ms)
  /// Audio starts this much before the visual anticipation begins
  /// Configurable via setAnticipationPreTriggerMs()
  int _anticipationPreTriggerMs = 50;

  /// P0.1: Reel stop pre-trigger offset (ms)
  /// Audio starts this much before the reel visually stops
  int _reelStopPreTriggerMs = 20;
  bool _jackpotEnabled = true;

  // ─── Free Spins State ──────────────────────────────────────────────────────
  bool _inFreeSpins = false;
  int _freeSpinsRemaining = 0;

  // ─── Audio Integration ─────────────────────────────────────────────────────
  MiddlewareProvider? _middleware;
  StageAudioMapper? _audioMapper;
  bool _autoTriggerAudio = true;

  // ─── ALE Integration ──────────────────────────────────────────────────────
  AleProvider? _aleProvider;
  bool _aleAutoSync = true;

  // ─── Stage Event Playback ──────────────────────────────────────────────────
  Timer? _stagePlaybackTimer;
  Timer? _audioPreTriggerTimer; // P0.6: Separate timer for audio pre-trigger
  int _currentStageIndex = 0;
  bool _isPlayingStages = false;
  int _totalReels = 5; // Default, can be configured
  int _playbackGeneration = 0; // Incremented on each new spin to invalidate old timers

  // ─── Persistent UI State (survives screen switches) ───────────────────────
  /// Audio pool now comes from AudioAssetManager (single source of truth)
  /// This getter provides backwards compatibility for existing code
  List<Map<String, dynamic>> get persistedAudioPool =>
      AudioAssetManager.instance.toMapList();

  /// Legacy setter - now syncs to AudioAssetManager
  set persistedAudioPool(List<Map<String, dynamic>> value) {
    for (final map in value) {
      AudioAssetManager.instance.addFromMap(map);
    }
  }

  List<Map<String, dynamic>> persistedCompositeEvents = [];
  List<Map<String, dynamic>> persistedTracks = [];
  Map<String, String> persistedEventToRegionMap = {};

  // ─── Lower Zone Tab State (survives screen switches) ──────────────────────
  /// Currently selected lower zone tab index (0=Timeline, 1=Command, 2=Events, 3=Meters)
  int _persistedLowerZoneTabIndex = 1; // Default to Command Builder
  /// Lower zone expanded state
  bool _persistedLowerZoneExpanded = true;
  /// Lower zone height
  double _persistedLowerZoneHeight = 250.0;

  int get persistedLowerZoneTabIndex => _persistedLowerZoneTabIndex;
  bool get persistedLowerZoneExpanded => _persistedLowerZoneExpanded;
  double get persistedLowerZoneHeight => _persistedLowerZoneHeight;

  void setLowerZoneTabIndex(int index) {
    debugPrint('[SlotLabProvider] setLowerZoneTabIndex: $index (was $_persistedLowerZoneTabIndex)');
    if (_persistedLowerZoneTabIndex != index) {
      _persistedLowerZoneTabIndex = index;
      // Don't notify - this is just persistence, UI handles its own updates
    }
  }

  void setLowerZoneExpanded(bool expanded) {
    _persistedLowerZoneExpanded = expanded;
  }

  void setLowerZoneHeight(double height) {
    _persistedLowerZoneHeight = height;
  }

  // ─── Waveform Cache (survives screen switches) ────────────────────────────
  /// Cache of waveform data by audio path - persists across navigation
  final Map<String, List<double>> waveformCache = {};
  /// Cache of FFI clip IDs by audio path - persists across navigation
  final Map<String, int> clipIdCache = {};

  /// Clear all persisted UI state (use when data is corrupted)
  void clearPersistedState() {
    // Audio pool is now in AudioAssetManager - clear it there
    AudioAssetManager.instance.clear();
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
  bool get aleAutoSync => _aleAutoSync;

  /// P0.6: Anticipation pre-trigger offset in ms
  int get anticipationPreTriggerMs => _anticipationPreTriggerMs;

  /// P0.1: Reel stop pre-trigger offset in ms
  int get reelStopPreTriggerMs => _reelStopPreTriggerMs;

  /// P0.1: Get timing configuration (latency compensation values)
  SlotLabTimingConfig? get timingConfig => _timingConfig;

  /// P0.1: Total audio offset in ms (latency compensation + sync)
  double get totalAudioOffsetMs => _timingConfig?.totalAudioOffsetMs ?? 5.0;

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

  // ─── Engine V2 State ──────────────────────────────────────────────────────
  bool _engineV2Initialized = false;
  Map<String, dynamic>? _currentGameModel;
  List<ScenarioInfo> _availableScenarios = [];
  String? _loadedScenarioId;

  bool get engineV2Initialized => _engineV2Initialized;
  Map<String, dynamic>? get currentGameModel => _currentGameModel;
  List<ScenarioInfo> get availableScenarios => _availableScenarios;
  String? get loadedScenarioId => _loadedScenarioId;

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
      _loadTimingConfig(); // P0.1: Load timing config from Rust

      // Configure AudioPool for Slot Lab rapid-fire events
      AudioPool.instance.configure(AudioPoolConfig.slotLabConfig);
      AudioPool.instance.preloadSlotLabEvents();

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
    _audioPreTriggerTimer?.cancel();
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

  /// Connect ALE provider for signal sync
  void connectAle(AleProvider ale) {
    _aleProvider = ale;
    debugPrint('[SlotLabProvider] ALE provider connected');
  }

  /// Set ALE auto sync
  void setAleAutoSync(bool enabled) {
    _aleAutoSync = enabled;
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
    // Update slider to match
    _volatilitySlider = preset.value / 3.0;
    notifyListeners();
  }

  /// Set timing profile
  void setTimingProfile(TimingProfileType profile) {
    _timingProfile = profile;
    if (_initialized) {
      _ffi.slotLabSetTimingProfile(profile);
      _loadTimingConfig(); // P0.1: Reload timing config after profile change
    }
    notifyListeners();
  }

  /// P0.1: Load timing configuration from Rust engine
  void _loadTimingConfig() {
    _timingConfig = _ffi.slotLabGetTimingConfig();
    if (_timingConfig != null) {
      // Apply timing config values to local fields
      _anticipationPreTriggerMs = _timingConfig!.anticipationAudioPreTriggerMs.round();
      _reelStopPreTriggerMs = _timingConfig!.reelStopAudioPreTriggerMs.round();
      debugPrint('[SlotLabProvider] P0.1 Timing config loaded: '
          'latency=${_timingConfig!.audioLatencyCompensationMs}ms, '
          'syncOffset=${_timingConfig!.visualAudioSyncOffsetMs}ms, '
          'anticipationPreTrigger=${_anticipationPreTriggerMs}ms, '
          'reelStopPreTrigger=${_reelStopPreTriggerMs}ms');
    } else {
      // Use defaults if config not available
      _timingConfig = SlotLabTimingConfig.studio();
      debugPrint('[SlotLabProvider] P0.1 Using default studio timing config');
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

  /// Set auto audio triggering
  void setAutoTriggerAudio(bool enabled) {
    _autoTriggerAudio = enabled;
    notifyListeners();
  }

  /// P0.6: Set anticipation pre-trigger offset in ms
  /// Higher value = audio plays earlier relative to visual
  /// Typical values: 30-100ms
  void setAnticipationPreTriggerMs(int ms) {
    _anticipationPreTriggerMs = ms.clamp(0, 200);
    debugPrint('[SlotLabProvider] Anticipation pre-trigger: ${_anticipationPreTriggerMs}ms');
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

      // DEBUG: Print all stage types to see what Rust generated
      final stageTypes = _lastStages.map((s) => s.stageType).toList();
      debugPrint('[SlotLabProvider] Spin #$_spinCount: win=${_lastResult?.isWin}, '
          'amount=${_lastResult?.totalWin.toStringAsFixed(2)}, '
          'stages=${_lastStages.length}');
      debugPrint('[SlotLabProvider] Stage sequence: $stageTypes');

      // Auto-trigger audio if enabled
      if (_autoTriggerAudio && _lastStages.isNotEmpty) {
        _playStagesSequentially();
      }

      // Sync ALE signals
      _syncAleSignals();

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

      // Sync ALE signals
      _syncAleSignals();

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
  // ALE SIGNAL SYNC
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sync Slot Lab state to ALE signals
  /// Maps game state metrics to ALE signal names for dynamic music layering
  void _syncAleSignals() {
    if (!_aleAutoSync || _aleProvider == null || !_aleProvider!.initialized) {
      return;
    }

    final result = _lastResult;
    if (result == null) return;

    // Calculate signals from current game state
    final signals = <String, double>{
      // Win tier (0-5 scale based on win ratio)
      'winTier': _calculateWinTier(result.winRatio),

      // Momentum (based on recent wins and volatility)
      'momentum': _calculateMomentum(),

      // Volatility (from current slider setting)
      'volatility': _volatilitySlider,

      // Session progress (normalized spin count)
      'sessionProgress': (_spinCount / 100.0).clamp(0.0, 1.0),

      // Feature progress (free spins progress if active)
      'featureProgress': _inFreeSpins
          ? 1.0 - (_freeSpinsRemaining / 15.0).clamp(0.0, 1.0)
          : 0.0,

      // Bet multiplier (normalized)
      'betMultiplier': (_betAmount / 10.0).clamp(0.0, 1.0),

      // Recent win rate (from stats)
      'recentWinRate': _hitRate,

      // Time since win (simulated - higher if no recent wins)
      'timeSinceWin': result.isWin ? 0.0 : 5000.0,

      // Combo count (cascade count if applicable)
      'comboCount': _countCascades().toDouble(),

      // Near miss rate (from anticipation events)
      'nearMissRate': _calculateNearMissRate(),
    };

    // Send all signals to ALE
    _aleProvider!.updateSignals(signals);

    // Handle context switching based on game state
    _syncAleContext();

    debugPrint('[SlotLabProvider] ALE signals synced: winTier=${signals['winTier']?.toStringAsFixed(2)}, momentum=${signals['momentum']?.toStringAsFixed(2)}');
  }

  /// Calculate win tier (0-5) from win ratio
  double _calculateWinTier(double winRatio) {
    if (winRatio <= 0) return 0.0;
    if (winRatio < 2) return 1.0;    // Small win
    if (winRatio < 5) return 2.0;    // Nice win
    if (winRatio < 15) return 3.0;   // Big win
    if (winRatio < 50) return 4.0;   // Mega win
    return 5.0;                       // Epic/Ultra win
  }

  /// Calculate momentum from recent activity
  double _calculateMomentum() {
    // Simple momentum based on hit rate and recent wins
    final baseMomentum = _hitRate;
    final winBoost = _lastResult?.isWin == true ? 0.3 : 0.0;
    final featureBoost = _inFreeSpins ? 0.2 : 0.0;
    return (baseMomentum + winBoost + featureBoost).clamp(0.0, 1.0);
  }

  /// Count cascade events in last stages
  int _countCascades() {
    return _lastStages.where((s) =>
        s.stageType.toUpperCase() == 'CASCADE_STEP').length;
  }

  /// Calculate near miss rate from stages
  double _calculateNearMissRate() {
    final anticipations = _lastStages.where((s) =>
        s.stageType.toUpperCase() == 'ANTICIPATION_ON').length;
    // More anticipations = higher near miss rate
    return (anticipations / 5.0).clamp(0.0, 1.0);
  }

  /// Sync ALE context based on game state
  void _syncAleContext() {
    if (_aleProvider == null) return;

    final currentContext = _aleProvider!.state.activeContextId;

    // Determine appropriate context
    String targetContext;
    if (_inFreeSpins) {
      targetContext = 'FREESPINS';
    } else if (_lastResult?.bigWinTier != null &&
               _lastResult!.bigWinTier != SlotLabWinTier.none) {
      targetContext = 'BIGWIN';
    } else {
      targetContext = 'BASE';
    }

    // Switch context if different
    if (currentContext != targetContext) {
      _aleProvider!.enterContext(targetContext);
      debugPrint('[SlotLabProvider] ALE context switched: $currentContext → $targetContext');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE PLAYBACK & AUDIO TRIGGERING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Play stages sequentially with timing
  void _playStagesSequentially() {
    if (_lastStages.isEmpty) return;

    // Acquire SlotLab section in UnifiedPlaybackController
    final controller = UnifiedPlaybackController.instance;
    if (!controller.acquireSection(PlaybackSection.slotLab)) {
      debugPrint('[SlotLabProvider] Failed to acquire SlotLab section');
      return;
    }

    // CRITICAL: Start the audio stream WITHOUT starting transport
    // SlotLab uses one-shot voices (playFileToBus), not timeline clips
    // Using ensureStreamRunning() instead of play() prevents DAW clips from playing
    controller.ensureStreamRunning();

    // Cancel any existing playback and increment generation to invalidate old timers
    _stagePlaybackTimer?.cancel();
    _audioPreTriggerTimer?.cancel();
    _playbackGeneration++; // Invalidate any pending timer callbacks from previous spin
    _currentStageIndex = 0;
    _isPlayingStages = true;

    debugPrint('[SlotLabProvider] Playing ${_lastStages.length} stages (gen: $_playbackGeneration)');

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
      // Release SlotLab section when done
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.slotLab);
      notifyListeners();
      return;
    }

    final currentStage = _lastStages[_currentStageIndex];
    final nextStage = _lastStages[_currentStageIndex + 1];
    int delayMs = (nextStage.timestampMs - currentStage.timestampMs).toInt();

    // ═══════════════════════════════════════════════════════════════════════════
    // P0.5: DYNAMIC ROLLUP SPEED — Apply RTPC multiplier to rollup timing
    // ═══════════════════════════════════════════════════════════════════════════
    // Only modify timing for ROLLUP_TICK stages (not START/END)
    final nextStageType = nextStage.stageType.toUpperCase();
    if (nextStageType == 'ROLLUP_TICK') {
      // Get rollup speed multiplier from RTPC (1.0 = normal, >1 = faster, <1 = slower)
      final speedMultiplier = RtpcModulationService.instance.getRollupSpeedMultiplier();
      // Apply: higher multiplier = shorter delay (faster rollup)
      delayMs = (delayMs / speedMultiplier).round();
      // Clamp to reasonable bounds (min 10ms for audio, max 1000ms for usability)
      delayMs = delayMs.clamp(10, 1000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // P0.4: DYNAMIC CASCADE TIMING — Sync cascade audio with visual animation
    // ═══════════════════════════════════════════════════════════════════════════
    // Use timing config's cascade_step_duration_ms for consistent timing
    // Apply RTPC multiplier for dynamic speed control (like rollup)
    if (nextStageType == 'CASCADE_STEP') {
      final baseDurationMs = _timingConfig?.cascadeStepDurationMs ?? 400.0;
      // Get cascade speed multiplier from RTPC (1.0 = normal, >1 = faster, <1 = slower)
      final speedMultiplier = RtpcModulationService.instance.getCascadeSpeedMultiplier();
      // Apply: higher multiplier = shorter delay (faster cascade)
      delayMs = (baseDurationMs / speedMultiplier).round();
      // Clamp to reasonable bounds (min 100ms for animation, max 1000ms for usability)
      delayMs = delayMs.clamp(100, 1000);
      debugPrint('[SlotLabProvider] P0.4 CASCADE_STEP timing: ${delayMs}ms (base: ${baseDurationMs.round()}ms, multiplier: ${speedMultiplier.toStringAsFixed(2)})');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // P0.1: AUDIO LATENCY COMPENSATION — Apply timing config offsets
    // ═══════════════════════════════════════════════════════════════════════════
    // Calculate total audio offset from timing config
    final totalAudioOffset = _timingConfig?.totalAudioOffsetMs ?? 5.0;

    // Capture current generation to check if timers are still valid when they fire
    final generation = _playbackGeneration;

    // ═══════════════════════════════════════════════════════════════════════════
    // P0.6: ANTICIPATION PRE-TRIGGER — Trigger audio earlier than visual
    // ═══════════════════════════════════════════════════════════════════════════
    // If next stage is ANTICIPATION_ON, schedule audio trigger earlier
    if (nextStageType == 'ANTICIPATION_ON' && _anticipationPreTriggerMs > 0) {
      // P0.1: Include total audio offset in pre-trigger calculation
      final preTriggerTotal = _anticipationPreTriggerMs + totalAudioOffset.round();
      final audioDelayMs = (delayMs - preTriggerTotal).clamp(0, delayMs);
      if (audioDelayMs < delayMs) {
        // Schedule AUDIO trigger earlier (pre-trigger)
        _audioPreTriggerTimer?.cancel();
        _audioPreTriggerTimer = Timer(Duration(milliseconds: audioDelayMs), () {
          if (!_isPlayingStages || _playbackGeneration != generation) return;
          // Trigger only the audio for anticipation (not full _triggerStage which includes UI logic)
          _triggerAudioOnly(nextStage);
          debugPrint('[SlotLabProvider] P0.1+P0.6 Pre-trigger: ANTICIPATION audio at ${audioDelayMs}ms (${preTriggerTotal}ms early, offset=${totalAudioOffset.toStringAsFixed(1)}ms)');
        });
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // P0.1: REEL_STOP PRE-TRIGGER — Trigger reel stop audio earlier than visual
    // ═══════════════════════════════════════════════════════════════════════════
    if (nextStageType == 'REEL_STOP' && _reelStopPreTriggerMs > 0) {
      // Include total audio offset in pre-trigger calculation
      final preTriggerTotal = _reelStopPreTriggerMs + totalAudioOffset.round();
      final audioDelayMs = (delayMs - preTriggerTotal).clamp(0, delayMs);
      if (audioDelayMs < delayMs) {
        // Schedule AUDIO trigger earlier (pre-trigger)
        _audioPreTriggerTimer?.cancel();
        _audioPreTriggerTimer = Timer(Duration(milliseconds: audioDelayMs), () {
          if (!_isPlayingStages || _playbackGeneration != generation) return;
          _triggerAudioOnly(nextStage);
          debugPrint('[SlotLabProvider] P0.1 Pre-trigger: REEL_STOP audio at ${audioDelayMs}ms (${preTriggerTotal}ms early)');
        });
      }
    }

    _stagePlaybackTimer = Timer(Duration(milliseconds: delayMs.clamp(10, 5000)), () {
      // Check if this timer belongs to the current playback session
      if (!_isPlayingStages || _playbackGeneration != generation) {
        debugPrint('[SlotLabProvider] Ignoring stale timer (gen: $generation, current: $_playbackGeneration)');
        return;
      }

      _currentStageIndex++;
      final stage = _lastStages[_currentStageIndex];
      final stageType = stage.stageType.toUpperCase();

      // P0.1+P0.6: Check if audio was pre-triggered for this stage
      final wasPreTriggered = (stageType == 'ANTICIPATION_ON' && _anticipationPreTriggerMs > 0) ||
                               (stageType == 'REEL_STOP' && _reelStopPreTriggerMs > 0);

      if (wasPreTriggered) {
        // Audio already played via pre-trigger, only update UI state
        // Still need to handle REEL_SPIN stop logic for REEL_STOP
        if (stageType == 'REEL_STOP') {
          _handleReelStopUIOnly(stage);
        }
        debugPrint('[SlotLabProvider] _triggerStage (UI only): $stageType @ ${stage.timestampMs.toStringAsFixed(0)}ms');
      } else {
        _triggerStage(stage);
      }
      notifyListeners();

      _scheduleNextStage();
    });
  }

  /// P0.1: Handle REEL_STOP UI-only logic (when audio was pre-triggered)
  /// This handles REEL_SPIN stop logic without re-triggering audio
  void _handleReelStopUIOnly(SlotLabStageEvent stage) {
    // CRITICAL: reel_index is in rawStage, not payload
    final reelIndex = stage.rawStage['reel_index'];

    // REEL_SPIN STOP LOGIC — Stop loop kad poslednji reel stane
    final bool shouldStopReelSpin;
    if (reelIndex != null) {
      // Ako imamo specifičan reel index, stop kad je poslednji
      shouldStopReelSpin = reelIndex >= _totalReels - 1;
    } else {
      // Ako nema reel indexa, ovo je generički REEL_STOP — proveri da li je poslednji
      final currentIdx = _lastStages.indexWhere((s) =>
        s.timestampMs == stage.timestampMs && s.stageType.toUpperCase() == 'REEL_STOP');
      if (currentIdx >= 0 && currentIdx < _lastStages.length - 1) {
        final nextStage = _lastStages[currentIdx + 1];
        shouldStopReelSpin = nextStage.stageType.toUpperCase() != 'REEL_STOP';
      } else {
        // Poslednji stage u listi
        shouldStopReelSpin = true;
      }
    }

    if (shouldStopReelSpin) {
      eventRegistry.stopEvent('REEL_SPIN');
      debugPrint('[SlotLabProvider] REEL_SPIN stopped (last reel landed, index: $reelIndex)');
    }
  }

  /// Trigger only the audio for a stage (no UI state changes)
  /// Used for P0.6 anticipation pre-trigger
  void _triggerAudioOnly(SlotLabStageEvent stage) {
    final stageType = stage.stageType.toUpperCase();
    // CRITICAL: reel_index is in rawStage, not payload
    final reelIndex = stage.rawStage['reel_index'];

    String effectiveStage = stageType;
    Map<String, dynamic> context = {...stage.payload, ...stage.rawStage};

    if (stageType == 'REEL_STOP' && reelIndex != null) {
      effectiveStage = 'REEL_STOP_$reelIndex';
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // P1.2: NEAR MISS AUDIO ESCALATION — Intensity-based anticipation
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType == 'ANTICIPATION_ON') {
      final escalationResult = _calculateAnticipationEscalation(stage);
      effectiveStage = escalationResult.effectiveStage;
      context['volumeMultiplier'] = escalationResult.volumeMultiplier;
      if (escalationResult.effectiveStage != 'ANTICIPATION_ON') {
        debugPrint('[SlotLabProvider] P1.2 Escalation: ${escalationResult.effectiveStage} (vol: ${escalationResult.volumeMultiplier.toStringAsFixed(2)})');
      }
    }

    // Debug: Show all registered stages
    final registeredStages = eventRegistry.allEvents.map((e) => e.stage).toList();

    // ALWAYS call triggerStage() - EventRegistry will notify Event Log even for stages without audio
    if (eventRegistry.hasEventForStage(effectiveStage)) {
      debugPrint('[SlotLabProvider] ✅ Triggering audio: $effectiveStage');
      eventRegistry.triggerStage(effectiveStage, context: context);
    } else if (effectiveStage != stageType && eventRegistry.hasEventForStage(stageType)) {
      debugPrint('[SlotLabProvider] ✅ Triggering audio (fallback): $stageType');
      eventRegistry.triggerStage(stageType, context: context);
    } else {
      // STILL trigger so Event Log shows the stage (even without audio)
      debugPrint('[SlotLabProvider] ⚠️ No audio event for: $effectiveStage (will show in Event Log)');
      eventRegistry.triggerStage(stageType, context: context);
    }
  }

  /// P1.2: Calculate anticipation escalation based on near miss info
  ({String effectiveStage, double volumeMultiplier}) _calculateAnticipationEscalation(SlotLabStageEvent stage) {
    // Get near miss info from both payload and rawStage
    final intensity = (stage.payload['intensity'] as num?)?.toDouble() ?? 0.5;
    final missingSymbols = stage.payload['missing'] as int? ?? 2;
    // reel_index is in rawStage for anticipation events
    final triggerReel = stage.rawStage['reel_index'] as int? ?? stage.payload['trigger_reel'] as int? ?? 2;
    final reason = stage.rawStage['reason'] as String? ?? stage.payload['reason'] as String?;

    // Calculate effective intensity
    // Later reels = more intense (player has seen more potential)
    final reelFactor = (triggerReel + 1) / _totalReels; // 0.2 to 1.0

    // Fewer missing symbols = closer to win = more intense
    final missingFactor = switch (missingSymbols) {
      1 => 1.0,   // One away = maximum tension
      2 => 0.75,  // Two away = high tension
      _ => 0.5,   // More = medium tension
    };

    final combinedIntensity = (intensity * reelFactor * missingFactor).clamp(0.0, 1.0);

    // Select appropriate stage based on intensity
    String effectiveStage;
    double volumeMultiplier;

    if (combinedIntensity >= 0.8) {
      // Maximum tension - try ANTICIPATION_MAX or ANTICIPATION_HIGH
      if (eventRegistry.hasEventForStage('ANTICIPATION_MAX')) {
        effectiveStage = 'ANTICIPATION_MAX';
      } else if (eventRegistry.hasEventForStage('ANTICIPATION_HIGH')) {
        effectiveStage = 'ANTICIPATION_HIGH';
      } else {
        effectiveStage = 'ANTICIPATION_ON';
      }
      volumeMultiplier = 1.0;
    } else if (combinedIntensity >= 0.5) {
      // High tension
      if (eventRegistry.hasEventForStage('ANTICIPATION_HIGH')) {
        effectiveStage = 'ANTICIPATION_HIGH';
      } else {
        effectiveStage = 'ANTICIPATION_ON';
      }
      volumeMultiplier = 0.9;
    } else {
      // Medium tension - use default
      effectiveStage = 'ANTICIPATION_ON';
      volumeMultiplier = 0.7 + (combinedIntensity * 0.3); // 0.7 to 0.85
    }

    return (effectiveStage: effectiveStage, volumeMultiplier: volumeMultiplier);
  }

  /// Trigger audio for a stage event
  /// CRITICAL: Uses ONLY EventRegistry. Legacy systems DISABLED to prevent duplicate audio.
  void _triggerStage(SlotLabStageEvent stage) {
    final stageType = stage.stageType.toUpperCase();
    // CRITICAL: reel_index and symbols are in rawStage (from stage JSON), not payload
    final reelIndex = stage.rawStage['reel_index'];
    Map<String, dynamic> context = {...stage.payload, ...stage.rawStage};

    debugPrint('[SlotLabProvider] >>> TRIGGER: $stageType (index: $_currentStageIndex/${_lastStages.length}) @ ${stage.timestampMs.toStringAsFixed(0)}ms');

    // ═══════════════════════════════════════════════════════════════════════════
    // CENTRALNI EVENT REGISTRY — JEDINI izvor audio playback-a
    // Legacy sistemi (Middleware postEvent, StageAudioMapper) su ONEMOGUĆENI
    // jer izazivaju dupli audio playback
    // ═══════════════════════════════════════════════════════════════════════════

    // Za REEL_STOP, koristi specifičan stage po reel-u: REEL_STOP_0, REEL_STOP_1, itd.
    String effectiveStage = stageType;

    // ═══════════════════════════════════════════════════════════════════════════
    // P1.2: NEAR MISS AUDIO ESCALATION — Intensity-based anticipation
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType == 'ANTICIPATION_ON') {
      final escalationResult = _calculateAnticipationEscalation(stage);
      effectiveStage = escalationResult.effectiveStage;
      context['volumeMultiplier'] = escalationResult.volumeMultiplier;
      if (escalationResult.effectiveStage != 'ANTICIPATION_ON') {
        debugPrint('[SlotLabProvider] P1.2 Escalation: ${escalationResult.effectiveStage} (vol: ${escalationResult.volumeMultiplier.toStringAsFixed(2)})');
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // P1.3: WIN LINE AUDIO PANNING — Pan based on symbol positions
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType == 'WIN_LINE_SHOW') {
      final lineIndex = stage.payload['line_index'] as int? ?? 0;
      final linePan = _calculateWinLinePan(lineIndex);
      context['pan'] = linePan;
      debugPrint('[SlotLabProvider] P1.3 Win Line Pan: line $lineIndex → pan ${linePan.toStringAsFixed(2)}');
    }

    if (stageType == 'REEL_STOP' && reelIndex != null) {
      effectiveStage = 'REEL_STOP_$reelIndex';

      // ═══════════════════════════════════════════════════════════════════════════
      // P1.1: SYMBOL-SPECIFIC AUDIO — Different sounds for special symbols
      // ═══════════════════════════════════════════════════════════════════════════
      // Check for special symbols in the stopped reel
      // CRITICAL: symbols are in rawStage (from stage JSON), not payload
      final symbols = stage.rawStage['symbols'] as List<dynamic>?;
      final hasWild = stage.rawStage['has_wild'] as bool? ?? _containsWild(symbols);
      final hasScatter = stage.rawStage['has_scatter'] as bool? ?? _containsScatter(symbols);
      final hasSeven = _containsSeven(symbols);

      // Try symbol-specific stage first (most specific to least specific)
      // Priority: WILD > SCATTER > SEVEN > generic
      String? symbolSpecificStage;
      if (hasWild && eventRegistry.hasEventForStage('${effectiveStage}_WILD')) {
        symbolSpecificStage = '${effectiveStage}_WILD';
      } else if (hasScatter && eventRegistry.hasEventForStage('${effectiveStage}_SCATTER')) {
        symbolSpecificStage = '${effectiveStage}_SCATTER';
      } else if (hasSeven && eventRegistry.hasEventForStage('${effectiveStage}_SEVEN')) {
        symbolSpecificStage = '${effectiveStage}_SEVEN';
      }

      if (symbolSpecificStage != null) {
        effectiveStage = symbolSpecificStage;
        debugPrint('[SlotLabProvider] P1.1 Symbol-specific: $symbolSpecificStage');
      }
    }

    // Probaj specifičan stage prvo, pa fallback na generički
    // P1.2: Koristi `context` umesto `stage.payload` da volumeMultiplier prođe
    // ALWAYS call triggerStage() - EventRegistry will notify Event Log even for stages without audio
    if (eventRegistry.hasEventForStage(effectiveStage)) {
      eventRegistry.triggerStage(effectiveStage, context: context);
      debugPrint('[SlotLabProvider] Registry trigger: $effectiveStage');
    } else if (effectiveStage != stageType && eventRegistry.hasEventForStage(stageType)) {
      // Fallback na generički REEL_STOP ako nema specifičnog
      eventRegistry.triggerStage(stageType, context: context);
      debugPrint('[SlotLabProvider] Registry trigger (fallback): $stageType');
    } else if (eventRegistry.hasEventForStage(stageType)) {
      eventRegistry.triggerStage(stageType, context: context);
      debugPrint('[SlotLabProvider] Registry trigger: $stageType');
    } else {
      // STILL trigger so Event Log shows the stage (even without audio)
      eventRegistry.triggerStage(stageType, context: context);
      debugPrint('[SlotLabProvider] Registry trigger (no audio): $stageType');
    }

    // Za SPIN_START, trigeruj i REEL_SPIN (loop audio dok se vrti)
    if (stageType == 'SPIN_START' && eventRegistry.hasEventForStage('REEL_SPIN')) {
      eventRegistry.triggerStage('REEL_SPIN', context: context);
      debugPrint('[SlotLabProvider] Registry trigger: REEL_SPIN (started)');
    }

    // REEL_SPIN STOP LOGIC — Stop loop kad poslednji reel stane
    // Logika: Stop REEL_SPIN ako je ovo poslednji reel (reel_index >= totalReels - 1)
    // ILI ako nema specifičnog reel indexa (fallback REEL_STOP)
    if (stageType == 'REEL_STOP') {
      final bool shouldStopReelSpin;
      if (reelIndex != null) {
        // Ako imamo specifičan reel index, stop kad je poslednji
        shouldStopReelSpin = reelIndex >= _totalReels - 1;
      } else {
        // Ako nema reel indexa, ovo je generički REEL_STOP — proveri da li je poslednji
        // Gledamo da li je sledeći stage nešto drugo osim REEL_STOP
        final currentIdx = _lastStages.indexWhere((s) =>
          s.timestampMs == stage.timestampMs && s.stageType.toUpperCase() == 'REEL_STOP');
        if (currentIdx >= 0 && currentIdx < _lastStages.length - 1) {
          final nextStage = _lastStages[currentIdx + 1];
          shouldStopReelSpin = nextStage.stageType.toUpperCase() != 'REEL_STOP';
        } else {
          // Poslednji stage u listi
          shouldStopReelSpin = true;
        }
      }

      if (shouldStopReelSpin) {
        eventRegistry.stopEvent('REEL_SPIN');
        debugPrint('[SlotLabProvider] REEL_SPIN stopped (last reel landed, index: $reelIndex)');
      }
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
    _audioPreTriggerTimer?.cancel();
    _isPlayingStages = false;
    // Release SlotLab section
    UnifiedPlaybackController.instance.releaseSection(PlaybackSection.slotLab);
    notifyListeners();
  }

  /// Alias for stopStagePlayback - used by mode switch isolation
  void stopAllPlayback() => stopStagePlayback();

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
  // P1.1: SYMBOL DETECTION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if symbols list contains a Wild (typically symbol ID 0 or 10)
  bool _containsWild(List<dynamic>? symbols) {
    if (symbols == null || symbols.isEmpty) return false;
    // Wild is typically ID 0 or 10 in standard slot configurations
    // Check for common wild IDs
    return symbols.any((s) => s == 0 || s == 10);
  }

  /// Check if symbols list contains a Scatter (typically symbol ID 9)
  bool _containsScatter(List<dynamic>? symbols) {
    if (symbols == null || symbols.isEmpty) return false;
    // Scatter is typically ID 9 in standard slot configurations
    return symbols.contains(9);
  }

  /// Check if symbols list contains a Seven (typically symbol ID 7)
  bool _containsSeven(List<dynamic>? symbols) {
    if (symbols == null || symbols.isEmpty) return false;
    // Seven is typically ID 7 in standard slot configurations
    return symbols.contains(7);
  }

  /// Check if symbols list contains a high-paying symbol (7, 8, or wild)
  bool _containsHighPaySymbol(List<dynamic>? symbols) {
    if (symbols == null || symbols.isEmpty) return false;
    return symbols.any((s) => s == 0 || s == 7 || s == 8 || s == 10);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.3: WIN LINE AUDIO PANNING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calculate pan value based on win line positions
  /// Returns pan from -1.0 (leftmost) to +1.0 (rightmost)
  /// Uses average X position of winning symbols on the line
  double _calculateWinLinePan(int lineIndex) {
    if (_lastResult == null) return 0.0;

    // Find the LineWin with matching lineIndex
    final lineWin = _lastResult!.lineWins.firstWhere(
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
      return 0.0; // No line found or no positions, center pan
    }

    // Calculate average X position (column) across winning positions
    // positions is List<List<int>> where each element is [col, row]
    double sumX = 0.0;
    for (final pos in lineWin.positions) {
      if (pos.isNotEmpty) {
        sumX += pos[0].toDouble(); // Column is first element
      }
    }
    final avgX = sumX / lineWin.positions.length;

    // Map to pan: column 0 → -1.0, column (totalReels-1) → +1.0
    // Formula: pan = (avgX / (totalReels - 1)) * 2.0 - 1.0
    // For 5-reel: col 0 → -1.0, col 2 → 0.0, col 4 → +1.0
    if (_totalReels <= 1) return 0.0;

    final normalizedX = avgX / (_totalReels - 1); // 0.0 to 1.0
    final pan = (normalizedX * 2.0) - 1.0; // -1.0 to +1.0

    return pan.clamp(-1.0, 1.0);
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
      debugPrint('[SlotLabProvider] Engine V2 initialized');
      notifyListeners();
    }
    return success;
  }

  /// Initialize Engine V2 from GDD JSON
  bool initEngineFromGdd(String gddJson) {
    // Shutdown existing engine first
    if (_engineV2Initialized) {
      _ffi.slotLabV2Shutdown();
      _engineV2Initialized = false;
    }

    final success = _ffi.slotLabV2InitFromGdd(gddJson);
    if (success) {
      _engineV2Initialized = true;
      _currentGameModel = _ffi.slotLabV2GetModel();
      _refreshScenarioList();
      debugPrint('[SlotLabProvider] Engine V2 initialized from GDD');
      notifyListeners();
    }
    return success;
  }

  /// Update game model (re-initializes engine)
  bool updateGameModel(Map<String, dynamic> model) {
    // Shutdown existing engine
    if (_engineV2Initialized) {
      _ffi.slotLabV2Shutdown();
      _engineV2Initialized = false;
    }

    // Convert model to JSON and initialize
    final modelJson = model.toString(); // Will be proper JSON in real impl
    final success = _ffi.slotLabV2InitWithModelJson(modelJson);
    if (success) {
      _engineV2Initialized = true;
      _currentGameModel = _ffi.slotLabV2GetModel();
      debugPrint('[SlotLabProvider] Game model updated');
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
      debugPrint('[SlotLabProvider] Loaded scenario: $scenarioId');
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
    final jsonStr = scenarioJson.toString(); // Will be proper JSON
    final success = _ffi.slotLabScenarioRegister(jsonStr);
    if (success) {
      _refreshScenarioList();
      debugPrint('[SlotLabProvider] Registered custom scenario');
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
      debugPrint('[SlotLabProvider] Registered scenario: ${scenario.id}');
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
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _stagePlaybackTimer?.cancel();
    _audioPreTriggerTimer?.cancel();
    shutdownEngineV2();
    shutdown();
    super.dispose();
  }
}
