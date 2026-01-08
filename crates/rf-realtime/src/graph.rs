//! Real-Time Processing Graph
//!
//! Unified processing graph that connects all Phase 3 modules:
//! - rf-ml (AI processing)
//! - rf-spatial (immersive audio)
//! - rf-restore (audio restoration)
//! - rf-master (intelligent mastering)
//! - rf-pitch (polyphonic pitch)

use std::collections::HashMap;
use portable_atomic::{AtomicU64, Ordering};

/// Unique identifier for graph nodes
pub type NodeId = u64;

/// Processing graph node types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum NodeType {
    // Input/Output
    AudioInput,
    AudioOutput,

    // Phase 3 Modules
    MlStemSeparation,
    MlDenoise,
    MlEnhance,
    MlVoiceIsolation,

    SpatialPanner,
    SpatialBinaural,
    SpatialReverb,
    SpatialAmbisonics,

    RestoreDenoise,
    RestoreDeclick,
    RestoreDeclip,
    RestoreDehum,
    RestoreDereverb,

    MasterLimiter,
    MasterEq,
    MasterCompressor,
    MasterStereoWidth,
    MasterLoudness,

    PitchDetector,
    PitchCorrector,
    PitchShifter,

    // Utility
    Mixer,
    Splitter,
    Gain,
    Bypass,
}

/// Connection between nodes
#[derive(Debug, Clone, Copy)]
pub struct Connection {
    pub from_node: NodeId,
    pub from_port: u32,
    pub to_node: NodeId,
    pub to_port: u32,
}

/// Processing order for a node
#[derive(Debug, Clone)]
pub struct ProcessingSlot {
    pub node_id: NodeId,
    pub node_type: NodeType,
    pub inputs: Vec<(NodeId, u32)>,  // (source_node, port)
    pub outputs: Vec<(NodeId, u32)>, // (dest_node, port)
    pub latency_samples: u32,
}

/// Real-time processing graph
pub struct ProcessingGraph {
    /// All nodes in the graph
    nodes: HashMap<NodeId, GraphNode>,
    /// Connections between nodes
    connections: Vec<Connection>,
    /// Topologically sorted processing order
    processing_order: Vec<ProcessingSlot>,
    /// Total graph latency
    total_latency: u32,
    /// Next node ID
    next_id: AtomicU64,
    /// Sample rate
    sample_rate: f64,
    /// Block size
    block_size: usize,
}

/// Individual node in the graph
pub struct GraphNode {
    pub id: NodeId,
    pub node_type: NodeType,
    pub enabled: bool,
    pub latency_samples: u32,
    /// Processing state (type-erased)
    state: Box<dyn NodeState + Send + Sync>,
}

/// Trait for node processing state
pub trait NodeState {
    /// Process a block of audio
    fn process(&mut self, inputs: &[&[f64]], outputs: &mut [&mut [f64]]);

    /// Get the latency in samples
    fn latency(&self) -> u32;

    /// Reset the processor state
    fn reset(&mut self);

    /// Get number of input channels
    fn num_inputs(&self) -> usize;

    /// Get number of output channels
    fn num_outputs(&self) -> usize;
}

impl ProcessingGraph {
    /// Create a new processing graph
    pub fn new(sample_rate: f64, block_size: usize) -> Self {
        Self {
            nodes: HashMap::new(),
            connections: Vec::new(),
            processing_order: Vec::new(),
            total_latency: 0,
            next_id: AtomicU64::new(1),
            sample_rate,
            block_size,
        }
    }

    /// Add a node to the graph
    pub fn add_node(&mut self, node_type: NodeType, state: Box<dyn NodeState + Send + Sync>) -> NodeId {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let latency = state.latency();

        let node = GraphNode {
            id,
            node_type,
            enabled: true,
            latency_samples: latency,
            state,
        };

        self.nodes.insert(id, node);
        id
    }

    /// Remove a node from the graph
    pub fn remove_node(&mut self, id: NodeId) -> bool {
        // Remove all connections to/from this node
        self.connections.retain(|c| c.from_node != id && c.to_node != id);
        self.nodes.remove(&id).is_some()
    }

    /// Connect two nodes
    pub fn connect(&mut self, from: NodeId, from_port: u32, to: NodeId, to_port: u32) -> bool {
        if !self.nodes.contains_key(&from) || !self.nodes.contains_key(&to) {
            return false;
        }

        // Check for cycles
        if self.would_create_cycle(from, to) {
            return false;
        }

        self.connections.push(Connection {
            from_node: from,
            from_port,
            to_node: to,
            to_port,
        });

        // Recalculate processing order
        self.update_processing_order();
        true
    }

    /// Disconnect two nodes
    pub fn disconnect(&mut self, from: NodeId, to: NodeId) -> bool {
        let len = self.connections.len();
        self.connections.retain(|c| !(c.from_node == from && c.to_node == to));

        if self.connections.len() != len {
            self.update_processing_order();
            true
        } else {
            false
        }
    }

    /// Check if connecting would create a cycle
    fn would_create_cycle(&self, from: NodeId, to: NodeId) -> bool {
        // DFS from 'to' to check if we can reach 'from'
        let mut visited = std::collections::HashSet::new();
        let mut stack = vec![to];

        while let Some(current) = stack.pop() {
            if current == from {
                return true;
            }
            if visited.insert(current) {
                for conn in &self.connections {
                    if conn.from_node == current {
                        stack.push(conn.to_node);
                    }
                }
            }
        }
        false
    }

    /// Update processing order using topological sort
    fn update_processing_order(&mut self) {
        // Kahn's algorithm for topological sort
        let mut in_degree: HashMap<NodeId, usize> = HashMap::new();
        let mut queue: Vec<NodeId> = Vec::new();

        // Initialize in-degrees
        for &id in self.nodes.keys() {
            in_degree.insert(id, 0);
        }
        for conn in &self.connections {
            *in_degree.get_mut(&conn.to_node).unwrap() += 1;
        }

        // Find all nodes with no incoming edges
        for (&id, &degree) in &in_degree {
            if degree == 0 {
                queue.push(id);
            }
        }

        // Build processing order
        self.processing_order.clear();
        while let Some(id) = queue.pop() {
            if let Some(node) = self.nodes.get(&id) {
                let inputs: Vec<(NodeId, u32)> = self.connections
                    .iter()
                    .filter(|c| c.to_node == id)
                    .map(|c| (c.from_node, c.from_port))
                    .collect();

                let outputs: Vec<(NodeId, u32)> = self.connections
                    .iter()
                    .filter(|c| c.from_node == id)
                    .map(|c| (c.to_node, c.to_port))
                    .collect();

                self.processing_order.push(ProcessingSlot {
                    node_id: id,
                    node_type: node.node_type,
                    inputs,
                    outputs: outputs.clone(),
                    latency_samples: node.latency_samples,
                });

                // Decrease in-degree of neighbors
                for conn in &self.connections {
                    if conn.from_node == id {
                        let degree = in_degree.get_mut(&conn.to_node).unwrap();
                        *degree -= 1;
                        if *degree == 0 {
                            queue.push(conn.to_node);
                        }
                    }
                }
            }
        }

        // Calculate total latency
        self.calculate_total_latency();
    }

    /// Calculate total graph latency
    fn calculate_total_latency(&mut self) {
        // Find maximum latency path from input to output
        let mut latencies: HashMap<NodeId, u32> = HashMap::new();

        for slot in &self.processing_order {
            let max_input_latency = slot.inputs
                .iter()
                .filter_map(|(id, _)| latencies.get(id))
                .max()
                .copied()
                .unwrap_or(0);

            latencies.insert(slot.node_id, max_input_latency + slot.latency_samples);
        }

        self.total_latency = latencies.values().max().copied().unwrap_or(0);
    }

    /// Get total graph latency
    pub fn total_latency(&self) -> u32 {
        self.total_latency
    }

    /// Get processing order
    pub fn processing_order(&self) -> &[ProcessingSlot] {
        &self.processing_order
    }

    /// Process a block of audio through the graph
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        // Buffer storage for intermediate results
        let mut buffers: HashMap<NodeId, Vec<f64>> = HashMap::new();

        // Initialize with input
        if let Some(input_node) = self.processing_order.first() {
            buffers.insert(input_node.node_id, input.to_vec());
        }

        // Process each node in order
        for slot in &self.processing_order {
            // Gather inputs
            let input_buffers: Vec<Vec<f64>> = slot.inputs
                .iter()
                .filter_map(|(id, _)| buffers.get(id).cloned())
                .collect();

            let input_refs: Vec<&[f64]> = input_buffers.iter().map(|b| b.as_slice()).collect();

            // Process
            if let Some(node) = self.nodes.get_mut(&slot.node_id) {
                if node.enabled {
                    let mut output_buffer = vec![0.0; self.block_size];
                    let mut output_refs: Vec<&mut [f64]> = vec![&mut output_buffer];

                    node.state.process(&input_refs, &mut output_refs);
                    buffers.insert(slot.node_id, output_buffer);
                } else {
                    // Bypass: pass first input to output
                    if let Some(first_input) = input_buffers.first() {
                        buffers.insert(slot.node_id, first_input.clone());
                    }
                }
            }
        }

        // Copy final output
        if let Some(output_node) = self.processing_order.last() {
            if let Some(final_buffer) = buffers.get(&output_node.node_id) {
                output.copy_from_slice(&final_buffer[..output.len().min(final_buffer.len())]);
            }
        }
    }

    /// Enable/disable a node
    pub fn set_enabled(&mut self, id: NodeId, enabled: bool) {
        if let Some(node) = self.nodes.get_mut(&id) {
            node.enabled = enabled;
        }
    }

    /// Get node by ID
    pub fn get_node(&self, id: NodeId) -> Option<&GraphNode> {
        self.nodes.get(&id)
    }

    /// Get mutable node by ID
    pub fn get_node_mut(&mut self, id: NodeId) -> Option<&mut GraphNode> {
        self.nodes.get_mut(&id)
    }

    /// Reset all nodes
    pub fn reset(&mut self) {
        for node in self.nodes.values_mut() {
            node.state.reset();
        }
    }
}

/// Bypass node - passes audio through unchanged
pub struct BypassNode {
    num_channels: usize,
}

impl BypassNode {
    pub fn new(num_channels: usize) -> Self {
        Self { num_channels }
    }
}

impl NodeState for BypassNode {
    fn process(&mut self, inputs: &[&[f64]], outputs: &mut [&mut [f64]]) {
        for (input, output) in inputs.iter().zip(outputs.iter_mut()) {
            output.copy_from_slice(input);
        }
    }

    fn latency(&self) -> u32 { 0 }
    fn reset(&mut self) {}
    fn num_inputs(&self) -> usize { self.num_channels }
    fn num_outputs(&self) -> usize { self.num_channels }
}

/// Gain node - adjusts gain with smoothing
pub struct GainNode {
    gain: f64,
    target_gain: f64,
    smoothing_coeff: f64,
}

impl GainNode {
    pub fn new(gain_db: f64, sample_rate: f64) -> Self {
        let gain = 10.0_f64.powf(gain_db / 20.0);
        let smoothing_time_ms = 10.0;
        let smoothing_coeff = (-2.0 * std::f64::consts::PI * 1000.0 / smoothing_time_ms / sample_rate).exp();

        Self {
            gain,
            target_gain: gain,
            smoothing_coeff,
        }
    }

    pub fn set_gain_db(&mut self, gain_db: f64) {
        self.target_gain = 10.0_f64.powf(gain_db / 20.0);
    }
}

impl NodeState for GainNode {
    fn process(&mut self, inputs: &[&[f64]], outputs: &mut [&mut [f64]]) {
        for (input, output) in inputs.iter().zip(outputs.iter_mut()) {
            for (i, &sample) in input.iter().enumerate() {
                // Smooth gain transition
                self.gain = self.target_gain + self.smoothing_coeff * (self.gain - self.target_gain);
                output[i] = sample * self.gain;
            }
        }
    }

    fn latency(&self) -> u32 { 0 }
    fn reset(&mut self) { self.gain = self.target_gain; }
    fn num_inputs(&self) -> usize { 2 }
    fn num_outputs(&self) -> usize { 2 }
}

/// Mixer node - sums multiple inputs
pub struct MixerNode {
    num_inputs: usize,
    gains: Vec<f64>,
}

impl MixerNode {
    pub fn new(num_inputs: usize) -> Self {
        Self {
            num_inputs,
            gains: vec![1.0; num_inputs],
        }
    }

    pub fn set_input_gain(&mut self, input: usize, gain_db: f64) {
        if input < self.gains.len() {
            self.gains[input] = 10.0_f64.powf(gain_db / 20.0);
        }
    }
}

impl NodeState for MixerNode {
    fn process(&mut self, inputs: &[&[f64]], outputs: &mut [&mut [f64]]) {
        if outputs.is_empty() || inputs.is_empty() {
            return;
        }

        // Clear output
        for sample in outputs[0].iter_mut() {
            *sample = 0.0;
        }

        // Sum all inputs with gains
        for (i, input) in inputs.iter().enumerate() {
            let gain = self.gains.get(i).copied().unwrap_or(1.0);
            for (j, &sample) in input.iter().enumerate() {
                if j < outputs[0].len() {
                    outputs[0][j] += sample * gain;
                }
            }
        }
    }

    fn latency(&self) -> u32 { 0 }
    fn reset(&mut self) {}
    fn num_inputs(&self) -> usize { self.num_inputs }
    fn num_outputs(&self) -> usize { 1 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_graph_creation() {
        let graph = ProcessingGraph::new(48000.0, 512);
        assert_eq!(graph.total_latency(), 0);
    }

    #[test]
    fn test_node_addition() {
        let mut graph = ProcessingGraph::new(48000.0, 512);
        let id = graph.add_node(NodeType::Gain, Box::new(GainNode::new(0.0, 48000.0)));
        assert!(graph.get_node(id).is_some());
    }

    #[test]
    fn test_connection() {
        let mut graph = ProcessingGraph::new(48000.0, 512);
        let id1 = graph.add_node(NodeType::AudioInput, Box::new(BypassNode::new(2)));
        let id2 = graph.add_node(NodeType::Gain, Box::new(GainNode::new(0.0, 48000.0)));
        let id3 = graph.add_node(NodeType::AudioOutput, Box::new(BypassNode::new(2)));

        assert!(graph.connect(id1, 0, id2, 0));
        assert!(graph.connect(id2, 0, id3, 0));
        assert_eq!(graph.processing_order().len(), 3);
    }

    #[test]
    fn test_cycle_detection() {
        let mut graph = ProcessingGraph::new(48000.0, 512);
        let id1 = graph.add_node(NodeType::Gain, Box::new(GainNode::new(0.0, 48000.0)));
        let id2 = graph.add_node(NodeType::Gain, Box::new(GainNode::new(0.0, 48000.0)));

        assert!(graph.connect(id1, 0, id2, 0));
        // This should fail - would create cycle
        assert!(!graph.connect(id2, 0, id1, 0));
    }

    #[test]
    fn test_bypass_processing() {
        let mut node = BypassNode::new(1);

        let input = [1.0, 2.0, 3.0, 4.0];
        let mut output = [0.0; 4];

        node.process(&[&input], &mut [&mut output]);

        // Output should equal input
        assert_eq!(output, input);
    }

    #[test]
    fn test_gain_node() {
        let mut node = GainNode::new(-6.0, 48000.0);
        let input = [1.0];
        let mut output = [0.0];

        node.process(&[&input], &mut [&mut output]);

        // -6dB ≈ 0.5
        assert!((output[0] - 0.501).abs() < 0.01);
    }

    #[test]
    fn test_mixer_node() {
        let mut node = MixerNode::new(2);
        let input1 = [1.0];
        let input2 = [2.0];
        let mut output = [0.0];

        node.process(&[&input1, &input2], &mut [&mut output]);

        // Sum should be 3.0
        assert_eq!(output[0], 3.0);
    }
}
