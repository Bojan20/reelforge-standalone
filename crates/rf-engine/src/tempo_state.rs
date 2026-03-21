//! Tempo State Engine — Wwise-style interactive music tempo transitions
//!
//! Orchestrates tempo state changes for the same musical material at different tempos.
//! Uses dual-voice crossfade (two Signalsmith Stretch instances) or real-time tempo ramp.
//!
//! ## Architecture
//!
//! ```text
//! UI Thread                          Audio Thread
//! ─────────                          ────────────
//! trigger_state("free_spins")  ──>   BeatGridTracker (sync point detection)
//!                                         │
//!                                    sync point hit!
//!                                         │
//!                                    ┌────┴────┐
//!                                    │ Voice A  │ (fade out, old tempo)
//!                                    │ Voice B  │ (fade in, new tempo)
//!                                    └────┬────┘
//!                                         │
//!                                    CrossfadeProcessor
//!                                         │
//!                                    output bus
//! ```
//!
//! ## Thread Safety
//! - `trigger_state()` is called from UI thread (sets pending state via atomic)
//! - `process()` runs on audio thread (zero alloc, zero locks)
//! - State queries use atomic reads

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};

use rf_dsp::beat_grid::{BeatGridTracker, SyncMode, TempoRampType};
use rf_dsp::crossfade::{CrossfadeProcessor, CrossfadeState, FadeCurve};

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Unique identifier for a tempo state
pub type TempoStateId = u32;

/// Tempo state definition
#[derive(Debug, Clone)]
pub struct TempoState {
    /// Unique ID
    pub id: TempoStateId,
    /// Human-readable name (e.g., "base_game", "free_spins")
    pub name: String,
    /// Target BPM for this state
    pub target_bpm: f64,
}

/// Transition rule between two tempo states
#[derive(Debug, Clone)]
pub struct TempoTransitionRule {
    /// Source state ID (0 = any)
    pub from_state: TempoStateId,
    /// Target state ID
    pub to_state: TempoStateId,
    /// When to start the transition
    pub sync_mode: SyncMode,
    /// Crossfade duration in bars
    pub duration_bars: u32,
    /// Tempo ramp type during crossfade
    pub ramp_type: TempoRampType,
    /// Crossfade curve
    pub fade_curve: FadeCurve,
}

impl Default for TempoTransitionRule {
    fn default() -> Self {
        Self {
            from_state: 0,
            to_state: 0,
            sync_mode: SyncMode::Bar,
            duration_bars: 2,
            ramp_type: TempoRampType::Linear,
            fade_curve: FadeCurve::EqualPower,
        }
    }
}

/// Internal voice for dual-voice crossfade
struct Voice {
    /// Stretch factor applied to source audio
    stretch_factor: f64,
    /// Whether this voice is active
    active: bool,
}

/// Engine processing state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EnginePhase {
    /// Steady state — single voice playing
    Steady,
    /// Waiting for sync point to start transition
    WaitingForSync,
    /// Crossfade in progress between two voices
    Crossfading,
}

// ═══════════════════════════════════════════════════════════════════════════════
// TEMPO STATE ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Interactive music tempo state engine
///
/// Manages tempo state transitions with beat-synced crossfades.
/// Designed for slot game music that plays the same composition at
/// different tempos depending on game state.
pub struct TempoStateEngine {
    /// Registered tempo states
    states: HashMap<TempoStateId, TempoState>,
    /// Name → ID lookup
    name_to_id: HashMap<String, TempoStateId>,
    /// Transition rules (from_id, to_id) → rule
    rules: HashMap<(TempoStateId, TempoStateId), TempoTransitionRule>,
    /// Default transition rule (used when no specific rule exists)
    default_rule: TempoTransitionRule,

    /// Beat grid tracker
    beat_grid: BeatGridTracker,
    /// Crossfade processor
    crossfade: CrossfadeProcessor,

    /// Voice A (current/outgoing)
    voice_a: Voice,
    /// Voice B (incoming)
    voice_b: Voice,

    /// Current active state ID
    current_state_id: TempoStateId,
    /// Pending state ID (set from UI thread, consumed by audio thread)
    pending_state_id: AtomicU32,
    /// Target state for in-progress transition
    target_state_id: TempoStateId,

    /// Current engine phase
    phase: EnginePhase,
    /// Source BPM of the music material
    source_bpm: f64,
    /// Sample rate
    sample_rate: f64,

    /// Next state ID for auto-increment
    next_id: TempoStateId,
}

impl TempoStateEngine {
    /// Create a new tempo state engine
    ///
    /// # Arguments
    /// * `source_bpm` - Original BPM of the music material
    /// * `beats_per_bar` - Time signature numerator
    /// * `sample_rate` - Audio sample rate
    pub fn new(source_bpm: f64, beats_per_bar: u32, sample_rate: f64) -> Self {
        Self {
            states: HashMap::new(),
            name_to_id: HashMap::new(),
            rules: HashMap::new(),
            default_rule: TempoTransitionRule::default(),
            beat_grid: BeatGridTracker::new(source_bpm, beats_per_bar, sample_rate),
            crossfade: CrossfadeProcessor::new(FadeCurve::EqualPower),
            voice_a: Voice { stretch_factor: 1.0, active: true },
            voice_b: Voice { stretch_factor: 1.0, active: false },
            current_state_id: 0,
            pending_state_id: AtomicU32::new(0),
            target_state_id: 0,
            phase: EnginePhase::Steady,
            source_bpm,
            sample_rate,
            next_id: 1,
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Configuration (UI thread)
    // ─────────────────────────────────────────────────────────────────────────

    /// Add a tempo state
    ///
    /// Returns the state ID.
    pub fn add_state(&mut self, name: &str, target_bpm: f64) -> TempoStateId {
        let id = self.next_id;
        self.next_id += 1;

        let state = TempoState {
            id,
            name: name.to_string(),
            target_bpm: target_bpm.clamp(20.0, 999.0),
        };

        self.name_to_id.insert(name.to_string(), id);
        self.states.insert(id, state);
        id
    }

    /// Set a transition rule between two states
    pub fn set_transition_rule(&mut self, rule: TempoTransitionRule) {
        self.rules.insert((rule.from_state, rule.to_state), rule);
    }

    /// Set the default transition rule (used when no specific rule matches)
    pub fn set_default_rule(&mut self, rule: TempoTransitionRule) {
        self.default_rule = rule;
    }

    /// Set the initial active state
    pub fn set_initial_state(&mut self, name: &str) {
        if let Some(&id) = self.name_to_id.get(name) {
            self.current_state_id = id;
            if let Some(state) = self.states.get(&id) {
                self.beat_grid.set_tempo(state.target_bpm);
                self.voice_a.stretch_factor = self.source_bpm / state.target_bpm;
                self.voice_a.active = true;
            }
        }
    }

    /// Trigger a transition to a new tempo state (UI thread safe)
    ///
    /// The actual transition will start at the next sync point
    /// as defined by the transition rule.
    pub fn trigger_state(&self, name: &str) {
        if let Some(&id) = self.name_to_id.get(name) {
            self.pending_state_id.store(id, Ordering::Release);
        }
    }

    /// Trigger a transition by state ID (UI thread safe)
    pub fn trigger_state_by_id(&self, id: TempoStateId) {
        self.pending_state_id.store(id, Ordering::Release);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Audio thread processing
    // ─────────────────────────────────────────────────────────────────────────

    /// Process one audio block — advance beat grid and manage transitions
    ///
    /// # Audio Thread Safe
    /// Zero allocations, zero locks. Only arithmetic and atomic ops.
    ///
    /// # Arguments
    /// * `num_samples` - Block size
    ///
    /// # Returns
    /// `(stretch_factor_a, gain_a, stretch_factor_b, gain_b)` for the dual voices.
    /// When not crossfading, voice B gains are 0.0.
    pub fn process(&mut self, num_samples: usize) -> VoiceGains {
        // Check for pending state change
        let pending = self.pending_state_id.load(Ordering::Acquire);
        if pending != 0 && pending != self.current_state_id && self.phase == EnginePhase::Steady {
            self.begin_transition(pending);
        }

        // Advance beat grid
        self.beat_grid.advance(num_samples);

        // Handle phase transitions
        match self.phase {
            EnginePhase::Steady => {
                VoiceGains {
                    voice_a_stretch: self.voice_a.stretch_factor,
                    voice_a_gain: 1.0,
                    voice_b_stretch: 1.0,
                    voice_b_gain: 0.0,
                    bpm: self.beat_grid.position().bpm,
                }
            }
            EnginePhase::WaitingForSync => {
                if self.beat_grid.sync_triggered() {
                    self.start_crossfade();
                }
                // Still playing voice A only while waiting
                VoiceGains {
                    voice_a_stretch: self.voice_a.stretch_factor,
                    voice_a_gain: 1.0,
                    voice_b_stretch: self.voice_b.stretch_factor,
                    voice_b_gain: 0.0,
                    bpm: self.beat_grid.position().bpm,
                }
            }
            EnginePhase::Crossfading => {
                // Advance crossfade by num_samples, capture midpoint gains for block
                let mut gain_a = 1.0;
                let mut gain_b = 0.0;
                let mid = num_samples / 2;
                for i in 0..num_samples {
                    let (ga, gb) = self.crossfade.next_gains();
                    if i == mid {
                        gain_a = ga;
                        gain_b = gb;
                    }
                }

                if self.crossfade.state() == CrossfadeState::Complete {
                    self.complete_transition();
                }

                VoiceGains {
                    voice_a_stretch: self.voice_a.stretch_factor,
                    voice_a_gain: gain_a,
                    voice_b_stretch: self.voice_b.stretch_factor,
                    voice_b_gain: gain_b,
                    bpm: self.beat_grid.position().bpm,
                }
            }
        }
    }

    /// Process a full block with per-sample crossfade gains
    ///
    /// Applies crossfade to pre-stretched stereo buffers and writes to output.
    ///
    /// # Arguments
    /// * `voice_a_l/r` - Pre-stretched audio from voice A
    /// * `voice_b_l/r` - Pre-stretched audio from voice B
    /// * `output_l/r` - Output buffers
    pub fn process_crossfade(
        &mut self,
        voice_a_l: &[f64],
        voice_a_r: &[f64],
        voice_b_l: &[f64],
        voice_b_r: &[f64],
        output_l: &mut [f64],
        output_r: &mut [f64],
    ) {
        match self.phase {
            EnginePhase::Steady => {
                // Copy voice A directly
                let len = voice_a_l.len().min(output_l.len());
                output_l[..len].copy_from_slice(&voice_a_l[..len]);
                output_r[..len].copy_from_slice(&voice_a_r[..len]);
            }
            EnginePhase::WaitingForSync => {
                // Still voice A only
                let len = voice_a_l.len().min(output_l.len());
                output_l[..len].copy_from_slice(&voice_a_l[..len]);
                output_r[..len].copy_from_slice(&voice_a_r[..len]);
            }
            EnginePhase::Crossfading => {
                self.crossfade.process_block(
                    voice_a_l, voice_a_r,
                    voice_b_l, voice_b_r,
                    output_l, output_r,
                );

                if self.crossfade.state() == CrossfadeState::Complete {
                    self.complete_transition();
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Queries (any thread)
    // ─────────────────────────────────────────────────────────────────────────

    /// Get current BPM (atomic, safe from any thread)
    pub fn current_bpm(&self) -> f64 {
        self.beat_grid.current_bpm_atomic()
    }

    /// Get current beat position
    pub fn beat_position(&self) -> rf_dsp::beat_grid::BeatPosition {
        self.beat_grid.position()
    }

    /// Get current engine phase
    pub fn phase(&self) -> EnginePhase {
        self.phase
    }

    /// Get current state name
    pub fn current_state_name(&self) -> Option<&str> {
        self.states.get(&self.current_state_id).map(|s| s.name.as_str())
    }

    /// Get stretch factor for voice A
    pub fn voice_a_stretch(&self) -> f64 {
        self.voice_a.stretch_factor
    }

    /// Get stretch factor for voice B (only valid during crossfade)
    pub fn voice_b_stretch(&self) -> f64 {
        self.voice_b.stretch_factor
    }

    /// Is a transition in progress?
    pub fn is_transitioning(&self) -> bool {
        self.phase != EnginePhase::Steady
    }

    /// Get crossfade progress (0.0-1.0, only meaningful during crossfade)
    pub fn crossfade_progress(&self) -> f64 {
        self.crossfade.progress()
    }

    /// Reset engine to initial state
    pub fn reset(&mut self) {
        self.phase = EnginePhase::Steady;
        self.beat_grid.reset();
        self.crossfade.reset();
        self.voice_a.active = true;
        self.voice_b.active = false;
        self.pending_state_id.store(0, Ordering::Release);
        self.target_state_id = 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal state machine
    // ─────────────────────────────────────────────────────────────────────────

    /// Begin a transition to the target state
    fn begin_transition(&mut self, target_id: TempoStateId) {
        // Clear pending
        self.pending_state_id.store(0, Ordering::Release);

        // Look up target state
        let target_state = match self.states.get(&target_id) {
            Some(s) => s.clone(),
            None => return,
        };

        self.target_state_id = target_id;

        // Find matching transition rule
        let rule = self.rules
            .get(&(self.current_state_id, target_id))
            .or_else(|| self.rules.get(&(0, target_id))) // wildcard source
            .unwrap_or(&self.default_rule)
            .clone();

        // Prepare voice B with new stretch factor
        self.voice_b.stretch_factor = self.source_bpm / target_state.target_bpm;
        self.voice_b.active = true;

        // Set crossfade curve
        self.crossfade.set_curve(rule.fade_curve);

        if rule.sync_mode == SyncMode::Immediate {
            // Start crossfade immediately
            self.start_crossfade_with_rule(&rule, &target_state);
        } else {
            // Request sync point and wait
            self.beat_grid.request_sync(rule.sync_mode);
            self.phase = EnginePhase::WaitingForSync;
        }
    }

    /// Start the actual crossfade (called when sync point is hit)
    fn start_crossfade(&mut self) {
        let target_state = match self.states.get(&self.target_state_id) {
            Some(s) => s.clone(),
            None => {
                self.phase = EnginePhase::Steady;
                return;
            }
        };

        let rule = self.rules
            .get(&(self.current_state_id, self.target_state_id))
            .or_else(|| self.rules.get(&(0, self.target_state_id)))
            .unwrap_or(&self.default_rule)
            .clone();

        self.start_crossfade_with_rule(&rule, &target_state);
    }

    fn start_crossfade_with_rule(&mut self, rule: &TempoTransitionRule, target_state: &TempoState) {
        // Calculate crossfade duration in samples
        let beats_per_bar = self.beat_grid.position().bpm; // current BPM for timing
        let _ = beats_per_bar; // timing is based on current tempo
        let current_bpm = self.beat_grid.position().bpm;
        let beats_in_crossfade = rule.duration_bars as f64 * 4.0; // assuming 4/4
        let crossfade_seconds = beats_in_crossfade * 60.0 / current_bpm;
        let crossfade_samples = (crossfade_seconds * self.sample_rate) as u64;

        // Start crossfade
        self.crossfade.reset();
        self.crossfade.start(crossfade_samples);

        // Start tempo ramp if not instant
        self.beat_grid.start_ramp(
            target_state.target_bpm,
            rule.duration_bars,
            rule.ramp_type,
        );

        self.beat_grid.clear_sync();
        self.phase = EnginePhase::Crossfading;
    }

    /// Complete the transition — swap voices
    fn complete_transition(&mut self) {
        // Voice B becomes the new Voice A
        self.voice_a.stretch_factor = self.voice_b.stretch_factor;
        self.voice_a.active = true;
        self.voice_b.active = false;

        self.current_state_id = self.target_state_id;
        self.target_state_id = 0;

        self.crossfade.reset();
        self.phase = EnginePhase::Steady;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VOICE GAINS (returned per-block)
// ═══════════════════════════════════════════════════════════════════════════════

/// Per-block voice gain information
///
/// Used by the caller to apply time-stretching and mixing externally.
#[derive(Debug, Clone, Copy)]
pub struct VoiceGains {
    /// Time-stretch factor for voice A (source_bpm / current_bpm)
    pub voice_a_stretch: f64,
    /// Gain for voice A (0.0-1.0)
    pub voice_a_gain: f64,
    /// Time-stretch factor for voice B
    pub voice_b_stretch: f64,
    /// Gain for voice B (0.0-1.0)
    pub voice_b_gain: f64,
    /// Current BPM
    pub bpm: f64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    const SR: f64 = 44100.0;

    fn setup_engine() -> TempoStateEngine {
        let mut engine = TempoStateEngine::new(120.0, 4, SR);

        engine.add_state("base_game", 100.0);
        engine.add_state("free_spins", 130.0);
        engine.add_state("bonus", 160.0);

        engine.set_initial_state("base_game");
        engine
    }

    #[test]
    fn test_initial_state() {
        let engine = setup_engine();

        assert_eq!(engine.phase(), EnginePhase::Steady);
        assert_eq!(engine.current_state_name(), Some("base_game"));
        assert!((engine.current_bpm() - 100.0).abs() < 0.1);
        // source=120, target=100 → stretch = 120/100 = 1.2
        assert!((engine.voice_a_stretch() - 1.2).abs() < 0.01);
    }

    #[test]
    fn test_trigger_state_immediate() {
        let mut engine = setup_engine();

        // Set rule: base_game → free_spins, immediate
        engine.set_transition_rule(TempoTransitionRule {
            from_state: *engine.name_to_id.get("base_game").unwrap(),
            to_state: *engine.name_to_id.get("free_spins").unwrap(),
            sync_mode: SyncMode::Immediate,
            duration_bars: 2,
            ramp_type: TempoRampType::Linear,
            fade_curve: FadeCurve::EqualPower,
        });

        engine.trigger_state("free_spins");

        // Process one block — should immediately start crossfading
        let gains = engine.process(256);
        assert_eq!(engine.phase(), EnginePhase::Crossfading);
        assert!(gains.voice_b_gain >= 0.0);
    }

    #[test]
    fn test_trigger_state_bar_sync() {
        let mut engine = setup_engine();

        let from_id = *engine.name_to_id.get("base_game").unwrap();
        let to_id = *engine.name_to_id.get("free_spins").unwrap();

        engine.set_transition_rule(TempoTransitionRule {
            from_state: from_id,
            to_state: to_id,
            sync_mode: SyncMode::Bar,
            duration_bars: 1,
            ramp_type: TempoRampType::Linear,
            fade_curve: FadeCurve::EqualPower,
        });

        engine.trigger_state("free_spins");

        // Process first block — should be waiting for sync
        engine.process(256);
        assert_eq!(engine.phase(), EnginePhase::WaitingForSync);

        // Process until bar boundary (4 beats at 100 BPM = 2.4s = 105840 samples)
        let mut total = 256usize;
        while engine.phase() == EnginePhase::WaitingForSync && total < 120000 {
            engine.process(256);
            total += 256;
        }

        assert_eq!(engine.phase(), EnginePhase::Crossfading,
            "Should be crossfading after bar boundary (processed {} samples)", total);
    }

    #[test]
    fn test_full_transition() {
        let mut engine = setup_engine();

        // Immediate transition with 0.1s crossfade (very short for testing)
        engine.set_default_rule(TempoTransitionRule {
            sync_mode: SyncMode::Immediate,
            duration_bars: 1,
            ramp_type: TempoRampType::Linear,
            fade_curve: FadeCurve::Linear,
            ..Default::default()
        });

        engine.trigger_state("free_spins");

        // Process enough blocks to complete transition
        for _ in 0..1000 {
            engine.process(256);
            if engine.phase() == EnginePhase::Steady && engine.current_state_name() == Some("free_spins") {
                break;
            }
        }

        assert_eq!(engine.current_state_name(), Some("free_spins"));
        assert_eq!(engine.phase(), EnginePhase::Steady);
        // source=120, target=130 → stretch = 120/130 ≈ 0.923
        assert!((engine.voice_a_stretch() - 0.923).abs() < 0.01,
            "Expected stretch ~0.923, got {}", engine.voice_a_stretch());
    }

    #[test]
    fn test_voice_gains_steady() {
        let mut engine = setup_engine();
        let gains = engine.process(256);

        assert!((gains.voice_a_gain - 1.0).abs() < 0.001);
        assert!(gains.voice_b_gain.abs() < 0.001);
    }

    #[test]
    fn test_chained_transitions() {
        let mut engine = setup_engine();

        engine.set_default_rule(TempoTransitionRule {
            sync_mode: SyncMode::Immediate,
            duration_bars: 1,
            fade_curve: FadeCurve::Linear,
            ramp_type: TempoRampType::Linear,
            ..Default::default()
        });

        // First: base_game → free_spins
        engine.trigger_state("free_spins");
        for _ in 0..1000 {
            engine.process(256);
            if engine.phase() == EnginePhase::Steady { break; }
        }
        assert_eq!(engine.current_state_name(), Some("free_spins"));

        // Second: free_spins → bonus
        engine.trigger_state("bonus");
        for _ in 0..1000 {
            engine.process(256);
            if engine.phase() == EnginePhase::Steady { break; }
        }
        assert_eq!(engine.current_state_name(), Some("bonus"));
        // source=120, target=160 → stretch = 0.75
        assert!((engine.voice_a_stretch() - 0.75).abs() < 0.01);
    }

    #[test]
    fn test_reset() {
        let mut engine = setup_engine();

        engine.trigger_state("free_spins");
        engine.process(256);

        engine.reset();

        assert_eq!(engine.phase(), EnginePhase::Steady);
        assert!(!engine.is_transitioning());
    }
}
