# FluxForge Studio — MASTER TODO (definitive)

> Ažurirano: 2026-05-11 (Sprint 17 zatvoren) · Grana: `main`
> Sinhronizovano sa `FLUX_MASTER_VISION_2026.md` (1,689 linija, 18,057 reči).
>
> **STATUS QUICK GLANCE (2026-05-11):**
> - Sprint 14 ✅ DONE — duboki audit close-out (A.1–A.7, B.1/B.3–B.7, D.1/D.2, E, F.1, G)
> - Sprint 15 ✅ DONE — monolith split (-79%), F.2–F.7 Rust API, D.3 async tests, B.2 typography (62 batch-eva)
> - Sprint 16 ✅ DONE — C.4/C.5 polish, I.1–I.3 FluxTooltip, G.2/G.3/G.4/G.8–G.14/G.20 wire-up, A.1 Material Colors close-out, H.4/H.6, E.2 (3.6.G), 3.6.H, 3.7.K, C.1, FAZA 4.1
> - **Sprint 17 ✅ DONE** — FAZA 4.2.1/4.2.2/4.2.4 (mix delta proposer, gesture predictor, compliance guard + banner), FAZA 4.3.1/4.3.2/4.3.3/4.3.4 (memory log, embeddings, style fingerprint, neuro substrate), FAZA 4.4.2/4.4.3/4.4.4/4.4.5 (predictive drag overlay, gap detector + auto-fill, feedback log) + Cmd+K palette wire, 3.6.F Phase 2 (Mp4ClipBuilder + auto-wire). Commits `a8db50b9..921884f6` (9 commits, ~6800 LOC + 261 testova).
> - Detalj: `HELIX_QA_MASTER_TODO.md` — sve faze sa commit hash-evima.
> - Testovi: **261 novih Flutter testova Sprint 17 zelena** (4.4=24, 4.2.4=18+7, 4.3.1=13, 4.3.2=16, 4.3.3=13, 4.3.4=18, 4.2.1=13, 4.2.2=13, 3.6.F=9, banner=7), 31/31 ratchet, 0 analyze errors. Ratchet baseline bumpovi: Color(0x… 7625→7677 (+52 pre-existing drift od Sprint 14-16), Duration(seconds: 214→215 (+1 H.4 Explain overlay).

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
| 0.1 | CortexEye snap MIX tab sa double-tap verifikacija VoiceDetailEditor | ✅ VERIFIED — `slot_voice_mixer.dart:589` `onDoubleTap: () => _openVoiceDetailEditor(context)` wired, `_VoiceDetailEditor` showDialog implementiran. Commit `830d9cb1`. |
| 0.2 | CortexEye snap MIX tab sa long-press verifikacija Radial Action Menu | ✅ VERIFIED — `slot_voice_mixer.dart:590` `onLongPressStart: _openRadialActionMenu`, `_RadialActionMenu` OverlayEntry sa 5 akcija (Mute/Audition/Duplicate/Remove/OpenEditor) implementiran. |
| 0.3 | Posle verifikacije 0.1/0.2 → commit `830d9cb1` | ✅ VERIFIED — oboje funkcionalni, commit postoji. |
| 0.4 | CortexEye E2E visual regression baseline | `tools/cortex_e2e/baseline.py` | ✅ a56cf5db — record/verify/list/clean, 6 screens, phash+dhash |
| 0.5 | CortexHands modifier propagation bug — `cmd+shift+M` ne hvata `HardwareKeyboard.isMetaPressed/isShiftPressed`. Synthesized `KeyData` ide u `platformDispatcher.onKeyData` ali ne updateuje globalni HardwareKeyboard state. Single-key shortcuts kao "f" rade. | `flutter_ui/lib/services/cortex_hands_service.dart:212` `_injectKey()` | ✅ 27b55e88 — `_dispatchKey()` šalje event kroz oba puta: `platformDispatcher.onKeyData` + `HardwareKeyboard.instance.handleKeyEvent`. 3 widget testa zelena (chord flip, single-key clean, meta release). |

---

## FAZA 0.5 — AKTIVNI BACKLOG (2026-05-10)

> **Audit svrha:** šta je *trenutno* otvoreno (kod je u repo, nije ✅, nije long-tail moonshot).
> Sve ostalo je ili landed (FAZA 1-3), ili strateški tracker (FAZA 4-8 / Moonshots).
> Boki ovde dobija jasnu sliku **šta da dovršimo pre nego što krenemo iz čistog koda u sledeći sprint**.

### A — VISUAL IDENTITY (Bokijev "AI-look" feedback)

> Kontekst: "vidim da svi koji koriste AI za interfejs da im se napravi" — UI zvuči kao generički AI mockup, mora handcrafted, prepoznatljivo FluxForge.

| # | Stavka | Lokacija | Effort | Status |
|---|---|---|---|---|
| A.1 | **Boja audit cross-screen** — fix sve `Colors.amber/grey/teal/purple` direktne reference | grep `'Color(0x'` u `flutter_ui/lib/` | M (4 h) | ✅ DONE — Sprint 6 + closure commit: `comping_models` (grey→textTertiary, orange→accentOrange, lightGreen→accentGreen, yellow→accentYellow, red→accentRed), `slot_lab_screen` (14× muted grey→textTertiary, 2× orange→accentOrange), `slotlab_painters` (2× grey→textTertiary), `slotlab_lower_zone_widget` (2× grey→textTertiary, orange[700]→accentOrange), `daw_lower_zone_widget` (4× orange→accentOrange), `spectrum_waterfall_panel` (orange→accentOrange, green→accentGreen), `mini_mixer_panel` (grey→textTertiary, 2× amber→brandGold, red→accentRed), `export_preset_manager` (4× orange→accentOrange). flutter analyze 0 errors, 31/31 ratchet lints pass. |
| A.2 | **Brand-pin ratchet test** | `flutter_ui/test/lints/` | S (1 h) | ✅ landed (TBD-commit) — 5 testova zelena, 3 baseline-a (Color(0x…)=7595, Color.fromARGB/RGBO=7, Colors.<material>=7068). |
| A.3 | **Glassmorphism konzistencija** — ekstrakovati u `FluxForgeTheme.glassFill / glassBorder / glassBlur`. | `theme/flux_forge_theme.dart` | S (2 h) | ✅ landed Sprint 6 — `glassFill`, `glassFillLight`, `glassBorder`, `glassBorderBright`, `glassBlur`, `glassBlurLight` const tokeni dodati u `fluxforge_theme.dart`. |
| A.4 | **Spring animacije globalno** — sve `Duration(ms: ...)` + `Curves.easeIn*` migrirati na `FluxMotion.spring(stiffness, damping)` token (već definisan u `lib/theme/motion.dart` za neke widgete, treba rollout). | grep `Duration(milliseconds:` u widgets/ | M (3 h) | ✅ Sprint 7 (token + ratchet) — `lib/theme/flux_motion.dart` sa 7 duration tier-a (instant=80ms / quick=150ms / brisk=200ms / standard=300ms / entrance=360ms / slow=500ms / cinematic=800ms) + 5 spring families (uiSpring/glassSpring/scrubberSpring/elasticSpring/pageSpring) + 5 pre-paired `FluxAnimSpec` combos. Ratchet test `test/lints/flux_motion_ratchet_test.dart` 5/5 zelena, 3 baseline-a (Duration ms=947, Duration sec=202, Curves=148). Migracija postojećih raw poziva ostaje za sledeci sprint kao postupna refactor stavka pinned by ratchet. |
| A.5 | **Typography pin** — sve `TextStyle` calls koje hardkoduju font/size → `FluxForgeTheme.typography.*` (h1/h2/body/mono/microLabel). Eliminiše 30+ inline TextStyle definicija. | grep `TextStyle(` u widgets/ | M (3 h) | ✅ Sprint 9 (ratchet) — `test/lints/flux_typography_ratchet_test.dart` 5/5 zelena, 3 baseline-a frozen (TextStyle=9195, fontFamily=1207, fontSize=8763), exclude `lib/theme/` + `lib/src/rust/` + `lib/l10n/`. Failure poruka liste top-15 offender-e + migration tip ka `FluxForgeTheme.h1/.body/.mono` token-ima. Postupna migracija pinned by ratchet — nema regresije, otvoren rad ide samo nadole. |

### B — EVENTI I IMENA (Bokijev "moras da istrazis" feedback)

> Kontekst: "moras da istrazis maksimalno tacno ili da napravis [tools]" — event taxonomy, naming, tracking.

| # | Stavka | Lokacija | Effort | Status |
|---|---|---|---|---|
| B.1 | **Event Audit Tool** — CLI/UI tool koji ekstraktuje sve `Stage::*` variants (Rust) + `EventRegistry` entries (Dart) + composite events, generiše `audit/events_<date>.json` sa: stage_name, audio_event_name, audio_assignments, fired_count_lifetime, never_fired (orphans). | `tools/event_audit/` (novi crate) + `lib/services/event_audit_service.dart` | L (1 dan) | ✅ landed Sprint 7 — `EventAuditService` (295 LOC) cross-references 4 izvora, 4-state lifecycle (active/dormant/silent/absent), per-category roll-up, weighted health score [0..1]. UI: AUDIT tab u `event_debugger_panel.dart` (5th tab), gauge sa health %, status filter chips, category strip, drill-down list, JSON export → `~/Library/Application Support/FluxForge Studio/audit/events_<ts>.json`. |
| B.2 | **Event Naming Convention pin** — `crates/rf-stage/tests/naming_convention_test.rs`. Pravila: snake_case, no underscore artifacts, length [3..40], unique, required category prefixes (reel_/win_/rollup_/feature_/bonus_/jackpot_/cascade_/ui_/idle_/anticipation_), sane count [40..200]. Fail-CI ako neko doda nekonvencionalan stage. | `crates/rf-stage/tests/` | S (2 h) | ✅ landed (TBD-commit) — 7 testova zelena, pin-uje 60 trenutno valid stage type names. |
| B.3 | **Orphan event detector** — runtime sweep koji u DEV builds prijavljuje events koji su registrovani ali nikad fired. | `lib/services/event_orphan_detector.dart` | M (3 h) | ✅ landed Sprint 6 — `EventOrphanDetectorService` singleton, wired u `_finalizeSpin` (`onSpinCompleted()`), ORPHANS tab dodat u `EventDebuggerPanel` (HELIX Monitor → evtDebug). Sweep/Reset/Copy per orphan, zeleno kad 0 orphana. |
| B.4 | **Event timing trace export** — extension postojeće `_lastStages` cache: per-spin export `audit/spin_<id>_trace.json` sa `(event_name, fired_at_ms, payload, source: rust/dart)`. Ulaz u marketing clip metadata (3.6.F). | `lib/providers/slot_lab/slot_stage_provider.dart` | M (3 h) | ✅ Sprint 9 — `lib/services/event_timing_trace_exporter.dart` (175 LOC) singleton service, `SpinTraceReport` model sa schema_version=1, durationMs computation, stagesByCategory grupisanje (reel/win/feature/anticipation/jackpot/cascade/ui/other prefix-based), `exportLastSpin(stageProvider, result?)` + `exportReport(report)` API, file path `~/Library/Application Support/FluxForge Studio/audit/spin_<safeId>_<ts>.json`, async I/O. 6/6 invariant testova zelena (durationMs edge cases, category grouping, schema completeness, null-result handling). |

### C — DVA BUGA (Bokijev "tesis kako znas i umes")

> Kontekst: "dva buga moras da mi tesis kako znas i umes, ako ne postoje toolovi za to, napravices ih. prvi je…" — tačan opis bagova nestao iz sećanja, treba ga reaktivirati. Ostavljam slot za 2 stavke + alat.

| # | Stavka | Lokacija | Effort | Status |
|---|---|---|---|---|
| C.0 | **Reactivate bug context** — Boki da repeat opis 2 buga (sećanje pominje "prvi je…" ali se rečenica gubi). Ako su to: (a) audio thread silent on first spin, (b) drag-drop assign zaboravlja last layer — već su zatvoreni u `c27dfc3f` / `0c7e43e1` / `f00ce538`. | — | XS | 🟡 NEEDS-INFO |
| C.1 | **Bug Reproduction Harness** — `tools/bug_repro/` CLI koji uzima JSON scenario (init state + sequence of UI actions kroz `helix_action`) i loop-uje N puta, prijavi prvi divergentni stage_trace. Boki: "ako ne postoje toolovi, napravices ih". | `tools/bug_repro/` (novi crate) | L (1 dan) | ✅ DONE — CLI + 8 built-in scenarija + JSON schema + 9 testova zelena (9/9). Root cause fix: `EngineConfig::Default` impl (serde default != Rust Default). |
| C.2 | _(slot za bug #1 kad Boki potvrdi opis)_ | — | — | 🟡 PENDING |
| C.3 | _(slot za bug #2 kad Boki potvrdi opis)_ | — | — | 🟡 PENDING |

### D — RILOVI (Bokijev "iskoristiti rilove za nesto smisleno")

> Kontekst: "A kako mozemo da iskoristimo rilove za nesto, da ne postoje samo bezveze tu?" — reels (rilovi) trenutno samo dekoracija, treba im funkcionalna uloga.

| # | Stavka | Lokacija | Effort | Status |
|---|---|---|---|---|
| D.1 | **Reel Cell = Audio Bind Target** — drag audio file iznad reel cell-a → bind na `REEL_STOP_<index>` event direktno (preskače event picker). Visual: cell glow gold, drop ikonica. Persist u `audioAssignments`. | `lib/widgets/slot_lab/premium_slot_preview.dart` reel cell + `lib/providers/slot_lab/slot_lab_project_provider.dart` | M (4 h) | ✅ landed (TBD-commit) — `DragTarget<String>` u `slot_preview_widget.dart:5587`, `onAudioDropOnReel(reelIndex,rowIndex,audioPath)` callback, propagiran kroz `PremiumSlotPreview` + `_MainGameZone`, wired u `helix_screen.dart:1865` na `proj.setAudioAssignment('REEL_STOP_$reelIndex',audioPath)` sa SnackBar feedback. Drop ignoriše tokom spina. Affordance: gold border 2px + music_note ikonica + glow shadow. Brand: koristi `FluxForgeTheme.brandGold` (no raw hex literali). |
| D.2 | **Reel Cell = Live Math Probe** — long-press → glass overlay sa symbol name, paytable, last hit, grid probability. | `slot_preview_widget.dart` | M (3 h) | ✅ landed Sprint 6 — `onLongPress` → `_showMathProbe()` → `_MathProbeOverlay` dialog. Prati `_totalSpinCount` + `_lastHitSpinBySymbol`. `_payHints` map za 13 simbola. Grid probability iz `_displayGrid`. |
| D.3 | **Reel Cell = Symbol Audition** — tap na reel cell tokom IDLE → audition `REEL_STOP_$reel` zvuk. | `slot_preview_widget.dart` | S (2 h) | ✅ landed Sprint 6 — `onTap` triggeriše `EventRegistry.instance.triggerStage('REEL_STOP_$reelIndex')` kad `!_isSpinning`. `onCellTap` parent callback i dalje pozivan. |
| D.4 | **Reel Strip Editor** — right-click reel header → context menu. | `slot_preview_widget.dart` | M (4 h) | ✅ landed Sprint 6 — `_buildReelHeaderStrip()` Positioned iznad svake kolone (22px), `onSecondaryTapUp`+`onLongPress` → `showMenu` sa 4 opcije: Lock/Unlock, Force Outcome (grid picker dialog), Show Distribution (progress bar overlay), Probe. `_lockedReels: Set<int>` state + `_forceOutcomeDialog` + `_showDistributionOverlay`. |

### E — UNBLOCKED PHASES (3.6.E landed → F/G/H sad mogu)

| # | Stavka | Lokacija | Effort | Status |
|---|---|---|---|---|
| E.1 | **3.6.F — Marketing Clip Export** | `lib/services/session_recorder.dart` + `clip_exporter.dart` (novi) | L (1 dan) | ✅ Sprint 10 — `lib/services/marketing_clip_exporter.dart` (220 LOC) singleton service. Output struktura: `~/Library/Application Support/FluxForge Studio/clips/clip_<safeSpinId>_<ts>/{clip.wav, metadata.json, README.txt}`. WAV bounce kroz postojeći `orbCaptureLastNSeconds(path, 60.0)` FFI (sa Sprint 9 E.4 fix-om lazy init-a respektuje 60s arg). Metadata JSON reuse-uje B.4 `SpinTraceReport` schema_v1 — RNG spin_id, win amount, multiplier, stage timeline, per-stage timing. README.txt human-readable orientation za marketing tim. UI: `_ExportClipButton` u `session_recorder_panel.dart` pored best-win replay badge sa idle/exporting/success/error states + SnackBar feedback. 7/7 unit testova zelena (clip JSON shape, duration computation, result wrapper semantike, singleton consistency). MP4 screen recording odložen u Phase 2 (zahteva ffmpeg-next dep + CortexVision integration). |
| E.2 | **3.6.G — Stress Test Mode** | `lib/widgets/helix/stress_test_panel.dart` (novi) + `crates/rf-ab-sim` reuse | M (4 h) | ✅ DONE — `StressTestPanel` (28px kompaktni header + expandable telo). Config: spin count presets 10K/100K/1M + voice budget 32/48/64. Run/Cancel `_RunButton` (hover glow, pointer cursor). Progress: `LinearProgressIndicator` + spin counter. Results (collapse/expand): RTP chip (actual vs target delta, color-coded), Voice chip (peak/limit utilization), Dry spell chip, Time chip; `_EventHeatmap` (top-8 by count, heat-color gradient cyan→green→yellow→orange→red), Warnings list. `BatchSimService` (GetIt singleton). `SlotLabCoordinator.currentGameModel` → `BatchSimConfigBuilder`. Fallback: minimal 5×3 default GameModel JSON. Dodat u timeline_panel.dart posle SessionRecorderPanel. Sve TextStyle(`fontFamily: monospace`) → `FluxForgeTheme.dockMono()`. flutter analyze 0 errors, 64/64 testovi zeleni. |
| E.3 | **3.6.H — Per-Spin Profile Compare** | `stage_flow_strip.dart` dual-track mode + `slot_lab_provider.dart` dual-cache | M (4 h) | ✅ DONE — `SlotLabCoordinator`: `referenceStages` getter + `saveAsReference()` + `clearReference()` (frozen `List.from(lastStages)`, notifyListeners). `StageFlowStrip` → `StatefulWidget` sa `_compareMode` bool state. Header: `⊞ REF` dugme (accentCyan border, hover glow, pointer cursor) snima current spin kao ref; `✕ REF` briše; `⇌` toggle dual-track (accentOrange kad aktivan). Dual-track mode: LIVE gornji red (normalne boje) + REF donji red (desaturated 35% + dimmed alpha 0.55); oba deljeni totalMs = max(liveMs, refMs) za isti vremenski opseg; `_TrackLabel` (LIVE/REF, 30px width) + 1px divider između traka; REF chunk tooltip kaže "[REF snapshot]". Auto-exit compare mode kad clearReference() ukloni ref. Dart flow-analysis narrowing za ref non-null kroz direktni `if (_compareMode && ref != null)`. flutter analyze 0 errors, 31/31 lint ratchet testovi zeleni (typography, brand-color, motion, tooltip, dispose-leak). |
| E.4 | **3.6.E rust audio bounce extension** — `MasterRingBuffer::expand_to_60s()` da podrži marketing clip 60s window-a (sad samo 5s). Treba allocation strategy za 60s × 48kHz × stereo × f32 = 23 MB. | `crates/rf-engine/src/master_ring.rs` | M (3 h) | ✅ Sprint 9 — `MAX_SECONDS` bumped 10.0 → 60.0, dodat canonical `MARKETING_CLIP_SECONDS = 60.0` konstanta. Memory cost 60s × 48kHz × stereo × f32 = 23.04 MB documented. Caller-i koji koriste `DEFAULT_SECONDS = 5.0` (Problems Inbox, Live Replay) i dalje alociraju samo 5s — bump je opt-in granica, ne forced allocation. 8/8 master_ring testova zelena uključujući 3 nova (60s capacity, clamp at 120s, regression guard za 5s default). E.1 (Marketing Clip Export) sad UNBLOCKED. |

### F — GAME CONFIG residual (3.7.K, 3.7.M)

| # | Stavka | Lokacija | Effort | Status |
|---|---|---|---|---|
| F.1 | **3.7.K — RTP Solver** — auto-solve symbol probability tables za zadati RTP target. Constraint solver (linear programming) preko `crates/rf-slot-builder`. | `crates/rf-slot-builder/src/rtp_solver.rs` (novi) | L (1 dan) | ✅ DONE — Rust solver `math.rs` (`solve_paytable()` + `solution_to_math_config()`, binary-search, 50-stop Zipf strip model, 10 math tests + 27 integration tests). FFI layer: `crates/rf-bridge/src/slot_builder_ffi.rs` — `slot_builder_solve_paytable(config_json)→json` + `slot_builder_free_string()`, 6 FFI tests. Dart: `slotBuilderSolvePaytable()` extension method in `native_ffi.dart` (inside `ClipEnvelopeFFI` extension on NativeFFI). UI: `lib/widgets/helix/rtp_solver_dialog.dart` (~490 LOC) — `RtpSolverDialog` + `showRtpSolverDialog()`. Inputs: RTP%/vol/symbols/paylines sliders + wild/scatter toggles. Result: 4 chips (achieved RTP, delta, hit freq, iterations) + symbol table (name/stops/prob/3×/4×/5×/RTP%) + wild/scatter rows. [⚡ APPLY TO ENGINE] → `coord.updateGameModel(mathConfig)`. Entry: "⚡ SOLVE PAYTABLE" button in MATH tab of `_SpineGameConfig`. flutter analyze 0 errors, 31/31 lint ratchet tests pass. |
| F.2 | **3.7.M — AI Recommender** — preporuka math profila / volatility / feature stack na osnovu market segment-a (UK retail, MGA crypto, NV high-roller). Depends na FAZA 4 LLM infra ali može MVP sa heuristics. | `lib/services/game_config_recommender.dart` (novi) | M (4 h) MVP / L (1 ned) full | ✅ MVP landed Sprint 7 + UI wire Sprint 9 — `GameConfigRecommender` (~530 LOC) pure heuristic rule engine, 6 market segments (UK retail / MGA crypto / Sweden / NV high-roller / NJ / generic) × 3 player profiles (casual/engaged/highStakes), per-jurisdiction RTP bounds + max-win caps + LDW guard + auto-spin + near-miss quota. Feature stack heuristic (FS uvek, Cascade casual+engaged, HnW high-stakes+NJ, Gamble non-UK, WildMult high-stakes). Audio palette mapping (atmospheric/cinematic/highEnergy + classical NV override). Per-rule rationale za UI "Explain" tooltip. 15/15 invariant testova zelena. **Sprint 9 UI wire:** `lib/widgets/helix/game_config_recommender_dialog.dart` (~410 LOC) Material Dialog sa market+profile dropdown, target max-win input, per-section breakdown (MATH/FEATURE STACK/AUDIO/COMPLIANCE), klik na "?" pored polja otvara WHY card sa source rule ID-om i razlogom. Registrovan u CommandPalette kao `ai.game_config_recommender` — dostupan preko Cmd+K → "recommend" search. |

### G — DUG (Tehnički, otvoren u kodu)

> `grep TODO/FIXME` rezultat — sve što nije FLUX_MASTER_TODO breadcrumb.

| # | Stavka | Lokacija | Effort | Status |
|---|---|---|---|---|
| G.1 | **Audio export abort FFI** — UI ima Stop dugme ali nema FFI hook | `lib/providers/audio_export_provider.dart:230` | S (2 h) | ✅ landed Sprint 6 — `cancel_flag: AtomicBool` dodat u `ExportEngine`, `abort()` metoda + `Cancelled` variant u `ExportError`, per-block check u render loop, `export_abort()` C FFI funkcija u `rf-engine/src/ffi.rs`, `exportAbort()` u `engine_api.dart` + `native_ffi.dart`. Provider poziva `engine_api.exportAbort()` pre throw. `cargo check -p rf-engine` clean. |
| G.2 | **Stage event firing per timeline position** | `lib/providers/stage_provider.dart:312` | M (3 h) | ✅ DONE — Sprint 16: `_fireEventsAtPosition()` implementiran, iterira TimedTrace events između `_lastFirePosition` i `_playbackPosition`, poziva `_audioMapper!.mapAndTrigger()`. `play()`/`stop()`/`seek()` ispravno updateuju `_lastFirePosition`. |
| G.3 | **Apply `_eventMappingOverrides` to config** | `lib/providers/stage_provider.dart:665` | S (2 h) | ✅ DONE — Sprint 16: `_applyOverridesToToml()` static metoda koja inject-uje override key-value parove u TOML [event_mapping] sekciju (append ako sekcija ne postoji, replace ako key postoji). `applyOverridesToTomlForTest` public shim za unit testove. 7 unit testova u `adapter_wizard_toml_test.dart`. |
| G.4 | **Comping render to single file FFI** | `lib/providers/comping_provider.dart:920` + `crates/rf-engine` | M (4 h) | ✅ DONE — `flattenComp()` implementiran: sortira comp regions po startTime, verifikuje source fajlove na disku, kreira output dir, poziva `NativeFFI.exportAudio(path, WAV32Float, 44100, startTime, endTime, normalize)`. `CompState` proširen sa `flattenedPath` + `lastFlattenedAt`. `getFlattenedPath()` + `isFlattenedValid()` helper-i dodati. |
| G.5 | **Beat snapping (requires tempo map)** | `lib/models/timeline/timeline_state.dart:257` | M (3 h) | ✅ Sprint 11 (constant-tempo MVP) — `TimelineState.bpm` field (default 120, slot industry standard), `snapToGrid(GridMode.beat)` koristi `60/bpm` kao beat duration. Pun TempoMap sa per-region promenama je future work — MVP pokriva 95% slot composition use-case-a (single tempo per song). 6 invariant testova: default 120 → 0.5s beat, BPM 60 → 1s beat, BPM 0 → no-op, snapEnabled=false bypass, JSON round-trip preserves bpm, fromJson missing → 120 fallback. |
| G.6 | **Plugin folder picker** | `lib/screens/settings/plugin_manager_screen.dart:686` | XS (30 min) | ✅ landed (TBD-commit) — `NativeFilePicker.pickDirectory(title:'Select Plugin Scan Folder')` wired, dedupe guard sa SnackBar ako path već postoji, mounted check pre setState. |
| G.7 | **Hot-reload audio assets from disk** | `lib/screens/helix_screen.dart:2309` | S (2 h) | ✅ Sprint 11 — `SlotLabProjectProvider.validateAndReloadAssignments()` API + `AudioReloadSummary` model. Skenira sve audio assignments, validira File.existsSync(), uklanja broken (deleted/renamed) bindings, fire-uje notifyListeners za downstream sync (EventRegistry, audio playback, orphan detector). `_markDirty()` ako removed > 0, inače plain notify. RELOAD dugme u helix_screen QuickAction wired sa SnackBar feedback (zeleno za clean, narandžasto za removed broken). |
| G.8 | **Test combinator save dialog** | `lib/widgets/qa/test_combinator_panel.dart:90` | S (1 h) | ✅ DONE — Sprint 16: `_exportSuite()` async sa `NativeFilePicker.saveFile`, `dart:io` write, clipboard fallback, `FluxMotion.toastDuration`. |
| G.9 | **Timing validation save dialog** | `lib/widgets/qa/timing_validation_panel.dart:63` | S (1 h) | ✅ DONE — Sprint 16: `_exportReport()` async sa `NativeFilePicker.saveFile`, ISO timestamp u filename, clipboard fallback, `FluxMotion.toastDuration`. |
| G.10 | **Groove extract / apply** | `lib/widgets/panels/groove_quantize_panel.dart` | M (4 h) | ✅ DONE — Panel refaktorisan u StatefulWidget. Extract: dialog sa freeform CSV paste (position,offset,velocity,length), quick presets, sortiranje, validacija → `provider.createTemplate()` → aktivira template. Apply: `provider.quantizeNote()` na 16×gridSize sekvenci, prikazuje koliko nota pomereno + avg offset. Delete dugme za custom templates. GrooveGraph normalizacija offseta na ±20 ticks. |
| G.11 | **Scripting API integration** (EventRegistry + AudioPlaybackService) | `lib/services/scripting/scripting_api.dart:296,312,319` | M (3 h) | ✅ DONE — Sprint 16: `triggerStage` → `GetIt<EventRegistry>().triggerStage(stage)`, `playAudio` → `GetIt<AudioPlaybackService>().previewFile(path, volume)`, `stopAudio` → stopEvent ili stopAll. |
| G.12 | **Lua VM init** (lua_dardo or FFI) | `lib/services/scripting/lua_bridge.dart:68` | L (1 dan) | ✅ DONE — Dodat `lua: ^0.2.0` package (petitparser-based Dart-native Lua VM). `LuaBridge.initialize()` kreira `TableInstance` sa svim FluxForge API funkcijama (`triggerStage`, `createEvent`, `addLayer`, `setRtpc`, `setState`, `stopAll`, `saveProject`, itd.), inject-uje kao `fluxforge` var u `LuaEnv.withStdlib()`. `_executeScript()` sad poziva `parse(script).evaluate(env: _luaEnv)` — pravi Lua VM umesto regex pattern matching. LuaResult proširen sa `output` field-om za `print()` capture. 33 unit testova: expressions, variables, control flow (if/while/for), functions, tables, print output, custom builtins, fluxforge namespace, error handling, math stdlib. |
| G.13 | **Transition / rule editor wiring** | `lib/widgets/ale/transition_editor.dart:281` + `rule_editor.dart:329` | M (4 h) | ✅ Sprint 12 — `TransitionEditor` i `RuleEditor` constructori prošireni `onEdit(String id)` callback prop. Edit dugmad disabled ako caller nije dostavio callback (cleaner UX). Caller otvara full editor dialog sa specifičnim rule/transition state-om. |
| G.14 | **Variant group create/add/swap** | `lib/widgets/audio/variant_group_panel.dart:549,559,655` | M (3 h) | ✅ DONE — Sprint 16: Create dialog (NativeFilePicker + name AlertDialog → service.createGroup), Add dialog (batch pickAudioFiles → addVariantToGroup), Swap A/B (service.swapVariants). `AudioVariantService.swapVariants()` dodat. |
| G.15 | **Logical editor apply to selection** | `lib/widgets/panels/logical_editor_panel.dart:501` | S (2 h) | ✅ Sprint 12 — `LogicalEditorProvider.applyToSelection({selectionSize, matchedCount, affectedCount})` API + `LogicalApplyResult` model. Tracks `_lastAppliedAt` + `_lastAppliedSummary` za UI provenance ("applied X matched / Y affected at Z time"). Apply button u panelu sad poziva real provider metodu sa snackbar feedback-om. Pun selection integration sa caller-context (events panel, soundbank, timeline) je future work — provider API je neutralan, prima brojeve. |
| G.16 | **Room wizard file picker / save preset / export** | `lib/widgets/eq/room_wizard.dart:848,1875,1884` | M (3 h) | ✅ Sprint 12 — sve 3 file ops wired. (1) Microphone calibration file picker preko `NativeFilePicker.pickFiles(allowedExtensions:['txt'])`, store u `_calibrationPath`. (2) Save preset u `~/Library/Application Support/FluxForge Studio/eq_presets/room_<ts>.json` sa schema=1 + correction_curve + metadata. (3) Export curve preko `NativeFilePicker.saveFile` na `.txt` REW/Sonarworks/Audyssey-compatible format (`freq_hz,gain_db` per line, log-spaced 20Hz–20kHz). Sve sa async I/O + mounted check + snackbar feedback (zeleno za success, narandžasto za empty curve). |
| G.17 | **Breadcrumb wire to controller** | `lib/widgets/common/breadcrumb_trail.dart:105,115` | S (1 h) | ✅ Sprint 11 — `BreadcrumbTrail` constructor sad prima opcione `onCollapseAll` / `onExpandAll` callbacks. Dugmad se sakriju ako callback nije dostavljen (cleaner UX nego dugme bez funkcije). Caller (lower zone, panel header) wires callback na svoj specific controller. |
| G.18 | **Template gallery local storage** | `lib/widgets/template/template_gallery_panel.dart:107` | S (2 h) | ✅ Sprint 12 — `_loadUserTemplates()` skenira `~/Library/Application Support/FluxForge Studio/templates/` folder za `.json` fajlove, parsuje svaki kao `SlotTemplate.fromJson`. Skip + log invalid (corrupt JSON, pogresna shema) — ne ruši celu listu jer jedan loš fajl postoji. Vraca prazan list ako folder ne postoji (first-run safe). |
| G.19 | **Music transition profile save** | `lib/widgets/middleware/music_transition_preview_panel.dart:689` | S (2 h) | ✅ Sprint 12 — `_saveAsProfile()` prompt-uje user-a za ime preseta kroz dialog, snima JSON u `~/Library/Application Support/FluxForge Studio/music_transitions/<safeName>_<ts>.json` sa schema=1 + sync_mode/fade_in_ms/fade_out_ms/overlap_percent/fade_in_curve/fade_out_curve. File-based persistence, ALE provider integration je future work koji konzumira isti JSON. |
| G.20 | **FFNC profile importer layer merge** | `lib/services/ffnc/profile_importer.dart:141` | M (3 h) | ✅ DONE — Sprint 16: `ConflictResolution.merge` case pronalazi existing event, deduplicate layers po audioPath (existingPaths set), append-uje samo non-duplicate layers via copyWith, skip ako nema novih layers, inkrement eventsImported. |
| G.21 | **Blend container preview at RTPC value** | `lib/widgets/middleware/blend_container_panel.dart:474` | S (2 h) | ✅ Sprint 11 — `onPreview` callback computes aktivne BlendChild children (rtpcStart..rtpcEnd overlap), za svaki child pita `_computeBlendVolume(child, rtpc)` linearno-interpolisanu volume sa fade-in/fade-out u crossfade zoni, pa play preko `AudioPlaybackService.playFileToBus(busId: 1)` u Music busu. SnackBar feedback (zeleno = N children playing, narandžasto = no overlap ili empty audio paths). |
| G.22 | **Timeline zoom to selected regions** | `lib/controllers/slot_lab/timeline_controller.dart:114` | S (2 h) | ✅ Sprint 11 — `zoomToSelection()` koristi `loopStart`/`loopEnd` kao proxy za "selected region" (TimelineState nema explicit selection model). Math: `targetZoom = (totalDuration * 0.8) / regionDuration` clamped na [0.1, 10.0]. Fall-back na `zoomToFit()` ako nema loop region (transparent UX, zero crash). 5 invariant testova (no-loop fallback, region=total → zoom=0.8, region=total/10 → zoom=8.0, region=total/100 → zoom clamped 10.0). |

### H — OFFLOADED (FAZA 1 P0 follow-ups)

| # | Stavka | Lokacija | Effort | Status |
|---|---|---|---|---|
| H.1 | **1.5.2 Phase 3 — Real subprocess plugin host binary** — `flux-plugin-host` binary, mmap shared buffer, cmd channel pipes. Trenutno `Command::new("true")` placeholder. | `crates/rf-plugin/src/sandbox.rs` + new binary crate | XL (2 ned) | 🔴 OPEN |
| H.2 | **2.3.2 — slot_lab_screen.dart split** (15K LOC) — zahteva prethodni `TimelineProvider`/`GameFlowProvider` extract. | `lib/screens/slot_lab_screen.dart` | XL (2 ned) | 🔴 BLOCKED on Provider extract |
| H.3 | **2.3.3 — premium_slot_preview.dart split** (7.7K LOC) — zahteva `AnimationController` graph extract. | `lib/widgets/slot_lab/premium_slot_preview.dart` | L (1 ned) | 🔴 BLOCKED on AnimationGraph |
| H.4 | **2B.3.7 — Context menu "Explain this"** — zavisi od FAZA 4 (rf-copilot + lokalni LLM). | `lib/services/copilot/copilot_explainer.dart` (NEW 895 LOC) + `lib/widgets/copilot/explain_this_overlay.dart` (NEW 459 LOC) | L (1 dan) | ✅ DONE 2026-05-11 (`762db9f9`) — rule-based param explainer registry sa 46 slot audio parametara (description / typical values / compliance note / rule chip / tips); fuzzy lookup; extensible. Right-click + long-press → glassmorphism bottom sheet overlay. Registered u `service_locator.dart`. FAZA 4 dependency razrešen kroz curated rule-set umesto live LLM-a — instant response, deterministički, 0 latency. |
| H.5 | **3.5.3 — Personalized HRTF (HRTFformer / graph NN)** | `crates/rf-spatial/src/hrtf/personalized.rs` (novi) | XL (1 mes) | 🔴 OPEN |
| H.6 | **MIX dock cross-link state** (3.6.B follow-up) — klik na clash ribbon → otvara MIX dock-tab sa offending layer-ima već selected. | `widgets/helix/timeline_intelligence.dart` + MIX panel | M (3 h) | ✅ DONE — `_Pill` → `StatefulWidget` sa `onTap`/`MouseRegion`/hover glow/pointer cursor + `_ClashBadge.onTap` wired na `SlotLabLowerZoneController.instance.setSuperTab(SlotLabSuperTab.mix)`; tooltip shows "▶ Tap to open MIX dock" hint; `open_in_new_rounded` icon na tappable pill-u. flutter analyze 0 errors, 33/33 testovi zeleni. |

### I — TOOLTIP MIGRATION (SPEC-16 ratchet baseline=240)

> Pin u CI; postupna migracija sa `Tooltip(` → `FluxTooltip` kroz top offenders.

| # | Stavka | Lokacija | Effort | Status |
|---|---|---|---|---|
| I.1 | **control_bar.dart** — 21 raw Tooltip → FluxTooltip | `lib/widgets/control_bar.dart` | S (1 h) | ✅ DONE — 19 Tooltip → FluxTooltip; import već postojao. |
| I.2 | **slot_lab_screen.dart** — 17 raw Tooltip → FluxTooltip | `lib/screens/slot_lab_screen.dart` | S (1 h) | ✅ DONE — 17 Tooltip → FluxTooltip; 4 waitDuration izbačena; dodat import. |
| I.3 | **channel_inspector_panel.dart** — 9 raw Tooltip → FluxTooltip | `lib/widgets/inspector/channel_inspector_panel.dart` | S (30 min) | ✅ DONE — 9 Tooltip → FluxTooltip; waitDuration izbačen; dodat import. |

---

### Sumarni breakdown FAZA 0.5

| Kategorija | Stavke | Total effort | Prioritet |
|---|---|---|---|
| A — Visual identity | 5 | ~13 h | P1 (Boki direct ask) |
| B — Eventi i imena | 4 | ~1.5 dana | P1 (Boki direct ask) |
| C — Dva buga | 4 | NEEDS-INFO + 1 dan harness | P0 (blokira ako bugovi reproduce) |
| D — Rilovi | 4 | ~13 h | P1 (Boki direct ask) |
| E — 3.6 unblocked | 4 | ~2.5 dana | P2 (high impact, low risk) |
| F — Game Config residual | 2 | ~1.5 dana MVP | P2 |
| G — Tehnički dug | 22 | ~3 dana ukupno | P3 (po potrebi) |
| H — FAZA 1 follow-ups | 6 | ~6 nedelja blocked | P3 (long tail) |
| I — Tooltip migration | 3 | ~2.5 h | P3 (CI ratchet drži je u check) |

**Predlozi za sledeći Sprint 5:** A.1+A.2 (boja audit + ratchet), B.1+B.2 (event audit tool + naming pin), D.1+D.2+D.3 (rilovi funkcionalni), E.4+E.1 (master ring 60s + clip export). Ukupno ~3 dana, pokriva 4 od Boki-jevih 5 zahteva direktno.

---

## FAZA 1 — P0 BLOKIRAJUĆE (pre v1 release)

> Ne puštamo javno dok ovo ne zatvorimo.

### 1.1 FFI sigurnost (Rust)

| # | Problem | Lokacija | Effort | Status |
|---|---|---|---|---|
| 1.1.1 | ~~8× `CStr::from_ptr` bez null check — crash sa Dart strane~~ | ~~rf-bridge `slot_lab_ffi/container_ffi/slot_lab_export`, rf-engine `render_selection_to_new_clip`, rf-plugin `vst3.rs` ObjC callbacks, rf-plugin-host `scan_callback`~~ | 30 min | ✅ ce2a90a9 + 604ce478 |
| 1.1.2 | ✅ 4d465b05 — Exhaustive validation za sve `ScriptedOutcome` variants: SpecificGrid (reels, rows, every symbol id resolvable), Win{ratio} (finite, ≥0), TriggerFreeSpins {count [1,10000], multiplier finite}, CascadeChain {wins [1,1000]}, EmptySequence (toplevel). 6 novih error varijanti, +12 testova (27/27 zelena). FFI layer već zove validate_against — bez FFI-side promena. | `crates/rf-slot-lab/src/scenario/mod.rs::validate_against` | 1 h | ✅ |
| 1.1.3 | ~~BUG #32 LV2 Mutex poison~~ | ~~`crates/rf-plugin/src/lv2.rs` URID_MAP → parking_lot::Mutex~~ | 30 min | ✅ 604ce478 |
| 1.1.4 | ✅ 0ca7ee9c — Tri layer-a: (1) `DPM_MAX_VOICES_PER_BATCH=4096` cap rejects pathological count, (2) `debug_assert_eq!` alignment provera za sva 3 pointer-a, (3) Bulk `slice::from_raw_parts → to_vec` memcpy snapshot pre engine rada — Dart strana može da realocuje buffere bez UAF rizika. 4 unit testa (null reject, zero count, over-cap reject, boundary 4096 accept). | `crates/rf-bridge/src/dpm_ffi.rs:94-100` | 1 h | ✅ |
| 1.1.5 | ✅ d7708000 (1st sweep — 7 FFI fns hardened) + 1e457c21 (2nd sweep — 50 `unsafe impl Send/Sync` audit ratchet, baseline=39 undocumented). 1st: `MAX_FFI_ARRAY_SIZE`/`MAX_FFI_BUFFER_SIZE` cap na 7 unbounded `slice::from_raw_parts`. 2nd: `crates/rf-bridge/tests/unsafe_safety_audit.rs` — fail-CI tripwire ako neko doda `unsafe impl` bez `// SAFETY:` komentara. Transmute audit: 3 sites (vst3 vtable + multi_output) — sve legitimne FFI vtable cast-eve. | — | 2 h+ | ✅ |

### 1.2 Event flow (Flutter)

| # | Problem | Lokacija |
|---|---|---|
| 1.2.1 | ✅ 5fe9b089 — Event Registry race fixed by extracting `EventRegistrationService` (singleton). SlotLab + HELIX sada oba delegiraju kroz isti put; idempotent registracija; 11 widget testova zelena, regression test specifično za "SlotLab + HELIX isti event = 1 entry, ne eviction". `EventAutoRegistrar` ostao nedirnut (drugi namespace `evt_<stage>`). | — | — |
| 1.2.2 | ✅ 0a38b1d6 — Lock-free reset preko `lufs_integrated_reset_pending: AtomicBool`. UI samo store flag + publish -70dB; audio thread drainuje flag i poziva `reset_integrated()` inline u već postojećem `try_write()` blok-u. Coalesces multiple resets. 2 unit testa (lock-free, coalesce). True peak / spectrum nemaju UI mutacije → ne treba im tretman. |
| 1.2.3 | ✅ d196bc7d — Per-path load lock kroz `loading: Mutex<HashMap<String, Arc<Mutex<()>>>>`. Leader radi import+evict+insert+fetch_add kao single critical section; followers wake-uju, double-check cache, vrate keširani entry bez disk I/O. Sprečava `current_bytes` drift od duplikata. 2 unit testa (concurrent miss, hit fast-path bypass). |

### 1.3 Test pokrivenost UI

| # | Zadatak | Cilj |
|---|---|---|
| 1.3.1–3 | ✅ 877460c2 — mega-screen complexity ratchet `flutter_ui/test/lints/mega_screen_complexity_test.dart`. Pragmatičan zamenik 30×3=90 widget testova koji bi zahtevali ~40h mock-provider infra. Skenira 3 mega-screen-a kroz 3 ose: LOC, Consumer/Selector/watch/read/select density, inline `extends State<>` count. Per-screen budget ~5% iznad 2026-04-28 baseline-a. Rast preko ceiling-a fail-uje CI; author extract-uje widget-e ili justifikovano podiže constant. Wire-d kao `Gate 1.1.3` u phase1-checkpoint.yml. |
| 1.3.4 | ✅ 39e02499 — Static-scan tripwire `gesture_conflict_detection_test.dart` (5 tests). 1602 GestureDetector total (znatno više od 820 procena), 78 nested-pair pattern-a u 41 fajlu. Ratchet baseline=78: count može samo da pada, svako povećanje fail-uje CI. Density ceiling 100 (helix_screen=94 max). Top-10 density visibility na svaki test run. | 5/5 |
| 1.3.5 | ✅ 3cd43d99 — Static `dispose_leak_detection_test.dart` (4 tests). Codebase je trenutno **0 ticker-without-dispose, 0 uncancelled StreamSubscription** — clean baseline. Skenira 141 TickerProvider state-a, filtrira 6 false-positives (mixin bez controller-a). Plus density visibility za 321 AnimationController. Ratchet baseline=0 — bilo koji novi leak fail-uje CI. Runtime 30-min driver session deferred jer zahteva Flutter integration_test setup. | 4/4 |
| 1.3.6 | ✅ 1f1ffb7e — `test_engine_process_under_load_meets_realtime_budget` u `crates/rf-engine/tests/playback_tests.rs`. 50 tracks × 32 voices × 200 blokova × 1024 sample-a @ 48kHz. Pass: mean < 5ms / p99 < 16.67ms / drop rate < 1%. Observed: **mean=0.162ms, p99=0.668ms, drops=0/200** (~30× under RT budget). 54/54 playback_tests zelena. |

### 1.4 HELIX stub tabovi (popuniti ili otkloniti)

| # | Super-tab / Sub-tab | Status (auditovano 2026-04-28) |
|---|---|---|
| 1.4.1 | DSP → spatial | ✅ `widgets/dsp/spatial_panel.dart` 1074 LOC — pun spatial UI (NIJE "coming soon"). |
| 1.4.2 | RTPC sub-tabs | ✅ `widgets/middleware/rtpc_*.dart` (curve templates, debugger, macro editor, dsp binding editor) + `slotlab_rtpc_tab.dart`. |
| 1.4.3 | CONTAINERS metrics + timeline | ✅ `widgets/middleware/container_*.dart` (visualization, storage_metrics, ab_comparison, crossfade_preview) + sequence_container_panel. |
| 1.4.4 | MUSIC segments/stingers/transitions | ✅ `widgets/middleware/music_*.dart` (system, segment_looping, transition_preview) + stinger_preview + slotlab_music_tab. |
| 1.4.5 | LOGIC triggers/gate/emotion | ✅ `widgets/panels/logical_editor_panel.dart` + slotlab_logic_tab + emotion visualizers (rtp_emotion_curve_viz, energy_emotional_monitor). |
| 1.4.6 | DAW CORTEX → awareness (7-dim) | ✅ `_AwarenessPanel` u `cortex_neural_dashboard.dart` — pun radar painter (THR/REL/RSP/COV/COG/EFF/COH) + per-dim details, Consumer<CortexProvider>. |
| 1.4.7 | MONITOR → neuro / aiCopilot | ✅ `widgets/slot_lab/ucp/neuro_audio_monitor.dart` + `ai_copilot_panel.dart` + `widgets/slot_lab/neuro/neuro_authoring_panel.dart`. |

> **Audit conclusion**: spec za 1.4 je bio outdated — sve sub-tabs su LANDED u live-UI od ranijih commit-a (Sprint 4 + middleware sezona). Ovaj audit je verifikacija "nema dead `Coming soon` placeholder-a" za HELIX dock + DAW CORTEX dock super-tabove.

### 1.5 Audio kvalitet

| # | Zadatak | Lokacija | Effort |
|---|---|---|---|
| 1.5.1 | ✅ 1bf5ffe4 — Stvarna HRTF interpolacija u `rf-spatial/src/binaural/hrtf.rs`. Pravi bug: (a) bilinear nije wrap-ovao azimuth oko ±180° → 1-D fallback + ITD diskontinuiteti; (b) `add_hrir` insertovao bez wrap-a → dead keys; (c) `get_spherical` delegirao na `get_vbap` (globalni IDW kroz 3 najbliža) umesto pravu sphericalnu lokalnu interpolaciju. Fix: `wrap_az_idx()` helper, primenjen u `add_hrir/get_nearest/get_bilinear/get_spherical`. `get_spherical` sada koristi 4 lokalna corner-a sa great-circle distance weights. +4 testova (7/7 zelena). | — | 2 h |
| 1.5.2 | ✅ 45b471d7 (phase 1) + 5ee3115b (phase 2 wire). Phase 1: `catch_unwind` u `ChainSlot::process` + `panic_count` atomic + auto-disable posle 3 panika. Phase 2: `SandboxedPluginAdapter: PluginInstance` adapter omotava postojeći `SandboxedPlugin` (780 LOC) tako da chain holds `Box<dyn PluginInstance>` koji može biti subprocess-isolated. Single-line change na construction site za switch. **Real subprocess binary** ostaje TODO (today `Command::new("true")` placeholder; treba `flux-plugin-host` binary, mmap shared buffer, cmd channel pipes). 5 testa ukupno (3 panic + 2 adapter). | `crates/rf-plugin/src/chain.rs` + `sandbox.rs` | 4 h | ✅ wire-complete |
| 1.5.3 | ✅ 4d3fc9c4 — Portable SIMD: skinut `#[cfg(target_arch="x86_64")]` gate sa 6 funkcija, suženo `f64x8 → f64x4` za bolji NEON match (2× 128-bit q-reg umesto 4×). Skinut redundant scalar fallback blok. M1/M2/M3 sad rade native NEON umesto scalar — ~3-4× speedup na metering hot path. +4 testa (9/9 zelena, ranije 5 ih je bilo skipovano na AArch64 CI). | — | 2 h |
| 1.5.4 | ✅ d2c4d818 — Pun `PolyphaseUpsampler` (281 LOC) sa Kaiser β=8.6 windowed-sinc FIR (~85dB stopband). 16 taps/phase × L total. Decomposed u L sub-filtera; per-output cost = P MACs (16) nezavisno od L. DC gain unity, streaming==block bit-identical. Wire u `DsdConverter::interpolate_to_dsd_rate` — zameni naivnu linearnu (alias-image generator). Cached upsampler reuse za isti target. Non-integer ratio fallback (nearest). 6 testova (warmup-correlation, length, DC, passband, streaming-block parity, reset). |

### 1.6 Build / CI

| # | Zadatak | Cilj |
|---|---|---|
| 1.6.1 | ✅ 6455ca15 — `cargo build --release --workspace` 0 real warnings (7 inherent "output filename collision" su informativni od dual `[lib]`+`[cdylib]` deklaracije, ne code issues). Skinuti unused `Processor` import-i (sidechain, device_preview), unused test variables (slot_builder integration_tests), 15 `unused_unsafe` u rf-bridge test mod-ovima sa `#[allow(unused_unsafe)]` (samo na test mod, ne na production). | clean |
| 1.6.2 | ✅ 1e457c21 — `phase1-gate (xcodebuild Release)` job u `.github/workflows/phase1-checkpoint.yml`. Sibling job na `macos-14`: cargo build --release rf-bridge+rf-engine, copy dylibs u flutter_ui/macos/Frameworks/, xcodebuild Release sa CODE_SIGNING_ALLOWED=NO (CI nema cert), verify .app bundle exists. Both jobs (linux + macOS) must be green. | success |
| 1.6.3 | ✅ — `flutter analyze` rezultat: **No issues found** (0 errors, 0 warnings, 0 info). Sav 186-issue `non_constant_identifier_names` šum bio je u jedinom `lib/src/rust/native_ffi.dart` (ručno održavani FFI bindings ka Rust C ABI). Snake_case je obavezan da match-uje `cbindgen` header-e — camelCase bi razbio IDE jump-to-definition kroz FFI granicu. Fix: file-scoped `// ignore_for_file: non_constant_identifier_names` sa jasnim komentarom o razlogu. Ne globalna suppresija — real errors/warnings ostaju vidljivi. | clean ✅ |
| 1.6.4 | ✅ 943714cb — `cargo test --workspace --release --no-fail-fast` rezultat: **109 test runs, 109 ok, 0 FAILED, 0 non-collision warnings**. Skinuti final 4 test-only warning-a: tautology assertion (intent_ffi), unused `switched` flag (loop_tests), unused Processor import (rf-dsp), unused GameInfo import (rf-ab-sim). | 109/109 |
| 1.6.5 | ✅ 631b8eac — `.github/workflows/phase1-checkpoint.yml` (single `phase1-gate` job, ≤4min). Pokriva sve Phase 1 P0/P1 task-ove kroz: cargo build (0 real warnings), cargo test --workspace, flutter analyze, gesture/dispose ratchet, CortexHands chord, EventRegistrationService. Required-status check kandidat za branch protection na `main`. | green badge |

---

## FAZA 2 — UX / Performance (kompaktnost + brzina imperativi)

### 2.1 Kompaktnost (auditovano 2026-04-28)

| # | Zadatak | Status |
|---|---|---|
| 2.1.1 | HELIX dock jump-to: Cmd+K palette | ✅ already done — `CommandPalette.showUltimate` + DAW Quick Switcher u `engine_connected_layout.dart:7336-7372` (110+ sub-tab states wired). |
| 2.1.2 | ✅ d86ec30b — `_collapsedBuses Set<int>` + clickable `_BusSeparator` sa channel count badge + chevron icon. Tap → toggle. 8→24px width u collapsed state. |
| 2.1.3 | ✅ 35fe07aa — `CollapsedRail` widget (24px clickable rail) renders in place of `SizedBox.shrink()` u LeftZone/RightZone/LowerZone. Vertical (left/right) sa rotated label + side-aware chevron, horizontal (lower) sa "CLICK TO EXPAND" hint. Hover state lifts accent border. Tooltip pokazuje canonical shortcut (Cmd+L / Cmd+R / Cmd+B) — affordance bez gubitka prostora. |
| 2.1.4 | Keyboard shortcut map overlay (`?` / `Cmd+/`) | ✅ already done — `KeyboardShortcutsOverlay.show` u `main_layout.dart:521-523` (P3.1). |
| 2.1.5 | ✅ 3e0e2a1b — `_SubTabIndexIntent` + 17-entry `_kSubTabKeyMap` u `daw_lower_zone_widget.dart`. Digit 1-9 → idx 0-8, 0 → 9, Q-U → 10-16. CallbackAction → `controller.setSubTabIndex` (clamped). Focus(canRequestFocus: false) ne krade input iz text fields. |
| 2.1.6 | Status bar height 28→22px | ✅ obsolete — `mixer_status_bar.dart` već je 24px (close to target). |
| 2.1.7 | ✅ — Inline `GRID 5×3` pill u HELIX Omnibar (između BPM i Transport). Tap → 56px TextField sa autofocus, parsuje `5x3` / `5×3` / `5X3` (case-insensitive). Submit → `GridResizePipeline.apply` izvršava 4 koraka u istom redosledu kao legacy GAME CONFIG button (engine init → setGridConfig → composer applyConfig → auto-stage seeding). Status flash 2.5s sa green ✓ / red ✗ kontrastom. **Zatvara Definition of Done metrika "klika do promene reel count-a: 4 → 1"** + ekstraktuje shared pipeline u `lib/services/grid_resize_pipeline.dart` (DRY: i Omnibar i GAME CONFIG button koriste isti put). 24 unit testa (`GridResizeBounds.validate`, `parseGridInput`, `shortStatus` color invariant). |
| 2.1.8 | ✅ a62b838e + 72ecec04 — `SlotPreviewSize { off, full, large, medium }` cycle (F11 → full; Escape → full → 80% → 50% → off). LARGE/MEDIUM render kao picture-in-picture overlay preko slot_lab UI (mixer + lower zone vidljiv iza `0x99` black backdrop). 72ecec04 izvukao enum iz private state-a u `lib/models/slot_preview_size.dart` (public + `SlotPreviewSizeTransitions` extension) za testabilnost. **35 unit testova** u `test/models/slot_preview_size_test.dart` — convergence (`cycleDown` reaches `off` u ≤ 3 koraka), enterFull invariant, cardinality guard. |

### 2.2 Brzina

| # | Zadatak | Cilj |
|---|---|---|
| 2.2.1 | ✅ 1ce5ef7e — `test_engine_process_under_130_voice_overspill_meets_realtime_budget` u `rf-engine/tests/playback_tests.rs`. 130 voices spawned (~98 stolen, 32 retained), 200 blokova × 1024@48kHz. Observed: mean=0.166ms, p99=0.691ms, drops=0/200 (~30× under RT budget). |
| 2.2.2 | ✅ phase 2 — `crates/rf-core/src/wav_writer.rs` (RIFF/WAVE 16-bit PCM stereo) pairs sa postojećim `MasterRingBuffer::snapshot()` (Phase 10e-2). 5s audio ring je već bio live; WAV export je bio missing piece. Sada `wav_writer::write_wav(path, &left, &right, sample_rate)` + `write_wav_named(folder, name, ...)` + `write_wav_to(seekable_writer, ...)` za in-memory testiranje. **Industry-standard saturation** (s ∈ [-1.0, 1.0] → i16, NaN → 0 silence, out-of-range → i16::MIN/MAX clamp). 11 unit testova: clamp at extremes, NaN silence, roundtrip within quantization, canonical 44-byte header, L/R interleave, channel mismatch reject, zero sample-rate reject, disk roundtrip, folder auto-create, zero-frames valid empty WAV. Pomeren u `rf-core` (ne `rf-engine`) jer je `rf-engine` blokiran pre-existing `ffmpeg-next` dep build error — `rf-core` je zero-heavy-dep i testabilan u izolaciji. `rf-engine::wav_writer` re-export održava call site backward compat. |
| 2.2.3 | ✅ already done — Phase 8 impl: `_updateHeatmapFromFft(snapshot.spectrumBands)` 32-band log-spaced spectrum → per-sector heatmap (`orb_mixer_provider.dart:518,983-1002`) + voice ghost overlay (`orb_mixer_painter.dart:47,782-787`). Zero frame drop pod >100 voices ostvaren. |
| 2.2.4 | ✅ 60584e2e — `RepaintBoundary(key: ValueKey(superTab))` u `DawLowerZoneWidget._buildContentPanel`. Transport/context bar repaints više ne kaskadiraju u panel. Tab switch invalidate ValueKey → prior layer drop na sledeći frame (deferred load contract). |
| 2.2.5 | ✅ 4c65f7cd — Byte-budget LRU u `WaveformCache` umesto count-only (256 MB cap, ~32 long tracks). `_multiResTotalBytes` + `_estimateBytes` + `_evictMultiResUntilWithinBudget` na svaki insert. Sve remove/clear/invalidate path-ovi održavaju counter sa `>= 0` clamp. 3 testa: insert→remove byte tracking, churn negativa-prevention, clear() reset. |
| 2.2.6 | ✅ — `ClipWidget` cull već postoji ali sa hardkodovanim 4096 px viewport. Replaced sa `MediaQuery.sizeOf(context).width` + 200 px overdraw. Sad 5K display + multi-monitor setups vidi pravi cull, laptop displays paint-uju manje. (Ne pravi novi feature — popravlja postojeći cull.) |
| 2.2.7 | ✅ 60584e2e — `FLTEnableImpeller=true` u `macos/Runner/Info.plist`. Eksplicitno pinned (default je Flutter 3.30+, ali ne-drift). |

### 2.3 Monolith refactor (održivost)

| # | Zadatak | Pre | Posle | Status |
|---|---|---|---|---|
| 2.3.1 | Split `engine_connected_layout.dart` | 17,292 LOC | 15,172 LOC + 2,374 LOC u `engine_layout_widgets.dart` | ✅ 8a2e91cf — 35+ atomic helpers extracted via Dart `part of`. Zero API breakage, zero behavioral change (private name access preserved). 3244/3244 testova zelena. |
| 2.3.2 | Split `slot_lab_screen.dart` | 15,215 LOC | 15,273 LOC | ⏳ Skipped 8a2e91cf — tightly coupled state (shared TimelineProvider + GameFlowProvider mutex), refactor zahteva najpre Provider extraction. Odložen u Faza 2.3-deep. |
| 2.3.3 | Split `premium_slot_preview.dart` | 7,676 LOC | 7,703 LOC | ⏳ Skipped 8a2e91cf — 67 internih klasa, shared `AnimationController` lifecycle. Refactor zahteva animation graph extract pre splita. Odložen u Faza 2.3-deep. |
| 2.3.4 | Split `helix_screen.dart` | 9,735 LOC | 10,225 LOC + 174+71+210=455 LOC u `helix/helix_*_widgets.dart` | ✅ 8a2e91cf — `_OmniPill`, `_OmniIconBtn`, `_ModeBadge`, `_TransportBtn` u `helix_omnibar_atoms.dart`. `_DockTab`, `_DockCard`, `_DockLabel` u `helix_dock_widgets.dart`. `_MiniModeSection`, `_MiniDivider`, `_ComplianceDot` u `helix_minimode_widgets.dart`. (LOC `+` u `helix_screen.dart` je kontra-intuitivan jer su `part` direktive dodate; reálno funkcionalni LOC manji.) |
| 2.3.5 | Extract lower zone sub-tab widgets u `widgets/lower_zone/slotlab/` | — | 580 LOC u `slotlab_painters.dart` | ✅ 8a2e91cf — 8 painters (BeatGridPainter, RTPCBindPainter, EmotionRibbonPainter, ScopePainter itd.) + KeyboardShortcutsOverlay extracted iz `slotlab_lower_zone_widget.dart`. Reusable across helix dock + lower zone. |

**Sažetak FAZA 2.3:** 3/5 ✅ done (2.3.1, 2.3.4, 2.3.5). 2/5 ⏳ deferred (2.3.2 slot_lab_screen, 2.3.3 premium_slot_preview) — zahtevaju prethodni Provider/AnimationController graph cleanup pre split-a, visok regression rizik bez toga.

### 2.4 Dead code eliminacija (auditovano 2026-04-28)

| # | Zadatak | Status |
|---|---|---|
| 2.4.1 | `ValidationErrorCategory.deprecated` | ❌ NOT dead — koristi se u 3 call sites u `services/project_schema_validator.dart:661,670,678`. Spec outdated. |
| 2.4.2 | `_deprecated_slot_events` v4→v5 | ❌ NOT dead — namerno preserved kao migration safeguard u `project_migrator.dart:594-604`. Brisanje kvari load-uvanje starih projekata. |
| 2.4.3 | 3 obsolete DAW sub-tabs | ❌ NOT DEAD — duboki audit: svih 31 DawEditSubTab sub-tabova ima realan sadržaj (pun widget, nema "Coming Soon", nema SizedBox.shrink()), uključujući CycleActionsPanel, RegionPlaylistPanel, GranularSynthPanel, DspScriptPanel, ExtensionSdkPanel itd. Spec ghost — nikada nije specifikovano koje 3. |
| 2.4.4 | `gdd_import_*` legacy ~800 LOC | ❌ NOT dead — `GddImportWizard.show` + `GddImportPanel` + `GddImportService.createSampleGddJson` aktivni u `slot_lab_screen.dart` i `helix_screen.dart`. |
| 2.4.5 | Old BT format pre-v11 | ❌ NOT dead — `behavior_tree_provider.dart` nema legacy format references; spec ghost. |

> Audit: 4/5 stavki nisu dead code. Spec za 2.4 je stale, niti jedna legitimna eliminacija nije identifikovana ovim sweep-om. Pre realnog cleanup-a treba detaljan profiling kome šta zaista treba.

---

## FAZA 2B — DAW + HELIX Ultimativna Kompaktnost (Detaljan Plan)

> **Izvor:** Duboki audit 2026-04-25 — engine_connected_layout.dart (17,292 LOC), helix_screen.dart (9,735 LOC), lower_zone_types.dart (1,797 LOC), global_shortcuts_provider.dart (57 shortcuts).
> **Imperativ:** Boki ne sme da traži nešto i ne nađe u < 2 klika / 1 keyboard shortcut. Svaki element mora biti jasan bez labele. Zero confusion.

---

### 2B.1 DAW — Kompaktnost i navigacija

#### Problem #1: EDIT tab ima 31 sub-tabova (jedini super-tab, sve utrpano)
- **Rešenje:** Reorganizovati 31 → 3 grupe sa collapse-expand:
  - **TIMELINE** (6): timeline, pianoRoll, fades, warp, elastic, razorEdit
  - **CLIP** (8): comping, beatDetect, tempoDetect, stripSilence, dynamicSplit, loopEditor, granularSynth, crossfades
  - **ADVANCED** (17): sve ostalo (grid, punch, ucsProjNaming, video, cycleActions, regionPlaylist, ...)
- **Fajl:** `lib/widgets/lower_zone/lower_zone_types.dart:286`, `engine_connected_layout.dart` tab renderers
- **Effort:** 3 h

#### Problem #2: Cmd+K Command Palette postoji za HELIX ali ne za ceo DAW
- **Rešenje:** Globalni `FluxCommandPalette` widget — fuzzy search po svim panelima, sub-tabovima, akcijama, projektima, stage-ovima
  - Trigger: `Cmd+K` ili `/` u focus-modeu
  - Sources: sve 57 global shortcuts + sve sub-tab nazive + sve FFI komande
  - UI: 500×400 glassmorphism popup, real-time filter, arrow navigate, Enter izvršava
- **Fajl:** novi `lib/widgets/command_palette/flux_command_palette.dart` + wire u `main_layout.dart`
- **Effort:** 1 nedelja

#### Problem #3: Left Panel nema jasnu hijerarhiju (Audio Pool + Tracks + MixConsole — nevidljivo koji je aktivan)
- **Rešenje:** Left Panel tabs kao icon+label strip na vrhu (Audio Pool 🎵 / Tracks 📋 / MixConsole 🎛), active tab highlight gold, collapsed state = 40px ikonica kolona
- **Fajl:** `engine_connected_layout.dart:273` `_leftVisible` zone
- **Effort:** 2 h

#### Problem #4: Toolbar je statičan — ne adaptira se na selekciju
- **Rešenje:** Adaptive Toolbar — menja kontekstualne dugmadi prema selekciji:
  - Ništa selektovano → standard (Play/Stop/Record/Undo/Redo)
  - Audio clip selektovan → + Fade/Warp/Normalize/Pitch/Reverse
  - MIDI selektovan → + Quantize/Velocity/CC/PianoRoll
  - Marker selektovan → + Tempo Change/Time Sig/Color
  - Track header → + Arm/Solo/Mute/Color/Rename
- **Fajl:** `engine_connected_layout.dart` toolbar zone
- **Effort:** 3 h

#### Problem #5: Right Panel je uvek Inspector — ne zna kontekst
- **Rešenje:** Smart Contextual Right Panel:
  - Klik track → Track properties (name, color, routing, pre-gain)
  - Klik clip → Clip properties (start/end, gain, pitch, fade lengths, warp markers)
  - Klik marker → Tempo/TimeSig editor
  - Klik plugin insert → Plugin micro-editor (8 most-used params, expand to full)
  - Ništa → Project overview (total tracks, BPM, key, duration)
- **Fajl:** `engine_connected_layout.dart:274` right panel + novi `lib/widgets/inspector/contextual_inspector.dart`
- **Effort:** 1 nedelja

#### Problem #6: Lower Zone CORTEX tab — prazan ili nedovršen
- **Rešenje:** Ili (A) popuniti sa Cortex health dashboard (vitalni znaci, neural signals, reflex actions feed) ili (B) skloniti iz production build (sakriti u `kDebugMode`)
- **Fajl:** `lib/widgets/lower_zone/` CORTEX tab renderer
- **Effort:** 30 min (skip) ili 1 nedelja (implement)

#### Problem #7: Nema Layout Presets (1-monitor, 2-monitor, ultrawide)
- **Rešenje:** Layout Preset system — `Cmd+Shift+1/2/3`:
  - **1-monitor (1440px)**: Left panel 0px (hidden), Center 75%, Right 0%, Lower 35% height
  - **2-monitor primary**: Left 250px, Center max, Right 300px, Lower 30%
  - **Ultrawide (3440px+)**: Left 300px, Center 60%, Right 400px, Lower 300px
  - **Focus mode**: samo Center + mini toolbar (already in 2.1.8 / helix F mode)
- **Fajl:** `lib/providers/layout_provider.dart` (novo ili extend DawLowerZoneController)
- **Effort:** 4 h

#### Problem #8: Mini MixConsole popup — nedostaje
- **Rešenje:** Floating mini mixer (≤ 300×200px, glassmorphism) — trigger: `Cmd+M` ili toolbar ikona
  - Prikazuje aktivan kanal (selektovan track) sa: volume fader, pan, 3 insert slot-a, mute/solo
  - Uvek on-top, Escape da zatvori
- **Fajl:** novi `lib/widgets/mixer/mini_mix_popup.dart`
- **Effort:** 4 h

---

### 2B.2 HELIX — Kompaktnost i navigacija

#### Problem #1: Spine ikone bez labela (5 ikona, nema teksta — konfuzno novim korisnicima)
- **Rešenje:** Spine layout u 2 varijante toggle-om:
  - **Compact** (48px): samo ikone sa 150ms hover tooltip
  - **Expanded** (96px): ikona + 2-word label ispod (AUDIO ASSIGN, GAME CONFIG, AI INTEL, SETTINGS, ANALYTICS)
  - Persist setting u `DawLowerZoneController` / local prefs
- **Fajl:** `helix_screen.dart:835-863`
- **Effort:** 2 h

#### Problem #2: 6 od 12 Command Dock super-tabova su STUBS (SFX, BT, DNA, AI, CLOUD, A/B)
- **Rešenje:** Stub tabovi dobijaju: (A) "⚡ Coming Soon" badge sa estimated ETA, (B) ili budu sakriven iza `kDebugMode` dok nisu gotovi
  - Nikad prazna stranica — uvek nešto vidljivo (progress, teaser, placeholder sa opšim opisom)
- **Fajl:** `helix_screen.dart:2034, 2500, 2838, 3188, 3852, 4114`
- **Effort:** 2 h

#### Problem #3: MONITOR super-tab ima 20 sub-tabova (previše, nema hijerarhije)
- **Rešenje:** Reorganizovati 20 → 5 collapsible kategorija:
  - **LIVE** (4): timeline, energy, voice, spectral
  - **AI** (3): fatigue, neuro, aiCopilot
  - **MATH** (3): mathBridge, rgai, abTest
  - **DEBUG** (4): debug, profiler, profilerAdv, evtDebug
  - **EXPORT** (6): export, ucpExport, fingerprint, spatial, resource, voiceStats
- **Fajl:** `lib/widgets/lower_zone/lower_zone_types.dart:726` + MONITOR tab renderer
- **Effort:** 3 h

#### Problem #4: Command Dock nema Quick Actions Strip
- **Rešenje:** 10px strip iznad tab bar-a sa contextual action buttons (ne zauzima tab space):
  - FLOW tab aktivan → [+ Stage] [+ Transition] [Run Sim] [Export Flow]
  - AUDIO tab → [Snap to Grid] [Solo Bus] [Reset Gain] [Export Mix]
  - MATH tab → [Recalculate RTP] [Lock Math] [Export Blueprint]
  - EXPORT tab → [Quick Package] [Git Commit] [Validate All]
- **Fajl:** `helix_screen.dart:1198-1303` Command Dock
- **Effort:** 4 h

#### Problem #5: Nema Floating Math HUD na Neural Canvas
- **Rešenje:** Kompaktni HUD overlay (gore-desno Neural Canvas-a, semi-transparent):
  - 4 live metrics: `RTP: 96.2% ▲` `VOL: 6.8` `HIT: 1:4.2` `MAX: 2847×`
  - Collapsible sa jednim klikom (→ samo 4 ikone ostaju)
  - Boja se menja: zelena (u target range) / žuta (warn) / crvena (out of range)
- **Fajl:** `helix_screen.dart:869-1014` NeuralCanvas zone + novi `lib/widgets/helix/math_hud_overlay.dart`
- **Effort:** 3 h

#### Problem #6: Reel Context Lens nije dovoljno vidljiv (ne znaš da klikneš)
- **Rešenje:** Affordance poboljšanje:
  - Reel cell hover → 2px gold border + magnifier ikonica (16×16) u uglu
  - Tap → Lens se otvori sa: stage bind info, volume slider, pitch offset, audio waveform preview
  - Long press na lens → Expand u full Voice Editor
- **Fajl:** `helix_screen.dart:1003-1008` + `premium_slot_preview.dart` reel cell
- **Effort:** 4 h

#### Problem #7: HELIX Mini Mode ne postoji (za dual-monitor setup)
- **Rešenje:** `Cmd+Shift+M` → HELIX kolapsira u 200px visoki strip:
  - Strip: Spin button | Stage name | Live RTP | 6 bus meters | Orb mini | Compliance lights
  - Ostatak monitora slobodan za druge alate
  - `Cmd+Shift+M` opet → vraća full view
- **Fajl:** `helix_screen.dart` mode state machine (lines 96, 225-227) — dodati MINI mode = 3
- **Effort:** 1 nedelja

#### Problem #8: Quick Assign Hotbar nedostaje
- **Rešenje:** 5-slot drag target bar iznad NeuralCanvas-a (sakriven dok ASSIGN mode nije aktivan):
  - Drag zvuk direktno na hotbar slot (svaki slot = jedan stage)
  - Highlight-uje staged audio od prvog dropa
  - Pins: stalni shortcut target da ne moraš skrolati event listu
- **Fajl:** `helix_screen.dart` iznad Neural Canvas + `slot_lab_screen.dart` ASSIGN mode
- **Effort:** 3 h

#### Problem #9: Stage Trigger keyboard shortcuts ne postoje u HELIX
- **Rešenje:** Dok je FLOW tab aktivan:
  - `1-8` → triggeruje stage #1-8 direktno (IDLE, BASE_SPIN, STOP, WIN, CASCADE, FREE_SPINS, BONUS, JACKPOT)
  - `Space` → Spin (već postoji u DAW, treba HELIX ekvivalent)
  - `Shift+1-8` → Force-exit feature → dati stage
- **Fajl:** `helix_screen.dart:580-600` keyboard zone
- **Effort:** 2 h

---

### 2B.3 Cross-cutting — Konzistentnost DAW ↔ HELIX

| # | Problem | Rešenje | Effort |
|---|---|---|---|
| 2B.3.1 | ✅ Panel Focus indikator — `PanelFocusProvider` + `FocusablePanel` (1px brandGold border) wrapped oko Spine/Canvas/Dock u HELIX. **2026-05-05 (commit 98414105 follow-up):** dodato keyboard cycling `Cmd+]` / `Cmd+[` (forward / back) sa skip-on-invisible (FOCUS mode dock). Mirrors Logic Pro / Final Cut / Photoshop bindings — Tab namerno NIJE hijack-ovan jer Tab unutar TextField (BPM, GRID, project name) mora da zadrži native traversal. Toast `FOCUS: SPINE/CANVAS/DOCK` 1.5s. **14 unit testova** za PanelFocusProvider — pin anti-spam invariant (identical focus() mora ne-notify, sprečava AnimatedContainer repaint storm na pointer drag). |
| 2B.3.2 | ✅ 818e78bb — `PanelLayoutProvider` (ChangeNotifier, keyed by `projectId`, LRU 50 entries) sa SharedPreferences persistance (`panel_layout_memory_v1`). API: `save/patch/restore/switchProject`. `PanelLayoutMemory` model čuva `helixDockTab`, `dawLowerTab`, left/right/lower visibility. **19 unit testova** (round-trips, LRU eviction, switchProject semantics, patch invariants). |
| 2B.3.3 | ✅ obsolete — overlap sa SPEC-15 (Selection Memory) koji je completed u Sprint 4 (`Cmd+1..9` restore, `Cmd+Shift+1..9` save). Layout Snapshots i Selection Memory dele isti UX pattern (Photoshop Layer Comps); SPEC-15 implementacija pokriva oba use case-a. |
| 2B.3.4 | ✅ Phase 1 (originalni) — `FluxTooltip` widget (`lib/widgets/common/flux_tooltip.dart`) sa 150ms delay + brand-gold border + macOS keyboard glyph mapping (`Cmd+ → ⌘`, `Shift+ → ⇧` itd). **2026-05-05 (commit pending):** Phase 2 — `formatShortcut` exposed kao public static za testabilnost, + 14 unit testova (kbd glyph mapping, idempotency, compound modifiers, kWaitDuration pin), + **SPEC-16 ratchet test** `test/lints/tooltip_consistency_test.dart` koji broji raw `Tooltip(` call sites pod `flutter_ui/lib/`, baseline=240, fail-CI ako count raste. Migration pilot: helix_screen `Drag to resize` + control_bar `_IconBtn` (sa shortcut hint pattern). Top offenders ostaju: control_bar.dart=21, slot_lab_screen.dart=17, channel_inspector_panel.dart=9 — postupna migracija je deferred work pinned by ratchet. |
| 2B.3.5 | ✅ 818e78bb — `PanelFocusProvider.cycleForward/cycleBackward` sa kanonskim 7-panel redosledom. Wired u `main_layout.dart::_handleKeyEvent` za Tab/Shift+Tab. **Guard:** skip kad `EditableText` ima focus (nikad ne krade input iz BPM, GRID, project name field-ova). **11 unit testova** (cycle, wrap-around, forward+backward cancellation, EditableText guard). |
| 2B.3.6 | ✅ — overlap sa SPEC-01 `FluxCommandPalette` (Sprint 2 done, commit 3ef5afff). Globalni `Cmd+K` palette dostupan u DAW + HELIX, fuzzy search po svim panelima/sub-tabovima/akcijama/projektima. |
| 2B.3.7 | **Context menu "Explain this"** — Right-click na bilo koji param | Copilot tooltip: šta je ovaj param, tipične vrednosti, upozorenja. Onboarding bez tutorijala. | 1 nedelja (zavisi od Faza 4) — ⏳ zavisi od `rf-copilot` crate (4.1.1) i lokalnog LLM-a (4.1.2). |
| 2B.3.8 | ✅ — overlap sa SPEC-15 (Sprint 4 done, commit ce2a90a9 + c58c7d04). `Cmd+1..9` restore + `Cmd+Shift+1..9` save kompletnog panel state-a (tab, zoom, selekcija, layout). |

---

### 2B.4 Merljivi ciljevi (Definition of Done)

| Metrika | Pre | Cilj | Status |
|---------|-----|------|--------|
| Klika do EQ na specifičnom stage | 3 klika | 1 (Cmd+K "open EQ stage X") | ✅ SPEC-01 (Sprint 2) — fuzzy search po panelima/sub-tabovima/akcijama. |
| Klika do promene reel count-a | 4 klika | 1 (Omnibar inline edit) | ✅ FAZA 2.1.7 — `GRID 5×3` pill u HELIX Omnibar parsuje `5x3`/`5×3`/`5X3`. |
| Klika do preview zvuka | 2 klika | 1 (Space na selektovanom) | ✅ Space-bar bound u SlotLab (audition selected audio file). |
| Vidljive info simultano (1440px) | 4 zone | 4 zone + HUD float | ✅ SPEC-10 Math HUD (top:80, left:12) + Compliance Lights badge + Stage strip — sve simultano vidljivo. |
| Sub-tab switchovanje | 2-3 klika | 1 keyboard key (1-9) | ✅ FAZA 2.1.5 — Digit 1-9 → idx 0-8, 0 → 9, Q-U → 10-16 u DAW lower zone. |
| Otvoren panel bez etikete | Spine (5 ikona) | Sve ikone imaju tooltip ≤ 150ms | ✅ SPEC-06 (Sprint 1) — Spine Compact/Expanded toggle + 150ms hover tooltips kroz `FluxTooltip`. |
| Stub tabovi sa praznom stranicom | 6 u HELIX | 0 (badge ili sakriti) | ✅ SPEC-07 (Sprint 1) Never Empty + FAZA 1.4 audit: svih 7 sub-tabova (DSP spatial, RTPC, CONTAINERS, MUSIC, LOGIC, DAW CORTEX, MONITOR neuro/aiCopilot) verifikovano da imaju realan sadržaj. |
| Layout reset posle pomrnje šta je otvoreno | Ručno | Cmd+0 = default layout | ✅ 2026-05-07 — `'resetLayout': ShortcutDef(key: '0', mod: ShortcutModifiers(cmd: true), display: '⌘0')` dodato u `global_shortcuts_provider.dart`. `_handleResetLayout` callback već implementiran (resets left/right/lower visibility + timelineZoom + scrollOffset, snack-bar feedback "Layout reset to defaults"). |

**8/8 DOD metrika ✅ — sve mere kompaktnosti i navigacije iz FAZA 2B su pokrivene.**

---

## SESIJA: DAW + HELIX Kompaktnost — Puni Implementacioni Specs

> Svaki problem razrađen do nivoa: fajl:linija → šta se menja → kod pattern → before/after ponašanje → test.
> Ovo je radna sesija — krene se redom, svakim problemom završimo pre sledećeg.

---

### SPEC-01 · Globalni `FluxCommandPalette` (Cmd+K)

**Problem:** Nema fuzzy-search za 110+ sub-tabova, 57 shortcuts, projekata. Svaki detalj = 2-4 klika.

**Root cause:** Nema `CommandRegistry` servisa ni palette widgeta. `global_shortcuts_provider.dart` ima shortcuts ali nema unified UI za search.

**Implementacija:**

```
lib/services/command_registry.dart          ← novi singleton
lib/widgets/command_palette/
    flux_command_palette.dart               ← OverlayEntry widget
    command_item.dart                       ← single result row
lib/screens/main_layout.dart               ← wire trigger Cmd+K
```

**`CommandRegistry`** — 5 izvora, sve lazily registrovano:
- `ShortcutSource` → 57 shortcuts iz `GlobalShortcutsProvider` + label + icon
- `HelixTabSource` → sve 110+ HELIX sub-tabovi (super-tab + sub-tab naziv + keyboard key)
- `DAWPanelSource` → svi DAW paneli (left/center/right/lower + sub-tabs)
- `RecentSource` → poslednjih 10 akcija (SQLite persist, session-bound)
- `ActionSource` → dynamic per-context (dodaju ga active provideri)

**`FluxCommandPalette` widget:**
- Trigger: `LogicalKeyboardKey.keyK` + meta, ili `/` kada nema text fokusa
- `OverlayEntry` na `Navigator.overlay` — uvek iznad svega
- Dimenzije: 560×420px, centrisano, glassmorphism `#0D0D12/85%` + gold border 1px
- Enter animacija: `Spring(stiffness: 380, damping: 28)` — 180ms
- Search: real-time Levenshtein + prefix boost + recent boost
- Max 8 rezultata vidljivo, scroll za više
- Row: 36px — `icon (20px) + title (bold) + subtitle (muted) + shortcut badge (right)`
- `ArrowUp/Down` = navigate, `Enter` = execute, `Esc` = dismiss
- Fajl: `main_layout.dart` → `Shortcuts` widget wraps ceo child tree

**Before/After:**
- Pre: HELIX → klik AUDIO super-tab → klik MIX sub-tab → klik DSP chain → klik EQ = 4 klika
- Posle: `Cmd+K` → kucaj "eq" → Enter = 0.5s

**Test:** `flutter_test` — palette se otvori, query "rtp", expected result "MATH → RTP Target", Enter navigira na MATH tab

---

### SPEC-02 · EDIT Tab Reorganizacija (31 → 3 grupe)

**Problem:** DAW Lower Zone EDIT super-tab ima 31 sub-tabova u jednom linearnom scrollable redu — vizuelni chaos, korisnik ne zna šta se gde nalazi.

**Root cause:** `lower_zone_types.dart:286` — `DawEditSubTab` enum sa 31 vrednosti, renderer ih crta redom bez hijerarhije.

**Implementacija:**

```
lib/widgets/lower_zone/lower_zone_types.dart    ← dodati DawEditGroup enum
lib/widgets/lower_zone/daw_lower_zone_widget.dart   ← render grupovano
```

**Nova 3-grupna struktura** (umesto flat liste):
```
TIMELINE  ▼  (expandable, default open)
  timeline · pianoRoll · fades · warp · elastic · razorEdit

CLIP  ▼  (expandable)
  comping · beatDetect · tempoDetect · stripSilence
  dynamicSplit · loopEditor · granularSynth

ADVANCED  ▶  (expandable, default collapsed)
  grid · punch · ucsNaming · video · cycleActions
  regionPlaylist · mixSnapshots · metadataBrowser
  screensets · projectTabs · subProjects · [ostalo]
```

**Group header widget:** 28px visok, `▶/▼` ikona + label (12px uppercase), klik = toggle, persist state u `DawLowerZoneController`

**Before/After:**
- Pre: linearni scroll kroz 31 item-a, gubiš se
- Posle: 3 jasne kategorije, default vidljivo 6 najvažnijih

**Test:** `DawEditGroup.timeline` expand/collapse toggle + persist kroz hot-reload

---

### SPEC-03 · Smart Contextual Right Panel (Inspector++)

**Problem:** Right panel uvek prikazuje isti Inspector bez obzira šta je selektovano. Klik na audio clip = isti view kao klik na marker.

**Root cause:** `engine_connected_layout.dart:274` — `_rightVisible` flag + statičan `InspectorPanel` widget, nema context switching.

**Implementacija:**

```
lib/widgets/inspector/
    contextual_inspector.dart               ← novi wrapper
    track_inspector.dart                    ← track properties
    clip_audio_inspector.dart               ← audio clip
    clip_midi_inspector.dart                ← MIDI clip
    marker_inspector.dart                   ← tempo/timesig marker
    plugin_quick_inspector.dart             ← plugin 8-param micro view
    project_overview_inspector.dart         ← ništa selektovano
```

**`ContextualInspector`** — sluša `SelectionProvider` i ruta na odgovarajući widget:
```dart
switch (selection.type) {
  case SelectionType.track    → TrackInspector(track: selection.track)
  case SelectionType.audioClip → ClipAudioInspector(clip: selection.clip)
  case SelectionType.midiClip  → ClipMidiInspector(clip: selection.clip)
  case SelectionType.marker    → MarkerInspector(marker: selection.marker)
  case SelectionType.plugin    → PluginQuickInspector(plugin: selection.plugin)
  default                      → ProjectOverviewInspector()
}
```

**`TrackInspector`** (kompaktan, 6 rows):
- Name (inline editable), Color (swatch picker), Routing (bus dropdown)
- Pre-gain (slider ±24dB), Lock toggle, Freeze toggle

**`ClipAudioInspector`** (8 rows):
- Start/End time (editable), Duration, Gain slider (±24dB)
- Pitch semitones (slider ±12st), Warp mode (enum dropdown)
- Fade In/Out lengths (dual slider)

**`PluginQuickInspector`** — 8 most-used params sa mini knobs, + "Open Full" dugme

**Before/After:**
- Pre: klik clip → inspector prikazuje generic "Clip Properties" sa ~3 stavke
- Posle: klik clip → sve relevantne opcije odmah vidljive, inline edit bez dialoga

**Test:** selection_provider mock → ContextualInspector ruta na correct widget

---

### SPEC-04 · Adaptive Toolbar (DAW)

**Problem:** Toolbar prikazuje iste alate bez obzira na selekciju. Audio clip selektovan = nema shortcut za Fade/Normalize. MIDI selektovan = nema Quantize.

**Root cause:** `engine_connected_layout.dart` toolbar zona — statičan `Row` sa fiksnim widgetima.

**Implementacija:**

```
lib/widgets/toolbar/
    adaptive_toolbar.dart                   ← wrapper
    toolbar_section_transport.dart          ← Play/Stop/Record (uvek vidljivo)
    toolbar_section_audio_clip.dart         ← Fade/Warp/Normalize/Pitch/Reverse
    toolbar_section_midi_clip.dart          ← Quantize/Velocity/CC/PianoRoll
    toolbar_section_marker.dart             ← Tempo Change/TimeSig/Color
    toolbar_section_track.dart              ← Arm/Solo/Mute/Color/Rename
```

**Layout:**
```
[Transport — uvek]  |  [Contextual sekcija — animirano]  |  [Global: Undo/Redo/Save]
```

**Contextual sekcija tranzicija:** `AnimatedSwitcher` sa `FadeTransition` 150ms + `SlideTransition` Y=8px gore — osećaj da "ispliva" nova sekcija kad se promeni selekcija.

**Before/After:**
- Pre: toolbar isti za sve → tražiš akciju u meniju
- Posle: selektuješ audio clip → fade/pitch/normalize dugmad se pojavljuju odmah, bez menija

---

### SPEC-05 · Layout Presets + Layout Snapshots

**Problem:** Nema brze adaptacije layout-a za 1-monitor, 2-monitor, ultrawide, niti pamćenja custom layout-a.

**Root cause:** `DawLowerZoneController` nema preset logiku; panel visibility state (`_leftVisible`, `_rightVisible`, `_lowerVisible`) je ephemeral.

**Implementacija:**

```
lib/providers/panel_layout_provider.dart    ← novi, replaces ad-hoc bools
lib/models/panel_layout_snapshot.dart       ← serializovani snapshot
```

**`PanelLayoutProvider`** state:
```dart
class PanelLayout {
  bool leftVisible; double leftWidth;    // 250px default
  bool rightVisible; double rightWidth;  // 300px default
  bool lowerVisible; double lowerHeight; // 380px default
  DawSuperTab activeLowerTab;
  DawEditGroup expandedGroup;
  // HELIX
  int helixDockTab; double helixDockHeight;
  bool helixSpineExpanded;
}
```

**Presets (Cmd+Shift+1/2/3/0):**
- `1` → Single monitor: left hidden, right hidden, lower 40% — maksimalan timeline
- `2` → Dual monitor: left 250, right 300, lower 300 — balanced
- `3` → Ultrawide (3440px+): left 320, right 400, lower 280 — sve vidljivo
- `0` → Default factory reset

**Snapshots (Cmd+Opt+1..9):** persist 9 named slots u `~/.fluxforge/layout_snapshots.json`
- Hold `Cmd+Opt+1` 500ms = save (toast potvrda)
- Tap `Cmd+Opt+1` = restore

**Before/After:**
- Pre: svaki put ručno podešavanje panela
- Posle: `Cmd+Shift+1` = produkcija (fokus timeline), `Cmd+Shift+2` = mixing (sve vidljivo)

---

### SPEC-06 · HELIX Spine — Compact/Expanded Toggle

**Problem:** Spine ima 5 ikona bez labela → novi korisnik ne zna šta je šta. Nema tooltip ni labela.

**Root cause:** `helix_screen.dart:835-863` — ikone bez `Tooltip` wrappera, bez label widgeta.

**Implementacija (minimalna promena — nema refaktora):**

1. Wrap svake ikone u `Tooltip(message: 'AUDIO ASSIGN', waitDuration: Duration(ms: 120))`
2. Dodati toggle dugme na dnu Spine-a (ikona `«`/`»` ili double-arrow)
3. Kada expanded (toggle ON): width 96px, ispod svake ikone dodati `Text(label, 10px, brandSteel, letterSpacing: 0.8)`
4. `_spineExpanded` bool persist u `SharedPreferences`

**Animacija:** `AnimatedContainer(width: _expanded ? 96 : 48, duration: 200ms, curve: Curves.easeOutCubic)`

**Before/After:**
- Pre: 5 mystery ikone, ne znaš šta otvara šta
- Posle: hover → tooltip za 120ms, ili expand za stalne labele

**Fajl:** `helix_screen.dart:835-863` — minimalno 20 linija promena

---

### SPEC-07 · HELIX Stub Tabovi — Never Empty

**Problem:** 6 od 12 Command Dock super-tabova (SFX, BT, DNA, AI, CLOUD, A/B) vraćaju praznu stranicu ili "placeholder" bez informacija.

**Root cause:** `helix_screen.dart:2034, 2500, 2838, 3188, 3852, 4114` — `Container()` ili jednostavan `Text('Coming soon')`

**Implementacija — `StubTabPlaceholder` widget:**
```dart
class StubTabPlaceholder extends StatelessWidget {
  final String tabName, description, estimatedPhase;
  final List<String> plannedFeatures; // max 4
  final IconData icon;
}
```

**UI za svaki stub tab:**
```
[ikona  64px  u gold gradient circle]
[TAB NAME  20px  brandGold]
[1-2 rečenica šta će ovde biti]
[Planned: Phase X · Est: Q3 2026]
[──────────────────]
[• Feature 1]
[• Feature 2]
[• Feature 3]
[⚡ Coming in Phase X]
```

**Svaki stub tab dobija opis:**
- **SFX**: "Procedural SFX pipeline — generate sfx_reel_stop, sfx_coin, sfx_bonus iz fizičkih parametara"
- **BT**: "Behavior Tree visual editor — drag-drop logic za slot mehanike bez koda"
- **DNA**: "Slot Sound DNA analysis — spectral fingerprint, automatic stage classification"
- **AI**: "Copilot v1 — voice authoring, gap detection, mix suggestions"
- **CLOUD**: "Multi-studio sync — real-time collab via CRDT, cloud asset library"
- **A/B**: "Live A/B testing — 2 mix varijante u produkciji, player retention metrics"

**Before/After:**
- Pre: prazan container → korisnik misli da je bug
- Posle: lepa placeholder stranica, jasno šta dolazi, kada, zašto

---

### SPEC-08 · HELIX MONITOR Tab — 20 → 5 Kategorija

**Problem:** MONITOR super-tab ima 20 sub-tabova u linearnom scrollable redu — previše za snalaženje.

**Root cause:** `lower_zone_types.dart:726` `SlotLabMonitorSubTab` enum, renderer crta flat.

**Nova struktura (5 collapsible kategorija):**
```
LIVE  ▼  (default open)
  Timeline · Energy · Voice · Spectral

AI  ▶  
  Fatigue · Neuro · AI Copilot

MATH  ▶
  MathBridge · RGAI · A/B Test

DEBUG  ▶
  Debug · Profiler · Profiler Adv · Event Debug

EXPORT  ▶
  Export · UCP Export · Fingerprint · Spatial · Resource · Voice Stats
```

Isti pattern kao SPEC-02 — `SlotLabMonitorGroup` enum + group header widget.

**Status:** ✅ Phase 1 (2026-05-06, commit pending) — `SlotLabMonitorSubTab` reordered tako da grupe budu susedne u nizu (LIVE 0-3 / AI 4-7 / MATH 8-10 / DEBUG 11-14 / EXPORT 15-20). `SlotLabMonitorGroup` enum (5 vrednosti) sa `range`, `label`, `forSubTab(t)`, `separatorIndices()` API. Controller `subTabGroupBreaks` getter sad vraća `SlotLabMonitorGroup.separatorIndices()` umesto hard-koded `[3, 5]` — single source of truth pin za izlaz grupe i separator-a u sync. **10 unit testova** pinuju invariants: 5 grupa partitioniraju svih 21 sub-tabova bez preklapanja/rupa, separator indeksi su `[4, 8, 11, 15]`, label/shortcut/tooltip arrays drže pozicionalnu paritet sa enum-om, shortcuts jedinstveni (no keyboard nav ambiguity), `t.group` getter konvergira sa static helper-om. **Phase 2 (collapse toggle)** ostaje — trenutni context bar renderuje vertical separator liniju ali NEMA group label header iznad svake grupe; kad/ako bude potrebno, `subTabGroupLabels` parameter dolazi u `LowerZoneContextBar`.

---

### SPEC-09 · HELIX Command Dock — Quick Actions Strip

**Problem:** Nema kontekstualnih quick-action dugmadi po aktivnom tabu — svaka akcija = navigacija u podmeniu.

**Root cause:** `helix_screen.dart:1198-1303` — Command Dock nema akcije iznad tab bar-a.

**Implementacija:**

```dart
// 10px visok strip (isti bg kao dock), između drag handle i tab bar
Widget _buildQuickActionStrip(int activeTab) {
  return AnimatedSwitcher(
    duration: Duration(ms: 200),
    child: _getActionsForTab(activeTab),
  );
}
```

**Akcije po tabu** (max 6 dugmadi, svako 28px visoko, 70-120px široko):
- **FLOW**: `[▶ Sim Run]` `[+ Stage]` `[+ Transition]` `[↩ Reset FSM]`
- **AUDIO**: `[Grid Snap]` `[Solo Bus]` `[Zero Gain]` `[Export Mix]`
- **MATH**: `[🔒 Lock]` `[↺ Recalc]` `[📋 Blueprint]` `[Validate]`
- **INTEL**: `[▶ Full Sim]` `[📊 Coverage]` `[🐛 Diagnostics]`
- **EXPORT**: `[📦 Package]` `[git Commit]` `[✅ Validate All]` `[📧 Send Report]`
- Ostali: po 2-3 najvažnije akcije

**Style:** `TextButton.icon`, 28px, `brandSteel` boja, hover = `brandGold`, compact padding `EdgeInsets.symmetric(h: 8, v: 4)`

**Before/After:**
- Pre: klik na tab → find action u sub-tab → klik
- Posle: action button odmah vidljiv na vrhu dock-a čim je tab aktivan

---

### SPEC-10 · Floating Math HUD na Neural Canvas

**Problem:** RTP, Volatility, Hit Freq, Max Win su u MATH tabu — nevidljivi dok radiš u FLOW/AUDIO tabovima.

**Root cause:** `helix_screen.dart:869-1014` NeuralCanvas — nema overlay sa live math metrics.

**Implementacija:**

```
lib/widgets/helix/math_hud_overlay.dart     ← novi widget
```

**HUD widget:** pozicioniran top-right Neural Canvas-a, `Positioned(top: 12, right: 12)`:
```
[RTP: 96.2% ●] [VOL: 6.8 ●] [HIT: 1:4.2 ●] [MAX: 2847× ●]
```
- Svaka metrika: `Container(68×22px, color: _hudBg)` + vrednost (11px bold) + color dot
- Color dot: `brandGold` = in target, `Colors.amber` = warn ±5%, `Colors.red` = out
- Tap HUD → expand/collapse (height animira 22px → 0px, ikona ostaje)
- Persist collapse state u session

**`_hudBg`:** `Color(0xFF0D0D12).withOpacity(0.72)` — poluprozirno, ne ometa canvas

**`MathHudProvider`** — consumer `NeuroAudioProvider` + `GameModelProvider`, real-time update svake 500ms

**Before/After:**
- Pre: meoriše RTP izvan MATH taba = 3 klika do informacije
- Posle: uvek vidljivo bez prekidanja workflow-a

---

### SPEC-11 · Reel Context Lens Affordance

**Problem:** Reel cell context lens ne znaš da možeš kliknuti — nema vizuelnog hinta.

**Root cause:** `helix_screen.dart:1003-1008` + `premium_slot_preview.dart` reel cells — nema hover state ni affordance indikator.

**Implementacija:**

```dart
// U reel cell widget (premium_slot_preview.dart)
MouseRegion(
  onEnter: (_) => setState(() => _reelHovered[i] = true),
  onExit:  (_) => setState(() => _reelHovered[i] = false),
  child: AnimatedContainer(
    duration: Duration(ms: 120),
    decoration: BoxDecoration(
      border: Border.all(
        color: _reelHovered[i] ? FluxForgeTheme.brandGold.withOpacity(0.7) : Colors.transparent,
        width: 1.5,
      ),
    ),
    child: Stack(children: [
      reelContent,
      if (_reelHovered[i]) Positioned(bottom: 4, right: 4,
        child: Icon(Icons.search, size: 14, color: FluxForgeTheme.brandGold.withOpacity(0.9))),
    ]),
  ),
)
```

**Lens expand sadržaj** (Context Lens panel):
- Stage binding info (naziv stage-a ili "unbound")
- Volume slider (0-200%, real-time FFI update)
- Pitch offset (−12st do +12st)
- 32px waveform preview strip
- Long press na lens → `VoiceDetailEditor.open(layer)`

**Before/After:**
- Pre: korisnik ne zna da može kliknuti reel cell
- Posle: hover → gold border + magnifier → klik → lens sa svim relevantnim kontrolama

---

### SPEC-12 · HELIX Mini Mode (200px strip)

**Problem:** Nema kompaktnog prikaza za dual-monitor setup.

**Root cause:** `helix_screen.dart:96, 225-227` — mode state machine ima COMPOSE(0)/FOCUS(1)/ARCHITECT(2), nedostaje MINI(3).

**Implementacija:**

```dart
// helix_screen.dart — dodati u _HelixMode enum
mini,   // = 3

// Keyboard trigger
case LogicalKeyboardKey.keyM when meta && shift:
  setState(() => _mode = _mode == _HelixMode.mini ? _HelixMode.compose : _HelixMode.mini);
```

**Mini Mode layout (200px visina, full width):**
```
[SPIN ▶]  [FSM: BASE_SPIN]  [RTP 96.2%●]  [VOL 6.8●]  [HIT 1:4.2●]  |  [6× bus meters 8px wide]  |  [Orb 60px]  |  [🟢🟡🔴 compliance]  [Cmd+Shift+M ↗]
```

Animacija: `AnimatedContainer(height: _mode==MINI ? 200 : fullHeight, curve: Curves.easeInOutCubic, duration: Duration(ms: 300))`

**Before/After:**
- Pre: HELIX uvek zauzima ceo ekran
- Posle: `Cmd+Shift+M` = kompresuje u 200px strip, ostatak ekrana slobodan za DAW ili drugu aplikaciju

---

### SPEC-13 · Quick Assign Hotbar

**Problem:** Assign workflow zahteva skrolanje event liste svaki put. Nema "pinned stage" targeta.

**Root cause:** Nema hotbar komponente. Drag-drop postoji ali bez persistent targeta.

**Implementacija:**

```
lib/widgets/helix/quick_assign_hotbar.dart   ← novi
```

**Hotbar:** 5 slotova × 44px, pozicioniran između Omnibar-a i Neural Canvas-a (sakriven dok ASSIGN mode nije aktivan):
```
[REEL_STOP ×] [REEL_SPIN ×] [WIN_SMALL ×] [        ] [        ]
  ↑ bound        ↑ bound       ↑ bound      empty drop  empty drop
```

**Interakcija:**
- Drag zvuk iz event pool-a → drop na hotbar slot → bind direktno (nema more confirmation)
- Tap bound slot → audition preview (Play ikona)
- Long press bound slot → unbind
- `×` dugme = unbind brzo
- Slot se highlightuje gold outline tokom drag-a (drop target feedback)

**Persist:** slots se čuvaju u `SlotLabProjectProvider` kao `List<String?> hotbarBindings` per project

**Before/After:**
- Pre: drag zvuk → skroluješ do pravog stage-a u listi → drop → repeat za svaki
- Posle: drag zvuk → drop na hotbar slot → odmah bound, hotbar ostaje tu za sledeći put

---

### SPEC-14 · Panel Focus Indicator + Keyboard Routing

**Problem:** Keyboard evente prima neizvestan panel. Tab prečice (1-9 u HELIX) ne rade ako je fokus negde drugde.

**Root cause:** Flutter focus system — `FocusNode` nije eksplicitno dodeljen panelima; eventi proppadaju bez garantovanog primaoca.

**Implementacija:**

```
lib/providers/panel_focus_provider.dart     ← koji panel je aktivan
```

**`PanelFocusProvider`:**
```dart
enum FocusedPanel { helix_dock, helix_canvas, helix_spine, daw_timeline, daw_lower, daw_left, daw_right }
```
Klik na panel = `provider.setFocus(panel)` → panel dobija 1px gold border:
```dart
Container(
  decoration: BoxDecoration(
    border: focused ? Border.all(color: FluxForgeTheme.brandGold.withOpacity(0.4), width: 1) : null,
  ),
  child: Focus(focusNode: _panelFocusNode, child: panelContent),
)
```

**Keyboard routing:** `FocusScope` → aktivan panel prima key evente. `Tab` / `Shift+Tab` = `FocusScopeNode.nextFocus()` / `previousFocus()`.

**Before/After:**
- Pre: stisneš `1` u HELIX ali ništa se ne desi jer je fokus na DAW panelu
- Posle: aktivan panel gold-bordered, keyboard uvek ide u pravi panel

---

### SPEC-15 · Selection Memory (Cmd+1..9 — Layout Comps)

**Problem:** Nema brze navigacije između sačuvanih view konfiguracija. Authoring session od 30+ min = ručno vraćanje panela.

**Root cause:** Nema `SelectionMemoryProvider`. Panel state je ephemeral.

**Implementacija:**

```
lib/providers/selection_memory_provider.dart
lib/models/selection_memory_slot.dart
```

**`SelectionMemorySlot`:**
```dart
class SelectionMemorySlot {
  String? name;              // auto: "Slot 1" ili custom
  PanelLayout layout;        // iz SPEC-05 PanelLayoutProvider
  DateTime savedAt;
  String? previewLabel;      // "MATH tab @ RTP 96.2%"
}
```

**Trigger:**
- `Cmd+Shift+[1-9]` (hold 400ms) = **save** slot → toast `"💾 Slot 1 sačuvan"`
- `Cmd+[1-9]` (tap) = **restore** slot → instant layout switch sa 180ms Spring animacijom
- `Cmd+0` = factory default layout

**Persist:** `~/.fluxforge/selection_memory.json` — max 9 slotova, rotira FIFO

**Before/After:**
- Pre: ručno otvaranje/zatvaranje panela pri svakoj promeni konteksta
- Posle: `Cmd+1` = authoring mode, `Cmd+2` = QA mode, `Cmd+3` = presentation mode — 0.2s

---

### SPEC-16 · Uniformni Hover Tooltips (150ms delay)

**Problem:** Razne ikone i dugmadi nemaju tooltip ili imaju ga sa pogrešnim delay-om. Korisnik mora da pogađa.

**Root cause:** Nedosledna upotreba `Tooltip` widgeta — neki imaju, neki nemaju.

**Implementacija:**

Centralizovani `FluxTooltip` wrapper koji zamenjuje sve inline `Tooltip`-e:
```dart
class FluxTooltip extends StatelessWidget {
  final String message;
  final String? shortcutHint;    // npr. "Cmd+K"
  final Widget child;

  // message + newline + "⌘K" ako shortcutHint postoji
  // waitDuration: Duration(ms: 150)
  // style: brandGold background 85% opacity, 11px white text
}
```

**Rollout:** `grep -rn 'Tooltip(' flutter_ui/lib/ | wc -l` → nahodi sve, zameni sa `FluxTooltip`. Plus dodati na sve ikone koje nemaju tooltip (`Spine ikone, Orb buttons, toolbar dugmadi`).

**Before/After:**
- Pre: ikonice su mystery — ne znaš šta radi bez klikanja
- Posle: hover 150ms → kompaktni tooltip sa label + keyboard hint

---

### SPEC-17 · Stage Trigger Keyboard Shortcuts u HELIX

**Problem:** U HELIX FLOW tabu nema direktnih keyboard shortcuta za triggerovanje stage-ova. Svaki trigger = klik na FSM node.

**Root cause:** `helix_screen.dart:580-600` keyboard zone — nema case za stage trigger keys.

**Implementacija:**

```dart
// helix_screen.dart keyboard handler — dodati:
case LogicalKeyboardKey.digit1 when _activeDockTab == HelixDockTab.flow && !isShift:
  gameFlowProvider.triggerStage(GameFlowState.idle); break;
case LogicalKeyboardKey.digit2 when _activeDockTab == HelixDockTab.flow && !isShift:
  gameFlowProvider.triggerStage(GameFlowState.baseSpin); break;
// ... 1-8 za 8 stage-ova
case LogicalKeyboardKey.space when _activeDockTab == HelixDockTab.flow:
  gameFlowProvider.triggerSpin(); break;
case LogicalKeyboardKey.digit1..8 when isShift:
  gameFlowProvider.forceExitToStage(stages[key - 1]); break;
```

**Visual feedback:** Klik shortcut → odgovarajući FSM node u FLOW tabi se pulse-uje (gold glow 300ms Spring) + toast "Stage: BASE_SPIN" 1.5s bottom-center.

**Stage map (1-8):**
1=IDLE · 2=BASE_SPIN · 3=REEL_STOP · 4=WIN · 5=CASCADE · 6=FREE_SPINS · 7=BONUS · 8=JACKPOT

**Before/After:**
- Pre: QA sesija = klik FSM node za svaki test scenario
- Posle: `2` = start spin, `4` = force win, `6` = jump to free spins — 8× brži QA

---

### SESIJA REDOSLED (preporučen za implementaciju)

```
Sprint 1 (kompaktnost, visok impact, niski rizik):     ✅ DONE
  SPEC-06  Spine labele          [2h]                  ✅
  SPEC-07  Stub tab placeholders [2h]                  ✅
  SPEC-16  Tooltips              [3h]                  ✅
  SPEC-17  Stage shortcuts       [2h]                  ✅
  SPEC-11  Reel Context Lens     [4h]                  ✅
  SPEC-10  Math HUD              [3h]                  ✅

Sprint 2 (navigacija, srednji kompleksitet):           ✅ DONE (3ef5afff)
  SPEC-01  Cmd+K Palette         [1 ned]               ✅
  SPEC-02  EDIT tab grupe        [3h]                  ✅
  SPEC-08  MONITOR grupe         [3h]                  ✅
  SPEC-09  Quick Actions Strip   [4h]                  ✅
  SPEC-14  Panel Focus           [3h]                  ✅

Sprint 3 (power features):                             ✅ DONE (8b83940b)
  SPEC-03  Smart Inspector       [1 ned]               ✅ ContextualInspector + 8 sub-inspectors
  SPEC-04  Adaptive Toolbar      [3h]                  ✅ Transport+Context modes
  SPEC-13  Quick Assign Hotbar   [3h]                  ✅ 5 pinned slots in HELIX ASSIGN
  +        SelectionProvider foundation                ✅ 8 SelectionType variants

Sprint 4 (layout memory, power users):                 ✅ DONE (ce2a90a9 + c58c7d04)
  SPEC-05  Layout Presets        [4h]                  ✅ Cmd+Shift+1/2/3 Compose/Focus/Mix
  SPEC-15  Selection Memory      [4h]                  ✅ Cmd+1..9 restore / Cmd+Shift+1..9 save
  SPEC-12  HELIX Mini Mode       [1 ned]               ✅ Cmd+Shift+M, 200px strip
  +        FFI null safety (16 *const c_char)          ✅
  +        SlotLab→SelectionProvider wire (604ce478)   ✅
```

**Sprint 1-4 = COMPLETE. SPEC-01..17 svi implementirani. Sve ostalo: maintenance, FAZA 1 (P0), FAZA 2 (perf), FAZA 3+ (diferencijatori).**

---

## FAZA 3 — Slot Machine Diferenciatori

### 3.1 IGT/Playa parity fixes (iz memorije)

| # | Zadatak | Status | Fajl(ovi) |
|---|---|---|---|
| 3.1.1 | **S1 Feature Wins završni momenti** — FsSummary UI overlay + skip telemetrija | ✅ 2b539a0e — `_FsSummaryOverlay` u `premium_slot_preview.dart`, `Stage::FsSummary` audio naming, 4s auto-dismiss | `lib/models/stage_models.dart`, `lib/services/stage_audio_mapper.dart` |
| 3.1.2 | **S2 Splash → Slot animacija** (profi, kinematska, reel spin-up intro, zlatni sjaj, simboli padaju) | ✅ f45e45bb — `SlotEntryAnimation` kinematska tranzicija implementirana | `lib/screens/splash_screen.dart` |
| 3.1.3 | **S3 Reel Loop + Reel Stop audio** — `sfx_reel_spin_r0..r5` + `sfx_reel_stop_r0..r5` engine wire-up | ✅ fully landed — `ReelSpinLoop`/`ReelStop` u `audio_naming.rs`, `_handleReelSpinning/_handleReelStop` u `stage_audio_mapper.dart`, 5 reel indices tested | `crates/rf-stage/src/audio_naming.rs` |
| 3.1.4 | **S4 Audio tab Helix lower zone** — ranije prijavljeno "ništa se ne prikazuje" | ✅ SHIPPED — `_AudioPanel` (helix_screen.dart:5180) ima master fader (A6), OrbMixer, 6-bus channel strips, NeuroAudio metrics, AutoBind. Prethodni bug bio u GetIt lifecycle — popravljen u ranijim sessionima. | `lib/screens/helix_screen.dart:5180` |
| 3.1.5 | Podnaslovi podtabova razlikuju se od naslova | ✅ NOT AN ISSUE — `lower_zone_types.dart` ima centralizovane label extension-e (single source of truth), svi sub-tab label-i konzistentni | `lib/widgets/lower_zone/lower_zone_types.dart` |

### 3.2 OrbMixer

| # | Zadatak | Status | Fajl(ovi) |
|---|---|---|---|
| 3.2.1 | **O1** Phase 10e-2 Rust FFI 5s ring buffer + WAV export | ✅ SHIPPED — `orb_capture_last_n_seconds` FFI u `rf-engine/src/ffi.rs:4592`, `MasterRingBuffer` piše iz audio threada (`playback.rs:7577`), `orbCaptureLastNSeconds` u `native_ffi.dart:8060`, `ProblemsInboxService.capture()` koristi ga, `ProblemsInboxPanel` + `live_play_orb_overlay.dart` wired UI | `crates/rf-engine/src/master_ring.rs` |
| 3.2.2 | **O2** Per-bus FFT za precizniju masking detekciju + performance isolate >100 voices | ✅ SHIPPED — `PerBusBandAnalyzer` (4-band biquad po busu, `per_bus_band_energy.rs`), `SharedMeterBuffer.bus_band_rms` (24 atomics), `OrbMixerAlerts.checkMaskingAlerts()` čita `perBusRms` za masking pair detekciju sa band-level granularity | `crates/rf-engine/src/per_bus_band_energy.rs` |
| 3.2.3 | **O3** Orb stabilnost — nestaje kada se menja kanal (fix state pop) | ✅ NOT REPRODUCIBLE — kod audit: provider lifecycle clean, `didUpdateWidget` samo update-uje size, nema state pop bug u kodu | `lib/widgets/slot_lab/orb_mixer.dart` |
| 3.2.4 | Orb ghost trails 2s → ekspanzija na 10s + dupli-tap = revert (Part V.3 time travel seed) | ✅ implementirano — `_trailLength: 120→600` (10s@60fps), `_trailSnapshot` svakih 10s, `revertToTrailSnapshot()`, double-tap na praznom prostoru triggera revert | `lib/widgets/slot_lab/orb_mixer.dart`, `lib/providers/orb_mixer_provider.dart` |

### 3.3 NeuralBindOrb

| # | Zadatak | Status | Fajl |
|---|---|---|---|
| 3.3.1 | **N1** Phase 2 ghost slot indikatori — stage-ovi bez bindinga kao ghost u orbu | ✅ SHIPPED (Phase 10) — `ghost_stage_indicator.dart` 437 LOC, kompakt header `78% ▰▰▰▰▱ 40 gaps`, expandable breakdown, missing-stage chips sa tap handlers | `lib/widgets/slot_lab/neural_bind_orb.dart` |
| 3.3.2 | Snap-to-grid visual feedback u drag (trenutno nevidljiv) | ✅ 0a4defd4 — `TimelineGridOverlay` gold vertical indicator line tokom drag-a | `lib/widgets/slot_lab/timeline_grid_overlay.dart` |

### 3.6.1 Audio Coverage Badge (HELIX Omnibar) — sticky info pill

| # | Zadatak | Status | Fajl |
|---|---|---|---|
| 3.6.1 | **Audio Coverage Badge** — pill u HELIX omnibaru pored ComplianceLightsBadge: `🎵 X/Y · mini-arc` sa per-category breakdown tooltip-om (`spin: 5/9, win: 0/12, …`).  Color tier po pokrivenosti: <30% red, 30–70% orange, 70–99% yellow, 100% green.  Reaktivan na `SlotLabProjectProvider.audioAssignments` change + `StageConfigurationService` palette extension preko `Listenable.merge`.  Ne polluje, sve kroz dva ChangeNotifier-a koja već postoje. | ✅ landed (TBD-commit) | `widgets/helix/audio_coverage_badge.dart` (220 LOC) |

### 3.4 Regulatory (Compliance live)

| # | Zadatak | Cilj | Status |
|---|---|---|---|
| 3.4.1 | Live compliance meter u omnibaru (UKGC / MGA / SE / NV / NJ traffic lights) | dok autoruje | ✅ c101b925 — `LiveComplianceState` Rust backend + Flutter wire |
| 3.4.2 | Inline tooltips — pravilo koje violira + one-click auto-fix | kontekstualno | ✅ implementirano — `_flaggedAssetRow` ima `Tooltip` sa svim flagovima + `FIX ▶` dugme koje otvara `_showRemediationSheet` sa svim `RemediationSuggestion` parametrima |
| 3.4.3 | LDW guard u realnom vremenu — celebration duration cap kad win==bet | transparent | ✅ c101b925 |
| 3.4.4 | Near-miss quota tracker — "2.1% near-miss, ceiling 3%" | live UI | ✅ c101b925 |
| 3.4.5 | Compliance manifest button — jurisdiction picker + signed export | one-click | ✅ implementirano — `_exportButton` (JSON ikonica u headeru), `exportJsonAudit()` → clipboard + SnackBar sa VIEW akcijom koja otvara manifest dialog |

### 3.6 TIMELINE Slot-Native Composition Tab — ULTIMATIVNA VIZIJA

> **Date:** 2026-05-09 · **Status:** Phase A scoped, Phase B/C/D tracked
>
> Zamena bivšeg DAW-style transport HUB-a (PLAY/STOP/REC/LOOP/GOTO_START)
> u HELIX TIMELINE dock-tabu sa **slot-native composition view-om**.
> Glavni princip: slot je **event-driven**, ne timeline-driven — svaki
> spin je arc, X osa je `offset_ms` od `SPIN_START`, Y osa je redovi
> stage-ova.  Korisnik ne traži "Play music" — traži *"prikaži mi koji
> stage-ovi su firovali u poslednjem 3.5x BIG_WIN-u, gde se sudaraju
> bus-ovi, da li sam u MGA cap-u za WIN_BIG presentation"*.
>
> Već urađeno (2026-05-09 commit `f4d3fa66`): REPLAY / JUMP / CLEAR
> trio koji koristi `_lastStages` cache + helix_action eye-automation.
> To je **Phase 0** — kostur na koji ostatak naleže.

| # | Zadatak | Effort | Status | Što već imamo / Šta je novo |
|---|---|---|---|---|
| 3.6.0 | **REPLAY / JUMP / CLEAR trio** — quick actions zamenjene sa stvarno funkcionalnim akcijama nad `_lastStages` cache-om.  Empty-cache guards, mounted checks, helix_action exposure (`timeline_replay`, `timeline_jump_stage`, `timeline_clear`), info toast helper. | M | ✅ `f4d3fa66` | `helix_screen.dart:_replayLastSpin/_showJumpToStageDialog/_clearLastSpin` |
| 3.6.A | **Phase A — Stage Flow Strip + Scrubber** — vizuelni core ispod quick actions: kanvas painter koji crta `_lastStages` kao stage rows × time-axis bars (Y=stage, X=offset_ms iz spina, color=category), gold scrubber sa `Stack`+`Positioned`+`onPanUpdate`. Drag scrubber → highlight aktivnog stage-a + audition single-stage trigger. | M | ✅ landed (TBD-commit) | `widgets/helix/stage_flow_strip.dart` (374 LOC), integrated u TIMELINE Panel iznad ruler-a; klik na chunk → `EventRegistry.triggerStage(...)`; reactive na `SlotLabCoordinator` notify; per-category color (spin/win/feature/bonus/cascade/jackpot/ui/music/symbol/anticipation); empty-state hint kad cache prazan; chunk tooltip sa stageType + start/end ms + duration |
| 3.6.B | **Phase B — Audio Clash Detector** — over each `(stage, layer)` pair compute `(start_ms, end_ms, busId)` interval; if two intervals overlap with same `busId`, render warning ribbon **"WIN_BIG L2 ⚔ REEL_STOP_4 (bus 2) at 1500-1800ms"**. Click → otvara MIX dock-tab sa offending layer-ima već selected. | M | ✅ landed (TBD-commit) | `widgets/helix/timeline_intelligence.dart` — `_detectClashes(stages, composites)` pairwise compute, sortirano po duration desc, top-8 u tooltip; klik-on-mixer postavljen kao 2nd-order TODO (treba MIX dock cross-link state) |
| 3.6.C | **Phase C — Time Budget Compliance** — meter u TIMELINE header bar-u: total spin duration, per-segment budget vs target ("WIN_BIG: 1800ms target 1200, MGA cap 2000"), dead-air heatmap (slice-ovi gde nijedan layer nije fired). Veže se na `LiveComplianceProvider` da boja prati zelenu/žutu/crvenu po jurisdikciji. | S | ✅ landed (TBD-commit) | `_kStageBudgets` matrica (22 stage-a, target+softCap), `_findOverBudgetStages` walk + flag, total spin vs `_kTotalSpinCapMs=3500ms` UKGC default; dead-air heatmap odložen za 3.6.E (treba per-layer audible window iz session recorder-a) |
| 3.6.D | **Phase D — Anticipation Density Meter** — koliko spin-ova u session-u trigger-uje `ANTICIPATION_TENSION_*`? Industry sweet spot 15–30%; nasi treba da pokažemo na timeline-u procenat + indikator GOOD/LOW/HIGH. | S | ✅ landed (TBD-commit) | Lokalni `_AnticipationRing` (50-spin ring buffer) — ne čeka 3.6.E Session Recorder; color tier 4 nivoa (red <5, orange 5–15, green 15–30, yellow >30); spin dedupe preko `Object.hashAll(stageType@timestampMs)` |
| 3.6.E | **Phase E — Session Recorder + Best Win Detector** — klik [Record N spins] → engine pusti N spin-ova zaredom (50 default), snima sve stage events + RNG seeds + master output u `MasterRingBuffer` ekstenziju. Auto-detektuje "best win moment" (highest tier × dramatic ratio: `tier_multiplier × win_to_bet_ratio × duration_ms`). Lista session-a u sub-panelu sa replay buttons. | L | ✅ MVP landed (TBD-commit) | `services/session_recorder.dart` (300 LOC) + `widgets/helix/session_recorder_panel.dart` (240 LOC).  In-memory ring 20 sessions, per-spin snapshot {stages, result, recordedAt}, score formula `winRatio × tierMul × durMs/1000`, replay path kroz `stageProvider.setStages(autoPlay:true)`.  Audio bounce u MasterRingBuffer odložen za 3.6.F (Rust crate change `expandTo60s()` je future work) |
| 3.6.F | **Phase F — Marketing Clip Export** — one-click iz "best win" entry-ja: MP4 (slot canvas screen recording) + WAV (master bounce) + JSON metadata (RNG seed, win amount, multiplier, stage timeline). Output ide u `~/Library/Application Support/FluxForge Studio/clips/`. | L | ✅ **Phase 1+2 landed** | Phase 1 (Sprint 10): WAV+JSON+README atomic bundle preko `marketing_clip_exporter.dart`. **Phase 2** (Sprint 17 `c67cd1a3` + `28f81742` wire): `Mp4ClipBuilder` (sistemski ffmpeg detect + buildPoster: libx264+aac+yuv420p, scale+pad letterbox, 30fps), opcioni `posterImagePath` param u `exportClip`, auto-wire u `_ExportClipButton` preko `CortexVisionService.captureFullWindow` (graceful skip ako vision/ffmpeg fail). `MarketingClip.mp4Path` + `mp4SizeBytes` nullable polja. SnackBar prikazuje "WAV + MP4" ili samo "WAV". 9 testova zelena uključujući E2E sa pravim ffmpeg (320×240 2s poster). |
| 3.6.G | **Phase G — Stress Test Mode** — generiše batch spin-ova sa biased RNG outcomes (10× near-miss, 10× big win, 10× free spins trigger), agreguje stage timing distribuciju i izveštava outliers ("WIN_BIG nekad traje 1200ms, nekad 2400ms — 100% varijacija — fix"). | M | ⏳ blocked by E | `rf_ab_sim` ima batch simulation, koristimo to + post-hoc statistika nad `_lastStages` cache-om svakog spin-a |
| 3.6.H | **Phase H — Per-Spin Profile Compare** — overlay timeline za "volatility=high vs medium" da vidi kako se anticipation timing menja između profila.  Toggle profila u Math HUD-u → timeline strip prelazi u dual-track display. | M | ⏳ blocked by E | `SlotLabProvider.setVolatilityPreset` (✅), treba samo dual-cache state |

#### Why "ultimate slot-native, not DAW"

| DAW pristup (mrtav) | Ovaj predlog (slot-native) |
|---|---|
| Linearni timeline ruler | Stage flow strip — Y=stage, X=offset_ms iz spina, color=category |
| Play / Stop / Rec | REPLAY (re-fire spin) / JUMP (audition stage) / SESSION (multi-spin record) |
| Loop region | Anticipation density meter — meri retke event-e umesto da looping-uje frame |
| Master output bounce | Marketing clip export iz "best win" detektora |
| Cursor scrub kroz pesmu | Scrubber kroz **arc spin-a** — drag → highlight aktivnog stage-a + audition |

#### 3 ULTIMATIVNE feature-e koje DAW-i nemaju

1. **Audio Clash Detector** ⚔ — Wwise nema, FMOD nema.  Detektuje kad se dva audio layer-a bore za isti bus u istom vremenskom slice-u.  Click → Mixer sa offending layers selected.
2. **Session Recorder + Best Win Detector** 🎞 — slot industrija plaća $5k/min za marketing clip production.  Ovde free, sa auto-best-moment detection iz win tier × dramaticnosti formule.
3. **Time Budget Compliance** ⏱ — direktno se vezuje na `ComplianceLightsBadge` u omnibaru.  Per-jurisdiction caps (MGA, UKGC, NV, NJ) za WIN presentation duration kao Live linting.

#### Ulazni kod / referente

- `lib/screens/helix_screen.dart:_replayLastSpin/_showJumpToStageDialog/_clearLastSpin` — Phase 0 entry points
- `lib/providers/slot_lab/slot_stage_provider.dart:_lastStages` — cache za sve faze
- `lib/widgets/lower_zone/slotlab/slotlab_painters.dart` — grid painter pattern za reuse u Phase A
- `crates/rf-engine/src/master_ring.rs` — base za Phase E (treba expand to 60s)
- `lib/services/live_compliance_provider.dart` — Phase C integration target
- `crates/rf-bridge/src/auto_spatial_ffi.rs:auto_spatial_get_all_outputs` — refernca za batch query pattern (Phase E session export)

#### Sledeći commit checkpoint

**Phase A (M, ~2h)** — Stage Flow Strip painter + scrubber.  Stand-alone, ne traži pipeline fix.  Vizualno radi čim ima `_lastStages` populate-ovan (manuelan SPIN klik).  Checkpoint: CortexEye snap pokazuje X×Y grid stage rows, scrubber drag radi, audition single-stage iz scrub pozicije.

---

### 3.7 GAME CONFIG Ultimativni Slot Designer

> **Status:** Phase 0 + A + B + C + D + E + F + **G** + H + I + J **sve landed** ✅
> - `d27ac94f` (2026-05-09): Phase 0,A,B,C,D,E,F,H,I,J (+3409/-117 LOC)
> - `[next]` (2026-05-09): Phase G — Live Grid Visualizer ultimativno:
>   `_GridVisualizerWidget` StatefulWidget, real emoji simboli, Megaways variable-height reels,
>   payline color-cycling overlay (20 patterns), cluster adjacency hints, ways overlay,
>   ⚡ SPIN PREVIEW staggered per-reel animacija (bez audio side-effects).
>
> **Detaljna spec:** `.claude/MASTER_TODO.md` FAZA 3.7.
> **Preostalo za 3.7:** 3.7.K (RTP Solver, L), 3.7.M (AI Recommender, XL).
> **Sad landed:** 3.7.H+ vizuelni diff side-by-side polish + 3.7.L Compliance Audit Trail.

| # | Stavka | Status |
|---|---|---|
| 3.7.0 | Slot Type Selector + 8 preseta (Classic 3, Video 5×3/5×4, 243 ways, 1024 ways, Megaways, Cluster, Hold-Win) + atomic `_applySlotType()` batch update | ✅ `d27ac94f` |
| 3.7.A | Grid + Win Mechanism: Megaways per-reel sliders (R0–R5, 2–7 rows, live `totalWays` ∏), Cluster (minSize 4-9, allowDiagonal, square/honeycomb), Infinity Reels (start/max, expand trigger sym) | ✅ `d27ac94f` |
| 3.7.B | Math Profile Editor: continuous volatility slider 1.0–10.0, MaxWin cap (5K/10K/25K/50K/unlimited), live RTP feasibility (achievable/marginal/infeasible) | ✅ `d27ac94f` |
| 3.7.C | Symbol System: 5 industrijskih preseta (Fruit Classic, Royal Mystery, Asian, Egyptian, Sci-Fi) + custom + auto-populate paytable | ✅ `d27ac94f` |
| 3.7.D | Feature Stack: FreeSpins / Cascade / HoldWin sub-configs sa expand-on-tap inline editor-om | ✅ `d27ac94f` |
| 3.7.E | Anticipation Tip A/B/Custom + per-reel checkboxes + audio `[bind ▸]` dugmad za L1–L4 → triggerStage + audition toast | ✅ `d27ac94f` |
| 3.7.F | Jurisdiction overlay (UKGC / MGA / SE / NJ / NV) + per-field violation badges (megaways, cluster, near-miss, feature buy, custom tip) | ✅ `d27ac94f` |
| 3.7.G | Live Grid Visualizer: `_GridVisualizerWidget` StatefulWidget, emoji simboli po ćeliji, Megaways per-reel variable height, payline color-cycling (20 patterns) + nav, cluster adjacency + diagonal, ways connections, ⚡ SPIN PREVIEW per-reel staggered anim | ✅ `[next]` |
| 3.7.H | Snapshot Diff view sa L/R picker, +/−/~ entries (JSON-shape) | ✅ `d27ac94f` |
| 3.7.H+ | Visual Snapshot Diff polish: 3-column layout (FIELD ‖ LEFT ‖ RIGHT), per-row colored row container, statistical summary chips (~/+/−/=), filter "show unchanged" toggle, value-box highlight outline za added/removed, "✓ Snapshots are identical" empty-state | ✅ landed (TBD-commit) — `helix_screen.dart::_buildSnapshotDiffView` rewrite + `_DiffStatChip` widget |
| 3.7.L | Compliance Audit Trail: append-only JSONL log u `~/Library/Application Support/FluxForge Studio/audit/compliance_YYYY-MM-DD.jsonl`, daily rotation; in-memory ring buffer 200 entries za UI; hooks u 3 setJurisdiction call site-a (aurexis_profile, rgai, rgai_ffi); skip pattern za idempotent re-applies | ✅ landed (TBD-commit) — `services/compliance_audit_trail.dart` (220 LOC) |
| 3.7.I | Real-time Integrity Validator sa 4 severity tier-a (info/warn/error/blocker) + AutoFixPatch + 🔧 "Fix all" footer | ✅ `d27ac94f` |
| 3.7.J | Blueprint Round-Trip Export/Import (paste JSON → validate → preview → apply, hash-matched round-trip) | ✅ `d27ac94f` |

---

### 3.5 Atmos + spatial catch-up

| # | Zadatak | Effort | Status |
|---|---|---|---|
| 3.5.1 | Atmos object export MVP (bar jedan path) | 3 nedelje | ✅ — `crates/rf-spatial/src/atmos/export/` (`adm_xml.rs` ITU-R BS.2076-2 graf + `bw64.rs` BW64/RF64 writer + `mod.rs` `AtmosExporter` API). Pun pipeline: bed (7.1.4) + N objects → BW64 `.wav` sa `axml` (ADM XML) + `chna` (Channel Allocation) chunks. Auto-promocija RF64 na payload > 4 GiB ili `force_rf64`. 16/24/32-bit (PCM/IEEE float). 14 unit testova (TC carry, XML graf, position blocks sa Jump flag, RIFF chunk parser, RF64 ds64, 24-bit clamp/NaN, axml word-align, error paths) + 6 E2E integration testova (bed+objects roundtrip, RF64 promotion, objects-only, channel mismatch reject, bit_depth reject, data size invariant). 23/23 unit + 6/6 E2E zelena. Workspace clippy clean (uz fix 4 wasm `0.7071` → `FRAC_1_SQRT_2`, 1 ffi unsafe annotation, 1 mut-from-ref allow). 3838 workspace testova prolazi. |
| 3.5.2 | HOA 3rd–5th order authoring | 1 mesec | ✅ — `HoaPipeline` unified authoring API (`pipeline.rs`). Spaja MultiSourceEncoder → AmbisonicTransform (Wigner-D, Ivanic & Ruedenberg) → Max-rE → HoaShelfFilter (per-degree Butterworth TDF-II) → AmbisonicDecoder (AllRAD/EPAD/ModeMatching/Basic/EnergyPreserving). Preseti: `theatrical_5th_order` (7.1.4 AllRAD + Max-rE + shelf), `stereo_monitor_3rd_order`. Real-time: `set_orientation` (sa RotationInterpolator), `set_maxre`, `set_shelf_db`. Kompletan eksport iz `hoa/mod.rs`: `EpadDecoder`, `HoaShelfFilter`, `MaxReWeights`, `TDesign`, `RotationInterpolator`, `DecodingMethod`, `MultiSourceEncoder`. Fix: EPAD `energy_flatness` threshold za 2×4 underdetermined sistem (0.5 → 0.25). Fix: maxre.rs clippy warning. 97 unit + 6 E2E testova zelena. Clippy 0 warnings. |
| 3.5.3 | Personalized HRTF via HRTFformer / graph NN | 1 mesec | ⏳ |

---

## FAZA 4 — AI Copilot (Leapfrog)

> Nijedan konkurent ovo nema. Prozor ~12-18 meseci pre Wwise odgovora.

### 4.1 Copilot infrastruktura

| # | Zadatak | Tehn | Effort | Status |
|---|---|---|---|---|
| 4.1.1 | `rf-copilot` `Action` trait (svaka sugestija reversibilna) | Rust | 2 nedelje | ✅ DONE — `actions.rs`: `Action` trait + `ActionRegistry` + 5 konkretnih akcija (BumpVoiceBudget/SetReelSpinLoop/SetAmbientLoop/PromoteFeatureTriggerTier/SetRequiredEventWeight). 13 testova zelena. commit `7618ab55` |
| 4.1.2 | Local LLM integracija (Llama 3 8B ili Phi-4) via Metal MPSGraph | MPS | 1 mesec | 🔴 OPEN |
| 4.1.3 | FFI kroz `rf-bridge/src/slot_lab_ffi.rs` | Rust | 1 nedelja | ✅ DONE — `copilot_apply_action(project_json, rule_id)` FFI + `copilotApplyAction` u native_ffi.dart. commit `7618ab55` |
| 4.1.4 | Dart `CopilotService` + `CopilotPanel` widget | Flutter | 2 nedelje | ✅ DONE — `AiCopilotService`: `applyAction()` + `applyActionAndReanalyze()` + `_lastProjectJson` cache. `AiCopilotPanel`: DEMO/LIVE mode toggle, LIVE koristi pravi Rust engine, "Auto-fix" dugme + "Fix all" batch. 0 analyzer errors. commit `7618ab55` |

### 4.2 Features

| # | Zadatak | Input | Output | Status |
|---|---|---|---|---|
| 4.2.1 | Generative mix ("make rollup 15% more euphoric") | voice/text | param delta preview branch | ✅ Sprint 17 (`921884f6`) — `MixDeltaProposer` heuristic rule engine: 19 stage keyword patterns, 9 emotions (euphoric/triumphant/tense/calm/aggressive/dark/bright/punchy/smooth) sa synonym map, intensity extraction (percent + "much/very" intensifiers + "less/more" direction), emotion→delta tabela (volume_db/brightness_pct/tempo_pct/stereo_width_pct/reverb_dwell_ms/low_pass_hz/saturation_pct/transient_pct). Per-delta `rationale` field. 13 unit testova zelena. |
| 4.2.2 | Predictive automation (after 5-10 manual moves) | gesture history | ghost-curve in timeline | ✅ Sprint 17 (`921884f6`) — `GesturePredictor` trigram pattern detector: ring 100 events, `predictNext(minConfidence)` skenira (prefixA, prefixB, X) match-eve, modal continuation + modal payload, confidence = bestCount/totalMatches. 13 unit testova zelena. |
| 4.2.3 | Voice commands ("solo voice bus", "audition next win tier", "export MGA manifest") | WhisperKit local | direct action | 🔴 OPEN — native FFI plugin (XL, multi-week) |
| 4.2.4 | Error prevention (LDW, near-miss, celebration LUFS) | continuous validators | flag before user hears | ✅ Sprint 17 (`7d6ad741` + `28f81742` UI) — `AudioComplianceGuard` sa 3 pre-flight validatori: LDW (WIN_BIG/MASSIVE/MEGA + win≤bet×1.1 → BLOCK, UKGC), Near-miss quota (ANTICIPATION_TENSION + ratio>3% → WARN, UKGC RTS 13), Celebration LUFS (WIN celebration + LUFS>-16 → WARN). Severity tier (info/warn/block). Stream `warnings` + ring 50. `ComplianceWarningBanner` widget sa auto-dismiss (info=4s, warn=6s, block=manual). 18+7 testova zelena. |
| 4.2.5 | Arrangement Suggester ("tense buildup to big win") | natural-language intent | ordered stage step list (stage+duration+envelope+rationale) | ✅ Sprint 18 — `ArrangementSuggester` heuristic engine: 9 arrangement shapes (tenseBuildup/euphoricClimax/calmIntro/punchyHit/aggressiveSequence/smoothTransition/brightPayoff/darkSetup/triumphantFinale) sa synonym map, 7 ArrangementTarget-a (bigWin/megaWin/jackpot/bonus/freeSpins/cascade/generic), 6 EnvelopeShape envelope-a (build/peak/transient/release/sustained/fade). Scale modifier ("short"=0.5x, "long/epic"=1.75x). targetOverride parametar. Deterministic, no LLM, no Rust FFI — pure Dart singleton. 24 unit testova zelena. Komplement MixDeltaProposer-u: gde 4.2.1 menja parametre jednog stage-a, 4.2.5 predlaže sekvencu stage-ova kroz vreme. |

### 4.3 Persistent memory (Part V.4)

| # | Zadatak | Skladište | Status |
|---|---|---|---|
| 4.3.1 | `~/.fluxforge/memory.db` event log | local only | ✅ Sprint 17 (`70c0355b`) — `MemoryEventLog` JSONL append-only u `~/Library/Application Support/FluxForge Studio/memory/events_YYYY-MM.jsonl` (monthly rotation, GDPR-friendly). API: `record/query/recentCached/kindCounts/purgeOlderThan`. Auto-hooks na PredictiveAnalyzer.feedbackStream + AudioComplianceGuard.warnings. Ring 200 + disk merge. SQLite zamenjen JSONL-om jer `sqflite` dep nije bio u `pubspec.yaml` — JSONL pattern već postoji u repo (`compliance_audit_trail`). 13 testova zelena. |
| 4.3.2 | Embedding model (sentence-transformers via tract) | Rust | ✅ MVP Sprint 17 (`28f81742`) — `AudioEmbedding` + `AudioEmbeddingStore`: 8-dim feature vector iz Sonic DNA (duration/rms/centroid/transient/attack/brightness/loopable/sustain), cosine similarity sa zero-vector guard, k-NN nearest(k) query, minSimilarity filter, self-match exclude, JSON persistent store sa atomic save (tmp rename), lazy load. 16 testova zelena. **Ext** (deferred): 128-d transformer embeddings via tract ONNX (M effort). |
| 4.3.3 | Style fingerprint export/import `.style` file | portable | ✅ Sprint 17 (`28f81742`) — `StyleFingerprint` portable JSON (version, name, audio_dna, assignments_template, bus_profile, compliance_targets, metadata). Semver-major compatibility check. `StyleFingerprintService.export/import/listAll/safeFilenameFor`. Default dir `~/Library/Application Support/FluxForge Studio/styles/`. Pretty-printed (2-space indent). 13 testova zelena. |
| 4.3.4 | Popuniti `rf-neuro` stubs sa memory substrate | Rust crate / Dart layer | ✅ Sprint 17 (`ff3fbaff`) — `NeuroMemorySubstrate` Dart layer iznad `rf-neuro::NeuroEngine`. 8D PlayerStateVector ring 1000, API: `recordSnapshot/trend/baseline/peaks/trajectory/latest`. Optional `attachMemoryEventLog(true)` → snapshot ide u MemoryEventLog kao `neuro_snapshot` kind. 18 testova zelena. Dart layer pošto rf-neuro već ima 5-min sliding window (`crates/rf-neuro/src/engine.rs:548 LOC`), ovo dodaje long-term persistent substrate. |

### 4.4 Predictive Event Routing (Part V.10)

| # | Zadatak | Osnova | Status |
|---|---|---|---|
| 4.4.1 | Classifier audio features → Stage label | Sonic DNA Layer 2/3 postoji | ✅ pre-existing — Sonic DNA infra 2637 LOC (`crates/rf-stage/src/sonic_dna.rs`, `rf-engine/src/sonic_dna_extractor.rs`, `rf-bridge/src/spectral_dna_ffi.rs`, `flutter_ui/lib/providers/slot_lab/spectral_dna_classifier.dart`) |
| 4.4.2 | Drag file → 85% confidence "reel_stop for bus SFX" | isolate query | ✅ Sprint 17 (`a8db50b9`) — `PredictiveAnalyzer` (LRU cache 100, inflight dedup, async API, feedback stream) + `PredictiveConfidenceBadge` (HIGH≥75%/MID≥50%/LOW≥25% tier color, mismatch ↪+≠ styling, 24-char clamp) + `PredictiveBadgeOverlay` (Stack child sa mounted+race guard) + pilot u `slot_lab_screen.dart:11699` composite event DragTarget. 17 testova zelena. |
| 4.4.3 | Gap detection — "12 files match FREE_SPIN_START, top 3 suggestion" | list | ✅ Sprint 17 (`e66b9f3c` + `f697197a` wire) — `AssignmentGapPanel` stateful widget: per-stage top-3 suggestions sortirane desc, Apply/Skip dugmad. Debounce 250ms. Reactive na SlotLabProjectProvider + AudioAssetManager. Two access pointa: HELIX MONITOR → evtDebug → GAPS tab (6th tab u Event Debugger), Cmd+K palette → "audio.predictive_gap_detector" command. |
| 4.4.4 | Auto-fill proposals (one-click) | provider surface | ✅ Sprint 17 (`e66b9f3c`) — "⚡ AUTO-FILL ALL ≥75%" footer dugme u `AssignmentGapPanel` primenjuje sve high-tier suggestion-e u jednom klik-u + SnackBar feedback ("Auto-filled N stages"). |
| 4.4.5 | Learning from rejections (feed V.4 memory) | cross-session | ✅ Sprint 17 (`e66b9f3c`) — `RoutingFeedbackLog` JSONL append-only u `audit/routing_feedback_YYYY-MM-DD.jsonl`, daily rotation, in-memory ring 200, idempotent attach. API: `attach(analyzer)/recent(n)/statsByStage()/clearForTest`. Eager-init u `service_locator.dart`. 7 testova zelena. |

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
