# FluxForge Studio — Agent Team Architecture

## Pregled

25 specijalizovanih AI agenata (0-24) za razvoj i odrzavanje FluxForge Studio DAW-a.
Svaki agent je duboki ekspert za svoj domen — ima sopstvenu memoriju, pravila, i znanje koje akumulira tokom vremena.

Dokument nastao na osnovu **ultimativnog QA audita celokupnog sistema** (2026-03-30).
Finalna verzija: 500+ source fajlova, 34 Rust crate-a, 57 widget direktorijuma — sve mapirano.

---

## Statistika codebase-a

- **Providers:** 127 fajlova (68 root, 43 slot_lab, 16 subsystems)
- **Services:** 211 fajlova (162 root + 49 subdirektorijumi)
- **Models:** 60 fajlova
- **Screens:** 15 fajlova
- **Widgets:** 57 direktorijuma, 500+ widget fajlova
- **Rust Crates:** 34 specijalizovana crate-a
- **FFI Bridge:** 6 Flutter-Rust bridge fajlova

---

## Agent Roster

### Agent 0: Orchestrator

**Uloga:** Routing, delegacija, big picture arhitektura
**Odgovornost:**
- Prima zahtev i odlucuje koji agent(i) treba da rade
- Paralelizuje nezavisne taskove
- Konsoliduje rezultate iz vise agenata
- Cuva "big picture" — cross-domain odluke
- Nikad radi implementaciju sam — delegira

**Zna:**
- Koji agent pokriva koji domen (svih 24 agenta)
- Koje bagove/zamke svaki domen ima
- Zavisnosti izmedju domena
- SlotLab 4 agenta: UI, Events, Audio, GameArchitect
- Slot Intelligence (Rust AI stack) je odvojen od GameArchitect (Dart game flow)
- MediaTimeline (Flutter UI) je odvojen od TimelineEngine (Rust core)

---

### Agent 1: AudioEngine

**Uloga:** Rust audio core, FFI granica, audio thread safety, device driver, core tipovi
**~100 fajlova**

**Rust crate-ovi:**
- `rf-engine` (63 fajla) — bus, graph, mixer, node, processor, realtime, send_return, sidechain, loop_asset, loop_manager, marker_ingest. Core audio routing i graph engine.
- `rf-bridge` (54 fajla) — engine_bridge, dsp_commands, transport, metering, ale_ffi, ail_ffi, aurexis_ffi, fluxmacro_ffi, sss_ffi, stage_ffi, ingest_ffi. Flutter-Rust FFI bridge.
- `rf-audio` (12 fajlova) — asio, aoip, dsd_output, multi_output, ringbuf, engine, thread_priority. Audio device driver (CoreAudio/ASIO/ALSA).
- `rf-realtime` (10 fajlova) — graph, pipeline, latency, masscore, simd, gpu, state, benchmark. Zero-latency RT procesiranje, GPU compute (wgpu).
- `rf-core` (16 fajlova) — channel_strip, tempo, routing, sample, time, track, midi, params, editing. Core tipovi (SampleRate, BufferSize, Decibels, MIDI).
- `rf-state` (14 fajlova) — Undo/redo, preseti, projekti, serijalizacija.
- `rf-event` (7 fajlova) — Wwise/FMOD-stil event management, curve automation.
- `rf-viz` (9 fajlova) — spectrogram, eq_spectrum, plugin_browser, plugin_chain. GPU vizualizacije (wgpu rendering).
- `rf-file` (7 fajlova) — Multi-format read/write (WAV, FLAC, MP3, AAC, ALAC). Symphonia + hound.

**Dart fajlovi:**
- `flutter_ui/lib/src/rust/native_ffi.dart`
- `flutter_ui/lib/src/rust/engine_api.dart`

**Kriticna pravila:**
- Audio thread = sacred: NULA alokacija, NULA lockova, NULA panica
- `try_write()` / `try_read()` — nikad blocking na audio thread
- `cache.peek()` (read), NIKAD `cache.get()` (write)
- `self.sample_rate()`, NIKAD hardkodiran 48000
- `Arc::make_mut` za CoW u clip operacijama
- Dva engine globala: `PLAYBACK_ENGINE` (LazyLock) vs `ENGINE` (Option, legacy)
- Lock-free: `rtrb::RingBuffer` za UI->Audio

**QA bagovi:**
- BUG #1 CRITICAL: Wave cache alloc/free mismatch (`ffi.rs:20150,20169`)
- BUG #2 CRITICAL: Video frame dealloc type mismatch (`ffi.rs:20932`)
- BUG #3 CRITICAL: Sample rate desync (`ffi.rs:133-159`)
- BUG #12 HIGH: Waveform SR fallback hardkodiran 48000 (`ffi.rs:2020`)
- BUG #13 HIGH: Eviction thread nema panic handler (`playback.rs:210-225`)
- BUG #14 HIGH: Audio thread try_write() silent skip (`playback.rs:5208-5340`)

---

### Agent 2: MixerArchitect

**Uloga:** MixerProvider, kanali, inserti, routing, bus, fader math, mixing console UI
**~40 fajlova**

**Provideri:**
- `flutter_ui/lib/providers/mixer_provider.dart`
- `flutter_ui/lib/providers/mixer_dsp_provider.dart`

**Widgeti:**
- `flutter_ui/lib/widgets/lower_zone/daw/mix/` (svi)
- `flutter_ui/lib/widgets/channel_inspector/` (svi)
- `flutter_ui/lib/widgets/mixer/` (19 fajlova) — ultimate_mixer, pro_mixer_strip, VCA strip, channel strip, control room, group manager, plugin selector, floating mixer/send windows, automation badges, IO selectors, color pickers
- `flutter_ui/lib/widgets/routing/` (5 fajlova) — routing matrix (standard + advanced), audio graph vizualizacija, stem routing matrix
- `flutter_ui/lib/widgets/channel/` (1 fajl) — channel strip widget

**Ostalo:**
- `flutter_ui/lib/screens/engine_connected_layout.dart` (mixer deo)
- `flutter_ui/lib/models/audio_math.dart`
- `flutter_ui/lib/services/session_template_service.dart`

**Kriticna pravila:**
- OutputBus: `.engineIndex`, NIKAD `.index` za FFI
- Moderne metode: `setChannelVolume()`, `toggleChannelMute()`, `toggleChannelSolo()`
- FaderCurve u `audio_math.dart` = jedini izvor istine
- Stereo dual pan: `pan=-1.0` = hard-left (NE bug), `panRight=+1.0` = hard-right
- Dual insert state: MixerProvider + _busInserts + Rust — moraju biti u sync-u
- Master ima 8 pre-fader slotova, regular 4

**QA bagovi:**
- BUG #4 CRITICAL: `OutputBus.index` umesto `.engineIndex` u session template (`session_template_service.dart:47,58`)
- BUG #6 CRITICAL: `replaceAll(RegExp(r'[^0-9]'), '')` za ID parsing (`mixer_provider.dart`)
- BUG #10 HIGH: Post-fader insert index hardkodiran `slotIndex < 4` (`mixer_provider.dart:2842,2857`)
- BUG #11 HIGH: Default bus volumes sve na 1.0 (`mixer_dsp_provider.dart:185-191`)
- BUG #20 MEDIUM: Dual insert state — nema single sync point

---

### Agent 3: SlotLabUI

**Uloga:** SlotLab screen rendering, koordinator, lower zone tabovi, UCP, preview widgeti
**~70 fajlova**

**Kljucni fajlovi:**
- `flutter_ui/lib/screens/slot_lab_screen.dart` (13000+ linija — citaj sa offset/limit)
- `flutter_ui/lib/providers/slot_lab/slot_lab_coordinator.dart`
- `flutter_ui/lib/providers/slot_lab/slot_engine_provider.dart`
- `flutter_ui/lib/providers/slot_lab/slot_stage_provider.dart`
- `flutter_ui/lib/providers/slot_lab/inspector_context_provider.dart`
- `flutter_ui/lib/providers/slot_lab/smart_collapsing_provider.dart`
- `flutter_ui/lib/providers/slot_lab/slotlab_notification_provider.dart`
- `flutter_ui/lib/providers/slot_lab/slotlab_undo_provider.dart`
- `flutter_ui/lib/providers/slot_lab/config_undo_manager.dart`
- `flutter_ui/lib/providers/slot_lab/error_prevention_provider.dart`

**Lower zone tabovi (10):**
- `widgets/slot_lab/lower_zone/slotlab_intel_tab.dart`
- `widgets/slot_lab/lower_zone/slotlab_logic_tab.dart`
- `widgets/slot_lab/lower_zone/slotlab_monitor_tab.dart`
- `widgets/slot_lab/lower_zone/slotlab_containers_tab.dart`
- `widgets/slot_lab/lower_zone/slotlab_rtpc_tab.dart`
- `widgets/slot_lab/lower_zone/slotlab_music_tab.dart`
- `widgets/slot_lab/lower_zone/slotlab_music_layers_panel.dart`
- `widgets/slot_lab/lower_zone/event_list_panel.dart`
- `widgets/slot_lab/lower_zone/command_builder_panel.dart`
- `widgets/slot_lab/lower_zone/bus_meters_panel.dart`

**UCP (8), Middleware UI (8), Timeline (4), Preview/General (30+):**
- Videti prethodni dokument za kompletnu listu

**Kriticna pravila:**
- SlotLabProvider je MRTAV KOD — koristi SlotLabCoordinator
- slot_lab_screen.dart: NIKAD citaj ceo fajl — offset/limit

---

### Agent 4: SlotLabEvents

**Uloga:** EventRegistry, CompositeEventSystem, Middleware, CustomEvents, FFNC, middleware UI widgeti
**~75 fajlova**

**Event system core (6):**
- `services/event_registry.dart` — centralni audio event sistem
- `services/event_sync_service.dart` — two-way sync EventRegistry <-> MiddlewareProvider
- `services/event_collision_detector.dart`
- `services/event_dependency_analyzer.dart`
- `services/event_naming_service.dart`
- `services/diagnostics/event_flow_monitor.dart`

**Composite event system (3):**
- `providers/subsystems/composite_event_system_provider.dart`
- `providers/subsystems/event_system_provider.dart`
- `providers/subsystems/event_profiler_provider.dart`

**Event modeli (5):**
- `models/middleware_models.dart`
- `models/advanced_middleware_models.dart`
- `models/slot_audio_events.dart`
- `models/event_folder_models.dart`
- `models/auto_event_builder_models.dart`

**FFNC (12):**
- `services/ffnc/ffnc_parser.dart`, `ffnc_renamer.dart`, `assignment_validator.dart`, `event_presets.dart`, `phase_presets.dart`, `stage_defaults.dart`, `template_generator.dart`, `template_library.dart`, `profile_importer.dart`, `profile_exporter.dart`, `readme_generator.dart`
- `widgets/slot_lab/ffnc_rename_dialog.dart`

**Middleware UI widgeti (46):**
- `widgets/middleware/` — kompletni middleware UI sistem: container management, event/state/RTPC sistemi, music sequencing, ducking matrices, preset morphing, timeline zoom, audio signatures, beat grids

**Event UI:**
- `widgets/slot_lab/lower_zone/events/composite_editor_panel.dart`
- `services/template/event_auto_registrar.dart`

**KRITICNA PRAVILA:**
- EventRegistry: **JEDAN** put registracije — SAMO `_syncEventToRegistry()` u slot_lab_screen.dart
- **NIKADA** registracija u composite_event_system_provider.dart
- Middleware composite events = **JEDINI** izvor istine za sav SlotLab audio
- ID format: `event.id`, **NIKAD** `composite_${id}_${STAGE}`
- FFNC prefixes: `sfx_`, `mus_`, `amb_`, `trn_`, `ui_`, `vo_`
- BIG_WIN_START/END su `mus_` (music bus), NE `sfx_`

**QA bagovi:**
- BUG #9 FIXED: Mrtav kod `_onAudioDroppedOnStage()` uklonjen — metoda vise ne postoji u kodu

---

### Agent 5: SlotLabAudio

**Uloga:** Voice mixer, audio triggering, bus routing, ducking, RTPC, music system
**~28 fajlova**

**Audio provideri (2):**
- `providers/slot_lab/slot_audio_provider.dart`
- `providers/slot_lab/slot_voice_mixer_provider.dart`

**Subsystem provideri (11):**
- `providers/subsystems/bus_hierarchy_provider.dart`
- `providers/subsystems/aux_send_provider.dart`
- `providers/subsystems/voice_pool_provider.dart`
- `providers/subsystems/ducking_system_provider.dart`
- `providers/subsystems/attenuation_curve_provider.dart`
- `providers/subsystems/rtpc_system_provider.dart`
- `providers/subsystems/music_system_provider.dart`
- `providers/subsystems/state_groups_provider.dart`
- `providers/subsystems/switch_groups_provider.dart`
- `providers/subsystems/memory_manager_provider.dart`

**Audio servisi (15):**
- `services/audio_playback_service.dart`, `audio_asset_manager.dart`, `audio_variant_service.dart`, `audio_context_service.dart`, `audio_pool.dart`, `audio_export_queue_service.dart`, `slot_audio_automation_service.dart`, `stage_audio_mapper.dart`, `audio_mapping_import_service.dart`, `audio_asset_tagging_service.dart`, `audio_suggestion_service.dart`, `audio_graph_layout_engine.dart`, `network_audio_service.dart`, `server_audio_bridge.dart`, `diagnostics/audio_voice_auditor.dart`

**Kriticna pravila:**
- Middleware composite events = JEDINI izvor istine
- Voice pool za rapid-fire events
- Ducking po prioritetu
- Bus hierarchy: slot lab busovi ODVOJENI od DAW mix busova

---

### Agent 6: GameArchitect

**Uloga:** Dart game flow, feature kompozicija, behavior tree, simulacija, matematicki model
**~60 fajlova**

**Game flow (5):**
- `providers/slot_lab/game_flow_provider.dart` — FSM: BASE_GAME -> FREE_SPINS -> CASCADING -> BONUS
- `providers/slot_lab/game_flow_integration.dart`
- `providers/slot_lab/stage_flow_provider.dart`
- `providers/slot_lab/transition_system_provider.dart`
- `providers/slot_lab/pacing_engine_provider.dart`

**Feature executors (10):**
- `executors/bonus_game_executor.dart`, `free_spins_executor.dart`, `cascade_executor.dart`, `hold_and_win_executor.dart`, `wild_features_executor.dart`, `collector_executor.dart`, `respin_executor.dart`, `gamble_executor.dart`, `multiplier_executor.dart`, `jackpot_executor.dart`

**Behavior tree i AI (4):**
- `providers/slot_lab/behavior_tree_provider.dart` — 22+ node types, 300+ engine hooks
- `providers/slot_lab/behavior_coverage_provider.dart`
- `providers/slot_lab/trigger_layer_provider.dart`
- `providers/slot_lab/context_layer_provider.dart`

**Simulacija i konfiguracija (8):**
- `providers/slot_lab/simulation_engine_provider.dart`
- `providers/slot_lab/feature_composer_provider.dart`
- `providers/slot_lab/slotlab_template_provider.dart`
- `providers/slot_lab/slotlab_export_provider.dart`
- `providers/slot_lab/ail_provider.dart`, `drc_provider.dart`, `sam_provider.dart`, `gad_provider.dart`, `sss_provider.dart`

**Modeli (2):**
- `models/slot_lab_models.dart`, `models/win_tier_config.dart`

**Game design widgeti (25+):**
- `widgets/slot_lab/game_flow_overlay.dart`, `game_model_editor.dart`, `win_tier_config_panel.dart`, `win_celebration_designer.dart`, `behavior_tree_widget.dart`, `scenario_controls.dart`, `scenario_editor.dart`, `forced_outcome_panel.dart`, `feature_builder_panel.dart`
- `widgets/slot_lab/bonus/` (4 fajla) — bonus_simulator, gamble_simulator, pick_bonus, hold_and_win_visualizer
- `widgets/slot_lab/sfx_pipeline_wizard.dart`, `stage_editor_dialog.dart`, `stage_timing_editor.dart`, `transition_config_panel.dart`, `gdd_import_panel.dart`, `gdd_import_wizard.dart`, `gdd_preview_dialog.dart`

**Kriticna pravila:**
- Win tier: data-driven (P5 WinTierConfig), NE hardkodirati
- `_bigWinEndFired` guard, FS auto-spin balance guard
- Behavior tree coverage MORA biti 100%

---

### Agent 7: UIEngineer

**Uloga:** Flutter generalni widgeti, layout, common komponente, gestures, Focus, lifecycle, onboarding
**~90 fajlova**

**Fajlovi:**
- `flutter_ui/lib/widgets/common/` (37 fajlova) — faders, meters, animated widgets, command palette, error boundary, context menu, search field, undo history, toast, shortcuts overlay, breadcrumbs
- `flutter_ui/lib/widgets/layout/` (12 fajlova) — left/right/center zones, control/transport/menu bars, channel inspector layout, project tree, event folders, responsive design
- `flutter_ui/lib/widgets/tutorial/` (4 fajla) — tutorial overlay, onboarding overlay, tutorial steps
- `flutter_ui/lib/screens/` (UI logika — NE slot_lab_screen.dart)
- `flutter_ui/macos/Runner/MainFlutterWindow.swift`
- `flutter_ui/lib/main.dart` (provider tree)

**Kriticna pravila:**
- FocusNode/Controllers -> `initState()` + `dispose()`, NIKAD inline u `build()`
- Modifier keys -> `Listener.onPointerDown`, NIKAD `GestureDetector.onTap` + HardwareKeyboard
- Keyboard handlers -> EditableText ancestor guard
- Nested drag -> `Listener.onPointerDown/Move/Up`
- SmartToolProvider: JEDAN instance
- Korisnik nema konzolu: NE print/debugPrint

**QA bagovi:**
- BUG #16 HIGH: 16x TextEditingController u build()
- BUG #17 HIGH: 2x GestureDetector + HardwareKeyboard anti-pattern
- BUG #21 MEDIUM: print() u MainFlutterWindow.swift:283

---

### Agent 8: DSPSpecialist

**Uloga:** DSP procesiranje, filteri, spektrum, metering (Rust), SIMD, ML audio, mastering, pitch, restauracija
**~120 fajlova**

**Rust crate-ovi:**
- `rf-dsp` (65 fajlova) — simd, automation, delay_compensation, biquad, eq, dynamics, reverb, delay, spatial, surround, convolution, linear_phase, metering, spectral, dsd, gpu. SIMD-optimized audio processing.
- `rf-restore` (8 fajlova) — Professional audio repair, denoising, declicking
- `rf-master` (10 fajlova) — AI-assisted mastering, loudness optimization
- `rf-pitch` (7 fajlova) — Polyphonic pitch engine (Melodyne DNA level)
- `rf-r8brain` (7 fajlova) — Reference-grade SRC (Blackman-Harris windowed sinc)
- `rf-ml` (26 fajlova) — ONNX model inference, Hugging Face integration, neural audio processing

**Flutter paneli:**
- `widgets/lower_zone/daw/process/` (svi paneli)
- `widgets/fabfilter/` (svi paneli)
- `widgets/dsp/` (svi paneli)
- `widgets/eq/` (8 fajlova) — API550, Neve1073, Pultec, ProEQ, morph pad, room wizard, GPU spectrum, vintage inserts
- `widgets/lower_zone/daw/mix/lufs_meter_widget.dart`

**Kriticna pravila:**
- Biquad: TDF-II, `z1`/`z2` state
- SIMD dispatch: avx512f -> avx2 -> sse4.2 -> scalar fallback
- Sample rate: `set_sample_rate()` + coefficient recalculation
- Denormal handling: FTZ/DAZ + software flush
- Metering: `try_write()` svuda, non-blocking
- FFT: Hann window, correct RMS scaling, exponential smoothing

**QA bagovi:**
- BUG #7 CRITICAL: BPM hardkodiran 120.0 u 4 Rust DSP struct-a (`delay.rs:521,982`, `dynamics.rs:602`, `reverb.rs:2636`)
- BUG #23 MEDIUM: FabFilter delay slider default hardkodiran

---

### Agent 9: ProjectIO

**Uloga:** Save/load, project format, import/export, audio format, publish pipeline, asset browser
**~15 fajlova**

**Fajlovi:**
- `crates/rf-bridge/src/project_ffi.rs`, `api_project.rs`
- `crates/rf-engine/src/audio_import.rs`, `export.rs`
- `flutter_ui/lib/src/rust/engine_api.dart` (save/load deo)
- `flutter_ui/lib/services/session_template_service.dart`
- `flutter_ui/lib/widgets/export/` (1 fajl) — loudness analysis panel
- `flutter_ui/lib/widgets/publish/` (1 fajl) — publish pipeline panel
- `flutter_ui/lib/widgets/browser/` (1 fajl) — audio pool browser
- `flutter_ui/lib/widgets/audio/` (1 fajl) — variant group panel

**Kriticna pravila:**
- project_save/project_load su u rf-bridge (NE deprecated stubs)
- Audio SRC: Lanczos-3 sinc interpolacija za export
- Import: bez SRC (Reaper-stil)

**QA bagovi:**
- BUG #4 CRITICAL (deljeno sa MixerArchitect): OutputBus serialization

---

### Agent 10: BuildOps

**Uloga:** Build pipeline, cargo, xcodebuild, dylib, codesign, CI, offline processing, testing infra, benchmarks, WASM
**~50 fajlova**

**Build fajlovi:**
- `Cargo.toml`, `rust-toolchain.toml`, `run-dev.sh`
- `flutter_ui/macos/copy_native_libs.sh`, `flutter_ui/scripts/bundle_dylibs.sh`
- `flutter_ui/macos/Runner/Scripts/clean_xattrs.sh`
- `flutter_ui/macos/Podfile`, `flutter_ui/pubspec.yaml`

**Rust crate-ovi:**
- `rf-offline` (11 fajlova) — config, decoder, encoder, formats, job, processor. Batch processing, bouncing, stem export, native encoders (MP3, FLAC, AAC, Vorbis, Opus).
- `rf-audio-diff` (11 fajlova) — FFT-based spectral comparison, regression testing, determinism verification, golden file management
- `rf-bench` (3 fajla) — Criterion benchmarking, DSP/SIMD/buffer performance profiling
- `rf-coverage` (5 fajlova) — Code coverage analysis, trend tracking, threshold enforcement
- `rf-fuzz` (8 fajlova) — Randomized FFI fuzzing, reproducible test generation
- `rf-release` (4 fajla) — Version management, packaging, changelog generation
- `rf-wasm` (1 fajl) — Web Audio API binding, WASM port

**Kriticna pravila:**
- NIKAD `flutter run` — samo xcodebuild + open .app
- UVEK `~/Library/Developer/Xcode/DerivedData/` (HOME)
- ExFAT workaround, @rpath linking

**QA bagovi:**
- BUG #8 CRITICAL: `edition = "2024"` u Cargo.toml
- BUG #15 HIGH: Hardkodirani Homebrew putevi

---

### Agent 11: QAAgent

**Uloga:** Korektnost, flutter analyze, regression, debug tools, test automation
**Svi fajlovi (cross-cutting)**

**Specificni fajlovi:**
- `.claude/REVIEW_MODE.md`
- `flutter_ui/lib/widgets/debug/` (9 fajlova) — debug console, animation/performance/DSP/signal analysis, FPS counter, RNG seed, insert chain debug, performance overlay
- `flutter_ui/lib/widgets/qa/` (2 fajla) — test combinator, timing validation
- `flutter_ui/lib/widgets/validation/` (1 fajl) — cross-section validation
- `flutter_ui/lib/widgets/test_automation/` (1 fajl) — test automation panel
- `flutter_ui/lib/widgets/edge_case/` (1 fajl) — edge case quick menu

**Odgovornost:**
- `flutter analyze` MORA proci sa 0 errors pre i posle svake promene
- Cross-domain regression testiranje
- Verifikacija da fix jednog buga ne uvodi nove
- Review mode za audit kompletnog sistema

---

### Agent 12: TimelineEngine

**Uloga:** Rust timeline core, transport, playback, warp markers, tempo, clip operations
**~15 fajlova**

**Fajlovi:**
- `flutter_ui/lib/models/timeline_models.dart`
- `flutter_ui/lib/providers/timeline_*` provideri
- `flutter_ui/lib/src/rust/engine_api.dart` (clip ops, transport)
- `crates/rf-engine/src/playback.rs` (transport state machine)
- `crates/rf-engine/src/track_manager.rs` (warp state)
- `crates/rf-engine/src/tempo_state.rs`
- `crates/rf-bridge/src/tempo_state_ffi.rs`
- `crates/rf-engine/src/audio_stretcher.rs`

**Kriticna pravila:**
- ID parsing: `RegExp(r'\d+').firstMatch()`, NIKAD `int.tryParse()`
- Clip ops: destructive sa CoW, invalidate waveform cache

**QA bagovi:**
- BUG #5 CRITICAL: ID parsing nekonzistentnost u engine_api.dart
- BUG #18 MEDIUM: Tempo state bez Dart FFI bindinga
- BUG #19 MEDIUM: Warp markers Phase 4-5 ne postoji

---

### Agent 13: DAWTools

**Uloga:** Editing tools, smart tool, razor, crossfade, clip inspector, recording, DAW utility widgeti
**~25 fajlova**

**Fajlovi:**
- `flutter_ui/lib/providers/smart_tool_provider.dart`
- `flutter_ui/lib/providers/razor_edit_provider.dart`
- `flutter_ui/lib/widgets/editors/crossfade_editor.dart`
- `flutter_ui/lib/widgets/editors/waveform_trim_editor.dart`
- `flutter_ui/lib/widgets/panels/` (10 fajlova) — clip inspector, audio alignment, gain envelopes, loop/groove/scale editors, track versions, macro controls, logical editor, connection monitor
- `flutter_ui/lib/widgets/daw/` (6 fajlova) — audio graph painter, automation curve editor, clip gain envelope, marker system, auto color rules, spectral heatmap
- `flutter_ui/lib/widgets/recording/` (2 fajla) — recording controls, recording panel
- `flutter_ui/lib/widgets/editor/` (1 fajl) — full clip editor
- `flutter_ui/lib/widgets/session_replay/` (2 fajla) — session replay panel
- `flutter_ui/lib/widgets/template/` (1 fajl) — template gallery
- `flutter_ui/lib/widgets/project/` (3 fajla) — project versions, schema migration, track templates
- `.claude/architecture/DAW_EDITING_TOOLS.md`, `DAW_TOOLS_QA.md`

---

### Agent 14: LiveServer

**Uloga:** Live server integracija, networking, remote sync
**~5 fajlova**

- `crates/rf-connector/` (4 fajla) — WebSocket/TCP, protocol, commands, connector
- `.claude/architecture/LIVE_SERVER_INTEGRATION.md`

**Status:** Implementiran, maintenance mode

---

### Agent 15: SecurityAgent

**Uloga:** FFI safety, sandbox, input validation, codesign integritet
**~10 fajlova**

- Svi FFI granicni fajlovi (rf-engine/ffi.rs, rf-bridge/*.rs)
- `flutter_ui/lib/services/input_validator.dart`
- `flutter_ui/lib/main.dart` (PathValidator)
- `flutter_ui/macos/Runner/*.swift` (entitlements)

**Poznati rizici:**
- `cstr_to_string()` buffer overflow rizik (`ffi.rs:279-306`)
- `string_to_cstr()` silent null return (`ffi.rs:309-313`)
- 45 unwrap() poziva u rf-bridge FFI kodu

---

### Agent 16: PerformanceAgent

**Uloga:** Profiling, memory management, CPU optimization, rebuild storms
**Svi fajlovi (cross-cutting)**

**Odgovornost:**
- Memory leak detekcija
- CPU profiling audio thread-a
- Widget rebuild storm detekcija
- Waveform cache eviction efikasnost
- Audio buffer underrun analiza
- Lock contention analiza

---

### Agent 17: PluginArchitect

**Uloga:** VST3/AU/CLAP/LV2/ARA2 plugin hosting ekosistem
**~20 fajlova**

**Rust crate-ovi:**
- `rf-plugin` (11 fajlova) — ultimate_scanner, ara2, sandbox. VST3/AU/CLAP/LV2/ARA2 parallel scanning, sandboxing, loading.
- `rf-plugin-host` (1 fajl) — Out-of-process GUI host (izbegava Flutter Metal konflikte)

**Flutter widgeti:**
- `flutter_ui/lib/widgets/plugin/` (7 fajlova) — plugin browser/selector, editor window, slot widget, state/PDC indicators, missing plugin dialog

**Odgovornost:**
- Plugin scanning (parallel, async)
- Plugin sandboxing (crash isolation)
- Plugin GUI hosting (out-of-process, floating window)
- ARA2 integracija (Melodyne-level editing)
- Plugin state save/restore
- PDC (Plugin Delay Compensation)
- Insert chain management (pre-fader, post-fader)
- CLAP extensions: params flush, state stream, latency, GUI
- LV2: URID map, Atom MIDI buffers, TTL parsing

**Kriticna pravila:**
- CLAP Drop: MORA `plugin_ptr = null` posle `destroy()` — sprecava double-free
- LV2 Drop: MORA `handle = null_mut` + `descriptor = null` posle `cleanup()`
- Plugin process(): `midi_in`/`midi_out` parametri u SVIH 5 implementacija

---

### Agent 18: SlotIntelligence

**Uloga:** Rust slot audio intelligence stack — AUREXIS, ALE, FluxMacro, Stage, Ingest, synthetic engine
**~200 fajlova — NAJVECI DOMEN**

**Rust crate-ovi:**
- `rf-aurexis` (68 fajlova) — **AUREXIS Intelligence Engine**: core, drc, energy, escalation, gad, geometry, priority, psycho, spectral, sss, variation, volatility. Deterministicka slot audio inteligencija, parameter mapping, safety envelopes, voice allocation, energy governance, psihoakusticka analiza.
- `rf-ale` (8 fajlova) — **Adaptive Layer Engine**: context, engine, profile, rules, signals, stability, transitions. Context-aware music sistem, layer transitions, signal-driven adaptation.
- `rf-slot-lab` (30 fajlova) — **Synthetic Slot Engine**: game_model, synthetic_engine, feature_registry, scenario, timeline. Deterministicki slot simulator, feature chapters, stage generation, volatility control.
- `rf-fluxmacro` (31 fajl) — **Deterministicki Orchestration Engine**: context, parser, interpreter, rules, steps, security, hash, reporter. Casino-grade slot audio automation, QA simulacija, manifest building, release packaging.
- `rf-stage` (6 fajlova) — **Stage System**: Universal slot game phase definitions, event schema, stage event spec.
- `rf-ingest` (11 fajlova) — **Universal Ingest System**: Adapters za bilo koji slot engine, configuration parsing, schema validation.

**Flutter widgeti:**
- `widgets/ale/` (7 fajlova) — rule editor, context editor, transition editor, layer visualizer, signal monitor, stability config, panel manager
- `widgets/aurexis/` (9 fajlova) — aurexis panel, QA framework, theme manager, behavior slider, memory budget, compliance report, cabinet simulator, audit trail, retheme wizard
- `widgets/stage_ingest/` (10 fajlova) — stage ingest panel, live connector, mock engine, network diagnostics, latency histogram, event mapping, JSON path explorer, adapter wizard, stage trace viewer

**Odgovornost:**
- AUREXIS deterministicka audio inteligencija
- Adaptive Layer Engine (ALE) za dynamic music
- FluxMacro automation i QA simulacija
- Stage phase system za slot game lifecycle
- Ingest adapteri za razlicite slot engine-e
- Synthetic engine za testiranje bez pravog hardware-a
- Casino-grade determinism i compliance
- Energy governance i safety envelopes

**Razlika od GameArchitect:**
- GameArchitect = **Dart** game flow, executors, behavior tree (frontend logika)
- SlotIntelligence = **Rust** AI engine, deterministicko procesiranje (backend inteligencija)

---

### Agent 19: MediaTimeline

**Uloga:** Flutter timeline UI — clip widgeti, automation tracks, warp handles, comping, track lanes
**~30 fajlova**

**Widgeti:**
- `flutter_ui/lib/widgets/timeline/` (26 fajlova) — clip widget, automation/tempo/marker/video tracks, time ruler, selection/stretch/freeze overlays, comping, warp handles, time stretch editor, track lanes
- `flutter_ui/lib/widgets/waveform/` (4 fajla) — ultimate waveform, waveform painter, cache management, LUFS normalization indicator
- `flutter_ui/lib/widgets/transport/` (3 fajla) — transport bar, ultimate transport bar, metronome settings

**Razlika od TimelineEngine:**
- TimelineEngine = **Rust** core (playback.rs, track_manager.rs, tempo_state.rs) — engine logika
- MediaTimeline = **Flutter** UI (clip widget, automation tracks, waveform rendering) — vizualni sloj

**Odgovornost:**
- Clip rendering i interakcija
- Automation lane vizualizacija
- Warp handle UI i drag interakcija
- Comping (take management) UI
- Track lane konfiguracija
- Time ruler rendering
- Transport bar kontrole
- Waveform rendering i cache management

---

### Agent 20: SpatialAudio

**Uloga:** Immersive audio — Atmos, HOA, MPEG-H, binaural rendering, 3D spatial processing
**~25 fajlova**

**Rust crate:**
- `rf-spatial` (17 fajlova) — Atmos, Higher Order Ambisonics (HOA), MPEG-H, binaural rendering, 3D spatial processing

**Flutter widgeti:**
- `flutter_ui/lib/widgets/spatial/` (7 fajlova) — anchor monitor, auto spatial, bus policy editor, intent rule editor, spatial event visualizer, spatial stats, spatial widgets

**Odgovornost:**
- Dolby Atmos renderer
- HOA (Higher Order Ambisonics) encoding/decoding
- MPEG-H authoring
- Binaural rendering (headphone spatialization)
- 3D object panning
- Spatial bus policy management
- Intent-based spatial mixing

---

### Agent 21: MeteringPro

**Uloga:** Profesionalni metering UI — LUFS, goniometer, vectorscope, correlation, loudness history, DSP attribution
**~15 fajlova**

**Widgeti:**
- `flutter_ui/lib/widgets/meters/` (11 fajlova) — loudness meter (LUFS), correlation/goniometer/vectorscope, metering panel, pro metering, loudness history, PDC display, loudness graphs
- `flutter_ui/lib/widgets/spectrum/` (2 fajla) — GPU spectrum widget, spectrum analyzer
- `flutter_ui/lib/widgets/profiler/` (4 fajla) — DSP attribution, latency profiler, stage detective, voice steal analyzer

**Odgovornost:**
- LUFS metering (Streaming, Broadcast, Apple, YouTube, Spotify standardi)
- Goniometer/vectorscope rendering
- Correlation metering
- Loudness history grafovi
- PDC (Plugin Delay Compensation) display
- DSP load attribution (koji plugin trosi koliko CPU)
- Latency profiling vizualizacija
- Voice steal analiza

---

### Agent 22: ScriptingEngine

**Uloga:** Lua scripting, automation scripts, player behavior simulacija
**~5 fajlova**

**Rust crate:**
- `rf-script` (1 fajl) — Thread-safe Lua 5.4 FFI (mlua), automation scripting

**Flutter widgeti:**
- `flutter_ui/lib/widgets/scripting/` (2 fajla) — script console, script editor panel

**Odgovornost:**
- Lua runtime integracija
- Script editor sa syntax highlighting
- Console za script output
- Automation scripting API
- Player behavior simulacija za testiranje

---

### Agent 23: MIDIEditor

**Uloga:** MIDI editing — piano roll, MIDI clip, expression maps, articulation mapping
**~5 fajlova**

**Widgeti:**
- `flutter_ui/lib/widgets/mice/` (2 fajla) — MIDI clip widget, piano roll widget

**Provideri:**
- Expression maps provider — MIDI articulation mapping

**Odgovornost:**
- Piano roll editor (note input, velocity, CC editing)
- MIDI clip rendering
- Expression map konfiguracija (Cubase-stil articulation mapping)
- MIDI quantization
- MIDI event editing

---

### Agent 24: VideoSync

**Uloga:** Video decoding, timecode sync, audio-visual alignment
**~6 fajlova**

**Rust crate:**
- `rf-video` (5 fajlova) — FFmpeg integracija, MP4 parsing, video decoding, timecode sync

**Flutter widgeti:**
- `flutter_ui/lib/widgets/video/` (1 fajl) — video export panel

**Odgovornost:**
- Video file decoding (MP4, MOV, AVI)
- Timecode synchronizacija (SMPTE)
- Audio-visual alignment
- Video export sa bounced audio
- Frame-accurate playback sync

---

## Workflow

```
Korisnik
   |
   v
Orchestrator (Agent 0)
   |
   +--- RUST CORE ---
   |  +---> AudioEngine (1)       --- rf-engine, rf-bridge, rf-audio, rf-realtime, rf-core
   |  +---> DSPSpecialist (8)     --- rf-dsp, rf-restore, rf-master, rf-pitch, rf-r8brain, rf-ml
   |  +---> TimelineEngine (12)   --- playback.rs, tempo_state.rs, track_manager.rs
   |  +---> PluginArchitect (17)  --- rf-plugin, rf-plugin-host
   |  +---> SlotIntelligence (18) --- rf-aurexis, rf-ale, rf-slot-lab, rf-fluxmacro, rf-stage, rf-ingest
   |  +---> SpatialAudio (20)     --- rf-spatial
   |  +---> ScriptingEngine (22)  --- rf-script
   |  +---> VideoSync (24)        --- rf-video
   |
   +--- FLUTTER DAW ---
   |  +---> MixerArchitect (2)    --- mixer, routing, channel, fader
   |  +---> UIEngineer (7)        --- common, layout, gestures, lifecycle
   |  +---> MediaTimeline (19)    --- timeline UI, waveform, transport
   |  +---> DAWTools (13)         --- editing tools, panels, recording
   |  +---> MeteringPro (21)      --- meters, spectrum, profiler
   |  +---> MIDIEditor (23)       --- piano roll, expression maps
   |
   +--- SLOTLAB ---
   |  +---> SlotLabUI (3)         --- screen, koordinator, lower zone (~70 fajlova)
   |  +---> SlotLabEvents (4)     --- event registry, middleware, FFNC (~75 fajlova)
   |  +---> SlotLabAudio (5)      --- voice mixer, bus, ducking (~28 fajlova)
   |  +---> GameArchitect (6)     --- Dart game flow, executors (~60 fajlova)
   |
   +--- INFRASTRUCTURE ---
      +---> ProjectIO (9)         --- save/load, export, publish
      +---> BuildOps (10)         --- build, CI, offline, benchmarks
      +---> QAAgent (11)          --- analyze, regression, debug
      +---> LiveServer (14)       --- networking
      +---> SecurityAgent (15)    --- FFI safety, sandbox
      +---> PerformanceAgent (16) --- profiling, memory, CPU
```

---

## QA Nalaz — Kompletna Tabela Bagova

### KRITICNI (9 bagova)

| # | Severity | Agent | Opis | Lokacija |
|---|----------|-------|------|----------|
| 1 | CRITICAL | AudioEngine | Wave cache alloc/free mismatch | `ffi.rs:20150,20169` |
| 2 | CRITICAL | AudioEngine | Video frame dealloc type mismatch | `ffi.rs:20932` |
| 3 | CRITICAL | AudioEngine | Sample rate desync — CLICK_TRACK/VIDEO_ENGINE/EVENT_MANAGER | `ffi.rs:133-159` |
| 4 | CRITICAL | MixerArchitect | OutputBus.index umesto .engineIndex u session template | `session_template_service.dart:47,58` |
| 5 | CRITICAL | TimelineEngine | ID parsing — normalizeClip/reverseClip/applyGainToClip | `engine_api.dart:476,485,561` |
| 6 | CRITICAL | MixerArchitect | replaceAll ID parsing u setTrackName | `mixer_provider.dart` |
| 7 | CRITICAL | DSPSpecialist | BPM hardkodiran 120.0 u 4 DSP struct-a | `delay.rs:521,982`, `dynamics.rs:602`, `reverb.rs:2636` |
| 8 | CRITICAL | BuildOps | edition = "2024" — ne kompajlira na stable | `Cargo.toml:51` |
| 9 | ~~FIXED~~ | SlotLabEvents | ~~Mrtav kod _onAudioDroppedOnStage() — uklonjen~~ | N/A |

### VISOKI (8 bagova)

| # | Severity | Agent | Opis | Lokacija |
|---|----------|-------|------|----------|
| 10 | HIGH | MixerArchitect | Post-fader insert index hardkodiran slotIndex < 4 | `mixer_provider.dart:2842,2857` |
| 11 | HIGH | MixerArchitect | Default bus volumes sve 1.0 | `mixer_dsp_provider.dart:185-191` |
| 12 | HIGH | AudioEngine | Waveform SR fallback hardkodiran 48000 | `ffi.rs:2020` |
| 13 | HIGH | AudioEngine | Eviction thread nema panic handler | `playback.rs:210-225` |
| 14 | HIGH | AudioEngine | Audio thread try_write() silent skip | `playback.rs:5208-5340` |
| 15 | HIGH | BuildOps | Hardkodirani Homebrew putevi | `copy_native_libs.sh:29-30` |
| 16 | HIGH | UIEngineer | 16x TextEditingController u build() | Vise fajlova |
| 17 | HIGH | UIEngineer | 2x GestureDetector + HardwareKeyboard | `slot_voice_mixer.dart:473`, `ultimate_audio_panel.dart:3271` |

### SREDNJI (6 bagova)

| # | Severity | Agent | Opis | Lokacija |
|---|----------|-------|------|----------|
| 18 | MEDIUM | TimelineEngine | Tempo state bez Dart FFI bindinga | `tempo_state.rs` |
| 19 | MEDIUM | TimelineEngine | Warp markers Phase 4-5 ne postoji | timeline widget |
| 20 | MEDIUM | MixerArchitect | Dual insert state — 3 izvora istine | `engine_connected_layout.dart` |
| 21 | MEDIUM | UIEngineer | print() u MainFlutterWindow.swift | `MainFlutterWindow.swift:283` |
| 22 | MEDIUM | BuildOps | wgpu device.poll() unused Result | `gpu.rs:273,495,690` |
| 23 | MEDIUM | DSPSpecialist | FabFilter delay slider default | `fabfilter_delay_panel.dart:1299` |

---

## Potvrdjeno Ispravno (iz QA)

- EventRegistry single source of truth arhitektura
- SlotLab listener lifecycle
- FaderCurve math (svi edge cases)
- Pan semantika (L=-1.0, R=+1.0 korektno)
- Biquad TDF-II sa SIMD fallback chain
- Denormal handling (CPU + software)
- FFT spektrum (Hann, RMS scaling, smoothing)
- Metering (try_write svuda)
- GetIt DI (70+ providera, nema circular deps)
- Project save/load (rf-bridge, ne deprecated stubs)
- Audio SRC (Lanczos-3 sinc)
- Win tier system (data-driven)
- Moderne mixer metode
- SmartToolProvider singleton
- desktop_drop workaround
- CompositeEventSystemProvider NE registruje u EventRegistry
- Async mounted checks u celom SlotLab-u
- Input validation (FFIBoundsChecker)

---

*Dokument generisan: 2026-03-30*
*Finalna verzija: 25 agenata (0-24)*
*Pokriva: 500+ source fajlova, 34 Rust crate-a, 57 widget direktorijuma*
*Na osnovu: Ultimativni QA audit + exhaustive codebase mapping*
