//! ElevenLabs adapter — SFX (`/v1/sound-generation`) + TTS (`/v1/text-to-speech/{voice}`).
//!
//! API key stored in OS keychain under account `elevenlabs`.

use crate::audio::generator::{
    sanitize_filename, AudioBackendId, AudioError, AudioGenerator, AudioKind, AudioOutput,
    AudioPrompt, AudioResult,
};
use crate::credentials::CredentialStore;
use async_trait::async_trait;
use serde::Serialize;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::AsyncWriteExt;

const API_BASE: &str = "https://api.elevenlabs.io";
const KEYCHAIN_ACCOUNT: &str = "elevenlabs";
const DEFAULT_TTS_MODEL: &str = "eleven_multilingual_v2";

/// ElevenLabs audio generator (SFX + TTS).
pub struct ElevenLabsBackend {
    endpoint: String,
    client: reqwest::Client,
    credentials: Arc<dyn CredentialStore>,
}

impl ElevenLabsBackend {
    /// Create with default endpoint.
    pub fn new(credentials: Arc<dyn CredentialStore>) -> AudioResult<Self> {
        Self::with_endpoint(API_BASE, credentials)
    }

    /// Create with a custom endpoint (for testing / proxy).
    pub fn with_endpoint(
        endpoint: impl Into<String>,
        credentials: Arc<dyn CredentialStore>,
    ) -> AudioResult<Self> {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(120))
            .connect_timeout(Duration::from_secs(10))
            .build()
            .map_err(|e| AudioError::Config(format!("HTTP client: {}", e)))?;
        Ok(Self {
            endpoint: endpoint.into(),
            client,
            credentials,
        })
    }

    /// Keychain account name where the API key is stored.
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
struct SfxRequest<'a> {
    text: &'a str,
    prompt_influence: f32,
    #[serde(skip_serializing_if = "Option::is_none")]
    duration_seconds: Option<f32>,
}

#[derive(Serialize)]
struct TtsRequest<'a> {
    text: &'a str,
    model_id: &'a str,
    voice_settings: VoiceSettings,
}

#[derive(Serialize)]
struct VoiceSettings {
    stability: f32,
    similarity_boost: f32,
    speed: f32,
}

#[async_trait]
impl AudioGenerator for ElevenLabsBackend {
    fn id(&self) -> AudioBackendId {
        AudioBackendId::Elevenlabs
    }

    async fn health_check(&self) -> AudioResult<()> {
        let key = self.api_key()?;
        let url = format!("{}/v1/voices", self.endpoint);
        let resp = self
            .client
            .get(&url)
            .header("xi-api-key", key)
            .send()
            .await
            .map_err(|e| AudioError::Network(format!("voices: {}", e)))?;
        let status = resp.status();
        if status.is_success() {
            Ok(())
        } else if matches!(status.as_u16(), 401 | 403) {
            Err(AudioError::Auth(format!("rejected: {}", status)))
        } else {
            Err(AudioError::Network(format!(
                "voices returned {}",
                status
            )))
        }
    }

    async fn generate(&self, prompt: &AudioPrompt, out_dir: &Path) -> AudioResult<AudioOutput> {
        match prompt.kind {
            AudioKind::Sfx => self.generate_sfx(prompt, out_dir).await,
            AudioKind::Tts => self.generate_tts(prompt, out_dir).await,
            AudioKind::Music => Err(AudioError::Unsupported {
                backend: AudioBackendId::Elevenlabs,
                kind: AudioKind::Music,
            }),
        }
    }
}

impl ElevenLabsBackend {
    async fn generate_sfx(
        &self,
        prompt: &AudioPrompt,
        out_dir: &Path,
    ) -> AudioResult<AudioOutput> {
        let key = self.api_key()?;
        let dur = prompt
            .length_seconds
            .map(|s| s.clamp(0.5, 22.0));
        let body = SfxRequest {
            text: &prompt.prompt,
            prompt_influence: 0.3,
            duration_seconds: dur,
        };
        let url = format!("{}/v1/sound-generation", self.endpoint);
        let resp = self
            .client
            .post(&url)
            .header("xi-api-key", key)
            .header("Accept", "audio/mpeg")
            .json(&body)
            .send()
            .await
            .map_err(|e| AudioError::Network(format!("POST sfx: {}", e)))?;

        let status = resp.status();
        if !status.is_success() {
            let txt = resp.text().await.unwrap_or_default();
            return Err(map_status(status, txt));
        }
        let bytes = resp
            .bytes()
            .await
            .map_err(|e| AudioError::Network(format!("read body: {}", e)))?;

        let path = write_to_disk(out_dir, &prompt.suggested_name, "mp3", &bytes).await?;
        let written = bytes.len() as u64;
        Ok(AudioOutput {
            path,
            format: "mp3".to_string(),
            duration_ms: dur.map(|s| (s * 1000.0) as u32).unwrap_or(0),
            bytes: written,
            backend: AudioBackendId::Elevenlabs,
            prompt: prompt.prompt.clone(),
            kind: AudioKind::Sfx,
        })
    }

    async fn generate_tts(
        &self,
        prompt: &AudioPrompt,
        out_dir: &Path,
    ) -> AudioResult<AudioOutput> {
        let key = self.api_key()?;
        let voice = prompt.voice_id.as_deref().ok_or_else(|| {
            AudioError::Config("TTS requires voice_id".to_string())
        })?;
        let body = TtsRequest {
            text: &prompt.prompt,
            model_id: DEFAULT_TTS_MODEL,
            voice_settings: VoiceSettings {
                stability: 0.4,
                similarity_boost: 0.75,
                speed: 1.05,
            },
        };
        let url = format!(
            "{}/v1/text-to-speech/{}?output_format=mp3_44100_128",
            self.endpoint, voice
        );
        let resp = self
            .client
            .post(&url)
            .header("xi-api-key", key)
            .header("Accept", "audio/mpeg")
            .json(&body)
            .send()
            .await
            .map_err(|e| AudioError::Network(format!("POST tts: {}", e)))?;

        let status = resp.status();
        if !status.is_success() {
            let txt = resp.text().await.unwrap_or_default();
            return Err(map_status(status, txt));
        }
        let bytes = resp
            .bytes()
            .await
            .map_err(|e| AudioError::Network(format!("read body: {}", e)))?;
        let path = write_to_disk(out_dir, &prompt.suggested_name, "mp3", &bytes).await?;
        let written = bytes.len() as u64;
        Ok(AudioOutput {
            path,
            format: "mp3".to_string(),
            duration_ms: 0,
            bytes: written,
            backend: AudioBackendId::Elevenlabs,
            prompt: prompt.prompt.clone(),
            kind: AudioKind::Tts,
        })
    }
}

fn map_status(status: reqwest::StatusCode, body: String) -> AudioError {
    match status.as_u16() {
        401 | 403 => AudioError::Auth(body),
        429 => AudioError::RateLimited(body),
        400 | 422 => AudioError::Rejected(body),
        _ => AudioError::Network(format!("{}: {}", status, body)),
    }
}

async fn write_to_disk(
    out_dir: &Path,
    suggested: &str,
    ext: &str,
    bytes: &[u8],
) -> AudioResult<std::path::PathBuf> {
    tokio::fs::create_dir_all(out_dir)
        .await
        .map_err(|e| AudioError::Io(format!("mkdir: {}", e)))?;
    let safe = sanitize_filename(suggested);
    let path = out_dir.join(format!("{}.{}", safe, ext));
    let mut f = tokio::fs::File::create(&path)
        .await
        .map_err(|e| AudioError::Io(format!("create {}: {}", path.display(), e)))?;
    f.write_all(bytes)
        .await
        .map_err(|e| AudioError::Io(format!("write: {}", e)))?;
    f.flush()
        .await
        .map_err(|e| AudioError::Io(format!("flush: {}", e)))?;
    Ok(path)
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
    fn id_correct() {
        let b = ElevenLabsBackend::new(store_with(None)).unwrap();
        assert_eq!(b.id(), AudioBackendId::Elevenlabs);
    }

    #[test]
    fn missing_key_is_auth_error() {
        let b = ElevenLabsBackend::new(store_with(None)).unwrap();
        match b.api_key() {
            Err(AudioError::Auth(_)) => {}
            other => panic!("expected Auth, got {:?}", other),
        }
    }

    #[test]
    fn key_present_returns_value() {
        let b = ElevenLabsBackend::new(store_with(Some("x"))).unwrap();
        assert_eq!(b.api_key().unwrap(), "x");
    }

    #[tokio::test]
    async fn music_kind_unsupported() {
        let b = ElevenLabsBackend::with_endpoint("http://127.0.0.1:1", store_with(Some("x"))).unwrap();
        let p = AudioPrompt {
            prompt: "x".to_string(),
            kind: AudioKind::Music,
            length_seconds: None,
            voice_id: None,
            suggested_name: "x".to_string(),
        };
        let dir = std::env::temp_dir().join("rf-composer-test-noop");
        match b.generate(&p, &dir).await {
            Err(AudioError::Unsupported {
                backend: AudioBackendId::Elevenlabs,
                kind: AudioKind::Music,
            }) => {}
            other => panic!("expected Unsupported, got {:?}", other.is_ok()),
        }
    }

    #[tokio::test]
    async fn tts_without_voice_is_config_error() {
        let b = ElevenLabsBackend::with_endpoint("http://127.0.0.1:1", store_with(Some("x"))).unwrap();
        let p = AudioPrompt {
            prompt: "hello".to_string(),
            kind: AudioKind::Tts,
            length_seconds: None,
            voice_id: None,
            suggested_name: "vo_test".to_string(),
        };
        let dir = std::env::temp_dir().join("rf-composer-test-noop2");
        match b.generate(&p, &dir).await {
            Err(AudioError::Config(_)) => {}
            other => panic!("expected Config, got {:?}", other.is_ok()),
        }
    }
}
