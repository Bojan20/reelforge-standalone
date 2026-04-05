//! CLAP Plugin Host
//!
//! CLever Audio Plugin format support with real dynamic library loading.
//! Reference: <https://github.com/free-audio/clap>

use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crate::scanner::{PluginCategory, PluginInfo, PluginType};
use crate::{
    AudioBuffer, ParameterInfo, PluginError, PluginInstance, PluginResult, ProcessContext,
};

// ═══════════════════════════════════════════════════════════════════════════
// CLAP C ABI DEFINITIONS (minimal subset for hosting)
// ═══════════════════════════════════════════════════════════════════════════

#[repr(C)]
#[derive(Debug, Clone, Copy)]
struct ClapVersion {
    major: u32,
    minor: u32,
    revision: u32,
}

const CLAP_VERSION: ClapVersion = ClapVersion {
    major: 1,
    minor: 2,
    revision: 0,
};

/// CLAP plugin entry point (exported from .clap binary)
#[repr(C)]
struct ClapPluginEntry {
    clap_version: ClapVersion,
    init: Option<unsafe extern "C" fn(plugin_path: *const c_char) -> bool>,
    deinit: Option<unsafe extern "C" fn()>,
    get_factory: Option<unsafe extern "C" fn(factory_id: *const c_char) -> *const c_void>,
}

/// CLAP plugin factory
#[repr(C)]
struct ClapPluginFactory {
    get_plugin_count: Option<unsafe extern "C" fn(factory: *const ClapPluginFactory) -> u32>,
    get_plugin_descriptor: Option<
        unsafe extern "C" fn(
            factory: *const ClapPluginFactory,
            index: u32,
        ) -> *const ClapPluginDescriptor,
    >,
    create_plugin: Option<
        unsafe extern "C" fn(
            factory: *const ClapPluginFactory,
            host: *const ClapHostInfo,
            plugin_id: *const c_char,
        ) -> *const ClapPlugin,
    >,
}

/// CLAP plugin descriptor (metadata)
#[repr(C)]
struct ClapPluginDescriptor {
    clap_version: ClapVersion,
    id: *const c_char,
    name: *const c_char,
    vendor: *const c_char,
    url: *const c_char,
    manual_url: *const c_char,
    support_url: *const c_char,
    version: *const c_char,
    description: *const c_char,
    features: *const *const c_char,
}

/// CLAP host info (provided by us to plugin)
#[repr(C)]
struct ClapHostInfo {
    clap_version: ClapVersion,
    host_data: *mut c_void,
    name: *const c_char,
    vendor: *const c_char,
    url: *const c_char,
    version: *const c_char,
    get_extension: Option<unsafe extern "C" fn(host: *const ClapHostInfo, ext_id: *const c_char) -> *const c_void>,
    request_restart: Option<unsafe extern "C" fn(host: *const ClapHostInfo)>,
    request_process: Option<unsafe extern "C" fn(host: *const ClapHostInfo)>,
    request_callback: Option<unsafe extern "C" fn(host: *const ClapHostInfo)>,
}

/// CLAP plugin instance (opaque from host perspective)
#[repr(C)]
struct ClapPlugin {
    desc: *const ClapPluginDescriptor,
    plugin_data: *mut c_void,
    init: Option<unsafe extern "C" fn(plugin: *const ClapPlugin) -> bool>,
    destroy: Option<unsafe extern "C" fn(plugin: *const ClapPlugin)>,
    activate: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, sample_rate: f64, min_frames: u32, max_frames: u32) -> bool>,
    deactivate: Option<unsafe extern "C" fn(plugin: *const ClapPlugin)>,
    start_processing: Option<unsafe extern "C" fn(plugin: *const ClapPlugin) -> bool>,
    stop_processing: Option<unsafe extern "C" fn(plugin: *const ClapPlugin)>,
    reset: Option<unsafe extern "C" fn(plugin: *const ClapPlugin)>,
    process: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, process: *const ClapProcess) -> ClapProcessStatus>,
    get_extension: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, id: *const c_char) -> *const c_void>,
    on_main_thread: Option<unsafe extern "C" fn(plugin: *const ClapPlugin)>,
}

/// CLAP process status
#[repr(i32)]
#[derive(Debug, Clone, Copy, PartialEq)]
enum ClapProcessStatus {
    Error = 0,
    Continue = 1,
    ContinueIfNotQuiet = 2,
    Tail = 3,
    Sleep = 4,
}

/// CLAP process data
#[repr(C)]
struct ClapProcess {
    steady_time: i64,
    frames_count: u32,
    transport: *const c_void, // ClapEventTransport (simplified)
    audio_inputs: *const ClapAudioBuffer,
    audio_outputs: *mut ClapAudioBuffer,
    audio_inputs_count: u32,
    audio_outputs_count: u32,
    in_events: *const ClapInputEvents,
    out_events: *const ClapOutputEvents,
}

/// CLAP audio buffer
#[repr(C)]
struct ClapAudioBuffer {
    data32: *mut *mut f32,
    data64: *mut *mut f64,
    channel_count: u32,
    latency: u32,
    constant_mask: u64,
}

/// CLAP input events (simplified — empty for now)
#[repr(C)]
struct ClapInputEvents {
    ctx: *mut c_void,
    size: Option<unsafe extern "C" fn(list: *const ClapInputEvents) -> u32>,
    get: Option<unsafe extern "C" fn(list: *const ClapInputEvents, index: u32) -> *const c_void>,
}

/// CLAP output events (simplified — empty for now)
#[repr(C)]
struct ClapOutputEvents {
    ctx: *mut c_void,
    try_push: Option<unsafe extern "C" fn(list: *const ClapOutputEvents, event: *const c_void) -> bool>,
}

const CLAP_PLUGIN_FACTORY_ID: &[u8] = b"clap.plugin-factory\0";

// ═══════════════════════════════════════════════════════════════════════════
// CLAP EXTENSION INTERFACES
// ═══════════════════════════════════════════════════════════════════════════

/// clap.params extension
#[repr(C)]
struct ClapPluginParams {
    count: Option<unsafe extern "C" fn(plugin: *const ClapPlugin) -> u32>,
    get_info: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, param_index: u32, info: *mut ClapParamInfo) -> bool>,
    get_value: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, param_id: u32, out_value: *mut f64) -> bool>,
    value_to_text: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, param_id: u32, value: f64, out_buf: *mut c_char, out_buf_capacity: u32) -> bool>,
    text_to_value: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, param_id: u32, param_value_text: *const c_char, out_value: *mut f64) -> bool>,
    flush: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, in_events: *const ClapInputEvents, out_events: *const ClapOutputEvents)>,
}

/// CLAP parameter info
#[repr(C)]
struct ClapParamInfo {
    id: u32,
    flags: u32,
    cookie: *mut c_void,
    name: [c_char; 256],
    module: [c_char; 1024],
    min_value: f64,
    max_value: f64,
    default_value: f64,
}

impl Default for ClapParamInfo {
    fn default() -> Self {
        Self {
            id: 0,
            flags: 0,
            cookie: std::ptr::null_mut(),
            name: [0; 256],
            module: [0; 1024],
            min_value: 0.0,
            max_value: 1.0,
            default_value: 0.0,
        }
    }
}

/// clap.state extension
#[repr(C)]
struct ClapPluginState {
    save: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, stream: *const ClapOStream) -> bool>,
    load: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, stream: *const ClapIStream) -> bool>,
}

#[repr(C)]
struct ClapOStream {
    ctx: *mut c_void,
    write: Option<unsafe extern "C" fn(stream: *const ClapOStream, buffer: *const c_void, size: u64) -> i64>,
}

#[repr(C)]
struct ClapIStream {
    ctx: *mut c_void,
    read: Option<unsafe extern "C" fn(stream: *const ClapIStream, buffer: *mut c_void, size: u64) -> i64>,
}

/// clap.latency extension
#[repr(C)]
struct ClapPluginLatency {
    get: Option<unsafe extern "C" fn(plugin: *const ClapPlugin) -> u32>,
}

/// clap.gui extension
#[repr(C)]
struct ClapPluginGui {
    is_api_supported: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, api: *const c_char, is_floating: bool) -> bool>,
    get_preferred_api: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, api: *mut *const c_char, is_floating: *mut bool) -> bool>,
    create: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, api: *const c_char, is_floating: bool) -> bool>,
    destroy: Option<unsafe extern "C" fn(plugin: *const ClapPlugin)>,
    set_scale: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, scale: f64) -> bool>,
    get_size: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, width: *mut u32, height: *mut u32) -> bool>,
    can_resize: Option<unsafe extern "C" fn(plugin: *const ClapPlugin) -> bool>,
    get_resize_hints: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, hints: *mut c_void) -> bool>,
    adjust_size: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, width: *mut u32, height: *mut u32) -> bool>,
    set_size: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, width: u32, height: u32) -> bool>,
    set_parent: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, window: *const ClapWindow) -> bool>,
    set_transient: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, window: *const ClapWindow) -> bool>,
    suggest_title: Option<unsafe extern "C" fn(plugin: *const ClapPlugin, title: *const c_char)>,
    show: Option<unsafe extern "C" fn(plugin: *const ClapPlugin) -> bool>,
    hide: Option<unsafe extern "C" fn(plugin: *const ClapPlugin) -> bool>,
}

#[repr(C)]
struct ClapWindow {
    api: *const c_char,
    handle: *mut c_void, // NSView* on macOS, HWND on Windows
}

// CLAP extension ID strings (null-terminated)
const CLAP_EXT_PARAMS: &[u8] = b"clap.params\0";
const CLAP_EXT_STATE: &[u8] = b"clap.state\0";
const CLAP_EXT_LATENCY: &[u8] = b"clap.latency\0";
const CLAP_EXT_GUI: &[u8] = b"clap.gui\0";

#[cfg(target_os = "macos")]
const CLAP_WINDOW_API_COCOA: &[u8] = b"cocoa\0";
#[cfg(target_os = "windows")]
const CLAP_WINDOW_API_WIN32: &[u8] = b"win32\0";
#[cfg(target_os = "linux")]
const CLAP_WINDOW_API_X11: &[u8] = b"x11\0";

// ═══════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════

unsafe fn cstr_to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string()
    }
}

/// Read null-terminated array of C strings (features)
unsafe fn read_features(features_ptr: *const *const c_char) -> Vec<String> {
    let mut result = Vec::new();
    if features_ptr.is_null() {
        return result;
    }
    let mut i = 0;
    loop {
        let ptr = unsafe { *features_ptr.add(i) };
        if ptr.is_null() {
            break;
        }
        result.push(unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string());
        i += 1;
    }
    result
}

/// Empty input events (no MIDI events for now)
unsafe extern "C" fn empty_events_size(_list: *const ClapInputEvents) -> u32 {
    0
}

unsafe extern "C" fn empty_events_get(_list: *const ClapInputEvents, _index: u32) -> *const c_void {
    std::ptr::null()
}

/// Empty output events (discard plugin output events for now)
unsafe extern "C" fn discard_output_try_push(_list: *const ClapOutputEvents, _event: *const c_void) -> bool {
    true
}

/// Host callbacks (minimal)
unsafe extern "C" fn host_get_extension(_host: *const ClapHostInfo, _ext_id: *const c_char) -> *const c_void {
    std::ptr::null()
}
unsafe extern "C" fn host_request_restart(_host: *const ClapHostInfo) {}
unsafe extern "C" fn host_request_process(_host: *const ClapHostInfo) {}
unsafe extern "C" fn host_request_callback(_host: *const ClapHostInfo) {}

// ═══════════════════════════════════════════════════════════════════════════
// CLAP DESCRIPTOR
// ═══════════════════════════════════════════════════════════════════════════

/// CLAP plugin descriptor
#[derive(Debug, Clone)]
pub struct ClapDescriptor {
    pub id: String,
    pub name: String,
    pub vendor: String,
    pub version: String,
    pub description: String,
    pub url: String,
    pub features: Vec<String>,
}

// ═══════════════════════════════════════════════════════════════════════════
// CLAP HOST
// ═══════════════════════════════════════════════════════════════════════════

/// CLAP plugin host with real dynamic library loading
pub struct ClapHost {
    /// Scanned plugin descriptors
    descriptors: HashMap<String, ClapDescriptor>,
    /// Plugin path cache (id -> .clap file path)
    plugin_paths: HashMap<String, PathBuf>,
}

impl ClapHost {
    pub fn new() -> Self {
        Self {
            descriptors: HashMap::new(),
            plugin_paths: HashMap::new(),
        }
    }

    /// Scan directory for CLAP plugins, loading descriptors from each .clap file
    pub fn scan_directory(&mut self, path: &Path) -> PluginResult<Vec<ClapDescriptor>> {
        let mut descriptors = Vec::new();

        if !path.exists() {
            return Ok(descriptors);
        }

        if let Ok(entries) = std::fs::read_dir(path) {
            for entry in entries.flatten() {
                let entry_path = entry.path();
                // CLAP bundles are .clap files (actually dynamic libraries)
                let is_clap = entry_path
                    .extension()
                    .is_some_and(|e| e == "clap");

                if !is_clap {
                    continue;
                }

                match self.scan_plugin(&entry_path) {
                    Ok(descs) => {
                        for desc in descs {
                            self.plugin_paths.insert(desc.id.clone(), entry_path.clone());
                            self.descriptors.insert(desc.id.clone(), desc.clone());
                            descriptors.push(desc);
                        }
                    }
                    Err(e) => {
                        log::warn!("Failed to scan CLAP plugin {:?}: {}", entry_path, e);
                    }
                }
            }
        }

        Ok(descriptors)
    }

    /// Scan a single .clap file — load library, get factory, enumerate descriptors
    fn scan_plugin(&self, path: &Path) -> PluginResult<Vec<ClapDescriptor>> {
        let lib = unsafe {
            libloading::Library::new(path)
                .map_err(|e| PluginError::LoadFailed(format!("dlopen failed: {}", e)))?
        };

        // Get entry point symbol
        let entry: libloading::Symbol<*const ClapPluginEntry> = unsafe {
            lib.get(b"clap_entry\0")
                .map_err(|e| PluginError::LoadFailed(format!("clap_entry not found: {}", e)))?
        };

        let entry_ptr = *entry;
        if entry_ptr.is_null() {
            return Err(PluginError::LoadFailed("clap_entry is null".into()));
        }

        let entry_ref = unsafe { &*entry_ptr };

        // Initialize
        let path_cstr = std::ffi::CString::new(path.to_string_lossy().as_ref())
            .map_err(|_| PluginError::LoadFailed("invalid path".into()))?;

        if let Some(init) = entry_ref.init {
            let ok = unsafe { init(path_cstr.as_ptr()) };
            if !ok {
                return Err(PluginError::InitFailed("clap_entry.init() failed".into()));
            }
        }

        // Get plugin factory
        let factory_ptr = if let Some(get_factory) = entry_ref.get_factory {
            unsafe { get_factory(CLAP_PLUGIN_FACTORY_ID.as_ptr() as *const c_char) }
        } else {
            std::ptr::null()
        };

        let mut descriptors = Vec::new();

        if !factory_ptr.is_null() {
            let factory = unsafe { &*(factory_ptr as *const ClapPluginFactory) };

            if let Some(get_count) = factory.get_plugin_count {
                let count = unsafe { get_count(factory) };

                for i in 0..count {
                    if let Some(get_desc) = factory.get_plugin_descriptor {
                        let desc_ptr = unsafe { get_desc(factory, i) };
                        if !desc_ptr.is_null() {
                            let desc_ref = unsafe { &*desc_ptr };
                            let features = unsafe { read_features(desc_ref.features) };
                            descriptors.push(ClapDescriptor {
                                id: unsafe { cstr_to_string(desc_ref.id) },
                                name: unsafe { cstr_to_string(desc_ref.name) },
                                vendor: unsafe { cstr_to_string(desc_ref.vendor) },
                                version: unsafe { cstr_to_string(desc_ref.version) },
                                description: unsafe { cstr_to_string(desc_ref.description) },
                                url: unsafe { cstr_to_string(desc_ref.url) },
                                features,
                            });
                        }
                    }
                }
            }
        }

        // Deinit
        if let Some(deinit) = entry_ref.deinit {
            unsafe { deinit() };
        }

        // Library is dropped here — that's fine for scanning.
        // Loading keeps library alive via ClapPluginInstance.

        Ok(descriptors)
    }

    /// Load a CLAP plugin instance (keeps library alive)
    pub fn load(&mut self, plugin_id: &str) -> PluginResult<ClapPluginInstance> {
        let path = self
            .plugin_paths
            .get(plugin_id)
            .ok_or_else(|| PluginError::NotFound(plugin_id.to_string()))?
            .clone();

        ClapPluginInstance::load(&path, plugin_id)
    }
}

impl Default for ClapHost {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLAP PLUGIN INSTANCE
// ═══════════════════════════════════════════════════════════════════════════

/// Live CLAP plugin instance with loaded library
pub struct ClapPluginInstance {
    info: PluginInfo,
    /// Loaded dynamic library (must stay alive for plugin pointer to be valid)
    _library: Arc<libloading::Library>,
    /// Pointer to live CLAP plugin instance (owned by factory, freed on destroy)
    plugin_ptr: *const ClapPlugin,
    /// Host info (must stay alive as long as plugin is alive)
    _host_info: Box<ClapHostInfo>,
    /// Host name C string (must stay alive)
    _host_name: std::ffi::CString,
    _host_vendor: std::ffi::CString,
    _host_url: std::ffi::CString,
    _host_version: std::ffi::CString,
    /// Is activated (atomic for audio thread safety)
    activated: std::sync::atomic::AtomicBool,
    /// Sample rate from initialize() context
    sample_rate: std::sync::atomic::AtomicU64,
    /// Latency
    latency_samples: usize,
    /// Pre-allocated audio buffer pointers — fixed size 8 channels (zero audio-thread alloc)
    input_ptrs: [*mut f32; 8],
    output_ptrs: [*mut f32; 8],
    /// Empty event lists (pre-allocated, zero-alloc)
    input_events: Box<ClapInputEvents>,
    output_events: Box<ClapOutputEvents>,
    /// CLAP extension pointers (queried at load, null if not supported)
    params_ext: *const ClapPluginParams,
    state_ext: *const ClapPluginState,
    latency_ext: *const ClapPluginLatency,
    gui_ext: *const ClapPluginGui,
    /// Cached parameter info (queried once at load)
    cached_params: Vec<(u32, String, f64, f64, f64)>, // (id, name, min, max, default)
    /// GUI state
    gui_created: bool,
    gui_width: u32,
    gui_height: u32,
}

// SAFETY: ClapPlugin is a C FFI pointer that is only accessed from audio thread
// and UI thread in sequence (never concurrently). The library owns the pointer.
unsafe impl Send for ClapPluginInstance {}
unsafe impl Sync for ClapPluginInstance {}

impl ClapPluginInstance {
    /// Load a CLAP plugin from path with specific plugin_id
    pub fn load(path: &Path, plugin_id: &str) -> PluginResult<Self> {
        let lib = unsafe {
            libloading::Library::new(path)
                .map_err(|e| PluginError::LoadFailed(format!("dlopen failed: {}", e)))?
        };
        let lib = Arc::new(lib);

        // Get entry point
        let entry: libloading::Symbol<*const ClapPluginEntry> = unsafe {
            lib.get(b"clap_entry\0")
                .map_err(|e| PluginError::LoadFailed(format!("clap_entry not found: {}", e)))?
        };
        let entry_ptr = *entry;
        if entry_ptr.is_null() {
            return Err(PluginError::LoadFailed("clap_entry is null".into()));
        }
        let entry_ref = unsafe { &*entry_ptr };

        // Initialize entry
        let path_cstr = std::ffi::CString::new(path.to_string_lossy().as_ref())
            .map_err(|_| PluginError::LoadFailed("invalid path".into()))?;
        if let Some(init) = entry_ref.init {
            let ok = unsafe { init(path_cstr.as_ptr()) };
            if !ok {
                return Err(PluginError::InitFailed("clap_entry.init() failed".into()));
            }
        }

        // Get factory
        let factory_ptr = entry_ref.get_factory
            .map(|f| unsafe { f(CLAP_PLUGIN_FACTORY_ID.as_ptr() as *const c_char) })
            .unwrap_or(std::ptr::null());
        if factory_ptr.is_null() {
            return Err(PluginError::LoadFailed("no plugin factory".into()));
        }
        let factory = unsafe { &*(factory_ptr as *const ClapPluginFactory) };

        // Create host info
        let host_name = std::ffi::CString::new("FluxForge Studio").unwrap();
        let host_vendor = std::ffi::CString::new("FluxForge").unwrap();
        let host_url = std::ffi::CString::new("https://fluxforge.studio").unwrap();
        let host_version = std::ffi::CString::new("1.0.0").unwrap();

        let host_info = Box::new(ClapHostInfo {
            clap_version: CLAP_VERSION,
            host_data: std::ptr::null_mut(),
            name: host_name.as_ptr(),
            vendor: host_vendor.as_ptr(),
            url: host_url.as_ptr(),
            version: host_version.as_ptr(),
            get_extension: Some(host_get_extension),
            request_restart: Some(host_request_restart),
            request_process: Some(host_request_process),
            request_callback: Some(host_request_callback),
        });

        // Create plugin instance via factory
        let id_cstr = std::ffi::CString::new(plugin_id)
            .map_err(|_| PluginError::LoadFailed("invalid plugin id".into()))?;

        let create_plugin = factory.create_plugin
            .ok_or_else(|| PluginError::LoadFailed("factory.create_plugin is null".into()))?;
        let plugin_ptr = unsafe {
            create_plugin(factory, &*host_info as *const ClapHostInfo, id_cstr.as_ptr())
        };
        if plugin_ptr.is_null() {
            return Err(PluginError::LoadFailed("factory.create_plugin returned null".into()));
        }

        // Initialize plugin
        let plugin_ref = unsafe { &*plugin_ptr };
        if let Some(plugin_init) = plugin_ref.init {
            let ok = unsafe { plugin_init(plugin_ptr) };
            if !ok {
                // Destroy on init failure
                if let Some(destroy) = plugin_ref.destroy {
                    unsafe { destroy(plugin_ptr) };
                }
                return Err(PluginError::InitFailed("plugin.init() failed".into()));
            }
        }

        // Extract plugin info from descriptor
        let (name, vendor, version, features) = if !plugin_ref.desc.is_null() {
            let desc = unsafe { &*plugin_ref.desc };
            (
                unsafe { cstr_to_string(desc.name) },
                unsafe { cstr_to_string(desc.vendor) },
                unsafe { cstr_to_string(desc.version) },
                unsafe { read_features(desc.features) },
            )
        } else {
            (plugin_id.to_string(), String::new(), "1.0.0".to_string(), Vec::new())
        };

        let has_midi = features.iter().any(|f| f == "instrument" || f == "note-effect");
        let is_instrument = features.iter().any(|f| f == "instrument");
        let category = if is_instrument {
            PluginCategory::Instrument
        } else {
            PluginCategory::Effect
        };

        let info = PluginInfo {
            id: plugin_id.to_string(),
            name,
            vendor,
            version,
            plugin_type: PluginType::Clap,
            category,
            path: path.to_path_buf(),
            audio_inputs: 2,
            audio_outputs: 2,
            has_midi_input: has_midi,
            has_midi_output: false,
            has_editor: false, // TODO: query gui extension
            latency: 0,
            is_shell: false,
            sub_plugins: Vec::new(),
        };

        // Pre-allocate event lists
        let input_events = Box::new(ClapInputEvents {
            ctx: std::ptr::null_mut(),
            size: Some(empty_events_size),
            get: Some(empty_events_get),
        });
        let output_events = Box::new(ClapOutputEvents {
            ctx: std::ptr::null_mut(),
            try_push: Some(discard_output_try_push),
        });

        // Query extensions via get_extension
        let params_ext = unsafe { Self::query_ext(plugin_ptr, CLAP_EXT_PARAMS) as *const ClapPluginParams };
        let state_ext = unsafe { Self::query_ext(plugin_ptr, CLAP_EXT_STATE) as *const ClapPluginState };
        let latency_ext = unsafe { Self::query_ext(plugin_ptr, CLAP_EXT_LATENCY) as *const ClapPluginLatency };
        let gui_ext = unsafe { Self::query_ext(plugin_ptr, CLAP_EXT_GUI) as *const ClapPluginGui };

        // Query latency if available
        let latency_samples = if !latency_ext.is_null() {
            unsafe {
                let lat = &*latency_ext;
                lat.get.map(|f| f(plugin_ptr) as usize).unwrap_or(0)
            }
        } else {
            0
        };

        // Update info with GUI support
        let has_gui = !gui_ext.is_null();

        let mut inst = Self {
            info,
            _library: lib,
            plugin_ptr,
            _host_info: host_info,
            _host_name: host_name,
            _host_vendor: host_vendor,
            _host_url: host_url,
            _host_version: host_version,
            activated: std::sync::atomic::AtomicBool::new(false),
            sample_rate: std::sync::atomic::AtomicU64::new(48000.0_f64.to_bits()),
            latency_samples,
            input_ptrs: [std::ptr::null_mut(); 8],
            output_ptrs: [std::ptr::null_mut(); 8],
            input_events,
            output_events,
            params_ext,
            state_ext,
            latency_ext,
            gui_ext,
            cached_params: Vec::new(),
            gui_created: false,
            gui_width: 0,
            gui_height: 0,
        };

        inst.info.has_editor = has_gui;
        inst.info.latency = latency_samples as u32;

        // Cache parameter info
        inst.cache_params();

        Ok(inst)
    }
}

impl ClapPluginInstance {
    /// Query a CLAP extension from the plugin
    unsafe fn query_ext(plugin_ptr: *const ClapPlugin, ext_id: &[u8]) -> *const c_void {
        if plugin_ptr.is_null() { return std::ptr::null(); }
        let plugin_ref = unsafe { &*plugin_ptr };
        plugin_ref.get_extension
            .map(|f| unsafe { f(plugin_ptr, ext_id.as_ptr() as *const c_char) })
            .unwrap_or(std::ptr::null())
    }

    /// Cache all parameter info from plugin (called once at load)
    fn cache_params(&mut self) {
        if self.params_ext.is_null() { return; }
        let params = unsafe { &*self.params_ext };
        let count = params.count.map(|f| unsafe { f(self.plugin_ptr) }).unwrap_or(0);

        self.cached_params.clear();
        for i in 0..count {
            let mut info = ClapParamInfo::default();
            let ok = params.get_info.map(|f| unsafe { f(self.plugin_ptr, i, &mut info) }).unwrap_or(false);
            if ok {
                let name = unsafe {
                    let name_ptr = info.name.as_ptr();
                    if name_ptr.is_null() { String::new() } else {
                        CStr::from_ptr(name_ptr).to_string_lossy().to_string()
                    }
                };
                self.cached_params.push((info.id, name, info.min_value, info.max_value, info.default_value));
            }
        }
        log::info!("CLAP plugin '{}': cached {} parameters", self.info.name, self.cached_params.len());
    }
}

impl Drop for ClapPluginInstance {
    fn drop(&mut self) {
        if !self.plugin_ptr.is_null() {
            // Close GUI before destroying plugin (must happen first)
            if self.gui_created {
                let _ = self.close_editor();
            }

            let plugin_ref = unsafe { &*self.plugin_ptr };
            if self.activated.load(std::sync::atomic::Ordering::SeqCst) {
                if let Some(stop) = plugin_ref.stop_processing {
                    unsafe { stop(self.plugin_ptr) };
                }
                if let Some(deactivate) = plugin_ref.deactivate {
                    unsafe { deactivate(self.plugin_ptr) };
                }
            }
            if let Some(destroy) = plugin_ref.destroy {
                unsafe { destroy(self.plugin_ptr) };
            }
            self.plugin_ptr = std::ptr::null();
        }
    }
}

impl PluginInstance for ClapPluginInstance {
    fn info(&self) -> &PluginInfo {
        &self.info
    }

    fn initialize(&mut self, context: &ProcessContext) -> PluginResult<()> {
        self.sample_rate.store(context.sample_rate.to_bits(), std::sync::atomic::Ordering::Relaxed);
        Ok(())
    }

    fn activate(&mut self) -> PluginResult<()> {
        if self.plugin_ptr.is_null() {
            return Err(PluginError::ProcessingError("Plugin not loaded".into()));
        }
        let sr = f64::from_bits(self.sample_rate.load(std::sync::atomic::Ordering::Relaxed));
        let plugin_ref = unsafe { &*self.plugin_ptr };
        if let Some(activate) = plugin_ref.activate {
            let ok = unsafe { activate(self.plugin_ptr, sr, 32, 4096) };
            if !ok {
                return Err(PluginError::InitFailed("plugin.activate() failed".into()));
            }
        }
        if let Some(start) = plugin_ref.start_processing {
            let ok = unsafe { start(self.plugin_ptr) };
            if !ok {
                return Err(PluginError::ProcessingError("start_processing failed".into()));
            }
        }
        self.activated.store(true, std::sync::atomic::Ordering::SeqCst);
        Ok(())
    }

    fn deactivate(&mut self) -> PluginResult<()> {
        if !self.plugin_ptr.is_null() && self.activated.load(std::sync::atomic::Ordering::SeqCst) {
            let plugin_ref = unsafe { &*self.plugin_ptr };
            if let Some(stop) = plugin_ref.stop_processing {
                unsafe { stop(self.plugin_ptr) };
            }
            if let Some(deactivate) = plugin_ref.deactivate {
                unsafe { deactivate(self.plugin_ptr) };
            }
        }
        self.activated.store(false, std::sync::atomic::Ordering::SeqCst);
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
        if self.plugin_ptr.is_null() || !self.activated.load(std::sync::atomic::Ordering::Relaxed) {
            // Passthrough if not active
            for (i, out_ch) in output.data.iter_mut().enumerate() {
                if let Some(in_ch) = input.data.get(i) {
                    out_ch.copy_from_slice(in_ch);
                }
            }
            return Ok(());
        }

        let frames = input.samples;
        let plugin_ref = unsafe { &*self.plugin_ptr };

        // Set up audio buffer pointers (zero-alloc — fixed-size arrays, max 8 channels)
        // Reset all pointers to null first (clear stale pointers from previous call)
        self.input_ptrs = [std::ptr::null_mut(); 8];
        self.output_ptrs = [std::ptr::null_mut(); 8];

        let in_channels = input.channels.min(8);
        let out_channels = output.channels.min(8);

        for (i, ch) in input.data.iter().enumerate().take(in_channels) {
            self.input_ptrs[i] = ch.as_ptr() as *mut f32;
        }
        for (i, ch) in output.data.iter_mut().enumerate().take(out_channels) {
            self.output_ptrs[i] = ch.as_mut_ptr();
        }

        let audio_in = ClapAudioBuffer {
            data32: self.input_ptrs.as_mut_ptr(),
            data64: std::ptr::null_mut(),
            channel_count: input.channels as u32,
            latency: 0,
            constant_mask: 0,
        };

        let mut audio_out = ClapAudioBuffer {
            data32: self.output_ptrs.as_mut_ptr(),
            data64: std::ptr::null_mut(),
            channel_count: output.channels as u32,
            latency: 0,
            constant_mask: 0,
        };

        // TODO: Convert _midi_in to CLAP input events for instrument plugins

        let process_data = ClapProcess {
            steady_time: -1,
            frames_count: frames as u32,
            transport: std::ptr::null(),
            audio_inputs: &audio_in as *const ClapAudioBuffer,
            audio_outputs: &mut audio_out as *mut ClapAudioBuffer,
            audio_inputs_count: 1,
            audio_outputs_count: 1,
            in_events: &*self.input_events as *const ClapInputEvents,
            out_events: &*self.output_events as *const ClapOutputEvents,
        };

        if let Some(process_fn) = plugin_ref.process {
            let status = unsafe { process_fn(self.plugin_ptr, &process_data) };
            if status == ClapProcessStatus::Error {
                return Err(PluginError::ProcessingError("CLAP process error".into()));
            }
        }

        Ok(())
    }

    fn parameter_count(&self) -> usize {
        self.cached_params.len()
    }

    fn parameter_info(&self, index: usize) -> Option<ParameterInfo> {
        self.cached_params.get(index).map(|(id, name, min, max, default)| {
            ParameterInfo {
                id: *id,
                name: name.clone(),
                unit: String::new(),
                min: *min,
                max: *max,
                default: *default,
                normalized: 0.0,
                steps: 0,
                automatable: true,
                read_only: false,
            }
        })
    }

    fn get_parameter(&self, id: u32) -> Option<f64> {
        if self.params_ext.is_null() { return None; }
        let params = unsafe { &*self.params_ext };
        let mut value = 0.0f64;
        let ok = params.get_value.map(|f| unsafe { f(self.plugin_ptr, id, &mut value) }).unwrap_or(false);
        if ok { Some(value) } else { None }
    }

    fn set_parameter(&mut self, id: u32, value: f64) -> PluginResult<()> {
        if self.params_ext.is_null() { return Ok(()); }
        // CLAP uses events for param changes — flush with a param value event
        // For now, we use the flush mechanism via input events
        let params = unsafe { &*self.params_ext };
        if let Some(flush) = params.flush {
            // Create a parameter value event on the stack
            // Layout matches clap_event_param_value_t exactly (verified: 56 bytes, value at offset 48)
            #[repr(C)]
            struct ClapEventParamValue {
                header: [u8; 16], // clap_event_header_t (size u32, time u32, space_id u16, type u16, flags u32)
                param_id: u32,    // clap_id
                cookie: *mut c_void,
                note_id: i32,
                port_index: i16,
                channel: i16,
                key: i16,
                // 6 bytes implicit padding (repr(C)) to align f64
                value: f64,
            }

            let event = ClapEventParamValue {
                header: {
                    let mut h = [0u8; 16];
                    let size = std::mem::size_of::<ClapEventParamValue>() as u32;
                    h[0..4].copy_from_slice(&size.to_ne_bytes()); // size
                    // h[4..8] = time (0)
                    // h[8..10] = space_id (0 = core)
                    h[10..12].copy_from_slice(&4u16.to_ne_bytes()); // type = CLAP_EVENT_PARAM_VALUE
                    // h[12..16] = flags (0)
                    h
                },
                param_id: id,
                cookie: std::ptr::null_mut(),
                note_id: -1,
                port_index: -1,
                channel: -1,
                key: -1,
                value,
            };

            // Wrap in a single-event input list
            struct SingleEventCtx { event_ptr: *const c_void }
            unsafe extern "C" fn single_size(_list: *const ClapInputEvents) -> u32 { 1 }
            unsafe extern "C" fn single_get(list: *const ClapInputEvents, index: u32) -> *const c_void {
                if index == 0 {
                    let ctx = unsafe { (*list).ctx as *const SingleEventCtx };
                    unsafe { (*ctx).event_ptr }
                } else {
                    std::ptr::null()
                }
            }

            // SAFETY: CLAP spec requires flush() to consume all events synchronously
            // before returning. Stack allocation is safe because event/ctx outlive the flush call.
            let ctx = SingleEventCtx { event_ptr: &event as *const _ as *const c_void };
            let in_events = ClapInputEvents {
                ctx: &ctx as *const _ as *mut c_void,
                size: Some(single_size),
                get: Some(single_get),
            };

            unsafe { flush(self.plugin_ptr, &in_events, &*self.output_events) };
        }
        Ok(())
    }

    fn get_state(&self) -> PluginResult<Vec<u8>> {
        if self.state_ext.is_null() { return Ok(Vec::new()); }
        let state = unsafe { &*self.state_ext };

        // Create output stream that writes to a Vec<u8>
        struct WriteCtx { data: Vec<u8> }
        unsafe extern "C" fn stream_write(stream: *const ClapOStream, buffer: *const c_void, size: u64) -> i64 {
            let ctx = unsafe { &mut *((*stream).ctx as *mut WriteCtx) };
            let slice = unsafe { std::slice::from_raw_parts(buffer as *const u8, size as usize) };
            ctx.data.extend_from_slice(slice);
            size as i64
        }

        let mut ctx = WriteCtx { data: Vec::new() };
        let ostream = ClapOStream {
            ctx: &mut ctx as *mut WriteCtx as *mut c_void,
            write: Some(stream_write),
        };

        let ok = state.save.map(|f| unsafe { f(self.plugin_ptr, &ostream) }).unwrap_or(false);
        if ok { Ok(ctx.data) } else { Ok(Vec::new()) }
    }

    fn set_state(&mut self, data: &[u8]) -> PluginResult<()> {
        if self.state_ext.is_null() || data.is_empty() { return Ok(()); }
        let state = unsafe { &*self.state_ext };

        // Create input stream that reads from a slice
        struct ReadCtx { data: *const u8, len: usize, pos: usize }
        unsafe extern "C" fn stream_read(stream: *const ClapIStream, buffer: *mut c_void, size: u64) -> i64 {
            let ctx = unsafe { &mut *((*stream).ctx as *mut ReadCtx) };
            let remaining = ctx.len - ctx.pos;
            let to_read = (size as usize).min(remaining);
            if to_read == 0 { return 0; }
            unsafe { std::ptr::copy_nonoverlapping(ctx.data.add(ctx.pos), buffer as *mut u8, to_read) };
            ctx.pos += to_read;
            to_read as i64
        }

        let mut ctx = ReadCtx { data: data.as_ptr(), len: data.len(), pos: 0 };
        let istream = ClapIStream {
            ctx: &mut ctx as *mut ReadCtx as *mut c_void,
            read: Some(stream_read),
        };

        let ok = state.load.map(|f| unsafe { f(self.plugin_ptr, &istream) }).unwrap_or(false);
        if ok {
            // Re-cache params after state load (values may have changed)
            self.cache_params();
        }
        Ok(())
    }

    fn latency(&self) -> usize {
        self.latency_samples
    }

    fn has_editor(&self) -> bool {
        !self.gui_ext.is_null()
    }

    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    fn open_editor(&mut self, _parent: *mut std::ffi::c_void) -> PluginResult<()> {
        if self.gui_ext.is_null() {
            return Err(PluginError::UnsupportedFormat("CLAP plugin has no GUI extension".into()));
        }
        let gui = unsafe { &*self.gui_ext };

        // Determine platform API
        #[cfg(target_os = "macos")]
        let api = CLAP_WINDOW_API_COCOA;
        #[cfg(target_os = "windows")]
        let api = CLAP_WINDOW_API_WIN32;
        #[cfg(target_os = "linux")]
        let api = CLAP_WINDOW_API_X11;

        let api_ptr = api.as_ptr() as *const c_char;

        // Check API support
        let supported = gui.is_api_supported
            .map(|f| unsafe { f(self.plugin_ptr, api_ptr, true) })
            .unwrap_or(false);
        if !supported {
            return Err(PluginError::UnsupportedFormat("CLAP GUI: platform API not supported".into()));
        }

        // Create floating GUI
        let created = gui.create
            .map(|f| unsafe { f(self.plugin_ptr, api_ptr, true) })
            .unwrap_or(false);
        if !created {
            return Err(PluginError::InitFailed("CLAP GUI create() failed".into()));
        }
        self.gui_created = true;

        // Get initial size
        let mut w = 800u32;
        let mut h = 600u32;
        if let Some(get_size) = gui.get_size {
            unsafe { get_size(self.plugin_ptr, &mut w, &mut h) };
        }
        self.gui_width = w;
        self.gui_height = h;

        // Show
        let _shown = gui.show.map(|f| unsafe { f(self.plugin_ptr) });

        log::info!("CLAP GUI opened: {}x{}", w, h);
        Ok(())
    }

    fn close_editor(&mut self) -> PluginResult<()> {
        if self.gui_created && !self.gui_ext.is_null() {
            let gui = unsafe { &*self.gui_ext };
            if let Some(hide) = gui.hide {
                unsafe { hide(self.plugin_ptr) };
            }
            if let Some(destroy) = gui.destroy {
                unsafe { destroy(self.plugin_ptr) };
            }
            self.gui_created = false;
        }
        Ok(())
    }

    fn editor_size(&self) -> Option<(u32, u32)> {
        if !self.gui_created || self.gui_ext.is_null() { return None; }
        let gui = unsafe { &*self.gui_ext };
        let mut w = self.gui_width;
        let mut h = self.gui_height;
        if let Some(get_size) = gui.get_size {
            unsafe { get_size(self.plugin_ptr, &mut w, &mut h) };
        }
        Some((w, h))
    }

    fn resize_editor(&mut self, width: u32, height: u32) -> PluginResult<()> {
        if !self.gui_created || self.gui_ext.is_null() {
            return Err(PluginError::ProcessingError("GUI not open".into()));
        }
        let gui = unsafe { &*self.gui_ext };
        if let Some(set_size) = gui.set_size {
            unsafe { set_size(self.plugin_ptr, width, height) };
            self.gui_width = width;
            self.gui_height = height;
        }
        Ok(())
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CLAP FEATURES
// ═══════════════════════════════════════════════════════════════════════════

/// CLAP-specific features
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClapFeature {
    Instrument,
    AudioEffect,
    NoteEffect,
    Analyzer,
    Synthesizer,
    Sampler,
    Drum,
    Filter,
    Phaser,
    Equalizer,
    Deesser,
    Compressor,
    Expander,
    Gate,
    Limiter,
    Delay,
    Reverb,
    Flanger,
    Chorus,
    Tremolo,
    Distortion,
    Transient,
    Mastering,
    Utility,
    Pitch,
    Glitch,
    Mono,
    Stereo,
    Surround,
    Ambisonic,
}

impl ClapFeature {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Instrument => "instrument",
            Self::AudioEffect => "audio-effect",
            Self::NoteEffect => "note-effect",
            Self::Analyzer => "analyzer",
            Self::Synthesizer => "synthesizer",
            Self::Sampler => "sampler",
            Self::Drum => "drum",
            Self::Filter => "filter",
            Self::Phaser => "phaser",
            Self::Equalizer => "equalizer",
            Self::Deesser => "de-esser",
            Self::Compressor => "compressor",
            Self::Expander => "expander",
            Self::Gate => "gate",
            Self::Limiter => "limiter",
            Self::Delay => "delay",
            Self::Reverb => "reverb",
            Self::Flanger => "flanger",
            Self::Chorus => "chorus",
            Self::Tremolo => "tremolo",
            Self::Distortion => "distortion",
            Self::Transient => "transient-shaper",
            Self::Mastering => "mastering",
            Self::Utility => "utility",
            Self::Pitch => "pitch",
            Self::Glitch => "glitch",
            Self::Mono => "mono",
            Self::Stereo => "stereo",
            Self::Surround => "surround",
            Self::Ambisonic => "ambisonic",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clap_host_creation() {
        let host = ClapHost::new();
        assert!(host.descriptors.is_empty());
    }

    #[test]
    fn test_clap_feature() {
        assert_eq!(ClapFeature::Compressor.as_str(), "compressor");
        assert_eq!(ClapFeature::Reverb.as_str(), "reverb");
    }
}
