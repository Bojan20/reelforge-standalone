//! Plugin Instance Management
//!
//! Provides actual plugin loading and instantiation:
//! - VST3 plugin loading via vst3-sys
//! - CLAP plugin loading via clap-sys
//! - AU plugin loading via AudioUnit framework
//! - Parameter management
//! - Audio/MIDI processing
//!
//! NOTE: This uses trait objects for format-agnostic plugin handling.

use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;

use parking_lot::{Mutex, RwLock};

use crate::{PluginError, PluginFormat, PluginInfo, PluginResult};

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN PARAMETER
// ═══════════════════════════════════════════════════════════════════════════════

/// Parameter ID
pub type ParamId = u32;

/// Plugin parameter information
#[derive(Debug, Clone)]
pub struct PluginParameter {
    /// Parameter ID
    pub id: ParamId,
    /// Display name
    pub name: String,
    /// Short name (for compact displays)
    pub short_name: String,
    /// Unit label (dB, Hz, %, etc.)
    pub unit: String,
    /// Minimum value
    pub min: f64,
    /// Maximum value
    pub max: f64,
    /// Default value
    pub default: f64,
    /// Current value
    pub value: f64,
    /// Is automatable
    pub automatable: bool,
    /// Is stepped/discrete
    pub stepped: bool,
    /// Step count (for discrete params)
    pub step_count: u32,
    /// Parameter flags
    pub flags: ParameterFlags,
}

/// Parameter flags
#[derive(Debug, Clone, Copy, Default)]
pub struct ParameterFlags {
    pub is_bypass: bool,
    pub is_hidden: bool,
    pub is_readonly: bool,
    pub is_program_change: bool,
}

impl PluginParameter {
    /// Get normalized value (0.0 - 1.0)
    pub fn normalized(&self) -> f64 {
        if (self.max - self.min).abs() < f64::EPSILON {
            0.0
        } else {
            (self.value - self.min) / (self.max - self.min)
        }
    }

    /// Set from normalized value
    pub fn set_normalized(&mut self, normalized: f64) {
        self.value = self.min + normalized.clamp(0.0, 1.0) * (self.max - self.min);
    }

    /// Format value for display
    pub fn format_value(&self) -> String {
        if self.stepped && self.step_count > 0 {
            format!("{:.0}{}", self.value, self.unit)
        } else if self.unit == "dB" {
            format!("{:.1} {}", self.value, self.unit)
        } else if self.unit == "Hz" {
            if self.value >= 1000.0 {
                format!("{:.2} kHz", self.value / 1000.0)
            } else {
                format!("{:.0} Hz", self.value)
            }
        } else if self.unit == "%" {
            format!("{:.0}%", self.value)
        } else if self.unit.is_empty() {
            format!("{:.2}", self.value)
        } else {
            format!("{:.2} {}", self.value, self.unit)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIO BUFFER
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio buffer for plugin processing
#[derive(Debug, Clone)]
pub struct PluginAudioBuffer {
    /// Input channels (each channel is a Vec of samples)
    pub inputs: Vec<Vec<f32>>,
    /// Output channels
    pub outputs: Vec<Vec<f32>>,
    /// Buffer size
    pub num_samples: usize,
}

impl PluginAudioBuffer {
    /// Create new buffer
    pub fn new(num_inputs: usize, num_outputs: usize, num_samples: usize) -> Self {
        Self {
            inputs: vec![vec![0.0; num_samples]; num_inputs],
            outputs: vec![vec![0.0; num_samples]; num_outputs],
            num_samples,
        }
    }

    /// Clear all buffers
    pub fn clear(&mut self) {
        for ch in &mut self.inputs {
            ch.fill(0.0);
        }
        for ch in &mut self.outputs {
            ch.fill(0.0);
        }
    }

    /// Copy inputs to outputs (passthrough)
    pub fn passthrough(&mut self) {
        let channels = self.inputs.len().min(self.outputs.len());
        for ch in 0..channels {
            self.outputs[ch].copy_from_slice(&self.inputs[ch]);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MIDI BUFFER
// ═══════════════════════════════════════════════════════════════════════════════

/// Simple MIDI event for plugin processing
#[derive(Debug, Clone, Copy)]
pub struct PluginMidiEvent {
    /// Sample offset in buffer
    pub sample_offset: u32,
    /// MIDI bytes (up to 3 for standard messages)
    pub data: [u8; 3],
    /// Data length (1-3)
    pub length: u8,
}

impl PluginMidiEvent {
    pub fn note_on(sample_offset: u32, channel: u8, note: u8, velocity: u8) -> Self {
        Self {
            sample_offset,
            data: [0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F],
            length: 3,
        }
    }

    pub fn note_off(sample_offset: u32, channel: u8, note: u8, velocity: u8) -> Self {
        Self {
            sample_offset,
            data: [0x80 | (channel & 0x0F), note & 0x7F, velocity & 0x7F],
            length: 3,
        }
    }

    pub fn control_change(sample_offset: u32, channel: u8, cc: u8, value: u8) -> Self {
        Self {
            sample_offset,
            data: [0xB0 | (channel & 0x0F), cc & 0x7F, value & 0x7F],
            length: 3,
        }
    }
}

/// MIDI buffer for plugin
#[derive(Debug, Clone, Default)]
pub struct PluginMidiBuffer {
    events: Vec<PluginMidiEvent>,
}

impl PluginMidiBuffer {
    pub fn new() -> Self {
        Self { events: Vec::with_capacity(256) }
    }

    pub fn clear(&mut self) {
        self.events.clear();
    }

    pub fn push(&mut self, event: PluginMidiEvent) {
        self.events.push(event);
    }

    pub fn events(&self) -> &[PluginMidiEvent] {
        &self.events
    }

    pub fn sort_by_time(&mut self) {
        self.events.sort_by_key(|e| e.sample_offset);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PROCESS CONTEXT
// ═══════════════════════════════════════════════════════════════════════════════

/// Transport state
#[derive(Debug, Clone, Copy, Default)]
pub struct TransportState {
    /// Is playing
    pub playing: bool,
    /// Is recording
    pub recording: bool,
    /// Is looping
    pub looping: bool,
    /// Current tempo (BPM)
    pub tempo: f64,
    /// Time signature numerator
    pub time_sig_num: u32,
    /// Time signature denominator
    pub time_sig_denom: u32,
    /// Current position in samples
    pub position_samples: i64,
    /// Current position in beats
    pub position_beats: f64,
    /// Current bar
    pub bar: i32,
    /// Loop start (beats)
    pub loop_start_beats: f64,
    /// Loop end (beats)
    pub loop_end_beats: f64,
}

/// Process context passed to plugins
#[derive(Debug, Clone)]
pub struct ProcessContext {
    /// Sample rate
    pub sample_rate: f64,
    /// Block size
    pub block_size: u32,
    /// Transport state
    pub transport: TransportState,
    /// Continuous time in samples
    pub continuous_time_samples: i64,
    /// System time in nanoseconds
    pub system_time_ns: u64,
}

impl Default for ProcessContext {
    fn default() -> Self {
        Self {
            sample_rate: 48000.0,
            block_size: 256,
            transport: TransportState {
                tempo: 120.0,
                time_sig_num: 4,
                time_sig_denom: 4,
                ..Default::default()
            },
            continuous_time_samples: 0,
            system_time_ns: 0,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN INSTANCE TRAIT
// ═══════════════════════════════════════════════════════════════════════════════

/// Result of processing
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProcessStatus {
    /// Plugin produced output
    Normal,
    /// Plugin produced silence (can skip downstream processing)
    Silence,
    /// Plugin requests tail processing
    Tail,
    /// Processing error
    Error,
}

/// Plugin instance trait - format-agnostic interface
pub trait PluginInstance: Send {
    /// Get plugin info
    fn info(&self) -> &PluginInfo;

    /// Initialize plugin
    fn init(&mut self, sample_rate: f64, max_block_size: u32) -> PluginResult<()>;

    /// Activate plugin (start processing)
    fn activate(&mut self) -> PluginResult<()>;

    /// Deactivate plugin (stop processing)
    fn deactivate(&mut self) -> PluginResult<()>;

    /// Process audio
    fn process(
        &mut self,
        audio: &mut PluginAudioBuffer,
        midi_in: &PluginMidiBuffer,
        midi_out: &mut PluginMidiBuffer,
        context: &ProcessContext,
    ) -> ProcessStatus;

    /// Get all parameters
    fn parameters(&self) -> Vec<PluginParameter>;

    /// Get parameter by ID
    fn get_parameter(&self, id: ParamId) -> Option<f64>;

    /// Set parameter value
    fn set_parameter(&mut self, id: ParamId, value: f64);

    /// Get parameter normalized (0-1)
    fn get_parameter_normalized(&self, id: ParamId) -> Option<f64>;

    /// Set parameter normalized (0-1)
    fn set_parameter_normalized(&mut self, id: ParamId, value: f64);

    /// Begin parameter edit (for automation recording)
    fn begin_edit(&mut self, id: ParamId);

    /// End parameter edit
    fn end_edit(&mut self, id: ParamId);

    /// Get latency in samples
    fn latency(&self) -> u32;

    /// Get tail length in samples
    fn tail_samples(&self) -> u32;

    /// Save state to bytes
    fn save_state(&self) -> PluginResult<Vec<u8>>;

    /// Load state from bytes
    fn load_state(&mut self, data: &[u8]) -> PluginResult<()>;

    /// Get preset names
    fn preset_names(&self) -> Vec<String>;

    /// Load preset by index
    fn load_preset(&mut self, index: usize) -> PluginResult<()>;

    /// Is plugin a synth/instrument?
    fn is_instrument(&self) -> bool {
        self.info().is_instrument
    }

    /// Has editor/GUI?
    fn has_editor(&self) -> bool {
        false
    }

    /// Get editor size
    fn editor_size(&self) -> (u32, u32) {
        (800, 600)
    }

    /// Reset plugin state
    fn reset(&mut self);
}

// ═══════════════════════════════════════════════════════════════════════════════
// DUMMY PLUGIN (for testing/fallback)
// ═══════════════════════════════════════════════════════════════════════════════

/// Dummy plugin instance for testing
pub struct DummyPlugin {
    info: PluginInfo,
    sample_rate: f64,
    is_active: bool,
    parameters: Vec<PluginParameter>,
    bypass: bool,
}

impl DummyPlugin {
    pub fn new(info: PluginInfo) -> Self {
        // Create default parameters
        let parameters = vec![
            PluginParameter {
                id: 0,
                name: "Bypass".to_string(),
                short_name: "Byp".to_string(),
                unit: String::new(),
                min: 0.0,
                max: 1.0,
                default: 0.0,
                value: 0.0,
                automatable: true,
                stepped: true,
                step_count: 2,
                flags: ParameterFlags { is_bypass: true, ..Default::default() },
            },
            PluginParameter {
                id: 1,
                name: "Gain".to_string(),
                short_name: "Gain".to_string(),
                unit: "dB".to_string(),
                min: -24.0,
                max: 24.0,
                default: 0.0,
                value: 0.0,
                automatable: true,
                stepped: false,
                step_count: 0,
                flags: Default::default(),
            },
        ];

        Self {
            info,
            sample_rate: 48000.0,
            is_active: false,
            parameters,
            bypass: false,
        }
    }
}

impl PluginInstance for DummyPlugin {
    fn info(&self) -> &PluginInfo {
        &self.info
    }

    fn init(&mut self, sample_rate: f64, _max_block_size: u32) -> PluginResult<()> {
        self.sample_rate = sample_rate;
        Ok(())
    }

    fn activate(&mut self) -> PluginResult<()> {
        self.is_active = true;
        Ok(())
    }

    fn deactivate(&mut self) -> PluginResult<()> {
        self.is_active = false;
        Ok(())
    }

    fn process(
        &mut self,
        audio: &mut PluginAudioBuffer,
        _midi_in: &PluginMidiBuffer,
        _midi_out: &mut PluginMidiBuffer,
        _context: &ProcessContext,
    ) -> ProcessStatus {
        if self.bypass {
            audio.passthrough();
            return ProcessStatus::Normal;
        }

        // Apply gain
        let gain_db = self.parameters[1].value;
        let gain = 10.0_f32.powf(gain_db as f32 / 20.0);

        let channels = audio.inputs.len().min(audio.outputs.len());
        for ch in 0..channels {
            for i in 0..audio.num_samples {
                audio.outputs[ch][i] = audio.inputs[ch][i] * gain;
            }
        }

        ProcessStatus::Normal
    }

    fn parameters(&self) -> Vec<PluginParameter> {
        self.parameters.clone()
    }

    fn get_parameter(&self, id: ParamId) -> Option<f64> {
        self.parameters.iter().find(|p| p.id == id).map(|p| p.value)
    }

    fn set_parameter(&mut self, id: ParamId, value: f64) {
        if let Some(param) = self.parameters.iter_mut().find(|p| p.id == id) {
            param.value = value.clamp(param.min, param.max);
            if id == 0 {
                self.bypass = value > 0.5;
            }
        }
    }

    fn get_parameter_normalized(&self, id: ParamId) -> Option<f64> {
        self.parameters.iter().find(|p| p.id == id).map(|p| p.normalized())
    }

    fn set_parameter_normalized(&mut self, id: ParamId, value: f64) {
        if let Some(param) = self.parameters.iter_mut().find(|p| p.id == id) {
            param.set_normalized(value);
            if id == 0 {
                self.bypass = param.value > 0.5;
            }
        }
    }

    fn begin_edit(&mut self, _id: ParamId) {}
    fn end_edit(&mut self, _id: ParamId) {}

    fn latency(&self) -> u32 {
        0
    }

    fn tail_samples(&self) -> u32 {
        0
    }

    fn save_state(&self) -> PluginResult<Vec<u8>> {
        let state: Vec<(ParamId, f64)> = self.parameters.iter()
            .map(|p| (p.id, p.value))
            .collect();
        serde_json::to_vec(&state)
            .map_err(|e| PluginError::SerializationError(e.to_string()))
    }

    fn load_state(&mut self, data: &[u8]) -> PluginResult<()> {
        let state: Vec<(ParamId, f64)> = serde_json::from_slice(data)
            .map_err(|e| PluginError::SerializationError(e.to_string()))?;
        for (id, value) in state {
            self.set_parameter(id, value);
        }
        Ok(())
    }

    fn preset_names(&self) -> Vec<String> {
        vec!["Default".to_string(), "Boost".to_string(), "Cut".to_string()]
    }

    fn load_preset(&mut self, index: usize) -> PluginResult<()> {
        match index {
            0 => self.set_parameter(1, 0.0),
            1 => self.set_parameter(1, 6.0),
            2 => self.set_parameter(1, -6.0),
            _ => return Err(PluginError::PresetNotFound(index)),
        }
        Ok(())
    }

    fn reset(&mut self) {
        for param in &mut self.parameters {
            param.value = param.default;
        }
        self.bypass = false;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN INSTANCE MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

/// Unique instance ID
pub type InstanceId = u64;

/// Plugin instance wrapper with shared state
pub struct ManagedInstance {
    pub id: InstanceId,
    pub instance: Box<dyn PluginInstance>,
    pub is_active: bool,
    pub is_bypassed: bool,
}

/// Plugin instance manager
pub struct PluginInstanceManager {
    instances: RwLock<HashMap<InstanceId, Arc<Mutex<ManagedInstance>>>>,
    next_id: std::sync::atomic::AtomicU64,
    sample_rate: f64,
    block_size: u32,
}

impl PluginInstanceManager {
    pub fn new(sample_rate: f64, block_size: u32) -> Self {
        Self {
            instances: RwLock::new(HashMap::new()),
            next_id: std::sync::atomic::AtomicU64::new(1),
            sample_rate,
            block_size,
        }
    }

    /// Create a new plugin instance
    pub fn create_instance(&self, info: &PluginInfo) -> PluginResult<InstanceId> {
        let id = self.next_id.fetch_add(1, std::sync::atomic::Ordering::Relaxed);

        // For now, create dummy plugin. Real implementation would:
        // - Load VST3 via vst3-sys
        // - Load CLAP via clap-sys
        // - Load AU via AudioUnit framework
        let mut instance: Box<dyn PluginInstance> = match info.format {
            PluginFormat::Vst3 => {
                // TODO: Load actual VST3
                log::info!("Creating VST3 instance for: {}", info.name);
                Box::new(DummyPlugin::new(info.clone()))
            }
            PluginFormat::Clap => {
                // TODO: Load actual CLAP
                log::info!("Creating CLAP instance for: {}", info.name);
                Box::new(DummyPlugin::new(info.clone()))
            }
            PluginFormat::Au => {
                // TODO: Load actual AU
                log::info!("Creating AU instance for: {}", info.name);
                Box::new(DummyPlugin::new(info.clone()))
            }
            PluginFormat::Vst2 => {
                return Err(PluginError::UnsupportedFormat("VST2".to_string()));
            }
        };

        // Initialize
        instance.init(self.sample_rate, self.block_size)?;

        let managed = ManagedInstance {
            id,
            instance,
            is_active: false,
            is_bypassed: false,
        };

        self.instances.write().insert(id, Arc::new(Mutex::new(managed)));

        Ok(id)
    }

    /// Get instance by ID
    pub fn get(&self, id: InstanceId) -> Option<Arc<Mutex<ManagedInstance>>> {
        self.instances.read().get(&id).cloned()
    }

    /// Remove instance
    pub fn remove(&self, id: InstanceId) -> bool {
        self.instances.write().remove(&id).is_some()
    }

    /// Activate instance
    pub fn activate(&self, id: InstanceId) -> PluginResult<()> {
        if let Some(instance) = self.get(id) {
            let mut locked = instance.lock();
            locked.instance.activate()?;
            locked.is_active = true;
            Ok(())
        } else {
            Err(PluginError::InstanceNotFound(id))
        }
    }

    /// Deactivate instance
    pub fn deactivate(&self, id: InstanceId) -> PluginResult<()> {
        if let Some(instance) = self.get(id) {
            let mut locked = instance.lock();
            locked.instance.deactivate()?;
            locked.is_active = false;
            Ok(())
        } else {
            Err(PluginError::InstanceNotFound(id))
        }
    }

    /// Set bypass state
    pub fn set_bypass(&self, id: InstanceId, bypass: bool) {
        if let Some(instance) = self.get(id) {
            instance.lock().is_bypassed = bypass;
        }
    }

    /// Get all instance IDs
    pub fn instance_ids(&self) -> Vec<InstanceId> {
        self.instances.read().keys().copied().collect()
    }

    /// Update sample rate (requires reinit)
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        // Would need to reinit all instances
    }

    /// Update block size (requires reinit)
    pub fn set_block_size(&mut self, block_size: u32) {
        self.block_size = block_size;
        // Would need to reinit all instances
    }
}

impl Default for PluginInstanceManager {
    fn default() -> Self {
        Self::new(48000.0, 256)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN LOADER (Format-specific stubs)
// ═══════════════════════════════════════════════════════════════════════════════

/// VST3 plugin loader (stub - requires vst3-sys)
#[cfg(feature = "vst3")]
pub mod vst3 {
    use super::*;

    pub fn load_vst3(_path: &Path) -> PluginResult<Box<dyn PluginInstance>> {
        // Would implement VST3 loading via vst3-sys:
        // 1. Load shared library
        // 2. Get IPluginFactory
        // 3. Create IComponent
        // 4. Query IEditController
        // 5. Initialize and connect
        Err(PluginError::UnsupportedFormat("VST3 not compiled".to_string()))
    }
}

/// CLAP plugin loader (stub - requires clap-sys)
#[cfg(feature = "clap")]
pub mod clap {
    use super::*;

    pub fn load_clap(_path: &Path) -> PluginResult<Box<dyn PluginInstance>> {
        // Would implement CLAP loading via clap-sys:
        // 1. Load shared library
        // 2. Get clap_plugin_entry
        // 3. Call entry->init
        // 4. Get factory, create plugin
        // 5. Activate
        Err(PluginError::UnsupportedFormat("CLAP not compiled".to_string()))
    }
}

/// AU plugin loader (stub - requires AudioUnit framework)
#[cfg(all(target_os = "macos", feature = "au"))]
pub mod au {
    use super::*;

    pub fn load_au(_path: &Path) -> PluginResult<Box<dyn PluginInstance>> {
        // Would implement AU loading via AudioUnit framework:
        // 1. Find AudioComponent by path/description
        // 2. AudioComponentInstanceNew
        // 3. AudioUnitInitialize
        // 4. Set parameters via AudioUnitSetProperty
        Err(PluginError::UnsupportedFormat("AU not compiled".to_string()))
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn test_plugin_info() -> PluginInfo {
        PluginInfo {
            id: "test-plugin".to_string(),
            name: "Test Plugin".to_string(),
            vendor: "Test Vendor".to_string(),
            version: "1.0.0".to_string(),
            format: PluginFormat::Vst3,
            category: crate::PluginCategory::Effect,
            path: PathBuf::from("/test/plugin.vst3"),
            is_instrument: false,
            num_inputs: 2,
            num_outputs: 2,
            has_midi_input: false,
            has_midi_output: false,
            is_valid: true,
            scanned_at: 0,
            file_modified: 0,
            tags: vec![],
        }
    }

    #[test]
    fn test_dummy_plugin_creation() {
        let info = test_plugin_info();
        let plugin = DummyPlugin::new(info);

        assert_eq!(plugin.latency(), 0);
        assert!(!plugin.is_instrument());
    }

    #[test]
    fn test_dummy_plugin_parameters() {
        let info = test_plugin_info();
        let mut plugin = DummyPlugin::new(info);

        let params = plugin.parameters();
        assert!(params.len() >= 2);

        // Test gain parameter
        plugin.set_parameter(1, 6.0);
        assert_eq!(plugin.get_parameter(1), Some(6.0));

        // Test normalized
        plugin.set_parameter_normalized(1, 0.5);
        let norm = plugin.get_parameter_normalized(1).unwrap();
        assert!((norm - 0.5).abs() < 0.01);
    }

    #[test]
    fn test_dummy_plugin_process() {
        let info = test_plugin_info();
        let mut plugin = DummyPlugin::new(info);
        plugin.init(48000.0, 256).unwrap();
        plugin.activate().unwrap();

        let mut buffer = PluginAudioBuffer::new(2, 2, 256);
        let midi_in = PluginMidiBuffer::new();
        let mut midi_out = PluginMidiBuffer::new();
        let context = ProcessContext::default();

        // Fill input with test signal
        for i in 0..256 {
            buffer.inputs[0][i] = 0.5;
            buffer.inputs[1][i] = 0.5;
        }

        let status = plugin.process(&mut buffer, &midi_in, &mut midi_out, &context);
        assert_eq!(status, ProcessStatus::Normal);

        // With 0dB gain, output should equal input
        assert!((buffer.outputs[0][0] - 0.5).abs() < 0.001);
    }

    #[test]
    fn test_plugin_state_save_load() {
        let info = test_plugin_info();
        let mut plugin = DummyPlugin::new(info.clone());

        plugin.set_parameter(1, 12.0);

        let state = plugin.save_state().unwrap();

        let mut plugin2 = DummyPlugin::new(info);
        plugin2.load_state(&state).unwrap();

        assert_eq!(plugin2.get_parameter(1), Some(12.0));
    }

    #[test]
    fn test_instance_manager() {
        let manager = PluginInstanceManager::new(48000.0, 256);
        let info = test_plugin_info();

        let id = manager.create_instance(&info).unwrap();
        assert!(manager.get(id).is_some());

        manager.activate(id).unwrap();
        manager.set_bypass(id, true);

        let ids = manager.instance_ids();
        assert!(ids.contains(&id));

        assert!(manager.remove(id));
        assert!(manager.get(id).is_none());
    }

    #[test]
    fn test_parameter_formatting() {
        let mut param = PluginParameter {
            id: 0,
            name: "Frequency".to_string(),
            short_name: "Freq".to_string(),
            unit: "Hz".to_string(),
            min: 20.0,
            max: 20000.0,
            default: 1000.0,
            value: 1000.0,
            automatable: true,
            stepped: false,
            step_count: 0,
            flags: Default::default(),
        };

        assert_eq!(param.format_value(), "1.00 kHz");

        param.value = 500.0;
        assert_eq!(param.format_value(), "500 Hz");
    }

    #[test]
    fn test_audio_buffer() {
        let mut buffer = PluginAudioBuffer::new(2, 2, 128);

        // Test passthrough
        buffer.inputs[0][0] = 1.0;
        buffer.inputs[1][0] = -1.0;
        buffer.passthrough();

        assert_eq!(buffer.outputs[0][0], 1.0);
        assert_eq!(buffer.outputs[1][0], -1.0);

        // Test clear
        buffer.clear();
        assert_eq!(buffer.inputs[0][0], 0.0);
        assert_eq!(buffer.outputs[0][0], 0.0);
    }

    #[test]
    fn test_midi_buffer() {
        let mut buffer = PluginMidiBuffer::new();

        buffer.push(PluginMidiEvent::note_on(100, 0, 60, 100));
        buffer.push(PluginMidiEvent::note_on(0, 0, 64, 100));
        buffer.push(PluginMidiEvent::note_off(200, 0, 60, 0));

        buffer.sort_by_time();

        let events = buffer.events();
        assert_eq!(events.len(), 3);
        assert_eq!(events[0].sample_offset, 0);
        assert_eq!(events[1].sample_offset, 100);
        assert_eq!(events[2].sample_offset, 200);
    }
}
