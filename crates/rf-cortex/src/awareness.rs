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
}

/// The seven dimensions of CORTEX self-awareness.
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
}

impl AwarenessDimensions {
    /// Calculate overall health as weighted average of dimensions.
    pub fn overall(&self) -> f64 {
        let weights = [
            (self.throughput, 0.20),
            (self.reliability, 0.25),
            (self.responsiveness, 0.15),
            (self.coverage, 0.10),
            (self.cognition, 0.10),
            (self.efficiency, 0.10),
            (self.coherence, 0.10),
        ];
        let (weighted_sum, weight_total) =
            weights.iter().fold((0.0, 0.0), |(sum, total), (val, w)| {
                (sum + val * w, total + w)
            });
        weighted_sum / weight_total
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
        };

        let snapshot = AwarenessSnapshot {
            uptime_secs: uptime.as_secs_f64(),
            signals_per_second,
            drop_rate,
            active_reflexes: reflex_stats.iter().filter(|r| r.enabled).count(),
            reflex_fires: new_reflex_fires,
            patterns_recognized: new_patterns,
            subscriber_count: bus_stats.subscriber_count,
            health_score: dimensions.overall(),
            dimensions,
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
    pub fn is_degraded(&self) -> bool {
        self.latest().is_some_and(|s| s.health_score < 0.6)
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
}

impl Default for AwarenessEngine {
    fn default() -> Self {
        Self::new(8) // expect 8 subsystems by default
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
        };
        let overall = dims.overall();
        assert!((overall - 1.0).abs() < 0.001);
    }
}
