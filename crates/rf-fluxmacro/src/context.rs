// ============================================================================
// rf-fluxmacro — MacroContext
// ============================================================================
// FM-1: Central execution state passed through all macro steps.
// Accumulates logs, artifacts, QA results, and intermediate data.
// ============================================================================

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

use crate::error::FluxMacroError;

// ─── Enums ───────────────────────────────────────────────────────────────────

/// Target volatility level for audio profile generation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VolatilityLevel {
    Low,
    Medium,
    High,
    Extreme,
}

impl VolatilityLevel {
    /// Parse from string (case-insensitive).
    pub fn from_str_loose(s: &str) -> Result<Self, FluxMacroError> {
        match s.to_lowercase().trim() {
            "low" => Ok(Self::Low),
            "medium" | "med" => Ok(Self::Medium),
            "high" => Ok(Self::High),
            "extreme" | "ultra" => Ok(Self::Extreme),
            other => Err(FluxMacroError::UnknownVolatility(other.to_string())),
        }
    }

    /// Numeric index in 0.0–1.0 range (center of band).
    pub fn index(&self) -> f32 {
        match self {
            Self::Low => 0.15,
            Self::Medium => 0.45,
            Self::High => 0.725,
            Self::Extreme => 0.925,
        }
    }
}

/// Target deployment platform.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Platform {
    Mobile,
    Desktop,
    Cabinet,
    WebGL,
}

impl Platform {
    pub fn from_str_loose(s: &str) -> Result<Self, FluxMacroError> {
        match s.to_lowercase().trim() {
            "mobile" => Ok(Self::Mobile),
            "desktop" => Ok(Self::Desktop),
            "cabinet" => Ok(Self::Cabinet),
            "webgl" | "web" => Ok(Self::WebGL),
            other => Err(FluxMacroError::UnknownPlatform(other.to_string())),
        }
    }

    /// Max voice budget for this platform.
    pub fn voice_budget(&self) -> u32 {
        match self {
            Self::Mobile => 24,
            Self::Desktop => 48,
            Self::Cabinet => 32,
            Self::WebGL => 16,
        }
    }
}

/// Game mechanics that drive ADB generation.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GameMechanic {
    Progressive,
    MysteryScatter,
    PickBonus,
    HoldAndWin,
    Cascades,
    FreeSpins,
    Megaways,
    ClusterPay,
    Gamble,
    WheelBonus,
    Multiplier,
    ExpandingWilds,
    StickyWilds,
    TrailBonus,
    Custom(String),
}

impl GameMechanic {
    pub fn from_str_loose(s: &str) -> Result<Self, FluxMacroError> {
        match s.to_lowercase().replace('-', "_").trim() {
            "progressive" => Ok(Self::Progressive),
            "mystery_scatter" | "mystery" | "scatter" => Ok(Self::MysteryScatter),
            "pick_bonus" | "pick" => Ok(Self::PickBonus),
            "hold_and_win" | "hold_win" | "cash_on_reels" => Ok(Self::HoldAndWin),
            "cascades" | "cascade" | "tumble" | "avalanche" => Ok(Self::Cascades),
            "free_spins" | "freespins" | "fs" => Ok(Self::FreeSpins),
            "megaways" => Ok(Self::Megaways),
            "cluster_pay" | "cluster" => Ok(Self::ClusterPay),
            "gamble" | "double_up" => Ok(Self::Gamble),
            "wheel_bonus" | "wheel" => Ok(Self::WheelBonus),
            "multiplier" | "mult" => Ok(Self::Multiplier),
            "expanding_wilds" | "expanding_wild" => Ok(Self::ExpandingWilds),
            "sticky_wilds" | "sticky_wild" => Ok(Self::StickyWilds),
            "trail_bonus" | "trail" => Ok(Self::TrailBonus),
            other => {
                if other.is_empty() {
                    Err(FluxMacroError::UnknownMechanic(s.to_string()))
                } else {
                    Ok(Self::Custom(other.to_string()))
                }
            }
        }
    }

    /// Canonical identifier used in step registry keys and rule lookups.
    pub fn id(&self) -> &str {
        match self {
            Self::Progressive => "progressive",
            Self::MysteryScatter => "mystery_scatter",
            Self::PickBonus => "pick_bonus",
            Self::HoldAndWin => "hold_and_win",
            Self::Cascades => "cascades",
            Self::FreeSpins => "free_spins",
            Self::Megaways => "megaways",
            Self::ClusterPay => "cluster_pay",
            Self::Gamble => "gamble",
            Self::WheelBonus => "wheel_bonus",
            Self::Multiplier => "multiplier",
            Self::ExpandingWilds => "expanding_wilds",
            Self::StickyWilds => "sticky_wilds",
            Self::TrailBonus => "trail_bonus",
            Self::Custom(id) => id.as_str(),
        }
    }
}

// ─── Log ─────────────────────────────────────────────────────────────────────

/// Severity level for log entries.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LogLevel {
    Debug,
    Info,
    Warning,
    Error,
}

/// A timestamped log entry recorded during macro execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    /// Duration since macro run started.
    pub elapsed: Duration,
    pub level: LogLevel,
    /// Which macro step produced this log.
    pub step: String,
    pub message: String,
}

// ─── QA ──────────────────────────────────────────────────────────────────────

/// Result of a single QA test within a macro run.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QaTestResult {
    pub test_name: String,
    pub passed: bool,
    pub details: String,
    pub duration_ms: u64,
    pub metrics: HashMap<String, f64>,
}

// ─── Intermediate Data Placeholders ──────────────────────────────────────────
// These are populated by Phase 2 steps. Defined here as opaque JSON values
// so the context compiles without step-specific types.

/// Opaque intermediate data produced by a step, stored as JSON value.
pub type IntermediateData = serde_json::Value;

// ─── Report Format ───────────────────────────────────────────────────────────

/// Output report format.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ReportFormat {
    Html,
    Json,
    Markdown,
    All,
}

impl ReportFormat {
    pub fn from_str_loose(s: &str) -> Result<Self, FluxMacroError> {
        match s.to_lowercase().trim() {
            "html" => Ok(Self::Html),
            "json" => Ok(Self::Json),
            "markdown" | "md" => Ok(Self::Markdown),
            "all" => Ok(Self::All),
            other => Err(FluxMacroError::UnknownReportFormat(other.to_string())),
        }
    }
}

// ─── Progress Callback ───────────────────────────────────────────────────────

/// Progress callback signature: receives (progress 0.0–1.0, step_name).
pub type ProgressCallback = Arc<dyn Fn(f32, &str) + Send + Sync>;

// ─── MacroContext ────────────────────────────────────────────────────────────

/// Central execution context passed through all macro steps.
/// Accumulates state, logs, artifacts, and validation results.
pub struct MacroContext {
    // === Input Parameters ===
    pub game_id: String,
    pub volatility: VolatilityLevel,
    pub platforms: Vec<Platform>,
    pub mechanics: Vec<GameMechanic>,
    pub theme: Option<String>,
    pub working_dir: PathBuf,
    pub assets_dir: Option<PathBuf>,
    pub rules_dir: PathBuf,
    pub profiles_dir: PathBuf,

    // === Execution State ===
    pub seed: u64,
    pub dry_run: bool,
    pub verbose: bool,
    pub fail_fast: bool,
    pub parallel_qa: bool,

    // === Cancellation ===
    pub cancel_token: Arc<AtomicBool>,

    // === Progress ===
    pub progress_callback: Option<ProgressCallback>,

    // === Accumulated Results ===
    pub logs: Vec<LogEntry>,
    pub artifacts: HashMap<String, PathBuf>,
    pub qa_results: Vec<QaTestResult>,
    pub warnings: Vec<String>,
    pub errors: Vec<String>,

    // === Intermediate Data (step-to-step) ===
    pub intermediate: HashMap<String, IntermediateData>,

    // === Hashing ===
    pub run_hash: String,
    pub started_at: Instant,

    // === Output ===
    pub report_path: Option<PathBuf>,
    pub report_format: ReportFormat,
}

impl MacroContext {
    /// Create a new context with required parameters.
    pub fn new(game_id: String, working_dir: PathBuf) -> Self {
        let rules_dir = working_dir.join("Rules");
        let profiles_dir = working_dir.join("Profiles");

        Self {
            game_id,
            volatility: VolatilityLevel::Medium,
            platforms: vec![Platform::Desktop],
            mechanics: Vec::new(),
            theme: None,
            working_dir,
            assets_dir: None,
            rules_dir,
            profiles_dir,
            seed: 0,
            dry_run: false,
            verbose: false,
            fail_fast: true,
            parallel_qa: false,
            cancel_token: Arc::new(AtomicBool::new(false)),
            progress_callback: None,
            logs: Vec::new(),
            artifacts: HashMap::new(),
            qa_results: Vec::new(),
            warnings: Vec::new(),
            errors: Vec::new(),
            intermediate: HashMap::new(),
            run_hash: String::new(),
            started_at: Instant::now(),
            report_path: None,
            report_format: ReportFormat::Html,
        }
    }

    /// Log a message with the given level and step name.
    pub fn log(&mut self, level: LogLevel, step: &str, message: &str) {
        let entry = LogEntry {
            elapsed: self.started_at.elapsed(),
            level,
            step: step.to_string(),
            message: message.to_string(),
        };

        if self.verbose || matches!(level, LogLevel::Warning | LogLevel::Error) {
            log::log!(
                match level {
                    LogLevel::Debug => log::Level::Debug,
                    LogLevel::Info => log::Level::Info,
                    LogLevel::Warning => log::Level::Warn,
                    LogLevel::Error => log::Level::Error,
                },
                "[{}] {}",
                step,
                message
            );
        }

        self.logs.push(entry);
    }

    /// Check if execution has been cancelled.
    pub fn is_cancelled(&self) -> bool {
        self.cancel_token.load(Ordering::Relaxed)
    }

    /// Request cancellation.
    pub fn cancel(&self) {
        self.cancel_token.store(true, Ordering::Relaxed);
    }

    /// Report progress to the callback.
    pub fn report_progress(&self, progress: f32, step_name: &str) {
        if let Some(cb) = &self.progress_callback {
            cb(progress.clamp(0.0, 1.0), step_name);
        }
    }

    /// Add a warning message.
    pub fn warn(&mut self, message: impl Into<String>) {
        let msg = message.into();
        self.warnings.push(msg.clone());
        self.log(LogLevel::Warning, "context", &msg);
    }

    /// Add an error message.
    pub fn error(&mut self, message: impl Into<String>) {
        let msg = message.into();
        self.errors.push(msg.clone());
        self.log(LogLevel::Error, "context", &msg);
    }

    /// Store intermediate data from a step for downstream steps.
    pub fn set_intermediate(&mut self, key: &str, value: IntermediateData) {
        self.intermediate.insert(key.to_string(), value);
    }

    /// Retrieve intermediate data.
    pub fn get_intermediate(&self, key: &str) -> Option<&IntermediateData> {
        self.intermediate.get(key)
    }

    /// Overall pass/fail status based on errors and QA results.
    pub fn is_success(&self) -> bool {
        self.errors.is_empty() && self.qa_results.iter().all(|r| r.passed)
    }

    /// Total execution duration.
    pub fn duration(&self) -> Duration {
        self.started_at.elapsed()
    }

    /// Number of QA tests that passed.
    pub fn qa_passed_count(&self) -> usize {
        self.qa_results.iter().filter(|r| r.passed).count()
    }

    /// Number of QA tests that failed.
    pub fn qa_failed_count(&self) -> usize {
        self.qa_results.iter().filter(|r| !r.passed).count()
    }
}

impl std::fmt::Debug for MacroContext {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MacroContext")
            .field("game_id", &self.game_id)
            .field("volatility", &self.volatility)
            .field("seed", &self.seed)
            .field("dry_run", &self.dry_run)
            .field("logs_count", &self.logs.len())
            .field("artifacts_count", &self.artifacts.len())
            .field("qa_results_count", &self.qa_results.len())
            .field("is_success", &self.is_success())
            .finish()
    }
}
