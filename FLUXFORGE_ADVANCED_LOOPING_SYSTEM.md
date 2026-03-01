# FluxForge Advanced Looping System — Ultimate Specification

**Version:** 1.0
**Date:** 2026-03-01
**Authority:** Chief Audio Architect + Lead DSP Engineer + Engine Architect + Technical Director + UI/UX Expert + Security Expert
**Prerequisite:** CLAUDE.md, .claude/00_AUTHORITY.md (Hard Non-Negotiables)
**Wwise Parity:** Full Entry/Exit/Custom Cue model + Sync To + Transition Segments
**FluxForge Superiority:** Multi-region, intro embedding policy, dual-voice web-safe loop, sample-level determinism, sidecar markers, QA harness

---

## Table of Contents

1. [System Goal & Scope](#1-system-goal--scope)
2. [Terminology Lock](#2-terminology-lock)
3. [Wwise Behavioral Model (What We Emulate)](#3-wwise-behavioral-model)
4. [FluxForge Superiority Layer (What We Add)](#4-fluxforge-superiority-layer)
5. [Authoritative Data Model](#5-authoritative-data-model)
6. [Runtime State Machine](#6-runtime-state-machine)
7. [Engine Implementation (Rust)](#7-engine-implementation-rust)
8. [Dual-Voice Crossfade Loop (Web-Safe)](#8-dual-voice-crossfade-loop-web-safe)
9. [Single-Voice PCM Wrap (Native)](#9-single-voice-pcm-wrap-native)
10. [Region Switch Without Restart](#10-region-switch-without-restart)
11. [Transitions & Pre-Entry / Post-Exit](#11-transitions--pre-entry--post-exit)
12. [Marker Ingest Pipeline](#12-marker-ingest-pipeline)
13. [Command API](#13-command-api)
14. [Authoring UI/UX](#14-authoring-uiux)
15. [Validation & Fail-Fast](#15-validation--fail-fast)
16. [QA Test Harness](#16-qa-test-harness)
17. [Integration with Existing Systems](#17-integration-with-existing-systems)
18. [Gap Analysis — Holes Plugged](#18-gap-analysis--holes-plugged)
19. [Implementation Phases](#19-implementation-phases)
20. [File Manifest](#20-file-manifest)

---

## 1. System Goal & Scope

Implement a **Wwise-grade + superior** sample-accurate looping system for FluxForge Middleware that supports:

- Loop region within a single track (WAV / stem / sprite slice)
- Intro + loop from the same file with configurable intro policy
- Multiple cue/marker points (Entry/Exit + Custom cues as sync points)
- Multi-region per asset (A/B/C loop zones) with runtime switching
- Deterministic behavior: same timeline, same events → same wrap timestamps, zero drift
- Web-runtime safe: works on sprites (Howler2 / HTML5 Audio) via dual-voice crossfade
- Native-runtime optimal: single-voice PCM wrap with micro-fade

### What This System Is NOT

- NOT a playlist sequencer (that's `MusicPlaylistContainer` — separate system)
- NOT a music switch container (that's state-driven segment selection — separate system)
- NOT a DAW timeline loop (that's `PlaybackPosition.loop_enabled` in rf-engine — already exists)

This system operates at the **LoopAsset level**: a single audio source with embedded loop metadata, running as a middleware voice instance.

---

## 2. Terminology Lock

These definitions are **canonical** for the entire FluxForge codebase. No deviation.

| Term | Definition | Unit |
|------|-----------|------|
| **Cue** | A named point on an asset's timeline. Sync point for transitions and callbacks. | samples (u64) |
| **Entry Cue** | Mandatory cue marking the logical start of the segment body. Content before this is pre-entry. | samples |
| **Exit Cue** | Mandatory cue marking the logical end of the segment body. Content after this is post-exit. | samples |
| **Custom Cue** | Optional user-defined sync point between Entry and Exit. | samples |
| **Region** | A named interval [inSamples, outSamples) within an asset. Defines a loop zone. | samples |
| **Marker** | Metadata embedded in an audio file (BWF cue chunk, Reaper marker, sidecar JSON). Source data that maps to Cues/Regions during ingest. | samples |
| **LoopAsset** | A complete audio source + its cues + its regions. The authoritative loop configuration object. | — |
| **Loop Instance** | A runtime instantiation of a LoopAsset with its own state machine, playhead, and active region. | — |
| **Pre-Entry Zone** | `[0, Entry Cue)` — audio content before the Entry Cue. May contain pickup notes, reverb build. | samples |
| **Post-Exit Zone** | `(Exit Cue, file_end]` — audio content after the Exit Cue. May contain reverb tail, note release. | samples |
| **Seam** | The boundary between loop-out and loop-in where audio wraps. | — |
| **Micro-Fade** | A 3–10ms cosine fade applied at the seam to prevent clicks. | ms |
| **Intro** | The portion of audio from Entry Cue (or 0) to LoopIn. Not part of the loop body. | samples |

### Units Policy

**All cue/region positions are stored in samples (u64), never milliseconds.**

Conversion to ms is done **only for display** and uses this formula:
```
ms = (samples as f64 / sample_rate as f64) * 1000.0
```

Rounding for display: `floor()` always. Never `round()`, never `ceil()`. This ensures determinism.

Conversion from ms to samples (during import only):
```
samples = (ms * sample_rate as f64 / 1000.0).round() as u64
```

`round()` is acceptable here because import is a one-time operation and the result is locked in samples.

---

## 3. Wwise Behavioral Model

### What We Fully Emulate

| Wwise Feature | FluxForge Equivalent |
|---------------|---------------------|
| Entry Cue / Exit Cue per segment | `cues[].name == "Entry"/"Exit"` in LoopAsset |
| Custom cues as sync points | `customCues[]` in LoopAsset |
| Pre-entry / post-exit overlap | `preEntryZone` / `postExitZone` computed from cue positions |
| Transition sync: Entry Cue, Same Time, Next Bar, Next Beat, Immediate | `sync` field in commands: `EntryCue / SameTime / NextBar / NextBeat / NextCue / Immediate` |
| Play pre-entry / post-exit toggle | `playPreEntry` / `playPostExit` booleans in LoopAsset |
| Fade-in / fade-out on transitions | `fadeInMs` / `fadeOutMs` + curve type |
| Segment self-loop (Entry→Exit→wrap) | Single-region LoopAsset with `mode: HARD` |
| Music callbacks (beat, bar, cue) | `LoopCallback` enum: `Beat / Bar / Entry / Exit / CustomCue / Grid / Wrap` |
| State-driven segment switching | Handled by existing `MusicSwitchContainer` — NOT this system |

### What We Do NOT Emulate (Out of Scope)

| Wwise Feature | Reason |
|---------------|--------|
| Music Playlist Container sequencing | Separate system (playlist orchestrator) |
| Music Switch Container state mapping | Separate system (state machine selector) |
| Transition Segments (dedicated bridge audio) | Phase 2 — not in initial scope |
| Random Cue / Random Position sync | Non-deterministic — conflicts with casino-grade requirements |
| Last Exit Position bookmark | Phase 2 candidate |

### Wwise Gaps We Fix

| Wwise Limitation | FluxForge Solution |
|-----------------|-------------------|
| No first-class loop regions (only Entry/Exit self-loop) | Multi-region per asset with `regions[]` array |
| No intro embedding policy | `wrapPolicy` enum: 4 modes |
| No web-runtime dual-voice loop | Dual-voice crossfade engine for sprite playback |
| Markers not auto-imported from WAV | Sidecar `.ffmarkers.json` + BWF/Reaper importer |
| No built-in loop seam QA | Automated peak discontinuity + click detector |
| Compressed format seek drift (~20ms) | Sample-accurate PCM path enforced for critical loops |

---

## 4. FluxForge Superiority Layer

### 4.1 Multi-Region Per Asset

A single `LoopAsset` can define multiple named loop regions:

```
LoopA: [960000, 47600000) — normal intensity
LoopB: [1920000, 47600000) — high intensity (shorter intro)
LoopC: [960000, 23800000) — fatigue-safe (half length)
```

Runtime switches between regions using `SetLoopRegion` command with quantized sync.

**Why superior:** Wwise requires separate segments for different loop ranges. FluxForge keeps one asset, multiple regions — less memory, simpler authoring, atomic switching.

### 4.2 Intro Embedding Policy (`wrapPolicy`)

| Policy | Behavior | Use Case |
|--------|----------|----------|
| `PLAY_ONCE_THEN_LOOP` | Play [Entry..LoopIn] once, then loop [LoopIn..LoopOut] forever | Music with intro that shouldn't repeat |
| `INCLUDE_IN_LOOP` | Loop entire [LoopIn..LoopOut] including intro range (Entry→LoopIn is skipped) | Ambient loops |
| `SKIP_INTRO` | Start directly at LoopIn, loop [LoopIn..LoopOut] | Quick-start backgrounds |
| `INTRO_ONLY` | Play [Entry..LoopIn] once, then stop | Stingers, teasers, one-shots with tail |

**Why superior:** Wwise has no concept of "intro inside a looping segment" — the entire Entry→Exit range loops. FluxForge separates intro from loop body.

### 4.3 Deterministic Crossfade & Micro-Fade

Every loop seam gets a cosine micro-fade:
- Default: 5ms (240 samples @ 48kHz)
- Configurable: 1–50ms via `seamFadeMs`
- Shape: always **cosine** (equal-power) — no configuration needed, this is mathematically optimal for loop seams

**Crossfade** (for region switches and dual-voice wrap):
- Configurable: 0–5000ms via `crossfadeMs`
- Shape: selectable from `CrossfadeCurve` enum (10 types)
- Applied symmetrically: voice A fades out, voice B fades in

### 4.4 Quantized Loop Points

Optional `quantize` on each region:

| Quantize Type | Behavior |
|---------------|----------|
| `none` | Loop points are exact sample positions |
| `bars` | Snap to nearest bar boundary (requires `barLengthSamples`) |
| `beats` | Snap to nearest beat boundary (requires `beatLengthSamples`) |
| `grid` | Snap to custom grid interval (requires `gridSamples`) |

Quantization is applied **at authoring time** (marker ingest), not runtime. The final sample positions in `LoopAsset` are always exact.

---

## 5. Authoritative Data Model

### 5.1 LoopAsset (Rust struct + JSON serialization)

```rust
/// A complete audio source with embedded loop metadata.
/// This is the Single Source of Truth for all loop behavior.
pub struct LoopAsset {
    /// Unique identifier (e.g., "bgm_base_main")
    pub id: String,

    /// Reference to the audio source
    pub sound_ref: SoundRef,

    /// Timeline metadata (from audio file analysis)
    pub timeline: TimelineInfo,

    /// Mandatory cues: Entry + Exit (always present)
    /// Custom cues: optional sync points
    pub cues: Vec<Cue>,

    /// Loop regions (at least one for a looping asset)
    pub regions: Vec<LoopRegion>,

    /// Pre-entry / post-exit behavior
    pub pre_entry: ZonePolicy,
    pub post_exit: ZonePolicy,
}

pub struct SoundRef {
    /// "file" or "sprite"
    pub source_type: SourceType,
    /// Asset ID in the sound bank / sprite atlas
    pub sound_id: String,
    /// Sprite slice ID (if source_type == Sprite)
    pub sprite_id: Option<String>,
}

pub enum SourceType {
    File,
    Sprite,
}

pub struct TimelineInfo {
    pub sample_rate: u32,
    pub channels: u16,
    pub length_samples: u64,
    /// BPM (optional, for bar/beat quantization)
    pub bpm: Option<f64>,
    /// Beats per bar (optional)
    pub beats_per_bar: Option<u32>,
}

pub struct Cue {
    /// Cue name. "Entry" and "Exit" are reserved.
    pub name: String,
    /// Position in samples from file start
    pub at_samples: u64,
    /// Cue type for fast dispatch
    pub cue_type: CueType,
}

pub enum CueType {
    Entry,
    Exit,
    Custom,
    /// Stinger sync point
    Sync,
    /// Event trigger point
    Event,
}

pub struct LoopRegion {
    /// Region name (e.g., "LoopA", "LoopB")
    pub name: String,
    /// Loop-in point (samples)
    pub in_samples: u64,
    /// Loop-out point (samples)
    pub out_samples: u64,
    /// Loop mode
    pub mode: LoopMode,
    /// Intro handling policy
    pub wrap_policy: WrapPolicy,
    /// Micro-fade at seam (ms)
    pub seam_fade_ms: f32,
    /// Crossfade duration for dual-voice mode (ms)
    pub crossfade_ms: f32,
    /// Crossfade curve shape
    pub crossfade_curve: CrossfadeCurve,
    /// Quantization rule (applied at authoring time)
    pub quantize: Option<Quantize>,
    /// Maximum loop count (None = infinite)
    pub max_loops: Option<u32>,
}

pub enum LoopMode {
    /// Hard wrap: position jumps from out to in
    Hard,
    /// Crossfade wrap: dual-voice overlap at seam
    Crossfade,
}

pub enum WrapPolicy {
    /// Play [Entry..LoopIn] once, then loop [LoopIn..LoopOut]
    PlayOnceThenLoop,
    /// Loop [LoopIn..LoopOut] including content before LoopIn
    IncludeInLoop,
    /// Start at LoopIn, skip intro
    SkipIntro,
    /// Play [Entry..LoopIn] once, then stop
    IntroOnly,
}

pub struct Quantize {
    pub quantize_type: QuantizeType,
    /// Grid unit size in samples
    pub grid_samples: u64,
    /// Snap rule
    pub snap: SnapRule,
}

pub enum QuantizeType {
    Bars,
    Beats,
    Grid,
}

pub enum SnapRule {
    Nearest,
    Floor,
    Ceil,
}

pub struct ZonePolicy {
    /// Whether to play this zone during transitions
    pub enabled: bool,
    /// Fade duration (ms) at zone boundary
    pub fade_ms: f32,
    /// Fade curve
    pub fade_curve: CrossfadeCurve,
}
```

### 5.2 LoopInstance (Runtime State)

```rust
/// Runtime state for an active loop playback.
/// One LoopAsset can have multiple concurrent instances.
pub struct LoopInstance {
    /// Unique instance ID
    pub instance_id: u64,
    /// Reference to the LoopAsset
    pub asset_id: String,
    /// Currently active region name
    pub active_region: String,
    /// Pending region switch (applied at next quantize boundary)
    pub pending_region: Option<PendingRegionSwitch>,
    /// Current state
    pub state: LoopState,
    /// Playhead position (samples from file start)
    pub playhead_samples: u64,
    /// Number of completed loop iterations
    pub loop_count: u32,
    /// Sample position of last wrap event
    pub last_wrap_at_samples: u64,
    /// Current gain (0.0–1.0)
    pub gain: f32,
    /// Target gain for fade (if fading)
    pub target_gain: f32,
    /// Fade increment per sample
    pub fade_increment: f32,
    /// Voice A ID (for dual-voice mode)
    pub voice_a: Option<u64>,
    /// Voice B ID (for dual-voice mode, armed or active)
    pub voice_b: Option<u64>,
    /// Bus routing
    pub output_bus: OutputBus,
}

pub enum LoopState {
    /// Playing intro (Entry→LoopIn or 0→LoopIn)
    Intro,
    /// Looping body (LoopIn→LoopOut→wrap)
    Looping,
    /// Exiting: playing to Exit Cue or fade-out in progress
    Exiting,
    /// Fully stopped, instance can be reclaimed
    Stopped,
}

pub struct PendingRegionSwitch {
    pub target_region: String,
    pub sync: SyncMode,
    pub crossfade_ms: f32,
    pub crossfade_curve: CrossfadeCurve,
}

pub enum SyncMode {
    /// Switch at the next quantize bar boundary
    NextBar,
    /// Switch at the next quantize beat boundary
    NextBeat,
    /// Switch at the next custom cue
    NextCue,
    /// Switch immediately with crossfade
    Immediate,
    /// Switch at the Exit Cue of current region
    ExitCue,
    /// Switch when reaching LoopOut (natural wrap point)
    OnWrap,
    /// Sync to destination Entry Cue
    EntryCue,
    /// Start destination at same relative position
    SameTime,
}
```

### 5.3 JSON Serialization Format

```json
{
  "id": "bgm_base_main",
  "soundRef": {
    "sourceType": "sprite",
    "soundId": "base_audioSprite1",
    "spriteId": "BaseMusicLoop"
  },
  "timeline": {
    "sampleRate": 48000,
    "channels": 2,
    "lengthSamples": 48765432,
    "bpm": 120.0,
    "beatsPerBar": 4
  },
  "cues": [
    { "name": "Entry", "atSamples": 0, "cueType": "Entry" },
    { "name": "Exit", "atSamples": 48765432, "cueType": "Exit" }
  ],
  "regions": [
    {
      "name": "LoopA",
      "inSamples": 960000,
      "outSamples": 47600000,
      "mode": "Hard",
      "wrapPolicy": "PlayOnceThenLoop",
      "seamFadeMs": 5.0,
      "crossfadeMs": 50.0,
      "crossfadeCurve": "EqualPower",
      "quantize": {
        "quantizeType": "Bars",
        "gridSamples": 96000,
        "snap": "Nearest"
      },
      "maxLoops": null
    }
  ],
  "customCues": [
    { "name": "A", "atSamples": 960000, "cueType": "Custom" },
    { "name": "B", "atSamples": 1920000, "cueType": "Custom" },
    { "name": "Hit", "atSamples": 4800000, "cueType": "Event" }
  ],
  "preEntry": {
    "enabled": true,
    "fadeMs": 100.0,
    "fadeCurve": "EqualPower"
  },
  "postExit": {
    "enabled": true,
    "fadeMs": 500.0,
    "fadeCurve": "Linear"
  }
}
```

---

## 6. Runtime State Machine

### 6.1 State Transitions

```
                    PlayLoop
                       │
                       ▼
    ┌──────────────────────────────────────┐
    │          INTRO                       │
    │  (Entry → LoopIn)                    │
    │  wrapPolicy controls behavior        │
    ├──────────────────────────────────────┤
    │  PLAY_ONCE_THEN_LOOP → LOOPING       │
    │  INCLUDE_IN_LOOP     → LOOPING       │
    │  SKIP_INTRO          → (skip) LOOPING│
    │  INTRO_ONLY          → STOPPED       │
    └──────────┬───────────────────────────┘
               │
               ▼
    ┌──────────────────────────────────────┐
    │          LOOPING                     │
    │  [LoopIn → LoopOut → wrap → LoopIn]  │
    │                                      │
    │  On wrap:                            │
    │    loop_count++                      │
    │    if max_loops && loop_count >= max  │
    │      → EXITING                       │
    │    else                              │
    │      → wrap to LoopIn               │
    │                                      │
    │  On SetLoopRegion:                   │
    │    pending_region = target           │
    │    apply at next sync boundary       │
    │                                      │
    │  On ExitLoop:                        │
    │    → EXITING                         │
    └──────────┬───────────────────────────┘
               │ ExitLoop / max_loops reached
               ▼
    ┌──────────────────────────────────────┐
    │          EXITING                     │
    │  Behavior depends on sync mode:      │
    │                                      │
    │  ExitCue: play until Exit Cue        │
    │  Immediate: fade out now             │
    │  NextBar: play until next bar        │
    │  OnWrap: play until next LoopOut     │
    │                                      │
    │  If postExit.enabled:                │
    │    play post-exit zone with fade      │
    │                                      │
    │  When fade complete or zone end:     │
    │    → STOPPED                         │
    └──────────┬───────────────────────────┘
               │
               ▼
    ┌──────────────────────────────────────┐
    │          STOPPED                     │
    │  Instance reclaimable.               │
    │  Voice(s) released to pool.          │
    └──────────────────────────────────────┘
```

### 6.2 State Invariants (MUST hold at all times)

1. `playhead_samples` is ALWAYS in range `[0, timeline.length_samples)`
2. If `state == LOOPING`, then `playhead_samples` is in `[active_region.in_samples, active_region.out_samples)`
3. If `state == INTRO`, then `playhead_samples` is in `[entry_cue, active_region.in_samples)`
4. `voice_a` is ALWAYS valid (non-None) when `state != STOPPED`
5. `voice_b` is only non-None during dual-voice crossfade wrap or region switch
6. `loop_count` increments **exactly once per wrap**, at the **exact sample** of LoopOut
7. `pending_region` is cleared **atomically** at the moment the switch executes

---

## 7. Engine Implementation (Rust)

### 7.1 Where This Lives

```
crates/rf-engine/src/
  loop_asset.rs          — LoopAsset, LoopRegion, Cue structs + validation
  loop_instance.rs       — LoopInstance, LoopState, state machine logic
  loop_manager.rs        — LoopInstanceManager (owns all active instances)
  loop_process.rs        — Audio processing: wrap, crossfade, micro-fade

crates/rf-bridge/src/
  loop_ffi.rs            — FFI exports (~30 functions)

flutter_ui/lib/
  models/loop_asset_models.dart    — Dart mirrors of Rust structs
  providers/loop_provider.dart      — LoopProvider (GetIt Layer 6.x)
```

### 7.2 Audio Thread Contract (SACRED — Non-Negotiable)

The loop processing runs inside the audio callback. These rules are ABSOLUTE:

```rust
// ❌ FORBIDDEN in loop_process.rs:
//    - Vec::new(), vec![], String::new(), format!()
//    - HashMap, BTreeMap, any heap allocation
//    - Mutex, RwLock, lock(), read(), write()
//    - panic!(), unwrap() without SAFETY proof
//    - log::warn!(), println!(), any I/O
//    - Box::new(), Arc::new() in hot path

// ✅ REQUIRED:
//    - Pre-allocated buffers (sized at init)
//    - AtomicU64/AtomicBool for state flags
//    - Stack-only computation
//    - rtrb::RingBuffer for command receipt
//    - #[cold] on error paths
```

### 7.3 LoopInstanceManager

```rust
pub struct LoopInstanceManager {
    /// Pre-allocated instance pool (no runtime allocation)
    instances: [Option<LoopInstance>; MAX_LOOP_INSTANCES],
    /// Asset registry (loaded at init, read-only during processing)
    assets: HashMap<String, Arc<LoopAsset>>,
    /// Command queue (UI thread → audio thread)
    command_rx: rtrb::Consumer<LoopCommand>,
    /// Callback queue (audio thread → UI thread)
    callback_tx: rtrb::Producer<LoopCallback>,
    /// Next instance ID (monotonic counter)
    next_instance_id: AtomicU64,
}

const MAX_LOOP_INSTANCES: usize = 32;
```

### 7.4 Process Block

```rust
impl LoopInstanceManager {
    /// Called from audio thread per buffer.
    /// output: interleaved f32 buffer, channels = 2
    /// frames: number of frames in this buffer
    pub fn process(&mut self, output: &mut [f32], frames: usize, sample_rate: u32) {
        // 1. Drain command queue (non-blocking)
        self.process_commands();

        // 2. Process each active instance
        for slot in self.instances.iter_mut() {
            if let Some(ref mut inst) = slot {
                if inst.state == LoopState::Stopped {
                    *slot = None; // Reclaim
                    continue;
                }
                self.process_instance(inst, output, frames, sample_rate);
            }
        }
    }
}
```

---

## 8. Dual-Voice Crossfade Loop (Web-Safe)

### 8.1 Problem Statement

Web audio APIs (Howler.js, HTML5 Audio, Web Audio API) cannot seek with sample accuracy. Decode granularity varies by codec and browser. A single-voice "seek to LoopIn on LoopOut" produces:

- ±5–50ms position error (browser-dependent)
- Audible click at the seam
- Cumulative drift over multiple iterations

### 8.2 Algorithm

```
Time →  ...........LoopOut-preRoll...........LoopOut...........

Voice A: ████████████████████████████████████▓▓▓▓▓(fade out)
Voice B:                               ▓▓▓▓▓████████████████████
                                       ↑
                                   B starts at LoopIn
                                   pre-rolled by crossfadeMs

After crossfade completes:
  Voice A → released to pool
  Voice B → becomes new Voice A
  System is ready for next iteration
```

**Steps:**

1. **Arm Phase**: When Voice A's playhead reaches `LoopOut - crossfadeMs - armMarginMs`:
   - Start Voice B at position `LoopIn` with gain 0.0
   - Set B's target gain to `inst.gain`
   - Set A's target gain to 0.0
   - Both fade over `crossfadeMs` duration

2. **Crossfade Phase**: Both voices play simultaneously.
   - A: `gain = inst.gain * crossfade_curve(1.0 - t)` where t = 0→1 over crossfadeMs
   - B: `gain = inst.gain * crossfade_curve(t)`
   - Both gains are computed per-sample for smoothness

3. **Swap Phase**: When crossfade completes (t >= 1.0):
   - Release Voice A to pool
   - Voice B becomes Voice A
   - Increment `loop_count`
   - Send `LoopCallback::Wrap` to UI thread

4. **Arm Margin**: `armMarginMs = 50ms` (fixed). This accounts for web audio scheduling latency. Voice B is started early enough that it's decoded and buffered before the crossfade begins.

### 8.3 Determinism in Dual-Voice Mode

The crossfade timing is computed in **samples**, not wall-clock time:

```rust
let crossfade_samples = (crossfade_ms * sample_rate as f32 / 1000.0) as u64;
let arm_sample = loop_out - crossfade_samples - arm_margin_samples;
```

The arm trigger is checked per-frame in the process block. No timers, no callbacks, no async.

### 8.4 Voice Pool Integration

Dual-voice mode temporarily uses 2 voices from the `music` pool. The pool must have capacity for `MAX_LOOP_INSTANCES * 2` voices during peak crossfade overlap.

If the pool is exhausted during arm phase:
- **Fallback**: Skip crossfade, do hard wrap with micro-fade only
- **Log**: Send `LoopCallback::VoiceStealWarning` to UI thread

---

## 9. Single-Voice PCM Wrap (Native)

### 9.1 When to Use

This mode is used when FluxForge has direct PCM buffer access (native playback via rf-engine, offline render, WASM with AudioWorklet).

### 9.2 Algorithm

```rust
fn process_single_voice_wrap(
    inst: &mut LoopInstance,
    audio: &ImportedAudio,
    region: &LoopRegion,
    output: &mut [f32],
    frames: usize,
) {
    let fade_samples = (region.seam_fade_ms * audio.sample_rate as f32 / 1000.0) as u64;

    for frame in 0..frames {
        let pos = inst.playhead_samples;

        // Check for wrap
        if pos >= region.out_samples {
            inst.playhead_samples = region.in_samples + (pos - region.out_samples);
            inst.loop_count += 1;
            inst.last_wrap_at_samples = pos;
            // Send callback (non-blocking)
        }

        // Read sample from audio buffer
        let sample_l = audio.get_sample(0, inst.playhead_samples);
        let sample_r = audio.get_sample(1, inst.playhead_samples);

        // Apply micro-fade at seam boundaries
        let fade_gain = compute_seam_fade(
            inst.playhead_samples,
            region.in_samples,
            region.out_samples,
            fade_samples,
        );

        output[frame * 2]     += sample_l * inst.gain * fade_gain;
        output[frame * 2 + 1] += sample_r * inst.gain * fade_gain;

        inst.playhead_samples += 1;
    }
}

/// Cosine micro-fade at loop boundaries.
/// Fades OUT approaching LoopOut, fades IN after LoopIn.
fn compute_seam_fade(pos: u64, loop_in: u64, loop_out: u64, fade_len: u64) -> f32 {
    // Fade out: [loop_out - fade_len, loop_out)
    if pos >= loop_out - fade_len && pos < loop_out {
        let t = (loop_out - pos) as f32 / fade_len as f32;
        return 0.5 * (1.0 + (t * std::f32::consts::PI).cos()); // cosine fade
    }
    // Fade in: [loop_in, loop_in + fade_len)
    if pos >= loop_in && pos < loop_in + fade_len {
        let t = (pos - loop_in) as f32 / fade_len as f32;
        return 0.5 * (1.0 - (t * std::f32::consts::PI).cos()); // cosine fade
    }
    1.0
}
```

### 9.3 Edge Case: Fade Length > Region Length

If `seam_fade_ms` converts to more samples than `(out_samples - in_samples) / 2`:
- **Clamp** to half the region length
- **Warn** at authoring time (validation error)

---

## 10. Region Switch Without Restart

### 10.1 Algorithm

When `SetLoopRegion("LoopB")` is received:

```
Current state  │ Behavior
───────────────┼──────────────────────────────────────────────
INTRO          │ Complete intro, use LoopB for first loop iteration
LOOPING        │ Set pending_region, apply at next sync boundary
EXITING        │ Ignore (already exiting)
STOPPED        │ Ignore
```

### 10.2 Sync Boundary Resolution

```rust
fn resolve_sync_boundary(
    playhead: u64,
    sync: SyncMode,
    region: &LoopRegion,
    asset: &LoopAsset,
) -> u64 {
    match sync {
        SyncMode::Immediate => playhead,
        SyncMode::OnWrap => region.out_samples,
        SyncMode::NextBar => {
            let grid = region.quantize.as_ref()
                .map(|q| q.grid_samples)
                .unwrap_or(region.out_samples - region.in_samples);
            let next = ((playhead / grid) + 1) * grid;
            next.min(region.out_samples)
        }
        SyncMode::NextBeat => {
            let beat_samples = asset.timeline.bpm
                .map(|bpm| (asset.timeline.sample_rate as f64 * 60.0 / bpm) as u64)
                .unwrap_or(region.out_samples - region.in_samples);
            let next = ((playhead / beat_samples) + 1) * beat_samples;
            next.min(region.out_samples)
        }
        SyncMode::NextCue => {
            // Find nearest custom cue after playhead
            asset.cues.iter()
                .filter(|c| c.cue_type == CueType::Custom && c.at_samples > playhead)
                .map(|c| c.at_samples)
                .min()
                .unwrap_or(region.out_samples)
        }
        SyncMode::ExitCue => {
            asset.cues.iter()
                .find(|c| c.cue_type == CueType::Exit)
                .map(|c| c.at_samples)
                .unwrap_or(region.out_samples)
        }
        SyncMode::EntryCue => {
            // For destination sync — start at entry
            asset.cues.iter()
                .find(|c| c.cue_type == CueType::Entry)
                .map(|c| c.at_samples)
                .unwrap_or(0)
        }
        SyncMode::SameTime => {
            // Map current relative position to new region
            let old_len = region.out_samples - region.in_samples;
            let rel = (playhead - region.in_samples) % old_len;
            // Will be applied to new region: new_in + rel
            rel // Caller adds new_region.in_samples
        }
    }
}
```

### 10.3 Crossfade During Region Switch

When switching regions with `crossfadeMs > 0`:

1. Arm Voice B at the new region's position (resolved via sync)
2. Crossfade from Voice A (old region) to Voice B (new region)
3. On crossfade completion, release Voice A

This reuses the dual-voice crossfade mechanism from Section 8.

---

## 11. Transitions & Pre-Entry / Post-Exit

### 11.1 Pre-Entry Zone

```
File:   [pre-entry......Entry.................Exit......post-exit]
                         ↑                     ↑
                     Entry Cue             Exit Cue

preEntryZone = [0, Entry Cue)
postExitZone = (Exit Cue, length_samples]
```

### 11.2 Transition Playback

When transitioning FROM this asset (ExitLoop):

1. If `postExit.enabled`: continue playing past Exit Cue, apply `postExit.fade_ms` fade-out
2. If `!postExit.enabled`: hard stop at Exit Cue (with micro-fade only)

When transitioning TO this asset (PlayLoop with pre-entry):

1. If `preEntry.enabled`: start playback at sample 0, fade in over `preEntry.fade_ms`
2. If `!preEntry.enabled`: start playback at Entry Cue

### 11.3 Dovetailing

When one loop asset exits and another enters simultaneously:

```
Asset A (exiting):  ........Exit──────post-exit fade──────────silence
Asset B (entering): silence──────pre-entry fade──────Entry........

Overlap:                              ↕↕↕↕↕↕↕↕↕↕↕↕
                                   (both playing, gains cross)
```

The overlap is managed by the `LoopInstanceManager` — both instances exist simultaneously during the crossfade. No special coordination needed beyond the standard state machine.

---

## 12. Marker Ingest Pipeline

### 12.1 Sidecar Format (`.ffmarkers.json`)

Primary format. Deterministic, portable, no DAW dependency.

```json
{
  "file": "BaseMusic.wav",
  "sampleRate": 48000,
  "markers": [
    { "type": "ENTRY",    "name": "Entry",  "atSamples": 0 },
    { "type": "LOOP_IN",  "name": "LoopIn", "atSamples": 960000 },
    { "type": "LOOP_OUT", "name": "LoopOut","atSamples": 47600000 },
    { "type": "EXIT",     "name": "Exit",   "atSamples": 48765432 },
    { "type": "CUE",      "name": "A",      "atSamples": 960000 },
    { "type": "CUE",      "name": "B",      "atSamples": 1920000 },
    { "type": "EVENT",    "name": "Hit",    "atSamples": 4800000 },
    { "type": "SYNC",     "name": "Sync1",  "atSamples": 2880000 }
  ]
}
```

### 12.2 BWF Cue Chunk Import

Reads RIFF `cue ` chunk + `LIST/adtl` labels from WAV files:

```rust
pub fn import_bwf_markers(wav_path: &Path) -> Result<Vec<RawMarker>, MarkerError> {
    // 1. Parse RIFF structure
    // 2. Find 'cue ' chunk → extract sample positions + IDs
    // 3. Find 'LIST'/'adtl' chunk → extract label names for IDs
    // 4. Return RawMarker vec
}
```

### 12.3 Reaper Marker Import

Reads `.RPP` project file or `.csv` marker export:

```rust
pub fn import_reaper_markers(rpp_path: &Path) -> Result<Vec<RawMarker>, MarkerError> {
    // Parse MARKER lines from RPP
    // Convert position (seconds) to samples using file sample rate
}
```

### 12.4 Marker → LoopAsset Mapping

```rust
pub fn markers_to_loop_asset(
    markers: &[RawMarker],
    audio_info: &AudioFileInfo,
    config: &IngestConfig,
) -> Result<LoopAsset, MarkerError> {
    // 1. Find ENTRY marker (by name or fallback to 0)
    // 2. Find EXIT marker (by name or fallback to file end)
    // 3. Find LOOP_IN / LOOP_OUT pairs → create regions
    // 4. Find CUE/EVENT/SYNC markers → create custom cues
    // 5. Apply quantization if config specifies
    // 6. Validate (Section 15)
    // 7. Return canonical LoopAsset
}
```

### 12.5 Name Matching Rules

| Marker Name Pattern | Maps To |
|--------------------|---------|
| `Entry`, `ENTRY`, `entry`, `Start` | `CueType::Entry` |
| `Exit`, `EXIT`, `exit`, `End` | `CueType::Exit` |
| `LoopIn`, `LOOP_IN`, `Loop_Start`, `LOOP_A_IN` | `LoopRegion.in_samples` |
| `LoopOut`, `LOOP_OUT`, `Loop_End`, `LOOP_A_OUT` | `LoopRegion.out_samples` |
| `LoopB_In`, `LOOP_B_IN` | Second `LoopRegion` |
| Anything else | `CueType::Custom` |

### 12.6 Fallback Rules

| Missing Marker | Fallback |
|----------------|----------|
| No Entry | `Entry = 0` |
| No Exit | `Exit = length_samples` |
| No LoopIn | `LoopIn = Entry` |
| No LoopOut | `LoopOut = Exit` |
| No sample rate in sidecar | Read from WAV header |

---

## 13. Command API

### 13.1 LoopCommand Enum (Sent via rtrb queue)

```rust
pub enum LoopCommand {
    /// Start a new loop instance
    Play {
        asset_id: String,
        region: String,
        volume: f32,
        bus: OutputBus,
        use_dual_voice: bool,
        play_pre_entry: Option<bool>,
        fade_in_ms: Option<f32>,
    },
    /// Switch active region
    SetRegion {
        instance_id: u64,
        region: String,
        sync: SyncMode,
        crossfade_ms: f32,
        crossfade_curve: CrossfadeCurve,
    },
    /// Begin exit sequence
    Exit {
        instance_id: u64,
        sync: SyncMode,
        fade_out_ms: f32,
        play_post_exit: Option<bool>,
    },
    /// Hard stop (optional fade)
    Stop {
        instance_id: u64,
        fade_out_ms: f32,
    },
    /// Seek to position (debug/QA only)
    Seek {
        instance_id: u64,
        position_samples: u64,
    },
    /// Set volume
    SetVolume {
        instance_id: u64,
        volume: f32,
        fade_ms: f32,
    },
    /// Set bus routing
    SetBus {
        instance_id: u64,
        bus: OutputBus,
    },
}
```

### 13.2 LoopCallback Enum (Audio thread → UI thread)

```rust
pub enum LoopCallback {
    /// Loop instance started playing
    Started { instance_id: u64, asset_id: String },
    /// State changed
    StateChanged { instance_id: u64, new_state: LoopState },
    /// Loop wrapped (LoopOut → LoopIn)
    Wrap { instance_id: u64, loop_count: u32, at_samples: u64 },
    /// Region switched
    RegionSwitched { instance_id: u64, from: String, to: String },
    /// Custom cue hit
    CueHit { instance_id: u64, cue_name: String, at_samples: u64 },
    /// Instance stopped
    Stopped { instance_id: u64 },
    /// Voice pool warning
    VoiceStealWarning { instance_id: u64 },
    /// Drift detected (dev builds only)
    DriftWarning { instance_id: u64, expected_samples: u64, actual_samples: u64 },
}
```

### 13.3 Middleware JSON Command Format

```json
{
  "onBaseGameSpinStart": [
    {
      "command": "PlayLoop",
      "loopAssetId": "bgm_base_main",
      "region": "LoopA",
      "volume": 1.0,
      "bus": "music",
      "dualVoice": true,
      "playPreEntry": false,
      "fadeInMs": 0
    }
  ],
  "onIntensityUp": [
    {
      "command": "SetLoopRegion",
      "instanceRef": "bgm_base_main",
      "region": "LoopB",
      "sync": "NextBar",
      "crossfadeMs": 1000,
      "crossfadeCurve": "EqualPower"
    }
  ],
  "onBaseToBonusStart": [
    {
      "command": "ExitLoop",
      "instanceRef": "bgm_base_main",
      "sync": "ExitCue",
      "fadeOutMs": 3000,
      "playPostExit": true
    },
    {
      "command": "PlayLoop",
      "loopAssetId": "bgm_bonus_main",
      "region": "LoopA",
      "volume": 1.0,
      "bus": "music",
      "playPreEntry": true,
      "fadeInMs": 3000
    }
  ]
}
```

---

## 14. Authoring UI/UX

### 14.1 Loop Editor Panel

```
┌──────────────────────────────────────────────────────────────┐
│  LOOP EDITOR — bgm_base_main                    [⚙] [?]    │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─ Time Ruler ──────────────────────────────────────────┐  │
│  │ 0:00    0:05    0:10    0:15    0:20    0:25    0:30  │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌─ Waveform ────────────────────────────────────────────┐  │
│  │ ▁▂▃▅▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇▅▃▂▁▂▃▅▇█▇▅▃▂▁▂▃▅▇▅▃▂▁    │  │
│  │ ▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔  │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌─ Cues Lane ───────────────────────────────────────────┐  │
│  │ ▼Entry          ▼A      ▼B                    ▼Exit  │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌─ Regions Lane ────────────────────────────────────────┐  │
│  │     ╠══════════════ LoopA ══════════════╣             │  │
│  │         ╠═══════ LoopB ═══════╣                       │  │
│  │     ╠═══ LoopC ═══╣                                   │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌─ Events Lane ─────────────────────────────────────────┐  │
│  │                        ★Hit                           │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                              │
├─ Inspector ──────────────────────────────────────────────────┤
│  Selected: LoopA                                             │
│  In:  960000 samples (20.000 ms)    [samples ▼] [snap: bar] │
│  Out: 47600000 samples (991.667 ms) [samples ▼] [snap: bar] │
│  Mode: Hard ▼    WrapPolicy: PlayOnceThenLoop ▼             │
│  SeamFade: 5ms   CrossfadeMs: 50ms                          │
│  CrossfadeCurve: EqualPower ▼                                │
│  MaxLoops: ∞ ▼   Quantize: Bars (96000 samples)             │
│                                                              │
│  [▶ Preview Loop]  [▶ Preview Intro+Loop]  [⟳ Reset]        │
└──────────────────────────────────────────────────────────────┘
```

### 14.2 Visual Conventions

| Element | Color | Interaction |
|---------|-------|------------|
| Pre-entry zone | `#2A3A4A` (dark blue overlay) | Click to toggle `playPreEntry` |
| Loop body | `#1A4A2A` (dark green overlay) | — |
| Intro (Entry→LoopIn) | `#4A3A1A` (amber overlay) | Shows only when wrapPolicy != SkipIntro |
| Post-exit zone | `#4A2A2A` (dark red overlay) | Click to toggle `playPostExit` |
| Entry cue | Green triangle ▼ | Drag to reposition |
| Exit cue | Red triangle ▼ | Drag to reposition |
| Custom cue | Blue triangle ▼ | Drag, right-click to rename/delete |
| LoopIn handle | Green bracket ╠ | Drag horizontally, snaps to grid |
| LoopOut handle | Red bracket ╣ | Drag horizontally, snaps to grid |

### 14.3 Grid Options

| Grid Mode | Display |
|-----------|---------|
| Samples | Raw sample numbers (e.g., 960000) |
| Time (ms) | Milliseconds (e.g., 20.000 ms) |
| Time (s) | Seconds (e.g., 0.020 s) |
| Bars:Beats | Musical grid (e.g., 1:1.000) — requires BPM |

### 14.4 Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Space` | Toggle playback preview |
| `L` | Set LoopIn at playhead |
| `Shift+L` | Set LoopOut at playhead |
| `E` | Set Entry Cue at playhead |
| `Shift+E` | Set Exit Cue at playhead |
| `M` | Add custom cue at playhead |
| `Delete` | Remove selected cue/region |
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z` | Redo |
| `G` | Toggle grid snap |
| `+/-` | Zoom in/out |
| `Home` | Jump to Entry Cue |
| `End` | Jump to Exit Cue |
| `1-9` | Jump to Custom Cue 1-9 |

---

## 15. Validation & Fail-Fast

### 15.1 Build-Time Validation (Authoring)

These errors MUST be caught at save/export time. No invalid LoopAsset can enter the runtime.

```rust
pub fn validate_loop_asset(asset: &LoopAsset) -> Result<(), Vec<ValidationError>> {
    let mut errors = Vec::new();

    // V-01: Entry and Exit cues must exist
    if !asset.cues.iter().any(|c| c.cue_type == CueType::Entry) {
        errors.push(V01_MissingEntryCue);
    }
    if !asset.cues.iter().any(|c| c.cue_type == CueType::Exit) {
        errors.push(V02_MissingExitCue);
    }

    // V-03: Entry must be before Exit
    let entry = asset.entry_samples();
    let exit = asset.exit_samples();
    if entry >= exit {
        errors.push(V03_EntryNotBeforeExit { entry, exit });
    }

    // V-04: All cues in [0, length)
    for cue in &asset.cues {
        if cue.at_samples >= asset.timeline.length_samples {
            errors.push(V04_CueOutOfBounds { name: cue.name.clone(), at: cue.at_samples });
        }
    }

    // V-05: Region bounds
    for region in &asset.regions {
        if region.in_samples >= region.out_samples {
            errors.push(V05_RegionInNotBeforeOut { name: region.name.clone() });
        }
        if region.out_samples > asset.timeline.length_samples {
            errors.push(V06_RegionOutOfBounds { name: region.name.clone() });
        }
        if region.in_samples < entry && region.wrap_policy == WrapPolicy::SkipIntro {
            errors.push(V07_SkipIntroButLoopInBeforeEntry { name: region.name.clone() });
        }
    }

    // V-08: SeamFade sanity
    for region in &asset.regions {
        let region_samples = region.out_samples - region.in_samples;
        let fade_samples = (region.seam_fade_ms * asset.timeline.sample_rate as f32 / 1000.0) as u64;
        if fade_samples * 2 > region_samples {
            errors.push(V08_SeamFadeTooLong {
                name: region.name.clone(),
                fade_ms: region.seam_fade_ms,
                region_ms: region_samples as f64 / asset.timeline.sample_rate as f64 * 1000.0,
            });
        }
    }

    // V-09: SeamFade > 100ms requires explicit override
    for region in &asset.regions {
        if region.seam_fade_ms > 100.0 {
            errors.push(V09_SeamFadeExcessive { name: region.name.clone(), fade_ms: region.seam_fade_ms });
        }
    }

    // V-10: Quantize grid must be non-zero
    for region in &asset.regions {
        if let Some(ref q) = region.quantize {
            if q.grid_samples == 0 {
                errors.push(V10_QuantizeGridZero { name: region.name.clone() });
            }
        }
    }

    // V-11: Unique region names
    let mut seen = HashSet::new();
    for region in &asset.regions {
        if !seen.insert(&region.name) {
            errors.push(V11_DuplicateRegionName { name: region.name.clone() });
        }
    }

    // V-12: Unique cue names
    let mut cue_seen = HashSet::new();
    for cue in &asset.cues {
        if !cue_seen.insert(&cue.name) {
            errors.push(V12_DuplicateCueName { name: cue.name.clone() });
        }
    }

    // V-13: Custom cues must be between Entry and Exit
    for cue in &asset.cues {
        if cue.cue_type == CueType::Custom {
            if cue.at_samples < entry || cue.at_samples > exit {
                errors.push(V13_CustomCueOutsideBody { name: cue.name.clone() });
            }
        }
    }

    // V-14: At least one region if this is a looping asset
    // (non-looping assets like stingers may have 0 regions — that's valid)

    // V-15: CrossfadeMs must be <= half the region length
    for region in &asset.regions {
        let region_ms = (region.out_samples - region.in_samples) as f64
            / asset.timeline.sample_rate as f64 * 1000.0;
        if region.crossfade_ms as f64 > region_ms / 2.0 {
            errors.push(V15_CrossfadeTooLong {
                name: region.name.clone(),
                crossfade_ms: region.crossfade_ms,
                region_ms: region_ms,
            });
        }
    }

    // V-16: Sample rate must match audio file
    // (validated at ingest time, not stored separately)

    if errors.is_empty() { Ok(()) } else { Err(errors) }
}
```

### 15.2 Runtime Assertions (Dev Builds Only)

```rust
#[cfg(debug_assertions)]
fn assert_loop_invariants(inst: &LoopInstance, asset: &LoopAsset) {
    // R-01: Playhead in bounds
    debug_assert!(inst.playhead_samples < asset.timeline.length_samples,
        "Playhead {} out of bounds (length {})", inst.playhead_samples, asset.timeline.length_samples);

    // R-02: Active region exists
    debug_assert!(asset.regions.iter().any(|r| r.name == inst.active_region),
        "Active region '{}' not found in asset", inst.active_region);

    // R-03: Looping state implies playhead in region
    if inst.state == LoopState::Looping {
        let region = asset.region_by_name(&inst.active_region).unwrap();
        debug_assert!(inst.playhead_samples >= region.in_samples
            && inst.playhead_samples < region.out_samples,
            "LOOPING but playhead {} not in region [{}, {})",
            inst.playhead_samples, region.in_samples, region.out_samples);
    }

    // R-04: Drift detection
    if inst.loop_count > 0 {
        let region = asset.region_by_name(&inst.active_region).unwrap();
        let expected_wrap = region.out_samples;
        let drift = inst.last_wrap_at_samples.abs_diff(expected_wrap);
        debug_assert!(drift <= 1,
            "Drift detected: expected wrap at {}, actual at {}, drift {} samples",
            expected_wrap, inst.last_wrap_at_samples, drift);
    }

    // R-05: No double-start
    debug_assert!(!(inst.voice_a.is_some() && inst.voice_b.is_some()
        && inst.state != LoopState::Looping),
        "Two voices active outside of crossfade wrap");
}
```

---

## 16. QA Test Harness

### 16.1 Automated Tests (Rust `#[test]`)

```rust
// T-01: Intro + Loop (no overlap, no gap)
#[test]
fn test_intro_then_loop_seamless() {
    // Create asset with Entry=0, LoopIn=96000, LoopOut=960000, Exit=960000
    // WrapPolicy::PlayOnceThenLoop
    // Process 20 seconds of audio
    // Assert: intro plays once, then continuous looping
    // Assert: no silence gap at intro→loop transition
    // Assert: no overlap at intro→loop transition
    // Assert: loop_count increments correctly
}

// T-02: Include-in-loop (full file loops)
#[test]
fn test_include_in_loop_no_restart_click() {
    // WrapPolicy::IncludeInLoop
    // Assert: continuous playback from LoopIn→LoopOut→LoopIn
    // Assert: no click at wrap point (micro-fade active)
    // Assert: no restart from Entry
}

// T-03: Region switch on next bar
#[test]
fn test_region_switch_next_bar_no_desync() {
    // Two regions: LoopA and LoopB
    // SetRegion("LoopB", NextBar) mid-playback
    // Assert: switch happens exactly at bar boundary
    // Assert: no silence during switch
    // Assert: playhead is valid in new region
}

// T-04: ExitLoop with post-exit tail
#[test]
fn test_exit_loop_post_exit_fade() {
    // ExitLoop with sync=ExitCue, postExit enabled
    // Assert: plays to Exit Cue
    // Assert: post-exit zone plays with fade
    // Assert: state transitions LOOPING→EXITING→STOPPED
}

// T-05: Dual-voice crossfade loop
#[test]
fn test_dual_voice_crossfade_no_click() {
    // Process with dual-voice mode
    // Assert: peak discontinuity at wrap < 0.01 (no click)
    // Assert: RMS level stable through crossfade
    // Assert: voice count never exceeds 2
}

// T-06: Determinism test
#[test]
fn test_determinism_10_runs() {
    // Run same LoopAsset with same commands 10 times
    // Assert: all 10 output buffers are bit-identical
    // Assert: all wrap timestamps are identical
    // Assert: all callback sequences are identical
}

// T-07: Seam analyzer (peak discontinuity)
#[test]
fn test_seam_peak_discontinuity() {
    // Process loop with micro-fade
    // At wrap point, measure sample-to-sample difference
    // Assert: max discontinuity < threshold (e.g., 0.01)
}

// T-08: Marker ingest (sidecar)
#[test]
fn test_sidecar_marker_ingest() {
    // Parse .ffmarkers.json → LoopAsset
    // Assert: Entry/Exit mapped correctly
    // Assert: LOOP_IN/LOOP_OUT → region
    // Assert: CUE → customCues
}

// T-09: Marker ingest (BWF cue chunk)
#[test]
fn test_bwf_cue_chunk_import() {
    // Parse WAV with cue chunk → RawMarkers → LoopAsset
    // Assert: positions match expected samples
}

// T-10: Validation errors
#[test]
fn test_validation_catches_all_errors() {
    // Test each V-01 through V-16 validation
    // Assert: correct error variant for each case
}

// T-11: Skip intro policy
#[test]
fn test_skip_intro_starts_at_loop_in() {
    // WrapPolicy::SkipIntro
    // Assert: first sample rendered is at LoopIn, not Entry
}

// T-12: Intro-only policy
#[test]
fn test_intro_only_stops_at_loop_in() {
    // WrapPolicy::IntroOnly
    // Assert: plays [Entry, LoopIn) then stops
    // Assert: state = STOPPED after intro
}

// T-13: Max loops
#[test]
fn test_max_loops_exits_after_n() {
    // MaxLoops = 3
    // Assert: plays intro, then exactly 3 loop iterations, then exits
}

// T-14: Region switch during intro
#[test]
fn test_region_switch_during_intro() {
    // SetRegion("LoopB") while in INTRO state
    // Assert: intro completes, then LoopB is used (not LoopA)
}

// T-15: Concurrent instances
#[test]
fn test_concurrent_loop_instances() {
    // Play 4 different LoopAssets simultaneously
    // Assert: all loop correctly, no cross-contamination
    // Assert: each has independent state
}

// T-16: Voice pool exhaustion
#[test]
fn test_voice_pool_exhaustion_fallback() {
    // Fill voice pool, then attempt dual-voice wrap
    // Assert: falls back to hard wrap with micro-fade
    // Assert: VoiceStealWarning callback sent
}
```

### 16.2 Click Detector Algorithm

```rust
/// Analyzes rendered audio for clicks at loop seams.
/// Returns max peak discontinuity (0.0 = perfect, 1.0 = full-scale click)
pub fn analyze_seam_quality(
    output: &[f32],
    wrap_positions: &[usize], // Frame indices where wraps occurred
    window_samples: usize,    // Analysis window (e.g., 128 samples)
) -> SeamAnalysis {
    let mut max_discontinuity: f32 = 0.0;
    let mut max_delta_db: f32 = f32::NEG_INFINITY;

    for &wrap_frame in wrap_positions {
        let idx = wrap_frame * 2; // stereo interleaved
        if idx >= output.len() || idx == 0 { continue; }

        // Sample-to-sample difference at wrap point
        let delta_l = (output[idx] - output[idx - 2]).abs();
        let delta_r = (output[idx + 1] - output[idx - 1]).abs();
        let delta = delta_l.max(delta_r);

        max_discontinuity = max_discontinuity.max(delta);

        // RMS before and after
        let rms_before = rms(&output[idx.saturating_sub(window_samples * 2)..idx]);
        let rms_after = rms(&output[idx..idx.saturating_add(window_samples * 2).min(output.len())]);

        if rms_before > 0.0 && rms_after > 0.0 {
            let delta_db = 20.0 * (rms_after / rms_before).log10();
            max_delta_db = max_delta_db.max(delta_db.abs());
        }
    }

    SeamAnalysis {
        max_discontinuity,
        max_delta_db,
        pass: max_discontinuity < 0.01 && max_delta_db < 3.0,
    }
}
```

### 16.3 Drift Logger

```rust
/// Dev-only: logs wrap timing for drift analysis
pub struct DriftLogger {
    expected_wraps: Vec<u64>,  // Expected wrap sample positions
    actual_wraps: Vec<u64>,    // Actual wrap sample positions
}

impl DriftLogger {
    pub fn report(&self) -> DriftReport {
        let drifts: Vec<i64> = self.expected_wraps.iter()
            .zip(self.actual_wraps.iter())
            .map(|(e, a)| *a as i64 - *e as i64)
            .collect();

        DriftReport {
            max_drift_samples: drifts.iter().map(|d| d.abs()).max().unwrap_or(0),
            mean_drift_samples: if drifts.is_empty() { 0.0 }
                else { drifts.iter().sum::<i64>() as f64 / drifts.len() as f64 },
            cumulative_drift: drifts.iter().sum::<i64>(),
            pass: drifts.iter().all(|d| d.abs() <= 1),
        }
    }
}
```

---

## 17. Integration with Existing Systems

### 17.1 Existing Code That Changes

| File | Change | Reason |
|------|--------|--------|
| `rf-engine/src/playback.rs` | Add `LoopInstanceManager` to `PlaybackEngine.process()` | Loop instances render alongside existing voices |
| `rf-engine/src/playback.rs` | Extend `OneShotVoice` with `loop_instance_id: Option<u64>` | Track which voices belong to loop instances |
| `rf-bridge/src/lib.rs` | Add `mod loop_ffi;` | FFI module registration |
| `flutter_ui/lib/src/rust/native_ffi.dart` | Add loop FFI bindings (~30 functions) | Dart↔Rust communication |
| `flutter_ui/lib/services/service_locator.dart` | Register `LoopProvider` at Layer 6.x | GetIt DI |
| `flutter_ui/lib/models/middleware_models.dart` | Add `LoopAsset`, `LoopRegion` Dart models | UI data models |

### 17.2 Existing Code That Does NOT Change

| System | Reason |
|--------|--------|
| `PlaybackPosition` (DAW loop) | DAW timeline loop is separate — this system is for middleware LoopAssets |
| `MusicSegment` (rf-event) | Music segments have their own cue system — LoopAsset is a new parallel model |
| `Crossfade` (track_manager) | DAW clip crossfades are unrelated to loop seam fades |
| `SlotEventLayer.loop` | Existing boolean flag for simple looping — LoopAsset is for advanced cases |
| `AudioRegion` | DAW timeline regions — not middleware loop regions |

### 17.3 Voice Pool Integration

LoopInstance voices are allocated from `VoicePoolType::music` (or a new `VoicePoolType::loop` pool).

```dart
// In VoicePoolType extension:
loop: defaultMaxVoices = 16, stealingWeight = 70
```

### 17.4 AUREXIS Integration

AUREXIS can observe loop state for intelligence:

```dart
// AurexisProvider can read:
// - loopProvider.activeInstances → which loops are playing
// - loopProvider.currentRegions → intensity tracking
// - loopCallbacks stream → wrap events for volatility analysis
```

### 17.5 ALE Integration

ALE layers can trigger region switches:

```
ALE Layer 1 (low intensity)  → SetLoopRegion("LoopC")
ALE Layer 2 (medium)         → SetLoopRegion("LoopA")
ALE Layer 3 (high)           → SetLoopRegion("LoopB")
```

---

## 18. Gap Analysis — Holes Plugged

The following gaps were identified in the original spec through multi-role analysis:

### 18.1 Chief Audio Architect — Architectural Gaps

| # | Gap | Resolution |
|---|-----|-----------|
| GA-01 | **No CueType taxonomy** — original spec has "Entry/Exit" and "Custom" but no distinction between sync, event, and stinger cues | Added `CueType::Sync` and `CueType::Event` for precise dispatch |
| GA-02 | **No voice pool integration** — dual-voice mode needs pool awareness | Added voice pool integration (Section 8.4), fallback to hard wrap on exhaustion |
| GA-03 | **No concurrent instance limit** — what happens with 100 PlayLoop commands? | Added `MAX_LOOP_INSTANCES = 32` pre-allocated pool |
| GA-04 | **No instance ID management** — how does `SetLoopRegion` target a specific instance? | Added `instance_id` (u64 monotonic counter) + `instanceRef` in JSON commands (maps asset_id to instance) |
| GA-05 | **SameTime sync not specified** — Wwise has it, original spec doesn't | Added `SyncMode::SameTime` with relative position mapping between regions |
| GA-06 | **No callback system** — UI needs to know about wraps, cue hits, state changes | Added `LoopCallback` enum with 8 callback types |

### 18.2 Lead DSP Engineer — Signal Processing Gaps

| # | Gap | Resolution |
|---|-----|-----------|
| GD-01 | **Micro-fade shape not specified** — "3-10ms" but what curve? | Specified: always **cosine** (equal-power). Mathematically optimal for loop seams — eliminates energy dip that linear fade creates |
| GD-02 | **Crossfade energy conservation** — linear crossfade creates -6dB dip at midpoint | Default crossfade curve is `EqualPower` (not `Linear`). Equal-power maintains constant perceived loudness through the crossfade |
| GD-03 | **Fade length vs region length constraint** — what if seam fade > half the region? | Added V-08 validation: clamp to half region length. Added V-15: crossfade cannot exceed half region length |
| GD-04 | **No pitch shift support during loop** — what about loops with pitch RTPC? | Out of scope for Phase 1. `OneShotVoice` already has `pitch_semitones` — can be exposed later |
| GD-05 | **No sample-rate mismatch handling** — asset at 44.1kHz, engine at 48kHz | SRC is handled by existing `PlaybackPosition` Lanczos-3 interpolation. LoopAsset stores source sample rate, positions are in source samples. Engine converts during playback |
| GD-06 | **Dual-voice crossfade phase coherence** — two voices playing the same source can cause comb filtering | Acknowledged risk. Mitigation: crossfade region should be < 50ms for seam wraps (eliminates audible comb). For region switches, crossfade can be longer because the audio content is different |

### 18.3 Engine Architect — Runtime Safety Gaps

| # | Gap | Resolution |
|---|-----|-----------|
| GE-01 | **No command queue sizing** — how large is the rtrb buffer? | `rtrb::RingBuffer::new(256)` for commands, `rtrb::RingBuffer::new(512)` for callbacks. If full → drop oldest (non-blocking) |
| GE-02 | **No instance reclamation** — when does a STOPPED instance get freed? | STOPPED instances are reclaimed in the next `process()` call (slot set to None) |
| GE-03 | **Asset loading is not lock-free** — `HashMap<String, Arc<LoopAsset>>` uses String comparison | Assets are loaded/registered from UI thread BEFORE playback starts. During processing, `assets` is read-only (no mutation). String lookup is acceptable because it happens once per PlayLoop command (not per sample) |
| GE-04 | **No graceful degradation** — what if asset_id not found at runtime? | `Play` command with unknown asset_id → send `LoopCallback::Error` → no instance created. No panic, no crash |
| GE-05 | **No thread safety for LoopInstance fields** — multiple fields updated per frame | `LoopInstance` is owned exclusively by the audio thread (inside `LoopInstanceManager`). No concurrent access. UI reads state via callbacks only |
| GE-06 | **Arm margin for dual-voice** — original spec says "pre-roll" but no concrete value | Fixed `armMarginMs = 50ms` (2400 samples @ 48kHz). This is the minimum scheduling lead time for web audio to decode and buffer Voice B |

### 18.4 Technical Director — Integration Gaps

| # | Gap | Resolution |
|---|-----|-----------|
| GT-01 | **No undo/redo for loop editing** — authoring actions need to be undoable | Reuse existing `Command` trait pattern from `rf-state/src/commands.rs`. New commands: `SetCueCommand`, `SetRegionCommand`, `AddCueCommand`, `RemoveCueCommand` |
| GT-02 | **No serialization versioning** — JSON format needs version field for migration | Added `"version": 1` to JSON root. Future changes increment version, migration code handles older formats |
| GT-03 | **No LoopAsset registry/bank** — where are LoopAssets stored? | `LoopAssetBank` (Dart) loads all `.ffloop.json` files from project assets folder. Rust side receives registered assets via FFI before playback starts |
| GT-04 | **Middleware command integration** — how do `PlayLoop`/`SetLoopRegion`/`ExitLoop` integrate with existing `EngineCommand` system? | New `EngineCommandType` variants: `playLoop`, `setLoopRegion`, `exitLoop`, `stopLoop`. These map to `LoopCommand` enum and are dispatched through the existing middleware command pipeline |

### 18.5 UI/UX Expert — Authoring Gaps

| # | Gap | Resolution |
|---|-----|-----------|
| GU-01 | **No loop preview in editor** — how does the author hear the loop? | Preview button in inspector: plays Entry→LoopIn→(3 loops of body)→Exit. Uses existing `AudioPlaybackService` with `PlaybackSource::browser` |
| GU-02 | **No visual wrap indicator** — how does the author see where the wrap happens? | Animated playhead in waveform view. At wrap point, playhead jumps back with brief flash animation |
| GU-03 | **No marker drag constraints** — can you drag Entry past Exit? | Drag constraints: Entry < first LoopIn. Exit > last LoopOut. LoopIn < LoopOut within same region. Drag stops at constraint |
| GU-04 | **No import wizard** — when dropping a WAV, how does the user create a LoopAsset? | Auto-detect: if `.ffmarkers.json` sidecar exists → auto-import. If BWF cue chunk exists → import dialog. Otherwise → create blank LoopAsset with Entry=0, Exit=end, one default region [0, end) |
| GU-05 | **No waveform overview for long files** — 10-minute background music needs zoom | Reuse existing multi-LOD waveform cache system. The Loop Editor waveform view connects to `WaveformThumbnailCache` with custom zoom levels |

### 18.6 Security Expert — Safety Gaps

| # | Gap | Resolution |
|---|-----|-----------|
| GS-01 | **Path traversal in sidecar** — `.ffmarkers.json` "file" field could reference `../../etc/passwd` | Sidecar parser validates: `file` field must be a bare filename (no path separators). Full path is resolved by the asset loader, not the marker file |
| GS-02 | **Integer overflow in sample positions** — `u64` is safe for samples, but `u64 * u64` during computation could overflow | All sample arithmetic uses `u64::checked_add()` / `u64::saturating_sub()` in validation. In processing, positions are guaranteed in-bounds by state machine invariants |
| GS-03 | **JSON parsing DoS** — malformed `.ffloop.json` with deeply nested arrays | Use `serde_json` with `recursion_limit(32)`. Reject files > 1MB |
| GS-04 | **Marker count limit** — 10,000 custom cues would degrade performance | Max 256 cues per asset. Max 16 regions per asset. Enforced at parse time |

---

## 19. Implementation Phases

### Phase 1: Foundation (~2,800 LOC Rust + ~600 LOC Dart)

| # | Task | LOC | File |
|---|------|-----|------|
| L-01 | `loop_asset.rs` — LoopAsset, LoopRegion, Cue, validation | ~500 | `rf-engine/src/loop_asset.rs` |
| L-02 | `loop_instance.rs` — LoopInstance, LoopState, state machine | ~400 | `rf-engine/src/loop_instance.rs` |
| L-03 | `loop_manager.rs` — LoopInstanceManager, command/callback queues | ~350 | `rf-engine/src/loop_manager.rs` |
| L-04 | `loop_process.rs` — Single-voice PCM wrap + micro-fade | ~400 | `rf-engine/src/loop_process.rs` |
| L-05 | `loop_process.rs` — Dual-voice crossfade wrap | ~500 | `rf-engine/src/loop_process.rs` |
| L-06 | `loop_process.rs` — Region switch with sync boundary | ~300 | `rf-engine/src/loop_process.rs` |
| L-07 | `loop_process.rs` — Pre-entry / post-exit zones | ~150 | `rf-engine/src/loop_process.rs` |
| L-08 | `loop_process.rs` — Intro state (all 4 wrap policies) | ~200 | `rf-engine/src/loop_process.rs` |
| L-09 | Unit tests (T-01 through T-16) | ~800 | `rf-engine/tests/loop_tests.rs` |
| L-10 | Dart models (`LoopAsset`, `LoopRegion`, `Cue`, etc.) | ~400 | `flutter_ui/lib/models/loop_asset_models.dart` |
| L-11 | Dart `LoopProvider` skeleton + GetIt registration | ~200 | `flutter_ui/lib/providers/loop_provider.dart` |

### Phase 2: FFI + Marker Ingest (~1,200 LOC Rust + ~400 LOC Dart)

| # | Task | LOC | File |
|---|------|-----|------|
| L-12 | `loop_ffi.rs` — ~30 FFI exports | ~500 | `rf-bridge/src/loop_ffi.rs` |
| L-13 | Dart FFI bindings | ~250 | `flutter_ui/lib/src/rust/native_ffi.dart` |
| L-14 | `marker_ingest.rs` — Sidecar parser | ~200 | `rf-engine/src/marker_ingest.rs` |
| L-15 | `marker_ingest.rs` — BWF cue chunk parser | ~250 | `rf-engine/src/marker_ingest.rs` |
| L-16 | `marker_ingest.rs` — Marker→LoopAsset mapping | ~150 | `rf-engine/src/marker_ingest.rs` |
| L-17 | `LoopProvider` — full implementation with FFI bridge | ~250 | `flutter_ui/lib/providers/loop_provider.dart` |
| L-18 | Ingest tests | ~200 | `rf-engine/tests/marker_ingest_tests.rs` |

### Phase 3: Authoring UI (~2,000 LOC Dart)

| # | Task | LOC | File |
|---|------|-----|------|
| L-19 | `loop_editor_panel.dart` — Main panel with waveform + lanes | ~600 | `flutter_ui/lib/widgets/loop/loop_editor_panel.dart` |
| L-20 | `loop_cue_lane.dart` — Cue markers lane | ~250 | `flutter_ui/lib/widgets/loop/loop_cue_lane.dart` |
| L-21 | `loop_region_lane.dart` — Region bars lane | ~250 | `flutter_ui/lib/widgets/loop/loop_region_lane.dart` |
| L-22 | `loop_inspector.dart` — Selected item inspector | ~350 | `flutter_ui/lib/widgets/loop/loop_inspector.dart` |
| L-23 | `loop_waveform_painter.dart` — Custom painter with zones | ~300 | `flutter_ui/lib/widgets/loop/loop_waveform_painter.dart` |
| L-24 | Lower Zone tab registration + keyboard shortcuts | ~100 | Integration in existing files |
| L-25 | Import wizard (drag-drop + sidecar auto-detect) | ~150 | `flutter_ui/lib/widgets/loop/loop_import_wizard.dart` |

### Phase 4: QA Harness + Integration (~800 LOC)

| # | Task | LOC | File |
|---|------|-----|------|
| L-26 | Click detector + seam analyzer | ~200 | `rf-engine/src/loop_qa.rs` |
| L-27 | Drift logger | ~100 | `rf-engine/src/loop_qa.rs` |
| L-28 | Integration tests (end-to-end loop playback) | ~300 | `rf-engine/tests/loop_integration_tests.rs` |
| L-29 | Middleware command integration | ~100 | `rf-engine/src/loop_manager.rs` + existing command pipeline |
| L-30 | LoopAssetBank + project save/load | ~100 | `flutter_ui/lib/services/loop_asset_bank.dart` |

### Summary

| Phase | Rust LOC | Dart LOC | Total |
|-------|---------|---------|-------|
| Phase 1: Foundation | ~2,800 | ~600 | ~3,400 |
| Phase 2: FFI + Ingest | ~1,200 | ~400 | ~1,600 |
| Phase 3: UI | — | ~2,000 | ~2,000 |
| Phase 4: QA + Integration | ~600 | ~200 | ~800 |
| **TOTAL** | **~4,600** | **~3,200** | **~7,800** |

---

## 20. File Manifest

### New Files (Rust)

```
crates/rf-engine/src/loop_asset.rs          — Data model + validation
crates/rf-engine/src/loop_instance.rs       — Runtime state machine
crates/rf-engine/src/loop_manager.rs        — Instance pool + command dispatch
crates/rf-engine/src/loop_process.rs        — Audio processing (wrap, fade, crossfade)
crates/rf-engine/src/loop_qa.rs             — Click detector + drift logger
crates/rf-engine/src/marker_ingest.rs       — Sidecar + BWF marker parsing
crates/rf-engine/tests/loop_tests.rs        — Unit tests (T-01 through T-16)
crates/rf-engine/tests/loop_integration_tests.rs — End-to-end tests
crates/rf-engine/tests/marker_ingest_tests.rs    — Ingest tests
crates/rf-bridge/src/loop_ffi.rs            — FFI exports
```

### New Files (Dart)

```
flutter_ui/lib/models/loop_asset_models.dart             — Dart data models
flutter_ui/lib/providers/loop_provider.dart               — LoopProvider (GetIt)
flutter_ui/lib/services/loop_asset_bank.dart              — Asset registry + save/load
flutter_ui/lib/widgets/loop/loop_editor_panel.dart        — Main editor UI
flutter_ui/lib/widgets/loop/loop_cue_lane.dart            — Cue markers lane
flutter_ui/lib/widgets/loop/loop_region_lane.dart         — Region bars lane
flutter_ui/lib/widgets/loop/loop_inspector.dart           — Inspector panel
flutter_ui/lib/widgets/loop/loop_waveform_painter.dart    — Waveform with zones
flutter_ui/lib/widgets/loop/loop_import_wizard.dart       — Import dialog
```

### Modified Files

```
crates/rf-engine/src/lib.rs                 — Add loop modules
crates/rf-engine/src/playback.rs            — Integrate LoopInstanceManager
crates/rf-bridge/src/lib.rs                 — Add loop_ffi module
flutter_ui/lib/src/rust/native_ffi.dart     — Add loop FFI bindings
flutter_ui/lib/services/service_locator.dart — Register LoopProvider
flutter_ui/lib/models/stage_models.dart      — Add loop EngineCommandType variants
```

---

*End of Specification — FluxForge Advanced Looping System v1.0*
*Casino-grade determinism. Wwise parity + multi-region superiority. Zero-allocation audio thread.*
