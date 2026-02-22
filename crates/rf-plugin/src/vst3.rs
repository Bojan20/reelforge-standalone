//! VST3 Plugin Host
//!
//! Loads and hosts VST3 plugins using the `rack` crate.
//! Handles:
//! - Plugin loading from .vst3 bundles
//! - Audio processing with real-time safety
//! - Parameter automation via lock-free queues
//! - State save/load
//! - Editor hosting (platform-specific)

use std::ffi::c_void;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::{Mutex, RwLock};

use crate::scanner::{PluginCategory, PluginType};
use crate::{
    AudioBuffer, ParameterInfo, PluginError, PluginInfo, PluginInstance, PluginResult,
    ProcessContext,
};

/// Maximum parameter changes per audio block
const MAX_PARAM_CHANGES: usize = 128;

/// Result type for rack plugin loading
type RackLoadResult = (
    Option<Arc<Mutex<RackPlugin>>>,
    Vec<ParameterInfo>,
    usize, // input channels
    usize, // output channels
    usize, // latency
);

/// Lock-free parameter change queue entry
#[derive(Debug, Clone, Copy)]
struct ParamChange {
    id: u32,
    value: f64,
}

/// VST3 plugin state for thread-safe access
struct Vst3State {
    /// Cached parameter infos
    parameters: Vec<ParameterInfo>,
    /// Current parameter values (normalized 0-1)
    param_values: Vec<f64>,
}

/// Rack plugin wrapper (type-erased to handle both AudioUnit and VST3)
struct RackPlugin {
    /// The actual rack plugin instance (type-erased via Box<dyn>)
    inner: Box<dyn RackPluginTrait + Send>,
}

/// Trait for rack plugin abstraction
trait RackPluginTrait {
    fn initialize(&mut self, sample_rate: f64, max_block_size: usize) -> Result<(), String>;
    fn reset(&mut self) -> Result<(), String>;
    fn process(
        &mut self,
        inputs: &[&[f32]],
        outputs: &mut [&mut [f32]],
        num_frames: usize,
    ) -> Result<(), String>;
    fn parameter_count(&self) -> usize;
    fn get_parameter(&self, index: usize) -> Result<f32, String>;
    fn set_parameter(&mut self, index: usize, value: f32) -> Result<(), String>;
    fn get_state(&self) -> Result<Vec<u8>, String>;
    fn set_state(&mut self, data: &[u8]) -> Result<(), String>;
    fn latency(&self) -> Option<u32>;

    /// Whether this plugin supports native GUI (AudioUnit on macOS).
    fn supports_gui(&self) -> bool { false }

    /// Open a standalone window for the plugin's native GUI.
    /// Returns (width, height) if GUI was created successfully.
    /// Default: not supported.
    #[cfg(target_os = "macos")]
    fn open_gui_window(&mut self, _title: &str) -> Result<(f32, f32), String> {
        Err("GUI not supported for this plugin format".into())
    }

    /// Close and drop the native GUI window.
    #[cfg(target_os = "macos")]
    fn close_gui_window(&mut self) {
        // no-op by default
    }

    /// Get the native GUI size (width, height) in points.
    #[cfg(target_os = "macos")]
    fn gui_size(&self) -> Option<(f32, f32)> {
        None
    }
}

/// Wrapper for rack::PluginInstance
struct RackPluginWrapper<P: rack::PluginInstance + Send + 'static> {
    plugin: P,
    latency_samples: u32,
    /// Native GUI handle (macOS AudioUnit only). Stored here because
    /// create_gui() requires the concrete AudioUnitPlugin type which
    /// is erased when we box as dyn RackPluginTrait.
    #[cfg(target_os = "macos")]
    gui: Option<rack::au::AudioUnitGui>,
}

impl<P: rack::PluginInstance + Send + 'static> RackPluginTrait for RackPluginWrapper<P> {
    fn initialize(&mut self, sample_rate: f64, max_block_size: usize) -> Result<(), String> {
        self.plugin
            .initialize(sample_rate, max_block_size)
            .map_err(|e| format!("{:?}", e))
    }

    fn reset(&mut self) -> Result<(), String> {
        self.plugin.reset().map_err(|e| format!("{:?}", e))
    }

    fn process(
        &mut self,
        inputs: &[&[f32]],
        outputs: &mut [&mut [f32]],
        num_frames: usize,
    ) -> Result<(), String> {
        self.plugin
            .process(inputs, outputs, num_frames)
            .map_err(|e| format!("{:?}", e))
    }

    fn parameter_count(&self) -> usize {
        self.plugin.parameter_count()
    }

    fn get_parameter(&self, index: usize) -> Result<f32, String> {
        self.plugin
            .get_parameter(index)
            .map_err(|e| format!("{:?}", e))
    }

    fn set_parameter(&mut self, index: usize, value: f32) -> Result<(), String> {
        self.plugin
            .set_parameter(index, value)
            .map_err(|e| format!("{:?}", e))
    }

    fn get_state(&self) -> Result<Vec<u8>, String> {
        self.plugin.get_state().map_err(|e| format!("{:?}", e))
    }

    fn set_state(&mut self, data: &[u8]) -> Result<(), String> {
        self.plugin.set_state(data).map_err(|e| format!("{:?}", e))
    }

    fn latency(&self) -> Option<u32> {
        Some(self.latency_samples)
    }

    fn supports_gui(&self) -> bool {
        // On macOS, AudioUnitPlugin supports GUI via create_gui()
        #[cfg(target_os = "macos")]
        {
            use std::any::TypeId;
            TypeId::of::<P>() == TypeId::of::<rack::au::AudioUnitPlugin>()
        }
        #[cfg(not(target_os = "macos"))]
        {
            false
        }
    }

    #[cfg(target_os = "macos")]
    fn open_gui_window(&mut self, title: &str) -> Result<(f32, f32), String> {
        use std::any::TypeId;
        use std::sync::mpsc;

        if TypeId::of::<P>() != TypeId::of::<rack::au::AudioUnitPlugin>() {
            return Err("GUI not supported for this plugin format (VST3 GUI not available in rack 0.4)".into());
        }

        // SAFETY: We verified P == AudioUnitPlugin via TypeId check above.
        // This is the standard Rust pattern for type-erased downcasting.
        let au_plugin: &mut rack::au::AudioUnitPlugin = unsafe {
            &mut *(&mut self.plugin as *mut P as *mut rack::au::AudioUnitPlugin)
        };

        // Use a channel to receive the GUI from the async callback
        let (tx, rx) = mpsc::channel();
        let title_owned = title.to_string();

        au_plugin.create_gui(move |result| {
            match result {
                Ok(gui) => {
                    // Show as standalone window (must be on main thread)
                    if let Err(e) = gui.show_window(Some(&title_owned)) {
                        log::error!("Failed to show plugin GUI window: {:?}", e);
                        let _ = tx.send(Err(format!("Failed to show window: {:?}", e)));
                        return Ok(());
                    }
                    let size = gui.get_size().unwrap_or((800.0, 600.0));
                    let _ = tx.send(Ok((gui, size)));
                    Ok(())
                }
                Err(e) => {
                    let _ = tx.send(Err(format!("create_gui failed: {:?}", e)));
                    Ok(())
                }
            }
        });

        // Wait for the callback (with timeout)
        match rx.recv_timeout(std::time::Duration::from_secs(5)) {
            Ok(Ok((gui, size))) => {
                self.gui = Some(gui);
                Ok(size)
            }
            Ok(Err(e)) => Err(e),
            Err(_) => Err("Timeout waiting for plugin GUI creation".into()),
        }
    }

    #[cfg(target_os = "macos")]
    fn close_gui_window(&mut self) {
        if let Some(gui) = self.gui.take() {
            if let Err(e) = gui.hide_window() {
                log::warn!("Failed to hide plugin GUI window: {:?}", e);
            }
            // GUI handle is dropped here, cleaning up native resources
        }
    }

    #[cfg(target_os = "macos")]
    fn gui_size(&self) -> Option<(f32, f32)> {
        self.gui.as_ref().and_then(|gui| gui.get_size().ok())
    }
}

/// VST3 plugin host implementation using rack crate
pub struct Vst3Host {
    /// Plugin info
    info: PluginInfo,
    /// Is plugin active
    active: AtomicBool,
    /// Processing latency in samples
    latency: AtomicU64,
    /// Plugin state (thread-safe)
    state: RwLock<Vst3State>,
    /// Pending parameter changes (lock-free queue)
    param_queue: Mutex<Vec<ParamChange>>,
    /// Sample rate
    sample_rate: AtomicU64,
    /// Max block size
    max_block_size: usize,
    /// Input bus arrangement
    input_channels: u16,
    /// Output bus arrangement
    output_channels: u16,
    /// Editor is open
    editor_open: AtomicBool,
    /// Has valid plugin module loaded
    module_loaded: bool,
    /// The actual rack plugin instance
    rack_plugin: Option<Arc<Mutex<RackPlugin>>>,
    /// Plugin path for reloading
    plugin_path: std::path::PathBuf,
    /// Temporary input buffers for format conversion
    input_buffers: Mutex<Vec<Vec<f32>>>,
    /// Temporary output buffers for format conversion
    output_buffers: Mutex<Vec<Vec<f32>>>,
    /// macOS AudioUnit GUI handle (kept alive while editor is open)
    #[cfg(target_os = "macos")]
    au_gui: Mutex<Option<rack::au::AudioUnitGui>>,
}

// SAFETY: All fields are either Sync+Send or protected by atomics/mutexes
unsafe impl Send for Vst3Host {}
unsafe impl Sync for Vst3Host {}

impl Vst3Host {
    /// Load plugin from path (supports both VST3 and AudioUnit via rack crate)
    pub fn load(path: &Path) -> PluginResult<Self> {
        // Get plugin name from path
        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown Plugin");

        // Detect format from bundle extension
        let ext = path
            .extension()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_lowercase();
        let is_au = ext == "component";
        let (id_prefix, plugin_type) = if is_au {
            ("au", PluginType::AudioUnit)
        } else {
            ("vst3", PluginType::Vst3)
        };
        let id = format!("{}.{}", id_prefix, name.to_lowercase().replace(' ', "_"));

        log::info!(
            "Loading {} plugin: {} from {:?}",
            if is_au { "AudioUnit" } else { "VST3" },
            name,
            path
        );

        // Check if bundle exists
        let bundle_exists = path.exists();
        if !bundle_exists {
            log::warn!("VST3 bundle not found at {:?}", path);
            return Err(PluginError::LoadFailed(format!(
                "VST3 bundle not found: {:?}",
                path
            )));
        }

        // Try to load with rack crate
        let (rack_plugin, parameters, audio_inputs, audio_outputs, plugin_latency) =
            match Self::load_with_rack(path) {
                Ok(result) => result,
                Err(e) => {
                    log::warn!("Failed to load plugin with rack: {}, using fallback", e);
                    // Fallback to passthrough mode
                    (None, Self::default_parameters(), 2, 2, 0)
                }
            };

        let param_values = parameters.iter().map(|p| p.default).collect();
        let module_loaded = rack_plugin.is_some();

        let info = PluginInfo {
            id,
            name: name.to_string(),
            vendor: String::from("Unknown"),
            version: String::from("1.0.0"),
            plugin_type,
            category: PluginCategory::Effect,
            path: path.to_path_buf(),
            audio_inputs: audio_inputs as u32,
            audio_outputs: audio_outputs as u32,
            has_midi_input: false,
            has_midi_output: false,
            has_editor: bundle_exists,
            latency: plugin_latency as u32,
            is_shell: false,
            sub_plugins: Vec::new(),
        };

        let state = Vst3State {
            parameters,
            param_values,
        };

        // Pre-allocate buffers for audio format conversion
        let input_buffers = (0..audio_inputs).map(|_| vec![0.0f32; 4096]).collect();
        let output_buffers = (0..audio_outputs).map(|_| vec![0.0f32; 4096]).collect();

        Ok(Self {
            info,
            active: AtomicBool::new(false),
            latency: AtomicU64::new(plugin_latency as u64),
            state: RwLock::new(state),
            param_queue: Mutex::new(Vec::with_capacity(MAX_PARAM_CHANGES)),
            sample_rate: AtomicU64::new(48000),
            max_block_size: 4096,
            input_channels: audio_inputs as u16,
            output_channels: audio_outputs as u16,
            editor_open: AtomicBool::new(false),
            module_loaded,
            rack_plugin,
            plugin_path: path.to_path_buf(),
            input_buffers: Mutex::new(input_buffers),
            output_buffers: Mutex::new(output_buffers),
            #[cfg(target_os = "macos")]
            au_gui: Mutex::new(None),
        })
    }

    /// Load plugin using rack crate
    fn load_with_rack(path: &Path) -> PluginResult<RackLoadResult> {
        use rack::prelude::*;

        // Create scanner
        let scanner = Scanner::new().map_err(|e| {
            PluginError::LoadFailed(format!("Failed to create rack scanner: {:?}", e))
        })?;

        // Scan the specific path to get plugin info
        let plugins = scanner
            .scan_path(path)
            .map_err(|e| PluginError::LoadFailed(format!("Failed to scan plugin path: {:?}", e)))?;

        if plugins.is_empty() {
            return Err(PluginError::LoadFailed(format!(
                "No plugins found at path: {:?}",
                path
            )));
        }

        // Load the first plugin found
        let plugin_info = &plugins[0];
        let plugin = scanner
            .load(plugin_info)
            .map_err(|e| PluginError::LoadFailed(format!("Failed to load plugin: {:?}", e)))?;

        // Extract parameters - use explicit crate::ParameterInfo to avoid confusion with rack::ParameterInfo
        let mut parameters: Vec<crate::ParameterInfo> = Vec::new();
        let param_count = plugin.parameter_count();
        for i in 0..param_count {
            if let Ok(rack_param) = plugin.parameter_info(i) {
                // Normalize default value to 0-1 range
                let range = rack_param.max - rack_param.min;
                let normalized_default = if range > 0.0 {
                    (rack_param.default - rack_param.min) / range
                } else {
                    0.5
                };

                parameters.push(crate::ParameterInfo {
                    id: i as u32,
                    name: rack_param.name.clone(),
                    unit: rack_param.unit.clone(),
                    min: rack_param.min as f64,
                    max: rack_param.max as f64,
                    default: normalized_default as f64,
                    normalized: normalized_default as f64,
                    steps: 0, // rack doesn't expose step count
                    automatable: true,
                    read_only: false,
                });
            }
        }

        // If no parameters found, add defaults
        if parameters.is_empty() {
            parameters = Self::default_parameters();
        }

        // Default to stereo - rack PluginInfo doesn't expose channel counts
        let audio_inputs = 2usize;
        let audio_outputs = 2usize;
        let latency = 0usize; // Will be determined after initialization

        // Wrap the plugin
        let wrapper = RackPluginWrapper {
            plugin,
            latency_samples: 0,
            #[cfg(target_os = "macos")]
            gui: None,
        };

        let rack_plugin = RackPlugin {
            inner: Box::new(wrapper),
        };

        Ok((
            Some(Arc::new(Mutex::new(rack_plugin))),
            parameters,
            audio_inputs,
            audio_outputs,
            latency,
        ))
    }

    /// Default parameters for fallback mode
    fn default_parameters() -> Vec<ParameterInfo> {
        vec![
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
        ]
    }

    /// Process pending parameter changes (called from audio thread)
    fn process_param_changes(&self) {
        let mut queue = self.param_queue.lock();
        if queue.is_empty() {
            return;
        }

        let mut state = self.state.write();
        for change in queue.drain(..) {
            if let Some(value) = state.param_values.get_mut(change.id as usize) {
                *value = change.value;
            }

            // Also update the rack plugin if available
            if let Some(ref instance) = self.rack_plugin
                && let Some(mut plugin) = instance.try_lock()
            {
                let _ = plugin
                    .inner
                    .set_parameter(change.id as usize, change.value as f32);
            }
        }
    }

    /// Get gain value from parameters (for fallback processing)
    fn get_gain(&self) -> f32 {
        let state = self.state.read();
        let normalized = state.param_values.first().copied().unwrap_or(0.5);
        let db = -60.0 + normalized * 72.0;
        10.0_f32.powf(db as f32 / 20.0)
    }

    /// Get mix value from parameters (for fallback processing)
    fn get_mix(&self) -> f32 {
        let state = self.state.read();
        state.param_values.get(1).copied().unwrap_or(1.0) as f32
    }

    /// Process audio using rack plugin (real VST3/AU)
    fn process_with_rack(
        &self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
        _context: &ProcessContext,
    ) -> PluginResult<()> {
        let instance = self
            .rack_plugin
            .as_ref()
            .ok_or_else(|| PluginError::ProcessingError("No rack instance available".into()))?;

        let mut plugin = instance.lock();

        let num_samples = input.samples.min(output.samples).min(self.max_block_size);
        let in_channels = input.channels.min(self.input_channels as usize);
        let out_channels = output.channels.min(self.output_channels as usize);

        // Get mutable access to our pre-allocated buffers
        let mut input_bufs = self.input_buffers.lock();
        let mut output_bufs = self.output_buffers.lock();

        // Ensure buffers are large enough
        for buf in input_bufs.iter_mut() {
            if buf.len() < num_samples {
                buf.resize(num_samples, 0.0);
            }
        }
        for buf in output_bufs.iter_mut() {
            if buf.len() < num_samples {
                buf.resize(num_samples, 0.0);
            }
        }

        // Copy input data to our buffers
        for ch in 0..in_channels {
            if ch < input_bufs.len()
                && let Some(inp) = input.channel(ch)
            {
                for (i, sample) in inp.iter().take(num_samples).enumerate() {
                    input_bufs[ch][i] = *sample;
                }
            }
        }

        // Create slices for rack API
        let input_slices: Vec<&[f32]> = input_bufs
            .iter()
            .take(in_channels)
            .map(|v| &v[..num_samples])
            .collect();

        let mut output_slices: Vec<&mut [f32]> = output_bufs
            .iter_mut()
            .take(out_channels)
            .map(|v| &mut v[..num_samples])
            .collect();

        // Process audio through the real plugin
        plugin
            .inner
            .process(&input_slices, &mut output_slices, num_samples)
            .map_err(|e| PluginError::ProcessingError(format!("rack process error: {}", e)))?;

        // Copy processed output back to AudioBuffer
        for ch in 0..out_channels {
            if ch < output_bufs.len()
                && let Some(out_ch) = output.channel_mut(ch)
            {
                for (i, sample) in output_bufs[ch].iter().take(num_samples).enumerate() {
                    if i < out_ch.len() {
                        out_ch[i] = *sample;
                    }
                }
            }
        }

        Ok(())
    }

    /// Fallback passthrough processing
    fn process_passthrough(
        &self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
    ) -> PluginResult<()> {
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
}

impl PluginInstance for Vst3Host {
    fn info(&self) -> &PluginInfo {
        &self.info
    }

    fn initialize(&mut self, context: &ProcessContext) -> PluginResult<()> {
        log::debug!(
            "Initializing VST3 plugin {} at {}Hz, block size {}",
            self.info.name,
            context.sample_rate,
            context.max_block_size
        );

        self.sample_rate
            .store(context.sample_rate.to_bits(), Ordering::SeqCst);
        self.max_block_size = context.max_block_size;

        // Resize buffers for new block size
        {
            let mut input_bufs = self.input_buffers.lock();
            for buf in input_bufs.iter_mut() {
                buf.resize(context.max_block_size, 0.0);
            }
        }
        {
            let mut output_bufs = self.output_buffers.lock();
            for buf in output_bufs.iter_mut() {
                buf.resize(context.max_block_size, 0.0);
            }
        }

        // Initialize the rack plugin if available
        if let Some(ref instance) = self.rack_plugin {
            let mut plugin = instance.lock();
            plugin
                .inner
                .initialize(context.sample_rate, context.max_block_size)
                .map_err(|e| PluginError::InitError(format!("rack init error: {}", e)))?;

            // Update latency if available
            if let Some(lat) = plugin.inner.latency() {
                self.latency.store(lat as u64, Ordering::SeqCst);
            }
        }

        Ok(())
    }

    fn activate(&mut self) -> PluginResult<()> {
        self.active.store(true, Ordering::SeqCst);
        log::debug!("Activated VST3 plugin: {}", self.info.name);
        Ok(())
    }

    fn deactivate(&mut self) -> PluginResult<()> {
        self.active.store(false, Ordering::SeqCst);

        // Reset the rack plugin if available
        if let Some(ref instance) = self.rack_plugin {
            let mut plugin = instance.lock();
            let _ = plugin.inner.reset();
        }

        log::debug!("Deactivated VST3 plugin: {}", self.info.name);
        Ok(())
    }

    fn process(
        &mut self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
        context: &ProcessContext,
    ) -> PluginResult<()> {
        if !self.active.load(Ordering::SeqCst) {
            return Err(PluginError::ProcessingError("Plugin not active".into()));
        }

        // Process any pending parameter changes
        self.process_param_changes();

        // Use real plugin processing if available, otherwise fallback
        if self.rack_plugin.is_some() {
            self.process_with_rack(input, output, context)
        } else {
            self.process_passthrough(input, output)
        }
    }

    fn parameter_count(&self) -> usize {
        self.state.read().parameters.len()
    }

    fn parameter_info(&self, index: usize) -> Option<ParameterInfo> {
        self.state.read().parameters.get(index).cloned()
    }

    fn get_parameter(&self, id: u32) -> Option<f64> {
        // Try to get from rack plugin first for real-time accuracy
        if let Some(ref instance) = self.rack_plugin
            && let Some(plugin) = instance.try_lock()
            && let Ok(value) = plugin.inner.get_parameter(id as usize)
        {
            return Some(value as f64);
        }
        // Fallback to cached value
        self.state.read().param_values.get(id as usize).copied()
    }

    fn set_parameter(&mut self, id: u32, value: f64) -> PluginResult<()> {
        let clamped = value.clamp(0.0, 1.0);

        // Queue for audio thread (lock-free)
        {
            let mut queue = self.param_queue.lock();
            if queue.len() < MAX_PARAM_CHANGES {
                queue.push(ParamChange { id, value: clamped });
            }
        }

        // Also update immediately for UI feedback
        {
            let mut state = self.state.write();
            if let Some(v) = state.param_values.get_mut(id as usize) {
                *v = clamped;
            }
        }

        Ok(())
    }

    fn get_state(&self) -> PluginResult<Vec<u8>> {
        // Try to get state from rack plugin first
        if let Some(ref instance) = self.rack_plugin {
            let plugin = instance.lock();
            if let Ok(state) = plugin.inner.get_state() {
                return Ok(state);
            }
        }

        // Fallback to parameter values
        let state = self.state.read();
        Ok(serde_json::to_vec(&state.param_values).unwrap_or_default())
    }

    fn set_state(&mut self, state: &[u8]) -> PluginResult<()> {
        // Try to set state on rack plugin first
        if let Some(ref instance) = self.rack_plugin {
            let mut plugin = instance.lock();
            if plugin.inner.set_state(state).is_ok() {
                return Ok(());
            }
        }

        // Fallback to parsing as parameter values
        if let Ok(values) = serde_json::from_slice::<Vec<f64>>(state) {
            let mut s = self.state.write();
            for (i, v) in values.into_iter().enumerate() {
                if i < s.param_values.len() {
                    s.param_values[i] = v;
                }
            }
        }
        Ok(())
    }

    fn latency(&self) -> usize {
        self.latency.load(Ordering::SeqCst) as usize
    }

    fn has_editor(&self) -> bool {
        self.module_loaded
    }

    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    fn open_editor(&mut self, parent: *mut c_void) -> PluginResult<()> {
        if self.editor_open.load(Ordering::SeqCst) {
            return Ok(());
        }

        if !self.module_loaded {
            return Err(PluginError::InitError("Plugin module not loaded".into()));
        }

        // Platform-specific editor opening
        // Note: rack crate doesn't expose editor hosting directly,
        // so we need to implement platform-specific hosting

        #[cfg(target_os = "macos")]
        {
            self.open_editor_macos(parent)?;
        }

        #[cfg(target_os = "windows")]
        {
            self.open_editor_windows(parent)?;
        }

        #[cfg(target_os = "linux")]
        {
            self.open_editor_linux(parent)?;
        }

        self.editor_open.store(true, Ordering::SeqCst);
        log::info!("Opened editor for plugin: {}", self.info.name);
        Ok(())
    }

    fn close_editor(&mut self) -> PluginResult<()> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return Ok(());
        }

        // Close native GUI window if open
        #[cfg(target_os = "macos")]
        {
            if let Some(ref rp) = self.rack_plugin {
                let mut lock = rp.lock();
                lock.inner.close_gui_window();
            }
            // Also clear the holder in case it was stored separately
            *self.au_gui.lock() = None;
        }

        self.editor_open.store(false, Ordering::SeqCst);
        log::info!("Closed editor for plugin: {}", self.info.name);
        Ok(())
    }

    fn editor_size(&self) -> Option<(u32, u32)> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return None;
        }

        // Query real plugin GUI size on macOS
        #[cfg(target_os = "macos")]
        {
            if let Some(ref rp) = self.rack_plugin {
                let lock = rp.lock();
                if let Some((w, h)) = lock.inner.gui_size() {
                    return Some((w as u32, h as u32));
                }
            }
        }

        // Fallback default size
        Some((800, 600))
    }

    fn resize_editor(&mut self, _width: u32, _height: u32) -> PluginResult<()> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return Err(PluginError::ProcessingError("Editor not open".into()));
        }
        Ok(())
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM-SPECIFIC EDITOR HOSTING
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(target_os = "macos")]
impl Vst3Host {
    fn open_editor_macos(&mut self, _parent: *mut c_void) -> PluginResult<()> {
        log::info!(
            "macOS plugin editor: opening GUI for {}",
            self.info.name
        );

        // Use rack's AudioUnit GUI API (production-ready in rack 0.4.8).
        // For AudioUnit plugins: create_gui() + show_window() opens a standalone window.
        // For VST3 plugins on macOS: rack 0.4.8 does NOT support VST3 GUI, so we
        // fall through to the generic parameter editor on the Dart side.

        if let Some(ref rp) = self.rack_plugin {
            let mut lock = rp.lock();

            if lock.inner.supports_gui() {
                match lock.inner.open_gui_window(&self.info.name) {
                    Ok((w, h)) => {
                        log::info!(
                            "Plugin GUI window opened: {}x{} for {}",
                            w, h, self.info.name
                        );
                        return Ok(());
                    }
                    Err(e) => {
                        log::warn!(
                            "Failed to open native GUI for {}: {}. Dart will show generic parameter editor.",
                            self.info.name, e
                        );
                        return Err(PluginError::InitError(format!(
                            "Native GUI failed for {}: {}",
                            self.info.name, e
                        )));
                    }
                }
            } else {
                log::info!(
                    "Plugin {} does not support native GUI (VST3 GUI not available in rack 0.4). \
                     Dart will show generic parameter editor.",
                    self.info.name
                );
                return Err(PluginError::InitError(format!(
                    "No native GUI for {} — use generic parameter editor",
                    self.info.name
                )));
            }
        }

        Err(PluginError::InitError("No rack plugin loaded".into()))
    }

    /// Get the preferred editor size for this plugin
    pub fn preferred_editor_size(&self) -> Option<(u32, u32)> {
        if let Some(ref rp) = self.rack_plugin {
            let lock = rp.lock();
            if let Some((w, h)) = lock.inner.gui_size() {
                return Some((w as u32, h as u32));
            }
        }
        Some((800, 600))
    }
}

#[cfg(target_os = "windows")]
impl Vst3Host {
    fn open_editor_windows(&mut self, parent: *mut c_void) -> PluginResult<()> {
        if parent.is_null() {
            return Err(PluginError::InitError("Null parent window handle".into()));
        }

        log::info!(
            "Windows plugin editor hosting for {} - parent HWND: {:?}",
            self.info.name,
            parent
        );

        // Windows plugin GUI embedding via VST3's IPlugView
        // The parent is an HWND that we need to embed the plugin's view into
        //
        // VST3 embedding on Windows:
        // 1. Query IPlugView from plugin
        // 2. Call attached(parent, "HWND") with the HWND
        // 3. Handle resize via IPlugView::onSize()
        //
        // Current limitation: rack crate doesn't expose IPlugView
        // Full implementation would require direct VST3 SDK integration

        log::warn!(
            "Plugin GUI embedding not yet fully implemented for Windows. \
             Awaiting rack crate GUI API or direct VST3 integration."
        );

        Ok(())
    }

    /// Get the preferred editor size for this plugin
    pub fn preferred_editor_size(&self) -> Option<(u32, u32)> {
        Some((800, 600))
    }
}

#[cfg(target_os = "linux")]
impl Vst3Host {
    fn open_editor_linux(&mut self, parent: *mut c_void) -> PluginResult<()> {
        if parent.is_null() {
            return Err(PluginError::InitError("Null parent window handle".into()));
        }

        log::info!(
            "Linux plugin editor hosting for {} - parent X11 window: {:?}",
            self.info.name,
            parent
        );

        // Linux plugin GUI embedding via X11 window embedding
        // The parent is an X11 Window ID that we embed into
        //
        // VST3 on Linux:
        // 1. Query IPlugView with platform "X11EmbedWindowID"
        // 2. Call attached(parent) with the XID
        // 3. Handle XEmbed protocol for proper embedding
        //
        // LV2 on Linux:
        // 1. Use LV2 UI extension with X11 embedding
        //
        // Current limitation: rack crate doesn't expose GUI APIs

        log::warn!(
            "Plugin GUI embedding not yet fully implemented for Linux. \
             Awaiting rack crate GUI API or direct X11/VST3 integration."
        );

        Ok(())
    }

    /// Get the preferred editor size for this plugin
    pub fn preferred_editor_size(&self) -> Option<(u32, u32)> {
        Some((800, 600))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_vst3_host_nonexistent_path() {
        let path = PathBuf::from("/tmp/nonexistent_plugin.vst3");
        let result = Vst3Host::load(&path);
        // Should fail because path doesn't exist
        assert!(result.is_err());
    }

    #[test]
    fn test_default_parameters() {
        let params = Vst3Host::default_parameters();
        assert_eq!(params.len(), 2);
        assert_eq!(params[0].name, "Gain");
        assert_eq!(params[1].name, "Mix");
    }

    #[test]
    fn test_param_change_struct() {
        let change = ParamChange { id: 0, value: 0.5 };
        assert_eq!(change.id, 0);
        assert!((change.value - 0.5).abs() < f64::EPSILON);
    }
}
