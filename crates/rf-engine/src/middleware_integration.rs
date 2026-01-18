//! Middleware Integration - Connect Event System to Audio Engine
//!
//! This module bridges rf-event's EventManagerProcessor with the Mixer system.
//! It processes executed actions and converts them to mixer commands.
//!
//! ## Architecture
//!
//! ```text
//! UI Thread                    Audio Thread
//! ─────────                    ────────────
//! EventManagerHandle  ──────>  EventManagerProcessor
//!     (post_event)      │           │
//!                       │      process()
//!                       │           │
//!                       │           v
//!                       │    Vec<ExecutedAction>
//!                       │           │
//!                       │      ActionExecutor
//!                       │           │
//!                       v           v
//!                      Mixer ←── MixerCommand
//! ```

use std::collections::HashMap;
use std::sync::Arc;

use parking_lot::RwLock;
use rtrb::Producer;

use rf_event::manager::{EventManagerHandle, EventManagerProcessor, ExecutedAction, create_event_manager};
use rf_event::action::ActionPriority;

use crate::mixer::{ChannelId, MixerCommand, NUM_CHANNELS};

// ═══════════════════════════════════════════════════════════════════════════════
// ASSET REGISTRY
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio asset entry (loaded sound)
#[derive(Debug, Clone)]
pub struct AudioAsset {
    /// Unique asset ID
    pub id: u32,
    /// Asset name
    pub name: String,
    /// Sample data left channel
    pub samples_l: Arc<Vec<f64>>,
    /// Sample data right channel
    pub samples_r: Arc<Vec<f64>>,
    /// Sample rate of the asset
    pub sample_rate: u32,
    /// Duration in samples
    pub duration_samples: u64,
}

/// Registry of loaded audio assets
pub struct AssetRegistry {
    assets: RwLock<HashMap<u32, AudioAsset>>,
    next_id: std::sync::atomic::AtomicU32,
}

impl AssetRegistry {
    pub fn new() -> Self {
        Self {
            assets: RwLock::new(HashMap::new()),
            next_id: std::sync::atomic::AtomicU32::new(1),
        }
    }

    /// Register an audio asset
    pub fn register(&self, name: &str, samples_l: Vec<f64>, samples_r: Vec<f64>, sample_rate: u32) -> u32 {
        let id = self.next_id.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let duration = samples_l.len() as u64;

        let asset = AudioAsset {
            id,
            name: name.to_string(),
            samples_l: Arc::new(samples_l),
            samples_r: Arc::new(samples_r),
            sample_rate,
            duration_samples: duration,
        };

        self.assets.write().insert(id, asset);
        id
    }

    /// Get asset by ID
    pub fn get(&self, id: u32) -> Option<AudioAsset> {
        self.assets.read().get(&id).cloned()
    }

    /// Unregister asset
    pub fn unregister(&self, id: u32) {
        self.assets.write().remove(&id);
    }
}

impl Default for AssetRegistry {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLAYING VOICE
// ═══════════════════════════════════════════════════════════════════════════════

/// A currently playing audio voice
#[derive(Debug)]
struct PlayingVoice {
    /// Unique playing ID
    playing_id: u64,
    /// Asset being played
    asset: AudioAsset,
    /// Current playback position (in samples)
    position: u64,
    /// Target bus/channel
    bus_id: u32,
    /// Current gain (linear)
    gain: f32,
    /// Target gain for fading
    target_gain: f32,
    /// Fade increment per sample
    fade_increment: f32,
    /// Loop playback
    looping: bool,
    /// Priority for voice stealing
    priority: ActionPriority,
    /// Is stopping (fade out)
    stopping: bool,
    /// Is finished (ready for removal)
    finished: bool,
}

impl PlayingVoice {
    fn new(
        playing_id: u64,
        asset: AudioAsset,
        bus_id: u32,
        gain: f32,
        looping: bool,
        fade_in_frames: u64,
        priority: ActionPriority,
    ) -> Self {
        let (current_gain, fade_increment) = if fade_in_frames > 0 {
            (0.0, gain / fade_in_frames as f32)
        } else {
            (gain, 0.0)
        };

        Self {
            playing_id,
            asset,
            position: 0,
            bus_id,
            gain: current_gain,
            target_gain: gain,
            fade_increment,
            looping,
            priority,
            stopping: false,
            finished: false,
        }
    }

    /// Start fade-out to stop
    fn start_stop(&mut self, fade_frames: u64) {
        self.stopping = true;
        self.target_gain = 0.0;
        self.fade_increment = if fade_frames > 0 {
            -self.gain / fade_frames as f32
        } else {
            -1.0 // Immediate stop
        };
    }

    /// Fill output buffers with audio
    fn fill(&mut self, left: &mut [f64], right: &mut [f64]) {
        let samples_l = &self.asset.samples_l;
        let samples_r = &self.asset.samples_r;
        let len = samples_l.len() as u64;

        for i in 0..left.len() {
            // Update gain (fade in/out)
            if self.fade_increment != 0.0 {
                self.gain += self.fade_increment;
                if self.fade_increment > 0.0 && self.gain >= self.target_gain {
                    self.gain = self.target_gain;
                    self.fade_increment = 0.0;
                } else if self.fade_increment < 0.0 && self.gain <= 0.0 {
                    self.gain = 0.0;
                    self.fade_increment = 0.0;
                    if self.stopping {
                        self.finished = true;
                        return;
                    }
                }
            }

            // Get sample
            if self.position < len {
                let sample_l = samples_l[self.position as usize] * self.gain as f64;
                let sample_r = if self.position < samples_r.len() as u64 {
                    samples_r[self.position as usize] * self.gain as f64
                } else {
                    sample_l
                };

                left[i] += sample_l;
                right[i] += sample_r;

                self.position += 1;
            } else if self.looping {
                self.position = 0;
                // Don't break - continue filling
                if len > 0 {
                    let sample_l = samples_l[0] * self.gain as f64;
                    let sample_r = if !samples_r.is_empty() {
                        samples_r[0] * self.gain as f64
                    } else {
                        sample_l
                    };
                    left[i] += sample_l;
                    right[i] += sample_r;
                    self.position = 1;
                }
            } else {
                // End of non-looping sound
                self.finished = true;
                return;
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BUS ID MAPPING
// ═══════════════════════════════════════════════════════════════════════════════

/// Map middleware bus ID to mixer ChannelId
fn bus_id_to_channel(bus_id: u32) -> Option<ChannelId> {
    // Standard bus ID mapping:
    // 0 = Master (skip - goes through all channels)
    // 1 = Music
    // 2 = SFX (maps to Fx)
    // 3 = Voice (maps to Vo)
    // 4 = UI
    // 5 = Ambience
    // 6 = Reels (slot-specific)
    // 7 = Wins (maps to Fx for now)
    match bus_id {
        1 => Some(ChannelId::Music),
        2 | 7 => Some(ChannelId::Fx),
        3 => Some(ChannelId::Vo),
        4 => Some(ChannelId::Ui),
        5 => Some(ChannelId::Ambient),
        6 => Some(ChannelId::Reels),
        _ => Some(ChannelId::Fx), // Default to FX
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ACTION EXECUTOR
// ═══════════════════════════════════════════════════════════════════════════════

/// Maximum concurrent voices
const MAX_VOICES: usize = 64;

/// Executes middleware actions and manages playing voices
pub struct ActionExecutor {
    /// Asset registry reference
    assets: Arc<AssetRegistry>,
    /// Currently playing voices
    voices: Vec<PlayingVoice>,
    /// Channel output buffers (per bus)
    channel_buffers: Vec<(Vec<f64>, Vec<f64>)>,
    /// Mixer command producer
    mixer_tx: Producer<MixerCommand>,
    /// Sample rate (reserved for future pitch/time-stretch features)
    #[allow(dead_code)]
    sample_rate: u32,
}

impl ActionExecutor {
    pub fn new(assets: Arc<AssetRegistry>, mixer_tx: Producer<MixerCommand>, sample_rate: u32, block_size: usize) -> Self {
        Self {
            assets,
            voices: Vec::with_capacity(MAX_VOICES),
            channel_buffers: (0..NUM_CHANNELS)
                .map(|_| (vec![0.0; block_size], vec![0.0; block_size]))
                .collect(),
            mixer_tx,
            sample_rate,
        }
    }

    /// Execute a list of actions from EventManagerProcessor
    pub fn execute(&mut self, actions: Vec<ExecutedAction>) {
        for action in actions {
            match action {
                ExecutedAction::Play {
                    playing_id,
                    asset_id,
                    bus_id,
                    gain,
                    loop_playback,
                    fade_in_frames,
                    priority,
                } => {
                    self.execute_play(
                        playing_id,
                        asset_id,
                        bus_id,
                        gain,
                        loop_playback,
                        fade_in_frames,
                        priority,
                    );
                }
                ExecutedAction::Stop {
                    playing_id,
                    asset_id: _,
                    fade_out_frames,
                } => {
                    self.execute_stop(playing_id, fade_out_frames);
                }
                ExecutedAction::StopAll {
                    game_object: _,
                    fade_out_frames,
                } => {
                    self.execute_stop_all(fade_out_frames);
                }
                ExecutedAction::SetVolume { bus_id, volume, fade_frames: _ } => {
                    self.execute_set_volume(bus_id, volume);
                }
                ExecutedAction::SetBusVolume { bus_id, volume, fade_frames: _ } => {
                    self.execute_set_volume(bus_id, volume);
                }
                ExecutedAction::SetState { .. } |
                ExecutedAction::SetSwitch { .. } |
                ExecutedAction::SetRtpc { .. } |
                ExecutedAction::PostEvent { .. } |
                ExecutedAction::EventPosted { .. } |
                ExecutedAction::Other { .. } => {
                    // These are handled by EventManagerProcessor internally
                    // or don't directly affect audio output
                }
            }
        }
    }

    fn execute_play(
        &mut self,
        playing_id: u64,
        asset_id: u32,
        bus_id: u32,
        gain: f32,
        loop_playback: bool,
        fade_in_frames: u64,
        priority: ActionPriority,
    ) {
        // Get asset
        let asset = match self.assets.get(asset_id) {
            Some(a) => a,
            None => {
                log::warn!("[ActionExecutor] Asset {} not found", asset_id);
                return;
            }
        };

        // Voice stealing if at capacity
        if self.voices.len() >= MAX_VOICES {
            // Find lowest priority voice
            if let Some(idx) = self.voices.iter().position(|v| v.priority < priority) {
                self.voices[idx].start_stop(0);
            } else {
                log::warn!("[ActionExecutor] Voice limit reached, dropping play");
                return;
            }
        }

        // Create new voice
        let voice = PlayingVoice::new(
            playing_id,
            asset,
            bus_id,
            gain,
            loop_playback,
            fade_in_frames,
            priority,
        );

        self.voices.push(voice);
        log::debug!("[ActionExecutor] Playing asset {} on bus {} (playing_id: {})", asset_id, bus_id, playing_id);
    }

    fn execute_stop(&mut self, playing_id: u64, fade_frames: u64) {
        if let Some(voice) = self.voices.iter_mut().find(|v| v.playing_id == playing_id) {
            voice.start_stop(fade_frames);
        }
    }

    fn execute_stop_all(&mut self, fade_frames: u64) {
        for voice in &mut self.voices {
            voice.start_stop(fade_frames);
        }
    }

    fn execute_set_volume(&mut self, bus_id: u32, volume: f32) {
        if let Some(channel_id) = bus_id_to_channel(bus_id) {
            // Convert linear to dB
            let db = if volume <= 0.0 {
                -120.0
            } else {
                20.0 * (volume as f64).log10()
            };
            let _ = self.mixer_tx.push(MixerCommand::SetChannelVolume(channel_id, db));
        }
    }

    /// Process all voices and fill channel buffers
    pub fn process(&mut self, num_frames: usize) {
        // Clear channel buffers
        for (left, right) in &mut self.channel_buffers {
            left[..num_frames].fill(0.0);
            right[..num_frames].fill(0.0);
        }

        // Process each voice
        for voice in &mut self.voices {
            if voice.finished {
                continue;
            }

            // Get channel for this bus
            if let Some(channel_id) = bus_id_to_channel(voice.bus_id) {
                let idx = channel_id.index();
                if idx < self.channel_buffers.len() {
                    let (left, right) = &mut self.channel_buffers[idx];
                    voice.fill(&mut left[..num_frames], &mut right[..num_frames]);
                }
            }
        }

        // Remove finished voices
        self.voices.retain(|v| !v.finished);
    }

    /// Get output buffer for a channel
    pub fn get_channel_output(&self, channel_id: ChannelId) -> (&[f64], &[f64]) {
        let idx = channel_id.index();
        let (left, right) = &self.channel_buffers[idx];
        (left, right)
    }

    /// Get number of active voices
    pub fn active_voice_count(&self) -> usize {
        self.voices.iter().filter(|v| !v.finished).count()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDDLEWARE AUDIO ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete middleware audio engine
///
/// Integrates EventManager with ActionExecutor for full middleware support.
pub struct MiddlewareAudioEngine {
    /// Event manager handle (for UI thread)
    pub handle: EventManagerHandle,
    /// Event processor (audio thread only)
    processor: EventManagerProcessor,
    /// Action executor
    executor: ActionExecutor,
    /// Sample rate (reserved for future sample-rate dependent processing)
    #[allow(dead_code)]
    sample_rate: u32,
}

impl MiddlewareAudioEngine {
    /// Create a new middleware audio engine
    pub fn new(
        assets: Arc<AssetRegistry>,
        mixer_tx: Producer<MixerCommand>,
        sample_rate: u32,
        block_size: usize,
    ) -> Self {
        let (handle, processor) = create_event_manager(sample_rate);
        let executor = ActionExecutor::new(assets, mixer_tx, sample_rate, block_size);

        Self {
            handle,
            processor,
            executor,
            sample_rate,
        }
    }

    /// Process one audio block
    ///
    /// Call this from the audio callback BEFORE mixing.
    /// Returns channel outputs that should be added to mixer.
    pub fn process(&mut self, num_frames: usize) {
        // 1. Process event commands and get executed actions
        let actions = self.processor.process(num_frames as u64);

        // 2. Execute actions (start/stop sounds, set volumes)
        self.executor.execute(actions);

        // 3. Process voices and fill channel buffers
        self.executor.process(num_frames);
    }

    /// Get output for a channel (call after process)
    pub fn get_channel_output(&self, channel_id: ChannelId) -> (&[f64], &[f64]) {
        self.executor.get_channel_output(channel_id)
    }

    /// Get handle for UI thread
    pub fn handle(&self) -> &EventManagerHandle {
        &self.handle
    }

    /// Get active voice count
    pub fn active_voice_count(&self) -> usize {
        self.executor.active_voice_count()
    }

    /// Get active event instance count
    pub fn active_instance_count(&self) -> usize {
        self.processor.active_instance_count()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use rtrb::RingBuffer;

    #[test]
    fn test_asset_registry() {
        let registry = AssetRegistry::new();

        let samples = vec![0.1, 0.2, 0.3];
        let id = registry.register("test", samples.clone(), samples.clone(), 48000);

        assert!(id > 0);

        let asset = registry.get(id).unwrap();
        assert_eq!(asset.name, "test");
        assert_eq!(asset.samples_l.len(), 3);
    }

    #[test]
    fn test_bus_id_mapping() {
        assert_eq!(bus_id_to_channel(1), Some(ChannelId::Music));
        assert_eq!(bus_id_to_channel(2), Some(ChannelId::Fx));
        assert_eq!(bus_id_to_channel(3), Some(ChannelId::Vo));
        assert_eq!(bus_id_to_channel(4), Some(ChannelId::Ui));
    }

    #[test]
    fn test_action_executor() {
        let assets = Arc::new(AssetRegistry::new());
        let (tx, _rx) = RingBuffer::new(1024);

        let mut executor = ActionExecutor::new(assets.clone(), tx, 48000, 256);

        // Register test asset
        let samples = vec![0.5; 1000];
        let asset_id = assets.register("test_sound", samples.clone(), samples, 48000);

        // Execute play action
        executor.execute(vec![
            ExecutedAction::Play {
                playing_id: 1,
                asset_id,
                bus_id: 2,
                gain: 1.0,
                loop_playback: false,
                fade_in_frames: 0,
                priority: ActionPriority::Normal,
            }
        ]);

        assert_eq!(executor.active_voice_count(), 1);

        // Process
        executor.process(256);

        // Check output has audio
        let (left, _right) = executor.get_channel_output(ChannelId::Fx);
        assert!(left.iter().any(|&s| s != 0.0));
    }
}
