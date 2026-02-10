/// Stage → Audio Mapper
///
/// Bridges STAGES protocol events to FluxForge Middleware audio events.
/// Implements intelligent mapping with context-aware audio triggering.
library;

import '../models/stage_models.dart';
import '../models/slot_audio_events.dart';
import '../models/middleware_models.dart';
import '../providers/middleware_provider.dart';
import '../services/unified_playback_controller.dart';
import '../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STAGE TO AUDIO MAPPER
// ═══════════════════════════════════════════════════════════════════════════

/// Maps STAGES events to Middleware audio events and triggers them
class StageAudioMapper {
  final MiddlewareProvider _middleware;
  final NativeFFI _ffi;

  /// Playback source - determines which section acquires playback control
  /// Defaults to slotLab since this mapper is primarily used by SlotLab
  PlaybackSection _source = PlaybackSection.slotLab;

  // ─── Tracking State ──────────────────────────────────────────────────────
  int _currentReelIndex = 0;
  int _totalReels = 5;
  bool _inAnticipation = false;
  bool _inFeature = false;
  bool _inBigWin = false;
  int _cascadeDepth = 0;
  double _lastWinAmount = 0.0;
  double _lastBetAmount = 1.0;

  // ─── Active Looping Sounds ───────────────────────────────────────────────
  // Maps event ID (String) → playing ID (int) for active loops
  final Map<String, int> _activeLoops = {};

  // ─── Registered Events ───────────────────────────────────────────────────
  final Map<String, MiddlewareEvent> _slotEvents = {};

  StageAudioMapper(this._middleware, this._ffi, {PlaybackSection source = PlaybackSection.slotLab})
      : _source = source {
    _initializeSlotEvents();
  }

  /// Set playback source section (slotLab or middleware)
  set source(PlaybackSection value) => _source = value;

  /// Initialize all slot audio events
  void _initializeSlotEvents() {
    final events = SlotAudioEventFactory.createAllEvents();
    for (final event in events) {
      _slotEvents[event.id] = event;
      // Also register with middleware provider
      _middleware.registerEvent(event);
    }

    // Initialize slot-specific RTPCs
    final rtpcs = SlotRtpcFactory.createAllRtpcs();
    for (final rtpc in rtpcs) {
      _middleware.registerRtpc(rtpc);
    }

    // Initialize slot-specific state groups
    final stateGroups = SlotStateGroupFactory.createAllGroups();
    for (final group in stateGroups) {
      _middleware.registerStateGroup(group);
    }

    // Initialize ducking rules
    final duckingRules = SlotDuckingPresets.createAllRules();
    for (final rule in duckingRules) {
      _middleware.addDuckingRule(
        sourceBus: rule.sourceBus,
        sourceBusId: rule.sourceBusId,
        targetBus: rule.targetBus,
        targetBusId: rule.targetBusId,
        duckAmountDb: rule.duckAmountDb,
        attackMs: rule.attackMs,
        releaseMs: rule.releaseMs,
        threshold: rule.threshold,
        curve: rule.curve,
      );
    }

  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN MAPPING FUNCTION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Map a stage event to audio and trigger it
  void mapAndTrigger(StageEvent event) {
    final stage = event.stage;
    final payload = event.payload;

    // Update context from payload
    if (payload.betAmount != null) _lastBetAmount = payload.betAmount!;
    if (payload.winAmount != null) _lastWinAmount = payload.winAmount!;

    // Update RTPCs based on payload
    _updateRtpcsFromPayload(payload);

    // Get stage type name for matching triggerStages
    final stageTypeName = stage.typeName.toUpperCase();

    // 1. Trigger USER-DEFINED composite events that have this stage in triggerStages
    final userEvents = _middleware.compositeEvents
        .where((e) => e.triggerStages.any((s) => s.toUpperCase() == stageTypeName))
        .toList();

    for (final compositeEvent in userEvents) {
      _triggerCompositeEvent(compositeEvent, stage, payload);
    }

    // 2. Also trigger built-in slot events (for fallback/defaults)
    final builtinEventIds = _mapStageToEvents(stage, payload);
    for (final eventId in builtinEventIds) {
      // Only trigger if no user event matched (avoid double-triggering)
      if (userEvents.isEmpty || !_slotEvents.containsKey(eventId)) {
        _triggerEvent(eventId, stage, payload);
      }
    }

    if (userEvents.isNotEmpty) {
    }
  }

  /// Trigger a user-defined composite event directly
  void _triggerCompositeEvent(SlotCompositeEvent compositeEvent, Stage stage, StagePayload payload) {
    // Build context parameters
    final context = <String, dynamic>{
      'stage_type': stage.typeName,
      'reel_index': _currentReelIndex,
      'cascade_depth': _cascadeDepth,
      'in_feature': _inFeature,
      'in_anticipation': _inAnticipation,
      if (payload.winAmount != null) 'win_amount': payload.winAmount,
      if (payload.betAmount != null) 'bet_amount': payload.betAmount,
      if (payload.multiplier != null) 'multiplier': payload.multiplier,
    };

    // Trigger via middleware - use composite event ID directly
    final playingId = _middleware.playCompositeEvent(compositeEvent.id, source: _source);

  }

  /// Map a Stage to one or more event IDs
  List<String> _mapStageToEvents(Stage stage, StagePayload payload) {
    return switch (stage) {
      // ─── Spin Lifecycle ─────────────────────────────────────────────────
      SpinStart() => ['slot_spin_start'],

      ReelSpinning(reelIndex: final idx) => _handleReelSpinning(idx),

      ReelStop(reelIndex: final idx) => _handleReelStop(idx),

      SpinEnd() => ['slot_spin_end'],

      // ─── Anticipation ───────────────────────────────────────────────────
      AnticipationOn() => _handleAnticipationOn(),

      AnticipationOff() => _handleAnticipationOff(),

      // ─── Win Lifecycle ──────────────────────────────────────────────────
      WinPresent(winAmount: final amount) => _handleWinPresent(amount, payload),

      WinLineShow() => ['slot_win_line_show'],

      RollupStart() => _handleRollupStart(),

      RollupTick() => ['slot_rollup_tick'],

      RollupEnd() => _handleRollupEnd(),

      // ─── Big Win Tiers ──────────────────────────────────────────────────
      BigWinTierStage(tier: final tier) => _handleBigWinTier(tier),

      // ─── Feature Lifecycle ──────────────────────────────────────────────
      FeatureEnter(featureType: final ft) => _handleFeatureEnter(ft),

      FeatureStep() => ['slot_feature_step'],

      FeatureRetrigger() => ['slot_feature_retrigger'],

      FeatureExit() => _handleFeatureExit(),

      // ─── Cascade ────────────────────────────────────────────────────────
      CascadeStart() => _handleCascadeStart(),

      CascadeStep(stepIndex: final idx) => _handleCascadeStep(idx),

      CascadeEnd() => _handleCascadeEnd(),

      // ─── Bonus ──────────────────────────────────────────────────────────
      BonusEnter() => ['slot_bonus_enter'],

      BonusChoice() => ['slot_bonus_choice'],

      BonusReveal() => ['slot_bonus_reveal'],

      BonusExit() => ['slot_bonus_exit'],

      // ─── Gamble ─────────────────────────────────────────────────────────
      GambleStart() => ['slot_gamble_start'],

      GambleResultStage(result: final r) => _handleGambleResult(r),

      GambleEnd() => ['slot_gamble_collect'],

      // ─── Jackpot ────────────────────────────────────────────────────────
      JackpotTrigger() => ['slot_jackpot_trigger'],

      JackpotPresent() => ['slot_jackpot_present'],

      JackpotEnd() => ['slot_jackpot_end'],

      // ─── UI / Idle ──────────────────────────────────────────────────────
      IdleStart() || IdleLoop() => ['slot_idle_start'],

      MenuOpen() => ['slot_menu_open'],

      MenuClose() => ['slot_menu_close'],

      // ─── Default ────────────────────────────────────────────────────────
      _ => _handleUnknownStage(stage),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HANDLER METHODS
  // ═══════════════════════════════════════════════════════════════════════════

  List<String> _handleReelSpinning(int reelIndex) {
    _currentReelIndex = reelIndex;
    if (!_activeLoops.containsKey('slot_reel_spin')) {
      // Will be tracked when mapAndTrigger calls postEvent
      return ['slot_reel_spin'];
    }
    return []; // Already spinning
  }

  List<String> _handleReelStop(int reelIndex) {
    _currentReelIndex = reelIndex;

    // If this is the last reel, stop the loop
    if (reelIndex >= _totalReels - 1) {
      _stopLoop('slot_reel_spin');
    }

    return ['slot_reel_stop'];
  }

  List<String> _handleAnticipationOn() {
    _inAnticipation = true;
    // Anticipation loop will be tracked when triggered

    // Set tension RTPC
    _middleware.setRtpc(SlotRtpcIds.tension, 0.8, interpolationMs: 100);

    return ['slot_anticipation_on'];
  }

  List<String> _handleAnticipationOff() {
    _inAnticipation = false;
    _stopLoop('slot_anticipation_on');

    // Reset tension RTPC
    _middleware.setRtpc(SlotRtpcIds.tension, 0.0, interpolationMs: 200);

    return ['slot_anticipation_off'];
  }

  List<String> _handleWinPresent(double amount, StagePayload payload) {
    final ratio = payload.calculateRatio() ?? (amount / _lastBetAmount);

    // Update win multiplier RTPC
    _middleware.setRtpc(SlotRtpcIds.winMultiplier, ratio.clamp(0.0, 1000.0));

    // Small wins just get basic win sound
    if (ratio < 10) {
      return ['slot_win_present'];
    }

    // Bigger wins handled by BigWinTier stage
    return ['slot_win_present'];
  }

  List<String> _handleRollupStart() {
    // Rollup loop will be tracked when triggered
    return ['slot_rollup_start'];
  }

  List<String> _handleRollupEnd() {
    _stopLoop('slot_rollup_start');
    _inBigWin = false;

    // Reset win multiplier
    _middleware.setRtpc(SlotRtpcIds.winMultiplier, 0.0, interpolationMs: 500);

    return ['slot_rollup_end'];
  }

  List<String> _handleBigWinTier(BigWinTier tier) {
    _inBigWin = true;

    // Set music mode state
    _middleware.setState(SlotStateGroupIds.musicMode, 2); // BigWin mode

    return switch (tier) {
      BigWinTier.win || BigWinTier.bigWin => ['slot_bigwin_base'],
      BigWinTier.megaWin => ['slot_bigwin_mega'],
      BigWinTier.epicWin => ['slot_bigwin_epic'],
      BigWinTier.ultraWin => ['slot_bigwin_ultra'],
    };
  }

  List<String> _handleFeatureEnter(FeatureType featureType) {
    _inFeature = true;

    // Set game phase state
    _middleware.setState(SlotStateGroupIds.gamePhase, 2); // Free_Spins

    // Set feature type state
    final featureStateId = switch (featureType) {
      FeatureType.freeSpins => 1,
      FeatureType.pickBonus => 2,
      FeatureType.wheelBonus => 3,
      FeatureType.holdAndSpin => 4,
      FeatureType.cascade => 5,
      _ => 1,
    };
    _middleware.setState(SlotStateGroupIds.featureType, featureStateId);

    // Set music mode
    _middleware.setState(SlotStateGroupIds.musicMode, 1); // Feature mode

    // Reset feature progress
    _middleware.setRtpc(SlotRtpcIds.featureProgress, 0.0);

    return ['slot_feature_enter'];
  }

  List<String> _handleFeatureExit() {
    _inFeature = false;

    // Reset states
    _middleware.setState(SlotStateGroupIds.gamePhase, 1); // Base_Game
    _middleware.setState(SlotStateGroupIds.featureType, 0); // None
    _middleware.setState(SlotStateGroupIds.musicMode, 0); // Normal

    // Reset feature progress
    _middleware.setRtpc(SlotRtpcIds.featureProgress, 0.0, interpolationMs: 500);

    return ['slot_feature_exit'];
  }

  List<String> _handleCascadeStart() {
    _cascadeDepth = 0;
    _middleware.setRtpc(SlotRtpcIds.cascadeDepth, 0.0);
    return ['slot_cascade_start'];
  }

  List<String> _handleCascadeStep(int stepIndex) {
    _cascadeDepth = stepIndex + 1;
    _middleware.setRtpc(SlotRtpcIds.cascadeDepth, _cascadeDepth.toDouble());
    return ['slot_cascade_step'];
  }

  List<String> _handleCascadeEnd() {
    _cascadeDepth = 0;
    _middleware.setRtpc(SlotRtpcIds.cascadeDepth, 0.0, interpolationMs: 300);
    return ['slot_cascade_end'];
  }

  List<String> _handleGambleResult(GambleResult result) {
    return switch (result) {
      GambleResult.win => ['slot_gamble_win'],
      GambleResult.lose => ['slot_gamble_lose'],
      GambleResult.draw => ['slot_gamble_win'], // Treat draw as minor win
      GambleResult.collected => ['slot_gamble_collect'],
    };
  }

  List<String> _handleUnknownStage(Stage stage) {
    return [];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RTPC UPDATES
  // ═══════════════════════════════════════════════════════════════════════════

  void _updateRtpcsFromPayload(StagePayload payload) {
    // Update win multiplier if we have win data
    if (payload.winAmount != null && payload.betAmount != null) {
      final ratio = payload.winAmount! / payload.betAmount!;
      _middleware.setRtpc(
        SlotRtpcIds.winMultiplier,
        ratio.clamp(0.0, 1000.0),
        interpolationMs: 50,
      );
    }

    // Update feature progress
    if (payload.spinsRemaining != null && _inFeature) {
      // Estimate total from remaining (this is approximate)
      final total = payload.spinsRemaining! + 1;
      final progress = 1.0 - (payload.spinsRemaining! / total);
      _middleware.setRtpc(SlotRtpcIds.featureProgress, progress);
    }

    // Update multiplier (for cascade games)
    if (payload.multiplier != null) {
      // Normalize multiplier to 0-1 range (assume max 15x)
      final normalized = ((payload.multiplier! - 1.0) / 14.0).clamp(0.0, 1.0);
      _middleware.setRtpc(SlotRtpcIds.cascadeDepth, normalized * 15);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EVENT TRIGGERING
  // ═══════════════════════════════════════════════════════════════════════════

  void _triggerEvent(String eventId, Stage stage, StagePayload payload) {
    final event = _slotEvents[eventId];
    if (event == null) {
      return;
    }

    // Build context parameters
    final context = <String, dynamic>{
      'stage_type': stage.typeName,
      'reel_index': _currentReelIndex,
      'cascade_depth': _cascadeDepth,
      'in_feature': _inFeature,
      'in_anticipation': _inAnticipation,
      if (payload.winAmount != null) 'win_amount': payload.winAmount,
      if (payload.betAmount != null) 'bet_amount': payload.betAmount,
      if (payload.multiplier != null) 'multiplier': payload.multiplier,
    };

    // Post event via middleware with correct source section
    final playingId = _middleware.postEvent(eventId, gameObjectId: 0, context: context, source: _source);

    // Track looping events for later stop
    if (_isLoopingEvent(eventId) && playingId > 0) {
      trackLoop(eventId, playingId);
    }

  }

  /// Check if an event contains looping sounds
  bool _isLoopingEvent(String eventId) {
    return eventId == 'slot_reel_spin' ||
           eventId == 'slot_anticipation_on' ||
           eventId == 'slot_rollup_start' ||
           eventId == 'slot_bigwin_tier_mega' ||
           eventId == 'slot_bigwin_tier_epic' ||
           eventId == 'slot_bigwin_tier_legendary';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set total reel count for proper loop management
  void setReelCount(int count) {
    _totalReels = count;
  }

  /// Track a looping sound by event ID
  void trackLoop(String eventId, int playingId) {
    if (playingId > 0) {
      _activeLoops[eventId] = playingId;
    }
  }

  /// Stop a specific loop by event ID
  void _stopLoop(String eventId) {
    final playingId = _activeLoops.remove(eventId);
    if (playingId != null && playingId > 0) {
      _ffi.middlewareStopEvent(playingId, fadeMs: 200);
    }
  }

  /// Stop all active loops (e.g., on disconnect)
  void stopAllLoops() {
    for (final entry in _activeLoops.entries.toList()) {
      if (entry.value > 0) {
        _ffi.middlewareStopEvent(entry.value, fadeMs: 200);
      }
    }
    _activeLoops.clear();
  }

  /// Reset state (e.g., on new session)
  void reset() {
    stopAllLoops();
    _currentReelIndex = 0;
    _inAnticipation = false;
    _inFeature = false;
    _inBigWin = false;
    _cascadeDepth = 0;
    _lastWinAmount = 0.0;
    _lastBetAmount = 1.0;

    // Reset all RTPCs
    _middleware.setRtpc(SlotRtpcIds.winMultiplier, 0.0);
    _middleware.setRtpc(SlotRtpcIds.tension, 0.0);
    _middleware.setRtpc(SlotRtpcIds.cascadeDepth, 0.0);
    _middleware.setRtpc(SlotRtpcIds.featureProgress, 0.0);

    // Reset state groups
    _middleware.setState(SlotStateGroupIds.gamePhase, 1); // Base_Game
    _middleware.setState(SlotStateGroupIds.featureType, 0); // None
    _middleware.setState(SlotStateGroupIds.musicMode, 0); // Normal
  }

  /// Get statistics
  ({
    int registeredEvents,
    int activeLoops,
    bool inFeature,
    bool inAnticipation,
    int cascadeDepth,
  }) get stats => (
    registeredEvents: _slotEvents.length,
    activeLoops: _activeLoops.length,
    inFeature: _inFeature,
    inAnticipation: _inAnticipation,
    cascadeDepth: _cascadeDepth,
  );
}
