//! Event Manager
//!
//! Core of the middleware event system. Handles:
//! - Event registration and lookup
//! - Command queue (UI → Audio thread)
//! - Event instance lifecycle
//! - State/Switch/RTPC management
//!
//! ## Thread Safety Design
//!
//! The event system is split into two parts:
//! - `EventManagerHandle`: Thread-safe handle for UI/game thread
//! - `EventManagerProcessor`: Audio-thread-only processor (not Sync)

use parking_lot::{Mutex, RwLock};
use rtrb::{Consumer, Producer, RingBuffer};
use std::collections::HashMap;
use std::sync::Arc;

use crate::action::{ActionPriority, ActionType, MiddlewareAction};
use crate::event::MiddlewareEvent;
use crate::instance::{
    CallbackInfo, CallbackType, EventInstance, EventInstanceState, GameObjectId, PlayingId,
    generate_playing_id,
};
use crate::state::{RtpcDefinition, StateGroup, SwitchGroup};

// ═══════════════════════════════════════════════════════════════════════════════
// COMMAND TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Commands sent from UI/game thread to audio thread
#[derive(Debug, Clone)]
pub enum EventCommand {
    /// Post an event
    PostEvent {
        event_id: u32,
        game_object: GameObjectId,
        playing_id: PlayingId,
        callback_id: Option<u32>,
        user_data: u64,
    },
    /// Post event by name
    PostEventByName {
        name: String,
        game_object: GameObjectId,
        playing_id: PlayingId,
        callback_id: Option<u32>,
        user_data: u64,
    },
    /// Stop a specific playing instance
    StopPlayingId { playing_id: PlayingId, fade_ms: u32 },
    /// Stop all instances of an event
    StopEvent {
        event_id: u32,
        game_object: Option<GameObjectId>,
        fade_ms: u32,
    },
    /// Stop all events
    StopAll {
        game_object: Option<GameObjectId>,
        fade_ms: u32,
    },
    /// Pause playing instance
    PausePlayingId { playing_id: PlayingId },
    /// Pause all instances
    PauseAll { game_object: Option<GameObjectId> },
    /// Resume playing instance
    ResumePlayingId { playing_id: PlayingId },
    /// Resume all instances
    ResumeAll { game_object: Option<GameObjectId> },
    /// Set state group value
    SetState { group_id: u32, state_id: u32 },
    /// Set switch for game object
    SetSwitch {
        game_object: GameObjectId,
        group_id: u32,
        switch_id: u32,
    },
    /// Set RTPC value
    SetRtpc {
        rtpc_id: u32,
        value: f32,
        game_object: Option<GameObjectId>,
        interpolation_ms: u32,
    },
    /// Reset RTPC to default
    ResetRtpc {
        rtpc_id: u32,
        game_object: Option<GameObjectId>,
        interpolation_ms: u32,
    },
    /// Set bus volume
    SetBusVolume {
        bus_id: u32,
        volume: f32,
        fade_ms: u32,
    },
    /// Seek in playing instance
    SeekPlayingId {
        playing_id: PlayingId,
        position_secs: f32,
    },
    /// Break loop in playing instance
    BreakLoop { playing_id: PlayingId },
}

// ═══════════════════════════════════════════════════════════════════════════════
// RTPC VALUE (with interpolation state)
// ═══════════════════════════════════════════════════════════════════════════════

/// RTPC value with interpolation state
#[derive(Debug, Clone)]
struct RtpcValue {
    current: f32,
    target: f32,
    interpolation_frames: u64,
    remaining_frames: u64,
}

impl RtpcValue {
    fn new(value: f32) -> Self {
        Self {
            current: value,
            target: value,
            interpolation_frames: 0,
            remaining_frames: 0,
        }
    }

    fn set_target(&mut self, target: f32, interpolation_frames: u64) {
        self.target = target;
        self.interpolation_frames = interpolation_frames;
        self.remaining_frames = interpolation_frames;
    }

    fn update(&mut self, frames: u64) {
        if self.remaining_frames == 0 {
            self.current = self.target;
            return;
        }

        if frames >= self.remaining_frames {
            self.current = self.target;
            self.remaining_frames = 0;
        } else {
            let progress = 1.0 - (self.remaining_frames as f32 / self.interpolation_frames as f32);
            self.current = self.current + (self.target - self.current) * progress;
            self.remaining_frames -= frames;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED STATE (Thread-safe)
// ═══════════════════════════════════════════════════════════════════════════════

/// Default command queue capacity
const COMMAND_QUEUE_CAPACITY: usize = 4096;

/// Maximum active instances
const MAX_ACTIVE_INSTANCES: usize = 1024;

/// Shared state between Handle and Processor (thread-safe)
pub struct EventManagerShared {
    /// Event definitions by ID
    events: RwLock<HashMap<u32, MiddlewareEvent>>,
    /// Event name → ID lookup
    event_names: RwLock<HashMap<String, u32>>,
    /// State group definitions
    state_groups: RwLock<HashMap<u32, StateGroup>>,
    /// Switch group definitions
    switch_groups: RwLock<HashMap<u32, SwitchGroup>>,
    /// RTPC definitions
    rtpc_definitions: RwLock<HashMap<u32, RtpcDefinition>>,
    /// Command producer (protected by Mutex for thread-safe access)
    command_tx: Mutex<Producer<EventCommand>>,
    /// Sample rate
    sample_rate: u32,
    /// Active instance count (for UI queries)
    active_count: std::sync::atomic::AtomicUsize,
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT MANAGER HANDLE (Thread-safe, for UI/Game thread)
// ═══════════════════════════════════════════════════════════════════════════════

/// Thread-safe handle for posting events and registering definitions
///
/// This is the interface used by UI/game code. It can be safely
/// shared across threads (implements Sync).
#[derive(Clone)]
pub struct EventManagerHandle {
    shared: Arc<EventManagerShared>,
}

// SAFETY: EventManagerHandle only contains Arc<EventManagerShared> which is Sync
unsafe impl Send for EventManagerHandle {}
unsafe impl Sync for EventManagerHandle {}

impl EventManagerHandle {
    /// Get sample rate
    pub fn sample_rate(&self) -> u32 {
        self.shared.sample_rate
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENT REGISTRATION (called from any thread)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Register an event definition
    pub fn register_event(&self, event: MiddlewareEvent) {
        let id = event.id;
        let name = event.name.clone();

        self.shared.events.write().insert(id, event);
        self.shared.event_names.write().insert(name, id);
    }

    /// Unregister an event
    pub fn unregister_event(&self, event_id: u32) {
        if let Some(event) = self.shared.events.write().remove(&event_id) {
            self.shared.event_names.write().remove(&event.name);
        }
    }

    /// Get event by ID
    pub fn get_event(&self, event_id: u32) -> Option<MiddlewareEvent> {
        self.shared.events.read().get(&event_id).cloned()
    }

    /// Get event ID by name
    pub fn get_event_id(&self, name: &str) -> Option<u32> {
        self.shared.event_names.read().get(name).copied()
    }

    /// Get all event IDs
    pub fn event_ids(&self) -> Vec<u32> {
        self.shared.events.read().keys().copied().collect()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE/SWITCH/RTPC REGISTRATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Register a state group
    pub fn register_state_group(&self, group: StateGroup) {
        self.shared.state_groups.write().insert(group.id, group);
    }

    /// Register a switch group
    pub fn register_switch_group(&self, group: SwitchGroup) {
        self.shared.switch_groups.write().insert(group.id, group);
    }

    /// Register an RTPC definition
    pub fn register_rtpc(&self, rtpc: RtpcDefinition) {
        self.shared.rtpc_definitions.write().insert(rtpc.id, rtpc);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // COMMAND POSTING (called from UI/game thread)
    // ═══════════════════════════════════════════════════════════════════════════

    fn push_command(&self, cmd: EventCommand) {
        let mut tx = self.shared.command_tx.lock();
        let _ = tx.push(cmd);
    }

    /// Post an event
    pub fn post_event(&self, event_id: u32, game_object: GameObjectId) -> PlayingId {
        self.post_event_ext(event_id, game_object, None, 0)
    }

    /// Post an event with extended options
    pub fn post_event_ext(
        &self,
        event_id: u32,
        game_object: GameObjectId,
        callback_id: Option<u32>,
        user_data: u64,
    ) -> PlayingId {
        let playing_id = generate_playing_id();

        self.push_command(EventCommand::PostEvent {
            event_id,
            game_object,
            playing_id,
            callback_id,
            user_data,
        });

        playing_id
    }

    /// Post an event by name
    pub fn post_event_by_name(&self, name: &str, game_object: GameObjectId) -> PlayingId {
        let playing_id = generate_playing_id();

        self.push_command(EventCommand::PostEventByName {
            name: name.to_string(),
            game_object,
            playing_id,
            callback_id: None,
            user_data: 0,
        });

        playing_id
    }

    /// Stop a playing instance
    pub fn stop_playing_id(&self, playing_id: PlayingId, fade_ms: u32) {
        self.push_command(EventCommand::StopPlayingId {
            playing_id,
            fade_ms,
        });
    }

    /// Stop all instances of an event
    pub fn stop_event(&self, event_id: u32, game_object: GameObjectId, fade_ms: u32) {
        self.push_command(EventCommand::StopEvent {
            event_id,
            game_object: if game_object == 0 {
                None
            } else {
                Some(game_object)
            },
            fade_ms,
        });
    }

    /// Stop all events
    pub fn stop_all(&self, fade_ms: u32) {
        self.push_command(EventCommand::StopAll {
            game_object: None,
            fade_ms,
        });
    }

    /// Pause a playing instance
    pub fn pause_playing_id(&self, playing_id: PlayingId) {
        self.push_command(EventCommand::PausePlayingId { playing_id });
    }

    /// Pause all events
    pub fn pause_all(&self, game_object: Option<GameObjectId>) {
        self.push_command(EventCommand::PauseAll { game_object });
    }

    /// Resume a playing instance
    pub fn resume_playing_id(&self, playing_id: PlayingId) {
        self.push_command(EventCommand::ResumePlayingId { playing_id });
    }

    /// Resume all events
    pub fn resume_all(&self, game_object: Option<GameObjectId>) {
        self.push_command(EventCommand::ResumeAll { game_object });
    }

    /// Set state
    pub fn set_state(&self, group_id: u32, state_id: u32) {
        self.push_command(EventCommand::SetState { group_id, state_id });
    }

    /// Set switch
    pub fn set_switch(&self, game_object: GameObjectId, group_id: u32, switch_id: u32) {
        self.push_command(EventCommand::SetSwitch {
            game_object,
            group_id,
            switch_id,
        });
    }

    /// Set RTPC value
    pub fn set_rtpc(&self, rtpc_id: u32, value: f32, interpolation_ms: u32) {
        self.push_command(EventCommand::SetRtpc {
            rtpc_id,
            value,
            game_object: None,
            interpolation_ms,
        });
    }

    /// Set RTPC value on specific game object
    pub fn set_rtpc_on_object(
        &self,
        game_object: GameObjectId,
        rtpc_id: u32,
        value: f32,
        interpolation_ms: u32,
    ) {
        self.push_command(EventCommand::SetRtpc {
            rtpc_id,
            value,
            game_object: Some(game_object),
            interpolation_ms,
        });
    }

    /// Reset RTPC to default
    pub fn reset_rtpc(
        &self,
        rtpc_id: u32,
        game_object: Option<GameObjectId>,
        interpolation_ms: u32,
    ) {
        self.push_command(EventCommand::ResetRtpc {
            rtpc_id,
            game_object,
            interpolation_ms,
        });
    }

    /// Set bus volume
    pub fn set_bus_volume(&self, bus_id: u32, volume: f32, fade_ms: u32) {
        self.push_command(EventCommand::SetBusVolume {
            bus_id,
            volume,
            fade_ms,
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // QUERY METHODS (thread-safe reads from shared state)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get active instance count (approximate, updated by processor)
    pub fn active_instance_count(&self) -> usize {
        self.shared
            .active_count
            .load(std::sync::atomic::Ordering::Relaxed)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EVENT MANAGER PROCESSOR (Audio thread only - NOT Sync)
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio-thread-only processor for event instances
///
/// This struct owns the Consumer end of the command queue and
/// manages all active event instances. It is NOT thread-safe
/// and must only be used from the audio thread.
pub struct EventManagerProcessor {
    /// Reference to shared state
    shared: Arc<EventManagerShared>,
    /// Command consumer (audio thread reads)
    command_rx: Consumer<EventCommand>,
    /// Active event instances
    instances: Vec<EventInstance>,
    /// Current state values (group_id → state_id)
    current_states: HashMap<u32, u32>,
    /// Current switch values ((game_object, group_id) → switch_id)
    current_switches: HashMap<(GameObjectId, u32), u32>,
    /// Current RTPC values (rtpc_id → value with interpolation)
    current_rtpcs: HashMap<u32, RtpcValue>,
    /// Per-object RTPC overrides ((game_object, rtpc_id) → value)
    object_rtpcs: HashMap<(GameObjectId, u32), RtpcValue>,
    /// Bus volumes (bus_id → volume)
    bus_volumes: HashMap<u32, RtpcValue>,
    /// Pending callbacks to send
    pending_callbacks: Vec<CallbackInfo>,
    /// Current frame counter
    current_frame: u64,
}

impl EventManagerProcessor {
    /// Process one audio block
    ///
    /// Call this from the audio callback. Processes commands,
    /// executes pending actions, and updates interpolations.
    pub fn process(&mut self, num_frames: u64) -> Vec<ExecutedAction> {
        let mut executed = Vec::new();

        // 1. Process pending commands
        self.process_commands(&mut executed);

        // 2. Update RTPC interpolations
        self.update_rtpc_interpolations(num_frames);

        // 3. Execute pending actions in instances
        self.execute_pending_actions(&mut executed);

        // 4. Update stop fades
        self.update_stop_fades(num_frames);

        // 5. Cleanup completed instances
        self.cleanup_instances();

        // 6. Update shared active count
        let active = self
            .instances
            .iter()
            .filter(|i| i.state.is_active())
            .count();
        self.shared
            .active_count
            .store(active, std::sync::atomic::Ordering::Relaxed);

        // 7. Advance frame counter
        self.current_frame += num_frames;

        executed
    }

    fn process_commands(&mut self, executed: &mut Vec<ExecutedAction>) {
        while let Ok(cmd) = self.command_rx.pop() {
            match cmd {
                EventCommand::PostEvent {
                    event_id,
                    game_object,
                    playing_id,
                    callback_id,
                    user_data,
                } => {
                    self.execute_post_event(
                        event_id,
                        game_object,
                        playing_id,
                        callback_id,
                        user_data,
                        executed,
                    );
                }
                EventCommand::PostEventByName {
                    name,
                    game_object,
                    playing_id,
                    callback_id,
                    user_data,
                } => {
                    let event_id = self.shared.event_names.read().get(&name).copied();
                    if let Some(id) = event_id {
                        self.execute_post_event(
                            id,
                            game_object,
                            playing_id,
                            callback_id,
                            user_data,
                            executed,
                        );
                    }
                }
                EventCommand::StopPlayingId {
                    playing_id,
                    fade_ms,
                } => {
                    self.execute_stop_playing_id(playing_id, fade_ms);
                }
                EventCommand::StopEvent {
                    event_id,
                    game_object,
                    fade_ms,
                } => {
                    self.execute_stop_event(event_id, game_object, fade_ms);
                }
                EventCommand::StopAll {
                    game_object,
                    fade_ms,
                } => {
                    self.execute_stop_all(game_object, fade_ms);
                }
                EventCommand::PausePlayingId { playing_id } => {
                    if let Some(inst) = self
                        .instances
                        .iter_mut()
                        .find(|i| i.playing_id == playing_id)
                    {
                        inst.pause();
                    }
                }
                EventCommand::PauseAll { game_object } => {
                    for inst in &mut self.instances {
                        if game_object.is_none() || Some(inst.game_object) == game_object {
                            inst.pause();
                        }
                    }
                }
                EventCommand::ResumePlayingId { playing_id } => {
                    if let Some(inst) = self
                        .instances
                        .iter_mut()
                        .find(|i| i.playing_id == playing_id)
                    {
                        inst.resume();
                    }
                }
                EventCommand::ResumeAll { game_object } => {
                    for inst in &mut self.instances {
                        if game_object.is_none() || Some(inst.game_object) == game_object {
                            inst.resume();
                        }
                    }
                }
                EventCommand::SetState { group_id, state_id } => {
                    self.current_states.insert(group_id, state_id);
                }
                EventCommand::SetSwitch {
                    game_object,
                    group_id,
                    switch_id,
                } => {
                    self.current_switches
                        .insert((game_object, group_id), switch_id);
                }
                EventCommand::SetRtpc {
                    rtpc_id,
                    value,
                    game_object,
                    interpolation_ms,
                } => {
                    let frames =
                        (interpolation_ms as f32 * self.shared.sample_rate as f32 / 1000.0) as u64;

                    // Get default value from RTPC definition, or 0.0
                    let default_value = self
                        .shared
                        .rtpc_definitions
                        .read()
                        .get(&rtpc_id)
                        .map(|d| d.default)
                        .unwrap_or(0.0);

                    if let Some(go) = game_object {
                        let entry = self
                            .object_rtpcs
                            .entry((go, rtpc_id))
                            .or_insert_with(|| RtpcValue::new(default_value));
                        entry.set_target(value, frames);
                    } else {
                        let entry = self
                            .current_rtpcs
                            .entry(rtpc_id)
                            .or_insert_with(|| RtpcValue::new(default_value));
                        entry.set_target(value, frames);
                    }
                }
                EventCommand::ResetRtpc {
                    rtpc_id,
                    game_object,
                    interpolation_ms,
                } => {
                    let default_value = self
                        .shared
                        .rtpc_definitions
                        .read()
                        .get(&rtpc_id)
                        .map(|d| d.default)
                        .unwrap_or(0.0);

                    let frames =
                        (interpolation_ms as f32 * self.shared.sample_rate as f32 / 1000.0) as u64;

                    if let Some(go) = game_object {
                        if let Some(val) = self.object_rtpcs.get_mut(&(go, rtpc_id)) {
                            val.set_target(default_value, frames);
                        }
                    } else if let Some(val) = self.current_rtpcs.get_mut(&rtpc_id) {
                        val.set_target(default_value, frames);
                    }
                }
                EventCommand::SetBusVolume {
                    bus_id,
                    volume,
                    fade_ms,
                } => {
                    let frames = (fade_ms as f32 * self.shared.sample_rate as f32 / 1000.0) as u64;
                    let entry = self
                        .bus_volumes
                        .entry(bus_id)
                        .or_insert_with(|| RtpcValue::new(1.0));
                    entry.set_target(volume, frames);
                }
                EventCommand::SeekPlayingId { .. } => {
                    // TODO: Implement seek
                }
                EventCommand::BreakLoop { .. } => {
                    // TODO: Implement break loop
                }
            }
        }
    }

    fn execute_post_event(
        &mut self,
        event_id: u32,
        game_object: GameObjectId,
        playing_id: PlayingId,
        callback_id: Option<u32>,
        user_data: u64,
        executed: &mut Vec<ExecutedAction>,
    ) {
        let event = match self.shared.events.read().get(&event_id).cloned() {
            Some(e) => e,
            None => return,
        };

        // Check max instances
        if event.max_instances > 0 {
            let count = self
                .instances
                .iter()
                .filter(|i| i.event_id == event_id && i.state.is_active())
                .count() as u32;

            if count >= event.max_instances {
                match event.max_instance_behavior {
                    crate::event::MaxInstanceBehavior::DiscardNewest => return,
                    crate::event::MaxInstanceBehavior::DiscardOldest => {
                        // Stop oldest instance
                        if let Some(oldest) = self
                            .instances
                            .iter_mut()
                            .filter(|i| i.event_id == event_id && i.state.is_active())
                            .min_by_key(|i| i.start_frame)
                        {
                            oldest.start_stopping(0);
                        }
                    }
                    crate::event::MaxInstanceBehavior::DiscardLowestPriority => {
                        // TODO: Implement priority-based discard
                    }
                    crate::event::MaxInstanceBehavior::IgnoreLimit => {}
                }
            }
        }

        // Create instance with the playing_id from handle
        let mut instance = EventInstance::new_with_id(
            playing_id,
            event_id,
            &event.name,
            game_object,
            self.current_frame,
        );
        if let Some(cb) = callback_id {
            instance.callback_id = Some(cb);
        }
        instance.user_data = user_data;
        instance.schedule_actions(&event, self.shared.sample_rate);

        // Send callback
        if let Some(cb_id) = callback_id {
            self.pending_callbacks.push(CallbackInfo {
                callback_type: CallbackType::EventStarted,
                playing_id,
                event_id,
                game_object,
                callback_id: cb_id,
                voice_id: None,
                data: 0,
            });
        }

        self.instances.push(instance);

        // Report as executed action
        executed.push(ExecutedAction::EventPosted {
            event_id,
            playing_id,
            game_object,
        });
    }

    fn execute_stop_playing_id(&mut self, playing_id: PlayingId, fade_ms: u32) {
        let fade_frames = (fade_ms as f32 * self.shared.sample_rate as f32 / 1000.0) as u64;

        if let Some(inst) = self
            .instances
            .iter_mut()
            .find(|i| i.playing_id == playing_id)
        {
            inst.start_stopping(fade_frames);
        }
    }

    fn execute_stop_event(
        &mut self,
        event_id: u32,
        game_object: Option<GameObjectId>,
        fade_ms: u32,
    ) {
        let fade_frames = (fade_ms as f32 * self.shared.sample_rate as f32 / 1000.0) as u64;

        for inst in &mut self.instances {
            if inst.event_id == event_id
                && (game_object.is_none() || Some(inst.game_object) == game_object)
            {
                inst.start_stopping(fade_frames);
            }
        }
    }

    fn execute_stop_all(&mut self, game_object: Option<GameObjectId>, fade_ms: u32) {
        let fade_frames = (fade_ms as f32 * self.shared.sample_rate as f32 / 1000.0) as u64;

        for inst in &mut self.instances {
            if game_object.is_none() || Some(inst.game_object) == game_object {
                inst.start_stopping(fade_frames);
            }
        }
    }

    fn update_rtpc_interpolations(&mut self, frames: u64) {
        for val in self.current_rtpcs.values_mut() {
            val.update(frames);
        }
        for val in self.object_rtpcs.values_mut() {
            val.update(frames);
        }
        for val in self.bus_volumes.values_mut() {
            val.update(frames);
        }
    }

    fn execute_pending_actions(&mut self, executed: &mut Vec<ExecutedAction>) {
        let current_frame = self.current_frame;
        let sample_rate = self.shared.sample_rate;

        // Build RTPC value map for condition checking (current values only)
        let rtpc_values: HashMap<u32, f32> = self
            .current_rtpcs
            .iter()
            .map(|(id, val)| (*id, val.current))
            .collect();

        for instance in &mut self.instances {
            if instance.state != EventInstanceState::Playing {
                continue;
            }

            let game_object = instance.game_object;

            // Collect ready actions data first, checking conditions
            let ready_action_data: Vec<_> = instance
                .pending_actions
                .iter()
                .filter(|a| {
                    if a.executed || a.execute_at_frame > current_frame {
                        return false;
                    }

                    // Check state condition
                    if !a.action.check_state_condition(&self.current_states) {
                        return false;
                    }

                    // Check switch condition (for this game object)
                    if !a
                        .action
                        .check_switch_condition(game_object, &self.current_switches)
                    {
                        return false;
                    }

                    // Check RTPC condition
                    if !a.action.check_rtpc_condition(&rtpc_values) {
                        return false;
                    }

                    true
                })
                .map(|a| (a.action.clone(), game_object, instance.playing_id))
                .collect();

            // Mark as executed only those that passed conditions
            let passed_ids: std::collections::HashSet<_> =
                ready_action_data.iter().map(|(a, _, _)| a.id).collect();

            for pending in &mut instance.pending_actions {
                if !pending.executed && pending.execute_at_frame <= current_frame {
                    // Only mark as executed if it passed conditions
                    // (or if it has no conditions - legacy behavior)
                    if !pending.action.has_condition() || passed_ids.contains(&pending.action.id) {
                        pending.executed = true;
                    }
                    // Actions that failed conditions remain pending for re-evaluation
                }
            }

            // Execute actions that passed conditions
            for (action, game_object, playing_id) in ready_action_data {
                let exec_action = execute_action(&action, game_object, playing_id, sample_rate);
                executed.push(exec_action);
            }
        }
    }

    fn update_stop_fades(&mut self, frames: u64) {
        for inst in &mut self.instances {
            inst.update_stop_fade(frames);
        }
    }

    fn cleanup_instances(&mut self) {
        // Send end callbacks before removing
        for inst in &self.instances {
            if inst.state == EventInstanceState::Stopped {
                if let Some(callback_id) = inst.callback_id {
                    self.pending_callbacks.push(CallbackInfo {
                        callback_type: CallbackType::EventEnded,
                        playing_id: inst.playing_id,
                        event_id: inst.event_id,
                        game_object: inst.game_object,
                        callback_id,
                        voice_id: None,
                        data: 0,
                    });
                }
            }
        }

        // Only remove instances that are fully stopped
        // Keep Playing/Paused/Stopping instances even if all actions executed
        self.instances
            .retain(|i| i.state != EventInstanceState::Stopped);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // QUERY METHODS (audio thread only)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get current state value for a group
    pub fn get_state(&self, group_id: u32) -> Option<u32> {
        self.current_states.get(&group_id).copied()
    }

    /// Get current switch value for game object
    pub fn get_switch(&self, game_object: GameObjectId, group_id: u32) -> Option<u32> {
        self.current_switches.get(&(game_object, group_id)).copied()
    }

    /// Get current RTPC value
    pub fn get_rtpc(&self, rtpc_id: u32) -> Option<f32> {
        self.current_rtpcs.get(&rtpc_id).map(|v| v.current)
    }

    /// Get RTPC value for specific game object
    pub fn get_object_rtpc(&self, game_object: GameObjectId, rtpc_id: u32) -> Option<f32> {
        self.object_rtpcs
            .get(&(game_object, rtpc_id))
            .map(|v| v.current)
    }

    /// Get bus volume
    pub fn get_bus_volume(&self, bus_id: u32) -> f32 {
        self.bus_volumes
            .get(&bus_id)
            .map(|v| v.current)
            .unwrap_or(1.0)
    }

    /// Get active instance count
    pub fn active_instance_count(&self) -> usize {
        self.instances
            .iter()
            .filter(|i| i.state.is_active())
            .count()
    }

    /// Get all active instances
    pub fn active_instances(&self) -> &[EventInstance] {
        &self.instances
    }

    /// Check if event is playing
    pub fn is_event_playing(&self, event_id: u32, game_object: GameObjectId) -> bool {
        self.instances.iter().any(|i| {
            i.event_id == event_id
                && (game_object == 0 || i.game_object == game_object)
                && i.state.is_active()
        })
    }

    /// Take pending callbacks
    pub fn take_callbacks(&mut self) -> Vec<CallbackInfo> {
        std::mem::take(&mut self.pending_callbacks)
    }

    /// Get current frame
    pub fn current_frame(&self) -> u64 {
        self.current_frame
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FACTORY FUNCTION
// ═══════════════════════════════════════════════════════════════════════════════

/// Create a new event manager system
///
/// Returns a tuple of:
/// - `EventManagerHandle`: Thread-safe handle for UI/game thread
/// - `EventManagerProcessor`: Audio-thread-only processor
///
/// The Handle can be cloned and shared across threads.
/// The Processor must stay on the audio thread.
pub fn create_event_manager(sample_rate: u32) -> (EventManagerHandle, EventManagerProcessor) {
    let (command_tx, command_rx) = RingBuffer::new(COMMAND_QUEUE_CAPACITY);

    let shared = Arc::new(EventManagerShared {
        events: RwLock::new(HashMap::new()),
        event_names: RwLock::new(HashMap::new()),
        state_groups: RwLock::new(HashMap::new()),
        switch_groups: RwLock::new(HashMap::new()),
        rtpc_definitions: RwLock::new(HashMap::new()),
        command_tx: Mutex::new(command_tx),
        sample_rate,
        active_count: std::sync::atomic::AtomicUsize::new(0),
    });

    let handle = EventManagerHandle {
        shared: Arc::clone(&shared),
    };

    let processor = EventManagerProcessor {
        shared,
        command_rx,
        instances: Vec::with_capacity(MAX_ACTIVE_INSTANCES),
        current_states: HashMap::new(),
        current_switches: HashMap::new(),
        current_rtpcs: HashMap::new(),
        object_rtpcs: HashMap::new(),
        bus_volumes: HashMap::new(),
        pending_callbacks: Vec::new(),
        current_frame: 0,
    };

    (handle, processor)
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTION (no borrow issues)
// ═══════════════════════════════════════════════════════════════════════════════

fn execute_action(
    action: &MiddlewareAction,
    game_object: GameObjectId,
    playing_id: PlayingId,
    sample_rate: u32,
) -> ExecutedAction {
    match action.action_type {
        ActionType::Play | ActionType::PlayAndContinue => ExecutedAction::Play {
            playing_id,
            asset_id: action.asset_id.unwrap_or(0),
            bus_id: action.bus_id,
            gain: action.gain,
            loop_playback: action.loop_playback,
            fade_in_frames: action.fade_frames(sample_rate),
            priority: action.priority,
        },
        ActionType::Stop => ExecutedAction::Stop {
            playing_id,
            asset_id: action.asset_id,
            fade_out_frames: action.fade_frames(sample_rate),
        },
        ActionType::StopAll => ExecutedAction::StopAll {
            game_object: if action.scope == crate::action::ActionScope::Global {
                None
            } else {
                Some(game_object)
            },
            fade_out_frames: action.fade_frames(sample_rate),
        },
        ActionType::SetVolume => ExecutedAction::SetVolume {
            bus_id: action.bus_id,
            volume: action.gain,
            fade_frames: action.fade_frames(sample_rate),
        },
        ActionType::SetBusVolume => ExecutedAction::SetBusVolume {
            bus_id: action.bus_id,
            volume: action.gain,
            fade_frames: action.fade_frames(sample_rate),
        },
        ActionType::SetState => ExecutedAction::SetState {
            group_id: action.group_id.unwrap_or(0),
            state_id: action.value_id.unwrap_or(0),
        },
        ActionType::SetSwitch => ExecutedAction::SetSwitch {
            game_object,
            group_id: action.group_id.unwrap_or(0),
            switch_id: action.value_id.unwrap_or(0),
        },
        ActionType::SetRTPC => ExecutedAction::SetRtpc {
            rtpc_id: action.rtpc_id.unwrap_or(0),
            value: action.rtpc_value.unwrap_or(0.0),
        },
        ActionType::PostEvent => ExecutedAction::PostEvent {
            event_id: action.target_event_id.unwrap_or(0),
            game_object,
        },
        _ => ExecutedAction::Other {
            action_type: action.action_type,
        },
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXECUTED ACTION (for integration with audio engine)
// ═══════════════════════════════════════════════════════════════════════════════

/// Action that was executed by the event manager
///
/// Returned from `process()` so the audio engine can react.
#[derive(Debug, Clone)]
pub enum ExecutedAction {
    /// Event was posted
    EventPosted {
        event_id: u32,
        playing_id: PlayingId,
        game_object: GameObjectId,
    },
    /// Play a sound
    Play {
        playing_id: PlayingId,
        asset_id: u32,
        bus_id: u32,
        gain: f32,
        loop_playback: bool,
        fade_in_frames: u64,
        priority: ActionPriority,
    },
    /// Stop a sound
    Stop {
        playing_id: PlayingId,
        asset_id: Option<u32>,
        fade_out_frames: u64,
    },
    /// Stop all sounds
    StopAll {
        game_object: Option<GameObjectId>,
        fade_out_frames: u64,
    },
    /// Set volume
    SetVolume {
        bus_id: u32,
        volume: f32,
        fade_frames: u64,
    },
    /// Set bus volume
    SetBusVolume {
        bus_id: u32,
        volume: f32,
        fade_frames: u64,
    },
    /// Set state
    SetState { group_id: u32, state_id: u32 },
    /// Set switch
    SetSwitch {
        game_object: GameObjectId,
        group_id: u32,
        switch_id: u32,
    },
    /// Set RTPC
    SetRtpc { rtpc_id: u32, value: f32 },
    /// Post another event
    PostEvent {
        event_id: u32,
        game_object: GameObjectId,
    },
    /// Other action type
    Other { action_type: ActionType },
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_manager_creation() {
        let (handle, processor) = create_event_manager(48000);
        assert_eq!(handle.sample_rate(), 48000);
        assert_eq!(processor.active_instance_count(), 0);
    }

    #[test]
    fn test_event_registration() {
        let (handle, _processor) = create_event_manager(48000);

        let event = MiddlewareEvent::new(1, "Test_Event");
        handle.register_event(event);

        assert!(handle.get_event(1).is_some());
        assert_eq!(handle.get_event_id("Test_Event"), Some(1));
    }

    #[test]
    fn test_post_event() {
        let (handle, mut processor) = create_event_manager(48000);

        // Register event with action
        let mut event = MiddlewareEvent::new(1, "Play_Sound");
        event.add_action(MiddlewareAction::play(100, 0).with_id(1));
        handle.register_event(event);

        // Post event
        let _playing_id = handle.post_event(1, 0);

        // Process
        let executed = processor.process(256);

        // Should have created instance and executed play
        assert_eq!(processor.active_instance_count(), 1);
        assert!(
            executed
                .iter()
                .any(|e| matches!(e, ExecutedAction::EventPosted { .. }))
        );
        assert!(
            executed
                .iter()
                .any(|e| matches!(e, ExecutedAction::Play { .. }))
        );
    }

    #[test]
    fn test_state_management() {
        let (handle, mut processor) = create_event_manager(48000);

        // Register state group
        let mut group = StateGroup::new(1, "GameState");
        group.add_state(1, "Menu");
        group.add_state(2, "Playing");
        handle.register_state_group(group);

        // Set state
        handle.set_state(1, 2);
        processor.process(256);

        assert_eq!(processor.get_state(1), Some(2));
    }

    #[test]
    fn test_rtpc_interpolation() {
        let (handle, mut processor) = create_event_manager(48000);

        // Set RTPC with interpolation
        handle.set_rtpc(1, 1.0, 1000); // 1 second interpolation
        processor.process(256);

        // Should be interpolating
        let value = processor.get_rtpc(1).unwrap();
        assert!(value < 1.0); // Not yet at target

        // Process more frames
        for _ in 0..200 {
            processor.process(256);
        }

        // Should be close to target now
        let value = processor.get_rtpc(1).unwrap();
        assert!((value - 1.0).abs() < 0.1);
    }

    #[test]
    fn test_stop_event() {
        let (handle, mut processor) = create_event_manager(48000);

        // Register and post event
        let mut event = MiddlewareEvent::new(1, "Test");
        event.add_action(MiddlewareAction::play(100, 0).with_id(1));
        handle.register_event(event);

        let playing_id = handle.post_event(1, 0);
        processor.process(256);
        assert_eq!(processor.active_instance_count(), 1);

        // Stop with fade
        handle.stop_playing_id(playing_id, 100);
        processor.process(256);

        // Should be stopping
        assert!(processor.active_instances()[0].state == EventInstanceState::Stopping);
    }

    #[test]
    fn test_handle_is_sync() {
        fn assert_sync<T: Sync>() {}
        assert_sync::<EventManagerHandle>();
    }
}
