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
import '../models/win_tier_config.dart';
import '../services/event_registry.dart';
import '../services/container_service.dart';
import '../services/audio_pool.dart';
import '../services/audio_asset_manager.dart';
import '../services/stage_configuration_service.dart';
import '../services/unified_playback_controller.dart';
import '../services/win_analytics_service.dart';
import '../src/rust/native_ffi.dart';
import '../src/rust/slot_lab_v2_ffi.dart';
import 'package:get_it/get_it.dart';

import '../services/diagnostics/diagnostics_service.dart';
import 'middleware_provider.dart';
import 'ale_provider.dart';
import 'slot_lab_project_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// P7.2.3: ANTICIPATION CONFIGURATION TYPE — Industry-standard trigger rules
// ═══════════════════════════════════════════════════════════════════════════

/// Anticipation configuration type
/// - tipA: Scatter on ALL reels, 3+ triggers for feature, 2+ for anticipation
/// - tipB: Scatter on specific reels (e.g., 0,2,4), must land on BOTH first two
enum AnticipationConfigType {
  /// Tip A: Universal rule — Scatter on all reels (0,1,2,3,4)
  /// 2 triggers = anticipation on remaining reels
  /// 3+ triggers = feature trigger
  tipA,

  /// Tip B: Restricted rule — Scatter only on specific reels (default: 0,2,4)
  /// Scatter MUST land on BOTH first two allowed reels for anticipation
  /// e.g., reels 0 AND 2 must have scatter for anticipation on reel 4
  tipB,
}

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

  // ─── Win Tier Configuration ────────────────────────────────────────────────
  /// P5 data-driven win tier configuration.
  /// Regular: WIN_LOW, WIN_EQUAL, WIN_1–WIN_5
  /// Big: BIG_WIN_TIER_1–BIG_WIN_TIER_5
  SlotWinConfiguration _slotWinConfig = SlotWinConfiguration.defaultConfig();

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

  // ─── P5 Win Tier Integration ─────────────────────────────────────────────────
  /// When true, uses P5 dynamic win tier evaluation from SlotLabProjectProvider
  /// instead of legacy hardcoded thresholds. This enables user-configurable
  /// win tier ranges, display labels, and rollup durations.
  bool _useP5WinTier = true;

  /// Getter for P5 win tier mode
  bool get useP5WinTier => _useP5WinTier;

  /// Enable/disable P5 win tier evaluation
  void setUseP5WinTier(bool enabled) {
    _useP5WinTier = enabled;
    notifyListeners();
  }

  // ─── Free Spins State ──────────────────────────────────────────────────────
  bool _inFreeSpins = false;
  int _freeSpinsRemaining = 0;
  int _freeSpinsTotal = 0;

  // ─── Audio Integration ─────────────────────────────────────────────────────
  MiddlewareProvider? _middleware;
  bool _autoTriggerAudio = true;

  // ─── ALE Integration ──────────────────────────────────────────────────────
  AleProvider? _aleProvider;
  bool _aleAutoSync = true;

  // ─── Stage Event Playback ──────────────────────────────────────────────────
  Timer? _stagePlaybackTimer;
  Timer? _audioPreTriggerTimer; // P0.6: Separate timer for audio pre-trigger
  int _currentStageIndex = 0;
  bool _isPlayingStages = false;
  int _totalReels = 3; // Default 3×3 (matches Rust engine default)

  // ─── Reel Spinning State (for STOP button) ────────────────────────────────
  /// True ONLY while reels are visually spinning (UI_SPIN_PRESS → all REEL_STOP)
  /// Used by STOP button - should NOT include win presentation phase
  bool _isReelsSpinning = false;
  bool _spinEndTriggered = false; // Guard: prevents double SPIN_END audio trigger
  int _playbackGeneration = 0; // Incremented on each new spin to invalidate old timers

  // ─── V13: Win Presentation State (for blocking next spin) ─────────────────
  /// True during win presentation (symbol highlight, plaque, rollup, win lines)
  /// When true, new spin should be blocked or fade out first before starting
  bool _isWinPresentationActive = false;
  bool _baseMusicStarted = false; // Track if MUSIC_BASE has been triggered
  bool _gameStartTriggered = false; // Track if GAME_START has been triggered

  // ─── P0.3: Anticipation Visual-Audio Sync Callbacks ────────────────────────
  /// Called when anticipation starts on a specific reel
  /// UI should dim background and slow reel animation
  /// tensionLevel: 1-4, higher = more intense (affects color: gold→orange→red-orange→red)
  void Function(int reelIndex, String reason, {int tensionLevel})? onAnticipationStart;

  /// Called when anticipation ends on a specific reel
  /// UI should restore normal speed and remove dim
  void Function(int reelIndex)? onAnticipationEnd;

  // ═══════════════════════════════════════════════════════════════════════════
  // P7.2.3: ANTICIPATION CONFIGURATION — Industry-standard trigger rules
  // Two types supported:
  //   Tip A: Scatter on ALL reels (0,1,2,3,4), 3+ triggers for feature, 2 for anticipation
  //   Tip B: Scatter on specific reels (e.g., 0,2,4), must land on BOTH first two allowed
  // Wild symbols NEVER trigger anticipation.
  // ═══════════════════════════════════════════════════════════════════════════
  AnticipationConfigType _anticipationConfigType = AnticipationConfigType.tipA;

  /// Current anticipation configuration
  AnticipationConfigType get anticipationConfigType => _anticipationConfigType;

  /// Scatter symbol ID for anticipation detection (default: 12)
  int _scatterSymbolId = 12;
  int get scatterSymbolId => _scatterSymbolId;

  /// Bonus symbol ID (default: 11)
  int _bonusSymbolId = 11;
  int get bonusSymbolId => _bonusSymbolId;

  /// Allowed reels for Tip B configuration (default: 0, 2, 4)
  List<int> _tipBAllowedReels = [0, 2, 4];
  List<int> get tipBAllowedReels => List.unmodifiable(_tipBAllowedReels);

  /// Set anticipation configuration type
  void setAnticipationConfigType(AnticipationConfigType type) {
    _anticipationConfigType = type;
    notifyListeners();
  }

  /// Set scatter symbol ID for anticipation detection
  void setScatterSymbolId(int symbolId) {
    _scatterSymbolId = symbolId;
    notifyListeners();
  }

  /// Set bonus symbol ID
  void setBonusSymbolId(int symbolId) {
    _bonusSymbolId = symbolId;
    notifyListeners();
  }

  /// Set allowed reels for Tip B configuration
  void setTipBAllowedReels(List<int> reels) {
    _tipBAllowedReels = List.from(reels)..sort();
    notifyListeners();
  }

  /// Check if a symbol can trigger anticipation
  /// Wild symbols (ID 10) NEVER trigger anticipation
  bool canTriggerAnticipation(int symbolId) {
    const wildSymbolId = 10; // StandardSymbolSet Wild ID
    if (symbolId == wildSymbolId) return false;
    return symbolId == _scatterSymbolId || symbolId == _bonusSymbolId;
  }

  /// P7.2.3: Check if anticipation should trigger based on current config
  /// For Tip B: Returns true only if triggers landed on BOTH first two allowed reels
  bool shouldTriggerAnticipation(Set<int> triggerReels) {
    if (triggerReels.length < 2) return false;

    if (_anticipationConfigType == AnticipationConfigType.tipB) {
      // Tip B: Must land on BOTH first two allowed reels
      if (_tipBAllowedReels.length < 2) return false;
      final firstTwo = _tipBAllowedReels.take(2).toSet();
      return firstTwo.every((r) => triggerReels.contains(r));
    } else {
      // Tip A: Any 2+ triggers activate anticipation
      return triggerReels.length >= 2;
    }
  }

  /// P7.2.3: Get anticipation reels based on current config
  /// Returns list of reels that should show anticipation effect
  List<int> getAnticipationReels(Set<int> triggerReels, int totalReels) {
    final result = <int>[];

    if (_anticipationConfigType == AnticipationConfigType.tipB) {
      // Tip B: Only anticipate on allowed reels that haven't triggered yet
      for (final reel in _tipBAllowedReels) {
        if (!triggerReels.contains(reel) && reel < totalReels) {
          result.add(reel);
        }
      }
    } else {
      // Tip A: Anticipate on all remaining reels
      for (int r = 0; r < totalReels; r++) {
        if (!triggerReels.contains(r)) {
          result.add(r);
        }
      }
    }

    return result..sort();
  }

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

  /// Get the current P5 win tier configuration
  SlotWinConfiguration get slotWinConfig => _slotWinConfig;

  /// Set a new P5 win tier configuration
  void setSlotWinConfig(SlotWinConfiguration config) {
    _slotWinConfig = config;
    notifyListeners();
  }

  // ─── Grid Configuration ─────────────────────────────────────────────────────

  int _totalRows = 3; // Default rows

  /// Current reel count
  int get totalReels => _totalReels;

  /// Current row count
  int get totalRows => _totalRows;

  /// Update grid dimensions (called from Feature Builder)
  void updateGridSize(int reels, int rows) {
    final changed = reels != _totalReels || rows != _totalRows;
    _totalReels = reels;
    _totalRows = rows;

    if (changed && _initialized) {
      // Direct FFI call — no need to shutdown+reinit the whole engine
      try {
        _ffi.slotLabSetGridSize(reels, rows);
      } catch (_) { /* ignore FFI errors */ }
      // Clear last spin result so grid shows blank cells
      _lastResult = null;
      // Reset music flags — new grid means new slot machine config
      _baseMusicStarted = false;
      _gameStartTriggered = false;
    }

    // Always notify — even if dimensions unchanged, config state may have changed
    // (e.g. FeatureComposerProvider.isConfigured flipped to true)
    notifyListeners();
  }

  /// Reinitialize the Rust engine with current grid dimensions.
  /// V1 engine doesn't accept grid params, so we shutdown + reinit.
  /// SlotPreviewWidget handles grid mismatch by padding with random symbols.
  void _reinitializeEngine() {
    try {
      _ffi.slotLabShutdown();
      _initialized = false;
      final success = _ffi.slotLabInit();
      if (success) {
        _initialized = true;
        // Apply current grid dimensions to newly initialized engine
        // Without this, engine resets to default 3×3 on every reinit
        _ffi.slotLabSetGridSize(_totalReels, _totalRows);
      }
    } catch (_) { /* ignore FFI errors during reinit */ }
  }

  /// Get the visual tier name for a win amount (P5 system)
  /// Returns: '', 'WIN_1'–'WIN_5', or 'BIG_WIN_TIER_1'–'BIG_WIN_TIER_5'
  String getVisualTierForWin(double winAmount) {
    if (_betAmount <= 0) return '';

    // Check big win first
    if (_slotWinConfig.isBigWin(winAmount, _betAmount)) {
      final maxTier = _slotWinConfig.getBigWinMaxTier(winAmount, _betAmount);
      if (maxTier > 0) return 'BIG_WIN_TIER_$maxTier';
      return 'BIG_WIN_TIER_1';
    }

    // Regular win
    final tier = _slotWinConfig.getRegularTier(winAmount, _betAmount);
    if (tier == null) return '';
    return tier.stageName; // WIN_LOW, WIN_EQUAL, WIN_1–WIN_5
  }

  /// Get RTPC value for a win amount (0.0 to 1.0)
  /// P5: derived from multiplier position within tier range
  double getRtpcForWin(double winAmount) {
    if (_betAmount <= 0) return 0.0;
    final multiplier = winAmount / _betAmount;
    // Normalize to 0-1 based on big win threshold
    final threshold = _slotWinConfig.bigWins.threshold;
    return (multiplier / threshold).clamp(0.0, 1.0);
  }

  /// Check if a win should trigger celebration animation
  bool shouldTriggerCelebration(double winAmount) {
    return _slotWinConfig.isBigWin(winAmount, _betAmount);
  }

  /// Get rollup duration in ms for a win (P5 system)
  int getRollupDurationMs(double winAmount) {
    if (_betAmount <= 0) return 1000;

    if (_slotWinConfig.isBigWin(winAmount, _betAmount)) {
      final tiers = _slotWinConfig.bigWins.getTiersForWin(winAmount, _betAmount);
      if (tiers.isNotEmpty) return tiers.last.durationMs;
      return 4000;
    }

    final tier = _slotWinConfig.getRegularTier(winAmount, _betAmount);
    return tier?.rollupDurationMs ?? 1000;
  }

  /// Get the stage to trigger for a win (P5 system)
  String? getTriggerStageForWin(double winAmount) {
    if (_betAmount <= 0) return null;

    if (_slotWinConfig.isBigWin(winAmount, _betAmount)) {
      return BigWinConfig.startStageName;
    }

    final tier = _slotWinConfig.getRegularTier(winAmount, _betAmount);
    return tier?.presentStageName;
  }

  bool get inFreeSpins => _inFreeSpins;
  int get freeSpinsRemaining => _freeSpinsRemaining;

  bool get autoTriggerAudio => _autoTriggerAudio;
  bool get isPlayingStages => _isPlayingStages;
  int get currentStageIndex => _currentStageIndex;
  bool get aleAutoSync => _aleAutoSync;

  /// True ONLY while reels are visually spinning (UI_SPIN_PRESS → all REEL_STOP)
  /// Use this for STOP button visibility - does NOT include win presentation
  bool get isReelsSpinning => _isReelsSpinning;

  /// V13: True during win presentation (symbol highlight, plaque, rollup, win lines)
  /// Used to block new spin or require fade-out before starting
  bool get isWinPresentationActive => _isWinPresentationActive;

  /// V13: Called by slot_preview_widget to update win presentation state
  void setWinPresentationActive(bool active) {
    if (_isWinPresentationActive != active) {
      _isWinPresentationActive = active;

      // Stop COIN_SHOWER when win presentation ends
      if (!active) {
        eventRegistry.stopEvent('COIN_SHOWER_START');
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

    // ANALYTICS: Track skip requested (get current tier from last result)
    final tier = getVisualTierForWin(_lastResult?.totalWin.toDouble() ?? 0.0);
    WinAnalyticsService.instance.trackSkipRequested(
      tier,
      progressPercent: 0.0, // Could be enhanced to pass actual progress
    );

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
      // Spin loop stops on SPIN_END, not here
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

      notifyListeners();
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
    _baseMusicStarted = false;
    _gameStartTriggered = false;
    notifyListeners();
  }

  /// Connect middleware for audio triggering
  void connectMiddleware(MiddlewareProvider middleware) {
    _middleware = middleware;
  }

  /// Connect ALE provider for signal sync
  void connectAle(AleProvider ale) {
    _aleProvider = ale;
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
    } else {
      // Use defaults if config not available
      _timingConfig = SlotLabTimingConfig.studio();
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
    notifyListeners();
  }

  /// Seed RNG for reproducible results
  void seedRng(int seed) {
    if (_initialized) {
      _ffi.slotLabSeedRng(seed);
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
    DiagnosticsService.instance.log('spin() called: initialized=$_initialized, isSpinning=$_isSpinning');
    if (!_initialized || _isSpinning) {
      return null;
    }

    _isSpinning = true;
    notifyListeners();

    try {
      // Use V2 engine if initialized (has custom GDD config), else V1
      // With P5 Win Tier enabled, use P5 spin functions for dynamic tier evaluation
      final int spinId;
      if (_engineV2Initialized) {
        spinId = _ffi.slotLabV2Spin();
      } else if (_useP5WinTier) {
        // P5 Win Tier mode: Use FFI function that applies P5 config after spin
        spinId = _ffi.slotLabSpinP5();
      } else {
        spinId = _ffi.slotLabSpin();
      }

      if (spinId == 0) {
        _isSpinning = false;
        notifyListeners();
        return null;
      }

      _spinCount++;

      // ANALYTICS: Track spin for win rate calculation
      WinAnalyticsService.instance.trackSpin();

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

      // Compact spin summary
      final win = _lastResult?.totalWin ?? 0;
      final isWin = _lastResult?.isWin ?? false;

      _reportSpinDiagnostics();

      // Auto-trigger audio if enabled
      if (_autoTriggerAudio && _lastStages.isNotEmpty) {
        _playStagesSequentially();
      }

      // Sync ALE signals
      _syncAleSignals();

      _isSpinning = false;
      notifyListeners();
      return _lastResult;
    } catch (e, stack) {
      DiagnosticsService.instance.reportFinding(DiagnosticFinding(
        checker: 'SpinCrash',
        severity: DiagnosticSeverity.error,
        message: 'spin() threw: $e',
        detail: stack.toString().split('\n').take(5).join('\n'),
      ));
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
      // With P5 Win Tier enabled, use P5 spin functions for dynamic tier evaluation
      final int spinId;
      if (_engineV2Initialized) {
        spinId = _ffi.slotLabV2SpinForced(outcome.index);
      } else if (_useP5WinTier) {
        // P5 Win Tier mode: Use FFI function that applies P5 config after spin
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

      _reportSpinDiagnostics();

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
      _isSpinning = false;
      notifyListeners();
      return null;
    }
  }

  /// Execute a forced spin with EXACT target win multiplier for precise tier testing
  ///
  /// [outcome] - ForcedOutcome type (SmallWin, MediumWin, BigWin etc.)
  /// [targetMultiplier] - Exact win multiplier (e.g., 1.5 for WIN_1, 3.5 for WIN_2)
  ///
  /// This ensures each tier button (W1, W2, W3...) produces a DISTINCT win tier
  /// by overriding paytable-evaluated win with: total_win = bet * targetMultiplier
  ///
  /// Target multipliers for P5 tiers (using mid-range values):
  /// - WIN_1: 1.5x  (range: >1x, ≤2x)
  /// - WIN_2: 3.0x  (range: >2x, ≤4x)
  /// - WIN_3: 6.0x  (range: >4x, ≤8x)
  /// - WIN_4: 10.5x (range: >8x, ≤13x)
  /// - WIN_5: 15.0x (range: >13x — default for regular wins)
  /// - BIG_WIN: 35x (range: 20x+)
  Future<SlotLabSpinResult?> spinForcedWithMultiplier(
    ForcedOutcome outcome,
    double targetMultiplier,
  ) async {
    if (!_initialized || _isSpinning) return null;

    _isSpinning = true;
    notifyListeners();

    try {

      final int spinId = _ffi.slotLabSpinForcedWithMultiplier(outcome, targetMultiplier);

      if (spinId == 0) {
        _isSpinning = false;
        notifyListeners();
        return null;
      }

      _spinCount++;

      // Get results - always from V1 engine since we're using the new FFI function
      _lastResult = _ffi.slotLabGetSpinResult();
      _lastStages = _ffi.slotLabGetStages();

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
      final tierName = _lastResult?.winTierName ?? 'unknown';

      _reportSpinDiagnostics();

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
      'featureProgress': _inFreeSpins && _freeSpinsTotal > 0
          ? 1.0 - (_freeSpinsRemaining / _freeSpinsTotal.toDouble()).clamp(0.0, 1.0)
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
  /// Examples: "ANTICIPATION_TENSION_3" → 3, "ANTICIPATION_MISS" → 0
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
        s.stageType.toUpperCase().startsWith('ANTICIPATION_TENSION')).length;
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
    }
  }

  /// Report spin results to diagnostics — feeds all stages to monitors
  void _reportSpinDiagnostics() {
    final diag = DiagnosticsService.instance;
    diag.log('_reportSpinDiagnostics: stages=${_lastStages.length}, win=${_lastResult?.totalWin ?? 0}');

    // Always report spin summary (reportFinding works regardless of monitoring state)
    diag.reportFinding(DiagnosticFinding(
      checker: 'SpinResult',
      severity: DiagnosticSeverity.ok,
      message: 'Spin #$_spinCount: ${_lastStages.length} stages, '
          'win=${_lastResult?.totalWin ?? 0}',
    ));

    // Feed stages to monitors (onStageTrigger/onSpinComplete have own guards)
    for (final stage in _lastStages) {
      diag.onStageTrigger(stage.stageType.toUpperCase(), stage.timestampMs);
    }
    diag.onSpinComplete();
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
      return;
    }

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
        return;
      }

      _currentStageIndex++;
      if (_currentStageIndex >= _lastStages.length) return;
      final stage = _lastStages[_currentStageIndex];

      // DIRECT TRIGGER — No pre-trigger, exact sync with animation
      _triggerStage(stage);
      notifyListeners();

      _scheduleNextStage();
    });
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
        effectiveStage = 'ANTICIPATION_TENSION';
      }
      volumeMultiplier = 1.0;
    } else if (combinedIntensity >= 0.5) {
      // High tension
      if (eventRegistry.hasEventForStage('ANTICIPATION_HIGH')) {
        effectiveStage = 'ANTICIPATION_HIGH';
      } else {
        effectiveStage = 'ANTICIPATION_TENSION';
      }
      volumeMultiplier = 0.9;
    } else {
      // Medium tension - use default
      effectiveStage = 'ANTICIPATION_TENSION';
      volumeMultiplier = 0.7 + (combinedIntensity * 0.3); // 0.7 to 0.85
    }

    return (effectiveStage: effectiveStage, volumeMultiplier: volumeMultiplier);
  }

  /// Ensure audio assignment is registered in EventRegistry before triggering.
  /// SAFETY NET: If audioAssignment exists in SlotLabProjectProvider but NOT in
  /// EventRegistry, re-register as single Play layer.
  /// NOTE: Does NOT override multi-layer composite events (BIG_WIN_START/END etc.)
  void _ensureAudioRegistered(String stageUppercase) {
    if (eventRegistry.hasEventForStage(stageUppercase)) return;
    final projectProvider = GetIt.instance<SlotLabProjectProvider>();
    final audioPath = projectProvider.getAudioAssignment(stageUppercase);
    if (audioPath == null || audioPath.isEmpty) return;

    final stageConfig = StageConfigurationService.instance;
    final shouldLoop = stageConfig.isLooping(stageUppercase);
    final bus = stageConfig.getBus(stageUppercase);
    final busId = bus.engineBusId;
    final isMusicBus = busId == 1;
    final shouldOverlap = !isMusicBus && !shouldLoop;
    final crossfadeMs = isMusicBus ? 500 : 0;

    double pan = 0.0;
    if (stageUppercase.startsWith('REEL_STOP_')) {
      final idx = int.tryParse(stageUppercase.replaceAll('REEL_STOP_', ''));
      if (idx != null) {
        const pans = [-0.8, -0.4, 0.0, 0.4, 0.8];
        if (idx >= 0 && idx < pans.length) pan = pans[idx];
      }
    }

    eventRegistry.registerEvent(AudioEvent(
      id: 'audio_$stageUppercase',
      name: stageUppercase.replaceAll('_', ' '),
      stage: stageUppercase,
      layers: [
        AudioLayer(
          id: 'layer_$stageUppercase',
          name: '${stageUppercase.replaceAll('_', ' ')} Audio',
          audioPath: audioPath,
          volume: 1.0,
          pan: pan,
          delay: 0.0,
          busId: busId,
        ),
      ],
      loop: shouldLoop,
      overlap: shouldOverlap,
      crossfadeMs: crossfadeMs,
      targetBusId: busId,
    ));
  }

  /// Trigger audio for a stage event
  /// CRITICAL: Uses ONLY EventRegistry. Legacy systems DISABLED to prevent duplicate audio.
  void _triggerStage(SlotLabStageEvent stage) {
    final stageType = stage.stageType.toUpperCase();

    // Diagnostics: feed every stage to monitors for live analysis
    DiagnosticsService.instance.onStageTrigger(stageType, stage.timestampMs);

    // CRITICAL: reel_index and symbols are in rawStage (from stage JSON), not payload
    final reelIndex = stage.rawStage['reel_index'];
    // CRITICAL: Include timestamp_ms for Event Log ordering display
    Map<String, dynamic> context = {
      ...stage.payload,
      ...stage.rawStage,
      'timestamp_ms': stage.timestampMs,
    };

    // ═══════════════════════════════════════════════════════════════════════════
    // VISUAL-SYNC MODE: Skip stages handled by animation callback in slot_preview_widget
    // REEL_STOP — widget triggers REEL_STOP_$i on animation callback (exact visual sync)
    // REEL_SPIN_LOOP — widget triggers on spin animation start (force_no_loop one-shot)
    // This prevents duplicate audio (provider + visual callback both triggering)
    // ═══════════════════════════════════════════════════════════════════════════
    if (_useVisualSyncForReelStop && (stageType == 'REEL_STOP' || stageType == 'REEL_SPIN_LOOP')) {
      return; // Visual callback in slot_preview_widget.dart will handle this
    }
    // ANTICIPATION_TENSION — visual sync: slot_preview_widget triggers per-reel tension.
    // Skip engine path to prevent duplicate audio.
    if (_useVisualSyncForReelStop && stageType.startsWith('ANTICIPATION_TENSION')) {
      final reelIdx = _extractReelIndexFromStage(stageType);
      final reason = stage.payload['reason'] as String? ??
          stage.rawStage['reason'] as String? ?? 'scatter';
      final tensionLevel = reelIdx.clamp(1, 4);
      onAnticipationStart?.call(reelIdx, reason, tensionLevel: tensionLevel);
      return;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ROLLUP TRACKING — Must run BEFORE visual-sync return so progress data
    // is available when widget triggers rollup audio with context['progress']
    // ═══════════════════════════════════════════════════════════════════════════
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

    // ═══════════════════════════════════════════════════════════════════════════
    // WIN_LINE_SHOW PAN — Must run BEFORE visual-sync return so pan data
    // is available when widget triggers win line audio
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType == 'WIN_LINE_SHOW') {
      final lineIndex = stage.payload['line_index'] as int? ?? 0;
      final linePan = _calculateWinLinePan(lineIndex);
      context['pan'] = linePan;
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
      'BIG_WIN_START',
      'BIG_WIN_END',
      'BIG_WIN_TIER',  // Widget triggers BIG_WIN_TIER_1..5 with correct timing
    };

    // Pattern prefixes — widget triggers dynamic versions of these
    const winPresentationPrefixes = [
      'WIN_SYMBOL_HIGHLIGHT',  // WIN_SYMBOL_HIGHLIGHT, WIN_SYMBOL_HIGHLIGHT_HP1, etc.
      'WIN_PRESENT',           // WIN_PRESENT_SMALL, WIN_PRESENT_BIG, etc.
      'WIN_TIER',              // WIN_TIER_BIG, WIN_TIER_MEGA, etc.
    ];

    // Check exact matches
    if (winPresentationStagesExact.contains(stageType)) {
      return;
    }

    // Check pattern prefixes
    for (final prefix in winPresentationPrefixes) {
      if (stageType == prefix || stageType.startsWith('${prefix}_')) {
        return;
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // P0.3: ANTICIPATION VISUAL-AUDIO SYNC — Invoke callbacks for synchronized visuals
    // Callbacks notify UI to dim background and slow reel animation at SAME TIME as audio
    // NOTE: ANTICIPATION_TENSION_LAYER is handled separately below (with progress/DSP params)
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType.startsWith('ANTICIPATION_TENSION') &&
        stageType != 'ANTICIPATION_TENSION_LAYER') {
      final reelIdx = _extractReelIndexFromStage(stageType);
      final reason = stage.payload['reason'] as String? ??
          stage.rawStage['reason'] as String? ?? 'scatter';
      final tensionLevel = reelIdx.clamp(1, 4);
      onAnticipationStart?.call(reelIdx, reason, tensionLevel: tensionLevel);
    } else if (stageType == 'ANTICIPATION_MISS') {
      final reelIdx = _extractReelIndexFromStage(stageType);
      onAnticipationEnd?.call(reelIdx);
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

      // Invoke visual callback for anticipation start
      if (progress == 0.0) {
        onAnticipationStart?.call(reelIdx, reason, tensionLevel: tensionLevel);
      }

      // Map to stage name for EventRegistry: ANTICIPATION_TENSION_R{reel}_L{level}
      effectiveStage = 'ANTICIPATION_TENSION_R${reelIdx}_L$tensionLevel';
    }
    // ═══════════════════════════════════════════════════════════════════════════
    // P1.2: NEAR MISS AUDIO ESCALATION — Intensity-based anticipation (legacy)
    // ═══════════════════════════════════════════════════════════════════════════
    else if (stageType == 'ANTICIPATION_TENSION') {
      final escalationResult = _calculateAnticipationEscalation(stage);
      effectiveStage = escalationResult.effectiveStage;
      context['volumeMultiplier'] = escalationResult.volumeMultiplier;
    }

    // (Rollup tracking and WIN_LINE_SHOW pan moved above visual-sync return)

    // ═══════════════════════════════════════════════════════════════════════════
    // P0: PER-REEL SPINNING — Each reel has its own spin loop for independent fade-out
    // ═══════════════════════════════════════════════════════════════════════════
    if ((stageType == 'REEL_SPINNING' || stageType == 'reel_spinning') && reelIndex != null) {
      effectiveStage = 'REEL_SPINNING_$reelIndex';
      // Pass reel_index to EventRegistry for voice tracking
      context['reel_index'] = reelIndex;
      context['is_reel_spin_loop'] = true; // Flag for voice tracking
    }

    if (stageType == 'REEL_STOP' && reelIndex != null) {
      effectiveStage = 'REEL_STOP_$reelIndex';
      // P0: Tell EventRegistry to fade out this reel's spin loop
      context['fade_out_spin_reel'] = reelIndex;
      // DEBUG: Detailed logging for REEL_STOP issue

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
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SAFETY NET: Ensure audio assignments are registered before triggering.
    // If EventRegistry lost the event (sync, re-init, composite overwrite),
    // re-register from SlotLabProjectProvider.audioAssignments.
    // ═══════════════════════════════════════════════════════════════════════════
    _ensureAudioRegistered(effectiveStage);
    if (effectiveStage != stageType) {
      _ensureAudioRegistered(stageType);
    }

    final bool hasSpecific = eventRegistry.hasEventForStage(effectiveStage);
    final bool hasFallback = effectiveStage != stageType && eventRegistry.hasEventForStage(stageType);

    // SPIN_END is handled below with guard — skip general trigger to prevent double audio
    if (stageType != 'SPIN_END') {
      if (hasSpecific) {
        eventRegistry.triggerStage(effectiveStage, context: context);
      } else if (hasFallback) {
        eventRegistry.triggerStage(stageType, context: context);
      } else {
        // STILL trigger so Event Log shows the stage (even without audio)
        eventRegistry.triggerStage(stageType, context: context);
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REEL SPINNING STATE — For STOP button visibility
    // ═══════════════════════════════════════════════════════════════════════════
    if (stageType == 'UI_SPIN_PRESS') {
      _isReelsSpinning = true;
      _spinEndTriggered = false; // Reset guard for new spin
      notifyListeners();
    }

    // MUSIC AUTO-TRIGGER: Start base music / game start on UI_SPIN_PRESS
    // Splash screen triggers GAME_START on CONTINUE. This is a safety net
    // that re-triggers music if it stopped (e.g., Events Panel stopAll).
    if (stageType == 'UI_SPIN_PRESS') {
      _ensureAudioRegistered('GAME_START');

      // Prefer GAME_START composite (has L1=vol1.0, L2/L3=vol0.0 for crossfade)
      final gameStartPlaying = _gameStartTriggered &&
          eventRegistry.isEventPlaying('audio_GAME_START');
      if (!gameStartPlaying && eventRegistry.hasEventForStage('GAME_START')) {
        eventRegistry.triggerStage('GAME_START', context: context);
        _gameStartTriggered = true;
        _baseMusicStarted = true;
      }

      // Fallback: if no GAME_START composite, trigger individual layers
      if (!_baseMusicStarted) {
        for (final layer in const ['MUSIC_BASE_L1', 'MUSIC_BASE_L2', 'MUSIC_BASE_L3', 'MUSIC_BASE_L4', 'MUSIC_BASE_L5']) {
          _ensureAudioRegistered(layer);
          final layerPlaying = eventRegistry.isEventPlaying('audio_$layer');
          if (!layerPlaying && eventRegistry.hasEventForStage(layer)) {
            eventRegistry.triggerStage(layer, context: context);
            _baseMusicStarted = true;
          }
        }
      }
    }

    // SPIN_END: Single trigger point — stops spin loop via EventRegistry + plays SPIN_END audio
    if (stageType == 'SPIN_END') {
      if (!_spinEndTriggered) {
        _spinEndTriggered = true;
        eventRegistry.triggerStage('SPIN_END', context: context);
      }
      // Reset container state (shuffle history, round-robin, active sequences)
      ContainerService.instance.resetState();
      // Diagnostics: notify monitors that spin is complete
      DiagnosticsService.instance.onSpinComplete();
    }

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
    notifyListeners();
  }

  /// Stop recording stage events
  void stopStageRecording() {
    if (!_isRecordingStages) return;
    _isRecordingStages = false;
    notifyListeners();
  }

  /// Clear all captured stages
  void clearStages() {
    _lastStages = [];
    _currentStageIndex = 0;
    _cachedStagesSpinId = null; // P0.18: Clear cache
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
      return;
    }

    _isPaused = false;

    // Resume Rust engine audio
    UnifiedPlaybackController.instance.play();

    // If we have remaining delay, schedule the next stage with that delay
    if (_pausedRemainingDelayMs > 0 && _currentStageIndex < _lastStages.length - 1) {
      _scheduleNextStageWithDelay(_pausedRemainingDelayMs);
    } else if (_currentStageIndex < _lastStages.length - 1) {
      // No remaining delay, just schedule normally
      _scheduleNextStage();
    } else {
      // We were at the last stage
      _isPlayingStages = false;
      UnifiedPlaybackController.instance.releaseSection(PlaybackSection.slotLab);
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
    if (_inFreeSpins) {
      final total = _ffi.freeSpinsTotal();
      if (total > 0) _freeSpinsTotal = total;
    }
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

    // 1. UI_SPIN_PRESS must be first
    if (stageTypes.isNotEmpty && stageTypes.first != 'UI_SPIN_PRESS') {
      issues.add(StageValidationIssue(
        type: StageValidationType.orderViolation,
        message: 'UI_SPIN_PRESS must be first stage (found: ${stageTypes.first})',
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
    const requiredStages = {'UI_SPIN_PRESS', 'SPIN_END'};
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
    return symbols.contains(_scatterSymbolId);
  }

  /// Check if symbols list contains a Seven (typically symbol ID 7)
  bool _containsSeven(List<dynamic>? symbols) {
    if (symbols == null || symbols.isEmpty) return false;
    // Seven is typically ID 7 in standard slot configurations
    return symbols.contains(7);
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
      notifyListeners();
    }
    return success;
  }

  /// Update game model (re-initializes engine)
  bool updateGameModel(Map<String, dynamic> model) {
    // Extract old grid dimensions
    final oldGrid = _currentGameModel?['grid'] as Map<String, dynamic>?;
    final oldReels = oldGrid?['reels'] as int? ?? 5;

    // Shutdown existing engine
    if (_engineV2Initialized) {
      _ffi.slotLabV2Shutdown();
      _engineV2Initialized = false;
    }

    // Convert model to JSON and initialize
    final modelJson = jsonEncode(model);
    final success = _ffi.slotLabV2InitWithModelJson(modelJson);
    if (success) {
      _engineV2Initialized = true;
      _currentGameModel = _ffi.slotLabV2GetModel();

      // Check if grid dimensions changed (P0 WF-03)
      final newGrid = model['grid'] as Map<String, dynamic>?;
      final newReels = newGrid?['reels'] as int? ?? 5;

      if (newReels != oldReels) {
        // Trigger reel stage regeneration callback
        onGridDimensionsChanged?.call(newReels);
      }

      notifyListeners();
    }
    return success;
  }

  /// Callback when grid dimensions change (P0 WF-03)
  void Function(int newReelCount)? onGridDimensionsChanged;

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
    final jsonStr = jsonEncode(scenarioJson);
    final success = _ffi.slotLabScenarioRegister(jsonStr);
    if (success) {
      _refreshScenarioList();
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
