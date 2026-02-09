//! Audio device enumeration and selection

use cpal::traits::{DeviceTrait, HostTrait};
use cpal::{Device, Host, SupportedStreamConfigRange};

use crate::{AudioError, AudioResult};

/// Audio device information
#[derive(Debug, Clone)]
pub struct DeviceInfo {
    pub name: String,
    pub is_default: bool,
    pub input_channels: u16,
    pub output_channels: u16,
    pub sample_rates: Vec<u32>,
}

/// Get the audio host (platform-specific backend)
pub fn get_host() -> Host {
    // On macOS, use CoreAudio
    // On Windows, prefer ASIO if available, otherwise WASAPI
    // On Linux, prefer JACK, otherwise use default

    #[cfg(target_os = "macos")]
    {
        cpal::default_host()
    }

    #[cfg(target_os = "windows")]
    {
        // Try ASIO first
        if let Some(host) = cpal::available_hosts()
            .into_iter()
            .find(|h| *h == cpal::HostId::Asio)
        {
            if let Ok(host) = cpal::host_from_id(host) {
                return host;
            }
        }
        cpal::default_host()
    }

    #[cfg(target_os = "linux")]
    {
        // Try JACK first
        if let Some(host) = cpal::available_hosts()
            .into_iter()
            .find(|h| *h == cpal::HostId::Jack)
        {
            if let Ok(host) = cpal::host_from_id(host) {
                return host;
            }
        }
        cpal::default_host()
    }

    #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
    {
        cpal::default_host()
    }
}

/// List available output devices
pub fn list_output_devices() -> AudioResult<Vec<DeviceInfo>> {
    let host = get_host();
    let default_device = host.default_output_device();
    let default_name = default_device.as_ref().and_then(|d| d.name().ok());

    let mut devices = Vec::new();

    for device in host
        .output_devices()
        .map_err(|e| AudioError::BackendError(e.to_string()))?
    {
        if let Ok(name) = device.name() {
            let is_default = default_name.as_ref().map(|d| d == &name).unwrap_or(false);

            let (output_channels, sample_rates) = get_device_info(&device, false);

            devices.push(DeviceInfo {
                name,
                is_default,
                input_channels: 0,
                output_channels,
                sample_rates,
            });
        }
    }

    Ok(devices)
}

/// List available input devices
pub fn list_input_devices() -> AudioResult<Vec<DeviceInfo>> {
    let host = get_host();
    let default_device = host.default_input_device();
    let default_name = default_device.as_ref().and_then(|d| d.name().ok());

    let mut devices = Vec::new();

    for device in host
        .input_devices()
        .map_err(|e| AudioError::BackendError(e.to_string()))?
    {
        if let Ok(name) = device.name() {
            let is_default = default_name.as_ref().map(|d| d == &name).unwrap_or(false);

            let (input_channels, sample_rates) = get_device_info(&device, true);

            devices.push(DeviceInfo {
                name,
                is_default,
                input_channels,
                output_channels: 0,
                sample_rates,
            });
        }
    }

    Ok(devices)
}

/// Get default output device
pub fn get_default_output_device() -> AudioResult<Device> {
    let host = get_host();
    host.default_output_device().ok_or(AudioError::NoDevice)
}

/// Get default input device
pub fn get_default_input_device() -> AudioResult<Device> {
    let host = get_host();
    host.default_input_device().ok_or(AudioError::NoDevice)
}

/// Get output device by name
pub fn get_output_device_by_name(name: &str) -> AudioResult<Device> {
    let host = get_host();

    for device in host
        .output_devices()
        .map_err(|e| AudioError::BackendError(e.to_string()))?
    {
        if let Ok(device_name) = device.name()
            && device_name == name
        {
            return Ok(device);
        }
    }

    Err(AudioError::DeviceNotFound(name.to_string()))
}

/// Get input device by name
pub fn get_input_device_by_name(name: &str) -> AudioResult<Device> {
    let host = get_host();

    for device in host
        .input_devices()
        .map_err(|e| AudioError::BackendError(e.to_string()))?
    {
        if let Ok(device_name) = device.name()
            && device_name == name
        {
            return Ok(device);
        }
    }

    Err(AudioError::DeviceNotFound(name.to_string()))
}

fn get_output_device_info(device: &Device) -> (u16, Vec<u32>) {
    let configs: Vec<SupportedStreamConfigRange> = device
        .supported_output_configs()
        .map(|c| c.collect())
        .unwrap_or_default();

    extract_device_info(&configs)
}

fn get_input_device_info(device: &Device) -> (u16, Vec<u32>) {
    let configs: Vec<SupportedStreamConfigRange> = device
        .supported_input_configs()
        .map(|c| c.collect())
        .unwrap_or_default();

    extract_device_info(&configs)
}

fn extract_device_info(configs: &[SupportedStreamConfigRange]) -> (u16, Vec<u32>) {
    let max_channels = configs.iter().map(|c| c.channels()).max().unwrap_or(0);

    let mut sample_rates: Vec<u32> = configs
        .iter()
        .flat_map(|c| {
            let min = c.min_sample_rate().0;
            let max = c.max_sample_rate().0;

            // Common sample rates
            [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000]
                .into_iter()
                .filter(move |&rate| rate >= min && rate <= max)
        })
        .collect();

    sample_rates.sort_unstable();
    sample_rates.dedup();

    (max_channels, sample_rates)
}

fn get_device_info(device: &Device, is_input: bool) -> (u16, Vec<u32>) {
    if is_input {
        get_input_device_info(device)
    } else {
        get_output_device_info(device)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DEVICE SELECTOR
// ═══════════════════════════════════════════════════════════════════════════════

use parking_lot::RwLock;

/// Device selection state
#[derive(Debug, Clone)]
pub struct DeviceSelection {
    pub input_device: Option<String>,
    pub output_device: Option<String>,
    pub sample_rate: u32,
    pub buffer_size: u32,
}

impl Default for DeviceSelection {
    fn default() -> Self {
        Self {
            input_device: None,
            output_device: None,
            sample_rate: 48000,
            buffer_size: 256,
        }
    }
}

/// Device manager for hot-plugging and device changes
pub struct DeviceManager {
    /// Current selection
    selection: RwLock<DeviceSelection>,
    /// Cached input devices
    input_devices: RwLock<Vec<DeviceInfo>>,
    /// Cached output devices
    output_devices: RwLock<Vec<DeviceInfo>>,
}

impl DeviceManager {
    pub fn new() -> Self {
        let manager = Self {
            selection: RwLock::new(DeviceSelection::default()),
            input_devices: RwLock::new(Vec::new()),
            output_devices: RwLock::new(Vec::new()),
        };

        // Initial scan
        manager.refresh_devices();

        manager
    }

    /// Refresh device lists
    pub fn refresh_devices(&self) {
        if let Ok(inputs) = list_input_devices() {
            *self.input_devices.write() = inputs;
        }

        if let Ok(outputs) = list_output_devices() {
            *self.output_devices.write() = outputs;
        }
    }

    /// Get available input devices
    pub fn input_devices(&self) -> Vec<DeviceInfo> {
        self.input_devices.read().clone()
    }

    /// Get available output devices
    pub fn output_devices(&self) -> Vec<DeviceInfo> {
        self.output_devices.read().clone()
    }

    /// Get current selection
    pub fn selection(&self) -> DeviceSelection {
        self.selection.read().clone()
    }

    /// Set output device by name
    pub fn set_output_device(&self, name: Option<String>) {
        self.selection.write().output_device = name;
    }

    /// Set input device by name
    pub fn set_input_device(&self, name: Option<String>) {
        self.selection.write().input_device = name;
    }

    /// Set sample rate
    pub fn set_sample_rate(&self, rate: u32) {
        self.selection.write().sample_rate = rate;
    }

    /// Set buffer size
    pub fn set_buffer_size(&self, size: u32) {
        self.selection.write().buffer_size = size;
    }

    /// Get default output device name
    pub fn default_output_name(&self) -> Option<String> {
        self.output_devices
            .read()
            .iter()
            .find(|d| d.is_default)
            .map(|d| d.name.clone())
    }

    /// Get default input device name
    pub fn default_input_name(&self) -> Option<String> {
        self.input_devices
            .read()
            .iter()
            .find(|d| d.is_default)
            .map(|d| d.name.clone())
    }

    /// Get supported sample rates for current output device
    pub fn supported_sample_rates(&self) -> Vec<u32> {
        let selection = self.selection.read();
        let outputs = self.output_devices.read();

        if let Some(ref name) = selection.output_device {
            outputs
                .iter()
                .find(|d| &d.name == name)
                .map(|d| d.sample_rates.clone())
                .unwrap_or_default()
        } else {
            // Return default rates
            outputs
                .iter()
                .find(|d| d.is_default)
                .map(|d| d.sample_rates.clone())
                .unwrap_or_else(|| vec![44100, 48000, 96000])
        }
    }

    /// Check if a device is available
    pub fn is_device_available(&self, name: &str, is_input: bool) -> bool {
        let devices = if is_input {
            self.input_devices.read()
        } else {
            self.output_devices.read()
        };

        devices.iter().any(|d| d.name == name)
    }
}

impl Default for DeviceManager {
    fn default() -> Self {
        Self::new()
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HOST INFO
// ═══════════════════════════════════════════════════════════════════════════════

/// Audio backend information
#[derive(Debug, Clone)]
pub struct HostInfo {
    pub name: String,
    pub is_asio: bool,
    pub is_jack: bool,
    pub is_core_audio: bool,
}

/// Get current audio host info
pub fn get_host_info() -> HostInfo {
    let host = get_host();
    let id = host.id();

    HostInfo {
        name: format!("{:?}", id),
        is_asio: cfg!(target_os = "windows") && format!("{:?}", id).contains("Asio"),
        is_jack: cfg!(target_os = "linux") && format!("{:?}", id).contains("Jack"),
        is_core_audio: cfg!(target_os = "macos"),
    }
}

/// List available audio backends
pub fn list_available_hosts() -> Vec<String> {
    cpal::available_hosts()
        .into_iter()
        .map(|h| format!("{:?}", h))
        .collect()
}
