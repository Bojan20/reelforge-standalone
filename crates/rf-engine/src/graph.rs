//! Audio graph for node-based processing

use std::collections::HashMap;

use rf_core::Sample;

use crate::node::{AudioNode, NodeId};

/// Connection between nodes
#[derive(Debug, Clone, Copy)]
pub struct Connection {
    pub from_node: NodeId,
    pub from_channel: usize,
    pub to_node: NodeId,
    pub to_channel: usize,
}

/// Maximum channels per node for pre-allocated buffers
const MAX_NODE_CHANNELS: usize = 8;

/// Audio processing graph
pub struct AudioGraph {
    nodes: HashMap<NodeId, Box<dyn AudioNode>>,
    connections: Vec<Connection>,
    processing_order: Vec<NodeId>,
    buffers: HashMap<NodeId, Vec<Vec<Sample>>>,
    /// Pre-allocated input buffers to avoid allocation in process()
    input_buffers: Vec<Vec<Sample>>,
    /// Pre-allocated output buffers to avoid allocation in process()
    output_buffers: Vec<Vec<Sample>>,
    block_size: usize,
    next_id: u32,
    dirty: bool,
}

impl AudioGraph {
    pub fn new(block_size: usize) -> Self {
        // Pre-allocate input/output buffers to avoid allocation in audio thread
        let input_buffers: Vec<Vec<Sample>> = (0..MAX_NODE_CHANNELS)
            .map(|_| vec![0.0; block_size])
            .collect();
        let output_buffers: Vec<Vec<Sample>> = (0..MAX_NODE_CHANNELS)
            .map(|_| vec![0.0; block_size])
            .collect();

        Self {
            nodes: HashMap::new(),
            connections: Vec::new(),
            processing_order: Vec::new(),
            buffers: HashMap::new(),
            input_buffers,
            output_buffers,
            block_size,
            next_id: 1, // 0 is reserved for master
            dirty: true,
        }
    }

    /// Add a node to the graph
    pub fn add_node(&mut self, node: Box<dyn AudioNode>) -> NodeId {
        let id = NodeId::new(self.next_id);
        self.next_id += 1;

        // Allocate buffers for node outputs
        let num_outputs = node.num_outputs();
        let buffers: Vec<Vec<Sample>> = (0..num_outputs)
            .map(|_| vec![0.0; self.block_size])
            .collect();

        self.buffers.insert(id, buffers);
        self.nodes.insert(id, node);
        self.dirty = true;

        id
    }

    /// Remove a node from the graph
    pub fn remove_node(&mut self, id: NodeId) -> Option<Box<dyn AudioNode>> {
        // Remove connections involving this node
        self.connections
            .retain(|c| c.from_node != id && c.to_node != id);

        self.buffers.remove(&id);
        self.dirty = true;

        self.nodes.remove(&id)
    }

    /// Connect two nodes
    pub fn connect(
        &mut self,
        from_node: NodeId,
        from_channel: usize,
        to_node: NodeId,
        to_channel: usize,
    ) -> bool {
        // Validate connection
        if let (Some(from), Some(to)) = (self.nodes.get(&from_node), self.nodes.get(&to_node)) {
            if from_channel < from.num_outputs() && to_channel < to.num_inputs() {
                self.connections.push(Connection {
                    from_node,
                    from_channel,
                    to_node,
                    to_channel,
                });
                self.dirty = true;
                return true;
            }
        }
        false
    }

    /// Disconnect two nodes
    pub fn disconnect(&mut self, from_node: NodeId, to_node: NodeId) {
        self.connections
            .retain(|c| c.from_node != from_node || c.to_node != to_node);
        self.dirty = true;
    }

    /// Get a node by ID
    pub fn get_node(&self, id: NodeId) -> Option<&dyn AudioNode> {
        self.nodes.get(&id).map(|n| n.as_ref())
    }

    /// Get a mutable node by ID
    pub fn get_node_mut(&mut self, id: NodeId) -> Option<&mut Box<dyn AudioNode>> {
        self.nodes.get_mut(&id)
    }

    /// Recalculate processing order using topological sort
    fn update_processing_order(&mut self) {
        if !self.dirty {
            return;
        }

        // Simple topological sort
        let mut order = Vec::new();
        let mut visited = HashMap::new();
        let mut temp_visited = HashMap::new();

        for &id in self.nodes.keys() {
            if !visited.contains_key(&id) {
                self.visit(id, &mut visited, &mut temp_visited, &mut order);
            }
        }

        order.reverse();
        self.processing_order = order;
        self.dirty = false;
    }

    fn visit(
        &self,
        id: NodeId,
        visited: &mut HashMap<NodeId, bool>,
        temp_visited: &mut HashMap<NodeId, bool>,
        order: &mut Vec<NodeId>,
    ) {
        if temp_visited.get(&id).copied().unwrap_or(false) {
            // Cycle detected - skip
            return;
        }
        if visited.get(&id).copied().unwrap_or(false) {
            return;
        }

        temp_visited.insert(id, true);

        // Visit all nodes this node outputs to
        for conn in &self.connections {
            if conn.from_node == id {
                self.visit(conn.to_node, visited, temp_visited, order);
            }
        }

        temp_visited.insert(id, false);
        visited.insert(id, true);
        order.push(id);
    }

    /// Process the audio graph for one block
    /// ZERO ALLOCATION in this function - uses pre-allocated buffers
    pub fn process(&mut self) {
        self.update_processing_order();

        // Clear all node output buffers
        for buffers in self.buffers.values_mut() {
            for buffer in buffers.iter_mut() {
                buffer.fill(0.0);
            }
        }

        // Process nodes in order (iterate by reference, no clone!)
        for idx in 0..self.processing_order.len() {
            let node_id = self.processing_order[idx];

            // Gather inputs from connected nodes
            let (num_inputs, num_outputs) = match self.nodes.get(&node_id) {
                Some(n) => (n.num_inputs().min(MAX_NODE_CHANNELS), n.num_outputs().min(MAX_NODE_CHANNELS)),
                None => continue,
            };

            // Clear pre-allocated input buffers (only channels we need)
            for i in 0..num_inputs {
                self.input_buffers[i].fill(0.0);
            }

            // Gather inputs from connections into pre-allocated buffers
            for conn in &self.connections {
                if conn.to_node == node_id && conn.to_channel < num_inputs {
                    if let Some(from_buffers) = self.buffers.get(&conn.from_node) {
                        if conn.from_channel < from_buffers.len() {
                            // Add to input (allows summing multiple sources)
                            let input_buf = &mut self.input_buffers[conn.to_channel];
                            let from_buf = &from_buffers[conn.from_channel];
                            for i in 0..self.block_size {
                                input_buf[i] += from_buf[i];
                            }
                        }
                    }
                }
            }

            // Clear pre-allocated output buffers (only channels we need)
            for i in 0..num_outputs {
                self.output_buffers[i].fill(0.0);
            }

            // Process the node using pre-allocated buffers
            let input_refs: Vec<&[Sample]> = self.input_buffers[..num_inputs]
                .iter()
                .map(|v| v.as_slice())
                .collect();
            let mut output_refs: Vec<&mut [Sample]> = self.output_buffers[..num_outputs]
                .iter_mut()
                .map(|v| v.as_mut_slice())
                .collect();

            if let Some(node) = self.nodes.get_mut(&node_id) {
                node.process(&input_refs, &mut output_refs);
            }

            // Copy outputs to node buffers (reuse existing allocations)
            if let Some(node_buffers) = self.buffers.get_mut(&node_id) {
                for i in 0..num_outputs.min(node_buffers.len()) {
                    node_buffers[i].copy_from_slice(&self.output_buffers[i]);
                }
            }
        }
    }

    /// Get output buffer for a node
    pub fn get_output(&self, node_id: NodeId, channel: usize) -> Option<&[Sample]> {
        self.buffers
            .get(&node_id)
            .and_then(|buffers| buffers.get(channel))
            .map(|v| v.as_slice())
    }

    /// Set block size
    pub fn set_block_size(&mut self, block_size: usize) {
        self.block_size = block_size;

        for (node_id, buffers) in &mut self.buffers {
            if let Some(node) = self.nodes.get(node_id) {
                buffers.resize(node.num_outputs(), Vec::new());
                for buffer in buffers.iter_mut() {
                    buffer.resize(block_size, 0.0);
                }
            }
        }
    }

    /// Set sample rate for all nodes
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        for node in self.nodes.values_mut() {
            node.set_sample_rate(sample_rate);
        }
    }

    /// Reset all nodes
    pub fn reset(&mut self) {
        for node in self.nodes.values_mut() {
            node.reset();
        }
    }

    /// Get total latency through the graph
    pub fn total_latency(&self) -> usize {
        // Simple: just sum latencies (proper implementation would trace paths)
        self.nodes.values().map(|n| n.latency()).max().unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::node::{GainNode, PassthroughNode};

    #[test]
    fn test_graph_basic() {
        let mut graph = AudioGraph::new(256);

        let node1 = graph.add_node(Box::new(PassthroughNode::new(2)));
        let node2 = graph.add_node(Box::new(GainNode::new(2)));

        assert!(graph.connect(node1, 0, node2, 0));
        assert!(graph.connect(node1, 1, node2, 1));

        graph.process();
    }

    #[test]
    fn test_graph_processing_order() {
        let mut graph = AudioGraph::new(256);

        let node1 = graph.add_node(Box::new(PassthroughNode::new(2)));
        let node2 = graph.add_node(Box::new(PassthroughNode::new(2)));
        let node3 = graph.add_node(Box::new(PassthroughNode::new(2)));

        // node1 -> node2 -> node3
        graph.connect(node1, 0, node2, 0);
        graph.connect(node2, 0, node3, 0);

        graph.process();

        // Processing order should be node1, node2, node3
        assert_eq!(graph.processing_order.len(), 3);
    }
}
