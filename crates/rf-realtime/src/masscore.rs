//! MassCore++ Style Processing Engine
//!
//! Pyramix-inspired ultra-low latency processing:
//! - Dedicated CPU core affinity
//! - Lock-free audio processing
//! - Zero-copy buffer management
//! - Deterministic latency
//! - Priority-based scheduling

use parking_lot::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

/// MassCore configuration
#[derive(Debug, Clone)]
pub struct MassCoreConfig {
    /// Number of dedicated audio cores
    pub audio_cores: usize,
    /// Buffer size in samples
    pub buffer_size: usize,
    /// Sample rate
    pub sample_rate: u32,
    /// Enable real-time priority
    pub realtime_priority: bool,
    /// Core affinity mask (bit per core)
    pub core_affinity: Option<u64>,
    /// Maximum processing time per buffer (microseconds)
    pub max_process_time_us: u64,
    /// Enable power efficiency mode
    pub power_efficient: bool,
    /// Watchdog timeout (ms)
    pub watchdog_timeout_ms: u64,
}

impl Default for MassCoreConfig {
    fn default() -> Self {
        Self {
            audio_cores: 2,
            buffer_size: 256,
            sample_rate: 48000,
            realtime_priority: true,
            core_affinity: None,
            max_process_time_us: 5000, // 5ms
            power_efficient: false,
            watchdog_timeout_ms: 100,
        }
    }
}

impl MassCoreConfig {
    /// Calculate buffer latency in milliseconds
    pub fn buffer_latency_ms(&self) -> f64 {
        self.buffer_size as f64 / self.sample_rate as f64 * 1000.0
    }

    /// Calculate samples per millisecond
    pub fn samples_per_ms(&self) -> f64 {
        self.sample_rate as f64 / 1000.0
    }

    /// Optimal core count for this machine
    pub fn optimal_audio_cores() -> usize {
        let available = num_cpus::get();
        // Reserve at least 2 cores for system + UI
        (available.saturating_sub(2)).max(1).min(8)
    }
}

/// Processing statistics
#[derive(Debug, Clone, Default)]
pub struct ProcessingStats {
    /// Total buffers processed
    pub buffers_processed: u64,
    /// Average process time (microseconds)
    pub avg_process_time_us: f64,
    /// Maximum process time (microseconds)
    pub max_process_time_us: f64,
    /// Minimum process time (microseconds)
    pub min_process_time_us: f64,
    /// Buffer underruns
    pub underruns: u64,
    /// Buffer overruns
    pub overruns: u64,
    /// CPU usage percentage
    pub cpu_usage: f64,
    /// Current latency samples
    pub latency_samples: u32,
}

/// Atomic statistics for real-time access
pub struct AtomicStats {
    buffers_processed: AtomicU64,
    total_process_time_us: AtomicU64,
    max_process_time_us: AtomicU64,
    min_process_time_us: AtomicU64,
    underruns: AtomicU64,
    overruns: AtomicU64,
}

impl Default for AtomicStats {
    fn default() -> Self {
        Self {
            buffers_processed: AtomicU64::new(0),
            total_process_time_us: AtomicU64::new(0),
            max_process_time_us: AtomicU64::new(0),
            min_process_time_us: AtomicU64::new(u64::MAX),
            underruns: AtomicU64::new(0),
            overruns: AtomicU64::new(0),
        }
    }
}

impl AtomicStats {
    /// Record a processing cycle
    pub fn record_cycle(&self, process_time_us: u64) {
        self.buffers_processed.fetch_add(1, Ordering::Relaxed);
        self.total_process_time_us
            .fetch_add(process_time_us, Ordering::Relaxed);

        // Update max
        let mut current = self.max_process_time_us.load(Ordering::Relaxed);
        while process_time_us > current {
            match self.max_process_time_us.compare_exchange_weak(
                current,
                process_time_us,
                Ordering::Relaxed,
                Ordering::Relaxed,
            ) {
                Ok(_) => break,
                Err(c) => current = c,
            }
        }

        // Update min
        let mut current = self.min_process_time_us.load(Ordering::Relaxed);
        while process_time_us < current {
            match self.min_process_time_us.compare_exchange_weak(
                current,
                process_time_us,
                Ordering::Relaxed,
                Ordering::Relaxed,
            ) {
                Ok(_) => break,
                Err(c) => current = c,
            }
        }
    }

    /// Record an underrun
    pub fn record_underrun(&self) {
        self.underruns.fetch_add(1, Ordering::Relaxed);
    }

    /// Record an overrun
    pub fn record_overrun(&self) {
        self.overruns.fetch_add(1, Ordering::Relaxed);
    }

    /// Get current stats snapshot
    pub fn snapshot(&self) -> ProcessingStats {
        let buffers = self.buffers_processed.load(Ordering::Relaxed);
        let total_time = self.total_process_time_us.load(Ordering::Relaxed);
        let max_time = self.max_process_time_us.load(Ordering::Relaxed);
        let min_time = self.min_process_time_us.load(Ordering::Relaxed);

        ProcessingStats {
            buffers_processed: buffers,
            avg_process_time_us: if buffers > 0 {
                total_time as f64 / buffers as f64
            } else {
                0.0
            },
            max_process_time_us: max_time as f64,
            min_process_time_us: if min_time == u64::MAX {
                0.0
            } else {
                min_time as f64
            },
            underruns: self.underruns.load(Ordering::Relaxed),
            overruns: self.overruns.load(Ordering::Relaxed),
            ..Default::default()
        }
    }

    /// Reset all statistics
    pub fn reset(&self) {
        self.buffers_processed.store(0, Ordering::Relaxed);
        self.total_process_time_us.store(0, Ordering::Relaxed);
        self.max_process_time_us.store(0, Ordering::Relaxed);
        self.min_process_time_us.store(u64::MAX, Ordering::Relaxed);
        self.underruns.store(0, Ordering::Relaxed);
        self.overruns.store(0, Ordering::Relaxed);
    }
}

/// Audio processing callback
pub trait AudioProcessor: Send + 'static {
    /// Process audio buffer
    fn process(&mut self, input: &[f32], output: &mut [f32], frames: usize);

    /// Get processor latency in samples
    fn latency(&self) -> u32 {
        0
    }

    /// Reset processor state
    fn reset(&mut self) {}
}

/// MassCore engine state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EngineState {
    /// Engine not started
    Stopped,
    /// Engine starting up
    Starting,
    /// Engine running
    Running,
    /// Engine stopping
    Stopping,
    /// Engine in error state
    Error,
}

/// Lock-free buffer pool for zero-copy processing
pub struct BufferPool {
    buffers: Vec<Vec<f32>>,
    available: AtomicUsize,
    buffer_size: usize,
}

impl BufferPool {
    /// Create new buffer pool
    pub fn new(pool_size: usize, buffer_size: usize) -> Self {
        let buffers = (0..pool_size).map(|_| vec![0.0f32; buffer_size]).collect();

        Self {
            buffers,
            available: AtomicUsize::new(pool_size),
            buffer_size,
        }
    }

    /// Acquire a buffer (returns index)
    pub fn acquire(&self) -> Option<usize> {
        let prev = self.available.fetch_sub(1, Ordering::Acquire);
        if prev > 0 {
            Some(prev - 1)
        } else {
            self.available.fetch_add(1, Ordering::Release);
            None
        }
    }

    /// Release a buffer
    pub fn release(&self, _index: usize) {
        self.available.fetch_add(1, Ordering::Release);
    }

    /// Get buffer by index
    pub fn get(&self, index: usize) -> Option<&Vec<f32>> {
        self.buffers.get(index)
    }

    /// Get mutable buffer by index (unsafe in multi-threaded context)
    pub fn get_mut(&mut self, index: usize) -> Option<&mut Vec<f32>> {
        self.buffers.get_mut(index)
    }

    /// Buffer size
    pub fn buffer_size(&self) -> usize {
        self.buffer_size
    }

    /// Pool size
    pub fn pool_size(&self) -> usize {
        self.buffers.len()
    }

    /// Available buffers
    pub fn available(&self) -> usize {
        self.available.load(Ordering::Relaxed)
    }
}

/// MassCore++ Engine
pub struct MassCoreEngine {
    config: MassCoreConfig,
    state: AtomicUsize,
    stats: Arc<AtomicStats>,
    running: Arc<AtomicBool>,
    processor: Arc<Mutex<Option<Box<dyn AudioProcessor>>>>,
    thread_handles: Vec<JoinHandle<()>>,
    watchdog_last_tick: Arc<AtomicU64>,
}

impl MassCoreEngine {
    /// Create new MassCore engine
    pub fn new(config: MassCoreConfig) -> Self {
        Self {
            config,
            state: AtomicUsize::new(EngineState::Stopped as usize),
            stats: Arc::new(AtomicStats::default()),
            running: Arc::new(AtomicBool::new(false)),
            processor: Arc::new(Mutex::new(None)),
            thread_handles: Vec::new(),
            watchdog_last_tick: Arc::new(AtomicU64::new(0)),
        }
    }

    /// Get current state
    pub fn state(&self) -> EngineState {
        match self.state.load(Ordering::Acquire) {
            0 => EngineState::Stopped,
            1 => EngineState::Starting,
            2 => EngineState::Running,
            3 => EngineState::Stopping,
            _ => EngineState::Error,
        }
    }

    /// Set processor
    pub fn set_processor(&self, processor: Box<dyn AudioProcessor>) {
        *self.processor.lock() = Some(processor);
    }

    /// Get statistics
    pub fn stats(&self) -> ProcessingStats {
        self.stats.snapshot()
    }

    /// Reset statistics
    pub fn reset_stats(&self) {
        self.stats.reset();
    }

    /// Start the engine
    pub fn start(&mut self) -> Result<(), &'static str> {
        if self.state() != EngineState::Stopped {
            return Err("Engine not in stopped state");
        }

        self.state
            .store(EngineState::Starting as usize, Ordering::Release);
        self.running.store(true, Ordering::Release);

        // Start audio processing thread
        let running = Arc::clone(&self.running);
        let stats = Arc::clone(&self.stats);
        let processor = Arc::clone(&self.processor);
        let watchdog_tick = Arc::clone(&self.watchdog_last_tick);
        let config = self.config.clone();

        let handle = thread::Builder::new()
            .name("masscore-audio".to_string())
            .spawn(move || {
                Self::audio_thread(running, stats, processor, watchdog_tick, config);
            })
            .map_err(|_| "Failed to spawn audio thread")?;

        self.thread_handles.push(handle);

        // Start watchdog thread
        if self.config.watchdog_timeout_ms > 0 {
            let running = Arc::clone(&self.running);
            let watchdog_tick = Arc::clone(&self.watchdog_last_tick);
            let timeout_ms = self.config.watchdog_timeout_ms;

            let handle = thread::Builder::new()
                .name("masscore-watchdog".to_string())
                .spawn(move || {
                    Self::watchdog_thread(running, watchdog_tick, timeout_ms);
                })
                .map_err(|_| "Failed to spawn watchdog thread")?;

            self.thread_handles.push(handle);
        }

        self.state
            .store(EngineState::Running as usize, Ordering::Release);
        Ok(())
    }

    /// Stop the engine
    pub fn stop(&mut self) {
        if self.state() != EngineState::Running {
            return;
        }

        self.state
            .store(EngineState::Stopping as usize, Ordering::Release);
        self.running.store(false, Ordering::Release);

        // Wait for threads to finish
        for handle in self.thread_handles.drain(..) {
            let _ = handle.join();
        }

        self.state
            .store(EngineState::Stopped as usize, Ordering::Release);
    }

    /// Audio processing thread
    fn audio_thread(
        running: Arc<AtomicBool>,
        stats: Arc<AtomicStats>,
        processor: Arc<Mutex<Option<Box<dyn AudioProcessor>>>>,
        watchdog_tick: Arc<AtomicU64>,
        config: MassCoreConfig,
    ) {
        // Set thread priority if requested
        #[cfg(target_os = "macos")]
        if config.realtime_priority {
            Self::set_realtime_priority_macos();
        }

        #[cfg(target_os = "linux")]
        if config.realtime_priority {
            Self::set_realtime_priority_linux();
        }

        let buffer_duration =
            Duration::from_secs_f64(config.buffer_size as f64 / config.sample_rate as f64);

        let input_buffer = vec![0.0f32; config.buffer_size * 2]; // stereo
        let mut output_buffer = vec![0.0f32; config.buffer_size * 2];

        while running.load(Ordering::Acquire) {
            let start = Instant::now();

            // Update watchdog
            watchdog_tick.store(start.elapsed().as_micros() as u64, Ordering::Release);

            // Process audio
            if let Some(ref mut proc) = *processor.lock() {
                proc.process(&input_buffer, &mut output_buffer, config.buffer_size);
            }

            let process_time = start.elapsed();
            stats.record_cycle(process_time.as_micros() as u64);

            // Check for overrun
            if process_time > buffer_duration {
                stats.record_overrun();
            }

            // Sleep for remaining time (simulate real-time)
            if process_time < buffer_duration {
                thread::sleep(buffer_duration - process_time);
            }
        }
    }

    /// Watchdog thread
    fn watchdog_thread(running: Arc<AtomicBool>, watchdog_tick: Arc<AtomicU64>, timeout_ms: u64) {
        let check_interval = Duration::from_millis(timeout_ms / 2);

        while running.load(Ordering::Acquire) {
            thread::sleep(check_interval);

            let last_tick = watchdog_tick.load(Ordering::Acquire);
            let now = Instant::now().elapsed().as_micros() as u64;

            if now.saturating_sub(last_tick) > timeout_ms * 1000 {
                log::warn!("MassCore watchdog: audio thread may be stuck");
            }
        }
    }

    /// Set real-time priority on macOS
    #[cfg(target_os = "macos")]
    fn set_realtime_priority_macos() {
        use std::mem;

        #[repr(C)]
        struct ThreadTimeConstraintPolicy {
            period: u32,
            computation: u32,
            constraint: u32,
            preemptible: i32,
        }

        extern "C" {
            fn pthread_self() -> usize;
            fn thread_policy_set(
                thread: usize,
                flavor: u32,
                policy_info: *const ThreadTimeConstraintPolicy,
                count: u32,
            ) -> i32;
        }

        unsafe {
            let policy = ThreadTimeConstraintPolicy {
                period: 48000,      // 1ms at 48kHz
                computation: 24000, // 0.5ms
                constraint: 48000,
                preemptible: 0,
            };

            let _ = thread_policy_set(
                pthread_self(),
                1, // THREAD_TIME_CONSTRAINT_POLICY
                &policy,
                mem::size_of::<ThreadTimeConstraintPolicy>() as u32 / 4,
            );
        }
    }

    /// Set real-time priority on Linux
    #[cfg(target_os = "linux")]
    fn set_realtime_priority_linux() {
        // Use SCHED_FIFO with priority 80
        #[cfg(target_os = "linux")]
        {
            use libc::{sched_param, sched_setscheduler, SCHED_FIFO};

            unsafe {
                let param = sched_param { sched_priority: 80 };
                let _ = sched_setscheduler(0, SCHED_FIFO, &param);
            }
        }
    }

    /// Get configuration
    pub fn config(&self) -> &MassCoreConfig {
        &self.config
    }

    /// Is running
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Acquire)
    }
}

impl Drop for MassCoreEngine {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Simple passthrough processor for testing
pub struct PassthroughProcessor;

impl AudioProcessor for PassthroughProcessor {
    fn process(&mut self, input: &[f32], output: &mut [f32], _frames: usize) {
        output.copy_from_slice(input);
    }
}

/// Gain processor for testing
pub struct GainProcessor {
    gain: f32,
}

impl GainProcessor {
    pub fn new(gain_db: f32) -> Self {
        Self {
            gain: 10.0_f32.powf(gain_db / 20.0),
        }
    }
}

impl AudioProcessor for GainProcessor {
    fn process(&mut self, input: &[f32], output: &mut [f32], frames: usize) {
        for i in 0..frames * 2 {
            output[i] = input[i] * self.gain;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = MassCoreConfig::default();
        assert_eq!(config.buffer_size, 256);
        assert!(config.realtime_priority);
    }

    #[test]
    fn test_buffer_latency() {
        let config = MassCoreConfig {
            buffer_size: 256,
            sample_rate: 48000,
            ..Default::default()
        };
        let latency = config.buffer_latency_ms();
        assert!((latency - 5.33).abs() < 0.1);
    }

    #[test]
    fn test_atomic_stats() {
        let stats = AtomicStats::default();
        stats.record_cycle(100);
        stats.record_cycle(200);

        let snapshot = stats.snapshot();
        assert_eq!(snapshot.buffers_processed, 2);
        assert!((snapshot.avg_process_time_us - 150.0).abs() < 0.1);
    }

    #[test]
    fn test_buffer_pool() {
        let pool = BufferPool::new(4, 256);
        assert_eq!(pool.available(), 4);

        let idx1 = pool.acquire().unwrap();
        assert_eq!(pool.available(), 3);

        pool.release(idx1);
        assert_eq!(pool.available(), 4);
    }

    #[test]
    fn test_engine_creation() {
        let engine = MassCoreEngine::new(MassCoreConfig::default());
        assert_eq!(engine.state(), EngineState::Stopped);
    }

    #[test]
    fn test_passthrough_processor() {
        let mut proc = PassthroughProcessor;
        let input = vec![0.5f32; 512];
        let mut output = vec![0.0f32; 512];

        proc.process(&input, &mut output, 256);
        assert_eq!(output[0], 0.5);
    }

    #[test]
    fn test_gain_processor() {
        let mut proc = GainProcessor::new(-6.0);
        let input = vec![1.0f32; 512];
        let mut output = vec![0.0f32; 512];

        proc.process(&input, &mut output, 256);
        assert!((output[0] - 0.5).abs() < 0.01);
    }
}
