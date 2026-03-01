// ============================================================================
// rf-fluxmacro — MacroStep Trait & Registry
// ============================================================================
// FM-3: Step plugin system. Every macro step implements MacroStep.
// Steps are stateless — all state lives in MacroContext.
// ============================================================================

use std::collections::HashMap;
use std::path::PathBuf;

use crate::context::MacroContext;
use crate::error::FluxMacroError;

// ─── Step Result ─────────────────────────────────────────────────────────────

/// Outcome status of a step execution.
#[derive(Debug, Clone)]
pub enum StepStatus {
    /// Step completed successfully.
    Success,
    /// Step completed with non-blocking warnings.
    SuccessWithWarnings(Vec<String>),
    /// Step was skipped (e.g., dry-run or precondition not applicable).
    Skipped(String),
    /// Step failed with a reason.
    Failed(String),
}

impl StepStatus {
    pub fn is_success(&self) -> bool {
        matches!(self, Self::Success | Self::SuccessWithWarnings(_))
    }

    pub fn is_failed(&self) -> bool {
        matches!(self, Self::Failed(_))
    }
}

/// Result returned by a step after execution.
#[derive(Debug, Clone)]
pub struct StepResult {
    pub status: StepStatus,
    /// Files created by this step (artifact_name → path).
    pub artifacts: Vec<(String, PathBuf)>,
    /// Step-specific metrics (e.g., "voices_max" → 31.0).
    pub metrics: HashMap<String, f64>,
    /// One-line summary for logging.
    pub summary: String,
}

impl StepResult {
    /// Create a successful result with a summary message.
    pub fn success(summary: impl Into<String>) -> Self {
        Self {
            status: StepStatus::Success,
            artifacts: Vec::new(),
            metrics: HashMap::new(),
            summary: summary.into(),
        }
    }

    /// Create a success result with warnings.
    pub fn success_with_warnings(summary: impl Into<String>, warnings: Vec<String>) -> Self {
        Self {
            status: StepStatus::SuccessWithWarnings(warnings),
            artifacts: Vec::new(),
            metrics: HashMap::new(),
            summary: summary.into(),
        }
    }

    /// Create a skipped result.
    pub fn skipped(reason: impl Into<String>) -> Self {
        let reason = reason.into();
        Self {
            status: StepStatus::Skipped(reason.clone()),
            artifacts: Vec::new(),
            metrics: HashMap::new(),
            summary: format!("Skipped: {reason}"),
        }
    }

    /// Create a failed result.
    pub fn failed(reason: impl Into<String>) -> Self {
        let reason = reason.into();
        Self {
            status: StepStatus::Failed(reason.clone()),
            artifacts: Vec::new(),
            metrics: HashMap::new(),
            summary: format!("Failed: {reason}"),
        }
    }

    /// Builder: add an artifact.
    pub fn with_artifact(mut self, name: impl Into<String>, path: PathBuf) -> Self {
        self.artifacts.push((name.into(), path));
        self
    }

    /// Builder: add a metric.
    pub fn with_metric(mut self, name: impl Into<String>, value: f64) -> Self {
        self.metrics.insert(name.into(), value);
        self
    }
}

// ─── MacroStep Trait ─────────────────────────────────────────────────────────

/// Every macro step implements this trait.
/// Steps are stateless — all state lives in MacroContext.
pub trait MacroStep: Send + Sync {
    /// Unique step identifier (e.g., "adb.generate", "qa.run_suite").
    fn name(&self) -> &'static str;

    /// Human-readable description for logs/reports.
    fn description(&self) -> &'static str;

    /// Execute the step, mutating context.
    fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError>;

    /// Validate preconditions before execution.
    /// Called automatically by interpreter before execute().
    fn validate(&self, _ctx: &MacroContext) -> Result<(), FluxMacroError> {
        Ok(())
    }

    /// Estimated duration in milliseconds (for progress reporting).
    fn estimated_duration_ms(&self) -> u64 {
        1000
    }
}

// ─── Step Registry ───────────────────────────────────────────────────────────

/// Registry of all available macro steps.
/// Steps are registered at engine initialization.
pub struct StepRegistry {
    steps: HashMap<String, Box<dyn MacroStep>>,
    insertion_order: Vec<String>,
}

impl StepRegistry {
    /// Create an empty registry (steps are registered by the interpreter).
    pub fn new() -> Self {
        Self {
            steps: HashMap::new(),
            insertion_order: Vec::new(),
        }
    }

    /// Register a step. Overwrites any existing step with the same name.
    pub fn register(&mut self, step: Box<dyn MacroStep>) {
        let name = step.name().to_string();
        if !self.steps.contains_key(&name) {
            self.insertion_order.push(name.clone());
        }
        self.steps.insert(name, step);
    }

    /// Look up a step by name.
    pub fn get(&self, name: &str) -> Option<&dyn MacroStep> {
        self.steps.get(name).map(|b| b.as_ref())
    }

    /// List all registered step names in insertion order.
    pub fn list(&self) -> &[String] {
        &self.insertion_order
    }

    /// Number of registered steps.
    pub fn len(&self) -> usize {
        self.steps.len()
    }

    /// Whether the registry is empty.
    pub fn is_empty(&self) -> bool {
        self.steps.is_empty()
    }

    /// Check if a step exists.
    pub fn contains(&self, name: &str) -> bool {
        self.steps.contains_key(name)
    }
}

impl Default for StepRegistry {
    fn default() -> Self {
        Self::new()
    }
}
