// file: crates/rf-brain-router/src/providers/claude_cli.rs
//! Claude CLI Provider — spawns `claude` CLI subprocess for queries.
//!
//! Uses Claude Code CLI instead of HTTP API:
//! - Full 1M context with session continuity (--resume/--session-id)
//! - Real-time streaming via --output-format stream-json
//! - No API key management (CLI handles its own auth)
//! - Same model access as Claude Code in VS Code

use crate::config::ClaudeCliConfig;
use crate::provider::{BrainError, BrainProviderAsync, BrainRequest, BrainResponse, ModelId};
use chrono::Utc;
use parking_lot::Mutex;
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

/// Callback type for streaming chunks.
/// Receives partial text as it arrives from CLI.
pub type StreamCallback = Box<dyn Fn(&str) + Send + Sync>;

/// Claude CLI provider — spawns subprocess per query.
///
/// Maintains session IDs per model for conversation continuity.
/// Each model gets its own session so context doesn't bleed.
pub struct ClaudeCliProvider {
    config: ClaudeCliConfig,
    available: AtomicBool,
    /// Session IDs per model — enables --resume for context continuity.
    session_ids: Mutex<HashMap<ModelId, String>>,
    /// Optional streaming callback for real-time chunks.
    stream_callback: Mutex<Option<StreamCallback>>,
}

impl ClaudeCliProvider {
    pub fn new(config: ClaudeCliConfig) -> Self {
        // Check if CLI binary exists
        let available = std::process::Command::new(&config.cli_path)
            .arg("--version")
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);

        if !available {
            log::warn!(
                "ClaudeCliProvider: '{}' not found or not executable",
                config.cli_path
            );
        } else {
            log::info!("ClaudeCliProvider: CLI available at '{}'", config.cli_path);
        }

        Self {
            config,
            available: AtomicBool::new(available),
            session_ids: Mutex::new(HashMap::new()),
            stream_callback: Mutex::new(None),
        }
    }

    /// Set the streaming callback. Called with each partial text chunk.
    pub fn set_stream_callback(&self, callback: StreamCallback) {
        *self.stream_callback.lock() = Some(callback);
    }

    /// Get the session ID for a model, or None for first query.
    fn session_id_for(&self, model: &ModelId) -> Option<String> {
        self.session_ids.lock().get(model).cloned()
    }

    /// Store session ID after successful query.
    fn store_session_id(&self, model: &ModelId, session_id: String) {
        self.session_ids.lock().insert(model.clone(), session_id);
    }

    /// Build CLI command arguments.
    fn build_args(&self, request: &BrainRequest) -> Vec<String> {
        let mut args = Vec::new();

        // Non-interactive mode
        args.push("-p".into());

        // Streaming JSON output with partial messages
        args.push("--output-format".into());
        args.push("stream-json".into());
        args.push("--include-partial-messages".into());

        // Model selection
        let model_str = match &request.model {
            ModelId::ClaudeOpus => "opus",
            ModelId::ClaudeSonnet => "sonnet",
            _ => "sonnet", // Default for non-Claude models routed here
        };
        args.push("--model".into());
        args.push(model_str.into());

        // Session continuity — resume previous conversation for same model
        if let Some(session_id) = self.session_id_for(&request.model) {
            args.push("--resume".into());
            args.push(session_id);
        }

        // System prompt
        if let Some(ref system) = request.system_prompt {
            args.push("--system-prompt".into());
            args.push(system.clone());
        }

        // Max tokens budget (approximate conversion to USD)
        if self.config.max_budget_per_query_usd > 0.0 {
            args.push("--max-budget-usd".into());
            args.push(format!("{:.2}", self.config.max_budget_per_query_usd));
        }

        // Bare mode for daemon queries (skip hooks, LSP, etc.)
        if self.config.bare_mode {
            args.push("--bare".into());
        }

        // Permission mode
        if !self.config.permission_mode.is_empty() {
            args.push("--permission-mode".into());
            args.push(self.config.permission_mode.clone());
        }

        // Additional directories for tool access
        for dir in &self.config.additional_dirs {
            args.push("--add-dir".into());
            args.push(dir.clone());
        }

        // The actual prompt — build from context + query
        let prompt = if request.context.is_empty() {
            request.query.clone()
        } else {
            format!("[Kontekst]: {}\n\n{}", request.context, request.query)
        };
        args.push(prompt);

        args
    }

    /// Execute CLI subprocess and collect streaming response.
    async fn do_query(&self, request: &BrainRequest) -> Result<BrainResponse, BrainError> {
        let args = self.build_args(request);
        let timeout_duration =
            tokio::time::Duration::from_secs(self.config.timeout_secs);

        log::info!(
            "ClaudeCliProvider: spawning '{}' with model={}, session={:?}, timeout={}s",
            self.config.cli_path,
            request.model.display_name(),
            self.session_id_for(&request.model),
            self.config.timeout_secs,
        );

        let start = std::time::Instant::now();

        // Spawn CLI process
        let mut child = Command::new(&self.config.cli_path)
            .args(&args)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .stdin(std::process::Stdio::null())
            .kill_on_drop(true)
            .spawn()
            .map_err(|e| BrainError::Network {
                message: format!("Failed to spawn claude CLI: {}", e),
            })?;

        let stdout = child.stdout.take().ok_or(BrainError::Network {
            message: "No stdout from claude CLI".into(),
        })?;

        // Capture stderr in background with timeout to prevent indefinite blocking.
        // stderr is only used for error diagnostics — cap at 30s or 64KB.
        let stderr = child.stderr.take();
        let stderr_timeout = timeout_duration; // same as main timeout
        let stderr_handle = tokio::spawn(async move {
            if let Some(stderr) = stderr {
                let mut reader = BufReader::new(stderr);
                let mut buf = String::new();
                match tokio::time::timeout(stderr_timeout, async {
                    // Read up to 64KB to prevent memory issues
                    let mut tmp = vec![0u8; 65536];
                    loop {
                        match tokio::io::AsyncReadExt::read(&mut reader, &mut tmp).await {
                            Ok(0) => break,
                            Ok(n) => {
                                if let Ok(s) = std::str::from_utf8(&tmp[..n]) {
                                    buf.push_str(s);
                                }
                                if buf.len() >= 65536 {
                                    break;
                                }
                            }
                            Err(_) => break,
                        }
                    }
                }).await {
                    Ok(()) => buf,
                    Err(_) => {
                        if buf.is_empty() {
                            "[stderr read timed out]".to_string()
                        } else {
                            buf
                        }
                    }
                }
            } else {
                String::new()
            }
        });

        let mut reader = BufReader::new(stdout).lines();
        let mut full_content = String::new();
        let mut session_id: Option<String> = None;
        let mut input_tokens: u64 = 0;
        let mut output_tokens: u64 = 0;

        // Track whether we've seen cumulative "assistant" events.
        // If so, ignore content_block_delta to prevent text duplication.
        // --include-partial-messages sends cumulative "assistant" events;
        // content_block_delta sends incremental deltas — mixing both corrupts full_content.
        let mut seen_assistant_content = false;

        // Read streaming JSON lines with timeout
        let stream_result = tokio::time::timeout(timeout_duration, async {
            while let Ok(Some(line)) = reader.next_line().await {
                if line.trim().is_empty() {
                    continue;
                }

                // Parse each JSON event
                let event: serde_json::Value = match serde_json::from_str(&line) {
                    Ok(v) => v,
                    Err(_) => continue, // Skip malformed lines
                };

                let event_type = event["type"].as_str().unwrap_or("");

                match event_type {
                    // Session info — capture session_id for resumption
                    "system" => {
                        if let Some(sid) = event["session_id"].as_str() {
                            session_id = Some(sid.to_string());
                        }
                    }

                    // Partial message — cumulative text (from --include-partial-messages)
                    "assistant" => {
                        if let Some(text) = event["message"]["content"]
                            .as_array()
                            .and_then(|arr| arr.last())
                            .and_then(|block| block["text"].as_str())
                        {
                            seen_assistant_content = true;

                            // Calculate delta: cumulative text minus what we already have.
                            // Validate cumulative invariant: new text must start with old text.
                            if text.len() > full_content.len()
                                && text.starts_with(&full_content)
                            {
                                let delta = &text[full_content.len()..];
                                if let Some(ref cb) = *self.stream_callback.lock() {
                                    cb(delta);
                                }
                            }
                            // Update full content (stream-json sends cumulative text)
                            full_content = text.to_string();
                        }
                    }

                    // Final result — the complete response
                    "result" => {
                        // Extract final content
                        if let Some(text) = event["result"].as_str() {
                            full_content = text.to_string();
                        }

                        // Extract session ID from result
                        if let Some(sid) = event["session_id"].as_str() {
                            session_id = Some(sid.to_string());
                        }

                        // Extract token usage
                        if let Some(usage) = event["usage"].as_object() {
                            input_tokens = usage
                                .get("input_tokens")
                                .and_then(|v| v.as_u64())
                                .unwrap_or(0);
                            output_tokens = usage
                                .get("output_tokens")
                                .and_then(|v| v.as_u64())
                                .unwrap_or(0);
                        }

                        // Also check total_cost_usd
                        if let Some(cost_cents) = event["cost_usd"].as_f64() {
                            log::info!(
                                "ClaudeCliProvider: query cost ${:.4}",
                                cost_cents,
                            );
                        }
                    }

                    // Content block delta — incremental text streaming.
                    // Only used when NOT receiving cumulative "assistant" events.
                    // If both fire, assistant takes priority to avoid text duplication.
                    "content_block_delta" => {
                        if !seen_assistant_content {
                            if let Some(delta_text) = event["delta"]["text"].as_str() {
                                if let Some(ref cb) = *self.stream_callback.lock() {
                                    cb(delta_text);
                                }
                                full_content.push_str(delta_text);
                            }
                        }
                    }

                    // Message delta — usage info
                    "message_delta" => {
                        if let Some(usage) = event["usage"].as_object() {
                            output_tokens = usage
                                .get("output_tokens")
                                .and_then(|v| v.as_u64())
                                .unwrap_or(output_tokens);
                        }
                    }

                    _ => {
                        // Log unknown events at debug level
                        log::debug!("ClaudeCliProvider: unknown event type '{}'", event_type);
                    }
                }
            }
        })
        .await;

        // Handle timeout — kill the subprocess
        if stream_result.is_err() {
            log::error!(
                "ClaudeCliProvider: timeout after {}s, killing subprocess",
                self.config.timeout_secs
            );
            let _ = child.kill().await;
            return Err(BrainError::Timeout {
                provider: "claude-cli".into(),
                timeout_ms: self.config.timeout_secs * 1000,
            });
        }

        // Wait for process to exit
        let status = child.wait().await.map_err(|e| BrainError::Network {
            message: format!("CLI process error: {}", e),
        })?;

        let latency_ms = start.elapsed().as_millis() as u64;

        // Store session ID BEFORE checking errors — preserves continuity even on partial failures.
        if let Some(ref sid) = session_id {
            log::info!(
                "ClaudeCliProvider: session {} stored for {}",
                &sid[..8.min(sid.len())],
                request.model.display_name()
            );
            self.store_session_id(&request.model, sid.clone());
        }

        if !status.success() {
            // Read stderr for actual error details
            let stderr_content = stderr_handle.await.unwrap_or_default();
            let exit_code = status.code().unwrap_or(-1);
            return Err(BrainError::ApiError {
                provider: "claude-cli".into(),
                status: exit_code as u16,
                message: format!(
                    "CLI exited with code {}. stderr: '{}'. Content so far: '{}'",
                    exit_code,
                    stderr_content.chars().take(500).collect::<String>(),
                    full_content.chars().take(200).collect::<String>()
                ),
            });
        }

        if full_content.is_empty() {
            let stderr_content = stderr_handle.await.unwrap_or_default();
            return Err(BrainError::ApiError {
                provider: "claude-cli".into(),
                status: 0,
                message: format!(
                    "CLI returned empty response. stderr: '{}'",
                    stderr_content.chars().take(500).collect::<String>()
                ),
            });
        }

        let estimated_cost =
            BrainResponse::calculate_cost(&request.model, input_tokens, output_tokens);

        Ok(BrainResponse {
            request_id: request.id.clone(),
            model: request.model.clone(),
            content: full_content,
            input_tokens,
            output_tokens,
            latency_ms,
            received_at: Utc::now(),
            is_fallback: false,
            estimated_cost_usd: estimated_cost,
        })
    }
}

impl BrainProviderAsync for ClaudeCliProvider {
    fn name(&self) -> &str {
        "claude-cli"
    }

    fn supported_models(&self) -> &[ModelId] {
        &[ModelId::ClaudeOpus, ModelId::ClaudeSonnet]
    }

    fn is_available(&self) -> bool {
        self.available.load(Ordering::Relaxed)
    }

    fn supports_streaming(&self) -> bool {
        true
    }

    fn set_stream_callback(
        &self,
        callback: Option<Box<dyn Fn(&str) + Send + Sync>>,
    ) {
        *self.stream_callback.lock() = callback;
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

    fn test_config() -> ClaudeCliConfig {
        ClaudeCliConfig {
            enabled: true,
            cli_path: "claude".into(),
            bare_mode: true,
            permission_mode: "auto".into(),
            max_budget_per_query_usd: 0.0,
            timeout_secs: 300,
            additional_dirs: vec![],
        }
    }

    #[test]
    fn provider_name() {
        let provider = ClaudeCliProvider::new(test_config());
        assert_eq!(provider.name(), "claude-cli");
    }

    #[test]
    fn supported_models() {
        let provider = ClaudeCliProvider::new(test_config());
        let models = provider.supported_models();
        assert!(models.contains(&ModelId::ClaudeOpus));
        assert!(models.contains(&ModelId::ClaudeSonnet));
        assert!(!models.contains(&ModelId::Gpt4o));
    }

    #[test]
    fn build_args_basic() {
        let config = test_config();
        let provider = ClaudeCliProvider::new(config);
        let request = BrainRequest::new("Analiziraj ovaj kod", ModelId::ClaudeOpus);

        let args = provider.build_args(&request);

        assert!(args.contains(&"-p".to_string()));
        assert!(args.contains(&"stream-json".to_string()));
        assert!(args.contains(&"--include-partial-messages".to_string()));
        assert!(args.contains(&"opus".to_string()));
        assert!(args.contains(&"--bare".to_string()));
        assert!(args.contains(&"--permission-mode".to_string()));
        assert!(args.contains(&"auto".to_string()));
        // Last arg should be the prompt
        assert_eq!(args.last().unwrap(), "Analiziraj ovaj kod");
    }

    #[test]
    fn build_args_with_context() {
        let config = test_config();
        let provider = ClaudeCliProvider::new(config);
        let request = BrainRequest::new("Šta misliš?", ModelId::ClaudeSonnet)
            .with_context("Prethodni razgovor o audio threadu");

        let args = provider.build_args(&request);

        let prompt = args.last().unwrap();
        assert!(prompt.contains("[Kontekst]:"));
        assert!(prompt.contains("Prethodni razgovor"));
        assert!(prompt.contains("Šta misliš?"));
    }

    #[test]
    fn build_args_with_system_prompt() {
        let config = test_config();
        let provider = ClaudeCliProvider::new(config);
        let request = BrainRequest::new("test", ModelId::ClaudeOpus)
            .with_system_prompt("Ti si audio ekspert");

        let args = provider.build_args(&request);

        let sys_idx = args.iter().position(|a| a == "--system-prompt").unwrap();
        assert_eq!(args[sys_idx + 1], "Ti si audio ekspert");
    }

    #[test]
    fn build_args_with_resume() {
        let config = test_config();
        let provider = ClaudeCliProvider::new(config);

        // Store a session ID
        let session_uuid = "550e8400-e29b-41d4-a716-446655440000".to_string();
        provider.store_session_id(&ModelId::ClaudeOpus, session_uuid.clone());

        let request = BrainRequest::new("Nastavi", ModelId::ClaudeOpus);
        let args = provider.build_args(&request);

        let resume_idx = args.iter().position(|a| a == "--resume").unwrap();
        assert_eq!(args[resume_idx + 1], session_uuid);
    }

    #[test]
    fn session_ids_per_model() {
        let config = test_config();
        let provider = ClaudeCliProvider::new(config);

        provider.store_session_id(&ModelId::ClaudeOpus, "opus-session".into());
        provider.store_session_id(&ModelId::ClaudeSonnet, "sonnet-session".into());

        assert_eq!(
            provider.session_id_for(&ModelId::ClaudeOpus),
            Some("opus-session".into())
        );
        assert_eq!(
            provider.session_id_for(&ModelId::ClaudeSonnet),
            Some("sonnet-session".into())
        );
        assert_eq!(provider.session_id_for(&ModelId::Gpt4o), None);
    }

    #[test]
    fn build_args_with_budget() {
        let mut config = test_config();
        config.max_budget_per_query_usd = 0.50;
        let provider = ClaudeCliProvider::new(config);
        let request = BrainRequest::new("test", ModelId::ClaudeOpus);

        let args = provider.build_args(&request);

        let budget_idx = args.iter().position(|a| a == "--max-budget-usd").unwrap();
        assert_eq!(args[budget_idx + 1], "0.50");
    }

    #[test]
    fn build_args_additional_dirs() {
        let mut config = test_config();
        config.additional_dirs = vec!["/tmp/project".into(), "/home/src".into()];
        let provider = ClaudeCliProvider::new(config);
        let request = BrainRequest::new("test", ModelId::ClaudeOpus);

        let args = provider.build_args(&request);

        let dir_count = args.iter().filter(|a| a.as_str() == "--add-dir").count();
        assert_eq!(dir_count, 2);
    }

    #[test]
    fn stream_callback_settable() {
        let config = test_config();
        let provider = ClaudeCliProvider::new(config);

        let chunks = std::sync::Arc::new(Mutex::new(Vec::<String>::new()));
        let chunks_clone = chunks.clone();

        provider.set_stream_callback(Box::new(move |chunk| {
            chunks_clone.lock().push(chunk.to_string());
        }));

        // Verify callback is set
        assert!(provider.stream_callback.lock().is_some());
    }

    #[test]
    fn disabled_when_not_enabled() {
        let mut config = test_config();
        config.enabled = false;
        config.cli_path = "/nonexistent/claude".into();
        let provider = ClaudeCliProvider::new(config);
        assert!(!provider.is_available());
    }
}
