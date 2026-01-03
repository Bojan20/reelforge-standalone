//! Send/Return Effect Routing
//!
//! Provides aux send/return system like traditional mixing consoles:
//! - Multiple sends per channel
//! - Pre/post fader sends
//! - Return channels with full processing
//! - Stereo and mono sends

use std::sync::atomic::{AtomicBool, Ordering};
use rf_core::Sample;
use rf_dsp::smoothing::{SmoothedParam, SmoothingType};

use crate::insert_chain::InsertChain;

// ============ Send Types ============

/// Maximum sends per channel
pub const MAX_SENDS: usize = 8;

/// Maximum return buses
pub const MAX_RETURNS: usize = 4;

/// Send tap point
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SendTapPoint {
    /// Before fader - level unaffected by fader
    PreFader,
    /// After fader - level follows fader
    #[default]
    PostFader,
    /// After pan - includes pan position
    PostPan,
}

// ============ Send ============

/// Single aux send
pub struct Send {
    /// Destination return bus index
    destination: usize,
    /// Send level (0.0 to 1.0, linear)
    level: SmoothedParam,
    /// Pan (-1.0 left to 1.0 right)
    pan: SmoothedParam,
    /// Tap point
    tap_point: SendTapPoint,
    /// Mute state
    muted: AtomicBool,
    /// Enabled state
    enabled: AtomicBool,
}

impl Send {
    pub fn new(destination: usize, sample_rate: f64) -> Self {
        Self {
            destination,
            level: SmoothedParam::with_range(0.0, 5.0, sample_rate, SmoothingType::Exponential, 0.0, 1.0),
            pan: SmoothedParam::with_range(0.0, 5.0, sample_rate, SmoothingType::Exponential, -1.0, 1.0),
            tap_point: SendTapPoint::PostFader,
            muted: AtomicBool::new(false),
            enabled: AtomicBool::new(true),
        }
    }

    /// Set send level (0.0 to 1.0)
    pub fn set_level(&self, level: f64) {
        self.level.set_target(level);
    }

    /// Set send level in dB
    pub fn set_level_db(&self, db: f64) {
        let linear = 10.0_f64.powf(db / 20.0);
        self.level.set_target(linear.clamp(0.0, 1.0));
    }

    /// Get current level
    pub fn level(&self) -> f64 {
        self.level.current()
    }

    /// Set pan
    pub fn set_pan(&self, pan: f64) {
        self.pan.set_target(pan);
    }

    /// Get pan
    pub fn pan(&self) -> f64 {
        self.pan.current()
    }

    /// Set tap point
    pub fn set_tap_point(&mut self, tap: SendTapPoint) {
        self.tap_point = tap;
    }

    /// Get tap point
    pub fn tap_point(&self) -> SendTapPoint {
        self.tap_point
    }

    /// Set destination
    pub fn set_destination(&mut self, dest: usize) {
        self.destination = dest;
    }

    /// Get destination
    pub fn destination(&self) -> usize {
        self.destination
    }

    /// Mute send
    pub fn set_muted(&self, muted: bool) {
        self.muted.store(muted, Ordering::Relaxed);
    }

    /// Check if muted
    pub fn is_muted(&self) -> bool {
        self.muted.load(Ordering::Relaxed)
    }

    /// Enable/disable send
    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
    }

    /// Check if enabled
    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.level.set_sample_rate(sample_rate);
        self.pan.set_sample_rate(sample_rate);
    }

    /// Reset smoothing
    pub fn reset(&mut self) {
        self.level.reset();
        self.pan.reset();
    }
}

// ============ Send Bank ============

/// Collection of sends for a channel
pub struct SendBank {
    sends: [Send; MAX_SENDS],
    sample_rate: f64,
}

impl SendBank {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sends: std::array::from_fn(|i| Send::new(i % MAX_RETURNS, sample_rate)),
            sample_rate,
        }
    }

    /// Get send by index
    pub fn get(&self, index: usize) -> Option<&Send> {
        self.sends.get(index)
    }

    /// Get mutable send by index
    pub fn get_mut(&mut self, index: usize) -> Option<&mut Send> {
        self.sends.get_mut(index)
    }

    /// Process sends and accumulate to return buffers
    /// Returns array of (destination, left_contribution, right_contribution) for each sample
    #[inline]
    pub fn process_sends(
        &mut self,
        source_left: &[Sample],
        source_right: &[Sample],
        fader_gain: f64,
        pan_left: f64,
        pan_right: f64,
        return_buffers: &mut [ReturnBus],
    ) {
        for send in &mut self.sends {
            if !send.is_enabled() || send.is_muted() {
                continue;
            }

            let dest = send.destination;
            if dest >= return_buffers.len() {
                continue;
            }

            let block_size = source_left.len().min(source_right.len());

            for i in 0..block_size {
                // Get source signal based on tap point
                let (left, right) = match send.tap_point {
                    SendTapPoint::PreFader => (source_left[i], source_right[i]),
                    SendTapPoint::PostFader => (
                        source_left[i] * fader_gain,
                        source_right[i] * fader_gain,
                    ),
                    SendTapPoint::PostPan => (
                        source_left[i] * fader_gain * pan_left,
                        source_right[i] * fader_gain * pan_right,
                    ),
                };

                // Apply send level with smoothing
                let level = send.level.current();

                // Apply send pan (constant power)
                let send_pan = send.pan.current();
                let angle = (send_pan + 1.0) * 0.25 * std::f64::consts::PI;
                let send_left_gain = angle.cos();
                let send_right_gain = angle.sin();

                // Accumulate to return bus
                return_buffers[dest].add_sample(
                    i,
                    left * level * send_left_gain,
                    right * level * send_right_gain,
                );
            }

            // Advance smoothing for next block
            for _ in 0..block_size {
                send.level.next();
                send.pan.next();
            }
        }
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for send in &mut self.sends {
            send.set_sample_rate(sample_rate);
        }
    }

    /// Reset all sends
    pub fn reset(&mut self) {
        for send in &mut self.sends {
            send.reset();
        }
    }
}

// ============ Return Bus ============

/// Return bus for aux effects
pub struct ReturnBus {
    /// Return bus index
    index: usize,
    /// Left input buffer
    input_left: Vec<Sample>,
    /// Right input buffer
    input_right: Vec<Sample>,
    /// Left output buffer (after processing)
    output_left: Vec<Sample>,
    /// Right output buffer
    output_right: Vec<Sample>,
    /// Insert chain for return processing
    inserts: InsertChain,
    /// Return level
    level: SmoothedParam,
    /// Return pan
    pan: SmoothedParam,
    /// Mute state
    muted: AtomicBool,
    /// Solo state
    solo: AtomicBool,
    /// Name
    name: String,
}

impl ReturnBus {
    pub fn new(index: usize, block_size: usize, sample_rate: f64) -> Self {
        Self {
            index,
            input_left: vec![0.0; block_size],
            input_right: vec![0.0; block_size],
            output_left: vec![0.0; block_size],
            output_right: vec![0.0; block_size],
            inserts: InsertChain::new(sample_rate),
            level: SmoothedParam::with_range(1.0, 5.0, sample_rate, SmoothingType::Exponential, 0.0, 2.0),
            pan: SmoothedParam::with_range(0.0, 5.0, sample_rate, SmoothingType::Exponential, -1.0, 1.0),
            muted: AtomicBool::new(false),
            solo: AtomicBool::new(false),
            name: format!("Return {}", index + 1),
        }
    }

    /// Add a sample to the input buffer
    #[inline]
    pub fn add_sample(&mut self, index: usize, left: Sample, right: Sample) {
        if index < self.input_left.len() {
            self.input_left[index] += left;
            self.input_right[index] += right;
        }
    }

    /// Clear input buffers
    pub fn clear_inputs(&mut self) {
        self.input_left.fill(0.0);
        self.input_right.fill(0.0);
    }

    /// Process the return bus
    pub fn process(&mut self) {
        if self.muted.load(Ordering::Relaxed) {
            self.output_left.fill(0.0);
            self.output_right.fill(0.0);
            return;
        }

        // Copy input to output
        self.output_left.copy_from_slice(&self.input_left);
        self.output_right.copy_from_slice(&self.input_right);

        // Process through insert chain
        self.inserts.process_all(&mut self.output_left, &mut self.output_right);

        // Apply level and pan
        let len = self.output_left.len();
        for i in 0..len {
            let level = self.level.next();
            let pan = self.pan.current();

            // Constant power pan
            let angle = (pan + 1.0) * 0.25 * std::f64::consts::PI;
            let left_gain = level * angle.cos();
            let right_gain = level * angle.sin();

            self.output_left[i] *= left_gain;
            self.output_right[i] *= right_gain;
        }
    }

    /// Get output buffers
    pub fn output(&self) -> (&[Sample], &[Sample]) {
        (&self.output_left, &self.output_right)
    }

    /// Set level
    pub fn set_level(&self, level: f64) {
        self.level.set_target(level);
    }

    /// Set level in dB
    pub fn set_level_db(&self, db: f64) {
        let linear = 10.0_f64.powf(db / 20.0);
        self.level.set_target(linear);
    }

    /// Set pan
    pub fn set_pan(&self, pan: f64) {
        self.pan.set_target(pan);
    }

    /// Set mute
    pub fn set_muted(&self, muted: bool) {
        self.muted.store(muted, Ordering::Relaxed);
    }

    /// Check if muted
    pub fn is_muted(&self) -> bool {
        self.muted.load(Ordering::Relaxed)
    }

    /// Set solo
    pub fn set_solo(&self, solo: bool) {
        self.solo.store(solo, Ordering::Relaxed);
    }

    /// Check if soloed
    pub fn is_solo(&self) -> bool {
        self.solo.load(Ordering::Relaxed)
    }

    /// Get insert chain
    pub fn inserts(&self) -> &InsertChain {
        &self.inserts
    }

    /// Get mutable insert chain
    pub fn inserts_mut(&mut self) -> &mut InsertChain {
        &mut self.inserts
    }

    /// Set block size
    pub fn set_block_size(&mut self, size: usize) {
        self.input_left.resize(size, 0.0);
        self.input_right.resize(size, 0.0);
        self.output_left.resize(size, 0.0);
        self.output_right.resize(size, 0.0);
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.level.set_sample_rate(sample_rate);
        self.pan.set_sample_rate(sample_rate);
        self.inserts.set_sample_rate(sample_rate);
    }

    /// Reset
    pub fn reset(&mut self) {
        self.clear_inputs();
        self.output_left.fill(0.0);
        self.output_right.fill(0.0);
        self.level.reset();
        self.pan.reset();
        self.inserts.reset();
    }

    /// Get name
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Set name
    pub fn set_name(&mut self, name: impl Into<String>) {
        self.name = name.into();
    }

    /// Get latency
    pub fn latency(&self) -> usize {
        self.inserts.total_latency()
    }
}

// ============ Return Bus Manager ============

/// Manages all return buses
pub struct ReturnBusManager {
    buses: Vec<ReturnBus>,
    block_size: usize,
    sample_rate: f64,
    any_solo: bool,
}

impl ReturnBusManager {
    pub fn new(num_returns: usize, block_size: usize, sample_rate: f64) -> Self {
        Self {
            buses: (0..num_returns)
                .map(|i| ReturnBus::new(i, block_size, sample_rate))
                .collect(),
            block_size,
            sample_rate,
            any_solo: false,
        }
    }

    /// Get return bus
    pub fn get(&self, index: usize) -> Option<&ReturnBus> {
        self.buses.get(index)
    }

    /// Get mutable return bus
    pub fn get_mut(&mut self, index: usize) -> Option<&mut ReturnBus> {
        self.buses.get_mut(index)
    }

    /// Get all buses as mutable slice
    pub fn buses_mut(&mut self) -> &mut [ReturnBus] {
        &mut self.buses
    }

    /// Clear all input buffers
    pub fn clear_all(&mut self) {
        for bus in &mut self.buses {
            bus.clear_inputs();
        }
    }

    /// Process all return buses
    pub fn process_all(&mut self) {
        // Update solo state
        self.any_solo = self.buses.iter().any(|b| b.is_solo());

        for bus in &mut self.buses {
            // If any bus is soloed, mute non-soloed buses
            if self.any_solo && !bus.is_solo() {
                bus.output_left.fill(0.0);
                bus.output_right.fill(0.0);
            } else {
                bus.process();
            }
        }
    }

    /// Sum all returns to output buffers
    pub fn sum_to_output(&self, left: &mut [Sample], right: &mut [Sample]) {
        for bus in &self.buses {
            if bus.is_muted() {
                continue;
            }

            let (bus_left, bus_right) = bus.output();
            let len = left.len().min(right.len()).min(bus_left.len());

            for i in 0..len {
                left[i] += bus_left[i];
                right[i] += bus_right[i];
            }
        }
    }

    /// Set block size
    pub fn set_block_size(&mut self, size: usize) {
        self.block_size = size;
        for bus in &mut self.buses {
            bus.set_block_size(size);
        }
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for bus in &mut self.buses {
            bus.set_sample_rate(sample_rate);
        }
    }

    /// Reset all
    pub fn reset(&mut self) {
        for bus in &mut self.buses {
            bus.reset();
        }
    }

    /// Number of return buses
    pub fn len(&self) -> usize {
        self.buses.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.buses.is_empty()
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_send_creation() {
        let send = Send::new(0, 48000.0);
        assert_eq!(send.destination(), 0);
        assert!((send.level() - 0.0).abs() < 0.01);
        assert!((send.pan() - 0.0).abs() < 0.01);
    }

    #[test]
    fn test_return_bus() {
        let mut bus = ReturnBus::new(0, 256, 48000.0);

        // Add some input
        for i in 0..256 {
            bus.add_sample(i, 0.5, 0.5);
        }

        // Process
        bus.process();

        // Should have output
        let (left, right) = bus.output();
        assert!(left.iter().any(|&s| s != 0.0));
        assert!(right.iter().any(|&s| s != 0.0));
    }

    #[test]
    fn test_return_mute() {
        let mut bus = ReturnBus::new(0, 256, 48000.0);

        for i in 0..256 {
            bus.add_sample(i, 0.5, 0.5);
        }

        bus.set_muted(true);
        bus.process();

        let (left, right) = bus.output();
        assert!(left.iter().all(|&s| s == 0.0));
        assert!(right.iter().all(|&s| s == 0.0));
    }

    #[test]
    fn test_send_bank() {
        let mut bank = SendBank::new(48000.0);

        // Enable first send
        bank.get_mut(0).unwrap().set_level(1.0);
        bank.get_mut(0).unwrap().set_enabled(true);

        assert!(bank.get(0).unwrap().is_enabled());
    }

    #[test]
    fn test_return_manager() {
        let mut manager = ReturnBusManager::new(4, 256, 48000.0);

        assert_eq!(manager.len(), 4);

        // Add input to first return
        if let Some(bus) = manager.get_mut(0) {
            for i in 0..256 {
                bus.add_sample(i, 0.5, 0.5);
            }
        }

        // Process all
        manager.process_all();

        // Sum to output
        let mut left = vec![0.0; 256];
        let mut right = vec![0.0; 256];
        manager.sum_to_output(&mut left, &mut right);

        assert!(left.iter().any(|&s| s != 0.0));
    }
}
