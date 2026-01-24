# Middleware Deep Analysis Plan

**Datum:** 2026-01-24
**Status:** IN PROGRESS
**Lead:** Claude (Principal Engineer)

---

## Prioritized Analysis Queue

| # | Komponenta | LOC | Kritičnost | Status |
|---|------------|-----|------------|--------|
| 1 | **EventRegistry** | ~1645 | ⭐⭐⭐⭐⭐ | ✅ COMPLETE (P1 done) |
| 2 | **CompositeEventSystemProvider** | ~1448 | ⭐⭐⭐⭐⭐ | ✅ COMPLETE (P1 done) |
| 3 | Container Panels (Blend/Random/Sequence) | ~3653 | ⭐⭐⭐⭐ | ✅ COMPLETE (P1 done) |
| 4 | ALE Provider | ~837 | ⭐⭐⭐⭐ | ✅ COMPLETE (P1 done) |
| 5 | Lower Zone Controller | ~498 | ⭐⭐⭐ | ✅ COMPLETE (NO P1) |
| 6 | Stage Ingest Provider | ~1270 | ⭐⭐⭐ | ✅ COMPLETE (NO P1) |

---

## Analysis #1: EventRegistry

### Fajl
`flutter_ui/lib/services/event_registry.dart`

### Zašto prvi?
- **Centralni hub** za sav SlotLab/Middleware audio
- Povezuje: SlotLabProvider ↔ MiddlewareProvider ↔ AudioPlaybackService
- Stage fallback, pooling, bus routing, priority — sva kritična logika
- Potencijalni performance bottleneck

### Analiza po CLAUDE.md ulogama — ✅ COMPLETED 2026-01-24

#### 1. Chief Audio Architect — 4/5 ✅
- [x] Stage→Event mapping kvalitet — **SOLID**
- [x] Bus routing strategija — **Via StageConfigurationService**
- [x] Priority sistem — **0-100 scale OK**
- [x] Spatial intent mapping — **AutoSpatialEngine integrated**

#### 2. Lead DSP Engineer — 4/5 ✅
- [x] Audio latency path — **Minimal, pooling helps**
- [x] Voice pooling efikasnost — **AudioPool integrated**
- [x] Real-time constraints — **No alloc in hot path**

#### 3. Engine Architect — 4/5 ✅
- [x] Memory patterns — ⚠️ **_playingInstances unbounded**
- [x] Lock-free komunikacija — **OK (Rust engine)**
- [x] FFI integration points — **AudioPlaybackService OK**

#### 4. Technical Director — 4/5 ✅
- [x] Arhitektura odluke — **Good separation**
- [x] Single source of truth — **Events in _events map**
- [x] Dependency graph — **Clear dependencies**

#### 5. UI/UX Expert — 3/5 ✅
- [x] Error feedback — ⚠️ **Only last trigger stored**
- [x] Debug visibility — **statsString() OK**
- [x] Designer workflow — **registerEvent() simple**

#### 6. Graphics Engineer — N/A ✅
- [x] N/A (no rendering)

#### 7. Security Expert — 4/5 ✅
- [x] Input validation — ⚠️ **Stage validated, audioPath NOT**
- [x] Path sanitization — ⚠️ **MISSING path traversal check**

### Deliverables — ✅ COMPLETED

1. **Weakness Report** — [EVENT_REGISTRY_ANALYSIS_2026_01_24.md](EVENT_REGISTRY_ANALYSIS_2026_01_24.md)
2. **P1 Tasks** — 4 issues identified (see below)
3. **Architecture Diagram** — In analysis doc
4. **Implementation** — 🔄 IN PROGRESS

---

## EventRegistry P1 Implementation Tasks — ✅ ALL DONE

| ID | Task | Status | LOC | Priority |
|----|------|--------|-----|----------|
| P1.1 | Path validation (Security) | ✅ DONE | ~35 | CRITICAL |
| P1.2 | Voice limit per event | ✅ DONE | ~20 | HIGH |
| P1.3 | Instance cleanup timer | ✅ DONE | ~40 | HIGH |
| P1.4 | Trigger history for UI | ✅ DONE | ~55 | MEDIUM |

**Total:** ~150 LOC added
**Verified:** `flutter analyze` — No errors

### P1.1 — Path Validation (Security)
**Problem:** `audioPath` u `AudioLayer` nije validiran za path traversal (`../../../etc/passwd`)
**Fix:** Dodati `_validateAudioPath()` helper i pozvati u `_playLayer()`

### P1.2 — Voice Limit Per Event
**Problem:** Event može spawn-ovati neograničen broj voice-ova istovremeno
**Fix:** Dodati `_maxVoicesPerEvent` konstanta, brojač u `_PlayingInstance`

### P1.3 — Instance Cleanup Timer
**Problem:** `_playingInstances` lista raste bez cleanup-a završenih voice-ova
**Fix:** Periodic Timer koji čisti stare instance (>30s)

### P1.4 — Trigger History
**Problem:** Samo poslednji trigger je čuvan, UI nema historiju
**Fix:** `_triggerHistory` ring buffer (max 100 entries)

---

## Analysis #2: CompositeEventSystemProvider — ✅ COMPLETE

### Fajl
`flutter_ui/lib/providers/subsystems/composite_event_system_provider.dart`

### Zašto?
- Najkompleksniji provider (~1448 LOC)
- Undo/redo, layer ops, stage triggers
- Direktna integracija sa EventRegistry

### Analiza po CLAUDE.md ulogama — ✅ COMPLETED 2026-01-24

#### 1. Chief Audio Architect — 4/5 ✅
- [x] Multi-layer event model — **Solid**
- [x] Mute/Solo per layer — **Standard DAW workflow**
- [x] Volume/Pan per layer — **Continuous + Final variants**
- [x] Fade in/out support — **Per-layer**
- [x] Bus routing by category — **Category → Bus mapping**

#### 2. Lead DSP Engineer — 3/5 ✅
- [x] Auto duration detection — **FFI call**
- [x] Volume clamping — **0.0-1.0 (FIXED from 2.0)**
- [x] Pan clamping — **-1.0 to 1.0**
- [ ] Sample-accurate sync — ⚠️ **Delay in seconds, not samples**

#### 3. Engine Architect — 4/5 ✅
- [x] Bounded history — **_maxUndoHistory=50, _maxHistoryEntries=100**
- [x] Bounded events — **_maxCompositeEvents=500 with LRU eviction**
- [x] Voice cleanup on delete — **Stops playing voices**
- [ ] Undo copies all events — ⚠️ **O(n) memory per push**

#### 4. Technical Director — 5/5 ✅
- [x] Clear separation — **Constructor injection**
- [x] Single source of truth — **_compositeEvents Map**
- [x] Bidirectional sync — **Composite ↔ Middleware**
- [x] ID mapping convention — **mw_event_* prefix**
- [x] Export/Import — **JSON serialization with versioning**

#### 5. UI/UX Expert — 5/5 ✅
- [x] Multi-select support — **Cmd/Ctrl+click, Shift+range**
- [x] Clipboard operations — **Copy, Paste, Duplicate**
- [x] Batch operations — **Delete, Mute, Solo, Volume, Move**
- [x] Event history tracking — **Ring buffer with timestamps**
- [x] Continuous vs Final updates — **No undo during drag**

#### 6. Graphics Engineer — N/A ✅
- [x] No direct rendering

#### 7. Security Expert — 4/5 ✅ (after P1 fixes)
- [x] Event limit enforced — **LRU eviction**
- [x] History limits — **Bounded undo and event history**
- [x] audioPath validation — **FIXED: Added _validateAudioPath()**
- [x] JSON import validation — **FIXED: Schema + structure validation**

### Deliverables — ✅ COMPLETED

1. **Weakness Report** — [COMPOSITE_EVENT_SYSTEM_ANALYSIS_2026_01_24.md](COMPOSITE_EVENT_SYSTEM_ANALYSIS_2026_01_24.md)
2. **P1 Tasks** — 3 issues identified and FIXED
3. **Architecture Diagram** — In analysis doc
4. **Implementation** — ✅ DONE

---

## CompositeEventSystemProvider P1 Implementation Tasks — ✅ ALL DONE

| ID | Task | Status | LOC | Priority |
|----|------|--------|-----|----------|
| P1.1 | audioPath validation | ✅ DONE | ~45 | CRITICAL |
| P1.2 | Volume clamp fix (2.0 → 1.0) | ✅ DONE | ~2 | HIGH |
| P1.3 | JSON import validation | ✅ DONE | ~80 | HIGH |

**Total:** ~127 LOC added
**Verified:** `flutter analyze` — No errors

### P1.1 — audioPath Validation (Security)
**Problem:** `audioPath` u `addLayerToEvent()` nije validiran za path traversal
**Fix:** Dodati `_validateAudioPath()` helper, blokira `..`, null bytes, invalid extensions

### P1.2 — Volume Range Fix
**Problem:** `adjustSelectedLayersVolume()` dozvoljavala volume > 1.0 (clamp 2.0)
**Fix:** Promenjen clamp na 1.0 (sprečava audio clipping/distortion)

### P1.3 — JSON Import Validation
**Problem:** `importCompositeEventsFromJson()` verovao JSON strukturi bez validacije
**Fix:** Dodati `_validateEventJson()` i `_validateEventLayers()` za schema validaciju

---

## Analysis #3: Container Panels — ✅ COMPLETE

### Fajlovi
- `blend_container_panel.dart` (~1145 LOC)
- `random_container_panel.dart` (~1212 LOC)
- `sequence_container_panel.dart` (~1296 LOC)

**Total:** ~3653 LOC

### Zašto?
- UI za core audio containers
- RTPC/FFI integracija
- Drag-drop, visualization

### Analiza po CLAUDE.md ulogama — ✅ COMPLETED 2026-01-24

#### 1. Chief Audio Architect — 4/5 ✅
- [x] RTPC crossfade — **Industry-standard Wwise-like**
- [x] Equal power curve — **Preserves loudness**
- [x] Pitch/volume variation — **Musical ranges**
- [ ] No crossfade overlap — ⚠️ **P2: Abrupt step transitions**

#### 2. Lead DSP Engineer — 3/5 ✅
- [x] Curve math — **EqualPower, SCurve correct**
- [x] Volume in dB — **Proper logarithmic scale**
- [x] SinCos curve — **FIXED: Was using Taylor approximation**
- [ ] Sample-accurate timing — ⚠️ **Delays in ms, not samples**

#### 3. Engine Architect — 4/5 ✅
- [x] Selector pattern — **Efficient rebuilds**
- [x] Controller disposal — **Proper cleanup**
- [ ] Timer hot reload — ⚠️ **Multiple timers possible**

#### 4. Technical Director — 5/5 ✅
- [x] Consistent UI pattern — **All three panels same structure**
- [x] Provider integration — **Clean Selector usage**
- [x] Reusable visualization — **CustomPainter for all charts**

#### 5. UI/UX Expert — 4/5 ✅
- [x] Visual curve preview — **Real-time**
- [x] Pie chart weights — **Intuitive**
- [x] Timeline ruler — **Clear timing**
- [ ] No undo for child changes — ⚠️ **Data loss risk**

#### 6. Graphics Engineer — 4/5 ✅
- [x] Efficient painters — **Good CustomPainter usage**

#### 7. Security Expert — 4/5 ✅
- [x] Audio paths from picker — **No raw user input**
- [ ] No name validation — ⚠️ **XSS risk in web export**

### Deliverables — ✅ COMPLETED
1. **Weakness Report** — [CONTAINER_PANELS_ANALYSIS_2026_01_24.md](CONTAINER_PANELS_ANALYSIS_2026_01_24.md)
2. **P1 Tasks** — 1 issue identified and FIXED
3. **Implementation** — ✅ DONE

---

## Container Panels P1 Implementation Tasks — ✅ ALL DONE

| ID | Task | Status | LOC | Priority |
|----|------|--------|-----|----------|
| P1.1 | SinCos curve fix (dart:math) | ✅ DONE | ~8 | CRITICAL |

**Total:** ~8 LOC changed
**Verified:** `flutter analyze` — No errors

### P1.1 — SinCos Curve Fix (DSP)
**Problem:** Taylor series approximation `1 - x²/2 + x⁴/24` was inaccurate for crossfade curves
**Fix:** Replaced with `dart:math` — `math.cos(t * math.pi)` for accurate trigonometric function

---

## Analysis #4: ALE Provider — ✅ COMPLETE

### Fajl
`flutter_ui/lib/providers/ale_provider.dart` (~837 LOC)

### Zašto?
- Adaptive Layer Engine state management
- Signal/Context/Rule system
- FFI integracija sa rf-ale crate

### Analiza po CLAUDE.md ulogama — ✅ COMPLETED 2026-01-24

#### 1. Chief Audio Architect — 5/5 ✅
- [x] Signal system — **4 normalization modes**
- [x] Context system — **Layer-based with level tracking**
- [x] Rule system — **16 comparison ops, 6 action types**
- [x] Transition profiles — **6 sync modes (beat, bar, phrase)**
- [x] Stability config — **7 mechanisms**

#### 2. Lead DSP Engineer — 4/5 ✅
- [x] Tick loop — **Configurable interval**
- [x] Signal caching — **Local cache avoids FFI**
- [ ] Level clamping — ⚠️ **setLevel() accepts any int**
- [x] notifyListeners — **FIXED: Only on state change**

#### 3. Engine Architect — 4/5 ✅
- [x] Timer disposal — **Proper cleanup**
- [x] FFI error handling — **Graceful failure**
- [x] State diff check — **FIXED: Skip JSON parse if unchanged**

#### 4. Technical Director — 5/5 ✅
- [x] Complete models — **Full toJson/fromJson**
- [x] Clean API — **Simple methods**
- [x] FFI abstraction — **Provider shields UI**

#### 5. UI/UX Expert — 5/5 ✅
- [x] Convenience getters — **activeContext, layerCount, etc.**
- [x] Signal caching — **Fast reads**
- [x] Transition state — **inTransition flag**

#### 6. Graphics Engineer — N/A ✅

#### 7. Security Expert — 4/5 ✅ (after P1.2 fix)
- [x] AssetId validation — **FIXED: Path traversal blocked**
- [ ] Profile JSON validation — ⚠️ **trusts structure**

### Deliverables — ✅ COMPLETED
1. **Weakness Report** — [ALE_PROVIDER_ANALYSIS_2026_01_24.md](ALE_PROVIDER_ANALYSIS_2026_01_24.md)
2. **P1 Tasks** — 2 issues identified and FIXED
3. **Implementation** — ✅ DONE

---

## ALE Provider P1 Implementation Tasks — ✅ ALL DONE

| ID | Task | Status | LOC | Priority |
|----|------|--------|-----|----------|
| P1.1 | State diff check (performance) | ✅ DONE | ~20 | CRITICAL |
| P1.2 | AssetId path validation (security) | ✅ DONE | ~30 | CRITICAL |

**Total:** ~50 LOC added
**Verified:** `flutter analyze` — No errors

### P1.1 — State Diff Check (Performance)
**Problem:** JSON parsing + notifyListeners() called 60x/sec even when state unchanged
**Fix:** Cache `_lastStateJson`, only parse and notify when different

### P1.2 — AssetId Path Validation (Security)
**Problem:** `AleLayer.assetId` was not validated, could contain path traversal
**Fix:** Added `_validateAssetPath()` in `AleLayer.fromJson()`, blocks `..`, null bytes, invalid extensions

---

## Analysis #5: Lower Zone Controller — ✅ COMPLETE

### Fajl
`flutter_ui/lib/controllers/slot_lab/lower_zone_controller.dart` (~498 LOC)

### Zašto?
- Lower Zone tab/height management
- Keyboard shortcuts
- Category system

### Analiza po CLAUDE.md ulogama — ✅ COMPLETED 2026-01-24

#### 1. Chief Audio Architect — 4/5 ✅
- [x] DSP panel tabs — **Compressor, Limiter, Gate, Reverb**
- [x] Audio category — **Clean grouping**

#### 2. Lead DSP Engineer — 4/5 ✅
- [x] DSP panel shortcuts — **Keys 5-8**

#### 3. Engine Architect — 5/5 ✅
- [x] Height clamping — **Always valid range**
- [x] Clean state machine — **switchTo() handles all cases**
- [x] No memory leaks — **Pure state**

#### 4. Technical Director — 5/5 ✅
- [x] Enum-based design — **LowerZoneTab, LowerZoneCategory**
- [x] Config pattern — **Centralized configs**
- [x] Serialization — **toJson/fromJson**

#### 5. UI/UX Expert — 5/5 ✅
- [x] Auto-expand on tab switch
- [x] Toggle on same-tab click
- [x] Keyboard shortcuts (1-8, `)
- [x] Category collapse

#### 6. Graphics Engineer — N/A ✅

#### 7. Security Expert — 5/5 ✅
- [x] Index bounds check — **Validates tabIndex**
- [x] Height clamping — **Prevents OOB**

### Deliverables — ✅ COMPLETED
1. **Weakness Report** — [LOWER_ZONE_CONTROLLER_ANALYSIS_2026_01_24.md](LOWER_ZONE_CONTROLLER_ANALYSIS_2026_01_24.md)
2. **P1 Tasks** — NONE (clean code)

---

## Analysis #6: Stage Ingest Provider — ✅ COMPLETE

### Fajl
`flutter_ui/lib/providers/stage_ingest_provider.dart` (~1270 LOC)

### Zašto?
- Universal Stage Ingest System
- Three-layer architecture (Direct, Diff, Rule)
- Live/Offline modes
- Mock engine integration

### Analiza po CLAUDE.md ulogama — ✅ COMPLETED 2026-01-24

#### 1. Chief Audio Architect — 5/5 ✅
- [x] Semantic stages — **Clean abstraction**
- [x] Timing profiles — **5 modes**
- [x] Stage helpers — **spinStart, reelStop, etc.**

#### 2. Lead DSP Engineer — N/A ✅
- Not DSP-focused

#### 3. Engine Architect — 5/5 ✅
- [x] Resource disposal — **Comprehensive**
- [x] Map-based tracking — **7 resource Maps**
- [x] StreamController — **Broadcast for events**
- [x] Timer cleanup — **Proper cancel**

#### 4. Technical Director — 5/5 ✅
- [x] Enum-based types — **4 enums**
- [x] Factory constructors — **All models**
- [x] Comprehensive API — **60+ methods**

#### 5. UI/UX Expert — 5/5 ✅
- [x] Rich getters — **adapters, traces, configs, etc.**
- [x] Staging mode — **Mock engine**
- [x] Event stream — **liveEvents**

#### 6. Graphics Engineer — N/A ✅

#### 7. Security Expert — 4/5 ✅
- [x] Safe JSON parsing — **Uses .as? with fallbacks**
- [x] Handle validation — **Returns null on failure**
- [ ] WebSocket URL validation — ⚠️ **P2: Not validated**

### Deliverables — ✅ COMPLETED
1. **Weakness Report** — [STAGE_INGEST_PROVIDER_ANALYSIS_2026_01_24.md](STAGE_INGEST_PROVIDER_ANALYSIS_2026_01_24.md)
2. **P1 Tasks** — NONE (clean code)

---

## Progress Tracking

| Datum | Komponenta | Status | Findings |
|-------|------------|--------|----------|
| 2026-01-24 | EventRegistry | ✅ ANALYZED | 8 issues (4 P1, 4 P2) |
| 2026-01-24 | EventRegistry P1.1-P1.4 | ✅ DONE | All 4 P1 fixes implemented (~150 LOC) |
| 2026-01-24 | CompositeEventSystemProvider | ✅ ANALYZED | 9 issues (3 P1, 6 P2) |
| 2026-01-24 | CompositeEventSystemProvider P1.1-P1.3 | ✅ DONE | All 3 P1 fixes implemented (~127 LOC) |
| 2026-01-24 | Container Panels | ✅ ANALYZED | 8 issues (1 P1, 7 P2) |
| 2026-01-24 | Container Panels P1.1 | ✅ DONE | 1 P1 fix implemented (~8 LOC) |
| 2026-01-24 | ALE Provider | ✅ ANALYZED | 5 issues (2 P1, 3 P2) |
| 2026-01-24 | ALE Provider P1.1-P1.2 | ✅ DONE | 2 P1 fixes implemented (~50 LOC) |
| 2026-01-24 | Lower Zone Controller | ✅ ANALYZED | 3 P3 issues (NO P1, NO P2) |
| 2026-01-24 | Stage Ingest Provider | ✅ ANALYZED | 4 issues (NO P1, 2 P2, 2 P3) |

---

## 🎉 FINAL SUMMARY — ALL ANALYSES COMPLETE

| # | Komponenta | LOC | P1 Fixed | P1 LOC | Status |
|---|------------|-----|----------|--------|--------|
| 1 | EventRegistry | ~1645 | 4 | ~150 | ✅ DONE |
| 2 | CompositeEventSystemProvider | ~1448 | 3 | ~127 | ✅ DONE |
| 3 | Container Panels | ~3653 | 1 | ~8 | ✅ DONE |
| 4 | ALE Provider | ~837 | 2 | ~50 | ✅ DONE |
| 5 | Lower Zone Controller | ~498 | 0 | 0 | ✅ CLEAN |
| 6 | Stage Ingest Provider | ~1270 | 0 | 0 | ✅ CLEAN |
| **TOTAL** | **~9351 LOC** | **10** | **~335** | **✅ ALL DONE** |

### Key Achievements

1. **10 P1 fixes implemented** — Security, performance, correctness
2. **~335 LOC added** — All defensive, validated, bounded
3. **6 comprehensive analysis docs** — From all 7 CLAUDE.md roles
4. **Last 2 components clean** — No P1 issues (excellent code quality)

### P1 Fixes Summary

| Component | Fix | Type |
|-----------|-----|------|
| EventRegistry | Path validation | Security |
| EventRegistry | Voice limit per event | Performance |
| EventRegistry | Instance cleanup timer | Memory |
| EventRegistry | Trigger history | UX |
| CompositeEventSystemProvider | audioPath validation | Security |
| CompositeEventSystemProvider | Volume clamp 2.0→1.0 | Audio |
| CompositeEventSystemProvider | JSON import validation | Security |
| Container Panels | SinCos curve fix | DSP |
| ALE Provider | State diff check | Performance |
| ALE Provider | AssetId path validation | Security |

---

## P2 Issues (Lower Priority)

### EventRegistry P2

| ID | Issue | Impact | Status |
|----|-------|--------|--------|
| P2.1 | Crossfade for loop stop | Audio clicks on stop | ✅ **ALREADY DONE** (Rust: `start_fade_out(240)` applied to all voices) |
| P2.2 | Pan smoothing | Audible zipper noise | ✅ **N/A** (pan set at creation, doesn't change during playback) |
| P2.3 | Global singleton removal | Testing difficulty | ⏸️ Deferred (low impact) |
| P2.4 | Validation feedback | Silent failures | ⏸️ Deferred (low impact) |

### CompositeEventSystemProvider P2

| ID | Issue | Impact | Status |
|----|-------|--------|--------|
| P2.1 | No layer crossfade | Abrupt transitions when adjusting | ⏸️ Deferred |
| P2.2 | No random pitch/volume variation | Repetitive audio | ⏸️ Deferred |
| P2.3 | Undo snapshot copies all events | O(n) memory per undo push | ⏸️ Deferred |
| P2.4 | No schema migration for imports | Future version incompatibility | ⏸️ Deferred |
| P2.5 | Name/category sanitization | XSS risk if displayed in web export | ✅ **DONE** (+45 LOC) |
| P2.6 | Condition parsing injection risk | Potential DoS via complex regex | ⏸️ Deferred |

### Container Panels P2

| ID | Issue | Panel | Impact | Status |
|----|-------|-------|--------|--------|
| P2.1 | No crossfade overlap between steps | Sequence | Abrupt transitions | ⏸️ Deferred |
| P2.2 | No RTPC parameter smoothing | Blend | Audible jumps | ⏸️ Deferred |
| P2.3 | Timer not cancelled on hot reload | Sequence | Multiple timers | ⏸️ Deferred |
| P2.4 | No undo for child changes | All | Data loss risk | ⏸️ Deferred |
| P2.5 | No copy/paste for children | All | Poor UX | ⏸️ Deferred |
| P2.6 | No name validation/sanitization | All | XSS risk | ⏸️ Deferred |
| P2.7 | No child count limit | All | Memory exhaustion | ✅ **DONE** (+18 LOC) |

### ALE Provider P2

| ID | Issue | Impact | Status |
|----|-------|--------|--------|
| P2.1 | No level clamping in setLevel() | Invalid level state | ✅ **DONE** (+10 LOC) |
| P2.2 | No profile JSON structure validation | Crash on malformed JSON | ⏸️ Deferred |
| P2.3 | No context/rule ID validation | Special char injection | ⏸️ Deferred |

### Lower Zone Controller P3

| ID | Issue | Impact | Status |
|----|-------|--------|--------|
| P3.1 | Emoji icons instead of IconData | Theme inconsistency | ⏸️ Cosmetic |
| P3.2 | No category cycling shortcut | Minor UX | ⏸️ Cosmetic |
| P3.3 | No visual keyboard hints | Discoverability | ⏸️ Cosmetic |

### Stage Ingest Provider P2

| ID | Issue | Line | Impact | Status |
|----|-------|------|--------|--------|
| P2.1 | Poll loop should be bounded | 1050-1057 | UI jank with many events | ✅ **DONE** (+12 LOC) |
| P2.2 | WebSocket URL validation | 941-943 | Malformed URLs not caught | ✅ **DONE** (+45 LOC) |

### Stage Ingest Provider P3

| ID | Issue | Line | Impact | Status |
|----|-------|------|--------|--------|
| P3.1 | Generic catch clause | 462 | Could hide specific errors | ⏸️ Cosmetic |
| P3.2 | Large JSON not bounded | 800-801 | Memory exhaustion possible | ⏸️ Deferred |

---

## P2 Implementation Summary (2026-01-24)

| Fix | File | LOC | Note |
|-----|------|-----|------|
| EventRegistry P2.1 | — | 0 | Already in Rust engine |
| EventRegistry P2.2 | — | 0 | N/A (architecture) |
| ALE Provider P2.1 | `ale_provider.dart` | +10 | Level clamping 0-4 |
| Stage Ingest P2.1 | `stage_ingest_provider.dart` | +12 | Poll loop max 100 |
| Container Panels P2.7 | `middleware_provider.dart` | +18 | Child count limit (32 max) |
| CompositeEvent P2.5 | `composite_event_system_provider.dart` | +45 | Name/category XSS sanitization |
| Stage Ingest P2.2 | `stage_ingest_provider.dart` | +45 | WebSocket URL validation |
| **Total P2** | | **+130 LOC** | |

---

## P3 Items (Cosmetic)

| ID | Issue | Status | Note |
|----|-------|--------|------|
| Lower Zone P3.1 | Emoji icons | ⏸️ Skipped | Low impact, works correctly |
| Lower Zone P3.2 | Category cycling shortcut | ⏸️ Deferred | Enhancement only |
| Lower Zone P3.3 | Visual keyboard hints | ⏸️ Deferred | Enhancement only |
| Stage Ingest P3.1 | Generic catch clause | ⏸️ Deferred | Cosmetic |
| Stage Ingest P3.2 | Large JSON not bounded | ⏸️ Deferred | Rare edge case |

---

**Last Updated:** 2026-01-24 (**ALL 6 ANALYSES COMPLETE** — 10 P1 fixes ~335 LOC, 7 P2 fixes ~130 LOC)
