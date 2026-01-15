//! Sidechain Routing System
//!
//! Provides professional sidechain routing for dynamics processors:
//! - External sidechain input selection
//! - Internal sidechain (from channel signal)
//! - Sidechain filtering (HPF/LPF)
//! - Sidechain monitoring
//! - Multiple sidechain sources per processor
//!
//! ## Usage Patterns
//! - Ducking: Kick drum triggers compressor on bass
//! - De-essing: HPF filtered sidechain for vocal sibilance
//! - Pumping: Rhythmic sidechain from synth pattern
//! - M/S Sidechain: Compress based on mid or side only

use rf_core::Sample;
use rf_dsp::biquad::{BiquadCoeffs, BiquadTDF2};
use rf_dsp::smoothing::{SmoothedParam, SmoothingType};
use rf_dsp::{MonoProcessor, Processor};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

// ═══════════════════════════════════════════════════════════════════════════════
// SIDECHAIN SOURCE
// ═══════════════════════════════════════════════════════════════════════════════

/// Sidechain source type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SidechainSource {
    /// Internal sidechain (uses the input signal)
    #[default]
    Internal,
    /// External sidechain from another track/bus
    External(u32),
    /// Mid component of stereo signal
    Mid,
    /// Side component of stereo signal
    Side,
}

/// Sidechain filter mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SidechainFilterMode {
    #[default]
    Off,
    /// High-pass filter (common for bass-heavy sources)
    HighPass,
    /// Low-pass filter
    LowPass,
    /// Band-pass filter
    BandPass,
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIDECHAIN INPUT
// ═══════════════════════════════════════════════════════════════════════════════

/// Sidechain input processor
///
/// Handles routing, filtering, and monitoring of sidechain signal
pub struct SidechainInput {
    /// Source selection
    source: SidechainSource,
    /// External source buffer (left channel)
    external_left: Vec<Sample>,
    /// External source buffer (right channel)
    external_right: Vec<Sample>,
    /// Filter mode
    filter_mode: SidechainFilterMode,
    /// Filter frequency
    filter_freq: SmoothedParam,
    /// Filter Q
    filter_q: SmoothedParam,
    /// High-pass filter
    hpf_left: BiquadTDF2,
    hpf_right: BiquadTDF2,
    /// Low-pass filter
    lpf_left: BiquadTDF2,
    lpf_right: BiquadTDF2,
    /// Mix (0 = internal only, 1 = external only)
    mix: SmoothedParam,
    /// Input gain
    gain: SmoothedParam,
    /// Monitor sidechain (solo the sidechain signal)
    monitor: AtomicBool,
    /// Is active
    active: AtomicBool,
    /// Sample rate
    sample_rate: f64,
    /// Block size
    block_size: usize,
}

impl SidechainInput {
    pub fn new(sample_rate: f64, block_size: usize) -> Self {
        let mut instance = Self {
            source: SidechainSource::Internal,
            external_left: vec![0.0; block_size],
            external_right: vec![0.0; block_size],
            filter_mode: SidechainFilterMode::Off,
            filter_freq: SmoothedParam::with_range(
                150.0,
                10.0,
                sample_rate,
                SmoothingType::Exponential,
                20.0,
                20000.0,
            ),
            filter_q: SmoothedParam::with_range(
                0.707,
                10.0,
                sample_rate,
                SmoothingType::Exponential,
                0.1,
                10.0,
            ),
            hpf_left: BiquadTDF2::new(sample_rate),
            hpf_right: BiquadTDF2::new(sample_rate),
            lpf_left: BiquadTDF2::new(sample_rate),
            lpf_right: BiquadTDF2::new(sample_rate),
            mix: SmoothedParam::with_range(
                0.0,
                5.0,
                sample_rate,
                SmoothingType::Exponential,
                0.0,
                1.0,
            ),
            gain: SmoothedParam::with_range(
                1.0,
                5.0,
                sample_rate,
                SmoothingType::Exponential,
                0.0,
                4.0,
            ),
            monitor: AtomicBool::new(false),
            active: AtomicBool::new(false),
            sample_rate,
            block_size,
        };

        instance.update_filters();
        instance
    }

    /// Set sidechain source
    pub fn set_source(&mut self, source: SidechainSource) {
        self.source = source;
        self.active.store(
            !matches!(source, SidechainSource::Internal),
            Ordering::Relaxed,
        );
    }

    /// Get current source
    pub fn source(&self) -> SidechainSource {
        self.source
    }

    /// Set filter mode
    pub fn set_filter_mode(&mut self, mode: SidechainFilterMode) {
        self.filter_mode = mode;
        self.update_filters();
    }

    /// Set filter frequency
    pub fn set_filter_freq(&self, freq: f64) {
        self.filter_freq.set_target(freq.clamp(20.0, 20000.0));
    }

    /// Set filter Q
    pub fn set_filter_q(&self, q: f64) {
        self.filter_q.set_target(q.clamp(0.1, 10.0));
    }

    /// Set mix (0 = internal, 1 = external)
    pub fn set_mix(&self, mix: f64) {
        self.mix.set_target(mix.clamp(0.0, 1.0));
    }

    /// Set input gain in dB
    pub fn set_gain_db(&self, db: f64) {
        let linear = 10.0_f64.powf(db / 20.0);
        self.gain.set_target(linear.clamp(0.0, 4.0));
    }

    /// Enable/disable sidechain monitor
    pub fn set_monitor(&self, monitor: bool) {
        self.monitor.store(monitor, Ordering::Relaxed);
    }

    /// Check if monitoring
    pub fn is_monitoring(&self) -> bool {
        self.monitor.load(Ordering::Relaxed)
    }

    /// Check if sidechain is active (using external source)
    pub fn is_active(&self) -> bool {
        self.active.load(Ordering::Relaxed)
    }

    /// Provide external sidechain signal
    /// Call this before process() with the external signal
    pub fn set_external_input(&mut self, left: &[Sample], right: &[Sample]) {
        let len = left.len().min(right.len()).min(self.block_size);
        self.external_left[..len].copy_from_slice(&left[..len]);
        self.external_right[..len].copy_from_slice(&right[..len]);
    }

    /// Process and return sidechain signal
    ///
    /// Takes the internal signal (input to the dynamics processor) and
    /// optionally mixes with external sidechain, applies filtering
    pub fn process(
        &mut self,
        internal_left: &[Sample],
        internal_right: &[Sample],
        output_left: &mut [Sample],
        output_right: &mut [Sample],
    ) {
        let len = internal_left
            .len()
            .min(internal_right.len())
            .min(output_left.len())
            .min(output_right.len())
            .min(self.block_size);

        // Update filter coefficients if parameters changed
        let freq = self.filter_freq.current();
        let q = self.filter_q.current();
        self.update_filter_coeffs(freq, q);

        for i in 0..len {
            // Get base signal based on source
            let (base_left, base_right) = match self.source {
                SidechainSource::Internal => (internal_left[i], internal_right[i]),
                SidechainSource::External(_) => {
                    // Mix internal and external based on mix parameter
                    let mix = self.mix.next_value();
                    let int_left = internal_left[i];
                    let int_right = internal_right[i];
                    let ext_left = self.external_left.get(i).copied().unwrap_or(0.0);
                    let ext_right = self.external_right.get(i).copied().unwrap_or(0.0);

                    (
                        int_left * (1.0 - mix) + ext_left * mix,
                        int_right * (1.0 - mix) + ext_right * mix,
                    )
                }
                SidechainSource::Mid => {
                    // M/S encode, use only mid
                    let mid = (internal_left[i] + internal_right[i]) * 0.5;
                    (mid, mid)
                }
                SidechainSource::Side => {
                    // M/S encode, use only side
                    let side = (internal_left[i] - internal_right[i]) * 0.5;
                    (side, side)
                }
            };

            // Apply gain
            let gain = self.gain.next_value();
            let gained_left = base_left * gain;
            let gained_right = base_right * gain;

            // Apply filter
            let (filtered_left, filtered_right) = match self.filter_mode {
                SidechainFilterMode::Off => (gained_left, gained_right),
                SidechainFilterMode::HighPass => (
                    self.hpf_left.process_sample(gained_left),
                    self.hpf_right.process_sample(gained_right),
                ),
                SidechainFilterMode::LowPass => (
                    self.lpf_left.process_sample(gained_left),
                    self.lpf_right.process_sample(gained_right),
                ),
                SidechainFilterMode::BandPass => {
                    // HPF then LPF for bandpass
                    let hp_left = self.hpf_left.process_sample(gained_left);
                    let hp_right = self.hpf_right.process_sample(gained_right);
                    (
                        self.lpf_left.process_sample(hp_left),
                        self.lpf_right.process_sample(hp_right),
                    )
                }
            };

            // Advance smoothing
            self.filter_freq.next_value();
            self.filter_q.next_value();

            output_left[i] = filtered_left;
            output_right[i] = filtered_right;
        }
    }

    /// Get sidechain signal for dynamics processor (mono sum)
    pub fn get_key_signal(
        &mut self,
        internal_left: &[Sample],
        internal_right: &[Sample],
    ) -> Vec<Sample> {
        let len = internal_left
            .len()
            .min(internal_right.len())
            .min(self.block_size);
        let mut left = vec![0.0; len];
        let mut right = vec![0.0; len];

        self.process(internal_left, internal_right, &mut left, &mut right);

        // Return mono sum for envelope detection
        left.iter()
            .zip(right.iter())
            .map(|(&l, &r)| (l + r) * 0.5)
            .collect()
    }

    /// Update filter coefficients
    fn update_filters(&mut self) {
        self.update_filter_coeffs(self.filter_freq.current(), self.filter_q.current());
    }

    fn update_filter_coeffs(&mut self, freq: f64, q: f64) {
        match self.filter_mode {
            SidechainFilterMode::Off => {}
            SidechainFilterMode::HighPass => {
                let coeffs = BiquadCoeffs::highpass(freq, q, self.sample_rate);
                self.hpf_left.set_coeffs(coeffs);
                self.hpf_right.set_coeffs(coeffs);
            }
            SidechainFilterMode::LowPass => {
                let coeffs = BiquadCoeffs::lowpass(freq, q, self.sample_rate);
                self.lpf_left.set_coeffs(coeffs);
                self.lpf_right.set_coeffs(coeffs);
            }
            SidechainFilterMode::BandPass => {
                // For bandpass, HPF at freq/2 and LPF at freq*2
                let hpf_coeffs = BiquadCoeffs::highpass(freq * 0.5, q, self.sample_rate);
                let lpf_coeffs = BiquadCoeffs::lowpass(freq * 2.0, q, self.sample_rate);
                self.hpf_left.set_coeffs(hpf_coeffs);
                self.hpf_right.set_coeffs(hpf_coeffs);
                self.lpf_left.set_coeffs(lpf_coeffs);
                self.lpf_right.set_coeffs(lpf_coeffs);
            }
        }
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.filter_freq.set_sample_rate(sample_rate);
        self.filter_q.set_sample_rate(sample_rate);
        self.mix.set_sample_rate(sample_rate);
        self.gain.set_sample_rate(sample_rate);
        self.update_filters();
    }

    /// Set block size
    pub fn set_block_size(&mut self, size: usize) {
        self.block_size = size;
        self.external_left.resize(size, 0.0);
        self.external_right.resize(size, 0.0);
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.external_left.fill(0.0);
        self.external_right.fill(0.0);
        self.hpf_left.reset();
        self.hpf_right.reset();
        self.lpf_left.reset();
        self.lpf_right.reset();
        self.filter_freq.reset();
        self.filter_q.reset();
        self.mix.reset();
        self.gain.reset();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIDECHAIN ROUTER
// ═══════════════════════════════════════════════════════════════════════════════

/// Sidechain routing point ID
pub type SidechainId = u32;

/// Sidechain routing entry
#[derive(Debug, Clone)]
pub struct SidechainRoute {
    /// Unique ID
    pub id: SidechainId,
    /// Source track/bus ID
    pub source_id: u32,
    /// Source tap point (pre/post fader)
    pub pre_fader: bool,
    /// Destination processor ID
    pub dest_processor_id: u32,
    /// Is active
    pub active: bool,
}

/// Sidechain router for the entire project
///
/// Manages sidechain routing between tracks/buses and dynamics processors
pub struct SidechainRouter {
    /// All sidechain routes
    routes: Vec<SidechainRoute>,
    /// Next route ID
    next_id: AtomicU32,
    /// Buffer storage for each source
    source_buffers: Vec<SidechainBuffer>,
    /// Block size
    block_size: usize,
}

/// Buffer for a single sidechain source
struct SidechainBuffer {
    source_id: u32,
    left: Vec<Sample>,
    right: Vec<Sample>,
    valid: bool,
}

impl SidechainRouter {
    pub fn new(block_size: usize) -> Self {
        Self {
            routes: Vec::new(),
            next_id: AtomicU32::new(1),
            source_buffers: Vec::new(),
            block_size,
        }
    }

    /// Add a sidechain route
    pub fn add_route(
        &mut self,
        source_id: u32,
        dest_processor_id: u32,
        pre_fader: bool,
    ) -> SidechainId {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);

        self.routes.push(SidechainRoute {
            id,
            source_id,
            pre_fader,
            dest_processor_id,
            active: true,
        });

        // Ensure source buffer exists
        if !self.source_buffers.iter().any(|b| b.source_id == source_id) {
            self.source_buffers.push(SidechainBuffer {
                source_id,
                left: vec![0.0; self.block_size],
                right: vec![0.0; self.block_size],
                valid: false,
            });
        }

        id
    }

    /// Remove a sidechain route
    pub fn remove_route(&mut self, id: SidechainId) -> bool {
        if let Some(pos) = self.routes.iter().position(|r| r.id == id) {
            self.routes.remove(pos);
            true
        } else {
            false
        }
    }

    /// Get route by ID
    pub fn get_route(&self, id: SidechainId) -> Option<&SidechainRoute> {
        self.routes.iter().find(|r| r.id == id)
    }

    /// Get mutable route by ID
    pub fn get_route_mut(&mut self, id: SidechainId) -> Option<&mut SidechainRoute> {
        self.routes.iter_mut().find(|r| r.id == id)
    }

    /// Get all routes for a destination processor
    pub fn routes_for_processor(&self, processor_id: u32) -> Vec<&SidechainRoute> {
        self.routes
            .iter()
            .filter(|r| r.dest_processor_id == processor_id && r.active)
            .collect()
    }

    /// Get all routes from a source
    pub fn routes_from_source(&self, source_id: u32) -> Vec<&SidechainRoute> {
        self.routes
            .iter()
            .filter(|r| r.source_id == source_id && r.active)
            .collect()
    }

    /// Store source signal for this processing block
    /// Call this during the source track's processing
    pub fn store_source_signal(&mut self, source_id: u32, left: &[Sample], right: &[Sample]) {
        if let Some(buffer) = self
            .source_buffers
            .iter_mut()
            .find(|b| b.source_id == source_id)
        {
            let len = left.len().min(right.len()).min(self.block_size);
            buffer.left[..len].copy_from_slice(&left[..len]);
            buffer.right[..len].copy_from_slice(&right[..len]);
            buffer.valid = true;
        }
    }

    /// Get source signal for a destination
    /// Returns None if source hasn't been processed yet this block
    pub fn get_source_signal(&self, source_id: u32) -> Option<(&[Sample], &[Sample])> {
        self.source_buffers
            .iter()
            .find(|b| b.source_id == source_id && b.valid)
            .map(|b| (b.left.as_slice(), b.right.as_slice()))
    }

    /// Clear all source buffers (call at start of each processing block)
    pub fn clear_buffers(&mut self) {
        for buffer in &mut self.source_buffers {
            buffer.valid = false;
        }
    }

    /// Set block size
    pub fn set_block_size(&mut self, size: usize) {
        self.block_size = size;
        for buffer in &mut self.source_buffers {
            buffer.left.resize(size, 0.0);
            buffer.right.resize(size, 0.0);
        }
    }

    /// Get all routes
    pub fn all_routes(&self) -> &[SidechainRoute] {
        &self.routes
    }

    /// Clear all routes
    pub fn clear_routes(&mut self) {
        self.routes.clear();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sidechain_input_internal() {
        let mut sc = SidechainInput::new(48000.0, 256);

        let input_left: Vec<f64> = (0..256).map(|i| (i as f64 * 0.1).sin()).collect();
        let input_right = input_left.clone();

        let mut output_left = vec![0.0; 256];
        let mut output_right = vec![0.0; 256];

        sc.process(
            &input_left,
            &input_right,
            &mut output_left,
            &mut output_right,
        );

        // Output should match input (no filtering, internal source)
        for i in 0..256 {
            assert!((output_left[i] - input_left[i]).abs() < 0.001);
        }
    }

    #[test]
    fn test_sidechain_external_mix() {
        let mut sc = SidechainInput::new(48000.0, 256);
        sc.set_source(SidechainSource::External(1));
        sc.set_mix(1.0); // Full external

        let internal: Vec<f64> = vec![0.5; 256];
        let external: Vec<f64> = vec![1.0; 256];

        sc.set_external_input(&external, &external);

        let mut output_l = vec![0.0; 256];
        let mut output_r = vec![0.0; 256];

        // Process multiple times for smoothing to settle
        for _ in 0..10 {
            sc.process(&internal, &internal, &mut output_l, &mut output_r);
        }

        // Should be mostly external signal
        // (smoothing means not exactly 1.0)
        assert!(output_l[255] > 0.9);
    }

    #[test]
    fn test_sidechain_hpf() {
        let mut sc = SidechainInput::new(48000.0, 256);
        sc.set_filter_mode(SidechainFilterMode::HighPass);
        sc.set_filter_freq(1000.0);

        // DC signal should be filtered out
        let input = vec![1.0; 256];
        let mut output_l = vec![0.0; 256];
        let mut output_r = vec![0.0; 256];

        sc.process(&input, &input, &mut output_l, &mut output_r);

        // After HPF, DC should approach zero
        // Need more samples for filter to settle
        for _ in 0..10 {
            sc.process(&input, &input, &mut output_l, &mut output_r);
        }

        // Last samples should be near zero (DC filtered)
        assert!(output_l[255].abs() < 0.1);
    }

    #[test]
    fn test_sidechain_mid_side() {
        let mut sc = SidechainInput::new(48000.0, 256);
        sc.set_source(SidechainSource::Mid);

        // Stereo signal with left only
        let left = vec![1.0; 256];
        let right = vec![0.0; 256];

        let key = sc.get_key_signal(&left, &right);

        // Mid = (L+R)/2 = 0.5
        assert!((key[0] - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_sidechain_router() {
        let mut router = SidechainRouter::new(256);

        // Add route: track 1 -> compressor 1
        let id = router.add_route(1, 100, false);

        // Store source signal
        let signal = vec![0.75; 256];
        router.store_source_signal(1, &signal, &signal);

        // Get for destination
        let (left, _right) = router.get_source_signal(1).unwrap();
        assert!((left[0] - 0.75).abs() < 0.001);

        // Get routes for processor
        let routes = router.routes_for_processor(100);
        assert_eq!(routes.len(), 1);
        assert_eq!(routes[0].source_id, 1);

        // Remove route
        assert!(router.remove_route(id));
        assert!(router.routes_for_processor(100).is_empty());
    }

    #[test]
    fn test_sidechain_gain() {
        let mut sc = SidechainInput::new(48000.0, 256);
        sc.set_gain_db(6.0); // +6dB

        let input = vec![0.5; 256];
        let mut output_l = vec![0.0; 256];
        let mut output_r = vec![0.0; 256];

        // Process multiple times for smoothing to settle
        for _ in 0..10 {
            sc.process(&input, &input, &mut output_l, &mut output_r);
        }

        // +6dB = factor of ~2
        assert!(output_l[255] > 0.9);
    }
}
