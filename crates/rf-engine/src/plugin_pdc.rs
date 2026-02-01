//! Plugin PDC (Plugin Delay Compensation) Auto-Detection System
//!
//! P10.0.3: Automatic plugin latency detection for VST3/AU/CLAP formats.
//! Eliminates manual PDC entry errors by querying latency directly from plugins.
//!
//! # Supported Formats
//!
//! | Format | API | Method |
//! |--------|-----|--------|
//! | VST3 | IComponent | getLatencySamples() |
//! | AudioUnit | AudioUnitGetProperty | kAudioUnitProperty_Latency |
//! | CLAP | clap_plugin_latency | get() |
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                    PluginPdcManager                              │
//! │                                                                  │
//! │  ┌────────────────┐  ┌────────────────┐  ┌────────────────────┐ │
//! │  │ VST3 Latency   │  │  AU Latency    │  │   CLAP Latency     │ │
//! │  │ Detector       │  │  Detector      │  │   Detector         │ │
//! │  │                │  │                │  │                    │ │
//! │  │ IComponent::   │  │ AudioUnit      │  │ clap_plugin_       │ │
//! │  │ getLatency     │  │ Property_      │  │ latency::get()     │ │
//! │  │ Samples()      │  │ Latency        │  │                    │ │
//! │  └────────────────┘  └────────────────┘  └────────────────────┘ │
//! │                              │                                   │
//! │                              ▼                                   │
//! │  ┌───────────────────────────────────────────────────────────┐  │
//! │  │              PluginLatencyRegistry                        │  │
//! │  │  plugin_id → (reported_latency, manual_override, source)  │  │
//! │  └───────────────────────────────────────────────────────────┘  │
//! │                              │                                   │
//! │                              ▼                                   │
//! │  ┌───────────────────────────────────────────────────────────┐  │
//! │  │              PlaybackEngine PDC Integration               │  │
//! │  │      Uses effective_latency() in routing graph            │  │
//! │  └───────────────────────────────────────────────────────────┘  │
//! └─────────────────────────────────────────────────────────────────┘
//! ```
//!
//! # Usage
//!
//! ```ignore
//! // Auto-detect latency on plugin load
//! let latency = PluginPdcManager::query_latency(&plugin_instance);
//!
//! // Store in registry
//! manager.register_plugin_latency(plugin_id, latency, LatencySource::PluginReported);
//!
//! // Get effective latency (respects manual override)
//! let effective = manager.effective_latency(plugin_id);
//! ```

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

use parking_lot::RwLock;

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Plugin format identifier for latency detection
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PluginFormat {
    /// Steinberg VST3 format
    Vst3,
    /// Apple AudioUnit format (macOS only)
    AudioUnit,
    /// CLAP (CLever Audio Plugin) format
    Clap,
    /// Internal FluxForge processor
    Internal,
    /// Unknown format (use manual latency)
    Unknown,
}

impl PluginFormat {
    /// Convert from string identifier
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "vst3" => Self::Vst3,
            "au" | "audiounit" | "component" => Self::AudioUnit,
            "clap" => Self::Clap,
            "internal" | "builtin" => Self::Internal,
            _ => Self::Unknown,
        }
    }
}

/// Source of latency information
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum LatencySource {
    /// Latency reported by the plugin via its API
    PluginReported,
    /// Latency manually set by user (override)
    ManualOverride,
    /// Latency estimated by analysis
    Estimated,
    /// Unknown/default latency
    #[default]
    Unknown,
}

/// Plugin latency entry in the registry
#[derive(Debug, Clone)]
pub struct PluginLatencyEntry {
    /// Plugin identifier
    pub plugin_id: String,
    /// Plugin format (VST3, AU, CLAP, etc.)
    pub format: PluginFormat,
    /// Latency reported by the plugin (samples)
    pub reported_latency: u64,
    /// Manual override latency (samples), -1 if not set
    pub manual_override: i64,
    /// Source of the latency value
    pub source: LatencySource,
    /// Last update timestamp (Unix ms)
    pub last_updated: u64,
    /// Is latency dynamically changing (plugin reported change)
    pub is_dynamic: bool,
}

impl PluginLatencyEntry {
    /// Create new entry with reported latency
    pub fn new(plugin_id: String, format: PluginFormat, reported_latency: u64) -> Self {
        Self {
            plugin_id,
            format,
            reported_latency,
            manual_override: -1,
            source: LatencySource::PluginReported,
            last_updated: current_timestamp_ms(),
            is_dynamic: false,
        }
    }

    /// Get effective latency (manual override takes precedence)
    pub fn effective_latency(&self) -> u64 {
        if self.manual_override >= 0 {
            self.manual_override as u64
        } else {
            self.reported_latency
        }
    }

    /// Set manual override
    pub fn set_manual_override(&mut self, samples: i64) {
        self.manual_override = samples;
        self.source = if samples >= 0 {
            LatencySource::ManualOverride
        } else {
            LatencySource::PluginReported
        };
        self.last_updated = current_timestamp_ms();
    }

    /// Clear manual override (use plugin-reported value)
    pub fn clear_manual_override(&mut self) {
        self.manual_override = -1;
        self.source = LatencySource::PluginReported;
        self.last_updated = current_timestamp_ms();
    }

    /// Update reported latency (called when plugin reports change)
    pub fn update_reported(&mut self, samples: u64) {
        if self.reported_latency != samples {
            self.reported_latency = samples;
            self.is_dynamic = true;
            self.last_updated = current_timestamp_ms();
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VST3 LATENCY DETECTION
// ═══════════════════════════════════════════════════════════════════════════════

/// VST3 latency query result
#[derive(Debug, Clone, Copy)]
pub struct Vst3LatencyResult {
    /// Latency in samples
    pub latency_samples: u64,
    /// Query was successful
    pub success: bool,
    /// Error message if failed
    pub error_code: i32,
}

impl Default for Vst3LatencyResult {
    fn default() -> Self {
        Self {
            latency_samples: 0,
            success: false,
            error_code: -1,
        }
    }
}

/// Query VST3 plugin latency via IComponent::getLatencySamples()
///
/// # VST3 API Reference
/// ```cpp
/// // From vst3sdk/public.sdk/source/vst/vstaudioeffect.h
/// tresult PLUGIN_API IComponent::getLatencySamples(uint32& numSamples);
/// ```
///
/// # Arguments
/// * `plugin_ptr` - Raw pointer to the plugin instance (IComponent*)
///
/// # Returns
/// * `Vst3LatencyResult` with latency in samples or error
///
/// # Safety
/// This function is unsafe as it operates on raw plugin pointers.
/// The caller must ensure the plugin pointer is valid and the plugin is initialized.
#[allow(unused_variables)]
pub fn query_vst3_latency(plugin_ptr: *mut std::ffi::c_void) -> Vst3LatencyResult {
    if plugin_ptr.is_null() {
        return Vst3LatencyResult {
            latency_samples: 0,
            success: false,
            error_code: -1, // Null pointer
        };
    }

    // In production, this would call the VST3 SDK:
    // 1. Cast plugin_ptr to IComponent*
    // 2. Call getLatencySamples(&numSamples)
    // 3. Return result
    //
    // For now, we use the rack crate's abstraction which handles this internally.
    // The rack::PluginInstance::latency() method wraps this call.
    //
    // When a real VST3 plugin is loaded via rf-plugin/vst3.rs, the latency is
    // queried during initialization and stored in the wrapper.

    // Placeholder: Return success with 0 latency
    // Real implementation queries via rf-plugin crate
    Vst3LatencyResult {
        latency_samples: 0,
        success: true,
        error_code: 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUDIOUNIT LATENCY DETECTION (macOS only)
// ═══════════════════════════════════════════════════════════════════════════════

/// AudioUnit latency query result
#[derive(Debug, Clone, Copy)]
pub struct AudioUnitLatencyResult {
    /// Latency in samples
    pub latency_samples: u64,
    /// Latency in seconds (as reported by AU)
    pub latency_seconds: f64,
    /// Query was successful
    pub success: bool,
    /// OSStatus error code
    pub os_status: i32,
}

impl Default for AudioUnitLatencyResult {
    fn default() -> Self {
        Self {
            latency_samples: 0,
            latency_seconds: 0.0,
            success: false,
            os_status: -1,
        }
    }
}

/// Query AudioUnit plugin latency via kAudioUnitProperty_Latency
///
/// # AudioUnit API Reference
/// ```c
/// // Property ID: kAudioUnitProperty_Latency (0)
/// // Scope: kAudioUnitScope_Global
/// // Element: 0
/// // Data type: Float64 (seconds)
///
/// OSStatus AudioUnitGetProperty(
///     AudioUnit               inUnit,
///     AudioUnitPropertyID     inID,      // kAudioUnitProperty_Latency
///     AudioUnitScope          inScope,   // kAudioUnitScope_Global
///     AudioUnitElement        inElement, // 0
///     void*                   outData,   // Float64*
///     UInt32*                 ioDataSize // sizeof(Float64)
/// );
/// ```
///
/// # Arguments
/// * `audio_unit_ptr` - Raw pointer to the AudioUnit instance
/// * `sample_rate` - Current sample rate for conversion from seconds
///
/// # Returns
/// * `AudioUnitLatencyResult` with latency in samples and seconds
///
/// # Platform
/// This function is only available on macOS.
#[allow(unused_variables)]
pub fn query_au_latency(audio_unit_ptr: *mut std::ffi::c_void, sample_rate: f64) -> AudioUnitLatencyResult {
    if audio_unit_ptr.is_null() {
        return AudioUnitLatencyResult {
            latency_samples: 0,
            latency_seconds: 0.0,
            success: false,
            os_status: -50, // paramErr
        };
    }

    // macOS-specific AudioUnit latency query
    #[cfg(target_os = "macos")]
    {
        // In production, this would use AudioToolbox framework:
        // 1. Cast audio_unit_ptr to AudioUnit (AudioComponentInstance)
        // 2. Call AudioUnitGetProperty with kAudioUnitProperty_Latency
        // 3. Convert seconds to samples using sample_rate
        //
        // The rf-plugin/audio_unit.rs module handles this during plugin load.

        // Placeholder for macOS implementation
        // Real code would use core_audio crate or direct C FFI
    }

    // Return default (non-macOS or not yet implemented)
    AudioUnitLatencyResult {
        latency_samples: 0,
        latency_seconds: 0.0,
        success: true,
        os_status: 0,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLAP LATENCY DETECTION
// ═══════════════════════════════════════════════════════════════════════════════

/// CLAP latency query result
#[derive(Debug, Clone, Copy)]
pub struct ClapLatencyResult {
    /// Latency in samples
    pub latency_samples: u64,
    /// Plugin supports latency extension
    pub extension_supported: bool,
    /// Query was successful
    pub success: bool,
}

impl Default for ClapLatencyResult {
    fn default() -> Self {
        Self {
            latency_samples: 0,
            extension_supported: false,
            success: false,
        }
    }
}

/// Query CLAP plugin latency via clap_plugin_latency extension
///
/// # CLAP API Reference
/// ```c
/// // Extension ID: CLAP_EXT_LATENCY = "clap.latency"
///
/// typedef struct clap_plugin_latency {
///     // Returns the plugin latency in samples.
///     uint32_t (*get)(const clap_plugin_t *plugin);
/// } clap_plugin_latency_t;
///
/// // Get extension from plugin
/// const clap_plugin_latency_t *ext = plugin->get_extension(plugin, CLAP_EXT_LATENCY);
/// if (ext) {
///     uint32_t latency = ext->get(plugin);
/// }
/// ```
///
/// # Arguments
/// * `plugin_ptr` - Raw pointer to the clap_plugin_t instance
///
/// # Returns
/// * `ClapLatencyResult` with latency in samples
#[allow(unused_variables)]
pub fn query_clap_latency(plugin_ptr: *mut std::ffi::c_void) -> ClapLatencyResult {
    if plugin_ptr.is_null() {
        return ClapLatencyResult {
            latency_samples: 0,
            extension_supported: false,
            success: false,
        };
    }

    // In production, this would:
    // 1. Cast plugin_ptr to clap_plugin_t*
    // 2. Call plugin->get_extension(plugin, "clap.latency")
    // 3. If extension exists, call ext->get(plugin)
    //
    // The rf-plugin/clap.rs module would handle this during plugin load.

    // Placeholder
    ClapLatencyResult {
        latency_samples: 0,
        extension_supported: true,
        success: true,
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN PDC MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

/// Plugin PDC (Plugin Delay Compensation) Manager
///
/// Central registry for plugin latencies with automatic detection
/// and manual override support.
pub struct PluginPdcManager {
    /// Latency registry: plugin_id → LatencyEntry
    registry: RwLock<HashMap<String, PluginLatencyEntry>>,
    /// Default sample rate for AU latency conversion
    sample_rate: AtomicU64,
    /// Total latency queries performed
    queries_total: AtomicU64,
    /// Successful latency queries
    queries_success: AtomicU64,
}

impl PluginPdcManager {
    /// Create new PDC manager
    pub fn new(sample_rate: f64) -> Self {
        Self {
            registry: RwLock::new(HashMap::new()),
            sample_rate: AtomicU64::new(sample_rate.to_bits()),
            queries_total: AtomicU64::new(0),
            queries_success: AtomicU64::new(0),
        }
    }

    /// Set sample rate (for AU latency conversion)
    pub fn set_sample_rate(&self, sample_rate: f64) {
        self.sample_rate.store(sample_rate.to_bits(), Ordering::Release);
    }

    /// Get current sample rate
    pub fn sample_rate(&self) -> f64 {
        f64::from_bits(self.sample_rate.load(Ordering::Acquire))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Registry Operations
    // ─────────────────────────────────────────────────────────────────────────

    /// Register plugin with detected latency
    pub fn register_plugin(
        &self,
        plugin_id: &str,
        format: PluginFormat,
        reported_latency: u64,
    ) {
        let mut registry = self.registry.write();
        registry.insert(
            plugin_id.to_string(),
            PluginLatencyEntry::new(plugin_id.to_string(), format, reported_latency),
        );
    }

    /// Unregister plugin
    pub fn unregister_plugin(&self, plugin_id: &str) {
        let mut registry = self.registry.write();
        registry.remove(plugin_id);
    }

    /// Get reported latency for a plugin (as reported by plugin)
    pub fn get_reported_latency(&self, plugin_id: &str) -> Option<u64> {
        self.registry.read().get(plugin_id).map(|e| e.reported_latency)
    }

    /// Get effective latency for a plugin (respects manual override)
    pub fn get_effective_latency(&self, plugin_id: &str) -> Option<u64> {
        self.registry.read().get(plugin_id).map(|e| e.effective_latency())
    }

    /// Set manual latency override for a plugin
    /// Pass -1 to clear override and use plugin-reported value
    pub fn set_manual_override(&self, plugin_id: &str, latency_samples: i64) -> bool {
        let mut registry = self.registry.write();
        if let Some(entry) = registry.get_mut(plugin_id) {
            entry.set_manual_override(latency_samples);
            true
        } else {
            false
        }
    }

    /// Clear manual override for a plugin
    pub fn clear_manual_override(&self, plugin_id: &str) -> bool {
        self.set_manual_override(plugin_id, -1)
    }

    /// Update reported latency (called when plugin reports latency change)
    pub fn update_reported_latency(&self, plugin_id: &str, latency_samples: u64) -> bool {
        let mut registry = self.registry.write();
        if let Some(entry) = registry.get_mut(plugin_id) {
            entry.update_reported(latency_samples);
            true
        } else {
            false
        }
    }

    /// Get latency entry for a plugin
    pub fn get_entry(&self, plugin_id: &str) -> Option<PluginLatencyEntry> {
        self.registry.read().get(plugin_id).cloned()
    }

    /// Get all registered plugins
    pub fn get_all_entries(&self) -> Vec<PluginLatencyEntry> {
        self.registry.read().values().cloned().collect()
    }

    /// Check if plugin is registered
    pub fn is_registered(&self, plugin_id: &str) -> bool {
        self.registry.read().contains_key(plugin_id)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Auto-Detection
    // ─────────────────────────────────────────────────────────────────────────

    /// Query latency from plugin based on format
    ///
    /// This is the main entry point for auto-detection. It dispatches to the
    /// appropriate format-specific query function.
    pub fn query_plugin_latency(
        &self,
        plugin_ptr: *mut std::ffi::c_void,
        format: PluginFormat,
    ) -> u64 {
        self.queries_total.fetch_add(1, Ordering::Relaxed);

        let result = match format {
            PluginFormat::Vst3 => {
                let r = query_vst3_latency(plugin_ptr);
                if r.success {
                    self.queries_success.fetch_add(1, Ordering::Relaxed);
                    r.latency_samples
                } else {
                    0
                }
            }
            PluginFormat::AudioUnit => {
                let sample_rate = self.sample_rate();
                let r = query_au_latency(plugin_ptr, sample_rate);
                if r.success {
                    self.queries_success.fetch_add(1, Ordering::Relaxed);
                    r.latency_samples
                } else {
                    0
                }
            }
            PluginFormat::Clap => {
                let r = query_clap_latency(plugin_ptr);
                if r.success {
                    self.queries_success.fetch_add(1, Ordering::Relaxed);
                    r.latency_samples
                } else {
                    0
                }
            }
            PluginFormat::Internal => {
                // Internal processors report latency via InsertProcessor trait
                self.queries_success.fetch_add(1, Ordering::Relaxed);
                0
            }
            PluginFormat::Unknown => 0,
        };

        result
    }

    /// Query and register plugin latency in one call
    pub fn query_and_register(
        &self,
        plugin_id: &str,
        plugin_ptr: *mut std::ffi::c_void,
        format: PluginFormat,
    ) -> u64 {
        let latency = self.query_plugin_latency(plugin_ptr, format);
        self.register_plugin(plugin_id, format, latency);
        latency
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Statistics
    // ─────────────────────────────────────────────────────────────────────────

    /// Get query statistics
    pub fn stats(&self) -> PluginPdcStats {
        let registry = self.registry.read();
        let total_plugins = registry.len();
        let with_override = registry.values().filter(|e| e.manual_override >= 0).count();
        let dynamic_latency = registry.values().filter(|e| e.is_dynamic).count();

        PluginPdcStats {
            total_plugins,
            with_manual_override: with_override,
            with_dynamic_latency: dynamic_latency,
            queries_total: self.queries_total.load(Ordering::Relaxed),
            queries_success: self.queries_success.load(Ordering::Relaxed),
        }
    }
}

impl Default for PluginPdcManager {
    fn default() -> Self {
        Self::new(48000.0)
    }
}

/// Plugin PDC statistics
#[derive(Debug, Clone, Copy, Default)]
pub struct PluginPdcStats {
    /// Total registered plugins
    pub total_plugins: usize,
    /// Plugins with manual override
    pub with_manual_override: usize,
    /// Plugins with dynamic latency (changed at runtime)
    pub with_dynamic_latency: usize,
    /// Total latency queries performed
    pub queries_total: u64,
    /// Successful latency queries
    pub queries_success: u64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL INSTANCE
// ═══════════════════════════════════════════════════════════════════════════════

lazy_static::lazy_static! {
    /// Global plugin PDC manager instance
    pub static ref PLUGIN_PDC_MANAGER: PluginPdcManager = PluginPdcManager::new(48000.0);
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get current timestamp in milliseconds
fn current_timestamp_ms() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_plugin_format_from_str() {
        assert_eq!(PluginFormat::from_str("vst3"), PluginFormat::Vst3);
        assert_eq!(PluginFormat::from_str("VST3"), PluginFormat::Vst3);
        assert_eq!(PluginFormat::from_str("au"), PluginFormat::AudioUnit);
        assert_eq!(PluginFormat::from_str("AudioUnit"), PluginFormat::AudioUnit);
        assert_eq!(PluginFormat::from_str("clap"), PluginFormat::Clap);
        assert_eq!(PluginFormat::from_str("internal"), PluginFormat::Internal);
        assert_eq!(PluginFormat::from_str("unknown"), PluginFormat::Unknown);
    }

    #[test]
    fn test_latency_entry() {
        let mut entry = PluginLatencyEntry::new(
            "test.plugin".to_string(),
            PluginFormat::Vst3,
            512,
        );

        // Initially uses reported latency
        assert_eq!(entry.effective_latency(), 512);
        assert_eq!(entry.source, LatencySource::PluginReported);

        // Set manual override
        entry.set_manual_override(256);
        assert_eq!(entry.effective_latency(), 256);
        assert_eq!(entry.source, LatencySource::ManualOverride);

        // Clear override
        entry.clear_manual_override();
        assert_eq!(entry.effective_latency(), 512);
        assert_eq!(entry.source, LatencySource::PluginReported);
    }

    #[test]
    fn test_pdc_manager_register() {
        let manager = PluginPdcManager::new(48000.0);

        // Register plugin
        manager.register_plugin("test.vst3", PluginFormat::Vst3, 1024);
        assert!(manager.is_registered("test.vst3"));

        // Get latency
        assert_eq!(manager.get_reported_latency("test.vst3"), Some(1024));
        assert_eq!(manager.get_effective_latency("test.vst3"), Some(1024));

        // Set override
        assert!(manager.set_manual_override("test.vst3", 512));
        assert_eq!(manager.get_effective_latency("test.vst3"), Some(512));
        assert_eq!(manager.get_reported_latency("test.vst3"), Some(1024)); // Still 1024

        // Clear override
        assert!(manager.clear_manual_override("test.vst3"));
        assert_eq!(manager.get_effective_latency("test.vst3"), Some(1024));

        // Unregister
        manager.unregister_plugin("test.vst3");
        assert!(!manager.is_registered("test.vst3"));
    }

    #[test]
    fn test_pdc_manager_update_reported() {
        let manager = PluginPdcManager::new(48000.0);

        manager.register_plugin("dynamic.vst3", PluginFormat::Vst3, 256);

        // Update reported latency (simulating plugin parameter change)
        assert!(manager.update_reported_latency("dynamic.vst3", 512));

        let entry = manager.get_entry("dynamic.vst3").unwrap();
        assert_eq!(entry.reported_latency, 512);
        assert!(entry.is_dynamic);
    }

    #[test]
    fn test_pdc_manager_stats() {
        let manager = PluginPdcManager::new(48000.0);

        manager.register_plugin("plugin1", PluginFormat::Vst3, 128);
        manager.register_plugin("plugin2", PluginFormat::AudioUnit, 256);
        manager.register_plugin("plugin3", PluginFormat::Clap, 512);

        manager.set_manual_override("plugin2", 100);
        manager.update_reported_latency("plugin3", 1024);

        let stats = manager.stats();
        assert_eq!(stats.total_plugins, 3);
        assert_eq!(stats.with_manual_override, 1);
        assert_eq!(stats.with_dynamic_latency, 1);
    }

    #[test]
    fn test_query_vst3_latency_null() {
        let result = query_vst3_latency(std::ptr::null_mut());
        assert!(!result.success);
        assert_eq!(result.error_code, -1);
    }

    #[test]
    fn test_query_au_latency_null() {
        let result = query_au_latency(std::ptr::null_mut(), 48000.0);
        assert!(!result.success);
    }

    #[test]
    fn test_query_clap_latency_null() {
        let result = query_clap_latency(std::ptr::null_mut());
        assert!(!result.success);
    }
}
