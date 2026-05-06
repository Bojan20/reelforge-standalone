//! `FluxComposer` — the high-level pipeline that turns a free-text description
//! into a validated, compliance-checked `StageAssetMap` JSON.
//!
//! ## Pipeline
//!
//! ```text
//! user description ─┐
//!                   ▼
//!   ┌──────────────────────────────┐
//!   │ THEME_ANALYSIS  (pass 1)     │  → motifs, BPM, palette
//!   └──────────────────────────────┘
//!                   │
//!                   ▼
//!   ┌──────────────────────────────┐
//!   │ STAGE_ASSET_MAP  (pass 2)    │  → JSON map
//!   └──────────────────────────────┘
//!                   │
//!                   ▼
//!   ┌──────────────────────────────┐
//!   │ STRUCTURAL VALIDATION        │  → required stages, busses, ranges
//!   └──────────────────────────────┘
//!         │                  │
//!         │ pass             │ fail
//!         ▼                  ▼
//!   ┌──────────────┐  ┌─────────────────────────────────┐
//!   │ AUDIO_BRIEF  │  │ COMPLIANCE_REPAIR  (re-prompt)  │
//!   │  (pass 3)    │  │   up to N retries               │
//!   └──────────────┘  └─────────────────────────────────┘
//!         │                  │
//!         ▼                  └─→ back to validation
//!   ┌──────────────┐
//!   │ VOICE_DIR    │  (pass 4, only if VO assets present)
//!   └──────────────┘
//!         │
//!         ▼
//!   ┌──────────────┐
//!   │ QUALITY_GRADE│  (pass 5, self-score 0-100)
//!   └──────────────┘
//!         │
//!         ▼
//!   ComposerOutput
//! ```

use crate::prompts;
use crate::provider::{AiPrompt, AiProvider, AiProviderError};
use crate::schema::StageAssetMap;
use rf_rgai::Jurisdiction;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use thiserror::Error;
use uuid::Uuid;

/// Maximum number of `COMPLIANCE_REPAIR` re-prompts before the composer gives up.
const MAX_REPAIR_ATTEMPTS: u32 = 3;

/// Input for one composer job.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComposerJob {
    /// Free-text description from the user.
    pub description: String,

    /// Jurisdictions the asset map must satisfy.
    pub jurisdictions: Vec<Jurisdiction>,

    /// Whether to run the optional `AUDIO_BRIEF` markdown pass.
    #[serde(default = "default_true")]
    pub include_brief: bool,

    /// Whether to run the optional `VOICE_DIRECTION` pass (only if VO assets exist).
    #[serde(default = "default_true")]
    pub include_voice_direction: bool,

    /// Whether to run the optional `QUALITY_GRADE` self-assessment.
    #[serde(default = "default_true")]
    pub include_quality_grade: bool,
}

fn default_true() -> bool {
    true
}

/// Result of one composer job.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComposerOutput {
    /// Correlation ID for telemetry / logging.
    pub job_id: String,

    /// The validated `StageAssetMap`.
    pub asset_map: StageAssetMap,

    /// Markdown audio brief (None if disabled or generation failed).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audio_brief_markdown: Option<String>,

    /// Voice direction markdown table (None if no VO assets or disabled).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub voice_direction_markdown: Option<String>,

    /// Number of repair attempts that ran (0 = first try passed).
    pub repair_attempts: u32,

    /// Total tokens consumed across all passes.
    pub total_tokens_input: u32,
    /// Total output tokens.
    pub total_tokens_output: u32,
    /// Total wall-clock milliseconds across all passes.
    pub total_elapsed_ms: u32,
}

/// All errors a composer job can produce.
#[derive(Error, Debug)]
pub enum ComposerError {
    /// The provider failed during one of the passes.
    #[error("provider error in {pass}: {source}")]
    Provider {
        /// Which pass failed (THEME_ANALYSIS, STAGE_ASSET_MAP, etc.).
        pass: String,
        /// Underlying provider error.
        #[source]
        source: AiProviderError,
    },

    /// The provider returned text that was supposed to be JSON but wasn't parseable.
    #[error("malformed JSON in {pass}: {detail}")]
    MalformedJson {
        /// Pass name.
        pass: String,
        /// Detail (parse error or expected shape).
        detail: String,
    },

    /// Even after `MAX_REPAIR_ATTEMPTS` re-prompts the map still failed validation.
    #[error("compliance repair exhausted after {attempts} attempts; last violations: {last_violations:?}")]
    RepairExhausted {
        /// Number of attempts made.
        attempts: u32,
        /// Last set of violations.
        last_violations: Vec<String>,
    },
}

/// The composer. Holds an `Arc<dyn AiProvider>` so it can be moved into tasks.
pub struct FluxComposer {
    provider: Arc<dyn AiProvider>,
}

impl FluxComposer {
    /// Construct from an existing provider instance.
    pub fn new(provider: Arc<dyn AiProvider>) -> Self {
        Self { provider }
    }

    /// Underlying provider (for diagnostics / testing).
    pub fn provider(&self) -> &Arc<dyn AiProvider> {
        &self.provider
    }

    /// Run the full pipeline.
    pub async fn run(&self, job: ComposerJob) -> Result<ComposerOutput, ComposerError> {
        let job_id = Uuid::new_v4().to_string();
        let mut total_in = 0u32;
        let mut total_out = 0u32;
        let mut total_ms = 0u32;

        // ── Pass 1: THEME_ANALYSIS ────────────────────────────────────────────
        log::debug!("[{}] composer pass 1: theme analysis", job_id);
        let theme_prompt = AiPrompt::new(
            prompts::SYSTEM_BASE,
            prompts::theme_analysis_user(&job.description),
        )
        .with_temperature(0.5)
        .with_max_tokens(800)
        .with_schema(serde_json::json!({
            "type": "object",
            "required": ["theme", "mood", "target_bpm"],
            "properties": {
                "theme": { "type": "string" },
                "mood": { "type": "string" },
                "target_bpm": { "type": "integer" },
                "palette": { "type": "array", "items": { "type": "string" } },
                "authenticity_notes": { "type": "string" }
            }
        }));

        let theme_resp = self.provider.generate(&theme_prompt).await.map_err(|e| {
            ComposerError::Provider {
                pass: "THEME_ANALYSIS".to_string(),
                source: e,
            }
        })?;
        total_in += theme_resp.tokens_input;
        total_out += theme_resp.tokens_output;
        total_ms += theme_resp.elapsed_ms;

        let theme_json = theme_resp
            .json
            .clone()
            .or_else(|| serde_json::from_str::<serde_json::Value>(&theme_resp.text).ok())
            .ok_or_else(|| ComposerError::MalformedJson {
                pass: "THEME_ANALYSIS".to_string(),
                detail: format!("response was not JSON: {}", truncate(&theme_resp.text, 200)),
            })?;

        // ── Pass 2: STAGE_ASSET_MAP ───────────────────────────────────────────
        log::debug!("[{}] composer pass 2: stage asset map", job_id);
        let jur_codes: Vec<String> = job
            .jurisdictions
            .iter()
            .map(|j| j.code().to_string())
            .collect();

        let mut current_map = self
            .request_asset_map(&job.description, &theme_json, &jur_codes, &mut total_in, &mut total_out, &mut total_ms)
            .await?;

        // ── Pass 2.5: STRUCTURAL VALIDATION + REPAIR LOOP ─────────────────────
        let mut repair_attempts = 0u32;
        loop {
            match current_map.validate() {
                Ok(()) => break,
                Err(violations) => {
                    if repair_attempts >= MAX_REPAIR_ATTEMPTS {
                        return Err(ComposerError::RepairExhausted {
                            attempts: repair_attempts,
                            last_violations: violations,
                        });
                    }
                    log::info!(
                        "[{}] compliance repair attempt {}/{}: {} violations",
                        job_id,
                        repair_attempts + 1,
                        MAX_REPAIR_ATTEMPTS,
                        violations.len()
                    );
                    let missing = current_map.missing_required_stages();
                    let repair_prompt = AiPrompt::new(
                        prompts::SYSTEM_BASE,
                        prompts::compliance_repair_user(&current_map, &violations, &missing),
                    )
                    .with_schema(StageAssetMap::json_schema())
                    .with_temperature(0.2);

                    let repair_resp = self.provider.generate(&repair_prompt).await.map_err(|e| {
                        ComposerError::Provider {
                            pass: "COMPLIANCE_REPAIR".to_string(),
                            source: e,
                        }
                    })?;
                    total_in += repair_resp.tokens_input;
                    total_out += repair_resp.tokens_output;
                    total_ms += repair_resp.elapsed_ms;

                    current_map = parse_asset_map(&repair_resp.text, repair_resp.json.as_ref())?;
                    repair_attempts += 1;
                }
            }
        }

        // ── Pass 3: AUDIO_BRIEF (optional) ────────────────────────────────────
        let audio_brief_markdown = if job.include_brief {
            log::debug!("[{}] composer pass 3: audio brief", job_id);
            let brief_prompt = AiPrompt::new(
                prompts::SYSTEM_BASE,
                prompts::audio_brief_user(&current_map),
            )
            .with_temperature(0.4)
            .with_max_tokens(2400);
            match self.provider.generate(&brief_prompt).await {
                Ok(r) => {
                    total_in += r.tokens_input;
                    total_out += r.tokens_output;
                    total_ms += r.elapsed_ms;
                    Some(r.text)
                }
                Err(e) => {
                    log::warn!("[{}] AUDIO_BRIEF failed (continuing): {}", job_id, e);
                    None
                }
            }
        } else {
            None
        };

        // ── Pass 4: VOICE_DIRECTION (optional, only if VO present) ────────────
        let has_vo = current_map
            .stages
            .iter()
            .any(|s| s.assets.iter().any(|a| a.kind == "vo"));
        let voice_direction_markdown = if job.include_voice_direction && has_vo {
            log::debug!("[{}] composer pass 4: voice direction", job_id);
            let vo_prompt = AiPrompt::new(
                prompts::SYSTEM_BASE,
                prompts::voice_direction_user(&current_map),
            )
            .with_temperature(0.5)
            .with_max_tokens(1600);
            match self.provider.generate(&vo_prompt).await {
                Ok(r) => {
                    total_in += r.tokens_input;
                    total_out += r.tokens_output;
                    total_ms += r.elapsed_ms;
                    Some(r.text)
                }
                Err(e) => {
                    log::warn!("[{}] VOICE_DIRECTION failed (continuing): {}", job_id, e);
                    None
                }
            }
        } else {
            None
        };

        // ── Pass 5: QUALITY_GRADE (optional) ──────────────────────────────────
        if job.include_quality_grade {
            log::debug!("[{}] composer pass 5: quality grade", job_id);
            let grade_prompt = AiPrompt::new(
                prompts::SYSTEM_BASE,
                prompts::quality_grade_user(&current_map),
            )
            .with_temperature(0.1)
            .with_max_tokens(400)
            .with_schema(serde_json::json!({
                "type": "object",
                "required": ["score", "critique"],
                "properties": {
                    "score": { "type": "integer", "minimum": 0, "maximum": 100 },
                    "critique": { "type": "string" }
                }
            }));
            if let Ok(r) = self.provider.generate(&grade_prompt).await {
                total_in += r.tokens_input;
                total_out += r.tokens_output;
                total_ms += r.elapsed_ms;
                if let Some(parsed) = r
                    .json
                    .clone()
                    .or_else(|| serde_json::from_str(&r.text).ok())
                {
                    if let Some(score) = parsed.get("score").and_then(|v| v.as_u64()) {
                        current_map.self_quality_score = score.min(100) as u8;
                    }
                    if let Some(crit) = parsed.get("critique").and_then(|v| v.as_str()) {
                        current_map.self_critique = crit.to_string();
                    }
                }
            }
        }

        Ok(ComposerOutput {
            job_id,
            asset_map: current_map,
            audio_brief_markdown,
            voice_direction_markdown,
            repair_attempts,
            total_tokens_input: total_in,
            total_tokens_output: total_out,
            total_elapsed_ms: total_ms,
        })
    }

    async fn request_asset_map(
        &self,
        description: &str,
        theme_json: &serde_json::Value,
        jurisdictions: &[String],
        total_in: &mut u32,
        total_out: &mut u32,
        total_ms: &mut u32,
    ) -> Result<StageAssetMap, ComposerError> {
        let prompt = AiPrompt::new(
            prompts::SYSTEM_BASE,
            prompts::stage_asset_map_user(description, theme_json, jurisdictions),
        )
        .with_schema(StageAssetMap::json_schema())
        .with_temperature(0.45)
        .with_max_tokens(6000);

        let resp = self
            .provider
            .generate(&prompt)
            .await
            .map_err(|e| ComposerError::Provider {
                pass: "STAGE_ASSET_MAP".to_string(),
                source: e,
            })?;
        *total_in += resp.tokens_input;
        *total_out += resp.tokens_output;
        *total_ms += resp.elapsed_ms;

        parse_asset_map(&resp.text, resp.json.as_ref())
    }
}

fn parse_asset_map(
    text: &str,
    pre_parsed: Option<&serde_json::Value>,
) -> Result<StageAssetMap, ComposerError> {
    if let Some(v) = pre_parsed {
        if let Ok(map) = serde_json::from_value::<StageAssetMap>(v.clone()) {
            return Ok(map);
        }
    }
    serde_json::from_str::<StageAssetMap>(text).map_err(|e| ComposerError::MalformedJson {
        pass: "STAGE_ASSET_MAP".to_string(),
        detail: format!("{}: {}", e, truncate(text, 200)),
    })
}

fn truncate(s: &str, n: usize) -> String {
    if s.chars().count() <= n {
        s.to_string()
    } else {
        let mut out: String = s.chars().take(n).collect();
        out.push('…');
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::provider::{
        AiProviderId, AiResponse, AiResult, ProviderCapabilities,
    };
    use async_trait::async_trait;
    use parking_lot::Mutex;
    use std::sync::Arc;

    /// Mock provider that returns scripted responses in order.
    struct MockProvider {
        scripts: Mutex<Vec<String>>,
    }

    impl MockProvider {
        fn new(scripts: Vec<&str>) -> Self {
            Self {
                scripts: Mutex::new(scripts.into_iter().map(String::from).collect()),
            }
        }
    }

    #[async_trait]
    impl AiProvider for MockProvider {
        fn id(&self) -> AiProviderId {
            AiProviderId::Ollama
        }
        fn capabilities(&self) -> ProviderCapabilities {
            ProviderCapabilities {
                streaming: false,
                structured_output: true,
                air_gapped: true,
                max_context_tokens: 8192,
                cost_per_1m_input_usd: 0.0,
            }
        }
        fn model(&self) -> &str {
            "mock"
        }
        fn endpoint(&self) -> &str {
            "mock://"
        }
        async fn health_check(&self) -> AiResult<()> {
            Ok(())
        }
        async fn generate(&self, _p: &AiPrompt) -> AiResult<AiResponse> {
            let mut s = self.scripts.lock();
            if s.is_empty() {
                return Err(AiProviderError::Other(anyhow::anyhow!("no more scripts")));
            }
            let text = s.remove(0);
            let json = serde_json::from_str(&text).ok();
            Ok(AiResponse {
                text,
                json,
                tokens_input: 100,
                tokens_output: 100,
                elapsed_ms: 10,
                model_used: "mock".to_string(),
            })
        }
    }

    fn make_full_map_json() -> String {
        let stages: Vec<serde_json::Value> = StageAssetMap::required_stage_ids()
            .iter()
            .map(|id| {
                serde_json::json!({
                    "stage_id": id,
                    "assets": [{
                        "kind": "oneshot",
                        "suggested_name": format!("{}_default", id.to_lowercase()),
                        "mood": "neutral",
                        "dynamic_level": 50,
                        "length_ms": 1000,
                        "bus": "sfx",
                        "generation_prompt": "neutral oneshot"
                    }]
                })
            })
            .collect();

        serde_json::to_string(&serde_json::json!({
            "theme": "test_theme",
            "mood": "neutral",
            "target_bpm": 120,
            "stages": stages,
            "compliance_hints": {
                "target_jurisdictions": ["UKGC"],
                "ldw_audio_suppressed": true,
                "proportional_celebrations": true,
                "near_miss_neutralized": true,
                "reviewer_notes": "ok"
            }
        }))
        .unwrap()
    }

    #[tokio::test]
    async fn happy_path_completes_in_one_try() {
        let theme = r#"{"theme":"test_theme","mood":"neutral","target_bpm":120}"#.to_string();
        let asset_map = make_full_map_json();
        let brief = "# Brief\nSome text".to_string();
        let grade = r#"{"score":85,"critique":"solid"}"#.to_string();

        let provider = Arc::new(MockProvider::new(vec![
            &theme, &asset_map, &brief, &grade,
        ])) as Arc<dyn AiProvider>;
        let composer = FluxComposer::new(provider);

        let job = ComposerJob {
            description: "test".to_string(),
            jurisdictions: vec![Jurisdiction::Ukgc],
            include_brief: true,
            include_voice_direction: false, // no VO assets in our minimal map
            include_quality_grade: true,
        };

        let out = composer.run(job).await.unwrap();
        assert_eq!(out.repair_attempts, 0);
        assert_eq!(out.asset_map.theme, "test_theme");
        assert_eq!(out.asset_map.self_quality_score, 85);
        assert!(out.audio_brief_markdown.is_some());
        assert!(out.voice_direction_markdown.is_none());
    }

    #[tokio::test]
    async fn repair_loop_fixes_missing_stage() {
        // First map missing BIG_WIN; second map (after repair) is complete.
        let theme = r#"{"theme":"x","mood":"y","target_bpm":120}"#.to_string();

        // Build a broken map (missing BIG_WIN)
        let broken_stages: Vec<serde_json::Value> = StageAssetMap::required_stage_ids()
            .iter()
            .filter(|id| **id != "BIG_WIN")
            .map(|id| {
                serde_json::json!({
                    "stage_id": id,
                    "assets": [{
                        "kind": "oneshot",
                        "suggested_name": "x",
                        "mood": "neutral",
                        "dynamic_level": 50,
                        "bus": "sfx",
                        "generation_prompt": "x"
                    }]
                })
            })
            .collect();
        let broken = serde_json::to_string(&serde_json::json!({
            "theme":"x","mood":"y","target_bpm":120,
            "stages":broken_stages,
            "compliance_hints":{
                "target_jurisdictions":["UKGC"],
                "ldw_audio_suppressed":true,
                "proportional_celebrations":true,
                "near_miss_neutralized":true,
                "reviewer_notes":""
            }
        }))
        .unwrap();

        let fixed = make_full_map_json();

        let provider = Arc::new(MockProvider::new(vec![
            &theme, &broken, &fixed,
        ])) as Arc<dyn AiProvider>;
        let composer = FluxComposer::new(provider);

        let job = ComposerJob {
            description: "x".to_string(),
            jurisdictions: vec![Jurisdiction::Ukgc],
            include_brief: false,
            include_voice_direction: false,
            include_quality_grade: false,
        };

        let out = composer.run(job).await.unwrap();
        assert_eq!(out.repair_attempts, 1);
    }

    #[tokio::test]
    async fn repair_exhausted_after_max_attempts() {
        let theme = r#"{"theme":"x","mood":"y","target_bpm":120}"#.to_string();

        // Always-broken map (missing all required stages)
        let broken = r#"{"theme":"x","mood":"y","target_bpm":120,"stages":[],"compliance_hints":{"target_jurisdictions":["UKGC"],"ldw_audio_suppressed":false,"proportional_celebrations":false,"near_miss_neutralized":false,"reviewer_notes":""}}"#.to_string();

        // Need: theme + 1 initial map + MAX_REPAIR_ATTEMPTS repairs
        let scripts = vec![
            theme.as_str(),
            broken.as_str(),
            broken.as_str(),
            broken.as_str(),
            broken.as_str(),
        ];

        let provider =
            Arc::new(MockProvider::new(scripts)) as Arc<dyn AiProvider>;
        let composer = FluxComposer::new(provider);

        let job = ComposerJob {
            description: "x".to_string(),
            jurisdictions: vec![Jurisdiction::Ukgc],
            include_brief: false,
            include_voice_direction: false,
            include_quality_grade: false,
        };

        match composer.run(job).await {
            Err(ComposerError::RepairExhausted { attempts, .. }) => {
                assert_eq!(attempts, MAX_REPAIR_ATTEMPTS);
            }
            other => panic!("expected RepairExhausted, got {:?}", other.is_ok()),
        }
    }

    #[tokio::test]
    async fn malformed_initial_response_is_error() {
        let provider = Arc::new(MockProvider::new(vec![
            "this is not json at all",
        ])) as Arc<dyn AiProvider>;
        let composer = FluxComposer::new(provider);

        let job = ComposerJob {
            description: "x".to_string(),
            jurisdictions: vec![Jurisdiction::Ukgc],
            include_brief: false,
            include_voice_direction: false,
            include_quality_grade: false,
        };

        match composer.run(job).await {
            Err(ComposerError::MalformedJson { pass, .. }) => {
                assert_eq!(pass, "THEME_ANALYSIS");
            }
            other => panic!("expected MalformedJson, got {:?}", other.is_ok()),
        }
    }
}
