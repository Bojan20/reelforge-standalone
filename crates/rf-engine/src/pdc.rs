//! Plugin Delay Compensation (PDC) System
//!
//! Professional-grade PDC like Cubase/Pro Tools:
//! - Graph-based latency propagation
//! - Sidechain and send path compensation
//! - Constrain Delay Compensation mode
//! - Per-track manual delay adjustment
//! - Real-time latency change handling
//!
//! ## Architecture
//! ```text
//! ┌─────────────────────────────────────────────────────────────────────┐
//! │                    PDC Manager                                       │
//! ├─────────────────────────────────────────────────────────────────────┤
//! │  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐         │
//! │  │ Track 1  │   │ Track 2  │   │ Track 3  │   │  Master  │         │
//! │  │ Lat: 512 │   │ Lat: 0   │   │ Lat: 256 │   │ Lat: 128 │         │
//! │  └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘         │
//! │       │              │              │              │               │
//! │       ▼              ▼              ▼              ▼               │
//! │  ┌──────────┐   ┌──────────┐   ┌──────────┐                        │
//! │  │ Comp: 0  │   │Comp: 512 │   │Comp: 256 │   Max Latency: 512     │
//! │  └──────────┘   └──────────┘   └──────────┘                        │
//! └─────────────────────────────────────────────────────────────────────┘
//! ```
//!
//! ## Constrain Delay Compensation
//! When enabled, limits compensation to specified threshold (e.g., 512 samples)
//! for live monitoring scenarios. Tracks exceeding limit are not compensated.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

use parking_lot::RwLock;
use rf_core::Sample;

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Node identifier in the audio graph
pub type NodeId = u32;

/// Latency in samples
pub type LatencySamples = u32;

/// Maximum supported latency (Cubase supports ~16000, we support more)
pub const MAX_PDC_SAMPLES: LatencySamples = 65536;

/// Default constrain threshold (similar to Cubase default)
pub const DEFAULT_CONSTRAIN_THRESHOLD: LatencySamples = 512;

// ═══════════════════════════════════════════════════════════════════════════════
// NODE TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Type of processing node
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum NodeType {
    /// Audio track
    Track,
    /// Group/bus channel
    Group,
    /// FX/Return channel
    FxReturn,
    /// Master output
    Master,
    /// External sidechain input
    Sidechain,
    /// Send to FX
    Send,
    /// VCA (no audio, control only)
    Vca,
}

/// Connection type between nodes
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionType {
    /// Direct audio routing
    Direct,
    /// Pre-fader send
    PreFaderSend,
    /// Post-fader send
    PostFaderSend,
    /// Sidechain input
    Sidechain,
}

// ═══════════════════════════════════════════════════════════════════════════════
// NODE LATENCY
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete latency information for a node
#[derive(Debug, Clone, Default)]
pub struct NodeLatencyInfo {
    /// Node identifier
    pub node_id: NodeId,
    /// Node type
    pub node_type: NodeType,
    /// Plugin/processing latency introduced by this node
    pub plugin_latency: LatencySamples,
    /// Manual track delay adjustment (positive = delay, negative = advance)
    pub manual_delay: i32,
    /// Cumulative latency from source to this node
    pub path_latency: LatencySamples,
    /// Required compensation delay
    pub compensation: LatencySamples,
    /// Is this node bypassed for PDC (constrain mode)?
    pub pdc_bypassed: bool,
    /// Nodes this node receives audio from
    pub input_nodes: Vec<NodeId>,
    /// Nodes this node sends audio to
    pub output_nodes: Vec<(NodeId, ConnectionType)>,
}

impl Default for NodeType {
    fn default() -> Self {
        NodeType::Track
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DELAY LINE
// ═══════════════════════════════════════════════════════════════════════════════

/// High-performance circular delay line
#[derive(Debug)]
pub struct PdcDelayLine {
    buffer_l: Vec<Sample>,
    buffer_r: Vec<Sample>,
    write_pos: usize,
    delay: usize,
    capacity: usize,
}

impl PdcDelayLine {
    /// Create with maximum capacity
    pub fn new(max_delay: usize) -> Self {
        let capacity = max_delay.max(1);
        Self {
            buffer_l: vec![0.0; capacity],
            buffer_r: vec![0.0; capacity],
            write_pos: 0,
            delay: 0,
            capacity,
        }
    }

    /// Set delay amount
    pub fn set_delay(&mut self, samples: usize) {
        self.delay = samples.min(self.capacity - 1);
    }

    /// Get current delay
    #[inline]
    pub fn delay(&self) -> usize {
        self.delay
    }

    /// Process stereo block in-place
    #[inline]
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        if self.delay == 0 {
            return;
        }

        debug_assert_eq!(left.len(), right.len());
        let len = left.len();

        for i in 0..len {
            let read_pos = (self.write_pos + self.capacity - self.delay) % self.capacity;

            // Read delayed samples
            let out_l = self.buffer_l[read_pos];
            let out_r = self.buffer_r[read_pos];

            // Write new samples
            self.buffer_l[self.write_pos] = left[i];
            self.buffer_r[self.write_pos] = right[i];

            // Output
            left[i] = out_l;
            right[i] = out_r;

            self.write_pos = (self.write_pos + 1) % self.capacity;
        }
    }

    /// Clear buffer
    pub fn clear(&mut self) {
        self.buffer_l.fill(0.0);
        self.buffer_r.fill(0.0);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PDC MANAGER
// ═══════════════════════════════════════════════════════════════════════════════

/// Plugin Delay Compensation Manager
///
/// Handles automatic latency compensation for entire audio graph.
/// Thread-safe for real-time audio callbacks.
pub struct PdcManager {
    /// Node latency information
    nodes: RwLock<HashMap<NodeId, NodeLatencyInfo>>,
    /// Delay lines per node
    delay_lines: RwLock<HashMap<NodeId, PdcDelayLine>>,
    /// Maximum latency in the graph
    max_latency: AtomicU32,
    /// PDC enabled
    enabled: AtomicBool,
    /// Constrain delay compensation mode
    constrain_enabled: AtomicBool,
    /// Constrain threshold in samples
    constrain_threshold: AtomicU32,
    /// Sample rate
    sample_rate: AtomicU32,
    /// Graph needs recalculation
    needs_recalc: AtomicBool,
}

impl PdcManager {
    /// Create new PDC manager
    pub fn new(sample_rate: u32) -> Self {
        Self {
            nodes: RwLock::new(HashMap::new()),
            delay_lines: RwLock::new(HashMap::new()),
            max_latency: AtomicU32::new(0),
            enabled: AtomicBool::new(true),
            constrain_enabled: AtomicBool::new(false),
            constrain_threshold: AtomicU32::new(DEFAULT_CONSTRAIN_THRESHOLD),
            sample_rate: AtomicU32::new(sample_rate),
            needs_recalc: AtomicBool::new(false),
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Configuration
    // ─────────────────────────────────────────────────────────────────────────

    /// Enable/disable PDC
    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Release);
        self.needs_recalc.store(true, Ordering::Release);
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Acquire)
    }

    /// Enable/disable Constrain Delay Compensation
    pub fn set_constrain_enabled(&self, enabled: bool) {
        self.constrain_enabled.store(enabled, Ordering::Release);
        self.needs_recalc.store(true, Ordering::Release);
    }

    pub fn is_constrain_enabled(&self) -> bool {
        self.constrain_enabled.load(Ordering::Acquire)
    }

    /// Set constrain threshold in samples
    pub fn set_constrain_threshold(&self, samples: LatencySamples) {
        self.constrain_threshold.store(samples, Ordering::Release);
        self.needs_recalc.store(true, Ordering::Release);
    }

    pub fn constrain_threshold(&self) -> LatencySamples {
        self.constrain_threshold.load(Ordering::Acquire)
    }

    /// Get constrain threshold in milliseconds
    pub fn constrain_threshold_ms(&self) -> f64 {
        let samples = self.constrain_threshold.load(Ordering::Acquire);
        let sr = self.sample_rate.load(Ordering::Acquire) as f64;
        (samples as f64 / sr) * 1000.0
    }

    /// Set sample rate
    pub fn set_sample_rate(&self, sample_rate: u32) {
        self.sample_rate.store(sample_rate, Ordering::Release);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Node Management
    // ─────────────────────────────────────────────────────────────────────────

    /// Register a processing node
    pub fn register_node(&self, node_id: NodeId, node_type: NodeType) {
        let mut nodes = self.nodes.write();
        let mut delay_lines = self.delay_lines.write();

        if !nodes.contains_key(&node_id) {
            nodes.insert(node_id, NodeLatencyInfo {
                node_id,
                node_type,
                ..Default::default()
            });
            delay_lines.insert(node_id, PdcDelayLine::new(MAX_PDC_SAMPLES as usize));
        }
    }

    /// Unregister a node
    pub fn unregister_node(&self, node_id: NodeId) {
        self.nodes.write().remove(&node_id);
        self.delay_lines.write().remove(&node_id);
        self.needs_recalc.store(true, Ordering::Release);
    }

    /// Add connection between nodes
    pub fn add_connection(&self, from: NodeId, to: NodeId, conn_type: ConnectionType) {
        let mut nodes = self.nodes.write();

        if let Some(from_node) = nodes.get_mut(&from) {
            if !from_node.output_nodes.iter().any(|(id, _)| *id == to) {
                from_node.output_nodes.push((to, conn_type));
            }
        }

        if let Some(to_node) = nodes.get_mut(&to) {
            if !to_node.input_nodes.contains(&from) {
                to_node.input_nodes.push(from);
            }
        }

        self.needs_recalc.store(true, Ordering::Release);
    }

    /// Remove connection
    pub fn remove_connection(&self, from: NodeId, to: NodeId) {
        let mut nodes = self.nodes.write();

        if let Some(from_node) = nodes.get_mut(&from) {
            from_node.output_nodes.retain(|(id, _)| *id != to);
        }

        if let Some(to_node) = nodes.get_mut(&to) {
            to_node.input_nodes.retain(|id| *id != from);
        }

        self.needs_recalc.store(true, Ordering::Release);
    }

    /// Report plugin latency for a node
    pub fn report_latency(&self, node_id: NodeId, latency: LatencySamples) {
        let mut nodes = self.nodes.write();
        if let Some(node) = nodes.get_mut(&node_id) {
            if node.plugin_latency != latency {
                node.plugin_latency = latency;
                self.needs_recalc.store(true, Ordering::Release);
            }
        }
    }

    /// Set manual delay adjustment for a track
    pub fn set_manual_delay(&self, node_id: NodeId, delay_samples: i32) {
        let mut nodes = self.nodes.write();
        if let Some(node) = nodes.get_mut(&node_id) {
            node.manual_delay = delay_samples;
            self.needs_recalc.store(true, Ordering::Release);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Query
    // ─────────────────────────────────────────────────────────────────────────

    /// Get total system latency
    pub fn total_latency(&self) -> LatencySamples {
        self.max_latency.load(Ordering::Acquire)
    }

    /// Get total latency in milliseconds
    pub fn total_latency_ms(&self) -> f64 {
        let samples = self.max_latency.load(Ordering::Acquire);
        let sr = self.sample_rate.load(Ordering::Acquire) as f64;
        (samples as f64 / sr) * 1000.0
    }

    /// Get node latency info
    pub fn get_node_info(&self, node_id: NodeId) -> Option<NodeLatencyInfo> {
        self.nodes.read().get(&node_id).cloned()
    }

    /// Get all node IDs
    pub fn node_ids(&self) -> Vec<NodeId> {
        self.nodes.read().keys().copied().collect()
    }

    /// Get compensation delay for a specific node
    pub fn get_compensation(&self, node_id: NodeId) -> LatencySamples {
        self.nodes.read()
            .get(&node_id)
            .map(|n| n.compensation)
            .unwrap_or(0)
    }

    /// Check if node is PDC bypassed (constrain mode)
    pub fn is_node_bypassed(&self, node_id: NodeId) -> bool {
        self.nodes.read()
            .get(&node_id)
            .map(|n| n.pdc_bypassed)
            .unwrap_or(false)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Graph Calculation
    // ─────────────────────────────────────────────────────────────────────────

    /// Recalculate all compensation delays
    /// Call this from non-audio thread when graph changes
    pub fn recalculate(&self) {
        if !self.needs_recalc.swap(false, Ordering::AcqRel) {
            return;
        }

        let enabled = self.enabled.load(Ordering::Acquire);
        let constrain = self.constrain_enabled.load(Ordering::Acquire);
        let threshold = self.constrain_threshold.load(Ordering::Acquire);

        let mut nodes = self.nodes.write();
        let mut delay_lines = self.delay_lines.write();

        if !enabled {
            // Disable all compensation
            for node in nodes.values_mut() {
                node.compensation = 0;
                node.pdc_bypassed = false;
            }
            for line in delay_lines.values_mut() {
                line.set_delay(0);
            }
            self.max_latency.store(0, Ordering::Release);
            return;
        }

        // Build sorted node list (topological order)
        let sorted = self.topological_sort(&nodes);

        // Phase 1: Calculate path latencies (forward pass)
        for &node_id in &sorted {
            // First, collect input latencies without holding mutable borrow
            let (max_input_latency, plugin_lat, manual_delay) = {
                if let Some(node) = nodes.get(&node_id) {
                    let max_input = node.input_nodes.iter()
                        .filter_map(|&input_id| nodes.get(&input_id))
                        .map(|input| input.path_latency)
                        .max()
                        .unwrap_or(0);
                    (max_input, node.plugin_latency, node.manual_delay)
                } else {
                    continue;
                }
            };

            // Now update with mutable borrow
            if let Some(node) = nodes.get_mut(&node_id) {
                let manual = manual_delay.max(0) as u32;
                node.path_latency = max_input_latency + plugin_lat + manual;
            }
        }

        // Find maximum latency
        let mut max_lat = nodes.values()
            .filter(|n| n.output_nodes.is_empty()) // Leaf nodes (outputs)
            .map(|n| n.path_latency)
            .max()
            .unwrap_or(0);

        // Apply constrain threshold if enabled
        if constrain {
            max_lat = max_lat.min(threshold);
        }

        // Phase 2: Calculate compensation (reverse pass)
        for node in nodes.values_mut() {
            if constrain && node.plugin_latency > threshold {
                // This node exceeds threshold - bypass PDC
                node.compensation = 0;
                node.pdc_bypassed = true;
            } else {
                // Compensation = max latency - this node's path latency
                node.compensation = max_lat.saturating_sub(node.path_latency);
                node.pdc_bypassed = false;
            }

            // Update delay line
            if let Some(line) = delay_lines.get_mut(&node.node_id) {
                line.set_delay(node.compensation as usize);
            }
        }

        self.max_latency.store(max_lat, Ordering::Release);

        log::debug!(
            "PDC: recalculated, max_latency={} samples ({:.2}ms), constrain={}",
            max_lat,
            (max_lat as f64 / self.sample_rate.load(Ordering::Acquire) as f64) * 1000.0,
            constrain
        );
    }

    /// Topological sort of nodes
    fn topological_sort(&self, nodes: &HashMap<NodeId, NodeLatencyInfo>) -> Vec<NodeId> {
        let mut result = Vec::with_capacity(nodes.len());
        let mut visited = HashSet::new();
        let mut temp_visited = HashSet::new();

        fn visit(
            node_id: NodeId,
            nodes: &HashMap<NodeId, NodeLatencyInfo>,
            visited: &mut HashSet<NodeId>,
            temp_visited: &mut HashSet<NodeId>,
            result: &mut Vec<NodeId>,
        ) {
            if visited.contains(&node_id) {
                return;
            }
            if temp_visited.contains(&node_id) {
                // Cycle detected - skip
                return;
            }

            temp_visited.insert(node_id);

            if let Some(node) = nodes.get(&node_id) {
                for &input_id in &node.input_nodes {
                    visit(input_id, nodes, visited, temp_visited, result);
                }
            }

            temp_visited.remove(&node_id);
            visited.insert(node_id);
            result.push(node_id);
        }

        for &node_id in nodes.keys() {
            visit(node_id, nodes, &mut visited, &mut temp_visited, &mut result);
        }

        result
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Audio Processing
    // ─────────────────────────────────────────────────────────────────────────

    /// Process compensation for a node (stereo)
    /// Call from audio thread
    #[inline]
    pub fn process(&self, node_id: NodeId, left: &mut [Sample], right: &mut [Sample]) {
        if !self.enabled.load(Ordering::Relaxed) {
            return;
        }

        // Try to get delay line without blocking
        if let Some(mut delay_lines) = self.delay_lines.try_write() {
            if let Some(line) = delay_lines.get_mut(&node_id) {
                line.process(left, right);
            }
        }
        // If can't acquire lock, skip this block (no glitches, just slight timing offset)
    }

    /// Process compensation for a node (mono)
    #[inline]
    pub fn process_mono(&self, node_id: NodeId, buffer: &mut [Sample]) {
        if !self.enabled.load(Ordering::Relaxed) {
            return;
        }

        if let Some(mut delay_lines) = self.delay_lines.try_write() {
            if let Some(line) = delay_lines.get_mut(&node_id) {
                // Process mono by treating it as stereo with same buffer
                let mut dummy = vec![0.0; buffer.len()];
                line.process(buffer, &mut dummy);
            }
        }
    }

    /// Clear all delay buffers (call on stop/seek)
    pub fn clear_all(&self) {
        let mut delay_lines = self.delay_lines.write();
        for line in delay_lines.values_mut() {
            line.clear();
        }
    }
}

impl Default for PdcManager {
    fn default() -> Self {
        Self::new(48000)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PDC STATS
// ═══════════════════════════════════════════════════════════════════════════════

/// PDC statistics for display
#[derive(Debug, Clone, Default)]
pub struct PdcStats {
    /// Total system latency in samples
    pub total_latency_samples: LatencySamples,
    /// Total system latency in milliseconds
    pub total_latency_ms: f64,
    /// PDC enabled
    pub enabled: bool,
    /// Constrain mode enabled
    pub constrain_enabled: bool,
    /// Constrain threshold
    pub constrain_threshold: LatencySamples,
    /// Number of nodes with compensation
    pub compensated_nodes: usize,
    /// Number of bypassed nodes (constrain mode)
    pub bypassed_nodes: usize,
    /// Highest single plugin latency
    pub highest_plugin_latency: LatencySamples,
    /// Node with highest latency
    pub highest_latency_node: Option<NodeId>,
}

impl PdcManager {
    /// Get current PDC statistics
    pub fn stats(&self) -> PdcStats {
        let nodes = self.nodes.read();
        let sample_rate = self.sample_rate.load(Ordering::Acquire) as f64;
        let total = self.max_latency.load(Ordering::Acquire);

        let mut highest_plugin = 0;
        let mut highest_node = None;
        let mut compensated = 0;
        let mut bypassed = 0;

        for node in nodes.values() {
            if node.plugin_latency > highest_plugin {
                highest_plugin = node.plugin_latency;
                highest_node = Some(node.node_id);
            }
            if node.compensation > 0 {
                compensated += 1;
            }
            if node.pdc_bypassed {
                bypassed += 1;
            }
        }

        PdcStats {
            total_latency_samples: total,
            total_latency_ms: (total as f64 / sample_rate) * 1000.0,
            enabled: self.enabled.load(Ordering::Acquire),
            constrain_enabled: self.constrain_enabled.load(Ordering::Acquire),
            constrain_threshold: self.constrain_threshold.load(Ordering::Acquire),
            compensated_nodes: compensated,
            bypassed_nodes: bypassed,
            highest_plugin_latency: highest_plugin,
            highest_latency_node: highest_node,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SIDECHAIN PDC
// ═══════════════════════════════════════════════════════════════════════════════

/// Sidechain-specific delay compensation
/// Ensures sidechain input arrives at the same time as main input
#[derive(Debug)]
pub struct SidechainPdc {
    delay_line: PdcDelayLine,
    source_node: NodeId,
    target_node: NodeId,
}

impl SidechainPdc {
    pub fn new(source: NodeId, target: NodeId) -> Self {
        Self {
            delay_line: PdcDelayLine::new(MAX_PDC_SAMPLES as usize),
            source_node: source,
            target_node: target,
        }
    }

    /// Update delay based on path difference
    pub fn update_delay(&mut self, pdc: &PdcManager) {
        let nodes = pdc.nodes.read();

        let source_latency = nodes.get(&self.source_node)
            .map(|n| n.path_latency)
            .unwrap_or(0);
        let target_latency = nodes.get(&self.target_node)
            .map(|n| n.path_latency)
            .unwrap_or(0);

        // Delay sidechain to match target's timing
        let delay = target_latency.saturating_sub(source_latency);
        self.delay_line.set_delay(delay as usize);
    }

    #[inline]
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.delay_line.process(left, right);
    }

    pub fn clear(&mut self) {
        self.delay_line.clear();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEND PDC
// ═══════════════════════════════════════════════════════════════════════════════

/// Send effect delay compensation
/// Compensates for latency difference between dry and wet paths
#[derive(Debug)]
pub struct SendPdc {
    delay_line: PdcDelayLine,
    send_node: NodeId,
    return_node: NodeId,
}

impl SendPdc {
    pub fn new(send_node: NodeId, return_node: NodeId) -> Self {
        Self {
            delay_line: PdcDelayLine::new(MAX_PDC_SAMPLES as usize),
            send_node,
            return_node,
        }
    }

    /// Update delay based on FX return latency
    pub fn update_delay(&mut self, pdc: &PdcManager) {
        let nodes = pdc.nodes.read();

        // FX return introduces latency, we need to delay the dry signal
        let return_latency = nodes.get(&self.return_node)
            .map(|n| n.plugin_latency)
            .unwrap_or(0);

        self.delay_line.set_delay(return_latency as usize);
    }

    #[inline]
    pub fn process_dry(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        self.delay_line.process(left, right);
    }

    pub fn clear(&mut self) {
        self.delay_line.clear();
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_delay_line_zero() {
        let mut line = PdcDelayLine::new(1024);
        line.set_delay(0);

        let mut l = [1.0, 2.0, 3.0];
        let mut r = [4.0, 5.0, 6.0];
        line.process(&mut l, &mut r);

        assert_eq!(l, [1.0, 2.0, 3.0]);
        assert_eq!(r, [4.0, 5.0, 6.0]);
    }

    #[test]
    fn test_delay_line_fixed() {
        let mut line = PdcDelayLine::new(1024);
        line.set_delay(2);

        let mut l = [1.0, 2.0, 3.0, 4.0, 5.0];
        let mut r = [1.0, 2.0, 3.0, 4.0, 5.0];
        line.process(&mut l, &mut r);

        // First 2 samples are zeros (initial buffer), then delayed input
        assert!((l[0] - 0.0).abs() < 1e-10);
        assert!((l[1] - 0.0).abs() < 1e-10);
        assert!((l[2] - 1.0).abs() < 1e-10);
        assert!((l[3] - 2.0).abs() < 1e-10);
        assert!((l[4] - 3.0).abs() < 1e-10);
    }

    #[test]
    fn test_pdc_manager_basic() {
        let pdc = PdcManager::new(48000);

        pdc.register_node(1, NodeType::Track);
        pdc.register_node(2, NodeType::Track);
        pdc.register_node(3, NodeType::Master);

        // Track 1 -> Master, Track 2 -> Master
        pdc.add_connection(1, 3, ConnectionType::Direct);
        pdc.add_connection(2, 3, ConnectionType::Direct);

        // Track 1 has 512 samples latency, Track 2 has none
        pdc.report_latency(1, 512);
        pdc.report_latency(2, 0);

        pdc.needs_recalc.store(true, Ordering::Release);
        pdc.recalculate();

        // Total latency should be 512
        assert_eq!(pdc.total_latency(), 512);

        // Track 2 needs 512 compensation, Track 1 needs 0
        assert_eq!(pdc.get_compensation(2), 512);
        assert_eq!(pdc.get_compensation(1), 0);
    }

    #[test]
    fn test_pdc_constrain() {
        let pdc = PdcManager::new(48000);

        pdc.register_node(1, NodeType::Track);
        pdc.report_latency(1, 2048);

        pdc.set_constrain_enabled(true);
        pdc.set_constrain_threshold(512);
        pdc.needs_recalc.store(true, Ordering::Release);
        pdc.recalculate();

        // Node should be bypassed
        assert!(pdc.is_node_bypassed(1));
        assert_eq!(pdc.get_compensation(1), 0);
    }

    #[test]
    fn test_pdc_disabled() {
        let pdc = PdcManager::new(48000);

        pdc.register_node(1, NodeType::Track);
        pdc.report_latency(1, 512);

        pdc.set_enabled(false);
        pdc.needs_recalc.store(true, Ordering::Release);
        pdc.recalculate();

        assert_eq!(pdc.total_latency(), 0);
        assert_eq!(pdc.get_compensation(1), 0);
    }

    #[test]
    fn test_pdc_chain() {
        let pdc = PdcManager::new(48000);

        // Track -> Group -> Master
        pdc.register_node(1, NodeType::Track);
        pdc.register_node(2, NodeType::Group);
        pdc.register_node(3, NodeType::Master);

        pdc.add_connection(1, 2, ConnectionType::Direct);
        pdc.add_connection(2, 3, ConnectionType::Direct);

        pdc.report_latency(1, 100);
        pdc.report_latency(2, 200);
        pdc.report_latency(3, 50);

        pdc.needs_recalc.store(true, Ordering::Release);
        pdc.recalculate();

        // Path latencies: Track=100, Group=300, Master=350
        // Total = 350, compensations: Track=250, Group=50, Master=0
        assert_eq!(pdc.total_latency(), 350);
    }
}
