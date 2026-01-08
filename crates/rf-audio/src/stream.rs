//! Audio stream management

use cpal::traits::{DeviceTrait, StreamTrait};
use cpal::{
    BufferSize as CpalBufferSize, Device, SampleFormat, Stream, StreamConfig,
    SupportedStreamConfig,
};
use parking_lot::Mutex;
use rtrb::{Consumer, Producer, RingBuffer};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use rf_core::{BufferSize, Sample};

use crate::{AudioConfig, AudioError, AudioResult};

/// Audio callback type
pub type AudioCallback = Box<dyn FnMut(&[Sample], &mut [Sample]) + Send + 'static>;

/// Shared input buffer between input and output streams
pub struct SharedInputBuffer {
    consumer: Mutex<Consumer<f32>>,
    num_channels: usize,
}

impl SharedInputBuffer {
    /// Read samples from input buffer into f64 slice
    pub fn read_to_f64(&self, output: &mut [f64]) {
        let mut consumer = self.consumer.lock();
        for (_i, sample) in output.iter_mut().enumerate() {
            *sample = consumer.pop().unwrap_or(0.0) as f64;
        }
    }

    /// Read samples as f32 directly
    pub fn read_to_f32(&self, output: &mut [f32]) {
        let mut consumer = self.consumer.lock();
        for sample in output.iter_mut() {
            *sample = consumer.pop().unwrap_or(0.0);
        }
    }

    /// Check how many samples are available
    pub fn available(&self) -> usize {
        self.consumer.lock().slots()
    }
}

/// Audio stream state
struct StreamState {
    callback: Mutex<AudioCallback>,
    running: AtomicBool,
    input_buffer: Option<Arc<SharedInputBuffer>>,
}

/// Audio stream wrapper
pub struct AudioStream {
    _output_stream: Stream,
    _input_stream: Option<Stream>,
    state: Arc<StreamState>,
    config: AudioConfig,
    /// Shared input buffer for recording
    pub input_buffer: Option<Arc<SharedInputBuffer>>,
}

impl AudioStream {
    /// Create a new audio stream with the given configuration
    pub fn new(
        output_device: &Device,
        input_device: Option<&Device>,
        config: AudioConfig,
        callback: AudioCallback,
    ) -> AudioResult<Self> {
        // Build input stream if device provided, get shared buffer
        let (input_stream, shared_input) = if let Some(input_dev) = input_device {
            let input_config = get_stream_config(input_dev, &config, true)?;
            let (stream, buffer) = build_input_stream_with_buffer(
                input_dev,
                &input_config,
                config.buffer_size,
                config.input_channels as usize,
            )?;
            (Some(stream), Some(buffer))
        } else {
            (None, None)
        };

        let state = Arc::new(StreamState {
            callback: Mutex::new(callback),
            running: AtomicBool::new(false),
            input_buffer: shared_input.clone(),
        });

        // Get supported output config
        let output_config = get_stream_config(output_device, &config, false)?;

        // Build output stream with access to input buffer
        let output_stream = build_output_stream_with_input(
            output_device,
            &output_config,
            config.buffer_size,
            Arc::clone(&state),
        )?;

        Ok(Self {
            _output_stream: output_stream,
            _input_stream: input_stream,
            state,
            config,
            input_buffer: shared_input,
        })
    }

    /// Start the audio stream
    pub fn start(&self) -> AudioResult<()> {
        self._output_stream
            .play()
            .map_err(|e| AudioError::StreamError(e.to_string()))?;

        if let Some(ref stream) = self._input_stream {
            stream
                .play()
                .map_err(|e| AudioError::StreamError(e.to_string()))?;
        }

        self.state.running.store(true, Ordering::Release);
        Ok(())
    }

    /// Stop the audio stream
    pub fn stop(&self) -> AudioResult<()> {
        self._output_stream
            .pause()
            .map_err(|e| AudioError::StreamError(e.to_string()))?;

        if let Some(ref stream) = self._input_stream {
            stream
                .pause()
                .map_err(|e| AudioError::StreamError(e.to_string()))?;
        }

        self.state.running.store(false, Ordering::Release);
        Ok(())
    }

    /// Check if stream is running
    pub fn is_running(&self) -> bool {
        self.state.running.load(Ordering::Acquire)
    }

    /// Get the stream configuration
    pub fn config(&self) -> &AudioConfig {
        &self.config
    }
}

fn get_output_stream_config(
    device: &Device,
    config: &AudioConfig,
) -> AudioResult<SupportedStreamConfig> {
    let sample_rate = cpal::SampleRate(config.sample_rate.as_u32());
    let channels = config.output_channels;

    let configs = device
        .supported_output_configs()
        .map_err(|e| AudioError::ConfigError(e.to_string()))?;

    for supported in configs {
        if supported.channels() >= channels
            && supported.min_sample_rate() <= sample_rate
            && supported.max_sample_rate() >= sample_rate
            && supported.sample_format() == SampleFormat::F32
        {
            return Ok(supported.with_sample_rate(sample_rate));
        }
    }

    Err(AudioError::ConfigError(format!(
        "No matching output config for {} channels @ {}Hz",
        channels,
        config.sample_rate.as_u32()
    )))
}

fn get_input_stream_config(
    device: &Device,
    config: &AudioConfig,
) -> AudioResult<SupportedStreamConfig> {
    let sample_rate = cpal::SampleRate(config.sample_rate.as_u32());
    let channels = config.input_channels;

    let configs = device
        .supported_input_configs()
        .map_err(|e| AudioError::ConfigError(e.to_string()))?;

    for supported in configs {
        if supported.channels() >= channels
            && supported.min_sample_rate() <= sample_rate
            && supported.max_sample_rate() >= sample_rate
            && supported.sample_format() == SampleFormat::F32
        {
            return Ok(supported.with_sample_rate(sample_rate));
        }
    }

    Err(AudioError::ConfigError(format!(
        "No matching input config for {} channels @ {}Hz",
        channels,
        config.sample_rate.as_u32()
    )))
}

fn get_stream_config(
    device: &Device,
    config: &AudioConfig,
    is_input: bool,
) -> AudioResult<SupportedStreamConfig> {
    if is_input {
        get_input_stream_config(device, config)
    } else {
        get_output_stream_config(device, config)
    }
}

fn build_output_stream_with_input(
    device: &Device,
    supported_config: &SupportedStreamConfig,
    buffer_size: BufferSize,
    state: Arc<StreamState>,
) -> AudioResult<Stream> {
    let channels = supported_config.channels() as usize;
    let sample_rate = supported_config.sample_rate();

    let config = StreamConfig {
        channels: supported_config.channels(),
        sample_rate,
        buffer_size: CpalBufferSize::Fixed(buffer_size.as_usize() as u32),
    };

    // Pre-allocate buffers for the callback
    let buffer_frames = buffer_size.as_usize();
    let mut input_buffer = vec![0.0f64; buffer_frames * 2]; // Stereo input
    let mut output_buffer = vec![0.0f64; buffer_frames * 2]; // Stereo output

    let stream = device
        .build_output_stream(
            &config,
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                let frames = data.len() / channels;

                // Read from shared input buffer if available
                if let Some(ref input_buf) = state.input_buffer {
                    input_buf.read_to_f64(&mut input_buffer[..frames * 2]);
                } else {
                    input_buffer[..frames * 2].fill(0.0);
                }

                // Clear output buffer
                output_buffer[..frames * 2].fill(0.0);

                // Call user callback with real input
                {
                    let mut callback = state.callback.lock();
                    callback(&input_buffer[..frames * 2], &mut output_buffer[..frames * 2]);
                }

                // Convert f64 to f32 and write to output
                // Handle mono/stereo conversion as needed
                match channels {
                    1 => {
                        for (i, sample) in data.iter_mut().enumerate() {
                            // Mix L+R to mono
                            let mono = (output_buffer[i * 2] + output_buffer[i * 2 + 1]) * 0.5;
                            *sample = mono as f32;
                        }
                    }
                    2 => {
                        for (i, sample) in data.iter_mut().enumerate() {
                            *sample = output_buffer[i] as f32;
                        }
                    }
                    _ => {
                        // Multi-channel: fill first 2 channels, zero rest
                        for (i, chunk) in data.chunks_mut(channels).enumerate() {
                            if i * 2 < output_buffer.len() {
                                chunk[0] = output_buffer[i * 2] as f32;
                                chunk[1] = output_buffer[i * 2 + 1] as f32;
                            }
                            for sample in chunk.iter_mut().skip(2) {
                                *sample = 0.0;
                            }
                        }
                    }
                }
            },
            move |err| {
                log::error!("Audio output stream error: {}", err);
            },
            None,
        )
        .map_err(|e| AudioError::StreamBuildError(e.to_string()))?;

    Ok(stream)
}

fn build_input_stream_with_buffer(
    device: &Device,
    supported_config: &SupportedStreamConfig,
    buffer_size: BufferSize,
    num_channels: usize,
) -> AudioResult<(Stream, Arc<SharedInputBuffer>)> {
    let channels = supported_config.channels() as usize;
    let sample_rate = supported_config.sample_rate();

    let config = StreamConfig {
        channels: supported_config.channels(),
        sample_rate,
        buffer_size: CpalBufferSize::Fixed(buffer_size.as_usize() as u32),
    };

    // Ring buffer for input data (8 buffers of headroom for safety)
    let ring_size = buffer_size.as_usize() * channels * 8;
    let (mut producer, consumer): (Producer<f32>, Consumer<f32>) = RingBuffer::new(ring_size);

    // Create shared input buffer
    let shared_buffer = Arc::new(SharedInputBuffer {
        consumer: Mutex::new(consumer),
        num_channels,
    });

    let stream = device
        .build_input_stream(
            &config,
            move |data: &[f32], _: &cpal::InputCallbackInfo| {
                // Push input samples to ring buffer
                for &sample in data {
                    // Overwrite oldest if full (avoid blocking)
                    if producer.push(sample).is_err() {
                        // Buffer full - could log a warning here
                    }
                }
            },
            move |err| {
                log::error!("Audio input stream error: {}", err);
            },
            None,
        )
        .map_err(|e| AudioError::StreamBuildError(e.to_string()))?;

    Ok((stream, shared_buffer))
}

/// Simple audio output for testing
pub fn test_output<F>(callback: F) -> AudioResult<AudioStream>
where
    F: FnMut(&[Sample], &mut [Sample]) + Send + 'static,
{
    let device = crate::get_default_output_device()?;
    let config = AudioConfig::default();

    AudioStream::new(&device, None, config, Box::new(callback))
}
