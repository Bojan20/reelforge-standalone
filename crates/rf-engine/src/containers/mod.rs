//! Container System - Wwise/FMOD-style Audio Containers
//!
//! Provides four container types for advanced audio playback:
//! - **BlendContainer**: RTPC-based crossfade between sounds
//! - **RandomContainer**: Weighted random selection with variation
//! - **SequenceContainer**: Timed sound sequences
//! - **ContainerGroup**: Hierarchical nesting of containers (P3C)
//!
//! ## Architecture
//!
//! ```text
//! Container (Rust)          FFI Bridge          Dart Provider
//! ────────────────          ──────────          ─────────────
//! BlendContainer  ←──────→  container_ffi  ←──→  BlendContainersProvider
//! RandomContainer ←──────→  container_ffi  ←──→  RandomContainersProvider
//! SequenceContainer ←────→  container_ffi  ←──→  SequenceContainersProvider
//! ContainerGroup ←────────→  container_ffi  ←──→  (TODO: GroupProvider)
//! ```
//!
//! ## Performance
//!
//! Container evaluation is < 1ms (vs 5-10ms in Dart):
//! - Lock-free storage via DashMap
//! - Pre-computed crossfade curves
//! - XorShift RNG for random selection
//! - Microsecond-accurate sequence timing

mod blend;
mod group;
mod random;
mod sequence;
mod storage;

pub use blend::{BlendChild, BlendContainer, BlendCurve, BlendResult};
pub use group::{ContainerGroup, GroupChild, GroupChildRef, GroupEvaluationMode, GroupResult};
pub use random::{
    RandomChild, RandomContainer, RandomMode, RandomResult, RandomVariation,
};
pub use sequence::{
    SequenceContainer, SequenceEndBehavior, SequenceResult, SequenceState, SequenceStep,
};
pub use storage::ContainerStorage;

/// Container type enumeration
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum ContainerType {
    /// No container (direct playback)
    None = 0,
    /// RTPC-based crossfade
    Blend = 1,
    /// Weighted random selection
    Random = 2,
    /// Timed sequence
    Sequence = 3,
    /// Hierarchical group (P3C)
    Group = 4,
}

impl ContainerType {
    /// Create from integer value
    pub fn from_u8(value: u8) -> Self {
        match value {
            1 => ContainerType::Blend,
            2 => ContainerType::Random,
            3 => ContainerType::Sequence,
            4 => ContainerType::Group,
            _ => ContainerType::None,
        }
    }
}

impl Default for ContainerType {
    fn default() -> Self {
        ContainerType::None
    }
}

/// Container ID type (unique per container type)
pub type ContainerId = u32;

/// Child ID type (unique within a container)
pub type ChildId = u32;

/// Common container trait
pub trait Container: Send + Sync {
    /// Get container ID
    fn id(&self) -> ContainerId;

    /// Get container name
    fn name(&self) -> &str;

    /// Check if container is enabled
    fn is_enabled(&self) -> bool;

    /// Get container type
    fn container_type(&self) -> ContainerType;

    /// Get number of children/steps
    fn child_count(&self) -> usize;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_container_type_from_u8() {
        assert_eq!(ContainerType::from_u8(0), ContainerType::None);
        assert_eq!(ContainerType::from_u8(1), ContainerType::Blend);
        assert_eq!(ContainerType::from_u8(2), ContainerType::Random);
        assert_eq!(ContainerType::from_u8(3), ContainerType::Sequence);
        assert_eq!(ContainerType::from_u8(4), ContainerType::Group);
        assert_eq!(ContainerType::from_u8(255), ContainerType::None);
    }
}
