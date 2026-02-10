//! Protocol definitions for engine communication

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Connection protocol
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Protocol {
    /// WebSocket connection
    WebSocket {
        /// WebSocket URL (ws:// or wss://)
        url: String,
    },
    /// Raw TCP connection
    Tcp {
        /// Host address
        host: String,
        /// Port number
        port: u16,
    },
}

/// Connection configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectionConfig {
    /// Protocol to use
    pub protocol: Protocol,

    /// Adapter ID for event translation
    pub adapter_id: String,

    /// Authentication token (if required)
    pub auth_token: Option<String>,

    /// Connection timeout in milliseconds
    pub timeout_ms: u32,
}

impl Default for ConnectionConfig {
    fn default() -> Self {
        Self {
            protocol: Protocol::WebSocket {
                url: "ws://localhost:8080".to_string(),
            },
            adapter_id: "generic".to_string(),
            auth_token: None,
            timeout_ms: 5000,
        }
    }
}

/// Connection state
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ConnectionState {
    /// Not connected
    Disconnected,
    /// Connection in progress
    Connecting,
    /// Connected and ready
    Connected,
    /// Disconnection in progress
    Disconnecting,
    /// Connection lost, waiting to reconnect
    Reconnecting,
    /// Connection error
    Error,
}

/// Raw message from engine
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngineMessage {
    /// Message type/event name
    pub message_type: String,

    /// Raw JSON payload
    pub payload: Value,

    /// Timestamp when received
    pub received_at_ms: f64,

    /// Sequence number (if provided)
    pub sequence: Option<u64>,
}

impl EngineMessage {
    /// Create a new engine message
    pub fn new(message_type: &str, payload: Value) -> Self {
        use std::time::{SystemTime, UNIX_EPOCH};

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as f64;

        Self {
            message_type: message_type.to_string(),
            payload,
            received_at_ms: now,
            sequence: None,
        }
    }

    /// Create with sequence number
    pub fn with_sequence(mut self, seq: u64) -> Self {
        self.sequence = Some(seq);
        self
    }
}

/// Protocol frame types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrameType {
    /// Stage event
    StageEvent,
    /// Engine state update
    StateUpdate,
    /// Command acknowledgement
    CommandAck,
    /// Error message
    Error,
    /// Heartbeat/ping
    Heartbeat,
    /// Authentication
    Auth,
    /// Custom message
    Custom,
}

/// Wire format for protocol messages
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProtocolFrame {
    /// Frame type
    #[serde(rename = "type")]
    pub frame_type: String,

    /// Frame ID for request/response matching
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,

    /// Frame payload
    pub data: Value,

    /// Timestamp
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timestamp: Option<f64>,
}

impl ProtocolFrame {
    /// Create a stage event frame
    pub fn stage_event(data: Value) -> Self {
        Self {
            frame_type: "stage_event".to_string(),
            id: None,
            data,
            timestamp: Some(current_time_ms()),
        }
    }

    /// Create a command frame
    pub fn command(id: &str, data: Value) -> Self {
        Self {
            frame_type: "command".to_string(),
            id: Some(id.to_string()),
            data,
            timestamp: Some(current_time_ms()),
        }
    }

    /// Create an auth frame
    pub fn auth(token: &str) -> Self {
        Self {
            frame_type: "auth".to_string(),
            id: None,
            data: serde_json::json!({ "token": token }),
            timestamp: Some(current_time_ms()),
        }
    }

    /// Create a heartbeat frame
    pub fn heartbeat() -> Self {
        Self {
            frame_type: "heartbeat".to_string(),
            id: None,
            data: Value::Null,
            timestamp: Some(current_time_ms()),
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
    use serde_json::json;

    #[test]
    fn test_protocol_frame_serialization() {
        let frame = ProtocolFrame::stage_event(json!({
            "stage": "spin_start",
            "timestamp": 1000.0
        }));

        let json = serde_json::to_string(&frame).unwrap();
        assert!(json.contains("stage_event"));
    }

    #[test]
    fn test_connection_config_default() {
        let config = ConnectionConfig::default();
        assert_eq!(config.adapter_id, "generic");
        assert_eq!(config.timeout_ms, 5000);
    }

    #[test]
    fn test_connection_state_disconnected_default() {
        // ConnectionConfig default uses Disconnected state implicitly;
        // verify the enum variant exists and can be compared
        let state = ConnectionState::Disconnected;
        assert_eq!(state, ConnectionState::Disconnected);
        assert_ne!(state, ConnectionState::Connected);
        assert_ne!(state, ConnectionState::Connecting);
        assert_ne!(state, ConnectionState::Reconnecting);
        assert_ne!(state, ConnectionState::Error);
    }

    #[test]
    fn test_protocol_websocket_url() {
        let proto = Protocol::WebSocket {
            url: "ws://example.com:9090/game".to_string(),
        };
        match proto {
            Protocol::WebSocket { url } => {
                assert_eq!(url, "ws://example.com:9090/game");
            }
            _ => panic!("Expected WebSocket"),
        }
    }

    #[test]
    fn test_protocol_tcp_host_port() {
        let proto = Protocol::Tcp {
            host: "192.168.1.100".to_string(),
            port: 7777,
        };
        match proto {
            Protocol::Tcp { host, port } => {
                assert_eq!(host, "192.168.1.100");
                assert_eq!(port, 7777);
            }
            _ => panic!("Expected Tcp"),
        }
    }

    #[test]
    fn test_engine_message_fields() {
        let msg = EngineMessage::new("spin_result", json!({"win": 500}));
        assert_eq!(msg.message_type, "spin_result");
        assert_eq!(msg.payload["win"], 500);
        assert!(msg.received_at_ms > 0.0);
        assert!(msg.sequence.is_none());
    }

    #[test]
    fn test_engine_message_with_sequence() {
        let msg = EngineMessage::new("test", json!(null)).with_sequence(42);
        assert_eq!(msg.sequence, Some(42));
    }

    #[test]
    fn test_protocol_frame_stage_event() {
        let frame = ProtocolFrame::stage_event(json!({"stage": "SPIN_START"}));
        assert_eq!(frame.frame_type, "stage_event");
        assert!(frame.id.is_none());
        assert_eq!(frame.data["stage"], "SPIN_START");
        assert!(frame.timestamp.is_some());
    }

    #[test]
    fn test_protocol_frame_command() {
        let frame = ProtocolFrame::command("cmd-42", json!({"action": "play"}));
        assert_eq!(frame.frame_type, "command");
        assert_eq!(frame.id, Some("cmd-42".to_string()));
        assert_eq!(frame.data["action"], "play");
        assert!(frame.timestamp.is_some());
    }

    #[test]
    fn test_protocol_frame_auth() {
        let frame = ProtocolFrame::auth("my-secret-token");
        assert_eq!(frame.frame_type, "auth");
        assert!(frame.id.is_none());
        assert_eq!(frame.data["token"], "my-secret-token");
        assert!(frame.timestamp.is_some());
    }

    #[test]
    fn test_protocol_frame_heartbeat() {
        let frame = ProtocolFrame::heartbeat();
        assert_eq!(frame.frame_type, "heartbeat");
        assert!(frame.id.is_none());
        assert_eq!(frame.data, Value::Null);
        assert!(frame.timestamp.is_some());
    }

    #[test]
    fn test_connection_config_custom() {
        let config = ConnectionConfig {
            protocol: Protocol::Tcp {
                host: "10.0.0.1".to_string(),
                port: 3000,
            },
            adapter_id: "custom-adapter".to_string(),
            auth_token: Some("bearer-xyz".to_string()),
            timeout_ms: 10000,
        };
        assert_eq!(config.adapter_id, "custom-adapter");
        assert_eq!(config.timeout_ms, 10000);
        assert_eq!(config.auth_token, Some("bearer-xyz".to_string()));
        match config.protocol {
            Protocol::Tcp { host, port } => {
                assert_eq!(host, "10.0.0.1");
                assert_eq!(port, 3000);
            }
            _ => panic!("Expected TCP protocol"),
        }
    }

    #[test]
    fn test_protocol_frame_serialization_roundtrip() {
        let frame = ProtocolFrame::command("id-99", json!({"key": "value"}));
        let json_str = serde_json::to_string(&frame).unwrap();
        let deserialized: ProtocolFrame = serde_json::from_str(&json_str).unwrap();
        assert_eq!(deserialized.frame_type, "command");
        assert_eq!(deserialized.id, Some("id-99".to_string()));
        assert_eq!(deserialized.data["key"], "value");
    }

    #[test]
    fn test_connection_state_all_variants() {
        let states = [
            ConnectionState::Disconnected,
            ConnectionState::Connecting,
            ConnectionState::Connected,
            ConnectionState::Disconnecting,
            ConnectionState::Reconnecting,
            ConnectionState::Error,
        ];
        // All unique
        for i in 0..states.len() {
            for j in (i + 1)..states.len() {
                assert_ne!(states[i], states[j]);
            }
        }
    }

    #[test]
    fn test_engine_message_serialization() {
        let msg = EngineMessage::new("test_type", json!({"data": 123}));
        let json_str = serde_json::to_string(&msg).unwrap();
        assert!(json_str.contains("test_type"));
        assert!(json_str.contains("123"));
        let deserialized: EngineMessage = serde_json::from_str(&json_str).unwrap();
        assert_eq!(deserialized.message_type, "test_type");
        assert_eq!(deserialized.payload["data"], 123);
    }

}
