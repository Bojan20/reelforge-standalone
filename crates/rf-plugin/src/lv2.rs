//! LV2 Plugin Host
//!
//! LV2 audio plugin format support with dynamic library loading.
//! Uses minimal TTL parsing for manifest discovery.
//! Reference: <https://lv2plug.in/>

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
// LV2 URID MAP (required by ~90% of real plugins)
// ═══════════════════════════════════════════════════════════════════════════

/// URID (URI → integer) mapping table
/// Thread-safe, global lifetime — plugins expect this to outlive them
use std::sync::Mutex;
use std::sync::LazyLock;

static URID_MAP: LazyLock<Mutex<UridMapState>> = LazyLock::new(|| {
    let mut state = UridMapState {
        uri_to_id: HashMap::new(),
        id_to_uri: Vec::new(),
    };
    // Pre-register common URIs
    for uri in [
        "http://lv2plug.in/ns/ext/midi#MidiEvent",
        "http://lv2plug.in/ns/ext/atom#Blank",
        "http://lv2plug.in/ns/ext/atom#Object",
        "http://lv2plug.in/ns/ext/atom#Float",
        "http://lv2plug.in/ns/ext/atom#Int",
        "http://lv2plug.in/ns/ext/atom#Long",
        "http://lv2plug.in/ns/ext/atom#Double",
        "http://lv2plug.in/ns/ext/atom#String",
        "http://lv2plug.in/ns/ext/atom#Literal",
        "http://lv2plug.in/ns/ext/atom#Chunk",
        "http://lv2plug.in/ns/ext/atom#Sequence",
        "http://lv2plug.in/ns/ext/atom#URID",
        "http://lv2plug.in/ns/ext/atom#Path",
        "http://lv2plug.in/ns/ext/patch#Set",
        "http://lv2plug.in/ns/ext/patch#Get",
        "http://lv2plug.in/ns/ext/patch#property",
        "http://lv2plug.in/ns/ext/patch#value",
    ] {
        let id = state.id_to_uri.len() as u32 + 1; // URID 0 is invalid
        state.uri_to_id.insert(uri.to_string(), id);
        state.id_to_uri.push(uri.to_string());
    }
    Mutex::new(state)
});

struct UridMapState {
    uri_to_id: HashMap<String, u32>,
    id_to_uri: Vec<String>,
}

/// LV2_URID_Map C interface
#[repr(C)]
struct Lv2UridMap {
    handle: *mut c_void,
    map: unsafe extern "C" fn(handle: *mut c_void, uri: *const c_char) -> u32,
}

/// LV2_URID_Unmap C interface
#[repr(C)]
struct Lv2UridUnmap {
    handle: *mut c_void,
    unmap: unsafe extern "C" fn(handle: *mut c_void, urid: u32) -> *const c_char,
}

/// URID map callback — called by plugins to map URI → integer
unsafe extern "C" fn urid_map_callback(_handle: *mut c_void, uri: *const c_char) -> u32 {
    if uri.is_null() { return 0; }
    let uri_str = unsafe { CStr::from_ptr(uri) }.to_string_lossy().to_string();
    // BUG#32 FIX: recover from mutex poison instead of crashing the host
    let mut map = URID_MAP.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(&id) = map.uri_to_id.get(&uri_str) {
        return id;
    }
    // Allocate new URID
    let id = map.id_to_uri.len() as u32 + 1;
    map.uri_to_id.insert(uri_str.clone(), id);
    map.id_to_uri.push(uri_str);
    id
}

/// URID unmap callback — called by plugins to get URI from integer
unsafe extern "C" fn urid_unmap_callback(_handle: *mut c_void, urid: u32) -> *const c_char {
    if urid == 0 { return std::ptr::null(); }
    // BUG#32 FIX: recover from mutex poison instead of crashing the host
    let map = URID_MAP.lock().unwrap_or_else(|e| e.into_inner());
    let idx = (urid - 1) as usize;
    if idx < map.id_to_uri.len() {
        // Return pointer to CString in a thread-local (stable for duration of plugin call)
        thread_local! {
            static UNMAP_BUF: std::cell::RefCell<std::ffi::CString> =
                std::cell::RefCell::new(std::ffi::CString::default());
        }
        let uri = map.id_to_uri[idx].clone();
        UNMAP_BUF.with(|buf| {
            *buf.borrow_mut() = std::ffi::CString::new(uri).unwrap_or_default();
            buf.borrow().as_ptr()
        })
    } else {
        std::ptr::null()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// LV2 ATOM BUFFER (for MIDI events)
// ═══════════════════════════════════════════════════════════════════════════

/// LV2 Atom header
#[repr(C)]
#[derive(Clone, Copy)]
struct Lv2Atom {
    size: u32,
    atom_type: u32, // URID
}

/// LV2 Atom Sequence (container for timed events)
#[repr(C)]
struct Lv2AtomSequence {
    atom: Lv2Atom,     // type = atom:Sequence
    body_pad: u32,     // unit (usually 0 for frames)
    body_pad2: u32,    // pad
    // followed by sequence of Lv2AtomEvent
}

/// LV2 Atom Event (single event in a sequence)
#[repr(C)]
struct Lv2AtomEvent {
    time_frames: i64,  // time in frames (or beats)
    body: Lv2Atom,     // event body (type + size)
    // followed by body.size bytes of data
}

/// Pre-allocated Atom buffer for MIDI input/output
struct AtomBuffer {
    data: Vec<u8>,
    capacity: usize,
}

impl AtomBuffer {
    fn new(capacity: usize) -> Self {
        let mut data = vec![0u8; capacity];
        // Initialize as empty Atom Sequence
        let seq = data.as_mut_ptr() as *mut Lv2AtomSequence;
        unsafe {
            (*seq).atom.size = 8; // just the body header (pad + pad2)
            (*seq).atom.atom_type = 0; // will be set to atom:Sequence URID at connect time
            (*seq).body_pad = 0;
            (*seq).body_pad2 = 0;
        }
        Self { data, capacity }
    }

    fn clear(&mut self, sequence_urid: u32) {
        let seq = self.data.as_mut_ptr() as *mut Lv2AtomSequence;
        unsafe {
            (*seq).atom.size = 8;
            (*seq).atom.atom_type = sequence_urid;
            (*seq).body_pad = 0;
            (*seq).body_pad2 = 0;
        }
    }

    fn as_mut_ptr(&mut self) -> *mut c_void {
        self.data.as_mut_ptr() as *mut c_void
    }

    /// Append a raw MIDI event to the Atom sequence.
    ///
    /// Format per LV2 Atom spec:
    ///   [time_frames: i64][body.size: u32][body.type: u32][data: [u8; data.len()]][padding to 8-byte]
    ///
    /// The sequence header `atom.size` is updated to include the new event.
    fn push_midi_event(&mut self, time_frames: i64, midi_urid: u32, raw_bytes: &[u8]) {
        if raw_bytes.is_empty() {
            return;
        }

        let data_size = raw_bytes.len() as u32;
        // event entry size: time(8) + atom header(8) + data, rounded up to 8-byte align
        let unpadded = 8u32 + 8 + data_size;
        let padded = (unpadded + 7) & !7;

        // Current body size (includes the 8-byte body_pad/body_pad2 prefix)
        let seq_ptr = self.data.as_mut_ptr() as *mut Lv2AtomSequence;
        let current_body_size = unsafe { (*seq_ptr).atom.size };

        // Events start at offset = 8 (Lv2Atom header) + current_body_size
        let offset = (8 + current_body_size) as usize;
        let needed = offset + padded as usize;

        if needed > self.capacity {
            // Buffer overflow — skip event silently (audio thread cannot panic)
            return;
        }

        // Extend Vec data length if needed (capacity was pre-allocated, just moving len)
        if self.data.len() < needed {
            self.data.resize(needed, 0);
        }

        // Write Lv2AtomEvent header at offset
        unsafe {
            let event_ptr = self.data.as_mut_ptr().add(offset) as *mut Lv2AtomEvent;
            (*event_ptr).time_frames = time_frames;
            (*event_ptr).body.size = data_size;
            (*event_ptr).body.atom_type = midi_urid;
        }

        // Copy MIDI data bytes after the event header
        let data_offset = offset + std::mem::size_of::<Lv2AtomEvent>();
        self.data[data_offset..data_offset + raw_bytes.len()].copy_from_slice(raw_bytes);

        // Zero padding bytes for alignment
        let pad_start = data_offset + raw_bytes.len();
        let pad_end = offset + padded as usize;
        if pad_end > pad_start {
            self.data[pad_start..pad_end].fill(0);
        }

        // Update sequence body size to include this event
        unsafe {
            (*seq_ptr).atom.size += padded;
        }
    }
}

// LV2 Feature URIs
const LV2_URID_MAP_URI: &[u8] = b"http://lv2plug.in/ns/ext/urid#map\0";
const LV2_URID_UNMAP_URI: &[u8] = b"http://lv2plug.in/ns/ext/urid#unmap\0";
const LV2_STATE_INTERFACE_URI: &[u8] = b"http://lv2plug.in/ns/ext/state#interface\0";

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
    /// UI extension: path to UI bundle (may be same as plugin bundle)
    pub ui_bundle_path: Option<PathBuf>,
    /// UI binary name within ui_bundle_path
    pub ui_binary_name: Option<String>,
    /// UI type URI (CocoaUI / X11UI / WindowsUI)
    pub ui_type_uri: Option<String>,
    /// UI plugin URI (identifies which UI within the bundle)
    pub ui_uri: Option<String>,
}

// ═══════════════════════════════════════════════════════════════════════════
// LV2 UI C ABI DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════

/// LV2 UI Descriptor (returned by lv2ui_descriptor())
#[repr(C)]
struct Lv2UiDescriptor {
    uri: *const c_char,
    instantiate: Option<
        unsafe extern "C" fn(
            descriptor: *const Lv2UiDescriptor,
            plugin_uri: *const c_char,
            bundle_path: *const c_char,
            write_function: Option<unsafe extern "C" fn(*mut c_void, u32, u32, u32, *const c_void)>,
            controller: *mut c_void,
            widget: *mut *mut c_void, // out: native widget handle
            features: *const *const Lv2Feature,
        ) -> *mut c_void, // LV2UI_Handle
    >,
    cleanup: Option<unsafe extern "C" fn(handle: *mut c_void)>,
    port_event: Option<
        unsafe extern "C" fn(handle: *mut c_void, port_index: u32, buffer_size: u32, format: u32, buffer: *const c_void)
    >,
    extension_data: Option<unsafe extern "C" fn(uri: *const c_char) -> *const c_void>,
}

/// Type of the lv2ui_descriptor() entry point
type Lv2UiDescriptorFn = unsafe extern "C" fn(index: u32) -> *const Lv2UiDescriptor;

// LV2 UI type URIs
const LV2_UI_COCOA: &str = "http://lv2plug.in/ns/extensions/ui#CocoaUI";
const LV2_UI_X11: &str = "http://lv2plug.in/ns/extensions/ui#X11UI";
const LV2_UI_WINDOWS: &str = "http://lv2plug.in/ns/extensions/ui#WindowsUI";

// LV2 UI Idle interface (host calls idle() periodically for toolkit event processing)
const LV2_UI_IDLE_URI: &str = "http://lv2plug.in/ns/extensions/ui#idleInterface";
// LV2 UI Resize interface (host queries/sets preferred UI size)
const LV2_UI_RESIZE_URI: &str = "http://lv2plug.in/ns/extensions/ui#resize";

/// LV2 UI Idle Interface — returned by extension_data(idleInterface URI)
#[repr(C)]
struct Lv2UiIdleInterface {
    /// Returns 0 on success, non-zero if UI should be closed
    idle: unsafe extern "C" fn(handle: *mut c_void) -> i32,
}

/// LV2 UI Resize Interface (plugin-side) — returned by UI's extension_data
#[repr(C)]
struct Lv2UiResizePlugin {
    /// Plugin requests resize to (width, height). Returns 0 on success.
    ui_resize: unsafe extern "C" fn(handle: *mut c_void, width: i32, height: i32) -> i32,
}

/// Controller data passed to the UI write_function callback.
/// This is a raw pointer to a heap-allocated struct, kept alive for UI lifetime.
struct Lv2UiController {
    /// Pointer to port_values array for direct parameter updates
    port_values: *mut Vec<f32>,
    /// Number of ports (bounds check)
    num_ports: usize,
}

/// Write function callback — called by UI when user changes a parameter.
/// Signature: write_function(controller, port_index, buffer_size, format, buffer)
/// format=0 means buffer points to a single f32 value (LV2 protocol atom).
unsafe extern "C" fn lv2_ui_write_callback(
    controller: *mut c_void,
    port_index: u32,
    buffer_size: u32,
    format: u32,
    buffer: *const c_void,
) {
    if controller.is_null() || buffer.is_null() { return; }
    // SAFETY: controller is a pointer to a heap-allocated Lv2UiController that lives
    // for the UI's lifetime. Called from UI thread (synchronous with open/close).
    unsafe {
        let ctrl = &*(controller as *const Lv2UiController);
        // format 0 = float protocol (standard LV2 control port update)
        if format == 0 && buffer_size == std::mem::size_of::<f32>() as u32 {
            let value = *(buffer as *const f32);
            let idx = port_index as usize;
            if idx < ctrl.num_ports {
                let values = &mut *ctrl.port_values;
                if idx < values.len() {
                    values[idx] = value;
                }
            }
        }
    }
    // format != 0: Atom protocol (MIDI, patch:Set, etc.) — ignore for now,
    // would need atom buffer routing for full implementation
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

    // Extract UI binary (ui:binary)
    if let Some(cap) = regex_lite_find(content, r#"ui:binary\s+<([^>]+)>"#) {
        map.insert("ui_binary".to_string(), cap);
    }

    // Extract UI type URI (CocoaUI / X11UI / WindowsUI)
    for ui_type in &["ui:CocoaUI", "ui:X11UI", "ui:WindowsUI"] {
        if content.contains(ui_type) {
            let uri_val = match *ui_type {
                "ui:CocoaUI"   => LV2_UI_COCOA,
                "ui:X11UI"     => LV2_UI_X11,
                "ui:WindowsUI" => LV2_UI_WINDOWS,
                _ => "",
            };
            map.insert("ui_type".to_string(), uri_val.to_string());
            break;
        }
    }

    // Extract UI URI (subject of ui:UI block)
    if let Some(cap) = regex_lite_find(content, r#"<(http[^>]+)>\s+a\s+ui:"#) {
        map.insert("ui_uri".to_string(), cap);
    }

    map
}

/// Simple regex-like pattern match (no regex crate dependency)
fn regex_lite_find(text: &str, pattern: &str) -> Option<String> {
    // Split pattern into prefix + capture + suffix
    let cap_start = pattern.find('(')?;
    let cap_end = pattern.rfind(')')?;
    let prefix_pat = &pattern[..cap_start];
    let _suffix_pat = &pattern[cap_end + 1..];

    // Very simplified matching — find prefix, then capture until suffix delimiter
    let prefix_clean = prefix_pat
        .replace(r"\s+", " ")
        .replace(r"\s", " ");

    // Search for prefix in text (case-insensitive search with whitespace normalization)
    let normalized = text.replace(['\t', '\n'], " ");
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
            .map_err(PluginError::IoError)?;

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

        // ── UI extension discovery ────────────────────────────────────────
        // Check for UI binary (may be in manifest.ttl, plugin.ttl, or separate ui.ttl)
        let ui_ttl_path = bundle_path.join("ui.ttl");
        let ui_data = if ui_ttl_path.exists() {
            std::fs::read_to_string(&ui_ttl_path)
                .map(|content| parse_ttl_simple(&content))
                .unwrap_or_default()
        } else {
            HashMap::new()
        };

        // Merge: dedicated ui.ttl → plugin.ttl → manifest.ttl
        let ui_binary_name = ui_data.get("ui_binary")
            .or(plugin_data.get("ui_binary"))
            .or(manifest_data.get("ui_binary"))
            .cloned();
        let ui_type = ui_data.get("ui_type")
            .or(plugin_data.get("ui_type"))
            .or(manifest_data.get("ui_type"))
            .cloned();
        let ui_uri = ui_data.get("ui_uri")
            .or(plugin_data.get("ui_uri"))
            .or(manifest_data.get("ui_uri"))
            .cloned();

        // UI bundle path: same directory as plugin bundle (LV2 spec §3.4)
        let ui_bundle_path = if ui_binary_name.is_some() {
            Some(bundle_path.to_path_buf())
        } else {
            None
        };

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
            ui_bundle_path,
            ui_binary_name,
            ui_type_uri: ui_type,
            ui_uri,
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
    /// Sample rate at which plugin was instantiated (BUG#33: track for reinit)
    instantiated_sample_rate: f64,
    /// Current device sample rate
    sample_rate: f64,
    /// Bundle path CString for reinstantiation (BUG#33)
    _bundle_path_cstr: std::ffi::CString,
    /// Pre-allocated Atom buffers for MIDI ports
    atom_input: Option<AtomBuffer>,
    atom_output: Option<AtomBuffer>,
    /// Port indices for Atom MIDI ports (-1 = not found)
    atom_input_port: Option<u32>,
    atom_output_port: Option<u32>,
    /// URID for atom:Sequence type
    sequence_urid: u32,
    /// URID for midi:MidiEvent type
    midi_event_urid: u32,
    // === UI extension fields ===
    /// Path to UI bundle (used for open_editor)
    ui_bundle_path: Option<PathBuf>,
    /// UI binary name within bundle
    ui_binary_name: Option<String>,
    /// UI type URI (CocoaUI / X11UI / WindowsUI)
    ui_type_uri: Option<String>,
    /// Active UI handle (null when editor closed)
    ui_handle: *mut c_void,
    /// Active UI descriptor pointer (from lv2ui_descriptor())
    ui_descriptor: *const Lv2UiDescriptor,
    /// Cached preferred editor size (set after successful open or resize query)
    ui_width: u32,
    ui_height: u32,
    /// UI idle interface (if supported by plugin UI)
    ui_idle_interface: *const Lv2UiIdleInterface,
    /// UI controller heap allocation (kept alive while editor open, freed on close)
    _ui_controller: Option<Box<Lv2UiController>>,

    // === LIFETIME-CRITICAL: fields below must be dropped LAST ===
    // Rust drops struct fields in declaration order. These own resources
    // that plugin pointers depend on. Dropping them last ensures no
    // dangling pointers during plugin cleanup().
    /// Feature structs (contain pointers into _feature_uris)
    #[allow(clippy::vec_box)] // Box needed for stable raw pointer addresses
    _feature_structs: Vec<Box<Lv2Feature>>,
    /// Feature C strings (owned, pointed to by _feature_structs)
    _feature_uris: Vec<std::ffi::CString>,
    /// URID map feature (pointed to by _feature_structs)
    _urid_map: Box<Lv2UridMap>,
    _urid_unmap: Box<Lv2UridUnmap>,
    /// UI library (kept alive while editor is open) — dropped before _library
    _ui_library: Option<Arc<libloading::Library>>,
    /// Loaded dynamic library — MUST be LAST (dylib unload = all symbols invalid)
    _library: Option<Arc<libloading::Library>>,
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

        // Create URID Map/Unmap features (required by ~90% of LV2 plugins)
        let urid_map = Box::new(Lv2UridMap {
            handle: std::ptr::null_mut(),
            map: urid_map_callback,
        });
        let urid_unmap = Box::new(Lv2UridUnmap {
            handle: std::ptr::null_mut(),
            unmap: urid_unmap_callback,
        });

        // Feature URIs (must outlive the plugin — stored in struct)
        let map_uri = std::ffi::CString::new("http://lv2plug.in/ns/ext/urid#map").unwrap_or_default();
        let unmap_uri = std::ffi::CString::new("http://lv2plug.in/ns/ext/urid#unmap").unwrap_or_default();

        // CRITICAL: Feature structs MUST be heap-allocated (Box) because plugins
        // may cache feature pointers beyond instantiate(). Stack pointers = UB.
        let map_feature = Box::new(Lv2Feature {
            uri: map_uri.as_ptr(),
            data: &*urid_map as *const Lv2UridMap as *const c_void,
        });
        let unmap_feature = Box::new(Lv2Feature {
            uri: unmap_uri.as_ptr(),
            data: &*urid_unmap as *const Lv2UridUnmap as *const c_void,
        });
        let features: [*const Lv2Feature; 3] = [
            &*map_feature as *const Lv2Feature,
            &*unmap_feature as *const Lv2Feature,
            std::ptr::null(),
        ];

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
        // Keep everything alive for plugin lifetime (stored in Self)
        let feature_uris = vec![map_uri, unmap_uri];
        let feature_structs = vec![map_feature, unmap_feature];

        if handle.is_null() {
            return Err(PluginError::LoadFailed("instantiate returned null".into()));
        }

        let category = desc.plugin_class.to_category();
        let has_midi = matches!(
            desc.plugin_class,
            Lv2Class::InstrumentPlugin | Lv2Class::GeneratorPlugin
        );

        // ── UI extension: check if plugin has a GUI ───────────────────────
        let has_ui = desc.ui_binary_name.is_some();
        // Verify UI binary actually exists before advertising has_editor=true
        let has_ui = has_ui && desc.ui_bundle_path.as_ref().is_some_and(|bp| {
            let binary = desc.ui_binary_name.as_ref().unwrap();
            bp.join(binary).exists()
        });

        let info = PluginInfo {
            id: plugin_uri,
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
            has_editor: has_ui,
            latency: 0,
            is_shell: false,
            sub_plugins: Vec::new(),
        };

        // Get URIDs for atom types
        let sequence_urid = unsafe { urid_map_callback(std::ptr::null_mut(), c"http://lv2plug.in/ns/ext/atom#Sequence".as_ptr() as *const c_char) };
        let midi_event_urid = unsafe { urid_map_callback(std::ptr::null_mut(), c"http://lv2plug.in/ns/ext/midi#MidiEvent".as_ptr() as *const c_char) };

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
            instantiated_sample_rate: 48000.0,
            sample_rate: 48000.0,
            _bundle_path_cstr: bundle_path_cstr,  // BUG#33: kept for potential reinstantiation
            _urid_map: urid_map,
            _urid_unmap: urid_unmap,
            _feature_uris: feature_uris,
            _feature_structs: feature_structs,
            atom_input: Some(AtomBuffer::new(8192)),
            atom_output: Some(AtomBuffer::new(8192)),
            atom_input_port: None, // Will be set from port discovery
            atom_output_port: None,
            sequence_urid,
            midi_event_urid,
            // UI extension fields
            ui_bundle_path: desc.ui_bundle_path.clone(),
            ui_binary_name: desc.ui_binary_name.clone(),
            ui_type_uri: desc.ui_type_uri.clone(),
            ui_handle: std::ptr::null_mut(),
            ui_descriptor: std::ptr::null(),
            ui_width: 800,
            ui_height: 600,
            ui_idle_interface: std::ptr::null(),
            _ui_controller: None,
            _ui_library: None,
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
        if let Some(connect) = unsafe { (*self.descriptor).connect_port } {
            // Connect audio inputs (assumed ports 0, 1)
            for (i, buf) in self.audio_inputs.iter_mut().enumerate() {
                unsafe { connect(self.handle, i as u32, buf.as_mut_ptr() as *mut c_void) };
            }
            // Connect audio outputs (assumed ports 2, 3 for stereo)
            for (i, buf) in self.audio_outputs.iter_mut().enumerate() {
                unsafe {
                    connect(
                        self.handle,
                        (i + self.audio_inputs.len()) as u32,
                        buf.as_mut_ptr() as *mut c_void,
                    )
                };
            }
            // Connect control ports (starting after audio ports)
            for (i, val) in self.port_values.iter_mut().enumerate() {
                let port_index = self.audio_inputs.len() + self.audio_outputs.len() + i;
                unsafe {
                    connect(
                        self.handle,
                        port_index as u32,
                        val as *mut f32 as *mut c_void,
                    )
                };
            }
        }
    }

    /// Send all current port values to the UI via port_event.
    /// Called after open_editor to sync UI display with actual plugin state.
    fn notify_ui_all_ports(&self) {
        if self.ui_handle.is_null() || self.ui_descriptor.is_null() { return; }
        unsafe {
            let port_event = match (*self.ui_descriptor).port_event {
                Some(f) => f,
                None => return, // UI has no port_event — can't receive updates
            };
            let audio_port_count = self.audio_inputs.len() + self.audio_outputs.len();
            // Include atom port offsets
            let atom_offset = if self.atom_input_port.is_some() { 1 } else { 0 }
                            + if self.atom_output_port.is_some() { 1 } else { 0 };
            for (i, val) in self.port_values.iter().enumerate() {
                let port_index = (audio_port_count + atom_offset + i) as u32;
                // format 0 = float protocol, buffer_size = sizeof(f32)
                port_event(
                    self.ui_handle,
                    port_index,
                    std::mem::size_of::<f32>() as u32,
                    0, // format: 0 = float
                    val as *const f32 as *const c_void,
                );
            }
        }
    }

    /// Call UI idle interface (must be called periodically from UI thread).
    /// Returns false if UI requests close.
    pub fn idle_ui(&self) -> bool {
        if self.ui_handle.is_null() || self.ui_idle_interface.is_null() {
            return true; // no idle needed
        }
        unsafe {
            let result = ((*self.ui_idle_interface).idle)(self.ui_handle);
            result == 0 // 0 = OK, non-zero = close requested
        }
    }

    /// Notify UI of a single port value change (called from set_parameter path).
    fn notify_ui_port(&self, port_index: u32, value: f32) {
        if self.ui_handle.is_null() || self.ui_descriptor.is_null() { return; }
        unsafe {
            if let Some(port_event) = (*self.ui_descriptor).port_event {
                port_event(
                    self.ui_handle,
                    port_index,
                    std::mem::size_of::<f32>() as u32,
                    0,
                    &value as *const f32 as *const c_void,
                );
            }
        }
    }
}

impl Drop for Lv2PluginInstance {
    fn drop(&mut self) {
        if !self.handle.is_null() && !self.descriptor.is_null() {
            let desc = unsafe { &*self.descriptor };
            if self.activated
                && let Some(deactivate) = desc.deactivate {
                    unsafe { deactivate(self.handle) };
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
        unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string()
    }
}

impl PluginInstance for Lv2PluginInstance {
    fn info(&self) -> &PluginInfo {
        &self.info
    }

    fn initialize(&mut self, context: &ProcessContext) -> PluginResult<()> {
        self.sample_rate = context.sample_rate;

        // BUG#33 FIX: Reinstantiate at correct sample rate if mismatch
        if (self.instantiated_sample_rate - context.sample_rate).abs() > 1.0 {
            log::info!(
                "LV2: reinstantiating at {} Hz (was {} Hz)",
                context.sample_rate,
                self.instantiated_sample_rate
            );

            // Cleanup old handle
            let desc = unsafe { &*self.descriptor };
            if let Some(cleanup) = desc.cleanup {
                unsafe { cleanup(self.handle) };
            }
            self.handle = std::ptr::null_mut();

            // Rebuild features list with stable pointers (still in self._feature_structs)
            let mut features: Vec<*const Lv2Feature> = self._feature_structs
                .iter()
                .map(|f| f.as_ref() as *const Lv2Feature)
                .collect();
            features.push(std::ptr::null());

            // Reinstantiate at correct sample rate
            let new_handle = if let Some(instantiate) = desc.instantiate {
                unsafe {
                    instantiate(
                        self.descriptor,
                        context.sample_rate,
                        self._bundle_path_cstr.as_ptr(),
                        features.as_ptr(),
                    )
                }
            } else {
                return Err(PluginError::ProcessingError(
                    "LV2 reinstantiation failed: no instantiate callback".into()
                ));
            };

            if new_handle.is_null() {
                return Err(PluginError::ProcessingError(format!(
                    "LV2 reinstantiation at {} Hz returned null", context.sample_rate
                )));
            }

            self.handle = new_handle;
            self.instantiated_sample_rate = context.sample_rate;
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
        midi_in: &rf_core::MidiBuffer,
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

        // Fill Atom MIDI input buffer with incoming MIDI events
        if self.info.has_midi_input
            && let Some(ref mut atom_buf) = self.atom_input {
                atom_buf.clear(self.sequence_urid);
                if !midi_in.is_empty() {
                    for event in midi_in.events() {
                        let mut bytes = [0u8; 3];
                        let byte_len = event.to_bytes(&mut bytes);
                        if byte_len > 0 {
                            atom_buf.push_midi_event(
                                event.sample_offset as i64,
                                self.midi_event_urid,
                                &bytes[..byte_len],
                            );
                        }
                    }
                }
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
        let value_f32 = value as f32;
        if let Some(val) = self.port_values.get_mut(id as usize) {
            *val = value_f32;
        }
        // Notify open UI of parameter change (so knobs reflect automation/host changes)
        let audio_port_count = self.audio_inputs.len() + self.audio_outputs.len();
        let atom_offset = if self.atom_input_port.is_some() { 1 } else { 0 }
                        + if self.atom_output_port.is_some() { 1 } else { 0 };
        let port_index = (audio_port_count + atom_offset + id as usize) as u32;
        self.notify_ui_port(port_index, value_f32);
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
        self.info.has_editor
    }

    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    fn open_editor(&mut self, parent: *mut std::ffi::c_void) -> PluginResult<()> {
        if parent.is_null() {
            return Err(PluginError::InitError("Null parent window handle for LV2 UI".into()));
        }

        // Close existing editor if open (defensive)
        if !self.ui_handle.is_null() {
            let _ = self.close_editor();
        }

        // Validate that a UI binary exists
        let ui_bundle = self.ui_bundle_path.as_ref().ok_or_else(|| {
            PluginError::UnsupportedFormat("LV2 plugin has no UI extension".into())
        })?.clone();
        let ui_binary_name = self.ui_binary_name.as_ref().ok_or_else(|| {
            PluginError::UnsupportedFormat("LV2 plugin has no UI binary".into())
        })?.clone();

        // Verify platform-appropriate UI type
        let ui_type = self.ui_type_uri.as_deref().unwrap_or("");
        #[cfg(target_os = "macos")]
        if !ui_type.is_empty() && ui_type != LV2_UI_COCOA {
            return Err(PluginError::UnsupportedFormat(
                format!("LV2 UI type {} not supported on macOS (need CocoaUI)", ui_type)
            ));
        }
        #[cfg(target_os = "linux")]
        if !ui_type.is_empty() && ui_type != LV2_UI_X11 {
            return Err(PluginError::UnsupportedFormat(
                format!("LV2 UI type {} not supported on Linux (need X11UI)", ui_type)
            ));
        }
        #[cfg(target_os = "windows")]
        if !ui_type.is_empty() && ui_type != LV2_UI_WINDOWS {
            return Err(PluginError::UnsupportedFormat(
                format!("LV2 UI type {} not supported on Windows (need WindowsUI)", ui_type)
            ));
        }

        let ui_binary_path = ui_bundle.join(&ui_binary_name);
        log::info!("LV2 UI: loading {:?} for {}", ui_binary_path, self.info.name);

        // Load UI library
        let ui_lib = unsafe {
            libloading::Library::new(&ui_binary_path)
                .map_err(|e| PluginError::LoadFailed(format!("LV2 UI dlopen failed: {}", e)))?
        };
        let ui_lib = Arc::new(ui_lib);

        // Get lv2ui_descriptor entry point
        let ui_descriptor_fn: libloading::Symbol<Lv2UiDescriptorFn> = unsafe {
            ui_lib.get(b"lv2ui_descriptor\0")
                .map_err(|e| PluginError::LoadFailed(format!("lv2ui_descriptor missing: {}", e)))?
        };

        // Find matching UI descriptor by URI
        let mut ui_desc_ptr = std::ptr::null::<Lv2UiDescriptor>();
        unsafe {
            let mut idx = 0u32;
            loop {
                let desc = (*ui_descriptor_fn)(idx);
                if desc.is_null() { break; }
                let uri = CStr::from_ptr((*desc).uri).to_string_lossy();
                if uri.contains(&self.info.id) || idx == 0 {
                    ui_desc_ptr = desc;
                    break;
                }
                idx += 1;
                if idx > 64 { break; } // sanity limit
            }
        }

        if ui_desc_ptr.is_null() {
            return Err(PluginError::LoadFailed(
                format!("LV2 UI descriptor not found for {}", self.info.id)
            ));
        }

        // ── Build UI controller (heap-allocated, lives for editor lifetime) ──
        let controller = Box::new(Lv2UiController {
            port_values: &mut self.port_values as *mut Vec<f32>,
            num_ports: self.port_values.len(),
        });
        let controller_ptr = &*controller as *const Lv2UiController as *mut c_void;

        // ── Build features list for UI ───────────────────────────────────────
        // Most LV2 UIs need: parent window + URID map + URID unmap
        let parent_uri = std::ffi::CString::new("http://lv2plug.in/ns/extensions/ui#parent")
            .unwrap_or_default();
        let parent_feature = Box::new(Lv2Feature {
            uri: parent_uri.as_ptr(),
            data: parent,
        });

        let map_uri = std::ffi::CString::new("http://lv2plug.in/ns/ext/urid#map").unwrap_or_default();
        let map_feature = Box::new(Lv2Feature {
            uri: map_uri.as_ptr(),
            data: &*self._urid_map as *const Lv2UridMap as *const c_void,
        });

        let unmap_uri = std::ffi::CString::new("http://lv2plug.in/ns/ext/urid#unmap").unwrap_or_default();
        let unmap_feature = Box::new(Lv2Feature {
            uri: unmap_uri.as_ptr(),
            data: &*self._urid_unmap as *const Lv2UridUnmap as *const c_void,
        });

        // Instance-access feature: gives UI direct plugin handle access
        let instance_uri = std::ffi::CString::new("http://lv2plug.in/ns/ext/instance-access").unwrap_or_default();
        let instance_feature = Box::new(Lv2Feature {
            uri: instance_uri.as_ptr(),
            data: self.handle as *const c_void,
        });

        // Null-terminated features array
        let ui_features: [*const Lv2Feature; 5] = [
            &*parent_feature as *const Lv2Feature,
            &*map_feature as *const Lv2Feature,
            &*unmap_feature as *const Lv2Feature,
            &*instance_feature as *const Lv2Feature,
            std::ptr::null(),
        ];

        // Build CStrings for instantiate
        let plugin_uri_cstr = std::ffi::CString::new(self.info.id.as_str()).unwrap_or_default();
        let bundle_path_str = ui_bundle.to_string_lossy().to_string();
        let bundle_cstr = std::ffi::CString::new(bundle_path_str).unwrap_or_default();

        // ── Instantiate the UI with write callback + controller ──────────────
        let mut widget_ptr: *mut c_void = std::ptr::null_mut();
        let ui_handle = unsafe {
            let instantiate = (*ui_desc_ptr).instantiate.ok_or_else(|| {
                PluginError::InitError("LV2 UI has no instantiate function".into())
            })?;
            instantiate(
                ui_desc_ptr,
                plugin_uri_cstr.as_ptr(),
                bundle_cstr.as_ptr(),
                Some(lv2_ui_write_callback), // write_function: routes UI changes → port_values
                controller_ptr,              // controller: passed back to write_function
                &mut widget_ptr,
                ui_features.as_ptr(),
            )
        };

        if ui_handle.is_null() {
            return Err(PluginError::InitError(
                format!("LV2 UI instantiate returned null for {}", self.info.name)
            ));
        }

        // ── Query idle extension (toolkit event processing) ──────────────────
        let idle_interface = unsafe {
            if let Some(ext_data) = (*ui_desc_ptr).extension_data {
                let uri = std::ffi::CString::new(LV2_UI_IDLE_URI).unwrap_or_default();
                let ptr = ext_data(uri.as_ptr());
                if ptr.is_null() {
                    std::ptr::null::<Lv2UiIdleInterface>()
                } else {
                    ptr as *const Lv2UiIdleInterface
                }
            } else {
                std::ptr::null()
            }
        };

        // ── Query resize extension to get actual UI size ─────────────────────
        unsafe {
            if let Some(ext_data) = (*ui_desc_ptr).extension_data {
                let uri = std::ffi::CString::new(LV2_UI_RESIZE_URI).unwrap_or_default();
                let ptr = ext_data(uri.as_ptr());
                if !ptr.is_null() {
                    let resize = &*(ptr as *const Lv2UiResizePlugin);
                    // Try to get size by requesting resize to 0,0 (some UIs report actual size)
                    // Most UIs will just report their preferred size via the widget
                    let _ = (resize.ui_resize)(ui_handle, 0, 0);
                }
            }
        }

        log::info!(
            "LV2 UI opened: {} widget={:?} handle={:?} idle={}",
            self.info.name, widget_ptr, ui_handle, !idle_interface.is_null()
        );

        self.ui_handle = ui_handle;
        self.ui_descriptor = ui_desc_ptr;
        self.ui_idle_interface = idle_interface;
        self._ui_controller = Some(controller);
        self._ui_library = Some(ui_lib);

        // ── Send current port values to UI (so it shows actual state, not defaults) ──
        self.notify_ui_all_ports();

        // Keep CStrings alive through the synchronous call above
        let _ = (parent_uri, map_uri, unmap_uri, instance_uri);
        let _ = (parent_feature, map_feature, unmap_feature, instance_feature);
        let _ = plugin_uri_cstr;
        let _ = bundle_cstr;

        Ok(())
    }

    fn close_editor(&mut self) -> PluginResult<()> {
        if self.ui_handle.is_null() {
            return Ok(());
        }
        unsafe {
            if let Some(cleanup) = (*self.ui_descriptor).cleanup {
                cleanup(self.ui_handle);
            }
        }
        self.ui_handle = std::ptr::null_mut();
        self.ui_descriptor = std::ptr::null();
        self.ui_idle_interface = std::ptr::null();
        self._ui_controller = None; // free controller before library
        self._ui_library = None;    // drop the library after cleanup
        log::info!("LV2 UI closed: {}", self.info.name);
        Ok(())
    }

    fn editor_size(&self) -> Option<(u32, u32)> {
        Some((self.ui_width, self.ui_height))
    }

    fn resize_editor(&mut self, width: u32, height: u32) -> PluginResult<()> {
        if self.ui_handle.is_null() {
            return Ok(());
        }
        // Query the resize extension from the UI
        unsafe {
            if !self.ui_descriptor.is_null()
                && let Some(ext_data) = (*self.ui_descriptor).extension_data {
                    let uri = std::ffi::CString::new(LV2_UI_RESIZE_URI).unwrap_or_default();
                    let ptr = ext_data(uri.as_ptr());
                    if !ptr.is_null() {
                        let resize = &*(ptr as *const Lv2UiResizePlugin);
                        let result = (resize.ui_resize)(self.ui_handle, width as i32, height as i32);
                        if result == 0 {
                            self.ui_width = width;
                            self.ui_height = height;
                        }
                        return Ok(());
                    }
                }
        }
        // Fallback: just update cached size
        self.ui_width = width;
        self.ui_height = height;
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
