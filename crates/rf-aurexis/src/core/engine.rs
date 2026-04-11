use crate::collision::{PanRedistributor, VoiceCollisionResolver};
use crate::core::config::AurexisConfig;
use crate::core::parameter_map::{DeterministicParameterMap, EscalationCurveType};
use crate::core::state::AurexisState;
use crate::energy::EnergyGovernor;
use crate::escalation::WinEscalationEngine;
use crate::geometry::AttentionVectorEngine;
use crate::platform::{PlatformAdapter, PlatformProfile};
use crate::priority::DynamicPriorityMatrix;
use crate::psycho::{PsychoRegulator, SessionFatigueTracker};
use crate::rtp::RtpEmotionalMapper;
use crate::spectral::SpectralAllocator;
use crate::variation::DeterministicVariationEngine;
use crate::volatility::VolatilityTranslator;

/// Main AUREXIS orchestrator.
///
/// Combines all intelligence modules into a single `compute()` call
/// that outputs a `DeterministicParameterMap`.
///
/// **Thread safety**: This struct is NOT `Send`/`Sync` — intended to be
/// owned by a single intelligence thread. The output map is `Send` and
/// can be shared freely.
pub struct AurexisEngine {
    config: AurexisConfig,
    state: AurexisState,

    // ═══ SUB-ENGINES (stateful) ═══
    fatigue_tracker: SessionFatigueTracker,
    collision_resolver: VoiceCollisionResolver,
    attention_engine: AttentionVectorEngine,
    energy_governor: EnergyGovernor,
    priority_matrix: DynamicPriorityMatrix,
    spectral_allocator: SpectralAllocator,

    // ═══ OUTPUT ═══
    output: DeterministicParameterMap,
    /// Monotonic tick counter for seed generation.
    tick_count: u64,
    initialized: bool,
}

impl AurexisEngine {
    /// Create a new AUREXIS engine with default configuration.
    pub fn new() -> Self {
        let config = AurexisConfig::default();
        let fatigue_tracker = SessionFatigueTracker::new(&config.fatigue);
        Self {
            config,
            state: AurexisState::default(),
            fatigue_tracker,
            collision_resolver: VoiceCollisionResolver::new(),
            attention_engine: AttentionVectorEngine::new(),
            energy_governor: EnergyGovernor::new(),
            priority_matrix: DynamicPriorityMatrix::new(),
            spectral_allocator: SpectralAllocator::new(),
            output: DeterministicParameterMap::default(),
            tick_count: 0,
            initialized: false,
        }
    }

    /// Create with a specific configuration.
    pub fn with_config(config: AurexisConfig) -> Self {
        let fatigue_tracker = SessionFatigueTracker::new(&config.fatigue);
        Self {
            config,
            state: AurexisState::default(),
            fatigue_tracker,
            collision_resolver: VoiceCollisionResolver::new(),
            attention_engine: AttentionVectorEngine::new(),
            energy_governor: EnergyGovernor::new(),
            priority_matrix: DynamicPriorityMatrix::new(),
            spectral_allocator: SpectralAllocator::new(),
            output: DeterministicParameterMap::default(),
            tick_count: 0,
            initialized: false,
        }
    }

    /// Initialize the engine. Must be called before `compute()`.
    pub fn initialize(&mut self) {
        self.state.initialized = true;
        self.initialized = true;
        self.tick_count = 0;
        log::info!("AUREXIS: Engine initialized");
    }

    /// Reset session state (fatigue, timing, voices) without clearing config.
    pub fn reset_session(&mut self) {
        self.state.reset_session();
        self.fatigue_tracker.reset();
        self.collision_resolver.clear();
        self.attention_engine.clear();
        self.energy_governor.reset_session();
        self.priority_matrix.reset();
        self.spectral_allocator.reset();
        self.output = DeterministicParameterMap::default();
        self.tick_count = 0;
        log::info!("AUREXIS: Session reset");
    }

    // ═══════════════════════════════════════════════
    // STATE SETTERS
    // ═══════════════════════════════════════════════

    /// Set the volatility index (0.0 = low, 1.0 = extreme).
    pub fn set_volatility(&mut self, index: f64) {
        self.state.volatility_index = index.clamp(0.0, 1.0);
    }

    /// Set the RTP percentage (85.0 - 99.5).
    pub fn set_rtp(&mut self, rtp: f64) {
        self.state.rtp_percent = rtp.clamp(crate::MIN_RTP, crate::MAX_RTP);
    }

    /// Update win data.
    pub fn set_win(&mut self, amount: f64, bet: f64, jackpot_proximity: f64) {
        self.state.update_win(amount, bet, jackpot_proximity);
    }

    /// Update audio metering (called frequently, ~20Hz).
    pub fn set_metering(&mut self, rms_db: f64, hf_db: f64) {
        self.state.current_rms_db = rms_db;
        self.state.current_hf_db = hf_db;
    }

    /// Set variation seed components.
    pub fn set_seed(
        &mut self,
        sprite_id: u64,
        event_time: u64,
        game_state: u64,
        session_index: u64,
    ) {
        self.state.seed_sprite_id = sprite_id;
        self.state.seed_event_time = event_time;
        self.state.seed_game_state = game_state;
        self.state.seed_session_index = session_index;
    }

    /// Register a voice for collision tracking.
    pub fn register_voice(&mut self, voice_id: u32, pan: f32, z_depth: f32, priority: i32) -> bool {
        self.collision_resolver
            .register_voice(voice_id, pan, z_depth, priority)
    }

    /// Unregister a voice.
    pub fn unregister_voice(&mut self, voice_id: u32) -> bool {
        self.collision_resolver.unregister_voice(voice_id)
    }

    /// Register a screen event for attention tracking.
    pub fn register_screen_event(&mut self, event: crate::geometry::ScreenEvent) -> bool {
        self.attention_engine.register_event(event)
    }

    /// Clear all screen events.
    pub fn clear_screen_events(&mut self) {
        self.attention_engine.clear();
    }

    /// Get energy governor reference.
    pub fn energy_governor(&self) -> &EnergyGovernor {
        &self.energy_governor
    }

    /// Get mutable energy governor reference.
    pub fn energy_governor_mut(&mut self) -> &mut EnergyGovernor {
        &mut self.energy_governor
    }

    /// Record a spin result for session memory.
    pub fn record_spin(&mut self, win_multiplier: f64, is_feature: bool, is_jackpot: bool) {
        self.energy_governor
            .record_spin(win_multiplier, is_feature, is_jackpot);
    }

    /// Get DPM reference.
    pub fn priority_matrix(&self) -> &DynamicPriorityMatrix {
        &self.priority_matrix
    }

    /// Get mutable DPM reference.
    pub fn priority_matrix_mut(&mut self) -> &mut DynamicPriorityMatrix {
        &mut self.priority_matrix
    }

    /// Get spectral allocator reference.
    pub fn spectral_allocator(&self) -> &SpectralAllocator {
        &self.spectral_allocator
    }

    /// Get mutable spectral allocator reference.
    pub fn spectral_allocator_mut(&mut self) -> &mut SpectralAllocator {
        &mut self.spectral_allocator
    }

    // ═══════════════════════════════════════════════
    // CONFIG
    // ═══════════════════════════════════════════════

    /// Get current configuration.
    pub fn config(&self) -> &AurexisConfig {
        &self.config
    }

    /// Get mutable configuration.
    pub fn config_mut(&mut self) -> &mut AurexisConfig {
        &mut self.config
    }

    /// Set configuration, reinitializing fatigue tracker if needed.
    pub fn set_config(&mut self, config: AurexisConfig) {
        self.fatigue_tracker = SessionFatigueTracker::new(&config.fatigue);
        self.config = config;
    }

    /// Set a single coefficient by section.key path.
    pub fn set_coefficient(&mut self, section: &str, key: &str, value: f64) -> bool {
        let result = self.config.set_coefficient(section, key, value);
        if result && section == "fatigue" {
            // Reinitialize fatigue tracker if fatigue config changed
            self.fatigue_tracker = SessionFatigueTracker::new(&self.config.fatigue);
        }
        result
    }

    // ═══════════════════════════════════════════════
    // OUTPUT
    // ═══════════════════════════════════════════════

    /// Get the current parameter map (last computed output).
    pub fn output(&self) -> &DeterministicParameterMap {
        &self.output
    }

    /// Get the current state.
    pub fn state(&self) -> &AurexisState {
        &self.state
    }

    /// Whether the engine has been initialized.
    pub fn is_initialized(&self) -> bool {
        self.initialized
    }

    // ═══════════════════════════════════════════════
    // MAIN COMPUTE — THE HEART OF AUREXIS
    // ═══════════════════════════════════════════════

    /// Compute the deterministic parameter map from current state.
    ///
    /// Called every tick (~50ms, 20Hz). This is the single entry point
    /// that orchestrates all intelligence modules.
    ///
    /// Pipeline order:
    /// 1. Volatility → stereo elasticity, energy density, escalation rate
    /// 2. RTP → pacing curve, spike frequency
    /// 3. Fatigue → track, compute index, regulate
    /// 4. Escalation → win magnitude → width, harmonic, reverb, sub, transient
    /// 5. Variation → deterministic micro-offsets
    /// 6. Collision → voice redistribution
    /// 7. Attention → screen event gravity
    /// 8. Platform → device adaptation
    ///
    /// Each stage writes to the output map. Later stages can read
    /// earlier values (fatigue reduces variation, etc).
    pub fn compute(&mut self, elapsed_ms: u64) -> &DeterministicParameterMap {
        self.tick_count += 1;
        self.state.session_elapsed_ms += elapsed_ms;

        let mut map = DeterministicParameterMap::default();

        // ─── STAGE 1: VOLATILITY ───
        let vol_output =
            VolatilityTranslator::compute_all(self.state.volatility_index, &self.config.volatility);
        map.stereo_elasticity = vol_output.stereo_elasticity;
        map.energy_density = vol_output.energy_density;

        // ─── STAGE 2: RTP → PACING ───
        let pacing = RtpEmotionalMapper::pacing_curve(self.state.rtp_percent, &self.config.rtp);
        // Pacing affects escalation rate (stored for escalation stage)
        let escalation_rate = vol_output.escalation_rate;

        // ─── STAGE 3: FATIGUE ───
        self.fatigue_tracker.tick(elapsed_ms, &self.config.fatigue);
        self.fatigue_tracker
            .update_rms(self.state.current_rms_db, &self.config.fatigue);
        self.fatigue_tracker.update_hf(self.state.current_hf_db);
        self.fatigue_tracker
            .update_stereo_width(map.stereo_elasticity);

        let fatigue_index = self.fatigue_tracker.fatigue_index(&self.config.fatigue);
        self.state.fatigue_index = fatigue_index;

        let regulation = PsychoRegulator::compute_all(fatigue_index, &self.config.fatigue);
        map.hf_attenuation_db = regulation.hf_attenuation_db;
        map.transient_smoothing = regulation.transient_smoothing;
        map.fatigue_index = fatigue_index;
        map.session_duration_s = self.fatigue_tracker.session_duration_s();
        map.rms_exposure_avg_db = self.fatigue_tracker.rms_exposure_avg_db();
        map.hf_exposure_cumulative = self.fatigue_tracker.hf_exposure_cumulative();
        map.transient_density_per_min = self.fatigue_tracker.transient_density_per_min();

        // ─── STAGE 4: ESCALATION ───
        let esc_output = WinEscalationEngine::compute(
            self.state.win_multiplier * escalation_rate,
            self.state.jackpot_proximity,
            EscalationCurveType::SCurve,
            &self.config.escalation,
        );
        map.stereo_width = esc_output.width * regulation.width_factor;
        map.harmonic_excitation = esc_output.harmonic_excitation;
        map.reverb_tail_extension_ms = esc_output.reverb_tail_ms;
        map.sub_reinforcement_db = esc_output.sub_reinforcement_db;
        map.transient_sharpness = esc_output.transient_sharpness;
        map.escalation_multiplier = esc_output.multiplier;
        map.escalation_curve = EscalationCurveType::SCurve;

        // ─── STAGE 5: VARIATION ───
        let seed = DeterministicVariationEngine::seed(
            self.state.seed_sprite_id,
            self.state.seed_event_time,
            self.state.seed_game_state,
            self.state.seed_session_index,
        );
        let variation = DeterministicVariationEngine::compute(seed, &self.config.variation);

        // Apply fatigue-based variation reduction
        let var_scale = regulation.variation_scale;
        map.pan_drift = variation.pan_drift * var_scale;
        map.width_variance = variation.width_variance * var_scale;
        map.early_reflection_weight = variation.reflection_weight * var_scale;
        map.variation_seed = seed;
        map.is_deterministic = self.config.variation.deterministic;

        // Harmonic shift modulates harmonic_excitation additively
        map.harmonic_excitation += variation.harmonic_shift * var_scale;

        // ─── STAGE 6: COLLISION ───
        let redistributions =
            PanRedistributor::resolve(&mut self.collision_resolver, &self.config.collision);
        map.center_occupancy = self
            .collision_resolver
            .center_occupancy(self.config.collision.center_zone_width);
        map.voices_redistributed = redistributions.len() as u32;

        // Aggregate ducking bias from all redistributed voices.
        // `.max(1)` on the denominator makes division safe even when the vec is
        // empty, so removing or reordering surrounding guards can never produce NaN.
        let total_duck: f64 = redistributions.iter().map(|r| r.duck_db).sum();
        map.ducking_bias_db = total_duck / redistributions.len().max(1) as f64;

        // ─── STAGE 7: ATTENTION ───
        let attention = self.attention_engine.compute_vector();
        map.attention_x = attention.x;
        map.attention_y = attention.y;
        map.attention_weight = attention.weight;

        // ─── STAGE 8: PLATFORM ───
        let profile = PlatformProfile::for_platform(self.config.platform.active_platform);
        PlatformAdapter::apply(&mut map, &profile);

        // ─── STAGE 9: PACING INTEGRATION ───
        // Pacing curve modulates reverb send bias
        // Faster build time = more reverb bias (heightened anticipation)
        let pacing_factor = 1.0 - (pacing.build_time_ms / self.config.rtp.build_time_max_ms);
        map.reverb_send_bias += pacing_factor * 0.3;
        map.reverb_send_bias = map.reverb_send_bias.clamp(-1.0, 1.0);

        // ─── STAGE 10: ENERGY GOVERNANCE ───
        // Derive emotional intensity per domain from current pipeline state
        let ei = [
            map.energy_density,                                     // Dynamic
            map.transient_sharpness.clamp(0.0, 2.0) / 2.0,          // Transient (normalize)
            map.stereo_width.clamp(0.0, 2.0) / 2.0,                 // Spatial (normalize)
            (map.harmonic_excitation - 1.0).clamp(0.0, 1.0),        // Harmonic (0=neutral)
            (map.transient_density_per_min / 30.0).clamp(0.0, 1.0), // Temporal (normalize)
        ];
        let budget = self.energy_governor.compute(ei);
        map.energy_caps = budget.caps;
        map.energy_overall_cap = budget.overall_cap;
        map.session_memory_sm = self.energy_governor.session_memory().sm();
        let vb = self.energy_governor.voice_budget();
        map.voice_budget_max = vb.max_voices;
        map.voice_budget_ratio = vb.budget_ratio;

        // ─── STAGE 11: DYNAMIC PRIORITY MATRIX ───
        // Feed GEG outputs into DPM
        self.priority_matrix.set_energy_cap(map.energy_overall_cap);
        self.priority_matrix
            .set_voice_budget_max(map.voice_budget_max);
        self.priority_matrix
            .set_profile_index(self.energy_governor.profile() as u8);

        // DPM computes internally when voices are submitted via FFI
        // Here we just sync the last output to the parameter map
        let dpm_out = self.priority_matrix.last_output();
        map.dpm_retained = dpm_out.retained_count;
        map.dpm_attenuated = dpm_out.attenuated_count;
        map.dpm_suppressed = dpm_out.suppressed_count;
        map.dpm_jackpot_override = dpm_out.jackpot_override_active;

        // ─── STAGE 12: SPECTRAL ALLOCATION ───
        // Feed energy cap into spectral allocator
        self.spectral_allocator
            .set_energy_cap(map.energy_overall_cap);

        // SAMCL computes internally when voices are submitted via FFI
        // Here we sync the last output to the parameter map
        let samcl_out = self.spectral_allocator.last_output();
        map.sci_adv = samcl_out.sci_adv;
        map.spectral_collisions = samcl_out.collision_count;
        map.spectral_slot_shifts = samcl_out.slot_shifts;
        map.spectral_aggressive_carve = samcl_out.aggressive_carve_active;

        // Store output
        self.output = map.clone();
        &self.output
    }

    /// Compute and return a cloned parameter map (for cross-thread sharing).
    pub fn compute_cloned(&mut self, elapsed_ms: u64) -> DeterministicParameterMap {
        self.compute(elapsed_ms).clone()
    }
}

impl Default for AurexisEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_engine() {
        let engine = AurexisEngine::new();
        assert!(!engine.is_initialized());
    }

    #[test]
    fn test_initialize() {
        let mut engine = AurexisEngine::new();
        engine.initialize();
        assert!(engine.is_initialized());
    }

    #[test]
    fn test_compute_neutral_output() {
        let mut engine = AurexisEngine::new();
        engine.initialize();
        let map = engine.compute(50);

        // With default state (no win, neutral volatility), output should be near-neutral
        assert!(map.stereo_width >= 0.5 && map.stereo_width <= 2.0);
        assert_eq!(map.sub_reinforcement_db, 0.0); // No win → no sub boost
        assert!(map.fatigue_index < 0.01); // Fresh session
        assert!(map.is_deterministic);
    }

    #[test]
    fn test_compute_determinism() {
        // Two engines with identical state MUST produce identical output
        let mut engine_a = AurexisEngine::new();
        engine_a.initialize();
        engine_a.set_volatility(0.7);
        engine_a.set_rtp(92.0);
        engine_a.set_win(50.0, 1.0, 0.3);
        engine_a.set_seed(42, 1000, 7, 0);
        engine_a.set_metering(-18.0, -24.0);

        let mut engine_b = AurexisEngine::new();
        engine_b.initialize();
        engine_b.set_volatility(0.7);
        engine_b.set_rtp(92.0);
        engine_b.set_win(50.0, 1.0, 0.3);
        engine_b.set_seed(42, 1000, 7, 0);
        engine_b.set_metering(-18.0, -24.0);

        let map_a = engine_a.compute_cloned(50);
        let map_b = engine_b.compute_cloned(50);

        assert_eq!(map_a.stereo_width, map_b.stereo_width);
        assert_eq!(map_a.stereo_elasticity, map_b.stereo_elasticity);
        assert_eq!(map_a.pan_drift, map_b.pan_drift);
        assert_eq!(map_a.harmonic_excitation, map_b.harmonic_excitation);
        assert_eq!(map_a.escalation_multiplier, map_b.escalation_multiplier);
        assert_eq!(map_a.variation_seed, map_b.variation_seed);
        assert_eq!(map_a.fatigue_index, map_b.fatigue_index);
    }

    #[test]
    fn test_win_escalation_increases_params() {
        let mut engine = AurexisEngine::new();
        engine.initialize();
        let neutral = engine.compute_cloned(50);

        engine.set_win(100.0, 1.0, 0.0); // 100x bet
        let escalated = engine.compute_cloned(50);

        assert!(
            escalated.stereo_width > neutral.stereo_width,
            "Win should increase stereo width: neutral={}, escalated={}",
            neutral.stereo_width,
            escalated.stereo_width
        );
        assert!(escalated.harmonic_excitation > neutral.harmonic_excitation);
        assert!(escalated.reverb_tail_extension_ms > neutral.reverb_tail_extension_ms);
        assert!(escalated.sub_reinforcement_db > neutral.sub_reinforcement_db);
    }

    #[test]
    fn test_high_volatility_increases_elasticity() {
        let mut engine = AurexisEngine::new();
        engine.initialize();
        engine.set_volatility(0.1);
        let low = engine.compute_cloned(50);

        engine.set_volatility(0.9);
        let high = engine.compute_cloned(50);

        assert!(
            high.stereo_elasticity > low.stereo_elasticity,
            "High volatility should increase elasticity: low={}, high={}",
            low.stereo_elasticity,
            high.stereo_elasticity
        );
        assert!(high.energy_density > low.energy_density);
    }

    #[test]
    fn test_fatigue_accumulation() {
        let mut engine = AurexisEngine::new();
        engine.initialize();

        // Simulate sustained loud session
        engine.set_metering(-6.0, -3.0);
        for _ in 0..500 {
            engine.compute(50);
        }

        let map = engine.output();
        assert!(
            map.fatigue_index > 0.0,
            "Sustained loud session should accumulate fatigue: {}",
            map.fatigue_index
        );
        assert!(
            map.hf_attenuation_db < 0.0,
            "Fatigue should cause HF attenuation: {}",
            map.hf_attenuation_db
        );
    }

    #[test]
    fn test_collision_detection() {
        let mut engine = AurexisEngine::new();
        engine.initialize();

        // Register 4 voices at center
        for i in 0..4 {
            engine.register_voice(i, 0.0, 0.0, (10 - i) as i32);
        }

        let map = engine.compute_cloned(50);
        assert!(
            map.center_occupancy >= 2,
            "Should detect center occupancy: {}",
            map.center_occupancy
        );
        assert!(
            map.voices_redistributed > 0,
            "Should redistribute excess center voices: {}",
            map.voices_redistributed
        );
    }

    #[test]
    fn test_attention_vector() {
        let mut engine = AurexisEngine::new();
        engine.initialize();

        engine.register_screen_event(crate::geometry::ScreenEvent {
            event_id: 1,
            x: 0.8,
            y: 0.0,
            weight: 1.0,
            priority: 10,
        });

        let map = engine.compute_cloned(50);
        assert!(
            map.attention_x > 0.5,
            "Attention should follow screen event: {}",
            map.attention_x
        );
        assert_eq!(map.attention_weight, 1.0); // Single event = fully focused
    }

    #[test]
    fn test_platform_mobile_compresses() {
        let mut config = AurexisConfig::default();
        config.platform.active_platform = crate::core::config::PlatformType::Mobile;

        let mut engine = AurexisEngine::with_config(config);
        engine.initialize();
        engine.set_win(20.0, 1.0, 0.0);
        let map = engine.compute_cloned(50);

        assert!(
            map.platform_stereo_range < 1.0,
            "Mobile should compress stereo range: {}",
            map.platform_stereo_range
        );
    }

    #[test]
    fn test_reset_session() {
        let mut engine = AurexisEngine::new();
        engine.initialize();

        // Accumulate state
        engine.set_win(50.0, 1.0, 0.5);
        engine.set_metering(-6.0, -3.0);
        for _ in 0..100 {
            engine.compute(50);
        }

        engine.reset_session();
        let map = engine.compute_cloned(50);

        assert!(map.fatigue_index < 0.01, "Reset should clear fatigue");
        assert_eq!(map.session_duration_s, 0.05); // Single tick
    }

    #[test]
    fn test_config_update() {
        let mut engine = AurexisEngine::new();
        engine.initialize();

        assert!(engine.set_coefficient("volatility", "elasticity_max", 3.0));
        assert_eq!(engine.config().volatility.elasticity_max, 3.0);

        assert!(!engine.set_coefficient("nonexistent", "key", 1.0));
    }

    #[test]
    fn test_seed_changes_variation() {
        let mut engine = AurexisEngine::new();
        engine.initialize();

        engine.set_seed(1, 100, 7, 0);
        let map_a = engine.compute_cloned(50);

        engine.set_seed(2, 100, 7, 0);
        let map_b = engine.compute_cloned(50);

        // Different seeds should produce different pan_drift
        assert_ne!(
            map_a.pan_drift, map_b.pan_drift,
            "Different seeds should produce different variation"
        );
    }
}
