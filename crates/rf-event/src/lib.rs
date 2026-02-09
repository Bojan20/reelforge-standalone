//! FluxForge Middleware Event System
//!
//! Wwise/FMOD-style event system for game audio integration:
//! - Event definitions with multiple actions
//! - PostEvent API for triggering sounds
//! - State and Switch groups
//! - RTPC (Real-Time Parameter Control)
//! - Lock-free command queue for audio thread safety
//!
//! ## Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                    EVENT SYSTEM ARCHITECTURE                     │
//! ├─────────────────────────────────────────────────────────────────┤
//! │                                                                  │
//! │   Game/UI Thread                      Audio Thread               │
//! │   ┌─────────────────┐                ┌─────────────────┐        │
//! │   │ post_event()    │                │ EventManager    │        │
//! │   │ set_state()     │───Command──────▶│ .process()     │        │
//! │   │ set_switch()    │   Queue        │                 │        │
//! │   │ set_rtpc()      │  (lock-free)   │ Execute actions │        │
//! │   └─────────────────┘                └─────────────────┘        │
//! │                                                                  │
//! │   ┌─────────────────────────────────────────────────────────┐   │
//! │   │                    Event Definition                      │   │
//! │   │  ┌─────────────────────────────────────────────────┐    │   │
//! │   │  │ Event: "BigWin_Start"                            │    │   │
//! │   │  │ ├── Action: SetVolume(Music, 0.3, fade: 200ms)  │    │   │
//! │   │  │ ├── Action: Play(sfx_jackpot, bus: Wins)        │    │   │
//! │   │  │ └── Action: Play(vo_bigwin, delay: 500ms)       │    │   │
//! │   │  └─────────────────────────────────────────────────┘    │   │
//! │   └─────────────────────────────────────────────────────────┘   │
//! │                                                                  │
//! └─────────────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_event::{EventManager, MiddlewareEvent, MiddlewareAction, ActionType};
//!
//! // Create manager
//! let mut manager = EventManager::new(48000);
//!
//! // Register event
//! let mut event = MiddlewareEvent::new(1, "Play_Music");
//! event.add_action(MiddlewareAction::play(100, 0).with_loop(true));
//! manager.register_event(event);
//!
//! // Post event (from game thread)
//! let playing_id = manager.post_event(1, 0);
//!
//! // Process in audio callback
//! manager.process(256);
//! ```

#![allow(clippy::new_without_default)]

pub mod action;
pub mod curve;
pub mod event;
pub mod instance;
pub mod manager;
pub mod state;

// Re-exports
pub use action::{ActionPriority, ActionScope, ActionType, MiddlewareAction};
pub use curve::FadeCurve;
pub use event::MiddlewareEvent;
pub use instance::{EventInstance, EventInstanceState, GameObjectId, PendingAction, PlayingId};
pub use manager::{
    EventCommand, EventManagerHandle, EventManagerProcessor, ExecutedAction, create_event_manager,
};
pub use state::{
    AttenuationCurve,
    AttenuationSystem,
    // Attenuation
    AttenuationType,
    // Blend Container
    BlendChild,
    BlendContainer,
    CrossfadeCurve,
    DuckingCurve,
    DuckingMatrix,
    // Ducking
    DuckingRule,
    DuckingState,
    MarkerType,
    MusicMarker,
    MusicSegment,
    // Music System
    MusicSyncPoint,
    MusicSystem,
    // Randomization
    RandomChild,
    RandomContainer,
    RandomContainerState,
    RandomMode,
    RtpcBinding,
    RtpcCurve,
    RtpcCurvePoint,
    RtpcCurveShape,
    RtpcDefinition,
    RtpcInterpolation,
    RtpcTargetParameter,
    SequenceContainer,
    SequenceContainerState,
    SequenceEndBehavior,
    // Sequence Container
    SequenceStep,
    StateGroup,
    Stinger,
    SwitchGroup,
};
