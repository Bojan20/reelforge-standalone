//! rf-plugin-host — Standalone plugin GUI host helper
//!
//! Uses native AUv3 API (AVAudioUnit + requestViewController) for fully
//! interactive plugin GUIs. Uses [NSApp run] for proper macOS event loop.
//!
//! # Protocol (JSON, line-delimited, over stdin/stdout)
//!
//! ## Commands (parent → child)
//!
//! | cmd         | extra fields                  | effect                               |
//! |-------------|-------------------------------|--------------------------------------|
//! | `open`      | `plugin_name: String`         | Open plugin GUI by fuzzy name match  |
//! | `close`     | —                             | Close window + terminate process      |
//! | `ping`      | —                             | Health check; replies with pong       |
//! | `list`      | —                             | Stream `{plugin: "name"}` lines       |
//! | `set_size`  | `width: f64`, `height: f64`   | Resize the live plugin window         |
//!
//! ## Responses (child → parent)
//!
//!   `{"status":"ok","msg":"ready, N plugins"}`     (on launch)
//!   `{"status":"ok","msg":"GUI opened"}`           (after open)
//!   `{"status":"ok","msg":"pong"}`                  (after ping)
//!   `{"status":"ok","msg":"closed"}`               (after close)
//!   `{"status":"error","msg":"<reason>"}`          (any error)
//!
//! # Parent-death detection
//!
//! On launch, env var `RF_PARENT_PID` (set by `GuiSession::spawn`) names
//! the parent's PID. A 1 Hz NSTimer polls `kill(pid, 0)`; when the parent
//! is gone (kill returns ESRCH), the host calls `[NSApp terminate]` to
//! avoid orphaned plugin windows after a DAW crash.

use std::ffi::CStr;
use std::io::{self, BufRead, Write as IoWrite};
use std::os::raw::c_char;
use std::sync::Mutex;

use objc2::rc::Retained;
use objc2::runtime::{AnyClass, AnyObject, Bool, Sel};
use objc2::{class, msg_send, sel};
use objc2::declare::ClassBuilder;
use objc2_foundation::{NSString, NSPoint, NSRect, NSSize, MainThreadMarker};
use objc2_app_kit::{
    NSApplication, NSApplicationActivationPolicy, NSBackingStoreType, NSWindow,
    NSWindowStyleMask,
};

// FFI to our ObjC helper (au_host.m)
// These use raw `*mut AnyObject` instead of cocoa `id`
type AUHostGuiCallback = extern "C" fn(
    user_data: *mut std::ffi::c_void,
    view: *mut AnyObject,
    width: f64,
    height: f64,
);

type AUHostScanCallback = extern "C" fn(
    user_data: *mut std::ffi::c_void,
    name: *const c_char,
    manufacturer: *const c_char,
    comp_type: u32,
    subtype: u32,
    mfr_code: u32,
);

unsafe extern "C" {
    fn au_host_open_plugin(
        component_type: u32,
        component_subtype: u32,
        component_manufacturer: u32,
        user_data: *mut std::ffi::c_void,
        callback: AUHostGuiCallback,
    );
    fn au_host_close();
    fn au_host_scan_plugins(user_data: *mut std::ffi::c_void, callback: AUHostScanCallback);
}

#[derive(serde::Deserialize)]
struct Command {
    cmd: String,
    #[serde(default)]
    plugin_name: String,
    #[serde(default)]
    width: f64,
    #[serde(default)]
    height: f64,
}

#[derive(serde::Serialize)]
struct Response {
    status: String,
    msg: String,
}

fn send_response(status: &str, msg: &str) {
    let resp = Response {
        status: status.to_string(),
        msg: msg.to_string(),
    };
    if let Ok(json) = serde_json::to_string(&resp) {
        let stdout = io::stdout();
        let mut out = stdout.lock();
        let _ = writeln!(out, "{}", json);
        let _ = out.flush();
    }
}

#[derive(Clone)]
struct PluginEntry {
    name: String,
    comp_type: u32,
    subtype: u32,
    mfr_code: u32,
}

/// Send+Sync wrapper for a raw ObjC pointer. SAFETY: we only touch
/// the wrapped pointer on the main thread; the Mutex is purely for
/// satisfying the `static` requirement.
struct SendPtr(*mut AnyObject);
unsafe impl Send for SendPtr {}
unsafe impl Sync for SendPtr {}

// Global state
static COMMANDS: Mutex<Vec<Command>> = Mutex::new(Vec::new());
static PLUGINS: Mutex<Vec<PluginEntry>> = Mutex::new(Vec::new());
static WINDOW: Mutex<Option<SendPtr>> = Mutex::new(None);
/// Parent process PID, set from RF_PARENT_PID env var on launch.
/// 0 = not set / disabled.
static PARENT_PID: Mutex<u32> = Mutex::new(0);

extern "C" fn scan_callback(
    _user_data: *mut std::ffi::c_void,
    name: *const c_char,
    _manufacturer: *const c_char,
    comp_type: u32,
    subtype: u32,
    mfr_code: u32,
) {
    if name.is_null() {
        return;
    }
    let name_str = unsafe { CStr::from_ptr(name) }
        .to_string_lossy()
        .to_string();
    if let Ok(mut plugins) = PLUGINS.lock() {
        plugins.push(PluginEntry {
            name: name_str,
            comp_type,
            subtype,
            mfr_code,
        });
    } else {
        eprintln!("[rf-plugin-host] PLUGINS lock poisoned in scan_callback");
    }
}

extern "C" fn gui_ready_callback(
    _user_data: *mut std::ffi::c_void,
    view: *mut AnyObject,
    width: f64,
    height: f64,
) {
    if view.is_null() {
        send_response("error", "Plugin has no GUI");
        return;
    }

    unsafe {
        let w = if width > 10.0 { width } else { 800.0 };
        let h = if height > 10.0 { height } else { 600.0 };

        let rect = NSRect::new(NSPoint::new(200.0, 200.0), NSSize::new(w, h));
        let style = NSWindowStyleMask::Titled
            | NSWindowStyleMask::Closable
            | NSWindowStyleMask::Miniaturizable
            | NSWindowStyleMask::Resizable;

        let mtm = MainThreadMarker::new_unchecked();
        let window = NSWindow::initWithContentRect_styleMask_backing_defer(
            mtm.alloc::<NSWindow>(),
            rect,
            style,
            NSBackingStoreType::Buffered,
            false,
        );

        window.setReleasedWhenClosed(false);

        // Get view class name for title
        let view_class: *const AnyClass = msg_send![view, class];
        let class_name: String = if !view_class.is_null() {
            (*view_class).name().to_string_lossy().to_string()
        } else {
            "Plugin".to_string()
        };

        let title = NSString::from_str(&format!("Plugin — {}", class_name));
        window.setTitle(&title);

        // Set autoresizing mask: NSViewWidthSizable (2) | NSViewHeightSizable (16) = 18
        let _: () = msg_send![view, setAutoresizingMask: 18u64];

        // Set view as content
        let _: () = msg_send![&*window, setContentView: view];

        window.center();
        window.makeKeyAndOrderFront(None);

        // Activate app
        let app = NSApplication::sharedApplication(mtm);
        #[allow(deprecated)]
        app.activateIgnoringOtherApps(true);

        let _: () = msg_send![&*window, makeFirstResponder: view];

        eprintln!("[rf-plugin-host] Window {}x{} view={}", w, h, class_name);

        // Store raw pointer; Retained::into_raw transfers ownership (prevents drop/release)
        let raw: *const NSWindow = Retained::into_raw(window);
        match WINDOW.lock() {
            Ok(mut w) => *w = Some(SendPtr(raw as *mut AnyObject)),
            Err(e) => {
                eprintln!("[rf-plugin-host] WINDOW lock poisoned: {}", e);
                *e.into_inner() = Some(SendPtr(raw as *mut AnyObject));
            }
        }
    }

    send_response("ok", "GUI opened");
}

/// NSTimer callback — polls for stdin commands
unsafe extern "C" fn timer_fired(_this: *mut AnyObject, _sel: Sel, _timer: *mut AnyObject) {
    let commands: Vec<Command> = match COMMANDS.lock() {
        Ok(mut cmds) => cmds.drain(..).collect(),
        Err(e) => {
            eprintln!("[rf-plugin-host] COMMANDS lock poisoned in timer_fired");
            e.into_inner().drain(..).collect()
        }
    };

    for cmd in commands {
        match cmd.cmd.as_str() {
            "open" => {
                let needle = cmd
                    .plugin_name
                    .to_lowercase()
                    .replace([':', '-', '_'], " ")
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ");

                let plugins = match PLUGINS.lock() {
                    Ok(p) => p,
                    Err(e) => {
                        eprintln!("[rf-plugin-host] PLUGINS lock poisoned");
                        e.into_inner()
                    }
                };
                let found = plugins.iter().find(|p| {
                    let norm = p
                        .name
                        .to_lowercase()
                        .replace([':', '-', '_'], " ")
                        .split_whitespace()
                        .collect::<Vec<_>>()
                        .join(" ");
                    norm == needle || norm.contains(&needle) || needle.contains(&norm)
                });

                match found {
                    Some(entry) => {
                        let entry = entry.clone();
                        drop(plugins);

                        eprintln!(
                            "[rf-plugin-host] Opening '{}' type={:08x} sub={:08x} mfr={:08x}",
                            entry.name, entry.comp_type, entry.subtype, entry.mfr_code
                        );

                        unsafe {
                            au_host_open_plugin(
                                entry.comp_type,
                                entry.subtype,
                                entry.mfr_code,
                                std::ptr::null_mut(),
                                gui_ready_callback,
                            );
                        }
                    }
                    None => {
                        drop(plugins);
                        send_response(
                            "error",
                            &format!("Plugin not found: {}", cmd.plugin_name),
                        );
                    }
                }
            }
            "close" => {
                let win_ptr = match WINDOW.lock() {
                    Ok(mut w) => w.take(),
                    Err(e) => {
                        eprintln!("[rf-plugin-host] WINDOW lock poisoned in close");
                        e.into_inner().take()
                    }
                };
                if let Some(SendPtr(raw)) = win_ptr {
                    unsafe {
                        // Reconstruct Retained from raw pointer, close, then let it drop (release)
                        if let Some(window) = Retained::<NSWindow>::from_raw(raw.cast()) {
                            window.close();
                        } else {
                            eprintln!("[rf-plugin-host] Failed to reconstruct NSWindow from raw pointer");
                        }
                    }
                }
                unsafe {
                    au_host_close();
                }
                send_response("ok", "closed");

                let mtm = unsafe { MainThreadMarker::new_unchecked() };
                let app = NSApplication::sharedApplication(mtm);
                app.terminate(None);
            }
            "ping" => {
                send_response("ok", "pong");
            }
            "list" => {
                let plugins = match PLUGINS.lock() {
                    Ok(p) => p,
                    Err(e) => {
                        eprintln!("[rf-plugin-host] PLUGINS lock poisoned in list");
                        e.into_inner()
                    }
                };
                let count = plugins.len();
                for entry in plugins.iter() {
                    // One JSON line per plugin so the parent can stream-parse.
                    let line = format!(
                        "{{\"status\":\"ok\",\"msg\":\"plugin: {}\"}}",
                        entry.name.replace('"', "\\\"")
                    );
                    let stdout = io::stdout();
                    let mut out = stdout.lock();
                    let _ = writeln!(out, "{}", line);
                    let _ = out.flush();
                }
                drop(plugins);
                send_response("ok", &format!("listed {} plugins", count));
            }
            "set_size" => {
                let win_ptr_opt = match WINDOW.lock() {
                    Ok(w) => w.as_ref().map(|SendPtr(p)| *p),
                    Err(e) => {
                        eprintln!("[rf-plugin-host] WINDOW lock poisoned in set_size");
                        e.into_inner().as_ref().map(|SendPtr(p)| *p)
                    }
                };
                match win_ptr_opt {
                    Some(raw) if !raw.is_null() => {
                        let w = if cmd.width > 50.0 { cmd.width } else { 800.0 };
                        let h = if cmd.height > 50.0 { cmd.height } else { 600.0 };
                        unsafe {
                            // Get current frame, replace size, keep origin.
                            let frame: NSRect = msg_send![raw, frame];
                            let new_frame = NSRect::new(
                                frame.origin,
                                NSSize::new(w, h),
                            );
                            let _: () = msg_send![raw, setFrame: new_frame, display: true, animate: true];
                        }
                        send_response("ok", &format!("resized to {}x{}", w as u32, h as u32));
                    }
                    _ => {
                        send_response("error", "no window open");
                    }
                }
            }
            _ => {
                send_response("error", &format!("Unknown command: {}", cmd.cmd));
            }
        }
    }
}

/// Parent-pid watcher — fires once per second. If the parent process is
/// gone (DAW crashed), terminate ourselves so the plugin window doesn't
/// linger as a zombie after the user expected the DAW to take it.
unsafe extern "C" fn parent_watch_fired(_this: *mut AnyObject, _sel: Sel, _timer: *mut AnyObject) {
    let parent_pid = match PARENT_PID.lock() {
        Ok(p) => *p,
        Err(e) => *e.into_inner(),
    };
    if parent_pid == 0 {
        return; // Not configured.
    }
    // SAFETY: kill(pid, 0) is the standard "is this PID alive" probe;
    // returns 0 if alive (we have permission to signal), -1/ESRCH if gone.
    unsafe {
        let result = libc_kill(parent_pid as i32, 0);
        if result != 0 {
            let errno = *libc_errno();
            // ESRCH = 3 on macOS; parent is gone.
            if errno == 3 {
                eprintln!("[rf-plugin-host] parent PID {} gone — terminating", parent_pid);
                let mtm = MainThreadMarker::new_unchecked();
                let app = NSApplication::sharedApplication(mtm);
                app.terminate(None);
            }
        }
    }
}

unsafe extern "C" {
    #[link_name = "kill"]
    fn libc_kill(pid: i32, sig: i32) -> i32;
    #[link_name = "__error"]
    fn libc_errno() -> *mut i32;
}

fn main() {
    let mtm = MainThreadMarker::new().expect("must run on main thread");
    let app = NSApplication::sharedApplication(mtm);
    app.setActivationPolicy(NSApplicationActivationPolicy::Accessory);

    // Read parent PID from env so we can self-terminate if DAW crashes.
    if let Ok(pid_str) = std::env::var("RF_PARENT_PID")
        && let Ok(pid) = pid_str.parse::<u32>()
    {
        match PARENT_PID.lock() {
            Ok(mut g) => *g = pid,
            Err(e) => *e.into_inner() = pid,
        }
        eprintln!("[rf-plugin-host] parent PID = {}", pid);
    }

    // Scan all AU plugins
    unsafe {
        au_host_scan_plugins(std::ptr::null_mut(), scan_callback);
    }

    let count = PLUGINS.lock().map(|p| p.len()).unwrap_or(0);
    send_response("ok", &format!("ready, {} plugins", count));

    // Stdin reader thread
    std::thread::spawn(move || {
        let stdin = io::stdin();
        for line in stdin.lock().lines() {
            match line {
                Ok(line) => {
                    if line.trim().is_empty() {
                        continue;
                    }
                    match serde_json::from_str::<Command>(&line) {
                        Ok(cmd) => {
                            match COMMANDS.lock() {
                                Ok(mut cmds) => cmds.push(cmd),
                                Err(e) => {
                                    eprintln!("[rf-plugin-host] COMMANDS lock poisoned in stdin reader");
                                    e.into_inner().push(cmd);
                                }
                            }
                        }
                        Err(e) => {
                            eprintln!("[rf-plugin-host] Parse error: {}", e);
                        }
                    }
                }
                Err(_) => break,
            }
        }
        eprintln!("[rf-plugin-host] stdin closed");
        let close_cmd = Command {
            cmd: "close".to_string(),
            plugin_name: String::new(),
            width: 0.0,
            height: 0.0,
        };
        match COMMANDS.lock() {
            Ok(mut cmds) => cmds.push(close_cmd),
            Err(e) => {
                eprintln!("[rf-plugin-host] COMMANDS lock poisoned on stdin close");
                e.into_inner().push(close_cmd);
            }
        }
    });

    // Timer for polling stdin commands on main thread
    unsafe {
        let Some(superclass) = AnyClass::get(c"NSObject") else {
            eprintln!("[rf-plugin-host] FATAL: NSObject class not found");
            return;
        };
        let Some(mut builder) = ClassBuilder::new(c"RFTimerTarget", superclass) else {
            eprintln!("[rf-plugin-host] FATAL: Failed to create RFTimerTarget class");
            return;
        };
        builder.add_method(
            sel!(timerFired:),
            timer_fired as unsafe extern "C" fn(*mut AnyObject, Sel, *mut AnyObject),
        );
        let target_class = builder.register();
        let target: *mut AnyObject = msg_send![target_class, alloc];
        let target: *mut AnyObject = msg_send![target, init];

        let interval: f64 = 1.0 / 60.0;
        let nil: *mut AnyObject = std::ptr::null_mut();
        let _timer: *mut AnyObject = msg_send![
            class!(NSTimer),
            scheduledTimerWithTimeInterval: interval,
            target: target,
            selector: sel!(timerFired:),
            userInfo: nil,
            repeats: Bool::YES
        ];

        // Parent-watch timer: only schedule if RF_PARENT_PID was provided.
        let parent_pid = match PARENT_PID.lock() {
            Ok(g) => *g,
            Err(e) => *e.into_inner(),
        };
        if parent_pid != 0 {
            let Some(parent_superclass) = AnyClass::get(c"NSObject") else {
                eprintln!("[rf-plugin-host] FATAL: NSObject class not found (parent watch)");
                return;
            };
            let Some(mut parent_builder) = ClassBuilder::new(c"RFParentWatchTarget", parent_superclass) else {
                eprintln!("[rf-plugin-host] FATAL: Failed to create RFParentWatchTarget class");
                return;
            };
            parent_builder.add_method(
                sel!(parentWatchFired:),
                parent_watch_fired as unsafe extern "C" fn(*mut AnyObject, Sel, *mut AnyObject),
            );
            let parent_class = parent_builder.register();
            let parent_target: *mut AnyObject = msg_send![parent_class, alloc];
            let parent_target: *mut AnyObject = msg_send![parent_target, init];

            let parent_interval: f64 = 1.0; // 1 Hz
            let _parent_timer: *mut AnyObject = msg_send![
                class!(NSTimer),
                scheduledTimerWithTimeInterval: parent_interval,
                target: parent_target,
                selector: sel!(parentWatchFired:),
                userInfo: nil,
                repeats: Bool::YES
            ];
            eprintln!("[rf-plugin-host] parent-watch timer armed (1 Hz)");
        }

        // [NSApp run] — proper macOS event loop
        app.run();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_command_parse_open() {
        let json = r#"{"cmd":"open","plugin_name":"FabFilter Pro-Q 4"}"#;
        let cmd: Command = serde_json::from_str(json).unwrap();
        assert_eq!(cmd.cmd, "open");
        assert_eq!(cmd.plugin_name, "FabFilter Pro-Q 4");
        assert_eq!(cmd.width, 0.0);
        assert_eq!(cmd.height, 0.0);
    }

    #[test]
    fn test_command_parse_close() {
        let json = r#"{"cmd":"close"}"#;
        let cmd: Command = serde_json::from_str(json).unwrap();
        assert_eq!(cmd.cmd, "close");
        assert_eq!(cmd.plugin_name, ""); // default
    }

    #[test]
    fn test_command_parse_unknown() {
        let json = r#"{"cmd":"unknown_cmd"}"#;
        let cmd: Command = serde_json::from_str(json).unwrap();
        assert_eq!(cmd.cmd, "unknown_cmd");
    }

    #[test]
    fn test_command_parse_ping() {
        let json = r#"{"cmd":"ping"}"#;
        let cmd: Command = serde_json::from_str(json).unwrap();
        assert_eq!(cmd.cmd, "ping");
    }

    #[test]
    fn test_command_parse_list() {
        let json = r#"{"cmd":"list"}"#;
        let cmd: Command = serde_json::from_str(json).unwrap();
        assert_eq!(cmd.cmd, "list");
    }

    #[test]
    fn test_command_parse_set_size() {
        let json = r#"{"cmd":"set_size","width":1024.0,"height":768.0}"#;
        let cmd: Command = serde_json::from_str(json).unwrap();
        assert_eq!(cmd.cmd, "set_size");
        assert_eq!(cmd.width, 1024.0);
        assert_eq!(cmd.height, 768.0);
    }

    #[test]
    fn test_response_serialize() {
        let resp = Response {
            status: "ok".to_string(),
            msg: "ready, 42 plugins".to_string(),
        };
        let json = serde_json::to_string(&resp).unwrap();
        assert!(json.contains("\"status\":\"ok\""));
        assert!(json.contains("42 plugins"));
    }

    #[test]
    fn test_plugin_entry_clone() {
        let entry = PluginEntry {
            name: "Test Plugin".to_string(),
            comp_type: 0x61756678, // 'aufx'
            subtype: 0x46504551,   // 'FPEQ'
            mfr_code: 0x46614669,  // 'FaFi'
        };
        let cloned = entry.clone();
        assert_eq!(cloned.name, "Test Plugin");
        assert_eq!(cloned.comp_type, 0x61756678);
    }

    #[test]
    fn test_command_empty_json() {
        let result = serde_json::from_str::<Command>("{}");
        // cmd is required — should fail
        assert!(result.is_err());
    }

    #[test]
    fn test_fuzzy_name_normalization() {
        // Simulate the normalization logic from timer_fired
        let input = "FabFilter:Pro-Q_4";
        let normalized = input
            .to_lowercase()
            .replace([':', '-', '_'], " ")
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ");
        assert_eq!(normalized, "fabfilter pro q 4");
    }
}
