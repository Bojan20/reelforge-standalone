# Plugin GUI Hosting — Technical Reference (DEFINITIVE)

## GOLDEN RULES — Verified from JUCE, Ardour, Pugl source code

### Rule 1: `defer:YES` — OBAVEZNO
JUCE koristi `defer:YES` pri kreiranju NSWindow-a. Ovo odlaže konekciju ka window serveru.
Bez ovoga, AppKit ODMAH kreira layer tree čim se view doda — što izaziva `_createLayer` crash
kod pluginova koji imaju custom `makeBackingLayer` (FabFilter, Apple AUDelay, itd).

rack crate koristi `defer:NO` — i zato crash-uje.

### Rule 2: NIKADA `wantsLayer:YES` na plugin view ili contentView
- JUCE: NE postavlja `wantsLayer` na plugin view. Samo na SVOJ view, i to USLOVNO.
- Ardour: NEMA `wantsLayer` nigde u AU GUI hosting kodu.
- Pugl: NEMA `wantsLayer` osim za Vulkan/Metal renderere.

`wantsLayer:YES` na parent-u forsira IMPLICIT layer-backing na subviews.
Ovo lomi event handling kod pluginova koji ne očekuju layer-backed hijerarhiju.
Kontrole se renderuju ali ne reaguju na klik.

### Rule 3: `addSubview:` — NE `setContentView:`
- JUCE: koristi `addSubview:` za plugin view
- Ardour: koristi `addSubview:` za plugin view
- Pugl: koristi `addSubview:` za embedded views

`setContentView:` zamenjuje ceo content view sa plugin view-om.
Ovo može izazvati probleme sa responder chain-om i layer tree-om.

### Rule 4: Redosled operacija
1. `NSWindow alloc + initWithContentRect...defer:YES` — window bez server konekcije
2. `setContentView:` sa PLAIN NSView kontejnerom (ne plugin view!)
3. `addSubview:` — dodaj plugin view u kontejner
4. `setFrame:` — postavi veličinu plugin view-a
5. `setAutoresizingMask:` — NSViewWidthSizable | NSViewHeightSizable
6. TEK SADA: `makeKeyAndOrderFront:` — ovo prvi put triggeruje layer tree

### Rule 5: Event loop
- `CFRunLoopRunInMode` sa kratkim intervalima (0.05s) MOŽE da propusti evente
- JUCE koristi `NSApp run` ili `NSRunLoop` sa timer-ima
- Baseview ima poznate probleme sa prvim klikom na macOS (issue #129)
- Za pouzdane mouse evente: koristiti `[NSApp run]` ili `NSTimer` na main run loop

## Zašto prethodni pristupi nisu radili

| Pristup | Rezultat | Razlog |
|---------|----------|--------|
| rack `show_window()` | SIGSEGV (139) | `defer:NO` → instant `_createLayer` → crash u `makeBackingLayer` |
| Custom window + `wantsLayer:YES` | Kontrole frozen | Implicit layer-backing lomi plugin event handling |
| Swizzle `makeBackingLayer` → prazan CALayer | Prazan prozor | Plugin rendering pipeline očekuje svoj specifični layer tip |
| `setContentView:pluginView` bez `wantsLayer` | Crash | Isti `_createLayer` problem |

## ISPRAVNA implementacija

```rust
unsafe {
    // 1. Window sa defer:YES — KRITIČNO
    let rect = NSRect::new(NSPoint::new(200.0, 200.0), NSSize::new(width, height));
    let style = NSWindowStyleMask::NSTitledWindowMask
        | NSWindowStyleMask::NSClosableWindowMask
        | NSWindowStyleMask::NSMiniaturizableWindowMask
        | NSWindowStyleMask::NSResizableWindowMask;

    let window = NSWindow::alloc(nil)
        .initWithContentRect_styleMask_backing_defer_(rect, style, NSBackingStoreBuffered, YES);
        // ^^^^^ defer:YES — NE defer:NO

    window.setReleasedWhenClosed_(NO);

    // 2. Plain kontejner view — BEZ wantsLayer
    let container: id = NSView::alloc(nil).initWithFrame_(rect);
    // NE: msg_send![container, setWantsLayer: YES];  ← ZABRANJENO

    // 3. Postavi kontejner kao contentView
    window.setContentView_(container);

    // 4. Dodaj plugin view kao subview — BEZ wantsLayer
    let bounds: NSRect = msg_send![container, bounds];
    let _: () = msg_send![plugin_view, setFrame: bounds];
    let _: () = msg_send![plugin_view, setAutoresizingMask: 18u64]; // width+height sizable
    container.addSubview_(plugin_view);
    // NE: msg_send![plugin_view, setWantsLayer: YES];  ← ZABRANJENO

    // 5. TEK SADA prikaži window
    window.setTitle_(NSString::alloc(nil).init_str(title));
    window.center();
    window.makeKeyAndOrderFront_(nil);
}
```

## Fallback ako i dalje crash-uje

Ako `defer:YES` + `addSubview:` i dalje crash-uje jer plugin poziva
`makeBackingLayer` tokom `addSubview:`:

**Option A: Layer-hosting kontejner**
```rust
// Kontejner sa SOPSTVENIM layer-om (layer-hosting, NE layer-backed)
let ca_layer: id = msg_send![Class::get("CALayer").unwrap(), layer];
let _: () = msg_send![container, setLayer: ca_layer];     // postavi layer PRVI
let _: () = msg_send![container, setWantsLayer: YES];      // PA ONDA wantsLayer
// Subviews layer-hosting view-a NE postaju automatski layer-backed
container.addSubview_(plugin_view);
```

**Option B: NSApp run umesto CFRunLoop**
```rust
// Umesto while loop sa CFRunLoopRunInMode:
let app: id = msg_send![Class::get("NSApplication").unwrap(), sharedApplication];
let _: () = msg_send![app, run];  // blokira, procesira SVE evente
```

## ARM64 ABI napomena

Na Apple Silicon, `objc_msgSend` sa `transmute` crash-uje za struct argumente (NSRect).
Koristiti `cocoa` crate sa `msg_send!` makroom — uvek.

## Izvori (verifikovani iz source koda)
- JUCE `juce_NSViewComponentPeer_mac.mm`: `defer:YES`, conditional `wantsLayer`, `addSubview:`
- Ardour `au_pluginui.mm`: `addSubview:`, NO `wantsLayer`, manual keyboard forwarding
- Pugl `mac_gl.m` / `mac.m`: `addSubview:` for embedded, NO `wantsLayer` for non-Metal
- Baseview issue #129: "initial click ignored on macOS" — poznati problem
- rack `au_gui.mm`: `defer:NO` + `setContentView:` — uzrok crash-a
