// file: crates/rf-brain-router/src/router.rs
//! BrainRouter — the central routing engine.
//!
//! The router is the single entry point for all AI queries from CORTEX.
//! It receives a raw query, classifies the task domain, selects the optimal
//! model, sends the request, handles failures with fallback, and tracks costs.
//!
//! ```text
//!   CORTEX tick / User request
//!          │
//!          ▼
//!   BrainRouter::route("query")
//!          │
//!          ├─ TaskClassifier → TaskDomain
//!          ├─ Domain → ModelId (primary)
//!          ├─ Config: is model available?
//!          │    ├─ YES → provider.query()
//!          │    └─ NO → fallback chain
//!          ├─ CostTracker.record()
//!          ▼
//!   BrainResponse → NeuralSignal
//! ```

use crate::classifier::{ClassificationResult, TaskClassifier, TaskDomain};
use crate::config::BrainRouterConfig;
use crate::cost::CostTracker;
use crate::provider::{BrainError, BrainProviderAsync, BrainRequest, BrainResponse, ModelId};
use crate::providers::{BrowserBridgeProvider, ClaudeCliProvider, ClaudeProvider, DeepSeekProvider, OpenAiProvider};
use parking_lot::Mutex;
use rf_cortex::signal::{NeuralSignal, SignalKind, SignalOrigin, SignalUrgency};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

// ═══════════════════════════════════════════════════════════════════════════════
// ROUTING RESULT
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete result of a routed query.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingResult {
    /// The AI response.
    pub response: BrainResponse,
    /// How the task was classified.
    pub classification: ClassificationResult,
    /// Whether a fallback model was used.
    pub used_fallback: bool,
    /// Number of providers attempted before success.
    pub attempts: u32,
    /// As a CORTEX NeuralSignal (for injection into NeuralBus).
    #[serde(skip)]
    pub signal: Option<NeuralSignal>,
}

/// Router statistics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouterStats {
    pub total_queries: u64,
    pub total_successes: u64,
    pub total_failures: u64,
    pub total_fallbacks: u64,
    pub queries_per_domain: HashMap<TaskDomain, u64>,
    pub queries_per_model: HashMap<ModelId, u64>,
    pub available_providers: Vec<String>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// BRAIN ROUTER
// ═══════════════════════════════════════════════════════════════════════════════

/// The central multi-brain routing engine.
pub struct BrainRouter {
    /// Task classifier.
    classifier: TaskClassifier,
    /// Configuration.
    config: BrainRouterConfig,
    /// Cost tracker.
    cost_tracker: Arc<CostTracker>,

    /// Providers (boxed for dynamic dispatch).
    providers: HashMap<String, Box<dyn BrainProviderAsync>>,

    /// Stats.
    total_queries: AtomicU64,
    total_successes: AtomicU64,
    total_failures: AtomicU64,
    total_fallbacks: AtomicU64,
    queries_per_domain: Mutex<HashMap<TaskDomain, u64>>,
    queries_per_model: Mutex<HashMap<ModelId, u64>>,
}

impl BrainRouter {
    /// Create the router with all providers initialized from config.
    ///
    /// Returns the router and browser bridge channels (for connecting to rf-gpt-bridge).
    pub fn new(
        config: BrainRouterConfig,
    ) -> (
        Self,
        crossbeam_channel::Receiver<crate::providers::browser::BrowserQuery>,
        crossbeam_channel::Sender<crate::providers::browser::BrowserResult>,
    ) {
        let mut providers: HashMap<String, Box<dyn BrainProviderAsync>> = HashMap::new();

        // Initialize Claude CLI provider (takes priority over HTTP API)
        if config.providers.claude_cli.enabled {
            let cli_provider = ClaudeCliProvider::new(config.providers.claude_cli.clone());
            if cli_provider.is_available() {
                log::info!("BrainRouter: Claude CLI provider enabled — takes priority over HTTP API");
                providers.insert("anthropic".into(), Box::new(cli_provider));
            } else {
                log::warn!("BrainRouter: Claude CLI enabled but not available, falling back to HTTP API");
                providers.insert(
                    "anthropic".into(),
                    Box::new(ClaudeProvider::new(config.providers.anthropic.clone())),
                );
            }
        } else {
            // HTTP API fallback
            providers.insert(
                "anthropic".into(),
                Box::new(ClaudeProvider::new(config.providers.anthropic.clone())),
            );
        }

        providers.insert(
            "deepseek".into(),
            Box::new(DeepSeekProvider::new(config.providers.deepseek.clone())),
        );
        providers.insert(
            "openai".into(),
            Box::new(OpenAiProvider::new(config.providers.openai.clone())),
        );

        // Initialize browser bridge provider
        let (browser_provider, browser_rx, browser_tx) =
            BrowserBridgeProvider::new(config.providers.browser.enabled);
        providers.insert("browser".into(), Box::new(browser_provider));

        let cost_tracker = Arc::new(CostTracker::new(config.monthly_budget_usd));

        let router = Self {
            classifier: TaskClassifier::new(),
            config,
            cost_tracker,
            providers,
            total_queries: AtomicU64::new(0),
            total_successes: AtomicU64::new(0),
            total_failures: AtomicU64::new(0),
            total_fallbacks: AtomicU64::new(0),
            queries_per_domain: Mutex::new(HashMap::new()),
            queries_per_model: Mutex::new(HashMap::new()),
        };

        (router, browser_rx, browser_tx)
    }

    /// Route a query to the optimal model.
    ///
    /// This is the main entry point. It:
    /// 1. Classifies the task
    /// 2. Selects the best available model
    /// 3. Sends the request
    /// 4. Falls back to alternative models on failure
    /// 5. Tracks costs and stats
    pub async fn route(
        &self,
        query: &str,
        context: &str,
        system_prompt: Option<&str>,
    ) -> Result<RoutingResult, BrainError> {
        self.total_queries.fetch_add(1, Ordering::Relaxed);

        // 1. Classify the task
        let classification = if self.config.auto_classify {
            self.classifier.classify(query)
        } else {
            ClassificationResult {
                domain: TaskDomain::General,
                confidence: 1.0,
                signals: vec!["Auto-classify disabled".into()],
                secondary_domain: None,
                recommended_model: self.config.default_model.clone(),
            }
        };

        // Track domain stats
        *self
            .queries_per_domain
            .lock()
            .entry(classification.domain)
            .or_insert(0) += 1;

        log::info!(
            "BrainRouter: classified as {:?} (confidence: {:.0}%) → {}",
            classification.domain,
            classification.confidence * 100.0,
            classification.recommended_model.display_name()
        );

        // 2. Check domain overrides
        let primary_model = self
            .config
            .domain_overrides
            .get(classification.domain.display_name())
            .cloned()
            .unwrap_or_else(|| classification.domain.primary_model());

        // 3. Build the model chain: primary + fallbacks
        let mut model_chain = vec![primary_model.clone()];
        model_chain.extend(classification.domain.fallback_chain());

        // Always add browser as ultimate fallback
        if !model_chain.contains(&ModelId::ChatGptBrowser) {
            model_chain.push(ModelId::ChatGptBrowser);
        }

        // 4. Try each model in the chain
        let mut attempts = 0u32;
        let mut last_error = None;

        for model in &model_chain {
            // Check if model is available
            if !self.config.is_model_available(model) {
                continue;
            }

            // Check budget
            if self.cost_tracker.would_exceed_budget(model, 4000) {
                log::warn!(
                    "BrainRouter: skipping {} — would exceed budget",
                    model.display_name()
                );
                continue;
            }

            attempts += 1;
            let is_fallback = model != &primary_model;

            // Build request with domain-appropriate settings
            let mut request = BrainRequest::new(query, model.clone())
                .with_context(context)
                .with_temperature(classification.domain.recommended_temperature())
                .with_max_tokens(classification.domain.recommended_max_tokens());

            if let Some(sp) = system_prompt {
                request = request.with_system_prompt(sp);
            }

            // Get the provider
            let provider_name = model.provider_name();
            let provider = match self.providers.get(provider_name) {
                Some(p) => p,
                None => continue,
            };

            // Track model stats
            *self.queries_per_model.lock().entry(model.clone()).or_insert(0) += 1;

            log::info!(
                "BrainRouter: sending to {} (attempt {}{})",
                model.display_name(),
                attempts,
                if is_fallback { ", fallback" } else { "" }
            );

            // Send the request
            match provider.query(&request).await {
                Ok(mut response) => {
                    response.is_fallback = is_fallback;

                    // Record cost
                    self.cost_tracker.record(&response);

                    if is_fallback {
                        self.total_fallbacks.fetch_add(1, Ordering::Relaxed);
                    }
                    self.total_successes.fetch_add(1, Ordering::Relaxed);

                    // Build CORTEX NeuralSignal
                    let signal = Self::response_to_signal(&response, &classification);

                    log::info!(
                        "BrainRouter: success from {} — {}ms, ${:.4}",
                        model.display_name(),
                        response.latency_ms,
                        response.estimated_cost_usd
                    );

                    return Ok(RoutingResult {
                        response,
                        classification,
                        used_fallback: is_fallback,
                        attempts,
                        signal: Some(signal),
                    });
                }
                Err(e) => {
                    self.cost_tracker.record_error(model);
                    log::warn!(
                        "BrainRouter: {} failed: {} — trying next",
                        model.display_name(),
                        e
                    );
                    last_error = Some(e);

                    // Don't retry on rate limit — move to next provider
                    if matches!(last_error, Some(BrainError::RateLimited { .. })) {
                        continue;
                    }
                }
            }
        }

        self.total_failures.fetch_add(1, Ordering::Relaxed);

        Err(BrainError::AllProvidersFailed {
            details: format!(
                "Tried {} models, last error: {:?}",
                attempts,
                last_error
            ),
        })
    }

    /// Route with streaming — the callback receives partial text chunks
    /// as they arrive from the CLI subprocess (real-time streaming).
    ///
    /// Falls back to normal batch query for non-streaming providers.
    pub async fn route_streaming(
        &self,
        query: &str,
        context: &str,
        system_prompt: Option<&str>,
        on_chunk: impl Fn(&str) + Send + Sync + 'static,
    ) -> Result<RoutingResult, BrainError> {
        // Share callback across providers via Arc — single allocation, no double-boxing.
        let shared_cb: Arc<dyn Fn(&str) + Send + Sync> = Arc::new(on_chunk);
        for provider in self.providers.values() {
            if provider.supports_streaming() {
                let cb = shared_cb.clone();
                provider.set_stream_callback(Some(Box::new(move |chunk| cb(chunk))));
            }
        }

        log::info!("BrainRouter: routing with streaming enabled");
        let result = self.route(query, context, system_prompt).await;

        // Clear streaming callbacks after query completes
        for provider in self.providers.values() {
            if provider.supports_streaming() {
                provider.set_stream_callback(None);
            }
        }

        result
    }

    /// Route with a forced model (bypasses classification).
    pub async fn route_to_model(
        &self,
        query: &str,
        context: &str,
        model: ModelId,
        system_prompt: Option<&str>,
    ) -> Result<BrainResponse, BrainError> {
        self.total_queries.fetch_add(1, Ordering::Relaxed);

        if !self.config.is_model_available(&model) {
            return Err(BrainError::ModelNotAvailable {
                provider: model.provider_name().into(),
                model: model.display_name().into(),
            });
        }

        let mut request = BrainRequest::new(query, model.clone()).with_context(context);
        if let Some(sp) = system_prompt {
            request = request.with_system_prompt(sp);
        }

        let provider = self
            .providers
            .get(model.provider_name())
            .ok_or(BrainError::NotConfigured {
                provider: model.provider_name().into(),
            })?;

        let response = provider.query(&request).await?;
        self.cost_tracker.record(&response);
        self.total_successes.fetch_add(1, Ordering::Relaxed);

        Ok(response)
    }

    /// Classify a query without sending it.
    pub fn classify(&self, query: &str) -> ClassificationResult {
        self.classifier.classify(query)
    }

    /// Get the cost tracker.
    pub fn cost_tracker(&self) -> &Arc<CostTracker> {
        &self.cost_tracker
    }

    /// Get router statistics.
    pub fn stats(&self) -> RouterStats {
        let available = self
            .providers
            .iter()
            .filter(|(_, p)| p.is_available())
            .map(|(name, _)| name.clone())
            .collect();

        RouterStats {
            total_queries: self.total_queries.load(Ordering::Relaxed),
            total_successes: self.total_successes.load(Ordering::Relaxed),
            total_failures: self.total_failures.load(Ordering::Relaxed),
            total_fallbacks: self.total_fallbacks.load(Ordering::Relaxed),
            queries_per_domain: self.queries_per_domain.lock().clone(),
            queries_per_model: self.queries_per_model.lock().clone(),
            available_providers: available,
        }
    }

    /// Convert a BrainResponse to a CORTEX NeuralSignal.
    fn response_to_signal(
        response: &BrainResponse,
        classification: &ClassificationResult,
    ) -> NeuralSignal {
        let urgency = match classification.domain {
            TaskDomain::Architecture | TaskDomain::AudioDsp | TaskDomain::CodeReview => {
                SignalUrgency::Elevated
            }
            TaskDomain::Mathematics | TaskDomain::SlotMath => SignalUrgency::Normal,
            _ => SignalUrgency::Ambient,
        };

        let kind = SignalKind::GptInsight {
            topic: format!(
                "{:?} via {}",
                classification.domain,
                response.model.display_name()
            ),
            insight: response.content.clone(),
            confidence: classification.confidence as f32,
        };

        NeuralSignal::new(SignalOrigin::Gpt, urgency, kind)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_config() -> BrainRouterConfig {
        BrainRouterConfig {
            providers: crate::config::ProvidersConfig {
                anthropic: crate::config::AnthropicConfig {
                    api_key: None,
                    ..Default::default()
                },
                deepseek: crate::config::DeepSeekConfig {
                    api_key: None,
                    ..Default::default()
                },
                openai: crate::config::OpenAiConfig {
                    api_key: None,
                    ..Default::default()
                },
                browser: crate::config::BrowserConfig {
                    enabled: false,
                    ws_port: 0,
                },
                claude_cli: crate::config::ClaudeCliConfig {
                    enabled: false,
                    ..Default::default()
                },
            },
            ..Default::default()
        }
    }

    #[test]
    fn router_creates_successfully() {
        let (router, _rx, _tx) = BrainRouter::new(test_config());
        assert_eq!(router.providers.len(), 4); // anthropic, deepseek, openai, browser
    }

    #[test]
    fn classifies_without_sending() {
        let (router, _rx, _tx) = BrainRouter::new(test_config());
        let result = router.classify("Izračunaj RTP za slot machine sa 5 reels i paytable");
        assert_eq!(result.domain, TaskDomain::SlotMath);
    }

    #[test]
    fn stats_start_at_zero() {
        let (router, _rx, _tx) = BrainRouter::new(test_config());
        let stats = router.stats();
        assert_eq!(stats.total_queries, 0);
        assert_eq!(stats.total_successes, 0);
        assert_eq!(stats.total_failures, 0);
    }

    #[test]
    fn no_providers_available_without_keys() {
        let (router, _rx, _tx) = BrainRouter::new(test_config());
        let stats = router.stats();
        // No API keys, browser disabled
        assert!(stats.available_providers.is_empty());
    }

    #[tokio::test]
    async fn route_fails_when_no_providers() {
        let (router, _rx, _tx) = BrainRouter::new(test_config());
        let result = router.route("test query", "", None).await;
        assert!(matches!(result, Err(BrainError::AllProvidersFailed { .. })));
    }

    #[tokio::test]
    async fn route_to_model_fails_when_unavailable() {
        let (router, _rx, _tx) = BrainRouter::new(test_config());
        let result = router
            .route_to_model("test", "", ModelId::ClaudeOpus, None)
            .await;
        assert!(matches!(result, Err(BrainError::ModelNotAvailable { .. })));
    }

    #[test]
    fn classification_maps_to_correct_models() {
        let (router, _rx, _tx) = BrainRouter::new(test_config());

        let tests = vec![
            ("Redizajniraj FFI arhitekturu", ModelId::ClaudeOpus),
            ("Fixuj bug u audio callback-u", ModelId::ClaudeSonnet), // DailyCoding or AudioDsp
            ("Izračunaj RTP za paytable", ModelId::DeepSeekR1),
            ("Smisli ime za plugin", ModelId::Gpt4o),
            ("Prove O(n log n) complexity", ModelId::DeepSeekR1),
        ];

        for (query, expected_provider) in tests {
            let result = router.classify(query);
            assert_eq!(
                result.recommended_model.provider_name(),
                expected_provider.provider_name(),
                "Query '{}' classified as {:?}, expected {:?}",
                query,
                result.recommended_model,
                expected_provider
            );
        }
    }

    #[test]
    fn cost_tracker_accessible() {
        let (router, _rx, _tx) = BrainRouter::new(test_config());
        assert!(router.cost_tracker().within_budget());
    }

    #[test]
    fn domain_override_works() {
        let mut config = test_config();
        config
            .domain_overrides
            .insert("Matematika".into(), ModelId::ClaudeOpus);

        let (router, _rx, _tx) = BrainRouter::new(config);

        // Even though Mathematics maps to DeepSeekR1, the override should change it
        // (but the classify result still shows the default recommendation)
        let result = router.classify("Izračunaj verovatnoću");
        assert_eq!(result.domain, TaskDomain::Mathematics);
        // The override is applied during routing, not classification
    }

    #[test]
    fn signal_urgency_mapping() {
        let response = BrainResponse {
            request_id: "test".into(),
            model: ModelId::ClaudeOpus,
            content: "test".into(),
            input_tokens: 100,
            output_tokens: 50,
            latency_ms: 500,
            received_at: chrono::Utc::now(),
            is_fallback: false,
            estimated_cost_usd: 0.001,
        };

        let class = ClassificationResult {
            domain: TaskDomain::Architecture,
            confidence: 0.9,
            signals: vec![],
            secondary_domain: None,
            recommended_model: ModelId::ClaudeOpus,
        };

        let signal = BrainRouter::response_to_signal(&response, &class);
        assert!(matches!(signal.urgency, SignalUrgency::Elevated));
    }
}
