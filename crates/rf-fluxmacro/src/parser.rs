// ============================================================================
// rf-fluxmacro — YAML Parser
// ============================================================================
// FM-2: Parses .ffmacro.yaml files into typed MacroFile structs.
// ============================================================================

use std::path::Path;

use serde::Deserialize;

use crate::context::{GameMechanic, Platform, ReportFormat, VolatilityLevel};
use crate::error::FluxMacroError;
use crate::security;

// ─── Raw YAML Structures ────────────────────────────────────────────────────

/// Top-level .ffmacro.yaml file structure.
#[derive(Debug, Deserialize)]
pub struct MacroFileRaw {
    #[serde(rename = "macro")]
    pub name: String,
    pub version: Option<String>,
    pub input: MacroInputRaw,
    pub options: Option<MacroOptionsRaw>,
    pub steps: Vec<String>,
    pub output: Option<MacroOutputRaw>,
}

#[derive(Debug, Deserialize)]
pub struct MacroInputRaw {
    pub game_id: Option<String>,
    pub volatility: Option<String>,
    pub mechanics: Option<Vec<String>>,
    pub theme: Option<String>,
    pub platforms: Option<Vec<String>>,
    pub assets_dir: Option<String>,
    pub gdd_path: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct MacroOptionsRaw {
    pub seed: Option<u64>,
    pub fail_fast: Option<bool>,
    pub verbose: Option<bool>,
    pub parallel_qa: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct MacroOutputRaw {
    pub report: Option<String>,
    pub format: Option<String>,
}

// ─── Parsed (Validated) Structures ───────────────────────────────────────────

/// Fully validated macro file ready for execution.
#[derive(Debug)]
pub struct MacroFile {
    pub name: String,
    pub version: Option<String>,
    pub game_id: String,
    pub volatility: VolatilityLevel,
    pub mechanics: Vec<GameMechanic>,
    pub theme: Option<String>,
    pub platforms: Vec<Platform>,
    pub assets_dir: Option<String>,
    pub gdd_path: Option<String>,
    pub seed: Option<u64>,
    pub fail_fast: bool,
    pub verbose: bool,
    pub parallel_qa: bool,
    pub steps: Vec<String>,
    pub report_path: Option<String>,
    pub report_format: ReportFormat,
}

// ─── Parser ──────────────────────────────────────────────────────────────────

/// Parse a .ffmacro.yaml file from disk.
pub fn parse_macro_file(path: &Path) -> Result<MacroFile, FluxMacroError> {
    let content = std::fs::read_to_string(path)
        .map_err(|e| FluxMacroError::FileRead(path.to_path_buf(), e))?;
    parse_macro_string(&content)
}

/// Parse a .ffmacro.yaml from a string (useful for testing).
pub fn parse_macro_string(content: &str) -> Result<MacroFile, FluxMacroError> {
    let raw: MacroFileRaw = serde_yaml::from_str(content)?;
    validate_and_convert(raw)
}

fn validate_and_convert(raw: MacroFileRaw) -> Result<MacroFile, FluxMacroError> {
    // Macro name is required
    if raw.name.is_empty() {
        return Err(FluxMacroError::ParseError(
            "macro name cannot be empty".to_string(),
        ));
    }

    // Game ID — required
    let game_id = raw
        .input
        .game_id
        .ok_or_else(|| FluxMacroError::ParseError("input.game_id is required".to_string()))?;

    // Validate game ID format
    security::validate_game_id(&game_id)?;

    // Volatility — default to medium
    let volatility = match &raw.input.volatility {
        Some(v) => VolatilityLevel::from_str_loose(v)?,
        None => VolatilityLevel::Medium,
    };

    // Mechanics — parse each
    let mechanics = match raw.input.mechanics {
        Some(list) => list
            .iter()
            .map(|s| GameMechanic::from_str_loose(s))
            .collect::<Result<Vec<_>, _>>()?,
        None => Vec::new(),
    };

    // Platforms — default to desktop
    let platforms = match raw.input.platforms {
        Some(list) => list
            .iter()
            .map(|s| Platform::from_str_loose(s))
            .collect::<Result<Vec<_>, _>>()?,
        None => vec![Platform::Desktop],
    };

    // Steps — must not be empty
    if raw.steps.is_empty() {
        return Err(FluxMacroError::ParseError(
            "steps list cannot be empty".to_string(),
        ));
    }

    // Options
    let options = raw.options.unwrap_or(MacroOptionsRaw {
        seed: None,
        fail_fast: None,
        verbose: None,
        parallel_qa: None,
    });

    // Output
    let output = raw.output.unwrap_or(MacroOutputRaw {
        report: None,
        format: None,
    });

    let report_format = match &output.format {
        Some(f) => ReportFormat::from_str_loose(f)?,
        None => ReportFormat::Html,
    };

    Ok(MacroFile {
        name: raw.name,
        version: raw.version,
        game_id,
        volatility,
        mechanics,
        theme: raw.input.theme,
        platforms,
        assets_dir: raw.input.assets_dir,
        gdd_path: raw.input.gdd_path,
        seed: options.seed,
        fail_fast: options.fail_fast.unwrap_or(true),
        verbose: options.verbose.unwrap_or(false),
        parallel_qa: options.parallel_qa.unwrap_or(false),
        steps: raw.steps,
        report_path: output.report,
        report_format,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID_YAML: &str = r#"
macro: build_release
version: "1.0"

input:
  game_id: "GoldenPantheon"
  volatility: "high"
  mechanics:
    - "hold_and_win"
    - "progressive"
    - "free_spins"
  theme: "mythological"
  platforms:
    - "mobile"
    - "desktop"

options:
  seed: 42
  fail_fast: true
  verbose: false
  parallel_qa: false

steps:
  - adb.generate
  - naming.validate
  - volatility.profile.generate
  - manifest.build
  - qa.run_suite
  - pack.release

output:
  report: "Reports/GoldenPantheon_RC.html"
  format: "all"
"#;

    #[test]
    fn parse_valid_macro() {
        let result = parse_macro_string(VALID_YAML);
        assert!(result.is_ok(), "Parse failed: {:?}", result.err());

        let macro_file = result.unwrap();
        assert_eq!(macro_file.name, "build_release");
        assert_eq!(macro_file.game_id, "GoldenPantheon");
        assert_eq!(macro_file.volatility, VolatilityLevel::High);
        assert_eq!(macro_file.mechanics.len(), 3);
        assert_eq!(macro_file.platforms.len(), 2);
        assert_eq!(macro_file.steps.len(), 6);
        assert_eq!(macro_file.seed, Some(42));
        assert!(macro_file.fail_fast);
        assert!(!macro_file.verbose);
        assert_eq!(macro_file.report_format, ReportFormat::All);
    }

    #[test]
    fn parse_minimal_macro() {
        let yaml = r#"
macro: quick_check
input:
  game_id: "TestGame"
steps:
  - naming.validate
"#;
        let result = parse_macro_string(yaml);
        assert!(result.is_ok());

        let m = result.unwrap();
        assert_eq!(m.name, "quick_check");
        assert_eq!(m.volatility, VolatilityLevel::Medium); // default
        assert_eq!(m.platforms, vec![Platform::Desktop]); // default
        assert!(m.mechanics.is_empty());
        assert!(m.seed.is_none());
    }

    #[test]
    fn parse_missing_game_id() {
        let yaml = r#"
macro: test
input: {}
steps:
  - naming.validate
"#;
        let result = parse_macro_string(yaml);
        assert!(result.is_err());
        let err = format!("{}", result.unwrap_err());
        assert!(
            err.contains("game_id"),
            "Error should mention game_id: {err}"
        );
    }

    #[test]
    fn parse_empty_steps() {
        let yaml = r#"
macro: test
input:
  game_id: "TestGame"
steps: []
"#;
        let result = parse_macro_string(yaml);
        assert!(result.is_err());
        let err = format!("{}", result.unwrap_err());
        assert!(err.contains("empty"), "Error should mention empty: {err}");
    }

    #[test]
    fn parse_invalid_volatility() {
        let yaml = r#"
macro: test
input:
  game_id: "TestGame"
  volatility: "nuclear"
steps:
  - naming.validate
"#;
        let result = parse_macro_string(yaml);
        assert!(result.is_err());
    }

    #[test]
    fn parse_invalid_game_id() {
        let yaml = r#"
macro: test
input:
  game_id: "has spaces bad"
steps:
  - naming.validate
"#;
        let result = parse_macro_string(yaml);
        assert!(result.is_err());
    }

    #[test]
    fn parse_all_volatilities() {
        for (label, expected) in [
            ("low", VolatilityLevel::Low),
            ("medium", VolatilityLevel::Medium),
            ("high", VolatilityLevel::High),
            ("extreme", VolatilityLevel::Extreme),
        ] {
            let yaml = format!(
                r#"
macro: test
input:
  game_id: "T"
  volatility: "{label}"
steps:
  - naming.validate
"#
            );
            let m = parse_macro_string(&yaml).unwrap();
            assert_eq!(m.volatility, expected, "Failed for {label}");
        }
    }

    #[test]
    fn parse_all_platforms() {
        let yaml = r#"
macro: test
input:
  game_id: "T"
  platforms:
    - "mobile"
    - "desktop"
    - "cabinet"
    - "webgl"
steps:
  - naming.validate
"#;
        let m = parse_macro_string(yaml).unwrap();
        assert_eq!(m.platforms.len(), 4);
    }

    #[test]
    fn parse_custom_mechanic() {
        let yaml = r#"
macro: test
input:
  game_id: "T"
  mechanics:
    - "custom_mechanic_xyz"
steps:
  - naming.validate
"#;
        let m = parse_macro_string(yaml).unwrap();
        assert_eq!(m.mechanics.len(), 1);
        assert!(matches!(&m.mechanics[0], GameMechanic::Custom(s) if s == "custom_mechanic_xyz"));
    }
}
