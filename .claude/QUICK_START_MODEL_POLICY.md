# Model Usage Policy — Quick Start

**Created:** 2026-01-26
**Audience:** User (developer) + Claude (AI)
**Read Time:** 2 minutes

---

## 🚀 For Users — How to Use This System

### When Giving Instructions to Claude

**Option 1: Let Claude Decide (Recommended)**

Just give the task normally:

```
"Analyze DAW Lower Zone and create TODO"
```

Claude will:
1. Check trigger words ("Analyze", "TODO")
2. Run 3-question protocol
3. Select Sonnet (analysis + task management)
4. Proceed automatically

---

**Option 2: Specify Model Explicitly**

When you KNOW it's architectural:

```
"Use Opus to design new event-driven middleware from scratch"
```

Claude will use Opus as requested.

---

**Option 3: Override Claude's Choice**

If Claude selects wrong model:

```
"Actually, use Sonnet for this instead"
```

Claude will comply and explain why Sonnet is suboptimal (if applicable).

---

### Common User Commands

| Your Command | Claude's Model | Why |
|--------------|----------------|-----|
| "Implement X feature" | Sonnet | Implementation work |
| "Fix Y bug" | Sonnet | Bug fixing |
| "Analyze Z system" | Sonnet | Code analysis |
| "Create TODO for P0" | Sonnet | Task management |
| "Design new architecture for X" | Opus (asks you first) | Architectural |
| "Write ultimate FluxForge spec" | Opus (asks you first) | Master documentation |
| "Should we use X or Y paradigm?" | Opus (asks you first) | Strategic decision |

---

### When Claude Asks "Which Model?"

**Claude will ask when task is ambiguous:**

```
Clarification needed:

Option A) Design NEW routing architecture → Opus
Option B) Refactor existing routing → Sonnet

Which is this task?
```

**Your response:** Just say "A" or "B" (or "Opus"/"Sonnet").

---

## 🤖 For Claude — How to Use This System

### Every Time You Start a Task

**Step 1: Read Trigger Words**

Scan user message for:
- Opus triggers: "Ultimate", "Master", "Philosophy", "Vision", "Design from scratch"
- Sonnet triggers: "Implement", "Refactor", "Fix", "Add", "Write code"

---

**Step 2: Run 3-Question Protocol**

```
Q1: Fundamental architecture change?
    └─ YES → Ask user if Opus
    └─ NO  → Continue to Q2

Q2: Ultimate/master/vision document?
    └─ YES → Ask user if Opus
    └─ NO  → Continue to Q3

Q3: Code writing/modification?
    └─ YES → Use Sonnet
    └─ NO  → Use Sonnet (analysis/docs)
```

---

**Step 3: Make Decision**

- If Questions 1 or 2 were YES → **Ask user** which model
- If Question 3 was YES → **Use Sonnet**
- If uncertain → **Ask user OR default to Sonnet**

---

**Step 4: Proceed with Selected Model**

No second-guessing. Commit to the decision.

---

### Quick Reference Documents

**For rapid decisions:**
- [MODEL_SELECTION_CHEAT_SHEET.md](.claude/guides/MODEL_SELECTION_CHEAT_SHEET.md)

**For visual learners:**
- [MODEL_DECISION_FLOWCHART.md](.claude/guides/MODEL_DECISION_FLOWCHART.md)

**For complex tasks:**
- [PRE_TASK_CHECKLIST.md](.claude/guides/PRE_TASK_CHECKLIST.md)

**For complete policy:**
- [00_MODEL_USAGE_POLICY.md](.claude/00_MODEL_USAGE_POLICY.md)

---

### If You Realize Wrong Model Mid-Task

**Self-Correction Protocol:**

1. **STOP immediately**
2. **Output:**
   ```
   ⚠️ MODEL MISMATCH DETECTED

   Started with: [Opus/Sonnet]
   Should be: [Sonnet/Opus]
   Reason: [explanation]

   Pausing for user confirmation.
   ```
3. **Ask user:**
   ```
   Should I:
   A) Continue with [current model]
   B) Switch to [correct model]
   C) Split task (Opus design → Sonnet impl)
   ```
4. **Wait for user approval** before proceeding

**Never auto-switch without asking.**

---

## 📊 Decision Matrix — The Simple Version

| Task Contains | Model |
|---------------|-------|
| "Implement", "Refactor", "Fix", "Add", "Code" | **Sonnet** |
| "Analyze existing", "Create TODO", "Review" | **Sonnet** |
| "Ultimate", "Master", "Vision", "Philosophy" | **Opus** (ask user) |
| "Design from scratch", "New architecture" | **Opus** (ask user) |
| "Should we [paradigm change]" | **Opus** (ask user) |
| Uncertain / Gray zone | **Ask user OR Sonnet** |

**Default:** When in doubt → **Sonnet**

---

## ✅ Success Indicators

**You're using policy correctly if:**

1. ✅ You consult trigger words before deciding
2. ✅ You run 3-question protocol mentally
3. ✅ You ask user when uncertain
4. ✅ You use Sonnet for 90% of tasks
5. ✅ You only use Opus for truly strategic work
6. ✅ You stop and self-correct if wrong model detected

**You're NOT using policy correctly if:**

1. ❌ You guess model without checking policy
2. ❌ You use Opus for implementation work
3. ❌ You use Sonnet for architectural design (without asking)
4. ❌ You auto-switch models mid-task without user approval

---

## 🎯 The One Rule to Remember

```
┌─────────────────────────────────────────────┐
│                                             │
│     WHEN UNCERTAIN → ASK USER               │
│                                             │
│     OR                                      │
│                                             │
│     DEFAULT TO SONNET                       │
│                                             │
└─────────────────────────────────────────────┘
```

**Never guess. Never assume. Always verify.**

---

## 🆘 Emergency Contact

**If policy doesn't cover your scenario:**

1. Consult `.claude/00_MODEL_USAGE_POLICY.md` (full details)
2. If still unclear → **Ask user**
3. Suggest policy update for future

**This system is living** — it should evolve as FluxForge grows.

---

## 📚 Document Hierarchy Reminder

**Authority order:**

0. **Model Usage Policy** ← YOU ARE HERE (how to work)
1. Hard Non-Negotiables (what never changes)
2. Engine Architecture (what system must be)
3. Milestones & Audits (what to build next)
4. Implementation Guides (how to implement)
5. Vision Docs (inspiration only)

**Always check Level 0 before checking other levels.**

---

**End of Quick Start — You're Ready!**

**Next Step:**
- User: Give Claude a task and watch policy in action
- Claude: Apply 3-question protocol to next task

**Questions?** See `.claude/00_MODEL_USAGE_POLICY.md`
