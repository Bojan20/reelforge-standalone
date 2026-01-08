//! Latency Management
//!
//! ULTIMATIVNI latency handling:
//! - Per-path latency tracking
//! - Automatic compensation
//! - Real-time latency reporting
//! - Lookahead management

use portable_atomic::{AtomicU32, Ordering};
use std::collections::HashMap;

/// Latency information for a single processor
#[derive(Debug, Clone, Copy)]
pub struct ProcessorLatency {
    /// Processor ID
    pub id: u32,
    /// Inherent latency (fixed)
    pub inherent_samples: u32,
    /// Lookahead latency (configurable)
    pub lookahead_samples: u32,
    /// Reporting latency (for PDC)
    pub reported_samples: u32,
}

impl ProcessorLatency {
    pub fn new(id: u32) -> Self {
        Self {
            id,
            inherent_samples: 0,
            lookahead_samples: 0,
            reported_samples: 0,
        }
    }

    /// Total latency
    pub fn total(&self) -> u32 {
        self.inherent_samples + self.lookahead_samples
    }

    /// Set inherent latency
    pub fn set_inherent(&mut self, samples: u32) {
        self.inherent_samples = samples;
        self.reported_samples = self.total();
    }

    /// Set lookahead latency
    pub fn set_lookahead(&mut self, samples: u32) {
        self.lookahead_samples = samples;
        self.reported_samples = self.total();
    }
}

/// Path latency information
#[derive(Debug, Clone)]
pub struct PathLatency {
    /// Path ID
    pub id: u32,
    /// Path name
    pub name: String,
    /// Processors in this path
    pub processors: Vec<ProcessorLatency>,
    /// Total path latency
    pub total_samples: u32,
    /// Compensation needed (relative to max path)
    pub compensation_samples: u32,
}

impl PathLatency {
    pub fn new(id: u32, name: String) -> Self {
        Self {
            id,
            name,
            processors: Vec::new(),
            total_samples: 0,
            compensation_samples: 0,
        }
    }

    /// Add a processor
    pub fn add_processor(&mut self, processor: ProcessorLatency) {
        self.processors.push(processor);
        self.recalculate();
    }

    /// Remove a processor
    pub fn remove_processor(&mut self, id: u32) -> bool {
        if let Some(idx) = self.processors.iter().position(|p| p.id == id) {
            self.processors.remove(idx);
            self.recalculate();
            true
        } else {
            false
        }
    }

    /// Recalculate total latency
    fn recalculate(&mut self) {
        self.total_samples = self.processors.iter().map(|p| p.total()).sum();
    }

    /// Get latency in milliseconds
    pub fn total_ms(&self, sample_rate: f64) -> f64 {
        self.total_samples as f64 / sample_rate * 1000.0
    }
}

/// Global latency manager
pub struct LatencyManager {
    /// All processing paths
    paths: HashMap<u32, PathLatency>,
    /// Maximum latency across all paths
    max_latency: AtomicU32,
    /// Sample rate
    sample_rate: f64,
    /// Auto-compensate enabled
    auto_compensate: bool,
}

impl LatencyManager {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            paths: HashMap::new(),
            max_latency: AtomicU32::new(0),
            sample_rate,
            auto_compensate: true,
        }
    }

    /// Add a path
    pub fn add_path(&mut self, id: u32, name: String) {
        self.paths.insert(id, PathLatency::new(id, name));
    }

    /// Remove a path
    pub fn remove_path(&mut self, id: u32) -> bool {
        if self.paths.remove(&id).is_some() {
            self.recalculate_compensation();
            true
        } else {
            false
        }
    }

    /// Add processor to path
    pub fn add_processor(&mut self, path_id: u32, processor: ProcessorLatency) {
        if let Some(path) = self.paths.get_mut(&path_id) {
            path.add_processor(processor);
            self.recalculate_compensation();
        }
    }

    /// Update processor latency
    pub fn update_processor(
        &mut self,
        path_id: u32,
        processor_id: u32,
        inherent: u32,
        lookahead: u32,
    ) {
        if let Some(path) = self.paths.get_mut(&path_id) {
            if let Some(processor) = path.processors.iter_mut().find(|p| p.id == processor_id) {
                processor.set_inherent(inherent);
                processor.set_lookahead(lookahead);
                path.recalculate();
                self.recalculate_compensation();
            }
        }
    }

    /// Recalculate all compensation values
    fn recalculate_compensation(&mut self) {
        // Find maximum latency
        let max = self
            .paths
            .values()
            .map(|p| p.total_samples)
            .max()
            .unwrap_or(0);

        self.max_latency.store(max, Ordering::Release);

        // Set compensation for each path
        if self.auto_compensate {
            for path in self.paths.values_mut() {
                path.compensation_samples = max.saturating_sub(path.total_samples);
            }
        }
    }

    /// Get maximum latency
    pub fn max_latency(&self) -> u32 {
        self.max_latency.load(Ordering::Acquire)
    }

    /// Get maximum latency in milliseconds
    pub fn max_latency_ms(&self) -> f64 {
        self.max_latency() as f64 / self.sample_rate * 1000.0
    }

    /// Get path
    pub fn get_path(&self, id: u32) -> Option<&PathLatency> {
        self.paths.get(&id)
    }

    /// Get all paths
    pub fn paths(&self) -> impl Iterator<Item = &PathLatency> {
        self.paths.values()
    }

    /// Set auto-compensate mode
    pub fn set_auto_compensate(&mut self, enabled: bool) {
        self.auto_compensate = enabled;
        self.recalculate_compensation();
    }

    /// Get latency report
    pub fn report(&self) -> LatencyReport {
        LatencyReport {
            max_latency_samples: self.max_latency(),
            max_latency_ms: self.max_latency_ms(),
            paths: self
                .paths
                .values()
                .map(|p| PathLatencyInfo {
                    id: p.id,
                    name: p.name.clone(),
                    total_samples: p.total_samples,
                    total_ms: p.total_ms(self.sample_rate),
                    compensation_samples: p.compensation_samples,
                    num_processors: p.processors.len(),
                })
                .collect(),
            auto_compensate: self.auto_compensate,
            sample_rate: self.sample_rate,
        }
    }
}

/// Latency report for UI/debugging
#[derive(Debug, Clone)]
pub struct LatencyReport {
    pub max_latency_samples: u32,
    pub max_latency_ms: f64,
    pub paths: Vec<PathLatencyInfo>,
    pub auto_compensate: bool,
    pub sample_rate: f64,
}

/// Path info for report
#[derive(Debug, Clone)]
pub struct PathLatencyInfo {
    pub id: u32,
    pub name: String,
    pub total_samples: u32,
    pub total_ms: f64,
    pub compensation_samples: u32,
    pub num_processors: usize,
}

/// Lookahead buffer for latency compensation
pub struct LookaheadBuffer {
    buffer: Vec<f64>,
    write_pos: usize,
    delay_samples: usize,
    capacity: usize,
}

impl LookaheadBuffer {
    pub fn new(max_delay: usize) -> Self {
        Self {
            buffer: vec![0.0; max_delay],
            write_pos: 0,
            delay_samples: 0,
            capacity: max_delay,
        }
    }

    /// Set delay in samples
    pub fn set_delay(&mut self, samples: usize) {
        self.delay_samples = samples.min(self.capacity);
    }

    /// Get delay in samples
    pub fn delay(&self) -> usize {
        self.delay_samples
    }

    /// Process a sample
    pub fn process(&mut self, input: f64) -> f64 {
        if self.delay_samples == 0 {
            return input;
        }

        let read_pos = (self.write_pos + self.capacity - self.delay_samples) % self.capacity;
        let output = self.buffer[read_pos];
        self.buffer[self.write_pos] = input;
        self.write_pos = (self.write_pos + 1) % self.capacity;
        output
    }

    /// Process a block of samples
    pub fn process_block(&mut self, input: &[f64], output: &mut [f64]) {
        for (i, &sample) in input.iter().enumerate() {
            output[i] = self.process(sample);
        }
    }

    /// Reset buffer
    pub fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
    }
}

/// Multi-channel lookahead buffer
pub struct MultiChannelLookahead {
    channels: Vec<LookaheadBuffer>,
}

impl MultiChannelLookahead {
    pub fn new(num_channels: usize, max_delay: usize) -> Self {
        Self {
            channels: (0..num_channels)
                .map(|_| LookaheadBuffer::new(max_delay))
                .collect(),
        }
    }

    /// Set delay for all channels
    pub fn set_delay(&mut self, samples: usize) {
        for channel in &mut self.channels {
            channel.set_delay(samples);
        }
    }

    /// Process multi-channel audio
    pub fn process(&mut self, input: &[&[f64]], output: &mut [&mut [f64]]) {
        for (i, (in_ch, out_ch)) in input.iter().zip(output.iter_mut()).enumerate() {
            if i < self.channels.len() {
                self.channels[i].process_block(in_ch, out_ch);
            }
        }
    }

    /// Reset all channels
    pub fn reset(&mut self) {
        for channel in &mut self.channels {
            channel.reset();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_processor_latency() {
        let mut latency = ProcessorLatency::new(0);
        latency.set_inherent(64);
        latency.set_lookahead(128);

        assert_eq!(latency.total(), 192);
        assert_eq!(latency.reported_samples, 192);
    }

    #[test]
    fn test_path_latency() {
        let mut path = PathLatency::new(0, "Main".to_string());

        let mut proc1 = ProcessorLatency::new(0);
        proc1.set_inherent(64);

        let mut proc2 = ProcessorLatency::new(1);
        proc2.set_inherent(128);

        path.add_processor(proc1);
        path.add_processor(proc2);

        assert_eq!(path.total_samples, 192);
    }

    #[test]
    fn test_latency_manager() {
        let mut manager = LatencyManager::new(48000.0);

        manager.add_path(0, "Direct".to_string());
        manager.add_path(1, "Lookahead".to_string());

        let mut proc = ProcessorLatency::new(0);
        proc.set_inherent(256);
        manager.add_processor(1, proc);

        assert_eq!(manager.max_latency(), 256);
        assert_eq!(manager.get_path(0).unwrap().compensation_samples, 256);
        assert_eq!(manager.get_path(1).unwrap().compensation_samples, 0);
    }

    #[test]
    fn test_lookahead_buffer() {
        let mut buffer = LookaheadBuffer::new(1024);
        buffer.set_delay(3);

        assert_eq!(buffer.process(1.0), 0.0);
        assert_eq!(buffer.process(2.0), 0.0);
        assert_eq!(buffer.process(3.0), 0.0);
        assert_eq!(buffer.process(4.0), 1.0);
        assert_eq!(buffer.process(5.0), 2.0);
    }

    #[test]
    fn test_zero_delay() {
        let mut buffer = LookaheadBuffer::new(1024);
        buffer.set_delay(0);

        assert_eq!(buffer.process(1.0), 1.0);
        assert_eq!(buffer.process(2.0), 2.0);
    }

    #[test]
    fn test_multi_channel() {
        let mut buffer = MultiChannelLookahead::new(2, 1024);
        buffer.set_delay(1);

        let input_l = [1.0, 2.0];
        let input_r = [3.0, 4.0];
        let mut output_l = [0.0; 2];
        let mut output_r = [0.0; 2];

        buffer.process(&[&input_l, &input_r], &mut [&mut output_l, &mut output_r]);

        // First samples should be 0 (delayed)
        assert_eq!(output_l[0], 0.0);
        assert_eq!(output_r[0], 0.0);
        // Second samples should be first inputs
        assert_eq!(output_l[1], 1.0);
        assert_eq!(output_r[1], 3.0);
    }

    #[test]
    fn test_latency_report() {
        let mut manager = LatencyManager::new(48000.0);
        manager.add_path(0, "Test".to_string());

        let report = manager.report();
        assert_eq!(report.paths.len(), 1);
        assert_eq!(report.sample_rate, 48000.0);
    }
}
