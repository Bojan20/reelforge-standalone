// file: crates/rf-gpt-bridge/src/config.rs
//! Configuration for the GPT Browser Bridge.
//!
//! No API keys needed — communicates with ChatGPT through the browser via WebSocket.

use serde::{Deserialize, Serialize};

/// GPT Browser Bridge configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GptBridgeConfig {
    /// WebSocket server port (browser connects here).
    pub ws_port: u16,

    /// WebSocket bind address (default: 127.0.0.1 — local only for security).
    pub ws_bind: String,

    /// Maximum conversation history length (messages kept in memory).
    pub max_conversation_history: usize,

    /// Minimum interval between autonomous GPT queries (seconds).
    /// Prevents spamming ChatGPT during crisis cascades.
    pub min_query_interval_secs: u64,

    /// System prompt context — sent as prefix to queries so GPT understands the context.
    pub system_prompt: String,

    /// Enable autonomous mode (Corti decides when to consult GPT).
    pub autonomous_enabled: bool,

    /// Confidence threshold — only send to GPT if Corti's confidence < this.
    pub confidence_threshold: f32,

    /// Timeout waiting for browser response (seconds).
    pub response_timeout_secs: u64,

    /// Maximum pending queries before dropping new ones.
    pub max_pending_queries: usize,

    /// Minimum quality threshold for accepting GPT responses (0.0 - 1.0).
    /// Responses below this threshold are logged but not propagated as signals.
    pub quality_threshold: f64,

    /// Enable pipeline mode (multi-role queries for critical decisions).
    pub pipeline_enabled: bool,

    /// Default persona to use when no specific role is selected.
    pub default_persona: String,
}

impl Default for GptBridgeConfig {
    fn default() -> Self {
        Self {
            ws_port: 9742,
            ws_bind: "127.0.0.1".into(),
            max_conversation_history: 50,
            min_query_interval_secs: 10,
            system_prompt: Self::default_system_prompt(),
            autonomous_enabled: true,
            confidence_threshold: 0.6,
            response_timeout_secs: 120,
            max_pending_queries: 32,
            quality_threshold: 0.4,
            pipeline_enabled: true,
            default_persona: "domain_researcher".into(),
        }
    }
}

impl GptBridgeConfig {
    /// The bridge is "ready" when the WebSocket server can bind.
    /// No API key needed — browser provides the ChatGPT connection.
    pub fn is_ready(&self) -> bool {
        self.ws_port > 0
    }

    /// WebSocket address string.
    pub fn ws_addr(&self) -> String {
        format!("{}:{}", self.ws_bind, self.ws_port)
    }

    fn default_system_prompt() -> String {
        r#"Ti si GPT — eksterna inteligencija u CORTEX ekosistemu.

CORTEX (Corti) je centralni nervni sistem FluxForge Studio DAW/SlotLab aplikacije, napisan u Rustu.
Corti te konsultuje kada:
1. Detektuje nepoznat pattern koji ne može sam da reši
2. Treba mu druga perspektiva na arhitektonsku odluku
3. Korisnik (Boki) eksplicitno traži tvoje mišljenje
4. Treba analiza koja zahteva šire znanje

Tvoj odgovor MORA biti:
- Konkretan (fajlovi, linije koda, tačne promene)
- Actionable (Corti može direktno da primeni)
- Kratak (max 500 reči osim ako je analiza kompleksna)
- JSON-strukturiran kada Corti traži structured output

NIKAD ne odgovaraj generičkim savetima. Budi specifičan.
Jezik: Srpski (ekavica) osim za kod i tehničke termine."#
            .into()
    }
}
