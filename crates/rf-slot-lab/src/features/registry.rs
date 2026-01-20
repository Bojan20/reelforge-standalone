//! Feature Registry — Central storage for all feature chapters

use std::collections::HashMap;

use super::{BoxedFeatureChapter, FeatureCategory, FeatureConfig, FeatureId, FeatureInfo};

/// Central registry for all feature chapters
///
/// The registry stores all available features and allows them to be
/// retrieved, configured, and managed.
///
/// ## Usage
///
/// ```rust,ignore
/// let mut registry = FeatureRegistry::new();
///
/// // Built-in features are registered automatically
/// let fs = registry.get(&FeatureId::new("free_spins"));
///
/// // List all features
/// for info in registry.list_all() {
///     println!("{}: {}", info.name, info.description);
/// }
/// ```
pub struct FeatureRegistry {
    /// All registered features
    chapters: HashMap<FeatureId, BoxedFeatureChapter>,

    /// Features grouped by category
    by_category: HashMap<FeatureCategory, Vec<FeatureId>>,
}

impl FeatureRegistry {
    /// Create a new empty registry
    pub fn new() -> Self {
        Self {
            chapters: HashMap::new(),
            by_category: HashMap::new(),
        }
    }

    /// Create a registry with built-in features
    ///
    /// This registers all standard features:
    /// - free_spins
    /// - cascades
    /// - hold_and_win
    /// - jackpot
    /// - gamble
    pub fn with_builtins() -> Self {
        let registry = Self::new();

        // TODO: Register built-in features when implemented
        // registry.register(Box::new(FreeSpinsChapter::new()));
        // registry.register(Box::new(CascadesChapter::new()));
        // registry.register(Box::new(HoldAndWinChapter::new()));
        // registry.register(Box::new(JackpotChapter::new()));
        // registry.register(Box::new(GambleChapter::new()));

        registry
    }

    /// Register a feature chapter
    pub fn register(&mut self, chapter: BoxedFeatureChapter) {
        let id = chapter.id();
        let category = chapter.category();

        // Add to category index
        self.by_category
            .entry(category)
            .or_default()
            .push(id.clone());

        // Store chapter
        self.chapters.insert(id, chapter);
    }

    /// Unregister a feature
    pub fn unregister(&mut self, id: &FeatureId) -> Option<BoxedFeatureChapter> {
        if let Some(chapter) = self.chapters.remove(id) {
            let category = chapter.category();
            if let Some(ids) = self.by_category.get_mut(&category) {
                ids.retain(|i| i != id);
            }
            Some(chapter)
        } else {
            None
        }
    }

    /// Get a feature by ID (immutable)
    pub fn get(&self, id: &FeatureId) -> Option<&dyn super::FeatureChapter> {
        self.chapters.get(id).map(|c| c.as_ref())
    }

    /// Get a feature by ID (mutable)
    pub fn get_mut(&mut self, id: &FeatureId) -> Option<&mut BoxedFeatureChapter> {
        self.chapters.get_mut(id)
    }

    /// Check if a feature is registered
    pub fn has(&self, id: &FeatureId) -> bool {
        self.chapters.contains_key(id)
    }

    /// Get number of registered features
    pub fn len(&self) -> usize {
        self.chapters.len()
    }

    /// Check if registry is empty
    pub fn is_empty(&self) -> bool {
        self.chapters.is_empty()
    }

    /// List all feature IDs
    pub fn list_ids(&self) -> Vec<&FeatureId> {
        self.chapters.keys().collect()
    }

    /// List all feature info
    pub fn list_all(&self) -> Vec<FeatureInfo> {
        self.chapters.values().map(|c| c.info()).collect()
    }

    /// List features by category
    pub fn list_by_category(&self, category: FeatureCategory) -> Vec<&FeatureId> {
        self.by_category
            .get(&category)
            .map(|ids| ids.iter().collect())
            .unwrap_or_default()
    }

    /// Get all categories that have features
    pub fn categories(&self) -> Vec<FeatureCategory> {
        self.by_category.keys().copied().collect()
    }

    /// Configure a feature
    pub fn configure(
        &mut self,
        id: &FeatureId,
        config: &FeatureConfig,
    ) -> Result<(), RegistryError> {
        self.chapters
            .get_mut(id)
            .ok_or_else(|| RegistryError::NotFound(id.clone()))?
            .configure(config)
            .map_err(RegistryError::ConfigError)
    }

    /// Configure multiple features from a list
    pub fn configure_many(
        &mut self,
        configs: &[(FeatureId, FeatureConfig)],
    ) -> Result<(), RegistryError> {
        for (id, config) in configs {
            self.configure(id, config)?;
        }
        Ok(())
    }

    /// Reset all features
    pub fn reset_all(&mut self) {
        for chapter in self.chapters.values_mut() {
            chapter.reset();
        }
    }

    /// Deactivate all features
    pub fn deactivate_all(&mut self) {
        for chapter in self.chapters.values_mut() {
            chapter.deactivate();
        }
    }

    /// Get all active features
    pub fn active_features(&self) -> Vec<&FeatureId> {
        self.chapters
            .iter()
            .filter(|(_, c)| c.is_active())
            .map(|(id, _)| id)
            .collect()
    }

    /// Iterate over all chapters
    pub fn iter(&self) -> impl Iterator<Item = (&FeatureId, &dyn super::FeatureChapter)> {
        self.chapters.iter().map(|(id, c)| (id, c.as_ref()))
    }

    /// Iterate over all chapters (mutable)
    pub fn iter_mut(
        &mut self,
    ) -> impl Iterator<Item = (&FeatureId, &mut BoxedFeatureChapter)> + '_ {
        self.chapters.iter_mut()
    }
}

impl Default for FeatureRegistry {
    fn default() -> Self {
        Self::with_builtins()
    }
}

/// Registry errors
#[derive(Debug, thiserror::Error)]
pub enum RegistryError {
    #[error("Feature not found: {0}")]
    NotFound(FeatureId),

    #[error("Configuration error: {0}")]
    ConfigError(#[from] super::ConfigError),

    #[error("Feature already registered: {0}")]
    AlreadyRegistered(FeatureId),
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::features::{
        ActivationContext, FeatureResult, FeatureSnapshot, FeatureState, SpinContext,
    };
    use crate::timing::TimestampGenerator;
    use rf_stage::StageEvent;

    // Test feature for registry tests
    struct DummyFeature {
        id: String,
        category: FeatureCategory,
    }

    impl DummyFeature {
        fn new(id: &str, category: FeatureCategory) -> Self {
            Self {
                id: id.to_string(),
                category,
            }
        }
    }

    impl super::super::FeatureChapter for DummyFeature {
        fn id(&self) -> FeatureId {
            FeatureId::new(&self.id)
        }
        fn name(&self) -> &str {
            &self.id
        }
        fn category(&self) -> FeatureCategory {
            self.category
        }
        fn configure(&mut self, _: &FeatureConfig) -> Result<(), super::super::ConfigError> {
            Ok(())
        }
        fn state(&self) -> FeatureState {
            FeatureState::Inactive
        }
        fn snapshot(&self) -> FeatureSnapshot {
            FeatureSnapshot {
                feature_id: self.id.clone(),
                is_active: false,
                current_step: 0,
                total_steps: None,
                multiplier: 1.0,
                accumulated_win: 0.0,
                data: Default::default(),
            }
        }
        fn restore(&mut self, _: &FeatureSnapshot) -> Result<(), super::super::ConfigError> {
            Ok(())
        }
        fn can_activate(&self, _: &ActivationContext) -> bool {
            true
        }
        fn activate(&mut self, _: &ActivationContext) {}
        fn deactivate(&mut self) {}
        fn reset(&mut self) {}
        fn process_spin(&mut self, _: &mut SpinContext) -> FeatureResult {
            FeatureResult::complete(0.0)
        }
        fn generate_stages(&self, _: &mut TimestampGenerator) -> Vec<StageEvent> {
            Vec::new()
        }
    }

    #[test]
    fn test_registry_register() {
        let mut registry = FeatureRegistry::new();

        registry.register(Box::new(DummyFeature::new("test", FeatureCategory::Other)));

        assert!(registry.has(&FeatureId::new("test")));
        assert_eq!(registry.len(), 1);
    }

    #[test]
    fn test_registry_get() {
        let mut registry = FeatureRegistry::new();
        registry.register(Box::new(DummyFeature::new("fs", FeatureCategory::FreeSpins)));

        let feature = registry.get(&FeatureId::new("fs"));
        assert!(feature.is_some());
        assert_eq!(feature.unwrap().name(), "fs");

        let missing = registry.get(&FeatureId::new("missing"));
        assert!(missing.is_none());
    }

    #[test]
    fn test_registry_by_category() {
        let mut registry = FeatureRegistry::new();
        registry.register(Box::new(DummyFeature::new("fs1", FeatureCategory::FreeSpins)));
        registry.register(Box::new(DummyFeature::new("fs2", FeatureCategory::FreeSpins)));
        registry.register(Box::new(DummyFeature::new("jp", FeatureCategory::Jackpot)));

        let fs_features = registry.list_by_category(FeatureCategory::FreeSpins);
        assert_eq!(fs_features.len(), 2);

        let jp_features = registry.list_by_category(FeatureCategory::Jackpot);
        assert_eq!(jp_features.len(), 1);
    }

    #[test]
    fn test_registry_unregister() {
        let mut registry = FeatureRegistry::new();
        registry.register(Box::new(DummyFeature::new("test", FeatureCategory::Other)));

        assert!(registry.has(&FeatureId::new("test")));

        let removed = registry.unregister(&FeatureId::new("test"));
        assert!(removed.is_some());
        assert!(!registry.has(&FeatureId::new("test")));
    }
}
