pub mod timeline;
pub mod tracks;
pub mod bake;
pub mod project;

pub use timeline::{
    DualTimeline, MusicalTimeline, GameplayTimeline,
    TimelineMarker, MarkerType, MusicalPosition, GameplayPosition,
    TimeSignature, TempoChange,
};
pub use tracks::{
    GadTrack, GadTrackType, TrackMetadata, TrackState,
    CanonicalEventBinding, VoicePriorityClass,
};
pub use bake::{
    BakeToSlot, BakeStep, BakeStepStatus, BakeResult,
    BakeConfig, BakeError, StemOutput,
};
pub use project::{
    GadProject, GadProjectConfig, GadTrackLayout,
};
