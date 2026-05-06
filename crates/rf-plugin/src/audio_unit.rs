//! AudioUnit Plugin Host (macOS only)
//!
//! Loads and hosts AudioUnit plugins on macOS.
//! Reference: <https://developer.apple.com/documentation/audiounit>
//!
//! # Architecture
//!
//! Audio rendering uses `au_render_create/process/destroy` from au_host.m — these
//! call `AudioUnitRender()` directly on the audio thread (AU spec requires this to
//! be render-thread safe after `AudioUnitInitialize()` returns).
//!
//! GUI is opened out-of-process via rf-plugin-host subprocess (avoids Flutter Metal conflict).

use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};

use parking_lot::Mutex;

use crate::scanner::{PluginCategory, PluginInfo, PluginType};
use crate::{
    AudioBuffer, ParameterInfo, PluginError, PluginInstance, PluginResult, ProcessContext,
};

// ─────────────────────────────────────────────────────────────────────────────
// FFI: au_host.m render path (macOS only)
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(target_os = "macos")]
unsafe extern "C" {
    /// Create AU render instance (allocates + initializes AU for audio processing).
    /// Returns opaque handle (AURenderCtx*) or NULL on failure.
    /// NOT audio-thread safe — call from init/setup thread.
    fn au_render_create(
        component_type: u32,
        component_subtype: u32,
        component_manufacturer: u32,
        sample_rate: f64,
        max_frames: u32,
        n_channels: u32,
    ) -> *mut c_void;

    /// Process one block: calls AudioUnitRender internally.
    /// AUDIO THREAD SAFE (no ObjC, no alloc, no locks).
    /// Returns 0 on success, non-zero AU OSStatus on failure.
    fn au_render_process(
        handle: *mut c_void,
        in_ptrs: *const *const f32,
        out_ptrs: *const *mut f32,
        n_channels: u32,
        n_frames: u32,
    ) -> i32;

    /// Set parameter value. Audio-thread safe for most AUs.
    fn au_render_set_param(handle: *mut c_void, param_id: u32, value: f32);

    /// Get plugin latency in samples (call from non-audio thread).
    fn au_render_get_latency(handle: *mut c_void) -> u32;

    /// Enumerate AU parameters — calls `callback` once per parameter.
    fn au_render_query_params(
        handle: *mut c_void,
        user_data: *mut c_void,
        callback: unsafe extern "C" fn(
            user_data: *mut c_void,
            param_id: u32,
            name: *const c_char,
            min_val: f32,
            max_val: f32,
            default_val: f32,
            flags: u32,
        ),
    );

    /// Send a single MIDI event to the AU instance.
    /// Uses MusicDeviceMIDIEvent — audio-thread safe, zero allocations.
    /// Returns 0 on success, non-zero OSStatus on failure (harmless for non-MIDI AUs).
    fn au_render_send_midi(
        handle: *mut c_void,
        status: u8,
        data1: u8,
        data2: u8,
        sample_offset: u32,
    ) -> i32;

    /// Reset AU internal state (e.g., on transport restart).
    fn au_render_reset(handle: *mut c_void);

    /// Destroy render instance (uninitializes + disposes AU, frees context).
    /// NOT audio-thread safe.
    fn au_render_destroy(handle: *mut c_void);

    /// Scan all installed AU plugins via AudioComponentFindNext.
    fn au_host_scan_plugins(
        user_data: *mut c_void,
        callback: unsafe extern "C" fn(
            user_data: *mut c_void,
            name: *const c_char,
            manufacturer: *const c_char,
            comp_type: u32,
            comp_subtype: u32,
            comp_mfr: u32,
        ),
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Scan callback — collects AUDescriptors from au_host_scan_plugins
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(target_os = "macos")]
struct ScanAccumulator {
    descriptors: Vec<AUDescriptor>,
}

#[cfg(target_os = "macos")]
unsafe extern "C" fn scan_callback(
    user_data: *mut c_void,
    name: *const c_char,
    manufacturer: *const c_char,
    comp_type: u32,
    comp_subtype: u32,
    comp_mfr: u32,
) {
    let acc = unsafe { &mut *(user_data as *mut ScanAccumulator) };

    let name_str = if name.is_null() {
        "Unknown".to_string()
    } else {
        unsafe { CStr::from_ptr(name) }.to_string_lossy().into_owned()
    };
    let mfr_str = if manufacturer.is_null() {
        "Unknown".to_string()
    } else {
        unsafe { CStr::from_ptr(manufacturer) }.to_string_lossy().into_owned()
    };

    // Only include audio-processing types (skip Output, FormatConverter, Panner)
    let au_type = AUType::from_u32(comp_type);
    let include = matches!(
        au_type,
        Some(AUType::Effect | AUType::MusicEffect | AUType::Instrument
             | AUType::Generator | AUType::MidiProcessor | AUType::Mixer)
    );
    if !include { return; }

    let desc = AUComponentDescription::new(
        au_type.unwrap(),
        comp_subtype,
        comp_mfr,
    );

    // Derive bundle path from system paths — approximation for display
    let bundle_path = dirs_next::home_dir()
        .map(|h| h.join("Library/Audio/Plug-Ins/Components").join(format!("{}.component", name_str)))
        .unwrap_or_else(|| PathBuf::from(format!("/Library/Audio/Plug-Ins/Components/{}.component", name_str)));

    let has_midi = matches!(au_type, Some(AUType::Instrument | AUType::MidiProcessor | AUType::MusicEffect));
    let is_instr = matches!(au_type, Some(AUType::Instrument | AUType::Generator));

    acc.descriptors.push(AUDescriptor {
        name: name_str,
        manufacturer: mfr_str,
        version: "1.0.0".to_string(),
        description: desc,
        bundle_path,
        is_sandboxed: false,
        is_v3: false,
        audio_inputs: if is_instr { 0 } else { 2 },
        audio_outputs: 2,
        has_midi_input: has_midi,
        has_custom_view: true,
    });
}

// ─────────────────────────────────────────────────────────────────────────────
// Parameter query accumulator
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(target_os = "macos")]
struct ParamQueryResult {
    params: Vec<ParameterInfo>,
}

#[cfg(target_os = "macos")]
unsafe extern "C" fn param_query_callback(
    user_data: *mut c_void,
    param_id: u32,
    name: *const c_char,
    min_val: f32,
    max_val: f32,
    default_val: f32,
    _flags: u32,
) {
    let result = unsafe { &mut *(user_data as *mut ParamQueryResult) };
    let name_str = if name.is_null() {
        format!("Param {}", param_id)
    } else {
        unsafe { CStr::from_ptr(name) }.to_string_lossy().into_owned()
    };
    let range = max_val - min_val;
    let normalized = if range > 0.0 { (default_val - min_val) / range } else { 0.5 };
    result.params.push(ParameterInfo {
        id: param_id,
        name: name_str,
        unit: "".to_string(),
        min: min_val as f64,
        max: max_val as f64,
        default: normalized as f64,
        normalized: normalized as f64,
        steps: 0,
        automatable: true,
        read_only: false,
    });
}

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

    /// Scan for AudioUnit plugins using AudioComponentFindNext (real component codes).
    #[cfg(target_os = "macos")]
    pub fn scan(&mut self) -> PluginResult<Vec<AUDescriptor>> {
        let mut acc = ScanAccumulator { descriptors: Vec::new() };

        // Use au_host_scan_plugins which calls AudioComponentFindNext — gives us
        // REAL fourcc component type/subtype/manufacturer codes, not guesses.
        unsafe {
            au_host_scan_plugins(
                &mut acc as *mut ScanAccumulator as *mut c_void,
                scan_callback,
            );
        }

        // Cache discovered plugins
        for desc in &acc.descriptors {
            let id = desc.description.identifier();
            self.descriptors.insert(id, desc.clone());
        }

        log::info!("Discovered {} AudioUnit plugins (via AudioComponentFindNext)", acc.descriptors.len());
        Ok(acc.descriptors)
    }

    #[cfg(not(target_os = "macos"))]
    pub fn scan(&mut self) -> PluginResult<Vec<AUDescriptor>> {
        Ok(Vec::new())
    }

    // scan_directory and scan_component are replaced by au_host_scan_plugins C FFI
    // which uses AudioComponentFindNext for real component codes.

    /// Load a plugin instance by identifier
    pub fn load(&self, identifier: &str) -> PluginResult<AudioUnitInstance> {
        let descriptor = self
            .descriptors
            .get(identifier)
            .ok_or_else(|| PluginError::NotFound(identifier.to_string()))?;

        AudioUnitInstance::new(descriptor.clone())
    }

    /// Load a plugin from path — scans the path to find real component codes.
    pub fn load_from_path(path: &Path) -> PluginResult<AudioUnitInstance> {
        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown AU")
            .to_string();

        // Try to find matching descriptor in a fresh scan
        #[cfg(target_os = "macos")]
        {
            let mut host = AudioUnitHost::new();
            if let Ok(descs) = host.scan() {
                // Match by name (case-insensitive)
                let name_lower = name.to_lowercase();
                if let Some(desc) = descs.into_iter().find(|d| d.name.to_lowercase() == name_lower) {
                    return AudioUnitInstance::new(desc);
                }
            }
        }

        // Fallback descriptor (non-macOS or scan failed)
        let descriptor = AUDescriptor {
            name,
            manufacturer: "Unknown".to_string(),
            version: "1.0.0".to_string(),
            description: AUComponentDescription::new(
                AUType::Effect,
                0x70617373, // 'pass' — will fail render but won't crash
                0x52464f47,
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
    /// AU descriptor (contains the real fourcc component codes)
    descriptor: AUDescriptor,
    /// Is active (audio processing enabled)
    active: AtomicBool,
    /// Latency in samples (read from AU after initialize)
    latency: AtomicU64,
    /// Real AU parameters (populated in initialize())
    parameters: Vec<ParameterInfo>,
    /// Parameter values (normalized 0-1 for non-AU fallback path)
    param_values: Vec<f64>,
    /// Pending parameter changes (for flush on next process())
    param_queue: Mutex<Vec<ParamChange>>,
    /// Sample rate (bits of f64 stored in u64 for atomic)
    sample_rate: AtomicU64,
    /// Max block size
    max_block_size: usize,
    /// Editor is open (rf-plugin-host subprocess)
    editor_open: AtomicBool,
    /// Live GUI session (only Some while editor is open).
    /// Owned per-instance so close_editor can actually shut down the
    /// child process — pre-Front-2 the child was orphaned via
    /// `drop(stdin_handle)` and only died when the DAW did.
    gui_session: Mutex<Option<crate::gui_host::GuiSession>>,
    /// Opaque handle to AURenderCtx* (0 = not created yet / failed)
    /// Stored as usize so AtomicUsize can hold it safely.
    /// Only written during initialize() / drop() (non-audio thread).
    /// Read during process() (audio thread) — atomic load with Acquire ordering.
    au_render_handle: AtomicUsize,
}

// SAFETY: AURenderCtx is heap-allocated C struct.
// - The handle is written only from initialize() / drop() (non-audio thread, exclusive)
// - The handle is read from process() (audio thread, shared-read only)
// - au_render_process() in C is documented render-thread safe after AudioUnitInitialize()
// - No two threads can call process() and destroy() simultaneously (plugin chain holds RwLock)
unsafe impl Send for AudioUnitInstance {}
unsafe impl Sync for AudioUnitInstance {}

impl Drop for AudioUnitInstance {
    fn drop(&mut self) {
        let handle = self.au_render_handle.load(Ordering::SeqCst) as *mut c_void;
        if !handle.is_null() {
            #[cfg(target_os = "macos")]
            unsafe { au_render_destroy(handle); }
            self.au_render_handle.store(0, Ordering::SeqCst);
            log::debug!("Destroyed AU render handle for '{}'", self.info.name);
        }
    }
}

impl AudioUnitInstance {
    /// Create new AU instance from descriptor.
    /// Does NOT create the AU render instance yet — that happens in `initialize()`.
    pub fn new(descriptor: AUDescriptor) -> PluginResult<Self> {
        let id = format!(
            "au.{}.{}.{}",
            AUComponentDescription::fourcc_to_string(descriptor.description.component_type as u32),
            AUComponentDescription::fourcc_to_string(descriptor.description.component_subtype),
            AUComponentDescription::fourcc_to_string(descriptor.description.component_manufacturer),
        );

        log::info!(
            "Creating AudioUnit instance: '{}' [{}]",
            descriptor.name,
            id
        );

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
            parameters: Vec::new(), // populated in initialize() from real AU
            param_values: Vec::new(),
            param_queue: Mutex::new(Vec::with_capacity(MAX_PARAM_CHANGES)),
            sample_rate: AtomicU64::new((48000.0_f64).to_bits()),
            max_block_size: 4096,
            editor_open: AtomicBool::new(false),
            gui_session: Mutex::new(None),
            au_render_handle: AtomicUsize::new(0),
        })
    }

    /// Get AU descriptor
    pub fn descriptor(&self) -> &AUDescriptor {
        &self.descriptor
    }

    /// Flush pending parameter changes to the AU (called at block start).
    /// Uses try_lock() — on the audio thread we MUST NOT block.
    /// If the queue is contended, changes are deferred to the next block (~5ms worst case).
    fn flush_param_queue(&self) {
        let handle = self.au_render_handle.load(Ordering::Acquire) as *mut c_void;
        if handle.is_null() { return; }

        // try_lock: never blocks the audio thread. Skip if main thread holds the lock.
        if let Some(mut queue) = self.param_queue.try_lock() {
            #[cfg(target_os = "macos")]
            for change in queue.drain(..) {
                unsafe { au_render_set_param(handle, change.id, change.value as f32); }
            }
            #[cfg(not(target_os = "macos"))]
            queue.clear();
        }
        // If try_lock() fails: changes will be applied next block. Acceptable latency.
    }

    /// Is the AU render handle valid (AU was successfully initialized).
    pub fn is_render_ready(&self) -> bool {
        self.au_render_handle.load(Ordering::Acquire) != 0
    }
}

impl PluginInstance for AudioUnitInstance {
    fn info(&self) -> &PluginInfo {
        &self.info
    }

    fn initialize(&mut self, context: &ProcessContext) -> PluginResult<()> {
        log::info!(
            "Initializing AU plugin '{}' at {}Hz, block size {}",
            self.info.name,
            context.sample_rate,
            context.max_block_size
        );

        self.sample_rate.store(context.sample_rate.to_bits(), Ordering::SeqCst);
        self.max_block_size = context.max_block_size;

        // Destroy previous render handle if re-initializing
        let old_handle = self.au_render_handle.swap(0, Ordering::SeqCst) as *mut c_void;
        if !old_handle.is_null() {
            #[cfg(target_os = "macos")]
            unsafe { au_render_destroy(old_handle); }
        }

        #[cfg(target_os = "macos")]
        {
            let n_channels = (self.descriptor.audio_outputs as u32).max(2);
            let handle = unsafe {
                au_render_create(
                    self.descriptor.description.component_type as u32,
                    self.descriptor.description.component_subtype,
                    self.descriptor.description.component_manufacturer,
                    context.sample_rate,
                    context.max_block_size as u32,
                    n_channels,
                )
            };

            if handle.is_null() {
                log::warn!(
                    "au_render_create() failed for '{}' ({}) — plugin will passthrough",
                    self.info.name,
                    self.descriptor.description.identifier()
                );
                // Not a hard error: plugin will passthrough silently
            } else {
                self.au_render_handle.store(handle as usize, Ordering::SeqCst);
                log::info!("AU render handle created for '{}'", self.info.name);

                // Query real parameters from the AU
                let mut query = ParamQueryResult { params: Vec::new() };
                unsafe {
                    au_render_query_params(
                        handle,
                        &mut query as *mut ParamQueryResult as *mut c_void,
                        param_query_callback,
                    );
                }
                if !query.params.is_empty() {
                    log::debug!("AU '{}': {} parameters discovered", self.info.name, query.params.len());
                    self.param_values = query.params.iter().map(|p| p.normalized).collect();
                    self.parameters = query.params;
                }

                // Read initial latency
                let latency = unsafe { au_render_get_latency(handle) };
                self.latency.store(latency as u64, Ordering::SeqCst);
                if latency > 0 {
                    log::info!("AU '{}': {} samples latency", self.info.name, latency);
                }
            }
        }

        Ok(())
    }

    fn activate(&mut self) -> PluginResult<()> {
        self.active.store(true, Ordering::SeqCst);
        // Reset AU state on activate (clears delay lines, etc.)
        let handle = self.au_render_handle.load(Ordering::Acquire) as *mut c_void;
        if !handle.is_null() {
            #[cfg(target_os = "macos")]
            unsafe { au_render_reset(handle); }
        }
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
        midi_in: &rf_core::MidiBuffer,
        _midi_out: &mut rf_core::MidiBuffer,
        _context: &ProcessContext,
    ) -> PluginResult<()> {
        if !self.active.load(Ordering::Acquire) {
            // Not active → passthrough (ZeroCopyChain will handle bypass)
            output.copy_from(input);
            return Ok(());
        }

        // Flush queued parameter changes to AU before rendering
        self.flush_param_queue();

        let handle = self.au_render_handle.load(Ordering::Acquire) as *mut c_void;

        #[cfg(target_os = "macos")]
        if !handle.is_null() {
            // ── BUG#24 FIX: Forward MIDI events to AU via MusicDeviceMIDIEvent ──
            //
            // Must happen BEFORE AudioUnitRender so the AU processes the events
            // in the same block. MusicDeviceMIDIEvent is audio-thread safe —
            // zero allocations, zero locks, zero ObjC.
            if self.info.has_midi_input && !midi_in.is_empty() {
                for event in midi_in.events() {
                    let mut bytes = [0u8; 3];
                    let byte_len = event.to_bytes(&mut bytes);
                    if byte_len >= 1 {
                        unsafe {
                            au_render_send_midi(
                                handle,
                                bytes[0],
                                if byte_len >= 2 { bytes[1] } else { 0 },
                                if byte_len >= 3 { bytes[2] } else { 0 },
                                event.sample_offset,
                            );
                        }
                    }
                }
            }

            // ── AudioUnit rendering path ──────────────────────────────────────
            //
            // Build stack-allocated pointer arrays (zero heap allocation on audio thread).
            // Max 8 channels — covers stereo, quad, 5.1, 7.1.
            const MAX_CH: usize = 8;
            let n_ch = input.channels.min(output.channels).min(MAX_CH);
            let n_frames = input.samples.min(output.samples);

            // Stack arrays of channel pointers
            let mut in_ptrs  = [std::ptr::null::<f32>(); MAX_CH];
            let mut out_ptrs = [std::ptr::null_mut::<f32>(); MAX_CH];

            for ch in 0..n_ch {
                if let Some(s) = input.channel(ch)  { in_ptrs[ch]  = s.as_ptr(); }
                if let Some(s) = output.channel_mut(ch) { out_ptrs[ch] = s.as_mut_ptr(); }
            }

            let result = unsafe {
                au_render_process(
                    handle,
                    in_ptrs.as_ptr(),
                    out_ptrs.as_ptr(),
                    n_ch as u32,
                    n_frames as u32,
                )
            };

            if result != 0 {
                // AU render failed — passthrough to avoid silence artifacts
                log::trace!("AU '{}': AudioUnitRender returned {}", self.info.name, result);
                output.copy_from(input);
            }

            return Ok(());
        }

        // ── Fallback passthrough (AU not initialized / non-macOS) ─────────────
        output.copy_from(input);
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
        // Find the real AU parameter range for denormalization
        let (au_value, normalized) = if let Some(param) = self.parameters.iter().find(|p| p.id == id) {
            let range = param.max - param.min;
            let normalized = value.clamp(0.0, 1.0);
            let au_val = param.min + normalized * range;
            (au_val as f32, normalized)
        } else {
            // No param info — use value directly clamped to 0-1
            (value.clamp(0.0, 1.0) as f32, value.clamp(0.0, 1.0))
        };

        // Update cache
        if let Some(v) = self.param_values.get_mut(id as usize) {
            *v = normalized;
        }

        // Queue for audio-thread delivery (flush_param_queue uses real AU value)
        {
            let mut queue = self.param_queue.lock();
            if queue.len() < MAX_PARAM_CHANGES {
                queue.push(ParamChange { id, value: au_value as f64 });
            }
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
                    // Re-apply to AU if handle exists (handles project load restore)
                    if let Some(param) = self.parameters.get(i) {
                        let range = param.max - param.min;
                        let au_val = (param.min + v * range) as f32;
                        let handle = self.au_render_handle.load(Ordering::Acquire) as *mut c_void;
                        if !handle.is_null() {
                            #[cfg(target_os = "macos")]
                            unsafe { au_render_set_param(handle, param.id, au_val); }
                        }
                    }
                }
            }
        }
        Ok(())
    }

    fn latency(&self) -> usize {
        // Try live read from AU (handles plugins that change latency at runtime)
        #[cfg(target_os = "macos")]
        {
            let handle = self.au_render_handle.load(Ordering::Acquire) as *mut c_void;
            if !handle.is_null() {
                let live = unsafe { au_render_get_latency(handle) };
                self.latency.store(live as u64, Ordering::Relaxed);
                return live as usize;
            }
        }
        self.latency.load(Ordering::Relaxed) as usize
    }

    fn has_editor(&self) -> bool {
        self.descriptor.has_custom_view
    }

    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    fn open_editor(&mut self, _parent: *mut std::ffi::c_void) -> PluginResult<()> {
        if self.editor_open.load(Ordering::SeqCst) {
            return Ok(());
        }

        #[cfg(target_os = "macos")]
        {
            // Out-of-process GUI: Flutter's Metal pipeline conflicts with
            // plugin GUI rendering in the same process. The `GuiSession`
            // owns the rf-plugin-host child handle for the editor's
            // lifetime so close_editor can actually shut it down.
            let plugin_name = self.info.name.clone();
            let helper_path = crate::find_plugin_host_binary()
                .ok_or_else(|| PluginError::InitError(
                    "rf-plugin-host binary not found".into(),
                ))?;

            let session = crate::gui_host::GuiSession::spawn(helper_path, plugin_name.clone())
                .map_err(|e| PluginError::InitError(format!(
                    "rf-plugin-host spawn failed: {}", e
                )))?;

            *self.gui_session.lock() = Some(session);
            self.editor_open.store(true, Ordering::SeqCst);
            log::info!("AU editor opened for '{}'", plugin_name);
            Ok(())
        }

        #[cfg(not(target_os = "macos"))]
        {
            Err(PluginError::UnsupportedFormat(
                "AudioUnit only supported on macOS".into(),
            ))
        }
    }

    fn close_editor(&mut self) -> PluginResult<()> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return Ok(());
        }

        // Drop the session — its `Drop` impl sends graceful close, waits
        // 200 ms, then kills. No more zombie host processes.
        let session = self.gui_session.lock().take();
        drop(session);

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
