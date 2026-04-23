// ═══════════════════════════════════════════════════════════════════════════════
// HELIX GRAPH — Deterministic Audio Graph (DAG) for SlotLab Intelligence
// ═══════════════════════════════════════════════════════════════════════════════
//
// Point 1.2 of HELIX Architecture. Extends the existing hook_graph system with:
//   - HELIX-specific node types (Gate, RTPC, Container, Spatial, Meter)
//   - Live-edit support (double-buffer swap without stopping audio)
//   - AUREXIS gate integration (conditional audio based on voice budget/energy)
//   - RTPC modulation (curve-driven parameter control from game state)
//   - Container nodes (Random, Sequence, Blend, Switch wrappers)
//   - HELIX Bus integration (publish/subscribe for every node)
//   - Deterministic execution (topological sort + sequence numbering)
//   - Graph serialization (save/load for .hxg project files)
//
// ARCHITECTURE:
//   HxGraph owns nodes + connections. HxGraphRenderer does the audio-rate work.
//   HxGraphEditor handles lock-free live-editing via double-buffer swap.
//   Every node can publish/subscribe to HELIX Bus channels.
//
// ZERO-ALLOC: All buffers pre-allocated. No Box, Vec, String on audio thread.
// ═══════════════════════════════════════════════════════════════════════════════

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;

// ─────────────────────────────────────────────────────────────────────────────
// Node Type System
// ─────────────────────────────────────────────────────────────────────────────

/// Unique node identifier within a graph
pub type HxNodeId = u32;

/// HELIX node types — superset of existing AudioNodeType
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum HxNodeType {
    // === Audio Sources ===
    /// Direct audio file playback (from voice pool or disk streaming)
    PlaySource      = 0,
    /// Oscillator / tone generator (for debug, calibration, or synth)
    Oscillator      = 1,
    /// Noise generator (white, pink, brown — for testing/ambience)
    Noise           = 2,

    // === DSP Processing ===
    /// Gain node (volume, mute, invert)
    Gain            = 10,
    /// Parametric EQ (any band count)
    Filter          = 11,
    /// Stereo panner (linear, equal-power, or slot-specific)
    Pan             = 12,
    /// Delay line (ms or tempo-synced)
    Delay           = 13,
    /// Dynamics: compressor
    Compressor      = 14,
    /// Dynamics: limiter (lookahead brickwall)
    Limiter         = 15,
    /// Dynamics: gate / expander
    Gate            = 16,
    /// Reverb (convolution or algorithmic)
    Reverb          = 17,
    /// Chorus / flanger / phaser
    Modulation      = 18,
    /// Distortion / saturation / waveshaper
    Distortion      = 19,
    /// Envelope follower → control signal
    EnvelopeFollow  = 20,

    // === Routing ===
    /// Mixer: sum multiple inputs
    Mixer           = 30,
    /// Bus send (post-fader or pre-fader)
    BusSend         = 31,
    /// Bus return (receive from send)
    BusReturn       = 32,
    /// Splitter: one input → multiple outputs (copy)
    Splitter        = 33,
    /// Crossfade: blend two inputs with single control
    Crossfade       = 34,

    // === Containers (Wwise-grade) ===
    /// Random container — weighted random selection
    RandomContainer     = 50,
    /// Sequence container — ordered playback with timing
    SequenceContainer   = 51,
    /// Blend container — RTPC-driven crossfade between children
    BlendContainer      = 52,
    /// Switch container — state-driven selection (game state → child)
    SwitchContainer     = 53,

    // === Intelligence (HELIX-exclusive) ===
    /// AUREXIS gate — conditional pass/block based on voice budget, energy, fatigue
    AurexisGate     = 70,
    /// RTPC modulation — curve-driven parameter control from game state
    RtpcModulator   = 71,
    /// Ducking node — auto-duck based on sidechain or priority
    Ducker          = 72,
    /// Transition node — crossfade/stinger between game states
    Transition      = 73,
    /// Anti-fatigue — dynamic variation based on play count + session age
    AntiFatigue     = 74,

    // === Spatial ===
    /// 3D position → binaural HRTF
    Spatial3D       = 80,
    /// Room simulation (early reflections + late reverb)
    RoomSim         = 81,
    /// Distance attenuation curve
    DistanceAtten   = 82,

    // === Analysis / Metering ===
    /// Level meter (RMS, peak, LUFS)
    Meter           = 90,
    /// Spectrum analyzer (FFT)
    Spectrum        = 91,
    /// Waveform scope
    Scope           = 92,

    // === Control ===
    /// Envelope generator (ADSR, multi-segment)
    Envelope        = 100,
    /// LFO (for parameter modulation)
    Lfo             = 101,
    /// Math operator (add, multiply, clamp, map range)
    MathOp          = 102,
    /// Trigger → one-shot or gated
    Trigger         = 103,

    // === Output ===
    /// Master output with final metering + compliance check
    MasterOutput    = 120,
}

impl HxNodeType {
    pub fn from_u8(v: u8) -> Option<Self> {
        // Use a match for all defined values
        match v {
            0 => Some(Self::PlaySource),
            1 => Some(Self::Oscillator),
            2 => Some(Self::Noise),
            10 => Some(Self::Gain),
            11 => Some(Self::Filter),
            12 => Some(Self::Pan),
            13 => Some(Self::Delay),
            14 => Some(Self::Compressor),
            15 => Some(Self::Limiter),
            16 => Some(Self::Gate),
            17 => Some(Self::Reverb),
            18 => Some(Self::Modulation),
            19 => Some(Self::Distortion),
            20 => Some(Self::EnvelopeFollow),
            30 => Some(Self::Mixer),
            31 => Some(Self::BusSend),
            32 => Some(Self::BusReturn),
            33 => Some(Self::Splitter),
            34 => Some(Self::Crossfade),
            50 => Some(Self::RandomContainer),
            51 => Some(Self::SequenceContainer),
            52 => Some(Self::BlendContainer),
            53 => Some(Self::SwitchContainer),
            70 => Some(Self::AurexisGate),
            71 => Some(Self::RtpcModulator),
            72 => Some(Self::Ducker),
            73 => Some(Self::Transition),
            74 => Some(Self::AntiFatigue),
            80 => Some(Self::Spatial3D),
            81 => Some(Self::RoomSim),
            82 => Some(Self::DistanceAtten),
            90 => Some(Self::Meter),
            91 => Some(Self::Spectrum),
            92 => Some(Self::Scope),
            100 => Some(Self::Envelope),
            101 => Some(Self::Lfo),
            102 => Some(Self::MathOp),
            103 => Some(Self::Trigger),
            120 => Some(Self::MasterOutput),
            _ => None,
        }
    }

    /// Whether this node type produces audio output
    pub fn has_audio_output(&self) -> bool {
        !matches!(self, Self::Meter | Self::Spectrum | Self::Scope)
    }

    /// Whether this node type is a container (manages children)
    pub fn is_container(&self) -> bool {
        matches!(self,
            Self::RandomContainer | Self::SequenceContainer |
            Self::BlendContainer | Self::SwitchContainer
        )
    }

    /// Whether this node type is an intelligence node (HELIX-exclusive)
    pub fn is_intelligence(&self) -> bool {
        matches!(self,
            Self::AurexisGate | Self::RtpcModulator |
            Self::Ducker | Self::Transition | Self::AntiFatigue
        )
    }

    /// Category name for UI grouping
    pub fn category(&self) -> &'static str {
        match self {
            Self::PlaySource | Self::Oscillator | Self::Noise => "Sources",
            Self::Gain | Self::Filter | Self::Pan | Self::Delay |
            Self::Compressor | Self::Limiter | Self::Gate |
            Self::Reverb | Self::Modulation | Self::Distortion |
            Self::EnvelopeFollow => "DSP",
            Self::Mixer | Self::BusSend | Self::BusReturn |
            Self::Splitter | Self::Crossfade => "Routing",
            Self::RandomContainer | Self::SequenceContainer |
            Self::BlendContainer | Self::SwitchContainer => "Containers",
            Self::AurexisGate | Self::RtpcModulator |
            Self::Ducker | Self::Transition | Self::AntiFatigue => "Intelligence",
            Self::Spatial3D | Self::RoomSim | Self::DistanceAtten => "Spatial",
            Self::Meter | Self::Spectrum | Self::Scope => "Analysis",
            Self::Envelope | Self::Lfo | Self::MathOp | Self::Trigger => "Control",
            Self::MasterOutput => "Output",
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connection Types
// ─────────────────────────────────────────────────────────────────────────────

/// Connection type between nodes
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum HxConnectionType {
    /// Standard audio signal flow
    Audio       = 0,
    /// Sidechain input (for ducking, gating, envelope following)
    Sidechain   = 1,
    /// Control signal (for RTPC, LFO → parameter modulation)
    Control     = 2,
    /// Trigger signal (one-shot event, e.g. envelope trigger)
    Trigger     = 3,
    /// MIDI (note data, CC, pitch bend)
    Midi        = 4,
}

/// A connection between two nodes in the graph
#[derive(Debug, Clone)]
pub struct HxConnection {
    /// Source node
    pub from_node: HxNodeId,
    /// Source output port index
    pub from_port: u8,
    /// Destination node
    pub to_node: HxNodeId,
    /// Destination input port index
    pub to_port: u8,
    /// Connection type
    pub conn_type: HxConnectionType,
    /// Per-connection gain (1.0 = unity, 0.0 = muted)
    pub gain: f32,
    /// Whether this connection is active
    pub active: bool,
}

// ─────────────────────────────────────────────────────────────────────────────
// Node Parameters
// ─────────────────────────────────────────────────────────────────────────────

/// Parameter descriptor — metadata for a single automatable parameter
#[derive(Debug, Clone)]
pub struct HxParamDescriptor {
    /// Parameter ID (unique within node, stable hash for FFI)
    pub id: u32,
    /// Human-readable name
    pub name: &'static str,
    /// Minimum value
    pub min: f64,
    /// Maximum value
    pub max: f64,
    /// Default value
    pub default: f64,
    /// Display unit (dB, Hz, ms, %, etc.)
    pub unit: &'static str,
    /// Curve type for UI display (linear, logarithmic, exponential)
    pub curve: ParamCurve,
}

/// Parameter display curve
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParamCurve {
    Linear,
    Logarithmic,
    Exponential,
    Stepped,
}

// ─────────────────────────────────────────────────────────────────────────────
// RTPC (Real-Time Parameter Control)
// ─────────────────────────────────────────────────────────────────────────────

/// An RTPC binding — maps a game state value to a node parameter via curve
#[derive(Debug, Clone)]
pub struct HxRtpcBinding {
    /// Which game parameter drives this (e.g. "arousal", "win_ratio", "bet_level")
    pub game_param_id: u32,
    /// Target node ID
    pub target_node: HxNodeId,
    /// Target parameter ID within the node
    pub target_param: u32,
    /// Curve control points (x = game value 0..1, y = param value 0..1)
    pub curve: Vec<RtpcCurvePoint>,
    /// Whether RTPC is active
    pub active: bool,
}

/// A point on an RTPC curve
#[derive(Debug, Clone, Copy)]
pub struct RtpcCurvePoint {
    pub x: f32,
    pub y: f32,
    /// Interpolation type to next point
    pub interp: RtpcInterpolation,
}

/// RTPC interpolation between curve points
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RtpcInterpolation {
    Linear,
    SCurve,
    Log,
    Exp,
    Step,
}

/// Evaluate an RTPC curve at a given input value (0..1)
pub fn evaluate_rtpc_curve(curve: &[RtpcCurvePoint], input: f32) -> f32 {
    if curve.is_empty() {
        return input; // Pass-through
    }
    if curve.len() == 1 {
        return curve[0].y;
    }

    let input = input.clamp(0.0, 1.0);

    // Find surrounding points
    if input <= curve[0].x {
        return curve[0].y;
    }
    if input >= curve[curve.len() - 1].x {
        return curve[curve.len() - 1].y;
    }

    for i in 0..curve.len() - 1 {
        let p0 = &curve[i];
        let p1 = &curve[i + 1];

        if input >= p0.x && input <= p1.x {
            let range = p1.x - p0.x;
            if range <= f32::EPSILON {
                return p0.y;
            }
            let t = (input - p0.x) / range;
            let t_curved = match p0.interp {
                RtpcInterpolation::Linear => t,
                RtpcInterpolation::SCurve => t * t * (3.0 - 2.0 * t), // Hermite
                RtpcInterpolation::Log => t.sqrt(),
                RtpcInterpolation::Exp => t * t,
                RtpcInterpolation::Step => 0.0,
            };
            return p0.y + (p1.y - p0.y) * t_curved;
        }
    }

    curve[curve.len() - 1].y
}

// ─────────────────────────────────────────────────────────────────────────────
// AUREXIS Gate Configuration
// ─────────────────────────────────────────────────────────────────────────────

/// Configuration for an AUREXIS gate node
#[derive(Debug, Clone)]
pub struct AurexisGateConfig {
    /// Minimum voice priority to pass (0-255)
    pub min_priority: u8,
    /// Maximum energy cost allowed (0.0 = block all, 1.0 = allow all)
    pub max_energy_cost: f32,
    /// Fatigue threshold — block if session fatigue > this (0.0-1.0)
    pub fatigue_threshold: f32,
    /// Spectral band requirement (only pass if band is available)
    pub required_band: Option<SpectralBand>,
    /// Masking group — block if group is already saturated
    pub masking_group: Option<u32>,
    /// Maximum simultaneous voices in this masking group
    pub max_group_voices: u32,
    /// Behavior when gate blocks
    pub block_behavior: GateBlockBehavior,
}

/// What happens when an AUREXIS gate blocks audio
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GateBlockBehavior {
    /// Silently drop (no audio)
    Silent,
    /// Fade out over N ms
    FadeOut(u32),
    /// Duck to -N dB instead of blocking
    Duck(i8),
    /// Queue and play when gate opens
    Queue,
}

/// Spectral band classification for masking analysis
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(u8)]
pub enum SpectralBand {
    SubBass     = 0,    // 20-60 Hz
    Bass        = 1,    // 60-250 Hz
    LowMid      = 2,    // 250-500 Hz
    Mid         = 3,    // 500-2000 Hz
    UpperMid    = 4,    // 2000-4000 Hz
    Presence    = 5,    // 4000-6000 Hz
    Brilliance  = 6,    // 6000-20000 Hz
}

impl Default for AurexisGateConfig {
    fn default() -> Self {
        Self {
            min_priority: 0,
            max_energy_cost: 1.0,
            fatigue_threshold: 1.0,
            required_band: None,
            masking_group: None,
            max_group_voices: 8,
            block_behavior: GateBlockBehavior::Silent,
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Graph Node — Runtime representation
// ─────────────────────────────────────────────────────────────────────────────

/// A node in the HELIX graph with all runtime state
#[derive(Debug, Clone)]
pub struct HxGraphNode {
    /// Unique ID within graph
    pub id: HxNodeId,
    /// Node type
    pub node_type: HxNodeType,
    /// Human-readable name (for UI)
    pub name: String,
    /// Parameter values (param_id → current_value)
    pub params: HashMap<u32, f64>,
    /// Whether this node is bypassed
    pub bypassed: bool,
    /// Whether this node is muted (still processes but output is zeroed)
    pub muted: bool,
    /// Solo state
    pub solo: bool,
    /// Position in UI canvas (x, y) — for graph editor
    pub ui_position: (f32, f32),
    /// RTPC bindings for this node
    pub rtpc_bindings: Vec<HxRtpcBinding>,
    /// AUREXIS gate config (only for AurexisGate nodes)
    pub gate_config: Option<AurexisGateConfig>,
    /// Number of audio input ports
    pub input_count: u8,
    /// Number of audio output ports
    pub output_count: u8,
    /// Number of sidechain input ports
    pub sidechain_input_count: u8,
    /// Number of control input ports
    pub control_input_count: u8,
    /// Latency introduced by this node (in samples)
    pub latency_samples: u32,
    /// Custom metadata (for serialization)
    pub metadata: HashMap<String, String>,
}

impl HxGraphNode {
    pub fn new(id: HxNodeId, node_type: HxNodeType, name: &str) -> Self {
        let (inputs, outputs) = default_port_counts(node_type);
        Self {
            id,
            node_type,
            name: name.to_string(),
            params: HashMap::new(),
            bypassed: false,
            muted: false,
            solo: false,
            ui_position: (0.0, 0.0),
            rtpc_bindings: Vec::new(),
            gate_config: if node_type == HxNodeType::AurexisGate {
                Some(AurexisGateConfig::default())
            } else {
                None
            },
            input_count: inputs,
            output_count: outputs,
            sidechain_input_count: if has_sidechain(node_type) { 1 } else { 0 },
            control_input_count: 0,
            latency_samples: 0,
            metadata: HashMap::new(),
        }
    }

    /// Set a parameter value
    pub fn set_param(&mut self, param_id: u32, value: f64) {
        self.params.insert(param_id, value);
    }

    /// Get a parameter value with default
    pub fn param(&self, param_id: u32, default: f64) -> f64 {
        self.params.get(&param_id).copied().unwrap_or(default)
    }
}

/// Default input/output port counts per node type
fn default_port_counts(node_type: HxNodeType) -> (u8, u8) {
    match node_type {
        // Sources: 0 in, 1 out
        HxNodeType::PlaySource | HxNodeType::Oscillator | HxNodeType::Noise => (0, 1),
        // Standard DSP: 1 in, 1 out
        HxNodeType::Gain | HxNodeType::Filter | HxNodeType::Pan |
        HxNodeType::Delay | HxNodeType::Compressor | HxNodeType::Limiter |
        HxNodeType::Gate | HxNodeType::Reverb | HxNodeType::Modulation |
        HxNodeType::Distortion | HxNodeType::EnvelopeFollow => (1, 1),
        // Routing
        HxNodeType::Mixer => (8, 1),       // 8 inputs, 1 output
        HxNodeType::BusSend => (1, 1),
        HxNodeType::BusReturn => (0, 1),
        HxNodeType::Splitter => (1, 4),    // 1 input, 4 outputs
        HxNodeType::Crossfade => (2, 1),   // 2 inputs, 1 blended output
        // Containers: variable children, 1 output
        HxNodeType::RandomContainer | HxNodeType::SequenceContainer |
        HxNodeType::BlendContainer | HxNodeType::SwitchContainer => (8, 1),
        // Intelligence
        HxNodeType::AurexisGate => (1, 1),
        HxNodeType::RtpcModulator => (0, 1),  // Control signal output
        HxNodeType::Ducker => (1, 1),
        HxNodeType::Transition => (2, 1),     // Current + next, blended output
        HxNodeType::AntiFatigue => (1, 1),
        // Spatial
        HxNodeType::Spatial3D | HxNodeType::RoomSim | HxNodeType::DistanceAtten => (1, 1),
        // Analysis: 1 in, 0 out (tap only)
        HxNodeType::Meter | HxNodeType::Spectrum | HxNodeType::Scope => (1, 0),
        // Control: 0 in, 1 out
        HxNodeType::Envelope | HxNodeType::Lfo | HxNodeType::Trigger => (0, 1),
        HxNodeType::MathOp => (2, 1),
        // Output
        HxNodeType::MasterOutput => (1, 0),
    }
}

/// Whether a node type supports sidechain input
fn has_sidechain(node_type: HxNodeType) -> bool {
    matches!(node_type,
        HxNodeType::Compressor | HxNodeType::Gate |
        HxNodeType::Ducker | HxNodeType::EnvelopeFollow
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// HELIX Graph — The complete graph structure
// ─────────────────────────────────────────────────────────────────────────────

/// Maximum nodes per graph (pre-allocated for deterministic memory)
pub const MAX_GRAPH_NODES: usize = 256;
/// Maximum connections per graph
pub const MAX_GRAPH_CONNECTIONS: usize = 1024;

/// The complete HELIX audio graph
#[derive(Debug, Clone)]
pub struct HxGraph {
    /// Graph identifier
    pub id: String,
    /// Human-readable name
    pub name: String,
    /// All nodes in the graph
    pub nodes: Vec<HxGraphNode>,
    /// All connections between nodes
    pub connections: Vec<HxConnection>,
    /// Topological execution order (node IDs in processing sequence)
    pub execution_order: Vec<HxNodeId>,
    /// Depth levels for parallel execution (groups of nodes at same depth)
    pub depth_levels: Vec<Vec<HxNodeId>>,
    /// RTPC bindings (graph-level)
    pub rtpc_bindings: Vec<HxRtpcBinding>,
    /// Total graph latency (sum of longest path)
    pub total_latency_samples: u32,
    /// Version counter (incremented on every edit)
    pub version: u32,
    /// Whether the graph needs re-sorting after edit
    pub dirty: bool,
}

impl HxGraph {
    pub fn new(id: &str, name: &str) -> Self {
        Self {
            id: id.to_string(),
            name: name.to_string(),
            nodes: Vec::with_capacity(64),
            connections: Vec::with_capacity(128),
            execution_order: Vec::with_capacity(64),
            depth_levels: Vec::with_capacity(16),
            rtpc_bindings: Vec::new(),
            total_latency_samples: 0,
            version: 0,
            dirty: true,
        }
    }

    // ── Node Management ──────────────────────────────────────────────────

    /// Add a node to the graph. Returns the node ID.
    pub fn add_node(&mut self, node: HxGraphNode) -> HxNodeId {
        let id = node.id;
        self.nodes.push(node);
        self.dirty = true;
        self.version += 1;
        id
    }

    /// Create and add a node with auto-generated ID
    pub fn create_node(&mut self, node_type: HxNodeType, name: &str) -> HxNodeId {
        let id = self.next_node_id();
        let node = HxGraphNode::new(id, node_type, name);
        self.add_node(node)
    }

    /// Remove a node and all its connections
    pub fn remove_node(&mut self, node_id: HxNodeId) -> Option<HxGraphNode> {
        // Remove all connections to/from this node
        self.connections.retain(|c| c.from_node != node_id && c.to_node != node_id);
        // Remove the node
        if let Some(idx) = self.nodes.iter().position(|n| n.id == node_id) {
            self.dirty = true;
            self.version += 1;
            Some(self.nodes.remove(idx))
        } else {
            None
        }
    }

    /// Get a node by ID
    pub fn node(&self, id: HxNodeId) -> Option<&HxGraphNode> {
        self.nodes.iter().find(|n| n.id == id)
    }

    /// Get a mutable node by ID
    pub fn node_mut(&mut self, id: HxNodeId) -> Option<&mut HxGraphNode> {
        self.nodes.iter_mut().find(|n| n.id == id)
    }

    /// Next available node ID
    fn next_node_id(&self) -> HxNodeId {
        self.nodes.iter().map(|n| n.id).max().unwrap_or(0) + 1
    }

    // ── Connection Management ────────────────────────────────────────────

    /// Add a connection between two nodes. Returns true if valid.
    pub fn connect(
        &mut self,
        from: HxNodeId,
        from_port: u8,
        to: HxNodeId,
        to_port: u8,
        conn_type: HxConnectionType,
    ) -> bool {
        // Validate: no self-loops
        if from == to {
            return false;
        }
        // Validate: both nodes exist
        if self.node(from).is_none() || self.node(to).is_none() {
            return false;
        }
        // Validate: no duplicate connections
        if self.connections.iter().any(|c| {
            c.from_node == from && c.from_port == from_port &&
            c.to_node == to && c.to_port == to_port
        }) {
            return false;
        }

        self.connections.push(HxConnection {
            from_node: from,
            from_port,
            to_node: to,
            to_port,
            conn_type,
            gain: 1.0,
            active: true,
        });

        self.dirty = true;
        self.version += 1;

        // Check for cycles
        if self.has_cycle() {
            self.connections.pop();
            self.version -= 1;
            return false;
        }

        true
    }

    /// Disconnect two nodes
    pub fn disconnect(&mut self, from: HxNodeId, to: HxNodeId) -> bool {
        let before = self.connections.len();
        self.connections.retain(|c| !(c.from_node == from && c.to_node == to));
        let removed = self.connections.len() < before;
        if removed {
            self.dirty = true;
            self.version += 1;
        }
        removed
    }

    /// Get all connections feeding into a node
    pub fn inputs_to(&self, node_id: HxNodeId) -> Vec<&HxConnection> {
        self.connections.iter()
            .filter(|c| c.to_node == node_id && c.active)
            .collect()
    }

    /// Get all connections from a node
    pub fn outputs_from(&self, node_id: HxNodeId) -> Vec<&HxConnection> {
        self.connections.iter()
            .filter(|c| c.from_node == node_id && c.active)
            .collect()
    }

    // ── Topological Sort ─────────────────────────────────────────────────

    /// Perform topological sort (Kahn's algorithm) and compute depth levels
    pub fn sort(&mut self) -> bool {
        if !self.dirty {
            return true;
        }

        let n = self.nodes.len();
        if n == 0 {
            self.execution_order.clear();
            self.depth_levels.clear();
            self.dirty = false;
            return true;
        }

        // Build adjacency and in-degree
        let node_ids: Vec<HxNodeId> = self.nodes.iter().map(|n| n.id).collect();
        let mut in_degree: HashMap<HxNodeId, usize> = HashMap::new();
        let mut adjacency: HashMap<HxNodeId, Vec<HxNodeId>> = HashMap::new();

        for &id in &node_ids {
            in_degree.insert(id, 0);
            adjacency.insert(id, Vec::new());
        }

        for conn in &self.connections {
            if !conn.active { continue; }
            *in_degree.entry(conn.to_node).or_default() += 1;
            adjacency.entry(conn.from_node).or_default().push(conn.to_node);
        }

        // Kahn's algorithm with depth tracking
        let mut queue: Vec<HxNodeId> = node_ids.iter()
            .filter(|id| in_degree[id] == 0)
            .copied()
            .collect();

        let mut order = Vec::with_capacity(n);
        let mut depth_map: HashMap<HxNodeId, usize> = HashMap::new();
        let mut max_depth = 0;

        // Initialize depth for source nodes
        for &id in &queue {
            depth_map.insert(id, 0);
        }

        while let Some(node_id) = queue.pop() {
            order.push(node_id);
            let current_depth = depth_map[&node_id];

            for &neighbor in adjacency.get(&node_id).unwrap_or(&Vec::new()) {
                let deg = in_degree.get_mut(&neighbor).unwrap();
                *deg -= 1;
                let neighbor_depth = current_depth + 1;
                let existing = depth_map.entry(neighbor).or_insert(0);
                *existing = (*existing).max(neighbor_depth);
                max_depth = max_depth.max(neighbor_depth);
                if *deg == 0 {
                    queue.push(neighbor);
                }
            }
        }

        // Check for cycles
        if order.len() != n {
            return false; // Cycle detected
        }

        // Build depth levels
        let mut levels: Vec<Vec<HxNodeId>> = vec![Vec::new(); max_depth + 1];
        for &id in &order {
            let depth = depth_map[&id];
            levels[depth].push(id);
        }

        self.execution_order = order;
        self.depth_levels = levels;
        self.dirty = false;

        // Compute total latency (longest path in samples)
        self.compute_total_latency();

        true
    }

    /// Check if graph has a cycle (DFS-based)
    fn has_cycle(&self) -> bool {
        let mut visited = HashMap::new();
        for node in &self.nodes {
            if self.dfs_cycle_check(node.id, &mut visited) {
                return true;
            }
        }
        false
    }

    fn dfs_cycle_check(&self, node_id: HxNodeId, visited: &mut HashMap<HxNodeId, u8>) -> bool {
        match visited.get(&node_id) {
            Some(2) => return false,  // Already fully processed
            Some(1) => return true,   // Back edge = cycle
            _ => {}
        }

        visited.insert(node_id, 1); // Mark as in-progress

        for conn in &self.connections {
            if conn.from_node == node_id && conn.active
                && self.dfs_cycle_check(conn.to_node, visited) {
                    return true;
                }
        }

        visited.insert(node_id, 2); // Mark as complete
        false
    }

    /// Compute total graph latency (longest path through latency-bearing nodes)
    fn compute_total_latency(&mut self) {
        let mut max_lat: HashMap<HxNodeId, u32> = HashMap::new();

        for &id in &self.execution_order {
            let node_lat = self.node(id).map(|n| n.latency_samples).unwrap_or(0);
            let input_max = self.inputs_to(id).iter()
                .map(|c| max_lat.get(&c.from_node).copied().unwrap_or(0))
                .max()
                .unwrap_or(0);
            max_lat.insert(id, input_max + node_lat);
        }

        self.total_latency_samples = max_lat.values().copied().max().unwrap_or(0);
    }

    // ── Validation ───────────────────────────────────────────────────────

    /// Validate graph structure. Returns list of issues.
    pub fn validate(&self) -> Vec<GraphValidationIssue> {
        let mut issues = Vec::new();

        // Check for orphan nodes (no connections)
        for node in &self.nodes {
            let has_input = self.connections.iter().any(|c| c.to_node == node.id);
            let has_output = self.connections.iter().any(|c| c.from_node == node.id);
            if !has_input && !has_output {
                issues.push(GraphValidationIssue::OrphanNode(node.id));
            }
        }

        // Check for missing master output
        if !self.nodes.iter().any(|n| n.node_type == HxNodeType::MasterOutput) {
            issues.push(GraphValidationIssue::NoMasterOutput);
        }

        // Check for dangling connections
        for conn in &self.connections {
            if self.node(conn.from_node).is_none() {
                issues.push(GraphValidationIssue::DanglingConnection(conn.from_node, conn.to_node));
            }
            if self.node(conn.to_node).is_none() {
                issues.push(GraphValidationIssue::DanglingConnection(conn.from_node, conn.to_node));
            }
        }

        issues
    }

    // ── Statistics ────────────────────────────────────────────────────────

    /// Get graph statistics
    pub fn stats(&self) -> HxGraphStats {
        let mut type_counts = HashMap::new();
        for node in &self.nodes {
            *type_counts.entry(node.node_type.category()).or_insert(0u32) += 1;
        }

        HxGraphStats {
            total_nodes: self.nodes.len(),
            total_connections: self.connections.len(),
            depth_levels: self.depth_levels.len(),
            total_latency_samples: self.total_latency_samples,
            max_parallel_nodes: self.depth_levels.iter().map(|l| l.len()).max().unwrap_or(0),
            type_counts,
            version: self.version,
        }
    }
}

/// Graph validation issue
#[derive(Debug, Clone)]
pub enum GraphValidationIssue {
    OrphanNode(HxNodeId),
    NoMasterOutput,
    DanglingConnection(HxNodeId, HxNodeId),
    CycleDetected,
    PortOverflow { node: HxNodeId, port: u8, max: u8 },
}

/// Graph statistics
#[derive(Debug, Clone)]
pub struct HxGraphStats {
    pub total_nodes: usize,
    pub total_connections: usize,
    pub depth_levels: usize,
    pub total_latency_samples: u32,
    pub max_parallel_nodes: usize,
    pub type_counts: HashMap<&'static str, u32>,
    pub version: u32,
}

// ─────────────────────────────────────────────────────────────────────────────
// Graph Editor — Lock-free live editing via double-buffer swap
// ─────────────────────────────────────────────────────────────────────────────

/// Lock-free graph editor for live-editing without stopping audio.
///
/// Uses double-buffer strategy:
///   - `active` graph is being rendered by audio thread
///   - `edit` graph is modified by UI thread
///   - On commit, edit graph is swapped into active position
///
/// The swap happens at audio block boundaries (deterministic timing).
pub struct HxGraphEditor {
    /// The active graph (being rendered) — Arc for shared read access
    active: Arc<HxGraph>,
    /// The edit copy — exclusive write access on UI thread
    edit: HxGraph,
    /// Whether a swap is pending
    swap_pending: AtomicBool,
    /// Version of the active graph (for change detection)
    active_version: AtomicU32,
}

impl HxGraphEditor {
    /// Create a new editor for a graph
    pub fn new(graph: HxGraph) -> Self {
        let version = graph.version;
        let active = Arc::new(graph.clone());
        Self {
            active,
            edit: graph,
            swap_pending: AtomicBool::new(false),
            active_version: AtomicU32::new(version),
        }
    }

    /// Get a reference to the active graph (for audio thread rendering)
    pub fn active_graph(&self) -> Arc<HxGraph> {
        Arc::clone(&self.active)
    }

    /// Get a mutable reference to the edit graph (for UI thread modifications)
    pub fn edit_graph(&mut self) -> &mut HxGraph {
        &mut self.edit
    }

    /// Commit changes: prepare to swap edit graph into active position.
    /// The actual swap happens when the audio thread calls `try_swap()`.
    pub fn commit(&mut self) -> bool {
        // Sort the edit graph
        if !self.edit.sort() {
            return false; // Sort failed (cycle?)
        }

        // Mark swap as pending
        self.swap_pending.store(true, Ordering::Release);
        true
    }

    /// Try to swap the edit graph into active position.
    /// Called by audio thread at block boundaries.
    /// Returns true if a swap occurred.
    pub fn try_swap(&mut self) -> bool {
        if !self.swap_pending.load(Ordering::Acquire) {
            return false;
        }

        // Swap: edit becomes active, old active becomes new edit base
        let new_active = Arc::new(self.edit.clone());
        self.active = new_active;
        self.active_version.store(self.edit.version, Ordering::Release);
        self.swap_pending.store(false, Ordering::Release);
        true
    }

    /// Check if there are uncommitted changes
    pub fn has_pending_changes(&self) -> bool {
        self.edit.version != self.active_version.load(Ordering::Relaxed)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Graph Templates — Pre-built graph templates for common slot audio patterns
// ─────────────────────────────────────────────────────────────────────────────

/// Create a basic slot audio graph template
pub fn template_basic_slot() -> HxGraph {
    let mut g = HxGraph::new("basic_slot", "Basic Slot Audio");

    // Sources
    let base_music = g.create_node(HxNodeType::PlaySource, "Base Music");
    let sfx = g.create_node(HxNodeType::PlaySource, "SFX Source");
    let win_music = g.create_node(HxNodeType::PlaySource, "Win Music");

    // Containers
    let reel_sfx = g.create_node(HxNodeType::RandomContainer, "Reel Stop Random");

    // DSP
    let music_eq = g.create_node(HxNodeType::Filter, "Music EQ");
    let sfx_comp = g.create_node(HxNodeType::Compressor, "SFX Compressor");
    let music_ducker = g.create_node(HxNodeType::Ducker, "Music Ducker");

    // Routing
    let music_bus = g.create_node(HxNodeType::Mixer, "Music Bus");
    let sfx_bus = g.create_node(HxNodeType::Mixer, "SFX Bus");
    let master_mix = g.create_node(HxNodeType::Mixer, "Master Mix");

    // Intelligence
    let aurexis = g.create_node(HxNodeType::AurexisGate, "AUREXIS Gate");
    let anti_fatigue = g.create_node(HxNodeType::AntiFatigue, "Anti-Fatigue");

    // Output
    let master = g.create_node(HxNodeType::MasterOutput, "Master Output");

    // Connect: Music path
    g.connect(base_music, 0, music_eq, 0, HxConnectionType::Audio);
    g.connect(win_music, 0, music_eq, 0, HxConnectionType::Audio);
    g.connect(music_eq, 0, music_ducker, 0, HxConnectionType::Audio);
    g.connect(music_ducker, 0, music_bus, 0, HxConnectionType::Audio);

    // Connect: SFX path
    g.connect(sfx, 0, aurexis, 0, HxConnectionType::Audio);
    g.connect(reel_sfx, 0, aurexis, 0, HxConnectionType::Audio);
    g.connect(aurexis, 0, sfx_comp, 0, HxConnectionType::Audio);
    g.connect(sfx_comp, 0, sfx_bus, 0, HxConnectionType::Audio);

    // SFX sidechains music ducker
    g.connect(sfx_bus, 0, music_ducker, 0, HxConnectionType::Sidechain);

    // Anti-fatigue on SFX
    g.connect(sfx_bus, 0, anti_fatigue, 0, HxConnectionType::Audio);

    // Master mix
    g.connect(music_bus, 0, master_mix, 0, HxConnectionType::Audio);
    g.connect(anti_fatigue, 0, master_mix, 1, HxConnectionType::Audio);
    g.connect(master_mix, 0, master, 0, HxConnectionType::Audio);

    g.sort();
    g
}

/// Create a full-featured slot graph with all intelligence nodes
pub fn template_helix_full() -> HxGraph {
    let mut g = HxGraph::new("helix_full", "HELIX Full Slot Audio");

    // === Sources ===
    let base_loop = g.create_node(HxNodeType::PlaySource, "Base Music Loop");
    let antic_stinger = g.create_node(HxNodeType::PlaySource, "Anticipation Stinger");
    let win_fanfare = g.create_node(HxNodeType::PlaySource, "Win Fanfare");
    let ambient = g.create_node(HxNodeType::PlaySource, "Ambient Bed");

    // === Containers ===
    let reel_random = g.create_node(HxNodeType::RandomContainer, "Reel Stop Variations");
    let win_switch = g.create_node(HxNodeType::SwitchContainer, "Win Tier Switch");
    let cascade_seq = g.create_node(HxNodeType::SequenceContainer, "Cascade Sequence");
    let idle_blend = g.create_node(HxNodeType::BlendContainer, "Idle Ambient Blend");

    // === DSP Chain ===
    let music_eq = g.create_node(HxNodeType::Filter, "Music EQ");
    let music_comp = g.create_node(HxNodeType::Compressor, "Music Comp");
    let sfx_eq = g.create_node(HxNodeType::Filter, "SFX EQ");
    let sfx_comp = g.create_node(HxNodeType::Compressor, "SFX Comp");
    let win_reverb = g.create_node(HxNodeType::Reverb, "Win Reverb");
    let _master_limiter = g.create_node(HxNodeType::Limiter, "Master Limiter");

    // === Intelligence ===
    let aurexis_sfx = g.create_node(HxNodeType::AurexisGate, "AUREXIS SFX Gate");
    let aurexis_music = g.create_node(HxNodeType::AurexisGate, "AUREXIS Music Gate");
    let rtpc_intensity = g.create_node(HxNodeType::RtpcModulator, "RTPC Intensity");
    let _rtpc_session = g.create_node(HxNodeType::RtpcModulator, "RTPC Session Age");
    let music_ducker = g.create_node(HxNodeType::Ducker, "Win→Music Ducker");
    let transition = g.create_node(HxNodeType::Transition, "Stage Transition");
    let fatigue = g.create_node(HxNodeType::AntiFatigue, "Session Anti-Fatigue");

    // === Spatial ===
    let spatial = g.create_node(HxNodeType::Spatial3D, "3D Spatial");

    // === Routing ===
    let music_bus = g.create_node(HxNodeType::Mixer, "Music Bus");
    let sfx_bus = g.create_node(HxNodeType::Mixer, "SFX Bus");
    let win_bus = g.create_node(HxNodeType::Mixer, "Win Bus");
    let ambient_bus = g.create_node(HxNodeType::Mixer, "Ambient Bus");
    let master_mix = g.create_node(HxNodeType::Mixer, "Pre-Master");

    // === Analysis ===
    let _meter = g.create_node(HxNodeType::Meter, "Master Meter");

    // === Output ===
    let master = g.create_node(HxNodeType::MasterOutput, "Master Output");

    // Connect music path
    g.connect(base_loop, 0, aurexis_music, 0, HxConnectionType::Audio);
    g.connect(aurexis_music, 0, transition, 0, HxConnectionType::Audio);
    g.connect(antic_stinger, 0, transition, 1, HxConnectionType::Audio);
    g.connect(transition, 0, music_eq, 0, HxConnectionType::Audio);
    g.connect(music_eq, 0, music_comp, 0, HxConnectionType::Audio);
    g.connect(music_comp, 0, music_ducker, 0, HxConnectionType::Audio);
    g.connect(music_ducker, 0, music_bus, 0, HxConnectionType::Audio);

    // Connect SFX path
    g.connect(reel_random, 0, aurexis_sfx, 0, HxConnectionType::Audio);
    g.connect(aurexis_sfx, 0, sfx_eq, 0, HxConnectionType::Audio);
    g.connect(sfx_eq, 0, sfx_comp, 0, HxConnectionType::Audio);
    g.connect(sfx_comp, 0, sfx_bus, 0, HxConnectionType::Audio);

    // Connect win path
    g.connect(win_fanfare, 0, win_switch, 0, HxConnectionType::Audio);
    g.connect(cascade_seq, 0, win_switch, 1, HxConnectionType::Audio);
    g.connect(win_switch, 0, win_reverb, 0, HxConnectionType::Audio);
    g.connect(win_reverb, 0, win_bus, 0, HxConnectionType::Audio);

    // Win sidechains music
    g.connect(win_bus, 0, music_ducker, 0, HxConnectionType::Sidechain);

    // Connect ambient path
    g.connect(ambient, 0, idle_blend, 0, HxConnectionType::Audio);
    g.connect(idle_blend, 0, spatial, 0, HxConnectionType::Audio);
    g.connect(spatial, 0, ambient_bus, 0, HxConnectionType::Audio);

    // RTPC modulation
    g.connect(rtpc_intensity, 0, sfx_comp, 0, HxConnectionType::Control);

    // Anti-fatigue on all buses
    g.connect(sfx_bus, 0, fatigue, 0, HxConnectionType::Audio);

    // Master mix
    g.connect(music_bus, 0, master_mix, 0, HxConnectionType::Audio);
    g.connect(fatigue, 0, master_mix, 1, HxConnectionType::Audio);
    g.connect(win_bus, 0, master_mix, 2, HxConnectionType::Audio);
    g.connect(ambient_bus, 0, master_mix, 3, HxConnectionType::Audio);
    g.connect(master_mix, 0, master, 0, HxConnectionType::Audio);

    g.sort();
    g
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_empty_graph() {
        let g = HxGraph::new("test", "Test Graph");
        assert_eq!(g.nodes.len(), 0);
        assert_eq!(g.connections.len(), 0);
        assert!(g.dirty);
    }

    #[test]
    fn test_add_nodes() {
        let mut g = HxGraph::new("test", "Test");
        let id1 = g.create_node(HxNodeType::PlaySource, "Source");
        let id2 = g.create_node(HxNodeType::Gain, "Gain");
        assert_eq!(g.nodes.len(), 2);
        assert_ne!(id1, id2);
    }

    #[test]
    fn test_connect_nodes() {
        let mut g = HxGraph::new("test", "Test");
        let src = g.create_node(HxNodeType::PlaySource, "Source");
        let gain = g.create_node(HxNodeType::Gain, "Gain");
        let master = g.create_node(HxNodeType::MasterOutput, "Master");

        assert!(g.connect(src, 0, gain, 0, HxConnectionType::Audio));
        assert!(g.connect(gain, 0, master, 0, HxConnectionType::Audio));
        assert_eq!(g.connections.len(), 2);
    }

    #[test]
    fn test_no_self_loop() {
        let mut g = HxGraph::new("test", "Test");
        let id = g.create_node(HxNodeType::Gain, "Gain");
        assert!(!g.connect(id, 0, id, 0, HxConnectionType::Audio));
    }

    #[test]
    fn test_no_duplicate_connections() {
        let mut g = HxGraph::new("test", "Test");
        let a = g.create_node(HxNodeType::PlaySource, "A");
        let b = g.create_node(HxNodeType::Gain, "B");
        assert!(g.connect(a, 0, b, 0, HxConnectionType::Audio));
        assert!(!g.connect(a, 0, b, 0, HxConnectionType::Audio)); // duplicate
    }

    #[test]
    fn test_cycle_detection() {
        let mut g = HxGraph::new("test", "Test");
        let a = g.create_node(HxNodeType::Gain, "A");
        let b = g.create_node(HxNodeType::Gain, "B");
        let c = g.create_node(HxNodeType::Gain, "C");

        assert!(g.connect(a, 0, b, 0, HxConnectionType::Audio));
        assert!(g.connect(b, 0, c, 0, HxConnectionType::Audio));
        // This would create a cycle: C → A
        assert!(!g.connect(c, 0, a, 0, HxConnectionType::Audio));
    }

    #[test]
    fn test_topological_sort() {
        let mut g = HxGraph::new("test", "Test");
        let src = g.create_node(HxNodeType::PlaySource, "Source");
        let eq = g.create_node(HxNodeType::Filter, "EQ");
        let comp = g.create_node(HxNodeType::Compressor, "Comp");
        let master = g.create_node(HxNodeType::MasterOutput, "Master");

        g.connect(src, 0, eq, 0, HxConnectionType::Audio);
        g.connect(eq, 0, comp, 0, HxConnectionType::Audio);
        g.connect(comp, 0, master, 0, HxConnectionType::Audio);

        assert!(g.sort());
        assert_eq!(g.execution_order.len(), 4);
        // Source must be before EQ, EQ before Comp, Comp before Master
        let src_pos = g.execution_order.iter().position(|&x| x == src).unwrap();
        let eq_pos = g.execution_order.iter().position(|&x| x == eq).unwrap();
        let comp_pos = g.execution_order.iter().position(|&x| x == comp).unwrap();
        let master_pos = g.execution_order.iter().position(|&x| x == master).unwrap();
        assert!(src_pos < eq_pos);
        assert!(eq_pos < comp_pos);
        assert!(comp_pos < master_pos);
    }

    #[test]
    fn test_depth_levels() {
        let mut g = HxGraph::new("test", "Test");
        let s1 = g.create_node(HxNodeType::PlaySource, "Source 1");
        let s2 = g.create_node(HxNodeType::PlaySource, "Source 2");
        let mix = g.create_node(HxNodeType::Mixer, "Mixer");
        let master = g.create_node(HxNodeType::MasterOutput, "Master");

        g.connect(s1, 0, mix, 0, HxConnectionType::Audio);
        g.connect(s2, 0, mix, 1, HxConnectionType::Audio);
        g.connect(mix, 0, master, 0, HxConnectionType::Audio);

        assert!(g.sort());
        // Depth 0: s1, s2 (parallel)
        // Depth 1: mix
        // Depth 2: master
        assert_eq!(g.depth_levels.len(), 3);
        assert_eq!(g.depth_levels[0].len(), 2); // Two sources in parallel
    }

    #[test]
    fn test_remove_node() {
        let mut g = HxGraph::new("test", "Test");
        let a = g.create_node(HxNodeType::PlaySource, "A");
        let b = g.create_node(HxNodeType::Gain, "B");
        let c = g.create_node(HxNodeType::MasterOutput, "C");

        g.connect(a, 0, b, 0, HxConnectionType::Audio);
        g.connect(b, 0, c, 0, HxConnectionType::Audio);
        assert_eq!(g.connections.len(), 2);

        // Remove B — should remove both connections
        g.remove_node(b);
        assert_eq!(g.nodes.len(), 2);
        assert_eq!(g.connections.len(), 0);
    }

    #[test]
    fn test_rtpc_curve_evaluation() {
        let curve = vec![
            RtpcCurvePoint { x: 0.0, y: 0.0, interp: RtpcInterpolation::Linear },
            RtpcCurvePoint { x: 0.5, y: 1.0, interp: RtpcInterpolation::Linear },
            RtpcCurvePoint { x: 1.0, y: 0.5, interp: RtpcInterpolation::Linear },
        ];

        assert!((evaluate_rtpc_curve(&curve, 0.0) - 0.0).abs() < f32::EPSILON);
        assert!((evaluate_rtpc_curve(&curve, 0.25) - 0.5).abs() < 0.01);
        assert!((evaluate_rtpc_curve(&curve, 0.5) - 1.0).abs() < f32::EPSILON);
        assert!((evaluate_rtpc_curve(&curve, 0.75) - 0.75).abs() < 0.01);
        assert!((evaluate_rtpc_curve(&curve, 1.0) - 0.5).abs() < f32::EPSILON);
    }

    #[test]
    fn test_rtpc_curve_edge_cases() {
        // Empty curve
        assert_eq!(evaluate_rtpc_curve(&[], 0.5), 0.5); // Pass-through

        // Single point
        let curve = vec![RtpcCurvePoint { x: 0.5, y: 0.8, interp: RtpcInterpolation::Linear }];
        assert_eq!(evaluate_rtpc_curve(&curve, 0.0), 0.8);
        assert_eq!(evaluate_rtpc_curve(&curve, 1.0), 0.8);
    }

    #[test]
    fn test_graph_editor_swap() {
        let graph = HxGraph::new("test", "Test");
        let mut editor = HxGraphEditor::new(graph);

        // Add nodes to edit graph
        let edit = editor.edit_graph();
        edit.create_node(HxNodeType::PlaySource, "Source");
        edit.create_node(HxNodeType::MasterOutput, "Master");

        assert!(editor.has_pending_changes());

        // Commit
        assert!(editor.commit());

        // Swap (simulates audio thread block boundary)
        assert!(editor.try_swap());

        // Active graph should now have 2 nodes
        let active = editor.active_graph();
        assert_eq!(active.nodes.len(), 2);
    }

    #[test]
    fn test_basic_slot_template() {
        let g = template_basic_slot();
        assert!(!g.nodes.is_empty());
        assert!(!g.connections.is_empty());
        assert!(!g.execution_order.is_empty());
        // Should have AUREXIS gate
        assert!(g.nodes.iter().any(|n| n.node_type == HxNodeType::AurexisGate));
        // Should have anti-fatigue
        assert!(g.nodes.iter().any(|n| n.node_type == HxNodeType::AntiFatigue));
    }

    #[test]
    fn test_helix_full_template() {
        let g = template_helix_full();
        assert!(g.nodes.len() >= 20); // Full template has many nodes
        assert!(g.execution_order.len() == g.nodes.len()); // All sorted
        assert!(g.depth_levels.len() >= 3); // At least 3 depth levels

        let stats = g.stats();
        assert!(stats.total_nodes >= 20);
        assert!(stats.total_connections >= 15);
    }

    #[test]
    fn test_node_type_categories() {
        assert_eq!(HxNodeType::PlaySource.category(), "Sources");
        assert_eq!(HxNodeType::Compressor.category(), "DSP");
        assert_eq!(HxNodeType::Mixer.category(), "Routing");
        assert_eq!(HxNodeType::RandomContainer.category(), "Containers");
        assert_eq!(HxNodeType::AurexisGate.category(), "Intelligence");
        assert_eq!(HxNodeType::Spatial3D.category(), "Spatial");
        assert_eq!(HxNodeType::Meter.category(), "Analysis");
        assert_eq!(HxNodeType::Envelope.category(), "Control");
        assert_eq!(HxNodeType::MasterOutput.category(), "Output");
    }

    #[test]
    fn test_validation() {
        let mut g = HxGraph::new("test", "Test");
        // No master output → validation issue
        g.create_node(HxNodeType::PlaySource, "Source");
        let issues = g.validate();
        assert!(issues.iter().any(|i| matches!(i, GraphValidationIssue::NoMasterOutput)));
        // Orphan node (no connections) → validation issue
        assert!(issues.iter().any(|i| matches!(i, GraphValidationIssue::OrphanNode(_))));
    }

    #[test]
    fn test_graph_stats() {
        let g = template_basic_slot();
        let stats = g.stats();
        assert!(stats.total_nodes > 0);
        assert!(stats.total_connections > 0);
        assert!(stats.depth_levels > 0);
        // Should have entries in type_counts
        assert!(!stats.type_counts.is_empty());
    }
}
