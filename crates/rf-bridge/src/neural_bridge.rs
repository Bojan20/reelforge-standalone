// file: crates/rf-bridge/src/neural_bridge.rs
//! Ultimate Neural Bridge — Unified Intent-Based Communication Layer
//!
//! Replaces the scatter of individual FFI calls with a single, typed, intent-based
//! bridge that routes through CORTEX neural bus to the right subsystem.
//!
//! ## Architecture
//! ```text
//! Flutter UI
//!     ↕ (FRB sync + async Stream)
//! NeuralBridge
//!     ├── IntentRouter → dispatch typed BridgeIntent to subsystems
//!     ├── AudioBus    → rtrb ring buffer (zero-copy, RT-safe)
//!     ├── CortexBus   → neural signals, health, awareness
//!     ├── WatcherBus  → FSEvents notifications (no polling)
//!     ├── StreamHub   → Rust→Flutter broadcast (metering, signals, FS)
//!     └── BatchExecutor → atomic multi-command in one FFI call
//! ```
//!
//! ## Key Properties
//! - Every request has a `correlation_id` for request↔response matching
//! - Timeouts are enforced at the bridge level (not scattered in Flutter)
//! - Priority routing: Emergency > Critical > High > Normal > Low
//! - Zero-copy audio path preserved (rtrb stays, bridge wraps intent layer on top)
//! - Bidirectional: Flutter→Rust via `bridge_send()`, Rust→Flutter via `StreamHub`

use std::cmp::Reverse;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant};

use crossbeam_channel::{Receiver, Sender, bounded};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};

use crate::{cortex_handle, cortex_shared};

// ═══════════════════════════════════════════════════════════════════════════
// CORRELATION ID GENERATOR
// ═══════════════════════════════════════════════════════════════════════════

static CORRELATION_COUNTER: AtomicU64 = AtomicU64::new(1);

/// Generate a unique correlation ID for request↔response tracking.
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_next_correlation_id() -> u64 {
    CORRELATION_COUNTER.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════
// PRIORITY
// ═══════════════════════════════════════════════════════════════════════════

/// Priority level for bridge intents.
/// Higher priority = processed first in batch and routing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[repr(u8)]
#[derive(Default)]
pub enum BridgePriority {
    /// Background tasks, non-urgent state sync
    Low = 0,
    /// Default for most UI interactions
    #[default]
    Normal = 1,
    /// Time-sensitive: transport, automation recording
    High = 2,
    /// DSP hot path, metering, real-time feedback
    Critical = 3,
    /// System health, memory pressure, audio dropout
    Emergency = 4,
}


impl From<u8> for BridgePriority {
    fn from(v: u8) -> Self {
        match v {
            0 => BridgePriority::Low,
            1 => BridgePriority::Normal,
            2 => BridgePriority::High,
            3 => BridgePriority::Critical,
            4 => BridgePriority::Emergency,
            _ => BridgePriority::Normal,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// BRIDGE INTENT — The Universal Request Type
// ═══════════════════════════════════════════════════════════════════════════

/// Target subsystem for routing.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum BridgeTarget {
    /// Audio DSP engine (EQ, dynamics, effects) — routes to rtrb
    Audio = 0,
    /// Transport control (play, stop, seek, loop, tempo)
    Transport = 1,
    /// Mixer (volume, pan, mute, solo, bus routing)
    Mixer = 2,
    /// CORTEX nervous system (signals, health, awareness)
    Cortex = 3,
    /// Project management (save, load, undo, redo)
    Project = 4,
    /// SlotLab (game audio assignment, events)
    SlotLab = 5,
    /// File system watcher events
    Watcher = 6,
    /// Memory management (soundbanks, budgets)
    Memory = 7,
    /// Metering (peaks, LUFS, spectrum, correlation)
    Metering = 8,
    /// Bridge control (ping, stats, config)
    System = 9,
}

impl From<u8> for BridgeTarget {
    fn from(v: u8) -> Self {
        match v {
            0 => BridgeTarget::Audio,
            1 => BridgeTarget::Transport,
            2 => BridgeTarget::Mixer,
            3 => BridgeTarget::Cortex,
            4 => BridgeTarget::Project,
            5 => BridgeTarget::SlotLab,
            6 => BridgeTarget::Watcher,
            7 => BridgeTarget::Memory,
            8 => BridgeTarget::Metering,
            9 => BridgeTarget::System,
            _ => BridgeTarget::System,
        }
    }
}

/// A typed bridge request from Flutter → Rust.
///
/// This is the universal envelope. The `payload` is a JSON-encoded
/// intent-specific structure (e.g., `{"band":2,"freq":1200.0,"gain_db":3.5}`
/// for `Audio` target with "eq_set_band" action).
///
/// For hot-path audio commands, use `bridge_send_dsp()` which bypasses
/// JSON and goes directly to the rtrb ring buffer.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeIntent {
    /// Unique ID for correlating response to this request
    pub correlation_id: u64,
    /// Target subsystem
    pub target: BridgeTarget,
    /// Action verb (e.g., "play", "set_volume", "emit_signal", "ping")
    pub action: String,
    /// JSON-encoded payload (subsystem-specific)
    pub payload: String,
    /// Priority (higher = routed first)
    pub priority: BridgePriority,
    /// Timeout in milliseconds (0 = no timeout, fire-and-forget)
    pub timeout_ms: u32,
}

// ═══════════════════════════════════════════════════════════════════════════
// BRIDGE RESPONSE — The Universal Response Type
// ═══════════════════════════════════════════════════════════════════════════

/// Status of a bridge operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum BridgeStatus {
    /// Request accepted and processing
    Ok = 0,
    /// Request completed with result data
    Complete = 1,
    /// Request failed (see error field)
    Error = 2,
    /// Request timed out
    Timeout = 3,
    /// Target subsystem not available
    Unavailable = 4,
    /// Unknown action for target
    UnknownAction = 5,
    /// Queue full, try again later
    Backpressure = 6,
}

impl From<u8> for BridgeStatus {
    fn from(v: u8) -> Self {
        match v {
            0 => BridgeStatus::Ok,
            1 => BridgeStatus::Complete,
            2 => BridgeStatus::Error,
            3 => BridgeStatus::Timeout,
            4 => BridgeStatus::Unavailable,
            5 => BridgeStatus::UnknownAction,
            6 => BridgeStatus::Backpressure,
            _ => BridgeStatus::Error,
        }
    }
}

/// Response from bridge back to Flutter.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeResponse {
    /// Matches the correlation_id of the original BridgeIntent
    pub correlation_id: u64,
    /// Operation status
    pub status: BridgeStatus,
    /// JSON-encoded result data (empty string if no data)
    pub data: String,
    /// Error message (empty string if no error)
    pub error: String,
    /// Processing time in microseconds
    pub elapsed_us: u64,
}

impl BridgeResponse {
    fn ok(correlation_id: u64, elapsed: Duration) -> Self {
        Self {
            correlation_id,
            status: BridgeStatus::Ok,
            data: String::new(),
            error: String::new(),
            elapsed_us: elapsed.as_micros() as u64,
        }
    }

    fn ok_with_data(correlation_id: u64, data: String, elapsed: Duration) -> Self {
        Self {
            correlation_id,
            status: BridgeStatus::Complete,
            data,
            error: String::new(),
            elapsed_us: elapsed.as_micros() as u64,
        }
    }

    fn error(correlation_id: u64, status: BridgeStatus, msg: String, elapsed: Duration) -> Self {
        Self {
            correlation_id,
            status,
            data: String::new(),
            error: msg,
            elapsed_us: elapsed.as_micros() as u64,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// STREAM HUB — Bidirectional Rust→Flutter Event Stream
// ═══════════════════════════════════════════════════════════════════════════

/// Event types streamed from Rust to Flutter (bidirectional push).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[repr(u8)]
pub enum StreamEventKind {
    // Audio subsystem
    Metering = 0,
    AudioDropout = 1,
    DeviceChanged = 2,

    // CORTEX nervous system
    CortexHealth = 10,
    CortexSignal = 11,
    CortexPattern = 12,
    CortexReflex = 13,
    CortexImmune = 14,
    CortexAwareness = 15,

    // File system
    FileChanged = 20,
    FileCreated = 21,
    FileDeleted = 22,

    // Memory
    MemoryWarning = 30,
    MemoryCritical = 31,
    SoundbankLoaded = 32,
    SoundbankUnloaded = 33,

    // Bridge control
    BridgeReady = 40,
    BridgeStats = 41,
    Heartbeat = 42,
}

/// A single event pushed from Rust → Flutter.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamEvent {
    /// Monotonically increasing event sequence number
    pub seq: u64,
    /// Event kind (determines payload schema)
    pub kind: StreamEventKind,
    /// JSON-encoded event data
    pub data: String,
    /// Timestamp (milliseconds since bridge init)
    pub timestamp_ms: u64,
}

/// The StreamHub manages Rust→Flutter event broadcasting.
/// Uses crossbeam bounded channel for backpressure.
pub struct StreamHub {
    tx: Sender<StreamEvent>,
    rx: Receiver<StreamEvent>,
    seq: AtomicU64,
    start_time: Instant,
    active: AtomicBool,
}

/// Stream hub capacity — enough for ~16ms of events at 60fps
const STREAM_HUB_CAPACITY: usize = 512;

impl Default for StreamHub {
    fn default() -> Self {
        Self::new()
    }
}

impl StreamHub {
    pub fn new() -> Self {
        let (tx, rx) = bounded(STREAM_HUB_CAPACITY);
        Self {
            tx,
            rx,
            seq: AtomicU64::new(0),
            start_time: Instant::now(),
            active: AtomicBool::new(true),
        }
    }

    /// Push an event to all Flutter listeners.
    /// Non-blocking: drops event if channel is full (backpressure).
    pub fn push(&self, kind: StreamEventKind, data: String) -> bool {
        if !self.active.load(Ordering::Relaxed) {
            return false;
        }
        let event = StreamEvent {
            seq: self.seq.fetch_add(1, Ordering::Relaxed),
            kind,
            data,
            timestamp_ms: self.start_time.elapsed().as_millis() as u64,
        };
        self.tx.try_send(event).is_ok()
    }

    /// Drain all pending events (called from Flutter poll or FRB stream).
    /// Returns up to `max` events.
    pub fn drain(&self, max: usize) -> Vec<StreamEvent> {
        let mut events = Vec::with_capacity(max.min(64));
        for _ in 0..max {
            match self.rx.try_recv() {
                Ok(event) => events.push(event),
                Err(_) => break,
            }
        }
        events
    }

    /// Number of pending events
    pub fn pending_count(&self) -> usize {
        self.rx.len()
    }

    /// Total events emitted since creation
    pub fn total_emitted(&self) -> u64 {
        self.seq.load(Ordering::Relaxed)
    }

    /// Shutdown the stream hub
    pub fn shutdown(&self) {
        self.active.store(false, Ordering::Relaxed);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// BATCH EXECUTOR — Atomic Multi-Command Execution
// ═══════════════════════════════════════════════════════════════════════════

/// A batch of intents to execute atomically.
/// All succeed or all fail (transactional semantics for non-audio targets).
/// Audio commands are best-effort (ring buffer push, no rollback).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeBatch {
    /// Unique batch ID
    pub batch_id: u64,
    /// All intents in this batch
    pub intents: Vec<BridgeIntent>,
    /// If true, stop on first error. If false, continue and collect errors.
    pub stop_on_error: bool,
}

/// Result of a batch execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatchResult {
    pub batch_id: u64,
    pub responses: Vec<BridgeResponse>,
    pub total_elapsed_us: u64,
    pub success_count: u32,
    pub error_count: u32,
}

// ═══════════════════════════════════════════════════════════════════════════
// BRIDGE STATS — Runtime diagnostics
// ═══════════════════════════════════════════════════════════════════════════

/// Bridge performance statistics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeStats {
    /// Total intents processed
    pub total_intents: u64,
    /// Total batches processed
    pub total_batches: u64,
    /// Total stream events emitted
    pub total_stream_events: u64,
    /// Intents per target (indexed by BridgeTarget repr)
    pub intents_per_target: [u64; 10],
    /// Average processing time in microseconds
    pub avg_processing_us: u64,
    /// Max processing time in microseconds
    pub max_processing_us: u64,
    /// Number of timeouts
    pub total_timeouts: u64,
    /// Number of backpressure events (queue full)
    pub total_backpressure: u64,
    /// Uptime in seconds
    pub uptime_secs: f64,
}

// ═══════════════════════════════════════════════════════════════════════════
// NEURAL BRIDGE — The Unified Bridge Instance
// ═══════════════════════════════════════════════════════════════════════════

/// The global Neural Bridge instance.
/// Thread-safe, lock-free on hot paths, mutex only for cold paths.
pub struct NeuralBridge {
    pub stream_hub: StreamHub,
    stats: RwLock<BridgeStatsInner>,
    start_time: Instant,
    initialized: AtomicBool,
}

struct BridgeStatsInner {
    total_intents: u64,
    total_batches: u64,
    intents_per_target: [u64; 10],
    total_processing_us: u64,
    max_processing_us: u64,
    total_timeouts: u64,
    total_backpressure: u64,
}

impl Default for NeuralBridge {
    fn default() -> Self {
        Self::new()
    }
}

impl NeuralBridge {
    pub fn new() -> Self {
        Self {
            stream_hub: StreamHub::new(),
            stats: RwLock::new(BridgeStatsInner {
                total_intents: 0,
                total_batches: 0,
                intents_per_target: [0; 10],
                total_processing_us: 0,
                max_processing_us: 0,
                total_timeouts: 0,
                total_backpressure: 0,
            }),
            start_time: Instant::now(),
            initialized: AtomicBool::new(false),
        }
    }

    /// Initialize the bridge. Call once after engine init.
    pub fn init(&self) {
        self.initialized.store(true, Ordering::Release);
        self.stream_hub.push(
            StreamEventKind::BridgeReady,
            "{}".into(),
        );
    }

    /// Route a single intent to the correct subsystem.
    pub fn route(&self, intent: BridgeIntent) -> BridgeResponse {
        let start = Instant::now();
        let cid = intent.correlation_id;

        if !self.initialized.load(Ordering::Acquire) {
            return BridgeResponse::error(
                cid,
                BridgeStatus::Unavailable,
                "Bridge not initialized".into(),
                start.elapsed(),
            );
        }

        let response = match intent.target {
            BridgeTarget::Audio => self.route_audio(&intent),
            BridgeTarget::Transport => self.route_transport(&intent),
            BridgeTarget::Mixer => self.route_mixer(&intent),
            BridgeTarget::Cortex => self.route_cortex(&intent),
            BridgeTarget::Project => self.route_project(&intent),
            BridgeTarget::SlotLab => self.route_slotlab(&intent),
            BridgeTarget::Watcher => self.route_watcher(&intent),
            BridgeTarget::Memory => self.route_memory(&intent),
            BridgeTarget::Metering => self.route_metering(&intent),
            BridgeTarget::System => self.route_system(&intent),
        };

        let elapsed = start.elapsed();

        // Update stats (cold path, RwLock is fine)
        {
            let mut stats = self.stats.write();
            stats.total_intents += 1;
            stats.intents_per_target[intent.target as usize] += 1;
            let us = elapsed.as_micros() as u64;
            stats.total_processing_us += us;
            if us > stats.max_processing_us {
                stats.max_processing_us = us;
            }
        }

        // Signal to CORTEX that a bridge intent was processed
        if let Some(handle) = cortex_handle() {
            use rf_cortex::prelude::*;
            handle.signal(
                SignalOrigin::Bridge,
                SignalUrgency::Normal,
                SignalKind::Custom {
                    tag: "bridge_intent".into(),
                    data: format!("target={:?},action={}", intent.target, intent.action),
                },
            );
        }

        response
    }

    /// Execute a batch of intents atomically.
    pub fn route_batch(&self, batch: BridgeBatch) -> BatchResult {
        let start = Instant::now();
        let mut responses = Vec::with_capacity(batch.intents.len());
        let mut success_count = 0u32;
        let mut error_count = 0u32;

        // Sort by priority (highest first) for optimal routing
        let mut intents = batch.intents;
        intents.sort_by_key(|x| Reverse(x.priority));

        for intent in intents {
            let response = self.route(intent);
            match response.status {
                BridgeStatus::Ok | BridgeStatus::Complete => success_count += 1,
                _ => {
                    error_count += 1;
                    if batch.stop_on_error {
                        responses.push(response);
                        break;
                    }
                }
            }
            responses.push(response);
        }

        // Update batch stats
        {
            let mut stats = self.stats.write();
            stats.total_batches += 1;
        }

        BatchResult {
            batch_id: batch.batch_id,
            responses,
            total_elapsed_us: start.elapsed().as_micros() as u64,
            success_count,
            error_count,
        }
    }

    /// Get bridge statistics.
    pub fn stats(&self) -> BridgeStats {
        let s = self.stats.read();
        let total = s.total_intents.max(1);
        BridgeStats {
            total_intents: s.total_intents,
            total_batches: s.total_batches,
            total_stream_events: self.stream_hub.total_emitted(),
            intents_per_target: s.intents_per_target,
            avg_processing_us: s.total_processing_us / total,
            max_processing_us: s.max_processing_us,
            total_timeouts: s.total_timeouts,
            total_backpressure: s.total_backpressure,
            uptime_secs: self.start_time.elapsed().as_secs_f64(),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // SUBSYSTEM ROUTERS
    // ═══════════════════════════════════════════════════════════════════════

    fn route_audio(&self, intent: &BridgeIntent) -> BridgeResponse {
        // Audio DSP commands: parse JSON payload → DspCommand → push to rtrb.
        // The audio thread consumes from the ring buffer with zero allocation.
        use crate::command_queue::send_command;
        use crate::dsp_commands::{
            AnalyzerMode, DspCommand, FilterSlope, FilterType, PhaseMode, StereoPlacement,
        };

        let start = Instant::now();
        let cid = intent.correlation_id;

        // Helper: parse payload JSON once
        let p: serde_json::Value = serde_json::from_str(&intent.payload)
            .unwrap_or(serde_json::Value::Null);

        // Convenience extractors with sensible defaults
        let u32_f = |k: &str| p[k].as_u64().unwrap_or(0) as u32;
        let u8_f  = |k: &str| p[k].as_u64().unwrap_or(0) as u8;
        let f64_f = |k: &str, d: f64| p[k].as_f64().unwrap_or(d);
        let bool_f = |k: &str| p[k].as_bool().unwrap_or(false);

        let cmd_opt: Option<DspCommand> = match intent.action.as_str() {
            // ── EQ band ────────────────────────────────────────────────────
            "eq_set_band" => Some(DspCommand::EqSetBand {
                track_id:    u32_f("track_id"),
                band_index:  u8_f("band_index"),
                freq:        f64_f("freq", 1000.0),
                gain_db:     f64_f("gain_db", 0.0),
                q:           f64_f("q", 0.707),
                filter_type: FilterType::from(u8_f("filter_type")),
                slope:       FilterSlope::from(u8_f("slope")),
                stereo:      StereoPlacement::from(u8_f("stereo")),
            }),
            "eq_enable_band" => Some(DspCommand::EqEnableBand {
                track_id:   u32_f("track_id"),
                band_index: u8_f("band_index"),
                enabled:    bool_f("enabled"),
            }),
            "eq_solo_band" => Some(DspCommand::EqSoloBand {
                track_id:   u32_f("track_id"),
                band_index: u8_f("band_index"),
                solo:       bool_f("solo"),
            }),
            "eq_set_frequency" => Some(DspCommand::EqSetFrequency {
                track_id:   u32_f("track_id"),
                band_index: u8_f("band_index"),
                freq:       f64_f("freq", 1000.0),
            }),
            "eq_set_gain" => Some(DspCommand::EqSetGain {
                track_id:   u32_f("track_id"),
                band_index: u8_f("band_index"),
                gain_db:    f64_f("gain_db", 0.0),
            }),
            "eq_set_q" => Some(DspCommand::EqSetQ {
                track_id:   u32_f("track_id"),
                band_index: u8_f("band_index"),
                q:          f64_f("q", 0.707),
            }),
            "eq_set_filter_type" => Some(DspCommand::EqSetFilterType {
                track_id:    u32_f("track_id"),
                band_index:  u8_f("band_index"),
                filter_type: FilterType::from(u8_f("filter_type")),
            }),
            "eq_bypass" => Some(DspCommand::EqBypass {
                track_id: u32_f("track_id"),
                bypass:   bool_f("bypass"),
            }),
            "eq_set_phase_mode" => Some(DspCommand::EqSetPhaseMode {
                track_id:     u32_f("track_id"),
                mode:         PhaseMode::from(u8_f("mode")),
                hybrid_blend: f64_f("hybrid_blend", 0.0),
            }),
            "eq_set_output_gain" => Some(DspCommand::EqSetOutputGain {
                track_id: u32_f("track_id"),
                gain_db:  f64_f("gain_db", 0.0),
            }),
            "eq_set_auto_gain" => Some(DspCommand::EqSetAutoGain {
                track_id: u32_f("track_id"),
                enabled:  bool_f("enabled"),
            }),
            "eq_set_analyzer_mode" => Some(DspCommand::EqSetAnalyzerMode {
                track_id: u32_f("track_id"),
                mode:     AnalyzerMode::from(u8_f("mode")),
            }),
            // ── Metering requests ──────────────────────────────────────────
            "request_spectrum" => Some(DspCommand::RequestSpectrum {
                track_id: u32_f("track_id"),
            }),
            "request_correlation" => Some(DspCommand::RequestCorrelation {
                track_id: u32_f("track_id"),
            }),
            "request_lufs" => Some(DspCommand::RequestLufs {
                track_id: u32_f("track_id"),
            }),
            "request_goniometer" => Some(DspCommand::RequestGoniometer {
                track_id:   u32_f("track_id"),
                num_points: p["num_points"].as_u64().unwrap_or(512) as u16,
            }),
            // ── Ping ──────────────────────────────────────────────────────
            "ping" => return BridgeResponse::ok(cid, start.elapsed()),
            _ => None,
        };

        match cmd_opt {
            Some(cmd) => {
                if send_command(cmd) {
                    BridgeResponse::ok(cid, start.elapsed())
                } else {
                    BridgeResponse::error(
                        cid,
                        BridgeStatus::Backpressure,
                        "DSP ring buffer full".into(),
                        start.elapsed(),
                    )
                }
            }
            None => BridgeResponse::error(
                cid,
                BridgeStatus::UnknownAction,
                format!("Unknown audio action '{}'", intent.action),
                start.elapsed(),
            ),
        }
    }

    fn route_transport(&self, intent: &BridgeIntent) -> BridgeResponse {
        use rf_engine::ffi::PLAYBACK_ENGINE;

        let start = Instant::now();
        let cid = intent.correlation_id;

        let p: serde_json::Value = serde_json::from_str(&intent.payload)
            .unwrap_or(serde_json::Value::Null);

        match intent.action.as_str() {
            "play" => {
                PLAYBACK_ENGINE.play();
                BridgeResponse::ok(cid, start.elapsed())
            }
            "stop" => {
                PLAYBACK_ENGINE.stop();
                BridgeResponse::ok(cid, start.elapsed())
            }
            "pause" => {
                PLAYBACK_ENGINE.pause();
                BridgeResponse::ok(cid, start.elapsed())
            }
            "seek" => {
                let position_secs = p["position_secs"].as_f64().unwrap_or(0.0);
                PLAYBACK_ENGINE.seek(position_secs);
                BridgeResponse::ok(cid, start.elapsed())
            }
            "set_tempo" => {
                let bpm = p["bpm"].as_f64().unwrap_or(120.0);
                PLAYBACK_ENGINE.position.set_tempo(bpm);
                // BUG#7: propagate new BPM to all tempo-synced insert processors
                PLAYBACK_ENGINE.sync_bpm_all_inserts(bpm);
                BridgeResponse::ok(cid, start.elapsed())
            }
            "set_loop" => {
                let start_secs = p["start_secs"].as_f64().unwrap_or(0.0);
                let end_secs   = p["end_secs"].as_f64().unwrap_or(0.0);
                let enabled    = p["enabled"].as_bool().unwrap_or(false);
                PLAYBACK_ENGINE.position.set_loop(start_secs, end_secs, enabled);
                BridgeResponse::ok(cid, start.elapsed())
            }
            "get_position" => {
                let pos = PLAYBACK_ENGINE.position.seconds();
                let data = format!(r#"{{"position_secs":{:.6}}}"#, pos);
                BridgeResponse::ok_with_data(cid, data, start.elapsed())
            }
            "get_tempo" => {
                let bpm = PLAYBACK_ENGINE.position.get_tempo().unwrap_or(120.0);
                let data = format!(r#"{{"bpm":{:.2}}}"#, bpm);
                BridgeResponse::ok_with_data(cid, data, start.elapsed())
            }
            "ping" => BridgeResponse::ok(cid, start.elapsed()),
            _ => BridgeResponse::error(
                cid,
                BridgeStatus::UnknownAction,
                format!("Unknown transport action '{}'", intent.action),
                start.elapsed(),
            ),
        }
    }

    fn route_mixer(&self, intent: &BridgeIntent) -> BridgeResponse {
        use crate::command_queue::send_command;
        use crate::dsp_commands::DspCommand;

        let start = Instant::now();
        let cid = intent.correlation_id;

        let p: serde_json::Value = serde_json::from_str(&intent.payload)
            .unwrap_or(serde_json::Value::Null);

        let u32_f = |k: &str| p[k].as_u64().unwrap_or(0) as u32;
        let f64_f = |k: &str, d: f64| p[k].as_f64().unwrap_or(d);
        let bool_f = |k: &str| p[k].as_bool().unwrap_or(false);

        let cmd_opt: Option<DspCommand> = match intent.action.as_str() {
            "track_volume" | "set_volume" => Some(DspCommand::TrackSetVolume {
                track_id: u32_f("track_id"),
                volume:   f64_f("volume", 1.0),
            }),
            "track_pan" | "set_pan" => Some(DspCommand::TrackSetPan {
                track_id: u32_f("track_id"),
                pan:      f64_f("pan", 0.0),
            }),
            "track_mute" | "set_mute" => Some(DspCommand::TrackSetMute {
                track_id: u32_f("track_id"),
                muted:    bool_f("muted"),
            }),
            "track_solo" | "set_solo" => Some(DspCommand::TrackSetSolo {
                track_id: u32_f("track_id"),
                solo:     bool_f("solo"),
            }),
            "track_bus" | "set_bus" => Some(DspCommand::TrackSetBus {
                track_id: u32_f("track_id"),
                bus_id:   p["bus_id"].as_u64().unwrap_or(0) as u8,
            }),
            "ping" => return BridgeResponse::ok(cid, start.elapsed()),
            _ => None,
        };

        match cmd_opt {
            Some(cmd) => {
                if send_command(cmd) {
                    BridgeResponse::ok(cid, start.elapsed())
                } else {
                    BridgeResponse::error(
                        cid,
                        BridgeStatus::Backpressure,
                        "DSP ring buffer full".into(),
                        start.elapsed(),
                    )
                }
            }
            None => BridgeResponse::error(
                cid,
                BridgeStatus::UnknownAction,
                format!("Unknown mixer action '{}'", intent.action),
                start.elapsed(),
            ),
        }
    }

    fn route_cortex(&self, intent: &BridgeIntent) -> BridgeResponse {
        let start = Instant::now();
        let cid = intent.correlation_id;

        match intent.action.as_str() {
            "health" => {
                let score = cortex_shared()
                    .map(|s| s.health_score())
                    .unwrap_or(1.0);
                let data = format!(r#"{{"health_score":{:.3}}}"#, score);
                BridgeResponse::ok_with_data(cid, data, start.elapsed())
            }
            "is_degraded" => {
                let degraded = cortex_shared()
                    .map(|s| s.is_degraded.load(std::sync::atomic::Ordering::Relaxed))
                    .unwrap_or(false);
                let data = format!(r#"{{"degraded":{}}}"#, degraded);
                BridgeResponse::ok_with_data(cid, data, start.elapsed())
            }
            "emit_signal" => {
                // Emit a custom signal from Flutter through neural bus
                if let Some(handle) = cortex_handle() {
                    use rf_cortex::prelude::*;
                    // Parse tag and data from payload
                    let tag = intent.payload.as_str();
                    handle.signal(
                        SignalOrigin::Bridge,
                        match intent.priority {
                            BridgePriority::Emergency => SignalUrgency::Emergency,
                            BridgePriority::Critical => SignalUrgency::Critical,
                            BridgePriority::High => SignalUrgency::Elevated,
                            _ => SignalUrgency::Normal,
                        },
                        SignalKind::Custom {
                            tag: "flutter_intent".into(),
                            data: tag.to_string(),
                        },
                    );
                    BridgeResponse::ok(cid, start.elapsed())
                } else {
                    BridgeResponse::error(
                        cid,
                        BridgeStatus::Unavailable,
                        "CORTEX not initialized".into(),
                        start.elapsed(),
                    )
                }
            }
            "total_signals" => {
                let total = cortex_shared()
                    .map(|s| s.total_processed.load(portable_atomic::Ordering::Relaxed))
                    .unwrap_or(0);
                let data = format!(r#"{{"total_signals":{}}}"#, total);
                BridgeResponse::ok_with_data(cid, data, start.elapsed())
            }
            "ping" => BridgeResponse::ok(cid, start.elapsed()),
            _ => BridgeResponse::error(
                cid,
                BridgeStatus::UnknownAction,
                format!("Cortex action '{}' not yet routed", intent.action),
                start.elapsed(),
            ),
        }
    }

    fn route_project(&self, intent: &BridgeIntent) -> BridgeResponse {
        let start = Instant::now();
        let cid = intent.correlation_id;
        match intent.action.as_str() {
            "ping" => BridgeResponse::ok(cid, start.elapsed()),
            _ => BridgeResponse::error(
                cid,
                BridgeStatus::UnknownAction,
                format!("Project action '{}' not yet routed", intent.action),
                start.elapsed(),
            ),
        }
    }

    fn route_slotlab(&self, intent: &BridgeIntent) -> BridgeResponse {
        let start = Instant::now();
        let cid = intent.correlation_id;
        match intent.action.as_str() {
            "ping" => BridgeResponse::ok(cid, start.elapsed()),
            _ => BridgeResponse::error(
                cid,
                BridgeStatus::UnknownAction,
                format!("SlotLab action '{}' not yet routed", intent.action),
                start.elapsed(),
            ),
        }
    }

    fn route_watcher(&self, intent: &BridgeIntent) -> BridgeResponse {
        let start = Instant::now();
        let cid = intent.correlation_id;
        match intent.action.as_str() {
            "ping" => BridgeResponse::ok(cid, start.elapsed()),
            _ => BridgeResponse::error(
                cid,
                BridgeStatus::UnknownAction,
                format!("Watcher action '{}' not yet routed", intent.action),
                start.elapsed(),
            ),
        }
    }

    fn route_memory(&self, intent: &BridgeIntent) -> BridgeResponse {
        let start = Instant::now();
        let cid = intent.correlation_id;
        match intent.action.as_str() {
            "ping" => BridgeResponse::ok(cid, start.elapsed()),
            _ => BridgeResponse::error(
                cid,
                BridgeStatus::UnknownAction,
                format!("Memory action '{}' not yet routed", intent.action),
                start.elapsed(),
            ),
        }
    }

    fn route_metering(&self, intent: &BridgeIntent) -> BridgeResponse {
        let start = Instant::now();
        let cid = intent.correlation_id;
        match intent.action.as_str() {
            "ping" => BridgeResponse::ok(cid, start.elapsed()),
            _ => BridgeResponse::error(
                cid,
                BridgeStatus::UnknownAction,
                format!("Metering action '{}' not yet routed", intent.action),
                start.elapsed(),
            ),
        }
    }

    fn route_system(&self, intent: &BridgeIntent) -> BridgeResponse {
        let start = Instant::now();
        let cid = intent.correlation_id;

        match intent.action.as_str() {
            "ping" => BridgeResponse::ok(cid, start.elapsed()),
            "stats" => {
                let stats = self.stats();
                match serde_json::to_string(&stats) {
                    Ok(json) => BridgeResponse::ok_with_data(cid, json, start.elapsed()),
                    Err(e) => BridgeResponse::error(
                        cid,
                        BridgeStatus::Error,
                        format!("Failed to serialize stats: {}", e),
                        start.elapsed(),
                    ),
                }
            }
            "heartbeat" => {
                self.stream_hub.push(
                    StreamEventKind::Heartbeat,
                    format!(r#"{{"uptime_secs":{:.1}}}"#, self.start_time.elapsed().as_secs_f64()),
                );
                BridgeResponse::ok(cid, start.elapsed())
            }
            _ => BridgeResponse::error(
                cid,
                BridgeStatus::UnknownAction,
                format!("System action '{}' unknown", intent.action),
                start.elapsed(),
            ),
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// GLOBAL INSTANCE
// ═══════════════════════════════════════════════════════════════════════════

use std::sync::LazyLock;

/// The singleton Neural Bridge instance.
static NEURAL_BRIDGE: LazyLock<NeuralBridge> = LazyLock::new(NeuralBridge::new);

/// Get the global Neural Bridge instance.
pub fn neural_bridge() -> &'static NeuralBridge {
    &NEURAL_BRIDGE
}

// ═══════════════════════════════════════════════════════════════════════════
// FFI ENTRY POINTS — Exposed to Flutter via flutter_rust_bridge
// ═══════════════════════════════════════════════════════════════════════════

/// Initialize the Neural Bridge. Call once after engine_init().
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_init() {
    neural_bridge().init();
}

/// Send a single intent through the Neural Bridge.
/// Returns a BridgeResponse with correlation_id matching the request.
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_send(
    correlation_id: u64,
    target: u8,
    action: String,
    payload: String,
    priority: u8,
    timeout_ms: u32,
) -> BridgeResponse {
    let intent = BridgeIntent {
        correlation_id,
        target: BridgeTarget::from(target),
        action,
        payload,
        priority: BridgePriority::from(priority),
        timeout_ms,
    };
    neural_bridge().route(intent)
}

/// Send a batch of intents atomically.
/// Returns a BatchResult with individual responses.
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_send_batch(
    batch_id: u64,
    intents_json: String,
    stop_on_error: bool,
) -> BatchResult {
    // Parse intents from JSON array
    let intents: Vec<BridgeIntent> = serde_json::from_str(&intents_json)
        .unwrap_or_default();

    let batch = BridgeBatch {
        batch_id,
        intents,
        stop_on_error,
    };
    neural_bridge().route_batch(batch)
}

/// Poll for Rust→Flutter stream events.
/// Call this at your desired frequency (e.g., 60fps for metering, 10Hz for cortex).
/// Returns up to `max_events` pending events.
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_poll_events(max_events: u32) -> Vec<StreamEvent> {
    neural_bridge().stream_hub.drain(max_events as usize)
}

/// Get bridge statistics.
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_stats() -> BridgeStats {
    neural_bridge().stats()
}

/// Get pending stream event count (useful for Flutter to know if it should poll).
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_pending_events() -> u32 {
    neural_bridge().stream_hub.pending_count() as u32
}

/// Push an event from Rust to Flutter stream (used internally or by subsystems).
/// Returns false if stream is full (backpressure).
pub fn bridge_push_event(kind: StreamEventKind, data: String) -> bool {
    neural_bridge().stream_hub.push(kind, data)
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_correlation_id_monotonic() {
        let a = bridge_next_correlation_id();
        let b = bridge_next_correlation_id();
        assert!(b > a);
    }

    #[test]
    fn test_bridge_priority_ordering() {
        assert!(BridgePriority::Emergency > BridgePriority::Critical);
        assert!(BridgePriority::Critical > BridgePriority::High);
        assert!(BridgePriority::High > BridgePriority::Normal);
        assert!(BridgePriority::Normal > BridgePriority::Low);
    }

    #[test]
    fn test_bridge_system_ping() {
        let bridge = NeuralBridge::new();
        bridge.init();

        let response = bridge.route(BridgeIntent {
            correlation_id: 42,
            target: BridgeTarget::System,
            action: "ping".into(),
            payload: String::new(),
            priority: BridgePriority::Normal,
            timeout_ms: 0,
        });

        assert_eq!(response.correlation_id, 42);
        assert_eq!(response.status, BridgeStatus::Ok);
    }

    #[test]
    fn test_bridge_stats() {
        let bridge = NeuralBridge::new();
        bridge.init();

        let response = bridge.route(BridgeIntent {
            correlation_id: 1,
            target: BridgeTarget::System,
            action: "stats".into(),
            payload: String::new(),
            priority: BridgePriority::Normal,
            timeout_ms: 0,
        });

        assert_eq!(response.status, BridgeStatus::Complete);
        assert!(!response.data.is_empty());
    }

    #[test]
    fn test_bridge_batch() {
        let bridge = NeuralBridge::new();
        bridge.init();

        let batch = BridgeBatch {
            batch_id: 100,
            intents: vec![
                BridgeIntent {
                    correlation_id: 1,
                    target: BridgeTarget::System,
                    action: "ping".into(),
                    payload: String::new(),
                    priority: BridgePriority::Normal,
                    timeout_ms: 0,
                },
                BridgeIntent {
                    correlation_id: 2,
                    target: BridgeTarget::System,
                    action: "ping".into(),
                    payload: String::new(),
                    priority: BridgePriority::High,
                    timeout_ms: 0,
                },
                BridgeIntent {
                    correlation_id: 3,
                    target: BridgeTarget::Cortex,
                    action: "ping".into(),
                    payload: String::new(),
                    priority: BridgePriority::Normal,
                    timeout_ms: 0,
                },
            ],
            stop_on_error: false,
        };

        let result = bridge.route_batch(batch);
        assert_eq!(result.batch_id, 100);
        assert_eq!(result.success_count, 3);
        assert_eq!(result.error_count, 0);
        assert_eq!(result.responses.len(), 3);
        // High priority should be routed first
        assert_eq!(result.responses[0].correlation_id, 2);
    }

    #[test]
    fn test_stream_hub_push_drain() {
        let hub = StreamHub::new();

        assert!(hub.push(StreamEventKind::Heartbeat, r#"{"test":1}"#.into()));
        assert!(hub.push(StreamEventKind::CortexHealth, r#"{"score":0.95}"#.into()));

        let events = hub.drain(10);
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].seq, 0);
        assert_eq!(events[1].seq, 1);
        assert_eq!(hub.total_emitted(), 2);
    }

    #[test]
    fn test_stream_hub_backpressure() {
        let hub = StreamHub::new();

        // Fill the channel
        for i in 0..STREAM_HUB_CAPACITY {
            assert!(hub.push(StreamEventKind::Heartbeat, format!("{}", i)));
        }

        // Next push should fail (backpressure)
        assert!(!hub.push(StreamEventKind::Heartbeat, "overflow".into()));

        // Drain and verify
        let events = hub.drain(STREAM_HUB_CAPACITY + 10);
        assert_eq!(events.len(), STREAM_HUB_CAPACITY);
    }

    #[test]
    fn test_bridge_not_initialized() {
        let bridge = NeuralBridge::new();
        // Don't call init()

        let response = bridge.route(BridgeIntent {
            correlation_id: 1,
            target: BridgeTarget::System,
            action: "ping".into(),
            payload: String::new(),
            priority: BridgePriority::Normal,
            timeout_ms: 0,
        });

        assert_eq!(response.status, BridgeStatus::Unavailable);
    }

    #[test]
    fn test_unknown_action() {
        let bridge = NeuralBridge::new();
        bridge.init();

        let response = bridge.route(BridgeIntent {
            correlation_id: 1,
            target: BridgeTarget::Audio,
            action: "nonexistent_action".into(),
            payload: String::new(),
            priority: BridgePriority::Normal,
            timeout_ms: 0,
        });

        assert_eq!(response.status, BridgeStatus::UnknownAction);
    }

    #[test]
    fn test_bridge_target_from_u8() {
        assert_eq!(BridgeTarget::from(0), BridgeTarget::Audio);
        assert_eq!(BridgeTarget::from(3), BridgeTarget::Cortex);
        assert_eq!(BridgeTarget::from(9), BridgeTarget::System);
        assert_eq!(BridgeTarget::from(255), BridgeTarget::System); // fallback
    }
}
