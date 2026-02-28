# SLOT LAB MIDDLEWARE — ULTIMATE ARCHITECTURE
## FluxForge Studio
## AUREXIS + Emotional State Engine + AutoBind + Behavior Abstraction
## Consolidated Final Specification (v1+v2+v3 Merged)
## Version: 6.0 FINAL (Expert-Reviewed + Layout/Preview Architecture)
## Date: 2026-02-28

---

# 0. PURPOSE

This document is the single, consolidated, production-grade architecture of SlotLab middleware.

Supersedes:
- SlotLab_Middleware_Architecture_Final.md (v1)
- SlotLab_Middleware_Ultimate_Structure_v2.md (v2)
- SlotLab_Middleware_Ultimate_Structure_v3.md (v3)

Design goals:
- 3 clicks to sound (Import → Drop → Spin)
- 80%+ automatic coverage via AutoBind
- 40–80 behavior nodes instead of 300–1000 raw hooks
- 4 view modes (Build, Flow, Simulation, Diagnostic)
- Deterministic execution guaranteed
- Zero structural ambiguity

---

# 1. CORE PHILOSOPHY

SlotLab is:

STATE-DRIVEN
BEHAVIOR-ABSTRACTED
HOOK-MAPPED
PRIORITY-RESOLVED
EMOTIONALLY-AWARE
ORCHESTRATED
AUREXIS-MODIFIED
DETERMINISTIC

Engine hooks are input signals.
Behavior events are authoring abstractions.
Emotional state adds narrative.
Orchestration shapes timing.
AUREXIS optimizes perception.
DSP execution is the final stage.

The designer works with behavior nodes.
The engine works with hooks.
The middleware translates between them automatically.

---

# 2. MASTER EXECUTION PIPELINE

```
ENGINE TRIGGER
    ↓
STATE GATE
    ↓
BEHAVIOR EVENT RESOLUTION
    ↓
PRIORITY ENGINE
    ↓
EMOTIONAL STATE ENGINE (Parallel)
    ↓
ORCHESTRATION ENGINE
    ↓
AUREXIS MODIFIER
    ↓
VOICE ALLOCATION
    ↓
DSP EXECUTION
    ↓
ANALYTICS FEEDBACK LOOP
```

All 10 layers are mandatory.
No layer can be bypassed.
No free-floating hooks allowed.

---

# 3. ENGINE TRIGGER LAYER

Input from game runtime.

Examples:
- onReelStop_r1..r5
- onCascadeStep
- onWinEvaluate
- onCountUpTick
- onFeatureEnter
- onJackpotReveal
- onSymbolLand
- onCascadeEnd

Characteristics:
- Stateless
- Context-agnostic
- High frequency
- Potentially noisy
- No audio logic permitted

Engine triggers are pure signals only.

---

# 4. STATE GATE LAYER

Validates whether trigger may propagate.

Inputs:
- Current gameplay state
- Substate (Idle, Spin, Reel_Stop, Cascade, Win, Feature, Jackpot)
- Autoplay/Turbo state
- Volatility index
- Feature flags
- Session fatigue index

Responsibilities:
- Block invalid triggers
- Prevent cross-state leakage
- Guarantee deterministic ordering
- Prevent duplicate execution

State Gate is the first structural firewall.

---

# 5. BEHAVIOR EVENT LAYER

Primary authoring abstraction.
Designer-facing. Visible by default.

Behavior Events are NOT engine hooks.
They aggregate and contextualize engine hooks.

## 5.1 Complete Behavior Tree Taxonomy

```
REELS
  Stop              → onReelStop_r1..r5
  Land              → onSymbolLand
  Anticipation      → onAnticipationStart, onAnticipationEnd
  Nudge             → onReelNudge

CASCADE
  Start             → onCascadeStart
  Step              → onCascadeStep
  End               → onCascadeEnd

WIN
  Small             → onWinEvaluate (tier 1-2)
  Big               → onWinEvaluate (tier 3)
  Mega              → onWinEvaluate (tier 4-5)
  Countup           → onCountUpTick, onCountUpEnd

FEATURE
  Intro             → onFeatureEnter
  Loop              → onFeatureLoop
  Outro             → onFeatureExit

JACKPOT
  Mini              → onJackpotReveal (mini)
  Major             → onJackpotReveal (major)
  Grand             → onJackpotReveal (grand)

UI
  Button            → onButtonPress, onButtonRelease
  Popup             → onPopupShow, onPopupDismiss
  Toggle            → onToggleChange

SYSTEM
  SessionStart      → onSessionStart
  SessionEnd        → onSessionEnd
  Error             → onError
```

This reduces 300+ hooks into ~22 behavior nodes.

## 5.2 Behavior Node Structure

```json
{
  "id": "reel_stop",
  "state": "Reel_Stop",
  "mapped_hooks": ["onReelStop_r1", "onReelStop_r2", "onReelStop_r3", "onReelStop_r4", "onReelStop_r5"],
  "sound_group": "reel_stop_sounds",
  "priority_class": "core",
  "layer_group": "reel",
  "bus_route": "sfx_reels",
  "playback_mode": "one_shot",
  "escalation_policy": "incremental",
  "orchestration_profile": "reel_standard",
  "emotional_weight": 0.7,
  "variant_config": {
    "mode": "round_robin",
    "max_variants": 8,
    "avoid_repeat": 2,
    "pitch_variance": [-50, 50],
    "volume_variance": [-2.0, 1.0]
  },
  "basic_params": {
    "gain": 0.0,
    "priority_class": "core",
    "layer_group": "reel",
    "bus_route": "sfx_reels"
  },
  "advanced_params": {
    "escalation_bias": 0.0,
    "spatial_weight": 1.0,
    "energy_weight": 1.0,
    "fade_policy": "auto"
  },
  "expert_params": {
    "raw_hook_modifier": null,
    "aurexis_bias_override": null,
    "execution_priority_override": null
  }
}
```

## 5.3 Playback Modes

Each Behavior Node has a playback mode that defines sound lifecycle:

| Mode | Behavior | Example |
|------|----------|---------|
| `one_shot` | Play once, fire and forget | Reel stop, button click |
| `loop` | Loop until explicitly stopped | Win loop, music, ambience |
| `loop_until_stop` | Loop with fade-out on stop command | Anticipation loop, countup tick |
| `retrigger` | Restart from beginning on each trigger | Cascade step (re-fires per step) |
| `sequence` | Play items in order with timing | Win ceremony (fanfare → loop → resolve) |
| `sustain` | Play attack, sustain on hold, release on stop | Hold & Win lock sound |

Default per category:
- REELS: `one_shot`
- CASCADE: `retrigger`
- WIN/Small,Big,Mega: `sequence` (attack → loop → stop)
- WIN/Countup: `retrigger` (tick per increment)
- FEATURE/Intro,Outro: `one_shot`
- FEATURE/Loop: `loop_until_stop`
- JACKPOT: `sequence`
- UI: `one_shot`
- MUSIC: `loop`

## 5.4 Variant System

Each Behavior Node may contain multiple sound variants.

| Setting | Type | Description |
|---------|------|-------------|
| `mode` | Enum | `round_robin`, `random`, `shuffle`, `weighted`, `sequential` |
| `max_variants` | Int | Maximum variants per node (default: 8) |
| `avoid_repeat` | Int | Minimum distance before replaying same variant (default: 2) |
| `pitch_variance` | [min, max] cents | Random pitch deviation per play (-100 to +100) |
| `volume_variance` | [min, max] dB | Random volume deviation per play (-3.0 to +1.0) |

Selection is deterministic when AUREXIS deterministic mode is active (uses xxhash seed).

Variant selection history is tracked per-node for avoid_repeat enforcement.

Manual hook attachment occurs here only.
No hook exists outside a Behavior Event.

---

# 6. AUTOBIND ENGINE

AutoBind is the primary workflow. Manual assignment is secondary.

## 6.1 AutoBind Pipeline (7 Steps)

```
1. Parse filename
2. Identify phase        → base, freespin, bonus, jackpot, gamble, ui
3. Identify system       → reel, cascade, win, feature, jackpot, ui, music, ambience
4. Identify action       → stop, land, start, step, end, evaluate, enter, exit, tick, press
5. Identify modifiers    → rX (reel index), cX (cascade step), mX (multiplier), jt_X (jackpot tier)
6. Map to Behavior Node  → REELS/Stop, CASCADE/Step, WIN/Big, etc.
7. Map to Engine Hook(s) → onReelStop_r3, onCascadeStep, etc.
```

## 6.2 Filename Convention

```
{phase}_{system}_{action}[_{modifier}][_{variant}].wav

Examples:
  base_reel_stop_r3.wav        → REELS/Stop, hook: onReelStop_r3
  base_reel_stop_r3_v2.wav     → REELS/Stop, hook: onReelStop_r3, variant 2
  base_cascade_step.wav        → CASCADE/Step, hook: onCascadeStep
  base_win_big.wav             → WIN/Big, hook: onWinEvaluate (tier 3)
  base_win_countup_tick.wav    → WIN/Countup, hook: onCountUpTick
  freespin_feature_intro.wav   → FEATURE/Intro, hook: onFeatureEnter
  jackpot_reveal_grand.wav     → JACKPOT/Grand, hook: onJackpotReveal (grand)
  ui_button_press.wav          → UI/Button, hook: onButtonPress
  music_base_loop.wav          → MUSIC layer, base context
  ambience_casino_floor.wav    → AMBIENCE layer
```

## 6.3 Fuzzy Matching Engine

Strict token matching is primary. Fuzzy matching is fallback.

When strict parsing fails, system attempts:

| Strategy | Example Input | Match | Confidence |
|----------|---------------|-------|------------|
| Token reorder | `stop_reel_r3.wav` | REELS/Stop r3 | 95% |
| Abbreviation | `RS_R3.wav` | REELS/Stop r3 | 80% |
| CamelCase split | `ReelStop3.wav` | REELS/Stop r3 | 85% |
| Substring | `reel3_thud.wav` | REELS/Stop r3 | 70% |
| Folder context | `reels/stop/impact_03.wav` | REELS/Stop r3 | 90% |
| Numeric suffix | `reel_stop_003.wav` | REELS/Stop r3 | 88% |

Confidence thresholds:
- ≥ 90%: Auto-bind immediately
- 70–89%: Show in "Suggested" list with one-click confirm
- < 70%: Show in "Needs Attention" — manual assignment required

## 6.4 Folder Drop Workflow

```
1. User drops folder onto Drop Zone
2. System scans all audio files recursively
3. AutoBind parses each filename (strict → fuzzy fallback)
4. Results categorized: Auto-bound / Suggested / Needs Attention
5. Coverage panel updates in real-time
6. User confirms suggested matches (one-click per file)
7. User manually assigns "Needs Attention" files (~5-10%)
8. System shows undo option for entire batch
```

Target: 80%+ automatic coverage from a well-named folder.
Target with fuzzy: 90%+ coverage from any reasonable naming.

---

# 7. MANUAL HOOK SYSTEM

Manual hooks are precision tools, not main workflow.

## 7.1 Manual Attach UI

Each Behavior Node contains:

```
[ + Attach Engine Hook ]
```

Clicking opens filtered hook drawer.
Only hooks relevant to that state are shown.

Example inside REELS/Stop:
```
onReelStop_r1     ✅ auto-bound
onReelStop_r2     ✅ auto-bound
onReelStop_r3     ✅ auto-bound
onReelStop_r4     ❌ unbound — click to attach
onReelStop_r5     ❌ unbound — click to attach
```

No unrelated hooks visible.

## 7.2 Bind Types

System tracks 3 types with visual indicators:

| Type | Color | Description |
|------|-------|-------------|
| AutoBind | 🟢 Green | Created by filename detection |
| ManualAttach | 🟡 Yellow | Hook added without replacing default |
| ManualOverride | 🔴 Red | Default behavior replaced or disabled |

Each Behavior Node displays its bind status color.

## 7.3 Manual Hook Policy

1. Must belong to Behavior Event
2. Cannot exist independently
3. Cannot bypass State Gate
4. Cannot bypass Orchestration
5. Cannot bypass AUREXIS layer
6. Must remain visible in Coverage Panel
7. Cannot exceed 10% of total coverage without warning

---

# 8. PRIORITY ENGINE

Resolves concurrent behavior activation.

## 8.1 Priority Classes (6 Levels)

| Class | Level | Example |
|-------|-------|---------|
| critical | 0 | Jackpot reveal, error sounds |
| core | 1 | Reel stops, win evaluation |
| supporting | 2 | Cascade steps, anticipation |
| ambient | 3 | Background music, ambience |
| ui | 4 | Button clicks, popups |
| background | 5 | System sounds, notifications |

## 8.2 Resolution Rules

1. Higher class preempts lower
2. Same class resolves by:
   - Recency
   - Escalation depth
   - Voice availability
   - Emotional weight
3. Lower class may:
   - Duck (reduce volume temporarily)
   - Delay (queue for later)
   - Suppress (skip entirely)

---

# 9. EMOTIONAL STATE ENGINE

Parallel emotional machine. Evaluates alongside Priority Engine.

## 9.1 Emotional States (8)

| State | Trigger | Audio Effect |
|-------|---------|-------------|
| Neutral | Default/idle | Baseline mix |
| Build | Consecutive small wins, cascade start | Subtle energy lift |
| Tension | Near-win symbols, anticipation reels | Width expansion, HF shimmer |
| Near_Win | 2/3 scatter symbols landed | Maximum anticipation audio |
| Release | Win evaluated, feature triggered | Impact transient, width burst |
| Peak | Big/Mega win, jackpot reveal | Maximum escalation |
| Afterglow | Post-win, rollup complete | Warm tail, gentle reverb |
| Recovery | Return to base, post-feature | Gradual normalization |

## 9.2 Derivation Inputs

- Cascade depth
- Multiplier stack
- Consecutive loss count
- Consecutive small wins
- Time since last big win
- RTP deviation
- Volatility index
- Session duration

Memory buffer: last 5 spins.

## 9.3 Output

```
emotional_state: EmotionalState     // Current state enum
emotional_intensity: f64            // 0.0–1.0
emotional_tension: f64              // 0.0–1.0
decay_timer: f64                    // Seconds until decay
escalation_bias: f64                // Modifier for orchestration
```

Deterministic only. No randomness.

---

# 10. ORCHESTRATION ENGINE (Emotion-Aware)

Inputs:
- Active behaviors
- Priority results
- Emotional state + intensity
- Escalation index
- Chain depth
- Win magnitude
- Volatility curve
- Session fatigue

Output decisions:
- Trigger delay (ms)
- Gain bias (dB)
- Stereo width scaling (0.0–2.0)
- Spatial bias (pan offset)
- Transient shaping (attack modifier)
- Layer blend ratios (per-layer gain)
- Conflict suppression (which behaviors to silence)
- Emotional modulation (intensity → audio parameter)

Ensures narrative flow and emotional continuity.

---

# 11. AUREXIS INTEGRATION

AUREXIS modifies orchestration output.
AUREXIS never binds sounds.

Inputs:
- Behavior metadata
- Emotional weight
- RTP mapping
- Event density/hour
- Fatigue index
- Device profile
- Volatility index
- Win magnitude
- Session duration

Adjustments:
- Dynamic panning
- Depth bias
- Energy normalization
- Attention gravity center
- Mix correction
- Fatigue compensation
- HF attenuation
- Transient smoothing
- Width narrowing/expansion
- Micro-variation (deterministic)

Output: DeterministicParameterMap (30+ fields, see AUREXIS_INTEGRATION_ARCHITECTURE.md §5)

---

# 12. VOICE ALLOCATION

## 12.1 Voice Pools (8)

| Pool | Max Voices | Steal Priority |
|------|-----------|----------------|
| Reel | 10 | core |
| Cascade | 8 | supporting |
| Win | 6 | core |
| Feature | 8 | core |
| Jackpot | 4 | critical |
| UI | 4 | ui |
| Ambient | 4 | ambient |
| Music | 4 | ambient |

## 12.2 Voice Steal Order

1. Lowest priority class
2. Oldest instance within same class
3. Lowest energy contribution

Deterministic. No random selection.

---

# 13. SIMULATION ENGINE

## 13.1 Simulation Modes

| Mode | Spins | Duration | Purpose |
|------|-------|----------|---------|
| Quick Sim | 100 | ~30s | Fast validation |
| Stress Sim | 1000+ | ~5min | Edge case detection |
| Session Sim | — | 30+ min | Fatigue curve analysis |
| Volatility Injection | Custom | Custom | Test specific volatility curves |
| RTP Shift | Custom | Custom | Test RTP deviation effects |
| Turbo/Autoplay | 1000+ | ~2min | Rapid-fire validation |

## 13.2 Simulation Outputs

| Output | Type | Description |
|--------|------|-------------|
| Fatigue curve | Graph | Session fatigue over time |
| Energy curve | Graph | Audio energy density over time |
| Emotional curve | Graph | Emotional state transitions |
| Collision map | Heatmap | Voice collision frequency by position |
| Event frequency heatmap | Heatmap | Which events fire most often |
| Silence gap detection | List | Gaps > threshold without audio |
| Layer dominance graph | Stacked bar | Which layers dominate audio |
| Escalation distribution | Histogram | Win escalation distribution |
| Voice peak analysis | Counter | Peak simultaneous voices |
| Steal event log | List | Every voice steal with context |

---

# 14. ANALYTICS FEEDBACK LOOP

Continuously monitors (real-time):

| Metric | Threshold | Warning |
|--------|-----------|---------|
| Event density/hour | > 500 | Over-triggering |
| RMS per behavior | > -6 dBFS | Clipping risk |
| Transient density/min | > 60 | Listener fatigue |
| Stereo width distribution | < 0.3 or > 1.8 | Mono collapse / phase issues |
| Override percentage | > 10% | Too many manual overrides |
| Manual hook ratio | > 15% | AutoBind naming needs improvement |
| Emotional drift | > 3 states/min | Unstable emotion |
| Fatigue growth rate | > 0.02/min | Excessive loudness |
| Silence gaps | > 2s during active | Missing audio coverage |

Warnings trigger visual indicators in Build Mode.

---

# 15. ERROR PREVENTION

System continuously validates and blocks:

| Error | Action |
|-------|--------|
| Duplicate hook attachment | Block — same hook cannot be on two nodes |
| Hook without state | Block — every hook must belong to a Behavior Node |
| Multiple overrides on same hook | Block — one override per hook maximum |
| Unmapped required state | Warning — required states must have audio |
| Detached sound file | Warning — file referenced but missing from disk |
| Cross-state leakage | Block — trigger cannot fire in wrong state |
| Circular dependency | Block — no circular state transitions |

Validation runs continuously in all modes.

---

# 16. VIEW MODES (4)

## 16.1 BUILD MODE (Default — 90% of workflow)

```
┌────────────────┬──────────────────────────────┬─────────────────┐
│ 🔍 [Search...] │  CONTEXT: [● Base] [○ FS]   │  INSPECTOR      │
│ [All▾] [S][M]  │  [○ Bonus] [○ H&W]          │                 │
│────────────────│──────────────────────────────│  Selected node: │
│ ▼ REELS 🟢    │  ┌────────────────────────┐   │  REELS/Stop     │
│   Stop         │  │ [▶ Spin] [⏭] [⏹]     │   │                 │
│   Land         │  │                        │   │  Sound Group:   │
│   Anticipation │  │  🎰 Slot Preview       │   │  [5 files]      │
│   Nudge        │  │     (interactive)      │   │  Playback: ⊙   │
│ ▼ CASCADE 🟢  │  └────────────────────────┘   │  one_shot       │
│   Start        │                              │                 │
│   Step         │  ┌────────────────────────┐   │  Priority: core │
│   End          │  │  Mini Timeline         │   │  Bus: SFX/Reels │
│ ▼ WIN 🟡      │  │  (auto-generated)      │   │  Variants: 3    │
│   Small        │  └────────────────────────┘   │  Mode: RR       │
│   Big ⚠️      │                              │                 │
│   Mega         │  ┌────────────────────────┐   │  ── Params ──   │
│   Countup      │  │  📁 DROP ZONE          │   │  [Basic ▾]      │
│ ▼ FEATURE 🔴  │  │  Drop folder for       │   │  Gain: 0 dB     │
│   Intro        │  │  AutoBind              │   │  Layer: reel    │
│   Loop         │  │                        │   │                 │
│   Outro        │  └────────────────────────┘   │  ── Hooks ──    │
│ ▼ JACKPOT 🟢  │                              │  🟢 onReelStop_r1│
│ ▼ UI 🟢       │                              │  🟢 onReelStop_r2│
│ ▼ SYSTEM 🟢   │                              │  🟢 onReelStop_r3│
│                │                              │  [+ Attach Hook]│
│ ───────────────│                              │                 │
│ COVERAGE: 92%  │                              │  ── Ducking ──  │
│ [██████████░]  │                              │  Music: -4dB    │
│                │                              │                 │
│ [Unmapped 1]   │                              │  ── AUREXIS ──  │
│ [Overrides 1]  │                              │  Width: +0.15   │
│ [Validate ✓]   │                              │  HF: -1.2dB    │
│                │                              │                 │
│                │                              │  ── Actions ──  │
│                │                              │  [▶ Audition▾]  │
│                │                              │  [🔄 Re-Bind]   │
│                │                              │  [📋 Copy]      │
└────────────────┴──────────────────────────────┴─────────────────┘
```

Features:
- Search field + filter presets at top of tree (§34)
- Context selector bar (§26) — switch between Base / Free Spins / Bonus / etc.
- Behavior tree with collapsible groups and smart collapsing (§18)
- Bind status colors per node (🟢🟡🔴)
- Solo (S) / Mute (M) per node in tree
- Slot preview with interactive spin (center)
- Mini timeline auto-generated from stage events (center)
- Drop zone for folder AutoBind with fuzzy matching (§6.3-6.4)
- Context-sensitive inspector (right) — shows: sound group, playback mode, priority, bus, variants, parameters, hooks, ducking rules, AUREXIS influence, quick actions
- Parameter tiers: Basic (default) → Advanced → Expert (§19)
- Audition dropdown: Solo Raw / Processed / In-Context / A/B (§20.1)
- Global coverage bar with quick filters (§17)
- Keyboard-driven navigation (§33)

## 16.2 FLOW MODE (Visualization)

```
┌──────────────────────────────────────────────────────────────────────┐
│  EMOTIONAL STATE GRAPH                                               │
│                                                                      │
│  [Neutral] ──▶ [Build] ──▶ [Tension] ──▶ [Near_Win]                │
│       ▲                                       │                      │
│       └── [Recovery] ◀── [Afterglow] ◀── [Release] ◀── [Peak]      │
│                                                                      │
│  Current: TENSION    Intensity: 0.72    Escalation Bias: +0.15      │
│                                                                      │
│  ── STAGE FLOW ──────────────────────────────────────────────────   │
│  SPIN → REEL_STOP[0-4] → EVALUATE → WIN/LOSS → [FEATURE?]         │
│    ↑                                                  │              │
│    └──────────────────────────────────────────────────┘              │
│                                                                      │
│  ── AUREXIS LIVE ────────────────────────────────────────────────   │
│  Fatigue: 34%  │  Voices: 8/48  │  Collision: 2 center  │  1.2x    │
└──────────────────────────────────────────────────────────────────────┘
```

Features:
- Emotional state transition graph with active path highlighted
- Stage flow diagram with current position
- AUREXIS live status bar
- Read-only — no editing

## 16.3 SIMULATION MODE

```
┌──────────────────────────────────────────────────────────────────────┐
│  [Quick 100] [Stress 1000] [Session 30min] [Custom...]   [▶ Run]    │
│                                                                      │
│  ── Fatigue Curve ───────────────────────────────────────────────   │
│  ████████████████████████░░░░░░░░░░  67%                            │
│  0min ──────────────────────────────────────────────────── 30min    │
│                                                                      │
│  ── Emotional Timeline ─────────────────────────────────────────   │
│  N·N·B·B·T·T·NW·R·P·A·R·N·N·B·T·R·N·N·N·B·B·T·NW·R·P·P·A·R·N  │
│                                                                      │
│  ── Energy Distribution ────────────────────────────────────────   │
│  ▁▂▃▅▇█▇▅▃▂▁▂▃▅▇█▇▅▃▂▁                                            │
│                                                                      │
│  ── Collision Heatmap ──────────────────────────────────────────   │
│  L ◄━━━━━━○━━━●●━━━━○━━━━━━━► R                                    │
│                                                                      │
│  ── Summary ────────────────────────────────────────────────────   │
│  Silence gaps: 3     Peak voices: 12     Steal events: 7           │
│  Layer dominance: REELS 45% │ WIN 30% │ MUSIC 15% │ UI 10%        │
│  Escalation: avg 1.3x │ max 4.2x │ distribution: normal           │
└──────────────────────────────────────────────────────────────────────┘
```

Features:
- One-click simulation presets
- Real-time curve rendering during simulation
- Emotional state timeline
- All 10 simulation outputs (§13.2)
- Read-only — no editing

## 16.4 DIAGNOSTIC MODE

```
┌──────────────────────────────────────────────────────────────────────┐
│  ── ENGINE HOOKS (ALL) ─────────────────────────────────────────   │
│  [Filter: All ▾]  [Sort: State ▾]  [Show: Unmapped Only ☐]        │
│                                                                      │
│  Hook                State           Bind        Node               │
│  onReelStop_r1       Reel_Stop       🟢 AUTO     REELS/Stop        │
│  onReelStop_r2       Reel_Stop       🟢 AUTO     REELS/Stop        │
│  onReelStop_r3       Reel_Stop       🟢 AUTO     REELS/Stop        │
│  onReelStop_r4       Reel_Stop       🟡 MANUAL   REELS/Stop        │
│  onCascadeStep       Cascade         🔴 OVERRIDE CASCADE/Step      │
│  onFeatureEnter      Feature         ❌ UNMAPPED  —                 │
│                                                                      │
│  ── AUREXIS RAW DATA ───────────────────────────────────────────   │
│  { stereo_width: 1.35, hf_attenuation_db: -3.2, fatigue: 0.67,    │
│    pan_drift: 0.02, escalation: 1.22, center_occupancy: 2, ... }   │
│                                                                      │
│  ── OVERRIDE DIFF ──────────────────────────────────────────────   │
│  3 manual overrides vs 42 auto-binds (6.7%)                        │
│                                                                      │
│  ── VOICE POOL ─────────────────────────────────────────────────   │
│  Active: 8/48  │  Virtual: 3  │  Peak: 14  │  Steals: 2           │
│  Pool breakdown: Reel 3 │ Win 2 │ Music 1 │ UI 1 │ Ambient 1      │
│                                                                      │
│  ── PERFORMANCE ────────────────────────────────────────────────   │
│  CPU: 1.2%  │  Memory: 12.4 MB  │  Loop overlap: 0  │  DSP: 0.8% │
│  Active voices per layer: Reel 3, Win 2, Music 1                   │
│  Mobile sim: ✅ within budget                                       │
└──────────────────────────────────────────────────────────────────────┘
```

Features:
- Full engine hook visibility with filters
- Raw AUREXIS DeterministicParameterMap data
- Override diff analysis
- Voice pool live status
- Performance metrics (CPU, memory, voices per layer, mobile sim)
- Advanced users only

---

# 17. HOOK COVERAGE PANEL

Always visible at bottom of Behavior Tree (Build Mode).

```
┌─ COVERAGE ──────────────────────────────────────────────┐
│  Total Hooks: 47                                         │
│  Auto Covered: 40 (85%)  ████████████████░░░             │
│  Manual Attached: 5 (11%) ██░░░░░░░░░░░░░░░░             │
│  Manual Override: 1 (2%)  ░░░░░░░░░░░░░░░░░░             │
│  Unmapped: 1 (2%)         ░░░░░░░░░░░░░░░░░░             │
│                                                          │
│  [Show Unmapped]  [Show Overrides]  [Validate All]       │
└──────────────────────────────────────────────────────────┘
```

Clicking "Show Unmapped" filters behavior tree to only show nodes with missing coverage.
Clicking "Validate All" runs full error prevention scan (§15).

---

# 18. SMART COLLAPSING RULES

Behavior Tree nodes auto-collapse/expand based on state:

## Auto-Collapse If:
- No manual override
- Default AutoBind mapping intact
- No parameter changes from defaults
- No validation warnings

## Auto-Expand If:
- Manual attach present
- Override exists
- Validation warning triggered
- Node is currently selected

## Group-Level:
- Group collapses if ALL children are auto-collapsed
- Group expands if ANY child has warning or override

---

# 19. PARAMETER TIERS (Progressive Disclosure)

## Tier 1: Basic (Default View)

| Parameter | Type | Description |
|-----------|------|-------------|
| Gain | dB | Volume offset |
| Priority Class | Enum | critical/core/supporting/ambient/ui/background |
| Layer Group | Enum | reel/cascade/win/feature/jackpot/ui/music/ambient |
| Variant Pool | Ref | Which variant group to use |

## Tier 2: Advanced (Expandable)

| Parameter | Type | Description |
|-----------|------|-------------|
| Escalation Bias | Float | Modifier for win escalation curve |
| Spatial Weight | Float | How much spatial processing applies |
| Energy Weight | Float | Contribution to energy density calculation |
| Fade Policy | Enum | auto/linear/exponential/none |

## Tier 3: Expert (Hidden by Default)

| Parameter | Type | Description |
|-----------|------|-------------|
| Raw Hook Modifier | JSON | Direct engine hook parameter override |
| AUREXIS Bias Override | Float | Override AUREXIS computation for this node |
| Execution Priority Override | Int | Force specific execution order |

Default: only Tier 1 visible.
Click "Advanced" → shows Tier 2.
Click "Expert" → shows Tier 3.

---

# 20. INSPECTOR PANEL (Context-Sensitive)

Right panel changes based on selected Behavior Node.

## When node selected:

```
┌─ INSPECTOR ─────────────────────────────────────────┐
│  REELS / Stop                                        │
│                                                      │
│  ── Sound Group ──                                   │
│  base_reel_stop_r1.wav         [▶] [✕]              │
│  base_reel_stop_r2.wav         [▶] [✕]              │
│  base_reel_stop_r3.wav         [▶] [✕]              │
│  [+ Add Sound]  [📁 Browse]                          │
│                                                      │
│  ── Parameters [Basic ▾] ──                          │
│  Gain:     ━━━━━━━━●━━━━━━  0 dB                    │
│  Priority: [core ▾]                                  │
│  Bus:      [SFX/Reels ▾]                             │
│  Variants: [Round Robin ▾]                           │
│                                                      │
│  ── Hooks (5 mapped) ──                              │
│  🟢 onReelStop_r1   auto                             │
│  🟢 onReelStop_r2   auto                             │
│  🟢 onReelStop_r3   auto                             │
│  🟢 onReelStop_r4   auto                             │
│  🟡 onReelStop_r5   manual                           │
│  [+ Attach Hook]                                     │
│                                                      │
│  ── AUREXIS Influence ──                             │
│  Width: +0.15  │  Pan drift: ±0.03  │  HF: -1.2dB  │
│  (from current volatility + session state)           │
│                                                      │
│  ── Quick Actions ──                                 │
│  [▶ Audition]  [🔄 Re-AutoBind]  [📋 Copy Config]   │
└──────────────────────────────────────────────────────┘
```

## When nothing selected:

Shows global project summary (coverage, warnings, AUREXIS status).

## 20.1 Audition Modes

The `[▶ Audition]` button supports multiple modes:

| Mode | Shortcut | Behavior |
|------|----------|----------|
| **Solo Raw** | Enter | Play selected node's sound in isolation, no processing |
| **Solo Processed** | Shift+Enter | Play with AUREXIS + DSP chain applied |
| **In-Context** | Ctrl+Enter | Play within full mix (all other nodes active, ducking applied) |
| **A/B Compare** | Alt+Enter | Alternate between two variants or two parameter states |

Additional audition features:
- **Solo/Mute per Node:** Click node icon in tree to solo (S) or mute (M)
- **Audition on Select:** Optional preference — auto-play when clicking a node
- **Loop Audition:** Hold Shift while clicking ▶ to loop playback
- **Scrub:** Drag timeline cursor while auditioning for seek

---

# 21. DETERMINISM GUARANTEE

Replay of identical spin sequence must produce identical audio output.

Requirements:
- Ordered state evaluation
- Stable priority rules
- Fixed voice steal order
- No random timing — all seed-based via xxhash3
- No uncontrolled concurrency
- Emotional state transitions are deterministic
- AUREXIS micro-variation uses hash(spriteId + eventTime + gameState + sessionIndex)

QA verification: AUREXIS ReplayVerifier (100 runs → identical output).

---

# 22. STRUCTURAL RULES (FINAL)

1. Behavior Layer is primary authoring interface
2. Engine Hook Layer is secondary (hidden by default)
3. AUREXIS modifies but never binds sounds
4. Emotional State Engine provides narrative context
5. No global raw hook list in default mode
6. AutoBind handles 80%+ of mapping workload
7. Manual hooks are contained and visible within their Behavior Node
8. System prevents duplicate logic, cross-state leakage, detached files
9. All required states must be covered or flagged
10. Deterministic execution guaranteed across all modes
11. 4 view modes serve different workflow stages
12. Parameter disclosure is progressive (Basic → Advanced → Expert)
13. Smart collapsing reduces visual noise in Build Mode
14. Coverage panel prevents hidden gaps
15. Analytics feedback loop catches problems before export

---

# 23. WHAT THIS REPLACES

This architecture replaces the current SlotLab structure:

| Current | New | Reason |
|---------|-----|--------|
| 7 super-tabs + 30 sub-tabs | 4 view modes + inspector | Too many choices → decision paralysis |
| UltimateAudioPanel (7 phases, manual drag-drop) | Behavior Tree + AutoBind | Manual → 90% automatic |
| Raw stage names (SPIN_START, REEL_STOP_0) | Behavior nodes (REELS/Stop) | Abstraction reduces cognitive load |
| Separate STAGES/EVENTS/MIX/DSP/BAKE tabs | Inspector panel (context-sensitive) | One place for everything |
| No emotional awareness | 8-state Emotional Engine | Narrative audio shaping |
| No simulation | 6 simulation modes with 10 outputs | Validation before export |
| No coverage tracking | Coverage panel with 4 categories | Prevents missing audio |
| No auto-binding | AutoBind + fuzzy matching | 3 clicks to sound, 90%+ coverage |
| No parameter tiers | Basic/Advanced/Expert | Progressive disclosure |
| No smart collapsing | Auto collapse/expand rules | Clean UI by default |
| Hard cuts between states | Transition Matrix (6 types) | Smooth, professional state changes |
| Flat tree (no game modes) | Context Layer (6 contexts) | Different audio per game mode |
| Music handled elsewhere | Integrated Music System | Loops, stingers, beat-sync, layers |
| No ducking relationships | Ducking Matrix per node | Mix clarity under voice pressure |
| No playback lifecycle | 6 Playback Modes per node | Correct loop/one-shot/sequence behavior |
| Manual bus assignment | Default Bus Mapping (auto) | 15-bus hierarchy with auto-routing |
| No undo for audio ops | Global Undo/Redo (100 steps) | Safe experimentation |
| Start from blank | 7 Project Templates | 80% of structure pre-built |
| No export pipeline | 7 export formats, 4 platforms | Production-ready output |
| Mouse-only workflow | 30+ keyboard shortcuts | Professional speed |
| No search/filter | Search + 7 filter presets | Find anything instantly |
| No comparison | Compare Mode (5 targets) | Validate changes side-by-side |
| No notifications | Toast notifications (5 types) | Async operation feedback |

---

# 24. PRODUCTION SYSTEMS (§25-§36)

The following sections define production-grade systems identified through expert review.
These systems fill gaps that would cause real-world integration failures.

Categories:
- §25-§29: Critical production systems (transitions, context, music, ducking, bus routing)
- §30-§32: Workflow systems (undo, templates, export)
- §33-§36: Quality-of-life (shortcuts, search, compare, notifications)

---

# 25. TRANSITION SYSTEM

Defines how audio transitions between gameplay states and emotional states.
Without this, state changes produce hard cuts, overlaps, and missing exit stingers.

## 25.1 Transition Matrix

Every State×State pair has a transition rule:

```
┌─────────────┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
│ FROM \ TO   │ Idle     │ Spin     │ Reel_Stop│ Win      │ Feature  │ Jackpot  │
├─────────────┼──────────┼──────────┼──────────┼──────────┼──────────┼──────────┤
│ Idle        │ —        │ Cut      │ —        │ —        │ XFade 1s │ Cut      │
│ Spin        │ —        │ —        │ Cut      │ —        │ —        │ —        │
│ Reel_Stop   │ Fade 0.5s│ —        │ —        │ Stinger  │ XFade 1s │ Stinger  │
│ Win         │ Fade 2s  │ Cut      │ —        │ —        │ XFade 1s │ —        │
│ Feature     │ XFade 2s │ Cut      │ —        │ Stinger  │ —        │ —        │
│ Jackpot     │ XFade 3s │ —        │ —        │ —        │ —        │ —        │
│ Cascade     │ Fade 1s  │ —        │ Cut      │ Stinger  │ —        │ —        │
└─────────────┴──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘
```

## 25.2 Transition Types

| Type | Behavior |
|------|----------|
| `cut` | Immediate stop of previous, immediate start of next |
| `crossfade` | Overlap with equal-power crossfade (configurable duration) |
| `fade_out_fade_in` | Fade previous to silence, then fade in next (gap allowed) |
| `stinger_bridge` | Play a stinger sound that bridges the two states |
| `tail_overlap` | Let previous tail ring out while next starts (reverb tails) |
| `beat_sync` | Wait for next beat/bar boundary before transitioning (music only) |

## 25.3 Transition Rule Structure

```json
{
  "from_state": "Win",
  "to_state": "Idle",
  "type": "crossfade",
  "duration_ms": 2000,
  "curve": "equal_power",
  "exit_stinger": null,
  "entry_delay_ms": 0,
  "keep_music": true,
  "duck_during_transition_db": -3.0
}
```

## 25.4 Emotional Transition Rules

Emotional state transitions also have audio rules:

| From → To | Audio Behavior |
|-----------|---------------|
| Any → Peak | Immediate intensity burst, no fade-in |
| Peak → Afterglow | Slow tail (2-3s reverb extension, width sustain) |
| Afterglow → Recovery | Gradual normalization (5s ramp to baseline) |
| Recovery → Neutral | Subtle fade, unnoticeable |
| Any → Tension | Gradual HF shimmer build (500ms ramp) |
| Tension → Release | Impact transient + instant width burst |

---

# 26. CONTEXT LAYER (Game Mode Switching)

Slot games have multiple game modes. Each mode changes the entire audio profile.

## 26.1 Contexts

| Context | Description | Audio Changes |
|---------|-------------|---------------|
| `base` | Normal base game | Default everything |
| `freespin` | Free Spins bonus | Different music, more intense reel stops, enhanced wins |
| `bonus` | Pick bonus / Wheel bonus | Unique music, simplified SFX, VO narration |
| `hold_and_win` | Hold & Win / Respins | Lock sounds, respawn SFX, progressive tension music |
| `gamble` | Double-or-Nothing | Tension music, card flip SFX, suspense |
| `jackpot_wheel` | Jackpot feature | Epic music, dramatic reveal SFX |

## 26.2 Context Override System

The Behavior Tree is context-aware. Each context can override any node:

```
REELS/Stop (base):       base_reel_stop_r3.wav       ← default
REELS/Stop (freespin):   freespin_reel_stop_r3.wav   ← override
REELS/Stop (bonus):      — (falls back to base)       ← no override, use default
```

Rules:
- If context has an override for a node → use override
- If context has no override → fall back to `base` context
- Context switch triggers Transition System (§25) rules
- AutoBind detects context from filename phase token (`freespin_`, `bonus_`, etc.)
- Each context can have its own AUREXIS profile (different volatility weighting)

## 26.3 Context UI in Build Mode

```
┌─ CONTEXT ──────────────────────────────┐
│  [● Base]  [○ Free Spins]  [○ Bonus]  │
│  [○ Hold & Win]  [○ Gamble]            │
│                                         │
│  Overrides: 12/22 nodes                 │
│  Inherited: 10/22 from Base             │
└─────────────────────────────────────────┘
```

Switching context in Build Mode shows which nodes have context-specific overrides (highlighted) and which fall back to base (dimmed).

---

# 27. MUSIC SYSTEM

Music in slot games is not a simple loop. It is a layered, context-aware, transition-sensitive system.

## 27.1 Music Structure

```
MUSIC SYSTEM
├── Base Layer (always playing, adjusts intensity via AUREXIS)
│   ├── base_music_low.wav        — Neutral/Recovery emotional states
│   ├── base_music_mid.wav        — Build/Tension states
│   └── base_music_high.wav       — Near_Win/Release states
│
├── Context Layers (replace base on context switch)
│   ├── freespin_music_loop.wav   — Free Spins context
│   ├── bonus_music_loop.wav      — Bonus context
│   └── holdwin_music_loop.wav    — Hold & Win context
│
├── Win Music (plays over base, ducks base)
│   ├── win_music_small.wav       — Plays for small wins (one-shot)
│   ├── win_music_big_loop.wav    — Loops for big wins
│   └── win_music_mega_loop.wav   — Loops for mega wins
│
└── Stingers (short musical accents, overlaid)
    ├── stinger_feature_enter.wav — On feature trigger
    ├── stinger_scatter_land.wav  — On scatter symbol
    └── stinger_jackpot_hit.wav   — On jackpot trigger
```

## 27.2 Music Behavior Rules

| Rule | Behavior |
|------|----------|
| Base music plays always | Seamless loop, crossfade between intensity layers |
| Context switch | Beat-synced crossfade to context music (§25 transition) |
| Win music | Plays OVER base, auto-ducks base by -8dB |
| Win music end | Crossfade back to base music over 1-2s |
| Stingers | One-shot, overlaid, no interruption to base |
| Feature music | Replaces base entirely, crossfade on enter/exit |
| Turbo mode | Music continues but tempo may scale |
| Autoplay | Music continues uninterrupted across spins |

## 27.3 Music Integration with Behavior Tree

Music is NOT a Behavior Node — it runs parallel to the node system.

```
BEHAVIOR TREE (event-driven)          MUSIC SYSTEM (continuous)
        │                                      │
        │ onWinEvaluate ──────────────→ Play win_music_big_loop
        │ onFeatureEnter ─────────────→ Crossfade to freespin_music
        │ onFeatureExit ──────────────→ Crossfade back to base
        │                                      │
        └──── Both feed into ────────→ ORCHESTRATION ENGINE
```

Music intensity is modulated by AUREXIS fatigue + emotional state.

## 27.4 Stinger System

Stingers fire on specific triggers and play on top of everything:

| Stinger | Trigger | Priority | Duck Others |
|---------|---------|----------|-------------|
| Feature Enter | onFeatureEnter | critical | -6dB all except self |
| Scatter Land | onSymbolLand (scatter) | core | none |
| Jackpot Hit | onJackpotReveal | critical | -12dB all except self |
| Near Win | onAnticipationEnd (win) | supporting | none |
| Mega Win | onWinEvaluate (tier 4-5) | critical | -6dB music |

Stingers have beat-sync option: wait for next beat boundary before playing.

---

# 28. DUCKING MATRIX

Defines per-behavior-node volume relationships.
When behavior A plays, what happens to behavior B?

## 28.1 Default Ducking Rules

| Source (playing) | Target (ducked) | Amount | Attack | Release | Hold |
|-----------------|-----------------|--------|--------|---------|------|
| WIN/Big,Mega | MUSIC | -8 dB | 50ms | 500ms | duration |
| WIN/Big,Mega | REELS | -4 dB | 50ms | 300ms | duration |
| JACKPOT/* | ALL except self | -12 dB | 20ms | 1000ms | duration |
| FEATURE/Intro | ALL except MUSIC | -6 dB | 100ms | 800ms | 2000ms |
| WIN/Countup | MUSIC | -4 dB | 50ms | 200ms | tick |
| REELS/Anticipation | MUSIC | -3 dB | 200ms | 500ms | duration |
| UI/* | nothing | 0 dB | — | — | — |

## 28.2 Ducking Rule Structure

```json
{
  "source_node": "win_big",
  "target_category": "music",
  "duck_amount_db": -8.0,
  "attack_ms": 50,
  "release_ms": 500,
  "hold_mode": "duration",
  "curve": "exponential",
  "enabled": true
}
```

`hold_mode` options:
- `duration` — duck for entire duration of source sound
- `tick` — duck per trigger, release between triggers
- `fixed` — duck for fixed `hold_ms` regardless of source length
- `manual` — duck until explicit stop command

## 28.3 AUREXIS Ducking Modulation

AUREXIS can modify ducking amounts based on context:
- High fatigue → reduce ducking depths (everything gets quieter anyway)
- High escalation → increase ducking contrast (make wins stand out more)
- High voice density → increase ducking to prevent mud

---

# 29. DEFAULT BUS MAPPING

Every Behavior Node category has a default bus route.

## 29.1 Bus Hierarchy

```
MASTER (0)
├── MUSIC (1)
│   ├── Music_Base (10)
│   ├── Music_Wins (11)
│   └── Music_Feature (12)
├── SFX (2)
│   ├── SFX_Reels (20)
│   ├── SFX_Wins (21)
│   ├── SFX_Anticipation (22)
│   ├── SFX_Cascade (23)
│   └── SFX_Jackpot (24)
├── VOICE (3)
│   ├── VO_Announcer (30)
│   └── VO_Celebration (31)
├── UI (4)
│   └── UI_Feedback (40)
└── AMBIENCE (5)
    └── Ambience_Casino (50)
```

## 29.2 Default Category → Bus Mapping

| Behavior Category | Default Bus | Reasoning |
|-------------------|-------------|-----------|
| REELS/* | SFX_Reels (20) | Core gameplay SFX |
| CASCADE/* | SFX_Cascade (23) | Cascade-specific processing |
| WIN/Small,Big,Mega | SFX_Wins (21) | Win SFX |
| WIN/Countup | SFX_Wins (21) | Win presentation |
| FEATURE/* | Music_Feature (12) | Feature-specific bus |
| JACKPOT/* | SFX_Jackpot (24) | Jackpot-specific processing |
| UI/* | UI_Feedback (40) | UI sounds |
| SYSTEM/* | UI_Feedback (40) | System notifications |
| MUSIC (base) | Music_Base (10) | Base game music |
| MUSIC (win) | Music_Wins (11) | Win celebration music |
| AMBIENCE | Ambience_Casino (50) | Background ambience |

AutoBind assigns default bus automatically. Designer can override per-node in Inspector.

---

# 30. GLOBAL UNDO/REDO

All operations in Build Mode are undoable.

## 30.1 Undoable Operations

| Operation | Undo Behavior |
|-----------|---------------|
| AutoBind batch (folder drop) | Remove all auto-binds from that batch |
| Manual hook attach | Detach hook, restore previous state |
| Manual hook override | Restore original auto-bind |
| Parameter change | Restore previous value |
| Sound add/remove | Restore/remove sound from node |
| Context override | Remove override, revert to base |
| Bus route change | Restore previous bus |
| Ducking rule change | Restore previous rule |
| Transition rule change | Restore previous transition |

## 30.2 Undo Stack

- Maximum 100 undo steps
- Batch operations (folder drop) count as 1 step
- Undo/Redo state persists with project save
- Keyboard: Cmd+Z (undo), Cmd+Shift+Z (redo)

---

# 31. PROJECT TEMPLATES

Pre-built configurations for common slot game types.
Designers don't start from zero — they start from a template and customize.

## 31.1 Built-in Templates

| Template | Reels | Nodes | Context | Description |
|----------|-------|-------|---------|-------------|
| **Standard 5-Reel** | 5×3 | 22 | Base, FreeSpin | Classic video slot |
| **Megaways** | 6×2-7 | 28 | Base, FreeSpin | Variable reel sizes, cascade |
| **Hold & Win** | 5×3 | 25 | Base, HoldWin | Respins with locked symbols |
| **Cluster Pays** | 7×7 | 20 | Base, FreeSpin | Grid-based, no paylines |
| **Jackpot Wheel** | 5×3 | 30 | Base, FreeSpin, JackpotWheel | Multi-tier jackpot |
| **Buy Feature** | 5×3 | 24 | Base, FreeSpin, Bonus | Purchasable feature |
| **Blank** | Custom | 0 | Base only | Empty starting point |

## 31.2 Template Contents

Each template provides:
- Behavior Tree structure (which nodes exist)
- Default bus routing per node
- Default priority classes
- Default playback modes
- Transition matrix for included contexts
- Ducking matrix defaults
- Suggested folder structure for AutoBind naming
- Music system skeleton (which loops/stingers expected)
- AUREXIS profile recommendation

## 31.3 Template Workflow

```
1. New Project → Select Template
2. Template creates Behavior Tree + defaults
3. User drops audio folder → AutoBind maps to template nodes
4. Coverage panel shows what's still needed
5. User customizes parameters
6. Done
```

---

# 32. EXPORT PIPELINE

Defines how finished SlotLab projects are exported for integration.

## 32.1 Export Formats

| Format | Target | Contents |
|--------|--------|----------|
| **FluxForge Package** (.ffpkg) | FluxForge runtime | Complete project: audio + config + AUREXIS params |
| **Wwise SoundBank** (.bnk) | Wwise integration | Events, buses, RTPC, state groups |
| **FMOD Bank** (.bank) | FMOD integration | Events, buses, parameters |
| **Unity Asset** (.unitypackage) | Unity direct | Audio clips + ScriptableObject config |
| **Raw Stems** (.wav) | Any engine | Per-bus audio stems, per-event bounces |
| **JSON Manifest** (.json) | Custom engines | Complete configuration without audio |
| **Compliance Report** (.pdf/.html) | Regulators | GLI-11, jurisdiction compliance data |

## 32.2 Per-Platform Export

| Platform | Processing |
|----------|-----------|
| Desktop (Stereo) | Full quality, full stereo width |
| Mobile (Mono-safe) | Mono compatibility check, compressed formats, reduced voice count |
| Cabinet (Filtered) | Speaker profile EQ, reduced dynamic range, ambient noise compensation |
| Headphones (Enhanced) | Widened stereo, M/S boost, intimate mix |

## 32.3 AUREXIS Parameter Baking

Export can optionally "freeze" AUREXIS intelligence into static parameters:
- Bake current volatility profile into fixed DSP settings
- Bake fatigue compensation as static EQ curve
- Bake collision redistribution as fixed pan positions

Baked export is simpler to integrate but loses runtime intelligence.
Unbaked export requires AUREXIS runtime library in target engine.

---

# 33. KEYBOARD SHORTCUTS

Professional workflow requires keyboard-driven operation.

## 33.1 Global Shortcuts

| Shortcut | Action |
|----------|--------|
| `Space` | Spin (in any mode) |
| `Escape` | Stop playback / Deselect |
| `Cmd+Z` | Undo |
| `Cmd+Shift+Z` | Redo |
| `Cmd+S` | Save project |
| `Cmd+F` | Search behavior tree |

## 33.2 View Mode Switching

| Shortcut | Mode |
|----------|------|
| `1` | BUILD mode |
| `2` | FLOW mode |
| `3` | SIMULATION mode |
| `4` | DIAGNOSTIC mode |

## 33.3 Build Mode Navigation

| Shortcut | Action |
|----------|--------|
| `↑/↓` | Navigate behavior tree |
| `←/→` | Collapse/expand node group |
| `Enter` | Audition selected node (Solo Raw) |
| `Shift+Enter` | Audition processed |
| `Ctrl+Enter` | Audition in-context |
| `Tab` | Jump to next unmapped node |
| `Shift+Tab` | Jump to previous unmapped node |
| `S` | Solo selected node |
| `M` | Mute selected node |
| `Cmd+D` | Duplicate node configuration |
| `Delete` | Remove sound from node |
| `Cmd+C / Cmd+V` | Copy/Paste node configuration |

## 33.4 Simulation Mode

| Shortcut | Action |
|----------|--------|
| `Q` | Quick Sim (100 spins) |
| `W` | Stress Sim (1000 spins) |
| `E` | Session Sim (30 min) |
| `Space` | Start/Pause simulation |
| `Escape` | Stop and reset |

---

# 34. SEARCH AND FILTER

## 34.1 Behavior Tree Search

Search field at top of Behavior Tree (Build Mode):

```
┌─ 🔍 Search: [cascade_______] ─────────────────┐
│                                                  │
│  Results:                                        │
│  ▼ CASCADE (3 matches)                           │
│    🟢 Start                                      │
│    🟢 Step                                       │
│    🟢 End                                        │
└──────────────────────────────────────────────────┘
```

Search matches against:
- Node names (cascade, stop, win)
- Hook names (onCascadeStep)
- Sound filenames (base_cascade_step.wav)
- Bus routes (SFX_Cascade)
- Tags and labels

## 34.2 Filter Presets

Quick filters in Build Mode toolbar:

| Filter | Shows |
|--------|-------|
| `All` | All nodes |
| `Unmapped` | Only nodes with missing coverage |
| `Overrides` | Only nodes with manual overrides |
| `Warnings` | Only nodes with validation warnings |
| `Context: X` | Only nodes with overrides in context X |
| `Priority: X` | Only nodes with specific priority class |
| `Bus: X` | Only nodes routed to specific bus |

---

# 35. COMPARE MODE

Side-by-side comparison for validation and review.

## 35.1 Compare Targets

| Comparison | Left Panel | Right Panel |
|------------|-----------|-------------|
| **Context vs Context** | Base game | Free Spins |
| **Before vs After** | Last saved state | Current state |
| **Project vs Project** | Project A | Project B |
| **Raw vs Processed** | Without AUREXIS | With AUREXIS |
| **Platform vs Platform** | Desktop mix | Mobile mix |

## 35.2 Compare UI

```
┌──────────────────────┬──────────────────────┐
│  BASE GAME           │  FREE SPINS          │
│                      │                      │
│  REELS/Stop 🟢      │  REELS/Stop 🟡      │
│  3 sounds            │  5 sounds (override) │
│  Bus: SFX_Reels      │  Bus: SFX_Reels      │
│  Gain: 0 dB          │  Gain: +2 dB ⚡      │
│                      │                      │
│  WIN/Big 🟢          │  WIN/Big 🟢         │
│  2 sounds            │  2 sounds (same)     │
│  Bus: SFX_Wins       │  Bus: SFX_Wins       │
│                      │                      │
│  ⚡ = different from left panel              │
│  [▶ Audition Left]  [▶ Audition Right]      │
└──────────────────────┴──────────────────────┘
```

Differences highlighted with ⚡ indicator.
Can audition left or right independently.

---

# 36. NOTIFICATION SYSTEM

Toast-style notifications for async operations and warnings.

## 36.1 Notification Types

| Type | Color | Duration | Example |
|------|-------|----------|---------|
| **Success** | Green | 3s auto-dismiss | "AutoBind complete: 38/45 files mapped" |
| **Warning** | Yellow | Sticky until dismissed | "3 required nodes have no audio" |
| **Error** | Red | Sticky until dismissed | "Audio file not found: reel_stop_r4.wav" |
| **Info** | Blue | 5s auto-dismiss | "Simulation complete: 100 spins processed" |
| **Progress** | Blue | Until complete | "AutoBind scanning... 24/45 files" |

## 36.2 Notification Queue

- Maximum 3 visible simultaneously
- Older notifications stack below
- Click to dismiss
- Click notification body to navigate to relevant node
- History accessible via notification bell icon

---

# 37. LAYOUT & PROJECT INITIALIZATION

Defines how reel layouts and project structure are created.
Two entry paths converge into the same middleware pipeline.

## 37.1 Dual-Path Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  PROJECT INITIALIZATION                  │
│                                                         │
│   PATH A: GDD Import          PATH B: Template Preset   │
│   ┌───────────────┐           ┌───────────────┐        │
│   │ JSON/PDF file │           │ Select preset │        │
│   │ (math model,  │           │ (Standard 5×3,│        │
│   │  symbols,     │           │  Megaways,    │        │
│   │  features,    │           │  Hold & Win,  │        │
│   │  paytable)    │           │  Cluster,     │        │
│   └──────┬────────┘           │  Jackpot,     │        │
│          ↓                    │  Buy Feature, │        │
│   GddImportService            │  Blank)       │        │
│   ├─ Parse & validate         └──────┬────────┘        │
│   ├─ GameDesignDocument              ↓                  │
│   ├─ Auto-generate 50+ stages  Template populates:     │
│   ├─ Symbol definitions        ├─ Grid config          │
│   ├─ Grid config               ├─ Default symbols      │
│   ├─ Feature definitions       ├─ Behavior tree        │
│   └─ Win tier mapping          ├─ Bus routing          │
│          ↓                     ├─ Priority classes      │
│          ↓                     ├─ Base stages           │
│   ┌──────┴─────────────────────┴──────┐                │
│   │        AutoBind Engine (§6)       │                │
│   │   GDD path: 90%+ auto-coverage   │                │
│   │   Template path: 70%+ coverage    │                │
│   └──────────────┬────────────────────┘                │
│                  ↓                                      │
│   ┌──────────────────────────────────┐                 │
│   │     Fine-Tune / Manual Polish    │                 │
│   │   ├─ ReelStripEditor (Advanced)  │                 │
│   │   ├─ Symbol overrides            │                 │
│   │   ├─ Per-reel weight adjustment  │                 │
│   │   ├─ Custom stage assignment     │                 │
│   │   └─ Coverage panel → fill gaps  │                 │
│   └──────────────┬────────────────────┘                │
│                  ↓                                      │
│   ════════════ MIDDLEWARE PIPELINE ════════════          │
│   (Same regardless of entry path)                       │
└─────────────────────────────────────────────────────────┘
```

## 37.2 GDD Import Path (Primary — 90% of projects)

**Entry:** File picker or drag-drop JSON onto SlotLab.

**JSON Format:**
```json
{
  "name": "Game Name",
  "version": "1.0",
  "grid": {
    "reels": 5,
    "rows": 3,
    "mechanic": "lines|ways|cluster|megaways",
    "paylines": 20
  },
  "symbols": [
    {
      "id": "diamond",
      "name": "Diamond",
      "tier": "premium|high|mid|low|wild|scatter|bonus",
      "payouts": { "3": 50, "4": 200, "5": 1000 }
    }
  ],
  "features": [
    {
      "id": "freespins",
      "type": "free_spins|bonus|hold_and_spin|cascade|gamble|jackpot",
      "triggerCondition": "3+ scatter",
      "initialSpins": 10
    }
  ],
  "math": {
    "rtp": 0.965,
    "volatility": "high",
    "hitFrequency": 0.25
  }
}
```

**Pipeline:**
1. `GddImportService.importFromJson(input)` — parse & validate
2. `GddValidatorService.validateDocument()` — bounds, consistency, audio readiness
3. `GameDesignDocument` → `SlotLabProjectProvider` — populate state
4. Auto-generate stages (REEL_STOP_0..N, SYMBOL_LAND_*, WIN_*, FS_*, etc.)
5. Auto-generate symbol definitions with audio contexts
6. `GameDesignDocument.toRustJson()` → Rust engine format

**Validation Rules:**
- Grid: 1-10 reels, 1-10 rows
- Symbols: 8+ required, unique IDs
- Payouts: must increase with match count
- RTP: 80-100% range
- Features: must reference existing symbols

## 37.3 Template Preset Path (Secondary — 10% of projects)

**Entry:** New Project → Template selector dialog.

**Templates** (from §31):
- Standard 5-Reel (5×3, 22 nodes, Base+FreeSpin)
- Megaways (6×2-7, 28 nodes, variable rows, cascade)
- Hold & Win (5×3, 25 nodes, respins with locked symbols)
- Cluster Pays (7×7, 20 nodes, grid-based)
- Jackpot Wheel (5×3, 30 nodes, multi-tier jackpot)
- Buy Feature (5×3, 24 nodes, purchasable feature)
- Blank (custom grid, 0 nodes, empty starting point)

**Template provides:**
- Grid configuration (reels × rows)
- Default 13-symbol set (HP1-4, LP1-6, Wild, Scatter, Bonus)
- Behavior tree structure with all expected nodes
- Default bus routing, priority classes, playback modes
- Transition matrix and ducking matrix defaults
- Suggested folder structure for AutoBind naming conventions
- Music system skeleton (expected loops/stingers)

**After template:**
1. User drops audio folder → AutoBind maps files to template nodes
2. Coverage panel shows bound vs unbound nodes
3. User fills gaps manually
4. Fine-tune parameters as needed

## 37.4 Manual Fine-Tuning (Both Paths)

**ReelStripEditor** — available as "Advanced" option in Build Mode:
- Visual grid: all reels side-by-side
- Drag-drop symbol reordering within reel strips
- Add/remove symbols via context menu
- Symbol palette for quick assignment
- Per-reel strip length (default 32, variable per reel)
- Statistics: symbol distribution, hit frequency estimate

**Symbol Override:**
- Edit type, tier, payouts per symbol
- Add custom audio contexts per symbol
- Per-reel weight adjustment (override default tier-based weights)

**When to use manual:**
- After GDD import: fix symbols that parser missed
- After template: add game-specific symbols
- Megaways: set variable row counts per reel
- Custom mechanics: non-standard symbol behavior

## 37.5 Grid Flexibility Matrix

| Grid Type | Reels | Rows | Mechanic | AutoBind Coverage |
|-----------|-------|------|----------|-------------------|
| Classic | 3-5 | 3 | Lines (1-20) | 95% |
| Standard | 5 | 3-5 | Lines (20-50) | 95% |
| Ways | 5-6 | 3-4 | Ways (243-1024) | 90% |
| Megaways | 6 | 2-7 variable | Ways (117,649) | 85% |
| Cluster | 5-8 | 5-8 | Cluster (5+ match) | 85% |
| Hold & Win | 5 | 3-4 | Respin locked | 90% |
| Custom | 1-10 | 1-10 | Any | 70% |

## 37.6 Convergence Guarantee

Both paths produce identical output for the middleware pipeline:
- `SlotLabProjectProvider` with populated grid, symbols, stages
- Behavior tree structure (from GDD auto-gen or template preset)
- Audio assignments (from AutoBind, manual, or both)
- Win tier configuration (from GDD math model or template defaults)

**The slot preview widget, middleware pipeline, AUREXIS, and all downstream systems are path-agnostic.** They receive the same data structures regardless of how the project was initialized.

---

# 38. SLOT PREVIEW WIDGET

Defines the scope and boundaries of the interactive slot machine preview.

## 38.1 Core Principle

The Slot Preview Widget is a **pure presentation layer**. It renders reel animations, win presentations, and visual effects based entirely on data received from providers. It contains **zero game logic**.

## 38.2 What Stays (No Changes)

| Component | LOC | Description |
|-----------|-----|-------------|
| Reel animation engine | ~400 | Professional spin→decel→stop→bounce phases |
| IGT sequential buffer | ~250 | Handles out-of-order reel stop callbacks |
| Win presentation (3-phase) | ~1,200 | Symbol highlight → plaque → win lines |
| P5 Win Tier system | ~600 | Data-driven tiers, labels, rollup durations |
| Anticipation system | ~800 | Scatter detection, sequential mode, L1-L4 tension |
| Cascade system | ~200 | Pop animation, burst particles, cascade steps |
| Particle system | ~400 | Object pool, win/celebration/anticipation particles |
| Visual effects | ~600 | Vignette, screen flash, camera zoom, screen shake |
| Rollup counter | ~300 | RTL digit animation, tier-based timing |
| Space key (stop) | ~100 | Immediate halt, fast-forward to result |

**Total preserved: ~4,850 LOC (79%)**

## 38.3 What Gets Added (Overlay Extensions)

| Addition | LOC | Description |
|----------|-----|-------------|
| Context indicator | ~30 | Badge showing current game mode (BASE / FREESPIN / BONUS / HOLD_WIN) |
| Emotional state overlay | ~80 | Subtle ambient glow color driven by AUREXIS emotional state |
| Transition feedback | ~60 | Visual indicator during active audio transitions (crossfade bar, stinger flash) |
| Diagnostic overlay | ~50 | Active behavior node name + state (only visible in Diagnostic view mode) |

**Total additions: ~220 LOC (4%)**

## 38.4 Implementation Rules

All additions are **visual overlay layers** added to the existing Stack widget:

```
Existing layers (bottom to top):
  1. Reel Table
  2. Anticipation Vignette
  3. Anticipation Particles
  4. Big Win Background
  5. Win Lines
  6. Win Particles
  7. Screen Flash
  8. Win Overlay (plaque + counter)

New layers (inserted):
  1.5  Context Badge (top-left corner, small pill)
  2.5  Emotional State Ambient (full-frame, ~5% opacity color wash)
  7.5  Transition Indicator (bottom bar, 3px height)
  9.   Diagnostic Overlay (top-right, monospace text, only in Diagnostic mode)
```

**Rules:**
- NO modification to existing layers
- NO changes to spin lifecycle or win detection logic
- New layers receive data from providers via `Consumer` widgets
- Emotional state color map: Neutral=none, Build=blue, Tension=amber, Near_Win=orange, Release=green, Peak=gold, Afterglow=warm_white, Recovery=cool_blue
- Context badge only shows when context ≠ base_game
- Diagnostic overlay hidden unless `ViewModeProvider.current == diagnostic`

## 38.5 Provider Communication (Unchanged)

**Input from providers:**
- `SlotLabProvider.lastResult` → spin result with grid, wins
- `SlotLabProvider.lastStages` → timing stages
- `SlotLabProjectProvider.winConfiguration` → tier thresholds, labels
- NEW: `AurexisProvider.emotionalState` → emotional state enum
- NEW: `MiddlewareProvider.activeContext` → current game mode
- NEW: `MiddlewareProvider.activeTransition` → transition type (if any)
- NEW: `ViewModeProvider.currentMode` → build/flow/simulation/diagnostic

**Output to EventRegistry (unchanged):**
- `REEL_STOP_${idx}`, `SYMBOL_LAND_*`, `WIN_PRESENT_*`, `BIG_WIN_*`, `ANTICIPATION_*`

---

# 39. RESULT

This architecture provides:

**Core System (§1-§15):**
- 10-layer execution pipeline with no bypass paths
- Behavior abstraction: 300+ hooks → ~22 designer-facing nodes
- AutoBind with fuzzy matching: 90%+ automatic coverage
- Priority engine: 6 classes with duck/delay/suppress resolution
- Emotional state engine: 8 states driving narrative audio
- AUREXIS intelligence: 30+ real-time audio parameters
- Voice allocation: 8 pools with deterministic stealing
- Simulation engine: 6 modes, 10 output types
- Analytics feedback loop: 9 real-time thresholds
- Error prevention: 7 continuous validations

**Production Features (§25-§32):**
- Transition system: state-to-state audio transitions with 6 types
- Context layer: 6 game modes with per-node overrides and fallback
- Music system: layered loops, stingers, beat-sync transitions
- Ducking matrix: per-node volume relationships with AUREXIS modulation
- Playback modes: 6 lifecycle types per behavior node
- Default bus mapping: 15-bus hierarchy with auto-routing
- Variant system: 5 selection modes with deterministic history
- Global undo/redo: 100-step stack for all operations
- Project templates: 7 built-in game type starters
- Export pipeline: 7 formats, 4 platform profiles, AUREXIS baking

**Workflow Quality (§33-§36):**
- 30+ keyboard shortcuts for professional speed
- Search/filter with 7 quick-filter presets
- Compare mode: 5 comparison targets with audition
- Notification system: 5 types with navigation
- 4 view modes: Build (90%), Flow, Simulation, Diagnostic
- Progressive disclosure: Basic → Advanced → Expert parameters
- Smart collapsing: auto-hide clean nodes, auto-show problems
- Inspector panel: context-sensitive, one place for all node editing
- Audition modes: Solo Raw, Solo Processed, In-Context, A/B Compare

**Layout & Initialization (§37-§38):**
- Dual-path project initialization: GDD Import (90%) + Template Preset (10%)
- GDD-First workflow: JSON parse → auto-stage generation → AutoBind → fine-tune
- Template-First workflow: preset selection → AutoBind → manual polish
- Both paths converge into identical middleware pipeline
- ReelStripEditor preserved as Advanced fine-tuning tool
- Grid flexibility: 1-10 reels, 1-10 rows, all mechanics supported
- Slot Preview Widget: pure presentation layer, 95% unchanged
- 4 new visual overlays (~220 LOC): context badge, emotional state, transition, diagnostic
- Path-agnostic guarantee: downstream systems identical regardless of entry path

**Guarantees:**
- Deterministic execution across all platforms
- Zero structural ambiguity
- No undefined execution paths
- No bypass paths possible
- Commercial-grade stability
- GLI-11 / ISO 17025 compliance support

This is the complete SlotLab Middleware Architecture.
39 sections. Zero gaps.

---

*© FluxForge Studio — SlotLab Middleware Architecture v6.0 FINAL (Expert-Reviewed)*
*Consolidated from v1 + v2 + v3 + Expert Gap Analysis + Layout/Preview Architecture*
*Sections 1-24: Core (consolidated from v1/v2/v3)*
*Sections 25-36: Expert additions (transitions, context, music, ducking, bus, undo, templates, export, shortcuts, search, compare, notifications)*
*Sections 37-38: Layout initialization (GDD/Template dual-path) + Slot Preview Widget scope*
*Date: 2026-02-28*
