// ============================================================================
// rf-fluxmacro — Macro Interpreter
// ============================================================================
// FM-4: Sequential step executor with fail-fast, cancellation,
// progress reporting, and run hash computation.
// ============================================================================

use std::path::PathBuf;

use crate::context::{LogLevel, MacroContext, VolatilityLevel};
use crate::error::FluxMacroError;
use crate::hash;
use crate::parser::MacroFile;
use crate::steps::{StepRegistry, StepStatus};
use crate::version;

/// Core interpreter that executes macro files step by step.
/// Guarantees deterministic order. No implicit parallelism.
pub struct MacroInterpreter {
    registry: StepRegistry,
}

impl MacroInterpreter {
    /// Create a new interpreter with the given step registry.
    pub fn new(registry: StepRegistry) -> Self {
        Self { registry }
    }

    /// Create an interpreter with an empty registry (steps registered manually).
    pub fn empty() -> Self {
        Self {
            registry: StepRegistry::new(),
        }
    }

    /// Get a reference to the step registry.
    pub fn registry(&self) -> &StepRegistry {
        &self.registry
    }

    /// Get a mutable reference to the step registry.
    pub fn registry_mut(&mut self) -> &mut StepRegistry {
        &mut self.registry
    }

    /// Execute a parsed macro file.
    /// Returns the final context with all accumulated results.
    pub fn run(
        &self,
        macro_file: &MacroFile,
        working_dir: PathBuf,
    ) -> Result<MacroContext, FluxMacroError> {
        // Build context from macro file
        let mut ctx = self.build_context(macro_file, working_dir)?;

        ctx.log(
            LogLevel::Info,
            "interpreter",
            &format!(
                "Starting macro '{}' ({} steps, seed={}, game={})",
                macro_file.name,
                macro_file.steps.len(),
                ctx.seed,
                ctx.game_id,
            ),
        );

        let total_steps = macro_file.steps.len();
        let total_estimated: u64 = macro_file
            .steps
            .iter()
            .filter_map(|name| self.registry.get(name))
            .map(|step| step.estimated_duration_ms())
            .sum();

        let mut elapsed_estimated: u64 = 0;

        for (i, step_name) in macro_file.steps.iter().enumerate() {
            // Check cancellation
            if ctx.is_cancelled() {
                ctx.log(LogLevel::Warning, "interpreter", "Macro execution cancelled");
                return Err(FluxMacroError::Cancelled);
            }

            // Look up step
            let step = self
                .registry
                .get(step_name)
                .ok_or_else(|| FluxMacroError::StepNotFound(step_name.clone()))?;

            ctx.log(
                LogLevel::Info,
                step_name,
                &format!(
                    "[{}/{}] {} — {}",
                    i + 1,
                    total_steps,
                    step_name,
                    step.description()
                ),
            );

            // Report progress
            let progress = if total_estimated > 0 {
                elapsed_estimated as f32 / total_estimated as f32
            } else {
                i as f32 / total_steps as f32
            };
            ctx.report_progress(progress, step_name);

            // Pre-validate
            if let Err(e) = step.validate(&ctx) {
                ctx.log(LogLevel::Error, step_name, &format!("Validation failed: {e}"));
                return Err(FluxMacroError::StepValidationFailed {
                    step: step_name.clone(),
                    reason: format!("{e}"),
                });
            }

            // Execute
            let result = step.execute(&mut ctx)?;

            // Record artifacts
            for (name, path) in &result.artifacts {
                ctx.artifacts.insert(name.clone(), path.clone());
            }

            // Log summary
            ctx.log(LogLevel::Info, step_name, &result.summary);

            // Handle status
            match &result.status {
                StepStatus::Success => {}
                StepStatus::SuccessWithWarnings(warnings) => {
                    for w in warnings {
                        ctx.warn(format!("[{step_name}] {w}"));
                    }
                }
                StepStatus::Skipped(reason) => {
                    ctx.log(
                        LogLevel::Info,
                        step_name,
                        &format!("Step skipped: {reason}"),
                    );
                }
                StepStatus::Failed(reason) => {
                    ctx.error(format!("[{step_name}] {reason}"));

                    if ctx.fail_fast {
                        return Err(FluxMacroError::StepFailed {
                            step: step_name.clone(),
                            reason: reason.clone(),
                        });
                    }
                }
            }

            elapsed_estimated += step.estimated_duration_ms();
        }

        // Final progress
        ctx.report_progress(1.0, "complete");

        // Compute run hash
        ctx.run_hash = hash::compute_run_hash(&ctx, &macro_file.name, &macro_file.steps);

        ctx.log(
            LogLevel::Info,
            "interpreter",
            &format!(
                "Macro '{}' completed in {:.1}s — {} (hash: {})",
                macro_file.name,
                ctx.duration().as_secs_f64(),
                if ctx.is_success() { "PASS" } else { "FAIL" },
                &ctx.run_hash[..16],
            ),
        );

        // Save run history (if not dry-run)
        if !ctx.dry_run {
            match version::save_run_history(&ctx, &macro_file.name, &macro_file.steps, None) {
                Ok(run_dir) => {
                    ctx.log(
                        LogLevel::Info,
                        "interpreter",
                        &format!("Run saved to: {}", run_dir.display()),
                    );
                }
                Err(e) => {
                    ctx.warn(format!("Failed to save run history: {e}"));
                }
            }
        }

        Ok(ctx)
    }

    /// Build a MacroContext from a parsed MacroFile.
    fn build_context(
        &self,
        macro_file: &MacroFile,
        working_dir: PathBuf,
    ) -> Result<MacroContext, FluxMacroError> {
        let mut ctx = MacroContext::new(macro_file.game_id.clone(), working_dir);

        ctx.volatility = macro_file.volatility;
        ctx.platforms = macro_file.platforms.clone();
        ctx.mechanics = macro_file.mechanics.clone();
        ctx.theme = macro_file.theme.clone();
        ctx.fail_fast = macro_file.fail_fast;
        ctx.verbose = macro_file.verbose;
        ctx.parallel_qa = macro_file.parallel_qa;
        ctx.report_format = macro_file.report_format;

        // Seed: use provided or generate from system time
        ctx.seed = macro_file.seed.unwrap_or_else(|| {
            use std::time::SystemTime;
            SystemTime::now()
                .duration_since(SystemTime::UNIX_EPOCH)
                .map(|d| d.as_nanos() as u64)
                .unwrap_or(0)
        });

        // Assets directory
        if let Some(ref assets) = macro_file.assets_dir {
            ctx.assets_dir = Some(ctx.working_dir.join(assets));
        }

        // Report path
        if let Some(ref report) = macro_file.report_path {
            ctx.report_path = Some(ctx.working_dir.join(report));
        }

        Ok(ctx)
    }

    /// Validate a macro file without executing it.
    /// Checks that all referenced steps exist.
    pub fn validate(&self, macro_file: &MacroFile) -> Result<Vec<String>, FluxMacroError> {
        let mut warnings = Vec::new();

        for step_name in &macro_file.steps {
            if !self.registry.contains(step_name) {
                return Err(FluxMacroError::StepNotFound(step_name.clone()));
            }
        }

        if macro_file.mechanics.is_empty() {
            warnings.push("No mechanics specified — ADB generation may be limited".to_string());
        }

        if macro_file.platforms.is_empty() {
            warnings.push("No platforms specified — defaulting to Desktop".to_string());
        }

        // Check for minimum voice budget
        let min_budget = macro_file
            .platforms
            .iter()
            .map(|p| p.voice_budget())
            .min()
            .unwrap_or(48);

        if min_budget < 16 {
            warnings.push(format!(
                "Minimum voice budget is very low: {min_budget} voices"
            ));
        }

        // Check for low volatility with high-action mechanics
        if macro_file.volatility == VolatilityLevel::Low
            && macro_file.mechanics.iter().any(|m| {
                matches!(
                    m,
                    crate::context::GameMechanic::Progressive
                        | crate::context::GameMechanic::Megaways
                )
            })
        {
            warnings.push(
                "Low volatility with Progressive/Megaways may produce suboptimal audio profile"
                    .to_string(),
            );
        }

        Ok(warnings)
    }
}

impl Default for MacroInterpreter {
    fn default() -> Self {
        Self::empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser;
    use crate::steps::{MacroStep, StepResult};

    /// Test step that always succeeds.
    struct EchoStep;

    impl MacroStep for EchoStep {
        fn name(&self) -> &'static str {
            "echo"
        }
        fn description(&self) -> &'static str {
            "Echo test step"
        }
        fn execute(&self, ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
            ctx.log(LogLevel::Info, "echo", "Echo step executed");
            Ok(StepResult::success("Echo completed"))
        }
    }

    /// Test step that always fails.
    struct FailStep;

    impl MacroStep for FailStep {
        fn name(&self) -> &'static str {
            "fail"
        }
        fn description(&self) -> &'static str {
            "Always fails"
        }
        fn execute(&self, _ctx: &mut MacroContext) -> Result<StepResult, FluxMacroError> {
            Ok(StepResult::failed("intentional failure"))
        }
    }

    fn make_interpreter(steps: Vec<Box<dyn MacroStep>>) -> MacroInterpreter {
        let mut registry = StepRegistry::new();
        for step in steps {
            registry.register(step);
        }
        MacroInterpreter::new(registry)
    }

    #[test]
    fn run_single_step() {
        let interp = make_interpreter(vec![Box::new(EchoStep)]);
        let yaml = r#"
macro: test
input:
  game_id: "TestGame"
options:
  seed: 42
steps:
  - echo
"#;
        let macro_file = parser::parse_macro_string(yaml).unwrap();
        let dir = tempfile::tempdir().unwrap();
        let ctx = interp.run(&macro_file, dir.path().to_path_buf()).unwrap();

        assert!(ctx.is_success());
        assert!(!ctx.run_hash.is_empty());
        assert!(ctx.logs.len() >= 2); // start + echo
    }

    #[test]
    fn run_step_not_found() {
        let interp = make_interpreter(vec![Box::new(EchoStep)]);
        let yaml = r#"
macro: test
input:
  game_id: "TestGame"
steps:
  - nonexistent
"#;
        let macro_file = parser::parse_macro_string(yaml).unwrap();
        let dir = tempfile::tempdir().unwrap();
        let result = interp.run(&macro_file, dir.path().to_path_buf());
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), FluxMacroError::StepNotFound(_)));
    }

    #[test]
    fn run_fail_fast() {
        let interp = make_interpreter(vec![Box::new(FailStep), Box::new(EchoStep)]);
        let yaml = r#"
macro: test
input:
  game_id: "TestGame"
options:
  fail_fast: true
steps:
  - fail
  - echo
"#;
        let macro_file = parser::parse_macro_string(yaml).unwrap();
        let dir = tempfile::tempdir().unwrap();
        let result = interp.run(&macro_file, dir.path().to_path_buf());
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), FluxMacroError::StepFailed { .. }));
    }

    #[test]
    fn run_deterministic_hash() {
        let interp = make_interpreter(vec![Box::new(EchoStep)]);
        let yaml = r#"
macro: test
input:
  game_id: "TestGame"
options:
  seed: 42
steps:
  - echo
"#;
        let macro_file = parser::parse_macro_string(yaml).unwrap();
        let dir1 = tempfile::tempdir().unwrap();
        let dir2 = tempfile::tempdir().unwrap();

        let ctx1 = interp.run(&macro_file, dir1.path().to_path_buf()).unwrap();
        let ctx2 = interp.run(&macro_file, dir2.path().to_path_buf()).unwrap();

        assert_eq!(ctx1.run_hash, ctx2.run_hash, "Same seed should produce same hash");
    }

    #[test]
    fn validate_unknown_step() {
        let interp = make_interpreter(vec![Box::new(EchoStep)]);
        let yaml = r#"
macro: test
input:
  game_id: "TestGame"
steps:
  - echo
  - unknown_step
"#;
        let macro_file = parser::parse_macro_string(yaml).unwrap();
        let result = interp.validate(&macro_file);
        assert!(result.is_err());
    }

    #[test]
    fn validate_warns_no_mechanics() {
        let interp = make_interpreter(vec![Box::new(EchoStep)]);
        let yaml = r#"
macro: test
input:
  game_id: "TestGame"
steps:
  - echo
"#;
        let macro_file = parser::parse_macro_string(yaml).unwrap();
        let warnings = interp.validate(&macro_file).unwrap();
        assert!(!warnings.is_empty());
    }

    #[test]
    fn cancellation() {
        let _interp = make_interpreter(vec![Box::new(EchoStep)]);
        let dir = tempfile::tempdir().unwrap();

        // Pre-cancel
        let ctx = MacroContext::new("TestGame".to_string(), dir.path().to_path_buf());
        ctx.cancel();
        assert!(ctx.is_cancelled());
    }
}
