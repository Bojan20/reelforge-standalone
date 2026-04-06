//! Wire protocol — JSON messages over WebSocket.
//!
//! Must match rf-gpt-bridge/src/protocol.rs exactly.
//! Duplicated here to avoid pulling in rf-cortex dependency chain.

use serde::{Deserialize, Serialize};

/// Command sent from daemon to browser (Chrome extension).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum BrowserCommand {
    /// Send a message to ChatGPT.
    #[serde(rename = "query")]
    Query {
        id: String,
        content: String,
        intent: String,
        urgency: f32,
    },

    /// Heartbeat ping.
    #[serde(rename = "ping")]
    Ping { ts: i64 },

    /// Tell browser to start new chat.
    #[serde(rename = "new_chat")]
    NewChat,
}

/// Event received from browser (Chrome extension).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum BrowserEvent {
    #[serde(rename = "response")]
    Response {
        id: String,
        content: String,
        streaming: bool,
    },

    #[serde(rename = "connected")]
    Connected {
        user_agent: String,
        model: Option<String>,
    },

    #[serde(rename = "pong")]
    Pong { ts: i64 },

    #[serde(rename = "error")]
    Error {
        id: Option<String>,
        message: String,
        code: String,
    },

    #[serde(rename = "busy")]
    Busy { id: String },

    #[serde(rename = "chat_cleared")]
    ChatCleared,

    #[serde(rename = "status")]
    Status {
        ready: bool,
        model: Option<String>,
        message_count: u32,
    },
}
