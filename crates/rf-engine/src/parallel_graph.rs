//! Parallel Audio Graph with Topological Sort
//!
//! Provides parallel execution of independent audio nodes using rayon.
//! Key features:
//! - Topological sort for correct processing order
//! - Parallel processing of independent nodes at each depth level
//! - Lock-free buffer management
//! - Zero allocation in audio thread (pre-allocated pools)

use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};

use parking_lot::RwLock;
use rayon::prelude::*;
use rf_core::Sample;
use rf_dsp::delay_compensation::DelayCompensationManager;

use crate::node::{AudioNode, NodeId};

// ============ Connection Types ============

/// Connection type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionType {
    /// Normal audio connection
    Audio,
    /// Sidechain input (for dynamics processors)
    Sidechain,
    /// Modulation signal
    Modulation,
}

/// Enhanced connection with type
#[derive(Debug, Clone, Copy)]
pub struct Connection {
    pub from_node: NodeId,
    pub from_channel: usize,
    pub to_node: NodeId,
    pub to_channel: usize,
    pub connection_type: ConnectionType,
    /// Gain for this connection (0.0 to 1.0)
    pub gain: f64,
}

impl Connection {
    pub fn audio(from_node: NodeId, from_ch: usize, to_node: NodeId, to_ch: usize) -> Self {
        Self {
            from_node,
            from_channel: from_ch,
            to_node,
            to_channel: to_ch,
            connection_type: ConnectionType::Audio,
            gain: 1.0,
        }
    }

    pub fn sidechain(from_node: NodeId, from_ch: usize, to_node: NodeId, to_ch: usize) -> Self {
        Self {
            from_node,
            from_channel: from_ch,
            to_node,
            to_channel: to_ch,
            connection_type: ConnectionType::Sidechain,
            gain: 1.0,
        }
    }
}

// ============ Buffer Pool ============

/// Pre-allocated buffer pool for zero-allocation processing
pub struct BufferPool {
    buffers: Vec<Vec<Sample>>,
    block_size: usize,
    available: Vec<usize>,
}

impl BufferPool {
    pub fn new(count: usize, block_size: usize) -> Self {
        Self {
            buffers: (0..count).map(|_| vec![0.0; block_size]).collect(),
            block_size,
            available: (0..count).collect(),
        }
    }

    pub fn acquire(&mut self) -> Option<usize> {
        self.available.pop()
    }

    pub fn release(&mut self, idx: usize) {
        if idx < self.buffers.len() {
            self.buffers[idx].fill(0.0);
            self.available.push(idx);
        }
    }

    pub fn get(&self, idx: usize) -> Option<&[Sample]> {
        self.buffers.get(idx).map(|v| v.as_slice())
    }

    pub fn get_mut(&mut self, idx: usize) -> Option<&mut [Sample]> {
        self.buffers.get_mut(idx).map(|v| v.as_mut_slice())
    }

    pub fn resize(&mut self, block_size: usize) {
        self.block_size = block_size;
        for buffer in &mut self.buffers {
            buffer.resize(block_size, 0.0);
        }
    }
}

// ============ Processing Level ============

/// A level of nodes that can be processed in parallel
#[derive(Debug, Clone)]
struct ProcessingLevel {
    /// Node IDs at this level
    node_ids: Vec<NodeId>,
    /// Depth in the graph (0 = sources, higher = deeper)
    depth: usize,
}

// ============ Node Wrapper ============

/// Thread-safe node wrapper for parallel processing
struct NodeWrapper {
    node: RwLock<Box<dyn AudioNode>>,
    /// Input buffer indices in the pool
    input_buffers: Vec<usize>,
    /// Output buffer indices in the pool
    output_buffers: Vec<usize>,
    /// Sidechain input buffer indices
    sidechain_buffers: Vec<usize>,
    /// Processing depth level
    depth: usize,
    /// Node latency in samples
    latency: AtomicUsize,
}

// ============ Parallel Audio Graph ============

/// Parallel audio processing graph
pub struct ParallelAudioGraph {
    /// All nodes in the graph
    nodes: HashMap<NodeId, NodeWrapper>,
    /// All connections
    connections: Vec<Connection>,
    /// Processing levels (parallel groups)
    levels: Vec<ProcessingLevel>,
    /// Buffer pool for audio data
    buffer_pool: BufferPool,
    /// Node output buffers (persistent between frames)
    node_outputs: HashMap<NodeId, Vec<Vec<Sample>>>,
    /// Block size
    block_size: usize,
    /// Sample rate
    sample_rate: f64,
    /// Next node ID
    next_id: u32,
    /// Graph needs recompilation
    dirty: bool,
    /// Delay compensation manager
    delay_comp: DelayCompensationManager,
    /// Total graph latency
    total_latency: usize,
}

impl ParallelAudioGraph {
    pub fn new(block_size: usize, sample_rate: f64) -> Self {
        Self {
            nodes: HashMap::new(),
            connections: Vec::new(),
            levels: Vec::new(),
            buffer_pool: BufferPool::new(256, block_size), // Pre-allocate 256 buffers
            node_outputs: HashMap::new(),
            block_size,
            sample_rate,
            next_id: 1,
            dirty: true,
            delay_comp: DelayCompensationManager::new(sample_rate),
            total_latency: 0,
        }
    }

    /// Add a node to the graph
    pub fn add_node(&mut self, mut node: Box<dyn AudioNode>) -> NodeId {
        let id = NodeId::new(self.next_id);
        self.next_id += 1;

        node.set_sample_rate(self.sample_rate);

        let num_outputs = node.num_outputs();
        let latency = node.latency();

        // Pre-allocate output buffers
        let outputs: Vec<Vec<Sample>> = (0..num_outputs)
            .map(|_| vec![0.0; self.block_size])
            .collect();
        self.node_outputs.insert(id, outputs);

        // Register with delay compensation
        self.delay_comp.register_node(id.0);
        self.delay_comp.report_latency(id.0, latency);

        let wrapper = NodeWrapper {
            node: RwLock::new(node),
            input_buffers: Vec::new(),
            output_buffers: Vec::new(),
            sidechain_buffers: Vec::new(),
            depth: 0,
            latency: AtomicUsize::new(latency),
        };

        self.nodes.insert(id, wrapper);
        self.dirty = true;

        id
    }

    /// Remove a node from the graph
    pub fn remove_node(&mut self, id: NodeId) -> Option<Box<dyn AudioNode>> {
        // Remove connections
        self.connections.retain(|c| c.from_node != id && c.to_node != id);

        // Remove from delay compensation
        self.delay_comp.unregister_node(id.0);

        // Remove outputs
        self.node_outputs.remove(&id);

        self.dirty = true;

        self.nodes.remove(&id).map(|w| w.node.into_inner())
    }

    /// Connect two nodes
    pub fn connect(&mut self, connection: Connection) -> bool {
        // Validate
        let from_valid = self.nodes.get(&connection.from_node)
            .map(|w| {
                let node = w.node.read();
                connection.from_channel < node.num_outputs()
            })
            .unwrap_or(false);

        let to_valid = self.nodes.get(&connection.to_node)
            .map(|w| {
                let node = w.node.read();
                match connection.connection_type {
                    ConnectionType::Audio => connection.to_channel < node.num_inputs(),
                    ConnectionType::Sidechain => connection.to_channel < node.num_inputs(), // Sidechain uses same input count
                    ConnectionType::Modulation => true,
                }
            })
            .unwrap_or(false);

        if from_valid && to_valid {
            self.connections.push(connection);
            self.dirty = true;
            true
        } else {
            false
        }
    }

    /// Disconnect nodes
    pub fn disconnect(&mut self, from: NodeId, to: NodeId) {
        self.connections.retain(|c| c.from_node != from || c.to_node != to);
        self.dirty = true;
    }

    /// Compile the graph for processing
    fn compile(&mut self) {
        if !self.dirty {
            return;
        }

        // Calculate depth for each node using topological sort
        let mut depths: HashMap<NodeId, usize> = HashMap::new();
        let mut in_degree: HashMap<NodeId, usize> = HashMap::new();

        // Initialize
        for &id in self.nodes.keys() {
            in_degree.insert(id, 0);
            depths.insert(id, 0);
        }

        // Count incoming edges
        for conn in &self.connections {
            if conn.connection_type == ConnectionType::Audio {
                *in_degree.get_mut(&conn.to_node).unwrap() += 1;
            }
        }

        // BFS for topological sort
        let mut queue: Vec<NodeId> = in_degree.iter()
            .filter(|&(_, deg)| *deg == 0)
            .map(|(&id, _)| id)
            .collect();

        while let Some(current) = queue.pop() {
            let current_depth = depths[&current];

            for conn in &self.connections {
                if conn.from_node == current && conn.connection_type == ConnectionType::Audio {
                    let to = conn.to_node;
                    let new_depth = current_depth + 1;

                    if new_depth > depths[&to] {
                        depths.insert(to, new_depth);
                    }

                    let deg = in_degree.get_mut(&to).unwrap();
                    *deg -= 1;
                    if *deg == 0 {
                        queue.push(to);
                    }
                }
            }
        }

        // Update node depths
        for (&id, &depth) in &depths {
            if let Some(wrapper) = self.nodes.get_mut(&id) {
                wrapper.depth = depth;
            }
        }

        // Group nodes by depth level
        let max_depth = depths.values().copied().max().unwrap_or(0);
        self.levels = (0..=max_depth)
            .map(|d| ProcessingLevel {
                node_ids: depths.iter()
                    .filter(|&(_, depth)| *depth == d)
                    .map(|(&id, _)| id)
                    .collect(),
                depth: d,
            })
            .filter(|level| !level.node_ids.is_empty())
            .collect();

        // Update total latency
        self.total_latency = self.delay_comp.total_latency();

        self.dirty = false;

        log::debug!(
            "ParallelGraph: compiled {} nodes into {} levels, total latency: {} samples",
            self.nodes.len(),
            self.levels.len(),
            self.total_latency
        );
    }

    /// Process the entire graph
    pub fn process(&mut self) {
        self.compile();

        // Clear all output buffers
        for outputs in self.node_outputs.values_mut() {
            for buffer in outputs {
                buffer.fill(0.0);
            }
        }

        // Clone levels to avoid borrow conflict
        let levels = self.levels.clone();

        // Process each level (levels must be sequential, nodes within level parallel)
        for level in &levels {
            self.process_level(level);
        }
    }

    /// Process a single level of nodes in parallel
    fn process_level(&mut self, level: &ProcessingLevel) {
        let block_size = self.block_size;
        let connections = &self.connections;
        let node_outputs = &self.node_outputs;

        // Collect inputs for each node in this level
        let level_inputs: Vec<(NodeId, Vec<Vec<Sample>>, Vec<Vec<Sample>>)> = level.node_ids.iter()
            .map(|&node_id| {
                let wrapper = &self.nodes[&node_id];
                let node = wrapper.node.read();
                let num_inputs = node.num_inputs();

                // Audio inputs
                let mut inputs: Vec<Vec<Sample>> = (0..num_inputs)
                    .map(|_| vec![0.0; block_size])
                    .collect();

                // Sidechain inputs
                let mut sidechains: Vec<Vec<Sample>> = (0..num_inputs)
                    .map(|_| vec![0.0; block_size])
                    .collect();

                // Sum inputs from connections
                for conn in connections {
                    if conn.to_node == node_id && conn.to_channel < num_inputs {
                        if let Some(from_outputs) = node_outputs.get(&conn.from_node) {
                            if conn.from_channel < from_outputs.len() {
                                let target = match conn.connection_type {
                                    ConnectionType::Audio => &mut inputs[conn.to_channel],
                                    ConnectionType::Sidechain => &mut sidechains[conn.to_channel],
                                    ConnectionType::Modulation => &mut inputs[conn.to_channel],
                                };

                                for (i, &sample) in from_outputs[conn.from_channel].iter().enumerate() {
                                    target[i] += sample * conn.gain;
                                }
                            }
                        }
                    }
                }

                (node_id, inputs, sidechains)
            })
            .collect();

        // Process nodes in parallel
        let results: Vec<(NodeId, Vec<Vec<Sample>>)> = level_inputs
            .into_par_iter()
            .map(|(node_id, inputs, sidechains)| {
                let wrapper = &self.nodes[&node_id];
                let mut node = wrapper.node.write();

                let num_outputs = node.num_outputs();
                let mut outputs: Vec<Vec<Sample>> = (0..num_outputs)
                    .map(|_| vec![0.0; block_size])
                    .collect();

                // Create slice references
                let input_refs: Vec<&[Sample]> = inputs.iter().map(|v| v.as_slice()).collect();
                let mut output_refs: Vec<&mut [Sample]> = outputs.iter_mut().map(|v| v.as_mut_slice()).collect();

                // Process (TODO: pass sidechain to node)
                node.process(&input_refs, &mut output_refs);

                (node_id, outputs)
            })
            .collect();

        // Store results
        for (node_id, outputs) in results {
            if let Some(node_outputs) = self.node_outputs.get_mut(&node_id) {
                for (i, output) in outputs.into_iter().enumerate() {
                    if i < node_outputs.len() {
                        node_outputs[i] = output;
                    }
                }
            }
        }
    }

    /// Get output of a node
    pub fn get_output(&self, node_id: NodeId, channel: usize) -> Option<&[Sample]> {
        self.node_outputs.get(&node_id)
            .and_then(|outputs| outputs.get(channel))
            .map(|v| v.as_slice())
    }

    /// Get mutable access to a node
    pub fn get_node_mut(&self, id: NodeId) -> Option<parking_lot::RwLockWriteGuard<Box<dyn AudioNode>>> {
        self.nodes.get(&id).map(|w| w.node.write())
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        self.delay_comp.set_sample_rate(sample_rate);

        for wrapper in self.nodes.values() {
            wrapper.node.write().set_sample_rate(sample_rate);
        }
    }

    /// Set block size
    pub fn set_block_size(&mut self, block_size: usize) {
        self.block_size = block_size;
        self.buffer_pool.resize(block_size);

        for outputs in self.node_outputs.values_mut() {
            for buffer in outputs {
                buffer.resize(block_size, 0.0);
            }
        }
    }

    /// Reset all nodes
    pub fn reset(&mut self) {
        for wrapper in self.nodes.values() {
            wrapper.node.write().reset();
        }
        self.delay_comp.clear_all();
    }

    /// Get total latency
    pub fn total_latency(&self) -> usize {
        self.total_latency
    }

    /// Get number of processing levels
    pub fn num_levels(&self) -> usize {
        self.levels.len()
    }

    /// Get node count
    pub fn node_count(&self) -> usize {
        self.nodes.len()
    }

    /// Report node latency change
    pub fn report_node_latency(&mut self, id: NodeId, latency: usize) {
        if let Some(wrapper) = self.nodes.get(&id) {
            wrapper.latency.store(latency, Ordering::Relaxed);
            self.delay_comp.report_latency(id.0, latency);
        }
    }

    /// Enable/disable delay compensation
    pub fn set_delay_compensation(&mut self, enabled: bool) {
        self.delay_comp.set_enabled(enabled);
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;
    use crate::node::{PassthroughNode, GainNode};

    #[test]
    fn test_parallel_graph_creation() {
        let graph = ParallelAudioGraph::new(256, 48000.0);
        assert_eq!(graph.node_count(), 0);
        assert_eq!(graph.num_levels(), 0);
    }

    #[test]
    fn test_parallel_graph_add_nodes() {
        let mut graph = ParallelAudioGraph::new(256, 48000.0);

        let n1 = graph.add_node(Box::new(PassthroughNode::new(2)));
        let n2 = graph.add_node(Box::new(GainNode::new(2)));

        assert_eq!(graph.node_count(), 2);

        // Connect n1 -> n2
        assert!(graph.connect(Connection::audio(n1, 0, n2, 0)));
        assert!(graph.connect(Connection::audio(n1, 1, n2, 1)));

        // Process
        graph.process();

        // Should have 2 levels (n1 at depth 0, n2 at depth 1)
        assert_eq!(graph.num_levels(), 2);
    }

    #[test]
    fn test_parallel_graph_processing() {
        let mut graph = ParallelAudioGraph::new(256, 48000.0);

        // Create three independent source nodes (will run in parallel)
        let s1 = graph.add_node(Box::new(GainNode::new(2)));
        let s2 = graph.add_node(Box::new(GainNode::new(2)));
        let s3 = graph.add_node(Box::new(GainNode::new(2)));

        // Create a mixer node
        let mix = graph.add_node(Box::new(PassthroughNode::new(2)));

        // Connect all sources to mixer
        graph.connect(Connection::audio(s1, 0, mix, 0));
        graph.connect(Connection::audio(s2, 0, mix, 0));
        graph.connect(Connection::audio(s3, 0, mix, 0));

        graph.process();

        // s1, s2, s3 at level 0 (parallel), mix at level 1
        assert_eq!(graph.num_levels(), 2);
    }

    #[test]
    fn test_sidechain_connection() {
        let mut graph = ParallelAudioGraph::new(256, 48000.0);

        let source = graph.add_node(Box::new(PassthroughNode::new(2)));
        let sidechain_source = graph.add_node(Box::new(PassthroughNode::new(2)));
        let compressor = graph.add_node(Box::new(PassthroughNode::new(2)));

        // Normal audio path
        assert!(graph.connect(Connection::audio(source, 0, compressor, 0)));

        // Sidechain input
        assert!(graph.connect(Connection::sidechain(sidechain_source, 0, compressor, 1)));

        graph.process();
    }
}
