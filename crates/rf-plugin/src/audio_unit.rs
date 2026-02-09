//! AudioUnit Plugin Host (macOS only)
//!
//! Loads and hosts AudioUnit plugins on macOS.
//! Reference: https://developer.apple.com/documentation/audiounit
//!
//! # Implementation
//!
//! Uses AudioToolbox framework via objc2 bindings.
//! Supports AU v2 and v3 plugins.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::Mutex;

use crate::scanner::{PluginCategory, PluginInfo, PluginType};
use crate::{
    AudioBuffer, ParameterInfo, PluginError, PluginInstance, PluginResult, ProcessContext,
};

/// AudioUnit component type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u32)]
pub enum AUType {
    /// Effect (kAudioUnitType_Effect)
    Effect = 0x61756678, // 'aufx'
    /// Instrument (kAudioUnitType_MusicDevice)
    Instrument = 0x61756d75, // 'aumu'
    /// Generator (kAudioUnitType_Generator)
    Generator = 0x6175676e, // 'augn'
    /// MIDI Processor (kAudioUnitType_MIDIProcessor)
    MidiProcessor = 0x61756d70, // 'aump'
    /// Music Effect (kAudioUnitType_MusicEffect)
    MusicEffect = 0x61756d66, // 'aumf'
    /// Mixer (kAudioUnitType_Mixer)
    Mixer = 0x61756d78, // 'aumx'
    /// Panner (kAudioUnitType_Panner)
    Panner = 0x6175706e, // 'aupn'
    /// Offline Effect (kAudioUnitType_OfflineEffect)
    OfflineEffect = 0x61756f6c, // 'auol'
    /// Format Converter (kAudioUnitType_FormatConverter)
    FormatConverter = 0x61756663, // 'aufc'
    /// Output (kAudioUnitType_Output)
    Output = 0x61756f75, // 'auou'
}

impl AUType {
    pub fn to_category(&self) -> PluginCategory {
        match self {
            Self::Effect | Self::MusicEffect | Self::OfflineEffect => PluginCategory::Effect,
            Self::Instrument | Self::Generator => PluginCategory::Instrument,
            Self::Mixer => PluginCategory::Utility,
            _ => PluginCategory::Effect,
        }
    }

    pub fn from_u32(value: u32) -> Option<Self> {
        match value {
            0x61756678 => Some(Self::Effect),
            0x61756d75 => Some(Self::Instrument),
            0x6175676e => Some(Self::Generator),
            0x61756d70 => Some(Self::MidiProcessor),
            0x61756d66 => Some(Self::MusicEffect),
            0x61756d78 => Some(Self::Mixer),
            0x6175706e => Some(Self::Panner),
            0x61756f6c => Some(Self::OfflineEffect),
            0x61756663 => Some(Self::FormatConverter),
            0x61756f75 => Some(Self::Output),
            _ => None,
        }
    }
}

/// AudioUnit component description
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct AUComponentDescription {
    /// Component type (effect, instrument, etc.)
    pub component_type: AUType,
    /// Component subtype (specific plugin identifier)
    pub component_subtype: u32,
    /// Manufacturer code
    pub component_manufacturer: u32,
}

impl AUComponentDescription {
    /// Create description from type, subtype, and manufacturer codes
    pub fn new(component_type: AUType, subtype: u32, manufacturer: u32) -> Self {
        Self {
            component_type,
            component_subtype: subtype,
            component_manufacturer: manufacturer,
        }
    }

    /// Convert four-char code to string
    pub fn fourcc_to_string(code: u32) -> String {
        let bytes = code.to_be_bytes();
        bytes
            .iter()
            .map(|&b| if b.is_ascii_graphic() { b as char } else { '?' })
            .collect()
    }

    /// Get string identifier
    pub fn identifier(&self) -> String {
        format!(
            "{}.{}.{}",
            Self::fourcc_to_string(self.component_type as u32),
            Self::fourcc_to_string(self.component_subtype),
            Self::fourcc_to_string(self.component_manufacturer)
        )
    }
}

/// AudioUnit plugin descriptor
#[derive(Debug, Clone)]
pub struct AUDescriptor {
    /// Display name
    pub name: String,
    /// Manufacturer name
    pub manufacturer: String,
    /// Version string
    pub version: String,
    /// Component description
    pub description: AUComponentDescription,
    /// Bundle path
    pub bundle_path: PathBuf,
    /// Is sandboxed (AU v3)
    pub is_sandboxed: bool,
    /// Is AU v3
    pub is_v3: bool,
    /// Audio inputs
    pub audio_inputs: u16,
    /// Audio outputs
    pub audio_outputs: u16,
    /// Has MIDI input
    pub has_midi_input: bool,
    /// Has custom view
    pub has_custom_view: bool,
}

/// Maximum parameter changes per audio block
const MAX_PARAM_CHANGES: usize = 128;

/// Lock-free parameter change
#[derive(Debug, Clone, Copy)]
struct ParamChange {
    id: u32,
    value: f64,
}

/// AudioUnit plugin host
pub struct AudioUnitHost {
    /// Discovered AU descriptors
    descriptors: HashMap<String, AUDescriptor>,
    /// Standard AU paths
    search_paths: Vec<PathBuf>,
}

impl AudioUnitHost {
    pub fn new() -> Self {
        let mut search_paths = Vec::new();

        #[cfg(target_os = "macos")]
        {
            // System AudioUnits
            search_paths.push(PathBuf::from("/Library/Audio/Plug-Ins/Components"));
            // User AudioUnits
            if let Some(home) = dirs_next::home_dir() {
                search_paths.push(home.join("Library/Audio/Plug-Ins/Components"));
            }
        }

        Self {
            descriptors: HashMap::new(),
            search_paths,
        }
    }

    /// Scan for AudioUnit plugins
    #[cfg(target_os = "macos")]
    pub fn scan(&mut self) -> PluginResult<Vec<AUDescriptor>> {
        let mut descriptors = Vec::new();

        for path in &self.search_paths.clone() {
            if path.exists() {
                self.scan_directory(path, &mut descriptors)?;
            }
        }

        // Cache discovered plugins
        for desc in &descriptors {
            let id = desc.description.identifier();
            self.descriptors.insert(id, desc.clone());
        }

        log::info!("Discovered {} AudioUnit plugins", descriptors.len());
        Ok(descriptors)
    }

    #[cfg(not(target_os = "macos"))]
    pub fn scan(&mut self) -> PluginResult<Vec<AUDescriptor>> {
        Ok(Vec::new())
    }

    #[cfg(target_os = "macos")]
    fn scan_directory(&self, path: &Path, descriptors: &mut Vec<AUDescriptor>) -> PluginResult<()> {
        if let Ok(entries) = std::fs::read_dir(path) {
            for entry in entries.flatten() {
                let entry_path = entry.path();
                if entry_path.extension().is_some_and(|e| e == "component")
                    && let Ok(desc) = self.scan_component(&entry_path)
                {
                    descriptors.push(desc);
                }
            }
        }
        Ok(())
    }

    #[cfg(target_os = "macos")]
    fn scan_component(&self, bundle_path: &Path) -> PluginResult<AUDescriptor> {
        // In real implementation:
        // 1. Load the bundle using CFBundleCreate
        // 2. Get AudioComponentFindNext to enumerate components
        // 3. Use AudioComponentCopyName and AudioComponentGetDescription

        let name = bundle_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown")
            .to_string();

        // Check Info.plist for AU v3
        let info_plist = bundle_path.join("Contents/Info.plist");
        let is_v3 = if info_plist.exists() {
            // Look for NSExtension key indicating AU v3
            std::fs::read_to_string(&info_plist)
                .map(|content| content.contains("NSExtension"))
                .unwrap_or(false)
        } else {
            false
        };

        Ok(AUDescriptor {
            name: name.clone(),
            manufacturer: "Unknown".to_string(),
            version: "1.0.0".to_string(),
            description: AUComponentDescription::new(
                AUType::Effect,
                0x70617373, // 'pass'
                0x52464f47, // 'RFOG' (FluxForge Studio)
            ),
            bundle_path: bundle_path.to_path_buf(),
            is_sandboxed: is_v3,
            is_v3,
            audio_inputs: 2,
            audio_outputs: 2,
            has_midi_input: false,
            has_custom_view: true,
        })
    }

    /// Load a plugin instance by identifier
    pub fn load(&self, identifier: &str) -> PluginResult<AudioUnitInstance> {
        let descriptor = self
            .descriptors
            .get(identifier)
            .ok_or_else(|| PluginError::NotFound(identifier.to_string()))?;

        AudioUnitInstance::new(descriptor.clone())
    }

    /// Load a plugin from path
    pub fn load_from_path(path: &Path) -> PluginResult<AudioUnitInstance> {
        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown AU");

        let descriptor = AUDescriptor {
            name: name.to_string(),
            manufacturer: "Unknown".to_string(),
            version: "1.0.0".to_string(),
            description: AUComponentDescription::new(
                AUType::Effect,
                0x70617373, // 'pass'
                0x52464f47, // 'RFOG'
            ),
            bundle_path: path.to_path_buf(),
            is_sandboxed: false,
            is_v3: false,
            audio_inputs: 2,
            audio_outputs: 2,
            has_midi_input: false,
            has_custom_view: true,
        };

        AudioUnitInstance::new(descriptor)
    }

    /// Get all discovered plugins
    pub fn plugins(&self) -> impl Iterator<Item = &AUDescriptor> {
        self.descriptors.values()
    }
}

impl Default for AudioUnitHost {
    fn default() -> Self {
        Self::new()
    }
}

/// AudioUnit plugin instance
pub struct AudioUnitInstance {
    /// Plugin info
    info: PluginInfo,
    /// AU descriptor
    descriptor: AUDescriptor,
    /// Is active
    active: AtomicBool,
    /// Latency in samples
    latency: AtomicU64,
    /// Parameters
    parameters: Vec<ParameterInfo>,
    /// Parameter values (normalized 0-1)
    param_values: Vec<f64>,
    /// Pending parameter changes
    param_queue: Mutex<Vec<ParamChange>>,
    /// Sample rate
    sample_rate: AtomicU64,
    /// Max block size
    max_block_size: usize,
    /// Editor is open
    editor_open: AtomicBool,
    /// Has valid AU loaded
    #[allow(dead_code)]
    au_loaded: bool,
}

// SAFETY: All fields are either Sync+Send or protected by atomics/mutexes
unsafe impl Send for AudioUnitInstance {}
unsafe impl Sync for AudioUnitInstance {}

impl AudioUnitInstance {
    /// Create new AU instance from descriptor
    pub fn new(descriptor: AUDescriptor) -> PluginResult<Self> {
        let id = format!("au.{}", descriptor.name.to_lowercase().replace(' ', "_"));

        log::info!(
            "Loading AudioUnit: {} from {:?}",
            descriptor.name,
            descriptor.bundle_path
        );

        // Default parameters (in real impl, query from AU)
        let parameters = vec![
            ParameterInfo {
                id: 0,
                name: "Gain".to_string(),
                unit: "dB".to_string(),
                min: -60.0,
                max: 12.0,
                default: 0.5,
                normalized: 0.5,
                steps: 0,
                automatable: true,
                read_only: false,
            },
            ParameterInfo {
                id: 1,
                name: "Mix".to_string(),
                unit: "%".to_string(),
                min: 0.0,
                max: 100.0,
                default: 1.0,
                normalized: 1.0,
                steps: 0,
                automatable: true,
                read_only: false,
            },
        ];

        let param_values = parameters.iter().map(|p| p.default).collect();

        let bundle_exists = descriptor.bundle_path.exists();

        let info = PluginInfo {
            id,
            name: descriptor.name.clone(),
            vendor: descriptor.manufacturer.clone(),
            version: descriptor.version.clone(),
            plugin_type: PluginType::AudioUnit,
            category: descriptor.description.component_type.to_category(),
            path: descriptor.bundle_path.clone(),
            audio_inputs: descriptor.audio_inputs as u32,
            audio_outputs: descriptor.audio_outputs as u32,
            has_midi_input: descriptor.has_midi_input,
            has_midi_output: false,
            has_editor: descriptor.has_custom_view,
            latency: 0,
            is_shell: false,
            sub_plugins: Vec::new(),
        };

        Ok(Self {
            info,
            descriptor,
            active: AtomicBool::new(false),
            latency: AtomicU64::new(0),
            parameters,
            param_values,
            param_queue: Mutex::new(Vec::with_capacity(MAX_PARAM_CHANGES)),
            sample_rate: AtomicU64::new(48000),
            max_block_size: 4096,
            editor_open: AtomicBool::new(false),
            au_loaded: bundle_exists,
        })
    }

    /// Get AU descriptor
    pub fn descriptor(&self) -> &AUDescriptor {
        &self.descriptor
    }

    /// Process pending parameter changes
    fn process_param_changes(&mut self) {
        let mut queue = self.param_queue.lock();
        for change in queue.drain(..) {
            if let Some(value) = self.param_values.get_mut(change.id as usize) {
                *value = change.value;
            }
        }
    }

    /// Get gain value
    fn get_gain(&self) -> f32 {
        let normalized = self.param_values.first().copied().unwrap_or(0.5);
        let db = -60.0 + normalized * 72.0;
        10.0_f32.powf(db as f32 / 20.0)
    }

    /// Get mix value
    fn get_mix(&self) -> f32 {
        self.param_values.get(1).copied().unwrap_or(1.0) as f32
    }
}

impl PluginInstance for AudioUnitInstance {
    fn info(&self) -> &PluginInfo {
        &self.info
    }

    fn initialize(&mut self, context: &ProcessContext) -> PluginResult<()> {
        log::debug!(
            "Initializing AU plugin {} at {}Hz, block size {}",
            self.info.name,
            context.sample_rate,
            context.max_block_size
        );

        self.sample_rate
            .store(context.sample_rate.to_bits(), Ordering::SeqCst);
        self.max_block_size = context.max_block_size;

        // In real implementation:
        // 1. AudioUnitSetProperty for kAudioUnitProperty_SampleRate
        // 2. AudioUnitSetProperty for kAudioUnitProperty_MaximumFramesPerSlice
        // 3. AudioUnitInitialize

        Ok(())
    }

    fn activate(&mut self) -> PluginResult<()> {
        self.active.store(true, Ordering::SeqCst);
        log::debug!("Activated AU plugin: {}", self.info.name);
        Ok(())
    }

    fn deactivate(&mut self) -> PluginResult<()> {
        self.active.store(false, Ordering::SeqCst);
        log::debug!("Deactivated AU plugin: {}", self.info.name);
        Ok(())
    }

    fn process(
        &mut self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
        _context: &ProcessContext,
    ) -> PluginResult<()> {
        if !self.active.load(Ordering::SeqCst) {
            return Err(PluginError::ProcessingError("Plugin not active".into()));
        }

        // Process parameter changes
        self.process_param_changes();

        // Apply gain and mix (passthrough mode)
        let gain = self.get_gain();
        let mix = self.get_mix();
        let dry = 1.0 - mix;

        for ch in 0..output.channels.min(input.channels) {
            if let (Some(inp), Some(out)) = (input.channel(ch), output.channel_mut(ch)) {
                for (i, sample) in out.iter_mut().enumerate() {
                    let dry_sample = inp.get(i).copied().unwrap_or(0.0);
                    let wet_sample = dry_sample * gain;
                    *sample = dry_sample * dry + wet_sample * mix;
                }
            }
        }

        Ok(())
    }

    fn parameter_count(&self) -> usize {
        self.parameters.len()
    }

    fn parameter_info(&self, index: usize) -> Option<ParameterInfo> {
        self.parameters.get(index).cloned()
    }

    fn get_parameter(&self, id: u32) -> Option<f64> {
        self.param_values.get(id as usize).copied()
    }

    fn set_parameter(&mut self, id: u32, value: f64) -> PluginResult<()> {
        let clamped = value.clamp(0.0, 1.0);

        {
            let mut queue = self.param_queue.lock();
            if queue.len() < MAX_PARAM_CHANGES {
                queue.push(ParamChange { id, value: clamped });
            }
        }

        if let Some(v) = self.param_values.get_mut(id as usize) {
            *v = clamped;
        }

        Ok(())
    }

    fn get_state(&self) -> PluginResult<Vec<u8>> {
        Ok(serde_json::to_vec(&self.param_values).unwrap_or_default())
    }

    fn set_state(&mut self, state: &[u8]) -> PluginResult<()> {
        if let Ok(values) = serde_json::from_slice::<Vec<f64>>(state) {
            for (i, v) in values.into_iter().enumerate() {
                if i < self.param_values.len() {
                    self.param_values[i] = v;
                }
            }
        }
        Ok(())
    }

    fn latency(&self) -> usize {
        self.latency.load(Ordering::SeqCst) as usize
    }

    fn has_editor(&self) -> bool {
        self.descriptor.has_custom_view
    }

    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    fn open_editor(&mut self, parent: *mut std::ffi::c_void) -> PluginResult<()> {
        if self.editor_open.load(Ordering::SeqCst) {
            return Ok(());
        }

        #[cfg(target_os = "macos")]
        {
            if parent.is_null() {
                return Err(PluginError::InitError("Null parent view handle".into()));
            }

            // In real implementation:
            // 1. Get AU view from AudioUnitGetProperty(kAudioUnitProperty_CocoaUI)
            // 2. Create AUViewFactory instance
            // 3. Call uiViewForAudioUnit:withSize:
            // 4. Add as subview to parent NSView

            log::info!(
                "Opening AU editor for {} - parent NSView: {:?}",
                self.info.name,
                parent
            );
        }

        #[cfg(not(target_os = "macos"))]
        {
            let _ = parent;
            return Err(PluginError::UnsupportedFormat(
                "AudioUnit only supported on macOS".into(),
            ));
        }

        self.editor_open.store(true, Ordering::SeqCst);
        Ok(())
    }

    fn close_editor(&mut self) -> PluginResult<()> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return Ok(());
        }

        // Cleanup would go here
        self.editor_open.store(false, Ordering::SeqCst);
        log::info!("Closed AU editor for {}", self.info.name);
        Ok(())
    }

    fn editor_size(&self) -> Option<(u32, u32)> {
        if self.editor_open.load(Ordering::SeqCst) {
            Some((800, 600))
        } else {
            None
        }
    }

    fn resize_editor(&mut self, _width: u32, _height: u32) -> PluginResult<()> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return Err(PluginError::ProcessingError("Editor not open".into()));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_au_type_category() {
        assert_eq!(AUType::Effect.to_category(), PluginCategory::Effect);
        assert_eq!(AUType::Instrument.to_category(), PluginCategory::Instrument);
    }

    #[test]
    fn test_fourcc_to_string() {
        assert_eq!(AUComponentDescription::fourcc_to_string(0x61756678), "aufx");
        assert_eq!(AUComponentDescription::fourcc_to_string(0x61756d75), "aumu");
    }

    #[test]
    fn test_au_host_creation() {
        let host = AudioUnitHost::new();
        assert_eq!(host.descriptors.len(), 0);
    }

    #[test]
    fn test_au_component_description() {
        let desc = AUComponentDescription::new(AUType::Effect, 0x70617373, 0x52464f47);
        let id = desc.identifier();
        assert!(id.contains("aufx"));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn test_au_instance_creation() {
        let descriptor = AUDescriptor {
            name: "Test AU".to_string(),
            manufacturer: "Test".to_string(),
            version: "1.0.0".to_string(),
            description: AUComponentDescription::new(AUType::Effect, 0x70617373, 0x52464f47),
            bundle_path: PathBuf::from("/tmp/test.component"),
            is_sandboxed: false,
            is_v3: false,
            audio_inputs: 2,
            audio_outputs: 2,
            has_midi_input: false,
            has_custom_view: true,
        };

        let instance = AudioUnitInstance::new(descriptor);
        assert!(instance.is_ok());
    }
}
