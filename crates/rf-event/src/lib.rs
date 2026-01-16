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
pub use instance::{EventInstance, EventInstanceState, PendingAction, PlayingId, GameObjectId};
pub use manager::{
    EventCommand, EventManagerHandle, EventManagerProcessor, ExecutedAction,
    create_event_manager,
};
pub use state::{
    StateGroup, SwitchGroup, RtpcDefinition,
    RtpcCurve, RtpcCurvePoint, RtpcCurveShape, RtpcInterpolation,
    RtpcBinding, RtpcTargetParameter,
    // Ducking
    DuckingRule, DuckingCurve, DuckingMatrix, DuckingState,
    // Blend Container
    BlendChild, BlendContainer, CrossfadeCurve,
    // Randomization
    RandomChild, RandomContainer, RandomMode, RandomContainerState,
    // Sequence Container
    SequenceStep, SequenceContainer, SequenceEndBehavior, SequenceContainerState,
    // Music System
    MusicSyncPoint, Stinger, MusicSegment, MusicMarker, MarkerType, MusicSystem,
    // Attenuation
    AttenuationType, AttenuationCurve, AttenuationSystem,
};
