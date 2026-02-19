# CONSTRAINTS — Hard Rules & Validation Targets
Status: LOCKED
Scope: Entire ecosystem

## 1) Core Workflow Constraints
- Patch-only changes (Unified Diff).
- No direct edits by AI providers.
- No merge without gates PASS (except Emergency Mode).

## 2) Provider Constraints (Claude Primary)
- Claude is the default implementer for code changes.
- ChatGPT is default for architecture/spec/review/QA.
- Fallback to ChatGPT implementation only when Claude is unavailable/limited, then “Claude normalization” task is required.

## 3) Determinism Constraints (Runtime)
Enforce at minimum:
- No Math.random() in runtime without explicit seeded RNG wrapper.
- No reliance on system time for gameplay-critical logic (unless abstracted and seeded).
- No unordered iteration reliance where order matters (documented stable ordering only).
- No runtime DSP if your product rule is “DSP is Studio-only inserts on preview chain”.

## 4) Performance Constraints (Slots + Mobile)
- Avoid unnecessary allocations in hot paths.
- Ensure predictable CPU usage for long sessions.
- Memory budgets for audio assets must be tracked (lazy loading rules if applicable).
- No large synchronous IO on main thread.

## 5) Security / Integrity Constraints
- Do not expose internal assets or keys via logs.
- Never commit API keys to repo.
- Local-only ACC service must bind to localhost unless explicitly configured otherwise.

## 6) Naming Constraints (Audio + Code)
Hard naming policies (extend as needed):
- Keep your established separation rules (e.g., s_ vs sl_) intact.
- Commands/events naming must be consistent per subsystem.
- File naming must be consistent within each domain (plugins, runtime, authoring).

## 7) Locked Zones (Hard)
- AI_BRAIN/memory/** locked.
- Any other locked areas defined in ACC config.
- STATE_LOCK.json modifications only via ACC-managed flow.

## 8) Output Quality Constraints
- No placeholder code merged unless explicitly allowed.
- All patch changes must include minimal notes + acceptance criteria mapping.

## 9) Gates Minimum Set (Must Exist)
- Locked Paths Gate
- Patch Sanity Gate (no mass deletions, no binary edits unless allowed)
- Determinism Gate (pattern-based + optional AST rules)
- State Lock Gate (hash/invariants)
- Repo Health Gate (optional: typecheck/tests)
