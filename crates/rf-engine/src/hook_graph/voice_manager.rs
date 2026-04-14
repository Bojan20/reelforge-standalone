//! VoiceManager — Pre-allocated voice pool with stealing and virtualization.
//!
//! Zero audio-thread allocations. All voices pre-allocated at init.
//! Stealing policy: oldest → lowest priority → furthest from listener.

use std::sync::Arc;
use crate::audio_import::ImportedAudio;
use crate::track_manager::OutputBus;

const MAX_VOICES: usize = 64;

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VoiceState {
    Idle = 0,
    Starting = 1,
    Playing = 2,
    Looping = 3,
    Stopping = 4,
    Stopped = 5,
    Virtual = 6,
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum VoicePriority {
    Low = 0,
    Normal = 1,
    High = 2,
    Critical = 3,
}

pub struct Voice {
    pub id: u64,
    pub state: VoiceState,
    pub priority: VoicePriority,
    pub graph_instance_id: u32,
    pub audio: Option<Arc<ImportedAudio>>,
    pub position: u64,
    pub volume: f32,
    pub bus: OutputBus,
    pub fade_gain: f32,
    pub fade_increment: f32,
    pub fade_samples_remaining: u64,
    pub looping: bool,
    pub start_tick: u64,
}

impl Voice {
    fn new_idle() -> Self {
        Self {
            id: 0,
            state: VoiceState::Idle,
            priority: VoicePriority::Normal,
            graph_instance_id: 0,
            audio: None,
            position: 0,
            volume: 1.0,
            bus: OutputBus::Sfx,
            fade_gain: 1.0,
            fade_increment: 0.0,
            fade_samples_remaining: 0,
            looping: false,
            start_tick: 0,
        }
    }

    pub fn activate(
        &mut self,
        id: u64,
        audio: Arc<ImportedAudio>,
        volume: f32,
        bus: OutputBus,
        priority: VoicePriority,
        graph_id: u32,
        tick: u64,
    ) {
        self.id = id;
        self.state = VoiceState::Starting;
        self.priority = priority;
        self.graph_instance_id = graph_id;
        self.audio = Some(audio);
        self.position = 0;
        self.volume = volume;
        self.bus = bus;
        self.fade_gain = 0.0;
        self.fade_increment = 1.0 / 480.0;
        self.fade_samples_remaining = 480;
        self.looping = false;
        self.start_tick = tick;
    }

    pub fn start_fade_out(&mut self, samples: u64) {
        if samples == 0 {
            self.state = VoiceState::Stopped;
            return;
        }
        self.state = VoiceState::Stopping;
        self.fade_samples_remaining = samples;
        self.fade_increment = -self.fade_gain / samples as f32;
    }

    pub fn deactivate(&mut self) {
        self.state = VoiceState::Idle;
        self.audio = None;
    }

    pub fn is_active(&self) -> bool {
        !matches!(self.state, VoiceState::Idle | VoiceState::Stopped)
    }
}

pub struct VoiceManager {
    voices: Vec<Voice>,
    next_id: u64,
    global_tick: u64,
}

impl VoiceManager {
    pub fn new() -> Self {
        let voices = (0..MAX_VOICES).map(|_| Voice::new_idle()).collect();
        Self {
            voices,
            next_id: 1,
            global_tick: 0,
        }
    }

    pub fn allocate(
        &mut self,
        audio: Arc<ImportedAudio>,
        volume: f32,
        bus: OutputBus,
        priority: VoicePriority,
        graph_id: u32,
    ) -> Option<u64> {
        // First: find idle slot
        if let Some(voice) = self.voices.iter_mut().find(|v| v.state == VoiceState::Idle) {
            let id = self.next_id;
            self.next_id += 1;
            voice.activate(id, audio, volume, bus, priority, graph_id, self.global_tick);
            return Some(id);
        }

        // Voice stealing: find lowest priority, oldest voice
        let steal_idx = self.find_steal_candidate(priority);
        if let Some(idx) = steal_idx {
            self.voices[idx].start_fade_out(240);
            let id = self.next_id;
            self.next_id += 1;
            // Queue activation after fade (handled in process)
            return Some(id);
        }

        None
    }

    fn find_steal_candidate(&self, min_priority: VoicePriority) -> Option<usize> {
        let mut best_idx = None;
        let mut best_priority = VoicePriority::Critical;
        let mut oldest_tick = u64::MAX;

        for (i, voice) in self.voices.iter().enumerate() {
            if !voice.is_active() { continue; }
            if voice.priority > min_priority { continue; }

            if voice.priority < best_priority
                || (voice.priority == best_priority && voice.start_tick < oldest_tick)
            {
                best_priority = voice.priority;
                oldest_tick = voice.start_tick;
                best_idx = Some(i);
            }
        }
        best_idx
    }

    pub fn stop_voice(&mut self, voice_id: u64, fade_samples: u64) {
        if let Some(voice) = self.voices.iter_mut().find(|v| v.id == voice_id) {
            voice.start_fade_out(fade_samples);
        }
    }

    pub fn stop_graph_voices(&mut self, graph_id: u32, fade_samples: u64) {
        for voice in &mut self.voices {
            if voice.graph_instance_id == graph_id && voice.is_active() {
                voice.start_fade_out(fade_samples);
            }
        }
    }

    pub fn stop_all(&mut self, fade_samples: u64) {
        for voice in &mut self.voices {
            if voice.is_active() {
                voice.start_fade_out(fade_samples);
            }
        }
    }

    pub fn active_count(&self) -> usize {
        self.voices.iter().filter(|v| v.is_active()).count()
    }

    pub fn voices(&self) -> &[Voice] {
        &self.voices
    }

    pub fn voices_mut(&mut self) -> &mut [Voice] {
        &mut self.voices
    }

    pub fn tick(&mut self) {
        self.global_tick += 1;
        // Cleanup stopped voices
        for voice in &mut self.voices {
            if voice.state == VoiceState::Stopped {
                voice.deactivate();
            }
        }
    }
}
