//! Autosave System
//!
//! Provides automatic project saving:
//! - Configurable interval
//! - Crash recovery
//! - Backup rotation
//! - Save-on-change detection

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};

// ============ Autosave Config ============

/// Autosave configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutosaveConfig {
    /// Enable autosave
    pub enabled: bool,
    /// Interval in seconds
    pub interval_secs: u64,
    /// Number of backup files to keep
    pub backup_count: usize,
    /// Save on significant changes
    pub save_on_change: bool,
    /// Minimum time between saves (seconds)
    pub min_interval_secs: u64,
    /// Autosave directory
    pub autosave_dir: PathBuf,
}

impl Default for AutosaveConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            interval_secs: 60, // 1 minute
            backup_count: 5,
            save_on_change: true,
            min_interval_secs: 10,
            autosave_dir: default_autosave_dir(),
        }
    }
}

fn default_autosave_dir() -> PathBuf {
    dirs::data_local_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("FluxForge Studio")
        .join("Autosave")
}

// ============ Autosave State ============

/// State tracking for autosave
pub struct AutosaveState {
    /// Last save timestamp
    last_save: AtomicU64,
    /// Pending changes flag
    has_changes: AtomicBool,
    /// Currently saving flag
    is_saving: AtomicBool,
    /// Change counter (for detecting significant changes)
    change_count: AtomicU64,
    /// Last change count at save
    last_saved_change_count: AtomicU64,
}

impl AutosaveState {
    pub fn new() -> Self {
        Self {
            last_save: AtomicU64::new(0),
            has_changes: AtomicBool::new(false),
            is_saving: AtomicBool::new(false),
            change_count: AtomicU64::new(0),
            last_saved_change_count: AtomicU64::new(0),
        }
    }

    /// Mark that a change occurred
    pub fn mark_changed(&self) {
        self.has_changes.store(true, Ordering::Relaxed);
        self.change_count.fetch_add(1, Ordering::Relaxed);
    }

    /// Mark save started
    pub fn start_save(&self) -> bool {
        self.is_saving
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok()
    }

    /// Mark save completed
    pub fn complete_save(&self) {
        self.has_changes.store(false, Ordering::Relaxed);
        self.last_saved_change_count
            .store(self.change_count.load(Ordering::Relaxed), Ordering::Relaxed);
        self.last_save.store(current_timestamp(), Ordering::Relaxed);
        self.is_saving.store(false, Ordering::Relaxed);
    }

    /// Check if has unsaved changes
    pub fn has_changes(&self) -> bool {
        self.has_changes.load(Ordering::Relaxed)
    }

    /// Check if save is in progress
    pub fn is_saving(&self) -> bool {
        self.is_saving.load(Ordering::Relaxed)
    }

    /// Get time since last save (seconds)
    pub fn seconds_since_save(&self) -> u64 {
        let last = self.last_save.load(Ordering::Relaxed);
        if last == 0 {
            return u64::MAX;
        }
        (current_timestamp() - last) / 1000
    }

    /// Get number of changes since last save
    pub fn changes_since_save(&self) -> u64 {
        let current = self.change_count.load(Ordering::Relaxed);
        let saved = self.last_saved_change_count.load(Ordering::Relaxed);
        current.saturating_sub(saved)
    }
}

impl Default for AutosaveState {
    fn default() -> Self {
        Self::new()
    }
}

fn current_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

// ============ Autosave Manager ============

/// Manages autosave functionality
pub struct AutosaveManager {
    config: RwLock<AutosaveConfig>,
    state: AutosaveState,
    project_path: RwLock<Option<PathBuf>>,
    project_name: RwLock<String>,
}

impl AutosaveManager {
    pub fn new(config: AutosaveConfig) -> Self {
        Self {
            config: RwLock::new(config),
            state: AutosaveState::new(),
            project_path: RwLock::new(None),
            project_name: RwLock::new("Untitled".to_string()),
        }
    }

    /// Set project path
    pub fn set_project_path(&self, path: Option<PathBuf>) {
        *self.project_path.write() = path;
    }

    /// Set project name
    pub fn set_project_name(&self, name: impl Into<String>) {
        *self.project_name.write() = name.into();
    }

    /// Get autosave file path
    ///
    /// Returns a safe path within the autosave directory.
    /// Path traversal attacks are prevented by sanitizing the filename
    /// and validating the final path stays within the autosave directory.
    pub fn autosave_path(&self) -> PathBuf {
        let config = self.config.read();
        let name = self.project_name.read();
        let timestamp = current_timestamp();

        let filename = format!(
            "{}_autosave_{}.rfproj",
            sanitize_filename(&name),
            timestamp
        );

        let path = config.autosave_dir.join(&filename);

        // Security: Verify the path is within autosave_dir (defense in depth)
        // Even though sanitize_filename should prevent traversal, we double-check
        if let (Ok(canonical_dir), Some(canonical_path)) = (
            config.autosave_dir.canonicalize(),
            // For new files, check parent directory
            path.parent()
                .and_then(|p| p.canonicalize().ok())
                .or_else(|| config.autosave_dir.canonicalize().ok()),
        )
            && !canonical_path.starts_with(&canonical_dir) {
                log::error!(
                    "Path traversal attempt detected: {} escapes {}",
                    path.display(),
                    config.autosave_dir.display()
                );
                // Return a safe fallback path
                return config.autosave_dir.join(format!("unnamed_autosave_{}.rfproj", timestamp));
            }

        path
    }

    /// Get latest autosave for recovery
    pub fn latest_autosave(&self) -> Option<PathBuf> {
        let config = self.config.read();

        if !config.autosave_dir.exists() {
            return None;
        }

        std::fs::read_dir(&config.autosave_dir)
            .ok()?
            .filter_map(|e| e.ok())
            .filter(|e| {
                e.path()
                    .extension()
                    .map(|ext| ext == "rfproj")
                    .unwrap_or(false)
            })
            .max_by_key(|e| {
                e.metadata()
                    .and_then(|m| m.modified())
                    .unwrap_or(UNIX_EPOCH)
            })
            .map(|e| e.path())
    }

    /// Check if autosave should happen now
    pub fn should_save(&self) -> bool {
        let config = self.config.read();

        if !config.enabled || self.state.is_saving() {
            return false;
        }

        if !self.state.has_changes() {
            return false;
        }

        let secs = self.state.seconds_since_save();

        // Regular interval save
        if secs >= config.interval_secs {
            return true;
        }

        // Save on significant change
        if config.save_on_change && secs >= config.min_interval_secs {
            let changes = self.state.changes_since_save();
            // Consider 10+ changes as significant
            if changes >= 10 {
                return true;
            }
        }

        false
    }

    /// Mark change occurred
    pub fn mark_changed(&self) {
        self.state.mark_changed();
    }

    /// Check for unsaved changes
    pub fn has_unsaved_changes(&self) -> bool {
        self.state.has_changes()
    }

    /// Perform autosave with data
    pub fn autosave<T: Serialize>(&self, data: &T) -> Result<PathBuf, AutosaveError> {
        if !self.state.start_save() {
            return Err(AutosaveError::SaveInProgress);
        }

        let result = self.do_autosave(data);

        self.state.complete_save();
        result
    }

    fn do_autosave<T: Serialize>(&self, data: &T) -> Result<PathBuf, AutosaveError> {
        let config = self.config.read();

        // Ensure directory exists
        std::fs::create_dir_all(&config.autosave_dir)?;

        // Generate autosave path
        let path = self.autosave_path();

        // Serialize and save
        let json = serde_json::to_string_pretty(data)?;
        std::fs::write(&path, json)?;

        // Rotate old backups
        self.rotate_backups(&config)?;

        log::info!("Autosave completed: {:?}", path);
        Ok(path)
    }

    /// Rotate old backup files
    fn rotate_backups(&self, config: &AutosaveConfig) -> Result<(), AutosaveError> {
        let name_prefix = {
            let name = self.project_name.read();
            format!("{}_autosave_", sanitize_filename(&name))
        };

        let mut autosaves: Vec<_> = std::fs::read_dir(&config.autosave_dir)?
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().starts_with(&name_prefix))
            .collect();

        // Sort by modification time (newest first)
        autosaves.sort_by(|a, b| {
            let a_time = a
                .metadata()
                .and_then(|m| m.modified())
                .unwrap_or(UNIX_EPOCH);
            let b_time = b
                .metadata()
                .and_then(|m| m.modified())
                .unwrap_or(UNIX_EPOCH);
            b_time.cmp(&a_time)
        });

        // Delete excess backups
        for old in autosaves.iter().skip(config.backup_count) {
            if let Err(e) = std::fs::remove_file(old.path()) {
                log::warn!("Failed to remove old autosave: {:?}", e);
            }
        }

        Ok(())
    }

    /// Get list of available autosaves
    pub fn list_autosaves(&self) -> Vec<AutosaveInfo> {
        let config = self.config.read();

        if !config.autosave_dir.exists() {
            return Vec::new();
        }

        std::fs::read_dir(&config.autosave_dir)
            .into_iter()
            .flatten()
            .filter_map(|e| e.ok())
            .filter(|e| {
                e.path()
                    .extension()
                    .map(|ext| ext == "rfproj")
                    .unwrap_or(false)
            })
            .filter_map(|e| {
                let path = e.path();
                let metadata = e.metadata().ok()?;
                let modified = metadata.modified().ok()?;
                let size = metadata.len();

                Some(AutosaveInfo {
                    path: path.clone(),
                    name: path.file_stem()?.to_string_lossy().into_owned(),
                    size,
                    modified,
                })
            })
            .collect()
    }

    /// Delete all autosaves for current project
    pub fn clear_autosaves(&self) -> Result<usize, AutosaveError> {
        let config = self.config.read();
        let name_prefix = {
            let name = self.project_name.read();
            format!("{}_autosave_", sanitize_filename(&name))
        };

        let mut count = 0;

        if let Ok(entries) = std::fs::read_dir(&config.autosave_dir) {
            for entry in entries.flatten() {
                if entry
                    .file_name()
                    .to_string_lossy()
                    .starts_with(&name_prefix)
                    && std::fs::remove_file(entry.path()).is_ok() {
                        count += 1;
                    }
            }
        }

        Ok(count)
    }

    /// Recover from autosave
    pub fn recover<T: for<'de> Deserialize<'de>>(&self, path: &Path) -> Result<T, AutosaveError> {
        let json = std::fs::read_to_string(path)?;
        let data: T = serde_json::from_str(&json)?;
        Ok(data)
    }

    /// Get current config
    pub fn config(&self) -> AutosaveConfig {
        self.config.read().clone()
    }

    /// Update config
    pub fn set_config(&self, config: AutosaveConfig) {
        *self.config.write() = config;
    }

    /// Get autosave state
    pub fn state(&self) -> AutosaveStatus {
        AutosaveStatus {
            enabled: self.config.read().enabled,
            has_changes: self.state.has_changes(),
            is_saving: self.state.is_saving(),
            seconds_since_save: self.state.seconds_since_save(),
            changes_since_save: self.state.changes_since_save(),
        }
    }
}

impl Default for AutosaveManager {
    fn default() -> Self {
        Self::new(AutosaveConfig::default())
    }
}

// ============ Helper Types ============

/// Autosave file info
#[derive(Debug, Clone)]
pub struct AutosaveInfo {
    pub path: PathBuf,
    pub name: String,
    pub size: u64,
    pub modified: SystemTime,
}

/// Autosave status
#[derive(Debug, Clone)]
pub struct AutosaveStatus {
    pub enabled: bool,
    pub has_changes: bool,
    pub is_saving: bool,
    pub seconds_since_save: u64,
    pub changes_since_save: u64,
}

/// Autosave errors
#[derive(Debug, thiserror::Error)]
pub enum AutosaveError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialize(#[from] serde_json::Error),

    #[error("Save already in progress")]
    SaveInProgress,

    #[error("No autosave found")]
    NotFound,
}

/// Sanitize filename for cross-platform compatibility
/// Also prevents path traversal attacks by removing directory separators and ".."
fn sanitize_filename(name: &str) -> String {
    // First pass: replace dangerous characters
    let sanitized: String = name
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            _ => c,
        })
        .collect();

    // Second pass: remove any ".." sequences that could escape directory
    let mut result = sanitized.replace("..", "");

    // Remove leading/trailing dots and spaces (Windows compatibility)
    result = result.trim_matches(|c| c == '.' || c == ' ').to_string();

    // If empty after sanitization, use a default name
    if result.is_empty() {
        result = "unnamed".to_string();
    }

    // Limit filename length (255 is typical filesystem limit)
    if result.len() > 200 {
        result.truncate(200);
    }

    result
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn test_autosave_state() {
        let state = AutosaveState::new();

        assert!(!state.has_changes());

        state.mark_changed();
        assert!(state.has_changes());

        state.complete_save();
        assert!(!state.has_changes());
    }

    #[test]
    fn test_sanitize_filename() {
        assert_eq!(sanitize_filename("test:file"), "test_file");
        assert_eq!(sanitize_filename("test/path"), "test_path");
        assert_eq!(sanitize_filename("valid_name"), "valid_name");
    }

    #[test]
    fn test_autosave_manager() {
        let config = AutosaveConfig {
            autosave_dir: std::env::temp_dir().join("rf_autosave_test"),
            ..Default::default()
        };

        let manager = AutosaveManager::new(config);
        manager.set_project_name("TestProject");

        // Mark change
        manager.mark_changed();
        assert!(manager.has_unsaved_changes());

        // Test autosave
        let data: HashMap<String, i32> = HashMap::from([("test".to_string(), 42)]);

        if let Ok(path) = manager.autosave(&data) {
            assert!(path.exists());
            // Cleanup
            let _ = std::fs::remove_file(path);
        }

        // Cleanup dir
        let _ = std::fs::remove_dir_all(std::env::temp_dir().join("rf_autosave_test"));
    }
}
