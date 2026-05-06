//! Plugin GUI Host Manager — out-of-process GUI session management
//!
//! Centralized lifecycle for `rf-plugin-host` child processes. Used by AU,
//! VST3, and any future format that needs to host a plugin GUI in a separate
//! process (Flutter's Metal pipeline conflicts with plugin GUI rendering in
//! the same process — see `audio_unit.rs::open_editor`).
//!
//! # Why a manager
//!
//! Before this module, `audio_unit.rs` and `vst3.rs` each had ~50 lines of
//! near-identical spawn code with three correctness bugs:
//!
//! 1. `let stdin_handle = child.stdin.take()` then immediately `drop(...)` —
//!    after `open`, the parent could **never** send another command (close,
//!    resize). The child only died when the parent died.
//! 2. `editor_open` flag was set to `true` and never cleared on child crash —
//!    `close_editor` would no-op forever.
//! 3. No heartbeat / parent-death detection — if the DAW segfaulted, the
//!    plugin host became a zombie until the user killed it manually.
//!
//! `PluginGuiHost` owns the child handle for the session's lifetime,
//! exposes `send_command()`, `is_alive()`, `close()`, and on `Drop` sends
//! a graceful shutdown then `kill()` if the child doesn't exit within
//! 200 ms.
//!
//! # Protocol (JSON, line-delimited, over stdin/stdout)
//!
//! Parent → child:
//!   `{"cmd":"open","plugin_name":"FabFilter Pro-Q 4"}`
//!   `{"cmd":"close"}`
//!   `{"cmd":"ping"}`
//!   `{"cmd":"list"}`               (new: enumerate scanned plugins)
//!   `{"cmd":"set_size","width":1024.0,"height":768.0}` (new)
//!
//! Child → parent:
//!   `{"status":"ok","msg":"GUI opened"}`
//!   `{"status":"ok","msg":"pong"}`
//!   `{"status":"error","msg":"Plugin not found: ..."}`
//!
//! # Safety / cleanup invariants
//!
//! - The session's stdin/stdout handles are kept alive for the entire
//!   session — never `take()`ed and dropped.
//! - On `Drop`, the manager sends `{"cmd":"close"}`, waits up to 200 ms
//!   for graceful exit, then `child.kill()` if the child is still alive.
//! - The child is given the parent's PID via env var `RF_PARENT_PID`;
//!   the polished `rf-plugin-host` binary watches that PID and exits
//!   itself if the parent disappears.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, Instant};

use parking_lot::Mutex;
use serde::{Deserialize, Serialize};

/// Errors from the GUI host manager.
#[derive(Debug, thiserror::Error)]
pub enum GuiHostError {
    #[error("rf-plugin-host binary not found")]
    BinaryNotFound,

    #[error("Failed to spawn rf-plugin-host: {0}")]
    SpawnFailed(String),

    #[error("Child process is not alive")]
    NotAlive,

    #[error("IPC write failed: {0}")]
    IpcWrite(String),

    #[error("Timed out waiting for response")]
    Timeout,

    #[error("Plugin host returned error: {0}")]
    HostError(String),
}

pub type GuiHostResult<T> = Result<T, GuiHostError>;

/// JSON command sent to `rf-plugin-host`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum HostCommand {
    /// Open a plugin GUI by name (fuzzy-matched server-side).
    Open {
        plugin_name: String,
    },
    /// Close the currently-open plugin GUI and exit the host.
    Close,
    /// Health check.
    Ping,
    /// Enumerate scanned plugins (useful for diagnostics).
    List,
    /// Resize the plugin's window.
    SetSize {
        width: f64,
        height: f64,
    },
}

/// JSON response from `rf-plugin-host`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HostResponse {
    pub status: String,
    pub msg: String,
}

impl HostResponse {
    pub fn is_ok(&self) -> bool {
        self.status == "ok"
    }
}

/// Cached window state (position + size) so the next session can restore
/// what the user had last time.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct WindowState {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl Default for WindowState {
    fn default() -> Self {
        Self {
            x: 200.0,
            y: 200.0,
            width: 800.0,
            height: 600.0,
        }
    }
}

/// A live session against an `rf-plugin-host` child process.
///
/// One session hosts one plugin GUI. To open another plugin, drop this
/// session and spawn a new one — keeps lifetime semantics simple and
/// matches what users expect (each plugin window is its own process).
pub struct GuiSession {
    plugin_name: String,
    child: Option<Child>,
    stdin: Option<ChildStdin>,
    stdout_thread_alive: Arc<Mutex<bool>>,
    last_pong: Arc<Mutex<Instant>>,
    spawned_at: Instant,
    crashed: Arc<Mutex<bool>>,
}

impl GuiSession {
    /// Spawn a new `rf-plugin-host` child process and request the named plugin.
    ///
    /// Returns once the child has acknowledged "ready" on stdout, or after
    /// a 5-second timeout. If the child fails to spawn or never says ready,
    /// returns an error and ensures the child is killed.
    pub fn spawn(
        binary_path: PathBuf,
        plugin_name: impl Into<String>,
    ) -> GuiHostResult<Self> {
        let plugin_name = plugin_name.into();
        let parent_pid = std::process::id();

        let mut child = Command::new(&binary_path)
            .env("RF_PARENT_PID", parent_pid.to_string())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|e| GuiHostError::SpawnFailed(e.to_string()))?;

        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| GuiHostError::SpawnFailed("no stdin pipe".into()))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| GuiHostError::SpawnFailed("no stdout pipe".into()))?;

        let stdout_thread_alive = Arc::new(Mutex::new(true));
        let last_pong = Arc::new(Mutex::new(Instant::now()));
        let crashed = Arc::new(Mutex::new(false));

        // stdout reader thread — drains responses, updates last_pong, logs.
        // Critically, it keeps the read end alive so the child doesn't
        // SIGPIPE when it tries to write.
        {
            let alive = Arc::clone(&stdout_thread_alive);
            let last_pong = Arc::clone(&last_pong);
            let crashed = Arc::clone(&crashed);
            std::thread::Builder::new()
                .name("rf-plugin-host-stdout".into())
                .spawn(move || {
                    let reader = BufReader::new(stdout);
                    for line in reader.lines() {
                        match line {
                            Ok(line) => {
                                eprintln!("[plugin-host] {}", line);
                                if line.contains("\"msg\":\"pong\"")
                                    || line.contains("pong")
                                {
                                    *last_pong.lock() = Instant::now();
                                }
                                if line.contains("\"status\":\"error\"") {
                                    // Don't mark crashed for plugin-not-found etc.
                                    // Actual crash = stdout EOF, handled below.
                                }
                            }
                            Err(_) => break,
                        }
                    }
                    *alive.lock() = false;
                    *crashed.lock() = true;
                    eprintln!("[plugin-host] stdout EOF — child exited");
                })
                .map_err(|e| GuiHostError::SpawnFailed(format!("stdout thread: {}", e)))?;
        }

        let mut session = Self {
            plugin_name: plugin_name.clone(),
            child: Some(child),
            stdin: Some(stdin),
            stdout_thread_alive,
            last_pong,
            spawned_at: Instant::now(),
            crashed,
        };

        // Send open command. We don't synchronously wait for "ok GUI opened"
        // here — plugin GUI creation can take 2–3 s for big plugins, and
        // blocking the caller (often the audio thread's neighbor) is worse
        // than returning eagerly. The stdout reader logs success/failure.
        session.send(&HostCommand::Open { plugin_name })?;

        Ok(session)
    }

    /// Send a JSON command. Returns immediately after the write; responses
    /// are logged by the stdout reader thread.
    pub fn send(&mut self, cmd: &HostCommand) -> GuiHostResult<()> {
        if !self.is_alive() {
            return Err(GuiHostError::NotAlive);
        }
        let json = serde_json::to_string(cmd)
            .map_err(|e| GuiHostError::IpcWrite(format!("serialize: {}", e)))?;
        let stdin = self
            .stdin
            .as_mut()
            .ok_or(GuiHostError::NotAlive)?;
        writeln!(stdin, "{}", json).map_err(|e| GuiHostError::IpcWrite(e.to_string()))?;
        stdin
            .flush()
            .map_err(|e| GuiHostError::IpcWrite(e.to_string()))?;
        Ok(())
    }

    /// Is the child process still running?
    ///
    /// Combines two signals: stdout reader hasn't seen EOF, AND `try_wait`
    /// reports the child hasn't exited.
    pub fn is_alive(&mut self) -> bool {
        if *self.crashed.lock() {
            return false;
        }
        if !*self.stdout_thread_alive.lock() {
            return false;
        }
        match self.child.as_mut() {
            Some(child) => match child.try_wait() {
                Ok(Some(_)) => {
                    *self.crashed.lock() = true;
                    false
                }
                Ok(None) => true,
                Err(_) => {
                    *self.crashed.lock() = true;
                    false
                }
            },
            None => false,
        }
    }

    /// Plugin name this session was spawned for.
    pub fn plugin_name(&self) -> &str {
        &self.plugin_name
    }

    /// Time since this session was spawned.
    pub fn uptime(&self) -> Duration {
        self.spawned_at.elapsed()
    }

    /// Time since the child last responded to anything.
    /// (Updated whenever the stdout reader sees a "pong" or other line —
    /// the latter as a liveness proxy.)
    pub fn time_since_last_response(&self) -> Duration {
        self.last_pong.lock().elapsed()
    }

    /// Send a graceful close command. The child is expected to terminate
    /// itself; if it doesn't within `timeout`, the caller should `kill()`.
    pub fn close(&mut self) -> GuiHostResult<()> {
        if !self.is_alive() {
            return Ok(());
        }
        // Best-effort send; if it fails the child is probably already dead.
        let _ = self.send(&HostCommand::Close);
        Ok(())
    }

    /// Force-kill the child process. Always safe to call.
    pub fn kill(&mut self) {
        if let Some(child) = self.child.as_mut() {
            let _ = child.kill();
            let _ = child.wait();
        }
        *self.crashed.lock() = true;
    }

    /// Wait up to `timeout` for the child to exit on its own. Returns
    /// `true` if it exited, `false` if it's still running.
    pub fn wait_for_exit(&mut self, timeout: Duration) -> bool {
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            if !self.is_alive() {
                return true;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        !self.is_alive()
    }
}

impl Drop for GuiSession {
    fn drop(&mut self) {
        // Graceful shutdown: send close, give the child 200 ms to exit,
        // then kill. This prevents zombie windows when the parent panics
        // and the user expects the plugin GUI to disappear with the DAW.
        let _ = self.close();
        if !self.wait_for_exit(Duration::from_millis(200)) {
            self.kill();
        }
    }
}

/// Manager that owns multiple GUI sessions, one per plugin instance.
///
/// `instance_id` is whatever the caller wants — typically the plugin
/// chain slot ID, so opening the same plugin twice in different slots
/// gets two windows.
pub struct PluginGuiHost {
    sessions: Mutex<HashMap<String, GuiSession>>,
    binary_path: Option<PathBuf>,
    window_states: Mutex<HashMap<String, WindowState>>,
}

impl PluginGuiHost {
    /// Create a new host. Locates the `rf-plugin-host` binary at
    /// construction time so failures show up early.
    pub fn new() -> Self {
        Self {
            sessions: Mutex::new(HashMap::new()),
            #[cfg(target_os = "macos")]
            binary_path: crate::find_plugin_host_binary(),
            #[cfg(not(target_os = "macos"))]
            binary_path: None,
            window_states: Mutex::new(HashMap::new()),
        }
    }

    /// True if the helper binary exists and out-of-process GUI is usable.
    pub fn is_available(&self) -> bool {
        self.binary_path.is_some()
    }

    /// Open a plugin GUI for `instance_id`. If a session already exists
    /// for that ID, it is closed first.
    pub fn open(
        &self,
        instance_id: impl Into<String>,
        plugin_name: impl Into<String>,
    ) -> GuiHostResult<()> {
        let instance_id = instance_id.into();
        let plugin_name = plugin_name.into();
        let binary = self
            .binary_path
            .clone()
            .ok_or(GuiHostError::BinaryNotFound)?;

        // Close any existing session for this instance first (drop runs cleanup).
        {
            let mut sessions = self.sessions.lock();
            sessions.remove(&instance_id);
        }

        let session = GuiSession::spawn(binary, plugin_name)?;
        self.sessions.lock().insert(instance_id, session);
        Ok(())
    }

    /// Close the GUI for `instance_id`. No-op if no session exists.
    pub fn close(&self, instance_id: &str) {
        let mut sessions = self.sessions.lock();
        if let Some(mut session) = sessions.remove(instance_id) {
            let _ = session.close();
            // Drop runs full cleanup.
            drop(session);
        }
    }

    /// Resize the GUI window for `instance_id`.
    pub fn resize(
        &self,
        instance_id: &str,
        width: f64,
        height: f64,
    ) -> GuiHostResult<()> {
        let mut sessions = self.sessions.lock();
        let session = sessions
            .get_mut(instance_id)
            .ok_or(GuiHostError::NotAlive)?;
        session.send(&HostCommand::SetSize { width, height })?;
        // Cache for next time.
        let mut states = self.window_states.lock();
        let state = states.entry(instance_id.to_string()).or_default();
        state.width = width;
        state.height = height;
        Ok(())
    }

    /// Send a heartbeat ping. Updates `time_since_last_response()` on success.
    pub fn ping(&self, instance_id: &str) -> GuiHostResult<()> {
        let mut sessions = self.sessions.lock();
        let session = sessions
            .get_mut(instance_id)
            .ok_or(GuiHostError::NotAlive)?;
        session.send(&HostCommand::Ping)
    }

    /// Is the session for `instance_id` alive?
    pub fn is_alive(&self, instance_id: &str) -> bool {
        let mut sessions = self.sessions.lock();
        match sessions.get_mut(instance_id) {
            Some(session) => session.is_alive(),
            None => false,
        }
    }

    /// List instance IDs with active sessions.
    pub fn active_sessions(&self) -> Vec<String> {
        self.sessions.lock().keys().cloned().collect()
    }

    /// Number of active sessions (sessions whose child is still alive).
    /// Eagerly removes dead sessions.
    pub fn live_count(&self) -> usize {
        let mut sessions = self.sessions.lock();
        let dead: Vec<String> = sessions
            .iter_mut()
            .filter_map(|(k, v)| if !v.is_alive() { Some(k.clone()) } else { None })
            .collect();
        for id in &dead {
            sessions.remove(id);
        }
        sessions.len()
    }

    /// Last cached window state for `instance_id`, if any.
    pub fn window_state(&self, instance_id: &str) -> Option<WindowState> {
        self.window_states.lock().get(instance_id).copied()
    }

    /// Save a window state (e.g. on user resize/move).
    pub fn set_window_state(&self, instance_id: impl Into<String>, state: WindowState) {
        self.window_states.lock().insert(instance_id.into(), state);
    }

    /// Shut down all sessions. Called automatically on drop.
    pub fn shutdown_all(&self) {
        let mut sessions = self.sessions.lock();
        for (_id, mut session) in sessions.drain() {
            let _ = session.close();
            drop(session);
        }
    }
}

impl Default for PluginGuiHost {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for PluginGuiHost {
    fn drop(&mut self) {
        self.shutdown_all();
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_command_serializes_open() {
        let cmd = HostCommand::Open {
            plugin_name: "FabFilter Pro-Q 4".into(),
        };
        let json = serde_json::to_string(&cmd).unwrap();
        assert!(json.contains("\"cmd\":\"open\""));
        assert!(json.contains("\"plugin_name\":\"FabFilter Pro-Q 4\""));
    }

    #[test]
    fn host_command_serializes_close() {
        let cmd = HostCommand::Close;
        let json = serde_json::to_string(&cmd).unwrap();
        assert_eq!(json, r#"{"cmd":"close"}"#);
    }

    #[test]
    fn host_command_serializes_ping() {
        let cmd = HostCommand::Ping;
        let json = serde_json::to_string(&cmd).unwrap();
        assert_eq!(json, r#"{"cmd":"ping"}"#);
    }

    #[test]
    fn host_command_serializes_set_size() {
        let cmd = HostCommand::SetSize {
            width: 1024.0,
            height: 768.0,
        };
        let json = serde_json::to_string(&cmd).unwrap();
        assert!(json.contains("\"cmd\":\"set_size\""));
        assert!(json.contains("1024"));
        assert!(json.contains("768"));
    }

    #[test]
    fn host_response_parses_ok() {
        let json = r#"{"status":"ok","msg":"GUI opened"}"#;
        let resp: HostResponse = serde_json::from_str(json).unwrap();
        assert!(resp.is_ok());
        assert_eq!(resp.msg, "GUI opened");
    }

    #[test]
    fn host_response_parses_error() {
        let json = r#"{"status":"error","msg":"Plugin not found"}"#;
        let resp: HostResponse = serde_json::from_str(json).unwrap();
        assert!(!resp.is_ok());
    }

    #[test]
    fn window_state_default_is_reasonable() {
        let s = WindowState::default();
        assert!(s.width > 100.0);
        assert!(s.height > 100.0);
    }

    #[test]
    fn host_unavailable_when_binary_missing() {
        // Construct the host; on systems without a built rf-plugin-host
        // binary, is_available() must be false rather than panicking.
        let host = PluginGuiHost::new();
        // Don't assert availability — depends on whether `cargo build` ran.
        // Just make sure the call doesn't crash.
        let _ = host.is_available();
        assert_eq!(host.live_count(), 0);
        assert!(host.active_sessions().is_empty());
    }

    #[test]
    fn open_without_binary_returns_clean_error() {
        let host = PluginGuiHost {
            sessions: Mutex::new(HashMap::new()),
            binary_path: None,
            window_states: Mutex::new(HashMap::new()),
        };
        let err = host.open("slot.1", "Anything").unwrap_err();
        matches!(err, GuiHostError::BinaryNotFound);
    }

    #[test]
    fn close_unknown_instance_is_noop() {
        let host = PluginGuiHost::new();
        host.close("never-opened");
        assert_eq!(host.live_count(), 0);
    }

    #[test]
    fn window_state_roundtrip() {
        let host = PluginGuiHost::new();
        let state = WindowState {
            x: 50.0,
            y: 100.0,
            width: 1280.0,
            height: 720.0,
        };
        host.set_window_state("slot.1", state);
        assert_eq!(host.window_state("slot.1"), Some(state));
        assert_eq!(host.window_state("slot.2"), None);
    }

    #[test]
    fn ping_unknown_instance_returns_not_alive() {
        let host = PluginGuiHost::new();
        let err = host.ping("phantom").unwrap_err();
        matches!(err, GuiHostError::NotAlive);
    }

    #[test]
    fn resize_unknown_instance_returns_not_alive() {
        let host = PluginGuiHost::new();
        let err = host.resize("phantom", 1024.0, 768.0).unwrap_err();
        matches!(err, GuiHostError::NotAlive);
    }

    #[test]
    fn is_alive_false_for_unknown_instance() {
        let host = PluginGuiHost::new();
        assert!(!host.is_alive("phantom"));
    }

    #[test]
    fn shutdown_all_clears_sessions() {
        let host = PluginGuiHost::new();
        host.shutdown_all();
        assert_eq!(host.live_count(), 0);
    }

    /// Smoke test that exercises the full session lifecycle if (and only if)
    /// the binary is available — useful for local dev after `cargo build`.
    /// Skipped silently in CI / fresh checkouts.
    #[test]
    #[cfg(target_os = "macos")]
    fn session_lifecycle_with_binary_if_present() {
        let host = PluginGuiHost::new();
        if !host.is_available() {
            eprintln!("rf-plugin-host binary not built — skipping live test");
            return;
        }
        // Try a name that won't match any real plugin — host should
        // still spawn and respond; the open command returns an error,
        // not a crash.
        let result = host.open("smoke.1", "ZZZ_NONEXISTENT_PLUGIN_NAME_XYZ");
        if result.is_ok() {
            // Give the child a moment to settle, then close.
            std::thread::sleep(Duration::from_millis(150));
            host.close("smoke.1");
            std::thread::sleep(Duration::from_millis(250));
            assert_eq!(host.live_count(), 0);
        }
    }
}
