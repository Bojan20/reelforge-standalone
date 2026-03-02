# FluxForge Studio — .claude/ Documentation

**Status:** ALL SYSTEMS COMPLETE (182/182 ✅)

---

## Structure

```
.claude/
├── 00_AUTHORITY.md           — Truth hierarchy
├── 00_MODEL_USAGE_POLICY.md  — Model selection rules
├── 01_BUILD_MATRIX.md        — Build configurations
├── 02_DOD_MILESTONES.md      — Production gates (summary)
├── 03_SAFETY_GUARDRAILS.md   — Audio thread rules
├── MASTER_TODO.md            — Grand total: 182/182 ✅
├── REVIEW_MODE.md            — Review procedure
├── README.md                 — This file
│
├── architecture/  (33 docs)  — System designs & specs
├── docs/          (10 docs)  — Reference documentation
├── domains/       (5 docs)   — Domain specs (audio, engine)
├── guides/        (6 docs)   — Quick reference cards
├── project/       (1 doc)    — Project spec
└── specs/         (6 docs)   — Technical specifications
```

## Rules

- **No session reports, progress reports, changelogs** — use git
- **No new root files** without explicit user permission
- **Edit existing** before creating new
- **Every new file** must be referenced from CLAUDE.md or another authority doc
