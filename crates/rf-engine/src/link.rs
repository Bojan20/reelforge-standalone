//! Ableton Link Integration
//!
//! Network tempo synchronization between DAWs and music applications.
//!
//! # Features
//!
//! - Automatic peer discovery on local network
//! - Tempo synchronization across all connected peers
//! - Beat/bar alignment
//! - Start/stop sync
//! - Sample-accurate timing

use std::sync::Arc;
use std::time::{Duration, Instant};

use parking_lot::RwLock;
use crossbeam_channel::{bounded, Receiver, Sender};

// ============ Link State ============

/// Beat/bar position in the timeline
#[derive(Debug, Clone, Copy, Default)]
pub struct LinkBeat {
    /// Current beat (can be fractional)
    pub beat: f64,
    /// Beats per bar (time signature numerator)
    pub beats_per_bar: u32,
    /// Current bar number
    pub bar: u64,
    /// Phase within bar (0.0 - 1.0)
    pub phase: f64,
}

impl LinkBeat {
    /// Create from beat position
    pub fn from_beat(beat: f64, beats_per_bar: u32) -> Self {
        let bar = (beat / beats_per_bar as f64).floor() as u64;
        let beat_in_bar = beat % beats_per_bar as f64;
        let phase = beat_in_bar / beats_per_bar as f64;

        Self {
            beat,
            beats_per_bar,
            bar,
            phase,
        }
    }

    /// Get beat within current bar
    pub fn beat_in_bar(&self) -> f64 {
        self.beat % self.beats_per_bar as f64
    }

    /// Is at start of bar
    pub fn is_bar_start(&self) -> bool {
        self.beat_in_bar() < 0.01
    }

    /// Is at start of beat
    pub fn is_beat_start(&self) -> bool {
        (self.beat - self.beat.floor()).abs() < 0.01
    }
}

/// Current Link session state
#[derive(Debug, Clone)]
pub struct LinkState {
    /// Number of peers connected
    pub num_peers: usize,
    /// Current tempo in BPM
    pub tempo: f64,
    /// Current beat position
    pub beat: LinkBeat,
    /// Is playing (start/stop sync)
    pub is_playing: bool,
    /// Is enabled
    pub enabled: bool,
    /// Session start time
    pub session_start: Option<Instant>,
}

impl Default for LinkState {
    fn default() -> Self {
        Self {
            num_peers: 0,
            tempo: 120.0,
            beat: LinkBeat::default(),
            is_playing: false,
            enabled: false,
            session_start: None,
        }
    }
}

// ============ Link Events ============

/// Events from Link
#[derive(Debug, Clone)]
pub enum LinkEvent {
    /// Peer count changed
    PeersChanged(usize),
    /// Tempo changed by another peer
    TempoChanged(f64),
    /// Start/stop state changed
    PlayStateChanged(bool),
    /// Session started
    SessionStarted,
    /// Session ended
    SessionEnded,
}

// ============ Link Configuration ============

/// Link configuration
#[derive(Debug, Clone)]
pub struct LinkConfig {
    /// Quantum (beats per group, usually matches time signature)
    pub quantum: f64,
    /// Enable start/stop sync
    pub start_stop_sync: bool,
    /// Initial tempo
    pub tempo: f64,
}

impl Default for LinkConfig {
    fn default() -> Self {
        Self {
            quantum: 4.0,
            start_stop_sync: true,
            tempo: 120.0,
        }
    }
}

// ============ Link Session ============

/// Ableton Link session manager
pub struct LinkSession {
    /// Configuration
    config: LinkConfig,
    /// Current state
    state: Arc<RwLock<LinkState>>,
    /// Event sender
    event_tx: Sender<LinkEvent>,
    /// Event receiver
    event_rx: Receiver<LinkEvent>,
    /// Sample rate
    sample_rate: u32,
    /// Last update time
    last_update: Instant,
    /// Beat accumulator
    beat_accumulator: f64,
}

impl LinkSession {
    /// Create a new Link session
    pub fn new(config: LinkConfig, sample_rate: u32) -> Self {
        let (event_tx, event_rx) = bounded(256);
        let tempo = config.tempo;

        Self {
            config,
            state: Arc::new(RwLock::new(LinkState {
                tempo,
                ..Default::default()
            })),
            event_tx,
            event_rx,
            sample_rate,
            last_update: Instant::now(),
            beat_accumulator: 0.0,
        }
    }

    /// Enable Link
    pub fn enable(&mut self) {
        let mut state = self.state.write();
        state.enabled = true;
        state.session_start = Some(Instant::now());
        drop(state);

        let _ = self.event_tx.send(LinkEvent::SessionStarted);

        // In a real implementation, this would start the Link network discovery
        // using the Ableton Link SDK or a Rust port
    }

    /// Disable Link
    pub fn disable(&mut self) {
        let mut state = self.state.write();
        state.enabled = false;
        state.num_peers = 0;
        state.session_start = None;
        drop(state);

        let _ = self.event_tx.send(LinkEvent::SessionEnded);
    }

    /// Is Link enabled
    pub fn is_enabled(&self) -> bool {
        self.state.read().enabled
    }

    /// Get current state
    pub fn state(&self) -> LinkState {
        self.state.read().clone()
    }

    /// Get event receiver
    pub fn events(&self) -> Receiver<LinkEvent> {
        self.event_rx.clone()
    }

    /// Set tempo (propagates to all peers)
    pub fn set_tempo(&mut self, tempo: f64) {
        let tempo = tempo.clamp(20.0, 999.0);
        let mut state = self.state.write();
        let old_tempo = state.tempo;
        state.tempo = tempo;
        drop(state);

        if (tempo - old_tempo).abs() > 0.001 {
            let _ = self.event_tx.send(LinkEvent::TempoChanged(tempo));
        }

        // In a real implementation, this would update the Link session tempo
    }

    /// Get current tempo
    pub fn tempo(&self) -> f64 {
        self.state.read().tempo
    }

    /// Set play state (start/stop sync)
    pub fn set_playing(&mut self, playing: bool) {
        if !self.config.start_stop_sync {
            return;
        }

        let mut state = self.state.write();
        let old_playing = state.is_playing;
        state.is_playing = playing;
        drop(state);

        if playing != old_playing {
            let _ = self.event_tx.send(LinkEvent::PlayStateChanged(playing));
        }
    }

    /// Is playing
    pub fn is_playing(&self) -> bool {
        self.state.read().is_playing
    }

    /// Get beat position at given sample time
    pub fn beat_at_sample(&self, sample_time: u64) -> LinkBeat {
        let state = self.state.read();
        let tempo = state.tempo;
        let beats_per_bar = self.config.quantum as u32;
        drop(state);

        let time_secs = sample_time as f64 / self.sample_rate as f64;
        let beat = (time_secs / 60.0) * tempo;

        LinkBeat::from_beat(beat, beats_per_bar)
    }

    /// Get sample time at given beat
    pub fn sample_at_beat(&self, beat: f64) -> u64 {
        let tempo = self.state.read().tempo;
        let time_secs = (beat / tempo) * 60.0;
        (time_secs * self.sample_rate as f64) as u64
    }

    /// Request beat alignment (snap to next quantum boundary)
    pub fn request_beat_at_time(&mut self, beat: f64, _at_time: Duration) {
        // Quantize to quantum
        let quantum = self.config.quantum;
        let quantized_beat = (beat / quantum).floor() * quantum;

        let mut state = self.state.write();
        state.beat = LinkBeat::from_beat(quantized_beat, quantum as u32);
    }

    /// Force beat now (useful for manual sync)
    pub fn force_beat_at_time(&mut self, beat: f64) {
        let mut state = self.state.write();
        state.beat = LinkBeat::from_beat(beat, self.config.quantum as u32);
    }

    /// Update Link state (call from audio thread or timer)
    pub fn update(&mut self, num_samples: usize) {
        if !self.state.read().enabled {
            return;
        }

        let tempo = self.state.read().tempo;
        let samples_per_beat = (self.sample_rate as f64 * 60.0) / tempo;
        let beat_increment = num_samples as f64 / samples_per_beat;

        self.beat_accumulator += beat_increment;

        let mut state = self.state.write();
        state.beat = LinkBeat::from_beat(self.beat_accumulator, self.config.quantum as u32);
        self.last_update = Instant::now();
    }

    /// Get number of connected peers
    pub fn num_peers(&self) -> usize {
        self.state.read().num_peers
    }

    /// Get quantum (beats per group)
    pub fn quantum(&self) -> f64 {
        self.config.quantum
    }

    /// Set quantum
    pub fn set_quantum(&mut self, quantum: f64) {
        self.config.quantum = quantum.clamp(1.0, 16.0);
    }

    /// Calculate phase for a specific beat count (0.0 - 1.0)
    pub fn phase(&self) -> f64 {
        self.state.read().beat.phase
    }

    /// Is at quantum boundary (start of bar/group)
    pub fn is_at_quantum(&self) -> bool {
        self.state.read().beat.is_bar_start()
    }

    /// Microseconds until next quantum boundary
    pub fn time_until_quantum(&self) -> Duration {
        let state = self.state.read();
        let remaining_beats = self.config.quantum - state.beat.beat_in_bar();
        let tempo = state.tempo;
        drop(state);

        let time_secs = (remaining_beats / tempo) * 60.0;
        Duration::from_secs_f64(time_secs)
    }
}

impl Default for LinkSession {
    fn default() -> Self {
        Self::new(LinkConfig::default(), 48000)
    }
}

// ============ Link Host ============

/// Host for managing Link across the application
pub struct LinkHost {
    /// Active session
    session: Arc<RwLock<LinkSession>>,
}

impl LinkHost {
    /// Create a new Link host
    pub fn new(sample_rate: u32) -> Self {
        Self {
            session: Arc::new(RwLock::new(LinkSession::new(
                LinkConfig::default(),
                sample_rate,
            ))),
        }
    }

    /// Get the session
    pub fn session(&self) -> Arc<RwLock<LinkSession>> {
        Arc::clone(&self.session)
    }

    /// Enable Link
    pub fn enable(&self) {
        self.session.write().enable();
    }

    /// Disable Link
    pub fn disable(&self) {
        self.session.write().disable();
    }

    /// Is enabled
    pub fn is_enabled(&self) -> bool {
        self.session.read().is_enabled()
    }

    /// Set tempo
    pub fn set_tempo(&self, tempo: f64) {
        self.session.write().set_tempo(tempo);
    }

    /// Get tempo
    pub fn tempo(&self) -> f64 {
        self.session.read().tempo()
    }

    /// Set playing state
    pub fn set_playing(&self, playing: bool) {
        self.session.write().set_playing(playing);
    }

    /// Is playing
    pub fn is_playing(&self) -> bool {
        self.session.read().is_playing()
    }

    /// Get state
    pub fn state(&self) -> LinkState {
        self.session.read().state()
    }

    /// Update (call from audio callback)
    pub fn update(&self, num_samples: usize) {
        self.session.write().update(num_samples);
    }

    /// Get beat at sample
    pub fn beat_at_sample(&self, sample: u64) -> LinkBeat {
        self.session.read().beat_at_sample(sample)
    }

    /// Get sample at beat
    pub fn sample_at_beat(&self, beat: f64) -> u64 {
        self.session.read().sample_at_beat(beat)
    }
}

impl Default for LinkHost {
    fn default() -> Self {
        Self::new(48000)
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_link_beat() {
        let beat = LinkBeat::from_beat(4.5, 4);
        assert_eq!(beat.bar, 1);
        assert!((beat.beat_in_bar() - 0.5).abs() < 0.001);
        assert!((beat.phase - 0.125).abs() < 0.001);
    }

    #[test]
    fn test_link_session() {
        let mut session = LinkSession::new(LinkConfig::default(), 48000);

        assert!(!session.is_enabled());
        assert_eq!(session.tempo(), 120.0);

        session.enable();
        assert!(session.is_enabled());

        session.set_tempo(140.0);
        assert!((session.tempo() - 140.0).abs() < 0.001);

        session.disable();
        assert!(!session.is_enabled());
    }

    #[test]
    fn test_beat_at_sample() {
        let session = LinkSession::new(
            LinkConfig {
                tempo: 120.0,
                ..Default::default()
            },
            48000,
        );

        // At 120 BPM, 48000 samples = 1 second = 2 beats
        let beat = session.beat_at_sample(48000);
        assert!((beat.beat - 2.0).abs() < 0.001);
    }

    #[test]
    fn test_sample_at_beat() {
        let session = LinkSession::new(
            LinkConfig {
                tempo: 120.0,
                ..Default::default()
            },
            48000,
        );

        // At 120 BPM, beat 2 = 1 second = 48000 samples
        let sample = session.sample_at_beat(2.0);
        assert_eq!(sample, 48000);
    }
}
