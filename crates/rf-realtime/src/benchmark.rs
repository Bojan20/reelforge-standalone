//! Performance Benchmarking System
//!
//! Real-time performance measurement and profiling:
//! - CPU usage per track/plugin
//! - Memory allocation tracking
//! - Latency measurement
//! - SIMD utilization
//! - GPU compute timing

use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant};

/// Performance target levels
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(Default)]
pub enum PerformanceTarget {
    /// Minimum viable (30% CPU budget)
    Minimum,
    /// Standard (20% CPU budget)
    #[default]
    Standard,
    /// Professional (10% CPU budget)
    Professional,
    /// Mastering (5% CPU budget)
    Mastering,
}

impl PerformanceTarget {
    /// Get CPU budget as percentage
    pub fn cpu_budget(&self) -> f64 {
        match self {
            Self::Minimum => 30.0,
            Self::Standard => 20.0,
            Self::Professional => 10.0,
            Self::Mastering => 5.0,
        }
    }

    /// Get maximum acceptable latency in ms
    pub fn max_latency_ms(&self) -> f64 {
        match self {
            Self::Minimum => 20.0,
            Self::Standard => 10.0,
            Self::Professional => 5.0,
            Self::Mastering => 3.0,
        }
    }
}


/// Timing measurement
#[derive(Debug, Clone, Default)]
pub struct TimingMeasurement {
    /// Total samples
    pub count: u64,
    /// Sum of all measurements (microseconds)
    pub total_us: u64,
    /// Minimum time (microseconds)
    pub min_us: u64,
    /// Maximum time (microseconds)
    pub max_us: u64,
    /// Sum of squares for std dev calculation
    pub sum_squares: u64,
}

impl TimingMeasurement {
    /// Add a measurement
    pub fn add(&mut self, duration_us: u64) {
        self.count += 1;
        self.total_us += duration_us;
        self.sum_squares += duration_us * duration_us;

        if self.count == 1 || duration_us < self.min_us {
            self.min_us = duration_us;
        }
        if duration_us > self.max_us {
            self.max_us = duration_us;
        }
    }

    /// Get average (microseconds)
    pub fn average_us(&self) -> f64 {
        if self.count == 0 {
            0.0
        } else {
            self.total_us as f64 / self.count as f64
        }
    }

    /// Get standard deviation (microseconds)
    pub fn std_dev_us(&self) -> f64 {
        if self.count < 2 {
            return 0.0;
        }
        let mean = self.average_us();
        let variance = (self.sum_squares as f64 / self.count as f64) - (mean * mean);
        variance.sqrt().max(0.0)
    }

    /// Reset measurements
    pub fn reset(&mut self) {
        *self = Self::default();
    }
}

/// Component type for profiling
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ComponentType {
    /// Audio I/O
    AudioIO,
    /// Plugin processing
    Plugin,
    /// DSP processing
    Dsp,
    /// State synchronization
    StateSync,
    /// GPU compute
    GpuCompute,
    /// Buffer management
    BufferMgmt,
    /// Automation
    Automation,
    /// Routing
    Routing,
    /// Analysis
    Analysis,
    /// Metering
    Metering,
}

/// Profiler scope guard for automatic timing
pub struct ProfilerScope {
    start: Instant,
    profiler: *const Profiler,
    component: ComponentType,
    id: u32,
}

impl Drop for ProfilerScope {
    fn drop(&mut self) {
        let duration = self.start.elapsed();
        unsafe {
            (*self.profiler).record_internal(self.component, self.id, duration);
        }
    }
}

/// Real-time profiler
pub struct Profiler {
    /// Is profiling enabled
    enabled: AtomicBool,
    /// Measurements by component and ID
    measurements: RwLock<HashMap<(ComponentType, u32), TimingMeasurement>>,
    /// Buffer processing time
    buffer_time: AtomicU64,
    /// Available time per buffer (microseconds)
    available_time_us: AtomicU64,
    /// Current sample rate
    sample_rate: AtomicU64,
    /// Current buffer size
    buffer_size: AtomicU64,
    /// Total CPU usage
    cpu_usage: AtomicU64,
}

impl Default for Profiler {
    fn default() -> Self {
        Self::new()
    }
}

impl Profiler {
    /// Create new profiler
    pub fn new() -> Self {
        Self {
            enabled: AtomicBool::new(false),
            measurements: RwLock::new(HashMap::new()),
            buffer_time: AtomicU64::new(0),
            available_time_us: AtomicU64::new(5333), // 256 samples @ 48kHz
            sample_rate: AtomicU64::new(48000),
            buffer_size: AtomicU64::new(256),
            cpu_usage: AtomicU64::new(0),
        }
    }

    /// Enable profiling
    pub fn enable(&self) {
        self.enabled.store(true, Ordering::Release);
    }

    /// Disable profiling
    pub fn disable(&self) {
        self.enabled.store(false, Ordering::Release);
    }

    /// Check if enabled
    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Acquire)
    }

    /// Configure for buffer size and sample rate
    pub fn configure(&self, buffer_size: usize, sample_rate: u32) {
        self.buffer_size
            .store(buffer_size as u64, Ordering::Release);
        self.sample_rate
            .store(sample_rate as u64, Ordering::Release);

        let available_us = (buffer_size as f64 / sample_rate as f64 * 1_000_000.0) as u64;
        self.available_time_us
            .store(available_us, Ordering::Release);
    }

    /// Start profiling scope
    pub fn scope(&self, component: ComponentType, id: u32) -> ProfilerScope {
        ProfilerScope {
            start: Instant::now(),
            profiler: self,
            component,
            id,
        }
    }

    /// Record measurement (internal use)
    fn record_internal(&self, component: ComponentType, id: u32, duration: Duration) {
        if !self.is_enabled() {
            return;
        }

        let duration_us = duration.as_micros() as u64;

        let mut measurements = self.measurements.write();
        measurements
            .entry((component, id))
            .or_default()
            .add(duration_us);
    }

    /// Record buffer processing time
    pub fn record_buffer_time(&self, duration: Duration) {
        let duration_us = duration.as_micros() as u64;
        self.buffer_time.store(duration_us, Ordering::Release);

        // Update CPU usage
        let available = self.available_time_us.load(Ordering::Acquire);
        if available > 0 {
            let usage = ((duration_us as f64 / available as f64) * 100.0 * 100.0) as u64;
            self.cpu_usage.store(usage, Ordering::Release);
        }
    }

    /// Get current CPU usage percentage
    pub fn cpu_usage(&self) -> f64 {
        self.cpu_usage.load(Ordering::Acquire) as f64 / 100.0
    }

    /// Get buffer time (microseconds)
    pub fn buffer_time_us(&self) -> u64 {
        self.buffer_time.load(Ordering::Acquire)
    }

    /// Get available time (microseconds)
    pub fn available_time_us(&self) -> u64 {
        self.available_time_us.load(Ordering::Acquire)
    }

    /// Get measurement for component
    pub fn get_measurement(&self, component: ComponentType, id: u32) -> Option<TimingMeasurement> {
        self.measurements.read().get(&(component, id)).cloned()
    }

    /// Get all measurements
    pub fn get_all_measurements(&self) -> HashMap<(ComponentType, u32), TimingMeasurement> {
        self.measurements.read().clone()
    }

    /// Reset all measurements
    pub fn reset(&self) {
        self.measurements.write().clear();
        self.buffer_time.store(0, Ordering::Release);
        self.cpu_usage.store(0, Ordering::Release);
    }

    /// Generate performance report
    pub fn generate_report(&self) -> PerformanceReport {
        let measurements = self.measurements.read();
        let mut components = Vec::new();

        for ((component, id), timing) in measurements.iter() {
            components.push(ComponentReport {
                component: *component,
                id: *id,
                avg_time_us: timing.average_us(),
                min_time_us: timing.min_us as f64,
                max_time_us: timing.max_us as f64,
                std_dev_us: timing.std_dev_us(),
                sample_count: timing.count,
            });
        }

        // Sort by average time descending
        components.sort_by(|a, b| b.avg_time_us.partial_cmp(&a.avg_time_us).unwrap());

        PerformanceReport {
            cpu_usage: self.cpu_usage(),
            buffer_time_us: self.buffer_time_us() as f64,
            available_time_us: self.available_time_us() as f64,
            sample_rate: self.sample_rate.load(Ordering::Acquire) as u32,
            buffer_size: self.buffer_size.load(Ordering::Acquire) as usize,
            components,
        }
    }
}

/// Component performance report
#[derive(Debug, Clone)]
pub struct ComponentReport {
    pub component: ComponentType,
    pub id: u32,
    pub avg_time_us: f64,
    pub min_time_us: f64,
    pub max_time_us: f64,
    pub std_dev_us: f64,
    pub sample_count: u64,
}

/// Full performance report
#[derive(Debug, Clone)]
pub struct PerformanceReport {
    pub cpu_usage: f64,
    pub buffer_time_us: f64,
    pub available_time_us: f64,
    pub sample_rate: u32,
    pub buffer_size: usize,
    pub components: Vec<ComponentReport>,
}

impl PerformanceReport {
    /// Check if meeting target
    pub fn meets_target(&self, target: PerformanceTarget) -> bool {
        self.cpu_usage <= target.cpu_budget()
    }

    /// Get top N consumers
    pub fn top_consumers(&self, n: usize) -> Vec<&ComponentReport> {
        self.components.iter().take(n).collect()
    }

    /// Total component time
    pub fn total_component_time_us(&self) -> f64 {
        self.components.iter().map(|c| c.avg_time_us).sum()
    }

    /// Overhead (buffer time - component time)
    pub fn overhead_us(&self) -> f64 {
        self.buffer_time_us - self.total_component_time_us()
    }
}

/// Memory tracking for allocations
#[derive(Debug, Default)]
pub struct MemoryTracker {
    /// Current allocated bytes
    allocated: AtomicU64,
    /// Peak allocated bytes
    peak: AtomicU64,
    /// Total allocations
    alloc_count: AtomicU64,
    /// Total deallocations
    dealloc_count: AtomicU64,
}

impl MemoryTracker {
    /// Record allocation
    pub fn record_alloc(&self, bytes: usize) {
        let prev = self.allocated.fetch_add(bytes as u64, Ordering::Relaxed);
        let current = prev + bytes as u64;

        // Update peak
        let mut peak = self.peak.load(Ordering::Relaxed);
        while current > peak {
            match self.peak.compare_exchange_weak(
                peak,
                current,
                Ordering::Relaxed,
                Ordering::Relaxed,
            ) {
                Ok(_) => break,
                Err(p) => peak = p,
            }
        }

        self.alloc_count.fetch_add(1, Ordering::Relaxed);
    }

    /// Record deallocation
    pub fn record_dealloc(&self, bytes: usize) {
        self.allocated.fetch_sub(bytes as u64, Ordering::Relaxed);
        self.dealloc_count.fetch_add(1, Ordering::Relaxed);
    }

    /// Get current allocation
    pub fn current_bytes(&self) -> u64 {
        self.allocated.load(Ordering::Relaxed)
    }

    /// Get peak allocation
    pub fn peak_bytes(&self) -> u64 {
        self.peak.load(Ordering::Relaxed)
    }

    /// Get allocation count
    pub fn alloc_count(&self) -> u64 {
        self.alloc_count.load(Ordering::Relaxed)
    }

    /// Reset tracker
    pub fn reset(&self) {
        self.allocated.store(0, Ordering::Relaxed);
        self.peak.store(0, Ordering::Relaxed);
        self.alloc_count.store(0, Ordering::Relaxed);
        self.dealloc_count.store(0, Ordering::Relaxed);
    }
}

/// Global profiler instance
static GLOBAL_PROFILER: std::sync::OnceLock<Profiler> = std::sync::OnceLock::new();

/// Get global profiler
pub fn profiler() -> &'static Profiler {
    GLOBAL_PROFILER.get_or_init(Profiler::new)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_performance_target() {
        assert_eq!(PerformanceTarget::Mastering.cpu_budget(), 5.0);
        assert_eq!(PerformanceTarget::Professional.max_latency_ms(), 5.0);
    }

    #[test]
    fn test_timing_measurement() {
        let mut timing = TimingMeasurement::default();
        timing.add(100);
        timing.add(200);
        timing.add(300);

        assert_eq!(timing.count, 3);
        assert!((timing.average_us() - 200.0).abs() < 0.1);
        assert_eq!(timing.min_us, 100);
        assert_eq!(timing.max_us, 300);
    }

    #[test]
    fn test_profiler() {
        let profiler = Profiler::new();
        profiler.enable();
        profiler.configure(256, 48000);

        {
            let _scope = profiler.scope(ComponentType::Dsp, 1);
            std::thread::sleep(Duration::from_micros(100));
        }

        let measurement = profiler.get_measurement(ComponentType::Dsp, 1);
        assert!(measurement.is_some());
        assert!(measurement.unwrap().count >= 1);
    }

    #[test]
    fn test_memory_tracker() {
        let tracker = MemoryTracker::default();
        tracker.record_alloc(1000);
        tracker.record_alloc(500);

        assert_eq!(tracker.current_bytes(), 1500);
        assert_eq!(tracker.peak_bytes(), 1500);

        tracker.record_dealloc(500);
        assert_eq!(tracker.current_bytes(), 1000);
        assert_eq!(tracker.peak_bytes(), 1500); // Peak unchanged
    }

    #[test]
    fn test_performance_report() {
        let profiler = Profiler::new();
        profiler.enable();
        profiler.configure(256, 48000);

        let report = profiler.generate_report();
        assert!(report.cpu_usage >= 0.0);
    }
}
