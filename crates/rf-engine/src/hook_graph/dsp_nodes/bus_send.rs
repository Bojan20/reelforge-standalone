//! BusSend node — routes audio to a named bus with send level.

use crate::hook_graph::audio_node::{AudioBuffer, AudioNode, NodeContext};
use crate::track_manager::OutputBus;

pub struct BusSendNode {
    pub bus: OutputBus,
    pub send_level: f32,
    pub pre_fader: bool,
}

impl BusSendNode {
    pub fn new(bus: OutputBus, send_level: f32, pre_fader: bool) -> Self {
        Self {
            bus,
            send_level: send_level.clamp(0.0, 1.5),
            pre_fader,
        }
    }
}

impl AudioNode for BusSendNode {
    fn type_id(&self) -> &'static str { "BusSend" }

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
            output.left[i] = input.left[i] * self.send_level;
            output.right[i] = input.right[i] * self.send_level;
        }
    }

    fn reset(&mut self) {}
}
