//! Immune System — anomaly tracking, antibody counts, and escalation.
//!
//! Like a biological immune system, this module:
//! - Tracks anomalies by category (antibody memory)
//! - Escalates response severity on repeated anomalies
//! - Decays counters over time (forgiveness / healing)
//! - Remembers "resolved" anomalies for faster future response
//!
//! Integration with the autonomic system:
//! - First occurrence → log + record
//! - Repeated → escalated autonomic command
//! - Chronic → aggressive response + alert

use crate::autonomic::{AutonomicCommand, CommandAction, CommandPriority};
use crate::signal::SignalOrigin;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{Duration, Instant};

/// How quickly antibody counts decay (per second).
const DECAY_RATE: f64 = 0.05;

/// Threshold for escalation levels.
const ESCALATION_THRESHOLDS: [u32; 4] = [1, 3, 7, 15];

/// An antibody — tracks a specific type of anomaly.
#[derive(Debug, Clone)]
pub struct Antibody {
    /// Category (e.g., "audio.underrun", "audio.clipping").
    pub category: String,
    /// How many times this anomaly has been observed (raw count).
    pub raw_count: u32,
    /// Effective count (decays over time).
    pub effective_count: f64,
    /// Maximum severity ever observed.
    pub max_severity: f32,
    /// Last time this anomaly was observed.
    pub last_seen: Instant,
    /// First time this anomaly was observed.
    pub first_seen: Instant,
    /// Current escalation level (0 = normal, 1 = elevated, 2 = high, 3 = critical).
    pub escalation_level: u8,
    /// Has this been resolved at least once before? (immune memory)
    pub previously_resolved: bool,
}

impl Antibody {
    fn new(category: &str, severity: f32) -> Self {
        let now = Instant::now();
        Self {
            category: category.to_string(),
            raw_count: 1,
            effective_count: 1.0,
            max_severity: severity,
            last_seen: now,
            first_seen: now,
            escalation_level: 0,
            previously_resolved: false,
        }
    }

    /// Record another occurrence.
    fn observe(&mut self, severity: f32) {
        self.raw_count += 1;
        self.effective_count += 1.0;
        if severity > self.max_severity {
            self.max_severity = severity;
        }
        self.last_seen = Instant::now();

        // Update escalation level
        for (level, &threshold) in ESCALATION_THRESHOLDS.iter().enumerate() {
            if self.raw_count >= threshold {
                self.escalation_level = level as u8;
            }
        }
    }

    /// Decay effective count based on time elapsed.
    fn decay(&mut self, elapsed_secs: f64) {
        self.effective_count *= (-DECAY_RATE * elapsed_secs).exp();
        if self.effective_count < 0.01 {
            self.effective_count = 0.0;
        }
    }

    /// Is this anomaly chronic? (high escalation + still active)
    pub fn is_chronic(&self) -> bool {
        self.escalation_level >= 3 && self.effective_count > 2.0
    }

    /// Is this anomaly active? (seen recently, non-zero effective count)
    pub fn is_active(&self) -> bool {
        self.effective_count > 0.1
    }

    /// Time since last observed.
    pub fn age(&self) -> Duration {
        self.last_seen.elapsed()
    }

    /// Mark as resolved (immune memory).
    pub fn resolve(&mut self) {
        self.previously_resolved = true;
        self.effective_count = 0.0;
        self.escalation_level = 0;
    }
}

/// The immune system — tracks all anomalies and determines escalated responses.
pub struct ImmuneSystem {
    /// Antibody registry — keyed by anomaly category.
    antibodies: HashMap<String, Antibody>,
    /// Last decay tick.
    last_decay: Instant,
    /// Total anomalies recorded.
    pub total_anomalies: u64,
    /// Total escalations triggered.
    pub total_escalations: u64,
}

impl ImmuneSystem {
    pub fn new() -> Self {
        Self {
            antibodies: HashMap::new(),
            last_decay: Instant::now(),
            total_anomalies: 0,
            total_escalations: 0,
        }
    }

    /// Record an anomaly. Returns an escalated command if the immune system
    /// determines the situation warrants autonomic intervention.
    pub fn record_anomaly(
        &mut self,
        category: &str,
        severity: f32,
    ) -> Option<AutonomicCommand> {
        self.total_anomalies += 1;

        let is_new = !self.antibodies.contains_key(category);

        let antibody = self
            .antibodies
            .entry(category.to_string())
            .or_insert_with(|| Antibody::new(category, severity));

        if is_new {
            // First occurrence — no escalation
            return None;
        }

        // Existing antibody — observe new occurrence
        let old_level = antibody.escalation_level;
        antibody.observe(severity);

        if antibody.escalation_level > old_level {
            self.total_escalations += 1;
            let cat = antibody.category.clone();
            let esc_level = antibody.escalation_level;
            let raw_count = antibody.raw_count;
            return self.generate_escalation_command_from(&cat, esc_level, raw_count);
        }

        None
    }

    /// Generate an autonomic command based on escalation (uses cloned values).
    fn generate_escalation_command_from(
        &self,
        category: &str,
        escalation_level: u8,
        raw_count: u32,
    ) -> Option<AutonomicCommand> {
        if category.starts_with("audio.underrun") {
            Some(match escalation_level {
                1 => AutonomicCommand::new(
                    SignalOrigin::AudioEngine,
                    CommandAction::AdjustBufferSize { target_samples: 512 },
                    format!("Repeated underruns ({}x) — increasing buffer", raw_count),
                    CommandPriority::Normal,
                ),
                2 => AutonomicCommand::new(
                    SignalOrigin::AudioEngine,
                    CommandAction::ReduceQuality { level: 0.3 },
                    format!("Chronic underruns ({}x) — reducing quality", raw_count),
                    CommandPriority::High,
                ),
                _ => AutonomicCommand::new(
                    SignalOrigin::AudioEngine,
                    CommandAction::ThrottleProcessing { factor: 0.5 },
                    format!("Critical underruns ({}x) — throttling processing", raw_count),
                    CommandPriority::Emergency,
                ),
            })
        } else if category.starts_with("audio.clipping") {
            Some(match escalation_level {
                1 => AutonomicCommand::new(
                    SignalOrigin::MixerBus,
                    CommandAction::EmergencyGainReduce { bus_id: 0, target_db: -3.0 },
                    format!("Repeated clipping ({}x) — reducing gain", raw_count),
                    CommandPriority::Normal,
                ),
                _ => AutonomicCommand::new(
                    SignalOrigin::MixerBus,
                    CommandAction::EmergencyGainReduce { bus_id: 0, target_db: -6.0 },
                    format!("Chronic clipping ({}x) — aggressive gain reduction", raw_count),
                    CommandPriority::High,
                ),
            })
        } else if category.starts_with("audio.cpu") {
            Some(AutonomicCommand::new(
                SignalOrigin::AudioEngine,
                CommandAction::ReduceQuality {
                    level: 0.2 * escalation_level as f32,
                },
                format!("CPU pressure escalation level {}", escalation_level),
                if escalation_level >= 3 {
                    CommandPriority::Emergency
                } else {
                    CommandPriority::High
                },
            ))
        } else if category.starts_with("plugin.") {
            Some(AutonomicCommand::new(
                SignalOrigin::PluginHost,
                CommandAction::SuspendBackground,
                format!("Plugin anomaly escalated: {} ({}x)", category, raw_count),
                CommandPriority::Normal,
            ))
        } else {
            log::info!(
                "Immune escalation for '{}' level {} — no specific handler",
                category,
                escalation_level
            );
            None
        }
    }

    /// Decay all antibody counts. Call periodically (e.g., every tick).
    pub fn decay_tick(&mut self) {
        let elapsed = self.last_decay.elapsed().as_secs_f64();
        if elapsed < 1.0 {
            return; // Decay at most once per second
        }
        self.last_decay = Instant::now();

        for antibody in self.antibodies.values_mut() {
            antibody.decay(elapsed);
        }

        // Remove completely decayed antibodies that weren't chronic
        self.antibodies.retain(|_, ab| ab.is_active() || ab.previously_resolved);
    }

    /// Get all active antibodies.
    pub fn active_antibodies(&self) -> Vec<&Antibody> {
        self.antibodies.values().filter(|ab| ab.is_active()).collect()
    }

    /// Get all antibodies (including resolved memory).
    pub fn all_antibodies(&self) -> Vec<&Antibody> {
        self.antibodies.values().collect()
    }

    /// Get a specific antibody by category.
    pub fn antibody(&self, category: &str) -> Option<&Antibody> {
        self.antibodies.get(category)
    }

    /// Resolve an anomaly category (mark as handled).
    pub fn resolve(&mut self, category: &str) {
        if let Some(ab) = self.antibodies.get_mut(category) {
            ab.resolve();
        }
    }

    /// Is any anomaly currently chronic?
    pub fn has_chronic(&self) -> bool {
        self.antibodies.values().any(|ab| ab.is_chronic())
    }

    /// Snapshot of immune system state for UI display.
    pub fn snapshot(&self) -> ImmuneSnapshot {
        ImmuneSnapshot {
            total_anomalies: self.total_anomalies,
            total_escalations: self.total_escalations,
            active_count: self.antibodies.values().filter(|ab| ab.is_active()).count(),
            chronic_count: self.antibodies.values().filter(|ab| ab.is_chronic()).count(),
            categories: self
                .antibodies
                .values()
                .filter(|ab| ab.is_active())
                .map(|ab| AntibodySummary {
                    category: ab.category.clone(),
                    count: ab.raw_count,
                    escalation_level: ab.escalation_level,
                    max_severity: ab.max_severity,
                    is_chronic: ab.is_chronic(),
                })
                .collect(),
        }
    }
}

impl Default for ImmuneSystem {
    fn default() -> Self {
        Self::new()
    }
}

/// Serializable snapshot of immune system state.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImmuneSnapshot {
    pub total_anomalies: u64,
    pub total_escalations: u64,
    pub active_count: usize,
    pub chronic_count: usize,
    pub categories: Vec<AntibodySummary>,
}

/// Summary of one antibody for UI display.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AntibodySummary {
    pub category: String,
    pub count: u32,
    pub escalation_level: u8,
    pub max_severity: f32,
    pub is_chronic: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_anomaly_no_escalation() {
        let mut immune = ImmuneSystem::new();
        let cmd = immune.record_anomaly("audio.underrun", 0.5);
        // First occurrence — no escalation
        assert!(cmd.is_none());
        assert_eq!(immune.total_anomalies, 1);
    }

    #[test]
    fn repeated_anomaly_escalates() {
        let mut immune = ImmuneSystem::new();

        // Record enough to trigger escalation (threshold at 3)
        for _ in 0..4 {
            immune.record_anomaly("audio.underrun", 0.8);
        }

        assert!(immune.total_escalations > 0);
        let ab = immune.antibody("audio.underrun").unwrap();
        assert!(ab.escalation_level >= 1);
    }

    #[test]
    fn escalation_generates_correct_command() {
        let mut immune = ImmuneSystem::new();

        let mut last_cmd = None;
        for _ in 0..4 {
            if let Some(cmd) = immune.record_anomaly("audio.underrun", 0.8) {
                last_cmd = Some(cmd);
            }
        }

        let cmd = last_cmd.unwrap();
        assert_eq!(cmd.target, SignalOrigin::AudioEngine);
        // Level 1 escalation should adjust buffer size
        assert!(matches!(cmd.action, CommandAction::AdjustBufferSize { .. }));
    }

    #[test]
    fn clipping_escalation() {
        let mut immune = ImmuneSystem::new();

        let mut last_cmd = None;
        for _ in 0..4 {
            if let Some(cmd) = immune.record_anomaly("audio.clipping", 0.6) {
                last_cmd = Some(cmd);
            }
        }

        let cmd = last_cmd.unwrap();
        assert_eq!(cmd.target, SignalOrigin::MixerBus);
        assert!(matches!(cmd.action, CommandAction::EmergencyGainReduce { .. }));
    }

    #[test]
    fn antibody_decay() {
        let mut immune = ImmuneSystem::new();
        immune.record_anomaly("test.decay", 0.5);

        let ab = immune.antibody("test.decay").unwrap();
        assert!(ab.effective_count > 0.5);

        // Simulate time passage — can't easily test real decay without sleep,
        // but we can test the decay math directly
        let mut ab = Antibody::new("test", 0.5);
        ab.decay(60.0); // 60 seconds of decay
        assert!(ab.effective_count < 0.1, "Expected significant decay, got {}", ab.effective_count);
    }

    #[test]
    fn antibody_resolve() {
        let mut immune = ImmuneSystem::new();
        for _ in 0..5 {
            immune.record_anomaly("audio.underrun", 0.8);
        }

        immune.resolve("audio.underrun");
        let ab = immune.antibody("audio.underrun").unwrap();
        assert!(ab.previously_resolved);
        assert_eq!(ab.escalation_level, 0);
        assert!(ab.effective_count < 0.01);
    }

    #[test]
    fn immune_snapshot() {
        let mut immune = ImmuneSystem::new();
        for _ in 0..3 {
            immune.record_anomaly("audio.underrun", 0.8);
        }
        immune.record_anomaly("audio.clipping", 0.5);

        let snap = immune.snapshot();
        assert_eq!(snap.total_anomalies, 4);
        assert_eq!(snap.active_count, 2);
    }

    #[test]
    fn chronic_detection() {
        let mut immune = ImmuneSystem::new();
        // Need 15+ occurrences for escalation level 3
        for _ in 0..16 {
            immune.record_anomaly("audio.underrun", 0.9);
        }

        let ab = immune.antibody("audio.underrun").unwrap();
        assert!(ab.is_chronic());
        assert!(immune.has_chronic());
    }

    #[test]
    fn multiple_categories_independent() {
        let mut immune = ImmuneSystem::new();
        for _ in 0..5 {
            immune.record_anomaly("audio.underrun", 0.8);
        }
        immune.record_anomaly("audio.clipping", 0.3);

        let underrun = immune.antibody("audio.underrun").unwrap();
        let clipping = immune.antibody("audio.clipping").unwrap();

        assert_eq!(underrun.raw_count, 5);
        assert_eq!(clipping.raw_count, 1);
        assert!(underrun.escalation_level > clipping.escalation_level);
    }

    #[test]
    fn active_antibodies_list() {
        let mut immune = ImmuneSystem::new();
        immune.record_anomaly("a", 0.5);
        immune.record_anomaly("b", 0.5);
        immune.record_anomaly("c", 0.5);

        let active = immune.active_antibodies();
        assert_eq!(active.len(), 3);
    }
}
