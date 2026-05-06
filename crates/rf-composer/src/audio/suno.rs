//! Suno adapter — music generation via the Suno API.
//!
//! ⚠️ Suno's public API is in flux. This adapter targets the published v1
//! endpoint (`/api/generate`) which accepts `{prompt, custom_mode, ...}` and
//! returns a generation ID that we poll until ready.
//!
//! Customer's API key is stored in the OS keychain under account `suno`.
//!
//! Many third-party Suno wrappers (suno-api, sunoapi.org, etc.) reimplement
//! the same endpoint shape. Endpoint is configurable so customers can point
//! at whichever wrapper they trust.

use crate::audio::generator::{
    sanitize_filename, AudioBackendId, AudioError, AudioGenerator, AudioKind, AudioOutput,
    AudioPrompt, AudioResult,
};
use crate::credentials::CredentialStore;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::AsyncWriteExt;

const DEFAULT_ENDPOINT: &str = "https://api.suno.ai";
const KEYCHAIN_ACCOUNT: &str = "suno";
const POLL_INTERVAL_MS: u64 = 4_000;
const MAX_POLL_ATTEMPTS: u32 = 45; // ~3 minutes total

/// Suno music generator.
pub struct SunoBackend {
    endpoint: String,
    client: reqwest::Client,
    credentials: Arc<dyn CredentialStore>,
}

impl SunoBackend {
    /// Create with default endpoint.
    pub fn new(credentials: Arc<dyn CredentialStore>) -> AudioResult<Self> {
        Self::with_endpoint(DEFAULT_ENDPOINT, credentials)
    }

    /// Create with a custom endpoint.
    pub fn with_endpoint(
        endpoint: impl Into<String>,
        credentials: Arc<dyn CredentialStore>,
    ) -> AudioResult<Self> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(60))
            .connect_timeout(Duration::from_secs(10))
            .build()
            .map_err(|e| AudioError::Config(format!("HTTP client: {}", e)))?;
        let endpoint: String = endpoint.into();
        Ok(Self {
            endpoint: endpoint.trim_end_matches('/').to_string(),
            client,
            credentials,
        })
    }

    /// Keychain account name where the Suno API key is stored.
    pub fn credential_account() -> &'static str {
        KEYCHAIN_ACCOUNT
    }

    fn api_key(&self) -> AudioResult<String> {
        self.credentials
            .get(KEYCHAIN_ACCOUNT)
            .map_err(|e| AudioError::Auth(format!("api key not configured: {}", e)))
    }
}

#[derive(Serialize)]
struct SunoGenRequest<'a> {
    prompt: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    duration: Option<f32>,
    make_instrumental: bool,
    wait_audio: bool,
}

#[derive(Deserialize)]
struct SunoGenResponseItem {
    id: String,
    #[serde(default)]
    status: String,
    #[serde(default)]
    audio_url: Option<String>,
}

#[async_trait]
impl AudioGenerator for SunoBackend {
    fn id(&self) -> AudioBackendId {
        AudioBackendId::Suno
    }

    async fn health_check(&self) -> AudioResult<()> {
        let key = self.api_key()?;
        // Suno wrappers commonly expose `/api/get_limit` or `/api/health`. Try
        // a HEAD on the base host as a non-destructive ping.
        let url = format!("{}/api/get_limit", self.endpoint);
        let resp = self
            .client
            .get(&url)
            .bearer_auth(key)
            .send()
            .await
            .map_err(|e| AudioError::Network(format!("ping: {}", e)))?;
        let status = resp.status();
        if status.is_success() {
            Ok(())
        } else if matches!(status.as_u16(), 401 | 403) {
            Err(AudioError::Auth(format!("rejected: {}", status)))
        } else if status.as_u16() == 404 {
            // Endpoint shape varies — treat 404 as "host alive, key untested".
            Ok(())
        } else {
            Err(AudioError::Network(format!("ping {}", status)))
        }
    }

    async fn generate(&self, prompt: &AudioPrompt, out_dir: &Path) -> AudioResult<AudioOutput> {
        if prompt.kind != AudioKind::Music {
            return Err(AudioError::Unsupported {
                backend: AudioBackendId::Suno,
                kind: prompt.kind,
            });
        }

        let key = self.api_key()?;

        // 1. Submit
        let submit_url = format!("{}/api/generate", self.endpoint);
        let body = SunoGenRequest {
            prompt: &prompt.prompt,
            duration: prompt.length_seconds,
            make_instrumental: true,
            wait_audio: false,
        };
        let resp = self
            .client
            .post(&submit_url)
            .bearer_auth(&key)
            .json(&body)
            .send()
            .await
            .map_err(|e| AudioError::Network(format!("submit: {}", e)))?;
        let status = resp.status();
        if !status.is_success() {
            let txt = resp.text().await.unwrap_or_default();
            return Err(match status.as_u16() {
                401 | 403 => AudioError::Auth(txt),
                429 => AudioError::RateLimited(txt),
                400 | 422 => AudioError::Rejected(txt),
                _ => AudioError::Network(format!("{}: {}", status, txt)),
            });
        }

        let items: Vec<SunoGenResponseItem> = resp
            .json()
            .await
            .map_err(|e| AudioError::Network(format!("submit json: {}", e)))?;
        let job_id = items
            .first()
            .map(|i| i.id.clone())
            .ok_or_else(|| AudioError::Network("empty response".to_string()))?;

        // 2. Poll
        let info_url = format!("{}/api/get?ids={}", self.endpoint, job_id);
        let mut audio_url: Option<String> = None;
        for attempt in 0..MAX_POLL_ATTEMPTS {
            tokio::time::sleep(Duration::from_millis(POLL_INTERVAL_MS)).await;
            let resp = self
                .client
                .get(&info_url)
                .bearer_auth(&key)
                .send()
                .await
                .map_err(|e| AudioError::Network(format!("poll {}: {}", attempt, e)))?;
            if !resp.status().is_success() {
                continue;
            }
            let items: Vec<SunoGenResponseItem> = match resp.json().await {
                Ok(v) => v,
                Err(_) => continue,
            };
            if let Some(it) = items.first() {
                if let Some(url) = &it.audio_url {
                    if !url.is_empty() {
                        audio_url = Some(url.clone());
                        break;
                    }
                }
                if matches!(it.status.as_str(), "error" | "failed") {
                    return Err(AudioError::Network(format!(
                        "suno generation failed: {}",
                        it.status
                    )));
                }
            }
        }
        let audio_url = audio_url.ok_or_else(|| {
            AudioError::Network("suno did not produce audio in time".to_string())
        })?;

        // 3. Download
        let bytes = self
            .client
            .get(&audio_url)
            .send()
            .await
            .map_err(|e| AudioError::Network(format!("download: {}", e)))?
            .error_for_status()
            .map_err(|e| AudioError::Network(format!("download status: {}", e)))?
            .bytes()
            .await
            .map_err(|e| AudioError::Network(format!("download body: {}", e)))?;

        // 4. Persist
        tokio::fs::create_dir_all(out_dir)
            .await
            .map_err(|e| AudioError::Io(format!("mkdir: {}", e)))?;
        let safe = sanitize_filename(&prompt.suggested_name);
        let path = out_dir.join(format!("{}.mp3", safe));
        let mut f = tokio::fs::File::create(&path)
            .await
            .map_err(|e| AudioError::Io(format!("create {}: {}", path.display(), e)))?;
        f.write_all(&bytes)
            .await
            .map_err(|e| AudioError::Io(format!("write: {}", e)))?;
        f.flush()
            .await
            .map_err(|e| AudioError::Io(format!("flush: {}", e)))?;

        let bytes_len = bytes.len() as u64;
        Ok(AudioOutput {
            path,
            format: "mp3".to_string(),
            duration_ms: prompt.length_seconds.map(|s| (s * 1000.0) as u32).unwrap_or(0),
            bytes: bytes_len,
            backend: AudioBackendId::Suno,
            prompt: prompt.prompt.clone(),
            kind: AudioKind::Music,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::credentials::MemoryStore;

    fn store_with(key: Option<&str>) -> Arc<dyn CredentialStore> {
        let s = Arc::new(MemoryStore::new());
        if let Some(k) = key {
            s.put(KEYCHAIN_ACCOUNT, k).unwrap();
        }
        s
    }

    #[test]
    fn endpoint_trim_trailing_slash() {
        let b = SunoBackend::with_endpoint("https://api.suno.ai/", store_with(None)).unwrap();
        assert!(!b.endpoint.ends_with('/'));
    }

    #[tokio::test]
    async fn sfx_kind_unsupported() {
        let b = SunoBackend::with_endpoint("http://127.0.0.1:1", store_with(Some("x"))).unwrap();
        let p = AudioPrompt {
            prompt: "x".to_string(),
            kind: AudioKind::Sfx,
            length_seconds: None,
            voice_id: None,
            suggested_name: "x".to_string(),
        };
        let dir = std::env::temp_dir().join("rf-composer-suno-test");
        match b.generate(&p, &dir).await {
            Err(AudioError::Unsupported { kind: AudioKind::Sfx, .. }) => {}
            other => panic!("expected Unsupported, got {:?}", other.is_ok()),
        }
    }

    #[tokio::test]
    async fn missing_key_is_auth_error_in_generate() {
        let b = SunoBackend::with_endpoint("http://127.0.0.1:1", store_with(None)).unwrap();
        let p = AudioPrompt {
            prompt: "x".to_string(),
            kind: AudioKind::Music,
            length_seconds: None,
            voice_id: None,
            suggested_name: "x".to_string(),
        };
        let dir = std::env::temp_dir().join("rf-composer-suno-test2");
        match b.generate(&p, &dir).await {
            Err(AudioError::Auth(_)) => {}
            other => panic!("expected Auth, got {:?}", other.is_ok()),
        }
    }
}
