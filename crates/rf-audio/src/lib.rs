//! rf-audio: Audio I/O using cpal
//!
//! Provides low-latency audio input/output with support for ASIO, CoreAudio, JACK, etc.

mod device;
mod stream;
mod error;

pub use device::*;
pub use stream::*;
pub use error::*;

use rf_core::{BufferSize, SampleRate};

/// Audio engine configuration
#[derive(Debug, Clone)]
pub struct AudioConfig {
    pub sample_rate: SampleRate,
    pub buffer_size: BufferSize,
    pub input_channels: u16,
    pub output_channels: u16,
}

impl Default for AudioConfig {
    fn default() -> Self {
        Self {
            sample_rate: SampleRate::Hz48000,
            buffer_size: BufferSize::Samples256,
            input_channels: 2,
            output_channels: 2,
        }
    }
}
