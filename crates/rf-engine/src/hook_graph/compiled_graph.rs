//! CompiledAudioGraph — Optimized runtime representation of a hook graph.
//!
//! The Dart-side GraphCompiler produces this via JSON → FFI.
//! Topologically sorted node execution order, type-checked connections.

use std::collections::HashMap;

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AudioNodeType {
    Gain = 0,
    Filter = 1,
    Pan = 2,
    Delay = 3,
    Compressor = 4,
    Mixer = 5,
    BusSend = 6,
    PlaySource = 7,
    Envelope = 8,
}

impl AudioNodeType {
    pub fn from_u8(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::Gain),
            1 => Some(Self::Filter),
            2 => Some(Self::Pan),
            3 => Some(Self::Delay),
            4 => Some(Self::Compressor),
            5 => Some(Self::Mixer),
            6 => Some(Self::BusSend),
            7 => Some(Self::PlaySource),
            8 => Some(Self::Envelope),
            _ => None,
        }
    }
}

/// A compiled connection between two nodes
#[derive(Debug, Clone)]
pub struct CompiledConnection {
    pub from_node: u32,
    pub from_port: u8,
    pub to_node: u32,
    pub to_port: u8,
}

/// A compiled node with its type and parameters
#[derive(Debug, Clone)]
pub struct CompiledNode {
    pub node_id: u32,
    pub node_type: AudioNodeType,
    pub params: HashMap<String, f64>,
    pub input_count: u8,
    pub output_count: u8,
}

/// Complete compiled audio graph ready for execution
#[derive(Debug, Clone)]
pub struct CompiledAudioGraph {
    pub graph_id: String,
    pub nodes: Vec<CompiledNode>,
    pub connections: Vec<CompiledConnection>,
    pub execution_order: Vec<u32>,
    pub total_latency_samples: usize,
}

impl CompiledAudioGraph {
    pub fn new(graph_id: String) -> Self {
        Self {
            graph_id,
            nodes: Vec::new(),
            connections: Vec::new(),
            execution_order: Vec::new(),
            total_latency_samples: 0,
        }
    }

    pub fn node_by_id(&self, id: u32) -> Option<&CompiledNode> {
        self.nodes.iter().find(|n| n.node_id == id)
    }

    pub fn connections_to(&self, node_id: u32) -> Vec<&CompiledConnection> {
        self.connections.iter().filter(|c| c.to_node == node_id).collect()
    }

    pub fn connections_from(&self, node_id: u32) -> Vec<&CompiledConnection> {
        self.connections.iter().filter(|c| c.from_node == node_id).collect()
    }
}
