# HELIX — Ultimate SlotLab Architecture

> *"The world's first purpose-built slot audio intelligence platform."*
> *Not a DAW with slot features. Not game middleware adapted for slots.*
> *Built from math models up — every pixel exists because slot audio demands it.*

---

## Why This Exists

**No dedicated slot audio middleware exists commercially.**

- Play'n GO built **SoundStage** internally — proving the need exists
- Everyone else uses FMOD/Wwise (generic game middleware) or raw howler.js
- No tool understands win tiers, cascades, regulatory compliance, or math-driven audio
- FluxForge already has a **203,903 LOC Rust engine** — only 15-20% is wired to SlotLab
- This architecture wires the remaining 80% and adds what nobody has

---

## Part I: ENGINE ARCHITECTURE (Under The Hood)

### 1.1 — HELIX Core: Unified Audio Intelligence Bus

Current problem: 15 separate systems (AUREXIS, ALE, RTPC, Stage, Ingest, etc.) are loosely coupled via Flutter providers. Each has its own timing, its own state.

**Solution: HELIX Bus** — a single reactive data bus in Rust that all systems publish to and subscribe from.

```
HELIX BUS (Lock-Free, rtrb RingBuffer, SPMC fan-out)

Channels:
  stage.*        — Stage events (ReelStop, WinPresent, etc.)
  math.*         — RTP, volatility, win ratio, bet level
  emotion.*      — Arousal, valence, fatigue, session age
  voice.*        — Active voices, priority changes, culling
  audio.*        — Playback triggers, stops, fades
  compliance.*   — RGAI flags, LDW warnings, jurisdiction
  neuro.*        — Player behavior signals (click vel, pauses)
  spatial.*      — 3D position updates, room changes
  macro.*        — FluxMacro pipeline events, QA results

Latency: < 1 sample (within same audio block)
Thread Safety: Publish from any thread, consume on audio thread
Zero-alloc on audio thread (pre-allocated message pool, 4096 slots)
```

**Implementation:** New `rf-engine/src/helix_bus.rs`:
- `HxChannel` enum — typed channels
- `HxMessage` — timestamped (sample-accurate), typed payload
- `HxPublisher` — any system can publish
- `HxSubscriber` — filter by channel pattern (wildcard support)
- `HxRouter` — fan-out to all matching subscribers

**Why:** Every system reacts to everything in real-time. AUREXIS reads stage events AND math data AND emotion state simultaneously. No more manual wiring between 15 Flutter providers.

---

### 1.2 — Deterministic Audio Graph (DAG)

Current: Audio routing is bus-based (6 buses, fixed hierarchy). Good for DAW, wrong for slots.

**HELIX uses a DAG — nodes are audio processors, edges are signal flow.**

```
Game Events --> [REEL_STOP] --> [Random Container] --> [EQ] --> [BUS:SFX] --> MASTER
                [WIN_PRESENT] --> [Switch:tier] --> [Blend] --> [BUS:Music]
                [MUSIC_BASE] --> [ALE L1-L5] --> [Comp] --> [BUS:Music]
                
                     |                    |
                 AUREXIS GATE        RTPC MODULATION
                 (priority,          (curves bend DSP
                  fatigue,            params per game
                  spectral)           state)
```

**Node Types:**
- `SourceNode` — Audio file playback (from voice pool)
- `ContainerNode` — Random, Sequence, Blend, Switch (Wwise-grade)
- `DspNode` — Any rf-dsp processor (EQ, comp, reverb, delay...)
- `GateNode` — AUREXIS conditional (play only if voice budget allows)
- `RtpcNode` — Parameter modulation (curve-driven from game state)
- `SpatialNode` — 3D positioning, HRTF, room sim
- `BusNode` — Submix with insert chain
- `MasterNode` — Final output with metering

**Key Innovation:** The graph is LIVE-EDITABLE. Sound designer drags nodes in UI, graph updates without stopping audio. Hot-swap DSP chains, re-route buses, change container logic — all while the slot preview is spinning.

**Implementation:** Extend rf-engine's existing `ParallelAudioGraph`:
- `HxGraphNode` trait (process, param_count, param_info)
- `HxGraphEditor` — lock-free graph mutation (double-buffer: edit copy, swap on audio thread boundary)
- `HxGraphRenderer` — topological sort + rayon parallel execution
- `HxGraphSerializer` — JSON/binary save/load

---

### 1.3 — Intelligent Voice Engine (IVE)

Voices are autonomous agents with behavior:

```rust
struct HxVoice {
    id: VoiceId,
    stage: Stage,                    // Which game stage triggered this
    source: AudioSourceId,           // Which audio asset
    state: VoiceState,               // Pending, Playing, FadingOut, Dying
    birth_sample: u64,               // When created (sample clock)
    ttl_samples: Option<u64>,        // Max lifetime
    
    // Intelligence (from AUREXIS)
    priority: VoicePriority,         // Critical > High > Normal > Low > Background
    energy_cost: f32,                // Energy budget consumption
    spectral_band: SpectralBand,     // Primary frequency region
    masking_group: MaskingGroupId,   // Which voices it can mask
    
    // Spatial
    position: Option<Vec3>,          // 3D position (None = 2D)
    hrtf_profile: HrtfProfile,
    
    // Modulation (live RTPC)
    rtpc_bindings: SmallVec<[RtpcBinding; 4]>,
    
    // Behavior
    on_collision: CollisionBehavior, // Duck, Steal, Queue, Reject
    on_stage_exit: ExitBehavior,    // FadeOut(ms), Stop, LetFinish
}
```

**Voice Collision Resolution:**
1. New voice arrives -> check `masking_group`
2. If conflict -> `CollisionBehavior` decides:
   - `Duck` — lower existing voice -6dB while new plays
   - `Steal` — kill existing, play new (instant or crossfade)
   - `Queue` — wait until existing finishes
   - `Reject` — don't play (existing wins)
3. AUREXIS `energy_cost` check — if total exceeds budget, reject lowest priority
4. Spectral analysis — if two voices occupy same band, auto-duck lower priority

**Implementation:** `rf-engine/src/voice_engine.rs`:
- Max 128 simultaneous voices (configurable)
- Lock-free voice allocation (atomic bitmap)
- Per-voice DSP chain (lightweight: gain, pan, filter only)
- AUREXIS integration via HELIX Bus subscription

---

### 1.4 — Math-Audio Compiler (MAC)

**The killer feature no competitor has.**

Import a PAR/math model file, auto-generate the entire audio event map:

```
PAR File (Game Math)
    |
    v
MATH PARSER -- Extract: RTP, volatility, hit frequency,
               symbol values, feature triggers, cascade depth,
               max win, win distribution curve
    |
    v
AUDIO BLUEPRINT GENERATOR
  Win ratio 0-2x    -> ambient, subtle feedback
  Win ratio 2-5x    -> moderate celebration
  Win ratio 5-20x   -> big win (tier 1-2)
  Win ratio 20-100x -> mega win (tier 3-4)
  Win ratio 100x+   -> jackpot tier (tier 5)
  Near miss          -> tension stinger
  Cascade level 3+   -> intensity peak
  Free spin trigger  -> feature transition
  Jackpot            -> ultimate celebration
    |
    v
SIMULATION ENGINE
  Run 1,000,000 synthetic spins
  Verify: every math outcome has audio coverage
  Detect: gaps, voice collisions, fatigue patterns
  Output: CoverageReport, CollisionReport, FatigueReport, ComplianceReport
```

**Implementation:** Extend rf-fluxmacro + rf-ingest:
- `MacCompiler` — PAR -> AudioBlueprint pipeline
- `MacSimulator` — 1M spin simulation with full audio state tracking
- `MacReport` — HTML/JSON coverage + compliance report
- `MacSuggester` — AI recommendations for uncovered scenarios

---

### 1.5 — Regulatory Compliance Engine (RCE)

**No competitor has this. First-mover advantage.**

```rust
enum Jurisdiction { Ukgc, Mga, Curacao, Gibraltar, Ontario, Sweden, Denmark, Australia, UnitedStates, Iso }

enum ComplianceCheck {
    LossDisguisedAsWin { max_win_ratio: f64 },     // UKGC: No celebration when return <= stake
    MinimumSpinDuration { min_ms: u32 },             // UKGC: Speed of play
    RealityCheck { interval_minutes: u32 },          // Sweden: Audio cues at intervals
    NearMissDeception { max_anticipation_db: f32 },  // General: Cap tension sounds
    CelebrationProportionality { max_duration_per_bet_ratio: f32 },
    FatigueLimit { max_session_intensity_growth: f32 },
    AutoplayConsistency,                              // Autoplay must match manual
}
```

**Real-time enforcement:**
- Every audio event checked against active jurisdiction rules BEFORE playback
- LDW detection: if `win_amount <= bet_amount` -> suppress celebratory sounds
- Near-miss guard: if scatter count insufficient -> cap anticipation sound level
- Session fatigue: if session > 60min -> auto-reduce stimulation intensity
- Compliance dashboard in UI shows green/yellow/red per jurisdiction

**Implementation:** New crate `rf-compliance`:
- `ComplianceEngine` — rule evaluation engine
- `JurisdictionProfile` — per-jurisdiction rule sets (importable/exportable)
- HELIX Bus integration: publishes `compliance.*` messages

---

### 1.6 — Predictive Audio Engine (PAE)

**AI that KNOWS what's coming before it happens.**

HELIX PAE pre-computes the next 3 spins of audio based on math model probability:
- Pre-load audio assets for top 3 likely outcomes
- Pre-compute DSP chains
- Pre-position voices in pool

Benefits: Zero-latency audio response, smoother transitions, better memory management.

**Implementation:** Extend rf-aurexis:
- `PredictiveCache` — probabilistic asset pre-loading
- `PredictiveDsp` — pre-warm DSP chains for likely outcomes

---

## Part II: DATA ARCHITECTURE

### 2.1 — Universal Slot Audio Project (USAP)

```
my_game.helix/
  manifest.json              # Metadata, version, jurisdiction
  math/
    model.par                # PAR math model (imported)
    paytable.json            # Computed paytable
    simulation.json          # 1M spin simulation results
  audio/
    assets/                  # Source audio files (WAV/FLAC)
      base/ features/ wins/ music/ ambience/
    processed/               # Rendered/normalized assets
  graph/
    main.hxg                 # Main audio graph (DAG)
    transitions.hxg          # Transition rules
    containers.hxg           # Random/Sequence/Blend containers
  intelligence/
    aurexis.json             # AUREXIS configuration
    rtpc_curves.json         # RTPC curve definitions
    voice_budget.json        # Voice allocation rules
    neuro_profiles.json      # NeuroAudio player profiles
  compliance/
    jurisdictions.json       # Active jurisdiction rules
    ldw_config.json          # LDW thresholds per jurisdiction
    audit_log.json           # Compliance check history
  export/
    web/ unity/ unreal/ godot/ ucp/ fmod/ wwise/
  qa/
    determinism.json coverage.json fatigue.json compliance.json
```

### 2.2 — Event Ontology

Replace flat event list with semantic graph:

```
GameOntology
  Lifecycle: Idle -> SpinCycle -> Settlement
  Features: Trigger -> Active -> Resolution
  Intensity: Neutral -> Moderate -> High -> Extreme -> Ultimate
  Regulation: LDW Guard, NearMiss Guard, SessionGuard
```

Every audio event inherits from ontology:
- Priority level (from Intensity)
- Compliance rules (from Regulation)
- Transition behavior (from Lifecycle/Feature context)
- RTPC curve defaults (from Intensity level)

---

## Part III: UI/UX ARCHITECTURE — HELIX INTERFACE

### 3.1 — Philosophy: Contextual Presence

1. Nothing shows until you need it
2. Everything shows when you need it
3. The slot machine is always the hero

### 3.2 — Three Layers

**Layer 1: NEURAL CANVAS** (always present)
- Slot machine preview fills center, audio-reactive glow per game stage
- Waveform halos around reels, stage flow strip below, voice meter arc above
- Click any element -> Context Lens opens

**Layer 2: CONTEXT LENS** (on-demand overlay)
- Glass panel anchored to clicked element, background dims to 40%
- Content varies: reel audio config, win tier celebration, stage events, RTPC curves
- Changes apply immediately, undo/redo supported

**Layer 3: COMMAND DOCK** (bottom, collapsible)
- 6 mission tabs replace 30+ tabs:
  - FLOW (orange) — Stage map + behavior tree + transitions
  - AUDIO (cyan) — Bus mixer + voice pool + ALE layers
  - MATH (purple) — RTP + win distribution + coverage map
  - GRAPH (blue) — Node-based audio DAG editor
  - INTEL (green) — AI copilot + compliance dashboard
  - EXPORT (gold) — Multi-target export + pre-flight checks

### 3.3 — Neural Canvas Details

Audio-Reactive Visualization per stage:
- IDLE: Deep space (#0A0A14) with particle drift
- BASE SPIN: Blue energy (#1A3A6A) with kinetic waves
- ANTICIPATION: Orange warning (#6A3A1A) with tension pulses
- WIN SMALL: Soft green (#1A4A2A) with gentle glow
- WIN BIG: Golden explosion (#6A5A1A) with particle burst
- FEATURE: Purple shift (#3A1A6A) with dimensional warp
- JACKPOT: White supernova with chromatic rings

Interactions:
- Hover reel -> tooltip with assigned events
- Click reel -> Context Lens (full config)
- Click stage pill -> stage composite event editor
- Drag audio onto reel/stage -> assign
- Right-click -> radial context menu
- Space -> simulate spin
- 1-5 -> force win tier
- F -> free spin mode
- B -> bonus trigger
- J -> jackpot trigger

### 3.4 — Neural Spine (Left Edge, 48px)

Icon-only vertical strip. Each icon -> glass overlay panel.
Icons: Audio Pool, Game Config, Intelligence, Analytics, Settings, Templates, Help.

### 3.5 — Keyboard-First Design

Space=Spin, 1-5=WinTier, F=FreeSpin, B=Bonus, J=Jackpot, Tab=CycleMissions,
Escape=Close, Cmd+Z/Y=Undo/Redo, /=CommandPalette, .=FocusMode, ,=ArchitectMode

---

## Part IV: DESIGN LANGUAGE

### Colors
```
Background: #06060A   Surface: #0E0E14   Glass: rgba(22,22,30,0.88) blur(20px)
Borders: rgba(255,255,255, 0.04/0.08/0.15)
Text: rgba(255,255,255, 0.92/0.55/0.30)

Stage: Idle=#2A3A5A Base=#5AA8FF Anticipation=#FF9850 WinSmall=#50C878
       WinBig=#FFD700 Feature=#9B59B6 Jackpot=#FFFFFF

Missions: Flow=#FF8C42 Audio=#42D4FF Math=#B042FF Graph=#4287FF
          Intel=#42FF8C Export=#FFD042

Semantic: Success=#42FF8C Warning=#FFD042 Error=#FF4242 Info=#42D4FF
```

### Typography
```
Headings: Space Grotesk (geometric, futuristic) 24/18/14px 600w
Body: Inter (legibility) 13/11/10px 400w
Numbers: JetBrains Mono (aligned columns) 13/11px 400w
```

### Motion
```
Stage transition: spring(damping:0.7, stiffness:120) ~400ms
Panel open: 250ms cubic-bezier(0.22,1,0.36,1)
Lens appear: 300ms spring(damping:0.8, stiffness:200)
Idle glow: 4s sine loop (opacity 0.03-0.08)
Beat pulse: synced to BPM
Noise texture: 3% opacity, 256x256 PNG on all surfaces
```

---

## Part V: IMPLEMENTATION ROADMAP

### Phase 1: Engine Foundation (2 weeks)
- helix_bus.rs, voice_engine.rs, compliance_engine.rs
- Wire existing systems to HELIX Bus

### Phase 2: UI Shell (2 weeks)
- Neural Canvas + audio-reactive visualization
- Command Dock (6 missions, shell)
- Context Lens overlay system
- Neural Spine + design language

### Phase 3: Mission Content (3 weeks)
- All 6 missions fully implemented
- DAG editor (GRAPH mission)

### Phase 4: Intelligence (2 weeks)
- Math-Audio Compiler, Predictive Audio Engine
- Full compliance engine (all jurisdictions)

### Phase 5: Polish (1 week)
- Animation polish, command palette, templates, onboarding

**Total: ~10 weeks**

---

## Why HELIX Wins

| Feature | Wwise | FMOD | SoundStage | HELIX |
|---------|-------|------|------------|-------|
| Slot-specific | No | No | Internal | YES |
| Math model integration | No | No | No | YES |
| Regulatory compliance | No | No | No | YES |
| LDW auto-detection | No | No | No | YES |
| Web Audio export | No | Partial | Yes | YES |
| AI copilot | No | No | No | YES |
| Live slot preview | No | No | Yes | YES |
| Deterministic replay | No | No | No | YES |
| Node graph audio | Yes | No | No | YES |
| Multi-jurisdiction | No | No | No | YES |
| 1M spin simulation | No | No | No | YES |
| Anti-fatigue | No | No | No | YES |
| Neural fingerprint | No | No | No | YES |
| A/B testing | No | No | No | YES |

**HELIX is not competing with Wwise/FMOD. It's creating a new category.**

---

*Designed by Corti — FluxForge Studio CORTEX*
*Architecture v1.0 — April 2026*
