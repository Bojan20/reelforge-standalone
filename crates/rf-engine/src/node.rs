//! Audio graph nodes

use rf_core::Sample;
use std::any::Any;

/// Unique node identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct NodeId(pub u32);

impl NodeId {
    pub const MASTER: Self = Self(0);

    pub fn new(id: u32) -> Self {
        Self(id)
    }
}

/// Node type classification
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NodeType {
    Source,
    Effect,
    Bus,
    Master,
    Analyzer,
}

/// Audio node trait
pub trait AudioNode: Send + Sync {
    /// Node type
    fn node_type(&self) -> NodeType;

    /// Number of input channels
    fn num_inputs(&self) -> usize;

    /// Number of output channels
    fn num_outputs(&self) -> usize;

    /// Process audio
    fn process(&mut self, inputs: &[&[Sample]], outputs: &mut [&mut [Sample]]);

    /// Reset node state
    fn reset(&mut self);

    /// Set sample rate
    fn set_sample_rate(&mut self, sample_rate: f64);

    /// Get latency in samples
    fn latency(&self) -> usize {
        0
    }

    /// Downcast to concrete type
    fn as_any(&self) -> &dyn Any;
    fn as_any_mut(&mut self) -> &mut dyn Any;
}

/// Pass-through node (for testing)
pub struct PassthroughNode {
    channels: usize,
}

impl PassthroughNode {
    pub fn new(channels: usize) -> Self {
        Self { channels }
    }
}

impl AudioNode for PassthroughNode {
    fn node_type(&self) -> NodeType {
        NodeType::Effect
    }

    fn num_inputs(&self) -> usize {
        self.channels
    }

    fn num_outputs(&self) -> usize {
        self.channels
    }

    fn process(&mut self, inputs: &[&[Sample]], outputs: &mut [&mut [Sample]]) {
        for (input, output) in inputs.iter().zip(outputs.iter_mut()) {
            output.copy_from_slice(input);
        }
    }

    fn reset(&mut self) {}

    fn set_sample_rate(&mut self, _sample_rate: f64) {}

    fn as_any(&self) -> &dyn Any {
        self
    }

    fn as_any_mut(&mut self) -> &mut dyn Any {
        self
    }
}

/// Gain node
pub struct GainNode {
    gain: f64,
    channels: usize,
}

impl GainNode {
    pub fn new(channels: usize) -> Self {
        Self {
            gain: 1.0,
            channels,
        }
    }

    pub fn set_gain(&mut self, gain: f64) {
        self.gain = gain;
    }

    pub fn set_gain_db(&mut self, db: f64) {
        self.gain = 10.0_f64.powf(db / 20.0);
    }
}

impl AudioNode for GainNode {
    fn node_type(&self) -> NodeType {
        NodeType::Effect
    }

    fn num_inputs(&self) -> usize {
        self.channels
    }

    fn num_outputs(&self) -> usize {
        self.channels
    }

    fn process(&mut self, inputs: &[&[Sample]], outputs: &mut [&mut [Sample]]) {
        for (input, output) in inputs.iter().zip(outputs.iter_mut()) {
            for (i, o) in input.iter().zip(output.iter_mut()) {
                *o = *i * self.gain;
            }
        }
    }

    fn reset(&mut self) {}

    fn set_sample_rate(&mut self, _sample_rate: f64) {}

    fn as_any(&self) -> &dyn Any {
        self
    }

    fn as_any_mut(&mut self) -> &mut dyn Any {
        self
    }
}

/// Mixer node - sums multiple inputs
pub struct MixerNode {
    num_inputs: usize,
    num_outputs: usize,
}

impl MixerNode {
    pub fn new(num_inputs: usize, num_outputs: usize) -> Self {
        Self {
            num_inputs,
            num_outputs,
        }
    }
}

impl AudioNode for MixerNode {
    fn node_type(&self) -> NodeType {
        NodeType::Effect
    }

    fn num_inputs(&self) -> usize {
        self.num_inputs
    }

    fn num_outputs(&self) -> usize {
        self.num_outputs
    }

    fn process(&mut self, inputs: &[&[Sample]], outputs: &mut [&mut [Sample]]) {
        // Clear outputs first
        for output in outputs.iter_mut() {
            output.fill(0.0);
        }

        // Sum inputs into outputs (wrapping around output channels)
        for (i, input) in inputs.iter().enumerate() {
            let output_idx = i % self.num_outputs;
            for (sample, out) in input.iter().zip(outputs[output_idx].iter_mut()) {
                *out += *sample;
            }
        }
    }

    fn reset(&mut self) {}

    fn set_sample_rate(&mut self, _sample_rate: f64) {}

    fn as_any(&self) -> &dyn Any {
        self
    }

    fn as_any_mut(&mut self) -> &mut dyn Any {
        self
    }
}
