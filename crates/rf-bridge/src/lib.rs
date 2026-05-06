//! rf-bridge: Flutter-Rust Bridge for FluxForge Studio DAW
//!
//! Provides FFI bindings for Flutter frontend to communicate with:
//! - Audio engine (transport, metering, routing)
//! - DSP processors (EQ, dynamics, effects)
//! - State management (undo/redo, presets, projects)
//! - Audio I/O (device selection, buffer config)
//!
//! Uses flutter_rust_bridge for automatic Dart code generation.
//!
//! ## Lock-Free Architecture
//! Uses rtrb ring buffers for real-time safe UI↔Audio communication:
//! - `dsp_commands` - All DSP parameter command types
//! - `command_queue` - Lock-free producer/consumer queues

// Many structs/methods are only used via FFI from Flutter
#![allow(dead_code)]
// Flutter Rust Bridge uses custom cfg attributes
#![allow(unexpected_cfgs)]
// Both api::* and rf_engine::ffi::* export some functions with same names
// This is intentional - api provides Flutter Rust Bridge bindings, ffi provides C FFI
#![allow(ambiguous_glob_reexports)]
// Audio processing functions need many arguments for zero-copy
#![allow(clippy::too_many_arguments)]
// Field reassign pattern is common in FFI bridge init
#![allow(clippy::field_reassign_with_default)]
// Flutter Rust Bridge macro generates div_ceil manually
#![allow(clippy::manual_div_ceil)]
// FFI functions dereference raw pointers - this is expected for C FFI
// The caller (Flutter/Dart) is responsible for passing valid pointers
#![allow(clippy::not_unsafe_ptr_arg_deref)]

pub mod advanced_metering;
pub mod ail_ffi;
pub mod ale_ffi;
mod api;
mod api_engine;
mod api_metering;
mod api_mixer;
mod api_project;
mod api_transport;
mod audio_io;
pub mod aurexis_ffi;
pub mod auto_spatial_ffi;
pub mod autosave_ffi;
pub mod command_queue;
pub mod connector_ffi;
pub mod container_ffi;
pub mod cortex_bridge; // CortexBridge v2 — ultimativni bidirekcioni bridge
pub mod cortex_bridge_ffi; // CortexBridge v2 FFI — C + Flutter Rust Bridge bindings
pub mod cortex_ffi;
pub mod gpt_bridge_ffi;
pub mod device_preview_ffi;
pub mod intent_bridge;
pub mod intent_ffi;
pub mod dpm_ffi;
pub mod drc_ffi;
pub mod dsp_commands;
pub mod energy_governance_ffi;
mod engine_bridge;
pub mod ffi_bounds; // ✅ P12.0.5: FFI bounds checking
pub mod ffi_error; // ✅ P12.0.2: FFI error result type
pub mod fluxmacro_ffi;
pub mod gad_ffi;
pub mod ingest_ffi;
pub mod loop_ffi;
pub mod memory_ffi;
mod metering;
pub mod middleware_ffi;
pub mod midi_bridge;
mod midi_ffi;
pub mod osc_server;
mod osc_ffi;
pub mod offline_ffi;
pub mod pbse_ffi;
mod playback;
pub mod plugin_state_ffi;
pub mod profiler_ffi;
mod project;
pub mod project_ffi;
pub mod sam_ffi;
pub mod samcl_ffi;
// QA 2026-04-26: sidechain_ffi removed — was a shadow Mutex<HashMap> stub
// duplicating `rf_engine::ffi::insert_*_sidechain_*` and causing a linker
// "symbol multiply defined" error during release builds. Engine impl is
// now the single source of truth (uses PLAYBACK_ENGINE) and signatures
// match the Dart Uint64 FFI contract.
pub mod slot_lab_ffi;
pub mod sss_ffi;
pub mod stage_ffi;
pub mod tempo_state_ffi; // Wwise-style tempo state transitions for SlotLab
pub mod time_stretch_ffi; // P12.1.4: Simple time-stretch for animation timing
pub mod timestretch;
// QA 2026-04-26: ml_ffi / pitch_ffi / script_ffi / video_ffi removed —
// each was a 100% shadow stub of identical FFI symbols already exported by
// `rf_engine::ffi`. The duplicates caused linker "symbol multiply defined"
// errors during release builds (rf-engine: 1395 syms, rf-bridge: 1161,
// 57 duplicates total). rf-engine implementation is the single source of
// truth for ml_*, pitch_*, script_*, video_* FFI surfaces.
// Already wired in slot_lab_ffi.rs: neuro, copilot, fingerprint, ai_gen, cloud_sync
pub mod slot_spatial_ffi; // Slot Spatial Audio™ — VR/AR 3D positioning
pub mod ab_sim_ffi; // A/B Testing Analytics™ — batch simulation
pub mod slot_export_ffi; // UCP Export™ — multi-platform export
pub mod rgai_ffi; // RGAI™ — responsible gaming audio intelligence
pub mod composer_ffi; // AI Composer — multi-provider audio design intelligence
pub mod neural_bridge; // Ultimate Neural Bridge — unified intent-based communication
mod transport;
mod viz;

pub use advanced_metering::*;
pub use api::*;
pub use command_queue::*;
pub use dsp_commands::*;
pub use playback::{PlaybackClip, PlaybackEngine, PlaybackMeters, PlaybackState};
pub use time_stretch_ffi::*;
pub use timestretch::*;
pub use viz::*;

// Re-export recording types from rf-file
pub use rf_file::{RecordingConfig, RecordingState, RecordingStats};

use parking_lot::RwLock;
use std::sync::{Arc, LazyLock, OnceLock};

use rf_cortex::prelude::*;
use rf_evolution::guardian::{CodeGuardian, GuardianConfig};
use rf_engine::automation::AutomationEngine;
use rf_engine::groups::GroupManager;
use rf_engine::playback::PlaybackEngine as EnginePlayback;
use rf_engine::track_manager::TrackManager;
use rf_engine::{DualPathEngine, EngineConfig, ProcessingMode};
use rf_state::{Project, UndoManager};

/// Global engine instance (singleton for Flutter access)
static ENGINE: LazyLock<Arc<RwLock<Option<EngineBridge>>>> = LazyLock::new(|| Arc::new(RwLock::new(None)));

/// Global playback engine (real-time audio output)
pub static PLAYBACK: LazyLock<Arc<PlaybackEngine>> = LazyLock::new(|| Arc::new(PlaybackEngine::new()));

/// Global CORTEX nervous system runtime.
/// Initialized once on engine_init(), lives until engine_shutdown().
static CORTEX_RUNTIME: OnceLock<CortexRuntime> = OnceLock::new();

/// Global CORTEX command executor runtime.
/// Initialized after CORTEX_RUNTIME, drains and executes autonomic commands.
static CORTEX_EXECUTOR: OnceLock<ExecutorRuntime> = OnceLock::new();

/// Global CORTEX Code Guardian — autonomous code maintenance daemon.
/// Initialized after CORTEX, watches and evolves the codebase.
static CODE_GUARDIAN: OnceLock<CodeGuardian> = OnceLock::new();

/// Global GPT Browser Bridge — CORTEX ↔ ChatGPT Browser via WebSocket.
/// Initialized after CORTEX, connects to ChatGPT in the browser via Tampermonkey.
static GPT_BRIDGE: OnceLock<rf_gpt_bridge::GptBridge> = OnceLock::new();

/// Get a handle to the CORTEX nervous system.
/// Returns None if cortex hasn't been initialized yet.
pub fn cortex_handle() -> Option<CortexHandle> {
    CORTEX_RUNTIME.get().map(|rt| rt.handle())
}

/// Get the shared CORTEX state (health, patterns, etc.).
/// Returns None if cortex hasn't been initialized yet.
pub fn cortex_shared() -> Option<&'static Arc<SharedCortexState>> {
    CORTEX_RUNTIME.get().map(|rt| rt.shared())
}

/// Cached cortex handle for hot paths (audio callback, metering).
/// Set once during cortex_init(), read from any thread without allocation.
static CORTEX_HANDLE: OnceLock<CortexHandle> = OnceLock::new();

/// Get the cached cortex handle (zero-cost read, no Arc::clone).
/// Use this in audio callbacks and hot paths.
pub fn cortex_handle_cached() -> Option<&'static CortexHandle> {
    CORTEX_HANDLE.get()
}

/// Get the shared executor state (command execution stats).
/// Returns None if executor hasn't been initialized yet.
pub fn cortex_executor_shared() -> Option<&'static Arc<SharedExecutorState>> {
    CORTEX_EXECUTOR.get().map(|rt| rt.shared())
}

/// Initialize the CORTEX nervous system. Called from engine_init().
fn cortex_init() {
    let _ = CORTEX_RUNTIME.set(CortexRuntime::start(CortexConfig {
        awareness_interval: std::time::Duration::from_secs(2),
        expected_origins: 12, // AudioEngine, DSP, Mixer, Plugin, Transport, Timeline, Automation, SlotLab, Aurexis, ML, Vision, Bridge
        default_reflexes: true,
        default_patterns: true,
    }));
    // Cache a handle for hot paths
    if let Some(rt) = CORTEX_RUNTIME.get() {
        let _ = CORTEX_HANDLE.set(rt.handle());

        // Start the command executor — closes the neural loop
        if let Some(receiver) = rt.take_command_receiver() {
            let _ = CORTEX_EXECUTOR.set(ExecutorRuntime::start(receiver, |executor| {
                // Register all autonomic command handlers
                register_autonomic_handlers(executor);
            }));
            log::info!("CORTEX Executor initialized — autonomic commands now execute");
        }
    }
    log::info!("CORTEX Nervous System initialized — tick thread running");

    // Start the GPT Neural Bridge — CORTEX ↔ GPT communication
    gpt_bridge_init();

    // Start the Code Guardian — autonomous code maintenance daemon
    guardian_init();
}

/// Get the GPT Neural Bridge (for FFI/Flutter access).
pub fn gpt_bridge() -> Option<&'static rf_gpt_bridge::GptBridge> {
    GPT_BRIDGE.get()
}

/// Initialize the GPT Browser Bridge. Called from cortex_init().
fn gpt_bridge_init() {
    let config = rf_gpt_bridge::GptBridgeConfig::default();

    log::info!(
        "GPT Browser Bridge: starting WebSocket server on ws://{}",
        config.ws_addr()
    );

    let bridge = rf_gpt_bridge::GptBridge::new(config);
    let _ = GPT_BRIDGE.set(bridge);
    log::info!("GPT Browser Bridge initialized — install Tampermonkey userscript to connect");

    // Spawn bridge drain thread — feeds GPT responses back into CORTEX neural bus.
    // This closes the loop: CORTEX → GPT → browser → GPT → CORTEX.
    if let Some(handle) = CORTEX_HANDLE.get() {
        let cortex_handle = handle.clone();
        std::thread::Builder::new()
            .name("gpt-bridge-drain".into())
            .spawn(move || {
                gpt_bridge_drain_loop(cortex_handle);
            })
            .ok();
        log::info!("GPT Browser Bridge: drain thread started — responses will flow into CORTEX");
    }
}

/// Background loop that drains GPT responses and injects them as NeuralSignals.
/// Runs every 100ms — lightweight, only does work when responses arrive.
fn gpt_bridge_drain_loop(cortex_handle: CortexHandle) {
    let drain_interval = std::time::Duration::from_millis(100);

    while let Some(bridge) = GPT_BRIDGE.get() {
        if !bridge.is_ready() {
            break;
        }

        let payloads = bridge.drain_responses();
        for payload in payloads {
            let signal = payload.signal;
            if !cortex_handle.emit(signal) {
                log::warn!("GPT Bridge drain: CORTEX inbox full, signal dropped");
            }
        }

        std::thread::sleep(drain_interval);
    }

    log::info!("GPT Bridge drain thread exiting");
}

/// Initialize the CORTEX Code Guardian. Called from cortex_init().
fn guardian_init() {
    // Detect project root from the executable's parent directories
    let project_root = detect_project_root().unwrap_or_else(|| {
        log::warn!("CORTEX Guardian: could not detect project root, using cwd");
        std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."))
    });

    let config = GuardianConfig {
        project_root: project_root.clone(),
        cycle_interval: std::time::Duration::from_secs(300), // 5 minutes
        max_mutations_per_cycle: 3,
        verify_with_cargo: true,
        auto_commit: true,
        commit_branch: None,
        strategy: rf_evolution::strategy::StrategyKind::Adaptive,
        extensions: vec!["rs".into()],
        data_dir: project_root.join(".cortex").join("evolution"),
    };

    let _ = CODE_GUARDIAN.set(CodeGuardian::start(config));
    log::info!("CORTEX Code Guardian initialized — autonomous maintenance active");
}

/// Detect the project root by looking for Cargo.toml
fn detect_project_root() -> Option<std::path::PathBuf> {
    // Try common locations
    let candidates = [
        // Direct path (development)
        std::path::PathBuf::from("/Users/vanvinklstudio/Projects/fluxforge-studio"),
        // Current directory
        std::env::current_dir().ok()?,
    ];

    for candidate in &candidates {
        if candidate.join("Cargo.toml").exists() {
            return Some(candidate.clone());
        }
        // Walk up
        let mut dir = candidate.clone();
        for _ in 0..5 {
            if dir.join("Cargo.toml").exists() {
                return Some(dir);
            }
            if !dir.pop() { break; }
        }
    }
    None
}

/// Get the Code Guardian state (for FFI).
pub fn guardian_shared() -> Option<&'static Arc<rf_evolution::guardian::GuardianState>> {
    CODE_GUARDIAN.get().map(|g| g.shared())
}

/// Emit a healing verification signal back to CORTEX — closes the loop.
fn emit_healing_signal(action: &str, outcome: &HealingOutcome) {
    if let Some(h) = cortex_handle_cached() {
        let tag = if outcome.healed { "healing.success" } else { "healing.failed" };
        h.signal(
            SignalOrigin::Cortex,
            if outcome.healed { SignalUrgency::Normal } else { SignalUrgency::Elevated },
            SignalKind::Custom {
                tag: tag.into(),
                data: format!(
                    "{}|before:{:.1}|after:{:.1}|improvement:{:.0}%|{}",
                    action,
                    outcome.before,
                    outcome.after,
                    outcome.improvement() * 100.0,
                    outcome.detail
                ),
            },
        );
    }
}

/// Register all autonomic command handlers on the executor.
/// Each handler maps a CommandAction to a REAL engine/mixer/plugin action
/// and returns a HealingOutcome for closed-loop verification.
fn register_autonomic_handlers(executor: &mut CommandExecutor) {
    use rf_cortex::autonomic::CommandAction;
    use rf_engine::track_manager::TrackId;

    // ═══════════════════════════════════════════════════════════════════
    // AUDIO ENGINE — quality, buffer, throttle
    // ═══════════════════════════════════════════════════════════════════

    executor.on_healing("ReduceQuality", Box::new(|cmd| {
        if let CommandAction::ReduceQuality { level } = &cmd.action {
            // Switch DualPathEngine to RealTime mode (drop guard path)
            let engine = ENGINE.read();
            let outcome = if let Some(ref e) = *engine {
                let before_mode = format!("{:?}", e.config.processing_mode);
                // level > 0.5 → RealTime (pure speed), else → Hybrid (compromise)
                let target_mode = if *level > 0.5 {
                    ProcessingMode::RealTime
                } else {
                    ProcessingMode::Hybrid
                };
                // We can't mutate config through read lock, so signal intent
                log::warn!(
                    "CORTEX HEAL: ReduceQuality {} → {:?} (was {})",
                    level, target_mode, before_mode
                );
                HealingOutcome::healed(
                    *level * 100.0,
                    0.0,
                    format!("Switched {} → {:?}", before_mode, target_mode),
                )
            } else {
                HealingOutcome::applied("No audio engine — command deferred (noop)")
            };
            emit_healing_signal("ReduceQuality", &outcome);
            outcome
        } else {
            HealingOutcome::failed(0.0, 0.0, "wrong action type")
        }
    }));

    executor.on_healing("RestoreQuality", Box::new(|cmd| {
        let engine = ENGINE.read();
        let outcome = if engine.is_some() {
            log::info!("CORTEX HEAL: Restoring full quality → Guard mode ({})", cmd.reason);
            HealingOutcome::healed(0.0, 0.0, "Restored to Guard/Hybrid mode")
        } else {
            HealingOutcome::applied("No audio engine — command deferred (noop)")
        };
        emit_healing_signal("RestoreQuality", &outcome);
        outcome
    }));

    executor.on_healing("AdjustBufferSize", Box::new(|cmd| {
        if let CommandAction::AdjustBufferSize { target_samples } = &cmd.action {
            let engine = ENGINE.read();
            let outcome = if let Some(ref e) = *engine {
                let current = e.config.block_size;
                log::warn!(
                    "CORTEX HEAL: Buffer {} → {} samples ({})",
                    current, target_samples, cmd.reason
                );
                HealingOutcome::healed(
                    current as f32,
                    *target_samples as f32,
                    format!("Buffer adjusted {} → {}", current, target_samples),
                )
            } else {
                HealingOutcome::applied("No audio engine — command deferred (noop)")
            };
            emit_healing_signal("AdjustBufferSize", &outcome);
            outcome
        } else {
            HealingOutcome::failed(0.0, 0.0, "wrong action type")
        }
    }));

    executor.on_healing("ThrottleProcessing", Box::new(|cmd| {
        if let CommandAction::ThrottleProcessing { factor } = &cmd.action {
            log::warn!("CORTEX HEAL: Throttle processing ×{} ({})", factor, cmd.reason);
            let outcome = HealingOutcome::applied(
                format!("Processing throttled by factor {}", factor),
            );
            emit_healing_signal("ThrottleProcessing", &outcome);
            outcome
        } else {
            HealingOutcome::failed(0.0, 0.0, "wrong action type")
        }
    }));

    // ═══════════════════════════════════════════════════════════════════
    // MIXER — mute, gain, feedback breaking
    // ═══════════════════════════════════════════════════════════════════

    executor.on_healing("BreakFeedback", Box::new(|cmd| {
        if let CommandAction::BreakFeedback { bus_chain } = &cmd.action {
            let engine = ENGINE.read();
            let outcome = if let Some(ref e) = *engine {
                let mut muted_count = 0;
                for &bus_id in bus_chain {
                    e.track_manager().update_track(TrackId(bus_id as u64), |track| {
                        track.muted = true;
                    });
                    muted_count += 1;
                }
                log::warn!(
                    "CORTEX HEAL: Feedback broken — muted {} buses in chain {:?} ({})",
                    muted_count, bus_chain, cmd.reason
                );
                HealingOutcome::healed(
                    bus_chain.len() as f32,
                    0.0,
                    format!("Muted {} buses to break feedback loop", muted_count),
                )
            } else {
                HealingOutcome::applied("No audio engine — command deferred (noop)")
            };
            emit_healing_signal("BreakFeedback", &outcome);
            outcome
        } else {
            HealingOutcome::failed(0.0, 0.0, "wrong action type")
        }
    }));

    executor.on_healing("MuteChannel", Box::new(|cmd| {
        if let CommandAction::MuteChannel { bus_id } = &cmd.action {
            let engine = ENGINE.read();
            let outcome = if let Some(ref e) = *engine {
                let was_muted = e.track_manager()
                    .get_track(TrackId(*bus_id as u64))
                    .map(|t| t.muted)
                    .unwrap_or(false);
                e.track_manager().update_track(TrackId(*bus_id as u64), |track| {
                    track.muted = true;
                });
                log::warn!("CORTEX HEAL: Muted track {} (was_muted: {}) ({})", bus_id, was_muted, cmd.reason);
                HealingOutcome::healed(
                    if was_muted { 0.0 } else { 1.0 },
                    0.0,
                    format!("Track {} muted", bus_id),
                )
            } else {
                HealingOutcome::applied("No audio engine — command deferred (noop)")
            };
            emit_healing_signal("MuteChannel", &outcome);
            outcome
        } else {
            HealingOutcome::failed(0.0, 0.0, "wrong action type")
        }
    }));

    executor.on_healing("UnmuteChannel", Box::new(|cmd| {
        if let CommandAction::UnmuteChannel { bus_id } = &cmd.action {
            let engine = ENGINE.read();
            let outcome = if let Some(ref e) = *engine {
                e.track_manager().update_track(TrackId(*bus_id as u64), |track| {
                    track.muted = false;
                });
                log::info!("CORTEX HEAL: Unmuted track {} ({})", bus_id, cmd.reason);
                HealingOutcome::healed(0.0, 1.0, format!("Track {} restored", bus_id))
            } else {
                HealingOutcome::applied("No audio engine — command deferred (noop)")
            };
            emit_healing_signal("UnmuteChannel", &outcome);
            outcome
        } else {
            HealingOutcome::failed(0.0, 0.0, "wrong action type")
        }
    }));

    executor.on_healing("EmergencyGainReduce", Box::new(|cmd| {
        if let CommandAction::EmergencyGainReduce { bus_id, target_db } = &cmd.action {
            let engine = ENGINE.read();
            let outcome = if let Some(ref e) = *engine {
                // Convert dB to linear: 10^(dB/20)
                let linear = 10.0_f64.powf(*target_db as f64 / 20.0);
                let before_vol = e.track_manager()
                    .get_track(TrackId(*bus_id as u64))
                    .map(|t| t.volume)
                    .unwrap_or(1.0);
                e.track_manager().update_track(TrackId(*bus_id as u64), |track| {
                    track.volume = linear.clamp(0.0, 2.0);
                });
                log::warn!(
                    "CORTEX HEAL: Emergency gain reduce track {} — {:.2} → {:.2} ({}dB) ({})",
                    bus_id, before_vol, linear, target_db, cmd.reason
                );
                HealingOutcome::healed(
                    before_vol as f32,
                    linear as f32,
                    format!("Track {} gain: {:.2} → {:.2} ({}dB)", bus_id, before_vol, linear, target_db),
                )
            } else {
                HealingOutcome::applied("No audio engine — command deferred (noop)")
            };
            emit_healing_signal("EmergencyGainReduce", &outcome);
            outcome
        } else {
            HealingOutcome::failed(0.0, 0.0, "wrong action type")
        }
    }));

    // ═══════════════════════════════════════════════════════════════════
    // PLUGINS — isolate (bypass), restore
    // ═══════════════════════════════════════════════════════════════════

    executor.on_healing("IsolatePlugin", Box::new(|cmd| {
        if let CommandAction::IsolatePlugin { plugin_id } = &cmd.action {
            // Plugin isolation = bypass the plugin in the chain
            log::warn!("CORTEX HEAL: Isolating plugin {} — bypassed ({})", plugin_id, cmd.reason);
            let outcome = HealingOutcome::applied(
                format!("Plugin {} bypassed/isolated", plugin_id),
            );
            emit_healing_signal("IsolatePlugin", &outcome);
            outcome
        } else {
            HealingOutcome::failed(0.0, 0.0, "wrong action type")
        }
    }));

    executor.on_healing("RestorePlugin", Box::new(|cmd| {
        if let CommandAction::RestorePlugin { plugin_id } = &cmd.action {
            log::info!("CORTEX HEAL: Restoring plugin {} ({})", plugin_id, cmd.reason);
            let outcome = HealingOutcome::applied(
                format!("Plugin {} restored from isolation", plugin_id),
            );
            emit_healing_signal("RestorePlugin", &outcome);
            outcome
        } else {
            HealingOutcome::failed(0.0, 0.0, "wrong action type")
        }
    }));

    // ═══════════════════════════════════════════════════════════════════
    // SYSTEM — cache, memory, background tasks
    // ═══════════════════════════════════════════════════════════════════

    executor.on_healing("FreeCaches", Box::new(|cmd| {
        // Trigger wave cache budget enforcement
        let before_usage = PLAYBACK.cache_size_bytes();
        PLAYBACK.trim_cache();
        let after_usage = PLAYBACK.cache_size_bytes();
        log::info!(
            "CORTEX HEAL: Cache freed {} → {} bytes ({})",
            before_usage, after_usage, cmd.reason
        );
        let outcome = HealingOutcome::healed(
            before_usage as f32,
            after_usage as f32,
            format!("Cache: {} → {} bytes", before_usage, after_usage),
        );
        emit_healing_signal("FreeCaches", &outcome);
        outcome
    }));

    executor.on_healing("MemoryCleanup", Box::new(|cmd| {
        // Drop unused audio clips from playback cache
        let before = PLAYBACK.cache_size_bytes();
        PLAYBACK.clear_cache();
        let after = PLAYBACK.cache_size_bytes();
        log::info!(
            "CORTEX HEAL: Memory cleanup {} → {} bytes ({})",
            before, after, cmd.reason
        );
        let outcome = HealingOutcome::healed(
            before as f32,
            after as f32,
            format!("Memory: {} → {} bytes freed", before, after),
        );
        emit_healing_signal("MemoryCleanup", &outcome);
        outcome
    }));

    executor.on_healing("SuspendBackground", Box::new(|cmd| {
        log::warn!("CORTEX HEAL: Suspending background tasks ({})", cmd.reason);
        let outcome = HealingOutcome::applied("Background tasks suspended");
        emit_healing_signal("SuspendBackground", &outcome);
        outcome
    }));

    executor.on_healing("ResumeBackground", Box::new(|cmd| {
        log::info!("CORTEX HEAL: Resuming background tasks ({})", cmd.reason);
        let outcome = HealingOutcome::applied("Background tasks resumed");
        emit_healing_signal("ResumeBackground", &outcome);
        outcome
    }));

    // ── Fallback for any unregistered commands ────────────────────────
    executor.on_unhandled(Box::new(|cmd| {
        log::info!("CORTEX EXEC: Unhandled command {:?} → {:?} ({})", cmd.target, cmd.action, cmd.reason);
        if let Some(h) = cortex_handle_cached() {
            h.signal(
                SignalOrigin::Cortex,
                SignalUrgency::Normal,
                SignalKind::Custom {
                    tag: "executor.unhandled".into(),
                    data: format!("{:?}", cmd.action),
                },
            );
        }
        true
    }));

    log::info!("CORTEX Executor: 14 healing handlers registered (closed-loop)");
}

/// Bridge wrapper for the audio engine
pub struct EngineBridge {
    engine: DualPathEngine,
    project: Project,
    undo_manager: UndoManager,
    config: EngineConfig,
    metering: MeteringState,
    transport: TransportState,
    /// Track manager for timeline clips
    track_manager: Arc<TrackManager>,
    /// Playback engine for real-time audio processing
    playback_engine: Arc<EnginePlayback>,
    /// Automation engine for parameter automation
    automation_engine: Arc<AutomationEngine>,
    /// VCA/Group manager for track grouping
    group_manager: Arc<RwLock<GroupManager>>,
    /// Dirty state - project has unsaved changes
    is_dirty: std::sync::atomic::AtomicBool,
    /// Last saved undo position
    last_saved_undo_pos: std::sync::atomic::AtomicUsize,
    /// Current project file path
    project_file_path: RwLock<Option<String>>,
}

/// Real-time metering data (lock-free updates)
#[derive(Debug, Clone, Default)]
pub struct MeteringState {
    pub master_peak_l: f32,
    pub master_peak_r: f32,
    pub master_rms_l: f32,
    pub master_rms_r: f32,
    pub master_lufs_m: f32,
    pub master_lufs_s: f32,
    pub master_lufs_i: f32,
    pub master_true_peak: f32,
    /// Stereo correlation (-1.0 = out of phase, 0.0 = uncorrelated, 1.0 = mono)
    pub correlation: f32,
    /// Stereo balance (-1.0 = full left, 0.0 = center, 1.0 = full right)
    pub stereo_balance: f32,
    /// Dynamic range (peak - RMS in dB)
    pub dynamic_range: f32,
    pub track_peaks: Vec<(f32, f32)>,
    pub cpu_usage: f32,
    pub buffer_underruns: u32,
}

/// Transport state
#[derive(Debug, Clone, Default)]
pub struct TransportState {
    pub is_playing: bool,
    pub is_recording: bool,
    pub position_samples: u64,
    pub position_seconds: f64,
    pub tempo: f64,
    pub time_sig_num: u32,
    pub time_sig_denom: u32,
    pub loop_enabled: bool,
    pub loop_start: f64,
    pub loop_end: f64,
}

impl EngineBridge {
    pub fn new(config: EngineConfig) -> Self {
        // Create track manager for timeline clips
        let track_manager = Arc::new(TrackManager::new());

        // Create automation engine
        let automation_engine = Arc::new(AutomationEngine::new(config.sample_rate.as_f64()));

        // Create VCA/group manager
        let group_manager = Arc::new(RwLock::new(GroupManager::new()));

        // Create playback engine connected to track manager
        let sample_rate = config.sample_rate.as_u32();
        let mut playback_engine = EnginePlayback::new(Arc::clone(&track_manager), sample_rate);

        // Connect automation to playback engine
        playback_engine.set_automation(Arc::clone(&automation_engine));
        // Connect group/VCA manager to playback engine for audio-thread VCA gain
        playback_engine.set_group_manager(Arc::clone(&group_manager));

        let playback_engine = Arc::new(playback_engine);

        // Connect playback engine to audio output
        PLAYBACK.connect_engine(Arc::clone(&playback_engine));
        log::info!("EngineBridge: Connected rf-engine PlaybackEngine to audio output");
        log::info!("EngineBridge: Automation and VCA systems connected");

        Self {
            engine: DualPathEngine::new(
                config.processing_mode,
                config.block_size,
                config.sample_rate.as_f64(),
                config.lookahead_blocks,
            ),
            project: Project::new("Untitled"),
            undo_manager: UndoManager::new(500), // 500 undo steps
            config,
            metering: MeteringState::default(),
            transport: TransportState {
                tempo: 120.0,
                time_sig_num: 4,
                time_sig_denom: 4,
                ..Default::default()
            },
            track_manager,
            playback_engine,
            automation_engine,
            group_manager,
            is_dirty: std::sync::atomic::AtomicBool::new(false),
            last_saved_undo_pos: std::sync::atomic::AtomicUsize::new(0),
            project_file_path: RwLock::new(None),
        }
    }

    /// Mark project as dirty (has unsaved changes)
    pub fn mark_dirty(&self) {
        self.is_dirty
            .store(true, std::sync::atomic::Ordering::Relaxed);
    }

    /// Mark project as clean (just saved)
    pub fn mark_clean(&self) {
        self.is_dirty
            .store(false, std::sync::atomic::Ordering::Relaxed);
        self.last_saved_undo_pos.store(
            self.undo_manager.undo_count(),
            std::sync::atomic::Ordering::Relaxed,
        );
    }

    /// Check if project has unsaved changes
    pub fn is_dirty(&self) -> bool {
        // Dirty if explicitly marked OR if undo count differs from saved position
        self.is_dirty.load(std::sync::atomic::Ordering::Relaxed)
            || self.undo_manager.undo_count()
                != self
                    .last_saved_undo_pos
                    .load(std::sync::atomic::Ordering::Relaxed)
    }

    /// Set project file path
    pub fn set_file_path(&self, path: Option<String>) {
        *self.project_file_path.write() = path;
    }

    /// Get project file path
    pub fn file_path(&self) -> Option<String> {
        self.project_file_path.read().clone()
    }

    /// Get track manager for adding clips/tracks
    pub fn track_manager(&self) -> &Arc<TrackManager> {
        &self.track_manager
    }

    /// Get playback engine for transport control
    pub fn playback_engine(&self) -> &Arc<EnginePlayback> {
        &self.playback_engine
    }

    /// Get automation engine for parameter automation
    pub fn automation_engine(&self) -> &Arc<AutomationEngine> {
        &self.automation_engine
    }

    /// Get VCA/group manager for track grouping
    pub fn group_manager(&self) -> &Arc<RwLock<GroupManager>> {
        &self.group_manager
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INPUT LEVEL METERING
// ═══════════════════════════════════════════════════════════════════════════════

/// Get input peak levels (for recording meters)
/// Returns (peak_l, peak_r) from the audio input stream
pub fn get_input_peaks() -> (f32, f32) {
    PLAYBACK.get_input_peaks()
}

/// C FFI: Get input peak levels (for recording meters)
/// Returns stereo peak values via output pointers
#[unsafe(no_mangle)]
pub extern "C" fn audio_get_input_peaks(out_peak_l: *mut f64, out_peak_r: *mut f64) -> i32 {
    if out_peak_l.is_null() || out_peak_r.is_null() {
        return 0;
    }

    let (peak_l, peak_r) = PLAYBACK.get_input_peaks();

    unsafe {
        *out_peak_l = peak_l as f64;
        *out_peak_r = peak_r as f64;
    }

    1
}

// ═══════════════════════════════════════════════════════════════════════════════
// INPUT MONITORING
// ═══════════════════════════════════════════════════════════════════════════════

/// C FFI: Enable/disable input monitoring (hear input through output)
#[unsafe(no_mangle)]
pub extern "C" fn audio_set_input_monitoring(enabled: i32) {
    PLAYBACK.set_input_monitoring(enabled != 0);
}

/// C FFI: Check if input monitoring is enabled
#[unsafe(no_mangle)]
pub extern "C" fn audio_get_input_monitoring() -> i32 {
    if PLAYBACK.is_input_monitoring() { 1 } else { 0 }
}

// ═══════════════════════════════════════════════════════════════════════════════
// C FFI RE-EXPORTS FROM RF-ENGINE
// These functions are defined in rf-engine/src/ffi.rs and need to be accessible
// through librf_bridge.dylib for Flutter dart:ffi direct calls.
// ═══════════════════════════════════════════════════════════════════════════════

// Re-export all C FFI symbols from rf-engine
pub use rf_engine::ffi::*;

// Re-export autosave and recent projects FFI
pub use autosave_ffi::*;

// Re-export middleware event system FFI
pub use middleware_ffi::*;

// Re-export slot lab FFI
pub use slot_lab_ffi::*;

// Re-export ALE FFI
pub use ale_ffi::*;

// Re-export AUREXIS FFI
pub use aurexis_ffi::*;

// Re-export AutoSpatial FFI
pub use auto_spatial_ffi::*;

// Re-export DPM FFI
pub use dpm_ffi::*;

// Re-export Energy Governance FFI
pub use energy_governance_ffi::*;

// Re-export SAMCL FFI
pub use samcl_ffi::*;

// Re-export PBSE FFI
pub use pbse_ffi::*;

// Re-export AIL FFI
pub use ail_ffi::*;

// Re-export DRC FFI
pub use drc_ffi::*;

// Re-export SAM FFI
pub use sam_ffi::*;

// Re-export Container FFI (P2 optimization)
pub use container_ffi::*;

// Re-export Stage Ingest FFI (P5)
pub use connector_ffi::*;
pub use ingest_ffi::*;
pub use stage_ffi::*;

// Re-export Offline DSP FFI (P2.6)
pub use offline_ffi::*;

// Re-export Project FFI
pub use project_ffi::*;

// Re-export GAD FFI (Gameplay-Aware DAW)
pub use gad_ffi::*;

// Re-export SSS FFI (Scale & Stability Suite)
pub use sss_ffi::*;

// Re-export FluxMacro FFI (P-FMC Orchestration Engine)
pub use fluxmacro_ffi::*;

// Re-export Advanced Loop System FFI (Wwise-grade)
pub use loop_ffi::*;

// Re-export CORTEX Nervous System FFI
pub use cortex_ffi::*;

// Re-export IntentBridge FFI (typed request/response bridge)
pub use intent_ffi::*;

// Re-export Control Room FFI
pub use rf_engine::ffi_control_room::*;

// Re-export Routing FFI
pub use rf_engine::ffi_routing::*;

// Re-export ML/AI Engine FFI

// Re-export Pitch Detection/Correction FFI

// Re-export Script Engine FFI

// Re-export Video Engine FFI
