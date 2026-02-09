//! Feature Chapter trait — the core interface for all features

use rf_stage::StageEvent;

use crate::timing::TimestampGenerator;

use super::{
    ActivationContext, FeatureCategory, FeatureConfig, FeatureId, FeatureResult, FeatureSnapshot,
    FeatureState, SpinContext,
};

/// The core trait that all feature implementations must implement.
///
/// A "chapter" represents a self-contained feature that can be activated,
/// process spins, generate stages, and be deactivated.
///
/// ## Lifecycle
///
/// 1. `configure()` — Set up the feature from GDD config
/// 2. `can_activate()` — Check if feature should trigger
/// 3. `activate()` — Start the feature
/// 4. `process_spin()` — Process each spin within the feature
/// 5. `generate_stages()` — Generate audio/visual stages
/// 6. `deactivate()` — End the feature
///
/// ## Example Implementation
///
/// ```rust,ignore
/// pub struct FreeSpinsChapter {
///     config: FreeSpinsConfig,
///     state: FreeSpinsState,
/// }
///
/// impl FeatureChapter for FreeSpinsChapter {
///     fn id(&self) -> FeatureId {
///         FeatureId::new("free_spins")
///     }
///     // ... other methods
/// }
/// ```
pub trait FeatureChapter: Send + Sync {
    // ═══════════════════════════════════════════════════════════════════════════
    // IDENTITY
    // ═══════════════════════════════════════════════════════════════════════════

    /// Unique feature identifier
    fn id(&self) -> FeatureId;

    /// Human-readable feature name
    fn name(&self) -> &str;

    /// Feature category for grouping
    fn category(&self) -> FeatureCategory;

    /// Feature description
    fn description(&self) -> &str {
        ""
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Configure the feature from GDD config
    fn configure(&mut self, config: &FeatureConfig) -> Result<(), ConfigError>;

    /// Get current configuration as JSON
    fn get_config(&self) -> FeatureConfig {
        FeatureConfig::default()
    }

    /// Reset to default configuration
    fn reset_config(&mut self) {}

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get current feature state
    fn state(&self) -> FeatureState;

    /// Check if feature is currently active
    fn is_active(&self) -> bool {
        self.state().is_active()
    }

    /// Get a snapshot of current state for serialization
    fn snapshot(&self) -> FeatureSnapshot;

    /// Restore state from snapshot
    fn restore(&mut self, snapshot: &FeatureSnapshot) -> Result<(), ConfigError>;

    // ═══════════════════════════════════════════════════════════════════════════
    // ACTIVATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Check if feature can be activated with given context
    fn can_activate(&self, context: &ActivationContext) -> bool;

    /// Activate the feature
    fn activate(&mut self, context: &ActivationContext);

    /// Deactivate the feature
    fn deactivate(&mut self);

    /// Reset feature to initial state
    fn reset(&mut self);

    // ═══════════════════════════════════════════════════════════════════════════
    // PROCESSING
    // ═══════════════════════════════════════════════════════════════════════════

    /// Process a spin within this feature
    fn process_spin(&mut self, context: &mut SpinContext) -> FeatureResult;

    /// Called before each spin (for setup)
    fn pre_spin(&mut self, _context: &SpinContext) {}

    /// Called after each spin (for cleanup)
    fn post_spin(&mut self, _context: &SpinContext, _result: &FeatureResult) {}

    // ═══════════════════════════════════════════════════════════════════════════
    // STAGE GENERATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Generate stage events for current state
    fn generate_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent>;

    /// Generate activation stages (feature enter)
    fn generate_activation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let _ = timing;
        Vec::new()
    }

    /// Generate deactivation stages (feature exit)
    fn generate_deactivation_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent> {
        let _ = timing;
        Vec::new()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTROSPECTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get list of stage types this feature can emit
    fn stage_types(&self) -> Vec<&'static str> {
        Vec::new()
    }

    /// Get feature info for UI display
    fn info(&self) -> FeatureInfo {
        FeatureInfo {
            id: self.id(),
            name: self.name().to_string(),
            category: self.category(),
            description: self.description().to_string(),
            is_active: self.is_active(),
        }
    }
}

/// Configuration error
#[derive(Debug, Clone, thiserror::Error)]
pub enum ConfigError {
    #[error("Missing required parameter: {0}")]
    MissingParam(String),

    #[error("Invalid parameter value: {0}")]
    InvalidValue(String),

    #[error("Invalid state for operation")]
    InvalidState,

    #[error("Restore failed: {0}")]
    RestoreFailed(String),
}

/// Feature information for display
#[derive(Debug, Clone)]
pub struct FeatureInfo {
    pub id: FeatureId,
    pub name: String,
    pub category: FeatureCategory,
    pub description: String,
    pub is_active: bool,
}

/// Boxed feature chapter for dynamic dispatch
pub type BoxedFeatureChapter = Box<dyn FeatureChapter + 'static>;

#[cfg(test)]
mod tests {
    use super::*;

    // Test implementation
    struct TestFeature {
        activated: bool,
    }

    impl FeatureChapter for TestFeature {
        fn id(&self) -> FeatureId {
            FeatureId::new("test")
        }

        fn name(&self) -> &str {
            "Test Feature"
        }

        fn category(&self) -> FeatureCategory {
            FeatureCategory::Other
        }

        fn configure(&mut self, _config: &FeatureConfig) -> Result<(), ConfigError> {
            Ok(())
        }

        fn state(&self) -> FeatureState {
            if self.activated {
                FeatureState::Active
            } else {
                FeatureState::Inactive
            }
        }

        fn snapshot(&self) -> FeatureSnapshot {
            FeatureSnapshot {
                feature_id: "test".to_string(),
                is_active: self.activated,
                current_step: 0,
                total_steps: None,
                multiplier: 1.0,
                accumulated_win: 0.0,
                data: Default::default(),
            }
        }

        fn restore(&mut self, snapshot: &FeatureSnapshot) -> Result<(), ConfigError> {
            self.activated = snapshot.is_active;
            Ok(())
        }

        fn can_activate(&self, _context: &ActivationContext) -> bool {
            !self.activated
        }

        fn activate(&mut self, _context: &ActivationContext) {
            self.activated = true;
        }

        fn deactivate(&mut self) {
            self.activated = false;
        }

        fn reset(&mut self) {
            self.activated = false;
        }

        fn process_spin(&mut self, _context: &mut SpinContext) -> FeatureResult {
            FeatureResult::complete(0.0)
        }

        fn generate_stages(&self, _timing: &mut TimestampGenerator) -> Vec<StageEvent> {
            Vec::new()
        }
    }

    #[test]
    fn test_feature_lifecycle() {
        let mut feature = TestFeature { activated: false };

        assert!(!feature.is_active());
        assert!(feature.can_activate(&ActivationContext::new(3, 1.0)));

        feature.activate(&ActivationContext::new(3, 1.0));
        assert!(feature.is_active());
        assert!(!feature.can_activate(&ActivationContext::new(3, 1.0)));

        feature.deactivate();
        assert!(!feature.is_active());
    }

    #[test]
    fn test_feature_snapshot() {
        let mut feature = TestFeature { activated: true };

        let snapshot = feature.snapshot();
        assert!(snapshot.is_active);

        feature.activated = false;
        feature.restore(&snapshot).unwrap();
        assert!(feature.is_active());
    }
}
