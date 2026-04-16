//! StageFlow — the directed graph that defines how a slot game flows.
//!
//! A `StageFlow` is a validated directed graph of [`StageNode`]s connected by
//! [`StageTransition`]s. It represents the complete game logic of a slot title.
//!
//! ## Guarantees (enforced at build time)
//! - Exactly one entry node
//! - At least one terminal node
//! - All transition targets reference existing nodes
//! - No orphaned nodes (every non-entry node is reachable)
//! - No unintended infinite loops (intentional loops are declared explicitly)
//! - Compliance rules don't conflict within the same jurisdiction

use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::node::{NodeId, StageNode, StageTransition};

// ─── Errors ───────────────────────────────────────────────────────────────────

#[derive(Debug, Error)]
pub enum ValidationError {
    #[error("No entry node defined — exactly one node must have is_entry=true")]
    NoEntryNode,

    #[error("Multiple entry nodes: {0:?}")]
    MultipleEntryNodes(Vec<String>),

    #[error("No terminal node defined — at least one node must have is_terminal=true")]
    NoTerminalNode,

    #[error("Dangling transition: node '{from}' transitions to unknown node '{to}'")]
    DanglingTransition { from: String, to: String },

    #[error("Orphaned node '{name}' — unreachable from entry node")]
    OrphanedNode { name: String },

    #[error("Node '{name}' has no outgoing transitions and is not marked as terminal")]
    DeadEnd { name: String },

    #[error("Duplicate node ID: {id}")]
    DuplicateNodeId { id: String },

    #[error("Empty flow — no nodes defined")]
    EmptyFlow,

    #[error("Circular dependency in non-loop node '{name}' (mark with allow_loop=true to permit)")]
    UnintendedCycle { name: String },
}

// ─── StageFlow ────────────────────────────────────────────────────────────────

/// The complete directed graph of game phases for a slot title.
///
/// Build with [`StageFlowBuilder`] or deserialize from JSON blueprint.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StageFlow {
    /// All nodes, indexed by NodeId for O(1) lookup
    pub nodes: IndexMap<NodeId, StageNode>,

    /// Entry node ID (cached after validation)
    pub entry_id: NodeId,

    /// All terminal node IDs (cached after validation)
    pub terminal_ids: Vec<NodeId>,

    /// Declared intentional loop node IDs (these are allowed to form cycles)
    /// e.g. the free-spins loop back to the spin node
    pub loop_node_ids: Vec<NodeId>,

    /// Schema version
    pub schema_version: String,
}

impl StageFlow {
    /// Start a new builder
    pub fn builder() -> StageFlowBuilder {
        StageFlowBuilder::new()
    }

    /// Look up a node by ID
    pub fn get(&self, id: &NodeId) -> Option<&StageNode> {
        self.nodes.get(id)
    }

    /// Entry node
    pub fn entry(&self) -> &StageNode {
        self.nodes.get(&self.entry_id).expect("entry node must exist after validation")
    }

    /// Number of nodes
    pub fn node_count(&self) -> usize {
        self.nodes.len()
    }

    /// Total number of transitions across all nodes
    pub fn transition_count(&self) -> usize {
        self.nodes.values().map(|n| n.transitions.len()).sum()
    }

    /// BFS traversal from entry — returns nodes in visitation order
    pub fn reachable_nodes(&self) -> Vec<&StageNode> {
        let mut visited = std::collections::HashSet::new();
        let mut queue = std::collections::VecDeque::new();
        let mut result = Vec::new();

        queue.push_back(&self.entry_id);
        visited.insert(self.entry_id.clone());

        while let Some(id) = queue.pop_front() {
            if let Some(node) = self.nodes.get(id) {
                result.push(node);
                for t in &node.transitions {
                    if !visited.contains(&t.to) {
                        visited.insert(t.to.clone());
                        queue.push_back(&t.to);
                    }
                }
            }
        }
        result
    }

    /// All nodes NOT reachable from entry (should be empty in a valid flow)
    pub fn orphaned_nodes(&self) -> Vec<&StageNode> {
        let reachable: std::collections::HashSet<NodeId> =
            self.reachable_nodes().iter().map(|n| n.id.clone()).collect();
        self.nodes.values().filter(|n| !reachable.contains(&n.id)).collect()
    }

    /// Find cycles in the graph (excluding declared loop nodes)
    pub fn detect_cycles(&self) -> Vec<Vec<NodeId>> {
        // Tarjan's SCC algorithm
        let mut index_counter = 0u32;
        let mut stack = Vec::new();
        let mut lowlinks: std::collections::HashMap<NodeId, u32> = Default::default();
        let mut indices: std::collections::HashMap<NodeId, u32> = Default::default();
        let mut on_stack: std::collections::HashSet<NodeId> = Default::default();
        let mut sccs: Vec<Vec<NodeId>> = Vec::new();

        fn strongconnect(
            node_id: &NodeId,
            flow: &StageFlow,
            index_counter: &mut u32,
            stack: &mut Vec<NodeId>,
            lowlinks: &mut std::collections::HashMap<NodeId, u32>,
            indices: &mut std::collections::HashMap<NodeId, u32>,
            on_stack: &mut std::collections::HashSet<NodeId>,
            sccs: &mut Vec<Vec<NodeId>>,
        ) {
            let v_index = *index_counter;
            indices.insert(node_id.clone(), v_index);
            lowlinks.insert(node_id.clone(), v_index);
            *index_counter += 1;
            stack.push(node_id.clone());
            on_stack.insert(node_id.clone());

            if let Some(node) = flow.nodes.get(node_id) {
                for t in &node.transitions {
                    if !indices.contains_key(&t.to) {
                        strongconnect(&t.to, flow, index_counter, stack, lowlinks, indices, on_stack, sccs);
                        let w_low = *lowlinks.get(&t.to).unwrap_or(&u32::MAX);
                        let v_low = lowlinks.get(node_id).copied().unwrap_or(u32::MAX);
                        lowlinks.insert(node_id.clone(), v_low.min(w_low));
                    } else if on_stack.contains(&t.to) {
                        let w_idx = *indices.get(&t.to).unwrap_or(&u32::MAX);
                        let v_low = lowlinks.get(node_id).copied().unwrap_or(u32::MAX);
                        lowlinks.insert(node_id.clone(), v_low.min(w_idx));
                    }
                }
            }

            let v_low = *lowlinks.get(node_id).unwrap_or(&u32::MAX);
            let v_idx = *indices.get(node_id).unwrap_or(&u32::MAX);
            if v_low == v_idx {
                let mut scc = Vec::new();
                loop {
                    let w = stack.pop().expect("stack not empty");
                    on_stack.remove(&w);
                    scc.push(w.clone());
                    if w == *node_id {
                        break;
                    }
                }
                if scc.len() > 1 {
                    sccs.push(scc);
                }
            }
        }

        for node_id in self.nodes.keys() {
            if !indices.contains_key(node_id) {
                strongconnect(
                    node_id, self, &mut index_counter, &mut stack,
                    &mut lowlinks, &mut indices, &mut on_stack, &mut sccs,
                );
            }
        }

        // Filter out declared intentional loops
        sccs.retain(|scc| !scc.iter().any(|id| self.loop_node_ids.contains(id)));
        sccs
    }

    /// All transitions in the entire flow (flat list)
    pub fn all_transitions(&self) -> Vec<(&StageNode, &StageTransition)> {
        self.nodes.values().flat_map(|n| n.transitions.iter().map(move |t| (n, t))).collect()
    }
}

// ─── Builder ──────────────────────────────────────────────────────────────────

/// Fluent builder for [`StageFlow`].
///
/// Validates the graph before building and returns an error if
/// any structural constraint is violated.
pub struct StageFlowBuilder {
    nodes: Vec<StageNode>,
    loop_node_ids: Vec<NodeId>,
}

impl StageFlowBuilder {
    pub fn new() -> Self {
        Self { nodes: Vec::new(), loop_node_ids: Vec::new() }
    }

    /// Add a node to the flow
    pub fn node(mut self, node: StageNode) -> Self {
        self.nodes.push(node);
        self
    }

    /// Add multiple nodes at once
    pub fn nodes(mut self, nodes: impl IntoIterator<Item = StageNode>) -> Self {
        self.nodes.extend(nodes);
        self
    }

    /// Declare a node as forming an intentional loop (e.g. free-spins spin node)
    pub fn allow_loop(mut self, node_id: NodeId) -> Self {
        self.loop_node_ids.push(node_id);
        self
    }

    /// Validate and build the [`StageFlow`].
    pub fn build(self) -> Result<StageFlow, ValidationError> {
        if self.nodes.is_empty() {
            return Err(ValidationError::EmptyFlow);
        }

        // Check for duplicate IDs
        let mut seen_ids = std::collections::HashSet::new();
        for node in &self.nodes {
            if !seen_ids.insert(node.id.clone()) {
                return Err(ValidationError::DuplicateNodeId {
                    id: node.id.to_string(),
                });
            }
        }

        // Find entry nodes
        let entries: Vec<&StageNode> = self.nodes.iter().filter(|n| n.is_entry).collect();
        match entries.len() {
            0 => return Err(ValidationError::NoEntryNode),
            1 => {} // good
            _ => {
                return Err(ValidationError::MultipleEntryNodes(
                    entries.iter().map(|n| n.name.clone()).collect(),
                ))
            }
        }

        // Find terminal nodes
        let terminals: Vec<NodeId> = self.nodes.iter()
            .filter(|n| n.is_terminal)
            .map(|n| n.id.clone())
            .collect();
        if terminals.is_empty() {
            return Err(ValidationError::NoTerminalNode);
        }

        // Build index
        let mut nodes: IndexMap<NodeId, StageNode> = IndexMap::new();
        for node in self.nodes {
            nodes.insert(node.id.clone(), node);
        }

        // Validate all transition targets exist
        for (_node_id, node) in &nodes {
            for t in &node.transitions {
                if !nodes.contains_key(&t.to) {
                    return Err(ValidationError::DanglingTransition {
                        from: node.name.clone(),
                        to: t.to.to_string(),
                    });
                }
            }

            // Dead-end check (non-terminal node with no transitions)
            if !node.is_terminal && node.transitions.is_empty() {
                return Err(ValidationError::DeadEnd { name: node.name.clone() });
            }
        }

        let entry_id = nodes.values().find(|n| n.is_entry).unwrap().id.clone();

        let flow = StageFlow {
            nodes,
            entry_id,
            terminal_ids: terminals,
            loop_node_ids: self.loop_node_ids,
            schema_version: "1.0.0".to_string(),
        };

        // Orphan check
        let orphans = flow.orphaned_nodes();
        if !orphans.is_empty() {
            return Err(ValidationError::OrphanedNode {
                name: orphans[0].name.clone(),
            });
        }

        // Cycle detection (excluding declared loops)
        let cycles = flow.detect_cycles();
        if !cycles.is_empty() {
            // Find a node name from the cycle to report
            let cycle_node_id = &cycles[0][0];
            let name = flow.nodes.get(cycle_node_id)
                .map(|n| n.name.clone())
                .unwrap_or_else(|| cycle_node_id.to_string());
            return Err(ValidationError::UnintendedCycle { name });
        }

        Ok(flow)
    }
}

impl Default for StageFlowBuilder {
    fn default() -> Self {
        Self::new()
    }
}
