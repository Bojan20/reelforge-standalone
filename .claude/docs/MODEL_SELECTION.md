## ⚡ MODEL SELECTION — Opus vs Sonnet vs Haiku

**OBAVEZNO pročitaj:** `.claude/00_MODEL_USAGE_POLICY.md`

### 🔀 HYBRID WORKFLOW — SlotLab Implementation (2026-01-29)

**Source:** SlotLab Ultimate Analysis + Opus Architectural Review
**Decision:** HYBRID approach — Sonnet za majority, Opus za architectural heavy-lifting

#### Sonnet Tasks (Routine Implementation — ~85% of P0 work)

**Week 1-2 Quick Wins + Bug Fixes:**
```
✅ SL-INT-P0.1: Event List Provider Fix (2h)
✅ SL-INT-P0.2: Remove AutoEventBuilderProvider (2h)
✅ SL-RP-P0.1: Delete Event Button (1h)
✅ SL-RP-P0.4: Add Layer Button (1h)
✅ SL-LP-P0.1: Audio Preview Playback (2d)
✅ SL-LP-P0.2: Section Completeness (1d)
✅ SL-LP-P0.3: Batch Distribution Dialog (1d)
```

**Why Sonnet:** Simple CRUD, UI widgets, provider sync — routine development work

**Week 4 Feature Implementation:**
```
✅ SL-LZ-P0.4: Batch Export Panel (3d)
✅ SL-RP-P0.2: Stage Editor Dialog (2d)
✅ SL-RP-P0.3: Layer Property Editor (3d)
```

**Why Sonnet:** UI panels, dialogs, forms — standard Flutter development

---

#### Opus Tasks (Architectural Complexity — ~15% of P0 work)

**Week 2-3 Architecture:**
```
🎯 SL-LZ-P0.2: Restructure Lower Zone to Super-Tabs (1w)
   - Fundamental architectural change (8 flat → 7 super-tabs)
   - Two-row header system
   - State management refactor
   - Migration strategy for existing tabs

🎯 SL-LZ-P0.3: Composite Editor Panel (3d)
   - Large panel (~800 LOC)
   - Complex interactions (layers, stages, properties)
   - Multiple provider integrations
   - Critical workflow component
```

**Why Opus:**
- SL-LZ-P0.2: **Architectural refactor** — changing fundamental structure
- SL-LZ-P0.3: **Complex panel** — 800 LOC with multi-provider coordination

---

#### Decision Criteria (When to Use Opus)

**Use Opus if task has 2+ of these:**
- [ ] Changes fundamental architecture (not just adding features)
- [ ] New panel > 600 LOC with complex state management
- [ ] Multiple provider integrations (3+)
- [ ] Affects cross-cutting concerns (all panels)
- [ ] High risk of breaking existing functionality
- [ ] Requires deep reasoning about trade-offs

**Use Sonnet if:**
- [ ] Adding UI controls (buttons, sliders, dialogs)
- [ ] Simple CRUD operations
- [ ] Single-provider changes
- [ ] Bug fixes with clear solution
- [ ] < 400 LOC changes
- [ ] Low risk, isolated changes

**Unclear?** Default to **Sonnet**, escalate to Opus if komplexity exceeds expectations.

---

#### Workflow Pattern

```
1. Sonnet: Analyze task from MASTER_TODO.md
2. Sonnet: Check decision criteria
3. IF Opus-worthy:
   → Sonnet: Prepare detailed brief for Opus
   → Opus: Execute architectural work
   → Sonnet: Review + integrate Opus changes
4. ELSE:
   → Sonnet: Execute task directly
5. Sonnet: Verify (flutter analyze, manual test)
6. Sonnet: Commit + move to next task
```

---

#### P0 Task Assignments (Final)

| Task ID | Task | Assigned To | Reason |
|---------|------|-------------|--------|
| SL-INT-P0.1 | Event List Provider | **Sonnet** | Simple import change |
| SL-INT-P0.2 | Remove Provider | **Sonnet** | Grep + delete + update refs |
| SL-LZ-P0.2 | **Super-Tab Restructure** | **Opus** | Architectural refactor |
| SL-LZ-P0.3 | **Composite Editor** | **Opus** | Complex 800 LOC panel |
| SL-LZ-P0.4 | Batch Export | **Sonnet** | Standard export panel |
| SL-RP-P0.1 | Delete Button | **Sonnet** | 1-hour UI addition |
| SL-RP-P0.2 | Stage Editor | **Sonnet** | Dialog widget, 400 LOC |
| SL-RP-P0.3 | Layer Properties | **Sonnet** | Sliders + UI logic |
| SL-RP-P0.4 | Add Layer Button | **Sonnet** | Simple button + callback |
| SL-LP-P0.1 | Audio Preview | **Sonnet** | Play button integration |
| SL-LP-P0.2 | Section Completeness | **Sonnet** | Calculation + badge |
| SL-LP-P0.3 | Batch Distribution | **Sonnet** | Dialog widget, 300 LOC |

**Sonnet: 10 tasks (85%)**
**Opus: 2 tasks (15%)**

---

#### Handoff Protocol (Sonnet → Opus)

**When Sonnet reaches Opus task:**

1. **Prepare Brief:**
```markdown
# TASK BRIEF FOR OPUS

**Task:** SL-LZ-P0.2 Super-Tab Restructure
**Context:** [Link to MASTER_TODO.md task]
**Analysis:** [Link to FAZA 2.3 document]
**Current State:** [Files affected, current implementation]
**Expected Outcome:** [DoD checklist]
**Constraints:** [Opus review decisions, design patterns]
```

2. **Invoke Opus:**
```
Use Task tool with model="opus"
Pass complete brief
Wait for completion
```

3. **Review Opus Output:**
- Verify flutter analyze passes
- Manual test new architecture
- Confirm DoD met
- Integrate any follow-up changes

4. **Continue with Next Sonnet Task**

---

**TL;DR — Quick Decision Tree:**

```
Is this task fundamentally changing system architecture?
├─ YES → Consider Opus (ask user)
└─ NO → Continue ↓

Is this task > 600 LOC with multi-provider complexity?
├─ YES → Consider Opus (ask user)
└─ NO → Continue ↓

Is this a routine implementation task?
├─ YES → Use Sonnet
└─ NO → Use Sonnet (analysis/docs)

DEFAULT: When uncertain → Sonnet
```

```
Is this task fundamentally changing system architecture?
├─ YES → Consider Opus (ask user)
└─ NO → Continue ↓

Is this an "ultimate/master/vision" document?
├─ YES → Consider Opus (ask user)
└─ NO → Continue ↓

Does this involve writing/modifying code?
├─ YES → Use Sonnet
└─ NO → Use Sonnet (analysis/docs)

DEFAULT: When uncertain → Sonnet
```

**Model Roles:**
- **Opus 4.5** = Chief Architect / CTO (architectural design, ultimate specs, vision)
- **Sonnet 4.5** = Senior Developer (90% of tasks: code, analysis, TODO, refactoring)
- **Haiku 3.5** = Quick Helper (optional: trivial tasks, fast searches)

**Key Rule:** Never use Opus for implementation, refactoring, or routine work.

**Violation:** Using wrong model is a critical error — see policy for self-correction protocol.

---

