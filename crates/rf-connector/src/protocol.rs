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
}
