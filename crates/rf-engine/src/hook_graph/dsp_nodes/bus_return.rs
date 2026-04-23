//! BusReturn node — sums audio from a bus back into the graph.
//!
//! Companion to BusSendNode. In the graph DAG, BusReturnNode represents a tap
//! point where audio from a specific bus feeds back into the processing chain.
//!
//! Use case: a reverb return bus feeds processed audio back into master output.
//! The ReturnBus (send_return.rs) accumulates send contributions, processes them
//! through its insert chain, and BusReturnNode reads the result.
//!
//! In practice, the graph renderer reads from BusBuffers to fill BusReturnNode's
//! output, making send→process→return a complete loop.

use crate::hook_graph::audio_node::{AudioBuffer, AudioNode, NodeContext};
use crate::track_manager::OutputBus;

pub struct BusReturnNode {
    /// Source bus to read from
    pub bus: OutputBus,
    /// Return level (0.0 = silent, 1.0 = unity)
    pub return_level: f32,
    /// Smoothed level
    target_level: f32,
    smooth_coeff: f32,
    /// Mute state
    pub muted: bool,
}

impl BusReturnNode {
    pub fn new(bus: OutputBus, return_level: f32) -> Self {
        let clamped = return_level.clamp(0.0, 2.0);
        Self {
            bus,
            return_level: clamped,
            target_level: clamped,
            smooth_coeff: 0.005,
            muted: false,
        }
    }

    /// Set return level with smoothing
    pub fn set_level(&mut self, level: f32) {
        self.target_level = level.clamp(0.0, 2.0);
    }

    /// Get source bus
    pub fn source(&self) -> OutputBus {
        self.bus
    }
}

impl AudioNode for BusReturnNode {
    fn type_id(&self) -> &'static str { "BusReturn" }

    fn process(
        &mut self,
        inputs: &[&AudioBuffer],
        output: &mut AudioBuffer,
        _ctx: &NodeContext,
    ) {
        if self.muted {
            output.clear();
            return;
        }

        // BusReturnNode reads from the bus buffer provided as input[0].
        // The graph renderer is responsible for feeding the correct bus buffer
        // as the input to this node (via BusBuffers::get_bus()).
        //
        // If no input is connected (bus not yet processed), output silence.
        let input = match inputs.first() {
            Some(i) => *i,
            None => { output.clear(); return; }
        };

        for i in 0..output.frames {
            self.return_level += self.smooth_coeff * (self.target_level - self.return_level);

            output.left[i] = input.left[i] * self.return_level;
            output.right[i] = input.right[i] * self.return_level;
        }
    }

    fn reset(&mut self) {
        self.return_level = self.target_level;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bus_return_passthrough() {
        let mut node = BusReturnNode::new(OutputBus::Sfx, 1.0);
        let input = AudioBuffer::with_constant(256, 0.5);
        let mut output = AudioBuffer::new(256);

        node.process(&[&input], &mut output, &NodeContext::default());

        // Should pass through at unity
        for i in 0..256 {
            assert!((output.left[i] - 0.5).abs() < 0.01, "sample {} = {}", i, output.left[i]);
        }
    }

    #[test]
    fn test_bus_return_muted() {
        let mut node = BusReturnNode::new(OutputBus::Music, 1.0);
        node.muted = true;
        let input = AudioBuffer::with_constant(256, 0.5);
        let mut output = AudioBuffer::new(256);

        node.process(&[&input], &mut output, &NodeContext::default());

        for i in 0..256 {
            assert_eq!(output.left[i], 0.0);
        }
    }

    #[test]
    fn test_bus_return_level() {
        let mut node = BusReturnNode::new(OutputBus::Voice, 0.5);
        // Force immediate (no smoothing lag in test)
        node.return_level = 0.5;
        node.smooth_coeff = 1.0; // instant
        let input = AudioBuffer::with_constant(256, 1.0);
        let mut output = AudioBuffer::new(256);

        node.process(&[&input], &mut output, &NodeContext::default());

        assert!((output.left[0] - 0.5).abs() < 0.01);
    }
}
