// ============================================================================
// rf-fluxmacro — Volatility Profile Generator Step
// ============================================================================
// FM-22: Wraps rf-aurexis volatility profiles + adds slot-specific params.
// ============================================================================

use crate::context::{LogLevel, MacroContext, VolatilityLevel};
use crate::error::FluxMacroError;
use crate::security;
use crate::steps::{MacroStep, StepResult};

pub struct VolatilityProfileStep;

/// Extended volatility profile with slot-specific parameters.
#[derive(Debug, Clone, serde::Serialize)]
pub struct GeneratedVolatilityProfile {
    // Base parameters from volatility level
    pub volatility_index: f32,
    pub volatility_level: String,

    // Energy parameters
    pub stereo_elasticity: (f32, f32),
    pub energy_density: (f32, f32),
    pub escalation_rate: f32,

    // Slot-specific extensions
    pub hit_intensity_scale: (f32, f32),
    pub big_win_thresholds: Vec<f32>,
    pub music_layer_up_shift_ms: u32,
    pub music_layer_down_shift_ms: u32,
    pub anticipation_boost_chance: f32,
    pub max_high_energy_duration_sec: f32,
    pub ducking_ui_during_big_win_db: f32,
    pub transient_aggression: f32,
    pub build_up_curve: String,
    pub cooldown_after_peak_sec: f32,
}

impl MacroStep for VolatilityProfileStep {
    fn name(&self) -> &'static str {
        "volatility.profile.generate"
    }

    fn description(&self) -> &'static str {
        "Generate volatility-aware audio profile with slot-specific parameters"
    }

    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
        if ctx.dry_run {
            return Ok(StepResult::success(format!(
                "Dry-run: would generate {:?} volatility profile",
                ctx.volatility
            )));
        }

        let profile = generate_profile(ctx.volatility, &ctx.mechanics);

        // Write profile
        let profiles_dir = ctx.working_dir.join("Profiles");
        std::fs::create_dir_all(&profiles_dir)
            .map_err(|e| FluxMacroError::DirectoryCreate(profiles_dir.clone(), e))?;

        let filename = format!(
            "{}_volatility.json",
            security::sanitize_filename(&ctx.game_id)
        );
        let path = profiles_dir.join(&filename);
        let json = serde_json::to_string_pretty(&profile)?;
        std::fs::write(&path, &json).map_err(|e| FluxMacroError::FileWrite(path.clone(), e))?;

        ctx.set_intermediate(
            "volatility_profile",
            serde_json::to_value(&profile).unwrap_or(serde_json::Value::Null),
        );

        ctx.log(
            LogLevel::Info,
            "volatility.profile.generate",
            &format!(
                "Generated {:?} profile (index={:.2}, aggression={:.2})",
                ctx.volatility, profile.volatility_index, profile.transient_aggression
            ),
        );

        Ok(StepResult::success(format!(
            "Volatility profile generated: {:?} (index={:.2})",
            ctx.volatility, profile.volatility_index
        ))
        .with_artifact("volatility_profile".to_string(), path)
        .with_metric(
            "volatility_index".to_string(),
            profile.volatility_index as f64,
        ))
    }

    fn estimated_duration_ms(&self) -> u64 {
        500
    }
}

fn generate_profile(
    volatility: VolatilityLevel,
    mechanics: &[crate::context::GameMechanic],
) -> GeneratedVolatilityProfile {
    let base = match volatility {
        VolatilityLevel::Low => GeneratedVolatilityProfile {
            volatility_index: 0.15,
            volatility_level: "low".to_string(),
            stereo_elasticity: (0.3, 0.6),
            energy_density: (0.2, 0.5),
            escalation_rate: 1.0,
            hit_intensity_scale: (0.5, 1.2),
            big_win_thresholds: vec![10.0, 25.0, 50.0],
            music_layer_up_shift_ms: 500,
            music_layer_down_shift_ms: 1000,
            anticipation_boost_chance: 0.0,
            max_high_energy_duration_sec: 15.0,
            ducking_ui_during_big_win_db: -3.0,
            transient_aggression: 0.2,
            build_up_curve: "linear".to_string(),
            cooldown_after_peak_sec: 2.0,
        },
        VolatilityLevel::Medium => GeneratedVolatilityProfile {
            volatility_index: 0.45,
            volatility_level: "medium".to_string(),
            stereo_elasticity: (0.4, 0.75),
            energy_density: (0.3, 0.7),
            escalation_rate: 1.5,
            hit_intensity_scale: (0.7, 1.5),
            big_win_thresholds: vec![15.0, 40.0, 80.0],
            music_layer_up_shift_ms: 1000,
            music_layer_down_shift_ms: 2000,
            anticipation_boost_chance: 0.10,
            max_high_energy_duration_sec: 25.0,
            ducking_ui_during_big_win_db: -4.0,
            transient_aggression: 0.4,
            build_up_curve: "log".to_string(),
            cooldown_after_peak_sec: 3.0,
        },
        VolatilityLevel::High => GeneratedVolatilityProfile {
            volatility_index: 0.725,
            volatility_level: "high".to_string(),
            stereo_elasticity: (0.5, 0.9),
            energy_density: (0.4, 0.85),
            escalation_rate: 2.0,
            hit_intensity_scale: (0.8, 2.0),
            big_win_thresholds: vec![20.0, 50.0, 100.0],
            music_layer_up_shift_ms: 2000,
            music_layer_down_shift_ms: 3000,
            anticipation_boost_chance: 0.20,
            max_high_energy_duration_sec: 40.0,
            ducking_ui_during_big_win_db: -6.0,
            transient_aggression: 0.65,
            build_up_curve: "exp".to_string(),
            cooldown_after_peak_sec: 4.0,
        },
        VolatilityLevel::Extreme => GeneratedVolatilityProfile {
            volatility_index: 0.925,
            volatility_level: "extreme".to_string(),
            stereo_elasticity: (0.6, 1.0),
            energy_density: (0.5, 1.0),
            escalation_rate: 3.0,
            hit_intensity_scale: (1.0, 3.0),
            big_win_thresholds: vec![25.0, 75.0, 150.0],
            music_layer_up_shift_ms: 3000,
            music_layer_down_shift_ms: 5000,
            anticipation_boost_chance: 0.35,
            max_high_energy_duration_sec: 60.0,
            ducking_ui_during_big_win_db: -9.0,
            transient_aggression: 0.85,
            build_up_curve: "s_curve".to_string(),
            cooldown_after_peak_sec: 5.0,
        },
    };

    apply_mechanic_modifiers(base, mechanics)
}

fn apply_mechanic_modifiers(
    mut profile: GeneratedVolatilityProfile,
    mechanics: &[crate::context::GameMechanic],
) -> GeneratedVolatilityProfile {
    use crate::context::GameMechanic;

    for mechanic in mechanics {
        match mechanic {
            GameMechanic::Progressive => {
                profile.music_layer_up_shift_ms += 1000;
                profile.anticipation_boost_chance += 0.10;
                profile.max_high_energy_duration_sec += 10.0;
            }
            GameMechanic::Megaways => {
                profile.transient_aggression += 0.15;
                profile.energy_density.1 = (profile.energy_density.1 + 0.1).min(1.0);
                profile.stereo_elasticity.1 = (profile.stereo_elasticity.1 + 0.1).min(1.0);
            }
            GameMechanic::HoldAndWin => {
                profile.music_layer_up_shift_ms =
                    profile.music_layer_up_shift_ms.saturating_sub(300);
                profile.cooldown_after_peak_sec -= 0.5;
            }
            GameMechanic::Cascades => {
                profile.escalation_rate += 0.5;
                profile.transient_aggression += 0.1;
            }
            GameMechanic::FreeSpins => {
                profile.max_high_energy_duration_sec += 15.0;
            }
            _ => {}
        }
    }

    profile.cooldown_after_peak_sec = profile.cooldown_after_peak_sec.max(1.0);
    profile.transient_aggression = profile.transient_aggression.clamp(0.0, 1.0);
    profile.anticipation_boost_chance = profile.anticipation_boost_chance.clamp(0.0, 0.5);

    profile
}
