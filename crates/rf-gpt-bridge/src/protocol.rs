// file: crates/rf-gpt-bridge/src/protocol.rs
//! Message protocol — types for CORTEX ↔ ChatGPT Browser communication.
//!
//! All messages are JSON over WebSocket.
//! Two directions:
//!   Rust → Browser: BrowserCommand (queries to send to ChatGPT)
//!   Browser → Rust: BrowserEvent (responses from ChatGPT, status updates)

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// WIRE PROTOCOL — JSON messages over WebSocket
// ═══════════════════════════════════════════════════════════════════════════════

/// Command sent from Rust to browser (Tampermonkey script).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum BrowserCommand {
    /// Send a message to ChatGPT.
    #[serde(rename = "query")]
    Query {
        /// Unique request ID for correlation.
        id: String,
        /// The message to type into ChatGPT.
        content: String,
        /// Intent tag (for browser UI display / logging).
        intent: String,
        /// Urgency level (0.0 = background, 1.0 = critical).
        urgency: f32,
        /// Role/persona tag (which GPT persona is being used).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        role: Option<String>,
        /// Pipeline ID (if part of a multi-role pipeline).
        #[serde(default, skip_serializing_if = "Option::is_none")]
        pipeline_id: Option<String>,
    },

    /// Heartbeat ping — browser should respond with pong.
    #[serde(rename = "ping")]
    Ping {
        /// Timestamp for latency measurement.
        ts: i64,
    },

    /// Tell browser to clear ChatGPT conversation (new chat).
    #[serde(rename = "new_chat")]
    NewChat,
}

/// Event received from browser (Tampermonkey script).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum BrowserEvent {
    /// ChatGPT response received.
    #[serde(rename = "response")]
    Response {
        /// Correlated request ID.
        id: String,
        /// The full response text from ChatGPT.
        content: String,
        /// Whether the response is still streaming (partial).
        streaming: bool,
    },

    /// Browser connected to WebSocket.
    #[serde(rename = "connected")]
    Connected {
        /// User agent or identifier.
        user_agent: String,
        /// ChatGPT model visible in browser (if detectable).
        model: Option<String>,
    },

    /// Heartbeat pong.
    #[serde(rename = "pong")]
    Pong {
        /// Original timestamp from ping.
        ts: i64,
    },

    /// Error in browser (ChatGPT rate limit, network issue, etc).
    #[serde(rename = "error")]
    Error {
        /// Correlated request ID (if applicable).
        id: Option<String>,
        /// Error message.
        message: String,
        /// Error code (e.g., "rate_limit", "network", "dom_error").
        code: String,
    },

    /// ChatGPT is busy (still generating previous response).
    #[serde(rename = "busy")]
    Busy {
        /// The request ID that was attempted.
        id: String,
    },

    /// New chat was started successfully.
    #[serde(rename = "chat_cleared")]
    ChatCleared,

    /// Browser status update (periodic).
    #[serde(rename = "status")]
    Status {
        /// Is ChatGPT page loaded and ready?
        ready: bool,
        /// Current ChatGPT model (if visible).
        model: Option<String>,
        /// Number of messages in current chat.
        message_count: u32,
    },
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTERNAL TYPES — used within Rust bridge
// ═══════════════════════════════════════════════════════════════════════════════

/// Role in the conversation (kept for conversation memory compatibility).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum GptRole {
    System,
    User,
    Assistant,
}

/// A single message in the conversation memory.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GptMessage {
    pub role: GptRole,
    pub content: String,
}

impl GptMessage {
    pub fn system(content: impl Into<String>) -> Self {
        Self { role: GptRole::System, content: content.into() }
    }

    pub fn user(content: impl Into<String>) -> Self {
        Self { role: GptRole::User, content: content.into() }
    }

    pub fn assistant(content: impl Into<String>) -> Self {
        Self { role: GptRole::Assistant, content: content.into() }
    }
}

/// Intent of the GPT request — what kind of answer Corti expects.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum GptIntent {
    Analysis,
    Architecture,
    Debugging,
    CodeReview,
    Insight,
    UserQuery,
    Creative,
}

impl GptIntent {
    /// Convert to wire format string.
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Analysis => "analysis",
            Self::Architecture => "architecture",
            Self::Debugging => "debugging",
            Self::CodeReview => "code_review",
            Self::Insight => "insight",
            Self::UserQuery => "user_query",
            Self::Creative => "creative",
        }
    }
}

/// A request to be sent to ChatGPT (internal representation).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GptRequest {
    pub id: String,
    pub query: String,
    pub context: String,
    pub intent: GptIntent,
    pub urgency: f32,
    pub created_at: DateTime<Utc>,
}

impl GptRequest {
    pub fn new(query: impl Into<String>, context: impl Into<String>, intent: GptIntent) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            query: query.into(),
            context: context.into(),
            intent,
            urgency: 0.5,
            created_at: Utc::now(),
        }
    }

    pub fn with_urgency(mut self, urgency: f32) -> Self {
        self.urgency = urgency.clamp(0.0, 1.0);
        self
    }
}

/// Response from ChatGPT (internal representation).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GptResponse {
    pub request_id: String,
    pub content: String,
    pub model: String,
    pub latency_ms: u64,
    pub received_at: DateTime<Utc>,
    pub from_browser: bool,
    /// Which persona generated this request (if role system is active).
    #[serde(default)]
    pub persona: Option<String>,
    /// Pipeline ID (if part of a multi-role pipeline).
    #[serde(default)]
    pub pipeline_id: Option<String>,
}

/// Error types for the browser bridge.
#[derive(Debug, Clone, Serialize, Deserialize, thiserror::Error)]
pub enum GptError {
    #[error("Browser not connected")]
    BrowserNotConnected,

    #[error("Browser reported error: {code} — {message}")]
    BrowserError { code: String, message: String },

    #[error("ChatGPT is busy generating a response")]
    ChatGptBusy { request_id: String },

    #[error("Response timeout after {timeout_secs}s")]
    Timeout { timeout_secs: u64 },

    #[error("WebSocket error: {message}")]
    WebSocketError { message: String },

    #[error("Bridge is shut down")]
    Shutdown,

    #[error("Queue full — {pending} queries pending")]
    QueueFull { pending: usize },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn browser_command_serializes() {
        let cmd = BrowserCommand::Query {
            id: "test-123".into(),
            content: "Šta misliš o ovom kodu?".into(),
            intent: "analysis".into(),
            urgency: 0.8,
            role: Some("domain_researcher".into()),
            pipeline_id: None,
        };
        let json = serde_json::to_string(&cmd).unwrap();
        assert!(json.contains("\"type\":\"query\""));
        assert!(json.contains("test-123"));
        assert!(json.contains("domain_researcher"));
        // pipeline_id should be skipped when None
        assert!(!json.contains("pipeline_id"));
    }

    #[test]
    fn browser_event_deserializes() {
        let json = r#"{"type":"response","id":"test-123","content":"Odgovor od GPT","streaming":false}"#;
        let event: BrowserEvent = serde_json::from_str(json).unwrap();
        match event {
            BrowserEvent::Response { id, content, streaming } => {
                assert_eq!(id, "test-123");
                assert_eq!(content, "Odgovor od GPT");
                assert!(!streaming);
            }
            _ => panic!("Expected Response"),
        }
    }

    #[test]
    fn browser_connected_deserializes() {
        let json = r#"{"type":"connected","user_agent":"Chrome","model":"GPT-4o"}"#;
        let event: BrowserEvent = serde_json::from_str(json).unwrap();
        assert!(matches!(event, BrowserEvent::Connected { .. }));
    }

    #[test]
    fn ping_pong_roundtrip() {
        let ping = BrowserCommand::Ping { ts: 1234567890 };
        let json = serde_json::to_string(&ping).unwrap();
        assert!(json.contains("\"type\":\"ping\""));

        let pong_json = r#"{"type":"pong","ts":1234567890}"#;
        let pong: BrowserEvent = serde_json::from_str(pong_json).unwrap();
        assert!(matches!(pong, BrowserEvent::Pong { ts: 1234567890 }));
    }

    #[test]
    fn error_event_deserializes() {
        let json = r#"{"type":"error","id":"req-1","message":"Rate limited","code":"rate_limit"}"#;
        let event: BrowserEvent = serde_json::from_str(json).unwrap();
        match event {
            BrowserEvent::Error { id, message, code } => {
                assert_eq!(id, Some("req-1".into()));
                assert_eq!(code, "rate_limit");
                assert_eq!(message, "Rate limited");
            }
            _ => panic!("Expected Error"),
        }
    }

    #[test]
    fn intent_as_str() {
        assert_eq!(GptIntent::Analysis.as_str(), "analysis");
        assert_eq!(GptIntent::UserQuery.as_str(), "user_query");
    }
}
