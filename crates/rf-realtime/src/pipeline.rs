//! Zero-Latency Processing Pipeline
//!
//! ULTIMATIVNI pipeline design:
//! - Direct path processing (0 samples latency)
//! - Lookahead compensation manager
//! - Plugin Delay Compensation (PDC)
//! - Per-path latency reporting

use std::collections::HashMap;
use portable_atomic::{AtomicU32, Ordering};

/// Pipeline processing mode
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PipelineMode {
    /// Zero latency - no lookahead, minimum phase
    ZeroLatency,
    /// Low latency - small lookahead, good quality
    LowLatency,
    /// Normal - balanced latency and quality
    Normal,
    /// High quality - maximum lookahead, best quality
    HighQuality,
    /// Custom latency budget
    Custom { max_latency_samples: u32 },
}

impl PipelineMode {
    /// Get maximum allowed latency in samples
    pub fn max_latency(&self, sample_rate: f64) -> u32 {
        match self {
            Self::ZeroLatency => 0,
            Self::LowLatency => (sample_rate * 0.001) as u32,    // 1ms
            Self::Normal => (sample_rate * 0.005) as u32,        // 5ms
            Self::HighQuality => (sample_rate * 0.020) as u32,   // 20ms
            Self::Custom { max_latency_samples } => *max_latency_samples,
        }
    }
}

/// Latency compensation slot
#[derive(Debug, Clone)]
pub struct LatencySlot {
    /// Delay buffer for compensation
    buffer: Vec<f64>,
    /// Current write position
    write_pos: usize,
    /// Delay in samples
    delay_samples: usize,
}

impl LatencySlot {
    pub fn new(max_delay: usize, channels: usize) -> Self {
        Self {
            buffer: vec![0.0; max_delay * channels],
            write_pos: 0,
            delay_samples: 0,
        }
    }

    pub fn set_delay(&mut self, samples: usize) {
        self.delay_samples = samples.min(self.buffer.len());
    }

    pub fn process(&mut self, input: f64) -> f64 {
        if self.delay_samples == 0 {
            return input;
        }

        let read_pos = (self.write_pos + self.buffer.len() - self.delay_samples) % self.buffer.len();
        let output = self.buffer[read_pos];
        self.buffer[self.write_pos] = input;
        self.write_pos = (self.write_pos + 1) % self.buffer.len();
        output
    }

    pub fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
    }
}

/// Processing path in the pipeline
#[derive(Debug, Clone)]
pub struct ProcessingPath {
    /// Path ID
    pub id: u32,
    /// Path name
    pub name: String,
    /// Processors in this path
    pub processors: Vec<ProcessorSlot>,
    /// Total latency of this path
    pub total_latency: u32,
    /// Compensation delay needed
    pub compensation_delay: u32,
    /// Latency compensation buffer
    compensation: LatencySlot,
}

/// Slot for a processor in the path
#[derive(Debug, Clone)]
pub struct ProcessorSlot {
    pub id: u32,
    pub name: String,
    pub latency_samples: u32,
    pub enabled: bool,
}

/// Plugin Delay Compensation (PDC) Manager
pub struct PdcManager {
    /// All processing paths
    paths: HashMap<u32, ProcessingPath>,
    /// Maximum latency across all paths
    max_latency: AtomicU32,
    /// Current mode
    mode: PipelineMode,
    /// Sample rate
    sample_rate: f64,
}

impl PdcManager {
    pub fn new(sample_rate: f64, mode: PipelineMode) -> Self {
        Self {
            paths: HashMap::new(),
            max_latency: AtomicU32::new(0),
            mode,
            sample_rate,
        }
    }

    /// Add a processing path
    pub fn add_path(&mut self, id: u32, name: String) {
        let max_delay = self.mode.max_latency(self.sample_rate) as usize;
        self.paths.insert(id, ProcessingPath {
            id,
            name,
            processors: Vec::new(),
            total_latency: 0,
            compensation_delay: 0,
            compensation: LatencySlot::new(max_delay.max(8192), 2),
        });
    }

    /// Add a processor to a path
    pub fn add_processor(&mut self, path_id: u32, processor: ProcessorSlot) {
        if let Some(path) = self.paths.get_mut(&path_id) {
            path.total_latency += processor.latency_samples;
            path.processors.push(processor);
            self.recalculate_compensation();
        }
    }

    /// Remove a processor from a path
    pub fn remove_processor(&mut self, path_id: u32, processor_id: u32) {
        if let Some(path) = self.paths.get_mut(&path_id) {
            if let Some(idx) = path.processors.iter().position(|p| p.id == processor_id) {
                let latency = path.processors[idx].latency_samples;
                path.total_latency = path.total_latency.saturating_sub(latency);
                path.processors.remove(idx);
                self.recalculate_compensation();
            }
        }
    }

    /// Update processor latency
    pub fn update_latency(&mut self, path_id: u32, processor_id: u32, new_latency: u32) {
        if let Some(path) = self.paths.get_mut(&path_id) {
            if let Some(processor) = path.processors.iter_mut().find(|p| p.id == processor_id) {
                let old_latency = processor.latency_samples;
                processor.latency_samples = new_latency;
                path.total_latency = path.total_latency.saturating_sub(old_latency) + new_latency;
                self.recalculate_compensation();
            }
        }
    }

    /// Recalculate compensation for all paths
    fn recalculate_compensation(&mut self) {
        // Find maximum latency
        let max = self.paths.values()
            .map(|p| p.total_latency)
            .max()
            .unwrap_or(0);

        self.max_latency.store(max, Ordering::Release);

        // Set compensation for each path
        for path in self.paths.values_mut() {
            path.compensation_delay = max.saturating_sub(path.total_latency);
            path.compensation.set_delay(path.compensation_delay as usize);
        }
    }

    /// Get total pipeline latency
    pub fn total_latency(&self) -> u32 {
        self.max_latency.load(Ordering::Acquire)
    }

    /// Process compensation for a path
    pub fn process_compensation(&mut self, path_id: u32, sample: f64) -> f64 {
        if let Some(path) = self.paths.get_mut(&path_id) {
            path.compensation.process(sample)
        } else {
            sample
        }
    }

    /// Get path info
    pub fn get_path(&self, id: u32) -> Option<&ProcessingPath> {
        self.paths.get(&id)
    }

    /// Get all paths
    pub fn paths(&self) -> impl Iterator<Item = &ProcessingPath> {
        self.paths.values()
    }

    /// Set pipeline mode
    pub fn set_mode(&mut self, mode: PipelineMode) {
        self.mode = mode;
        self.recalculate_compensation();
    }

    /// Reset all compensation buffers
    pub fn reset(&mut self) {
        for path in self.paths.values_mut() {
            path.compensation.reset();
        }
    }
}

/// Zero-latency processing pipeline
pub struct ZeroLatencyPipeline {
    /// PDC manager
    pdc: PdcManager,
    /// Direct path (no latency)
    direct_path: Option<u32>,
    /// Lookahead paths
    lookahead_paths: Vec<u32>,
    /// Block size
    block_size: usize,
    /// Sample rate
    sample_rate: f64,
}

impl ZeroLatencyPipeline {
    pub fn new(sample_rate: f64, block_size: usize) -> Self {
        Self {
            pdc: PdcManager::new(sample_rate, PipelineMode::ZeroLatency),
            direct_path: None,
            lookahead_paths: Vec::new(),
            block_size,
            sample_rate,
        }
    }

    /// Create direct path (zero latency)
    pub fn create_direct_path(&mut self, name: &str) -> u32 {
        let id = 0;
        self.pdc.add_path(id, name.to_string());
        self.direct_path = Some(id);
        id
    }

    /// Create lookahead path
    pub fn create_lookahead_path(&mut self, name: &str) -> u32 {
        let id = (self.lookahead_paths.len() + 1) as u32;
        self.pdc.add_path(id, name.to_string());
        self.lookahead_paths.push(id);
        id
    }

    /// Add processor to path
    pub fn add_processor(&mut self, path_id: u32, name: &str, latency: u32) -> u32 {
        let processor_id = self.pdc.get_path(path_id)
            .map(|p| p.processors.len() as u32)
            .unwrap_or(0);

        self.pdc.add_processor(path_id, ProcessorSlot {
            id: processor_id,
            name: name.to_string(),
            latency_samples: latency,
            enabled: true,
        });

        processor_id
    }

    /// Get total pipeline latency
    pub fn total_latency(&self) -> u32 {
        self.pdc.total_latency()
    }

    /// Get latency in milliseconds
    pub fn latency_ms(&self) -> f64 {
        self.total_latency() as f64 / self.sample_rate * 1000.0
    }

    /// Process with zero-latency direct path
    pub fn process_direct(&mut self, input: &[f64], output: &mut [f64]) {
        // Direct path has zero latency, just copy
        output.copy_from_slice(input);
    }

    /// Process with lookahead path
    pub fn process_lookahead(&mut self, path_id: u32, input: &[f64], output: &mut [f64]) {
        for (i, &sample) in input.iter().enumerate() {
            output[i] = self.pdc.process_compensation(path_id, sample);
        }
    }

    /// Set pipeline mode
    pub fn set_mode(&mut self, mode: PipelineMode) {
        self.pdc.set_mode(mode);
    }

    /// Get pipeline info
    pub fn info(&self) -> PipelineInfo {
        PipelineInfo {
            total_latency_samples: self.total_latency(),
            total_latency_ms: self.latency_ms(),
            num_paths: self.pdc.paths().count(),
            direct_path_active: self.direct_path.is_some(),
            lookahead_paths: self.lookahead_paths.len(),
        }
    }

    /// Reset pipeline
    pub fn reset(&mut self) {
        self.pdc.reset();
    }
}

/// Pipeline information
#[derive(Debug, Clone)]
pub struct PipelineInfo {
    pub total_latency_samples: u32,
    pub total_latency_ms: f64,
    pub num_paths: usize,
    pub direct_path_active: bool,
    pub lookahead_paths: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pipeline_mode_latency() {
        let sample_rate = 48000.0;

        assert_eq!(PipelineMode::ZeroLatency.max_latency(sample_rate), 0);
        assert_eq!(PipelineMode::LowLatency.max_latency(sample_rate), 48);   // 1ms
        assert_eq!(PipelineMode::Normal.max_latency(sample_rate), 240);      // 5ms
        assert_eq!(PipelineMode::HighQuality.max_latency(sample_rate), 960); // 20ms
    }

    #[test]
    fn test_latency_slot() {
        let mut slot = LatencySlot::new(1024, 1);
        slot.set_delay(3);

        // Feed samples
        assert_eq!(slot.process(1.0), 0.0);  // Output delayed zeros initially
        assert_eq!(slot.process(2.0), 0.0);
        assert_eq!(slot.process(3.0), 0.0);
        assert_eq!(slot.process(4.0), 1.0);  // Now we get the delayed sample
        assert_eq!(slot.process(5.0), 2.0);
    }

    #[test]
    fn test_pdc_manager() {
        let mut pdc = PdcManager::new(48000.0, PipelineMode::Normal);

        pdc.add_path(0, "Path A".to_string());
        pdc.add_path(1, "Path B".to_string());

        pdc.add_processor(0, ProcessorSlot {
            id: 0,
            name: "Comp".to_string(),
            latency_samples: 64,
            enabled: true,
        });

        pdc.add_processor(1, ProcessorSlot {
            id: 0,
            name: "Limiter".to_string(),
            latency_samples: 128,
            enabled: true,
        });

        // Max latency should be 128
        assert_eq!(pdc.total_latency(), 128);

        // Path A should have 64 samples compensation
        assert_eq!(pdc.get_path(0).unwrap().compensation_delay, 64);
        // Path B should have 0 samples compensation
        assert_eq!(pdc.get_path(1).unwrap().compensation_delay, 0);
    }

    #[test]
    fn test_zero_latency_pipeline() {
        let mut pipeline = ZeroLatencyPipeline::new(48000.0, 512);

        let direct = pipeline.create_direct_path("Direct");
        assert_eq!(pipeline.total_latency(), 0);

        let lookahead = pipeline.create_lookahead_path("Lookahead");
        pipeline.add_processor(lookahead, "Limiter", 256);

        // Direct path still has 0 latency
        // But total pipeline latency is 256 for compensation
        assert_eq!(pipeline.total_latency(), 256);
    }

    #[test]
    fn test_pipeline_info() {
        let mut pipeline = ZeroLatencyPipeline::new(48000.0, 512);
        pipeline.create_direct_path("Direct");
        pipeline.create_lookahead_path("Lookahead 1");
        pipeline.create_lookahead_path("Lookahead 2");

        let info = pipeline.info();
        assert!(info.direct_path_active);
        assert_eq!(info.lookahead_paths, 2);
        assert_eq!(info.num_paths, 3);
    }

    #[test]
    fn test_direct_processing() {
        let mut pipeline = ZeroLatencyPipeline::new(48000.0, 4);
        pipeline.create_direct_path("Direct");

        let input = [1.0, 2.0, 3.0, 4.0];
        let mut output = [0.0; 4];

        pipeline.process_direct(&input, &mut output);
        assert_eq!(output, input);
    }
}
