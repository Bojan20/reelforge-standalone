# FluxForge Studio — MASTER TODO

**Updated:** 2026-01-30
**Status:** 🚧 **REALISTIC ASSESSMENT — 65% Functional, Needs Polish**

---

## 📊 REALISTIC STATUS (After Ultimate Analysis + Cross-Verification)

| Phase | Tasks | Done | Remaining | Effort | Status |
|-------|-------|------|-----------|--------|--------|
| 🔴 **P0 Critical (Blockers)** | 15 | 3 | 12 | 35-50h | 🚧 20% |
| 🟠 **P1 High (Major UX)** | 29 | 0 | 29 | 99-129h | ❌ 0% |
| 🟡 **P2 Medium (Polish)** | 21 | 0 | 21 | 103-138h | ❌ 0% |
| 🟢 **P3 Low (Future)** | 12 | 0 | 12 | 250-340h | ❌ 0% |
| **TOTAL** | **77** | **3** | **74** | **487-657h** | **4%** |

**Cross-Verified By:** Claude Sonnet (added 8 gaps Opus missed)

⚠️ **CORE WORKS, WORKFLOWS NEED POLISH** — 6-10 weeks to production-ready

---

## WHAT WORKS ✅

**Solid Foundation (60-70% functional):**
- ✅ Rust engine (audio playback, FFI bridge working)
- ✅ Event creation system (UI → Provider → Registry → Audio)
- ✅ Container evaluation (Blend/Random/Sequence FFI ~40 functions)
- ✅ Stage Trace timeline visualization
- ✅ GDD Import (symbol/grid/feature parsing)
- ✅ Profiler (voice pool, DSP load, memory stats)
- ✅ Ducking matrix (full sidechain system)
- ✅ RTPC curves (modulation working)
- ✅ Export adapters (Unity/Unreal/Howler.js exist)

---

## WHAT'S BROKEN ❌

**Critical Gaps (prevent production use):**
- ❌ Events Folder: DELETE works but visual update delayed (debounce)
- ❌ 12 UI overflow issues (mainAxisSize.min in Flexible)
- ❌ ALE layer assignment has no UI (code exists, UI missing)
- ❌ Audio preview ignores layer offsets (plays all at t=0)
- ❌ GDD symbols don't auto-generate stages (20+ manual mappings)
- ❌ Win tier templates missing (6+ manual creations)
- ❌ Grid changes don't regenerate reel stages
- ❌ No test template library for QA
- ❌ No undo history visualization
- ❌ No custom event handler extension
- ❌ No stage coverage tracking
- ❌ No event dependency graph

---

## 🔴 P0 CRITICAL TASKS (15 Total, 3 Done, 12 Remaining)

### UI Connectivity Fixes (5 tasks)

| ID | Task | File | Lines | Status | Effort |
|----|------|------|-------|--------|--------|
| UI-01 | Events Folder DELETE visual update | `events_folder_panel.dart` | 1332 | ✅ FIXED | — |
| UI-02 | Grid dimension sync to preview | `premium_slot_preview.dart` | 5012 | ✅ FIXED | — |
| UI-03 | Timing profile sync to FFI | `slot_lab_screen.dart` | 3324 | ✅ FIXED | — |
| UI-04 | Lower Zone overflow (14 locations) | `slotlab_lower_zone_widget.dart` | Multiple | ❌ TODO | 4-6h |
| UI-05 | Context bar sub-tabs overflow | `lower_zone_context_bar.dart` | 345-366 | ❌ TODO | 2-3h |

**Details:**
- **UI-04:** Remove `mainAxisSize: MainAxisSize.min` from 14 Columns inside Flexible
  - Lines: 507, 536, 565, 934, 936, 1088, 1267, 1303, 1795, 1842, 2155, 2169, 2289, 2356
  - Impact: Panels don't expand when Lower Zone is resized
  - Fix: Replace with `mainAxisSize: MainAxisSize.max` or remove constraint

- **UI-05:** Wrap sub-tabs Row in `SingleChildScrollView`
  - File: `lower_zone_context_bar.dart:355`
  - Impact: Sub-tabs overflow horizontally when >8 tabs
  - Fix: Add horizontal scroll + `clipBehavior: Clip.hardEdge`

### Workflow Gaps (10 tasks)

| ID | Task | Role | Status | Effort |
|----|------|------|--------|--------|
| WF-01 | GDD symbol → stage auto-generation | Game Designer | ❌ TODO | 2-3h |
| WF-02 | Win tier template generator | Game Designer | ❌ TODO | 1-2h |
| WF-03 | Grid change → reel stage regeneration | Game Designer | ❌ TODO | 3-4h |
| WF-04 | ALE layer selector UI | Audio Designer | ❌ TODO | 4-6h |
| WF-05 | Audio preview with layer offsets | Audio Designer | ❌ TODO | 2-3h |
| WF-06 | Custom event handler extension | Tooling Developer | ❌ TODO | 3-4h |
| WF-07 | Stage→asset CSV export | Tooling Developer | ❌ TODO | 2-3h |
| WF-08 | Test template library | QA Engineer | ❌ TODO | 3-4h |
| WF-09 | Determinism replay with seed trace | QA Engineer | ❌ TODO | 4-5h |
| WF-10 | Stage coverage tracking | QA Engineer | ❌ TODO | 3-4h |

**Details:**
- **WF-01:** Modify `gdd_import_service.dart` to call `_generateSymbolStages(gdd.symbols)`
  - For each symbol: Generate SYMBOL_LAND_X, WIN_SYMBOL_HIGHLIGHT_X, EXPAND_X stages
  - Auto-register in EventRegistry with template audio slots

- **WF-04:** Add `aleLayerId` field to `AudioEvent`, dropdown in event inspector
  - File: `event_editor_panel.dart` or `events_folder_panel.dart`
  - Dropdown: L1 (Calm), L2 (Tense), L3 (Excited), L4 (Intense), L5 (Epic)
  - Provider: `updateEventLayer(eventId, layer.copyWith(aleLayerId: X))`

- **WF-05:** Fix `AudioPlaybackService.previewEvent()` to schedule delayed layers
  - Use `Future.delayed(Duration(milliseconds: layer.offsetMs))` for each layer
  - Current: All layers play at t=0, offsets ignored

---

## 🟠 P1 HIGH PRIORITY TASKS (29 Total, 0 Done)

### Cross-Verification Additions (5 new tasks from Sonnet)

| ID | Task | Impact | Effort |
|----|------|--------|--------|
| P1-19 | DAW Timeline selection state persistence | Cross-section state loss | 2-3h |
| P1-20 | Container evaluation logging | QA debugging | 3-4h |
| P1-21 | Plugin PDC visualization in FX Chain | DSP transparency | 4-5h |
| P1-22 | Cross-section event playback validation | Data integrity | 3-4h |
| P1-23 | FFI function binding audit (1688 vs 33) | Completeness check | 2-3h |

### Audio Designer Improvements (3 tasks)

| ID | Task | Impact | Effort |
|----|------|--------|--------|
| P1-01 | Audio variant group + A/B UI | Systematic comparison | 6-8h |
| P1-02 | LUFS normalization preview | Validate loudness balance | 3-4h |
| P1-03 | Waveform zoom per-event | Fine-grained timing | 2-3h |

### Middleware Architect Tools (4 tasks)

| ID | Task | Impact | Effort |
|----|------|--------|--------|
| P1-04 | Undo history visualization panel | Trust in undo system | 3-4h |
| P1-05 | Container smoothing UI control | Fine-tune RTPC response | 2-3h |
| P1-06 | Event dependency graph | Detect circular refs | 6-8h |
| P1-07 | Container real-time metering | Live blend evaluation | 4-6h |

### Engine Developer Profiling (4 tasks)

| ID | Task | Impact | Effort |
|----|------|--------|--------|
| P1-08 | End-to-end latency measurement | Validate <5ms SLA | 4-5h |
| P1-09 | Voice steal statistics | Priority bug detection | 3-4h |
| P1-10 | Stage→event resolution trace | Debugging clarity | 5-6h |
| P1-11 | DSP load attribution | Performance bottleneck ID | 6-8h |

### Game Designer Templates (2 tasks)

| ID | Task | Impact | Effort |
|----|------|--------|--------|
| P1-12 | Feature template library (FS/Bonus/Hold&Win) | 80% faster setup | 8-10h |
| P1-13 | Volatility → expected hold time calculator | Validate design | 4-6h |

### Tooling Developer API (2 tasks)

| ID | Task | Impact | Effort |
|----|------|--------|--------|
| P1-14 | Scripting API (JSON-RPC + Lua) | Automation ecosystem | 8-12h |
| P1-15 | Hook system (onCreate/onDelete) | Event-driven tooling | 6-8h |

### QA Engineer Testing (2 tasks)

| ID | Task | Impact | Effort |
|----|------|--------|--------|
| P1-16 | Multi-condition test combinator | Systematic edge case testing | 5-6h |
| P1-17 | Event timing validation | SLA enforcement | 4-6h |

### DSP Engineer Visualization (1 task)

| ID | Task | Impact | Effort |
|----|------|--------|--------|
| P1-18 | Per-track frequency response viz | Visual EQ feedback | 5-6h |

### UX Improvements (6 tasks)

| ID | Task | Impact | Effort |
|----|------|--------|--------|
| UX-01 | Interactive onboarding tutorial | Reduce learning curve | 6-8h |
| UX-02 | One-step event creation | 60% time savings | 2-3h |
| UX-03 | Human-readable event names | Clarity | 2-3h |
| UX-04 | Smart tab organization | Discoverability | 4-6h |
| UX-05 | Enhanced drag visual feedback | Precision | 4-5h |
| UX-06 | Keyboard shortcuts | Power users | 3-4h |

---

## 🟡 P2 MEDIUM PRIORITY TASKS (21 Total)

### Cross-Verification Additions (3 new tasks from Sonnet)

| ID | Task | Impact | Effort |
|----|------|--------|--------|
| P2-19 | Performance regression tests in CI | Catch perf drops | 6-8h |
| P2-20 | Input validation consistency audit | Security/stability | 4-6h |
| P2-21 | Memory leak risk in dispose() methods | Memory stability | 3-4h |

[See `.claude/ULTIMATE_SLOTLAB_GAPS_2026_01_30.md` for full list]

Key items:
- Processor latency compensation (3-4h)
- FMOD/Wwise export (18-22h)
- Collaborative projects (20-24h)
- Live WebSocket integration (12-16h)

---

## 🟢 P3 LOW PRIORITY TASKS (12 Total)

[See `.claude/ULTIMATE_SLOTLAB_GAPS_2026_01_30.md` for full list]

Future enhancements:
- Cloud sync (16-20h)
- Mobile companion (40-60h)
- AI audio matching (60-80h)

---

### P4 Breakdown Verified (2026-01-30)

| Category | Tasks | LOC | Files |
|----------|-------|-----|-------|
| DSP Features | 2 | ~1,800 | eq.rs, multiband.rs, linear_phase.rs |
| Platform Adapters | 3 | ~2,085 | unity_exporter.dart, unreal_exporter.dart, howler_exporter.dart |
| WASM/Optimization | 3 | ~727+ | rf-wasm/lib.rs |
| QA & Testing | 6 | ~3,630 | rf-fuzz, rf-audio-diff, rf-coverage, rf-release |
| Producer Tools | 3 | ~1,050 | client_review_mode, export_package, version_comparison |
| Accessibility | 8 | ~2,940 | accessibility/, particles/, scripting/ |
| Video Export | 1 | ~680 | video_export_service.dart |
| **TOTAL** | **26** | **~12,912** | **✅ All Verified** |

---

## 📁 ARCHIVED TASK DOCUMENTATION

All completed task details have been archived to:

| Document | Content |
|----------|---------|
| `.claude/tasks/P4_COMPLETE_VERIFICATION_2026_01_30.md` | P4.1-P4.26 verification |
| `.claude/tasks/SLOTLAB_P0_VERIFICATION_2026_01_30.md` | SlotLab P0 verification |
| `.claude/tasks/SLOTLAB_P2_UX_VERIFICATION_2026_01_30.md` | SlotLab P2 UX verification |
| `.claude/PROJECT_STATUS_2026_01_30.md` | Complete project status |
| `.claude/CHANGELOG.md` | Development history |

---

## 🏗️ COMPLETED SYSTEMS SUMMARY

### Core Engine (Rust)
- ✅ rf-dsp — DSP processors, SIMD, Linear Phase EQ, Multiband Compression
- ✅ rf-engine — Audio graph, routing, playback
- ✅ rf-bridge — Flutter-Rust FFI bridge
- ✅ rf-slot-lab — Synthetic slot engine
- ✅ rf-ale — Adaptive Layer Engine
- ✅ rf-wasm — WebAssembly port
- ✅ rf-offline — Batch processing, EBU R128

### Flutter UI
- ✅ DAW Section — Timeline, mixer, effects, routing
- ✅ Middleware Section — Events, containers, RTPC, ducking
- ✅ SlotLab Section — Slot preview, stage system, audio authoring

### Platform Adapters
- ✅ Unity Adapter — C# + JSON export
- ✅ Unreal Adapter — C++ + JSON export
- ✅ Howler.js Adapter — TypeScript + JSON export

### QA & Testing
- ✅ CI/CD Pipeline — 14 jobs, cross-platform
- ✅ Regression Tests — 14 DSP tests
- ✅ Test Automation API — Scenario-based testing
- ✅ Session Replay — Deterministic replay

### Accessibility
- ✅ High Contrast Mode
- ✅ Color Blindness Support
- ✅ Reduced Motion
- ✅ Keyboard Navigation
- ✅ Screen Reader Support

---

## 📈 PROJECT METRICS

| Metric | Value |
|--------|-------|
| Total LOC (Rust) | ~38,628 |
| Total LOC (Flutter) | ~70,000 |
| Total LOC (Docs) | ~15,000 |
| **Grand Total** | **~123,628** |
| Rust Crates | 15 |
| Flutter Providers | 25+ |
| FFI Functions | 200+ |
| Regression Tests | 14 |
| CI/CD Jobs | 14 |

---

## 🔮 FUTURE ENHANCEMENTS (Optional)

These are not blockers — system is production-ready without them:

1. **Plugin Hosting** — Real-time VST3/AU/CLAP hosting
2. **Cloud Sync** — Project backup and collaboration
3. **AI Mastering** — ML-based audio processing
4. **Video Sync** — Frame-accurate video playback
5. **Undo Stack Serialization** — Disk offload for large undo history

---

## ✅ VERIFICATION

```bash
# Build verification (2026-01-30)
cargo check --workspace  # ✅ SUCCESS
flutter analyze          # ✅ 8 info-level (0 errors)
```

---

*Last Updated: 2026-01-30*
*Version: 1.0.0 — Production Release*
