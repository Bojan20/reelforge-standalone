//! State, Switch, and RTPC Definitions
//!
//! Wwise-style state management for dynamic audio behavior.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ═══════════════════════════════════════════════════════════════════════════════
// STATE GROUP
// ═══════════════════════════════════════════════════════════════════════════════

/// State group definition
///
/// States are global values that affect how sounds behave.
/// Only one state per group can be active at a time.
///
/// ## Example
/// ```rust
/// use rf_event::StateGroup;
///
/// let mut group = StateGroup::new(1, "GameState");
/// group.add_state(1, "Menu");
/// group.add_state(2, "Playing");
/// group.add_state(3, "Paused");
/// group.set_current(2);  // Set to "Playing"
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StateGroup {
    /// Unique group ID
    pub id: u32,
    /// Group name
    pub name: String,
    /// Available states (id → name)
    pub states: HashMap<u32, String>,
    /// Currently active state ID
    pub current_state: u32,
    /// Default state ID
    pub default_state: u32,
    /// Transition time when changing states (seconds)
    pub transition_time_secs: f32,
}

impl StateGroup {
    /// Create a new state group
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            states: HashMap::new(),
            current_state: 0,
            default_state: 0,
            transition_time_secs: 0.0,
        }
    }

    /// Add a state to the group
    pub fn add_state(&mut self, state_id: u32, name: impl Into<String>) {
        let name = name.into();
        self.states.insert(state_id, name);

        // First state added becomes default
        if self.states.len() == 1 {
            self.default_state = state_id;
            self.current_state = state_id;
        }
    }

    /// Set current state
    pub fn set_current(&mut self, state_id: u32) {
        if self.states.contains_key(&state_id) {
            self.current_state = state_id;
        }
    }

    /// Get current state name
    pub fn current_name(&self) -> Option<&str> {
        self.states.get(&self.current_state).map(|s| s.as_str())
    }

    /// Get state name by ID
    pub fn state_name(&self, state_id: u32) -> Option<&str> {
        self.states.get(&state_id).map(|s| s.as_str())
    }

    /// Get state ID by name
    pub fn state_id(&self, name: &str) -> Option<u32> {
        self.states
            .iter()
            .find(|(_, n)| n.as_str() == name)
            .map(|(id, _)| *id)
    }

    /// Reset to default state
    pub fn reset(&mut self) {
        self.current_state = self.default_state;
    }

    /// Set transition time
    pub fn with_transition(mut self, time_secs: f32) -> Self {
        self.transition_time_secs = time_secs;
        self
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SWITCH GROUP
// ═══════════════════════════════════════════════════════════════════════════════

/// Switch group definition
///
/// Switches are per-game-object values that control which sound
/// variant plays. Unlike states (global), switches are scoped to
/// individual emitters.
///
/// ## Example
/// ```rust
/// use rf_event::SwitchGroup;
///
/// let mut group = SwitchGroup::new(1, "Surface");
/// group.add_switch(1, "Concrete");
/// group.add_switch(2, "Wood");
/// group.add_switch(3, "Grass");
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwitchGroup {
    /// Unique group ID
    pub id: u32,
    /// Group name
    pub name: String,
    /// Available switches (id → name)
    pub switches: HashMap<u32, String>,
    /// Default switch ID
    pub default_switch: u32,
}

impl SwitchGroup {
    /// Create a new switch group
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            switches: HashMap::new(),
            default_switch: 0,
        }
    }

    /// Add a switch to the group
    pub fn add_switch(&mut self, switch_id: u32, name: impl Into<String>) {
        self.switches.insert(switch_id, name.into());

        // First switch added becomes default
        if self.switches.len() == 1 {
            self.default_switch = switch_id;
        }
    }

    /// Get switch name by ID
    pub fn switch_name(&self, switch_id: u32) -> Option<&str> {
        self.switches.get(&switch_id).map(|s| s.as_str())
    }

    /// Get switch ID by name
    pub fn switch_id(&self, name: &str) -> Option<u32> {
        self.switches
            .iter()
            .find(|(_, n)| n.as_str() == name)
            .map(|(id, _)| *id)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RTPC DEFINITION
// ═══════════════════════════════════════════════════════════════════════════════

/// RTPC (Real-Time Parameter Control) definition
///
/// RTPCs are continuously variable parameters that can drive
/// multiple properties (volume, pitch, filter, etc.) through curves.
///
/// ## Example
/// ```rust
/// use rf_event::RtpcDefinition;
///
/// let mut rtpc = RtpcDefinition::new(1, "Health")
///     .with_range(0.0, 100.0)
///     .with_default(100.0);
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RtpcDefinition {
    /// Unique RTPC ID
    pub id: u32,
    /// RTPC name
    pub name: String,
    /// Minimum value
    pub min: f32,
    /// Maximum value
    pub max: f32,
    /// Default value
    pub default: f32,
    /// Current value
    pub current: f32,
    /// Interpolation mode
    pub interpolation: RtpcInterpolation,
    /// Slew rate (units per second, 0 = instant)
    pub slew_rate: f32,
}

/// RTPC interpolation mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum RtpcInterpolation {
    /// No interpolation (instant change)
    #[default]
    None = 0,
    /// Linear interpolation over time
    Linear = 1,
    /// Exponential (faster response)
    Exponential = 2,
    /// Slew rate limited
    SlewRate = 3,
}

impl RtpcDefinition {
    /// Create a new RTPC definition
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            min: 0.0,
            max: 1.0,
            default: 0.5,
            current: 0.5,
            interpolation: RtpcInterpolation::None,
            slew_rate: 0.0,
        }
    }

    /// Set value range
    pub fn with_range(mut self, min: f32, max: f32) -> Self {
        self.min = min;
        self.max = max;
        self
    }

    /// Set default value
    pub fn with_default(mut self, default: f32) -> Self {
        self.default = default.clamp(self.min, self.max);
        self.current = self.default;
        self
    }

    /// Set interpolation mode
    pub fn with_interpolation(mut self, mode: RtpcInterpolation) -> Self {
        self.interpolation = mode;
        self
    }

    /// Set slew rate (for SlewRate interpolation)
    pub fn with_slew_rate(mut self, rate: f32) -> Self {
        self.slew_rate = rate;
        self.interpolation = RtpcInterpolation::SlewRate;
        self
    }

    /// Set current value (clamped to range)
    pub fn set_value(&mut self, value: f32) {
        self.current = value.clamp(self.min, self.max);
    }

    /// Get normalized value (0.0 - 1.0)
    #[inline]
    pub fn normalized(&self) -> f32 {
        if (self.max - self.min).abs() < f32::EPSILON {
            return 0.0;
        }
        (self.current - self.min) / (self.max - self.min)
    }

    /// Set from normalized value
    pub fn set_normalized(&mut self, normalized: f32) {
        let value = self.min + normalized.clamp(0.0, 1.0) * (self.max - self.min);
        self.set_value(value);
    }

    /// Reset to default
    pub fn reset(&mut self) {
        self.current = self.default;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RTPC CURVE POINT
// ═══════════════════════════════════════════════════════════════════════════════

/// RTPC curve point for mapping RTPC values to parameters
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct RtpcCurvePoint {
    /// RTPC value (x)
    pub rtpc_value: f32,
    /// Output value (y)
    pub output_value: f32,
    /// Curve shape to next point
    pub curve: RtpcCurveShape,
}

/// Curve shape between RTPC points
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum RtpcCurveShape {
    /// Linear interpolation
    #[default]
    Linear = 0,
    /// Logarithmic (base 3)
    Log3 = 1,
    /// Sine
    Sine = 2,
    /// Logarithmic (base 1)
    Log1 = 3,
    /// Inverse S-curve
    InvSCurve = 4,
    /// S-curve
    SCurve = 5,
    /// Exponential (base 1)
    Exp1 = 6,
    /// Exponential (base 3)
    Exp3 = 7,
    /// Constant (hold until next point)
    Constant = 8,
}

/// Complete RTPC curve (multiple points)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RtpcCurve {
    /// Curve points (sorted by rtpc_value)
    pub points: Vec<RtpcCurvePoint>,
}

impl RtpcCurve {
    /// Create empty curve
    pub fn new() -> Self {
        Self { points: Vec::new() }
    }

    /// Create linear 1:1 curve
    pub fn linear() -> Self {
        Self {
            points: vec![
                RtpcCurvePoint {
                    rtpc_value: 0.0,
                    output_value: 0.0,
                    curve: RtpcCurveShape::Linear,
                },
                RtpcCurvePoint {
                    rtpc_value: 1.0,
                    output_value: 1.0,
                    curve: RtpcCurveShape::Linear,
                },
            ],
        }
    }

    /// Add a point to the curve
    pub fn add_point(&mut self, rtpc_value: f32, output_value: f32, curve: RtpcCurveShape) {
        self.points.push(RtpcCurvePoint {
            rtpc_value,
            output_value,
            curve,
        });
        self.points
            .sort_by(|a, b| a.rtpc_value.partial_cmp(&b.rtpc_value).unwrap());
    }

    /// Evaluate curve at given RTPC value
    pub fn evaluate(&self, rtpc_value: f32) -> f32 {
        if self.points.is_empty() {
            return rtpc_value;
        }
        if self.points.len() == 1 {
            return self.points[0].output_value;
        }

        // Clamp to curve range
        if rtpc_value <= self.points[0].rtpc_value {
            return self.points[0].output_value;
        }
        if rtpc_value >= self.points.last().unwrap().rtpc_value {
            return self.points.last().unwrap().output_value;
        }

        // Find segment
        for i in 0..self.points.len() - 1 {
            let p0 = &self.points[i];
            let p1 = &self.points[i + 1];

            if rtpc_value >= p0.rtpc_value && rtpc_value <= p1.rtpc_value {
                let t = (rtpc_value - p0.rtpc_value) / (p1.rtpc_value - p0.rtpc_value);
                let shaped_t = self.apply_curve_shape(t, p0.curve);
                return p0.output_value + shaped_t * (p1.output_value - p0.output_value);
            }
        }

        self.points.last().unwrap().output_value
    }

    /// Apply curve shape to normalized position
    fn apply_curve_shape(&self, t: f32, shape: RtpcCurveShape) -> f32 {
        let t = t.clamp(0.0, 1.0);

        match shape {
            RtpcCurveShape::Linear => t,
            RtpcCurveShape::Log3 => (1.0 + t * 3.0).ln() / 4.0_f32.ln(),
            RtpcCurveShape::Sine => (t * std::f32::consts::FRAC_PI_2).sin(),
            RtpcCurveShape::Log1 => (1.0 + t).ln() / 2.0_f32.ln(),
            RtpcCurveShape::InvSCurve => {
                if t < 0.5 {
                    2.0 * t * t
                } else {
                    1.0 - 2.0 * (1.0 - t) * (1.0 - t)
                }
            }
            RtpcCurveShape::SCurve => {
                if t < 0.5 {
                    4.0 * t * t * t
                } else {
                    1.0 - (-2.0 * t + 2.0).powi(3) / 2.0
                }
            }
            RtpcCurveShape::Exp1 => {
                (std::f32::consts::E.powf(t) - 1.0) / (std::f32::consts::E - 1.0)
            }
            RtpcCurveShape::Exp3 => {
                (std::f32::consts::E.powf(t * 3.0) - 1.0) / (std::f32::consts::E.powi(3) - 1.0)
            }
            RtpcCurveShape::Constant => 0.0, // Hold at start value
        }
    }
}

impl Default for RtpcCurve {
    fn default() -> Self {
        Self::linear()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RTPC PARAMETER BINDING
// ═══════════════════════════════════════════════════════════════════════════════

/// Target parameter type for RTPC binding
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum RtpcTargetParameter {
    /// Volume (0.0 - 2.0, 1.0 = unity)
    Volume = 0,
    /// Pitch in semitones (-24 to +24)
    Pitch = 1,
    /// Low-pass filter cutoff (20 Hz - 20 kHz)
    LowPassFilter = 2,
    /// High-pass filter cutoff (20 Hz - 20 kHz)
    HighPassFilter = 3,
    /// Pan position (-1.0 to 1.0)
    Pan = 4,
    /// Bus volume
    BusVolume = 5,
    /// Reverb send level
    ReverbSend = 6,
    /// Delay send level
    DelaySend = 7,
    /// Width (stereo spread, 0.0 = mono, 1.0 = stereo)
    Width = 8,
    /// Playback rate (0.5 - 2.0, 1.0 = normal)
    PlaybackRate = 9,
}

impl RtpcTargetParameter {
    /// Get default output range for this parameter type
    pub fn default_range(&self) -> (f32, f32) {
        match self {
            RtpcTargetParameter::Volume => (0.0, 2.0),
            RtpcTargetParameter::Pitch => (-24.0, 24.0),
            RtpcTargetParameter::LowPassFilter => (20.0, 20000.0),
            RtpcTargetParameter::HighPassFilter => (20.0, 20000.0),
            RtpcTargetParameter::Pan => (-1.0, 1.0),
            RtpcTargetParameter::BusVolume => (0.0, 2.0),
            RtpcTargetParameter::ReverbSend => (0.0, 1.0),
            RtpcTargetParameter::DelaySend => (0.0, 1.0),
            RtpcTargetParameter::Width => (0.0, 1.0),
            RtpcTargetParameter::PlaybackRate => (0.5, 2.0),
        }
    }

    /// Get display name
    pub fn display_name(&self) -> &'static str {
        match self {
            RtpcTargetParameter::Volume => "Volume",
            RtpcTargetParameter::Pitch => "Pitch",
            RtpcTargetParameter::LowPassFilter => "Low-Pass Filter",
            RtpcTargetParameter::HighPassFilter => "High-Pass Filter",
            RtpcTargetParameter::Pan => "Pan",
            RtpcTargetParameter::BusVolume => "Bus Volume",
            RtpcTargetParameter::ReverbSend => "Reverb Send",
            RtpcTargetParameter::DelaySend => "Delay Send",
            RtpcTargetParameter::Width => "Width",
            RtpcTargetParameter::PlaybackRate => "Playback Rate",
        }
    }

    /// Convert from index
    pub fn from_index(index: u8) -> Self {
        match index {
            0 => RtpcTargetParameter::Volume,
            1 => RtpcTargetParameter::Pitch,
            2 => RtpcTargetParameter::LowPassFilter,
            3 => RtpcTargetParameter::HighPassFilter,
            4 => RtpcTargetParameter::Pan,
            5 => RtpcTargetParameter::BusVolume,
            6 => RtpcTargetParameter::ReverbSend,
            7 => RtpcTargetParameter::DelaySend,
            8 => RtpcTargetParameter::Width,
            9 => RtpcTargetParameter::PlaybackRate,
            _ => RtpcTargetParameter::Volume,
        }
    }
}

/// RTPC binding - connects RTPC to a target parameter via curve
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RtpcBinding {
    /// Unique binding ID
    pub id: u32,
    /// Source RTPC ID
    pub rtpc_id: u32,
    /// Target parameter type
    pub target: RtpcTargetParameter,
    /// Target bus ID (for bus-specific parameters)
    pub target_bus_id: Option<u32>,
    /// Target event ID (for event-specific bindings)
    pub target_event_id: Option<u32>,
    /// Mapping curve
    pub curve: RtpcCurve,
    /// Enable/disable binding
    pub enabled: bool,
}

impl RtpcBinding {
    /// Create a new binding
    pub fn new(id: u32, rtpc_id: u32, target: RtpcTargetParameter) -> Self {
        let (min_out, max_out) = target.default_range();
        let curve = RtpcCurve::linear_range(0.0, 1.0, min_out, max_out);

        Self {
            id,
            rtpc_id,
            target,
            target_bus_id: None,
            target_event_id: None,
            curve,
            enabled: true,
        }
    }

    /// Create binding for specific bus
    pub fn for_bus(id: u32, rtpc_id: u32, target: RtpcTargetParameter, bus_id: u32) -> Self {
        let mut binding = Self::new(id, rtpc_id, target);
        binding.target_bus_id = Some(bus_id);
        binding
    }

    /// Create binding for specific event
    pub fn for_event(id: u32, rtpc_id: u32, target: RtpcTargetParameter, event_id: u32) -> Self {
        let mut binding = Self::new(id, rtpc_id, target);
        binding.target_event_id = Some(event_id);
        binding
    }

    /// Evaluate binding - get output parameter value for given RTPC value
    pub fn evaluate(&self, rtpc_value: f32) -> f32 {
        if !self.enabled {
            // Return parameter default when disabled
            let (min, max) = self.target.default_range();
            return (min + max) / 2.0;
        }
        self.curve.evaluate(rtpc_value)
    }

    /// Set custom curve
    pub fn with_curve(mut self, curve: RtpcCurve) -> Self {
        self.curve = curve;
        self
    }

    /// Set enabled state
    pub fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
    }
}

impl RtpcCurve {
    /// Create linear curve with custom input/output range
    pub fn linear_range(in_min: f32, in_max: f32, out_min: f32, out_max: f32) -> Self {
        Self {
            points: vec![
                RtpcCurvePoint {
                    rtpc_value: in_min,
                    output_value: out_min,
                    curve: RtpcCurveShape::Linear,
                },
                RtpcCurvePoint {
                    rtpc_value: in_max,
                    output_value: out_max,
                    curve: RtpcCurveShape::Linear,
                },
            ],
        }
    }

    /// Create inverted linear curve
    pub fn inverted_linear(in_min: f32, in_max: f32, out_min: f32, out_max: f32) -> Self {
        Self {
            points: vec![
                RtpcCurvePoint {
                    rtpc_value: in_min,
                    output_value: out_max,
                    curve: RtpcCurveShape::Linear,
                },
                RtpcCurvePoint {
                    rtpc_value: in_max,
                    output_value: out_min,
                    curve: RtpcCurveShape::Linear,
                },
            ],
        }
    }

    /// Create S-curve (smooth transition)
    pub fn s_curve_range(in_min: f32, in_max: f32, out_min: f32, out_max: f32) -> Self {
        Self {
            points: vec![
                RtpcCurvePoint {
                    rtpc_value: in_min,
                    output_value: out_min,
                    curve: RtpcCurveShape::SCurve,
                },
                RtpcCurvePoint {
                    rtpc_value: in_max,
                    output_value: out_max,
                    curve: RtpcCurveShape::SCurve,
                },
            ],
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════════
// DUCKING MATRIX
// ═══════════════════════════════════════════════════════════════════════════════

/// Ducking rule - automatic volume reduction when source plays
///
/// When audio plays on the source bus, the target bus is ducked (volume reduced).
/// This is commonly used for voice-over ducking music, or win sounds ducking ambient.
///
/// ## Example
/// ```rust
/// use rf_event::DuckingRule;
///
/// // VO ducks music by -12dB with fast attack, slow release
/// let rule = DuckingRule::new(1, "VO", "Music")
///     .with_duck_amount(-12.0)
///     .with_attack_ms(50.0)
///     .with_release_ms(500.0);
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DuckingRule {
    /// Unique rule ID
    pub id: u32,
    /// Source bus name (triggers ducking when active)
    pub source_bus: String,
    /// Source bus ID
    pub source_bus_id: u32,
    /// Target bus name (gets ducked)
    pub target_bus: String,
    /// Target bus ID
    pub target_bus_id: u32,
    /// Duck amount in dB (negative values reduce volume)
    pub duck_amount_db: f32,
    /// Attack time in milliseconds
    pub attack_ms: f32,
    /// Release time in milliseconds
    pub release_ms: f32,
    /// Threshold - minimum source level to trigger ducking (0.0-1.0)
    pub threshold: f32,
    /// Curve shape for ducking
    pub curve: DuckingCurve,
    /// Enable/disable rule
    pub enabled: bool,
}

/// Ducking curve shape
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum DuckingCurve {
    /// Linear fade
    #[default]
    Linear = 0,
    /// Exponential (faster start)
    Exponential = 1,
    /// Logarithmic (slower start)
    Logarithmic = 2,
    /// S-curve (smooth)
    SCurve = 3,
}

impl DuckingRule {
    /// Create new ducking rule
    pub fn new(id: u32, source_bus: impl Into<String>, target_bus: impl Into<String>) -> Self {
        Self {
            id,
            source_bus: source_bus.into(),
            source_bus_id: 0,
            target_bus: target_bus.into(),
            target_bus_id: 0,
            duck_amount_db: -6.0,
            attack_ms: 50.0,
            release_ms: 500.0,
            threshold: 0.01,
            curve: DuckingCurve::Linear,
            enabled: true,
        }
    }

    /// Set bus IDs
    pub fn with_bus_ids(mut self, source_id: u32, target_id: u32) -> Self {
        self.source_bus_id = source_id;
        self.target_bus_id = target_id;
        self
    }

    /// Set duck amount in dB
    pub fn with_duck_amount(mut self, db: f32) -> Self {
        self.duck_amount_db = db;
        self
    }

    /// Set attack time
    pub fn with_attack_ms(mut self, ms: f32) -> Self {
        self.attack_ms = ms.max(0.0);
        self
    }

    /// Set release time
    pub fn with_release_ms(mut self, ms: f32) -> Self {
        self.release_ms = ms.max(0.0);
        self
    }

    /// Set threshold
    pub fn with_threshold(mut self, threshold: f32) -> Self {
        self.threshold = threshold.clamp(0.0, 1.0);
        self
    }

    /// Set curve shape
    pub fn with_curve(mut self, curve: DuckingCurve) -> Self {
        self.curve = curve;
        self
    }

    /// Convert dB to linear gain
    #[inline]
    pub fn duck_gain(&self) -> f32 {
        10.0_f32.powf(self.duck_amount_db / 20.0)
    }
}

/// Ducking matrix - collection of all ducking rules
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DuckingMatrix {
    /// All ducking rules
    pub rules: Vec<DuckingRule>,
}

impl DuckingMatrix {
    /// Create empty matrix
    pub fn new() -> Self {
        Self { rules: Vec::new() }
    }

    /// Add a rule
    pub fn add_rule(&mut self, rule: DuckingRule) {
        self.rules.push(rule);
    }

    /// Remove rule by ID
    pub fn remove_rule(&mut self, rule_id: u32) {
        self.rules.retain(|r| r.id != rule_id);
    }

    /// Get rule by ID
    pub fn get_rule(&self, rule_id: u32) -> Option<&DuckingRule> {
        self.rules.iter().find(|r| r.id == rule_id)
    }

    /// Get mutable rule by ID
    pub fn get_rule_mut(&mut self, rule_id: u32) -> Option<&mut DuckingRule> {
        self.rules.iter_mut().find(|r| r.id == rule_id)
    }

    /// Get all rules targeting a specific bus
    pub fn rules_for_target(&self, target_bus_id: u32) -> Vec<&DuckingRule> {
        self.rules
            .iter()
            .filter(|r| r.target_bus_id == target_bus_id && r.enabled)
            .collect()
    }

    /// Get all rules sourced from a specific bus
    pub fn rules_from_source(&self, source_bus_id: u32) -> Vec<&DuckingRule> {
        self.rules
            .iter()
            .filter(|r| r.source_bus_id == source_bus_id && r.enabled)
            .collect()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DUCKING STATE TRACKER (for real-time processing)
// ═══════════════════════════════════════════════════════════════════════════════

/// Tracks ducking state for a single rule (real-time safe)
#[derive(Debug, Clone)]
pub struct DuckingState {
    /// Rule ID being tracked
    pub rule_id: u32,
    /// Current duck multiplier (1.0 = no ducking, 0.0 = full duck)
    pub current_gain: f32,
    /// Target gain (based on source activity)
    pub target_gain: f32,
    /// Attack coefficient (pre-calculated)
    attack_coeff: f32,
    /// Release coefficient (pre-calculated)
    release_coeff: f32,
}

impl DuckingState {
    /// Create new ducking state for a rule
    pub fn new(rule: &DuckingRule, sample_rate: f32) -> Self {
        Self {
            rule_id: rule.id,
            current_gain: 1.0,
            target_gain: 1.0,
            attack_coeff: Self::calc_coeff(rule.attack_ms, sample_rate),
            release_coeff: Self::calc_coeff(rule.release_ms, sample_rate),
        }
    }

    /// Calculate smoothing coefficient from time in ms
    #[inline]
    fn calc_coeff(time_ms: f32, sample_rate: f32) -> f32 {
        if time_ms <= 0.0 {
            return 1.0;
        }
        let samples = (time_ms / 1000.0) * sample_rate;
        (-1.0 / samples).exp()
    }

    /// Update coefficients if rule parameters change
    pub fn update_from_rule(&mut self, rule: &DuckingRule, sample_rate: f32) {
        self.attack_coeff = Self::calc_coeff(rule.attack_ms, sample_rate);
        self.release_coeff = Self::calc_coeff(rule.release_ms, sample_rate);
    }

    /// Process one sample - returns duck multiplier
    #[inline]
    pub fn process(&mut self, source_active: bool, duck_gain: f32) -> f32 {
        self.target_gain = if source_active { duck_gain } else { 1.0 };

        let coeff = if self.target_gain < self.current_gain {
            self.attack_coeff
        } else {
            self.release_coeff
        };

        self.current_gain = coeff * self.current_gain + (1.0 - coeff) * self.target_gain;
        self.current_gain
    }

    /// Reset state to no ducking
    pub fn reset(&mut self) {
        self.current_gain = 1.0;
        self.target_gain = 1.0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// BLEND CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// Blend container child with crossfade range
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlendChild {
    /// Child ID (event or sound)
    pub id: u32,
    /// Child name
    pub name: String,
    /// RTPC range start (fade in starts here)
    pub rtpc_start: f32,
    /// RTPC range end (fade out ends here)
    pub rtpc_end: f32,
    /// Crossfade width (overlap with adjacent children)
    pub crossfade_width: f32,
}

impl BlendChild {
    /// Create new blend child
    pub fn new(id: u32, name: impl Into<String>, rtpc_start: f32, rtpc_end: f32) -> Self {
        Self {
            id,
            name: name.into(),
            rtpc_start,
            rtpc_end,
            crossfade_width: 0.1, // 10% overlap by default
        }
    }

    /// Set crossfade width (0.0 - 0.5)
    pub fn with_crossfade(mut self, width: f32) -> Self {
        self.crossfade_width = width.clamp(0.0, 0.5);
        self
    }

    /// Calculate gain for given RTPC value
    pub fn calculate_gain(&self, rtpc_value: f32) -> f32 {
        let range = self.rtpc_end - self.rtpc_start;
        let crossfade_range = range * self.crossfade_width;

        // Outside range completely
        if rtpc_value < self.rtpc_start - crossfade_range {
            return 0.0;
        }
        if rtpc_value > self.rtpc_end + crossfade_range {
            return 0.0;
        }

        // Fade in region
        if rtpc_value < self.rtpc_start + crossfade_range {
            let t = (rtpc_value - (self.rtpc_start - crossfade_range)) / (crossfade_range * 2.0);
            return t.clamp(0.0, 1.0);
        }

        // Fade out region
        if rtpc_value > self.rtpc_end - crossfade_range {
            let t = ((self.rtpc_end + crossfade_range) - rtpc_value) / (crossfade_range * 2.0);
            return t.clamp(0.0, 1.0);
        }

        // Full gain in middle
        1.0
    }
}

/// Blend container - crossfade between sounds based on RTPC
///
/// Multiple children are played simultaneously with volume controlled by RTPC.
/// Perfect for tension systems, speed-based variations, etc.
///
/// ## Slot Use Case: Reel Speed
/// ```rust
/// use rf_event::{BlendContainer, BlendChild};
///
/// let mut container = BlendContainer::new(1, "ReelSpeed", 1);  // RTPC 1 = Speed
/// container.add_child(BlendChild::new(1, "Slow_Loop", 0.0, 0.3));
/// container.add_child(BlendChild::new(2, "Medium_Loop", 0.25, 0.75));
/// container.add_child(BlendChild::new(3, "Fast_Loop", 0.7, 1.0));
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlendContainer {
    /// Unique container ID
    pub id: u32,
    /// Container name
    pub name: String,
    /// RTPC ID that controls blending
    pub rtpc_id: u32,
    /// Children (sounds to blend between)
    pub children: Vec<BlendChild>,
    /// Crossfade curve type
    pub crossfade_curve: CrossfadeCurve,
    /// Enable/disable container
    pub enabled: bool,
}

/// Crossfade curve type for blend transitions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum CrossfadeCurve {
    /// Linear crossfade
    #[default]
    Linear = 0,
    /// Equal power (constant loudness)
    EqualPower = 1,
    /// S-curve (smooth)
    SCurve = 2,
    /// Sin/Cos (most natural for music)
    SinCos = 3,
}

impl BlendContainer {
    /// Create new blend container
    pub fn new(id: u32, name: impl Into<String>, rtpc_id: u32) -> Self {
        Self {
            id,
            name: name.into(),
            rtpc_id,
            children: Vec::new(),
            crossfade_curve: CrossfadeCurve::EqualPower,
            enabled: true,
        }
    }

    /// Add child to container
    pub fn add_child(&mut self, child: BlendChild) {
        self.children.push(child);
        // Sort by RTPC start for consistent evaluation
        self.children
            .sort_by(|a, b| a.rtpc_start.partial_cmp(&b.rtpc_start).unwrap());
    }

    /// Remove child by ID
    pub fn remove_child(&mut self, child_id: u32) {
        self.children.retain(|c| c.id != child_id);
    }

    /// Set crossfade curve
    pub fn with_crossfade_curve(mut self, curve: CrossfadeCurve) -> Self {
        self.crossfade_curve = curve;
        self
    }

    /// Calculate gains for all children at given RTPC value
    pub fn calculate_gains(&self, rtpc_value: f32) -> Vec<(u32, f32)> {
        self.children
            .iter()
            .map(|child| {
                let gain = child.calculate_gain(rtpc_value);
                let shaped_gain = self.apply_crossfade_curve(gain);
                (child.id, shaped_gain)
            })
            .filter(|(_, gain)| *gain > 0.0001) // Skip inaudible
            .collect()
    }

    /// Apply crossfade curve shaping
    fn apply_crossfade_curve(&self, t: f32) -> f32 {
        let t = t.clamp(0.0, 1.0);
        match self.crossfade_curve {
            CrossfadeCurve::Linear => t,
            CrossfadeCurve::EqualPower => (t * std::f32::consts::FRAC_PI_2).sin(),
            CrossfadeCurve::SCurve => {
                if t < 0.5 {
                    2.0 * t * t
                } else {
                    1.0 - (-2.0 * t + 2.0).powi(2) / 2.0
                }
            }
            CrossfadeCurve::SinCos => {
                (t * std::f32::consts::PI - std::f32::consts::FRAC_PI_2).sin() * 0.5 + 0.5
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RANDOMIZATION CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// Random child with weight
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RandomChild {
    /// Child ID (event or sound)
    pub id: u32,
    /// Child name
    pub name: String,
    /// Selection weight (higher = more likely)
    pub weight: f32,
    /// Pitch variation range (semitones)
    pub pitch_min: f32,
    pub pitch_max: f32,
    /// Volume variation range (dB)
    pub volume_min: f32,
    pub volume_max: f32,
}

impl RandomChild {
    /// Create new random child
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            weight: 1.0,
            pitch_min: 0.0,
            pitch_max: 0.0,
            volume_min: 0.0,
            volume_max: 0.0,
        }
    }

    /// Set weight
    pub fn with_weight(mut self, weight: f32) -> Self {
        self.weight = weight.max(0.0);
        self
    }

    /// Set pitch variation (semitones)
    pub fn with_pitch_variation(mut self, min: f32, max: f32) -> Self {
        self.pitch_min = min;
        self.pitch_max = max;
        self
    }

    /// Set volume variation (dB)
    pub fn with_volume_variation(mut self, min: f32, max: f32) -> Self {
        self.volume_min = min;
        self.volume_max = max;
        self
    }
}

/// Random selection mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum RandomMode {
    /// Pure weighted random
    #[default]
    Random = 0,
    /// Shuffle (no repeats until all played)
    Shuffle = 1,
    /// Shuffle with history (avoid recent N)
    ShuffleWithHistory = 2,
    /// Round robin (sequential)
    RoundRobin = 3,
}

/// Randomization container - random sound selection with variation
///
/// ## Slot Use Cases
/// - Coin sounds with pitch/volume variation
/// - Button clicks with subtle differences
/// - Reel stop sounds (different per reel)
///
/// ## Example
/// ```rust
/// use rf_event::{RandomContainer, RandomChild, RandomMode};
///
/// let mut container = RandomContainer::new(1, "CoinSounds");
/// container.add_child(RandomChild::new(1, "Coin_1").with_weight(1.0));
/// container.add_child(RandomChild::new(2, "Coin_2").with_weight(1.5));  // More likely
/// container.add_child(RandomChild::new(3, "Coin_3").with_weight(0.5));  // Less likely
/// container.set_mode(RandomMode::ShuffleWithHistory);
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RandomContainer {
    /// Unique container ID
    pub id: u32,
    /// Container name
    pub name: String,
    /// Children (sounds to randomly select from)
    pub children: Vec<RandomChild>,
    /// Random selection mode
    pub mode: RandomMode,
    /// History size for shuffle modes
    pub avoid_repeat_count: u32,
    /// Global pitch variation (semitones, applied to all)
    pub global_pitch_min: f32,
    pub global_pitch_max: f32,
    /// Global volume variation (dB, applied to all)
    pub global_volume_min: f32,
    pub global_volume_max: f32,
    /// Enable/disable container
    pub enabled: bool,
}

impl RandomContainer {
    /// Create new random container
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            children: Vec::new(),
            mode: RandomMode::Random,
            avoid_repeat_count: 2,
            global_pitch_min: 0.0,
            global_pitch_max: 0.0,
            global_volume_min: 0.0,
            global_volume_max: 0.0,
            enabled: true,
        }
    }

    /// Add child
    pub fn add_child(&mut self, child: RandomChild) {
        self.children.push(child);
    }

    /// Remove child by ID
    pub fn remove_child(&mut self, child_id: u32) {
        self.children.retain(|c| c.id != child_id);
    }

    /// Set selection mode
    pub fn set_mode(&mut self, mode: RandomMode) {
        self.mode = mode;
    }

    /// Set global pitch variation
    pub fn with_global_pitch(mut self, min: f32, max: f32) -> Self {
        self.global_pitch_min = min;
        self.global_pitch_max = max;
        self
    }

    /// Set global volume variation
    pub fn with_global_volume(mut self, min: f32, max: f32) -> Self {
        self.global_volume_min = min;
        self.global_volume_max = max;
        self
    }

    /// Calculate total weight
    pub fn total_weight(&self) -> f32 {
        self.children.iter().map(|c| c.weight).sum()
    }
}

/// Random container playback state tracker
#[derive(Debug, Clone, Default)]
pub struct RandomContainerState {
    /// Container ID
    pub container_id: u32,
    /// Play history (for shuffle modes)
    pub history: Vec<u32>,
    /// Shuffle deck (for Shuffle mode)
    pub shuffle_deck: Vec<u32>,
    /// Current position in round-robin/shuffle
    pub current_index: usize,
}

impl RandomContainerState {
    /// Create new state for container
    pub fn new(container_id: u32) -> Self {
        Self {
            container_id,
            history: Vec::new(),
            shuffle_deck: Vec::new(),
            current_index: 0,
        }
    }

    /// Select next child based on container mode
    /// Returns (child_id, pitch_variation, volume_variation)
    pub fn select_next(
        &mut self,
        container: &RandomContainer,
        rng: &mut impl FnMut() -> f32,
    ) -> Option<(u32, f32, f32)> {
        if container.children.is_empty() {
            return None;
        }

        let child_id = match container.mode {
            RandomMode::Random => self.select_weighted_random(container, rng),
            RandomMode::Shuffle => self.select_shuffle(container, rng),
            RandomMode::ShuffleWithHistory => self.select_shuffle_with_history(container, rng),
            RandomMode::RoundRobin => self.select_round_robin(container),
        }?;

        // Get child for variations
        let child = container.children.iter().find(|c| c.id == child_id)?;

        // Calculate random variations
        let pitch = container.global_pitch_min
            + rng() * (container.global_pitch_max - container.global_pitch_min)
            + child.pitch_min
            + rng() * (child.pitch_max - child.pitch_min);
        let volume = container.global_volume_min
            + rng() * (container.global_volume_max - container.global_volume_min)
            + child.volume_min
            + rng() * (child.volume_max - child.volume_min);

        // Update history
        self.history.push(child_id);
        if self.history.len() > container.avoid_repeat_count as usize {
            self.history.remove(0);
        }

        Some((child_id, pitch, volume))
    }

    fn select_weighted_random(
        &self,
        container: &RandomContainer,
        rng: &mut impl FnMut() -> f32,
    ) -> Option<u32> {
        let total = container.total_weight();
        if total <= 0.0 {
            return container.children.first().map(|c| c.id);
        }

        let mut roll = rng() * total;
        for child in &container.children {
            roll -= child.weight;
            if roll <= 0.0 {
                return Some(child.id);
            }
        }
        container.children.last().map(|c| c.id)
    }

    fn select_shuffle(
        &mut self,
        container: &RandomContainer,
        rng: &mut impl FnMut() -> f32,
    ) -> Option<u32> {
        // Rebuild deck if empty
        if self.shuffle_deck.is_empty() {
            self.shuffle_deck = container.children.iter().map(|c| c.id).collect();
            // Fisher-Yates shuffle
            let n = self.shuffle_deck.len();
            for i in (1..n).rev() {
                let j = (rng() * (i + 1) as f32) as usize;
                self.shuffle_deck.swap(i, j);
            }
            self.current_index = 0;
        }

        let id = self.shuffle_deck.get(self.current_index).copied();
        self.current_index += 1;
        if self.current_index >= self.shuffle_deck.len() {
            self.shuffle_deck.clear();
        }
        id
    }

    fn select_shuffle_with_history(
        &mut self,
        container: &RandomContainer,
        rng: &mut impl FnMut() -> f32,
    ) -> Option<u32> {
        // Filter out recent history
        let available: Vec<_> = container
            .children
            .iter()
            .filter(|c| !self.history.contains(&c.id))
            .collect();

        if available.is_empty() {
            // All in history, pick least recent
            return self.history.first().copied();
        }

        // Weighted random from available
        let total: f32 = available.iter().map(|c| c.weight).sum();
        let mut roll = rng() * total;
        for child in &available {
            roll -= child.weight;
            if roll <= 0.0 {
                return Some(child.id);
            }
        }
        available.last().map(|c| c.id)
    }

    fn select_round_robin(&mut self, container: &RandomContainer) -> Option<u32> {
        if container.children.is_empty() {
            return None;
        }
        let id = container.children[self.current_index % container.children.len()].id;
        self.current_index += 1;
        Some(id)
    }

    /// Reset state
    pub fn reset(&mut self) {
        self.history.clear();
        self.shuffle_deck.clear();
        self.current_index = 0;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SEQUENCE CONTAINER
// ═══════════════════════════════════════════════════════════════════════════════

/// Sequence step
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SequenceStep {
    /// Step index (0-based)
    pub index: u32,
    /// Child ID (event or sound) to play
    pub child_id: u32,
    /// Child name
    pub child_name: String,
    /// Delay before this step (seconds from previous)
    pub delay_secs: f32,
    /// Duration override (0 = natural length)
    pub duration_secs: f32,
    /// Fade in time (seconds)
    pub fade_in_secs: f32,
    /// Fade out time (seconds)
    pub fade_out_secs: f32,
    /// Loop count (0 = infinite, 1 = once, etc)
    pub loop_count: u32,
}

impl SequenceStep {
    /// Create new sequence step
    pub fn new(index: u32, child_id: u32, name: impl Into<String>) -> Self {
        Self {
            index,
            child_id,
            child_name: name.into(),
            delay_secs: 0.0,
            duration_secs: 0.0,
            fade_in_secs: 0.0,
            fade_out_secs: 0.0,
            loop_count: 1,
        }
    }

    /// Set delay
    pub fn with_delay(mut self, secs: f32) -> Self {
        self.delay_secs = secs.max(0.0);
        self
    }

    /// Set duration
    pub fn with_duration(mut self, secs: f32) -> Self {
        self.duration_secs = secs.max(0.0);
        self
    }

    /// Set fades
    pub fn with_fades(mut self, fade_in: f32, fade_out: f32) -> Self {
        self.fade_in_secs = fade_in.max(0.0);
        self.fade_out_secs = fade_out.max(0.0);
        self
    }

    /// Set loop count
    pub fn with_loop(mut self, count: u32) -> Self {
        self.loop_count = count;
        self
    }
}

/// Sequence end behavior
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum SequenceEndBehavior {
    /// Stop after last step
    #[default]
    Stop = 0,
    /// Loop entire sequence
    Loop = 1,
    /// Hold last step
    HoldLast = 2,
    /// Ping-pong (reverse on end)
    PingPong = 3,
}

/// Sequence container - timed sequence of sounds
///
/// ## Slot Use Cases
/// - Reel cascade sounds (each reel 200ms apart)
/// - Win celebration sequences
/// - Anticipation build-ups
///
/// ## Example
/// ```rust
/// use rf_event::{SequenceContainer, SequenceStep};
///
/// let mut container = SequenceContainer::new(1, "ReelCascade");
/// container.add_step(SequenceStep::new(0, 1, "Reel1_Stop"));
/// container.add_step(SequenceStep::new(1, 2, "Reel2_Stop").with_delay(0.2));
/// container.add_step(SequenceStep::new(2, 3, "Reel3_Stop").with_delay(0.2));
/// container.add_step(SequenceStep::new(3, 4, "Reel4_Stop").with_delay(0.2));
/// container.add_step(SequenceStep::new(4, 5, "Reel5_Stop").with_delay(0.2));
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SequenceContainer {
    /// Unique container ID
    pub id: u32,
    /// Container name
    pub name: String,
    /// Sequence steps
    pub steps: Vec<SequenceStep>,
    /// End behavior
    pub end_behavior: SequenceEndBehavior,
    /// Speed multiplier (1.0 = normal)
    pub speed: f32,
    /// Enable/disable container
    pub enabled: bool,
}

impl SequenceContainer {
    /// Create new sequence container
    pub fn new(id: u32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
            steps: Vec::new(),
            end_behavior: SequenceEndBehavior::Stop,
            speed: 1.0,
            enabled: true,
        }
    }

    /// Add step
    pub fn add_step(&mut self, step: SequenceStep) {
        self.steps.push(step);
        self.steps.sort_by_key(|s| s.index);
    }

    /// Remove step by index
    pub fn remove_step(&mut self, index: u32) {
        self.steps.retain(|s| s.index != index);
    }

    /// Set end behavior
    pub fn with_end_behavior(mut self, behavior: SequenceEndBehavior) -> Self {
        self.end_behavior = behavior;
        self
    }

    /// Set playback speed
    pub fn with_speed(mut self, speed: f32) -> Self {
        self.speed = speed.max(0.1);
        self
    }

    /// Get total sequence duration
    pub fn total_duration(&self) -> f32 {
        self.steps
            .iter()
            .map(|s| s.delay_secs + s.duration_secs)
            .sum::<f32>()
            / self.speed
    }

    /// Get step at given time position
    pub fn step_at_time(&self, time_secs: f32) -> Option<(usize, &SequenceStep)> {
        let adjusted_time = time_secs * self.speed;
        let mut cumulative = 0.0;

        for (i, step) in self.steps.iter().enumerate() {
            cumulative += step.delay_secs;
            if adjusted_time >= cumulative
                && adjusted_time < cumulative + step.duration_secs.max(0.001)
            {
                return Some((i, step));
            }
            cumulative += step.duration_secs;
        }
        None
    }
}

/// Sequence container playback state
#[derive(Debug, Clone, Default)]
pub struct SequenceContainerState {
    /// Container ID
    pub container_id: u32,
    /// Current step index
    pub current_step: usize,
    /// Time since sequence started
    pub elapsed_secs: f32,
    /// Time since current step started
    pub step_elapsed_secs: f32,
    /// Current loop iteration (for step loops)
    pub step_loop_count: u32,
    /// Direction (for ping-pong)
    pub forward: bool,
    /// Is playing
    pub playing: bool,
}

impl SequenceContainerState {
    /// Create new state
    pub fn new(container_id: u32) -> Self {
        Self {
            container_id,
            current_step: 0,
            elapsed_secs: 0.0,
            step_elapsed_secs: 0.0,
            step_loop_count: 0,
            forward: true,
            playing: false,
        }
    }

    /// Start playback
    pub fn start(&mut self) {
        self.current_step = 0;
        self.elapsed_secs = 0.0;
        self.step_elapsed_secs = 0.0;
        self.step_loop_count = 0;
        self.forward = true;
        self.playing = true;
    }

    /// Stop playback
    pub fn stop(&mut self) {
        self.playing = false;
    }

    /// Reset to beginning
    pub fn reset(&mut self) {
        self.current_step = 0;
        self.elapsed_secs = 0.0;
        self.step_elapsed_secs = 0.0;
        self.step_loop_count = 0;
        self.forward = true;
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MUSIC STINGER SYSTEM
// ═══════════════════════════════════════════════════════════════════════════════

/// Music sync point type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum MusicSyncPoint {
    /// Immediate (no sync)
    #[default]
    Immediate = 0,
    /// Next beat
    Beat = 1,
    /// Next bar
    Bar = 2,
    /// Next marker
    Marker = 3,
    /// Custom grid (e.g., every 4 beats)
    CustomGrid = 4,
    /// End of current segment
    SegmentEnd = 5,
}

/// Stinger definition - music overlay triggered by game events
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Stinger {
    /// Unique stinger ID
    pub id: u32,
    /// Stinger name
    pub name: String,
    /// Sound/event ID to play
    pub sound_id: u32,
    /// Sync point (when to trigger)
    pub sync_point: MusicSyncPoint,
    /// Custom grid size (beats, for CustomGrid)
    pub custom_grid_beats: f32,
    /// Duck music during stinger (dB)
    pub music_duck_db: f32,
    /// Duck attack time (ms)
    pub duck_attack_ms: f32,
    /// Duck release time (ms)
    pub duck_release_ms: f32,
    /// Priority (higher overrides lower)
    pub priority: u32,
    /// Can interrupt other stingers
    pub can_interrupt: bool,
    /// Look-ahead time (ms) for scheduling
    pub look_ahead_ms: f32,
}

impl Stinger {
    /// Create new stinger
    pub fn new(id: u32, name: impl Into<String>, sound_id: u32) -> Self {
        Self {
            id,
            name: name.into(),
            sound_id,
            sync_point: MusicSyncPoint::Beat,
            custom_grid_beats: 4.0,
            music_duck_db: 0.0,
            duck_attack_ms: 10.0,
            duck_release_ms: 100.0,
            priority: 50,
            can_interrupt: false,
            look_ahead_ms: 50.0,
        }
    }

    /// Set sync point
    pub fn with_sync_point(mut self, sync: MusicSyncPoint) -> Self {
        self.sync_point = sync;
        self
    }

    /// Set custom grid
    pub fn with_custom_grid(mut self, beats: f32) -> Self {
        self.custom_grid_beats = beats.max(0.25);
        self.sync_point = MusicSyncPoint::CustomGrid;
        self
    }

    /// Set music ducking
    pub fn with_music_duck(mut self, db: f32, attack_ms: f32, release_ms: f32) -> Self {
        self.music_duck_db = db;
        self.duck_attack_ms = attack_ms.max(0.0);
        self.duck_release_ms = release_ms.max(0.0);
        self
    }

    /// Set priority
    pub fn with_priority(mut self, priority: u32) -> Self {
        self.priority = priority;
        self
    }

    /// Set interrupt behavior
    pub fn with_interrupt(mut self, can_interrupt: bool) -> Self {
        self.can_interrupt = can_interrupt;
        self
    }
}

/// Music segment for horizontal re-sequencing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MusicSegment {
    /// Unique segment ID
    pub id: u32,
    /// Segment name
    pub name: String,
    /// Sound/music ID
    pub sound_id: u32,
    /// Tempo (BPM)
    pub tempo: f32,
    /// Time signature (beats per bar)
    pub beats_per_bar: u32,
    /// Duration in bars
    pub duration_bars: u32,
    /// Entry cue (bars into segment where music begins)
    pub entry_cue_bars: f32,
    /// Exit cue (bars into segment where we can transition out)
    pub exit_cue_bars: f32,
    /// Loop start (bars)
    pub loop_start_bars: f32,
    /// Loop end (bars)
    pub loop_end_bars: f32,
    /// Transition markers (bar positions)
    pub markers: Vec<MusicMarker>,
}

/// Music marker for transitions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MusicMarker {
    /// Marker name
    pub name: String,
    /// Position in bars
    pub position_bars: f32,
    /// Marker type
    pub marker_type: MarkerType,
}

/// Marker type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum MarkerType {
    /// Generic marker
    #[default]
    Generic = 0,
    /// Entry point for transitions
    Entry = 1,
    /// Exit point for transitions
    Exit = 2,
    /// Sync point for stingers
    Sync = 3,
}

impl MusicSegment {
    /// Create new music segment
    pub fn new(id: u32, name: impl Into<String>, sound_id: u32) -> Self {
        Self {
            id,
            name: name.into(),
            sound_id,
            tempo: 120.0,
            beats_per_bar: 4,
            duration_bars: 4,
            entry_cue_bars: 0.0,
            exit_cue_bars: 4.0,
            loop_start_bars: 0.0,
            loop_end_bars: 4.0,
            markers: Vec::new(),
        }
    }

    /// Set tempo
    pub fn with_tempo(mut self, bpm: f32) -> Self {
        self.tempo = bpm.max(20.0);
        self
    }

    /// Set time signature
    pub fn with_time_signature(mut self, beats_per_bar: u32) -> Self {
        self.beats_per_bar = beats_per_bar.max(1);
        self
    }

    /// Set duration
    pub fn with_duration(mut self, bars: u32) -> Self {
        self.duration_bars = bars.max(1);
        self.exit_cue_bars = bars as f32;
        self.loop_end_bars = bars as f32;
        self
    }

    /// Add marker
    pub fn add_marker(
        &mut self,
        name: impl Into<String>,
        position_bars: f32,
        marker_type: MarkerType,
    ) {
        self.markers.push(MusicMarker {
            name: name.into(),
            position_bars,
            marker_type,
        });
        self.markers
            .sort_by(|a, b| a.position_bars.partial_cmp(&b.position_bars).unwrap());
    }

    /// Convert bars to seconds
    #[inline]
    pub fn bars_to_secs(&self, bars: f32) -> f32 {
        let beats_per_sec = self.tempo / 60.0;
        (bars * self.beats_per_bar as f32) / beats_per_sec
    }

    /// Convert seconds to bars
    #[inline]
    pub fn secs_to_bars(&self, secs: f32) -> f32 {
        let beats_per_sec = self.tempo / 60.0;
        (secs * beats_per_sec) / self.beats_per_bar as f32
    }

    /// Get next beat time from current position
    pub fn next_beat_time(&self, current_secs: f32) -> f32 {
        let beat_duration = 60.0 / self.tempo;
        let current_beat = current_secs / beat_duration;
        let next_beat = current_beat.ceil();
        next_beat * beat_duration
    }

    /// Get next bar time from current position
    pub fn next_bar_time(&self, current_secs: f32) -> f32 {
        let bar_duration = self.bars_to_secs(1.0);
        let current_bar = current_secs / bar_duration;
        let next_bar = current_bar.ceil();
        next_bar * bar_duration
    }
}

/// Music system state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MusicSystem {
    /// All segments
    pub segments: Vec<MusicSegment>,
    /// All stingers
    pub stingers: Vec<Stinger>,
    /// Currently playing segment ID
    pub current_segment_id: Option<u32>,
    /// Next segment to transition to
    pub next_segment_id: Option<u32>,
    /// Global music volume
    pub volume: f32,
    /// Music bus ID
    pub music_bus_id: u32,
}

impl Default for MusicSystem {
    fn default() -> Self {
        Self::new()
    }
}

impl MusicSystem {
    /// Create new music system
    pub fn new() -> Self {
        Self {
            segments: Vec::new(),
            stingers: Vec::new(),
            current_segment_id: None,
            next_segment_id: None,
            volume: 1.0,
            music_bus_id: 0,
        }
    }

    /// Add segment
    pub fn add_segment(&mut self, segment: MusicSegment) {
        self.segments.push(segment);
    }

    /// Remove segment
    pub fn remove_segment(&mut self, segment_id: u32) {
        self.segments.retain(|s| s.id != segment_id);
    }

    /// Add stinger
    pub fn add_stinger(&mut self, stinger: Stinger) {
        self.stingers.push(stinger);
    }

    /// Remove stinger
    pub fn remove_stinger(&mut self, stinger_id: u32) {
        self.stingers.retain(|s| s.id != stinger_id);
    }

    /// Get segment by ID
    pub fn get_segment(&self, segment_id: u32) -> Option<&MusicSegment> {
        self.segments.iter().find(|s| s.id == segment_id)
    }

    /// Get stinger by ID
    pub fn get_stinger(&self, stinger_id: u32) -> Option<&Stinger> {
        self.stingers.iter().find(|s| s.id == stinger_id)
    }

    /// Set current segment
    pub fn set_current_segment(&mut self, segment_id: u32) {
        if self.segments.iter().any(|s| s.id == segment_id) {
            self.current_segment_id = Some(segment_id);
        }
    }

    /// Queue next segment for transition
    pub fn queue_next_segment(&mut self, segment_id: u32) {
        if self.segments.iter().any(|s| s.id == segment_id) {
            self.next_segment_id = Some(segment_id);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ATTENUATION CURVES (Slot-specific)
// ═══════════════════════════════════════════════════════════════════════════════

/// Attenuation curve type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[repr(u8)]
pub enum AttenuationType {
    /// Win amount based (higher win = louder)
    #[default]
    WinAmount = 0,
    /// Near-win proximity (closer to win = louder/more intense)
    NearWin = 1,
    /// Combo multiplier
    ComboMultiplier = 2,
    /// Feature progress (0% to 100%)
    FeatureProgress = 3,
    /// Time elapsed (tension build)
    TimeElapsed = 4,
}

/// Attenuation curve for slot-specific effects
///
/// Maps game parameters to audio parameters for dramatic effect.
///
/// ## Example
/// ```rust
/// use rf_event::{AttenuationCurve, AttenuationType};
///
/// // Near-win: Increase pitch and reverb as symbols almost align
/// let curve = AttenuationCurve::new(1, "NearWin_Tension", AttenuationType::NearWin)
///     .with_output_range(-12.0, 12.0)  // Pitch: -12 to +12 semitones
///     .with_input_range(0.0, 1.0);     // 0 = miss, 1 = almost-win
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttenuationCurve {
    /// Unique curve ID
    pub id: u32,
    /// Curve name
    pub name: String,
    /// Input type
    pub attenuation_type: AttenuationType,
    /// Input range
    pub input_min: f32,
    pub input_max: f32,
    /// Output range
    pub output_min: f32,
    pub output_max: f32,
    /// Curve shape
    pub curve_shape: RtpcCurveShape,
    /// Multi-point curve (optional, for complex responses)
    pub custom_curve: Option<RtpcCurve>,
    /// Enable/disable
    pub enabled: bool,
}

impl AttenuationCurve {
    /// Create new attenuation curve
    pub fn new(id: u32, name: impl Into<String>, attenuation_type: AttenuationType) -> Self {
        Self {
            id,
            name: name.into(),
            attenuation_type,
            input_min: 0.0,
            input_max: 1.0,
            output_min: 0.0,
            output_max: 1.0,
            curve_shape: RtpcCurveShape::Linear,
            custom_curve: None,
            enabled: true,
        }
    }

    /// Set input range
    pub fn with_input_range(mut self, min: f32, max: f32) -> Self {
        self.input_min = min;
        self.input_max = max;
        self
    }

    /// Set output range
    pub fn with_output_range(mut self, min: f32, max: f32) -> Self {
        self.output_min = min;
        self.output_max = max;
        self
    }

    /// Set curve shape
    pub fn with_curve_shape(mut self, shape: RtpcCurveShape) -> Self {
        self.curve_shape = shape;
        self
    }

    /// Set custom multi-point curve
    pub fn with_custom_curve(mut self, curve: RtpcCurve) -> Self {
        self.custom_curve = Some(curve);
        self
    }

    /// Evaluate curve at input value
    pub fn evaluate(&self, input: f32) -> f32 {
        if !self.enabled {
            return self.output_min;
        }

        // Use custom curve if set
        if let Some(ref curve) = self.custom_curve {
            return curve.evaluate(input);
        }

        // Normalize input
        let range = self.input_max - self.input_min;
        if range.abs() < f32::EPSILON {
            return self.output_min;
        }
        let t = ((input - self.input_min) / range).clamp(0.0, 1.0);

        // Apply curve shape
        let shaped_t = match self.curve_shape {
            RtpcCurveShape::Linear => t,
            RtpcCurveShape::Log3 => (1.0 + t * 3.0).ln() / 4.0_f32.ln(),
            RtpcCurveShape::Sine => (t * std::f32::consts::FRAC_PI_2).sin(),
            RtpcCurveShape::Log1 => (1.0 + t).ln() / 2.0_f32.ln(),
            RtpcCurveShape::InvSCurve => {
                if t < 0.5 {
                    2.0 * t * t
                } else {
                    1.0 - 2.0 * (1.0 - t) * (1.0 - t)
                }
            }
            RtpcCurveShape::SCurve => {
                if t < 0.5 {
                    4.0 * t * t * t
                } else {
                    1.0 - (-2.0 * t + 2.0).powi(3) / 2.0
                }
            }
            RtpcCurveShape::Exp1 => {
                (std::f32::consts::E.powf(t) - 1.0) / (std::f32::consts::E - 1.0)
            }
            RtpcCurveShape::Exp3 => {
                (std::f32::consts::E.powf(t * 3.0) - 1.0) / (std::f32::consts::E.powi(3) - 1.0)
            }
            RtpcCurveShape::Constant => 0.0,
        };

        // Map to output range
        self.output_min + shaped_t * (self.output_max - self.output_min)
    }
}

/// Attenuation system - collection of all attenuation curves
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AttenuationSystem {
    /// All curves
    pub curves: Vec<AttenuationCurve>,
}

impl AttenuationSystem {
    /// Create new attenuation system
    pub fn new() -> Self {
        Self { curves: Vec::new() }
    }

    /// Add curve
    pub fn add_curve(&mut self, curve: AttenuationCurve) {
        self.curves.push(curve);
    }

    /// Remove curve
    pub fn remove_curve(&mut self, curve_id: u32) {
        self.curves.retain(|c| c.id != curve_id);
    }

    /// Get curve by ID
    pub fn get_curve(&self, curve_id: u32) -> Option<&AttenuationCurve> {
        self.curves.iter().find(|c| c.id == curve_id)
    }

    /// Get curves by type
    pub fn curves_by_type(&self, atten_type: AttenuationType) -> Vec<&AttenuationCurve> {
        self.curves
            .iter()
            .filter(|c| c.attenuation_type == atten_type && c.enabled)
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_state_group() {
        let mut group = StateGroup::new(1, "GameState");
        group.add_state(1, "Menu");
        group.add_state(2, "Playing");
        group.add_state(3, "Paused");

        assert_eq!(group.current_state, 1); // First added is default
        assert_eq!(group.current_name(), Some("Menu"));

        group.set_current(2);
        assert_eq!(group.current_name(), Some("Playing"));

        assert_eq!(group.state_id("Paused"), Some(3));
        assert_eq!(group.state_name(3), Some("Paused"));
    }

    #[test]
    fn test_switch_group() {
        let mut group = SwitchGroup::new(1, "Surface");
        group.add_switch(1, "Concrete");
        group.add_switch(2, "Wood");
        group.add_switch(3, "Grass");

        assert_eq!(group.default_switch, 1);
        assert_eq!(group.switch_name(2), Some("Wood"));
        assert_eq!(group.switch_id("Grass"), Some(3));
    }

    #[test]
    fn test_rtpc_definition() {
        let mut rtpc = RtpcDefinition::new(1, "Health")
            .with_range(0.0, 100.0)
            .with_default(100.0);

        assert_eq!(rtpc.current, 100.0);
        assert_eq!(rtpc.normalized(), 1.0);

        rtpc.set_value(50.0);
        assert_eq!(rtpc.normalized(), 0.5);

        rtpc.set_normalized(0.25);
        assert_eq!(rtpc.current, 25.0);

        rtpc.set_value(200.0); // Should clamp
        assert_eq!(rtpc.current, 100.0);

        rtpc.reset();
        assert_eq!(rtpc.current, 100.0);
    }

    #[test]
    fn test_rtpc_curve() {
        let mut curve = RtpcCurve::new();
        curve.add_point(0.0, 0.0, RtpcCurveShape::Linear);
        curve.add_point(0.5, 0.8, RtpcCurveShape::Linear);
        curve.add_point(1.0, 1.0, RtpcCurveShape::Linear);

        // Before first point
        assert_eq!(curve.evaluate(-0.5), 0.0);

        // First point
        assert_eq!(curve.evaluate(0.0), 0.0);

        // Between points (linear)
        assert!((curve.evaluate(0.25) - 0.4).abs() < 0.001);

        // Middle point
        assert_eq!(curve.evaluate(0.5), 0.8);

        // Last point
        assert_eq!(curve.evaluate(1.0), 1.0);

        // After last point
        assert_eq!(curve.evaluate(1.5), 1.0);
    }

    #[test]
    fn test_default_linear_curve() {
        let curve = RtpcCurve::linear();

        assert_eq!(curve.evaluate(0.0), 0.0);
        assert_eq!(curve.evaluate(0.5), 0.5);
        assert_eq!(curve.evaluate(1.0), 1.0);
    }
}
