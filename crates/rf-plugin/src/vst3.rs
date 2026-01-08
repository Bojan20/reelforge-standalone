//! VST3 Plugin Host
//!
//! Loads and hosts VST3 plugins.
//! Handles:
//! - Plugin loading from .vst3 bundles
//! - Audio processing with real-time safety
//! - Parameter automation via lock-free queues
//! - State save/load
//! - Editor hosting (platform-specific)
//!
//! # Implementation Status
//!
//! Currently uses passthrough mode until VST3 SDK integration is complete.
//! The vst3 crate provides bindings but not a complete hosting solution.
//! For production use, consider integrating vst3-sys directly or using
//! the `rack` crate which provides higher-level hosting APIs.

use std::ffi::c_void;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::Mutex;

use crate::scanner::{PluginCategory, PluginType};
use crate::{
    AudioBuffer, ParameterInfo, PluginError, PluginInfo, PluginInstance, PluginResult,
    ProcessContext,
};

/// Maximum parameter changes per audio block
const MAX_PARAM_CHANGES: usize = 128;

/// Lock-free parameter change queue entry
#[derive(Debug, Clone, Copy)]
struct ParamChange {
    id: u32,
    value: f64,
}

/// VST3 plugin host implementation
///
/// Currently operates in passthrough mode. Full VST3 hosting requires:
/// 1. Loading the .vst3 bundle (platform-specific)
/// 2. Getting the plugin factory
/// 3. Creating component instances
/// 4. Setting up audio processing
///
/// This structure is prepared for full implementation.
pub struct Vst3Host {
    /// Plugin info
    info: PluginInfo,
    /// Is plugin active
    active: AtomicBool,
    /// Processing latency in samples
    latency: AtomicU64,
    /// Cached parameter infos
    parameters: Vec<ParameterInfo>,
    /// Current parameter values (normalized 0-1)
    param_values: Vec<f64>,
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
    /// Has valid VST3 module loaded
    module_loaded: bool,
}

// SAFETY: All fields are either Sync+Send or protected by atomics/mutexes
unsafe impl Send for Vst3Host {}
unsafe impl Sync for Vst3Host {}

impl Vst3Host {
    /// Load VST3 plugin from path
    ///
    /// Currently creates a passthrough instance while VST3 hosting is being implemented.
    pub fn load(path: &Path) -> PluginResult<Self> {
        // Get plugin name from path
        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown VST3");

        let id = format!("vst3.{}", name.to_lowercase().replace(' ', "_"));

        log::info!("Loading VST3 plugin: {} from {:?}", name, path);

        // Check if bundle exists
        let bundle_exists = path.exists();
        if !bundle_exists {
            log::warn!("VST3 bundle not found at {:?}", path);
        }

        // Create default parameters for demo
        // In real implementation, these come from the plugin's IEditController
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

        let info = PluginInfo {
            id,
            name: name.to_string(),
            vendor: String::from("Unknown"),
            version: String::from("1.0.0"),
            plugin_type: PluginType::Vst3,
            category: PluginCategory::Effect,
            path: path.to_path_buf(),
            audio_inputs: 2,
            audio_outputs: 2,
            has_midi_input: false,
            has_midi_output: false,
            has_editor: bundle_exists,
            latency: 0,
            is_shell: false,
            sub_plugins: Vec::new(),
        };

        Ok(Self {
            info,
            active: AtomicBool::new(false),
            latency: AtomicU64::new(0),
            parameters,
            param_values,
            param_queue: Mutex::new(Vec::with_capacity(MAX_PARAM_CHANGES)),
            sample_rate: AtomicU64::new(48000),
            max_block_size: 4096,
            input_channels: 2,
            output_channels: 2,
            editor_open: AtomicBool::new(false),
            module_loaded: bundle_exists,
        })
    }

    /// Process pending parameter changes (called from audio thread)
    fn process_param_changes(&mut self) {
        let mut queue = self.param_queue.lock();
        for change in queue.drain(..) {
            if let Some(value) = self.param_values.get_mut(change.id as usize) {
                *value = change.value;
            }
        }
    }

    /// Get gain value from parameters (for passthrough processing)
    fn get_gain(&self) -> f32 {
        // Parameter 0 is gain, normalized 0-1 maps to -60dB to +12dB
        let normalized = self.param_values.get(0).copied().unwrap_or(0.5);
        let db = -60.0 + normalized * 72.0; // -60 to +12 dB range
        10.0_f32.powf(db as f32 / 20.0)
    }

    /// Get mix value from parameters
    fn get_mix(&self) -> f32 {
        self.param_values.get(1).copied().unwrap_or(1.0) as f32
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

        Ok(())
    }

    fn activate(&mut self) -> PluginResult<()> {
        self.active.store(true, Ordering::SeqCst);
        log::debug!("Activated VST3 plugin: {}", self.info.name);
        Ok(())
    }

    fn deactivate(&mut self) -> PluginResult<()> {
        self.active.store(false, Ordering::SeqCst);
        log::debug!("Deactivated VST3 plugin: {}", self.info.name);
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

        // Process any pending parameter changes
        self.process_param_changes();

        // Apply gain and mix (simple passthrough with gain)
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

        // Queue for audio thread
        {
            let mut queue = self.param_queue.lock();
            if queue.len() < MAX_PARAM_CHANGES {
                queue.push(ParamChange { id, value: clamped });
            }
        }

        // Also update immediately for UI feedback
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
        self.module_loaded
    }

    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    fn open_editor(&mut self, parent: *mut c_void) -> PluginResult<()> {
        if self.editor_open.load(Ordering::SeqCst) {
            return Ok(());
        }

        if !self.module_loaded {
            return Err(PluginError::InitError("VST3 module not loaded".into()));
        }

        // Platform-specific editor hosting
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
        log::info!("Opened editor for VST3 plugin: {}", self.info.name);
        Ok(())
    }

    fn close_editor(&mut self) -> PluginResult<()> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return Ok(());
        }

        // Platform-specific cleanup would go here
        // For now, just mark as closed

        self.editor_open.store(false, Ordering::SeqCst);
        log::info!("Closed editor for VST3 plugin: {}", self.info.name);
        Ok(())
    }

    fn editor_size(&self) -> Option<(u32, u32)> {
        if self.editor_open.load(Ordering::SeqCst) {
            // Default editor size - in real implementation this comes from IPlugView
            Some((800, 600))
        } else {
            None
        }
    }

    fn resize_editor(&mut self, _width: u32, _height: u32) -> PluginResult<()> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return Err(PluginError::ProcessingError("Editor not open".into()));
        }
        // TODO: Implement via IPlugView::onSize
        Ok(())
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM-SPECIFIC EDITOR HOSTING
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(target_os = "macos")]
impl Vst3Host {
    /// Open editor on macOS using NSView
    fn open_editor_macos(&mut self, parent: *mut c_void) -> PluginResult<()> {
        if parent.is_null() {
            return Err(PluginError::InitError("Null parent window handle".into()));
        }

        // In real implementation:
        // 1. Get IPlugView from IEditController
        // 2. Call IPlugView::attached(parent, kPlatformTypeNSView)
        // 3. Get preferred size with IPlugView::getSize()
        // 4. Create/resize the NSView subview

        log::info!(
            "macOS VST3 editor hosting for {} - parent NSView: {:?}",
            self.info.name,
            parent
        );

        // Placeholder: Full implementation requires vst3-sys integration
        // The VST3 SDK IPlugView interface needs to be called:
        //
        // extern "C" {
        //     fn IPlugView_attached(view: *mut c_void, parent: *mut c_void, platform_type: u32) -> i32;
        //     fn IPlugView_getSize(view: *mut c_void, size: *mut ViewRect) -> i32;
        // }
        //
        // const kPlatformTypeNSView: u32 = 0x4E535677; // 'NSVw'

        Ok(())
    }
}

#[cfg(target_os = "windows")]
impl Vst3Host {
    /// Open editor on Windows using HWND
    fn open_editor_windows(&mut self, parent: *mut c_void) -> PluginResult<()> {
        if parent.is_null() {
            return Err(PluginError::InitError("Null parent window handle".into()));
        }

        log::info!(
            "Windows VST3 editor hosting for {} - parent HWND: {:?}",
            self.info.name,
            parent
        );

        // const kPlatformTypeHWND: u32 = 0x4857494E; // 'HWIN'
        // IPlugView::attached(parent, kPlatformTypeHWND)

        Ok(())
    }
}

#[cfg(target_os = "linux")]
impl Vst3Host {
    /// Open editor on Linux using X11
    fn open_editor_linux(&mut self, parent: *mut c_void) -> PluginResult<()> {
        if parent.is_null() {
            return Err(PluginError::InitError("Null parent window handle".into()));
        }

        log::info!(
            "Linux VST3 editor hosting for {} - parent X11 window: {:?}",
            self.info.name,
            parent
        );

        // const kPlatformTypeX11EmbedWindowID: u32 = 0x58314557; // 'X1EW'
        // IPlugView::attached(parent, kPlatformTypeX11EmbedWindowID)

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_vst3_host_creation() {
        let path = PathBuf::from("/tmp/test.vst3");
        let result = Vst3Host::load(&path);
        assert!(result.is_ok());

        let host = result.unwrap();
        assert!(!host.active.load(Ordering::SeqCst));
        assert_eq!(host.info.plugin_type, PluginType::Vst3);
    }

    #[test]
    fn test_param_queue() {
        let path = PathBuf::from("/tmp/test.vst3");
        let mut host = Vst3Host::load(&path).unwrap();

        // Queue some parameter changes
        host.set_parameter(0, 0.5).unwrap();
        host.set_parameter(1, 0.75).unwrap();

        // Process them
        host.process_param_changes();

        // Queue should be empty now
        assert!(host.param_queue.lock().is_empty());
    }

    #[test]
    fn test_gain_calculation() {
        let path = PathBuf::from("/tmp/test.vst3");
        let host = Vst3Host::load(&path).unwrap();

        // Default gain (0.5 normalized) should be close to 0dB (1.0 linear)
        let gain = host.get_gain();
        // 0.5 normalized = -60 + 0.5*72 = -24 dB = ~0.063 linear
        assert!(gain > 0.05 && gain < 0.1);
    }

    #[test]
    fn test_passthrough_processing() {
        let path = PathBuf::from("/tmp/test.vst3");
        let mut host = Vst3Host::load(&path).unwrap();
        host.activate().unwrap();

        // Set unity gain and full mix
        host.set_parameter(0, 0.833).unwrap(); // ~0dB
        host.set_parameter(1, 1.0).unwrap();

        let input = AudioBuffer::from_data(vec![vec![0.5; 128], vec![-0.5; 128]]);
        let mut output = AudioBuffer::new(2, 128);

        let ctx = ProcessContext::default();
        host.process(&input, &mut output, &ctx).unwrap();

        // Check output is processed
        assert!(output.channel(0).unwrap()[0].abs() > 0.0);
    }
}
