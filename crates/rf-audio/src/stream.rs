//! Audio stream management
//!
//! Lock-free audio streaming using rtrb ring buffers.
//! NO MUTEXES IN AUDIO CALLBACKS - this is critical for real-time audio.

use cpal::traits::{DeviceTrait, StreamTrait};
use cpal::{
    BufferSize as CpalBufferSize, Device, SampleFormat, Stream, StreamConfig, SupportedStreamConfig,
};
use rtrb::{Consumer, Producer, RingBuffer};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use rf_core::{BufferSize, Sample};

use crate::{AudioConfig, AudioError, AudioResult};

/// Audio callback type - takes ownership, no locking needed
pub type AudioCallback = Box<dyn FnMut(&[Sample], &mut [Sample]) + Send + 'static>;

/// Lock-free input buffer info
/// Consumer is moved into the output callback, no Mutex needed
pub struct SharedInputBuffer {
    /// Number of input channels
    num_channels: usize,
}

impl SharedInputBuffer {
    /// Create new shared input buffer info
    pub fn new(num_channels: usize) -> Self {
        Self { num_channels }
    }

    /// Get number of channels
    pub fn channels(&self) -> usize {
        self.num_channels
    }
}

/// Audio stream running state (lock-free)
struct StreamRunningState {
    running: AtomicBool,
}

/// Audio stream wrapper
pub struct AudioStream {
    _output_stream: Stream,
    _input_stream: Option<Stream>,
    running_state: Arc<StreamRunningState>,
    config: AudioConfig,
    /// Input buffer info for recording
    pub input_buffer: Option<Arc<SharedInputBuffer>>,
}

impl AudioStream {
    /// Create a new audio stream with the given configuration
    ///
    /// # Lock-free Design
    /// - Callback is MOVED into the output stream closure (no Mutex)
    /// - Input samples transferred via rtrb ring buffer (no Mutex)
    /// - All buffers pre-allocated before stream starts
    pub fn new(
        output_device: &Device,
        input_device: Option<&Device>,
        config: AudioConfig,
        callback: AudioCallback,
    ) -> AudioResult<Self> {
        let running_state = Arc::new(StreamRunningState {
            running: AtomicBool::new(false),
        });

        // Get supported output config first
        let output_config = get_stream_config(output_device, &config, false)?;

        // Build input stream if device provided
        // Returns (Stream, Consumer<f32>) - consumer goes to output callback
        let (input_stream, input_consumer, input_info) = if let Some(input_dev) = input_device {
            let input_config = get_stream_config(input_dev, &config, true)?;
            let (stream, consumer) = build_input_stream_lockfree(
                input_dev,
                &input_config,
                config.buffer_size,
            )?;
            let info = Arc::new(SharedInputBuffer::new(config.input_channels as usize));
            (Some(stream), Some(consumer), Some(info))
        } else {
            (None, None, None)
        };

        // Build output stream - callback is MOVED in, no Mutex
        let output_stream = build_output_stream_lockfree(
            output_device,
            &output_config,
            config.buffer_size,
            callback,
            input_consumer,
        )?;

        Ok(Self {
            _output_stream: output_stream,
            _input_stream: input_stream,
            running_state,
            config,
            input_buffer: input_info,
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

        self.running_state.running.store(true, Ordering::Release);
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

        self.running_state.running.store(false, Ordering::Release);
        Ok(())
    }

    /// Check if stream is running
    pub fn is_running(&self) -> bool {
        self.running_state.running.load(Ordering::Acquire)
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

/// Build output stream with LOCK-FREE design
///
/// # Design principles:
/// - Callback is MOVED into closure, not locked
/// - Input samples come from rtrb Consumer (lock-free)
/// - All buffers pre-allocated before stream creation
/// - Zero allocations in audio callback
fn build_output_stream_lockfree(
    device: &Device,
    supported_config: &SupportedStreamConfig,
    buffer_size: BufferSize,
    mut callback: AudioCallback,
    input_consumer: Option<Consumer<f32>>,
) -> AudioResult<Stream> {
    let channels = supported_config.channels() as usize;
    let sample_rate = supported_config.sample_rate();

    let config = StreamConfig {
        channels: supported_config.channels(),
        sample_rate,
        buffer_size: CpalBufferSize::Fixed(buffer_size.as_usize() as u32),
    };

    // PRE-ALLOCATE all buffers BEFORE stream creation
    // This is critical - no allocations allowed in audio callback
    let buffer_frames = buffer_size.as_usize();
    let max_frames = buffer_frames * 2; // Safety margin for variable buffer sizes

    // Pre-allocated f64 buffers for callback (stereo)
    let mut input_buffer_f64 = vec![0.0f64; max_frames * 2];
    let mut output_buffer_f64 = vec![0.0f64; max_frames * 2];

    // Pre-allocated f32 buffer for reading from input ring buffer
    let mut input_buffer_f32 = vec![0.0f32; max_frames * 2];

    // Move consumer into closure (Option allows us to check if input is available)
    let mut input_rx = input_consumer;

    // Track if denormals have been set (once per audio thread)
    let mut denormals_set = false;

    let stream = device
        .build_output_stream(
            &config,
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
                // ZERO ALLOCATIONS IN THIS CLOSURE
                // All buffers are pre-allocated and moved in

                // Set denormals to zero on first callback (once per audio thread)
                // This prevents massive CPU slowdown when processing very quiet audio
                if !denormals_set {
                    rf_dsp::simd::set_denormals_zero();
                    denormals_set = true;
                }

                let frames = data.len() / channels;
                let stereo_samples = frames * 2;

                // Read from input ring buffer if available (LOCK-FREE)
                if let Some(ref mut consumer) = input_rx {
                    // Read available samples from ring buffer
                    let mut read_count = 0;
                    for sample in input_buffer_f32[..stereo_samples].iter_mut() {
                        match consumer.pop() {
                            Ok(s) => {
                                *sample = s;
                                read_count += 1;
                            }
                            Err(_) => {
                                // Ring buffer empty - fill with silence
                                *sample = 0.0;
                            }
                        }
                    }

                    // Convert f32 input to f64 for callback
                    for (i, &sample) in input_buffer_f32[..stereo_samples].iter().enumerate() {
                        input_buffer_f64[i] = sample as f64;
                    }

                    // Log underrun only if significant (avoid spam)
                    if read_count == 0 && stereo_samples > 0 {
                        // Input underrun - silence already filled
                    }
                } else {
                    // No input device - clear input buffer
                    input_buffer_f64[..stereo_samples].fill(0.0);
                }

                // Clear output buffer
                output_buffer_f64[..stereo_samples].fill(0.0);

                // Call user callback directly - NO MUTEX
                // Callback was MOVED into this closure
                callback(
                    &input_buffer_f64[..stereo_samples],
                    &mut output_buffer_f64[..stereo_samples],
                );

                // Convert f64 to f32 and write to output
                // Handle mono/stereo/multi-channel conversion
                match channels {
                    1 => {
                        // Mono output: mix L+R
                        for i in 0..frames {
                            let mono = (output_buffer_f64[i * 2] + output_buffer_f64[i * 2 + 1]) * 0.5;
                            data[i] = mono as f32;
                        }
                    }
                    2 => {
                        // Stereo output: direct copy
                        for (i, sample) in data.iter_mut().enumerate() {
                            *sample = output_buffer_f64[i] as f32;
                        }
                    }
                    _ => {
                        // Multi-channel: fill first 2 channels, zero rest
                        for (i, chunk) in data.chunks_mut(channels).enumerate() {
                            let idx = i * 2;
                            if idx + 1 < output_buffer_f64.len() {
                                chunk[0] = output_buffer_f64[idx] as f32;
                                chunk[1] = output_buffer_f64[idx + 1] as f32;
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

/// Build input stream with LOCK-FREE ring buffer
///
/// Returns (Stream, Consumer<f32>) - Consumer goes directly to output callback
/// No Mutex wrapping the Consumer - it's already thread-safe
fn build_input_stream_lockfree(
    device: &Device,
    supported_config: &SupportedStreamConfig,
    buffer_size: BufferSize,
) -> AudioResult<(Stream, Consumer<f32>)> {
    let channels = supported_config.channels() as usize;
    let sample_rate = supported_config.sample_rate();

    let config = StreamConfig {
        channels: supported_config.channels(),
        sample_rate,
        buffer_size: CpalBufferSize::Fixed(buffer_size.as_usize() as u32),
    };

    // Ring buffer for input data
    // Size: 8 buffers of headroom for safety against timing jitter
    let ring_size = buffer_size.as_usize() * channels * 8;
    let (mut producer, consumer): (Producer<f32>, Consumer<f32>) = RingBuffer::new(ring_size);

    let stream = device
        .build_input_stream(
            &config,
            move |data: &[f32], _: &cpal::InputCallbackInfo| {
                // LOCK-FREE push to ring buffer
                // Producer::push is wait-free
                for &sample in data {
                    // If buffer is full, drop oldest samples (never block)
                    let _ = producer.push(sample);
                }
            },
            move |err| {
                log::error!("Audio input stream error: {}", err);
            },
            None,
        )
        .map_err(|e| AudioError::StreamBuildError(e.to_string()))?;

    // Return Consumer directly - no Mutex wrapper
    Ok((stream, consumer))
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
