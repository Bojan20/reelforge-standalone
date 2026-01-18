//! Transient Detection (Beat Detective Style)
//!
//! Analyzes audio waveforms for transient events (drums, attacks, onsets):
//! - Multiple detection algorithms (High/Low/Enhanced)
//! - Configurable sensitivity
//! - Beat grid alignment
//! - Slice point generation

use serde::{Deserialize, Serialize};

/// Transient marker
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransientMarker {
    /// Position in samples
    pub position: u64,
    /// Strength/confidence (0.0-1.0)
    pub strength: f64,
    /// Type classification
    pub marker_type: TransientType,
    /// User-adjusted (vs auto-detected)
    pub user_adjusted: bool,
}

/// Transient type classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum TransientType {
    /// Generic transient
    #[default]
    Generic,
    /// Kick drum
    Kick,
    /// Snare drum
    Snare,
    /// Hi-hat/cymbal
    HiHat,
    /// Percussion
    Percussion,
    /// Note onset
    NoteOnset,
    /// Chord change
    ChordChange,
}

/// Detection algorithm
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum DetectionAlgorithm {
    /// High frequency emphasis (cymbals, hi-hats)
    HighEmphasis,
    /// Low frequency emphasis (kick, bass)
    LowEmphasis,
    /// Enhanced resolution (default, broad range)
    #[default]
    Enhanced,
    /// Spectral flux based
    SpectralFlux,
    /// Complex domain (phase + magnitude)
    ComplexDomain,
}

/// Transient detection settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetectionSettings {
    /// Detection algorithm
    pub algorithm: DetectionAlgorithm,
    /// Sensitivity (0.0-1.0, higher = more detections)
    pub sensitivity: f64,
    /// Minimum gap between transients (samples)
    pub min_gap_samples: u64,
    /// High-pass filter cutoff for detection (Hz)
    pub highpass_hz: f64,
    /// Low-pass filter cutoff for detection (Hz)
    pub lowpass_hz: f64,
    /// Use multi-band analysis
    pub multiband: bool,
    /// Number of bands for multiband analysis
    pub num_bands: usize,
}

impl Default for DetectionSettings {
    fn default() -> Self {
        Self {
            algorithm: DetectionAlgorithm::Enhanced,
            sensitivity: 0.5,
            min_gap_samples: 1024, // ~21ms at 48kHz
            highpass_hz: 20.0,
            lowpass_hz: 16000.0,
            multiband: true,
            num_bands: 4,
        }
    }
}

impl DetectionSettings {
    /// Settings for drum detection
    pub fn drums() -> Self {
        Self {
            algorithm: DetectionAlgorithm::Enhanced,
            sensitivity: 0.6,
            min_gap_samples: 512,
            highpass_hz: 40.0,
            lowpass_hz: 12000.0,
            multiband: true,
            num_bands: 4,
        }
    }

    /// Settings for bass/low frequency
    pub fn bass() -> Self {
        Self {
            algorithm: DetectionAlgorithm::LowEmphasis,
            sensitivity: 0.5,
            min_gap_samples: 2048,
            highpass_hz: 20.0,
            lowpass_hz: 300.0,
            multiband: false,
            num_bands: 1,
        }
    }

    /// Settings for percussive high frequencies
    pub fn percussion() -> Self {
        Self {
            algorithm: DetectionAlgorithm::HighEmphasis,
            sensitivity: 0.7,
            min_gap_samples: 256,
            highpass_hz: 2000.0,
            lowpass_hz: 16000.0,
            multiband: false,
            num_bands: 1,
        }
    }
}

/// Transient Detector
pub struct TransientDetector {
    /// Detection settings
    settings: DetectionSettings,
    /// Sample rate
    sample_rate: f64,
    /// Energy buffer for smoothing
    energy_buffer: Vec<f64>,
    /// Previous energy for derivative calculation
    prev_energy: f64,
    /// Adaptive threshold
    adaptive_threshold: f64,
    /// Decay rate for adaptive threshold
    threshold_decay: f64,
    /// High-pass filter state
    hp_state: (f64, f64),
    /// Low-pass filter state
    lp_state: (f64, f64),
    /// Samples since last detection
    samples_since_detection: u64,
    /// Detected transients buffer
    detections: Vec<TransientMarker>,
    /// Block counter for position tracking
    block_position: u64,
}

impl TransientDetector {
    /// Create new detector
    pub fn new(sample_rate: f64) -> Self {
        Self {
            settings: DetectionSettings::default(),
            sample_rate,
            energy_buffer: vec![0.0; 64], // Short buffer for energy smoothing
            prev_energy: 0.0,
            adaptive_threshold: 0.1,
            threshold_decay: 0.9995,
            hp_state: (0.0, 0.0),
            lp_state: (0.0, 0.0),
            samples_since_detection: 0,
            detections: Vec::new(),
            block_position: 0,
        }
    }

    /// Create with specific settings
    pub fn with_settings(sample_rate: f64, settings: DetectionSettings) -> Self {
        let mut detector = Self::new(sample_rate);
        detector.settings = settings;
        detector.update_filters();
        detector
    }

    /// Update filter coefficients
    fn update_filters(&mut self) {
        // Simple first-order filter coefficient calculation
        // High-pass: fc / fs (approximate)
        // Low-pass: 1 - fc / fs (approximate)
    }

    /// Set sensitivity
    pub fn set_sensitivity(&mut self, sensitivity: f64) {
        self.settings.sensitivity = sensitivity.clamp(0.0, 1.0);
    }

    /// Set algorithm
    pub fn set_algorithm(&mut self, algorithm: DetectionAlgorithm) {
        self.settings.algorithm = algorithm;
    }

    /// Apply simple one-pole high-pass filter
    fn highpass(&mut self, sample: f64) -> f64 {
        let alpha = 1.0 - (self.settings.highpass_hz / self.sample_rate).min(0.5);
        let output = alpha * (self.hp_state.0 + sample - self.hp_state.1);
        self.hp_state.0 = output;
        self.hp_state.1 = sample;
        output
    }

    /// Apply simple one-pole low-pass filter
    fn lowpass(&mut self, sample: f64) -> f64 {
        let alpha = (self.settings.lowpass_hz / self.sample_rate).min(0.5);
        let output = self.lp_state.0 + alpha * (sample - self.lp_state.0);
        self.lp_state.0 = output;
        output
    }

    /// Calculate energy for current sample
    fn calculate_energy(&self, sample: f64) -> f64 {
        sample * sample
    }

    /// Process single sample for transient detection
    pub fn process_sample(&mut self, sample: f64) -> Option<TransientMarker> {
        // Apply pre-filters based on algorithm
        let filtered = match self.settings.algorithm {
            DetectionAlgorithm::HighEmphasis => self.highpass(sample),
            DetectionAlgorithm::LowEmphasis => self.lowpass(sample),
            DetectionAlgorithm::Enhanced => {
                let hp = self.highpass(sample);
                let lp = self.lowpass(sample);
                (hp + lp) * 0.5
            }
            DetectionAlgorithm::SpectralFlux | DetectionAlgorithm::ComplexDomain => sample,
        };

        // Calculate instantaneous energy
        let energy = self.calculate_energy(filtered);

        // Smooth energy with short moving average
        self.energy_buffer.rotate_left(1);
        let buf_len = self.energy_buffer.len();
        self.energy_buffer[buf_len - 1] = energy;
        let smooth_energy: f64 = self.energy_buffer.iter().sum::<f64>() / buf_len as f64;

        // Calculate energy derivative (onset detection function)
        let energy_delta = (smooth_energy - self.prev_energy).max(0.0);
        self.prev_energy = smooth_energy;

        // Update adaptive threshold
        self.adaptive_threshold = self.adaptive_threshold * self.threshold_decay
            + smooth_energy * (1.0 - self.threshold_decay);

        // Detection threshold based on sensitivity
        let threshold = self.adaptive_threshold * (2.0 - self.settings.sensitivity * 1.5);

        self.samples_since_detection += 1;
        self.block_position += 1;

        // Check for transient
        if energy_delta > threshold && self.samples_since_detection >= self.settings.min_gap_samples
        {
            self.samples_since_detection = 0;

            // Calculate strength (normalized)
            let strength = (energy_delta / threshold).min(1.0);

            let marker = TransientMarker {
                position: self.block_position,
                strength,
                marker_type: self.classify_transient(energy, smooth_energy),
                user_adjusted: false,
            };

            self.detections.push(marker.clone());

            return Some(marker);
        }

        None
    }

    /// Process a block of audio
    pub fn process_block(&mut self, audio: &[f64]) -> Vec<TransientMarker> {
        let mut markers = Vec::new();

        for &sample in audio {
            if let Some(marker) = self.process_sample(sample) {
                markers.push(marker);
            }
        }

        markers
    }

    /// Classify transient type based on spectral characteristics
    fn classify_transient(&self, energy: f64, smooth_energy: f64) -> TransientType {
        // Simplified classification based on energy ratio
        let ratio = if smooth_energy > 0.0 {
            energy / smooth_energy
        } else {
            1.0
        };

        match self.settings.algorithm {
            DetectionAlgorithm::LowEmphasis => {
                if ratio > 3.0 {
                    TransientType::Kick
                } else {
                    TransientType::NoteOnset
                }
            }
            DetectionAlgorithm::HighEmphasis => {
                if ratio > 5.0 {
                    TransientType::HiHat
                } else {
                    TransientType::Percussion
                }
            }
            _ => TransientType::Generic,
        }
    }

    /// Analyze complete audio buffer
    pub fn analyze(&mut self, audio: &[f64]) -> Vec<TransientMarker> {
        self.reset();
        self.process_block(audio)
    }

    /// Analyze stereo audio (sum to mono internally)
    pub fn analyze_stereo(&mut self, left: &[f64], right: &[f64]) -> Vec<TransientMarker> {
        let mono: Vec<f64> = left
            .iter()
            .zip(right.iter())
            .map(|(&l, &r)| (l + r) * 0.5)
            .collect();

        self.analyze(&mono)
    }

    /// Get all detected transients
    pub fn detections(&self) -> &[TransientMarker] {
        &self.detections
    }

    /// Clear detection history
    pub fn clear_detections(&mut self) {
        self.detections.clear();
    }

    /// Reset detector state
    pub fn reset(&mut self) {
        self.energy_buffer.fill(0.0);
        self.prev_energy = 0.0;
        self.adaptive_threshold = 0.1;
        self.hp_state = (0.0, 0.0);
        self.lp_state = (0.0, 0.0);
        self.samples_since_detection = self.settings.min_gap_samples;
        self.detections.clear();
        self.block_position = 0;
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.update_filters();
    }
}

/// Transient-based slice point generator
pub struct SliceGenerator {
    /// Detected transients
    transients: Vec<TransientMarker>,
    /// Audio length in samples
    audio_length: u64,
    /// Sample rate
    sample_rate: f64,
}

impl SliceGenerator {
    /// Create from transient markers
    pub fn new(transients: Vec<TransientMarker>, audio_length: u64, sample_rate: f64) -> Self {
        Self {
            transients,
            audio_length,
            sample_rate,
        }
    }

    /// Generate slice regions (start, end) in samples
    pub fn generate_slices(&self) -> Vec<(u64, u64)> {
        if self.transients.is_empty() {
            return vec![(0, self.audio_length)];
        }

        let mut slices = Vec::with_capacity(self.transients.len() + 1);

        // First slice from 0 to first transient
        if self.transients[0].position > 0 {
            slices.push((0, self.transients[0].position));
        }

        // Slices between transients
        for i in 0..self.transients.len() {
            let start = self.transients[i].position;
            let end = if i + 1 < self.transients.len() {
                self.transients[i + 1].position
            } else {
                self.audio_length
            };
            slices.push((start, end));
        }

        slices
    }

    /// Quantize transients to grid
    pub fn quantize_to_grid(
        &mut self,
        tempo_bpm: f64,
        grid_division: f64, // 1.0 = beat, 0.5 = 8th, 0.25 = 16th
        strength: f64,      // 0.0-1.0, how much to quantize
    ) {
        let samples_per_beat = (self.sample_rate * 60.0) / tempo_bpm;
        let grid_samples = samples_per_beat * grid_division;

        for marker in &mut self.transients {
            let nearest_grid = (marker.position as f64 / grid_samples).round() * grid_samples;
            let quantized = nearest_grid as u64;

            // Blend based on strength
            marker.position =
                (marker.position as f64 * (1.0 - strength) + quantized as f64 * strength) as u64;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TRANSIENT SHAPER DSP
// ═══════════════════════════════════════════════════════════════════════════

/// Transient Shaper - Modify attack and sustain independently
/// Similar to SPL Transient Designer, Oxford TransMod
#[derive(Debug, Clone)]
pub struct TransientShaper {
    /// Sample rate
    sample_rate: f64,

    // Attack control
    /// Attack amount (-100% to +100%)
    attack: f64,
    /// Attack speed (ms)
    attack_speed: f64,
    /// Attack envelope
    attack_env: f64,
    /// Attack detector state
    attack_detector: f64,

    // Sustain control
    /// Sustain amount (-100% to +100%)
    sustain: f64,
    /// Sustain speed (ms)
    sustain_speed: f64,
    /// Sustain envelope
    sustain_env: f64,
    /// Sustain detector state
    sustain_detector: f64,

    // Internal
    /// Previous input for differential
    prev_input: f64,
    /// Output gain
    output_gain: f64,
    /// Mix (0.0 = dry, 1.0 = wet)
    mix: f64,

    // Coefficients
    attack_coeff: f64,
    sustain_coeff: f64,
    attack_release: f64,
    sustain_attack: f64,
}

impl TransientShaper {
    /// Create new transient shaper
    pub fn new(sample_rate: f64) -> Self {
        let mut shaper = Self {
            sample_rate,
            attack: 0.0,
            attack_speed: 15.0,
            attack_env: 0.0,
            attack_detector: 0.0,
            sustain: 0.0,
            sustain_speed: 50.0,
            sustain_env: 0.0,
            sustain_detector: 0.0,
            prev_input: 0.0,
            output_gain: 1.0,
            mix: 1.0,
            attack_coeff: 0.0,
            sustain_coeff: 0.0,
            attack_release: 0.0,
            sustain_attack: 0.0,
        };
        shaper.update_coefficients();
        shaper
    }

    /// Update filter coefficients
    fn update_coefficients(&mut self) {
        // Attack detector: fast attack, slower release
        self.attack_coeff =
            (-2.0 * std::f64::consts::PI * 1000.0 / (self.attack_speed * self.sample_rate)).exp();

        // Attack release (slower)
        self.attack_release = (-2.0 * std::f64::consts::PI * 100.0
            / (self.attack_speed * 10.0 * self.sample_rate))
            .exp();

        // Sustain detector: slower attack, slow release
        self.sustain_attack =
            (-2.0 * std::f64::consts::PI * 100.0 / (self.sustain_speed * self.sample_rate)).exp();

        self.sustain_coeff = (-2.0 * std::f64::consts::PI * 10.0
            / (self.sustain_speed * 10.0 * self.sample_rate))
            .exp();
    }

    /// Set attack amount (-100 to +100)
    pub fn set_attack(&mut self, percent: f64) {
        self.attack = percent.clamp(-100.0, 100.0) / 100.0;
    }

    /// Set sustain amount (-100 to +100)
    pub fn set_sustain(&mut self, percent: f64) {
        self.sustain = percent.clamp(-100.0, 100.0) / 100.0;
    }

    /// Set attack speed in ms
    pub fn set_attack_speed(&mut self, ms: f64) {
        self.attack_speed = ms.clamp(1.0, 200.0);
        self.update_coefficients();
    }

    /// Set sustain speed in ms
    pub fn set_sustain_speed(&mut self, ms: f64) {
        self.sustain_speed = ms.clamp(10.0, 500.0);
        self.update_coefficients();
    }

    /// Set output gain
    pub fn set_output_gain(&mut self, db: f64) {
        self.output_gain = 10.0_f64.powf(db.clamp(-24.0, 24.0) / 20.0);
    }

    /// Set wet/dry mix
    pub fn set_mix(&mut self, mix: f64) {
        self.mix = mix.clamp(0.0, 1.0);
    }

    /// Process single sample
    pub fn process_sample(&mut self, input: f64) -> f64 {
        let abs_input = input.abs();

        // Differential for transient detection
        let differential = (abs_input - self.prev_input).max(0.0);
        self.prev_input = abs_input;

        // Attack envelope follower
        if differential > self.attack_env {
            self.attack_env = differential + self.attack_coeff * (self.attack_env - differential);
        } else {
            self.attack_env *= self.attack_release;
        }

        // Sustain envelope follower (smoother)
        if abs_input > self.sustain_env {
            self.sustain_env = abs_input + self.sustain_attack * (self.sustain_env - abs_input);
        } else {
            self.sustain_env = abs_input + self.sustain_coeff * (self.sustain_env - abs_input);
        }

        // Calculate attack gain
        let attack_gain = if self.attack > 0.0 {
            1.0 + self.attack_env * self.attack * 4.0
        } else {
            1.0 / (1.0 + self.attack_env * (-self.attack) * 4.0)
        };

        // Calculate sustain gain (inverse of attack envelope)
        let sustain_gain = if self.sustain > 0.0 {
            let sustain_factor = self.sustain_env - self.attack_env * 0.5;
            1.0 + sustain_factor.max(0.0) * self.sustain * 2.0
        } else {
            let sustain_factor = self.sustain_env - self.attack_env * 0.5;
            1.0 / (1.0 + sustain_factor.max(0.0) * (-self.sustain) * 2.0)
        };

        // Apply gain
        let shaped = input * attack_gain * sustain_gain * self.output_gain;

        // Mix dry/wet
        input * (1.0 - self.mix) + shaped * self.mix
    }

    /// Process stereo samples
    pub fn process_stereo(&mut self, left: f64, right: f64) -> (f64, f64) {
        // Use mid signal for detection
        let mid = (left + right) * 0.5;
        let abs_mid = mid.abs();

        // Differential for transient detection
        let differential = (abs_mid - self.prev_input).max(0.0);
        self.prev_input = abs_mid;

        // Attack envelope follower
        if differential > self.attack_env {
            self.attack_env = differential + self.attack_coeff * (self.attack_env - differential);
        } else {
            self.attack_env *= self.attack_release;
        }

        // Sustain envelope follower
        if abs_mid > self.sustain_env {
            self.sustain_env = abs_mid + self.sustain_attack * (self.sustain_env - abs_mid);
        } else {
            self.sustain_env = abs_mid + self.sustain_coeff * (self.sustain_env - abs_mid);
        }

        // Calculate gains
        let attack_gain = if self.attack > 0.0 {
            1.0 + self.attack_env * self.attack * 4.0
        } else {
            1.0 / (1.0 + self.attack_env * (-self.attack) * 4.0)
        };

        let sustain_gain = if self.sustain > 0.0 {
            let sustain_factor = self.sustain_env - self.attack_env * 0.5;
            1.0 + sustain_factor.max(0.0) * self.sustain * 2.0
        } else {
            let sustain_factor = self.sustain_env - self.attack_env * 0.5;
            1.0 / (1.0 + sustain_factor.max(0.0) * (-self.sustain) * 2.0)
        };

        let total_gain = attack_gain * sustain_gain * self.output_gain;

        // Apply to both channels
        let out_l = left * (1.0 - self.mix) + left * total_gain * self.mix;
        let out_r = right * (1.0 - self.mix) + right * total_gain * self.mix;

        (out_l, out_r)
    }

    /// Process block of audio (mono)
    pub fn process_block(&mut self, audio: &mut [f64]) {
        for sample in audio.iter_mut() {
            *sample = self.process_sample(*sample);
        }
    }

    /// Process block of audio (stereo interleaved)
    pub fn process_block_stereo(&mut self, left: &mut [f64], right: &mut [f64]) {
        for (l, r) in left.iter_mut().zip(right.iter_mut()) {
            let (out_l, out_r) = self.process_stereo(*l, *r);
            *l = out_l;
            *r = out_r;
        }
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.attack_env = 0.0;
        self.attack_detector = 0.0;
        self.sustain_env = 0.0;
        self.sustain_detector = 0.0;
        self.prev_input = 0.0;
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.update_coefficients();
    }

    /// Get current attack envelope (for metering)
    pub fn attack_envelope(&self) -> f64 {
        self.attack_env
    }

    /// Get current sustain envelope (for metering)
    pub fn sustain_envelope(&self) -> f64 {
        self.sustain_env
    }
}

/// Multiband Transient Shaper
#[derive(Debug, Clone)]
pub struct MultibandTransientShaper {
    /// Low band shaper
    low: TransientShaper,
    /// Mid band shaper
    mid: TransientShaper,
    /// High band shaper
    high: TransientShaper,

    /// Low-mid crossover frequency
    crossover_low: f64,
    /// Mid-high crossover frequency
    crossover_high: f64,

    // Linkwitz-Riley filter states
    lp1_l: f64,
    lp1_r: f64,
    hp1_l: f64,
    hp1_r: f64,
    lp2_l: f64,
    lp2_r: f64,
    hp2_l: f64,
    hp2_r: f64,

    sample_rate: f64,
}

impl MultibandTransientShaper {
    /// Create new multiband transient shaper
    pub fn new(sample_rate: f64) -> Self {
        Self {
            low: TransientShaper::new(sample_rate),
            mid: TransientShaper::new(sample_rate),
            high: TransientShaper::new(sample_rate),
            crossover_low: 200.0,
            crossover_high: 4000.0,
            lp1_l: 0.0,
            lp1_r: 0.0,
            hp1_l: 0.0,
            hp1_r: 0.0,
            lp2_l: 0.0,
            lp2_r: 0.0,
            hp2_l: 0.0,
            hp2_r: 0.0,
            sample_rate,
        }
    }

    /// Set crossover frequencies
    pub fn set_crossovers(&mut self, low: f64, high: f64) {
        self.crossover_low = low.clamp(50.0, 500.0);
        self.crossover_high = high.clamp(1000.0, 10000.0);
    }

    /// Get low band shaper
    pub fn low_band(&mut self) -> &mut TransientShaper {
        &mut self.low
    }

    /// Get mid band shaper
    pub fn mid_band(&mut self) -> &mut TransientShaper {
        &mut self.mid
    }

    /// Get high band shaper
    pub fn high_band(&mut self) -> &mut TransientShaper {
        &mut self.high
    }

    /// Process stereo
    pub fn process_stereo(&mut self, left: f64, right: f64) -> (f64, f64) {
        // Simple 1-pole crossover (should be Linkwitz-Riley in production)
        let alpha_low = (2.0 * std::f64::consts::PI * self.crossover_low / self.sample_rate).tan()
            / (1.0 + (2.0 * std::f64::consts::PI * self.crossover_low / self.sample_rate).tan());
        let alpha_high = (2.0 * std::f64::consts::PI * self.crossover_high / self.sample_rate)
            .tan()
            / (1.0 + (2.0 * std::f64::consts::PI * self.crossover_high / self.sample_rate).tan());

        // Low band
        self.lp1_l = self.lp1_l + alpha_low * (left - self.lp1_l);
        self.lp1_r = self.lp1_r + alpha_low * (right - self.lp1_r);
        let low_l = self.lp1_l;
        let low_r = self.lp1_r;

        // High band
        self.hp2_l = left - (self.lp2_l + alpha_high * (left - self.lp2_l));
        self.hp2_r = right - (self.lp2_r + alpha_high * (right - self.lp2_r));
        self.lp2_l = self.lp2_l + alpha_high * (left - self.lp2_l);
        self.lp2_r = self.lp2_r + alpha_high * (right - self.lp2_r);
        let high_l = self.hp2_l;
        let high_r = self.hp2_r;

        // Mid band (what's left)
        let mid_l = left - low_l - high_l;
        let mid_r = right - low_r - high_r;

        // Process each band
        let (low_out_l, low_out_r) = self.low.process_stereo(low_l, low_r);
        let (mid_out_l, mid_out_r) = self.mid.process_stereo(mid_l, mid_r);
        let (high_out_l, high_out_r) = self.high.process_stereo(high_l, high_r);

        // Sum bands
        (
            low_out_l + mid_out_l + high_out_l,
            low_out_r + mid_out_r + high_out_r,
        )
    }

    /// Reset all states
    pub fn reset(&mut self) {
        self.low.reset();
        self.mid.reset();
        self.high.reset();
        self.lp1_l = 0.0;
        self.lp1_r = 0.0;
        self.hp1_l = 0.0;
        self.hp1_r = 0.0;
        self.lp2_l = 0.0;
        self.lp2_r = 0.0;
        self.hp2_l = 0.0;
        self.hp2_r = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn generate_impulse(len: usize, impulse_positions: &[usize]) -> Vec<f64> {
        let mut audio = vec![0.0; len];
        for &pos in impulse_positions {
            if pos < len {
                audio[pos] = 1.0;
                // Add some decay
                for i in 1..100.min(len - pos) {
                    audio[pos + i] = 0.5_f64.powi(i as i32);
                }
            }
        }
        audio
    }

    #[test]
    fn test_impulse_detection() {
        let mut detector = TransientDetector::new(48000.0);
        detector.set_sensitivity(0.7);

        // Create audio with clear impulses
        let audio = generate_impulse(48000, &[10000, 20000, 30000]);

        let markers = detector.analyze(&audio);

        // Should detect approximately 3 transients
        assert!(
            markers.len() >= 2,
            "Expected at least 2 transients, got {}",
            markers.len()
        );
    }

    #[test]
    fn test_slice_generation() {
        let transients = vec![
            TransientMarker {
                position: 1000,
                strength: 1.0,
                marker_type: TransientType::Generic,
                user_adjusted: false,
            },
            TransientMarker {
                position: 2000,
                strength: 1.0,
                marker_type: TransientType::Generic,
                user_adjusted: false,
            },
        ];

        let generator = SliceGenerator::new(transients, 3000, 48000.0);
        let slices = generator.generate_slices();

        assert_eq!(slices.len(), 3); // 0-1000, 1000-2000, 2000-3000
        assert_eq!(slices[0], (0, 1000));
        assert_eq!(slices[1], (1000, 2000));
        assert_eq!(slices[2], (2000, 3000));
    }

    #[test]
    fn test_grid_quantization() {
        let transients = vec![TransientMarker {
            position: 11000, // Slightly off grid
            strength: 1.0,
            marker_type: TransientType::Generic,
            user_adjusted: false,
        }];

        let mut generator = SliceGenerator::new(transients, 48000, 48000.0);

        // At 120 BPM, 48kHz: 1 beat = 24000 samples
        generator.quantize_to_grid(120.0, 0.5, 1.0); // Quantize to 8th notes

        // 8th note = 12000 samples, 11000 should quantize to 12000
        assert_eq!(generator.transients[0].position, 12000);
    }

    #[test]
    fn test_detection_settings() {
        let drums = DetectionSettings::drums();
        assert_eq!(drums.algorithm, DetectionAlgorithm::Enhanced);

        let bass = DetectionSettings::bass();
        assert_eq!(bass.algorithm, DetectionAlgorithm::LowEmphasis);

        let perc = DetectionSettings::percussion();
        assert_eq!(perc.algorithm, DetectionAlgorithm::HighEmphasis);
    }
}
