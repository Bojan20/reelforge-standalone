// file: crates/rf-cortex/src/awareness.rs
//! Self-awareness module — the cortex monitors its own health and performance.
//!
//! Tracks signal throughput, reflex efficiency, pattern recognition accuracy,
//! and overall system coherence. This is the meta-cognitive layer.

use crate::bus::BusStats;
use crate::pattern::PatternDetectorStats;
use crate::reflex::ReflexStats;
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::time::{Duration, Instant};

/// Whether the cortex is in an idle state (no active app connected).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CortexActivityState {
    /// App is running, signals flowing — full health evaluation applies.
    Active,
    /// No app connected, daemon-only mode — low scores are expected, not alarming.
    Idle,
}

/// A snapshot of the cortex's self-awareness at a point in time.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AwarenessSnapshot {
    /// Timestamp as seconds since cortex boot.
    pub uptime_secs: f64,
    /// Signals processed per second (throughput).
    pub signals_per_second: f64,
    /// Signal drop rate (0.0 = none dropped, 1.0 = all dropped).
    pub drop_rate: f64,
    /// Number of active reflexes.
    pub active_reflexes: usize,
    /// Total reflex fires since last snapshot.
    pub reflex_fires: u64,
    /// Number of patterns recognized since last snapshot.
    pub patterns_recognized: u64,
    /// Number of connected subscribers.
    pub subscriber_count: usize,
    /// Overall health score (0.0 = critical, 1.0 = perfect).
    pub health_score: f64,
    /// Individual dimension scores.
    pub dimensions: AwarenessDimensions,
    /// Whether system was idle when this snapshot was taken.
    pub activity_state: CortexActivityState,
}

/// The eight dimensions of CORTEX self-awareness.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AwarenessDimensions {
    /// Signal throughput health (are we processing fast enough?).
    pub throughput: f64,
    /// Reliability (are signals being delivered?).
    pub reliability: f64,
    /// Responsiveness (how fast are reflexes reacting?).
    pub responsiveness: f64,
    /// Coverage (are all subsystems sending signals?).
    pub coverage: f64,
    /// Pattern recognition effectiveness.
    pub cognition: f64,
    /// Resource efficiency (memory, CPU usage of cortex itself).
    pub efficiency: f64,
    /// System coherence (are subsystems in sync?).
    pub coherence: f64,
    /// Code health (evolution fitness score from Code Guardian).
    pub code_health: f64,
    /// Vision health (freshness and anomaly level from Flutter vision system).
    pub vision: f64,
}

impl AwarenessDimensions {
    /// Calculate overall health as weighted average of dimensions.
    /// When `active`, all dimensions contribute normally.
    /// When `idle`, dimensions that require app connectivity are excluded
    /// from the score — only code_health, reliability, and efficiency matter.
    pub fn overall(&self) -> f64 {
        self.overall_for_state(CortexActivityState::Active)
    }

    /// Calculate overall health adjusted for the current activity state.
    pub fn overall_for_state(&self, state: CortexActivityState) -> f64 {
        match state {
            CortexActivityState::Active => {
                let weights = [
                    (self.throughput, 0.16),
                    (self.reliability, 0.20),
                    (self.responsiveness, 0.12),
                    (self.coverage, 0.07),
                    (self.cognition, 0.08),
                    (self.efficiency, 0.07),
                    (self.coherence, 0.07),
                    (self.code_health, 0.13),
                    (self.vision, 0.10),
                ];
                let (weighted_sum, weight_total) =
                    weights.iter().fold((0.0, 0.0), |(sum, total), (val, w)| {
                        (sum + val * w, total + w)
                    });
                weighted_sum / weight_total
            }
            CortexActivityState::Idle => {
                // When idle: only evaluate dimensions that make sense without an app.
                // Throughput, vision, coverage, coherence are N/A — don't penalize.
                // Code health, reliability, efficiency still matter (daemon health).
                let weights = [
                    (self.reliability, 0.30),
                    (self.code_health, 0.35),
                    (self.efficiency, 0.20),
                    (self.cognition, 0.15),
                ];
                let (weighted_sum, weight_total) =
                    weights.iter().fold((0.0, 0.0), |(sum, total), (val, w)| {
                        (sum + val * w, total + w)
                    });
                weighted_sum / weight_total
            }
        }
    }
}

/// The awareness engine — maintains history and computes snapshots.
pub struct AwarenessEngine {
    /// When the cortex started.
    boot_time: Instant,
    /// History of snapshots.
    history: VecDeque<AwarenessSnapshot>,
    /// Maximum history size.
    max_history: usize,
    /// Previous bus stats (for delta calculation).
    prev_bus_stats: Option<(Instant, BusStats)>,
    /// Previous reflex fire count.
    prev_reflex_fires: u64,
    /// Previous pattern count.
    prev_pattern_count: u64,
    /// Expected origins (subsystems that should be sending signals).
    expected_origins: usize,
    /// Code health score from Code Guardian (0.0-1.0).
    /// Updated externally via `set_code_health()`.
    code_health_score: f64,
    /// Vision freshness: seconds since last vision signal from Flutter.
    /// Updated externally via `report_vision_capture()`.
    vision_last_capture: Option<Instant>,
    /// Count of visual anomalies in the current window.
    vision_anomaly_count: u32,
    /// Count of frozen regions reported by Flutter.
    vision_frozen_count: u32,
    /// Last time we saw real activity (signals > 0 or subscribers > 0).
    last_activity: Option<Instant>,
    /// How long without activity before we consider the system idle.
    idle_threshold: Duration,
}

impl AwarenessEngine {
    pub fn new(expected_origins: usize) -> Self {
        Self {
            boot_time: Instant::now(),
            history: VecDeque::with_capacity(1000),
            max_history: 1000,
            prev_bus_stats: None,
            prev_reflex_fires: 0,
            prev_pattern_count: 0,
            expected_origins,
            code_health_score: 1.0, // assume healthy until Guardian reports
            vision_last_capture: None,
            vision_anomaly_count: 0,
            vision_frozen_count: 0,
            last_activity: None,
            idle_threshold: Duration::from_secs(30), // 30s without signals → idle
        }
    }

    /// Set the code health score (called by Code Guardian).
    pub fn set_code_health(&mut self, score: f64) {
        self.code_health_score = score.clamp(0.0, 1.0);
    }

    /// Report a vision capture from Flutter (called on each auto-observe cycle).
    pub fn report_vision_capture(&mut self, anomaly_count: u32, frozen_count: u32) {
        self.vision_last_capture = Some(Instant::now());
        self.vision_anomaly_count = anomaly_count;
        self.vision_frozen_count = frozen_count;
    }

    /// Detect current activity state based on signal flow and subscribers.
    fn detect_activity_state(&mut self, bus_stats: &BusStats, signals_per_second: f64) -> CortexActivityState {
        let now = Instant::now();
        let has_activity = signals_per_second > 0.1
            || bus_stats.subscriber_count > 0
            || bus_stats.origin_counts.len() > 0;

        if has_activity {
            self.last_activity = Some(now);
            CortexActivityState::Active
        } else {
            match self.last_activity {
                Some(last) if now.duration_since(last) < self.idle_threshold => {
                    CortexActivityState::Active // grace period
                }
                _ => CortexActivityState::Idle,
            }
        }
    }

    /// Get the current activity state without mutating.
    pub fn activity_state(&self) -> CortexActivityState {
        match self.last_activity {
            Some(last) if last.elapsed() < self.idle_threshold => CortexActivityState::Active,
            Some(_) | None => CortexActivityState::Idle,
        }
    }

    /// Take a snapshot of the cortex's current awareness state.
    pub fn snapshot(
        &mut self,
        bus_stats: &BusStats,
        reflex_stats: &[ReflexStats],
        pattern_stats: &[PatternDetectorStats],
    ) -> AwarenessSnapshot {
        let now = Instant::now();
        let uptime = now.duration_since(self.boot_time);

        // Calculate throughput (signals per second since last snapshot)
        let (signals_per_second, drop_rate) = if let Some((prev_time, ref prev_stats)) =
            self.prev_bus_stats
        {
            let dt = now.duration_since(prev_time).as_secs_f64().max(0.001);
            let new_signals = bus_stats.total_emitted.saturating_sub(prev_stats.total_emitted);
            let new_drops = bus_stats.total_dropped.saturating_sub(prev_stats.total_dropped);
            let sps = new_signals as f64 / dt;
            let dr = if new_signals > 0 {
                new_drops as f64 / new_signals as f64
            } else {
                0.0
            };
            (sps, dr)
        } else {
            (0.0, 0.0)
        };

        // Detect idle vs active state
        let activity_state = self.detect_activity_state(bus_stats, signals_per_second);

        // Count current reflex fires
        let total_reflex_fires: u64 = reflex_stats.iter().map(|r| r.fire_count).sum();
        let new_reflex_fires = total_reflex_fires.saturating_sub(self.prev_reflex_fires);

        // Count pattern recognitions
        let total_patterns: u64 = pattern_stats.iter().map(|p| p.recognition_count).sum();
        let new_patterns = total_patterns.saturating_sub(self.prev_pattern_count);

        // Calculate dimensions
        let dimensions = AwarenessDimensions {
            throughput: Self::score_throughput(signals_per_second),
            reliability: Self::score_reliability(drop_rate),
            responsiveness: Self::score_responsiveness(reflex_stats),
            coverage: Self::score_coverage(bus_stats, self.expected_origins),
            cognition: Self::score_cognition(new_patterns, new_reflex_fires),
            efficiency: Self::score_efficiency(bus_stats),
            coherence: Self::score_coherence(bus_stats),
            code_health: self.code_health_score,
            vision: Self::score_vision(
                self.vision_last_capture,
                self.vision_anomaly_count,
                self.vision_frozen_count,
            ),
        };

        // Use idle-aware scoring: when idle, don't penalize missing signals/vision
        let health_score = dimensions.overall_for_state(activity_state);

        let snapshot = AwarenessSnapshot {
            uptime_secs: uptime.as_secs_f64(),
            signals_per_second,
            drop_rate,
            active_reflexes: reflex_stats.iter().filter(|r| r.enabled).count(),
            reflex_fires: new_reflex_fires,
            patterns_recognized: new_patterns,
            subscriber_count: bus_stats.subscriber_count,
            health_score,
            dimensions,
            activity_state,
        };

        // Update history
        self.history.push_back(snapshot.clone());
        while self.history.len() > self.max_history {
            self.history.pop_front();
        }

        // Update prev state
        self.prev_bus_stats = Some((now, bus_stats.clone()));
        self.prev_reflex_fires = total_reflex_fires;
        self.prev_pattern_count = total_patterns;

        snapshot
    }

    /// Get the most recent snapshot.
    pub fn latest(&self) -> Option<&AwarenessSnapshot> {
        self.history.back()
    }

    /// Get the full history.
    pub fn history(&self) -> &VecDeque<AwarenessSnapshot> {
        &self.history
    }

    /// Average health over the last N snapshots.
    pub fn average_health(&self, n: usize) -> f64 {
        let recent: Vec<_> = self.history.iter().rev().take(n).collect();
        if recent.is_empty() {
            return 1.0;
        }
        recent.iter().map(|s| s.health_score).sum::<f64>() / recent.len() as f64
    }

    /// Is the cortex degraded (health below threshold)?
    /// When idle, the system is NEVER considered degraded — low scores are expected.
    pub fn is_degraded(&self) -> bool {
        self.latest().is_some_and(|s| {
            s.activity_state == CortexActivityState::Active && s.health_score < 0.6
        })
    }

    /// Uptime since boot.
    pub fn uptime(&self) -> Duration {
        self.boot_time.elapsed()
    }

    // --- Dimension scoring functions ---

    fn score_throughput(sps: f64) -> f64 {
        // 0 sps = 0.5 (no signals is not necessarily bad at startup)
        // 10+ sps = 1.0 (healthy flow)
        // 1000+ sps = slight decrease (possible storm)
        if sps < 0.1 {
            0.5
        } else if sps <= 500.0 {
            1.0
        } else if sps <= 2000.0 {
            1.0 - (sps - 500.0) / 3000.0
        } else {
            0.5
        }
    }

    fn score_reliability(drop_rate: f64) -> f64 {
        // 0% drop = 1.0, 10% drop = 0.5, 50%+ drop = 0.0
        (1.0 - drop_rate * 2.0).clamp(0.0, 1.0)
    }

    fn score_responsiveness(reflex_stats: &[ReflexStats]) -> f64 {
        // If reflexes exist and are enabled, assume responsive
        let enabled = reflex_stats.iter().filter(|r| r.enabled).count();
        let total = reflex_stats.len();
        if total == 0 {
            return 0.5;
        }
        enabled as f64 / total as f64
    }

    fn score_coverage(bus_stats: &BusStats, expected_origins: usize) -> f64 {
        if expected_origins == 0 {
            return 1.0;
        }
        let active = bus_stats.origin_counts.len();
        (active as f64 / expected_origins as f64).min(1.0)
    }

    fn score_cognition(new_patterns: u64, new_reflex_fires: u64) -> f64 {
        // Having some pattern recognition activity is good
        // Too many fires might indicate problems
        let activity = new_patterns + new_reflex_fires;
        if activity == 0 {
            0.7 // quiet is fine
        } else if activity <= 10 {
            1.0 // healthy activity
        } else if activity <= 50 {
            0.8 // busy but ok
        } else {
            0.5 // too busy, something might be wrong
        }
    }

    fn score_efficiency(bus_stats: &BusStats) -> f64 {
        // Fewer subscribers with good throughput = efficient
        let subs = bus_stats.subscriber_count;
        if subs == 0 {
            return 0.5;
        }
        if subs <= 20 {
            1.0
        } else if subs <= 100 {
            0.8
        } else {
            0.6
        }
    }

    fn score_coherence(bus_stats: &BusStats) -> f64 {
        // If signals are flowing from multiple origins, system is coherent
        let origins = bus_stats.origin_counts.len();
        if origins == 0 {
            0.5
        } else if origins >= 3 {
            1.0
        } else {
            0.7
        }
    }

    /// Score vision health based on freshness, anomalies, and frozen regions.
    fn score_vision(
        last_capture: Option<Instant>,
        anomaly_count: u32,
        frozen_count: u32,
    ) -> f64 {
        let freshness = match last_capture {
            None => 0.3, // No captures yet — vision not active
            Some(t) => {
                let age_secs = t.elapsed().as_secs_f64();
                if age_secs < 15.0 {
                    1.0 // Fresh — captured within observation interval
                } else if age_secs < 60.0 {
                    0.8 // Recent
                } else if age_secs < 300.0 {
                    0.5 // Stale
                } else {
                    0.2 // Very stale — vision may have stopped
                }
            }
        };

        // Anomaly penalty: each anomaly reduces score
        let anomaly_penalty = (anomaly_count as f64 * 0.1).min(0.4);

        // Frozen penalty: frozen regions indicate UI problems
        let frozen_penalty = (frozen_count as f64 * 0.15).min(0.5);

        (freshness - anomaly_penalty - frozen_penalty).clamp(0.0, 1.0)
    }
}

impl Default for AwarenessEngine {
    fn default() -> Self {
        Self::new(8) // expect 8 subsystems by default
    }
}

impl Default for CortexActivityState {
    fn default() -> Self {
        Self::Idle
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signal::SignalOrigin;
    use std::collections::HashMap;

    fn mock_bus_stats(emitted: u64, dropped: u64, origins: usize) -> BusStats {
        let mut origin_counts = HashMap::new();
        let all_origins = [
            SignalOrigin::AudioEngine,
            SignalOrigin::DspPipeline,
            SignalOrigin::MixerBus,
            SignalOrigin::PluginHost,
            SignalOrigin::Transport,
            SignalOrigin::SlotLab,
            SignalOrigin::Cortex,
            SignalOrigin::Vision,
        ];
        for origin in all_origins.iter().take(origins) {
            origin_counts.insert(*origin, emitted / origins.max(1) as u64);
        }
        BusStats {
            total_emitted: emitted,
            total_dropped: dropped,
            subscriber_count: 3,
            origin_counts,
        }
    }

    fn mock_reflex_stats() -> Vec<ReflexStats> {
        vec![
            ReflexStats { name: "r1".into(), fire_count: 5, enabled: true },
            ReflexStats { name: "r2".into(), fire_count: 2, enabled: true },
            ReflexStats { name: "r3".into(), fire_count: 0, enabled: false },
        ]
    }

    fn mock_pattern_stats() -> Vec<PatternDetectorStats> {
        vec![
            PatternDetectorStats { name: "p1".into(), recognition_count: 3 },
            PatternDetectorStats { name: "p2".into(), recognition_count: 1 },
        ]
    }

    #[test]
    fn snapshot_basic() {
        let mut engine = AwarenessEngine::new(8);
        let snap = engine.snapshot(
            &mock_bus_stats(100, 0, 5),
            &mock_reflex_stats(),
            &mock_pattern_stats(),
        );
        assert!(snap.health_score > 0.0);
        assert!(snap.health_score <= 1.0);
        assert!(snap.uptime_secs >= 0.0);
    }

    #[test]
    fn perfect_health() {
        let mut engine = AwarenessEngine::new(5);
        let bus = mock_bus_stats(100, 0, 5);
        let _ = engine.snapshot(&bus, &mock_reflex_stats(), &mock_pattern_stats());

        // Second snapshot with more signals (to get throughput)
        std::thread::sleep(Duration::from_millis(10));
        let bus2 = mock_bus_stats(200, 0, 5);
        let snap = engine.snapshot(&bus2, &mock_reflex_stats(), &mock_pattern_stats());

        assert!(snap.health_score > 0.5, "health={}", snap.health_score);
        assert!(snap.dimensions.reliability > 0.9);
    }

    #[test]
    fn degraded_on_high_drops() {
        let mut engine = AwarenessEngine::new(5);
        let bus = mock_bus_stats(100, 0, 5);
        let _ = engine.snapshot(&bus, &mock_reflex_stats(), &mock_pattern_stats());

        std::thread::sleep(Duration::from_millis(10));
        let bus2 = mock_bus_stats(200, 80, 5); // 80% of new signals dropped
        let snap = engine.snapshot(&bus2, &mock_reflex_stats(), &mock_pattern_stats());

        assert!(snap.dimensions.reliability < 0.5);
    }

    #[test]
    fn history_bounded() {
        let mut engine = AwarenessEngine::new(5);
        engine.max_history = 10;

        for i in 0..20 {
            engine.snapshot(
                &mock_bus_stats(i * 10, 0, 3),
                &mock_reflex_stats(),
                &mock_pattern_stats(),
            );
        }

        assert_eq!(engine.history().len(), 10);
    }

    #[test]
    fn average_health() {
        let mut engine = AwarenessEngine::new(5);
        for i in 0..5 {
            engine.snapshot(
                &mock_bus_stats(i * 50, 0, 3),
                &mock_reflex_stats(),
                &mock_pattern_stats(),
            );
        }
        let avg = engine.average_health(3);
        assert!(avg > 0.0 && avg <= 1.0);
    }

    #[test]
    fn uptime_increases() {
        let engine = AwarenessEngine::new(5);
        std::thread::sleep(Duration::from_millis(5));
        assert!(engine.uptime().as_millis() >= 5);
    }

    #[test]
    fn dimensions_overall_weighted() {
        let dims = AwarenessDimensions {
            throughput: 1.0,
            reliability: 1.0,
            responsiveness: 1.0,
            coverage: 1.0,
            cognition: 1.0,
            efficiency: 1.0,
            coherence: 1.0,
            code_health: 1.0,
            vision: 1.0,
        };
        let overall = dims.overall();
        assert!((overall - 1.0).abs() < 0.001);
    }
}
