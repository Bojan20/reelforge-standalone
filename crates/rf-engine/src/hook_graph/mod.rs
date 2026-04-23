//! Hook Graph Engine — Rust audio-rate execution engine for the Dynamic Hook Graph System.
//!
//! Receives commands from Dart (control-rate, ~60Hz) via lock-free ring buffer.
//! Executes audio-rate DSP node graphs on the audio thread.
//! Manages voice allocation, bus routing, and graph instance lifecycle.
//!
//! Architecture:
//! ```text
//!  Dart ControlRateExecutor (~60Hz)
//!      │  GraphCommand (StartVoice, SetParam, etc.)
//!      ▼
//!  rtrb::RingBuffer (lock-free SPSC)
//!      │
//!      ▼
//!  HookGraphEngine (audio thread)
//!      │  Processes commands, updates graph state, renders audio
//!      ▼
//!  PlaybackEngine bus_buffers (mixes into bus system)
//! ```

pub mod audio_node;
pub mod compiled_graph;
pub mod voice_manager;
pub mod instance_pool;
pub mod dsp_nodes;
pub mod containers;
pub mod helix_graph;
pub mod helix_voice;
pub mod helix_compliance;
pub mod helix_predictive;

use std::collections::HashMap;
use std::sync::Arc;

use crate::audio_import::ImportedAudio;
use crate::track_manager::OutputBus;

use self::audio_node::AudioBuffer;
use self::compiled_graph::CompiledAudioGraph;
use self::instance_pool::GraphInstancePool;
use self::voice_manager::{VoiceManager, VoicePriority};

/// Commands sent from Dart control-rate executor to Rust audio-rate engine.
/// Transmitted via rtrb lock-free SPSC ring buffer.
#[repr(u8)]
#[derive(Debug)]
pub enum GraphCommand {
    /// Load a compiled graph into the engine
    LoadGraph {
        graph_id: u32,
        graph: Box<CompiledAudioGraph>,
    },
    /// Unload a graph
    UnloadGraph { graph_id: u32 },
    /// Trigger a graph (start execution)
    TriggerGraph {
        graph_id: u32,
        instance_id: u32,
    },
    /// Stop a graph instance
    StopGraph {
        instance_id: u32,
        fade_ms: u32,
    },
    /// Start a voice within a graph
    StartVoice {
        instance_id: u32,
        audio: Arc<ImportedAudio>,
        volume: f32,
        bus: OutputBus,
        priority: VoicePriority,
    },
    /// Stop a specific voice
    StopVoice {
        voice_id: u64,
        fade_ms: u32,
    },
    /// Set a node parameter
    SetNodeParam {
        instance_id: u32,
        node_id: u32,
        param_name_hash: u32,
        value: f64,
    },
    /// Set RTPC value (global parameter)
    SetRTPC {
        param_id: u32,
        value: f64,
    },
    /// Set bus volume
    SetBusVolume {
        bus: OutputBus,
        volume: f32,
    },
}

/// Feedback from audio engine back to Dart (for metering, state updates)
#[repr(u8)]
#[derive(Debug)]
pub enum GraphFeedback {
    VoiceStarted { voice_id: u64, instance_id: u32 },
    VoiceStopped { voice_id: u64 },
    GraphDone { instance_id: u32 },
    NodeError { instance_id: u32, node_id: u32 },
}

/// The main hook graph audio engine.
/// Owned by PlaybackEngine, processed on the audio thread.
pub struct HookGraphEngine {
    /// Loaded compiled graphs (graph_id → graph)
    graphs: HashMap<u32, CompiledAudioGraph>,
    /// Voice manager (pre-allocated pool)
    voice_manager: VoiceManager,
    /// Graph instance pool
    instance_pool: GraphInstancePool,
    /// RTPC values (param_id → value)
    rtpc_values: HashMap<u32, f64>,
    /// Command ring buffer (Dart → Rust)
    cmd_rx: parking_lot::Mutex<rtrb::Consumer<GraphCommand>>,
    /// Feedback ring buffer (Rust → Dart)
    fb_tx: parking_lot::Mutex<rtrb::Producer<GraphFeedback>>,
    /// Pre-allocated audio buffers for node processing
    _node_buffers: Vec<AudioBuffer>,
    /// Sample rate
    sample_rate: u32,
    /// Active flag
    active: bool,
    /// Per-bus volume overrides from SetBusVolume commands [Master, Music, SFX, Voice, Ambience, Aux]
    bus_volumes: [f32; 6],
}

impl HookGraphEngine {
    pub fn new(
        sample_rate: u32,
        max_block_size: usize,
        cmd_rx: rtrb::Consumer<GraphCommand>,
        fb_tx: rtrb::Producer<GraphFeedback>,
    ) -> Self {
        let _node_buffers = (0..16)
            .map(|_| AudioBuffer::new(max_block_size))
            .collect();

        Self {
            graphs: HashMap::new(),
            voice_manager: VoiceManager::new(),
            instance_pool: GraphInstancePool::new(max_block_size),
            rtpc_values: HashMap::new(),
            cmd_rx: parking_lot::Mutex::new(cmd_rx),
            fb_tx: parking_lot::Mutex::new(fb_tx),
            _node_buffers,
            sample_rate,
            active: true,
            bus_volumes: [1.0; 6],
        }
    }

    /// Process commands and render audio for one block.
    /// Called from PlaybackEngine::process() on the audio thread.
    ///
    /// `bus_buffers` variant: routes each voice to its assigned bus (OutputBus).
    /// This is the primary path — all voices respect bus routing.
    pub fn process_into_buses(
        &mut self,
        bus_buffers: &mut crate::playback::BusBuffers,
        frames: usize,
    ) {
        if !self.active { return; }

        self.drain_commands();
        self.voice_manager.tick();
        self.instance_pool.tick_all();
        self.render_voices_to_buses(bus_buffers, frames);
    }

    /// Legacy: render directly to output (bypasses bus routing).
    /// Kept for backward compat — prefer process_into_buses().
    pub fn process(&mut self, output_l: &mut [f64], output_r: &mut [f64], frames: usize) {
        if !self.active { return; }

        self.drain_commands();
        self.voice_manager.tick();
        self.instance_pool.tick_all();
        self.render_voices(output_l, output_r, frames);
    }

    fn drain_commands(&mut self) {
        let mut rx = match self.cmd_rx.try_lock() {
            Some(rx) => rx,
            None => return,
        };

        while let Ok(cmd) = rx.pop() {
            match cmd {
                GraphCommand::LoadGraph { graph_id, graph } => {
                    self.graphs.insert(graph_id, *graph);
                }
                GraphCommand::UnloadGraph { graph_id } => {
                    self.graphs.remove(&graph_id);
                }
                GraphCommand::TriggerGraph { graph_id, instance_id: _ } => {
                    if let Some(graph) = self.graphs.get(&graph_id) {
                        self.instance_pool.allocate(graph);
                    }
                }
                GraphCommand::StopGraph { instance_id, fade_ms } => {
                    let fade_samples = (self.sample_rate as u64 * fade_ms as u64) / 1000;
                    self.voice_manager.stop_graph_voices(instance_id, fade_samples);
                    self.instance_pool.release(instance_id);
                }
                GraphCommand::StartVoice {
                    instance_id, audio, volume, bus, priority,
                } => {
                    if let Some(voice_id) = self.voice_manager.allocate(
                        audio, volume, bus, priority, instance_id,
                    )
                        && let Some(mut fb) = self.fb_tx.try_lock() {
                            let _ = fb.push(GraphFeedback::VoiceStarted {
                                voice_id,
                                instance_id,
                            });
                        }
                }
                GraphCommand::StopVoice { voice_id, fade_ms } => {
                    let fade_samples = (self.sample_rate as u64 * fade_ms as u64) / 1000;
                    self.voice_manager.stop_voice(voice_id, fade_samples);
                }
                GraphCommand::SetNodeParam {
                    instance_id, node_id, param_name_hash, value,
                } => {
                    // Route to instance → node
                    if let Some(inst) = self.instance_pool.instance_mut(instance_id) {
                        inst.params.insert(format!("{node_id}.{param_name_hash}"), value);
                    }
                }
                GraphCommand::SetRTPC { param_id, value } => {
                    self.rtpc_values.insert(param_id, value);
                }
                GraphCommand::SetBusVolume { bus, volume } => {
                    // Store bus volumes for per-voice rendering gain adjustment.
                    // Primary bus volume/mute/solo is managed by PlaybackEngine bus_states.
                    // This stores a local override for graph-controlled bus volumes.
                    let idx = match bus {
                        OutputBus::Master => 0,
                        OutputBus::Music => 1,
                        OutputBus::Sfx => 2,
                        OutputBus::Voice => 3,
                        OutputBus::Ambience => 4,
                        OutputBus::Aux => 5,
                    };
                    self.bus_volumes[idx] = volume;
                }
            }
        }
    }

    /// Render voices into per-bus buffers (proper bus routing).
    /// Each voice's audio goes to its assigned OutputBus via BusBuffers.
    fn render_voices_to_buses(
        &mut self,
        bus_buffers: &mut crate::playback::BusBuffers,
        frames: usize,
    ) {
        // Use thread-local scratch buffers to avoid audio-thread allocation
        thread_local! {
            static VOICE_SCRATCH_L: std::cell::RefCell<Vec<f64>> = std::cell::RefCell::new(vec![0.0; 8192]);
            static VOICE_SCRATCH_R: std::cell::RefCell<Vec<f64>> = std::cell::RefCell::new(vec![0.0; 8192]);
        }

        let voices = self.voice_manager.voices_mut();

        for voice in voices.iter_mut() {
            if !voice.is_active() { continue; }

            let audio = match &voice.audio {
                Some(a) => a.clone(),
                None => continue,
            };

            let channels = audio.channels as usize;
            let total_frames = audio.samples.len() / channels.max(1);

            if total_frames == 0 || voice.position >= total_frames as u64 {
                if voice.looping {
                    voice.position = 0;
                } else {
                    voice.state = voice_manager::VoiceState::Stopped;
                    continue;
                }
            }

            // Render into scratch buffers, then add_to_bus
            VOICE_SCRATCH_L.with(|buf_l| {
                VOICE_SCRATCH_R.with(|buf_r| {
                    let mut sl = buf_l.borrow_mut();
                    let mut sr = buf_r.borrow_mut();
                    if sl.len() < frames { sl.resize(frames, 0.0); }
                    if sr.len() < frames { sr.resize(frames, 0.0); }
                    sl[..frames].fill(0.0);
                    sr[..frames].fill(0.0);

                    let mut fade = voice.fade_gain;
                    let fade_inc = voice.fade_increment;
                    let vol = voice.volume;

                    for i in 0..frames {
                        let pos = voice.position as usize;
                        if pos >= total_frames {
                            if voice.looping {
                                voice.position = 0;
                                continue;
                            }
                            voice.state = voice_manager::VoiceState::Stopped;
                            break;
                        }

                        if voice.fade_samples_remaining > 0 {
                            fade += fade_inc;
                            voice.fade_samples_remaining -= 1;
                            if fade <= 0.0 {
                                voice.state = voice_manager::VoiceState::Stopped;
                                break;
                            }
                            fade = fade.clamp(0.0, 1.0);
                        }

                        let gain = vol * fade;
                        let sample_l = audio.samples[pos * channels] as f64 * gain as f64;
                        let sample_r = if channels > 1 {
                            audio.samples[pos * channels + 1] as f64 * gain as f64
                        } else {
                            sample_l
                        };

                        sl[i] = sample_l;
                        sr[i] = sample_r;
                        voice.position += 1;
                    }

                    voice.fade_gain = fade;

                    // Route to the voice's assigned bus
                    bus_buffers.add_to_bus(voice.bus, &sl[..frames], &sr[..frames]);
                });
            });
        }
    }

    /// Legacy: render all voices directly to output (no bus routing).
    fn render_voices(&mut self, output_l: &mut [f64], output_r: &mut [f64], frames: usize) {
        let voices = self.voice_manager.voices_mut();

        for voice in voices.iter_mut() {
            if !voice.is_active() { continue; }

            let audio = match &voice.audio {
                Some(a) => a.clone(),
                None => continue,
            };

            let channels = audio.channels as usize;
            let total_frames = audio.samples.len() / channels.max(1);

            if total_frames == 0 || voice.position >= total_frames as u64 {
                if voice.looping {
                    voice.position = 0;
                } else {
                    voice.state = voice_manager::VoiceState::Stopped;
                    continue;
                }
            }

            // Fade processing
            let mut fade = voice.fade_gain;
            let fade_inc = voice.fade_increment;

            let vol = voice.volume;

            for i in 0..frames {
                let pos = voice.position as usize;
                if pos >= total_frames {
                    if voice.looping {
                        voice.position = 0;
                        continue;
                    }
                    voice.state = voice_manager::VoiceState::Stopped;
                    break;
                }

                // Update fade
                if voice.fade_samples_remaining > 0 {
                    fade += fade_inc;
                    voice.fade_samples_remaining -= 1;
                    if fade <= 0.0 {
                        voice.state = voice_manager::VoiceState::Stopped;
                        break;
                    }
                    fade = fade.clamp(0.0, 1.0);
                }

                let gain = vol * fade;

                let sample_l = audio.samples[pos * channels] as f64 * gain as f64;
                let sample_r = if channels > 1 {
                    audio.samples[pos * channels + 1] as f64 * gain as f64
                } else {
                    sample_l
                };

                output_l[i] += sample_l;
                output_r[i] += sample_r;

                voice.position += 1;
            }

            voice.fade_gain = fade;
        }
    }

    pub fn set_sample_rate(&mut self, sr: u32) {
        self.sample_rate = sr;
    }

    pub fn active_voice_count(&self) -> usize {
        self.voice_manager.active_count()
    }

    pub fn loaded_graph_count(&self) -> usize {
        self.graphs.len()
    }

    pub fn active_instance_count(&self) -> usize {
        self.instance_pool.active_count()
    }
}
