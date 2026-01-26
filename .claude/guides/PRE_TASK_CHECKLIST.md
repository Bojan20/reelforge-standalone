# Pre-Task Validation Checklist

**Created:** 2026-01-26
**Purpose:** Mandatory checks before starting ANY task
**Frequency:** Every single task, no exceptions

---

## ✅ MANDATORY CHECKS (Complete in Order)

### 1️⃣ MODEL SELECTION ⚡ CRITICAL

**Before proceeding, answer these 3 questions:**

#### Question A: Fundamental Architecture Change?

Does this task **fundamentally change** system architecture?

**Examples of YES:**
- Switching state management paradigm (Provider → Bloc)
- Redesigning audio routing from scratch
- Moving from monolithic to microservices
- Changing core DSP algorithms

**Examples of NO:**
- Refactoring single module/file
- Adding feature to existing system
- Bug fixes
- Performance optimization

**Decision:**
- [ ] YES → Ask user if Opus needed, then proceed to Question B
- [ ] NO → Proceed to Question B

---

#### Question B: Ultimate/Master/Vision Document?

Is this an **ultimate, master, philosophy, or vision** document?

**Keywords that indicate YES:**
- "Ultimate"
- "Master specification"
- "Philosophy"
- "Long-term vision"
- "Comprehensive system design"

**Examples of YES:**
- "Write ultimate FluxForge architecture spec"
- "Create master middleware philosophy document"
- "Design FluxForge 2027 vision"

**Examples of NO:**
- "Analyze DAW Lower Zone" (analysis report)
- "Create TODO for P0 tasks" (task list)
- "Review mixer provider" (code review)

**Decision:**
- [ ] YES → Ask user if Opus needed, then proceed to Question C
- [ ] NO → Proceed to Question C

---

#### Question C: Code Writing/Modification?

Does this task involve **writing or modifying code**?

**Keywords that indicate YES:**
- "Implement"
- "Refactor"
- "Fix bug"
- "Add feature"
- "Write function"
- "Create widget"

**Decision:**
- [ ] YES → Use **Sonnet** (skip to Section 2)
- [ ] NO → Use **Sonnet** for analysis/docs (skip to Section 2)

---

#### ⚠️ If Questions A or B were YES:

**Ask user explicitly:**

> "This task may require **Opus** because:
> - [Architectural change / Ultimate document]
>
> Should I:
> A) Use Opus (strategic/architectural)
> B) Use Sonnet (implementation/analysis)
> C) Split into phases (Opus design → Sonnet implementation)"

**Wait for user response before proceeding.**

---

#### ✅ Final Model Selection

**Selected Model:** _________________ (Opus / Sonnet / Haiku)

**Reasoning:** _________________________________________________

**If uncertain:** Ask user which model to use.

---

### 2️⃣ TOOL CONCURRENCY CHECK

**Rule:** Tools must be used **SEKVENCIJALNO** (never parallel).

**Before executing tools, confirm:**

- [ ] I will execute tools ONE AT A TIME
- [ ] I will WAIT for each tool result before next call
- [ ] I will NOT attempt parallel read/write/search

**If "tool use concurrency issues" occur:**
1. Stop immediately
2. Continue with single-step execution
3. Never retry with parallel calls

---

### 3️⃣ DOCUMENT HIERARCHY CHECK

**Authority order (from supreme to lowest):**

0. **Model Usage Policy** (.claude/00_MODEL_USAGE_POLICY.md) — HOW to work
1. **Hard Non-Negotiables** (.claude/00_AUTHORITY.md) — WHAT never changes
2. **Engine Architecture** — WHAT the system must be
3. **Milestones & Audits** — WHAT to build next
4. **Implementation Guides** — HOW to implement
5. **Vision Docs** — INSPIRATION only

**Before proceeding, confirm:**

- [ ] I have checked MODEL_USAGE_POLICY for model selection
- [ ] I will obey Hard Non-Negotiables (lock-free audio, no allocations, etc.)
- [ ] I understand current milestone priorities
- [ ] If docs conflict, I will use this hierarchy to resolve

---

### 4️⃣ CONTEXT VERIFICATION

**Before implementing, verify I have all necessary context:**

- [ ] Read relevant files (don't assume contents)
- [ ] Searched for ALL instances (grep/glob) if making changes
- [ ] Understood existing architecture (no blind changes)
- [ ] Checked for similar patterns elsewhere in codebase

**Critical Rule:** **AUTOMATSKI ČITAJ pre promene** — Never modify code you haven't read.

---

### 5️⃣ BUILD VERIFICATION (If Code Changes)

**If this task involves Rust or Flutter code:**

- [ ] I will run `flutter analyze` BEFORE changes
- [ ] I will run `flutter analyze` AFTER changes
- [ ] I will run `cargo build --release` if Rust changed
- [ ] I will copy dylibs to ALL 3 locations (if applicable)
- [ ] I will NEVER run app if compile errors exist

**Build Locations (macOS):**
1. `target/release/*.dylib`
2. `flutter_ui/macos/Frameworks/*.dylib`
3. `~/Library/Developer/Xcode/DerivedData/.../Frameworks/*.dylib`

---

### 6️⃣ IMPLEMENTATION APPROACH

**Before writing code, confirm:**

- [ ] I will implement the **BEST** solution, not quickest
- [ ] I will find **ROOT CAUSE**, not treat symptoms
- [ ] I will implement **PRODUCTION-READY** code, not mockups
- [ ] I will make changes to **ALL instances**, not just first found
- [ ] I will **NOT ask "A or B?"** — I choose the best solution

**Rule:** **NIKADA jednostavno rešenje — UVEK ultimativno rešenje.**

---

### 7️⃣ TASK CLARITY

**Before starting, confirm:**

- [ ] I understand EXACTLY what the task requires
- [ ] I know EXACTLY what "done" looks like
- [ ] I have a CONCRETE plan (if complex task)
- [ ] I know which files will be modified/created

**If ANY uncertainty exists:**
- [ ] Ask user for clarification BEFORE starting

---

### 8️⃣ ERROR HANDLING

**If errors occur during implementation:**

- [ ] I will analyze ROOT CAUSE, not just symptoms
- [ ] I will fix the REAL issue, not add workarounds
- [ ] I will update ALL affected code, not just error location
- [ ] I will verify fix with testing/manual check

**Rule:** **Pronađi ROOT CAUSE, ne simptom.**

---

## 📋 QUICK CHECKLIST SUMMARY

**Before EVERY task, mentally verify:**

1. ✅ Model selected (Opus/Sonnet) via 3-question protocol
2. ✅ Tools will be used sekvencijalno (never parallel)
3. ✅ Authority hierarchy understood (Model Policy → Hard Rules → Milestones)
4. ✅ Context gathered (files read, instances searched)
5. ✅ Build verification plan (if code changes)
6. ✅ Implementation approach clear (best solution, root cause)
7. ✅ Task clarity confirmed (know what "done" means)
8. ✅ Error handling strategy ready

**If ANY item unchecked → STOP and resolve before proceeding.**

---

## 🚨 VIOLATION CONSEQUENCES

**Not following this checklist can result in:**

1. **Wrong model used** → Wasted time/cost, poor quality
2. **Tool concurrency errors** → Task failure
3. **Violated architecture rules** → Code must be rewritten
4. **Incomplete implementation** → Missed instances, bugs
5. **Build failures** → Wasted time, frustration
6. **Wrong solution** → Technical debt, future problems

---

## ✅ CERTIFICATION

**Before starting task, mentally certify:**

> "I have completed ALL 8 mandatory checks.
> I am ready to proceed with [selected model].
> I understand the task requirements and Definition of Done."

**If you cannot certify this → STOP and ask user for guidance.**

---

**End of Checklist — Use Before Every Task**
