# FluxForge Studio — MASTER TODO

## Bug Fix Status (2026-04-21 Audit)

**84/84 bagova reseno** ✅ (osim #66 — feature request, ne bug)

| Kategorija | Bagovi | Status |
|------------|--------|--------|
| KRITIČNI (#1-#9) | heap corruption, double-free, SR desync, session template, clip ID, BPM hardcode, edition 2024, dead code | SVE FIXOVANO ✅ |
| VISOKI (#10-#17) | post-fader index, bus volumes, waveform SR, eviction panic, audio skip, homebrew paths, TextEditingController, GestureDetector | SVE FIXOVANO ✅ |
| SREDNJI (#18-#23) | tempo state, warp markers, dual insert, Swift print, wgpu poll, FabFilter slider | SVE FIXOVANO ✅ |
| ROUND 2 KRITIČNI (#24-#29) | MIDI forwarding, ALE panic, drop frame, FFmpeg unsafe, LUFS maxTruePeak, Lua sandbox | SVE FIXOVANO ✅ |
| ROUND 2 VISOKI (#30-#43) | plugin unload, chain TOCTOU, LV2 URID, LV2 SR, VBAP, HRTF, VCA trim, routing feedback, NPE, schema migration, Lua timeout, path traversal, AUREXIS FP, ingest unwrap | SVE FIXOVANO ✅ |
| ROUND 2 SREDNJI (#44-#52) | floating timer, bezier X CP, waveform cache, grid FP drift, binaural buffer, FluxMacro cancel, GameModel validation, clip inspector ln(), script console | SVE FIXOVANO ✅ |
| ROUND 2 DODATNI (#53-#84) | plugin safety, CLAP string, buffer pool, editor null, bypass mounted, instance TOCTOU, AUREXIS replay, ALE builtins, engine division, stage timing, scenario bounds, snapshot diff, atmos gain, room sim, video cache, timecode, frame count, LUFS indicator, IO selector, group manager, automation badge, stem routing, send pan, control room, clip pitch, clip gain, loop editor, logical editor, project versions (x2), offline encoder, bundle dylibs | SVE FIXOVANO ✅ |

Poslednje fixovano (2026-04-21): #15 (otool detection), #22 (wgpu poll logging), #51 (dead code _ln()), #73 (automation badge → AutomationProvider), Spectral DNA FFI bindings

---


## QA Bagovi — KRITIČNI (fix pre release-a)

### BUG #1: Wave Cache Alloc/Free Mismatch [AudioEngine]
- **Fajl:** `crates/rf-engine/src/ffi.rs:20150,20169`
- **Problem:** `wave_cache_query_tiles()` alocira `Layout::array::<f32>(flat.len())`, ali `wave_cache_free_tiles()` dealocira sa `(count as usize).saturating_mul(2)`. Ako `flat.len() != count * 2` -> heap corruption.
- **Fix:** Uskladiti alokaciju i dealokaciju — ili obe koriste `flat.len()`, ili obe koriste `count * 2` sa istom semantikom.
- **Uticaj:** Heap corruption, crash, memory corruption

### BUG #2: Video Frame Dealloc Type Mismatch [AudioEngine]
- **Fajl:** `crates/rf-engine/src/ffi.rs:20932`
- **Problem:** `video_free_frame()` koristi `Box::from_raw(std::ptr::slice_from_raw_parts_mut(data, size))`. `slice_from_raw_parts_mut` pravi `*mut [u8]`, ali original alokacija mozda nije Box<[u8]>. Dealloc metadata mismatch.
- **Fix:** Koristiti isti alokacioni mehanizam za alloc i free. Ako je allocirano sa `Vec::into_raw_parts()`, koristiti `Vec::from_raw_parts()` za free.
- **Uticaj:** Double-free, use-after-free, heap corruption

### BUG #3: Sample Rate Desync [AudioEngine]
- **Fajl:** `crates/rf-engine/src/ffi.rs:133-159, 2846-2868`
- **Problem:** `engine_set_sample_rate()` azurira SAMO `PLAYBACK_ENGINE`. Ne azurira:
  - `CLICK_TRACK` (line 138) — click track na pogresnom tempu
  - `VIDEO_ENGINE` (line 156) — video sync drift
  - `EVENT_MANAGER_PARTS` (line 159) — event timing pogresan
- **Fix:** Dodati `set_sample_rate()` pozive za sva tri globala u `engine_set_sample_rate()`.
- **Uticaj:** Click track pogresno, video desync, event timing off

### BUG #4: OutputBus.index u Session Template [MixerArchitect]
- **Fajl:** `flutter_ui/lib/services/session_template_service.dart:47,58`
- **Problem:** `toJson()` koristi `outputBus.index` (enum pozicija), `fromJson()` rekonstruise iz enum pozicije. Treba `.engineIndex` za korektno FFI mapiranje.
- **Fix:** Line 47: `'outputBus': outputBus.engineIndex`. Line 58: lookup po engineIndex umesto `OutputBus.values[index]`.
- **Uticaj:** Load saved session -> tracks na pogresnim busovima

### BUG #5: Clip Operations ID Parsing [TimelineEngine]
- **Fajl:** `flutter_ui/lib/src/rust/engine_api.dart:476,485,561`
- **Problem:** Nekonzistentnost:
  - `normalizeClip()` (line 476): `int.tryParse(clipId)` — POGRESNO
  - `reverseClip()` (line 485): `int.tryParse(clipId)` — POGRESNO
  - `applyGainToClip()` (line 561): `int.tryParse(clipId)` — POGRESNO
  - `fadeInClip()` (line 492): `_parseClipId()` — ISPRAVNO
  - `fadeOutClip()` (line 498): `_parseClipId()` — ISPRAVNO
- **Fix:** Sve clip operacije moraju koristiti `_parseClipId()` koji koristi `RegExp(r'\d+').firstMatch()`.
- **Uticaj:** Clip operacije failuju na compound ID formatima (npr. "clip_12")

### BUG #6: replaceAll ID Parsing u Mixer [MixerArchitect]
- **Fajl:** `flutter_ui/lib/providers/mixer_provider.dart`
- **Problem:** `int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), ''))` — spaja SVE cifre. "clip_12_track_3" -> "123" umesto "12".
- **Fix:** Koristiti `RegExp(r'\d+').firstMatch(id)` da izvuce PRVI numericki segment.
- **Uticaj:** Pogresan track ID -> operacija na pogresnom track-u

### BUG #7: BPM Hardkodiran 120.0 u Rust DSP [DSPSpecialist]
- **Fajl:** `crates/rf-dsp/src/delay.rs:521,982`, `crates/rf-dsp/src/dynamics.rs:602`, `crates/rf-dsp/src/reverb.rs:2636`
- **Problem:** Cetiri DSP strukture inicijalizuju BPM na 120.0 u `new()`:
  - `DelayLfo::new()` — delay.rs:521
  - `PingPongDelay::new()` — delay.rs:982
  - `Compressor::new()` — dynamics.rs:602
  - `Reverb::new()` — reverb.rs:2636
- **Fix:** Dodati `set_bpm()` poziv odmah posle kreacije, ili proslediti BPM u konstruktor.
- **Uticaj:** Tempo-synced DSP efekti ignorisu projekat BPM na startu

### BUG #8: Cargo Edition 2024 [BuildOps]
- **Fajl:** `Cargo.toml:51`
- **Problem:** `edition = "2024"` nije standardna Rust edicija. Kompajlira samo na nightly (rust-toolchain.toml). Blokira stable release.
- **Fix:** Ili promeniti na `edition = "2021"`, ili eksplicitno dokumentovati nightly zahtev u README i build instrukcijama.
- **Uticaj:** Build fail na stable/beta Rust

### BUG #9: Mrtav Kod sa registerEvent() Bypass [SlotLabEvents]
- **Fajl:** `flutter_ui/lib/screens/slot_lab_screen.dart:13120-13192`
- **Problem:** `_onAudioDroppedOnStage()` direktno poziva `eventRegistry.registerEvent()` na linijama 13153 i 13177, zaobilazeci `_syncEventToRegistry()`. Metoda je trenutno mrtav kod (niko je ne poziva), ali ako se aktivira -> EventRegistry race, nema zvuka.
- **Fix:** UKLONITI celu metodu, ili refaktorisati da koristi `_syncEventToRegistry()` pattern.
- **Uticaj:** Ako se aktivira: event trka, dupla registracija, nema zvuka

---

## QA Bagovi — VISOKI PRIORITET

### BUG #10: Post-Fader Insert Index Hardkodiran [MixerArchitect]
- **Fajl:** `flutter_ui/lib/providers/mixer_provider.dart:2842,2857`
- **Problem:** `final isPreFader = slotIndex < 4;` — hardkodiran threshold. Master kanal ima 8 pre-fader slotova, regular 4.
- **Fix:** Koristiti dinamicki `maxPre` (8 za master, 4 za regular) umesto hardkodiranog 4.

### BUG #11: Default Bus Volumes [MixerArchitect]
- **Fajl:** `flutter_ui/lib/providers/mixer_dsp_provider.dart:185-191`
- **Problem:** Svi busovi inicijalizovani na `volume: 1.0`. DAW_AUDIO_ROUTING.md specificira: Master=0.85, Music=0.7, SFX=0.9, Ambience=0.5, Voice=0.95.
- **Fix:** Azurirati `kDefaultBuses` da koristi dokumentovane vrednosti.

### BUG #12: Waveform SR Fallback [AudioEngine]
- **Fajl:** `crates/rf-engine/src/ffi.rs:2020`
- **Problem:** `engine_get_waveform_sample_rate()` vraca hardkodiran 48000 ako cache miss. Treba da vrati PLAYBACK_ENGINE sample rate.
- **Fix:** `PLAYBACK_ENGINE.position.sample_rate()` kao fallback umesto 48000.

### BUG #13: Eviction Thread Panic Handler [AudioEngine]
- **Fajl:** `crates/rf-engine/src/playback.rs:210-225`
- **Problem:** Eviction thread nema panic handler. `let _ = thread::Builder::new().spawn(...)` ignorise JoinHandle. Ako thread panic-uje, tiho umire.
- **Fix:** Dodati panic handler (catch_unwind ili log), sacuvati JoinHandle za graceful shutdown.
- **Uticaj:** Silent thread death -> cache nikad evicted -> memory leak -> OOM

### BUG #14: Audio Thread Silent Skip [AudioEngine]
- **Fajl:** `crates/rf-engine/src/playback.rs:5208-5340`
- **Problem:** `process()` radi `try_write()` na `bus_buffers`. Ako UI drzi write lock, audio thread vraca early bez processinga. Ceo frame tiho preskocen.
- **Fix:** Lock-free atomic update ili dupli buffer (read/write swap).
- **Uticaj:** Audio dropouts, silent frames tokom UI operacija

### BUG #15: Hardkodirani Homebrew Putevi [BuildOps]
- **Fajl:** `flutter_ui/macos/copy_native_libs.sh:29-30`
- **Problem:** `/opt/homebrew/opt/flac/lib/libFLAC.14.dylib` i `/opt/homebrew/opt/libogg/lib/libogg.0.dylib` — hardkodirani.
- **Fix:** Koristiti `$(brew --prefix flac)/lib/libFLAC.14.dylib` za dinamicke puteve.

### BUG #16: TextEditingController u build() [UIEngineer]
- **Problem:** 16 instanci TextEditingController kreiran inline u `build()` umesto `initState()`. Memory leak — kontroler se kreira na svakom rebuild-u, nikad dispose.
- **Fajlovi:**
  - `priority_tier_preset_panel.dart:390,404`
  - `branding_panel.dart:537`
  - `input_bus_panel.dart:165`
  - `right_zone.dart:336`
  - `crossfade_editor.dart:635`
  - `soundbank_panel.dart:1249`
  - `test_combinator_panel.dart:178`
  - `macro_config_editor.dart:237,460`
  - `events_panel_widget.dart:1321,1893`
  - `feature_builder_panel.dart:807`
  - `game_model_editor.dart:1016,1176,1194`
- **Fix:** Premestiti u `initState()`, dispose u `dispose()`, ili koristiti Provider pattern.

### BUG #17: GestureDetector + HardwareKeyboard Anti-Pattern [UIEngineer]
- **Problem:** 2 instanci koriste `GestureDetector.onTap` + `HardwareKeyboard.instance.isMetaPressed/isShiftPressed` umesto `Listener.onPointerDown`.
- **Fajlovi:**
  - `slot_voice_mixer.dart:473-478`
  - `ultimate_audio_panel.dart:3271-3274`
- **Fix:** Zameni sa `Listener(onPointerDown: (event) { ... event.buttons/modifiers ... })`.

---

## QA Bagovi — SREDNJI PRIORITET

### BUG #18: Tempo State Engine Nije Wired [TimelineEngine]
- **Fajl:** `crates/rf-engine/src/tempo_state.rs`, `crates/rf-bridge/src/tempo_state_ffi.rs`
- **Problem:** Rust implementacija kompletna (Phase 1-3). FFI bridge postoji. Ali NEMA Dart FFI bindinga — engine nije dostupan Flutter UI-u.
- **Fix:** Dodati bindinge u native_ffi.dart, wire do TransitionSystemProvider.

### BUG #19: Warp Markers Phase 4-5 [TimelineEngine]
- **Problem:** Data model i basic markers implementirani (Phase 1-3). Flutter vizualizacija i quantize (Phase 4-5) ne postoje.
- **Fix:** Implementirati warp handle vizualizaciju u timeline widgetu i quantize logiku.

### BUG #20: Dual Insert State [MixerArchitect]
- **Fajl:** `flutter_ui/lib/screens/engine_connected_layout.dart`, `flutter_ui/lib/providers/mixer_provider.dart`
- **Problem:** Tri izvora istine za insert state: MixerProvider.channels[].inserts, _busInserts (local), Rust engine. Nema single sync point.
- **Fix:** MixerProvider kao jedini izvor -> propagira na _busInserts i Rust. Nikad direktna _busInserts mutacija.

### BUG #21: Print u Swift [UIEngineer]
- **Fajl:** `flutter_ui/macos/Runner/MainFlutterWindow.swift:283`
- **Problem:** `print("[FluxForge]...")` — zabranjeno CLAUDE.md pravilima (korisnik nema konzolu).
- **Fix:** Ukloniti ili zameniti sa logging servisom.

### BUG #22: wgpu Unused Result [BuildOps]
- **Fajl:** `crates/rf-realtime/src/gpu.rs:273,495,690`
- **Problem:** `device.poll()` vraca `Result<()>` ali nije proveren.
- **Fix:** `let _ = self.context.device.poll(...);` ili handle error.

### BUG #23: FabFilter Delay Slider Default [DSPSpecialist]
- **Fajl:** `flutter_ui/lib/widgets/fabfilter/fabfilter_delay_panel.dart:1299`
- **Problem:** `defaultValue: (120.0 - 20.0) / 280.0` — hardkodiran BPM u slider default.
- **Fix:** Koristiti dinamicku kalkulaciju iz ucitanog `_bpm` value-a.

---

## QA Round 2 — KRITICNI (novi bagovi iz drugog kruga audita)

### BUG #24: MIDI Ne Dolazi do Plugin Instrumenata [PluginArchitect]
- **Fajlovi:** `rf-plugin/src/vst3.rs:1019-1035`, `clap.rs:832-884`, `audio_unit.rs:487-502`, `lv2.rs:953-960`
- **Problem:** `_midi_in` i `_midi_out` parametri u process() su IGNORISANI u sva 4 plugin formata (VST3/CLAP/AU/LV2). TODO komentari potvrdjuju da MIDI forwarding nije implementiran. Jedino Internal plugin ima ispravan potpis.
- **Fix:** Implementirati konverziju MidiBuffer -> IEventList (VST3), CLAP input events (CLAP), AUv3 MIDI (AU), LV2 Atom Sequence (LV2).
- **Uticaj:** SVE plugin instrument instanci ne primaju MIDI — nema NOTE ON/OFF. Instrument plugini su KOMPLETNO nefunkcionalni.

### BUG #25: ALE Transition Registry Panic [SlotIntelligence]
- **Fajl:** `rf-ale/src/transitions.rs:551`
- **Problem:** `default_profile()` koristi nested unwrap: `.get("default").unwrap_or_else(|| .values().next().unwrap())`. Ako je registry prazan — PANIC na audio thread.
- **Fix:** Garantovati da registry uvek ima "default" u konstruktoru, ili return Option.
- **Uticaj:** Audio thread crash tokom layer transition-a

### BUG #26: Drop Frame Timecode Kalkulacija [VideoSync]
- **Fajl:** `rf-video/src/timecode.rs:158-197`
- **Problem:** Drop frame logika primenjuje frame drop na SVE minute umesto samo na non-10-minute granice. SMPTE 12M specificira drop SAMO na MM:00;00 osim MM:10:00, MM:20:00, itd.
- **Fix:** Implementirati ispravnu SMPTE 12M logiku sa 10-minute exception-om.
- **Uticaj:** Sync greske u 29.97/59.94fps sadrzaju

### BUG #27: FFmpeg Decoder unsafe Send+Sync [VideoSync]
- **Fajl:** `rf-video/src/decoder.rs:386-387`
- **Problem:** `unsafe impl Send for FfmpegDecoder {}` i `unsafe impl Sync for FfmpegDecoder {}` — FFmpeg context NIJE thread-safe. Mutex na VideoDecoder nije dovoljan ako vise thread-ova kreira odvojene decoder instance.
- **Fix:** Ukloniti unsafe impl, omotati u proper synchronization, ili koristiti thread-local.
- **Uticaj:** Race conditions, memory corruption u multi-threaded playback

### BUG #28: LUFS maxTruePeak Vraca Pogresnu Vrednost [MeteringPro]
- **Fajl:** `flutter_ui/lib/widgets/meters/lufs_meter_widget.dart:38`
- **Problem:** `maxTruePeak` getter vraca `momentary > shortTerm ? momentary : shortTerm` — poredi LUFS vrednosti umesto dBTP. Treba `max(truePeakL, truePeakR)`.
- **Fix:** `double get maxTruePeak => truePeakL > truePeakR ? truePeakL : truePeakR;`
- **Uticaj:** Broadcasting compliance provere potpuno pogresne (off by 70-80 dB)

### BUG #29: Lua Sandbox — os Library Dostupan [ScriptingEngine]
- **Fajl:** `rf-script/src/lib.rs:295-297`
- **Problem:** `new_unsafe()` kreira Lua sa `StdLib::ALL`, ukljucujuci `os` library. Skripte mogu potencijalno izvrsiti shell komande.
- **Fix:** Verifikovati da `new()` (ne `new_unsafe()`) pravilno disabluje `os` i `io` libraries. Dodati sandbox test.
- **Uticaj:** Arbitrary code execution ako korisnik ucita malicious script

## QA Round 2 — VISOKI PRIORITET (novi)

### BUG #30: Plugin Unload closeEditor() Missing Await [PluginArchitect]
- **Fajl:** `flutter_ui/lib/providers/plugin_provider.dart:547-567`
- **Problem:** `closeEditor(instanceId)` pozvan bez `await` u `unloadPlugin()`. Plugin se deaktivira dok se editor jos zatvara.
- **Fix:** `await closeEditor(instanceId);`

### BUG #31: Plugin Chain TOCTOU Race [PluginArchitect]
- **Fajl:** `rf-plugin/src/chain.rs:480-482`, `lib.rs:509-510`
- **Problem:** Chain processing ne sinhronizuje sa plugin removal. Plugin moze biti unloaded dok je jos u upotrebi. Instance map get() i use() imaju TOCTOU race.
- **Fix:** Arc<RwLock> cuvanje za ceo processing scope, ne samo get().

### BUG #32: LV2 URID Map Mutex Poisoning [PluginArchitect]
- **Fajl:** `rf-plugin/src/lv2.rs:120,134`
- **Problem:** `.expect("URID map mutex poisoned")` — ako bilo koji thread panic-uje dok drzi URID lock, CEO host crashuje.
- **Fix:** Implement recovery mehanizam (re-lock after clearing poison).

### BUG #33: LV2 Sample Rate Mismatch [PluginArchitect]
- **Fajl:** `rf-plugin/src/lv2.rs:913-924`
- **Problem:** LV2 plugin instantiated na 48kHz. Ako device radi na drugom SR, plugin se NE reinstancira — samo log warning.
- **Fix:** Reinstancirati plugin na ispravnom sample rate-u, ili reject rate change.

### BUG #34: HOA Decoder VBAP Simplifikacija [SpatialAudio]
- **Fajl:** `rf-spatial/src/hoa/decoder.rs:333-335`
- **Problem:** VBAP koristi nearest-speaker umesto triangulacije sa 3 okolna speaker-a. `gains[nearest_idx] = 1.0;` umesto proper VBAP.
- **Fix:** Implementirati VBAP triangulaciju.
- **Uticaj:** Panning artifacts, neprirodno prostorno kretanje

### BUG #35: HRTF Bilinear Interpolation Fallback [SpatialAudio]
- **Fajl:** `rf-spatial/src/binaural/hrtf.rs:106-114`
- **Problem:** Kad uglovi bilinear grida nedostaju, fallback na single `unwrap_or(ll)`. Frekvencijski-zavisne ITD/ILD greske za off-grid pravce.
- **Fix:** Implementirati sfernu interpolaciju umesto bilinear fallback-a.

### BUG #36: VCA Trim State Ne Sync-uje sa Provider [MixerArchitect]
- **Fajl:** `flutter_ui/lib/widgets/mixer/vca_strip.dart:32-33`
- **Problem:** VCA member `trimDb` i `bypassVca` su mutable ali nemaju sync nazad ka MixerProvider. Promene se gube.
- **Fix:** Propagirati trim promene na `MixerProvider.setVcaTrim(vcaId, trackId, trimDb)`.

### BUG #37: Routing Matrix Nema Feedback Loop Detekciju [MixerArchitect]
- **Fajl:** `flutter_ui/lib/widgets/routing/routing_matrix_panel.dart:190-207`
- **Problem:** `_toggleConnection()` dozvoljava arbitrarne track->bus konekcije bez provere za feedback petlje. Bus A -> Bus B -> Bus A = beskonacna petlja.
- **Fix:** DFS/BFS detekcija ciklusa pre prihvatanja konekcije.

### BUG #38: Track Versions NPE [DAWTools]
- **Fajl:** `flutter_ui/lib/widgets/panels/track_versions_panel.dart:235-237`
- **Problem:** `provider.getContainer(trackId)` moze vratiti null, ali nema null check pre pristupa `.versions.length`.
- **Fix:** Dodati null check.

### BUG #39: Schema Migration Safety [DAWTools]
- **Fajl:** `flutter_ui/lib/widgets/project/schema_migration_panel.dart:35-37`
- **Problem:** Migration version detection kaskadira kroz `schema_version` -> `version` -> hardkodiran 1, bez audit trail-a ako se ime polja menja.
- **Fix:** Striktna validacija polja, error ako nema ni jednog.

### BUG #40: Lua Nema Infinite Loop Zastitu [ScriptingEngine]
- **Fajl:** `rf-script/src/lib.rs`
- **Problem:** Nema timeout/iteration limita. Lua skripta moze da se vrti beskonacno, blokirajuci audio thread.
- **Fix:** Dodati instruction count hook ili timeout.

### BUG #41: Script File Loading Path Traversal [ScriptingEngine]
- **Fajl:** `rf-script/src/lib.rs:732`
- **Problem:** `std::fs::read_to_string(path)` dozvoljava citanje proizvoljnih fajlova. Ako path dolazi od korisnickog inputa, moze procitati config fajlove, kljuceve itd.
- **Fix:** Validirati path protiv sandbox root-a pre citanja.

### BUG #42: AUREXIS FP Normalization Bias [SlotIntelligence]
- **Fajl:** `rf-aurexis/src/variation/hash.rs:29-36`
- **Problem:** `(sub_seed as f64) / (u64::MAX as f64)` gubi preciznost u IEEE 754. Distribucija nije savrseno uniformna.
- **Fix:** Koristiti `(sub_seed >> 1) as f64 / ((1u64 << 63) as f64)` za tacnu normalizaciju.

### BUG #43: Ingest SystemTime Unwrap [SlotIntelligence]
- **Fajl:** `rf-ingest/src/layer_event.rs:407-410`
- **Problem:** `SystemTime::now().duration_since(UNIX_EPOCH).unwrap()` — panic ako je sistemski sat iza UNIX_EPOCH.
- **Fix:** `.unwrap_or_default()` ili monotonic clock.

## QA Round 2 — SREDNJI PRIORITET (novi)

### BUG #44: Floating Window Timer Lifecycle [MixerArchitect]
- **Fajl:** `widgets/mixer/floating_mixer_window.dart:194-201`
- **Problem:** 10Hz refresh Timer moze da pozove setState na stale OverlayEntry.

### BUG #45: Automation Bezier X Control Points Neiskorisceni [MediaTimeline]
- **Fajl:** `widgets/timeline/automation_lane.dart:212-217`
- **Problem:** cx1 i cx2 (X-axis control points) izracunati ali nikad iskorisceni u bezier interpolaciji. Handle adjustments ne kontrolisu pravilno oblik krive.

### BUG #46: Waveform Cache Oversized Image [MediaTimeline]
- **Fajl:** `widgets/waveform/waveform_cache.dart:128-141`
- **Problem:** Ako je jedan waveform texture veci od maxCacheSizeBytes, dodaje se svejedno. Memory moze da raste neograniceno.

### BUG #47: Grid Line FP Drift u Dugim Sesijama [MediaTimeline]
- **Fajl:** `widgets/timeline/grid_lines.dart:173-174`
- **Problem:** Tolerancija 0.0001 nedovoljna za bar 10000+. Floating-point greska dovodi do duplih grid linija.

### BUG #48: Binaural Buffer Size Assumption [SpatialAudio]
- **Fajl:** `rf-spatial/src/binaural/renderer.rs:213-227`
- **Problem:** `input_pos` akumulacija moze da predje `fft_size` bez bounds check-a. Potential buffer overflow.

### BUG #49: FluxMacro Interpreter No Cancellation [SlotIntelligence]
- **Fajl:** `rf-fluxmacro/src/interpreter.rs:78-130`
- **Problem:** Cancellation se proverava samo na pocetku loop-a, ne tokom step execution. Dugi koraci se ne mogu prekinuti.

### BUG #50: GameModel No Runtime Validation [SlotIntelligence]
- **Fajl:** `rf-slot-lab/src/model/game_model.rs:52-85`
- **Problem:** Konstruktor ne poziva `validate()`. Invalid game modeli (0 reelova, RTP=1.5) mogu da se kreiraju.

### BUG #51: Clip Inspector Custom Logarithm [DAWTools]
- **Fajl:** `widgets/panels/clip_inspector_panel.dart:877-879`
- **Problem:** Custom `_ln()` koristi Taylor series (8 termova) umesto `dart:math log()`. Precision error >±0.1dB za extreme gain vrednosti.

### BUG #52: Script Console Unbounded History [ScriptingEngine]
- **Fajl:** `widgets/scripting/script_console.dart:31-32`
- **Problem:** `_history` i `_commandHistory` liste rastu neograniceno. Moze izazvati OOM.
- **Fix:** Dodati cap (npr. 10000 entries).

## QA Round 2 — Dodatni bagovi (propusteni u prvom prolazu)

### BUG #53: Plugin Unload try_write() Bez Fallback [PluginArchitect]
- **Fajl:** `rf-plugin/src/lib.rs:569`, `chain.rs:516`
- **Problem:** Plugin unload i chain reset koriste `try_write()` bez error handlinga. Ako lock contention — deactivate() se NIKAD ne pozove, plugin ostaje aktivan sa dangling locks.
- **Fix:** Koristiti blocking `.write()` ili retry sa exponential backoff.

### BUG #54: CLAP String Handle Lifetime [PluginArchitect]
- **Fajl:** `rf-plugin/src/clap.rs:734`
- **Problem:** `query_ext()` vraca null pointer bez verifikacije. Silent null moze biti pogresno protumacen kao "extension not supported" umesto error-a.
- **Fix:** Dodati logging kad je null return unexpected.

### BUG #55: Buffer Pool Exhaust Panic [PluginArchitect]
- **Fajl:** `rf-plugin/src/chain.rs:424-483`
- **Problem:** Chain processing poziva `pool.acquire().unwrap()` — panic ako je pool iscrpljen.
- **Fix:** Handle gracefully — return silence ili skip processing umesto panic.
- **Uticaj:** Real-time crash ako je buffer pool premali

### BUG #56: Plugin Editor Unguarded getInstance() [PluginArchitect]
- **Fajl:** `flutter_ui/lib/widgets/plugin/plugin_editor_window.dart:42,84,207-209`
- **Problem:** Vise pristupa `getInstance()` bez null safety izmedju provera. Ako se instance ukloni iz provider mape izmedju linija 42 i 208 — null pointer.
- **Fix:** Cuvati referencu lokalno, proveravati na svakom pristupu.

### BUG #57: Plugin Bypass Missing Mounted Check [PluginArchitect]
- **Fajl:** `flutter_ui/lib/widgets/plugin/plugin_slot.dart:328-335`
- **Problem:** `_BypassButton.onTap` poziva `context.read<PluginProvider>()` sinhrono bez mounted provere. Ako je widget disposed — crash.
- **Fix:** Dodati `if (!context.mounted) return;` pre context.read().

### BUG #58: Plugin Instance Map TOCTOU [PluginArchitect]
- **Fajl:** `rf-plugin/src/lib.rs:420-421, 509-510`
- **Problem:** `get_instance()` vraca `Arc<RwLock>` ali read lock se otpusta odmah. Instance moze biti uklonjena izmedju get i use na drugom thread-u.
- **Fix:** Zadrzati Arc reference za ceo scope koriscenja.

### BUG #59: AUREXIS Replay Unwrap After Set [SlotIntelligence]
- **Fajl:** `rf-aurexis/src/drc/replay.rs:185,225`
- **Problem:** `self.last_trace = Some(trace); self.last_trace.as_ref().unwrap()` — logicki safe ali maintainability rizik. Ako se doda early return, unwrap postaje opasan.
- **Fix:** Vratiti owned vrednost direktno umesto interior Option + unwrap.

### BUG #60: ALE with_builtins() Bez Validacije [SlotIntelligence]
- **Fajl:** `rf-ale/src/transitions.rs:525-535`
- **Problem:** `with_builtins()` registruje 5 profila ali ne validira da su svih 5 uspesno registrovani. Nema length assertion.
- **Fix:** `assert!(registry.len() == 5)` ili return Result.

### BUG #61: AUREXIS Engine Division Guard [SlotIntelligence]
- **Fajl:** `rf-aurexis/src/core/engine.rs:346-353`
- **Problem:** Deljenje sa `redistributions.len()` zasticeno `.is_empty()` proverom, ali ako neko ukloni if — silent NaN. Nejasna namera.
- **Fix:** Koristiti `.len().max(1)` ili `Option` reduce pattern.

### BUG #62: Stage Timing Profile Expect [SlotIntelligence]
- **Fajl:** `rf-stage/src/timing.rs:245-250`
- **Problem:** `.expect("Normal profile must exist")` — panic ako TimingProfile::Normal nedostaje iz profiles mape. Nema enforced invariant.
- **Fix:** Return `Option<&TimingProfile>` ili garantovati invariant u konstruktoru.

### BUG #63: Scenario Presets Bez Bounds Check [SlotIntelligence]
- **Fajl:** `rf-slot-lab/src/scenario/presets.rs`
- **Problem:** Scenario generisanje ne validira protiv game modela. Symbol nizovi mogu biti veci/manji od grida (reelovi, redovi).
- **Fix:** Dodati `Scenario::validate_against(&GameModel)` pre izvrsavanja.

### BUG #64: Ingest Snapshot Diff Silent Corruption [SlotIntelligence]
- **Fajl:** `rf-ingest/src/layer_snapshot.rs`
- **Problem:** `compute_diff()` vraca prazan diff ako su snapshoti identicni. Ako snapshot update failuje (corrupted JSON), sledeci snapshot izgleda nepromenjeno — silent failure, stuck state.
- **Fix:** Pratiti hash poslednjeg snapshota, error ako je identican za >N update-ova.

### BUG #65: Atmos Gain Smoothing Race [SpatialAudio]
- **Fajl:** `rf-spatial/src/atmos/renderer.rs:209-214`
- **Problem:** Per-object gain smoothing koristi `prev_gains` niz, ali u multi-threaded render kontekstu, `self.prev_gains` nije lockovan tokom read-modify-write.
- **Fix:** Lock ili atomic za gain smoothing, ili garantovati single-thread render.
- **Uticaj:** Audio crackles kad objekti simultano mute/unmute

### BUG #66: Room Simulator Samo First-Order Reflections [SpatialAudio]
- **Fajl:** `rf-spatial/src/room/mod.rs:209-231`
- **Problem:** Samo racuna first-order refleksije (6 zidova). Multi-bounce scenariji (uglovi, kompleksni oblici sobe) nisu modelovani.
- **Uticaj:** Nedostajuce early refleksije, neprecizan room impulse response.

### BUG #67: Video Frame Cache Memory Leak [VideoSync]
- **Fajl:** `rf-video/src/frame_cache.rs:192-201`
- **Problem:** Ako `frames.remove()` vrati None (ne bi trebalo), memory_used se ne dekrementira. Memory tracking postaje netacan.
- **Fix:** Dodati fallback za None slucaj.

### BUG #68: Timecode Mixed Separators [VideoSync]
- **Fajl:** `rf-video/src/timecode.rs:236`
- **Problem:** `split([':', ';'])` dozvoljava mesane separatore (npr. "01:30:45;12"). Treba enforsirati konzistentnost po formatu.
- **Fix:** Detektovati format (non-drop = ':', drop-frame = ';') i odbiti mesane.

### BUG #69: Frame Count Truncation [VideoSync]
- **Fajl:** `rf-video/src/decoder.rs:266`
- **Problem:** `(duration_secs * frame_rate) as u64` truncira frakcione frame-ove. Za 23.976fps na 3600s, gubi ~86 frame-ova.
- **Fix:** Koristiti `.round() as u64` umesto truncation.

### BUG #70: LUFS Normalization Indicator Incomplete [MeteringPro]
- **Fajl:** `flutter_ui/lib/widgets/waveform/lufs_normalization_indicator.dart:62-64`
- **Problem:** `_calculateNormalizedPosition()` metoda verovatno nije kompletno implementirana. Pozicija indikatora moze biti pogresna.
- **Fix:** Kompletirati implementaciju metode.

### BUG #71: IO Selector Runtime Availability [MixerArchitect]
- **Fajl:** `flutter_ui/lib/widgets/mixer/io_selector_popup.dart:240-254`
- **Problem:** Rute oznacene `isAvailable: false` su prikazane ali disabled. Nema re-validacije pre selekcije — hardware moze biti diskonektovan.
- **Fix:** Pre-selection validation callback koji proverava route.isAvailable.

### BUG #72: Group Manager Multi-Group Overwrite [MixerArchitect]
- **Fajl:** `flutter_ui/lib/widgets/mixer/group_manager_panel.dart:175-183`
- **Problem:** `addChannelToGroup(channel.id, group.id)` overwrite-uje prethodni groupId. Kanal koji je u grupi "a", prebacivanjem u "c" gubi "a" membership.
- **Fix:** Podrzati multi-group (comma-separated IDs) ili jasno dokumentovati single-group ogranicenje.

### BUG #73: Automation Badge State Not Persisted [MixerArchitect]
- **Fajl:** `flutter_ui/lib/widgets/mixer/automation_mode_badge.dart:100-199`
- **Problem:** Automation mode selection menja UI lokalno ali nikad ne sync-uje sa engine-om ili provider-om. State se gubi na rebuild.
- **Fix:** Wire do AutomationProvider i FFI.

### BUG #74: Stem Routing No Multi-Output Validation [MixerArchitect]
- **Fajl:** `flutter_ui/lib/widgets/routing/stem_routing_matrix.dart:87-113`
- **Problem:** Dozvoljava jednom track-u da routuje na vise stem kolona. Audio engine mozda ne podrzava multiple final outputs per track.
- **Fix:** Validirati da track ima unique final output, ili podrzati multi-output eksplicitno.

### BUG #75: Send Slot Missing Pan Control [MixerArchitect]
- **Fajl:** `flutter_ui/lib/widgets/mixer/send_slot_widget.dart`
- **Problem:** SendData ima `.pan` field ali SendSlotWidget ga nikad ne prikazuje niti dozvoljava editovanje.
- **Fix:** Dodati pan kontrolu u send slot UI.

### BUG #76: Control Room Metering Timer Race [MixerArchitect]
- **Fajl:** `flutter_ui/lib/widgets/mixer/control_room_panel.dart:36-48`
- **Problem:** Timer callback proverava `mounted` ali posle `context.read()` — moze failovati ako mounted postane false izmedju timer fire i if-check.
- **Uticaj:** Mitigirano try/catch, ali nije idealno.

### BUG #77: Clip Inspector PitchShift No Debounce [DAWTools]
- **Fajl:** `flutter_ui/lib/widgets/panels/clip_inspector_panel.dart:620-625`
- **Problem:** `clipSetPitchShift()` FFI poziv na svakom slider drag-u bez debounce-a. Visoko-frekventni FFI pozivi mogu overwhelm Rust bridge.
- **Fix:** Dodati debounce (50-100ms).

### BUG #78: Clip Gain Envelope Division by Zero [DAWTools]
- **Fajl:** `flutter_ui/lib/widgets/panels/clip_gain_envelope_panel.dart:352`
- **Problem:** `gain = 12.0 - (y / height) * 72.0` — nema validacije da height > 0. CustomPaint moze da renderuje na height=0.
- **Fix:** Guard: `if (height <= 0) return;`

### BUG #79: Loop Editor Silent Filter Failure [DAWTools]
- **Fajl:** `flutter_ui/lib/widgets/panels/loop_editor_panel.dart:73-75`
- **Problem:** Track clip filtriranje pretpostavlja da je `clip.trackId` string format integer ID-a, ali nema validaciju formata. Mismatch tiho filtrira SVE clipove.
- **Fix:** Dodati format validaciju ili fallback.

### BUG #80: Logical Editor Filter Display [DAWTools]
- **Fajl:** `flutter_ui/lib/widgets/panels/logical_editor_panel.dart:625-629`
- **Problem:** `_formatFilterValue()` prikazuje samo value1 za range operatore, ignorise value2. UI kaze "5" umesto "5-20".
- **Fix:** Za range operatore formatirati kao "value1-value2".

### BUG #81: Project Versions Date Format [DAWTools]
- **Fajl:** `flutter_ui/lib/widgets/project/project_versions_panel.dart:59-62`
- **Problem:** `.day.toString()` bez zero-padding-a. Dan 1-9 prikazan kao "1/1/2024" umesto "01/01/2024".
- **Fix:** `.day.toString().padLeft(2, '0')`.

### BUG #82: Project Versions jsonDecode No Try-Catch [DAWTools]
- **Fajl:** `flutter_ui/lib/widgets/project/project_versions_panel.dart:103`
- **Problem:** `jsonDecode()` pretpostavlja ispravan JSON iz FFI. Nema try-catch — crash ako decode failuje.
- **Fix:** Omotati u try-catch sa graceful error handling.

### BUG #83: Offline Encoder No Pre-Dither Overflow Check [BuildOps]
- **Fajl:** `crates/rf-offline/src/encoder.rs:70-74`
- **Problem:** Dithering se primenjuje posle `clamp(-1.0, 1.0)`. Overdriven audio (>1.0) tiho clipuje pre dithering-a. Nema pre-check za overflow samples.
- **Fix:** Log warning ili soft-clip pre dithering-a.

### BUG #84: bundle_dylibs.sh No Cycle Detection [BuildOps]
- **Fajl:** `flutter_ui/scripts/bundle_dylibs.sh:23`
- **Problem:** Rekurzivni `bundle_dylib()` nema detekciju ciklusa. Cirkularne zavisnosti (A -> B -> A) izazivaju beskonacan recursion.
- **Fix:** Dodati visited set za vec obradjene dylib-ove.

---

## Zamke — SlotLab

- `slot_lab_screen.dart` — 15K+ linija, NE MOZE se razbiti. Citaj sa `offset/limit`.
- `_bigWinEndFired` guard — sprecava dupli BIG_WIN_END trigger na skip tokom end hold
- BIG_WIN_END composite SAM handluje stop BIG_WIN_START (NE rucno `stopEvent`)
- `hasExplicitFadeActions` u event_registry MORA da ukljucuje FadeVoice/StopVoice
- FFNC rename: BIG_WIN_START/END su `mus_` (music bus), NE `sfx_`
- `_syncEventToRegistry` OBAVEZNO posle svakog composite refresh-a (stale registry bug)
- FS auto-spin: balance se NE oduzima tokom free spins-a (`_isInFreeSpins` guard)
- EventRegistry: JEDAN put registracije — SAMO `_syncEventToRegistry()` u `slot_lab_screen.dart`
- NIKADA registracija u `composite_event_system_provider.dart` — dva sistema se medjusobno brisu
- ID format: `event.id` (npr. `audio_REEL_STOP`), NIKADA `composite_${id}_${STAGE}`
- `_syncCompositeToMiddleware` -> MiddlewareEvent sistem, NE EventRegistry
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
- Lock-free: `rtrb::RingBuffer` za UI->Audio thread

## Zamke — FFI / Rust

- Dva engine globala: `PLAYBACK_ENGINE` (LazyLock, uvek init) vs `ENGINE` (Option, starts None)
- `TRACK_MANAGER`, `WAVEFORM_CACHE`, `IMPORTED_AUDIO` — `pub(crate)` u ffi.rs, pristup iz clip_ops.rs
- OutputBus: koristi `.engineIndex`, NIKADA `.index` za FFI
- Clip operations: destructive, `Arc::make_mut` za CoW, invalidate waveform cache posle
- Fade destructive: bake curve -> CLEAR metadata (fade_in=0.0) da spreci double-apply
- ID parsing: `RegExp(r'\d+').firstMatch(id)`, NIKADA `replaceAll(RegExp(r'[^0-9]'), '')`
- CLAP Drop: MORA `plugin_ptr = null` posle `destroy()` — sprecava double-free
- LV2 Drop: MORA `handle = null_mut` + `descriptor = null` posle `cleanup()`
- Plugin process(): `midi_in`/`midi_out` parametri u SVIH 5 implementacija (VST3/AU/CLAP/LV2/Internal)
- Multi-output routing: JEDAN `try_read()` scope za ceo channel map — sprecava race condition
- TrackType enum: Audio/Instrument/Bus/Aux — Midi/Master mapiraju na Audio pri load-u
- `toNativeUtf8()` alocira sa calloc -> MORA `calloc.free()`, NIKADA `malloc.free()`

## Zamke — Flutter UI

- SmartToolProvider: JEDAN instance via ChangeNotifierProvider u `main.dart:239`
- Split View: static ref counting `_engineRefCount`, provideri MORAJU biti GetIt singletoni
- Modifier keys -> `Listener.onPointerDown`, NIKADA `GestureDetector.onTap` + HardwareKeyboard
- FocusNode/Controllers -> `initState()` + `dispose()`, NIKADA inline u `build()`
- Keyboard handlers -> EditableText ancestor guard kao prva provera
- Nested drag -> `Listener.onPointerDown/Move/Up` (bypass gesture arena)
- Stereo waveform -> threshold `trackHeight > 60`
- Optimistic state -> nullable `bool? _optimisticActive`, NIKADA Timer
- MixerProvider: `setChannelVolume()`, `toggleChannelMute()`, `toggleChannelSolo()`, `renameChannel()`
- Stereo dual pan: `pan=-1.0` je hard-left (NE bug), `panRight=+1.0` hard-right
- FaderCurve klasa u `audio_math.dart` — jedini izvor istine za volume fadere
- desktop_drop plugin: fullscreen DropTarget NSView presrece mouse. Timer (2s) u MainFlutterWindow.swift uklanja non-Flutter subview-ove

## Zamke — Build

- ExFAT disk: macOS `._*` fajlovi -> codesign fail. UVEK xcodebuild sa derivedData na HOME
- NIKADA `flutter run` — samo xcodebuild + open .app
- UVEK `~/Library/Developer/Xcode/DerivedData/`, NIKADA `/Library/Developer/`

---

## Status — Kompletno

- Voice Mixer, DAW Mixer, SlotLab WoO Game Flow (W1-W7 + polish)
- 16 subsystem providera, clip operations, FFNC audio triggering
- SFX Pipeline Wizard — svih 6 koraka (21K UI + rf-offline backend)
- Time Stretch — rf-dsp + FFI + Flutter bindings (koristi SlotLab)
- Warp Markers — KOMPLETNO: data modeli, UI widgeti (warp_handles, audio_warping_panel, time_stretch_editor), Rust WarpMarker/WarpState, clipSetWarpMarkerPitch FFI, quantize strength slider (4 preseta), warp_state_provider.dart, BPM UI integracija, project save/load (Serialize/Deserialize), transient detekcija
- Live Server Integration — WebSocket/TCP (rf-connector) + JSON-RPC server (port 8765)
- AUREXIS: GEG, DPM, SAMCL, Device Preview, SAM — Rust + FFI + Dart provideri kompletni
- VST3/AU plugin hosting — skeniranje, loading, GUI (out-of-process), insert chain, PDC
- Pitch Shift FFI — 20+ FFI funkcija (detect, analyze, correct, elastic, clip, voice pitch) + Dart bindings + UI paneli
- MIDI Instrument Pipeline — MidiBuffer u process(), TrackType::Instrument, MIDI clip rendering u audio loop, plugin lifecycle
- Multi-Output Routing — per-channel bus routing via output_channel_map (do 64ch), PinConnector, project save/load
- CLAP Plugin Hosting — dlopen + clap_entry + factory + process() + lifecycle + null-safe Drop
- LV2 Plugin Hosting — dlopen + lv2_descriptor + instantiate + run() + port connection + TTL parsing + null-safe Drop
- Project Save/Load — prerutirano na rf-bridge project_ffi.rs, calloc fix, automation CurveType/ParamId, clip properties
- Plugin Automation — wire UI -> FFI, param_name parse bug fix, PluginParamId class, 10 provider metoda
- VST3/AU GUI Resize — resize_editor implementiran (objc2 NSWindow), Flutter drag-to-resize handle
- Plugin Preset Browser — PluginInstance trait (preset_count/name/load), FFI, Dart, UI menu
- CLAP Full Extensions — params (flush event), state (stream), latency, GUI (floating cocoa/win32/x11)
- LV2 URID Map — global thread-safe URI<->integer mapping (17 pre-registered), Atom MIDI buffers
- Sidechain Routing — InsertProcessor.set_sidechain_input(), CompressorWrapper integration, FFI
- Plugin Automation Recording — slider onChangeStart/onChanged/onChangeEnd -> FFI touch/release
- GR Metering — VEC KOMPLETNO (insert_get_meter FFI + Dart + 7 wrappers sa get_meter)
- FFT Metering — VEC KOMPLETNO (metering_get_master_spectrum + getMasterSpectrum Dart)
- Project Sample Rate Selection — engine_set_sample_rate FFI, validacija, update svih insert chains
- Real FFT Spectrum Bridge — bus_hierarchy_panel sada cita pravi FFT iz engine-a (ne simulirani)
- HELIX Neural Slot Design Environment — svih 12 dock panela funkcionalni:
  - FLOW: interaktivni DAG graf sa CustomPainter bezier edges, 8 node tipova, force state
  - AUDIO: master meters, fader, channel strips, events list, Auto-Bind (FFNC + Spectral DNA)
  - MATH: win distribution histogram, RTP kalkulator, volatility meter (iz AUREXIS-a)
  - TIMELINE: multi-track stage timing, drag events, playhead
  - INTEL: analytics dashboard, spin statistika, win distribucija
  - EXPORT: UCP/WWISE/FMOD/GDD export + UKGC/MGA/SE compliance validator (COMPLY)
  - SFX: SFX pipeline kontrole
  - BT: visual behavior tree editor sa 22 node tipova, canvas, edges
  - DNA: Spectral DNA classifier (7 DSP feature extractors u Rust FFI)
  - AI GEN: pipeline UI sa prompt + log + ElevenLabs real backend + dynamic backends
  - CLOUD: CloudSyncService + AssetCloudService — real HTTP transport (authenticate, upload, download, sync, search, rate, collections)
  - A/B: A/B test comparison
- HELIX Test Suite — 60 integration testova + 60 property testova + 25 golden pixel testova + state hot-swap
- HELIX Audio Drag-Drop — stage binding pipeline, auto-match, _pickStage dialog, EventRegistry registration
- HELIX ESC Fix — onExit zatvara overlaye umesto da izlazi iz HELIX-a (root cause fix u PremiumSlotPreview)
- HELIX Bug Fixes — ESC/PopScope, broken dugmadi (forceTransition, addCompositeEvent, REC, masterFader, DNA)
- QA Audit Sweep — 84/84 buga provereno, 5 aktivnih fixovano (#15 otool, #22 wgpu poll, #51 dead code, #73 automation badge, Spectral DNA FFI)
- Cargo Clippy + Flutter Analyzer — 0 warnings (41 clippy + 9 analyzer fiksovano)
- DAW Editing Tools — Razor Edit kompletno (15 akcija): delete, split, cut, copy, paste, mute, join, fadeBoth, healSeparation, insertSilence, stripSilence, reverse, stretch, duplicate, move. Rust FFI (track_manager.rs 6 metoda + ffi.rs 7 eksporta) → Dart bindings (native_ffi.dart 7 typedef + 7 metoda) → RazorEditProvider wiring. Crossfade curve + clip fade curve wiring kroz TrackLane→Timeline→engine_connected_layout
- Smart Tool 9-zone Detection — SmartToolProvider sa 13 zona, cursor wiring, zone logika kompletna
- Project SR Selector UI — _SampleRateSelector dropdown u toolbar-u, setSampleRate FFI wiring
- Tempo State Engine Dart Wiring — setTempo() → clickSetTempo() FFI, Rust click track kompletno
- HELIX Reactivity Fixes — BT shouldRepaint hash, A/B listener pattern, CLOUD/EXPORT/AUDIO DNA/AI GEN addListener/removeListener, masterFader iz FFI
- HELIX AI GEN Real Backend — ElevenLabs API integration, dynamic backends, reaktivnost
- Horizontal Pro Meter — _paintHorizontal() sa L/R bars, gradient, peak hold, clip indicator
- Agent Team Architecture — 25 specijalizovanih agenata (0-24) sa CLAUDE.md + MEMORY.md. Pokriva: Orchestrator, AudioEngine, MixerArchitect, SlotLabUI, SlotLabEvents, SlotLabAudio, GameArchitect, UIEngineer, DSPSpecialist, ProjectIO, BuildOps, QAAgent, TimelineEngine, DAWTools, LiveServer, SecurityAgent, PerformanceAgent, PluginArchitect, SlotIntelligence, MediaTimeline, SpatialAudio, MeteringPro, ScriptingEngine, MIDIEditor, VideoSync. 50 fajlova u .claude/agents/
- HELIX BehaviorTree Persistence — BehaviorTreeProvider + HelixBtCanvasProvider sa toJson/loadFromJson, dirty flag tracking
- HELIX TIMELINE Zoom/Scroll — 0.5x-8x zoom (+/- buttons + Ctrl+scroll wheel), horizontal scroll, FIT reset
- HELIX EXPORT Batch — parallel Future.wait multi-format (UCP/WWISE/FMOD/GDD), per-format status badges
- HELIX Reel Vizualizacija — phase-based animation (accel/spin/decel/bounce), motion blur, win line overlay, anticipation system, per-reel stop timing
- HELIX Feature Composer — FeatureComposerProvider sa 12+ mehanika (free spins, bonus, pick games), 3 preset-a (BASIC/STD/FULL), mechanics toggle, composed stages view
- MIDI Editor — piano roll widget (1126 LOC), MIDI clip widget (482 LOC), expression maps provider (1146 LOC), MIDI provider (1212 LOC), 20+ FFI funkcija. Kompletna infrastruktura: MidiBuffer → process() → plugin forwarding za svih 5 formata
- HOA Higher Orders (Wigner-D) — AmbisonicTransform sa Ivanic & Ruedenberg (1996) rekurzijom, orderi 1-7 (do 64ch), RotationInterpolator, SN3D/ACN format, full test suite (identity, π rotation, energy preservation, mirror, 7th order). transform.rs 656 LOC
- LV2 GUI Hosting — direktno LV2 UI hosting (bez Suil): dlopen UI binary, lv2ui_descriptor lookup, write_function callback za parameter routing UI→plugin, URID map/unmap features za UI, instance-access feature, port_event notifikacija (sync UI sa plugin state), idle extension (toolkit event processing), resize extension, proper cleanup (close_editor). Podržava CocoaUI (macOS), X11UI (Linux), WindowsUI
- VST3 GUI Windows/Linux — IPlugView COM vtable (12 metoda), vst3_load_plug_view() sa GetPluginFactory→IEditController→QueryInterface(IPlugView), HWND attach (Windows), X11EmbedWindowID XEmbed (Linux), proper close_editor sa removed()+release(), Arc<Library> umesto mem::forget leak

## Potvrdjeno Ispravno (QA Audit 2026-03-30)

- EventRegistry single source of truth arhitektura
- SlotLab listener lifecycle (svi pravilno dodati/uklonjeni)
- FaderCurve math (svi edge cases pokriveni)
- Pan semantika (L=-1.0, R=+1.0 korektno svuda)
- Biquad TDF-II implementacija sa SIMD fallback chain (avx2->sse4.2->scalar)
- Denormal handling (CPU-level FTZ/DAZ + software flush)
- FFT spektrum (Hann window, RMS scaling, exponential smoothing)
- Metering (try_write svuda, non-blocking)
- GetIt DI (70+ providera, nema circular dependencies)
- Project save/load (rf-bridge, ne deprecated stubs)
- Audio SRC (Lanczos-3 sinc interpolacija za export i one-shot playback)
- Win tier system (data-driven)
- Moderne mixer metode (setChannelVolume/toggleChannelMute/toggleChannelSolo)
- SmartToolProvider singleton u main.dart
- desktop_drop workaround funkcionalan
- CompositeEventSystemProvider NE registruje u EventRegistry (korektno)
- Async mounted checks u celom SlotLab-u
- Input validation comprehensive (FFIBoundsChecker)
- @rpath linking za dylib-ove korektno
- ExFAT workaround aktivan (clean_xattrs.sh)
- AUDIO_FORMAT_HANDLING.md bagovi vec fixovani u kodu (doc zastareo)
- CLAP Drop: plugin_ptr = null posle destroy() (KOREKTNO)
- LV2 Drop: handle = null_mut + descriptor = null posle cleanup() (KOREKTNO)
- Internal plugin: MIDI potpis ispravan
- Casino-grade determinizam: FNV-1a + SHA-256 (KOREKTNO)
- AUREXIS thread safety: single-intelligence-thread design (KOREKTNO)
- DeterministicParameterMap: Send + Sync (KOREKTNO)
- Security: path sandboxing, game ID validation, HTML escaping (KOREKTNO)
- Flutter common widgets: svi AnimationControllers u initState/dispose (KOREKTNO)
- Flutter layout widgets: svi FocusNode/TextEditingControllers pravilno (KOREKTNO)
- main.dart provider tree: SmartToolProvider singleton, GetIt .value(), nema circular deps (KOREKTNO)
- Tutorial overlay: AnimationController pravilno disposed (KOREKTNO)
- Nema print/debugPrint u Dart kodu (samo Swift violation #21)
- Waveform cache LRU: pravilna implementacija sa eviction i memory tracking
- Timeline time ruler: beat/bar kalkulacija korektna
- Transport state management: korektno strukturiran
- Multi-selection: normalized() sprecava off-by-one

---

## Preostalo (TODO)

### Feature Development
- ~~LV2 GUI hosting~~ ✅ KOMPLETNO (2026-04-21)
- ~~VST3 native GUI on Windows/Linux~~ ✅ KOMPLETNO (2026-04-21)

### HELIX Improvements
- ~~CLOUD panel real sync~~ ✅ KOMPLETNO (2026-04-21) — CloudSyncService + AssetCloudService: svi stubovi zamenjeni realnim HTTP transportom (authenticate, upload multipart, download, manifest sync, search, rate, collections, share, delete). Backend-agnostic REST sa timeout/socket error handling.

### Agent Team — ✅ KOMPLETNO (2026-04-21)
- ~~Implementirati agent CLAUDE.md + MEMORY.md + rules za svakog od 25 agenata~~
- 25 agenata (0-24), 50 fajlova (CLAUDE.md + MEMORY.md svaki), u `.claude/agents/`

---

## DAW Industrija — Istraživanje za Flux Nadogradnju

> Ovo je referenca za buduće odluke. Kad pravimo novu feature — pogledamo ovde šta industrija radi pogrešno i kako Flux može bolje.

### 1. FRUSTRACIJE PRODUCENATA — Šta mrze u svojim DAW-ovima

**Ableton Live:**
- Zamrzavanje (Freeze) traje predugo, blokira workflow
- Nema comping (snimanje više take-ova i biranje najboljih delova) — tek u 12+
- Ograničen MIDI editor — nema notation view, expression editing je primitivan
- Nema video track — post-production nemoguća
- Max for Live kočenje — CPU spike kad koristiš M4L device
- Session View ↔ Arrangement View desync — producenti gube rad
- Izvoz je SPOR — nema offline render optimizaciju

**Logic Pro:**
- macOS only — zaključava korisnike u ekosistem
- Mixer izgleda kao iz 2005. — UI zastareo
- MIDI environment je nerazumljiv — flight simulator kontrola
- Bounce offline NIKAD ne zvuči isto kao realtime — poznati bug
- Plugin scanning crash — restart celog DAW-a
- Undo history se gubi posle save — katastrofa za workflow
- Smart Tempo detektuje pogrešno u 30%+ slučajeva

**FL Studio:**
- Pattern/Playlist koncept zbunjuje početnike — jedinstven ali neintuitivni model
- Mixer routing je spaghetti — nema vizuelni signal flow
- Audio recording je sekundarni citizen — MIDI first filozofija
- Nema ARA podrška — Melodyne/SpectraLayers integra nemoguća
- Automation Clips su odvojeni od svega — teško upravljanje
- CPU threading loš — ne koristi sve core-ove efikasno
- macOS verzija je ZAOSTALA za Windows

**Bitwig Studio:**
- Stabilnost — crashuje više od drugih DAW-ova
- Plugin hosting — sandbox crashuje plugin bez razloga
- CPU optimizacija — troši više nego Ableton za isti projekat
- Dokumentacija — skoro pa ne postoji
- Preset browser — spor, bez tagova, chaotičan
- Nema notation view
- VST3 podrška kasni za standardom

**Reaper:**
- UI je RUŽAN — izgleda kao Windows 98
- Nema stock instrumente — moraš kupiti sve treće strane
- Learning curve — konfigurisanje traje danima
- JSFX plugin format — niko ga ne koristi van Reaper-a
- MIDI editor — funkcionalan ali primitivan UX
- Nema kolaboraciju — offline alat iz prošlosti
- Theme engine je moćan ali NIKO ne pravi profesionalne teme

**Pro Tools:**
- iLok DRM — producenti MRZE iLok (hardver dongle, licencni problemi)
- Subscription model — preskup za indie producente
- Avid hardware lock-in — "radi najbolje" sa Avid interfejsima
- Buffer size promene zahtevaju restart
- Editing je fenomenalno ali MIDI je katastrofa
- AAX only — ne podržava VST3, smanjuje plugin izbor
- Cloud kolaboracija je spora i nesigurna

**Studio One:**
- Mastering Page — dobar koncept ali polovično implementiran
- Show Page — live performance mod ima bug-ove
- Plugin scanner crash
- ARA integracija — jedina koja radi DOBRO (referenca za Flux)
- Scratch pad — genijalna ideja, loša implementacija

**Cubase/Nuendo:**
- NAJSTARIJI DAW — legacy kod iz 90-ih
- Dongle (ranije eLicenser) — isto kao iLok problemi
- MixConsole — moćan ali komplikovan
- Expression Maps — samo Cubase ih ima, ali UX je užasan
- MediaBay — scan traje SATIMA
- Svaki update slomi nešto — "Steinberg quality"
- ASIO Guard nepredvidiv

### 2. TEHNIČKE GRANICE — Gde se DAW-ovi lome

**Performanse:**
| DAW | Track limit pre pada | Plugin limit | Gde puca |
|-----|---------------------|-------------|----------|
| Ableton | ~150 audio | ~80 plugin chains | M4L + complex routing |
| Logic | ~200 audio | ~100 | Alchemy synth + Flex Time |
| FL Studio | ~100 pattern | ~60 | Mixer routing complexity |
| Bitwig | ~100 audio | ~50 sandboxed | Plugin sandbox overhead |
| Reaper | ~500+ audio | ~200 | UI postaje bottleneck pre audio engine-a |
| Pro Tools | ~256 (HDX limit) | ~128 (DSP limit) | Hardware ceiling |
| Cubase | ~200 | ~80 | MixConsole rendering |
| Studio One | ~200 | ~90 | ARA processing peak |

**Multithreading:**
- NIJEDAN DAW ne koristi GPU za audio processing (osim parcijalno Bitwig)
- Većina koristi per-bus threading, ne per-plugin
- Audio graph paralelizam je ograničen dependency chain-om
- Lock contention na mixer bus-ovima — univerzalni problem

**Memory:**
- Sample library loading — svi koriste disk streaming ali sa različitim cache strategijama
- Undo history — neograničena u memoriji, swap na disk kad ponestane RAM
- Waveform cache — svi regenerišu pri svakom otvaranju projekta (sporo)

**Latency:**
- Plugin latency compensation — SVE DAW-ovi imaju edge case bug-ove
- MIDI input latency — Pro Tools jedini sa sub-ms (sa HDX)
- Audio-to-MIDI konverzija — realtime je nemoguć sa <10ms latency

### 3. BUDUĆNOST VAN AUDIO INDUSTRIJE — Šta audio svet NIJE dotakao

**AI/ML alati koji audio industrija ignoriše:**
- **Generativni audio** — Stable Audio, MusicGen, AudioCraft — nijedan DAW nema native integraciju
- **AI mastering** — LANDR, eMastering, CloudBounce — DAW-ovi ih ne integrišu
- **Stem separation** — Demucs, LALAL.ai — samo Logic ima primitive verziju
- **Voice cloning** — ElevenLabs, RVC — nijedan DAW ne podržava
- **Intelligent mixing** — iZotope Neutron AI — ali kao plugin, ne native
- **Real-time style transfer** — Google Magenta, RAVE — akademski rad, nula u produkciji

**Game Engine inovacije koje DAW-ovi ne koriste:**
- **Node-based visual scripting** — Unreal Blueprints, Unity Visual Scripting → DAW-ovi još koriste linearne automation lane-ove
- **Real-time collaborative editing** — Figma model → nijedan DAW nema pravi real-time collab
- **Hot reload** — Flutter/React → DAW-ovi zahtevaju restart za plugin promene
- **GPU-accelerated rendering** — Metal/Vulkan → DAW-ovi renderuju waveform na CPU
- **Entity Component System (ECS)** — Bevy, Unity DOTS → DAW-ovi koriste monolitne objekte
- **Procedural generation** — Houdini, World Machine → audio nema proceduralne alate
- **Digital twins** — replika studija u softveru za testiranje pre fizičkog postavljanja
- **Spatial computing** — Apple Vision Pro, Meta Quest → 3D mixing postoji ali primitivan

**Kreativni alati koji su ISPRED audio sveta:**
- **Figma** — multiplayer editing, auto-layout, design tokens, plugin API → DAW ekvivalent NE POSTOJI
- **Notion/Obsidian** — linked thinking, graph view → project metadata u DAW-ovima je flat lista
- **After Effects/DaVinci** — node-based compositing → audio routing je zaostao 15 godina
- **Blender** — open source sa profesionalnim kvalitetom + geometry nodes → audio nema ekvivalent
- **TouchDesigner** — real-time generativna grafika sa MIDI/OSC → audio verzija ne postoji
- **Runway ML** — AI u kreativnom workflow-u → audio to tek počinje

### 4. FLUX PRILIKE — Gde Flux može da ubije

Na osnovu svega gore, ovo su oblasti gde Flux može biti **prvi na svetu**:

- [ ] **AI-native workflow** — ne plugin, ne sidebar — AI u jezgru editovanja (stem split, smart comp, generativni fill)
- [ ] **Real-time kolaboracija** — Figma model za audio: više producenata u istom projektu simultano
- [ ] **GPU waveform/spectrum** — Metal/Vulkan za sve vizualizacije, CPU samo za audio
- [ ] **Node-based routing** — vizuelni signal flow umesto mixer-strip paradigme
- [ ] **Proceduralni audio** — generator zvuka baziran na pravilima, ne samo sample playback
- [ ] **Hot reload plugins** — promena parametara bez restart-a, live patching
- [ ] **Unified MIDI+Audio** — jedan clip type koji je i MIDI i audio istovremeno (Bitwig pokušao, loše)
- [ ] **Smart project memory** — DAW koji pamti šta si radio, predlaže sledeći korak, uči od tebe
- [ ] **Cross-platform native** — jednaki performansi na macOS, Windows, Linux (ne Electron wrapper)
- [ ] **Zero-config audio** — bez ASIO, bez driver setup-a, radi iz kutije

---

## Reference

- `AGENT_TEAM_ARCHITECTURE.md` — Agent tim arhitektura + kompletna tabela bagova
- `.claude/architecture/WRATH_OF_OLYMPUS_GAME_FLOW.md` — WoO flow spec
- `.claude/architecture/SLOTLAB_COMPLETE_INVENTORY.md` — 23 blokova inventar
- `.claude/architecture/SLOT_LAB_SYSTEM.md` — Stage pipeline, providers, FFI
- `.claude/architecture/SLOTLAB_VOICE_MIXER.md` — Voice mixer arhitektura
- `.claude/architecture/DAW_EDITING_TOOLS.md` — DAW alati + QA
- `.claude/docs/VST_HOSTING_ARCHITECTURE.md` — VST3/AU/CLAP hosting spec
- `.claude/docs/DEPENDENCY_INJECTION.md` — GetIt/provideri
- `.claude/docs/TROUBLESHOOTING.md` — poznati problemi i resenja
- `.claude/specs/SFX_PIPELINE_WIZARD.md` — SFX Pipeline 6-step spec
- `.claude/specs/FLUXFORGE_MASTER_SPEC.md` — 17 sistema pregled
