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

---

# Plugin Hosting — KOMPLETNA REFERENCA (Logic/Cubase/Reaper)

## VST3 Hosting — Kanonska sekvenca (Steinberg SDK)

### Inicijalizacija

```
1. Load .vst3 bundle → dlopen → GetPluginFactory() → IPluginFactory*
2. factory->createInstance(classID, IComponent::iid) → IComponent*
3. processor->initialize(hostContext)    // hostContext = IHostApplication
4. processor->getControllerClassId(&controllerCID)
5. factory->createInstance(controllerCID, IEditController::iid) → IEditController*
   // FALLBACK: queryInterface(IEditController::iid) on processor
6. controller->initialize(hostContext)
7. Connect via IConnectionPoint (bidirectional processor<->controller)
8. controller->setComponentHandler(myComponentHandler)
9. controller->setComponentState(processorState)  // sync state
```

### Audio Setup

```
10. processor->getBusInfo() — enumerate I/O buses
11. processor->activateBus(direction, index, true/false)
12. audioProcessor->setBusArrangements(inputs, numIn, outputs, numOut)
13. audioProcessor->setupProcessing(processSetup)  // sampleRate, maxBlockSize
14. audioProcessor->setActive(true)     // resource allocation
15. audioProcessor->setProcessing(true) // start real-time
```

### Audio Processing Loop

```
audioProcessor->process(processData)
// ProcessData sadrži:
//   inputs[]/outputs[] — AudioBusBuffers (float** channelBuffers32)
//   inputParameterChanges (IParameterChanges)
//   outputParameterChanges
//   processContext (tempo, position, time sig, transport)
//   numSamples
```

### Parameter Flow

**GUI → Processor:**
- Controller poziva `IComponentHandler::beginEdit/performEdit/endEdit`
- Host queue-uje u `IParameterChanges` za sledeći `process()` poziv
- Processor čita iz `ProcessData::inputParameterChanges`

**Processor → GUI:**
- Processor piše u `ProcessData::outputParameterChanges`
- Host dostavlja controller-u via `setParamNormalized()` (60Hz timer flush)

### State Save/Restore

```
// SAVE:
processor->getState(stream)
controller->getState(stream)

// RESTORE (redosled je KRITIČAN):
processor->setState(stream)              // 1. PRVO
controller->setComponentState(stream)    // 2. DRUGO (isti stream)
controller->setState(stream)             // 3. TREĆE
```

### GUI Hosting (IPlugView)

```
view = controller->createView("editor")
view->setFrame(myPlugFrame)              // host implements IPlugFrame
view->isPlatformTypeSupported("NSView")  // macOS
view->attached(parentNSView, "NSView")   // embed
view->getSize(&rect)                     // initial size
// Resize: canResize() → checkSizeConstraint() → onSize()
// Close: removed() → release()
```

### IRunLoop — SAMO ZA LINUX

Na macOS-u plugini koriste CFRunLoop direktno. IRunLoop je ISKLJUČIVO za Linux
jer Linux nema globalni event loop. Na macOS-u: NEPOTREBAN.

### IComponentHandler (host MORA da implementira)

- `IComponentHandler` — beginEdit/performEdit/endEdit/restartComponent
- `IHostApplication` — getName, createInstance
- `IPlugFrame` — resizeView

**restartComponent flags:**
- `kLatencyChanged` — plugin promenio latency → recalc PDC
- `kParamValuesChanged` — rescan svih parametara
- `kIoChanged` — bus config promenjen

### Shutdown

```
audioProcessor->setProcessing(false)
audioProcessor->setActive(false)
processor->terminate()
controller->terminate()
// Release all COM references
```

---

## AudioUnit Hosting (macOS)

### AUv2 Sekvenca

```c
// DISCOVERY
AudioComponent comp = AudioComponentFindNext(NULL, &desc);

// INSTANTIATION (sync, blokira 2+ sec na Mojave+)
AudioUnit unit;
AudioComponentInstanceNew(comp, &unit);

// STREAM FORMAT (pre initialization!)
AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat,
    kAudioUnitScope_Input, 0, &asbd, sizeof(asbd));

// RENDER CALLBACK (host šalje audio pluginu)
AURenderCallbackStruct callback = { MyRenderCallback, myContext };
AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback,
    kAudioUnitScope_Input, 0, &callback, sizeof(callback));

// INITIALIZE
AudioUnitInitialize(unit);

// RENDER (audio thread)
AudioUnitRender(unit, &flags, &timeStamp, outputBus, numFrames, &bufferList);

// CLEANUP
AudioUnitUninitialize(unit);
AudioComponentInstanceDispose(unit);
```

### AUv3 Razlike

- **MORA async:** `AudioComponentInstantiate(comp, options, completionHandler)`
- **GUI:** `kAudioUnitProperty_RequestViewController` (ne CocoaUI)
- Apple: **UVEK koristiti async instantiation** za forward compatibility

### AU GUI

**AUv2:**
```c
AudioUnitGetProperty(unit, kAudioUnitProperty_CocoaUI, ...);
// → bundle URL + NSView class → uiViewForAudioUnit:withSize:
```

**AUv3:**
```objc
[auAudioUnit requestViewControllerWithCompletionHandler:^(AUViewControllerBase *vc) {
    // vc.view je NSView za embedding
}];
```

### AU State

```c
// SAVE: kAudioUnitProperty_ClassInfo → CFDictionary (plist)
// RESTORE: AudioUnitSetProperty(kAudioUnitProperty_ClassInfo, ...)
```

### AU Parameters

```c
AudioUnitSetParameter(unit, paramID, kAudioUnitScope_Global, 0, value, 0);
// Thread-safe — može se zvati sa bilo kog thread-a

// Latency
Float64 latency;
AudioUnitGetProperty(unit, kAudioUnitProperty_Latency, ...);
```

### Logic Pro Specifics

- Logic koristi `AUHostingServiceXPC` za out-of-process AUv3 hosting
- AUv2 se hostuje in-process
- Plugin scanning: `AudioComponentFindNext` iteracija + `AudioComponentCopyName`

---

## CLAP Hosting

### Discovery i Loading

```c
// Scan .clap fajlove (shared libraries)
// macOS: ~/Library/Audio/Plug-Ins/CLAP, /Library/Audio/Plug-Ins/CLAP

extern "C" const clap_plugin_entry_t clap_entry;
clap_entry.init(plugin_path);

const clap_plugin_factory_t *factory =
    clap_entry.get_factory(CLAP_PLUGIN_FACTORY_ID);

const clap_plugin_t *plugin =
    factory->create_plugin(factory, &my_host, desc->id);
```

### Lifecycle

```c
plugin->init(plugin);                    // main thread
plugin->activate(plugin, sampleRate, minFrames, maxFrames);  // main
plugin->start_processing(plugin);        // audio thread
// ... process loop ...
plugin->stop_processing(plugin);         // audio thread
plugin->deactivate(plugin);              // main thread
plugin->destroy(plugin);                 // main thread
clap_entry.deinit();
```

### Audio Processing

```c
clap_process_t process = {
    .frames_count = numFrames,
    .audio_inputs = &audio_in,     // audio_in.data32[channel][sample]
    .audio_outputs = &audio_out,
    .in_events = &input_events,
    .out_events = &output_events,
};
clap_process_status status = plugin->process(plugin, &process);
```

### CLAP GUI (clap_plugin_gui extension)

```c
const clap_plugin_gui_t *gui = plugin->get_extension(plugin, CLAP_EXT_GUI);
gui->is_api_supported(plugin, CLAP_WINDOW_API_COCOA, false);
gui->create(plugin, CLAP_WINDOW_API_COCOA, false);  // false = embedded
gui->get_size(plugin, &width, &height);

clap_window_t window = { .api = CLAP_WINDOW_API_COCOA, .cocoa = parentNSView };
gui->set_parent(plugin, &window);
gui->show(plugin);
// Close: gui->hide → gui->destroy
```

### clap_host Interface

```c
static const clap_host_t my_host = {
    .name = "FluxForge Studio",
    .get_extension = host_get_extension,
    .request_restart = host_request_restart,
    .request_process = host_request_process,
    .request_callback = host_request_callback,
};
```

---

## Zajednički Paterni (Logic/Cubase/Reaper)

### Threading Model

| Operacija | Thread | Napomene |
|-----------|--------|----------|
| Scanning/Discovery | Background | Reaper: 16 parallel threads |
| Instantiation | Main | AUv3: async callback |
| initialize/terminate | Main | Jednom |
| setupProcessing/setActive | Main | Pre/posle processing-a |
| process() | Audio | **ZERO** alokacija/lockova |
| GUI create/show/destroy | Main | Uvek |
| Param set iz GUI | Main → queue → audio | Lock-free queue |
| Param output iz procesora | Audio → dispatch → main | 60Hz timer flush |

### Insert Chain Audio Routing

```
Input → [Plugin 1 (lat=L1)] → [Plugin 2 (lat=L2)] → [Plugin 3 (lat=L3)] → Output
Ukupni delay: L1+L2+L3
```

- **Pre-alocirani bufferi** — NIKAD alokacija u audio thread-u
- **In-place processing** — input i output isti buffer gde plugin dozvoli
- **Double buffering** — dva buffera ping-pong između plugina u chain-u
- **Wet/dry mix** — dry buffer kopija pre processing-a, pa blend

### PDC (Plugin Delay Compensation)

```
1. totalLatency[ch] = sum(plugin.latency za sve inserte na kanalu)
2. maxLatency = max(totalLatency[ch] za sve kanale)
3. delayNeeded[ch] = maxLatency - totalLatency[ch]  → circular delay buffer
4. Record: pomeri recording poziciju za totalLatency tog kanala
5. kLatencyChanged → recalc, crossfade za glatku tranziciju
```

Za parallel routing (sends/aux): graph traversal (topological sort) za najduži path.

### State Management

- **VST3:** `IComponent::getState()` + `IEditController::getState()` → binary streams
- **AU:** `kAudioUnitProperty_ClassInfo` → CFDictionary (plist)
- **CLAP:** `clap_plugin_state::save/load(stream)`

---

## FluxForge Studio — Implementacioni Prioriteti

### Trenutno stanje

| Oblast | Status |
|--------|--------|
| Plugin scan (AU/VST3) | RADI — `rf-plugin/scanner.rs` |
| Plugin load (rack crate) | RADI — ali fallback na passthrough ako rack ne uspe |
| AU editor GUI | RADI — `rf-plugin-host` subprocess, AUv3 API |
| VST3 editor GUI (macOS) | NE RADI — rack 0.4.8 ne podržava VST3 GUI na macOS |
| CLAP load/process | STUB — `clap.rs` |
| Audio signal kroz chain | RADI ako rack uspe, passthrough ako ne |
| PDC | DELIMIČNO — `PdcManager` postoji ali nema graph-aware calc |

### Šta treba za "sve da radi"

1. **VST3 GUI na macOS** — `vst3-sys` crate za direktan IPlugView pristup umesto rack-a
2. **CLAP hosting** — `clack` crate ili direktni C FFI
3. **Proper IComponentHandler** — beginEdit/performEdit/endEdit flow
4. **Unified GUI embedding** — NSWindow sa `addSubview:` (defer:YES, bez wantsLayer)
5. **PDC recalc** na `kLatencyChanged` signal

### Rust Ecosystem

- **`vst3-sys`** — raw VST3 COM bindings
- **`clack`** (prokopyl/clack) — safe CLAP host wrapper
- **`baseview`** — native window za embedding
- **`nih-plug`** — referentni kod (plugin side, ne host)

### Izvori

- [VST3 API Docs](https://steinbergmedia.github.io/vst3_dev_portal/)
- [Apple AU Hosting Guide](https://developer.apple.com/documentation/audiotoolbox/hosting-audio-unit-extensions-using-the-auv2-api)
- [CLAP Spec](https://github.com/free-audio/clap)
- [CLAP Reference Host](https://github.com/free-audio/clap-host)
- [JUCE AudioPluginHost](https://github.com/juce-framework/JUCE/tree/master/extras/AudioPluginHost)
- [Reaper SDK](https://www.reaper.fm/sdk/plugin/plugin.php)
