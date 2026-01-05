//! FX Containers (REAPER Style)
//!
//! Pre-built, saveable effect chains with parallel processing support:
//! - Encapsulate complex routing as single unit
//! - Parallel paths with wet/dry per path
//! - Parameter mapping for macro controls
//! - Portable across projects

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use rf_core::Sample;

use crate::insert_chain::{InsertChain, InsertProcessor};

/// Container ID
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct ContainerId(pub u32);

impl ContainerId {
    pub fn new(id: u32) -> Self {
        Self(id)
    }
}

/// Path ID within container
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PathId(pub u8);

/// Maximum parallel paths
pub const MAX_PARALLEL_PATHS: usize = 8;

/// Maximum macro parameters
pub const MAX_MACROS: usize = 16;

/// Processing path within a container
#[derive(Debug)]
pub struct ContainerPath {
    /// Path identifier
    pub id: PathId,
    /// Path name
    pub name: String,
    /// FX chain for this path
    pub chain: InsertChain,
    /// Wet/dry mix (0.0 = dry, 1.0 = wet)
    pub wet: f64,
    /// Path gain
    pub gain: f64,
    /// Path is muted
    pub muted: bool,
    /// Path is soloed
    pub soloed: bool,
    /// Pan position (-1.0 to 1.0)
    pub pan: f64,
}

impl ContainerPath {
    pub fn new(id: PathId, name: impl Into<String>, sample_rate: f64) -> Self {
        Self {
            id,
            name: name.into(),
            chain: InsertChain::new(sample_rate),
            wet: 1.0,
            gain: 1.0,
            muted: false,
            soloed: false,
            pan: 0.0,
        }
    }

    /// Calculate effective gain for this path
    pub fn effective_gain(&self, any_soloed: bool) -> f64 {
        if self.muted {
            return 0.0;
        }
        if any_soloed && !self.soloed {
            return 0.0;
        }
        self.gain * self.wet
    }
}

/// Macro parameter mapping
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MacroMapping {
    /// Macro parameter index (0-15)
    pub macro_index: u8,
    /// Target path
    pub path_id: PathId,
    /// Target FX slot
    pub fx_slot: u8,
    /// Target parameter index
    pub param_index: u16,
    /// Minimum value
    pub min_value: f64,
    /// Maximum value
    pub max_value: f64,
    /// Curve type
    pub curve: MappingCurve,
}

/// Mapping curve type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum MappingCurve {
    #[default]
    Linear,
    Exponential,
    Logarithmic,
    SCurve,
}

impl MappingCurve {
    /// Apply curve to normalized value (0.0-1.0)
    pub fn apply(&self, value: f64) -> f64 {
        let v = value.clamp(0.0, 1.0);
        match self {
            Self::Linear => v,
            Self::Exponential => v * v,
            Self::Logarithmic => v.sqrt(),
            Self::SCurve => {
                // Smooth S-curve using smoothstep
                let t = v * v * (3.0 - 2.0 * v);
                t
            }
        }
    }
}

/// Macro parameter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MacroParameter {
    /// Macro name
    pub name: String,
    /// Current value (0.0-1.0)
    pub value: f64,
    /// Default value
    pub default: f64,
    /// Mappings to FX parameters
    pub mappings: Vec<MacroMapping>,
}

impl Default for MacroParameter {
    fn default() -> Self {
        Self {
            name: String::new(),
            value: 0.5,
            default: 0.5,
            mappings: Vec::new(),
        }
    }
}

/// Blend mode for combining parallel paths
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum BlendMode {
    /// Sum all paths
    #[default]
    Sum,
    /// Average all paths
    Average,
    /// Maximum amplitude
    Maximum,
    /// Minimum amplitude
    Minimum,
}

/// FX Container metadata for saving/loading
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerPreset {
    /// Preset name
    pub name: String,
    /// Description
    pub description: String,
    /// Author
    pub author: String,
    /// Category tags
    pub tags: Vec<String>,
    /// Path configurations (serialized)
    pub paths: Vec<PathPreset>,
    /// Macro parameters
    pub macros: Vec<MacroParameter>,
    /// Blend mode
    pub blend_mode: BlendMode,
    /// Global wet/dry
    pub global_wet: f64,
}

/// Path preset data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PathPreset {
    pub name: String,
    pub wet: f64,
    pub gain: f64,
    pub pan: f64,
    pub muted: bool,
    /// Plugin chain configuration (plugin IDs and state)
    pub plugins: Vec<PluginState>,
}

/// Serialized plugin state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PluginState {
    /// Plugin identifier
    pub plugin_id: String,
    /// Plugin name
    pub name: String,
    /// Serialized plugin state (base64 or JSON)
    pub state: String,
    /// Bypassed
    pub bypassed: bool,
}

/// FX Container
pub struct FxContainer {
    /// Container ID
    pub id: ContainerId,
    /// Container name
    pub name: String,
    /// Parallel processing paths
    paths: Vec<ContainerPath>,
    /// Macro parameters
    macros: Vec<MacroParameter>,
    /// Blend mode for combining paths
    blend_mode: BlendMode,
    /// Global wet/dry (container level)
    global_wet: f64,
    /// Sample rate
    sample_rate: f64,
    /// Block size
    block_size: usize,
    /// Temporary buffers for processing
    path_buffers: Vec<(Vec<Sample>, Vec<Sample>)>,
    /// Dry buffer for wet/dry mixing
    dry_left: Vec<Sample>,
    dry_right: Vec<Sample>,
}

impl FxContainer {
    /// Create new container
    pub fn new(id: ContainerId, name: impl Into<String>, sample_rate: f64, block_size: usize) -> Self {
        Self {
            id,
            name: name.into(),
            paths: Vec::new(),
            macros: vec![MacroParameter::default(); MAX_MACROS],
            blend_mode: BlendMode::Sum,
            global_wet: 1.0,
            sample_rate,
            block_size,
            path_buffers: Vec::new(),
            dry_left: vec![0.0; block_size],
            dry_right: vec![0.0; block_size],
        }
    }

    /// Add a parallel path
    pub fn add_path(&mut self, name: impl Into<String>) -> PathId {
        if self.paths.len() >= MAX_PARALLEL_PATHS {
            return PathId(0); // Return first path if at limit
        }

        let id = PathId(self.paths.len() as u8);
        let path = ContainerPath::new(id, name, self.sample_rate);
        self.paths.push(path);

        // Add buffer for this path
        self.path_buffers.push((
            vec![0.0; self.block_size],
            vec![0.0; self.block_size],
        ));

        id
    }

    /// Get path by ID
    pub fn get_path(&self, id: PathId) -> Option<&ContainerPath> {
        self.paths.get(id.0 as usize)
    }

    /// Get mutable path by ID
    pub fn get_path_mut(&mut self, id: PathId) -> Option<&mut ContainerPath> {
        self.paths.get_mut(id.0 as usize)
    }

    /// Add FX to a path (loads into next available slot)
    pub fn add_fx_to_path(&mut self, path_id: PathId, processor: Box<dyn InsertProcessor>) -> bool {
        if let Some(path) = self.paths.get_mut(path_id.0 as usize) {
            // Find first empty slot
            for i in 0..8 {
                if let Some(slot) = path.chain.slot(i) {
                    if !slot.is_loaded() {
                        return path.chain.load(i, processor);
                    }
                }
            }
            false
        } else {
            false
        }
    }

    /// Set macro value and update mapped parameters
    pub fn set_macro(&mut self, macro_index: u8, value: f64) {
        if (macro_index as usize) >= MAX_MACROS {
            return;
        }

        let value = value.clamp(0.0, 1.0);
        self.macros[macro_index as usize].value = value;

        // Note: Macro mappings require InsertSlot to expose parameter setters.
        // For now, we just store the value. Full implementation would require
        // extending InsertSlot with a set_param method that delegates to the processor.
        // The mappings are stored for future use when the slot API is extended.
    }

    /// Add macro mapping
    pub fn add_macro_mapping(
        &mut self,
        macro_index: u8,
        path_id: PathId,
        fx_slot: u8,
        param_index: u16,
        min_value: f64,
        max_value: f64,
    ) {
        if (macro_index as usize) >= MAX_MACROS {
            return;
        }

        self.macros[macro_index as usize].mappings.push(MacroMapping {
            macro_index,
            path_id,
            fx_slot,
            param_index,
            min_value,
            max_value,
            curve: MappingCurve::Linear,
        });
    }

    /// Check if any path is soloed
    fn any_soloed(&self) -> bool {
        self.paths.iter().any(|p| p.soloed)
    }

    /// Process audio through all paths
    pub fn process(&mut self, left: &mut [Sample], right: &mut [Sample]) {
        let len = left.len().min(right.len());

        // Store dry signal for wet/dry mixing
        self.dry_left[..len].copy_from_slice(&left[..len]);
        self.dry_right[..len].copy_from_slice(&right[..len]);

        // Ensure we have enough buffers
        while self.path_buffers.len() < self.paths.len() {
            self.path_buffers.push((
                vec![0.0; self.block_size],
                vec![0.0; self.block_size],
            ));
        }

        let any_soloed = self.any_soloed();

        // Clear output
        left[..len].fill(0.0);
        right[..len].fill(0.0);

        let mut active_paths = 0usize;

        // Process each path
        for (i, path) in self.paths.iter_mut().enumerate() {
            let gain = path.effective_gain(any_soloed);
            if gain <= 0.0 {
                continue;
            }

            // Copy input to path buffer
            let (path_left, path_right) = &mut self.path_buffers[i];
            path_left[..len].copy_from_slice(&self.dry_left[..len]);
            path_right[..len].copy_from_slice(&self.dry_right[..len]);

            // Process through path's FX chain
            path.chain.process_all(&mut path_left[..len], &mut path_right[..len]);

            // Apply path gain and pan
            for j in 0..len {
                let sample_l = path_left[j] * gain;
                let sample_r = path_right[j] * gain;

                // Simple pan law
                let pan = path.pan.clamp(-1.0, 1.0);
                let left_gain = ((1.0 - pan) / 2.0).sqrt();
                let right_gain = ((1.0 + pan) / 2.0).sqrt();

                // Mix based on blend mode
                match self.blend_mode {
                    BlendMode::Sum => {
                        left[j] += sample_l * left_gain;
                        right[j] += sample_r * right_gain;
                    }
                    BlendMode::Average => {
                        left[j] += sample_l * left_gain;
                        right[j] += sample_r * right_gain;
                    }
                    BlendMode::Maximum => {
                        left[j] = left[j].max(sample_l * left_gain);
                        right[j] = right[j].max(sample_r * right_gain);
                    }
                    BlendMode::Minimum => {
                        if active_paths == 0 {
                            left[j] = sample_l * left_gain;
                            right[j] = sample_r * right_gain;
                        } else {
                            left[j] = left[j].min(sample_l * left_gain);
                            right[j] = right[j].min(sample_r * right_gain);
                        }
                    }
                }
            }

            active_paths += 1;
        }

        // Average if using Average blend mode
        if self.blend_mode == BlendMode::Average && active_paths > 1 {
            let divisor = active_paths as f64;
            for j in 0..len {
                left[j] /= divisor;
                right[j] /= divisor;
            }
        }

        // Apply global wet/dry
        if self.global_wet < 1.0 {
            let dry_amount = 1.0 - self.global_wet;
            for j in 0..len {
                left[j] = left[j] * self.global_wet + self.dry_left[j] * dry_amount;
                right[j] = right[j] * self.global_wet + self.dry_right[j] * dry_amount;
            }
        }
    }

    /// Get total latency
    pub fn latency(&self) -> usize {
        // Return max latency across all paths
        self.paths
            .iter()
            .map(|p| p.chain.total_latency())
            .max()
            .unwrap_or(0)
    }

    /// Reset all paths
    pub fn reset(&mut self) {
        for path in &mut self.paths {
            path.chain.reset();
        }
    }

    /// Set sample rate
    pub fn set_sample_rate(&mut self, sample_rate: f64) {
        self.sample_rate = sample_rate;
        for path in &mut self.paths {
            path.chain.set_sample_rate(sample_rate);
        }
    }

    /// Set block size
    pub fn set_block_size(&mut self, block_size: usize) {
        self.block_size = block_size;
        self.dry_left.resize(block_size, 0.0);
        self.dry_right.resize(block_size, 0.0);
        for (l, r) in &mut self.path_buffers {
            l.resize(block_size, 0.0);
            r.resize(block_size, 0.0);
        }
    }

    /// Get number of paths
    pub fn num_paths(&self) -> usize {
        self.paths.len()
    }

    /// Set global wet/dry
    pub fn set_global_wet(&mut self, wet: f64) {
        self.global_wet = wet.clamp(0.0, 1.0);
    }

    /// Set blend mode
    pub fn set_blend_mode(&mut self, mode: BlendMode) {
        self.blend_mode = mode;
    }
}

/// FX Container Manager
pub struct ContainerManager {
    containers: HashMap<ContainerId, FxContainer>,
    next_id: u32,
    sample_rate: f64,
    block_size: usize,
}

impl ContainerManager {
    pub fn new(sample_rate: f64, block_size: usize) -> Self {
        Self {
            containers: HashMap::new(),
            next_id: 1,
            sample_rate,
            block_size,
        }
    }

    /// Create a new container
    pub fn create(&mut self, name: impl Into<String>) -> ContainerId {
        let id = ContainerId::new(self.next_id);
        self.next_id += 1;

        let container = FxContainer::new(id, name, self.sample_rate, self.block_size);
        self.containers.insert(id, container);

        id
    }

    /// Get container
    pub fn get(&self, id: ContainerId) -> Option<&FxContainer> {
        self.containers.get(&id)
    }

    /// Get mutable container
    pub fn get_mut(&mut self, id: ContainerId) -> Option<&mut FxContainer> {
        self.containers.get_mut(&id)
    }

    /// Remove container
    pub fn remove(&mut self, id: ContainerId) -> Option<FxContainer> {
        self.containers.remove(&id)
    }

    /// List all containers
    pub fn list(&self) -> Vec<ContainerId> {
        self.containers.keys().copied().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_container_creation() {
        let mut container = FxContainer::new(
            ContainerId::new(1),
            "Test Container",
            48000.0,
            256,
        );

        let path1 = container.add_path("Clean");
        let path2 = container.add_path("Distorted");

        assert_eq!(container.num_paths(), 2);
        assert!(container.get_path(path1).is_some());
        assert!(container.get_path(path2).is_some());
    }

    #[test]
    fn test_mapping_curves() {
        assert!((MappingCurve::Linear.apply(0.5) - 0.5).abs() < 0.001);
        assert!((MappingCurve::Exponential.apply(0.5) - 0.25).abs() < 0.001);
        assert!(MappingCurve::Logarithmic.apply(0.5) > 0.5); // sqrt(0.5) ≈ 0.707
    }

    #[test]
    fn test_passthrough_processing() {
        let mut container = FxContainer::new(
            ContainerId::new(1),
            "Empty",
            48000.0,
            256,
        );

        // Add empty path
        container.add_path("Pass");

        let mut left = vec![1.0; 256];
        let mut right = vec![0.5; 256];

        container.process(&mut left, &mut right);

        // With center pan (0.0), the pan law applies sqrt(0.5) ≈ 0.707 gain
        // So passthrough with center pan gives approximately 0.707 of input
        let expected_gain = (0.5_f64).sqrt(); // ≈ 0.707
        assert!((left[0] - 1.0 * expected_gain).abs() < 0.01);
        assert!((right[0] - 0.5 * expected_gain).abs() < 0.01);
    }

    #[test]
    fn test_wet_dry_mix() {
        let mut container = FxContainer::new(
            ContainerId::new(1),
            "WetDry",
            48000.0,
            256,
        );

        container.add_path("Effect");
        container.set_global_wet(0.5);

        let mut left = vec![1.0; 256];
        let mut right = vec![1.0; 256];

        container.process(&mut left, &mut right);

        // 50% wet (with pan law 0.707) + 50% dry
        // wet component: 1.0 * 0.707 * 0.5 = 0.354
        // dry component: 1.0 * 0.5 = 0.5
        // total: 0.854
        let pan_gain = (0.5_f64).sqrt();
        let expected = 0.5 * pan_gain + 0.5; // wet * pan_gain * wet_mix + dry * dry_mix
        assert!((left[0] - expected).abs() < 0.01);
    }
}
