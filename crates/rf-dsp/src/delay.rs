//! Delay processors
//!
//! Includes:
//! - Simple delay
//! - Ping-pong delay
//! - Multi-tap delay
//! - Modulated delay (chorus/flanger)

use rf_core::Sample;
use std::f64::consts::PI;

use crate::biquad::BiquadTDF2;
use crate::{MonoProcessor, Processor, ProcessorConfig, StereoProcessor};

/// Simple mono delay with feedback and filtering
#[derive(Debug, Clone)]
pub struct Delay {
    buffer: Vec<Sample>,
    write_pos: usize,
    delay_samples: usize,
    max_delay_samples: usize,
    feedback: f64,
    dry_wet: f64,

    // Feedback filtering
    highpass: BiquadTDF2,
    lowpass: BiquadTDF2,
    filter_enabled: bool,

    sample_rate: f64,
}

impl Delay {
    pub fn new(sample_rate: f64, max_delay_ms: f64) -> Self {
        let max_delay_samples = (max_delay_ms * 0.001 * sample_rate) as usize;

        let mut delay = Self {
            buffer: vec![0.0; max_delay_samples],
            write_pos: 0,
            delay_samples: (500.0 * 0.001 * sample_rate) as usize, // Default 500ms
            max_delay_samples,
            feedback: 0.5,
            dry_wet: 0.5,
            highpass: BiquadTDF2::new(sample_rate),
            lowpass: BiquadTDF2::new(sample_rate),
            filter_enabled: true,
            sample_rate,
        };

        delay.highpass.set_highpass(80.0, 0.707);
        delay.lowpass.set_lowpass(8000.0, 0.707);

        delay
    }

    pub fn set_delay_ms(&mut self, ms: f64) {
        let samples = (ms * 0.001 * self.sample_rate) as usize;
        self.delay_samples = samples.min(self.max_delay_samples - 1);
    }

    pub fn set_delay_samples(&mut self, samples: usize) {
        self.delay_samples = samples.min(self.max_delay_samples - 1);
    }

    pub fn set_feedback(&mut self, feedback: f64) {
        self.feedback = feedback.clamp(0.0, 0.99);
    }

    pub fn set_dry_wet(&mut self, mix: f64) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }

    pub fn set_highpass(&mut self, freq: f64) {
        self.highpass.set_highpass(freq, 0.707);
    }

    pub fn set_lowpass(&mut self, freq: f64) {
        self.lowpass.set_lowpass(freq, 0.707);
    }

    pub fn set_filter_enabled(&mut self, enabled: bool) {
        self.filter_enabled = enabled;
    }

    fn read_delayed(&self) -> Sample {
        let read_pos =
            (self.write_pos + self.max_delay_samples - self.delay_samples) % self.max_delay_samples;
        self.buffer[read_pos]
    }
}

impl Processor for Delay {
    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
        self.highpass.reset();
        self.lowpass.reset();
    }
}

impl MonoProcessor for Delay {
    fn process_sample(&mut self, input: Sample) -> Sample {
        let delayed = self.read_delayed();

        // Apply filtering to feedback path
        let filtered = if self.filter_enabled {
            let hp = self.highpass.process_sample(delayed);
            self.lowpass.process_sample(hp)
        } else {
            delayed
        };

        // Write to buffer with feedback
        self.buffer[self.write_pos] = input + filtered * self.feedback;
        self.write_pos = (self.write_pos + 1) % self.max_delay_samples;

        // Mix dry and wet
        input * (1.0 - self.dry_wet) + delayed * self.dry_wet
    }
}

impl ProcessorConfig for Delay {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        let ratio = sample_rate / self.sample_rate;
        self.sample_rate = sample_rate;
        self.max_delay_samples = (self.max_delay_samples as f64 * ratio) as usize;
        self.delay_samples = (self.delay_samples as f64 * ratio) as usize;
        self.buffer = vec![0.0; self.max_delay_samples];
        self.highpass.set_sample_rate(sample_rate);
        self.lowpass.set_sample_rate(sample_rate);
    }
}

/// Note value for tempo sync (D3.2)
/// Maps note division to multiplier relative to quarter note (1 beat)
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum NoteValue {
    N1_64, N1_32, N1_16T, N1_16, N1_16D,
    N1_8T, N1_8, N1_8D,
    N1_4T, N1_4, N1_4D,
    N1_2T, N1_2, N1_2D,
    N1_1T, N1_1, N1_1D,
    N2_1, N4_1,
}

impl NoteValue {
    /// Returns the beat multiplier (quarter note = 1.0)
    pub fn beats(self) -> f64 {
        match self {
            NoteValue::N1_64  => 0.0625,
            NoteValue::N1_32  => 0.125,
            NoteValue::N1_16T => 1.0 / 6.0,    // triplet 16th
            NoteValue::N1_16  => 0.25,
            NoteValue::N1_16D => 0.375,          // dotted 16th
            NoteValue::N1_8T  => 1.0 / 3.0,     // triplet 8th
            NoteValue::N1_8   => 0.5,
            NoteValue::N1_8D  => 0.75,           // dotted 8th
            NoteValue::N1_4T  => 2.0 / 3.0,     // triplet quarter
            NoteValue::N1_4   => 1.0,
            NoteValue::N1_4D  => 1.5,            // dotted quarter
            NoteValue::N1_2T  => 4.0 / 3.0,     // triplet half
            NoteValue::N1_2   => 2.0,
            NoteValue::N1_2D  => 3.0,            // dotted half
            NoteValue::N1_1T  => 8.0 / 3.0,     // triplet whole
            NoteValue::N1_1   => 4.0,
            NoteValue::N1_1D  => 6.0,            // dotted whole
            NoteValue::N2_1   => 8.0,            // 2 bars
            NoteValue::N4_1   => 16.0,           // 4 bars
        }
    }

    /// Convert BPM + note value to delay time in ms
    pub fn to_ms(self, bpm: f64) -> f64 {
        let beat_ms = 60000.0 / bpm; // ms per quarter note
        beat_ms * self.beats()
    }

    /// Convert index (0-18) to NoteValue
    pub fn from_index(idx: u8) -> Self {
        match idx {
            0 => NoteValue::N1_64, 1 => NoteValue::N1_32,
            2 => NoteValue::N1_16T, 3 => NoteValue::N1_16, 4 => NoteValue::N1_16D,
            5 => NoteValue::N1_8T, 6 => NoteValue::N1_8, 7 => NoteValue::N1_8D,
            8 => NoteValue::N1_4T, 9 => NoteValue::N1_4, 10 => NoteValue::N1_4D,
            11 => NoteValue::N1_2T, 12 => NoteValue::N1_2, 13 => NoteValue::N1_2D,
            14 => NoteValue::N1_1T, 15 => NoteValue::N1_1, 16 => NoteValue::N1_1D,
            17 => NoteValue::N2_1, 18 => NoteValue::N4_1,
            _ => NoteValue::N1_4,
        }
    }
}

/// Vintage delay character mode (D7)
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum VintageMode {
    Clean,     // No coloring
    Tape,      // Wow + flutter + saturation
    BBD,       // Bucket brigade: clock noise, LP degradation
    OilCan,    // Spring-based: nonlinear response
    LoFi,      // Bit crush + sample rate reduction
}

/// Analog character processor for feedback path (D7)
#[derive(Debug, Clone)]
pub struct VintageProcessor {
    mode: VintageMode,
    amount: f64,        // 0.0 - 1.0
    // Tape wow/flutter
    wow_phase: f64,     // 0.5-3Hz
    flutter_phase: f64, // 3-15Hz
    // BBD state
    bbd_lp: BiquadTDF2,
    bbd_lp_r: BiquadTDF2,
    bbd_noise_phase: f64,
    // LoFi state
    lofi_hold_l: f64,
    lofi_hold_r: f64,
    lofi_counter: u32,
    sample_rate: f64,
}

impl VintageProcessor {
    pub fn new(sample_rate: f64) -> Self {
        let mut bbd_lp = BiquadTDF2::new(sample_rate);
        bbd_lp.set_lowpass(8000.0, 0.707);
        let mut bbd_lp_r = BiquadTDF2::new(sample_rate);
        bbd_lp_r.set_lowpass(8000.0, 0.707);
        Self {
            mode: VintageMode::Clean,
            amount: 0.5,
            wow_phase: 0.0,
            flutter_phase: 0.0,
            bbd_lp,
            bbd_lp_r,
            bbd_noise_phase: 0.0,
            lofi_hold_l: 0.0,
            lofi_hold_r: 0.0,
            lofi_counter: 0,
            sample_rate,
        }
    }

    pub fn set_mode(&mut self, mode: VintageMode) {
        self.mode = mode;
    }

    pub fn set_amount(&mut self, amount: f64) {
        self.amount = amount.clamp(0.0, 1.0);
    }

    /// Process stereo sample through vintage character
    #[inline]
    pub fn process(&mut self, l: f64, r: f64) -> (f64, f64) {
        if self.mode == VintageMode::Clean || self.amount < 0.001 {
            return (l, r);
        }
        let amt = self.amount;
        match self.mode {
            VintageMode::Clean => (l, r),
            VintageMode::Tape => {
                // Wow: slow pitch modulation (1.5Hz)
                let wow = (self.wow_phase * std::f64::consts::TAU).sin() * 0.002 * amt;
                self.wow_phase += 1.5 / self.sample_rate;
                if self.wow_phase >= 1.0 { self.wow_phase -= 1.0; }
                // Flutter: fast pitch modulation (8Hz)
                let flutter = (self.flutter_phase * std::f64::consts::TAU).sin() * 0.001 * amt;
                self.flutter_phase += 8.0 / self.sample_rate;
                if self.flutter_phase >= 1.0 { self.flutter_phase -= 1.0; }
                // Tape saturation: tanh with 2nd harmonic emphasis
                let sat = |x: f64| -> f64 {
                    let gained = x * (1.0 + amt * 2.0);
                    let clean = x;
                    let saturated = gained.tanh() + (gained * 2.0).sin() * 0.05 * amt;
                    clean * (1.0 - amt) + saturated * amt
                };
                let mod_factor = 1.0 + wow + flutter;
                (sat(l) * mod_factor, sat(r) * mod_factor)
            }
            VintageMode::BBD => {
                // LP degradation per repeat (amount controls cutoff)
                let cutoff = 20000.0 - amt * 16000.0; // 20kHz → 4kHz
                self.bbd_lp.set_lowpass(cutoff.max(500.0), 0.707);
                self.bbd_lp_r.set_lowpass(cutoff.max(500.0), 0.707);
                let filt_l = self.bbd_lp.process_sample(l);
                let filt_r = self.bbd_lp_r.process_sample(r);
                // Clock noise
                self.bbd_noise_phase += 1.0;
                let noise = ((self.bbd_noise_phase * 7919.0).sin() * 43758.5453).fract() * 2.0 - 1.0;
                let noise_amt = noise * 0.005 * amt;
                (filt_l + noise_amt, filt_r + noise_amt)
            }
            VintageMode::OilCan => {
                // Nonlinear spring-like response
                let spring = |x: f64| -> f64 {
                    let soft = x.tanh();
                    // Add slight resonance via cubic nonlinearity
                    soft + soft * soft * soft * 0.1 * amt
                };
                // Slow modulation (spring wobble)
                let wobble = (self.wow_phase * std::f64::consts::TAU).sin() * 0.003 * amt;
                self.wow_phase += 0.8 / self.sample_rate;
                if self.wow_phase >= 1.0 { self.wow_phase -= 1.0; }
                (spring(l) * (1.0 + wobble), spring(r) * (1.0 - wobble))
            }
            VintageMode::LoFi => {
                // Bit crush: reduce to 4-16 bits based on amount
                let bits = 16.0 - amt * 12.0; // 16 → 4 bits
                let levels = (2.0_f64).powf(bits);
                let crush = |x: f64| -> f64 {
                    (x * levels).round() / levels
                };
                // Sample rate reduction: downsample by factor
                let sr_factor = (1.0 + amt * 15.0) as u32; // 1× → 16×
                self.lofi_counter += 1;
                if self.lofi_counter >= sr_factor {
                    self.lofi_counter = 0;
                    self.lofi_hold_l = crush(l);
                    self.lofi_hold_r = crush(r);
                }
                let clean_l = l;
                let clean_r = r;
                (clean_l * (1.0 - amt) + self.lofi_hold_l * amt,
                 clean_r * (1.0 - amt) + self.lofi_hold_r * amt)
            }
        }
    }

    pub fn reset(&mut self) {
        self.wow_phase = 0.0;
        self.flutter_phase = 0.0;
        self.bbd_lp.reset();
        self.bbd_lp_r.reset();
        self.bbd_noise_phase = 0.0;
        self.lofi_hold_l = 0.0;
        self.lofi_hold_r = 0.0;
        self.lofi_counter = 0;
    }

    pub fn set_sample_rate(&mut self, sr: f64) {
        self.sample_rate = sr;
        self.bbd_lp.set_sample_rate(sr);
        self.bbd_lp_r.set_sample_rate(sr);
    }
}

/// Stereo routing topology (D5.1)
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum StereoRouting {
    Stereo,     // Independent L/R
    PingPong,   // Classic ping-pong (existing behavior)
    CrossFeed,  // L feedback → R and vice versa
    DualMono,   // Same signal to both channels
    MidSide,    // Process in M/S domain
}

/// Stereo ping-pong delay
#[derive(Debug, Clone)]
pub struct PingPongDelay {
    buffer_l: Vec<Sample>,
    buffer_r: Vec<Sample>,
    write_pos: usize,
    delay_samples: usize,       // L delay (or shared when linked)
    delay_samples_r: usize,     // R delay (independent, D3.6)
    max_delay_samples: usize,
    // D10.3: Delay time smoothing (fractional for interpolated reads)
    smooth_delay_l: f64,         // current smoothed delay in samples (fractional)
    smooth_delay_r: f64,
    delay_smoothing: f64,        // smoothing coefficient (0=instant, 0.9999=very slow)
    feedback: f64,
    dry_wet: f64,
    ping_pong: f64, // 0.0 = normal stereo, 1.0 = full ping-pong

    // Tempo sync (D3)
    tempo_sync: bool,
    bpm: f64,
    note_value_l: NoteValue,
    note_value_r: NoteValue,    // Independent R note (D3.6)
    lr_linked: bool,            // L/R time linked
    swing: f64,                 // 0.0-1.0, shifts every other repeat (D3.3)
    swing_counter: u32,         // Track even/odd repeats for swing

    // Feedback filtering — 3-band: HP + parametric mid + LP
    highpass_l: BiquadTDF2,
    highpass_r: BiquadTDF2,
    mid_l: BiquadTDF2,
    mid_r: BiquadTDF2,
    lowpass_l: BiquadTDF2,
    lowpass_r: BiquadTDF2,
    mid_enabled: bool,

    // Filter params (cached for recalc)
    hp_freq: f64,
    hp_q: f64,
    lp_freq: f64,
    lp_q: f64,
    mid_freq: f64,
    mid_q: f64,
    mid_gain_db: f64,

    // Feedback drive/saturation
    drive_amount: f64, // 0.0 = clean, 1.0 = full saturation
    drive_mode: DriveMode,

    // Feedback tilt EQ
    tilt_db_per_oct: f64, // -6.0 to +6.0 dB/oct (0 = flat)
    tilt_lp_l: BiquadTDF2,
    tilt_hp_l: BiquadTDF2,
    tilt_lp_r: BiquadTDF2,
    tilt_hp_r: BiquadTDF2,

    // Filter LFO modulation (legacy — kept for backward compat, but prefer mod matrix)
    filter_lfo_rate: f64,   // Hz (0 = off)
    filter_lfo_depth: f64,  // 0.0 - 1.0 (fraction of filter freq range)
    filter_lfo_phase: f64,
    filter_lfo_shape: LfoShape,

    // === D2 Modulation Engine ===
    lfo1: DelayLfo,
    lfo2: DelayLfo,
    env_follower: EnvelopeFollower,
    mod_matrix: ModulationMatrix,
    pitch_shifter_l: PitchShifter,
    pitch_shifter_r: PitchShifter,

    // D6 Freeze & Glitch
    reverse_enabled: bool,          // D6.2 — read buffer backwards
    stutter_enabled: bool,          // D6.3 — retrigger fragment
    stutter_samples: usize,         // fragment length for stutter
    stutter_pos: usize,             // current stutter read position
    stutter_decay: f64,             // 0.0-1.0 per-repeat decay
    infinite_fb: bool,              // D6.5 — feedback=100% + soft limiter
    freeze_fade_samples: usize,     // D6.4 — crossfade length for freeze
    freeze_fade_pos: usize,         // current position in fade

    // D5 Stereo & Spatial
    stereo_routing: StereoRouting,
    cross_feedback: f64,         // 0.0-1.0 cross-feedback amount (D5.2)
    haas_samples: usize,         // 0-30ms micro-delay for widening (D5.4)
    diffusion_amount: f64,       // 0.0-1.0 allpass output smearing (D5.5)
    diffusion_ap: [BiquadTDF2; 4], // 4 allpass stages for diffusion

    // D7 Vintage character
    vintage: VintageProcessor,

    sample_rate: f64,
}

/// Drive/saturation mode for feedback path
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DriveMode {
    /// tanh soft-clip — warm, musical
    Tube,
    /// Tape-style asymmetric saturation (2nd harmonic emphasis)
    Tape,
    /// Hard-clip transistor — aggressive, bright
    Transistor,
}

/// LFO waveshape for delay modulation (D2.1 — 7 shapes)
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LfoShape {
    Sine,
    Triangle,
    SawUp,
    SawDown,
    Square,
    SampleAndHold,
    RandomSmooth,
}

/// Modulation target for the delay modulation matrix (D2.5)
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ModTarget {
    DelayTime,    // ±50% of base delay time
    Feedback,     // ±0.5
    FilterHp,     // ±2 octaves of HP freq
    FilterLp,     // ±2 octaves of LP freq
    Pan,          // ±1.0 stereo
    Drive,        // ±0.5
    PitchShift,   // ±12 semitones
}

/// Full-featured LFO for delay modulation (D2.1 + D2.2 + D2.6)
#[derive(Debug, Clone)]
pub struct DelayLfo {
    phase: f64,
    rate_hz: f64,
    depth: f64,          // 0.0 - 1.0
    shape: LfoShape,
    // Tempo sync (D2.2)
    sync_enabled: bool,
    sync_division: f64,  // Note value: 1.0 = quarter, 0.5 = eighth, 2.0 = half, etc.
    bpm: f64,
    // Retrigger (D2.6)
    retrigger_enabled: bool,
    // S&H / RandomSmooth state
    sh_value: f64,
    sh_prev: f64,
    sh_target: f64,
    sh_counter: u32,
    sample_rate: f64,
}

impl DelayLfo {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            phase: 0.0,
            rate_hz: 1.0,
            depth: 0.0,
            shape: LfoShape::Sine,
            sync_enabled: false,
            sync_division: 1.0,
            bpm: 120.0,
            retrigger_enabled: false,
            sh_value: 0.0,
            sh_prev: 0.0,
            sh_target: 0.0,
            sh_counter: 0,
            sample_rate,
        }
    }

    pub fn set_rate(&mut self, hz: f64) {
        self.rate_hz = hz.clamp(0.01, 20.0);
    }

    pub fn set_depth(&mut self, depth: f64) {
        self.depth = depth.clamp(0.0, 1.0);
    }

    pub fn set_shape(&mut self, shape: LfoShape) {
        self.shape = shape;
    }

    pub fn set_sync(&mut self, enabled: bool) {
        self.sync_enabled = enabled;
    }

    /// Set sync division: 1.0 = 1/4, 0.5 = 1/8, 2.0 = 1/2, 4.0 = 1/1, etc.
    pub fn set_sync_division(&mut self, div: f64) {
        self.sync_division = div.clamp(0.0625, 16.0); // 1/64 to 4 bars
    }

    pub fn set_bpm(&mut self, bpm: f64) {
        self.bpm = bpm.clamp(20.0, 999.0);
    }

    pub fn set_retrigger(&mut self, enabled: bool) {
        self.retrigger_enabled = enabled;
    }

    /// Reset phase to 0 (for retrigger on transient — D2.6)
    pub fn retrigger(&mut self) {
        self.phase = 0.0;
    }

    /// Get effective rate (free-running or tempo-synced)
    fn effective_rate(&self) -> f64 {
        if self.sync_enabled {
            // BPM to Hz: quarter note = bpm/60, then divide by sync_division
            self.bpm / (60.0 * self.sync_division)
        } else {
            self.rate_hz
        }
    }

    /// Compute LFO value for current phase (-1.0 to 1.0) and advance
    pub fn tick(&mut self) -> f64 {
        if self.depth < 0.001 {
            return 0.0;
        }

        let rate = self.effective_rate();
        let p = self.phase;

        let raw = match self.shape {
            LfoShape::Sine => (p * std::f64::consts::TAU).sin(),
            LfoShape::Triangle => {
                if p < 0.25 { p * 4.0 }
                else if p < 0.75 { 2.0 - p * 4.0 }
                else { p * 4.0 - 4.0 }
            }
            LfoShape::SawUp => p * 2.0 - 1.0,
            LfoShape::SawDown => 1.0 - p * 2.0,
            LfoShape::Square => if p < 0.5 { 1.0 } else { -1.0 },
            LfoShape::SampleAndHold => {
                // New random value at start of each cycle
                self.sh_value
            }
            LfoShape::RandomSmooth => {
                // Cosine interpolation between random targets
                let t = p;
                let cos_interp = (1.0 - (t * std::f64::consts::PI).cos()) * 0.5;
                self.sh_prev * (1.0 - cos_interp) + self.sh_target * cos_interp
            }
        };

        // Advance phase
        self.phase += rate / self.sample_rate;
        if self.phase >= 1.0 {
            self.phase -= 1.0;
            // New S&H value on cycle boundary
            self.sh_counter = self.sh_counter.wrapping_add(1);
            let hash = self.sh_counter.wrapping_mul(2654435761) & 0xFFFF;
            let new_val = hash as f64 / 65535.0 * 2.0 - 1.0;
            self.sh_value = new_val;
            self.sh_prev = self.sh_target;
            self.sh_target = new_val;
        }

        raw * self.depth
    }

    /// Advance by N samples (block mode), return average value for the block
    pub fn tick_block(&mut self, num_samples: usize) -> f64 {
        if self.depth < 0.001 || num_samples == 0 {
            return 0.0;
        }
        // Sample at midpoint of block for efficiency
        let rate = self.effective_rate();
        let half = num_samples as f64 * 0.5;
        let mid_phase = self.phase + rate / self.sample_rate * half;
        let mid_phase = mid_phase.rem_euclid(1.0);

        let val = match self.shape {
            LfoShape::Sine => (mid_phase * std::f64::consts::TAU).sin(),
            LfoShape::Triangle => {
                if mid_phase < 0.25 { mid_phase * 4.0 }
                else if mid_phase < 0.75 { 2.0 - mid_phase * 4.0 }
                else { mid_phase * 4.0 - 4.0 }
            }
            LfoShape::SawUp => mid_phase * 2.0 - 1.0,
            LfoShape::SawDown => 1.0 - mid_phase * 2.0,
            LfoShape::Square => if mid_phase < 0.5 { 1.0 } else { -1.0 },
            LfoShape::SampleAndHold => self.sh_value,
            LfoShape::RandomSmooth => {
                let t = mid_phase;
                let cos_interp = (1.0 - (t * std::f64::consts::PI).cos()) * 0.5;
                self.sh_prev * (1.0 - cos_interp) + self.sh_target * cos_interp
            }
        };

        // Advance phase by full block
        self.phase += rate / self.sample_rate * num_samples as f64;
        while self.phase >= 1.0 {
            self.phase -= 1.0;
            self.sh_counter = self.sh_counter.wrapping_add(1);
            let hash = self.sh_counter.wrapping_mul(2654435761) & 0xFFFF;
            let new_val = hash as f64 / 65535.0 * 2.0 - 1.0;
            self.sh_value = new_val;
            self.sh_prev = self.sh_target;
            self.sh_target = new_val;
        }

        val * self.depth
    }

    pub fn reset(&mut self) {
        self.phase = 0.0;
        self.sh_value = 0.0;
        self.sh_prev = 0.0;
        self.sh_target = 0.0;
        self.sh_counter = 0;
    }

    pub fn set_sample_rate(&mut self, sr: f64) {
        self.sample_rate = sr;
    }
}

/// Envelope follower for input-driven modulation (D2.4)
#[derive(Debug, Clone)]
pub struct EnvelopeFollower {
    envelope: f64,
    attack_coef: f64,
    release_coef: f64,
    sensitivity: f64,   // 0.0 - 1.0, scales output
    sample_rate: f64,
}

impl EnvelopeFollower {
    pub fn new(sample_rate: f64) -> Self {
        let mut ef = Self {
            envelope: 0.0,
            attack_coef: 0.0,
            release_coef: 0.0,
            sensitivity: 0.5,
            sample_rate,
        };
        ef.set_attack_ms(5.0);
        ef.set_release_ms(50.0);
        ef
    }

    pub fn set_attack_ms(&mut self, ms: f64) {
        let ms = ms.clamp(0.1, 100.0);
        self.attack_coef = (-1.0 / (ms * 0.001 * self.sample_rate)).exp();
    }

    pub fn set_release_ms(&mut self, ms: f64) {
        let ms = ms.clamp(1.0, 1000.0);
        self.release_coef = (-1.0 / (ms * 0.001 * self.sample_rate)).exp();
    }

    pub fn set_sensitivity(&mut self, sens: f64) {
        self.sensitivity = sens.clamp(0.0, 1.0);
    }

    /// Process a stereo block and return the envelope value (0.0 - 1.0)
    pub fn process_block(&mut self, left: &[f64], right: &[f64]) -> f64 {
        let len = left.len().min(right.len());
        for i in 0..len {
            let input = (left[i].abs() + right[i].abs()) * 0.5;
            let coef = if input > self.envelope {
                self.attack_coef
            } else {
                self.release_coef
            };
            self.envelope = input + coef * (self.envelope - input);
        }
        (self.envelope * self.sensitivity).clamp(0.0, 1.0)
    }

    pub fn reset(&mut self) {
        self.envelope = 0.0;
    }

    pub fn set_sample_rate(&mut self, sr: f64) {
        let old_sr = self.sample_rate;
        self.sample_rate = sr;
        // Recalculate coefficients — preserve time constants
        let att_ms = if self.attack_coef > 0.0 {
            -1.0 / (self.attack_coef.ln() * old_sr) * 1000.0
        } else {
            5.0
        };
        let rel_ms = if self.release_coef > 0.0 {
            -1.0 / (self.release_coef.ln() * old_sr) * 1000.0
        } else {
            50.0
        };
        self.set_attack_ms(att_ms);
        self.set_release_ms(rel_ms);
    }
}

/// Single modulation routing: source → target with amount (D2.5)
#[derive(Debug, Clone, Copy)]
pub struct ModRoute {
    pub target: ModTarget,
    pub amount: f64, // -1.0 to 1.0
}

/// Modulation matrix: routes LFO1, LFO2, ENV to multiple targets (D2.5)
#[derive(Debug, Clone)]
pub struct ModulationMatrix {
    /// LFO1 routes (up to 4 targets)
    pub lfo1_routes: Vec<ModRoute>,
    /// LFO2 routes (up to 4 targets)
    pub lfo2_routes: Vec<ModRoute>,
    /// Envelope follower routes (up to 4 targets)
    pub env_routes: Vec<ModRoute>,
}

impl ModulationMatrix {
    pub fn new() -> Self {
        Self {
            lfo1_routes: Vec::new(),
            lfo2_routes: Vec::new(),
            env_routes: Vec::new(),
        }
    }

    /// Add an LFO1 → target route
    pub fn add_lfo1_route(&mut self, target: ModTarget, amount: f64) {
        if self.lfo1_routes.len() < 4 {
            self.lfo1_routes.push(ModRoute { target, amount: amount.clamp(-1.0, 1.0) });
        }
    }

    /// Add an LFO2 → target route
    pub fn add_lfo2_route(&mut self, target: ModTarget, amount: f64) {
        if self.lfo2_routes.len() < 4 {
            self.lfo2_routes.push(ModRoute { target, amount: amount.clamp(-1.0, 1.0) });
        }
    }

    /// Add an ENV → target route
    pub fn add_env_route(&mut self, target: ModTarget, amount: f64) {
        if self.env_routes.len() < 4 {
            self.env_routes.push(ModRoute { target, amount: amount.clamp(-1.0, 1.0) });
        }
    }

    /// Clear all routes
    pub fn clear(&mut self) {
        self.lfo1_routes.clear();
        self.lfo2_routes.clear();
        self.env_routes.clear();
    }

    /// Compute summed modulation for each target given source values
    /// Returns: (delay_time, feedback, filter_hp, filter_lp, pan, drive, pitch_shift)
    pub fn compute(&self, lfo1_val: f64, lfo2_val: f64, env_val: f64) -> ModOutput {
        let mut out = ModOutput::default();

        for route in &self.lfo1_routes {
            out.apply(route.target, lfo1_val * route.amount);
        }
        for route in &self.lfo2_routes {
            out.apply(route.target, lfo2_val * route.amount);
        }
        for route in &self.env_routes {
            out.apply(route.target, env_val * route.amount);
        }

        out
    }
}

/// Accumulated modulation output from the matrix
#[derive(Debug, Clone, Copy, Default)]
pub struct ModOutput {
    pub delay_time: f64,
    pub feedback: f64,
    pub filter_hp: f64,
    pub filter_lp: f64,
    pub pan: f64,
    pub drive: f64,
    pub pitch_shift: f64,
}

impl ModOutput {
    fn apply(&mut self, target: ModTarget, value: f64) {
        match target {
            ModTarget::DelayTime => self.delay_time += value,
            ModTarget::Feedback => self.feedback += value,
            ModTarget::FilterHp => self.filter_hp += value,
            ModTarget::FilterLp => self.filter_lp += value,
            ModTarget::Pan => self.pan += value,
            ModTarget::Drive => self.drive += value,
            ModTarget::PitchShift => self.pitch_shift += value,
        }
    }
}

/// Simple granular pitch shifter for feedback path (D2.7)
/// Uses two overlapping grains with crossfade for smooth shifting
#[derive(Debug, Clone)]
pub struct PitchShifter {
    buffer: Vec<f64>,
    write_pos: usize,
    read_pos_a: f64,
    read_pos_b: f64,
    grain_phase: f64,
    shift_ratio: f64,   // 1.0 = no shift, 2.0 = octave up, 0.5 = octave down
    buf_len: usize,
    enabled: bool,
}

impl PitchShifter {
    pub fn new(sample_rate: f64) -> Self {
        let buf_len = (sample_rate * 0.1) as usize; // 100ms buffer
        Self {
            buffer: vec![0.0; buf_len],
            write_pos: 0,
            read_pos_a: 0.0,
            read_pos_b: buf_len as f64 * 0.5,
            grain_phase: 0.0,
            shift_ratio: 1.0,
            buf_len,
            enabled: false,
        }
    }

    /// Set pitch shift in semitones (-12 to +12)
    pub fn set_semitones(&mut self, semitones: f64) {
        let st = semitones.clamp(-12.0, 12.0);
        self.shift_ratio = (2.0_f64).powf(st / 12.0);
        self.enabled = st.abs() > 0.01;
    }

    /// Process a single sample through pitch shifter
    #[inline]
    pub fn process(&mut self, input: f64) -> f64 {
        if !self.enabled {
            return input;
        }

        // Write
        self.buffer[self.write_pos] = input;
        self.write_pos = (self.write_pos + 1) % self.buf_len;

        // Read with two grains
        let len = self.buf_len as f64;
        let idx_a = self.read_pos_a.rem_euclid(len) as usize;
        let idx_b = self.read_pos_b.rem_euclid(len) as usize;
        let frac_a = self.read_pos_a.rem_euclid(len) - idx_a as f64;
        let frac_b = self.read_pos_b.rem_euclid(len) - idx_b as f64;

        // Linear interpolation for each grain
        let sa = self.buffer[idx_a % self.buf_len] * (1.0 - frac_a)
            + self.buffer[(idx_a + 1) % self.buf_len] * frac_a;
        let sb = self.buffer[idx_b % self.buf_len] * (1.0 - frac_b)
            + self.buffer[(idx_b + 1) % self.buf_len] * frac_b;

        // Crossfade: triangle window on grain_phase
        let fade_a = if self.grain_phase < 0.5 {
            self.grain_phase * 2.0
        } else {
            2.0 - self.grain_phase * 2.0
        };
        let fade_b = 1.0 - fade_a;

        // Advance read positions
        self.read_pos_a += self.shift_ratio;
        self.read_pos_b += self.shift_ratio;
        if self.read_pos_a >= len { self.read_pos_a -= len; }
        if self.read_pos_b >= len { self.read_pos_b -= len; }

        // Advance grain phase
        self.grain_phase += 1.0 / (self.buf_len as f64 * 0.5);
        if self.grain_phase >= 1.0 {
            self.grain_phase -= 1.0;
            // Reset grain A to write position when phase wraps
            self.read_pos_a = (self.write_pos as f64 - self.buf_len as f64 * 0.25).rem_euclid(len);
        }

        sa * fade_a + sb * fade_b
    }

    pub fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
        self.read_pos_a = 0.0;
        self.read_pos_b = self.buf_len as f64 * 0.5;
        self.grain_phase = 0.0;
    }

    pub fn set_sample_rate(&mut self, sr: f64) {
        let buf_len = (sr * 0.1) as usize;
        self.buffer = vec![0.0; buf_len];
        self.buf_len = buf_len;
        self.reset();
    }
}

impl PingPongDelay {
    pub fn new(sample_rate: f64, max_delay_ms: f64) -> Self {
        let max_delay_samples = (max_delay_ms * 0.001 * sample_rate) as usize;

        let default_delay = (500.0 * 0.001 * sample_rate) as usize;
        let mut delay = Self {
            buffer_l: vec![0.0; max_delay_samples],
            buffer_r: vec![0.0; max_delay_samples],
            write_pos: 0,
            delay_samples: default_delay,
            delay_samples_r: default_delay,
            max_delay_samples,
            smooth_delay_l: default_delay as f64,
            smooth_delay_r: default_delay as f64,
            delay_smoothing: 0.999, // ~10ms smoothing at 48kHz
            feedback: 0.5,
            dry_wet: 0.5,
            ping_pong: 1.0,
            // D3 Tempo Sync
            tempo_sync: false,
            bpm: 120.0,
            note_value_l: NoteValue::N1_4,
            note_value_r: NoteValue::N1_4,
            lr_linked: true,
            swing: 0.0,
            swing_counter: 0,
            highpass_l: BiquadTDF2::new(sample_rate),
            highpass_r: BiquadTDF2::new(sample_rate),
            mid_l: BiquadTDF2::new(sample_rate),
            mid_r: BiquadTDF2::new(sample_rate),
            lowpass_l: BiquadTDF2::new(sample_rate),
            lowpass_r: BiquadTDF2::new(sample_rate),
            mid_enabled: false,
            hp_freq: 80.0,
            hp_q: 0.707,
            lp_freq: 8000.0,
            lp_q: 0.707,
            mid_freq: 1000.0,
            mid_q: 1.0,
            mid_gain_db: 0.0,
            drive_amount: 0.0,
            drive_mode: DriveMode::Tube,
            tilt_db_per_oct: 0.0,
            tilt_lp_l: BiquadTDF2::new(sample_rate),
            tilt_hp_l: BiquadTDF2::new(sample_rate),
            tilt_lp_r: BiquadTDF2::new(sample_rate),
            tilt_hp_r: BiquadTDF2::new(sample_rate),
            filter_lfo_rate: 0.0,
            filter_lfo_depth: 0.0,
            filter_lfo_phase: 0.0,
            filter_lfo_shape: LfoShape::Sine,
            // D2 Modulation Engine
            lfo1: DelayLfo::new(sample_rate),
            lfo2: DelayLfo::new(sample_rate),
            env_follower: EnvelopeFollower::new(sample_rate),
            mod_matrix: ModulationMatrix::new(),
            pitch_shifter_l: PitchShifter::new(sample_rate),
            pitch_shifter_r: PitchShifter::new(sample_rate),
            // D6 Freeze & Glitch
            reverse_enabled: false,
            stutter_enabled: false,
            stutter_samples: 0,
            stutter_pos: 0,
            stutter_decay: 0.95,
            infinite_fb: false,
            freeze_fade_samples: (0.05 * sample_rate) as usize, // 50ms default
            freeze_fade_pos: 0,
            // D5 Stereo
            stereo_routing: StereoRouting::PingPong,
            cross_feedback: 0.0,
            haas_samples: 0,
            diffusion_amount: 0.0,
            diffusion_ap: [
                BiquadTDF2::new(sample_rate), BiquadTDF2::new(sample_rate),
                BiquadTDF2::new(sample_rate), BiquadTDF2::new(sample_rate),
            ],
            vintage: VintageProcessor::new(sample_rate),
            sample_rate,
        };

        delay.highpass_l.set_highpass(80.0, 0.707);
        delay.highpass_r.set_highpass(80.0, 0.707);
        delay.lowpass_l.set_lowpass(8000.0, 0.707);
        delay.lowpass_r.set_lowpass(8000.0, 0.707);
        // Mid band defaults to unity (0dB gain = no effect)
        delay.mid_l.set_peaking(1000.0, 1.0, 0.0);
        delay.mid_r.set_peaking(1000.0, 1.0, 0.0);
        // Tilt shelves (stereo pairs)
        delay.tilt_lp_l.set_low_shelf(1000.0, 0.707, 0.0);
        delay.tilt_hp_l.set_high_shelf(1000.0, 0.707, 0.0);
        delay.tilt_lp_r.set_low_shelf(1000.0, 0.707, 0.0);
        delay.tilt_hp_r.set_high_shelf(1000.0, 0.707, 0.0);

        delay
    }

    pub fn set_delay_ms(&mut self, ms: f64) {
        let samples = (ms * 0.001 * self.sample_rate) as usize;
        self.delay_samples = samples.min(self.max_delay_samples - 1);
    }

    pub fn set_feedback(&mut self, feedback: f64) {
        self.feedback = feedback.clamp(0.0, 0.99);
    }

    pub fn set_dry_wet(&mut self, mix: f64) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }

    pub fn set_ping_pong(&mut self, amount: f64) {
        self.ping_pong = amount.clamp(0.0, 1.0);
    }

    /// Set feedback highpass filter frequency (Hz)
    pub fn set_hp_freq(&mut self, freq_hz: f64) {
        self.hp_freq = freq_hz.clamp(20.0, 2000.0);
        self.highpass_l.set_highpass(self.hp_freq, self.hp_q);
        self.highpass_r.set_highpass(self.hp_freq, self.hp_q);
    }

    /// Set feedback highpass Q (0.5 - 10.0)
    pub fn set_hp_q(&mut self, q: f64) {
        self.hp_q = q.clamp(0.5, 10.0);
        self.highpass_l.set_highpass(self.hp_freq, self.hp_q);
        self.highpass_r.set_highpass(self.hp_freq, self.hp_q);
    }

    /// Set feedback lowpass filter frequency (Hz)
    pub fn set_lp_freq(&mut self, freq_hz: f64) {
        self.lp_freq = freq_hz.clamp(200.0, 20000.0);
        self.lowpass_l.set_lowpass(self.lp_freq, self.lp_q);
        self.lowpass_r.set_lowpass(self.lp_freq, self.lp_q);
    }

    /// Set feedback lowpass Q (0.5 - 10.0)
    pub fn set_lp_q(&mut self, q: f64) {
        self.lp_q = q.clamp(0.5, 10.0);
        self.lowpass_l.set_lowpass(self.lp_freq, self.lp_q);
        self.lowpass_r.set_lowpass(self.lp_freq, self.lp_q);
    }

    /// Set feedback mid band frequency (Hz)
    pub fn set_mid_freq(&mut self, freq_hz: f64) {
        self.mid_freq = freq_hz.clamp(80.0, 16000.0);
        self.mid_l.set_peaking(self.mid_freq, self.mid_q, self.mid_gain_db);
        self.mid_r.set_peaking(self.mid_freq, self.mid_q, self.mid_gain_db);
        self.mid_enabled = self.mid_gain_db.abs() > 0.01;
    }

    /// Set feedback mid band Q (0.5 - 10.0)
    pub fn set_mid_q(&mut self, q: f64) {
        self.mid_q = q.clamp(0.5, 10.0);
        self.mid_l.set_peaking(self.mid_freq, self.mid_q, self.mid_gain_db);
        self.mid_r.set_peaking(self.mid_freq, self.mid_q, self.mid_gain_db);
    }

    /// Set feedback mid band gain (dB, -18 to +18)
    pub fn set_mid_gain(&mut self, gain_db: f64) {
        self.mid_gain_db = gain_db.clamp(-18.0, 18.0);
        self.mid_l.set_peaking(self.mid_freq, self.mid_q, self.mid_gain_db);
        self.mid_r.set_peaking(self.mid_freq, self.mid_q, self.mid_gain_db);
        self.mid_enabled = self.mid_gain_db.abs() > 0.01;
    }

    /// Set feedback drive amount (0.0 = clean, 1.0 = full saturation)
    pub fn set_drive(&mut self, amount: f64) {
        self.drive_amount = amount.clamp(0.0, 1.0);
    }

    /// Set drive saturation mode
    pub fn set_drive_mode(&mut self, mode: DriveMode) {
        self.drive_mode = mode;
    }

    /// Set feedback tilt EQ (-6.0 to +6.0 dB/oct, 0 = flat)
    /// Negative = darker each repeat, positive = brighter
    pub fn set_tilt(&mut self, db_per_oct: f64) {
        self.tilt_db_per_oct = db_per_oct.clamp(-6.0, 6.0);
        // Implement tilt via complementary shelves at 1kHz pivot
        // Positive tilt: boost highs + cut lows, negative: opposite
        let half = self.tilt_db_per_oct * 0.5;
        self.tilt_lp_l.set_low_shelf(1000.0, 0.707, -half);
        self.tilt_hp_l.set_high_shelf(1000.0, 0.707, half);
        self.tilt_lp_r.set_low_shelf(1000.0, 0.707, -half);
        self.tilt_hp_r.set_high_shelf(1000.0, 0.707, half);
    }

    // === D3 Tempo Sync & Rhythm Engine ===

    /// Enable/disable tempo sync (D3.1)
    pub fn set_tempo_sync(&mut self, enabled: bool) {
        self.tempo_sync = enabled;
        if enabled {
            self.recalc_synced_delay();
        }
    }

    /// Set BPM for tempo sync (D3.1 + D3.5 host sync)
    pub fn set_bpm(&mut self, bpm: f64) {
        self.bpm = bpm.clamp(20.0, 999.0);
        // Also forward to LFOs
        self.lfo1.set_bpm(bpm);
        self.lfo2.set_bpm(bpm);
        if self.tempo_sync {
            self.recalc_synced_delay();
        }
    }

    /// Set note value for L channel (D3.2) — index 0-18
    pub fn set_note_value_l(&mut self, idx: u8) {
        self.note_value_l = NoteValue::from_index(idx);
        if self.tempo_sync {
            self.recalc_synced_delay();
        }
    }

    /// Set note value for R channel (D3.6 independent L/R)
    pub fn set_note_value_r(&mut self, idx: u8) {
        self.note_value_r = NoteValue::from_index(idx);
        if self.tempo_sync {
            self.recalc_synced_delay();
        }
    }

    /// Set L/R link
    pub fn set_lr_linked(&mut self, linked: bool) {
        self.lr_linked = linked;
        if linked {
            self.note_value_r = self.note_value_l;
            self.delay_samples_r = self.delay_samples;
        }
        if self.tempo_sync {
            self.recalc_synced_delay();
        }
    }

    /// Set swing amount 0-100% (D3.3)
    pub fn set_swing(&mut self, pct: f64) {
        self.swing = (pct / 100.0).clamp(0.0, 1.0);
    }

    /// Set delay ms for R channel independently (when not linked/synced)
    pub fn set_delay_ms_r(&mut self, ms: f64) {
        let samples = (ms * 0.001 * self.sample_rate) as usize;
        self.delay_samples_r = samples.min(self.max_delay_samples - 1);
    }

    /// Recalculate delay times from BPM + note values
    fn recalc_synced_delay(&mut self) {
        let ms_l = self.note_value_l.to_ms(self.bpm);
        self.delay_samples = ((ms_l * 0.001 * self.sample_rate) as usize)
            .min(self.max_delay_samples - 1);

        if self.lr_linked {
            self.delay_samples_r = self.delay_samples;
        } else {
            let ms_r = self.note_value_r.to_ms(self.bpm);
            self.delay_samples_r = ((ms_r * 0.001 * self.sample_rate) as usize)
                .min(self.max_delay_samples - 1);
        }
    }

    // === D6 Freeze & Glitch ===

    /// Enable reverse delay (D6.2)
    pub fn set_reverse(&mut self, enabled: bool) {
        self.reverse_enabled = enabled;
    }

    /// Enable stutter mode (D6.3)
    pub fn set_stutter(&mut self, enabled: bool, note_div_ms: f64) {
        self.stutter_enabled = enabled;
        self.stutter_samples = ((note_div_ms * 0.001 * self.sample_rate) as usize)
            .max(1).min(self.max_delay_samples - 1);
        self.stutter_pos = 0;
    }

    pub fn set_stutter_decay(&mut self, decay: f64) {
        self.stutter_decay = decay.clamp(0.0, 1.0);
    }

    /// Enable infinite feedback mode (D6.5)
    pub fn set_infinite_feedback(&mut self, enabled: bool) {
        self.infinite_fb = enabled;
    }

    /// Set freeze fade time in ms (D6.4)
    pub fn set_freeze_fade_ms(&mut self, ms: f64) {
        self.freeze_fade_samples = ((ms.clamp(1.0, 500.0)) * 0.001 * self.sample_rate) as usize;
    }

    // === D5 Stereo & Spatial ===

    pub fn set_stereo_routing(&mut self, routing: StereoRouting) {
        self.stereo_routing = routing;
        // When switching to PingPong, set classic behavior
        if routing == StereoRouting::PingPong {
            self.ping_pong = 1.0;
        }
    }

    pub fn set_cross_feedback(&mut self, amount: f64) {
        self.cross_feedback = amount.clamp(0.0, 1.0);
    }

    /// Set Haas delay in ms (0-30ms) (D5.4)
    pub fn set_haas_ms(&mut self, ms: f64) {
        self.haas_samples = ((ms.clamp(0.0, 30.0)) * 0.001 * self.sample_rate) as usize;
    }

    pub fn set_diffusion(&mut self, amount: f64) {
        self.diffusion_amount = amount.clamp(0.0, 1.0);
    }

    // === D7 Vintage Character ===

    pub fn set_vintage_mode(&mut self, mode: VintageMode) {
        self.vintage.set_mode(mode);
    }

    pub fn set_vintage_amount(&mut self, amount: f64) {
        self.vintage.set_amount(amount);
    }

    // === D2 Modulation Engine public API ===

    /// Access LFO1 (D2.1 + D2.2)
    pub fn lfo1_mut(&mut self) -> &mut DelayLfo { &mut self.lfo1 }
    /// Access LFO2 (D2.3)
    pub fn lfo2_mut(&mut self) -> &mut DelayLfo { &mut self.lfo2 }
    /// Access envelope follower (D2.4)
    pub fn env_follower_mut(&mut self) -> &mut EnvelopeFollower { &mut self.env_follower }
    /// Access modulation matrix (D2.5)
    pub fn mod_matrix_mut(&mut self) -> &mut ModulationMatrix { &mut self.mod_matrix }
    /// Access pitch shifter L (D2.7)
    pub fn pitch_shifter_l_mut(&mut self) -> &mut PitchShifter { &mut self.pitch_shifter_l }
    /// Access pitch shifter R (D2.7)
    pub fn pitch_shifter_r_mut(&mut self) -> &mut PitchShifter { &mut self.pitch_shifter_r }

    /// Retrigger both LFOs (D2.6 — called on input transient)
    pub fn retrigger_lfos(&mut self) {
        if self.lfo1.retrigger_enabled {
            self.lfo1.retrigger();
        }
        if self.lfo2.retrigger_enabled {
            self.lfo2.retrigger();
        }
    }

    /// D10.3: Set delay time smoothing (0.0 = instant, 0.9999 = very slow glide)
    pub fn set_delay_smoothing(&mut self, amount: f64) {
        self.delay_smoothing = amount.clamp(0.0, 0.9999);
    }

    /// D10.3: Read from buffer with linear interpolation (fractional sample position)
    #[inline]
    fn read_interpolated(buffer: &[f64], pos: f64, len: usize) -> f64 {
        let pos_mod = pos.rem_euclid(len as f64);
        let idx = pos_mod as usize;
        let frac = pos_mod - idx as f64;
        let s0 = buffer[idx % len];
        let s1 = buffer[(idx + 1) % len];
        s0 + (s1 - s0) * frac
    }

    /// Process modulation for a block: computes LFO/ENV values and returns ModOutput
    /// Call this per block BEFORE process_sample loop
    pub fn compute_modulation(&mut self, left: &[f64], right: &[f64], block_size: usize) -> ModOutput {
        let lfo1_val = self.lfo1.tick_block(block_size);
        let lfo2_val = self.lfo2.tick_block(block_size);
        let env_val = self.env_follower.process_block(left, right);
        self.mod_matrix.compute(lfo1_val, lfo2_val, env_val)
    }

    /// Set filter LFO rate (Hz, 0 = off)
    pub fn set_filter_lfo_rate(&mut self, rate_hz: f64) {
        self.filter_lfo_rate = rate_hz.clamp(0.0, 20.0);
    }

    /// Set filter LFO depth (0.0 - 1.0)
    pub fn set_filter_lfo_depth(&mut self, depth: f64) {
        self.filter_lfo_depth = depth.clamp(0.0, 1.0);
    }

    /// Set filter LFO waveshape
    pub fn set_filter_lfo_shape(&mut self, shape: LfoShape) {
        self.filter_lfo_shape = shape;
    }

    /// Apply saturation to a sample based on current drive mode
    #[inline]
    fn apply_drive(sample: f64, amount: f64, mode: DriveMode) -> f64 {
        if amount < 0.001 {
            return sample;
        }
        // Drive gain: 1x at 0%, up to 4x at 100%
        let gained = sample * (1.0 + amount * 3.0);
        let saturated = match mode {
            DriveMode::Tube => {
                // tanh soft-clip — warm, musical
                gained.tanh()
            }
            DriveMode::Tape => {
                // Asymmetric soft-clip: 2nd harmonic emphasis
                let x = gained;
                if x >= 0.0 {
                    x.tanh()
                } else {
                    // Softer negative clipping → 2nd harmonic
                    (x * 0.8).tanh() * 1.25
                }
            }
            DriveMode::Transistor => {
                // Hard-clip with slight rounding
                let x = gained;
                if x > 1.0 {
                    1.0
                } else if x < -1.0 {
                    -1.0
                } else {
                    x - x * x * x / 3.0 // Cubic soft-clip
                }
            }
        };
        // Crossfade clean → saturated
        sample * (1.0 - amount) + saturated * amount
    }

    /// Compute filter LFO value and advance phase
    pub fn advance_filter_lfo(&mut self, num_samples: usize) -> f64 {
        if self.filter_lfo_rate < 0.001 || self.filter_lfo_depth < 0.001 {
            return 0.0;
        }
        let val = match self.filter_lfo_shape {
            LfoShape::Sine => (self.filter_lfo_phase * std::f64::consts::TAU).sin(),
            LfoShape::Triangle => {
                let p = self.filter_lfo_phase;
                if p < 0.25 { p * 4.0 }
                else if p < 0.75 { 2.0 - p * 4.0 }
                else { p * 4.0 - 4.0 }
            }
            LfoShape::SawUp => self.filter_lfo_phase * 2.0 - 1.0,
            LfoShape::Square => if self.filter_lfo_phase < 0.5 { 1.0 } else { -1.0 },
            LfoShape::SampleAndHold => {
                // Sample & hold — changes once per cycle
                let cycle = (self.filter_lfo_phase * 1000.0) as u64;
                let hash = cycle.wrapping_mul(2654435761) & 0xFFFF;
                hash as f64 / 65535.0 * 2.0 - 1.0
            }
            LfoShape::SawDown => 1.0 - self.filter_lfo_phase * 2.0,
            LfoShape::RandomSmooth => {
                // For filter LFO, treat like S&H (simplified)
                let cycle = (self.filter_lfo_phase * 1000.0) as u64;
                let hash = cycle.wrapping_mul(2654435761) & 0xFFFF;
                hash as f64 / 65535.0 * 2.0 - 1.0
            }
        };
        // Advance phase
        self.filter_lfo_phase += self.filter_lfo_rate / self.sample_rate * num_samples as f64;
        if self.filter_lfo_phase >= 1.0 {
            self.filter_lfo_phase -= 1.0;
        }
        val * self.filter_lfo_depth
    }
}

impl Processor for PingPongDelay {
    fn reset(&mut self) {
        self.buffer_l.fill(0.0);
        self.buffer_r.fill(0.0);
        self.write_pos = 0;
        self.highpass_l.reset();
        self.highpass_r.reset();
        self.mid_l.reset();
        self.mid_r.reset();
        self.lowpass_l.reset();
        self.lowpass_r.reset();
        self.tilt_lp_l.reset();
        self.tilt_hp_l.reset();
        self.tilt_lp_r.reset();
        self.tilt_hp_r.reset();
        self.filter_lfo_phase = 0.0;
        self.swing_counter = 0;
        self.stutter_pos = 0;
        self.freeze_fade_pos = 0;
        // D5 diffusion
        for ap in &mut self.diffusion_ap { ap.reset(); }
        // D7 vintage
        self.vintage.reset();
        // D2 modulation
        self.lfo1.reset();
        self.lfo2.reset();
        self.env_follower.reset();
        self.pitch_shifter_l.reset();
        self.pitch_shifter_r.reset();
    }
}

impl StereoProcessor for PingPongDelay {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // D10.3: Smooth delay time — exponential approach to target
        let target_l = self.delay_samples as f64;
        let target_r = if self.lr_linked { target_l } else { self.delay_samples_r as f64 };
        let coeff = self.delay_smoothing;
        self.smooth_delay_l = coeff * self.smooth_delay_l + (1.0 - coeff) * target_l;
        self.smooth_delay_r = coeff * self.smooth_delay_r + (1.0 - coeff) * target_r;

        let delay_l = self.smooth_delay_l;
        let delay_r = self.smooth_delay_r;

        // D6.2: Reverse — read backwards through delay buffer (grain-based)
        // Uses freeze_fade_pos as reverse playback counter
        let (delayed_l, delayed_r) = if self.reverse_enabled {
            let delay_l_int = delay_l as usize;
            let delay_r_int = delay_r as usize;
            let dl = delay_l_int.max(1);
            let dr = delay_r_int.max(1);
            // Reverse counter: counts 0..delay, reads from newest to oldest
            let rev_phase = self.freeze_fade_pos % dl;
            // Read from (write_pos - 1 - rev_phase) = newest first, going older
            let rev_read_l = (self.write_pos + self.max_delay_samples - 1 - rev_phase) % self.max_delay_samples;
            let rev_read_r = (self.write_pos + self.max_delay_samples - 1 - (self.freeze_fade_pos % dr)) % self.max_delay_samples;
            self.freeze_fade_pos = self.freeze_fade_pos.wrapping_add(1);
            (self.buffer_l[rev_read_l], self.buffer_r[rev_read_r])
        } else if self.stutter_enabled && self.stutter_samples > 0 {
            // D6.3: Stutter — loop a short fragment
            let base_l = (self.write_pos as f64 + self.max_delay_samples as f64 - delay_l).rem_euclid(self.max_delay_samples as f64) as usize;
            let s_pos = (base_l + self.stutter_pos) % self.max_delay_samples;
            self.stutter_pos = (self.stutter_pos + 1) % self.stutter_samples;
            (self.buffer_l[s_pos] * self.stutter_decay.powi((self.stutter_pos as f64 / self.stutter_samples as f64 * 4.0) as i32),
             self.buffer_r[s_pos] * self.stutter_decay.powi((self.stutter_pos as f64 / self.stutter_samples as f64 * 4.0) as i32))
        } else {
            // D10.3: Interpolated read for smooth delay changes
            let read_pos_l = self.write_pos as f64 + self.max_delay_samples as f64 - delay_l;
            let read_pos_r = self.write_pos as f64 + self.max_delay_samples as f64 - delay_r;
            (Self::read_interpolated(&self.buffer_l, read_pos_l, self.max_delay_samples),
             Self::read_interpolated(&self.buffer_r, read_pos_r, self.max_delay_samples))
        };

        // === Feedback processing chain: Drive → HP → Mid → LP → Tilt ===

        // 1. Drive/saturation (pre-filter for warmer character)
        let driven_l = Self::apply_drive(delayed_l, self.drive_amount, self.drive_mode);
        let driven_r = Self::apply_drive(delayed_r, self.drive_amount, self.drive_mode);

        // 2. Highpass filter
        let hp_l = self.highpass_l.process_sample(driven_l);
        let hp_r = self.highpass_r.process_sample(driven_r);

        // 3. Parametric mid (only when gain != 0)
        let mid_l = if self.mid_enabled {
            self.mid_l.process_sample(hp_l)
        } else {
            hp_l
        };
        let mid_r = if self.mid_enabled {
            self.mid_r.process_sample(hp_r)
        } else {
            hp_r
        };

        // 4. Lowpass filter
        let filtered_l = self.lowpass_l.process_sample(mid_l);
        let filtered_r = self.lowpass_r.process_sample(mid_r);

        // 5. Tilt EQ (spectral darkening/brightening per repeat)
        let tilted_l = if self.tilt_db_per_oct.abs() > 0.01 {
            self.tilt_hp_l.process_sample(self.tilt_lp_l.process_sample(filtered_l))
        } else {
            filtered_l
        };
        let tilted_r = if self.tilt_db_per_oct.abs() > 0.01 {
            self.tilt_hp_r.process_sample(self.tilt_lp_r.process_sample(filtered_r))
        } else {
            filtered_r
        };

        // 6. Pitch shift in feedback path (D2.7)
        let shifted_l = self.pitch_shifter_l.process(tilted_l);
        let shifted_r = self.pitch_shifter_r.process(tilted_r);

        // 7. Vintage character (D7)
        let (vint_l, vint_r) = self.vintage.process(shifted_l, shifted_r);

        // Stereo routing (D5.1)
        let (fb_l, fb_r) = match self.stereo_routing {
            StereoRouting::Stereo => {
                // Independent L/R — no crossfeed
                (vint_l, vint_r)
            }
            StereoRouting::PingPong => {
                // Classic ping-pong
                let pp = self.ping_pong;
                (vint_l * (1.0 - pp) + vint_r * pp,
                 vint_r * (1.0 - pp) + vint_l * pp)
            }
            StereoRouting::CrossFeed => {
                // Cross-feedback: L↔R bleed (D5.2)
                let cf = self.cross_feedback;
                (vint_l * (1.0 - cf) + vint_r * cf,
                 vint_r * (1.0 - cf) + vint_l * cf)
            }
            StereoRouting::DualMono => {
                // Mono sum to both channels
                let mono = (vint_l + vint_r) * 0.5;
                (mono, mono)
            }
            StereoRouting::MidSide => {
                // Process in M/S domain: boost side for wider stereo image
                let mid = (vint_l + vint_r) * 0.5;
                let side = (vint_l - vint_r) * 0.5;
                // Cross-feedback amount controls mid/side balance:
                // 0% = mid only (mono), 50% = normal, 100% = side only (wide)
                let side_boost = 1.0 + self.cross_feedback * 2.0; // 1.0 → 3.0
                let mid_cut = 1.0 - self.cross_feedback * 0.5;    // 1.0 → 0.5
                let ms_mid = mid * mid_cut;
                let ms_side = side * side_boost;
                (ms_mid + ms_side, ms_mid - ms_side)
            }
        };

        // Write to buffers (D6.5: infinite feedback with soft limiter)
        let eff_fb = if self.infinite_fb { 1.0 } else { self.feedback };
        let write_l = left + fb_l * eff_fb;
        let write_r = right + fb_r * eff_fb;
        // Soft limiter for infinite mode to prevent clipping
        self.buffer_l[self.write_pos] = if self.infinite_fb { write_l.tanh() } else { write_l };
        self.buffer_r[self.write_pos] = if self.infinite_fb { write_r.tanh() } else { write_r };
        self.write_pos = (self.write_pos + 1) % self.max_delay_samples;

        // Output with Haas delay on R channel (D5.4)
        // Note: write_pos was already incremented above, so subtract 1 to compensate
        let wet_l = delayed_l;
        let wet_r = if self.haas_samples > 0 && self.haas_samples < self.max_delay_samples {
            let haas_read = (self.write_pos as f64 - 1.0) + self.max_delay_samples as f64
                - delay_r - self.haas_samples as f64;
            Self::read_interpolated(&self.buffer_r, haas_read, self.max_delay_samples)
        } else {
            delayed_r
        };


        // Spatial diffusion on output (D5.5)
        let (diff_l, diff_r) = if self.diffusion_amount > 0.01 {
            let d = self.diffusion_amount;
            let tmp_l = self.diffusion_ap[1].process_sample(wet_l);
            let dl = self.diffusion_ap[0].process_sample(tmp_l);
            let tmp_r = self.diffusion_ap[3].process_sample(wet_r);
            let dr = self.diffusion_ap[2].process_sample(tmp_r);
            (wet_l * (1.0 - d) + dl * d, wet_r * (1.0 - d) + dr * d)
        } else {
            (wet_l, wet_r)
        };

        let out_l = left * (1.0 - self.dry_wet) + diff_l * self.dry_wet;
        let out_r = right * (1.0 - self.dry_wet) + diff_r * self.dry_wet;

        (out_l, out_r)
    }
}

impl ProcessorConfig for PingPongDelay {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        let ratio = sample_rate / self.sample_rate;
        self.sample_rate = sample_rate;
        self.max_delay_samples = (self.max_delay_samples as f64 * ratio) as usize;
        self.delay_samples = (self.delay_samples as f64 * ratio) as usize;
        self.delay_samples_r = (self.delay_samples_r as f64 * ratio) as usize;
        self.buffer_l = vec![0.0; self.max_delay_samples];
        self.buffer_r = vec![0.0; self.max_delay_samples];
        self.highpass_l.set_sample_rate(sample_rate);
        self.highpass_r.set_sample_rate(sample_rate);
        self.mid_l.set_sample_rate(sample_rate);
        self.mid_r.set_sample_rate(sample_rate);
        self.lowpass_l.set_sample_rate(sample_rate);
        self.lowpass_r.set_sample_rate(sample_rate);
        self.tilt_lp_l.set_sample_rate(sample_rate);
        self.tilt_hp_l.set_sample_rate(sample_rate);
        self.tilt_lp_r.set_sample_rate(sample_rate);
        self.tilt_hp_r.set_sample_rate(sample_rate);
        // Recalculate filter coefficients at new sample rate
        self.set_hp_freq(self.hp_freq);
        self.set_lp_freq(self.lp_freq);
        self.set_mid_freq(self.mid_freq);
        self.set_tilt(self.tilt_db_per_oct);
        // D2 modulation
        self.lfo1.set_sample_rate(sample_rate);
        self.lfo2.set_sample_rate(sample_rate);
        self.env_follower.set_sample_rate(sample_rate);
        self.pitch_shifter_l.set_sample_rate(sample_rate);
        self.pitch_shifter_r.set_sample_rate(sample_rate);
        for ap in &mut self.diffusion_ap { ap.set_sample_rate(sample_rate); }
        self.vintage.set_sample_rate(sample_rate);
    }
}

/// Per-tap filter configuration
#[derive(Debug, Clone)]
pub struct TapFilter {
    hp: BiquadTDF2,
    lp: BiquadTDF2,
    hp_freq: f64,
    lp_freq: f64,
    enabled: bool,
}

impl TapFilter {
    fn new(sample_rate: f64) -> Self {
        let mut hp = BiquadTDF2::new(sample_rate);
        let mut lp = BiquadTDF2::new(sample_rate);
        hp.set_highpass(20.0, 0.707);
        lp.set_lowpass(20000.0, 0.707);
        Self { hp, lp, hp_freq: 20.0, lp_freq: 20000.0, enabled: false }
    }

    fn set_hp(&mut self, freq: f64) {
        self.hp_freq = freq.clamp(20.0, 2000.0);
        self.hp.set_highpass(self.hp_freq, 0.707);
        self.enabled = self.hp_freq > 25.0 || self.lp_freq < 19000.0;
    }

    fn set_lp(&mut self, freq: f64) {
        self.lp_freq = freq.clamp(200.0, 20000.0);
        self.lp.set_lowpass(self.lp_freq, 0.707);
        self.enabled = self.hp_freq > 25.0 || self.lp_freq < 19000.0;
    }

    #[inline]
    fn process(&mut self, sample: Sample) -> Sample {
        if !self.enabled {
            return sample;
        }
        self.lp.process_sample(self.hp.process_sample(sample))
    }

    fn reset(&mut self) {
        self.hp.reset();
        self.lp.reset();
    }
}

/// Per-tap configuration for MultiTapDelay
#[derive(Debug, Clone)]
pub struct TapConfig {
    pub delay_samples: usize,
    pub level: f64,
    pub pan: f64,
    pub feedback: f64,         // D4.2: per-tap feedback (0..1)
    pub pitch_semitones: f64,  // D4.3: per-tap pitch shift (-12..+12)
    pub diffusion: f64,        // D4.5: per-tap diffusion amount (0..1)
    pub active: bool,
}

/// Tap pattern preset (D4.4)
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TapPattern {
    Rhythmic,
    Cascade,
    PingPongSpread,
    Fibonacci,
    GoldenRatio,
    Random,
}

/// Multi-tap delay — D4 Pro upgrade: 16 taps, per-tap FB/pitch/diffusion, pattern presets
#[derive(Debug, Clone)]
pub struct MultiTapDelay {
    buffer: Vec<Sample>,
    write_pos: usize,
    max_delay_samples: usize,

    // D4.1: up to 16 taps
    taps: Vec<TapConfig>,
    tap_filters: Vec<TapFilter>,
    // D4.3: per-tap pitch shifters
    tap_pitch: Vec<PitchShifter>,
    // D4.5: per-tap diffusion (2-stage allpass per tap)
    tap_diffusion_ap: Vec<[[f64; 2]; 2]>, // [tap_idx][stage][z1,z2] — simplified 2-stage
    num_active_taps: usize,

    feedback: f64,   // global feedback (legacy compat)
    dry_wet: f64,

    sample_rate: f64,
    max_delay_ms: f64,
    rng_state: u64,  // D4.7: simple xorshift for randomize
}

const MAX_TAPS: usize = 16;

impl MultiTapDelay {
    pub fn new(sample_rate: f64, max_delay_ms: f64, num_taps: usize) -> Self {
        let max_delay_samples = (max_delay_ms * 0.001 * sample_rate) as usize;
        let n = num_taps.min(MAX_TAPS);

        let mut taps = Vec::with_capacity(MAX_TAPS);
        let mut tap_filters = Vec::with_capacity(MAX_TAPS);
        let mut tap_pitch = Vec::with_capacity(MAX_TAPS);
        let mut tap_diffusion_ap = Vec::with_capacity(MAX_TAPS);

        for i in 0..MAX_TAPS {
            let delay = if i < n {
                (i + 1) * max_delay_samples / (n + 1)
            } else {
                0
            };
            let level = if i < n { 1.0 / (i + 1) as f64 } else { 0.0 };
            let pan = if i % 2 == 0 { -0.3 } else { 0.3 };

            taps.push(TapConfig {
                delay_samples: delay,
                level,
                pan,
                feedback: 0.0,
                pitch_semitones: 0.0,
                diffusion: 0.0,
                active: i < n,
            });
            tap_filters.push(TapFilter::new(sample_rate));
            tap_pitch.push(PitchShifter::new(sample_rate));
            tap_diffusion_ap.push([[0.0; 2]; 2]);
        }

        Self {
            buffer: vec![0.0; max_delay_samples],
            write_pos: 0,
            max_delay_samples,
            taps,
            tap_filters,
            tap_pitch,
            tap_diffusion_ap,
            num_active_taps: n,
            feedback: 0.3,
            dry_wet: 0.5,
            sample_rate,
            max_delay_ms,
            rng_state: 0xDEAD_BEEF_CAFE_1234,
        }
    }

    pub fn set_tap(&mut self, index: usize, delay_ms: f64, level: f64, pan: f64) {
        if let Some(t) = self.taps.get_mut(index) {
            let delay_samples = (delay_ms * 0.001 * self.sample_rate) as usize;
            t.delay_samples = delay_samples.min(self.max_delay_samples.saturating_sub(1));
            t.level = level.clamp(0.0, 1.0);
            t.pan = pan.clamp(-1.0, 1.0);
        }
    }

    /// D4.2: Set per-tap feedback amount
    pub fn set_tap_feedback(&mut self, index: usize, feedback: f64) {
        if let Some(t) = self.taps.get_mut(index) {
            t.feedback = feedback.clamp(0.0, 0.99);
        }
    }

    /// D4.3: Set per-tap pitch shift in semitones
    pub fn set_tap_pitch(&mut self, index: usize, semitones: f64) {
        if let Some(t) = self.taps.get_mut(index) {
            t.pitch_semitones = semitones.clamp(-12.0, 12.0);
        }
        if let Some(ps) = self.tap_pitch.get_mut(index) {
            ps.set_semitones(semitones);
        }
    }

    /// D4.5: Set per-tap diffusion amount (0-100%)
    pub fn set_tap_diffusion(&mut self, index: usize, amount: f64) {
        if let Some(t) = self.taps.get_mut(index) {
            t.diffusion = amount.clamp(0.0, 1.0);
        }
    }

    /// Set per-tap highpass filter frequency (Hz)
    pub fn set_tap_hp(&mut self, index: usize, freq: f64) {
        if let Some(f) = self.tap_filters.get_mut(index) {
            f.set_hp(freq);
        }
    }

    /// Set per-tap lowpass filter frequency (Hz)
    pub fn set_tap_lp(&mut self, index: usize, freq: f64) {
        if let Some(f) = self.tap_filters.get_mut(index) {
            f.set_lp(freq);
        }
    }

    /// Set tap active/inactive
    pub fn set_tap_active(&mut self, index: usize, active: bool) {
        if let Some(t) = self.taps.get_mut(index) {
            t.active = active;
        }
        self.num_active_taps = self.taps.iter().filter(|t| t.active).count();
    }

    /// Set number of active taps (enables first N taps)
    pub fn set_num_taps(&mut self, n: usize) {
        let n = n.min(MAX_TAPS);
        for (i, t) in self.taps.iter_mut().enumerate() {
            t.active = i < n;
        }
        self.num_active_taps = n;
    }

    pub fn set_feedback(&mut self, feedback: f64) {
        self.feedback = feedback.clamp(0.0, 0.99);
    }

    pub fn set_dry_wet(&mut self, mix: f64) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }

    /// D4.4: Apply a tap pattern preset
    pub fn apply_pattern(&mut self, pattern: TapPattern, num_taps: usize, base_delay_ms: f64) {
        let n = num_taps.min(MAX_TAPS);
        self.set_num_taps(n);

        match pattern {
            TapPattern::Rhythmic => {
                // Standard rhythmic: 1/8, 1/4, dotted 1/4, 1/2, etc.
                let multipliers = [0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0,
                                   1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 3.5, 4.0];
                for i in 0..n {
                    let delay_ms = base_delay_ms * multipliers[i];
                    let level = 1.0 - (i as f64 / n as f64) * 0.6;
                    let pan = if i % 2 == 0 { -0.4 } else { 0.4 };
                    self.set_tap(i, delay_ms, level, pan);
                }
            }
            TapPattern::Cascade => {
                // Cascading: exponentially increasing delays, decreasing levels
                for i in 0..n {
                    let delay_ms = base_delay_ms * (1.5_f64).powi(i as i32);
                    let level = (0.85_f64).powi(i as i32);
                    let pan = (i as f64 / n as f64 * 2.0 - 1.0) * 0.7; // L→R spread
                    self.set_tap(i, delay_ms, level, pan);
                }
            }
            TapPattern::PingPongSpread => {
                // Evenly spaced, alternating hard L/R
                for i in 0..n {
                    let delay_ms = base_delay_ms * (i + 1) as f64 / n as f64;
                    let level = 1.0 - (i as f64 / n as f64) * 0.5;
                    let pan = if i % 2 == 0 { -0.9 } else { 0.9 };
                    self.set_tap(i, delay_ms, level, pan);
                }
            }
            TapPattern::Fibonacci => {
                // Fibonacci sequence ratios
                let mut a: f64 = 1.0;
                let mut b: f64 = 1.0;
                let mut fib_vals = Vec::with_capacity(n);
                for _ in 0..n {
                    fib_vals.push(a);
                    let tmp = a + b;
                    a = b;
                    b = tmp;
                }
                let max_fib = fib_vals.last().copied().unwrap_or(1.0);
                for i in 0..n {
                    let delay_ms = base_delay_ms * fib_vals[i] / max_fib;
                    let level = 1.0 - (i as f64 / n as f64) * 0.7;
                    let pan = ((i as f64 * 2.399) % 2.0 - 1.0) * 0.6; // golden scatter
                    self.set_tap(i, delay_ms, level, pan);
                }
            }
            TapPattern::GoldenRatio => {
                // Golden ratio spacing
                let phi = 1.618_033_988_749_895;
                for i in 0..n {
                    let ratio = ((i + 1) as f64 * phi) % 1.0;
                    let delay_ms = base_delay_ms * (ratio * 0.9 + 0.1); // 10%-100% range
                    let level = 0.9 - (i as f64 / n as f64) * 0.5;
                    let pan = (ratio * 2.0 - 1.0) * 0.8;
                    self.set_tap(i, delay_ms, level, pan);
                }
            }
            TapPattern::Random => {
                // D4.7: Randomized pattern using internal rng
                for i in 0..n {
                    let r1 = self.next_rng_f64();
                    let r2 = self.next_rng_f64();
                    let r3 = self.next_rng_f64();
                    let delay_ms = base_delay_ms * (r1 * 0.9 + 0.1);
                    let level = 0.3 + r2 * 0.7;
                    let pan = r3 * 2.0 - 1.0;
                    self.set_tap(i, delay_ms, level, pan);
                }
            }
        }
    }

    /// D4.7: Randomize current tap pattern with new seed
    pub fn randomize(&mut self, seed: u64) {
        self.rng_state = seed | 1; // ensure non-zero
        let n = self.num_active_taps;
        let base = self.max_delay_ms;
        self.apply_pattern(TapPattern::Random, n, base);
    }

    /// Simple xorshift64 PRNG (no allocation, deterministic)
    #[inline]
    fn next_rng(&mut self) -> u64 {
        let mut x = self.rng_state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.rng_state = x;
        x
    }

    #[inline]
    fn next_rng_f64(&mut self) -> f64 {
        (self.next_rng() & 0x000F_FFFF_FFFF_FFFFu64) as f64 / 0x0010_0000_0000_0000u64 as f64
    }

}

impl Processor for MultiTapDelay {
    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.write_pos = 0;
        for f in &mut self.tap_filters {
            f.reset();
        }
        for ps in &mut self.tap_pitch {
            ps.reset();
        }
        for ap in &mut self.tap_diffusion_ap {
            *ap = [[0.0; 2]; 2];
        }
    }
}

impl StereoProcessor for MultiTapDelay {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        let input = (left + right) * 0.5;

        // Sum per-tap feedback contributions
        let mut fb_sum = 0.0;
        for tap in self.taps.iter() {
            if !tap.active || tap.feedback < 0.001 { continue; }
            let read_pos = (self.write_pos + self.max_delay_samples - tap.delay_samples)
                % self.max_delay_samples;
            fb_sum += self.buffer[read_pos] * tap.feedback;
        }
        // Global feedback from last active tap (legacy compat)
        if self.feedback > 0.001 {
            let last_delay = self.taps.iter().rev()
                .find(|t| t.active)
                .map(|t| t.delay_samples)
                .unwrap_or(0);
            let last_pos = (self.write_pos + self.max_delay_samples - last_delay)
                % self.max_delay_samples;
            fb_sum += self.buffer[last_pos] * self.feedback;
        }

        // Write to buffer
        self.buffer[self.write_pos] = input + fb_sum.clamp(-4.0, 4.0);
        self.write_pos = (self.write_pos + 1) % self.max_delay_samples;

        // Read all active taps and sum
        let mut wet_l = 0.0;
        let mut wet_r = 0.0;

        for i in 0..MAX_TAPS {
            // Copy tap config to locals to avoid borrow conflicts
            let active = self.taps[i].active;
            if !active { continue; }
            let delay_samples = self.taps[i].delay_samples;
            let level = self.taps[i].level;
            let pan = self.taps[i].pan;
            let diffusion_amt = self.taps[i].diffusion;

            let read_pos = (self.write_pos + self.max_delay_samples - delay_samples)
                % self.max_delay_samples;
            let raw = self.buffer[read_pos];

            // Per-tap filter
            let filtered = self.tap_filters[i].process(raw);

            // D4.3: Per-tap pitch shift
            let pitched = self.tap_pitch[i].process(filtered);

            // D4.5: Per-tap diffusion (inline to avoid &mut self borrow)
            let diffused = if diffusion_amt < 0.001 {
                pitched
            } else {
                let coeff = diffusion_amt * 0.7;
                let mut x = pitched;
                // Stage 0
                let y0 = -coeff * x + self.tap_diffusion_ap[i][0][0];
                self.tap_diffusion_ap[i][0][0] = x + coeff * y0;
                x = y0;
                // Stage 1
                let y1 = -coeff * x + self.tap_diffusion_ap[i][1][0];
                self.tap_diffusion_ap[i][1][0] = x + coeff * y1;
                x = y1;
                pitched + (x - pitched) * diffusion_amt
            };

            let delayed = diffused * level;

            // Pan law (constant power)
            let pan_angle = (pan + 1.0) * 0.5 * PI * 0.5;
            wet_l += delayed * pan_angle.cos();
            wet_r += delayed * pan_angle.sin();
        }

        // Mix
        let out_l = left * (1.0 - self.dry_wet) + wet_l * self.dry_wet;
        let out_r = right * (1.0 - self.dry_wet) + wet_r * self.dry_wet;

        (out_l, out_r)
    }
}

impl ProcessorConfig for MultiTapDelay {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        let ratio = sample_rate / self.sample_rate;
        self.sample_rate = sample_rate;
        self.max_delay_samples = (self.max_delay_samples as f64 * ratio) as usize;
        self.buffer = vec![0.0; self.max_delay_samples];

        for tap in &mut self.taps {
            tap.delay_samples = (tap.delay_samples as f64 * ratio) as usize;
        }

        for f in &mut self.tap_filters {
            f.hp.set_sample_rate(sample_rate);
            f.lp.set_sample_rate(sample_rate);
            f.set_hp(f.hp_freq);
            f.set_lp(f.lp_freq);
        }

        for ps in &mut self.tap_pitch {
            // Re-create pitch shifter with new sample rate
            *ps = PitchShifter::new(sample_rate);
        }
    }
}

/// Modulated delay (for chorus/flanger effects)
#[derive(Debug, Clone)]
pub struct ModulatedDelay {
    buffer_l: Vec<Sample>,
    buffer_r: Vec<Sample>,
    write_pos: usize,
    max_delay_samples: usize,

    // Base delay
    base_delay_samples: f64,

    // Modulation
    mod_depth: f64, // In samples
    mod_rate: f64,  // Hz
    mod_phase: f64,
    mod_stereo_offset: f64, // Phase offset between L/R

    feedback: f64,
    dry_wet: f64,

    sample_rate: f64,
}

impl ModulatedDelay {
    pub fn new(sample_rate: f64) -> Self {
        let max_delay_samples = (50.0 * 0.001 * sample_rate) as usize; // 50ms max

        Self {
            buffer_l: vec![0.0; max_delay_samples],
            buffer_r: vec![0.0; max_delay_samples],
            write_pos: 0,
            max_delay_samples,
            base_delay_samples: 10.0 * 0.001 * sample_rate, // 10ms default
            mod_depth: 2.0 * 0.001 * sample_rate,           // 2ms
            mod_rate: 0.5,                                  // 0.5 Hz
            mod_phase: 0.0,
            mod_stereo_offset: PI * 0.5, // 90 degree offset
            feedback: 0.0,
            dry_wet: 0.5,
            sample_rate,
        }
    }

    /// Create chorus preset
    pub fn chorus(sample_rate: f64) -> Self {
        let mut delay = Self::new(sample_rate);
        delay.set_delay_ms(20.0);
        delay.set_mod_depth_ms(3.0);
        delay.set_mod_rate(0.8);
        delay.set_feedback(0.0);
        delay.set_dry_wet(0.5);
        delay
    }

    /// Create flanger preset
    pub fn flanger(sample_rate: f64) -> Self {
        let mut delay = Self::new(sample_rate);
        delay.set_delay_ms(2.0);
        delay.set_mod_depth_ms(1.5);
        delay.set_mod_rate(0.3);
        delay.set_feedback(0.7);
        delay.set_dry_wet(0.5);
        delay
    }

    pub fn set_delay_ms(&mut self, ms: f64) {
        self.base_delay_samples = ms * 0.001 * self.sample_rate;
    }

    pub fn set_mod_depth_ms(&mut self, ms: f64) {
        self.mod_depth = ms * 0.001 * self.sample_rate;
    }

    pub fn set_mod_rate(&mut self, hz: f64) {
        self.mod_rate = hz.clamp(0.01, 20.0);
    }

    pub fn set_feedback(&mut self, feedback: f64) {
        self.feedback = feedback.clamp(-0.99, 0.99);
    }

    pub fn set_dry_wet(&mut self, mix: f64) {
        self.dry_wet = mix.clamp(0.0, 1.0);
    }

    /// Interpolated read from buffer
    fn read_interpolated(buffer: &[Sample], pos: f64, max_samples: usize) -> Sample {
        let pos = pos.rem_euclid(max_samples as f64);
        let index = pos as usize;
        let frac = pos - index as f64;

        let s0 = buffer[index % max_samples];
        let s1 = buffer[(index + 1) % max_samples];

        // Linear interpolation
        s0 + (s1 - s0) * frac
    }
}

impl Processor for ModulatedDelay {
    fn reset(&mut self) {
        self.buffer_l.fill(0.0);
        self.buffer_r.fill(0.0);
        self.write_pos = 0;
        self.mod_phase = 0.0;
    }
}

impl StereoProcessor for ModulatedDelay {
    fn process_sample(&mut self, left: Sample, right: Sample) -> (Sample, Sample) {
        // Calculate modulated delay times
        let mod_l = (self.mod_phase).sin();
        let mod_r = (self.mod_phase + self.mod_stereo_offset).sin();

        let delay_l = self.base_delay_samples + self.mod_depth * mod_l;
        let delay_r = self.base_delay_samples + self.mod_depth * mod_r;

        // Read with interpolation
        let read_pos_l = self.write_pos as f64 + self.max_delay_samples as f64 - delay_l;
        let read_pos_r = self.write_pos as f64 + self.max_delay_samples as f64 - delay_r;

        let delayed_l = Self::read_interpolated(&self.buffer_l, read_pos_l, self.max_delay_samples);
        let delayed_r = Self::read_interpolated(&self.buffer_r, read_pos_r, self.max_delay_samples);

        // Write with feedback
        self.buffer_l[self.write_pos] = left + delayed_l * self.feedback;
        self.buffer_r[self.write_pos] = right + delayed_r * self.feedback;
        self.write_pos = (self.write_pos + 1) % self.max_delay_samples;

        // Advance modulation phase
        self.mod_phase += 2.0 * PI * self.mod_rate / self.sample_rate;
        if self.mod_phase > 2.0 * PI {
            self.mod_phase -= 2.0 * PI;
        }

        // Mix
        let out_l = left * (1.0 - self.dry_wet) + delayed_l * self.dry_wet;
        let out_r = right * (1.0 - self.dry_wet) + delayed_r * self.dry_wet;

        (out_l, out_r)
    }
}

impl ProcessorConfig for ModulatedDelay {
    fn set_sample_rate(&mut self, sample_rate: f64) {
        let ratio = sample_rate / self.sample_rate;
        self.sample_rate = sample_rate;
        self.max_delay_samples = (self.max_delay_samples as f64 * ratio) as usize;
        self.base_delay_samples *= ratio;
        self.mod_depth *= ratio;
        self.buffer_l = vec![0.0; self.max_delay_samples];
        self.buffer_r = vec![0.0; self.max_delay_samples];
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_delay() {
        let mut delay = Delay::new(48000.0, 1000.0);
        delay.set_delay_ms(100.0);
        delay.set_feedback(0.5);
        delay.set_dry_wet(0.5);

        // Send impulse
        let _ = delay.process_sample(1.0);

        // Wait for delay time
        for _ in 0..4799 {
            let _ = delay.process_sample(0.0);
        }

        // Should get delayed signal
        let out = delay.process_sample(0.0);
        assert!(out.abs() > 0.4);
    }

    #[test]
    fn test_ping_pong() {
        let mut delay = PingPongDelay::new(48000.0, 1000.0);
        delay.set_ping_pong(1.0);

        // Process some samples
        for _ in 0..1000 {
            let _ = delay.process_sample(0.5, 0.5);
        }
    }

    #[test]
    fn test_modulated_delay() {
        let mut chorus = ModulatedDelay::chorus(48000.0);

        // Process and verify modulation is working
        let mut outputs = Vec::new();
        for i in 0..1000 {
            let input = if i == 0 { 1.0 } else { 0.0 };
            let (l, r) = chorus.process_sample(input, input);
            outputs.push((l, r));
        }

        // L and R should differ due to stereo modulation
        let mut any_different = false;
        for (l, r) in &outputs {
            if (l - r).abs() > 0.001 {
                any_different = true;
                break;
            }
        }
        assert!(any_different);
    }
}
