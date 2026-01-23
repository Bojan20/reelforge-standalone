# FluxForge Studio — Architecture Diagrams

**Version:** 0.1.0
**Date:** 2026-01-22
**Updated for:** P0-P3 Implementation Complete

---

## 1. High-Level System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FLUXFORGE STUDIO                                   │
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │      DAW        │  │    SLOT LAB     │  │   MIDDLEWARE    │              │
│  │   (Timeline)    │  │  (Simulation)   │  │   (Events)      │              │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘              │
│           │                    │                    │                        │
│           └────────────────────┼────────────────────┘                        │
│                                │                                             │
│                    ┌───────────▼───────────┐                                 │
│                    │ UnifiedPlaybackController│                              │
│                    │  (Section Isolation)   │                                │
│                    └───────────┬───────────┘                                 │
│                                │                                             │
│  ┌─────────────────────────────┼─────────────────────────────┐              │
│  │                    DART FFI BRIDGE                         │              │
│  │                   (native_ffi.dart)                        │              │
│  └─────────────────────────────┼─────────────────────────────┘              │
│                                │                                             │
└────────────────────────────────┼────────────────────────────────────────────┘
                                 │
┌────────────────────────────────┼────────────────────────────────────────────┐
│                                │                                             │
│                    ┌───────────▼───────────┐                                 │
│                    │     RF-BRIDGE         │                                 │
│                    │   (C FFI Layer)       │                                 │
│                    └───────────┬───────────┘                                 │
│                                │                                             │
│    ┌───────────────────────────┼───────────────────────────┐                │
│    │                           │                           │                │
│    ▼                           ▼                           ▼                │
│ ┌──────────┐            ┌──────────┐              ┌──────────┐             │
│ │RF-ENGINE │            │  RF-DSP  │              │RF-SLOT-LAB│             │
│ │(Playback)│            │  (SIMD)  │              │(Simulate) │             │
│ └──────────┘            └──────────┘              └──────────┘             │
│                                                                             │
│                         RUST CRATES                                         │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Audio Signal Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AUDIO SIGNAL FLOW                                    │
│                                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │  Track 1 │    │  Track 2 │    │  Track 3 │    │  Track N │              │
│  │ (Clips)  │    │ (Clips)  │    │ (Clips)  │    │ (Clips)  │              │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘    └────┬─────┘              │
│       │               │               │               │                     │
│       │               │               │               │                     │
│       ▼               ▼               ▼               ▼                     │
│  ┌─────────────────────────────────────────────────────────┐               │
│  │              TRACK ROUTING MATRIX                        │               │
│  │    (Each track routes to one or more buses)             │               │
│  └───────────────────────┬─────────────────────────────────┘               │
│                          │                                                  │
│       ┌──────────────────┼──────────────────────┐                          │
│       │                  │                      │                          │
│       ▼                  ▼                      ▼                          │
│  ┌─────────┐       ┌─────────┐            ┌─────────┐                      │
│  │   SFX   │       │  MUSIC  │            │  VOICE  │                      │
│  │ (Bus 0) │       │ (Bus 1) │            │ (Bus 2) │                      │
│  └────┬────┘       └────┬────┘            └────┬────┘                      │
│       │                 │                      │                           │
│       │                 │                      │                           │
│       ▼                 ▼                      ▼                           │
│  ┌─────────┐       ┌─────────┐            ┌─────────┐                      │
│  │AMBIENCE │       │   AUX   │            │         │                      │
│  │ (Bus 3) │       │ (Bus 4) │            │    ↓    │                      │
│  └────┬────┘       └────┬────┘            │         │                      │
│       │                 │                 │         │                      │
│       └─────────────────┼─────────────────┘         │                      │
│                         │                           │                      │
│                         ▼                           │                      │
│              ┌──────────────────────┐               │                      │
│              │    BUS SUMMATION     │◄──────────────┘                      │
│              │  (SIMD mix_add)      │                                      │
│              └──────────┬───────────┘                                      │
│                         │                                                  │
│                         ▼                                                  │
│              ┌──────────────────────┐                                      │
│              │   MASTER INSERT      │                                      │
│              │   (DSP Chain)        │                                      │
│              └──────────┬───────────┘                                      │
│                         │                                                  │
│                         ▼                                                  │
│              ┌──────────────────────┐                                      │
│              │    MASTER BUS        │                                      │
│              │  (Volume, Limiter)   │                                      │
│              └──────────┬───────────┘                                      │
│                         │                                                  │
│                         ▼                                                  │
│              ┌──────────────────────┐                                      │
│              │      METERING        │                                      │
│              │ (Peak, RMS, LUFS,    │                                      │
│              │  True Peak, Corr)    │                                      │
│              └──────────┬───────────┘                                      │
│                         │                                                  │
│                         ▼                                                  │
│              ┌──────────────────────┐                                      │
│              │    AUDIO OUTPUT      │                                      │
│              │   (CoreAudio/ASIO)   │                                      │
│              └──────────────────────┘                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Event System Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         EVENT SYSTEM FLOW                                    │
│                                                                              │
│   SlotLabProvider                MiddlewareProvider                          │
│        │                               │                                     │
│        │ triggerStage()               │ postEvent()                         │
│        ▼                               ▼                                     │
│   ┌────────────────────────────────────────────────────┐                    │
│   │                 EVENT REGISTRY                      │                    │
│   │                                                     │                    │
│   │  ┌─────────────┐    ┌─────────────┐               │                    │
│   │  │ Stage Map   │    │ Event Map   │               │                    │
│   │  │ SPIN_START  │───▶│ AudioEvent  │               │                    │
│   │  │ REEL_STOP_0 │    │ id, layers  │               │                    │
│   │  │ WIN_PRESENT │    │ priority    │               │                    │
│   │  └─────────────┘    └─────────────┘               │                    │
│   │                                                     │                    │
│   │        │ lookupEvent()                             │                    │
│   │        ▼                                           │                    │
│   │  ┌─────────────────────────────────────┐          │                    │
│   │  │        CONTAINER CHECK              │          │                    │
│   │  │  containerType == blend/random/seq? │          │                    │
│   │  └──────────────┬──────────────────────┘          │                    │
│   │                 │                                  │                    │
│   └─────────────────┼──────────────────────────────────┘                    │
│                     │                                                        │
│           ┌─────────┴─────────┐                                             │
│           │                   │                                             │
│           ▼                   ▼                                             │
│   ┌───────────────┐   ┌───────────────┐                                    │
│   │ Direct Play   │   │ ContainerService│                                   │
│   │ (no container)│   │ (evaluate/select)│                                  │
│   └───────┬───────┘   └───────┬───────┘                                    │
│           │                   │                                             │
│           └─────────┬─────────┘                                             │
│                     │                                                        │
│                     ▼                                                        │
│   ┌─────────────────────────────────────────┐                               │
│   │         AUDIO PLAYBACK SERVICE          │                               │
│   │                                         │                               │
│   │   ┌───────────────┐  ┌──────────────┐  │                               │
│   │   │ RTPC Modulate │  │ Ducking Check│  │                               │
│   │   └───────┬───────┘  └──────┬───────┘  │                               │
│   │           │                 │          │                               │
│   │           ▼                 ▼          │                               │
│   │   ┌─────────────────────────────────┐  │                               │
│   │   │  playFileToBus(path, bus, vol)  │  │                               │
│   │   └─────────────────────────────────┘  │                               │
│   │                                         │                               │
│   └─────────────────────────────────────────┘                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Provider Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      PROVIDER ARCHITECTURE                                   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                      SERVICE LOCATOR (GetIt)                          │   │
│  │                                                                        │   │
│  │  Layer 1: Core FFI                                                    │   │
│  │    └── NativeFFI                                                      │   │
│  │                                                                        │   │
│  │  Layer 2: Low-level Services                                          │   │
│  │    ├── SharedMeterReader                                              │   │
│  │    ├── WaveformCacheService                                           │   │
│  │    ├── AudioAssetManager                                              │   │
│  │    └── LiveEngineService                                              │   │
│  │                                                                        │   │
│  │  Layer 3: Playback Services                                           │   │
│  │    ├── UnifiedPlaybackController                                      │   │
│  │    ├── AudioPlaybackService                                           │   │
│  │    ├── AudioPool                                                      │   │
│  │    ├── SlotLabTrackBridge                                             │   │
│  │    └── SessionPersistenceService                                      │   │
│  │                                                                        │   │
│  │  Layer 4: Processing Services                                         │   │
│  │    ├── DuckingService                                                 │   │
│  │    ├── RtpcModulationService                                          │   │
│  │    └── ContainerService                                               │   │
│  │                                                                        │   │
│  │  Layer 5: Subsystem Providers                                         │   │
│  │    ├── StateGroupsProvider                                            │   │
│  │    ├── SwitchGroupsProvider                                           │   │
│  │    ├── RtpcSystemProvider                                             │   │
│  │    └── DuckingSystemProvider                                          │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     CHANGE NOTIFIER PROVIDERS                         │   │
│  │                                                                        │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │  │               MiddlewareProvider (4714 LOC)                      │ │   │
│  │  │                                                                   │ │   │
│  │  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐│ │   │
│  │  │  │StateGroups- │ │SwitchGroups-│ │RtpcSystem-  │ │DuckingSystem││ │   │
│  │  │  │Provider     │ │Provider     │ │Provider     │ │Provider     ││ │   │
│  │  │  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘ └──────┬──────┘│ │   │
│  │  │         │               │               │               │       │ │   │
│  │  │         └───────────────┴───────────────┴───────────────┘       │ │   │
│  │  │                              │                                   │ │   │
│  │  │                    Forward notifications                        │ │   │
│  │  │                                                                   │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  │                                                                        │   │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐          │   │
│  │  │ SlotLabProvider│  │ MixerProvider  │  │TimelinePlayback│          │   │
│  │  │                │  │                │  │    Provider    │          │   │
│  │  └────────────────┘  └────────────────┘  └────────────────┘          │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Waveform Cache System (P3.4 Memory-Mapped)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    WAVEFORM CACHE SYSTEM (P3.4)                              │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     WaveCacheManager                                   │   │
│  │                                                                        │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │  │              loaded_caches: HashMap<String, CachedWaveform>      │ │   │
│  │  │                                                                   │ │   │
│  │  │   CachedWaveform::Loaded(Arc<WfcFile>)   ◄── Small files (<10MB) │ │   │
│  │  │   CachedWaveform::Mmap(Arc<WfcFileMmap>) ◄── Large files (>10MB) │ │   │
│  │  │                                                                   │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  │                                                                        │   │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │  │                    Memory Management                             │ │   │
│  │  │                                                                   │ │   │
│  │  │  memory_budget: AtomicUsize (512 MB default)                     │ │   │
│  │  │  memory_usage: AtomicUsize (tracked per cache)                   │ │   │
│  │  │  mmap_threshold: AtomicUsize (10 MB default)                     │ │   │
│  │  │                                                                   │ │   │
│  │  │  LRU Eviction: lru_order HashMap<String, u64>                    │ │   │
│  │  │  Evicts to 80% of budget when exceeded                           │ │   │
│  │  │                                                                   │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        .wfc File Format                               │   │
│  │                                                                        │   │
│  │  ┌────────────────────────────────────────────────────────────────┐  │   │
│  │  │ Header (64 bytes)                                               │  │   │
│  │  │   magic: "WFC1", version, channels, sample_rate, total_frames  │  │   │
│  │  │   mip_offsets[8]                                                │  │   │
│  │  └────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                        │   │
│  │  ┌────────────────────────────────────────────────────────────────┐  │   │
│  │  │ Mip Level 0 (256 samples/tile)   ◄── Finest resolution         │  │   │
│  │  │   Tiles: [min: f32, max: f32] × num_tiles × channels           │  │   │
│  │  └────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                        │   │
│  │  ┌────────────────────────────────────────────────────────────────┐  │   │
│  │  │ Mip Level 1-7 (progressively coarser)                          │  │   │
│  │  │   512, 1024, 2048, 4096, 8192, 16384, 32768 samples/tile       │  │   │
│  │  └────────────────────────────────────────────────────────────────┘  │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  Memory Comparison:                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │  File Size    │ Full Load (WfcFile) │ Memory-Mapped (WfcFileMmap)  │     │
│  │───────────────┼─────────────────────┼──────────────────────────────│     │
│  │  1 MB         │  ~1 MB              │  ~100 bytes                  │     │
│  │  10 MB        │  ~10 MB             │  ~100 bytes                  │     │
│  │  100 MB       │  ~100 MB            │  ~100 bytes                  │     │
│  │                                      (tile data read from disk)    │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Container System (P2/P3)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        CONTAINER SYSTEM                                      │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     AudioEvent.containerType                          │   │
│  │                                                                        │   │
│  │   none ────────────────────────────▶ Direct playback                  │   │
│  │   blend ───────────────────────────▶ BlendContainer evaluation        │   │
│  │   random ──────────────────────────▶ RandomContainer selection        │   │
│  │   sequence ────────────────────────▶ SequenceContainer tick           │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     BLEND CONTAINER                                    │   │
│  │                                                                        │   │
│  │  RTPC Value ─────▶ ┌─────────────────────────────────────────┐        │   │
│  │      0.0          │  Child A: 0.0-0.3  │ vol: 1.0 → 0.0      │        │   │
│  │      0.3          │  Child B: 0.2-0.6  │ vol: 0.0 → 1.0 → 0.0│        │   │
│  │      0.6          │  Child C: 0.5-1.0  │ vol: 0.0 → 1.0      │        │   │
│  │      1.0          └─────────────────────────────────────────┘        │   │
│  │                                                                        │   │
│  │  P3.4: smoothing_ms ──▶ Critically damped spring interpolation       │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    RANDOM CONTAINER                                    │   │
│  │                                                                        │   │
│  │  Mode: random | shuffle | roundRobin                                  │   │
│  │                                                                        │   │
│  │  Children with weights:                                               │   │
│  │    ├── Sound A (weight: 3)  ──▶ 50% chance                           │   │
│  │    ├── Sound B (weight: 2)  ──▶ 33% chance                           │   │
│  │    └── Sound C (weight: 1)  ──▶ 17% chance                           │   │
│  │                                                                        │   │
│  │  Variation:                                                           │   │
│  │    pitchVariation: ±semitones                                        │   │
│  │    volumeVariation: ±dB                                              │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                   SEQUENCE CONTAINER                                   │   │
│  │                                                                        │   │
│  │  Mode: oneShot | loop | hold | pingPong                               │   │
│  │                                                                        │   │
│  │  Steps (timeline):                                                    │   │
│  │    │ Step 0 │ Step 1 │ Step 2 │ Step 3 │ ... │                       │   │
│  │    ├────────┼────────┼────────┼────────┼─────┤                       │   │
│  │    0        1        2        3        4     beats                   │   │
│  │                                                                        │   │
│  │  P3.3A: Rust-side tick timing for microsecond accuracy               │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                   CONTAINER GROUPS (P3.3C)                            │   │
│  │                                                                        │   │
│  │  ContainerGroup                                                       │   │
│  │    ├── RandomContainer ──▶ Select variant                            │   │
│  │    │     └── BlendContainer ──▶ Apply RTPC crossfade                 │   │
│  │    └── SequenceContainer ──▶ Play steps                              │   │
│  │                                                                        │   │
│  │  Evaluation Modes: All | FirstMatch | Priority | Random               │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. SIMD DSP Pipeline (P2.1/P2.2)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SIMD DSP PIPELINE                                    │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    Runtime SIMD Detection                             │   │
│  │                                                                        │   │
│  │  #[cfg(target_arch = "x86_64")]                                       │   │
│  │  if is_x86_feature_detected!("avx512f") {                             │   │
│  │      process_avx512(samples)     // 8 f64 per iteration               │   │
│  │  } else if is_x86_feature_detected!("avx2") {                         │   │
│  │      process_avx2(samples)       // 4 f64 per iteration               │   │
│  │  } else if is_x86_feature_detected!("sse4.2") {                       │   │
│  │      process_sse42(samples)      // 2 f64 per iteration               │   │
│  │  } else {                                                              │   │
│  │      process_scalar(samples)     // 1 f64 per iteration               │   │
│  │  }                                                                     │   │
│  │                                                                        │   │
│  │  #[cfg(target_arch = "aarch64")]                                      │   │
│  │  process_neon(samples)           // ARM NEON                          │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                     P2.1: SIMD Metering                               │   │
│  │                                                                        │   │
│  │  rf_dsp::metering_simd::find_peak_simd(samples)                       │   │
│  │    ├── Load 8 f64 values (f64x8)                                     │   │
│  │    ├── Apply abs() via bitwise AND                                   │   │
│  │    ├── Compare and accumulate max                                    │   │
│  │    └── Horizontal reduce to single f64                               │   │
│  │                                                                        │   │
│  │  rf_dsp::metering_simd::calculate_rms_simd(samples)                   │   │
│  │    ├── Square each sample (x * x)                                    │   │
│  │    ├── Sum all squares (SIMD reduction)                              │   │
│  │    └── sqrt(sum / n)                                                 │   │
│  │                                                                        │   │
│  │  rf_dsp::metering_simd::calculate_correlation_simd(left, right)       │   │
│  │    ├── Multiply L × R                                                │   │
│  │    ├── Sum products                                                  │   │
│  │    └── Normalize by energy                                           │   │
│  │                                                                        │   │
│  │  Speedup: ~6x vs scalar                                               │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    P2.2: SIMD Bus Summation                           │   │
│  │                                                                        │   │
│  │  rf_dsp::simd::mix_add(dest, src, gain)                               │   │
│  │    ├── dest[i] += src[i] * gain                                      │   │
│  │    ├── Uses FMA (Fused Multiply-Add) when available                  │   │
│  │    └── Processes 8 samples per iteration (AVX2)                      │   │
│  │                                                                        │   │
│  │  BusBuffers::add_to_bus():                                            │   │
│  │    mix_add(&mut bus_l, &left, 1.0)                                   │   │
│  │    mix_add(&mut bus_r, &right, 1.0)                                  │   │
│  │                                                                        │   │
│  │  BusBuffers::sum_to_master():                                         │   │
│  │    for (bus_l, bus_r) in buses:                                      │   │
│  │        mix_add(&mut master_l, bus_l, 1.0)                            │   │
│  │        mix_add(&mut master_r, bus_r, 1.0)                            │   │
│  │                                                                        │   │
│  │  Speedup: ~4x vs scalar                                               │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Section-Based Playback Isolation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SECTION-BASED PLAYBACK ISOLATION                          │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                  UnifiedPlaybackController                            │   │
│  │                                                                        │   │
│  │  activeSection: PlaybackSection                                       │   │
│  │                                                                        │   │
│  │  acquireSection(section):                                             │   │
│  │    1. Check if section is available                                   │   │
│  │    2. Pause other sections                                            │   │
│  │    3. Set activeSection                                               │   │
│  │    4. Notify FFI: engine_set_active_section(section)                 │   │
│  │                                                                        │   │
│  │  releaseSection(section):                                             │   │
│  │    1. Clear activeSection                                             │   │
│  │    2. Resume previously active section (if any)                      │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    Voice Filtering (Rust Engine)                      │   │
│  │                                                                        │   │
│  │  PlaybackSource enum:                                                 │   │
│  │    Daw = 0        ─────▶ Always plays (uses track mute)              │   │
│  │    SlotLab = 1    ─────▶ Filtered when section != SlotLab            │   │
│  │    Middleware = 2 ─────▶ Filtered when section != Middleware         │   │
│  │    Browser = 3    ─────▶ Always plays (isolated preview)             │   │
│  │                                                                        │   │
│  │  process_one_shot_voices():                                           │   │
│  │    for voice in active_voices:                                        │   │
│  │        if should_filter(voice.source, active_section):               │   │
│  │            continue  // Skip this voice                               │   │
│  │        // Process voice...                                            │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                        Behavior Matrix                                │   │
│  │                                                                        │   │
│  │  When DAW starts playback:                                            │   │
│  │    ├── SlotLab voices: MUTED                                         │   │
│  │    ├── Middleware voices: MUTED                                      │   │
│  │    └── Browser voices: PLAY (isolated)                               │   │
│  │                                                                        │   │
│  │  When SlotLab spins:                                                  │   │
│  │    ├── DAW transport: PAUSED                                         │   │
│  │    ├── Middleware voices: MUTED                                      │   │
│  │    └── Browser voices: PLAY (isolated)                               │   │
│  │                                                                        │   │
│  │  When Middleware previews:                                            │   │
│  │    ├── DAW transport: PAUSED                                         │   │
│  │    ├── SlotLab voices: MUTED                                         │   │
│  │    └── Browser voices: PLAY (isolated)                               │   │
│  │                                                                        │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

*Generated by Claude Code — FluxForge Studio Architecture Diagrams*
*Last Updated: 2026-01-22 (P3 Complete)*
