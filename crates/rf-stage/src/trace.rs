//! StageTrace — A complete sequence of stage events for one spin/session
//!
//! A trace captures the full timeline of a game round.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::event::StageEvent;
use crate::stage::{Stage, StageCategory};
use crate::taxonomy::BigWinTier;
use crate::timing::TimingProfile;

/// A complete trace of stage events for one spin or session
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StageTrace {
    /// Unique identifier for this trace
    pub trace_id: String,

    /// Game identifier (e.g., "buffalo_gold", "88_fortunes")
    pub game_id: String,

    /// Optional session identifier
    #[serde(default)]
    pub session_id: Option<String>,

    /// Spin ID within session
    #[serde(default)]
    pub spin_id: Option<String>,

    /// All events in chronological order
    pub events: Vec<StageEvent>,

    /// When this trace was recorded
    pub recorded_at: DateTime<Utc>,

    /// Timing profile used (if resolved)
    #[serde(default)]
    pub timing_profile: Option<TimingProfile>,

    /// Adapter that generated this trace
    #[serde(default)]
    pub adapter_id: Option<String>,

    /// Custom metadata
    #[serde(default)]
    pub metadata: serde_json::Map<String, serde_json::Value>,
}

impl StageTrace {
    /// Create a new empty trace
    pub fn new(trace_id: impl Into<String>, game_id: impl Into<String>) -> Self {
        Self {
            trace_id: trace_id.into(),
            game_id: game_id.into(),
            session_id: None,
            spin_id: None,
            events: Vec::new(),
            recorded_at: Utc::now(),
            timing_profile: None,
            adapter_id: None,
            metadata: serde_json::Map::new(),
        }
    }

    /// Add an event to the trace
    pub fn push(&mut self, event: StageEvent) {
        self.events.push(event);
    }

    /// Add an event and return self (builder pattern)
    pub fn with_event(mut self, event: StageEvent) -> Self {
        self.events.push(event);
        self
    }

    /// Set session ID
    pub fn with_session(mut self, session_id: impl Into<String>) -> Self {
        self.session_id = Some(session_id.into());
        self
    }

    /// Set spin ID
    pub fn with_spin(mut self, spin_id: impl Into<String>) -> Self {
        self.spin_id = Some(spin_id.into());
        self
    }

    /// Set adapter ID
    pub fn with_adapter(mut self, adapter_id: impl Into<String>) -> Self {
        self.adapter_id = Some(adapter_id.into());
        self
    }

    /// Add metadata
    pub fn with_metadata(mut self, key: impl Into<String>, value: serde_json::Value) -> Self {
        self.metadata.insert(key.into(), value);
        self
    }

    /// Get total duration in milliseconds
    pub fn duration_ms(&self) -> f64 {
        if self.events.is_empty() {
            return 0.0;
        }
        let first = self.events.first().map(|e| e.timestamp_ms).unwrap_or(0.0);
        let last = self.events.last().map(|e| e.timestamp_ms).unwrap_or(0.0);
        last - first
    }

    /// Get events by category
    pub fn events_by_category(&self, category: StageCategory) -> Vec<&StageEvent> {
        self.events
            .iter()
            .filter(|e| e.stage.category() == category)
            .collect()
    }

    /// Get events by stage type name
    pub fn events_by_type(&self, type_name: &str) -> Vec<&StageEvent> {
        self.events
            .iter()
            .filter(|e| e.stage.type_name() == type_name)
            .collect()
    }

    /// Find first event matching a predicate
    pub fn find_event<F>(&self, predicate: F) -> Option<&StageEvent>
    where
        F: Fn(&StageEvent) -> bool,
    {
        self.events.iter().find(|e| predicate(e))
    }

    /// Check if trace contains a specific stage type
    pub fn has_stage(&self, type_name: &str) -> bool {
        self.events.iter().any(|e| e.stage.type_name() == type_name)
    }

    /// Get all reel stop events
    pub fn reel_stops(&self) -> Vec<&StageEvent> {
        self.events_by_type("reel_stop")
    }

    /// Get total win amount from WinPresent or BigWinTier events
    pub fn total_win(&self) -> f64 {
        for event in self.events.iter().rev() {
            // Check payload first
            if let Some(win) = event.payload.win_amount {
                return win;
            }
            // Check stage-specific wins
            match &event.stage {
                Stage::WinPresent { win_amount, .. } => return *win_amount,
                Stage::BigWinTier { amount, .. } => return *amount,
                Stage::FeatureExit { total_win } => return *total_win,
                _ => continue,
            }
        }
        0.0
    }

    /// Get highest big win tier in trace
    pub fn max_bigwin_tier(&self) -> Option<BigWinTier> {
        self.events
            .iter()
            .filter_map(|e| match &e.stage {
                Stage::BigWinTier { tier, .. } => Some(*tier),
                _ => None,
            })
            .max_by_key(|tier| tier.min_ratio() as i32)
    }

    /// Check if this spin triggered a feature
    pub fn has_feature(&self) -> bool {
        self.has_stage("feature_enter")
    }

    /// Check if this spin hit a jackpot
    pub fn has_jackpot(&self) -> bool {
        self.has_stage("jackpot_trigger")
    }

    /// Get feature type if feature was triggered
    pub fn feature_type(&self) -> Option<crate::taxonomy::FeatureType> {
        self.events.iter().find_map(|e| match &e.stage {
            Stage::FeatureEnter { feature_type, .. } => Some(*feature_type),
            _ => None,
        })
    }

    /// Validate trace has required stages
    pub fn validate(&self) -> TraceValidation {
        // Check for reel stops
        let reel_stops = self.reel_stops().len();

        // Check for win handling if there was a win
        let has_win = self.total_win() > 0.0;

        TraceValidation {
            has_spin_start: self.has_stage("spin_start"),
            has_spin_end: self.has_stage("spin_end"),
            reel_stop_count: reel_stops as u8,
            has_all_reels: reel_stops >= 3, // Most slots have at least 3 reels
            has_win_present: has_win && self.has_stage("win_present"),
            has_feature_enter: self.has_feature(),
            has_feature_exit: self.has_feature() && self.has_stage("feature_exit"),
        }
    }

    /// Get summary of trace
    pub fn summary(&self) -> TraceSummary {
        TraceSummary {
            trace_id: self.trace_id.clone(),
            game_id: self.game_id.clone(),
            event_count: self.events.len(),
            duration_ms: self.duration_ms(),
            total_win: self.total_win(),
            has_feature: self.has_feature(),
            has_jackpot: self.has_jackpot(),
            max_bigwin_tier: self.max_bigwin_tier(),
        }
    }
}

/// Validation result for a trace
#[derive(Debug, Clone, Default)]
pub struct TraceValidation {
    pub has_spin_start: bool,
    pub has_spin_end: bool,
    pub has_all_reels: bool,
    pub reel_stop_count: u8,
    pub has_win_present: bool,
    pub has_feature_enter: bool,
    pub has_feature_exit: bool,
}

impl TraceValidation {
    /// Check if trace is valid (has all required elements)
    pub fn is_valid(&self) -> bool {
        self.has_spin_start && self.has_spin_end && self.has_all_reels
    }

    /// Get list of warnings
    pub fn warnings(&self) -> Vec<&'static str> {
        let mut warnings = Vec::new();

        if !self.has_spin_start {
            warnings.push("Missing SPIN_START event");
        }
        if !self.has_spin_end {
            warnings.push("Missing SPIN_END event");
        }
        if !self.has_all_reels {
            warnings.push("Not all reels have stop events");
        }
        if self.has_feature_enter && !self.has_feature_exit {
            warnings.push("Feature entered but not exited");
        }

        warnings
    }
}

/// Summary of a trace for quick overview
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraceSummary {
    pub trace_id: String,
    pub game_id: String,
    pub event_count: usize,
    pub duration_ms: f64,
    pub total_win: f64,
    pub has_feature: bool,
    pub has_jackpot: bool,
    pub max_bigwin_tier: Option<BigWinTier>,
}

/// Collection of traces (e.g., from a session or batch import)
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct TraceCollection {
    pub traces: Vec<StageTrace>,
    pub metadata: serde_json::Map<String, serde_json::Value>,
}

impl TraceCollection {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push(&mut self, trace: StageTrace) {
        self.traces.push(trace);
    }

    pub fn len(&self) -> usize {
        self.traces.len()
    }

    pub fn is_empty(&self) -> bool {
        self.traces.is_empty()
    }

    /// Get summary stats
    pub fn stats(&self) -> CollectionStats {
        let total_wins: f64 = self.traces.iter().map(|t| t.total_win()).sum();
        let feature_count = self.traces.iter().filter(|t| t.has_feature()).count();
        let jackpot_count = self.traces.iter().filter(|t| t.has_jackpot()).count();

        CollectionStats {
            trace_count: self.traces.len(),
            total_wins,
            average_win: if self.traces.is_empty() {
                0.0
            } else {
                total_wins / self.traces.len() as f64
            },
            feature_count,
            jackpot_count,
        }
    }
}

/// Stats for a trace collection
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollectionStats {
    pub trace_count: usize,
    pub total_wins: f64,
    pub average_win: f64,
    pub feature_count: usize,
    pub jackpot_count: usize,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::StageEvent;
    use crate::taxonomy::FeatureType;

    fn create_basic_trace() -> StageTrace {
        let mut trace = StageTrace::new("test-001", "test_game");

        trace.push(StageEvent::new(Stage::SpinStart, 0.0));
        for i in 0..5 {
            trace.push(StageEvent::new(
                Stage::ReelStop {
                    reel_index: i,
                    symbols: vec![1, 2, 3],
                },
                500.0 + (i as f64 * 150.0),
            ));
        }
        trace.push(StageEvent::new(
            Stage::WinPresent {
                win_amount: 50.0,
                line_count: 2,
            },
            1500.0,
        ));
        trace.push(StageEvent::new(Stage::SpinEnd, 2000.0));

        trace
    }

    #[test]
    fn test_trace_creation() {
        let trace = create_basic_trace();

        assert_eq!(trace.game_id, "test_game");
        assert_eq!(trace.events.len(), 8); // 1 start + 5 reels + 1 win + 1 end
    }

    #[test]
    fn test_trace_duration() {
        let trace = create_basic_trace();
        assert_eq!(trace.duration_ms(), 2000.0);
    }

    #[test]
    fn test_trace_total_win() {
        let trace = create_basic_trace();
        assert_eq!(trace.total_win(), 50.0);
    }

    #[test]
    fn test_trace_validation() {
        let trace = create_basic_trace();
        let validation = trace.validate();

        assert!(validation.has_spin_start);
        assert!(validation.has_spin_end);
        assert_eq!(validation.reel_stop_count, 5);
        assert!(validation.is_valid());
    }

    #[test]
    fn test_trace_with_feature() {
        let mut trace = StageTrace::new("test-002", "test_game");

        trace.push(StageEvent::new(Stage::SpinStart, 0.0));
        trace.push(StageEvent::new(
            Stage::FeatureEnter {
                feature_type: FeatureType::FreeSpins,
                total_steps: Some(10),
                multiplier: 1.0,
            },
            1000.0,
        ));
        trace.push(StageEvent::new(
            Stage::FeatureExit { total_win: 500.0 },
            5000.0,
        ));
        trace.push(StageEvent::new(Stage::SpinEnd, 5500.0));

        assert!(trace.has_feature());
        assert_eq!(trace.feature_type(), Some(FeatureType::FreeSpins));
    }

    #[test]
    fn test_trace_serialization() {
        let trace = create_basic_trace();
        let json = serde_json::to_string_pretty(&trace).unwrap();

        assert!(json.contains("test_game"));
        assert!(json.contains("spin_start"));

        let deserialized: StageTrace = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.game_id, trace.game_id);
        assert_eq!(deserialized.events.len(), trace.events.len());
    }
}
