//! BusSend node — applies send level for bus routing.
//!
//! In FluxForge's architecture, actual bus routing happens at the voice level:
//! each voice has an OutputBus assignment, and PlaybackEngine routes voice output
//! to the correct bus via BusBuffers::add_to_bus().
//!
//! BusSendNode's role in the graph is to apply send-level gain and mark audio
//! for a specific bus destination. The node stores the target bus so the graph
//! renderer knows where the audio should go.
//!
//! For aux sends (reverb, delay), audio passes through BusSendNode with a send
//! level, then the containing voice routes it to the destination bus.

use crate::hook_graph::audio_node::{AudioBuffer, AudioNode, NodeContext};
use crate::track_manager::OutputBus;

pub struct BusSendNode {
    /// Target bus for this send
    pub bus: OutputBus,
    /// Send level (0.0 = silent, 1.0 = unity, up to 1.5 for boost)
    pub send_level: f32,
    /// Pre-fader: send tapped before voice volume is applied
    pub pre_fader: bool,
    /// Smoothed level for click-free changes
    target_level: f32,
    smooth_coeff: f32,
}

impl BusSendNode {
    pub fn new(bus: OutputBus, send_level: f32, pre_fader: bool) -> Self {
        let clamped = send_level.clamp(0.0, 1.5);
        Self {
            bus,
            send_level: clamped,
            pre_fader,
            target_level: clamped,
            smooth_coeff: 0.005, // ~3ms at 48kHz
        }
    }

    /// Set send level with smoothing (click-free)
    pub fn set_level(&mut self, level: f32) {
        self.target_level = level.clamp(0.0, 1.5);
    }

    /// Get destination bus
    pub fn destination(&self) -> OutputBus {
        self.bus
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

        // Smooth level changes to avoid clicks
        for i in 0..output.frames {
            // One-pole smoother: level += coeff * (target - level)
            self.send_level += self.smooth_coeff * (self.target_level - self.send_level);

            output.left[i] = input.left[i] * self.send_level;
            output.right[i] = input.right[i] * self.send_level;
        }
    }

    fn reset(&mut self) {
        self.send_level = self.target_level;
    }
}
