# VST Hosting Architecture — FluxForge Studio

> Detaljan plan za hostovanje VST3/AU/CLAP/LV2 plugina unutar FluxForge DAW-a.
> Fokus: Kontakt, Serum, Omnisphere, Massive X, i svi popularni VST instrumenti/efekti.

---

## 1. Trenutno Stanje (rf-plugin crate)

### 1.1 Infrastruktura koja POSTOJI

```
rf-plugin/
├── src/
│   ├── lib.rs          — Plugin trait, PluginHost, format dispatch
│   ├── scanner.rs      — 16-thread parallel scanner (rayon)
│   ├── formats/
│   │   ├── vst3.rs     — VST3 via `rack` crate (COM interfaces)
│   │   ├── au.rs       — AudioUnit via `rack` (CoreAudio)
│   │   ├── clap.rs     — CLAP stub (entry point parsing only)
│   │   └── lv2.rs      — LV2 stub (lilv discovery only)
│   ├── chain/
│   │   ├── insert_chain.rs  — Zero-copy processing chain
│   │   ├── plugin_pdc.rs    — Plugin Delay Compensation
│   │   └── buffer_pool.rs   — Pre-allocated buffer management
│   ├── state/
│   │   ├── persistence.rs   — .ffstate binary format
│   │   └── preset_bank.rs   — Internal preset management
│   └── gui/
│       ├── host_window.rs   — Native window embedding
│       └── cocoa_bridge.rs  — macOS NSView hosting (AU CocoaUI)
```

**Ukupno: 7,385 LOC**

| Komponenta | Status | Detalji |
|---|---|---|
| VST3 loading | ✅ Radi | `rack` crate, COM factory → component |
| AU loading | ✅ Radi | CoreAudio AudioComponentDescription |
| CLAP loading | 🟡 Stub | Entry point parsing, no process call |
| LV2 loading | 🟡 Stub | lilv discovery, no instantiation |
| 16-thread scanner | ✅ Radi | 3000 plugins/min, format detection |
| Zero-copy chain | ✅ Radi | BufferPool + insert ordering |
| PDC compensation | ✅ Radi | Automatic latency alignment |
| Lock-free params | ✅ Radi | rtrb ring buffer UI→Audio |
| Plugin state save | ✅ Radi | .ffstate binary chunks |
| Native GUI (AU) | ✅ Radi | CocoaUI NSView embedding |
| Native GUI (VST3) | 🟡 Partial | IPlugView created, sizing issues |
| Preset browser | ❌ Nema | No factory preset enumeration |
| Sidechain routing | ❌ Nema | Single stereo bus only |
| Plugin automation | ❌ Nema | No parameter → timeline lane mapping |

### 1.2 FFI Bridge (30+ funkcija)

```rust
// rf-bridge/src/lib.rs — Plugin-related FFI
pub extern "C" fn scan_plugins(path: *const c_char) -> i32;
pub extern "C" fn load_plugin(plugin_id: *const c_char, track_id: i32) -> i32;
pub extern "C" fn unload_plugin(track_id: i32, slot: i32) -> i32;
pub extern "C" fn set_plugin_param(track_id: i32, slot: i32, param_id: u32, value: f32);
pub extern "C" fn get_plugin_param(track_id: i32, slot: i32, param_id: u32) -> f32;
pub extern "C" fn get_plugin_param_count(track_id: i32, slot: i32) -> i32;
pub extern "C" fn get_plugin_param_name(track_id: i32, slot: i32, param_id: u32) -> *const c_char;
pub extern "C" fn save_plugin_state(track_id: i32, slot: i32) -> *const u8;
pub extern "C" fn load_plugin_state(track_id: i32, slot: i32, data: *const u8, len: u32);
pub extern "C" fn open_plugin_editor(track_id: i32, slot: i32) -> i32;
pub extern "C" fn close_plugin_editor(track_id: i32, slot: i32);
pub extern "C" fn get_plugin_latency(track_id: i32, slot: i32) -> i32;
// ... 18 more functions
```

### 1.3 Flutter Provajderi

```
PluginProvider         — Scanner state, filtered list, favorites, search
DspChainProvider       — Insert chain management, node CRUD, bypass/wetDry
PluginEditorProvider   — GUI window lifecycle (planned)
```

---

## 2. VST Hosting — Šta Treba za Production

### 2.1 Problem: Zašto je Ovo Najbitnija Stvar

FluxForge bez VST hostinga = DAW bez instrumenata. Korisnici očekuju:

1. **Kontakt 7** (Native Instruments) — 90% producenata koristi
2. **Serum** (Xfer) — Najkorišćeniji wavetable synth
3. **Omnisphere 2** (Spectrasonics) — Flagship softver synth
4. **Massive X** (Native Instruments) — Modular synth
5. **Spitfire Audio** — Orchestral libraries
6. **FabFilter Pro-Q 3 / Pro-L 2** — Referentni efekti
7. **Valhalla** reverbs — Budget reverb standard
8. **iZotope Ozone / Neutron** — Mastering/mixing suites
9. **Waves** plugins — Legacy industrija standard
10. **Arturia** V Collection — Vintage synth emulacije

Bez podrške za ove plugine, FluxForge je igračka. Sa punom podrškom, konkuriše Cubase/Logic/Ableton.

### 2.2 Zahtevi po Prioritetu

#### P0 — Kritično (bez ovoga DAW ne može da radi)

| # | Feature | Opis |
|---|---|---|
| P0.1 | **VST3 Instrument Hosting** | MIDI input → plugin → audio output na instrument track |
| P0.2 | **VST3 Effect Insert** | Audio in → plugin → audio out na audio/bus track |
| P0.3 | **Plugin GUI Window** | Floating native window sa plugin UI |
| P0.4 | **Plugin State Persistence** | Save/load plugin state sa projektom |
| P0.5 | **Plugin Delay Compensation** | Automatsko latency poravnanje u chain-u |
| P0.6 | **Multi-output Instruments** | Kontakt 16 stereo out → individual tracks |
| P0.7 | **Sample Rate Handling** | Plugin notification on SR change, SR bridging |

#### P1 — Važno (očekivano od DAW-a)

| # | Feature | Opis |
|---|---|---|
| P1.1 | **Plugin Parameter Automation** | Parameter → automation lane na timeline |
| P1.2 | **Preset Browser** | Factory + user presets, kategorije, favorites |
| P1.3 | **Sidechain Input** | Plugin sidechain bus routing (Pro-C 2, etc.) |
| P1.4 | **Plugin Sandboxing** | Crash isolation — plugin crash ≠ DAW crash |
| P1.5 | **AU Instrument Hosting** | macOS AudioUnit instruments (Logic kompatibilnost) |
| P1.6 | **MIDI Learn** | Controller → plugin parameter mapping |
| P1.7 | **Plugin Search & Categories** | Brza pretraga, tagovi, favorites |

#### P2 — Napredno (kompetitivna prednost)

| # | Feature | Opis |
|---|---|---|
| P2.1 | **CLAP Full Support** | Novi format — Bitwig prednost |
| P2.2 | **ARA2 Integration** | Melodyne, SpectraLayers inline editing |
| P2.3 | **Plugin Freeze/Bounce** | CPU offload — render plugin output to audio |
| P2.4 | **Multi-timbral MIDI** | 16 MIDI channels → 1 plugin (Kontakt multis) |
| P2.5 | **Network Plugin Hosting** | Distribute plugin load across machines |
| P2.6 | **Plugin Performance Monitor** | Per-plugin CPU/RAM real-time metrics |
| P2.7 | **AAX Compatibility Layer** | Pro Tools plugin format (optional) |

---

## 3. Arhitektura — Deep Design

### 3.1 Plugin Host Engine (Rust)

```
┌─────────────────────────────────────────────────────┐
│                  AUDIO THREAD                        │
│                                                      │
│  Track 1 ──► [Insert 1] ──► [Insert 2] ──► Bus      │
│                  │               │                    │
│              VST3Effect      VST3Effect               │
│              (Pro-Q 3)       (Pro-L 2)                │
│                                                      │
│  Track 2 ──► [Instrument] ──► [Insert 1] ──► Bus    │
│                  │                │                   │
│              VST3Synth        VST3Effect              │
│              (Kontakt 7)     (Valhalla)               │
│                  │                                    │
│              Multi-Out (16 stereo)                    │
│                  ├─► Aux 1 (Drums)                   │
│                  ├─► Aux 2 (Bass)                    │
│                  ├─► Aux 3 (Strings)                 │
│                  └─► ... Aux 16                      │
│                                                      │
│  Bus Master ──► [Insert 1] ──► [Insert 2] ──► OUT   │
│                    │               │                  │
│                VST3Effect      VST3Effect             │
│                (Ozone 11)     (Limiter)               │
└─────────────────────────────────────────────────────┘
```

### 3.2 Plugin Instance Lifecycle

```rust
/// Core plugin trait — already exists in rf-plugin/src/lib.rs
pub trait PluginInstance: Send {
    // Initialization
    fn initialize(&mut self, sample_rate: f64, max_block: usize) -> Result<()>;
    fn terminate(&mut self);

    // Processing (audio thread — ZERO allocation)
    fn process(&mut self, buffers: &mut ProcessBuffers) -> ProcessResult;
    fn get_latency(&self) -> u32;
    fn get_tail_size(&self) -> u32;

    // Parameters (lock-free ring buffer)
    fn param_count(&self) -> u32;
    fn get_param(&self, id: u32) -> f32;
    fn set_param(&mut self, id: u32, value: f32);
    fn get_param_info(&self, id: u32) -> ParamInfo;

    // State
    fn save_state(&self) -> Vec<u8>;
    fn load_state(&mut self, data: &[u8]) -> Result<()>;

    // Editor GUI
    fn has_editor(&self) -> bool;
    fn open_editor(&mut self, parent: RawWindowHandle) -> Result<EditorHandle>;
    fn close_editor(&mut self);
    fn get_editor_size(&self) -> (u32, u32);

    // === NOVO — Multi-output ===
    fn output_bus_count(&self) -> u32;  // Kontakt: 16
    fn output_bus_info(&self, index: u32) -> BusInfo;

    // === NOVO — Sidechain ===
    fn input_bus_count(&self) -> u32;   // Pro-C 2: 2 (main + SC)
    fn input_bus_info(&self, index: u32) -> BusInfo;

    // === NOVO — MIDI ===
    fn accepts_midi(&self) -> bool;     // Instruments: true
    fn process_midi(&mut self, events: &[MidiEvent]);
}
```

### 3.3 Multi-Output Routing (Kontakt, etc.)

Kontakt 7 podržava do 64 output kanala (32 stereo parova). FluxForge treba:

```
┌──────────────────────────────┐
│  KONTAKT 7 INSTANCE          │
│                               │
│  MIDI In ──────────► Engine   │
│                       │       │
│  Out 1/2   (Main)  ──┼──► Track 1 (Drums)
│  Out 3/4   (Aux 1) ──┼──► Track 2 (Bass)
│  Out 5/6   (Aux 2) ──┼──► Track 3 (Strings)
│  Out 7/8   (Aux 3) ──┼──► Track 4 (Brass)
│  ...                  │
│  Out 31/32 (Aux 15) ──┼──► Track 16 (Perc)
│                       │
└──────────────────────────────┘
```

**Implementacija:**

```rust
// rf-engine/src/mixer/multi_output.rs

pub struct MultiOutputRouter {
    /// Source plugin instance
    source_track: TrackId,
    source_slot: usize,

    /// Output routing map: plugin_bus_index → target_track
    routes: Vec<OutputRoute>,

    /// Intermediate buffers (pre-allocated)
    bus_buffers: Vec<AudioBuffer>,
}

pub struct OutputRoute {
    pub bus_index: u32,      // Plugin output bus (0 = main, 1+ = aux)
    pub target_track: TrackId, // Destination track in mixer
    pub gain: f32,            // Per-route gain
    pub enabled: bool,
}

impl MultiOutputRouter {
    /// Called in audio thread — routes plugin outputs to tracks
    pub fn route_outputs(&self, plugin: &dyn PluginInstance, mixer: &mut Mixer) {
        for route in &self.routes {
            if !route.enabled { continue; }
            let bus = &self.bus_buffers[route.bus_index as usize];
            mixer.add_to_track(route.target_track, bus, route.gain);
        }
    }
}
```

**Flutter strana:**

```dart
// Multi-output routing UI u mixer-u
class MultiOutputConfig {
  final String pluginId;
  final int sourceTrack;
  final List<OutputRouteConfig> routes;
}

class OutputRouteConfig {
  final int busIndex;
  final String busName;     // "Drums", "Bass", etc.
  final int? targetTrack;   // null = not routed
  final double gain;
}
```

### 3.4 Plugin GUI Hosting

VST plugini imaju native GUI (NSView na macOS, HWND na Windows). FluxForge mora:

1. **Kreirati native child window** za plugin editor
2. **Embedovati u Flutter layout** (ili floating window)
3. **Handle resize** (plugin može da menja veličinu)
4. **Sync sa dark/light mode** (gde plugin podržava)

```
┌─────────────────────────────────────────┐
│  FluxForge Studio (Flutter)              │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  Track Inspector / Plugin Chain     │  │
│  │                                    │  │
│  │  [Pro-Q 3] [Pro-C 2] [Pro-L 2]   │  │
│  │     ↓ double-click                │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌────────────────────────────────────┐  │
│  │  FLOATING PLUGIN WINDOW            │  │
│  │  ┌──────────────────────────────┐ │  │
│  │  │                              │ │  │
│  │  │   NATIVE VST3 GUI            │ │  │
│  │  │   (NSView / HWND)            │ │  │
│  │  │                              │ │  │
│  │  │   FabFilter Pro-Q 3          │ │  │
│  │  │   1280 × 720                 │ │  │
│  │  │                              │ │  │
│  │  └──────────────────────────────┘ │  │
│  │  [Bypass] [A/B] [Preset ▼] [×]   │  │
│  └────────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**macOS implementacija:**

```rust
// rf-plugin/src/gui/cocoa_bridge.rs (vec postoji — treba prosiriti)

pub struct PluginEditorWindow {
    ns_window: *mut Object,      // NSWindow
    plugin_view: *mut Object,    // NSView from plugin
    resize_observer: ResizeObserver,

    // NOVO
    title_bar: bool,             // Show FluxForge title bar
    always_on_top: bool,         // Float above main window
    dark_mode: bool,             // Sync with FluxForge theme
}

impl PluginEditorWindow {
    pub fn open(plugin: &mut dyn PluginInstance, parent: Option<NSWindow>) -> Self {
        // 1. Create NSWindow (borderless or titled)
        // 2. Get plugin editor size
        // 3. Call plugin.open_editor(window_handle)
        // 4. Set up resize callback
        // 5. Position relative to parent
    }

    pub fn close(&mut self, plugin: &mut dyn PluginInstance) {
        plugin.close_editor();
        // Release NSWindow
    }
}
```

### 3.5 Plugin Sandboxing (Crash Isolation)

Kritično za production. Jedan crashujući plugin NE SME da sruši ceo DAW.

```
┌─────────────────────────────────────────────────┐
│  FLUXFORGE MAIN PROCESS                          │
│                                                   │
│  Audio Thread ──────────────────────────────────  │
│       │                                           │
│       ├── Internal DSP (eq, comp, etc.) — in-proc │
│       │                                           │
│       ├── Trusted Plugins — in-process            │
│       │   (FabFilter, Valhalla — known stable)    │
│       │                                           │
│       └── IPC Bridge ──► Plugin Sandbox Process   │
│                           │                       │
│                     ┌─────┴─────┐                 │
│                     │ SANDBOX   │                 │
│                     │           │                 │
│                     │ Kontakt 7 │                 │
│                     │ (may crash)│                │
│                     │           │                 │
│                     │ Shared    │                 │
│                     │ Memory    │                 │
│                     │ Audio I/O │                 │
│                     └───────────┘                 │
└─────────────────────────────────────────────────┘
```

**Strategija:**

| Mode | Kada | Latency | Safety |
|---|---|---|---|
| **In-Process** | Trusted, stabilni plugini | 0 samples | Plugin crash = DAW crash |
| **Sandboxed** | Nepoznati, nestabilni | +64-256 samples | Plugin crash → restart bez gubitka |

```rust
// rf-plugin/src/sandbox/mod.rs (NOVO)

pub struct SandboxedPlugin {
    child_process: std::process::Child,
    shared_audio: SharedMemoryRegion,  // mmap audio buffers
    command_pipe: UnixStream,           // control messages
    heartbeat: AtomicU64,              // watchdog
}

impl SandboxedPlugin {
    pub fn spawn(plugin_path: &Path) -> Result<Self> {
        // 1. Fork child process (rf-plugin-host binary)
        // 2. Set up shared memory for audio (zero-copy)
        // 3. Set up command pipe for param/state/GUI
        // 4. Start heartbeat watchdog (500ms timeout)
    }

    /// Audio thread: write input → signal → read output
    pub fn process(&self, input: &AudioBuffer, output: &mut AudioBuffer) {
        self.shared_audio.write_input(input);
        self.shared_audio.signal_process();
        self.shared_audio.wait_output();  // spin-wait, bounded
        self.shared_audio.read_output(output);
    }

    /// Watchdog detects crash → restart
    pub fn check_health(&self) -> PluginHealth {
        let last = self.heartbeat.load(Ordering::Relaxed);
        if elapsed_ms(last) > 500 {
            PluginHealth::Crashed
        } else {
            PluginHealth::Running
        }
    }
}
```

### 3.6 Plugin Parameter Automation

Svaki plugin parametar mora moći da se automatizuje na timeline-u:

```
┌─────────────────────────────────────────────┐
│  AUTOMATION LANE: Pro-Q 3 — Band 1 Freq     │
│                                               │
│  ╭─────╮                    ╭──────╮         │
│  │     ╰────────────────────╯      ╰──────  │
│  │                                           │
│  ├───┼───┼───┼───┼───┼───┼───┼───┼───┼───  │
│  1   2   3   4   5   6   7   8   9   10  bar│
└─────────────────────────────────────────────┘
```

```rust
// rf-engine/src/automation/plugin_automation.rs (NOVO)

pub struct PluginAutomationLane {
    pub track_id: TrackId,
    pub plugin_slot: usize,
    pub param_id: u32,
    pub param_name: String,
    pub points: Vec<AutomationPoint>,
    pub mode: AutomationMode,  // Read/Write/Touch/Latch
}

/// Called per-sample in audio thread
pub fn read_automation(
    lane: &PluginAutomationLane,
    position: u64,  // samples
) -> f32 {
    // Binary search + interpolation (already exists in AutomationProvider)
    // Returns normalized 0.0..1.0
}
```

**Flutter strana — parameter discovery:**

```dart
class PluginParameterInfo {
  final int paramId;
  final String name;
  final String label;      // "Hz", "dB", "%"
  final double minValue;
  final double maxValue;
  final double defaultValue;
  final bool isAutomatable;
  final int stepCount;      // 0 = continuous, N = stepped
  final List<String>? valueStrings;  // For enum params
}

// In AutomationProvider
void createPluginAutomationLane(int trackId, int slot, int paramId) {
  final paramInfo = NativeFFI.instance.getPluginParamInfo(trackId, slot, paramId);
  final lane = AutomationLane(
    id: 'plugin_${trackId}_${slot}_${paramId}',
    name: paramInfo.name,
    minValue: paramInfo.minValue,
    maxValue: paramInfo.maxValue,
  );
  addLane(trackId, lane);
}
```

### 3.7 Preset Management

```
┌───────────────────────────────────────────────┐
│  PRESET BROWSER                                │
│                                                 │
│  ┌─────────────────┐  ┌─────────────────────┐ │
│  │ CATEGORIES       │  │ PRESETS              │ │
│  │                  │  │                      │ │
│  │ ▸ Factory        │  │ ★ Init Patch         │ │
│  │   ▸ Synth Leads  │  │   Dark Pad           │ │
│  │   ▸ Pads         │  │   Warm Strings       │ │
│  │   ▸ Bass         │  │ ★ 80s Poly           │ │
│  │   ▸ Keys         │  │   Moog Lead          │ │
│  │ ▸ User           │  │   Tape Wobble        │ │
│  │   ▸ My Presets   │  │   ... (124 more)     │ │
│  │   ▸ Favorites    │  │                      │ │
│  │ ▸ Downloaded     │  │ [Load] [Save As]     │ │
│  └─────────────────┘  └─────────────────────┘ │
└───────────────────────────────────────────────┘
```

```rust
// rf-plugin/src/state/preset_browser.rs (NOVO)

pub struct PresetBrowser {
    /// Factory presets from plugin (VST3 unitData/programData)
    factory_presets: Vec<PresetEntry>,

    /// User presets (~/.fluxforge/presets/<plugin_id>/)
    user_presets: Vec<PresetEntry>,

    /// Current preset index
    current: Option<usize>,
}

pub struct PresetEntry {
    pub name: String,
    pub category: String,
    pub tags: Vec<String>,
    pub is_favorite: bool,
    pub data: LazyPresetData,  // Loaded on demand
}

impl PresetBrowser {
    /// VST3: enumerate via IUnitInfo / IProgramListData
    pub fn scan_factory_presets(plugin: &dyn PluginInstance) -> Vec<PresetEntry> { ... }

    /// Load from user directory
    pub fn scan_user_presets(plugin_id: &str) -> Vec<PresetEntry> { ... }

    /// A/B comparison
    pub fn store_a(&mut self, plugin: &dyn PluginInstance) { ... }
    pub fn recall_a(&self, plugin: &mut dyn PluginInstance) { ... }
    pub fn swap_ab(&mut self) { ... }
}
```

---

## 4. Implementacija — Faze

### Faza 1: VST3 Instrument Track (2-3 nedelje)

**Cilj:** Učitaj Kontakt 7, sviraj MIDI, čuj zvuk.

1. **MIDI routing u audio engine**
   - `MidiTrack` tip koji šalje MIDI events u plugin process()
   - MIDI input monitoring (keyboard → plugin)
   - MIDI file playback → plugin

2. **Instrument track tip u mikser**
   - Razlika od audio track: ima MIDI input, nema audio input
   - Plugin je "generator" umesto "processor"
   - Output ide u insert chain kao normalan audio

3. **Plugin GUI window management**
   - Proširiti `cocoa_bridge.rs` za full window lifecycle
   - Double-click na plugin slot → otvori native GUI
   - Window position persistence

4. **Plugin state u projektu**
   - Save: serialize plugin state + chain config
   - Load: restore plugin + params + GUI position

### Faza 2: Multi-Output + Sidechain (2 nedelje)

**Cilj:** Kontakt multi-output radi, Pro-C 2 sidechain radi.

1. **Multi-output bus routing**
   - Plugin output bus enumeration
   - Routing matrix UI (plugin out → mixer track)
   - Aux track creation from plugin outputs

2. **Sidechain input routing**
   - Plugin sidechain bus detection
   - Routing UI (source track → plugin SC input)
   - Pre-fader send for SC signal

### Faza 3: Automation + Presets (1-2 nedelje)

**Cilj:** Automatiziraj bilo koji plugin parametar, presets rade.

1. **Plugin parameter discovery**
   - Enumerate all automatable params via FFI
   - Parameter info (name, range, units, steps)
   - Create automation lane from parameter picker

2. **Automation write modes**
   - Touch: write while moving, return to previous on release
   - Latch: write while moving, hold last value
   - Write: overwrite everything during playback

3. **Preset browser**
   - Factory preset enumeration
   - User preset save/load
   - A/B comparison
   - Favorites

### Faza 4: Sandboxing + Polish (2 nedelje)

**Cilj:** Crash-safe, production-ready.

1. **Sandbox process**
   - `rf-plugin-host` binary za out-of-process hosting
   - Shared memory audio transport
   - Crash detection + automatic restart

2. **Plugin performance monitoring**
   - Per-plugin CPU metering
   - Memory usage tracking
   - Audio dropout detection

3. **CLAP full support**
   - Complete CLAP host implementation
   - CLAP-specific features (polyphonic modulation, note expressions)

---

## 5. Specifični Plugin Zahtevi

### 5.1 Kontakt 7 (Native Instruments)

Kontakt je NAJKRITIČNIJI plugin za podršku. 90%+ producenata ga koristi.

| Feature | Zahtev | Prioritet |
|---|---|---|
| VST3 loading | Standard VST3 COM | P0 |
| Multi-output (16 stereo) | output_bus_count() = 32 channels | P0 |
| Multi-timbral MIDI | 16 MIDI channels → 1 instance | P2 |
| Large RAM (50GB+ libraries) | 64-bit process, memory mapping | P0 |
| Factory preset support | NKS format | P1 |
| Batch resave | Background scanning | P2 |
| Wavetable display | Custom GUI (native NSView) | P0 |

**Kontakt specifičnosti:**
- Koristi massive amounts of RAM (veliki library-ji 50GB+)
- Sandboxing OBAVEZNO — Kontakt crash je čest kod velikih libraries
- Multi-output setup mora biti "jedan klik" — korisnik bira "16 Stereo Out" i FluxForge automatski kreira aux tracks

### 5.2 Serum (Xfer)

| Feature | Zahtev | Prioritet |
|---|---|---|
| VST3 loading | Standard | P0 |
| Wavetable import | File drag → plugin | P1 |
| Modulation matrix display | Native GUI | P0 |
| CPU intensive | Per-voice processing | Sandbox optional |
| Preset .fxp/.fxb | Legacy format support | P1 |

### 5.3 Omnisphere 2 (Spectrasonics)

| Feature | Zahtev | Prioritet |
|---|---|---|
| AU loading (macOS primary) | AudioUnit hosting | P0 |
| Massive library (100GB+) | Disk streaming | P0 |
| STEAM engine integration | Custom file paths | P1 |
| Multi-timbral (8 parts) | MIDI channel routing | P2 |

### 5.4 iZotope Suite (Ozone, Neutron)

| Feature | Zahtev | Prioritet |
|---|---|---|
| VST3 loading | Standard | P0 |
| Inter-plugin communication | iZotope relay system | P2 |
| Visual feedback sync | Plugin → DAW metering | P1 |
| Sidechain (Neutron) | SC bus routing | P1 |

---

## 6. Tehnički Detalji — Audio Thread Safety

### 6.1 Lock-Free Parameter Updates

```rust
// Existing pattern in rf-plugin — extend for all params

use rtrb::RingBuffer;

pub struct PluginParamBridge {
    /// UI → Audio: parameter changes
    param_tx: rtrb::Producer<ParamChange>,
    param_rx: rtrb::Consumer<ParamChange>,

    /// Audio → UI: parameter feedback (automation read, plugin internal changes)
    feedback_tx: rtrb::Producer<ParamFeedback>,
    feedback_rx: rtrb::Consumer<ParamFeedback>,
}

#[repr(C)]
pub struct ParamChange {
    param_id: u32,
    value: f32,
    sample_offset: u32,  // For sample-accurate automation
}

// Audio thread — process all pending changes before plugin.process()
fn apply_param_changes(plugin: &mut dyn PluginInstance, bridge: &PluginParamBridge) {
    while let Ok(change) = bridge.param_rx.pop() {
        plugin.set_param(change.param_id, change.value);
    }
}
```

### 6.2 MIDI Event Processing

```rust
// rf-engine/src/midi/plugin_midi.rs (NOVO)

/// MIDI events sorted by sample offset for sample-accurate timing
pub struct MidiBuffer {
    events: Vec<TimestampedMidiEvent>,
    capacity: usize,
}

#[repr(C)]
pub struct TimestampedMidiEvent {
    pub sample_offset: u32,
    pub status: u8,
    pub data1: u8,
    pub data2: u8,
    pub channel: u8,  // 0-15 for multi-timbral
}

impl MidiBuffer {
    /// Pre-allocated, reused per block
    pub fn new(capacity: usize) -> Self { ... }

    /// Audio thread: merge MIDI sources (keyboard + timeline + arpeggiator)
    pub fn merge(&mut self, sources: &[&MidiBuffer]) { ... }
}
```

### 6.3 Buffer Management

```rust
// rf-plugin/src/chain/buffer_pool.rs (vec postoji — prosiriti)

pub struct BufferPool {
    /// Pre-allocated audio buffers
    buffers: Vec<AudioBuffer>,
    /// Free list (lock-free)
    free_list: crossbeam::queue::ArrayQueue<usize>,
}

/// Extended for multi-output
pub struct ProcessBuffers {
    pub inputs: Vec<AudioBusBuffer>,    // Main + sidechain inputs
    pub outputs: Vec<AudioBusBuffer>,   // Main + aux outputs
    pub midi_in: MidiBuffer,
    pub midi_out: MidiBuffer,           // For MIDI effects
    pub transport: TransportInfo,
    pub block_size: usize,
}

pub struct AudioBusBuffer {
    pub channels: Vec<*mut f32>,  // Channel pointers (non-owning)
    pub channel_count: u32,
    pub name: String,
}
```

---

## 7. Flutter UI — Plugin Chain u DAW

### 7.1 Insert Chain Strip

```
┌──────────────────────────────────┐
│  TRACK 1: DRUMS                   │
│                                    │
│  ┌──────────────────────────────┐ │
│  │ 🔌 Kontakt 7          [≡][×] │ │  ← Instrument slot
│  │    "Studio Drummer"           │ │
│  ├──────────────────────────────┤ │
│  │ 1. Pro-Q 3            [○][×] │ │  ← Insert 1 (bypass dot)
│  │ 2. Pro-C 2    [SC▸Bus2][○]  │ │  ← Insert 2 (sidechain indicator)
│  │ 3. Pro-L 2            [○][×] │ │  ← Insert 3
│  │ 4. ─── empty slot ────────── │ │  ← Click to add
│  │ 5. ─── empty slot ────────── │ │
│  │ 6. ─── empty slot ────────── │ │
│  │ 7. ─── empty slot ────────── │ │
│  │ 8. ─── empty slot ────────── │ │
│  ├──────────────────────────────┤ │
│  │ [SENDS]                      │ │
│  │ S1: Bus 3 (Reverb)  -12dB   │ │
│  │ S2: Bus 4 (Delay)   -18dB   │ │
│  └──────────────────────────────┘ │
└──────────────────────────────────┘
```

### 7.2 Plugin Browser (proširenje PluginsScannerPanel)

```
┌───────────────────────────────────────────────┐
│ PLUGINS                              [Rescan] │
│ ┌─────────────────────────────────────────┐   │
│ │ 🔍 Search plugins...                    │   │
│ └─────────────────────────────────────────┘   │
│ [All] [VST3] [AU] [CLAP] [★ Fav]  [Inst|FX] │
│                                                │
│ INSTRUMENTS                                    │
│ ├── Kontakt 7 (Native Instruments)     [★]    │
│ ├── Serum (Xfer Records)               [★]    │
│ ├── Omnisphere 2 (Spectrasonics)       [★]    │
│ ├── Massive X (Native Instruments)     [ ]    │
│ └── Vital (Matt Tytel)                 [★]    │
│                                                │
│ EFFECTS                                        │
│ ├── Pro-Q 3 (FabFilter)               [★]    │
│ ├── Pro-C 2 (FabFilter)               [★]    │
│ ├── Pro-L 2 (FabFilter)               [★]    │
│ ├── Valhalla Shimmer (Valhalla DSP)    [ ]    │
│ └── Ozone 11 (iZotope)                [ ]    │
│                                                │
│ RECENTLY USED                                  │
│ ├── Pro-Q 3                        (2 min ago) │
│ └── Kontakt 7                      (5 min ago) │
└───────────────────────────────────────────────┘
```

---

## 8. Project File Integration

### 8.1 Plugin State u .ffproject

```json
{
  "tracks": [
    {
      "id": 1,
      "name": "Drums",
      "type": "instrument",
      "instrument": {
        "plugin_id": "com.native-instruments.kontakt.vst3",
        "state": "<base64 encoded plugin state>",
        "multi_output": {
          "enabled": true,
          "routes": [
            { "bus": 0, "target_track": 1, "name": "Main" },
            { "bus": 1, "target_track": 5, "name": "Kick" },
            { "bus": 2, "target_track": 6, "name": "Snare" }
          ]
        },
        "gui": {
          "visible": true,
          "x": 100, "y": 200,
          "width": 1280, "height": 720
        }
      },
      "inserts": [
        {
          "slot": 0,
          "plugin_id": "com.fabfilter.pro-q3.vst3",
          "state": "<base64>",
          "bypass": false,
          "wet_dry": 1.0,
          "sidechain_source": null
        },
        {
          "slot": 1,
          "plugin_id": "com.fabfilter.pro-c2.vst3",
          "state": "<base64>",
          "bypass": false,
          "wet_dry": 1.0,
          "sidechain_source": "bus_2"
        }
      ],
      "automation_lanes": [
        {
          "param_source": "insert_0_param_42",
          "param_name": "Band 1 Freq",
          "points": [
            { "time": 0, "value": 0.5 },
            { "time": 48000, "value": 0.8, "curve": "smooth" }
          ]
        }
      ]
    }
  ]
}
```

---

## 9. Konkurentska Analiza

| Feature | Logic Pro | Cubase 14 | Ableton 12 | FL Studio | **FluxForge** |
|---|---|---|---|---|---|
| VST3 | ✅ | ✅ | ✅ | ✅ | ✅ (radi) |
| AU | ✅ | ✅ | ✅ | ❌ | ✅ (radi) |
| CLAP | ❌ | ❌ | ❌ | ❌ | 🟡 (planned) |
| AAX | ❌ | ❌ | ❌ | ❌ | ❌ |
| ARA2 | ✅ | ✅ | ❌ | ❌ | 🟡 (stub) |
| Sandboxing | ✅ (AU) | ✅ | ❌ | ❌ | 🔲 (planned) |
| Multi-out | ✅ | ✅ | ✅ | ✅ | 🔲 (planned) |
| Plugin freeze | ✅ | ✅ | ✅ | ✅ | 🔲 (planned) |
| CLAP poly mod | ❌ | ❌ | ❌ | ❌ | 🔲 (P2) |

**FluxForge prednost:** CLAP first-class support (jedini pored Bitwiga) + Rust audio engine performance.

---

## 10. Rizici i Mitigacija

| Rizik | Verovatnoća | Uticaj | Mitigacija |
|---|---|---|---|
| VST3 SDK licensing | Niska | Visok | `rack` crate koristi clean-room impl |
| Plugin crash sruši DAW | Visoka | Kritičan | Sandboxing (Faza 4) |
| Multi-output latency | Srednja | Srednji | PDC calculator za aux routes |
| macOS Gatekeeper blokira plugin | Srednja | Nizak | Uputstvo za codesign exemption |
| 32-bit plugin podrška | Niska | Nizak | Ignorišemo — 2026, svi su 64-bit |
| Plugin GUI DPI scaling | Srednja | Srednji | HiDPI-aware window hosting |
| Large Kontakt libraries (100GB+) | Niska | Nizak | Disk streaming, ne RAM loading |

---

## 11. Timeline

```
Nedelja 1-2:  Faza 1a — MIDI routing + Instrument track
Nedelja 3:    Faza 1b — Plugin GUI windows
Nedelja 4:    Faza 1c — Plugin state persistence
Nedelja 5-6:  Faza 2  — Multi-output + Sidechain
Nedelja 7-8:  Faza 3  — Automation + Presets
Nedelja 9-10: Faza 4  — Sandboxing + CLAP + Polish
```

**Ukupno: ~10 nedelja do full VST hosting.**

Posle toga FluxForge ima sve što treba da bude ozbiljan DAW.
