use std::time::Instant;
use crate::core::config::AurexisConfig;
use crate::core::engine::AurexisEngine;

/// Measures AUREXIS compute performance.
pub struct PerformanceProfiler {
    /// Compute times in nanoseconds (sub-microsecond precision).
    times_ns: Vec<u64>,
}

impl PerformanceProfiler {
    pub fn new() -> Self {
        Self {
            times_ns: Vec::with_capacity(1024),
        }
    }

    /// Profile a single compute call and record the time.
    pub fn profile_compute(&mut self, engine: &mut AurexisEngine, elapsed_ms: u64) {
        let start = Instant::now();
        engine.compute(elapsed_ms);
        let elapsed = start.elapsed().as_nanos() as u64;
        self.times_ns.push(elapsed);
    }

    /// Run N profiling iterations and return stats.
    pub fn run_benchmark(&mut self, iterations: usize) -> ProfileStats {
        let config = AurexisConfig::default();
        let mut engine = AurexisEngine::with_config(config);
        engine.initialize();
        engine.set_volatility(0.7);
        engine.set_rtp(93.0);
        engine.set_win(25.0, 1.0, 0.2);
        engine.set_seed(42, 1000, 7, 0);
        engine.set_metering(-12.0, -18.0);

        // Register some voices for collision
        for i in 0..8 {
            let pan = -1.0 + (i as f32 / 4.0);
            engine.register_voice(i, pan, 0.0, (10 - i) as i32);
        }

        self.times_ns.clear();
        for _ in 0..iterations {
            self.profile_compute(&mut engine, 50);
        }

        self.stats()
    }

    /// Compute statistics from recorded times.
    pub fn stats(&self) -> ProfileStats {
        if self.times_ns.is_empty() {
            return ProfileStats::default();
        }

        let mut sorted = self.times_ns.clone();
        sorted.sort_unstable();

        let sum: u64 = sorted.iter().sum();
        // Convert ns → us (f64 preserves sub-microsecond precision)
        let mean = (sum as f64 / sorted.len() as f64) / 1000.0;
        let median = sorted[sorted.len() / 2] / 1000;
        let p95 = sorted[(sorted.len() as f64 * 0.95) as usize] / 1000;
        let p99 = sorted[(sorted.len() as f64 * 0.99) as usize] / 1000;
        let min = sorted[0] / 1000;
        let max = *sorted.last().unwrap() / 1000;

        ProfileStats {
            iterations: sorted.len(),
            mean_us: mean,
            median_us: median,
            p95_us: p95,
            p99_us: p99,
            min_us: min,
            max_us: max,
            mean_ns: sum as f64 / sorted.len() as f64,
        }
    }

    /// Clear recorded times.
    pub fn clear(&mut self) {
        self.times_ns.clear();
    }
}

impl Default for PerformanceProfiler {
    fn default() -> Self {
        Self::new()
    }
}

/// Performance statistics.
#[derive(Debug, Clone, Default)]
pub struct ProfileStats {
    pub iterations: usize,
    pub mean_us: f64,
    pub median_us: u64,
    pub p95_us: u64,
    pub p99_us: u64,
    pub min_us: u64,
    pub max_us: u64,
    /// Mean in nanoseconds (sub-microsecond precision).
    pub mean_ns: f64,
}

impl ProfileStats {
    /// Check if performance meets the 50ms budget (compute < 1ms).
    pub fn within_budget(&self) -> bool {
        // AUREXIS compute must complete in <1ms for 20Hz tick
        self.p99_us < 1000
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_profiler_runs() {
        let mut profiler = PerformanceProfiler::new();
        let stats = profiler.run_benchmark(100);
        assert_eq!(stats.iterations, 100);
        // mean_ns is always > 0 (nanosecond precision)
        assert!(stats.mean_ns > 0.0, "mean_ns should be > 0, got {}", stats.mean_ns);
        assert!(stats.min_us <= stats.median_us);
        assert!(stats.median_us <= stats.p95_us);
        assert!(stats.p95_us <= stats.p99_us);
        assert!(stats.p99_us <= stats.max_us);
    }

    #[test]
    fn test_within_budget() {
        let mut profiler = PerformanceProfiler::new();
        let stats = profiler.run_benchmark(50);
        // AUREXIS compute is pure math, should be well under 1ms
        assert!(stats.within_budget(),
            "AUREXIS compute exceeded 1ms budget: p99={}us", stats.p99_us);
    }
}
