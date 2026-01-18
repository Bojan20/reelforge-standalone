# AUTO-REVIEW MODE — FluxForge Studio (Gatekeeper + Self-Audit)

You are NOT implementing new features now.
You are reviewing the last implementation as a Principal Engineer / Gatekeeper.
You MUST run the audit commands below and base your verdict on evidence.

## MUST-READ (in order)
1) CLAUDE.md (STOP + CORE REFERENCES)
2) .claude/00_AUTHORITY.md
3) .claude/01_BUILD_MATRIX.md
4) .claude/02_DOD_MILESTONES.md
5) .claude/03_SAFETY_GUARDRAILS.md

## HARD RULES
- Do NOT ask me questions unless a blocking ambiguity exists.
- Do NOT propose “nice-to-have”. Only correctness, safety, determinism, performance.
- Output must be short, decisive, evidence-based.

---

## STEP 0 — REQUIRED COMMANDS (run exactly)

### 0A) Flutter (if any UI/Dart files changed)
Run:
```bash
cd flutter_ui
flutter analyze
```
Result MUST be 0 errors.

### 0B) Rust (if any Rust files changed)
Run:
```bash
cargo build --release
cargo test
cargo clippy
```

If any command fails → verdict is FAIL.

---

## STEP 1 — LAW CHECKS (grep audits)

Run these searches from repo root and inspect results.

### 1A) Timeline must be sample-accurate (no DateTime clock inference)
```bash
rg -n "DateTime\\.now\\(|difference\\(|_playbackStartTime|inMilliseconds" flutter_ui || true
rg -n "DateTime" flutter_ui || true
```
If timeline tracking still uses DateTime → FAIL.

### 1B) Audio thread must not allocate or lock
Search for allocations/locks in hot paths (process(), callback, render, routing RT):
```bash
rg -n "process\\(|process_block|audio callback|callback\\(" crates || true
rg -n "Vec::new\\(|vec!\\[|HashMap::new\\(|String::new\\(|format!\\(" crates/rf-engine crates/rf-dsp || true
rg -n "Mutex<|RwLock<|lock\\(|write\\(|read\\(" crates/rf-engine crates/rf-dsp || true
```
If allocations/locks are inside real-time processing paths → FAIL.

### 1C) Waveform must not rebuild on zoom / must use cache & batching
```bash
rg -n "rebuild|recompute|build_cache\\(|compute_waveform|decode.*waveform" flutter_ui || true
rg -n "zoom|scale|pixels_per|frames_per_pixel|LOD|bucket" flutter_ui || true
```
If UI zoom triggers full recompute or blocks UI thread → FAIL.

### 1D) FFI safety (buffers must have capacity and bounds checks)
```bash
rg -n "extern \"C\"|no_mangle|\\*mut|\\*const|out_capacity|out_" crates/rf-engine/src/ffi.rs || true
rg -n "calloc<|Pointer<|asTypedList\\(" flutter_ui/lib/src/rust || true
```
If any FFI writes without capacity guard → FAIL.

### 1E) Routing must remain graph-based + lock-free commands
```bash
rg -n "RoutingGraphRT|topological|cycle|rtrb|command_tx|command_rx" crates/rf-engine/src/routing.rs || true
```
If changes reintroduce hardcoded routing or locks in RT → FAIL.

---

## STEP 2 — DOD CHECK (milestone gate)

Identify which milestone the change belongs to:
- Plugin Hosting
- Recording
- Export/Render
- Waveform/Sample Editor
- Timeline/VSync
- Automation

Then verify the corresponding exit criteria from `.claude/02_DOD_MILESTONES.md`.
If anything missing → FAIL.

---

## STEP 3 — PRODUCE REVIEW OUTPUT (MANDATORY FORMAT)

Verdict: ✅ PASS — Merge-safe  /  ❌ FAIL — Must fix before merge

Evidence:
- flutter analyze: <PASS/FAIL + key line>
- cargo build: <PASS/FAIL>
- cargo test: <PASS/FAIL>
- cargo clippy: <PASS/FAIL>

Law violations (from grep + inspection):
- [LAW-x] <what> — <file:line> — <why violates> — <required fix>

DoD:
- Milestone: <name>
- DoD: ✅ met / ❌ not met
- Missing items:
  - ...

Risks (only critical):
- [RISK] <risk> — <impact> — <where> — <fix>

Perf (only real issues):
- [PERF] <issue> — <where> — <fix>

Required patches (ONLY if FAIL):
- Minimal patch list (surgical):
  1) <file> — <exact change>
  2) <file> — <exact change>
