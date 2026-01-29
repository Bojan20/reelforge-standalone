# SlotLab Analysis — FAZA 1: Panel-Role Mapping

**Date:** 2026-01-29
**Status:** ✅ COMPLETE
**Duration:** 30 min

---

## 9 Uloga (iz CLAUDE.md)

| # | Uloga | Domen |
|---|-------|-------|
| 1 | **Chief Audio Architect** | Audio pipeline, DSP, spatial, mixing |
| 2 | **Lead DSP Engineer** | Filters, dynamics, SIMD, real-time |
| 3 | **Engine Architect** | Performance, memory, systems |
| 4 | **Technical Director** | Architecture, tech decisions |
| 5 | **UI/UX Expert** | DAW workflows, pro audio UX |
| 6 | **Graphics Engineer** | GPU rendering, shaders, visualization |
| 7 | **Security Expert** | Input validation, safety |
| 8 | **Slot Game Designer** | Slot mechanics, math, features |
| 9 | **Producer / Product Owner** | Roadmap, priorities, market fit |

---

## 4 Glavna Panela

### 1. LEVI PANEL (UltimateAudioPanel + SymbolStrip)

**Komponente:**
- UltimateAudioPanel — 341 audio slotova × 12 sekcija (Base Game, Symbols, Wins, Cascades, Multipliers, Free Spins, Bonus, Hold & Win, Jackpots, Gamble, Music, UI)
- SymbolStripWidget — Symbol definitions + Music layer assignments

**Uloge koje koriste (5):**

| Uloga | Use Case | Sekcije |
|-------|----------|---------|
| **Chief Audio Architect** | Organizacija audio po game flow-u | Sve sekcije |
| **Audio Designer / Composer** | Dodavanje audio fajlova, layering | Sve sekcije |
| **Slot Game Designer** | Mapiranje simbola na audio | Symbols, Wins, Features |
| **UI/UX Expert** | Audio browser, drag-drop workflow | Panel navigation |
| **Producer** | Audio content review, completeness check | Sve sekcije |

**Primarni data flow:**
```
Audio File → UltimateAudioPanel slot → Drop → EventRegistry
Symbol Audio → SymbolStripWidget → SlotLabProjectProvider → EventRegistry
Music Layer → SymbolStripWidget → ALE Provider → Adaptive layering
```

---

### 2. DESNI PANEL (EventsPanelWidget)

**Komponente:**
- Events Folder — Event tree sa create/delete
- Audio Browser — Waveform preview, drag-drop
- File/Folder Import — Bulk import buttons
- Audio Pool Toggle — DAW↔SlotLab sync

**Uloge koje koriste (4):**

| Uloga | Use Case | Features |
|-------|----------|----------|
| **Audio Middleware Architect** | Event creation, stage binding | Events folder, event CRUD |
| **Audio Designer** | Audio browsing, waveform preview | Audio browser, drag-drop |
| **Tooling Developer** | Bulk import, file management | File/Folder import |
| **QA Engineer** | Event validation, testing | Event list verification |

**Primarni data flow:**
```
Audio Browser → Drag to Slot Mockup → QuickSheet → MiddlewareProvider → EventRegistry
File Import → AudioAssetManager → Audio Pool → Available for drag
```

---

### 3. LOWER ZONE (7 Super-Tabs + Menu)

**Super-Tabs:**
1. **Stages** (Timeline, Event Debug)
2. **Events** (Event list, RTPC, Composite Editor)
3. **Mix** (Bus hierarchy, Aux sends, Meters)
4. **DSP** (FabFilter EQ/Comp/Limiter/Gate/Reverb)
5. **Bake** (Batch export, validation, package)
6. **Music/ALE** (ALE rules, signals, transitions)
7. **Engine** (Profiler, Stage Ingest)

**Uloge koje koriste (SVE 9):**

| Uloga | Primary Tabs | Use Case |
|-------|--------------|----------|
| **Chief Audio Architect** | Mix, DSP, Music/ALE | Bus routing, mastering chain, adaptive music |
| **Lead DSP Engineer** | DSP, Mix | FabFilter panels, dynamics, EQ |
| **Engine Architect** | Engine, Profiler | Performance monitoring, stage ingest |
| **Technical Director** | Sve | Architecture overview, system health |
| **UI/UX Expert** | Stages, Events | Workflow optimization |
| **Graphics Engineer** | DSP (spectrum) | Visualization quality |
| **Security Expert** | Bake | Export validation |
| **Slot Game Designer** | Stages, Events, Bake | Audio-visual sync, testing, delivery |
| **Producer** | Bake, Engine | Export readiness, performance metrics |

**Primarni data flow:**
```
Stage Trace → EventRegistry trigger → Audio playback
Event Editor → MiddlewareProvider → FFI sync → Rust engine
Bus Hierarchy → MixerDSPProvider → FFI → Audio routing
FabFilter DSP → DspChainProvider → InsertProcessor → Audio processing
Batch Export → Validation → JSON/ZIP package
ALE → Music layering → Adaptive audio
Stage Ingest → External engine → Stage events → Audio trigger
```

---

### 4. CENTRALNI PANEL (PremiumSlotPreview + EmbeddedSlotMockup)

**Komponente:**
- 8 UI zona (Header, Jackpot, Reels, Win Presenter, Features, Controls, Info, Settings)
- 6-Phase reel animation (Idle, Accelerating, Spinning, Decelerating, Bouncing, Stopped)
- Win presentation system (3 faze: Symbol highlight, Tier plaque rollup, Win line cycling)
- Audio-visual sync (callbacks na visual events)

**Uloge koje koriste (6):**

| Uloga | Use Case | Features |
|-------|----------|----------|
| **Slot Game Designer** | Slot simulation, feature testing | Full preview, forced outcomes, GDD config |
| **Audio Designer** | Audio-visual sync testing | Hear audio in context, timing verification |
| **QA Engineer** | Regression testing, determinism | Forced outcomes (1-7 keys), consistent results |
| **Producer** | Client preview, approval workflow | Fullscreen mode (F11), realistic presentation |
| **UI/UX Expert** | Player experience testing | Control flow, feature indicators |
| **Graphics Engineer** | Animation quality, particles | Win animations, cascade overlays |

**Primarni data flow:**
```
User Action (Spin) → SlotLabProvider.spin()
                   ↓
Rust Engine (slotLabSpin) → SpinResult + Stages
                   ↓
Visual Animation (6-phase reel) → onReelStop callbacks
                   ↓
EventRegistry.triggerStage() → Audio playback
                   ↓
Win Presentation (3-phase) → WIN_PRESENT, ROLLUP, WIN_LINE_SHOW stages
```

---

## 📊 Panel Usage Matrix

| Panel | Audio Arch | DSP Eng | Engine Arch | Tech Dir | UX | Graphics | Security | Slot Designer | Producer |
|-------|------------|---------|-------------|----------|-----|----------|----------|---------------|----------|
| **Levi** | 🟢 Primary | — | — | — | 🟡 Secondary | — | — | 🟢 Primary | 🟡 Secondary |
| **Desni** | 🟢 Primary | — | — | — | 🟡 Secondary | — | — | — | — |
| **Lower Zone** | 🟢 Primary | 🟢 Primary | 🟢 Primary | 🟢 Primary | 🟢 Primary | 🟡 Secondary | 🟡 Secondary | 🟢 Primary | 🟢 Primary |
| **Centralni** | 🟡 Secondary | — | — | — | 🟢 Primary | 🟢 Primary | — | 🟢 Primary | 🟢 Primary |

**Legend:**
- 🟢 Primary — Main use case za ovu ulogu
- 🟡 Secondary — Koristi povremeno
- — — Ne koristi

---

## 🎯 Key Insights

### Coverage Summary

**Most Used Panels:**
- Lower Zone → Koristi svih 9 uloga (univerzalan)
- Levi Panel → 5 uloga (audio fokus)
- Centralni Panel → 6 uloga (testing fokus)
- Desni Panel → 4 uloga (event management fokus)

**Most Active Roles:**
- Technical Director → Koristi sve 4 panela
- Chief Audio Architect → Koristi sve 4 panela
- Slot Game Designer → Koristi 3 panela (Levi, Centralni, Lower Zone)

**Least Active Roles:**
- Lead DSP Engineer → Samo Lower Zone (DSP tab)
- Security Expert → Samo Lower Zone (Bake validation)
- Graphics Engineer → Centralni + Lower Zone (spectrum)

### Potential Gaps (Preview)

**DSP Engineer:**
- Nedostaje dedicated DSP testing panel izvan Lower Zone
- FabFilter paneli su u Lower Zone → mora otvoriti tab

**Security Expert:**
- Validation samo u Bake fazi → ne preventivno tokom authoring-a
- Nema real-time security warnings

**Graphics Engineer:**
- Spectrum analyzer samo u Lower Zone
- Nema waveform kvalitet settings u main UI

---

## ✅ FAZA 1 COMPLETE

**Next Step:** Proceed to FAZA 2.1 (Levi Panel dubinska analiza)

---

**Created:** 2026-01-29
**Version:** 1.0
