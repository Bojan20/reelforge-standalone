//! Mixer node — N-input summing mixer with per-input gain.

use crate::hook_graph::audio_node::{AudioBuffer, AudioNode, NodeContext};

pub struct MixerNode {
    input_gains: Vec<f32>,
    output_gain: f32,
}

impl MixerNode {
    pub fn new(input_count: usize) -> Self {
        Self {
            input_gains: vec![1.0; input_count],
            output_gain: 1.0,
        }
    }

    pub fn set_input_gain(&mut self, index: usize, gain: f32) {
        if index < self.input_gains.len() {
            self.input_gains[index] = gain.clamp(0.0, 4.0);
        }
    }

    pub fn set_output_gain(&mut self, gain: f32) {
        self.output_gain = gain.clamp(0.0, 4.0);
    }
}

impl AudioNode for MixerNode {
    fn type_id(&self) -> &'static str { "Mixer" }

    fn process(
        &mut self,
        inputs: &[&AudioBuffer],
        output: &mut AudioBuffer,
        _ctx: &NodeContext,
    ) {
        output.clear();

        for (idx, input) in inputs.iter().enumerate() {
            let gain = self.input_gains.get(idx).copied().unwrap_or(1.0) * self.output_gain;
            for i in 0..output.frames {
                output.left[i] += input.left[i] * gain;
                output.right[i] += input.right[i] * gain;
            }
        }
    }

    fn reset(&mut self) {}
}
