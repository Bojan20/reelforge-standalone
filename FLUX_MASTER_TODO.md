# FluxForge Studio — MASTER TODO (definitive)

> Ažurirano: 2026-04-25 · Grana: `fix/ci-infra`
> Sinhronizovano sa `FLUX_MASTER_VISION_2026.md` (1,689 linija, 18,057 reči).

---

## IMPERATIVI (uvek, bez izuzetka)

1. **Kompaktnost i brzina su imperativ** — svaki novi widget / panel / flow mora biti jasniji i brži od prethodnog. Bez "samo još jedan tab".
2. **Kvalitet se podrazumeva** — 0 flutter analyze errors, cargo clippy clean, 60fps pod 50+ voice load, zero audio dropout, uvek testovi.
3. **CORTEX OČI / RUKE zakon** — uvek CortexEye/CortexHands, nikad macOS screenshot, nikad Boki klikće.
   - `GET  /eye/snap`, `GET /eye/logs`, `GET /eye/inspect`
   - `POST /hands/tap`, `POST /hands/input`, `POST /hands/swipe`
   - Redosled: impl → CortexEye snap → CortexHands verify → tek onda izveštaj.

---

## FAZA 0 — Nekomitovano / nedovršeno (trenutno)

| # | Zadatak | Fajl(ovi) | Status |
|---|---|---|---|
| 0.1 | CortexEye snap MIX tab sa double-tap verifikacija VoiceDetailEditor | — | ⏳ BuildContext zavisno, CortexHands verify |
| 0.2 | CortexEye snap MIX tab sa long-press verifikacija Radial Action Menu | — | ⏳ BuildContext zavisno, CortexHands verify |
| 0.3 | Posle verifikacije 0.1/0.2 → ako padne, fix; ako radi, commitovano je `830d9cb1` | — | ⏳ |

---

## FAZA 1 — P0 BLOKIRAJUĆE (pre v1 release)

> Ne puštamo javno dok ovo ne zatvorimo.

### 1.1 FFI sigurnost (Rust)

| # | Problem | Lokacija | Effort |
|---|---|---|---|
| 1.1.1 | 8× `CStr::from_ptr` bez null check — crash sa Dart strane | `crates/rf-bridge/src/slot_lab_ffi.rs:916` + `pbse_ffi.rs:849` + 6 sites | 30 min |
| 1.1.2 | BUG #63 scenario validation — dimenzije outcome-a nisu provereno sa aktivnim GameModel | `crates/rf-bridge/src/slot_lab_ffi.rs:1635-1640` | 1 h |
| 1.1.3 | BUG #32 LV2 Mutex poison — `.unwrap_or_else(\|e\| e.into_inner())` može vratiti corrupted URID map | `crates/rf-engine/src/plugin/lv2.rs:120-136` → prebaci na `parking_lot::Mutex` | 30 min |
| 1.1.4 | TOCTOU u voice_id array iteration | `crates/rf-bridge/src/dpm_ffi.rs:94-100` | 1 h |
| 1.1.5 | Audit svih 47 `unsafe` blokova u rf-engine + 23 u rf-bridge | — | 2 h |

### 1.2 Event flow (Flutter)

| # | Problem | Lokacija |
|---|---|---|
| 1.2.1 | **Event Registry race** — dva paralelna sistema registracije (`EventRegistry` + `CompositeEventSystemProvider`) — silent audio dropout. CLAUDE.md warning line 40. | `lib/services/event_registry.dart` + `lib/providers/subsystems/composite_event_system_provider.dart` — konsolidovati na JEDAN path kroz `_syncEventToRegistry()` |
| 1.2.2 | Metering lock contention — `lufs_meter.try_write()` / `true_peak_meter.try_write()` silent skip tokom UI interakcije → metering gaps | `crates/rf-engine/src/playback.rs:7322-7335` — decouple metering od audio thread, separate readers |
| 1.2.3 | Cache TOCTOU — check→evict bez atomic CAS | `crates/rf-engine/src/playback.rs:1044-1055` — dedicated RwLock u background eviction thread |

### 1.3 Test pokrivenost UI

| # | Zadatak | Cilj |
|---|---|---|
| 1.3.1 | Widget tests za `engine_connected_layout.dart` (17,292 LOC) | min 30 integration interactions |
| 1.3.2 | Widget tests za `slot_lab_screen.dart` (15,215 LOC) | min 30 |
| 1.3.3 | Widget tests za `helix_screen.dart` (9,735 LOC) | min 30 |
| 1.3.4 | Gesture conflict detection test (820 GestureDetector instances — automatska detekcija arena collision-a) | pass under stress |
| 1.3.5 | Memory leak profiling (30+ min sessions, Ticker/OverlayEntry/Provider disposal) | zero leak |
| 1.3.6 | 60fps perf test pod 50+ channel load | frame drops < 1% |

### 1.4 HELIX stub tabovi (popuniti ili otkloniti)

| # | Super-tab / Sub-tab | Trenutno | Odluka |
|---|---|---|---|
| 1.4.1 | DSP → spatial | "Coming soon" placeholder | Popuniti sa HRTF + Atmos monitoring + HOA 3 controls |
| 1.4.2 | RTPC → sve 4 sub-tabs (curves, macros, dspBinding, debugger) | UI bez FFI binding | Wire real-time parametar curves kroz `rf-bridge/src/rtpc_ffi.rs` |
| 1.4.3 | CONTAINERS → metrics, timeline | UI-only | Rust backend za container synthesis |
| 1.4.4 | MUSIC → segments, stingers, transitions | Skeletal | Interactive music logic (layered, Wwise-style) |
| 1.4.5 | LOGIC → triggers, gate, emotion | Placeholderi | Behavior tree UI + rule editor |
| 1.4.6 | DAW CORTEX → awareness (7-dim) | Enum deklarisan, nema UI | Brisati ili implementirati |
| 1.4.7 | MONITOR → neuro, aiCopilot | AI stubs | Wire sa Faza 4 AI Copilot |

### 1.5 Audio kvalitet

| # | Zadatak | Lokacija | Effort |
|---|---|---|---|
| 1.5.1 | HRTF bilinear interpolation upgrade (BUG #35 trenutno IDW) | `crates/rf-dsp/src/spatial.rs:118-120` | 2 h |
| 1.5.2 | Plugin crash sandbox — VST3/AU/CLAP/LV2 izolovan u subprocess | `crates/rf-engine/src/plugin/` | 4 h |
| 1.5.3 | True Peak NEON implementacija (trenutno samo AVX2) | `crates/rf-dsp/src/metering_simd.rs` | 2 h |
| 1.5.4 | DSD polyphase resampling (TODO u `dsd/mod.rs:197`) | | 1 dan |

### 1.6 Build / CI

| # | Zadatak | Cilj |
|---|---|---|
| 1.6.1 | `cargo build --release --all` — 0 warnings | clean |
| 1.6.2 | `xcodebuild ... -configuration Release build` | success |
| 1.6.3 | `flutter analyze` — 0 errors | clean |
| 1.6.4 | `cargo test --workspace` — sve pass | 1873+ tests green |
| 1.6.5 | Full Build CI checkpoint (GitHub Action) | green badge |

---

## FAZA 2 — UX / Performance (kompaktnost + brzina imperativi)

### 2.1 Kompaktnost

| # | Zadatak | Zašto |
|---|---|---|
| 2.1.1 | HELIX dock jump-to: Cmd+K palette za skok na bilo koji od 110+ sub-tab statesa | sada 2-3 klika za sub-tab |
| 2.1.2 | SlotVoiceMixer — collapse-by-bus button (6 buseva, svaki collapsible) | 100+ channels trenutno linear scroll |
| 2.1.3 | Engine_connected_layout — 3-panel raspored collapsible (left/right toggle tabovi) | trenutno 3 monitora potrebna |
| 2.1.4 | Keyboard shortcut map overlay (`?` ili `Cmd+/`) | discoverability |
| 2.1.5 | Sub-tab nav shortcuts (1-0 + Q-U) | missing |
| 2.1.6 | Status bar height smanjiti na 22px (trenutno 28px) | više prostora za rad |
| 2.1.7 | HELIX Omnibar inline edit-in-place everywhere (project name, BPM, RTP, tier thresholds) | manje klikova |
| 2.1.8 | Slot preview: toggle fullscreen / 80% / 50% size (Escape cycles) | instant fokus |

### 2.2 Brzina

| # | Zadatak | Cilj |
|---|---|---|
| 2.2.1 | 60fps pod 130-voice live mix | Phase 10 orchestra fazom 10e-2 |
| 2.2.2 | OrbMixer Phase 10e-2 — 5s master ring buffer + WAV export | Problems Inbox replay <200ms |
| 2.2.3 | OrbMixer per-bus FFT isolate za ghost buffer >100 voices | zero frame drop |
| 2.2.4 | Lazy loading za 11 super-tabs × sub-tabs (memo + IndexedStack sa keepAlive=false za neaktivne) | <50ms tab switch |
| 2.2.5 | Waveform cache LRU invalidation (trenutno oversized images BUG #46) | stale waveforms |
| 2.2.6 | Timeline virtualization — samo visible clips render | 10000+ clips project |
| 2.2.7 | Impeller GPU compositing enable za macOS (Flutter 3.30+) | smoother scroll/pan |

### 2.3 Monolith refactor (održivost)

| # | Zadatak | Pre | Cilj |
|---|---|---|---|
| 2.3.1 | Split `engine_connected_layout.dart` | 17,292 LOC | 3 panela × ~2000 LOC |
| 2.3.2 | Split `slot_lab_screen.dart` | 15,215 LOC | Timeline + LowerZone + Overlay sekcije |
| 2.3.3 | Split `premium_slot_preview.dart` | 7,676 LOC | ReelStrip + SymbolOverlay + WinLine + AnticipationGlow painters |
| 2.3.4 | Split `helix_screen.dart` | 9,735 LOC | Omnibar + NeuralCanvas + Dock widgets |
| 2.3.5 | Extract lower zone sub-tab widgets u `widgets/lower_zone/slotlab/` | — | reuse |

### 2.4 Dead code eliminacija

| # | Zadatak | Lokacija |
|---|---|---|
| 2.4.1 | `ValidationErrorCategory.deprecated` ukloniti | `lib/models/validation_error.dart:67` |
| 2.4.2 | `_deprecated_slot_events` v4→v5 migration (posle >6 meseci na v5) | `lib/services/project_migrator.dart:594-604` |
| 2.4.3 | 3 obsolete DAW sub-tabs (video, cyc, ...) | placeholderi 20+ |
| 2.4.4 | `gdd_import_*` legacy format ~800 LOC | ako niko ne importuje GDD više |
| 2.4.5 | Old behavior tree format pre-v11 ~400 LOC | `providers/slot_lab/behavior_tree*` |

---

## FAZA 3 — Slot Machine Diferenciatori

### 3.1 IGT/Playa parity fixes (iz memorije)

| # | Zadatak | Status | Fajl(ovi) |
|---|---|---|---|
| 3.1.1 | **S1 Feature Wins završni momenti** — CortexEye verifikacija da FsSummary UI overlay triggeruje na FS exit + skip telemetrija log | commit `2b539a0e` postoji, verify nedostaje | `lib/models/stage_models.dart`, `lib/services/stage_audio_mapper.dart`, `crates/rf-stage/src/audio_naming.rs` |
| 3.1.2 | **S2 Splash → Slot animacija** (Boki eksplicitno tražio — profi, kinematska, reel spin-up intro, zlatni sjaj, simboli padaju, dramatski crescendo → tišina) | ⏳ | `lib/screens/splash_screen.dart`, `lib/screens/slot_lab_screen.dart` |
| 3.1.3 | **S3 Reel Loop + Reel Stop audio** — `sfx_reel_spin_r0..r5` (loop) i `sfx_reel_stop_r0..r5` (stinger) engine wire-up | ⏳ | `crates/rf-stage/src/audio_naming.rs`, `lib/services/stage_audio_mapper.dart`, `lib/screens/slot_lab_screen.dart` |
| 3.1.4 | **S4 Audio tab Helix lower zone** — ranije prijavljeno "ništa se ne prikazuje" | ⏳ | CortexEye snap → debug → fix |
| 3.1.5 | Podnaslovi podtabova razlikuju se od naslova | ⏳ | `lib/widgets/helix/helix_lower_zone.dart` |

### 3.2 OrbMixer

| # | Zadatak | Status | Fajl(ovi) |
|---|---|---|---|
| 3.2.1 | **O1** Phase 10e-2 Rust FFI 5s ring buffer + WAV export | ⏳ | `crates/rf-bridge/src/orb_mixer_ffi.rs`, `lib/providers/orb_mixer_provider.dart` |
| 3.2.2 | **O2** Per-bus FFT za precizniji masking + performance isolate >100 voices | ⏳ | `crates/rf-bridge/src/orb_mixer_ffi.rs`, `lib/widgets/slot_lab/orb_mixer_painter.dart` |
| 3.2.3 | **O3** Orb stabilnost — nestaje kada se menja kanal (fix state pop) | ⏳ | CortexEye watch orb kroz switch → state log → fix |
| 3.2.4 | Orb ghost trails 2s → ekspanzija na 10s + dupli-tap = revert (Part V.3 time travel seed) | ⏳ | `lib/widgets/slot_lab/orb_mixer.dart` |

### 3.3 NeuralBindOrb

| # | Zadatak | Status | Fajl |
|---|---|---|---|
| 3.3.1 | **N1** Phase 2 ghost slot indikatori — stage-ovi bez bindinga kao ghost u orbu | ⏳ | `lib/widgets/slot_lab/neural_bind_orb.dart` |
| 3.3.2 | Snap-to-grid visual feedback u drag (trenutno nevidljiv) | ⏳ | `lib/widgets/slot_lab/neural_bind_orb.dart` |

### 3.4 Regulatory (Compliance live)

| # | Zadatak | Cilj |
|---|---|---|
| 3.4.1 | Live compliance meter u omnibaru (UKGC / MGA / SE / NV / NJ traffic lights) | dok autoruje |
| 3.4.2 | Inline tooltips — pravilo koje violira + one-click auto-fix | kontekstualno |
| 3.4.3 | LDW guard u realnom vremenu — celebration duration cap kad win==bet | transparent |
| 3.4.4 | Near-miss quota tracker — "2.1% near-miss, ceiling 3%" | live UI |
| 3.4.5 | Compliance manifest button — jurisdiction picker + signed export | one-click |

### 3.5 Atmos + spatial catch-up

| # | Zadatak | Effort |
|---|---|---|
| 3.5.1 | Atmos object export MVP (bar jedan path) | 3 nedelje |
| 3.5.2 | HOA 3rd–5th order authoring | 1 mesec |
| 3.5.3 | Personalized HRTF via HRTFformer / graph NN | 1 mesec |

---

## FAZA 4 — AI Copilot (Leapfrog)

> Nijedan konkurent ovo nema. Prozor ~12-18 meseci pre Wwise odgovora.

### 4.1 Copilot infrastruktura

| # | Zadatak | Tehn | Effort |
|---|---|---|---|
| 4.1.1 | `rf-copilot` crate sa `Action` trait (svaka sugestija reversibilna) | Rust | 2 nedelje |
| 4.1.2 | Local LLM integracija (Llama 3 8B ili Phi-4) via Metal MPSGraph | MPS | 1 mesec |
| 4.1.3 | Isolate za copilot, FFI kroz `rf-bridge/src/copilot_ffi.rs` | | 1 nedelja |
| 4.1.4 | Dart `CopilotService` + `CopilotPanel` widget | Flutter | 2 nedelje |

### 4.2 Features

| # | Zadatak | Input | Output |
|---|---|---|---|
| 4.2.1 | Generative mix ("make rollup 15% more euphoric") | voice/text | param delta preview branch |
| 4.2.2 | Predictive automation (after 5-10 manual moves) | gesture history | ghost-curve in timeline |
| 4.2.3 | Voice commands ("solo voice bus", "audition next win tier", "export MGA manifest") | WhisperKit local | direct action |
| 4.2.4 | Error prevention (LDW, near-miss, celebration LUFS) | continuous validators | flag before user hears |

### 4.3 Persistent memory (Part V.4)

| # | Zadatak | Skladište |
|---|---|---|
| 4.3.1 | `~/.fluxforge/memory.db` SQLite event log | local only |
| 4.3.2 | Embedding model (sentence-transformers via tract) | Rust |
| 4.3.3 | Style fingerprint export/import `.style` file | portable |
| 4.3.4 | Popuniti `rf-neuro` stubs sa memory substrate | Rust crate |

### 4.4 Predictive Event Routing (Part V.10)

| # | Zadatak | Osnova |
|---|---|---|
| 4.4.1 | Classifier audio features → Stage label | Sonic DNA Layer 2/3 postoji |
| 4.4.2 | Drag file → 85% confidence "reel_stop for bus SFX" | isolate query |
| 4.4.3 | Gap detection — "12 files match FREE_SPIN_START, top 3 suggestion" | list |
| 4.4.4 | Auto-fill proposals (one-click) | provider surface |
| 4.4.5 | Learning from rejections (feed V.4 memory) | cross-session |

---

## FAZA 5 — Generativni layer

### 5.1 Generative Slot Scoring (Part V.6)

| # | Zadatak | Tehn |
|---|---|---|
| 5.1.1 | `rf-generative` crate, ONNX via tract | Rust |
| 5.1.2 | Stable Audio Open Small local inference (30s u 8s na M3) | ONNX |
| 5.1.3 | `generate_stage_audio(stage, style, duration)` FFI | `sam_ffi.rs` |
| 5.1.4 | "GEN" sub-tab u MUSIC ili MONITOR super-tab | UI |
| 5.1.5 | Emotional arc timeline input (tension → excitement → euphoria) | UI |
| 5.1.6 | Style transfer iz reference slota | Model |
| 5.1.7 | Variation generation (5 alternate BIG_WIN stings) | 1 klik |
| 5.1.8 | Auto-compliance validator na generisan audio | `rf-slot-builder` |

### 5.2 Generative Voice / Foley (Part V.9)

| # | Zadatak |
|---|---|
| 5.2.1 | Text-to-SFX ("coin drop, wet marble, bright" → 3s WAV preview) |
| 5.2.2 | Voice cloning za VO draftove (30s sample → generate scripted lines) |
| 5.2.3 | Variation generation (10 pitched alternatives za random container) |
| 5.2.4 | AudioSeal watermark na sve generisano (provenance audit) |

### 5.3 Neural stem separation

| # | Zadatak | Model |
|---|---|---|
| 5.3.1 | Demucs v4 (HT-Demucs) local inference | ONNX via tract |
| 5.3.2 | UI: "extract stems from reference" u DAW PROCESS tab | Flutter |
| 5.3.3 | Kim Vocal 2 za vocal-only extract | alternate model |

---

## FAZA 6 — GPU DSP + spatial pro

### 6.1 GPU compute

| # | Zadatak | Tehnologija |
|---|---|---|
| 6.1.1 | wgpu compute shaderi za partitioned convolution reverb (IR > 2s, 10-50× speed-up) | WebGPU/wgpu |
| 6.1.2 | Metal Performance Shaders za neural inference (copilot + generative) | MPSGraph |
| 6.1.3 | HOA encode/decode na GPU | wgpu |
| 6.1.4 | Fragment shaders za real-time spectrum + heatmap (sada CPU) | Flutter .frag |

### 6.2 End-to-end neural mastering

| # | Zadatak |
|---|---|
| 6.2.1 | Ozone-class quality chain (multiband comp + limiter + EQ + satur) |
| 6.2.2 | Local inference |
| 6.2.3 | Per-jurisdiction LUFS target (UKGC -16 LUFS, MGA -18 LUFS, ...) |

---

## FAZA 7 — Collab + visionOS + Orb Ecosystem

### 7.1 Multi-studio Collab (Part V.7)

| # | Zadatak | Tehn |
|---|---|---|
| 7.1.1 | `rf-crdt` crate — Yjs (wasm) ili Automerge 2.0 (native Rust) | CRDT |
| 7.1.2 | WebRTC transport (Pion ili Flutter plugin) | audio stream + data |
| 7.1.3 | `services/collaboration_service.dart` | Flutter |
| 7.1.4 | Presence indicators na svaki control (cursor, selection) | UI |
| 7.1.5 | Voice chat integracija (LiveKit) | audio |
| 7.1.6 | Roles + permissions (composer / sound designer / QA read-only) | auth |
| 7.1.7 | Comment threads na timeline regione | UI |

### 7.2 Gaze Mix on visionOS (Part V.2)

| # | Zadatak | Tehn |
|---|---|---|
| 7.2.1 | visionOS companion app (Flutter ili SwiftUI) | Xcode |
| 7.2.2 | ARKit eye tracking → gaze coordinates 90Hz | visionOS 2 |
| 7.2.3 | Pinch + drag gesture → volume, pan, width | gesture |
| 7.2.4 | WebRTC ili CRDT channel ka macOS master | transport |
| 7.2.5 | Voice command "solo voice bus" hands-free | WhisperKit |

### 7.3 Orb Ecosystem (Part V.5)

| # | Zadatak |
|---|---|
| 7.3.1 | Refaktor `OrbMixerProvider` → generic `OrbProvider<T>` (T = voice / bus / DSP / container / music) |
| 7.3.2 | `OrbContainerWidget` host any `OrbProvider<T>` |
| 7.3.3 | `OrbGestureService` — centralizovana logika (click/double/long-press) |
| 7.3.4 | Nested orbs — master orb sadrži 6 bus orbova, svaki sadrži voice orbove |
| 7.3.5 | Dock / Float / Merge / Split gestures |
| 7.3.6 | Drag voice orb u bus orb = re-route |

### 7.4 Time-Travel Authoring (Part V.3)

| # | Zadatak |
|---|---|
| 7.4.1 | Ghost trails na orbu (10s fade-out history) |
| 7.4.2 | Session scrub ring — spoljni prsten orba zamenjuje 30s mix-a |
| 7.4.3 | Git-style branches (named save state, branch tree minimap) |
| 7.4.4 | "What did I hear 10 minutes ago?" — mix params rewind, audio replay kroz snapshot |
| 7.4.5 | Audio ring buffer 5min (extension od Phase 10e-2 5s) |
| 7.4.6 | Proširiti `rf-state` za BranchId + persistent tree |

---

## FAZA 8 — Platform Leadership

| # | Zadatak | Outcome |
|---|---|---|
| 8.1 | **Open-source `rf-stage` taxonomy** + SDK za third-party integraciju | ecosystem gravity |
| 8.2 | Plugin SDK — third-party UI paneli, FX, AI modeli | ecosystem pull |
| 8.3 | Marketplace za style fingerprint + generative presete + compliance templates | revenue + lock-in |
| 8.4 | Education platform — embedded tutorials, AI mentor, certifikacija | talent pipeline |
| 8.5 | Regulatory partnerships — pre-validated audio templates per jurisdiction | moat deepening |
| 8.6 | **FluxForge Cloud** — optional cloud sync, collab, version history, compliance archive | SaaS layer |
| 8.7 | Research partnership (university / lab) na perceptual audio + generative slot | frontier R&D |

---

## DAW — Dodatne stavke (Boki će dopunjavati)

> Ostavljeno mesto za nove DAW-specifične poboljšanje zahteve.

- [ ] _(popuniti posle pregleda)_
- [ ] _(popuniti)_

---

## HELIX — Dodatne stavke (Boki će dopunjavati)

> Ostavljeno mesto za nove HELIX-specifične poboljšanje zahteve.

- [ ] _(popuniti)_
- [ ] _(popuniti)_

---

## OPERATIVA & STRATEŠKO (kako radimo, kako se predstavljamo, kako se branimo)

> 10 preporuka koje nisu featuri nego procesi, strateški potezi, micro-UX i risk mitigation. Sve odobreno za TODO.

### Proces razvoja

| # | Stavka | Detalj |
|---|---|---|
| OP1 | **Boki kao patient zero customer** | Svaka Bokijeva live sesija snimljena (CortexEye Vision postoji). Svaki frustration moment (long pause, pogrešan klik, glasna reakcija) = automatski backlog item. Razvoj vođen tvojim stvarnim trenjem, ne pretpostavkom. |
| OP2 | **Release cadence — 2-nedeljni sprintovi sa tematskim imenima** | `release_005_atmos`, `release_006_copilot`, `release_007_collab`. Predvidljiv tempo. Partneri planiraju oko nas. Tema = jedan glavni differentiator po sprintu. |

### Strateški potezi

| # | Stavka | Detalj |
|---|---|---|
| OP3 | **Akademske partnership** | IRCAM (Pariz, audio research), Stanford CCRMA, McGill MIRA, MIT CSAIL audio. Internship pipeline. Istraživački radovi → FluxForge featuri kroz 3-6 mesečne projekte. Free R&D, talent funnel. |
| OP4 | **Open Stage Taxonomy konzorcijum** | Pre nego konkurent forkne, osnuj nezavisan governance body koji vlada `rf-stage` taksonomijom (kao Khronos za grafiku, MMA za MIDI). Wwise i FMOD moraju da slušaju nas, ne obrnuto. Drives industry adoption. |

### UX patterni (mali ali strateški)

| # | Stavka | Detalj |
|---|---|---|
| OP5 | **Inline voice memos** | Pritisneš ikonicu pored bilo kog elementa (track, voice, stage, container) → snimaš 30s voice memo. Sound designer ostavlja white-board notu vezanu za konkretan stage. Niko od konkurenata ovo nema. Jednostavno za implementaciju, masivan UX boost. |
| OP6 | **Selection memory — Cmd+1…9 / Cmd+Shift+1…9** | Photoshop layer comps za audio. Cmd+1 sačuva trenutni view (track + zoom + selected tab + lower zone state) na slot 1; Cmd+Shift+1 vraća. 30+ minuta authoring postaje 30 sekundi recall-a. Crucial za workflow brzinu. |
| OP7 | **Right-click "Explain this"** | Corti objašnjava bilo koji parameter / feature kontekstualno. AI tooltip 2.0. Onboarding bez tutorijala. Onboarding novog tima u studio = nekoliko dana umesto nedelja. Reuses Faza 4 AI Copilot infrastrukturu. |

### Risk mitigation

| # | Stavka | Detalj |
|---|---|---|
| OP8 | **Wwise + FMOD interop layer** | `rf-bridge` može da exportuje u Wwise SoundBank i FMOD bank. Pozicija: "FluxForge je tvoj authoring tool, koristi bilo koji runtime". Studio koji koristi Wwise nema razloga da te odbije — koegzistuješ, ne zameniš. Najefikasnija obrana od pretnje #1 i #2. |

### Operativno

| # | Stavka | Detalj |
|---|---|---|
| OP9 | **Anonymous opt-in telemetry** | Koje funkcije se najčešće koriste, gde korisnik zaglavi (long pause + abandon), šta zatraži pa ne nađe (search query bez rezultata). Data-driven roadmap umesto pretpostavki. UKGC-friendly ako je opt-in + anonimno + agregirano. |

### Brand / pozicioniranje

| # | Stavka | Detalj |
|---|---|---|
| OP10 | **Quarterly "Sound of Slots" report** | Agregirana anonymous statistika iz svih FluxForge projekata: najčešći stages per market, LUFS distribucija, popularne bus konfiguracije, win-tier ratio. Industry benchmark — konkurenti se referenciraju **na nas**. Free press svake 3 meseca. Postavlja FluxForge kao autoritet, ne učesnika. |

---

## MOONSHOTS — Blue-sky inovacije (sve što može biti bolje nego što jeste)

> Boki: "od tebe mi treba sve futurističko i što može da bude bolje nego što jeste".
> Ovo nije roadmap — ovo je open-ended istraživački kanon. Sve napisano je tehnički zamislivo do 2030. Implementacija po prilici, partnerima, prilikama. **Ništa nije preskočeno.**

### M.1 Audio engine inovacije

| # | Stavka | Detalj |
|---|---|---|
| M1.1 | **Differentiable audio engine** | Ceo `rf-engine` postaje differentiable computational graph. Definiš target ("treba da zvuči ovako") + reference audio → engine samosebe trenira da pristigne tu. Ozone-style mastering, ali za mix params. |
| M1.2 | **Neural codec native storage** | Interno sve audio kao DAC/Encodec embeddings (6-12 kbps). Lossless re-encode na export. 50-100× manje storage, instant load, semantic search po sound bibliotekama. |
| M1.3 | **Hybrid CPU+GPU+NPU automatic dispatch** | DSP graf zna gde da pošalje koju operaciju (CPU za simple biquad, GPU za convolution, NPU za neural inference). Auto-balance po platformi. |
| M1.4 | **Time-varying impulse response reverb** | Reverb IR se menja sa game state-om real-time. Bonus mode = bigger room. Free spins = celestial. Bez disclosure latency. |
| M1.5 | **Microsound granular at sample level** | Per-sample granularni shaping ispod sample rate-a. Texture morphing impossible u trenutnoj DSP-u. |
| M1.6 | **Wave function physics modeling** | Slot symbol audio modeluje se kao quantum superposition; "observe" event kolapsuje state. Eksperimentalno. |
| M1.7 | **Sub-millisecond latency mode** | Apple Audio Workgroups + Vulkan compute = <1ms voice→output latency. Headphone live monitoring uživo. |

### M.2 UX paradigme (post-mouse era)

| # | Stavka | Detalj |
|---|---|---|
| M2.1 | **3D spatial UI on Vision Pro** | Orbi u stvarnom 3D prostoru. Mix isfront tebe, EQ levo, automation desno. Telo postaje navigation. |
| M2.2 | **Predictive disclosure** | UI se sažima/proširuje na osnovu šta korisnik **sledeće** radi (LSTM nad gesture history). Kad si na rollup mix-u, automation lane se sam expand-uje. |
| M2.3 | **Touchless gesture** (Leap Motion v2 / camera) | Pomeraš ruku iznad laptopa, knob se okreće. Bez dodira. |
| M2.4 | **Emotional state UI** | Kamera čita Bokijevu mimiku → frustration detected → UI density se smanjuje, Corti predlaže pauzu ili "želiš da preuzmem ovaj rollup?". |
| M2.5 | **Sound-driven UI** | Pevaš melody, sistem prepoznaje, mapira na MIDI clip, postavlja u trenutni stage. Humming = audio sketch input. |
| M2.6 | **Brain-computer interface (Neuralink class)** | Misli komanda → slot reaguje. Eksperimentalno, ne prioritet, ali ostavljeno za 2028+ kad BCI consumer-grade. |
| M2.7 | **Spatial computing keyboard** | Virtuelna tastatura iznad bilo kog uređaja kroz visionOS/AR Glasses. Authoring bez fizičkog laptopa. |
| M2.8 | **Adaptive density per-user** | Junior sound designer dobija pojednostavljen UI; senior dobija sve. Auto-detection po behavioral signature-u. |
| M2.9 | **Single-key universal action** | "Make better" dugme — Corti analizira kontekst i radi 1 najbitniju izmenu. Lazy day mode. |

### M.3 AI infrastruktura

| # | Stavka | Detalj |
|---|---|---|
| M3.1 | **Federated learning** | Boki-jeve mix preferences kombinovane anonimno sa drugim FluxForge korisnicima. Sve corisniki postaju pametniji bez compromise privatnosti. |
| M3.2 | **Agentic LLM execution** | Corti može da pokrene sub-agente: "ti optimizuj voice bus, ti kreiraj 3 variante big-win sting-a, ti validiraj UKGC compliance, vrati mi rezime za 30 minuta". |
| M3.3 | **Multi-modal copilot** | Sluša audio + vidi screen + razume tekst → kombinovano razumevanje. "Ovaj zvuk levo na ekranu, smanji ga 2dB" radi bez specifikacije. |
| M3.4 | **Explainable AI** | Svaka sugestija ima causal chain: "predlažem -3dB na 1.2kHz jer ima peak na 2.5s spina, koincidentan sa near-miss audio cue, što po UKGC test guideline-u može flagovati nepošten signaling". |
| M3.5 | **Adversarial training u kompoziciji** | Jedan Corti pravi mix, drugi ga kritikuje (player umoran, regulator skeptic, igrač neopiranje). Iterativno do nirvane. |
| M3.6 | **Long-context industry memory** | Cela slot audio istorija (svaki popularan slot 2010-2030) u persistent memoriji za referencu. "Šta bi MGM/IGT uradili?" |
| M3.7 | **Self-improving DSP** | DSP algoritmi koje Corti piše/optimizuje sam. Custom EQ topology za specific use case. |
| M3.8 | **Continuous-learning watcher** | Corti gleda Bokija svaki put; svake nedelje šalje "evo 3 stvari koje sam naučio od tebe ove nedelje". |

### M.4 Slot mehanike (audio kao prvoklasna mehanika)

| # | Stavka | Detalj |
|---|---|---|
| M4.1 | **Adaptive volatility** | Slot menja volatility profil na osnovu igračevog state-a (samo gde regulisano dozvoljava). Audio postaje signal koji vodi modulaciju. |
| M4.2 | **Audio-driven RTP** | Soundscape utiče na win frequency u realnom vremenu. Domena gambling research. |
| M4.3 | **Generative paytables** | Corti generiše balanced paytable za zadati RTP target + volatility profile + audio mood. |
| M4.4 | **Cross-game audio motifs** | Shared melodic theme između slot-ova istog studio-a. Brand recognition kao Hollywood franchise. |
| M4.5 | **Time-of-day aware slots** | Različiti audio mix za jutro / popodne / veče. Smiren ujutro, energičan uveče. |
| M4.6 | **Quantum slot mode (eksperimentalno)** | Superpozicija outcome-a; igračeva opservacija kolapsuje. Teoretski model za novu generaciju mehanike. |
| M4.7 | **Synesthesia slot** | Vizuelni feedback (boja simbola, emisija svetlosti) sinhronizovan sa audio nota — ton C = plavo, F# = ljubičasto. |
| M4.8 | **Player-personalized mix** | Svaki igrač ima blago drugačiji audio mix po ML preferences. Privacy-preserving. |

### M.5 Compliance / regulatory budućnost

| # | Stavka | Detalj |
|---|---|---|
| M5.1 | **Explainable RTP** | Svaki spin ima math + audio attribution chain za regulator audit. Why this RTP, why this audio. |
| M5.2 | **Real-time jurisdiction detection** | Geo-IP + cabinet ID → automatic compliance switch (UKGC, MGA, NV, NJ, ON). |
| M5.3 | **Self-mutating compliance** | Kad regulacija changes, slot auto-adjusts (sa human approval gate). |
| M5.4 | **Zero-knowledge player privacy** | Telemetry koja ne otkriva player ID nikom — homomorphic aggregation. |
| M5.5 | **Regulator co-pilot** | Regulator ima view-only Corti sa explanation. "Ovaj slot u ovom mode-u radi ovo, evo proof." |
| M5.6 | **Anti-money-laundering audio fingerprint** | Audio metadata pomaže AML detection (cabinet usage patterns). |
| M5.7 | **Quantum-safe manifest** | Post-quantum signature na svaki compliance manifest (CRYSTALS-Dilithium). Survives 2030+ quantum break. |

### M.6 Production / workflow budućnost

| # | Stavka | Detalj |
|---|---|---|
| M6.1 | **Live remote sound design** | Boki šeta sa AirPods Pro + iPhone, podešava mix glasom dok je u kafiću. WebRTC streaming celog projekta. |
| M6.2 | **Music synchronization to math** | Auto-tune base bed tempo na hit frequency / volatility. Tempo = 120 ako je high vol, 84 ako je low vol. |
| M6.3 | **Polyphonic timelines** | Više simultanih timelines koji se sinhronizuju (slot + bonus + pick + jackpot). Bez dialog-a "switch context". |
| M6.4 | **Project DNA** | Svaki projekat ima cryptographic hash istorije svake odluke. "Ovaj zvuk nastao je iz [genealogy chain] commits, autori X, Y, Z." |
| M6.5 | **Time-machine debugging** | "U kom commitu se ovaj zvuk loše ponašao?" — git bisect za audio. |
| M6.6 | **Intent merging u kolaboraciji** | Ne samo CRDT merge, nego semantičko merging "ti hoćeš punchier, ja hoćeš smoother → kompromis". |
| M6.7 | **A/V sync engine** | Automatska sinhronizacija audio sa svakim video element u slotu. Frame-accurate by default. |
| M6.8 | **Hot reload za sve** | Svaki kod change (Rust + Dart + DSP) — instant reload bez restart-a. State persisted. |

### M.7 Distribution / runtime

| # | Stavka | Detalj |
|---|---|---|
| M7.1 | **WebAssembly slot engine** | Slot kao `.wasm` modul, runs anywhere (browser, mobile, embedded) bez native build. |
| M7.2 | **Edge inference** | Neural copilot deployed na CDN edge — Cloudflare Workers AI. Sub-100ms suggestion latency globally. |
| M7.3 | **P2P self-distribution** | Slot ima embedded P2P delivery (BitTorrent layer). Cabinet pulls bandwidth-optimized. |
| M7.4 | **Lite version u browseru** | Preview slot u Chrome bez instalacije. Sales pitch link click → live preview u 5 sekundi. |
| M7.5 | **VR slot machine experience** | Slot kao VR scene, ne flat UI. Quest 3 / Vision Pro / PSVR2. |
| M7.6 | **Smart TV native** | Tizen / webOS app za TV slot. Cabinet on TV setup. |
| M7.7 | **Dolby Atmos for Home** | Slot u Dolby Atmos format za soundbar / AVR / home theater playback. |

### M.8 Research collaboration

| # | Stavka | Detalj |
|---|---|---|
| M8.1 | **Open dataset za slot audio research** | Anonimno otpakirana FluxForge data za istraživače. Free corpus → academic citations → reputational moat. |
| M8.2 | **Slot Audio Olympics** | Yearly challenge sa scoring leaderboard. Najbolji studio audio dobija nagradu + press. |
| M8.3 | **Cognitive science partnership** | Measurable engagement metrics (HRV, EEG, eye tracking). Da li audio zaista vodi engagement? Empirijski. |
| M8.4 | **Synthetic player** | Psihometrijski model igrača koji testira novi slot pre deployment. "Ovaj je previše agresivan za novog igrača." |
| M8.5 | **Audio-cognition paper publishing** | FluxForge tim objavljuje 2-3 paper-a godišnje (DAFx, AES, ICAD). Akademski autoritet. |

### M.9 Hardware-level moonshots

| # | Stavka | Detalj |
|---|---|---|
| M9.1 | **Holographic slot machine** | 3D pixel space (Looking Glass / autostereoscopic display). Simboli lebde u prostoru. |
| M9.2 | **Haptic vest** | Bass pumping kroz haptic vest (bHaptics, Subpac). Big win = celo telo oseti. |
| M9.3 | **Custom FluxForge hardware controller** | Fizički knob/fader kontroler dizajniran za FluxForge workflow. Kao Push za Ableton. |
| M9.4 | **AirPods Pro 3 head-tracking compose** | Head tilt = pan, head nod = volume confirm, head shake = undo. Zero-keyboard authoring. |
| M9.5 | **Quantum random number** | True quantum RNG za slot mehaniku (IBM Q cloud access). Provably random. |
| M9.6 | **Neural processor co-design** | Ako stignemo do skale — partnerstvo sa silicon vendor-om za FluxForge-optimized NPU. |

### M.10 Blue-sky / 2030+

| # | Stavka | Detalj |
|---|---|---|
| M10.1 | **AGI sound director** | Do 2030, AI radi ceo slot audio sam, čovek samo daje creative brief. FluxForge postaje hiring platform za AI sound directors. |
| M10.2 | **Brain-state-aware mixing** | Biofeedback od igrača utiče na audio (gde regulisano). EEG → mood detection → mix adapt. |
| M10.3 | **Memory-augmented slot** | Slot koji se sećа prošlih spinova svakog igrača i evoluira (privacy-preserving). |
| M10.4 | **Ambient slot — never-loop** | Slot bez ponavljanja audio-a u celom svom životnom veku. Generativna struktura. |
| M10.5 | **Cross-modal generation** | Daš sliku → Corti generiše audio. Daš melody → Corti generiše vizual. |
| M10.6 | **Self-replicating slot studio** | Studio kao kontejner — Corti može da klonira "naš stil rada" i predloži novi slot bez ljudske intervencije. |
| M10.7 | **Speech-of-the-world voice library** | Svaki language u svetu, svaki dialect, svaki ton — gen-on-demand kroz ElevenLabs evolution. |
| M10.8 | **AI Composer Twin** | Digital twin tvog kompozitora — još je živ, ali Corti uči od njega tako da kad ode, zna da održi style. |
| M10.9 | **Post-DAW paradigm** | DAW kao koncept iz 2020-ih nestaje. FluxForge prelazi u "intent-based audio environment" — opisuješ šta hoćeš, sve se desi. |
| M10.10 | **FluxForge OS** | Cela OS layer dizajnirana za audio professionals. Apple Logic + Ableton se gase. |

---

## Futurističko (ideje bez tajm lajna)

> Sve ideje koje su iznad standardnog roadmap-a. Boki je odobrio "sve" → ovde stoje kao kandidati za buduće faze ili kao istraživački pravci.

### Audio + Mix

- **Neural tension arc** — model koji mapira game-theory tension → target LUFS / spektralna kriva real-time. Slot ima emocionalni luk koji se autom prati.
- **Spectral gene editor** — "pomeri bass harmonics +3dB samo pri rollup-u" kroz manipulaciju latent space-a neural reverb-a. Bez parametarskih krivulja, direktno na neural model kao DNA sekvenca.
- **Haptic mixing** (Wacom + Force Touch) — osetiš kad knob stigne do target-a, kad LUFS pređe gate, kad solo prelazi.
- **Voice authoring hands-free** — ceo authoring flow glasom (dictate + commands). Korisnik ne mora ni da gleda u ekran.
- **Procedural ambient bed** — never-loop background koji se generiše real-time iz semantic description-a ("Mediterranean coastal village, sunset, light wind") → 4h jedinstvenog ambijenta bez ponavljanja.
- **Foley sandbox sa fizikom** — fizički simulator (ball drop, water splash, glass shatter) — iz fizičkih parametara generišeš realistic SFX. Niko ne mora da snima foley za prototype.

### Slot specifično

- **Reelovi kao interaktivni audio kontroleri** — svaka pozicija na reelu = touchzone za audio asset. Reel postaje step-sequencer ili parameter modulator. Slot dizajner može da koristi sam reel UI kao audio canvas (rešenje za tvoje pitanje "kako iskoristiti reelove da ne stoje bezveze").
- **AI Demo Reel generator** — daš slot, AI uzme best moments + applause + voice-over → 30s promo audio za sales pitch. Boki ide na sajam, ima 5 demo-a istog dana.

### QA + testing

- **AI regression tester** — Corti igra 10,000 spinova preko noći i prijavljuje audio anomalije koje ljudski QA ne bi nikad uhvatio (habituacija, fatigue, masking u win konstelacijama, near-miss iznad limita).
- **Live Wear Test** — Corti glumi "umorenog igrača" i meri kada audio prelazi u "iritantno" posle 100/500/1000 spinova. Slot mašine žive od dugih sesija; audio mora da izdrži.
- **Real-time A/B u produkciji** — produkcijski slot emituje 2 mix varijante, prikuplja player retention metrike, automatski bira winner. Audio postaje data-driven posle launch-a.

### AI + Memory

- **Cross-project style learn** — Corti prepoznaje "ovo zvuči kao Wrath of Olympus arc" i predlaže pattern preko više slot projekata.
- **Personalized spatial HRTF per-user** — kamera snimak uha → ML generiše individual HRTF dataset (Apple radi to za AirPods Pro).

### Ekosistem + monetizacija

- **Style fingerprint marketplace** — kompozitori prodaju svoj `.style` potpis (iz V.4 persistent memory). Kupac dobija auto-mix u tom stilu. Ekosistem revenue za studio.
- **Compositions-as-code** — slot kao `.ts` ili `.py` skript umesto JSON. Git diffable, peer-review-able, type-safe.

### Compliance + budućnost

- **Compliance as smart contract** — regulator verifikuje cryptographic proof bez pristupa projektu. Cryptographic manifest signed with private key.
- **Quantum-safe compliance audit trail** — post-quantum signature na svaku manifest (CRYSTALS-Dilithium, Falcon). Manifest preživi i nakon kvantnog probojа.

---

## GOTOVO (arhiva)

| Datum | Stavka | Commit |
|---|---|---|
| 2026-04-24 | FLUX_MASTER_VISION_2026 — total-system audit + 5yr roadmap | `ecbb87c2` |
| 2026-04-24 | Orb out-of-card + voice mixer focus-solo + detail editor + radial menu + CortexEye `/eye/voice*` | `830d9cb1` |
| 2026-04-24 | Casino Vault brand palette (5 fajlova) | `2917ae33` |
| 2026-04-24 | FsSummary + UiSkipPress stages + skip telemetry | `2b539a0e` |
| 2026-04-24 | Scene transition early-dismiss | `893c9c9d` |
| 2026-04-24 | AnticipationConfig wire-up (sekvencijalna anticipacija kao IGT) | `e7bca3a8` |
| 2026-04-22 | Slot Flow IGT Parity — Talas 1/2/3 | `1a3b2af7` `3b563438` `47d18a27` |
| 2026-04-22 | OrbMixer Phase 6-10e (9 commits, 2,153 LOC) | višestruki |
| 2026-04-22 | Sonic DNA Classifier Layer 2+3 + FFI + Dart modeli | |
| 2026-04-22 | CortexEye automation infrastruktura | |
| 2026-04-21 | 84/84 QA bagova rešeno | |
| 2026-04-21 | HELIX Auto-Bind QA + Redesign | |
| 2026-04-21 | NeuralBindOrb instant binding | |
| 2026-04-21 | CORTEX Organism refaktor | |

---

## ARHITEKTURA — ključni fajlovi

**Flutter screens:**
- `lib/screens/launcher_screen.dart` (1,144 LOC)
- `lib/screens/splash_screen.dart` (515 LOC)
- `lib/screens/welcome_screen.dart` (597 LOC)
- `lib/screens/daw_hub_screen.dart` (1,037 LOC)
- `lib/screens/engine_connected_layout.dart` (**17,292 LOC** monolith)
- `lib/screens/slot_lab_screen.dart` (**15,215 LOC** monolith)
- `lib/screens/helix_screen.dart` (9,735 LOC)

**SlotLab widgets:**
- `lib/widgets/slot_lab/premium_slot_preview.dart` (7,676 LOC)
- `lib/widgets/slot_lab/slot_voice_mixer.dart` (2,585 LOC)
- `lib/widgets/slot_lab/slotlab_bus_mixer.dart` (933 LOC)
- `lib/widgets/slot_lab/live_play_orb_overlay.dart` (1,174 LOC)
- `lib/widgets/slot_lab/orb_mixer.dart` (534 LOC)
- `lib/widgets/slot_lab/orb_mixer_painter.dart`
- `lib/widgets/slot_lab/neural_bind_orb.dart` (1,340 LOC)
- `lib/widgets/slot_lab/game_flow_overlay.dart` (2,344 LOC)

**Providers:**
- `lib/providers/slot_lab/slot_voice_mixer_provider.dart`
- `lib/providers/orb_mixer_provider.dart`
- `lib/providers/slot_lab/game_flow_provider.dart`
- `lib/providers/subsystems/composite_event_system_provider.dart`

**Services:**
- `lib/services/event_registry.dart`
- `lib/services/stage_audio_mapper.dart`
- `lib/services/cortex_eye_server.dart`

**Lower zone:**
- `lib/widgets/lower_zone/lower_zone_types.dart` (HELIX taxonomy def)
- `lib/widgets/lower_zone/slotlab_lower_zone_widget.dart` (5,338 LOC)

**Theme:**
- `lib/theme/fluxforge_theme.dart` (Casino Vault palette)

**Rust core (48 crates, ~259k LOC):**
- `crates/rf-engine/src/playback.rs` (7,500+ LOC — audio thread entry)
- `crates/rf-dsp/` (eq, dynamics, reverb, delay, spatial, convolution, timestretch)
- `crates/rf-stage/src/{event,stage,timing,trace,audio_naming,taxonomy}.rs`
- `crates/rf-slot-lab/src/{engine,engine_v2}.rs` + `parser/par.rs`
- `crates/rf-bridge/src/*_ffi.rs` (67 FFI files)
- `crates/rf-aurexis/` (SAM)
- `crates/rf-slot-builder/` (compliance)
- `crates/rf-state/` (history / snapshots)
- `crates/rf-neuro/` (stub — popuniti u Fazi 4.3)

---

## REDOSLED IZVRŠAVANJA (default, bez Boki override-a)

```
┌─ FAZA 0  [odmah]     Commit-verify tekući rad
├─ FAZA 1  [0-4 ned]   P0 blokirajuće — FFI safety, event race, widget tests, HELIX stubs
├─ FAZA 2  [2-6 ned]   UX kompaktnost + brzina + monolith refactor
├─ FAZA 3  [6-12 ned]  Slot diferencijatori — S1-S4, O1-O3, N1, compliance, atmos
├─ FAZA 4  [3-6 mes]   AI Copilot — LLM local, predictive routing, persistent memory
├─ FAZA 5  [6-9 mes]   Generativni layer — slot scoring, voice/foley, stem separation
├─ FAZA 6  [9-12 mes]  GPU DSP + end-to-end neural mastering
├─ FAZA 7  [12-18 mes] Collab + visionOS gaze + orb ecosystem + time-travel
└─ FAZA 8  [18+ mes]   Platform leadership — SDK, marketplace, cloud, partnerships
```

Paralelizam: Faze 1+2 idu uvek zajedno. Faza 3 može paralelno sa krajem Faze 1. Faze 4-5 dele `rf-generative` / `rf-copilot` infrastrukturu. Faza 6 može rano da krene ako se nađe GPU-specific low-hanging fruit.

---

**Reference:** `FLUX_MASTER_VISION_2026.md` — svaka stavka iz ovog TODO-a mapira se na sekciju Vision dokumenta. Prioritete menja Boki.
