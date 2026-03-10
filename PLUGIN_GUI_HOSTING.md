# Plugin GUI Hosting — Technical Reference

## How Professional DAWs Host Plugin GUIs on macOS

### The Universal Pattern (JUCE, Reaper, Cubase, Logic, Bitwig, Ardour)

Every DAW follows the same fundamental approach:

1. **Create NSWindow** via `initWithContentRect:styleMask:backing:defer:`
2. **Get contentView** (NSView) from the window
3. **Set `wantsLayer = YES`** on contentView (critical for Metal/CoreAnimation compat)
4. **Add plugin's NSView as subview** of contentView
5. For VST3: pass NSView to `IPlugView::attached(nsview, kPlatformTypeNSView)` — always NSView, never NSWindow
6. For AU v2: get NSView from `kAudioUnitProperty_CocoaUI`
7. For AU v3: get `AUViewController.view` (NSView)

### Why Raw `objc_msgSend` + `transmute` Crashes on ARM64

On Apple Silicon (AArch64), variadic and non-variadic functions use **different calling conventions**:
- **Non-variadic**: arguments in registers (x0-x7 integers, v0-v7 floats)
- **Variadic**: fixed args in registers, variadic args on **stack**

`objc_msgSend` is declared variadic but acts as a transparent trampoline. When you `transmute` it to a typed fn pointer, the Rust compiler generates caller code assuming non-variadic ABI, but the underlying trampoline may interpret the register state differently for struct arguments like NSRect (32 bytes = 4×f64).

The `msg_send!` macro from `objc` crate handles this correctly by generating properly-typed function pointer casts that match the actual method signature.

### The Solution: `cocoa` Crate

The `cocoa` crate (from Servo project) provides battle-tested Cocoa bindings:
- `NSWindow::alloc(nil).initWithContentRect_styleMask_backing_defer_(...)`
- NSRect, NSPoint, NSSize with correct `Encode` implementations
- Used by: Servo, baseview (RustAudio), wgpu, winit, dozens of Rust audio projects

### Critical Implementation Details

1. **`setWantsLayer: YES`** on both contentView AND plugin NSView — prevents CALayer/Metal conflicts with Flutter
2. **`setReleasedWhenClosed: NO`** — prevents double-free when user closes window
3. **`retain`** the NSWindow — prevents ARC deallocation; store `id` and `release` on close
4. **NSRect layout**: `{origin: {x, y}, size: {w, h}}` (matches CGRect), NOT flat `{x, y, w, h}`
5. **Autoresizing mask**: NSViewWidthSizable | NSViewHeightSizable = 2 | 16 = 18
6. **Return window id** from create function for lifecycle management (close/release later)

### Reference Code (cocoa crate)

```rust
use cocoa::appkit::{NSBackingStoreBuffered, NSView, NSWindow, NSWindowStyleMask};
use cocoa::base::{id, nil, NO};
use cocoa::foundation::{NSAutoreleasePool, NSPoint, NSRect, NSSize, NSString};
use objc::runtime::YES;

let rect = NSRect::new(NSPoint::new(200.0, 200.0), NSSize::new(width, height));
let style = NSWindowStyleMask::NSTitledWindowMask
    | NSWindowStyleMask::NSClosableWindowMask
    | NSWindowStyleMask::NSMiniaturizableWindowMask
    | NSWindowStyleMask::NSResizableWindowMask;

let window = NSWindow::alloc(nil)
    .initWithContentRect_styleMask_backing_defer_(rect, style, NSBackingStoreBuffered, NO);

let content_view = window.contentView();
msg_send![content_view, setWantsLayer: YES];
msg_send![plugin_view, setWantsLayer: YES];
content_view.addSubview_(plugin_view);
window.center();
window.makeKeyAndOrderFront_(nil);
```

### Sources

- [JUCE NSViewComponentPeer](https://github.com/juce-framework/JUCE) — `modules/juce_gui_basics/native/juce_NSViewComponentPeer_mac.mm`
- [RustAudio/baseview macOS](https://github.com/RustAudio/baseview/blob/master/src/macos/window.rs)
- [Steinberg IPlugView docs](https://steinbergmedia.github.io/vst3_doc/base/classSteinberg_1_1IPlugView.html)
- [Mike Ash: objc_msgSend on ARM64](https://www.mikeash.com/pyblog/friday-qa-2017-06-30-dissecting-objc_msgsend-on-arm64.html)
- [cocoa crate docs](https://docs.rs/cocoa/latest/cocoa/)
