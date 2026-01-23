//! Benchmark utilities

use std::time::{Duration, Instant};

/// Throughput metrics for audio processing
#[derive(Debug, Clone)]
pub struct ThroughputMetrics {
    /// Samples processed per second
    pub samples_per_sec: f64,
    /// Time per sample in nanoseconds
    pub ns_per_sample: f64,
    /// Real-time ratio (>1.0 means faster than real-time)
    pub realtime_ratio: f64,
    /// Processing latency at given buffer size
    pub latency_ms: f64,
}

impl ThroughputMetrics {
    /// Calculate metrics from benchmark results
    pub fn from_benchmark(
        samples: usize,
        duration: Duration,
        sample_rate: f64,
    ) -> Self {
        let secs = duration.as_secs_f64();
        let samples_per_sec = samples as f64 / secs;
        let ns_per_sample = duration.as_nanos() as f64 / samples as f64;
        let realtime_ratio = samples_per_sec / sample_rate;
        let latency_ms = secs * 1000.0;

        Self {
            samples_per_sec,
            ns_per_sample,
            realtime_ratio,
            latency_ms,
        }
    }

    /// Check if processing is real-time capable
    pub fn is_realtime(&self) -> bool {
        self.realtime_ratio > 1.0
    }

    /// Print summary
    pub fn summary(&self) -> String {
        format!(
            "{:.2} MS/s ({:.1}ns/sample), {:.1}x realtime, {:.3}ms latency",
            self.samples_per_sec / 1_000_000.0,
            self.ns_per_sample,
            self.realtime_ratio,
            self.latency_ms
        )
    }
}

/// Simple benchmark runner for quick measurements
pub struct QuickBench {
    iterations: usize,
}

impl QuickBench {
    pub fn new(iterations: usize) -> Self {
        Self { iterations }
    }

    /// Run benchmark and return average duration
    pub fn run<F>(&self, mut f: F) -> Duration
    where
        F: FnMut(),
    {
        // Warmup
        for _ in 0..10 {
            f();
        }

        let start = Instant::now();
        for _ in 0..self.iterations {
            f();
        }
        start.elapsed() / self.iterations as u32
    }

    /// Run benchmark with throughput metrics
    pub fn run_with_metrics<F>(
        &self,
        samples_per_iteration: usize,
        sample_rate: f64,
        mut f: F,
    ) -> ThroughputMetrics
    where
        F: FnMut(),
    {
        // Warmup
        for _ in 0..10 {
            f();
        }

        let start = Instant::now();
        for _ in 0..self.iterations {
            f();
        }
        let total_duration = start.elapsed();
        let avg_duration = total_duration / self.iterations as u32;

        ThroughputMetrics::from_benchmark(samples_per_iteration, avg_duration, sample_rate)
    }
}

/// Black box to prevent compiler optimizations
#[inline(never)]
pub fn black_box<T>(x: T) -> T {
    std::hint::black_box(x)
}

/// Calculate overhead percentage
pub fn overhead_percent(baseline: Duration, measured: Duration) -> f64 {
    ((measured.as_nanos() as f64 / baseline.as_nanos() as f64) - 1.0) * 100.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_throughput_metrics() {
        let metrics = ThroughputMetrics::from_benchmark(
            44100,
            Duration::from_millis(10),
            44100.0,
        );
        assert!(metrics.realtime_ratio > 90.0); // Should be ~100x realtime
        assert!(metrics.is_realtime());
    }

    #[test]
    fn test_quick_bench() {
        let bench = QuickBench::new(100);
        let duration = bench.run(|| {
            let _ = (0..1000).sum::<i32>();
        });
        assert!(duration.as_nanos() > 0);
    }
}
