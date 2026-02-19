# LONG_TERM — FluxForge Ecosystem AI Operating Constitution
Status: LOCKED
Owner: Bojan (Product Owner)
Applies to: Entire ecosystem (FluxForge Studio + SlotLab + tooling + runtime adapters)

## 0) Purpose
This document defines non-negotiable rules that keep the ecosystem stable, deterministic, and scalable.
Chat conversations are NOT storage. The authoritative memory lives in AI_BRAIN.

## 1) Roles (Hard Rule)
- Claude = PRIMARY IMPLEMENTER (main dev). Claude is responsible for producing code changes.
- ChatGPT = ARCHITECT + REVIEW GATE + QA + FALLBACK (only if Claude is unavailable/limited).
- ACC (AI Control Core) = ENFORCER. No code change is “real” unless ACC gates pass.

## 2) Patch-Only Rule (Hard Rule)
- AI never directly edits files in-place.
- AI outputs Unified Diff patches ONLY.
- ACC applies patches in a controlled flow (sandbox/branch), runs gates, then merges or rolls back.

## 3) Merge Gate Rule (Hard Rule)
No change is considered accepted unless:
- Patch applied successfully
- All gates PASS
- Review gate PASS (unless Emergency Mode is explicitly enabled)

## 4) Emergency Mode (Controlled Exception)
Emergency Mode may be used ONLY when:
- Provider is unavailable and work must continue
- The change is small, isolated, and reversible

Emergency Mode still requires:
- Patch-only
- Locked-path protection
- Audit entry
- Follow-up “Claude normalization task” once Claude is back (cleanup/refactor/final ownership)

## 5) Single Source of Truth (Hard Rule)
Authoritative sources:
1) AI_BRAIN/memory/* (this folder)
2) AI_BRAIN/state/* (tasks, milestones, provider status)
3) STATE_LOCK.json (hash-lock / invariants for critical files)

Non-authoritative:
- Chat logs
- Random notes outside AI_BRAIN
- Untracked local edits

## 6) Locked Paths (Hard Rule)
The following must not be modified by normal tasks:
- AI_BRAIN/memory/** (LOCKED; only changed via “Memory Update Task” with explicit approval)
- Any file listed as “locked” in ACC config

## 7) Determinism First (Hard Rule)
- Runtime must remain deterministic.
- No nondeterministic behavior without explicit seed and documented rationale.
- DSP-in-runtime is forbidden if your ecosystem rule says “DSP is Studio-only inserts on preview chain” (enforced by gates).

## 8) Auditability (Hard Rule)
Every meaningful change must be traceable:
- Task ID
- Snapshot ID (before/after)
- Patch ID
- Provider used
- Gate results
- Review result

## 9) Naming + Structure Authority
Naming conventions and folder structure live in:
- CONSTRAINTS.md (hard)
- ARCHITECTURE.md (structural mapping)
- GLOSSARY.md (terminology)

## 10) “No Drift” Rule
If an AI response conflicts with AI_BRAIN/memory, AI_BRAIN wins.
If AI_BRAIN is outdated, update AI_BRAIN first (explicit Memory Update Task), then implement.

## 11) Default Workflow Summary
1) Create Task (spec + acceptance)
2) Snapshot baseline
3) Claude implements (patch)
4) ACC applies patch → gates
5) ChatGPT reviews diff → PASS/FAIL
6) Merge or rollback
7) Update AI_BRAIN state (tasks/milestones) and only update memory docs when needed
