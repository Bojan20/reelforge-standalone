//! Plugin Scanner
//!
//! Discovers and catalogs VST3/CLAP/AU plugins on the system.
//! Supports:
//! - Standard plugin paths per platform
//! - Custom search paths
//! - Background scanning
//! - Progress reporting

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::SystemTime;

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

use crate::{PluginCache, PluginError, PluginResult};

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN FORMAT
// ═══════════════════════════════════════════════════════════════════════════════

/// Supported plugin formats
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum PluginFormat {
    /// Steinberg VST3
    Vst3,
    /// Clever Audio Plugin API
    Clap,
    /// Apple Audio Units
    Au,
    /// Legacy VST2 (not supported for new scans)
    Vst2,
}

impl PluginFormat {
    /// Get file extension for this format
    pub fn extension(&self) -> &'static str {
        match self {
            PluginFormat::Vst3 => "vst3",
            PluginFormat::Clap => "clap",
            PluginFormat::Au => "component",
            PluginFormat::Vst2 => "vst",
        }
    }

    /// Check if path matches this format
    pub fn matches_path(&self, path: &Path) -> bool {
        path.extension()
            .and_then(|e| e.to_str())
            .map(|e| e.eq_ignore_ascii_case(self.extension()))
            .unwrap_or(false)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN CATEGORY
// ═══════════════════════════════════════════════════════════════════════════════

/// Plugin category
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
pub enum PluginCategory {
    #[default]
    Effect,
    Instrument,
    Analyzer,
    Dynamics,
    Eq,
    Filter,
    Reverb,
    Delay,
    Modulation,
    Distortion,
    Utility,
}

impl PluginCategory {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "instrument" | "synth" | "generator" => Self::Instrument,
            "analyzer" | "analysis" | "meter" => Self::Analyzer,
            "dynamics" | "compressor" | "limiter" | "gate" => Self::Dynamics,
            "eq" | "equalizer" => Self::Eq,
            "filter" => Self::Filter,
            "reverb" | "room" | "hall" => Self::Reverb,
            "delay" | "echo" => Self::Delay,
            "modulation" | "chorus" | "flanger" | "phaser" => Self::Modulation,
            "distortion" | "saturation" | "overdrive" => Self::Distortion,
            "utility" | "tool" => Self::Utility,
            _ => Self::Effect,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN INFO
// ═══════════════════════════════════════════════════════════════════════════════

/// Plugin metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginInfo {
    /// Unique plugin ID
    pub id: String,
    /// Display name
    pub name: String,
    /// Vendor/manufacturer
    pub vendor: String,
    /// Version string
    pub version: String,
    /// Plugin format
    pub format: PluginFormat,
    /// Plugin category
    pub category: PluginCategory,
    /// File path
    pub path: PathBuf,
    /// Is this a synthesizer/instrument?
    pub is_instrument: bool,
    /// Number of audio inputs
    pub num_inputs: u32,
    /// Number of audio outputs
    pub num_outputs: u32,
    /// Supports MIDI input
    pub has_midi_input: bool,
    /// Supports MIDI output
    pub has_midi_output: bool,
    /// Plugin has been validated/scanned successfully
    pub is_valid: bool,
    /// Last scan timestamp
    pub scanned_at: u64,
    /// File modification time (for cache invalidation)
    pub file_modified: u64,
    /// Tags for search
    pub tags: Vec<String>,
}

impl PluginInfo {
    /// Create basic info from path (before full scan)
    pub fn from_path(path: PathBuf, format: PluginFormat) -> Self {
        let name = path.file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown")
            .to_string();

        let file_modified = std::fs::metadata(&path)
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        Self {
            id: format!("{:?}:{}", format, path.display()),
            name,
            vendor: String::new(),
            version: String::new(),
            format,
            category: PluginCategory::Effect,
            path,
            is_instrument: false,
            num_inputs: 2,
            num_outputs: 2,
            has_midi_input: false,
            has_midi_output: false,
            is_valid: false,
            scanned_at: now,
            file_modified,
            tags: Vec::new(),
        }
    }

    /// Check if plugin needs rescan (file modified since last scan)
    pub fn needs_rescan(&self) -> bool {
        let current_modified = std::fs::metadata(&self.path)
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.duration_since(SystemTime::UNIX_EPOCH).ok())
            .map(|d| d.as_secs())
            .unwrap_or(0);

        current_modified > self.file_modified
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCAN PROGRESS
// ═══════════════════════════════════════════════════════════════════════════════

/// Scan progress callback
pub type ScanProgressCallback = Box<dyn Fn(ScanProgress) + Send + Sync>;

/// Scan progress information
#[derive(Debug, Clone)]
pub struct ScanProgress {
    /// Current plugin being scanned
    pub current_plugin: String,
    /// Number of plugins scanned
    pub scanned: usize,
    /// Total plugins found
    pub total: usize,
    /// Number of valid plugins
    pub valid: usize,
    /// Number of failed plugins
    pub failed: usize,
}

impl ScanProgress {
    pub fn percent(&self) -> f32 {
        if self.total == 0 {
            0.0
        } else {
            (self.scanned as f32 / self.total as f32) * 100.0
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN SCANNER
// ═══════════════════════════════════════════════════════════════════════════════

/// Plugin scanner configuration
#[derive(Debug, Clone)]
pub struct ScannerConfig {
    /// Search paths for plugins
    pub search_paths: Vec<PathBuf>,
    /// Formats to scan
    pub formats: HashSet<PluginFormat>,
    /// Skip blacklisted plugins
    pub skip_blacklist: bool,
    /// Validate plugins during scan (slower but more reliable)
    pub validate: bool,
    /// Scan timeout per plugin (seconds)
    pub timeout_secs: u64,
}

impl Default for ScannerConfig {
    fn default() -> Self {
        let mut formats = HashSet::new();
        formats.insert(PluginFormat::Vst3);
        formats.insert(PluginFormat::Clap);

        #[cfg(target_os = "macos")]
        formats.insert(PluginFormat::Au);

        Self {
            search_paths: get_default_plugin_paths(),
            formats,
            skip_blacklist: true,
            validate: true,
            timeout_secs: 10,
        }
    }
}

/// Get default plugin search paths for current platform
pub fn get_default_plugin_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();

    #[cfg(target_os = "macos")]
    {
        // System paths
        paths.push(PathBuf::from("/Library/Audio/Plug-Ins/VST3"));
        paths.push(PathBuf::from("/Library/Audio/Plug-Ins/CLAP"));
        paths.push(PathBuf::from("/Library/Audio/Plug-Ins/Components"));

        // User paths
        if let Some(home) = dirs_next::home_dir() {
            paths.push(home.join("Library/Audio/Plug-Ins/VST3"));
            paths.push(home.join("Library/Audio/Plug-Ins/CLAP"));
            paths.push(home.join("Library/Audio/Plug-Ins/Components"));
        }
    }

    #[cfg(target_os = "windows")]
    {
        // Common Files paths
        if let Some(pf) = std::env::var_os("CommonProgramFiles") {
            let pf = PathBuf::from(pf);
            paths.push(pf.join("VST3"));
            paths.push(pf.join("CLAP"));
        }

        // User paths
        if let Some(local) = dirs_next::data_local_dir() {
            paths.push(local.join("Programs\\Common\\VST3"));
            paths.push(local.join("Programs\\Common\\CLAP"));
        }
    }

    #[cfg(target_os = "linux")]
    {
        // System paths
        paths.push(PathBuf::from("/usr/lib/vst3"));
        paths.push(PathBuf::from("/usr/lib/clap"));
        paths.push(PathBuf::from("/usr/local/lib/vst3"));
        paths.push(PathBuf::from("/usr/local/lib/clap"));

        // User paths
        if let Some(home) = dirs_next::home_dir() {
            paths.push(home.join(".vst3"));
            paths.push(home.join(".clap"));
        }
    }

    paths
}

/// Plugin scanner
pub struct PluginScanner {
    config: ScannerConfig,
    cache: Arc<RwLock<PluginCache>>,
    blacklist: HashSet<PathBuf>,
    progress_callback: Option<ScanProgressCallback>,
}

impl PluginScanner {
    /// Create new scanner with default config
    pub fn new() -> Self {
        Self {
            config: ScannerConfig::default(),
            cache: Arc::new(RwLock::new(PluginCache::new())),
            blacklist: HashSet::new(),
            progress_callback: None,
        }
    }

    /// Create scanner with custom config
    pub fn with_config(config: ScannerConfig) -> Self {
        Self {
            config,
            cache: Arc::new(RwLock::new(PluginCache::new())),
            blacklist: HashSet::new(),
            progress_callback: None,
        }
    }

    /// Set progress callback
    pub fn set_progress_callback<F>(&mut self, callback: F)
    where
        F: Fn(ScanProgress) + Send + Sync + 'static,
    {
        self.progress_callback = Some(Box::new(callback));
    }

    /// Add path to blacklist
    pub fn blacklist(&mut self, path: PathBuf) {
        self.blacklist.insert(path);
    }

    /// Add custom search path
    pub fn add_search_path(&mut self, path: PathBuf) {
        self.config.search_paths.push(path);
    }

    /// Discover all plugin files (without full scan)
    pub fn discover(&self) -> Vec<PathBuf> {
        let mut plugins = Vec::new();

        for search_path in &self.config.search_paths {
            if !search_path.exists() {
                continue;
            }

            for entry in WalkDir::new(search_path)
                .max_depth(3)
                .into_iter()
                .filter_map(|e| e.ok())
            {
                let path = entry.path();

                // Check if this matches any enabled format
                for format in &self.config.formats {
                    if format.matches_path(path) {
                        // Skip blacklisted
                        if self.config.skip_blacklist && self.blacklist.contains(path) {
                            continue;
                        }

                        plugins.push(path.to_path_buf());
                        break;
                    }
                }
            }
        }

        plugins
    }

    /// Full scan - discover and validate all plugins
    pub fn scan(&self) -> PluginResult<Vec<PluginInfo>> {
        let plugin_paths = self.discover();
        let total = plugin_paths.len();

        let mut results = Vec::with_capacity(total);
        let mut scanned = 0;
        let mut valid = 0;
        let mut failed = 0;

        for path in plugin_paths {
            // Determine format
            let format = self.config.formats.iter()
                .find(|f| f.matches_path(&path))
                .copied()
                .unwrap_or(PluginFormat::Vst3);

            let name = path.file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("Unknown")
                .to_string();

            // Report progress
            if let Some(ref callback) = self.progress_callback {
                callback(ScanProgress {
                    current_plugin: name.clone(),
                    scanned,
                    total,
                    valid,
                    failed,
                });
            }

            // Check cache first
            let cache = self.cache.read();
            if let Some(cached) = cache.get(&path) {
                if !cached.needs_rescan() {
                    results.push(cached.clone());
                    scanned += 1;
                    if cached.is_valid {
                        valid += 1;
                    }
                    continue;
                }
            }
            drop(cache);

            // Create basic info
            let mut info = PluginInfo::from_path(path.clone(), format);

            // Validate if enabled
            if self.config.validate {
                match self.validate_plugin(&info) {
                    Ok(validated) => {
                        info = validated;
                        info.is_valid = true;
                        valid += 1;
                    }
                    Err(e) => {
                        log::warn!("Plugin validation failed for {}: {}", name, e);
                        info.is_valid = false;
                        failed += 1;
                    }
                }
            } else {
                info.is_valid = true;
                valid += 1;
            }

            // Update cache
            let mut cache = self.cache.write();
            cache.insert(info.clone());

            results.push(info);
            scanned += 1;
        }

        // Final progress
        if let Some(ref callback) = self.progress_callback {
            callback(ScanProgress {
                current_plugin: "Complete".to_string(),
                scanned,
                total,
                valid,
                failed,
            });
        }

        Ok(results)
    }

    /// Validate a single plugin
    fn validate_plugin(&self, info: &PluginInfo) -> PluginResult<PluginInfo> {
        // This is where we would load the plugin in a sandboxed process
        // and extract metadata. For now, we just do basic validation.

        if !info.path.exists() {
            return Err(PluginError::NotFound(info.path.display().to_string()));
        }

        // Check file is readable
        std::fs::metadata(&info.path)
            .map_err(|e| PluginError::LoadError(e.to_string()))?;

        // In a real implementation, we would:
        // 1. Spawn a sandboxed child process
        // 2. Load the plugin in that process
        // 3. Extract metadata via IPC
        // 4. Timeout after config.timeout_secs

        let mut validated = info.clone();

        // Parse vendor from path (common convention)
        if let Some(parent) = info.path.parent() {
            if let Some(vendor) = parent.file_name().and_then(|s| s.to_str()) {
                validated.vendor = vendor.to_string();
            }
        }

        // Guess category from name
        let name_lower = info.name.to_lowercase();
        validated.category = if name_lower.contains("comp") || name_lower.contains("limit") {
            PluginCategory::Dynamics
        } else if name_lower.contains("eq") || name_lower.contains("filter") {
            PluginCategory::Eq
        } else if name_lower.contains("reverb") || name_lower.contains("verb") {
            PluginCategory::Reverb
        } else if name_lower.contains("delay") || name_lower.contains("echo") {
            PluginCategory::Delay
        } else if name_lower.contains("synth") || name_lower.contains("keys") {
            PluginCategory::Instrument
        } else if name_lower.contains("meter") || name_lower.contains("analyzer") {
            PluginCategory::Analyzer
        } else {
            PluginCategory::Effect
        };

        validated.is_instrument = validated.category == PluginCategory::Instrument;

        Ok(validated)
    }

    /// Get cached plugins
    pub fn cached_plugins(&self) -> Vec<PluginInfo> {
        self.cache.read().all()
    }

    /// Clear cache
    pub fn clear_cache(&self) {
        self.cache.write().clear();
    }

    /// Save cache to file
    pub fn save_cache<P: AsRef<Path>>(&self, path: P) -> PluginResult<()> {
        self.cache.read().save(path)
    }

    /// Load cache from file
    pub fn load_cache<P: AsRef<Path>>(&self, path: P) -> PluginResult<()> {
        let loaded = PluginCache::load(path)?;
        *self.cache.write() = loaded;
        Ok(())
    }
}

impl Default for PluginScanner {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_plugin_format_extension() {
        assert_eq!(PluginFormat::Vst3.extension(), "vst3");
        assert_eq!(PluginFormat::Clap.extension(), "clap");
        assert_eq!(PluginFormat::Au.extension(), "component");
    }

    #[test]
    fn test_plugin_format_matches() {
        assert!(PluginFormat::Vst3.matches_path(Path::new("/path/to/Plugin.vst3")));
        assert!(PluginFormat::Clap.matches_path(Path::new("/path/to/Plugin.clap")));
        assert!(!PluginFormat::Vst3.matches_path(Path::new("/path/to/Plugin.clap")));
    }

    #[test]
    fn test_category_from_str() {
        assert_eq!(PluginCategory::from_str("compressor"), PluginCategory::Dynamics);
        assert_eq!(PluginCategory::from_str("EQ"), PluginCategory::Eq);
        assert_eq!(PluginCategory::from_str("reverb"), PluginCategory::Reverb);
        assert_eq!(PluginCategory::from_str("unknown"), PluginCategory::Effect);
    }

    #[test]
    fn test_plugin_info_from_path() {
        let path = PathBuf::from("/test/FabFilter Pro-Q 3.vst3");
        let info = PluginInfo::from_path(path.clone(), PluginFormat::Vst3);

        assert_eq!(info.name, "FabFilter Pro-Q 3");
        assert_eq!(info.format, PluginFormat::Vst3);
        assert_eq!(info.path, path);
    }

    #[test]
    fn test_scanner_config_default() {
        let config = ScannerConfig::default();

        assert!(config.formats.contains(&PluginFormat::Vst3));
        assert!(config.formats.contains(&PluginFormat::Clap));
        assert!(config.validate);
    }

    #[test]
    fn test_scanner_creation() {
        let scanner = PluginScanner::new();

        // Should have default search paths
        assert!(!scanner.config.search_paths.is_empty() || cfg!(not(any(
            target_os = "macos",
            target_os = "windows",
            target_os = "linux"
        ))));
    }

    #[test]
    fn test_progress_percent() {
        let progress = ScanProgress {
            current_plugin: "Test".to_string(),
            scanned: 50,
            total: 100,
            valid: 45,
            failed: 5,
        };

        assert!((progress.percent() - 50.0).abs() < 0.01);
    }
}
