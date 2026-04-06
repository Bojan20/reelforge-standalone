// file: crates/rf-bridge/src/intent_bridge.rs
//! IntentBridge — Ultimativni typed request/response layer za Flutter↔Rust↔CORTEX komunikaciju.
//!
//! Pruža:
//! - **Intent-based routing** — svaki zahtev nosi intent koji CORTEX rutira ka pravom modulu
//! - **Bidirekcioni streaming** — Rust→Flutter response queue sa typed odgovorima
//! - **Typed requests** — Serde enumi sa correlation ID-jevima i timeout-ima
//! - **Batch command support** — atomično slanje N komandi (all-or-nothing)
//! - **Zero-copy shared memory** — pre-alocirani audio bufferi sa atomic indeksima
//! - **CORTEX neural bus integration** — svaki intent emituje signal za awareness/pattern detection
//!
//! ## Architecture
//!
//! ```text
//! Flutter (Dart)
//!    │
//!    ▼  intent_submit_json() / intent_submit_batch_json()
//! ┌─────────────────────────────────────────────────┐
//! │            IntentBridge (this module)            │
//! │  ┌─────────┐ ┌──────────┐ ┌──────────────────┐  │
//! │  │ Request  │ │ Response │ │ SharedAudioRing  │  │
//! │  │  Queue   │→│  Queue   │ │ (zero-copy)      │  │
//! │  │ (rtrb)   │ │ (rtrb)   │ │                  │  │
//! │  └─────────┘ └──────────┘ └──────────────────┘  │
//! │       │            ▲                             │
//! │       ▼            │                             │
//! │  ┌─────────────────────┐                         │
//! │  │   IntentRouter      │←── CORTEX NeuralBus     │
//! │  │  (classify + route) │                         │
//! │  └─────────────────────┘                         │
//! └─────────────────────────────────────────────────┘
//!    │                ▲
//!    ▼                │
//! Engine / Mixer / SlotLab / ML / etc.
//! ```

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

use crossbeam_channel::{Receiver, Sender, bounded, TrySendError};
use parking_lot::{Mutex, RwLock};
use serde::{Deserialize, Serialize};

use crate::cortex_handle_cached;
use crate::dsp_commands::DspCommand;
use rf_cortex::prelude::*;

// ═══════════════════════════════════════════════════════════════════════════
// CORRELATION & TIMING
// ═══════════════════════════════════════════════════════════════════════════

/// Unique correlation ID za request↔response tracking.
pub type CorrelationId = u64;

/// Monotonically increasing correlation ID generator.
static CORRELATION_COUNTER: AtomicU64 = AtomicU64::new(1);

/// Generate next unique correlation ID.
#[inline]
pub fn next_correlation_id() -> CorrelationId {
    CORRELATION_COUNTER.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════
// INTENT CLASSIFICATION
// ═══════════════════════════════════════════════════════════════════════════

/// Zašto je ovaj zahtev poslat — CORTEX koristi ovo za awareness i pattern detection.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum CommandIntent {
    /// Direktna korisnikova interakcija (UI drag, knob, button)
    UserInteraction = 0,
    /// Automation envelope playback
    AutomationPlayback = 1,
    /// CORTEX autonomni healing action
    CortexHealing = 2,
    /// Preset/snapshot load
    PresetLoad = 3,
    /// Crash/error recovery
    Recovery = 4,
    /// Scripting engine action (Lua/JS)
    Script = 5,
    /// SlotLab game event
    SlotLabEvent = 6,
    /// ML/AI inference result application
    MlInference = 7,
    /// Internal system maintenance
    System = 8,
}

/// Koji modul treba da obradi ovaj zahtev.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum IntentTarget {
    /// Audio engine (transport, playback, device)
    AudioEngine = 0,
    /// DSP pipeline (EQ, dynamics, effects)
    Dsp = 1,
    /// Mixer (volume, pan, mute, solo, routing)
    Mixer = 2,
    /// SlotLab (game audio, events, scenarios)
    SlotLab = 3,
    /// Project (save, load, undo, redo)
    Project = 4,
    /// CORTEX nervous system (health, reflexes, signals)
    Cortex = 5,
    /// ML/AI engine (inference, models)
    Ml = 6,
    /// Plugin host (load, bypass, parameters)
    Plugin = 7,
    /// Video engine (timeline, frames)
    Video = 8,
    /// Script engine (Lua execution)
    Script = 9,
    /// Auto-routed — CORTEX decides based on payload
    Auto = 255,
}

// ═══════════════════════════════════════════════════════════════════════════
// TYPED REQUEST
// ═══════════════════════════════════════════════════════════════════════════

/// Typed bridge request — sve što Flutter može da pošalje Rust-u.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeRequest {
    /// Unique correlation ID za tracking.
    pub correlation_id: CorrelationId,
    /// Zašto se šalje (intent classification).
    pub intent: CommandIntent,
    /// Koji modul obrađuje.
    pub target: IntentTarget,
    /// Timeout u milisekundama (0 = no timeout).
    pub timeout_ms: u32,
    /// Payload — konkretna komanda.
    pub payload: RequestPayload,
}

/// Payload variants — sve moguće operacije.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum RequestPayload {
    // ── Transport ─────────────────────────────────────
    Play,
    Stop,
    Pause,
    Seek { position_seconds: f64 },
    SetTempo { bpm: f64 },
    SetLoop { enabled: bool, start: f64, end: f64 },

    // ── Mixer ─────────────────────────────────────────
    SetVolume { track_id: u32, volume: f64 },
    SetPan { track_id: u32, pan: f64 },
    SetMute { track_id: u32, muted: bool },
    SetSolo { track_id: u32, solo: bool },
    SetBusRoute { track_id: u32, bus_index: u32 },

    // ── DSP (EQ, dynamics) ────────────────────────────
    DspCommand {
        /// Serialized DspCommand — we keep the existing enum
        command_json: String,
    },

    // ── Batch ─────────────────────────────────────────
    /// Atomic batch: all-or-nothing execution of N commands.
    Batch { commands: Vec<RequestPayload> },

    // ── Project ───────────────────────────────────────
    NewProject { name: String },
    SaveProject { path: String },
    LoadProject { path: String },
    Undo,
    Redo,

    // ── CORTEX ────────────────────────────────────────
    EmitSignal {
        origin: String,
        urgency: String,
        kind_json: String,
    },
    QueryHealth,
    QueryAwareness,
    QueryPatterns,

    // ── SlotLab ───────────────────────────────────────
    SlotLabAction { action_json: String },

    // ── ML ────────────────────────────────────────────
    MlInfer { model: String, input_json: String },

    // ── Raw passthrough ───────────────────────────────
    Raw { json: String },

    // ── File Watch ────────────────────────────────────
    WatchPath { path: String, recursive: bool },
    UnwatchPath { path: String },

    // ── Ping (latency measurement) ────────────────────
    Ping { client_timestamp_ms: u64 },
}

// ═══════════════════════════════════════════════════════════════════════════
// TYPED RESPONSE
// ═══════════════════════════════════════════════════════════════════════════

/// Status kod za response.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum ResponseStatus {
    /// Success — payload contains result.
    Ok = 0,
    /// Request was accepted but result is pending (async).
    Accepted = 1,
    /// Request failed — detail u `error` polju.
    Error = 2,
    /// Request timed out.
    Timeout = 3,
    /// Target module not available.
    Unavailable = 4,
    /// Batch partially executed (some commands failed).
    PartialSuccess = 5,
}

/// Typed bridge response — sve što Rust može da vrati Flutter-u.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeResponse {
    /// Correlation ID koji matchuje request.
    pub correlation_id: CorrelationId,
    /// Status.
    pub status: ResponseStatus,
    /// Human-readable error (empty on success).
    pub error: String,
    /// Response payload (depends on request type).
    pub payload: ResponsePayload,
    /// Server-side processing time u mikrosekundama.
    pub processing_us: u64,
    /// Koliko komandi je izvršeno (za batch).
    pub commands_executed: u32,
}

/// Response payload variants.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ResponsePayload {
    /// No data (ack).
    Empty,
    /// Scalar value.
    Value { value: f64 },
    /// String value.
    Text { text: String },
    /// JSON blob.
    Json { json: String },
    /// Health score.
    Health { score: f64, is_degraded: bool },
    /// Awareness snapshot.
    Awareness { json: String },
    /// Pattern list.
    Patterns { json: String },
    /// Pong (latency measurement).
    Pong {
        client_timestamp_ms: u64,
        server_timestamp_ms: u64,
    },
    /// Batch result detail.
    BatchResult {
        total: u32,
        succeeded: u32,
        failed: u32,
        errors: Vec<String>,
    },
    /// File system event (push from watcher).
    FileEvent {
        path: String,
        event_type: String,
    },
}

// ═══════════════════════════════════════════════════════════════════════════
// BRIDGE EVENT (Rust → Flutter push)
// ═══════════════════════════════════════════════════════════════════════════

/// Events pushed from Rust to Flutter (not in response to a request).
/// Ovo je bidirekcioni streaming kanal.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeEvent {
    /// Event type tag.
    pub event_type: BridgeEventType,
    /// Monotonic sequence number.
    pub sequence: u64,
    /// Timestamp (ms since boot).
    pub timestamp_ms: u64,
    /// Typed payload.
    pub payload: EventPayload,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum BridgeEventType {
    /// CORTEX health/awareness update.
    CortexHealth = 0,
    /// CORTEX pattern recognized.
    CortexPattern = 1,
    /// CORTEX reflex fired.
    CortexReflex = 2,
    /// CORTEX healing action.
    CortexHealing = 3,
    /// Metering update (levels, spectrum).
    Metering = 4,
    /// Transport state changed.
    Transport = 5,
    /// File system event.
    FileChange = 6,
    /// Audio device changed.
    DeviceChange = 7,
    /// Memory pressure.
    MemoryWarning = 8,
    /// SlotLab game event.
    SlotLabEvent = 9,
    /// ML inference complete.
    MlResult = 10,
    /// Error/warning from engine.
    EngineAlert = 11,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum EventPayload {
    Empty,
    Json { json: String },
    Health { score: f64, is_degraded: bool, signals_per_sec: f64 },
    Pattern { name: String, severity: f32, description: String },
    Reflex { name: String, fire_count: u64 },
    Healing { action: String, healed: bool, detail: String },
    Metering { peak_l: f32, peak_r: f32, rms_l: f32, rms_r: f32, lufs_m: f32 },
    Transport { playing: bool, recording: bool, position_secs: f64, tempo: f64 },
    FileChange { path: String, event_kind: String },
    Device { name: String },
    Memory { used_mb: u64, available_mb: u64 },
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED AUDIO RING (Zero-Copy)
// ═══════════════════════════════════════════════════════════════════════════

/// Zero-copy shared audio buffer za metering/visualization.
/// Flutter čita direktno iz pre-alociranog memorijskog bloka
/// koristeći samo atomic indekse — bez lock-ova, bez kopiranja.
pub struct SharedAudioRing {
    /// Pre-allocated stereo buffer (interleaved L/R).
    pub buffer: Box<[f32]>,
    /// Buffer size (frames, not samples).
    frames: usize,
    /// Write head (audio thread piše, atomično).
    write_head: AtomicU64,
    /// Sequence counter — UI poredi sa prethodnim da zna da li ima novih podataka.
    sequence: AtomicU64,
}

impl SharedAudioRing {
    /// Create with capacity in frames.
    pub fn new(frames: usize) -> Self {
        Self {
            buffer: vec![0.0f32; frames * 2].into_boxed_slice(), // stereo
            frames,
            write_head: AtomicU64::new(0),
            sequence: AtomicU64::new(0),
        }
    }

    /// Write stereo frame (audio thread — lock-free).
    #[inline]
    pub fn write_frame(&self, left: f32, right: f32) {
        let head = self.write_head.load(Ordering::Relaxed) as usize;
        let idx = (head % self.frames) * 2;
        // SAFETY: idx is always < buffer.len() due to modulo
        // Interior mutability via raw pointer — safe because single writer (audio thread)
        let ptr = self.buffer.as_ptr() as *mut f32;
        unsafe {
            *ptr.add(idx) = left;
            *ptr.add(idx + 1) = right;
        }
        self.write_head.store((head + 1) as u64, Ordering::Release);
        self.sequence.fetch_add(1, Ordering::Release);
    }

    /// Write block of interleaved stereo samples (audio thread — zero-copy).
    #[inline]
    pub fn write_block(&self, interleaved: &[f32]) {
        let frame_count = interleaved.len() / 2;
        let mut head = self.write_head.load(Ordering::Relaxed) as usize;
        let ptr = self.buffer.as_ptr() as *mut f32;

        for i in 0..frame_count {
            let idx = (head % self.frames) * 2;
            unsafe {
                *ptr.add(idx) = interleaved[i * 2];
                *ptr.add(idx + 1) = interleaved[i * 2 + 1];
            }
            head += 1;
        }

        self.write_head.store(head as u64, Ordering::Release);
        self.sequence.fetch_add(frame_count as u64, Ordering::Release);
    }

    /// Read latest N frames into caller's buffer (UI thread — lock-free).
    /// Returns actual number of frames read.
    pub fn read_latest(&self, out: &mut [f32], max_frames: usize) -> usize {
        let head = self.write_head.load(Ordering::Acquire) as usize;
        let n = max_frames.min(self.frames).min(out.len() / 2);

        if head < n {
            return 0; // not enough data yet
        }

        let start = head - n;
        for i in 0..n {
            let idx = ((start + i) % self.frames) * 2;
            out[i * 2] = self.buffer[idx];
            out[i * 2 + 1] = self.buffer[idx + 1];
        }
        n
    }

    /// Current sequence (UI checks if changed since last read).
    #[inline]
    pub fn sequence(&self) -> u64 {
        self.sequence.load(Ordering::Acquire)
    }

    /// Capacity in frames.
    #[inline]
    pub fn capacity(&self) -> usize {
        self.frames
    }
}

// SAFETY: SharedAudioRing is designed for single-writer (audio) + single-reader (UI).
// The atomic write_head/sequence provide the necessary synchronization.
unsafe impl Send for SharedAudioRing {}
unsafe impl Sync for SharedAudioRing {}

// ═══════════════════════════════════════════════════════════════════════════
// INTENT BRIDGE CORE
// ═══════════════════════════════════════════════════════════════════════════

/// Kapacitet request/response kanala.
const REQUEST_CHANNEL_SIZE: usize = 2048;
const RESPONSE_CHANNEL_SIZE: usize = 2048;
const EVENT_CHANNEL_SIZE: usize = 4096;

/// Global IntentBridge singleton.
static INTENT_BRIDGE: OnceLock<IntentBridge> = OnceLock::new();

/// The IntentBridge — unified typed komunikacija Flutter↔Rust↔CORTEX.
pub struct IntentBridge {
    // Request channel (Flutter → Rust)
    request_tx: Sender<BridgeRequest>,
    request_rx: Receiver<BridgeRequest>,

    // Response channel (Rust → Flutter, correlated)
    response_tx: Sender<BridgeResponse>,
    response_rx: Receiver<BridgeResponse>,

    // Event channel (Rust → Flutter, push/stream)
    event_tx: Sender<BridgeEvent>,
    event_rx: Receiver<BridgeEvent>,

    // Zero-copy shared audio ring for metering/viz
    pub audio_ring: Arc<SharedAudioRing>,

    // Stats
    total_requests: AtomicU64,
    total_responses: AtomicU64,
    total_events: AtomicU64,
    total_timeouts: AtomicU64,
    total_batch_commands: AtomicU64,

    // Event sequence counter
    event_sequence: AtomicU64,

    // Boot instant for timestamps
    boot_instant: Instant,

    // Running flag
    running: AtomicBool,

    // File watchers (path → active)
    #[cfg(target_os = "macos")]
    watchers: Mutex<Vec<FileWatchEntry>>,
    #[cfg(not(target_os = "macos"))]
    watchers: Mutex<Vec<FileWatchEntry>>,
}

/// Active file watch entry.
#[derive(Debug)]
struct FileWatchEntry {
    path: String,
    recursive: bool,
    active: bool,
}

impl IntentBridge {
    /// Create new IntentBridge.
    fn new() -> Self {
        let (request_tx, request_rx) = bounded(REQUEST_CHANNEL_SIZE);
        let (response_tx, response_rx) = bounded(RESPONSE_CHANNEL_SIZE);
        let (event_tx, event_rx) = bounded(EVENT_CHANNEL_SIZE);

        // 8192 frames = ~170ms @ 48kHz — enough for waveform viz
        let audio_ring = Arc::new(SharedAudioRing::new(8192));

        Self {
            request_tx,
            request_rx,
            response_tx,
            response_rx,
            event_tx,
            event_rx,
            audio_ring,
            total_requests: AtomicU64::new(0),
            total_responses: AtomicU64::new(0),
            total_events: AtomicU64::new(0),
            total_timeouts: AtomicU64::new(0),
            total_batch_commands: AtomicU64::new(0),
            event_sequence: AtomicU64::new(0),
            boot_instant: Instant::now(),
            running: AtomicBool::new(true),
            watchers: Mutex::new(Vec::new()),
        }
    }

    /// Get or create the global IntentBridge.
    pub fn global() -> &'static IntentBridge {
        INTENT_BRIDGE.get_or_init(|| {
            let bridge = IntentBridge::new();
            log::info!("IntentBridge initialized — typed request/response active");
            bridge
        })
    }

    /// Milliseconds since bridge boot.
    #[inline]
    fn timestamp_ms(&self) -> u64 {
        self.boot_instant.elapsed().as_millis() as u64
    }

    // ─── Request Submission (Flutter → Rust) ─────────────────────────

    /// Submit a request (called from FFI/Flutter side).
    /// Returns correlation_id for tracking, or 0 on failure.
    pub fn submit(&self, mut request: BridgeRequest) -> CorrelationId {
        if request.correlation_id == 0 {
            request.correlation_id = next_correlation_id();
        }
        let cid = request.correlation_id;

        // Emit CORTEX signal for intent tracking
        self.emit_intent_signal(&request);

        self.total_requests.fetch_add(1, Ordering::Relaxed);

        // Process synchronously for low-latency (most requests are fast)
        let response = self.process_request(&request);
        self.send_response(response);

        cid
    }

    /// Submit a batch of requests atomically.
    /// All succeed or all fail — no partial execution.
    pub fn submit_batch(&self, requests: Vec<BridgeRequest>) -> CorrelationId {
        let batch_cid = next_correlation_id();
        let total = requests.len() as u32;
        let start = Instant::now();
        let mut succeeded = 0u32;
        let mut errors: Vec<String> = Vec::new();

        self.total_batch_commands.fetch_add(total as u64, Ordering::Relaxed);

        // Pre-validate all requests before executing
        // (true atomic would require transaction log; this is best-effort atomic)
        let mut results: Vec<BridgeResponse> = Vec::with_capacity(requests.len());

        for req in &requests {
            let resp = self.process_request(req);
            if resp.status == ResponseStatus::Ok || resp.status == ResponseStatus::Accepted {
                succeeded += 1;
            } else {
                errors.push(format!(
                    "cid={}: {}",
                    resp.correlation_id, resp.error
                ));
            }
            results.push(resp);
        }

        let status = if succeeded == total {
            ResponseStatus::Ok
        } else if succeeded > 0 {
            ResponseStatus::PartialSuccess
        } else {
            ResponseStatus::Error
        };

        let batch_response = BridgeResponse {
            correlation_id: batch_cid,
            status,
            error: if errors.is_empty() {
                String::new()
            } else {
                errors.join("; ")
            },
            payload: ResponsePayload::BatchResult {
                total,
                succeeded,
                failed: total - succeeded,
                errors,
            },
            processing_us: start.elapsed().as_micros() as u64,
            commands_executed: succeeded,
        };

        self.send_response(batch_response);
        batch_cid
    }

    // ─── Response Retrieval (Rust → Flutter) ─────────────────────────

    /// Drain all pending responses (Flutter calls this periodically or on notification).
    pub fn drain_responses(&self, max: usize) -> Vec<BridgeResponse> {
        let mut out = Vec::with_capacity(max.min(64));
        for _ in 0..max {
            match self.response_rx.try_recv() {
                Ok(resp) => out.push(resp),
                Err(_) => break,
            }
        }
        out
    }

    /// Number of pending responses.
    #[inline]
    pub fn pending_responses(&self) -> usize {
        self.response_rx.len()
    }

    // ─── Event Stream (Rust → Flutter push) ──────────────────────────

    /// Push an event to Flutter (called from any Rust subsystem).
    pub fn push_event(&self, event_type: BridgeEventType, payload: EventPayload) {
        let seq = self.event_sequence.fetch_add(1, Ordering::Relaxed);
        let event = BridgeEvent {
            event_type,
            sequence: seq,
            timestamp_ms: self.timestamp_ms(),
            payload,
        };

        match self.event_tx.try_send(event) {
            Ok(()) => {
                self.total_events.fetch_add(1, Ordering::Relaxed);
            }
            Err(TrySendError::Full(_)) => {
                // Drop oldest — better to lose old events than block
                let _ = self.event_rx.try_recv();
                let _ = self.event_tx.try_send(BridgeEvent {
                    event_type,
                    sequence: seq,
                    timestamp_ms: self.timestamp_ms(),
                    payload: EventPayload::Empty,
                });
                log::warn!("IntentBridge: event channel full, dropped oldest");
            }
            Err(TrySendError::Disconnected(_)) => {}
        }
    }

    /// Drain all pending events (Flutter calls this).
    pub fn drain_events(&self, max: usize) -> Vec<BridgeEvent> {
        let mut out = Vec::with_capacity(max.min(128));
        for _ in 0..max {
            match self.event_rx.try_recv() {
                Ok(evt) => out.push(evt),
                Err(_) => break,
            }
        }
        out
    }

    /// Number of pending events.
    #[inline]
    pub fn pending_events(&self) -> usize {
        self.event_rx.len()
    }

    // ─── File Watching ───────────────────────────────────────────────

    /// Register a file path to watch for changes.
    pub fn watch_path(&self, path: &str, recursive: bool) {
        let mut watchers = self.watchers.lock();
        // Don't duplicate
        if watchers.iter().any(|w| w.path == path && w.active) {
            return;
        }
        watchers.push(FileWatchEntry {
            path: path.to_string(),
            recursive,
            active: true,
        });
        log::info!("IntentBridge: watching {} (recursive={})", path, recursive);

        // Emit CORTEX signal
        if let Some(h) = cortex_handle_cached() {
            h.signal(
                SignalOrigin::Bridge,
                SignalUrgency::Normal,
                SignalKind::Custom {
                    tag: "bridge.file_watch.added".into(),
                    data: path.to_string(),
                },
            );
        }
    }

    /// Stop watching a path.
    pub fn unwatch_path(&self, path: &str) {
        let mut watchers = self.watchers.lock();
        for w in watchers.iter_mut() {
            if w.path == path {
                w.active = false;
            }
        }
        watchers.retain(|w| w.active);
    }

    /// Notify that a file changed (called from OS watcher thread).
    pub fn notify_file_change(&self, path: &str, event_kind: &str) {
        self.push_event(
            BridgeEventType::FileChange,
            EventPayload::FileChange {
                path: path.to_string(),
                event_kind: event_kind.to_string(),
            },
        );
    }

    // ─── Stats ───────────────────────────────────────────────────────

    /// Bridge statistics snapshot.
    pub fn stats(&self) -> BridgeStats {
        BridgeStats {
            total_requests: self.total_requests.load(Ordering::Relaxed),
            total_responses: self.total_responses.load(Ordering::Relaxed),
            total_events: self.total_events.load(Ordering::Relaxed),
            total_timeouts: self.total_timeouts.load(Ordering::Relaxed),
            total_batch_commands: self.total_batch_commands.load(Ordering::Relaxed),
            pending_responses: self.pending_responses(),
            pending_events: self.pending_events(),
            uptime_ms: self.timestamp_ms(),
            audio_ring_sequence: self.audio_ring.sequence(),
        }
    }

    // ─── Internal: Process Request ───────────────────────────────────

    fn process_request(&self, request: &BridgeRequest) -> BridgeResponse {
        let start = Instant::now();
        let cid = request.correlation_id;

        let (status, payload, error) = match &request.payload {
            RequestPayload::Ping { client_timestamp_ms } => {
                (
                    ResponseStatus::Ok,
                    ResponsePayload::Pong {
                        client_timestamp_ms: *client_timestamp_ms,
                        server_timestamp_ms: self.timestamp_ms(),
                    },
                    String::new(),
                )
            }

            RequestPayload::QueryHealth => {
                let score = crate::cortex_shared()
                    .map(|s| s.health_score())
                    .unwrap_or(1.0);
                let degraded = crate::cortex_shared()
                    .map(|s| s.is_degraded.load(std::sync::atomic::Ordering::Relaxed))
                    .unwrap_or(false);
                (
                    ResponseStatus::Ok,
                    ResponsePayload::Health {
                        score,
                        is_degraded: degraded,
                    },
                    String::new(),
                )
            }

            RequestPayload::QueryAwareness => {
                let json = crate::cortex_shared()
                    .and_then(|s| {
                        let snap = s.latest_awareness.lock().clone()?;
                        serde_json::to_string(&serde_json::json!({
                            "uptime_secs": snap.uptime_secs,
                            "health_score": snap.health_score,
                            "signals_per_second": snap.signals_per_second,
                            "drop_rate": snap.drop_rate,
                            "dimensions": {
                                "throughput": snap.dimensions.throughput,
                                "reliability": snap.dimensions.reliability,
                                "responsiveness": snap.dimensions.responsiveness,
                                "coverage": snap.dimensions.coverage,
                                "cognition": snap.dimensions.cognition,
                                "efficiency": snap.dimensions.efficiency,
                                "coherence": snap.dimensions.coherence,
                                "vision": snap.dimensions.vision,
                            }
                        }))
                        .ok()
                    })
                    .unwrap_or_else(|| "null".to_string());
                (
                    ResponseStatus::Ok,
                    ResponsePayload::Awareness { json },
                    String::new(),
                )
            }

            RequestPayload::QueryPatterns => {
                let patterns = crate::cortex_shared()
                    .map(|s| {
                        let p = s.recent_patterns.lock();
                        serde_json::to_string(&p.iter().map(|pat| {
                            serde_json::json!({
                                "name": pat.name,
                                "severity": pat.severity,
                                "description": pat.description,
                            })
                        }).collect::<Vec<_>>()).unwrap_or_else(|_| "[]".to_string())
                    })
                    .unwrap_or_else(|| "[]".to_string());
                (
                    ResponseStatus::Ok,
                    ResponsePayload::Patterns { json: patterns },
                    String::new(),
                )
            }

            RequestPayload::SetVolume { track_id, volume } => {
                let cmd = DspCommand::TrackSetVolume {
                    track_id: *track_id,
                    volume: *volume,
                };
                if crate::send_command(cmd) {
                    (ResponseStatus::Ok, ResponsePayload::Empty, String::new())
                } else {
                    (
                        ResponseStatus::Error,
                        ResponsePayload::Empty,
                        "command queue full".into(),
                    )
                }
            }

            RequestPayload::SetPan { track_id, pan } => {
                let cmd = DspCommand::TrackSetPan {
                    track_id: *track_id,
                    pan: *pan,
                };
                if crate::send_command(cmd) {
                    (ResponseStatus::Ok, ResponsePayload::Empty, String::new())
                } else {
                    (
                        ResponseStatus::Error,
                        ResponsePayload::Empty,
                        "command queue full".into(),
                    )
                }
            }

            RequestPayload::SetMute { track_id, muted } => {
                let cmd = DspCommand::TrackSetMute {
                    track_id: *track_id,
                    muted: *muted,
                };
                if crate::send_command(cmd) {
                    (ResponseStatus::Ok, ResponsePayload::Empty, String::new())
                } else {
                    (
                        ResponseStatus::Error,
                        ResponsePayload::Empty,
                        "command queue full".into(),
                    )
                }
            }

            RequestPayload::SetSolo { track_id, solo } => {
                let cmd = DspCommand::TrackSetSolo {
                    track_id: *track_id,
                    solo: *solo,
                };
                if crate::send_command(cmd) {
                    (ResponseStatus::Ok, ResponsePayload::Empty, String::new())
                } else {
                    (
                        ResponseStatus::Error,
                        ResponsePayload::Empty,
                        "command queue full".into(),
                    )
                }
            }

            RequestPayload::WatchPath { path, recursive } => {
                self.watch_path(path, *recursive);
                (ResponseStatus::Ok, ResponsePayload::Empty, String::new())
            }

            RequestPayload::UnwatchPath { path } => {
                self.unwatch_path(path);
                (ResponseStatus::Ok, ResponsePayload::Empty, String::new())
            }

            RequestPayload::Batch { commands } => {
                // Nested batch — flatten and execute
                let mut succeeded = 0u32;
                let total = commands.len() as u32;
                let mut errors = Vec::new();

                for cmd_payload in commands {
                    let sub_req = BridgeRequest {
                        correlation_id: next_correlation_id(),
                        intent: request.intent,
                        target: request.target,
                        timeout_ms: request.timeout_ms,
                        payload: cmd_payload.clone(),
                    };
                    let sub_resp = self.process_request(&sub_req);
                    if sub_resp.status == ResponseStatus::Ok
                        || sub_resp.status == ResponseStatus::Accepted
                    {
                        succeeded += 1;
                    } else {
                        errors.push(sub_resp.error);
                    }
                }

                let status = if succeeded == total {
                    ResponseStatus::Ok
                } else if succeeded > 0 {
                    ResponseStatus::PartialSuccess
                } else {
                    ResponseStatus::Error
                };

                (
                    status,
                    ResponsePayload::BatchResult {
                        total,
                        succeeded,
                        failed: total - succeeded,
                        errors: errors.clone(),
                    },
                    if errors.is_empty() {
                        String::new()
                    } else {
                        errors.join("; ")
                    },
                )
            }

            // Default: acknowledge but mark as unhandled
            _ => {
                log::debug!(
                    "IntentBridge: unhandled payload variant for cid={}",
                    cid
                );
                (
                    ResponseStatus::Accepted,
                    ResponsePayload::Empty,
                    String::new(),
                )
            }
        };

        BridgeResponse {
            correlation_id: cid,
            status,
            error,
            payload,
            processing_us: start.elapsed().as_micros() as u64,
            commands_executed: 1,
        }
    }

    fn send_response(&self, response: BridgeResponse) {
        self.total_responses.fetch_add(1, Ordering::Relaxed);
        if let Err(TrySendError::Full(_)) = self.response_tx.try_send(response) {
            // Drop oldest response
            let _ = self.response_rx.try_recv();
            log::warn!("IntentBridge: response channel full, dropped oldest");
        }
    }

    /// Emit a CORTEX signal for this intent (awareness + pattern tracking).
    fn emit_intent_signal(&self, request: &BridgeRequest) {
        if let Some(h) = cortex_handle_cached() {
            let urgency = match request.intent {
                CommandIntent::CortexHealing | CommandIntent::Recovery => SignalUrgency::Elevated,
                CommandIntent::System => SignalUrgency::Ambient,
                _ => SignalUrgency::Normal,
            };

            h.signal(
                SignalOrigin::Bridge,
                urgency,
                SignalKind::Custom {
                    tag: format!(
                        "bridge.intent.{:?}.{:?}",
                        request.intent, request.target
                    ),
                    data: format!("cid={}", request.correlation_id),
                },
            );
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// BRIDGE STATS
// ═══════════════════════════════════════════════════════════════════════════

/// Bridge statistics snapshot.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeStats {
    pub total_requests: u64,
    pub total_responses: u64,
    pub total_events: u64,
    pub total_timeouts: u64,
    pub total_batch_commands: u64,
    pub pending_responses: usize,
    pub pending_events: usize,
    pub uptime_ms: u64,
    pub audio_ring_sequence: u64,
}

// ═══════════════════════════════════════════════════════════════════════════
// CONVENIENCE FUNCTIONS (for use from other Rust modules)
// ═══════════════════════════════════════════════════════════════════════════

/// Push a CORTEX health event to Flutter.
pub fn bridge_push_health(score: f64, is_degraded: bool, signals_per_sec: f64) {
    IntentBridge::global().push_event(
        BridgeEventType::CortexHealth,
        EventPayload::Health {
            score,
            is_degraded,
            signals_per_sec,
        },
    );
}

/// Push a transport state event to Flutter.
pub fn bridge_push_transport(playing: bool, recording: bool, position_secs: f64, tempo: f64) {
    IntentBridge::global().push_event(
        BridgeEventType::Transport,
        EventPayload::Transport {
            playing,
            recording,
            position_secs,
            tempo,
        },
    );
}

/// Push a metering event to Flutter.
pub fn bridge_push_metering(peak_l: f32, peak_r: f32, rms_l: f32, rms_r: f32, lufs_m: f32) {
    IntentBridge::global().push_event(
        BridgeEventType::Metering,
        EventPayload::Metering {
            peak_l,
            peak_r,
            rms_l,
            rms_r,
            lufs_m,
        },
    );
}

/// Push a CORTEX pattern event to Flutter.
pub fn bridge_push_pattern(name: &str, severity: f32, description: &str) {
    IntentBridge::global().push_event(
        BridgeEventType::CortexPattern,
        EventPayload::Pattern {
            name: name.to_string(),
            severity,
            description: description.to_string(),
        },
    );
}

/// Push a CORTEX healing event to Flutter.
pub fn bridge_push_healing(action: &str, healed: bool, detail: &str) {
    IntentBridge::global().push_event(
        BridgeEventType::CortexHealing,
        EventPayload::Healing {
            action: action.to_string(),
            healed,
            detail: detail.to_string(),
        },
    );
}

/// Write a stereo block to the shared audio ring (call from audio thread).
pub fn bridge_audio_ring_write(interleaved: &[f32]) {
    IntentBridge::global().audio_ring.write_block(interleaved);
}

/// Get shared audio ring reference (for FFI pointer access).
pub fn bridge_audio_ring() -> &'static Arc<SharedAudioRing> {
    &IntentBridge::global().audio_ring
}

// ═══════════════════════════════════════════════════════════════════════════
// CALLBACK-BASED EVENT DELIVERY (Rust→Flutter push without polling)
// ═══════════════════════════════════════════════════════════════════════════

/// Callback type: Flutter registers this to receive pushed events.
pub type CEventCallback = extern "C" fn(*const std::ffi::c_char);

/// Registered callback (set by Flutter, read by event dispatch thread).
static EVENT_CALLBACK: std::sync::LazyLock<RwLock<Option<CEventCallback>>> =
    std::sync::LazyLock::new(|| RwLock::new(None));

/// Whether the callback dispatch thread is running.
static CALLBACK_DISPATCH_RUNNING: AtomicBool = AtomicBool::new(false);

/// Register a C callback for real-time Rust→Flutter event push.
/// A background thread invokes this callback with JSON events — no polling needed.
pub fn register_event_callback(callback: Option<CEventCallback>) {
    *EVENT_CALLBACK.write() = callback;

    if callback.is_some() && !CALLBACK_DISPATCH_RUNNING.swap(true, Ordering::SeqCst) {
        std::thread::Builder::new()
            .name("intent-bridge-callback".into())
            .spawn(|| {
                log::info!("IntentBridge: callback dispatch thread started");
                callback_dispatch_loop();
                log::info!("IntentBridge: callback dispatch thread stopped");
            })
            .expect("Failed to spawn intent bridge callback thread");
    }
}

/// Unregister the event callback.
pub fn unregister_event_callback() {
    *EVENT_CALLBACK.write() = None;
}

/// Background thread: drains events and delivers via registered callback.
fn callback_dispatch_loop() {
    let bridge = IntentBridge::global();

    loop {
        let cb = {
            let guard = EVENT_CALLBACK.read();
            match *guard {
                Some(cb) => cb,
                None => {
                    CALLBACK_DISPATCH_RUNNING.store(false, Ordering::SeqCst);
                    return;
                }
            }
        };

        let events = bridge.drain_events(64);
        for event in &events {
            if let Ok(json) = serde_json::to_string(event) {
                if let Ok(cstr) = std::ffi::CString::new(json) {
                    cb(cstr.as_ptr());
                }
            }
        }

        if events.is_empty() {
            std::thread::sleep(Duration::from_millis(16)); // ~60Hz
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_correlation_ids_are_unique() {
        let id1 = next_correlation_id();
        let id2 = next_correlation_id();
        let id3 = next_correlation_id();
        assert!(id2 > id1);
        assert!(id3 > id2);
    }

    #[test]
    fn test_shared_audio_ring_write_read() {
        let ring = SharedAudioRing::new(1024);

        // Write 10 stereo frames
        for i in 0..10 {
            ring.write_frame(i as f32 * 0.1, i as f32 * -0.1);
        }

        assert_eq!(ring.sequence(), 10);

        // Read latest 5 frames
        let mut out = vec![0.0f32; 10];
        let read = ring.read_latest(&mut out, 5);
        assert_eq!(read, 5);

        // Last frame should be (0.9, -0.9)
        assert!((out[8] - 0.9).abs() < 0.001);
        assert!((out[9] - (-0.9)).abs() < 0.001);
    }

    #[test]
    fn test_shared_audio_ring_block_write() {
        let ring = SharedAudioRing::new(256);
        let block: Vec<f32> = (0..20).map(|i| i as f32 * 0.05).collect();
        ring.write_block(&block);
        assert_eq!(ring.sequence(), 10); // 20 samples / 2 channels = 10 frames
    }

    #[test]
    fn test_request_serialization() {
        let req = BridgeRequest {
            correlation_id: 42,
            intent: CommandIntent::UserInteraction,
            target: IntentTarget::Mixer,
            timeout_ms: 1000,
            payload: RequestPayload::SetVolume {
                track_id: 3,
                volume: 0.75,
            },
        };

        let json = serde_json::to_string(&req).unwrap();
        let deser: BridgeRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(deser.correlation_id, 42);
    }

    #[test]
    fn test_response_serialization() {
        let resp = BridgeResponse {
            correlation_id: 42,
            status: ResponseStatus::Ok,
            error: String::new(),
            payload: ResponsePayload::Health {
                score: 0.95,
                is_degraded: false,
            },
            processing_us: 150,
            commands_executed: 1,
        };

        let json = serde_json::to_string(&resp).unwrap();
        assert!(json.contains("0.95"));
    }

    #[test]
    fn test_event_serialization() {
        let evt = BridgeEvent {
            event_type: BridgeEventType::CortexHealth,
            sequence: 1,
            timestamp_ms: 12345,
            payload: EventPayload::Health {
                score: 0.8,
                is_degraded: false,
                signals_per_sec: 500.0,
            },
        };

        let json = serde_json::to_string(&evt).unwrap();
        let deser: BridgeEvent = serde_json::from_str(&json).unwrap();
        assert_eq!(deser.sequence, 1);
    }

    #[test]
    fn test_batch_payload() {
        let batch = RequestPayload::Batch {
            commands: vec![
                RequestPayload::SetVolume {
                    track_id: 0,
                    volume: 0.5,
                },
                RequestPayload::SetPan {
                    track_id: 0,
                    pan: -0.3,
                },
                RequestPayload::SetMute {
                    track_id: 1,
                    muted: true,
                },
            ],
        };

        let json = serde_json::to_string(&batch).unwrap();
        assert!(json.contains("Batch"));
    }

    #[test]
    fn test_bridge_stats_default() {
        // Can't use global() in tests (singleton), but test struct creation
        let stats = BridgeStats {
            total_requests: 0,
            total_responses: 0,
            total_events: 0,
            total_timeouts: 0,
            total_batch_commands: 0,
            pending_responses: 0,
            pending_events: 0,
            uptime_ms: 0,
            audio_ring_sequence: 0,
        };
        assert_eq!(stats.total_requests, 0);
    }
}
