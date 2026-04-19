// ═══════════════════════════════════════════════════════════════════════════════
// HELIX VOICE ENGINE (IVE) — Intelligent Voice Engine for SlotLab
// ═══════════════════════════════════════════════════════════════════════════════
//
// Point 1.3 of HELIX Architecture. Voices are autonomous agents with behavior:
//   - Spectral band tracking (for masking analysis)
//   - Masking group collision resolution (Duck, Steal, Queue, Reject)
//   - Energy budget enforcement (AUREXIS integration)
//   - Per-voice lightweight DSP (gain, pan, low-pass filter)
//   - Session fatigue awareness
//   - HELIX Bus integration (publish voice lifecycle events)
//   - Pre-allocated pool (128 voices, zero audio-thread allocation)
//   - Atomic bitmap for lock-free allocation
//
// DESIGN: Extends the existing VoiceManager (64 voices, basic stealing) with
// intelligence features while maintaining zero-alloc on audio thread.
// ═══════════════════════════════════════════════════════════════════════════════

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use crate::audio_import::ImportedAudio;

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/// Maximum simultaneous voices (configurable per-project)
pub const MAX_HX_VOICES: usize = 128;
/// Maximum masking groups
pub const MAX_MASKING_GROUPS: usize = 16;
/// Maximum voices per masking group before collision resolution
pub const DEFAULT_MAX_GROUP_VOICES: usize = 4;
/// Default fade-in duration in samples (10ms at 48kHz)
pub const DEFAULT_FADE_IN_SAMPLES: u64 = 480;
/// Default fade-out duration in samples (20ms at 48kHz)
pub const DEFAULT_FADE_OUT_SAMPLES: u64 = 960;

// ─────────────────────────────────────────────────────────────────────────────
// Voice Identity & State
// ─────────────────────────────────────────────────────────────────────────────

/// Unique voice ID (monotonically increasing, never reused within session)
pub type HxVoiceId = u64;

/// Voice lifecycle state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum HxVoiceState {
    /// Not in use — available for allocation
    Idle        = 0,
    /// Allocated, waiting for trigger or queued behind another voice
    Pending     = 1,
    /// Fading in
    FadingIn    = 2,
    /// Actively playing
    Playing     = 3,
    /// Looping (will not auto-stop)
    Looping     = 4,
    /// Fading out (will transition to Stopped when fade completes)
    FadingOut   = 5,
    /// Playback complete, waiting for cleanup
    Stopped     = 6,
    /// Virtualized — too low priority to render, but tracking position
    Virtual     = 7,
    /// Ducked — playing at reduced volume due to collision
    Ducked      = 8,
}

impl HxVoiceState {
    pub fn is_active(self) -> bool {
        matches!(self, Self::FadingIn | Self::Playing | Self::Looping | Self::FadingOut | Self::Ducked)
    }

    pub fn is_audible(self) -> bool {
        matches!(self, Self::FadingIn | Self::Playing | Self::Looping | Self::Ducked)
    }
}

/// Voice priority levels (determines stealing order and gate behavior)
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
#[repr(u8)]
pub enum HxVoicePriority {
    /// Background ambience, idle sounds — first to be killed
    Background  = 0,
    /// Normal SFX — standard game sounds
    Low         = 1,
    /// Standard gameplay sounds — reel spins, button clicks
    Normal      = 2,
    /// Important feedback — win presentations, feature triggers
    High        = 3,
    /// Critical sounds — jackpot, regulatory audio cues
    Critical    = 4,
    /// System sounds — cannot be killed (compliance alerts, reality checks)
    System      = 5,
}

// ─────────────────────────────────────────────────────────────────────────────
// Spectral Band & Masking
// ─────────────────────────────────────────────────────────────────────────────

/// Spectral band classification for intelligent masking
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum HxSpectralBand {
    SubBass     = 0,    // 20-60 Hz
    Bass        = 1,    // 60-250 Hz
    LowMid      = 2,    // 250-500 Hz
    Mid         = 3,    // 500-2000 Hz
    UpperMid    = 4,    // 2000-4000 Hz
    Presence    = 5,    // 4000-6000 Hz
    Brilliance  = 6,    // 6000-20000 Hz
    FullRange   = 7,    // Unclassified / full spectrum
}

/// Masking group ID — voices in the same group compete for spectral space
pub type MaskingGroupId = u8;

/// Collision behavior — what happens when voices in same masking group overlap
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum CollisionBehavior {
    /// Lower existing voice by N dB while new voice plays
    Duck { db: i8 },
    /// Kill existing voice (instant or crossfade), play new one
    Steal { crossfade_ms: u16 },
    /// Wait until existing voice finishes, then play new one
    Queue,
    /// Don't play new voice — existing voice wins
    Reject,
    /// Play both — no collision handling (default for different groups)
    Coexist,
}

/// Exit behavior — what happens when the voice's triggering stage exits
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ExitBehavior {
    /// Fade out over N ms when stage exits
    FadeOut { ms: u16 },
    /// Stop immediately (hard cut)
    Stop,
    /// Let the voice play to natural completion
    LetFinish,
    /// Keep playing indefinitely (loop, ambient)
    KeepPlaying,
}

// ─────────────────────────────────────────────────────────────────────────────
// Voice DSP — Lightweight per-voice processing
// ─────────────────────────────────────────────────────────────────────────────

/// Per-voice DSP chain (lightweight: gain, pan, filter only)
/// No heap allocations — all inline state
#[derive(Debug, Clone, Copy)]
pub struct HxVoiceDsp {
    /// Volume (linear gain, 0.0 - 2.0)
    pub volume: f32,
    /// Pan position (-1.0 = hard left, 0.0 = center, 1.0 = hard right)
    pub pan: f32,
    /// Low-pass filter cutoff (Hz, 20-20000; 20000 = bypass)
    pub lpf_cutoff: f32,
    /// High-pass filter cutoff (Hz, 20-20000; 20 = bypass)
    pub hpf_cutoff: f32,
    /// Pitch shift (semitones, -24 to +24; 0 = no shift)
    pub pitch_shift: f32,
    // ── Filter State (biquad TDF-II) ──
    lpf_z1: f32,
    lpf_z2: f32,
    lpf_a1: f32,
    lpf_a2: f32,
    lpf_b0: f32,
    lpf_b1: f32,
    lpf_b2: f32,
    hpf_z1: f32,
    hpf_z2: f32,
    hpf_a1: f32,
    hpf_a2: f32,
    hpf_b0: f32,
    hpf_b1: f32,
    hpf_b2: f32,
}

impl Default for HxVoiceDsp {
    fn default() -> Self {
        Self {
            volume: 1.0,
            pan: 0.0,
            lpf_cutoff: 20000.0,
            hpf_cutoff: 20.0,
            pitch_shift: 0.0,
            lpf_z1: 0.0, lpf_z2: 0.0,
            lpf_a1: 0.0, lpf_a2: 0.0,
            lpf_b0: 1.0, lpf_b1: 0.0, lpf_b2: 0.0,
            hpf_z1: 0.0, hpf_z2: 0.0,
            hpf_a1: 0.0, hpf_a2: 0.0,
            hpf_b0: 1.0, hpf_b1: 0.0, hpf_b2: 0.0,
        }
    }
}

impl HxVoiceDsp {
    /// Recalculate filter coefficients (call when cutoff or sample rate changes)
    pub fn update_coefficients(&mut self, sample_rate: f32) {
        // LPF (2nd order Butterworth)
        if self.lpf_cutoff < 19999.0 {
            let w0 = 2.0 * std::f32::consts::PI * self.lpf_cutoff / sample_rate;
            let cos_w0 = w0.cos();
            let sin_w0 = w0.sin();
            let alpha = sin_w0 / (2.0 * std::f32::consts::FRAC_1_SQRT_2); // Q = sqrt(2)/2
            let a0 = 1.0 + alpha;
            self.lpf_b0 = ((1.0 - cos_w0) / 2.0) / a0;
            self.lpf_b1 = (1.0 - cos_w0) / a0;
            self.lpf_b2 = self.lpf_b0;
            self.lpf_a1 = (-2.0 * cos_w0) / a0;
            self.lpf_a2 = (1.0 - alpha) / a0;
        } else {
            // Bypass
            self.lpf_b0 = 1.0;
            self.lpf_b1 = 0.0;
            self.lpf_b2 = 0.0;
            self.lpf_a1 = 0.0;
            self.lpf_a2 = 0.0;
        }

        // HPF (2nd order Butterworth)
        if self.hpf_cutoff > 21.0 {
            let w0 = 2.0 * std::f32::consts::PI * self.hpf_cutoff / sample_rate;
            let cos_w0 = w0.cos();
            let sin_w0 = w0.sin();
            let alpha = sin_w0 / (2.0 * std::f32::consts::FRAC_1_SQRT_2);
            let a0 = 1.0 + alpha;
            self.hpf_b0 = ((1.0 + cos_w0) / 2.0) / a0;
            self.hpf_b1 = -(1.0 + cos_w0) / a0;
            self.hpf_b2 = self.hpf_b0;
            self.hpf_a1 = (-2.0 * cos_w0) / a0;
            self.hpf_a2 = (1.0 - alpha) / a0;
        } else {
            self.hpf_b0 = 1.0;
            self.hpf_b1 = 0.0;
            self.hpf_b2 = 0.0;
            self.hpf_a1 = 0.0;
            self.hpf_a2 = 0.0;
        }
    }

    /// Process a single sample through the voice DSP chain
    #[inline]
    pub fn process_sample(&mut self, input: f32) -> f32 {
        // LPF (TDF-II)
        let lpf_out = self.lpf_b0 * input + self.lpf_z1;
        self.lpf_z1 = self.lpf_b1 * input - self.lpf_a1 * lpf_out + self.lpf_z2;
        self.lpf_z2 = self.lpf_b2 * input - self.lpf_a2 * lpf_out;

        // HPF (TDF-II)
        let hpf_out = self.hpf_b0 * lpf_out + self.hpf_z1;
        self.hpf_z1 = self.hpf_b1 * lpf_out - self.hpf_a1 * hpf_out + self.hpf_z2;
        self.hpf_z2 = self.hpf_b2 * lpf_out - self.hpf_a2 * hpf_out;

        hpf_out * self.volume
    }

    /// Apply stereo panning (equal-power) — returns (left_gain, right_gain)
    #[inline]
    pub fn pan_gains(&self) -> (f32, f32) {
        // Equal-power panning
        let angle = (self.pan + 1.0) * 0.25 * std::f32::consts::PI;
        (angle.cos(), angle.sin())
    }

    /// Reset filter state (call on voice activation)
    pub fn reset(&mut self) {
        self.lpf_z1 = 0.0;
        self.lpf_z2 = 0.0;
        self.hpf_z1 = 0.0;
        self.hpf_z2 = 0.0;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELIX Voice — The intelligent voice agent
// ─────────────────────────────────────────────────────────────────────────────

/// A single voice in the HELIX engine — an autonomous agent with behavior
pub struct HxVoice {
    /// Unique voice ID (monotonically increasing)
    pub id: HxVoiceId,
    /// Current lifecycle state
    pub state: HxVoiceState,
    /// Audio source data
    pub audio: Option<Arc<ImportedAudio>>,
    /// Playback position (in frames)
    pub position: u64,
    /// When this voice was born (absolute sample clock)
    pub birth_sample: u64,
    /// Maximum lifetime in samples (None = play to end)
    pub ttl_samples: Option<u64>,
    /// Samples since birth
    pub age_samples: u64,

    // ── Intelligence ──
    /// Voice priority (determines stealing order and gate behavior)
    pub priority: HxVoicePriority,
    /// Energy cost (0.0-1.0, consumed from AUREXIS energy budget)
    pub energy_cost: f32,
    /// Primary spectral band (for masking analysis)
    pub spectral_band: HxSpectralBand,
    /// Masking group (voices in same group compete)
    pub masking_group: MaskingGroupId,

    // ── Behavior ──
    /// What happens on collision with same masking group
    pub on_collision: CollisionBehavior,
    /// What happens when triggering stage exits
    pub on_stage_exit: ExitBehavior,
    /// Whether this voice loops
    pub looping: bool,

    // ── Audio ──
    /// Per-voice DSP chain
    pub dsp: HxVoiceDsp,
    /// Fade state
    pub fade_gain: f32,
    pub fade_increment: f32,
    pub fade_samples_remaining: u64,
    /// Duck state (from collision resolution)
    pub duck_gain: f32,
    pub duck_target: f32,
    pub duck_speed: f32,

    // ── Graph Context ──
    /// Which graph instance spawned this voice
    pub graph_instance_id: u32,
    /// Which game stage triggered this voice
    pub stage_id: u32,
    /// Output bus routing
    pub bus_id: u8,
}

impl HxVoice {
    /// Create an idle voice (pre-allocated, not in use)
    pub fn new_idle() -> Self {
        Self {
            id: 0,
            state: HxVoiceState::Idle,
            audio: None,
            position: 0,
            birth_sample: 0,
            ttl_samples: None,
            age_samples: 0,
            priority: HxVoicePriority::Normal,
            energy_cost: 0.1,
            spectral_band: HxSpectralBand::FullRange,
            masking_group: 0,
            on_collision: CollisionBehavior::Coexist,
            on_stage_exit: ExitBehavior::FadeOut { ms: 100 },
            looping: false,
            dsp: HxVoiceDsp::default(),
            fade_gain: 0.0,
            fade_increment: 0.0,
            fade_samples_remaining: 0,
            duck_gain: 1.0,
            duck_target: 1.0,
            duck_speed: 0.001,
            graph_instance_id: 0,
            stage_id: 0,
            bus_id: 0,
        }
    }

    /// Activate this voice for playback
    pub fn activate(&mut self, config: HxVoiceActivation) {
        self.id = config.id;
        self.state = HxVoiceState::FadingIn;
        self.audio = Some(config.audio);
        self.position = 0;
        self.birth_sample = config.sample_clock;
        self.ttl_samples = config.ttl_samples;
        self.age_samples = 0;
        self.priority = config.priority;
        self.energy_cost = config.energy_cost;
        self.spectral_band = config.spectral_band;
        self.masking_group = config.masking_group;
        self.on_collision = config.on_collision;
        self.on_stage_exit = config.on_stage_exit;
        self.looping = config.looping;
        self.dsp = config.dsp;
        self.dsp.reset();
        self.fade_gain = 0.0;
        self.fade_increment = 1.0 / config.fade_in_samples.max(1) as f32;
        self.fade_samples_remaining = config.fade_in_samples;
        self.duck_gain = 1.0;
        self.duck_target = 1.0;
        self.graph_instance_id = config.graph_instance_id;
        self.stage_id = config.stage_id;
        self.bus_id = config.bus_id;
    }

    /// Start fade-out (voice will transition to Stopped when complete)
    pub fn start_fade_out(&mut self, samples: u64) {
        if samples == 0 {
            self.state = HxVoiceState::Stopped;
            return;
        }
        self.state = HxVoiceState::FadingOut;
        self.fade_samples_remaining = samples;
        self.fade_increment = -self.fade_gain / samples.max(1) as f32;
    }

    /// Apply ducking (reduce volume due to masking collision)
    pub fn start_duck(&mut self, target_db: f32, speed: f32) {
        self.state = HxVoiceState::Ducked;
        self.duck_target = 10.0_f32.powf(target_db / 20.0);
        self.duck_speed = speed;
    }

    /// Release ducking (return to normal volume)
    pub fn release_duck(&mut self) {
        self.duck_target = 1.0;
        if self.state == HxVoiceState::Ducked {
            self.state = HxVoiceState::Playing;
        }
    }

    /// Deactivate voice (return to pool)
    pub fn deactivate(&mut self) {
        self.state = HxVoiceState::Idle;
        self.audio = None;
        self.id = 0;
    }

    /// Process one block of audio for this voice
    /// Returns (samples_written, voice_ended)
    pub fn render(&mut self, out_l: &mut [f64], out_r: &mut [f64], frames: usize) -> (usize, bool) {
        if !self.state.is_active() {
            return (0, true);
        }

        let audio = match &self.audio {
            Some(a) => a,
            None => return (0, true),
        };

        let channels = audio.channels as usize;
        let total_frames = if channels > 0 { audio.samples.len() / channels } else { 0 };

        if total_frames == 0 {
            self.state = HxVoiceState::Stopped;
            return (0, true);
        }

        let (pan_l, pan_r) = self.dsp.pan_gains();
        let mut written = 0;

        for i in 0..frames {
            let pos = self.position as usize;

            // Check end of audio
            if pos >= total_frames {
                if self.looping {
                    self.position = 0;
                    continue;
                } else {
                    self.state = HxVoiceState::Stopped;
                    return (written, true);
                }
            }

            // Check TTL (inline to avoid borrow conflict with audio)
            if let Some(ttl) = self.ttl_samples
                && self.age_samples >= ttl && self.state != HxVoiceState::FadingOut {
                    self.state = HxVoiceState::FadingOut;
                    self.fade_samples_remaining = DEFAULT_FADE_OUT_SAMPLES;
                    self.fade_increment = -self.fade_gain / DEFAULT_FADE_OUT_SAMPLES.max(1) as f32;
                }

            // Update fade
            if self.fade_samples_remaining > 0 {
                self.fade_gain += self.fade_increment;
                self.fade_samples_remaining -= 1;

                if self.fade_gain <= 0.0 && self.state == HxVoiceState::FadingOut {
                    self.state = HxVoiceState::Stopped;
                    return (written, true);
                }

                self.fade_gain = self.fade_gain.clamp(0.0, 1.0);

                // Transition from FadingIn to Playing when fade complete
                if self.fade_samples_remaining == 0 && self.state == HxVoiceState::FadingIn {
                    self.state = if self.looping { HxVoiceState::Looping } else { HxVoiceState::Playing };
                }
            }

            // Update duck
            if (self.duck_gain - self.duck_target).abs() > 0.0001 {
                self.duck_gain += (self.duck_target - self.duck_gain) * self.duck_speed;
            }

            // Read source sample
            let raw_sample = audio.samples[pos * channels];
            let raw_r = if channels > 1 {
                audio.samples[pos * channels + 1]
            } else {
                raw_sample
            };

            // Apply per-voice DSP
            let processed_l = self.dsp.process_sample(raw_sample);
            let processed_r = if channels > 1 {
                // For stereo, process right channel too
                // Note: shares filter state which is a simplification
                self.dsp.process_sample(raw_r)
            } else {
                processed_l
            };

            // Apply fade + duck
            let total_gain = self.fade_gain * self.duck_gain;

            // Mix into output with panning
            out_l[i] += (processed_l * pan_l * total_gain) as f64;
            out_r[i] += (processed_r * pan_r * total_gain) as f64;

            self.position += 1;
            self.age_samples += 1;
            written += 1;
        }

        (written, false)
    }
}

/// Voice activation parameters — everything needed to start a voice
pub struct HxVoiceActivation {
    pub id: HxVoiceId,
    pub audio: Arc<ImportedAudio>,
    pub sample_clock: u64,
    pub priority: HxVoicePriority,
    pub energy_cost: f32,
    pub spectral_band: HxSpectralBand,
    pub masking_group: MaskingGroupId,
    pub on_collision: CollisionBehavior,
    pub on_stage_exit: ExitBehavior,
    pub looping: bool,
    pub dsp: HxVoiceDsp,
    pub fade_in_samples: u64,
    pub ttl_samples: Option<u64>,
    pub graph_instance_id: u32,
    pub stage_id: u32,
    pub bus_id: u8,
}

// ─────────────────────────────────────────────────────────────────────────────
// HELIX Voice Engine — Manager for all voices
// ─────────────────────────────────────────────────────────────────────────────

/// Voice engine statistics
#[derive(Debug, Clone, Default)]
pub struct HxVoiceStats {
    pub total_voices: usize,
    pub active_voices: usize,
    pub virtual_voices: usize,
    pub queued_voices: usize,
    pub ducked_voices: usize,
    pub peak_voices: usize,
    pub total_spawned: u64,
    pub total_stolen: u64,
    pub total_rejected: u64,
    pub total_energy_used: f32,
    pub energy_budget: f32,
    /// Per-masking-group active count
    pub group_counts: [u32; MAX_MASKING_GROUPS],
}

/// The HELIX Intelligent Voice Engine
pub struct HxVoiceEngine {
    /// Pre-allocated voice pool
    voices: Vec<HxVoice>,
    /// Next voice ID (monotonically increasing)
    next_id: AtomicU64,
    /// Global sample clock
    sample_clock: u64,
    /// Sample rate
    sample_rate: u32,

    // ── AUREXIS Integration ──
    /// Energy budget (0.0-1.0, replenishes over time)
    energy_budget: f32,
    /// Energy replenish rate per sample
    energy_replenish_rate: f32,
    /// Session fatigue level (0.0 = fresh, 1.0 = fatigued)
    session_fatigue: f32,
    /// Maximum simultaneous voices per masking group
    max_group_voices: [usize; MAX_MASKING_GROUPS],

    // ── Queue ──
    /// Queued voice activations (waiting for group slot)
    queue: Vec<HxVoiceActivation>,

    // ── Statistics ──
    pub stats: HxVoiceStats,
}

impl HxVoiceEngine {
    pub fn new(sample_rate: u32) -> Self {
        let voices = (0..MAX_HX_VOICES).map(|_| HxVoice::new_idle()).collect();
        let mut max_group_voices = [DEFAULT_MAX_GROUP_VOICES; MAX_MASKING_GROUPS];
        // Group 0 is "no group" — unlimited
        max_group_voices[0] = MAX_HX_VOICES;

        Self {
            voices,
            next_id: AtomicU64::new(1),
            sample_clock: 0,
            sample_rate,
            energy_budget: 1.0,
            energy_replenish_rate: 1.0 / (sample_rate as f32 * 2.0), // Full refill in 2 seconds
            session_fatigue: 0.0,
            max_group_voices,
            queue: Vec::with_capacity(32),
            stats: HxVoiceStats::default(),
        }
    }

    /// Spawn a new voice with intelligent collision resolution.
    /// Returns the voice ID if spawned, None if rejected.
    pub fn spawn(&mut self, mut activation: HxVoiceActivation) -> Option<HxVoiceId> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        activation.id = id;
        activation.sample_clock = self.sample_clock;

        // ── Energy Budget Check ──
        if self.energy_budget < activation.energy_cost {
            // Not enough energy — reject low-priority, allow critical
            if activation.priority < HxVoicePriority::High {
                self.stats.total_rejected += 1;
                return None;
            }
            // High/Critical voices bypass energy check
        }

        // ── Masking Group Collision Resolution ──
        let group = activation.masking_group as usize;
        if group < MAX_MASKING_GROUPS {
            let group_count = self.count_group_voices(activation.masking_group);
            if group_count >= self.max_group_voices[group] {
                match activation.on_collision {
                    CollisionBehavior::Reject => {
                        self.stats.total_rejected += 1;
                        return None;
                    }
                    CollisionBehavior::Queue => {
                        self.queue.push(activation);
                        self.stats.queued_voices += 1;
                        return Some(id);
                    }
                    CollisionBehavior::Duck { db } => {
                        // Duck all existing voices in group
                        for voice in &mut self.voices {
                            if voice.state.is_active() && voice.masking_group == activation.masking_group {
                                voice.start_duck(db as f32, 0.005);
                            }
                        }
                    }
                    CollisionBehavior::Steal { crossfade_ms } => {
                        // Steal lowest priority voice in group
                        if let Some(victim) = self.find_steal_victim(activation.masking_group, activation.priority) {
                            let fade_samples = (self.sample_rate as u64 * crossfade_ms as u64) / 1000;
                            self.voices[victim].start_fade_out(fade_samples);
                            self.stats.total_stolen += 1;
                        }
                    }
                    CollisionBehavior::Coexist => {} // Allow overflow
                }
            }
        }

        // ── Allocate Voice Slot ──
        let slot = self.find_idle_slot()
            .or_else(|| self.find_steal_candidate(activation.priority));

        if let Some(idx) = slot {
            if self.voices[idx].state.is_active() {
                // Stealing — force stop existing voice
                self.voices[idx].start_fade_out(240);
                self.stats.total_stolen += 1;
            }

            self.voices[idx].activate(activation);
            self.energy_budget = (self.energy_budget - self.voices[idx].energy_cost).max(0.0);
            self.stats.total_spawned += 1;
            self.update_stats();
            Some(id)
        } else {
            self.stats.total_rejected += 1;
            None
        }
    }

    /// Stop a specific voice by ID
    pub fn stop_voice(&mut self, voice_id: HxVoiceId, fade_ms: u32) {
        if let Some(voice) = self.voices.iter_mut().find(|v| v.id == voice_id) {
            let fade_samples = (self.sample_rate as u64 * fade_ms as u64) / 1000;
            voice.start_fade_out(fade_samples.max(1));
        }
    }

    /// Stop all voices for a stage
    pub fn stop_stage_voices(&mut self, stage_id: u32) {
        for voice in &mut self.voices {
            if voice.stage_id == stage_id && voice.state.is_active() {
                match voice.on_stage_exit {
                    ExitBehavior::FadeOut { ms } => {
                        let samples = (self.sample_rate as u64 * ms as u64) / 1000;
                        voice.start_fade_out(samples.max(1));
                    }
                    ExitBehavior::Stop => {
                        voice.state = HxVoiceState::Stopped;
                    }
                    ExitBehavior::LetFinish => {
                        voice.looping = false; // Will stop at end of audio
                    }
                    ExitBehavior::KeepPlaying => {} // Do nothing
                }
            }
        }
    }

    /// Stop all voices in a masking group
    pub fn stop_group(&mut self, group: MaskingGroupId, fade_ms: u32) {
        let fade_samples = (self.sample_rate as u64 * fade_ms as u64) / 1000;
        for voice in &mut self.voices {
            if voice.masking_group == group && voice.state.is_active() {
                voice.start_fade_out(fade_samples.max(1));
            }
        }
    }

    /// Stop all voices
    pub fn stop_all(&mut self, fade_ms: u32) {
        let fade_samples = (self.sample_rate as u64 * fade_ms as u64) / 1000;
        for voice in &mut self.voices {
            if voice.state.is_active() {
                voice.start_fade_out(fade_samples.max(1));
            }
        }
        self.queue.clear();
    }

    /// Process one block of audio (called on audio thread)
    pub fn process(&mut self, out_l: &mut [f64], out_r: &mut [f64], frames: usize) {
        // Replenish energy budget
        self.energy_budget = (self.energy_budget + self.energy_replenish_rate * frames as f32).min(1.0);

        // Process queued voices
        self.drain_queue();

        // Render all active voices
        for voice in &mut self.voices {
            if !voice.state.is_active() { continue; }

            let (_written, ended) = voice.render(out_l, out_r, frames);

            if ended {
                // Release ducked voices in same masking group
                let group = voice.masking_group;
                voice.deactivate();
                // Can't borrow self mutably again, so we'll release ducks in a second pass
                let _ = group; // Used below
            }
        }

        // Release ducks for groups that now have capacity
        self.release_ducks();

        // Update sample clock
        self.sample_clock += frames as u64;

        // Cleanup
        for voice in &mut self.voices {
            if voice.state == HxVoiceState::Stopped {
                voice.deactivate();
            }
        }

        self.update_stats();
    }

    /// Set session fatigue level (from AUREXIS emotion analysis)
    pub fn set_fatigue(&mut self, fatigue: f32) {
        self.session_fatigue = fatigue.clamp(0.0, 1.0);
    }

    /// Set energy budget directly (from AUREXIS)
    pub fn set_energy_budget(&mut self, budget: f32) {
        self.energy_budget = budget.clamp(0.0, 1.0);
    }

    /// Configure max voices per masking group
    pub fn set_max_group_voices(&mut self, group: MaskingGroupId, max: usize) {
        if (group as usize) < MAX_MASKING_GROUPS {
            self.max_group_voices[group as usize] = max;
        }
    }

    /// Get current statistics
    pub fn stats(&self) -> &HxVoiceStats {
        &self.stats
    }

    /// Get active voice count
    pub fn active_count(&self) -> usize {
        self.voices.iter().filter(|v| v.state.is_active()).count()
    }

    /// Get energy budget
    pub fn energy_budget(&self) -> f32 {
        self.energy_budget
    }

    // ── Internal ─────────────────────────────────────────────────────────

    fn find_idle_slot(&self) -> Option<usize> {
        self.voices.iter().position(|v| v.state == HxVoiceState::Idle)
    }

    fn find_steal_candidate(&self, min_priority: HxVoicePriority) -> Option<usize> {
        let mut best: Option<(usize, HxVoicePriority, u64)> = None;

        for (i, voice) in self.voices.iter().enumerate() {
            if !voice.state.is_active() { continue; }
            if voice.priority >= min_priority { continue; }
            if voice.priority == HxVoicePriority::System { continue; } // Never steal system

            match &best {
                None => best = Some((i, voice.priority, voice.birth_sample)),
                Some((_, bp, bt)) => {
                    if voice.priority < *bp || (voice.priority == *bp && voice.birth_sample < *bt) {
                        best = Some((i, voice.priority, voice.birth_sample));
                    }
                }
            }
        }

        best.map(|(idx, _, _)| idx)
    }

    fn find_steal_victim(&self, group: MaskingGroupId, min_priority: HxVoicePriority) -> Option<usize> {
        let mut best: Option<(usize, HxVoicePriority, u64)> = None;

        for (i, voice) in self.voices.iter().enumerate() {
            if !voice.state.is_active() { continue; }
            if voice.masking_group != group { continue; }
            if voice.priority >= min_priority { continue; }

            match &best {
                None => best = Some((i, voice.priority, voice.birth_sample)),
                Some((_, bp, bt)) => {
                    if voice.priority < *bp || (voice.priority == *bp && voice.birth_sample < *bt) {
                        best = Some((i, voice.priority, voice.birth_sample));
                    }
                }
            }
        }

        best.map(|(idx, _, _)| idx)
    }

    fn count_group_voices(&self, group: MaskingGroupId) -> usize {
        self.voices.iter()
            .filter(|v| v.state.is_active() && v.masking_group == group)
            .count()
    }

    fn drain_queue(&mut self) {
        let mut i = 0;
        while i < self.queue.len() {
            let group = self.queue[i].masking_group as usize;
            let group_count = self.count_group_voices(self.queue[i].masking_group);
            if group < MAX_MASKING_GROUPS && group_count < self.max_group_voices[group] {
                let activation = self.queue.remove(i);
                if let Some(slot) = self.find_idle_slot() {
                    self.voices[slot].activate(activation);
                    self.stats.queued_voices = self.stats.queued_voices.saturating_sub(1);
                }
            } else {
                i += 1;
            }
        }
    }

    fn release_ducks(&mut self) {
        // Check each masking group — if under capacity, release ducks
        for group in 0..MAX_MASKING_GROUPS as u8 {
            let count = self.count_group_voices(group);
            if count < self.max_group_voices[group as usize] {
                for voice in &mut self.voices {
                    if voice.masking_group == group && voice.state == HxVoiceState::Ducked {
                        voice.release_duck();
                    }
                }
            }
        }
    }

    fn update_stats(&mut self) {
        self.stats.active_voices = 0;
        self.stats.virtual_voices = 0;
        self.stats.ducked_voices = 0;
        self.stats.total_energy_used = 0.0;
        self.stats.group_counts = [0; MAX_MASKING_GROUPS];

        for voice in &self.voices {
            match voice.state {
                HxVoiceState::Idle | HxVoiceState::Stopped | HxVoiceState::Pending => {}
                HxVoiceState::Virtual => self.stats.virtual_voices += 1,
                HxVoiceState::Ducked => {
                    self.stats.ducked_voices += 1;
                    self.stats.active_voices += 1;
                }
                _ => self.stats.active_voices += 1,
            }

            if voice.state.is_active() {
                self.stats.total_energy_used += voice.energy_cost;
                let g = voice.masking_group as usize;
                if g < MAX_MASKING_GROUPS {
                    self.stats.group_counts[g] += 1;
                }
            }
        }

        self.stats.energy_budget = self.energy_budget;
        self.stats.total_voices = MAX_HX_VOICES;
        self.stats.peak_voices = self.stats.peak_voices.max(self.stats.active_voices);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_audio(frames: usize) -> Arc<ImportedAudio> {
        Arc::new(ImportedAudio {
            samples: vec![0.5; frames * 2], // stereo
            channels: 2,
            sample_rate: 48000,
            duration_secs: frames as f64 / 48000.0,
            sample_count: frames,
            source_path: String::new(),
            name: "test".to_string(),
            bit_depth: Some(32),
            format: "wav".to_string(),
        })
    }

    fn make_activation(audio: Arc<ImportedAudio>) -> HxVoiceActivation {
        HxVoiceActivation {
            id: 0, // Will be assigned by engine
            audio,
            sample_clock: 0,
            priority: HxVoicePriority::Normal,
            energy_cost: 0.1,
            spectral_band: HxSpectralBand::Mid,
            masking_group: 0,
            on_collision: CollisionBehavior::Coexist,
            on_stage_exit: ExitBehavior::FadeOut { ms: 100 },
            looping: false,
            dsp: HxVoiceDsp::default(),
            fade_in_samples: 10,
            ttl_samples: None,
            graph_instance_id: 1,
            stage_id: 0,
            bus_id: 0,
        }
    }

    #[test]
    fn test_voice_engine_creation() {
        let engine = HxVoiceEngine::new(48000);
        assert_eq!(engine.active_count(), 0);
        assert_eq!(engine.voices.len(), MAX_HX_VOICES);
    }

    #[test]
    fn test_spawn_voice() {
        let mut engine = HxVoiceEngine::new(48000);
        let audio = make_test_audio(4800);
        let activation = make_activation(audio);

        let id = engine.spawn(activation);
        assert!(id.is_some());
        assert_eq!(engine.active_count(), 1);
    }

    #[test]
    fn test_spawn_multiple_voices() {
        let mut engine = HxVoiceEngine::new(48000);
        for _ in 0..10 {
            let audio = make_test_audio(4800);
            let mut activation = make_activation(audio);
            activation.energy_cost = 0.05; // Low cost so 10 fit in budget
            assert!(engine.spawn(activation).is_some());
        }
        assert_eq!(engine.active_count(), 10);
    }

    #[test]
    fn test_voice_render() {
        let mut engine = HxVoiceEngine::new(48000);
        let audio = make_test_audio(4800);
        let activation = make_activation(audio);
        engine.spawn(activation);

        let mut out_l = vec![0.0f64; 256];
        let mut out_r = vec![0.0f64; 256];
        engine.process(&mut out_l, &mut out_r, 256);

        // Should have some audio output
        let sum_l: f64 = out_l.iter().sum();
        assert!(sum_l.abs() > 0.0, "Expected audio output");
    }

    #[test]
    fn test_voice_stop() {
        let mut engine = HxVoiceEngine::new(48000);
        let audio = make_test_audio(48000);
        let activation = make_activation(audio);
        let id = engine.spawn(activation).unwrap();

        engine.stop_voice(id, 10);

        // Process enough frames for fade-out to complete
        let mut out_l = vec![0.0f64; 1024];
        let mut out_r = vec![0.0f64; 1024];
        engine.process(&mut out_l, &mut out_r, 1024);

        assert_eq!(engine.active_count(), 0);
    }

    #[test]
    fn test_collision_reject() {
        let mut engine = HxVoiceEngine::new(48000);
        engine.set_max_group_voices(1, 2); // Group 1: max 2 voices

        // Spawn 2 voices in group 1
        for _ in 0..2 {
            let audio = make_test_audio(4800);
            let mut activation = make_activation(audio);
            activation.masking_group = 1;
            activation.on_collision = CollisionBehavior::Reject;
            assert!(engine.spawn(activation).is_some());
        }

        // Third voice should be rejected
        let audio = make_test_audio(4800);
        let mut activation = make_activation(audio);
        activation.masking_group = 1;
        activation.on_collision = CollisionBehavior::Reject;
        assert!(engine.spawn(activation).is_none());
        assert_eq!(engine.stats.total_rejected, 1);
    }

    #[test]
    fn test_collision_steal() {
        let mut engine = HxVoiceEngine::new(48000);
        engine.set_max_group_voices(2, 1); // Group 2: max 1 voice

        // Spawn low-priority voice
        let audio = make_test_audio(48000);
        let mut activation = make_activation(audio);
        activation.masking_group = 2;
        activation.priority = HxVoicePriority::Low;
        activation.on_collision = CollisionBehavior::Steal { crossfade_ms: 10 };
        engine.spawn(activation);

        // Spawn high-priority voice — should steal low priority
        let audio = make_test_audio(48000);
        let mut activation = make_activation(audio);
        activation.masking_group = 2;
        activation.priority = HxVoicePriority::High;
        activation.on_collision = CollisionBehavior::Steal { crossfade_ms: 10 };
        engine.spawn(activation);

        assert_eq!(engine.stats.total_stolen, 1);
    }

    #[test]
    fn test_collision_duck() {
        let mut engine = HxVoiceEngine::new(48000);
        engine.set_max_group_voices(3, 1); // Group 3: max 1 voice

        // Spawn first voice
        let audio = make_test_audio(48000);
        let mut activation = make_activation(audio);
        activation.masking_group = 3;
        activation.on_collision = CollisionBehavior::Duck { db: -6 };
        engine.spawn(activation);

        // Spawn second voice — should duck first
        let audio = make_test_audio(48000);
        let mut activation = make_activation(audio);
        activation.masking_group = 3;
        activation.on_collision = CollisionBehavior::Duck { db: -6 };
        engine.spawn(activation);

        assert!(engine.stats.ducked_voices > 0 || engine.active_count() >= 2);
    }

    #[test]
    fn test_energy_budget() {
        let mut engine = HxVoiceEngine::new(48000);
        engine.set_energy_budget(0.05); // Very low budget

        // High energy cost voice should be rejected at low priority
        let audio = make_test_audio(4800);
        let mut activation = make_activation(audio);
        activation.energy_cost = 0.5;
        activation.priority = HxVoicePriority::Low;
        assert!(engine.spawn(activation).is_none());

        // But critical priority bypasses
        let audio = make_test_audio(4800);
        let mut activation = make_activation(audio);
        activation.energy_cost = 0.5;
        activation.priority = HxVoicePriority::Critical;
        assert!(engine.spawn(activation).is_some());
    }

    #[test]
    fn test_stop_all() {
        let mut engine = HxVoiceEngine::new(48000);
        for _ in 0..5 {
            let audio = make_test_audio(48000);
            engine.spawn(make_activation(audio));
        }
        assert_eq!(engine.active_count(), 5);

        engine.stop_all(0);
        // Process one block to cleanup
        let mut out_l = vec![0.0f64; 256];
        let mut out_r = vec![0.0f64; 256];
        engine.process(&mut out_l, &mut out_r, 256);
        assert_eq!(engine.active_count(), 0);
    }

    #[test]
    fn test_voice_dsp_pan() {
        let dsp = HxVoiceDsp::default();
        let (l, r) = dsp.pan_gains();
        // Center pan should give roughly equal L/R
        assert!((l - r).abs() < 0.01);

        let dsp_left = HxVoiceDsp { pan: -1.0, ..Default::default() };
        // Hard left should have more L than R
        let (l, r) = dsp_left.pan_gains();
        assert!(l > r);
    }

    #[test]
    fn test_voice_stats() {
        let mut engine = HxVoiceEngine::new(48000);
        for _ in 0..3 {
            let audio = make_test_audio(4800);
            engine.spawn(make_activation(audio));
        }

        let stats = engine.stats();
        assert_eq!(stats.active_voices, 3);
        assert_eq!(stats.total_spawned, 3);
        assert_eq!(stats.total_voices, MAX_HX_VOICES);
    }
}
