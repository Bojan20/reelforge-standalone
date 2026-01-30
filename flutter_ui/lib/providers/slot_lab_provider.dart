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
import '../services/unified_playback_controller.dart';
import '../src/rust/native_ffi.dart';
import '../src/rust/slot_lab_v2_ffi.dart';
import 'middleware_provider.dart';
import 'ale_provider.dart';

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

  /// Reset this pooled event with new data
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

  /// Release back to pool
  void release() {
    _inUse = false;
    stageType = '';
    timestampMs = 0.0;
    payload = const {};
    rawStage = const {};
  }

  /// Convert from SlotLabStageEvent
  void fromStageEvent(SlotLabStageEvent event) {
    reset(
      stageType: event.stageType,
      timestampMs: event.timestampMs,
      payload: event.payload,
      rawStage: event.rawStage,
    );
  }
}

/// Object pool for stage events to reduce GC pressure during rapid spins
class StageEventPool {
  static final StageEventPool instance = StageEventPool._();
  StageEventPool._();

  static const int _initialPoolSize = 64;
  static const int _maxPoolSize = 256;

  final List<PooledStageEvent> _pool = [];
  int _acquiredCount = 0;
  int _totalAllocations = 0;
  int _poolHits = 0;
  int _poolMisses = 0;

  /// Initialize pool with pre-allocated objects
  void init() {
    if (_pool.isEmpty) {
      for (int i = 0; i < _initialPoolSize; i++) {
        _pool.add(PooledStageEvent());
      }
      debugPrint('[StageEventPool] Initialized with $_initialPoolSize objects');
    }
  }

  /// Acquire a pooled event (reuse or allocate new)
  PooledStageEvent acquire() {
    // Find unused event in pool
    for (final event in _pool) {
      if (!event._inUse) {
        event._inUse = true;
        _acquiredCount++;
        _poolHits++;
        return event;
      }
    }

    // Pool exhausted — grow if under max
    _poolMisses++;
    if (_pool.length < _maxPoolSize) {
      final newEvent = PooledStageEvent();
      newEvent._inUse = true;
      _pool.add(newEvent);
      _acquiredCount++;
      _totalAllocations++;
      return newEvent;
    }

    // At max — create temporary (will be GC'd)
    _totalAllocations++;
    final temp = PooledStageEvent();
    temp._inUse = true;
    return temp;
  }

  /// Acquire and populate from SlotLabStageEvent
  PooledStageEvent acquireFrom(SlotLabStageEvent source) {
    final pooled = acquire();
    pooled.fromStageEvent(source);
    return pooled;
  }

  /// Release event back to pool
  void release(PooledStageEvent event) {
    event.release();
    if (_acquiredCount > 0) _acquiredCount--;
  }

  /// Release all events
  void releaseAll() {
    for (final event in _pool) {
      event.release();
    }
    _acquiredCount = 0;
  }

  /// Pool statistics
  double get hitRate => _poolHits + _poolMisses > 0
      ? _poolHits / (_poolHits + _poolMisses)
      : 1.0;

  String get statsString =>
      'Pool: ${_pool.length}/$_maxPoolSize, Acquired: $_acquiredCount, '
      'Hits: $_poolHits, Misses: $_poolMisses, Hit Rate: ${(hitRate * 100).toStringAsFixed(1)}%';

  /// Reset statistics
  void resetStats() {
    _poolHits = 0;
    _poolMisses = 0;
    _totalAllocations = 0;
  }
}

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

  // ═══════════════════════════════════════════════════════════════════════════
  // P3.1: POOLED STAGE EVENTS — Reduce allocation during spin sequences
  // ═══════════════════════════════════════════════════════════════════════════
  /// Pooled stage events for current spin (reused across spins)
  final List<PooledStageEvent> _pooledStages = [];

  /// Get pooled stages for timeline display (read-only view)
  List<PooledStageEvent> get pooledStages => List.unmodifiable(_pooledStages);

  /// Get pool statistics
  String get stagePoolStats => StageEventPool.instance.statsString;

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.18: STAGE CACHING — Avoid re-parsing JSON for same spin
  // ═══════════════════════════════════════════════════════════════════════════
  /// SpinId for which _lastStages was parsed (prevents redundant parsing)
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

  // ─── Audio Timing Configuration ─────────────────────────────────────────────
  /// P0.1: Timing configuration from Rust engine
  /// Contains audio latency compensation and pre-trigger offsets
  SlotLabTimingConfig? _timingConfig;

  /// P0.6: Pre-trigger offset for anticipation audio (ms)
  /// Audio starts this much before the visual anticipation begins
  /// Configurable via setAnticipationPreTriggerMs()
  /// DISABLED: User wants exact sync with animation — no delays
  int _anticipationPreTriggerMs = 0;

  /// P0.1: Reel stop pre-trigger offset (ms)
  /// Audio starts this much before the reel visually stops
  /// DISABLED: User wants exact sync with animation — no delays
  int _reelStopPreTriggerMs = 0;
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

  // ─── Reel Spinning State (for STOP button) ────────────────────────────────
  /// True ONLY while reels are visually spinning (SPIN_START → all REEL_STOP)
  /// Used by STOP button - should NOT include win presentation phase
  bool _isReelsSpinning = false;
  int _playbackGeneration = 0; // Incremented on each new spin to invalidate old timers

  // ─── V13: Win Presentation State (for blocking next spin) ─────────────────
  /// True during win presentation (symbol highlight, plaque, rollup, win lines)
  /// When true, new spin should be blocked or fade out first before starting
  bool _isWinPresentationActive = false;
  bool _baseMusicStarted = false; // Track if base music has been triggered

  // ─── P0.3: Anticipation Visual-Audio Sync Callbacks ────────────────────────
  /// Called when anticipation starts on a specific reel
  /// UI should dim background and slow reel animation
  /// tensionLevel: 1-4, higher = more intense (affects color: gold→orange→red-orange→red)
  void Function(int reelIndex, String reason, {int tensionLevel})? onAnticipationStart;

  /// Called when anticipation ends on a specific reel
  /// UI should restore normal speed and remove dim
  void Function(int reelIndex)? onAnticipationEnd;

  // ─── P1.2: Rollup Progress Tracking (for pitch/volume dynamics) ───────────
  double _rollupStartTimestampMs = 0.0;
  double _rollupEndTimestampMs = 0.0;
  int _rollupTickCount = 0;
  int _rollupTotalTicks = 0;

  // ─── P0.3: Pause/Resume State ─────────────────────────────────────────────
  /// True when stage playback is paused (suspended, not stopped)
  bool _isPaused = false;

  // ─── Visual-Sync Mode ─────────────────────────────────────────────────────
  /// When true, REEL_STOP events are triggered by visual animation callbacks,
  /// not by stage playback. This prevents duplicate audio triggers.
  // ═══════════════════════════════════════════════════════════════════════════
  // VISUAL-SYNC MODE: DISABLED — Engine timestamps drive all audio
  // Previous behavior: Provider skipped REEL_STOP, expected visual callback to trigger
  // Problem: premium_slot_preview.dart visual callbacks were ALSO disabled
  // Result: NOBODY triggered REEL_STOP audio!
  // FIX: Set to TRUE — slot_preview_widget triggers REEL_STOP from animation callback
  // This ensures audio plays exactly when reel VISUALLY stops, not when Rust says so.
  // Setting to false caused DOUBLE TRIGGERS (provider + widget both triggering).
  // ═══════════════════════════════════════════════════════════════════════════
  bool _useVisualSyncForReelStop = true;

  /// Timestamp when pause was initiated (for accurate resume timing)
  int _pausedAtTimestampMs = 0;

  /// Elapsed time at pause point (ms into current stage delay)
  int _pausedElapsedMs = 0;

  /// Remaining delay for the next stage when paused
  int _pausedRemainingDelayMs = 0;

  /// Scheduled next stage time (DateTime.now().millisecondsSinceEpoch + delayMs)
  int _scheduledNextStageTimeMs = 0;

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
  /// Lower zone expanded state — COLLAPSED by default (user request 2026-01-24)
  bool _persistedLowerZoneExpanded = false;
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

  /// P0.18: Cached stages from last spin (parsed once, reused for all accesses)
  /// Cache key: _cachedStagesSpinId tracks which spinId these stages belong to
  List<SlotLabStageEvent> get lastStages => _lastStages;

  /// P0.18: Get spinId for which stages are cached (for debugging/validation)
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

  bool get inFreeSpins => _inFreeSpins;
  int get freeSpinsRemaining => _freeSpinsRemaining;

  bool get autoTriggerAudio => _autoTriggerAudio;
  bool get isPlayingStages => _isPlayingStages;
  int get currentStageIndex => _currentStageIndex;
  bool get aleAutoSync => _aleAutoSync;

  /// True ONLY while reels are visually spinning (SPIN_START → all REEL_STOP)
  /// Use this for STOP button visibility - does NOT include win presentation
  bool get isReelsSpinning => _isReelsSpinning;

  /// V13: True during win presentation (symbol highlight, plaque, rollup, win lines)
  /// Used to block new spin or require fade-out before starting
  bool get isWinPresentationActive => _isWinPresentationActive;

  /// V13: Called by slot_preview_widget to update win presentation state
  void setWinPresentationActive(bool active) {
    if (_isWinPresentationActive != active) {
      _isWinPresentationActive = active;

      // Stop BIG_WIN_LOOP when win presentation ends
      if (!active) {
        eventRegistry.stopEvent('BIG_WIN_LOOP');
      }

      notifyListeners();
    }
  }

  // ─── V13: Skip Presentation with Fade-out ─────────────────────────────────────
  /// Callback to be invoked after skip fade-out completes
  VoidCallback? _pendingSkipCallback;

  /// True when skip has been requested and fade-out is in progress
  bool _skipRequested = false;
  bool get skipRequested => _skipRequested;

  /// Request skip of current win presentation with fade-out animation
  /// The slot_preview_widget will execute the fade and call onComplete when done
  void requestSkipPresentation(VoidCallback onComplete) {
    if (!_isWinPresentationActive) {
      // No presentation active, call immediately
      onComplete();
      return;
    }
    _skipRequested = true;
    _pendingSkipCallback = onComplete;
    notifyListeners(); // slot_preview_widget will see skipRequested = true
  }

  /// Called by slot_preview_widget when skip fade-out is complete
  void onSkipComplete() {
    _skipRequested = false;
    final callback = _pendingSkipCallback;
    _pendingSkipCallback = null;
    setWinPresentationActive(false);
    callback?.call();
  }

  /// P0.3: True when stage playback is paused (can be resumed)
  bool get isPaused => _isPaused;

  /// Visual-sync mode: When true, REEL_STOP events are triggered by visual
  /// animation callbacks, not by provider stage playback. Default: true.
  // ignore: unnecessary_getters_setters
  bool get useVisualSyncForReelStop => _useVisualSyncForReelStop;
  // ignore: unnecessary_getters_setters
  set useVisualSyncForReelStop(bool value) => _useVisualSyncForReelStop = value;

  /// P0.3: True when stages are playing and NOT paused
  bool get isActivelyPlaying => _isPlayingStages && !_isPaused;

  /// Called by slot_preview_widget when ALL reels have visually stopped
  /// Sets isReelsSpinning = false so STOP button hides during win presentation
  void onAllReelsVisualStop() {
    if (_isReelsSpinning) {
      _isReelsSpinning = false;
      notifyListeners();
    }
  }

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
    // DEBUG: Trace entry conditions
    debugPrint('[SlotLabProvider] spin() called: initialized=$_initialized, isSpinning=$_isSpinning');

    if (!_initialized || _isSpinning) {
      debugPrint('[SlotLabProvider] ❌ spin() BLOCKED: initialized=$_initialized, isSpinning=$_isSpinning');
      return null;
    }

    _isSpinning = true;
    notifyListeners();

    try {
      // Use V2 engine if initialized (has custom GDD config), else V1
      final int spinId;
      if (_engineV2Initialized) {
        debugPrint('[SlotLabProvider] Calling FFI slotLabV2Spin() (V2 engine with GDD)...');
        spinId = _ffi.slotLabV2Spin();
      } else {
        debugPrint('[SlotLabProvider] Calling FFI slotLabSpin() (V1 default engine)...');
        spinId = _ffi.slotLabSpin();
      }
      debugPrint('[SlotLabProvider] FFI returned spinId=$spinId');

      if (spinId == 0) {
        debugPrint('[SlotLabProvider] ❌ spinId=0, aborting');
        _isSpinning = false;
        notifyListeners();
        return null;
      }

      _spinCount++;

      // Get results from appropriate engine
      if (_engineV2Initialized) {
        _lastResult = _convertV2Result(_ffi.slotLabV2GetSpinResult());
        _lastStages = _convertV2Stages(_ffi.slotLabV2GetStages());
      } else {
        _lastResult = _ffi.slotLabGetSpinResult();
        _lastStages = _ffi.slotLabGetStages();
      }

      // P3.1: Populate pooled stages for timeline display
      _populatePooledStages();

      // P0.18: Cache stages with spinId to prevent re-parsing
      _cachedStagesSpinId = _lastResult?.spinId;

      // DEBUG: Log stage details
      debugPrint('[SlotLabProvider] Got ${_lastStages.length} stages:');
      for (int i = 0; i < _lastStages.length && i < 10; i++) {
        final s = _lastStages[i];
        debugPrint('[SlotLabProvider]   [$i] type="${s.stageType}", ts=${s.timestampMs}ms');
      }
      if (_lastStages.length > 10) {
        debugPrint('[SlotLabProvider]   ... and ${_lastStages.length - 10} more');
      }

      _updateFreeSpinsState();
      _updateStats();

      // P0.10: Validate stage sequence
      validateStageSequence();

      // Compact spin summary
      final win = _lastResult?.totalWin ?? 0;
      final isWin = _lastResult?.isWin ?? false;
      debugPrint('[Spin #$_spinCount] ${isWin ? "WIN \$${win.toStringAsFixed(2)}" : "no win"} | ${_lastStages.length} stages');

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
      // Use V2 engine if initialized (has custom GDD config), else V1
      final int spinId;
      if (_engineV2Initialized) {
        debugPrint('[SlotLabProvider] Calling FFI slotLabV2SpinForced(${outcome.index}) (V2 engine with GDD)...');
        spinId = _ffi.slotLabV2SpinForced(outcome.index);
      } else {
        debugPrint('[SlotLabProvider] Calling FFI slotLabSpinForced() (V1 default engine)...');
        spinId = _ffi.slotLabSpinForced(outcome);
      }
      if (spinId == 0) {
        _isSpinning = false;
        notifyListeners();
        return null;
      }

      _spinCount++;

      // Get results from appropriate engine
      if (_engineV2Initialized) {
        _lastResult = _convertV2Result(_ffi.slotLabV2GetSpinResult());
        _lastStages = _convertV2Stages(_ffi.slotLabV2GetStages());
      } else {
        _lastResult = _ffi.slotLabGetSpinResult();
        _lastStages = _ffi.slotLabGetStages();
      }

      // P3.1: Populate pooled stages for timeline display
      _populatePooledStages();

      // P0.18: Cache stages with spinId to prevent re-parsing
      _cachedStagesSpinId = _lastResult?.spinId;

      _updateFreeSpinsState();
      _updateStats();

      // P0.10: Validate stage sequence
      validateStageSequence();

      final win = _lastResult?.totalWin ?? 0;
      final isWin = _lastResult?.isWin ?? false;
      debugPrint('[Spin #$_spinCount ${outcome.name}] ${isWin ? "WIN \$${win.toStringAsFixed(2)}" : "no win"} | ${_lastStages.length} stages');

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

  /// P0.3: Extract reel index from stage type
  /// Examples: "ANTICIPATION_ON_3" → 3, "ANTICIPATION_OFF" → 0, "ANTICIPATION_ON" → 0
  int _extractReelIndexFromStage(String stageType) {
    final parts = stageType.split('_');
    if (parts.length >= 3) {
      final lastPart = parts.last;
      final idx = int.tryParse(lastPart);
      if (idx != null) return idx;
    }
    return 0; // Default to first reel if no index specified
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

    // ═══════════════════════════════════════════════════════════════════════════
    // DEBUG: Dump ALL stages with timing and reel indices for verification
    // ═══════════════════════════════════════════════════════════════════════════
    debugPrint('╔══════════════════════════════════════════════════════════════╗');
    debugPrint('║ STAGE PLAYBACK — ${_lastStages.length} stages                 ');
    debugPrint('╠══════════════════════════════════════════════════════════════╣');
    for (int i = 0; i < _lastStages.length; i++) {
      final s = _lastStages[i];
      final type = s.stageType.toUpperCase();
      final reelIdx = s.rawStage['reel_index'];
      final ts = s.timestampMs.toStringAsFixed(0);
      final reelInfo = reelIdx != null ? ' [reel=$reelIdx]' : '';
      debugPrint('║ [$i] ${ts.padLeft(5)}ms: $type$reelInfo');
    }
    debugPrint('╚══════════════════════════════════════════════════════════════╝');

    // Acquire SlotLab section in UnifiedPlaybackController
    final controller = UnifiedPlaybackController.instance;
    debugPrint('[SlotLabProvider] 🔒 Attempting to acquire SlotLab section...');
    debugPrint('[SlotLabProvider]   activeSection=${controller.activeSection}');

    if (!controller.acquireSection(PlaybackSection.slotLab)) {
      debugPrint('[SlotLabProvider] ❌ Failed to acquire SlotLab section!');
      debugPrint('[SlotLabProvider]   isRecording=${controller.isRecording}');
      return;
    }
    debugPrint('[SlotLabProvider] ✅ SlotLab section acquired');

    // CRITICAL: Start the audio stream WITHOUT starting transport
    // SlotLab uses one-shot voices (playFileToBus), not timeline clips
    // Using ensureStreamRunning() instead of play() prevents DAW clips from playing
    controller.ensureStreamRunning();

    // Cancel any existing playback and increment generation to invalidate old timers
    _stagePlaybackTimer?.cancel();
    _audioPreTriggerTimer?.cancel();
    _playbackGeneration++;
    _currentStageIndex = 0;
    _isPlayingStages = true;

    debugPrint('[SlotLabProvider] 🎬 Starting stage playback: _isPlayingStages=$_isPlayingStages');

    // Trigeruj prvi stage odmah
    debugPrint('[SlotLabProvider] Triggering first stage: ${_lastStages[0].stageType}');
    _triggerStage(_lastStages[0]);

    if (_lastStages.length > 1) {
      _scheduleNextStage();
    } else {
      _isPlayingStages = false;
    }

    notifyListeners();
    debugPrint('[SlotLabProvider] notifyListeners() called, _isPlayingStages=$_isPlayingStages');
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
    // PURE TIMING — No delay modifications
    // User requested: exact sync with animation, no RTPC speed changes, no offsets
    // ═══════════════════════════════════════════════════════════════════════════
    final nextStageType = nextStage.stageType.toUpperCase();

    // Capture current generation to check if timers are still valid when they fire
    final generation = _playbackGeneration;

    // Pre-trigger DISABLED — user wants exact sync with animation
    // Audio triggers EXACTLY when stage fires, no earlier

    // P0.3: Store scheduled time for pause/resume calculation
    final actualDelayMs = delayMs.clamp(10, 5000);
    _scheduledNextStageTimeMs = DateTime.now().millisecondsSinceEpoch + actualDelayMs;

    _stagePlaybackTimer = Timer(Duration(milliseconds: actualDelayMs), () {
      // Check if this timer belongs to the current playback session
      // P0.3: Also check if paused
      if (!_isPlayingStages || _playbackGeneration != generation || _isPaused) {
        debugPrint('[SlotLabProvider] Ignoring stale timer (gen: $generation, current: $_playbackGeneration, paused: $_isPaused)');
        return;
      }

      _currentStageIndex++;
      final stage = _lastStages[_currentStageIndex];

      // DIRECT TRIGGER — No pre-trigger, exact sync with animation
      _triggerStage(stage);
      notifyListeners();

      _scheduleNextStage();
    });
  }

  /// P0.1: Handle REEL_STOP UI-only logic (when audio was pre-triggered)
  /// This handles REEL_SPIN stop logic without re-triggering audio
  void _handleReelStopUIOnly(SlotLabStageEvent stage) {
    // CRITICAL: reel_index is in rawStage, not payload
    final reelIndex = stage.rawStage['reel_index'];
    // Cast to int properly (may be dynamic from JSON)
    final int? reelIdx = reelIndex is int ? reelIndex : null;

    debugPrint('[SlotLabProvider] _handleReelStopUIOnly: reelIdx=$reelIdx, totalReels=$_totalReels');

    // REEL_SPIN STOP LOGIC — Stop loop kad poslednji reel stane
    final bool shouldStopReelSpin;
    if (reelIdx != null) {
      // Ako imamo specifičan reel index, stop kad je poslednji
      shouldStopReelSpin = reelIdx >= _totalReels - 1;
      debugPrint('[SlotLabProvider] UI-only: reelIdx=$reelIdx >= ${_totalReels - 1} → shouldStop=$shouldStopReelSpin');
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
      debugPrint('[SlotLabProvider] UI-only: fallback logic → shouldStop=$shouldStopReelSpin');
    }

    if (shouldStopReelSpin) {
      eventRegistry.stopEvent('REEL_SPIN');
      debugPrint('[SlotLabProvider] REEL_SPIN stopped (UI-only, last reel, index: $reelIdx)');

      // AUTO-TRIGGER SPIN_END immediately after last reel stop
      if (eventRegistry.hasEventForStage('SPIN_END')) {
        final context = {...stage.payload, ...stage.rawStage, 'timestamp_ms': stage.timestampMs};
        eventRegistry.triggerStage('SPIN_END', context: context);
        debugPrint('[SlotLabProvider] ✅ AUTO: SPIN_END triggered (UI-only path)');
      } else {
        debugPrint('[SlotLabProvider] ⚠️ SPIN_END not triggered — no event registered (UI-only path)');
      }
    }
  }

  /// Trigger only the audio for a stage (no UI state changes)
  /// Used for P0.6 anticipation pre-trigger
  void _triggerAudioOnly(SlotLabStageEvent stage) {
    final stageType = stage.stageType.toUpperCase();
    // CRITICAL: reel_index is in rawStage, not payload
    final reelIndex = stage.rawStage['reel_index'];

    String effectiveStage = stageType;
    // CRITICAL: Include timestamp_ms for Event Log ordering display
    Map<String, dynamic> context = {...stage.payload, ...stage.rawStage, 'timestamp_ms': stage.timestampMs};

    if (stageType == 'REEL_STOP' && reelIndex != null) {
      effectiveStage = 'REEL_STOP_$reelIndex';
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // P0.4/P0.5: ANTICIPATION TENSION LAYER — Per-reel escalating audio (v2)
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType == 'ANTICIPATION_TENSION_LAYER') {
      final reelIdx = stage.payload['reel_index'] as int? ??
                      stage.rawStage['reel_index'] as int? ?? 0;
      final tensionLevel = stage.payload['tension_level'] as int? ??
                          stage.rawStage['tension_level'] as int? ?? 1;
      final progress = (stage.payload['progress'] as num?)?.toDouble() ??
                      (stage.rawStage['progress'] as num?)?.toDouble() ?? 0.0;

      // Per-reel volume/pitch escalation
      context['volumeMultiplier'] = 0.5 + (tensionLevel * 0.1);
      context['pitchSemitones'] = tensionLevel.toDouble();
      context['tensionLevel'] = tensionLevel;
      context['progress'] = progress;

      // Map to stage name for EventRegistry
      effectiveStage = 'ANTICIPATION_TENSION_R${reelIdx}_L$tensionLevel';
    }
    // ═══════════════════════════════════════════════════════════════════════════
    // P1.2: NEAR MISS AUDIO ESCALATION — Intensity-based anticipation (legacy)
    // ═══════════════════════════════════════════════════════════════════════════
    else if (stageType == 'ANTICIPATION_ON') {
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
    // CRITICAL: Include timestamp_ms for Event Log ordering display
    Map<String, dynamic> context = {
      ...stage.payload,
      ...stage.rawStage,
      'timestamp_ms': stage.timestampMs,
    };

    // ═══════════════════════════════════════════════════════════════════════════
    // VISUAL-SYNC MODE: Skip REEL_STOP in provider — handled by animation callback
    // This prevents duplicate audio (provider + visual callback both triggering)
    // ═══════════════════════════════════════════════════════════════════════════
    if (_useVisualSyncForReelStop && stageType == 'REEL_STOP') {
      debugPrint('[Stage] REEL_STOP [$reelIndex] → SKIPPED (visual-sync mode)');
      return; // Visual callback in slot_preview_widget.dart will handle this
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ═══════════════════════════════════════════════════════════════════════════
    // V12: WIN PRESENTATION VISUAL-SYNC — Skip ALL win/presentation stages
    // These stages are handled by slot_preview_widget.dart's 3-phase win presentation:
    // - Phase 1: WIN_SYMBOL_HIGHLIGHT_* (symbol glow/bounce, includes symbol-specific)
    // - Phase 2: WIN_PRESENT_* + ROLLUP_* (plaque + counter, tier-specific)
    // - Phase 3: WIN_LINE_SHOW (win line cycling)
    // - Big Win: BIG_WIN_*, WIN_TIER_*
    // Provider should NOT trigger these — Dart widget handles timing!
    // ═══════════════════════════════════════════════════════════════════════════

    // Exact match stages
    const winPresentationStagesExact = {
      'WIN_LINE_SHOW',
      'WIN_LINE_HIDE',
      'ROLLUP_START',
      'ROLLUP_TICK',
      'ROLLUP_END',
      'BIG_WIN_INTRO',
      'BIG_WIN_END',
    };

    // Pattern prefixes — widget triggers dynamic versions of these
    const winPresentationPrefixes = [
      'WIN_SYMBOL_HIGHLIGHT',  // WIN_SYMBOL_HIGHLIGHT, WIN_SYMBOL_HIGHLIGHT_HP1, etc.
      'WIN_PRESENT',           // WIN_PRESENT_SMALL, WIN_PRESENT_BIG, etc.
      'WIN_TIER',              // WIN_TIER_BIG, WIN_TIER_MEGA, etc.
    ];

    // Check exact matches
    if (winPresentationStagesExact.contains(stageType)) {
      debugPrint('[Stage] $stageType → SKIPPED (visual-sync, widget handles)');
      return;
    }

    // Check pattern prefixes
    for (final prefix in winPresentationPrefixes) {
      if (stageType == prefix || stageType.startsWith('${prefix}_')) {
        debugPrint('[Stage] $stageType → SKIPPED (visual-sync, widget handles)');
        return;
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // P0.3: ANTICIPATION VISUAL-AUDIO SYNC — Invoke callbacks for synchronized visuals
    // Callbacks notify UI to dim background and slow reel animation at SAME TIME as audio
    // Includes per-reel variants (ANTICIPATION_ON_0, etc.)
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType.startsWith('ANTICIPATION_ON')) {
      final reelIdx = _extractReelIndexFromStage(stageType);
      final reason = stage.payload['reason'] as String? ??
          stage.rawStage['reason'] as String? ?? 'scatter';
      // Calculate tension level based on reel position: R1=L1, R2=L2, etc. (max L4)
      final tensionLevel = reelIdx.clamp(1, 4);
      debugPrint('[Stage] P0.3: ANTICIPATION_ON → invoking onAnticipationStart(reel=$reelIdx, reason=$reason, tension=L$tensionLevel)');
      onAnticipationStart?.call(reelIdx, reason, tensionLevel: tensionLevel);
      // Continue to trigger audio below (don't return)
    } else if (stageType.startsWith('ANTICIPATION_OFF')) {
      final reelIdx = _extractReelIndexFromStage(stageType);
      debugPrint('[Stage] P0.3: ANTICIPATION_OFF → invoking onAnticipationEnd(reel=$reelIdx)');
      onAnticipationEnd?.call(reelIdx);
      // Continue to trigger audio below (don't return)
    }

    // Simplified debug - only show stage name, skip per-reel spam for REEL_SPINNING
    if (stageType != 'REEL_SPINNING') {
      debugPrint('[Stage] $stageType${reelIndex != null ? " [$reelIndex]" : ""}');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CENTRALNI EVENT REGISTRY — JEDINI izvor audio playback-a
    // Legacy sistemi (Middleware postEvent, StageAudioMapper) su ONEMOGUĆENI
    // jer izazivaju dupli audio playback
    // ═══════════════════════════════════════════════════════════════════════════

    // Za REEL_STOP, koristi specifičan stage po reel-u: REEL_STOP_0, REEL_STOP_1, itd.
    String effectiveStage = stageType;

    // ═══════════════════════════════════════════════════════════════════════════
    // P0.4/P0.5: ANTICIPATION TENSION LAYER — Per-reel escalating audio
    // New industry-standard stage with reel_index, tension_level (1-4), progress
    // Each subsequent reel has HIGHER tension level for crescendo effect
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType == 'ANTICIPATION_TENSION_LAYER') {
      final reelIdx = stage.payload['reel_index'] as int? ??
                      stage.rawStage['reel_index'] as int? ?? 0;
      final tensionLevel = stage.payload['tension_level'] as int? ??
                          stage.rawStage['tension_level'] as int? ?? 1;
      final progress = (stage.payload['progress'] as num?)?.toDouble() ??
                      (stage.rawStage['progress'] as num?)?.toDouble() ?? 0.0;
      final reason = stage.payload['reason'] as String? ??
                    stage.rawStage['reason'] as String? ?? 'scatter';

      // Per-reel volume escalation: L1=0.6, L2=0.7, L3=0.8, L4=0.9
      final volumeMultiplier = 0.5 + (tensionLevel * 0.1);
      context['volumeMultiplier'] = volumeMultiplier;

      // Per-reel pitch escalation: R2=+1st, R3=+2st, R4=+3st, R5=+4st
      final pitchSemitones = tensionLevel.toDouble();
      context['pitchSemitones'] = pitchSemitones;

      // P2.3: Per-reel filter sweep DSP — cutoff rises with tension
      // L1=500Hz, L2=2000Hz, L3=5000Hz, L4=8000Hz (low→high pass sweep)
      final filterCutoffHz = switch (tensionLevel) {
        1 => 500.0,
        2 => 2000.0,
        3 => 5000.0,
        4 => 8000.0,
        _ => 500.0 + (tensionLevel * 1875.0), // Linear fallback
      };
      context['filterCutoffHz'] = filterCutoffHz;
      // Filter resonance increases slightly with tension
      context['filterResonance'] = 0.5 + (tensionLevel * 0.1); // 0.6 to 0.9

      // Per-reel color (for visual sync callback)
      final colors = ['#FFD700', '#FFA500', '#FF6347', '#FF4500']; // gold→orange→red-orange→red
      final colorIndex = (tensionLevel - 1).clamp(0, 3);
      context['glowColor'] = colors[colorIndex];
      context['tensionLevel'] = tensionLevel;
      context['progress'] = progress;

      // Invoke visual callback for anticipation start (if not already invoked by ANTICIPATION_ON)
      if (progress == 0.0) {
        debugPrint('[Stage] P0.4: ANTICIPATION_TENSION_LAYER reel=$reelIdx, level=$tensionLevel, reason=$reason');
        onAnticipationStart?.call(reelIdx, reason, tensionLevel: tensionLevel);
      }

      // Map to stage name for EventRegistry: ANTICIPATION_TENSION_R{reel}_L{level}
      effectiveStage = 'ANTICIPATION_TENSION_R${reelIdx}_L$tensionLevel';
      debugPrint('[SlotLabProvider] P0.5 Tension: reel=$reelIdx L$tensionLevel vol=${volumeMultiplier.toStringAsFixed(2)} pitch=+${pitchSemitones.toInt()}st filter=${filterCutoffHz.toInt()}Hz');
    }
    // ═══════════════════════════════════════════════════════════════════════════
    // P1.2: NEAR MISS AUDIO ESCALATION — Intensity-based anticipation (legacy)
    // ═══════════════════════════════════════════════════════════════════════════
    else if (stageType == 'ANTICIPATION_ON') {
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

    // ═══════════════════════════════════════════════════════════════════════════
    // P1.2: ROLLUP PITCH/VOLUME DYNAMICS — Progress-based escalation
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType == 'ROLLUP_START') {
      // Scan remaining stages to find ROLLUP_END timestamp
      _rollupStartTimestampMs = stage.timestampMs;
      _rollupTickCount = 0;
      _rollupTotalTicks = 0;

      // Count total ROLLUP_TICKs and find ROLLUP_END
      for (final s in _lastStages) {
        final sType = s.stageType.toUpperCase();
        if (sType == 'ROLLUP_TICK') _rollupTotalTicks++;
        if (sType == 'ROLLUP_END') {
          _rollupEndTimestampMs = s.timestampMs;
        }
      }
      debugPrint('[SlotLabProvider] P1.2 ROLLUP_START: duration=${(_rollupEndTimestampMs - _rollupStartTimestampMs).toInt()}ms, ticks=$_rollupTotalTicks');
    } else if (stageType == 'ROLLUP_TICK') {
      _rollupTickCount++;

      // Calculate progress (0.0 to 1.0)
      double progress = 0.0;
      if (_rollupTotalTicks > 0) {
        progress = _rollupTickCount / _rollupTotalTicks;
      } else if (_rollupEndTimestampMs > _rollupStartTimestampMs) {
        final elapsed = stage.timestampMs - _rollupStartTimestampMs;
        final total = _rollupEndTimestampMs - _rollupStartTimestampMs;
        progress = (elapsed / total).clamp(0.0, 1.0);
      }

      // Add progress to context — EventRegistry will use this for pitch/volume modulation
      context['progress'] = progress;
      debugPrint('[SlotLabProvider] P1.2 ROLLUP_TICK: progress=${progress.toStringAsFixed(2)} (tick $_rollupTickCount/$_rollupTotalTicks)');
    } else if (stageType == 'ROLLUP_END') {
      // Reset rollup tracking
      _rollupStartTimestampMs = 0.0;
      _rollupEndTimestampMs = 0.0;
      _rollupTickCount = 0;
      _rollupTotalTicks = 0;
      debugPrint('[SlotLabProvider] P1.2 ROLLUP_END: resetting rollup tracking');
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // P0: PER-REEL SPINNING — Each reel has its own spin loop for independent fade-out
    // ═══════════════════════════════════════════════════════════════════════════
    if ((stageType == 'REEL_SPINNING' || stageType == 'reel_spinning') && reelIndex != null) {
      effectiveStage = 'REEL_SPINNING_$reelIndex';
      // Pass reel_index to EventRegistry for voice tracking
      context['reel_index'] = reelIndex;
      context['is_reel_spin_loop'] = true; // Flag for voice tracking
      debugPrint('[SlotLabProvider] P0 Per-reel spin: $effectiveStage');
    }

    if (stageType == 'REEL_STOP' && reelIndex != null) {
      effectiveStage = 'REEL_STOP_$reelIndex';
      // P0: Tell EventRegistry to fade out this reel's spin loop
      context['fade_out_spin_reel'] = reelIndex;
      // DEBUG: Detailed logging for REEL_STOP issue
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('[REEL_STOP] 🎰 RAW DATA:');
      debugPrint('  rawStage = ${stage.rawStage}');
      debugPrint('  reel_index type = ${reelIndex.runtimeType}, value = $reelIndex');
      debugPrint('  effectiveStage = $effectiveStage');
      debugPrint('  timestampMs = ${stage.timestampMs.toStringAsFixed(0)}ms');
      debugPrint('═══════════════════════════════════════════════════════════');

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
    final bool hasSpecific = eventRegistry.hasEventForStage(effectiveStage);
    final bool hasFallback = effectiveStage != stageType && eventRegistry.hasEventForStage(stageType);
    final bool hasGeneric = eventRegistry.hasEventForStage(stageType);

    // DEBUG: Log which path is taken for REEL_STOP
    if (stageType == 'REEL_STOP') {
      debugPrint('[REEL_STOP] 🔍 EVENT LOOKUP:');
      debugPrint('  effectiveStage = "$effectiveStage"');
      debugPrint('  stageType = "$stageType"');
      debugPrint('  hasSpecific($effectiveStage) = $hasSpecific');
      debugPrint('  hasFallback($stageType) = $hasFallback');
      debugPrint('  hasGeneric($stageType) = $hasGeneric');
      // List all registered stages containing REEL
      final allReelStages = eventRegistry.registeredStages
          .where((s) => s.contains('REEL'))
          .toList();
      debugPrint('  registered REEL stages: $allReelStages');
    }

    if (hasSpecific) {
      if (stageType == 'REEL_STOP') debugPrint('[REEL_STOP] ✅ TRIGGERING: $effectiveStage (specific)');
      eventRegistry.triggerStage(effectiveStage, context: context);
    } else if (hasFallback) {
      if (stageType == 'REEL_STOP') debugPrint('[REEL_STOP] ⚠️ TRIGGERING: $stageType (fallback from $effectiveStage)');
      eventRegistry.triggerStage(stageType, context: context);
    } else {
      // STILL trigger so Event Log shows the stage (even without audio)
      if (stageType == 'REEL_STOP') debugPrint('[REEL_STOP] ❌ TRIGGERING: $stageType (no audio event)');
      eventRegistry.triggerStage(stageType, context: context);
    }

    // Za SPIN_START, trigeruj i REEL_SPIN (loop audio dok se vrti)
    if (stageType == 'SPIN_START' && eventRegistry.hasEventForStage('REEL_SPIN')) {
      eventRegistry.triggerStage('REEL_SPIN', context: context);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REEL SPINNING STATE — For STOP button visibility
    // Set true at SPIN_START, set false via onAllReelsVisualStop() callback
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType == 'SPIN_START') {
      _isReelsSpinning = true;
      notifyListeners();
    }

    // MUSIC AUTO-TRIGGER: Start base music on first SPIN_START
    if (stageType == 'SPIN_START' && !_baseMusicStarted) {
      if (eventRegistry.hasEventForStage('MUSIC_BASE')) {
        eventRegistry.triggerStage('MUSIC_BASE', context: context);
        _baseMusicStarted = true;
      }
      if (eventRegistry.hasEventForStage('GAME_START')) {
        eventRegistry.triggerStage('GAME_START', context: context);
      }
    }

    // REEL_SPIN STOP LOGIC — Stop loop kad poslednji reel stane
    if (stageType == 'REEL_STOP') {
      final bool shouldStopReelSpin;
      // CRITICAL: reelIndex may be dynamic (int or null), cast properly
      final int? reelIdx = reelIndex is int ? reelIndex : null;

      if (reelIdx != null) {
        shouldStopReelSpin = reelIdx >= _totalReels - 1;
      } else {
        // Generički REEL_STOP — proveri da li je poslednji
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
        eventRegistry.stopEvent('REEL_SPIN');
        if (eventRegistry.hasEventForStage('SPIN_END')) {
          eventRegistry.triggerStage('SPIN_END', context: context);
          debugPrint('[Stage] SPIN_END (auto after last REEL_STOP)');
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SPIN_END: Handle explicit SPIN_END stage from Rust (backup)
    if (stageType == 'SPIN_END') {
      eventRegistry.stopEvent('REEL_SPIN');
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

  /// Stop stage playback (full reset)
  void stopStagePlayback() {
    _stagePlaybackTimer?.cancel();
    _audioPreTriggerTimer?.cancel();
    _isPlayingStages = false;
    _isReelsSpinning = false; // CRITICAL: Reset so next SPACE starts new spin
    _isPaused = false; // P0.3: Reset pause state
    _pausedAtTimestampMs = 0;
    _pausedElapsedMs = 0;
    _pausedRemainingDelayMs = 0;
    _currentStageIndex = 0; // P0.3: Reset to beginning
    // Release SlotLab section
    UnifiedPlaybackController.instance.releaseSection(PlaybackSection.slotLab);
    debugPrint('[SlotLabProvider] Stage playback STOPPED (full reset)');
    notifyListeners();
  }

  /// Alias for stopStagePlayback - used by mode switch isolation
  void stopAllPlayback() => stopStagePlayback();

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE RECORDING SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  bool _isRecordingStages = false;

  /// Whether stages are being recorded
  bool get isRecordingStages => _isRecordingStages;

  /// Start recording stage events
  void startStageRecording() {
    if (_isRecordingStages) return;
    _isRecordingStages = true;
    debugPrint('[SlotLabProvider] Stage recording STARTED');
    notifyListeners();
  }

  /// Stop recording stage events
  void stopStageRecording() {
    if (!_isRecordingStages) return;
    _isRecordingStages = false;
    debugPrint('[SlotLabProvider] Stage recording STOPPED (${_lastStages.length} stages captured)');
    notifyListeners();
  }

  /// Clear all captured stages
  void clearStages() {
    _lastStages = [];
    _currentStageIndex = 0;
    _cachedStagesSpinId = null; // P0.18: Clear cache
    debugPrint('[SlotLabProvider] Stages cleared');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.3: PAUSE/RESUME SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pause stage playback (suspend timers, preserve position)
  ///
  /// Unlike stop(), pause() preserves:
  /// - Current stage index
  /// - Playback generation
  /// - Section acquisition
  /// - Remaining delay for next stage
  ///
  /// Call [resumeStages()] to continue from paused position.
  void pauseStages() {
    if (!_isPlayingStages || _isPaused) {
      debugPrint('[SlotLabProvider] pauseStages() ignored - not playing or already paused');
      return;
    }

    // Calculate how much time has elapsed since we scheduled the next stage
    final now = DateTime.now().millisecondsSinceEpoch;
    _pausedAtTimestampMs = now;

    // Calculate remaining delay
    if (_scheduledNextStageTimeMs > now) {
      _pausedRemainingDelayMs = _scheduledNextStageTimeMs - now;
    } else {
      _pausedRemainingDelayMs = 0;
    }

    // Cancel timers but DON'T cancel generation (so we can resume)
    _stagePlaybackTimer?.cancel();
    _audioPreTriggerTimer?.cancel();

    _isPaused = true;

    // Pause Rust engine audio (delegates to UnifiedPlaybackController)
    UnifiedPlaybackController.instance.pause();

    debugPrint('[SlotLabProvider] Stages PAUSED at index $_currentStageIndex, remaining delay: ${_pausedRemainingDelayMs}ms');
    notifyListeners();
  }

  /// Resume paused stage playback
  ///
  /// Continues from where pause() left off:
  /// - Same stage index
  /// - Uses remaining delay (not full delay)
  /// - Restarts audio engine
  void resumeStages() {
    if (!_isPlayingStages || !_isPaused) {
      debugPrint('[SlotLabProvider] resumeStages() ignored - not paused');
      return;
    }

    _isPaused = false;

    // Resume Rust engine audio
    UnifiedPlaybackController.instance.play();

    // If we have remaining delay, schedule the next stage with that delay
    if (_pausedRemainingDelayMs > 0 && _currentStageIndex < _lastStages.length - 1) {
      _scheduleNextStageWithDelay(_pausedRemainingDelayMs);
      debugPrint('[SlotLabProvider] Stages RESUMED from index $_currentStageIndex with ${_pausedRemainingDelayMs}ms remaining');
    } else if (_currentStageIndex < _lastStages.length - 1) {
      // No remaining delay, just schedule normally
      _scheduleNextStage();
      debugPrint('[SlotLabProvider] Stages RESUMED from index $_currentStageIndex (no delay remaining)');
    } else {
      // We were at the last stage
      _isPlayingStages = false;
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.slotLab);
      debugPrint('[SlotLabProvider] Stages RESUMED but already at end - completing');
    }

    _pausedRemainingDelayMs = 0;
    _pausedAtTimestampMs = 0;

    notifyListeners();
  }

  /// Toggle between paused and playing state
  ///
  /// Convenience method for UI buttons:
  /// - If playing → pause
  /// - If paused → resume
  /// - If stopped → do nothing (use spin() to start)
  void togglePauseResume() {
    if (_isPaused) {
      resumeStages();
    } else if (_isPlayingStages) {
      pauseStages();
    }
    // If not playing at all, do nothing - user needs to spin first
  }

  /// Schedule next stage with explicit delay (used for resume)
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
      // Check if playback was cancelled or paused
      if (!_isPlayingStages || _playbackGeneration != generation || _isPaused) {
        debugPrint('[SlotLabProvider] Timer fired but playback invalid (gen: $generation vs $_playbackGeneration, paused: $_isPaused)');
        return;
      }

      _currentStageIndex++;
      _triggerStage(_lastStages[_currentStageIndex]);
      _scheduleNextStage();
    });
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
  // P0.10: STAGE SEQUENCE VALIDATION
  // Validates stage ordering for QA and regression testing
  // ═══════════════════════════════════════════════════════════════════════════

  /// Validation result for stage sequence
  List<StageValidationIssue> _lastValidationIssues = [];

  /// Get last validation issues
  List<StageValidationIssue> get lastValidationIssues => _lastValidationIssues;

  /// Check if last stages passed validation
  bool get stagesValid => _lastValidationIssues.isEmpty;

  /// Validate the current stage sequence
  /// Returns list of validation issues (empty if valid)
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

    // 1. SPIN_START must be first
    if (stageTypes.isNotEmpty && stageTypes.first != 'SPIN_START') {
      issues.add(StageValidationIssue(
        type: StageValidationType.orderViolation,
        message: 'SPIN_START must be first stage (found: ${stageTypes.first})',
        severity: StageValidationSeverity.error,
        stageIndex: 0,
      ));
    }

    // 2. SPIN_END must be last
    if (stageTypes.isNotEmpty && stageTypes.last != 'SPIN_END') {
      issues.add(StageValidationIssue(
        type: StageValidationType.orderViolation,
        message: 'SPIN_END must be last stage (found: ${stageTypes.last})',
        severity: StageValidationSeverity.warning,
        stageIndex: stageTypes.length - 1,
      ));
    }

    // 3. Timestamps must be monotonically increasing
    for (int i = 1; i < _lastStages.length; i++) {
      if (_lastStages[i].timestampMs < _lastStages[i - 1].timestampMs) {
        issues.add(StageValidationIssue(
          type: StageValidationType.timestampViolation,
          message: 'Timestamp decreased at stage $i: ${_lastStages[i].timestampMs}ms < ${_lastStages[i - 1].timestampMs}ms',
          severity: StageValidationSeverity.error,
          stageIndex: i,
        ));
      }
    }

    // 4. Required stages check
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

    // 5. REEL_STOP must come after REEL_SPINNING (if both present)
    final reelSpinIdx = stageTypes.indexWhere((s) => s.startsWith('REEL_SPINNING'));
    final reelStopIdx = stageTypes.indexWhere((s) => s.startsWith('REEL_STOP'));
    if (reelSpinIdx >= 0 && reelStopIdx >= 0 && reelStopIdx < reelSpinIdx) {
      issues.add(StageValidationIssue(
        type: StageValidationType.orderViolation,
        message: 'REEL_STOP ($reelStopIdx) before REEL_SPINNING ($reelSpinIdx)',
        severity: StageValidationSeverity.error,
        stageIndex: reelStopIdx,
      ));
    }

    // 6. WIN_PRESENT must come after all REEL_STOP (if present)
    final winPresentIdx = stageTypes.indexWhere((s) => s.startsWith('WIN_PRESENT'));
    final lastReelStopIdx = stageTypes.lastIndexWhere((s) => s.startsWith('REEL_STOP'));
    if (winPresentIdx >= 0 && lastReelStopIdx >= 0 && winPresentIdx < lastReelStopIdx) {
      issues.add(StageValidationIssue(
        type: StageValidationType.orderViolation,
        message: 'WIN_PRESENT ($winPresentIdx) before last REEL_STOP ($lastReelStopIdx)',
        severity: StageValidationSeverity.warning,
        stageIndex: winPresentIdx,
      ));
    }

    // Log validation result
    if (issues.isEmpty) {
      debugPrint('[SlotLabProvider] P0.10: Stage sequence VALID (${_lastStages.length} stages)');
    } else {
      debugPrint('[SlotLabProvider] P0.10: Stage sequence INVALID (${issues.length} issues):');
      for (final issue in issues) {
        debugPrint('  [${issue.severity.name}] ${issue.message}');
      }
    }

    _lastValidationIssues = issues;
    notifyListeners();
    return issues;
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

    // P3.1: Initialize stage event pool
    StageEventPool.instance.init();

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

  /// Convert V2 spin result Map to SlotLabSpinResult
  SlotLabSpinResult? _convertV2Result(Map<String, dynamic>? v2Result) {
    if (v2Result == null) return null;
    return SlotLabSpinResult.fromJson(v2Result);
  }

  /// Convert V2 stages List to List<SlotLabStageEvent>
  List<SlotLabStageEvent> _convertV2Stages(List<Map<String, dynamic>> v2Stages) {
    return v2Stages.map((s) => SlotLabStageEvent.fromJson(s)).toList();
  }

  /// P3.1: Populate pooled stages from current _lastStages
  /// Reuses objects from pool to reduce GC pressure
  void _populatePooledStages() {
    final pool = StageEventPool.instance;

    // Release previous pooled stages back to pool
    for (final pooled in _pooledStages) {
      pool.release(pooled);
    }
    _pooledStages.clear();

    // Acquire pooled events for current stages
    for (final stage in _lastStages) {
      final pooled = pool.acquireFrom(stage);
      _pooledStages.add(pooled);
    }
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
