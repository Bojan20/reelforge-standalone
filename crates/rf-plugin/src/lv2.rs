//! LV2 Plugin Host
//!
//! Linux Audio plugin format (cross-platform)
//! Reference: https://lv2plug.in/

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::scanner::{PluginCategory, PluginInfo, PluginType};
use crate::{
    AudioBuffer, ParameterInfo, PluginError, PluginInstance, PluginResult, ProcessContext,
};

/// LV2 plugin descriptor
#[derive(Debug, Clone)]
pub struct Lv2Descriptor {
    /// Plugin URI (unique identifier)
    pub uri: String,
    /// Display name
    pub name: String,
    /// Author
    pub author: String,
    /// License
    pub license: String,
    /// Plugin class (effect, instrument, etc.)
    pub plugin_class: Lv2Class,
    /// Required features
    pub required_features: Vec<String>,
    /// Optional features
    pub optional_features: Vec<String>,
    /// Bundle path
    pub bundle_path: PathBuf,
}

/// LV2 plugin class
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Lv2Class {
    Plugin,
    AnalyserPlugin,
    ChorusPlugin,
    CombPlugin,
    CompressorPlugin,
    ConstantPlugin,
    ConverterPlugin,
    DelayPlugin,
    DistortionPlugin,
    DynamicsPlugin,
    EQPlugin,
    ExpanderPlugin,
    FilterPlugin,
    FlangerPlugin,
    GatePlugin,
    GeneratorPlugin,
    HighpassPlugin,
    InstrumentPlugin,
    LimiterPlugin,
    LowpassPlugin,
    MIDIPlugin,
    ModulatorPlugin,
    MultiEQPlugin,
    OscillatorPlugin,
    ParametricEQPlugin,
    PhaserPlugin,
    PitchPlugin,
    ReverbPlugin,
    SimulatorPlugin,
    SpatialPlugin,
    SpectralPlugin,
    UtilityPlugin,
    WaveshaperPlugin,
}

impl Lv2Class {
    pub fn as_uri(&self) -> &'static str {
        match self {
            Self::Plugin => "http://lv2plug.in/ns/lv2core#Plugin",
            Self::AnalyserPlugin => "http://lv2plug.in/ns/lv2core#AnalyserPlugin",
            Self::ChorusPlugin => "http://lv2plug.in/ns/lv2core#ChorusPlugin",
            Self::CombPlugin => "http://lv2plug.in/ns/lv2core#CombPlugin",
            Self::CompressorPlugin => "http://lv2plug.in/ns/lv2core#CompressorPlugin",
            Self::ConstantPlugin => "http://lv2plug.in/ns/lv2core#ConstantPlugin",
            Self::ConverterPlugin => "http://lv2plug.in/ns/lv2core#ConverterPlugin",
            Self::DelayPlugin => "http://lv2plug.in/ns/lv2core#DelayPlugin",
            Self::DistortionPlugin => "http://lv2plug.in/ns/lv2core#DistortionPlugin",
            Self::DynamicsPlugin => "http://lv2plug.in/ns/lv2core#DynamicsPlugin",
            Self::EQPlugin => "http://lv2plug.in/ns/lv2core#EQPlugin",
            Self::ExpanderPlugin => "http://lv2plug.in/ns/lv2core#ExpanderPlugin",
            Self::FilterPlugin => "http://lv2plug.in/ns/lv2core#FilterPlugin",
            Self::FlangerPlugin => "http://lv2plug.in/ns/lv2core#FlangerPlugin",
            Self::GatePlugin => "http://lv2plug.in/ns/lv2core#GatePlugin",
            Self::GeneratorPlugin => "http://lv2plug.in/ns/lv2core#GeneratorPlugin",
            Self::HighpassPlugin => "http://lv2plug.in/ns/lv2core#HighpassPlugin",
            Self::InstrumentPlugin => "http://lv2plug.in/ns/lv2core#InstrumentPlugin",
            Self::LimiterPlugin => "http://lv2plug.in/ns/lv2core#LimiterPlugin",
            Self::LowpassPlugin => "http://lv2plug.in/ns/lv2core#LowpassPlugin",
            Self::MIDIPlugin => "http://lv2plug.in/ns/lv2core#MIDIPlugin",
            Self::ModulatorPlugin => "http://lv2plug.in/ns/lv2core#ModulatorPlugin",
            Self::MultiEQPlugin => "http://lv2plug.in/ns/lv2core#MultiEQPlugin",
            Self::OscillatorPlugin => "http://lv2plug.in/ns/lv2core#OscillatorPlugin",
            Self::ParametricEQPlugin => "http://lv2plug.in/ns/lv2core#ParametricEQPlugin",
            Self::PhaserPlugin => "http://lv2plug.in/ns/lv2core#PhaserPlugin",
            Self::PitchPlugin => "http://lv2plug.in/ns/lv2core#PitchPlugin",
            Self::ReverbPlugin => "http://lv2plug.in/ns/lv2core#ReverbPlugin",
            Self::SimulatorPlugin => "http://lv2plug.in/ns/lv2core#SimulatorPlugin",
            Self::SpatialPlugin => "http://lv2plug.in/ns/lv2core#SpatialPlugin",
            Self::SpectralPlugin => "http://lv2plug.in/ns/lv2core#SpectralPlugin",
            Self::UtilityPlugin => "http://lv2plug.in/ns/lv2core#UtilityPlugin",
            Self::WaveshaperPlugin => "http://lv2plug.in/ns/lv2core#WaveshaperPlugin",
        }
    }

    pub fn to_category(&self) -> PluginCategory {
        match self {
            Self::AnalyserPlugin => PluginCategory::Analyzer,
            Self::InstrumentPlugin | Self::GeneratorPlugin | Self::OscillatorPlugin => {
                PluginCategory::Instrument
            }
            Self::UtilityPlugin | Self::ConverterPlugin | Self::ConstantPlugin => {
                PluginCategory::Utility
            }
            _ => PluginCategory::Effect,
        }
    }
}

/// LV2 port type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Lv2PortType {
    AudioInput,
    AudioOutput,
    ControlInput,
    ControlOutput,
    AtomInput,
    AtomOutput,
    CVInput,
    CVOutput,
}

/// LV2 port descriptor
#[derive(Debug, Clone)]
pub struct Lv2Port {
    /// Port index
    pub index: u32,
    /// Port symbol (code-safe name)
    pub symbol: String,
    /// Port name (display)
    pub name: String,
    /// Port type
    pub port_type: Lv2PortType,
    /// Default value
    pub default: f32,
    /// Minimum value
    pub minimum: f32,
    /// Maximum value
    pub maximum: f32,
    /// Is logarithmic
    pub logarithmic: bool,
    /// Is integer
    pub integer: bool,
    /// Is toggled (boolean)
    pub toggled: bool,
}

/// LV2 plugin host
pub struct Lv2Host {
    /// Discovered plugins
    plugins: HashMap<String, Lv2Descriptor>,
    /// World (lilv world in real impl)
    world_initialized: bool,
}

impl Lv2Host {
    pub fn new() -> Self {
        Self {
            plugins: HashMap::new(),
            world_initialized: false,
        }
    }

    /// Initialize LV2 world and scan for plugins
    pub fn initialize(&mut self) -> PluginResult<()> {
        // In real implementation:
        // 1. Create lilv world
        // 2. Load all installed plugins
        // 3. Cache descriptors
        self.world_initialized = true;
        Ok(())
    }

    /// Scan for LV2 plugins
    pub fn scan(&mut self) -> PluginResult<Vec<Lv2Descriptor>> {
        let mut descriptors = Vec::new();

        // Standard LV2 paths
        let paths = self.get_lv2_paths();

        for path in paths {
            if path.exists() {
                self.scan_directory(&path, &mut descriptors)?;
            }
        }

        // Cache discovered plugins
        for desc in &descriptors {
            self.plugins.insert(desc.uri.clone(), desc.clone());
        }

        Ok(descriptors)
    }

    fn get_lv2_paths(&self) -> Vec<PathBuf> {
        let mut paths = Vec::new();

        #[cfg(target_os = "linux")]
        {
            paths.push(PathBuf::from("/usr/lib/lv2"));
            paths.push(PathBuf::from("/usr/local/lib/lv2"));
            if let Some(home) = dirs_next::home_dir() {
                paths.push(home.join(".lv2"));
            }
        }

        #[cfg(target_os = "macos")]
        {
            paths.push(PathBuf::from("/Library/Audio/Plug-Ins/LV2"));
            if let Some(home) = dirs_next::home_dir() {
                paths.push(home.join("Library/Audio/Plug-Ins/LV2"));
            }
        }

        #[cfg(target_os = "windows")]
        {
            paths.push(PathBuf::from("C:\\Program Files\\Common Files\\LV2"));
            if let Some(app_data) = dirs_next::data_local_dir() {
                paths.push(app_data.join("LV2"));
            }
        }

        // Check LV2_PATH environment variable
        if let Ok(lv2_path) = std::env::var("LV2_PATH") {
            for path in lv2_path.split(':') {
                paths.push(PathBuf::from(path));
            }
        }

        paths
    }

    fn scan_directory(
        &self,
        path: &Path,
        descriptors: &mut Vec<Lv2Descriptor>,
    ) -> PluginResult<()> {
        if let Ok(entries) = std::fs::read_dir(path) {
            for entry in entries.flatten() {
                let entry_path = entry.path();
                if entry_path.is_dir() {
                    // LV2 bundles are directories with .lv2 extension
                    if entry_path.extension().is_some_and(|e| e == "lv2")
                        && let Ok(desc) = self.scan_bundle(&entry_path)
                    {
                        descriptors.push(desc);
                    }
                }
            }
        }
        Ok(())
    }

    fn scan_bundle(&self, bundle_path: &Path) -> PluginResult<Lv2Descriptor> {
        // In real implementation, parse manifest.ttl and plugin.ttl
        let name = bundle_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown")
            .replace(".lv2", "");

        Ok(Lv2Descriptor {
            uri: format!("http://example.org/plugins/{}", name.to_lowercase()),
            name,
            author: String::new(),
            license: String::new(),
            plugin_class: Lv2Class::Plugin,
            required_features: Vec::new(),
            optional_features: Vec::new(),
            bundle_path: bundle_path.to_path_buf(),
        })
    }

    /// Load a plugin instance
    pub fn load(&self, uri: &str) -> PluginResult<Lv2PluginInstance> {
        let descriptor = self
            .plugins
            .get(uri)
            .ok_or_else(|| PluginError::NotFound(uri.to_string()))?;

        Lv2PluginInstance::new(descriptor.clone())
    }

    /// Get all discovered plugins
    pub fn plugins(&self) -> impl Iterator<Item = &Lv2Descriptor> {
        self.plugins.values()
    }
}

impl Default for Lv2Host {
    fn default() -> Self {
        Self::new()
    }
}

/// LV2 plugin instance
pub struct Lv2PluginInstance {
    descriptor: Lv2Descriptor,
    info: PluginInfo,
    ports: Vec<Lv2Port>,
    /// Port values (control ports)
    port_values: Vec<f32>,
    /// Audio buffers
    audio_inputs: Vec<Vec<f32>>,
    audio_outputs: Vec<Vec<f32>>,
    /// Is activated
    activated: bool,
    sample_rate: f64,
}

impl Lv2PluginInstance {
    pub fn new(descriptor: Lv2Descriptor) -> PluginResult<Self> {
        let info = PluginInfo {
            id: format!("lv2.{}", descriptor.name.to_lowercase().replace(' ', "_")),
            name: descriptor.name.clone(),
            vendor: descriptor.author.clone(),
            version: "1.0.0".to_string(),
            plugin_type: PluginType::Clap, // Using Clap as placeholder for LV2
            category: descriptor.plugin_class.to_category(),
            path: descriptor.bundle_path.clone(),
            audio_inputs: 2,
            audio_outputs: 2,
            has_midi_input: false,
            has_midi_output: false,
            has_editor: false, // LV2 UI is separate
            latency: 0,
            is_shell: false,
            sub_plugins: Vec::new(),
        };

        Ok(Self {
            descriptor,
            info,
            ports: Vec::new(),
            port_values: Vec::new(),
            audio_inputs: Vec::new(),
            audio_outputs: Vec::new(),
            activated: false,
            sample_rate: 48000.0,
        })
    }

    /// Get the plugin descriptor
    pub fn descriptor(&self) -> &Lv2Descriptor {
        &self.descriptor
    }
}

impl PluginInstance for Lv2PluginInstance {
    fn info(&self) -> &PluginInfo {
        &self.info
    }

    fn initialize(&mut self, context: &ProcessContext) -> PluginResult<()> {
        self.sample_rate = context.sample_rate;

        // Allocate audio buffers
        let block_size = context.max_block_size;
        self.audio_inputs = vec![vec![0.0f32; block_size]; 2];
        self.audio_outputs = vec![vec![0.0f32; block_size]; 2];

        Ok(())
    }

    fn activate(&mut self) -> PluginResult<()> {
        self.activated = true;
        Ok(())
    }

    fn deactivate(&mut self) -> PluginResult<()> {
        self.activated = false;
        Ok(())
    }

    fn process(
        &mut self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
        _context: &ProcessContext,
    ) -> PluginResult<()> {
        // Pass through
        for (i, out_ch) in output.data.iter_mut().enumerate() {
            if let Some(in_ch) = input.data.get(i) {
                out_ch.copy_from_slice(in_ch);
            }
        }
        Ok(())
    }

    fn parameter_count(&self) -> usize {
        self.ports
            .iter()
            .filter(|p| matches!(p.port_type, Lv2PortType::ControlInput))
            .count()
    }

    fn parameter_info(&self, index: usize) -> Option<ParameterInfo> {
        let control_ports: Vec<_> = self
            .ports
            .iter()
            .filter(|p| matches!(p.port_type, Lv2PortType::ControlInput))
            .collect();

        control_ports.get(index).map(|port| ParameterInfo {
            id: port.index,
            name: port.name.clone(),
            unit: String::new(),
            min: port.minimum as f64,
            max: port.maximum as f64,
            default: port.default as f64,
            normalized: 0.5,
            steps: if port.integer {
                (port.maximum - port.minimum) as u32
            } else {
                0
            },
            automatable: true,
            read_only: false,
        })
    }

    fn get_parameter(&self, id: u32) -> Option<f64> {
        self.port_values.get(id as usize).map(|&v| v as f64)
    }

    fn set_parameter(&mut self, id: u32, value: f64) -> PluginResult<()> {
        if let Some(v) = self.port_values.get_mut(id as usize) {
            *v = value as f32;
        }
        Ok(())
    }

    fn get_state(&self) -> PluginResult<Vec<u8>> {
        Ok(Vec::new())
    }

    fn set_state(&mut self, _state: &[u8]) -> PluginResult<()> {
        Ok(())
    }

    fn latency(&self) -> usize {
        0
    }

    fn has_editor(&self) -> bool {
        false
    }

    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    fn open_editor(&mut self, _parent: *mut std::ffi::c_void) -> PluginResult<()> {
        Err(PluginError::UnsupportedFormat(
            "LV2 UI not implemented".to_string(),
        ))
    }

    fn close_editor(&mut self) -> PluginResult<()> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lv2_host_creation() {
        let host = Lv2Host::new();
        assert!(!host.world_initialized);
    }

    #[test]
    fn test_lv2_class() {
        assert!(
            Lv2Class::CompressorPlugin
                .as_uri()
                .contains("CompressorPlugin")
        );
        assert_eq!(
            Lv2Class::AnalyserPlugin.to_category(),
            PluginCategory::Analyzer
        );
    }

    #[test]
    fn test_lv2_paths() {
        let host = Lv2Host::new();
        let paths = host.get_lv2_paths();
        assert!(!paths.is_empty());
    }
}
