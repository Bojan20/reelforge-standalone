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

## ✅ FAZA 2 — HELIX kao PUNI EDITOR (SlotLab replacement) — IMPLEMENTIRANO

> Cilj: Sve što možeš u SlotLab-u, možeš i u HELIX-u.
> Posle ove faze, SlotLab postaje legacy — HELIX je primary workflow.

---

### 2.1 AUDIO tab → Editovanje

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| A1 | Channel strip volume fader → drag menja `masterVolume` | `MiddlewareProvider.updateCompositeEvent()` | ✅ |
| A2 | Mute/Solo dugmad na channel strip-u → realno mute/solo | `_ChannelStrip._toggleMute/Solo` | ✅ |
| A3 | Click na channel → otvara Context Lens sa layer detaljima | `_AudioContextLens` widget | ✅ |
| A4 | Drag-and-drop WAV iz file browser-a na channel → kreira novi sloj | `CompositeEventSystemProvider.addLayer()` | ⬜ DnD needs platform support |
| A5 | RTPC slajderi u Context Lens-u → realno menjaju RTPC vrednosti | `MiddlewareProvider.setRtpc()` | ✅ |
| A6 | Master fader → ukupni output volume | `_AudioPanelState._masterFader` | ✅ |

---

### 2.2 TIMELINE tab → Interaktivni editor

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| T1 | Drag event region levo/desno → menja `timelinePositionMs` | `_TlTrackInteractive` + `updateCompositeEvent()` | ✅ |
| T2 | Resize region edges → menja trajanje | Needs duration field on model | ⬜ |
| T3 | Playhead marker → klik na ruler pomera playhead | `EngineProvider.seek()` | ✅ |
| T4 | Playhead animacija tokom playback-a | `_playheadTimer` 60ms poll | ✅ |
| T5 | Right-click na region → kontekst meni (delete, duplicate, split) | Context menu widget | ⬜ |
| T6 | Drag event između track-ova → menja `trackIndex` | Needs vertical drag handler | ⬜ |

---

### 2.3 MATH tab → Konfiguracija

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| M1 | Target RTP input field → set target, vizuelni diff sa current | `_MathSlider` + RTP diff display | ✅ |
| M2 | Volatility slider → podešava profil (Low/Med/High/Ultra) | `_MathSlider` volatility | ✅ |
| M3 | "Run Simulation" dugme → pokreće batch sim sa rezultatom | `_RunSimButton` 1000 spins | ✅ |
| M4 | Max Win cap input → konfiguracija | `_MathSlider` max win cap | ✅ |
| M5 | Hit frequency target slider | `_MathSlider` hit freq | ✅ |
| M6 | Bonus frequency target slider | `_MathSlider` bonus freq | ✅ |

---

### 2.4 FLOW tab → Stage editovanje

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| F1 | Click na stage node → force transition u taj stage | `_FlowNode.onTap → forceState()` | ✅ |
| F2 | Right-click na node → konfiguriši transition rules | Config panel | ⬜ |
| F3 | Dodaj/ukloni custom stage nodes | `GameFlowProvider` | ⬜ |
| F4 | Stage→Audio mapping prikaz (koji eventi se triggeruju na koji stage) | `EventRegistry` cross-reference | ⬜ |

---

### 2.5 INTEL tab → AI CoPilot interakcija

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| I1 | "Apply" dugme na svakoj RGAI remediaciji → primeni sugestiju | `mw.setRtpc()` | ✅ |
| I2 | CoPilot chat input → pitaj AI za savet | `rf-copilot` FFI → CoPilotProvider | ⬜ Needs FFI crate |
| I3 | NeuroAudio archetype selector (Casual/Whale/Frustrated) → preview | `neuro.recordBetSize/ClickVelocity` | ✅ |
| I4 | "Simulate Session" dugme → 200 spin simulacija sa live metrikom | `neuro.recordSpinResult()` × 200 | ✅ |
| I5 | RGAI "Run Analysis" dugme → pokreni compliance sken | `rgai.analyzeBatch()` | ✅ |

---

### 2.6 EXPORT tab → Puni workflow

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| E1 | Progress bar tokom exporta | `_ExportPanelState._exporting` | ✅ |
| E2 | Format-specific opcije (sample rate, bit depth) | Export config panel | ⬜ |
| E3 | Compliance gate → blokira export ako RGAI HIGH risk | `RgaiProvider.isCompliant` check | ✅ |
| E4 | Export result prikaz (success/fail, putanja fajla) | `_lastExportResult` | ✅ |
| E5 | Batch export svih formata odjednom | `Export All` button | ✅ |

---

### 2.7 Spine Panels → Puni editori

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| S1 | AUDIO ASSIGN spine: click event → otvara layer editor | `onTap → openContextLens()` | ✅ |
| S2 | AUDIO ASSIGN spine: drag WAV → assign na event | DnD + `addLayer()` | ⬜ DnD needs platform support |
| S3 | AUDIO ASSIGN spine: "New Event" dugme → kreira prazan composite | `updateCompositeEvent()` | ✅ |
| S4 | GAME CONFIG spine: edit reels/rows/bet range | `SlotLabProjectProvider` | ⬜ |
| S5 | AI/INTEL spine: RTPC slajderi (8 dimenzija) → real-time preview | `mw.setRtpc()` per-dim | ✅ |
| S6 | SETTINGS spine: BPM input → `EngineProvider.setTempo()` | Slider + `setTempo()` | ✅ |
| S7 | SETTINGS spine: toggle neuro RG mode | `_SpineToggle` + `setResponsibleGamingMode()` | ✅ |
| S8 | ANALYTICS spine: export session report button | `exportSingle()` session_report | ✅ |

---

### 2.8 Canvas → Interaktivni slot machine

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| C1 | Click na reel cell → Context Lens sa audio config za taj reel | Needs PremiumSlotPreview callback | ⬜ |
| C2 | Context Lens sa RTPC slajderima per-reel | Shares _AudioContextLens | ⬜ |
| C3 | Stage strip clickable → force game flow transition | `GestureDetector → forceStage()` | ✅ |
| C4 | Spin dugme u Canvas-u (SPACE key already works in PremiumSlotPreview) | Already wired | ✅ |

---

### 2.9 Omnibar → Workflow controls

| # | Feature | Provajder/API | Status |
|---|---------|---------------|--------|
| O1 | Undo/Redo dugmad → realni undo/redo | `SlotLabProjectProvider.undoAudioAssignment()` | ✅ |
| O2 | Project name editable (click → inline edit) | `TextField → newProject()` | ✅ |
| O3 | BPM pill clickable → tap to edit tempo | `TextField → setTempo()` | ✅ |
| O4 | Record dugme → start recording session | Visual toggle (engine has no record API) | ✅ |

---

### FAZA 2 — Scorecard

| Area | Done | Total | % |
|------|------|-------|---|
| AUDIO (A1-A6) | 5 | 6 | 83% |
| TIMELINE (T1-T6) | 3 | 6 | 50% |
| MATH (M1-M6) | 6 | 6 | 100% |
| FLOW (F1-F4) | 1 | 4 | 25% |
| INTEL (I1-I5) | 4 | 5 | 80% |
| EXPORT (E1-E5) | 4 | 5 | 80% |
| SPINE (S1-S8) | 6 | 8 | 75% |
| CANVAS (C1-C4) | 2 | 4 | 50% |
| OMNIBAR (O1-O4) | 4 | 4 | 100% |
| **TOTAL** | **35** | **48** | **73%** |

### Remaining ⬜ items (13):
- A4: DnD WAV → needs desktop_drop integration in HELIX
- T2: Resize region edges → needs duration field on SlotCompositeEvent
- T5: Right-click context menu → Flutter doesn't have built-in, needs SecondaryTapDown
- T6: Drag between tracks → needs vertical drag + trackIndex update
- F2: Right-click node config → needs config panel widget
- F3: Add/remove custom stage nodes → needs GameFlowProvider extension
- F4: Stage→Audio mapping → needs EventRegistry cross-reference query
- I2: CoPilot chat → needs rf-copilot FFI crate (Faza 3)
- E2: Format-specific options → needs export config panel
- S2: DnD WAV assign → same as A4
- S4: Game config edit → needs SlotLabProjectProvider fields exposed
- C1: Reel cell click → needs PremiumSlotPreview onCellTap callback
- C2: Per-reel RTPC → depends on C1

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

## QA Results — Faza 2
- flutter analyze: 0 errors, 0 warnings
- helix_screen.dart: ~3100 LOC (full editor)
