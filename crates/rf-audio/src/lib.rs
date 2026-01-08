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

mod device;
mod stream;
mod error;
mod engine;
mod ringbuf;
pub mod thread_priority;
pub mod aoip;
pub mod dsd_output;

#[cfg(target_os = "macos")]
pub mod coreaudio;

#[cfg(target_os = "windows")]
pub mod asio;

pub use device::*;
pub use stream::*;
pub use error::*;
pub use engine::*;
pub use ringbuf::*;
pub use thread_priority::{set_realtime_priority, PriorityResult};
pub use aoip::*;
pub use dsd_output::*;

#[cfg(target_os = "macos")]
pub use coreaudio::{
    CoreAudioDevice,
    CoreAudioStream,
    ClockDriftMonitor,
    AggregateDevice,
    list_devices as list_coreaudio_devices,
    list_aggregate_devices,
    get_aggregate_sub_devices,
    get_default_input_device_id,
    get_default_output_device_id,
};

#[cfg(target_os = "windows")]
pub use asio::{
    AsioDriverInfo,
    AsioSampleType,
    AsioBufferSizes,
    AsioChannelInfo,
    AsioStream,
    list_asio_drivers,
    load_asio_driver,
    show_control_panel as show_asio_control_panel,
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
