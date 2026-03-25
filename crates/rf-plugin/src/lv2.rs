//! LV2 Plugin Host
//!
//! LV2 audio plugin format support with dynamic library loading.
//! Uses minimal TTL parsing for manifest discovery.
//! Reference: https://lv2plug.in/

use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::scanner::{PluginCategory, PluginInfo, PluginType};
use crate::{
    AudioBuffer, ParameterInfo, PluginError, PluginInstance, PluginResult, ProcessContext,
};

// ═══════════════════════════════════════════════════════════════════════════
// LV2 C ABI DEFINITIONS (minimal subset for hosting)
// ═══════════════════════════════════════════════════════════════════════════

/// LV2 descriptor returned by lv2_descriptor() entry point
#[repr(C)]
struct Lv2PluginDescriptor {
    uri: *const c_char,
    instantiate: Option<
        unsafe extern "C" fn(
            descriptor: *const Lv2PluginDescriptor,
            sample_rate: f64,
            bundle_path: *const c_char,
            features: *const *const Lv2Feature,
        ) -> LV2Handle,
    >,
    connect_port:
        Option<unsafe extern "C" fn(instance: LV2Handle, port: u32, data_location: *mut c_void)>,
    activate: Option<unsafe extern "C" fn(instance: LV2Handle)>,
    run: Option<unsafe extern "C" fn(instance: LV2Handle, sample_count: u32)>,
    deactivate: Option<unsafe extern "C" fn(instance: LV2Handle)>,
    cleanup: Option<unsafe extern "C" fn(instance: LV2Handle)>,
    extension_data:
        Option<unsafe extern "C" fn(uri: *const c_char) -> *const c_void>,
}

/// LV2 feature (host capability declaration)
#[repr(C)]
struct Lv2Feature {
    uri: *const c_char,
    data: *const c_void,
}

/// Opaque plugin instance handle
type LV2Handle = *mut c_void;

/// Type of the lv2_descriptor() entry point function
type Lv2DescriptorFn = unsafe extern "C" fn(index: u32) -> *const Lv2PluginDescriptor;

// ═══════════════════════════════════════════════════════════════════════════
// LV2 PORT TYPES
// ═══════════════════════════════════════════════════════════════════════════

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

/// LV2 port metadata
#[derive(Debug, Clone)]
pub struct Lv2Port {
    pub index: u32,
    pub symbol: String,
    pub name: String,
    pub port_type: Lv2PortType,
    pub default_value: f32,
    pub min_value: f32,
    pub max_value: f32,
    pub is_logarithmic: bool,
    pub is_integer: bool,
    pub is_toggled: bool,
}

// ═══════════════════════════════════════════════════════════════════════════
// LV2 PLUGIN CLASS
// ═══════════════════════════════════════════════════════════════════════════

/// LV2 plugin class (from lv2:classes)
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Lv2Class {
    Plugin,
    AnalyserPlugin,
    ChorusPlugin,
    CombPlugin,
    CompressorPlugin,
    DelayPlugin,
    DistortionPlugin,
    DynamicsPlugin,
    EQPlugin,
    FilterPlugin,
    FlangerPlugin,
    GatePlugin,
    GeneratorPlugin,
    InstrumentPlugin,
    ModulatorPlugin,
    OscillatorPlugin,
    PhaserPlugin,
    ReverbPlugin,
    SimulatorPlugin,
    SpatialPlugin,
    SpectralPlugin,
    UtilityPlugin,
    WaveshaperPlugin,
    AmplifierPlugin,
    ConverterPlugin,
    ExpanderPlugin,
    FunctionPlugin,
    HighpassPlugin,
    LowpassPlugin,
    BandpassPlugin,
    MixerPlugin,
}

impl Lv2Class {
    pub fn to_category(&self) -> PluginCategory {
        match self {
            Self::AnalyserPlugin | Self::SpectralPlugin => PluginCategory::Analyzer,
            Self::InstrumentPlugin | Self::GeneratorPlugin | Self::OscillatorPlugin => {
                PluginCategory::Instrument
            }
            Self::UtilityPlugin | Self::ConverterPlugin | Self::MixerPlugin => {
                PluginCategory::Utility
            }
            _ => PluginCategory::Effect,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// LV2 DESCRIPTOR
// ═══════════════════════════════════════════════════════════════════════════

/// Scanned LV2 plugin descriptor
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Lv2Descriptor {
    pub uri: String,
    pub name: String,
    pub author: String,
    pub license: String,
    pub plugin_class: Lv2Class,
    pub required_features: Vec<String>,
    pub optional_features: Vec<String>,
    pub bundle_path: PathBuf,
    /// Binary name (relative to bundle)
    pub binary_name: String,
}

// ═══════════════════════════════════════════════════════════════════════════
// MINIMAL TTL PARSER
// ═══════════════════════════════════════════════════════════════════════════

/// Extract simple key-value pairs from TTL manifest files.
/// This is NOT a full Turtle parser — just enough for LV2 plugin discovery.
fn parse_ttl_simple(content: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();

    // Strip TTL comments (lines starting with # after whitespace)
    let content: String = content
        .lines()
        .filter(|line| !line.trim_start().starts_with('#'))
        .collect::<Vec<_>>()
        .join("\n");
    let content = &content;

    // Extract lv2:binary
    if let Some(cap) = regex_lite_find(content, r#"lv2:binary\s+<([^>]+)>"#) {
        map.insert("binary".to_string(), cap);
    }

    // Extract lv2:name / rdfs:label / doap:name
    for prefix in &["lv2:name", "rdfs:label", "doap:name"] {
        if let Some(cap) = regex_lite_find(content, &format!(r#"{}\s+"([^"]+)""#, prefix)) {
            map.insert("name".to_string(), cap);
            break;
        }
    }

    // Extract doap:developer / doap:maintainer
    if let Some(cap) = regex_lite_find(content, r#"foaf:name\s+"([^"]+)""#) {
        map.insert("author".to_string(), cap);
    }

    // Extract plugin URI from first subject
    if let Some(cap) = regex_lite_find(content, r#"<(http[^>]+)>\s+a\s+lv2:Plugin"#) {
        map.insert("uri".to_string(), cap);
    }

    map
}

/// Simple regex-like pattern match (no regex crate dependency)
fn regex_lite_find(text: &str, pattern: &str) -> Option<String> {
    // Split pattern into prefix + capture + suffix
    let cap_start = pattern.find('(')?;
    let cap_end = pattern.rfind(')')?;
    let prefix_pat = &pattern[..cap_start];
    let suffix_pat = &pattern[cap_end + 1..];

    // Very simplified matching — find prefix, then capture until suffix delimiter
    let prefix_clean = prefix_pat
        .replace(r"\s+", " ")
        .replace(r"\s", " ");

    // Search for prefix in text (case-insensitive search with whitespace normalization)
    let normalized = text.replace('\t', " ").replace('\n', " ");
    let lower = normalized.to_lowercase();
    let search = prefix_clean.to_lowercase().trim().to_string();

    let start_idx = lower.find(&search)?;
    let after_prefix = start_idx + search.len();

    // Skip whitespace
    let remaining = normalized[after_prefix..].trim_start();

    // Determine capture delimiter from pattern
    let cap_pattern = &pattern[cap_start + 1..cap_end];
    let end_char = if cap_pattern.contains('>') {
        '>'
    } else if cap_pattern.contains('"') {
        '"'
    } else {
        ' '
    };

    // Skip opening delimiter
    let capture_start = if remaining.starts_with('<') || remaining.starts_with('"') {
        1
    } else {
        0
    };

    let capture_text = &remaining[capture_start..];
    let end_idx = capture_text.find(end_char)?;
    Some(capture_text[..end_idx].to_string())
}

// ═══════════════════════════════════════════════════════════════════════════
// LV2 HOST
// ═══════════════════════════════════════════════════════════════════════════

/// LV2 plugin host with real dynamic library loading
pub struct Lv2Host {
    /// Scanned plugin descriptors
    plugins: HashMap<String, Lv2Descriptor>,
    /// World initialized flag
    world_initialized: bool,
}

impl Lv2Host {
    pub fn new() -> Self {
        Self {
            plugins: HashMap::new(),
            world_initialized: false,
        }
    }

    pub fn initialize(&mut self) {
        self.world_initialized = true;
    }

    /// Scan all standard LV2 paths
    pub fn scan(&mut self) -> PluginResult<Vec<Lv2Descriptor>> {
        if !self.world_initialized {
            self.initialize();
        }

        let mut all_descriptors = Vec::new();
        for path in Self::get_lv2_paths() {
            if path.exists() {
                match self.scan_directory(&path) {
                    Ok(descs) => all_descriptors.extend(descs),
                    Err(e) => log::warn!("Failed to scan LV2 directory {:?}: {}", path, e),
                }
            }
        }
        Ok(all_descriptors)
    }

    /// Get platform-specific LV2 plugin paths
    fn get_lv2_paths() -> Vec<PathBuf> {
        let mut paths = Vec::new();

        // Check LV2_PATH environment variable
        if let Ok(lv2_path) = std::env::var("LV2_PATH") {
            for p in lv2_path.split(':') {
                paths.push(PathBuf::from(p));
            }
        }

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
            paths.push(PathBuf::from(
                r"C:\Program Files\Common Files\LV2",
            ));
            if let Ok(appdata) = std::env::var("APPDATA") {
                paths.push(PathBuf::from(appdata).join("LV2"));
            }
        }

        paths
    }

    /// Scan directory for .lv2 bundles
    fn scan_directory(&mut self, path: &Path) -> PluginResult<Vec<Lv2Descriptor>> {
        let mut descriptors = Vec::new();

        if let Ok(entries) = std::fs::read_dir(path) {
            for entry in entries.flatten() {
                let entry_path = entry.path();
                if entry_path.is_dir()
                    && entry_path.extension().is_some_and(|e| e == "lv2")
                {
                    match self.scan_bundle(&entry_path) {
                        Ok(desc) => {
                            self.plugins.insert(desc.uri.clone(), desc.clone());
                            descriptors.push(desc);
                        }
                        Err(e) => {
                            log::debug!("Skipping LV2 bundle {:?}: {}", entry_path, e);
                        }
                    }
                }
            }
        }

        Ok(descriptors)
    }

    /// Scan a single LV2 bundle — parse manifest.ttl, discover binary
    fn scan_bundle(&self, bundle_path: &Path) -> PluginResult<Lv2Descriptor> {
        let manifest_path = bundle_path.join("manifest.ttl");
        if !manifest_path.exists() {
            return Err(PluginError::NotFound("manifest.ttl not found".into()));
        }

        let manifest_content = std::fs::read_to_string(&manifest_path)
            .map_err(|e| PluginError::IoError(e))?;

        let manifest_data = parse_ttl_simple(&manifest_content);

        // Extract binary name
        let binary_name = manifest_data
            .get("binary")
            .cloned()
            .unwrap_or_default();

        // Try to read plugin.ttl for more metadata
        let plugin_ttl_path = bundle_path.join("plugin.ttl");
        let plugin_data = if plugin_ttl_path.exists() {
            std::fs::read_to_string(&plugin_ttl_path)
                .map(|content| parse_ttl_simple(&content))
                .unwrap_or_default()
        } else {
            HashMap::new()
        };

        // Merge data (plugin.ttl overrides manifest.ttl)
        let uri = plugin_data
            .get("uri")
            .or(manifest_data.get("uri"))
            .cloned()
            .unwrap_or_else(|| {
                format!(
                    "urn:fluxforge:lv2:{}",
                    bundle_path
                        .file_stem()
                        .unwrap_or_default()
                        .to_string_lossy()
                )
            });

        let name = plugin_data
            .get("name")
            .or(manifest_data.get("name"))
            .cloned()
            .unwrap_or_else(|| {
                bundle_path
                    .file_stem()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .to_string()
            });

        let author = plugin_data
            .get("author")
            .or(manifest_data.get("author"))
            .cloned()
            .unwrap_or_default();

        Ok(Lv2Descriptor {
            uri,
            name,
            author,
            license: String::new(),
            plugin_class: Lv2Class::Plugin,
            required_features: Vec::new(),
            optional_features: Vec::new(),
            bundle_path: bundle_path.to_path_buf(),
            binary_name,
        })
    }

    /// Load an LV2 plugin by URI
    pub fn load(&self, uri: &str) -> PluginResult<Lv2PluginInstance> {
        let descriptor = self
            .plugins
            .get(uri)
            .ok_or_else(|| PluginError::NotFound(uri.to_string()))?;

        Lv2PluginInstance::load(descriptor)
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

// ═══════════════════════════════════════════════════════════════════════════
// LV2 PLUGIN INSTANCE
// ═══════════════════════════════════════════════════════════════════════════

/// Live LV2 plugin instance with loaded library
pub struct Lv2PluginInstance {
    info: PluginInfo,
    /// Loaded dynamic library (must stay alive)
    _library: Option<Arc<libloading::Library>>,
    /// LV2 plugin handle (returned by instantiate())
    handle: LV2Handle,
    /// Descriptor pointer (points into loaded library)
    descriptor: *const Lv2PluginDescriptor,
    /// Discovered ports
    ports: Vec<Lv2Port>,
    /// Port buffer values (for control ports)
    port_values: Vec<f32>,
    /// Pre-allocated audio input buffers
    audio_inputs: Vec<Vec<f32>>,
    /// Pre-allocated audio output buffers
    audio_outputs: Vec<Vec<f32>>,
    /// Is activated
    activated: bool,
    /// Sample rate
    sample_rate: f64,
}

// SAFETY: LV2 handle is a C pointer, accessed sequentially (never concurrent audio+UI)
unsafe impl Send for Lv2PluginInstance {}
unsafe impl Sync for Lv2PluginInstance {}

impl Lv2PluginInstance {
    /// Load an LV2 plugin from bundle descriptor
    pub fn load(desc: &Lv2Descriptor) -> PluginResult<Self> {
        // Determine binary path
        let binary_path = if desc.binary_name.is_empty() {
            // Try to find any .so/.dylib in bundle
            Self::find_binary(&desc.bundle_path)?
        } else {
            desc.bundle_path.join(&desc.binary_name)
        };

        if !binary_path.exists() {
            return Err(PluginError::LoadFailed(format!(
                "LV2 binary not found: {:?}",
                binary_path
            )));
        }

        // Load dynamic library
        let lib = unsafe {
            libloading::Library::new(&binary_path)
                .map_err(|e| PluginError::LoadFailed(format!("dlopen failed: {}", e)))?
        };
        let lib = Arc::new(lib);

        // Get lv2_descriptor entry point
        let lv2_descriptor_fn: libloading::Symbol<Lv2DescriptorFn> = unsafe {
            lib.get(b"lv2_descriptor\0")
                .map_err(|e| PluginError::LoadFailed(format!("lv2_descriptor not found: {}", e)))?
        };

        // Get first plugin descriptor (index 0)
        let descriptor_ptr = unsafe { lv2_descriptor_fn(0) };
        if descriptor_ptr.is_null() {
            return Err(PluginError::LoadFailed(
                "lv2_descriptor(0) returned null".into(),
            ));
        }

        let descriptor_ref = unsafe { &*descriptor_ptr };
        let plugin_uri = unsafe { cstr_to_string(descriptor_ref.uri) };

        // Instantiate plugin
        let bundle_path_cstr =
            std::ffi::CString::new(desc.bundle_path.to_string_lossy().as_ref())
                .map_err(|_| PluginError::LoadFailed("invalid bundle path".into()))?;

        // Null-terminated features array.
        // NOTE: Many LV2 plugins require urid:map feature. Without it, instantiate()
        // returns null for ~90% of real plugins. Adding urid:map requires implementing
        // a full URI↔integer mapping table. For now, only simple plugins (TAP, MDA) will load.
        // TODO: Implement LV2_URID_Map feature for broad plugin compatibility.
        let features: [*const Lv2Feature; 1] = [std::ptr::null()];

        let handle = if let Some(instantiate) = descriptor_ref.instantiate {
            unsafe {
                instantiate(
                    descriptor_ptr,
                    48000.0, // Default sample rate, updated on activate
                    bundle_path_cstr.as_ptr(),
                    features.as_ptr(),
                )
            }
        } else {
            return Err(PluginError::LoadFailed("no instantiate callback".into()));
        };

        if handle.is_null() {
            return Err(PluginError::LoadFailed("instantiate returned null".into()));
        }

        let category = desc.plugin_class.to_category();
        let has_midi = matches!(
            desc.plugin_class,
            Lv2Class::InstrumentPlugin | Lv2Class::GeneratorPlugin
        );

        let info = PluginInfo {
            id: plugin_uri.clone(),
            name: desc.name.clone(),
            vendor: desc.author.clone(),
            version: "1.0.0".to_string(),
            plugin_type: PluginType::Lv2,
            category,
            path: desc.bundle_path.clone(),
            audio_inputs: 2,
            audio_outputs: 2,
            has_midi_input: has_midi,
            has_midi_output: false,
            has_editor: false,
            latency: 0,
            is_shell: false,
            sub_plugins: Vec::new(),
        };

        Ok(Self {
            info,
            _library: Some(lib),
            handle,
            descriptor: descriptor_ptr,
            ports: Vec::new(),
            port_values: Vec::new(),
            audio_inputs: vec![vec![0.0f32; 4096]; 2],
            audio_outputs: vec![vec![0.0f32; 4096]; 2],
            activated: false,
            sample_rate: 48000.0,
        })
    }

    /// Find binary (.so/.dylib) in bundle directory
    fn find_binary(bundle_path: &Path) -> PluginResult<PathBuf> {
        if let Ok(entries) = std::fs::read_dir(bundle_path) {
            for entry in entries.flatten() {
                let path = entry.path();
                if let Some(ext) = path.extension() {
                    #[cfg(target_os = "macos")]
                    if ext == "dylib" {
                        return Ok(path);
                    }
                    #[cfg(target_os = "linux")]
                    if ext == "so" {
                        return Ok(path);
                    }
                    #[cfg(target_os = "windows")]
                    if ext == "dll" {
                        return Ok(path);
                    }
                }
            }
        }
        Err(PluginError::LoadFailed(
            "No binary found in LV2 bundle".into(),
        ))
    }

    /// Connect audio ports to plugin (called before run)
    /// Connect audio and control ports to plugin.
    /// NOTE: This assumes standard port layout [AudioIn0, AudioIn1, AudioOut0, AudioOut1, Control...].
    /// Real LV2 plugins may have arbitrary port ordering. For full compatibility, port indices
    /// should be discovered from plugin.ttl via RDF parsing. This works for simple stereo plugins
    /// (TAP, MDA, basic LV2 effects) but may fail for complex plugins with non-standard layouts.
    /// TODO: Parse plugin.ttl port definitions to discover actual port indices by type.
    unsafe fn connect_audio_ports(&mut self) {
        if let Some(connect) = (*self.descriptor).connect_port {
            // Connect audio inputs (assumed ports 0, 1)
            for (i, buf) in self.audio_inputs.iter_mut().enumerate() {
                connect(self.handle, i as u32, buf.as_mut_ptr() as *mut c_void);
            }
            // Connect audio outputs (assumed ports 2, 3 for stereo)
            for (i, buf) in self.audio_outputs.iter_mut().enumerate() {
                connect(
                    self.handle,
                    (i + self.audio_inputs.len()) as u32,
                    buf.as_mut_ptr() as *mut c_void,
                );
            }
            // Connect control ports (starting after audio ports)
            for (i, val) in self.port_values.iter_mut().enumerate() {
                let port_index = self.audio_inputs.len() + self.audio_outputs.len() + i;
                connect(
                    self.handle,
                    port_index as u32,
                    val as *mut f32 as *mut c_void,
                );
            }
        }
    }
}

impl Drop for Lv2PluginInstance {
    fn drop(&mut self) {
        if !self.handle.is_null() && !self.descriptor.is_null() {
            let desc = unsafe { &*self.descriptor };
            if self.activated {
                if let Some(deactivate) = desc.deactivate {
                    unsafe { deactivate(self.handle) };
                }
            }
            if let Some(cleanup) = desc.cleanup {
                unsafe { cleanup(self.handle) };
            }
            self.handle = std::ptr::null_mut();
            self.descriptor = std::ptr::null();
        }
    }
}

unsafe fn cstr_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        CStr::from_ptr(ptr).to_string_lossy().to_string()
    }
}

impl PluginInstance for Lv2PluginInstance {
    fn info(&self) -> &PluginInfo {
        &self.info
    }

    fn initialize(&mut self, context: &ProcessContext) -> PluginResult<()> {
        // NOTE: LV2 sample rate is set at instantiate() time (in load()).
        // If device sample rate differs from 48000, plugin should be re-instantiated.
        // For now, store the actual rate for reference. Full fix requires lazy instantiation.
        self.sample_rate = context.sample_rate;
        if (self.sample_rate - 48000.0).abs() > 1.0 {
            log::warn!(
                "LV2 plugin instantiated at 48000 Hz but device is {} Hz. Audio may be incorrect.",
                self.sample_rate
            );
        }
        Ok(())
    }

    fn activate(&mut self) -> PluginResult<()> {
        if self.handle.is_null() {
            return Err(PluginError::ProcessingError("Plugin not loaded".into()));
        }
        // Connect ports before activation
        unsafe { self.connect_audio_ports() };

        let desc = unsafe { &*self.descriptor };
        if let Some(activate) = desc.activate {
            unsafe { activate(self.handle) };
        }
        self.activated = true;
        Ok(())
    }

    fn deactivate(&mut self) -> PluginResult<()> {
        if !self.handle.is_null() && self.activated {
            let desc = unsafe { &*self.descriptor };
            if let Some(deactivate) = desc.deactivate {
                unsafe { deactivate(self.handle) };
            }
        }
        self.activated = false;
        Ok(())
    }

    fn process(
        &mut self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
        _midi_in: &rf_core::MidiBuffer,
        _midi_out: &mut rf_core::MidiBuffer,
        _context: &ProcessContext,
    ) -> PluginResult<()> {
        if self.handle.is_null() || !self.activated {
            // Passthrough
            for (i, out_ch) in output.data.iter_mut().enumerate() {
                if let Some(in_ch) = input.data.get(i) {
                    out_ch.copy_from_slice(in_ch);
                }
            }
            return Ok(());
        }

        // Cap frames to pre-allocated buffer size (4096) — prevents buffer overflow
        let frames = input.samples.min(self.audio_inputs.first().map_or(4096, |b| b.len()));

        // Copy input to pre-allocated LV2 input buffers
        for (i, buf) in self.audio_inputs.iter_mut().enumerate() {
            if let Some(in_ch) = input.data.get(i) {
                let len = frames.min(buf.len()).min(in_ch.len());
                buf[..len].copy_from_slice(&in_ch[..len]);
            }
        }

        // Clear output buffers
        for buf in &mut self.audio_outputs {
            let len = frames.min(buf.len());
            buf[..len].fill(0.0);
        }

        // Run plugin
        let desc = unsafe { &*self.descriptor };
        if let Some(run) = desc.run {
            unsafe { run(self.handle, frames as u32) };
        }

        // Copy LV2 output to AudioBuffer
        for (i, out_ch) in output.data.iter_mut().enumerate() {
            if let Some(buf) = self.audio_outputs.get(i) {
                let len = frames.min(buf.len()).min(out_ch.len());
                out_ch[..len].copy_from_slice(&buf[..len]);
            }
        }

        Ok(())
    }

    fn parameter_count(&self) -> usize {
        self.port_values.len()
    }

    fn parameter_info(&self, index: usize) -> Option<ParameterInfo> {
        self.ports
            .iter()
            .filter(|p| matches!(p.port_type, Lv2PortType::ControlInput))
            .nth(index)
            .map(|port| ParameterInfo {
                id: port.index,
                name: port.name.clone(),
                unit: String::new(),
                min: port.min_value as f64,
                max: port.max_value as f64,
                default: port.default_value as f64,
                normalized: 0.5,
                steps: if port.is_integer { 1 } else { 0 },
                automatable: true,
                read_only: false,
            })
    }

    fn get_parameter(&self, id: u32) -> Option<f64> {
        self.port_values.get(id as usize).map(|v| *v as f64)
    }

    fn set_parameter(&mut self, id: u32, value: f64) -> PluginResult<()> {
        if let Some(val) = self.port_values.get_mut(id as usize) {
            *val = value as f32;
        }
        Ok(())
    }

    fn get_state(&self) -> PluginResult<Vec<u8>> {
        Ok(Vec::new()) // TODO: LV2 state extension
    }

    fn set_state(&mut self, _state: &[u8]) -> PluginResult<()> {
        Ok(())
    }

    fn latency(&self) -> usize {
        0
    }

    fn has_editor(&self) -> bool {
        false // TODO: LV2 UI extension
    }

    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    fn open_editor(&mut self, _parent: *mut std::ffi::c_void) -> PluginResult<()> {
        Err(PluginError::UnsupportedFormat(
            "LV2 GUI not yet implemented".into(),
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
        assert!(host.plugins.is_empty());
    }

    #[test]
    fn test_lv2_class_category() {
        assert_eq!(
            Lv2Class::InstrumentPlugin.to_category(),
            PluginCategory::Instrument
        );
        assert_eq!(
            Lv2Class::CompressorPlugin.to_category(),
            PluginCategory::Effect
        );
    }

    #[test]
    fn test_ttl_parse_binary() {
        let ttl = r#"
            @prefix lv2: <http://lv2plug.in/ns/lv2core#> .
            <http://example.org/test> a lv2:Plugin ;
                lv2:binary <test.so> .
        "#;
        let data = parse_ttl_simple(ttl);
        assert_eq!(data.get("binary").unwrap(), "test.so");
    }
}
