# ⚠️ MODEL USAGE POLICY — ULTIMATE VERSION (No Gaps)

**Created:** 2026-01-26
**Authority:** OBAVEZNO poštovati — bez izuzetka
**Scope:** Ceo FluxForge Studio projekat (DAW, Middleware, SlotLab, Engine, DSP)

---

## 🛑 TOOL CONCURRENCY — STRICT MODE (FIRST RULE)

**Pravilo #1:** Claude MORA da koristi alate SEKVENCIJALNO.

```
❌ ZABRANJENO: Paralelne tool calls
✅ OBAVEZNO: Plan → Tool call → Wait result → Next step
```

**Ako se desi "tool use concurrency issues":**
1. Odmah prekini sve pokušaje
2. Nastavi sa JEDNOM akcijom (single-step)
3. Ne pokušavaj paralelne read/write/search

**Izuzeci:** NEMA izuzetaka — uvek sekvencijalno.

---

## 🎯 MODEL ROLES — Crystal Clear Definitions

### Claude Opus 4.5 = Chief Architect / Visionary / CTO

**Exclusive Use Cases:**
1. **System Architecture Design**
   - Designing NEW systems from scratch
   - Fundamentally changing existing architecture
   - Multi-crate refactoring strategy
   - Engine/Middleware/DSP architectural decisions

2. **Ultimate Documentation**
   - Master specifications (e.g., `ADAPTIVE_LAYER_ENGINE.md`)
   - Philosophy documents (e.g., `ENGINE_PHILOSOPHY.md`)
   - Long-term vision documents
   - Comprehensive system reviews (Ultimate Analysis)

3. **Strategic Decisions**
   - Tech stack changes
   - Paradigm shifts (e.g., moving from OOP to ECS)
   - Cross-cutting concerns (security, performance, scalability)
   - Roadmap milestones

4. **Deep Conceptual Thinking**
   - Algorithm design (new DSP algorithms, novel approaches)
   - Trade-off analysis (latency vs throughput, memory vs CPU)
   - Research-level problem solving

**Example Triggers for Opus:**
- "Design a new audio engine architecture"
- "Write the ultimate FluxForge specification"
- "Should we use X or Y paradigm for the entire system?"
- "Create a comprehensive system review from 9 roles"

---

### Claude Sonnet 4.5 = Senior Developer / Implementer / Executor

**Default Use Cases (90% of tasks):**
1. **Code Implementation**
   - Writing Rust/Dart code
   - Refactoring components/modules
   - Bug fixes
   - Feature implementation

2. **Analysis & Documentation**
   - Analyzing existing code
   - Writing TODO lists
   - Task breakdowns
   - Code reviews
   - Performance profiling

3. **UI/UX Work**
   - Flutter widgets
   - Panel implementations
   - Layout adjustments
   - User workflows

4. **Daily Development**
   - Adding features to existing systems
   - Connecting providers
   - FFI bindings
   - Testing

**Example Triggers for Sonnet:**
- "Implement sidechain routing UI"
- "Analyze DAW Lower Zone by roles"
- "Create a detailed TODO for P0 tasks"
- "Refactor 5,459 LOC file into modules"
- "Fix FX chain reorder bug"

---

### Claude Haiku 3.5 = Quick Helper / Utility Specialist

**Use Cases (Cost Optimization):**
1. **Trivial Tasks**
   - Simple file reads
   - Quick grep/glob searches
   - Basic text transformations
   - JSON parsing

2. **Fast Exploration**
   - Finding file locations
   - Listing dependencies
   - Quick syntax checks

**When NOT to use Haiku:**
- Complex analysis
- Multi-step tasks
- Architecture decisions
- Code generation

**Note:** Haiku is optional — Sonnet can do everything Haiku can, but slower/costlier.

---

## 📊 DECISION MATRIX — The Ultimate Cheat Sheet

| Task Type | Example | Model | Reasoning |
|-----------|---------|-------|-----------|
| **New System Design** | "Design event-driven audio middleware" | **Opus** | Architectural |
| **Existing System Analysis** | "Analyze DAW Lower Zone by 9 roles" | **Sonnet** | Analysis of existing code |
| **Feature Implementation** | "Add sidechain routing UI" | **Sonnet** | Implementation |
| **Large Refactoring** | "Split 5,459 LOC file into modules" | **Sonnet** (design) → **Sonnet** (execution) | Both phases use Sonnet unless fundamentally changing architecture |
| **TODO/Task Docs** | "Create TODO list for P0 tasks" | **Sonnet** | Task management |
| **Ultimate Specs** | "Write master FluxForge architecture spec" | **Opus** | Ultimate documentation |
| **Bug Fix** | "Fix audio cutoff on event trigger" | **Sonnet** | Debugging |
| **Code Review** | "Review mixer provider for bugs" | **Sonnet** | Code analysis |
| **Architecture Review** | "Should we use ECS or OOP for slot engine?" | **Opus** | Strategic decision |
| **Performance Optimization** | "Optimize DSP chain rendering" | **Sonnet** | Implementation |
| **Algorithm Design** | "Design new FFT windowing algorithm" | **Opus** | Research-level |
| **UI Polish** | "Add tooltips to all DAW tabs" | **Sonnet** | UI work |
| **Multi-Crate Refactor** | "Reorganize rf-dsp, rf-engine, rf-bridge" | **Opus** (plan) → **Sonnet** (execute) | Architecture change |
| **Single Module Refactor** | "Refactor mixer_provider.dart" | **Sonnet** | Component work |
| **Documentation Update** | "Update LOWER_ZONE_TYPES.md" | **Sonnet** | Routine docs |
| **Philosophy Document** | "Write audio engine philosophy" | **Opus** | Visionary |

---

## 🚨 EDGE CASES — Gray Zones Resolved

### Case 1: Hybrid Tasks (Analysis + Implementation)

**Scenario:** "Analyze DAW Lower Zone and create a TODO"

**Decision:**
- If analysis is exploratory → **Sonnet** (analyze) → **Sonnet** (TODO)
- If analysis requires architectural redesign → **Opus** (design) → **Sonnet** (TODO + implementation)

**Rule:** Default to **Sonnet** unless explicitly architectural.

---

### Case 2: "Ultimate" Analysis

**Scenario:** "Comprehensive system review from 9 roles"

**Decision:**
- If output is strategic/visionary → **Opus**
- If output is actionable task list → **Sonnet**

**Boundary:** Ask yourself:
> "Is this document shaping the future vision of FluxForge (Opus),
> or documenting/analyzing what exists (Sonnet)?"

**Example:**
- "Ultimate FluxForge Vision 2027" → **Opus**
- "DAW Lower Zone Role Analysis 2026-01-26" → **Sonnet** (analyzing existing)

---

### Case 3: Large File Refactoring

**Scenario:** "Split daw_lower_zone_widget.dart (5,459 LOC) into modules"

**Decision:**
1. **Module Structure Design** → **Sonnet** (not changing fundamental architecture)
2. **File Splitting Execution** → **Sonnet**

**Why Sonnet, not Opus?**
- This is refactoring existing code, not designing a new system
- Architecture (tabs, providers) stays the same
- Only file organization changes

**When it WOULD be Opus:**
- If redesigning the entire Lower Zone architecture (e.g., switching from tabs to workspaces)
- If fundamentally changing state management pattern

---

### Case 4: Documentation Tiers

| Document Type | Example | Model |
|---------------|---------|-------|
| **Master Spec** | `ADAPTIVE_LAYER_ENGINE.md` | **Opus** |
| **Architecture Doc** | `DSP_ENGINE_INTEGRATION.md` | **Opus** |
| **Analysis Report** | `DAW_LOWER_ZONE_ROLE_ANALYSIS.md` | **Sonnet** |
| **TODO List** | `DAW_LOWER_ZONE_TODO.md` | **Sonnet** |
| **Task Tracking** | `CONTAINER_P0_INTEGRATION.md` | **Sonnet** |
| **Code Guide** | `PROVIDER_ACCESS_PATTERN.md` | **Sonnet** |
| **Philosophy** | `AUDIO_ENGINE_PHILOSOPHY.md` | **Opus** |
| **Roadmap** | `MASTER_ROADMAP_2026_Q1.md` | **Opus** |

**Rule of Thumb:**
- "Ultimate", "Master", "Philosophy", "Vision" → **Opus**
- "Analysis", "TODO", "Task", "Guide", "Review" → **Sonnet**

---

### Case 5: Task Tool Delegation

**When using `Task` tool, which `model` parameter to use?**

| Subagent Type | Task Example | Model Parameter |
|---------------|--------------|-----------------|
| `Explore` | "Find all FFI calls in codebase" | `haiku` or omit (default) |
| `Plan` | "Plan implementation for new feature" | `sonnet` (default is fine) |
| `general-purpose` | "Multi-step research + implementation" | `sonnet` |
| `Bash` | "Run cargo build and report errors" | N/A (no model param) |

**Rule:** Task tool defaults to `sonnet` — only override if you need `haiku` for speed/cost.

**Never use `opus` in Task tool** — Opus should be used directly in main conversation, not delegated.

---

## ✅ THE MANDATORY DECISION PROTOCOL

**Before EVERY task, Claude MUST ask these 3 questions:**

### Question 1: Does this task **fundamentally change** the system architecture?

**Examples of "fundamentally change":**
- Switching from Provider to Bloc state management
- Redesigning audio routing from scratch
- Moving from monolithic to microservices
- Changing from Rust to C++ for DSP

**If YES:** Consider **Opus** (ask user to confirm)
**If NO:** Proceed to Question 2

---

### Question 2: Is this an **ultimate/master/vision** document?

**Keywords that trigger YES:**
- "Ultimate"
- "Master specification"
- "Philosophy"
- "Long-term vision"
- "Comprehensive system design"

**If YES:** Consider **Opus** (ask user to confirm)
**If NO:** Proceed to Question 3

---

### Question 3: Does this task involve **writing/modifying code**?

**Keywords that trigger YES:**
- "Implement"
- "Refactor"
- "Add feature"
- "Fix bug"
- "Write function"
- "Create widget"

**If YES:** Use **Sonnet** (no question needed)
**If NO:** Check if it's analysis/documentation → **Sonnet**

---

### Default Rule (When Uncertain)

**IF in doubt → Use Sonnet.**

**Why?**
- Sonnet is cheaper
- Sonnet is faster
- 90% of tasks are implementation/analysis
- Opus should be reserved for truly strategic work

---

## 🔄 SELF-CORRECTION PROTOCOL

**What if Claude realizes mid-task that the wrong model was chosen?**

### Step 1: Recognize the Error

**Signs you're using wrong model:**
- **Opus doing implementation** → Should be Sonnet
- **Sonnet making architectural decisions** → Should ask user if Opus needed

### Step 2: Stop and Acknowledge

```
"⚠️ MODEL MISMATCH DETECTED

I started this task with [Opus/Sonnet], but I now realize this is:
- [Architectural/Implementation] work
- Should use [Opus/Sonnet] instead

Pausing for user confirmation."
```

### Step 3: Ask for Guidance

**Never auto-switch mid-task** — always ask user:

> "Should I:
> A) Continue with current model (Opus/Sonnet)
> B) Switch to recommended model (Sonnet/Opus)
> C) Split task into phases (Opus design → Sonnet implementation)"

---

## 🚑 EMERGENCY OVERRIDE CLAUSE

**Can Claude ever break the Opus/Sonnet rule?**

**Answer: Only in these scenarios:**

### Override Scenario 1: User Explicit Request

**User says:** "Use Opus for this implementation task"

**Claude response:** Acknowledge and comply, but warn:

> "⚠️ Note: This is typically a Sonnet task (implementation).
> Proceeding with Opus as requested, but this may be suboptimal."

Then proceed with Opus.

---

### Override Scenario 2: Critical Architectural Discovery During Implementation

**Scenario:** Claude is implementing a feature with Sonnet and discovers the entire architecture is flawed.

**Claude response:**

> "🚨 ARCHITECTURAL ISSUE DISCOVERED
>
> While implementing [task], I discovered that the current architecture
> [specific issue]. This requires fundamental redesign.
>
> Recommend:
> 1. Pause current implementation
> 2. Switch to Opus for architectural redesign
> 3. Resume implementation with Sonnet after redesign
>
> Proceed?"

**User must approve** before switching to Opus.

---

### Override Scenario 3: NONE — Always Ask User

**There are NO scenarios where Claude auto-switches without user approval.**

---

## 📝 PRACTICAL EXAMPLES — Real FluxForge Tasks

### Example 1: ✅ CORRECT — Sonnet for Analysis

**User:** "Analyze DAW Lower Zone by 9 roles"

**Claude Decision:**
- Question 1: Fundamental change? NO (analyzing existing)
- Question 2: Ultimate doc? NO (analysis report)
- Question 3: Code work? NO, but analysis → **Sonnet**

**Result:** Analysis completed with Sonnet ✅

---

### Example 2: ✅ CORRECT — Sonnet for TODO

**User:** "Create detailed TODO for DAW Lower Zone improvements"

**Claude Decision:**
- Question 1: Fundamental change? NO (task management)
- Question 2: Ultimate doc? NO (TODO list)
- Question 3: Code work? NO, but task breakdown → **Sonnet**

**Result:** TODO created with Sonnet ✅

---

### Example 3: ✅ CORRECT — Opus for Architecture

**User:** "Design a new event-driven middleware system from scratch"

**Claude Decision:**
- Question 1: Fundamental change? YES (new system design)
- Question 2: Ultimate doc? YES (master spec will result)
- → **Opus** required

**Result:** Architecture design with Opus ✅

---

### Example 4: ❌ WRONG — Opus for Refactoring

**User:** "Refactor mixer_provider.dart to use better patterns"

**Incorrect Decision:** Use Opus (thinking it's architectural)

**Correct Decision:**
- Question 1: Fundamental change? NO (refactoring one file)
- Question 3: Code work? YES → **Sonnet**

**Result:** Should use Sonnet ✅

---

### Example 5: ⚠️ GRAY ZONE — Requires User Clarification

**User:** "Redesign the entire audio routing system"

**Claude Decision:**
- Question 1: Fundamental change? UNCLEAR (depends on scope)
- Need to ask user:

> "Clarification needed:
>
> Option A) Design NEW routing architecture from scratch → Opus
> Option B) Refactor existing routing for better performance → Sonnet
>
> Which is this task?"

---

## 🎯 TRIGGER WORDS — Quick Reference

### ⚡ OPUS Triggers

| Word/Phrase | Context |
|-------------|---------|
| "Ultimate" | Ultimate analysis, ultimate spec |
| "Master" | Master specification, master plan |
| "Philosophy" | System philosophy, design philosophy |
| "Vision" | Long-term vision, strategic vision |
| "Design from scratch" | New system design |
| "Should we" | Strategic decision questions |
| "Paradigm" | Paradigm shifts |
| "Comprehensive review" | If output is strategic roadmap |

### ⚙️ SONNET Triggers

| Word/Phrase | Context |
|-------------|---------|
| "Implement" | Feature implementation |
| "Refactor" | Code refactoring |
| "Fix" | Bug fixes |
| "Add" | Add feature, add function |
| "Create TODO" | Task management |
| "Analyze [existing]" | Code analysis |
| "Write [code]" | Code generation |
| "Debug" | Debugging |
| "Optimize" | Performance tuning |

### 🚫 FORBIDDEN for Opus

| Word/Phrase | Reason |
|-------------|--------|
| "Implement X feature" | Implementation = Sonnet |
| "Write code for Y" | Code writing = Sonnet |
| "Fix bug in Z" | Debugging = Sonnet |
| "Refactor component" | Refactoring = Sonnet |

---

## 📋 CHECKLIST — Before Every Major Task

**Claude MUST mentally check:**

- [ ] Does this fundamentally change architecture?
- [ ] Is this an ultimate/master/vision document?
- [ ] Does this involve writing/modifying code?
- [ ] Am I 100% certain which model to use?
- [ ] If uncertain → Default to Sonnet
- [ ] If Opus → Ask user to confirm before starting

---

## 🔍 META RULE — Policy Updates

**Who can update this policy?**
- User (korisnik) can always override
- Claude can suggest improvements, but never unilaterally change

**When to suggest policy updates:**
- New edge case discovered
- Ambiguity found in existing rules
- Model capabilities change (e.g., Opus 5.0 released)

**How to suggest:**
> "⚠️ POLICY GAP DETECTED
>
> Current policy doesn't cover [scenario].
> Suggest adding:
> [proposed rule]
>
> Approve?"

---

## 📊 COST AWARENESS

**Model Costs (Relative):**
- Haiku: 1x (cheapest)
- Sonnet: ~10x
- Opus: ~30x

**Optimization Rule:**
- Prefer Sonnet unless Opus is truly necessary
- Use Haiku for trivial/quick tasks (optional)
- Never use Opus for routine work

**Cost Justification:**
- Opus should only be used for tasks that save DAYS of work
- Example: Opus architectural design prevents weeks of wrong implementation

---

## 🎓 LEARNING & ADAPTATION

**What if Claude makes mistakes?**

1. **Log the error** — Document what went wrong
2. **Update policy** — Suggest policy addition (with user approval)
3. **Prevent recurrence** — Add to trigger words / edge cases

**Continuous improvement:** This policy should evolve as FluxForge grows.

---

## ✅ FINAL RULE — The Ultimate Tiebreaker

**When absolutely nothing else helps:**

> **Ask the user which model to use.**

Never guess. Never assume. **Always ask.**

---

**End of Policy — No Gaps, No Exceptions, No Confusion.**

**Violations of this policy are considered critical errors.**
