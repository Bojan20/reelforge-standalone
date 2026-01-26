# Model Selection Cheat Sheet — Quick Reference

**Created:** 2026-01-26
**For:** Rapid model selection during tasks
**Full Policy:** `.claude/00_MODEL_USAGE_POLICY.md`

---

## 🎯 3-Second Decision

```
┌─────────────────────────────────────────────┐
│  QUICK CHECK:                               │
│                                             │
│  "Am I writing/modifying code?"             │
│  ├─ YES → SONNET                            │
│  └─ NO  → Continue ↓                        │
│                                             │
│  "Is this architectural/vision work?"       │
│  ├─ YES → Ask user (probably OPUS)          │
│  └─ NO  → SONNET                            │
│                                             │
│  DEFAULT: When uncertain → SONNET           │
└─────────────────────────────────────────────┘
```

---

## ⚡ Trigger Words

### OPUS Triggers ⚠️

| Word | Action |
|------|--------|
| "Ultimate" | Ask user if architectural |
| "Master spec" | Likely Opus |
| "Design from scratch" | Likely Opus |
| "Philosophy" | Opus |
| "Vision" | Opus |
| "Should we [paradigm]" | Ask user |

### SONNET Triggers ✅

| Word | Action |
|------|--------|
| "Implement" | Sonnet (always) |
| "Refactor" | Sonnet (unless entire arch) |
| "Fix" | Sonnet (always) |
| "Add feature" | Sonnet (always) |
| "Analyze [existing]" | Sonnet (always) |
| "Create TODO" | Sonnet (always) |
| "Write code" | Sonnet (always) |

---

## 📊 Common Scenarios

| Scenario | Model | Why |
|----------|-------|-----|
| "Analyze DAW Lower Zone" | **Sonnet** | Analyzing existing code |
| "Design new middleware" | **Opus** | New system from scratch |
| "Create TODO for P0 tasks" | **Sonnet** | Task management |
| "Split 5k LOC file" | **Sonnet** | Refactoring existing |
| "Write ultimate FluxForge spec" | **Opus** | Master documentation |
| "Fix sidechain bug" | **Sonnet** | Bug fixing |
| "Should we use ECS or OOP?" | **Opus** | Strategic decision |
| "Add LUFS meter UI" | **Sonnet** | Feature implementation |
| "Refactor entire engine" | Ask user | Depends on scope |

---

## ❌ Common Mistakes

### MISTAKE 1: Opus for Refactoring

```
❌ WRONG: "Refactor mixer_provider.dart" → Opus
✅ RIGHT: Use Sonnet (unless fundamentally changing architecture)
```

### MISTAKE 2: Sonnet for Vision Docs

```
❌ WRONG: "Write FluxForge 2027 Vision" → Sonnet
✅ RIGHT: Use Opus (strategic vision)
```

### MISTAKE 3: Not Asking When Uncertain

```
❌ WRONG: Guessing which model to use
✅ RIGHT: Ask user which model for gray zones
```

---

## 🚨 Emergency Protocol

**If you realize mid-task you're using wrong model:**

1. **STOP immediately**
2. **Acknowledge:**
   > "⚠️ MODEL MISMATCH: Started with [X], should be [Y]"
3. **Ask user:**
   > "Continue with [X], switch to [Y], or split task?"
4. **Never auto-switch** without approval

---

## 🔍 Gray Zones — Ask User

| Scenario | Question to Ask |
|----------|-----------------|
| "Redesign routing" | "New architecture (Opus) or refactor existing (Sonnet)?" |
| "Ultimate analysis" | "Strategic vision (Opus) or actionable report (Sonnet)?" |
| "Large refactoring" | "Changing architecture (Opus) or reorganizing files (Sonnet)?" |
| "Comprehensive review" | "Vision roadmap (Opus) or task list (Sonnet)?" |

---

## 💰 Cost Awareness

| Model | Relative Cost | When to Use |
|-------|---------------|-------------|
| Haiku | 1x | Trivial/quick tasks (optional) |
| Sonnet | ~10x | Default (90% of work) |
| Opus | ~30x | Strategic only (saves days) |

**Rule:** Opus cost should be justified by saving DAYS of wrong implementation.

---

## ✅ Final Tiebreaker

**When nothing else helps:**

> **Ask the user which model to use.**

Never guess. Never assume. Always ask.

---

**End of Cheat Sheet**
