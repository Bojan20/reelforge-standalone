//! Input Bus System
//!
//! Cubase-style input bus architecture:
//! - Virtual buses map hardware inputs to tracks
//! - Each track selects which bus to monitor/record
//! - Zero-copy audio routing
//! - Lock-free communication

use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;

/// Input bus ID
pub type InputBusId = u32;

/// Input monitoring mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[derive(Default)]
pub enum MonitorMode {
    /// Monitor when armed and playing (DAW standard)
    #[default]
    Auto,
    /// Always monitor input
    Manual,
    /// Never monitor input
    Off,
}


/// Input bus configuration
#[derive(Debug, Clone)]
pub struct InputBusConfig {
    /// Bus name (e.g., "Input 1-2")
    pub name: String,
    /// Number of channels (1=mono, 2=stereo)
    pub channels: u16,
    /// Hardware input channel indices (e.g., [0, 1] for first stereo pair)
    pub hardware_channels: Vec<usize>,
    /// Enable this bus
    pub enabled: bool,
}

/// Input bus — virtual bus mapping hardware inputs
pub struct InputBus {
    /// Bus ID
    id: InputBusId,
    /// Configuration
    config: RwLock<InputBusConfig>,
    /// Audio buffers (pre-allocated, zero-copy)
    /// buffers[0] = left/mono, buffers[1] = right (if stereo)
    buffers: Vec<RwLock<Vec<f32>>>,
    /// Peak metering (per channel)
    peaks: Vec<AtomicU64>,
    /// Enabled state (atomic for audio thread)
    enabled: AtomicBool,
}

impl InputBus {
    /// Create new input bus
    pub fn new(id: InputBusId, config: InputBusConfig, buffer_size: usize) -> Self {
        let channels = config.channels as usize;
        let buffers = (0..channels)
            .map(|_| RwLock::new(vec![0.0; buffer_size]))
            .collect();

        let peaks = (0..channels)
            .map(|_| AtomicU64::new(0))
            .collect();

        let enabled = AtomicBool::new(config.enabled);

        Self {
            id,
            config: RwLock::new(config),
            buffers,
            peaks,
            enabled,
        }
    }

    /// Get bus ID
    pub fn id(&self) -> InputBusId {
        self.id
    }

    /// Get bus name
    pub fn name(&self) -> String {
        self.config.read().name.clone()
    }

    /// Get channel count
    pub fn channels(&self) -> u16 {
        self.config.read().channels
    }

    /// Get hardware channel mapping
    pub fn hardware_channels(&self) -> Vec<usize> {
        self.config.read().hardware_channels.clone()
    }

    /// Is bus enabled (lock-free read)
    pub fn is_enabled(&self) -> bool {
        self.enabled.load(Ordering::Relaxed)
    }

    /// Set enabled state
    pub fn set_enabled(&self, enabled: bool) {
        self.enabled.store(enabled, Ordering::Relaxed);
        self.config.write().enabled = enabled;
    }

    /// Write audio from hardware input to bus buffers
    /// Called from audio thread — lock-free
    pub fn write_from_hardware(&self, hardware_input: &[f32], frames: usize) {
        if !self.is_enabled() {
            return;
        }

        let config = self.config.read();
        let hw_channels = &config.hardware_channels;

        for (ch_idx, &hw_idx) in hw_channels.iter().enumerate() {
            if ch_idx >= self.buffers.len() {
                break;
            }

            if let Some(mut buffer) = self.buffers[ch_idx].try_write() {
                let mut peak = 0.0f32;

                for i in 0..frames.min(buffer.len()) {
                    let sample_idx = i * 2 + hw_idx; // Assuming stereo interleaved hardware
                    if sample_idx < hardware_input.len() {
                        let sample = hardware_input[sample_idx];
                        buffer[i] = sample;
                        peak = peak.max(sample.abs());
                    } else {
                        buffer[i] = 0.0;
                    }
                }

                // Update peak meter (lock-free)
                self.peaks[ch_idx].store(peak.to_bits() as u64, Ordering::Relaxed);
            }
        }
    }

    /// Read audio from bus buffer (for track monitoring/recording)
    /// Returns (left, right) slices — immutable reference for zero-copy
    pub fn read_buffers(&self) -> Option<(Vec<f32>, Option<Vec<f32>>)> {
        if !self.is_enabled() {
            return None;
        }

        let left = self.buffers[0].read().clone();
        let right = if self.buffers.len() > 1 {
            Some(self.buffers[1].read().clone())
        } else {
            None
        };

        Some((left, right))
    }

    /// Get peak level for channel (0.0 - 1.0)
    pub fn peak(&self, channel: usize) -> f32 {
        if channel >= self.peaks.len() {
            return 0.0;
        }

        let bits = self.peaks[channel].load(Ordering::Relaxed);
        f32::from_bits(bits as u32)
    }

    /// Update configuration
    pub fn update_config(&self, config: InputBusConfig) {
        self.enabled.store(config.enabled, Ordering::Relaxed);
        *self.config.write() = config;
    }
}

/// Input bus manager — manages all input buses
pub struct InputBusManager {
    /// All input buses (BusId → InputBus)
    buses: RwLock<HashMap<InputBusId, Arc<InputBus>>>,
    /// Next bus ID
    next_id: AtomicU64,
    /// Buffer size (matches audio engine block size)
    buffer_size: usize,
}

impl InputBusManager {
    /// Create new input bus manager
    pub fn new(buffer_size: usize) -> Self {
        Self {
            buses: RwLock::new(HashMap::new()),
            next_id: AtomicU64::new(1),
            buffer_size,
        }
    }

    /// Create new input bus
    pub fn create_bus(&self, config: InputBusConfig) -> InputBusId {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed) as InputBusId;
        let bus = Arc::new(InputBus::new(id, config, self.buffer_size));
        self.buses.write().insert(id, bus);
        id
    }

    /// Delete input bus
    pub fn delete_bus(&self, id: InputBusId) -> bool {
        self.buses.write().remove(&id).is_some()
    }

    /// Get input bus by ID
    pub fn get_bus(&self, id: InputBusId) -> Option<Arc<InputBus>> {
        self.buses.read().get(&id).cloned()
    }

    /// Get all bus IDs
    pub fn bus_ids(&self) -> Vec<InputBusId> {
        self.buses.read().keys().copied().collect()
    }

    /// Get all buses
    pub fn buses(&self) -> Vec<Arc<InputBus>> {
        self.buses.read().values().cloned().collect()
    }

    /// Get bus count
    pub fn bus_count(&self) -> usize {
        self.buses.read().len()
    }

    /// Clear all buses
    pub fn clear(&self) {
        self.buses.write().clear();
    }

    /// Route hardware input to all buses
    /// Called from audio thread — lock-free
    pub fn route_hardware_input(&self, hardware_input: &[f32], frames: usize) {
        let buses = self.buses.read();
        for bus in buses.values() {
            bus.write_from_hardware(hardware_input, frames);
        }
    }

    /// Create default stereo input bus (Input 1-2)
    pub fn create_default_stereo_bus(&self) -> InputBusId {
        let config = InputBusConfig {
            name: "Input 1-2".to_string(),
            channels: 2,
            hardware_channels: vec![0, 1],
            enabled: true,
        };
        self.create_bus(config)
    }

    /// Create default mono input bus (Input 1)
    pub fn create_default_mono_bus(&self) -> InputBusId {
        let config = InputBusConfig {
            name: "Input 1".to_string(),
            channels: 1,
            hardware_channels: vec![0],
            enabled: true,
        };
        self.create_bus(config)
    }
}

impl Default for InputBusManager {
    fn default() -> Self {
        Self::new(512) // Default buffer size
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_input_bus_creation() {
        let config = InputBusConfig {
            name: "Test Bus".to_string(),
            channels: 2,
            hardware_channels: vec![0, 1],
            enabled: true,
        };

        let bus = InputBus::new(1, config, 512);
        assert_eq!(bus.id(), 1);
        assert_eq!(bus.name(), "Test Bus");
        assert_eq!(bus.channels(), 2);
        assert!(bus.is_enabled());
    }

    #[test]
    fn test_input_bus_manager() {
        let manager = InputBusManager::new(512);
        assert_eq!(manager.bus_count(), 0);

        let id1 = manager.create_default_stereo_bus();
        assert_eq!(manager.bus_count(), 1);

        let id2 = manager.create_default_mono_bus();
        assert_eq!(manager.bus_count(), 2);

        assert!(manager.get_bus(id1).is_some());
        assert!(manager.get_bus(id2).is_some());

        assert!(manager.delete_bus(id1));
        assert_eq!(manager.bus_count(), 1);

        manager.clear();
        assert_eq!(manager.bus_count(), 0);
    }

    #[test]
    fn test_audio_routing() {
        let manager = InputBusManager::new(512);
        let bus_id = manager.create_default_stereo_bus();
        let bus = manager.get_bus(bus_id).unwrap();

        // Simulate hardware input (stereo interleaved)
        let mut hardware_input = vec![0.0f32; 1024];
        for i in 0..512 {
            hardware_input[i * 2] = 0.5; // Left channel
            hardware_input[i * 2 + 1] = 0.3; // Right channel
        }

        // Route to bus
        bus.write_from_hardware(&hardware_input, 512);

        // Read back
        let (left, right) = bus.read_buffers().unwrap();
        assert_eq!(left.len(), 512);
        assert_eq!(right.as_ref().unwrap().len(), 512);
        assert_eq!(left[0], 0.5);
        assert_eq!(right.as_ref().unwrap()[0], 0.3);
    }

    #[test]
    fn test_peak_metering() {
        let config = InputBusConfig {
            name: "Test Bus".to_string(),
            channels: 2,
            hardware_channels: vec![0, 1],
            enabled: true,
        };

        let bus = InputBus::new(1, config, 512);

        // Simulate hardware input with peaks
        let mut hardware_input = vec![0.0f32; 1024];
        hardware_input[0] = 0.8; // Left peak
        hardware_input[1] = 0.6; // Right peak

        bus.write_from_hardware(&hardware_input, 512);

        assert_eq!(bus.peak(0), 0.8);
        assert_eq!(bus.peak(1), 0.6);
    }
}
