//! Container Group - Hierarchical Container Nesting (P3C)
//!
//! Allows nesting containers for complex sound design:
//! - Random → Blend (pick random variant, then crossfade by RTPC)
//! - Sequence → Random (play sequence, each step picks random variation)
//! - Any combination of container types
//!
//! ## Example
//!
//! ```text
//! ContainerGroup: "Vehicle Engine"
//! ├── Random: "Engine Variants" (pick base engine sample)
//! │   ├── engine_v1.wav
//! │   └── engine_v2.wav
//! └── Blend: "RPM Crossfade" (crossfade by RPM RTPC)
//!     ├── idle (0-2000 RPM)
//!     ├── mid (1500-4000 RPM)
//!     └── high (3500-6000 RPM)
//! ```

use super::{Container, ContainerId, ContainerType};
use smallvec::SmallVec;
use std::collections::HashSet;

/// Maximum children per group (stack-allocated)
const MAX_GROUP_CHILDREN: usize = 8;

/// Maximum nesting depth (prevents stack overflow on recursive evaluation)
pub const MAX_NESTING_DEPTH: usize = 8;

// =============================================================================
// VALIDATION TYPES
// =============================================================================

/// Validation error types
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ValidationError {
    /// Nesting depth exceeds maximum
    MaxDepthExceeded { depth: usize, max: usize },
    /// Circular reference detected
    CycleDetected { container_id: ContainerId },
    /// Referenced container does not exist
    MissingContainer {
        container_type: ContainerType,
        container_id: ContainerId,
    },
    /// Too many children
    TooManyChildren { count: usize, max: usize },
    /// Self-reference (group contains itself)
    SelfReference { group_id: ContainerId },
}

impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ValidationError::MaxDepthExceeded { depth, max } => {
                write!(f, "Nesting depth {} exceeds maximum {}", depth, max)
            }
            ValidationError::CycleDetected { container_id } => {
                write!(f, "Cycle detected at container {}", container_id)
            }
            ValidationError::MissingContainer {
                container_type,
                container_id,
            } => {
                write!(f, "Missing {:?} container {}", container_type, container_id)
            }
            ValidationError::TooManyChildren { count, max } => {
                write!(f, "Too many children: {} exceeds maximum {}", count, max)
            }
            ValidationError::SelfReference { group_id } => {
                write!(f, "Group {} contains itself", group_id)
            }
        }
    }
}

/// Validation result
#[derive(Debug, Clone)]
pub struct ValidationResult {
    pub valid: bool,
    pub errors: Vec<ValidationError>,
    pub warnings: Vec<String>,
    pub max_depth_found: usize,
    pub total_containers: usize,
}

impl ValidationResult {
    pub fn success(max_depth: usize, total: usize) -> Self {
        Self {
            valid: true,
            errors: vec![],
            warnings: vec![],
            max_depth_found: max_depth,
            total_containers: total,
        }
    }

    pub fn failure(errors: Vec<ValidationError>) -> Self {
        Self {
            valid: false,
            errors,
            warnings: vec![],
            max_depth_found: 0,
            total_containers: 0,
        }
    }
}

/// Trait for container lookup during validation
pub trait ContainerLookup {
    fn group_exists(&self, id: ContainerId) -> bool;
    fn get_group_children(&self, id: ContainerId) -> Option<Vec<(ContainerType, ContainerId)>>;
    fn container_exists(&self, ctype: ContainerType, id: ContainerId) -> bool;
}

/// Child container reference within a group
#[derive(Debug, Clone)]
pub struct GroupChild {
    /// Container type
    pub container_type: ContainerType,
    /// Container ID (references stored container)
    pub container_id: ContainerId,
    /// Display name (for UI)
    pub name: String,
    /// Whether this child is enabled
    pub enabled: bool,
    /// Evaluation order (lower = first)
    pub order: u32,
}

impl GroupChild {
    /// Create a new group child reference
    pub fn new(
        container_type: ContainerType,
        container_id: ContainerId,
        name: impl Into<String>,
    ) -> Self {
        Self {
            container_type,
            container_id,
            name: name.into(),
            enabled: true,
            order: 0,
        }
    }
}

/// Container group - hierarchical container nesting
#[derive(Debug, Clone)]
pub struct ContainerGroup {
    /// Unique group ID
    pub id: ContainerId,
    /// Display name
    pub name: String,
    /// Whether group is enabled
    pub enabled: bool,
    /// Child container references
    pub children: SmallVec<[GroupChild; MAX_GROUP_CHILDREN]>,
    /// Evaluation mode
    pub mode: GroupEvaluationMode,
}

/// How to evaluate child containers
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u8)]
pub enum GroupEvaluationMode {
    /// Evaluate all children, combine results
    #[default]
    All = 0,
    /// Evaluate children in order until one succeeds
    FirstMatch = 1,
    /// Evaluate children based on priority/order
    Priority = 2,
    /// Evaluate randomly selected child
    Random = 3,
}

impl GroupEvaluationMode {
    pub fn from_u8(value: u8) -> Self {
        match value {
            1 => GroupEvaluationMode::FirstMatch,
            2 => GroupEvaluationMode::Priority,
            3 => GroupEvaluationMode::Random,
            _ => GroupEvaluationMode::All,
        }
    }
}

impl ContainerGroup {
    /// Create a new container group
    pub fn new(id: ContainerId, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            enabled: true,
            children: SmallVec::new(),
            mode: GroupEvaluationMode::All,
        }
    }

    /// Add a child container reference
    pub fn add_child(&mut self, child: GroupChild) {
        self.children.push(child);
        self.sort_by_order();
    }

    /// Remove a child by container ID
    pub fn remove_child(
        &mut self,
        container_type: ContainerType,
        container_id: ContainerId,
    ) -> bool {
        if let Some(pos) = self
            .children
            .iter()
            .position(|c| c.container_type == container_type && c.container_id == container_id)
        {
            self.children.remove(pos);
            true
        } else {
            false
        }
    }

    /// Sort children by order field
    fn sort_by_order(&mut self) {
        self.children.sort_by_key(|c| c.order);
    }

    /// Get child at index
    pub fn get_child(&self, index: usize) -> Option<&GroupChild> {
        self.children.get(index)
    }

    /// Get enabled children
    pub fn enabled_children(&self) -> impl Iterator<Item = &GroupChild> {
        self.children.iter().filter(|c| c.enabled)
    }

    /// Evaluate the group and return children to trigger
    pub fn evaluate(&self) -> GroupResult {
        if !self.enabled || self.children.is_empty() {
            return GroupResult::default();
        }

        let mut result = GroupResult::default();

        match self.mode {
            GroupEvaluationMode::All => {
                // Return all enabled children
                for child in self.enabled_children() {
                    result.children.push(GroupChildRef {
                        container_type: child.container_type,
                        container_id: child.container_id,
                    });
                }
            }
            GroupEvaluationMode::FirstMatch => {
                // Return first enabled child
                if let Some(child) = self.enabled_children().next() {
                    result.children.push(GroupChildRef {
                        container_type: child.container_type,
                        container_id: child.container_id,
                    });
                }
            }
            GroupEvaluationMode::Priority => {
                // Return first enabled child (already sorted by order)
                if let Some(child) = self.enabled_children().next() {
                    result.children.push(GroupChildRef {
                        container_type: child.container_type,
                        container_id: child.container_id,
                    });
                }
            }
            GroupEvaluationMode::Random => {
                // Return random enabled child
                let enabled: SmallVec<[&GroupChild; MAX_GROUP_CHILDREN]> =
                    self.enabled_children().collect();
                if !enabled.is_empty() {
                    // Simple random selection using time-based seed
                    let idx = (std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_nanos() as usize)
                        .unwrap_or(0))
                        % enabled.len();
                    let child = enabled[idx];
                    result.children.push(GroupChildRef {
                        container_type: child.container_type,
                        container_id: child.container_id,
                    });
                }
            }
        }

        result
    }

    /// Remove a child by container ID only (for FFI simplicity)
    pub fn remove_child_by_id(&mut self, container_id: ContainerId) -> bool {
        if let Some(pos) = self
            .children
            .iter()
            .position(|c| c.container_id == container_id)
        {
            self.children.remove(pos);
            true
        } else {
            false
        }
    }

    // =========================================================================
    // VALIDATION
    // =========================================================================

    /// Quick validation without external lookup (checks local constraints only)
    pub fn validate_local(&self) -> Result<(), ValidationError> {
        // Check child count
        if self.children.len() > MAX_GROUP_CHILDREN {
            return Err(ValidationError::TooManyChildren {
                count: self.children.len(),
                max: MAX_GROUP_CHILDREN,
            });
        }

        // Check for self-reference
        for child in &self.children {
            if child.container_type == ContainerType::Group && child.container_id == self.id {
                return Err(ValidationError::SelfReference { group_id: self.id });
            }
        }

        Ok(())
    }

    /// Full validation with depth and cycle checking
    /// Requires a lookup trait to resolve nested groups
    pub fn validate<L: ContainerLookup>(&self, lookup: &L) -> ValidationResult {
        // Local validation first
        if let Err(e) = self.validate_local() {
            return ValidationResult::failure(vec![e]);
        }

        let mut visited = HashSet::new();
        let mut errors = vec![];
        let mut max_depth = 0;
        let mut total = 0;

        // DFS to check depth and cycles
        self.validate_recursive(
            lookup,
            &mut visited,
            &mut errors,
            1,
            &mut max_depth,
            &mut total,
        );

        if errors.is_empty() {
            ValidationResult::success(max_depth, total)
        } else {
            ValidationResult::failure(errors)
        }
    }

    fn validate_recursive<L: ContainerLookup>(
        &self,
        lookup: &L,
        visited: &mut HashSet<ContainerId>,
        errors: &mut Vec<ValidationError>,
        current_depth: usize,
        max_depth: &mut usize,
        total: &mut usize,
    ) {
        // Track depth
        if current_depth > *max_depth {
            *max_depth = current_depth;
        }

        // Check max depth
        if current_depth > MAX_NESTING_DEPTH {
            errors.push(ValidationError::MaxDepthExceeded {
                depth: current_depth,
                max: MAX_NESTING_DEPTH,
            });
            return;
        }

        // Check cycle
        if !visited.insert(self.id) {
            errors.push(ValidationError::CycleDetected {
                container_id: self.id,
            });
            return;
        }

        *total += 1;

        // Validate each child
        for child in &self.children {
            // Check container exists
            if !lookup.container_exists(child.container_type, child.container_id) {
                errors.push(ValidationError::MissingContainer {
                    container_type: child.container_type,
                    container_id: child.container_id,
                });
                continue;
            }

            // Recurse into nested groups
            if child.container_type == ContainerType::Group {
                if let Some(children) = lookup.get_group_children(child.container_id) {
                    // Create temporary group for validation
                    let mut nested_group = ContainerGroup::new(child.container_id, "");
                    for (ct, cid) in children {
                        nested_group.add_child(GroupChild::new(ct, cid, ""));
                    }
                    nested_group.validate_recursive(
                        lookup,
                        visited,
                        errors,
                        current_depth + 1,
                        max_depth,
                        total,
                    );
                }
            } else {
                *total += 1;
            }
        }

        // Remove from visited for other paths (DAG support)
        visited.remove(&self.id);
    }
}

// =============================================================================
// VALIDATION HELPERS
// =============================================================================

/// Validate a proposed group addition without actually adding it
pub fn validate_group_addition<L: ContainerLookup>(
    parent_group_id: ContainerId,
    child_type: ContainerType,
    child_id: ContainerId,
    lookup: &L,
) -> Result<(), ValidationError> {
    // Check self-reference
    if child_type == ContainerType::Group && child_id == parent_group_id {
        return Err(ValidationError::SelfReference {
            group_id: parent_group_id,
        });
    }

    // Check if child exists
    if !lookup.container_exists(child_type, child_id) {
        return Err(ValidationError::MissingContainer {
            container_type: child_type,
            container_id: child_id,
        });
    }

    // For group children, check for potential cycles
    if child_type == ContainerType::Group {
        let mut visited = HashSet::new();
        visited.insert(parent_group_id);

        if would_create_cycle(child_id, &visited, lookup) {
            return Err(ValidationError::CycleDetected {
                container_id: child_id,
            });
        }
    }

    Ok(())
}

/// Check if adding a group would create a cycle
fn would_create_cycle<L: ContainerLookup>(
    group_id: ContainerId,
    visited: &HashSet<ContainerId>,
    lookup: &L,
) -> bool {
    if visited.contains(&group_id) {
        return true;
    }

    if let Some(children) = lookup.get_group_children(group_id) {
        let mut new_visited = visited.clone();
        new_visited.insert(group_id);

        for (ct, cid) in children {
            if ct == ContainerType::Group && would_create_cycle(cid, &new_visited, lookup) {
                return true;
            }
        }
    }

    false
}

impl Container for ContainerGroup {
    fn id(&self) -> ContainerId {
        self.id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn is_enabled(&self) -> bool {
        self.enabled
    }

    fn container_type(&self) -> ContainerType {
        ContainerType::Group
    }

    fn child_count(&self) -> usize {
        self.children.len()
    }
}

/// Reference to a child container
#[derive(Debug, Clone, Copy)]
pub struct GroupChildRef {
    pub container_type: ContainerType,
    pub container_id: ContainerId,
}

/// Result of group evaluation
#[derive(Debug, Clone, Default)]
pub struct GroupResult {
    /// Child containers to trigger
    pub children: SmallVec<[GroupChildRef; 4]>,
}

impl GroupResult {
    pub fn has_children(&self) -> bool {
        !self.children.is_empty()
    }

    pub fn is_empty(&self) -> bool {
        self.children.is_empty()
    }

    pub fn len(&self) -> usize {
        self.children.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_group_creation() {
        let group = ContainerGroup::new(1, "Test Group");
        assert_eq!(group.id, 1);
        assert_eq!(group.name, "Test Group");
        assert!(group.enabled);
        assert!(group.children.is_empty());
    }

    #[test]
    fn test_group_add_remove_child() {
        let mut group = ContainerGroup::new(1, "Test");

        group.add_child(GroupChild::new(ContainerType::Blend, 10, "Blend"));
        group.add_child(GroupChild::new(ContainerType::Random, 20, "Random"));

        assert_eq!(group.child_count(), 2);

        assert!(group.remove_child(ContainerType::Blend, 10));
        assert_eq!(group.child_count(), 1);

        assert!(!group.remove_child(ContainerType::Blend, 10)); // Already removed
    }

    #[test]
    fn test_group_order() {
        let mut group = ContainerGroup::new(1, "Test");

        let mut child1 = GroupChild::new(ContainerType::Blend, 1, "Second");
        child1.order = 2;

        let mut child2 = GroupChild::new(ContainerType::Random, 2, "First");
        child2.order = 1;

        group.add_child(child1);
        group.add_child(child2);

        // Should be sorted by order
        assert_eq!(group.children[0].name, "First");
        assert_eq!(group.children[1].name, "Second");
    }
}
