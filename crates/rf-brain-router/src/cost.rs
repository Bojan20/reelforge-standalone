// file: crates/rf-brain-router/src/cost.rs
//! Cost tracking — monitors token usage and spend per model.
//!
//! Tracks:
//! - Per-model token counts (input + output)
//! - Estimated cost in USD
//! - Session and monthly totals
//! - Budget enforcement

use crate::provider::{BrainResponse, ModelId};
use chrono::{DateTime, Utc};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Per-model usage statistics.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ModelUsage {
    /// Total input tokens consumed.
    pub input_tokens: u64,
    /// Total output tokens generated.
    pub output_tokens: u64,
    /// Total requests sent.
    pub request_count: u64,
    /// Total estimated cost (USD).
    pub total_cost_usd: f64,
    /// Average latency (ms).
    pub avg_latency_ms: f64,
    /// Total errors.
    pub error_count: u64,
    /// Last used.
    pub last_used: Option<DateTime<Utc>>,
}

/// Session-level cost tracking.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CostSnapshot {
    /// Per-model usage.
    pub models: HashMap<ModelId, ModelUsage>,
    /// Session start time.
    pub session_start: DateTime<Utc>,
    /// Total spend this session (USD).
    pub session_total_usd: f64,
    /// Total requests this session.
    pub session_total_requests: u64,
}

/// Thread-safe cost tracker.
pub struct CostTracker {
    inner: Mutex<CostTrackerInner>,
}

struct CostTrackerInner {
    models: HashMap<ModelId, ModelUsage>,
    session_start: DateTime<Utc>,
    monthly_budget_usd: f64,
}

impl CostTracker {
    pub fn new(monthly_budget_usd: f64) -> Self {
        Self {
            inner: Mutex::new(CostTrackerInner {
                models: HashMap::new(),
                session_start: Utc::now(),
                monthly_budget_usd,
            }),
        }
    }

    /// Record a completed response.
    pub fn record(&self, response: &BrainResponse) {
        let mut inner = self.inner.lock();
        let usage = inner.models.entry(response.model.clone()).or_default();

        usage.input_tokens += response.input_tokens;
        usage.output_tokens += response.output_tokens;
        usage.request_count += 1;
        usage.total_cost_usd += response.estimated_cost_usd;
        usage.last_used = Some(response.received_at);

        // Running average for latency
        let n = usage.request_count as f64;
        usage.avg_latency_ms =
            usage.avg_latency_ms * ((n - 1.0) / n) + response.latency_ms as f64 / n;
    }

    /// Record an error for a model.
    pub fn record_error(&self, model: &ModelId) {
        let mut inner = self.inner.lock();
        let usage = inner.models.entry(model.clone()).or_default();
        usage.error_count += 1;
    }

    /// Check if we're within budget.
    pub fn within_budget(&self) -> bool {
        let inner = self.inner.lock();
        if inner.monthly_budget_usd <= 0.0 {
            return true; // No budget limit
        }
        self.session_total_usd_inner(&inner) < inner.monthly_budget_usd
    }

    /// Remaining budget (USD). Returns f64::MAX if unlimited.
    pub fn remaining_budget(&self) -> f64 {
        let inner = self.inner.lock();
        if inner.monthly_budget_usd <= 0.0 {
            return f64::MAX;
        }
        (inner.monthly_budget_usd - self.session_total_usd_inner(&inner)).max(0.0)
    }

    /// Get a snapshot of current costs.
    pub fn snapshot(&self) -> CostSnapshot {
        let inner = self.inner.lock();
        CostSnapshot {
            models: inner.models.clone(),
            session_start: inner.session_start,
            session_total_usd: self.session_total_usd_inner(&inner),
            session_total_requests: inner.models.values().map(|u| u.request_count).sum(),
        }
    }

    /// Total session spend (USD).
    pub fn session_total_usd(&self) -> f64 {
        let inner = self.inner.lock();
        self.session_total_usd_inner(&inner)
    }

    /// Get usage for a specific model.
    pub fn model_usage(&self, model: &ModelId) -> Option<ModelUsage> {
        let inner = self.inner.lock();
        inner.models.get(model).cloned()
    }

    /// Check if a specific model query would exceed budget.
    pub fn would_exceed_budget(&self, model: &ModelId, estimated_tokens: u64) -> bool {
        let inner = self.inner.lock();
        if inner.monthly_budget_usd <= 0.0 {
            return false;
        }

        let estimated_cost = (estimated_tokens as f64 / 1_000_000.0)
            * (model.input_cost_per_million() + model.output_cost_per_million()) / 2.0;

        let current = self.session_total_usd_inner(&inner);
        (current + estimated_cost) > inner.monthly_budget_usd
    }

    fn session_total_usd_inner(&self, inner: &CostTrackerInner) -> f64 {
        inner.models.values().map(|u| u.total_cost_usd).sum()
    }
}

impl Default for CostTracker {
    fn default() -> Self {
        Self::new(0.0) // Unlimited
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn mock_response(model: ModelId, input: u64, output: u64) -> BrainResponse {
        let cost = BrainResponse::calculate_cost(&model, input, output);
        BrainResponse {
            request_id: "test".into(),
            model: model.clone(),
            content: "test response".into(),
            input_tokens: input,
            output_tokens: output,
            latency_ms: 500,
            received_at: Utc::now(),
            is_fallback: false,
            estimated_cost_usd: cost,
        }
    }

    #[test]
    fn tracks_costs_per_model() {
        let tracker = CostTracker::new(0.0);

        tracker.record(&mock_response(ModelId::ClaudeOpus, 1000, 500));
        tracker.record(&mock_response(ModelId::ClaudeSonnet, 2000, 1000));
        tracker.record(&mock_response(ModelId::ClaudeOpus, 500, 250));

        let opus = tracker.model_usage(&ModelId::ClaudeOpus).unwrap();
        assert_eq!(opus.request_count, 2);
        assert_eq!(opus.input_tokens, 1500);
        assert_eq!(opus.output_tokens, 750);

        let sonnet = tracker.model_usage(&ModelId::ClaudeSonnet).unwrap();
        assert_eq!(sonnet.request_count, 1);
    }

    #[test]
    fn budget_enforcement() {
        let tracker = CostTracker::new(0.01); // $0.01 budget

        // Claude Opus is expensive — this should eat into budget
        tracker.record(&mock_response(ModelId::ClaudeOpus, 100_000, 50_000));

        // After expensive query, budget should be partially consumed
        let total = tracker.session_total_usd();
        assert!(total > 0.0);

        // Check if within budget depends on the actual cost
        if total >= 0.01 {
            assert!(!tracker.within_budget());
        }
    }

    #[test]
    fn unlimited_budget_always_within() {
        let tracker = CostTracker::new(0.0);
        tracker.record(&mock_response(ModelId::ClaudeOpus, 1_000_000, 500_000));
        assert!(tracker.within_budget());
        assert_eq!(tracker.remaining_budget(), f64::MAX);
    }

    #[test]
    fn error_tracking() {
        let tracker = CostTracker::new(0.0);
        tracker.record_error(&ModelId::DeepSeekR1);
        tracker.record_error(&ModelId::DeepSeekR1);

        let usage = tracker.model_usage(&ModelId::DeepSeekR1).unwrap();
        assert_eq!(usage.error_count, 2);
        assert_eq!(usage.request_count, 0);
    }

    #[test]
    fn snapshot_consistency() {
        let tracker = CostTracker::new(0.0);
        tracker.record(&mock_response(ModelId::ClaudeSonnet, 1000, 500));
        tracker.record(&mock_response(ModelId::Gpt4o, 2000, 1000));

        let snap = tracker.snapshot();
        assert_eq!(snap.session_total_requests, 2);
        assert!(snap.session_total_usd > 0.0);
        assert_eq!(snap.models.len(), 2);
    }

    #[test]
    fn would_exceed_budget_check() {
        let tracker = CostTracker::new(0.001); // Very small budget

        // Large request should exceed
        assert!(tracker.would_exceed_budget(&ModelId::ClaudeOpus, 1_000_000));

        // Browser is free, never exceeds
        assert!(!tracker.would_exceed_budget(&ModelId::ChatGptBrowser, 1_000_000));
    }
}
