// ============================================================================
// FLUXFORGE STUDIO — WASM Port
// WebAssembly bindings for FluxForge audio middleware
// Enables runtime audio processing in web browsers
// ============================================================================

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use wasm_bindgen::prelude::*;
use web_sys::{AudioBuffer, AudioContext, GainNode, StereoPannerNode};

// ============================================================================
// INITIALIZATION
// ============================================================================

#[cfg(feature = "console_error_panic_hook")]
pub fn set_panic_hook() {
    console_error_panic_hook::set_once();
}

#[cfg(feature = "wee_alloc")]
#[global_allocator]
static ALLOC: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;

/// Initialize the WASM module
#[wasm_bindgen(start)]
pub fn init() {
    #[cfg(feature = "console_error_panic_hook")]
    set_panic_hook();

    console_log::init_with_level(log::Level::Debug).ok();
    log::info!("[FluxForge WASM] Initialized");
}

// ============================================================================
// TYPES
// ============================================================================

/// Audio bus identifier
#[wasm_bindgen]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AudioBus {
    Master = 0,
    Sfx = 1,
    Music = 2,
    Voice = 3,
    Ambience = 4,
    Ui = 5,
    Reels = 6,
}

/// Voice stealing mode
#[wasm_bindgen]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum VoiceStealMode {
    None = 0,
    Oldest = 1,
    Quietest = 2,
    LowestPriority = 3,
}

/// Playback state
#[wasm_bindgen]
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum PlaybackState {
    Stopped = 0,
    Playing = 1,
    Paused = 2,
    FadingOut = 3,
}

/// Audio event layer
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AudioLayer {
    pub audio_path: String,
    pub volume: f32,
    pub pan: f32,
    pub delay_ms: u32,
    pub offset_ms: u32,
    pub bus: AudioBus,
    pub loop_enabled: bool,
}

/// Audio event definition
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AudioEvent {
    pub id: String,
    pub name: String,
    pub stages: Vec<String>,
    pub layers: Vec<AudioLayer>,
    pub priority: u8,
}

/// Voice instance
#[derive(Clone, Debug)]
struct VoiceInstance {
    id: u32,
    event_id: String,
    start_time: f64,
    state: PlaybackState,
    volume: f32,
    priority: u8,
}

/// RTPC definition
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RtpcDef {
    pub name: String,
    pub min: f32,
    pub max: f32,
    pub default: f32,
}

/// State group
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StateGroupDef {
    pub name: String,
    pub states: Vec<String>,
    pub default_state: String,
}

// ============================================================================
// VOICE HANDLE (JS-visible)
// ============================================================================

#[wasm_bindgen]
#[derive(Clone, Debug)]
pub struct VoiceHandle {
    id: u32,
    event_id: String,
}

#[wasm_bindgen]
impl VoiceHandle {
    #[wasm_bindgen(getter)]
    pub fn id(&self) -> u32 {
        self.id
    }

    #[wasm_bindgen(getter)]
    pub fn event_id(&self) -> String {
        self.event_id.clone()
    }

    #[wasm_bindgen]
    pub fn is_valid(&self) -> bool {
        self.id > 0
    }
}

// ============================================================================
// AUDIO MANAGER (Main WASM API)
// ============================================================================

static NEXT_VOICE_ID: AtomicU32 = AtomicU32::new(1);

#[wasm_bindgen]
pub struct FluxForgeAudio {
    context: Option<AudioContext>,
    master_gain: Option<GainNode>,
    bus_gains: HashMap<u8, GainNode>,
    events: HashMap<String, AudioEvent>,
    stage_map: HashMap<String, String>,
    voices: Vec<VoiceInstance>,
    free_voice_ids: Vec<u32>,
    bus_volumes: HashMap<u8, f32>,
    bus_mutes: HashMap<u8, bool>,
    rtpc_values: HashMap<String, f32>,
    rtpc_defs: HashMap<String, RtpcDef>,
    state_groups: HashMap<String, String>,
    max_voices: u32,
    max_voices_per_event: u32,
    steal_mode: VoiceStealMode,
    initialized: bool,
}

#[wasm_bindgen]
impl FluxForgeAudio {
    /// Create a new FluxForge audio manager
    #[wasm_bindgen(constructor)]
    pub fn new() -> FluxForgeAudio {
        FluxForgeAudio {
            context: None,
            master_gain: None,
            bus_gains: HashMap::new(),
            events: HashMap::new(),
            stage_map: HashMap::new(),
            voices: Vec::with_capacity(32),
            free_voice_ids: Vec::with_capacity(32),
            bus_volumes: HashMap::new(),
            bus_mutes: HashMap::new(),
            rtpc_values: HashMap::new(),
            rtpc_defs: HashMap::new(),
            state_groups: HashMap::new(),
            max_voices: 32,
            max_voices_per_event: 4,
            steal_mode: VoiceStealMode::Oldest,
            initialized: false,
        }
    }

    /// Initialize the audio context (must be called from user gesture)
    #[wasm_bindgen]
    pub fn init(&mut self) -> Result<(), JsValue> {
        if self.initialized {
            return Ok(());
        }

        // Create AudioContext
        let context = AudioContext::new()?;

        // Create master gain
        let master_gain = context.create_gain()?;
        master_gain.connect_with_audio_node(&context.destination())?;
        master_gain.gain().set_value(1.0);

        // Create bus gains
        for bus in 0..7u8 {
            let gain = context.create_gain()?;
            gain.connect_with_audio_node(&master_gain)?;
            gain.gain().set_value(1.0);
            self.bus_gains.insert(bus, gain);
            self.bus_volumes.insert(bus, 1.0);
            self.bus_mutes.insert(bus, false);
        }

        self.context = Some(context);
        self.master_gain = Some(master_gain);
        self.initialized = true;

        log::info!("[FluxForge WASM] Audio context initialized");
        Ok(())
    }

    /// Resume audio context (for auto-play policy)
    #[wasm_bindgen]
    pub async fn resume(&self) -> Result<(), JsValue> {
        if let Some(ctx) = &self.context {
            wasm_bindgen_futures::JsFuture::from(ctx.resume()?).await?;
        }
        Ok(())
    }

    /// Load event definitions from JSON
    #[wasm_bindgen]
    pub fn load_events_json(&mut self, json: &str) -> Result<u32, JsValue> {
        let events: Vec<AudioEvent> = serde_json::from_str(json)
            .map_err(|e| JsValue::from_str(&format!("JSON parse error: {}", e)))?;

        let count = events.len() as u32;

        for event in events {
            // Build stage mappings
            for stage in &event.stages {
                self.stage_map
                    .insert(stage.to_uppercase(), event.id.clone());
            }
            self.events.insert(event.id.clone(), event);
        }

        log::info!("[FluxForge WASM] Loaded {} events", count);
        Ok(count)
    }

    /// Load RTPC definitions from JSON
    #[wasm_bindgen]
    pub fn load_rtpc_json(&mut self, json: &str) -> Result<u32, JsValue> {
        let defs: Vec<RtpcDef> = serde_json::from_str(json)
            .map_err(|e| JsValue::from_str(&format!("JSON parse error: {}", e)))?;

        let count = defs.len() as u32;

        for def in defs {
            self.rtpc_values.insert(def.name.clone(), def.default);
            self.rtpc_defs.insert(def.name.clone(), def);
        }

        log::info!("[FluxForge WASM] Loaded {} RTPCs", count);
        Ok(count)
    }

    /// Load state group definitions from JSON
    #[wasm_bindgen]
    pub fn load_state_groups_json(&mut self, json: &str) -> Result<u32, JsValue> {
        let groups: Vec<StateGroupDef> = serde_json::from_str(json)
            .map_err(|e| JsValue::from_str(&format!("JSON parse error: {}", e)))?;

        let count = groups.len() as u32;

        for group in groups {
            self.state_groups
                .insert(group.name.clone(), group.default_state);
        }

        log::info!("[FluxForge WASM] Loaded {} state groups", count);
        Ok(count)
    }

    // ════════════════════════════════════════════════════════════════════════
    // EVENT PLAYBACK
    // ════════════════════════════════════════════════════════════════════════

    /// Play an event by ID
    #[wasm_bindgen]
    pub fn play_event(&mut self, event_id: &str, volume: f32, pitch: f32) -> Option<VoiceHandle> {
        if !self.initialized {
            log::warn!("[FluxForge WASM] Not initialized");
            return None;
        }

        let event = self.events.get(event_id)?.clone();

        // Acquire voice
        let voice_id = self.acquire_voice(&event_id.to_string(), event.priority)?;

        // Create voice instance
        let context = self.context.as_ref()?;
        let now = context.current_time();

        self.voices.push(VoiceInstance {
            id: voice_id,
            event_id: event_id.to_string(),
            start_time: now,
            state: PlaybackState::Playing,
            volume,
            priority: event.priority,
        });

        // Note: Actual audio playback would use AudioBufferSourceNode
        // This requires loading audio files which is handled separately
        log::debug!(
            "[FluxForge WASM] Playing event: {} (voice {})",
            event_id,
            voice_id
        );

        Some(VoiceHandle {
            id: voice_id,
            event_id: event_id.to_string(),
        })
    }

    /// Trigger a stage
    #[wasm_bindgen]
    pub fn trigger_stage(&mut self, stage: &str, volume: f32) -> Option<VoiceHandle> {
        let event_id = self.stage_map.get(&stage.to_uppercase())?.clone();
        self.play_event(&event_id, volume, 1.0)
    }

    /// Trigger reel stop by index
    #[wasm_bindgen]
    pub fn trigger_reel_stop(&mut self, reel_index: u32, volume: f32) -> Option<VoiceHandle> {
        let stage = format!("REEL_STOP_{}", reel_index);
        self.trigger_stage(&stage, volume)
            .or_else(|| self.trigger_stage("REEL_STOP", volume))
    }

    /// Stop an event
    #[wasm_bindgen]
    pub fn stop_event(&mut self, event_id: &str, fade_time_ms: u32) {
        for voice in &mut self.voices {
            if voice.event_id == event_id && voice.state == PlaybackState::Playing {
                voice.state = PlaybackState::FadingOut;
                // Note: Actual fade would be applied to GainNode
            }
        }
    }

    /// Stop a specific voice
    #[wasm_bindgen]
    pub fn stop_voice(&mut self, voice_id: u32, fade_time_ms: u32) {
        if let Some(voice) = self.voices.iter_mut().find(|v| v.id == voice_id) {
            voice.state = PlaybackState::FadingOut;
        }
    }

    /// Stop all sounds
    #[wasm_bindgen]
    pub fn stop_all(&mut self, fade_time_ms: u32) {
        for voice in &mut self.voices {
            if voice.state == PlaybackState::Playing {
                voice.state = PlaybackState::FadingOut;
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // BUS CONTROL
    // ════════════════════════════════════════════════════════════════════════

    /// Set bus volume
    #[wasm_bindgen]
    pub fn set_bus_volume(&mut self, bus: AudioBus, volume: f32) {
        let bus_id = bus as u8;
        let clamped = volume.clamp(0.0, 2.0);
        self.bus_volumes.insert(bus_id, clamped);

        if let Some(gain) = self.bus_gains.get(&bus_id) {
            gain.gain().set_value(clamped);
        }
    }

    /// Get bus volume
    #[wasm_bindgen]
    pub fn get_bus_volume(&self, bus: AudioBus) -> f32 {
        *self.bus_volumes.get(&(bus as u8)).unwrap_or(&1.0)
    }

    /// Set bus mute
    #[wasm_bindgen]
    pub fn set_bus_mute(&mut self, bus: AudioBus, mute: bool) {
        let bus_id = bus as u8;
        self.bus_mutes.insert(bus_id, mute);

        if let Some(gain) = self.bus_gains.get(&bus_id) {
            let volume = if mute {
                0.0
            } else {
                *self.bus_volumes.get(&bus_id).unwrap_or(&1.0)
            };
            gain.gain().set_value(volume);
        }
    }

    /// Get bus mute state
    #[wasm_bindgen]
    pub fn is_bus_muted(&self, bus: AudioBus) -> bool {
        *self.bus_mutes.get(&(bus as u8)).unwrap_or(&false)
    }

    /// Set master volume
    #[wasm_bindgen]
    pub fn set_master_volume(&mut self, volume: f32) {
        let clamped = volume.clamp(0.0, 2.0);
        self.bus_volumes.insert(AudioBus::Master as u8, clamped);

        if let Some(gain) = &self.master_gain {
            gain.gain().set_value(clamped);
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // RTPC
    // ════════════════════════════════════════════════════════════════════════

    /// Set RTPC value
    #[wasm_bindgen]
    pub fn set_rtpc(&mut self, name: &str, value: f32) {
        if let Some(def) = self.rtpc_defs.get(name) {
            let clamped = value.clamp(def.min, def.max);
            self.rtpc_values.insert(name.to_string(), clamped);
        }
    }

    /// Get RTPC value
    #[wasm_bindgen]
    pub fn get_rtpc(&self, name: &str) -> f32 {
        *self.rtpc_values.get(name).unwrap_or(&0.0)
    }

    /// Get RTPC normalized (0-1)
    #[wasm_bindgen]
    pub fn get_rtpc_normalized(&self, name: &str) -> f32 {
        if let (Some(def), Some(value)) = (self.rtpc_defs.get(name), self.rtpc_values.get(name)) {
            if def.max > def.min {
                return (value - def.min) / (def.max - def.min);
            }
        }
        0.0
    }

    // ════════════════════════════════════════════════════════════════════════
    // STATE SYSTEM
    // ════════════════════════════════════════════════════════════════════════

    /// Set state
    #[wasm_bindgen]
    pub fn set_state(&mut self, group: &str, state: &str) {
        self.state_groups
            .insert(group.to_string(), state.to_string());
    }

    /// Get current state
    #[wasm_bindgen]
    pub fn get_state(&self, group: &str) -> Option<String> {
        self.state_groups.get(group).cloned()
    }

    // ════════════════════════════════════════════════════════════════════════
    // VOICE MANAGEMENT
    // ════════════════════════════════════════════════════════════════════════

    fn acquire_voice(&mut self, event_id: &str, priority: u8) -> Option<u32> {
        // Count voices for this event
        let event_voice_count = self
            .voices
            .iter()
            .filter(|v| v.event_id == event_id && v.state == PlaybackState::Playing)
            .count();

        // Steal if at max per event
        if event_voice_count >= self.max_voices_per_event as usize {
            self.steal_voice_for_event(event_id);
        }

        // Steal if at global max
        if self.voices.len() >= self.max_voices as usize {
            self.steal_voice_global();
        }

        // Get or create voice ID
        let voice_id = if let Some(id) = self.free_voice_ids.pop() {
            id
        } else {
            NEXT_VOICE_ID.fetch_add(1, Ordering::SeqCst)
        };

        Some(voice_id)
    }

    fn steal_voice_for_event(&mut self, event_id: &str) {
        // Find oldest voice for this event
        if let Some(idx) = self
            .voices
            .iter()
            .enumerate()
            .filter(|(_, v)| v.event_id == event_id && v.state == PlaybackState::Playing)
            .min_by(|(_, a), (_, b)| a.start_time.partial_cmp(&b.start_time).unwrap())
            .map(|(i, _)| i)
        {
            let voice = self.voices.remove(idx);
            self.free_voice_ids.push(voice.id);
        }
    }

    fn steal_voice_global(&mut self) {
        let idx = match self.steal_mode {
            VoiceStealMode::Oldest => self
                .voices
                .iter()
                .enumerate()
                .filter(|(_, v)| v.state == PlaybackState::Playing)
                .min_by(|(_, a), (_, b)| a.start_time.partial_cmp(&b.start_time).unwrap())
                .map(|(i, _)| i),
            VoiceStealMode::Quietest => self
                .voices
                .iter()
                .enumerate()
                .filter(|(_, v)| v.state == PlaybackState::Playing)
                .min_by(|(_, a), (_, b)| a.volume.partial_cmp(&b.volume).unwrap())
                .map(|(i, _)| i),
            VoiceStealMode::LowestPriority => self
                .voices
                .iter()
                .enumerate()
                .filter(|(_, v)| v.state == PlaybackState::Playing)
                .min_by(|(_, a), (_, b)| a.priority.cmp(&b.priority))
                .map(|(i, _)| i),
            VoiceStealMode::None => None,
        };

        if let Some(idx) = idx {
            let voice = self.voices.remove(idx);
            self.free_voice_ids.push(voice.id);
        }
    }

    /// Cleanup finished voices (call periodically)
    #[wasm_bindgen]
    pub fn cleanup_voices(&mut self) {
        let mut to_remove = Vec::new();

        for (idx, voice) in self.voices.iter().enumerate() {
            if voice.state == PlaybackState::Stopped || voice.state == PlaybackState::FadingOut {
                to_remove.push(idx);
            }
        }

        // Remove in reverse order to maintain indices
        for idx in to_remove.into_iter().rev() {
            let voice = self.voices.remove(idx);
            self.free_voice_ids.push(voice.id);
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // STATS
    // ════════════════════════════════════════════════════════════════════════

    /// Get active voice count
    #[wasm_bindgen]
    pub fn get_active_voice_count(&self) -> u32 {
        self.voices
            .iter()
            .filter(|v| v.state == PlaybackState::Playing)
            .count() as u32
    }

    /// Get total event count
    #[wasm_bindgen]
    pub fn get_event_count(&self) -> u32 {
        self.events.len() as u32
    }

    /// Get total RTPC count
    #[wasm_bindgen]
    pub fn get_rtpc_count(&self) -> u32 {
        self.rtpc_defs.len() as u32
    }

    /// Check if initialized
    #[wasm_bindgen]
    pub fn is_initialized(&self) -> bool {
        self.initialized
    }

    /// Get current time from audio context
    #[wasm_bindgen]
    pub fn get_current_time(&self) -> f64 {
        self.context
            .as_ref()
            .map(|c| c.current_time())
            .unwrap_or(0.0)
    }

    /// Get sample rate
    #[wasm_bindgen]
    pub fn get_sample_rate(&self) -> f32 {
        self.context
            .as_ref()
            .map(|c| c.sample_rate())
            .unwrap_or(44100.0)
    }

    // ════════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ════════════════════════════════════════════════════════════════════════

    /// Set max voices
    #[wasm_bindgen]
    pub fn set_max_voices(&mut self, max: u32) {
        self.max_voices = max;
    }

    /// Set max voices per event
    #[wasm_bindgen]
    pub fn set_max_voices_per_event(&mut self, max: u32) {
        self.max_voices_per_event = max;
    }

    /// Set voice steal mode
    #[wasm_bindgen]
    pub fn set_voice_steal_mode(&mut self, mode: VoiceStealMode) {
        self.steal_mode = mode;
    }

    /// Dispose and cleanup
    #[wasm_bindgen]
    pub fn dispose(&mut self) {
        self.stop_all(0);
        self.voices.clear();
        self.events.clear();
        self.stage_map.clear();
        self.rtpc_values.clear();
        self.rtpc_defs.clear();
        self.state_groups.clear();

        // Close audio context
        if let Some(ctx) = &self.context {
            let _ = ctx.close();
        }

        self.context = None;
        self.master_gain = None;
        self.bus_gains.clear();
        self.initialized = false;

        log::info!("[FluxForge WASM] Disposed");
    }
}

// ============================================================================
// UTILITY EXPORTS
// ============================================================================

/// Get FluxForge version
#[wasm_bindgen]
pub fn get_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Convert dB to linear gain
#[wasm_bindgen]
pub fn db_to_linear(db: f32) -> f32 {
    10.0_f32.powf(db / 20.0)
}

/// Convert linear gain to dB
#[wasm_bindgen]
pub fn linear_to_db(linear: f32) -> f32 {
    20.0 * linear.max(0.000001).log10()
}

/// Calculate equal power crossfade values
#[wasm_bindgen]
pub fn equal_power_crossfade(position: f32) -> Vec<f32> {
    let clamped = position.clamp(0.0, 1.0);
    let angle = clamped * std::f32::consts::FRAC_PI_2;
    vec![angle.cos(), angle.sin()]
}

// ============================================================================
// TESTS
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_db_conversion() {
        let db = 0.0;
        let linear = db_to_linear(db);
        assert!((linear - 1.0).abs() < 0.0001);

        let db = -6.0;
        let linear = db_to_linear(db);
        assert!((linear - 0.501187).abs() < 0.001);

        let back_to_db = linear_to_db(linear);
        assert!((back_to_db - db).abs() < 0.001);
    }

    #[test]
    fn test_equal_power() {
        let result = equal_power_crossfade(0.0);
        assert!((result[0] - 1.0).abs() < 0.0001);
        assert!(result[1].abs() < 0.0001);

        let result = equal_power_crossfade(1.0);
        assert!(result[0].abs() < 0.0001);
        assert!((result[1] - 1.0).abs() < 0.0001);

        let result = equal_power_crossfade(0.5);
        assert!((result[0] - 0.7071).abs() < 0.001);
        assert!((result[1] - 0.7071).abs() < 0.001);
    }
}
