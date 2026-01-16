//! Engine commands — FluxForge → Engine communication

use serde::{Deserialize, Serialize};

/// Commands that FluxForge can send to the engine
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "command", rename_all = "snake_case")]
pub enum EngineCommand {
    /// Request to play a specific spin by ID
    PlaySpin {
        /// Spin ID to play
        spin_id: String,
    },

    /// Pause the current playback
    Pause,

    /// Resume playback
    Resume,

    /// Stop playback
    Stop,

    /// Seek to a specific timestamp
    Seek {
        /// Target timestamp in milliseconds
        timestamp_ms: f64,
    },

    /// Set playback speed
    SetSpeed {
        /// Speed multiplier (1.0 = normal, 2.0 = 2x, 0.5 = half)
        speed: f64,
    },

    /// Set timing profile
    SetTimingProfile {
        /// Profile name (normal, turbo, mobile, etc.)
        profile: String,
    },

    /// Request current engine state
    GetState,

    /// Request available spins list
    GetSpinList,

    /// Request engine capabilities
    GetCapabilities,

    /// Trigger a specific event (for testing)
    TriggerEvent {
        /// Event name
        event_name: String,
        /// Event payload
        payload: Option<serde_json::Value>,
    },

    /// Set parameter value
    SetParameter {
        /// Parameter name
        name: String,
        /// Parameter value
        value: serde_json::Value,
    },

    /// Custom command
    Custom {
        /// Command name
        name: String,
        /// Command data
        data: serde_json::Value,
    },
}

impl EngineCommand {
    /// Get command name
    pub fn name(&self) -> &'static str {
        match self {
            Self::PlaySpin { .. } => "play_spin",
            Self::Pause => "pause",
            Self::Resume => "resume",
            Self::Stop => "stop",
            Self::Seek { .. } => "seek",
            Self::SetSpeed { .. } => "set_speed",
            Self::SetTimingProfile { .. } => "set_timing_profile",
            Self::GetState => "get_state",
            Self::GetSpinList => "get_spin_list",
            Self::GetCapabilities => "get_capabilities",
            Self::TriggerEvent { .. } => "trigger_event",
            Self::SetParameter { .. } => "set_parameter",
            Self::Custom { .. } => "custom",
        }
    }

    /// Check if command expects a response
    pub fn expects_response(&self) -> bool {
        matches!(
            self,
            Self::GetState | Self::GetSpinList | Self::GetCapabilities
        )
    }
}

/// Command response from engine
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandResponse {
    /// Original command ID
    pub command_id: String,

    /// Success flag
    pub success: bool,

    /// Response data
    pub data: Option<serde_json::Value>,

    /// Error message if failed
    pub error: Option<String>,

    /// Response timestamp
    pub timestamp_ms: f64,
}

impl CommandResponse {
    /// Create a success response
    pub fn success(command_id: &str, data: Option<serde_json::Value>) -> Self {
        Self {
            command_id: command_id.to_string(),
            success: true,
            data,
            error: None,
            timestamp_ms: current_time_ms(),
        }
    }

    /// Create an error response
    pub fn error(command_id: &str, message: &str) -> Self {
        Self {
            command_id: command_id.to_string(),
            success: false,
            data: None,
            error: Some(message.to_string()),
            timestamp_ms: current_time_ms(),
        }
    }
}

/// Engine capabilities reported by the engine
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngineCapabilities {
    /// Engine name
    pub engine_name: String,

    /// Engine version
    pub version: String,

    /// Supported commands
    pub supported_commands: Vec<String>,

    /// Supported timing profiles
    pub timing_profiles: Vec<String>,

    /// Supports bidirectional control
    pub bidirectional: bool,

    /// Supports seeking
    pub seekable: bool,

    /// Supports variable speed
    pub variable_speed: bool,

    /// Minimum supported speed
    pub min_speed: f64,

    /// Maximum supported speed
    pub max_speed: f64,
}

impl Default for EngineCapabilities {
    fn default() -> Self {
        Self {
            engine_name: "Unknown".to_string(),
            version: "1.0".to_string(),
            supported_commands: vec![
                "play_spin".to_string(),
                "pause".to_string(),
                "resume".to_string(),
                "stop".to_string(),
            ],
            timing_profiles: vec!["normal".to_string(), "turbo".to_string()],
            bidirectional: false,
            seekable: false,
            variable_speed: false,
            min_speed: 1.0,
            max_speed: 1.0,
        }
    }
}

/// Get current time in milliseconds
fn current_time_ms() -> f64 {
    use std::time::{SystemTime, UNIX_EPOCH};

    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as f64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_command_serialization() {
        let cmd = EngineCommand::PlaySpin {
            spin_id: "spin_123".to_string(),
        };

        let json = serde_json::to_string(&cmd).unwrap();
        assert!(json.contains("play_spin"));
        assert!(json.contains("spin_123"));
    }

    #[test]
    fn test_command_response() {
        let response = CommandResponse::success("cmd_1", Some(serde_json::json!({"status": "ok"})));

        assert!(response.success);
        assert!(response.error.is_none());
    }

    #[test]
    fn test_engine_capabilities() {
        let caps = EngineCapabilities::default();
        assert!(!caps.seekable);
        assert!(caps.supported_commands.contains(&"pause".to_string()));
    }
}
