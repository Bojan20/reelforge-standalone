// file: crates/rf-brain-router/src/providers/browser.rs
//! Browser Bridge Provider — wraps the existing rf-gpt-bridge for zero-cost fallback.
//!
//! When no API keys are available, queries go through the ChatGPT browser bridge
//! (Tampermonkey script + WebSocket). This is the ultimate fallback — it's free,
//! but requires the browser to be open with ChatGPT.
//!
//! This provider doesn't directly depend on rf-gpt-bridge — it communicates
//! via a crossbeam channel that the bridge monitors. This keeps the dependency
//! graph clean and allows the router to work without the bridge compiled in.

use crate::provider::{BrainError, BrainProviderAsync, BrainRequest, BrainResponse, ModelId};
use chrono::Utc;
use crossbeam_channel::{Receiver, Sender};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

/// Message sent to the browser bridge.
#[derive(Debug, Clone)]
pub struct BrowserQuery {
    pub id: String,
    pub content: String,
}

/// Response received from the browser bridge.
#[derive(Debug, Clone)]
pub struct BrowserResult {
    pub id: String,
    pub content: String,
    pub model: Option<String>,
}

/// Browser bridge provider — zero-cost ChatGPT fallback.
pub struct BrowserBridgeProvider {
    /// Channel to send queries to the bridge.
    query_tx: Sender<BrowserQuery>,
    /// Channel to receive responses from the bridge.
    response_rx: Receiver<BrowserResult>,
    /// Pending requests waiting for response.
    pending: Arc<Mutex<HashMap<String, tokio::sync::oneshot::Sender<BrowserResult>>>>,
    /// Is the browser connected?
    browser_connected: Arc<AtomicBool>,
    /// Is the bridge enabled?
    enabled: AtomicBool,
}

impl BrowserBridgeProvider {
    /// Create a new browser bridge provider.
    ///
    /// Returns the provider and a pair of channels that the rf-gpt-bridge
    /// should connect to:
    /// - `query_rx`: bridge reads queries from here
    /// - `response_tx`: bridge writes responses here
    pub fn new(
        enabled: bool,
    ) -> (
        Self,
        Receiver<BrowserQuery>,
        Sender<BrowserResult>,
    ) {
        let (query_tx, query_rx) = crossbeam_channel::bounded(64);
        let (response_tx, response_rx) = crossbeam_channel::bounded(64);

        let provider = Self {
            query_tx,
            response_rx,
            pending: Arc::new(Mutex::new(HashMap::new())),
            browser_connected: Arc::new(AtomicBool::new(false)),
            enabled: AtomicBool::new(enabled),
        };

        // Spawn background task to route responses to pending waiters
        let pending_clone = provider.pending.clone();
        let rx_clone = provider.response_rx.clone();
        std::thread::Builder::new()
            .name("brain-browser-response-router".into())
            .spawn(move || {
                while let Ok(result) = rx_clone.recv() {
                    let mut pending = pending_clone.lock();
                    if let Some(sender) = pending.remove(&result.id) {
                        let _ = sender.send(result);
                    }
                }
            })
            .ok();

        (provider, query_rx, response_tx)
    }

    /// Set browser connection status (called by rf-gpt-bridge).
    pub fn set_browser_connected(&self, connected: bool) {
        self.browser_connected.store(connected, Ordering::Relaxed);
    }

    async fn do_query(&self, request: &BrainRequest) -> Result<BrainResponse, BrainError> {
        if !self.enabled.load(Ordering::Relaxed) {
            return Err(BrainError::NotConfigured {
                provider: "browser".into(),
            });
        }

        if !self.browser_connected.load(Ordering::Relaxed) {
            return Err(BrainError::BrowserNotConnected);
        }

        let query = BrowserQuery {
            id: request.id.clone(),
            content: if request.context.is_empty() {
                request.query.clone()
            } else {
                format!("{}\n\n[Kontekst]: {}", request.query, request.context)
            },
        };

        // Create oneshot channel for this request's response
        let (tx, rx) = tokio::sync::oneshot::channel();
        self.pending.lock().insert(request.id.clone(), tx);

        let start = std::time::Instant::now();

        // Send query to bridge
        self.query_tx.try_send(query).map_err(|_| BrainError::ApiError {
            provider: "browser".into(),
            status: 503,
            message: "Browser bridge queue full".into(),
        })?;

        // Wait for response with timeout
        let timeout = tokio::time::Duration::from_secs(120);
        let result = tokio::time::timeout(timeout, rx)
            .await
            .map_err(|_| BrainError::Timeout {
                provider: "browser".into(),
                timeout_ms: 120_000,
            })?
            .map_err(|_| BrainError::ApiError {
                provider: "browser".into(),
                status: 500,
                message: "Response channel closed".into(),
            })?;

        let latency_ms = start.elapsed().as_millis() as u64;

        // Estimate tokens (rough: 4 chars per token)
        let input_tokens = (request.query.len() as u64 + request.context.len() as u64) / 4;
        let output_tokens = result.content.len() as u64 / 4;

        Ok(BrainResponse {
            request_id: request.id.clone(),
            model: ModelId::ChatGptBrowser,
            content: result.content,
            input_tokens,
            output_tokens,
            latency_ms,
            received_at: Utc::now(),
            is_fallback: true, // Browser is always a fallback
            estimated_cost_usd: 0.0, // Free
        })
    }
}

impl BrainProviderAsync for BrowserBridgeProvider {
    fn name(&self) -> &str {
        "browser"
    }

    fn supported_models(&self) -> &[ModelId] {
        &[ModelId::ChatGptBrowser]
    }

    fn is_available(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
            && self.browser_connected.load(Ordering::Relaxed)
    }

    fn query<'a>(
        &'a self,
        request: &'a BrainRequest,
    ) -> Pin<Box<dyn Future<Output = Result<BrainResponse, BrainError>> + Send + 'a>> {
        Box::pin(self.do_query(request))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn not_available_when_disconnected() {
        let (provider, _rx, _tx) = BrowserBridgeProvider::new(true);
        assert!(!provider.is_available()); // No browser connected
    }

    #[test]
    fn available_when_connected() {
        let (provider, _rx, _tx) = BrowserBridgeProvider::new(true);
        provider.set_browser_connected(true);
        assert!(provider.is_available());
    }

    #[test]
    fn not_available_when_disabled() {
        let (provider, _rx, _tx) = BrowserBridgeProvider::new(false);
        provider.set_browser_connected(true);
        assert!(!provider.is_available());
    }

    #[test]
    fn supported_models() {
        let (provider, _rx, _tx) = BrowserBridgeProvider::new(true);
        assert_eq!(provider.supported_models(), &[ModelId::ChatGptBrowser]);
    }

    #[tokio::test]
    async fn query_fails_when_disconnected() {
        let (provider, _rx, _tx) = BrowserBridgeProvider::new(true);
        let request = BrainRequest::new("test", ModelId::ChatGptBrowser);

        let result = provider.do_query(&request).await;
        assert!(matches!(result, Err(BrainError::BrowserNotConnected)));
    }
}
