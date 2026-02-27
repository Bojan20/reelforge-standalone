## 🔬 KOMPLET ANALIZA SISTEMA — Ultimate System Review

**Trigger:** Kada korisnik kaže "komplet analiza sistema", "full system review", "ultimate analysis"

**Uloga:** Principal Engine Architect + Audio Middleware Architect + Slot Systems Designer + UX Lead

**Cilj:** Potpuna, ultimativna analiza FluxForge Studio kao:
- Profesionalni slot-audio middleware
- Authoring alat za dizajnere
- Runtime engine
- Offline DSP pipeline
- Simulacioni alat za slot igre
- Kreativni alat za audio dizajnere
- Produkcioni alat za studije

---

### FAZA 1: Analiza po ulogama (9 uloga)

Za SVAKU ulogu izvršiti:

| # | Uloga | Fokus |
|---|-------|-------|
| 1 | 🎮 Slot Game Designer | Slot layout, math, GDD, feature flow |
| 2 | 🎵 Audio Designer / Composer | Layering, states, events, mixing |
| 3 | 🧠 Audio Middleware Architect | Event model, state machines, runtime |
| 4 | 🛠 Engine / Runtime Developer | FFI, playback, memory, latency |
| 5 | 🧩 Tooling / Editor Developer | UI, workflows, batch processing |
| 6 | 🎨 UX / UI Designer | Mental models, discoverability, friction |
| 7 | 🧪 QA / Determinism Engineer | Reproducibility, validation, testing |
| 8 | 🧬 DSP / Audio Processing Engineer | Filters, dynamics, offline processing |
| 9 | 🧭 Producer / Product Owner | Roadmap, priorities, market fit |

**Za svaku ulogu odgovoriti:**

```
1. SEKCIJE: Koje delove FluxForge ta uloga koristi?
2. INPUTS: Koje podatke unosi?
3. OUTPUTS: Šta očekuje kao rezultat?
4. DECISIONS: Koje odluke donosi?
5. FRICTION: Gde se sudara sa sistemom?
6. GAPS: Šta nedostaje toj ulozi?
7. PROPOSAL: Kako poboljšati iskustvo te uloge?
```

---

### FAZA 2: Analiza po sekcijama (15+ sekcija)

Za SVAKU sekciju:

| Sekcija | Ključna pitanja |
|---------|-----------------|
| Project / Game Setup | Kako se definiše igra? Koji metapodaci? |
| Slot Layout / Mockup | Vizuelni prikaz grida, reels, simbola |
| Math & GDD Layer | Volatility, RTP, paytable integracija |
| Audio Layering System | Kako rade layer levels L1-L5? |
| Event Graph / Triggers | Stage→Event mapiranje, priority |
| Music State System | Contexts, transitions, sync modes |
| Feature Modules | FS, Bonus, Hold&Win, Cascade, Jackpot |
| Asset Manager | Import, tagging, variants, banks |
| DSP / Offline Processing | Loudness, peak limiting, format conversion |
| Runtime Adapter | Howler, Unity, Unreal, native export |
| Simulation / Preview | Synthetic engine, forced outcomes |
| Export / Manifest | JSON, binary, package structure |
| QA / Validation | Determinism, coverage, regression |
| Versioning / Profiles | Platform profiles, A/B testing |
| Automation / Batch | Scripting, CI/CD integration |

**Za svaku sekciju:**

```
1. PURPOSE: Koja je svrha?
2. INPUT: Šta prima?
3. OUTPUT: Šta proizvodi?
4. DEPENDENCIES: Od čega zavisi?
5. DEPENDENTS: Ko zavisi od nje?
6. ERRORS: Koje greške su moguće?
7. CROSS-IMPACT: Kako utiče na druge sekcije?
```

---

### FAZA 3: Horizontalna sistemska analiza

**Data Flow Analysis:**
```
Designer → FluxForge → Runtime Engine
    ↓           ↓           ↓
  Inputs    Processing   Outputs
```

**Identifikovati:**
- Gde se GUBI informacija?
- Gde se DUPLIRA logika?
- Gde se KRŠI determinizam?
- Gde je hard-coded umesto data-driven?
- Gde nedostaje "single source of truth"?

**Preporučiti:**
- Pure state machines
- Declarative layer logic
- Data-driven rule systems
- Eliminiacija if/else odluka u runtime-u

---

### FAZA 4: Obavezni deliverables

| # | Deliverable | Format |
|---|-------------|--------|
| 1 | 📐 Sistem mapa | ASCII dijagram + opis |
| 2 | 🧩 Idealna arhitektura | Authoring → Pipeline → Runtime |
| 3 | 🎛 Ultimate Layering Model | Slot-specifičan L1-L5 sistem |
| 4 | 🧠 Unified Event Model | Stage → Event → Audio chain |
| 5 | 🧪 Determinism & QA Layer | Validation, reproducibility |
| 6 | 🧭 Roadmap (M-milestones) | Prioritized phases |
| 7 | 🔥 Critical Weaknesses | Top 10 pain points |
| 8 | 🚀 Vision Statement | FluxForge kao Wwise/FMOD za slots |

---

### FAZA 5: Benchmark standardi

FluxForge mora nadmašiti:
- **Wwise** — Event model, state groups, RTPC
- **FMOD** — Layering, music system, runtime efficiency
- **Unity** — Authoring UX, preview, prototyping
- **iZotope** — DSP quality, offline processing

---

### Pravila izvršenja

1. **Ništa ne preskači** — svaka uloga, svaka sekcija
2. **Ništa ne pojednostavljuj** — inženjerski dokument, ne marketing
3. **Budi kritičan** — identifikuj slabosti bez diplomatije
4. **Budi konstruktivan** — svaka kritika ima predlog
5. **Output format:**
   - Markdown dokument u `.claude/reviews/`
   - Naziv: `SYSTEM_REVIEW_YYYY_MM_DD.md`
   - Commit nakon završetka

---

### Quick Reference — Fajlovi za analizu

```
# Core Providers
flutter_ui/lib/providers/middleware_provider.dart
flutter_ui/lib/providers/slot_lab_provider.dart
flutter_ui/lib/providers/ale_provider.dart
flutter_ui/lib/providers/stage_ingest_provider.dart

# Services
flutter_ui/lib/services/event_registry.dart
flutter_ui/lib/services/audio_playback_service.dart
flutter_ui/lib/services/service_locator.dart

# Rust Engine
crates/rf-engine/src/
crates/rf-bridge/src/
crates/rf-ale/src/
crates/rf-slot-lab/src/
crates/rf-stage/src/
crates/rf-ingest/src/
crates/rf-connector/src/

# Stage Ingest UI
flutter_ui/lib/widgets/stage_ingest/

# Architecture Docs
.claude/architecture/
.claude/domains/
```

---

**VAŽNO:** Ova analiza može trajati dugo. Koristiti Task tool za paralelizaciju gde je moguće. Rezultat mora biti production-ready dokument koji služi kao osnova za roadmap.

---


## 🔍 SLOTLAB SYSTEM ANALYSIS SUMMARY (2026-01-24)

Kompletna analiza SlotLab audio sistema — 8 task-ova, 6 dokumenata.

**Lokacija:** `.claude/analysis/`

### Analysis Documents

| Document | Focus | Status |
|----------|-------|--------|
| `AUDIO_VISUAL_SYNC_ANALYSIS_2026_01_24.md` | SlotLabProvider ↔ EventRegistry sync | ✅ VERIFIED |
| `QUICKSHEET_EVENT_CREATION_ANALYSIS_2026_01_24.md` | QuickSheet draft→commit flow | ✅ VERIFIED |
| `WIN_LINE_PRESENTATION_ANALYSIS_2026_01_24.md` | Win line coordinates, timers | ✅ VERIFIED |
| `CONTAINER_SYSTEM_ANALYSIS_2026_01_24.md` | Container FFI (~1225 LOC) | ✅ VERIFIED |
| `LOWER_ZONE_PANEL_CONNECTIVITY_ANALYSIS_2026_01_24.md` | 21 panels, all connected | ✅ VERIFIED |
| `ALE_SYSTEM_ANALYSIS_2026_01_24.md` | ALE FFI (776 LOC), 29 functions | ✅ VERIFIED |
| `AUTOSPATIAL_SYSTEM_ANALYSIS_2026_01_24.md` | AutoSpatial engine (~2296 LOC) | ✅ VERIFIED |

### Key Findings

**Audio-Visual Sync (P0.1):**
- Stage event flow: `spin()` → `_broadcastStages()` → EventRegistry → Audio
- `_lastNotifiedStages` deduplication prevents double-plays
- `notifyListeners()` at line 420 triggers EventRegistry sync

**QuickSheet Flow (P0.2):**
- `createDraft()` at `quick_sheet.dart:37` — SINGLE call point
- `commitDraft()` at `auto_event_builder_provider.dart:132` — SINGLE call point
- Bridge function `_onEventBuilderEventCreated()` at `slot_lab_screen.dart:6835`

**Container System (P1.1):**
- 40+ FFI functions in `container_ffi.rs` (~1225 LOC)
- P3D smoothing functions exist in Rust (lines 164, 171, 178)
- Dart bindings added: `containerSetBlendRtpcTarget`, `containerSetBlendSmoothing`, `containerTickBlendSmoothing`

**Lower Zone (P1.3):**
- 21 panels across 5 super-tabs (Stages, Events, Mix, DSP, Bake)
- ALL connected to real providers — NO placeholders
- Action strips call real provider methods

**Stage→Audio Chain (P2.1):**
- Path: Stage → EventRegistry.triggerStage() → _tryPlayEvent() → AudioPlaybackService
- Fallback resolution: `REEL_STOP_0` → `REEL_STOP` (generic)
- isLooping detection: `_LOOP` suffix, `MUSIC_*`, `AMBIENT_*` prefixes

**ALE System (P2.2):**
- 29 FFI functions fully implemented
- Tick loop at 16ms (`ale_provider.dart:783-806`)
- Signals: 18+ built-in (winTier, momentum, etc.)

**AutoSpatial (P2.3):**
- 24+ intent rules (`auto_spatial.dart:662-896`)
- 6 bus policies (UI, Reels, SFX, VO, Music, Ambience)
- Per-reel pan formula: `(reelIndex - 2) * 0.4`

### FFI Coverage

| System | Rust LOC | Dart Bindings | Status |
|--------|----------|---------------|--------|
| Container | ~1225 | 40+ functions | ✅ Complete |
| ALE | ~776 | 29 functions | ✅ Complete |
| AutoSpatial | ~2296 | Provider-based | ✅ Complete |
| Slot Lab | ~1200 | 20+ functions | ✅ Complete |

### Conclusion

**ALL SlotLab audio systems are FULLY OPERATIONAL:**
- Stage→Audio resolution works correctly
- Event creation via QuickSheet works correctly
- Container evaluation (Blend/Random/Sequence) works correctly
- ALE adaptive layering works correctly
- AutoSpatial panning works correctly
- Lower Zone panels all connected to real data

**No critical gaps identified.** System is production-ready.
