# FluxForge Event System — Detaljna Analiza

**Autori:** Chief Audio Architect, Lead DSP Engineer, Engine Architect
**Datum:** 2026-01-16
**Fokus:** Event system i sve povezane komponente

---

## Executive Summary

FluxForge ima **DVA RAZLIČITA "Event" koncepta** koji se NE PREKLAPAJU:

| Koncept | Lokacija | Namena | Status |
|---------|----------|--------|--------|
| **AudioEvent (DAW)** | `rf-engine/streaming.rs` | Timeline clip playback | ✅ Implementirano |
| **MiddlewareEvent (Game)** | `flutter_ui/models/middleware_models.dart` | Wwise-style PostEvent | ❌ UI Only |

**Problem:** Middleware event system postoji SAMO kao Dart UI model — nema Rust backend.

---

## 1. ŠTA POSTOJI: AudioEvent (DAW Koncept)

### 1.1 Definicija

**Lokacija:** `crates/rf-engine/src/streaming.rs:1245`

```rust
/// Non-destructive audio event on timeline
///
/// One audio file can have multiple events (instances) on the timeline.
/// This is the "clip" in DAW terminology.
#[derive(Debug, Clone)]
pub struct AudioEvent {
    /// Unique event ID
    pub event_id: u32,
    /// Asset ID (source audio file)
    pub asset_id: u32,
    /// Track ID this event belongs to
    pub track_id: u32,
    /// Timeline start position (frames)
    pub tl_start: i64,
    /// Event length (frames)
    pub length: i64,
    /// Source file offset (frames) - for trimmed clips
    pub src_start: i64,
    /// Clip gain (linear 0.0 - 2.0)
    pub gain: f32,
    /// Fade in length (frames)
    pub fade_in: i64,
    /// Fade out length (frames)
    pub fade_out: i64,
    /// Is event muted
    pub muted: bool,
}
```

### 1.2 Šta AudioEvent RADI

```
Timeline:
0s        1s        2s        3s        4s        5s
├─────────┼─────────┼─────────┼─────────┼─────────┤
│         │ [AudioEvent: "drums.wav"]   │         │
│         │ ┌───────────────────────┐   │         │
│         │ │ tl_start: 48000       │   │         │
│         │ │ length: 96000         │   │         │
│         │ │ fade_in: 4800         │   │         │
│         │ │ fade_out: 9600        │   │         │
│         │ └───────────────────────┘   │         │
```

Ovo je **DAW clip** — statički segment na timeline-u. Engine ga automatski svira kad playhead dođe do njega.

### 1.3 EventIndex za Efikasno Pronalaženje

```rust
// streaming.rs:391
pub struct EventIndex {
    bins: Vec<Vec<u32>>,  // Time bins za O(k) lookup
    bin_size: i64,
}

impl EventIndex {
    /// Get candidates for given frame (O(1) bin lookup + O(k) filtering)
    pub fn get_candidates(&self, frame: i64) -> &[u32] {
        let bin = (frame / self.bin_size) as usize;
        &self.bins[bin.min(self.bins.len() - 1)]
    }
}
```

**Ovo je ODLIČNO za DAW** — efikasan lookup aktivnih clipova.

---

## 2. ŠTA POSTOJI: MiddlewareEvent (UI Only)

### 2.1 Definicija

**Lokacija:** `flutter_ui/lib/models/middleware_models.dart`

```dart
/// Middleware event containing actions
class MiddlewareEvent {
  final String id;
  final String name;
  final String category;
  final List<MiddlewareAction> actions;
  final bool expanded;
}

/// Individual middleware action
class MiddlewareAction {
  final ActionType type;       // play, stop, setVolume, etc.
  final String assetId;        // Sound to play
  final String bus;            // Target bus
  final ActionScope scope;     // global, gameObject, etc.
  final ActionPriority priority;
  final FadeCurve fadeCurve;
  final double fadeTime;
  final double gain;
  final double delay;
  final bool loop;
}
```

### 2.2 ActionType Enum

```dart
enum ActionType {
  play,              // Play sound
  playAndContinue,   // Play without interrupting
  stop,              // Stop sound
  stopAll,           // Stop all on scope
  pause,             // Pause
  pauseAll,          // Pause all
  resume,            // Resume
  resumeAll,         // Resume all
  break_,            // Break loop
  mute,              // Mute
  unmute,            // Unmute
  setVolume,         // Set volume with fade
  setPitch,          // Set pitch
  setLPF,            // Set low-pass filter
  setHPF,            // Set high-pass filter
  setBusVolume,      // Set bus volume
  setState,          // Set state group
  setSwitch,         // Set switch
  setRTPC,           // Set RTPC
  resetRTPC,         // Reset RTPC to default
  seek,              // Seek position
  trigger,           // Trigger stinger
  postEvent,         // Post another event
}
```

### 2.3 Problem: NEMA RUST BACKEND

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRENUTNO STANJE                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Flutter UI (Dart)                                             │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │ MiddlewareEvent                                          │  │
│   │ ├── id: "BigWin_Start"                                  │  │
│   │ ├── actions:                                            │  │
│   │ │   ├── SetVolume(bus: "Music", gain: 0.3)             │  │
│   │ │   ├── Play(asset: "sfx_jackpot", bus: "Wins")        │  │
│   │ │   └── Play(asset: "vo_bigwin", delay: 0.5)           │  │
│   │ └── ...                                                 │  │
│   └─────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           ▼                                      │
│                    ❌ NEMA FFI BRIDGE ❌                         │
│                           │                                      │
│                           ▼                                      │
│   Rust Engine (rf-engine)                                       │
│   ┌─────────────────────────────────────────────────────────┐  │
│   │                                                          │  │
│   │         ❌ NEMA EventManager                             │  │
│   │         ❌ NEMA PostEvent funkcija                       │  │
│   │         ❌ NEMA Action executor                          │  │
│   │                                                          │  │
│   └─────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. WWISE EVENT SYSTEM (Referenca)

### 3.1 Wwise PostEvent Flow

```cpp
// Game code
AK::SoundEngine::PostEvent("Play_Explosion", gameObjectID);
```

```
┌─────────────────────────────────────────────────────────────────┐
│                    WWISE PostEvent FLOW                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. API Call                                                    │
│     PostEvent("Play_Explosion", gameObjectID)                   │
│                           │                                      │
│                           ▼                                      │
│  2. Event Lookup                                                │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ Event "Play_Explosion"                               │    │
│     │ ├── Action 1: Play "explosion_close" (0ms delay)    │    │
│     │ ├── Action 2: Play "debris_scatter" (100ms delay)   │    │
│     │ └── Action 3: SetRTPC "Intensity" = 1.0             │    │
│     └─────────────────────────────────────────────────────┘    │
│                           │                                      │
│                           ▼                                      │
│  3. Action Queue                                                │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ Frame 0: Execute Action 1, 3                         │    │
│     │ Frame 5: Execute Action 2 (100ms = ~5 frames @48kHz) │    │
│     └─────────────────────────────────────────────────────┘    │
│                           │                                      │
│                           ▼                                      │
│  4. Voice Allocation                                            │
│     ┌─────────────────────────────────────────────────────┐    │
│     │ VoiceManager::AllocateVoice()                        │    │
│     │ ├── Check voice limit                                │    │
│     │ ├── Priority-based stealing if needed                │    │
│     │ ├── Create EventInstance                             │    │
│     │ └── Start streaming/decoding                         │    │
│     └─────────────────────────────────────────────────────┘    │
│                           │                                      │
│                           ▼                                      │
│  5. Playback                                                    │
│     Sound plays on assigned game object position                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Wwise Event Instance

```cpp
struct AkEventInstance {
    AkPlayingID playingID;           // Unique ID for this instance
    AkGameObjectID gameObjectID;      // Which object triggered it
    AkEventID eventID;                // Which event
    AkTimeMs startTime;               // When started

    // Actions pending execution
    std::vector<AkPendingAction> pendingActions;

    // Voice references
    std::vector<AkVoiceID> voices;

    // Callback data
    AkCallbackFunc callback;
    void* callbackCookie;
};
```

---

## 4. ŠTA FLUXFORGE TREBA DA IMPLEMENTIRA

### 4.1 Rust: EventManager (`rf-event` crate)

```rust
// rf-event/src/lib.rs

pub mod action;
pub mod event;
pub mod instance;
pub mod queue;
pub mod state;
pub mod switch;
pub mod rtpc;

pub use action::*;
pub use event::*;
pub use instance::*;
```

### 4.2 Rust: Action Types

```rust
// rf-event/src/action.rs

/// Action type matching Dart UI
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ActionType {
    Play = 0,
    PlayAndContinue = 1,
    Stop = 2,
    StopAll = 3,
    Pause = 4,
    PauseAll = 5,
    Resume = 6,
    ResumeAll = 7,
    Break = 8,
    Mute = 9,
    Unmute = 10,
    SetVolume = 11,
    SetPitch = 12,
    SetLPF = 13,
    SetHPF = 14,
    SetBusVolume = 15,
    SetState = 16,
    SetSwitch = 17,
    SetRTPC = 18,
    ResetRTPC = 19,
    Seek = 20,
    Trigger = 21,
    PostEvent = 22,
}

/// Action scope
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ActionScope {
    Global = 0,
    GameObject = 1,
    Emitter = 2,
    All = 3,
    FirstOnly = 4,
    Random = 5,
}

/// Action priority
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
#[repr(u8)]
pub enum ActionPriority {
    Lowest = 0,
    Low = 1,
    BelowNormal = 2,
    Normal = 3,
    AboveNormal = 4,
    High = 5,
    Highest = 6,
}

/// Fade curve type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum FadeCurve {
    Linear = 0,
    Log3 = 1,
    Sine = 2,
    Log1 = 3,
    InvSCurve = 4,
    SCurve = 5,
    Exp1 = 6,
    Exp3 = 7,
}

impl FadeCurve {
    /// Evaluate curve at position t (0.0 - 1.0)
    #[inline]
    pub fn evaluate(&self, t: f32) -> f32 {
        let t = t.clamp(0.0, 1.0);
        match self {
            FadeCurve::Linear => t,
            FadeCurve::Log3 => (t * 3.0).ln_1p() / 3.0_f32.ln_1p(),
            FadeCurve::Sine => (t * std::f32::consts::FRAC_PI_2).sin(),
            FadeCurve::Log1 => (t + 1.0).ln() / 2.0_f32.ln(),
            FadeCurve::InvSCurve => {
                if t < 0.5 {
                    2.0 * t * t
                } else {
                    1.0 - 2.0 * (1.0 - t) * (1.0 - t)
                }
            }
            FadeCurve::SCurve => {
                if t < 0.5 {
                    4.0 * t * t * t
                } else {
                    1.0 - (-2.0 * t + 2.0).powi(3) / 2.0
                }
            }
            FadeCurve::Exp1 => (std::f32::consts::E.powf(t) - 1.0) / (std::f32::consts::E - 1.0),
            FadeCurve::Exp3 => (std::f32::consts::E.powf(t * 3.0) - 1.0) / (std::f32::consts::E.powi(3) - 1.0),
        }
    }
}
```

### 4.3 Rust: MiddlewareAction

```rust
// rf-event/src/action.rs

/// Complete action definition
#[derive(Debug, Clone)]
pub struct MiddlewareAction {
    /// Unique action ID
    pub id: u32,
    /// Action type
    pub action_type: ActionType,
    /// Target asset ID (for Play/Stop)
    pub asset_id: Option<u32>,
    /// Target bus ID
    pub bus_id: u32,
    /// Action scope
    pub scope: ActionScope,
    /// Priority
    pub priority: ActionPriority,
    /// Fade curve
    pub fade_curve: FadeCurve,
    /// Fade time in seconds
    pub fade_time: f32,
    /// Gain multiplier (0.0 - 2.0)
    pub gain: f32,
    /// Delay before execution (seconds)
    pub delay: f32,
    /// Loop playback
    pub loop_: bool,
    /// For SetState/SetSwitch: target group ID
    pub group_id: Option<u32>,
    /// For SetState/SetSwitch: target value ID
    pub value_id: Option<u32>,
    /// For SetRTPC: RTPC ID
    pub rtpc_id: Option<u32>,
    /// For SetRTPC: target value
    pub rtpc_value: Option<f32>,
    /// For Seek: position in seconds
    pub seek_position: Option<f32>,
    /// For PostEvent: target event ID
    pub target_event_id: Option<u32>,
}
```

### 4.4 Rust: MiddlewareEvent

```rust
// rf-event/src/event.rs

/// Middleware event definition
#[derive(Debug, Clone)]
pub struct MiddlewareEvent {
    /// Unique event ID
    pub id: u32,
    /// Event name (for lookup)
    pub name: String,
    /// Category for organization
    pub category: String,
    /// Actions to execute
    pub actions: Vec<MiddlewareAction>,
}

impl MiddlewareEvent {
    /// Create new event
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            category: "General".to_string(),
            actions: Vec::new(),
        }
    }

    /// Add action
    pub fn add_action(&mut self, action: MiddlewareAction) {
        self.actions.push(action);
    }

    /// Sort actions by delay for execution order
    pub fn sort_by_delay(&mut self) {
        self.actions.sort_by(|a, b| {
            a.delay.partial_cmp(&b.delay).unwrap_or(std::cmp::Ordering::Equal)
        });
    }
}
```

### 4.5 Rust: EventInstance

```rust
// rf-event/src/instance.rs

use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

/// Unique playing ID generator
static NEXT_PLAYING_ID: AtomicU64 = AtomicU64::new(1);

/// Playing ID type
pub type PlayingId = u64;

/// Game object ID type
pub type GameObjectId = u64;

/// Generate unique playing ID
pub fn generate_playing_id() -> PlayingId {
    NEXT_PLAYING_ID.fetch_add(1, Ordering::Relaxed)
}

/// Instance of an event being executed
#[derive(Debug)]
pub struct EventInstance {
    /// Unique playing ID
    pub playing_id: PlayingId,
    /// Source event ID
    pub event_id: u32,
    /// Game object that triggered this
    pub game_object: GameObjectId,
    /// When instance was created (engine frame)
    pub start_frame: u64,
    /// Current state
    pub state: EventInstanceState,
    /// Pending actions with execution frame
    pub pending_actions: Vec<PendingAction>,
    /// Active voice IDs created by this instance
    pub voice_ids: Vec<u32>,
    /// Callback function ID (for completion notification)
    pub callback_id: Option<u32>,
}

/// Event instance state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventInstanceState {
    /// Executing actions
    Playing,
    /// Paused
    Paused,
    /// Stopping (fading out)
    Stopping,
    /// Completed
    Stopped,
}

/// Action pending execution
#[derive(Debug, Clone)]
pub struct PendingAction {
    /// Action to execute
    pub action: MiddlewareAction,
    /// Frame at which to execute
    pub execute_at_frame: u64,
    /// Has been executed
    pub executed: bool,
}

impl EventInstance {
    /// Create new instance
    pub fn new(event_id: u32, game_object: GameObjectId, current_frame: u64) -> Self {
        Self {
            playing_id: generate_playing_id(),
            event_id,
            game_object,
            start_frame: current_frame,
            state: EventInstanceState::Playing,
            pending_actions: Vec::new(),
            voice_ids: Vec::new(),
            callback_id: None,
        }
    }

    /// Schedule actions from event definition
    pub fn schedule_actions(&mut self, event: &MiddlewareEvent, sample_rate: u32) {
        let frame_rate = sample_rate as f32;

        for action in &event.actions {
            let delay_frames = (action.delay * frame_rate) as u64;

            self.pending_actions.push(PendingAction {
                action: action.clone(),
                execute_at_frame: self.start_frame + delay_frames,
                executed: false,
            });
        }

        // Sort by execution time
        self.pending_actions.sort_by_key(|a| a.execute_at_frame);
    }

    /// Get next actions to execute at given frame
    pub fn get_actions_for_frame(&mut self, frame: u64) -> Vec<&MiddlewareAction> {
        self.pending_actions
            .iter_mut()
            .filter(|a| !a.executed && a.execute_at_frame <= frame)
            .map(|a| {
                a.executed = true;
                &a.action
            })
            .collect()
    }

    /// Check if all actions completed and all voices stopped
    pub fn is_complete(&self) -> bool {
        self.pending_actions.iter().all(|a| a.executed) &&
        self.voice_ids.is_empty()
    }
}
```

### 4.6 Rust: EventManager

```rust
// rf-event/src/lib.rs

use std::collections::HashMap;
use parking_lot::RwLock;
use rtrb::{Consumer, Producer, RingBuffer};

/// Command from UI thread to audio thread
#[derive(Debug, Clone)]
pub enum EventCommand {
    PostEvent {
        event_id: u32,
        game_object: GameObjectId,
    },
    StopEvent {
        playing_id: PlayingId,
        fade_ms: u32,
    },
    StopAll {
        game_object: Option<GameObjectId>,
        fade_ms: u32,
    },
    SetState {
        group_id: u32,
        state_id: u32,
    },
    SetSwitch {
        game_object: GameObjectId,
        group_id: u32,
        switch_id: u32,
    },
    SetRTPC {
        rtpc_id: u32,
        value: f32,
        game_object: Option<GameObjectId>,
        interpolation_ms: u32,
    },
    SetBusVolume {
        bus_id: u32,
        volume: f32,
        fade_ms: u32,
    },
}

/// Event manager - core of middleware system
pub struct EventManager {
    /// Event definitions
    events: RwLock<HashMap<u32, MiddlewareEvent>>,
    /// Event name to ID lookup
    event_names: RwLock<HashMap<String, u32>>,
    /// Active event instances
    instances: RwLock<Vec<EventInstance>>,
    /// Command queue (UI → Audio thread)
    command_rx: Consumer<EventCommand>,
    command_tx: Producer<EventCommand>,
    /// Current global states
    states: RwLock<HashMap<u32, u32>>,  // group_id → state_id
    /// Current switches per game object
    switches: RwLock<HashMap<(GameObjectId, u32), u32>>,  // (game_object, group_id) → switch_id
    /// Current RTPC values
    rtpcs: RwLock<HashMap<u32, f32>>,  // rtpc_id → value
    /// Sample rate
    sample_rate: u32,
    /// Current frame
    current_frame: u64,
}

impl EventManager {
    /// Create new event manager
    pub fn new(sample_rate: u32) -> Self {
        let (command_tx, command_rx) = RingBuffer::new(1024);

        Self {
            events: RwLock::new(HashMap::new()),
            event_names: RwLock::new(HashMap::new()),
            instances: RwLock::new(Vec::new()),
            command_rx,
            command_tx,
            states: RwLock::new(HashMap::new()),
            switches: RwLock::new(HashMap::new()),
            rtpcs: RwLock::new(HashMap::new()),
            sample_rate,
            current_frame: 0,
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EVENT REGISTRATION (Called from UI thread)
    // ═══════════════════════════════════════════════════════════════════════

    /// Register event definition
    pub fn register_event(&self, event: MiddlewareEvent) {
        let id = event.id;
        let name = event.name.clone();

        self.events.write().insert(id, event);
        self.event_names.write().insert(name, id);
    }

    /// Get event ID by name
    pub fn get_event_id(&self, name: &str) -> Option<u32> {
        self.event_names.read().get(name).copied()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // COMMAND POSTING (Called from UI/Game thread)
    // ═══════════════════════════════════════════════════════════════════════

    /// Post event (Wwise-style API)
    pub fn post_event(&self, event_id: u32, game_object: GameObjectId) -> Option<PlayingId> {
        // Queue command for audio thread
        if self.command_tx.push(EventCommand::PostEvent {
            event_id,
            game_object
        }).is_ok() {
            // Return a predicted playing ID (actual ID generated on audio thread)
            Some(generate_playing_id())
        } else {
            None
        }
    }

    /// Post event by name
    pub fn post_event_by_name(&self, name: &str, game_object: GameObjectId) -> Option<PlayingId> {
        if let Some(id) = self.get_event_id(name) {
            self.post_event(id, game_object)
        } else {
            None
        }
    }

    /// Stop event
    pub fn stop_event(&self, playing_id: PlayingId, fade_ms: u32) {
        let _ = self.command_tx.push(EventCommand::StopEvent {
            playing_id,
            fade_ms
        });
    }

    /// Stop all events
    pub fn stop_all(&self, game_object: Option<GameObjectId>, fade_ms: u32) {
        let _ = self.command_tx.push(EventCommand::StopAll {
            game_object,
            fade_ms
        });
    }

    /// Set state
    pub fn set_state(&self, group_id: u32, state_id: u32) {
        let _ = self.command_tx.push(EventCommand::SetState {
            group_id,
            state_id
        });
    }

    /// Set switch
    pub fn set_switch(&self, game_object: GameObjectId, group_id: u32, switch_id: u32) {
        let _ = self.command_tx.push(EventCommand::SetSwitch {
            game_object,
            group_id,
            switch_id
        });
    }

    /// Set RTPC
    pub fn set_rtpc(&self, rtpc_id: u32, value: f32, game_object: Option<GameObjectId>, interpolation_ms: u32) {
        let _ = self.command_tx.push(EventCommand::SetRTPC {
            rtpc_id,
            value,
            game_object,
            interpolation_ms
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO THREAD PROCESSING
    // ═══════════════════════════════════════════════════════════════════════

    /// Process commands and update instances (called from audio thread)
    pub fn process(&mut self, num_frames: u64) {
        // 1. Process pending commands
        self.process_commands();

        // 2. Update current frame
        self.current_frame += num_frames;

        // 3. Execute pending actions in instances
        self.execute_pending_actions();

        // 4. Cleanup completed instances
        self.cleanup_instances();
    }

    fn process_commands(&mut self) {
        while let Ok(cmd) = self.command_rx.pop() {
            match cmd {
                EventCommand::PostEvent { event_id, game_object } => {
                    self.execute_post_event(event_id, game_object);
                }
                EventCommand::StopEvent { playing_id, fade_ms } => {
                    self.execute_stop_event(playing_id, fade_ms);
                }
                EventCommand::StopAll { game_object, fade_ms } => {
                    self.execute_stop_all(game_object, fade_ms);
                }
                EventCommand::SetState { group_id, state_id } => {
                    self.states.write().insert(group_id, state_id);
                }
                EventCommand::SetSwitch { game_object, group_id, switch_id } => {
                    self.switches.write().insert((game_object, group_id), switch_id);
                }
                EventCommand::SetRTPC { rtpc_id, value, .. } => {
                    self.rtpcs.write().insert(rtpc_id, value);
                }
                EventCommand::SetBusVolume { .. } => {
                    // TODO: Implement bus volume control
                }
            }
        }
    }

    fn execute_post_event(&mut self, event_id: u32, game_object: GameObjectId) {
        if let Some(event) = self.events.read().get(&event_id).cloned() {
            let mut instance = EventInstance::new(event_id, game_object, self.current_frame);
            instance.schedule_actions(&event, self.sample_rate);
            self.instances.write().push(instance);
        }
    }

    fn execute_stop_event(&mut self, playing_id: PlayingId, _fade_ms: u32) {
        let mut instances = self.instances.write();
        if let Some(instance) = instances.iter_mut().find(|i| i.playing_id == playing_id) {
            instance.state = EventInstanceState::Stopping;
            // TODO: Apply fade to voices
        }
    }

    fn execute_stop_all(&mut self, game_object: Option<GameObjectId>, _fade_ms: u32) {
        let mut instances = self.instances.write();
        for instance in instances.iter_mut() {
            if game_object.is_none() || Some(instance.game_object) == game_object {
                instance.state = EventInstanceState::Stopping;
            }
        }
    }

    fn execute_pending_actions(&mut self) {
        let mut instances = self.instances.write();

        for instance in instances.iter_mut() {
            if instance.state != EventInstanceState::Playing {
                continue;
            }

            let actions = instance.get_actions_for_frame(self.current_frame);

            for action in actions {
                self.execute_action(action, instance.game_object);
            }
        }
    }

    fn execute_action(&self, action: &MiddlewareAction, game_object: GameObjectId) {
        match action.action_type {
            ActionType::Play => {
                // TODO: Allocate voice and start playback
                log::debug!("Execute Play: asset={:?}, bus={}", action.asset_id, action.bus_id);
            }
            ActionType::Stop => {
                // TODO: Stop voices matching criteria
                log::debug!("Execute Stop: asset={:?}", action.asset_id);
            }
            ActionType::SetVolume => {
                // TODO: Set bus volume
                log::debug!("Execute SetVolume: bus={}, gain={}", action.bus_id, action.gain);
            }
            ActionType::SetState => {
                if let (Some(group), Some(value)) = (action.group_id, action.value_id) {
                    self.states.write().insert(group, value);
                }
            }
            ActionType::SetSwitch => {
                if let (Some(group), Some(value)) = (action.group_id, action.value_id) {
                    self.switches.write().insert((game_object, group), value);
                }
            }
            ActionType::SetRTPC => {
                if let (Some(rtpc), Some(value)) = (action.rtpc_id, action.rtpc_value) {
                    self.rtpcs.write().insert(rtpc, value);
                }
            }
            ActionType::PostEvent => {
                if let Some(target_event) = action.target_event_id {
                    self.execute_post_event(target_event, game_object);
                }
            }
            _ => {
                log::debug!("Execute action: {:?}", action.action_type);
            }
        }
    }

    fn cleanup_instances(&mut self) {
        self.instances.write().retain(|i| {
            i.state != EventInstanceState::Stopped && !i.is_complete()
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // QUERY (Thread-safe)
    // ═══════════════════════════════════════════════════════════════════════

    /// Get current state value
    pub fn get_state(&self, group_id: u32) -> Option<u32> {
        self.states.read().get(&group_id).copied()
    }

    /// Get current switch value for game object
    pub fn get_switch(&self, game_object: GameObjectId, group_id: u32) -> Option<u32> {
        self.switches.read().get(&(game_object, group_id)).copied()
    }

    /// Get current RTPC value
    pub fn get_rtpc(&self, rtpc_id: u32) -> Option<f32> {
        self.rtpcs.read().get(&rtpc_id).copied()
    }

    /// Get active instance count
    pub fn active_instances(&self) -> usize {
        self.instances.read().len()
    }
}
```

### 4.7 FFI Bridge Functions

```rust
// rf-bridge/src/middleware_ffi.rs

use std::ffi::{c_char, CStr};
use rf_event::{EventManager, GameObjectId, PlayingId};

static mut EVENT_MANAGER: Option<EventManager> = None;

/// Initialize event manager
#[no_mangle]
pub extern "C" fn middleware_init(sample_rate: u32) -> i32 {
    unsafe {
        EVENT_MANAGER = Some(EventManager::new(sample_rate));
    }
    1
}

/// Post event by ID
#[no_mangle]
pub extern "C" fn middleware_post_event(event_id: u32, game_object: u64) -> u64 {
    unsafe {
        EVENT_MANAGER
            .as_ref()
            .and_then(|mgr| mgr.post_event(event_id, game_object))
            .unwrap_or(0)
    }
}

/// Post event by name
#[no_mangle]
pub extern "C" fn middleware_post_event_by_name(
    name: *const c_char,
    game_object: u64,
) -> u64 {
    let name = unsafe { CStr::from_ptr(name).to_str().unwrap_or("") };
    unsafe {
        EVENT_MANAGER
            .as_ref()
            .and_then(|mgr| mgr.post_event_by_name(name, game_object))
            .unwrap_or(0)
    }
}

/// Stop event
#[no_mangle]
pub extern "C" fn middleware_stop_event(playing_id: u64, fade_ms: u32) {
    unsafe {
        if let Some(mgr) = EVENT_MANAGER.as_ref() {
            mgr.stop_event(playing_id, fade_ms);
        }
    }
}

/// Stop all events
#[no_mangle]
pub extern "C" fn middleware_stop_all(game_object: u64, fade_ms: u32) {
    let go = if game_object == 0 { None } else { Some(game_object) };
    unsafe {
        if let Some(mgr) = EVENT_MANAGER.as_ref() {
            mgr.stop_all(go, fade_ms);
        }
    }
}

/// Set state
#[no_mangle]
pub extern "C" fn middleware_set_state(group_id: u32, state_id: u32) {
    unsafe {
        if let Some(mgr) = EVENT_MANAGER.as_ref() {
            mgr.set_state(group_id, state_id);
        }
    }
}

/// Set switch
#[no_mangle]
pub extern "C" fn middleware_set_switch(game_object: u64, group_id: u32, switch_id: u32) {
    unsafe {
        if let Some(mgr) = EVENT_MANAGER.as_ref() {
            mgr.set_switch(game_object, group_id, switch_id);
        }
    }
}

/// Set RTPC
#[no_mangle]
pub extern "C" fn middleware_set_rtpc(
    rtpc_id: u32,
    value: f32,
    game_object: u64,
    interpolation_ms: u32,
) {
    let go = if game_object == 0 { None } else { Some(game_object) };
    unsafe {
        if let Some(mgr) = EVENT_MANAGER.as_ref() {
            mgr.set_rtpc(rtpc_id, value, go, interpolation_ms);
        }
    }
}

/// Process events (called from audio callback)
#[no_mangle]
pub extern "C" fn middleware_process(num_frames: u64) {
    unsafe {
        if let Some(mgr) = EVENT_MANAGER.as_mut() {
            mgr.process(num_frames);
        }
    }
}

/// Get active instance count
#[no_mangle]
pub extern "C" fn middleware_active_instances() -> u32 {
    unsafe {
        EVENT_MANAGER
            .as_ref()
            .map(|mgr| mgr.active_instances() as u32)
            .unwrap_or(0)
    }
}
```

---

## 5. POREĐENJE

### 5.1 FluxForge vs Wwise Event System

| Feature | FluxForge (Planirano) | Wwise |
|---------|----------------------|-------|
| **PostEvent API** | ✅ | ✅ |
| **Action Types** | 22 types | 30+ types |
| **Action Delay** | ✅ Sample-accurate | ✅ |
| **Fade Curves** | 8 types | 9 types |
| **Priority System** | 7 levels | 100 levels |
| **Game Object Scope** | ✅ | ✅ |
| **State Groups** | ✅ | ✅ |
| **Switch Groups** | ✅ | ✅ |
| **RTPC** | Basic | Full (curves, ranges) |
| **Event Callbacks** | Basic | Comprehensive |
| **Nested Events** | ✅ PostEvent action | ✅ |
| **Random Containers** | ❌ | ✅ |
| **Sequence Containers** | ❌ | ✅ |
| **Blend Containers** | ❌ | ✅ |
| **Interactive Music** | ❌ | ✅ Full system |

### 5.2 Missing Advanced Features

1. **Random/Sequence/Blend Containers** — Container types za varijacije
2. **Interactive Music System** — Stingers, transitions, segments
3. **Dialogue System** — Dynamic path evaluation
4. **RTPC Curves** — Multi-point curves with different shapes
5. **3D Positioning** — Emitter/listener model
6. **Obstruction/Occlusion** — Raycast-based audio blocking

---

## 6. IMPLEMENTATION ROADMAP

### Phase 1: Core Event System ✅ COMPLETED
- [x] Create `rf-event` crate
- [x] Implement `ActionType`, `FadeCurve`, `ActionScope`, `ActionPriority`
- [x] Implement `MiddlewareAction`, `MiddlewareEvent`
- [x] Implement `EventInstance`, `PendingAction`
- [x] Implement `EventManagerHandle` + `EventManagerProcessor` (split design)

### Phase 2: FFI Bridge ✅ COMPLETED
- [x] Add FFI exports to `rf-bridge` (`middleware_ffi.rs`)
- [x] Add Dart bindings in `native_ffi.dart`
- [x] Connect Dart `MiddlewareEvent` to Rust

### Phase 3: Integration ✅ COMPLETED
- [x] Connect EventManager to existing audio engine
- [x] Implement Play action (voice allocation)
- [x] Implement Stop action (with fade)
- [x] Implement SetVolume/SetBusVolume

### Phase 4: State/Switch ✅ COMPLETED (2026-01-16)
- [x] Implement State groups (Rust + Dart)
- [x] Implement Switch groups (Rust + Dart)
- [x] Add state-aware playback with conditional actions
- [x] `MiddlewareProvider` for UI state management

### Phase 5: RTPC ✅ COMPLETED (2026-01-16)
- [x] Implement RTPC storage
- [x] Implement RTPC interpolation (slew rate)
- [x] Per-object RTPC overrides
- [x] Multi-point curves (`RtpcCurve`, `RtpcCurvePoint`)
- [x] RTPC → Parameter bindings (`RtpcBinding`, `RtpcTargetParameter`)

**Total implementation:** ~5000+ LOC (Rust + Dart)

---

## 7. CURRENT STATUS ✅ FULLY IMPLEMENTED

| Komponenta | Status | LOC |
|------------|--------|-----|
| **`rf-event` crate** | ✅ Kompletno | ~2000 |
| **Rust FFI Bridge** | ✅ Kompletno | ~800 |
| **Dart Models** | ✅ Kompletno | ~1000 |
| **Dart Provider** | ✅ Kompletno | ~550 |
| **Conditional Actions** | ✅ Kompletno | ~200 |

### Implementirane Funkcionalnosti

#### Event System
- `PostEvent(eventId, gameObjectId)` → PlayingId
- `StopEvent(playingId, fadeMs)`
- `StopAll(gameObjectId?, fadeMs)`
- `PauseEvent` / `ResumeEvent`
- Event instance lifecycle (Playing → Stopping → Stopped)
- Max instances per event (DiscardNewest, DiscardOldest, IgnoreLimit)
- Callback system (`EventStarted`, `EventEnded`)

#### Actions (23 tipova)
- Play, PlayAndContinue, Stop, StopAll
- Pause, PauseAll, Resume, ResumeAll
- Break, Mute, Unmute
- SetVolume, SetPitch, SetLPF, SetHPF, SetBusVolume
- SetState, SetSwitch, SetRTPC, ResetRTPC
- Seek, Trigger, PostEvent

#### State/Switch
- StateGroup sa transition time
- SwitchGroup per-game-object
- State-aware conditional actions
- Switch-aware conditional actions

#### RTPC
- Global + per-object values
- Interpolation modes (None, Linear, Exponential, SlewRate)
- Multi-point curves (9 curve shapes)
- Parameter bindings (Volume, Pitch, LPF, HPF, Pan, BusVolume, etc.)

---

## 8. PRIORITET ZA DALJE

Event system je **KOMPLETIRAN**. Sledeći koraci:

1. **UI Widgets** — Vizualni editor za evente, state grupe, RTPC curve
2. **Asset Pipeline** — Povezivanje sa audio file loading
3. **Profiler** — Voice count, CPU usage, RTPC real-time display
4. **Bank System** — Wwise-style SoundBank loading

---

*Analiza ažurirana: 2026-01-16*
*Phase 1-5: COMPLETED*
*Chief Audio Architect / Lead DSP Engineer / Engine Architect*
