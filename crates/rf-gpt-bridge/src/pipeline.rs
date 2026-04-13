// file: crates/rf-gpt-bridge/src/pipeline.rs
//! Multi-Role Pipeline — send queries to multiple GPT personas and merge results.
//!
//! Three pipeline modes:
//! 1. **Single** — one role, one query (fast, default)
//! 2. **Consensus** — same query to 2-3 roles, merge where they agree
//! 3. **Chain** — role A's output feeds into role B (refinement pipeline)
//!
//! The pipeline is the orchestration layer — it doesn't send queries directly,
//! it produces PipelineStage instructions that the bridge executes.

use crate::evaluator::EvaluationResult;
use crate::protocol::GptIntent;
use crate::roles::GptPersona;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Pipeline execution mode.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PipelineMode {
    /// Single role, single query.
    Single,
    /// Same query to multiple roles, merge results.
    Consensus,
    /// Sequential: output of role A feeds into role B.
    Chain,
}

/// A complete pipeline definition — what to send, to whom, in what order.
#[derive(Debug, Clone)]
pub struct Pipeline {
    /// Unique pipeline ID.
    pub id: String,
    /// The original query from Corti.
    pub original_query: String,
    /// The intent.
    pub intent: GptIntent,
    /// Pipeline mode.
    pub mode: PipelineMode,
    /// Stages to execute (in order for Chain, parallel for Consensus).
    pub stages: Vec<PipelineStage>,
    /// Created timestamp.
    pub created_at: DateTime<Utc>,
}

/// A single stage in the pipeline.
#[derive(Debug, Clone)]
pub struct PipelineStage {
    /// Stage index (0-based).
    pub index: usize,
    /// Which persona handles this stage.
    pub persona: GptPersona,
    /// The query for this stage (may differ from original in Chain mode).
    pub query: String,
    /// Urgency for this stage.
    pub urgency: f32,
    /// Current state.
    pub state: StageState,
}

/// State of a pipeline stage.
#[derive(Debug, Clone)]
pub enum StageState {
    /// Waiting to be sent.
    Pending,
    /// Sent to GPT, waiting for response.
    Sent { request_id: String },
    /// Response received and evaluated.
    Completed {
        request_id: String,
        response: String,
        evaluation: EvaluationResult,
        latency_ms: u64,
    },
    /// Failed (timeout, error, rejected by evaluator).
    Failed { reason: String },
}

/// The merged result of a completed pipeline.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineResult {
    /// Pipeline ID.
    pub pipeline_id: String,
    /// The final merged/selected response.
    pub content: String,
    /// Which persona(s) contributed.
    pub contributors: Vec<GptPersona>,
    /// Overall quality score.
    pub quality: f64,
    /// Pipeline mode used.
    pub mode: PipelineMode,
    /// Total wall-clock time.
    pub total_latency_ms: u64,
    /// Per-stage results summary.
    pub stage_summaries: Vec<StageSummary>,
}

/// Summary of a single stage result.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StageSummary {
    pub persona: GptPersona,
    pub quality: f64,
    pub accepted: bool,
    pub latency_ms: u64,
}

/// Pipeline builder — creates pipeline definitions.
pub struct PipelineBuilder;

impl PipelineBuilder {
    /// Build a single-role pipeline.
    pub fn single(query: &str, intent: GptIntent, persona: GptPersona, urgency: f32) -> Pipeline {
        Pipeline {
            id: uuid::Uuid::new_v4().to_string(),
            original_query: query.to_string(),
            intent,
            mode: PipelineMode::Single,
            stages: vec![PipelineStage {
                index: 0,
                persona,
                query: query.to_string(),
                urgency,
                state: StageState::Pending,
            }],
            created_at: Utc::now(),
        }
    }

    /// Build a consensus pipeline (same query to multiple roles).
    pub fn consensus(
        query: &str,
        intent: GptIntent,
        personas: Vec<GptPersona>,
        urgency: f32,
    ) -> Pipeline {
        let stages = personas
            .into_iter()
            .enumerate()
            .map(|(i, persona)| PipelineStage {
                index: i,
                persona,
                query: query.to_string(),
                urgency,
                state: StageState::Pending,
            })
            .collect();

        Pipeline {
            id: uuid::Uuid::new_v4().to_string(),
            original_query: query.to_string(),
            intent,
            mode: PipelineMode::Consensus,
            stages,
            created_at: Utc::now(),
        }
    }

    /// Build a chain pipeline (output of A feeds into B).
    pub fn chain(
        query: &str,
        intent: GptIntent,
        chain: Vec<(GptPersona, &str)>,
        urgency: f32,
    ) -> Pipeline {
        let stages = chain
            .into_iter()
            .enumerate()
            .map(|(i, (persona, stage_query))| PipelineStage {
                index: i,
                persona,
                query: if i == 0 {
                    query.to_string()
                } else {
                    stage_query.to_string()
                },
                urgency,
                state: StageState::Pending,
            })
            .collect();

        Pipeline {
            id: uuid::Uuid::new_v4().to_string(),
            original_query: query.to_string(),
            intent,
            mode: PipelineMode::Chain,
            stages,
            created_at: Utc::now(),
        }
    }

    /// Build a smart pipeline — automatically selects mode and roles.
    pub fn auto(
        query: &str,
        intent: GptIntent,
        primary_persona: GptPersona,
        urgency: f32,
    ) -> Pipeline {
        // High-stakes decisions get consensus
        if urgency > 0.8 && matches!(intent, GptIntent::Architecture | GptIntent::Debugging) {
            let personas = match intent {
                GptIntent::Architecture => vec![
                    primary_persona,
                    GptPersona::DevilsAdvocate,
                ],
                GptIntent::Debugging => vec![
                    primary_persona,
                    GptPersona::TestOracle,
                ],
                _ => vec![primary_persona],
            };
            if personas.len() > 1 {
                return Self::consensus(query, intent, personas, urgency);
            }
        }

        // Creative tasks get chain: bulk generate → creative direct
        if intent == GptIntent::Creative && primary_persona == GptPersona::BulkGenerator {
            return Self::chain(
                query,
                intent,
                vec![
                    (GptPersona::BulkGenerator, query),
                    (
                        GptPersona::CreativeDirector,
                        "Iz prethodne liste, izaberi top 5 i rangiraj ih. Za svaki objasni zašto je dobar.",
                    ),
                ],
                urgency,
            );
        }

        // Default: single role
        Self::single(query, intent, primary_persona, urgency)
    }
}

impl Pipeline {
    /// Get the next pending stage (for sending).
    pub fn next_pending_stage(&self) -> Option<&PipelineStage> {
        match self.mode {
            PipelineMode::Single | PipelineMode::Consensus => {
                // All pending stages can be sent in parallel
                self.stages.iter().find(|s| matches!(s.state, StageState::Pending))
            }
            PipelineMode::Chain => {
                // Only send next if previous is completed
                for (i, stage) in self.stages.iter().enumerate() {
                    if matches!(stage.state, StageState::Pending) {
                        if i == 0 || matches!(self.stages[i - 1].state, StageState::Completed { .. }) {
                            return Some(stage);
                        }
                        return None; // Previous stage not done yet
                    }
                }
                None
            }
        }
    }

    /// Get all pending stages (for consensus parallel send).
    pub fn all_pending_stages(&self) -> Vec<&PipelineStage> {
        match self.mode {
            PipelineMode::Consensus => {
                self.stages.iter().filter(|s| matches!(s.state, StageState::Pending)).collect()
            }
            _ => {
                self.next_pending_stage().into_iter().collect()
            }
        }
    }

    /// Mark a stage as sent.
    pub fn mark_sent(&mut self, stage_index: usize, request_id: String) {
        if let Some(stage) = self.stages.get_mut(stage_index) {
            stage.state = StageState::Sent { request_id };
        }
    }

    /// Mark a stage as completed with response.
    pub fn mark_completed(
        &mut self,
        request_id: &str,
        response: String,
        evaluation: EvaluationResult,
        latency_ms: u64,
    ) -> bool {
        // Find the stage index that matches this request_id
        let stage_idx = self.stages.iter().position(|s| {
            matches!(&s.state, StageState::Sent { request_id: rid } if rid == request_id)
        });

        let stage_idx = match stage_idx {
            Some(idx) => idx,
            None => return false,
        };

        // For chain mode, prepare next stage query modification
        let chain_update = if self.mode == PipelineMode::Chain {
            let next_idx = stage_idx + 1;
            if next_idx < self.stages.len() && matches!(self.stages[next_idx].state, StageState::Pending) {
                let next_query = self.stages[next_idx].query.clone();
                Some((next_idx, format!(
                    "{}\n\n[Rezultat prethodnog koraka]:\n{}",
                    next_query, response
                )))
            } else {
                None
            }
        } else {
            None
        };

        // Update the completed stage
        self.stages[stage_idx].state = StageState::Completed {
            request_id: request_id.to_string(),
            response,
            evaluation,
            latency_ms,
        };

        // Update next stage's query if chain mode
        if let Some((next_idx, new_query)) = chain_update {
            self.stages[next_idx].query = new_query;
        }

        true
    }

    /// Mark a stage as failed.
    pub fn mark_failed(&mut self, request_id: &str, reason: String) {
        for stage in &mut self.stages {
            if matches!(&stage.state, StageState::Sent { request_id: rid } if rid == request_id) {
                stage.state = StageState::Failed { reason };
                return;
            }
        }
    }

    /// Is the entire pipeline done?
    pub fn is_complete(&self) -> bool {
        self.stages.iter().all(|s| {
            matches!(s.state, StageState::Completed { .. } | StageState::Failed { .. })
        })
    }

    /// Merge results when pipeline is complete.
    pub fn merge_results(&self) -> Option<PipelineResult> {
        if !self.is_complete() {
            return None;
        }

        let stage_summaries: Vec<StageSummary> = self
            .stages
            .iter()
            .filter_map(|s| match &s.state {
                StageState::Completed {
                    evaluation,
                    latency_ms,
                    ..
                } => Some(StageSummary {
                    persona: s.persona,
                    quality: evaluation.quality,
                    accepted: evaluation.accepted,
                    latency_ms: *latency_ms,
                }),
                StageState::Failed { .. } => Some(StageSummary {
                    persona: s.persona,
                    quality: 0.0,
                    accepted: false,
                    latency_ms: 0,
                }),
                _ => None,
            })
            .collect();

        let completed_stages: Vec<&PipelineStage> = self
            .stages
            .iter()
            .filter(|s| matches!(s.state, StageState::Completed { .. }))
            .collect();

        if completed_stages.is_empty() {
            return Some(PipelineResult {
                pipeline_id: self.id.clone(),
                content: "[Svi koraci pipeline-a su pali]".into(),
                contributors: vec![],
                quality: 0.0,
                mode: self.mode,
                total_latency_ms: 0,
                stage_summaries,
            });
        }

        let (content, contributors, quality) = match self.mode {
            PipelineMode::Single => {
                let stage = &completed_stages[0];
                if let StageState::Completed {
                    response,
                    evaluation,
                    ..
                } = &stage.state
                {
                    (response.clone(), vec![stage.persona], evaluation.quality)
                } else {
                    unreachable!()
                }
            }

            PipelineMode::Consensus => {
                self.merge_consensus(&completed_stages)
            }

            PipelineMode::Chain => {
                // Chain mode: use the last stage's output
                let Some(last) = completed_stages.last() else {
                    return None;
                };
                let contributors: Vec<GptPersona> = completed_stages.iter().map(|s| s.persona).collect();
                if let StageState::Completed {
                    response,
                    evaluation,
                    ..
                } = &last.state
                {
                    (response.clone(), contributors, evaluation.quality)
                } else {
                    unreachable!()
                }
            }
        };

        let total_latency_ms = stage_summaries.iter().map(|s| s.latency_ms).max().unwrap_or(0);

        Some(PipelineResult {
            pipeline_id: self.id.clone(),
            content,
            contributors,
            quality,
            mode: self.mode,
            total_latency_ms,
            stage_summaries,
        })
    }

    /// Merge consensus results — pick the best, note agreements/disagreements.
    fn merge_consensus(&self, completed: &[&PipelineStage]) -> (String, Vec<GptPersona>, f64) {
        // Find the highest quality accepted response
        let mut best: Option<(&str, GptPersona, f64)> = None;

        for stage in completed {
            if let StageState::Completed {
                response,
                evaluation,
                ..
            } = &stage.state
            {
                if evaluation.accepted {
                    let is_better = best.as_ref().is_none_or(|(_, _, q)| evaluation.quality > *q);
                    if is_better {
                        best = Some((response, stage.persona, evaluation.quality));
                    }
                }
            }
        }

        match best {
            Some((response, persona, quality)) => {
                let mut content = response.to_string();

                // Append dissenting opinions from other roles
                let others: Vec<String> = completed
                    .iter()
                    .filter(|s| s.persona != persona)
                    .filter_map(|s| {
                        if let StageState::Completed {
                            response,
                            evaluation,
                            ..
                        } = &s.state
                        {
                            if evaluation.accepted {
                                Some(format!(
                                    "\n\n---\n**[{}] kaže:**\n{}",
                                    s.persona.display_name(),
                                    // Truncate to 500 chars for secondary opinions
                                    if response.len() > 500 {
                                        format!("{}...", &response[..500])
                                    } else {
                                        response.clone()
                                    }
                                ))
                            } else {
                                None
                            }
                        } else {
                            None
                        }
                    })
                    .collect();

                if !others.is_empty() {
                    content.push_str("\n\n---\n## Druge perspektive");
                    for other in &others {
                        content.push_str(other);
                    }
                }

                let contributors = completed.iter().map(|s| s.persona).collect();
                (content, contributors, quality)
            }
            None => {
                // No accepted responses — return the best rejected one
                let best_rejected = completed
                    .iter()
                    .filter_map(|s| {
                        if let StageState::Completed {
                            response,
                            evaluation,
                            ..
                        } = &s.state
                        {
                            Some((response.as_str(), s.persona, evaluation.quality))
                        } else {
                            None
                        }
                    })
                    .max_by(|a, b| a.2.partial_cmp(&b.2).unwrap_or(std::cmp::Ordering::Equal));

                match best_rejected {
                    Some((response, persona, quality)) => {
                        (
                            format!("[UPOZORENJE: Nijedan odgovor nije prošao evaluaciju]\n\n{}", response),
                            vec![persona],
                            quality,
                        )
                    }
                    None => (
                        "[Nijedan odgovor nije primljen]".into(),
                        vec![],
                        0.0,
                    ),
                }
            }
        }
    }
}

/// Tracks active pipelines.
pub struct PipelineManager {
    /// Active pipelines indexed by ID.
    pub active: HashMap<String, Pipeline>,
    /// Request ID → Pipeline ID mapping.
    request_to_pipeline: HashMap<String, String>,
    /// Completed pipeline results.
    completed: Vec<PipelineResult>,
    /// Max completed results to keep.
    max_completed: usize,
}

impl Default for PipelineManager {
    fn default() -> Self {
        Self::new()
    }
}

impl PipelineManager {
    pub fn new() -> Self {
        Self {
            active: HashMap::new(),
            request_to_pipeline: HashMap::new(),
            completed: Vec::new(),
            max_completed: 100,
        }
    }

    /// Add a new pipeline.
    pub fn add(&mut self, pipeline: Pipeline) -> String {
        let id = pipeline.id.clone();
        self.active.insert(id.clone(), pipeline);
        id
    }

    /// Register a request ID for a pipeline stage.
    pub fn register_request(&mut self, request_id: String, pipeline_id: String) {
        self.request_to_pipeline.insert(request_id, pipeline_id);
    }

    /// Handle a response — route to the correct pipeline.
    pub fn handle_response(
        &mut self,
        request_id: &str,
        response: String,
        evaluation: EvaluationResult,
        latency_ms: u64,
    ) -> Option<PipelineResult> {
        let pipeline_id = self.request_to_pipeline.remove(request_id)?;
        let pipeline = self.active.get_mut(&pipeline_id)?;

        pipeline.mark_completed(request_id, response, evaluation, latency_ms);

        if pipeline.is_complete() {
            let result = pipeline.merge_results();
            self.active.remove(&pipeline_id);

            if let Some(ref r) = result {
                self.completed.push(r.clone());
                if self.completed.len() > self.max_completed {
                    self.completed.remove(0);
                }
            }

            result
        } else {
            None
        }
    }

    /// Handle a failure for a request.
    pub fn handle_failure(&mut self, request_id: &str, reason: String) -> Option<PipelineResult> {
        let pipeline_id = self.request_to_pipeline.remove(request_id)?;
        let pipeline = self.active.get_mut(&pipeline_id)?;

        pipeline.mark_failed(request_id, reason);

        if pipeline.is_complete() {
            let result = pipeline.merge_results();
            self.active.remove(&pipeline_id);
            result
        } else {
            None
        }
    }

    /// Get all stages that need to be sent.
    pub fn stages_to_send(&self) -> Vec<(&str, Vec<&PipelineStage>)> {
        self.active
            .iter()
            .filter_map(|(id, pipeline)| {
                let pending = pipeline.all_pending_stages();
                if pending.is_empty() {
                    None
                } else {
                    Some((id.as_str(), pending))
                }
            })
            .collect()
    }

    /// Number of active pipelines.
    pub fn active_count(&self) -> usize {
        self.active.len()
    }

    /// Recent completed results.
    pub fn recent_results(&self) -> &[PipelineResult] {
        &self.completed
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::evaluator::{EvaluationResult, QualityDimensions};

    fn good_eval() -> EvaluationResult {
        EvaluationResult {
            quality: 0.85,
            accepted: true,
            dimensions: QualityDimensions {
                relevance: 0.9,
                specificity: 0.8,
                format_compliance: 0.9,
                length_appropriateness: 0.9,
                groundedness: 0.8,
            },
            verdict: "PRIHVAĆENO".into(),
            issues: vec![],
        }
    }

    fn bad_eval() -> EvaluationResult {
        EvaluationResult {
            quality: 0.2,
            accepted: false,
            dimensions: QualityDimensions {
                relevance: 0.2,
                specificity: 0.1,
                format_compliance: 0.3,
                length_appropriateness: 0.5,
                groundedness: 0.1,
            },
            verdict: "ODBIJENO".into(),
            issues: vec![],
        }
    }

    #[test]
    fn single_pipeline_lifecycle() {
        let pipeline = PipelineBuilder::single(
            "test query",
            GptIntent::Analysis,
            GptPersona::DomainResearcher,
            0.5,
        );

        assert_eq!(pipeline.stages.len(), 1);
        assert_eq!(pipeline.mode, PipelineMode::Single);
        assert!(!pipeline.is_complete());

        let mut pipeline = pipeline;
        pipeline.mark_sent(0, "req-1".into());
        assert!(!pipeline.is_complete());

        pipeline.mark_completed("req-1", "Response text".into(), good_eval(), 500);
        assert!(pipeline.is_complete());

        let result = pipeline.merge_results().unwrap();
        assert_eq!(result.content, "Response text");
        assert_eq!(result.contributors, vec![GptPersona::DomainResearcher]);
    }

    #[test]
    fn consensus_pipeline_picks_best() {
        let mut pipeline = PipelineBuilder::consensus(
            "architecture question",
            GptIntent::Architecture,
            vec![GptPersona::DomainResearcher, GptPersona::DevilsAdvocate],
            0.8,
        );

        pipeline.mark_sent(0, "req-1".into());
        pipeline.mark_sent(1, "req-2".into());

        // DomainResearcher gives good answer
        pipeline.mark_completed("req-1", "Good analysis".into(), good_eval(), 500);
        // DevilsAdvocate gives bad answer
        pipeline.mark_completed("req-2", "Bad take".into(), bad_eval(), 600);

        assert!(pipeline.is_complete());
        let result = pipeline.merge_results().unwrap();
        assert!(result.content.contains("Good analysis"));
        assert_eq!(result.mode, PipelineMode::Consensus);
    }

    #[test]
    fn chain_pipeline_feeds_forward() {
        let mut pipeline = PipelineBuilder::chain(
            "generiši 20 imena",
            GptIntent::Creative,
            vec![
                (GptPersona::BulkGenerator, "generiši 20 imena"),
                (GptPersona::CreativeDirector, "izaberi top 5"),
            ],
            0.5,
        );

        assert_eq!(pipeline.stages.len(), 2);

        // First stage should be pending
        let pending = pipeline.next_pending_stage().unwrap();
        assert_eq!(pending.persona, GptPersona::BulkGenerator);

        pipeline.mark_sent(0, "req-1".into());

        // Second stage should NOT be pending (waiting for first)
        assert!(pipeline.next_pending_stage().is_none());

        // Complete first stage
        pipeline.mark_completed("req-1", "1. Name1\n2. Name2\n3. Name3".into(), good_eval(), 500);

        // Now second stage should be pending with modified query
        let next = pipeline.next_pending_stage().unwrap();
        assert_eq!(next.persona, GptPersona::CreativeDirector);
        assert!(next.query.contains("Name1"));

        pipeline.mark_sent(1, "req-2".into());
        pipeline.mark_completed("req-2", "Top 5: Name1 is best".into(), good_eval(), 400);

        let result = pipeline.merge_results().unwrap();
        assert!(result.content.contains("Top 5"));
        assert_eq!(result.contributors.len(), 2);
    }

    #[test]
    fn auto_pipeline_consensus_for_critical_architecture() {
        let pipeline = PipelineBuilder::auto(
            "novi audio graph dizajn",
            GptIntent::Architecture,
            GptPersona::DomainResearcher,
            0.9, // High urgency
        );

        assert_eq!(pipeline.mode, PipelineMode::Consensus);
        assert!(pipeline.stages.len() >= 2);
    }

    #[test]
    fn auto_pipeline_chain_for_creative_bulk() {
        let pipeline = PipelineBuilder::auto(
            "generiši 30 imena za plugin",
            GptIntent::Creative,
            GptPersona::BulkGenerator,
            0.5,
        );

        assert_eq!(pipeline.mode, PipelineMode::Chain);
        assert_eq!(pipeline.stages.len(), 2);
    }

    #[test]
    fn auto_pipeline_single_for_normal() {
        let pipeline = PipelineBuilder::auto(
            "šta je ovo?",
            GptIntent::UserQuery,
            GptPersona::DomainResearcher,
            0.5,
        );

        assert_eq!(pipeline.mode, PipelineMode::Single);
    }

    #[test]
    fn pipeline_manager_routes_responses() {
        let mut mgr = PipelineManager::new();

        let mut pipeline = PipelineBuilder::single(
            "test",
            GptIntent::Analysis,
            GptPersona::DomainResearcher,
            0.5,
        );
        // Mark stage as sent (simulates the bridge sending it)
        pipeline.mark_sent(0, "req-1".into());

        let pid = mgr.add(pipeline);

        // Register request-to-pipeline mapping
        mgr.register_request("req-1".into(), pid);

        // Simulate response
        let result = mgr.handle_response("req-1", "Response".into(), good_eval(), 500);
        assert!(result.is_some());
        assert_eq!(mgr.active_count(), 0);
        assert_eq!(mgr.recent_results().len(), 1);
    }
}
