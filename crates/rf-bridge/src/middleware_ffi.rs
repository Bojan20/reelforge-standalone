//! FFI exports for FluxForge Middleware Event System
//!
//! Provides C-compatible functions for Flutter dart:ffi to control:
//! - Event posting and stopping
//! - State/Switch/RTPC management
//! - Event instance lifecycle
//!
//! Architecture:
//! - EventManager lives in audio thread (not directly accessible from FFI)
//! - FFI functions send commands through a separate command channel
//! - Registration data is stored in thread-safe global state

use once_cell::sync::Lazy;
use parking_lot::{Mutex, RwLock};
use rtrb::{Producer, RingBuffer};
use std::collections::HashMap;
use std::ffi::{c_char, CStr};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use rf_event::{
    ActionPriority, ActionScope, ActionType, EventCommand, FadeCurve, MiddlewareAction,
    MiddlewareEvent, RtpcDefinition, StateGroup, SwitchGroup,
    // Advanced features
    DuckingRule, DuckingCurve, DuckingMatrix,
    BlendChild, BlendContainer, CrossfadeCurve,
    RandomChild, RandomContainer, RandomMode,
    SequenceStep, SequenceContainer, SequenceEndBehavior,
    Stinger, MusicSegment, MusicSystem, MusicSyncPoint, MarkerType,
    AttenuationCurve, AttenuationType, AttenuationSystem,
    RtpcCurveShape,
};
use rf_event::event::MaxInstanceBehavior;

// ═══════════════════════════════════════════════════════════════════════════════
// GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Command queue capacity
const COMMAND_QUEUE_CAPACITY: usize = 4096;

/// Initialization flag
static INITIALIZED: AtomicBool = AtomicBool::new(false);

/// Playing ID counter
static NEXT_PLAYING_ID: AtomicU64 = AtomicU64::new(1);

/// Command producer for sending to audio thread
static COMMAND_TX: Lazy<Mutex<Option<Producer<EventCommand>>>> =
    Lazy::new(|| Mutex::new(None));

/// Registered events (for lookup and registration)
static EVENTS: Lazy<RwLock<HashMap<u32, MiddlewareEvent>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Event name to ID mapping
static EVENT_NAMES: Lazy<RwLock<HashMap<String, u32>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// State groups
static STATE_GROUPS: Lazy<RwLock<HashMap<u32, StateGroup>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Switch groups
static SWITCH_GROUPS: Lazy<RwLock<HashMap<u32, SwitchGroup>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// RTPC definitions
static RTPC_DEFS: Lazy<RwLock<HashMap<u32, RtpcDefinition>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Current state values (for query)
static CURRENT_STATES: Lazy<RwLock<HashMap<u32, u32>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Current RTPC values (for query)
static CURRENT_RTPCS: Lazy<RwLock<HashMap<u32, f32>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Active instance count
static ACTIVE_INSTANCES: AtomicU64 = AtomicU64::new(0);

/// Test synchronization mutex - ensures only one test accesses global state at a time
/// This is the ONLY correct way to test code with global mutable state in Rust
#[cfg(test)]
static TEST_MUTEX: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

// ═══════════════════════════════════════════════════════════════════════════════
// ADVANCED FEATURE GLOBAL STATE
// ═══════════════════════════════════════════════════════════════════════════════

/// Ducking matrix
static DUCKING_MATRIX: Lazy<RwLock<DuckingMatrix>> =
    Lazy::new(|| RwLock::new(DuckingMatrix::new()));

/// Blend containers
static BLEND_CONTAINERS: Lazy<RwLock<HashMap<u32, BlendContainer>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Random containers
static RANDOM_CONTAINERS: Lazy<RwLock<HashMap<u32, RandomContainer>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Sequence containers
static SEQUENCE_CONTAINERS: Lazy<RwLock<HashMap<u32, SequenceContainer>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

/// Music system
static MUSIC_SYSTEM: Lazy<RwLock<MusicSystem>> =
    Lazy::new(|| RwLock::new(MusicSystem::new()));

/// Attenuation system
static ATTENUATION_SYSTEM: Lazy<RwLock<AttenuationSystem>> =
    Lazy::new(|| RwLock::new(AttenuationSystem::new()));

// ═══════════════════════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Initialize the middleware event system
///
/// Creates a command ring buffer. The consumer should be passed to the
/// audio thread's EventManager.
///
/// Returns a pointer to the consumer that should be given to the audio thread.
/// Returns null if already initialized.
#[unsafe(no_mangle)]
pub extern "C" fn middleware_init() -> *mut std::ffi::c_void {
    if INITIALIZED.swap(true, Ordering::SeqCst) {
        log::warn!("middleware_init: Already initialized");
        return std::ptr::null_mut();
    }

    let (tx, rx) = RingBuffer::new(COMMAND_QUEUE_CAPACITY);

    *COMMAND_TX.lock() = Some(tx);

    // Box and leak the consumer so audio thread can own it
    let consumer = Box::new(rx);
    let ptr = Box::into_raw(consumer) as *mut std::ffi::c_void;

    log::info!("middleware_init: Event system initialized, consumer ptr={:?}", ptr);
    ptr
}

/// Shutdown the middleware event system
#[unsafe(no_mangle)]
pub extern "C" fn middleware_shutdown() {
    if !INITIALIZED.swap(false, Ordering::SeqCst) {
        log::warn!("middleware_shutdown: Not initialized");
        return;
    }

    // Clear command producer
    *COMMAND_TX.lock() = None;

    // Clear all registrations
    EVENTS.write().clear();
    EVENT_NAMES.write().clear();
    STATE_GROUPS.write().clear();
    SWITCH_GROUPS.write().clear();
    RTPC_DEFS.write().clear();
    CURRENT_STATES.write().clear();
    CURRENT_RTPCS.write().clear();

    log::info!("middleware_shutdown: Event system shut down");
}

/// Check if middleware is initialized
#[unsafe(no_mangle)]
pub extern "C" fn middleware_is_initialized() -> i32 {
    if INITIALIZED.load(Ordering::Relaxed) { 1 } else { 0 }
}

/// Full reset of ALL global state - used for testing
/// Unlike middleware_shutdown(), this resets EVERYTHING including:
/// - Advanced features (ducking, containers, music system, attenuation)
/// - Atomic counters
/// - Does NOT require INITIALIZED flag to be set
#[cfg(test)]
fn full_reset_for_testing() {
    // Force uninitialize
    INITIALIZED.store(false, Ordering::SeqCst);

    // Reset atomic counters
    NEXT_PLAYING_ID.store(1, Ordering::SeqCst);
    ACTIVE_INSTANCES.store(0, Ordering::SeqCst);

    // Clear command producer
    *COMMAND_TX.lock() = None;

    // Clear core registrations
    EVENTS.write().clear();
    EVENT_NAMES.write().clear();
    STATE_GROUPS.write().clear();
    SWITCH_GROUPS.write().clear();
    RTPC_DEFS.write().clear();
    CURRENT_STATES.write().clear();
    CURRENT_RTPCS.write().clear();

    // Clear advanced features
    *DUCKING_MATRIX.write() = DuckingMatrix::new();
    BLEND_CONTAINERS.write().clear();
    RANDOM_CONTAINERS.write().clear();
    SEQUENCE_CONTAINERS.write().clear();
    *MUSIC_SYSTEM.write() = MusicSystem::new();
    *ATTENUATION_SYSTEM.write() = AttenuationSystem::new();
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER: Push command
// ═══════════════════════════════════════════════════════════════════════════════

fn push_command(cmd: EventCommand) -> bool {
    if let Some(ref mut tx) = *COMMAND_TX.lock() {
        tx.push(cmd).is_ok()
    } else {
        false
    }
}

fn generate_playing_id() -> u64 {
    NEXT_PLAYING_ID.fetch_add(1, Ordering::Relaxed)
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT REGISTRATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Register a new event
#[unsafe(no_mangle)]
pub extern "C" fn middleware_register_event(
    event_id: u32,
    name: *const c_char,
    category: *const c_char,
    max_instances: u32,
) -> i32 {
    if name.is_null() || category.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("Unknown");
    let category_str = unsafe { CStr::from_ptr(category) }
        .to_str()
        .unwrap_or("Default");

    let event = MiddlewareEvent::new(event_id, name_str)
        .with_category(category_str)
        .with_max_instances(max_instances, MaxInstanceBehavior::DiscardOldest);

    EVENT_NAMES.write().insert(name_str.to_string(), event_id);
    EVENTS.write().insert(event_id, event);

    log::debug!("middleware_register_event: {} '{}'", event_id, name_str);
    1
}

/// Add an action to a registered event
#[unsafe(no_mangle)]
pub extern "C" fn middleware_add_action(
    event_id: u32,
    action_type: u32,
    asset_id: u32,
    bus_id: u32,
    scope: u32,
    priority: u32,
    fade_curve: u32,
    fade_time_ms: u32,
    delay_ms: u32,
) -> i32 {
    let action_type = match action_type {
        0 => ActionType::Play,
        1 => ActionType::PlayAndContinue,
        2 => ActionType::Stop,
        3 => ActionType::StopAll,
        4 => ActionType::Pause,
        5 => ActionType::PauseAll,
        6 => ActionType::Resume,
        7 => ActionType::ResumeAll,
        8 => ActionType::Break,
        9 => ActionType::Mute,
        10 => ActionType::Unmute,
        11 => ActionType::SetVolume,
        12 => ActionType::SetPitch,
        13 => ActionType::SetLPF,
        14 => ActionType::SetHPF,
        15 => ActionType::SetBusVolume,
        16 => ActionType::SetState,
        17 => ActionType::SetSwitch,
        18 => ActionType::SetRTPC,
        19 => ActionType::ResetRTPC,
        20 => ActionType::Seek,
        21 => ActionType::Trigger,
        22 => ActionType::PostEvent,
        _ => {
            log::error!("middleware_add_action: Invalid action type {}", action_type);
            return 0;
        }
    };

    let scope = ActionScope::from_index(scope as u8);
    let priority = ActionPriority::from_index(priority as u8);
    let fade_curve = FadeCurve::from_index(fade_curve as u8);

    let action = MiddlewareAction {
        id: 0, // Will be assigned
        action_type,
        asset_id: if asset_id > 0 { Some(asset_id) } else { None },
        bus_id,
        scope,
        priority,
        fade_curve,
        fade_time_secs: fade_time_ms as f32 / 1000.0,
        gain: 1.0,
        delay_secs: delay_ms as f32 / 1000.0,
        loop_playback: false,
        group_id: None,
        value_id: None,
        rtpc_id: None,
        rtpc_value: None,
        rtpc_interpolation_secs: None,
        seek_position_secs: None,
        seek_to_percent: false,
        target_event_id: None,
        pitch_semitones: None,
        filter_freq_hz: None,
        // State/Switch/RTPC conditions (default: no conditions)
        require_state_group: None,
        require_state_id: None,
        require_state_inverted: false,
        require_switch_group: None,
        require_switch_id: None,
        require_rtpc_id: None,
        require_rtpc_min: None,
        require_rtpc_max: None,
    };

    let mut events = EVENTS.write();
    if let Some(event) = events.get_mut(&event_id) {
        event.add_action_auto(action);
        log::debug!("middleware_add_action: Added {:?} to event {}", action_type, event_id);
        1
    } else {
        log::error!("middleware_add_action: Event {} not found", event_id);
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT POSTING
// ═══════════════════════════════════════════════════════════════════════════════

/// Post an event on a game object
#[unsafe(no_mangle)]
pub extern "C" fn middleware_post_event(event_id: u32, game_object_id: u64) -> u64 {
    if !INITIALIZED.load(Ordering::Relaxed) {
        return 0;
    }

    let playing_id = generate_playing_id();

    let success = push_command(EventCommand::PostEvent {
        event_id,
        game_object: game_object_id,
        playing_id,
        callback_id: None,
        user_data: 0,
    });

    if success {
        log::debug!("middleware_post_event: {} on object {}", event_id, game_object_id);
        playing_id
    } else {
        0
    }
}

/// Post an event by name
#[unsafe(no_mangle)]
pub extern "C" fn middleware_post_event_by_name(
    event_name: *const c_char,
    game_object_id: u64,
) -> u64 {
    if event_name.is_null() {
        return 0;
    }

    let name = unsafe { CStr::from_ptr(event_name) }
        .to_str()
        .unwrap_or("");

    let event_id = EVENT_NAMES.read().get(name).copied();

    match event_id {
        Some(id) => middleware_post_event(id, game_object_id),
        None => {
            log::error!("middleware_post_event_by_name: Event '{}' not found", name);
            0
        }
    }
}

/// Stop a playing event instance
#[unsafe(no_mangle)]
pub extern "C" fn middleware_stop_playing_id(playing_id: u64, fade_ms: u32) -> i32 {
    if push_command(EventCommand::StopPlayingId {
        playing_id,
        fade_ms,
    }) {
        1
    } else {
        0
    }
}

/// Stop all instances of an event
#[unsafe(no_mangle)]
pub extern "C" fn middleware_stop_event(event_id: u32, game_object_id: u64, fade_ms: u32) {
    let game_object = if game_object_id == 0 { None } else { Some(game_object_id) };

    push_command(EventCommand::StopEvent {
        event_id,
        game_object,
        fade_ms,
    });
}

/// Stop all playing events
#[unsafe(no_mangle)]
pub extern "C" fn middleware_stop_all(fade_ms: u32) {
    push_command(EventCommand::StopAll {
        game_object: None,
        fade_ms,
    });
}

// ═══════════════════════════════════════════════════════════════════════════════
// STATE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Register a state group
#[unsafe(no_mangle)]
pub extern "C" fn middleware_register_state_group(
    group_id: u32,
    name: *const c_char,
    default_state: u32,
) -> i32 {
    if name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("Unknown");

    let mut group = StateGroup::new(group_id, name_str);
    group.default_state = default_state;
    group.current_state = default_state;

    STATE_GROUPS.write().insert(group_id, group);
    CURRENT_STATES.write().insert(group_id, default_state);

    log::debug!("middleware_register_state_group: {} '{}'", group_id, name_str);
    1
}

/// Add a state to a state group
#[unsafe(no_mangle)]
pub extern "C" fn middleware_add_state(
    group_id: u32,
    state_id: u32,
    state_name: *const c_char,
) -> i32 {
    if state_name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(state_name) }
        .to_str()
        .unwrap_or("Unknown");

    let mut groups = STATE_GROUPS.write();
    if let Some(group) = groups.get_mut(&group_id) {
        group.add_state(state_id, name_str);
        1
    } else {
        0
    }
}

/// Set the current state
#[unsafe(no_mangle)]
pub extern "C" fn middleware_set_state(group_id: u32, state_id: u32) -> i32 {
    // Update local tracking
    CURRENT_STATES.write().insert(group_id, state_id);

    // Send command to audio thread
    if push_command(EventCommand::SetState { group_id, state_id }) {
        log::debug!("middleware_set_state: group {} = state {}", group_id, state_id);
        1
    } else {
        0
    }
}

/// Get current state
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_state(group_id: u32) -> u32 {
    CURRENT_STATES.read().get(&group_id).copied().unwrap_or(0)
}

// ═══════════════════════════════════════════════════════════════════════════════
// SWITCH MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Register a switch group
#[unsafe(no_mangle)]
pub extern "C" fn middleware_register_switch_group(group_id: u32, name: *const c_char) -> i32 {
    if name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("Unknown");

    let group = SwitchGroup::new(group_id, name_str);
    SWITCH_GROUPS.write().insert(group_id, group);

    log::debug!("middleware_register_switch_group: {} '{}'", group_id, name_str);
    1
}

/// Add a switch to a switch group
#[unsafe(no_mangle)]
pub extern "C" fn middleware_add_switch(
    group_id: u32,
    switch_id: u32,
    switch_name: *const c_char,
) -> i32 {
    if switch_name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(switch_name) }
        .to_str()
        .unwrap_or("Unknown");

    let mut groups = SWITCH_GROUPS.write();
    if let Some(group) = groups.get_mut(&group_id) {
        group.add_switch(switch_id, name_str);
        1
    } else {
        0
    }
}

/// Set a switch value on a game object
#[unsafe(no_mangle)]
pub extern "C" fn middleware_set_switch(
    game_object_id: u64,
    group_id: u32,
    switch_id: u32,
) -> i32 {
    if push_command(EventCommand::SetSwitch {
        game_object: game_object_id,
        group_id,
        switch_id,
    }) {
        1
    } else {
        0
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RTPC MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Register an RTPC parameter
#[unsafe(no_mangle)]
pub extern "C" fn middleware_register_rtpc(
    rtpc_id: u32,
    name: *const c_char,
    min_value: f32,
    max_value: f32,
    default_value: f32,
) -> i32 {
    if name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("Unknown");

    let rtpc = RtpcDefinition::new(rtpc_id, name_str)
        .with_range(min_value, max_value)
        .with_default(default_value);

    RTPC_DEFS.write().insert(rtpc_id, rtpc);
    CURRENT_RTPCS.write().insert(rtpc_id, default_value);

    log::debug!("middleware_register_rtpc: {} '{}' [{}, {}]", rtpc_id, name_str, min_value, max_value);
    1
}

/// Set RTPC value globally
#[unsafe(no_mangle)]
pub extern "C" fn middleware_set_rtpc(rtpc_id: u32, value: f32, interpolation_ms: u32) -> i32 {
    // Update local tracking
    CURRENT_RTPCS.write().insert(rtpc_id, value);

    // Send command
    if push_command(EventCommand::SetRtpc {
        rtpc_id,
        value,
        game_object: None,
        interpolation_ms,
    }) {
        1
    } else {
        0
    }
}

/// Set RTPC value on specific game object
#[unsafe(no_mangle)]
pub extern "C" fn middleware_set_rtpc_on_object(
    game_object_id: u64,
    rtpc_id: u32,
    value: f32,
    interpolation_ms: u32,
) -> i32 {
    if push_command(EventCommand::SetRtpc {
        rtpc_id,
        value,
        game_object: Some(game_object_id),
        interpolation_ms,
    }) {
        1
    } else {
        0
    }
}

/// Get current RTPC value
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_rtpc(rtpc_id: u32) -> f32 {
    CURRENT_RTPCS.read().get(&rtpc_id).copied().unwrap_or(0.0)
}

/// Reset RTPC to default value
#[unsafe(no_mangle)]
pub extern "C" fn middleware_reset_rtpc(rtpc_id: u32, interpolation_ms: u32) -> i32 {
    let default = RTPC_DEFS.read()
        .get(&rtpc_id)
        .map(|r| r.default)
        .unwrap_or(0.0);

    middleware_set_rtpc(rtpc_id, default, interpolation_ms)
}

// ═══════════════════════════════════════════════════════════════════════════════
// GAME OBJECT MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

/// Register a game object (optional, for debugging)
#[unsafe(no_mangle)]
pub extern "C" fn middleware_register_game_object(
    game_object_id: u64,
    name: *const c_char,
) -> i32 {
    let name_str = if name.is_null() {
        "Unnamed"
    } else {
        unsafe { CStr::from_ptr(name) }.to_str().unwrap_or("Unnamed")
    };

    log::debug!("middleware_register_game_object: {} '{}'", game_object_id, name_str);
    1
}

/// Unregister a game object and stop all its events
#[unsafe(no_mangle)]
pub extern "C" fn middleware_unregister_game_object(game_object_id: u64) {
    // Stop all events on this object with quick fade
    push_command(EventCommand::StopAll {
        game_object: Some(game_object_id),
        fade_ms: 50,
    });

    log::debug!("middleware_unregister_game_object: {}", game_object_id);
}

// ═══════════════════════════════════════════════════════════════════════════════
// QUERY FUNCTIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Get number of registered events
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_event_count() -> u32 {
    EVENTS.read().len() as u32
}

/// Get number of registered state groups
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_state_group_count() -> u32 {
    STATE_GROUPS.read().len() as u32
}

/// Get number of registered switch groups
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_switch_group_count() -> u32 {
    SWITCH_GROUPS.read().len() as u32
}

/// Get number of registered RTPCs
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_rtpc_count() -> u32 {
    RTPC_DEFS.read().len() as u32
}

/// Update active instance count (called from audio thread)
#[unsafe(no_mangle)]
pub extern "C" fn middleware_set_active_instance_count(count: u32) {
    ACTIVE_INSTANCES.store(count as u64, Ordering::Relaxed);
}

/// Get active instance count
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_active_instance_count() -> u32 {
    ACTIVE_INSTANCES.load(Ordering::Relaxed) as u32
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT DATA ACCESS (for audio thread integration)
// ═══════════════════════════════════════════════════════════════════════════════

/// Get a registered event by ID (for audio thread to clone into EventManager)
///
/// Returns null if not found. Caller must free with middleware_free_event.
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_event_data(event_id: u32) -> *mut MiddlewareEvent {
    let events = EVENTS.read();
    if let Some(event) = events.get(&event_id) {
        let boxed = Box::new(event.clone());
        Box::into_raw(boxed)
    } else {
        std::ptr::null_mut()
    }
}

/// Free an event obtained from middleware_get_event_data
#[unsafe(no_mangle)]
pub extern "C" fn middleware_free_event(event: *mut MiddlewareEvent) {
    if !event.is_null() {
        unsafe { drop(Box::from_raw(event)) };
    }
}

/// Get all registered event IDs
///
/// Fills the provided buffer with event IDs. Returns number of events.
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_all_event_ids(buffer: *mut u32, buffer_size: u32) -> u32 {
    if buffer.is_null() {
        return EVENTS.read().len() as u32;
    }

    let events = EVENTS.read();
    let count = events.len().min(buffer_size as usize);

    for (i, id) in events.keys().take(count).enumerate() {
        unsafe { *buffer.add(i) = *id };
    }

    count as u32
}

// ═══════════════════════════════════════════════════════════════════════════════
// DUCKING MATRIX
// ═══════════════════════════════════════════════════════════════════════════════

/// Add a ducking rule
#[unsafe(no_mangle)]
pub extern "C" fn middleware_add_ducking_rule(
    rule_id: u32,
    source_bus_name: *const c_char,
    source_bus_id: u32,
    target_bus_name: *const c_char,
    target_bus_id: u32,
    duck_amount_db: f32,
    attack_ms: f32,
    release_ms: f32,
    threshold: f32,
    curve: u32,
) -> i32 {
    if source_bus_name.is_null() || target_bus_name.is_null() {
        return 0;
    }

    let source_name = unsafe { CStr::from_ptr(source_bus_name) }
        .to_str()
        .unwrap_or("Unknown");
    let target_name = unsafe { CStr::from_ptr(target_bus_name) }
        .to_str()
        .unwrap_or("Unknown");

    let curve_type = match curve {
        0 => DuckingCurve::Linear,
        1 => DuckingCurve::Exponential,
        2 => DuckingCurve::Logarithmic,
        3 => DuckingCurve::SCurve,
        _ => DuckingCurve::Linear,
    };

    let rule = DuckingRule::new(rule_id, source_name, target_name)
        .with_bus_ids(source_bus_id, target_bus_id)
        .with_duck_amount(duck_amount_db)
        .with_attack_ms(attack_ms)
        .with_release_ms(release_ms)
        .with_threshold(threshold)
        .with_curve(curve_type);

    DUCKING_MATRIX.write().add_rule(rule);
    log::debug!("middleware_add_ducking_rule: {} ({} → {})", rule_id, source_name, target_name);
    1
}

/// Remove a ducking rule
#[unsafe(no_mangle)]
pub extern "C" fn middleware_remove_ducking_rule(rule_id: u32) -> i32 {
    DUCKING_MATRIX.write().remove_rule(rule_id);
    1
}

/// Enable/disable a ducking rule
#[unsafe(no_mangle)]
pub extern "C" fn middleware_set_ducking_rule_enabled(rule_id: u32, enabled: i32) -> i32 {
    let mut matrix = DUCKING_MATRIX.write();
    if let Some(rule) = matrix.get_rule_mut(rule_id) {
        rule.enabled = enabled != 0;
        1
    } else {
        0
    }
}

/// Get ducking rule count
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_ducking_rule_count() -> u32 {
    DUCKING_MATRIX.read().rules.len() as u32
}

/// Clear all ducking rules
#[unsafe(no_mangle)]
pub extern "C" fn middleware_clear_ducking_rules() {
    DUCKING_MATRIX.write().rules.clear();
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLEND CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a blend container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_create_blend_container(
    container_id: u32,
    name: *const c_char,
    rtpc_id: u32,
    crossfade_curve: u32,
) -> i32 {
    if name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("Unknown");

    let curve = match crossfade_curve {
        0 => CrossfadeCurve::Linear,
        1 => CrossfadeCurve::EqualPower,
        2 => CrossfadeCurve::SCurve,
        3 => CrossfadeCurve::SinCos,
        _ => CrossfadeCurve::EqualPower,
    };

    let container = BlendContainer::new(container_id, name_str, rtpc_id)
        .with_crossfade_curve(curve);

    BLEND_CONTAINERS.write().insert(container_id, container);
    log::debug!("middleware_create_blend_container: {} '{}' (RTPC={})", container_id, name_str, rtpc_id);
    1
}

/// Add child to blend container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_blend_add_child(
    container_id: u32,
    child_id: u32,
    child_name: *const c_char,
    rtpc_start: f32,
    rtpc_end: f32,
    crossfade_width: f32,
) -> i32 {
    if child_name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(child_name) }
        .to_str()
        .unwrap_or("Unknown");

    let child = BlendChild::new(child_id, name_str, rtpc_start, rtpc_end)
        .with_crossfade(crossfade_width);

    let mut containers = BLEND_CONTAINERS.write();
    if let Some(container) = containers.get_mut(&container_id) {
        container.add_child(child);
        1
    } else {
        0
    }
}

/// Remove child from blend container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_blend_remove_child(container_id: u32, child_id: u32) -> i32 {
    let mut containers = BLEND_CONTAINERS.write();
    if let Some(container) = containers.get_mut(&container_id) {
        container.remove_child(child_id);
        1
    } else {
        0
    }
}

/// Remove blend container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_remove_blend_container(container_id: u32) -> i32 {
    if BLEND_CONTAINERS.write().remove(&container_id).is_some() { 1 } else { 0 }
}

/// Get blend container count
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_blend_container_count() -> u32 {
    BLEND_CONTAINERS.read().len() as u32
}

// ═══════════════════════════════════════════════════════════════════════════════
// RANDOM CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a random container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_create_random_container(
    container_id: u32,
    name: *const c_char,
    mode: u32,
    avoid_repeat_count: u32,
) -> i32 {
    if name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("Unknown");

    let random_mode = match mode {
        0 => RandomMode::Random,
        1 => RandomMode::Shuffle,
        2 => RandomMode::ShuffleWithHistory,
        3 => RandomMode::RoundRobin,
        _ => RandomMode::Random,
    };

    let mut container = RandomContainer::new(container_id, name_str);
    container.mode = random_mode;
    container.avoid_repeat_count = avoid_repeat_count;

    RANDOM_CONTAINERS.write().insert(container_id, container);
    log::debug!("middleware_create_random_container: {} '{}'", container_id, name_str);
    1
}

/// Add child to random container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_random_add_child(
    container_id: u32,
    child_id: u32,
    child_name: *const c_char,
    weight: f32,
    pitch_min: f32,
    pitch_max: f32,
    volume_min: f32,
    volume_max: f32,
) -> i32 {
    if child_name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(child_name) }
        .to_str()
        .unwrap_or("Unknown");

    let child = RandomChild::new(child_id, name_str)
        .with_weight(weight)
        .with_pitch_variation(pitch_min, pitch_max)
        .with_volume_variation(volume_min, volume_max);

    let mut containers = RANDOM_CONTAINERS.write();
    if let Some(container) = containers.get_mut(&container_id) {
        container.add_child(child);
        1
    } else {
        0
    }
}

/// Remove child from random container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_random_remove_child(container_id: u32, child_id: u32) -> i32 {
    let mut containers = RANDOM_CONTAINERS.write();
    if let Some(container) = containers.get_mut(&container_id) {
        container.remove_child(child_id);
        1
    } else {
        0
    }
}

/// Set global variation for random container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_random_set_global_variation(
    container_id: u32,
    pitch_min: f32,
    pitch_max: f32,
    volume_min: f32,
    volume_max: f32,
) -> i32 {
    let mut containers = RANDOM_CONTAINERS.write();
    if let Some(container) = containers.get_mut(&container_id) {
        container.global_pitch_min = pitch_min;
        container.global_pitch_max = pitch_max;
        container.global_volume_min = volume_min;
        container.global_volume_max = volume_max;
        1
    } else {
        0
    }
}

/// Remove random container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_remove_random_container(container_id: u32) -> i32 {
    if RANDOM_CONTAINERS.write().remove(&container_id).is_some() { 1 } else { 0 }
}

/// Get random container count
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_random_container_count() -> u32 {
    RANDOM_CONTAINERS.read().len() as u32
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEQUENCE CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a sequence container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_create_sequence_container(
    container_id: u32,
    name: *const c_char,
    end_behavior: u32,
    speed: f32,
) -> i32 {
    if name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("Unknown");

    let behavior = match end_behavior {
        0 => SequenceEndBehavior::Stop,
        1 => SequenceEndBehavior::Loop,
        2 => SequenceEndBehavior::HoldLast,
        3 => SequenceEndBehavior::PingPong,
        _ => SequenceEndBehavior::Stop,
    };

    let container = SequenceContainer::new(container_id, name_str)
        .with_end_behavior(behavior)
        .with_speed(speed);

    SEQUENCE_CONTAINERS.write().insert(container_id, container);
    log::debug!("middleware_create_sequence_container: {} '{}'", container_id, name_str);
    1
}

/// Add step to sequence container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_sequence_add_step(
    container_id: u32,
    step_index: u32,
    child_id: u32,
    child_name: *const c_char,
    delay_ms: f32,
    duration_ms: f32,
    fade_in_ms: f32,
    fade_out_ms: f32,
    loop_count: u32,
) -> i32 {
    if child_name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(child_name) }
        .to_str()
        .unwrap_or("Unknown");

    let step = SequenceStep::new(step_index, child_id, name_str)
        .with_delay(delay_ms / 1000.0)
        .with_duration(duration_ms / 1000.0)
        .with_fades(fade_in_ms / 1000.0, fade_out_ms / 1000.0)
        .with_loop(loop_count);

    let mut containers = SEQUENCE_CONTAINERS.write();
    if let Some(container) = containers.get_mut(&container_id) {
        container.add_step(step);
        1
    } else {
        0
    }
}

/// Remove step from sequence container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_sequence_remove_step(container_id: u32, step_index: u32) -> i32 {
    let mut containers = SEQUENCE_CONTAINERS.write();
    if let Some(container) = containers.get_mut(&container_id) {
        container.remove_step(step_index);
        1
    } else {
        0
    }
}

/// Remove sequence container
#[unsafe(no_mangle)]
pub extern "C" fn middleware_remove_sequence_container(container_id: u32) -> i32 {
    if SEQUENCE_CONTAINERS.write().remove(&container_id).is_some() { 1 } else { 0 }
}

/// Get sequence container count
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_sequence_container_count() -> u32 {
    SEQUENCE_CONTAINERS.read().len() as u32
}

// ═══════════════════════════════════════════════════════════════════════════════
// MUSIC SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

/// Add music segment
#[unsafe(no_mangle)]
pub extern "C" fn middleware_add_music_segment(
    segment_id: u32,
    name: *const c_char,
    sound_id: u32,
    tempo: f32,
    beats_per_bar: u32,
    duration_bars: u32,
) -> i32 {
    if name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("Unknown");

    let segment = MusicSegment::new(segment_id, name_str, sound_id)
        .with_tempo(tempo)
        .with_time_signature(beats_per_bar)
        .with_duration(duration_bars);

    MUSIC_SYSTEM.write().add_segment(segment);
    log::debug!("middleware_add_music_segment: {} '{}' ({}BPM)", segment_id, name_str, tempo);
    1
}

/// Add marker to music segment
#[unsafe(no_mangle)]
pub extern "C" fn middleware_music_segment_add_marker(
    segment_id: u32,
    marker_name: *const c_char,
    position_bars: f32,
    marker_type: u32,
) -> i32 {
    if marker_name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(marker_name) }
        .to_str()
        .unwrap_or("Unknown");

    let m_type = match marker_type {
        0 => MarkerType::Generic,
        1 => MarkerType::Entry,
        2 => MarkerType::Exit,
        3 => MarkerType::Sync,
        _ => MarkerType::Generic,
    };

    let mut system = MUSIC_SYSTEM.write();
    if let Some(segment) = system.segments.iter_mut().find(|s| s.id == segment_id) {
        segment.add_marker(name_str, position_bars, m_type);
        1
    } else {
        0
    }
}

/// Remove music segment
#[unsafe(no_mangle)]
pub extern "C" fn middleware_remove_music_segment(segment_id: u32) -> i32 {
    MUSIC_SYSTEM.write().remove_segment(segment_id);
    1
}

/// Add stinger
#[unsafe(no_mangle)]
pub extern "C" fn middleware_add_stinger(
    stinger_id: u32,
    name: *const c_char,
    sound_id: u32,
    sync_point: u32,
    custom_grid_beats: f32,
    music_duck_db: f32,
    duck_attack_ms: f32,
    duck_release_ms: f32,
    priority: u32,
    can_interrupt: i32,
) -> i32 {
    if name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("Unknown");

    let sync = match sync_point {
        0 => MusicSyncPoint::Immediate,
        1 => MusicSyncPoint::Beat,
        2 => MusicSyncPoint::Bar,
        3 => MusicSyncPoint::Marker,
        4 => MusicSyncPoint::CustomGrid,
        5 => MusicSyncPoint::SegmentEnd,
        _ => MusicSyncPoint::Beat,
    };

    let mut stinger = Stinger::new(stinger_id, name_str, sound_id)
        .with_sync_point(sync)
        .with_music_duck(music_duck_db, duck_attack_ms, duck_release_ms)
        .with_priority(priority)
        .with_interrupt(can_interrupt != 0);

    if sync == MusicSyncPoint::CustomGrid {
        stinger = stinger.with_custom_grid(custom_grid_beats);
    }

    MUSIC_SYSTEM.write().add_stinger(stinger);
    log::debug!("middleware_add_stinger: {} '{}'", stinger_id, name_str);
    1
}

/// Remove stinger
#[unsafe(no_mangle)]
pub extern "C" fn middleware_remove_stinger(stinger_id: u32) -> i32 {
    MUSIC_SYSTEM.write().remove_stinger(stinger_id);
    1
}

/// Set current music segment
#[unsafe(no_mangle)]
pub extern "C" fn middleware_set_music_segment(segment_id: u32) -> i32 {
    MUSIC_SYSTEM.write().set_current_segment(segment_id);
    1
}

/// Queue next music segment
#[unsafe(no_mangle)]
pub extern "C" fn middleware_queue_music_segment(segment_id: u32) -> i32 {
    MUSIC_SYSTEM.write().queue_next_segment(segment_id);
    1
}

/// Set music bus ID
#[unsafe(no_mangle)]
pub extern "C" fn middleware_set_music_bus(bus_id: u32) {
    MUSIC_SYSTEM.write().music_bus_id = bus_id;
}

/// Get music segment count
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_music_segment_count() -> u32 {
    MUSIC_SYSTEM.read().segments.len() as u32
}

/// Get stinger count
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_stinger_count() -> u32 {
    MUSIC_SYSTEM.read().stingers.len() as u32
}

// ═══════════════════════════════════════════════════════════════════════════════
// ATTENUATION SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

/// Add attenuation curve
#[unsafe(no_mangle)]
pub extern "C" fn middleware_add_attenuation_curve(
    curve_id: u32,
    name: *const c_char,
    attenuation_type: u32,
    input_min: f32,
    input_max: f32,
    output_min: f32,
    output_max: f32,
    curve_shape: u32,
) -> i32 {
    if name.is_null() {
        return 0;
    }

    let name_str = unsafe { CStr::from_ptr(name) }
        .to_str()
        .unwrap_or("Unknown");

    let atten_type = match attenuation_type {
        0 => AttenuationType::WinAmount,
        1 => AttenuationType::NearWin,
        2 => AttenuationType::ComboMultiplier,
        3 => AttenuationType::FeatureProgress,
        4 => AttenuationType::TimeElapsed,
        _ => AttenuationType::WinAmount,
    };

    let shape = match curve_shape {
        0 => RtpcCurveShape::Linear,
        1 => RtpcCurveShape::Log3,
        2 => RtpcCurveShape::Sine,
        3 => RtpcCurveShape::Log1,
        4 => RtpcCurveShape::InvSCurve,
        5 => RtpcCurveShape::SCurve,
        6 => RtpcCurveShape::Exp1,
        7 => RtpcCurveShape::Exp3,
        8 => RtpcCurveShape::Constant,
        _ => RtpcCurveShape::Linear,
    };

    let curve = AttenuationCurve::new(curve_id, name_str, atten_type)
        .with_input_range(input_min, input_max)
        .with_output_range(output_min, output_max)
        .with_curve_shape(shape);

    ATTENUATION_SYSTEM.write().add_curve(curve);
    log::debug!("middleware_add_attenuation_curve: {} '{}'", curve_id, name_str);
    1
}

/// Remove attenuation curve
#[unsafe(no_mangle)]
pub extern "C" fn middleware_remove_attenuation_curve(curve_id: u32) -> i32 {
    ATTENUATION_SYSTEM.write().remove_curve(curve_id);
    1
}

/// Enable/disable attenuation curve
#[unsafe(no_mangle)]
pub extern "C" fn middleware_set_attenuation_curve_enabled(curve_id: u32, enabled: i32) -> i32 {
    let mut system = ATTENUATION_SYSTEM.write();
    if let Some(curve) = system.curves.iter_mut().find(|c| c.id == curve_id) {
        curve.enabled = enabled != 0;
        1
    } else {
        0
    }
}

/// Evaluate attenuation curve
#[unsafe(no_mangle)]
pub extern "C" fn middleware_evaluate_attenuation_curve(curve_id: u32, input: f32) -> f32 {
    let system = ATTENUATION_SYSTEM.read();
    system.get_curve(curve_id)
        .map(|c| c.evaluate(input))
        .unwrap_or(0.0)
}

/// Get attenuation curve count
#[unsafe(no_mangle)]
pub extern "C" fn middleware_get_attenuation_curve_count() -> u32 {
    ATTENUATION_SYSTEM.read().curves.len() as u32
}

/// Clear all attenuation curves
#[unsafe(no_mangle)]
pub extern "C" fn middleware_clear_attenuation_curves() {
    ATTENUATION_SYSTEM.write().curves.clear();
}

#[cfg(test)]
mod tests {
    use super::*;
    use parking_lot::MutexGuard;

    // ═══════════════════════════════════════════════════════════════════════════
    // RAII TEST GUARD — Ensures exclusive access and automatic cleanup
    // ═══════════════════════════════════════════════════════════════════════════

    /// RAII guard that:
    /// 1. Acquires exclusive lock on global test mutex (prevents parallel test interference)
    /// 2. Resets ALL global state before test runs
    /// 3. Initializes middleware and stores consumer pointer
    /// 4. On drop: shuts down, resets state, frees consumer, releases lock
    struct MiddlewareTestGuard {
        _lock: MutexGuard<'static, ()>,
        consumer_ptr: *mut std::ffi::c_void,
    }

    impl MiddlewareTestGuard {
        fn new() -> Self {
            // Step 1: Acquire exclusive lock (blocks other tests)
            let lock = TEST_MUTEX.lock();

            // Step 2: Full reset of ALL global state
            full_reset_for_testing();

            // Step 3: Initialize middleware
            let ptr = middleware_init();
            assert!(!ptr.is_null(), "middleware_init() returned null");
            assert_eq!(middleware_is_initialized(), 1);

            Self {
                _lock: lock,
                consumer_ptr: ptr,
            }
        }
    }

    impl Drop for MiddlewareTestGuard {
        fn drop(&mut self) {
            // Step 1: Shutdown middleware properly
            if middleware_is_initialized() == 1 {
                middleware_shutdown();
            }

            // Step 2: Full reset for next test
            full_reset_for_testing();

            // Step 3: Free the leaked consumer
            if !self.consumer_ptr.is_null() {
                unsafe {
                    drop(Box::from_raw(self.consumer_ptr as *mut rtrb::Consumer<EventCommand>));
                }
            }
            // Step 4: Lock is automatically released when _lock drops
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TESTS — All use MiddlewareTestGuard for isolation
    // ═══════════════════════════════════════════════════════════════════════════

    #[test]
    fn test_init_shutdown() {
        let guard = MiddlewareTestGuard::new();
        assert_eq!(middleware_is_initialized(), 1);

        middleware_shutdown();
        assert_eq!(middleware_is_initialized(), 0);

        // Re-init to satisfy guard's drop (which expects initialized state or handles it)
        let ptr = middleware_init();
        assert!(!ptr.is_null());

        // Guard will handle final cleanup
        drop(guard);

        // Clean up the second consumer
        if !ptr.is_null() {
            unsafe {
                drop(Box::from_raw(ptr as *mut rtrb::Consumer<EventCommand>));
            }
        }
    }

    #[test]
    fn test_register_event() {
        let _guard = MiddlewareTestGuard::new();

        let name = std::ffi::CString::new("TestEvent").unwrap();
        let category = std::ffi::CString::new("SFX").unwrap();

        assert_eq!(
            middleware_register_event(1, name.as_ptr(), category.as_ptr(), 5),
            1
        );
        assert_eq!(middleware_get_event_count(), 1);
    }

    #[test]
    fn test_state_management() {
        let _guard = MiddlewareTestGuard::new();

        let group_name = std::ffi::CString::new("GameState").unwrap();
        let state_name = std::ffi::CString::new("Playing").unwrap();

        assert_eq!(middleware_register_state_group(1, group_name.as_ptr(), 0), 1);
        assert_eq!(middleware_add_state(1, 1, state_name.as_ptr()), 1);
        assert_eq!(middleware_set_state(1, 1), 1);
        assert_eq!(middleware_get_state(1), 1);
    }

    #[test]
    fn test_rtpc() {
        let _guard = MiddlewareTestGuard::new();

        let name = std::ffi::CString::new("Volume").unwrap();

        assert_eq!(
            middleware_register_rtpc(1, name.as_ptr(), 0.0, 1.0, 0.5),
            1
        );
        assert_eq!(middleware_set_rtpc(1, 0.75, 0), 1);
        assert!((middleware_get_rtpc(1) - 0.75).abs() < 0.001);
    }
}
