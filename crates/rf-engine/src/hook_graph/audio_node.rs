//! AudioNode trait — base interface for all Rust-side graph nodes.
//!
//! Audio-rate nodes run on the audio thread at sample rate.
//! Control-rate nodes run in Dart (~60Hz) and send commands via rtrb.

use std::collections::HashMap;

/// Audio buffer pair (stereo)
pub struct AudioBuffer {
    pub left: Vec<f32>,
    pub right: Vec<f32>,
    pub frames: usize,
}

impl AudioBuffer {
    pub fn new(frames: usize) -> Self {
        Self {
            left: vec![0.0; frames],
            right: vec![0.0; frames],
            frames,
        }
    }

    /// Create buffer filled with a constant value (both channels)
    pub fn with_constant(frames: usize, value: f32) -> Self {
        Self {
            left: vec![value; frames],
            right: vec![value; frames],
            frames,
        }
    }

    pub fn clear(&mut self) {
        self.left.fill(0.0);
        self.right.fill(0.0);
    }

    pub fn resize(&mut self, frames: usize) {
        self.left.resize(frames, 0.0);
        self.right.resize(frames, 0.0);
        self.frames = frames;
    }
}

/// Context passed to audio nodes during processing
pub struct NodeContext<'a> {
    pub sample_rate: u32,
    pub frames: usize,
    pub tempo: f64,
    pub params: &'a HashMap<String, f64>,
}

impl<'a> Default for NodeContext<'a> {
    fn default() -> Self {
        static EMPTY_PARAMS: std::sync::LazyLock<HashMap<String, f64>> =
            std::sync::LazyLock::new(HashMap::new);
        Self {
            sample_rate: 48000,
            frames: 256,
            tempo: 120.0,
            params: &EMPTY_PARAMS,
        }
    }
}

/// Trait for audio-rate graph nodes (Rust side)
pub trait AudioNode: Send + Sync {
    fn type_id(&self) -> &'static str;

    fn process(
        &mut self,
        inputs: &[&AudioBuffer],
        output: &mut AudioBuffer,
        ctx: &NodeContext,
    );

    fn reset(&mut self);

    fn latency_samples(&self) -> usize { 0 }

    fn tail_samples(&self) -> usize { 0 }
}
