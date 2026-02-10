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

    #[test]
    fn test_all_command_variants() {
        // Verify all 13 EngineCommand variants can be constructed
        let commands: Vec<EngineCommand> = vec![
            EngineCommand::PlaySpin {
                spin_id: "s1".to_string(),
            },
            EngineCommand::Pause,
            EngineCommand::Resume,
            EngineCommand::Stop,
            EngineCommand::Seek {
                timestamp_ms: 1000.0,
            },
            EngineCommand::SetSpeed { speed: 2.0 },
            EngineCommand::SetTimingProfile {
                profile: "turbo".to_string(),
            },
            EngineCommand::GetState,
            EngineCommand::GetSpinList,
            EngineCommand::GetCapabilities,
            EngineCommand::TriggerEvent {
                event_name: "test".to_string(),
                payload: None,
            },
            EngineCommand::SetParameter {
                name: "volume".to_string(),
                value: serde_json::json!(0.8),
            },
            EngineCommand::Custom {
                name: "my_cmd".to_string(),
                data: serde_json::json!({}),
            },
        ];
        assert_eq!(commands.len(), 13);
    }

    #[test]
    fn test_command_name() {
        assert_eq!(
            EngineCommand::PlaySpin {
                spin_id: "x".into()
            }
            .name(),
            "play_spin"
        );
        assert_eq!(EngineCommand::Pause.name(), "pause");
        assert_eq!(EngineCommand::Resume.name(), "resume");
        assert_eq!(EngineCommand::Stop.name(), "stop");
        assert_eq!(EngineCommand::Seek { timestamp_ms: 0.0 }.name(), "seek");
        assert_eq!(EngineCommand::SetSpeed { speed: 1.0 }.name(), "set_speed");
        assert_eq!(
            EngineCommand::SetTimingProfile {
                profile: "n".into()
            }
            .name(),
            "set_timing_profile"
        );
        assert_eq!(EngineCommand::GetState.name(), "get_state");
        assert_eq!(EngineCommand::GetSpinList.name(), "get_spin_list");
        assert_eq!(EngineCommand::GetCapabilities.name(), "get_capabilities");
        assert_eq!(
            EngineCommand::TriggerEvent {
                event_name: "e".into(),
                payload: None
            }
            .name(),
            "trigger_event"
        );
        assert_eq!(
            EngineCommand::SetParameter {
                name: "p".into(),
                value: serde_json::json!(1)
            }
            .name(),
            "set_parameter"
        );
        assert_eq!(
            EngineCommand::Custom {
                name: "c".into(),
                data: serde_json::json!({})
            }
            .name(),
            "custom"
        );
    }

    #[test]
    fn test_command_expects_response() {
        // These expect responses
        assert!(EngineCommand::GetState.expects_response());
        assert!(EngineCommand::GetSpinList.expects_response());
        assert!(EngineCommand::GetCapabilities.expects_response());

        // These do NOT expect responses
        assert!(!EngineCommand::PlaySpin {
            spin_id: "x".into()
        }
        .expects_response());
        assert!(!EngineCommand::Pause.expects_response());
        assert!(!EngineCommand::Resume.expects_response());
        assert!(!EngineCommand::Stop.expects_response());
        assert!(!EngineCommand::Seek { timestamp_ms: 0.0 }.expects_response());
        assert!(!EngineCommand::SetSpeed { speed: 1.0 }.expects_response());
        assert!(!EngineCommand::SetTimingProfile {
            profile: "x".into()
        }
        .expects_response());
        assert!(!EngineCommand::TriggerEvent {
            event_name: "e".into(),
            payload: None
        }
        .expects_response());
        assert!(!EngineCommand::SetParameter {
            name: "n".into(),
            value: serde_json::json!(1)
        }
        .expects_response());
        assert!(!EngineCommand::Custom {
            name: "c".into(),
            data: serde_json::json!({})
        }
        .expects_response());
    }

    #[test]
    fn test_command_response_success() {
        let resp = CommandResponse::success("cmd-1", Some(serde_json::json!({"result": "ok"})));
        assert_eq!(resp.command_id, "cmd-1");
        assert!(resp.success);
        assert!(resp.data.is_some());
        assert_eq!(resp.data.unwrap()["result"], "ok");
        assert!(resp.error.is_none());
        assert!(resp.timestamp_ms > 0.0);
    }

    #[test]
    fn test_command_response_success_no_data() {
        let resp = CommandResponse::success("cmd-2", None);
        assert_eq!(resp.command_id, "cmd-2");
        assert!(resp.success);
        assert!(resp.data.is_none());
        assert!(resp.error.is_none());
    }

    #[test]
    fn test_command_response_error() {
        let resp = CommandResponse::error("cmd-3", "something went wrong");
        assert_eq!(resp.command_id, "cmd-3");
        assert!(!resp.success);
        assert!(resp.data.is_none());
        assert_eq!(resp.error, Some("something went wrong".to_string()));
        assert!(resp.timestamp_ms > 0.0);
    }

    #[test]
    fn test_engine_capabilities_default() {
        let caps = EngineCapabilities::default();
        assert_eq!(caps.engine_name, "Unknown");
        assert_eq!(caps.version, "1.0");
        assert!(!caps.bidirectional);
        assert!(!caps.seekable);
        assert!(!caps.variable_speed);
        assert_eq!(caps.min_speed, 1.0);
        assert_eq!(caps.max_speed, 1.0);
        assert_eq!(caps.supported_commands.len(), 4);
        assert_eq!(caps.timing_profiles.len(), 2);
    }

    #[test]
    fn test_engine_capabilities_fields() {
        let caps = EngineCapabilities {
            engine_name: "TestEngine".to_string(),
            version: "2.5.0".to_string(),
            supported_commands: vec!["play_spin".into(), "pause".into(), "seek".into()],
            timing_profiles: vec!["normal".into(), "turbo".into(), "mobile".into()],
            bidirectional: true,
            seekable: true,
            variable_speed: true,
            min_speed: 0.25,
            max_speed: 4.0,
        };
        assert_eq!(caps.engine_name, "TestEngine");
        assert_eq!(caps.version, "2.5.0");
        assert_eq!(caps.supported_commands.len(), 3);
        assert_eq!(caps.timing_profiles.len(), 3);
        assert!(caps.bidirectional);
        assert!(caps.seekable);
        assert!(caps.variable_speed);
        assert_eq!(caps.min_speed, 0.25);
        assert_eq!(caps.max_speed, 4.0);
    }

    #[test]
    fn test_command_serialization_all() {
        // Verify all 13 variants serialize to valid JSON
        let commands: Vec<EngineCommand> = vec![
            EngineCommand::PlaySpin {
                spin_id: "s1".to_string(),
            },
            EngineCommand::Pause,
            EngineCommand::Resume,
            EngineCommand::Stop,
            EngineCommand::Seek {
                timestamp_ms: 500.0,
            },
            EngineCommand::SetSpeed { speed: 1.5 },
            EngineCommand::SetTimingProfile {
                profile: "turbo".to_string(),
            },
            EngineCommand::GetState,
            EngineCommand::GetSpinList,
            EngineCommand::GetCapabilities,
            EngineCommand::TriggerEvent {
                event_name: "win".to_string(),
                payload: Some(serde_json::json!({"amount": 100})),
            },
            EngineCommand::SetParameter {
                name: "volume".to_string(),
                value: serde_json::json!(0.75),
            },
            EngineCommand::Custom {
                name: "reset".to_string(),
                data: serde_json::json!({"full": true}),
            },
        ];

        for cmd in &commands {
            let json_str = serde_json::to_string(cmd).unwrap();
            assert!(
                !json_str.is_empty(),
                "Serialization produced empty string for {:?}",
                cmd
            );

            // Verify it contains the command tag
            let parsed: serde_json::Value = serde_json::from_str(&json_str).unwrap();
            assert!(
                parsed.get("command").is_some(),
                "Missing 'command' tag in {:?}",
                json_str
            );
            assert_eq!(parsed["command"].as_str().unwrap(), cmd.name());
        }
    }

    #[test]
    fn test_command_serialization_roundtrip() {
        let cmd = EngineCommand::TriggerEvent {
            event_name: "test_event".to_string(),
            payload: Some(serde_json::json!({"key": "value", "num": 42})),
        };
        let json_str = serde_json::to_string(&cmd).unwrap();
        let deserialized: EngineCommand = serde_json::from_str(&json_str).unwrap();
        assert_eq!(deserialized.name(), "trigger_event");
        // Verify payload survived roundtrip
        match deserialized {
            EngineCommand::TriggerEvent {
                event_name,
                payload,
            } => {
                assert_eq!(event_name, "test_event");
                assert_eq!(payload.unwrap()["key"], "value");
            }
            _ => panic!("Wrong variant after deserialization"),
        }
    }

    #[test]
    fn test_command_response_serialization() {
        let resp = CommandResponse::success("id-1", Some(serde_json::json!({"items": [1, 2, 3]})));
        let json_str = serde_json::to_string(&resp).unwrap();
        let deserialized: CommandResponse = serde_json::from_str(&json_str).unwrap();
        assert_eq!(deserialized.command_id, "id-1");
        assert!(deserialized.success);
        assert_eq!(deserialized.data.unwrap()["items"][1], 2);
    }

    #[test]
    fn test_engine_capabilities_serialization() {
        let caps = EngineCapabilities::default();
        let json_str = serde_json::to_string(&caps).unwrap();
        let deserialized: EngineCapabilities = serde_json::from_str(&json_str).unwrap();
        assert_eq!(deserialized.engine_name, caps.engine_name);
        assert_eq!(deserialized.version, caps.version);
        assert_eq!(
            deserialized.supported_commands.len(),
            caps.supported_commands.len()
        );
    }
}
