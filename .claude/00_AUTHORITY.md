# FluxForge Studio — Authority & Truth Hierarchy

This file defines the absolute authority model for this repository.
When documents conflict, this file decides what is "law".

Claude MUST treat this hierarchy as non-negotiable.

---

## 0. Meta-Law: Model Usage Policy (ABSOLUTE SUPREME)

**Document:** `.claude/00_MODEL_USAGE_POLICY.md`

This policy determines **HOW Claude operates** — which model to use for which task.

**It is Level 0 because:**
- It affects ALL other levels (1-5)
- Wrong model = wrong architecture decisions OR wasted resources
- Must be checked BEFORE any work begins

**Core Rule:**
- Opus 4.5 = Architectural design, ultimate specs, vision
- Sonnet 4.5 = Implementation, analysis, refactoring, TODO (90% of work)
- Haiku 3.5 = Trivial tasks (optional)

**Violation:** Using wrong model is a critical error.

**When uncertain → Ask user OR default to Sonnet.**

---

## 1. Hard Non-Negotiables (Supreme Law)

These are architectural laws. They override everything else:

- Audio thread must be:
  - lock-free
  - allocation-free
  - deterministic
- Waveform system must:
  - never rebuild on zoom
  - never block UI thread
  - use precomputed multi-LOD cache
  - preserve peaks at all zoom levels
  - support instant zoom + progressive refine
- Timeline position must be:
  - sample-accurate
  - driven from Rust audio engine
  - never inferred from DateTime or UI clocks
- Routing must be:
  - graph-based (topological order)
  - cycle-safe
  - lock-free via command queue
- DSP must:
  - prefer SIMD paths when available
  - remain numerically stable
  - never allocate in process()

If any implementation violates these, it is WRONG even if a document suggests otherwise.

---

## 2. Engine Architecture

Documents describing engine fundamentals are second in authority:

- unified routing architecture
- playback engine
- DSP core
- waveform cache design
- automation engine

These define how the system *must* be shaped.

---

## 3. Milestones & Audit Guidance

Documents such as:

- REELFORGE_AUDIT_REPORT.md
- PRIORITY_LIST_COMPLETE.md
- CURRENT_STATUS.md
- QUICK_START.md

Define *what to build next* and *what “complete” means*.

They do not override architectural law.

---

## 4. Implementation Guides

Files in `.claude/implementation/` describe:

- how to implement
- where to modify
- example code

They are authoritative *only* if they do not violate levels 1–3.

---

## 5. Nice-to-Have / Vision Docs

Competitive analysis, future vision, “superiority” ideas:

- inspire
- guide direction

They NEVER override architecture or milestones.

---

When in doubt:

1. Obey Hard Non-Negotiables
2. Obey Engine Architecture
3. Obey Milestone Definition of Done
4. Then follow implementation guides
