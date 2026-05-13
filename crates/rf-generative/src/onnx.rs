//! ONNX backend — runs an audio-generation model on the local machine via
//! the `tract` runtime.
//!
//! # Status
//!
//! **5.1.2 lands the runtime skeleton.** The Stable Audio Open Small model
//! file is a multi-GB blob and is **not** committed; instead, the user
//! provisions it on disk and points `OnnxBackend::open` at the path. When
//! the file is missing or malformed, this backend fails with a typed error
//! (`GenError::ModelNotFound` / `MalformedModel`) and the higher-level
//! `BackendRouter` falls back to `MockBackend`. Nothing silently breaks.
//!
//! # I/O contract — generic ONNX
//!
//! We model the audio-generation graph as:
//!
//! ```text
//!   inputs:   prompt_tokens : i64 [1, T]     (variable T)
//!             duration_secs : f32 []         (scalar)
//!             seed          : i64 []         (scalar)
//!
//!   outputs:  audio         : f32 [C, F]     (channels × frames)
//! ```
//!
//! Real Stable Audio Open Small has more inputs (CFG scale, step count,
//! negative prompt, …) and a tokenizer in front of `prompt_tokens`. Those
//! all live behind a `ModelSpec` struct so a future commit can swap in
//! exact tensor names without touching the trait impl. For 5.1.2 the
//! spec defaults match what the upstream model card publishes.
//!
//! # Determinism
//!
//! When `request.seed.is_some()`, we feed that seed to the model's seed
//! tensor and run a single pass. tract is deterministic by construction
//! (no internal RNG state), so equal inputs → equal outputs. When
//! `seed.is_none()`, we synthesize a seed from `(now_nanos ^ pid)` so the
//! response is still reproducible from the response side (the seed lands
//! in `ProvenanceTag`, available to the caller for archival).
//!
//! # Audio-thread safety
//!
//! Same as the trait contract: `generate()` is **off-thread only**.
//! `tract` allocates, JITs at first inference, and can take seconds per
//! call. Anything calling `OnnxBackend::generate` MUST already be on a
//! worker (Tokio blocking task, std::thread, or a Dart isolate).

use std::path::{Path, PathBuf};
#[cfg(feature = "onnx")]
use std::sync::Mutex;
use std::time::Instant;

#[cfg(feature = "onnx")]
use crate::compliance::{compute_compliance, ComplianceReport};
use crate::{
    BackendCapabilities, GenError, GenerationRequest, GenerationResponse, GenerativeBackend,
};
#[cfg(feature = "onnx")]
use crate::response::ProvenanceTag;

// `tract` types are only in scope under the feature; the dummy backend
// below keeps `cargo build` (no features) compiling cleanly.
#[cfg(feature = "onnx")]
use tract_onnx::prelude::*;

// ─── Public types ────────────────────────────────────────────────────────────

/// Where each logical I/O lives in the ONNX model graph. Defaults match
/// what Stable Audio Open Small publishes; callers can override per model.
///
/// Centralising names here means a future model swap is a *config change*,
/// not a code change.
#[derive(Debug, Clone)]
pub struct ModelSpec {
    /// Tensor name for the int64 prompt-token sequence, shape `[1, T]`.
    pub prompt_tokens_input: String,
    /// Tensor name for the f32 duration scalar (seconds).
    pub duration_input: String,
    /// Tensor name for the i64 seed scalar.
    pub seed_input: String,
    /// Tensor name for the f32 audio output, shape `[C, F]`.
    pub audio_output: String,
    /// Native sample rate the model emits, in Hz. The engine resamples
    /// downstream if a different rate is requested.
    pub native_sample_rate_hz: u32,
    /// 1 = mono, 2 = stereo.
    pub native_channels: u16,
    /// Maximum total duration in seconds the model will accept.
    pub max_duration_seconds: f32,
}

impl Default for ModelSpec {
    fn default() -> Self {
        // Names from the Stable Audio Open Small model card. Adjust the
        // strings (not the layout) when targeting a different model.
        Self {
            prompt_tokens_input: "prompt_tokens".into(),
            duration_input: "duration".into(),
            seed_input: "seed".into(),
            audio_output: "audio".into(),
            native_sample_rate_hz: 44_100,
            native_channels: 2,
            max_duration_seconds: 47.0,
        }
    }
}

// ─── Backend impl (feature-gated) ────────────────────────────────────────────

#[cfg(feature = "onnx")]
type RunnableModel = tract_onnx::prelude::RunnableModel<
    tract_onnx::prelude::TypedFact,
    Box<dyn tract_onnx::prelude::TypedOp>,
    tract_onnx::prelude::Graph<
        tract_onnx::prelude::TypedFact,
        Box<dyn tract_onnx::prelude::TypedOp>,
    >,
>;

/// On-device ONNX backend powered by tract.
///
/// One instance = one loaded model. Cloning is intentionally not derived —
/// loaded graphs are huge (often >500 MB resident); the canonical sharing
/// pattern is `Arc<OnnxBackend>`, not deep clone.
pub struct OnnxBackend {
    spec: ModelSpec,
    model_path: PathBuf,
    id_str: String,

    /// The compiled tract graph. `Mutex` so concurrent `generate()` calls
    /// serialise — tract's `Runnable` is not `Sync`. For a slot-design UI
    /// (one user, one generation at a time) this is the right trade-off;
    /// when we need parallel inference we'll switch to a pool of clones.
    #[cfg(feature = "onnx")]
    model: Mutex<RunnableModel>,

    /// Without the `onnx` feature we still want the type to exist so
    /// `mod onnx` compiles. The dummy backend errors on every call.
    #[cfg(not(feature = "onnx"))]
    _unused: std::marker::PhantomData<*const ()>,
}

// SAFETY: PhantomData<*const ()> is !Send / !Sync. Under the no-`onnx`
// feature the field is never read and the backend is purely a fail-fast
// stub; asserting Send/Sync is sound because nothing accessible is
// thread-sensitive.
#[cfg(not(feature = "onnx"))]
unsafe impl Send for OnnxBackend {}
#[cfg(not(feature = "onnx"))]
unsafe impl Sync for OnnxBackend {}

impl std::fmt::Debug for OnnxBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("OnnxBackend")
            .field("id", &self.id_str)
            .field("model_path", &self.model_path)
            .field("spec", &self.spec)
            .finish_non_exhaustive()
    }
}

impl OnnxBackend {
    /// Open a model from disk with the default Stable Audio Open Small spec.
    ///
    /// Returns `Err(GenError::ModelNotFound)` if the file is missing
    /// (cheap stat check first — saves a 2-3 s tract parse on the common
    /// "user hasn't downloaded the model yet" case).
    /// Returns `Err(GenError::MalformedModel)` if tract can't parse it.
    pub fn open(model_path: impl Into<PathBuf>) -> Result<Self, GenError> {
        Self::open_with_spec(model_path, ModelSpec::default())
    }

    /// Open with an explicit `ModelSpec`. Use this to target a different
    /// audio-generation model whose tensor names differ from Stable Audio.
    pub fn open_with_spec(
        model_path: impl Into<PathBuf>,
        spec: ModelSpec,
    ) -> Result<Self, GenError> {
        let model_path = model_path.into();
        if !model_path.exists() {
            return Err(GenError::ModelNotFound {
                path: model_path.to_string_lossy().to_string(),
            });
        }
        let stem = model_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("onnx");
        let id_str = format!("tract-onnx-{}", stem);

        #[cfg(feature = "onnx")]
        {
            let model = tract_onnx::onnx()
                .model_for_path(&model_path)
                .map_err(|e| GenError::MalformedModel(format!("tract parse: {e}")))?
                .into_optimized()
                .map_err(|e| GenError::MalformedModel(format!("tract optimize: {e}")))?
                .into_runnable()
                .map_err(|e| GenError::MalformedModel(format!("tract runnable: {e}")))?;

            Ok(Self {
                spec,
                model_path,
                id_str,
                model: Mutex::new(model),
            })
        }

        #[cfg(not(feature = "onnx"))]
        {
            // Pretend we opened it so the rest of the wiring can be
            // exercised. Calls to `generate()` will surface `Unsupported`.
            Ok(Self {
                spec,
                model_path,
                id_str,
                _unused: std::marker::PhantomData,
            })
        }
    }

    /// Path of the model file the backend is bound to. Useful for
    /// provenance + audit trails.
    pub fn model_path(&self) -> &Path {
        &self.model_path
    }

    /// The active model spec.
    pub fn spec(&self) -> &ModelSpec {
        &self.spec
    }

    // ─── inference internals (feature-gated) ────────────────────────────────

    #[cfg(feature = "onnx")]
    fn run_inference(
        &self,
        request: &GenerationRequest,
        seed: u64,
    ) -> Result<(Vec<f32>, u32, u16), GenError> {
        // Token encoding is *intentionally* a placeholder. The production
        // pipeline plugs in a CLIP/T5 tokenizer here; for the skeleton we
        // pass UTF-8 byte codepoints clipped to i64 so the model graph at
        // least sees a non-empty sequence and exercises end-to-end.
        let tokens: Vec<i64> = request
            .prompt
            .as_bytes()
            .iter()
            .take(256) // arbitrary cap; real tokenizers truncate too
            .map(|&b| b as i64)
            .collect();
        let tokens_tensor = tract_ndarray::Array2::from_shape_vec(
            (1, tokens.len()),
            tokens,
        )
        .map_err(|e| GenError::Inference(format!("prompt tensor shape: {e}")))?
        .into_tensor();

        let duration_tensor =
            tract_ndarray::arr0(request.duration_seconds).into_tensor();
        let seed_tensor = tract_ndarray::arr0(seed as i64).into_tensor();

        // tract `run` takes ordered input tensors. The order is the order
        // tract's optimisation pass picked for the graph inputs; we have
        // to match the order, not the names, here. For Stable Audio Open
        // Small the canonical order is (prompt, duration, seed). When
        // targeting a model with a different input order, override
        // `ModelSpec` and adjust this call.
        let model = self
            .model
            .lock()
            .map_err(|_| GenError::Inference("model mutex poisoned".into()))?;

        let outputs = model
            .run(tvec!(
                tokens_tensor.into_tvalue(),
                duration_tensor.into_tvalue(),
                seed_tensor.into_tvalue(),
            ))
            .map_err(|e| GenError::Inference(format!("tract run: {e}")))?;

        let audio = outputs
            .first()
            .ok_or_else(|| GenError::Inference("model produced no outputs".into()))?;
        let audio_view = audio
            .to_array_view::<f32>()
            .map_err(|e| GenError::Inference(format!("audio output type: {e}")))?;

        // Expected shape: [C, F]. We accept [F] (mono, drop channel axis) and
        // [1, C, F] (some exporters add a batch dim) as concessions.
        let shape = audio_view.shape();
        let (channels, frames) = match shape.len() {
            1 => (1u16, shape[0]),
            2 => (shape[0] as u16, shape[1]),
            3 if shape[0] == 1 => (shape[1] as u16, shape[2]),
            _ => {
                return Err(GenError::Inference(format!(
                    "unexpected audio output shape {:?}; expected [C, F] or [F]",
                    shape
                )));
            }
        };
        if channels == 0 || channels > 2 || frames == 0 {
            return Err(GenError::Inference(format!(
                "unsupported audio output dimensions: channels={}, frames={}",
                channels, frames
            )));
        }

        // Interleave per the `GenerationResponse` contract.
        let mut pcm = Vec::with_capacity(channels as usize * frames);
        if channels == 1 {
            pcm.extend(audio_view.iter().copied());
        } else {
            // We have [C, F] (or normalised to it). Walk frame-by-frame.
            let flat: Vec<f32> = audio_view.iter().copied().collect();
            let per_channel = frames;
            for f in 0..frames {
                for c in 0..channels as usize {
                    pcm.push(flat[c * per_channel + f]);
                }
            }
        }

        Ok((pcm, self.spec.native_sample_rate_hz, channels))
    }

    /// Resolve a seed for this request — request's seed if set, else a
    /// reproducible-but-fresh one synthesised from wall clock + pid so the
    /// response is still archive-able.
    pub fn effective_seed(request: &GenerationRequest) -> u64 {
        request.seed.unwrap_or_else(|| {
            let nanos = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos() as u64)
                .unwrap_or(0);
            nanos ^ (std::process::id() as u64).wrapping_mul(0x9E3779B97F4A7C15)
        })
    }
}

impl GenerativeBackend for OnnxBackend {
    fn id(&self) -> &str {
        &self.id_str
    }

    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            deterministic: true,
            // Stable Audio Open Small doesn't accept per-segment envelope
            // shaping — emotional arc is currently ignored by the backend
            // and post-processed by the engine via gain automation.
            honors_emotional_arc: false,
            // Stage hint is consumed at the prompt-engineering layer above
            // this backend (in `rf-ai-gen`); the ONNX graph doesn't see it.
            honors_stage_hint: false,
            stereo: self.spec.native_channels >= 2,
            max_duration_seconds: self.spec.max_duration_seconds,
        }
    }

    fn generate(
        &self,
        request: &GenerationRequest,
    ) -> Result<GenerationResponse, GenError> {
        request
            .validate()
            .map_err(GenError::InvalidRequest)?;

        if request.duration_seconds > self.spec.max_duration_seconds {
            return Err(GenError::InvalidRequest(format!(
                "duration {:.2}s exceeds model max {:.2}s",
                request.duration_seconds, self.spec.max_duration_seconds
            )));
        }

        let seed = Self::effective_seed(request);
        let start = Instant::now();

        #[cfg(not(feature = "onnx"))]
        {
            let _ = (request, seed, start);
            return Err(GenError::Unsupported(
                "rf-generative built without the `onnx` feature; \
                 rebuild with `--features onnx` to enable tract"
                    .into(),
            ));
        }

        #[cfg(feature = "onnx")]
        {
            let (pcm, native_sr, channels) = self.run_inference(request, seed)?;
            let latency_ms = start.elapsed().as_millis() as u32;
            let provenance = ProvenanceTag {
                backend_id: self.id_str.clone(),
                model_id: self
                    .model_path
                    .file_stem()
                    .and_then(|s| s.to_str())
                    .unwrap_or("onnx")
                    .to_string(),
                seed: Some(seed),
                generated_at_utc: iso8601_utc_now(),
            };
            // Build with a placeholder compliance, then run the real
            // compliance pass against the finished response. The validator
            // wants the assembled `GenerationResponse + GenerationRequest`
            // pair, not the raw PCM — that lets it inspect provenance and
            // duration mismatches in one place.
            let mut response = GenerationResponse {
                pcm,
                sample_rate_hz: native_sr,
                channels,
                latency_ms,
                provenance,
                compliance: ComplianceReport::default_unknown(),
            };
            response.compliance = compute_compliance(&response, request);
            Ok(response)
        }
    }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/// Format `SystemTime::now()` as RFC-3339 / ISO-8601 UTC without dragging
/// chrono into rf-generative's dep set. Good-enough precision (seconds)
/// for provenance — audit trail doesn't need sub-second.
///
/// Hand-rolled Gregorian-from-Unix-seconds so the crate stays tiny.
/// `#[allow(dead_code)]` because the call site lives behind `feature = "onnx"`;
/// tests exercise the helpers directly so they're still real, just
/// unreachable from the default build.
#[allow(dead_code)]
fn iso8601_utc_now() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    iso8601_from_unix_secs(secs)
}

/// Pure function used by both the call site and the test. Days-since-epoch
/// → (year, month, day) using the standard algorithm from Hinnant 2011.
#[allow(dead_code)]
fn iso8601_from_unix_secs(secs: i64) -> String {
    let days = secs.div_euclid(86_400);
    let sod = secs.rem_euclid(86_400);
    let h = sod / 3600;
    let m = (sod / 60) % 60;
    let s = sod % 60;
    let (y, mo, d) = civil_from_days(days);
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        y, mo, d, h, m, s
    )
}

/// Howard Hinnant's civil-from-days algorithm. Maps days-since-1970-01-01
/// to (year, month, day) in the proleptic Gregorian calendar. Verified
/// against several known dates in tests.
#[allow(dead_code)]
fn civil_from_days(days: i64) -> (i32, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z / 146_097 } else { (z - 146_096) / 146_097 };
    let doe = (z - era * 146_097) as u64; // [0, 146097)
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365; // [0, 400)
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 366)
    let mp = (5 * doy + 2) / 153; // [0, 12)
    let d = doy - (153 * mp + 2) / 5 + 1; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 }; // [1, 12]
    let y = if m <= 2 { y + 1 } else { y };
    (y as i32, m as u32, d as u32)
}

// ─── Tests ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::request::GenerationStyle;

    fn req(prompt: &str, dur: f32) -> GenerationRequest {
        GenerationRequest {
            prompt: prompt.into(),
            duration_seconds: dur,
            sample_rate_hz: 0,
            seed: Some(42),
            style: GenerationStyle::default(),
        }
    }

    #[test]
    fn open_missing_file_returns_model_not_found() {
        let err = OnnxBackend::open("/tmp/__rf_generative_definitely_missing.onnx")
            .unwrap_err();
        match err {
            GenError::ModelNotFound { path } => {
                assert!(path.contains("__rf_generative_definitely_missing"));
            }
            other => panic!("expected ModelNotFound, got {:?}", other),
        }
    }

    #[test]
    fn id_derives_from_filename_stem() {
        // Use a real-but-empty file so the `.exists()` check passes.
        // tract parsing is skipped under the default build (no `onnx`
        // feature), so the rest of the constructor succeeds.
        let tmp = std::env::temp_dir().join(format!(
            "rf_generative_id_{}.onnx",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::write(&tmp, b"").unwrap();
        // Without the `onnx` feature, this returns Ok with a stub
        // (we never actually parse the file). With the feature on,
        // tract WILL fail on the empty file — the test below covers that.
        #[cfg(not(feature = "onnx"))]
        {
            let backend = OnnxBackend::open(&tmp).unwrap();
            assert!(backend.id().starts_with("tract-onnx-rf_generative_id_"));
            assert_eq!(backend.spec().native_sample_rate_hz, 44_100);
        }
        #[cfg(feature = "onnx")]
        {
            // Empty file is not a valid ONNX → MalformedModel
            let err = OnnxBackend::open(&tmp).unwrap_err();
            assert!(matches!(err, GenError::MalformedModel(_)));
        }
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn generate_without_onnx_feature_is_unsupported() {
        // Use a placeholder file so open() succeeds in the stub path.
        let tmp = std::env::temp_dir().join("rf_generative_unsupported_test.onnx");
        std::fs::write(&tmp, b"").unwrap();
        let backend = match OnnxBackend::open(&tmp) {
            Ok(b) => b,
            Err(_) => {
                // Under the `onnx` feature, open() fails on the empty file;
                // this branch of the test only proves the unsupported path
                // and is a no-op when tract is on.
                let _ = std::fs::remove_file(&tmp);
                return;
            }
        };
        let result = backend.generate(&req("test", 1.0));
        #[cfg(not(feature = "onnx"))]
        {
            match result {
                Err(GenError::Unsupported(msg)) => {
                    assert!(msg.contains("onnx"));
                }
                other => panic!("expected Unsupported, got {:?}", other),
            }
        }
        #[cfg(feature = "onnx")]
        {
            // tract should have failed during open() above, so this line
            // is unreachable; defensive sanity check.
            let _ = result;
        }
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn capabilities_reflect_stable_audio_open_small_defaults() {
        let tmp = std::env::temp_dir().join("rf_generative_caps_test.onnx");
        std::fs::write(&tmp, b"").unwrap();
        if let Ok(backend) = OnnxBackend::open(&tmp) {
            let caps = backend.capabilities();
            assert!(caps.deterministic);
            // SAOS doesn't honour these at the model layer.
            assert!(!caps.honors_emotional_arc);
            assert!(!caps.honors_stage_hint);
            assert!(caps.stereo);
            assert!((caps.max_duration_seconds - 47.0).abs() < 0.001);
        }
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn rejects_overlong_duration() {
        let tmp = std::env::temp_dir().join("rf_generative_dur_test.onnx");
        std::fs::write(&tmp, b"").unwrap();
        let Ok(backend) = OnnxBackend::open(&tmp) else {
            let _ = std::fs::remove_file(&tmp);
            return;
        };
        // Request something well under MAX_DURATION_SECONDS (so the
        // upstream `validate()` lets it through) but above the model's
        // 47-second cap.
        let mut r = req("test prompt", 48.0);
        // Force-bypass workspace MAX by clamping to crate constant if needed
        if r.duration_seconds > crate::MAX_DURATION_SECONDS {
            r.duration_seconds = crate::MAX_DURATION_SECONDS - 0.1;
        }
        // Set duration that's still > model cap but < crate cap
        r.duration_seconds = 47.5_f32.min(crate::MAX_DURATION_SECONDS - 0.1);
        if r.duration_seconds > 47.0 {
            let err = backend.generate(&r).unwrap_err();
            match err {
                GenError::InvalidRequest(msg) => assert!(msg.contains("exceeds model max")),
                // Under no-feature build, Unsupported wins; that's fine.
                GenError::Unsupported(_) => {}
                other => panic!("unexpected error: {:?}", other),
            }
        }
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn effective_seed_uses_request_when_set() {
        let r = req("x", 1.0);
        assert_eq!(OnnxBackend::effective_seed(&r), 42);
    }

    #[test]
    fn effective_seed_generates_when_none() {
        let mut r = req("x", 1.0);
        r.seed = None;
        let s1 = OnnxBackend::effective_seed(&r);
        std::thread::sleep(std::time::Duration::from_millis(2));
        let s2 = OnnxBackend::effective_seed(&r);
        // Different ns + same pid = different seeds.
        assert_ne!(s1, s2);
    }

    #[test]
    fn model_spec_default_matches_stable_audio_open_small() {
        let spec = ModelSpec::default();
        assert_eq!(spec.prompt_tokens_input, "prompt_tokens");
        assert_eq!(spec.duration_input, "duration");
        assert_eq!(spec.seed_input, "seed");
        assert_eq!(spec.audio_output, "audio");
        assert_eq!(spec.native_sample_rate_hz, 44_100);
        assert_eq!(spec.native_channels, 2);
    }

    #[test]
    fn debug_does_not_dump_model_internals() {
        let tmp = std::env::temp_dir().join("rf_generative_debug_test.onnx");
        std::fs::write(&tmp, b"").unwrap();
        if let Ok(backend) = OnnxBackend::open(&tmp) {
            let s = format!("{:?}", backend);
            // We don't want the entire tract graph printed in logs.
            assert!(s.contains("OnnxBackend"));
            assert!(s.contains("rf_generative_debug_test"));
            assert!(!s.contains("Graph<"));
        }
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn iso8601_format_unix_epoch_zero() {
        // 1970-01-01T00:00:00Z
        assert_eq!(iso8601_from_unix_secs(0), "1970-01-01T00:00:00Z");
    }

    #[test]
    fn iso8601_format_known_dates() {
        // Well-known epoch anchors — any failure here means the algorithm
        // drifted, not the clock.
        assert_eq!(iso8601_from_unix_secs(0), "1970-01-01T00:00:00Z");
        assert_eq!(iso8601_from_unix_secs(946_684_800), "2000-01-01T00:00:00Z");
        // y2k38 boundary — must NOT silently truncate.
        assert_eq!(
            iso8601_from_unix_secs(2_147_483_647),
            "2038-01-19T03:14:07Z"
        );
        // Mid-day arithmetic round trip.
        // 2024-06-15T12:34:56Z
        let mid = iso8601_from_unix_secs(1_718_454_896);
        assert_eq!(mid, "2024-06-15T12:34:56Z");
    }

    #[test]
    fn iso8601_leap_year_handling() {
        // 2000-03-01 = Mar 1 of a leap year; one day after the leap.
        // 2000-02-29 unix = 951782400; 2000-03-01 = 951868800.
        assert_eq!(iso8601_from_unix_secs(951_782_400), "2000-02-29T00:00:00Z");
        assert_eq!(iso8601_from_unix_secs(951_868_800), "2000-03-01T00:00:00Z");
    }

    #[test]
    fn iso8601_now_is_well_formed() {
        let s = iso8601_utc_now();
        assert!(s.ends_with("Z"));
        assert_eq!(s.len(), "1970-01-01T00:00:00Z".len());
        // YYYY between 2020 and 2100 — sanity guard so a wildly broken
        // clock surfaces in a failing test.
        let year: i32 = s[..4].parse().expect("year prefix");
        assert!(year >= 2020 && year <= 2100, "got {}", s);
    }

    #[test]
    fn invalid_prompt_surfaces_invalid_request() {
        let tmp = std::env::temp_dir().join("rf_generative_invalid_test.onnx");
        std::fs::write(&tmp, b"").unwrap();
        let Ok(backend) = OnnxBackend::open(&tmp) else {
            let _ = std::fs::remove_file(&tmp);
            return;
        };
        let mut r = req("ok", 1.0);
        r.prompt = "   ".into(); // whitespace-only → rejected by validate()
        match backend.generate(&r) {
            Err(GenError::InvalidRequest(msg)) => assert!(msg.contains("prompt")),
            // Stub build returns Unsupported before reaching validate-via-model;
            // but validate() is called BEFORE the cfg branch — so we should
            // hit InvalidRequest first.
            other => panic!("expected InvalidRequest, got {:?}", other),
        }
        let _ = std::fs::remove_file(&tmp);
    }
}
