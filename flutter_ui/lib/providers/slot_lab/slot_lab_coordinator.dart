/// Slot Lab Coordinator — Aggregates and coordinates sub-providers
///
/// Part of P12.1.7 SlotLabProvider decomposition.
/// Provides unified API for UI while delegating to focused sub-providers:
/// - SlotEngineProvider: Engine state, spin execution, configuration
/// - SlotStageProvider: Stage events, playback, validation
/// - SlotAudioProvider: Audio playback, ALE sync, persistent state
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../models/stage_models.dart';
import '../../models/win_tier_config.dart';
import '../../src/rust/slot_lab_v2_ffi.dart';
import '../../src/rust/native_ffi.dart' show SlotLabStageEvent, SlotLabStats, SlotLabWinTier, SlotLabTimingConfig, VolatilityPreset, TimingProfileType, ForcedOutcome, SlotLabSpinResult;
import '../middleware_provider.dart';
import '../ale_provider.dart';

import 'slot_engine_provider.dart';
import 'slot_stage_provider.dart';
import 'slot_audio_provider.dart';

// Re-export sub-providers for convenience
export 'slot_engine_provider.dart';
export 'slot_stage_provider.dart' show PooledStageEvent, StageEventPool, AnticipationConfigType;
export 'slot_audio_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SLOT LAB COORDINATOR
// ═══════════════════════════════════════════════════════════════════════════

/// Unified coordinator for SlotLab functionality
///
/// Aggregates three focused sub-providers:
/// - [engineProvider]: Engine lifecycle, spin execution, configuration
/// - [stageProvider]: Stage events, playback, validation
/// - [audioProvider]: Audio playback, ALE sync, persistent state
///
/// The coordinator:
/// - Provides a unified API for UI components
/// - Manages cross-provider communication
/// - Handles lifecycle coordination
class SlotLabCoordinator extends ChangeNotifier {
  // ─── Sub-Providers ──────────────────────────────────────────────────────
  final SlotEngineProvider engineProvider;
  final SlotStageProvider stageProvider;
  final SlotAudioProvider audioProvider;

  /// Whether this coordinator has been disposed.
  /// Prevents notifyListeners() from being called after disposal.
  bool _isDisposed = false;

  /// Whether a post-frame notification is already scheduled.
  /// Prevents scheduling multiple callbacks in the same frame.
  bool _notifyScheduled = false;

  SlotLabCoordinator({
    SlotEngineProvider? engineProvider,
    SlotStageProvider? stageProvider,
    SlotAudioProvider? audioProvider,
  }) : engineProvider = engineProvider ?? SlotEngineProvider(),
       stageProvider = stageProvider ?? SlotStageProvider(),
       audioProvider = audioProvider ?? SlotAudioProvider() {
    _setupListeners();
    _setupCallbacks();
  }

  void _setupListeners() {
    // Forward notifications from sub-providers
    engineProvider.addListener(_onSubProviderChanged);
    stageProvider.addListener(_onSubProviderChanged);
    audioProvider.addListener(_onSubProviderChanged);
  }

  void _setupCallbacks() {
    // Wire up engine -> stage playback callback
    engineProvider.onSpinComplete = (result, stages) {
      // Validate stages
      stageProvider.setStages(
        stages,
        spinId: result.spinId,
        autoPlay: audioProvider.autoTriggerAudio,
      );

      // Sync ALE signals
      audioProvider.syncAleSignals(
        result,
        engineProvider.hitRate,
        engineProvider.inFreeSpins,
        engineProvider.freeSpinsRemaining,
        engineProvider.spinCount,
        engineProvider.volatilitySlider,
        stages,
      );
    };

    // Wire up stage provider callbacks to coordinator's public callbacks
    stageProvider.onAnticipationStart = (reelIndex, reason, {int tensionLevel = 1}) {
      onAnticipationStart?.call(reelIndex, reason, tensionLevel: tensionLevel);
    };
    stageProvider.onAnticipationEnd = (reelIndex) {
      onAnticipationEnd?.call(reelIndex);
    };
  }

  void _onSubProviderChanged() {
    if (_isDisposed) return;
    // Defer notification to after the current frame to prevent
    // "setState() or markNeedsBuild() called during build" errors
    // when sub-providers notify during didChangeDependencies.
    if (!_notifyScheduled) {
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (!_isDisposed) {
          notifyListeners();
        }
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC CALLBACKS — For UI to handle events
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when anticipation starts on a specific reel
  void Function(int reelIndex, String reason, {int tensionLevel})? onAnticipationStart;

  /// Called when anticipation ends on a specific reel
  void Function(int reelIndex)? onAnticipationEnd;

  /// Callback when grid dimensions change
  void Function(int newReelCount)? get onGridDimensionsChanged =>
      engineProvider.onGridDimensionsChanged;
  set onGridDimensionsChanged(void Function(int newReelCount)? value) =>
      engineProvider.onGridDimensionsChanged = value;

  // ═══════════════════════════════════════════════════════════════════════════
  // UNIFIED GETTERS — Delegate to appropriate sub-provider
  // ═══════════════════════════════════════════════════════════════════════════

  // --- Engine State ---
  bool get initialized => engineProvider.initialized;
  bool get isSpinning => engineProvider.isSpinning;
  int get spinCount => engineProvider.spinCount;
  SlotLabSpinResult? get lastResult => engineProvider.lastResult;
  SlotLabStats? get stats => engineProvider.stats;
  double get rtp => engineProvider.rtp;
  double get hitRate => engineProvider.hitRate;

  // --- Configuration ---
  double get volatilitySlider => engineProvider.volatilitySlider;
  VolatilityPreset get volatilityPreset => engineProvider.volatilityPreset;
  TimingProfileType get timingProfile => engineProvider.timingProfile;
  double get betAmount => engineProvider.betAmount;
  bool get cascadesEnabled => engineProvider.cascadesEnabled;
  bool get freeSpinsEnabled => engineProvider.freeSpinsEnabled;
  bool get jackpotEnabled => engineProvider.jackpotEnabled;
  WinTierConfig get winTierConfig => engineProvider.winTierConfig;
  bool get useP5WinTier => engineProvider.useP5WinTier;
  bool get inFreeSpins => engineProvider.inFreeSpins;
  int get freeSpinsRemaining => engineProvider.freeSpinsRemaining;
  int get totalReels => engineProvider.totalReels;
  int get totalRows => engineProvider.totalRows;

  // --- Timing ---
  SlotLabTimingConfig? get timingConfig => engineProvider.timingConfig;
  int get anticipationPreTriggerMs => engineProvider.anticipationPreTriggerMs;
  int get reelStopPreTriggerMs => engineProvider.reelStopPreTriggerMs;
  double get totalAudioOffsetMs => engineProvider.totalAudioOffsetMs;

  // --- Engine V2 ---
  bool get engineV2Initialized => engineProvider.engineV2Initialized;
  Map<String, dynamic>? get currentGameModel => engineProvider.currentGameModel;
  List<ScenarioInfo> get availableScenarios => engineProvider.availableScenarios;
  String? get loadedScenarioId => engineProvider.loadedScenarioId;

  // --- Stage State ---
  List<SlotLabStageEvent> get lastStages => stageProvider.lastStages;
  List<PooledStageEvent> get pooledStages => stageProvider.pooledStages;
  String? get cachedStagesSpinId => stageProvider.cachedStagesSpinId;
  String get stagePoolStats => stageProvider.stagePoolStats;
  bool get isPlayingStages => stageProvider.isPlayingStages;
  int get currentStageIndex => stageProvider.currentStageIndex;
  bool get isPaused => stageProvider.isPaused;
  bool get isActivelyPlaying => stageProvider.isActivelyPlaying;
  bool get isReelsSpinning => stageProvider.isReelsSpinning;
  bool get isWinPresentationActive => stageProvider.isWinPresentationActive;
  bool get useVisualSyncForReelStop => stageProvider.useVisualSyncForReelStop;
  set useVisualSyncForReelStop(bool value) => stageProvider.useVisualSyncForReelStop = value;
  bool get isRecordingStages => stageProvider.isRecordingStages;
  bool get skipRequested => stageProvider.skipRequested;
  List<StageValidationIssue> get lastValidationIssues => stageProvider.lastValidationIssues;
  bool get stagesValid => stageProvider.stagesValid;

  // --- Anticipation Config ---
  AnticipationConfigType get anticipationConfigType => stageProvider.anticipationConfigType;
  int get scatterSymbolId => stageProvider.scatterSymbolId;
  int get bonusSymbolId => stageProvider.bonusSymbolId;
  List<int> get tipBAllowedReels => stageProvider.tipBAllowedReels;

  // --- Audio State ---
  bool get autoTriggerAudio => audioProvider.autoTriggerAudio;
  bool get aleAutoSync => audioProvider.aleAutoSync;
  int get persistedLowerZoneTabIndex => audioProvider.persistedLowerZoneTabIndex;
  bool get persistedLowerZoneExpanded => audioProvider.persistedLowerZoneExpanded;
  double get persistedLowerZoneHeight => audioProvider.persistedLowerZoneHeight;
  List<Map<String, dynamic>> get persistedAudioPool => audioProvider.persistedAudioPool;
  set persistedAudioPool(List<Map<String, dynamic>> value) => audioProvider.persistedAudioPool = value;
  List<Map<String, dynamic>> get persistedCompositeEvents => audioProvider.persistedCompositeEvents;
  set persistedCompositeEvents(List<Map<String, dynamic>> value) => audioProvider.persistedCompositeEvents = value;
  List<Map<String, dynamic>> get persistedTracks => audioProvider.persistedTracks;
  set persistedTracks(List<Map<String, dynamic>> value) => audioProvider.persistedTracks = value;
  Map<String, String> get persistedEventToRegionMap => audioProvider.persistedEventToRegionMap;
  set persistedEventToRegionMap(Map<String, String> value) => audioProvider.persistedEventToRegionMap = value;
  Map<String, List<double>> get waveformCache => audioProvider.waveformCache;
  Map<String, int> get clipIdCache => audioProvider.clipIdCache;

  // --- Win helpers ---
  List<List<int>>? get currentGrid => engineProvider.currentGrid;
  bool get lastSpinWasWin => engineProvider.lastSpinWasWin;
  double get lastWinAmount => engineProvider.lastWinAmount;
  double get lastWinRatio => engineProvider.lastWinRatio;
  SlotLabWinTier? get lastBigWinTier => engineProvider.lastBigWinTier;

  // ═══════════════════════════════════════════════════════════════════════════
  // UNIFIED METHODS — Delegate to appropriate sub-provider
  // ═══════════════════════════════════════════════════════════════════════════

  // --- Engine Lifecycle ---
  bool initialize({bool audioTestMode = false}) {
    stageProvider.setTotalReels(engineProvider.totalReels);
    audioProvider.setTotalReels(engineProvider.totalReels);
    StageEventPool.instance.init();
    return engineProvider.initialize(audioTestMode: audioTestMode);
  }

  void shutdown() => engineProvider.shutdown();

  void connectMiddleware(MiddlewareProvider middleware) {
    audioProvider.connectMiddleware(middleware);
  }

  void connectAle(AleProvider ale) {
    // Engine provider doesn't need ALE connection
    stageProvider.connectAle(ale);
    audioProvider.connectAle(ale);
  }

  // --- Configuration ---
  void setVolatilitySlider(double value) => engineProvider.setVolatilitySlider(value);
  void setVolatilityPreset(VolatilityPreset preset) => engineProvider.setVolatilityPreset(preset);
  void setTimingProfile(TimingProfileType profile) => engineProvider.setTimingProfile(profile);

  void setBetAmount(double bet) {
    engineProvider.setBetAmount(bet);
    stageProvider.setBetAmount(bet);
    audioProvider.setBetAmount(bet);
  }

  void setCascadesEnabled(bool enabled) => engineProvider.setCascadesEnabled(enabled);
  void setFreeSpinsEnabled(bool enabled) => engineProvider.setFreeSpinsEnabled(enabled);
  void setJackpotEnabled(bool enabled) => engineProvider.setJackpotEnabled(enabled);
  void setWinTierConfig(WinTierConfig config) => engineProvider.setWinTierConfig(config);
  void setUseP5WinTier(bool enabled) => engineProvider.setUseP5WinTier(enabled);
  void setAnticipationPreTriggerMs(int ms) => engineProvider.setAnticipationPreTriggerMs(ms);
  void seedRng(int seed) => engineProvider.seedRng(seed);
  void resetStats() => engineProvider.resetStats();

  void updateGridSize(int reels, int rows) {
    engineProvider.updateGridSize(reels, rows);
    stageProvider.setTotalReels(reels);
    audioProvider.setTotalReels(reels);
  }

  // --- Anticipation Config ---
  void setAnticipationConfigType(AnticipationConfigType type) =>
      stageProvider.setAnticipationConfigType(type);
  void setScatterSymbolId(int symbolId) => stageProvider.setScatterSymbolId(symbolId);
  void setBonusSymbolId(int symbolId) => stageProvider.setBonusSymbolId(symbolId);
  void setTipBAllowedReels(List<int> reels) => stageProvider.setTipBAllowedReels(reels);

  bool canTriggerAnticipation(int symbolId) =>
      stageProvider.canTriggerAnticipation(symbolId);
  bool shouldTriggerAnticipation(Set<int> triggerReels) =>
      stageProvider.shouldTriggerAnticipation(triggerReels);
  List<int> getAnticipationReels(Set<int> triggerReels, int totalReels) =>
      stageProvider.getAnticipationReels(triggerReels, totalReels);

  // --- Audio Config ---
  void setAutoTriggerAudio(bool enabled) => audioProvider.setAutoTriggerAudio(enabled);
  void setAleAutoSync(bool enabled) {
    stageProvider.setAleAutoSync(enabled);
    audioProvider.setAleAutoSync(enabled);
  }
  void setLowerZoneTabIndex(int index) => audioProvider.setLowerZoneTabIndex(index);
  void setLowerZoneExpanded(bool expanded) => audioProvider.setLowerZoneExpanded(expanded);
  void setLowerZoneHeight(double height) => audioProvider.setLowerZoneHeight(height);
  void clearPersistedState() => audioProvider.clearPersistedState();

  // --- Win Tier Helpers ---
  String getVisualTierForWin(double winAmount) =>
      engineProvider.getVisualTierForWin(winAmount);
  double getRtpcForWin(double winAmount) =>
      engineProvider.getRtpcForWin(winAmount);
  bool shouldTriggerCelebration(double winAmount) =>
      engineProvider.shouldTriggerCelebration(winAmount);
  double getRollupMultiplier(double winAmount) =>
      engineProvider.getRollupMultiplier(winAmount);
  String? getTriggerStageForWin(double winAmount) =>
      engineProvider.getTriggerStageForWin(winAmount);

  // --- Spin Execution ---
  Future<SlotLabSpinResult?> spin() => engineProvider.spin();
  Future<SlotLabSpinResult?> spinForced(ForcedOutcome outcome) =>
      engineProvider.spinForced(outcome);
  Future<SlotLabSpinResult?> spinForcedWithMultiplier(
    ForcedOutcome outcome,
    double targetMultiplier,
  ) => engineProvider.spinForcedWithMultiplier(outcome, targetMultiplier);

  // --- Stage Playback ---
  void stopStagePlayback() => stageProvider.stopStagePlayback();
  void stopAllPlayback() => stageProvider.stopAllPlayback();
  void pauseStages() => stageProvider.pauseStages();
  void resumeStages() => stageProvider.resumeStages();
  void togglePauseResume() => stageProvider.togglePauseResume();
  void triggerStageManually(int stageIndex) => stageProvider.triggerStageManually(stageIndex);

  // --- Stage Recording ---
  void startStageRecording() => stageProvider.startStageRecording();
  void stopStageRecording() => stageProvider.stopStageRecording();
  void clearStages() => stageProvider.clearStages();

  // --- Win Presentation ---
  void setWinPresentationActive(bool active) => stageProvider.setWinPresentationActive(active);
  void onAllReelsVisualStop() => stageProvider.onAllReelsVisualStop();
  void requestSkipPresentation(VoidCallback onComplete) =>
      stageProvider.requestSkipPresentation(onComplete);
  void onSkipComplete() => stageProvider.onSkipComplete();

  // --- Stage Validation ---
  List<StageValidationIssue> validateStageSequence() =>
      stageProvider.validateStageSequence();

  // --- Engine V2 ---
  bool initEngineV2() => engineProvider.initEngineV2();
  bool initEngineFromGdd(String gddJson) => engineProvider.initEngineFromGdd(gddJson);
  bool updateGameModel(Map<String, dynamic> model) => engineProvider.updateGameModel(model);
  void shutdownEngineV2() => engineProvider.shutdownEngineV2();

  // --- Scenario System ---
  bool loadScenario(String scenarioId) => engineProvider.loadScenario(scenarioId);
  void unloadScenario() => engineProvider.unloadScenario();
  bool registerScenario(Map<String, dynamic> scenarioJson) =>
      engineProvider.registerScenario(scenarioJson);
  bool registerScenarioFromDemoScenario(DemoScenario scenario) =>
      engineProvider.registerScenarioFromDemoScenario(scenario);
  (int, int) get scenarioProgress => engineProvider.scenarioProgress;
  bool get scenarioIsComplete => engineProvider.scenarioIsComplete;
  void resetScenario() => engineProvider.resetScenario();

  // --- Config Export/Import ---
  String? exportConfig() => engineProvider.exportConfig();
  bool importConfig(String json) => engineProvider.importConfig(json);

  // --- Audio Helpers ---
  double calculateWinLinePan(int lineIndex) =>
      audioProvider.calculateWinLinePan(lineIndex, lastResult);

  // ═══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _isDisposed = true;

    engineProvider.removeListener(_onSubProviderChanged);
    stageProvider.removeListener(_onSubProviderChanged);
    audioProvider.removeListener(_onSubProviderChanged);

    engineProvider.dispose();
    stageProvider.dispose();
    audioProvider.dispose();

    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BACKWARDS COMPATIBILITY ALIAS
// ═══════════════════════════════════════════════════════════════════════════

/// Backwards compatibility alias for SlotLabProvider
/// Existing code can continue to use SlotLabProvider name
typedef SlotLabProvider = SlotLabCoordinator;
