//! Preset management

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Preset metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PresetMeta {
    pub name: String,
    pub author: Option<String>,
    pub description: Option<String>,
    pub category: Option<String>,
    pub tags: Vec<String>,
    pub created: String,
    pub modified: String,
    pub version: u32,
}

impl Default for PresetMeta {
    fn default() -> Self {
        let now = chrono_lite();
        Self {
            name: "Untitled".to_string(),
            author: None,
            description: None,
            category: None,
            tags: Vec::new(),
            created: now.clone(),
            modified: now,
            version: 1,
        }
    }
}

fn chrono_lite() -> String {
    // Simple timestamp without chrono dependency
    "2025-01-01T00:00:00Z".to_string()
}

/// Generic preset structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Preset<T> {
    pub meta: PresetMeta,
    pub data: T,
}

impl<T: Default> Default for Preset<T> {
    fn default() -> Self {
        Self {
            meta: PresetMeta::default(),
            data: T::default(),
        }
    }
}

impl<T: Serialize> Preset<T> {
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }
}

impl<T: for<'de> Deserialize<'de>> Preset<T> {
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}

/// Preset bank for organizing presets
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PresetBank<T> {
    pub name: String,
    pub presets: Vec<Preset<T>>,
}

impl<T> PresetBank<T> {
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
            presets: Vec::new(),
        }
    }

    pub fn add(&mut self, preset: Preset<T>) {
        self.presets.push(preset);
    }

    pub fn remove(&mut self, index: usize) -> Option<Preset<T>> {
        if index < self.presets.len() {
            Some(self.presets.remove(index))
        } else {
            None
        }
    }

    pub fn get(&self, index: usize) -> Option<&Preset<T>> {
        self.presets.get(index)
    }

    pub fn len(&self) -> usize {
        self.presets.len()
    }

    pub fn is_empty(&self) -> bool {
        self.presets.is_empty()
    }
}

/// Preset manager for loading/saving presets
pub struct PresetManager {
    preset_dirs: Vec<PathBuf>,
    cache: HashMap<PathBuf, String>,
}

impl PresetManager {
    pub fn new() -> Self {
        Self {
            preset_dirs: Vec::new(),
            cache: HashMap::new(),
        }
    }

    pub fn add_directory(&mut self, path: PathBuf) {
        if !self.preset_dirs.contains(&path) {
            self.preset_dirs.push(path);
        }
    }

    pub fn scan_presets(&mut self) -> Vec<PathBuf> {
        let mut presets = Vec::new();

        for dir in &self.preset_dirs {
            if let Ok(entries) = std::fs::read_dir(dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.extension().map(|e| e == "json").unwrap_or(false) {
                        presets.push(path);
                    }
                }
            }
        }

        presets
    }

    pub fn load_preset<T: for<'de> Deserialize<'de>>(
        &mut self,
        path: &PathBuf,
    ) -> Result<Preset<T>, PresetError> {
        let json = if let Some(cached) = self.cache.get(path) {
            cached.clone()
        } else {
            let json = std::fs::read_to_string(path).map_err(PresetError::Io)?;
            self.cache.insert(path.clone(), json.clone());
            json
        };

        Preset::from_json(&json).map_err(PresetError::Parse)
    }

    pub fn save_preset<T: Serialize>(
        &mut self,
        preset: &Preset<T>,
        path: &PathBuf,
    ) -> Result<(), PresetError> {
        let json = preset.to_json().map_err(PresetError::Parse)?;

        // Ensure directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(PresetError::Io)?;
        }

        std::fs::write(path, &json).map_err(PresetError::Io)?;

        // Update cache
        self.cache.insert(path.clone(), json);

        Ok(())
    }

    pub fn clear_cache(&mut self) {
        self.cache.clear();
    }
}

impl Default for PresetManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Preset errors
#[derive(Debug, thiserror::Error)]
pub enum PresetError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Parse error: {0}")]
    Parse(#[from] serde_json::Error),

    #[error("Invalid preset: {0}")]
    Invalid(String),
}
