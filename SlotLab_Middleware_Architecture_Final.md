# SLOT LAB MIDDLEWARE ARCHITECTURE SPEC
## FluxForge Studio – State-Driven + Engine Hook Hybrid Model
### AUREXIS Integrated
### Version 1.0
### Generated: 2026-02-24

---

# 0. PURPOSE

This document defines the **final, production-grade architecture** of SlotLab middleware.

Goal:

- Eliminate mental overload
- Eliminate event chaos
- Preserve full engine control
- Support 300–1000+ engine hooks
- Maintain deterministic behavior
- Enable AutoBind + Manual Hook precision
- Keep AUREXIS fully integrated
- Zero structural ambiguity

This document is COMPLETE. No architectural gaps.

---

# 1. CORE ARCHITECTURE PHILOSOPHY

SlotLab must be:

STATE-DRIVEN
not
EVENT-LIST-DRIVEN

Engine hooks exist.
But they are not the primary authoring layer.

The authoring layer is:

STATE → BEHAVIOR NODE → ENGINE HOOK MAP → AUREXIS → DSP

---

# 2. SYSTEM LAYER MODEL

There are exactly THREE layers.

## 2.1 Behavior Layer (Primary)

Visible by default.
Designer-facing.

Structure:

Idle
Spin
Reel_Stop
Cascade
Win
Feature
Jackpot
UI
System

Each state contains:

- Behavior Nodes
- Sound Groups
- Variant Pools
- Basic Parameters

Engine hooks are NOT directly visible here.

---

## 2.2 Engine Hook Layer (Secondary)

Hidden by default.
Advanced view only.

Examples:

onReelStop_r1
onReelStop_r2
onSymbolLand
onCascadeStep
onWinEvaluate
onCountUpTick
onFeatureEnter
onJackpotReveal

Engine hooks cannot exist without being attached to:

- A Behavior Node
OR
- A State Container

No free-floating hooks allowed.

---

## 2.3 AUREXIS Layer (Intelligence Layer)

Consumes:

- State
- Behavior context
- Volatility
- RTP
- Escalation state
- Event density
- Layer priority

Produces:

- Spatial bias
- Dynamic mix shift
- Escalation curve
- Fatigue regulation
- Collision prevention

AUREXIS never binds sounds directly.
It modifies behavior output.

---

# 3. LEFT PANEL STRUCTURE (FINAL)

Default View: Behavior Tree

Example:

REELS
  Stop
  Land
  Anticipation
  Nudge

CASCADE
  Start
  Step
  End

WIN
  Small
  Big
  Mega
  Countup

FEATURE
  Intro
  Loop
  Outro

JACKPOT
  Mini
  Major
  Grand

UI
  Button
  Popup
  Toggle

This reduces 300+ hooks into 40–80 behavior nodes.

---

# 4. AUTO BIND SYSTEM

AutoBind Flow:

1. Parse filename
2. Identify phase
3. Identify system
4. Identify action
5. Identify modifiers (rX, cX, mX, jt_X)
6. Map to Behavior Node
7. Internally map to engine hook(s)

Example:

base_reel_stop_r3.wav

→ Phase: base
→ System: reel
→ Action: stop
→ Modifier: r3

AutoBind attaches sound to:

Behavior Node: REELS → Stop
Engine Hook: onReelStop_r3

---

# 5. MANUAL HOOK ATTACH SYSTEM

Manual Attach is allowed.

But strictly controlled.

Each Behavior Node contains:

[ + Attach Engine Hook ]

Clicking opens filtered hook drawer.

Only hooks relevant to that state are shown.

Example inside Reel_Stop:

onReelStop_r1
onReelStop_r2
onReelStop_r3
onReelStop_r4
onReelStop_r5

No unrelated hooks visible.

---

# 6. BIND TYPES

System internally tracks 3 types:

AutoBind
ManualAttach
ManualOverride

AutoBind:
Created by naming detection.

ManualAttach:
Hook added without replacing default behavior.

ManualOverride:
Default behavior replaced or disabled.

Each Behavior Node displays status:

Green → Fully Auto
Yellow → Partial Manual
Red → Manual Override

---

# 7. HOOK COVERAGE PANEL

Global panel shows:

Total Engine Hooks
Auto Covered
Manual Attached
Manual Override
Unmapped

Clicking "Unmapped" filters only missing hooks.

Prevents hidden gaps.

---

# 8. VIEW MODES

SlotLab contains 4 modes.

## 8.1 Build Mode

Default.
Behavior tree visible.
Minimal parameters.
Manual attach enabled.

## 8.2 Flow Mode

Behavior graph view.
State transitions visualized.
No hook editing.

## 8.3 Simulation Mode

Read-only.
Displays:

Active events
Voice count
Escalation index
Fatigue index
Collision warnings

## 8.4 Diagnostic Mode

Full engine hook visibility.
Override diff.
Raw AUREXIS data.

Not default.

---

# 9. PARAMETER STRUCTURE

Parameters are tiered.

Basic:
Gain
Priority Class
Layer Group
Variant Pool

Advanced:
Escalation Bias
Spatial Weight
Energy Weight
Fade Policy

Expert:
Raw hook modifier
AUREXIS bias override
Execution priority override

Default view shows Basic only.

---

# 10. SMART COLLAPSING RULES

Behavior Node collapses automatically if:

- No manual override
- Default mapping intact
- No parameter changes

Expanded automatically if:

- Manual attach present
- Override exists
- Validation warning triggered

---

# 11. STATE-DRIVEN EXECUTION MODEL

Execution Flow:

Current Game State
↓
Behavior Node
↓
Mapped Engine Hook(s)
↓
AUREXIS Modification
↓
Voice Allocation
↓
DSP Execution

Engine hooks never bypass state logic.

---

# 12. SIMULATION ENGINE

Simulation Mode supports:

- 100 spin quick sim
- 1000 spin stress test
- 30 minute session sim
- Volatility curve simulation
- RTP shift test
- Turbo mode simulation
- Autoplay simulation

Outputs:

Fatigue curve
Energy curve
Collision map
Silence gaps
Layer dominance graph

---

# 13. ERROR PREVENTION RULES

System blocks:

Duplicate hook attachment
Hook without state
Multiple overrides on same hook
Unmapped required state
Detached sound file

Validation runs continuously.

---

# 14. MANUAL HOOK POLICY

Manual hooks:

Must belong to state
Must have minimal parameters
Cannot exceed 10% of total hook coverage without warning
Cannot bypass AUREXIS layer

Manual hook is precision tool, not main workflow.

---

# 15. PERFORMANCE INTEGRATION

Real-time display:

Active Voices per Layer
CPU estimate
Memory footprint
Loop overlap density
Mobile profile simulation

---

# 16. FINAL STRUCTURAL RULES

1. Behavior Layer is primary
2. Engine Layer is secondary
3. AUREXIS modifies but does not bind
4. No global raw hook list in default mode
5. Manual hooks are contained and visible
6. AutoBind handles majority workload
7. System prevents duplicate logic
8. All states must be covered or flagged

---

# 17. RESULT

This architecture:

Eliminates left panel overload
Preserves full engine control
Supports unlimited scalability
Prevents hook chaos
Maintains deterministic execution
Supports commercial-level stability

This is the final SlotLab Middleware Architecture Model.

No structural gaps remain.
