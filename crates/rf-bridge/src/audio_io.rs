//! Audio I/O utilities for device management

use cpal::traits::{DeviceTrait, HostTrait};

/// Audio device info
#[derive(Debug, Clone)]
pub struct AudioDeviceInfo {
    pub id: String,
    pub name: String,
    pub is_default: bool,
    pub sample_rates: Vec<u32>,
    pub buffer_sizes: Vec<u32>,
    pub input_channels: u32,
    pub output_channels: u32,
}

/// Audio configuration
#[derive(Debug, Clone)]
pub struct AudioConfig {
    pub input_device: Option<String>,
    pub output_device: Option<String>,
    pub sample_rate: u32,
    pub buffer_size: u32,
    pub input_channels: u32,
    pub output_channels: u32,
}

impl Default for AudioConfig {
    fn default() -> Self {
        Self {
            input_device: None,
            output_device: None,
            sample_rate: 48000,
            buffer_size: 256,
            input_channels: 2,
            output_channels: 2,
        }
    }
}

/// Get available audio devices
/// Uses cpal for cross-platform device enumeration
pub fn get_audio_devices() -> Vec<AudioDeviceInfo> {
    let host = cpal::default_host();
    let mut devices = Vec::new();

    // Get output devices
    if let Ok(output_devices) = host.output_devices() {
        let default_output = host.default_output_device().and_then(|d| d.name().ok());

        for device in output_devices {
            if let Ok(name) = device.name() {
                let is_default = default_output.as_ref() == Some(&name);

                let mut sample_rates = Vec::new();
                let mut output_channels = 2;

                if let Ok(configs) = device.supported_output_configs() {
                    for config in configs {
                        sample_rates.push(config.min_sample_rate().0);
                        sample_rates.push(config.max_sample_rate().0);
                        output_channels = config.channels() as u32;
                    }
                }

                sample_rates.sort();
                sample_rates.dedup();

                devices.push(AudioDeviceInfo {
                    id: name.clone(),
                    name,
                    is_default,
                    sample_rates,
                    buffer_sizes: vec![64, 128, 256, 512, 1024, 2048],
                    input_channels: 0,
                    output_channels,
                });
            }
        }
    }

    // Get input devices
    if let Ok(input_devices) = host.input_devices() {
        let default_input = host.default_input_device().and_then(|d| d.name().ok());

        for device in input_devices {
            if let Ok(name) = device.name() {
                let is_default = default_input.as_ref() == Some(&name);

                // Check if we already have this device (as output)
                if let Some(existing) = devices.iter_mut().find(|d| d.name == name) {
                    if let Ok(mut configs) = device.supported_input_configs() {
                        if let Some(config) = configs.next() {
                            existing.input_channels = config.channels() as u32;
                        }
                    }
                } else {
                    let mut sample_rates = Vec::new();
                    let mut input_channels = 2;

                    if let Ok(configs) = device.supported_input_configs() {
                        for config in configs {
                            sample_rates.push(config.min_sample_rate().0);
                            sample_rates.push(config.max_sample_rate().0);
                            input_channels = config.channels() as u32;
                        }
                    }

                    sample_rates.sort();
                    sample_rates.dedup();

                    devices.push(AudioDeviceInfo {
                        id: name.clone(),
                        name,
                        is_default,
                        sample_rates,
                        buffer_sizes: vec![64, 128, 256, 512, 1024, 2048],
                        input_channels,
                        output_channels: 0,
                    });
                }
            }
        }
    }

    devices
}

/// Get default audio configuration
pub fn get_default_config() -> AudioConfig {
    let devices = get_audio_devices();

    let output_device = devices
        .iter()
        .find(|d| d.is_default && d.output_channels > 0)
        .map(|d| d.id.clone());

    let input_device = devices
        .iter()
        .find(|d| d.is_default && d.input_channels > 0)
        .map(|d| d.id.clone());

    AudioConfig {
        input_device,
        output_device,
        sample_rate: 48000,
        buffer_size: 256,
        input_channels: 2,
        output_channels: 2,
    }
}

/// Calculate latency in milliseconds
pub fn calculate_latency_ms(sample_rate: u32, buffer_size: u32) -> f64 {
    (buffer_size as f64 / sample_rate as f64) * 1000.0
}

/// Calculate safe buffer size for given latency target
pub fn buffer_size_for_latency(sample_rate: u32, target_latency_ms: f64) -> u32 {
    let samples = (sample_rate as f64 * target_latency_ms / 1000.0) as u32;
    // Round up to nearest power of 2
    samples.next_power_of_two()
}
