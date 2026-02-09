//! rf-script: Scripting API for FluxForge Studio
//!
//! Power user automation via Lua scripting:
//! - Track/clip manipulation
//! - Custom processors
//! - Batch operations
//! - Macro recording
//! - External control

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use crossbeam_channel::{Receiver, Sender, bounded};
use mlua::{Lua, Table, UserData, UserDataMethods};
use parking_lot::RwLock;
use thiserror::Error;

// ============ Error Types ============

#[derive(Error, Debug)]
pub enum ScriptError {
    #[error("Lua error: {0}")]
    LuaError(#[from] mlua::Error),

    #[error("Script not found: {0}")]
    NotFound(String),

    #[error("Script execution failed: {0}")]
    ExecutionFailed(String),

    #[error("Invalid script: {0}")]
    InvalidScript(String),

    #[error("Timeout")]
    Timeout,

    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),
}

pub type ScriptResult<T> = Result<T, ScriptError>;

// ============ Script Context ============

/// Execution context passed to scripts
#[derive(Clone)]
pub struct ScriptContext {
    /// Current project path
    pub project_path: Option<PathBuf>,
    /// Selected track IDs
    pub selected_tracks: Vec<u64>,
    /// Selected clip IDs
    pub selected_clips: Vec<u64>,
    /// Playhead position (samples)
    pub playhead: u64,
    /// Transport playing
    pub is_playing: bool,
    /// Recording
    pub is_recording: bool,
    /// Sample rate
    pub sample_rate: u32,
    /// Block size
    pub block_size: usize,
}

impl Default for ScriptContext {
    fn default() -> Self {
        Self {
            project_path: None,
            selected_tracks: Vec::new(),
            selected_clips: Vec::new(),
            playhead: 0,
            is_playing: false,
            is_recording: false,
            sample_rate: 48000,
            block_size: 256,
        }
    }
}

impl UserData for ScriptContext {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("get_playhead", |_, this, ()| Ok(this.playhead));
        methods.add_method("get_sample_rate", |_, this, ()| Ok(this.sample_rate));
        methods.add_method("is_playing", |_, this, ()| Ok(this.is_playing));
        methods.add_method("is_recording", |_, this, ()| Ok(this.is_recording));
        methods.add_method("get_selected_tracks", |_, this, ()| {
            Ok(this.selected_tracks.clone())
        });
        methods.add_method("get_selected_clips", |_, this, ()| {
            Ok(this.selected_clips.clone())
        });
    }
}

// ============ Script Actions ============

/// Actions that scripts can trigger
#[derive(Debug, Clone)]
pub enum ScriptAction {
    // Transport
    Play,
    Stop,
    Record,
    SetPlayhead(u64),
    SetLoop(u64, u64),

    // Track operations
    CreateTrack {
        name: String,
        track_type: String,
    },
    DeleteTrack(u64),
    RenameTrack(u64, String),
    MuteTrack(u64, bool),
    SoloTrack(u64, bool),
    SetTrackVolume(u64, f64),
    SetTrackPan(u64, f64),

    // Clip operations
    CreateClip {
        track_id: u64,
        start: u64,
        length: u64,
    },
    DeleteClip(u64),
    MoveClip {
        clip_id: u64,
        new_start: u64,
    },
    TrimClip {
        clip_id: u64,
        new_start: u64,
        new_end: u64,
    },
    SplitClip {
        clip_id: u64,
        position: u64,
    },
    DuplicateClip(u64),

    // Selection
    SelectTrack(u64),
    SelectClip(u64),
    SelectAll,
    DeselectAll,

    // Edit operations
    Cut,
    Copy,
    Paste,
    Delete,
    Undo,
    Redo,

    // Plugin operations
    InsertPlugin {
        track_id: u64,
        slot: usize,
        plugin_id: String,
    },
    RemovePlugin {
        track_id: u64,
        slot: usize,
    },
    SetPluginParam {
        track_id: u64,
        slot: usize,
        param_id: u32,
        value: f64,
    },

    // Automation
    WriteAutomation {
        track_id: u64,
        param: String,
        time: u64,
        value: f64,
    },
    ClearAutomation {
        track_id: u64,
        param: String,
    },

    // Markers
    AddMarker {
        position: u64,
        name: String,
        color: u32,
    },
    DeleteMarker(u64),

    // Project
    Save,
    SaveAs(PathBuf),
    Export {
        path: PathBuf,
        format: String,
    },

    // Custom message
    Custom {
        name: String,
        data: String,
    },
}

// ============ Script Engine ============

/// Lua scripting engine
pub struct ScriptEngine {
    /// Lua state
    lua: Lua,
    /// Loaded scripts
    scripts: HashMap<String, LoadedScript>,
    /// Action sender
    action_tx: Sender<ScriptAction>,
    /// Action receiver (for the host)
    action_rx: Receiver<ScriptAction>,
    /// Current context
    context: Arc<RwLock<ScriptContext>>,
    /// Script search paths
    search_paths: Vec<PathBuf>,
}

#[allow(dead_code)]
struct LoadedScript {
    name: String,
    path: PathBuf,
    source: String,
    description: Option<String>,
}

impl ScriptEngine {
    /// Create a new sandboxed script engine
    ///
    /// SECURITY: Uses Lua::new_with() to create a restricted environment
    /// that excludes dangerous libraries (os, io, debug, ffi, package).
    /// Only safe standard libraries are loaded (coroutine, string, utf8, table, math).
    pub fn new() -> ScriptResult<Self> {
        // SECURITY: Create sandboxed Lua without dangerous libraries
        // Excludes: os, io, debug, ffi, package
        // Includes: coroutine, string, utf8, table, math
        let safe_libs = mlua::StdLib::COROUTINE
            | mlua::StdLib::STRING
            | mlua::StdLib::UTF8
            | mlua::StdLib::TABLE
            | mlua::StdLib::MATH;

        let lua = Lua::new_with(safe_libs, mlua::LuaOptions::default())?;

        // SECURITY: Remove potentially dangerous globals that might leak through
        {
            let globals = lua.globals();
            // Remove loadfile/dofile (can load external code)
            globals.set("loadfile", mlua::Value::Nil)?;
            globals.set("dofile", mlua::Value::Nil)?;
            // Remove collectgarbage (can cause DoS)
            globals.set("collectgarbage", mlua::Value::Nil)?;
            // Remove rawget/rawset (can bypass metatables)
            globals.set("rawget", mlua::Value::Nil)?;
            globals.set("rawset", mlua::Value::Nil)?;
            globals.set("rawequal", mlua::Value::Nil)?;
            globals.set("rawlen", mlua::Value::Nil)?;
            // Keep: assert, error, ipairs, pairs, next, pcall, xpcall,
            //       print (we override), select, tonumber, tostring, type, _VERSION
        }

        let (action_tx, action_rx) = bounded(256);
        let context = Arc::new(RwLock::new(ScriptContext::default()));

        let engine = Self {
            lua,
            scripts: HashMap::new(),
            action_tx,
            action_rx,
            context,
            search_paths: Vec::new(),
        };

        engine.setup_api()?;

        Ok(engine)
    }

    /// Create an UNSAFE script engine with full Lua access
    ///
    /// WARNING: Only use for trusted internal scripts or debugging.
    /// This exposes os, io, debug libraries which can:
    /// - Execute system commands
    /// - Read/write arbitrary files
    /// - Modify running program state
    #[allow(dead_code)]
    pub fn new_unsafe() -> ScriptResult<Self> {
        // SAFETY: This is explicitly unsafe and should only be used for trusted scripts
        let lua = unsafe { Lua::unsafe_new_with(mlua::StdLib::ALL, mlua::LuaOptions::default()) };
        let (action_tx, action_rx) = bounded(256);
        let context = Arc::new(RwLock::new(ScriptContext::default()));

        let engine = Self {
            lua,
            scripts: HashMap::new(),
            action_tx,
            action_rx,
            context,
            search_paths: Vec::new(),
        };

        engine.setup_api()?;

        Ok(engine)
    }

    /// Set up the Lua API
    fn setup_api(&self) -> ScriptResult<()> {
        let globals = self.lua.globals();

        // FluxForge Studio namespace
        let rf = self.lua.create_table()?;

        // Transport API
        let tx = self.action_tx.clone();
        rf.set(
            "play",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::Play).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "stop",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::Stop).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "record",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::Record).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "set_playhead",
            self.lua.create_function(move |_, position: u64| {
                tx.send(ScriptAction::SetPlayhead(position)).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "set_loop",
            self.lua
                .create_function(move |_, (start, end): (u64, u64)| {
                    tx.send(ScriptAction::SetLoop(start, end)).ok();
                    Ok(())
                })?,
        )?;

        // Track API
        let tx = self.action_tx.clone();
        rf.set(
            "create_track",
            self.lua
                .create_function(move |_, (name, track_type): (String, String)| {
                    tx.send(ScriptAction::CreateTrack { name, track_type }).ok();
                    Ok(())
                })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "delete_track",
            self.lua.create_function(move |_, id: u64| {
                tx.send(ScriptAction::DeleteTrack(id)).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "mute_track",
            self.lua
                .create_function(move |_, (id, muted): (u64, bool)| {
                    tx.send(ScriptAction::MuteTrack(id, muted)).ok();
                    Ok(())
                })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "solo_track",
            self.lua
                .create_function(move |_, (id, solo): (u64, bool)| {
                    tx.send(ScriptAction::SoloTrack(id, solo)).ok();
                    Ok(())
                })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "set_track_volume",
            self.lua.create_function(move |_, (id, vol): (u64, f64)| {
                tx.send(ScriptAction::SetTrackVolume(id, vol)).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "set_track_pan",
            self.lua.create_function(move |_, (id, pan): (u64, f64)| {
                tx.send(ScriptAction::SetTrackPan(id, pan)).ok();
                Ok(())
            })?,
        )?;

        // Clip API
        let tx = self.action_tx.clone();
        rf.set(
            "create_clip",
            self.lua
                .create_function(move |_, (track_id, start, length): (u64, u64, u64)| {
                    tx.send(ScriptAction::CreateClip {
                        track_id,
                        start,
                        length,
                    })
                    .ok();
                    Ok(())
                })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "delete_clip",
            self.lua.create_function(move |_, id: u64| {
                tx.send(ScriptAction::DeleteClip(id)).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "move_clip",
            self.lua
                .create_function(move |_, (clip_id, new_start): (u64, u64)| {
                    tx.send(ScriptAction::MoveClip { clip_id, new_start }).ok();
                    Ok(())
                })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "split_clip",
            self.lua
                .create_function(move |_, (clip_id, position): (u64, u64)| {
                    tx.send(ScriptAction::SplitClip { clip_id, position }).ok();
                    Ok(())
                })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "duplicate_clip",
            self.lua.create_function(move |_, id: u64| {
                tx.send(ScriptAction::DuplicateClip(id)).ok();
                Ok(())
            })?,
        )?;

        // Edit API
        let tx = self.action_tx.clone();
        rf.set(
            "cut",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::Cut).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "copy",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::Copy).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "paste",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::Paste).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "delete",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::Delete).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "undo",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::Undo).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "redo",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::Redo).ok();
                Ok(())
            })?,
        )?;

        // Selection API
        let tx = self.action_tx.clone();
        rf.set(
            "select_track",
            self.lua.create_function(move |_, id: u64| {
                tx.send(ScriptAction::SelectTrack(id)).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "select_clip",
            self.lua.create_function(move |_, id: u64| {
                tx.send(ScriptAction::SelectClip(id)).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "select_all",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::SelectAll).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "deselect_all",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::DeselectAll).ok();
                Ok(())
            })?,
        )?;

        // Plugin API
        let tx = self.action_tx.clone();
        rf.set(
            "insert_plugin",
            self.lua.create_function(
                move |_, (track_id, slot, plugin_id): (u64, usize, String)| {
                    tx.send(ScriptAction::InsertPlugin {
                        track_id,
                        slot,
                        plugin_id,
                    })
                    .ok();
                    Ok(())
                },
            )?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "remove_plugin",
            self.lua
                .create_function(move |_, (track_id, slot): (u64, usize)| {
                    tx.send(ScriptAction::RemovePlugin { track_id, slot }).ok();
                    Ok(())
                })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "set_plugin_param",
            self.lua.create_function(
                move |_, (track_id, slot, param_id, value): (u64, usize, u32, f64)| {
                    tx.send(ScriptAction::SetPluginParam {
                        track_id,
                        slot,
                        param_id,
                        value,
                    })
                    .ok();
                    Ok(())
                },
            )?,
        )?;

        // Marker API
        let tx = self.action_tx.clone();
        rf.set(
            "add_marker",
            self.lua
                .create_function(move |_, (position, name, color): (u64, String, u32)| {
                    tx.send(ScriptAction::AddMarker {
                        position,
                        name,
                        color,
                    })
                    .ok();
                    Ok(())
                })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "delete_marker",
            self.lua.create_function(move |_, id: u64| {
                tx.send(ScriptAction::DeleteMarker(id)).ok();
                Ok(())
            })?,
        )?;

        // Project API
        let tx = self.action_tx.clone();
        rf.set(
            "save",
            self.lua.create_function(move |_, ()| {
                tx.send(ScriptAction::Save).ok();
                Ok(())
            })?,
        )?;

        let tx = self.action_tx.clone();
        rf.set(
            "export",
            self.lua
                .create_function(move |_, (path, format): (String, String)| {
                    tx.send(ScriptAction::Export {
                        path: PathBuf::from(path),
                        format,
                    })
                    .ok();
                    Ok(())
                })?,
        )?;

        // Custom action
        let tx = self.action_tx.clone();
        rf.set(
            "action",
            self.lua
                .create_function(move |_, (name, data): (String, String)| {
                    tx.send(ScriptAction::Custom { name, data }).ok();
                    Ok(())
                })?,
        )?;

        // Utility functions
        rf.set(
            "print",
            self.lua.create_function(|_, msg: String| {
                log::info!("[Script] {}", msg);
                Ok(())
            })?,
        )?;

        rf.set(
            "samples_to_seconds",
            self.lua
                .create_function(|_, (samples, sample_rate): (u64, u32)| {
                    Ok(samples as f64 / sample_rate as f64)
                })?,
        )?;

        rf.set(
            "seconds_to_samples",
            self.lua
                .create_function(|_, (seconds, sample_rate): (f64, u32)| {
                    Ok((seconds * sample_rate as f64) as u64)
                })?,
        )?;

        rf.set(
            "db_to_linear",
            self.lua
                .create_function(|_, db: f64| Ok(10.0_f64.powf(db / 20.0)))?,
        )?;

        rf.set(
            "linear_to_db",
            self.lua.create_function(|_, linear: f64| {
                if linear > 0.0 {
                    Ok(20.0 * linear.log10())
                } else {
                    Ok(-120.0)
                }
            })?,
        )?;

        globals.set("rf", rf)?;

        Ok(())
    }

    /// Add a script search path
    pub fn add_search_path(&mut self, path: impl Into<PathBuf>) {
        self.search_paths.push(path.into());
    }

    /// Load a script from file
    pub fn load_script(&mut self, path: impl AsRef<Path>) -> ScriptResult<String> {
        let path = path.as_ref();
        let source = std::fs::read_to_string(path)?;

        let name = path
            .file_stem()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| "unnamed".into());

        let script = LoadedScript {
            name: name.clone(),
            path: path.to_path_buf(),
            source,
            description: None,
        };

        self.scripts.insert(name.clone(), script);
        Ok(name)
    }

    /// Execute a loaded script
    pub fn execute_script(&self, name: &str) -> ScriptResult<()> {
        let script = self
            .scripts
            .get(name)
            .ok_or_else(|| ScriptError::NotFound(name.into()))?;

        self.lua
            .load(&script.source)
            .set_name(&script.name)
            .exec()?;

        Ok(())
    }

    /// Execute inline Lua code
    pub fn execute(&self, code: &str) -> ScriptResult<()> {
        self.lua.load(code).exec()?;
        Ok(())
    }

    /// Execute and return result
    pub fn eval<T: for<'lua> mlua::FromLua>(&self, code: &str) -> ScriptResult<T> {
        Ok(self.lua.load(code).eval()?)
    }

    /// Update the context (call before script execution)
    pub fn update_context(&self, context: ScriptContext) {
        *self.context.write() = context;
        // Make context available in Lua
        if let Ok(globals) = self.lua.globals().get::<Table>("rf") {
            let ctx = self.context.read().clone();
            globals.set("context", ctx).ok();
        }
    }

    /// Get pending actions
    pub fn poll_actions(&self) -> Vec<ScriptAction> {
        let mut actions = Vec::new();
        while let Ok(action) = self.action_rx.try_recv() {
            actions.push(action);
        }
        actions
    }

    /// Get action receiver for the host
    pub fn action_receiver(&self) -> Receiver<ScriptAction> {
        self.action_rx.clone()
    }

    /// List loaded scripts
    pub fn list_scripts(&self) -> Vec<&str> {
        self.scripts.keys().map(|s| s.as_str()).collect()
    }

    /// Reload a script
    pub fn reload_script(&mut self, name: &str) -> ScriptResult<()> {
        let path = self
            .scripts
            .get(name)
            .ok_or_else(|| ScriptError::NotFound(name.into()))?
            .path
            .clone();

        self.load_script(path)?;
        Ok(())
    }

    /// Get Lua state for advanced usage
    pub fn lua(&self) -> &Lua {
        &self.lua
    }
}

impl Default for ScriptEngine {
    fn default() -> Self {
        Self::new().expect("Failed to create script engine")
    }
}

// ============ Script Manager ============

/// Manages script discovery and execution
pub struct ScriptManager {
    engine: ScriptEngine,
    /// User scripts directory
    user_scripts_dir: Option<PathBuf>,
    /// Built-in scripts
    builtin_scripts: HashMap<String, &'static str>,
}

impl ScriptManager {
    pub fn new() -> ScriptResult<Self> {
        let mut manager = Self {
            engine: ScriptEngine::new()?,
            user_scripts_dir: None,
            builtin_scripts: HashMap::new(),
        };

        // Add built-in scripts
        manager.builtin_scripts.insert(
            "normalize_clips".into(),
            r#"
-- Normalize all selected clips
local clips = rf.context:get_selected_clips()
for _, clip_id in ipairs(clips) do
    rf.action("normalize", tostring(clip_id))
end
rf.print("Normalized " .. #clips .. " clips")
"#,
        );

        manager.builtin_scripts.insert(
            "mute_all".into(),
            r#"
-- Mute all tracks
local tracks = rf.context:get_selected_tracks()
if #tracks == 0 then
    rf.print("No tracks selected")
else
    for _, track_id in ipairs(tracks) do
        rf.mute_track(track_id, true)
    end
    rf.print("Muted " .. #tracks .. " tracks")
end
"#,
        );

        manager.builtin_scripts.insert(
            "duplicate_track".into(),
            r#"
-- Duplicate selected track with all clips
local tracks = rf.context:get_selected_tracks()
if #tracks > 0 then
    local track_id = tracks[1]
    rf.action("duplicate_track", tostring(track_id))
    rf.print("Duplicated track " .. track_id)
end
"#,
        );

        Ok(manager)
    }

    /// Set user scripts directory
    pub fn set_user_scripts_dir(&mut self, path: impl Into<PathBuf>) {
        let path = path.into();
        self.engine.add_search_path(path.clone());
        self.user_scripts_dir = Some(path);
    }

    /// Scan and load user scripts
    pub fn scan_user_scripts(&mut self) -> ScriptResult<usize> {
        let dir = match &self.user_scripts_dir {
            Some(d) => d.clone(),
            None => return Ok(0),
        };

        if !dir.exists() {
            return Ok(0);
        }

        let mut count = 0;
        for entry in std::fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();

            if path.extension().map(|e| e == "lua").unwrap_or(false)
                && self.engine.load_script(&path).is_ok()
            {
                count += 1;
            }
        }

        Ok(count)
    }

    /// Execute a script by name
    pub fn execute(&self, name: &str) -> ScriptResult<()> {
        // Try loaded scripts first
        if self.engine.scripts.contains_key(name) {
            return self.engine.execute_script(name);
        }

        // Try built-in scripts
        if let Some(source) = self.builtin_scripts.get(name) {
            return self.engine.execute(source);
        }

        Err(ScriptError::NotFound(name.into()))
    }

    /// Execute inline code
    pub fn execute_code(&self, code: &str) -> ScriptResult<()> {
        self.engine.execute(code)
    }

    /// Get the engine
    pub fn engine(&self) -> &ScriptEngine {
        &self.engine
    }

    /// Get mutable engine
    pub fn engine_mut(&mut self) -> &mut ScriptEngine {
        &mut self.engine
    }

    /// List all available scripts
    pub fn list_all_scripts(&self) -> Vec<String> {
        let mut scripts: Vec<String> = self
            .engine
            .list_scripts()
            .into_iter()
            .map(|s| s.to_string())
            .collect();

        for name in self.builtin_scripts.keys() {
            if !scripts.contains(name) {
                scripts.push(name.clone());
            }
        }

        scripts.sort();
        scripts
    }
}

impl Default for ScriptManager {
    fn default() -> Self {
        Self::new().expect("Failed to create script manager")
    }
}

// ============ Tests ============

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_script_engine() {
        let engine = ScriptEngine::new().unwrap();

        // Test basic Lua execution
        engine.execute("rf.print('Hello from Lua!')").unwrap();

        // Test utility functions
        let db: f64 = engine.eval("return rf.linear_to_db(1.0)").unwrap();
        assert!((db - 0.0).abs() < 0.001);

        let linear: f64 = engine.eval("return rf.db_to_linear(-6.0)").unwrap();
        assert!((linear - 0.5012).abs() < 0.01);
    }

    #[test]
    fn test_script_actions() {
        let engine = ScriptEngine::new().unwrap();

        engine.execute("rf.play()").unwrap();
        engine.execute("rf.set_playhead(48000)").unwrap();
        engine.execute("rf.create_track('Test', 'audio')").unwrap();

        let actions = engine.poll_actions();
        assert_eq!(actions.len(), 3);

        matches!(&actions[0], ScriptAction::Play);
        matches!(&actions[1], ScriptAction::SetPlayhead(48000));
    }

    #[test]
    fn test_script_context() {
        let engine = ScriptEngine::new().unwrap();

        let ctx = ScriptContext {
            playhead: 96000,
            sample_rate: 48000,
            is_playing: true,
            ..Default::default()
        };

        engine.update_context(ctx);

        let playhead: u64 = engine.eval("return rf.context:get_playhead()").unwrap();
        assert_eq!(playhead, 96000);

        let is_playing: bool = engine.eval("return rf.context:is_playing()").unwrap();
        assert!(is_playing);
    }
}
