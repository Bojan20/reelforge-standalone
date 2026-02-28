/// Behavior Tree Models — SlotLab Middleware §5
///
/// The primary authoring abstraction for SlotLab audio.
/// Behavior nodes aggregate and contextualize engine hooks into
/// ~22 designer-facing nodes organized in 7 categories.
///
/// See: SlotLab_Middleware_Architecture_Ultimate.md §5


// =============================================================================
// BEHAVIOR CATEGORIES (7 top-level groups)
// =============================================================================

/// Top-level behavior category in the tree
enum BehaviorCategory {
  reels,
  cascade,
  win,
  feature,
  jackpot,
  ui,
  system,
}

extension BehaviorCategoryExtension on BehaviorCategory {
  String get displayName {
    switch (this) {
      case BehaviorCategory.reels: return 'REELS';
      case BehaviorCategory.cascade: return 'CASCADE';
      case BehaviorCategory.win: return 'WIN';
      case BehaviorCategory.feature: return 'FEATURE';
      case BehaviorCategory.jackpot: return 'JACKPOT';
      case BehaviorCategory.ui: return 'UI';
      case BehaviorCategory.system: return 'SYSTEM';
    }
  }

  /// Default priority class for this category
  BehaviorPriorityClass get defaultPriority {
    switch (this) {
      case BehaviorCategory.reels: return BehaviorPriorityClass.core;
      case BehaviorCategory.cascade: return BehaviorPriorityClass.core;
      case BehaviorCategory.win: return BehaviorPriorityClass.critical;
      case BehaviorCategory.feature: return BehaviorPriorityClass.high;
      case BehaviorCategory.jackpot: return BehaviorPriorityClass.critical;
      case BehaviorCategory.ui: return BehaviorPriorityClass.low;
      case BehaviorCategory.system: return BehaviorPriorityClass.ambient;
    }
  }

  /// Default bus route for this category
  String get defaultBusRoute {
    switch (this) {
      case BehaviorCategory.reels: return 'sfx_reels';
      case BehaviorCategory.cascade: return 'sfx_cascade';
      case BehaviorCategory.win: return 'sfx_wins';
      case BehaviorCategory.feature: return 'sfx_features';
      case BehaviorCategory.jackpot: return 'sfx_jackpot';
      case BehaviorCategory.ui: return 'sfx_ui';
      case BehaviorCategory.system: return 'sfx_system';
    }
  }

  /// Icon for tree display
  String get icon {
    switch (this) {
      case BehaviorCategory.reels: return '🎰';
      case BehaviorCategory.cascade: return '⬇';
      case BehaviorCategory.win: return '🏆';
      case BehaviorCategory.feature: return '⭐';
      case BehaviorCategory.jackpot: return '💎';
      case BehaviorCategory.ui: return '🖱';
      case BehaviorCategory.system: return '⚙';
    }
  }
}

// =============================================================================
// BEHAVIOR NODE TYPE (22 leaf nodes)
// =============================================================================

/// Specific behavior node type within a category
enum BehaviorNodeType {
  // REELS (4)
  reelStop,
  reelLand,
  reelAnticipation,
  reelNudge,

  // CASCADE (3)
  cascadeStart,
  cascadeStep,
  cascadeEnd,

  // WIN (4)
  winSmall,
  winBig,
  winMega,
  winCountup,

  // FEATURE (3)
  featureIntro,
  featureLoop,
  featureOutro,

  // JACKPOT (3)
  jackpotMini,
  jackpotMajor,
  jackpotGrand,

  // UI (3)
  uiButton,
  uiPopup,
  uiToggle,

  // SYSTEM (2)
  systemSessionStart,
  systemSessionEnd,
}

extension BehaviorNodeTypeExtension on BehaviorNodeType {
  /// Parent category
  BehaviorCategory get category {
    switch (this) {
      case BehaviorNodeType.reelStop:
      case BehaviorNodeType.reelLand:
      case BehaviorNodeType.reelAnticipation:
      case BehaviorNodeType.reelNudge:
        return BehaviorCategory.reels;
      case BehaviorNodeType.cascadeStart:
      case BehaviorNodeType.cascadeStep:
      case BehaviorNodeType.cascadeEnd:
        return BehaviorCategory.cascade;
      case BehaviorNodeType.winSmall:
      case BehaviorNodeType.winBig:
      case BehaviorNodeType.winMega:
      case BehaviorNodeType.winCountup:
        return BehaviorCategory.win;
      case BehaviorNodeType.featureIntro:
      case BehaviorNodeType.featureLoop:
      case BehaviorNodeType.featureOutro:
        return BehaviorCategory.feature;
      case BehaviorNodeType.jackpotMini:
      case BehaviorNodeType.jackpotMajor:
      case BehaviorNodeType.jackpotGrand:
        return BehaviorCategory.jackpot;
      case BehaviorNodeType.uiButton:
      case BehaviorNodeType.uiPopup:
      case BehaviorNodeType.uiToggle:
        return BehaviorCategory.ui;
      case BehaviorNodeType.systemSessionStart:
      case BehaviorNodeType.systemSessionEnd:
        return BehaviorCategory.system;
    }
  }

  /// Display name for UI
  String get displayName {
    switch (this) {
      case BehaviorNodeType.reelStop: return 'Stop';
      case BehaviorNodeType.reelLand: return 'Land';
      case BehaviorNodeType.reelAnticipation: return 'Anticipation';
      case BehaviorNodeType.reelNudge: return 'Nudge';
      case BehaviorNodeType.cascadeStart: return 'Start';
      case BehaviorNodeType.cascadeStep: return 'Step';
      case BehaviorNodeType.cascadeEnd: return 'End';
      case BehaviorNodeType.winSmall: return 'Small';
      case BehaviorNodeType.winBig: return 'Big';
      case BehaviorNodeType.winMega: return 'Mega';
      case BehaviorNodeType.winCountup: return 'Countup';
      case BehaviorNodeType.featureIntro: return 'Intro';
      case BehaviorNodeType.featureLoop: return 'Loop';
      case BehaviorNodeType.featureOutro: return 'Outro';
      case BehaviorNodeType.jackpotMini: return 'Mini';
      case BehaviorNodeType.jackpotMajor: return 'Major';
      case BehaviorNodeType.jackpotGrand: return 'Grand';
      case BehaviorNodeType.uiButton: return 'Button';
      case BehaviorNodeType.uiPopup: return 'Popup';
      case BehaviorNodeType.uiToggle: return 'Toggle';
      case BehaviorNodeType.systemSessionStart: return 'Session Start';
      case BehaviorNodeType.systemSessionEnd: return 'Session End';
    }
  }

  /// Engine hooks that this behavior node maps to
  List<String> get mappedHooks {
    switch (this) {
      case BehaviorNodeType.reelStop:
        return ['onReelStop_r1', 'onReelStop_r2', 'onReelStop_r3', 'onReelStop_r4', 'onReelStop_r5'];
      case BehaviorNodeType.reelLand:
        return ['onSymbolLand'];
      case BehaviorNodeType.reelAnticipation:
        return ['onAnticipationStart', 'onAnticipationEnd'];
      case BehaviorNodeType.reelNudge:
        return ['onReelNudge'];
      case BehaviorNodeType.cascadeStart:
        return ['onCascadeStart'];
      case BehaviorNodeType.cascadeStep:
        return ['onCascadeStep'];
      case BehaviorNodeType.cascadeEnd:
        return ['onCascadeEnd'];
      case BehaviorNodeType.winSmall:
        return ['onWinEvaluate_tier1', 'onWinEvaluate_tier2'];
      case BehaviorNodeType.winBig:
        return ['onWinEvaluate_tier3'];
      case BehaviorNodeType.winMega:
        return ['onWinEvaluate_tier4', 'onWinEvaluate_tier5'];
      case BehaviorNodeType.winCountup:
        return ['onCountUpTick', 'onCountUpEnd'];
      case BehaviorNodeType.featureIntro:
        return ['onFeatureEnter'];
      case BehaviorNodeType.featureLoop:
        return ['onFeatureLoop'];
      case BehaviorNodeType.featureOutro:
        return ['onFeatureExit'];
      case BehaviorNodeType.jackpotMini:
        return ['onJackpotReveal_mini'];
      case BehaviorNodeType.jackpotMajor:
        return ['onJackpotReveal_major'];
      case BehaviorNodeType.jackpotGrand:
        return ['onJackpotReveal_grand'];
      case BehaviorNodeType.uiButton:
        return ['onButtonPress', 'onButtonRelease'];
      case BehaviorNodeType.uiPopup:
        return ['onPopupShow', 'onPopupDismiss'];
      case BehaviorNodeType.uiToggle:
        return ['onToggleChange'];
      case BehaviorNodeType.systemSessionStart:
        return ['onSessionStart'];
      case BehaviorNodeType.systemSessionEnd:
        return ['onSessionEnd'];
    }
  }

  /// Default playback mode per §5.3
  PlaybackMode get defaultPlaybackMode {
    switch (this) {
      case BehaviorNodeType.reelStop:
      case BehaviorNodeType.reelLand:
      case BehaviorNodeType.reelNudge:
        return PlaybackMode.oneShot;
      case BehaviorNodeType.reelAnticipation:
        return PlaybackMode.loopUntilStop;
      case BehaviorNodeType.cascadeStart:
      case BehaviorNodeType.cascadeEnd:
        return PlaybackMode.oneShot;
      case BehaviorNodeType.cascadeStep:
        return PlaybackMode.retrigger;
      case BehaviorNodeType.winSmall:
      case BehaviorNodeType.winBig:
      case BehaviorNodeType.winMega:
        return PlaybackMode.sequence;
      case BehaviorNodeType.winCountup:
        return PlaybackMode.retrigger;
      case BehaviorNodeType.featureIntro:
      case BehaviorNodeType.featureOutro:
        return PlaybackMode.oneShot;
      case BehaviorNodeType.featureLoop:
        return PlaybackMode.loopUntilStop;
      case BehaviorNodeType.jackpotMini:
      case BehaviorNodeType.jackpotMajor:
      case BehaviorNodeType.jackpotGrand:
        return PlaybackMode.sequence;
      case BehaviorNodeType.uiButton:
      case BehaviorNodeType.uiPopup:
      case BehaviorNodeType.uiToggle:
        return PlaybackMode.oneShot;
      case BehaviorNodeType.systemSessionStart:
      case BehaviorNodeType.systemSessionEnd:
        return PlaybackMode.oneShot;
    }
  }

  /// Unique string ID for serialization
  String get nodeId {
    switch (this) {
      case BehaviorNodeType.reelStop: return 'reel_stop';
      case BehaviorNodeType.reelLand: return 'reel_land';
      case BehaviorNodeType.reelAnticipation: return 'reel_anticipation';
      case BehaviorNodeType.reelNudge: return 'reel_nudge';
      case BehaviorNodeType.cascadeStart: return 'cascade_start';
      case BehaviorNodeType.cascadeStep: return 'cascade_step';
      case BehaviorNodeType.cascadeEnd: return 'cascade_end';
      case BehaviorNodeType.winSmall: return 'win_small';
      case BehaviorNodeType.winBig: return 'win_big';
      case BehaviorNodeType.winMega: return 'win_mega';
      case BehaviorNodeType.winCountup: return 'win_countup';
      case BehaviorNodeType.featureIntro: return 'feature_intro';
      case BehaviorNodeType.featureLoop: return 'feature_loop';
      case BehaviorNodeType.featureOutro: return 'feature_outro';
      case BehaviorNodeType.jackpotMini: return 'jackpot_mini';
      case BehaviorNodeType.jackpotMajor: return 'jackpot_major';
      case BehaviorNodeType.jackpotGrand: return 'jackpot_grand';
      case BehaviorNodeType.uiButton: return 'ui_button';
      case BehaviorNodeType.uiPopup: return 'ui_popup';
      case BehaviorNodeType.uiToggle: return 'ui_toggle';
      case BehaviorNodeType.systemSessionStart: return 'system_session_start';
      case BehaviorNodeType.systemSessionEnd: return 'system_session_end';
    }
  }

  /// Parse from string ID
  static BehaviorNodeType? fromId(String id) {
    for (final type in BehaviorNodeType.values) {
      if (type.nodeId == id) return type;
    }
    return null;
  }
}

// =============================================================================
// PLAYBACK MODE (6 lifecycle types per §5.3)
// =============================================================================

/// Defines how sound is managed during its lifecycle
enum PlaybackMode {
  /// Play once, fire and forget
  oneShot,
  /// Loop until explicitly stopped
  loop,
  /// Loop with fade-out on stop command
  loopUntilStop,
  /// Restart from beginning on each trigger
  retrigger,
  /// Play items in order with timing (attack → loop → resolve)
  sequence,
  /// Play attack, sustain on hold, release on stop
  sustain,
}

extension PlaybackModeExtension on PlaybackMode {
  String get displayName {
    switch (this) {
      case PlaybackMode.oneShot: return 'One Shot';
      case PlaybackMode.loop: return 'Loop';
      case PlaybackMode.loopUntilStop: return 'Loop Until Stop';
      case PlaybackMode.retrigger: return 'Retrigger';
      case PlaybackMode.sequence: return 'Sequence';
      case PlaybackMode.sustain: return 'Sustain';
    }
  }

  String get description {
    switch (this) {
      case PlaybackMode.oneShot: return 'Play once, fire and forget';
      case PlaybackMode.loop: return 'Loop until explicitly stopped';
      case PlaybackMode.loopUntilStop: return 'Loop with fade-out on stop';
      case PlaybackMode.retrigger: return 'Restart from beginning on each trigger';
      case PlaybackMode.sequence: return 'Play items in order with timing';
      case PlaybackMode.sustain: return 'Attack, sustain on hold, release on stop';
    }
  }
}

// =============================================================================
// PRIORITY CLASS (6 classes per §8)
// =============================================================================

/// Behavior priority classes for conflict resolution
enum BehaviorPriorityClass {
  /// Jackpot, mega win — never interrupted
  critical,
  /// Reel mechanics, win sounds — core gameplay
  core,
  /// Feature sounds — important but interruptible
  high,
  /// Supplementary effects
  medium,
  /// UI feedback
  low,
  /// Background ambience
  ambient,
}

extension BehaviorPriorityClassExtension on BehaviorPriorityClass {
  String get displayName {
    switch (this) {
      case BehaviorPriorityClass.critical: return 'Critical';
      case BehaviorPriorityClass.core: return 'Core';
      case BehaviorPriorityClass.high: return 'High';
      case BehaviorPriorityClass.medium: return 'Medium';
      case BehaviorPriorityClass.low: return 'Low';
      case BehaviorPriorityClass.ambient: return 'Ambient';
    }
  }

  /// Numeric priority (higher = more important)
  int get numericPriority {
    switch (this) {
      case BehaviorPriorityClass.critical: return 100;
      case BehaviorPriorityClass.core: return 80;
      case BehaviorPriorityClass.high: return 60;
      case BehaviorPriorityClass.medium: return 40;
      case BehaviorPriorityClass.low: return 20;
      case BehaviorPriorityClass.ambient: return 10;
    }
  }

  /// Conflict resolution: what happens when a lower-priority sound conflicts
  PriorityConflictAction get conflictAction {
    switch (this) {
      case BehaviorPriorityClass.critical: return PriorityConflictAction.suppress;
      case BehaviorPriorityClass.core: return PriorityConflictAction.duck;
      case BehaviorPriorityClass.high: return PriorityConflictAction.duck;
      case BehaviorPriorityClass.medium: return PriorityConflictAction.delay;
      case BehaviorPriorityClass.low: return PriorityConflictAction.delay;
      case BehaviorPriorityClass.ambient: return PriorityConflictAction.suppress;
    }
  }
}

/// Action taken when priority conflict occurs
enum PriorityConflictAction {
  /// Lower-priority sound is silenced completely
  suppress,
  /// Lower-priority sound is ducked (volume reduced)
  duck,
  /// Lower-priority sound is delayed until higher finishes
  delay,
}

// =============================================================================
// VARIANT CONFIG (per §5.4)
// =============================================================================

/// Selection mode for sound variants within a behavior node
enum VariantSelectionMode {
  roundRobin,
  random,
  shuffle,
  weighted,
  sequential,
}

extension VariantSelectionModeExtension on VariantSelectionMode {
  String get displayName {
    switch (this) {
      case VariantSelectionMode.roundRobin: return 'Round Robin';
      case VariantSelectionMode.random: return 'Random';
      case VariantSelectionMode.shuffle: return 'Shuffle';
      case VariantSelectionMode.weighted: return 'Weighted';
      case VariantSelectionMode.sequential: return 'Sequential';
    }
  }
}

/// Configuration for variant selection within a behavior node
class VariantConfig {
  /// Selection algorithm
  final VariantSelectionMode mode;

  /// Maximum variants per node
  final int maxVariants;

  /// Minimum distance before replaying same variant
  final int avoidRepeat;

  /// Random pitch deviation per play [min, max] in cents (-100 to +100)
  final List<double> pitchVariance;

  /// Random volume deviation per play [min, max] in dB (-3.0 to +1.0)
  final List<double> volumeVariance;

  const VariantConfig({
    this.mode = VariantSelectionMode.roundRobin,
    this.maxVariants = 8,
    this.avoidRepeat = 2,
    this.pitchVariance = const [-50.0, 50.0],
    this.volumeVariance = const [-2.0, 1.0],
  });

  VariantConfig copyWith({
    VariantSelectionMode? mode,
    int? maxVariants,
    int? avoidRepeat,
    List<double>? pitchVariance,
    List<double>? volumeVariance,
  }) {
    return VariantConfig(
      mode: mode ?? this.mode,
      maxVariants: maxVariants ?? this.maxVariants,
      avoidRepeat: avoidRepeat ?? this.avoidRepeat,
      pitchVariance: pitchVariance ?? this.pitchVariance,
      volumeVariance: volumeVariance ?? this.volumeVariance,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'max_variants': maxVariants,
    'avoid_repeat': avoidRepeat,
    'pitch_variance': pitchVariance,
    'volume_variance': volumeVariance,
  };

  factory VariantConfig.fromJson(Map<String, dynamic> json) {
    return VariantConfig(
      mode: VariantSelectionMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => VariantSelectionMode.roundRobin,
      ),
      maxVariants: json['max_variants'] as int? ?? 8,
      avoidRepeat: json['avoid_repeat'] as int? ?? 2,
      pitchVariance: (json['pitch_variance'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble()).toList() ?? [-50.0, 50.0],
      volumeVariance: (json['volume_variance'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble()).toList() ?? [-2.0, 1.0],
    );
  }
}

// =============================================================================
// PARAMETER TIERS (Progressive Disclosure per §19)
// =============================================================================

/// Basic parameters visible to all users
class BasicParams {
  /// Master gain in dB
  final double gain;

  /// Priority class
  final BehaviorPriorityClass priorityClass;

  /// Layer group for organization
  final String layerGroup;

  /// Bus route for output
  final String busRoute;

  const BasicParams({
    this.gain = 0.0,
    this.priorityClass = BehaviorPriorityClass.core,
    this.layerGroup = 'default',
    this.busRoute = 'sfx_master',
  });

  BasicParams copyWith({
    double? gain,
    BehaviorPriorityClass? priorityClass,
    String? layerGroup,
    String? busRoute,
  }) {
    return BasicParams(
      gain: gain ?? this.gain,
      priorityClass: priorityClass ?? this.priorityClass,
      layerGroup: layerGroup ?? this.layerGroup,
      busRoute: busRoute ?? this.busRoute,
    );
  }

  Map<String, dynamic> toJson() => {
    'gain': gain,
    'priority_class': priorityClass.name,
    'layer_group': layerGroup,
    'bus_route': busRoute,
  };

  factory BasicParams.fromJson(Map<String, dynamic> json) {
    return BasicParams(
      gain: (json['gain'] as num?)?.toDouble() ?? 0.0,
      priorityClass: BehaviorPriorityClass.values.firstWhere(
        (e) => e.name == json['priority_class'],
        orElse: () => BehaviorPriorityClass.core,
      ),
      layerGroup: json['layer_group'] as String? ?? 'default',
      busRoute: json['bus_route'] as String? ?? 'sfx_master',
    );
  }
}

/// Advanced parameters for experienced users
class AdvancedParams {
  /// Escalation bias — shifts AUREXIS escalation curve
  final double escalationBias;

  /// Spatial weight — importance in spatial audio scene
  final double spatialWeight;

  /// Energy weight — contribution to emotional energy
  final double energyWeight;

  /// Fade policy (auto, manual, none)
  final String fadePolicy;

  const AdvancedParams({
    this.escalationBias = 0.0,
    this.spatialWeight = 1.0,
    this.energyWeight = 1.0,
    this.fadePolicy = 'auto',
  });

  AdvancedParams copyWith({
    double? escalationBias,
    double? spatialWeight,
    double? energyWeight,
    String? fadePolicy,
  }) {
    return AdvancedParams(
      escalationBias: escalationBias ?? this.escalationBias,
      spatialWeight: spatialWeight ?? this.spatialWeight,
      energyWeight: energyWeight ?? this.energyWeight,
      fadePolicy: fadePolicy ?? this.fadePolicy,
    );
  }

  Map<String, dynamic> toJson() => {
    'escalation_bias': escalationBias,
    'spatial_weight': spatialWeight,
    'energy_weight': energyWeight,
    'fade_policy': fadePolicy,
  };

  factory AdvancedParams.fromJson(Map<String, dynamic> json) {
    return AdvancedParams(
      escalationBias: (json['escalation_bias'] as num?)?.toDouble() ?? 0.0,
      spatialWeight: (json['spatial_weight'] as num?)?.toDouble() ?? 1.0,
      energyWeight: (json['energy_weight'] as num?)?.toDouble() ?? 1.0,
      fadePolicy: json['fade_policy'] as String? ?? 'auto',
    );
  }
}

/// Expert parameters for power users
class ExpertParams {
  /// Direct hook modifier override (bypasses behavior abstraction)
  final String? rawHookModifier;

  /// Override AUREXIS bias for this node
  final double? aurexisBiasOverride;

  /// Override execution priority for this node
  final int? executionPriorityOverride;

  const ExpertParams({
    this.rawHookModifier,
    this.aurexisBiasOverride,
    this.executionPriorityOverride,
  });

  ExpertParams copyWith({
    String? rawHookModifier,
    double? aurexisBiasOverride,
    int? executionPriorityOverride,
  }) {
    return ExpertParams(
      rawHookModifier: rawHookModifier ?? this.rawHookModifier,
      aurexisBiasOverride: aurexisBiasOverride ?? this.aurexisBiasOverride,
      executionPriorityOverride: executionPriorityOverride ?? this.executionPriorityOverride,
    );
  }

  Map<String, dynamic> toJson() => {
    if (rawHookModifier != null) 'raw_hook_modifier': rawHookModifier,
    if (aurexisBiasOverride != null) 'aurexis_bias_override': aurexisBiasOverride,
    if (executionPriorityOverride != null) 'execution_priority_override': executionPriorityOverride,
  };

  factory ExpertParams.fromJson(Map<String, dynamic> json) {
    return ExpertParams(
      rawHookModifier: json['raw_hook_modifier'] as String?,
      aurexisBiasOverride: (json['aurexis_bias_override'] as num?)?.toDouble(),
      executionPriorityOverride: json['execution_priority_override'] as int?,
    );
  }
}

// =============================================================================
// CONTEXT OVERRIDE (per §26)
// =============================================================================

/// Per-node override for a specific game context
class ContextOverride {
  /// Which context this override applies to
  final String contextId;

  /// Override gain (null = use default)
  final double? gainOverride;

  /// Override bus route (null = use default)
  final String? busRouteOverride;

  /// Override playback mode (null = use default)
  final PlaybackMode? playbackModeOverride;

  /// Override variant config (null = use default)
  final VariantConfig? variantConfigOverride;

  /// Whether this node is disabled in this context
  final bool disabled;

  const ContextOverride({
    required this.contextId,
    this.gainOverride,
    this.busRouteOverride,
    this.playbackModeOverride,
    this.variantConfigOverride,
    this.disabled = false,
  });

  ContextOverride copyWith({
    String? contextId,
    double? gainOverride,
    String? busRouteOverride,
    PlaybackMode? playbackModeOverride,
    VariantConfig? variantConfigOverride,
    bool? disabled,
  }) {
    return ContextOverride(
      contextId: contextId ?? this.contextId,
      gainOverride: gainOverride ?? this.gainOverride,
      busRouteOverride: busRouteOverride ?? this.busRouteOverride,
      playbackModeOverride: playbackModeOverride ?? this.playbackModeOverride,
      variantConfigOverride: variantConfigOverride ?? this.variantConfigOverride,
      disabled: disabled ?? this.disabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'context_id': contextId,
    if (gainOverride != null) 'gain_override': gainOverride,
    if (busRouteOverride != null) 'bus_route_override': busRouteOverride,
    if (playbackModeOverride != null) 'playback_mode_override': playbackModeOverride!.name,
    if (variantConfigOverride != null) 'variant_config_override': variantConfigOverride!.toJson(),
    'disabled': disabled,
  };

  factory ContextOverride.fromJson(Map<String, dynamic> json) {
    return ContextOverride(
      contextId: json['context_id'] as String,
      gainOverride: (json['gain_override'] as num?)?.toDouble(),
      busRouteOverride: json['bus_route_override'] as String?,
      playbackModeOverride: json['playback_mode_override'] != null
          ? PlaybackMode.values.firstWhere(
              (e) => e.name == json['playback_mode_override'],
              orElse: () => PlaybackMode.oneShot,
            )
          : null,
      variantConfigOverride: json['variant_config_override'] != null
          ? VariantConfig.fromJson(json['variant_config_override'] as Map<String, dynamic>)
          : null,
      disabled: json['disabled'] as bool? ?? false,
    );
  }
}

// =============================================================================
// SOUND ASSIGNMENT (audio file → behavior node)
// =============================================================================

/// A single sound file assigned to a behavior node
class BehaviorSoundAssignment {
  /// Unique ID for this assignment
  final String id;

  /// Path to audio file (relative to project)
  final String audioPath;

  /// Display name (derived from filename)
  final String displayName;

  /// Variant index (0-based, for multi-variant nodes)
  final int variantIndex;

  /// Weight for weighted selection mode
  final double weight;

  /// Whether this was auto-bound (vs manual)
  final bool autoBound;

  /// AutoBind confidence score (0.0-1.0)
  final double bindConfidence;

  const BehaviorSoundAssignment({
    required this.id,
    required this.audioPath,
    required this.displayName,
    this.variantIndex = 0,
    this.weight = 1.0,
    this.autoBound = false,
    this.bindConfidence = 0.0,
  });

  BehaviorSoundAssignment copyWith({
    String? id,
    String? audioPath,
    String? displayName,
    int? variantIndex,
    double? weight,
    bool? autoBound,
    double? bindConfidence,
  }) {
    return BehaviorSoundAssignment(
      id: id ?? this.id,
      audioPath: audioPath ?? this.audioPath,
      displayName: displayName ?? this.displayName,
      variantIndex: variantIndex ?? this.variantIndex,
      weight: weight ?? this.weight,
      autoBound: autoBound ?? this.autoBound,
      bindConfidence: bindConfidence ?? this.bindConfidence,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'audio_path': audioPath,
    'display_name': displayName,
    'variant_index': variantIndex,
    'weight': weight,
    'auto_bound': autoBound,
    'bind_confidence': bindConfidence,
  };

  factory BehaviorSoundAssignment.fromJson(Map<String, dynamic> json) {
    return BehaviorSoundAssignment(
      id: json['id'] as String,
      audioPath: json['audio_path'] as String,
      displayName: json['display_name'] as String? ?? '',
      variantIndex: json['variant_index'] as int? ?? 0,
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
      autoBound: json['auto_bound'] as bool? ?? false,
      bindConfidence: (json['bind_confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// =============================================================================
// BEHAVIOR NODE (Core data model per §5.2)
// =============================================================================

/// Execution state of a behavior node
enum BehaviorNodeState {
  /// Node is idle, ready to trigger
  idle,
  /// Node is currently playing audio
  active,
  /// Node is in cooldown after playing
  cooldown,
  /// Node is disabled (manually or by context)
  disabled,
  /// Node has an error (missing audio, broken config)
  error,
}

/// A single behavior node in the tree — the atomic unit of audio behavior
class BehaviorNode {
  /// Unique ID (e.g., 'reel_stop', 'win_big')
  final String id;

  /// Node type from taxonomy
  final BehaviorNodeType nodeType;

  /// Display state label (from §5.2)
  final String state;

  /// Sound group identifier
  final String soundGroup;

  /// Playback mode
  final PlaybackMode playbackMode;

  /// Escalation policy
  final String escalationPolicy;

  /// Orchestration profile
  final String orchestrationProfile;

  /// Emotional weight (0.0-1.0) — contribution to emotional state
  final double emotionalWeight;

  /// Variant configuration
  final VariantConfig variantConfig;

  /// Basic parameters (always visible)
  final BasicParams basicParams;

  /// Advanced parameters (visible in Advanced+ tier)
  final AdvancedParams advancedParams;

  /// Expert parameters (visible in Expert tier)
  final ExpertParams expertParams;

  /// Sound assignments (audio files bound to this node)
  final List<BehaviorSoundAssignment> soundAssignments;

  /// Per-context overrides
  final List<ContextOverride> contextOverrides;

  /// Runtime state (not serialized)
  BehaviorNodeState runtimeState;

  /// Variant selection history for avoid_repeat
  final List<int> _variantHistory;

  BehaviorNode({
    required this.id,
    required this.nodeType,
    String? state,
    String? soundGroup,
    PlaybackMode? playbackMode,
    this.escalationPolicy = 'incremental',
    String? orchestrationProfile,
    this.emotionalWeight = 0.5,
    VariantConfig? variantConfig,
    BasicParams? basicParams,
    AdvancedParams? advancedParams,
    ExpertParams? expertParams,
    List<BehaviorSoundAssignment>? soundAssignments,
    List<ContextOverride>? contextOverrides,
    this.runtimeState = BehaviorNodeState.idle,
  }) : state = state ?? nodeType.displayName,
       soundGroup = soundGroup ?? '${nodeType.nodeId}_sounds',
       playbackMode = playbackMode ?? nodeType.defaultPlaybackMode,
       orchestrationProfile = orchestrationProfile ?? '${nodeType.category.name}_standard',
       variantConfig = variantConfig ?? const VariantConfig(),
       basicParams = basicParams ?? BasicParams(
         priorityClass: nodeType.category.defaultPriority,
         busRoute: nodeType.category.defaultBusRoute,
       ),
       advancedParams = advancedParams ?? const AdvancedParams(),
       expertParams = expertParams ?? const ExpertParams(),
       soundAssignments = soundAssignments ?? [],
       contextOverrides = contextOverrides ?? [],
       _variantHistory = [];

  /// Category shortcut
  BehaviorCategory get category => nodeType.category;

  /// Engine hooks this node listens to
  List<String> get mappedHooks => nodeType.mappedHooks;

  /// Whether this node has any audio assigned
  bool get hasAudio => soundAssignments.isNotEmpty;

  /// Number of assigned variants
  int get variantCount => soundAssignments.length;

  /// Coverage status for the coverage panel
  BehaviorCoverageStatus get coverageStatus {
    if (soundAssignments.isEmpty) return BehaviorCoverageStatus.unbound;
    if (soundAssignments.every((a) => a.autoBound)) return BehaviorCoverageStatus.autoBound;
    if (soundAssignments.any((a) => a.autoBound)) return BehaviorCoverageStatus.mixed;
    return BehaviorCoverageStatus.manualBound;
  }

  /// Get effective params for a given context (with overrides applied)
  BasicParams getEffectiveBasicParams(String? contextId) {
    if (contextId == null) return basicParams;
    final override = contextOverrides.where((o) => o.contextId == contextId).firstOrNull;
    if (override == null) return basicParams;
    return basicParams.copyWith(
      gain: override.gainOverride,
      busRoute: override.busRouteOverride,
    );
  }

  /// Get effective playback mode for a given context
  PlaybackMode getEffectivePlaybackMode(String? contextId) {
    if (contextId == null) return playbackMode;
    final override = contextOverrides.where((o) => o.contextId == contextId).firstOrNull;
    return override?.playbackModeOverride ?? playbackMode;
  }

  /// Whether this node is disabled in a given context
  bool isDisabledInContext(String contextId) {
    return contextOverrides.any((o) => o.contextId == contextId && o.disabled);
  }

  /// Select next variant index based on variant config
  int selectVariant() {
    if (soundAssignments.isEmpty) return -1;
    if (soundAssignments.length == 1) return 0;

    int selected;
    switch (variantConfig.mode) {
      case VariantSelectionMode.sequential:
        selected = _variantHistory.isEmpty ? 0 : (_variantHistory.last + 1) % soundAssignments.length;
      case VariantSelectionMode.roundRobin:
        selected = _variantHistory.isEmpty ? 0 : (_variantHistory.last + 1) % soundAssignments.length;
        // Skip if in avoid_repeat window
        int attempts = 0;
        while (_isInAvoidWindow(selected) && attempts < soundAssignments.length) {
          selected = (selected + 1) % soundAssignments.length;
          attempts++;
        }
      case VariantSelectionMode.random:
        selected = _selectRandomAvoidRepeat();
      case VariantSelectionMode.shuffle:
        selected = _selectShuffleAvoidRepeat();
      case VariantSelectionMode.weighted:
        selected = _selectWeighted();
    }

    _variantHistory.add(selected);
    if (_variantHistory.length > variantConfig.maxVariants * 2) {
      _variantHistory.removeRange(0, _variantHistory.length - variantConfig.maxVariants);
    }
    return selected;
  }

  bool _isInAvoidWindow(int index) {
    if (_variantHistory.length < variantConfig.avoidRepeat) return false;
    final recentWindow = _variantHistory.sublist(_variantHistory.length - variantConfig.avoidRepeat);
    return recentWindow.contains(index);
  }

  int _selectRandomAvoidRepeat() {
    final available = List<int>.generate(soundAssignments.length, (i) => i)
      ..removeWhere((i) => _isInAvoidWindow(i));
    if (available.isEmpty) return 0;
    available.shuffle();
    return available.first;
  }

  int _selectShuffleAvoidRepeat() {
    // Shuffle mode: play all variants before repeating
    final played = _variantHistory.toSet();
    final remaining = List<int>.generate(soundAssignments.length, (i) => i)
      ..removeWhere((i) => played.contains(i));
    if (remaining.isEmpty) {
      _variantHistory.clear();
      return _selectShuffleAvoidRepeat();
    }
    remaining.shuffle();
    return remaining.first;
  }

  int _selectWeighted() {
    final totalWeight = soundAssignments.fold<double>(0, (sum, a) => sum + a.weight);
    if (totalWeight <= 0) return 0;
    var roll = totalWeight * (DateTime.now().microsecondsSinceEpoch % 1000) / 1000.0;
    for (int i = 0; i < soundAssignments.length; i++) {
      roll -= soundAssignments[i].weight;
      if (roll <= 0) return i;
    }
    return soundAssignments.length - 1;
  }

  BehaviorNode copyWith({
    String? id,
    BehaviorNodeType? nodeType,
    String? state,
    String? soundGroup,
    PlaybackMode? playbackMode,
    String? escalationPolicy,
    String? orchestrationProfile,
    double? emotionalWeight,
    VariantConfig? variantConfig,
    BasicParams? basicParams,
    AdvancedParams? advancedParams,
    ExpertParams? expertParams,
    List<BehaviorSoundAssignment>? soundAssignments,
    List<ContextOverride>? contextOverrides,
    BehaviorNodeState? runtimeState,
  }) {
    return BehaviorNode(
      id: id ?? this.id,
      nodeType: nodeType ?? this.nodeType,
      state: state ?? this.state,
      soundGroup: soundGroup ?? this.soundGroup,
      playbackMode: playbackMode ?? this.playbackMode,
      escalationPolicy: escalationPolicy ?? this.escalationPolicy,
      orchestrationProfile: orchestrationProfile ?? this.orchestrationProfile,
      emotionalWeight: emotionalWeight ?? this.emotionalWeight,
      variantConfig: variantConfig ?? this.variantConfig,
      basicParams: basicParams ?? this.basicParams,
      advancedParams: advancedParams ?? this.advancedParams,
      expertParams: expertParams ?? this.expertParams,
      soundAssignments: soundAssignments ?? this.soundAssignments,
      contextOverrides: contextOverrides ?? this.contextOverrides,
      runtimeState: runtimeState ?? this.runtimeState,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'node_type': nodeType.nodeId,
    'state': state,
    'sound_group': soundGroup,
    'playback_mode': playbackMode.name,
    'escalation_policy': escalationPolicy,
    'orchestration_profile': orchestrationProfile,
    'emotional_weight': emotionalWeight,
    'variant_config': variantConfig.toJson(),
    'basic_params': basicParams.toJson(),
    'advanced_params': advancedParams.toJson(),
    'expert_params': expertParams.toJson(),
    'sound_assignments': soundAssignments.map((a) => a.toJson()).toList(),
    'context_overrides': contextOverrides.map((o) => o.toJson()).toList(),
  };

  factory BehaviorNode.fromJson(Map<String, dynamic> json) {
    final nodeType = BehaviorNodeTypeExtension.fromId(json['node_type'] as String)
        ?? BehaviorNodeType.reelStop;
    return BehaviorNode(
      id: json['id'] as String,
      nodeType: nodeType,
      state: json['state'] as String?,
      soundGroup: json['sound_group'] as String?,
      playbackMode: json['playback_mode'] != null
          ? PlaybackMode.values.firstWhere(
              (e) => e.name == json['playback_mode'],
              orElse: () => nodeType.defaultPlaybackMode,
            )
          : null,
      escalationPolicy: json['escalation_policy'] as String? ?? 'incremental',
      orchestrationProfile: json['orchestration_profile'] as String?,
      emotionalWeight: (json['emotional_weight'] as num?)?.toDouble() ?? 0.5,
      variantConfig: json['variant_config'] != null
          ? VariantConfig.fromJson(json['variant_config'] as Map<String, dynamic>)
          : null,
      basicParams: json['basic_params'] != null
          ? BasicParams.fromJson(json['basic_params'] as Map<String, dynamic>)
          : null,
      advancedParams: json['advanced_params'] != null
          ? AdvancedParams.fromJson(json['advanced_params'] as Map<String, dynamic>)
          : null,
      expertParams: json['expert_params'] != null
          ? ExpertParams.fromJson(json['expert_params'] as Map<String, dynamic>)
          : null,
      soundAssignments: (json['sound_assignments'] as List<dynamic>?)
          ?.map((a) => BehaviorSoundAssignment.fromJson(a as Map<String, dynamic>))
          .toList(),
      contextOverrides: (json['context_overrides'] as List<dynamic>?)
          ?.map((o) => ContextOverride.fromJson(o as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Create a default node for a given type
  factory BehaviorNode.defaultForType(BehaviorNodeType type) {
    return BehaviorNode(
      id: type.nodeId,
      nodeType: type,
    );
  }
}

// =============================================================================
// COVERAGE STATUS
// =============================================================================

/// Coverage status for a behavior node
enum BehaviorCoverageStatus {
  /// No audio assigned
  unbound,
  /// All audio was auto-bound by AutoBind engine
  autoBound,
  /// All audio was manually assigned
  manualBound,
  /// Mix of auto-bound and manual
  mixed,
}

extension BehaviorCoverageStatusExtension on BehaviorCoverageStatus {
  String get displayName {
    switch (this) {
      case BehaviorCoverageStatus.unbound: return 'Unbound';
      case BehaviorCoverageStatus.autoBound: return 'Auto';
      case BehaviorCoverageStatus.manualBound: return 'Manual';
      case BehaviorCoverageStatus.mixed: return 'Mixed';
    }
  }

  /// Color for coverage indicators
  int get colorValue {
    switch (this) {
      case BehaviorCoverageStatus.unbound: return 0xFFFF4444;    // Red
      case BehaviorCoverageStatus.autoBound: return 0xFF44BB44;  // Green
      case BehaviorCoverageStatus.manualBound: return 0xFF4488FF; // Blue
      case BehaviorCoverageStatus.mixed: return 0xFFFFAA22;       // Orange
    }
  }
}

// =============================================================================
// BEHAVIOR TREE (Full tree structure)
// =============================================================================

/// The complete behavior tree containing all nodes organized by category
class BehaviorTree {
  /// All behavior nodes, keyed by node ID
  final Map<String, BehaviorNode> _nodes;

  /// Creation timestamp
  final DateTime createdAt;

  /// Last modification timestamp
  DateTime lastModifiedAt;

  BehaviorTree({
    Map<String, BehaviorNode>? nodes,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
  }) : _nodes = nodes ?? {},
       createdAt = createdAt ?? DateTime.now(),
       lastModifiedAt = lastModifiedAt ?? DateTime.now();

  /// Get all nodes
  Map<String, BehaviorNode> get nodes => Map.unmodifiable(_nodes);

  /// Get node by ID
  BehaviorNode? getNode(String id) => _nodes[id];

  /// Get all nodes in a category
  List<BehaviorNode> getNodesByCategory(BehaviorCategory category) {
    return _nodes.values.where((n) => n.category == category).toList();
  }

  /// Get total node count
  int get nodeCount => _nodes.length;

  /// Get bound node count (nodes with audio assigned)
  int get boundNodeCount => _nodes.values.where((n) => n.hasAudio).length;

  /// Overall coverage percentage
  double get coveragePercent {
    if (_nodes.isEmpty) return 0.0;
    return boundNodeCount / nodeCount;
  }

  /// Get nodes grouped by category
  Map<BehaviorCategory, List<BehaviorNode>> get nodesByCategory {
    final result = <BehaviorCategory, List<BehaviorNode>>{};
    for (final cat in BehaviorCategory.values) {
      final catNodes = getNodesByCategory(cat);
      if (catNodes.isNotEmpty) {
        result[cat] = catNodes;
      }
    }
    return result;
  }

  /// Add or update a node
  void setNode(BehaviorNode node) {
    _nodes[node.id] = node;
    lastModifiedAt = DateTime.now();
  }

  /// Remove a node
  void removeNode(String id) {
    _nodes.remove(id);
    lastModifiedAt = DateTime.now();
  }

  /// Clear all nodes
  void clear() {
    _nodes.clear();
    lastModifiedAt = DateTime.now();
  }

  /// Create a default tree with all 22 standard nodes
  factory BehaviorTree.defaultTree() {
    final nodes = <String, BehaviorNode>{};
    for (final type in BehaviorNodeType.values) {
      final node = BehaviorNode.defaultForType(type);
      nodes[node.id] = node;
    }
    return BehaviorTree(nodes: nodes);
  }

  /// Create a tree from a list of node types (subset for templates)
  factory BehaviorTree.fromNodeTypes(List<BehaviorNodeType> types) {
    final nodes = <String, BehaviorNode>{};
    for (final type in types) {
      final node = BehaviorNode.defaultForType(type);
      nodes[node.id] = node;
    }
    return BehaviorTree(nodes: nodes);
  }

  Map<String, dynamic> toJson() => {
    'nodes': _nodes.map((key, node) => MapEntry(key, node.toJson())),
    'created_at': createdAt.toIso8601String(),
    'last_modified_at': lastModifiedAt.toIso8601String(),
  };

  factory BehaviorTree.fromJson(Map<String, dynamic> json) {
    final nodesJson = json['nodes'] as Map<String, dynamic>? ?? {};
    final nodes = nodesJson.map((key, value) =>
      MapEntry(key, BehaviorNode.fromJson(value as Map<String, dynamic>)),
    );
    return BehaviorTree(
      nodes: nodes,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      lastModifiedAt: json['last_modified_at'] != null
          ? DateTime.parse(json['last_modified_at'] as String)
          : null,
    );
  }
}
