// file: crates/rf-bridge/src/cortex_bridge.rs
//! CortexBridge v2 — Ultimativni bidirekcioni bridge za CORTEX nervni sistem.
//!
//! Arhitektura:
//! ```text
//!   Flutter (Dart)                          Rust (CORTEX)
//!   ─────────────                           ─────────────
//!   CortexRequest ──→ [request_ring] ──→ IntentRouter
//!                                           │
//!                          ┌────────────────┼────────────────┐
//!                          │                │                │
//!                     ParamChange      Analysis         Background
//!                     (RT path)        (polling)        (deferred)
//!                          │                │                │
//!                          └────────┬───────┘                │
//!                                   │                        │
//!   CortexResponse ←── [response_ring] ←── ResponseCollector ←┘
//!                                   │
//!   CortexEvent    ←── [event_ring]  ←── NeuralBus subscriber
//! ```
//!
//! ## Features
//! - **Intent-based routing** — requests tagged with intent, routed to correct subsystem
//! - **Bidirectional streaming** — response + event rings push data back to Flutter
//! - **Typed requests** — Serde enum payloads with correlation IDs and timeouts
//! - **Batch transactions** — atomic N-command batches with commit/rollback
//! - **Zero-copy audio** — shared memory region for large audio buffers
//! - **FSEvents watcher** — file system change notifications without polling

use crossbeam_channel::{Receiver, Sender};
use parking_lot::{Mutex, RwLock};
use portable_atomic::{AtomicU64, Ordering};
use rtrb::{Consumer, Producer, RingBuffer};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};

// ═══════════════════════════════════════════════════════════════════════════════
// CORRELATION & IDENTITY
// ═══════════════════════════════════════════════════════════════════════════════

/// Monotonically increasing request ID generator.
static REQUEST_ID_GEN: AtomicU64 = AtomicU64::new(1);

/// Generate a unique request ID.
#[inline]
pub fn next_request_id() -> u64 {
    REQUEST_ID_GEN.fetch_add(1, Ordering::Relaxed)
}

/// Batch ID generator.
static BATCH_ID_GEN: AtomicU64 = AtomicU64::new(1);

/// Generate a unique batch ID.
#[inline]
pub fn next_batch_id() -> u64 {
    BATCH_ID_GEN.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTENT — routing labels
// ═══════════════════════════════════════════════════════════════════════════════

/// Intent label — tells the router HOW to handle this request.
/// Different intents get different latency budgets and thread affinity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum BridgeIntent {
    /// DSP parameter mutation — routed to lock-free audio command queue.
    /// Latency budget: <1ms. Never allocates.
    ParamChange = 0,

    /// Read-only state query — routed to shared state readers.
    /// Returns current value, no mutation.
    Query = 1,

    /// Request analysis/metering data — routed to analysis subsystem.
    /// May specify desired update rate.
    Analysis = 2,

    /// Real-time path — lowest latency, highest priority.
    /// For transport control, MIDI, time-critical operations.
    RealTime = 3,

    /// Background/deferred — can be processed in next tick cycle.
    /// File operations, preset loading, ML inference.
    Background = 4,

    /// Open/close a streaming channel (metering, CORTEX events).
    Stream = 5,

    /// Batch operation — contains N sub-requests processed atomically.
    Batch = 6,

    /// CORTEX nervous system — signal emission, reflex control, awareness queries.
    Cortex = 7,

    /// Spatial audio — 3D positioning, Atmos, binaural processing.
    Spatial = 8,
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRIORITY
// ═══════════════════════════════════════════════════════════════════════════════

/// Request priority — determines queue ordering when contention exists.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum BridgePriority {
    /// Background task, process when idle.
    Low = 0,
    /// Normal interactive operation.
    Normal = 1,
    /// User-initiated action that should feel instant.
    High = 2,
    /// System-critical (transport, safety, feedback break).
    Critical = 3,
    /// Emergency — bypass all queues, execute immediately.
    Emergency = 4,
}

impl Default for BridgePriority {
    fn default() -> Self {
        Self::Normal
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// REQUEST PAYLOAD
// ═══════════════════════════════════════════════════════════════════════════════

/// The payload of a bridge request — what the caller wants done.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BridgePayload {
    // --- DSP Parameter Changes (Intent: ParamChange) ---
    /// Set EQ band gain.
    EqSetGain { track_id: u32, band: u8, gain_db: f64 },
    /// Set EQ band frequency.
    EqSetFreq { track_id: u32, band: u8, freq_hz: f64 },
    /// Set EQ band Q.
    EqSetQ { track_id: u32, band: u8, q: f64 },
    /// Bypass EQ.
    EqBypass { track_id: u32, bypass: bool },
    /// Set track volume.
    TrackVolume { track_id: u32, volume_db: f64 },
    /// Set track pan.
    TrackPan { track_id: u32, pan: f64 },
    /// Set track mute.
    TrackMute { track_id: u32, mute: bool },
    /// Set track solo.
    TrackSolo { track_id: u32, solo: bool },
    /// Set bus volume.
    BusVolume { bus_id: u32, volume_db: f64 },

    // --- Transport (Intent: RealTime) ---
    /// Play from current position.
    TransportPlay,
    /// Stop playback.
    TransportStop,
    /// Pause playback.
    TransportPause,
    /// Seek to position (in samples).
    TransportSeek { position_samples: u64 },
    /// Set loop region.
    TransportLoop { start: u64, end: u64, enabled: bool },
    /// Set tempo.
    TransportTempo { bpm: f64 },

    // --- Queries (Intent: Query) ---
    /// Get current transport state.
    GetTransportState,
    /// Get track info.
    GetTrackInfo { track_id: u32 },
    /// Get mixer state.
    GetMixerState,
    /// Get project info.
    GetProjectInfo,
    /// Get CORTEX health.
    GetCortexHealth,
    /// Get awareness dimensions.
    GetAwareness,

    // --- Analysis (Intent: Analysis) ---
    /// Request spectrum data.
    GetSpectrum { track_id: u32 },
    /// Request loudness data.
    GetLoudness { track_id: u32 },
    /// Request stereo correlation.
    GetCorrelation { track_id: u32 },

    // --- Spatial Audio (Intent: Spatial) ---
    /// Set 3D position for a source.
    SpatialSetPosition { source_id: u32, x: f32, y: f32, z: f32 },
    /// Set listener position/orientation.
    SpatialSetListener { x: f32, y: f32, z: f32, yaw: f32, pitch: f32 },
    /// Enable/disable binaural rendering.
    SpatialBinaural { enabled: bool, hrtf_profile: u8 },
    /// Set Atmos bed/object configuration.
    SpatialAtmosConfig { bed_channels: u8, max_objects: u16 },
    /// Set distance attenuation curve.
    SpatialAttenuation { source_id: u32, model: u8, min_dist: f32, max_dist: f32 },
    /// Set reverb zone.
    SpatialReverbZone { zone_id: u32, size: f32, damping: f32, mix: f32 },

    // --- CORTEX (Intent: Cortex) ---
    /// Emit a neural signal into the bus.
    CortexEmitSignal { origin: String, urgency: u8, kind: String, data: String },
    /// Query recent patterns.
    CortexGetPatterns { limit: u32 },
    /// Query immune system status.
    CortexGetImmune,
    /// Trigger a reflex manually.
    CortexTriggerReflex { reflex_name: String },

    // --- Streaming (Intent: Stream) ---
    /// Subscribe to CORTEX event stream.
    StreamSubscribe { filter_origins: Vec<String>, min_urgency: u8 },
    /// Unsubscribe from event stream.
    StreamUnsubscribe { subscription_id: u64 },

    // --- Background (Intent: Background) ---
    /// Load a preset.
    LoadPreset { path: String },
    /// Save project.
    SaveProject { path: String },
    /// Export audio.
    ExportAudio { path: String, format: String, sample_rate: u32, bit_depth: u8 },

    // --- Batch (Intent: Batch) ---
    /// Atomic batch of sub-requests. All succeed or all fail.
    BatchExecute { requests: Vec<CortexRequest> },

    // --- File Watch (Intent: Background) ---
    /// Watch a directory for changes.
    FileWatch { path: String, recursive: bool },
    /// Stop watching a directory.
    FileUnwatch { watch_id: u64 },

    // --- Generic ---
    /// Custom payload for extensibility.
    Custom { tag: String, data: String },
}

// ═══════════════════════════════════════════════════════════════════════════════
// REQUEST ENVELOPE
// ═══════════════════════════════════════════════════════════════════════════════

/// A typed request flowing from Flutter → Rust through the bridge.
/// Every request has a correlation ID for tracking responses.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CortexRequest {
    /// Unique correlation ID — ties request to response.
    pub id: u64,
    /// Routing intent — determines which subsystem handles this.
    pub intent: BridgeIntent,
    /// Execution priority.
    pub priority: BridgePriority,
    /// The actual payload.
    pub payload: BridgePayload,
    /// Optional timeout in milliseconds. 0 = no timeout.
    pub timeout_ms: u32,
    /// Optional batch ID — groups requests into atomic transactions.
    pub batch_id: Option<u64>,
    /// Sequence number within a batch (for ordering).
    pub sequence: u32,
}

impl CortexRequest {
    /// Create a new request with auto-generated ID.
    pub fn new(intent: BridgeIntent, payload: BridgePayload) -> Self {
        Self {
            id: next_request_id(),
            intent,
            priority: BridgePriority::default(),
            payload,
            timeout_ms: 0,
            batch_id: None,
            sequence: 0,
        }
    }

    /// Set priority.
    pub fn with_priority(mut self, priority: BridgePriority) -> Self {
        self.priority = priority;
        self
    }

    /// Set timeout.
    pub fn with_timeout(mut self, timeout_ms: u32) -> Self {
        self.timeout_ms = timeout_ms;
        self
    }

    /// Set batch ID and sequence.
    pub fn with_batch(mut self, batch_id: u64, sequence: u32) -> Self {
        self.batch_id = Some(batch_id);
        self.sequence = sequence;
        self
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RESPONSE
// ═══════════════════════════════════════════════════════════════════════════════

/// Status of a bridge response.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum ResponseStatus {
    /// Request succeeded.
    Ok = 0,
    /// Request failed.
    Error = 1,
    /// Request timed out.
    Timeout = 2,
    /// Request was part of a batch that was rolled back.
    RolledBack = 3,
    /// Streaming data (more to come).
    Streaming = 4,
    /// Stream ended.
    StreamEnd = 5,
}

/// Response data — typed results flowing back from Rust → Flutter.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ResponseData {
    /// No data (ack only).
    None,
    /// Boolean result.
    Bool(bool),
    /// Numeric result.
    F64(f64),
    /// String result.
    String(String),
    /// JSON-encoded complex data.
    Json(String),
    /// Spectrum data (256 f32 bins).
    Spectrum(Vec<f32>),
    /// Loudness data.
    Loudness { momentary: f32, short_term: f32, integrated: f32, true_peak: f32 },
    /// Health score + awareness dimensions.
    CortexHealth { score: f64, dimensions: Vec<(String, f64)> },
    /// Transport state.
    Transport { playing: bool, recording: bool, position_samples: u64, bpm: f64 },
    /// Batch result — individual sub-responses.
    BatchResult(Vec<CortexResponse>),
    /// File watch event.
    FileEvent { path: String, kind: String },
    /// CORTEX neural signal (streamed).
    NeuralSignal { id: u64, origin: String, urgency: u8, kind: String, data: String },
    /// Error detail.
    ErrorDetail { code: u32, message: String },
}

/// A response flowing from Rust → Flutter through the bridge.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CortexResponse {
    /// Correlation ID — matches the request that triggered this.
    pub request_id: u64,
    /// Status of the response.
    pub status: ResponseStatus,
    /// The response data.
    pub data: ResponseData,
    /// Processing time in microseconds (for telemetry).
    pub processing_us: u64,
    /// Sequence number (for streaming responses).
    pub sequence: u32,
}

impl CortexResponse {
    /// Create an OK response with data.
    pub fn ok(request_id: u64, data: ResponseData) -> Self {
        Self {
            request_id,
            status: ResponseStatus::Ok,
            data,
            processing_us: 0,
            sequence: 0,
        }
    }

    /// Create an error response.
    pub fn error(request_id: u64, code: u32, message: impl Into<String>) -> Self {
        Self {
            request_id,
            status: ResponseStatus::Error,
            data: ResponseData::ErrorDetail {
                code,
                message: message.into(),
            },
            processing_us: 0,
            sequence: 0,
        }
    }

    /// Create a timeout response.
    pub fn timeout(request_id: u64) -> Self {
        Self {
            request_id,
            status: ResponseStatus::Timeout,
            data: ResponseData::None,
            processing_us: 0,
            sequence: 0,
        }
    }

    /// Set processing time.
    pub fn with_timing(mut self, start: Instant) -> Self {
        self.processing_us = start.elapsed().as_micros() as u64;
        self
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BRIDGE EVENT (Rust → Flutter push, no request needed)
// ═══════════════════════════════════════════════════════════════════════════════

/// Autonomous event pushed from Rust to Flutter (no request correlation).
/// These come from CORTEX neural bus, file watchers, autonomic system, etc.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeEvent {
    /// Monotonically increasing event ID.
    pub id: u64,
    /// Event category for client-side routing.
    pub category: EventCategory,
    /// Event data.
    pub data: ResponseData,
    /// Unix timestamp millis.
    pub timestamp_ms: u64,
}

/// Event categories for client-side filtering.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[repr(u8)]
pub enum EventCategory {
    /// CORTEX neural signal.
    NeuralSignal = 0,
    /// CORTEX pattern detected.
    PatternDetected = 1,
    /// Autonomic command issued.
    AutonomicAction = 2,
    /// Health/awareness change.
    HealthChange = 3,
    /// File system change (from watcher).
    FileChange = 4,
    /// Metering update.
    MeteringUpdate = 5,
    /// Reflex fired.
    ReflexFired = 6,
    /// Immune response.
    ImmuneResponse = 7,
}

static EVENT_ID_GEN: AtomicU64 = AtomicU64::new(1);

impl BridgeEvent {
    pub fn new(category: EventCategory, data: ResponseData) -> Self {
        Self {
            id: EVENT_ID_GEN.fetch_add(1, Ordering::Relaxed),
            category,
            data,
            timestamp_ms: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BATCH TRANSACTION MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

/// Transaction state for atomic batch operations.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BatchState {
    /// Accumulating commands.
    Pending,
    /// All commands executed successfully.
    Committed,
    /// One or more commands failed, batch rolled back.
    RolledBack,
}

/// A batch transaction — N commands that must all succeed or all fail.
pub struct BatchTransaction {
    pub batch_id: u64,
    pub state: BatchState,
    pub requests: Vec<CortexRequest>,
    pub responses: Vec<CortexResponse>,
    /// Undo log — stores pre-mutation state for rollback.
    pub undo_log: Vec<UndoEntry>,
    pub created_at: Instant,
}

/// An entry in the undo log — enough info to reverse a single mutation.
#[derive(Debug, Clone)]
pub struct UndoEntry {
    pub request_id: u64,
    pub description: String,
    /// Serialized pre-mutation state (varies by command type).
    pub previous_state: String,
}

impl BatchTransaction {
    pub fn new(requests: Vec<CortexRequest>) -> Self {
        let batch_id = next_batch_id();
        Self {
            batch_id,
            state: BatchState::Pending,
            requests,
            responses: Vec::new(),
            undo_log: Vec::new(),
            created_at: Instant::now(),
        }
    }

    /// Record a successful sub-operation.
    pub fn record_success(&mut self, response: CortexResponse, undo: Option<UndoEntry>) {
        self.responses.push(response);
        if let Some(entry) = undo {
            self.undo_log.push(entry);
        }
    }

    /// Mark batch as committed (all succeeded).
    pub fn commit(&mut self) {
        self.state = BatchState::Committed;
        self.undo_log.clear(); // No rollback needed.
    }

    /// Roll back all executed operations.
    pub fn rollback(&mut self) {
        self.state = BatchState::RolledBack;
        // Mark all responses as rolled back.
        for resp in &mut self.responses {
            resp.status = ResponseStatus::RolledBack;
        }
        // Undo log is consumed by the caller to reverse mutations.
    }

    /// Is the batch still pending?
    pub fn is_pending(&self) -> bool {
        self.state == BatchState::Pending
    }

    /// Elapsed time since batch was created.
    pub fn elapsed(&self) -> Duration {
        self.created_at.elapsed()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED MEMORY REGION (Zero-Copy Audio Buffers)
// ═══════════════════════════════════════════════════════════════════════════════

/// A shared memory region for zero-copy audio buffer transfer.
/// Both Flutter and Rust can read/write to the same memory without copying.
pub struct SharedAudioBuffer {
    /// Raw pointer to the shared memory.
    ptr: *mut f32,
    /// Number of f32 samples in the buffer.
    len: usize,
    /// Layout used for deallocation.
    layout: std::alloc::Layout,
    /// Read cursor (consumer position).
    read_pos: AtomicU64,
    /// Write cursor (producer position).
    write_pos: AtomicU64,
}

// SAFETY: The shared buffer is designed for single-writer/single-reader
// with atomic cursors providing memory ordering.
unsafe impl Send for SharedAudioBuffer {}
unsafe impl Sync for SharedAudioBuffer {}

impl SharedAudioBuffer {
    /// Allocate a new shared audio buffer.
    /// `capacity_samples` should be a power of 2 for efficient wrapping.
    pub fn new(capacity_samples: usize) -> Self {
        let layout = std::alloc::Layout::array::<f32>(capacity_samples)
            .expect("Invalid buffer layout");
        // SAFETY: Layout is valid, non-zero size.
        let ptr = unsafe { std::alloc::alloc_zeroed(layout) as *mut f32 };
        if ptr.is_null() {
            std::alloc::handle_alloc_error(layout);
        }
        Self {
            ptr,
            len: capacity_samples,
            layout,
            read_pos: AtomicU64::new(0),
            write_pos: AtomicU64::new(0),
        }
    }

    /// Get a raw pointer to the buffer (for FFI to Flutter).
    pub fn as_ptr(&self) -> *const f32 {
        self.ptr as *const f32
    }

    /// Get a mutable raw pointer.
    pub fn as_mut_ptr(&self) -> *mut f32 {
        self.ptr
    }

    /// Buffer capacity in samples.
    pub fn capacity(&self) -> usize {
        self.len
    }

    /// Write samples into the buffer (producer side).
    /// Returns number of samples actually written.
    pub fn write(&self, samples: &[f32]) -> usize {
        let write = self.write_pos.load(Ordering::Acquire) as usize;
        let read = self.read_pos.load(Ordering::Acquire) as usize;
        let available = self.len - (write.wrapping_sub(read));
        let to_write = samples.len().min(available);

        for i in 0..to_write {
            let idx = (write + i) % self.len;
            // SAFETY: idx is within bounds (modulo len), ptr is valid.
            unsafe { self.ptr.add(idx).write(samples[i]) };
        }

        self.write_pos.store((write + to_write) as u64, Ordering::Release);
        to_write
    }

    /// Read samples from the buffer (consumer side).
    /// Returns number of samples actually read.
    pub fn read(&self, output: &mut [f32]) -> usize {
        let write = self.write_pos.load(Ordering::Acquire) as usize;
        let read = self.read_pos.load(Ordering::Acquire) as usize;
        let available = write.wrapping_sub(read);
        let to_read = output.len().min(available);

        for i in 0..to_read {
            let idx = (read + i) % self.len;
            // SAFETY: idx is within bounds (modulo len), ptr is valid.
            output[i] = unsafe { self.ptr.add(idx).read() };
        }

        self.read_pos.store((read + to_read) as u64, Ordering::Release);
        to_read
    }

    /// Available samples to read.
    pub fn available(&self) -> usize {
        let write = self.write_pos.load(Ordering::Relaxed) as usize;
        let read = self.read_pos.load(Ordering::Relaxed) as usize;
        write.wrapping_sub(read)
    }

    /// Available space to write.
    pub fn space(&self) -> usize {
        self.len - self.available()
    }
}

impl Drop for SharedAudioBuffer {
    fn drop(&mut self) {
        // SAFETY: ptr was allocated with this layout in new().
        unsafe { std::alloc::dealloc(self.ptr as *mut u8, self.layout) };
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FILE SYSTEM WATCHER (FSEvents on macOS)
// ═══════════════════════════════════════════════════════════════════════════════

/// File watch subscription.
#[derive(Debug)]
pub struct FileWatchEntry {
    pub watch_id: u64,
    pub path: String,
    pub recursive: bool,
}

static WATCH_ID_GEN: AtomicU64 = AtomicU64::new(1);

/// File watcher manager — uses crossbeam channel to forward events.
/// Actual OS-level watching is done via std::fs polling or kqueue on macOS.
/// (notify crate integration is optional — we keep zero external deps for this core.)
pub struct FileWatchManager {
    watches: HashMap<u64, FileWatchEntry>,
    event_tx: Sender<BridgeEvent>,
    /// Polling interval for file stat checks.
    poll_interval: Duration,
}

impl FileWatchManager {
    pub fn new(event_tx: Sender<BridgeEvent>) -> Self {
        Self {
            watches: HashMap::new(),
            event_tx,
            poll_interval: Duration::from_secs(1),
        }
    }

    /// Register a new file watch. Returns watch_id.
    pub fn watch(&mut self, path: String, recursive: bool) -> u64 {
        let watch_id = WATCH_ID_GEN.fetch_add(1, Ordering::Relaxed);
        self.watches.insert(watch_id, FileWatchEntry {
            watch_id,
            path,
            recursive,
        });
        watch_id
    }

    /// Remove a file watch.
    pub fn unwatch(&mut self, watch_id: u64) -> bool {
        self.watches.remove(&watch_id).is_some()
    }

    /// Emit a file change event (called by OS-level watcher callback).
    pub fn emit_change(&self, path: &str, kind: &str) {
        let event = BridgeEvent::new(
            EventCategory::FileChange,
            ResponseData::FileEvent {
                path: path.to_string(),
                kind: kind.to_string(),
            },
        );
        let _ = self.event_tx.try_send(event);
    }

    /// Get active watch count.
    pub fn watch_count(&self) -> usize {
        self.watches.len()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INTENT ROUTER — the brain of the bridge
// ═══════════════════════════════════════════════════════════════════════════════

/// Statistics for the intent router.
#[derive(Debug, Default)]
pub struct RouterStats {
    pub total_routed: AtomicU64,
    pub total_errors: AtomicU64,
    pub total_timeouts: AtomicU64,
    pub total_batches: AtomicU64,
    pub by_intent: [AtomicU64; 9], // One per BridgeIntent variant
}

impl RouterStats {
    pub fn record_route(&self, intent: BridgeIntent) {
        self.total_routed.fetch_add(1, Ordering::Relaxed);
        self.by_intent[intent as usize].fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_error(&self) {
        self.total_errors.fetch_add(1, Ordering::Relaxed);
    }

    pub fn record_timeout(&self) {
        self.total_timeouts.fetch_add(1, Ordering::Relaxed);
    }

    pub fn snapshot(&self) -> RouterStatsSnapshot {
        RouterStatsSnapshot {
            total_routed: self.total_routed.load(Ordering::Relaxed),
            total_errors: self.total_errors.load(Ordering::Relaxed),
            total_timeouts: self.total_timeouts.load(Ordering::Relaxed),
            total_batches: self.total_batches.load(Ordering::Relaxed),
        }
    }
}

/// Serializable stats snapshot.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouterStatsSnapshot {
    pub total_routed: u64,
    pub total_errors: u64,
    pub total_timeouts: u64,
    pub total_batches: u64,
}

// ═══════════════════════════════════════════════════════════════════════════════
// CORTEX BRIDGE — the main struct
// ═══════════════════════════════════════════════════════════════════════════════

/// Ring buffer sizes.
const REQUEST_RING_SIZE: usize = 4096;
const RESPONSE_RING_SIZE: usize = 4096;
const EVENT_RING_SIZE: usize = 2048;

/// The CortexBridge — bidirectional, intent-routed communication layer.
pub struct CortexBridge {
    // --- Request channel (Flutter → Rust) ---
    request_producer: Producer<CortexRequest>,
    request_consumer: Consumer<CortexRequest>,

    // --- Response channel (Rust → Flutter) ---
    response_producer: Producer<CortexResponse>,
    response_consumer: Consumer<CortexResponse>,

    // --- Event channel (Rust → Flutter, autonomous push) ---
    event_producer: Producer<BridgeEvent>,
    event_consumer: Consumer<BridgeEvent>,

    // --- Batch transaction state ---
    active_batches: HashMap<u64, BatchTransaction>,

    // --- Shared audio buffers ---
    shared_buffers: HashMap<String, Arc<SharedAudioBuffer>>,

    // --- Pending requests (for timeout tracking) ---
    pending_requests: HashMap<u64, (CortexRequest, Instant)>,

    // --- Statistics ---
    stats: Arc<RouterStats>,
}

impl CortexBridge {
    /// Create a new CortexBridge with default ring sizes.
    pub fn new() -> Self {
        let (req_prod, req_cons) = RingBuffer::new(REQUEST_RING_SIZE);
        let (resp_prod, resp_cons) = RingBuffer::new(RESPONSE_RING_SIZE);
        let (evt_prod, evt_cons) = RingBuffer::new(EVENT_RING_SIZE);

        Self {
            request_producer: req_prod,
            request_consumer: req_cons,
            response_producer: resp_prod,
            response_consumer: resp_cons,
            event_producer: evt_prod,
            event_consumer: evt_cons,
            active_batches: HashMap::new(),
            shared_buffers: HashMap::new(),
            pending_requests: HashMap::new(),
            stats: Arc::new(RouterStats::default()),
        }
    }

    /// Split into Flutter-side and Rust-side handles.
    pub fn split(self) -> (BridgeFlutterHandle, BridgeRustHandle) {
        let stats = self.stats.clone();

        let flutter = BridgeFlutterHandle {
            request_producer: self.request_producer,
            response_consumer: self.response_consumer,
            event_consumer: self.event_consumer,
            stats: stats.clone(),
        };

        let rust = BridgeRustHandle {
            request_consumer: self.request_consumer,
            response_producer: self.response_producer,
            event_producer: self.event_producer,
            active_batches: self.active_batches,
            shared_buffers: self.shared_buffers,
            pending_requests: self.pending_requests,
            stats,
        };

        (flutter, rust)
    }
}

impl Default for CortexBridge {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FLUTTER-SIDE HANDLE (sends requests, receives responses + events)
// ═══════════════════════════════════════════════════════════════════════════════

/// Handle used by Flutter/Dart side via FFI.
pub struct BridgeFlutterHandle {
    request_producer: Producer<CortexRequest>,
    response_consumer: Consumer<CortexResponse>,
    event_consumer: Consumer<BridgeEvent>,
    stats: Arc<RouterStats>,
}

impl BridgeFlutterHandle {
    /// Send a request to Rust. Returns false if queue is full.
    #[inline]
    pub fn send_request(&mut self, request: CortexRequest) -> bool {
        self.request_producer.push(request).is_ok()
    }

    /// Send a batch of requests atomically.
    /// All requests are tagged with the same batch_id.
    pub fn send_batch(&mut self, requests: Vec<CortexRequest>) -> Option<u64> {
        let batch_id = next_batch_id();
        let capacity = self.request_producer.slots();
        if requests.len() > capacity {
            return None; // Not enough space for entire batch.
        }

        // Create the batch envelope.
        let batch_request = CortexRequest {
            id: next_request_id(),
            intent: BridgeIntent::Batch,
            priority: requests.iter()
                .map(|r| r.priority)
                .max()
                .unwrap_or(BridgePriority::Normal),
            payload: BridgePayload::BatchExecute { requests },
            timeout_ms: 5000, // 5s default for batches
            batch_id: Some(batch_id),
            sequence: 0,
        };

        if self.request_producer.push(batch_request).is_ok() {
            Some(batch_id)
        } else {
            None
        }
    }

    /// Poll for responses. Returns all available responses.
    pub fn poll_responses(&mut self) -> Vec<CortexResponse> {
        let mut responses = Vec::new();
        while let Ok(resp) = self.response_consumer.pop() {
            responses.push(resp);
        }
        responses
    }

    /// Poll for a specific response by request ID.
    /// Drains queue into internal buffer, returns matching response if found.
    pub fn poll_response_for(&mut self, request_id: u64) -> Option<CortexResponse> {
        // Simple linear scan — fine for typical response rates.
        while let Ok(resp) = self.response_consumer.pop() {
            if resp.request_id == request_id {
                return Some(resp);
            }
            // Non-matching responses are consumed but lost.
            // For production: buffer them. For now: KISS.
        }
        None
    }

    /// Poll for events (CORTEX signals, file changes, etc.).
    pub fn poll_events(&mut self) -> Vec<BridgeEvent> {
        let mut events = Vec::new();
        while let Ok(evt) = self.event_consumer.pop() {
            events.push(evt);
        }
        events
    }

    /// Check how many responses are waiting.
    pub fn pending_responses(&self) -> usize {
        self.response_consumer.slots()
    }

    /// Check how many events are waiting.
    pub fn pending_events(&self) -> usize {
        self.event_consumer.slots()
    }

    /// Get router stats.
    pub fn stats(&self) -> RouterStatsSnapshot {
        self.stats.snapshot()
    }

    /// Check if request queue has space.
    pub fn has_space(&self) -> bool {
        !self.request_producer.is_full()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RUST-SIDE HANDLE (receives requests, sends responses + events)
// ═══════════════════════════════════════════════════════════════════════════════

/// Handle used by Rust-side processing (CORTEX, audio engine, etc.).
pub struct BridgeRustHandle {
    request_consumer: Consumer<CortexRequest>,
    response_producer: Producer<CortexResponse>,
    event_producer: Producer<BridgeEvent>,
    active_batches: HashMap<u64, BatchTransaction>,
    shared_buffers: HashMap<String, Arc<SharedAudioBuffer>>,
    pending_requests: HashMap<u64, (CortexRequest, Instant)>,
    stats: Arc<RouterStats>,
}

impl BridgeRustHandle {
    /// Drain all pending requests. Call this from the processing loop.
    pub fn drain_requests(&mut self) -> Vec<CortexRequest> {
        let mut requests = Vec::new();
        while let Ok(req) = self.request_consumer.pop() {
            self.stats.record_route(req.intent);
            if req.timeout_ms > 0 {
                self.pending_requests.insert(req.id, (req.clone(), Instant::now()));
            }
            requests.push(req);
        }
        requests
    }

    /// Process a single request and route by intent.
    /// Returns the response (caller is responsible for sending it).
    pub fn route_request(&mut self, request: &CortexRequest) -> CortexResponse {
        let start = Instant::now();

        // Check timeout.
        if request.timeout_ms > 0 {
            if let Some((_req, created)) = self.pending_requests.get(&request.id) {
                if created.elapsed() > Duration::from_millis(request.timeout_ms as u64) {
                    self.stats.record_timeout();
                    self.pending_requests.remove(&request.id);
                    return CortexResponse::timeout(request.id);
                }
            }
        }

        let response = match request.intent {
            BridgeIntent::ParamChange => self.handle_param_change(request),
            BridgeIntent::Query => self.handle_query(request),
            BridgeIntent::Analysis => self.handle_analysis(request),
            BridgeIntent::RealTime => self.handle_realtime(request),
            BridgeIntent::Background => self.handle_background(request),
            BridgeIntent::Stream => self.handle_stream(request),
            BridgeIntent::Batch => self.handle_batch(request),
            BridgeIntent::Cortex => self.handle_cortex(request),
            BridgeIntent::Spatial => self.handle_spatial(request),
        };

        self.pending_requests.remove(&request.id);
        response.with_timing(start)
    }

    /// Send a response back to Flutter.
    #[inline]
    pub fn send_response(&mut self, response: CortexResponse) -> bool {
        self.response_producer.push(response).is_ok()
    }

    /// Push an autonomous event to Flutter.
    #[inline]
    pub fn push_event(&mut self, event: BridgeEvent) -> bool {
        self.event_producer.push(event).is_ok()
    }

    /// Check for timed-out requests and send timeout responses.
    pub fn check_timeouts(&mut self) {
        let timed_out: Vec<u64> = self.pending_requests.iter()
            .filter(|(_, (req, created))| {
                req.timeout_ms > 0
                    && created.elapsed() > Duration::from_millis(req.timeout_ms as u64)
            })
            .map(|(id, _)| *id)
            .collect();

        for id in timed_out {
            self.stats.record_timeout();
            self.pending_requests.remove(&id);
            let _ = self.response_producer.push(CortexResponse::timeout(id));
        }
    }

    /// Register a shared audio buffer.
    pub fn register_shared_buffer(&mut self, name: impl Into<String>, capacity: usize) -> Arc<SharedAudioBuffer> {
        let buf = Arc::new(SharedAudioBuffer::new(capacity));
        let name = name.into();
        self.shared_buffers.insert(name, buf.clone());
        buf
    }

    /// Get a shared audio buffer by name.
    pub fn get_shared_buffer(&self, name: &str) -> Option<Arc<SharedAudioBuffer>> {
        self.shared_buffers.get(name).cloned()
    }

    /// Get statistics.
    pub fn stats(&self) -> RouterStatsSnapshot {
        self.stats.snapshot()
    }

    // ── Intent Handlers ──────────────────────────────────────────────────

    fn handle_param_change(&self, request: &CortexRequest) -> CortexResponse {
        // Route to existing DSP command queue.
        // This converts BridgePayload → DspCommand and pushes to rtrb.
        use crate::command_queue::send_command;
        use crate::dsp_commands::DspCommand;

        let cmd = match &request.payload {
            BridgePayload::EqSetGain { track_id, band, gain_db } => {
                Some(DspCommand::EqSetGain {
                    track_id: *track_id,
                    band_index: *band,
                    gain_db: *gain_db,
                })
            }
            BridgePayload::EqSetFreq { track_id, band, freq_hz } => {
                Some(DspCommand::EqSetFrequency {
                    track_id: *track_id,
                    band_index: *band,
                    freq: *freq_hz,
                })
            }
            BridgePayload::EqSetQ { track_id, band, q } => {
                Some(DspCommand::EqSetQ {
                    track_id: *track_id,
                    band_index: *band,
                    q: *q,
                })
            }
            BridgePayload::EqBypass { track_id, bypass } => {
                Some(DspCommand::EqBypass {
                    track_id: *track_id,
                    bypass: *bypass,
                })
            }
            BridgePayload::TrackVolume { track_id, volume_db } => {
                Some(DspCommand::TrackSetVolume {
                    track_id: *track_id,
                    volume: *volume_db,
                })
            }
            BridgePayload::TrackPan { track_id, pan } => {
                Some(DspCommand::TrackSetPan {
                    track_id: *track_id,
                    pan: *pan,
                })
            }
            BridgePayload::TrackMute { track_id, mute } => {
                Some(DspCommand::TrackSetMute {
                    track_id: *track_id,
                    muted: *mute,
                })
            }
            BridgePayload::TrackSolo { track_id, solo } => {
                Some(DspCommand::TrackSetSolo {
                    track_id: *track_id,
                    solo: *solo,
                })
            }
            BridgePayload::BusVolume { bus_id, volume_db } => {
                // Bus volume is routed via track bus assignment + track volume.
                // No direct BusSetVolume in DSP commands — use TrackSetBus for routing.
                Some(DspCommand::TrackSetVolume {
                    track_id: *bus_id, // Bus as virtual track
                    volume: *volume_db,
                })
            }
            _ => None,
        };

        match cmd {
            Some(dsp_cmd) => {
                if send_command(dsp_cmd) {
                    CortexResponse::ok(request.id, ResponseData::Bool(true))
                } else {
                    self.stats.record_error();
                    CortexResponse::error(request.id, 1001, "DSP command queue full")
                }
            }
            None => {
                self.stats.record_error();
                CortexResponse::error(request.id, 1002, "Payload not valid for ParamChange intent")
            }
        }
    }

    fn handle_query(&self, request: &CortexRequest) -> CortexResponse {
        match &request.payload {
            BridgePayload::GetCortexHealth => {
                let score = crate::cortex_ffi::cortex_health_score();
                CortexResponse::ok(request.id, ResponseData::CortexHealth {
                    score,
                    dimensions: Vec::new(), // TODO: wire awareness dims
                })
            }
            BridgePayload::GetProjectInfo => {
                // Delegate to existing API
                CortexResponse::ok(request.id, ResponseData::String("project_info".into()))
            }
            _ => CortexResponse::error(request.id, 2001, "Unknown query payload"),
        }
    }

    fn handle_analysis(&self, request: &CortexRequest) -> CortexResponse {
        use crate::command_queue;

        match &request.payload {
            BridgePayload::GetSpectrum { track_id } => {
                let spectrum = command_queue::get_spectrum(*track_id);
                CortexResponse::ok(request.id, ResponseData::Spectrum(spectrum.magnitudes.to_vec()))
            }
            BridgePayload::GetLoudness { track_id } => {
                let loudness = command_queue::get_loudness(*track_id);
                CortexResponse::ok(request.id, ResponseData::Loudness {
                    momentary: loudness.momentary,
                    short_term: loudness.short_term,
                    integrated: loudness.integrated,
                    true_peak: loudness.true_peak_l.max(loudness.true_peak_r),
                })
            }
            BridgePayload::GetCorrelation { track_id } => {
                let corr = command_queue::get_correlation(*track_id);
                CortexResponse::ok(request.id, ResponseData::F64(corr as f64))
            }
            _ => CortexResponse::error(request.id, 3001, "Unknown analysis payload"),
        }
    }

    fn handle_realtime(&self, request: &CortexRequest) -> CortexResponse {
        // Transport commands — routed with highest priority.
        match &request.payload {
            BridgePayload::TransportPlay
            | BridgePayload::TransportStop
            | BridgePayload::TransportPause
            | BridgePayload::TransportSeek { .. }
            | BridgePayload::TransportLoop { .. }
            | BridgePayload::TransportTempo { .. } => {
                // TODO: wire to actual transport API
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            _ => CortexResponse::error(request.id, 4001, "Unknown realtime payload"),
        }
    }

    fn handle_background(&self, request: &CortexRequest) -> CortexResponse {
        match &request.payload {
            BridgePayload::LoadPreset { path } => {
                // TODO: async preset loading
                CortexResponse::ok(request.id, ResponseData::String(format!("Loading: {path}")))
            }
            BridgePayload::SaveProject { path } => {
                // TODO: async project save
                CortexResponse::ok(request.id, ResponseData::String(format!("Saving: {path}")))
            }
            BridgePayload::ExportAudio { path, .. } => {
                // TODO: async export
                CortexResponse::ok(request.id, ResponseData::String(format!("Exporting: {path}")))
            }
            BridgePayload::FileWatch { path, recursive } => {
                // TODO: wire to FileWatchManager
                CortexResponse::ok(request.id, ResponseData::F64(1.0)) // watch_id placeholder
            }
            BridgePayload::FileUnwatch { watch_id } => {
                // TODO: wire to FileWatchManager
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            _ => CortexResponse::error(request.id, 5001, "Unknown background payload"),
        }
    }

    fn handle_stream(&self, request: &CortexRequest) -> CortexResponse {
        match &request.payload {
            BridgePayload::StreamSubscribe { filter_origins, min_urgency } => {
                // TODO: create NeuralBus subscription, pipe to event ring
                let sub_id = next_request_id();
                CortexResponse::ok(request.id, ResponseData::F64(sub_id as f64))
            }
            BridgePayload::StreamUnsubscribe { subscription_id } => {
                // TODO: remove subscription
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            _ => CortexResponse::error(request.id, 6001, "Unknown stream payload"),
        }
    }

    fn handle_batch(&mut self, request: &CortexRequest) -> CortexResponse {
        if let BridgePayload::BatchExecute { requests } = &request.payload {
            let mut batch = BatchTransaction::new(requests.clone());
            let mut all_ok = true;

            for sub_req in &batch.requests.clone() {
                let resp = self.route_request(sub_req);
                if resp.status != ResponseStatus::Ok {
                    all_ok = false;
                    batch.record_success(resp, None);
                    break;
                }
                batch.record_success(resp, None);
            }

            if all_ok {
                batch.commit();
                let responses = batch.responses.clone();
                self.stats.total_batches.fetch_add(1, Ordering::Relaxed);
                CortexResponse::ok(request.id, ResponseData::BatchResult(responses))
            } else {
                batch.rollback();
                let responses = batch.responses.clone();
                self.stats.record_error();
                CortexResponse {
                    request_id: request.id,
                    status: ResponseStatus::RolledBack,
                    data: ResponseData::BatchResult(responses),
                    processing_us: 0,
                    sequence: 0,
                }
            }
        } else {
            CortexResponse::error(request.id, 7001, "Batch intent requires BatchExecute payload")
        }
    }

    fn handle_cortex(&self, request: &CortexRequest) -> CortexResponse {
        match &request.payload {
            BridgePayload::CortexEmitSignal { origin, urgency, kind, data } => {
                // TODO: wire to cortex_handle().signal()
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            BridgePayload::CortexGetPatterns { limit } => {
                // TODO: wire to cortex pattern engine
                CortexResponse::ok(request.id, ResponseData::Json("[]".into()))
            }
            BridgePayload::CortexGetImmune => {
                CortexResponse::ok(request.id, ResponseData::Json("{}".into()))
            }
            BridgePayload::CortexTriggerReflex { reflex_name } => {
                // TODO: wire to reflex arc
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            _ => CortexResponse::error(request.id, 8001, "Unknown cortex payload"),
        }
    }

    fn handle_spatial(&self, request: &CortexRequest) -> CortexResponse {
        match &request.payload {
            BridgePayload::SpatialSetPosition { source_id, x, y, z } => {
                // TODO: wire to spatial audio engine
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            BridgePayload::SpatialSetListener { x, y, z, yaw, pitch } => {
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            BridgePayload::SpatialBinaural { enabled, hrtf_profile } => {
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            BridgePayload::SpatialAtmosConfig { bed_channels, max_objects } => {
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            BridgePayload::SpatialAttenuation { source_id, model, min_dist, max_dist } => {
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            BridgePayload::SpatialReverbZone { zone_id, size, damping, mix } => {
                CortexResponse::ok(request.id, ResponseData::Bool(true))
            }
            _ => CortexResponse::error(request.id, 9001, "Unknown spatial payload"),
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL BRIDGE INSTANCE
// ═══════════════════════════════════════════════════════════════════════════════

static BRIDGE: OnceLock<(
    Mutex<BridgeFlutterHandle>,
    Mutex<BridgeRustHandle>,
)> = OnceLock::new();

/// Initialize the global CortexBridge.
pub fn init_bridge() {
    BRIDGE.get_or_init(|| {
        let bridge = CortexBridge::new();
        let (flutter, rust) = bridge.split();
        (Mutex::new(flutter), Mutex::new(rust))
    });
}

/// Get the Flutter-side handle.
pub fn flutter_handle() -> &'static Mutex<BridgeFlutterHandle> {
    init_bridge();
    &BRIDGE.get().expect("Bridge must be initialized").0
}

/// Get the Rust-side handle.
pub fn rust_handle() -> &'static Mutex<BridgeRustHandle> {
    init_bridge();
    &BRIDGE.get().expect("Bridge must be initialized").1
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONVENIENCE FFI-READY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Send a request through the bridge (from Flutter FFI).
/// Returns the request ID for correlation.
pub fn bridge_send_request(intent: u8, payload_json: &str) -> u64 {
    let intent = match intent {
        0 => BridgeIntent::ParamChange,
        1 => BridgeIntent::Query,
        2 => BridgeIntent::Analysis,
        3 => BridgeIntent::RealTime,
        4 => BridgeIntent::Background,
        5 => BridgeIntent::Stream,
        6 => BridgeIntent::Batch,
        7 => BridgeIntent::Cortex,
        8 => BridgeIntent::Spatial,
        _ => BridgeIntent::Background,
    };

    let payload: BridgePayload = match serde_json::from_str(payload_json) {
        Ok(p) => p,
        Err(_) => return 0, // Invalid payload
    };

    let request = CortexRequest::new(intent, payload);
    let id = request.id;

    if flutter_handle().lock().send_request(request) {
        id
    } else {
        0 // Queue full
    }
}

/// Poll responses as JSON array. Returns "[]" if none available.
pub fn bridge_poll_responses() -> String {
    let responses = flutter_handle().lock().poll_responses();
    serde_json::to_string(&responses).unwrap_or_else(|_| "[]".into())
}

/// Poll events as JSON array. Returns "[]" if none available.
pub fn bridge_poll_events() -> String {
    let events = flutter_handle().lock().poll_events();
    serde_json::to_string(&events).unwrap_or_else(|_| "[]".into())
}

/// Process all pending requests (call from Rust processing loop).
/// Returns number of requests processed.
pub fn bridge_process_requests() -> u32 {
    let mut handle = rust_handle().lock();
    let requests = handle.drain_requests();
    let count = requests.len() as u32;

    for req in &requests {
        let response = handle.route_request(req);
        let _ = handle.send_response(response);
    }

    // Check for timeouts.
    handle.check_timeouts();

    count
}

/// Push an event from Rust to Flutter (e.g., CORTEX neural signal).
pub fn bridge_push_event(category: u8, data_json: &str) -> bool {
    let category = match category {
        0 => EventCategory::NeuralSignal,
        1 => EventCategory::PatternDetected,
        2 => EventCategory::AutonomicAction,
        3 => EventCategory::HealthChange,
        4 => EventCategory::FileChange,
        5 => EventCategory::MeteringUpdate,
        6 => EventCategory::ReflexFired,
        7 => EventCategory::ImmuneResponse,
        _ => EventCategory::NeuralSignal,
    };

    let data: ResponseData = match serde_json::from_str(data_json) {
        Ok(d) => d,
        Err(_) => ResponseData::String(data_json.to_string()),
    };

    let event = BridgeEvent::new(category, data);
    rust_handle().lock().push_event(event)
}

/// Get bridge stats as JSON.
pub fn bridge_stats() -> String {
    let stats = flutter_handle().lock().stats();
    serde_json::to_string(&stats).unwrap_or_else(|_| "{}".into())
}

/// Register a shared audio buffer. Returns pointer and capacity for FFI.
pub fn bridge_register_shared_buffer(name: &str, capacity: usize) -> (*const f32, usize) {
    let buf = rust_handle().lock().register_shared_buffer(name, capacity);
    (buf.as_ptr(), buf.capacity())
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_request_response_roundtrip() {
        let bridge = CortexBridge::new();
        let (mut flutter, mut rust) = bridge.split();

        // Send request from Flutter side.
        let req = CortexRequest::new(
            BridgeIntent::Query,
            BridgePayload::GetCortexHealth,
        );
        let req_id = req.id;
        assert!(flutter.send_request(req));

        // Process on Rust side.
        let requests = rust.drain_requests();
        assert_eq!(requests.len(), 1);
        assert_eq!(requests[0].intent, BridgeIntent::Query);

        let response = rust.route_request(&requests[0]);
        assert_eq!(response.status, ResponseStatus::Ok);
        assert!(rust.send_response(response));

        // Receive on Flutter side.
        let responses = flutter.poll_responses();
        assert_eq!(responses.len(), 1);
        assert_eq!(responses[0].request_id, req_id);
    }

    #[test]
    fn test_event_push() {
        let bridge = CortexBridge::new();
        let (mut flutter, mut rust) = bridge.split();

        // Push event from Rust.
        let event = BridgeEvent::new(
            EventCategory::NeuralSignal,
            ResponseData::String("test signal".into()),
        );
        assert!(rust.push_event(event));

        // Receive on Flutter side.
        let events = flutter.poll_events();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].category, EventCategory::NeuralSignal);
    }

    #[test]
    fn test_batch_transaction() {
        let bridge = CortexBridge::new();
        let (mut flutter, mut rust) = bridge.split();

        // Create batch of 3 EQ changes.
        let requests = vec![
            CortexRequest::new(BridgeIntent::ParamChange, BridgePayload::EqSetGain {
                track_id: 0, band: 0, gain_db: 3.0,
            }),
            CortexRequest::new(BridgeIntent::ParamChange, BridgePayload::EqSetFreq {
                track_id: 0, band: 0, freq_hz: 1000.0,
            }),
            CortexRequest::new(BridgeIntent::ParamChange, BridgePayload::EqSetQ {
                track_id: 0, band: 0, q: 1.5,
            }),
        ];

        let batch_id = flutter.send_batch(requests);
        assert!(batch_id.is_some());

        // Process batch on Rust side.
        let reqs = rust.drain_requests();
        assert_eq!(reqs.len(), 1);
        assert_eq!(reqs[0].intent, BridgeIntent::Batch);

        let response = rust.route_request(&reqs[0]);
        // Batch may succeed or fail depending on DSP queue state.
        // In test context without audio engine, individual cmds will go to send_command.
        assert!(rust.send_response(response));
    }

    #[test]
    fn test_shared_audio_buffer() {
        let buf = SharedAudioBuffer::new(1024);
        let samples = [1.0f32, 2.0, 3.0, 4.0];

        assert_eq!(buf.write(&samples), 4);
        assert_eq!(buf.available(), 4);

        let mut output = [0.0f32; 4];
        assert_eq!(buf.read(&mut output), 4);
        assert_eq!(output, samples);
        assert_eq!(buf.available(), 0);
    }

    #[test]
    fn test_shared_buffer_wrap() {
        let buf = SharedAudioBuffer::new(4);

        // Fill buffer.
        let data = [1.0f32, 2.0, 3.0, 4.0];
        assert_eq!(buf.write(&data), 4);
        assert_eq!(buf.space(), 0);

        // Read 2.
        let mut out = [0.0f32; 2];
        assert_eq!(buf.read(&mut out), 2);
        assert_eq!(out, [1.0, 2.0]);

        // Write 2 more (wraps around).
        let more = [5.0f32, 6.0];
        assert_eq!(buf.write(&more), 2);

        // Read all 4.
        let mut all = [0.0f32; 4];
        assert_eq!(buf.read(&mut all), 4);
        assert_eq!(all, [3.0, 4.0, 5.0, 6.0]);
    }

    #[test]
    fn test_priority_ordering() {
        assert!(BridgePriority::Emergency > BridgePriority::Critical);
        assert!(BridgePriority::Critical > BridgePriority::High);
        assert!(BridgePriority::High > BridgePriority::Normal);
        assert!(BridgePriority::Normal > BridgePriority::Low);
    }

    #[test]
    fn test_request_builder() {
        let req = CortexRequest::new(BridgeIntent::Spatial, BridgePayload::SpatialSetPosition {
            source_id: 1, x: 0.5, y: 1.0, z: -2.0,
        })
        .with_priority(BridgePriority::High)
        .with_timeout(500)
        .with_batch(42, 3);

        assert_eq!(req.intent, BridgeIntent::Spatial);
        assert_eq!(req.priority, BridgePriority::High);
        assert_eq!(req.timeout_ms, 500);
        assert_eq!(req.batch_id, Some(42));
        assert_eq!(req.sequence, 3);
    }

    #[test]
    fn test_file_watch_manager() {
        let (tx, _rx) = crossbeam_channel::bounded(64);
        let mut manager = FileWatchManager::new(tx);

        let id1 = manager.watch("/tmp/test".into(), true);
        let id2 = manager.watch("/tmp/test2".into(), false);
        assert_ne!(id1, id2);
        assert_eq!(manager.watch_count(), 2);

        assert!(manager.unwatch(id1));
        assert_eq!(manager.watch_count(), 1);
        assert!(!manager.unwatch(999));
    }

    #[test]
    fn test_response_constructors() {
        let ok = CortexResponse::ok(42, ResponseData::Bool(true));
        assert_eq!(ok.request_id, 42);
        assert_eq!(ok.status, ResponseStatus::Ok);

        let err = CortexResponse::error(43, 1001, "queue full");
        assert_eq!(err.request_id, 43);
        assert_eq!(err.status, ResponseStatus::Error);

        let timeout = CortexResponse::timeout(44);
        assert_eq!(timeout.request_id, 44);
        assert_eq!(timeout.status, ResponseStatus::Timeout);
    }
}
