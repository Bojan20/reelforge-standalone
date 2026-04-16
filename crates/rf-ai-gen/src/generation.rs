//! T8.2: Generation pipeline — backend adapters + request formatting.
//!
//! FluxForge is backend-agnostic: the same GenerationSpec can be sent to
//! AudioCraft (local), ElevenLabs, Stability AI, or any future API.

use serde::{Deserialize, Serialize};
use crate::prompt::AudioDescriptor;

/// Available generation backends
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum GenerationBackend {
    /// Meta AudioCraft (local, via subprocess IPC) — runs offline
    AudioCraft,
    /// ElevenLabs Sound Effects API
    ElevenLabs,
    /// Stability AI Audio API (Stable Audio)
    StabilityAi,
    /// OpenAI (if/when audio generation available)
    OpenAi,
    /// Stub backend for testing (returns empty spec, no network)
    Stub,
}

impl GenerationBackend {
    pub fn display_name(&self) -> &'static str {
        match self {
            Self::AudioCraft   => "AudioCraft (Local)",
            Self::ElevenLabs   => "ElevenLabs Sound Effects",
            Self::StabilityAi  => "Stability AI (Stable Audio)",
            Self::OpenAi       => "OpenAI Audio",
            Self::Stub         => "Test Stub",
        }
    }

    pub fn requires_internet(&self) -> bool {
        !matches!(self, Self::AudioCraft | Self::Stub)
    }

    pub fn max_duration_ms(&self) -> u32 {
        match self {
            Self::AudioCraft   => 30_000,
            Self::ElevenLabs   => 22_000,
            Self::StabilityAi  => 180_000,
            Self::OpenAi       => 60_000,
            Self::Stub         => 30_000,
        }
    }
}

/// Complete specification for a generation request (T8.2)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenerationSpec {
    /// Target backend
    pub backend: GenerationBackend,
    /// Natural-language generation prompt (ready for the AI model)
    pub generation_prompt: String,
    /// Negative prompt (what to avoid)
    pub negative_prompt: Option<String>,
    /// Duration in milliseconds (0 = backend-determined)
    pub duration_ms: u32,
    /// Sample rate for output
    pub sample_rate: u32,
    /// Number of generation candidates to produce
    pub num_candidates: u8,
    /// Random seed for reproducibility (None = random)
    pub seed: Option<u64>,
    /// Original descriptor (for FFNC classification and post-processing)
    pub descriptor: AudioDescriptor,
    /// Backend-specific configuration (arbitrary JSON)
    pub backend_config: serde_json::Value,
}

impl GenerationSpec {
    /// Build a GenerationSpec from an AudioDescriptor for a specific backend.
    pub fn build(descriptor: AudioDescriptor, backend: GenerationBackend) -> Self {
        let generation_prompt = descriptor.to_generation_prompt();
        let negative_prompt = Self::build_negative_prompt(&descriptor, &backend);
        let duration_ms = if descriptor.duration_ms > 0 {
            descriptor.duration_ms.min(backend.max_duration_ms())
        } else {
            0
        };
        let backend_config = Self::build_backend_config(&descriptor, &backend);

        Self {
            backend,
            generation_prompt,
            negative_prompt,
            duration_ms,
            sample_rate: 44100,
            num_candidates: 3,
            seed: None,
            descriptor,
            backend_config,
        }
    }

    fn build_negative_prompt(descriptor: &AudioDescriptor, _backend: &GenerationBackend) -> Option<String> {
        use crate::prompt::EventCategory;
        let mut negatives = vec!["speech", "dialogue", "voice", "words", "singing"];

        // Category-specific negatives
        match descriptor.category {
            EventCategory::Ambient | EventCategory::Win => {
                negatives.push("noise");
                negatives.push("distortion");
            }
            EventCategory::UI => {
                negatives.push("music");
                negatives.push("melody");
            }
            _ => {}
        }
        Some(negatives.join(", "))
    }

    fn build_backend_config(descriptor: &AudioDescriptor, backend: &GenerationBackend) -> serde_json::Value {
        match backend {
            GenerationBackend::AudioCraft => {
                // AudioCraft MusicGen/AudioGen params
                serde_json::json!({
                    "model": if descriptor.can_loop { "musicgen-melody" } else { "audiogen-medium" },
                    "top_k": 250,
                    "top_p": 0.0,
                    "temperature": 1.0,
                    "cfg_coef": 3.0,
                })
            }
            GenerationBackend::ElevenLabs => {
                serde_json::json!({
                    "duration_seconds": descriptor.duration_ms as f64 / 1000.0,
                    "prompt_influence": 0.3,
                })
            }
            GenerationBackend::StabilityAi => {
                serde_json::json!({
                    "output_format": "mp3",
                    "steps": 50,
                    "cfg_scale": 7.0,
                    "tempo_bpm": descriptor.tempo_bpm,
                })
            }
            _ => serde_json::json!({}),
        }
    }
}

/// Backend request formatted for the specific API (ready to send)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackendRequest {
    pub backend: GenerationBackend,
    pub endpoint: String,
    pub method: String,
    pub headers: Vec<(String, String)>,
    pub body: serde_json::Value,
}

impl BackendRequest {
    /// Format the GenerationSpec into a ready-to-send API request.
    pub fn from_spec(spec: &GenerationSpec, api_key: Option<&str>) -> Self {
        match &spec.backend {
            GenerationBackend::ElevenLabs => Self {
                backend: spec.backend.clone(),
                endpoint: "https://api.elevenlabs.io/v1/sound-generation".to_string(),
                method: "POST".to_string(),
                headers: vec![
                    ("Content-Type".to_string(), "application/json".to_string()),
                    ("xi-api-key".to_string(), api_key.unwrap_or("").to_string()),
                ],
                body: serde_json::json!({
                    "text": spec.generation_prompt,
                    "duration_seconds": spec.duration_ms as f64 / 1000.0,
                    "prompt_influence": spec.backend_config.get("prompt_influence").cloned().unwrap_or(serde_json::json!(0.3)),
                }),
            },
            GenerationBackend::StabilityAi => Self {
                backend: spec.backend.clone(),
                endpoint: "https://api.stability.ai/v2beta/audio/generate".to_string(),
                method: "POST".to_string(),
                headers: vec![
                    ("Authorization".to_string(), format!("Bearer {}", api_key.unwrap_or(""))),
                    ("Content-Type".to_string(), "application/json".to_string()),
                ],
                body: serde_json::json!({
                    "prompt": spec.generation_prompt,
                    "negative_prompt": spec.negative_prompt,
                    "output_format": "mp3",
                    "steps": spec.backend_config.get("steps").cloned().unwrap_or(serde_json::json!(50)),
                    "cfg_scale": spec.backend_config.get("cfg_scale").cloned().unwrap_or(serde_json::json!(7.0)),
                }),
            },
            GenerationBackend::AudioCraft => Self {
                // AudioCraft uses local subprocess — no HTTP endpoint
                backend: spec.backend.clone(),
                endpoint: "ipc://audiocraft".to_string(),
                method: "IPC".to_string(),
                headers: vec![],
                body: serde_json::json!({
                    "model": spec.backend_config.get("model").cloned().unwrap_or(serde_json::json!("audiogen-medium")),
                    "prompt": spec.generation_prompt,
                    "duration": spec.duration_ms as f64 / 1000.0,
                    "cfg_coef": spec.backend_config.get("cfg_coef").cloned().unwrap_or(serde_json::json!(3.0)),
                    "temperature": spec.backend_config.get("temperature").cloned().unwrap_or(serde_json::json!(1.0)),
                    "seed": spec.seed,
                }),
            },
            GenerationBackend::Stub => Self {
                backend: spec.backend.clone(),
                endpoint: "stub://localhost".to_string(),
                method: "STUB".to_string(),
                headers: vec![],
                body: serde_json::json!({ "prompt": spec.generation_prompt }),
            },
            _ => Self {
                backend: spec.backend.clone(),
                endpoint: String::new(),
                method: "POST".to_string(),
                headers: vec![],
                body: serde_json::json!({ "prompt": spec.generation_prompt }),
            },
        }
    }
}

/// Status of a generation request
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum GenerationStatus {
    Pending,
    Processing,
    Complete,
    Failed { reason: String },
}

/// Result of a completed generation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenerationResult {
    pub spec: GenerationSpec,
    pub status: GenerationStatus,
    /// Generated asset paths or URLs (None = stub/pending)
    pub output_urls: Vec<String>,
    /// Duration of generated audio in ms (actual)
    pub actual_duration_ms: u32,
    /// Generation time in ms
    pub generation_time_ms: u64,
    /// Suggested filename
    pub suggested_filename: String,
}

impl GenerationResult {
    /// Create a stub result (for testing without a real backend)
    pub fn stub(spec: GenerationSpec) -> Self {
        
        let filename = format!(
            "{}_{}.wav",
            spec.descriptor.category.as_str().to_lowercase(),
            &spec.descriptor.tier.as_str().replace(' ', "_"),
        );
        let duration = spec.duration_ms.max(1000);
        Self {
            status: GenerationStatus::Complete,
            output_urls: vec![format!("stub://generated/{}", filename)],
            actual_duration_ms: duration,
            generation_time_ms: 100,
            suggested_filename: filename,
            spec,
        }
    }
}

/// High-level generation pipeline (T8.2)
pub struct GenerationPipeline;

impl GenerationPipeline {
    /// Parse a text prompt and build a generation spec for a backend.
    pub fn prepare(prompt: &str, backend: GenerationBackend) -> GenerationSpec {
        let descriptor = crate::prompt::PromptParser::parse(prompt);
        GenerationSpec::build(descriptor, backend)
    }

    /// Format a BackendRequest ready for submission.
    pub fn format_request(spec: &GenerationSpec, api_key: Option<&str>) -> BackendRequest {
        BackendRequest::from_spec(spec, api_key)
    }

    /// Execute with stub backend (no network, for testing).
    pub fn execute_stub(spec: GenerationSpec) -> GenerationResult {
        GenerationResult::stub(spec)
    }

    /// Get all available backends with their status.
    pub fn available_backends() -> Vec<(GenerationBackend, bool)> {
        vec![
            (GenerationBackend::AudioCraft,  false), // not installed by default
            (GenerationBackend::ElevenLabs,  true),  // cloud, needs API key
            (GenerationBackend::StabilityAi, true),  // cloud, needs API key
            (GenerationBackend::OpenAi,      true),  // cloud, needs API key
            (GenerationBackend::Stub,        true),  // always available
        ]
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spec_built_for_elevenlabs() {
        let spec = GenerationPipeline::prepare(
            "epic jackpot win fanfare with brass",
            GenerationBackend::ElevenLabs,
        );
        assert_eq!(spec.backend, GenerationBackend::ElevenLabs);
        assert!(!spec.generation_prompt.is_empty());
    }

    #[test]
    fn test_spec_duration_clamped_to_backend_max() {
        // ElevenLabs max = 22s
        let spec = GenerationPipeline::prepare(
            "very long ambient loop 60 seconds",
            GenerationBackend::ElevenLabs,
        );
        assert!(spec.duration_ms <= GenerationBackend::ElevenLabs.max_duration_ms());
    }

    #[test]
    fn test_stub_execution_returns_complete() {
        let spec = GenerationPipeline::prepare("win sound", GenerationBackend::Stub);
        let result = GenerationPipeline::execute_stub(spec);
        assert_eq!(result.status, GenerationStatus::Complete);
        assert!(!result.output_urls.is_empty());
    }

    #[test]
    fn test_backend_request_elevenlabs_format() {
        let spec = GenerationPipeline::prepare("coin win", GenerationBackend::ElevenLabs);
        let req = GenerationPipeline::format_request(&spec, Some("test_key"));
        assert!(req.endpoint.contains("elevenlabs"));
        assert!(req.body.get("text").is_some());
    }

    #[test]
    fn test_backend_request_audiocraft_is_ipc() {
        let spec = GenerationPipeline::prepare("reel spin", GenerationBackend::AudioCraft);
        let req = GenerationPipeline::format_request(&spec, None);
        assert_eq!(req.method, "IPC");
        assert!(req.endpoint.contains("audiocraft"));
    }

    #[test]
    fn test_negative_prompt_excludes_speech() {
        let spec = GenerationPipeline::prepare("ambient music", GenerationBackend::ElevenLabs);
        let neg = spec.negative_prompt.unwrap_or_default();
        assert!(neg.contains("speech") || neg.contains("voice") || neg.contains("dialogue"));
    }

    #[test]
    fn test_audiocraft_requires_no_internet() {
        assert!(!GenerationBackend::AudioCraft.requires_internet());
    }

    #[test]
    fn test_available_backends_includes_stub() {
        let backends = GenerationPipeline::available_backends();
        assert!(backends.iter().any(|(b, _)| *b == GenerationBackend::Stub));
    }
}
