# Timeline Tab — KOMPLETNA ULTIMATIVNA LISTA POBOLJŠANJA

**Datum:** 2026-01-26
**Izvor:** Analiza po 16 uloga iz CLAUDE.md
**Status:** Sve stavke identifikovane, prioritizovane, procenjene

---

## 📊 STATISTIKA

| Prioritet | Broj | LOC | Status |
|-----------|------|-----|--------|
| P0 (Critical) | 18 | ~980 | ✅ **KOMPLETNO** |
| P1 (High) | 21 | ~1,450 | ✅ **KOMPLETNO** |
| P2 (Medium) | 6 | ~350 | ✅ **KOMPLETNO** |
| P3 (Low) | 8 | ~380 | ⏳ Čeka |
| **UKUPNO** | **53** | **~3,160** | **85% Done** |

### Progres

```
P0 ████████████████████ 100% (18/18)
P1 ████████████████████ 100% (21/21)
P2 ████████████████████ 100% (6/6)
P3 ░░░░░░░░░░░░░░░░░░░░   0% (0/8)
```

---

## ✅ P0 — KRITIČNO (18 stavki) — **KOMPLETNO**

**Status:** ✅ SVE ZAVRŠENO (2026-01-26)

### UI/UX

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P0.1 | Waveform preview u stage markers | Audio Designer | ~200 | `stage_trace_widget.dart` | ✅ Done |
| P0.2 | Timeline zoom/pan kontrole | UI/UX Expert | ~150 | `stage_trace_widget.dart` | ✅ Done |
| P0.3 | Keyboard shortcuts overlay (`?` button) | UI/UX Expert | ~100 | `slotlab_lower_zone_widget.dart` | ✅ Done |
| P0.4 | Veći touch targets (min 44px) | UX Designer | ~20 | `stage_trace_widget.dart` | ✅ Done |
| P0.5 | Keyboard focus indicators | UX Designer | ~40 | `stage_trace_widget.dart` | ✅ Done |
| P0.6 | Poboljšan tooltip (stage + audio + bus) | UI/UX Expert | ~60 | `stage_trace_widget.dart` | ✅ Done |

### Audio/DSP

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P0.7 | Latency metering u StageTraceWidget | Chief Audio Architect | ~80 | `stage_trace_widget.dart` | ✅ Done |
| P0.8 | Pre-trigger za anticipation stages | DSP Engineer | ~150 | `event_registry.dart` | ✅ Done |
| P0.9 | Timestamp precision (f64 umesto i64 ms) | Lead DSP Engineer | ~30 | `slot_lab_ffi.rs`, `slot_lab_provider.dart` | ✅ Done |

### Validation/QA

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P0.10 | Stage sequence validation | QA Engineer | ~80 | `slot_lab_provider.dart` | ✅ Done |
| P0.11 | Export stage trace za regression testing | QA Engineer | ~60 | `stage_trace_widget.dart` | ✅ Done |
| P0.12 | Sanitize stageType string | Security Expert | ~20 | `stage_trace_widget.dart` | ✅ Done |

### Missing Stages

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P0.13 | NEAR_MISS stage support | Slot Game Designer | ~40 | `spin.rs`, `stage.rs` | ✅ Done |
| P0.14 | NEAR_MISS_REEL_4 stage | Slot Game Designer | ~20 | `spin.rs` | ✅ Done |
| P0.15 | SYMBOL_UPGRADE stage | Slot Game Designer | ~20 | `stage.rs` | ✅ Done |
| P0.16 | MYSTERY_REVEAL stage | Slot Game Designer | ~20 | `stage.rs` | ✅ Done |
| P0.17 | MULTIPLIER_APPLY stage | Slot Game Designer | ~20 | `stage.rs` | ✅ Done |

### Performance

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P0.18 | Cache parsed stages (avoid re-parse) | Engine Architect | ~30 | `slot_lab_provider.dart` | ✅ Done |

---

## ✅ P1 — VISOK PRIORITET (21 stavka) — **KOMPLETNO**

### UI/UX

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P1.1 | Layer count badges na stage markers | Audio Designer | ~50 | `stage_trace_widget.dart` | ✅ Done (u P0.1) |
| P1.2 | Drag preview (ghost audio waveform) | UI/UX Expert | ~80 | `stage_trace_widget.dart` | ✅ Done |
| P1.3 | Stage grouping (spin phases, win phases) | UI/UX Expert | ~120 | `stage_trace_widget.dart` | ✅ Done |
| P1.4 | Quick A/B toggle za poređenje varijanti | Audio Designer | ~150 | `stage_trace_widget.dart` | ✅ Done |
| P1.5 | Context menu (right-click actions) | Tooling Developer | ~100 | `stage_trace_widget.dart` | ✅ Done |
| P1.6 | Multi-select stages za batch assign | Tooling Developer | ~120 | `stage_trace_widget.dart` | ✅ Done |
| P1.7 | Reduced motion accessibility option | UX Designer | ~40 | `stage_trace_widget.dart` | ✅ Done |

### Audio/DSP

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P1.8 | Inline waveform sa stage markerima | Chief Audio Architect | ~150 | `stage_trace_widget.dart` | ✅ Done |
| P1.9 | Bus assignment color coding per stage | Chief Audio Architect | ~40 | `stage_trace_widget.dart` | ✅ Done |
| P1.10 | Crossfade opcija za stage transitions | Lead DSP Engineer | ~100 | `event_registry.dart` | ✅ Done |
| P1.11 | Pre-trigger buffer za anticipation | Lead DSP Engineer | ~80 | `audio_playback_service.dart` | ✅ Done |
| P1.12 | Tail handling (fade out umesto hard stop) | DSP Engineer | ~60 | `audio_playback_service.dart` | ✅ Done |
| P1.13 | Crossfade on stage boundaries | DSP Engineer | ~80 | `event_registry.dart` | ✅ Done |

### Middleware

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P1.14 | Stage dependency UI | Middleware Architect | ~200 | `stage_dependency_editor.dart` (NEW) | ✅ Done |
| P1.15 | Conditional audio rules based on payload | Middleware Architect | ~150 | `event_registry.dart` | ✅ Done |

### Configuration

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P1.16 | Externalize stage colors to config | Tooling Developer | ~100 | `stage_config.dart` (NEW) | ✅ Done |
| P1.17 | Externalize stage icons to registry | Tooling Developer | ~80 | `stage_config.dart` (NEW) | ✅ Done |

### Testing

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P1.18 | Widget tests za StageTraceWidget | QA Engineer | ~500 | `stage_trace_widget_test.dart` (NEW) | ✅ Done |

### Documentation

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P1.19 | Dokumentovati public API za StageTraceWidget | Technical Director | ~50 | `stage_trace_widget.dart` | ✅ Done |
| P1.20 | Unit tests za controller state transitions | Technical Director | ~350 | `lower_zone_controller_test.dart` (NEW) | ✅ Done |

### Performance

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P1.21 | Use `const` constructors where possible | Engine Architect | ~20 | `stage_trace_widget.dart` | ✅ Done |

---

## ✅ P2 — SREDNJI PRIORITET (6 stavki) — **KOMPLETNO**

**Status:** ✅ SVE ZAVRŠENO (2026-01-26)

### Implementirano

| # | Task | Uloga | LOC | Fajl | Status |
|---|------|-------|-----|------|--------|
| P2.1 | Batch assign isti audio na multiple stages | Audio Designer | ~80 | `stage_trace_widget.dart` | ✅ Done |
| P2.2 | High contrast mode (WCAG 2.1 AA) | UX Designer | ~100 | `stage_trace_widget.dart` | ✅ Done |
| P2.3 | Stage template system (save/load patterns) | Tooling Developer | ~120 | `stage_trace_widget.dart` | ✅ Done |
| P2.4 | Parallel stage visualization (multiple lanes) | Middleware Architect | ~160 | `stage_trace_widget.dart` | ✅ Done |
| P2.5 | RepaintBoundary oko stage markers | Graphics Engineer | ~10 | `stage_trace_widget.dart` | ✅ Done |
| P2.6 | Cache painter rezultate (Path, Paint objects) | Graphics Engineer | ~60 | `stage_trace_widget.dart` | ✅ Done |

### Detalji Implementacije

**P2.1 Batch Assign:**
- `_batchAssignAudio()` metoda za multi-stage assignment
- Koristi `_selectedStages` set iz P1.6
- Kreira jedan AudioEvent per selected stage

**P2.2 High Contrast Mode:**
- `_highContrastEnabled` state flag
- `_getHighContrastColor()` metoda sa WCAG 2.1 AA compliant paletom
- Toggle button u header-u
- 8 high-contrast boja: #FFFF00, #00FF00, #FF00FF, #00FFFF, #FF8000, #FFFFFF, #80FF00, #FF0080

**P2.3 Stage Templates:**
- `StageTemplate` model sa id, name, description, stagePatterns
- `StageTemplates.all` lista built-in templates (7 templates)
- `_buildTemplateSelector()` PopupMenuButton
- `_applyTemplate()` metoda koja poziva callback
- Templates: Base Spin Flow, Win Celebration, Feature Trigger, Cascade Sequence, Jackpot Flow, Full Spin Cycle, Quick Spin

**P2.4 Parallel Lanes:**
- `_parallelLanesEnabled` toggle (default: true)
- `_stageLaneAssignments` Map<int, int> za lane mapping
- `_calculateStageLanes()` greedy algorithm
- `_getStageLaneOffset()` helper za Y poziciju
- `_overlapThresholdMs = 50ms` za detekciju overlap-a
- `_laneHeight = 16px` per lane

**P2.5 RepaintBoundary:**
- Wrapped stage marker Tooltip widget sa RepaintBoundary
- Izoluje repaint od ostalih elemenata

**P2.6 Cached Painters:**
- `_MiniWaveformPainter`: static cache za Path, waveform, size
- `_InlineWaveformStripPainter`: static Paint objects (_bgPaint, _centerLinePaint, _gridPaint)
- Cache key pattern za waveform points

### Odloženo za P4+ (13 stavki)

| # | Task | Razlog |
|---|------|--------|
| P2.7 | CustomMultiChildLayout | Complex refactor, low ROI |
| P2.8 | Binary protocol FFI | Breaking change, needs Rust changes |
| P2.9-10 | Security checks | Already covered by P0.12 |
| P2.11 | Extract marker widget | Code is maintainable as-is |
| P2.12 | Golden tests | Requires CI setup |
| P2.13 | Accessibility docs | Low priority |
| P2.14 | Pre-buffered audio | Already in P1.11 |
| P2.15 | Stage grouping | Already in P1.3 |
| P2.16-19 | Lower Zone extras | Nice-to-have, not critical |

---

## 🟢 P3 — NIZAK PRIORITET (8 stavki)

| # | Task | Uloga | LOC | Fajl |
|---|------|-------|-----|------|
| P3.1 | Pool stage objects za reduced allocation | Runtime Developer | ~60 | `slot_lab_provider.dart` |
| P3.2 | Custom stage color picker UI | Tooling Developer | ~100 | `stage_color_picker.dart` (NEW) |
| P3.3 | Stage analytics dashboard | Producer | ~150 | `stage_analytics_panel.dart` (NEW) |
| P3.4 | Compare two stage traces side-by-side | QA Engineer | ~80 | `stage_trace_comparator.dart` (NEW) |
| P3.5 | Auto-generate audio suggestions based on stage | Audio Designer | ~100 | `audio_suggestion_service.dart` (NEW) |
| P3.6 | ARIA labels za screen readers | UX Designer | ~40 | `stage_trace_widget.dart` |
| P3.7 | Stage occurrence statistics | Slot Game Designer | ~60 | `stage_trace_widget.dart` |
| P3.8 | Keyboard navigation between stages | UX Designer | ~50 | `stage_trace_widget.dart` |

---

## 📁 NOVI FAJLOVI (12)

| Fajl | Prioritet | LOC | Opis |
|------|-----------|-----|------|
| `stage_config.dart` | P1 | ~180 | Stage colors, icons config |
| `stage_dependency_editor.dart` | P1 | ~200 | Dependency graph UI |
| `stage_trace_widget_test.dart` | P1 | ~200 | Widget tests |
| `slotlab_lower_zone_controller_test.dart` | P1 | ~100 | Controller tests |
| `stage_marker_widget.dart` | P2 | ~100 | Extracted marker widget |
| `stage_trace_golden_test.dart` | P2 | ~80 | Golden tests |
| `stage_template_service.dart` | P2 | ~200 | Template save/load |
| `stage_trace_exporter.dart` | P2 | ~200 | Video export |
| `stage_color_picker.dart` | P3 | ~100 | Color picker UI |
| `stage_analytics_panel.dart` | P3 | ~150 | Analytics dashboard |
| `stage_trace_comparator.dart` | P3 | ~80 | Side-by-side compare |
| `audio_suggestion_service.dart` | P3 | ~100 | AI audio suggestions |

---

## 📋 MODIFIKOVANI FAJLOVI (11)

| Fajl | P0 | P1 | P2 | P3 | Ukupno LOC |
|------|----|----|----|----|------------|
| `stage_trace_widget.dart` | 8 | 9 | 5 | 3 | ~1,200 |
| `slot_lab_provider.dart` | 3 | 0 | 2 | 1 | ~170 |
| `event_registry.dart` | 1 | 3 | 0 | 0 | ~310 |
| `audio_playback_service.dart` | 0 | 2 | 1 | 0 | ~220 |
| `slotlab_lower_zone_widget.dart` | 1 | 0 | 0 | 0 | ~100 |
| `slotlab_lower_zone_controller.dart` | 0 | 0 | 1 | 0 | ~30 |
| `lower_zone_types.dart` | 0 | 0 | 1 | 0 | ~60 |
| `slot_lab_ffi.rs` | 1 | 0 | 1 | 0 | ~130 |
| `spin.rs` | 2 | 0 | 0 | 0 | ~60 |
| `stages.rs` | 3 | 0 | 0 | 0 | ~60 |

---

## ⏱️ VREMENSKI PLAN

### Sprint 1: Critical Fixes (3-4 dana)
```
P0.1  Waveform preview                    ~200 LOC
P0.2  Timeline zoom/pan                   ~150 LOC
P0.3  Keyboard shortcuts overlay          ~100 LOC
P0.4  Veći touch targets                   ~20 LOC
P0.5  Keyboard focus indicators            ~40 LOC
P0.6  Poboljšan tooltip                    ~60 LOC
                                    ─────────────
                                         ~570 LOC
```

### Sprint 2: Audio/DSP Fixes (2-3 dana)
```
P0.7  Latency metering                     ~80 LOC
P0.8  Pre-trigger anticipation            ~150 LOC
P0.9  Timestamp precision                  ~30 LOC
P0.18 Cache parsed stages                  ~30 LOC
                                    ─────────────
                                         ~290 LOC
```

### Sprint 3: Validation & Stages (2 dana)
```
P0.10 Stage sequence validation            ~80 LOC
P0.11 Export stage trace                   ~60 LOC
P0.12 Sanitize stageType                   ~20 LOC
P0.13-17 Missing stages                   ~120 LOC
                                    ─────────────
                                         ~280 LOC
```

### Sprint 4: High Priority Features (4-5 dana)
```
P1.1  Layer count badges                   ~50 LOC
P1.4  A/B toggle                          ~150 LOC
P1.5  Context menu                        ~100 LOC
P1.6  Multi-select                        ~120 LOC
P1.14 Stage dependency UI                 ~200 LOC
P1.16-17 Externalize config               ~180 LOC
                                    ─────────────
                                         ~800 LOC
```

### Sprint 5: Testing & Polish (3-4 dana)
```
P1.18 Widget tests                        ~200 LOC
P1.20 Controller tests                    ~100 LOC
P2.5-7 Performance optimizations          ~230 LOC
P2.12 Golden tests                         ~80 LOC
                                    ─────────────
                                         ~610 LOC
```

---

## 🎯 DEFINICIJA DONE

Za svaku stavku, "done" znači:
1. ✅ Kod implementiran
2. ✅ `flutter analyze` — 0 errors
3. ✅ Test pokrivenost (gde je primenjivo)
4. ✅ Dokumentacija ažurirana
5. ✅ Code review (self-review minimum)

---

## 📊 METRIČKI CILJEVI

| Metrika | Trenutno | Cilj |
|---------|----------|------|
| Test coverage (StageTraceWidget) | ~20% | 80% |
| Touch target size | 24px | 44px |
| Latency feedback | None | < 10ms display |
| Keyboard shortcuts documented | 0% | 100% |
| Accessibility score | ~40% | 80% |
| Stage types supported | 20 | 25+ |

---

---

## 📝 CHANGELOG

| Verzija | Datum | Opis |
|---------|-------|------|
| 2.0 | 2026-01-26 | P2 KOMPLETNO (6/6): batch assign, high contrast, templates, parallel lanes, repaint boundary, painter caching (~530 LOC) |
| 1.6 | 2026-01-26 | P1 KOMPLETNO (21/21): +P1.18-20 tests & docs (~900 LOC) |
| 1.5 | 2026-01-26 | P1 86% (18/21): +P1.16-17 stage_config.dart (~600 LOC) |
| 1.4 | 2026-01-26 | P1 76% (16/21): +P1.14 stage dependency, +P1.15 conditional rules |
| 1.3 | 2026-01-26 | P1 67% (14/21): +P1.8 waveform, +P1.10-13 crossfade/tail |
| 1.2 | 2026-01-26 | P1 u toku (10/21): P1.1-P1.9, P1.21 |
| 1.1 | 2026-01-26 | P0 kompletno (18/18 stavki) |
| 1.0 | 2026-01-26 | Inicijalna lista |

---

**Dokument kreiran:** 2026-01-26
**Verzija:** 2.0
**Ukupno stavki:** 53 (45 done, 8 P3 pending)
**Ukupno LOC:** ~3,160
**P0 Status:** ✅ KOMPLETNO (18/18)
**P1 Status:** ✅ KOMPLETNO (21/21)
**P2 Status:** ✅ KOMPLETNO (6/6)
