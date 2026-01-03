//! Plugin Cache
//!
//! Persistent storage for plugin metadata to avoid rescanning.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::{PluginError, PluginInfo, PluginResult};

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN CACHE
// ═══════════════════════════════════════════════════════════════════════════════

/// Cache version for migration
const CACHE_VERSION: u32 = 1;

/// Plugin cache file format
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginCacheFile {
    /// Cache version
    pub version: u32,
    /// Plugins indexed by path
    pub plugins: HashMap<String, PluginInfo>,
}

impl Default for PluginCacheFile {
    fn default() -> Self {
        Self {
            version: CACHE_VERSION,
            plugins: HashMap::new(),
        }
    }
}

/// In-memory plugin cache
#[derive(Debug, Clone, Default)]
pub struct PluginCache {
    /// Plugins indexed by path
    plugins: HashMap<PathBuf, PluginInfo>,
    /// Is cache dirty (modified since last save)?
    dirty: bool,
}

impl PluginCache {
    /// Create new empty cache
    pub fn new() -> Self {
        Self {
            plugins: HashMap::new(),
            dirty: false,
        }
    }

    /// Get plugin by path
    pub fn get(&self, path: &Path) -> Option<&PluginInfo> {
        self.plugins.get(path)
    }

    /// Insert plugin info
    pub fn insert(&mut self, info: PluginInfo) {
        self.plugins.insert(info.path.clone(), info);
        self.dirty = true;
    }

    /// Remove plugin by path
    pub fn remove(&mut self, path: &Path) -> Option<PluginInfo> {
        let removed = self.plugins.remove(path);
        if removed.is_some() {
            self.dirty = true;
        }
        removed
    }

    /// Get all cached plugins
    pub fn all(&self) -> Vec<PluginInfo> {
        self.plugins.values().cloned().collect()
    }

    /// Get all valid plugins
    pub fn valid(&self) -> Vec<PluginInfo> {
        self.plugins.values()
            .filter(|p| p.is_valid)
            .cloned()
            .collect()
    }

    /// Clear all entries
    pub fn clear(&mut self) {
        self.plugins.clear();
        self.dirty = true;
    }

    /// Number of cached plugins
    pub fn len(&self) -> usize {
        self.plugins.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.plugins.is_empty()
    }

    /// Check if cache is dirty
    pub fn is_dirty(&self) -> bool {
        self.dirty
    }

    /// Mark cache as clean
    pub fn mark_clean(&mut self) {
        self.dirty = false;
    }

    /// Save cache to file
    pub fn save<P: AsRef<Path>>(&self, path: P) -> PluginResult<()> {
        let cache_file = PluginCacheFile {
            version: CACHE_VERSION,
            plugins: self.plugins.iter()
                .map(|(k, v)| (k.display().to_string(), v.clone()))
                .collect(),
        };

        let json = serde_json::to_string_pretty(&cache_file)?;
        fs::write(path, json)?;

        Ok(())
    }

    /// Load cache from file
    pub fn load<P: AsRef<Path>>(path: P) -> PluginResult<Self> {
        let content = fs::read_to_string(path)?;
        let cache_file: PluginCacheFile = serde_json::from_str(&content)?;

        // Version check
        if cache_file.version > CACHE_VERSION {
            return Err(PluginError::CacheError(format!(
                "Cache version {} is newer than supported version {}",
                cache_file.version, CACHE_VERSION
            )));
        }

        let plugins = cache_file.plugins.into_iter()
            .map(|(k, v)| (PathBuf::from(k), v))
            .collect();

        Ok(Self {
            plugins,
            dirty: false,
        })
    }

    /// Prune invalid entries (files that no longer exist)
    pub fn prune(&mut self) -> usize {
        let before = self.plugins.len();

        self.plugins.retain(|path, _| path.exists());

        let removed = before - self.plugins.len();
        if removed > 0 {
            self.dirty = true;
        }
        removed
    }

    /// Find plugins matching search query
    pub fn search(&self, query: &str) -> Vec<&PluginInfo> {
        let query = query.to_lowercase();

        self.plugins.values()
            .filter(|p| {
                p.name.to_lowercase().contains(&query)
                    || p.vendor.to_lowercase().contains(&query)
                    || p.tags.iter().any(|t| t.to_lowercase().contains(&query))
            })
            .collect()
    }

    /// Find plugins by category
    pub fn by_category(&self, category: crate::PluginCategory) -> Vec<&PluginInfo> {
        self.plugins.values()
            .filter(|p| p.category == category)
            .collect()
    }

    /// Find plugins by format
    pub fn by_format(&self, format: crate::PluginFormat) -> Vec<&PluginInfo> {
        self.plugins.values()
            .filter(|p| p.format == format)
            .collect()
    }

    /// Find instruments
    pub fn instruments(&self) -> Vec<&PluginInfo> {
        self.plugins.values()
            .filter(|p| p.is_instrument)
            .collect()
    }

    /// Find effects (non-instruments)
    pub fn effects(&self) -> Vec<&PluginInfo> {
        self.plugins.values()
            .filter(|p| !p.is_instrument)
            .collect()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PLUGIN COLLECTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Organized collection of plugins
#[derive(Debug, Clone, Default)]
pub struct PluginCollection {
    /// All plugins
    pub all: Vec<PluginInfo>,
    /// By vendor
    pub by_vendor: HashMap<String, Vec<usize>>,
    /// By category
    pub by_category: HashMap<crate::PluginCategory, Vec<usize>>,
    /// By format
    pub by_format: HashMap<crate::PluginFormat, Vec<usize>>,
    /// Favorites
    pub favorites: Vec<usize>,
    /// Recently used
    pub recent: Vec<usize>,
}

impl PluginCollection {
    /// Build collection from cache
    pub fn from_cache(cache: &PluginCache) -> Self {
        let all: Vec<PluginInfo> = cache.valid();
        let mut collection = Self {
            all: Vec::new(),
            by_vendor: HashMap::new(),
            by_category: HashMap::new(),
            by_format: HashMap::new(),
            favorites: Vec::new(),
            recent: Vec::new(),
        };

        for (idx, plugin) in all.into_iter().enumerate() {
            // Index by vendor
            collection.by_vendor
                .entry(plugin.vendor.clone())
                .or_default()
                .push(idx);

            // Index by category
            collection.by_category
                .entry(plugin.category)
                .or_default()
                .push(idx);

            // Index by format
            collection.by_format
                .entry(plugin.format)
                .or_default()
                .push(idx);

            collection.all.push(plugin);
        }

        collection
    }

    /// Get plugin by index
    pub fn get(&self, index: usize) -> Option<&PluginInfo> {
        self.all.get(index)
    }

    /// Get plugins by vendor
    pub fn vendor(&self, vendor: &str) -> Vec<&PluginInfo> {
        self.by_vendor.get(vendor)
            .map(|indices| indices.iter().filter_map(|&i| self.all.get(i)).collect())
            .unwrap_or_default()
    }

    /// Get list of all vendors
    pub fn vendors(&self) -> Vec<&str> {
        self.by_vendor.keys().map(|s| s.as_str()).collect()
    }

    /// Mark plugin as favorite
    pub fn add_favorite(&mut self, index: usize) {
        if !self.favorites.contains(&index) && index < self.all.len() {
            self.favorites.push(index);
        }
    }

    /// Remove from favorites
    pub fn remove_favorite(&mut self, index: usize) {
        self.favorites.retain(|&i| i != index);
    }

    /// Add to recent
    pub fn add_recent(&mut self, index: usize) {
        // Remove if already in list
        self.recent.retain(|&i| i != index);
        // Add at front
        self.recent.insert(0, index);
        // Keep only last 20
        self.recent.truncate(20);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{PluginCategory, PluginFormat};

    fn create_test_plugin(name: &str, vendor: &str) -> PluginInfo {
        PluginInfo {
            id: format!("test:{}", name),
            name: name.to_string(),
            vendor: vendor.to_string(),
            version: "1.0".to_string(),
            format: PluginFormat::Vst3,
            category: PluginCategory::Effect,
            path: PathBuf::from(format!("/test/{}.vst3", name)),
            is_instrument: false,
            num_inputs: 2,
            num_outputs: 2,
            has_midi_input: false,
            has_midi_output: false,
            is_valid: true,
            scanned_at: 0,
            file_modified: 0,
            tags: vec!["test".to_string()],
        }
    }

    #[test]
    fn test_cache_insert_get() {
        let mut cache = PluginCache::new();
        let plugin = create_test_plugin("TestPlugin", "TestVendor");
        let path = plugin.path.clone();

        cache.insert(plugin);

        assert!(cache.get(&path).is_some());
        assert_eq!(cache.get(&path).unwrap().name, "TestPlugin");
    }

    #[test]
    fn test_cache_search() {
        let mut cache = PluginCache::new();
        cache.insert(create_test_plugin("Pro-Q 3", "FabFilter"));
        cache.insert(create_test_plugin("Pro-C 2", "FabFilter"));
        cache.insert(create_test_plugin("Limiter", "DMG Audio"));

        let results = cache.search("fabfilter");
        assert_eq!(results.len(), 2);

        let results = cache.search("pro-q");
        assert_eq!(results.len(), 1);
    }

    #[test]
    fn test_cache_dirty_flag() {
        let mut cache = PluginCache::new();
        assert!(!cache.is_dirty());

        cache.insert(create_test_plugin("Test", "Vendor"));
        assert!(cache.is_dirty());

        cache.mark_clean();
        assert!(!cache.is_dirty());
    }

    #[test]
    fn test_collection_from_cache() {
        let mut cache = PluginCache::new();
        cache.insert(create_test_plugin("Plugin1", "VendorA"));
        cache.insert(create_test_plugin("Plugin2", "VendorA"));
        cache.insert(create_test_plugin("Plugin3", "VendorB"));

        let collection = PluginCollection::from_cache(&cache);

        assert_eq!(collection.all.len(), 3);
        assert_eq!(collection.vendors().len(), 2);
        assert_eq!(collection.vendor("VendorA").len(), 2);
    }

    #[test]
    fn test_collection_favorites() {
        let mut cache = PluginCache::new();
        cache.insert(create_test_plugin("Plugin1", "Vendor"));
        cache.insert(create_test_plugin("Plugin2", "Vendor"));

        let mut collection = PluginCollection::from_cache(&cache);

        collection.add_favorite(0);
        assert_eq!(collection.favorites.len(), 1);

        collection.add_favorite(0); // Duplicate
        assert_eq!(collection.favorites.len(), 1);

        collection.remove_favorite(0);
        assert!(collection.favorites.is_empty());
    }

    #[test]
    fn test_collection_recent() {
        let mut cache = PluginCache::new();
        for i in 0..25 {
            cache.insert(create_test_plugin(&format!("Plugin{}", i), "Vendor"));
        }

        let mut collection = PluginCollection::from_cache(&cache);

        for i in 0..25 {
            collection.add_recent(i);
        }

        // Should only keep 20 most recent
        assert_eq!(collection.recent.len(), 20);
        // Most recent should be last added
        assert_eq!(collection.recent[0], 24);
    }
}
