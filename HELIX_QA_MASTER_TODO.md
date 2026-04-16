# HELIX — Master TODO
> Updated: 2026-04-16 | Branch: feature/slotlab-ultimate-mockup
> HELIX = Jedini ekran koji ti treba. Editovanje + Monitoring + Authoring.

---

## ✅ FAZA 1 — Vizuelni shell + Read-only wiring (ZAVRŠENO)

### Bug Fixes (6/6)
- [x] FocusNode leak → initState/dispose
- [x] Double underscore `__` → `child`
- [x] Container→SizedBox resize handle
- [x] Unused import engine_connected_layout.dart
- [x] Hardcoded project name → `projectName`
- [x] Hardcoded RTP → `sessionStats.rtp`

### Panel Wiring — Read-Only (12/12)
- [x] FLOW tab → GameFlowProvider (stage nodes, current state)
- [x] AUDIO tab meters → NeuroAudioProvider (arousal/engagement)
- [x] AUDIO tab channels → MiddlewareProvider (composite events)
- [x] MATH tab → SlotLabProjectProvider + NeuroAudioProvider
- [x] TIMELINE tab → MiddlewareProvider (real trackIndex grouping)
- [x] INTEL CoPilot → RgaiProvider remediations + NeuroAudio state
- [x] INTEL RGAI → RgaiProvider compliance + NeuroAudio risk level
- [x] INTEL Engagement → NeuroAudioProvider (engagement × 10)
- [x] INTEL Mini metrics → NeuroAudioProvider (real retention, session, fatigue)
- [x] EXPORT tab → SlotExportProvider
- [x] 5 Spine overlay paneli → real provider data
- [x] Canvas PremiumSlotPreview → 5×3 fullscreen + projectProvider

### QA Results
- flutter analyze: 0 errors, 0 warnings
- cargo test: ALL passed, 0 failed

---

## 🔴 FAZA 2 — HELIX kao PUNI EDITOR (SlotLab replacement)

> Cilj: Sve što možeš u SlotLab-u, možeš i u HELIX-u.
> Posle ove faze, SlotLab postaje legacy — HELIX je primary workflow.

---

### 2.1 AUDIO tab → Editovanje (ne samo prikaz)

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| A1 | Channel strip volume fader → drag menja `masterVolume` | `MiddlewareProvider.updateCompositeEventVolume()` | ⬜ |
| A2 | Mute/Solo dugmad na channel strip-u → realno mute/solo | `MiddlewareProvider` mute/solo API | ⬜ |
| A3 | Click na channel → otvara Context Lens sa layer detaljima | Novi widget: `_AudioContextLens` | ⬜ |
| A4 | Drag-and-drop WAV iz file browser-a na channel → kreira novi sloj | `CompositeEventSystemProvider.addLayer()` | ⬜ |
| A5 | RTPC slajderi u Context Lens-u → realno menjaju RTPC vrednosti | `MiddlewareProvider.setRtpcValue()` | ⬜ |
| A6 | Master fader → ukupni output volume | `EngineProvider` master volume | ⬜ |

---

### 2.2 TIMELINE tab → Interaktivni editor

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| T1 | Drag event region levo/desno → menja `timelinePositionMs` | `CompositeEventSystemProvider.updateEvent()` | ⬜ |
| T2 | Resize region edges → menja trajanje | `CompositeEventSystemProvider` | ⬜ |
| T3 | Playhead marker → klik na ruler pomera playhead | `EngineProvider.seek()` | ⬜ |
| T4 | Playhead animacija tokom playback-a | `EngineProvider.transport.positionSeconds` | ⬜ |
| T5 | Right-click na region → kontekst meni (delete, duplicate, split) | Context menu widget | ⬜ |
| T6 | Drag event između track-ova → menja `trackIndex` | `CompositeEventSystemProvider` | ⬜ |

---

### 2.3 MATH tab → Konfiguracija (ne samo statistika)

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| M1 | Target RTP input field → set target, vizuelni diff sa current | `SlotLabProjectProvider` | ⬜ |
| M2 | Volatility slider → podešava profil (Low/Med/High/Ultra) | `SlotEngineProvider.setVolatilityProfile()` FFI | ⬜ |
| M3 | "Run Simulation" dugme → pokreće batch A/B sim sa rezultatom | `rf-ab-sim` FFI → `AbTestProvider` | ⬜ |
| M4 | Max Win cap input → konfiguracija | `SlotLabProjectProvider` | ⬜ |
| M5 | Hit frequency target slider | `SlotEngineProvider` config | ⬜ |
| M6 | Bonus frequency target slider | `SlotEngineProvider` config | ⬜ |

---

### 2.4 FLOW tab → Stage editovanje

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| F1 | Click na stage node → force transition u taj stage | `GameFlowProvider.forceTransition()` | ⬜ |
| F2 | Right-click na node → konfiguriši transition rules | Config panel | ⬜ |
| F3 | Dodaj/ukloni custom stage nodes | `GameFlowProvider` | ⬜ |
| F4 | Stage→Audio mapping prikaz (koji eventi se triggeruju na koji stage) | `EventRegistry` cross-reference | ⬜ |

---

### 2.5 INTEL tab → AI CoPilot interakcija

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| I1 | "Apply" dugme na svakoj RGAI remediaciji → primeni sugestiju | `MiddlewareProvider` / `NeuroAudioProvider` | ⬜ |
| I2 | CoPilot chat input → pitaj AI za savet | `rf-copilot` FFI → CoPilotProvider | ⬜ |
| I3 | NeuroAudio archetype selector (Casual/Whale/Frustrated) → preview | `NeuroAudioProvider.setArchetype()` | ⬜ |
| I4 | "Simulate Session" dugme → 200 spin simulacija sa live metrikom | `NeuroAudioProvider` simulation mode | ⬜ |
| I5 | RGAI "Run Analysis" dugme → pokreni compliance sken | `RgaiProvider.runAnalysis()` | ⬜ |

---

### 2.6 EXPORT tab → Puni workflow

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| E1 | Progress bar tokom exporta | `SlotExportProvider.isExporting` + progress | ⬜ |
| E2 | Format-specific opcije (sample rate, bit depth) | Export config panel | ⬜ |
| E3 | Compliance gate → blokira export ako RGAI HIGH risk | `RgaiProvider.isCompliant` check | ⬜ |
| E4 | Export result prikaz (success/fail, putanja fajla) | `SlotExportProvider.lastExportResults` | ⬜ |
| E5 | Batch export svih formata odjednom | `SlotExportProvider.exportAll()` | ⬜ |

---

### 2.7 Spine Panels → Puni editori

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| S1 | AUDIO ASSIGN spine: click event → otvara layer editor | `CompositeEventSystemProvider` | ⬜ |
| S2 | AUDIO ASSIGN spine: drag WAV → assign na event | DnD + `addLayer()` | ⬜ |
| S3 | AUDIO ASSIGN spine: "New Event" dugme → kreira prazan composite | `CompositeEventSystemProvider.createEvent()` | ⬜ |
| S4 | GAME CONFIG spine: edit reels/rows/bet range | `SlotLabProjectProvider` | ⬜ |
| S5 | AI/INTEL spine: RTPC slajderi (8 dimenzija) → real-time preview | `NeuroAudioProvider` RTPC write | ⬜ |
| S6 | SETTINGS spine: BPM input → `EngineProvider.setTempo()` | EngineProvider FFI | ⬜ |
| S7 | SETTINGS spine: toggle neuro RG mode | `NeuroAudioProvider.setResponsibleGamingMode()` | ⬜ |
| S8 | ANALYTICS spine: export session report button | SlotLabProjectProvider | ⬜ |

---

### 2.8 Canvas → Interaktivni slot machine

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| C1 | Click na reel cell → Context Lens sa audio config za taj reel | Mockup: `openLens()` behavior | ⬜ |
| C2 | Context Lens sa RTPC slajderima per-reel | `MiddlewareProvider.setRtpcValue()` | ⬜ |
| C3 | Stage strip clickable → force game flow transition | `GameFlowProvider.forceTransition()` | ⬜ |
| C4 | Spin dugme u Canvas-u (SPACE key already works in PremiumSlotPreview) | Already wired | ✅ |

---

### 2.9 Omnibar → Workflow controls

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| O1 | Undo/Redo dugmad → realni undo/redo | `SlotLabProjectProvider.undo()/redo()` | ⬜ |
| O2 | Project name editable (click → inline edit) | `SlotLabProjectProvider.setProjectName()` | ⬜ |
| O3 | BPM pill clickable → tap to edit tempo | `EngineProvider.setTempo()` | ⬜ |
| O4 | Record dugme → start recording session | `EngineProvider.record()` | ⬜ |

---

## FAZA 3 — Napredni authoring (posle Faze 2)

| # | Feature | Notes |
|---|---------|-------|
| 3.1 | SFX Pipeline Wizard u HELIX-u | 6-step import→export workflow |
| 3.2 | Behavior Tree visual editor u dock-u | Node-based editor, 22 node types |
| 3.3 | PAR file import → auto audio mapping | MathAudio Bridge from architecture |
| 3.4 | Audio DNA / Fingerprint generator | Brand identity generation |
| 3.5 | AI Generation panel | rf-ai-gen crate → generate audio from text |
| 3.6 | Cloud Sync status/controls | rf-cloud-sync crate |
| 3.7 | A/B Split test editor | Full test configuration UI |

---

## Prioritizacija

**Odmah (Faza 2 core):**
1. A1-A3 (Audio faders + mute/solo + context lens) — ovo je najvidljivije
2. T1, T3-T4 (Timeline drag + playhead) — osnovna interakcija
3. I1, I5 (Apply suggestions + Run Analysis) — AI value
4. O1-O3 (Undo/Redo + edit project name + BPM) — basic workflow
5. S6-S7 (BPM edit + RG toggle u Settings spine)

**Sledeći sprint:**
6. F1, F4 (Force stage + stage→audio mapping)
7. M1-M3 (RTP target + volatility + simulation)
8. C1-C3 (Context Lens na reel click)
9. E1-E4 (Export progress + compliance gate)

**Poslednji sprint:**
10. A4-A5 (DnD audio + RTPC slajderi)
11. T2, T5-T6 (Resize + context menu + track reorder)
12. S1-S5 (Spine full editors)
13. I2-I4 (CoPilot chat + archetype + simulation)

---

## Provider Dependency Map (HELIX full editor)
```
EngineProvider ──────────── Transport, BPM edit, Seek, Record, Master volume
GameFlowProvider ────────── Stage nodes, Force transition, Stage rules
MiddlewareProvider ──────── Channels, RTPC read/write, Mute/Solo, Composite CRUD
SlotLabProjectProvider ──── Project name, Stats, Reels/Rows, Undo/Redo, Win config
NeuroAudioProvider ──────── 8D state, Archetype select, RG toggle, Session sim
RgaiProvider ────────────── Compliance, Apply remediation, Run analysis
SlotExportProvider ──────── Export formats, Progress, Results, Batch
CompositeEventSystemProvider Layer editor, DnD assign, Create/Delete events
AbTestProvider ──────────── A/B simulation, Variant config
```
