//! Plugin Scanner
//!
//! Scans filesystem for available plugins in standard locations:
//! - VST3: /Library/Audio/Plug-Ins/VST3 (macOS)
//! - CLAP: /Library/Audio/Plug-Ins/CLAP (macOS)
//! - AU: /Library/Audio/Plug-Ins/Components (macOS)
//!
//! Caches plugin metadata for fast startup.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

use crate::PluginResult;

/// Plugin format type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PluginType {
    /// VST3 plugin
    Vst3,
    /// CLAP plugin
    Clap,
    /// Audio Unit (macOS only)
    AudioUnit,
    /// Internal rf-dsp processor
    Internal,
}

/// Plugin category
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PluginCategory {
    /// Effect processor (EQ, compressor, reverb, etc.)
    Effect,
    /// Virtual instrument / synth
    Instrument,
    /// Analyzer (spectrum, meter, etc.)
    Analyzer,
    /// Utility (gain, routing, etc.)
    Utility,
    /// Unknown category
    Unknown,
}

/// Plugin information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginInfo {
    /// Unique plugin ID
    pub id: String,
    /// Display name
    pub name: String,
    /// Vendor name
    pub vendor: String,
    /// Version string
    pub version: String,
    /// Plugin type
    pub plugin_type: PluginType,
    /// Category
    pub category: PluginCategory,
    /// File path
    pub path: PathBuf,
    /// Number of audio inputs
    pub audio_inputs: u32,
    /// Number of audio outputs
    pub audio_outputs: u32,
    /// Supports MIDI input
    pub has_midi_input: bool,
    /// Supports MIDI output
    pub has_midi_output: bool,
    /// Has editor GUI
    pub has_editor: bool,
    /// Processing latency in samples
    pub latency: u32,
    /// Is this a shell plugin
    pub is_shell: bool,
    /// Sub-plugins (for shell plugins)
    pub sub_plugins: Vec<String>,
}

impl PluginInfo {
    /// Create new plugin info
    pub fn new(id: &str, name: &str, plugin_type: PluginType, path: PathBuf) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            vendor: String::new(),
            version: String::from("1.0.0"),
            plugin_type,
            category: PluginCategory::Unknown,
            path,
            audio_inputs: 2,
            audio_outputs: 2,
            has_midi_input: false,
            has_midi_output: false,
            has_editor: false,
            latency: 0,
            is_shell: false,
            sub_plugins: Vec::new(),
        }
    }

    /// Create internal plugin info
    pub fn internal(id: &str, name: &str, category: PluginCategory) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            vendor: String::from("ReelForge"),
            version: String::from("1.0.0"),
            plugin_type: PluginType::Internal,
            category,
            path: PathBuf::new(),
            audio_inputs: 2,
            audio_outputs: 2,
            has_midi_input: false,
            has_midi_output: false,
            has_editor: true,
            latency: 0,
            is_shell: false,
            sub_plugins: Vec::new(),
        }
    }
}

/// Plugin scanner
pub struct PluginScanner {
    /// Discovered plugins
    plugins: Vec<PluginInfo>,
    /// Plugin lookup by ID
    plugin_map: HashMap<String, usize>,
    /// Scan locations
    scan_paths: Vec<(PluginType, PathBuf)>,
    /// Internal plugins
    internal_plugins: Vec<PluginInfo>,
}

impl PluginScanner {
    /// Create new scanner with default paths
    pub fn new() -> Self {
        let mut scanner = Self {
            plugins: Vec::new(),
            plugin_map: HashMap::new(),
            scan_paths: Vec::new(),
            internal_plugins: Self::register_internal_plugins(),
        };

        // Add default scan paths
        scanner.add_default_paths();

        scanner
    }

    /// Add default plugin paths for current platform
    fn add_default_paths(&mut self) {
        #[cfg(target_os = "macos")]
        {
            // System-wide
            self.scan_paths.push((
                PluginType::Vst3,
                PathBuf::from("/Library/Audio/Plug-Ins/VST3"),
            ));
            self.scan_paths.push((
                PluginType::Clap,
                PathBuf::from("/Library/Audio/Plug-Ins/CLAP"),
            ));
            self.scan_paths.push((
                PluginType::AudioUnit,
                PathBuf::from("/Library/Audio/Plug-Ins/Components"),
            ));

            // User-specific
            if let Some(home) = dirs_next::home_dir() {
                self.scan_paths
                    .push((PluginType::Vst3, home.join("Library/Audio/Plug-Ins/VST3")));
                self.scan_paths
                    .push((PluginType::Clap, home.join("Library/Audio/Plug-Ins/CLAP")));
                self.scan_paths.push((
                    PluginType::AudioUnit,
                    home.join("Library/Audio/Plug-Ins/Components"),
                ));
            }
        }

        #[cfg(target_os = "windows")]
        {
            // Common paths
            self.scan_paths.push((
                PluginType::Vst3,
                PathBuf::from("C:\\Program Files\\Common Files\\VST3"),
            ));
            self.scan_paths.push((
                PluginType::Clap,
                PathBuf::from("C:\\Program Files\\Common Files\\CLAP"),
            ));
        }

        #[cfg(target_os = "linux")]
        {
            // Standard Linux paths
            self.scan_paths
                .push((PluginType::Vst3, PathBuf::from("/usr/lib/vst3")));
            self.scan_paths
                .push((PluginType::Clap, PathBuf::from("/usr/lib/clap")));

            if let Some(home) = dirs_next::home_dir() {
                self.scan_paths.push((PluginType::Vst3, home.join(".vst3")));
                self.scan_paths.push((PluginType::Clap, home.join(".clap")));
            }
        }
    }

    /// Register internal rf-dsp plugins
    fn register_internal_plugins() -> Vec<PluginInfo> {
        vec![
            // EQ
            PluginInfo::internal("rf.eq.parametric", "Parametric EQ", PluginCategory::Effect),
            PluginInfo::internal("rf.eq.graphic", "Graphic EQ", PluginCategory::Effect),
            // Dynamics
            PluginInfo::internal(
                "rf.dynamics.compressor",
                "Compressor",
                PluginCategory::Effect,
            ),
            PluginInfo::internal("rf.dynamics.limiter", "Limiter", PluginCategory::Effect),
            PluginInfo::internal("rf.dynamics.gate", "Gate", PluginCategory::Effect),
            PluginInfo::internal("rf.dynamics.expander", "Expander", PluginCategory::Effect),
            PluginInfo::internal(
                "rf.dynamics.multiband",
                "Multiband Dynamics",
                PluginCategory::Effect,
            ),
            // Time-based
            PluginInfo::internal("rf.delay.stereo", "Stereo Delay", PluginCategory::Effect),
            PluginInfo::internal(
                "rf.reverb.algorithmic",
                "Algorithmic Reverb",
                PluginCategory::Effect,
            ),
            PluginInfo::internal(
                "rf.reverb.convolution",
                "Convolution Reverb",
                PluginCategory::Effect,
            ),
            // Spatial
            PluginInfo::internal("rf.spatial.panner", "Stereo Panner", PluginCategory::Effect),
            PluginInfo::internal("rf.spatial.width", "Stereo Width", PluginCategory::Effect),
            PluginInfo::internal("rf.spatial.ms", "M/S Processor", PluginCategory::Effect),
            // Analysis
            PluginInfo::internal(
                "rf.analysis.spectrum",
                "Spectrum Analyzer",
                PluginCategory::Analyzer,
            ),
            PluginInfo::internal(
                "rf.analysis.loudness",
                "Loudness Meter",
                PluginCategory::Analyzer,
            ),
            PluginInfo::internal(
                "rf.analysis.correlation",
                "Correlation Meter",
                PluginCategory::Analyzer,
            ),
            // Utility
            PluginInfo::internal("rf.utility.gain", "Gain", PluginCategory::Utility),
            PluginInfo::internal("rf.utility.phase", "Phase Invert", PluginCategory::Utility),
            PluginInfo::internal("rf.utility.trim", "Trim", PluginCategory::Utility),
        ]
    }

    /// Add custom scan path
    pub fn add_path(&mut self, plugin_type: PluginType, path: PathBuf) {
        self.scan_paths.push((plugin_type, path));
    }

    /// Scan all configured paths
    pub fn scan_all(&mut self) -> PluginResult<Vec<PluginInfo>> {
        self.plugins.clear();
        self.plugin_map.clear();

        // Add internal plugins first
        for plugin in &self.internal_plugins {
            let idx = self.plugins.len();
            self.plugin_map.insert(plugin.id.clone(), idx);
            self.plugins.push(plugin.clone());
        }

        // Scan external plugins
        for (plugin_type, path) in self.scan_paths.clone() {
            if path.exists() {
                self.scan_directory(&path, plugin_type)?;
            }
        }

        log::info!("Found {} plugins", self.plugins.len());
        Ok(self.plugins.clone())
    }

    /// Scan a directory for plugins
    fn scan_directory(&mut self, path: &Path, plugin_type: PluginType) -> PluginResult<()> {
        let extension = match plugin_type {
            PluginType::Vst3 => "vst3",
            PluginType::Clap => "clap",
            PluginType::AudioUnit => "component",
            PluginType::Internal => return Ok(()),
        };

        if let Ok(entries) = std::fs::read_dir(path) {
            for entry in entries.flatten() {
                let entry_path = entry.path();

                if entry_path.extension().map_or(false, |e| e == extension) {
                    match self.scan_plugin(&entry_path, plugin_type) {
                        Ok(info) => {
                            log::debug!("Found plugin: {} at {:?}", info.name, entry_path);
                            let idx = self.plugins.len();
                            self.plugin_map.insert(info.id.clone(), idx);
                            self.plugins.push(info);
                        }
                        Err(e) => {
                            log::warn!("Failed to scan plugin {:?}: {}", entry_path, e);
                        }
                    }
                }
            }
        }

        Ok(())
    }

    /// Scan a single plugin file/bundle
    fn scan_plugin(&self, path: &Path, plugin_type: PluginType) -> PluginResult<PluginInfo> {
        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown");

        let id = format!(
            "{}.{}",
            match plugin_type {
                PluginType::Vst3 => "vst3",
                PluginType::Clap => "clap",
                PluginType::AudioUnit => "au",
                PluginType::Internal => "internal",
            },
            name.to_lowercase().replace(' ', "_")
        );

        // For now, create basic info without actually loading the plugin
        // Full validation would require loading the plugin binary
        let mut info = PluginInfo::new(&id, name, plugin_type, path.to_path_buf());

        // Try to get more info based on plugin type
        match plugin_type {
            PluginType::Vst3 => {
                // VST3 bundles have Contents/Info.plist on macOS
                #[cfg(target_os = "macos")]
                if let Some(vendor) = Self::read_vst3_info(path) {
                    info.vendor = vendor;
                }
            }
            PluginType::Clap => {
                // CLAP plugins have embedded metadata
                info.category = PluginCategory::Effect;
            }
            PluginType::AudioUnit => {
                // AU components have Info.plist
                info.category = PluginCategory::Effect;
            }
            PluginType::Internal => {}
        }

        Ok(info)
    }

    /// Read VST3 plugin info from bundle
    #[cfg(target_os = "macos")]
    fn read_vst3_info(path: &Path) -> Option<String> {
        let plist_path = path.join("Contents/Info.plist");
        if plist_path.exists() {
            // Could parse plist here for vendor info
            // For now just return None
        }
        None
    }

    /// Get all discovered plugins
    pub fn plugins(&self) -> &[PluginInfo] {
        &self.plugins
    }

    /// Find plugin by ID
    pub fn find_plugin(&self, id: &str) -> Option<&PluginInfo> {
        self.plugin_map.get(id).map(|&idx| &self.plugins[idx])
    }

    /// Find plugins by category
    pub fn find_by_category(&self, category: PluginCategory) -> Vec<&PluginInfo> {
        self.plugins
            .iter()
            .filter(|p| p.category == category)
            .collect()
    }

    /// Find plugins by type
    pub fn find_by_type(&self, plugin_type: PluginType) -> Vec<&PluginInfo> {
        self.plugins
            .iter()
            .filter(|p| p.plugin_type == plugin_type)
            .collect()
    }

    /// Search plugins by name
    pub fn search(&self, query: &str) -> Vec<&PluginInfo> {
        let query_lower = query.to_lowercase();
        self.plugins
            .iter()
            .filter(|p| {
                p.name.to_lowercase().contains(&query_lower)
                    || p.vendor.to_lowercase().contains(&query_lower)
            })
            .collect()
    }
}

impl Default for PluginScanner {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scanner_creation() {
        let scanner = PluginScanner::new();
        // Should have internal plugins registered
        assert!(!scanner.internal_plugins.is_empty());
    }

    #[test]
    fn test_plugin_info() {
        let info = PluginInfo::internal("test.eq", "Test EQ", PluginCategory::Effect);
        assert_eq!(info.vendor, "ReelForge");
        assert_eq!(info.plugin_type, PluginType::Internal);
    }
}
