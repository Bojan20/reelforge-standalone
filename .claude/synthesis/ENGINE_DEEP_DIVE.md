# FluxForge Engine — Deep Dive: 4 Critical Features

> Tehnička specifikacija za implementaciju 4 revolucionarna engine feature-a
> Ekstrahirano iz REAPER 7, Cubase Pro 14, Pyramix 15 analiza

---

## 1. ANTICIPATIVE FX PROCESSING (REAPER)

### 1.1 Problem koji rešava

```
┌─────────────────────────────────────────────────────────────┐
│ STANDARDNI DAW — REAL-TIME CONSTRAINT                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Buffer Size: 256 samples @ 48kHz = 5.33ms                  │
│                                                              │
│  Timeline:                                                   │
│  ├─────────────────────────────────────────────────────────┤│
│  │ t=0ms        │ t=5.33ms      │ t=10.66ms     │ ...      ││
│  │ Buffer 1     │ Buffer 2      │ Buffer 3      │          ││
│  ├─────────────────────────────────────────────────────────┤│
│                                                              │
│  SVE PROCESSING mora završiti unutar 5.33ms:                │
│                                                              │
│  Track 1: EQ (0.2ms) + Comp (0.3ms) = 0.5ms    ✓           │
│  Track 2: EQ (0.2ms) + Reverb (2ms) = 2.2ms    ✓           │
│  Track 3: Linear Phase EQ (8ms latency) = ???   ✗          │
│                                                              │
│  Problem: Plugin sa 8ms latency NE MOŽE raditi              │
│  u 5.33ms buffer-u bez glitch-a!                            │
│                                                              │
│  Tradicionalno rešenje:                                      │
│  • Povećaj buffer → više latency za monitoring             │
│  • Freeze track → gubi se real-time editovanje             │
│  • Ne koristi heavy plugine → ograničen workflow           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 REAPER Anticipative FX rešenje

```
┌─────────────────────────────────────────────────────────────┐
│ ANTICIPATIVE FX — KAKO REAPER REŠAVA PROBLEM                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Ključna ideja: "Gledaj unapred" (anticipate)               │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    PLAYBACK TRACK                        ││
│  │  (track koji samo pušta audio, bez live input-a)        ││
│  │                                                          ││
│  │  Audio file na disku:                                    ││
│  │  [======================================]                ││
│  │        ↑                                                 ││
│  │        Playhead position                                 ││
│  │                                                          ││
│  │  REAPER zna ŠTA DOLAZI jer čita sa diska!               ││
│  │  Može procesirati UNAPRED, pre nego što treba           ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Workflow:                                                   │
│                                                              │
│  1. REAPER čita audio UNAPRED (npr. 500ms ahead)           │
│  2. Procesira FX chain na background thread-u              │
│  3. Rezultat čeka u buffer-u                               │
│  4. Kada playhead stigne → audio je već spreman            │
│                                                              │
│  Timeline vizualizacija:                                     │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Playhead: ──────────────────►                          ││
│  │             t=0                                          ││
│  │                                                          ││
│  │  Anticipative processing:                                ││
│  │  ═══════════════════════════►                           ││
│  │             t=0        t=500ms                           ││
│  │                        (već procesiran)                  ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Rezultat:                                                   │
│  • Plugin može koristiti VIŠE vremena nego buffer size     │
│  • Linear Phase EQ sa 50ms latency? Nema problema!         │
│  • Convolution reverb sa 100ms? Works!                     │
│  • CPU usage: ~100% iskorišćenost (ne samo burst)          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 Tehnička implementacija

```
┌─────────────────────────────────────────────────────────────┐
│ IMPLEMENTACIJA — PSEUDO-KOD                                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  struct AnticipativeProcessor {                             │
│      // Lookahead buffer (npr. 1 sekunda)                   │
│      lookahead_samples: usize,  // 48000 @ 48kHz           │
│                                                              │
│      // Ring buffer za pre-procesiran audio                 │
│      processed_buffer: RingBuffer<f64>,                     │
│                                                              │
│      // Pozicija do koje smo procesirali                    │
│      processed_until: AtomicU64,                            │
│                                                              │
│      // FX chain za procesiranje                            │
│      fx_chain: Vec<Box<dyn Processor>>,                     │
│  }                                                           │
│                                                              │
│  // BACKGROUND THREAD (non-realtime)                        │
│  fn anticipative_worker(proc: &AnticipativeProcessor) {     │
│      loop {                                                  │
│          // 1. Koliko treba procesirati?                    │
│          let playhead = get_playhead_position();            │
│          let target = playhead + proc.lookahead_samples;    │
│          let current = proc.processed_until.load();         │
│                                                              │
│          if current < target {                              │
│              // 2. Čitaj raw audio sa diska                 │
│              let raw = read_audio(current, CHUNK_SIZE);     │
│                                                              │
│              // 3. Procesiraj kroz FX chain                 │
│              let mut processed = raw;                       │
│              for fx in &proc.fx_chain {                     │
│                  processed = fx.process(processed);         │
│              }                                               │
│                                                              │
│              // 4. Upiši u ring buffer                      │
│              proc.processed_buffer.write(processed);        │
│                                                              │
│              // 5. Update poziciju                          │
│              proc.processed_until.store(current + CHUNK);   │
│          } else {                                            │
│              // Caught up - sleep briefly                   │
│              thread::sleep(Duration::from_micros(100));     │
│          }                                                   │
│      }                                                       │
│  }                                                           │
│                                                              │
│  // AUDIO THREAD (realtime, lock-free)                      │
│  fn audio_callback(output: &mut [f64]) {                    │
│      let playhead = get_playhead_position();                │
│                                                              │
│      // Samo čitaj iz ring buffer-a (ZERO processing!)     │
│      proc.processed_buffer.read_into(output);               │
│  }                                                           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.4 Ograničenja i Edge Cases

```
┌─────────────────────────────────────────────────────────────┐
│ OGRANIČENJA ANTICIPATIVE FX                                 │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  NE RADI ZA:                                                 │
│                                                              │
│  1. LIVE INPUT (record-enabled tracks)                      │
│     • Ne možeš "gledati unapred" live mikrofon             │
│     • Rešenje: Ovi trackovi koriste real-time path         │
│                                                              │
│  2. MIDI → VSTi (virtual instruments)                       │
│     • MIDI se može menjati u real-time                     │
│     • Rešenje: VSTi koristi real-time, post-FX anticipative│
│                                                              │
│  3. SIDECHAIN koji zavisi od live signala                   │
│     • Ako compressor sluša live input                      │
│     • Rešenje: Kompleksnije, potrebna sinhronizacija       │
│                                                              │
│  4. PARAMETER CHANGES u real-time                           │
│     • Ako user pomeri fader tokom playback-a               │
│     • Rešenje: Re-process od trenutne pozicije             │
│     • Ili: Crossfade između starog i novog                 │
│                                                              │
│  EDGE CASES:                                                 │
│                                                              │
│  • Seek/Jump: Mora re-fill buffer od nove pozicije         │
│  • Loop points: Pre-compute loop region                    │
│  • Tempo change: Invalidira pre-computed audio             │
│  • Plugin bypass: Može se ignorisati u chain-u             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.5 FluxForge implementacija: Guard Path

```
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE rf-engine — GUARD PATH ARCHITECTURE               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Već imamo osnovu u rf-engine! Treba proširiti:             │
│                                                              │
│  crates/rf-engine/src/                                      │
│  ├── anticipative.rs      ← NOVO: Anticipative processor   │
│  ├── guard_path.rs        ← Postojeći guard path           │
│  └── routing.rs           ← Routing integracija            │
│                                                              │
│  Arhitektura:                                                │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  ┌─────────────────┐     ┌─────────────────┐            ││
│  │  │   REAL-TIME     │     │   GUARD PATH    │            ││
│  │  │     PATH        │     │  (Anticipative) │            ││
│  │  ├─────────────────┤     ├─────────────────┤            ││
│  │  │ • Live input    │     │ • Playback only │            ││
│  │  │ • VSTi output   │     │ • Heavy FX      │            ││
│  │  │ • Low latency   │     │ • Linear phase  │            ││
│  │  │ • < 3ms         │     │ • Convolution   │            ││
│  │  └────────┬────────┘     └────────┬────────┘            ││
│  │           │                       │                      ││
│  │           └───────────┬───────────┘                      ││
│  │                       ▼                                  ││
│  │              ┌─────────────────┐                        ││
│  │              │   SEAMLESS      │                        ││
│  │              │   CROSSFADE     │                        ││
│  │              └─────────────────┘                        ││
│  │                       │                                  ││
│  │                       ▼                                  ││
│  │              ┌─────────────────┐                        ││
│  │              │     OUTPUT      │                        ││
│  │              └─────────────────┘                        ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Track routing decision:                                     │
│  • has_live_input() → Real-Time Path                        │
│  • has_midi_input() → Real-Time Path (VSTi part)           │
│  • playback_only() → Guard Path (Anticipative)             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. ASIO-GUARD DUAL-PATH (CUBASE)

### 2.1 Koncept

```
┌─────────────────────────────────────────────────────────────┐
│ ASIO-GUARD — STEINBERG DUAL BUFFER SYSTEM                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Standardni DAW:                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  ASIO Buffer (npr. 128 samples)                         ││
│  │  ════════════════════════════════                       ││
│  │  │ Track 1 │ Track 2 │ Track 3 │ Master │               ││
│  │  │  (all)  │  (all)  │  (all)  │  (all) │               ││
│  │  ════════════════════════════════                       ││
│  │                                                          ││
│  │  Problem: SVI trackovi moraju završiti za 128 samples   ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ASIO-Guard sistem:                                          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  ASIO Buffer (128 samples) — REAL-TIME CRITICAL         ││
│  │  ════════════════════════════════                       ││
│  │  │ Record  │ VSTi    │         │                        ││
│  │  │ Tracks  │ Live    │         │                        ││
│  │  ════════════════════════════════                       ││
│  │                                                          ││
│  │  Guard Buffer (2048 samples) — PREFETCH                 ││
│  │  ════════════════════════════════════════════════════   ││
│  │  │ Playback │ Frozen  │ Master  │ Heavy   │            ││
│  │  │ Tracks   │ Tracks  │ Bus FX  │ Plugins │            ││
│  │  ════════════════════════════════════════════════════   ││
│  │                                                          ││
│  │  Dva buffer-a rade PARALELNO!                           ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Rezultat:                                                   │
│  • Live input: 128 samples latency (2.67ms @ 48kHz)        │
│  • Playback: 2048 samples available (42.67ms @ 48kHz)      │
│  • 2-3x više plugina bez povećanja monitoring latency      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 ASIO-Guard Levels

```
┌─────────────────────────────────────────────────────────────┐
│ ASIO-GUARD LEVELS — CUBASE IMPLEMENTATION                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Level: OFF                                                  │
│  ├── Guard buffer: Disabled                                 │
│  ├── Sve ide kroz ASIO buffer                              │
│  └── Use case: Maximum compatibility, troubleshooting       │
│                                                              │
│  Level: LOW                                                  │
│  ├── Guard buffer: ~4x ASIO buffer                         │
│  ├── Samo non-critical tracks                              │
│  ├── Example: ASIO=128 → Guard=512                         │
│  └── Use case: Some problematic plugins                    │
│                                                              │
│  Level: NORMAL (Default)                                     │
│  ├── Guard buffer: ~8-16x ASIO buffer                      │
│  ├── Agresivnije prebacivanje na Guard path                │
│  ├── Example: ASIO=128 → Guard=1024-2048                   │
│  └── Use case: Most sessions                               │
│                                                              │
│  Level: HIGH                                                 │
│  ├── Guard buffer: ~32x ASIO buffer                        │
│  ├── Maximum offloading to Guard path                      │
│  ├── Example: ASIO=128 → Guard=4096                        │
│  ├── Highest plugin count                                  │
│  └── Use case: Massive sessions, mixing stage              │
│                                                              │
│  Track Assignment (automatic):                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Track State              │ ASIO │ Guard │ Decision     │ │
│  ├──────────────────────────┼──────┼───────┼──────────────┤ │
│  │ Record-enabled           │  ✓   │       │ Always ASIO  │ │
│  │ Monitor-enabled          │  ✓   │       │ Always ASIO  │ │
│  │ VSTi with live MIDI      │  ✓   │       │ Always ASIO  │ │
│  │ Playback audio track     │      │   ✓   │ Guard        │ │
│  │ Frozen/Committed track   │      │   ✓   │ Guard        │ │
│  │ Group/Bus channel        │      │   ✓   │ Guard        │ │
│  │ Master bus               │      │   ✓   │ Guard        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 Implementacija za FluxForge

```rust
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE DUAL-PATH IMPLEMENTATION                          │
├─────────────────────────────────────────────────────────────┤

// rf-engine/src/dual_path.rs

/// Dual-path processing configuration
pub struct DualPathConfig {
    /// ASIO/CoreAudio buffer size (user setting)
    pub asio_buffer_size: usize,

    /// Guard buffer multiplier (1-32x)
    pub guard_multiplier: usize,

    /// Guard level (Off, Low, Normal, High)
    pub guard_level: GuardLevel,
}

#[derive(Clone, Copy)]
pub enum GuardLevel {
    Off,     // guard_multiplier = 1 (effectively disabled)
    Low,     // guard_multiplier = 4
    Normal,  // guard_multiplier = 16
    High,    // guard_multiplier = 32
}

impl GuardLevel {
    pub fn multiplier(&self) -> usize {
        match self {
            GuardLevel::Off => 1,
            GuardLevel::Low => 4,
            GuardLevel::Normal => 16,
            GuardLevel::High => 32,
        }
    }
}

/// Track path assignment
pub enum ProcessingPath {
    /// Real-time ASIO path (low latency, live input)
    RealTime,

    /// Guard path (higher latency, prefetch)
    Guard,
}

impl Track {
    /// Determine which path this track should use
    pub fn get_processing_path(&self) -> ProcessingPath {
        // Always real-time for live input
        if self.is_record_enabled() {
            return ProcessingPath::RealTime;
        }

        // Always real-time for input monitoring
        if self.is_monitor_enabled() {
            return ProcessingPath::RealTime;
        }

        // VSTi with active MIDI = real-time
        if self.has_instrument() && self.has_midi_input() {
            return ProcessingPath::RealTime;
        }

        // Sidechain receiver from real-time track
        if self.receives_sidechain_from_realtime() {
            return ProcessingPath::RealTime;
        }

        // Everything else → Guard path
        ProcessingPath::Guard
    }
}

/// Dual-path audio engine
pub struct DualPathEngine {
    /// Real-time processor (ASIO buffer)
    realtime: RealtimeProcessor,

    /// Guard processor (larger buffer, background thread)
    guard: GuardProcessor,

    /// Crossfade buffer for seamless transitions
    crossfade: CrossfadeBuffer,

    /// Configuration
    config: DualPathConfig,
}

impl DualPathEngine {
    pub fn process(&mut self, output: &mut [f32]) {
        // 1. Process real-time tracks (must complete in buffer time)
        let realtime_output = self.realtime.process();

        // 2. Get pre-processed guard output (already computed)
        let guard_output = self.guard.get_output();

        // 3. Mix together
        for i in 0..output.len() {
            output[i] = realtime_output[i] + guard_output[i];
        }
    }
}

└─────────────────────────────────────────────────────────────┘
```

### 2.4 Sinhronizacija Real-Time i Guard Path

```
┌─────────────────────────────────────────────────────────────┐
│ SINHRONIZACIJA — KRITIČAN ASPEKT                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Problem: Guard path procesira UNAPRED                      │
│           Real-time path procesira SADA                     │
│           Kako ih sinhronizovati?                           │
│                                                              │
│  Rešenje: Delay Compensation                                 │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Guard Path:                                             ││
│  │  ═══════════════════════════════►                       ││
│  │  │ Process │ Process │ Process │ (ahead of playhead)    ││
│  │  │ Buffer 1│ Buffer 2│ Buffer 3│                        ││
│  │                                                          ││
│  │  Real-Time Path:                                         ││
│  │  ──────────────────────────────►                        ││
│  │              │ Process │ (at playhead)                  ││
│  │              │ Current │                                 ││
│  │                                                          ││
│  │  Output: Guard delayed to match Real-Time               ││
│  │  ═══════════════════════════════►                       ││
│  │              │ Guard   │ (delayed)                      ││
│  │              │ Output  │                                 ││
│  │                        +                                 ││
│  │              │ RT      │ (current)                      ││
│  │              │ Output  │                                 ││
│  │              ═══════════                                ││
│  │              │ MIXED   │                                 ││
│  │              │ OUTPUT  │                                 ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Delay formula:                                              │
│  guard_delay = guard_buffer_size - asio_buffer_size         │
│                                                              │
│  Example:                                                    │
│  • Guard buffer: 2048 samples                               │
│  • ASIO buffer: 128 samples                                 │
│  • Guard delay: 2048 - 128 = 1920 samples                   │
│  • Guard output čeka 1920 samples pre mixovanja            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. CPU CORE ISOLATION (PYRAMIX MASSCORE)

### 3.1 Problem sa standardnim OS scheduling-om

```
┌─────────────────────────────────────────────────────────────┐
│ PROBLEM: OS SCHEDULER vs AUDIO                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Standardni OS (Windows/macOS/Linux):                        │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  OS Scheduler kontroliše SVE CPU core-ove:              ││
│  │                                                          ││
│  │  Core 0: Chrome │ DAW │ Slack │ System │ ...            ││
│  │  Core 1: DAW │ Antivirus │ Dropbox │ ...                ││
│  │  Core 2: System │ DAW │ VS Code │ ...                   ││
│  │  Core 3: DAW │ Spotlight │ Updates │ ...                ││
│  │                                                          ││
│  │  Problem:                                                ││
│  │  • Audio thread se TAKMIČI sa drugim procesima          ││
│  │  • OS može preempt-ovati audio u bilo kom trenutku      ││
│  │  • Antivirus scan = audio glitch                        ││
│  │  • System update check = potential dropout              ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Čak i sa HIGHEST priority:                                  │
│  • Windows: MMCSS "Pro Audio" može biti preempted          │
│  • macOS: Real-time thread ima ograničenja                 │
│  • Linux: SCHED_FIFO pomaže ali nije 100%                  │
│                                                              │
│  Rezultat: NEDETERMINISTIČNO ponašanje                      │
│  • Većinu vremena: OK                                       │
│  • Ponekad: Random glitch                                   │
│  • Worst case: Recording session ruined                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Pyramix MassCore rešenje

```
┌─────────────────────────────────────────────────────────────┐
│ MASSCORE — CPU CORE ISOLATION                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Koncept: "Sakrij" CPU core-ove od OS-a                     │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  8-core CPU sa MassCore:                                ││
│  │                                                          ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │ VIDLJIVO ZA OS (Windows/macOS)                      │││
│  │  │                                                      │││
│  │  │  Core 0: OS + GUI + Chrome + Everything else        │││
│  │  │  Core 1: OS + GUI + System services                 │││
│  │  │                                                      │││
│  │  │  (OS misli da ima samo 2 core-a!)                   │││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │ IZOLOVANO — SAMO AUDIO (OS ne vidi!)               │││
│  │  │                                                      │││
│  │  │  Core 2: Audio Engine — Track 1-32                  │││
│  │  │  Core 3: Audio Engine — Track 33-64                 │││
│  │  │  Core 4: Audio Engine — Track 65-96                 │││
│  │  │  Core 5: Audio Engine — FX Processing               │││
│  │  │  Core 6: Audio Engine — Mixing                      │││
│  │  │  Core 7: Audio Engine — Master + I/O                │││
│  │  │                                                      │││
│  │  │  NEMA PREKIDA od OS-a!                              │││
│  │  │  100% deterministično!                              │││
│  │  │  Zero glitches!                                     │││
│  │  └─────────────────────────────────────────────────────┘││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Kako funkcioniše (tehnički):                                │
│  • RTX64 real-time kernel extension (Windows)              │
│  • Boot-time CPU core reservation                          │
│  • Direct hardware access (bypass OS HAL)                  │
│  • Custom interrupt handling                               │
│  • Inter-core communication via shared memory              │
│                                                              │
│  Rezultat:                                                   │
│  • Pyramix može: 384 kanala @ 48kHz                        │
│  • ~1ms round-trip latency                                 │
│  • ZERO dropouts čak i sa 100% CPU load                    │
│  • Industry standard za broadcast i mastering              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 FluxForge implementacija (bez RTX64)

```
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE — PRAKTIČNA CPU ISOLATION                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Ne možemo koristiti RTX64 (proprietary, expensive)         │
│  Ali MOŽEMO postići ~90% benefita sa OS API-jima:           │
│                                                              │
│  WINDOWS — MMCSS + Thread Affinity:                          │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ // rf-engine/src/platform/windows.rs                    ││
│  │                                                          ││
│  │ use windows::Win32::System::Threading::*;               ││
│  │                                                          ││
│  │ pub fn setup_audio_thread() {                           ││
│  │     // 1. Register with MMCSS "Pro Audio"               ││
│  │     let task = AvSetMmThreadCharacteristicsW(           ││
│  │         "Pro Audio",                                     ││
│  │         &mut task_index                                  ││
│  │     );                                                    ││
│  │                                                          ││
│  │     // 2. Set highest priority                          ││
│  │     AvSetMmThreadPriority(task, AVRT_PRIORITY_CRITICAL);││
│  │                                                          ││
│  │     // 3. Set CPU affinity (pin to specific cores)      ││
│  │     let mask = 0b11110000; // Cores 4-7 for audio       ││
│  │     SetThreadAffinityMask(GetCurrentThread(), mask);    ││
│  │                                                          ││
│  │     // 4. Disable priority boost                        ││
│  │     SetThreadPriorityBoost(GetCurrentThread(), true);   ││
│  │ }                                                        ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  macOS — Audio Workgroup API (macOS 11+):                    │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ // rf-engine/src/platform/macos.rs                      ││
│  │                                                          ││
│  │ use core_audio::*;                                       ││
│  │                                                          ││
│  │ pub fn setup_audio_thread(device: AudioDevice) {        ││
│  │     // 1. Get workgroup from audio device               ││
│  │     let workgroup = device.get_workgroup();             ││
│  │                                                          ││
│  │     // 2. Join workgroup (tells OS this is audio)       ││
│  │     workgroup.join();                                    ││
│  │                                                          ││
│  │     // 3. Set real-time policy                          ││
│  │     let policy = thread_time_constraint_policy_data_t { ││
│  │         period: buffer_frames,                          ││
│  │         computation: buffer_frames / 2,                 ││
│  │         constraint: buffer_frames,                      ││
│  │         preemptible: false,                             ││
│  │     };                                                   ││
│  │     thread_policy_set(thread, THREAD_TIME_CONSTRAINT,   ││
│  │                       &policy);                         ││
│  │ }                                                        ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Linux — SCHED_FIFO + CPU Affinity + cgroups:               │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ // rf-engine/src/platform/linux.rs                      ││
│  │                                                          ││
│  │ use libc::*;                                             ││
│  │                                                          ││
│  │ pub fn setup_audio_thread() {                           ││
│  │     // 1. Set SCHED_FIFO with max priority              ││
│  │     let param = sched_param {                           ││
│  │         sched_priority: 99, // Highest RT priority      ││
│  │     };                                                   ││
│  │     sched_setscheduler(0, SCHED_FIFO, &param);          ││
│  │                                                          ││
│  │     // 2. Set CPU affinity                              ││
│  │     let mut cpuset: cpu_set_t = zeroed();               ││
│  │     CPU_SET(4, &mut cpuset); // Core 4                  ││
│  │     CPU_SET(5, &mut cpuset); // Core 5                  ││
│  │     CPU_SET(6, &mut cpuset); // Core 6                  ││
│  │     CPU_SET(7, &mut cpuset); // Core 7                  ││
│  │     sched_setaffinity(0, size_of_val(&cpuset), &cpuset);││
│  │                                                          ││
│  │     // 3. Lock memory (prevent page faults)             ││
│  │     mlockall(MCL_CURRENT | MCL_FUTURE);                 ││
│  │ }                                                        ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  User-Space dodatne optimizacije:                            │
│  • Disable CPU frequency scaling (performance governor)    │
│  • Disable hyperthreading za audio cores (BIOS)            │
│  • Use isolcpus kernel parameter (Linux)                   │
│  • Disable C-states za audio cores                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.4 FluxForge Audio Thread Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE MULTI-THREAD AUDIO ARCHITECTURE                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Thread Layout (8-core example):                             │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Core 0: Flutter UI Thread                               ││
│  │         └── All UI rendering, user input                ││
│  │                                                          ││
│  │ Core 1: Flutter Platform Thread                         ││
│  │         └── File I/O, network, plugins                  ││
│  │                                                          ││
│  │ Core 2: Guard Path Worker #1                            ││
│  │         └── Anticipative processing (tracks 1-16)       ││
│  │                                                          ││
│  │ Core 3: Guard Path Worker #2                            ││
│  │         └── Anticipative processing (tracks 17-32)      ││
│  │                                                          ││
│  │ Core 4: DSP Worker #1 (pinned, SCHED_FIFO)              ││
│  │         └── Real-time FX processing                     ││
│  │                                                          ││
│  │ Core 5: DSP Worker #2 (pinned, SCHED_FIFO)              ││
│  │         └── Real-time FX processing                     ││
│  │                                                          ││
│  │ Core 6: Audio Mixer Thread (pinned, SCHED_FIFO)         ││
│  │         └── Final mixing, metering                      ││
│  │                                                          ││
│  │ Core 7: Audio I/O Thread (pinned, SCHED_FIFO)           ││
│  │         └── ASIO/CoreAudio callback                     ││
│  │         └── MUST NEVER BLOCK                            ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Inter-thread communication (LOCK-FREE):                     │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  UI ──[rtrb]──► DSP Workers ──[rtrb]──► Mixer ──► I/O  ││
│  │       params        processed audio     mixed            ││
│  │                                                          ││
│  │  rtrb = lock-free SPSC ring buffer                      ││
│  │  Zero allocations in audio path                         ││
│  │  Zero mutex/locks in audio path                         ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. PER-FX OVERSAMPLING (REAPER 7)

### 4.1 Zašto je oversampling kritičan

```
┌─────────────────────────────────────────────────────────────┐
│ ALIASING PROBLEM — ZAŠTO NAM TREBA OVERSAMPLING            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Nyquist teorema:                                            │
│  • Sample rate 48kHz → max frequency 24kHz                  │
│  • Sve iznad 24kHz = ALIASING (distorzija)                 │
│                                                              │
│  Problem sa nelinearnim processing-om (saturation/dist):    │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Input: 10kHz sine wave @ 48kHz sample rate             ││
│  │                                                          ││
│  │  Saturation generira HARMONIKE:                          ││
│  │  • Fundamental: 10kHz    ✓ (below Nyquist)              ││
│  │  • 2nd harmonic: 20kHz   ✓ (below Nyquist)              ││
│  │  • 3rd harmonic: 30kHz   ✗ ALIASING! (above 24kHz)      ││
│  │  • 4th harmonic: 40kHz   ✗ ALIASING!                    ││
│  │  • 5th harmonic: 50kHz   ✗ ALIASING!                    ││
│  │                                                          ││
│  │  Šta se dešava sa 30kHz @ 48kHz sample rate?            ││
│  │  30kHz - 48kHz = -18kHz → reflects to 18kHz             ││
│  │                                                          ││
│  │  Rezultat: Inharmonic, harsh, "digital" zvuk            ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Visualizacija:                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Frequency spectrum @ 48kHz:                              ││
│  │                                                          ││
│  │ Without oversampling:                                    ││
│  │ │  10k     20k     │18k│    │                           ││
│  │ │   ▲       ▲      │ ▲ │    │ Nyquist                   ││
│  │ │   │       │      │ │ │    │ (24kHz)                   ││
│  │ └───┴───────┴──────┴─┴─┴────┴─────────                  ││
│  │   fund    2nd    ALIAS!                                  ││
│  │                 (30kHz reflected)                        ││
│  │                                                          ││
│  │ With 4x oversampling (192kHz):                          ││
│  │ │  10k   20k   30k   40k   50k        │                 ││
│  │ │   ▲     ▲     ▲     ▲     ▲         │ Nyquist        ││
│  │ │   │     │     │     │     │         │ (96kHz)        ││
│  │ └───┴─────┴─────┴─────┴─────┴─────────┴─────────        ││
│  │   fund   2nd   3rd   4th   5th                          ││
│  │   All harmonics below Nyquist = NO aliasing!            ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 REAPER 7 Per-FX Oversampling

```
┌─────────────────────────────────────────────────────────────┐
│ REAPER 7 — PER-FX OVERSAMPLING DO 768kHz                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Tradicionalni pristup: Project-level oversampling          │
│  • Ceo projekat na 96kHz ili 192kHz                        │
│  • Problem: OGROMNO povećanje CPU za SVE                   │
│  • EQ ne treba oversampling, ali ga dobija                 │
│                                                              │
│  REAPER 7 inovacija: PER-FX oversampling                    │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  Project: 48kHz                                          ││
│  │                                                          ││
│  │  Track FX Chain:                                         ││
│  │  ┌────────────────────────────────────────────────────┐ ││
│  │  │ EQ         @ 48kHz   (1x) — linearno, ne treba    │ ││
│  │  │ Compressor @ 48kHz   (1x) — linearno, ne treba    │ ││
│  │  │ Saturator  @ 384kHz  (8x) — NELINEARNO, treba!    │ ││
│  │  │ Limiter    @ 192kHz  (4x) — clipping, treba       │ ││
│  │  └────────────────────────────────────────────────────┘ ││
│  │                                                          ││
│  │  Signal flow:                                            ││
│  │  Input (48k) → EQ (48k) → Comp (48k)                    ││
│  │      → Upsample 8x → Saturator (384k) → Downsample 8x   ││
│  │      → Upsample 4x → Limiter (192k) → Downsample 4x     ││
│  │      → Output (48k)                                      ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Oversampling opcije u REAPER 7:                             │
│  • 1x (None) — 48kHz                                        │
│  • 2x — 96kHz                                               │
│  • 4x — 192kHz                                              │
│  • 8x — 384kHz                                              │
│  • 16x — 768kHz (za extreme precision)                     │
│                                                              │
│  Tipične preporuke:                                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Plugin Type           │ Recommended OS │ Why            │ │
│  ├───────────────────────┼────────────────┼────────────────┤ │
│  │ Linear EQ             │ 1x             │ No harmonics   │ │
│  │ Compressor (no clip)  │ 1x             │ No harmonics   │ │
│  │ Soft saturation       │ 2x-4x          │ Few harmonics  │ │
│  │ Hard saturation       │ 4x-8x          │ Many harmonics │ │
│  │ Distortion            │ 8x-16x         │ Extreme harm.  │ │
│  │ Limiter (soft knee)   │ 2x             │ Mild clipping  │ │
│  │ Brickwall limiter     │ 4x-8x          │ Hard clipping  │ │
│  │ Bitcrusher            │ 8x+            │ Extreme nonlin │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.3 Implementacija Polyphase Resampling

```rust
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE — POLYPHASE OVERSAMPLING IMPLEMENTATION           │
├─────────────────────────────────────────────────────────────┤

// rf-dsp/src/oversampling.rs

/// Oversampling factor
#[derive(Clone, Copy, PartialEq)]
pub enum OversampleFactor {
    X1 = 1,
    X2 = 2,
    X4 = 4,
    X8 = 8,
    X16 = 16,
}

/// Polyphase upsampler with anti-imaging filter
pub struct Upsampler {
    factor: OversampleFactor,
    /// Polyphase filter coefficients
    filter_bank: Vec<Vec<f64>>,
    /// State for each polyphase branch
    state: Vec<Vec<f64>>,
}

impl Upsampler {
    pub fn new(factor: OversampleFactor) -> Self {
        // Design low-pass filter
        // Cutoff = original_nyquist / factor
        // Example: 48kHz → 384kHz (8x)
        //          Cutoff = 24kHz, Stopband = 48kHz

        let filter_len = 128 * factor as usize;
        let cutoff = 0.5 / factor as f64;  // Normalized

        let prototype = design_lowpass(filter_len, cutoff);
        let filter_bank = polyphase_decompose(&prototype, factor);

        Self {
            factor,
            filter_bank,
            state: vec![vec![0.0; filter_len / factor as usize]; factor as usize],
        }
    }

    /// Upsample input buffer
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        let factor = self.factor as usize;

        for (i, &sample) in input.iter().enumerate() {
            // For each output sample position
            for phase in 0..factor {
                let out_idx = i * factor + phase;

                // Apply polyphase filter for this phase
                output[out_idx] = self.filter_phase(sample, phase);
            }
        }
    }

    #[inline]
    fn filter_phase(&mut self, input: f64, phase: usize) -> f64 {
        // Shift state
        self.state[phase].rotate_right(1);
        self.state[phase][0] = input;

        // Convolve with polyphase coefficients
        let mut sum = 0.0;
        for (i, &coef) in self.filter_bank[phase].iter().enumerate() {
            sum += coef * self.state[phase][i];
        }

        sum * self.factor as f64  // Gain compensation
    }
}

/// Polyphase downsampler with anti-aliasing filter
pub struct Downsampler {
    factor: OversampleFactor,
    filter_bank: Vec<Vec<f64>>,
    state: Vec<Vec<f64>>,
    phase_counter: usize,
}

impl Downsampler {
    pub fn new(factor: OversampleFactor) -> Self {
        // Same filter design as upsampler
        let filter_len = 128 * factor as usize;
        let cutoff = 0.5 / factor as f64;

        let prototype = design_lowpass(filter_len, cutoff);
        let filter_bank = polyphase_decompose(&prototype, factor);

        Self {
            factor,
            filter_bank,
            state: vec![vec![0.0; filter_len / factor as usize]; factor as usize],
            phase_counter: 0,
        }
    }

    /// Downsample input buffer
    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        let factor = self.factor as usize;
        let mut out_idx = 0;

        for &sample in input.iter() {
            // Accumulate into current phase
            let phase = self.phase_counter % factor;
            self.accumulate_phase(sample, phase);

            self.phase_counter += 1;

            // Output when we've collected all phases
            if self.phase_counter % factor == 0 {
                output[out_idx] = self.compute_output();
                out_idx += 1;
            }
        }
    }
}

/// Oversampled processor wrapper
pub struct OversampledProcessor<P: Processor> {
    processor: P,
    factor: OversampleFactor,
    upsampler: Upsampler,
    downsampler: Downsampler,
    /// Upsampled buffer (reused)
    up_buffer: Vec<f64>,
}

impl<P: Processor> OversampledProcessor<P> {
    pub fn new(processor: P, factor: OversampleFactor) -> Self {
        Self {
            processor,
            factor,
            upsampler: Upsampler::new(factor),
            downsampler: Downsampler::new(factor),
            up_buffer: Vec::new(),
        }
    }

    pub fn process(&mut self, input: &[f64], output: &mut [f64]) {
        let factor = self.factor as usize;

        // Resize up_buffer if needed
        let up_len = input.len() * factor;
        if self.up_buffer.len() != up_len {
            self.up_buffer.resize(up_len, 0.0);
        }

        // 1. Upsample
        self.upsampler.process(input, &mut self.up_buffer);

        // 2. Process at higher rate
        self.processor.process_inplace(&mut self.up_buffer);

        // 3. Downsample
        self.downsampler.process(&self.up_buffer, output);
    }
}

// Usage example
fn create_oversampled_saturator() -> OversampledProcessor<Saturator> {
    let saturator = Saturator::new(SaturatorType::Tape);
    OversampledProcessor::new(saturator, OversampleFactor::X8)
}

└─────────────────────────────────────────────────────────────┘
```

### 4.4 FluxForge Per-Processor Oversampling UI

```
┌─────────────────────────────────────────────────────────────┐
│ FLUXFORGE UI — PER-PROCESSOR OVERSAMPLING CONTROL           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Insert Slot UI Mockup:                                      │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ ┌─────────────────────────────────────────────────────┐ ││
│  │ │ [1] FluxForge Saturator           [bypass] [x]     │ ││
│  │ │                                                      │ ││
│  │ │  Drive: ═══════●═══════  12dB                       │ ││
│  │ │  Type:  [Tape ▼]                                    │ ││
│  │ │  Mix:   ═══════════●═══  75%                        │ ││
│  │ │                                                      │ ││
│  │ │  ┌─────────────────────────────────────────────┐   │ ││
│  │ │  │ Oversampling: [1x] [2x] [4x] [●8x] [16x]   │   │ ││
│  │ │  │                                              │   │ ││
│  │ │  │ CPU: +12%  Latency: +2.7ms                  │   │ ││
│  │ │  └─────────────────────────────────────────────┘   │ ││
│  │ │                                                      │ ││
│  │ └─────────────────────────────────────────────────────┘ ││
│  │                                                          ││
│  │ ┌─────────────────────────────────────────────────────┐ ││
│  │ │ [2] FluxForge EQ                  [bypass] [x]     │ ││
│  │ │                                                      │ ││
│  │ │  [Spectrum display]                                 │ ││
│  │ │                                                      │ ││
│  │ │  ┌─────────────────────────────────────────────┐   │ ││
│  │ │  │ Oversampling: [●1x] [2x] [4x] [8x] [16x]   │   │ ││
│  │ │  │                                              │   │ ││
│  │ │  │ CPU: +0%   Latency: +0ms   (not needed)    │   │ ││
│  │ │  └─────────────────────────────────────────────┘   │ ││
│  │ │                                                      │ ││
│  │ └─────────────────────────────────────────────────────┘ ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  Auto-Suggest Feature:                                       │
│  • Saturator/Distortion → Suggest 4x-8x                     │
│  • Limiter → Suggest 2x-4x                                  │
│  • EQ/Compressor → Suggest 1x (grayed out)                  │
│  • Show CPU/latency cost in real-time                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. KOMBINOVANI ARCHITECTURE DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    FLUXFORGE ULTIMATE ENGINE ARCHITECTURE                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                           FLUTTER UI                                    │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐                 │ │
│  │  │   Mixer      │  │   Timeline   │  │   DSP UIs    │                 │ │
│  │  │   Widget     │  │   Widget     │  │   (EQ, etc)  │                 │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘                 │ │
│  │         └─────────────────┴─────────────────┘                          │ │
│  │                           │                                             │ │
│  │                    [rtrb: params]                                       │ │
│  │                           ▼                                             │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                        FFI BRIDGE (rf-bridge)                           │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                     RUST AUDIO ENGINE (rf-engine)                       │ │
│  │                                                                          │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐   │ │
│  │  │                    TRACK ROUTING DECISION                        │   │ │
│  │  │                                                                   │   │ │
│  │  │   is_record_enabled() ──────────────────┐                        │   │ │
│  │  │   is_monitor_enabled() ─────────────────┼──► REAL-TIME PATH     │   │ │
│  │  │   has_live_midi() ──────────────────────┘                        │   │ │
│  │  │                                                                   │   │ │
│  │  │   is_playback_only() ───────────────────────► GUARD PATH        │   │ │
│  │  │   is_frozen() ──────────────────────────────► (Anticipative)    │   │ │
│  │  │                                                                   │   │ │
│  │  └─────────────────────────────────────────────────────────────────┘   │ │
│  │                           │                                             │ │
│  │           ┌───────────────┴───────────────┐                            │ │
│  │           ▼                               ▼                            │ │
│  │  ┌─────────────────────┐       ┌─────────────────────┐                │ │
│  │  │   REAL-TIME PATH    │       │    GUARD PATH       │                │ │
│  │  │   (ASIO Buffer)     │       │  (Anticipative FX)  │                │ │
│  │  │                     │       │                     │                │ │
│  │  │ • Buffer: 128-512   │       │ • Buffer: 2048-8192 │                │ │
│  │  │ • Latency: 2-10ms   │       │ • Latency: N/A      │                │ │
│  │  │ • Live input        │       │ • Pre-computed      │                │ │
│  │  │ • VSTi              │       │ • Heavy plugins     │                │ │
│  │  │                     │       │ • Linear phase      │                │ │
│  │  │ ┌─────────────────┐ │       │ ┌─────────────────┐ │                │ │
│  │  │ │ Per-FX          │ │       │ │ Per-FX          │ │                │ │
│  │  │ │ Oversampling    │ │       │ │ Oversampling    │ │                │ │
│  │  │ │ (2x-16x)        │ │       │ │ (2x-16x)        │ │                │ │
│  │  │ └─────────────────┘ │       │ └─────────────────┘ │                │ │
│  │  └──────────┬──────────┘       └──────────┬──────────┘                │ │
│  │             │                              │                           │ │
│  │             │   ┌──────────────────────┐   │                           │ │
│  │             └──►│   DELAY COMPENSATED  │◄──┘                           │ │
│  │                 │       MIXER          │                               │ │
│  │                 │                      │                               │ │
│  │                 │  ┌────────────────┐  │                               │ │
│  │                 │  │ 64-bit double  │  │                               │ │
│  │                 │  │ summing bus    │  │                               │ │
│  │                 │  └────────────────┘  │                               │ │
│  │                 └──────────┬───────────┘                               │ │
│  │                            │                                           │ │
│  │                            ▼                                           │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                     CPU CORE ISOLATION                           │  │ │
│  │  │                                                                   │  │ │
│  │  │  Core 0-1: Flutter + OS + Other apps                             │  │ │
│  │  │  Core 2-3: Guard Path Workers (SCHED_FIFO, pinned)               │  │ │
│  │  │  Core 4-5: DSP Workers (SCHED_FIFO, pinned)                      │  │ │
│  │  │  Core 6:   Mixer Thread (SCHED_FIFO, pinned)                     │  │ │
│  │  │  Core 7:   Audio I/O Thread (SCHED_FIFO, pinned, HIGHEST)        │  │ │
│  │  │                                                                   │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │                            │                                           │ │
│  │                            ▼                                           │ │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │ │
│  │  │                    AUDIO I/O (rf-audio)                          │  │ │
│  │  │                                                                   │  │ │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │  │ │
│  │  │  │    ASIO     │  │  CoreAudio  │  │ JACK/Pulse  │               │  │ │
│  │  │  │  (Windows)  │  │   (macOS)   │  │  (Linux)    │               │  │ │
│  │  │  └─────────────┘  └─────────────┘  └─────────────┘               │  │ │
│  │  │                                                                   │  │ │
│  │  └─────────────────────────────────────────────────────────────────┘  │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. IMPLEMENTATION CHECKLIST

```
┌─────────────────────────────────────────────────────────────┐
│ IMPLEMENTATION CHECKLIST                                     │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ ANTICIPATIVE FX (Guard Path):                                │
│ [ ] Design ring buffer for pre-computed audio               │
│ [ ] Implement background worker thread                      │
│ [ ] Add track routing decision logic                        │
│ [ ] Handle seek/jump (re-fill buffer)                       │
│ [ ] Handle parameter changes (re-process)                   │
│ [ ] Test with high-latency plugins                          │
│                                                              │
│ ASIO-GUARD (Dual Path):                                      │
│ [ ] Implement Guard buffer (separate from ASIO)             │
│ [ ] Add Guard Level enum (Off/Low/Normal/High)              │
│ [ ] Implement delay compensation between paths              │
│ [ ] Add seamless crossfade                                  │
│ [ ] UI: Guard Level selector in preferences                 │
│ [ ] Test: CPU usage comparison                              │
│                                                              │
│ CPU CORE ISOLATION:                                          │
│ [ ] Windows: MMCSS + SetThreadAffinityMask                  │
│ [ ] macOS: Audio Workgroup API                              │
│ [ ] Linux: SCHED_FIFO + sched_setaffinity                   │
│ [ ] Memory locking (mlockall)                               │
│ [ ] Test: Glitch-free under load                            │
│                                                              │
│ PER-FX OVERSAMPLING:                                         │
│ [ ] Implement polyphase upsampler                           │
│ [ ] Implement polyphase downsampler                         │
│ [ ] OversampledProcessor<P> wrapper                         │
│ [ ] UI: Per-processor oversampling selector                 │
│ [ ] Auto-suggest based on processor type                    │
│ [ ] Show CPU/latency cost                                   │
│ [ ] Test: Aliasing measurement                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

**Document Version:** 1.0
**Date:** January 2026
**Source Analysis:**
- REAPER 7: Anticipative FX, Per-FX Oversampling
- Cubase Pro 14: ASIO-Guard dual-path
- Pyramix 15: MassCore CPU isolation
