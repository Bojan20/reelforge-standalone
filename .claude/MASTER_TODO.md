# FluxForge Studio — MASTER TODO

**Updated:** 2026-02-01
**Status:** ✅ **PRODUCTION READY** — P0-P9 Complete, Ultimate Analysis Complete

---

## 🎯 CURRENT STATE

**SHIP READY (Previous Milestones):**
- ✅ `flutter analyze` = 0 errors, 0 warnings
- ✅ P0-P2 = 100% Complete (63/63 tasks)
- ✅ P4 SlotLab Spec = 100% Complete (64/64 tasks)
- ✅ P3 Quick Wins = 100% Complete (5/5 tasks)
- ✅ P5 Win Tier System = 100% Complete (9/9 phases)
- ✅ P6 Premium Slot Preview V2 = 100% Complete (7/7 tasks)
- ✅ P7 Anticipation System V2 = 100% Complete (11/11 tasks)
- ✅ P8 Ultimate Audio Panel Analysis = 100% Complete (12/12 sections)
- ✅ P9 Audio Panel Consolidation = 100% Complete (12/12 tasks)

**ACTIVE — Feature Builder Panel:**
- 🟣 **P13 Feature Builder** — 75 tasks, 27 days, ~12,400 LOC
  - ✅ P13.8 Integration: Apply & Build flow complete (5/9 tasks)
  - ✅ P13.9 Additional Blocks: 5/9 complete (Jackpot, Multiplier, BonusGame, Gambling, Transitions)

**NEXT — Ultimate Analysis Gap Resolution:**
- 🔴 **P10 DAW Gaps** — 5 P0 + 20 P1 + 21 P2 = 46 tasks
- 🟡 **P11 Middleware Gaps** — 0 P0 + 8 P1 + 12 P2 = 20 tasks
- 🔵 **P12 SlotLab Gaps** — 5 P0 + 18 P1 + 13 P2 = 36 tasks

---

## 📊 ULTIMATE ANALYSIS RESULTS (2026-01-31)

| Section | Score | P0 | P1 | P2 | Total Gaps |
|---------|-------|----|----|----|----|
| **DAW** | 84% | 5 | 20 | 21 | 46 |
| **Middleware** | 92% | 0 | 8 | 12 | 20 |
| **SlotLab** | 87% | 5 | 18 | 13 | 36 |
| **TOTAL** | **88%** | **10** | **46** | **46** | **102** |

**Analysis Documents:**
- `.claude/analysis/DAW_ULTIMATE_ANALYSIS_2026_01_31.md`
- `.claude/reviews/MIDDLEWARE_ULTIMATE_ANALYSIS_2026_01_31.md`
- `.claude/reviews/SLOTLAB_ULTIMATE_ANALYSIS_2026_01_31.md`

---

## 🔴 P10 — DAW SECTION GAPS (Score: 84%)

### P10.0 — CRITICAL (P0) — Must Fix Before Production

| ID | Role | Gap | Description | Impact | LOC Est. | File |
|----|------|-----|-------------|--------|----------|------|
| **P10.0.1** | DSP Engineer | Per-processor metering | Cannot verify signal levels at each insert point | Professional mixing impossible | ~400 | `dsp_chain_provider.dart`, `ffi.rs` |
| **P10.0.2** | Engine Architect | Graph-level PDC | Parallel paths may have timing issues | Phase issues in complex routing | ~600 | `routing.rs`, `routing_provider.dart` |
| **P10.0.3** | Engine Architect | Auto PDC detection | Manual entry error-prone for complex chains | User must manually calculate latency | ~400 | `plugin_provider.dart`, `ffi.rs` |
| **P10.0.4** | Technical Director | Undo for mixer operations | Destructive changes cannot be reversed | Lost work on mistakes | ~500 | `mixer_provider.dart`, `undo_manager.dart` |
| **P10.0.5** | Graphics Engineer | LUFS history graph | No loudness trend visualization for mastering | Cannot analyze loudness over time | ~350 | `master_strip.dart`, `lufs_history_widget.dart` |

**Total P10.0:** 5 tasks, ~2,250 LOC

### P10.1 — HIGH PRIORITY (P1) — Next Sprint

| ID | Role | Gap | Description | LOC Est. | File |
|----|------|-----|-------------|----------|------|
| **P10.1.1** | Audio Architect | Sidechain visualization | Show sidechain routing in mixer | ~250 | `ultimate_mixer.dart` |
| **P10.1.2** | Audio Architect | Stem routing matrix | Visual matrix for assigning tracks to stems | ~450 | `stem_routing_matrix.dart` |
| **P10.1.3** | Audio Architect | Monitor section | Control room with dim, mono, speaker selection | ~600 | `monitor_section.dart` |
| **P10.1.4** | DSP Engineer | Factory presets for processors | Default presets for all 9 DSP types | ~300 | `fabfilter/*.dart`, `presets.json` |
| **P10.1.5** | DSP Engineer | Oversampling control | Per-processor 2x/4x/8x oversampling UI | ~200 | `fabfilter_panel_base.dart` |
| **P10.1.6** | DSP Engineer | Processor frequency graphs | Transfer function / frequency response display | ~400 | `processor_graph_widget.dart` |
| **P10.1.7** | Engine Architect | Graph visualization | Visual audio graph (nodes, connections) | ~500 | `audio_graph_panel.dart` |
| **P10.1.8** | Engine Architect | Per-track CPU load | DSP load breakdown per track | ~250 | `dsp_profiler_panel.dart`, `ffi.rs` |
| **P10.1.9** | Engine Architect | Underrun recovery UI | Buffer underrun notification and recovery | ~200 | `playback_status.dart` |
| **P10.1.10** | Technical Director | Error propagation UI | Surface FFI errors to UI consistently | ~300 | `error_handler.dart`, all providers |
| **P10.1.11** | Technical Director | Session restore | Crash recovery with auto-save | ~400 | `session_restore_service.dart` |
| **P10.1.12** | UX Expert | Undo feedback toast | Visual confirmation of undo/redo | ~100 | `undo_feedback_widget.dart` |
| **P10.1.13** | UX Expert | Collapsible sends | Hide/show send section in channel strip | ~150 | `ultimate_mixer.dart` |
| **P10.1.14** | UX Expert | Channel strip view modes | Minimal/standard/full configurations | ~300 | `channel_strip_modes.dart` |
| **P10.1.15** | UX Expert | Command palette for DAW | Cmd+K with DAW-specific commands | ~200 | `command_palette.dart` |
| **P10.1.16** | Graphics Engineer | GPU-accelerated meters | Replace widget-based with GPU rendering | ~500 | `gpu_meter_widget.dart`, shader |
| **P10.1.17** | Graphics Engineer | Correlation meter | Stereo correlation display in master | ~250 | `correlation_meter.dart` |
| **P10.1.18** | Graphics Engineer | Phase scope | Goniometer/phase scope visualization | ~350 | `phase_scope.dart` |
| **P10.1.19** | Security Expert | Plugin state validation | Integrity checks for plugin state chunks | ~200 | `plugin_state_service.dart` |
| **P10.1.20** | Security Expert | FFI rate limiting | Throttle rapid FFI calls from sliders | ~150 | `ffi_rate_limiter.dart` |

**Total P10.1:** 20 tasks, ~6,050 LOC

### P10.2 — MEDIUM PRIORITY (P2) — Backlog

| ID | Role | Gap | Description | LOC Est. | File |
|----|------|-----|-------------|----------|------|
| **P10.2.1** | Audio Architect | Nested bus hierarchy | Sub-buses within buses | ~400 | `routing_provider.dart` |
| **P10.2.2** | Audio Architect | VCA spill | Show member channels when VCA selected | ~200 | `ultimate_mixer.dart` |
| **P10.2.3** | Audio Architect | Parallel processing paths | Wet/dry parallel routing per insert | ~350 | `dsp_chain_provider.dart` |
| **P10.2.4** | DSP Engineer | A/B per processor | Individual processor A/B comparison | ~250 | `fabfilter_panel_base.dart` |
| **P10.2.5** | DSP Engineer | Linear phase mode | Toggle linear phase in DSP chain | ~200 | `dsp_chain_provider.dart`, `ffi.rs` |
| **P10.2.6** | DSP Engineer | M/S per processor | Mid/Side mode per processor | ~200 | `fabfilter_panel_base.dart` |
| **P10.2.7** | Engine Architect | Cache preloading UI | UI for audio cache preloading | ~150 | `cache_manager_panel.dart` |
| **P10.2.8** | Engine Architect | Voice stealing UI | Visual display of voice stealing | ~150 | `voice_pool_panel.dart` |
| **P10.2.9** | Technical Director | Widget file splitting | Break up large widget files | ~0 | `daw_lower_zone_widget.dart` (refactor) |
| **P10.2.10** | Technical Director | Centralized action handlers | Consolidate scattered handlers | ~300 | `daw_action_handlers.dart` |
| **P10.2.11** | Technical Director | DAW project templates | Pre-configured project templates | ~200 | `project_templates.dart` |
| **P10.2.12** | UX Expert | Keyboard navigation | Full keyboard control in DAW | ~400 | Multiple widgets |
| **P10.2.13** | UX Expert | Mixer zoom | Horizontal zoom for mixer | ~200 | `ultimate_mixer.dart` |
| **P10.2.14** | UX Expert | Contextual help | Tooltips for DSP parameters | ~300 | `fabfilter/*.dart` |
| **P10.2.15** | Graphics Engineer | Mini waveform overview | Waveform in channel strip | ~250 | `channel_strip.dart` |
| **P10.2.16** | Graphics Engineer | K-weighting toggle | K-weighting display in meters | ~100 | `meter_widgets.dart` |
| **P10.2.17** | Graphics Engineer | Mini spectrum per channel | Per-channel spectrum analyzer | ~300 | `mini_spectrum.dart` |
| **P10.2.18** | Security Expert | Path canonicalization | Always canonicalize paths | ~100 | Various |
| **P10.2.19** | Security Expert | Plugin sandboxing | Process isolation for plugins | ~800 | `plugin_sandbox.dart` |
| **P10.2.20** | Security Expert | Signed crash state | Encrypted crash recovery data | ~300 | `crash_state.dart` |
| **P10.2.21** | Security Expert | Audit logging | Log parameter changes | ~250 | `audit_logger.dart` |

**Total P10.2:** 21 tasks, ~5,400 LOC

---

## 🟡 P11 — MIDDLEWARE SECTION GAPS (Score: 92%)

### P11.0 — CRITICAL (P0) — None! ✅

**Middleware section has NO critical gaps. Ship-ready.**

### P11.1 — HIGH PRIORITY (P1) — Next Sprint

| ID | Role | Gap | Description | LOC Est. | File |
|----|------|-----|-------------|----------|------|
| **P11.1.1** | Audio Architect | Bus metering wrapper | Add `getBusMeterLevel()` wrapper in provider | ~50 | `bus_hierarchy_provider.dart` |
| **P11.1.2** | DSP Engineer | RTPC to all DSP params | Route RTPC bindings to filter, reverb, delay | ~400 | `rtpc_system_provider.dart` |
| **P11.1.3** | Engine Architect | Unregister soundbank FFI | Add `memoryManagerUnregisterBank()` FFI | ~100 | `memory_manager_provider.dart`, `ffi.rs` |
| **P11.1.4** | Technical Director | FFI nullable pattern | Standardize `NativeFFI?` vs `NativeFFI` | ~100 | All subsystem providers |
| **P11.1.5** | Technical Director | Subsystem provider tests | Unit tests for all 16 providers | ~800 | `test/providers/` |
| **P11.1.6** | UX Expert | Tab categories | Collapsible categories in AdvancedMiddlewarePanel | ~150 | `advanced_middleware_panel.dart` |
| **P11.1.7** | Security Expert | Event rate limiting | Max 100 events/second | ~100 | `composite_event_system_provider.dart` |
| **P11.1.8** | Security Expert | JSON schema validation | Validate JSON in Rust FFI | ~300 | `middleware_ffi.rs`, schema files |

**Total P11.1:** 8 tasks, ~2,000 LOC

### P11.2 — MEDIUM PRIORITY (P2) — Backlog

| ID | Role | Gap | Description | LOC Est. | File |
|----|------|-----|-------------|----------|------|
| **P11.2.1** | Audio Architect | External sidechain input | Route external audio as sidechain source | ~400 | `ducking_system_provider.dart` |
| **P11.2.2** | Audio Architect | Dynamic aux bus IDs | Auto-allocate aux bus IDs | ~100 | `aux_send_provider.dart` |
| **P11.2.3** | DSP Engineer | Envelope follower RTPC | Audio level as RTPC source | ~500 | `rtpc_system_provider.dart`, `ffi.rs` |
| **P11.2.4** | DSP Engineer | Rust path validation | Validate audio paths in Rust FFI | ~150 | `container_ffi.rs` |
| **P11.2.5** | Engine Architect | Push-based voice stats | Callback instead of polling | ~300 | `voice_pool_provider.dart`, `ffi.rs` |
| **P11.2.6** | Engine Architect | Memory pressure observer | React to system memory warnings | ~250 | `memory_manager_provider.dart` |
| **P11.2.7** | Technical Director | AuxSend FFI sync | Connect AuxSendProvider to Rust | ~400 | `aux_send_provider.dart`, `ffi.rs` |
| **P11.2.8** | UX Expert | Drag-drop container reorder | Drag to reorder containers | ~300 | `*_container_panel.dart` |
| **P11.2.9** | UX Expert | Container preset browser | Categories, search, favorites | ~400 | `container_preset_browser.dart` |
| **P11.2.10** | Graphics Engineer | Mini waveform in containers | Show audio waveform in child items | ~350 | `container_visualization_widgets.dart` |
| **P11.2.11** | Graphics Engineer | Zoom/pan container timeline | Pan and zoom in sequence editor | ~200 | `sequence_container_panel.dart` |
| **P11.2.12** | Security Expert | Audit logging | Log security-sensitive operations | ~300 | `audit_logger.dart` |

**Total P11.2:** 12 tasks, ~3,650 LOC

---

## 🔵 P12 — SLOTLAB SECTION GAPS (Score: 87%)

### P12.0 — CRITICAL (P0) — Must Fix Before Production

| ID | Role | Gap | Description | Impact | LOC Est. | File |
|----|------|-----|-------------|--------|----------|------|
| **P12.0.1** | DSP Engineer | Real-time pitch shifting | Pitch variation not real-time | Limited dynamic win audio | ~400 | `event_registry.dart`, `playback.rs` |
| **P12.0.2** | Engine Architect | FFI error result type | Functions return bool/null, no error details | Hard to debug production issues | ~300 | `slot_lab_ffi.rs`, `native_ffi.dart` |
| **P12.0.3** | Engine Architect | Async FFI wrapper | All calls are synchronous | UI blocking on slow devices | ~400 | `slot_lab_provider.dart` |
| **P12.0.4** | Security Expert | Path traversal protection | `../` not blocked in file paths | Security vulnerability | ~100 | `event_registry.dart`, various |
| **P12.0.5** | Security Expert | FFI bounds checking | Array indices unchecked | Potential crash | ~200 | `slot_lab_ffi.rs`, `native_ffi.dart` |

**Total P12.0:** 5 tasks, ~1,400 LOC

### P12.1 — HIGH PRIORITY (P1) — Next Sprint

| ID | Role | Gap | Description | LOC Est. | File |
|----|------|-----|-------------|----------|------|
| **P12.1.1** | Audio Architect | RTPC→rollup connection | Connect win amount to RTPC for volume/pitch | ~150 | `rtpc_modulation_service.dart` |
| **P12.1.2** | Audio Architect | Waveform scrubber | Scrub through audio in preview | ~400 | `audio_preview_scrubber.dart` |
| **P12.1.3** | Audio Architect | Per-bus LUFS meter | LUFS display per bus in SlotLab | ~300 | `bus_lufs_meter.dart` |
| **P12.1.4** | DSP Engineer | Time-stretch FFI | Match audio to animation timing | ~600 | `time_stretch_ffi.rs`, `native_ffi.dart` |
| **P12.1.5** | DSP Engineer | Per-layer DSP insert | Mini DSP chain per event layer | ~500 | `layer_dsp_chain.dart` |
| **P12.1.6** | Engine Architect | Engine metrics API | CPU, memory, voice stats from Rust | ~250 | `slot_lab_ffi.rs`, `engine_metrics.dart` |
| **P12.1.7** | Technical Director | Split SlotLabProvider | Decompose into focused sub-providers | ~600 | `slot_lab_provider.dart` → multiple |
| **P12.1.8** | Technical Director | JSDoc documentation | Document all public methods | ~400 | All SlotLab files |
| **P12.1.9** | UX Expert | Undo snackbar | Visual feedback for undo/redo | ~100 | `undo_snackbar.dart` |
| **P12.1.10** | UX Expert | Lower Zone presets | Quick switch between layouts | ~350 | `workspace_preset_service.dart` |
| **P12.1.11** | Graphics Engineer | Shader integration | Use `anticipation_glow.frag` | ~200 | `professional_reel_animation.dart` |
| **P12.1.12** | Graphics Engineer | Win line grow animation | Animate line from first to last symbol | ~150 | `slot_preview_widget.dart` |
| **P12.1.13** | Security Expert | Event rate limiter | Max 100 events/second | ~150 | `event_registry.dart` |
| **P12.1.14** | Security Expert | Input sanitization | Strip HTML from event names | ~100 | `composite_event_system_provider.dart` |
| **P12.1.15** | QA Engineer | Event log CSV export | Export triggered events for QA | ~150 | `event_profiler_provider.dart` |
| **P12.1.16** | QA Engineer | Flutter coverage CI | lcov in GitHub Actions | ~100 | `.github/workflows/ci.yml` |
| **P12.1.17** | Producer | Demo project | Sample project with audio | ~50 | `assets/demo_project/` |
| **P12.1.18** | Producer | Video tutorials | 5 key workflow tutorials | N/A | YouTube/docs |

**Total P12.1:** 18 tasks, ~4,550 LOC

### P12.2 — MEDIUM PRIORITY (P2) — Backlog

| ID | Role | Gap | Description | LOC Est. | File |
|----|------|-----|-------------|----------|------|
| **P12.2.1** | Audio Architect | SlotLab ducking presets | Pre-configured ducking for slots | ~250 | `ducking_presets.dart` |
| **P12.2.2** | DSP Engineer | Sidechain containers | Blend volumes based on game signals | ~350 | `container_service.dart` |
| **P12.2.3** | Engine Architect | Graceful degradation | Fallback when FFI fails | ~200 | `slot_lab_provider.dart` |
| **P12.2.4** | Technical Director | Migrate singletons | All services through GetIt | ~200 | Various services |
| **P12.2.5** | Technical Director | Naming convention lint | Dart lint rules for style | ~50 | `analysis_options.yaml` |
| **P12.2.6** | UX Expert | Keyboard-only assignment | Tab+Enter to assign audio | ~300 | `drop_target_wrapper.dart` |
| **P12.2.7** | UX Expert | Onboarding wizard | Step-by-step first event | ~500 | `onboarding_wizard.dart` |
| **P12.2.8** | Graphics Engineer | Enhanced symbol anims | 3D flip, rotation, particles | ~350 | `symbol_animation.dart` |
| **P12.2.9** | Graphics Engineer | Configurable screen shake | Intensity, duration, decay | ~100 | `screen_shake.dart` |
| **P12.2.10** | QA Engineer | Visual regression tests | Screenshot comparison | ~500 | `test/visual/` |
| **P12.2.11** | QA Engineer | A/B config comparison | Side-by-side audio diff | ~400 | `ab_comparison.dart` |
| **P12.2.12** | Producer | Cloud sync | Firebase/S3 backup | ~800 | `cloud_sync_service.dart` |
| **P12.2.13** | Producer | Template marketplace | Share/sell templates | ~1,500 | `marketplace/` |

**Total P12.2:** 13 tasks, ~5,500 LOC

---

## 📋 IMPLEMENTATION ROADMAP

### Phase A: Security & Critical (Week 1) — 10 P0 Tasks

| Day | Tasks | Total LOC |
|-----|-------|-----------|
| Day 1 | P12.0.4 Path traversal, P12.0.5 FFI bounds | ~300 |
| Day 2 | P12.0.2 FFI error type, P12.0.3 Async FFI | ~700 |
| Day 3 | P10.0.1 Per-processor metering | ~400 |
| Day 4 | P10.0.4 Undo for mixer | ~500 |
| Day 5 | P10.0.2 Graph-level PDC (start) | ~300 |

### Phase B: DAW P0 Completion (Week 2)

| Day | Tasks | Total LOC |
|-----|-------|-----------|
| Day 1 | P10.0.2 Graph-level PDC (finish) | ~300 |
| Day 2 | P10.0.3 Auto PDC detection | ~400 |
| Day 3 | P10.0.5 LUFS history graph | ~350 |
| Day 4 | P12.0.1 Real-time pitch shifting | ~400 |
| Day 5 | Testing & verification | ~0 |

### Phase C: High Priority P1 (Weeks 3-4)

Focus on highest-impact P1 tasks:
1. P10.1.3 Monitor section (~600 LOC)
2. P10.1.2 Stem routing matrix (~450 LOC)
3. P11.1.5 Subsystem provider tests (~800 LOC)
4. P12.1.7 Split SlotLabProvider (~600 LOC)
5. P12.1.4 Time-stretch FFI (~600 LOC)

### Phase D: Medium Priority P2 (Weeks 5-8)

Address highest-value P2 tasks by section.

---

## 📊 LOC SUMMARY

| Section | P0 LOC | P1 LOC | P2 LOC | Total |
|---------|--------|--------|--------|-------|
| **P10 DAW** | 2,250 | 6,050 | 5,400 | **13,700** |
| **P11 Middleware** | 0 | 2,000 | 3,650 | **5,650** |
| **P12 SlotLab** | 1,400 | 4,550 | 5,500 | **11,450** |
| **TOTAL** | **3,650** | **12,600** | **14,550** | **30,800** |

---

## ✅ COMPLETED MILESTONES (Archived)

<details>
<summary>Click to expand completed work</summary>

### P0-P9 Summary (All Complete)

| Phase | Tasks | Status |
|-------|-------|--------|
| P0 Critical | 15/15 | ✅ 100% |
| P1 High | 29/29 | ✅ 100% |
| P2 Medium | 19/19 | ✅ 100% |
| P3 Quick Wins | 5/5 | ✅ 100% |
| P4 SlotLab Spec | 64/64 | ✅ 100% |
| P5 Win Tier | 9/9 | ✅ 100% |
| P6 Preview V2 | 7/7 | ✅ 100% |
| P7 Anticipation V2 | 11/11 | ✅ 100% |
| P8 Audio Analysis | 12/12 | ✅ 100% |
| P9 Consolidation | 12/12 | ✅ 100% |

See individual spec files in `.claude/specs/` and `.claude/tasks/` for details.

</details>

---

## 📚 REFERENCES

| Document | Content |
|----------|---------|
| `specs/FEATURE_BUILDER_ULTIMATE_SPEC.md` | **P13 Feature Builder Panel** — ~3,100 LOC specification |
| `specs/FEATURE_BUILDER_GAPS_AND_ADDITIONS.md` | P13 Gap Analysis — additional blocks, validation rules |
| `analysis/DAW_ULTIMATE_ANALYSIS_2026_01_31.md` | DAW 9-role analysis (Score: 84%) |
| `reviews/MIDDLEWARE_ULTIMATE_ANALYSIS_2026_01_31.md` | Middleware 7-role analysis (Score: 92%) |
| `reviews/SLOTLAB_ULTIMATE_ANALYSIS_2026_01_31.md` | SlotLab 9-role analysis (Score: 87%) |
| `specs/WIN_TIER_SYSTEM_SPEC.md` | P5 Win Tier System v2.0 |
| `specs/PREMIUM_SLOT_PREVIEW_V2_SPEC.md` | P6 Extended features |
| `specs/ANTICIPATION_SYSTEM_V2_SPEC.md` | P7 Anticipation V2 |
| `analysis/ULTIMATE_AUDIO_PANEL_ANALYSIS_2026_01_31.md` | P8 415+ slot analysis |
| `tasks/P9_AUDIO_PANEL_CONSOLIDATION_2026_01_31.md` | P9 Consolidation |
| `domains/slot-audio-events-master.md` | V1.4 Stage catalog (603+ events) |

---

---

## 🟣 P13 — FEATURE BUILDER PANEL (Score: NEW)

**Specification:** `.claude/specs/FEATURE_BUILDER_ULTIMATE_SPEC.md` (~3,100 LOC)
**Gap Analysis:** `.claude/specs/FEATURE_BUILDER_GAPS_AND_ADDITIONS.md` (~595 LOC)
**Total Estimate:** 27 days, ~12,400 LOC (9 phases + 3 additional blocks)

### P13.0 — PHASE 1: FOUNDATION (3 days, ~1,500 LOC)

| ID | Task | Description | LOC Est. | File |
|----|------|-------------|----------|------|
| **P13.0.1** | FeatureBlock base model | Abstract class with id, name, category, dependencies, optionDefinitions | ~200 | `models/feature_builder/feature_block.dart` |
| **P13.0.2** | BlockCategory enum | core, feature, presentation, bonus categories | ~50 | `models/feature_builder/block_category.dart` |
| **P13.0.3** | BlockDependency model | enables, requires, modifies, conflicts relationships | ~150 | `models/feature_builder/block_dependency.dart` |
| **P13.0.4** | BlockOption model | Option types: toggle, dropdown, range, multi-select | ~200 | `models/feature_builder/block_options.dart` |
| **P13.0.5** | FeaturePreset model | JSON serializable preset with schemaVersion | ~150 | `models/feature_builder/feature_preset.dart` |
| **P13.0.6** | FeatureBlockRegistry | Block registration + retrieval by category | ~200 | `services/feature_builder/feature_block_registry.dart` |
| **P13.0.7** | GameCoreBlock | Pay model, spin type, volatility options | ~150 | `blocks/game_core_block.dart` |
| **P13.0.8** | GridBlock | Reels, rows, paylines/ways configuration | ~150 | `blocks/grid_block.dart` |
| **P13.0.9** | SymbolSetBlock | Low/mid/high counts, Wild, Scatter, Bonus | ~200 | `blocks/symbol_set_block.dart` |
| **P13.0.10** | Basic FeatureBuilderProvider | enableBlock(), disableBlock(), setBlockOption() | ~50 | `providers/feature_builder_provider.dart` |

**Phase 1 Total:** 10 tasks, ~1,500 LOC

### P13.1 — PHASE 2: FEATURE BLOCKS (4 days, ~2,000 LOC)

| ID | Task | Description | LOC Est. | File |
|----|------|-------------|----------|------|
| **P13.1.1** | FreeSpinsBlock | Trigger type, spin count, retrigger, multiplier | ~300 | `blocks/free_spins_block.dart` |
| **P13.1.2** | RespinBlock | Lock type, count, upgrade symbols | ~200 | `blocks/respin_block.dart` |
| **P13.1.3** | HoldAndWinBlock | 4 jackpot tiers, respin count, coin values | ~350 | `blocks/hold_and_win_block.dart` |
| **P13.1.4** | CascadesBlock | Max cascades, multiplier progression, tumble style | ~250 | `blocks/cascades_block.dart` |
| **P13.1.5** | CollectorBlock | Meter type, milestones, rewards | ~200 | `blocks/collector_block.dart` |
| **P13.1.6** | WinPresentationBlock | P5 integration, rollup settings, celebration levels | ~400 | `blocks/win_presentation_block.dart` |
| **P13.1.7** | MusicStatesBlock | ALE integration, context transitions, layer volumes | ~300 | `blocks/music_states_block.dart` |

**Phase 2 Total:** 7 tasks, ~2,000 LOC

### P13.2 — PHASE 3: DEPENDENCY SYSTEM (2 days, ~800 LOC)

| ID | Task | Description | LOC Est. | File |
|----|------|-------------|----------|------|
| **P13.2.1** | DependencyResolver | Graph-based dependency resolution | ~350 | `services/feature_builder/dependency_resolver.dart` |
| **P13.2.2** | Conflict detection | Detect and report block conflicts | ~150 | `services/feature_builder/dependency_resolver.dart` |
| **P13.2.3** | Auto-resolution | Suggest and apply dependency fixes | ~150 | `services/feature_builder/dependency_resolver.dart` |
| **P13.2.4** | Dependency graph data | Nodes and edges for visualization | ~100 | `models/feature_builder/block_dependency.dart` |
| **P13.2.5** | Warning generation | Modification warnings (e.g., "modifies Win Presentation") | ~50 | `services/feature_builder/dependency_resolver.dart` |

**Phase 3 Total:** 5 tasks, ~800 LOC

### P13.3 — PHASE 4: CONFIGURATION GENERATOR (3 days, ~1,500 LOC)

| ID | Task | Description | LOC Est. | File |
|----|------|-------------|----------|------|
| **P13.3.1** | GeneratedConfiguration model | Complete output structure | ~200 | `models/feature_builder/generated_config.dart` |
| **P13.3.2** | Mockup layout generator | Grid, symbols, reel strips based on config | ~250 | `services/feature_builder/configuration_generator.dart` |
| **P13.3.3** | State machine generator | Game flow states and transitions | ~250 | `services/feature_builder/configuration_generator.dart` |
| **P13.3.4** | Outcome controls generator | Dynamic forced outcome buttons | ~200 | `services/feature_builder/configuration_generator.dart` |
| **P13.3.5** | Stage definitions generator | All stages from enabled blocks | ~300 | `services/feature_builder/configuration_generator.dart` |
| **P13.3.6** | SlotLabProjectProvider integration | Apply generated config to project | ~300 | Various integration updates |

**Phase 4 Total:** 6 tasks, ~1,500 LOC

### P13.4 — PHASE 5: RUST FFI INTEGRATION (2 days, ~600 LOC)

| ID | Task | Description | LOC Est. | File |
|----|------|-------------|----------|------|
| **P13.4.1** | FeatureBuilderConfig Rust struct | Rust model for feature configuration | ~150 | `crates/rf-slot-lab/src/feature_builder_config.rs` |
| **P13.4.2** | slot_lab_apply_feature_config FFI | Apply config to Rust engine | ~100 | `crates/rf-bridge/src/feature_builder_ffi.rs` |
| **P13.4.3** | slot_lab_get_current_config FFI | Retrieve current config | ~50 | `crates/rf-bridge/src/feature_builder_ffi.rs` |
| **P13.4.4** | Dart FFI bindings | Native FFI extension methods | ~100 | `flutter_ui/lib/src/rust/native_ffi.dart` |
| **P13.4.5** | RustConfigBridge service | High-level Dart wrapper | ~150 | `services/feature_builder/rust_config_bridge.dart` |
| **P13.4.6** | JSON schema sync | Ensure Dart/Rust schema compatibility | ~50 | Schema validation |

**Phase 5 Total:** 6 tasks, ~600 LOC

### P13.5 — PHASE 6: UI PANEL (4 days, ~2,500 LOC)

| ID | Task | Description | LOC Est. | File |
|----|------|-------------|----------|------|
| **P13.5.1** | FeatureBuilderPanel main | Dockable panel (380px width) | ~400 | `widgets/feature_builder/feature_builder_panel.dart` |
| **P13.5.2** | Dock controls | Position toggle (left/right), resize, float | ~200 | `widgets/feature_builder/feature_builder_panel.dart` |
| **P13.5.3** | BlockListWidget | Checkboxes with categories, dependency badges | ~400 | `widgets/feature_builder/block_list_widget.dart` |
| **P13.5.4** | BlockSettingsSheet | Slide-out panel with block options | ~500 | `widgets/feature_builder/block_settings_sheet.dart` |
| **P13.5.5** | DependencyBadge | Visual indicators for requires/enables/conflicts | ~150 | `widgets/feature_builder/dependency_badge.dart` |
| **P13.5.6** | PresetDropdown | Built-in + user presets selector | ~300 | `widgets/feature_builder/preset_dropdown.dart` |
| **P13.5.7** | ApplyConfirmationDialog | Changes summary, audio preservation note | ~250 | `widgets/feature_builder/apply_confirmation_dialog.dart` |
| **P13.5.8** | Panel header | Title, preset selector, apply button | ~100 | `widgets/feature_builder/feature_builder_panel.dart` |
| **P13.5.9** | Panel footer | Validation summary, expand/collapse | ~100 | `widgets/feature_builder/feature_builder_panel.dart` |
| **P13.5.10** | Keyboard shortcuts | Ctrl+Shift+F toggle, 1-9 block quick-enable | ~100 | `widgets/feature_builder/feature_builder_panel.dart` |

**Phase 6 Total:** 10 tasks, ~2,500 LOC

### P13.6 — PHASE 7: VALIDATION SYSTEM (2 days, ~700 LOC)

| ID | Task | Description | LOC Est. | File |
|----|------|-------------|----------|------|
| **P13.6.1** | ValidationRule base | Abstract with severity (error/warning/info) | ~100 | `models/feature_builder/validation_rule.dart` |
| **P13.6.2** | Error rules (5) | Scatter required, Bonus symbol required, etc. | ~150 | `data/feature_builder/validation_rules.dart` |
| **P13.6.3** | Warning rules (5) | Cascades+FS, multiple jackpots, etc. | ~100 | `data/feature_builder/validation_rules.dart` |
| **P13.6.4** | Info rules (3) | New stages count, market notes | ~50 | `data/feature_builder/validation_rules.dart` |
| **P13.6.5** | ValidationService | Run all rules, collect results | ~150 | `services/feature_builder/validation_service.dart` |
| **P13.6.6** | ValidationPanel UI | Error/warning/info display with fix buttons | ~150 | `widgets/feature_builder/validation_panel.dart` |

**Phase 7 Total:** 6 tasks, ~700 LOC

### P13.7 — PHASE 8: PRESET SYSTEM (2 days, ~800 LOC)

| ID | Task | Description | LOC Est. | File |
|----|------|-------------|----------|------|
| **P13.7.1** | PresetService | CRUD operations for presets | ~250 | `services/feature_builder/preset_service.dart` |
| **P13.7.2** | Preset file I/O | Save/load JSON with versioning | ~100 | `services/feature_builder/preset_service.dart` |
| **P13.7.3** | Built-in presets (12) | Classic 3x3, 5x3, Ways 243, Megaways, H&W, etc. | ~300 | `data/feature_builder/built_in_presets.dart` |
| **P13.7.4** | Import/export | File picker integration | ~100 | `services/feature_builder/preset_service.dart` |
| **P13.7.5** | Preset gallery UI | Grid view with thumbnails | ~50 | `widgets/feature_builder/preset_gallery.dart` |

**Phase 8 Total:** 5 tasks, ~800 LOC

### P13.8 — PHASE 9: INTEGRATION & TESTING (2 days, ~500 LOC)

| ID | Task | Description | LOC Est. | File | Status |
|----|------|-------------|----------|------|--------|
| **P13.8.1** | SlotLabScreen integration | Feature Builder button in header + Apply & Build flow | ~150 | `screens/slot_lab_screen.dart` | ✅ DONE |
| **P13.8.2** | FeatureBuilderProvider registration | Provider registration in main.dart | ~20 | `main.dart` | ✅ DONE |
| **P13.8.3** | Apply & Build callback | onApplyAndBuild callback + FeatureBuilderResult | ~100 | `widgets/slot_lab/feature_builder_panel.dart` | ✅ DONE |
| **P13.8.4** | SlotLabProvider grid update | updateGridSize() method for engine sync | ~50 | `providers/slot_lab_provider.dart` | ✅ DONE |
| **P13.8.5** | Symbol generation | _generateDefaultSymbols() for new projects | ~80 | `screens/slot_lab_screen.dart` | ✅ DONE |
| **P13.8.6** | UltimateAudioPanel stage registration | Auto-register generated stages | ~100 | Integration updates | ⏳ |
| **P13.8.7** | ForcedOutcomePanel dynamic controls | Show/hide based on enabled blocks | ~100 | `widgets/slot_lab/forced_outcome_panel.dart` | ⏳ |
| **P13.8.8** | Unit tests (30+) | Block generation, validation, serialization | ~150 | `test/feature_builder/` | ⏳ |
| **P13.8.9** | Integration tests (10) | Full apply flow, preset load | ~50 | `test/feature_builder/` | ⏳ |

**Phase 9 Total:** 9 tasks, ~800 LOC (5 of 9 complete)

### P13.9 — ADDITIONAL BLOCKS (4 days, ~2,650 LOC)

| ID | Task | Description | LOC Est. | File | Status |
|----|------|-------------|----------|------|--------|
| **P13.9.1** | AnticipationBlock | Pattern (Tip A/B), trigger symbol, tension escalation | ~300 | `blocks/anticipation_block.dart` | ⏳ |
| **P13.9.2** | JackpotBlock (standalone) | Progressive/Fixed, 4-5 tiers, trigger modes, contribution rates | ~800 | `blocks/jackpot_block.dart` | ✅ DONE |
| **P13.9.3** | MultiplierBlock | Global/Win/Reel/Symbol multipliers, caps, progression | ~760 | `blocks/multiplier_block.dart` | ✅ DONE |
| **P13.9.4** | BonusGameBlock | Pick, Wheel, Trail, Ladder bonus types with multi-level | ~1130 | `blocks/bonus_game_block.dart` | ✅ DONE |
| **P13.9.5** | WildFeaturesBlock | Expanding, Sticky, Walking, Multiplier, Stacked | ~350 | `blocks/wild_features_block.dart` | ⏳ |
| **P13.9.6** | TransitionsBlock | Context/Music/Anticipation/WinTier/UI/Jackpot/Multiplier/Bonus/Gambling transitions | ~1580 | `blocks/transitions_block.dart` | ✅ DONE |
| **P13.9.7** | GamblingBlock | Card/Coin/Wheel/Ladder/Dice gamble types, streak limits, double-up | ~640 | `blocks/gambling_block.dart` | ✅ DONE |
| **P13.9.8** | Update dependency matrix | Add new blocks to dependency resolver | ~100 | `services/feature_builder/dependency_resolver.dart` | ⏳ |
| **P13.9.9** | Additional built-in presets (6) | Anticipation-focused, Jackpot-focused, Wild-heavy, Full Feature, Bonus-heavy, Multiplier-focused | ~100 | `data/feature_builder/built_in_presets.dart` | ⏳ |

**Phase 9 Additional Total:** 9 tasks, ~5,760 LOC (5 of 9 complete)

---

### P13 SUMMARY

| Phase | Days | Tasks | LOC | Description | Status |
|-------|------|-------|-----|-------------|--------|
| Phase 1: Foundation | 3 | 10 | 1,500 | Models, core blocks, registry | ✅ |
| Phase 2: Feature Blocks | 4 | 7 | 2,000 | 7 feature blocks | ✅ |
| Phase 3: Dependencies | 2 | 5 | 800 | Resolver, conflicts | ✅ |
| Phase 4: Generator | 3 | 6 | 1,500 | Config generation | ✅ |
| Phase 5: Rust FFI | 2 | 6 | 600 | Engine integration | ✅ |
| Phase 6: UI Panel | 4 | 10 | 2,500 | Dockable panel | ✅ |
| Phase 7: Validation | 2 | 6 | 700 | Rules, service, UI | ✅ |
| Phase 8: Presets | 2 | 5 | 800 | Service, built-ins | ✅ |
| Phase 9: Integration | 2 | 9 | 800 | Apply & Build, Testing | **5/9** |
| Phase 9+: Additional | 4 | 9 | 5,760 | 5 new blocks | **5/9** |
| **TOTAL** | **28** | **73** | **~17,460** | | **~75%** |

---

### P13 FILE STRUCTURE

```
flutter_ui/lib/
├── models/feature_builder/
│   ├── feature_block.dart              # ~200 LOC
│   ├── block_category.dart             # ~50 LOC
│   ├── block_dependency.dart           # ~300 LOC
│   ├── block_options.dart              # ~200 LOC
│   ├── feature_preset.dart             # ~150 LOC
│   ├── generated_config.dart           # ~200 LOC
│   └── validation_rule.dart            # ~100 LOC
│
├── services/feature_builder/
│   ├── feature_block_registry.dart     # ~200 LOC
│   ├── dependency_resolver.dart        # ~500 LOC
│   ├── configuration_generator.dart    # ~800 LOC
│   ├── preset_service.dart             # ~400 LOC
│   ├── validation_service.dart         # ~150 LOC
│   └── rust_config_bridge.dart         # ~150 LOC
│
├── widgets/feature_builder/
│   ├── feature_builder_panel.dart      # ~600 LOC
│   ├── block_list_widget.dart          # ~400 LOC
│   ├── block_settings_sheet.dart       # ~500 LOC
│   ├── dependency_badge.dart           # ~150 LOC
│   ├── preset_dropdown.dart            # ~300 LOC
│   ├── validation_panel.dart           # ~150 LOC
│   ├── apply_confirmation_dialog.dart  # ~250 LOC
│   └── preset_gallery.dart             # ~100 LOC
│
├── blocks/
│   ├── game_core_block.dart            # ~150 LOC
│   ├── grid_block.dart                 # ~150 LOC
│   ├── symbol_set_block.dart           # ~200 LOC
│   ├── free_spins_block.dart           # ~300 LOC
│   ├── respin_block.dart               # ~200 LOC
│   ├── hold_and_win_block.dart         # ~350 LOC
│   ├── cascades_block.dart             # ~250 LOC
│   ├── collector_block.dart            # ~200 LOC
│   ├── win_presentation_block.dart     # ~400 LOC
│   ├── music_states_block.dart         # ~300 LOC
│   ├── anticipation_block.dart         # ~300 LOC (⏳ pending)
│   ├── jackpot_block.dart              # ~800 LOC ✅
│   ├── multiplier_block.dart           # ~760 LOC ✅
│   ├── bonus_game_block.dart           # ~1130 LOC ✅
│   ├── gambling_block.dart             # ~640 LOC ✅
│   ├── wild_features_block.dart        # ~350 LOC (⏳ pending)
│   └── transitions_block.dart          # ~1580 LOC ✅
│
├── data/feature_builder/
│   ├── built_in_presets.dart           # ~350 LOC
│   └── validation_rules.dart           # ~300 LOC
│
└── providers/
    └── feature_builder_provider.dart   # ~400 LOC

crates/
├── rf-slot-lab/src/
│   └── feature_builder_config.rs       # ~300 LOC
│
└── rf-bridge/src/
    └── feature_builder_ffi.rs          # ~150 LOC

test/feature_builder/                   # ~200 LOC
```

---

### P13 KEYBOARD SHORTCUTS

| Shortcut | Action |
|----------|--------|
| `Ctrl+Shift+F` | Toggle Feature Builder panel |
| `Escape` | Close settings sheet / panel |
| `Tab` | Navigate between blocks |
| `Space` | Toggle selected block |
| `Enter` | Open block settings |
| `Ctrl+Enter` | Apply configuration |
| `Ctrl+R` | Reset to defaults |
| `Ctrl+S` | Save current as preset |
| `1-9, 0` | Quick-enable blocks (FS, Respin, H&W, Cascades, Collector, Anticipation, Gamble, Jackpot, Bonus, Multiplier) |

---

### P13 BLOCKS CATALOG (18 Total)

| # | Block | Category | Key Options | Generated Stages | Status |
|---|-------|----------|-------------|------------------|--------|
| 1 | Game Core | core | Pay model, spin type, volatility | SPIN_START, SPIN_END | ✅ |
| 2 | Grid | core | Reels, rows, paylines/ways | REEL_STOP_0..N | ✅ |
| 3 | Symbol Set | core | Symbol counts, Wild, Scatter, Bonus | SYMBOL_LAND_* | ✅ |
| 4 | Free Spins | feature | Trigger type, spin count, retrigger | FS_TRIGGER, FS_INTRO, FS_SPIN_*, FS_OUTRO | ✅ |
| 5 | Respin | feature | Lock type, count | RESPIN_TRIGGER, RESPIN_LOCK, RESPIN_WIN | ✅ |
| 6 | Hold & Win | feature | Jackpot tiers, respin count | HNW_TRIGGER, HNW_SPIN, HNW_JACKPOT_* | ✅ |
| 7 | Cascades | feature | Max cascades, multiplier | CASCADE_START, CASCADE_STEP_N, CASCADE_END | ✅ |
| 8 | Collector | feature | Meter type, milestones | COLLECT_SYMBOL, COLLECT_MILESTONE | ✅ |
| 9 | Win Presentation | presentation | P5 tiers, rollup style | WIN_PRESENT_*, ROLLUP_*, BIG_WIN_* | ✅ |
| 10 | Music States | presentation | ALE contexts, transitions | CONTEXT_*, layer switches | ✅ |
| 11 | Transitions | presentation | All context/music/win/UI/jackpot/multiplier/bonus/gamble | CONTEXT_*, MUSIC_*, UI_*, + 80+ new stages | ✅ |
| 12 | Anticipation | bonus | Pattern, tension levels | ANTICIPATION_ON, ANTICIPATION_TENSION_R*_L* | ⏳ |
| 13 | **Jackpot** | **bonus** | Progressive/Fixed, 5 tiers, trigger modes, contribution | JACKPOT_TRIGGER, JACKPOT_*_WIN, JACKPOT_CONTRIB, ~60 stages | ✅ |
| 14 | **Multiplier** | **feature** | Global/Win/Reel/Symbol multipliers, caps, progression | MULT_INCREASE, MULT_APPLY, MULT_RESET, ~40 stages | ✅ |
| 15 | **Bonus Game** | **bonus** | Pick/Wheel/Trail/Ladder/Match types, multi-level | BONUS_ENTER, BONUS_PICK_*, BONUS_WHEEL_*, ~80 stages | ✅ |
| 16 | **Gambling** | **feature** | Card/Coin/Wheel/Ladder/Dice/Higher-Lower, streak limits | GAMBLE_ENTER, GAMBLE_*_REVEAL, GAMBLE_STREAK_*, ~50 stages | ✅ |
| 17 | Wild Features | bonus | Expand, Sticky, Walking, Multiplier | WILD_LAND, WILD_EXPAND_*, WILD_WALK | ⏳ |
| 18 | (Reserved) | — | Future expansion | — | — |

---

### P13 BUILT-IN PRESETS (16)

| # | Preset Name | Category | Blocks | Description |
|---|-------------|----------|--------|-------------|
| 1 | Classic 3x3 Fruit | classic | Core + WinPres | Minimal 3-reel fruit |
| 2 | Classic 5x3 Lines | classic | Core + FS + WinPres | Traditional 5x3 with FS |
| 3 | Ways 243 | video | Core + FS + Cascades + WinPres | 243 ways with cascades |
| 4 | Ways 1024 | video | Core + FS + WinPres + Music | 1024 ways modern |
| 5 | Megaways | megaways | Core (dynamic) + FS + Cascades + WinPres | 117649 ways |
| 6 | Cluster Pays | cluster | Core (cluster) + Cascades + Collector + WinPres | Cluster mechanics |
| 7 | Hold & Win Basic | holdwin | Core + HNW + WinPres | Simple hold & win |
| 8 | Hold & Win + FS | holdwin | Core + FS + HNW + WinPres | Combined features |
| 9 | Cascades + Multiplier | video | Core + Cascades + WinPres + Music | Cascade focus |
| 10 | Collector + FS | video | Core + FS + Collector + WinPres | Meter-based FS trigger |
| 11 | Full Feature | video | ALL BLOCKS | Everything enabled |
| 12 | Audio Test Mode | test | Core + WinPres | High frequency events |
| 13 | Anticipation Focus | video | Core + FS + Anticipation + WinPres | Tension-heavy |
| 14 | Jackpot Focus | jackpot | Core + Jackpot + WinPres + Music | Progressive jackpots |
| 15 | Wild Heavy | video | Core + FS + WildFeatures + WinPres | Wild-centric mechanics |
| 16 | Transition Demo | test | Core + Transitions + WinPres | Animation testing |

---

### P13 DEPENDENCY MATRIX

| Block | Enables | Requires | Modifies | Conflicts |
|-------|---------|----------|----------|-----------|
| Game Core | All | — | — | — |
| Grid | — | Game Core | — | — |
| Symbol Set | — | Game Core | — | — |
| Free Spins | Respin (in FS) | Scatter symbol | Win Presentation | — |
| Respin | — | — | Spin flow | Hold & Win |
| Hold & Win | Collector, Jackpot | Coin symbol | Disables spin | Respin |
| Cascades | Multiplier | — | Win Presentation | — |
| Collector | — | Special symbol | — | — |
| Win Presentation | — | — | — | — |
| Music States | — | — | All audio | — |
| Anticipation | — | Scatter/Bonus | Reel timing | — |
| **Jackpot** | — | Game Core | Win Presentation, Music States | — |
| **Multiplier** | — | Game Core | Cascades, Free Spins, Symbol Set | — |
| **Bonus Game** | Jackpot | Game Core | Free Spins, Multiplier | — |
| **Gambling** | — | Game Core, Win Presentation | Win Presentation | — |
| Wild Features | — | Wild symbol | Win evaluation | — |
| **Transitions** | — | — | Music States, Win Pres, Jackpot, Multiplier, Bonus Game, Gambling | — |

---

### P13 VALIDATION RULES

**Error Rules (block Apply):**
| ID | Rule | Message |
|----|------|---------|
| E001 | Scatter required for FS scatter trigger | "Enable Scatter in Symbol Set" |
| E002 | Bonus symbol required for Bonus game | "Enable Bonus symbol in Symbol Set" |
| E003 | Coin symbol required for Hold & Win | "Enable special symbol (Coin) in Symbol Set" |
| E004 | Wild required for Wild Features | "Enable Wild in Symbol Set" |
| E005 | Grid too small for feature | "Increase grid size for Hold & Win (min 5x3)" |

**Warning Rules:**
| ID | Rule | Message |
|----|------|---------|
| W001 | Cascades + FS = long sequences | "Consider limiting cascades during FS" |
| W002 | Multiple jackpot sources | "Both H&W and standalone Jackpot enabled" |
| W003 | Too many features | "5+ features may confuse players" |

---

*Last updated: 2026-02-01 — P13.8 Apply & Build Integration Complete (5/9 tasks)*
