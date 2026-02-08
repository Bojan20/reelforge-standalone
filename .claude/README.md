# FluxForge Studio — .claude/ Documentation

**Last Updated:** 2026-02-08
**Status:** 100% Complete (362/362 tasks)

---

## QUICK START

**Project Status:** [MASTER_TODO.md](MASTER_TODO.md)
**Build Instructions:** [CLAUDE.md](../CLAUDE.md#kritično-full-build-procedura)
**Truth Hierarchy:** [00_AUTHORITY.md](00_AUTHORITY.md)
**Full Documentation Index:** [INDEX.md](INDEX.md)

---

## DIRECTORY STRUCTURE

```
.claude/
├── 00_AUTHORITY.md           — Truth hierarchy
├── 00_MODEL_USAGE_POLICY.md  — Opus vs Sonnet rules
├── 01_BUILD_MATRIX.md        — Build configurations
├── 02_DOD_MILESTONES.md      — Production gates
├── 03_SAFETY_GUARDRAILS.md   — Audio thread rules
├── CLEANUP_TODO.md           — Cleanup tracker
├── DOC_RULES.md              — Documentation rules
├── INDEX.md                  — Navigation hub
├── MASTER_TODO.md            — Global task tracker
├── README.md                 — This file
├── REVIEW_MODE.md            — Review procedure
├── SYSTEM_AUDIT_2026_01_21.md — Architecture audit
│
├── analysis/      (13 docs)  — Code analysis reports
├── architecture/  (24 docs)  — System designs
├── audits/        (1 doc)    — Security audits
├── docs/          (4 docs)   — Technical docs
├── domains/       (5 docs)   — Domain specs
├── guides/        (6 docs)   — Development guides
├── performance/   (1 doc)    — Optimization guide
├── project/       (1 doc)    — Project spec
├── reviews/       (1 doc)    — System review
├── roadmap/       (1 doc)    — SlotLab roadmap
├── specs/         (5 docs)   — Technical specs
├── tasks/         (6 docs)   — Task tracking
└── verification/  (1 doc)    — Verification reports
```

**Total:** 12 root files, 14 folders, 69 subfolder docs = **81 files**

---

## DOCUMENTATION RULES

See [DOC_RULES.md](DOC_RULES.md) for:
- Forbidden file types (no session reports, progress reports, changelogs)
- Folder structure with max file limits
- Pre-creation checklist
- Naming conventions

---

## PREVENTION MECHANISMS

| Mechanism | Location | Purpose |
|-----------|----------|---------|
| AppleDouble cleanup | `scripts/clean-appledouble.sh` | Removes `._*` from project |
| Build integration | `scripts/run-macos.sh` | Auto-cleanup before build |
| Pre-commit hook | `.git/hooks/pre-commit` | Blocks `._*` commits |
| Documentation rules | `.claude/DOC_RULES.md` | Prevents doc spam |

---

*For questions: See MASTER_TODO.md for current priorities*
