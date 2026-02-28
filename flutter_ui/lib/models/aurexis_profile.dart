import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════════
// AUREXIS™ PROFILE SYSTEM
//
// Profile = complete configuration of ALL AUREXIS intelligence coefficients.
// Profile-driven design: select a profile → engine auto-configures everything.
// Designer tweaks only what they want different.
// ═══════════════════════════════════════════════════════════════════════════════

/// Profile category for grouping in the dropdown.
enum AurexisProfileCategory {
  classic,
  video,
  highVol,
  megaways,
  holdWin,
  jackpot,
  cascade,
  themed,
  platform,
  utility,
  custom;

  String get label => switch (this) {
    classic => 'Classic',
    video => 'Video Slot',
    highVol => 'High Volatility',
    megaways => 'Megaways',
    holdWin => 'Hold & Win',
    jackpot => 'Jackpot',
    cascade => 'Cascade',
    themed => 'Themed',
    platform => 'Platform',
    utility => 'Utility',
    custom => 'Custom',
  };
}

/// Behavior group: Spatial parameters.
class SpatialBehavior {
  /// Stereo field width (0.0=mono, 1.0=full panoramic).
  final double width;

  /// Sound field depth (0.0=flat, 1.0=deep reverb/distance).
  final double depth;

  /// Movement intensity (0.0=static, 1.0=highly dynamic pan drift/motion).
  final double movement;

  const SpatialBehavior({
    this.width = 0.6,
    this.depth = 0.5,
    this.movement = 0.3,
  });

  SpatialBehavior copyWith({double? width, double? depth, double? movement}) =>
      SpatialBehavior(
        width: width ?? this.width,
        depth: depth ?? this.depth,
        movement: movement ?? this.movement,
      );

  Map<String, dynamic> toJson() => {
    'width': width,
    'depth': depth,
    'movement': movement,
  };

  factory SpatialBehavior.fromJson(Map<String, dynamic> json) =>
      SpatialBehavior(
        width: (json['width'] as num?)?.toDouble() ?? 0.6,
        depth: (json['depth'] as num?)?.toDouble() ?? 0.5,
        movement: (json['movement'] as num?)?.toDouble() ?? 0.3,
      );
}

/// Behavior group: Dynamics parameters.
class DynamicsBehavior {
  /// Win escalation aggressiveness (0.0=subtle linear, 1.0=exponential dramatic).
  final double escalation;

  /// Ducking aggressiveness (0.0=gentle, 1.0=deep fast ducking).
  final double ducking;

  /// Fatigue regulation aggressiveness (0.0=minimal, 1.0=aggressive ear protection).
  final double fatigue;

  const DynamicsBehavior({
    this.escalation = 0.5,
    this.ducking = 0.5,
    this.fatigue = 0.4,
  });

  DynamicsBehavior copyWith({
    double? escalation,
    double? ducking,
    double? fatigue,
  }) =>
      DynamicsBehavior(
        escalation: escalation ?? this.escalation,
        ducking: ducking ?? this.ducking,
        fatigue: fatigue ?? this.fatigue,
      );

  Map<String, dynamic> toJson() => {
    'escalation': escalation,
    'ducking': ducking,
    'fatigue': fatigue,
  };

  factory DynamicsBehavior.fromJson(Map<String, dynamic> json) =>
      DynamicsBehavior(
        escalation: (json['escalation'] as num?)?.toDouble() ?? 0.5,
        ducking: (json['ducking'] as num?)?.toDouble() ?? 0.5,
        fatigue: (json['fatigue'] as num?)?.toDouble() ?? 0.4,
      );
}

/// Behavior group: Music reactivity parameters.
class MusicBehavior {
  /// How fast music reacts to gameplay (0.0=slow background, 1.0=instant tracking).
  final double reactivity;

  /// Default energy level bias (0.0=L1 calm, 1.0=L5 intense).
  final double layerBias;

  /// Transition smoothness (0.0=instant jumps, 1.0=phrase-length crossfades).
  final double transition;

  const MusicBehavior({
    this.reactivity = 0.5,
    this.layerBias = 0.4,
    this.transition = 0.6,
  });

  MusicBehavior copyWith({
    double? reactivity,
    double? layerBias,
    double? transition,
  }) =>
      MusicBehavior(
        reactivity: reactivity ?? this.reactivity,
        layerBias: layerBias ?? this.layerBias,
        transition: transition ?? this.transition,
      );

  Map<String, dynamic> toJson() => {
    'reactivity': reactivity,
    'layerBias': layerBias,
    'transition': transition,
  };

  factory MusicBehavior.fromJson(Map<String, dynamic> json) => MusicBehavior(
    reactivity: (json['reactivity'] as num?)?.toDouble() ?? 0.5,
    layerBias: (json['layerBias'] as num?)?.toDouble() ?? 0.4,
    transition: (json['transition'] as num?)?.toDouble() ?? 0.6,
  );
}

/// Behavior group: Micro-variation parameters.
class VariationBehavior {
  /// Pan drift micro-oscillation range (0.0=none, 1.0=full ±0.05).
  final double panDrift;

  /// Width variance micro-oscillation (0.0=none, 1.0=full ±0.03).
  final double widthVar;

  /// Timing variation (0.0=none, 1.0=full offset range).
  final double timingVar;

  const VariationBehavior({
    this.panDrift = 0.3,
    this.widthVar = 0.2,
    this.timingVar = 0.4,
  });

  VariationBehavior copyWith({
    double? panDrift,
    double? widthVar,
    double? timingVar,
  }) =>
      VariationBehavior(
        panDrift: panDrift ?? this.panDrift,
        widthVar: widthVar ?? this.widthVar,
        timingVar: timingVar ?? this.timingVar,
      );

  Map<String, dynamic> toJson() => {
    'panDrift': panDrift,
    'widthVar': widthVar,
    'timingVar': timingVar,
  };

  factory VariationBehavior.fromJson(Map<String, dynamic> json) =>
      VariationBehavior(
        panDrift: (json['panDrift'] as num?)?.toDouble() ?? 0.3,
        widthVar: (json['widthVar'] as num?)?.toDouble() ?? 0.2,
        timingVar: (json['timingVar'] as num?)?.toDouble() ?? 0.4,
      );
}

/// Combined behavior configuration — the designer-facing abstraction.
class AurexisBehaviorConfig {
  final SpatialBehavior spatial;
  final DynamicsBehavior dynamics;
  final MusicBehavior music;
  final VariationBehavior variation;

  const AurexisBehaviorConfig({
    this.spatial = const SpatialBehavior(),
    this.dynamics = const DynamicsBehavior(),
    this.music = const MusicBehavior(),
    this.variation = const VariationBehavior(),
  });

  AurexisBehaviorConfig copyWith({
    SpatialBehavior? spatial,
    DynamicsBehavior? dynamics,
    MusicBehavior? music,
    VariationBehavior? variation,
  }) =>
      AurexisBehaviorConfig(
        spatial: spatial ?? this.spatial,
        dynamics: dynamics ?? this.dynamics,
        music: music ?? this.music,
        variation: variation ?? this.variation,
      );

  Map<String, dynamic> toJson() => {
    'spatial': spatial.toJson(),
    'dynamics': dynamics.toJson(),
    'music': music.toJson(),
    'variation': variation.toJson(),
  };

  factory AurexisBehaviorConfig.fromJson(Map<String, dynamic> json) =>
      AurexisBehaviorConfig(
        spatial: json['spatial'] != null
            ? SpatialBehavior.fromJson(json['spatial'] as Map<String, dynamic>)
            : const SpatialBehavior(),
        dynamics: json['dynamics'] != null
            ? DynamicsBehavior.fromJson(json['dynamics'] as Map<String, dynamic>)
            : const DynamicsBehavior(),
        music: json['music'] != null
            ? MusicBehavior.fromJson(json['music'] as Map<String, dynamic>)
            : const MusicBehavior(),
        variation: json['variation'] != null
            ? VariationBehavior.fromJson(
                json['variation'] as Map<String, dynamic>)
            : const VariationBehavior(),
      );

  /// Scale all behavior parameters by an intensity factor (0.0-1.0).
  /// Values are interpolated between neutral (0.5) and their current setting.
  AurexisBehaviorConfig scaledBy(double intensity) {
    double scale(double value) {
      const neutral = 0.5;
      return neutral + (value - neutral) * intensity;
    }

    return AurexisBehaviorConfig(
      spatial: SpatialBehavior(
        width: scale(spatial.width),
        depth: scale(spatial.depth),
        movement: scale(spatial.movement),
      ),
      dynamics: DynamicsBehavior(
        escalation: scale(dynamics.escalation),
        ducking: scale(dynamics.ducking),
        fatigue: scale(dynamics.fatigue),
      ),
      music: MusicBehavior(
        reactivity: scale(music.reactivity),
        layerBias: scale(music.layerBias),
        transition: scale(music.transition),
      ),
      variation: VariationBehavior(
        panDrift: scale(variation.panDrift),
        widthVar: scale(variation.widthVar),
        timingVar: scale(variation.timingVar),
      ),
    );
  }
}

/// Complete AUREXIS profile — describes behavior + maps to engine config.
class AurexisProfile {
  final String id;
  final String name;
  final String description;
  final AurexisProfileCategory category;

  /// Master intensity (0.0-1.0). Scales all behavior parameters proportionally.
  final double intensity;

  /// Designer-facing behavior parameters (meta-controls).
  final AurexisBehaviorConfig behavior;

  /// Raw engine config JSON. When non-null, this is loaded directly into the
  /// Rust engine via `aurexisLoadConfig()`. Built-in profiles pre-compute this.
  /// Custom profiles store it after the first apply.
  final Map<String, dynamic>? engineConfig;

  /// Whether this is a built-in (read-only) profile.
  final bool builtIn;

  const AurexisProfile({
    required this.id,
    required this.name,
    this.description = '',
    this.category = AurexisProfileCategory.custom,
    this.intensity = 0.5,
    this.behavior = const AurexisBehaviorConfig(),
    this.engineConfig,
    this.builtIn = false,
  });

  AurexisProfile copyWith({
    String? id,
    String? name,
    String? description,
    AurexisProfileCategory? category,
    double? intensity,
    AurexisBehaviorConfig? behavior,
    Map<String, dynamic>? engineConfig,
    bool? builtIn,
  }) =>
      AurexisProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        category: category ?? this.category,
        intensity: intensity ?? this.intensity,
        behavior: behavior ?? this.behavior,
        engineConfig: engineConfig ?? this.engineConfig,
        builtIn: builtIn ?? this.builtIn,
      );

  String toJsonString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'category': category.name,
    'intensity': intensity,
    'behavior': behavior.toJson(),
    if (engineConfig != null) 'engineConfig': engineConfig,
    'builtIn': builtIn,
  };

  factory AurexisProfile.fromJson(Map<String, dynamic> json) => AurexisProfile(
    id: json['id'] as String? ?? 'unknown',
    name: json['name'] as String? ?? 'Unnamed',
    description: json['description'] as String? ?? '',
    category: AurexisProfileCategory.values.firstWhere(
      (c) => c.name == json['category'],
      orElse: () => AurexisProfileCategory.custom,
    ),
    intensity: (json['intensity'] as num?)?.toDouble() ?? 0.5,
    behavior: json['behavior'] != null
        ? AurexisBehaviorConfig.fromJson(
            json['behavior'] as Map<String, dynamic>)
        : const AurexisBehaviorConfig(),
    engineConfig: json['engineConfig'] as Map<String, dynamic>?,
    builtIn: json['builtIn'] as bool? ?? false,
  );

  /// Generate engine config JSON from behavior parameters.
  /// Maps abstract behavior values to concrete engine coefficients.
  Map<String, dynamic> generateEngineConfig() {
    final scaled = behavior.scaledBy(intensity);

    return {
      'volatility': {
        'elasticity_min': 0.1 + scaled.spatial.width * 0.3,
        'elasticity_max': 0.8 + scaled.spatial.width * 1.2,
        'elasticity_curve_exp': 1.0 + scaled.dynamics.escalation * 1.0,
        'energy_density_min': 0.1 + scaled.spatial.depth * 0.15,
        'energy_density_max': 0.6 + scaled.spatial.depth * 0.35,
        'escalation_rate_max': 1.0 + scaled.dynamics.escalation * 2.0,
        'micro_dynamics_max': 0.3 + scaled.spatial.movement * 0.6,
      },
      'rtp': {
        'build_time_max_ms':
            1500.0 + (1.0 - scaled.music.reactivity) * 3000.0,
        'build_time_min_ms': 200.0 + (1.0 - scaled.music.reactivity) * 600.0,
        'hold_time_ms': 400.0 + scaled.music.transition * 800.0,
        'release_time_ms': 600.0 + scaled.music.transition * 1200.0,
        'spike_rate_scale': 1.0 + scaled.dynamics.escalation * 4.0,
        'peak_elasticity_max': 1.0 + scaled.dynamics.escalation * 1.5,
      },
      'fatigue': {
        'rms_threshold_db': -18.0 + (1.0 - scaled.dynamics.fatigue) * 10.0,
        'hf_threshold_db_s': 60.0 + (1.0 - scaled.dynamics.fatigue) * 120.0,
        'transient_threshold_per_min':
            8.0 + (1.0 - scaled.dynamics.fatigue) * 15.0,
        'stereo_time_threshold_min':
            10.0 + (1.0 - scaled.dynamics.fatigue) * 25.0,
        'max_hf_atten_db': -3.0 - scaled.dynamics.fatigue * 6.0,
        'max_transient_smooth': 0.3 + scaled.dynamics.fatigue * 0.5,
        'max_width_narrow': 0.4 + (1.0 - scaled.dynamics.fatigue) * 0.4,
        'rms_window_s': 5.0 + (1.0 - scaled.dynamics.fatigue) * 10.0,
        'hf_band_lower_hz': 6000.0 + (1.0 - scaled.dynamics.fatigue) * 4000.0,
        'transient_detect_mult': 1.5 + (1.0 - scaled.dynamics.fatigue) * 2.0,
      },
      'collision': {
        'max_center_voices': 2,
        'center_zone_width': 0.1 + scaled.spatial.width * 0.1,
        'pan_spread_step': 0.08 + scaled.spatial.width * 0.08,
        'z_displacement_amount': 0.2 + scaled.spatial.depth * 0.2,
        'width_compression': 0.4 + (1.0 - scaled.spatial.width) * 0.3,
        'duck_amount_db': -1.5 - scaled.dynamics.ducking * 3.0,
        'duck_attack_ms': 2.0 + (1.0 - scaled.dynamics.ducking) * 8.0,
        'duck_release_ms': 40.0 + (1.0 - scaled.dynamics.ducking) * 80.0,
      },
      'escalation': {
        'width_exponent': 1.0 + scaled.dynamics.escalation * 1.0,
        'width_max': 1.5 + scaled.dynamics.escalation * 0.5,
        'harmonic_rate': 0.05 + scaled.dynamics.escalation * 0.2,
        'harmonic_max': 1.5 + scaled.dynamics.escalation * 0.5,
        'reverb_ms_per_unit': 80.0 + scaled.spatial.depth * 150.0,
        'reverb_max_ms': 1000.0 + scaled.spatial.depth * 1500.0,
        'sub_db_per_unit': 0.5 + scaled.dynamics.escalation * 2.0,
        'sub_max_db': 6.0 + scaled.dynamics.escalation * 6.0,
        'transient_rate': 0.05 + scaled.dynamics.escalation * 0.1,
        'transient_max': 1.3 + scaled.dynamics.escalation * 0.7,
      },
      'variation': {
        'pan_drift_range': 0.01 + scaled.variation.panDrift * 0.06,
        'width_variance_range': 0.005 + scaled.variation.widthVar * 0.04,
        'harmonic_shift_range': 0.005 + scaled.variation.panDrift * 0.03,
        'reflection_weight_range': 0.01 + scaled.variation.widthVar * 0.05,
        'deterministic': true,
      },
      'platform': {
        'active_platform': 'Desktop',
      },
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUILT-IN PROFILES (12)
// ═══════════════════════════════════════════════════════════════════════════════

/// All built-in AUREXIS profiles. Read-only, always available.
class AurexisBuiltInProfiles {
  AurexisBuiltInProfiles._();

  static const calmClassic = AurexisProfile(
    id: 'calm_classic',
    name: 'Calm Classic',
    description: 'Low volatility, gentle transitions, relaxed stereo field',
    category: AurexisProfileCategory.classic,
    intensity: 0.3,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.4, depth: 0.3, movement: 0.15),
      dynamics: DynamicsBehavior(escalation: 0.2, ducking: 0.3, fatigue: 0.3),
      music: MusicBehavior(reactivity: 0.3, layerBias: 0.2, transition: 0.8),
      variation: VariationBehavior(panDrift: 0.1, widthVar: 0.1, timingVar: 0.2),
    ),
    builtIn: true,
  );

  static const standardVideo = AurexisProfile(
    id: 'standard_video',
    name: 'Standard Video',
    description: 'Balanced parameters for standard video slots',
    category: AurexisProfileCategory.video,
    intensity: 0.5,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.6, depth: 0.5, movement: 0.3),
      dynamics: DynamicsBehavior(escalation: 0.5, ducking: 0.5, fatigue: 0.4),
      music: MusicBehavior(reactivity: 0.5, layerBias: 0.4, transition: 0.6),
      variation: VariationBehavior(panDrift: 0.3, widthVar: 0.2, timingVar: 0.4),
    ),
    builtIn: true,
  );

  static const highVolatilityThriller = AurexisProfile(
    id: 'high_volatility_thriller',
    name: 'High Volatility Thriller',
    description: 'Aggressive escalation, wide stereo, dramatic dynamics',
    category: AurexisProfileCategory.highVol,
    intensity: 0.8,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.85, depth: 0.7, movement: 0.5),
      dynamics: DynamicsBehavior(escalation: 0.8, ducking: 0.6, fatigue: 0.5),
      music: MusicBehavior(reactivity: 0.7, layerBias: 0.6, transition: 0.4),
      variation: VariationBehavior(panDrift: 0.4, widthVar: 0.3, timingVar: 0.5),
    ),
    builtIn: true,
  );

  static const megawaysChaos = AurexisProfile(
    id: 'megaways_chaos',
    name: 'Megaways Chaos',
    description: 'Maximum variation, fast transitions, dense energy',
    category: AurexisProfileCategory.megaways,
    intensity: 0.9,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.9, depth: 0.6, movement: 0.8),
      dynamics: DynamicsBehavior(escalation: 0.85, ducking: 0.7, fatigue: 0.6),
      music: MusicBehavior(reactivity: 0.9, layerBias: 0.7, transition: 0.2),
      variation: VariationBehavior(panDrift: 0.6, widthVar: 0.5, timingVar: 0.7),
    ),
    builtIn: true,
  );

  static const holdWinTension = AurexisProfile(
    id: 'hold_win_tension',
    name: 'Hold & Win Tension',
    description: 'Building suspense, locking focus, gradual escalation',
    category: AurexisProfileCategory.holdWin,
    intensity: 0.7,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.5, depth: 0.8, movement: 0.2),
      dynamics: DynamicsBehavior(escalation: 0.7, ducking: 0.65, fatigue: 0.45),
      music: MusicBehavior(reactivity: 0.4, layerBias: 0.5, transition: 0.7),
      variation: VariationBehavior(panDrift: 0.2, widthVar: 0.15, timingVar: 0.3),
    ),
    builtIn: true,
  );

  static const jackpotHunter = AurexisProfile(
    id: 'jackpot_hunter',
    name: 'Jackpot Hunter',
    description: 'Progressive buildup, epic payoff, maximum width at peak',
    category: AurexisProfileCategory.jackpot,
    intensity: 0.85,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.75, depth: 0.85, movement: 0.4),
      dynamics: DynamicsBehavior(escalation: 0.9, ducking: 0.55, fatigue: 0.5),
      music: MusicBehavior(reactivity: 0.6, layerBias: 0.5, transition: 0.5),
      variation: VariationBehavior(panDrift: 0.3, widthVar: 0.25, timingVar: 0.4),
    ),
    builtIn: true,
  );

  static const cascadeFlow = AurexisProfile(
    id: 'cascade_flow',
    name: 'Cascade Flow',
    description: 'Escalating pitch/width per cascade step, flowing motion',
    category: AurexisProfileCategory.cascade,
    intensity: 0.6,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.7, depth: 0.55, movement: 0.6),
      dynamics: DynamicsBehavior(escalation: 0.65, ducking: 0.5, fatigue: 0.4),
      music: MusicBehavior(reactivity: 0.75, layerBias: 0.45, transition: 0.35),
      variation: VariationBehavior(panDrift: 0.4, widthVar: 0.35, timingVar: 0.5),
    ),
    builtIn: true,
  );

  static const asianPremium = AurexisProfile(
    id: 'asian_premium',
    name: 'Asian Premium',
    description: 'Cultural audio conventions, balanced width, rich reverb',
    category: AurexisProfileCategory.themed,
    intensity: 0.5,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.55, depth: 0.65, movement: 0.25),
      dynamics: DynamicsBehavior(escalation: 0.55, ducking: 0.45, fatigue: 0.35),
      music: MusicBehavior(reactivity: 0.5, layerBias: 0.45, transition: 0.65),
      variation: VariationBehavior(panDrift: 0.2, widthVar: 0.15, timingVar: 0.3),
    ),
    builtIn: true,
  );

  static const mobileOptimized = AurexisProfile(
    id: 'mobile_optimized',
    name: 'Mobile Optimized',
    description: 'Compressed stereo, reduced fatigue, mono-safe',
    category: AurexisProfileCategory.platform,
    intensity: 0.4,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.35, depth: 0.3, movement: 0.15),
      dynamics: DynamicsBehavior(escalation: 0.4, ducking: 0.55, fatigue: 0.6),
      music: MusicBehavior(reactivity: 0.45, layerBias: 0.35, transition: 0.7),
      variation: VariationBehavior(panDrift: 0.1, widthVar: 0.1, timingVar: 0.2),
    ),
    builtIn: true,
  );

  static const headphoneSpatial = AurexisProfile(
    id: 'headphone_spatial',
    name: 'Headphone Spatial',
    description: 'Exaggerated width, enhanced depth, HRTF hints',
    category: AurexisProfileCategory.platform,
    intensity: 0.6,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.9, depth: 0.8, movement: 0.45),
      dynamics: DynamicsBehavior(escalation: 0.5, ducking: 0.4, fatigue: 0.55),
      music: MusicBehavior(reactivity: 0.5, layerBias: 0.4, transition: 0.6),
      variation: VariationBehavior(panDrift: 0.35, widthVar: 0.3, timingVar: 0.4),
    ),
    builtIn: true,
  );

  static const cabinetMonoSafe = AurexisProfile(
    id: 'cabinet_mono_safe',
    name: 'Cabinet Mono-Safe',
    description: 'Mono-compatible, bass managed, minimal stereo',
    category: AurexisProfileCategory.platform,
    intensity: 0.3,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.2, depth: 0.25, movement: 0.1),
      dynamics: DynamicsBehavior(escalation: 0.35, ducking: 0.6, fatigue: 0.5),
      music: MusicBehavior(reactivity: 0.4, layerBias: 0.35, transition: 0.7),
      variation: VariationBehavior(panDrift: 0.05, widthVar: 0.05, timingVar: 0.15),
    ),
    builtIn: true,
  );

  static const silentMode = AurexisProfile(
    id: 'silent_mode',
    name: 'Silent Mode',
    description: 'All intelligence OFF — manual only, neutral parameters',
    category: AurexisProfileCategory.utility,
    intensity: 0.0,
    behavior: AurexisBehaviorConfig(
      spatial: SpatialBehavior(width: 0.5, depth: 0.5, movement: 0.0),
      dynamics: DynamicsBehavior(escalation: 0.0, ducking: 0.0, fatigue: 0.0),
      music: MusicBehavior(reactivity: 0.0, layerBias: 0.5, transition: 0.5),
      variation: VariationBehavior(panDrift: 0.0, widthVar: 0.0, timingVar: 0.0),
    ),
    builtIn: true,
  );

  /// All built-in profiles ordered by intensity.
  static const List<AurexisProfile> all = [
    silentMode,
    calmClassic,
    cabinetMonoSafe,
    mobileOptimized,
    standardVideo,
    asianPremium,
    cascadeFlow,
    headphoneSpatial,
    holdWinTension,
    highVolatilityThriller,
    jackpotHunter,
    megawaysChaos,
  ];

  /// Find a profile by ID.
  static AurexisProfile? findById(String id) {
    for (final profile in all) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  /// Auto-select the best matching profile from GDD import data.
  static AurexisProfile autoSelectFromGdd({
    required String volatility,
    required double rtp,
    String? mechanic,
    List<String>? features,
  }) {
    // Map volatility string to profile category preference
    switch (volatility.toLowerCase()) {
      case 'low':
        return calmClassic;
      case 'medium':
      case 'med':
        return standardVideo;
      case 'high':
        if (mechanic?.toLowerCase() == 'megaways') return megawaysChaos;
        if (features?.contains('cascade') ?? false) return cascadeFlow;
        if (features?.contains('holdAndWin') ?? false) return holdWinTension;
        return highVolatilityThriller;
      case 'extreme':
      case 'very high':
        if (features?.contains('jackpot') ?? false) return jackpotHunter;
        return megawaysChaos;
      default:
        return standardVideo;
    }
  }
}

/// A/B comparison snapshot.
class AurexisProfileSnapshot {
  final AurexisProfile profile;
  final Map<String, dynamic> engineConfig;
  final DateTime timestamp;

  AurexisProfileSnapshot({
    required this.profile,
    required this.engineConfig,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
