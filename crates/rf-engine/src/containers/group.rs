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

/// Maximum children per group (stack-allocated)
const MAX_GROUP_CHILDREN: usize = 8;

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
    pub fn new(container_type: ContainerType, container_id: ContainerId, name: impl Into<String>) -> Self {
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
    pub fn remove_child(&mut self, container_type: ContainerType, container_id: ContainerId) -> bool {
        if let Some(pos) = self.children.iter().position(|c| {
            c.container_type == container_type && c.container_id == container_id
        }) {
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
                        .unwrap_or(0)) % enabled.len();
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
        if let Some(pos) = self.children.iter().position(|c| c.container_id == container_id) {
            self.children.remove(pos);
            true
        } else {
            false
        }
    }
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
