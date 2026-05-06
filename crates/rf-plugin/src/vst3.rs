//! VST3 Plugin Host
//!
//! Loads and hosts VST3 plugins using the `rack` crate.
//! Handles:
//! - Plugin loading from .vst3 bundles
//! - Audio processing with real-time safety
//! - Parameter automation via lock-free queues
//! - State save/load
//! - Editor hosting (platform-specific)

use std::ffi::c_void;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use parking_lot::{Mutex, RwLock};

use crate::scanner::{PluginCategory, PluginType};
use crate::{
    AudioBuffer, ParameterInfo, PluginError, PluginInfo, PluginInstance, PluginResult,
    ProcessContext,
};

/// Maximum parameter changes per audio block
const MAX_PARAM_CHANGES: usize = 128;

// ═══════════════════════════════════════════════════════════════════════════
// PRE-FLIGHT BUNDLE VALIDATION
// ═══════════════════════════════════════════════════════════════════════════
//
// Pro DAWs reject malformed / quarantined / wrong-arch plugins BEFORE handing
// them to the loader (rack/dlopen). That avoids opaque dlopen panics, AU
// component-not-found segfaults, and Gatekeeper kills inside third-party
// plugin code. We do the same here for VST3 + AudioUnit bundles.

/// Locate the actual executable inside a `.vst3` / `.component` bundle.
/// On non-macOS, just returns the path itself if it's a file.
fn locate_bundle_executable(path: &Path) -> Option<PathBuf> {
    if path.is_file() {
        return Some(path.to_path_buf());
    }
    if path.is_dir() {
        // Standard CFBundle layout: Contents/MacOS/<binary>
        let macos_dir = path.join("Contents").join("MacOS");
        if macos_dir.is_dir() {
            if let Ok(entries) = std::fs::read_dir(&macos_dir) {
                for entry in entries.flatten() {
                    let p = entry.path();
                    if p.is_file() {
                        return Some(p);
                    }
                }
            }
        }
    }
    None
}

/// Verify the file starts with a Mach-O magic number. Catches dragged
/// shortcuts, zero-byte stubs, broken downloads, and accidentally-installed
/// Windows .dll plugins long before dlopen would crash on them.
fn check_mach_o_magic(path: &Path) -> Result<(), String> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)
        .map_err(|e| format!("cannot open binary {:?}: {}", path, e))?;
    let mut magic = [0u8; 4];
    if file.read_exact(&mut magic).is_err() {
        return Err(format!("binary too short: {:?}", path));
    }
    let m_be = u32::from_be_bytes(magic);
    let m_le = u32::from_le_bytes(magic);
    // Mach-O thin (FE ED FA CE / CF) and fat (CA FE BA BE / BF)
    const VALID: [u32; 4] = [0xCAFE_BABE, 0xCAFE_BABF, 0xFEED_FACE, 0xFEED_FACF];
    if VALID.contains(&m_be) || VALID.contains(&m_le) {
        Ok(())
    } else {
        Err(format!(
            "not a Mach-O binary ({}: magic={:08X})",
            path.display(),
            m_be
        ))
    }
}

/// macOS Gatekeeper sets `com.apple.quarantine` xattr on downloaded files.
/// AudioUnit / VST3 bundles with this attribute will be rejected by the
/// kernel during init or load partway through, sometimes silently. Reject
/// upfront with an actionable error message.
#[cfg(target_os = "macos")]
fn check_quarantine(path: &Path) -> Result<(), String> {
    use std::ffi::CString;
    use std::os::raw::{c_char, c_int};

    unsafe extern "C" {
        fn getxattr(
            path: *const c_char,
            name: *const c_char,
            value: *mut c_void,
            size: usize,
            position: u32,
            options: c_int,
        ) -> isize;
    }

    let path_str = path.to_string_lossy();
    let Ok(c_path) = CString::new(path_str.as_bytes()) else {
        return Ok(());
    };
    let c_name = CString::new("com.apple.quarantine").expect("static literal has no NUL");

    let res = unsafe {
        getxattr(
            c_path.as_ptr(),
            c_name.as_ptr(),
            std::ptr::null_mut(),
            0,
            0,
            0,
        )
    };

    if res >= 0 {
        Err(format!(
            "plugin is quarantined by Gatekeeper. Run in Terminal:  xattr -dr com.apple.quarantine \"{}\"",
            path.display()
        ))
    } else {
        Ok(())
    }
}

#[cfg(not(target_os = "macos"))]
fn check_quarantine(_path: &Path) -> Result<(), String> {
    Ok(())
}

/// Run all pre-flight checks. Returns Ok(()) if the bundle looks safe to load,
/// or Err with a human-readable reason that's safe to surface in the UI.
fn pre_flight_validate(bundle_path: &Path) -> Result<(), String> {
    if !bundle_path.exists() {
        return Err(format!("plugin bundle not found: {}", bundle_path.display()));
    }

    // Quarantine check applies to the bundle itself.
    check_quarantine(bundle_path)?;

    // Mach-O check applies to the actual executable inside the bundle.
    let exe = locate_bundle_executable(bundle_path).ok_or_else(|| {
        format!(
            "could not locate executable inside bundle: {}",
            bundle_path.display()
        )
    })?;
    check_mach_o_magic(&exe)?;

    Ok(())
}

/// Register ObjC runtime subclasses for plugin GUI hosting.
/// Called once — creates FFPluginWindow (NSWindow subclass) and
/// FFPluginContainerView (NSView subclass with acceptsFirstMouse).
/// Based on baseview (RustAudio) and JUCE patterns.
#[cfg(target_os = "macos")]
fn register_plugin_window_classes() {
    use objc2::declare::ClassBuilder;
    use objc2::runtime::{AnyClass, AnyObject, Bool, Sel};
    use objc2::{sel, msg_send};
    use objc2_foundation::NSPoint;

    static REGISTERED: std::sync::Once = std::sync::Once::new();
    REGISTERED.call_once(|| {
        unsafe {
            // --- FFPluginWindow: NSWindow that always accepts key/main ---
            let Some(ns_window) = AnyClass::get(c"NSWindow") else {
                eprintln!("[FluxForge] FATAL: NSWindow class not found in ObjC runtime");
                return;
            };
            let Some(mut window_builder) = ClassBuilder::new(c"FFPluginWindow", ns_window) else {
                eprintln!("[FluxForge] FATAL: Failed to create FFPluginWindow class builder");
                return;
            };

            unsafe extern "C" fn can_become_key(_this: *mut AnyObject, _sel: Sel) -> Bool {
                Bool::YES
            }
            unsafe extern "C" fn can_become_main(_this: *mut AnyObject, _sel: Sel) -> Bool {
                Bool::YES
            }

            // Debug: log sendEvent + hitTest for mouseDown
            unsafe extern "C" fn send_event(this: *mut AnyObject, _sel: Sel, event: *mut AnyObject) {
                unsafe {
                    let etype: u64 = msg_send![event, r#type];
                    if etype == 1 { // mouseDown
                        let location: NSPoint = msg_send![event, locationInWindow];
                        let content_view: *mut AnyObject = msg_send![this, contentView];
                        let local: NSPoint = msg_send![content_view, convertPoint: location, fromView:std::ptr::null_mut::<AnyObject>()];
                        let hit: *mut AnyObject = msg_send![content_view, hitTest: local];
                        if !hit.is_null() {
                            let cls: *mut AnyObject = msg_send![hit, class];
                            let name: *mut AnyObject = msg_send![cls, className];
                            let cstr: *const i8 = msg_send![name, UTF8String];
                            let n = if cstr.is_null() { "?" } else { std::ffi::CStr::from_ptr(cstr).to_str().unwrap_or("?") };
                            let super_cls: *mut AnyObject = msg_send![cls, superclass];
                            let super_name: *mut AnyObject = msg_send![super_cls, className];
                            let scstr: *const i8 = msg_send![super_name, UTF8String];
                            let sn = if scstr.is_null() { "?" } else { std::ffi::CStr::from_ptr(scstr).to_str().unwrap_or("?") };
                            eprintln!("[FFPluginWindow] mouseDown at ({:.0},{:.0}) hit={} super={}", local.x, local.y, n, sn);
                            // Check view hierarchy depth
                            let mut v: *mut AnyObject = hit;
                            let mut depth = 0;
                            while !v.is_null() {
                                let parent: *mut AnyObject = msg_send![v, superview];
                                v = parent;
                                depth += 1;
                                if depth > 20 { break; }
                            }
                            eprintln!("[FFPluginWindow] view depth={}", depth);
                        } else {
                            eprintln!("[FFPluginWindow] mouseDown hitTest=nil at ({:.0},{:.0})", local.x, local.y);
                        }
                    }
                    // Call super
                    if let Some(superclass) = AnyClass::get(c"NSWindow") {
                        let send_event_sel = sel!(sendEvent:);
                        if let Some(method) = superclass.instance_method(send_event_sel) {
                            let imp: unsafe extern "C" fn(*mut AnyObject, Sel, *mut AnyObject) =
                                std::mem::transmute(method.implementation());
                            imp(this, send_event_sel, event);
                        }
                    }
                }
            }

            window_builder.add_method(
                sel!(canBecomeKeyWindow),
                can_become_key as unsafe extern "C" fn(*mut AnyObject, Sel) -> Bool,
            );
            window_builder.add_method(
                sel!(canBecomeMainWindow),
                can_become_main as unsafe extern "C" fn(*mut AnyObject, Sel) -> Bool,
            );
            window_builder.add_method(
                sel!(sendEvent:),
                send_event as unsafe extern "C" fn(*mut AnyObject, Sel, *mut AnyObject),
            );
            window_builder.register();

            // --- FFPluginContainerView: NSView with acceptsFirstMouse ---
            // Without this, first click on non-key window just focuses it
            // but does NOT deliver mouseDown to the plugin view.
            let Some(ns_view) = AnyClass::get(c"NSView") else {
                eprintln!("[FluxForge] FATAL: NSView class not found in ObjC runtime");
                return;
            };
            let Some(mut view_builder) = ClassBuilder::new(c"FFPluginContainerView", ns_view) else {
                eprintln!("[FluxForge] FATAL: Failed to create FFPluginContainerView class builder");
                return;
            };

            unsafe extern "C" fn accepts_first_mouse(_this: *mut AnyObject, _sel: Sel, _event: *mut AnyObject) -> Bool {
                Bool::YES
            }
            unsafe extern "C" fn accepts_first_responder(_this: *mut AnyObject, _sel: Sel) -> Bool {
                Bool::YES
            }
            // NOTE: do NOT override isFlipped — use NSView default (origin bottom-left)
            // Plugin views use unflipped coordinates

            unsafe extern "C" fn container_mouse_down(this: *mut AnyObject, _sel: Sel, event: *mut AnyObject) {
                unsafe {
                    eprintln!("[FFContainer] mouseDown received! Forwarding to subviews");
                    // Forward to subviews via hitTest
                    let location: NSPoint = msg_send![event, locationInWindow];
                    let local: NSPoint = msg_send![this, convertPoint: location, fromView:std::ptr::null_mut::<AnyObject>()];
                    eprintln!("[FFContainer] click at ({:.0}, {:.0})", local.x, local.y);
                    let hit: *mut AnyObject = msg_send![this, hitTest: local];
                    if !hit.is_null() && hit != this {
                        let class_name: *mut AnyObject = msg_send![hit, className];
                        let cstr: *const i8 = msg_send![class_name, UTF8String];
                        let name = if cstr.is_null() { "?" } else { std::ffi::CStr::from_ptr(cstr).to_str().unwrap_or("?") };
                        eprintln!("[FFContainer] hitTest found: {} — forwarding mouseDown", name);
                        let _: () = msg_send![hit, mouseDown: event];
                    } else {
                        eprintln!("[FFContainer] hitTest returned self or nil");
                    }
                }
            }

            view_builder.add_method(
                sel!(acceptsFirstMouse:),
                accepts_first_mouse as unsafe extern "C" fn(*mut AnyObject, Sel, *mut AnyObject) -> Bool,
            );
            view_builder.add_method(
                sel!(acceptsFirstResponder),
                accepts_first_responder as unsafe extern "C" fn(*mut AnyObject, Sel) -> Bool,
            );
            // isFlipped NOT overridden — keep default NSView coords
            view_builder.add_method(
                sel!(mouseDown:),
                container_mouse_down as unsafe extern "C" fn(*mut AnyObject, Sel, *mut AnyObject),
            );
            view_builder.register();
        }
    });
}

/// Create a standalone NSWindow hosting a plugin's NSView.
///
/// Minimal approach matching rack's show_window() but using cocoa crate
/// for ABI-correct message dispatch. setContentView: gives plugin view
/// full control over the window's responder chain.
///
/// SAFETY: Must be called from the main thread. `view_ptr` must be a valid NSView*.
#[cfg(target_os = "macos")]
unsafe fn create_plugin_window(view_ptr: *mut c_void, width: f64, height: f64, title: &str) {
    use objc2::runtime::{AnyClass, AnyObject, Bool};
    use objc2::msg_send;
    use objc2_foundation::{NSPoint, NSRect, NSSize, NSString};

    register_plugin_window_classes();

    objc2::rc::autoreleasepool(|_| {
        let rect = NSRect::new(
            NSPoint::new(200.0, 200.0),
            NSSize::new(width, height),
        );

        // FFPluginWindow: canBecomeKeyWindow/canBecomeMainWindow -> YES
        let Some(window_cls) = AnyClass::get(c"FFPluginWindow") else {
            eprintln!("[FluxForge] FFPluginWindow class not registered, cannot create plugin window");
            return;
        };
        let window: *mut AnyObject = msg_send![window_cls, alloc];
        let window: *mut AnyObject = msg_send![window,
            initWithContentRect: rect,
            styleMask: 15u64,
            backing: 2u64,
            defer: Bool::NO
        ];

        if window.is_null() {
            eprintln!("[FluxForge] Failed to create FFPluginWindow");
            return;
        }

        let _: () = msg_send![window, setReleasedWhenClosed: Bool::NO];

        let ns_title = NSString::from_str(title);
        let _: () = msg_send![window, setTitle: &*ns_title];

        // CRITICAL: Set wantsLayer on content view but use canDrawSubviewsIntoLayer
        // to avoid forcing separate CALayers on plugin subviews. This prevents
        // _createLayer crash while keeping plugin's rendering pipeline intact.
        let content_view: *mut AnyObject = msg_send![window, contentView];
        let _: () = msg_send![content_view, setWantsLayer: Bool::YES];
        let _: () = msg_send![content_view, setCanDrawSubviewsIntoLayer: Bool::YES];

        // Add plugin view as subview — do NOT set wantsLayer on plugin view
        // Plugin manages its own rendering (Metal/OpenGL/CoreGraphics)
        let plugin_view = view_ptr as *mut AnyObject;
        let view_rect = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(width, height));
        let _: () = msg_send![plugin_view, setFrame: view_rect];
        let _: () = msg_send![plugin_view, setAutoresizingMask: 18u64];
        let _: () = msg_send![content_view, setAutoresizesSubviews: Bool::YES];
        let _: () = msg_send![content_view, addSubview: plugin_view];

        let _: () = msg_send![window, setAcceptsMouseMovedEvents: Bool::YES];

        let Some(ns_app_class) = AnyClass::get(c"NSApplication") else {
            eprintln!("[FluxForge] NSApplication class not found");
            return;
        };
        let nsapp: *mut AnyObject = msg_send![ns_app_class, sharedApplication];
        #[allow(deprecated)]
        let _: () = msg_send![nsapp, activateIgnoringOtherApps: Bool::YES];

        let _: () = msg_send![window, center];
        let _: () = msg_send![window, makeKeyAndOrderFront: std::ptr::null_mut::<AnyObject>()];
        let _: () = msg_send![window, makeFirstResponder: plugin_view];
        let _: () = msg_send![window, setLevel: 3i64]; // NSFloatingWindowLevel

        let _: () = msg_send![window, retain];

        eprintln!("[FluxForge] FFPluginWindow created {}x{} for '{}'", width as u32, height as u32, title);
    });
}

/// Find the rf-plugin-host binary.
/// Searches: same directory as current executable, Frameworks dir, cargo target dir.
#[cfg(target_os = "macos")]
// Uses crate::find_plugin_host_binary() from lib.rs
/// Result type for rack plugin loading
type RackLoadResult = (
    Option<Arc<Mutex<RackPlugin>>>,
    Vec<ParameterInfo>,
    usize, // input channels
    usize, // output channels
    usize, // latency
    bool,  // has_midi_input (true for Instrument plugins)
);

/// Lock-free parameter change queue entry
#[derive(Debug, Clone, Copy)]
struct ParamChange {
    id: u32,
    value: f64,
}

/// VST3 plugin state for thread-safe access
struct Vst3State {
    /// Cached parameter infos
    parameters: Vec<ParameterInfo>,
    /// Current parameter values (normalized 0-1)
    param_values: Vec<f64>,
}

/// Rack plugin wrapper (type-erased to handle both AudioUnit and VST3)
struct RackPlugin {
    /// The actual rack plugin instance (type-erased via Box<dyn>)
    inner: Box<dyn RackPluginTrait + Send>,
}

/// Trait for rack plugin abstraction
trait RackPluginTrait {
    fn initialize(&mut self, sample_rate: f64, max_block_size: usize) -> Result<(), String>;
    fn reset(&mut self) -> Result<(), String>;
    fn process(
        &mut self,
        inputs: &[&[f32]],
        outputs: &mut [&mut [f32]],
        num_frames: usize,
    ) -> Result<(), String>;
    /// Send MIDI events to the plugin before the next process() call.
    /// Default: no-op (for effect plugins that don't need MIDI).
    fn send_midi(&mut self, _events: &[rack::MidiEvent]) -> Result<(), String> {
        Ok(())
    }
    fn parameter_count(&self) -> usize;
    fn get_parameter(&self, index: usize) -> Result<f32, String>;
    fn set_parameter(&mut self, index: usize, value: f32) -> Result<(), String>;
    fn get_state(&self) -> Result<Vec<u8>, String>;
    fn set_state(&mut self, data: &[u8]) -> Result<(), String>;
    fn latency(&self) -> Option<u32>;

    /// Whether this plugin supports native GUI (AudioUnit on macOS).
    fn supports_gui(&self) -> bool {
        false
    }

    /// Open a standalone window for the plugin's native GUI.
    /// Returns (width, height) if GUI was created successfully.
    /// Default: not supported.
    #[cfg(target_os = "macos")]
    fn open_gui_window(&mut self, _title: &str) -> Result<(f32, f32), String> {
        Err("GUI not supported for this plugin format".into())
    }

    /// Close and drop the native GUI window.
    #[cfg(target_os = "macos")]
    fn close_gui_window(&mut self) {
        // no-op by default
    }

    /// Get the native GUI size (width, height) in points.
    #[cfg(target_os = "macos")]
    fn gui_size(&self) -> Option<(f32, f32)> {
        None
    }
}

/// Wrapper for rack::PluginInstance
struct RackPluginWrapper<P: rack::PluginInstance + Send + 'static> {
    plugin: P,
    latency_samples: u32,
    /// Native GUI handle (macOS AudioUnit only). Stored in Arc<Mutex>
    /// so the async create_gui callback can store the handle without
    /// holding a mutable reference to the wrapper.
    #[cfg(target_os = "macos")]
    gui: Arc<Mutex<Option<rack::au::AudioUnitGui>>>,
}

impl<P: rack::PluginInstance + Send + 'static> RackPluginTrait for RackPluginWrapper<P> {
    fn initialize(&mut self, sample_rate: f64, max_block_size: usize) -> Result<(), String> {
        self.plugin
            .initialize(sample_rate, max_block_size)
            .map_err(|e| format!("{:?}", e))
    }

    fn reset(&mut self) -> Result<(), String> {
        self.plugin.reset().map_err(|e| format!("{:?}", e))
    }

    fn process(
        &mut self,
        inputs: &[&[f32]],
        outputs: &mut [&mut [f32]],
        num_frames: usize,
    ) -> Result<(), String> {
        self.plugin
            .process(inputs, outputs, num_frames)
            .map_err(|e| format!("{:?}", e))
    }

    fn send_midi(&mut self, events: &[rack::MidiEvent]) -> Result<(), String> {
        self.plugin.send_midi(events).map_err(|e| format!("{:?}", e))
    }

    fn parameter_count(&self) -> usize {
        self.plugin.parameter_count()
    }

    fn get_parameter(&self, index: usize) -> Result<f32, String> {
        self.plugin
            .get_parameter(index)
            .map_err(|e| format!("{:?}", e))
    }

    fn set_parameter(&mut self, index: usize, value: f32) -> Result<(), String> {
        self.plugin
            .set_parameter(index, value)
            .map_err(|e| format!("{:?}", e))
    }

    fn get_state(&self) -> Result<Vec<u8>, String> {
        self.plugin.get_state().map_err(|e| format!("{:?}", e))
    }

    fn set_state(&mut self, data: &[u8]) -> Result<(), String> {
        self.plugin.set_state(data).map_err(|e| format!("{:?}", e))
    }

    fn latency(&self) -> Option<u32> {
        Some(self.latency_samples)
    }

    fn supports_gui(&self) -> bool {
        // On macOS, AudioUnitPlugin supports GUI via create_gui()
        #[cfg(target_os = "macos")]
        {
            use std::any::TypeId;
            TypeId::of::<P>() == TypeId::of::<rack::au::AudioUnitPlugin>()
        }
        #[cfg(not(target_os = "macos"))]
        {
            false
        }
    }

    #[cfg(target_os = "macos")]
    fn open_gui_window(&mut self, title: &str) -> Result<(f32, f32), String> {
        use std::any::TypeId;

        if TypeId::of::<P>() != TypeId::of::<rack::au::AudioUnitPlugin>() {
            return Err(
                "GUI not supported for this plugin format (VST3 GUI not available in rack 0.4)"
                    .into(),
            );
        }

        // Spawn out-of-process plugin GUI host.
        // Flutter's Metal rendering pipeline conflicts with plugin GUI rendering
        // in the same process (CALayer/_createLayer crash, or renders but controls
        // are frozen). The rf-plugin-host binary runs in a clean process with its
        // own NSApplication event loop — no Flutter interference.
        let plugin_name = title.to_string();
        eprintln!("[FluxForge] Spawning rf-plugin-host for '{}'", plugin_name);

        // Find the helper binary next to the main app binary
        let helper_path = crate::find_plugin_host_binary();

        match helper_path {
            Some(path) => {
                use std::process::{Command, Stdio};
                use std::io::Write as IoWrite;

                let mut child = Command::new(&path)
                    .stdin(Stdio::piped())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::inherit()) // share stderr for debugging
                    .spawn()
                    .map_err(|e| format!("Failed to spawn rf-plugin-host: {}", e))?;

                // Read "ready" response
                if let Some(ref mut stdout) = child.stdout {
                    use std::io::BufRead;
                    let mut reader = std::io::BufReader::new(stdout);
                    let mut line = String::new();
                    if reader.read_line(&mut line).is_ok() {
                        eprintln!("[FluxForge] plugin-host: {}", line.trim());
                    }
                }

                // Send open command
                if let Some(ref mut stdin) = child.stdin {
                    let cmd = format!("{{\"cmd\":\"open\",\"plugin_name\":\"{}\"}}\n", plugin_name);
                    let _ = stdin.write_all(cmd.as_bytes());
                    let _ = stdin.flush();
                }

                // Store child process handle for cleanup
                // Detach stdin so the process keeps running
                let stdin_handle = child.stdin.take();
                std::thread::spawn(move || {
                    // Keep child alive, read stdout for responses
                    if let Some(stdout) = child.stdout.take() {
                        use std::io::BufRead;
                        let reader = std::io::BufReader::new(stdout);
                        for line in reader.lines().map_while(Result::ok) {
                            eprintln!("[FluxForge] plugin-host: {}", line);
                        }
                    }
                    let _ = child.wait();
                    eprintln!("[FluxForge] plugin-host process ended");
                    drop(stdin_handle); // drop stdin when done
                });

                eprintln!("[FluxForge] rf-plugin-host spawned for '{}'", plugin_name);
                Ok((800.0, 600.0))
            }
            None => {
                Err("rf-plugin-host binary not found".into())
            }
        }
    }

    #[cfg(target_os = "macos")]
    fn close_gui_window(&mut self) {
        if let Some(gui) = self.gui.lock().take()
            && let Err(e) = gui.hide_window() {
                log::warn!("Failed to hide plugin GUI window: {:?}", e);
            }
            // GUI handle is dropped here, cleaning up native resources
    }

    #[cfg(target_os = "macos")]
    fn gui_size(&self) -> Option<(f32, f32)> {
        self.gui.lock().as_ref().and_then(|gui| gui.get_size().ok())
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIDI CONVERSION HELPERS
// ═══════════════════════════════════════════════════════════════════════════

/// Convert rf_core::MidiBuffer events to rack::MidiEvent slice (audio-thread safe,
/// uses stack allocation for up to 256 events; falls back to heap beyond that).
fn rf_core_midi_to_rack_events(midi_in: &rf_core::MidiBuffer) -> Vec<rack::MidiEvent> {
    let mut out = Vec::with_capacity(midi_in.len());
    for event in midi_in.events() {
        let rack_event = match event.data {
            rf_core::MidiEventData::NoteOn { note, velocity } => {
                rack::MidiEvent::note_on(note, velocity.min(127) as u8, event.channel, event.sample_offset)
            }
            rf_core::MidiEventData::NoteOff { note, velocity } => {
                rack::MidiEvent::note_off(note, velocity.min(127) as u8, event.channel, event.sample_offset)
            }
            rf_core::MidiEventData::ControlChange { controller, value } => {
                rack::MidiEvent::control_change(controller, value.min(127) as u8, event.channel, event.sample_offset)
            }
            rf_core::MidiEventData::ProgramChange { program } => {
                rack::MidiEvent::program_change(program, event.channel, event.sample_offset)
            }
            rf_core::MidiEventData::PitchBend { value } => {
                // rf_core: -8192..+8191 centered at 0 → rack: 0..16383 centered at 8192
                let rack_val = ((value as i32) + 8192).clamp(0, 16383) as u16;
                rack::MidiEvent::pitch_bend(rack_val, event.channel, event.sample_offset)
            }
            rf_core::MidiEventData::ChannelPressure { pressure } => {
                rack::MidiEvent::channel_aftertouch(pressure.min(127) as u8, event.channel, event.sample_offset)
            }
            rf_core::MidiEventData::PolyPressure { note, pressure } => {
                rack::MidiEvent::polyphonic_aftertouch(note, pressure.min(127) as u8, event.channel, event.sample_offset)
            }
            rf_core::MidiEventData::TimingClock => rack::MidiEvent::timing_clock(event.sample_offset),
            rf_core::MidiEventData::Start => rack::MidiEvent::start(event.sample_offset),
            rf_core::MidiEventData::Continue => rack::MidiEvent::continue_playback(event.sample_offset),
            rf_core::MidiEventData::Stop => rack::MidiEvent::stop(event.sample_offset),
            rf_core::MidiEventData::ActiveSensing => rack::MidiEvent::active_sensing(event.sample_offset),
            rf_core::MidiEventData::SystemReset => rack::MidiEvent::system_reset(event.sample_offset),
            // SysEx, MTC, SongPosition, SongSelect, TuneRequest — not supported by rack MidiEvent
            _ => continue,
        };
        out.push(rack_event);
    }
    out
}

/// VST3 plugin host implementation using rack crate
pub struct Vst3Host {
    /// Plugin info
    info: PluginInfo,
    /// Is plugin active
    active: AtomicBool,
    /// Processing latency in samples
    latency: AtomicU64,
    /// Plugin state (thread-safe)
    state: RwLock<Vst3State>,
    /// Pending parameter changes (lock-free queue)
    param_queue: Mutex<Vec<ParamChange>>,
    /// Sample rate
    sample_rate: AtomicU64,
    /// Max block size
    max_block_size: usize,
    /// Input bus arrangement
    input_channels: u16,
    /// Output bus arrangement
    output_channels: u16,
    /// Editor is open
    editor_open: AtomicBool,
    /// Has valid plugin module loaded
    module_loaded: bool,
    /// The actual rack plugin instance
    rack_plugin: Option<Arc<Mutex<RackPlugin>>>,
    /// Plugin path for reloading
    plugin_path: std::path::PathBuf,
    /// Temporary input buffers for format conversion
    input_buffers: Mutex<Vec<Vec<f32>>>,
    /// Temporary output buffers for format conversion
    output_buffers: Mutex<Vec<Vec<f32>>>,
    /// macOS AudioUnit GUI handle (kept alive while editor is open)
    #[cfg(target_os = "macos")]
    au_gui: Mutex<Option<rack::au::AudioUnitGui>>,
    /// In-process AU GUI window pointer (NSWindow*) — no subprocess needed
    #[cfg(target_os = "macos")]
    au_window: Mutex<Option<usize>>,
    /// IPlugView COM pointer (Windows/Linux — stored for close_editor cleanup)
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    plug_view: Mutex<Option<*mut c_void>>,
    /// UI library handle (Windows/Linux — keep alive while editor is open)
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    _ui_library: Mutex<Option<Arc<libloading::Library>>>,
}

// SAFETY: All fields are either Sync+Send or protected by atomics/mutexes
unsafe impl Send for Vst3Host {}
unsafe impl Sync for Vst3Host {}

impl Vst3Host {
    /// Load plugin from path (supports both VST3 and AudioUnit via rack crate)
    pub fn load(path: &Path) -> PluginResult<Self> {
        // Get plugin name from path
        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("Unknown Plugin");

        // Detect format from bundle extension
        let ext = path
            .extension()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_lowercase();
        let is_au = ext == "component";
        let (id_prefix, plugin_type) = if is_au {
            ("au", PluginType::AudioUnit)
        } else {
            ("vst3", PluginType::Vst3)
        };
        let id = format!("{}.{}", id_prefix, name.to_lowercase().replace(' ', "_"));

        log::info!(
            "Loading {} plugin: {} from {:?}",
            if is_au { "AudioUnit" } else { "VST3" },
            name,
            path
        );

        // Pre-flight: bundle existence + Mach-O magic + quarantine xattr.
        // Reject malformed / quarantined / wrong-arch plugins BEFORE handing
        // them to rack — that avoids opaque panics inside third-party loader code.
        if let Err(reason) = pre_flight_validate(path) {
            log::warn!("Plugin pre-flight failed for {:?}: {}", path, reason);
            return Err(PluginError::LoadFailed(reason));
        }
        let bundle_exists = true;

        // Try to load with rack crate
        let (rack_plugin, parameters, audio_inputs, audio_outputs, plugin_latency, has_midi_input) =
            match Self::load_with_rack(path) {
                Ok(result) => result,
                Err(e) => {
                    eprintln!("[FluxForge] load_with_rack FAILED for {:?}: {}", path, e);
                    // Fallback to passthrough mode — no native GUI available
                    (None, Self::default_parameters(), 2, 2, 0, false)
                }
            };

        let param_values = parameters.iter().map(|p| p.default).collect();
        let module_loaded = rack_plugin.is_some();

        let info = PluginInfo {
            id,
            name: name.to_string(),
            vendor: String::from("Unknown"),
            version: String::from("1.0.0"),
            plugin_type,
            category: PluginCategory::Effect,
            path: path.to_path_buf(),
            audio_inputs: audio_inputs as u32,
            audio_outputs: audio_outputs as u32,
            has_midi_input,
            has_midi_output: false,
            has_editor: bundle_exists,
            latency: plugin_latency as u32,
            is_shell: false,
            sub_plugins: Vec::new(),
        };

        let state = Vst3State {
            parameters,
            param_values,
        };

        // Pre-allocate buffers for audio format conversion
        let input_buffers = (0..audio_inputs).map(|_| vec![0.0f32; 4096]).collect();
        let output_buffers = (0..audio_outputs).map(|_| vec![0.0f32; 4096]).collect();

        Ok(Self {
            info,
            active: AtomicBool::new(false),
            latency: AtomicU64::new(plugin_latency as u64),
            state: RwLock::new(state),
            param_queue: Mutex::new(Vec::with_capacity(MAX_PARAM_CHANGES)),
            sample_rate: AtomicU64::new(48000),
            max_block_size: 4096,
            input_channels: audio_inputs as u16,
            output_channels: audio_outputs as u16,
            editor_open: AtomicBool::new(false),
            module_loaded,
            rack_plugin,
            plugin_path: path.to_path_buf(),
            input_buffers: Mutex::new(input_buffers),
            output_buffers: Mutex::new(output_buffers),
            #[cfg(target_os = "macos")]
            au_gui: Mutex::new(None),
            #[cfg(target_os = "macos")]
            au_window: Mutex::new(None),
            #[cfg(any(target_os = "windows", target_os = "linux"))]
            plug_view: Mutex::new(None),
            #[cfg(any(target_os = "windows", target_os = "linux"))]
            _ui_library: Mutex::new(None),
        })
    }

    /// Load plugin using rack crate
    ///
    /// Reaper/Cubase approach: scan all system AU plugins via AudioComponent API,
    /// then match by path or name to find the correct plugin instance.
    /// AU plugins are system-registered — scan_path() ignores the path argument,
    /// so we must match from the full scan results.
    fn load_with_rack(path: &Path) -> PluginResult<RackLoadResult> {
        use rack::prelude::*;

        let _is_au = path
            .extension()
            .and_then(|e| e.to_str())
            .is_some_and(|e| e.eq_ignore_ascii_case("component"));

        // Create scanner
        let scanner = Scanner::new().map_err(|e| {
            PluginError::LoadFailed(format!("Failed to create rack scanner: {:?}", e))
        })?;

        // Scan all plugins — for AU, scan_path() ignores path and returns ALL system AU plugins.
        // We then match by path or name to find the correct one.
        let plugins = scanner
            .scan()
            .map_err(|e| PluginError::LoadFailed(format!("Failed to scan plugins: {:?}", e)))?;

        eprintln!("[FluxForge] load_with_rack: scan found {} plugins for path {:?}", plugins.len(), path);

        if plugins.is_empty() {
            return Err(PluginError::LoadFailed(format!(
                "No plugins found at path: {:?}",
                path
            )));
        }

        // Match the correct plugin from scan results.
        // Rack's AU scanner returns names like "FabFilter: Pro-Q 4" or
        // "Native Instruments: Kontakt 8" while our filesystem scanner
        // produces names like "FabFilter Pro-Q 4" from the .component filename.
        // We normalize both sides by stripping punctuation for fuzzy matching.
        let plugin_name_raw = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("");
        let plugin_name = plugin_name_raw.to_lowercase();

        /// Strip colons, dashes, underscores and extra spaces for fuzzy compare
        fn normalize_for_match(s: &str) -> String {
            s.to_lowercase()
                .replace([':', '-', '_'], " ")
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" ")
        }

        let needle = normalize_for_match(&plugin_name);

        // Strategy 1: Match by path (exact)
        let mut plugin_info = plugins.iter().find(|p| p.path == path);

        // Strategy 2: Match by normalized name (exact after stripping punctuation)
        if plugin_info.is_none() {
            plugin_info = plugins.iter().find(|p| normalize_for_match(&p.name) == needle);
        }

        // Strategy 3: Match by name contains (fuzzy)
        if plugin_info.is_none() {
            plugin_info = plugins.iter().find(|p| {
                let norm = normalize_for_match(&p.name);
                norm.contains(&needle) || needle.contains(&norm)
            });
        }

        let plugin_info = plugin_info.ok_or_else(|| {
            // Log ALL plugins for debugging (to find the correct name)
            eprintln!("[FluxForge] Could not find plugin matching '{}' in {} scanned plugins:", plugin_name, plugins.len());
            for p in &plugins {
                eprintln!("[FluxForge]   '{}' by {} (path={:?})", p.name, p.manufacturer, p.path);
            }
            PluginError::LoadFailed(format!(
                "Plugin '{}' not found in {} scanned plugins",
                plugin_name,
                plugins.len()
            ))
        })?;

        eprintln!("[FluxForge] Matched plugin: '{}' by {} (id={})", plugin_info.name, plugin_info.manufacturer, plugin_info.unique_id);

        let plugin = scanner
            .load(plugin_info)
            .map_err(|e| PluginError::LoadFailed(format!("Failed to load plugin: {:?}", e)))?;

        // Extract parameters - use explicit crate::ParameterInfo to avoid confusion with rack::ParameterInfo
        let mut parameters: Vec<crate::ParameterInfo> = Vec::new();
        let param_count = plugin.parameter_count();
        for i in 0..param_count {
            if let Ok(rack_param) = plugin.parameter_info(i) {
                // Normalize default value to 0-1 range
                let range = rack_param.max - rack_param.min;
                let normalized_default = if range > 0.0 {
                    (rack_param.default - rack_param.min) / range
                } else {
                    0.5
                };

                parameters.push(crate::ParameterInfo {
                    id: i as u32,
                    name: rack_param.name.clone(),
                    unit: rack_param.unit.clone(),
                    min: rack_param.min as f64,
                    max: rack_param.max as f64,
                    default: normalized_default as f64,
                    normalized: normalized_default as f64,
                    steps: 0, // rack doesn't expose step count
                    automatable: true,
                    read_only: false,
                });
            }
        }

        // If no parameters found, add defaults
        if parameters.is_empty() {
            parameters = Self::default_parameters();
        }

        // Default to stereo - rack PluginInfo doesn't expose channel counts
        let audio_inputs = 2usize;
        let audio_outputs = 2usize;
        let latency = 0usize; // Will be determined after initialization

        // Wrap the plugin
        let wrapper = RackPluginWrapper {
            plugin,
            latency_samples: 0,
            #[cfg(target_os = "macos")]
            gui: Arc::new(Mutex::new(None)),
        };

        let rack_plugin = RackPlugin {
            inner: Box::new(wrapper),
        };

        // Determine MIDI capability from plugin type
        let has_midi = matches!(plugin_info.plugin_type, rack::PluginType::Instrument);

        Ok((
            Some(Arc::new(Mutex::new(rack_plugin))),
            parameters,
            audio_inputs,
            audio_outputs,
            latency,
            has_midi,
        ))
    }

    /// Default parameters for fallback mode
    fn default_parameters() -> Vec<ParameterInfo> {
        vec![
            ParameterInfo {
                id: 0,
                name: "Gain".to_string(),
                unit: "dB".to_string(),
                min: -60.0,
                max: 12.0,
                default: 0.5,
                normalized: 0.5,
                steps: 0,
                automatable: true,
                read_only: false,
            },
            ParameterInfo {
                id: 1,
                name: "Mix".to_string(),
                unit: "%".to_string(),
                min: 0.0,
                max: 100.0,
                default: 1.0,
                normalized: 1.0,
                steps: 0,
                automatable: true,
                read_only: false,
            },
        ]
    }

    /// Process pending parameter changes (called from audio thread)
    fn process_param_changes(&self) {
        let mut queue = self.param_queue.lock();
        if queue.is_empty() {
            return;
        }

        let mut state = self.state.write();
        for change in queue.drain(..) {
            if let Some(value) = state.param_values.get_mut(change.id as usize) {
                *value = change.value;
            }

            // Also update the rack plugin if available
            if let Some(ref instance) = self.rack_plugin
                && let Some(mut plugin) = instance.try_lock()
            {
                let _ = plugin
                    .inner
                    .set_parameter(change.id as usize, change.value as f32);
            }
        }
    }

    /// Get gain value from parameters (for fallback processing)
    fn get_gain(&self) -> f32 {
        let state = self.state.read();
        let normalized = state.param_values.first().copied().unwrap_or(0.5);
        let db = -60.0 + normalized * 72.0;
        10.0_f32.powf(db as f32 / 20.0)
    }

    /// Get mix value from parameters (for fallback processing)
    fn get_mix(&self) -> f32 {
        let state = self.state.read();
        state.param_values.get(1).copied().unwrap_or(1.0) as f32
    }

    /// Process audio using rack plugin (real VST3/AU)
    fn process_with_rack(
        &self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
        _context: &ProcessContext,
    ) -> PluginResult<()> {
        let instance = self
            .rack_plugin
            .as_ref()
            .ok_or_else(|| PluginError::ProcessingError("No rack instance available".into()))?;

        let mut plugin = instance.lock();

        let num_samples = input.samples.min(output.samples).min(self.max_block_size);
        let in_channels = input.channels.min(self.input_channels as usize);
        let out_channels = output.channels.min(self.output_channels as usize);

        // Get mutable access to our pre-allocated buffers
        let mut input_bufs = self.input_buffers.lock();
        let mut output_bufs = self.output_buffers.lock();

        // Ensure buffers are large enough
        for buf in input_bufs.iter_mut() {
            if buf.len() < num_samples {
                buf.resize(num_samples, 0.0);
            }
        }
        for buf in output_bufs.iter_mut() {
            if buf.len() < num_samples {
                buf.resize(num_samples, 0.0);
            }
        }

        // Copy input data to our buffers
        for ch in 0..in_channels {
            if ch < input_bufs.len()
                && let Some(inp) = input.channel(ch)
            {
                for (i, sample) in inp.iter().take(num_samples).enumerate() {
                    input_bufs[ch][i] = *sample;
                }
            }
        }

        // Create slices for rack API
        let input_slices: Vec<&[f32]> = input_bufs
            .iter()
            .take(in_channels)
            .map(|v| &v[..num_samples])
            .collect();

        let mut output_slices: Vec<&mut [f32]> = output_bufs
            .iter_mut()
            .take(out_channels)
            .map(|v| &mut v[..num_samples])
            .collect();

        // Process audio through the real plugin
        plugin
            .inner
            .process(&input_slices, &mut output_slices, num_samples)
            .map_err(|e| PluginError::ProcessingError(format!("rack process error: {}", e)))?;

        // Copy processed output back to AudioBuffer
        for ch in 0..out_channels {
            if ch < output_bufs.len()
                && let Some(out_ch) = output.channel_mut(ch)
            {
                for (i, sample) in output_bufs[ch].iter().take(num_samples).enumerate() {
                    if i < out_ch.len() {
                        out_ch[i] = *sample;
                    }
                }
            }
        }

        Ok(())
    }

    /// Fallback passthrough processing
    fn process_passthrough(
        &self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
    ) -> PluginResult<()> {
        let gain = self.get_gain();
        let mix = self.get_mix();
        let dry = 1.0 - mix;

        for ch in 0..output.channels.min(input.channels) {
            if let (Some(inp), Some(out)) = (input.channel(ch), output.channel_mut(ch)) {
                for (i, sample) in out.iter_mut().enumerate() {
                    let dry_sample = inp.get(i).copied().unwrap_or(0.0);
                    let wet_sample = dry_sample * gain;
                    *sample = dry_sample * dry + wet_sample * mix;
                }
            }
        }

        Ok(())
    }
}

impl PluginInstance for Vst3Host {
    fn info(&self) -> &PluginInfo {
        &self.info
    }

    fn initialize(&mut self, context: &ProcessContext) -> PluginResult<()> {
        log::debug!(
            "Initializing VST3 plugin {} at {}Hz, block size {}",
            self.info.name,
            context.sample_rate,
            context.max_block_size
        );

        self.sample_rate
            .store(context.sample_rate.to_bits(), Ordering::SeqCst);
        self.max_block_size = context.max_block_size;

        // Resize buffers for new block size
        {
            let mut input_bufs = self.input_buffers.lock();
            for buf in input_bufs.iter_mut() {
                buf.resize(context.max_block_size, 0.0);
            }
        }
        {
            let mut output_bufs = self.output_buffers.lock();
            for buf in output_bufs.iter_mut() {
                buf.resize(context.max_block_size, 0.0);
            }
        }

        // Initialize the rack plugin if available
        if let Some(ref instance) = self.rack_plugin {
            let mut plugin = instance.lock();
            plugin
                .inner
                .initialize(context.sample_rate, context.max_block_size)
                .map_err(|e| PluginError::InitError(format!("rack init error: {}", e)))?;

            // Update latency if available
            if let Some(lat) = plugin.inner.latency() {
                self.latency.store(lat as u64, Ordering::SeqCst);
            }
        }

        Ok(())
    }

    fn activate(&mut self) -> PluginResult<()> {
        self.active.store(true, Ordering::SeqCst);
        log::debug!("Activated VST3 plugin: {}", self.info.name);
        Ok(())
    }

    fn deactivate(&mut self) -> PluginResult<()> {
        self.active.store(false, Ordering::SeqCst);

        // Reset the rack plugin if available
        if let Some(ref instance) = self.rack_plugin {
            let mut plugin = instance.lock();
            let _ = plugin.inner.reset();
        }

        log::debug!("Deactivated VST3 plugin: {}", self.info.name);
        Ok(())
    }

    fn process(
        &mut self,
        input: &AudioBuffer,
        output: &mut AudioBuffer,
        midi_in: &rf_core::MidiBuffer,
        _midi_out: &mut rf_core::MidiBuffer,
        context: &ProcessContext,
    ) -> PluginResult<()> {
        if !self.active.load(Ordering::SeqCst) {
            return Err(PluginError::ProcessingError("Plugin not active".into()));
        }

        // Process any pending parameter changes
        self.process_param_changes();

        // Forward MIDI events to instrument plugins via rack send_midi()
        if self.info.has_midi_input && !midi_in.is_empty()
            && let Some(ref instance) = self.rack_plugin {
                let rack_events = rf_core_midi_to_rack_events(midi_in);
                if let Some(mut plugin) = instance.try_lock() {
                    let _ = plugin.inner.send_midi(&rack_events);
                }
            }

        // Use real plugin processing if available, otherwise fallback
        if self.rack_plugin.is_some() {
            self.process_with_rack(input, output, context)
        } else {
            self.process_passthrough(input, output)
        }
    }

    fn parameter_count(&self) -> usize {
        self.state.read().parameters.len()
    }

    fn parameter_info(&self, index: usize) -> Option<ParameterInfo> {
        self.state.read().parameters.get(index).cloned()
    }

    fn get_parameter(&self, id: u32) -> Option<f64> {
        // Try to get from rack plugin first for real-time accuracy
        if let Some(ref instance) = self.rack_plugin
            && let Some(plugin) = instance.try_lock()
            && let Ok(value) = plugin.inner.get_parameter(id as usize)
        {
            return Some(value as f64);
        }
        // Fallback to cached value
        self.state.read().param_values.get(id as usize).copied()
    }

    fn set_parameter(&mut self, id: u32, value: f64) -> PluginResult<()> {
        let clamped = value.clamp(0.0, 1.0);

        // Queue for audio thread (lock-free)
        {
            let mut queue = self.param_queue.lock();
            if queue.len() < MAX_PARAM_CHANGES {
                queue.push(ParamChange { id, value: clamped });
            }
        }

        // Also update immediately for UI feedback
        {
            let mut state = self.state.write();
            if let Some(v) = state.param_values.get_mut(id as usize) {
                *v = clamped;
            }
        }

        Ok(())
    }

    fn get_state(&self) -> PluginResult<Vec<u8>> {
        // Try to get state from rack plugin first
        if let Some(ref instance) = self.rack_plugin {
            let plugin = instance.lock();
            if let Ok(state) = plugin.inner.get_state() {
                return Ok(state);
            }
        }

        // Fallback to parameter values
        let state = self.state.read();
        Ok(serde_json::to_vec(&state.param_values).unwrap_or_default())
    }

    fn set_state(&mut self, state: &[u8]) -> PluginResult<()> {
        // Try to set state on rack plugin first
        if let Some(ref instance) = self.rack_plugin {
            let mut plugin = instance.lock();
            if plugin.inner.set_state(state).is_ok() {
                return Ok(());
            }
        }

        // Fallback to parsing as parameter values
        if let Ok(values) = serde_json::from_slice::<Vec<f64>>(state) {
            let mut s = self.state.write();
            for (i, v) in values.into_iter().enumerate() {
                if i < s.param_values.len() {
                    s.param_values[i] = v;
                }
            }
        }
        Ok(())
    }

    fn latency(&self) -> usize {
        self.latency.load(Ordering::SeqCst) as usize
    }

    fn has_editor(&self) -> bool {
        // On macOS, AU hosting works independently of rack (in-process via au_host.m).
        // So has_editor is true whenever the plugin bundle exists, even if rack failed to load it.
        #[cfg(target_os = "macos")]
        { self.info.has_editor}
        #[cfg(not(target_os = "macos"))]
        { self.module_loaded }
    }

    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    fn open_editor(&mut self, parent: *mut c_void) -> PluginResult<()> {
        if self.editor_open.load(Ordering::SeqCst) {
            return Ok(());
        }

        // On macOS, AU hosting works without rack — skip module_loaded check
        #[cfg(not(target_os = "macos"))]
        if !self.module_loaded {
            return Err(PluginError::InitError("Plugin module not loaded".into()));
        }

        // Platform-specific editor opening
        // Note: rack crate doesn't expose editor hosting directly,
        // so we need to implement platform-specific hosting

        #[cfg(target_os = "macos")]
        {
            self.open_editor_macos(parent)?;
        }

        #[cfg(target_os = "windows")]
        {
            self.open_editor_windows(parent)?;
        }

        #[cfg(target_os = "linux")]
        {
            self.open_editor_linux(parent)?;
        }

        self.editor_open.store(true, Ordering::SeqCst);
        log::info!("Opened editor for plugin: {}", self.info.name);
        Ok(())
    }

    fn close_editor(&mut self) -> PluginResult<()> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return Ok(());
        }

        #[cfg(target_os = "macos")]
        {
            // Close in-process AU GUI window
            // Check both self.au_window and PENDING_WINDOW (async callback may have set it)
            let window_ptr = self.au_window.lock().take()
                .or_else(|| PENDING_WINDOW.lock().take());
            if let Some(ptr) = window_ptr {
                unsafe {
                    use objc2::msg_send;
                    use objc2::runtime::AnyObject;
                    let window = ptr as *mut AnyObject;
                    let _: () = msg_send![window, close];
                    let _: () = msg_send![window, release];
                }
            }
            unsafe { au_host_close(); }
            *self.au_gui.lock() = None;
        }

        #[cfg(any(target_os = "windows", target_os = "linux"))]
        {
            // Clean up IPlugView COM object
            if let Some(plug_view) = self.plug_view.lock().take() {
                unsafe {
                    let vtable = *(plug_view as *const *const IPlugViewVtable);
                    // Detach from parent window first
                    let _ = ((*vtable).removed)(plug_view);
                    // Release COM reference
                    ((*vtable).release)(plug_view);
                }
            }
            // Drop UI library (after plug_view is released)
            *self._ui_library.lock() = None;
        }

        self.editor_open.store(false, Ordering::SeqCst);
        log::info!("Closed editor for plugin: {}", self.info.name);
        Ok(())
    }

    fn editor_size(&self) -> Option<(u32, u32)> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return None;
        }

        // Query real plugin GUI size on macOS
        #[cfg(target_os = "macos")]
        {
            if let Some(ref rp) = self.rack_plugin {
                let lock = rp.lock();
                if let Some((w, h)) = lock.inner.gui_size() {
                    return Some((w as u32, h as u32));
                }
            }
        }

        // Fallback default size
        Some((800, 600))
    }

    fn resize_editor(&mut self, width: u32, height: u32) -> PluginResult<()> {
        if !self.editor_open.load(Ordering::SeqCst) {
            return Err(PluginError::ProcessingError("Editor not open".into()));
        }

        // Clamp to reasonable bounds
        let w = width.clamp(200, 4096) as f64;
        let h = height.clamp(150, 4096) as f64;

        #[cfg(target_os = "macos")]
        {
            // Resize the AU window if we have one
            {
                let guard = self.au_window.lock();
                if let Some(window_ptr) = *guard
                    && window_ptr != 0 {
                        unsafe {
                            use objc2::msg_send;
                            use objc2::runtime::AnyObject;
                            use objc2_foundation::{NSPoint, NSRect, NSSize};

                            let window = window_ptr as *mut AnyObject;
                            // Get current frame origin to preserve position
                            let frame: NSRect = msg_send![window, frame];
                            let new_frame = NSRect::new(
                                NSPoint::new(frame.origin.x, frame.origin.y),
                                NSSize::new(w, h + 22.0), // +22 for standard macOS title bar
                            );
                            let _: () = msg_send![window, setFrame: new_frame, display: true, animate: true];
                            // Also resize the content view's plugin subview
                            let content_view: *mut AnyObject = msg_send![window, contentView];
                            if !content_view.is_null() {
                                let subviews: *mut AnyObject = msg_send![content_view, subviews];
                                let count: usize = msg_send![subviews, count];
                                if count > 0 {
                                    let plugin_view: *mut AnyObject = msg_send![subviews, objectAtIndex: 0usize];
                                    let view_rect = NSRect::new(
                                        NSPoint::new(0.0, 0.0),
                                        NSSize::new(w, h),
                                    );
                                    let _: () = msg_send![plugin_view, setFrame: view_rect];
                                }
                            }
                        }
                        log::info!("Resized editor window to {}x{}", width, height);
                    }
            }
        }

        Ok(())
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// PLATFORM-SPECIFIC EDITOR HOSTING
// ═══════════════════════════════════════════════════════════════════════════

// FFI to au_host.m — compiled in-process via build.rs (no subprocess needed)
#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn au_host_open_plugin(
        component_type: u32,
        component_subtype: u32,
        component_manufacturer: u32,
        user_data: *mut std::ffi::c_void,
        callback: extern "C" fn(*mut std::ffi::c_void, *mut objc2::runtime::AnyObject, f64, f64),
    );
    fn au_host_close();
    fn au_host_scan_plugins(
        user_data: *mut std::ffi::c_void,
        callback: unsafe extern "C" fn(
            *mut std::ffi::c_void,
            *const std::os::raw::c_char,
            *const std::os::raw::c_char,
            u32, u32, u32,
        ),
    );
}

/// Scanned AU plugin entry for in-process lookup
#[cfg(target_os = "macos")]
#[derive(Clone)]
struct AuPluginEntry {
    name: String,
    comp_type: u32,
    subtype: u32,
    mfr_code: u32,
}

/// Global scanned AU plugins list (populated once on first open_editor call)
#[cfg(target_os = "macos")]
static AU_PLUGINS: Mutex<Vec<AuPluginEntry>> = Mutex::new(Vec::new());
#[cfg(target_os = "macos")]
static AU_SCANNED: std::sync::Once = std::sync::Once::new();

/// Global window pointer set by GUI callback, read by open_editor_macos
#[cfg(target_os = "macos")]
static PENDING_WINDOW: Mutex<Option<usize>> = Mutex::new(None);

/// Callback from au_host.m when plugin GUI view is ready
#[cfg(target_os = "macos")]
extern "C" fn au_gui_ready_callback(
    _user_data: *mut std::ffi::c_void,
    view: *mut objc2::runtime::AnyObject,
    width: f64,
    height: f64,
) {
    if view.is_null() {
        eprintln!("[FluxForge] AU plugin has no GUI view");
        return;
    }

    let w = if width > 10.0 { width } else { 800.0 };
    let h = if height > 10.0 { height } else { 600.0 };

    // Create window using existing FFPluginWindow infrastructure (in-process)
    unsafe {
        use objc2::msg_send;
        use objc2::runtime::AnyObject;
        create_plugin_window(view as *mut c_void, w, h, "Plugin");
        // The window was retained in create_plugin_window, grab its pointer
        // from the view's window property
        let window: *mut AnyObject = msg_send![view, window];
        if !window.is_null() {
            *PENDING_WINDOW.lock() = Some(window as usize);
        }
    }
    eprintln!("[FluxForge] AU GUI window created {}x{}", w as u32, h as u32);
}

/// Scan callback for building AU_PLUGINS list
#[cfg(target_os = "macos")]
extern "C" fn au_scan_callback(
    _user_data: *mut std::ffi::c_void,
    name: *const std::os::raw::c_char,
    _manufacturer: *const std::os::raw::c_char,
    comp_type: u32,
    subtype: u32,
    mfr_code: u32,
) {
    if name.is_null() {
        return;
    }
    let name_str = unsafe { std::ffi::CStr::from_ptr(name) }
        .to_string_lossy()
        .to_string();
    AU_PLUGINS.lock().push(AuPluginEntry {
        name: name_str,
        comp_type,
        subtype,
        mfr_code,
    });
}

#[cfg(target_os = "macos")]
impl Vst3Host {
    fn open_editor_macos(&mut self, _parent: *mut c_void) -> PluginResult<()> {
        log::info!("macOS plugin editor: opening GUI for {}", self.info.name);

        // In-process AU hosting — no subprocess, no Dock icon.
        // Uses au_host.m compiled directly into FluxForge via build.rs.
        // GUI window is a child of FluxForge's process, not a separate app.

        let plugin_name = self.info.name.clone();
        eprintln!(
            "[FluxForge] open_editor_macos: in-process AU hosting for '{}'",
            plugin_name
        );

        // Scan AU plugins once (lazy init)
        AU_SCANNED.call_once(|| {
            unsafe {
                au_host_scan_plugins(std::ptr::null_mut(), au_scan_callback);
            }
            let count = AU_PLUGINS.lock().len();
            eprintln!("[FluxForge] AU scan: {} plugins found", count);
        });

        // Fuzzy match plugin name — handles vendor prefixes and spacing differences
        // e.g. "DUNE3" must match "Synapse Audio: DUNE 3"
        // e.g. "KrotosStudio" must match "Krotos: Krotos Studio"
        let needle_spaced = plugin_name
            .to_lowercase()
            .replace([':', '-', '_'], " ")
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ");
        // Also create a no-space version for matching "DUNE3" vs "DUNE 3"
        let needle_nospace: String = needle_spaced.chars().filter(|c| !c.is_whitespace()).collect();

        let plugins = AU_PLUGINS.lock();
        let found = plugins.iter().find(|p| {
            let norm_spaced = p.name
                .to_lowercase()
                .replace([':', '-', '_'], " ")
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" ");
            let norm_nospace: String = norm_spaced.chars().filter(|c| !c.is_whitespace()).collect();

            // Exact match (with spaces normalized)
            norm_spaced == needle_spaced
            // Substring match (with spaces)
            || norm_spaced.contains(&needle_spaced) || needle_spaced.contains(&norm_spaced)
            // No-space match: "dune3" matches "synapseaudiodune3"
            || norm_nospace.contains(&needle_nospace) || needle_nospace.contains(&norm_nospace)
        }).cloned();
        drop(plugins);

        match found {
            Some(entry) => {
                eprintln!(
                    "[FluxForge] Opening AU '{}' type={:08x} sub={:08x} mfr={:08x}",
                    entry.name, entry.comp_type, entry.subtype, entry.mfr_code
                );

                // Clear pending window
                *PENDING_WINDOW.lock() = None;

                unsafe {
                    au_host_open_plugin(
                        entry.comp_type,
                        entry.subtype,
                        entry.mfr_code,
                        std::ptr::null_mut(),
                        au_gui_ready_callback,
                    );
                }

                // Callback fires asynchronously on main thread — window will appear when ready.
                // No polling needed: callback creates the window directly via create_plugin_window().
                // PENDING_WINDOW is checked in close_editor to find the window handle.

                Ok(())
            }
            None => {
                eprintln!("[FluxForge] AU plugin not found: '{}'", plugin_name);
                Err(PluginError::InitError(format!(
                    "AU plugin not found: {}. VST3-only plugins without AU version cannot show GUI yet.",
                    plugin_name
                )))
            }
        }
    }

    /// Get the preferred editor size for this plugin
    pub fn preferred_editor_size(&self) -> Option<(u32, u32)> {
        if let Some(ref rp) = self.rack_plugin {
            let lock = rp.lock();
            if let Some((w, h)) = lock.inner.gui_size() {
                return Some((w as u32, h as u32));
            }
        }
        Some((800, 600))
    }
}

/// Minimal VST3 COM ABI definitions for IPlugView embedding.
///
/// VST3 plugins are COM-style objects. We need:
///   IPluginFactory → createInstance(IEditController) → IEditController::createView("editor")
///   → IPlugView::attached(parent, platformType)
///
/// The rack crate wraps audio processing but doesn't expose the GUI COM interfaces.
/// We implement the minimal vtable layout here to call IPlugView directly.
///
/// VST3 SDK COM calling convention: *mut *const VTable, where VTable is function pointer array.
// ── VST3 GUID helpers ─────────────────────────────────────────────────────
type Vst3Guid = [u8; 16];

/// IPlugView interface GUID: {5BC32507-D060-49EA-A615-1B522B755B29}
const IPLUG_VIEW_IID: Vst3Guid = [
    0x5B, 0xC3, 0x25, 0x07, 0xD0, 0x60, 0x49, 0xEA,
    0xA6, 0x15, 0x1B, 0x52, 0x2B, 0x75, 0x5B, 0x29,
];

/// IEditController interface GUID: {DAF2127B-58E9-4A2F-8D4E-08A5A38C0DA4}
const IEDIT_CONTROLLER_IID: Vst3Guid = [
    0xDA, 0xF2, 0x12, 0x7B, 0x58, 0xE9, 0x4A, 0x2F,
    0x8D, 0x4E, 0x08, 0xA5, 0xA3, 0x8C, 0x0D, 0xA4,
];

/// Minimal IPlugView vtable layout (VST3 SDK §4.3.2)
/// Offsets match the SDK's IPlugView class vtable in COM calling order:
///   [0] queryInterface [1] addRef [2] release
///   [3] isPlatformTypeSupported [4] attached [5] removed
///   [6] onWheel [7] onKeyDown [8] onKeyUp [9] setFrame [10] canResize [11] checkSizeConstraint
#[repr(C)]
struct IPlugViewVtable {
    query_interface: unsafe extern "system" fn(*mut c_void, *const Vst3Guid, *mut *mut c_void) -> i32,
    add_ref:  unsafe extern "system" fn(*mut c_void) -> u32,
    release:  unsafe extern "system" fn(*mut c_void) -> u32,
    is_platform_type_supported: unsafe extern "system" fn(*mut c_void, *const u8) -> i32,
    attached: unsafe extern "system" fn(*mut c_void, *mut c_void, *const u8) -> i32,
    removed:  unsafe extern "system" fn(*mut c_void) -> i32,
    on_wheel: unsafe extern "system" fn(*mut c_void, f32) -> i32,
    on_key_down: unsafe extern "system" fn(*mut c_void, u16, u16, u16) -> i32,
    on_key_up:   unsafe extern "system" fn(*mut c_void, u16, u16, u16) -> i32,
    set_frame:   unsafe extern "system" fn(*mut c_void, *mut c_void) -> i32,
    can_resize:  unsafe extern "system" fn(*mut c_void) -> i32,
    check_size_constraint: unsafe extern "system" fn(*mut c_void, *mut [i32; 4]) -> i32,
}

/// Minimal IEditController vtable (relevant portion only — createView is at offset +30 in SDK)
/// We query IPlugView directly via queryInterface instead.
#[repr(C)]
struct IEditControllerVtable {
    query_interface: unsafe extern "system" fn(*mut c_void, *const Vst3Guid, *mut *mut c_void) -> i32,
    add_ref:  unsafe extern "system" fn(*mut c_void) -> u32,
    release:  unsafe extern "system" fn(*mut c_void) -> u32,
    // ... initialize, terminate (FUnknown+IPluginBase), then IEditController methods
    // create_view is at vtable index 16 (0-indexed, after all base class methods)
    _pad: [usize; 13], // FUnknown (3) + IPluginBase (2) + IEditController methods before createView (8)
    create_view: unsafe extern "system" fn(*mut c_void, *const u8) -> *mut c_void,
}

/// Load GetPluginFactory from a VST3 binary and return (IPlugView ptr, library).
/// Caller owns both the plug_view COM reference and the library handle.
/// Library MUST be kept alive while plug_view is in use.
unsafe fn vst3_load_plug_view(plugin_path: &Path, plugin_name: &str) -> Option<(*mut c_void, Arc<libloading::Library>)> { unsafe {
    // Determine actual binary path inside .vst3 bundle
    let binary_path = {
        #[cfg(target_os = "windows")]
        { plugin_path.join("Contents/x86_64-win").join(format!("{}.vst3", plugin_name)) }
        #[cfg(target_os = "linux")]
        { plugin_path.join("Contents/x86_64-linux").join(format!("{}.so", plugin_name)) }
        #[cfg(target_os = "macos")]
        { plugin_path.join("Contents/MacOS").join(plugin_name) }
    };

    if !binary_path.exists() {
        log::warn!("VST3 binary not found at {:?}", binary_path);
        return None;
    }

    // Load the binary
    let lib = match libloading::Library::new(&binary_path) {
        Ok(l) => l,
        Err(e) => { log::error!("VST3 dlopen failed: {}", e); return None; }
    };

    // Get GetPluginFactory
    type GetPluginFactoryFn = unsafe extern "system" fn() -> *mut c_void;
    let get_factory: libloading::Symbol<GetPluginFactoryFn> = match lib.get(b"GetPluginFactory\0") {
        Ok(f) => f,
        Err(e) => { log::error!("GetPluginFactory missing: {}", e); return None; }
    };

    let factory = (*get_factory)();
    if factory.is_null() { return None; }

    // Query IEditController from factory (simplified: try to get class 0)
    let factory_vtable = *(factory as *const *const [usize; 8]);
    let query_interface_fn: unsafe extern "system" fn(*mut c_void, *const Vst3Guid, *mut *mut c_void) -> i32
        = std::mem::transmute((*factory_vtable)[0]);

    let mut edit_controller: *mut c_void = std::ptr::null_mut();
    let hr = query_interface_fn(factory, &IEDIT_CONTROLLER_IID, &mut edit_controller);
    if hr != 0 || edit_controller.is_null() {
        log::warn!("IEditController QueryInterface failed hr={}", hr);
        return None;
    }

    // Query IPlugView from IEditController
    let ec_vtable = *(edit_controller as *const *const IEditControllerVtable);
    let mut plug_view: *mut c_void = std::ptr::null_mut();
    let hr2 = ((*ec_vtable).query_interface)(edit_controller, &IPLUG_VIEW_IID, &mut plug_view);
    if hr2 != 0 || plug_view.is_null() {
        log::warn!("IPlugView QueryInterface failed hr={}", hr2);
        ((*ec_vtable).release)(edit_controller);
        return None;
    }

    // Release edit_controller reference (plug_view holds its own)
    ((*ec_vtable).release)(edit_controller);

    let lib = Arc::new(lib);
    Some((plug_view, lib))
}}

#[cfg(target_os = "windows")]
impl Vst3Host {
    fn open_editor_windows(&mut self, parent: *mut c_void) -> PluginResult<()> {
        if parent.is_null() {
            return Err(PluginError::InitError("Null parent HWND for VST3 editor".into()));
        }

        log::info!(
            "VST3 Windows editor: opening {} with parent HWND {:?}",
            self.info.name, parent
        );

        let (plug_view, ui_lib) = unsafe {
            vst3_load_plug_view(&self.plugin_path, &self.info.name)
        }.ok_or_else(|| PluginError::InitError(
            format!("Failed to get IPlugView for {}", self.info.name)
        ))?;

        // VST3 Windows platform type string: "HWND\0"
        let platform_type = b"HWND\0";

        let result = unsafe {
            let vtable = *(plug_view as *const *const IPlugViewVtable);

            // Check platform support
            let supported = ((*vtable).is_platform_type_supported)(
                plug_view, platform_type.as_ptr()
            );
            if supported != 0 {
                log::warn!("VST3 plugin {} does not support HWND platform type", self.info.name);
                ((*vtable).release)(plug_view);
                return Err(PluginError::UnsupportedFormat(
                    format!("{} does not support Windows GUI embedding", self.info.name)
                ));
            }

            // Attach to parent HWND
            ((*vtable).attached)(plug_view, parent, platform_type.as_ptr())
        };

        if result != 0 {
            unsafe {
                let vtable = *(plug_view as *const *const IPlugViewVtable);
                ((*vtable).release)(plug_view);
            }
            return Err(PluginError::InitError(
                format!("IPlugView::attached failed for {} (hr={})", self.info.name, result)
            ));
        }

        // Store plug_view and library for cleanup in close_editor
        *self.plug_view.lock() = Some(plug_view);
        *self._ui_library.lock() = Some(ui_lib);

        log::info!("VST3 Windows editor opened successfully: {}", self.info.name);
        Ok(())
    }

    pub fn preferred_editor_size(&self) -> Option<(u32, u32)> {
        if let Some(ref rp) = self.rack_plugin {
            let lock = rp.lock();
            if let Some((w, h)) = lock.inner.gui_size() {
                return Some((w as u32, h as u32));
            }
        }
        Some((800, 600))
    }
}

#[cfg(target_os = "linux")]
impl Vst3Host {
    fn open_editor_linux(&mut self, parent: *mut c_void) -> PluginResult<()> {
        if parent.is_null() {
            return Err(PluginError::InitError("Null parent X11 Window ID for VST3 editor".into()));
        }

        // On Linux, parent is an X11 Window (XID = unsigned long)
        let xid = parent as usize;
        log::info!(
            "VST3 Linux editor: opening {} with X11 XID 0x{:x}",
            self.info.name, xid
        );

        let (plug_view, ui_lib) = unsafe {
            vst3_load_plug_view(&self.plugin_path, &self.info.name)
        }.ok_or_else(|| PluginError::InitError(
            format!("Failed to get IPlugView for {}", self.info.name)
        ))?;

        // VST3 Linux platform type: "X11EmbedWindowID\0"
        let platform_type = b"X11EmbedWindowID\0";

        let result = unsafe {
            let vtable = *(plug_view as *const *const IPlugViewVtable);

            let supported = ((*vtable).is_platform_type_supported)(
                plug_view, platform_type.as_ptr()
            );
            if supported != 0 {
                log::warn!("VST3 plugin {} does not support X11EmbedWindowID", self.info.name);
                ((*vtable).release)(plug_view);
                return Err(PluginError::UnsupportedFormat(
                    format!("{} does not support Linux X11 GUI embedding", self.info.name)
                ));
            }

            // Attach to X11 parent window via XEmbed protocol
            ((*vtable).attached)(plug_view, parent, platform_type.as_ptr())
        };

        if result != 0 {
            unsafe {
                let vtable = *(plug_view as *const *const IPlugViewVtable);
                ((*vtable).release)(plug_view);
            }
            return Err(PluginError::InitError(
                format!("IPlugView::attached failed for {} (hr={})", self.info.name, result)
            ));
        }

        // Store plug_view and library for cleanup in close_editor
        *self.plug_view.lock() = Some(plug_view);
        *self._ui_library.lock() = Some(ui_lib);

        log::info!("VST3 Linux editor opened successfully via XEmbed: {}", self.info.name);
        Ok(())
    }

    pub fn preferred_editor_size(&self) -> Option<(u32, u32)> {
        if let Some(ref rp) = self.rack_plugin {
            let lock = rp.lock();
            if let Some((w, h)) = lock.inner.gui_size() {
                return Some((w as u32, h as u32));
            }
        }
        Some((800, 600))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_vst3_host_nonexistent_path() {
        let path = PathBuf::from("/tmp/nonexistent_plugin.vst3");
        let result = Vst3Host::load(&path);
        // Should fail because path doesn't exist
        assert!(result.is_err());
    }

    #[test]
    fn test_default_parameters() {
        let params = Vst3Host::default_parameters();
        assert_eq!(params.len(), 2);
        assert_eq!(params[0].name, "Gain");
        assert_eq!(params[1].name, "Mix");
    }

    #[test]
    fn test_param_change_struct() {
        let change = ParamChange { id: 0, value: 0.5 };
        assert_eq!(change.id, 0);
        assert!((change.value - 0.5).abs() < f64::EPSILON);
    }
}
