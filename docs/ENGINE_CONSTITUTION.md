# FluxForge Engine Constitution v1.0

Status: LOCKED  
Scope: Mixer Core Hardening Phase  
Target: 512 Channels Deterministic Real-Time  

## 1. Identity
FluxForge 1.0 is a deterministic, high-density, real-time safe mixer engine.

It is not:
- A cloud-first platform
- A marketplace
- A feature-driven demo system

It is:
- Engine-first
- Real-time disciplined
- Architecture-driven

## 2. Thread Model
UI Thread  
↓  
SessionGraph (Command / Orchestration Layer)  
↓  
RoutingGraph (Compiled DSP State)  
↓  
Audio Thread (Execution Kernel)  

Plugin Host runs in a separate process (IPC).

## 3. Absolute Rules
- Audio thread never allocates.
- Audio thread never locks.
- Audio thread never performs HashMap lookup.
- Audio thread never evaluates business logic.
- RoutingGraph never mutates during process().
- All state changes occur through SessionCommand.
- Graph swaps are atomic.
- Freeze replaces DSP chain.
- Automation per-sample traversal is forbidden.

Violation = Critical Engine Bug.

## 4. Performance Targets
- 512 channels stable
- 10 inserts per channel
- 10 sends per channel
- 48kHz / 512 buffer
- < 50% buffer processing time worst-case
- Undo depth ≥ 10,000

## 5. Scope Lock (1.0)
IN:
- Mixer
- Automation
- Freeze / Commit
- Offline Bounce
- Control Surface
- Basic Surround

OUT:
- Cloud
- Collaboration
- Marketplace
- Distributed Rendering
- Atmos Objects
