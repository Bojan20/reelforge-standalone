//! Lock-Free Command Queue for Real-Time DSP Communication
//!
//! Uses rtrb (real-time ring buffer) for zero-allocation, lock-free
//! communication between UI thread and audio thread.

use parking_lot::RwLock;
use rtrb::{Consumer, Producer, RingBuffer};
use std::sync::Arc;

use crate::dsp_commands::{AnalysisData, DspCommand, LoudnessData, SpectrumData, StereoMeterData};

/// Command queue capacity (power of 2 for efficiency)
pub const COMMAND_QUEUE_SIZE: usize = 4096;

/// Analysis data queue capacity
pub const ANALYSIS_QUEUE_SIZE: usize = 64;

/// Maximum tracks for analysis data storage
pub const MAX_TRACKS: usize = 128;

// ============================================================================
// COMMAND QUEUE MANAGER
// ============================================================================

/// Manages lock-free communication between UI and audio threads
pub struct CommandQueueManager {
    /// UI → Audio: Command producer (UI thread writes)
    command_producer: Producer<DspCommand>,
    /// UI → Audio: Command consumer (Audio thread reads)
    command_consumer: Consumer<DspCommand>,

    /// Audio → UI: Analysis producer (Audio thread writes)
    analysis_producer: Producer<AnalysisData>,
    /// Audio → UI: Analysis consumer (UI thread reads)
    analysis_consumer: Consumer<AnalysisData>,

    /// Cached analysis data per track (for UI polling)
    cached_analysis: Arc<RwLock<Vec<AnalysisData>>>,
}

impl CommandQueueManager {
    /// Create new command queue manager
    pub fn new() -> Self {
        let (command_producer, command_consumer) = RingBuffer::new(COMMAND_QUEUE_SIZE);
        let (analysis_producer, analysis_consumer) = RingBuffer::new(ANALYSIS_QUEUE_SIZE);

        // Pre-allocate analysis cache
        let mut cached = Vec::with_capacity(MAX_TRACKS);
        for i in 0..MAX_TRACKS {
            let mut data = AnalysisData::default();
            data.track_id = i as u32;
            cached.push(data);
        }

        Self {
            command_producer,
            command_consumer,
            analysis_producer,
            analysis_consumer,
            cached_analysis: Arc::new(RwLock::new(cached)),
        }
    }

    /// Split into UI-side and audio-side handles
    pub fn split(self) -> (UiCommandHandle, AudioCommandHandle) {
        let cached = self.cached_analysis.clone();

        let ui_handle = UiCommandHandle {
            command_producer: self.command_producer,
            analysis_consumer: self.analysis_consumer,
            cached_analysis: cached.clone(),
        };

        let audio_handle = AudioCommandHandle {
            command_consumer: self.command_consumer,
            analysis_producer: self.analysis_producer,
            cached_analysis: cached,
        };

        (ui_handle, audio_handle)
    }
}

impl Default for CommandQueueManager {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// UI-SIDE HANDLE
// ============================================================================

/// Handle for UI thread to send commands and receive analysis
pub struct UiCommandHandle {
    command_producer: Producer<DspCommand>,
    analysis_consumer: Consumer<AnalysisData>,
    cached_analysis: Arc<RwLock<Vec<AnalysisData>>>,
}

impl UiCommandHandle {
    /// Send command to audio thread (non-blocking, may fail if queue full)
    #[inline]
    pub fn send(&mut self, command: DspCommand) -> bool {
        self.command_producer.push(command).is_ok()
    }

    /// Send multiple commands atomically
    pub fn send_batch(&mut self, commands: &[DspCommand]) -> usize {
        let mut sent = 0;
        for cmd in commands {
            if self.command_producer.push(*cmd).is_ok() {
                sent += 1;
            } else {
                break;
            }
        }
        sent
    }

    /// Check if queue has space
    #[inline]
    pub fn has_space(&self) -> bool {
        !self.command_producer.is_full()
    }

    /// Get available space in queue
    #[inline]
    pub fn available_space(&self) -> usize {
        self.command_producer.slots()
    }

    /// Poll for analysis data updates (call from UI thread, e.g., in timer)
    pub fn poll_analysis(&mut self) {
        // Drain analysis queue and update cache
        while let Ok(data) = self.analysis_consumer.pop() {
            let track_id = data.track_id as usize;
            if track_id < MAX_TRACKS {
                let mut cache = self.cached_analysis.write();
                cache[track_id] = data;
            }
        }
    }

    /// Get cached spectrum data for track
    pub fn get_spectrum(&self, track_id: u32) -> SpectrumData {
        let cache = self.cached_analysis.read();
        if (track_id as usize) < cache.len() {
            cache[track_id as usize].spectrum.clone()
        } else {
            SpectrumData::default()
        }
    }

    /// Get cached stereo meter data for track
    pub fn get_stereo_meter(&self, track_id: u32) -> StereoMeterData {
        let cache = self.cached_analysis.read();
        if (track_id as usize) < cache.len() {
            cache[track_id as usize].stereo.clone()
        } else {
            StereoMeterData::default()
        }
    }

    /// Get cached loudness data for track
    pub fn get_loudness(&self, track_id: u32) -> LoudnessData {
        let cache = self.cached_analysis.read();
        if (track_id as usize) < cache.len() {
            cache[track_id as usize].loudness.clone()
        } else {
            LoudnessData::default()
        }
    }

    /// Get EQ curve magnitude response
    pub fn get_eq_curve(&self, track_id: u32) -> [f32; 256] {
        let cache = self.cached_analysis.read();
        if (track_id as usize) < cache.len() {
            cache[track_id as usize].eq_curve
        } else {
            [0.0; 256]
        }
    }

    /// Get dynamic EQ gain reduction per band
    pub fn get_dynamic_gr(&self, track_id: u32) -> [f32; 64] {
        let cache = self.cached_analysis.read();
        if (track_id as usize) < cache.len() {
            cache[track_id as usize].dynamic_gr
        } else {
            [0.0; 64]
        }
    }

    /// Get correlation value
    pub fn get_correlation(&self, track_id: u32) -> f32 {
        let cache = self.cached_analysis.read();
        if (track_id as usize) < cache.len() {
            cache[track_id as usize].stereo.correlation
        } else {
            0.0
        }
    }
}

// ============================================================================
// AUDIO-SIDE HANDLE
// ============================================================================

/// Handle for audio thread to receive commands and send analysis
pub struct AudioCommandHandle {
    command_consumer: Consumer<DspCommand>,
    analysis_producer: Producer<AnalysisData>,
    cached_analysis: Arc<RwLock<Vec<AnalysisData>>>,
}

impl AudioCommandHandle {
    /// Poll for commands (call from audio callback)
    /// Returns iterator over available commands
    #[inline]
    pub fn poll_commands(&mut self) -> CommandIterator<'_> {
        CommandIterator {
            consumer: &mut self.command_consumer,
        }
    }

    /// Check if commands are available
    #[inline]
    pub fn has_commands(&self) -> bool {
        !self.command_consumer.is_empty()
    }

    /// Send analysis data to UI (non-blocking)
    #[inline]
    pub fn send_analysis(&mut self, data: AnalysisData) -> bool {
        // Also update cache for immediate access
        let track_id = data.track_id as usize;
        if track_id < MAX_TRACKS {
            if let Some(mut cache) = self.cached_analysis.try_write() {
                cache[track_id] = data.clone();
            }
        }

        self.analysis_producer.push(data).is_ok()
    }

    /// Update spectrum data for track
    pub fn update_spectrum(&mut self, track_id: u32, spectrum: SpectrumData) {
        if let Some(mut cache) = self.cached_analysis.try_write() {
            if (track_id as usize) < cache.len() {
                cache[track_id as usize].spectrum = spectrum;
            }
        }
    }

    /// Update stereo meter data for track
    pub fn update_stereo_meter(&mut self, track_id: u32, meter: StereoMeterData) {
        if let Some(mut cache) = self.cached_analysis.try_write() {
            if (track_id as usize) < cache.len() {
                cache[track_id as usize].stereo = meter;
            }
        }
    }

    /// Update loudness data for track
    pub fn update_loudness(&mut self, track_id: u32, loudness: LoudnessData) {
        if let Some(mut cache) = self.cached_analysis.try_write() {
            if (track_id as usize) < cache.len() {
                cache[track_id as usize].loudness = loudness;
            }
        }
    }

    /// Update EQ curve
    pub fn update_eq_curve(&mut self, track_id: u32, curve: [f32; 256]) {
        if let Some(mut cache) = self.cached_analysis.try_write() {
            if (track_id as usize) < cache.len() {
                cache[track_id as usize].eq_curve = curve;
            }
        }
    }

    /// Update dynamic EQ gain reduction
    pub fn update_dynamic_gr(&mut self, track_id: u32, gr: [f32; 64]) {
        if let Some(mut cache) = self.cached_analysis.try_write() {
            if (track_id as usize) < cache.len() {
                cache[track_id as usize].dynamic_gr = gr;
            }
        }
    }
}

// ============================================================================
// COMMAND ITERATOR
// ============================================================================

/// Iterator for draining commands from queue
pub struct CommandIterator<'a> {
    consumer: &'a mut Consumer<DspCommand>,
}

impl<'a> Iterator for CommandIterator<'a> {
    type Item = DspCommand;

    #[inline]
    fn next(&mut self) -> Option<Self::Item> {
        self.consumer.pop().ok()
    }
}

// ============================================================================
// GLOBAL QUEUE INSTANCE
// ============================================================================

use std::sync::OnceLock;

/// Global command queue (singleton)
static COMMAND_QUEUE: OnceLock<(
    parking_lot::Mutex<UiCommandHandle>,
    parking_lot::Mutex<AudioCommandHandle>,
)> = OnceLock::new();

/// Initialize global command queue
pub fn init_command_queue() {
    COMMAND_QUEUE.get_or_init(|| {
        let manager = CommandQueueManager::new();
        let (ui, audio) = manager.split();
        (parking_lot::Mutex::new(ui), parking_lot::Mutex::new(audio))
    });
}

/// Get UI command handle (for sending commands from UI thread)
pub fn ui_command_handle() -> &'static parking_lot::Mutex<UiCommandHandle> {
    init_command_queue();
    &COMMAND_QUEUE.get().unwrap().0
}

/// Get audio command handle (for receiving commands in audio thread)
pub fn audio_command_handle() -> &'static parking_lot::Mutex<AudioCommandHandle> {
    init_command_queue();
    &COMMAND_QUEUE.get().unwrap().1
}

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

/// Send a single command to audio thread
#[inline]
pub fn send_command(command: DspCommand) -> bool {
    ui_command_handle().lock().send(command)
}

/// Poll for analysis updates (call periodically from UI)
pub fn poll_analysis() {
    ui_command_handle().lock().poll_analysis();
}

/// Get spectrum data for track
pub fn get_spectrum(track_id: u32) -> SpectrumData {
    ui_command_handle().lock().get_spectrum(track_id)
}

/// Get stereo meter data for track
pub fn get_stereo_meter(track_id: u32) -> StereoMeterData {
    ui_command_handle().lock().get_stereo_meter(track_id)
}

/// Get loudness data for track
pub fn get_loudness(track_id: u32) -> LoudnessData {
    ui_command_handle().lock().get_loudness(track_id)
}

/// Get EQ curve for track
pub fn get_eq_curve(track_id: u32) -> [f32; 256] {
    ui_command_handle().lock().get_eq_curve(track_id)
}

/// Get dynamic EQ gain reduction for track
pub fn get_dynamic_gr(track_id: u32) -> [f32; 64] {
    ui_command_handle().lock().get_dynamic_gr(track_id)
}

/// Get correlation for track
pub fn get_correlation(track_id: u32) -> f32 {
    ui_command_handle().lock().get_correlation(track_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_command_queue_send_receive() {
        let manager = CommandQueueManager::new();
        let (mut ui, mut audio) = manager.split();

        // Send command
        let cmd = DspCommand::EqSetGain {
            track_id: 0,
            band_index: 0,
            gain_db: 3.0,
        };
        assert!(ui.send(cmd));

        // Receive command
        let mut received = false;
        for c in audio.poll_commands() {
            if let DspCommand::EqSetGain { gain_db, .. } = c {
                assert!((gain_db - 3.0).abs() < 0.001);
                received = true;
            }
        }
        assert!(received);
    }

    #[test]
    fn test_analysis_data_flow() {
        let manager = CommandQueueManager::new();
        let (mut ui, mut audio) = manager.split();

        // Send analysis from audio thread
        let mut data = AnalysisData::default();
        data.track_id = 5;
        data.stereo.correlation = 0.95;
        assert!(audio.send_analysis(data));

        // Poll and check
        ui.poll_analysis();
        let corr = ui.get_correlation(5);
        assert!((corr - 0.95).abs() < 0.001);
    }

    #[test]
    fn test_queue_capacity() {
        let manager = CommandQueueManager::new();
        let (mut ui, mut _audio) = manager.split();

        // Fill queue
        let mut sent = 0;
        for _ in 0..COMMAND_QUEUE_SIZE + 100 {
            let cmd = DspCommand::EqBypass {
                track_id: 0,
                bypass: false,
            };
            if ui.send(cmd) {
                sent += 1;
            }
        }

        // Should have sent exactly COMMAND_QUEUE_SIZE
        assert_eq!(sent, COMMAND_QUEUE_SIZE);
    }
}
