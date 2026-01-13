//! Full Delay Compensation System
//!
//! Provides automatic delay compensation (ADC) for plugin latency:
//! - Per-track latency tracking
//! - Automatic compensation calculation
//! - Dynamic buffer allocation (pre-allocated pools)
//! - Support for plugin latency changes
//!
//! # Design
//! Similar to Pro Tools' 16,383 sample compensation, but unlimited.

use rf_core::Sample;
use std::collections::HashMap;

// ============ Types ============

/// Unique identifier for tracks/buses
pub type NodeId = u32;

/// Latency in samples
pub type LatencySamples = usize;

// ============ Delay Line ============

/// Circular buffer delay line for compensation
#[derive(Debug)]
pub struct DelayLine {
    buffer: Vec<Sample>,
    write_pos: usize,
    delay_samples: usize,
}

impl DelayLine {
    /// Create new delay line with maximum capacity
    pub fn new(max_delay: usize) -> Self {
        Self {
            buffer: vec![0.0; max_delay + 1],
            write_pos: 0,
            delay_samples: 0,
        }
    }

    /// Set delay amount (must be <= max_delay)
    pub fn set_delay(&mut self, samples: usize) {
        if samples >= self.buffer.len() {
            // Resize buffer if needed (NOT in audio thread!)
            self.buffer.resize(samples + 1, 0.0);
        }
        self.delay_samples = samples;
    }

    /// Get current delay
    #[inline]
    pub fn delay(&self) -> usize {
        self.delay_samples
    }

    /// Process a single sample
    #[inline]
    pub fn process_sample(&mut self, input: Sample) -> Sample {
        if self.delay_samples == 0 {
            return input;
        }

        let buffer_len = self.buffer.len();
        let read_pos = (self.write_pos + buffer_len - self.delay_samples) % buffer_len;

        let output = self.buffer[read_pos];
        self.buffer[self.write_pos] = input;
        self.write_pos = (self.write_pos + 1) % buffer_len;

        output
    }

    /// Process a block of samples
    pub fn process_block(&mut self, buffer: &mut [Sample]) {
        if self.delay_samples == 0 {
            return;
        }

        for sample in buffer.iter_mut() {
            *sample = self.process_sample(*sample);
        }
    }

    /// Clear buffer (reset to zeros)
    pub fn clear(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
    }
}

// ============ Stereo Delay Line ============

/// Stereo delay line for compensation
#[derive(Debug)]
pub struct StereoDelayLine {
    left: DelayLine,
    right: DelayLine,
}

impl StereoDelayLine {
    pub fn new(max_delay: usize) -> Self {
        Self {
            left: DelayLine::new(max_delay),
            right: DelayLine::new(max_delay),
        }
    }

    pub fn set_delay(&mut self, samples: usize) {
        self.left.set_delay(samples);
        self.right.set_delay(samples);
    }

    #[inline]
    pub fn delay(&self) -> usize {
        self.left.delay()
    }

    #[inline]
    pub fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        (
            self.left.process_sample(left),
            self.right.process_sample(right),
        )
    }

    pub fn process_block(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.left.process_block(left);
        self.right.process_block(right);
    }

    pub fn clear(&mut self) {
        self.left.clear();
        self.right.clear();
    }
}

// ============ Node Latency Info ============

/// Latency information for a processing node
#[derive(Debug, Clone, Copy, Default)]
pub struct NodeLatency {
    /// Latency introduced by this node's processing (plugins, etc.)
    pub plugin_latency: LatencySamples,
    /// Total latency from source to this node
    pub cumulative_latency: LatencySamples,
    /// Compensation delay needed for this node
    pub compensation_delay: LatencySamples,
}

// ============ Delay Compensation Manager ============

/// Maximum supported delay compensation (64K samples = ~1.5s @ 44.1kHz)
pub const MAX_COMPENSATION_SAMPLES: usize = 65536;

/// Manages delay compensation for entire audio graph
#[derive(Debug)]
pub struct DelayCompensationManager {
    /// Latency info per node
    node_latencies: HashMap<NodeId, NodeLatency>,
    /// Delay lines per node
    delay_lines: HashMap<NodeId, StereoDelayLine>,
    /// Maximum latency in the graph
    max_latency: LatencySamples,
    /// Whether compensation is enabled
    enabled: bool,
    /// Sample rate for latency calculations
    sample_rate: f64,
}

impl DelayCompensationManager {
    /// Create new delay compensation manager
    pub fn new(sample_rate: f64) -> Self {
        Self {
            node_latencies: HashMap::new(),
            delay_lines: HashMap::new(),
            max_latency: 0,
            enabled: true,
            sample_rate,
        }
    }

    /// Enable/disable compensation
    pub fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
        if !enabled {
            // Clear all delay lines
            for line in self.delay_lines.values_mut() {
                line.clear();
            }
        } else {
            // Recalculate
            self.recalculate();
        }
    }

    /// Check if compensation is enabled
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
    }

    /// Register a new node
    pub fn register_node(&mut self, node_id: NodeId) {
        if let std::collections::hash_map::Entry::Vacant(e) = self.node_latencies.entry(node_id) {
            e.insert(NodeLatency::default());
            self.delay_lines
                .insert(node_id, StereoDelayLine::new(MAX_COMPENSATION_SAMPLES));
        }
    }

    /// Unregister a node
    pub fn unregister_node(&mut self, node_id: NodeId) {
        self.node_latencies.remove(&node_id);
        self.delay_lines.remove(&node_id);
        self.recalculate();
    }

    /// Report plugin latency for a node
    pub fn report_latency(&mut self, node_id: NodeId, latency: LatencySamples) {
        if let Some(info) = self.node_latencies.get_mut(&node_id)
            && info.plugin_latency != latency {
                info.plugin_latency = latency;
                self.recalculate();
            }
    }

    /// Get latency info for a node
    pub fn get_latency(&self, node_id: NodeId) -> Option<&NodeLatency> {
        self.node_latencies.get(&node_id)
    }

    /// Get total system latency
    pub fn total_latency(&self) -> LatencySamples {
        self.max_latency
    }

    /// Get total latency in milliseconds
    pub fn total_latency_ms(&self) -> f64 {
        (self.max_latency as f64 / self.sample_rate) * 1000.0
    }

    /// Recalculate all compensation delays
    /// Called when any latency changes
    fn recalculate(&mut self) {
        if !self.enabled {
            // Reset all compensation to 0
            for info in self.node_latencies.values_mut() {
                info.compensation_delay = 0;
                info.cumulative_latency = 0;
            }
            for line in self.delay_lines.values_mut() {
                line.set_delay(0);
            }
            self.max_latency = 0;
            return;
        }

        // Find maximum latency across all nodes
        self.max_latency = self
            .node_latencies
            .values()
            .map(|info| info.plugin_latency)
            .max()
            .unwrap_or(0);

        // Calculate compensation for each node
        for (&node_id, info) in self.node_latencies.iter_mut() {
            // Compensation = max - this node's latency
            info.compensation_delay = self.max_latency.saturating_sub(info.plugin_latency);
            info.cumulative_latency = info.plugin_latency;

            // Update delay line
            if let Some(line) = self.delay_lines.get_mut(&node_id) {
                line.set_delay(info.compensation_delay);
            }
        }

        log::debug!(
            "DelayCompensation: recalculated, max_latency={}samples ({:.2}ms)",
            self.max_latency,
            self.total_latency_ms()
        );
    }

    /// Process compensation for a node
    #[inline]
    pub fn process(&mut self, node_id: NodeId, left: &mut [Sample], right: &mut [Sample]) {
        if !self.enabled {
            return;
        }

        if let Some(line) = self.delay_lines.get_mut(&node_id) {
            line.process_block(left, right);
        }
    }

    /// Process compensation for a mono node
    #[inline]
    pub fn process_mono(&mut self, node_id: NodeId, buffer: &mut [Sample]) {
        if !self.enabled {
            return;
        }

        if let Some(line) = self.delay_lines.get_mut(&node_id) {
            line.left.process_block(buffer);
        }
    }

    /// Clear all buffers (call when seeking/stopping)
    pub fn clear_all(&mut self) {
        for line in self.delay_lines.values_mut() {
            line.clear();
        }
    }

    /// Get list of all registered nodes
    pub fn nodes(&self) -> impl Iterator<Item = &NodeId> {
        self.node_latencies.keys()
    }
}

// ============ Track Delay Compensation ============

/// Per-track delay compensation helper
#[derive(Debug)]
pub struct TrackDelayCompensation {
    /// Delay line for this track
    delay_line: StereoDelayLine,
    /// Current compensation amount
    compensation: LatencySamples,
    /// Track's own latency (from plugins)
    track_latency: LatencySamples,
}

impl TrackDelayCompensation {
    pub fn new() -> Self {
        Self {
            delay_line: StereoDelayLine::new(MAX_COMPENSATION_SAMPLES),
            compensation: 0,
            track_latency: 0,
        }
    }

    /// Set track's plugin latency
    pub fn set_track_latency(&mut self, latency: LatencySamples) {
        self.track_latency = latency;
    }

    /// Get track's plugin latency
    pub fn track_latency(&self) -> LatencySamples {
        self.track_latency
    }

    /// Set compensation delay based on max system latency
    pub fn set_compensation(&mut self, max_system_latency: LatencySamples) {
        self.compensation = max_system_latency.saturating_sub(self.track_latency);
        self.delay_line.set_delay(self.compensation);
    }

    /// Get current compensation delay
    pub fn compensation(&self) -> LatencySamples {
        self.compensation
    }

    /// Process stereo block
    #[inline]
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        if self.compensation > 0 {
            self.delay_line.process_block(left, right);
        }
    }

    /// Process mono block
    #[inline]
    pub fn process_mono(&mut self, buffer: &mut [Sample]) {
        if self.compensation > 0 {
            self.delay_line.left.process_block(buffer);
        }
    }

    /// Clear delay buffer
    pub fn clear(&mut self) {
        self.delay_line.clear();
    }
}

impl Default for TrackDelayCompensation {
    fn default() -> Self {
        Self::new()
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_delay_line_zero_delay() {
        let mut line = DelayLine::new(100);
        line.set_delay(0);

        let output = line.process_sample(1.0);
        assert!((output - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_delay_line_fixed_delay() {
        let mut line = DelayLine::new(100);
        line.set_delay(3);

        // First 3 outputs should be 0 (initial buffer)
        assert!((line.process_sample(1.0) - 0.0).abs() < 1e-10);
        assert!((line.process_sample(2.0) - 0.0).abs() < 1e-10);
        assert!((line.process_sample(3.0) - 0.0).abs() < 1e-10);

        // Now we should get delayed output
        assert!((line.process_sample(4.0) - 1.0).abs() < 1e-10);
        assert!((line.process_sample(5.0) - 2.0).abs() < 1e-10);
    }

    #[test]
    fn test_compensation_manager_simple() {
        let mut manager = DelayCompensationManager::new(48000.0);

        manager.register_node(1);
        manager.register_node(2);

        // Node 1 has 100 samples latency, Node 2 has 200
        manager.report_latency(1, 100);
        manager.report_latency(2, 200);

        // Max should be 200
        assert_eq!(manager.total_latency(), 200);

        // Node 1 needs 100 samples compensation, Node 2 needs 0
        assert_eq!(manager.get_latency(1).unwrap().compensation_delay, 100);
        assert_eq!(manager.get_latency(2).unwrap().compensation_delay, 0);
    }

    #[test]
    fn test_compensation_disabled() {
        let mut manager = DelayCompensationManager::new(48000.0);
        manager.set_enabled(false);

        manager.register_node(1);
        manager.report_latency(1, 100);

        // Should have no compensation when disabled
        assert_eq!(manager.get_latency(1).unwrap().compensation_delay, 0);
    }

    #[test]
    fn test_track_delay_compensation() {
        let mut track1 = TrackDelayCompensation::new();
        let mut track2 = TrackDelayCompensation::new();

        track1.set_track_latency(50);
        track2.set_track_latency(100);

        // Set compensation based on max (100)
        track1.set_compensation(100);
        track2.set_compensation(100);

        assert_eq!(track1.compensation(), 50);
        assert_eq!(track2.compensation(), 0);
    }
}
