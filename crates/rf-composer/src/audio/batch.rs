//! Batch processor — turn a `StageAssetMap` into actual files on disk.
//!
//! Iterates every asset in every stage, classifies it, routes to the backend,
//! generates the file with bounded concurrency, reports progress, and produces
//! a `BatchOutput` with per-asset results.

use crate::audio::generator::{
    AudioBackendId, AudioGenerator, AudioPrompt, AudioResult,
};
use crate::audio::router::{classify, AudioRoutingTable};
use crate::schema::{AssetIntent, StageAssetMap};
use parking_lot::Mutex;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;
use tokio::sync::Semaphore;
use uuid::Uuid;

/// Maximum concurrent generation tasks (rate-limit safe for 99% of providers).
pub const DEFAULT_CONCURRENCY: usize = 4;

/// Inputs to a batch run.
#[derive(Debug, Clone)]
pub struct BatchJob {
    /// Output directory where files land. Created if missing.
    pub out_dir: PathBuf,
    /// Asset map to walk.
    pub map: StageAssetMap,
    /// Routing — which backend per `AudioKind`.
    pub routing: AudioRoutingTable,
    /// Default voice ID for TTS lines (overridable per-asset).
    pub default_voice_id: Option<String>,
    /// Bounded concurrency.
    pub concurrency: usize,
}

impl BatchJob {
    /// Sensible default concurrency (4) and routing.
    pub fn new(out_dir: PathBuf, map: StageAssetMap) -> Self {
        Self {
            out_dir,
            map,
            routing: AudioRoutingTable::defaults(),
            default_voice_id: None,
            concurrency: DEFAULT_CONCURRENCY,
        }
    }
}

/// One result per asset (success or failure).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssetResult {
    /// Stage this asset belongs to.
    pub stage_id: String,
    /// Suggested name from the asset map.
    pub asset_name: String,
    /// Backend that produced (or would have produced) this asset.
    pub backend: AudioBackendId,
    /// Output path on success.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<PathBuf>,
    /// Container format on success (mp3, wav).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub format: Option<String>,
    /// Bytes written on success.
    pub bytes: u64,
    /// Wall-clock duration milliseconds (best-effort).
    pub duration_ms: u32,
    /// Error message on failure.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl AssetResult {
    /// Whether this entry represents a success.
    pub fn ok(&self) -> bool {
        self.error.is_none() && self.path.is_some()
    }
}

/// Final outcome of a batch run.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchOutput {
    /// Correlation ID.
    pub job_id: String,
    /// One entry per asset.
    pub results: Vec<AssetResult>,
    /// Total assets attempted.
    pub total: u32,
    /// Successful generations.
    pub succeeded: u32,
    /// Failures.
    pub failed: u32,
    /// Wall-clock milliseconds across the entire batch.
    pub elapsed_ms: u32,
}

/// Live progress snapshot — surfaced to the UI by polling.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct BatchProgress {
    /// Whether a job is currently running.
    pub active: bool,
    /// Total assets in the active job.
    pub total: u32,
    /// Completed assets (success or failure).
    pub completed: u32,
    /// Successful generations.
    pub succeeded: u32,
    /// Failed generations.
    pub failed: u32,
    /// Currently-being-generated asset name (best-effort).
    pub current: Option<String>,
    /// Whether the user requested cancellation.
    pub cancel_requested: bool,
    /// Completed `AssetResult` entries — appended as work finishes so the UI
    /// can stream output without waiting for the whole batch.
    pub partial_results: Vec<AssetResult>,
}

/// Shared progress state between the running batch and external pollers.
#[derive(Default)]
pub struct ProgressHandle {
    inner: Mutex<BatchProgress>,
    completed: AtomicU32,
    succeeded: AtomicU32,
    failed: AtomicU32,
    cancel: AtomicBool,
}

impl ProgressHandle {
    /// Construct a fresh handle.
    pub fn new() -> Arc<Self> {
        Arc::new(Self::default())
    }

    /// Read a copy of the current progress.
    pub fn snapshot(&self) -> BatchProgress {
        let mut p = self.inner.lock().clone();
        p.completed = self.completed.load(Ordering::Relaxed);
        p.succeeded = self.succeeded.load(Ordering::Relaxed);
        p.failed = self.failed.load(Ordering::Relaxed);
        p.cancel_requested = self.cancel.load(Ordering::Relaxed);
        p
    }

    /// Request cancellation. In-flight tasks may still finish their HTTP call.
    pub fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
        self.inner.lock().cancel_requested = true;
    }

    /// Reset between jobs.
    pub fn reset(&self, total: u32) {
        self.completed.store(0, Ordering::Relaxed);
        self.succeeded.store(0, Ordering::Relaxed);
        self.failed.store(0, Ordering::Relaxed);
        self.cancel.store(false, Ordering::Relaxed);
        let mut p = self.inner.lock();
        *p = BatchProgress {
            active: true,
            total,
            ..Default::default()
        };
    }

    fn mark_current(&self, name: &str) {
        self.inner.lock().current = Some(name.to_string());
    }

    fn record(&self, result: AssetResult) {
        if result.ok() {
            self.succeeded.fetch_add(1, Ordering::Relaxed);
        } else {
            self.failed.fetch_add(1, Ordering::Relaxed);
        }
        self.completed.fetch_add(1, Ordering::Relaxed);
        self.inner.lock().partial_results.push(result);
    }

    fn finish(&self) {
        self.inner.lock().active = false;
    }

    fn cancel_requested(&self) -> bool {
        self.cancel.load(Ordering::Relaxed)
    }
}

/// Map of `AudioBackendId` → constructed generator.
pub type BackendMap = HashMap<AudioBackendId, Arc<dyn AudioGenerator>>;

/// Run a batch using the supplied backends and progress handle.
pub async fn run_batch(
    job: BatchJob,
    backends: BackendMap,
    progress: Arc<ProgressHandle>,
) -> AudioResult<BatchOutput> {
    let started = std::time::Instant::now();

    // Flatten asset list with stage_id context.
    let mut items: Vec<(String, AssetIntent)> = Vec::new();
    for stage in &job.map.stages {
        for asset in &stage.assets {
            items.push((stage.stage_id.clone(), asset.clone()));
        }
    }
    let total = items.len() as u32;

    progress.reset(total);

    let semaphore = Arc::new(Semaphore::new(job.concurrency.max(1)));
    let backends = Arc::new(backends);
    let routing = Arc::new(job.routing.clone());
    let out_dir = Arc::new(job.out_dir.clone());
    let default_voice = Arc::new(job.default_voice_id.clone());

    let mut handles = Vec::with_capacity(items.len());
    for (stage_id, asset) in items {
        if progress.cancel_requested() {
            break;
        }
        let permit = Arc::clone(&semaphore);
        let backends = Arc::clone(&backends);
        let routing = Arc::clone(&routing);
        let out_dir = Arc::clone(&out_dir);
        let default_voice = Arc::clone(&default_voice);
        let progress = Arc::clone(&progress);

        let handle = tokio::spawn(async move {
            let _p = match permit.acquire().await {
                Ok(p) => p,
                Err(_) => return None, // semaphore closed → cancellation
            };
            if progress.cancel_requested() {
                let res = AssetResult {
                    stage_id: stage_id.clone(),
                    asset_name: asset.suggested_name.clone(),
                    backend: AudioBackendId::Local,
                    path: None,
                    format: None,
                    bytes: 0,
                    duration_ms: 0,
                    error: Some("cancelled".to_string()),
                };
                progress.record(res.clone());
                return Some(res);
            }
            let kind = classify(&asset.kind);
            let backend_id = routing.route(kind);
            progress.mark_current(&asset.suggested_name);

            let prompt = AudioPrompt {
                prompt: asset.generation_prompt.clone(),
                kind,
                length_seconds: asset.length_ms.map(|ms| ms as f32 / 1000.0),
                voice_id: default_voice.as_deref().map(|s| s.to_string()),
                suggested_name: asset.suggested_name.clone(),
            };
            let stage_dir = out_dir.join(stage_id.to_lowercase());

            let res = match backends.get(&backend_id) {
                Some(backend) => match backend.generate(&prompt, &stage_dir).await {
                    Ok(out) => AssetResult {
                        stage_id: stage_id.clone(),
                        asset_name: asset.suggested_name.clone(),
                        backend: backend_id,
                        path: Some(out.path),
                        format: Some(out.format),
                        bytes: out.bytes,
                        duration_ms: out.duration_ms,
                        error: None,
                    },
                    Err(e) => AssetResult {
                        stage_id: stage_id.clone(),
                        asset_name: asset.suggested_name.clone(),
                        backend: backend_id,
                        path: None,
                        format: None,
                        bytes: 0,
                        duration_ms: 0,
                        error: Some(e.to_string()),
                    },
                },
                None => AssetResult {
                    stage_id: stage_id.clone(),
                    asset_name: asset.suggested_name.clone(),
                    backend: backend_id,
                    path: None,
                    format: None,
                    bytes: 0,
                    duration_ms: 0,
                    error: Some(format!(
                        "backend {:?} not configured",
                        backend_id
                    )),
                },
            };
            progress.record(res.clone());
            Some(res)
        });
        handles.push(handle);
    }

    let mut results = Vec::with_capacity(handles.len());
    for h in handles {
        if let Ok(Some(r)) = h.await {
            results.push(r);
        }
    }

    progress.finish();

    let succeeded = results.iter().filter(|r| r.ok()).count() as u32;
    let failed = results.len() as u32 - succeeded;

    Ok(BatchOutput {
        job_id: Uuid::new_v4().to_string(),
        results,
        total,
        succeeded,
        failed,
        elapsed_ms: started.elapsed().as_millis() as u32,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::audio::generator::{AudioError, AudioOutput};
    use crate::schema::{ComplianceHints, StageIntent};
    use async_trait::async_trait;
    use std::path::Path;

    #[derive(Default)]
    struct MockGen {
        calls: Mutex<u32>,
        fail_after: Option<u32>,
    }

    #[async_trait]
    impl AudioGenerator for MockGen {
        fn id(&self) -> AudioBackendId {
            AudioBackendId::Local
        }
        async fn health_check(&self) -> AudioResult<()> {
            Ok(())
        }
        async fn generate(&self, p: &AudioPrompt, dir: &Path) -> AudioResult<AudioOutput> {
            let n = {
                let mut c = self.calls.lock();
                *c += 1;
                *c
            };
            if let Some(after) = self.fail_after {
                if n > after {
                    return Err(AudioError::Network("forced".to_string()));
                }
            }
            tokio::fs::create_dir_all(dir).await.unwrap();
            let path = dir.join(format!("{}.wav", p.suggested_name));
            tokio::fs::write(&path, b"RIFF...placeholder").await.unwrap();
            Ok(AudioOutput {
                path,
                format: "wav".to_string(),
                duration_ms: 100,
                bytes: 18,
                backend: AudioBackendId::Local,
                prompt: p.prompt.clone(),
                kind: p.kind,
            })
        }
    }

    fn make_map() -> StageAssetMap {
        let stages = vec![
            StageIntent {
                stage_id: "REEL_SPIN_START".to_string(),
                assets: vec![AssetIntent {
                    kind: "oneshot".to_string(),
                    suggested_name: "spin_start".to_string(),
                    mood: "anticipation".to_string(),
                    dynamic_level: 70,
                    length_ms: Some(500),
                    bus: "sfx".to_string(),
                    generation_prompt: "spin start sound".to_string(),
                }],
            },
            StageIntent {
                stage_id: "BIG_WIN".to_string(),
                assets: vec![AssetIntent {
                    kind: "sting".to_string(),
                    suggested_name: "big_win_sting".to_string(),
                    mood: "celebration".to_string(),
                    dynamic_level: 95,
                    length_ms: Some(2000),
                    bus: "sfx".to_string(),
                    generation_prompt: "huge win sting".to_string(),
                }],
            },
        ];
        StageAssetMap {
            theme: "test".to_string(),
            mood: "neutral".to_string(),
            target_bpm: 120,
            stages,
            compliance_hints: ComplianceHints::default(),
            self_quality_score: 0,
            self_critique: String::new(),
        }
    }

    #[tokio::test]
    async fn batch_routes_to_local_when_only_local_configured() {
        let map = make_map();
        let dir = std::env::temp_dir().join("rf-batch-test1");
        let _ = std::fs::remove_dir_all(&dir);
        let mut routing = AudioRoutingTable::air_gapped();
        // Force Local for everything.
        let _ = &mut routing;
        let job = BatchJob {
            out_dir: dir,
            map,
            routing,
            default_voice_id: None,
            concurrency: 2,
        };
        let mock: Arc<dyn AudioGenerator> = Arc::new(MockGen::default());
        let mut backends = BackendMap::new();
        backends.insert(AudioBackendId::Local, mock);

        let progress = ProgressHandle::new();
        let out = run_batch(job, backends, progress).await.unwrap();
        assert_eq!(out.total, 2);
        assert_eq!(out.succeeded, 2);
        assert_eq!(out.failed, 0);
        assert!(out.results.iter().all(|r| r.ok()));
    }

    #[tokio::test]
    async fn batch_records_failures() {
        let map = make_map();
        let dir = std::env::temp_dir().join("rf-batch-test2");
        let _ = std::fs::remove_dir_all(&dir);
        let routing = AudioRoutingTable::air_gapped();
        let job = BatchJob {
            out_dir: dir,
            map,
            routing,
            default_voice_id: None,
            concurrency: 1,
        };
        let mock: Arc<dyn AudioGenerator> = Arc::new(MockGen {
            calls: Mutex::new(0),
            fail_after: Some(1), // first OK, then fail
        });
        let mut backends = BackendMap::new();
        backends.insert(AudioBackendId::Local, mock);
        let progress = ProgressHandle::new();
        let out = run_batch(job, backends, progress).await.unwrap();
        assert_eq!(out.total, 2);
        assert_eq!(out.succeeded, 1);
        assert_eq!(out.failed, 1);
    }

    #[tokio::test]
    async fn missing_backend_records_per_asset_error() {
        let map = make_map();
        let dir = std::env::temp_dir().join("rf-batch-test3");
        let _ = std::fs::remove_dir_all(&dir);
        let routing = AudioRoutingTable::defaults(); // routes SFX to ElevenLabs
        let job = BatchJob {
            out_dir: dir,
            map,
            routing,
            default_voice_id: None,
            concurrency: 1,
        };
        // Backends map empty → all assets fail with "backend not configured".
        let backends = BackendMap::new();
        let progress = ProgressHandle::new();
        let out = run_batch(job, backends, progress).await.unwrap();
        assert_eq!(out.total, 2);
        assert_eq!(out.succeeded, 0);
        assert_eq!(out.failed, 2);
        for r in &out.results {
            assert!(r.error.as_deref().unwrap().contains("not configured"));
        }
    }

    #[test]
    fn progress_handle_cancel_round_trip() {
        let p = ProgressHandle::new();
        p.reset(10);
        assert!(!p.snapshot().cancel_requested);
        p.cancel();
        assert!(p.snapshot().cancel_requested);
    }

    #[test]
    fn progress_handle_record_increments_counters() {
        let p = ProgressHandle::new();
        p.reset(2);
        p.record(AssetResult {
            stage_id: "s".to_string(),
            asset_name: "a".to_string(),
            backend: AudioBackendId::Local,
            path: Some(PathBuf::from("/tmp/x.wav")),
            format: Some("wav".to_string()),
            bytes: 100,
            duration_ms: 1000,
            error: None,
        });
        let snap = p.snapshot();
        assert_eq!(snap.completed, 1);
        assert_eq!(snap.succeeded, 1);
        assert_eq!(snap.failed, 0);

        p.record(AssetResult {
            stage_id: "s".to_string(),
            asset_name: "b".to_string(),
            backend: AudioBackendId::Local,
            path: None,
            format: None,
            bytes: 0,
            duration_ms: 0,
            error: Some("fail".to_string()),
        });
        let snap = p.snapshot();
        assert_eq!(snap.completed, 2);
        assert_eq!(snap.succeeded, 1);
        assert_eq!(snap.failed, 1);
    }
}
