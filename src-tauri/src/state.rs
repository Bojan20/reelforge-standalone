//! Application state management
//!
//! Thread-safe state for audio engine and UI communication.
//! Uses separate audio thread to avoid Send+Sync issues with cpal::Stream.

use std::sync::Arc;
use std::sync::mpsc;
use std::thread::{self, JoinHandle};

use parking_lot::{Mutex, RwLock};
use rtrb::{Consumer, Producer, RingBuffer};

use rf_core::{BufferSize, SampleRate};
use rf_engine::{MixerCommand, MeterBridge};

/// Commands sent to audio thread
#[derive(Debug)]
pub enum AudioThreadCommand {
    /// Initialize audio engine with given settings
    Init(SampleRate, BufferSize),
    /// Start audio playback
    Start,
    /// Stop audio playback
    Stop,
    /// Shutdown the audio thread
    Shutdown,
    /// Forward mixer command
    Mixer(MixerCommand),
}

/// Responses from audio thread
#[derive(Debug)]
pub enum AudioThreadResponse {
    /// Init succeeded
    InitOk,
    /// Init failed with error message
    InitError(String),
    /// Started successfully
    Started,
    /// Stopped successfully
    Stopped,
    /// Start/stop failed
    Error(String),
}

/// Audio engine handle - stores only Send+Sync types
pub struct AudioEngineHandle {
    /// Command sender to audio thread
    pub command_tx: Producer<AudioThreadCommand>,
    /// Response receiver from audio thread
    pub response_rx: Consumer<AudioThreadResponse>,
    /// Meter bridge receiver (receives Arc<MeterBridge> after init)
    pub meter_rx: mpsc::Receiver<Arc<MeterBridge>>,
    /// Audio thread handle
    pub thread_handle: Option<JoinHandle<()>>,
    /// Is audio currently running
    pub running: bool,
    /// Current sample rate
    pub sample_rate: SampleRate,
    /// Current buffer size
    pub buffer_size: BufferSize,
}

/// Transport state
#[derive(Debug, Clone, Default)]
pub struct TransportState {
    pub is_playing: bool,
    pub is_recording: bool,
    pub is_looping: bool,
    pub position_samples: u64,
    pub tempo: f64,
    pub time_signature: (u8, u8),
}

impl TransportState {
    pub fn new() -> Self {
        Self {
            is_playing: false,
            is_recording: false,
            is_looping: false,
            position_samples: 0,
            tempo: 120.0,
            time_signature: (4, 4),
        }
    }
}

/// Main application state (managed by Tauri)
pub struct AppState {
    pub audio: Mutex<AudioEngineHandle>,
    pub transport: RwLock<TransportState>,
    /// Meter bridge - shared with audio thread (set after init)
    pub meters: RwLock<Option<Arc<MeterBridge>>>,
}

impl AppState {
    pub fn new() -> Self {
        // Create command/response channels
        let (cmd_tx, cmd_rx) = RingBuffer::<AudioThreadCommand>::new(256);
        let (resp_tx, resp_rx) = RingBuffer::<AudioThreadResponse>::new(64);

        // Channel for receiving MeterBridge from audio thread
        let (meter_tx, meter_rx) = mpsc::channel::<Arc<MeterBridge>>();

        // Spawn audio thread
        let thread_handle = thread::Builder::new()
            .name("audio-engine".into())
            .spawn(move || {
                audio_thread_main(cmd_rx, resp_tx, meter_tx);
            })
            .expect("Failed to spawn audio thread");

        Self {
            audio: Mutex::new(AudioEngineHandle {
                command_tx: cmd_tx,
                response_rx: resp_rx,
                meter_rx,
                thread_handle: Some(thread_handle),
                running: false,
                sample_rate: SampleRate::Hz48000,
                buffer_size: BufferSize::Samples256,
            }),
            transport: RwLock::new(TransportState::new()),
            meters: RwLock::new(None),
        }
    }

    /// Initialize audio engine
    pub fn init_audio(&self, sample_rate: SampleRate, buffer_size: BufferSize) -> Result<(), String> {
        let mut audio = self.audio.lock();

        // Send init command
        audio.command_tx
            .push(AudioThreadCommand::Init(sample_rate, buffer_size))
            .map_err(|_| "Audio thread not responding")?;

        // Wait for response (with timeout)
        let start = std::time::Instant::now();
        let timeout = std::time::Duration::from_secs(5);

        loop {
            if let Ok(response) = audio.response_rx.pop() {
                match response {
                    AudioThreadResponse::InitOk => {
                        audio.sample_rate = sample_rate;
                        audio.buffer_size = buffer_size;
                        audio.running = true;
                        log::info!("Audio engine initialized: {}Hz, {} samples",
                            sample_rate.as_u32(), buffer_size.as_usize());

                        // Receive MeterBridge from audio thread
                        if let Ok(meter_bridge) = audio.meter_rx.recv_timeout(std::time::Duration::from_secs(1)) {
                            *self.meters.write() = Some(meter_bridge);
                            log::info!("MeterBridge received from audio thread");
                        }

                        return Ok(());
                    }
                    AudioThreadResponse::InitError(e) => {
                        log::error!("Audio init failed: {}", e);
                        return Err(e);
                    }
                    _ => {}
                }
            }

            if start.elapsed() > timeout {
                return Err("Audio init timeout".into());
            }

            std::thread::sleep(std::time::Duration::from_millis(10));
        }
    }

    /// Start audio playback
    pub fn start_audio(&self) -> Result<(), String> {
        let mut audio = self.audio.lock();

        audio.command_tx
            .push(AudioThreadCommand::Start)
            .map_err(|_| "Audio thread not responding")?;

        // Wait for response
        let start = std::time::Instant::now();
        let timeout = std::time::Duration::from_secs(2);

        loop {
            if let Ok(response) = audio.response_rx.pop() {
                match response {
                    AudioThreadResponse::Started => {
                        audio.running = true;
                        return Ok(());
                    }
                    AudioThreadResponse::Error(e) => return Err(e),
                    _ => {}
                }
            }

            if start.elapsed() > timeout {
                return Err("Start audio timeout".into());
            }

            std::thread::sleep(std::time::Duration::from_millis(10));
        }
    }

    /// Stop audio playback
    pub fn stop_audio(&self) -> Result<(), String> {
        let mut audio = self.audio.lock();

        audio.command_tx
            .push(AudioThreadCommand::Stop)
            .map_err(|_| "Audio thread not responding")?;

        // Wait for response
        let start = std::time::Instant::now();
        let timeout = std::time::Duration::from_secs(2);

        loop {
            if let Ok(response) = audio.response_rx.pop() {
                match response {
                    AudioThreadResponse::Stopped => {
                        audio.running = false;
                        return Ok(());
                    }
                    AudioThreadResponse::Error(e) => return Err(e),
                    _ => {}
                }
            }

            if start.elapsed() > timeout {
                return Err("Stop audio timeout".into());
            }

            std::thread::sleep(std::time::Duration::from_millis(10));
        }
    }

    /// Send mixer command (fire and forget)
    pub fn send_mixer_command(&self, cmd: MixerCommand) {
        let mut audio = self.audio.lock();
        let _ = audio.command_tx.push(AudioThreadCommand::Mixer(cmd));
    }

    /// Check if audio is running
    pub fn is_audio_running(&self) -> bool {
        self.audio.lock().running
    }

    /// Get current sample rate
    pub fn sample_rate(&self) -> SampleRate {
        self.audio.lock().sample_rate
    }

    /// Get current buffer size
    pub fn buffer_size(&self) -> BufferSize {
        self.audio.lock().buffer_size
    }

    /// Get meter bridge (if initialized)
    pub fn meter_bridge(&self) -> Option<Arc<MeterBridge>> {
        self.meters.read().clone()
    }
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for AppState {
    fn drop(&mut self) {
        // Signal audio thread to shutdown
        let mut audio = self.audio.lock();
        let _ = audio.command_tx.push(AudioThreadCommand::Shutdown);

        // Wait for thread to finish
        if let Some(handle) = audio.thread_handle.take() {
            let _ = handle.join();
        }
    }
}

/// Audio thread main loop
fn audio_thread_main(
    mut cmd_rx: Consumer<AudioThreadCommand>,
    mut resp_tx: Producer<AudioThreadResponse>,
    meter_tx: mpsc::Sender<Arc<MeterBridge>>,
) {
    use rf_engine::RealtimeEngine;

    log::info!("Audio thread started");

    let mut engine: Option<RealtimeEngine> = None;

    loop {
        // Process commands
        while let Ok(cmd) = cmd_rx.pop() {
            match cmd {
                AudioThreadCommand::Init(sample_rate, buffer_size) => {
                    // Stop existing engine
                    if let Some(ref e) = engine {
                        let _ = e.stop();
                    }
                    engine = None;

                    // Create new engine
                    match RealtimeEngine::new(sample_rate, buffer_size) {
                        Ok(e) => {
                            log::info!("RealtimeEngine created: {}Hz, {} samples",
                                e.sample_rate(), e.block_size());

                            // Send MeterBridge to main thread
                            let meters = e.meters();
                            let _ = meter_tx.send(meters);

                            engine = Some(e);
                            let _ = resp_tx.push(AudioThreadResponse::InitOk);
                        }
                        Err(e) => {
                            log::error!("RealtimeEngine creation failed: {}", e);
                            let _ = resp_tx.push(AudioThreadResponse::InitError(e.to_string()));
                        }
                    }
                }

                AudioThreadCommand::Start => {
                    if let Some(ref e) = engine {
                        match e.start() {
                            Ok(()) => {
                                let _ = resp_tx.push(AudioThreadResponse::Started);
                            }
                            Err(e) => {
                                let _ = resp_tx.push(AudioThreadResponse::Error(e.to_string()));
                            }
                        }
                    } else {
                        let _ = resp_tx.push(AudioThreadResponse::Error("Engine not initialized".into()));
                    }
                }

                AudioThreadCommand::Stop => {
                    if let Some(ref e) = engine {
                        match e.stop() {
                            Ok(()) => {
                                let _ = resp_tx.push(AudioThreadResponse::Stopped);
                            }
                            Err(e) => {
                                let _ = resp_tx.push(AudioThreadResponse::Error(e.to_string()));
                            }
                        }
                    } else {
                        let _ = resp_tx.push(AudioThreadResponse::Stopped);
                    }
                }

                AudioThreadCommand::Mixer(mixer_cmd) => {
                    if let Some(ref mut e) = engine {
                        // Forward to mixer via MixerHandle
                        let handle = e.mixer_handle_mut();
                        match mixer_cmd {
                            MixerCommand::SetChannelVolume(id, db) => handle.set_channel_volume(id, db),
                            MixerCommand::SetChannelPan(id, pan) => handle.set_channel_pan(id, pan),
                            MixerCommand::SetChannelMute(id, mute) => handle.set_channel_mute(id, mute),
                            MixerCommand::SetChannelSolo(id, solo) => handle.set_channel_solo(id, solo),
                            MixerCommand::SetMasterVolume(db) => handle.set_master_volume(db),
                            MixerCommand::SetMasterLimiterEnabled(enabled) => {
                                handle.set_master_limiter(enabled, -0.3);
                            }
                            MixerCommand::SetMasterLimiterCeiling(ceiling) => {
                                handle.set_master_limiter(true, ceiling);
                            }
                            // Other commands can be added as needed
                            _ => {}
                        }
                    }
                }

                AudioThreadCommand::Shutdown => {
                    log::info!("Audio thread shutting down");
                    if let Some(ref e) = engine {
                        let _ = e.stop();
                    }
                    return;
                }
            }
        }

        // Sleep briefly to avoid busy-waiting
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
}
