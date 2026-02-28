/// AUREXIS™ — Dart data models for the Deterministic Slot Audio Intelligence Engine.

/// The sole output of the AUREXIS Rust engine.
/// All fields are deterministic — identical inputs produce identical outputs.
class AurexisParameterMap {
  // ═══ STEREO FIELD ═══
  final double stereoWidth;
  final double stereoElasticity;
  final double panDrift;
  final double widthVariance;

  // ═══ FREQUENCY ═══
  final double hfAttenuationDb;
  final double harmonicExcitation;
  final double subReinforcementDb;

  // ═══ DYNAMICS ═══
  final double transientSmoothing;
  final double transientSharpness;
  final double energyDensity;

  // ═══ SPACE ═══
  final double reverbSendBias;
  final double reverbTailExtensionMs;
  final double zDepthOffset;
  final double earlyReflectionWeight;

  // ═══ ESCALATION ═══
  final double escalationMultiplier;
  final String escalationCurve;

  // ═══ ATTENTION ═══
  final double attentionX;
  final double attentionY;
  final double attentionWeight;

  // ═══ COLLISION ═══
  final int centerOccupancy;
  final int voicesRedistributed;
  final double duckingBiasDb;

  // ═══ PLATFORM ═══
  final double platformStereoRange;
  final double platformMonoSafety;
  final double platformDepthRange;

  // ═══ FATIGUE ═══
  final double fatigueIndex;
  final double sessionDurationS;
  final double rmsExposureAvgDb;
  final double hfExposureCumulative;
  final double transientDensityPerMin;

  // ═══ SEED ═══
  final int variationSeed;
  final bool isDeterministic;

  const AurexisParameterMap({
    this.stereoWidth = 1.0,
    this.stereoElasticity = 1.0,
    this.panDrift = 0.0,
    this.widthVariance = 0.0,
    this.hfAttenuationDb = 0.0,
    this.harmonicExcitation = 1.0,
    this.subReinforcementDb = 0.0,
    this.transientSmoothing = 0.0,
    this.transientSharpness = 1.0,
    this.energyDensity = 0.5,
    this.reverbSendBias = 0.0,
    this.reverbTailExtensionMs = 0.0,
    this.zDepthOffset = 0.0,
    this.earlyReflectionWeight = 0.0,
    this.escalationMultiplier = 1.0,
    this.escalationCurve = 'linear',
    this.attentionX = 0.0,
    this.attentionY = 0.0,
    this.attentionWeight = 0.0,
    this.centerOccupancy = 0,
    this.voicesRedistributed = 0,
    this.duckingBiasDb = 0.0,
    this.platformStereoRange = 1.0,
    this.platformMonoSafety = 0.0,
    this.platformDepthRange = 1.0,
    this.fatigueIndex = 0.0,
    this.sessionDurationS = 0.0,
    this.rmsExposureAvgDb = -60.0,
    this.hfExposureCumulative = 0.0,
    this.transientDensityPerMin = 0.0,
    this.variationSeed = 0,
    this.isDeterministic = true,
  });

  factory AurexisParameterMap.fromJson(Map<String, dynamic> json) {
    return AurexisParameterMap(
      stereoWidth: (json['stereo_width'] as num?)?.toDouble() ?? 1.0,
      stereoElasticity: (json['stereo_elasticity'] as num?)?.toDouble() ?? 1.0,
      panDrift: (json['pan_drift'] as num?)?.toDouble() ?? 0.0,
      widthVariance: (json['width_variance'] as num?)?.toDouble() ?? 0.0,
      hfAttenuationDb: (json['hf_attenuation_db'] as num?)?.toDouble() ?? 0.0,
      harmonicExcitation: (json['harmonic_excitation'] as num?)?.toDouble() ?? 1.0,
      subReinforcementDb: (json['sub_reinforcement_db'] as num?)?.toDouble() ?? 0.0,
      transientSmoothing: (json['transient_smoothing'] as num?)?.toDouble() ?? 0.0,
      transientSharpness: (json['transient_sharpness'] as num?)?.toDouble() ?? 1.0,
      energyDensity: (json['energy_density'] as num?)?.toDouble() ?? 0.5,
      reverbSendBias: (json['reverb_send_bias'] as num?)?.toDouble() ?? 0.0,
      reverbTailExtensionMs: (json['reverb_tail_extension_ms'] as num?)?.toDouble() ?? 0.0,
      zDepthOffset: (json['z_depth_offset'] as num?)?.toDouble() ?? 0.0,
      earlyReflectionWeight: (json['early_reflection_weight'] as num?)?.toDouble() ?? 0.0,
      escalationMultiplier: (json['escalation_multiplier'] as num?)?.toDouble() ?? 1.0,
      escalationCurve: json['escalation_curve'] as String? ?? 'linear',
      attentionX: (json['attention_x'] as num?)?.toDouble() ?? 0.0,
      attentionY: (json['attention_y'] as num?)?.toDouble() ?? 0.0,
      attentionWeight: (json['attention_weight'] as num?)?.toDouble() ?? 0.0,
      centerOccupancy: (json['center_occupancy'] as num?)?.toInt() ?? 0,
      voicesRedistributed: (json['voices_redistributed'] as num?)?.toInt() ?? 0,
      duckingBiasDb: (json['ducking_bias_db'] as num?)?.toDouble() ?? 0.0,
      platformStereoRange: (json['platform_stereo_range'] as num?)?.toDouble() ?? 1.0,
      platformMonoSafety: (json['platform_mono_safety'] as num?)?.toDouble() ?? 0.0,
      platformDepthRange: (json['platform_depth_range'] as num?)?.toDouble() ?? 1.0,
      fatigueIndex: (json['fatigue_index'] as num?)?.toDouble() ?? 0.0,
      sessionDurationS: (json['session_duration_s'] as num?)?.toDouble() ?? 0.0,
      rmsExposureAvgDb: (json['rms_exposure_avg_db'] as num?)?.toDouble() ?? -60.0,
      hfExposureCumulative: (json['hf_exposure_cumulative'] as num?)?.toDouble() ?? 0.0,
      transientDensityPerMin: (json['transient_density_per_min'] as num?)?.toDouble() ?? 0.0,
      variationSeed: (json['variation_seed'] as num?)?.toInt() ?? 0,
      isDeterministic: json['is_deterministic'] as bool? ?? true,
    );
  }
}

/// AUREXIS platform type.
enum AurexisPlatform {
  desktop(0),
  mobile(1),
  headphones(2),
  cabinet(3);

  const AurexisPlatform(this.id);
  final int id;

  String get label => switch (this) {
    desktop => 'Desktop',
    mobile => 'Mobile',
    headphones => 'Headphones',
    cabinet => 'Cabinet',
  };
}

/// Fatigue level category for UI display.
enum FatigueLevel {
  fresh,    // 0.0 - 0.2
  mild,     // 0.2 - 0.4
  moderate, // 0.4 - 0.6
  high,     // 0.6 - 0.8
  critical; // 0.8 - 1.0

  static FatigueLevel fromIndex(double index) {
    if (index < 0.2) return fresh;
    if (index < 0.4) return mild;
    if (index < 0.6) return moderate;
    if (index < 0.8) return high;
    return critical;
  }

  String get label {
    switch (this) {
      case fresh: return 'Fresh';
      case mild: return 'Mild';
      case moderate: return 'Moderate';
      case high: return 'High';
      case critical: return 'Critical';
    }
  }
}
