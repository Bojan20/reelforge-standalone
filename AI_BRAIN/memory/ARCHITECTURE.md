# ARCHITECTURE — Ecosystem Map (FluxForge + Tools + Runtime)
Status: LOCKED
Goal: Provide a stable high-level map so AI tasks always know where to put things.

## 1) Ecosystem Components
### A) FluxForge Studio (DAW / Authoring)
- Plugin UI + editors
- Studio preview chain (Asset → Gain → Bus → Ducking → Master)
- Offline compilation / export
- Deterministic manifests and asset pipelines

### B) Middleware / Runtime Adapters
- Runtime adapter layer (engine-specific adapters)
- Deterministic playback policy
- Event/Command mapping
- Asset loading policy (lazy load, cache, platform formats)

### C) SlotLab / Mockup Tooling
- Slot simulation / staging
- Audio event triggering simulation
- Volatility mapping support (without leaking private math)
- QA harness / stress tests

### D) AI Control Core (ACC)
ACC is the orchestrator and gatekeeper.
- Watches repository
- Builds snapshots and diffpacks
- Routes tasks to providers (Claude primary)
- Applies patches
- Runs gates (constraints, determinism, locked paths)
- Maintains audit trail and state files in AI_BRAIN

## 2) ACC Data & State Model
### Memory (Authoritative)
- AI_BRAIN/memory/LONG_TERM.md
- AI_BRAIN/memory/CONSTRAINTS.md
- AI_BRAIN/memory/ARCHITECTURE.md
- AI_BRAIN/memory/GLOSSARY.md

### State (Operational)
- AI_BRAIN/state/MILESTONES.json
- AI_BRAIN/state/TASKS_ACTIVE.json
- AI_BRAIN/state/PROVIDERS.json

### Snapshots
- AI_BRAIN/snapshots/diffpack_latest.json (current)
- AI_BRAIN/snapshots/history/* (rotating archive)

## 3) Task Lifecycle
1) Task created → stored in TASKS_ACTIVE.json + audit log (later SQLite)
2) Snapshot baseline created
3) Provider implements (Claude) → returns Unified Diff patch
4) ACC applies patch in sandbox
5) Gates run → PASS/FAIL
6) Review gate runs (ChatGPT) → PASS/FAIL
7) If PASS → merge & update milestone + close task
8) If FAIL → rollback & create fix task

## 4) Routing Rules (Provider Selection)
- Implementation/refactor/bulk edits → Claude (primary)
- Architecture/spec/QA/review/risk → ChatGPT
- Claude unavailable → fallback to ChatGPT implementation + mandatory Claude normalization later

## 5) Where New Things Go (General Guidance)
- New orchestration code → ai-control-core/
- New persistent knowledge → AI_BRAIN/memory/ (via Memory Update Task)
- New operational statuses → AI_BRAIN/state/
- New logs/snapshots → AI_BRAIN/snapshots/

## 6) Non-Negotiable Review Flow
- Patch must be inspectable before apply
- Gates decide correctness
- Review gate decides maintainability and architecture alignment
- No silent merges
