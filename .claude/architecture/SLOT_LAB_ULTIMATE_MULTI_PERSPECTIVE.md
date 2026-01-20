# Slot Lab Ultimate — Multi-Perspective Architecture Analysis

## Document Version: 1.0
## Status: COMPREHENSIVE DESIGN DOCUMENT
## Created: 2026-01-20

---

# EXECUTIVE SUMMARY

Ovaj dokument predstavlja **ultimativnu analizu Slot Lab sistema** iz perspektive svih 7 CLAUDE.md uloga. Svaka uloga doprinosi svojom ekspertizom da osiguramo **zero gaps** u dizajnu.

## Uloge i Njihov Fokus

| Uloga | Fokus u Slot Lab | Kritični Aspekti |
|-------|------------------|------------------|
| **Chief Audio Architect** | Audio pipeline, latency, mixing | Stage→Audio sync, event timing |
| **Lead DSP Engineer** | Real-time processing, SIMD | Audio playback engine, effects |
| **Engine Architect** | Performance, memory, state | Rust engine, FFI bridge |
| **Technical Director** | Architecture decisions | System design, integration |
| **UI/UX Expert** | Workflow, interaction | Slot Lab interface, usability |
| **Graphics Engineer** | Visualization, animation | Slot preview, stage trace |
| **Security Expert** | Validation, safety | Input sanitization, bounds |

---

# PART 1: CHIEF AUDIO ARCHITECT

## 1.1 Audio Pipeline Design

### Zahtevi

Slot Lab mora da podrži **sample-accurate audio triggering** za slot game audio dizajn.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SLOT LAB AUDIO PIPELINE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   StageEvent          AudioEventRegistry        PreviewEngine               │
│       │                      │                       │                      │
│       │  timestamp_ms        │  event_id             │  play()              │
│       ▼                      ▼                       ▼                      │
│  ┌─────────┐           ┌─────────┐             ┌─────────┐                 │
│  │ STAGE   │──────────►│ LOOKUP  │────────────►│ TRIGGER │                 │
│  │ EMIT    │           │ EVENT   │             │ AUDIO   │                 │
│  └─────────┘           └─────────┘             └─────────┘                 │
│       │                      │                       │                      │
│       │                      │                       │                      │
│       ▼                      ▼                       ▼                      │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │                     TIMING COMPENSATION                          │       │
│  │                                                                  │       │
│  │   visual_timestamp ─────┐                                       │       │
│  │                         │                                       │       │
│  │   audio_latency ────────┼──► adjusted_timestamp                 │       │
│  │                         │                                       │       │
│  │   pre_trigger_offset ───┘                                       │       │
│  │                                                                  │       │
│  │   Formula:                                                       │       │
│  │   audio_trigger_time = visual_time - latency - pre_trigger      │       │
│  │                                                                  │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Stage-to-Audio Mapping Architecture

```rust
/// Complete stage-to-audio mapping system
pub struct AudioStageMapping {
    /// Default event for each stage type
    pub stage_defaults: HashMap<Stage, AudioEventId>,

    /// Per-symbol audio overrides
    pub symbol_audio: HashMap<SymbolId, SymbolAudioConfig>,

    /// Win tier audio escalation
    pub win_tier_audio: WinTierAudioConfig,

    /// Feature-specific audio
    pub feature_audio: HashMap<FeatureId, FeatureAudioConfig>,

    /// Positional audio (stereo panning per reel)
    pub positional_config: PositionalAudioConfig,
}

pub struct SymbolAudioConfig {
    /// Audio for this symbol landing
    pub land_event: Option<AudioEventId>,

    /// Audio for this symbol in winning combination
    pub win_event: Option<AudioEventId>,

    /// Audio for anticipation (if this symbol is "hot")
    pub anticipation_event: Option<AudioEventId>,
}

pub struct WinTierAudioConfig {
    /// Tier thresholds and corresponding audio
    pub tiers: Vec<WinTierAudio>,

    /// Rollup audio (tick sound)
    pub rollup_tick: AudioEventId,

    /// Rollup speed multiplier per tier
    pub rollup_speed_multiplier: HashMap<BigWinTier, f64>,
}

pub struct PositionalAudioConfig {
    /// Enable stereo panning based on reel position
    pub enabled: bool,

    /// Pan values per reel (e.g., [-0.8, -0.4, 0.0, 0.4, 0.8] for 5 reels)
    pub reel_pan_values: Vec<f32>,

    /// Depth/distance attenuation per row
    pub row_attenuation: Vec<f32>,
}
```

### 1.3 Advanced Audio Features

#### Per-Reel Stop Sounds

```
REEL_STOP Event Hierarchy:
├── REEL_STOP_0 → reel_stop_first.wav (distinct "first impact")
├── REEL_STOP_1 → reel_stop_mid.wav
├── REEL_STOP_2 → reel_stop_mid.wav
├── REEL_STOP_3 → reel_stop_mid.wav
└── REEL_STOP_4 → reel_stop_last.wav (distinct "final thud")

Alternative: Pitched variants
├── REEL_STOP_0 → reel_stop.wav @ pitch 0.9
├── REEL_STOP_1 → reel_stop.wav @ pitch 0.95
├── REEL_STOP_2 → reel_stop.wav @ pitch 1.0
├── REEL_STOP_3 → reel_stop.wav @ pitch 1.05
└── REEL_STOP_4 → reel_stop.wav @ pitch 1.1
```

#### Anticipation Audio System

```
ANTICIPATION STATES:
                                    ┌──────────────────────┐
                                    │   REEL 3 SPINNING    │
                                    │   (normal speed)     │
                                    └──────────┬───────────┘
                                               │
                                    ┌──────────▼───────────┐
                                    │  SCATTER ON REEL 1,2 │
                                    │    (2 scatters)      │
                                    └──────────┬───────────┘
                                               │
                              ┌────────────────▼────────────────┐
                              │      ANTICIPATION_ON (reel 3)   │
                              │                                  │
                              │  • Start anticipation_loop.wav  │
                              │  • Slow down reel 3 visually    │
                              │  • Tension building...          │
                              └────────────────┬────────────────┘
                                               │
                    ┌──────────────────────────┴──────────────────────────┐
                    │                                                      │
         ┌──────────▼──────────┐                            ┌──────────────▼──────────────┐
         │   SCATTER LANDS!    │                            │    NO SCATTER (miss)        │
         │                     │                            │                              │
         │ • Stop antic loop   │                            │ • Stop antic loop           │
         │ • Play scatter_hit  │                            │ • Play antic_fail.wav       │
         │ • FEATURE_ENTER     │                            │ • Continue normal           │
         └─────────────────────┘                            └─────────────────────────────┘
```

#### Layered Audio for Big Wins

```
BIG WIN AUDIO LAYERS:

Layer 1: Base Impact
├── big_win_impact.wav (one-shot)
└── Triggered at: BigWinTier stage emit

Layer 2: Celebration Loop
├── big_win_celebration_loop.wav
├── Start: 500ms after impact
└── Stop: When rollup ends

Layer 3: Crowd/Cheers (optional)
├── crowd_cheer_loop.wav
├── Volume: Scales with win tier
└── Start: 1000ms after impact

Layer 4: Rollup Ticks
├── rollup_tick.wav
├── Rate: Proportional to rollup speed
└── Pitch: Increases as amount grows

Layer 5: Final Sting
├── big_win_sting_{tier}.wav
├── Triggered at: RollupEnd
└── Tier-specific (big/mega/epic/ultra)
```

### 1.4 Audio Event Registry Schema

```json
{
  "events": {
    "SPIN_START": {
      "id": "spin_start",
      "layers": [
        {
          "file": "spin_start.wav",
          "volume": 1.0,
          "pan": 0.0,
          "delay_ms": 0
        }
      ]
    },
    "REEL_SPIN": {
      "id": "reel_spin_loop",
      "layers": [
        {
          "file": "reel_spin_loop.wav",
          "volume": 0.8,
          "loop": true,
          "fade_in_ms": 100
        }
      ],
      "stop_on": ["REEL_STOP_4", "SPIN_END"]
    },
    "REEL_STOP_0": {
      "id": "reel_stop_0",
      "layers": [
        {
          "file": "reel_stop.wav",
          "volume": 1.0,
          "pan": -0.8,
          "pitch": 0.95
        }
      ]
    },
    "WIN_PRESENT": {
      "id": "win_present",
      "layers": [
        {
          "file": "win_ding.wav",
          "volume": 1.0
        },
        {
          "file": "coins_drop.wav",
          "volume": 0.6,
          "delay_ms": 200
        }
      ],
      "conditions": {
        "min_win_ratio": 1.0
      }
    },
    "BIG_WIN_TIER": {
      "id": "big_win",
      "variants": {
        "BigWin": {
          "layers": [
            {"file": "big_win_impact.wav", "volume": 1.0},
            {"file": "big_win_loop.wav", "volume": 0.8, "delay_ms": 500, "loop": true}
          ]
        },
        "MegaWin": {
          "layers": [
            {"file": "mega_win_impact.wav", "volume": 1.0},
            {"file": "mega_win_loop.wav", "volume": 0.9, "delay_ms": 500, "loop": true},
            {"file": "crowd_cheer.wav", "volume": 0.5, "delay_ms": 1000, "loop": true}
          ]
        },
        "EpicWin": {
          "layers": [
            {"file": "epic_win_impact.wav", "volume": 1.0},
            {"file": "epic_win_loop.wav", "volume": 1.0, "delay_ms": 500, "loop": true},
            {"file": "crowd_roar.wav", "volume": 0.7, "delay_ms": 800, "loop": true},
            {"file": "epic_atmosphere.wav", "volume": 0.4, "delay_ms": 1500, "loop": true}
          ]
        }
      }
    }
  }
}
```

### 1.5 Latency Budget

```
TOTAL LATENCY BUDGET: < 20ms

┌─────────────────────────────────────────────────────────────────┐
│                    LATENCY BREAKDOWN                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Stage Emit (Rust)           │  < 1ms                           │
│  FFI Bridge                  │  < 1ms                           │
│  Dart Event Processing       │  < 2ms                           │
│  Audio Engine Scheduling     │  < 1ms                           │
│  Audio Buffer (128 samples)  │  ~3ms @ 44.1kHz                  │
│  DAC Output                  │  < 1ms                           │
│  ─────────────────────────────────────────────                  │
│  TOTAL                       │  < 10ms (typical)                │
│                                                                  │
│  Compensation Available:                                         │
│  • Pre-trigger offset: 0-50ms                                   │
│  • Visual delay: 0-100ms                                        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

# PART 2: LEAD DSP ENGINEER

## 2.1 Real-Time Audio Playback Engine

### Requirements

- **Zero allocations** in audio callback
- **Lock-free** communication between UI and audio thread
- **SIMD-optimized** mixing and effects
- **Sample-accurate** event triggering

### 2.2 Audio Playback Architecture

```rust
/// Real-time audio playback engine for Slot Lab
pub struct SlotLabAudioEngine {
    /// Pre-allocated voice pool
    voices: VoicePool,

    /// Lock-free event queue (UI → Audio)
    event_rx: rtrb::Consumer<AudioCommand>,

    /// Lock-free meter output (Audio → UI)
    meter_tx: rtrb::Producer<MeterData>,

    /// Sample rate
    sample_rate: f64,

    /// Master output buffer
    output_buffer: StereoBuffer,

    /// Global master volume
    master_volume: AtomicF32,
}

/// Pre-allocated voice pool for zero-allocation playback
pub struct VoicePool {
    /// Fixed array of voices
    voices: [Voice; MAX_VOICES],  // e.g., 64 voices

    /// Active voice count
    active_count: AtomicUsize,

    /// Free list (indices of available voices)
    free_list: ArrayVec<usize, MAX_VOICES>,
}

pub struct Voice {
    /// Current state
    state: VoiceState,

    /// Audio buffer reference (pre-loaded)
    buffer_id: BufferId,

    /// Playback position (samples)
    position: f64,

    /// Playback rate (for pitch shifting)
    playback_rate: f64,

    /// Volume envelope
    volume: f32,

    /// Pan position (-1.0 to 1.0)
    pan: f32,

    /// Fade state
    fade: FadeState,

    /// Loop points (if looping)
    loop_start: Option<usize>,
    loop_end: Option<usize>,
}

impl SlotLabAudioEngine {
    /// Audio callback - MUST be real-time safe
    #[inline(always)]
    pub fn process(&mut self, output: &mut [f32]) {
        // 1. Process incoming commands (non-blocking)
        self.process_commands();

        // 2. Clear output buffer
        self.output_buffer.clear();

        // 3. Mix all active voices
        for voice in self.voices.active_iter_mut() {
            voice.render_to(&mut self.output_buffer);
        }

        // 4. Apply master volume and copy to output
        let master = self.master_volume.load(Ordering::Relaxed);
        self.output_buffer.copy_to_interleaved(output, master);

        // 5. Send meter data (non-blocking)
        let _ = self.meter_tx.push(MeterData {
            peak_l: self.output_buffer.peak_l(),
            peak_r: self.output_buffer.peak_r(),
        });
    }

    fn process_commands(&mut self) {
        // Process up to N commands per callback to avoid starvation
        for _ in 0..MAX_COMMANDS_PER_CALLBACK {
            match self.event_rx.pop() {
                Ok(cmd) => self.handle_command(cmd),
                Err(_) => break,
            }
        }
    }

    fn handle_command(&mut self, cmd: AudioCommand) {
        match cmd {
            AudioCommand::Play { buffer_id, volume, pan, pitch } => {
                if let Some(voice) = self.voices.allocate() {
                    voice.start(buffer_id, volume, pan, pitch);
                }
            }
            AudioCommand::Stop { voice_id, fade_ms } => {
                if let Some(voice) = self.voices.get_mut(voice_id) {
                    voice.stop_with_fade(fade_ms);
                }
            }
            AudioCommand::StopEvent { event_id } => {
                for voice in self.voices.active_iter_mut() {
                    if voice.event_id == event_id {
                        voice.stop_with_fade(50.0);
                    }
                }
            }
            AudioCommand::SetMasterVolume(vol) => {
                self.master_volume.store(vol, Ordering::Relaxed);
            }
        }
    }
}
```

### 2.3 SIMD-Optimized Mixing

```rust
#[cfg(target_arch = "x86_64")]
use std::arch::x86_64::*;

/// SIMD-optimized stereo mixing
#[inline(always)]
pub unsafe fn mix_stereo_avx2(
    output: &mut [f32],
    source: &[f32],
    volume_l: f32,
    volume_r: f32,
) {
    let vol_l = _mm256_set1_ps(volume_l);
    let vol_r = _mm256_set1_ps(volume_r);

    let chunks = output.len() / 16;

    for i in 0..chunks {
        let offset = i * 16;

        // Load 8 stereo samples (16 floats)
        let src = _mm256_loadu_ps(source.as_ptr().add(offset));
        let src2 = _mm256_loadu_ps(source.as_ptr().add(offset + 8));

        let dst = _mm256_loadu_ps(output.as_ptr().add(offset));
        let dst2 = _mm256_loadu_ps(output.as_ptr().add(offset + 8));

        // Deinterleave, scale, reinterleave (simplified)
        // In practice, use proper deinterleave for L/R channels
        let scaled = _mm256_mul_ps(src, vol_l);
        let scaled2 = _mm256_mul_ps(src2, vol_l);

        let mixed = _mm256_add_ps(dst, scaled);
        let mixed2 = _mm256_add_ps(dst2, scaled2);

        _mm256_storeu_ps(output.as_mut_ptr().add(offset), mixed);
        _mm256_storeu_ps(output.as_mut_ptr().add(offset + 8), mixed2);
    }
}
```

### 2.4 Audio Buffer Management

```rust
/// Pre-loaded audio buffer storage
pub struct AudioBufferStore {
    /// All loaded buffers (indexed by BufferId)
    buffers: Vec<AudioBuffer>,

    /// Buffer lookup by name
    name_to_id: HashMap<String, BufferId>,

    /// Total memory usage
    memory_bytes: AtomicUsize,

    /// Maximum allowed memory
    max_memory_bytes: usize,
}

pub struct AudioBuffer {
    /// Unique ID
    pub id: BufferId,

    /// File name/path
    pub name: String,

    /// Sample data (interleaved stereo)
    pub samples: Vec<f32>,

    /// Sample rate
    pub sample_rate: u32,

    /// Channel count
    pub channels: u8,

    /// Duration in seconds
    pub duration_secs: f64,
}

impl AudioBufferStore {
    /// Load audio file and add to store
    pub fn load(&mut self, path: &Path) -> Result<BufferId, AudioError> {
        // Decode audio file
        let buffer = decode_audio_file(path)?;

        // Check memory limit
        let buffer_bytes = buffer.samples.len() * std::mem::size_of::<f32>();
        let current = self.memory_bytes.load(Ordering::Relaxed);
        if current + buffer_bytes > self.max_memory_bytes {
            return Err(AudioError::OutOfMemory);
        }

        // Add to store
        let id = BufferId(self.buffers.len() as u32);
        self.name_to_id.insert(buffer.name.clone(), id);
        self.buffers.push(buffer);
        self.memory_bytes.fetch_add(buffer_bytes, Ordering::Relaxed);

        Ok(id)
    }

    /// Get buffer by ID (no allocation, just reference)
    #[inline(always)]
    pub fn get(&self, id: BufferId) -> Option<&AudioBuffer> {
        self.buffers.get(id.0 as usize)
    }
}
```

---

# PART 3: ENGINE ARCHITECT

## 3.1 System Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           SLOT LAB SYSTEM ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                          FLUTTER UI LAYER                                │   │
│  │                                                                          │   │
│  │  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐              │   │
│  │  │ SlotLab   │ │ Scenario  │ │  Audio    │ │   GDD     │              │   │
│  │  │ Provider  │ │ Provider  │ │ Provider  │ │  Editor   │              │   │
│  │  └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘              │   │
│  │        │             │             │             │                     │   │
│  └────────┼─────────────┼─────────────┼─────────────┼─────────────────────┘   │
│           │             │             │             │                          │
│           └─────────────┴──────┬──────┴─────────────┘                          │
│                                │                                                │
│                         ┌──────▼──────┐                                        │
│                         │  FFI BRIDGE │                                        │
│                         │ (rf-bridge) │                                        │
│                         └──────┬──────┘                                        │
│                                │                                                │
│  ┌─────────────────────────────┼─────────────────────────────────────────────┐ │
│  │                       RUST ENGINE LAYER                                    │ │
│  │                             │                                              │ │
│  │  ┌──────────────────────────▼──────────────────────────────────────────┐  │ │
│  │  │                     SLOT LAB ENGINE                                  │  │ │
│  │  │                                                                      │  │ │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │  │ │
│  │  │  │   Game      │  │   Feature   │  │  Scenario   │                 │  │ │
│  │  │  │   Model     │  │  Registry   │  │  Playback   │                 │  │ │
│  │  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                 │  │ │
│  │  │         │                │                │                         │  │ │
│  │  │         └────────────────┼────────────────┘                         │  │ │
│  │  │                          │                                          │  │ │
│  │  │                   ┌──────▼──────┐                                   │  │ │
│  │  │                   │   SPIN      │                                   │  │ │
│  │  │                   │   ENGINE    │                                   │  │ │
│  │  │                   └──────┬──────┘                                   │  │ │
│  │  │                          │                                          │  │ │
│  │  │                   ┌──────▼──────┐                                   │  │ │
│  │  │                   │   STAGE     │                                   │  │ │
│  │  │                   │  GENERATOR  │                                   │  │ │
│  │  │                   └──────┬──────┘                                   │  │ │
│  │  │                          │                                          │  │ │
│  │  └──────────────────────────┼──────────────────────────────────────────┘  │ │
│  │                             │                                              │ │
│  │                      ┌──────▼──────┐                                      │ │
│  │                      │ AUDIO       │                                      │ │
│  │                      │ ENGINE      │                                      │ │
│  │                      │ (rf-engine) │                                      │ │
│  │                      └─────────────┘                                      │ │
│  │                                                                            │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## 3.2 Memory Management Strategy

```rust
/// Memory budget for Slot Lab
pub struct MemoryBudget {
    /// Audio buffer pool: 100MB max
    pub audio_buffers_mb: usize,

    /// Waveform cache: 50MB max
    pub waveform_cache_mb: usize,

    /// Stage history: 10MB max
    pub stage_history_mb: usize,

    /// Scenario cache: 5MB max
    pub scenario_cache_mb: usize,
}

impl Default for MemoryBudget {
    fn default() -> Self {
        Self {
            audio_buffers_mb: 100,
            waveform_cache_mb: 50,
            stage_history_mb: 10,
            scenario_cache_mb: 5,
        }
    }
}

/// Memory-efficient stage history
pub struct StageHistory {
    /// Ring buffer of stages
    stages: RingBuffer<CompactStageEvent>,

    /// Maximum entries
    max_entries: usize,

    /// Current write position
    write_pos: usize,
}

/// Compact stage event (minimal memory)
#[repr(C, packed)]
pub struct CompactStageEvent {
    /// Stage type (enum as u8)
    pub stage_type: u8,

    /// Timestamp (ms, u32 = up to ~50 days)
    pub timestamp_ms: u32,

    /// Payload (union of possible data)
    pub payload: CompactPayload,
}

// Size: 1 + 4 + 16 = 21 bytes per event
// 10MB = ~500,000 events = ~6 hours at 25 events/second
```

## 3.3 State Management

```rust
/// Complete Slot Lab state
pub struct SlotLabState {
    /// Engine mode
    pub mode: GameMode,

    /// Current game model
    pub game_model: Option<GameModel>,

    /// Feature registry
    pub feature_registry: FeatureRegistry,

    /// Active scenario
    pub scenario: Option<ScenarioState>,

    /// Spin state
    pub spin: SpinState,

    /// Audio state
    pub audio: AudioState,

    /// Statistics
    pub stats: SessionStats,
}

pub struct SpinState {
    /// Is currently spinning?
    pub is_spinning: bool,

    /// Current spin ID
    pub spin_id: u64,

    /// Last result
    pub last_result: Option<SpinResult>,

    /// Last stages
    pub last_stages: Vec<StageEvent>,

    /// Stage playback progress
    pub playback_progress: Option<PlaybackProgress>,
}

pub struct AudioState {
    /// Loaded audio pool
    pub pool: AudioPoolState,

    /// Event registry
    pub event_registry: EventRegistryState,

    /// Currently playing events
    pub playing: Vec<PlayingEvent>,

    /// Master volume
    pub master_volume: f32,

    /// Muted?
    pub muted: bool,
}

pub struct SessionStats {
    /// Total spins this session
    pub total_spins: u64,

    /// Win distribution
    pub win_distribution: WinDistribution,

    /// Feature triggers
    pub feature_triggers: HashMap<FeatureId, u64>,

    /// Average RTP (calculated)
    pub session_rtp: f64,
}
```

## 3.4 FFI Bridge Design

```rust
// rf-bridge/src/slot_lab_ffi.rs

/// Initialize Slot Lab engine
#[no_mangle]
pub extern "C" fn slot_lab_init() -> i32 {
    // Initialize with default config
    match SLOT_LAB_STATE.lock() {
        Ok(mut state) => {
            *state = Some(SlotLabState::new());
            0
        }
        Err(_) => -1,
    }
}

/// Shutdown and cleanup
#[no_mangle]
pub extern "C" fn slot_lab_shutdown() {
    if let Ok(mut state) = SLOT_LAB_STATE.lock() {
        *state = None;
    }
}

/// Load game from GDD JSON
#[no_mangle]
pub extern "C" fn slot_lab_load_gdd(gdd_json: *const c_char) -> *mut c_char {
    let gdd_str = unsafe { CStr::from_ptr(gdd_json).to_str().unwrap_or("") };

    match SLOT_LAB_STATE.lock() {
        Ok(mut state) => {
            if let Some(ref mut s) = *state {
                match GddParser::new().parse_json(gdd_str) {
                    Ok(model) => {
                        s.game_model = Some(model);
                        json_to_c_string(r#"{"status": "ok"}"#)
                    }
                    Err(e) => json_to_c_string(&format!(r#"{{"error": "{}"}}"#, e)),
                }
            } else {
                json_to_c_string(r#"{"error": "not initialized"}"#)
            }
        }
        Err(_) => json_to_c_string(r#"{"error": "lock failed"}"#),
    }
}

/// Set game mode
#[no_mangle]
pub extern "C" fn slot_lab_set_mode(mode: i32) -> i32 {
    let mode = match mode {
        0 => GameMode::GddOnly,
        1 => GameMode::MathDriven,
        _ => return -1,
    };

    match SLOT_LAB_STATE.lock() {
        Ok(mut state) => {
            if let Some(ref mut s) = *state {
                s.mode = mode;
                0
            } else {
                -1
            }
        }
        Err(_) => -1,
    }
}

/// Load scenario
#[no_mangle]
pub extern "C" fn slot_lab_load_scenario(scenario_id: *const c_char) -> i32 {
    let id = unsafe { CStr::from_ptr(scenario_id).to_str().unwrap_or("") };

    match SLOT_LAB_STATE.lock() {
        Ok(mut state) => {
            if let Some(ref mut s) = *state {
                if let Some(scenario) = DemoScenario::preset(id) {
                    s.scenario = Some(ScenarioState::new(scenario));
                    0
                } else {
                    -1 // Unknown scenario
                }
            } else {
                -1
            }
        }
        Err(_) => -1,
    }
}

/// Execute spin with optional forced outcome
#[no_mangle]
pub extern "C" fn slot_lab_spin(forced_outcome: i32) -> *mut c_char {
    match SLOT_LAB_STATE.lock() {
        Ok(mut state) => {
            if let Some(ref mut s) = *state {
                let outcome = if forced_outcome >= 0 {
                    Some(ForcedOutcome::from_i32(forced_outcome))
                } else if let Some(ref mut scenario) = s.scenario {
                    scenario.next_outcome()
                } else {
                    None
                };

                let result = s.execute_spin(outcome);
                json_to_c_string(&serde_json::to_string(&result).unwrap())
            } else {
                json_to_c_string(r#"{"error": "not initialized"}"#)
            }
        }
        Err(_) => json_to_c_string(r#"{"error": "lock failed"}"#),
    }
}

/// Get stages from last spin
#[no_mangle]
pub extern "C" fn slot_lab_get_stages() -> *mut c_char {
    match SLOT_LAB_STATE.lock() {
        Ok(state) => {
            if let Some(ref s) = *state {
                let stages = &s.spin.last_stages;
                json_to_c_string(&serde_json::to_string(stages).unwrap())
            } else {
                json_to_c_string("[]")
            }
        }
        Err(_) => json_to_c_string("[]"),
    }
}

/// Get available scenarios
#[no_mangle]
pub extern "C" fn slot_lab_get_scenarios() -> *mut c_char {
    let scenarios = DemoScenario::all_presets()
        .iter()
        .map(|s| ScenarioInfo {
            id: s.id.clone(),
            name: s.name.clone(),
            description: s.description.clone(),
            spin_count: s.sequence.len(),
        })
        .collect::<Vec<_>>();

    json_to_c_string(&serde_json::to_string(&scenarios).unwrap())
}

/// Get session statistics
#[no_mangle]
pub extern "C" fn slot_lab_get_stats() -> *mut c_char {
    match SLOT_LAB_STATE.lock() {
        Ok(state) => {
            if let Some(ref s) = *state {
                json_to_c_string(&serde_json::to_string(&s.stats).unwrap())
            } else {
                json_to_c_string(r#"{}"#)
            }
        }
        Err(_) => json_to_c_string(r#"{}"#),
    }
}
```

---

# PART 4: TECHNICAL DIRECTOR

## 4.1 Integration Architecture

### Layer Dependencies

```
DEPENDENCY FLOW (strict hierarchy):

Layer 7: Flutter UI
    │
    │ depends on
    ▼
Layer 6: Dart Providers
    │
    │ depends on
    ▼
Layer 5: FFI Bridge (rf-bridge)
    │
    │ depends on
    ▼
Layer 4: Slot Lab Engine (rf-slot-lab)
    │
    │ depends on
    ▼
Layer 3: Stage System (rf-stage)
    │
    │ depends on
    ▼
Layer 2: Audio Engine (rf-engine)
    │
    │ depends on
    ▼
Layer 1: Core Types (rf-core)

RULE: Each layer can ONLY depend on layers below it.
      No circular dependencies. No upward dependencies.
```

### 4.2 Module Boundaries

```rust
// Crate: rf-slot-lab
// Dependencies: rf-stage, rf-core, serde

pub mod model;      // GameModel, GameInfo, etc.
pub mod features;   // FeatureChapter, Registry
pub mod scenario;   // DemoScenario, Playback
pub mod parser;     // GDD parsing
pub mod engine;     // SyntheticSlotEngine

// Crate: rf-stage
// Dependencies: rf-core, serde

pub mod stage;      // Stage enum
pub mod event;      // StageEvent
pub mod payload;    // StagePayload
pub mod timing;     // Timing utilities

// Crate: rf-bridge
// Dependencies: rf-slot-lab, rf-engine, rf-stage, rf-core

pub mod slot_lab_ffi;   // Slot Lab FFI
pub mod audio_ffi;      // Audio engine FFI
pub mod common;         // Shared FFI utilities
```

### 4.3 API Contract

```yaml
# Slot Lab API Contract v1.0

initialization:
  - slot_lab_init() → i32
  - slot_lab_shutdown() → void

configuration:
  - slot_lab_load_gdd(json: string) → Result<void, Error>
  - slot_lab_set_mode(mode: 0|1) → i32
  - slot_lab_get_config() → ConfigJson

game_control:
  - slot_lab_spin(forced: i32) → SpinResultJson
  - slot_lab_get_stages() → StageArrayJson
  - slot_lab_get_grid() → GridJson

scenario:
  - slot_lab_get_scenarios() → ScenarioListJson
  - slot_lab_load_scenario(id: string) → i32
  - slot_lab_scenario_next() → SpinResultJson
  - slot_lab_scenario_reset() → i32
  - slot_lab_scenario_progress() → ProgressJson

features:
  - slot_lab_get_features() → FeatureListJson
  - slot_lab_enable_feature(id: string) → i32
  - slot_lab_disable_feature(id: string) → i32
  - slot_lab_configure_feature(id: string, config: json) → i32

audio:
  - slot_lab_get_audio_map() → AudioMapJson
  - slot_lab_set_audio_event(stage: string, event: json) → i32
  - slot_lab_trigger_test_event(event_id: string) → i32

statistics:
  - slot_lab_get_stats() → StatsJson
  - slot_lab_reset_stats() → void

# JSON Schemas defined in separate schema files
```

### 4.4 Error Handling Strategy

```rust
/// Slot Lab error types
#[derive(Debug, thiserror::Error)]
pub enum SlotLabError {
    #[error("Not initialized")]
    NotInitialized,

    #[error("Invalid GDD: {0}")]
    InvalidGdd(String),

    #[error("Feature not found: {0}")]
    FeatureNotFound(String),

    #[error("Scenario not found: {0}")]
    ScenarioNotFound(String),

    #[error("Invalid mode: {0}")]
    InvalidMode(i32),

    #[error("Engine busy")]
    EngineBusy,

    #[error("Audio error: {0}")]
    AudioError(#[from] AudioError),

    #[error("Parse error: {0}")]
    ParseError(#[from] serde_json::Error),
}

/// Result type for FFI
pub type SlotLabResult<T> = Result<T, SlotLabError>;

/// FFI error codes
pub const ERR_OK: i32 = 0;
pub const ERR_NOT_INITIALIZED: i32 = -1;
pub const ERR_INVALID_PARAM: i32 = -2;
pub const ERR_NOT_FOUND: i32 = -3;
pub const ERR_BUSY: i32 = -4;
pub const ERR_PARSE: i32 = -5;
pub const ERR_INTERNAL: i32 = -99;
```

---

# PART 5: UI/UX EXPERT

## 5.1 Slot Lab Main Interface

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│  FluxForge Studio    │ File  Edit  View  Window  Help                     [─][□][×]│
├─────────────────────────────────────────────────────────────────────────────────────┤
│ ◀ DAW │ SLOT LAB │ Middleware ▶                                                     │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌─────────────────────────────────────────────┬────────────────────────────────┐  │
│  │                                             │                                 │  │
│  │              SLOT PREVIEW                   │         STAGE TRACE            │  │
│  │                                             │                                 │  │
│  │     ┌─────┬─────┬─────┬─────┬─────┐       │   0ms ──┬── SPIN_START          │  │
│  │     │ 🍒  │ 🍊  │ 7️⃣  │ 🍊  │ 🍒  │       │         │                        │  │
│  │     ├─────┼─────┼─────┼─────┼─────┤       │  250ms ─┼── REEL_SPIN           │  │
│  │     │ 🍋  │ 7️⃣  │ 7️⃣  │ 7️⃣  │ 🍋  │ ◄WIN │         │                        │  │
│  │     ├─────┼─────┼─────┼─────┼─────┤       │  800ms ─┼── REEL_STOP_0 ──────● │  │
│  │     │ 🍇  │ 🍊  │ BAR │ 🍊  │ 🍇  │       │ 1100ms ─┼── REEL_STOP_1 ──────● │  │
│  │     └─────┴─────┴─────┴─────┴─────┘       │ 1400ms ─┼── REEL_STOP_2 ──────● │  │
│  │                                             │ 1700ms ─┼── REEL_STOP_3 ──────● │  │
│  │     WIN: $150.00  (15x)  │ BIG WIN! │       │ 2000ms ─┼── REEL_STOP_4 ──────● │  │
│  │                                             │         │                        │  │
│  │  ┌────────────────────────────────────┐    │ 2100ms ─┼── WIN_PRESENT ───────● │  │
│  │  │  ▶ SPIN │ ⏸ │ ⏹ │ 🎲 AUTO │ ⚙️  │    │         │                        │  │
│  │  └────────────────────────────────────┘    │ 2200ms ─┼── BIG_WIN_TIER ──────● │  │
│  │                                             │         │                        │  │
│  │     Mode: [GDD-Only ▼]  Speed: [Normal ▼]  │ 2500ms ─┼── ROLLUP_START        │  │
│  │                                             │         │                        │  │
│  └─────────────────────────────────────────────┴────────────────────────────────┘  │
│                                                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │  FORCED OUTCOMES                                                             │   │
│  │                                                                              │   │
│  │  [1] Lose  [2] Small  [3] Big  [4] Mega  [5] Epic  [6] FS  [7] JP  [8] Near │   │
│  │                                                                              │   │
│  │  Scenario: [Win Showcase ▼]  │ ▶ Play │ ⏸ Pause │ ⟲ Reset │  Progress: 3/8 │   │
│  │                                                                              │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  ┌───────────────────────────────────┬────────────────────────────────────────┐    │
│  │  AUDIO EVENTS                     │  EVENT LOG                             │    │
│  │                                   │                                        │    │
│  │  Stage          Event      🔊     │  [12:34:56] SPIN_START                │    │
│  │  ────────────────────────────     │  [12:34:56] REEL_SPIN → reel_spin_lp  │    │
│  │  SPIN_START    spin_start   ▶     │  [12:34:57] REEL_STOP_0 → reel_stop   │    │
│  │  REEL_SPIN     reel_loop    ▶     │  [12:34:57] REEL_STOP_1 → reel_stop   │    │
│  │  REEL_STOP_0   reel_stop_0  ▶     │  [12:34:57] REEL_STOP_2 → reel_stop   │    │
│  │  REEL_STOP_1   reel_stop_1  ▶     │  [12:34:57] REEL_STOP_3 → reel_stop   │    │
│  │  WIN_PRESENT   win_ding     ▶     │  [12:34:58] REEL_STOP_4 → reel_stop   │    │
│  │  BIG_WIN       big_win      ▶     │  [12:34:58] WIN_PRESENT → win_ding    │    │
│  │                                   │  [12:34:58] BIG_WIN → big_win_impact  │    │
│  │  [+ Add Mapping]                  │                                        │    │
│  │                                   │  [Clear] [Export] [Filter: All ▼]     │    │
│  └───────────────────────────────────┴────────────────────────────────────────┘    │
│                                                                                      │
├─────────────────────────────────────────────────────────────────────────────────────┤
│  AUDIO POOL: 12 files │ 4.2 MB │ ● Loaded                   [Master: ████████░░ 80%]│
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## 5.2 GDD Editor Interface

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│  GDD EDITOR — Game Design Document                                           [×]   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  ┌─ GAME INFO ────────────────────────────────────────────────────────────────┐    │
│  │                                                                             │    │
│  │  Name: [Egyptian Gold                    ]   ID: [egyptian_gold       ]    │    │
│  │                                                                             │    │
│  │  Provider: [Internal        ]   Volatility: [High ▼]   Target RTP: [96.5%] │    │
│  │                                                                             │    │
│  └─────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                      │
│  ┌─ GRID ──────────────────────────────────────────────────────────────────────┐   │
│  │                                                                              │   │
│  │  Reels: [5]   Rows: [3]   Win Type: [Paylines ▼]   Paylines: [20]          │   │
│  │                                                                              │   │
│  │  [ ] Megaways    [ ] Cluster Pays    [ ] Expanding Reels                    │   │
│  │                                                                              │   │
│  └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  ┌─ SYMBOLS ───────────────────────────────────────────────────────────────────┐   │
│  │                                                                              │   │
│  │  ┌──────┬──────────┬──────────┬────────────────────────┬──────────────┐    │   │
│  │  │ Icon │ Name     │ Type     │ Pays (3/4/5)           │ Actions      │    │   │
│  │  ├──────┼──────────┼──────────┼────────────────────────┼──────────────┤    │   │
│  │  │  👁️  │ Eye      │ Wild     │ 50 / 200 / 1000        │ [Edit] [Del] │    │   │
│  │  │  📜  │ Scarab   │ Scatter  │ 2x / 5x / 20x (bet)    │ [Edit] [Del] │    │   │
│  │  │  🏺  │ Pharaoh  │ High     │ 20 / 100 / 500         │ [Edit] [Del] │    │   │
│  │  │  🐍  │ Cobra    │ High     │ 15 / 75 / 300          │ [Edit] [Del] │    │   │
│  │  │  🪲  │ Beetle   │ Medium   │ 10 / 50 / 200          │ [Edit] [Del] │    │   │
│  │  │  A   │ Ace      │ Low      │ 5 / 20 / 80            │ [Edit] [Del] │    │   │
│  │  │  K   │ King     │ Low      │ 4 / 15 / 60            │ [Edit] [Del] │    │   │
│  │  │  Q   │ Queen    │ Low      │ 3 / 10 / 40            │ [Edit] [Del] │    │   │
│  │  └──────┴──────────┴──────────┴────────────────────────┴──────────────┘    │   │
│  │                                                                              │   │
│  │  [+ Add Symbol]                                                              │   │
│  │                                                                              │   │
│  └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  ┌─ FEATURES ──────────────────────────────────────────────────────────────────┐   │
│  │                                                                              │   │
│  │  [✓] Free Spins                                                             │   │
│  │      Trigger: 3+ Scatter │ Spins: 10-15 │ Multiplier: 2x                   │   │
│  │      [ ] Retrigger    [ ] Expanding Wilds                                   │   │
│  │                                                                              │   │
│  │  [ ] Cascades                                                                │   │
│  │      Max Steps: 8 │ Multiplier Step: +1x                                    │   │
│  │                                                                              │   │
│  │  [ ] Hold & Win                                                              │   │
│  │                                                                              │   │
│  │  [ ] Jackpot Wheel                                                           │   │
│  │      Tiers: Mini (50x) │ Minor (200x) │ Major (1000x) │ Grand (10000x)     │   │
│  │                                                                              │   │
│  │  [+ Add Feature from Registry]                                               │   │
│  │                                                                              │   │
│  └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  ┌─ WIN TIERS ─────────────────────────────────────────────────────────────────┐   │
│  │                                                                              │   │
│  │  Small: < 5x │ Medium: 5-15x │ Big: 15-25x │ Mega: 25-50x │ Epic: 50-100x  │   │
│  │                                                                              │   │
│  └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  ┌──────────────────────────────────────────────────────────────────────────────┐  │
│  │  [Validate GDD]  │  [Load from File]  │  [Export JSON]  │  [Apply to Engine] │  │
│  └──────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                      │
│  Validation: ✓ Valid — Ready to use                                                 │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## 5.3 Scenario Editor Interface

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│  SCENARIO EDITOR — Demo Sequence Builder                                     [×]   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│  Scenario: [Win Showcase               ]   Loop: [Once ▼]   [Save] [Save As] [Del] │
│                                                                                      │
│  Description: [Demonstrates all win tiers from lose to epic win                   ] │
│                                                                                      │
│  ┌─ SEQUENCE ──────────────────────────────────────────────────────────────────┐   │
│  │                                                                              │   │
│  │   #  │ Outcome        │ Parameters            │ Note              │ Actions │   │
│  │  ────┼────────────────┼───────────────────────┼───────────────────┼─────────│   │
│  │   1  │ Lose           │ —                     │ Base case         │ ⬆ ⬇ ✕  │   │
│  │   2  │ Small Win      │ ratio: 2x             │ Minor win         │ ⬆ ⬇ ✕  │   │
│  │   3  │ Medium Win     │ ratio: 8x             │ Decent win        │ ⬆ ⬇ ✕  │   │
│  │   4  │ Big Win        │ ratio: 18x            │ Big win tier      │ ⬆ ⬇ ✕  │   │
│  │   5  │ Mega Win       │ ratio: 35x            │ Mega celebration  │ ⬆ ⬇ ✕  │   │
│  │   6  │ Epic Win       │ ratio: 70x            │ Epic fanfare      │ ⬆ ⬇ ✕  │   │
│  │   7  │ Free Spins     │ count: 10, mult: 2x   │ Feature trigger   │ ⬆ ⬇ ✕  │   │
│  │   8  │ Jackpot Grand  │ —                     │ Grand jackpot     │ ⬆ ⬇ ✕  │   │
│  │                                                                              │   │
│  │  [+ Add Step]                                                                │   │
│  │                                                                              │   │
│  └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  ┌─ ADD STEP ──────────────────────────────────────────────────────────────────┐   │
│  │                                                                              │   │
│  │  Type: [Big Win ▼]                                                          │   │
│  │                                                                              │   │
│  │  ┌─ WIN TIERS ───────┐  ┌─ FEATURES ────────┐  ┌─ SPECIAL ─────────┐       │   │
│  │  │ ○ Lose            │  │ ○ Free Spins      │  │ ○ Near Miss       │       │   │
│  │  │ ○ Small Win       │  │ ○ Cascade Chain   │  │ ○ Specific Grid   │       │   │
│  │  │ ○ Medium Win      │  │ ○ Hold & Win      │  │ ○ Anticipation    │       │   │
│  │  │ ● Big Win         │  │ ○ Bonus Wheel     │  │                   │       │   │
│  │  │ ○ Mega Win        │  │                   │  │                   │       │   │
│  │  │ ○ Epic Win        │  │ ┌─ JACKPOT ─────┐ │  │                   │       │   │
│  │  │ ○ Ultra Win       │  │ │ ○ Mini        │ │  │                   │       │   │
│  │  └───────────────────┘  │ │ ○ Minor       │ │  └───────────────────┘       │   │
│  │                         │ │ ○ Major       │ │                              │   │
│  │  Parameters:            │ │ ○ Grand       │ │                              │   │
│  │  Ratio: [18.0]         │ └───────────────┘ │                              │   │
│  │                         └──────────────────┘                              │   │
│  │  Note: [Big win for audio testing          ]                              │   │
│  │                                                                              │   │
│  │  [Add to Sequence]                                                           │   │
│  │                                                                              │   │
│  └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  ┌─ PRESETS ───────────────────────────────────────────────────────────────────┐   │
│  │                                                                              │   │
│  │  [Win Showcase] [Free Spins Demo] [Cascade Demo] [Jackpot Demo] [Stress]   │   │
│  │                                                                              │   │
│  └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                      │
│  [Preview Sequence]  │  Total Steps: 8  │  Est. Duration: ~45 sec                   │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## 5.4 UX Flow Diagrams

### Main Workflow

```
                              USER ENTERS SLOT LAB
                                      │
                                      ▼
                    ┌─────────────────────────────────┐
                    │    Has existing game loaded?    │
                    └─────────────────┬───────────────┘
                                      │
                        ┌─────────────┴─────────────┐
                        │                           │
                       YES                          NO
                        │                           │
                        ▼                           ▼
                ┌───────────────┐          ┌───────────────┐
                │ Show current  │          │ Show welcome  │
                │ game state    │          │ / quick start │
                └───────┬───────┘          └───────┬───────┘
                        │                           │
                        │                           ▼
                        │                  ┌───────────────────┐
                        │                  │ Options:          │
                        │                  │ • Load GDD        │
                        │                  │ • Use template    │
                        │                  │ • Start empty     │
                        │                  └─────────┬─────────┘
                        │                            │
                        └────────────┬───────────────┘
                                     │
                                     ▼
                        ┌────────────────────────┐
                        │   MAIN WORKSPACE       │
                        │                        │
                        │  • Slot Preview        │
                        │  • Stage Trace         │
                        │  • Audio Events        │
                        │  • Forced Outcomes     │
                        │  • Scenario Controls   │
                        └────────────────────────┘
                                     │
                                     ▼
                        ┌────────────────────────┐
                        │   USER ACTIONS         │
                        │                        │
                        │  • Spin (manual)       │
                        │  • Force outcome       │
                        │  • Play scenario       │
                        │  • Map audio events    │
                        │  • Edit GDD            │
                        │  • Switch mode         │
                        └────────────────────────┘
```

### Audio Mapping Workflow

```
                        USER WANTS TO MAP AUDIO
                                   │
                                   ▼
                      ┌────────────────────────┐
                      │ Select Stage to Map    │
                      │ (from Stage Trace or   │
                      │  Audio Events panel)   │
                      └───────────┬────────────┘
                                  │
                                  ▼
                      ┌────────────────────────┐
                      │ Select Audio Source    │
                      │                        │
                      │ • From Audio Pool      │
                      │ • Browse file          │
                      │ • Record new           │
                      └───────────┬────────────┘
                                  │
                                  ▼
                      ┌────────────────────────┐
                      │ Configure Layer        │
                      │                        │
                      │ • Volume: [────●───]   │
                      │ • Pan:    [──●─────]   │
                      │ • Delay:  [0 ms    ]   │
                      │ • Loop:   [ ]          │
                      │ • Pitch:  [1.0    ]    │
                      └───────────┬────────────┘
                                  │
                                  ▼
                      ┌────────────────────────┐
                      │ Preview (▶ Test)       │
                      └───────────┬────────────┘
                                  │
                                  ▼
                      ┌────────────────────────┐
                      │ Satisfied?             │
                      └───────────┬────────────┘
                                  │
                        ┌─────────┴─────────┐
                       YES                  NO
                        │                    │
                        ▼                    │
                      ┌────────────────┐     │
                      │ Save Mapping   │     │
                      └────────────────┘     │
                                             │
                              ┌──────────────┘
                              │
                              ▼
                      ┌────────────────────────┐
                      │ Add more layers?       │
                      │ [+ Add Layer]          │
                      └────────────────────────┘
```

## 5.5 Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Space` | Spin / Pause |
| `1-9, 0` | Force outcome (Lose, Small, Big, Mega, Epic, FS, JP, Near, Cascade, Ultra) |
| `Ctrl+S` | Save current state |
| `Ctrl+E` | Open GDD Editor |
| `Ctrl+Shift+E` | Open Scenario Editor |
| `Ctrl+P` | Play/Pause scenario |
| `Ctrl+R` | Reset scenario |
| `Ctrl+M` | Toggle mode (GDD-only ↔ Math) |
| `Ctrl+L` | Open event log |
| `F5` | Refresh audio pool |
| `Escape` | Stop all audio |

---

# PART 6: GRAPHICS ENGINEER

## 6.1 Slot Preview Rendering

### Symbol Rendering Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                        SYMBOL RENDERING PIPELINE                                     │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                      │
│   Symbol Asset                GPU Texture             Render Pass                   │
│       │                           │                       │                         │
│       ▼                           ▼                       ▼                         │
│  ┌─────────┐               ┌─────────────┐         ┌─────────────┐                │
│  │  SVG /  │──── Load ────►│  Texture    │────────►│   Draw      │                │
│  │  PNG    │               │  Atlas      │         │   Call      │                │
│  └─────────┘               └─────────────┘         └─────────────┘                │
│                                   │                       │                         │
│                                   │                       │                         │
│                                   ▼                       ▼                         │
│                            ┌─────────────┐         ┌─────────────┐                │
│                            │  Mipmap     │         │  Shader     │                │
│                            │  Generation │         │  Effects    │                │
│                            └─────────────┘         └─────────────┘                │
│                                                          │                         │
│                                                          ▼                         │
│                                                   ┌─────────────┐                 │
│                                                   │  • Glow     │                 │
│                                                   │  • Pulse    │                 │
│                                                   │  • Win      │                 │
│                                                   │    Highlight│                 │
│                                                   └─────────────┘                 │
│                                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 6.2 Animation System

```dart
/// Slot animation controller
class SlotAnimationController {
  /// Reel spin animations
  final List<ReelSpinAnimation> reelAnimations;

  /// Win celebration animation
  WinCelebrationAnimation? winAnimation;

  /// Symbol highlight animations
  final Map<(int, int), SymbolHighlightAnimation> highlights;

  /// Big win screen overlay
  BigWinOverlay? bigWinOverlay;
}

/// Individual reel spin animation
class ReelSpinAnimation {
  final int reelIndex;

  /// Animation state
  ReelAnimationState state = ReelAnimationState.idle;

  /// Current visual position (for blur effect)
  double visualPosition = 0;

  /// Target stop position
  int targetStopIndex = 0;

  /// Spin speed (symbols per second)
  double spinSpeed = 20.0;

  /// Anticipation slow-down factor
  double anticipationFactor = 1.0;

  /// Bounce effect on stop
  final SpringSimulation bounceSimulation;
}

/// Win highlight animation
class SymbolHighlightAnimation {
  /// Position (reel, row)
  final int reel;
  final int row;

  /// Animation type
  HighlightType type; // glow, pulse, frame

  /// Current opacity
  double opacity = 0;

  /// Animation phase
  double phase = 0;

  /// Is part of winning line?
  bool isWinning = false;

  /// Wild indicator
  bool isWild = false;
}

/// Big win overlay animation
class BigWinOverlay {
  /// Win tier
  final BigWinTier tier;

  /// Animation phase (intro, loop, outro)
  BigWinPhase phase = BigWinPhase.intro;

  /// Particle system for coins/confetti
  final ParticleSystem particles;

  /// Counter animation
  final CounterAnimation counter;

  /// Background effects
  final BackgroundEffect background;
}
```

### 6.3 Stage Trace Visualization

```dart
/// Stage trace timeline widget
class StageTraceWidget extends StatefulWidget {
  final List<StageEvent> stages;
  final double currentTime;
  final void Function(StageEvent)? onStageSelected;
}

class _StageTraceWidgetState extends State<StageTraceWidget> {
  /// Scroll controller for timeline
  final ScrollController _scrollController = ScrollController();

  /// Selected stage
  StageEvent? _selectedStage;

  /// Zoom level (ms per pixel)
  double _msPerPixel = 5.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        _buildToolbar(),

        // Timeline
        Expanded(
          child: CustomPaint(
            painter: StageTimelinePainter(
              stages: widget.stages,
              currentTime: widget.currentTime,
              selectedStage: _selectedStage,
              msPerPixel: _msPerPixel,
              stageColors: _getStageColors(),
            ),
            child: GestureDetector(
              onTapUp: _handleTap,
              onScaleUpdate: _handleZoom,
            ),
          ),
        ),

        // Selected stage details
        if (_selectedStage != null)
          _buildStageDetails(_selectedStage!),
      ],
    );
  }

  Map<String, Color> _getStageColors() {
    return {
      'SPIN_START': Colors.blue,
      'REEL_SPIN': Colors.lightBlue,
      'REEL_STOP': Colors.green,
      'ANTICIPATION': Colors.orange,
      'WIN_PRESENT': Colors.yellow,
      'BIG_WIN': Colors.amber,
      'FEATURE': Colors.purple,
      'JACKPOT': Colors.red,
      'ROLLUP': Colors.teal,
    };
  }
}

/// Custom painter for stage timeline
class StageTimelinePainter extends CustomPainter {
  final List<StageEvent> stages;
  final double currentTime;
  final StageEvent? selectedStage;
  final double msPerPixel;
  final Map<String, Color> stageColors;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw time ruler
    _drawTimeRuler(canvas, size);

    // Draw stage events
    for (final stage in stages) {
      _drawStageEvent(canvas, size, stage);
    }

    // Draw current time indicator
    _drawCurrentTimeIndicator(canvas, size);

    // Draw connections (for related stages)
    _drawConnections(canvas, size);
  }

  void _drawStageEvent(Canvas canvas, Size size, StageEvent stage) {
    final x = stage.timestampMs / msPerPixel;
    final color = stageColors[_getStageCategory(stage)] ?? Colors.grey;

    // Draw event marker
    final markerRect = Rect.fromLTWH(x - 2, 20, 4, size.height - 40);
    canvas.drawRect(markerRect, Paint()..color = color);

    // Draw label
    final textPainter = TextPainter(
      text: TextSpan(
        text: stage.stage.name,
        style: TextStyle(color: Colors.white, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x + 4, markerRect.top));

    // Draw audio indicator if mapped
    if (stage.hasAudioMapping) {
      _drawAudioIndicator(canvas, x, markerRect.bottom);
    }
  }
}
```

### 6.4 Performance Optimizations

```dart
/// Optimized rendering for Slot Lab
class SlotLabRenderer {
  /// Pre-rendered symbol textures
  final Map<int, ui.Image> symbolTextures = {};

  /// Cached gradient for reels
  ui.Gradient? reelGradient;

  /// Frame budget tracking
  final Stopwatch _frameStopwatch = Stopwatch();

  /// Target frame time (16.67ms for 60fps)
  static const double targetFrameMs = 16.67;

  void renderFrame(Canvas canvas, Size size, SlotLabState state) {
    _frameStopwatch.reset();
    _frameStopwatch.start();

    // 1. Render background (cached)
    _renderBackground(canvas, size);

    // 2. Render reels (optimized)
    _renderReels(canvas, size, state.grid, state.reelAnimations);

    // 3. Render win highlights (if any)
    if (state.hasWinHighlights) {
      _renderWinHighlights(canvas, size, state.highlights);
    }

    // 4. Render big win overlay (if active)
    if (state.bigWinOverlay != null) {
      _renderBigWinOverlay(canvas, size, state.bigWinOverlay!);
    }

    _frameStopwatch.stop();

    // Log if over budget
    if (_frameStopwatch.elapsedMilliseconds > targetFrameMs) {
      debugPrint('Frame over budget: ${_frameStopwatch.elapsedMilliseconds}ms');
    }
  }

  void _renderReels(
    Canvas canvas,
    Size size,
    List<List<int>> grid,
    List<ReelSpinAnimation> animations,
  ) {
    final reelWidth = size.width / grid.length;
    final rowHeight = size.height / 3;

    for (int reel = 0; reel < grid.length; reel++) {
      final anim = animations[reel];
      final reelX = reel * reelWidth;

      // If spinning, render with blur
      if (anim.state == ReelAnimationState.spinning) {
        _renderSpinningReel(canvas, reelX, reelWidth, rowHeight, anim);
      } else {
        // Static render
        for (int row = 0; row < grid[reel].length; row++) {
          final symbolId = grid[reel][row];
          final texture = symbolTextures[symbolId];
          if (texture != null) {
            final destRect = Rect.fromLTWH(
              reelX,
              row * rowHeight,
              reelWidth,
              rowHeight,
            );
            canvas.drawImageRect(
              texture,
              Rect.fromLTWH(0, 0, texture.width.toDouble(), texture.height.toDouble()),
              destRect,
              Paint(),
            );
          }
        }
      }
    }
  }

  void _renderSpinningReel(
    Canvas canvas,
    double x,
    double width,
    double rowHeight,
    ReelSpinAnimation anim,
  ) {
    // Apply motion blur effect
    canvas.saveLayer(
      Rect.fromLTWH(x, 0, width, rowHeight * 3),
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 0, sigmaY: anim.spinSpeed * 0.5),
    );

    // Draw multiple symbol copies for blur effect
    // ...

    canvas.restore();
  }
}
```

---

# PART 7: SECURITY EXPERT

## 7.1 Input Validation

### GDD Validation

```rust
/// GDD input sanitization and validation
pub struct GddValidator {
    /// Maximum allowed values
    pub limits: GddLimits,
}

pub struct GddLimits {
    pub max_name_length: usize,        // 256
    pub max_symbols: usize,            // 50
    pub max_paylines: usize,           // 100
    pub max_features: usize,           // 20
    pub max_reels: usize,              // 10
    pub max_rows: usize,               // 10
    pub max_pay_value: f64,            // 100_000.0
    pub max_multiplier: f64,           // 10_000.0
    pub max_scenario_steps: usize,     // 1000
}

impl GddValidator {
    pub fn validate(&self, gdd: &StructuredGdd) -> Result<(), ValidationError> {
        // 1. Validate strings (no injection)
        self.validate_string(&gdd.game.name, "game.name")?;
        self.validate_string(&gdd.game.id, "game.id")?;

        // 2. Validate numeric ranges
        self.validate_grid(&gdd.grid)?;

        // 3. Validate symbols
        if gdd.symbols.len() > self.limits.max_symbols {
            return Err(ValidationError::TooManySymbols(gdd.symbols.len()));
        }
        for symbol in &gdd.symbols {
            self.validate_symbol(symbol)?;
        }

        // 4. Validate features
        if gdd.features.len() > self.limits.max_features {
            return Err(ValidationError::TooManyFeatures(gdd.features.len()));
        }

        // 5. Validate pay values (prevent overflow)
        self.validate_pay_values(gdd)?;

        Ok(())
    }

    fn validate_string(&self, s: &str, field: &str) -> Result<(), ValidationError> {
        // Check length
        if s.len() > self.limits.max_name_length {
            return Err(ValidationError::StringTooLong(field.to_string()));
        }

        // Check for dangerous characters (path traversal, injection)
        if s.contains("..") || s.contains('/') || s.contains('\\') {
            return Err(ValidationError::InvalidCharacters(field.to_string()));
        }

        // Check for null bytes
        if s.contains('\0') {
            return Err(ValidationError::NullByte(field.to_string()));
        }

        Ok(())
    }

    fn validate_grid(&self, grid: &GridGdd) -> Result<(), ValidationError> {
        if grid.reels > self.limits.max_reels {
            return Err(ValidationError::ReelCountExceeded(grid.reels));
        }
        if grid.rows > self.limits.max_rows {
            return Err(ValidationError::RowCountExceeded(grid.rows));
        }
        if grid.paylines > self.limits.max_paylines {
            return Err(ValidationError::PaylineCountExceeded(grid.paylines));
        }
        Ok(())
    }

    fn validate_pay_values(&self, gdd: &StructuredGdd) -> Result<(), ValidationError> {
        for symbol in &gdd.symbols {
            for pay in &symbol.pays {
                if *pay < 0.0 {
                    return Err(ValidationError::NegativePayValue);
                }
                if *pay > self.limits.max_pay_value {
                    return Err(ValidationError::PayValueTooHigh(*pay));
                }
                if pay.is_nan() || pay.is_infinite() {
                    return Err(ValidationError::InvalidPayValue);
                }
            }
        }
        Ok(())
    }
}
```

### 7.2 Audio File Validation

```rust
/// Audio file security validation
pub struct AudioFileValidator;

impl AudioFileValidator {
    /// Validate audio file before loading
    pub fn validate(path: &Path, data: &[u8]) -> Result<(), AudioValidationError> {
        // 1. Check file extension
        let ext = path.extension()
            .and_then(|e| e.to_str())
            .map(|e| e.to_lowercase());

        let allowed_extensions = ["wav", "mp3", "ogg", "flac", "aiff"];
        if !ext.map(|e| allowed_extensions.contains(&e.as_str())).unwrap_or(false) {
            return Err(AudioValidationError::InvalidExtension);
        }

        // 2. Check magic bytes (file signature)
        if !Self::validate_magic_bytes(data, &ext.unwrap_or_default()) {
            return Err(AudioValidationError::InvalidFileSignature);
        }

        // 3. Check file size (max 100MB)
        const MAX_SIZE: usize = 100 * 1024 * 1024;
        if data.len() > MAX_SIZE {
            return Err(AudioValidationError::FileTooLarge(data.len()));
        }

        // 4. Validate audio metadata
        Self::validate_audio_metadata(data)?;

        Ok(())
    }

    fn validate_magic_bytes(data: &[u8], ext: &str) -> bool {
        if data.len() < 12 {
            return false;
        }

        match ext {
            "wav" => &data[0..4] == b"RIFF" && &data[8..12] == b"WAVE",
            "mp3" => &data[0..3] == b"\xFF\xFB\x90" || &data[0..3] == b"ID3",
            "ogg" => &data[0..4] == b"OggS",
            "flac" => &data[0..4] == b"fLaC",
            "aiff" => &data[0..4] == b"FORM" && &data[8..12] == b"AIFF",
            _ => false,
        }
    }

    fn validate_audio_metadata(data: &[u8]) -> Result<(), AudioValidationError> {
        // Parse header to check for valid audio parameters
        // This prevents loading malformed files that could cause crashes

        // ... header parsing logic ...

        Ok(())
    }
}
```

### 7.3 Scenario Validation

```rust
/// Scenario security validation
pub struct ScenarioValidator {
    pub max_steps: usize,
    pub max_delay_ms: f64,
}

impl ScenarioValidator {
    pub fn validate(&self, scenario: &DemoScenario) -> Result<(), ScenarioValidationError> {
        // 1. Check step count
        if scenario.sequence.len() > self.max_steps {
            return Err(ScenarioValidationError::TooManySteps(scenario.sequence.len()));
        }

        // 2. Validate each step
        for (i, step) in scenario.sequence.iter().enumerate() {
            self.validate_step(step, i)?;
        }

        // 3. Check for infinite loops
        if let LoopMode::Forever = scenario.loop_mode {
            // Allowed, but log warning
            log::warn!("Scenario {} has infinite loop mode", scenario.id);
        }

        Ok(())
    }

    fn validate_step(&self, step: &ScriptedSpin, index: usize) -> Result<(), ScenarioValidationError> {
        // Check delay bounds
        if let Some(delay) = step.delay_before_ms {
            if delay < 0.0 {
                return Err(ScenarioValidationError::NegativeDelay(index));
            }
            if delay > self.max_delay_ms {
                return Err(ScenarioValidationError::DelayTooLong(index, delay));
            }
        }

        // Validate outcome parameters
        match &step.outcome {
            ScriptedOutcome::SmallWin { target_ratio }
            | ScriptedOutcome::MediumWin { target_ratio }
            | ScriptedOutcome::BigWin { target_ratio } => {
                if *target_ratio < 0.0 || *target_ratio > 10000.0 {
                    return Err(ScenarioValidationError::InvalidRatio(index, *target_ratio));
                }
            }
            ScriptedOutcome::TriggerFreeSpins { count, multiplier } => {
                if *count > 1000 || *multiplier > 1000.0 {
                    return Err(ScenarioValidationError::InvalidFeatureParams(index));
                }
            }
            ScriptedOutcome::SpecificGrid { grid } => {
                // Validate grid dimensions
                if grid.len() > 10 || grid.iter().any(|col| col.len() > 10) {
                    return Err(ScenarioValidationError::InvalidGridSize(index));
                }
            }
            _ => {}
        }

        Ok(())
    }
}
```

### 7.4 FFI Safety

```rust
/// Safe FFI wrapper with bounds checking
pub struct SafeFfi;

impl SafeFfi {
    /// Safe string conversion from C
    pub fn c_str_to_string(ptr: *const c_char) -> Option<String> {
        if ptr.is_null() {
            return None;
        }

        unsafe {
            // Limit string length to prevent DoS
            const MAX_LEN: usize = 1024 * 1024; // 1MB max

            let c_str = CStr::from_ptr(ptr);
            let bytes = c_str.to_bytes();

            if bytes.len() > MAX_LEN {
                log::error!("FFI string too long: {} bytes", bytes.len());
                return None;
            }

            c_str.to_str().ok().map(String::from)
        }
    }

    /// Safe JSON parsing with size limit
    pub fn parse_json<T: serde::de::DeserializeOwned>(json: &str) -> Result<T, FfiError> {
        const MAX_JSON_SIZE: usize = 10 * 1024 * 1024; // 10MB

        if json.len() > MAX_JSON_SIZE {
            return Err(FfiError::JsonTooLarge(json.len()));
        }

        serde_json::from_str(json).map_err(FfiError::ParseError)
    }

    /// Safe array index access
    #[inline]
    pub fn safe_index<T>(slice: &[T], index: usize) -> Option<&T> {
        slice.get(index)
    }
}

/// Rate limiter for FFI calls
pub struct FfiRateLimiter {
    /// Max calls per second
    max_calls_per_second: u32,

    /// Current call count
    call_count: AtomicU32,

    /// Last reset time
    last_reset: AtomicU64,
}

impl FfiRateLimiter {
    pub fn check(&self) -> bool {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let last = self.last_reset.load(Ordering::Relaxed);

        if now > last {
            self.last_reset.store(now, Ordering::Relaxed);
            self.call_count.store(1, Ordering::Relaxed);
            return true;
        }

        let count = self.call_count.fetch_add(1, Ordering::Relaxed);
        count < self.max_calls_per_second
    }
}
```

---

# PART 8: CONSOLIDATED CHECKLIST

## 8.1 Complete Feature Matrix

| Feature | Chief Audio | Lead DSP | Engine | Tech Dir | UI/UX | Graphics | Security |
|---------|-------------|----------|--------|----------|-------|----------|----------|
| Stage→Audio Mapping | ✓ | | | | | | |
| Latency Compensation | ✓ | ✓ | | | | | |
| Layered Audio Events | ✓ | ✓ | | | | | |
| Per-Reel Audio | ✓ | | | | | | |
| RT Audio Engine | | ✓ | | | | | |
| SIMD Mixing | | ✓ | | | | | |
| Voice Pool | | ✓ | | | | | |
| Memory Management | | | ✓ | | | | |
| State Management | | | ✓ | | | | |
| FFI Bridge | | | ✓ | ✓ | | | |
| Module Boundaries | | | | ✓ | | | |
| API Contract | | | | ✓ | | | |
| Main Interface | | | | | ✓ | | |
| GDD Editor | | | | | ✓ | | |
| Scenario Editor | | | | | ✓ | | |
| UX Flows | | | | | ✓ | | |
| Slot Preview | | | | | | ✓ | |
| Stage Trace | | | | | | ✓ | |
| Animations | | | | | | ✓ | |
| Input Validation | | | | | | | ✓ |
| File Validation | | | | | | | ✓ |
| FFI Safety | | | | | | | ✓ |

## 8.2 Implementation Priority

### P0 — Core (Must Have)

- [ ] FeatureChapter trait
- [ ] Feature Registry
- [ ] GameModel structure
- [ ] GDD Parser (JSON)
- [ ] DemoScenario system
- [ ] Mode switching (GDD-only / Math)
- [ ] Input validation

### P1 — Essential

- [ ] Free Spins Chapter
- [ ] Cascades Chapter
- [ ] Scenario Playback
- [ ] Built-in Presets
- [ ] Stage Trace UI
- [ ] Audio Event Mapping UI

### P2 — Important

- [ ] Hold & Win Chapter
- [ ] Jackpot Chapter
- [ ] GDD Editor UI
- [ ] Scenario Editor UI
- [ ] Slot Preview Animations
- [ ] Big Win Overlay

### P3 — Nice to Have

- [ ] YAML GDD parser
- [ ] State Machine Generator
- [ ] Custom Symbol Import
- [ ] Advanced Animations
- [ ] Statistics Dashboard

## 8.3 Testing Requirements

| Area | Unit Tests | Integration | E2E |
|------|------------|-------------|-----|
| Feature Registry | ✓ | ✓ | |
| GDD Parser | ✓ | ✓ | |
| Scenario System | ✓ | ✓ | |
| Audio Pipeline | ✓ | ✓ | ✓ |
| FFI Bridge | ✓ | ✓ | |
| UI Components | | ✓ | ✓ |
| Security | ✓ | ✓ | |

## 8.4 Documentation Requirements

- [ ] API Reference (auto-generated from Rust docs)
- [ ] GDD Schema Documentation
- [ ] Scenario Format Documentation
- [ ] UI User Guide
- [ ] Audio Mapping Guide
- [ ] Security Guidelines

---

# CONCLUSION

Ovaj dokument pokriva **sve aspekte** Slot Lab Ultimate sistema iz perspektive svih 7 uloga definisanih u CLAUDE.md.

**Nema rupa** — svaki aspekt je analiziran:

1. **Audio** — Kompletan pipeline, latency, layering
2. **DSP** — Real-time engine, SIMD, voice pool
3. **Engine** — Memory, state, FFI
4. **Architecture** — Modules, API, integration
5. **UI/UX** — Interfaces, workflows, shortcuts
6. **Graphics** — Rendering, animations, performance
7. **Security** — Validation, safety, bounds

**Sledeći korak:** Početi implementaciju po fazama definisanim u IMPLEMENTATION_PLAN.md.

---

*Document created: 2026-01-20*
*Total perspectives: 7*
*Status: COMPREHENSIVE — Ready for implementation*
