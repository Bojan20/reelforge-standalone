//! rf-audio: Audio I/O using cpal
//!
//! Provides low-latency audio input/output with support for ASIO, CoreAudio, JACK, etc.
//!
//! # Architecture
//!
//! ```text
//! ┌──────────────┐     ┌─────────────┐     ┌─────────────┐
//! │ AudioEngine  │────▶│ AudioStream │────▶│ cpal Device │
//! │              │     │             │     │             │
//! │ - transport  │     │ - callback  │     │ - output    │
//! │ - metering   │     │ - buffers   │     │ - input     │
//! │ - processor  │     │             │     │             │
//! └──────────────┘     └─────────────┘     └─────────────┘
//! ```
//!
//! # Real-Time Thread Priority
//!
//! The `thread_priority` module provides platform-specific thread priority
//! elevation for deterministic audio latency. Call `set_realtime_priority()`
//! at the start of your audio callback thread.

pub mod aoip;
mod device;
pub mod dsd_output;
mod engine;
mod error;
pub mod multi_output;
mod ringbuf;
mod stream;
pub mod thread_priority;

#[cfg(target_os = "macos")]
pub mod coreaudio;

#[cfg(target_os = "windows")]
pub mod asio;

pub use aoip::*;
pub use device::*;
pub use dsd_output::*;
pub use engine::*;
pub use error::*;
pub use multi_output::*;
pub use ringbuf::*;
pub use stream::*;
pub use thread_priority::{PriorityResult, set_realtime_priority};

#[cfg(target_os = "macos")]
pub use coreaudio::{
    AggregateDevice, ClockDriftMonitor, CoreAudioDevice, CoreAudioStream,
    get_aggregate_sub_devices, get_default_input_device_id, get_default_output_device_id,
    list_aggregate_devices, list_devices as list_coreaudio_devices,
};

#[cfg(target_os = "windows")]
pub use asio::{
    AsioBufferSizes, AsioChannelInfo, AsioDriverInfo, AsioSampleType, AsioStream,
    list_asio_drivers, load_asio_driver, show_control_panel as show_asio_control_panel,
};

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
