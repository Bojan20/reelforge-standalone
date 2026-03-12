//! rf-plugin-host — Standalone plugin GUI host helper
//!
//! Uses native AUv3 API (AVAudioUnit + requestViewController) for fully
//! interactive plugin GUIs. Uses [NSApp run] for proper macOS event loop.
//!
//! Protocol (JSON over stdin/stdout):
//!   → {"cmd":"open","plugin_name":"FabFilter Pro-Q 4"}
//!   ← {"status":"ok","msg":"GUI opened"}
//!   → {"cmd":"close"}

use std::ffi::CStr;
use std::io::{self, BufRead, Write as IoWrite};
use std::os::raw::c_char;
use std::sync::Mutex;

use cocoa::appkit::{NSApp, NSApplication, NSBackingStoreBuffered, NSWindow, NSWindowStyleMask};
use cocoa::base::{id, nil, NO, YES};
use cocoa::foundation::{NSPoint, NSRect, NSSize, NSString};
use objc::declare::ClassDecl;
use objc::runtime::{Class, Object, Sel};
use objc::{class, msg_send, sel, sel_impl};

// FFI to our ObjC helper (au_host.m)
type AUHostGuiCallback = extern "C" fn(
    user_data: *mut std::ffi::c_void,
    view: id,
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

// Global state
static COMMANDS: Mutex<Vec<Command>> = Mutex::new(Vec::new());
static PLUGINS: Mutex<Vec<PluginEntry>> = Mutex::new(Vec::new());
static WINDOW: Mutex<Option<usize>> = Mutex::new(None);

extern "C" fn scan_callback(
    _user_data: *mut std::ffi::c_void,
    name: *const c_char,
    _manufacturer: *const c_char,
    comp_type: u32,
    subtype: u32,
    mfr_code: u32,
) {
    let name_str = unsafe { CStr::from_ptr(name) }
        .to_string_lossy()
        .to_string();
    PLUGINS.lock().unwrap().push(PluginEntry {
        name: name_str,
        comp_type,
        subtype,
        mfr_code,
    });
}

extern "C" fn gui_ready_callback(
    _user_data: *mut std::ffi::c_void,
    view: id,
    width: f64,
    height: f64,
) {
    if view == nil {
        send_response("error", "Plugin has no GUI");
        return;
    }

    unsafe {
        let w = if width > 10.0 { width } else { 800.0 };
        let h = if height > 10.0 { height } else { 600.0 };

        let rect = NSRect::new(NSPoint::new(200.0, 200.0), NSSize::new(w, h));
        let style = NSWindowStyleMask::NSTitledWindowMask
            | NSWindowStyleMask::NSClosableWindowMask
            | NSWindowStyleMask::NSMiniaturizableWindowMask
            | NSWindowStyleMask::NSResizableWindowMask;

        let window = NSWindow::alloc(nil)
            .initWithContentRect_styleMask_backing_defer_(rect, style, NSBackingStoreBuffered, YES);

        window.setReleasedWhenClosed_(NO);
        let _: () = msg_send![window, retain];

        let view_class: *const Class = msg_send![view, class];
        let class_name = if !view_class.is_null() {
            (*view_class).name()
        } else {
            "Plugin"
        };

        let title = NSString::alloc(nil).init_str(&format!("Plugin — {}", class_name));
        window.setTitle_(title);

        let _: () = msg_send![view, setAutoresizingMask: 18u64];
        window.setContentView_(view);

        window.center();
        window.makeKeyAndOrderFront_(nil);

        let nsapp: id = msg_send![class!(NSApplication), sharedApplication];
        let _: () = msg_send![nsapp, activateIgnoringOtherApps: YES];
        let _: () = msg_send![window, makeFirstResponder: view];

        *WINDOW.lock().unwrap() = Some(window as usize);

        eprintln!("[rf-plugin-host] Window {}x{} view={}", w, h, class_name);
    }

    send_response("ok", "GUI opened");
}

/// NSTimer callback — polls for stdin commands
extern "C" fn timer_fired(_this: &Object, _sel: Sel, _timer: id) {
    let commands: Vec<Command> = COMMANDS.lock().unwrap().drain(..).collect();

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

                let plugins = PLUGINS.lock().unwrap();
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
                if let Some(window_ptr) = WINDOW.lock().unwrap().take() {
                    unsafe {
                        let window = window_ptr as id;
                        let _: () = msg_send![window, close];
                        let _: () = msg_send![window, release];
                    }
                }
                unsafe {
                    au_host_close();
                }
                send_response("ok", "closed");
                unsafe {
                    let nsapp: id = msg_send![class!(NSApplication), sharedApplication];
                    let _: () = msg_send![nsapp, terminate: nil];
                }
            }
            _ => {
                send_response("error", &format!("Unknown command: {}", cmd.cmd));
            }
        }
    }
}

fn main() {
    unsafe {
        let nsapp = NSApp();
        nsapp.setActivationPolicy_(
            cocoa::appkit::NSApplicationActivationPolicy::NSApplicationActivationPolicyAccessory,
        );
    }

    // Scan all AU plugins
    unsafe {
        au_host_scan_plugins(std::ptr::null_mut(), scan_callback);
    }

    let count = PLUGINS.lock().unwrap().len();
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
                            COMMANDS.lock().unwrap().push(cmd);
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
        COMMANDS.lock().unwrap().push(Command {
            cmd: "close".to_string(),
            plugin_name: String::new(),
        });
    });

    // Timer for polling stdin commands on main thread
    unsafe {
        let superclass = Class::get("NSObject").unwrap();
        let mut decl = ClassDecl::new("RFTimerTarget", superclass).unwrap();
        decl.add_method(
            sel!(timerFired:),
            timer_fired as extern "C" fn(&Object, Sel, id),
        );
        decl.register();

        let target_class = Class::get("RFTimerTarget").unwrap();
        let target: id = msg_send![target_class, alloc];
        let target: id = msg_send![target, init];

        let interval: f64 = 1.0 / 60.0;
        let _timer: id = msg_send![
            class!(NSTimer),
            scheduledTimerWithTimeInterval: interval
            target: target
            selector: sel!(timerFired:)
            userInfo: nil
            repeats: YES
        ];

        // [NSApp run] — proper macOS event loop
        let nsapp: id = msg_send![class!(NSApplication), sharedApplication];
        let _: () = msg_send![nsapp, run];
    }
}
