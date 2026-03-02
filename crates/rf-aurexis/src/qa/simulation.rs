use crate::core::config::AurexisConfig;
use crate::core::engine::AurexisEngine;
use crate::core::parameter_map::DeterministicParameterMap;

/// Simulates a complete AUREXIS session with scripted inputs.
pub struct VolatilitySimulator {
    config: AurexisConfig,
    /// Simulation steps: (elapsed_ms, volatility, rtp, win_mult, jackpot).
    steps: Vec<SimulationStep>,
}

/// A single simulation step.
#[derive(Debug, Clone)]
pub struct SimulationStep {
    pub elapsed_ms: u64,
    pub volatility: f64,
    pub rtp: f64,
    pub win_multiplier: f64,
    pub jackpot_proximity: f64,
    pub rms_db: f64,
    pub hf_db: f64,
}

impl Default for SimulationStep {
    fn default() -> Self {
        Self {
            elapsed_ms: 50,
            volatility: 0.5,
            rtp: 96.0,
            win_multiplier: 0.0,
            jackpot_proximity: 0.0,
            rms_db: -24.0,
            hf_db: -30.0,
        }
    }
}

/// Results from a complete simulation run.
#[derive(Debug, Clone)]
pub struct SimulationResult {
    pub outputs: Vec<DeterministicParameterMap>,
    pub peak_fatigue: f64,
    pub peak_width: f64,
    pub peak_escalation: f64,
    pub total_duration_s: f64,
}

impl VolatilitySimulator {
    pub fn new(config: AurexisConfig) -> Self {
        Self {
            config,
            steps: Vec::new(),
        }
    }

    /// Add a simulation step.
    pub fn add_step(&mut self, step: SimulationStep) {
        self.steps.push(step);
    }

    /// Generate N steps with constant parameters.
    pub fn add_constant_steps(&mut self, count: usize, step: SimulationStep) {
        for _ in 0..count {
            self.steps.push(step.clone());
        }
    }

    /// Run the simulation and return all output maps.
    pub fn run(&self) -> SimulationResult {
        let mut engine = AurexisEngine::with_config(self.config.clone());
        engine.initialize();
        engine.set_seed(0, 0, 0, 0);

        let mut outputs = Vec::with_capacity(self.steps.len());
        let mut peak_fatigue = 0.0_f64;
        let mut peak_width = 0.0_f64;
        let mut peak_escalation = 0.0_f64;

        for step in &self.steps {
            engine.set_volatility(step.volatility);
            engine.set_rtp(step.rtp);
            engine.set_win(step.win_multiplier, 1.0, step.jackpot_proximity);
            engine.set_metering(step.rms_db, step.hf_db);

            let map = engine.compute_cloned(step.elapsed_ms);
            peak_fatigue = peak_fatigue.max(map.fatigue_index);
            peak_width = peak_width.max(map.stereo_width);
            peak_escalation = peak_escalation.max(map.escalation_multiplier);
            outputs.push(map);
        }

        let total_duration_s = outputs.last().map(|m| m.session_duration_s).unwrap_or(0.0);

        SimulationResult {
            outputs,
            peak_fatigue,
            peak_width,
            peak_escalation,
            total_duration_s,
        }
    }

    /// Get step count.
    pub fn step_count(&self) -> usize {
        self.steps.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_basic_simulation() {
        let mut sim = VolatilitySimulator::new(AurexisConfig::default());
        sim.add_constant_steps(100, SimulationStep::default());

        let result = sim.run();
        assert_eq!(result.outputs.len(), 100);
        assert!(result.total_duration_s > 4.0); // 100 × 50ms = 5s
    }

    #[test]
    fn test_escalation_during_win() {
        let mut sim = VolatilitySimulator::new(AurexisConfig::default());

        // 50 ticks neutral, then 50 ticks with big win
        sim.add_constant_steps(50, SimulationStep::default());
        sim.add_constant_steps(
            50,
            SimulationStep {
                win_multiplier: 100.0,
                ..Default::default()
            },
        );

        let result = sim.run();
        assert!(result.peak_escalation > 1.0, "Win should cause escalation");
        assert!(result.peak_width > 1.0, "Win should increase width");
    }
}
