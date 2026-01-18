//! Plugin Sandbox
//!
//! Process isolation for VST3/CLAP/AU plugins to prevent crashes
//! from affecting the main DAW process.
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                     Main DAW Process                             │
//! │                                                                  │
//! │  ┌──────────────────────────────────────────────────────────┐   │
//! │  │                   SandboxHost                              │   │
//! │  │                                                            │   │
//! │  │  - Spawns child processes                                  │   │
//! │  │  - Manages IPC channels                                    │   │
//! │  │  - Handles crash recovery                                  │   │
//! │  │  - Audio buffer bridging                                   │   │
//! │  └──────────────────────────────────────────────────────────┘   │
//! │           │                    │                                 │
//! │           ▼                    ▼                                 │
//! └───────────┬────────────────────┬─────────────────────────────────┘
//!             │                    │
//!   ┌─────────┴───────┐  ┌─────────┴───────┐
//!   │ Plugin Process 1 │  │ Plugin Process 2 │
//!   │                  │  │                  │
//!   │  ┌────────────┐  │  │  ┌────────────┐  │
//!   │  │ VST3 Plugin│  │  │  │CLAP Plugin │  │
//!   │  └────────────┘  │  │  └────────────┘  │
//!   │                  │  │                  │
//!   │  Shared Memory   │  │  Shared Memory   │
//!   │  Audio Buffers   │  │  Audio Buffers   │
//!   └──────────────────┘  └──────────────────┘
//! ```

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, Instant};

use crossbeam_channel::{Receiver, Sender, bounded};
use parking_lot::{Mutex, RwLock};
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{AudioBuffer, ParameterInfo, PluginError, ProcessContext};

// ============ Error Types ============

#[derive(Error, Debug)]
pub enum SandboxError {
    #[error("Failed to spawn sandbox process: {0}")]
    SpawnFailed(String),

    #[error("IPC communication failed: {0}")]
    IpcError(String),

    #[error("Plugin crashed")]
    PluginCrashed,

    #[error("Timeout waiting for response")]
    Timeout,

    #[error("Sandbox not initialized")]
    NotInitialized,

    #[error("Plugin error: {0}")]
    PluginError(#[from] PluginError),
}

pub type SandboxResult<T> = Result<T, SandboxError>;

/// Type alias for crash callback
pub type CrashCallback = Box<dyn Fn(&str) + Send + Sync>;

// ============ IPC Messages ============

/// Messages sent to sandbox process
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SandboxCommand {
    /// Load plugin
    Load {
        plugin_path: String,
        plugin_type: String,
    },
    /// Initialize with context
    Initialize { sample_rate: f64, block_size: usize },
    /// Activate processing
    Activate,
    /// Deactivate processing
    Deactivate,
    /// Process audio (data in shared memory)
    Process { buffer_id: u64, num_samples: usize },
    /// Get parameter
    GetParameter { id: u32 },
    /// Set parameter
    SetParameter { id: u32, value: f64 },
    /// Get all parameters
    GetAllParameters,
    /// Get state
    GetState,
    /// Set state
    SetState { data: Vec<u8> },
    /// Ping (health check)
    Ping,
    /// Shutdown
    Shutdown,
}

/// Responses from sandbox process
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SandboxResponse {
    /// Success with optional data
    Ok { data: Option<Vec<u8>> },
    /// Plugin loaded
    Loaded { latency: usize },
    /// Parameter value
    ParameterValue { id: u32, value: f64 },
    /// All parameters
    Parameters { params: Vec<ParameterInfoSer> },
    /// Processing complete
    ProcessComplete { output_buffer_id: u64 },
    /// Pong response
    Pong,
    /// Error
    Error { message: String },
}

/// Serializable parameter info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParameterInfoSer {
    pub id: u32,
    pub name: String,
    pub unit: String,
    pub min: f64,
    pub max: f64,
    pub default: f64,
    pub normalized: f64,
    pub steps: u32,
    pub automatable: bool,
}

impl From<ParameterInfo> for ParameterInfoSer {
    fn from(p: ParameterInfo) -> Self {
        Self {
            id: p.id,
            name: p.name,
            unit: p.unit,
            min: p.min,
            max: p.max,
            default: p.default,
            normalized: p.normalized,
            steps: p.steps,
            automatable: p.automatable,
        }
    }
}

impl From<ParameterInfoSer> for ParameterInfo {
    fn from(p: ParameterInfoSer) -> Self {
        Self {
            id: p.id,
            name: p.name,
            unit: p.unit,
            min: p.min,
            max: p.max,
            default: p.default,
            normalized: p.normalized,
            steps: p.steps,
            automatable: p.automatable,
            read_only: false,
        }
    }
}

// ============ Sandbox Configuration ============

/// Configuration for sandbox behavior
#[derive(Debug, Clone)]
pub struct SandboxConfig {
    /// Timeout for IPC operations
    pub ipc_timeout: Duration,
    /// Auto-restart on crash
    pub auto_restart: bool,
    /// Max restart attempts
    pub max_restarts: u32,
    /// Process priority (lower = higher priority)
    pub priority: i32,
    /// Memory limit (bytes, 0 = unlimited)
    pub memory_limit: usize,
    /// CPU limit (percentage, 0 = unlimited)
    pub cpu_limit: u32,
}

impl Default for SandboxConfig {
    fn default() -> Self {
        Self {
            ipc_timeout: Duration::from_millis(1000),
            auto_restart: true,
            max_restarts: 3,
            priority: 0,
            memory_limit: 0,
            cpu_limit: 0,
        }
    }
}

// ============ Shared Memory Buffer ============

/// Shared memory buffer for zero-copy audio transfer
#[derive(Debug)]
pub struct SharedAudioBuffer {
    /// Buffer ID
    pub id: u64,
    /// Number of channels
    pub channels: usize,
    /// Samples per channel
    pub samples: usize,
    /// Actual data (would be mmap in production)
    data: Vec<Vec<f32>>,
}

impl SharedAudioBuffer {
    pub fn new(id: u64, channels: usize, samples: usize) -> Self {
        Self {
            id,
            channels,
            samples,
            data: (0..channels).map(|_| vec![0.0; samples]).collect(),
        }
    }

    /// Copy from AudioBuffer
    pub fn copy_from(&mut self, buffer: &AudioBuffer) {
        for (i, channel) in self.data.iter_mut().enumerate() {
            if let Some(src) = buffer.channel(i) {
                let len = src.len().min(channel.len());
                channel[..len].copy_from_slice(&src[..len]);
            }
        }
    }

    /// Copy to AudioBuffer
    pub fn copy_to(&self, buffer: &mut AudioBuffer) {
        for (i, channel) in self.data.iter().enumerate() {
            if let Some(dst) = buffer.channel_mut(i) {
                let len = channel.len().min(dst.len());
                dst[..len].copy_from_slice(&channel[..len]);
            }
        }
    }
}

// ============ Sandbox Process ============

/// Handle to a sandbox child process
struct SandboxProcess {
    /// Child process handle
    child: Child,
    /// Process ID
    pid: u32,
    /// Command sender
    cmd_tx: Sender<SandboxCommand>,
    /// Response receiver
    resp_rx: Receiver<SandboxResponse>,
    /// Last heartbeat
    last_heartbeat: Instant,
    /// Restart count
    restart_count: u32,
    /// Is alive
    alive: bool,
}

impl SandboxProcess {
    /// Check if process is alive
    fn is_alive(&mut self) -> bool {
        if !self.alive {
            return false;
        }

        match self.child.try_wait() {
            Ok(Some(_status)) => {
                self.alive = false;
                false
            }
            Ok(None) => true,
            Err(_) => {
                self.alive = false;
                false
            }
        }
    }

    /// Kill the process
    fn kill(&mut self) {
        let _ = self.child.kill();
        self.alive = false;
    }
}

// ============ Sandboxed Plugin ============

/// A plugin running in a sandboxed subprocess
pub struct SandboxedPlugin {
    /// Sandbox config
    config: SandboxConfig,
    /// Plugin path
    plugin_path: PathBuf,
    /// Plugin type (vst3, clap, au)
    plugin_type: String,
    /// Sandbox process
    process: Option<SandboxProcess>,
    /// Shared audio buffers
    input_buffer: SharedAudioBuffer,
    output_buffer: SharedAudioBuffer,
    /// Cached parameters
    parameters: Vec<ParameterInfo>,
    /// Latency in samples
    latency: usize,
    /// Processing context
    context: ProcessContext,
    /// Is initialized
    initialized: bool,
    /// Is active
    active: bool,
    /// Buffer ID counter
    buffer_id: u64,
}

impl SandboxedPlugin {
    /// Create a new sandboxed plugin
    pub fn new(plugin_path: impl AsRef<Path>, plugin_type: &str, config: SandboxConfig) -> Self {
        Self {
            config,
            plugin_path: plugin_path.as_ref().to_path_buf(),
            plugin_type: plugin_type.to_string(),
            process: None,
            input_buffer: SharedAudioBuffer::new(0, 2, 512),
            output_buffer: SharedAudioBuffer::new(1, 2, 512),
            parameters: Vec::new(),
            latency: 0,
            context: ProcessContext::default(),
            initialized: false,
            active: false,
            buffer_id: 0,
        }
    }

    /// Spawn the sandbox process
    fn spawn_process(&mut self) -> SandboxResult<()> {
        // In a real implementation, this would spawn a separate executable
        // that loads the plugin and communicates via IPC
        //
        // For this implementation, we simulate the behavior

        let (cmd_tx, _cmd_rx) = bounded(256);
        let (_resp_tx, resp_rx) = bounded(256);

        // Simulate spawning a process
        // In production: spawn actual child process with plugin host binary
        let child = Command::new("true") // Placeholder
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|e| SandboxError::SpawnFailed(e.to_string()))?;

        let pid = child.id();

        self.process = Some(SandboxProcess {
            child,
            pid,
            cmd_tx,
            resp_rx,
            last_heartbeat: Instant::now(),
            restart_count: 0,
            alive: true,
        });

        Ok(())
    }

    /// Send command and wait for response
    fn send_command(&mut self, cmd: SandboxCommand) -> SandboxResult<SandboxResponse> {
        let process = self.process.as_mut().ok_or(SandboxError::NotInitialized)?;

        if !process.is_alive() {
            return Err(SandboxError::PluginCrashed);
        }

        // Send command
        process
            .cmd_tx
            .send(cmd.clone())
            .map_err(|e| SandboxError::IpcError(e.to_string()))?;

        // Wait for response with timeout
        match process.resp_rx.recv_timeout(self.config.ipc_timeout) {
            Ok(resp) => {
                process.last_heartbeat = Instant::now();
                Ok(resp)
            }
            Err(_) => {
                // Check if process crashed
                if !process.is_alive() {
                    Err(SandboxError::PluginCrashed)
                } else {
                    Err(SandboxError::Timeout)
                }
            }
        }
    }

    /// Initialize the plugin
    pub fn initialize(&mut self, context: &ProcessContext) -> SandboxResult<()> {
        self.context = context.clone();

        // Spawn process if needed
        if self.process.is_none() {
            self.spawn_process()?;
        }

        // Send load command
        let resp = self.send_command(SandboxCommand::Load {
            plugin_path: self.plugin_path.to_string_lossy().to_string(),
            plugin_type: self.plugin_type.clone(),
        })?;

        match resp {
            SandboxResponse::Loaded { latency } => {
                self.latency = latency;
            }
            SandboxResponse::Error { message } => {
                return Err(SandboxError::PluginError(PluginError::LoadFailed(message)));
            }
            _ => {}
        }

        // Send initialize command
        let resp = self.send_command(SandboxCommand::Initialize {
            sample_rate: context.sample_rate,
            block_size: context.max_block_size,
        })?;

        if let SandboxResponse::Error { message } = resp {
            return Err(SandboxError::PluginError(PluginError::InitFailed(message)));
        }

        // Get parameters
        let resp = self.send_command(SandboxCommand::GetAllParameters)?;
        if let SandboxResponse::Parameters { params } = resp {
            self.parameters = params.into_iter().map(Into::into).collect();
        }

        // Resize buffers
        self.input_buffer = SharedAudioBuffer::new(0, 2, context.max_block_size);
        self.output_buffer = SharedAudioBuffer::new(1, 2, context.max_block_size);

        self.initialized = true;
        Ok(())
    }

    /// Activate processing
    pub fn activate(&mut self) -> SandboxResult<()> {
        if !self.initialized {
            return Err(SandboxError::NotInitialized);
        }

        let resp = self.send_command(SandboxCommand::Activate)?;
        if let SandboxResponse::Error { message } = resp {
            return Err(SandboxError::PluginError(PluginError::InitFailed(message)));
        }

        self.active = true;
        Ok(())
    }

    /// Deactivate processing
    pub fn deactivate(&mut self) -> SandboxResult<()> {
        if self.active {
            let _ = self.send_command(SandboxCommand::Deactivate);
            self.active = false;
        }
        Ok(())
    }

    /// Process audio
    pub fn process(
        &mut self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
        _context: &ProcessContext,
    ) -> SandboxResult<()> {
        if !self.active {
            // Pass through
            for i in 0..output.channels.min(input.channels) {
                if let (Some(src), Some(dst)) = (input.channel(i), output.channel_mut(i)) {
                    let len = src.len().min(dst.len());
                    dst[..len].copy_from_slice(&src[..len]);
                }
            }
            return Ok(());
        }

        // Copy input to shared buffer
        self.input_buffer.copy_from(input);
        self.buffer_id += 1;

        // Check if process is alive
        if let Some(process) = &mut self.process
            && !process.is_alive() {
                // Try to restart
                if self.config.auto_restart && process.restart_count < self.config.max_restarts {
                    process.restart_count += 1;
                    drop(self.process.take());
                    self.spawn_process()?;
                    self.initialize(&self.context.clone())?;
                    self.activate()?;
                } else {
                    return Err(SandboxError::PluginCrashed);
                }
            }

        // Send process command
        let resp = self.send_command(SandboxCommand::Process {
            buffer_id: self.buffer_id,
            num_samples: input.samples,
        })?;

        match resp {
            SandboxResponse::ProcessComplete { .. } => {
                // Copy output from shared buffer
                self.output_buffer.copy_to(output);
                Ok(())
            }
            SandboxResponse::Error { message } => Err(SandboxError::PluginError(
                PluginError::ProcessingError(message),
            )),
            _ => Ok(()),
        }
    }

    /// Get parameter value
    pub fn get_parameter(&self, id: u32) -> Option<f64> {
        self.parameters
            .iter()
            .find(|p| p.id == id)
            .map(|p| p.normalized)
    }

    /// Set parameter value
    pub fn set_parameter(&mut self, id: u32, value: f64) -> SandboxResult<()> {
        let resp = self.send_command(SandboxCommand::SetParameter { id, value })?;

        if let SandboxResponse::Error { message } = resp {
            return Err(SandboxError::PluginError(PluginError::ParameterError(
                message,
            )));
        }

        // Update cached value
        if let Some(param) = self.parameters.iter_mut().find(|p| p.id == id) {
            param.normalized = value;
        }

        Ok(())
    }

    /// Get latency in samples
    pub fn latency(&self) -> usize {
        self.latency
    }

    /// Get parameters
    pub fn parameters(&self) -> &[ParameterInfo] {
        &self.parameters
    }

    /// Health check
    pub fn is_healthy(&mut self) -> bool {
        if let Some(process) = &mut self.process {
            if !process.is_alive() {
                return false;
            }

            // Send ping
            if let Ok(SandboxResponse::Pong) = self.send_command(SandboxCommand::Ping) {
                return true;
            }
        }
        false
    }

    /// Force kill the sandbox process
    pub fn kill(&mut self) {
        if let Some(process) = &mut self.process {
            process.kill();
        }
        self.process = None;
        self.active = false;
    }

    /// Shutdown gracefully
    pub fn shutdown(&mut self) {
        if self.process.is_some() {
            // Try to send shutdown command
            if let Some(process) = &self.process {
                let _ = process.cmd_tx.send(SandboxCommand::Shutdown);
            }
            // Wait a bit for graceful shutdown
            std::thread::sleep(Duration::from_millis(100));
            // Kill if still alive
            if let Some(process) = &mut self.process
                && process.is_alive() {
                    process.kill();
                }
        }
        self.process = None;
        self.active = false;
        self.initialized = false;
    }
}

impl Drop for SandboxedPlugin {
    fn drop(&mut self) {
        self.shutdown();
    }
}

// ============ Sandbox Manager ============

/// Manages multiple sandboxed plugins
pub struct SandboxManager {
    /// Active sandboxed plugins
    plugins: RwLock<HashMap<String, Arc<Mutex<SandboxedPlugin>>>>,
    /// Default configuration
    config: SandboxConfig,
    /// Health check interval
    health_check_interval: Duration,
    /// Crash callback
    crash_callback: Option<CrashCallback>,
}

impl SandboxManager {
    pub fn new(config: SandboxConfig) -> Self {
        Self {
            plugins: RwLock::new(HashMap::new()),
            config,
            health_check_interval: Duration::from_secs(5),
            crash_callback: None,
        }
    }

    /// Set crash callback
    pub fn on_crash<F>(&mut self, callback: F)
    where
        F: Fn(&str) + Send + Sync + 'static,
    {
        self.crash_callback = Some(Box::new(callback));
    }

    /// Load a plugin in sandbox
    pub fn load_plugin(
        &self,
        instance_id: &str,
        plugin_path: impl AsRef<Path>,
        plugin_type: &str,
    ) -> SandboxResult<()> {
        let plugin = SandboxedPlugin::new(plugin_path, plugin_type, self.config.clone());

        self.plugins
            .write()
            .insert(instance_id.to_string(), Arc::new(Mutex::new(plugin)));

        Ok(())
    }

    /// Get sandboxed plugin
    pub fn get_plugin(&self, instance_id: &str) -> Option<Arc<Mutex<SandboxedPlugin>>> {
        self.plugins.read().get(instance_id).cloned()
    }

    /// Unload plugin
    pub fn unload_plugin(&self, instance_id: &str) {
        if let Some(plugin) = self.plugins.write().remove(instance_id)
            && let Some(mut p) = plugin.try_lock() {
                p.shutdown();
            }
    }

    /// Check health of all plugins
    pub fn check_health(&self) -> Vec<(String, bool)> {
        let plugins = self.plugins.read();
        let mut results = Vec::with_capacity(plugins.len());

        for (id, plugin) in plugins.iter() {
            if let Some(mut p) = plugin.try_lock() {
                let healthy = p.is_healthy();
                results.push((id.clone(), healthy));

                if !healthy
                    && let Some(ref callback) = self.crash_callback {
                        callback(id);
                    }
            }
        }

        results
    }

    /// Kill all sandboxes
    pub fn shutdown_all(&self) {
        for (_, plugin) in self.plugins.write().drain() {
            if let Some(mut p) = plugin.try_lock() {
                p.shutdown();
            }
        }
    }
}

impl Default for SandboxManager {
    fn default() -> Self {
        Self::new(SandboxConfig::default())
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sandbox_config() {
        let config = SandboxConfig::default();
        assert!(config.auto_restart);
        assert_eq!(config.max_restarts, 3);
    }

    #[test]
    fn test_shared_audio_buffer() {
        let mut shared = SharedAudioBuffer::new(0, 2, 512);

        let input = AudioBuffer::new(2, 512);
        shared.copy_from(&input);

        let mut output = AudioBuffer::new(2, 512);
        shared.copy_to(&mut output);
    }

    #[test]
    fn test_parameter_info_conversion() {
        let info = ParameterInfo {
            id: 1,
            name: "Volume".into(),
            unit: "dB".into(),
            min: -96.0,
            max: 6.0,
            default: 0.0,
            normalized: 0.5,
            steps: 0,
            automatable: true,
            read_only: false,
        };

        let ser: ParameterInfoSer = info.clone().into();
        let back: ParameterInfo = ser.into();

        assert_eq!(back.id, 1);
        assert_eq!(back.name, "Volume");
    }

    #[test]
    fn test_sandbox_manager() {
        let manager = SandboxManager::default();
        assert!(manager.check_health().is_empty());
    }
}
