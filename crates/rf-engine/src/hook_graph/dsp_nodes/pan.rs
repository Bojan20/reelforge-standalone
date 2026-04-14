//! Pan node — equal-power stereo panner with smoothing.

use crate::hook_graph::audio_node::{AudioBuffer, AudioNode, NodeContext};

pub struct PanNode {
    target_pan: f32,
    current_pan: f32,
    smooth_coeff: f32,
}

impl PanNode {
    pub fn new(pan: f32) -> Self {
        Self {
            target_pan: pan.clamp(-1.0, 1.0),
            current_pan: pan.clamp(-1.0, 1.0),
            smooth_coeff: 0.005,
        }
    }

    pub fn set_pan(&mut self, pan: f32) {
        self.target_pan = pan.clamp(-1.0, 1.0);
    }
}

impl AudioNode for PanNode {
    fn type_id(&self) -> &'static str { "Pan" }

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
            self.current_pan += (self.target_pan - self.current_pan) * self.smooth_coeff;
            let angle = (self.current_pan + 1.0) * std::f32::consts::FRAC_PI_4;
            let gain_l = angle.cos();
            let gain_r = angle.sin();

            let mono = (input.left[i] + input.right[i]) * 0.5;
            output.left[i] = mono * gain_l;
            output.right[i] = mono * gain_r;
        }
    }

    fn reset(&mut self) {
        self.current_pan = self.target_pan;
    }
}
