pub mod bake;
pub mod project;
pub mod timeline;
pub mod tracks;

pub use bake::{
    BakeConfig, BakeError, BakeResult, BakeStep, BakeStepStatus, BakeToSlot, StemOutput,
};
pub use project::{GadProject, GadProjectConfig, GadTrackLayout};
pub use timeline::{
    DualTimeline, GameplayPosition, GameplayTimeline, MarkerType, MusicalPosition, MusicalTimeline,
    TempoChange, TimeSignature, TimelineMarker,
};
pub use tracks::{
    CanonicalEventBinding, GadTrack, GadTrackType, TrackMetadata, TrackState, VoicePriorityClass,
};
