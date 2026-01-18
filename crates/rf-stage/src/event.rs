//! StageEvent — A stage occurrence with metadata
//!
//! Wraps a Stage with timing, payload, and source information.

use serde::{Deserialize, Serialize};

use crate::stage::Stage;
use crate::taxonomy::WinLine;

/// A stage event with full metadata
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StageEvent {
    /// The canonical stage
    pub stage: Stage,

    /// Timestamp in milliseconds (from start of spin or session)
    pub timestamp_ms: f64,

    /// Additional payload data
    #[serde(default)]
    pub payload: StagePayload,

    /// Original event name from engine (for debugging)
    #[serde(default)]
    pub source_event: Option<String>,

    /// Custom tags for filtering/routing
    #[serde(default)]
    pub tags: Vec<String>,
}

impl StageEvent {
    /// Create a new stage event with current timestamp
    pub fn new(stage: Stage, timestamp_ms: f64) -> Self {
        Self {
            stage,
            timestamp_ms,
            payload: StagePayload::default(),
            source_event: None,
            tags: Vec::new(),
        }
    }

    /// Create with payload
    pub fn with_payload(stage: Stage, timestamp_ms: f64, payload: StagePayload) -> Self {
        Self {
            stage,
            timestamp_ms,
            payload,
            source_event: None,
            tags: Vec::new(),
        }
    }

    /// Add source event info
    pub fn with_source(mut self, source: impl Into<String>) -> Self {
        self.source_event = Some(source.into());
        self
    }

    /// Add a tag
    pub fn with_tag(mut self, tag: impl Into<String>) -> Self {
        self.tags.push(tag.into());
        self
    }

    /// Add multiple tags
    pub fn with_tags(mut self, tags: impl IntoIterator<Item = impl Into<String>>) -> Self {
        self.tags.extend(tags.into_iter().map(|t| t.into()));
        self
    }

    /// Get stage type name
    pub fn type_name(&self) -> &'static str {
        self.stage.type_name()
    }
}

/// Additional payload data for a stage event
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct StagePayload {
    // ═══ WIN DATA ═══
    /// Total win amount
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub win_amount: Option<f64>,

    /// Bet amount (for ratio calculations)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bet_amount: Option<f64>,

    /// Win-to-bet ratio
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub win_ratio: Option<f64>,

    /// Individual win lines
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub win_lines: Vec<WinLine>,

    // ═══ SYMBOL DATA ═══
    /// Symbol ID
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub symbol_id: Option<u32>,

    /// Symbol name
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub symbol_name: Option<String>,

    /// Full reel grid (reels × rows)
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reel_grid: Option<Vec<Vec<u32>>>,

    // ═══ FEATURE DATA ═══
    /// Feature name
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub feature_name: Option<String>,

    /// Spins remaining in feature
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub spins_remaining: Option<u32>,

    /// Current multiplier
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub multiplier: Option<f64>,

    // ═══ JACKPOT DATA ═══
    /// Jackpot name
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub jackpot_name: Option<String>,

    /// Jackpot pool amount
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub jackpot_pool: Option<f64>,

    // ═══ GAME STATE ═══
    /// Current balance
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub balance: Option<f64>,

    /// Session ID
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,

    /// Spin ID
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub spin_id: Option<String>,

    // ═══ CUSTOM DATA ═══
    /// Arbitrary JSON for engine-specific data
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub custom: Option<serde_json::Value>,
}

impl StagePayload {
    /// Create empty payload
    pub fn new() -> Self {
        Self::default()
    }

    /// Create with win data
    pub fn with_win(win_amount: f64, bet_amount: Option<f64>) -> Self {
        let win_ratio = bet_amount.map(|bet| if bet > 0.0 { win_amount / bet } else { 0.0 });

        Self {
            win_amount: Some(win_amount),
            bet_amount,
            win_ratio,
            ..Default::default()
        }
    }

    /// Create with symbol data
    pub fn with_symbol(symbol_id: u32, symbol_name: Option<String>) -> Self {
        Self {
            symbol_id: Some(symbol_id),
            symbol_name,
            ..Default::default()
        }
    }

    /// Builder: set win amount
    pub fn win_amount(mut self, amount: f64) -> Self {
        self.win_amount = Some(amount);
        self
    }

    /// Builder: set bet amount
    pub fn bet_amount(mut self, amount: f64) -> Self {
        self.bet_amount = Some(amount);
        self
    }

    /// Builder: set multiplier
    pub fn multiplier(mut self, mult: f64) -> Self {
        self.multiplier = Some(mult);
        self
    }

    /// Builder: set spins remaining
    pub fn spins_remaining(mut self, spins: u32) -> Self {
        self.spins_remaining = Some(spins);
        self
    }

    /// Builder: set custom data
    pub fn custom(mut self, data: serde_json::Value) -> Self {
        self.custom = Some(data);
        self
    }

    /// Calculate win ratio if both amounts are present
    pub fn calculate_ratio(&self) -> Option<f64> {
        match (self.win_amount, self.bet_amount) {
            (Some(win), Some(bet)) if bet > 0.0 => Some(win / bet),
            _ => None,
        }
    }

    /// Check if this is a big win based on ratio
    pub fn is_big_win(&self, threshold: f64) -> bool {
        self.calculate_ratio().is_some_and(|r| r >= threshold)
    }
}

/// Builder for creating StageEvents fluently
pub struct StageEventBuilder {
    stage: Stage,
    timestamp_ms: f64,
    payload: StagePayload,
    source_event: Option<String>,
    tags: Vec<String>,
}

impl StageEventBuilder {
    pub fn new(stage: Stage) -> Self {
        Self {
            stage,
            timestamp_ms: 0.0,
            payload: StagePayload::default(),
            source_event: None,
            tags: Vec::new(),
        }
    }

    pub fn timestamp(mut self, ms: f64) -> Self {
        self.timestamp_ms = ms;
        self
    }

    pub fn payload(mut self, payload: StagePayload) -> Self {
        self.payload = payload;
        self
    }

    pub fn win_amount(mut self, amount: f64) -> Self {
        self.payload.win_amount = Some(amount);
        self
    }

    pub fn bet_amount(mut self, amount: f64) -> Self {
        self.payload.bet_amount = Some(amount);
        self
    }

    pub fn source(mut self, source: impl Into<String>) -> Self {
        self.source_event = Some(source.into());
        self
    }

    pub fn tag(mut self, tag: impl Into<String>) -> Self {
        self.tags.push(tag.into());
        self
    }

    pub fn build(self) -> StageEvent {
        StageEvent {
            stage: self.stage,
            timestamp_ms: self.timestamp_ms,
            payload: self.payload,
            source_event: self.source_event,
            tags: self.tags,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_stage_event_creation() {
        let event = StageEvent::new(Stage::SpinStart, 0.0)
            .with_source("cmd_spin_start")
            .with_tag("user_initiated");

        assert_eq!(event.stage, Stage::SpinStart);
        assert_eq!(event.timestamp_ms, 0.0);
        assert_eq!(event.source_event, Some("cmd_spin_start".to_string()));
        assert!(event.tags.contains(&"user_initiated".to_string()));
    }

    #[test]
    fn test_payload_win_ratio() {
        let payload = StagePayload::with_win(500.0, Some(10.0));
        assert_eq!(payload.calculate_ratio(), Some(50.0));
        assert!(payload.is_big_win(25.0)); // 50x > 25x threshold
    }

    #[test]
    fn test_builder_pattern() {
        let event = StageEventBuilder::new(Stage::WinPresent {
            win_amount: 100.0,
            line_count: 3,
        })
        .timestamp(1500.0)
        .win_amount(100.0)
        .bet_amount(2.0)
        .source("show_win")
        .tag("big_win")
        .build();

        assert_eq!(event.timestamp_ms, 1500.0);
        assert_eq!(event.payload.win_amount, Some(100.0));
        assert_eq!(event.payload.bet_amount, Some(2.0));
    }

    #[test]
    fn test_payload_serialization() {
        let payload = StagePayload::with_win(1000.0, Some(5.0)).multiplier(3.0);

        let json = serde_json::to_string(&payload).unwrap();
        assert!(json.contains("win_amount"));
        assert!(json.contains("multiplier"));

        // Empty fields should be skipped
        assert!(!json.contains("symbol_id"));
    }
}
