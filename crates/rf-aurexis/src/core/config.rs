use serde::{Deserialize, Serialize};

/// All tunable AUREXIS coefficients. Loaded from profile or set manually.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AurexisConfig {
    // ═══ VOLATILITY ═══
    pub volatility: VolatilityConfig,

    // ═══ RTP ═══
    pub rtp: RtpConfig,

    // ═══ FATIGUE ═══
    pub fatigue: FatigueConfig,

    // ═══ COLLISION ═══
    pub collision: CollisionConfig,

    // ═══ ESCALATION ═══
    pub escalation: EscalationConfig,

    // ═══ VARIATION ═══
    pub variation: VariationConfig,

    // ═══ PLATFORM ═══
    pub platform: PlatformConfig,

    // ═══ ENERGY GOVERNANCE ═══
    pub energy: EnergyConfig,
}

impl Default for AurexisConfig {
    fn default() -> Self {
        Self {
            volatility: VolatilityConfig::default(),
            rtp: RtpConfig::default(),
            fatigue: FatigueConfig::default(),
            collision: CollisionConfig::default(),
            escalation: EscalationConfig::default(),
            variation: VariationConfig::default(),
            platform: PlatformConfig::default(),
            energy: EnergyConfig::default(),
        }
    }
}

impl AurexisConfig {
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }

    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    /// Set a single coefficient by section.key path.
    pub fn set_coefficient(&mut self, section: &str, key: &str, value: f64) -> bool {
        match section {
            "volatility" => self.volatility.set(key, value),
            "rtp" => self.rtp.set(key, value),
            "fatigue" => self.fatigue.set(key, value),
            "collision" => self.collision.set(key, value),
            "escalation" => self.escalation.set(key, value),
            "variation" => self.variation.set(key, value),
            "energy" => self.energy.set(key, value),
            _ => false,
        }
    }
}

// ═══════════════════════════════════════════════
// SUB-CONFIGS
// ═══════════════════════════════════════════════

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolatilityConfig {
    /// Elasticity range minimum (at volatility=0).
    pub elasticity_min: f64,
    /// Elasticity range maximum (at volatility=1).
    pub elasticity_max: f64,
    /// Exponent for elasticity curve (1.0=linear, 1.5=aggressive, 0.5=gentle).
    pub elasticity_curve_exp: f64,
    /// Energy density floor.
    pub energy_density_min: f64,
    /// Energy density ceiling.
    pub energy_density_max: f64,
    /// Escalation rate multiplier at max volatility.
    pub escalation_rate_max: f64,
    /// Micro dynamics intensity at max volatility.
    pub micro_dynamics_max: f64,
}

impl Default for VolatilityConfig {
    fn default() -> Self {
        Self {
            elasticity_min: 0.3,
            elasticity_max: 1.8,
            elasticity_curve_exp: 1.5,
            energy_density_min: 0.2,
            energy_density_max: 0.95,
            escalation_rate_max: 2.0,
            micro_dynamics_max: 0.8,
        }
    }
}

impl VolatilityConfig {
    fn set(&mut self, key: &str, value: f64) -> bool {
        match key {
            "elasticity_min" => { self.elasticity_min = value; true }
            "elasticity_max" => { self.elasticity_max = value; true }
            "elasticity_curve_exp" => { self.elasticity_curve_exp = value; true }
            "energy_density_min" => { self.energy_density_min = value; true }
            "energy_density_max" => { self.energy_density_max = value; true }
            "escalation_rate_max" => { self.escalation_rate_max = value; true }
            "micro_dynamics_max" => { self.micro_dynamics_max = value; true }
            _ => false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RtpConfig {
    /// Build time at RTP=99% (slowest, ms).
    pub build_time_max_ms: f64,
    /// Build time at RTP=85% (fastest, ms).
    pub build_time_min_ms: f64,
    /// Hold time at peak (ms).
    pub hold_time_ms: f64,
    /// Release time (ms).
    pub release_time_ms: f64,
    /// Spike rate multiplier at low RTP.
    pub spike_rate_scale: f64,
    /// Peak elasticity at low RTP.
    pub peak_elasticity_max: f64,
}

impl Default for RtpConfig {
    fn default() -> Self {
        Self {
            build_time_max_ms: 3000.0,
            build_time_min_ms: 500.0,
            hold_time_ms: 800.0,
            release_time_ms: 1200.0,
            spike_rate_scale: 3.0,
            peak_elasticity_max: 1.8,
        }
    }
}

impl RtpConfig {
    fn set(&mut self, key: &str, value: f64) -> bool {
        match key {
            "build_time_max_ms" => { self.build_time_max_ms = value; true }
            "build_time_min_ms" => { self.build_time_min_ms = value; true }
            "hold_time_ms" => { self.hold_time_ms = value; true }
            "release_time_ms" => { self.release_time_ms = value; true }
            "spike_rate_scale" => { self.spike_rate_scale = value; true }
            "peak_elasticity_max" => { self.peak_elasticity_max = value; true }
            _ => false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FatigueConfig {
    /// RMS average threshold before regulation starts (dB).
    pub rms_threshold_db: f64,
    /// HF cumulative energy threshold (dB·s).
    pub hf_threshold_db_s: f64,
    /// Transient density threshold (events/minute).
    pub transient_threshold_per_min: f64,
    /// Stereo time-on threshold (minutes).
    pub stereo_time_threshold_min: f64,
    /// Maximum HF attenuation applied (dB, negative).
    pub max_hf_atten_db: f64,
    /// Maximum transient smoothing factor (0-1).
    pub max_transient_smooth: f64,
    /// Maximum width narrowing factor (0-1, lower = narrower).
    pub max_width_narrow: f64,
    /// RMS tracking window (seconds, exponential).
    pub rms_window_s: f64,
    /// HF frequency band lower bound (Hz).
    pub hf_band_lower_hz: f64,
    /// Transient detection threshold (multiple of RMS envelope).
    pub transient_detect_mult: f64,
}

impl Default for FatigueConfig {
    fn default() -> Self {
        Self {
            rms_threshold_db: -12.0,
            hf_threshold_db_s: 120.0,
            transient_threshold_per_min: 15.0,
            stereo_time_threshold_min: 20.0,
            max_hf_atten_db: -6.0,
            max_transient_smooth: 0.7,
            max_width_narrow: 0.6,
            rms_window_s: 10.0,
            hf_band_lower_hz: 8000.0,
            transient_detect_mult: 2.5,
        }
    }
}

impl FatigueConfig {
    fn set(&mut self, key: &str, value: f64) -> bool {
        match key {
            "rms_threshold_db" => { self.rms_threshold_db = value; true }
            "hf_threshold_db_s" => { self.hf_threshold_db_s = value; true }
            "transient_threshold_per_min" => { self.transient_threshold_per_min = value; true }
            "stereo_time_threshold_min" => { self.stereo_time_threshold_min = value; true }
            "max_hf_atten_db" => { self.max_hf_atten_db = value; true }
            "max_transient_smooth" => { self.max_transient_smooth = value; true }
            "max_width_narrow" => { self.max_width_narrow = value; true }
            "rms_window_s" => { self.rms_window_s = value; true }
            "hf_band_lower_hz" => { self.hf_band_lower_hz = value; true }
            "transient_detect_mult" => { self.transient_detect_mult = value; true }
            _ => false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollisionConfig {
    /// Maximum voices allowed in front/center zone before redistribution.
    pub max_center_voices: u32,
    /// Center zone pan width (±this value counts as "center").
    pub center_zone_width: f64,
    /// Pan spread amount when redistributing (per voice step).
    pub pan_spread_step: f64,
    /// Z-depth displacement for pushed-back voices.
    pub z_displacement_amount: f64,
    /// Width compression factor for background voices.
    pub width_compression: f64,
    /// Auto-duck amount (dB) for pushed voices.
    pub duck_amount_db: f64,
    /// Duck attack time (ms).
    pub duck_attack_ms: f64,
    /// Duck release time (ms).
    pub duck_release_ms: f64,
}

impl Default for CollisionConfig {
    fn default() -> Self {
        Self {
            max_center_voices: 2,
            center_zone_width: 0.15,
            pan_spread_step: 0.12,
            z_displacement_amount: 0.3,
            width_compression: 0.6,
            duck_amount_db: -3.0,
            duck_attack_ms: 5.0,
            duck_release_ms: 80.0,
        }
    }
}

impl CollisionConfig {
    fn set(&mut self, key: &str, value: f64) -> bool {
        match key {
            "max_center_voices" => { self.max_center_voices = value as u32; true }
            "center_zone_width" => { self.center_zone_width = value; true }
            "pan_spread_step" => { self.pan_spread_step = value; true }
            "z_displacement_amount" => { self.z_displacement_amount = value; true }
            "width_compression" => { self.width_compression = value; true }
            "duck_amount_db" => { self.duck_amount_db = value; true }
            "duck_attack_ms" => { self.duck_attack_ms = value; true }
            "duck_release_ms" => { self.duck_release_ms = value; true }
            _ => false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscalationConfig {
    /// Width growth exponent (1.0=linear, 2.0=quadratic).
    pub width_exponent: f64,
    /// Maximum width multiplier (saturation limit).
    pub width_max: f64,
    /// Harmonic excitation growth rate.
    pub harmonic_rate: f64,
    /// Maximum harmonic excitation.
    pub harmonic_max: f64,
    /// Reverb tail extension per escalation unit (ms).
    pub reverb_ms_per_unit: f64,
    /// Maximum reverb tail extension (ms).
    pub reverb_max_ms: f64,
    /// Sub reinforcement per escalation unit (dB).
    pub sub_db_per_unit: f64,
    /// Maximum sub reinforcement (dB).
    pub sub_max_db: f64,
    /// Transient sharpness growth rate.
    pub transient_rate: f64,
    /// Maximum transient sharpness.
    pub transient_max: f64,
}

impl Default for EscalationConfig {
    fn default() -> Self {
        Self {
            width_exponent: 1.5,
            width_max: 2.0,
            harmonic_rate: 0.15,
            harmonic_max: 2.0,
            reverb_ms_per_unit: 150.0,
            reverb_max_ms: 2000.0,
            sub_db_per_unit: 1.5,
            sub_max_db: 12.0,
            transient_rate: 0.1,
            transient_max: 2.0,
        }
    }
}

impl EscalationConfig {
    fn set(&mut self, key: &str, value: f64) -> bool {
        match key {
            "width_exponent" => { self.width_exponent = value; true }
            "width_max" => { self.width_max = value; true }
            "harmonic_rate" => { self.harmonic_rate = value; true }
            "harmonic_max" => { self.harmonic_max = value; true }
            "reverb_ms_per_unit" => { self.reverb_ms_per_unit = value; true }
            "reverb_max_ms" => { self.reverb_max_ms = value; true }
            "sub_db_per_unit" => { self.sub_db_per_unit = value; true }
            "sub_max_db" => { self.sub_max_db = value; true }
            "transient_rate" => { self.transient_rate = value; true }
            "transient_max" => { self.transient_max = value; true }
            _ => false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VariationConfig {
    /// Maximum pan drift range (±).
    pub pan_drift_range: f64,
    /// Maximum width variance range (±).
    pub width_variance_range: f64,
    /// Maximum harmonic shift range (±).
    pub harmonic_shift_range: f64,
    /// Maximum early reflection weight range (±).
    pub reflection_weight_range: f64,
    /// Enable deterministic mode (always true in production).
    pub deterministic: bool,
}

impl Default for VariationConfig {
    fn default() -> Self {
        Self {
            pan_drift_range: 0.05,
            width_variance_range: 0.03,
            harmonic_shift_range: 0.02,
            reflection_weight_range: 0.04,
            deterministic: true,
        }
    }
}

impl VariationConfig {
    fn set(&mut self, key: &str, value: f64) -> bool {
        match key {
            "pan_drift_range" => { self.pan_drift_range = value; true }
            "width_variance_range" => { self.width_variance_range = value; true }
            "harmonic_shift_range" => { self.harmonic_shift_range = value; true }
            "reflection_weight_range" => { self.reflection_weight_range = value; true }
            _ => false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlatformConfig {
    /// Active platform identifier.
    pub active_platform: PlatformType,
}

impl Default for PlatformConfig {
    fn default() -> Self {
        Self {
            active_platform: PlatformType::Desktop,
        }
    }
}

/// Supported playback platforms.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlatformType {
    Desktop,
    Mobile,
    Headphones,
    Cabinet,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnergyConfig {
    /// Default slot profile index (0-8 matching SlotProfile enum order).
    pub default_profile: u8,
    /// Loss streak threshold before SM starts dropping.
    pub loss_streak_threshold: u32,
    /// Maximum SM drop from loss streak.
    pub loss_streak_max_drop: f64,
    /// Feature storm window size (spins).
    pub feature_storm_window: u32,
    /// Feature count threshold for storm activation.
    pub feature_storm_threshold: u32,
    /// Jackpot compression duration (spins).
    pub jackpot_compression_spins: u32,
}

impl Default for EnergyConfig {
    fn default() -> Self {
        Self {
            default_profile: 1, // MediumVolatility
            loss_streak_threshold: 5,
            loss_streak_max_drop: 0.15,
            feature_storm_window: 20,
            feature_storm_threshold: 3,
            jackpot_compression_spins: 30,
        }
    }
}

impl EnergyConfig {
    fn set(&mut self, key: &str, value: f64) -> bool {
        match key {
            "default_profile" => { self.default_profile = value as u8; true }
            "loss_streak_threshold" => { self.loss_streak_threshold = value as u32; true }
            "loss_streak_max_drop" => { self.loss_streak_max_drop = value; true }
            "feature_storm_window" => { self.feature_storm_window = value as u32; true }
            "feature_storm_threshold" => { self.feature_storm_threshold = value as u32; true }
            "jackpot_compression_spins" => { self.jackpot_compression_spins = value as u32; true }
            _ => false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_json_roundtrip() {
        let config = AurexisConfig::default();
        let json = config.to_json().unwrap();
        let restored = AurexisConfig::from_json(&json).unwrap();
        assert_eq!(restored.volatility.elasticity_min, 0.3);
        assert_eq!(restored.fatigue.rms_threshold_db, -12.0);
    }

    #[test]
    fn test_set_coefficient() {
        let mut config = AurexisConfig::default();
        assert!(config.set_coefficient("volatility", "elasticity_max", 2.5));
        assert_eq!(config.volatility.elasticity_max, 2.5);
        assert!(!config.set_coefficient("nonexistent", "key", 1.0));
    }
}
