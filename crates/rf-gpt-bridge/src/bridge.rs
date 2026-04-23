// file: crates/rf-gpt-bridge/src/bridge.rs
//! GptBridge — the neural pathway between CORTEX and ChatGPT Browser.
//!
//! Replaces the old OpenAI API approach with a WebSocket bridge to the browser.
//! ChatGPT runs in the browser — no API key needed. Corti talks to it directly.
//!
//! Flow:
//! 1. CORTEX signal/pattern → DecisionEngine evaluates
//! 2. If approved → format query → send via WebSocket to browser
//! 3. Tampermonkey script types into ChatGPT → sends response back
//! 4. Response arrives as BrowserEvent → converted to NeuralSignal
//!
//! The bridge NEVER blocks the CORTEX tick loop.

use crate::config::GptBridgeConfig;
use crate::conversation::ConversationMemory;
use crate::decision::{DecisionEngine, DecisionStats, GptDecision};
use crate::evaluator::ResponseEvaluator;
use crate::pipeline::{PipelineBuilder, PipelineManager};
use crate::protocol::{
    BrowserCommand, BrowserEvent, GptIntent, GptResponse,
};
use crate::roles::{GptPersona, RoleSelector};
use crate::websocket::WsServer;
use chrono::Utc;
use crossbeam_channel::{Receiver, Sender};
use parking_lot::Mutex;
use rf_cortex::signal::{NeuralSignal, SignalKind, SignalOrigin, SignalUrgency};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Instant;

/// A GPT response ready to be injected into CORTEX as a NeuralSignal.
#[derive(Debug)]
pub struct GptSignalPayload {
    pub signal: NeuralSignal,
    pub response: GptResponse,
}

/// Bridge statistics.
#[derive(Debug, Clone)]
pub struct BridgeStats {
    pub total_requests: u64,
    pub total_responses: u64,
    pub total_errors: u64,
    pub browser_connected: bool,
    pub browser_model: Option<String>,
    pub ping_latency_ms: i64,
    pub decision_stats: DecisionStats,
    pub conversation_exchanges: usize,
    pub active_pipelines: usize,
    pub total_pipeline_results: usize,
    pub accepted_responses: u64,
    pub rejected_responses: u64,
}

/// The GPT Browser Bridge.
pub struct GptBridge {
    /// WebSocket server for browser communication.
    ws_server: Mutex<WsServer>,
    /// Decision engine — determines when to consult GPT.
    decision_engine: Mutex<DecisionEngine>,
    /// Conversation memory — maintains context.
    conversation: Mutex<ConversationMemory>,
    /// Role selector — picks the best persona for each query.
    role_selector: Mutex<RoleSelector>,
    /// Response evaluator — quality gate for GPT responses.
    evaluator: ResponseEvaluator,
    /// Pipeline manager — orchestrates multi-role queries.
    pipeline_manager: Mutex<PipelineManager>,
    /// Pending requests awaiting browser response (id → request metadata).
    pending_requests: Mutex<HashMap<String, PendingRequest>>,
    /// Channel for outbound payloads (processed responses ready for CORTEX).
    payload_tx: Sender<GptSignalPayload>,
    payload_rx: Receiver<GptSignalPayload>,
    /// Shared counters.
    total_requests: Arc<AtomicU64>,
    total_responses: Arc<AtomicU64>,
    total_errors: Arc<AtomicU64>,
    accepted_responses: Arc<AtomicU64>,
    rejected_responses: Arc<AtomicU64>,
    /// Shutdown flag.
    shutdown: Arc<AtomicBool>,
    /// Config.
    config: Mutex<GptBridgeConfig>,
    /// Tokio runtime (owned if we created it).
    _tokio_runtime: Option<tokio::runtime::Runtime>,
}

/// Metadata for a pending request.
struct PendingRequest {
    intent: GptIntent,
    persona: Option<GptPersona>,
    query: String,
    sent_at: Instant,
}

impl GptBridge {
    /// Create and start the GPT Browser Bridge.
    pub fn new(config: GptBridgeConfig) -> Self {
        let (payload_tx, payload_rx) = crossbeam_channel::bounded(64);

        let conversation = ConversationMemory::new(
            &config.system_prompt,
            config.max_conversation_history,
        );

        let decision_engine = DecisionEngine::new(&config);
        let role_selector = RoleSelector::new();
        let evaluator = ResponseEvaluator::new().with_threshold(config.quality_threshold);
        let pipeline_manager = PipelineManager::new();

        let mut ws_server = WsServer::new();

        // Get or create tokio runtime
        let (tokio_handle, tokio_runtime) = match tokio::runtime::Handle::try_current() {
            Ok(handle) => (handle, None),
            Err(_) => {
                let rt = tokio::runtime::Builder::new_multi_thread()
                    .worker_threads(2)
                    .thread_name("gpt-browser-bridge")
                    .enable_all()
                    .build()
                    .expect("Failed to create GPT bridge tokio runtime");
                let handle = rt.handle().clone();
                (handle, Some(rt))
            }
        };

        // Start WebSocket server
        let addr = config
            .ws_addr()
            .parse()
            .unwrap_or_else(|_| "127.0.0.1:9742".parse().unwrap());
        ws_server.start(addr, &tokio_handle);

        Self {
            ws_server: Mutex::new(ws_server),
            decision_engine: Mutex::new(decision_engine),
            conversation: Mutex::new(conversation),
            role_selector: Mutex::new(role_selector),
            evaluator,
            pipeline_manager: Mutex::new(pipeline_manager),
            pending_requests: Mutex::new(HashMap::new()),
            payload_tx,
            payload_rx,
            total_requests: Arc::new(AtomicU64::new(0)),
            total_responses: Arc::new(AtomicU64::new(0)),
            total_errors: Arc::new(AtomicU64::new(0)),
            accepted_responses: Arc::new(AtomicU64::new(0)),
            rejected_responses: Arc::new(AtomicU64::new(0)),
            shutdown: Arc::new(AtomicBool::new(false)),
            config: Mutex::new(config),
            _tokio_runtime: tokio_runtime,
        }
    }

    /// Process a signal through the decision engine.
    /// If the decision engine says "query GPT", sends via WebSocket to browser.
    pub fn process_signal(&self, signal: &NeuralSignal) -> GptDecision {
        let decision = self.decision_engine.lock().evaluate_signal(signal);

        if decision.should_query {
            // Resolve persona: decision might suggest one, or RoleSelector decides
            let persona = decision.persona.unwrap_or_else(|| {
                self.role_selector.lock().select(decision.intent, &decision.query)
            });

            if decision.use_pipeline {
                self.send_pipeline_query(
                    &decision.query,
                    &decision.context,
                    decision.intent,
                    persona,
                    decision.urgency,
                );
            } else {
                self.send_query_with_role(
                    &decision.query,
                    &decision.context,
                    decision.intent,
                    persona,
                    decision.urgency,
                );
            }
        }

        decision
    }

    /// Process a recognized pattern through the decision engine.
    pub fn process_pattern(&self, name: &str, severity: f32, description: &str) -> GptDecision {
        let decision = self
            .decision_engine
            .lock()
            .evaluate_pattern(name, severity, description);

        if decision.should_query {
            let persona = decision.persona.unwrap_or_else(|| {
                self.role_selector.lock().select(decision.intent, &decision.query)
            });

            if decision.use_pipeline {
                self.send_pipeline_query(
                    &decision.query,
                    &decision.context,
                    decision.intent,
                    persona,
                    decision.urgency,
                );
            } else {
                self.send_query_with_role(
                    &decision.query,
                    &decision.context,
                    decision.intent,
                    persona,
                    decision.urgency,
                );
            }
        }

        decision
    }

    /// Send a query to ChatGPT via the browser bridge (legacy API — uses auto role selection).
    pub fn send_query(&self, query: &str, context: &str, intent: GptIntent, urgency: f32) {
        let persona = self.role_selector.lock().select(intent, query);
        self.send_query_with_role(query, context, intent, persona, urgency);
    }

    /// Send a query with a specific role/persona.
    pub fn send_query_with_role(
        &self,
        query: &str,
        context: &str,
        intent: GptIntent,
        persona: GptPersona,
        urgency: f32,
    ) {
        if self.shutdown.load(Ordering::Relaxed) {
            log::warn!("GPT Browser Bridge: shut down, ignoring query");
            return;
        }

        let ws = self.ws_server.lock();
        if !ws.is_browser_connected() {
            log::warn!("GPT Browser Bridge: no browser connected, query will be lost");
            self.total_errors.fetch_add(1, Ordering::Relaxed);
            return;
        }

        let role_def = persona.definition();

        // Build full message with role-specific system prompt + context
        let full_content = if context.is_empty() {
            query.to_string()
        } else {
            format!("{}\n\n[Kontekst]: {}", query, context)
        };

        // Prepend role-specific system prompt for first message or always for important roles
        let conv = self.conversation.lock();
        let content = if conv.exchange_count() == 0 || urgency > 0.7 {
            format!(
                "[TVOJA ULOGA — pročitaj ali ne ponavljaj ovo u odgovoru]\n{}\n\n---\n\n{}",
                role_def.system_prompt, full_content
            )
        } else {
            full_content
        };
        drop(conv);

        let request_id = uuid::Uuid::new_v4().to_string();

        let cmd = BrowserCommand::Query {
            id: request_id.clone(),
            content,
            intent: intent.as_str().to_string(),
            urgency,
            role: Some(persona.as_str().to_string()),
            pipeline_id: None,
        };

        match ws.send_command(cmd) {
            Ok(()) => {
                self.total_requests.fetch_add(1, Ordering::Relaxed);

                self.pending_requests.lock().insert(
                    request_id.clone(),
                    PendingRequest {
                        intent,
                        persona: Some(persona),
                        query: query.to_string(),
                        sent_at: Instant::now(),
                    },
                );

                log::info!(
                    "GPT Browser Bridge: query sent — id={}, intent={:?}, persona={}",
                    request_id,
                    intent,
                    persona.display_name()
                );
            }
            Err(e) => {
                self.total_errors.fetch_add(1, Ordering::Relaxed);
                log::error!("GPT Browser Bridge: failed to send query: {}", e);
            }
        }
    }

    /// Send a pipeline query (multi-role).
    pub fn send_pipeline_query(
        &self,
        query: &str,
        context: &str,
        intent: GptIntent,
        primary_persona: GptPersona,
        urgency: f32,
    ) {
        let full_query = if context.is_empty() {
            query.to_string()
        } else {
            format!("{}\n\n[Kontekst]: {}", query, context)
        };

        let pipeline = PipelineBuilder::auto(&full_query, intent, primary_persona, urgency);
        let pipeline_id = pipeline.id.clone();

        // Get all pending stages and send them
        let stages_to_send: Vec<(usize, GptPersona, String, f32)> = pipeline
            .all_pending_stages()
            .iter()
            .map(|s| (s.index, s.persona, s.query.clone(), s.urgency))
            .collect();

        let mut mgr = self.pipeline_manager.lock();
        let pid = mgr.add(pipeline);

        for (stage_idx, persona, stage_query, stage_urgency) in stages_to_send {
            let role_def = persona.definition();
            let request_id = uuid::Uuid::new_v4().to_string();

            let content = format!(
                "[TVOJA ULOGA — pročitaj ali ne ponavljaj ovo u odgovoru]\n{}\n\n---\n\n{}",
                role_def.system_prompt, stage_query
            );

            let ws = self.ws_server.lock();
            let cmd = BrowserCommand::Query {
                id: request_id.clone(),
                content,
                intent: intent.as_str().to_string(),
                urgency: stage_urgency,
                role: Some(persona.as_str().to_string()),
                pipeline_id: Some(pipeline_id.clone()),
            };

            if let Ok(()) = ws.send_command(cmd) {
                self.total_requests.fetch_add(1, Ordering::Relaxed);

                self.pending_requests.lock().insert(
                    request_id.clone(),
                    PendingRequest {
                        intent,
                        persona: Some(persona),
                        query: stage_query,
                        sent_at: Instant::now(),
                    },
                );

                // Update pipeline stage state
                if let Some(p) = mgr.active.get_mut(&pid) {
                    p.mark_sent(stage_idx, request_id.clone());
                }

                mgr.register_request(request_id, pid.clone());

                log::info!(
                    "GPT Browser Bridge: pipeline stage sent — pipeline={}, stage={}, persona={}",
                    pipeline_id,
                    stage_idx,
                    persona.display_name()
                );
            }
        }
    }

    /// Poll for browser events and convert to NeuralSignal payloads.
    /// Called from CORTEX tick loop. Now includes quality evaluation and pipeline routing.
    pub fn drain_responses(&self) -> Vec<GptSignalPayload> {
        let ws = self.ws_server.lock();
        let events = ws.drain_events();
        drop(ws);

        for event in events {
            match event {
                BrowserEvent::Response {
                    id,
                    content,
                    streaming,
                } => {
                    if streaming {
                        continue;
                    }

                    let pending = self.pending_requests.lock().remove(&id);
                    let (intent, persona, query, latency_ms) = match pending {
                        Some(p) => (p.intent, p.persona, p.query, p.sent_at.elapsed().as_millis() as u64),
                        None => (GptIntent::Insight, None, String::new(), 0),
                    };

                    // Evaluate response quality
                    let eval_persona = persona.unwrap_or(GptPersona::DomainResearcher);
                    let evaluation = self.evaluator.evaluate(&content, &query, eval_persona, intent);

                    log::info!(
                        "GPT Browser Bridge: response evaluated — id={}, persona={}, quality={:.2}, accepted={}",
                        id,
                        eval_persona.display_name(),
                        evaluation.quality,
                        evaluation.accepted
                    );

                    // Update role performance tracking
                    self.role_selector.lock().record_performance(
                        eval_persona,
                        evaluation.quality,
                        evaluation.accepted,
                        latency_ms,
                    );

                    if evaluation.accepted {
                        self.accepted_responses.fetch_add(1, Ordering::Relaxed);
                    } else {
                        self.rejected_responses.fetch_add(1, Ordering::Relaxed);
                    }

                    // Check if this is part of a pipeline
                    let pipeline_result = {
                        let mut mgr = self.pipeline_manager.lock();
                        mgr.handle_response(&id, content.clone(), evaluation.clone(), latency_ms)
                    };

                    if let Some(result) = pipeline_result {
                        // Pipeline complete — emit merged result
                        let response = GptResponse {
                            request_id: result.pipeline_id.clone(),
                            content: result.content.clone(),
                            model: self.ws_server.lock().browser_info()
                                .and_then(|i| i.model)
                                .unwrap_or_else(|| "ChatGPT-Browser".into()),
                            latency_ms: result.total_latency_ms,
                            received_at: Utc::now(),
                            from_browser: true,
                            persona: Some(result.contributors.iter().map(|p| p.as_str()).collect::<Vec<_>>().join("+")),
                            pipeline_id: Some(result.pipeline_id),
                        };

                        self.conversation.lock().record(
                            query,
                            result.content,
                            intent,
                            0,
                            result.quality as f32,
                        );

                        self.decision_engine.lock().record_query_sent(0);
                        self.total_responses.fetch_add(1, Ordering::Relaxed);

                        let signal = Self::response_to_signal(&response, intent);
                        let _ = self.payload_tx.try_send(GptSignalPayload { signal, response });
                    } else if evaluation.accepted {
                        // Single query — accepted, emit directly
                        let browser_model = self.ws_server.lock().browser_info()
                            .and_then(|i| i.model)
                            .unwrap_or_else(|| "ChatGPT-Browser".into());

                        let response = GptResponse {
                            request_id: id,
                            content: content.clone(),
                            model: browser_model,
                            latency_ms,
                            received_at: Utc::now(),
                            from_browser: true,
                            persona: persona.map(|p| p.as_str().to_string()),
                            pipeline_id: None,
                        };

                        // Record with quality-based importance (accepted = higher importance)
                        self.conversation.lock().record(
                            query,
                            content,
                            intent,
                            0,
                            evaluation.quality as f32,
                        );

                        self.decision_engine.lock().record_query_sent(0);
                        self.total_responses.fetch_add(1, Ordering::Relaxed);

                        let signal = Self::response_to_signal(&response, intent);
                        let _ = self.payload_tx.try_send(GptSignalPayload { signal, response });
                    } else {
                        // Rejected by evaluator — log but don't emit as signal
                        log::warn!(
                            "GPT Browser Bridge: response rejected — id={}, verdict={}",
                            id,
                            evaluation.verdict
                        );
                        self.total_responses.fetch_add(1, Ordering::Relaxed);

                        // Still record in conversation memory with low importance
                        self.conversation.lock().record(
                            query,
                            content,
                            intent,
                            0,
                            0.1, // Low importance — rejected
                        );
                    }
                }

                BrowserEvent::Error { id, message, code } => {
                    self.total_errors.fetch_add(1, Ordering::Relaxed);
                    log::error!(
                        "GPT Browser Bridge: browser error — code={}, msg={}, id={:?}",
                        code,
                        message,
                        id
                    );

                    if let Some(request_id) = id {
                        self.pending_requests.lock().remove(&request_id);

                        // Notify pipeline manager if applicable
                        {
                            let mut mgr = self.pipeline_manager.lock();
                            mgr.handle_failure(&request_id, format!("[{}] {}", code, message));
                        }

                        let error_signal = NeuralSignal::new(
                            SignalOrigin::Gpt,
                            SignalUrgency::Elevated,
                            SignalKind::GptRequestFailed {
                                request_id: request_id.clone(),
                                error: format!("[{}] {}", code, message),
                            },
                        );

                        let payload = GptSignalPayload {
                            signal: error_signal,
                            response: GptResponse {
                                request_id,
                                content: String::new(),
                                model: String::new(),
                                latency_ms: 0,
                                received_at: Utc::now(),
                                from_browser: true,
                                persona: None,
                                pipeline_id: None,
                            },
                        };

                        let _ = self.payload_tx.try_send(payload);
                    }
                }

                BrowserEvent::Busy { id } => {
                    log::warn!("GPT Browser Bridge: ChatGPT busy, request {} will retry", id);
                }

                BrowserEvent::Connected { .. }
                | BrowserEvent::Pong { .. }
                | BrowserEvent::ChatCleared
                | BrowserEvent::Status { .. } => {
                    // Handled by WsServer internally
                }
            }
        }

        // Drain processed payloads
        let mut payloads = Vec::new();
        while let Ok(payload) = self.payload_rx.try_recv() {
            payloads.push(payload);
        }

        // Process pipeline stages that need sending (chain mode — next stage after completion)
        {
            let mgr = self.pipeline_manager.lock();
            #[allow(clippy::type_complexity)]
            let pending_stages: Vec<(String, Vec<(usize, GptPersona, String, f32)>)> = mgr
                .stages_to_send()
                .iter()
                .map(|(pid, stages)| {
                    let stage_data: Vec<_> = stages
                        .iter()
                        .map(|s| (s.index, s.persona, s.query.clone(), s.urgency))
                        .collect();
                    (pid.to_string(), stage_data)
                })
                .collect();
            drop(mgr);

            for (pipeline_id, stages) in pending_stages {
                for (stage_idx, persona, stage_query, stage_urgency) in stages {
                    let role_def = persona.definition();
                    let request_id = uuid::Uuid::new_v4().to_string();

                    let content = format!(
                        "[TVOJA ULOGA — pročitaj ali ne ponavljaj ovo u odgovoru]\n{}\n\n---\n\n{}",
                        role_def.system_prompt, stage_query
                    );

                    let ws = self.ws_server.lock();
                    let cmd = BrowserCommand::Query {
                        id: request_id.clone(),
                        content,
                        intent: "analysis".to_string(),
                        urgency: stage_urgency,
                        role: Some(persona.as_str().to_string()),
                        pipeline_id: Some(pipeline_id.clone()),
                    };

                    if let Ok(()) = ws.send_command(cmd) {
                        self.total_requests.fetch_add(1, Ordering::Relaxed);

                        self.pending_requests.lock().insert(
                            request_id.clone(),
                            PendingRequest {
                                intent: GptIntent::Analysis,
                                persona: Some(persona),
                                query: stage_query,
                                sent_at: Instant::now(),
                            },
                        );

                        let mut mgr = self.pipeline_manager.lock();
                        if let Some(p) = mgr.active.get_mut(&pipeline_id) {
                            p.mark_sent(stage_idx, request_id.clone());
                        }
                        mgr.register_request(request_id, pipeline_id.clone());

                        log::info!(
                            "GPT Browser Bridge: pipeline stage sent — pipeline={}, stage={}, persona={}",
                            pipeline_id,
                            stage_idx,
                            persona.display_name()
                        );
                    }
                }
            }
        }

        // Timeout stale requests
        let timeout_secs = self.config.lock().response_timeout_secs;
        let mut pending = self.pending_requests.lock();
        let stale: Vec<String> = pending
            .iter()
            .filter(|(_, p)| p.sent_at.elapsed().as_secs() > timeout_secs)
            .map(|(id, _)| id.clone())
            .collect();

        for id in stale {
            if let Some(_req) = pending.remove(&id) {
                log::warn!("GPT Browser Bridge: request {} timed out", id);
                self.total_errors.fetch_add(1, Ordering::Relaxed);

                // Notify pipeline manager
                {
                    let mut mgr = self.pipeline_manager.lock();
                    mgr.handle_failure(&id, format!("Timeout after {}s", timeout_secs));
                }

                let timeout_signal = NeuralSignal::new(
                    SignalOrigin::Gpt,
                    SignalUrgency::Normal,
                    SignalKind::GptRequestFailed {
                        request_id: id.clone(),
                        error: format!("Timeout after {}s", timeout_secs),
                    },
                );

                let payload = GptSignalPayload {
                    signal: timeout_signal,
                    response: GptResponse {
                        request_id: id,
                        content: String::new(),
                        model: String::new(),
                        latency_ms: timeout_secs * 1000,
                        received_at: Utc::now(),
                        from_browser: true,
                        persona: None,
                        pipeline_id: None,
                    },
                };

                payloads.push(payload);
            }
        }

        payloads
    }

    /// Get bridge statistics.
    pub fn stats(&self) -> BridgeStats {
        let ws = self.ws_server.lock();
        let browser_info = ws.browser_info();
        let mgr = self.pipeline_manager.lock();

        BridgeStats {
            total_requests: self.total_requests.load(Ordering::Relaxed),
            total_responses: self.total_responses.load(Ordering::Relaxed),
            total_errors: self.total_errors.load(Ordering::Relaxed),
            browser_connected: ws.is_browser_connected(),
            browser_model: browser_info.and_then(|i| i.model),
            ping_latency_ms: ws.last_ping_latency_ms.load(Ordering::Relaxed),
            decision_stats: self.decision_engine.lock().stats(),
            conversation_exchanges: self.conversation.lock().exchange_count(),
            active_pipelines: mgr.active_count(),
            total_pipeline_results: mgr.recent_results().len(),
            accepted_responses: self.accepted_responses.load(Ordering::Relaxed),
            rejected_responses: self.rejected_responses.load(Ordering::Relaxed),
        }
    }

    /// Get role performance data.
    pub fn role_performance(&self) -> crate::roles::RolePerformance {
        self.role_selector.lock().performance().clone()
    }

    /// Get a clone of the current configuration.
    pub fn current_config(&self) -> GptBridgeConfig {
        self.config.lock().clone()
    }

    /// Update configuration at runtime.
    pub fn update_config(&self, config: GptBridgeConfig) {
        self.conversation
            .lock()
            .set_system_prompt(&config.system_prompt);
        self.decision_engine.lock().update_config(&config);
        *self.config.lock() = config;
    }

    /// Is the bridge ready? (WS server running, doesn't require browser to be connected).
    pub fn is_ready(&self) -> bool {
        !self.shutdown.load(Ordering::Relaxed)
    }

    /// Is the browser actually connected right now?
    pub fn is_browser_connected(&self) -> bool {
        self.ws_server.lock().is_browser_connected()
    }

    /// Shutdown the bridge gracefully.
    pub fn shutdown(&self) {
        self.shutdown.store(true, Ordering::Relaxed);
        self.ws_server.lock().shutdown();
        log::info!("GPT Browser Bridge: shutting down");
    }

    /// Clear conversation memory.
    pub fn clear_conversation(&self) {
        self.conversation.lock().clear();
        // Also tell browser to start new chat
        let _ = self.ws_server.lock().send_command(BrowserCommand::NewChat);
    }

    fn response_to_signal(response: &GptResponse, intent: GptIntent) -> NeuralSignal {
        let urgency = match intent {
            GptIntent::Debugging | GptIntent::UserQuery => SignalUrgency::Elevated,
            GptIntent::Analysis | GptIntent::Architecture => SignalUrgency::Normal,
            _ => SignalUrgency::Ambient,
        };

        let kind = SignalKind::GptInsight {
            topic: format!("{:?}", intent),
            insight: response.content.clone(),
            confidence: 0.8, // Browser responses are complete (no truncation)
        };

        NeuralSignal::new(SignalOrigin::Gpt, urgency, kind)
    }
}

impl Drop for GptBridge {
    fn drop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        self.ws_server.lock().shutdown();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bridge_creates_and_is_ready() {
        let bridge = GptBridge::new(GptBridgeConfig::default());
        assert!(bridge.is_ready());
        assert!(!bridge.is_browser_connected()); // No browser yet
    }

    #[test]
    fn bridge_skips_normal_signals() {
        let bridge = GptBridge::new(GptBridgeConfig::default());
        let signal = NeuralSignal::new(
            SignalOrigin::AudioEngine,
            SignalUrgency::Normal,
            SignalKind::Heartbeat,
        );

        let decision = bridge.process_signal(&signal);
        assert!(!decision.should_query);
    }

    #[test]
    fn bridge_shutdown_stops_queries() {
        let bridge = GptBridge::new(GptBridgeConfig::default());
        bridge.shutdown();
        assert!(!bridge.is_ready());
    }

    #[test]
    fn drain_returns_empty_when_no_responses() {
        let bridge = GptBridge::new(GptBridgeConfig::default());
        let payloads = bridge.drain_responses();
        assert!(payloads.is_empty());
    }

    #[test]
    fn stats_work() {
        let bridge = GptBridge::new(GptBridgeConfig::default());
        let stats = bridge.stats();
        assert_eq!(stats.total_requests, 0);
        assert_eq!(stats.total_responses, 0);
        assert!(!stats.browser_connected);
    }

    #[test]
    fn conversation_clears() {
        let bridge = GptBridge::new(GptBridgeConfig::default());
        bridge.clear_conversation();
        assert_eq!(bridge.stats().conversation_exchanges, 0);
    }

    #[test]
    fn custom_port_config() {
        let mut config = GptBridgeConfig::default();
        config.ws_port = 9999;
        assert_eq!(config.ws_addr(), "127.0.0.1:9999");
        assert!(config.is_ready());
    }
}
