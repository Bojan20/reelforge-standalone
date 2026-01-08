//! Hybrid GPU/CPU Scheduler
//!
//! UNIQUE: Intelligent workload distribution between GPU and CPU.
//!
//! Features:
//! - Dynamic load balancing
//! - Latency-aware scheduling
//! - Automatic fallback
//! - Multi-GPU support
//! - Real-time performance monitoring

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant};

/// Processing target
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcessingTarget {
    /// CPU (always available)
    Cpu,
    /// Primary GPU
    GpuPrimary,
    /// Secondary GPU (if available)
    GpuSecondary,
    /// Hybrid (split workload)
    Hybrid,
}

/// Task type for scheduling
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskType {
    /// FFT computation
    Fft,
    /// EQ processing
    Eq,
    /// Dynamics (compressor/limiter)
    Dynamics,
    /// Convolution
    Convolution,
    /// Spectrum analysis
    SpectrumAnalysis,
    /// Waveform generation
    WaveformGeneration,
}

impl TaskType {
    /// Estimated complexity (affects scheduling)
    pub fn complexity(&self) -> u32 {
        match self {
            TaskType::Fft => 100,
            TaskType::Eq => 50,
            TaskType::Dynamics => 30,
            TaskType::Convolution => 200,
            TaskType::SpectrumAnalysis => 80,
            TaskType::WaveformGeneration => 40,
        }
    }

    /// Minimum samples for GPU to be efficient
    pub fn gpu_threshold(&self) -> usize {
        match self {
            TaskType::Fft => 512,
            TaskType::Eq => 256,
            TaskType::Dynamics => 128,
            TaskType::Convolution => 1024,
            TaskType::SpectrumAnalysis => 2048,
            TaskType::WaveformGeneration => 4096,
        }
    }

    /// Is this task latency-critical?
    pub fn is_latency_critical(&self) -> bool {
        matches!(self, TaskType::Eq | TaskType::Dynamics | TaskType::Convolution)
    }
}

/// Task descriptor
#[derive(Debug, Clone)]
pub struct GpuTask {
    /// Task type
    pub task_type: TaskType,
    /// Number of samples to process
    pub sample_count: usize,
    /// Channel count
    pub channels: usize,
    /// Priority (higher = more urgent)
    pub priority: u32,
    /// Deadline (for latency-critical tasks)
    pub deadline: Option<Instant>,
    /// Task ID
    pub id: u64,
}

/// Execution statistics
#[derive(Debug, Clone, Default)]
pub struct ExecutionStats {
    pub cpu_time_us: u64,
    pub gpu_time_us: u64,
    pub transfer_time_us: u64,
    pub total_time_us: u64,
    pub samples_processed: u64,
}

/// GPU device info
#[derive(Debug, Clone)]
pub struct GpuDeviceInfo {
    pub name: String,
    pub vendor: String,
    pub memory_mb: u32,
    pub compute_units: u32,
    pub max_workgroup_size: u32,
    pub supports_fp64: bool,
}

/// Scheduler configuration
#[derive(Debug, Clone)]
pub struct SchedulerConfig {
    /// Enable GPU processing
    pub enable_gpu: bool,
    /// Maximum GPU utilization target (0.0-1.0)
    pub max_gpu_utilization: f64,
    /// Latency budget in microseconds
    pub latency_budget_us: u64,
    /// Enable hybrid mode
    pub enable_hybrid: bool,
    /// Minimum batch size for GPU
    pub min_gpu_batch: usize,
    /// Enable auto-tuning
    pub auto_tune: bool,
}

impl Default for SchedulerConfig {
    fn default() -> Self {
        Self {
            enable_gpu: true,
            max_gpu_utilization: 0.8,
            latency_budget_us: 3000, // 3ms
            enable_hybrid: true,
            min_gpu_batch: 256,
            auto_tune: true,
        }
    }
}

/// Performance history for auto-tuning
struct PerformanceHistory {
    cpu_times: VecDeque<u64>,
    gpu_times: VecDeque<u64>,
    max_history: usize,
}

impl PerformanceHistory {
    fn new(max_history: usize) -> Self {
        Self {
            cpu_times: VecDeque::with_capacity(max_history),
            gpu_times: VecDeque::with_capacity(max_history),
            max_history,
        }
    }

    fn add_cpu_time(&mut self, time_us: u64) {
        if self.cpu_times.len() >= self.max_history {
            self.cpu_times.pop_front();
        }
        self.cpu_times.push_back(time_us);
    }

    fn add_gpu_time(&mut self, time_us: u64) {
        if self.gpu_times.len() >= self.max_history {
            self.gpu_times.pop_front();
        }
        self.gpu_times.push_back(time_us);
    }

    fn avg_cpu_time(&self) -> f64 {
        if self.cpu_times.is_empty() {
            return 0.0;
        }
        self.cpu_times.iter().sum::<u64>() as f64 / self.cpu_times.len() as f64
    }

    fn avg_gpu_time(&self) -> f64 {
        if self.gpu_times.is_empty() {
            return f64::MAX; // Assume GPU is slow if no data
        }
        self.gpu_times.iter().sum::<u64>() as f64 / self.gpu_times.len() as f64
    }
}

/// Hybrid GPU/CPU scheduler
pub struct HybridScheduler {
    /// Configuration
    config: SchedulerConfig,
    /// GPU available
    gpu_available: AtomicBool,
    /// GPU info
    gpu_info: Option<GpuDeviceInfo>,
    /// Task ID counter
    next_task_id: AtomicU64,
    /// Performance history per task type
    performance_history: [PerformanceHistory; 6],
    /// Current GPU utilization
    gpu_utilization: AtomicU64, // Fixed-point: value / 1000
    /// Tasks scheduled to GPU
    gpu_task_count: AtomicU64,
    /// Tasks scheduled to CPU
    cpu_task_count: AtomicU64,
}

impl HybridScheduler {
    /// Create new scheduler
    pub fn new(config: SchedulerConfig) -> Self {
        Self {
            config,
            gpu_available: AtomicBool::new(false),
            gpu_info: None,
            next_task_id: AtomicU64::new(0),
            performance_history: [
                PerformanceHistory::new(32),
                PerformanceHistory::new(32),
                PerformanceHistory::new(32),
                PerformanceHistory::new(32),
                PerformanceHistory::new(32),
                PerformanceHistory::new(32),
            ],
            gpu_utilization: AtomicU64::new(0),
            gpu_task_count: AtomicU64::new(0),
            cpu_task_count: AtomicU64::new(0),
        }
    }

    /// Initialize GPU
    pub fn init_gpu(&mut self) -> Result<(), String> {
        // Would initialize wgpu device here
        // For now, simulate detection

        #[cfg(feature = "gpu")]
        {
            self.gpu_info = Some(GpuDeviceInfo {
                name: "Simulated GPU".to_string(),
                vendor: "Vendor".to_string(),
                memory_mb: 8192,
                compute_units: 64,
                max_workgroup_size: 256,
                supports_fp64: false,
            });
            self.gpu_available.store(true, Ordering::SeqCst);
        }

        Ok(())
    }

    /// Check if GPU is available
    pub fn is_gpu_available(&self) -> bool {
        self.gpu_available.load(Ordering::SeqCst)
    }

    /// Get GPU info
    pub fn gpu_info(&self) -> Option<&GpuDeviceInfo> {
        self.gpu_info.as_ref()
    }

    /// Schedule a task
    pub fn schedule(&self, task: &GpuTask) -> ProcessingTarget {
        // Check if GPU is available and enabled
        if !self.config.enable_gpu || !self.is_gpu_available() {
            self.cpu_task_count.fetch_add(1, Ordering::Relaxed);
            return ProcessingTarget::Cpu;
        }

        // Check if task is too small for GPU
        if task.sample_count < task.task_type.gpu_threshold() {
            self.cpu_task_count.fetch_add(1, Ordering::Relaxed);
            return ProcessingTarget::Cpu;
        }

        // Check latency constraints
        if task.task_type.is_latency_critical() {
            if let Some(deadline) = task.deadline {
                let remaining = deadline.saturating_duration_since(Instant::now());
                if remaining.as_micros() < self.config.latency_budget_us as u128 {
                    // Not enough time for GPU round-trip
                    self.cpu_task_count.fetch_add(1, Ordering::Relaxed);
                    return ProcessingTarget::Cpu;
                }
            }
        }

        // Check GPU utilization
        let current_util = self.gpu_utilization.load(Ordering::Relaxed) as f64 / 1000.0;
        if current_util > self.config.max_gpu_utilization {
            self.cpu_task_count.fetch_add(1, Ordering::Relaxed);
            return ProcessingTarget::Cpu;
        }

        // Auto-tune based on historical performance
        if self.config.auto_tune {
            let task_idx = task.task_type as usize;
            let cpu_avg = self.performance_history[task_idx].avg_cpu_time();
            let gpu_avg = self.performance_history[task_idx].avg_gpu_time();

            // Account for transfer overhead (estimate ~500us)
            let gpu_total = gpu_avg + 500.0;

            if cpu_avg < gpu_total && cpu_avg > 0.0 {
                // CPU is faster for this task type
                self.cpu_task_count.fetch_add(1, Ordering::Relaxed);
                return ProcessingTarget::Cpu;
            }
        }

        // Use hybrid for large tasks
        if self.config.enable_hybrid && task.sample_count > task.task_type.gpu_threshold() * 4 {
            self.gpu_task_count.fetch_add(1, Ordering::Relaxed);
            return ProcessingTarget::Hybrid;
        }

        // Schedule to GPU
        self.gpu_task_count.fetch_add(1, Ordering::Relaxed);
        ProcessingTarget::GpuPrimary
    }

    /// Create a new task
    pub fn create_task(
        &self,
        task_type: TaskType,
        sample_count: usize,
        channels: usize,
        priority: u32,
        deadline: Option<Duration>,
    ) -> GpuTask {
        let deadline_instant = deadline.map(|d| Instant::now() + d);

        GpuTask {
            task_type,
            sample_count,
            channels,
            priority,
            deadline: deadline_instant,
            id: self.next_task_id.fetch_add(1, Ordering::Relaxed),
        }
    }

    /// Report task completion
    pub fn report_completion(&mut self, task: &GpuTask, stats: ExecutionStats, target: ProcessingTarget) {
        let task_idx = task.task_type as usize;

        match target {
            ProcessingTarget::Cpu => {
                self.performance_history[task_idx].add_cpu_time(stats.cpu_time_us);
            }
            ProcessingTarget::GpuPrimary | ProcessingTarget::GpuSecondary => {
                self.performance_history[task_idx].add_gpu_time(stats.gpu_time_us);
            }
            ProcessingTarget::Hybrid => {
                self.performance_history[task_idx].add_cpu_time(stats.cpu_time_us);
                self.performance_history[task_idx].add_gpu_time(stats.gpu_time_us);
            }
        }
    }

    /// Update GPU utilization
    pub fn update_utilization(&self, utilization: f64) {
        let fixed = (utilization * 1000.0) as u64;
        self.gpu_utilization.store(fixed, Ordering::Relaxed);
    }

    /// Get statistics
    pub fn get_stats(&self) -> SchedulerStats {
        SchedulerStats {
            gpu_task_count: self.gpu_task_count.load(Ordering::Relaxed),
            cpu_task_count: self.cpu_task_count.load(Ordering::Relaxed),
            gpu_utilization: self.gpu_utilization.load(Ordering::Relaxed) as f64 / 1000.0,
            gpu_available: self.is_gpu_available(),
        }
    }

    /// Reset statistics
    pub fn reset_stats(&self) {
        self.gpu_task_count.store(0, Ordering::Relaxed);
        self.cpu_task_count.store(0, Ordering::Relaxed);
    }
}

/// Scheduler statistics
#[derive(Debug, Clone)]
pub struct SchedulerStats {
    pub gpu_task_count: u64,
    pub cpu_task_count: u64,
    pub gpu_utilization: f64,
    pub gpu_available: bool,
}

/// Batch scheduler for grouping similar tasks
pub struct BatchScheduler {
    /// Pending tasks by type
    pending_tasks: [Vec<GpuTask>; 6],
    /// Maximum batch size
    max_batch_size: usize,
    /// Batch timeout
    batch_timeout: Duration,
    /// Last flush time per type
    last_flush: [Instant; 6],
}

impl BatchScheduler {
    pub fn new(max_batch_size: usize, batch_timeout: Duration) -> Self {
        let now = Instant::now();
        Self {
            pending_tasks: Default::default(),
            max_batch_size,
            batch_timeout,
            last_flush: [now; 6],
        }
    }

    /// Add task to batch
    pub fn add_task(&mut self, task: GpuTask) -> Option<Vec<GpuTask>> {
        let idx = task.task_type as usize;
        self.pending_tasks[idx].push(task);

        // Check if batch is full
        if self.pending_tasks[idx].len() >= self.max_batch_size {
            return Some(self.flush_batch(idx));
        }

        // Check timeout
        if self.last_flush[idx].elapsed() >= self.batch_timeout {
            if !self.pending_tasks[idx].is_empty() {
                return Some(self.flush_batch(idx));
            }
        }

        None
    }

    /// Flush a specific batch
    fn flush_batch(&mut self, idx: usize) -> Vec<GpuTask> {
        self.last_flush[idx] = Instant::now();
        std::mem::take(&mut self.pending_tasks[idx])
    }

    /// Flush all pending batches
    pub fn flush_all(&mut self) -> Vec<Vec<GpuTask>> {
        let mut result = Vec::new();
        for idx in 0..6 {
            if !self.pending_tasks[idx].is_empty() {
                result.push(self.flush_batch(idx));
            }
        }
        result
    }

    /// Check for timeouts and flush if needed
    pub fn check_timeouts(&mut self) -> Vec<Vec<GpuTask>> {
        let mut result = Vec::new();
        for idx in 0..6 {
            if !self.pending_tasks[idx].is_empty()
                && self.last_flush[idx].elapsed() >= self.batch_timeout
            {
                result.push(self.flush_batch(idx));
            }
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scheduler_creation() {
        let config = SchedulerConfig::default();
        let scheduler = HybridScheduler::new(config);
        assert!(!scheduler.is_gpu_available()); // No GPU by default
    }

    #[test]
    fn test_task_scheduling_cpu_fallback() {
        let config = SchedulerConfig {
            enable_gpu: true,
            ..Default::default()
        };
        let scheduler = HybridScheduler::new(config);

        let task = scheduler.create_task(TaskType::Eq, 128, 2, 1, None);
        let target = scheduler.schedule(&task);

        // Should fall back to CPU (no GPU available)
        assert_eq!(target, ProcessingTarget::Cpu);
    }

    #[test]
    fn test_task_type_thresholds() {
        assert!(TaskType::Fft.gpu_threshold() > 0);
        assert!(TaskType::Convolution.gpu_threshold() > TaskType::Eq.gpu_threshold());
    }

    #[test]
    fn test_batch_scheduler() {
        let mut batch = BatchScheduler::new(4, Duration::from_millis(10));

        let scheduler = HybridScheduler::new(SchedulerConfig::default());

        // Add 3 tasks - shouldn't flush yet
        for _ in 0..3 {
            let task = scheduler.create_task(TaskType::Fft, 1024, 2, 1, None);
            assert!(batch.add_task(task).is_none());
        }

        // 4th task should trigger flush
        let task = scheduler.create_task(TaskType::Fft, 1024, 2, 1, None);
        let flushed = batch.add_task(task);
        assert!(flushed.is_some());
        assert_eq!(flushed.unwrap().len(), 4);
    }

    #[test]
    fn test_performance_history() {
        let mut history = PerformanceHistory::new(10);

        for i in 0..5 {
            history.add_cpu_time(100 + i * 10);
            history.add_gpu_time(50 + i * 5);
        }

        assert!(history.avg_cpu_time() > 0.0);
        assert!(history.avg_gpu_time() > 0.0);
        assert!(history.avg_cpu_time() > history.avg_gpu_time());
    }

    #[test]
    fn test_scheduler_stats() {
        let config = SchedulerConfig::default();
        let scheduler = HybridScheduler::new(config);

        let task = scheduler.create_task(TaskType::Eq, 128, 2, 1, None);
        scheduler.schedule(&task);

        let stats = scheduler.get_stats();
        assert!(stats.cpu_task_count > 0 || stats.gpu_task_count > 0);
    }
}
