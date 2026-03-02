# Model Usage Policy

**Scope:** FluxForge Studio — all domains

---

## Model Roles

| Model | Role | When |
|-------|------|------|
| **Opus** | Architect / CTO | New system design, architecture specs, strategic decisions |
| **Sonnet** | Senior Dev (default 90%) | Implementation, refactoring, analysis, bug fixes, UI, testing |
| **Haiku** | Quick helper | Trivial searches, file reads, basic transforms |

## Decision Rule

1. Does this **fundamentally change** system architecture? → Opus
2. Is this an **architecture spec or vision doc**? → Opus
3. Everything else → **Sonnet** (default)

**When uncertain → Sonnet.**

## Subagent Model Selection

| Agent type | Model |
|------------|-------|
| Explore | haiku or default |
| Plan | sonnet |
| general-purpose | sonnet |

**Never delegate Opus to subagents** — use directly in main conversation.

## Cost Awareness

Haiku: 1x, Sonnet: ~10x, Opus: ~30x. Use Opus only when it saves days of wrong implementation.
