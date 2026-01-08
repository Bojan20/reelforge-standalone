//! # ULTIMATIVNI Time Stretch Engine
//!
//! State-of-the-art time stretching sa minimalnim artefaktima.
//!
//! ## Arhitektura
//!
//! ```text
//! ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
//! │   ANALIZA   │───▶│  SEPARACIJA │───▶│  PROCESING  │
//! └─────────────┘    └─────────────┘    └─────────────┘
//!       │                  │                  │
//!       ▼                  ▼                  ▼
//!  F0, Envelope,      Sines,           Phase Vocoder
//!  Transients,       Transients,       WSOLA, Granular
//!  Aperiodicity       Noise
//! ```
//!
//! ## Algoritmi
//!
//! - **NSGT + RTPGHI**: Constant-Q transform sa automatskom faznom koherencijom
//! - **STN Separacija**: Per-component processing za optimalan kvalitet
//! - **Formant Preservation**: LPC envelope extraction
//! - **WSOLA**: Time-domain za transiente
//! - **WORLD Vocoder**: Najviši kvalitet za monophonic

pub mod nsgt;
pub mod rtpghi;
pub mod formant;
pub mod stn;
pub mod wsola;
pub mod world;
pub mod transient;
pub mod granular;

// Re-exports
pub use nsgt::{ConstantQNsgt, NsgtConfig};
pub use rtpghi::PhaseGradientHeap;
pub use formant::FormantPreserver;
pub use stn::{StnDecomposer, StnComponents};
pub use wsola::WsolaProcessor;
pub use world::WorldVocoder;
pub use transient::TransientDetector;
pub use granular::GranularProcessor;

// ═══════════════════════════════════════════════════════════════════════════════
// CORE TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Time stretch algorithm selection
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Algorithm {
    /// Automatic selection based on content analysis
    #[default]
    Auto,
    /// NSGT Phase Vocoder + RTPGHI (highest quality polyphonic)
    PhaseVocoder,
    /// WSOLA time-domain (fast, good for transients)
    Wsola,
    /// TD-PSOLA pitch-synchronous (monophonic speech/vocals)
    Psola,
    /// WORLD vocoder (highest quality monophonic)
    World,
    /// Granular synthesis (creative/extreme stretch)
    Granular,
    /// Hybrid STN separation + per-component processing
    Hybrid,
}

/// Quality preset
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Quality {
    /// Real-time capable, ~50ms latency
    Realtime,
    /// High quality, ~200ms latency
    #[default]
    High,
    /// Maximum quality, offline only
    Ultra,
}

/// Transient preservation mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum TransientMode {
    /// No special transient handling
    Off,
    /// Detect and preserve transients
    #[default]
    Preserve,
    /// Detect, separate, and reposition transients
    Separate,
    /// Crisp mode - aggressive transient preservation
    Crisp,
}

/// Time stretch configuration
#[derive(Debug, Clone)]
pub struct TimeStretchConfig {
    /// Algorithm selection
    pub algorithm: Algorithm,
    /// Quality preset
    pub quality: Quality,
    /// Preserve formants during pitch shift
    pub formant_preserve: bool,
    /// Formant shift in semitones (independent of pitch)
    pub formant_shift: f64,
    /// Transient handling mode
    pub transient_mode: TransientMode,
    /// Enable neural post-enhancement
    pub neural_enhance: bool,
    /// Sample rate
    pub sample_rate: f64,
}

impl Default for TimeStretchConfig {
    fn default() -> Self {
        Self {
            algorithm: Algorithm::Auto,
            quality: Quality::High,
            formant_preserve: true,
            formant_shift: 0.0,
            transient_mode: TransientMode::Preserve,
            neural_enhance: false,
            sample_rate: 44100.0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FLEX MARKER TYPES (for UI)
// ═══════════════════════════════════════════════════════════════════════════════

/// Flex/Warp marker type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlexMarkerType {
    /// Auto-detected transient
    Transient,
    /// User-placed warp marker
    WarpMarker,
    /// Beat grid marker
    BeatMarker,
    /// Anchor point (locked position)
    Anchor,
}

/// A flex marker for time manipulation
#[derive(Debug, Clone)]
pub struct FlexMarker {
    /// Original position in samples
    pub original_pos: u64,
    /// Warped position in samples
    pub warped_pos: u64,
    /// Marker type
    pub marker_type: FlexMarkerType,
    /// Confidence (0.0 - 1.0) for auto-detected markers
    pub confidence: f32,
    /// Is this marker locked (anchor)
    pub locked: bool,
}

/// A stretch region between two markers
#[derive(Debug, Clone)]
pub struct StretchRegion {
    /// Start position in original samples
    pub src_start: u64,
    /// End position in original samples
    pub src_end: u64,
    /// Start position in stretched samples
    pub dst_start: u64,
    /// End position in stretched samples
    pub dst_end: u64,
}

impl StretchRegion {
    /// Calculate the stretch ratio for this region
    pub fn ratio(&self) -> f64 {
        let src_len = (self.src_end - self.src_start) as f64;
        let dst_len = (self.dst_end - self.dst_start) as f64;
        if src_len > 0.0 {
            dst_len / src_len
        } else {
            1.0
        }
    }

    /// Check if this region is compressed (ratio < 1)
    pub fn is_compressed(&self) -> bool {
        self.ratio() < 1.0
    }

    /// Check if this region is expanded (ratio > 1)
    pub fn is_expanded(&self) -> bool {
        self.ratio() > 1.0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ULTIMATE TIME STRETCH ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

/// ULTIMATIVNI Time Stretch processor
pub struct UltimateTimeStretch {
    // ═══════════════════════════════════════════════════════════
    // ANALYSIS
    // ═══════════════════════════════════════════════════════════
    /// Transient detection
    transient_detector: TransientDetector,
    /// Formant extraction
    formant_extractor: FormantPreserver,
    /// STN decomposition
    stn_decomposer: StnDecomposer,

    // ═══════════════════════════════════════════════════════════
    // TRANSFORMS
    // ═══════════════════════════════════════════════════════════
    /// NSGT (Constant-Q)
    nsgt: ConstantQNsgt,
    /// RTPGHI phase reconstruction
    rtpghi: PhaseGradientHeap,

    // ═══════════════════════════════════════════════════════════
    // ALGORITHMS
    // ═══════════════════════════════════════════════════════════
    /// WSOLA processor
    wsola: WsolaProcessor,
    /// Granular processor
    granular: GranularProcessor,
    /// WORLD vocoder
    world: WorldVocoder,

    // ═══════════════════════════════════════════════════════════
    // CONFIG
    // ═══════════════════════════════════════════════════════════
    config: TimeStretchConfig,

    // ═══════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════
    /// Detected flex markers
    markers: Vec<FlexMarker>,
    /// Current stretch regions
    regions: Vec<StretchRegion>,
}

impl UltimateTimeStretch {
    /// Create a new time stretch processor
    pub fn new(config: TimeStretchConfig) -> Self {
        let sample_rate = config.sample_rate;

        Self {
            transient_detector: TransientDetector::new(sample_rate),
            formant_extractor: FormantPreserver::new(sample_rate),
            stn_decomposer: StnDecomposer::new(sample_rate),
            nsgt: ConstantQNsgt::new(NsgtConfig::default_for_sample_rate(sample_rate)),
            rtpghi: PhaseGradientHeap::new(sample_rate),
            wsola: WsolaProcessor::new(sample_rate),
            granular: GranularProcessor::new(sample_rate),
            world: WorldVocoder::new(sample_rate),
            config,
            markers: Vec::new(),
            regions: Vec::new(),
        }
    }

    /// Analyze audio and detect transients/markers
    pub fn analyze(&mut self, input: &[f64]) -> Vec<FlexMarker> {
        self.markers = self.transient_detector.detect(input);
        self.markers.clone()
    }

    /// Add a user-placed warp marker
    pub fn add_marker(&mut self, original_pos: u64, warped_pos: u64) {
        self.markers.push(FlexMarker {
            original_pos,
            warped_pos,
            marker_type: FlexMarkerType::WarpMarker,
            confidence: 1.0,
            locked: false,
        });
        self.markers.sort_by_key(|m| m.original_pos);
        self.update_regions();
    }

    /// Update stretch regions from markers
    fn update_regions(&mut self) {
        self.regions.clear();

        if self.markers.len() < 2 {
            return;
        }

        for i in 0..self.markers.len() - 1 {
            let start = &self.markers[i];
            let end = &self.markers[i + 1];

            self.regions.push(StretchRegion {
                src_start: start.original_pos,
                src_end: end.original_pos,
                dst_start: start.warped_pos,
                dst_end: end.warped_pos,
            });
        }
    }

    /// Get current stretch regions (for UI visualization)
    pub fn get_regions(&self) -> &[StretchRegion] {
        &self.regions
    }

    /// Get current markers (for UI visualization)
    pub fn get_markers(&self) -> &[FlexMarker] {
        &self.markers
    }

    /// Process audio with uniform time stretch
    pub fn process(&mut self, input: &[f64], ratio: f64) -> Vec<f64> {
        self.process_with_pitch(input, ratio, 1.0)
    }

    /// Process audio with time stretch and pitch shift
    pub fn process_with_pitch(
        &mut self,
        input: &[f64],
        time_ratio: f64,
        pitch_ratio: f64,
    ) -> Vec<f64> {
        // Select algorithm based on config or auto-detect
        let algorithm = match self.config.algorithm {
            Algorithm::Auto => self.auto_select_algorithm(input, time_ratio),
            other => other,
        };

        match algorithm {
            Algorithm::PhaseVocoder | Algorithm::Auto => {
                self.process_phase_vocoder(input, time_ratio, pitch_ratio)
            }
            Algorithm::Wsola => {
                self.wsola.process(input, time_ratio)
            }
            Algorithm::World => {
                self.world.process(input, time_ratio, pitch_ratio)
            }
            Algorithm::Granular => {
                self.granular.process(input, time_ratio, pitch_ratio)
            }
            Algorithm::Hybrid => {
                self.process_hybrid(input, time_ratio, pitch_ratio)
            }
            Algorithm::Psola => {
                // Falls back to WORLD for now
                self.world.process(input, time_ratio, pitch_ratio)
            }
        }
    }

    /// Auto-select best algorithm based on content
    fn auto_select_algorithm(&self, input: &[f64], ratio: f64) -> Algorithm {
        // Extreme stretch → Granular or Hybrid
        if ratio < 0.25 || ratio > 4.0 {
            return Algorithm::Hybrid;
        }

        // Analyze content
        let transient_density = self.estimate_transient_density(input);
        let is_monophonic = self.estimate_monophonic(input);

        if is_monophonic && transient_density < 0.1 {
            // Monophonic with few transients → WORLD
            Algorithm::World
        } else if transient_density > 0.5 {
            // Highly transient → Hybrid (STN separation)
            Algorithm::Hybrid
        } else {
            // Default → Phase Vocoder
            Algorithm::PhaseVocoder
        }
    }

    fn estimate_transient_density(&self, input: &[f64]) -> f64 {
        // Quick estimate based on zero-crossing rate and energy variance
        let zcr = self.zero_crossing_rate(input);
        let energy_var = self.energy_variance(input);
        (zcr * 0.5 + energy_var * 0.5).min(1.0)
    }

    fn zero_crossing_rate(&self, input: &[f64]) -> f64 {
        if input.len() < 2 {
            return 0.0;
        }
        let crossings = input.windows(2)
            .filter(|w| w[0].signum() != w[1].signum())
            .count();
        crossings as f64 / input.len() as f64
    }

    fn energy_variance(&self, input: &[f64]) -> f64 {
        let frame_size = 1024;
        let energies: Vec<f64> = input.chunks(frame_size)
            .map(|chunk| chunk.iter().map(|&x| x * x).sum::<f64>() / chunk.len() as f64)
            .collect();

        if energies.is_empty() {
            return 0.0;
        }

        let mean = energies.iter().sum::<f64>() / energies.len() as f64;
        let variance = energies.iter()
            .map(|&e| (e - mean).powi(2))
            .sum::<f64>() / energies.len() as f64;

        (variance / (mean + 1e-10)).min(1.0)
    }

    fn estimate_monophonic(&self, _input: &[f64]) -> bool {
        // Simplified: could use pitch detection confidence
        // For now, assume polyphonic
        false
    }

    /// Phase vocoder processing with NSGT + RTPGHI
    fn process_phase_vocoder(
        &mut self,
        input: &[f64],
        time_ratio: f64,
        pitch_ratio: f64,
    ) -> Vec<f64> {
        // 1. Forward NSGT transform
        let coeffs = self.nsgt.forward(input);

        // 2. Time stretch in NSGT domain (interpolate magnitudes)
        let stretched_mag = self.nsgt.interpolate_time(&coeffs, time_ratio);

        // 3. Pitch shift if needed (frequency shift in CQ domain)
        let pitched_mag = if (pitch_ratio - 1.0).abs() > 1e-6 {
            self.nsgt.shift_pitch(&stretched_mag, pitch_ratio)
        } else {
            stretched_mag
        };

        // 4. Formant correction if enabled
        let corrected = if self.config.formant_preserve && (pitch_ratio - 1.0).abs() > 1e-6 {
            self.apply_formant_correction(&pitched_mag, pitch_ratio)
        } else {
            pitched_mag
        };

        // 5. Phase reconstruction with RTPGHI
        let phase = self.rtpghi.reconstruct(&corrected);

        // 6. Inverse NSGT
        self.nsgt.inverse(&corrected, &phase)
    }

    /// Hybrid STN processing
    fn process_hybrid(
        &mut self,
        input: &[f64],
        time_ratio: f64,
        pitch_ratio: f64,
    ) -> Vec<f64> {
        // 1. STN decomposition
        let components = self.stn_decomposer.decompose(input);

        // 2. Process each component optimally
        let sines = self.process_phase_vocoder(&components.sines, time_ratio, pitch_ratio);
        let transients = self.wsola.process(&components.transients, time_ratio);
        let noise = self.granular.process(&components.noise, time_ratio, pitch_ratio);

        // 3. Mix components back
        let output_len = sines.len().max(transients.len()).max(noise.len());
        let mut output = vec![0.0; output_len];

        for (i, out) in output.iter_mut().enumerate() {
            let s = sines.get(i).copied().unwrap_or(0.0);
            let t = transients.get(i).copied().unwrap_or(0.0);
            let n = noise.get(i).copied().unwrap_or(0.0);
            *out = s + t + n;
        }

        output
    }

    fn apply_formant_correction(
        &self,
        mag: &[Vec<f64>],
        pitch_ratio: f64,
    ) -> Vec<Vec<f64>> {
        // Apply formant correction using LPC envelope
        // This is simplified - full implementation in formant.rs
        let mut corrected = mag.to_vec();

        let shift_bins = (12.0 * (pitch_ratio).log2() * (self.nsgt.config.bins_per_octave as f64) / 12.0) as i32;

        for frame in &mut corrected {
            if shift_bins > 0 {
                // Pitch up: shift envelope down
                frame.rotate_right(shift_bins.unsigned_abs() as usize);
            } else if shift_bins < 0 {
                // Pitch down: shift envelope up
                frame.rotate_left(shift_bins.unsigned_abs() as usize);
            }
        }

        corrected
    }

    /// Reset processor state
    pub fn reset(&mut self) {
        self.markers.clear();
        self.regions.clear();
        self.nsgt.reset();
        self.rtpghi.reset();
        self.wsola.reset();
        self.granular.reset();
        self.world.reset();
    }

    /// Update configuration
    pub fn set_config(&mut self, config: TimeStretchConfig) {
        if (config.sample_rate - self.config.sample_rate).abs() > 1.0 {
            // Sample rate changed - reinitialize
            *self = Self::new(config);
        } else {
            self.config = config;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Convert semitones to frequency ratio
#[inline]
pub fn semitones_to_ratio(semitones: f64) -> f64 {
    2.0_f64.powf(semitones / 12.0)
}

/// Convert frequency ratio to semitones
#[inline]
pub fn ratio_to_semitones(ratio: f64) -> f64 {
    12.0 * ratio.log2()
}

/// Convert cents to frequency ratio
#[inline]
pub fn cents_to_ratio(cents: f64) -> f64 {
    2.0_f64.powf(cents / 1200.0)
}

/// Convert frequency ratio to cents
#[inline]
pub fn ratio_to_cents(ratio: f64) -> f64 {
    1200.0 * ratio.log2()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_semitone_conversion() {
        assert!((semitones_to_ratio(12.0) - 2.0).abs() < 1e-10);
        assert!((semitones_to_ratio(-12.0) - 0.5).abs() < 1e-10);
        assert!((ratio_to_semitones(2.0) - 12.0).abs() < 1e-10);
    }

    #[test]
    fn test_stretch_region() {
        let region = StretchRegion {
            src_start: 0,
            src_end: 1000,
            dst_start: 0,
            dst_end: 1500,
        };
        assert!((region.ratio() - 1.5).abs() < 1e-10);
        assert!(region.is_expanded());
        assert!(!region.is_compressed());
    }

    #[test]
    fn test_time_stretch_creation() {
        let config = TimeStretchConfig::default();
        let _processor = UltimateTimeStretch::new(config);
    }
}
