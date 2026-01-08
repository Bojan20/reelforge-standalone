//! Phase 3 Module Integration
//!
//! ULTIMATIVNI integration of all Phase 3 modules:
//! - rf-ml (AI Processing Suite)
//! - rf-spatial (Immersive Audio Engine)
//! - rf-restore (Audio Restoration Suite)
//! - rf-master (Intelligent Mastering Engine)
//! - rf-pitch (Polyphonic Pitch Engine)

use crate::graph::{NodeState, NodeType};

/// Integrated processor that wraps all Phase 3 modules
pub struct IntegratedProcessor {
    /// Current module type
    module: ModuleType,
    /// Sample rate
    sample_rate: f64,
    /// Block size
    block_size: usize,
    /// Processing state
    state: ProcessingState,
}

/// Available module types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModuleType {
    // ML Modules
    MlStemSeparation,
    MlDenoise,
    MlEnhance,
    MlVoiceIsolation,

    // Spatial Modules
    SpatialPanner,
    SpatialBinaural,
    SpatialReverb,
    SpatialAmbisonics,

    // Restoration Modules
    RestoreDenoise,
    RestoreDeclick,
    RestoreDeclip,
    RestoreDehum,
    RestoreDereverb,

    // Mastering Modules
    MasterLimiter,
    MasterEq,
    MasterCompressor,
    MasterStereoWidth,
    MasterLoudness,

    // Pitch Modules
    PitchDetector,
    PitchCorrector,
    PitchShifter,
}

impl ModuleType {
    /// Get default latency for this module
    pub fn default_latency(&self) -> u32 {
        match self {
            // ML modules have high latency (neural network processing)
            Self::MlStemSeparation => 8192,
            Self::MlDenoise => 2048,
            Self::MlEnhance => 2048,
            Self::MlVoiceIsolation => 4096,

            // Spatial modules have medium latency
            Self::SpatialPanner => 0,
            Self::SpatialBinaural => 128,
            Self::SpatialReverb => 512,
            Self::SpatialAmbisonics => 256,

            // Restoration modules have medium latency
            Self::RestoreDenoise => 2048,
            Self::RestoreDeclick => 512,
            Self::RestoreDeclip => 256,
            Self::RestoreDehum => 1024,
            Self::RestoreDereverb => 4096,

            // Mastering modules have low to medium latency
            Self::MasterLimiter => 64,
            Self::MasterEq => 0,
            Self::MasterCompressor => 32,
            Self::MasterStereoWidth => 0,
            Self::MasterLoudness => 0,

            // Pitch modules have medium latency
            Self::PitchDetector => 2048,
            Self::PitchCorrector => 1024,
            Self::PitchShifter => 2048,
        }
    }

    /// Convert to graph NodeType
    pub fn to_node_type(&self) -> NodeType {
        match self {
            Self::MlStemSeparation => NodeType::MlStemSeparation,
            Self::MlDenoise => NodeType::MlDenoise,
            Self::MlEnhance => NodeType::MlEnhance,
            Self::MlVoiceIsolation => NodeType::MlVoiceIsolation,

            Self::SpatialPanner => NodeType::SpatialPanner,
            Self::SpatialBinaural => NodeType::SpatialBinaural,
            Self::SpatialReverb => NodeType::SpatialReverb,
            Self::SpatialAmbisonics => NodeType::SpatialAmbisonics,

            Self::RestoreDenoise => NodeType::RestoreDenoise,
            Self::RestoreDeclick => NodeType::RestoreDeclick,
            Self::RestoreDeclip => NodeType::RestoreDeclip,
            Self::RestoreDehum => NodeType::RestoreDehum,
            Self::RestoreDereverb => NodeType::RestoreDereverb,

            Self::MasterLimiter => NodeType::MasterLimiter,
            Self::MasterEq => NodeType::MasterEq,
            Self::MasterCompressor => NodeType::MasterCompressor,
            Self::MasterStereoWidth => NodeType::MasterStereoWidth,
            Self::MasterLoudness => NodeType::MasterLoudness,

            Self::PitchDetector => NodeType::PitchDetector,
            Self::PitchCorrector => NodeType::PitchCorrector,
            Self::PitchShifter => NodeType::PitchShifter,
        }
    }

    /// Get all available modules
    pub fn all() -> Vec<Self> {
        vec![
            Self::MlStemSeparation,
            Self::MlDenoise,
            Self::MlEnhance,
            Self::MlVoiceIsolation,
            Self::SpatialPanner,
            Self::SpatialBinaural,
            Self::SpatialReverb,
            Self::SpatialAmbisonics,
            Self::RestoreDenoise,
            Self::RestoreDeclick,
            Self::RestoreDeclip,
            Self::RestoreDehum,
            Self::RestoreDereverb,
            Self::MasterLimiter,
            Self::MasterEq,
            Self::MasterCompressor,
            Self::MasterStereoWidth,
            Self::MasterLoudness,
            Self::PitchDetector,
            Self::PitchCorrector,
            Self::PitchShifter,
        ]
    }

    /// Get modules by category
    pub fn ml_modules() -> Vec<Self> {
        vec![
            Self::MlStemSeparation,
            Self::MlDenoise,
            Self::MlEnhance,
            Self::MlVoiceIsolation,
        ]
    }

    pub fn spatial_modules() -> Vec<Self> {
        vec![
            Self::SpatialPanner,
            Self::SpatialBinaural,
            Self::SpatialReverb,
            Self::SpatialAmbisonics,
        ]
    }

    pub fn restoration_modules() -> Vec<Self> {
        vec![
            Self::RestoreDenoise,
            Self::RestoreDeclick,
            Self::RestoreDeclip,
            Self::RestoreDehum,
            Self::RestoreDereverb,
        ]
    }

    pub fn mastering_modules() -> Vec<Self> {
        vec![
            Self::MasterLimiter,
            Self::MasterEq,
            Self::MasterCompressor,
            Self::MasterStereoWidth,
            Self::MasterLoudness,
        ]
    }

    pub fn pitch_modules() -> Vec<Self> {
        vec![
            Self::PitchDetector,
            Self::PitchCorrector,
            Self::PitchShifter,
        ]
    }
}

/// Processing state for the integrated processor
#[derive(Clone)]
pub struct ProcessingState {
    /// Enabled
    pub enabled: bool,
    /// Wet/dry mix (0-1)
    pub mix: f64,
    /// Input gain (linear)
    pub input_gain: f64,
    /// Output gain (linear)
    pub output_gain: f64,
    /// Module-specific parameters
    pub params: Vec<f64>,
}

impl Default for ProcessingState {
    fn default() -> Self {
        Self {
            enabled: true,
            mix: 1.0,
            input_gain: 1.0,
            output_gain: 1.0,
            params: vec![0.0; 32], // Pre-allocate for any module
        }
    }
}

impl IntegratedProcessor {
    /// Create a new integrated processor
    pub fn new(module: ModuleType, sample_rate: f64, block_size: usize) -> Self {
        Self {
            module,
            sample_rate,
            block_size,
            state: ProcessingState::default(),
        }
    }

    /// Get module type
    pub fn module(&self) -> ModuleType {
        self.module
    }

    /// Set parameter
    pub fn set_param(&mut self, index: usize, value: f64) {
        if index < self.state.params.len() {
            self.state.params[index] = value;
        }
    }

    /// Get parameter
    pub fn get_param(&self, index: usize) -> f64 {
        self.state.params.get(index).copied().unwrap_or(0.0)
    }

    /// Set mix (wet/dry)
    pub fn set_mix(&mut self, mix: f64) {
        self.state.mix = mix.clamp(0.0, 1.0);
    }

    /// Set enabled
    pub fn set_enabled(&mut self, enabled: bool) {
        self.state.enabled = enabled;
    }

    /// Process audio (placeholder - would call actual module)
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        if !self.state.enabled {
            output.copy_from_slice(input);
            return;
        }

        // Apply input gain
        for (i, sample) in input.iter().enumerate() {
            output[i] = sample * self.state.input_gain;
        }

        // Here we would call the actual module processing
        // For now, this is a placeholder that passes through
        self.process_module(output);

        // Apply wet/dry mix
        if self.state.mix < 1.0 {
            let dry = 1.0 - self.state.mix;
            let wet = self.state.mix;
            for (i, &input_sample) in input.iter().enumerate() {
                output[i] = input_sample * dry + output[i] * wet;
            }
        }

        // Apply output gain
        for sample in output.iter_mut() {
            *sample *= self.state.output_gain;
        }
    }

    /// Module-specific processing (placeholder)
    fn process_module(&mut self, buffer: &mut [f64]) {
        // This would dispatch to the actual module implementation
        // For demonstration, just pass through
        match self.module {
            ModuleType::MasterLimiter => {
                // Apply simple limiting
                let threshold = 0.99;
                for sample in buffer.iter_mut() {
                    if sample.abs() > threshold {
                        *sample = sample.signum() * threshold;
                    }
                }
            }
            ModuleType::MasterEq => {
                // Pass through (EQ would use actual biquads)
            }
            ModuleType::SpatialPanner => {
                // Pan (would use actual panner)
            }
            _ => {
                // Other modules pass through for now
            }
        }
    }
}

impl NodeState for IntegratedProcessor {
    fn process(&mut self, inputs: &[&[f64]], outputs: &mut [&mut [f64]]) {
        if inputs.is_empty() || outputs.is_empty() {
            return;
        }

        // Process first channel pair
        if let (Some(input), Some(output)) = (inputs.first(), outputs.first_mut()) {
            IntegratedProcessor::process(self, input, output);
        }

        // Copy to other output channels if present
        if outputs.len() > 1 {
            // Copy first output to rest using split_first_mut
            let (first, rest) = outputs.split_first_mut().unwrap();
            for other in rest {
                other.copy_from_slice(first);
            }
        }
    }

    fn latency(&self) -> u32 {
        self.module.default_latency()
    }

    fn reset(&mut self) {
        self.state = ProcessingState::default();
    }

    fn num_inputs(&self) -> usize {
        2 // Stereo
    }

    fn num_outputs(&self) -> usize {
        2 // Stereo
    }
}

/// Processing chain combining multiple modules
pub struct ProcessingChain {
    processors: Vec<IntegratedProcessor>,
    sample_rate: f64,
    block_size: usize,
    /// Intermediate buffer
    buffer: Vec<f64>,
}

impl ProcessingChain {
    pub fn new(sample_rate: f64, block_size: usize) -> Self {
        Self {
            processors: Vec::new(),
            sample_rate,
            block_size,
            buffer: vec![0.0; block_size],
        }
    }

    /// Add a processor to the chain
    pub fn add(&mut self, module: ModuleType) -> usize {
        let processor = IntegratedProcessor::new(module, self.sample_rate, self.block_size);
        self.processors.push(processor);
        self.processors.len() - 1
    }

    /// Remove a processor
    pub fn remove(&mut self, index: usize) -> Option<IntegratedProcessor> {
        if index < self.processors.len() {
            Some(self.processors.remove(index))
        } else {
            None
        }
    }

    /// Get total latency
    pub fn total_latency(&self) -> u32 {
        self.processors.iter().map(|p| p.latency()).sum()
    }

    /// Process audio through the chain
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        if self.processors.is_empty() {
            output.copy_from_slice(input);
            return;
        }

        // Process through first processor
        self.processors[0].process(input, output);

        // Process through remaining processors
        for i in 1..self.processors.len() {
            self.buffer.copy_from_slice(output);
            self.processors[i].process(&self.buffer, output);
        }
    }

    /// Get processor at index
    pub fn get(&self, index: usize) -> Option<&IntegratedProcessor> {
        self.processors.get(index)
    }

    /// Get mutable processor at index
    pub fn get_mut(&mut self, index: usize) -> Option<&mut IntegratedProcessor> {
        self.processors.get_mut(index)
    }

    /// Number of processors
    pub fn len(&self) -> usize {
        self.processors.len()
    }

    /// Is empty
    pub fn is_empty(&self) -> bool {
        self.processors.is_empty()
    }
}

/// Preset for common processing chains
#[derive(Debug, Clone)]
pub struct ChainPreset {
    pub name: String,
    pub modules: Vec<ModuleType>,
    pub description: String,
}

impl ChainPreset {
    /// Mastering chain preset
    pub fn mastering() -> Self {
        Self {
            name: "Mastering".to_string(),
            modules: vec![
                ModuleType::MasterEq,
                ModuleType::MasterCompressor,
                ModuleType::MasterStereoWidth,
                ModuleType::MasterLoudness,
                ModuleType::MasterLimiter,
            ],
            description: "Complete mastering chain".to_string(),
        }
    }

    /// Restoration chain preset
    pub fn restoration() -> Self {
        Self {
            name: "Restoration".to_string(),
            modules: vec![
                ModuleType::RestoreDenoise,
                ModuleType::RestoreDeclick,
                ModuleType::RestoreDehum,
            ],
            description: "Audio restoration chain".to_string(),
        }
    }

    /// Vocal processing preset
    pub fn vocal() -> Self {
        Self {
            name: "Vocal".to_string(),
            modules: vec![
                ModuleType::RestoreDenoise,
                ModuleType::PitchCorrector,
                ModuleType::MasterCompressor,
                ModuleType::MasterEq,
            ],
            description: "Vocal processing chain".to_string(),
        }
    }

    /// Spatial audio preset
    pub fn spatial() -> Self {
        Self {
            name: "Spatial".to_string(),
            modules: vec![
                ModuleType::SpatialPanner,
                ModuleType::SpatialBinaural,
                ModuleType::SpatialReverb,
            ],
            description: "Spatial audio chain".to_string(),
        }
    }

    /// Get all presets
    pub fn all() -> Vec<Self> {
        vec![
            Self::mastering(),
            Self::restoration(),
            Self::vocal(),
            Self::spatial(),
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_module_type() {
        assert_eq!(ModuleType::MasterLimiter.default_latency(), 64);
        assert_eq!(ModuleType::MlStemSeparation.default_latency(), 8192);
        assert_eq!(ModuleType::all().len(), 21);
    }

    #[test]
    fn test_integrated_processor() {
        let mut processor = IntegratedProcessor::new(ModuleType::MasterLimiter, 48000.0, 512);

        assert!(processor.state.enabled);
        assert_eq!(processor.latency(), 64);

        processor.set_enabled(false);
        assert!(!processor.state.enabled);
    }

    #[test]
    fn test_processing_chain() {
        let mut chain = ProcessingChain::new(48000.0, 4);

        chain.add(ModuleType::MasterEq);
        chain.add(ModuleType::MasterLimiter);

        assert_eq!(chain.len(), 2);
        assert_eq!(chain.total_latency(), 0 + 64);

        let input = [0.5, 0.6, 0.7, 0.8];
        let mut output = [0.0; 4];

        chain.process(&input, &mut output);

        // Output should be processed
        assert!(!output.iter().all(|&x| x == 0.0));
    }

    #[test]
    fn test_presets() {
        let mastering = ChainPreset::mastering();
        assert_eq!(mastering.modules.len(), 5);

        let all = ChainPreset::all();
        assert_eq!(all.len(), 4);
    }

    #[test]
    fn test_wet_dry_mix() {
        let mut processor = IntegratedProcessor::new(ModuleType::MasterLimiter, 48000.0, 4);
        processor.set_mix(0.5);

        let input = [1.0, 1.0, 1.0, 1.0];
        let mut output = [0.0; 4];

        processor.process(&input, &mut output);

        // With 50% mix, output should be blend of dry and wet
        // Since limiter is near-transparent at low levels, should be close to input
        for &sample in &output {
            assert!((sample - 1.0).abs() < 0.1);
        }
    }
}
