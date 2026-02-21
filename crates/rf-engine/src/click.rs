//! Click Track / Metronome System
//!
//! Professional metronome like Cubase/Pro Tools:
//! - Customizable click sounds
//! - Accent on downbeat
//! - Pre-count/count-in
//! - Pattern-based clicks (subdivision)
//! - MIDI output option
//! - Volume control
//!
//! ## Click Patterns
//! - Standard: accent + normal beats
//! - Subdivided: 8ths, 16ths, triplets
//! - Custom: user-defined patterns

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use rf_core::Sample;

// ═══════════════════════════════════════════════════════════════════════════════
// CLICK SOUNDS
// ═══════════════════════════════════════════════════════════════════════════════

/// Click sound type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClickSoundType {
    /// Downbeat accent
    Accent,
    /// Normal beat
    Beat,
    /// Subdivision click
    Subdivision,
}

/// Click sound sample
#[derive(Debug, Clone)]
pub struct ClickSound {
    /// Audio samples (mono)
    pub samples: Vec<f32>,
    /// Sample rate
    pub sample_rate: u32,
    /// Gain (linear)
    pub gain: f32,
}

impl ClickSound {
    /// Generate default click sound (short sine burst)
    pub fn default_accent(sample_rate: u32) -> Self {
        Self::generate_click(sample_rate, 1000.0, 0.015, 0.8)
    }

    pub fn default_beat(sample_rate: u32) -> Self {
        Self::generate_click(sample_rate, 800.0, 0.012, 0.5)
    }

    pub fn default_subdivision(sample_rate: u32) -> Self {
        Self::generate_click(sample_rate, 600.0, 0.008, 0.3)
    }

    /// Generate click sound
    fn generate_click(sample_rate: u32, freq: f32, duration: f32, gain: f32) -> Self {
        let num_samples = (sample_rate as f32 * duration) as usize;
        let mut samples = Vec::with_capacity(num_samples);

        for i in 0..num_samples {
            let t = i as f32 / sample_rate as f32;
            // Sine wave with exponential decay
            let envelope = (-t * 40.0).exp();
            let sample = (t * freq * std::f32::consts::TAU).sin() * envelope * gain;
            samples.push(sample);
        }

        Self {
            samples,
            sample_rate,
            gain: 1.0,
        }
    }

    /// Load from audio file (placeholder)
    pub fn from_file(_path: &str, sample_rate: u32) -> Self {
        // In real implementation, load and resample audio file
        Self::default_accent(sample_rate)
    }

    /// Generate a noise-based click (for rimshot, sticks, hi-hat presets)
    fn generate_noise_click(sample_rate: u32, duration: f32, gain: f32, hp_cutoff: f32) -> Self {
        let num_samples = (sample_rate as f32 * duration) as usize;
        let mut samples = Vec::with_capacity(num_samples);

        // Simple LCG pseudo-random for deterministic noise (no allocations)
        let mut rng_state: u32 = 0xDEAD_BEEF;

        // One-pole HP filter state
        let rc = 1.0 / (hp_cutoff * std::f32::consts::TAU);
        let dt = 1.0 / sample_rate as f32;
        let alpha = rc / (rc + dt);
        let mut prev_input = 0.0f32;
        let mut prev_output = 0.0f32;

        for i in 0..num_samples {
            let t = i as f32 / sample_rate as f32;
            let envelope = (-t * 60.0).exp(); // Sharp decay

            // LCG noise [-1, 1]
            rng_state = rng_state.wrapping_mul(1103515245).wrapping_add(12345);
            let noise = (rng_state as f32 / u32::MAX as f32) * 2.0 - 1.0;

            // HP filter
            let filtered = alpha * (prev_output + noise - prev_input);
            prev_input = noise;
            prev_output = filtered;

            samples.push(filtered * envelope * gain);
        }

        Self {
            samples,
            sample_rate,
            gain: 1.0,
        }
    }

    /// Generate a square wave click (for beep preset)
    fn generate_square_click(sample_rate: u32, freq: f32, duration: f32, gain: f32) -> Self {
        let num_samples = (sample_rate as f32 * duration) as usize;
        let mut samples = Vec::with_capacity(num_samples);

        for i in 0..num_samples {
            let t = i as f32 / sample_rate as f32;
            let envelope = (-t * 50.0).exp();
            let phase = (t * freq * std::f32::consts::TAU).sin();
            let square = if phase >= 0.0 { 1.0 } else { -1.0 };
            samples.push(square * envelope * gain * 0.5); // -6dB to avoid harshness
        }

        Self {
            samples,
            sample_rate,
            gain: 1.0,
        }
    }

    /// Generate a combined sine + noise transient click (for woodblock, clave, sidestick)
    fn generate_transient_click(
        sample_rate: u32,
        freq: f32,
        duration: f32,
        gain: f32,
        noise_amount: f32,
        noise_decay: f32,
    ) -> Self {
        let num_samples = (sample_rate as f32 * duration) as usize;
        let mut samples = Vec::with_capacity(num_samples);

        let mut rng_state: u32 = 0xCAFE_BABE;

        for i in 0..num_samples {
            let t = i as f32 / sample_rate as f32;
            let sine_env = (-t * 40.0).exp();
            let noise_env = (-t * noise_decay).exp();

            let sine = (t * freq * std::f32::consts::TAU).sin() * sine_env;

            rng_state = rng_state.wrapping_mul(1103515245).wrapping_add(12345);
            let noise = (rng_state as f32 / u32::MAX as f32) * 2.0 - 1.0;

            let mixed = sine * (1.0 - noise_amount) + noise * noise_env * noise_amount;
            samples.push(mixed * gain);
        }

        Self {
            samples,
            sample_rate,
            gain: 1.0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLICK PRESETS (Pro Tools Click II-style)
// ═══════════════════════════════════════════════════════════════════════════════

/// Click sound preset (12 built-in presets like Pro Tools Click II)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum ClickPreset {
    /// Pure sine with exponential decay (default — clean studio click)
    #[default]
    Sine = 0,
    /// Sharp high-frequency hit (2200/1800 Hz)
    Woodblock = 1,
    /// White noise burst + sine body
    Rimshot = 2,
    /// Lower frequency, longer sustain (560/420 Hz)
    Cowbell = 3,
    /// Soft round tone (900/700 Hz)
    Marimba = 4,
    /// Filtered noise burst (percussive)
    Sticks = 5,
    /// Very short high-pitched click (2500/2000 Hz)
    Clave = 6,
    /// Square wave pulse
    Beep = 7,
    /// Ultra-short tick (5ms)
    Click = 8,
    /// Filtered noise + body resonance
    SideStick = 9,
    /// Noise + HP filter (bright)
    HiHat = 10,
    /// Traditional analog metronome (warm sine)
    Metronome = 11,
}

impl ClickPreset {
    /// Total number of presets
    pub const COUNT: u8 = 12;

    /// Get preset name
    pub fn name(&self) -> &'static str {
        match self {
            ClickPreset::Sine => "Sine",
            ClickPreset::Woodblock => "Woodblock",
            ClickPreset::Rimshot => "Rimshot",
            ClickPreset::Cowbell => "Cowbell",
            ClickPreset::Marimba => "Marimba",
            ClickPreset::Sticks => "Sticks",
            ClickPreset::Clave => "Clave",
            ClickPreset::Beep => "Beep",
            ClickPreset::Click => "Click",
            ClickPreset::SideStick => "SideStick",
            ClickPreset::HiHat => "HiHat",
            ClickPreset::Metronome => "Metronome",
        }
    }

    /// Convert from u8
    pub fn from_u8(v: u8) -> Self {
        match v {
            0 => ClickPreset::Sine,
            1 => ClickPreset::Woodblock,
            2 => ClickPreset::Rimshot,
            3 => ClickPreset::Cowbell,
            4 => ClickPreset::Marimba,
            5 => ClickPreset::Sticks,
            6 => ClickPreset::Clave,
            7 => ClickPreset::Beep,
            8 => ClickPreset::Click,
            9 => ClickPreset::SideStick,
            10 => ClickPreset::HiHat,
            11 => ClickPreset::Metronome,
            _ => ClickPreset::Sine,
        }
    }

    /// Generate accent, beat, and subdivision sounds for this preset.
    /// All synthesis is pre-computed (safe to call from any thread).
    pub fn generate(&self, sample_rate: u32) -> (ClickSound, ClickSound, ClickSound) {
        match self {
            ClickPreset::Sine => (
                ClickSound::generate_click(sample_rate, 1000.0, 0.015, 0.8),
                ClickSound::generate_click(sample_rate, 800.0, 0.012, 0.5),
                ClickSound::generate_click(sample_rate, 600.0, 0.008, 0.3),
            ),
            ClickPreset::Woodblock => (
                ClickSound::generate_transient_click(sample_rate, 2200.0, 0.012, 0.85, 0.3, 120.0),
                ClickSound::generate_transient_click(sample_rate, 1800.0, 0.010, 0.55, 0.25, 120.0),
                ClickSound::generate_transient_click(sample_rate, 1500.0, 0.008, 0.35, 0.2, 120.0),
            ),
            ClickPreset::Rimshot => (
                ClickSound::generate_transient_click(sample_rate, 900.0, 0.020, 0.85, 0.6, 80.0),
                ClickSound::generate_transient_click(sample_rate, 700.0, 0.015, 0.55, 0.5, 80.0),
                ClickSound::generate_transient_click(sample_rate, 500.0, 0.010, 0.35, 0.4, 80.0),
            ),
            ClickPreset::Cowbell => (
                ClickSound::generate_click(sample_rate, 560.0, 0.040, 0.8),
                ClickSound::generate_click(sample_rate, 420.0, 0.030, 0.5),
                ClickSound::generate_click(sample_rate, 350.0, 0.020, 0.3),
            ),
            ClickPreset::Marimba => (
                ClickSound::generate_click(sample_rate, 900.0, 0.025, 0.75),
                ClickSound::generate_click(sample_rate, 700.0, 0.020, 0.48),
                ClickSound::generate_click(sample_rate, 550.0, 0.015, 0.28),
            ),
            ClickPreset::Sticks => (
                ClickSound::generate_noise_click(sample_rate, 0.008, 0.85, 3000.0),
                ClickSound::generate_noise_click(sample_rate, 0.006, 0.55, 2500.0),
                ClickSound::generate_noise_click(sample_rate, 0.004, 0.35, 2000.0),
            ),
            ClickPreset::Clave => (
                ClickSound::generate_transient_click(sample_rate, 2500.0, 0.008, 0.85, 0.15, 150.0),
                ClickSound::generate_transient_click(sample_rate, 2000.0, 0.006, 0.55, 0.1, 150.0),
                ClickSound::generate_transient_click(sample_rate, 1600.0, 0.005, 0.35, 0.08, 150.0),
            ),
            ClickPreset::Beep => (
                ClickSound::generate_square_click(sample_rate, 1200.0, 0.012, 0.75),
                ClickSound::generate_square_click(sample_rate, 900.0, 0.010, 0.48),
                ClickSound::generate_square_click(sample_rate, 700.0, 0.008, 0.3),
            ),
            ClickPreset::Click => (
                ClickSound::generate_click(sample_rate, 4000.0, 0.005, 0.9),
                ClickSound::generate_click(sample_rate, 3200.0, 0.004, 0.6),
                ClickSound::generate_click(sample_rate, 2500.0, 0.003, 0.35),
            ),
            ClickPreset::SideStick => (
                ClickSound::generate_transient_click(sample_rate, 1200.0, 0.018, 0.85, 0.45, 90.0),
                ClickSound::generate_transient_click(sample_rate, 950.0, 0.014, 0.55, 0.35, 90.0),
                ClickSound::generate_transient_click(sample_rate, 750.0, 0.010, 0.35, 0.25, 90.0),
            ),
            ClickPreset::HiHat => (
                ClickSound::generate_noise_click(sample_rate, 0.025, 0.8, 6000.0),
                ClickSound::generate_noise_click(sample_rate, 0.015, 0.5, 5000.0),
                ClickSound::generate_noise_click(sample_rate, 0.010, 0.3, 4000.0),
            ),
            ClickPreset::Metronome => (
                ClickSound::generate_click(sample_rate, 600.0, 0.030, 0.85),
                ClickSound::generate_click(sample_rate, 480.0, 0.025, 0.55),
                ClickSound::generate_click(sample_rate, 400.0, 0.018, 0.3),
            ),
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLICK PATTERN
// ═══════════════════════════════════════════════════════════════════════════════

/// Click subdivision pattern
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ClickPattern {
    /// Just quarter notes
    #[default]
    Quarter,
    /// Eighth notes
    Eighth,
    /// Sixteenth notes
    Sixteenth,
    /// Triplets
    Triplet,
    /// Only downbeat
    DownbeatOnly,
}

impl ClickPattern {
    /// Clicks per beat
    pub fn clicks_per_beat(&self) -> u32 {
        match self {
            ClickPattern::Quarter => 1,
            ClickPattern::Eighth => 2,
            ClickPattern::Sixteenth => 4,
            ClickPattern::Triplet => 3,
            ClickPattern::DownbeatOnly => 0, // Special case
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COUNT IN
// ═══════════════════════════════════════════════════════════════════════════════

/// Count-in mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CountInMode {
    /// No count-in
    #[default]
    Off,
    /// 1 bar count-in
    OneBar,
    /// 2 bar count-in
    TwoBars,
    /// 4 beats count-in
    FourBeats,
}

impl CountInMode {
    /// Number of beats for count-in
    pub fn beats(&self, beats_per_bar: u8) -> u32 {
        match self {
            CountInMode::Off => 0,
            CountInMode::OneBar => beats_per_bar as u32,
            CountInMode::TwoBars => beats_per_bar as u32 * 2,
            CountInMode::FourBeats => 4,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLICK TRACK
// ═══════════════════════════════════════════════════════════════════════════════

/// Audibility mode — when should the click be heard?
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum AudibilityMode {
    /// Click during both playback and recording
    #[default]
    Always = 0,
    /// Click only during recording
    RecordOnly = 1,
    /// Click only during count-in, silent during playback/recording
    CountInOnly = 2,
}

impl AudibilityMode {
    pub fn from_u8(v: u8) -> Self {
        match v {
            1 => AudibilityMode::RecordOnly,
            2 => AudibilityMode::CountInOnly,
            _ => AudibilityMode::Always,
        }
    }
}

/// Metronome/Click track generator
#[allow(dead_code)]
pub struct ClickTrack {
    /// Enabled
    enabled: AtomicBool,
    /// Accent sound
    accent_sound: ClickSound,
    /// Beat sound
    beat_sound: ClickSound,
    /// Subdivision sound
    subdivision_sound: ClickSound,
    /// Master volume (linear)
    volume: f32,
    /// Per-sound volumes (Pro Tools Click II style)
    accent_volume: f32,
    beat_volume: f32,
    subdivision_volume: f32,
    /// Current preset
    preset: ClickPreset,
    /// Click pattern
    pattern: ClickPattern,
    /// Count-in mode
    count_in: CountInMode,
    /// Audibility mode (Always / RecordOnly / CountInOnly)
    audibility_mode: u8, // stored as u8 for lock-free atomicity
    /// Current playback position in click sound
    playback_pos: usize,
    /// Current sound being played
    current_sound: Option<ClickSoundType>,
    /// Sample rate
    sample_rate: u32,
    /// PPQ (pulses per quarter note)
    ppq: u32,
    /// Only during recording (legacy — superseded by audibility_mode, kept for FFI compat)
    only_during_record: AtomicBool,
    /// Pan position (-1.0 to 1.0)
    pan: f32,
    /// Tempo in BPM (atomic — set from UI, read from audio thread)
    tempo_bpm: AtomicU64,
    /// Beats per bar (time signature numerator)
    beats_per_bar: u8,
    /// Last tick that triggered a click (prevents double-triggers within same beat)
    last_trigger_tick: u64,

    // ── Count-in state ──
    /// Count-in is currently active
    count_in_active: AtomicBool,
    /// Total count-in beats to play
    count_in_total_beats: u32,
    /// Count-in beats played so far
    count_in_beats_played: u32,
    /// Sample position within count-in (independent from transport)
    count_in_sample_pos: u64,
    /// Last tick that triggered during count-in
    count_in_last_tick: u64,

    // ── Tap tempo state ──
    /// Last 8 tap timestamps (milliseconds since epoch)
    tap_times: [u64; 8],
    /// Number of valid taps in buffer
    tap_count: usize,
}

impl ClickTrack {
    pub fn new(sample_rate: u32) -> Self {
        Self {
            enabled: AtomicBool::new(false),
            accent_sound: ClickSound::default_accent(sample_rate),
            beat_sound: ClickSound::default_beat(sample_rate),
            subdivision_sound: ClickSound::default_subdivision(sample_rate),
            volume: 0.7,
            accent_volume: 1.0,
            beat_volume: 0.7,
            subdivision_volume: 0.4,
            preset: ClickPreset::Sine,
            pattern: ClickPattern::Quarter,
            count_in: CountInMode::Off,
            audibility_mode: 0, // Always
            playback_pos: 0,
            current_sound: None,
            sample_rate,
            ppq: 960,
            only_during_record: AtomicBool::new(false),
            pan: 0.0,
            tempo_bpm: AtomicU64::new(120.0_f64.to_bits()),
            beats_per_bar: 4,
            last_trigger_tick: u64::MAX,
            // Count-in
            count_in_active: AtomicBool::new(false),
            count_in_total_beats: 0,
            count_in_beats_played: 0,
            count_in_sample_pos: 0,
            count_in_last_tick: u64::MAX,
            // Tap tempo
            tap_times: [0; 8],
            tap_count: 0,
        }
    }

    /// Enable/disable click
    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    /// Set volume (0.0 - 1.0)
    pub fn set_volume(&mut self, volume: f32) {
        self.volume = volume.clamp(0.0, 1.0);
    }

    /// Set click pattern
    pub fn set_pattern(&mut self, pattern: ClickPattern) {
        self.pattern = pattern;
    }

    /// Set count-in mode
    pub fn set_count_in(&mut self, mode: CountInMode) {
        self.count_in = mode;
    }

    /// Set pan (-1.0 left, 0.0 center, 1.0 right)
    pub fn set_pan(&mut self, pan: f32) {
        self.pan = pan.clamp(-1.0, 1.0);
    }

    /// Get current volume
    pub fn get_volume(&self) -> f32 {
        self.volume
    }

    /// Get current pattern as integer (0=Quarter, 1=Eighth, 2=Sixteenth, 3=Triplet, 4=DownbeatOnly)
    pub fn get_pattern(&self) -> u8 {
        match self.pattern {
            ClickPattern::Quarter => 0,
            ClickPattern::Eighth => 1,
            ClickPattern::Sixteenth => 2,
            ClickPattern::Triplet => 3,
            ClickPattern::DownbeatOnly => 4,
        }
    }

    /// Get current count-in mode as integer (0=Off, 1=OneBar, 2=TwoBars, 3=FourBeats)
    pub fn get_count_in(&self) -> u8 {
        match self.count_in {
            CountInMode::Off => 0,
            CountInMode::OneBar => 1,
            CountInMode::TwoBars => 2,
            CountInMode::FourBeats => 3,
        }
    }

    /// Get current pan position
    pub fn get_pan(&self) -> f32 {
        self.pan
    }

    /// Set tempo (BPM) — thread-safe, called from UI
    pub fn set_tempo(&self, bpm: f64) {
        self.tempo_bpm.store(bpm.clamp(20.0, 999.0).to_bits(), Ordering::Relaxed);
    }

    /// Get tempo (BPM)
    pub fn get_tempo(&self) -> f64 {
        f64::from_bits(self.tempo_bpm.load(Ordering::Relaxed))
    }

    /// Set beats per bar (time signature numerator)
    pub fn set_beats_per_bar(&mut self, beats: u8) {
        self.beats_per_bar = beats.clamp(1, 16);
    }

    /// Get beats per bar
    pub fn get_beats_per_bar(&self) -> u8 {
        self.beats_per_bar
    }

    /// Set only-during-record mode (thread-safe)
    pub fn set_only_during_record(&self, enabled: bool) {
        self.only_during_record.store(enabled, Ordering::Relaxed);
    }

    /// Get only-during-record mode
    pub fn get_only_during_record(&self) -> bool {
        self.only_during_record.load(Ordering::Relaxed)
    }

    // ── Per-Sound Volumes ──

    pub fn set_accent_volume(&mut self, v: f32) {
        self.accent_volume = v.clamp(0.0, 1.0);
    }
    pub fn get_accent_volume(&self) -> f32 {
        self.accent_volume
    }
    pub fn set_beat_volume(&mut self, v: f32) {
        self.beat_volume = v.clamp(0.0, 1.0);
    }
    pub fn get_beat_volume(&self) -> f32 {
        self.beat_volume
    }
    pub fn set_subdivision_volume(&mut self, v: f32) {
        self.subdivision_volume = v.clamp(0.0, 1.0);
    }
    pub fn get_subdivision_volume(&self) -> f32 {
        self.subdivision_volume
    }

    // ── Preset ──

    pub fn set_preset(&mut self, preset_id: u8) {
        let preset = ClickPreset::from_u8(preset_id);
        self.preset = preset;
        let (accent, beat, sub) = preset.generate(self.sample_rate);
        self.accent_sound = accent;
        self.beat_sound = beat;
        self.subdivision_sound = sub;
    }
    pub fn get_preset(&self) -> u8 {
        self.preset as u8
    }

    // ── Audibility Mode ──

    pub fn set_audibility_mode(&mut self, mode: u8) {
        self.audibility_mode = mode.min(2);
        // Sync legacy field for backward compat
        self.only_during_record.store(mode == 1, Ordering::Relaxed);
    }
    pub fn get_audibility_mode(&self) -> u8 {
        self.audibility_mode
    }

    // ── Count-In ──

    /// Start a count-in sequence (called from FFI before transport starts)
    pub fn start_count_in(&mut self) {
        let total = self.count_in.beats(self.beats_per_bar);
        if total == 0 {
            return; // Count-in is Off
        }
        self.count_in_total_beats = total;
        self.count_in_beats_played = 0;
        self.count_in_sample_pos = 0;
        self.count_in_last_tick = u64::MAX;
        self.count_in_active.store(true, Ordering::Release);
    }

    /// Check if count-in is currently active
    pub fn is_count_in_active(&self) -> bool {
        self.count_in_active.load(Ordering::Acquire)
    }

    /// Get current count-in beat number (0-based, -1 if inactive)
    pub fn get_count_in_beat(&self) -> i32 {
        if !self.is_count_in_active() {
            return -1;
        }
        self.count_in_beats_played as i32
    }

    /// Process count-in audio (independent sample position, no transport advance).
    /// Returns true when count-in is complete.
    fn process_count_in_block(
        &mut self,
        output_l: &mut [Sample],
        output_r: &mut [Sample],
        frames: usize,
    ) -> bool {
        let tempo = self.get_tempo();
        if tempo <= 0.0 {
            return false;
        }

        let sample_rate = self.sample_rate as f64;
        let ppq = self.ppq as f64;
        let samples_per_tick = (sample_rate * 60.0) / (tempo * ppq);
        let ticks_per_beat = self.ppq as u64;

        for frame in 0..frames {
            let sample_pos = self.count_in_sample_pos;
            let tick = (sample_pos as f64 / samples_per_tick) as u64;

            if tick != self.count_in_last_tick && tick.is_multiple_of(ticks_per_beat) {
                // A new beat in count-in
                let beat_in_bar = (self.count_in_beats_played % self.beats_per_bar as u32) as u8;
                let is_downbeat = beat_in_bar == 0;
                self.trigger(beat_in_bar, is_downbeat, false);
                self.count_in_last_tick = tick;
                self.count_in_beats_played += 1;

                if self.count_in_beats_played >= self.count_in_total_beats {
                    // Count-in complete — render remaining sound then signal done
                    self.render_sample(output_l, output_r, frame);
                    self.count_in_sample_pos += 1;
                    // Render rest of block
                    for f2 in (frame + 1)..frames {
                        self.render_sample(output_l, output_r, f2);
                        self.count_in_sample_pos += 1;
                    }
                    self.count_in_active.store(false, Ordering::Release);
                    return true;
                }
            }

            self.render_sample(output_l, output_r, frame);
            self.count_in_sample_pos += 1;
        }

        false
    }

    /// Render one sample of the current click sound at frame index
    fn render_sample(&mut self, output_l: &mut [Sample], output_r: &mut [Sample], frame: usize) {
        if let Some(ref sound_type) = self.current_sound {
            let (sound, per_vol) = match sound_type {
                ClickSoundType::Accent => (&self.accent_sound, self.accent_volume),
                ClickSoundType::Beat => (&self.beat_sound, self.beat_volume),
                ClickSoundType::Subdivision => (&self.subdivision_sound, self.subdivision_volume),
            };

            if self.playback_pos < sound.samples.len() {
                let s = sound.samples[self.playback_pos] as f64
                    * sound.gain as f64
                    * self.volume as f64
                    * per_vol as f64;

                let left_gain = if self.pan <= 0.0 { 1.0 } else { 1.0 - self.pan as f64 };
                let right_gain = if self.pan >= 0.0 { 1.0 } else { 1.0 + self.pan as f64 };

                output_l[frame] += s * left_gain;
                output_r[frame] += s * right_gain;
                self.playback_pos += 1;
            } else {
                self.current_sound = None;
            }
        }
    }

    // ── Tap Tempo ──

    /// Record a tap and return the calculated BPM (or current BPM if not enough taps)
    pub fn tap_tempo(&mut self) -> f64 {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;

        // Reset if gap > 2 seconds since last tap
        if self.tap_count > 0 {
            let last = self.tap_times[(self.tap_count - 1) % 8];
            if now.saturating_sub(last) > 2000 {
                self.tap_count = 0;
            }
        }

        self.tap_times[self.tap_count % 8] = now;
        self.tap_count += 1;

        // Need at least 2 taps to calculate
        if self.tap_count < 2 {
            return self.get_tempo();
        }

        // Average intervals from last N taps (max 8)
        let usable = self.tap_count.min(8);
        let start_idx = if self.tap_count > 8 {
            self.tap_count - 8
        } else {
            0
        };

        let mut total_interval = 0u64;
        let mut count = 0u64;
        for i in (start_idx + 1)..self.tap_count {
            let prev = self.tap_times[(i - 1) % 8];
            let curr = self.tap_times[i % 8];
            let interval = curr.saturating_sub(prev);
            if interval > 0 && interval < 2000 {
                total_interval += interval;
                count += 1;
            }
        }

        if count == 0 {
            return self.get_tempo();
        }

        let avg_ms = total_interval as f64 / count as f64;
        let bpm = (60000.0 / avg_ms).clamp(20.0, 999.0);
        self.set_tempo(bpm);
        bpm
    }

    /// Process an entire audio block — converts sample position to ticks,
    /// detects click positions, triggers, and renders audio.
    /// Called from the audio callback with the current transport sample position.
    ///
    /// This is the MAIN entry point for the metronome in the audio thread.
    /// It handles sample-accurate click triggering by scanning each sample
    /// in the block for tick boundaries.
    ///
    /// Returns true if a count-in just completed (signal to transport to start).
    pub fn process_block(
        &mut self,
        output_l: &mut [Sample],
        output_r: &mut [Sample],
        start_sample: u64,
        frames: usize,
        is_recording: bool,
    ) -> bool {
        if !self.is_enabled() {
            return false;
        }

        // Handle count-in phase (independent from transport)
        if self.is_count_in_active() {
            return self.process_count_in_block(output_l, output_r, frames);
        }

        // Audibility mode check
        let mode = AudibilityMode::from_u8(self.audibility_mode);
        match mode {
            AudibilityMode::Always => {} // Always play
            AudibilityMode::RecordOnly => {
                if !is_recording {
                    return false;
                }
            }
            AudibilityMode::CountInOnly => {
                // Only play during count-in (handled above), silent during transport
                return false;
            }
        }

        let tempo = self.get_tempo();
        if tempo <= 0.0 {
            return false;
        }

        let sample_rate = self.sample_rate as f64;
        let ppq = self.ppq as f64;
        let beats_per_bar = self.beats_per_bar;

        // samples_per_tick = (sample_rate * 60.0) / (tempo * ppq)
        let samples_per_tick = (sample_rate * 60.0) / (tempo * ppq);

        // Scan through the block sample-by-sample for tick boundaries
        for frame in 0..frames {
            let sample_pos = start_sample + frame as u64;
            // Convert sample position to tick (integer)
            let tick = (sample_pos as f64 / samples_per_tick) as u64;

            // Only trigger once per tick position
            if tick != self.last_trigger_tick {
                if let Some((is_downbeat, is_subdivision)) =
                    self.should_trigger(tick, beats_per_bar)
                {
                    let ticks_per_beat = self.ppq as u64;
                    let beat_in_bar =
                        ((tick / ticks_per_beat) % beats_per_bar as u64) as u8;
                    self.trigger(beat_in_bar, is_downbeat, is_subdivision);
                    self.last_trigger_tick = tick;
                }
            }

            // Render current click sound sample-by-sample with per-sound volumes
            self.render_sample(output_l, output_r, frame);
        }

        false
    }

    /// Set custom accent sound
    pub fn set_accent_sound(&mut self, sound: ClickSound) {
        self.accent_sound = sound;
    }

    /// Set custom beat sound
    pub fn set_beat_sound(&mut self, sound: ClickSound) {
        self.beat_sound = sound;
    }

    /// Trigger click at specific beat position
    pub fn trigger(&mut self, _beat_in_bar: u8, is_downbeat: bool, is_subdivision: bool) {
        if !self.is_enabled() {
            return;
        }

        self.current_sound = Some(if is_downbeat {
            ClickSoundType::Accent
        } else if is_subdivision {
            ClickSoundType::Subdivision
        } else {
            ClickSoundType::Beat
        });
        self.playback_pos = 0;
    }

    /// Check if click should trigger at this tick position
    pub fn should_trigger(&self, tick: u64, beats_per_bar: u8) -> Option<(bool, bool)> {
        // is_downbeat, is_subdivision
        let ticks_per_beat = self.ppq as u64;
        let ticks_per_bar = ticks_per_beat * beats_per_bar as u64;

        // Check for downbeat
        if tick.is_multiple_of(ticks_per_bar) {
            return Some((true, false));
        }

        // Check for regular beat
        if tick.is_multiple_of(ticks_per_beat) && self.pattern != ClickPattern::DownbeatOnly {
            return Some((false, false));
        }

        // Check for subdivisions
        match self.pattern {
            ClickPattern::Eighth => {
                let subdivision_ticks = ticks_per_beat / 2;
                if tick.is_multiple_of(subdivision_ticks) && !tick.is_multiple_of(ticks_per_beat) {
                    return Some((false, true));
                }
            }
            ClickPattern::Sixteenth => {
                let subdivision_ticks = ticks_per_beat / 4;
                if tick.is_multiple_of(subdivision_ticks) && !tick.is_multiple_of(ticks_per_beat) {
                    return Some((false, true));
                }
            }
            ClickPattern::Triplet => {
                let subdivision_ticks = ticks_per_beat / 3;
                if tick.is_multiple_of(subdivision_ticks) && !tick.is_multiple_of(ticks_per_beat) {
                    return Some((false, true));
                }
            }
            _ => {}
        }

        None
    }

    /// Process audio block (legacy entry point — uses render_sample for per-sound volumes)
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        if !self.is_enabled() || self.current_sound.is_none() {
            return;
        }

        let to_process = left.len();
        for i in 0..to_process {
            self.render_sample(left, right, i);
        }
    }

    /// Reset playback state
    pub fn reset(&mut self) {
        self.current_sound = None;
        self.playback_pos = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLICK TRACK STATE (for serialization)
// ═══════════════════════════════════════════════════════════════════════════════

/// Click track settings (serializable)
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ClickTrackSettings {
    pub enabled: bool,
    pub volume: f32,
    pub accent_volume: f32,
    pub beat_volume: f32,
    pub subdivision_volume: f32,
    pub pattern: u8, // 0=Quarter, 1=Eighth, etc
    pub count_in: u8,
    pub pan: f32,
    pub preset: u8,
    pub audibility_mode: u8, // 0=Always, 1=RecordOnly, 2=CountInOnly
    pub tempo: f64,
    pub beats_per_bar: u8,
    pub accent_sound_path: Option<String>,
    pub beat_sound_path: Option<String>,
    #[serde(default)]
    pub only_during_record: bool, // legacy, superseded by audibility_mode
}

impl Default for ClickTrackSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            volume: 0.7,
            accent_volume: 1.0,
            beat_volume: 0.7,
            subdivision_volume: 0.4,
            pattern: 0,
            count_in: 0,
            pan: 0.0,
            preset: 0,
            audibility_mode: 0,
            tempo: 120.0,
            beats_per_bar: 4,
            accent_sound_path: None,
            beat_sound_path: None,
            only_during_record: false,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_click_sound_generation() {
        let sound = ClickSound::default_accent(48000);
        assert!(!sound.samples.is_empty());
        // ~15ms at 48kHz = ~720 samples
        assert!(sound.samples.len() > 500);
        assert!(sound.samples.len() < 1000);
    }

    #[test]
    fn test_click_pattern() {
        assert_eq!(ClickPattern::Quarter.clicks_per_beat(), 1);
        assert_eq!(ClickPattern::Eighth.clicks_per_beat(), 2);
        assert_eq!(ClickPattern::Triplet.clicks_per_beat(), 3);
    }

    #[test]
    fn test_count_in() {
        assert_eq!(CountInMode::Off.beats(4), 0);
        assert_eq!(CountInMode::OneBar.beats(4), 4);
        assert_eq!(CountInMode::TwoBars.beats(3), 6);
    }

    #[test]
    fn test_click_trigger() {
        let click = ClickTrack::new(48000);

        // Should trigger on downbeat (tick 0)
        assert!(click.should_trigger(0, 4).is_some());
        let (is_down, _) = click.should_trigger(0, 4).unwrap();
        assert!(is_down);

        // Should trigger on beat (tick 960)
        assert!(click.should_trigger(960, 4).is_some());
        let (is_down, _) = click.should_trigger(960, 4).unwrap();
        assert!(!is_down);
    }

    #[test]
    fn test_click_processing() {
        let mut click = ClickTrack::new(48000);
        click.set_enabled(true);
        click.trigger(0, true, false);

        let mut left = vec![0.0; 512];
        let mut right = vec![0.0; 512];

        click.process(&mut left, &mut right);

        // Should have non-zero samples
        assert!(left.iter().any(|&s| s.abs() > 0.001));
    }
}
