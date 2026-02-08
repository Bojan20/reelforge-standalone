# FluxForge Studio — Documentation Index

**Last Updated:** 2026-02-08
**Purpose:** Central navigation hub for all project documentation

---

## QUICK START

1. [CLAUDE.md](../CLAUDE.md) — Main project instructions
2. [00_AUTHORITY.md](00_AUTHORITY.md) — Truth hierarchy
3. [00_MODEL_USAGE_POLICY.md](00_MODEL_USAGE_POLICY.md) — Model selection rules

**Building the app?** See [CLAUDE.md — Build Procedures](../CLAUDE.md#kritično-full-build-procedura)

---

## AUTHORITY DOCUMENTS

| Level | Document | Purpose |
|-------|----------|---------|
| 0 | [00_MODEL_USAGE_POLICY.md](00_MODEL_USAGE_POLICY.md) | Opus vs Sonnet decision protocol |
| 1 | [00_AUTHORITY.md](00_AUTHORITY.md) | Truth hierarchy |
| 1 | [03_SAFETY_GUARDRAILS.md](03_SAFETY_GUARDRAILS.md) | Audio thread rules |
| 2 | [01_BUILD_MATRIX.md](01_BUILD_MATRIX.md) | Build configurations |
| 3 | [02_DOD_MILESTONES.md](02_DOD_MILESTONES.md) | Production gates |
| 3 | [MASTER_TODO.md](MASTER_TODO.md) | Global task tracker |

---

## BY TOPIC

### SlotLab & Middleware

| Document | Purpose |
|----------|---------|
| [architecture/SLOT_LAB_SYSTEM.md](architecture/SLOT_LAB_SYSTEM.md) | SlotLab architecture |
| [architecture/EVENT_SYNC_SYSTEM.md](architecture/EVENT_SYNC_SYSTEM.md) | Event registry |
| [architecture/ADAPTIVE_LAYER_ENGINE.md](architecture/ADAPTIVE_LAYER_ENGINE.md) | ALE system |
| [domains/slot-audio-events-master.md](domains/slot-audio-events-master.md) | 600+ stage definitions |

### Guides

| Document | Purpose |
|----------|---------|
| [guides/PRE_TASK_CHECKLIST.md](guides/PRE_TASK_CHECKLIST.md) | Task validation |
| [guides/MODEL_SELECTION_CHEAT_SHEET.md](guides/MODEL_SELECTION_CHEAT_SHEET.md) | Quick model decision |
| [guides/MODEL_DECISION_FLOWCHART.md](guides/MODEL_DECISION_FLOWCHART.md) | Visual model guide |
| [guides/PROVIDER_ACCESS_PATTERN.md](guides/PROVIDER_ACCESS_PATTERN.md) | Provider standard |

---

## FOLDER STRUCTURE

```
.claude/
├── 00_AUTHORITY.md
├── 00_MODEL_USAGE_POLICY.md
├── 01_BUILD_MATRIX.md
├── 02_DOD_MILESTONES.md
├── 03_SAFETY_GUARDRAILS.md
├── CLEANUP_TODO.md
├── DOC_RULES.md
├── INDEX.md (this file)
├── MASTER_TODO.md
├── README.md
├── REVIEW_MODE.md
├── SYSTEM_AUDIT_2026_01_21.md
│
├── analysis/      — Code analysis reports (13 docs)
├── architecture/  — System designs (24 docs)
├── audits/        — System audits (1 doc)
├── docs/          — Specifications (4 docs)
├── domains/       — Domain specs (5 docs)
├── guides/        — Development guides (6 docs)
├── performance/   — Performance guides (1 doc)
├── project/       — Project specs (1 doc)
├── reviews/       — System reviews (1 doc)
├── roadmap/       — Long-term plans (1 doc)
├── specs/         — Technical specs (5 docs)
├── tasks/         — Task tracking (6 docs)
└── verification/  — Verification reports (1 doc)
```

**Total:** 12 root files + 14 folders + 69 subfolder docs = **81 files**

---

## AUTHORITY ORDER (when documents conflict)

1. Model Usage Policy (how to work)
2. Hard Non-Negotiables (audio thread, routing)
3. Engine Architecture
4. Milestones & Audits
5. Implementation Guides

Reference: [00_AUTHORITY.md](00_AUTHORITY.md)
