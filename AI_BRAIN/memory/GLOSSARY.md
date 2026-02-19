# GLOSSARY — Shared Terms for the Ecosystem
Status: LOCKED
Purpose: Keep naming and meaning consistent across Studio, Runtime, SlotLab, and ACC.

## Core Terms
- ACC (AI Control Core): Local orchestrator that routes tasks, applies patches, runs gates, and maintains audit/state.
- AI_BRAIN: Persistent memory and state store for the ecosystem. Authoritative source of truth.
- Provider: An AI system used by ACC (Claude, ChatGPT/OpenAI, etc.).
- Gate: A validation step that must PASS before merge (constraints, determinism, locked paths, state lock).
- Patch: Unified Diff text produced by a provider. The only allowed AI output for code changes.
- Diffpack: Structured snapshot of what changed (files + diffs + hashes + task metadata).

## Audio / Slot Terms (Generic)
- Event/Command: A named trigger from game logic that causes audio behavior.
- Sprite / Sound Sprite: Packed audio segments referenced by ID.
- Layering: Multi-layer music intensity design controlled by parameters/RTPC-like values.
- Ducking: Sidechain-style gain reduction for priority audio.
- RTPC/Parameter: Real-time parameter controlling mix/behavior.
- Determinism: Same inputs produce same outputs; required for regulated/stable gameplay behavior.

## Workflow Terms
- Task Spec: Structured definition of what to do, with acceptance criteria and constraints.
- Acceptance Criteria: Concrete PASS conditions for completion.
- Normalization Task: Follow-up where Claude becomes final owner when fallback provider implemented changes.
- Locked Paths: Files/folders that cannot be changed without explicit workflow.

## Status Terms
- READY: Task queued and waiting to run.
- RUNNING: Provider executing the task.
- WAITING_PROVIDER: Provider unavailable/limited; task paused.
- REVIEW: Patch applied and waiting for review gate.
- PASS: Approved for merge.
- FAIL: Rejected; requires rollback/fix task.
