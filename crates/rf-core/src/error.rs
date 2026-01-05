//! Error types for ReelForge
//!
//! Provides comprehensive error handling with:
//! - Categorized error types
//! - Error severity levels
//! - User-friendly error messages
//! - Crash recovery support

use thiserror::Error;
use serde::{Deserialize, Serialize};
use std::fmt;

/// Core error type
#[derive(Error, Debug)]
pub enum RfError {
    #[error("Audio error: {0}")]
    Audio(String),

    #[error("DSP error: {0}")]
    Dsp(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Invalid parameter: {0}")]
    InvalidParam(String),

    #[error("Invalid sample rate: {0}")]
    InvalidSampleRate(u32),

    #[error("Buffer underrun")]
    BufferUnderrun,

    #[error("Buffer overrun")]
    BufferOverrun,

    #[error("Plugin error: {0}")]
    Plugin(String),

    #[error("Serialization error: {0}")]
    Serialization(String),

    #[error("State error: {0}")]
    State(String),
}

/// Result type alias
pub type RfResult<T> = Result<T, RfError>;

// ═══════════════════════════════════════════════════════════════════════════════
// APP ERROR (For UI/Flutter integration)
// ═══════════════════════════════════════════════════════════════════════════════

/// Error severity level
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ErrorSeverity {
    /// Informational message, no action needed
    Info,
    /// Warning - something might be wrong but operation continues
    Warning,
    /// Error - operation failed but app is stable
    Error,
    /// Critical - app stability may be compromised
    Critical,
    /// Fatal - app must close or restart
    Fatal,
}

impl fmt::Display for ErrorSeverity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Info => write!(f, "Info"),
            Self::Warning => write!(f, "Warning"),
            Self::Error => write!(f, "Error"),
            Self::Critical => write!(f, "Critical"),
            Self::Fatal => write!(f, "Fatal"),
        }
    }
}

/// Error category for grouping related errors
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ErrorCategory {
    /// Audio engine errors
    Audio,
    /// File I/O errors
    File,
    /// Project/state errors
    Project,
    /// Plugin errors
    Plugin,
    /// Hardware/device errors
    Hardware,
    /// Network errors
    Network,
    /// User action errors
    User,
    /// Internal/system errors
    System,
}

impl fmt::Display for ErrorCategory {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Audio => write!(f, "Audio"),
            Self::File => write!(f, "File"),
            Self::Project => write!(f, "Project"),
            Self::Plugin => write!(f, "Plugin"),
            Self::Hardware => write!(f, "Hardware"),
            Self::Network => write!(f, "Network"),
            Self::User => write!(f, "User"),
            Self::System => write!(f, "System"),
        }
    }
}

/// Application error for UI display
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppError {
    /// Error code (for logging/debugging)
    pub code: String,
    /// User-friendly title
    pub title: String,
    /// Detailed message for user
    pub message: String,
    /// Technical details (for developers)
    pub details: Option<String>,
    /// Error severity
    pub severity: ErrorSeverity,
    /// Error category
    pub category: ErrorCategory,
    /// Suggested actions
    pub actions: Vec<ErrorAction>,
    /// Is this error recoverable?
    pub recoverable: bool,
    /// Timestamp (milliseconds since epoch)
    pub timestamp: u64,
}

impl AppError {
    /// Create a new app error
    pub fn new(
        code: impl Into<String>,
        title: impl Into<String>,
        message: impl Into<String>,
    ) -> Self {
        Self {
            code: code.into(),
            title: title.into(),
            message: message.into(),
            details: None,
            severity: ErrorSeverity::Error,
            category: ErrorCategory::System,
            actions: Vec::new(),
            recoverable: true,
            timestamp: current_timestamp_ms(),
        }
    }

    /// Builder: set severity
    pub fn with_severity(mut self, severity: ErrorSeverity) -> Self {
        self.severity = severity;
        self
    }

    /// Builder: set category
    pub fn with_category(mut self, category: ErrorCategory) -> Self {
        self.category = category;
        self
    }

    /// Builder: set details
    pub fn with_details(mut self, details: impl Into<String>) -> Self {
        self.details = Some(details.into());
        self
    }

    /// Builder: add action
    pub fn with_action(mut self, action: ErrorAction) -> Self {
        self.actions.push(action);
        self
    }

    /// Builder: set recoverable
    pub fn recoverable(mut self, recoverable: bool) -> Self {
        self.recoverable = recoverable;
        self
    }

    // ---- Common errors ----

    /// Audio device not found
    pub fn audio_device_not_found(device_name: &str) -> Self {
        Self::new(
            "AUDIO_DEVICE_NOT_FOUND",
            "Audio Device Not Found",
            format!("Cannot find audio device: {}", device_name),
        )
        .with_severity(ErrorSeverity::Error)
        .with_category(ErrorCategory::Hardware)
        .with_action(ErrorAction::retry("Retry"))
        .with_action(ErrorAction::open_settings("Audio Settings"))
    }

    /// Audio device error
    pub fn audio_device_error(message: &str) -> Self {
        Self::new(
            "AUDIO_DEVICE_ERROR",
            "Audio Device Error",
            message,
        )
        .with_severity(ErrorSeverity::Error)
        .with_category(ErrorCategory::Audio)
        .with_action(ErrorAction::retry("Retry"))
    }

    /// Buffer underrun
    pub fn buffer_underrun() -> Self {
        Self::new(
            "BUFFER_UNDERRUN",
            "Audio Buffer Underrun",
            "Audio buffer underrun detected. Try increasing buffer size.",
        )
        .with_severity(ErrorSeverity::Warning)
        .with_category(ErrorCategory::Audio)
        .with_action(ErrorAction::open_settings("Audio Settings"))
    }

    /// File not found
    pub fn file_not_found(path: &str) -> Self {
        Self::new(
            "FILE_NOT_FOUND",
            "File Not Found",
            format!("Cannot find file: {}", path),
        )
        .with_severity(ErrorSeverity::Error)
        .with_category(ErrorCategory::File)
        .with_action(ErrorAction::browse("Locate File"))
    }

    /// File read error
    pub fn file_read_error(path: &str, error: &str) -> Self {
        Self::new(
            "FILE_READ_ERROR",
            "Cannot Read File",
            format!("Error reading {}: {}", path, error),
        )
        .with_severity(ErrorSeverity::Error)
        .with_category(ErrorCategory::File)
        .with_details(error.to_string())
    }

    /// File write error
    pub fn file_write_error(path: &str, error: &str) -> Self {
        Self::new(
            "FILE_WRITE_ERROR",
            "Cannot Save File",
            format!("Error saving {}: {}", path, error),
        )
        .with_severity(ErrorSeverity::Error)
        .with_category(ErrorCategory::File)
        .with_details(error.to_string())
        .with_action(ErrorAction::retry("Retry"))
        .with_action(ErrorAction::browse("Save As..."))
    }

    /// Project load error
    pub fn project_load_error(name: &str, error: &str) -> Self {
        Self::new(
            "PROJECT_LOAD_ERROR",
            "Cannot Open Project",
            format!("Error loading project '{}': {}", name, error),
        )
        .with_severity(ErrorSeverity::Error)
        .with_category(ErrorCategory::Project)
        .with_details(error.to_string())
    }

    /// Project corrupted
    pub fn project_corrupted(name: &str) -> Self {
        Self::new(
            "PROJECT_CORRUPTED",
            "Project File Corrupted",
            format!("Project '{}' appears to be corrupted.", name),
        )
        .with_severity(ErrorSeverity::Critical)
        .with_category(ErrorCategory::Project)
        .with_action(ErrorAction::custom("recover", "Recover from Backup"))
        .recoverable(false)
    }

    /// Plugin load error
    pub fn plugin_load_error(plugin_name: &str, error: &str) -> Self {
        Self::new(
            "PLUGIN_LOAD_ERROR",
            "Plugin Load Failed",
            format!("Cannot load plugin '{}': {}", plugin_name, error),
        )
        .with_severity(ErrorSeverity::Warning)
        .with_category(ErrorCategory::Plugin)
        .with_details(error.to_string())
        .with_action(ErrorAction::custom("skip", "Skip Plugin"))
        .with_action(ErrorAction::custom("rescan", "Rescan Plugins"))
    }

    /// Plugin crash
    pub fn plugin_crashed(plugin_name: &str) -> Self {
        Self::new(
            "PLUGIN_CRASHED",
            "Plugin Crashed",
            format!("Plugin '{}' has crashed and was disabled.", plugin_name),
        )
        .with_severity(ErrorSeverity::Error)
        .with_category(ErrorCategory::Plugin)
        .with_action(ErrorAction::custom("reload", "Reload Plugin"))
        .with_action(ErrorAction::custom("remove", "Remove Plugin"))
    }

    /// Out of memory
    pub fn out_of_memory() -> Self {
        Self::new(
            "OUT_OF_MEMORY",
            "Out of Memory",
            "The application has run out of memory. Try closing some plugins or projects.",
        )
        .with_severity(ErrorSeverity::Critical)
        .with_category(ErrorCategory::System)
        .recoverable(false)
    }

    /// Crash recovery available
    pub fn crash_recovery_available(project_name: &str) -> Self {
        Self::new(
            "CRASH_RECOVERY",
            "Recover Previous Session?",
            format!(
                "A previous session for '{}' was not properly closed. Would you like to recover it?",
                project_name
            ),
        )
        .with_severity(ErrorSeverity::Info)
        .with_category(ErrorCategory::Project)
        .with_action(ErrorAction::custom("recover", "Recover Session"))
        .with_action(ErrorAction::custom("discard", "Start Fresh"))
    }

    /// Generic error from RfError
    pub fn from_rf_error(error: &RfError) -> Self {
        let (code, category) = match error {
            RfError::Audio(_) => ("AUDIO_ERROR", ErrorCategory::Audio),
            RfError::Dsp(_) => ("DSP_ERROR", ErrorCategory::Audio),
            RfError::Io(_) => ("IO_ERROR", ErrorCategory::File),
            RfError::InvalidParam(_) => ("INVALID_PARAM", ErrorCategory::User),
            RfError::InvalidSampleRate(_) => ("INVALID_SAMPLE_RATE", ErrorCategory::Audio),
            RfError::BufferUnderrun => ("BUFFER_UNDERRUN", ErrorCategory::Audio),
            RfError::BufferOverrun => ("BUFFER_OVERRUN", ErrorCategory::Audio),
            RfError::Plugin(_) => ("PLUGIN_ERROR", ErrorCategory::Plugin),
            RfError::Serialization(_) => ("SERIALIZATION_ERROR", ErrorCategory::Project),
            RfError::State(_) => ("STATE_ERROR", ErrorCategory::System),
        };

        Self::new(code, "Error", error.to_string())
            .with_category(category)
    }
}

impl From<RfError> for AppError {
    fn from(error: RfError) -> Self {
        Self::from_rf_error(&error)
    }
}

/// User action for error dialog
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorAction {
    /// Action identifier
    pub id: String,
    /// Display label
    pub label: String,
    /// Action type
    pub action_type: ErrorActionType,
}

impl ErrorAction {
    /// Create custom action
    pub fn custom(id: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            label: label.into(),
            action_type: ErrorActionType::Custom,
        }
    }

    /// Create retry action
    pub fn retry(label: impl Into<String>) -> Self {
        Self {
            id: "retry".to_string(),
            label: label.into(),
            action_type: ErrorActionType::Retry,
        }
    }

    /// Create dismiss action
    pub fn dismiss(label: impl Into<String>) -> Self {
        Self {
            id: "dismiss".to_string(),
            label: label.into(),
            action_type: ErrorActionType::Dismiss,
        }
    }

    /// Create settings action
    pub fn open_settings(label: impl Into<String>) -> Self {
        Self {
            id: "settings".to_string(),
            label: label.into(),
            action_type: ErrorActionType::OpenSettings,
        }
    }

    /// Create browse action
    pub fn browse(label: impl Into<String>) -> Self {
        Self {
            id: "browse".to_string(),
            label: label.into(),
            action_type: ErrorActionType::Browse,
        }
    }
}

/// Error action type
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ErrorActionType {
    /// Retry the failed operation
    Retry,
    /// Dismiss the error
    Dismiss,
    /// Open settings
    OpenSettings,
    /// Browse for file
    Browse,
    /// Custom action
    Custom,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CRASH RECOVERY
// ═══════════════════════════════════════════════════════════════════════════════

/// Crash recovery state file
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CrashRecoveryInfo {
    /// Project name
    pub project_name: String,
    /// Last known project path
    pub project_path: Option<String>,
    /// Autosave path if available
    pub autosave_path: Option<String>,
    /// Timestamp when session started
    pub session_start: u64,
    /// Last activity timestamp
    pub last_activity: u64,
    /// Whether session ended cleanly
    pub clean_exit: bool,
    /// Error message if crashed
    pub crash_message: Option<String>,
}

impl CrashRecoveryInfo {
    /// Create new recovery info
    pub fn new(project_name: impl Into<String>) -> Self {
        let now = current_timestamp_ms();
        Self {
            project_name: project_name.into(),
            project_path: None,
            autosave_path: None,
            session_start: now,
            last_activity: now,
            clean_exit: false,
            crash_message: None,
        }
    }

    /// Update last activity
    pub fn touch(&mut self) {
        self.last_activity = current_timestamp_ms();
    }

    /// Mark clean exit
    pub fn mark_clean_exit(&mut self) {
        self.clean_exit = true;
    }

    /// Check if recovery is needed
    pub fn needs_recovery(&self) -> bool {
        !self.clean_exit && self.autosave_path.is_some()
    }
}

/// Get current timestamp in milliseconds
fn current_timestamp_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
