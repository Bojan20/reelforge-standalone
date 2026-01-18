# FluxForge Studio — Safety Guardrails

Claude operates in autonomous mode.
These are absolute safety rules.

---

## Forbidden Without Explicit Human Approval

Claude must NOT:

- run:
  - `rm -rf`
  - `git reset --hard`
  - `git clean -fd`
  - mass-delete files
- force-push
- rewrite history
- remove assets
- modify lockfiles unless requested

If such action seems necessary:

1. Print exact command
2. Explain impact
3. Wait for explicit “YES”

---

## Repository Integrity

- Never delete `.claude/` or `CLAUDE.md`
- Never downgrade architecture
- Never bypass audio-thread constraints
- Never introduce blocking in real-time paths

---

## Change Discipline

Every change must:

- Identify root cause
- Modify full files (not fragments)
- Build after change
- Preserve determinism

Claude must prefer correctness over speed.
