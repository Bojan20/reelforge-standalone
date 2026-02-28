use serde::{Deserialize, Serialize};

/// The SOLE output of AUREXIS. All consumers read from this.
/// Every field is deterministic — identical inputs produce identical outputs.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeterministicParameterMap {
    // ═══ STEREO FIELD ═══
    /// Overall stereo width multiplier. 0.0 (mono) — 2.0 (super wide).
    pub stereo_width: f64,
    /// How responsive width is to events. 0.0 — 2.0.
    pub stereo_elasticity: f64,
    /// Micro pan offset. ±0.05 typical.
    pub pan_drift: f64,
    /// Micro width offset. ±0.03 typical.
    pub width_variance: f64,

    // ═══ FREQUENCY ═══
    /// HF shelf attenuation from fatigue. 0 to -12 dB.
    pub hf_attenuation_db: f64,
    /// Harmonic excitation multiplier. 1.0 (neutral) — 2.0 (saturated).
    pub harmonic_excitation: f64,
    /// Sub frequency boost from win emphasis. 0 to +12 dB.
    pub sub_reinforcement_db: f64,

    // ═══ DYNAMICS ═══
    /// Transient smoothing from fatigue. 0.0 (sharp) — 1.0 (smoothed).
    pub transient_smoothing: f64,
    /// Transient emphasis from escalation. 0.5 (soft) — 2.0 (aggressive).
    pub transient_sharpness: f64,
    /// Energy density envelope. 0.0 (sparse) — 1.0 (dense).
    pub energy_density: f64,

    // ═══ SPACE ═══
    /// Reverb send bias. -1.0 (dry) — +1.0 (wet).
    pub reverb_send_bias: f64,
    /// Additional reverb tail length in ms.
    pub reverb_tail_extension_ms: f64,
    /// Front/back Z-depth positioning offset.
    pub z_depth_offset: f64,
    /// Early reflection weight bias. ±0.04 typical.
    pub early_reflection_weight: f64,

    // ═══ ESCALATION ═══
    /// Overall escalation multiplier. 1.0 (neutral) — unbounded.
    pub escalation_multiplier: f64,
    /// Active escalation curve type.
    pub escalation_curve: EscalationCurveType,

    // ═══ ATTENTION ═══
    /// Audio gravity center X. -1.0 (left) — +1.0 (right).
    pub attention_x: f64,
    /// Audio gravity center Y. -1.0 (bottom) — +1.0 (top).
    pub attention_y: f64,
    /// Attention focus weight. 0.0 (dispersed) — 1.0 (focused).
    pub attention_weight: f64,

    // ═══ COLLISION ═══
    /// Number of voices in front/center depth zone.
    pub center_occupancy: u32,
    /// Number of voices that were redistributed.
    pub voices_redistributed: u32,
    /// Auto-duck amount in dB (negative).
    pub ducking_bias_db: f64,

    // ═══ PLATFORM ═══
    /// Stereo range factor. 0.0-1.0 (mobile compressed).
    pub platform_stereo_range: f64,
    /// Mono compatibility safety. 0.0-1.0.
    pub platform_mono_safety: f64,
    /// Depth compression. 0.0-1.0.
    pub platform_depth_range: f64,

    // ═══ FATIGUE ═══
    /// Overall fatigue index. 0.0 (fresh) — 1.0 (fatigued).
    pub fatigue_index: f64,
    /// Total session duration in seconds.
    pub session_duration_s: f64,
    /// Running RMS average in dB.
    pub rms_exposure_avg_db: f64,
    /// Accumulated HF energy (dB·s).
    pub hf_exposure_cumulative: f64,
    /// Transient events per minute.
    pub transient_density_per_min: f64,

    // ═══ ENERGY GOVERNANCE ═══
    /// Per-domain energy caps [Dynamic, Transient, Spatial, Harmonic, Temporal]. Each 0.0–1.0.
    pub energy_caps: [f64; 5],
    /// Overall energy cap (average of domain caps). 0.0–1.0.
    pub energy_overall_cap: f64,
    /// Session Memory factor. 0.7–1.0.
    pub session_memory_sm: f64,
    /// Voice budget: maximum allowed voices at current energy level.
    pub voice_budget_max: u32,
    /// Voice budget ratio (0.5, 0.7, or 0.9).
    pub voice_budget_ratio: f64,

    // ═══ DPM (Dynamic Priority Matrix) ═══
    /// Number of voices retained by DPM.
    pub dpm_retained: u32,
    /// Number of voices attenuated by DPM.
    pub dpm_attenuated: u32,
    /// Number of voices suppressed by DPM.
    pub dpm_suppressed: u32,
    /// Whether JACKPOT_GRAND override is active.
    pub dpm_jackpot_override: bool,

    // ═══ SAMCL (Spectral Allocation) ═══
    /// Spectral Collision Index (0.0-1.0+).
    pub sci_adv: f64,
    /// Number of spectral collisions detected.
    pub spectral_collisions: u32,
    /// Number of slot shifts applied.
    pub spectral_slot_shifts: u32,
    /// Whether aggressive carve mode is active.
    pub spectral_aggressive_carve: bool,

    // ═══ SEED ═══
    /// Current deterministic variation seed.
    pub variation_seed: u64,
    /// Always true in production. False only in debug override.
    pub is_deterministic: bool,
}

impl Default for DeterministicParameterMap {
    fn default() -> Self {
        Self {
            // Stereo
            stereo_width: 1.0,
            stereo_elasticity: 1.0,
            pan_drift: 0.0,
            width_variance: 0.0,
            // Frequency
            hf_attenuation_db: 0.0,
            harmonic_excitation: 1.0,
            sub_reinforcement_db: 0.0,
            // Dynamics
            transient_smoothing: 0.0,
            transient_sharpness: 1.0,
            energy_density: 0.5,
            // Space
            reverb_send_bias: 0.0,
            reverb_tail_extension_ms: 0.0,
            z_depth_offset: 0.0,
            early_reflection_weight: 0.0,
            // Escalation
            escalation_multiplier: 1.0,
            escalation_curve: EscalationCurveType::Linear,
            // Attention
            attention_x: 0.0,
            attention_y: 0.0,
            attention_weight: 0.0,
            // Collision
            center_occupancy: 0,
            voices_redistributed: 0,
            ducking_bias_db: 0.0,
            // Platform
            platform_stereo_range: 1.0,
            platform_mono_safety: 0.0,
            platform_depth_range: 1.0,
            // Fatigue
            fatigue_index: 0.0,
            session_duration_s: 0.0,
            rms_exposure_avg_db: -60.0,
            hf_exposure_cumulative: 0.0,
            transient_density_per_min: 0.0,
            // Energy Governance
            energy_caps: [0.5; 5],
            energy_overall_cap: 0.5,
            session_memory_sm: 1.0,
            voice_budget_max: 40,
            voice_budget_ratio: 0.7,
            // DPM
            dpm_retained: 0,
            dpm_attenuated: 0,
            dpm_suppressed: 0,
            dpm_jackpot_override: false,
            // SAMCL
            sci_adv: 0.0,
            spectral_collisions: 0,
            spectral_slot_shifts: 0,
            spectral_aggressive_carve: false,
            // Seed
            variation_seed: 0,
            is_deterministic: true,
        }
    }
}

impl DeterministicParameterMap {
    /// Get a parameter value by name. Returns None for unknown names.
    pub fn get(&self, name: &str) -> Option<f64> {
        match name {
            "stereo_width" => Some(self.stereo_width),
            "stereo_elasticity" => Some(self.stereo_elasticity),
            "pan_drift" => Some(self.pan_drift),
            "width_variance" => Some(self.width_variance),
            "hf_attenuation_db" => Some(self.hf_attenuation_db),
            "harmonic_excitation" => Some(self.harmonic_excitation),
            "sub_reinforcement_db" => Some(self.sub_reinforcement_db),
            "transient_smoothing" => Some(self.transient_smoothing),
            "transient_sharpness" => Some(self.transient_sharpness),
            "energy_density" => Some(self.energy_density),
            "reverb_send_bias" => Some(self.reverb_send_bias),
            "reverb_tail_extension_ms" => Some(self.reverb_tail_extension_ms),
            "z_depth_offset" => Some(self.z_depth_offset),
            "early_reflection_weight" => Some(self.early_reflection_weight),
            "escalation_multiplier" => Some(self.escalation_multiplier),
            "attention_x" => Some(self.attention_x),
            "attention_y" => Some(self.attention_y),
            "attention_weight" => Some(self.attention_weight),
            "center_occupancy" => Some(self.center_occupancy as f64),
            "voices_redistributed" => Some(self.voices_redistributed as f64),
            "ducking_bias_db" => Some(self.ducking_bias_db),
            "platform_stereo_range" => Some(self.platform_stereo_range),
            "platform_mono_safety" => Some(self.platform_mono_safety),
            "platform_depth_range" => Some(self.platform_depth_range),
            "fatigue_index" => Some(self.fatigue_index),
            "session_duration_s" => Some(self.session_duration_s),
            "rms_exposure_avg_db" => Some(self.rms_exposure_avg_db),
            "hf_exposure_cumulative" => Some(self.hf_exposure_cumulative),
            "transient_density_per_min" => Some(self.transient_density_per_min),
            "variation_seed" => Some(self.variation_seed as f64),
            "energy_overall_cap" => Some(self.energy_overall_cap),
            "session_memory_sm" => Some(self.session_memory_sm),
            "voice_budget_max" => Some(self.voice_budget_max as f64),
            "voice_budget_ratio" => Some(self.voice_budget_ratio),
            "dpm_retained" => Some(self.dpm_retained as f64),
            "dpm_attenuated" => Some(self.dpm_attenuated as f64),
            "dpm_suppressed" => Some(self.dpm_suppressed as f64),
            "sci_adv" => Some(self.sci_adv),
            "spectral_collisions" => Some(self.spectral_collisions as f64),
            "spectral_slot_shifts" => Some(self.spectral_slot_shifts as f64),
            _ => None,
        }
    }

    /// Serialize to JSON string.
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    /// Deserialize from JSON string.
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}

/// Escalation curve shape.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EscalationCurveType {
    Linear,
    Exponential,
    Logarithmic,
    SCurve,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_is_neutral() {
        let map = DeterministicParameterMap::default();
        assert_eq!(map.stereo_width, 1.0);
        assert_eq!(map.hf_attenuation_db, 0.0);
        assert_eq!(map.escalation_multiplier, 1.0);
        assert_eq!(map.fatigue_index, 0.0);
        assert!(map.is_deterministic);
    }

    #[test]
    fn test_json_roundtrip() {
        let mut map = DeterministicParameterMap::default();
        map.stereo_width = 1.5;
        map.fatigue_index = 0.7;
        map.escalation_curve = EscalationCurveType::Exponential;

        let json = map.to_json().unwrap();
        let restored = DeterministicParameterMap::from_json(&json).unwrap();

        assert_eq!(restored.stereo_width, 1.5);
        assert_eq!(restored.fatigue_index, 0.7);
        assert_eq!(restored.escalation_curve, EscalationCurveType::Exponential);
    }

    #[test]
    fn test_get_by_name() {
        let map = DeterministicParameterMap::default();
        assert_eq!(map.get("stereo_width"), Some(1.0));
        assert_eq!(map.get("fatigue_index"), Some(0.0));
        assert_eq!(map.get("nonexistent"), None);
    }
}
