# FluxForge Studio — Authority & Truth Hierarchy

When documents conflict, this hierarchy decides.

---

## 1. Hard Non-Negotiables (Supreme Law)

- **Audio thread:** lock-free, allocation-free, deterministic
- **Waveform:** precomputed multi-LOD cache, never rebuild on zoom, never block UI
- **Timeline:** sample-accurate, driven from Rust engine, never from DateTime
- **Routing:** graph-based (topological order), cycle-safe, lock-free command queue
- **DSP:** prefer SIMD, numerically stable, never allocate in process()

If any implementation violates these, it is WRONG regardless of other documents.

## 2. Engine Architecture

Engine fundamentals (routing, playback, DSP core, waveform cache, automation) define how the system must be shaped.

## 3. Milestones & Definition of Done

Define what to build next and what "complete" means. Do not override architectural law.

## 4. Implementation Guides

How/where to implement. Authoritative only if they don't violate levels 1-3.

## 5. Vision / Nice-to-Have

Inspire direction. Never override architecture or milestones.

---

**When in doubt:** 1 > 2 > 3 > 4 > 5
