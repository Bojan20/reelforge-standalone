//! Insert Effect Chain
//!
//! Provides per-channel effect insert slots with:
//! - 10 insert slots per channel (Pro Tools style: 5 pre + 5 post fader)
//! - Pre/post fader positioning
//! - Bypass per slot
//! - Latency compensation
//! - Lock-free parameter updates via ring buffer

use rf_core::Sample;
use rf_dsp::delay_compensation::LatencySamples;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

// ============ Lock-Free Parameter Change ============

/// Lock-free parameter change message for insert processors.
/// Sent from UI thread via ring buffer, consumed by audio thread.
#[derive(Clone, Copy, Debug)]
pub struct InsertParamChange {
    /// Target track ID (0 = master bus)
    pub track_id: u64,
    /// Insert slot index (0-9)
    pub slot_index: u8,
    /// Parameter index within processor
    pub param_index: u16,
    /// New parameter value
    pub value: f64,
}

impl InsertParamChange {
    pub fn new(track_id: u64, slot_index: usize, param_index: usize, value: f64) -> Self {
        Self {
            track_id,
            slot_index: slot_index as u8,
            param_index: param_index as u16,
            value,
        }
    }
}

// ============ Insert Slot ============

/// Maximum insert slots per channel (Pro Tools style: 5 pre-fader + 5 post-fader)
pub const MAX_INSERT_SLOTS: usize = 10;

/// Insert slot position
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InsertPosition {
    /// Before fader (affects send levels)
    #[default]
    PreFader,
    /// After fader
    PostFader,
}

/// Maximum buffer size for wet/dry blending (pre-allocated to avoid audio thread allocations)
const MAX_BLEND_BUFFER_SIZE: usize = 8192;

/// Single insert slot
pub struct InsertSlot {
    /// The effect processor (trait object)
    processor: Option<Box<dyn InsertProcessor>>,
    /// Bypass state
    bypassed: AtomicBool,
    /// Position (pre/post fader)
    position: InsertPosition,
    /// Slot index (0-7)
    #[allow(dead_code)]
    index: usize,
    /// Latency introduced by this slot
    latency: LatencySamples,
    /// Wet/dry mix (0.0 = dry, 1.0 = wet)
    mix: AtomicU64,
    /// Pre-allocated buffer for wet/dry blending (left channel)
    /// Avoids heap allocation in audio thread
    dry_buffer_l: Box<[Sample; MAX_BLEND_BUFFER_SIZE]>,
    /// Pre-allocated buffer for wet/dry blending (right channel)
    dry_buffer_r: Box<[Sample; MAX_BLEND_BUFFER_SIZE]>,
}

impl InsertSlot {
    pub fn new(index: usize) -> Self {
        Self {
            processor: None,
            bypassed: AtomicBool::new(false),
            position: InsertPosition::PreFader,
            index,
            latency: 0,
            mix: AtomicU64::new(1.0_f64.to_bits()),
            // Pre-allocate buffers to avoid audio thread allocation
            dry_buffer_l: Box::new([0.0; MAX_BLEND_BUFFER_SIZE]),
            dry_buffer_r: Box::new([0.0; MAX_BLEND_BUFFER_SIZE]),
        }
    }

    /// Load a processor into this slot
    pub fn load(&mut self, processor: Box<dyn InsertProcessor>) {
        self.latency = processor.latency();
        self.processor = Some(processor);
    }

    /// Unload the processor
    pub fn unload(&mut self) -> Option<Box<dyn InsertProcessor>> {
        self.latency = 0;
        self.processor.take()
    }

    /// Check if slot has a processor
    pub fn is_loaded(&self) -> bool {
        self.processor.is_some()
    }

    /// Set bypass state
    pub fn set_bypass(&self, bypass: bool) {
        self.bypassed.store(bypass, Ordering::Relaxed);
    }

    /// Get bypass state
    pub fn is_bypassed(&self) -> bool {
        self.bypassed.load(Ordering::Relaxed)
    }

    /// Set wet/dry mix
    pub fn set_mix(&self, mix: f64) {
        self.mix
            .store(mix.clamp(0.0, 1.0).to_bits(), Ordering::Relaxed);
    }

    /// Get wet/dry mix
    pub fn mix(&self) -> f64 {
        f64::from_bits(self.mix.load(Ordering::Relaxed))
    }

    /// Set position
    pub fn set_position(&mut self, position: InsertPosition) {
        self.position = position;
    }

    /// Get position
    pub fn position(&self) -> InsertPosition {
        self.position
    }

    /// Get latency
    pub fn latency(&self) -> LatencySamples {
        if self.is_bypassed() { 0 } else { self.latency }
    }

    /// Process audio through this slot
    ///
    /// # Audio Thread Safety
    /// This method uses pre-allocated buffers for wet/dry blending,
    /// avoiding heap allocations in the audio thread.
    #[inline]
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        if self.is_bypassed() {
            return;
        }

        // Get mix before borrowing processor
        let mix = self.mix();

        if let Some(ref mut processor) = self.processor {
            if mix >= 0.999 {
                // Full wet - no need to blend
                processor.process_stereo(left, right);
            } else if mix <= 0.001 {
                // Full dry - skip processing
            } else {
                // Wet/dry blend using pre-allocated buffers (no audio thread allocation!)
                let dry_gain = 1.0 - mix;
                let wet_gain = mix;

                // Store dry signal in pre-allocated buffers
                let len = left.len().min(right.len()).min(MAX_BLEND_BUFFER_SIZE);
                self.dry_buffer_l[..len].copy_from_slice(&left[..len]);
                self.dry_buffer_r[..len].copy_from_slice(&right[..len]);

                // Process wet
                processor.process_stereo(left, right);

                // Blend using pre-allocated dry buffers
                for i in 0..len {
                    left[i] = self.dry_buffer_l[i] * dry_gain + left[i] * wet_gain;
                    right[i] = self.dry_buffer_r[i] * dry_gain + right[i] * wet_gain;
                }
            }
        }
    }

    /// Reset processor state
    pub fn reset(&mut self) {
        if let Some(ref mut processor) = self.processor {
            processor.reset();
        }
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        if let Some(ref mut processor) = self.processor {
            processor.set_sample_rate(sample_rate);
            self.latency = processor.latency();
        }
    }

    /// Get processor name
    pub fn name(&self) -> &str {
        self.processor.as_ref().map(|p| p.name()).unwrap_or("Empty")
    }

    /// Set processor parameter (lock-free if processor supports it)
    pub fn set_processor_param(&mut self, index: usize, value: f64) {
        if let Some(ref mut processor) = self.processor {
            processor.set_param(index, value);
        }
    }

    /// Get processor parameter
    pub fn get_processor_param(&self, index: usize) -> f64 {
        self.processor
            .as_ref()
            .map(|p| p.get_param(index))
            .unwrap_or(0.0)
    }
}

// ============ Insert Processor Trait ============

/// Trait for insert effect processors
pub trait InsertProcessor: Send + Sync {
    /// Processor name
    fn name(&self) -> &str;

    /// Process stereo audio in-place
    fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]);

    /// Process mono audio in-place
    ///
    /// # Warning
    /// Default implementation allocates on heap - not suitable for audio thread!
    /// Implementors should override this with a pre-allocated buffer if mono
    /// processing is needed in real-time context.
    fn process_mono(&mut self, buffer: &mut [Sample]) {
        // Default: process left only (for mono compatibility)
        // NOTE: This default allocates! Override in performance-critical code.
        // Most DAW inserts are stereo, so this is rarely called in audio thread.
        let len = buffer.len().min(MAX_BLEND_BUFFER_SIZE);
        let mut dummy = [0.0_f64; MAX_BLEND_BUFFER_SIZE];
        dummy[..len].copy_from_slice(&buffer[..len]);
        self.process_stereo(&mut buffer[..len], &mut dummy[..len]);
    }

    /// Get latency in samples
    fn latency(&self) -> LatencySamples {
        0
    }

    /// Reset processor state
    fn reset(&mut self);

    /// Set sample rate
    fn set_sample_rate(&mut self, sample_rate: f64);

    /// Get number of parameters
    fn num_params(&self) -> usize {
        0
    }

    /// Get parameter value
    fn get_param(&self, _index: usize) -> f64 {
        0.0
    }

    /// Set parameter value
    fn set_param(&mut self, _index: usize, _value: f64) {}

    /// Get parameter name
    fn param_name(&self, _index: usize) -> &str {
        ""
    }
}

// ============ Insert Chain ============

/// Complete insert chain for a channel
pub struct InsertChain {
    /// Pre-fader slots
    pre_slots: [InsertSlot; MAX_INSERT_SLOTS / 2],
    /// Post-fader slots
    post_slots: [InsertSlot; MAX_INSERT_SLOTS / 2],
    /// Total latency
    total_latency: LatencySamples,
    /// Sample rate
    sample_rate: f64,
}

impl std::fmt::Debug for InsertChain {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("InsertChain")
            .field("total_latency", &self.total_latency)
            .field("sample_rate", &self.sample_rate)
            .field("loaded_slots", &self.loaded_slots())
            .finish()
    }
}

impl InsertChain {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            pre_slots: std::array::from_fn(InsertSlot::new),
            post_slots: std::array::from_fn(|i| InsertSlot::new(i + MAX_INSERT_SLOTS / 2)),
            total_latency: 0,
            sample_rate,
        }
    }

    /// Get slot by index (0-3 = pre, 4-7 = post)
    pub fn slot(&self, index: usize) -> Option<&InsertSlot> {
        if index < MAX_INSERT_SLOTS / 2 {
            Some(&self.pre_slots[index])
        } else if index < MAX_INSERT_SLOTS {
            Some(&self.post_slots[index - MAX_INSERT_SLOTS / 2])
        } else {
            None
        }
    }

    /// Get mutable slot by index
    pub fn slot_mut(&mut self, index: usize) -> Option<&mut InsertSlot> {
        if index < MAX_INSERT_SLOTS / 2 {
            Some(&mut self.pre_slots[index])
        } else if index < MAX_INSERT_SLOTS {
            Some(&mut self.post_slots[index - MAX_INSERT_SLOTS / 2])
        } else {
            None
        }
    }

    /// Load processor into slot
    pub fn load(&mut self, index: usize, processor: Box<dyn InsertProcessor>) -> bool {
        if let Some(slot) = self.slot_mut(index) {
            slot.load(processor);
            self.update_latency();
            true
        } else {
            false
        }
    }

    /// Unload processor from slot
    pub fn unload(&mut self, index: usize) -> Option<Box<dyn InsertProcessor>> {
        let result = self.slot_mut(index).and_then(|s| s.unload());
        self.update_latency();
        result
    }

    /// Process pre-fader slots
    #[inline]
    pub fn process_pre_fader(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for slot in &mut self.pre_slots {
            slot.process(left, right);
        }
    }

    /// Process post-fader slots
    #[inline]
    pub fn process_post_fader(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        for slot in &mut self.post_slots {
            slot.process(left, right);
        }
    }

    /// Process all slots (for simple use)
    #[inline]
    pub fn process_all(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.process_pre_fader(left, right);
        self.process_post_fader(left, right);
    }

    /// Update total latency
    fn update_latency(&mut self) {
        self.total_latency = self.pre_slots.iter().map(|s| s.latency()).sum::<usize>()
            + self.post_slots.iter().map(|s| s.latency()).sum::<usize>();
    }

    /// Get total latency
    pub fn total_latency(&self) -> LatencySamples {
        self.total_latency
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for slot in &mut self.pre_slots {
            slot.set_sample_rate(sample_rate);
        }
        for slot in &mut self.post_slots {
            slot.set_sample_rate(sample_rate);
        }
        self.update_latency();
    }

    /// Reset all processors
    pub fn reset(&mut self) {
        for slot in &mut self.pre_slots {
            slot.reset();
        }
        for slot in &mut self.post_slots {
            slot.reset();
        }
    }

    /// Bypass all slots
    pub fn bypass_all(&self, bypass: bool) {
        for slot in &self.pre_slots {
            slot.set_bypass(bypass);
        }
        for slot in &self.post_slots {
            slot.set_bypass(bypass);
        }
    }

    /// Get list of loaded processors
    pub fn loaded_slots(&self) -> Vec<(usize, &str)> {
        let mut result = Vec::new();

        for (i, slot) in self.pre_slots.iter().enumerate() {
            if slot.is_loaded() {
                result.push((i, slot.name()));
            }
        }

        for (i, slot) in self.post_slots.iter().enumerate() {
            if slot.is_loaded() {
                result.push((i + MAX_INSERT_SLOTS / 2, slot.name()));
            }
        }

        result
    }

    /// Set parameter on processor in specific slot
    pub fn set_slot_param(&mut self, slot_index: usize, param_index: usize, value: f64) {
        if let Some(slot) = self.slot_mut(slot_index) {
            slot.set_processor_param(param_index, value);
        }
    }

    /// Get parameter from processor in specific slot
    pub fn get_slot_param(&self, slot_index: usize, param_index: usize) -> f64 {
        self.slot(slot_index)
            .map(|s| s.get_processor_param(param_index))
            .unwrap_or(0.0)
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    struct TestProcessor {
        gain: f64,
    }

    impl TestProcessor {
        fn new(gain: f64) -> Self {
            Self { gain }
        }
    }

    impl InsertProcessor for TestProcessor {
        fn name(&self) -> &str {
            "TestGain"
        }

        fn process_stereo(&mut self, left: &mut [Sample], right: &mut [Sample]) {
            for s in left.iter_mut() {
                *s *= self.gain;
            }
            for s in right.iter_mut() {
                *s *= self.gain;
            }
        }

        fn reset(&mut self) {}
        fn set_sample_rate(&mut self, _: f64) {}
    }

    #[test]
    fn test_insert_slot() {
        let mut slot = InsertSlot::new(0);
        assert!(!slot.is_loaded());

        slot.load(Box::new(TestProcessor::new(0.5)));
        assert!(slot.is_loaded());
        assert_eq!(slot.name(), "TestGain");

        let mut left = vec![1.0; 4];
        let mut right = vec![1.0; 4];
        slot.process(&mut left, &mut right);

        assert!((left[0] - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_insert_chain() {
        let mut chain = InsertChain::new(48000.0);

        // Load processor in slot 0 (pre-fader)
        chain.load(0, Box::new(TestProcessor::new(0.5)));

        let mut left = vec![1.0; 4];
        let mut right = vec![1.0; 4];
        chain.process_pre_fader(&mut left, &mut right);

        assert!((left[0] - 0.5).abs() < 1e-10);
    }

    #[test]
    fn test_bypass() {
        let mut slot = InsertSlot::new(0);
        slot.load(Box::new(TestProcessor::new(0.5)));

        slot.set_bypass(true);

        let mut left = vec![1.0; 4];
        let mut right = vec![1.0; 4];
        slot.process(&mut left, &mut right);

        // Should be unchanged when bypassed
        assert!((left[0] - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_wet_dry_mix() {
        let mut slot = InsertSlot::new(0);
        slot.load(Box::new(TestProcessor::new(0.0))); // Zeroes the signal
        slot.set_mix(0.5); // 50% wet

        let mut left = vec![1.0; 4];
        let mut right = vec![1.0; 4];
        slot.process(&mut left, &mut right);

        // 50% of 1.0 (dry) + 50% of 0.0 (wet) = 0.5
        assert!((left[0] - 0.5).abs() < 1e-10);
    }
}
