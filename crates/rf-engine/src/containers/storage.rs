//! Container Storage - Lock-Free Container Management
//!
//! Provides thread-safe storage for containers using DashMap for lock-free access.
//! Supports concurrent reads from audio thread while UI thread updates containers.

use super::{
    BlendContainer, BlendResult, ChildId, Container, ContainerId, ContainerType, RandomContainer,
    RandomResult, SequenceContainer, SequenceResult, ContainerGroup,
    group::{ContainerLookup, ValidationResult, ValidationError, validate_group_addition},
};
use dashmap::DashMap;
use std::sync::atomic::{AtomicU32, Ordering};

/// Thread-safe container storage
pub struct ContainerStorage {
    /// Blend containers
    blend: DashMap<ContainerId, BlendContainer>,
    /// Random containers
    random: DashMap<ContainerId, RandomContainer>,
    /// Sequence containers
    sequence: DashMap<ContainerId, SequenceContainer>,
    /// Container groups (P3C)
    group: DashMap<ContainerId, ContainerGroup>,
    /// Next container ID
    next_id: AtomicU32,
}

impl ContainerStorage {
    /// Create new empty storage
    pub fn new() -> Self {
        Self {
            blend: DashMap::new(),
            random: DashMap::new(),
            sequence: DashMap::new(),
            group: DashMap::new(),
            next_id: AtomicU32::new(1),
        }
    }

    /// Generate next unique container ID
    pub fn next_id(&self) -> ContainerId {
        self.next_id.fetch_add(1, Ordering::Relaxed)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BLEND CONTAINERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Insert or update a blend container
    pub fn insert_blend(&self, container: BlendContainer) {
        self.blend.insert(container.id, container);
    }

    /// Get blend container by ID (cloned)
    pub fn get_blend(&self, id: ContainerId) -> Option<BlendContainer> {
        self.blend.get(&id).map(|c| c.clone())
    }

    /// Remove blend container
    pub fn remove_blend(&self, id: ContainerId) -> Option<BlendContainer> {
        self.blend.remove(&id).map(|(_, c)| c)
    }

    /// Evaluate blend container at given RTPC value
    /// Returns None if container doesn't exist or is disabled
    pub fn evaluate_blend(&self, id: ContainerId, rtpc: f64) -> Option<BlendResult> {
        self.blend.get(&id).and_then(|container| {
            if container.is_enabled() {
                Some(container.evaluate_at(rtpc))
            } else {
                None
            }
        })
    }

    /// Update RTPC value for a blend container (instant)
    pub fn set_blend_rtpc(&self, id: ContainerId, rtpc: f64) {
        if let Some(mut container) = self.blend.get_mut(&id) {
            container.set_rtpc(rtpc);
        }
    }

    /// Set RTPC target value for smoothed interpolation (P3D)
    pub fn set_blend_rtpc_target(&self, id: ContainerId, rtpc: f64) {
        if let Some(mut container) = self.blend.get_mut(&id) {
            container.set_rtpc_target(rtpc);
        }
    }

    /// Set smoothing time in milliseconds (P3D)
    pub fn set_blend_smoothing(&self, id: ContainerId, smoothing_ms: f64) {
        if let Some(mut container) = self.blend.get_mut(&id) {
            container.set_smoothing_ms(smoothing_ms);
        }
    }

    /// Tick smoothing by delta milliseconds (P3D)
    /// Returns Some(true) if value changed, Some(false) if unchanged, None if container not found
    pub fn tick_blend_smoothing(&self, id: ContainerId, delta_ms: f64) -> Option<bool> {
        self.blend.get_mut(&id).map(|mut container| {
            container.tick_smoothing(delta_ms)
        })
    }

    /// Get blend child audio path
    pub fn get_blend_child_audio_path(
        &self,
        container_id: ContainerId,
        child_id: ChildId,
    ) -> Option<String> {
        self.blend.get(&container_id).and_then(|container| {
            container
                .get_child(child_id)
                .and_then(|c| c.audio_path.clone())
        })
    }

    /// Get blend container count
    pub fn blend_count(&self) -> usize {
        self.blend.len()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RANDOM CONTAINERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Insert or update a random container
    pub fn insert_random(&self, container: RandomContainer) {
        self.random.insert(container.id, container);
    }

    /// Get random container by ID (cloned)
    pub fn get_random(&self, id: ContainerId) -> Option<RandomContainer> {
        self.random.get(&id).map(|c| c.clone())
    }

    /// Remove random container
    pub fn remove_random(&self, id: ContainerId) -> Option<RandomContainer> {
        self.random.remove(&id).map(|(_, c)| c)
    }

    /// Select from random container (mutates internal state)
    pub fn select_random(&self, id: ContainerId) -> Option<RandomResult> {
        self.random.get_mut(&id).and_then(|mut container| {
            if container.is_enabled() {
                container.select()
            } else {
                None
            }
        })
    }

    /// Get random child audio path
    pub fn get_random_child_audio_path(
        &self,
        container_id: ContainerId,
        child_id: ChildId,
    ) -> Option<String> {
        self.random.get(&container_id).and_then(|container| {
            container
                .get_child(child_id)
                .and_then(|c| c.audio_path.clone())
        })
    }

    /// Seed random container RNG
    pub fn seed_random(&self, id: ContainerId, seed: u64) {
        if let Some(mut container) = self.random.get_mut(&id) {
            container.seed(seed);
        }
    }

    /// Reset random container state
    pub fn reset_random(&self, id: ContainerId) {
        if let Some(mut container) = self.random.get_mut(&id) {
            container.reset_state();
        }
    }

    /// Get RNG state from random container (for determinism capture)
    pub fn get_random_rng_state(&self, id: ContainerId) -> Option<u64> {
        self.random.get(&id).map(|container| container.get_rng_state())
    }

    /// Set RNG state on random container (for determinism replay)
    pub fn set_random_rng_state(&self, id: ContainerId, state: u64) -> bool {
        if let Some(mut container) = self.random.get_mut(&id) {
            container.set_rng_state(state);
            true
        } else {
            false
        }
    }

    /// Get random container count
    pub fn random_count(&self) -> usize {
        self.random.len()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SEQUENCE CONTAINERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Insert or update a sequence container
    pub fn insert_sequence(&self, container: SequenceContainer) {
        self.sequence.insert(container.id, container);
    }

    /// Get sequence container by ID (cloned)
    pub fn get_sequence(&self, id: ContainerId) -> Option<SequenceContainer> {
        self.sequence.get(&id).map(|c| c.clone())
    }

    /// Remove sequence container
    pub fn remove_sequence(&self, id: ContainerId) -> Option<SequenceContainer> {
        self.sequence.remove(&id).map(|(_, c)| c)
    }

    /// Start sequence playback
    pub fn play_sequence(&self, id: ContainerId) {
        if let Some(mut container) = self.sequence.get_mut(&id) {
            container.play();
        }
    }

    /// Stop sequence playback
    pub fn stop_sequence(&self, id: ContainerId) {
        if let Some(mut container) = self.sequence.get_mut(&id) {
            container.stop();
        }
    }

    /// Pause sequence playback
    pub fn pause_sequence(&self, id: ContainerId) {
        if let Some(mut container) = self.sequence.get_mut(&id) {
            container.pause();
        }
    }

    /// Resume sequence playback
    pub fn resume_sequence(&self, id: ContainerId) {
        if let Some(mut container) = self.sequence.get_mut(&id) {
            container.resume();
        }
    }

    /// Tick sequence by delta milliseconds
    pub fn tick_sequence(&self, id: ContainerId, delta_ms: f64) -> Option<SequenceResult> {
        self.sequence.get_mut(&id).map(|mut container| container.tick(delta_ms))
    }

    /// Get sequence step audio path
    pub fn get_sequence_step_audio_path(
        &self,
        container_id: ContainerId,
        step_index: usize,
    ) -> Option<String> {
        self.sequence.get(&container_id).and_then(|container| {
            container
                .get_step(step_index)
                .and_then(|s| s.audio_path.clone())
        })
    }

    /// Check if sequence is playing
    pub fn is_sequence_playing(&self, id: ContainerId) -> bool {
        self.sequence
            .get(&id)
            .map(|c| c.is_playing())
            .unwrap_or(false)
    }

    /// Get sequence container count
    pub fn sequence_count(&self) -> usize {
        self.sequence.len()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GLOBAL OPERATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get total container count
    pub fn total_count(&self) -> usize {
        self.blend_count() + self.random_count() + self.sequence_count() + self.group_count()
    }

    /// Clear all containers
    pub fn clear(&self) {
        self.blend.clear();
        self.random.clear();
        self.sequence.clear();
        self.group.clear();
    }

    /// Check if container exists by type and ID
    pub fn exists(&self, container_type: ContainerType, id: ContainerId) -> bool {
        match container_type {
            ContainerType::None => false,
            ContainerType::Blend => self.blend.contains_key(&id),
            ContainerType::Random => self.random.contains_key(&id),
            ContainerType::Sequence => self.sequence.contains_key(&id),
            ContainerType::Group => self.group.contains_key(&id),
        }
    }

    /// Get container name by type and ID
    pub fn get_name(&self, container_type: ContainerType, id: ContainerId) -> Option<String> {
        match container_type {
            ContainerType::None => None,
            ContainerType::Blend => self.blend.get(&id).map(|c| c.name.clone()),
            ContainerType::Random => self.random.get(&id).map(|c| c.name.clone()),
            ContainerType::Sequence => self.sequence.get(&id).map(|c| c.name.clone()),
            ContainerType::Group => self.group.get(&id).map(|c| c.name.clone()),
        }
    }

    /// Get child count for container
    pub fn get_child_count(&self, container_type: ContainerType, id: ContainerId) -> usize {
        match container_type {
            ContainerType::None => 0,
            ContainerType::Blend => self.blend.get(&id).map(|c| c.children.len()).unwrap_or(0),
            ContainerType::Random => self.random.get(&id).map(|c| c.children.len()).unwrap_or(0),
            ContainerType::Sequence => self.sequence.get(&id).map(|c| c.steps.len()).unwrap_or(0),
            ContainerType::Group => self.group.get(&id).map(|c| c.children.len()).unwrap_or(0),
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONTAINER GROUPS (P3C)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Insert or update a container group
    pub fn insert_group(&self, group: ContainerGroup) {
        self.group.insert(group.id, group);
    }

    /// Get group by ID (cloned)
    pub fn get_group(&self, id: ContainerId) -> Option<ContainerGroup> {
        self.group.get(&id).map(|g| g.clone())
    }

    /// Remove group
    pub fn remove_group(&self, id: ContainerId) -> Option<ContainerGroup> {
        self.group.remove(&id).map(|(_, g)| g)
    }

    /// Get group count
    pub fn group_count(&self) -> usize {
        self.group.len()
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Validate a group with full depth and cycle checking
    pub fn validate_group(&self, id: ContainerId) -> Option<ValidationResult> {
        self.group.get(&id).map(|g| g.validate(self))
    }

    /// Validate all groups in storage
    pub fn validate_all_groups(&self) -> Vec<(ContainerId, ValidationResult)> {
        self.group
            .iter()
            .map(|entry| (*entry.key(), entry.value().validate(self)))
            .collect()
    }

    /// Check if adding a child to a group would be valid
    pub fn validate_group_child_addition(
        &self,
        group_id: ContainerId,
        child_type: ContainerType,
        child_id: ContainerId,
    ) -> Result<(), ValidationError> {
        validate_group_addition(group_id, child_type, child_id, self)
    }

    /// Insert group with validation (returns error if invalid)
    pub fn insert_group_validated(&self, group: ContainerGroup) -> Result<(), ValidationError> {
        // Validate local constraints first
        group.validate_local()?;

        // Full validation
        let result = group.validate(self);
        if !result.valid {
            return Err(result.errors.into_iter().next().unwrap());
        }

        self.group.insert(group.id, group);
        Ok(())
    }

    /// Add child to group with validation
    pub fn add_group_child_validated(
        &self,
        group_id: ContainerId,
        child_type: ContainerType,
        child_id: ContainerId,
        name: impl Into<String>,
    ) -> Result<(), ValidationError> {
        // Pre-validate the addition
        self.validate_group_child_addition(group_id, child_type, child_id)?;

        // Add the child
        if let Some(mut group) = self.group.get_mut(&group_id) {
            group.add_child(super::group::GroupChild::new(child_type, child_id, name));
            Ok(())
        } else {
            Err(ValidationError::MissingContainer {
                container_type: ContainerType::Group,
                container_id: group_id,
            })
        }
    }
}

// =============================================================================
// CONTAINER LOOKUP IMPLEMENTATION
// =============================================================================

impl ContainerLookup for ContainerStorage {
    fn group_exists(&self, id: ContainerId) -> bool {
        self.group.contains_key(&id)
    }

    fn get_group_children(&self, id: ContainerId) -> Option<Vec<(ContainerType, ContainerId)>> {
        self.group.get(&id).map(|g| {
            g.children
                .iter()
                .map(|c| (c.container_type, c.container_id))
                .collect()
        })
    }

    fn container_exists(&self, ctype: ContainerType, id: ContainerId) -> bool {
        self.exists(ctype, id)
    }
}

impl Default for ContainerStorage {
    fn default() -> Self {
        Self::new()
    }
}

// Safety: DashMap is thread-safe, atomics are thread-safe
unsafe impl Send for ContainerStorage {}
unsafe impl Sync for ContainerStorage {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::containers::{BlendChild, RandomChild, SequenceStep};

    #[test]
    fn test_storage_blend() {
        let storage = ContainerStorage::new();

        let mut container = BlendContainer::new(1, "test_blend");
        container.add_child(BlendChild::new(1, "child1", 0.0, 0.5));
        container.add_child(BlendChild::new(2, "child2", 0.4, 1.0));

        storage.insert_blend(container);

        assert_eq!(storage.blend_count(), 1);
        assert!(storage.exists(ContainerType::Blend, 1));

        // Evaluate
        let result = storage.evaluate_blend(1, 0.45);
        assert!(result.is_some());
        assert!(!result.unwrap().is_empty());

        // Remove
        storage.remove_blend(1);
        assert_eq!(storage.blend_count(), 0);
    }

    #[test]
    fn test_storage_random() {
        let storage = ContainerStorage::new();

        let mut container = RandomContainer::new(1, "test_random");
        container.add_child(RandomChild::new(1, "child1"));
        container.add_child(RandomChild::new(2, "child2"));

        storage.insert_random(container);
        storage.seed_random(1, 12345);

        // Select
        let result = storage.select_random(1);
        assert!(result.is_some());

        assert_eq!(storage.random_count(), 1);
    }

    #[test]
    fn test_storage_sequence() {
        let storage = ContainerStorage::new();

        let mut container = SequenceContainer::new(1, "test_sequence");
        container.add_step(SequenceStep::new(0, 1, "step1", 0.0, 100.0));
        container.add_step(SequenceStep::new(1, 2, "step2", 150.0, 100.0));

        storage.insert_sequence(container);

        // Play
        storage.play_sequence(1);
        assert!(storage.is_sequence_playing(1));

        // Tick
        let result = storage.tick_sequence(1, 10.0);
        assert!(result.is_some());
        assert!(result.unwrap().has_triggers());

        // Stop
        storage.stop_sequence(1);
        assert!(!storage.is_sequence_playing(1));
    }

    #[test]
    fn test_storage_clear() {
        let storage = ContainerStorage::new();

        storage.insert_blend(BlendContainer::new(1, "blend"));
        storage.insert_random(RandomContainer::new(2, "random"));
        storage.insert_sequence(SequenceContainer::new(3, "sequence"));

        assert_eq!(storage.total_count(), 3);

        storage.clear();

        assert_eq!(storage.total_count(), 0);
    }
}
