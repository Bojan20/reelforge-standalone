# SLOT LAB MIDDLEWARE – ULTIMATE ARCHITECTURE SPEC
## FluxForge Studio
## AUREXIS Integrated
## Version 2.0 – Complete Structural Definition
## Generated: 2026-02-24

---
# 0. PURPOSE

This document defines the complete, production‑grade internal architecture of SlotLab middleware.

Scope:
- 300–1000+ engine hooks
- State-driven execution
- Behavior abstraction layer
- Priority resolution
- Orchestration engine
- AUREXIS intelligence integration
- Deterministic simulation
- Manual hook precision without structural chaos

No conceptual gaps. No undefined layers.

---
# 1. CORE ARCHITECTURAL PRINCIPLE

SlotLab is:

STATE‑DRIVEN  
BEHAVIOR‑ABSTRACTED  
HOOK‑MAPPED  
PRIORITY‑RESOLVED  
ORCHESTRATED  
AUREXIS‑MODIFIED  
DETERMINISTIC  

Engine hooks are input signals.  
Behavior events are authoring abstractions.  
Orchestration is intelligence.  
DSP execution is the final stage.

---
# 2. COMPLETE EXECUTION PIPELINE

ENGINE TRIGGER  
↓  
STATE GATE  
↓  
BEHAVIOR EVENT RESOLUTION  
↓  
PRIORITY ENGINE  
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

Each layer is mandatory.

---
# 3. ENGINE TRIGGER LAYER

Input from game runtime.

Examples:
- onReelStop_r1
- onReelStop_r2
- onCascadeStep
- onWinEvaluate
- onCountUpTick
- onFeatureEnter
- onJackpotReveal

Characteristics:
- Stateless
- Context‑agnostic
- High frequency
- Potentially noisy

No audio logic allowed here.

---
# 4. STATE GATE LAYER

Validates whether trigger may propagate.

Inputs:
- Current game state
- Substate (Spin, Reel_Stop, Cascade, Win, Feature)
- Volatility index
- Feature flags
- Autoplay/Turbo
- Session fatigue level

Responsibilities:
- Block invalid triggers
- Prevent duplicate execution
- Prevent cross‑state leakage
- Enforce deterministic order

State is the first stability wall.

---
# 5. BEHAVIOR EVENT LAYER

Primary authoring abstraction.

Behavior Event is NOT equal to engine hook.

Example:

Behavior Event: REEL_STOP

Internally maps to:
- onReelStop_r1
- onReelStop_r2
- onReelStop_r3
- onReelStop_r4
- onReelStop_r5

Behavior Node Structure:

{
  id: "reel_stop",
  state: "Reel_Stop",
  mapped_hooks: [...],
  priority_class: "core",
  layer_group: "reel",
  escalation_policy: "incremental",
  orchestration_profile: "reel_standard"
}

Manual hook attachment occurs here only.  
No hook exists outside a Behavior Event.

---
# 6. PRIORITY ENGINE

Each Behavior Event has a priority_class:

- critical
- core
- supporting
- ambient
- ui
- background

Rules:
1. Higher class preempts lower.
2. Same class resolves by recency, escalation weight, voice availability.
3. Lower priority may duck, delay, or suppress.

Prevents audio collision chaos.

---
# 7. ORCHESTRATION ENGINE

Input:
- Active behaviors
- Escalation index
- Chain depth
- Multiplier level
- Win magnitude
- Volatility curve
- Session fatigue

Output decisions:
- Trigger delay
- Gain bias
- Stereo width scaling
- Spatial bias
- Transient shaping
- Layer blend ratios
- Suppression of conflicting behaviors

Ensures emotional continuity and tension shaping.

---
# 8. AUREXIS INTEGRATION

AUREXIS modifies orchestration output.

Inputs:
- Behavior metadata
- Emotional weight
- RTP mapping
- Event density/hour
- Fatigue index
- Device profile

Adjustments:
- Dynamic panning
- Depth bias
- Energy normalization
- Attention gravity center
- Dynamic mix correction

AUREXIS never binds sounds.

---
# 9. VOICE ALLOCATION STRATEGY

Voice pools:
- Reel
- Cascade
- Win
- Feature
- Jackpot
- UI
- Ambient
- Music

Voice Steal Order:
1. Lowest priority
2. Oldest instance
3. Lowest energy contribution

Deterministic execution guaranteed.

---
# 10. SIMULATION ENGINE

Supports:
- Quick Sim (100 spins)
- Stress Sim (1000+ spins)
- Session Sim (30+ minutes)
- Volatility injection
- RTP shift
- Turbo/autoplay

Outputs:
- Event frequency heatmap
- Fatigue curve
- Collision index
- Silence gap detection
- Layer dominance graph
- Escalation distribution

---
# 11. ANALYTICS FEEDBACK LOOP

Continuously measures:
- Event density/hour
- RMS per behavior
- Transient density
- Stereo width distribution
- Override percentage
- Manual hook ratio

Warnings triggered when thresholds exceeded.

---
# 12. MANUAL HOOK POLICY

Manual Hook Rules:
1. Must belong to Behavior Event.
2. Cannot exist independently.
3. Cannot bypass state gate.
4. Cannot bypass orchestration.
5. Must remain visible in coverage panel.

---
# 13. VIEW MODES

BUILD MODE  
FLOW MODE  
SIMULATION MODE  
DIAGNOSTIC MODE  

Default is Build Mode.

---
# 14. DETERMINISM GUARANTEE

Replay of identical spin sequence must produce identical audio output.

Requires:
- Ordered state evaluation
- Stable priority rules
- Fixed voice steal order
- No random timing
- No uncontrolled concurrency

---
# 15. FINAL CONCLUSION

SlotLab middleware is a layered, deterministic, state‑gated, orchestrated execution system.

Engine hooks are inputs.  
Behavior events are abstractions.  
Priority engine prevents chaos.  
Orchestration shapes emotion.  
AUREXIS optimizes perception.  
Voice allocation guarantees stability.  
Simulation ensures long-session safety.  
Analytics closes the feedback loop.

No raw hook bypass.  
No uncontrolled execution path.  
No architectural ambiguity.

This is the complete middleware structure.
