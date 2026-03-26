# FluxForge Studio — MASTER TODO

## Zamke — SlotLab

- `slot_lab_screen.dart` — 15K+ linija, NE MOŽE se razbiti. Čitaj sa `offset/limit`.
- `_bigWinEndFired` guard — sprečava dupli BIG_WIN_END trigger na skip tokom end hold
- BIG_WIN_END composite SAM handluje stop BIG_WIN_START (NE ručno `stopEvent`)
- `hasExplicitFadeActions` u event_registry MORA da uključuje FadeVoice/StopVoice
- FFNC rename: BIG_WIN_START/END su `mus_` (music bus), NE `sfx_`
- `_syncEventToRegistry` OBAVEZNO posle svakog composite refresh-a (stale registry bug)
- FS auto-spin: balance se NE oduzima tokom free spins-a (`_isInFreeSpins` guard)
- EventRegistry: JEDAN put registracije — SAMO `_syncEventToRegistry()` u `slot_lab_screen.dart`
- NIKADA registracija u `composite_event_system_provider.dart` — dva sistema se medjusobno brisu
- ID format: `event.id` (npr. `audio_REEL_STOP`), NIKADA `composite_${id}_${STAGE}`
- `_syncCompositeToMiddleware` → MiddlewareEvent sistem, NE EventRegistry
- SlotLabProvider je MRTAV KOD — koristi `SlotLabCoordinator` (typedef u `slot_lab_coordinator.dart`)
- Middleware composite events = JEDINI izvor istine za sav SlotLab audio
- Win tier: NE hardkodirati labele/boje/ikone/trajanja — koristi tier identifikatore "WIN 1"-"WIN 5", data-driven (P5 WinTierConfig)

## Zamke — Audio Thread

- NULA alokacija, NULA lockova, NULA panica
- `cache.peek()` na audio thread (read lock), NIKADA `cache.get()` (write lock)
- `lufs_meter.try_write()` / `true_peak_meter.try_write()` — nikada blocking `.write()`
- `self.sample_rate()` za fade kalkulacije, NIKADA hardkodiran 48000
- `SHARED_METERS.sample_rate` synced na device pri `audio_start_stream`
- Samo stack alokacije, pre-alocirani buffers, atomics, SIMD
- Lock-free: `rtrb::RingBuffer` za UI→Audio thread

## Zamke — FFI / Rust

- Dva engine globala: `PLAYBACK_ENGINE` (LazyLock, uvek init) vs `ENGINE` (Option, starts None)
- `TRACK_MANAGER`, `WAVEFORM_CACHE`, `IMPORTED_AUDIO` — `pub(crate)` u ffi.rs, pristup iz clip_ops.rs
- OutputBus: koristi `.engineIndex`, NIKADA `.index` za FFI
- Clip operations: destructive, `Arc::make_mut` za CoW, invalidate waveform cache posle
- Fade destructive: bake curve → CLEAR metadata (fade_in=0.0) da spreci double-apply
- ID parsing: `RegExp(r'\d+').firstMatch(id)`, NIKADA `replaceAll(RegExp(r'[^0-9]'), '')`
- CLAP Drop: MORA `plugin_ptr = null` posle `destroy()` — sprečava double-free
- LV2 Drop: MORA `handle = null_mut` + `descriptor = null` posle `cleanup()`
- Plugin process(): `midi_in`/`midi_out` parametri u SVIH 5 implementacija (VST3/AU/CLAP/LV2/Internal)
- Multi-output routing: JEDAN `try_read()` scope za ceo channel map — sprečava race condition
- TrackType enum: Audio/Instrument/Bus/Aux — Midi/Master mapiraju na Audio pri load-u
- `toNativeUtf8()` alocira sa calloc → MORA `calloc.free()`, NIKADA `malloc.free()`

## Zamke — Flutter UI

- SmartToolProvider: JEDAN instance via ChangeNotifierProvider u `main.dart:239`
- Split View: static ref counting `_engineRefCount`, provideri MORAJU biti GetIt singletoni
- Modifier keys → `Listener.onPointerDown`, NIKADA `GestureDetector.onTap` + HardwareKeyboard
- FocusNode/Controllers → `initState()` + `dispose()`, NIKADA inline u `build()`
- Keyboard handlers → EditableText ancestor guard kao prva provera
- Nested drag → `Listener.onPointerDown/Move/Up` (bypass gesture arena)
- Stereo waveform → threshold `trackHeight > 60`
- Optimistic state → nullable `bool? _optimisticActive`, NIKADA Timer
- MixerProvider: `setChannelVolume()`, `toggleChannelMute()`, `toggleChannelSolo()`, `renameChannel()`
- Stereo dual pan: `pan=-1.0` je hard-left (NE bug), `panRight=+1.0` hard-right
- FaderCurve klasa u `audio_math.dart` — jedini izvor istine za volume fadere
- desktop_drop plugin: fullscreen DropTarget NSView presrece mouse. Timer (2s) u MainFlutterWindow.swift uklanja non-Flutter subview-ove

## Zamke — Build

- ExFAT disk: macOS `._*` fajlovi → codesign fail. UVEK xcodebuild sa derivedData na HOME
- NIKADA `flutter run` — samo xcodebuild + open .app
- UVEK `~/Library/Developer/Xcode/DerivedData/`, NIKADA `/Library/Developer/`

## Status — Kompletno

- Voice Mixer, DAW Mixer, SlotLab WoO Game Flow (W1-W7 + polish)
- 16 subsystem providera, clip operations, FFNC audio triggering
- SFX Pipeline Wizard — svih 6 koraka (21K UI + rf-offline backend)
- Time Stretch — rf-dsp + FFI + Flutter bindings (koristi SlotLab)
- Warp Markers — data modeli + UI widgeti (warp_handles, audio_warping_panel, time_stretch_editor)
- Live Server Integration — WebSocket/TCP (rf-connector) + JSON-RPC server (port 8765)
- AUREXIS: GEG, DPM, SAMCL, Device Preview, SAM — Rust + FFI + Dart provideri kompletni
- VST3/AU plugin hosting — skeniranje, loading, GUI (out-of-process), insert chain, PDC
- Pitch Shift FFI — 20+ FFI funkcija (detect, analyze, correct, elastic, clip, voice pitch) + Dart bindings + UI paneli
- MIDI Instrument Pipeline — MidiBuffer u process(), TrackType::Instrument, MIDI clip rendering u audio loop, plugin lifecycle
- Multi-Output Routing — per-channel bus routing via output_channel_map (do 64ch), PinConnector, project save/load
- CLAP Plugin Hosting — dlopen + clap_entry + factory + process() + lifecycle + null-safe Drop
- LV2 Plugin Hosting — dlopen + lv2_descriptor + instantiate + run() + port connection + TTL parsing + null-safe Drop
- Project Save/Load — prerutirano na rf-bridge project_ffi.rs, calloc fix, automation CurveType/ParamId, clip properties

## Nedavno završeno (2026-03-25)

- Plugin Automation — wire UI → FFI, param_name parse bug fix, PluginParamId class, 10 provider metoda
- VST3/AU GUI Resize — resize_editor implementiran (objc2 NSWindow), Flutter drag-to-resize handle
- Plugin Preset Browser — PluginInstance trait (preset_count/name/load), FFI, Dart, UI menu
- CLAP Full Extensions — params (flush event), state (stream), latency, GUI (floating cocoa/win32/x11)
- LV2 URID Map — global thread-safe URI↔integer mapping (17 pre-registered), Atom MIDI buffers
- Sidechain Routing — InsertProcessor.set_sidechain_input(), CompressorWrapper integration, FFI
- Plugin Automation Recording — slider onChangeStart/onChanged/onChangeEnd → FFI touch/release
- GR Metering — VEĆ KOMPLETNO (insert_get_meter FFI + Dart + CompressorWrapper.get_meter)
- FFT Metering — VEĆ KOMPLETNO (pro_eq_get_spectrum FFI + get_spectrum_data)

## Preostalo (TODO)

- LV2 GUI hosting (Suil library integration — zahteva external C dependency)
- VST3 native GUI on Windows/Linux (IPlugView COM — zahteva platform-specific kod)

## Reference

- `.claude/architecture/WRATH_OF_OLYMPUS_GAME_FLOW.md` — WoO flow spec
- `.claude/architecture/SLOTLAB_COMPLETE_INVENTORY.md` — 23 blokova inventar
- `.claude/architecture/SLOT_LAB_SYSTEM.md` — Stage pipeline, providers, FFI
- `.claude/architecture/SLOTLAB_VOICE_MIXER.md` — Voice mixer arhitektura
- `.claude/architecture/DAW_EDITING_TOOLS.md` — DAW alati + QA
- `.claude/docs/VST_HOSTING_ARCHITECTURE.md` — VST3/AU/CLAP hosting spec
- `.claude/docs/DEPENDENCY_INJECTION.md` — GetIt/provideri
- `.claude/docs/TROUBLESHOOTING.md` — poznati problemi i rešenja
- `.claude/specs/SFX_PIPELINE_WIZARD.md` — SFX Pipeline 6-step spec
- `.claude/specs/FLUXFORGE_MASTER_SPEC.md` — 17 sistema pregled
