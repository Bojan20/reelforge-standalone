//! Gain node — linear amplitude with smoothing.
//! Zero-allocation, audio-thread safe.

use crate::hook_graph::audio_node::{AudioBuffer, AudioNode, NodeContext};

pub struct GainNode {
    target_gain: f32,
    current_gain: f32,
    smooth_coeff: f32,
}

impl GainNode {
    pub fn new(gain: f32) -> Self {
        Self {
            target_gain: gain,
            current_gain: gain,
            smooth_coeff: 0.005,
        }
    }

    pub fn set_gain(&mut self, gain: f32) {
        self.target_gain = gain.clamp(0.0, 4.0);
    }
}

impl AudioNode for GainNode {
    fn type_id(&self) -> &'static str { "Gain" }

    fn process(
        &mut self,
        inputs: &[&AudioBuffer],
        output: &mut AudioBuffer,
        _ctx: &NodeContext,
    ) {
        let input = match inputs.first() {
            Some(i) => *i,
            None => { output.clear(); return; }
        };

        for i in 0..output.frames {
            self.current_gain += (self.target_gain - self.current_gain) * self.smooth_coeff;
            output.left[i] = input.left[i] * self.current_gain;
            output.right[i] = input.right[i] * self.current_gain;
        }
    }

    fn reset(&mut self) {
        self.current_gain = self.target_gain;
    }
}
