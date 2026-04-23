//! GraphInstancePool — Pre-allocated pool of graph execution instances.
//!
//! Each active event gets its own graph instance from the pool.
//! Instances are recycled (not deallocated) when done.

use super::audio_node::{AudioBuffer, AudioNode};
use super::compiled_graph::CompiledAudioGraph;
use std::collections::HashMap;

const MAX_INSTANCES: usize = 50;
const HARD_LIMIT: usize = 100;

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstanceState {
    Pooled = 0,
    Allocated = 1,
    Executing = 2,
    Finishing = 3,
    Done = 4,
}

pub struct GraphInstance {
    pub id: u32,
    pub state: InstanceState,
    pub graph_id: String,
    pub nodes: Vec<Box<dyn AudioNode>>,
    pub buffers: Vec<AudioBuffer>,
    pub params: HashMap<String, f64>,
    pub tick: u64,
}

impl GraphInstance {
    fn new(id: u32, _max_block_size: usize) -> Self {
        Self {
            id,
            state: InstanceState::Pooled,
            graph_id: String::new(),
            nodes: Vec::new(),
            buffers: Vec::new(),
            params: HashMap::new(),
            tick: 0,
        }
    }

    pub fn activate(&mut self, graph: &CompiledAudioGraph) {
        self.state = InstanceState::Allocated;
        self.graph_id = graph.graph_id.clone();
        self.tick = 0;
        self.params.clear();
        for node in &mut self.nodes {
            node.reset();
        }
    }

    pub fn recycle(&mut self) {
        self.state = InstanceState::Pooled;
        self.graph_id.clear();
        self.nodes.clear();
        self.buffers.clear();
        self.params.clear();
        self.tick = 0;
    }

    pub fn is_available(&self) -> bool {
        self.state == InstanceState::Pooled
    }
}

pub struct GraphInstancePool {
    instances: Vec<GraphInstance>,
    active_count: usize,
}

impl GraphInstancePool {
    pub fn new(max_block_size: usize) -> Self {
        let instances = (0..MAX_INSTANCES as u32)
            .map(|i| GraphInstance::new(i, max_block_size))
            .collect();
        Self {
            instances,
            active_count: 0,
        }
    }

    pub fn allocate(&mut self, graph: &CompiledAudioGraph) -> Option<u32> {
        if self.active_count >= HARD_LIMIT {
            return None;
        }

        // Find pooled instance
        for instance in &mut self.instances {
            if instance.is_available() {
                instance.activate(graph);
                self.active_count += 1;
                return Some(instance.id);
            }
        }

        // Grow pool if under hard limit
        if self.instances.len() < HARD_LIMIT {
            let id = self.instances.len() as u32;
            let mut instance = GraphInstance::new(id, 1024);
            instance.activate(graph);
            self.instances.push(instance);
            self.active_count += 1;
            return Some(id);
        }

        None
    }

    pub fn release(&mut self, instance_id: u32) {
        if let Some(inst) = self.instances.iter_mut().find(|i| i.id == instance_id)
            && inst.state != InstanceState::Pooled {
                inst.recycle();
                self.active_count = self.active_count.saturating_sub(1);
            }
    }

    pub fn instance(&self, id: u32) -> Option<&GraphInstance> {
        self.instances.iter().find(|i| i.id == id && !i.is_available())
    }

    pub fn instance_mut(&mut self, id: u32) -> Option<&mut GraphInstance> {
        self.instances.iter_mut().find(|i| i.id == id && !i.is_available())
    }

    pub fn active_count(&self) -> usize {
        self.active_count
    }

    pub fn tick_all(&mut self) {
        for instance in &mut self.instances {
            if instance.state == InstanceState::Done {
                instance.recycle();
                self.active_count = self.active_count.saturating_sub(1);
            }
        }
    }
}
