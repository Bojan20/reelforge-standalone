//! Dynamic Routing Graph System
//!
//! Professional bus/aux/group architecture inspired by:
//! - Reaper's flexibility (tracks are just tracks)
//! - Cubase's intuitiveness (semantic channel types)
//! - Pro Tools' robustness (master fader architecture)
//!
//! ## Core Principles
//! - No hardcoded bus types (no "SFX bus", "Voice bus" etc)
//! - Dynamic creation/deletion of channels
//! - Full routing graph with feedback prevention
//! - Hierarchical bus routing (bus can feed another bus)
//! - Pre/post fader sends with post-pan option
//!
//! ## Channel Types
//! - Audio: Standard track with clips
//! - Bus: Group/submix channel
//! - Aux: Send effect return
//! - VCA: Level control only (no audio routing)
//! - Master: Final output stage

use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use serde::{Deserialize, Serialize};

use rf_core::Sample;

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Channel kind (semantic label, not hardcoded behavior)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
pub enum ChannelKind {
    /// Standard audio track (has clips)
    #[default]
    Audio,
    /// Bus/Group for submixing
    Bus,
    /// Aux/FX for send effects
    Aux,
    /// VCA (controls levels, no audio routing)
    Vca,
    /// Master output (special, single instance)
    Master,
}

impl ChannelKind {
    /// Get default color for channel kind
    pub fn default_color(&self) -> u32 {
        match self {
            ChannelKind::Audio => 0x4a9eff,  // Blue
            ChannelKind::Bus => 0x40ff90,    // Green
            ChannelKind::Aux => 0xff9040,    // Orange
            ChannelKind::Vca => 0xffff40,    // Yellow
            ChannelKind::Master => 0xff4060, // Red
        }
    }

    /// Get prefix for auto-naming
    pub fn prefix(&self) -> &'static str {
        match self {
            ChannelKind::Audio => "Audio",
            ChannelKind::Bus => "Bus",
            ChannelKind::Aux => "Aux",
            ChannelKind::Vca => "VCA",
            ChannelKind::Master => "Master",
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL IDENTIFIER
// ═══════════════════════════════════════════════════════════════════════════

/// Type-safe channel identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ChannelId(pub u32);

impl ChannelId {
    /// Master channel ID (always 0)
    pub const MASTER: ChannelId = ChannelId(0);

    /// Invalid/none channel ID
    pub const NONE: ChannelId = ChannelId(u32::MAX);

    /// Check if this is the master channel
    pub fn is_master(&self) -> bool {
        *self == Self::MASTER
    }
}

impl Default for ChannelId {
    fn default() -> Self {
        Self::NONE
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// OUTPUT DESTINATION
// ═══════════════════════════════════════════════════════════════════════════

/// Output routing destination
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum OutputDestination {
    /// Route to master (default)
    #[default]
    Master,
    /// Route to another channel (bus/aux)
    Channel(ChannelId),
    /// Route to hardware output directly
    HardwareOutput(u32),
    /// No output (sidechain-only source or muted)
    None,
}

impl OutputDestination {
    /// Get target channel ID if routing to a channel
    pub fn target_channel(&self) -> Option<ChannelId> {
        match self {
            OutputDestination::Master => Some(ChannelId::MASTER),
            OutputDestination::Channel(id) => Some(*id),
            _ => None,
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SEND CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════

/// Send tap point (where signal is taken from)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum SendTapPoint {
    /// Before fader and pan
    PreFader,
    /// After fader, before pan (default)
    #[default]
    PostFader,
    /// After fader and pan
    PostPan,
}

/// Send configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SendConfig {
    /// Destination channel (usually Aux)
    pub destination: ChannelId,
    /// Send level in dB
    pub level_db: f64,
    /// Send pan (-1.0 to 1.0)
    pub pan: f64,
    /// Tap point
    pub tap_point: SendTapPoint,
    /// Is send enabled
    pub enabled: bool,
}

impl SendConfig {
    /// Create new send
    pub fn new(destination: ChannelId) -> Self {
        Self {
            destination,
            level_db: -6.0, // Default -6dB
            pan: 0.0,
            tap_point: SendTapPoint::PostFader,
            enabled: true,
        }
    }

    /// Create pre-fader send
    pub fn pre_fader(destination: ChannelId) -> Self {
        Self {
            tap_point: SendTapPoint::PreFader,
            ..Self::new(destination)
        }
    }

    /// Get linear gain
    pub fn gain(&self) -> f64 {
        if self.level_db <= -60.0 {
            0.0
        } else {
            10.0_f64.powf(self.level_db / 20.0)
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL
// ═══════════════════════════════════════════════════════════════════════════

/// Complete channel with routing
#[derive(Debug)]
pub struct Channel {
    /// Unique identifier
    pub id: ChannelId,
    /// Channel type
    pub kind: ChannelKind,
    /// Display name
    pub name: String,
    /// Color (RGB)
    pub color: u32,

    // Routing
    /// Output destination
    pub output: OutputDestination,
    /// Send configurations
    pub sends: Vec<SendConfig>,

    // Mixer state (using atomics for lock-free access from audio thread)
    /// Fader level in dB
    fader_db: f64,
    /// Pan (-1.0 to 1.0)
    pan: f64,
    /// Mute state
    muted: AtomicBool,
    /// Solo state
    soloed: AtomicBool,
    /// Record arm state
    armed: AtomicBool,
    /// Monitor state
    monitoring: AtomicBool,

    // Internal buffers
    input_left: Vec<Sample>,
    input_right: Vec<Sample>,
    output_left: Vec<Sample>,
    output_right: Vec<Sample>,

    // State
    /// Processing order index (computed by topological sort)
    processing_order: u32,
}

impl Channel {
    /// Create new channel
    pub fn new(id: ChannelId, kind: ChannelKind, name: &str, block_size: usize) -> Self {
        Self {
            id,
            kind,
            name: name.to_string(),
            color: kind.default_color(),
            output: if id.is_master() { OutputDestination::HardwareOutput(0) } else { OutputDestination::Master },
            sends: Vec::new(),
            fader_db: 0.0,
            pan: 0.0,
            muted: AtomicBool::new(false),
            soloed: AtomicBool::new(false),
            armed: AtomicBool::new(false),
            monitoring: AtomicBool::new(false),
            input_left: vec![0.0; block_size],
            input_right: vec![0.0; block_size],
            output_left: vec![0.0; block_size],
            output_right: vec![0.0; block_size],
            processing_order: 0,
        }
    }

    /// Set fader level in dB
    pub fn set_fader(&mut self, db: f64) {
        self.fader_db = db.clamp(-144.0, 12.0);
    }

    /// Get fader level in dB
    pub fn fader_db(&self) -> f64 {
        self.fader_db
    }

    /// Get fader gain (linear)
    pub fn fader_gain(&self) -> f64 {
        if self.fader_db <= -60.0 {
            0.0
        } else {
            10.0_f64.powf(self.fader_db / 20.0)
        }
    }

    /// Set pan
    pub fn set_pan(&mut self, pan: f64) {
        self.pan = pan.clamp(-1.0, 1.0);
    }

    /// Get pan
    pub fn pan(&self) -> f64 {
        self.pan
    }

    /// Set mute (lock-free)
    pub fn set_mute(&self, muted: bool) {
        self.muted.store(muted, Ordering::Release);
    }

    /// Is muted (lock-free)
    pub fn is_muted(&self) -> bool {
        self.muted.load(Ordering::Acquire)
    }

    /// Set solo (lock-free)
    pub fn set_solo(&self, soloed: bool) {
        self.soloed.store(soloed, Ordering::Release);
    }

    /// Is soloed (lock-free)
    pub fn is_soloed(&self) -> bool {
        self.soloed.load(Ordering::Acquire)
    }

    /// Add send
    pub fn add_send(&mut self, destination: ChannelId, pre_fader: bool) {
        let mut send = SendConfig::new(destination);
        if pre_fader {
            send.tap_point = SendTapPoint::PreFader;
        }
        self.sends.push(send);
    }

    /// Remove send
    pub fn remove_send(&mut self, index: usize) {
        if index < self.sends.len() {
            self.sends.remove(index);
        }
    }

    /// Clear input buffers
    pub fn clear_input(&mut self) {
        self.input_left.fill(0.0);
        self.input_right.fill(0.0);
    }

    /// Add to input buffer (for summing from children)
    pub fn add_to_input(&mut self, left: &[Sample], right: &[Sample]) {
        for (i, (&l, &r)) in left.iter().zip(right.iter()).enumerate() {
            if i < self.input_left.len() {
                self.input_left[i] += l;
                self.input_right[i] += r;
            }
        }
    }

    /// Process channel (apply fader, pan, mute)
    pub fn process(&mut self, global_solo_active: bool) {
        // Check mute/solo
        if self.is_muted() || (global_solo_active && !self.is_soloed()) {
            self.output_left.fill(0.0);
            self.output_right.fill(0.0);
            return;
        }

        let gain = self.fader_gain();

        // Constant power pan
        let pan_angle = (self.pan + 1.0) * 0.25 * std::f64::consts::PI;
        let left_gain = gain * pan_angle.cos();
        let right_gain = gain * pan_angle.sin();

        for i in 0..self.input_left.len().min(self.output_left.len()) {
            self.output_left[i] = self.input_left[i] * left_gain;
            self.output_right[i] = self.input_right[i] * right_gain;
        }
    }

    /// Get output buffers
    pub fn output(&self) -> (&[Sample], &[Sample]) {
        (&self.output_left, &self.output_right)
    }

    /// Resize buffers
    pub fn resize(&mut self, block_size: usize) {
        self.input_left.resize(block_size, 0.0);
        self.input_right.resize(block_size, 0.0);
        self.output_left.resize(block_size, 0.0);
        self.output_right.resize(block_size, 0.0);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ROUTING GRAPH
// ═══════════════════════════════════════════════════════════════════════════

/// Routing error types
#[derive(Debug, Clone)]
pub enum RoutingError {
    /// Connection would create feedback loop
    WouldCreateCycle { from: ChannelId, to: ChannelId },
    /// Channel not found
    ChannelNotFound(ChannelId),
    /// Cannot route to self
    SelfReference(ChannelId),
    /// Invalid connection (e.g., routing audio track to VCA)
    InvalidConnection { from: ChannelId, to: ChannelId, reason: &'static str },
}

/// Dynamic routing graph with feedback prevention
pub struct RoutingGraph {
    /// All channels indexed by ID
    channels: HashMap<ChannelId, Channel>,
    /// Processing order (topologically sorted)
    processing_order: Vec<ChannelId>,
    /// Next channel ID
    next_id: AtomicU32,
    /// Global solo state
    global_solo_active: AtomicBool,
    /// Graph is dirty (needs re-sorting)
    dirty: AtomicBool,
    /// Block size
    block_size: usize,
}

impl RoutingGraph {
    /// Create new routing graph with master channel
    pub fn new(block_size: usize) -> Self {
        let mut channels = HashMap::new();

        // Create master channel (always ID 0)
        let master = Channel::new(ChannelId::MASTER, ChannelKind::Master, "Master", block_size);
        channels.insert(ChannelId::MASTER, master);

        Self {
            channels,
            processing_order: vec![ChannelId::MASTER],
            next_id: AtomicU32::new(1), // Master is 0, start at 1
            global_solo_active: AtomicBool::new(false),
            dirty: AtomicBool::new(false),
            block_size,
        }
    }

    /// Create new channel
    pub fn create_channel(&mut self, kind: ChannelKind, name: Option<&str>) -> ChannelId {
        let id = ChannelId(self.next_id.fetch_add(1, Ordering::Relaxed));
        let auto_name = name.map(String::from).unwrap_or_else(|| {
            format!("{} {}", kind.prefix(), id.0)
        });

        let channel = Channel::new(id, kind, &auto_name, self.block_size);
        self.channels.insert(id, channel);
        self.dirty.store(true, Ordering::Release);

        id
    }

    /// Create bus channel
    pub fn create_bus(&mut self, name: &str) -> ChannelId {
        self.create_channel(ChannelKind::Bus, Some(name))
    }

    /// Create aux channel
    pub fn create_aux(&mut self, name: &str) -> ChannelId {
        self.create_channel(ChannelKind::Aux, Some(name))
    }

    /// Delete channel
    pub fn delete_channel(&mut self, id: ChannelId) -> bool {
        if id.is_master() {
            return false; // Cannot delete master
        }

        if self.channels.remove(&id).is_some() {
            // Re-route any channels that were outputting to this one
            for channel in self.channels.values_mut() {
                if channel.output == OutputDestination::Channel(id) {
                    channel.output = OutputDestination::Master;
                }
                // Remove sends to this channel
                channel.sends.retain(|s| s.destination != id);
            }
            self.dirty.store(true, Ordering::Release);
            true
        } else {
            false
        }
    }

    /// Get channel by ID
    pub fn get(&self, id: ChannelId) -> Option<&Channel> {
        self.channels.get(&id)
    }

    /// Get mutable channel by ID
    pub fn get_mut(&mut self, id: ChannelId) -> Option<&mut Channel> {
        self.channels.get_mut(&id)
    }

    /// Get master channel
    pub fn master(&self) -> &Channel {
        self.channels.get(&ChannelId::MASTER).expect("Master channel must exist")
    }

    /// Get mutable master channel
    pub fn master_mut(&mut self) -> &mut Channel {
        self.channels.get_mut(&ChannelId::MASTER).expect("Master channel must exist")
    }

    /// Set channel output destination with validation
    pub fn set_output(&mut self, id: ChannelId, destination: OutputDestination) -> Result<(), RoutingError> {
        // Validate
        if id.is_master() {
            return Err(RoutingError::InvalidConnection {
                from: id,
                to: ChannelId::NONE,
                reason: "Cannot change master output",
            });
        }

        if let OutputDestination::Channel(to_id) = destination {
            if to_id == id {
                return Err(RoutingError::SelfReference(id));
            }

            if !self.channels.contains_key(&to_id) {
                return Err(RoutingError::ChannelNotFound(to_id));
            }

            // Check for cycle
            if self.would_create_cycle(id, to_id) {
                return Err(RoutingError::WouldCreateCycle { from: id, to: to_id });
            }
        }

        // Apply
        if let Some(channel) = self.channels.get_mut(&id) {
            channel.output = destination;
            self.dirty.store(true, Ordering::Release);
        }

        Ok(())
    }

    /// Add send with validation
    pub fn add_send(&mut self, from: ChannelId, to: ChannelId, pre_fader: bool) -> Result<(), RoutingError> {
        if from == to {
            return Err(RoutingError::SelfReference(from));
        }

        if !self.channels.contains_key(&from) {
            return Err(RoutingError::ChannelNotFound(from));
        }

        if !self.channels.contains_key(&to) {
            return Err(RoutingError::ChannelNotFound(to));
        }

        // Check for cycle
        if self.would_create_cycle(from, to) {
            return Err(RoutingError::WouldCreateCycle { from, to });
        }

        // Add send
        if let Some(channel) = self.channels.get_mut(&from) {
            channel.add_send(to, pre_fader);
            self.dirty.store(true, Ordering::Release);
        }

        Ok(())
    }

    /// Check if adding edge would create cycle (DFS)
    fn would_create_cycle(&self, from: ChannelId, to: ChannelId) -> bool {
        // Check if 'from' is reachable from 'to' (would create cycle)
        let mut visited = HashSet::new();
        let mut stack = vec![to];

        while let Some(current) = stack.pop() {
            if current == from {
                return true;
            }

            if visited.insert(current) {
                if let Some(channel) = self.channels.get(&current) {
                    // Check output
                    if let Some(target) = channel.output.target_channel() {
                        stack.push(target);
                    }
                    // Check sends
                    for send in &channel.sends {
                        stack.push(send.destination);
                    }
                }
            }
        }

        false
    }

    /// Recompute processing order using Kahn's algorithm (topological sort)
    pub fn update_processing_order(&mut self) {
        if !self.dirty.load(Ordering::Acquire) {
            return;
        }

        // Calculate in-degrees
        let mut in_degree: HashMap<ChannelId, usize> = HashMap::new();
        for &id in self.channels.keys() {
            in_degree.insert(id, 0);
        }

        // Count incoming edges
        for channel in self.channels.values() {
            if let Some(target) = channel.output.target_channel() {
                *in_degree.get_mut(&target).unwrap() += 1;
            }
            for send in &channel.sends {
                *in_degree.get_mut(&send.destination).unwrap() += 1;
            }
        }

        // Start with source nodes (no inputs)
        let mut queue: VecDeque<ChannelId> = VecDeque::new();
        for (&id, &degree) in &in_degree {
            if degree == 0 {
                queue.push_back(id);
            }
        }

        // Process in topological order
        let mut order = Vec::new();
        while let Some(id) = queue.pop_front() {
            order.push(id);

            if let Some(channel) = self.channels.get(&id) {
                // Process output
                if let Some(target) = channel.output.target_channel() {
                    let deg = in_degree.get_mut(&target).unwrap();
                    *deg -= 1;
                    if *deg == 0 {
                        queue.push_back(target);
                    }
                }

                // Process sends
                for send in &channel.sends {
                    let deg = in_degree.get_mut(&send.destination).unwrap();
                    *deg -= 1;
                    if *deg == 0 {
                        queue.push_back(send.destination);
                    }
                }
            }
        }

        // Update processing order indices
        for (idx, &id) in order.iter().enumerate() {
            if let Some(channel) = self.channels.get_mut(&id) {
                channel.processing_order = idx as u32;
            }
        }

        self.processing_order = order;
        self.dirty.store(false, Ordering::Release);
    }

    /// Process all channels in correct order
    pub fn process(&mut self) {
        // Update processing order if needed
        self.update_processing_order();

        // Update global solo state
        let solo_active = self.channels.values().any(|c| c.is_soloed());
        self.global_solo_active.store(solo_active, Ordering::Release);

        // Clear all inputs
        for channel in self.channels.values_mut() {
            channel.clear_input();
        }

        // Clone processing order to avoid borrow issues
        let order = self.processing_order.clone();

        // Process in topological order
        for id in order {
            // First pass: process channel and collect routing info
            let routing_info = {
                let channel = match self.channels.get_mut(&id) {
                    Some(c) => c,
                    None => continue,
                };

                channel.process(solo_active);

                // Collect output and routing info
                let (out_l, out_r) = channel.output();
                let out_l = out_l.to_vec();
                let out_r = out_r.to_vec();

                let target = channel.output.target_channel();
                let sends: Vec<(ChannelId, f64)> = channel.sends.iter()
                    .filter(|s| s.enabled)
                    .map(|s| (s.destination, s.gain()))
                    .collect();

                (out_l, out_r, target, sends)
            };

            // Second pass: route to destinations
            let (out_l, out_r, target, sends) = routing_info;

            if let Some(target_id) = target {
                if let Some(target) = self.channels.get_mut(&target_id) {
                    target.add_to_input(&out_l, &out_r);
                }
            }

            // Process sends
            for (dest_id, gain) in sends {
                let send_l: Vec<Sample> = out_l.iter().map(|&s| s * gain).collect();
                let send_r: Vec<Sample> = out_r.iter().map(|&s| s * gain).collect();

                if let Some(target) = self.channels.get_mut(&dest_id) {
                    target.add_to_input(&send_l, &send_r);
                }
            }
        }
    }

    /// Get final output from master
    pub fn get_output(&self) -> (&[Sample], &[Sample]) {
        self.master().output()
    }

    /// Get all channels of a specific kind
    pub fn channels_of_kind(&self, kind: ChannelKind) -> Vec<&Channel> {
        self.channels.values().filter(|c| c.kind == kind).collect()
    }

    /// Get all channel IDs
    pub fn all_channel_ids(&self) -> Vec<ChannelId> {
        self.channels.keys().copied().collect()
    }

    /// Get channel count (excluding master)
    pub fn channel_count(&self) -> usize {
        self.channels.len() - 1 // Exclude master
    }

    /// Set block size for all channels
    pub fn set_block_size(&mut self, block_size: usize) {
        self.block_size = block_size;
        for channel in self.channels.values_mut() {
            channel.resize(block_size);
        }
    }
}

impl Default for RoutingGraph {
    fn default() -> Self {
        Self::new(256)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_bus() {
        let mut graph = RoutingGraph::new(256);

        let bus_id = graph.create_bus("Drums");
        assert!(graph.get(bus_id).is_some());
        assert_eq!(graph.get(bus_id).unwrap().kind, ChannelKind::Bus);
    }

    #[test]
    fn test_routing() {
        let mut graph = RoutingGraph::new(256);

        let drums_bus = graph.create_bus("Drums");
        let kick_track = graph.create_channel(ChannelKind::Audio, Some("Kick"));

        // Route kick to drums bus
        graph.set_output(kick_track, OutputDestination::Channel(drums_bus)).unwrap();

        assert_eq!(
            graph.get(kick_track).unwrap().output,
            OutputDestination::Channel(drums_bus)
        );
    }

    #[test]
    fn test_cycle_prevention() {
        let mut graph = RoutingGraph::new(256);

        let bus_a = graph.create_bus("Bus A");
        let bus_b = graph.create_bus("Bus B");

        // A -> B (OK)
        graph.set_output(bus_a, OutputDestination::Channel(bus_b)).unwrap();

        // B -> A (would create cycle)
        let result = graph.set_output(bus_b, OutputDestination::Channel(bus_a));
        assert!(matches!(result, Err(RoutingError::WouldCreateCycle { .. })));
    }

    #[test]
    fn test_self_reference() {
        let mut graph = RoutingGraph::new(256);

        let bus = graph.create_bus("Bus");
        let result = graph.set_output(bus, OutputDestination::Channel(bus));
        assert!(matches!(result, Err(RoutingError::SelfReference(_))));
    }

    #[test]
    fn test_send() {
        let mut graph = RoutingGraph::new(256);

        let reverb_aux = graph.create_aux("Reverb");
        let track = graph.create_channel(ChannelKind::Audio, Some("Vocal"));

        // Add send from track to reverb
        graph.add_send(track, reverb_aux, false).unwrap();

        assert_eq!(graph.get(track).unwrap().sends.len(), 1);
        assert_eq!(graph.get(track).unwrap().sends[0].destination, reverb_aux);
    }

    #[test]
    fn test_processing_order() {
        let mut graph = RoutingGraph::new(256);

        let drums_bus = graph.create_bus("Drums");
        let music_bus = graph.create_bus("Music");
        let kick = graph.create_channel(ChannelKind::Audio, Some("Kick"));
        let snare = graph.create_channel(ChannelKind::Audio, Some("Snare"));

        // Route kick, snare -> drums bus -> master
        graph.set_output(kick, OutputDestination::Channel(drums_bus)).unwrap();
        graph.set_output(snare, OutputDestination::Channel(drums_bus)).unwrap();

        graph.update_processing_order();

        // Kick and snare should process before drums bus
        let kick_order = graph.get(kick).unwrap().processing_order;
        let drums_order = graph.get(drums_bus).unwrap().processing_order;
        let master_order = graph.get(ChannelId::MASTER).unwrap().processing_order;

        assert!(kick_order < drums_order);
        assert!(drums_order < master_order);
    }
}
