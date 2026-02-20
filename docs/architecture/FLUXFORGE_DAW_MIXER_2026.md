# FLUXFORGE DAW MIXER 2026 — ULTIMATE ARCHITECTURE SPEC

Status: AUTHORITATIVE IMPLEMENTATION BLUEPRINT
Scope: DAW Section (NOT Slot Middleware Mixer)
Target: Pro Tools 2026–Class Mixer
Audience: Claude / Any Provider / Future Core Devs

---

# 0. PURPOSE

This document defines the complete architectural, behavioral, state, UI, routing,
undo, and performance specification for the FluxForge DAW Mixer.

It is written so that any provider can implement without ambiguity.

---

# 1. FUNDAMENTAL DESIGN DECISIONS

## 1.1 Dedicated Mixer Screen

The DAW mixer is NOT inline and NOT docked.

```
enum AppViewMode {
  edit,
  mixer,
}
```

Edit and Mixer share engine state but render different UI trees.

---

# 2. ENGINE ORCHESTRATION LAYER

New module:

```
crates/rf-engine/src/daw_mixer/
```

Module structure:

```
daw_mixer/
 ├── mod.rs
 ├── session_graph.rs
 ├── solo_engine.rs
 ├── folder_engine.rs
 ├── vca_engine.rs
 ├── spill_engine.rs
 ├── layout_snapshot.rs
```

SessionGraph coordinates TrackManager, Routing, InsertChain and AudioGraph.

---

# 3. CHANNEL TYPES

```
Audio
Bus
Aux
Folder (audio path)
VCA (control only)
Master
```

Folder behaves as Bus with grouping semantics.

---

# 4. SOLO ENGINE

Supported modes:

- SIP
- AFL
- PFL

Requirements:

- Listen Bus
- Solo Safe
- Deterministic recompute
- No allocation in audio thread

---

# 5. SEND FLEXIBILITY

Send tap positions:

```
PreInsert
PostInsert
PreFader
PostFader
PostPan
```

---

# 6. GLOBAL UNDO

All mixer changes go through AppTransactionManager.

Undo includes layout, spill, routing, inserts and view changes.

---

# 7. UI STRUCTURE

```
MixerScreen
 ├── TopBar (44px)
 ├── Body (virtualized strips + pinned zone)
