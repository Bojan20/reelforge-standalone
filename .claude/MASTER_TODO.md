# FluxForge Studio — MASTER TODO

**Updated:** 2026-01-31
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

*Last updated: 2026-01-31 — Ultimate Analysis Complete*
