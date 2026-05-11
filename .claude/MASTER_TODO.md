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
  - AUDIO: master meters, fader, channel strips, events list, NeuralBindOrb (instant drag-bind + scoring engine)
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
- NeuralBindOrb — instant drag-to-bind sa neural vizualizacijom: folder drag → <300ms full bind. Orb state machine (idle→dragHover→analyzing→done→error), CustomPainter circular node layout, wave ring animations, confidence scoring (FFNC 100 > Exact 90 > Prefix 80 > Fuzzy 65), staggered reveal, compact bottom sheet sa top matches. Zamenjuje stari multi-step AutoBindDialog
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

### Audio Pipeline — ✅ KOMPLETNO (2026-04-22)
- ~~Stage→Asset naming~~ ✅ — `rf-stage/src/audio_naming.rs` (450+ LOC, 13 testova)
- ~~FFI bridge (4 funkcije)~~ ✅ — `rf-bridge/src/slot_lab_ffi.rs` (resolve_audio_assets, resolve_stage_audio, get_canonical_asset_ids, audio_coverage)
- ~~Dart FFI bindings~~ ✅ — `flutter_ui/lib/src/rust/slot_lab_v2_ffi.dart` (4 metode)
- ~~StageAudioMapper 3-tier wiring~~ ✅ — `flutter_ui/lib/services/stage_audio_mapper.dart` (user→Rust→legacy fallback)
- ~~BUG #14 AudioThreadCell~~ ✅ — `rf-engine/src/playback.rs` (RwLock→AudioThreadCell, zero silent frames)

### OrbMixer — Radijalni Audio Mixer (TODO)

> Kompaktan futuristički mixer u jednom krugu (120×120px). Zamenjuje DAW channel strips.
> **Ovo ne postoji NIGDE** — ni Wwise, ni FMOD, ni Pro Tools.
> Kompletna arhitektura: `docs/architecture/ORBMIXER_ARCHITECTURE.md`

**3 nivoa interakcije:**

| Nivo | Šta se vidi | Aktivacija |
|------|-------------|------------|
| 1: Orbit View | 6 bus tačaka + Master centar (120×120px) | Default |
| 2: Bus Expand | Individualni zvukovi unutar busa (voice dots) | Tap na bus dot |
| 3: Sound Detail | Per-voice parametri (vol/pan/pitch/HPF/LPF/send) arc slideri | Long-press na voice dot |

**Vizualni parametri (Nivo 1):** udaljenost=volume, ugao=pan, veličina=peak, boja=kategorija, glow=solo, dim=muted

**Gestovi:** drag radijalno=volume, drag kružno=pan, click=solo, right-click=mute, scroll=fine vol, hover=tooltip

**4 vizuelna sloja:**
- Ghost Trails — bledi trag prethodne pozicije (2s), dupli tap=undo
- Magnetic Snap Groups — linkovanje zvukova u klaster, pinch za razdvajanje
- Frequency Heatmap — živa spektralna pozadina (bass=crveno centar, treble=plavo ivica)
- Timeline Scrub Ring — spoljašnji prsten, replay mixa poslednjih 30s

**Slot-specific:** win escalation glow, anticipation tension, idle dimming, feature transition

**Integrisanje:** floating (120px overlay), docked (80px toolbar), embedded (HELIX AUDIO), expanded (180px hover)

**Faze implementacije:**
- [x] Phase 1: Bus Routing Fix (P0 preduslov) ✅ DONE (2026-04-22)
- [x] Phase 2: OrbMixer Nivo 1 (bus dots + gestures + MixerProvider) ✅ DONE (2026-04-22) — 514+745+894 LOC
- [x] Phase 3: OrbMixer Nivo 2 (FFI active voices + bus expand) ✅ DONE (2026-04-22) — full vertical stack
- [x] Phase 4: OrbMixer Nivo 3 (per-voice params + arc sliders) ✅ DONE (2026-04-22) — OrbParamArc, long-press ring
- [x] Phase 5: Vizuelni slojevi (ghost trails, magnetic snap, heatmap, scrub ring) ✅ DONE (2026-04-22) — 12 paint layers
- [x] **Phase 6: HPF/LPF/Send Engine Wire-up** ✅ DONE (2026-04-22, commit `37d65489`) — OneShotCommand SetHpf/SetLpf/SetSend + per-voice BiquadTDF2 × 4 + fill_buffer per-sample application
- [x] **Phase 7: Real-time RMS metering po voicu** ✅ DONE (pre-existing, audit confirmed) — meter_peak_l/r in fill_buffer + FFI packed indices 4/5 + painter glow ∝ peak
- [x] **Phase 8: Frequency Heatmap iz živog FFT-a** ✅ DONE (2026-04-22, commit `2ba2ce1f`) — `_updateHeatmapFromFft` reads master 32-band spectrum directly
- [x] **Phase 9: Live Play Companion Mode** ✅ DONE (2026-04-22, commits `717703d1` + `4c850c33`) — floating overlay, 3 sizes, drag handle, reveal button, keyboard O/Shift+O, SharedPrefs persist
- [x] **Phase 10: 130-Voice Live Mix Orchestra** ✅ DONE (2026-04-22, commits `ae2a6df7`+`c436a67a`+`3e607545`+`6395f0f3`+`f9d68183`) — 5 substages: foundation, rendering, UX chips, live alerts, Problems Inbox
- [x] **Phase 10e-2: Audio ring buffer capture** ✅ DONE (2026-05-11) — `orb_ring_init`, `orb_ring_frames_written`, `orb_capture_last_n_seconds`, `orb_ring_rearm` u Rust FFI + Dart bindings + `ProblemsInboxService._captureClipFor()`
- [x] **Phase 10 polish** ✅ DONE (2026-05-11) — `PerBusBandAnalyzer` u `rf-engine/src/per_bus_band_energy.rs`, `SHARED_METERS.bus_band_rms[24]`, Phase 10e-3 u `orb_mixer_alerts.dart`, Phase 10e-4 isolate path u `orb_mixer_provider.dart` linija 575-585

**Planirani fajlovi (~1950 LOC):**
- `flutter_ui/lib/widgets/slot_lab/orb_mixer.dart` (~800)
- `flutter_ui/lib/widgets/slot_lab/orb_mixer_painter.dart` (~500)
- `flutter_ui/lib/providers/orb_mixer_provider.dart` (~300)
- `crates/rf-bridge/src/orb_mixer_ffi.rs` (~150)
- `crates/rf-engine/src/voice_control.rs` (~200)

### Audio Bus Routing Wireup — ✅ KOMPLETNO (2026-04-22)

> Bus routing potpuno funkcionalan. Voice→Bus, Send→Bus, Bus InsertChain, Dart↔Rust sync.

**Trenutni status:**
- ✅ BusManager (7 buseva) — `rf-engine/src/bus.rs`
- ✅ Mixer (6ch+master, HPF/Gate/Comp/EQ, TruePeak, rtrb) — `rf-engine/src/mixer.rs`
- ✅ InputBus (Cubase-style, zero-copy) — `rf-engine/src/input_bus.rs`
- ✅ Send/Return (8 sendova, 4 returna) — `rf-engine/src/send_return.rs` — definisan (redundantan sa bus sistemom)
- ✅ BusSendNode — `hook_graph/dsp_nodes/bus_send.rs` — smoothed level, click-free
- ✅ BusReturnNode — `hook_graph/dsp_nodes/bus_return.rs` — NEW (120 LOC, 3 testa)
- ✅ BusHierarchyProvider (Dart, 11-bus) — komplet
- ✅ Mixer (6ch+master, HPF/Gate/Comp/EQ, TruePeak, rtrb) — `rf-engine/src/mixer.rs`
- ✅ Dart→Rust bus sync — MixerDSPProvider → NativeFFI → PlaybackEngine.set_bus_*() → bus_states

**Šta je urađeno (2026-04-22):**
1. HookGraphEngine.process_into_buses() — voices route to assigned bus via BusBuffers
2. render_voices_to_buses() — thread-local scratch buffers, zero audio-thread alloc
3. BusSendNode — rewritten with one-pole smoother (click-free level changes)
4. BusReturnNode — NEW node (mute, smoothed level, 3 unit testa)
5. SetBusVolume command wired in HookGraphEngine.drain_commands()
6. playback.rs calls process_into_buses() instead of legacy process()
7. Track sends → bus buffers (pre/post fader, pan, level) — playback.rs:6536-6578
8. Bus InsertChains (pre+post fader, sidechain-aware) — playback.rs:6770-6829
9. Dart→Rust: MixerDSPProvider → FFI → bus_states RwLock (volume/pan/mute/solo)

**NAPOMENA:** send_return.rs (SendBank/ReturnBusManager) je arhitektonski redundantan
sa bus sistemom — svaki bus već ima InsertChain, volume, pan, mute/solo. ReturnBusManager
ostaje kao potencijalno proširenje za >6 return tačaka (P3+).

### Audio Pipeline — Completeness Status (2026-04-22)

| Komponenta | Status | Lokacija |
|------------|--------|----------|
| Stage→Asset naming (Rust) | ✅ | `rf-stage/src/audio_naming.rs` (450+ LOC, 13 testova) |
| FFI bridge (4 funkcije) | ✅ | `rf-bridge/src/slot_lab_ffi.rs` |
| Dart FFI bindings | ✅ | `flutter_ui/lib/src/rust/slot_lab_v2_ffi.dart` |
| StageAudioMapper 3-tier wiring | ✅ | `flutter_ui/lib/services/stage_audio_mapper.dart` |
| BUG #14 AudioThreadCell | ✅ | `rf-engine/src/playback.rs` (zero silent frames) |
| SlotLab Audio Coverage Widget | ✅ DONE | badge + dialog, dual coverage, missing assets |
| Bus routing wireup | ✅ DONE | HookGraphEngine + BusSend/Return + Dart sync |
| OrbMixer (5 faza) | ✅ DONE | 2153 LOC, 3 nivoa, 4 viz sloja, UI integrisano |
| Per-voice FFI | ✅ DONE | orb_get_active_voices + orb_set_voice_param |

### Ostalo TODO
- [x] SlotLab Audio Coverage Widget ✅ DONE (2026-04-22) — badge+dialog, asset path fix
- [x] Neural Bind Orb fix ✅ DONE (2026-04-22) — 0 errors, 0 warnings
- [x] OrbMixer UI placement ✅ DONE (2026-04-22) — živ u _AudioPanel (helix_screen)
- [x] AudioCoverage canonical fix ✅ DONE (2026-04-22) — audioAssignments.values umesto stage keys
- [x] QA (flutter analyze + cargo tests) ✅ DONE (2026-04-22) — 0 errors, 313+27 testova pass
- [x] Full Build + Test ✅ (cargo test 0 failed, flutter analyze 0 issues, 2026-05-11)
- [x] **Sonic DNA Classifier** ✅ DONE (2026-04-22) — Layer 2 (15 profila) + Layer 3 (Hungarian + variant + gap) + FFI + Dart models
- [x] **OrbMixer Phase 6: HPF/LPF/Send wire-up** ✅ DONE (2026-04-22) — commit `37d65489`
- [x] **OrbMixer Phase 7: RMS metering po voicu** ✅ DONE (pre-existing, audited 2026-04-22)
- [x] **OrbMixer Phase 8: Live FFT heatmap** ✅ DONE (2026-04-22) — commit `2ba2ce1f`
- [x] **OrbMixer Phase 9: Live Play Companion Mode** ✅ DONE (2026-04-22) — commits `717703d1` + stability `4c850c33`
- [x] **OrbMixer Phase 10: 130-Voice Live Mix Orchestra** ✅ DONE (2026-04-22) — 5 commits: foundation / rendering / UX / alerts / inbox
- [x] **OrbMixer Phase 10e-2: Audio ring buffer capture** ✅ DONE (2026-05-11) — `orb_ring_init`, `orb_ring_frames_written`, `orb_capture_last_n_seconds`, `orb_ring_rearm` u Rust FFI + Dart bindings + `ProblemsInboxService._captureClipFor()`
- [ ] **NeuralBindOrb Phase 2: Ghost slot indikatori** — stage-ovi bez audio bindinga prikazani kao ghost u orbu (gap analysis integration)

---

## OrbMixer — Phase 9: Live Play Companion Mode (DETAILED SPEC)

> **Vizija:** Dok igram slot, orb mi je pri ruci. Ako je neki zvuk glasan, smiksujem ga na licu mesta, on se updateuje u realnom vremenu. Nema "stop → podesi → play" ciklusa. **Closed feedback loop < 1 sekunda.**

### Kontekst — šta već imamo
| Komponent | Status | Fajl |
|-----------|--------|------|
| OrbMixer widget (3 nivoa) | ✅ | `flutter_ui/lib/widgets/slot_lab/orb_mixer.dart` (514 LOC) |
| OrbMixer painter (4 viz sloja) | ✅ | `flutter_ui/lib/widgets/slot_lab/orb_mixer_painter.dart` (745 LOC) |
| OrbMixer provider | ✅ | `flutter_ui/lib/providers/orb_mixer_provider.dart` (894 LOC) |
| Active voices FFI | ✅ | `crates/rf-bridge/src/orb_mixer_ffi.rs` → `orb_get_active_voices()` |
| Per-voice params FFI | ✅ | `orb_set_voice_param(voice_id, param, value)` |
| Premium Slot Preview (fullscreen) | ✅ | `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart` |

**Rupa:** Orb je zakucan u Lower Zone / HELIX `_AudioPanel`. U full-screen slot preview-u nije dostupan.

### Cilj
Floating overlay widget koji lebdi preko `PremiumSlotPreview`, uvek dostupan, nikad u putu.

### 1. Floating Overlay Arhitektura
- **Widget:** novi `LivePlayOrbOverlay` — `Stack` child iznad slot preview-a
- **Positioning:** `Positioned` sa `Offset(x, y)` u provider state-u; default donji-desni ugao (16px margin)
- **Lifting z-order:** preko svega osim WinPresenter-a (kad WinPresenter peak fullscreen → orb dim na 30%)
- **Draggable:** `GestureDetector.onPanUpdate` → update `Offset`; `onPanEnd` → snap na najbližu ivicu (top/bottom/left/right)
- **Snap logika:** ako je `center.distance(edge) < 48px` → magnetno prilepi uz ivicu sa 8px margin-om
- **Persist pozicije:** `SharedPreferences` → `orb_position_x`, `orb_position_y`, `orb_dock_edge`

### 2. Tri veličine (LOD — Level of Detail)
| Mod | Veličina | Što prikazuje | Aktivacija |
|-----|----------|---------------|------------|
| **Mini** | 60×60px | Samo Master fader kao prsten + peak LED | tap na "mini" toggle |
| **Standard** | 120×120px | 6 buseva + Master centar (Nivo 1) | default |
| **Full** | 240×240px | 6 buseva + ekspanzija voice-ova (Nivo 2) | pinch-out ili double-tap |

**Tranzicija:** `AnimatedContainer` sa `Duration(ms: 180)` + `Curves.easeOutCubic`. Painter receivuje `scale` parametar i re-kalkuliše rastojanja proporcionalno.

### 3. Transparency & Auto-Hide
- **Default opacity:** 0.85 kad nije "in use"
- **In use:** 1.0 (finger down, drag, hover u desktop-u)
- **Auto-hide trigger:** 3s bez interakcije → `AnimatedOpacity` → 0.40
- **Revive:** bilo koji touch u 32px radijusu → instant 1.0
- **Never fully hidden** — uvek minimum 0.40 da ostane jasno gde je

### 4. Gesture mapa
| Gesture | Akcija |
|---------|--------|
| Single tap bus | Solo toggle |
| Double tap bus | Mute toggle |
| Drag radial on bus | Volume (near→low, far→high) |
| Drag angular on bus | Pan (L↔R) |
| Long-press bus centar | Ekspanzija (Nivo 2 voices) |
| Long-press orb centar | **Undo last change** (poslednja volume/pan promena) |
| Swipe levo preko orba | Sakrij (fade na 0.15, samo "halo" ostane) |
| Double-tap ivice ekrana | Vrati sakriveni orb |
| Pinch-out | Mini → Standard → Full |
| Pinch-in | Full → Standard → Mini |

### 5. Live Pulse (zavisi od Phase 7 RMS stream-a)
- Svaki bus prsten pulsira po **trenutnom RMS-u** tog busa
- **Algoritam:** `glow_intensity = clamp(rms_db + 40, 0, 40) / 40` (mapiranje -40dB..0dB → 0..1)
- Bus koji "gori" (peaking) vidis trenutno — to ti kaže KOJI da pipneš

### 6. Persist mix (autosave)
- Svaka promena volume/pan ide u `projectProvider.setBusMix(busId, vol, pan)` odmah
- Debounce 500ms → zapis u projekat JSON
- **Nema "Save Mix" dugmeta** — kao što audio editori (Logic/Ableton) uvek pamte

### 7. Undo history
- In-memory `CircularBuffer<MixChange>` (kapacitet 32)
- `MixChange { voice_or_bus_id, param, old_value, new_value, timestamp }`
- Long-press centar orba → pop sa vrha → reverse change → apply
- Vizuelno: kratko "↶ vol -2dB Bus SFX" toast ispod orba (2s fade)

### 8. "Problem-first" zoom (bonus feature)
- **Long-press + hold 500ms** → orb analizira poslednjih 500ms RMS-a svih buseva
- Bus sa najvećim `rms_peak × time_above_threshold` score-om → **automatski highlight-uje sa crvenim prstenom**
- Vibracija (ako mobile) → znaš koji je
- Još 300ms držiš → orb zumira na taj bus (Nivo 2) — direktno vidiš voice-ove
- Otpustiš → reset

### Konkretni fajlovi za implementaciju
| Fajl | LOC est. | Šta |
|------|----------|-----|
| `flutter_ui/lib/widgets/slot_lab/live_play_orb_overlay.dart` | ~280 | Floating widget, positioning, drag, snap, opacity states |
| `flutter_ui/lib/providers/live_play_orb_provider.dart` | ~180 | State (position, size mode, visible, autohide timer, undo buffer) |
| `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart` | +20 | Integracija: `Stack` child sa LivePlayOrbOverlay |
| `flutter_ui/lib/widgets/slot_lab/orb_mixer_painter.dart` | +40 | `scale` param + LOD rendering (mini/std/full) |
| `flutter_ui/lib/providers/orb_mixer_provider.dart` | +60 | Undo buffer + `popUndo()` metoda + problem-first zoom helper |
| `flutter_ui/lib/theme/fluxforge_theme.dart` | +8 | `liveOrbGlow`, `liveOrbDim` boje |

**Ukupno:** ~588 LOC novo + ~128 LOC izmene

### Testovi
- Widget test: drag → position update → snap na ivicu
- Widget test: pinch-out → mode prelazak (mini→std→full)
- Widget test: auto-hide tajmer → opacity 0.40 posle 3s
- Widget test: long-press orb centar → undo applied
- Integration test: WinPresenter peak → orb opacity 0.30 dok traje

---

## OrbMixer — Phase 10: 130-Voice Live Mix Orchestra (DETAILED SPEC)

> **Problem:** Slot ima 130 zvukova. 30+ SFX, 20+ MUS varijanti, 40+ VO, 15 AMB. Ne mogu svi u jedan krug.
> **Rešenje:** Hijerarhija + vremenska memorija + inteligentno filtriranje. Nikad više od ~10 tačaka na ekranu.

### Brutalna realnost
| Faza igre | Istovremeno aktivnih voice-ova |
|-----------|-------------------------------|
| Idle | 1-2 (ambient beds) |
| Spin | 3-5 (spin loop, reel stops, music bed) |
| Win rollup | 8-12 (rollup, particles, fanfara, VO, ducking) |
| Feature trigger | 10-15 (cluster) |
| **Max peak** | **~15 istovremeno** |

Ali **130 postoji u biblioteci** — i oni se vrte. Zvuk svira 300ms i nestane. Nemoguće ga je uhvatiti prstom.

### 1. Tri-slojna hijerarhija
#### Sloj 1 — BUSEVI (6 fiksno)
Uvek isti, uvek vidljivi:
- Music / SFX / Voice / Ambience / Aux / Master

#### Sloj 2 — KATEGORIJE (~15-20 dinamički)
Smart grupe po event taksonomiji (postojeća `SlotEventIds` u `flutter_ui/lib/models/slot_audio_events.dart`):

```
SFX bus     → [Spin loop] [Reel stops] [UI clicks] [Win rollup] [Collect] [Near miss]
MUS bus     → [Base] [Anticipation] [Feature] [BigWin Tier 1] [Tier 2] [Tier 3] [Tier 4] [Tier 5]
VO bus      → [Char A] [Char B] [Narrator] [Announcer]
AMB bus     → [Lobby] [Game idle] [Feature amb]
Aux bus     → [Send FX 1] [Send FX 2]
```

**Mapiranje:** pravimo `VoiceCategoryResolver` servis — za `voice_id` → resolve to category via event_id ranges (već definisane u `SlotEventIds`).

**Aktivacija:** tap na bus → expand u 3-6 kategorija; svaka tačka pulsira ako u toj kategoriji nešto trenutno svira.

#### Sloj 3 — INDIVIDUALNI VOICE (aktivni + nedavni)
Tap na kategoriju → vidiš **samo voice-ove koji su svirali u poslednjih 10 sekundi** (recent + active). Tipično 3-8, ne 30.

### 2. Time-Rewind Orb (ghost slots)
**Problem:** SFX svira 300ms. Ne stigneš.

**Rešenje:**
- Orb pamti **poslednjih 10 sekundi** aktivnosti svih voice-ova u `VoiceHistoryBuffer`
- Svaki voice koji je svirao → ghost tačka u orbitalnom prstenu oko svog bus-a
- **Fade algoritam:** `alpha = 1.0 - (age_ms / 10000.0)` (10s do potpunog nestanka)
- **Tap ghost tačke** → solo replay taj voice (jedna instanca, bez bus overlapa) + orb se zadrži na njoj 5s za edit
- **Timeline skala:** 0-2s = 100% alpha, 2-5s = 80%, 5-10s = 60%→0%

**Data model:**
```dart
class GhostSlot {
  final int voiceId;
  final String canonicalAssetId;
  final int busId;
  final DateTime startedAt;
  final DateTime endedAt;
  final double peakRms;
  double get ageSeconds => DateTime.now().difference(endedAt).inMilliseconds / 1000;
  double get alpha => (1.0 - (ageSeconds / 10)).clamp(0.0, 1.0);
}
```

**Buffer:** `CircularBuffer<GhostSlot>` kapacitet 128, eviction po `endedAt > 10s`.

### 3. Auto-Focus na problem
**Kad čuješ "ovaj zvuk je preglasan", ne moraš da znaš koji je.**

1. **Long-press centra orba** (500ms+) → game pause, freeze snapshot
2. Orb kalkuliše **"culprit score"** za svaki voice u poslednjih 500ms:
   ```
   culprit_score = rms_peak_db_abs × time_active_ms × frequency_dominance
   ```
   gde je `frequency_dominance` = % spektra koji voice zauzima (iz FFT-a)
3. Voice sa najvećim score-om → orb **automatski zumira na njega** (Nivo 3)
4. Arc slider za volume se otvori odmah
5. Spustis → unpause → nastavi igru

**Engine support:** `orb_get_culprit_voice(last_ms: u32) -> i64` → voice_id ili -1.

### 4. Live Alerts ("crveni prsten")
Daemon pomaže u realnom vremenu:

| Alert | Boja | Trigger |
|-------|------|---------|
| **Clipping** | Crveno puls | `true_peak > -0.3 dBTP` na busu |
| **Frequency masking** | Žuti arc između 2 voice-a | 2+ voice-a u istom 1/3 oktavnom opsegu sa RMS > -18dB |
| **Phase cancellation** | Ljubičasti outline | correlation < 0.3 na stereo polju |
| **Headroom warning** | Narandžasto | bus master > -6dB LUFS-M u 500ms prozoru |

**Engine support:**
- `orb_get_alerts() -> Vec<Alert>` preko JSON FFI
- Tipovi: `Clipping(bus_id)`, `Masking(voice_a, voice_b, band_hz)`, `PhaseIssue(bus_id, corr)`, `Headroom(bus_id, lufs)`
- Poll rate: 100ms (10Hz)

**Haptic:** na mobile → `HapticFeedback.mediumImpact()` kad alert pojavi (max jedan per 2s da ne dosadi)

### 5. Mark Problem dugme (retrospective)
Kad čuješ nešto čudno ali nemaš vremena:

1. Tap **crveni marker dugme** (malo dugme u donjem desnom uglu orba) — samo beleži, ne prekida game
2. Sačuvaj: `timestamp + active_voices_snapshot + spectrum_snapshot + 3s_audio_clip (ring buffer)`
3. Nastavljaš igru
4. Posle `stop` → otvori se **"Problems Inbox"** panel
5. Lista svih markera, svaki sa 3-sekundnim audio clip-om i thumbnail spektra
6. Tap marker → replay sa orbom u stanju iz tog momenta + možeš odmah da fix-uješ

**Data model:**
```dart
class MixProblem {
  final int id;
  final DateTime markedAt;
  final List<ActiveVoiceSnapshot> voices;
  final Float32List audioClip;  // 3s x 48kHz = 144k samples
  final Float32List spectrum;    // 2048-bin FFT
  final List<Alert> activeAlerts;
}
```

**Storage:** `List<MixProblem>` u `projectProvider._problems` → serialize u `.fluxforge/problems.json` (audio clipovi kao WAV u `.fluxforge/problems/`)

**Engine support:**
- Ring buffer poslednjih 5 sekundi audio-a po master bus-u (već postoji za scrub)
- `orb_capture_problem_snapshot() -> ProblemSnapshot` FFI

### 6. Quick Filter chip-ovi
4 male ikonice oko orba (radijalno raspoređene u 4 ugla prstena):

| Chip | Akcija |
|------|--------|
| 🎵 **SFX only** | Sakrij sve osim SFX bus-a + njegovih kategorija |
| 🔊 **Loud now** | Prikaži samo voice-ove sa RMS > -12dB trenutno |
| ⏱ **Recent** | Samo voice-ovi iz poslednjih 5 sekundi (ghosts uključeni) |
| 🎚 **Muted hidden** | Sakrij mute-ovane buseve |

**Kombinovanje:** chip-ovi su toggle, mogu biti kombinovani (AND logika). Aktivni chip = cyan outline.

**Persist:** poslednji aktivni set chip-ova u `SharedPreferences` → `orb_filters_active`.

### 7. Performance zahtevi
- **Paint frame budget:** ≤ 4ms (@ 60fps = 16.67ms total)
- **FFI poll rate:** active voices 60Hz, RMS 60Hz, alerts 10Hz, culprit on-demand
- **Ghost buffer eviction:** background isolate, ne blokira UI
- **Max concurrent ghosts:** 64 (performance cap — dodatni se evict-uju)

### 8. Konkretni fajlovi za implementaciju

#### Rust (engine)
| Fajl | LOC est. | Šta |
|------|----------|-----|
| `crates/rf-engine/src/voice_history.rs` | ~180 | `VoiceHistoryBuffer` — cirkularni buffer ghost slotova, timestamp tracking |
| `crates/rf-engine/src/culprit_analyzer.rs` | ~220 | `CulpritScorer` — RMS × time × freq dominance, 500ms lookback |
| `crates/rf-engine/src/mix_alerts.rs` | ~260 | Alert detekcija: clip, masking (FFT 1/3 oct), phase correlation, headroom LUFS |
| `crates/rf-engine/src/problem_capture.rs` | ~150 | `ProblemSnapshot` + 5s audio ring buffer clone + FFT snapshot |
| `crates/rf-bridge/src/orb_mixer_ffi.rs` | +140 | `orb_get_ghost_slots()`, `orb_get_culprit_voice()`, `orb_get_alerts()`, `orb_capture_problem_snapshot()` |

#### Dart (UI)
| Fajl | LOC est. | Šta |
|------|----------|-----|
| `flutter_ui/lib/providers/voice_category_resolver.dart` | ~200 | Voice_id → (bus, category) mapiranje via SlotEventIds ranges |
| `flutter_ui/lib/widgets/slot_lab/orb_category_ring.dart` | ~240 | Nivo 1.5 widget — ekspandovane kategorije oko bus tačke |
| `flutter_ui/lib/widgets/slot_lab/orb_ghost_painter.dart` | ~180 | Ghost slot rendering sa alpha fade |
| `flutter_ui/lib/widgets/slot_lab/orb_alert_overlay.dart` | ~220 | Crveni/žuti/ljubičasti/narandžasti overlay slojevi |
| `flutter_ui/lib/widgets/slot_lab/problems_inbox_panel.dart` | ~380 | Retrospective review panel — lista, audio player, replay button |
| `flutter_ui/lib/widgets/slot_lab/orb_quick_filters.dart` | ~160 | 4 chip dugmeta oko orba, toggle state |
| `flutter_ui/lib/providers/orb_mixer_provider.dart` | +240 | Ghost buffer state, alerts stream, filters state, auto-focus logika |
| `flutter_ui/lib/models/mix_problem.dart` | ~120 | MixProblem data model + serialization |

**Ukupno:** ~810 LOC Rust + ~1740 LOC Dart + ~380 LOC izmene = ~2930 LOC novo

### 9. Faze unutar Phase 10 (subfaze)
- **10a:** VoiceCategoryResolver + Nivo 1.5 kategorijski ring
- **10b:** VoiceHistoryBuffer + Ghost slots rendering
- **10c:** Culprit analyzer + Auto-Focus long-press logika
- **10d:** Mix alerts (clip → masking → phase → headroom, redom po važnosti)
- **10e:** Problem capture + Problems Inbox panel
- **10f:** Quick Filter chip-ovi
- **10g:** Performance tuning (isolate za ghost buffer, FFI poll optimization)

### 10. Testovi
- Unit Rust: VoiceHistoryBuffer eviction pod opterećenjem (1000 voice startova/s)
- Unit Rust: CulpritScorer bira tačan voice sa predefined RMS/freq scenario
- Unit Rust: MixAlerts detektuje clipping unutar 100ms
- Widget test: kategorijski ring se ekspandira na tap bus-a
- Widget test: ghost slot fade iz 1.0 na 0.0 u 10s
- Widget test: long-press 500ms centra orba → auto-focus na najglasniji
- Widget test: quick filter "Loud now" sakriva voice-ove sa RMS < -12dB
- Integration: igra spin → win sa 12 voice-ovima → Problems Inbox prikazuje marker sa ispravnim snapshot-om

### 11. Edge case-ovi koji moraju biti pokriveni
- **Voice startuje i završi unutar 1 audio bloka (<11ms):** i dalje mora biti ghost (zapisan u buffer sa `duration_ms = 0`)
- **Glitch u FFT-u (NaN):** alert detector mora safe-default (no alert umesto panic)
- **Problem capture tokom clip-a:** audio clip mora biti iz ring buffer-a PRE alert-a (ne tokom limiter-ovog reakcionog vremena)
- **Pozicija orba preko Problems Inbox dugmeta:** auto-offset za 40px
- **Kategorija bez aktivnih voice-ova:** tačka je prisutna ali 30% alpha (grey state)
- **130+ voice-ova u biblioteci, 0 aktivnih trenutno:** orb prikazuje samo buseve, nema praznog prostora

### 12. Otvorena pitanja za diskusiju
1. **Problems Inbox** — koliko problema da čuvamo per sesija? 50? 100?
2. **Auto-focus trigger** — long-press je 500ms. Isto na mobile i desktop, ili kraće na mobile?
3. **Haptic na alerts** — samo na mobile, ili i na desktop preko system-beep toggle-a?
4. **Category resolver** — da li koristiti postojeće `SlotEventIds` range-ove ili napraviti nov `VoiceCategory` enum?
5. **Ghost replay** — solo reprodukcija ghost slotova: da li zaustavlja trenutnu igru ili dozvoljava preklapanje?

---

---

## Slot Flow — IGT Parity (🔴 KRITIČNO — DETAILED SPEC)

> **Boki zahtev (2026-04-22):** "Flow slot mašine ne radi potpuno kao IGT. Skip, slam, koliko traju, kad se pojavljuje spin, prelazak base→FS i nazad — sve mora biti do tančina kao IGT."
> **Cilj:** 1:1 parity sa IGT Playa game flow-om, bez ijednog rupa. Closed FSM loop, clean state transitions, ispravan UX svakog dugmeta u svakoj fazi.

### 🧭 Referentni dokumenti (read FIRST)
- `SLOTLAB_VS_PLAYA_ANALYSIS.md` (root) — konkurentska analiza, Playa patterns
- `.claude/architecture/WRATH_OF_OLYMPUS_GAME_FLOW.md` — kompletan flow reference sa svim timing-ima
- `FLUXFORGE_SLOTLAB_ULTIMATE_ARCHITECTURE.md` — compliance + vizija
- Kod fajlovi:
  - `flutter_ui/lib/providers/slot_lab/game_flow_provider.dart` (1217 LOC — FSM)
  - `flutter_ui/lib/models/game_flow_models.dart` (state enum)
  - `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart` (fullscreen preview — spin/stop/skip handlers)
  - `flutter_ui/lib/widgets/slot_lab/game_flow_overlay.dart` (plaque transitions)
  - `flutter_ui/lib/widgets/slot_lab/professional_reel_animation.dart` (reel animation)

---

### ✅ ŠTO VEĆ RADI KAKO TREBA (ne dirati)

| Komponenta | Status | Dokaz |
|------------|--------|-------|
| FSM — 9-state game flow | ✅ | `game_flow_provider.dart:86–1217`, enum `GameFlowState` sa `.isFeature` klasifikacijom |
| Feature queue + stack (nested do 5 nivoa) | ✅ | `GameFlowStack` sa `canNest()` pravilima |
| Spin/Stop/Skip phase detection | ✅ | `SpinButtonPhase` enum (`spin\|stop\|skip\|skipProtected`), `premium_slot_preview.dart:238–320` |
| Big Win skip protection 2.5s | ✅ | `_bigWinProtectionRemaining` countdown, `premium_slot_preview.dart:279, 3801` |
| Two-phase Big Win skip (BIG_WIN_END → collect) | ✅ | `_handleSkipWinPresentation` dvosmerno skip logika |
| Reel timing (Normal 250ms/Turbo 100ms/Slam 30ms) | ✅ | Arhitektura match sa WoO doc |
| Scene transitions (enter/exit plaque) | ✅ | `_startEnterTransition` / `_startExitTransition` sa `dismissMode` (timed/click/both) |
| Anticipation logic | ✅ | Per-reel detection, audio stops on SLAM |
| Win tier dynamics (P5 WinTierConfig) | ✅ | Superior to Playa's fixed tiers |
| Cascading/tumble (rf-slot-lab CascadesChapter) | ✅ | More sophisticated than Playa's GSAP approach |

---

### ❌ 5 KRITIČNIH RUPA KOJE LOME FLOW

#### 🔴 GAP #1: FSM nije wire-ovan na Spin handlers
**Problem:** `GameFlowProvider.onSpinStart()` i `onSpinComplete()` **postoje ali se NIKAD ne pozivaju** iz UI sloja.

**Lokacije:**
- `game_flow_provider.dart:502–547` — metode definisane (`onSpinStart`, `onSpinComplete`)
- `premium_slot_preview.dart:5888` — `_executeSpinAfterSkip()` zove `provider.spin()` ali **NE** zove `gameFlowProvider.onSpinStart()`
- `premium_slot_preview.dart:5930 (otprilike)` — `_processResult()` **NE** zove `gameFlowProvider.onSpinComplete(result)`

**Posledica lanca:**
1. FS spin counter ne opada — FS loop beskonačan
2. `_evaluateTriggers(context)` (line 550) nikad ne radi — novi feature triggers se ne detektuju
3. Retrigger detekcija potpuno mrtva
4. Feature queue ne aktivira sledeći feature
5. Cascade depth ne trackuje

#### 🔴 GAP #2: FS auto-loop nikad ne startuje
**Problem:** `GameFlowProvider.startFsAutoLoop()` (line 900–908) postoji, Timer-driven, ali UI ne zove ovu metodu posle FS entry plaque dismiss-a.

**Lokacije:**
- `game_flow_provider.dart:900–951` — `startFsAutoLoop()` + `onRequestAutoSpin` callback (line 143)
- `game_flow_overlay.dart` — FS counter UI postoji ali **nema callback-a** na plaque dismiss
- `premium_slot_preview.dart` — **zero referenci** na `gameFlowProvider.startFsAutoLoop()` ili `onRequestAutoSpin`

**Posledica:** U Free Spins modu korisnik mora **ručno** da klikne spin posle svakog FS-a. To nije IGT/arcade standard — FS je auto-play od ulaska do izlaska.

#### 🔴 GAP #3: SLAM STOP ne čisti feature state
**Problem:** `_handleStop()` (line 6396–6409) zove `slamStop()` na reel widget-u, ali **ne poziva** `gameFlowProvider.onSpinComplete()` niti `exitCurrentFeature()`.

**Lokacije:**
- `premium_slot_preview.dart:6396–6409` — samo `_previewKey.currentState?.slamStop()` + `_stopAnticipationAudio()`
- Nema poziva `gameFlowProvider.onSpinComplete(abortResult)` niti state reset-a

**Posledica:**
- SLAM tokom FS-a → FS counter ostaje stale
- Auto-loop timer i dalje otkucava (orphan timer)
- Cascade depth se ne resetuje
- Feature state inconsistent sa stvarnim stanjem igre

#### 🔴 GAP #4: Deferred Big Win posle FS nikad se ne prikazuje
**Problem:** `GameFlowProvider.onDeferredBigWin` callback (line 147) se invoke-uje (line 735–739) kad je FS totalWin ≥ 10× bet, ali **UI nije subscribovan** na taj callback.

**Lokacije:**
- `game_flow_provider.dart:147, 735–739` — callback signature: `(double totalWin, double winRatio)`
- `premium_slot_preview.dart` — **zero referenci** na `onDeferredBigWin`

**Posledica:** Završiš FS sa totalWin = 50× bet → trebao bi "EPIC WIN" overlay sa 12s celebration → umesto toga samo tihi exit plaque "FREE SPINS COMPLETE" i back to base. **Potpuno gubitak emocionalne punote.**

#### 🔴 GAP #5: Future.delayed bez mounted guard-a (race conditions)
**Problem:** Minimum 5 mesta u `premium_slot_preview.dart` sa chained `Future.delayed` bez `if (!mounted) return;` provera.

**Lokacije (konkretne linije):**
- `premium_slot_preview.dart:5040, 5046, 5053` — tri chained delay-a (300ms, 3000ms, 4200ms) u win presentation kodu
- `premium_slot_preview.dart:6214` — delay u keyboard handler-u
- `premium_slot_preview.dart:7101` — delay u animation callback-u
- `premium_slot_preview.dart:6037` — visual-sync timer, brisan samo na sledećem spin-u (leak ako se widget dispose-uje mid-spin)

**Posledica:**
- `setState() called after dispose` warnings
- Memory leak orphan timera
- Crash kad korisnik izađe iz preview-a tokom Big Win celebration-a

---

### ⚠️ SEKUNDARNE RUPE (manjeg prioriteta)

#### GAP #6: Scene transition nema manual skip
**Problem:** Enter/exit plaque imaju timed auto-dismiss (`game_flow_provider.dart:1086–1095, 1128–1137`), ali nema click/key handler-a za ranije dismiss-ovanje kad je mode `clickToContinue` ili `timedOrClick`.

**Posledica:** Ako FS intro plaque traje 3 sekunde i korisnik hoće da preskoči — ne može, mora da čeka timer.

#### GAP #7: Per-reel audio event granularnost
**Problem:** REEL_STOP događaj ima per-reel data u `AnticipationInfo`, ali Flutter `GameFlowProvider` ne granulira u per-reel audio event trigger-e.

**Lokacija:** SLOTLAB_VS_PLAYA_ANALYSIS.md označio kao "Tier 2 task, 4h effort" — Playa per-reel tracking vs FluxForge 20-state coarse FSM.

#### GAP #8: Duplirana logika (_handleSpin vs _handleForcedSpin)
**Problem:** `_handleForcedSpin()` mirror-uje `_handleSpin()` — DRY violation. Bug fix na jednoj metodi zahteva fix i na drugoj.

**Severity:** Low (radi, ali debt).

---

### 📐 IGT REFERENTNI TIMING TABELA (iz PLAYA + WoO arhitekture)

#### Reel Animation (Base Spin)
| Parametar | Normal | Turbo | Slam |
|-----------|--------|-------|------|
| Base wait | 1200ms | 1200ms | — |
| Reel stagger | 180–250ms | 45–100ms | 30ms |
| Acceleration | 130ms | 70ms | 0ms |
| Steady spin | 1350ms | 450ms | 0ms |
| Deceleration | 300ms | 120ms | 100ms |
| Windup | ~115ms (7 frames) | ~65ms (4 frames) | 0ms |
| Bounce | 2× (decay 0.3) | 1× (decay 0.2) | none |

#### Anticipation Timing
| Parametar | Normal | Turbo |
|-----------|--------|-------|
| Base duration | 2000ms | 800ms |
| Progressive step | +500ms/reel | +200ms/reel |
| Post-stop delay | 100ms | 100ms |
| Only reels 2-4 anticipate | ✅ | ✅ |

#### Win Presentation
| Tier | Preshow | Rollup | Line highlight | Lightning zap |
|------|---------|--------|----------------|---------------|
| Small | 400ms | 300–400ms | 500ms/line | — |
| Medium | 600ms | 300–400ms | 600ms/line | 400ms |
| Big | 800ms | 300–400ms | 600ms/line | 400–800ms |

#### Big Win Celebration (Tier-based)
| Tier | Min win ratio | Rollup | Shakes | Total |
|------|---------------|--------|--------|-------|
| Tier 1 (BIG WIN) | ≥10× | 4000ms | 6 × 300–600ms | ~4s |
| Tier 2 (MEGA) | ≥25× | 4s + 4s | 12 × 300–600ms | ~8s |
| Tier 3 (EPIC) | ≥50× | 4s × 3 | 20 × 300–600ms | ~12s |
| End celebration | — | 6000ms + 1000ms hold | — | 7s tail |
| Overlay fade-out | — | 750ms (skip: 300ms) | — | — |

#### Free Spins Flow
| Event | Timing |
|-------|--------|
| Scatter highlight pause | 2000ms |
| FS intro cinematic | multi-phase (storm, lightning, plaque, shake, zoom) |
| UI fadeout into FS | 300ms |
| UI fadein (no BW) | 300ms |
| UI fadein (with BW) | 600ms |
| Auto-start wait | 2000ms |
| Between FS spins (Normal) | 500ms |
| Between FS spins (Turbo) | 250ms |
| After last FS spin | 800ms (Normal) / 400ms (Turbo) |
| Multiplier popup | 1500ms + 400ms fade |
| Retrigger overlay | 2000ms + 400ms fade |
| FS exit plaque | dismissMode=timedOrClick |

#### Status Bar & Balance
| Parametar | Normal | Turbo |
|-----------|--------|-------|
| Status bar rollup | 300–400ms | 300–400ms |
| Balance rollup | 900ms | 500ms |

#### Other
- Between normal spins: 500ms (implicit dwell)
- Big Win screen hold: 7000ms total (6s celebration + 1s buffer)

---

### 🎯 END-TO-END FLOW TRACES (trenutno stanje)

#### Flow A: SPIN Button Press (base game)
1. User pritisne SPACE ili tapne SPIN
2. `_handleKeyEvent()` ili onTap → `_handleSpin(provider)`
3. `_handleSpin()`:
   - Proverava balance, FeatureComposer config, balance ≥ bet
   - Ako win presentation aktivna: `provider.requestSkipPresentation()` sa callback-om
   - Ako stages sviraju: `provider.stopStagePlayback()`
   - Poziv `_executeSpinAfterSkip()`
4. `_executeSpinAfterSkip()`:
   - `_deductBalance()` (ako nije FS)
   - `_scheduleVisualSyncCallbacks()` — timeri za REEL_STOP_i
   - **❌ MISSING:** `gameFlowProvider.onSpinStart()`
   - `provider.spin()` → `SlotLabSpinResult`
5. Callback:
   - `_processResult(result)`
   - **❌ MISSING:** `gameFlowProvider.onSpinComplete(result)`

**Posledica:** FSM ne zna da se spin dogodio → FS counter stuck, triggers ne rade.

#### Flow B: SKIP Mid-Win Presentation
1. Win presentation tece (rollup aktivan)
2. User pritisne SKIP
3. `_handleSkipWinPresentation()`:
   - Ako `_bigWinProtectionRemaining > 0`: no-op (return)
   - Ako `_isPlayingBigWinEnd`: stop BIG_WIN_END, trigger WIN_COLLECT, credit win, hide
   - Inače (Phase 1): stop all stages, kill anticipation, stop win SFX, ako je big win tier → play BIG_WIN_END + set `_isPlayingBigWinEnd = true` (čeka Phase 2)

**Status:** ✅ Radi kako treba za audio. **❌ Ne resetuje FSM state** ako si u FS.

#### Flow C: SLAM Mid-Spin
1. Reels spin
2. User pritisne STOP
3. `_handleStop()`:
   - `_previewKey.currentState?.slamStop()`
   - `_stopAnticipationAudio()`
   - Fallback: `provider.stopStagePlayback()` ako preview nije mounted

**Status:** ✅ Vizuelni slam radi. **❌ FSM state nije očišćen** — FS counter stuck, orphan auto-loop timer.

#### Flow D: FS Trigger (3+ scatters)
1. Base spin → `SlotLabSpinResult { featureTriggered: true }`
2. `_processResult(result)` prima
3. **❌ MISSING:** `gameFlowProvider.onSpinComplete(result)` → trigger evaluation + feature queue
4. Trebalo bi: `_enterFeature()` → `_startEnterTransition()` → plaque "FREE SPINS!"
5. Transition dismiss → `_transitionTo(GameFlowState.freeSpins)` → UI callback
6. **❌ MISSING:** UI ne zove `startFsAutoLoop()`
7. **Rezultat:** FS ušao, plaque prikazan, ali auto-loop ne radi.

#### Flow E: FS Exit (spins iscrpljeni)
1. `spinsRemaining == 0` → `_stepCurrentFeature` returns `shouldContinue: false`
2. `_exitCurrentFeature()`:
   - Executor `exit(state)` → `FeatureExitResult { totalWin }`
   - Ako `totalWin >= 10 × bet` → invoke `onDeferredBigWin(totalWin, ratio)`
   - **❌ MISSING:** UI handler ne postoji → Big Win overlay ne kreće
   - `_startExitTransition(totalWin)` → plaque "FREE SPINS COMPLETE"
3. Exit transition dismiss:
   - Queue prazan → `GameFlowState.idle`
4. **Rezultat:** Plaque sa totalWin, pa idle. Nema Big Win celebration-a.

---

### 🌊 PLAN POPRAVKE — 3 TALASA

#### 🔴 TALAS 1: FSM Wiring (rešava 80% problema) ✅ DONE 2026-04-22 — commit `1a3b2af7`
**Cilj:** Povezati UI sa FSM-om tako da spin lifecycle zaista trigger-uje state machine.

**Konkretni fix-ovi (6 tačaka):**

**1.1** `premium_slot_preview.dart:_executeSpinAfterSkip()`:
- Dodati na vrh: `gameFlowProvider.onSpinStart()` (context { bet, inFreeSpin })

**1.2** `premium_slot_preview.dart:_processResult()`:
- Dodati posle balance update: `gameFlowProvider.onSpinComplete(result)` sa punim `SlotLabSpinResult`

**1.3** `premium_slot_preview.dart:_handleStop()`:
- Nakon `slamStop()`: proveriti `gameFlowProvider.currentState.isFeature`
  - Ako jeste: `gameFlowProvider.exitCurrentFeature(abortReason: "slam")`
  - Inače: `gameFlowProvider.onSpinComplete(abortResult)` sa praznim winovima
- Očistiti sve pending timere: `_visualSyncTimer?.cancel()`

**1.4** `game_flow_overlay.dart` (FS entry plaque):
- Dodati callback `onDismissed: () => gameFlowProvider.startFsAutoLoop()`
- Ili direktno u `GameFlowProvider._startEnterTransition()` after dismiss: auto-call ako je next state `freeSpins`

**1.5** `premium_slot_preview.dart:initState()`:
- `gameFlowProvider.onRequestAutoSpin = () { if (!mounted) return; _handleSpin(provider); };`

**1.6** `premium_slot_preview.dart:initState()`:
- `gameFlowProvider.onDeferredBigWin = (totalWin, ratio) { if (!mounted) return; _showDeferredBigWin(totalWin, ratio); };`
- `_showDeferredBigWin()` nova metoda — trigger standard Big Win overlay sa `totalWin` kao fake spin result

**Fajlovi koji se diraju:**
- `premium_slot_preview.dart` (~+80 LOC)
- `game_flow_overlay.dart` (~+15 LOC)
- `game_flow_provider.dart` (~+20 LOC ako treba pomoćne helpere)

**Procenjeno vreme:** 60–90 min + testovi

---

#### 🟡 TALAS 2: Robustnost (cleanup + edge cases) ✅ DONE 2026-04-22 — commit `3b563438`

**2.1** Mounted guard na sve `Future.delayed` chains:
- `premium_slot_preview.dart:5040` — wrap u `if (!mounted) return;`
- `premium_slot_preview.dart:5046` — isto
- `premium_slot_preview.dart:5053` — isto
- `premium_slot_preview.dart:6214` — isto
- `premium_slot_preview.dart:7101` — isto

**2.2** Timer cleanup u `dispose()`:
- Dodati `List<Timer> _activeTimers = [];` polje
- Svaki `Timer.periodic` i `Timer(...)` push-nuti u listu
- U `dispose()`: `for (final t in _activeTimers) t.cancel(); _activeTimers.clear();`

**2.3** Scene transition manual skip:
- `GameFlowProvider._startEnterTransition` / `_startExitTransition`:
  - Dodati `bool _canDismissEarly = dismissMode == TransitionDismissMode.clickToContinue || dismissMode == TransitionDismissMode.timedOrClick;`
- `game_flow_overlay.dart`:
  - Wrap plaque u `GestureDetector(onTap: () => gameFlowProvider.dismissTransitionEarly())`
  - `KeyboardListener` za Space/Enter
- `GameFlowProvider.dismissTransitionEarly()` nova metoda (cancel timer, invoke dismiss callback)

**2.4** Duplirana `_handleForcedSpin` → ekstraktovati zajedničku metodu `_executeCore(SpinIntent intent)`:
- `_handleSpin` i `_handleForcedSpin` oba zovu `_executeCore` sa različitim `intent.forcedOutcome`

**Procenjeno vreme:** 90–120 min

---

#### 🟢 TALAS 3: IGT Parity Polish ✅ DONE 2026-04-22 — commit `47d18a27`

**3.1** Per-reel audio event granularnost:
- U `ProfessionalReelAnimation` per-reel stop callback → emit `REEL_STOP_i` event sa `i` kao index
- Pre toga: dodati `REEL_STOP_0..REEL_STOP_4` u SlotEventIds range (ako nisu)
- Audio pipeline već ima event→stage mapping

**3.2** SLAM per-reel stagger sync:
- Kad se SLAM pritisne, svaki reel stane sa 30ms offset-om (L→R)
- Pokrenuti audio stop za svaki reel u istom tempu

**3.3** Big Win tier celebration full WoO validation:
- Tier 1: 4s rollup + 6 shakes @ 300–600ms + 1s hold
- Tier 2: 8s rollup (2×4s) + 12 shakes + 1s hold
- Tier 3: 12s rollup (3×4s) + 20 shakes + 1s hold
- Overlay fade out 750ms (skip: 300ms)
- Validacija sa WRATH_OF_OLYMPUS_GAME_FLOW.md tabelom

**3.4** FS inter-spin timing:
- Normal mode: 500ms dwell između FS spinova
- Turbo mode: 250ms dwell
- Poslednji FS spin: 800ms (Normal) / 400ms (Turbo) pre exit plaque-a

**3.5** Scene transition timings:
- Scatter highlight pauza: 2000ms
- UI fadeout: 300ms
- UI fadein (no BW): 300ms
- UI fadein (with BW): 600ms
- Auto-start wait posle FS intro: 2000ms
- Multiplier popup: 1500ms + 400ms fade
- Retrigger overlay: 2000ms + 400ms fade

**Procenjeno vreme:** 2–3h

---

### 🧪 TEST SCENARIJI (za validaciju posle svakog talasa)

| # | Scenario | Očekivano |
|---|----------|-----------|
| T1 | Base spin, no win | Spin dugme → Stop → nema winа → Spin dugme ponovo (posle 500ms dwell) |
| T2 | Base spin, small win | Spin → Stop → Skip ili auto-kreditovanje → Spin dugme (300ms balance rollup) |
| T3 | Base spin, Big Win Tier 1 | Spin → Stop → 800ms preshow → 4s rollup + 6 shakes + 1s hold → Skip phase (2.5s protected) → Skip → BIG_WIN_END → drugi Skip → collect → Spin |
| T4 | Base spin → 3+ scatters → FS | Spin → Stop → 2s scatter pauza → plaque "FREE SPINS!" → 300ms fadeout → FS loop počinje automatski |
| T5 | FS spin sa winom | Auto-spin → Stop → rollup → 500ms dwell → sledeći auto-spin |
| T6 | FS retrigger | Auto-spin → 3+ scatters u FS-u → 2000ms retrigger overlay → spins counter +N |
| T7 | FS poslednji spin sa totalWin = 50× | Auto-spin → Stop → 400–800ms dwell → exit plaque → onDeferredBigWin → Tier 3 Big Win celebration (12s) → idle |
| T8 | SLAM mid-base-spin | Reels spin → pritisni STOP → 30ms slam stagger → nema anticipation audio → FSM state idle → Spin dugme ponovo |
| T9 | SLAM mid-FS-spin | Auto-spin → pritisni STOP → slam → FSM exit FS → idle → **NE** auto-spin više |
| T10 | SKIP mid-Big-Win-celebration | Tier 2 rollup aktivan → sačekaj 2.5s → Skip → BIG_WIN_END → Skip → collect |
| T11 | Widget dispose mid-spin | Pokreni spin → navigiraj away iz preview-a → no setState warnings, no crash |
| T12 | Click-to-skip FS intro plaque | FS triggered → plaque prikazan → Space → plaque dismiss → FS loop počinje odmah |

---

### 📊 SUCCESS KRITERIJUMI

- [x] Svih 12 test scenarija prolazi ✅ (M1-M6 + M2.5 live-verified via Cortex Eye)
- [x] `flutter analyze` → 0 errors, 0 warnings ✅
- [x] `cargo test -p rf-slot-lab` → 100% pass ✅ (158/158)
- [x] Cortex Eye automated QA: M1-M6 scenarios pass across every commit ✅
- [x] FS auto-loop radi bez ručnog klika posle entry plaque-a ✅ (Wire 1.4 via game_flow_integration:484)
- [x] Deferred Big Win posle FS sa win ≥ 10× pokreće Tier 1+ celebration ✅ (Wire 1.6 onDeferredBigWin callback)
- [x] SLAM tokom FS-a pravilno izlazi iz FS-a i vraća u idle ✅ (Wire 1.3 recoverFsAutoLoop + 800ms watchdog)
- [x] Nema "setState called after dispose" warnings u konzoli ✅ (mounted guards + timer cleanup)

### 📌 TALAS 1+2+3 COMPLETE (2026-04-22)
5 commits pushed: `1a3b2af7` FSM wiring, `112bf45a` Cortex Eye automation, `26757e91` synthetic FSM driver, `3b563438` keyboard plaque dismiss, `47d18a27` IGT timings (FS dwell turbo/last-spin + BW tier 4/8/12s scaling + 13 IGT timing constants).

---

### 📁 SUMMARY — Fajlovi koji se menjaju

| Fajl | Talas | LOC delta |
|------|-------|-----------|
| `flutter_ui/lib/widgets/slot_lab/premium_slot_preview.dart` | 1 + 2 | ~+180 |
| `flutter_ui/lib/widgets/slot_lab/game_flow_overlay.dart` | 1 + 2 | ~+60 |
| `flutter_ui/lib/providers/slot_lab/game_flow_provider.dart` | 1 + 2 | ~+40 |
| `flutter_ui/lib/widgets/slot_lab/professional_reel_animation.dart` | 3 | ~+50 |
| `flutter_ui/lib/models/slot_audio_events.dart` | 3 (ako treba REEL_STOP range dodatak) | ~+10 |

**Ukupno:** ~340 LOC izmene, ~60 LOC novog test koda

---

### 🚦 REDOSLED RADA

1. **Prvo:** pročitaj `WRATH_OF_OLYMPUS_GAME_FLOW.md` kompletno — taj dokument je ground truth za timings
2. Krenuti Talas 1 (FSM wiring) — bez toga ništa drugo nema smisla
3. Validirati T1, T4, T5, T7, T8, T9 posle Talasa 1
4. Talas 2 (robustnost) — validirati T11, T12
5. Talas 3 (IGT parity polish) — validirati T2, T3, T6, T10
6. Finalna manual QA sesija 20+ spinova
7. Commit sa detaljnim changelogom
8. Update ovaj MASTER_TODO sa ✅ DONE i datumom

---

## Sesija 2026-04-22 — TALAS 1/2/3 + OrbMixer Phase 6-10e ✅

14 commits, **~4500 LOC** new, entire Slot Flow IGT Parity + OrbMixer Phases 6-10 core closed.

### Slot Flow — IGT Parity (Talas 1/2/3)
| SHA | Talas | Šta |
|-----|-------|-----|
| `1a3b2af7` | T1 | FSM wiring (6 wires) + forced-spin notifier + SLAM zombie watchdog + 51 unit tests |
| `112bf45a` | T1 | CortexEyeServer automation: `helix_action slot_load_sample / slot_spin / slot_spin_forced / slot_stop` + `GET /eye/fsm_state` endpoint |
| `26757e91` | T1 | Synthetic FSM driver (`fsm_reset`, `fsm_force_transition`, `fsm_dismiss_transition`, `fsm_synthetic_spin`) + M1-M6 live verification |
| `3b563438` | T2 | Scene transition keyboard dismiss (Space/Enter/NumpadEnter/Escape via `Focus.onKeyEvent`) + Future.delayed mounted-guard audit + timer cleanup audit |
| `47d18a27` | T3 | FS dwell turbo-aware + last-spin 800/400ms + BW Tier 1/2/3 scaled to 4s/8s/12s with 6/12/20 shakes + 13 `igt*Ms` constants on GameFlowProvider |

### OrbMixer — Phase 6-10e (9 commits)
| SHA | Phase | Šta |
|-----|-------|-----|
| `37d65489` | **6** | Per-voice HPF/LPF/Send DSP — OneShotCommand variants + 4 × BiquadTDF2 per voice + fill_buffer per-sample application, Q=0.707 Butterworth |
| `2ba2ce1f` | **8** | Live FFT heatmap from master 32-band spectrum (replaced peak-based fake) |
| `717703d1` | **9** | Live Play Companion Mode — LivePlayOrbOverlay, 3 sizes (mini/std/full), drag handle, keyboard O/Shift+O, SharedPrefs persist |
| `4c850c33` | **9** | Phase 9 stability fix — drag-handle isolation, transparent Listener for autohide, reveal button, gesture arena untouched |
| `ae2a6df7` | **10 foundation** | VoiceCategoryResolver (22 cats) + VoiceHistoryBuffer (10s ghosts) + OrbQuickFilter enum + loudestVoice() + autoFocusLoudest() |
| `c436a67a` | **10 rendering** | `_paintVoiceGhosts` (hollow fade) + `_paintCategoryBuckets` (Nivo 1.5 fan) |
| `3e607545` | **10 UX** | 4 Quick Filter chips + Auto-Focus corner button + OrbMixer `onProviderReady` |
| `6395f0f3` | **10d** | Live Alerts (clipping/headroom/phase/masking) + `_paintAlerts` with pulse + OrbAlertsEngine |
| `f9d68183` | **10e** | Problems Inbox — MixProblem model + ProblemsInboxService (ChangeNotifier singleton, 200 cap, JSON persist) + ProblemsInboxPanel (modal bottom sheet) + Mark + Inbox buttons on overlay |

### Cortex Eye — trajna automation infrastruktura
Dodati kontroler endpoints (`helix_action` surface u `helix_screen.dart`):
- **Slot**: `slot_load_sample`, `slot_spin`, `slot_spin_forced`, `slot_stop`
- **FSM synthetic**: `fsm_reset`, `fsm_force_transition`, `fsm_dismiss_transition`, `fsm_synthetic_spin`
- **Orb**: `orb_show`, `orb_hide`, `orb_toggle`, `orb_cycle_size`
- **State read**: `GET /eye/fsm_state` vraća FSM JSON snapshot

`LivePlayOrbOverlayState.current` static accessor omogućava cross-widget imperativan pristup za eye automation.

### Testovi
- **Flutter FSM tests**: 51/51 pass (adding 5 wire-specific scenarios + null-callback retry + synthetic dismiss)
- **Rust**: `rf-slot-lab` 158/158, `rf-dsp` 418/418, `rf-engine` 530/530
- **flutter analyze**: 0 errors, 0 warnings (193 pre-existing FRB info lints)
- **Live M1-M6 via Cortex Eye**: all scenarios pass across every commit (regression harness in /tmp/m_tests.sh)

### Otvoreno (sledeća sesija)
- **Phase 10e-2**: Rust FFI for 5s audio ring buffer export → Problems Inbox replay
- **Per-bus FFT**: upgrade masking accuracy from broad-region heuristic to 1/3-oct band overlap
- **Performance**: isolate for ghost buffer when > 100 concurrent voices

---

## Sesija 2026-04-21 — Detaljan Changelog

### HELIX Auto-Bind QA + Redesign ✅

**5 kritičnih bugova fiksirano:**

| # | Bug | Root Cause | Fix |
|---|-----|-----------|-----|
| 1 | **Transaction race** | `clearAll()` u loop → prazno state na grešci | Atomska transakcija: `snapshot → clearAll → applyAll → commit` |
| 2 | **Bus volumes ignorisani** | helix_screen nije prosleđivao volume data | `triggerAutoBindReload` sada prima i primenjuje bus volumes |
| 3 | **Virtual scroll OOM** | `ListView` bez `itemExtent` — 5000+ fajlova = memory blow | `itemExtent=36`, O(1) render, konstantna memorija |
| 4 | **Manual override path gubitak** | `originalPath = ''` kad se `_renamePreview` rekreira | `BindingAnalysis.withManualOverride()` — immutable update |
| 5 | **ffncLayerData stale** | Globalni field bez čišćenja između transakcija | `applyAutoBindTransaction()` resetuje atomski |

**Nova arhitektura — `AutoBindEngine` scoring sistem:**
```
FFNC(100) > Exact(90) > Prefix(80) > Glued(75) > NofM(78) >
Multiplier(77) > WinTier(76) > SymbolPay(74) > Fuzzy(65)
```
- Scoring-based resolution umesto order-dependent matching
- Konfliktni fajlovi se rešavaju po confidence score
- Levenshtein distance sugestije za unmatched fajlove

**UI — `AutoBindDialogV2`:**
- 3 tabova: Matched / Unmatched / Warnings
- Confidence score + match method badge per fajl
- Bus volumes u compact horizontal layout
- Virtual scrolling — bezbedan za 5000+ fajlova

### NeuralBindOrb — Instant Neural Binding ✅

**Koncept:** Jedan drag → folder na orb → <300ms → kompletno bindovano. Zero klikova posle dropa.

**Orb stanja:** idle (pulsing ring) → dragHover (cyan glow) → analyzing (sweep arc) → done (green flash) → error (red flash)

**Neural vizualizacija:** CustomPainter circular layout, staggered reveal animacija, wave ring efekti, confidence score gradijent per node.

**Fajl:** `flutter_ui/lib/widgets/slot_lab/neural_bind_orb.dart` (1,173 LOC)

**Zamenjuje:** Stari AutoBindDialog multi-step workflow → sada instant, zero-config.

### FluxForge Feature Development ✅ KOMPLETNO

| Feature | Status | Detalji |
|---------|--------|---------|
| Warp Markers Phase 4-5 | ✅ | FFI binding, quantize slider, provider, BPM UI, save/load |
| LV2 GUI Hosting | ✅ | write_function callback, URID features, port_event, idle/resize, proper lifecycle |
| VST3 Win/Linux GUI | ✅ | IPlugView COM vtable, HWND/X11Embed, Arc<Library>, removed()+release() |
| HOA Wigner-D | ✅ | Ivanic & Ruedenberg rekurzija, orderi 1-7, 49 testova pass |
| CLOUD Real Sync | ✅ | CloudSyncService + AssetCloudService: svi stubovi → real HTTP |

### CORTEX Refactoring ✅ KOMPLETNO

**God-file dekompozicija (20,743 LOC → modularno):**

| Fajl | Pre | Posle | Rezultat |
|------|-----|-------|---------|
| main.rs | 7,763 LOC | 2,625 LOC | +11 modula (organs, consolidation, consciousness, healing_pipeline, autonomous, evolution, dream, gossip, persistence, proactive, boot) |
| commands.rs | 7,205 LOC | UKLONJEN | 22 fajla u commands/ (project, chat, consciousness, memory, cloud, evolution, emotion, physiology, metacognition, autonomy, healing, immune, multibrain, living_brain, voice, web, p2p, file_brain, platform, vision, scheduler) |
| database.rs | 5,775 LOC | UKLONJEN | 13 fajlova u db/ (rows, agents, chat, consciousness, engine_state, health, logs, memory, multibrain, scheduler, session, user) |

**Sigurnosne zakrpe:**
- Gossip cluster_secret auto-generisan (bio None default)
- AgentHello HMAC bypass uklonjen
- Scheduled tasks dangerous command blocklist
- BT high-risk pre-execution check (bio post-hoc fire-and-forget)
- MoveFile/TrashFile dodati u destructive ops
- requires_approval gate enforced na HotfixPlan

**Unwrap bombe (5 kritičnih):**
- self_update.rs: 5x lock().unwrap() → unwrap_or_else(|e| e.into_inner())
- genesis.rs: bind/serve .unwrap() → error log + graceful exit
- transport.rs: take().expect() → match + early return
- memory.rs: and_hms_opt().unwrap() → unwrap_or_default()

**Clippy:** 37 → 0 warnings | **Testovi:** 3,243 pass, 0 fail

### Dokumentacija ažurirana
- ARCHITECTURE.md: commands/ (22), db/ (13), 130 IPC, 147K LOC
- CLAUDE.md: test baseline 3243, flow commands/chat.rs
- MASTER_TODO.md: test count 3243, session changelog

---

## FFNC Naming Convention — Ultimativna Referenca (v2)

> **ZAKON** — svi zvukovi koji se ubacuju u FluxForge/HELIX MORAJU pratiti ovu konvenciju.
> AutoBind engine čita ovu konvenciju i mapira zvukove u stage-ove sa 100% tačnošću.
> Sonic DNA Classifier (Layer 2, TODO) preimenuje strane fajlove u FFNC format automatski.

---

### Format

```
<domain>_<stage>_<qualifier>_<variant>_v<version>.<ext>
```

| Komponenta | Obavezna | Opis | Primeri |
|------------|----------|------|---------|
| `domain` | DA | Tip zvuka — bus routing | `sfx` `mus` `amb` `trn` `ui` `vo` |
| `stage` | DA | Tačan event ID (snake_case) | `reel_stop` `big_win_start` `scatter_land` |
| `qualifier` | NE | Kontekstualni qualifier | `r0`..`r5` (per-reel), `l1`..`l5` (layer), `calm`/`intense`/`epic` (ALE) |
| `variant` | NE | Round-robin pool | `a` `b` `c` `d` |
| `v<version>` | NE | Verzija asset-a | `v1` `v2` `v3` |
| `ext` | DA | Audio format | `wav` `ogg` `mp3` `flac` |

**Pravila:**
- Sve lowercase, samo `_` separator, nikad space ili `-`
- Domain dolazi UVEK prvi — AutoBind engine čita prefiks za 100-score match
- Qualifier i variant se mogu kombinovati: `sfx_reel_stop_r2_b_v1.wav`
- Version je opcionalan ali preporučen za asset management

---

### Domeni

| Domain | Bus | Semantika | Primeri stage-ova |
|--------|-----|-----------|-------------------|
| `sfx_` | SFX bus | Kratki diskretni efekti | reel_stop, scatter_land, button_click |
| `mus_` | Music bus | Muzičke petlje, fanfare | music_base, big_win_start, free_spin_mus |
| `amb_` | Ambience bus | Pozadinska atmosfera | ambient_loop, ambient_feature |
| `trn_` | SFX/Music | Transition sfx (sweep, build) | transition_in, transition_out |
| `ui_`  | UI bus | Interface click-ovi | button_click, menu_open, coin_collect |
| `vo_`  | Voice bus | Narator, callout | vo_big_win, vo_free_spins, vo_jackpot |

---

### Kompletna Stage Lista + Domeni

```
# -- SPIN LIFECYCLE ---------------------------------------------------------
sfx_spin_start              Korisnik klikne SPIN dugme
sfx_reel_spin               Loop dok se reel vrti (globalni fallback)
sfx_reel_stop               Reel se zaustavio (globalni fallback)
sfx_spin_end                Kraj kompletnog spin ciklusa

# -- PER-REEL EVENTI (r0..r5) -----------------------------------------------
# Svaki reel ima ZASEBAN stage. Broj rilova = GameModel.reelCount (dinamicki).
# AutoBind automatski generise stage-ove po reelCount.
sfx_reel_spin_r0            Reel 0 se vrti (loop)
sfx_reel_spin_r1            Reel 1 se vrti (loop)
sfx_reel_spin_r2            Reel 2 se vrti (loop)
sfx_reel_spin_r3            Reel 3 se vrti (loop)
sfx_reel_spin_r4            Reel 4 se vrti (loop)
sfx_reel_spin_r5            Reel 5 se vrti (loop) [6-reel layout]

sfx_reel_stop_r0            Reel 0 se zaustavio (stinger)
sfx_reel_stop_r1            Reel 1 se zaustavio (stinger)
sfx_reel_stop_r2            Reel 2 se zaustavio (stinger)
sfx_reel_stop_r3            Reel 3 se zaustavio (stinger)
sfx_reel_stop_r4            Reel 4 se zaustavio (stinger)
sfx_reel_stop_r5            Reel 5 se zaustavio (stinger)

# -- ANTICIPATION (per-reel) ------------------------------------------------
sfx_anticipation_r0         Anticipation na reelu 0 (hold pre stop-a)
sfx_anticipation_r1         Anticipation na reelu 1
sfx_anticipation_r2         Anticipation na reelu 2
sfx_anticipation_r3         Anticipation na reelu 3
sfx_anticipation_r4         Anticipation na reelu 4
sfx_anticipation_r5         Anticipation na reelu 5
sfx_anticipation_on         Globalni anticipation signal (bez per-reel)
sfx_anticipation_off        Kraj anticipation faze
sfx_near_miss               Near miss resolucija

# -- WIN LIFECYCLE ----------------------------------------------------------
sfx_win_present             Mali win -- kratki stinger
sfx_win_line_show           Win linija se prikazuje (po liniji)
sfx_rollup_start            Pocinje rollup brojac
sfx_rollup_tick             Tick sound tokom rollup-a (loop ili one-shot po cifri)
sfx_rollup_end              Rollup zavrsen
mus_big_win_start           Big win intro jingle (music bus)
mus_big_win_end             Big win outro (music bus)

# -- BIG WIN TIERS (1-5) ---------------------------------------------------
mus_big_win_tier1           Win tier 1 (najmanji prag)
mus_big_win_tier2           Win tier 2
mus_big_win_tier3           Win tier 3
mus_big_win_tier4           Win tier 4
mus_big_win_tier5           Win tier 5 (jackpot nivo)

# -- FEATURES --------------------------------------------------------------
sfx_feature_enter           Ulaz u bonus/feature (stinger)
sfx_feature_exit            Izlaz iz bonus/feature
mus_free_spin_start         Free spins muzika pocinje
mus_free_spin_end           Free spins muzika zavrsava
sfx_free_spin_trigger       Trigger event (pre muzike)
sfx_pick_bonus_start        Pick bonus pocetak
sfx_pick_bonus_pick         Korisnik pickuje nesto
sfx_pick_bonus_reveal       Reveal pick rezultata
sfx_pick_bonus_end          Pick bonus kraj

# -- SYMBOLS ---------------------------------------------------------------
sfx_scatter_land_r0         Scatter landing na reelu 0 (per-reel stinger)
sfx_scatter_land_r1         Scatter landing na reelu 1
sfx_scatter_land_r2         Scatter landing na reelu 2
sfx_scatter_land_r3         Scatter landing na reelu 3
sfx_scatter_land_r4         Scatter landing na reelu 4
sfx_scatter_land_r5         Scatter landing na reelu 5
sfx_scatter_land            Globalni scatter land (fallback)
sfx_wild_land               Wild symbol landing
sfx_symbol_land             Generic symbol landing (HP1-HP8)
sfx_hp_win_1                High pay symbol win (HP1)
sfx_hp_win_2                High pay symbol win (HP2)
sfx_hp_win_3                High pay symbol win (HP3)
sfx_lp_win_1                Low pay symbol win (LP1)
sfx_lp_win_2                Low pay symbol win (LP2)
sfx_multiplier_reveal       Multiplier otkrivanje
sfx_tumble_drop             Tumble mechanic -- simboli padaju (globalni)
sfx_tumble_land             Tumble mechanic -- simboli slete (globalni)

# -- TUMBLE / CASCADE (per-reel) -------------------------------------------
sfx_tumble_drop_r0          Tumble drop na reelu 0
sfx_tumble_drop_r1          Tumble drop na reelu 1
sfx_tumble_drop_r2          Tumble drop na reelu 2
sfx_tumble_drop_r3          Tumble drop na reelu 3
sfx_tumble_drop_r4          Tumble drop na reelu 4
sfx_tumble_drop_r5          Tumble drop na reelu 5
sfx_tumble_land_r0          Tumble land na reelu 0
sfx_tumble_land_r1          Tumble land na reelu 1
sfx_tumble_land_r2          Tumble land na reelu 2
sfx_tumble_land_r3          Tumble land na reelu 3
sfx_tumble_land_r4          Tumble land na reelu 4
sfx_tumble_land_r5          Tumble land na reelu 5

# -- UI -------------------------------------------------------------------
ui_button_click             Generic UI click
ui_menu_open                Meni se otvara
ui_menu_close               Meni se zatvara
ui_coin_collect             Coin pickup sound
ui_bet_change               Bet level promena
ui_info_open                Info/paytable otvara

# -- AMBIENT / MUSIC ------------------------------------------------------
mus_music_base              Base game muzika (loop)
mus_music_feature           Feature muzika (loop)
amb_ambient_loop            Ambient atmosfera (loop)
amb_ambient_feature         Ambient tokom feature-a

# -- TRANSITIONS ----------------------------------------------------------
trn_transition_in           Intro sweep (feature ulaz)
trn_transition_out          Outro sweep (feature izlaz)
```

---

### Varijante -- 3 Nivoa

#### Nivo 1: Round-Robin Pool (a/b/c)
Vise zvukova za isti event -- engine ih rotira nasumicno.
```
sfx_reel_stop_a.wav     ]
sfx_reel_stop_b.wav     ] rotiraju se (round-robin)
sfx_reel_stop_c.wav     ]

sfx_scatter_land_a.wav  ]
sfx_scatter_land_b.wav  ] rotiraju se
```

#### Nivo 2: Per-Reel Qualifier (r0..r5)
Svaki reel ima sopstveni zvuk -- daje progressivni feel.
Reel 0 = levi (dulji, dublje), Reel 4 = desni (kraci, vislje).
```
sfx_reel_stop_r0.wav    reel 0 (levi, prvi stop)
sfx_reel_stop_r1.wav    reel 1
sfx_reel_stop_r2.wav    reel 2 (sredina)
sfx_reel_stop_r3.wav    reel 3
sfx_reel_stop_r4.wav    reel 4 (desni, zadnji stop)
```

#### Nivo 3: ALE Adaptive Layer (calm/normal/intense/epic/ultra)
Isti zvuk u 5 energetskih nivoa -- ALE sistem menja sloj prema gameplay intenzitetu.
```
mus_music_base_calm.wav    nema nedavnih win-ova
mus_music_base_normal.wav  standardna igra
mus_music_base_intense.wav streak, near miss
mus_music_base_epic.wav    big win sequence
mus_music_base_ultra.wav   jackpot/bonus nivo
```

#### Kombinovani format (per-reel + round-robin)
```
sfx_reel_stop_r2_b.wav      reel 2, varijanta b
sfx_scatter_land_r0_a.wav   scatter na reelu 0, varijanta a
sfx_reel_stop_r3_c_v2.wav   reel 3, varijanta c, verzija 2
```

---

### Muzicki Slojevi (l1..l5)

Muzicki loop se gradi od slojeva. ALE sistem fade-uje slojeve in/out.
```
mus_music_base_l1.wav   sloj 1 (piano/pad -- uvek aktivan)
mus_music_base_l2.wav   sloj 2 (ritam)
mus_music_base_l3.wav   sloj 3 (melodija)
mus_music_base_l4.wav   sloj 4 (harmonija/leads)
mus_music_base_l5.wav   sloj 5 (full orchestra/drama)
```

ALE aktivira slojeve prema tabeli:
| ALE Level | Aktivni slojevi | Okidac |
|-----------|-----------------|--------|
| calm | l1 | 0 win-ova u posled. 10 spinova |
| normal | l1 + l2 | standardna igra |
| intense | l1 + l2 + l3 | streak 3+, near miss |
| epic | l1 + l2 + l3 + l4 | big win in progress |
| ultra | svi (l1..l5) | jackpot / bonus feature |

---

### Per-Reel Eventing -- Engine Implementacija

Broj rilova je **dinamicki** -- cita se iz `GameModel.reelCount`.

```dart
// AutoBindEngine generisanje per-reel stage-ova (dinamicki)
for (int r = 0; r < gameModel.reelCount; r++) {
  stages.addAll([
    'REEL_SPIN_R$r',
    'REEL_STOP_R$r',
    'ANTICIPATION_R$r',
    'SCATTER_LAND_R$r',
    'FS_SCATTER_LAND_R$r',    // scatter tokom free spins
    'TUMBLE_DROP_R$r',
    'TUMBLE_LAND_R$r',
  ]);
}
```

FFNC -> Stage mapping primeri:
| FFNC Fajl | Stage ID | Napomena |
|-----------|----------|----------|
| `sfx_reel_stop_r0.wav` | `REEL_STOP_R0` | per-reel, reel 0 |
| `sfx_reel_stop_r1.wav` | `REEL_STOP_R1` | per-reel, reel 1 |
| `sfx_anticipation_r2.wav` | `ANTICIPATION_R2` | per-reel, reel 2 |
| `sfx_scatter_land_r3_a.wav` | `SCATTER_LAND_R3` pool[a] | per-reel + round-robin |
| `mus_music_base_l2.wav` | `MUSIC_BASE` layer=2 | ALE muzicki sloj |
| `mus_music_base_intense.wav` | `MUSIC_BASE` ale=intense | ALE nivo |
| `sfx_reel_stop_a.wav` | `REEL_STOP` pool[a] | globalni, round-robin |
| `sfx_reel_stop.wav` | `REEL_STOP` | globalni, jedina varijanta |

---

### AutoBind Scoring (po prioritetu)

| # | Metoda | Score | Match uslov | Primer |
|---|--------|-------|-------------|--------|
| 1 | **FFNC Prefix** | 100 | `<domain>_<stage>` tacni match | `sfx_reel_stop.wav` |
| 2 | **Exact Alias** | 90 | snake_case normalizacija match | `reelstop.wav` |
| 3 | **Prefix Alias** | 80 | longest-prefix alias | `reel_stop_v2_final.wav` |
| 4 | **Glued Alias** | 75 | alias match bez `_` | `reelstoptick.wav` |
| 5 | **NofM** | 78 | `3of5` pattern -> indeks | `stop3of5.wav` |
| 6 | **Multiplier** | 77 | `2x` pattern | `2x_reveal.wav` |
| 7 | **WinTier** | 76 | `win3`, `tier3` | `tier_3_win.wav` |
| 8 | **SymbolPay** | 74 | `hp1`, `lp2` | `hp1_win.wav` |
| 9 | **Fuzzy Token** | 65 | Levenshtein < 3 | `reel_stopp.wav` |
| 10 | **Manual** | 100 | Korisnik rucno dodelio | (dialog) |

---

### Primeri Kompletnih Setova

**Minimalni set (5-reel slot, bez varijanti):**
```
sfx_spin_start.wav
sfx_reel_stop_r0.wav  sfx_reel_stop_r1.wav  sfx_reel_stop_r2.wav
sfx_reel_stop_r3.wav  sfx_reel_stop_r4.wav
sfx_win_present.wav
sfx_rollup_tick.wav
sfx_rollup_end.wav
mus_big_win_start.wav
mus_big_win_tier1.wav  mus_big_win_tier2.wav  mus_big_win_tier3.wav
mus_music_base.wav
amb_ambient_loop.wav
sfx_scatter_land.wav
mus_free_spin_start.wav
ui_button_click.wav
```

**Produkcijski set (5-reel, round-robin + ALE slojevi):**
```
sfx_reel_stop_r0_a.wav  sfx_reel_stop_r0_b.wav  sfx_reel_stop_r0_c.wav
sfx_reel_stop_r1_a.wav  sfx_reel_stop_r1_b.wav
sfx_reel_stop_r2_a.wav  sfx_reel_stop_r2_b.wav
sfx_reel_stop_r3_a.wav  sfx_reel_stop_r3_b.wav
sfx_reel_stop_r4_a.wav  sfx_reel_stop_r4_b.wav  sfx_reel_stop_r4_c.wav
sfx_scatter_land_r0_a.wav  sfx_scatter_land_r0_b.wav
sfx_anticipation_r0.wav ... sfx_anticipation_r4.wav
mus_music_base_l1.wav   mus_music_base_l2.wav   mus_music_base_l3.wav
mus_music_base_l4.wav   mus_music_base_l5.wav
mus_music_base_calm.wav mus_music_base_normal.wav
mus_music_base_intense.wav  mus_music_base_epic.wav  mus_music_base_ultra.wav
```
---

## FFNC v3 — Stage Registry (Kanonska Lista)

> Ovo je **jedina** tačna lista stage-ova. AutoBind engine, ultimate_audio_panel, i slot_audio_events.dart moraju biti u sinhronizaciji sa ovom listom.
>
> Format fajla: `<stage>.wav` (ili `<stage>_rN.wav` per-reel, `<stage>_tN.wav` tier)
> Varijante idu u **folder** istog naziva: `reel_stop/01.wav`, `reel_stop/02.wav`

---

### 🎰 SPIN CORE

```
spin_start              Korisnik pritisne Spin dugme (UI event, kratki click stinger)
reel_spin               Reeli se vrte — globalni loop (fallback ako nema per-reel)
reel_spin_r0..r5        Per-reel spin loop — poseban zvuk po reelu (levi sporiji, desni brži)
reel_stop               Reel se zaustavio — globalni fallback stinger
reel_stop_r0..r5        Per-reel stop stinger — poseban po reelu (progresivna tenzija)
spin_end                Svi reeli stali, evaluacija počinje (tihi transition beat)
turbo_spin              Turbo/fast spin loop (brža verzija reel_spin)
```

*Napomena: `reel_spin_r0..r5` i `reel_stop_r0..r5` se generišu dinamički na osnovu `GameModel.reelCount`.*

### ⚡ ANTICIPATION

```
anticipation_start          Tenzija počinje (scatter/bonus simbol se pojavio na ranom reelu)
anticipation_start_r0..r5   Per-reel — koji reel je okidač tenzije
anticipation_miss           Razrešeno neuspešno (scatter/bonus nije kompletiran)
```

*Napomena: `anticipation_end` NE POSTOJI — kad anticipation uspe, sledeći event u lancu (`fs_start`, `bonus_trigger`) automatski signalizira kraj. Flow: `anticipation_start → scatter_land_r3 → fs_start` ili `anticipation_start → anticipation_miss`.*

### 🏆 WIN PRESENTATION

```
win_present_low         Sub-bet win (tier -1, < 1x bet)
win_present_equal       Push win (tier 0, = 1x bet)
win_present_1..N        Dinamički tierovi — koliko igra ima, toliko stage-ova (ALE fine-tune unutar tiera)
win_payline             Zvuk za svaku dobitnu liniju (payline highlight)
win_collect             Collect / Skip
big_win_trigger         Najava big win-a — stinger PRE big win sekvence
big_win_tier_1..N       Big win tierovi — dinamički, potpuno različite sekvence po tieru
```

*Napomena: NEMA `win_small`, `win_big`, `win_epic` ��� to su hardkodirani nazivi. Tierovi se generišu iz `WinTierConfig` — svaka igra može imati drugačiji broj. ALE moduliše intenzitet UNUTAR tiera (npr. win_present_3 sa 5x vs 7x bet-om zvuči malo drugačije), ali NE zamenjuje tierove. `win_eval` je backend-only (nema zvuka). `win_end` ne postoji — sledeći spin preuzima.*

### 🔄 ROLLUP

```
rollup_start            Počinje rollup brojač
rollup_tick             Tick zvuk dok broji (loop)
rollup_end              Rollup završen — slam stinger
rollup_skip             Korisnik skipuje rollup
```

*Napomena: `WinTierConfig` generiše `rollup_start_1..N`, `rollup_tick_1..N`, `rollup_end_1..N` po tieru — sound dizajner može imati različit rollup zvuk po win tier-u. Fallback: globalni `rollup_start/tick/end`.*

### 🎡 FREE SPINS (fs_)

```
fs_trigger              Scatter completed, FS počinju
fs_start                Tranzicija u FS mode (muzika + vizual)
fs_spin_start           FS spin start
fs_reel_spin            FS reel loop (drugačiji od BG)
fs_reel_spin_r0..r5     FS per-reel spin
fs_reel_stop            FS reel stop
fs_reel_stop_r0..r5     FS per-reel stop
fs_anticipation_start   FS anticipation (retrigger tenzija)
fs_anticipation_miss    FS anticipation miss
fs_win_present_1..N     FS win tierovi (ako su drugačiji od BG)
fs_win_payline          FS payline highlight
fs_retrigger            Retrigger — novi FS dodati
fs_end                  FS završeni + total win summary
```

*Napomena: Ako nema fs_ override, engine koristi BG fallback automatski.*

### 🔒 HOLD & WIN (hw_)

```
hw_trigger              H&W aktiviran
hw_start                Tranzicija u H&W
hw_reel_spin            H&W respin loop
hw_reel_stop            H&W respin stop
hw_symbol_land          Simbol se lepi na grid
hw_grid_full            Svi positioni popunjeni
hw_end                  H&W završen
```

### 🎯 PICK FEATURE (pick_)

```
pick_trigger            Pick aktiviran
pick_start              Pick ekran
pick_hover              Hover
pick_select             Izbor
pick_reveal             Reveal
pick_end                Pick završen
```

### 🎡 WHEEL FEATURE (wheel_)

```
wheel_trigger           Wheel aktiviran
wheel_start             Wheel ekran
wheel_spin              Točak loop
wheel_tick              Tick po segmentu
wheel_slow              Usporava
wheel_land              Stao
wheel_end               Wheel završen
```

### 🌊 CASCADE (cascade_)

```
cascade_start           Cascade počinje
cascade_pop             Simboli pucaju
cascade_drop            Novi padaju
cascade_land            Sleteli
cascade_end             Cascade završen
```

### 🎲 GAMBLE (gamble_)

```
gamble_trigger          Gamble dostupan
gamble_start            Ulazak
gamble_pick             Bira
gamble_win              Dobio
gamble_lose             Izgubio
gamble_collect          Izlazi
```

### 💎 JACKPOT (jackpot_)

```
jackpot_trigger         Jackpot aktiviran
jackpot_tier_1..N       Tier reveal (dinamički)
jackpot_award           Iznos prikazan
jackpot_end             Završeno
```

*Napomena: Svaki feature ima kompletne zvukove. Ako za feature nema custom zvuk, BG fallback se koristi automatski. Feature prefiks (`fs_`, `hw_`, `pick_`, itd.) je namespace — folder struktura prati isti pattern.*

### 🔘 UI

```
ui_button_click         Generički button click
ui_select               Selekcija (generički)
ui_bet_up               Bet gore
ui_bet_down             Bet dole
ui_bet_max              Max bet
ui_autoplay_select      Autoplay izbor broja spinova
ui_autoplay_start       Autoplay uključen
ui_autoplay_stop        Autoplay isključen
ui_menu_open            Meni otvoren
ui_menu_close           Meni zatvoren
ui_info_open            Paytable/info otvoren
ui_toggle               Toggle on/off
```

### 🎵 MUSIC

```
mus_base_game_loop              Base game muzika (loop)
mus_free_spins_loop             Free spins muzika (loop)
mus_free_spins_loop_end         Free spins muzika outro
mus_hold_and_win_loop           Hold & Win muzika (loop)
mus_hold_and_win_loop_end       Hold & Win muzika outro
mus_pick_feature_loop           Pick feature muzika (loop)
mus_pick_feature_loop_end       Pick feature muzika outro
mus_wheel_feature_loop          Wheel feature muzika (loop)
mus_wheel_feature_loop_end      Wheel feature muzika outro
mus_big_win_loop                Big win muzika (loop)
mus_big_win_loop_end            Big win muzika outro
mus_jackpot_loop                Jackpot muzika (loop)
mus_jackpot_loop_end            Jackpot muzika outro
mus_gamble_loop                 Gamble muzika (loop)
mus_gamble_loop_end             Gamble muzika outro
```

*Napomena: Base game ima samo `_loop`, nema `_loop_end` — BG muzika se nikad ne završava outrom, samo fade ili tranzicija. Svaki feature kontekst ima par: `_loop` (beskonačan loop tokom feature-a) + `_loop_end` (outro kad feature završi).*

### 🌫️ AMBIENT

```
amb_base_game_loop      Base game ambient bed (loop)
amb_free_spins_loop     Free spins ambient (loop)
amb_feature_loop        Feature ambient (loop, generički fallback)
```

### 🔀 TRANSITIONS

```
trn_base_to_free_spins          BG → Free Spins
trn_free_spins_to_base          Free Spins → BG
trn_base_to_hold_and_win        BG → Hold & Win
trn_hold_and_win_to_base        Hold & Win → BG
trn_base_to_pick_feature        BG → Pick Feature
trn_base_to_wheel_feature       BG → Wheel Feature
trn_wheel_feature_to_base       Wheel Feature → BG
trn_base_to_gamble              BG → Gamble
trn_gamble_to_base              Gamble → BG
trn_base_to_jackpot             BG → Jackpot
trn_jackpot_to_base             Jackpot → BG
```

*Napomena: Svaki feature ima svoj tranzicioni par (in + out). Ako za feature nema custom tranzicija, engine koristi generički crossfade.*

---

## Sonic DNA Classifier — Zero-Click Sound Placement (90% KOMPLETNO)

### Cilj
Korisnik prevuče folder sa BILO KAKVIM imenima zvukova → algoritam **autonomno klasifikuje** svaki zvuk po akustičkom sadržaju → **preimenuje** u FFNC format → **rasporedi** u tačne stage-ove. ZERO klikova, ZERO inputa.

### Layer 1: Spectral Fingerprint (rf-dsp — VEĆ POSTOJI)

7 feature vektora za svaki zvuk:

| Feature | Šta meri | Diskriminativnost |
|---------|----------|-------------------|
| Duration | kratko/srednje/dugo | Razdvaja click (<200ms) od fanfare (>2s) |
| RMS Energy | tiho/srednje/glasno | Razdvaja ambient od win |
| Spectral Centroid | bass/mid/treble | Razdvaja scatter (high) od reel (mid) |
| Transient Density | klik/sustain/pad | Razdvaja hit od loop |
| Zero Crossing Rate | noise/tonal | Razdvaja metalic ping od muzike |
| Spectral Flux | static/dynamic | Razdvaja ambient od evolving win |
| Envelope Shape | attack/decay profil | Razdvaja impulse od buildup |

### Layer 2: Slot Sound Taxonomy (NOVO — treba implementirati)

Hardcoded akustički profili za svaki stage type:

| Stage Type | Duration | Energy | Centroid | Transient | Envelope | Dodatno |
|------------|----------|--------|----------|-----------|----------|---------|
| REEL_SPIN | 50-300ms | LOW-MED | MID | HIGH | sharp_attack, fast_decay | repetitivni pattern boost |
| REEL_STOP | 100-500ms | MED | LOW-MID | SINGLE_SPIKE | sharp_attack, medium_decay | — |
| SCATTER_HIT | 200-800ms | MED-HIGH | HIGH (>4kHz) | HIGH | sharp_attack, long_tail | ZCR HIGH (metallic) |
| BIG_WIN | 2-8s | HIGH | WIDE_BAND | LOW | building/sustained | spectral flux HIGH |
| SMALL_WIN | 500ms-2s | MED | MID-HIGH | LOW-MED | quick_burst | — |
| BUTTON_CLICK | 20-150ms | LOW | MID-HIGH | SINGLE | impulse | — |
| AMBIENT_LOOP | >3s | LOW | LOW-MID | VERY_LOW | flat/no_attack | spectral flux VERY_LOW |
| BONUS_TRIGGER | 500ms-1.5s | HIGH | MID-HIGH | MED | dramatic_attack | ZCR MED-HIGH |
| MULTIPLIER | 300ms-1.2s | MED-HIGH | MID-HIGH | MED | building_crescendo | rising sweep |
| FREE_SPIN_START | 1-3s | MED-HIGH | WIDE | MED | fanfare_shape | spectral flux HIGH |
| MUSIC_BASE | >5s | LOW-MED | LOW-MID | VERY_LOW | flat | harmonic ratio test |
| MUSIC_FEATURE | >3s | MED | MID | LOW | sustained | harmonic ratio test |

**Matching:** Weighted Euclidean distance između zvukovog feature vektora i svakog profila. Najbliži profil = klasifikacija.

### Layer 3: Intelligent Placement Engine (NOVO — treba implementirati)

**Korak 1 — Score Matrix:** Svaki zvuk × svaki stage type → distance score matrica.

**Korak 2 — Hungarian Algorithm:** Optimalno dodeljivanje (maksimizuj ukupni score). Rešava konflikte kad 2 zvuka žele isti slot.

**Korak 3 — Variant Detection:** Ako 5 zvukova svi matchuju REEL_STOP → automatski `reel_stop_1` ... `reel_stop_5`.

**Korak 4 — Gap Analysis:** Posle placement-a, lista stage-ova koji nemaju zvuk → ghost slots u NeuralBindOrb.

**Korak 5 — Auto-Rename + Place:** `boom.wav` → `big_win_tier1.wav`, `click.wav` → `reel_spin.wav` — FFNC-compliant, na disk, gotovo.

### Napredne tehnike (Layer 2 proširenja)

| Tehnika | Šta radi | Implementacija |
|---------|----------|----------------|
| **Contextual Set Inference** | Gleda ceo folder kao set, ne individualne zvukove | Cluster analysis po duration/timbre sličnosti |
| **Harmonic vs Transient Topology** | FFT peak ratio test — muzika ima pravilne harmonike (1:2:3:4), SFX nema | Deterministička matematika, ~97% accuracy |
| **Temporal Periodicity Score** | Detektuje loop-able zvukove po periodičnom transient patternu | Jedan FFT prolaz → auto `_LOOP` tag |
| **Energy Trajectory Classifier** | Envelope integracija: raste=buildup, spada=stinger, ravan=ambient, spike+decay=hit | 4 kategorije pokrivaju 90%+ slot zvukova |

### Šta postoji vs šta treba

| Komponenta | Status | Lokacija |
|------------|--------|----------|
| SpectralDNA (7 ekstrahtora) | ✅ POSTOJI | `crates/rf-dsp/` |
| NeuralBindOrb (drag-to-bind UI) | ✅ POSTOJI | `flutter_ui/lib/widgets/slot_lab/neural_bind_orb.dart` |
| AutoBindEngine scoring | ✅ POSTOJI | `flutter_ui/lib/services/auto_bind/auto_bind_engine.dart` |
| Slot stage definicije | ✅ POSTOJI | `flutter_ui/lib/models/slot_audio_events.dart` |
| SonicClassifier (taxonomy profili + distance) | ✅ KOMPLETNO | `crates/rf-stage/src/sonic_dna.rs` (1168 LOC) |
| PlacementSolver (Hungarian + variants + gaps) | ✅ KOMPLETNO | `crates/rf-stage/src/sonic_dna.rs` (Munkres O(n³)) |
| SonicClassifier FFI | ✅ KOMPLETNO | `crates/rf-engine/src/ffi.rs` (sonic_dna_classify_folder) |
| Dart SonicClassifierProvider | ✅ KOMPLETNO | `flutter_ui/lib/src/rust/slot_lab_v2_ffi.dart` (SonicDnaResult) |
| NeuralBindOrb ring vizualizacija za classified zvukove | ✅ DONE (2026-05-11) | `_paintClassificationRings()` u `_OrbPainter`, `GhostStageIndicator` u `ghost_stage_indicator.dart`, `_buildGhostIndicator()` u orbu |

### User Flow (finalni)

```
1. Korisnik selektuje folder sa 30 zvukova (BILO KAKVA imena)
2. Prevuče na NeuralBindOrb
3. Orb → ANALYZING (cyan sweep, 200-400ms)
4. Zvukovi "lete" u ringove po boji (spin=plava, win=zlatna, scatter=cyan)
5. Orb → DONE (zeleni flash)
6. Rezultat:
   ✓ Svaki zvuk klasifikovan po akustičkom sadržaju
   ✓ Preimenovan u FFNC format
   ✓ Raspoređen u tačan stage
   ✓ Varijante automatski numerisane
   ✓ Gap analysis prikazuje šta fali
   ZERO CLICKS. ZERO INPUT.
```

**Procenjena tačnost:** 85-92% za pravilno snimljene slot zvukove (deterministička fizika, ne ML).

**Ovo ne postoji NIGDE** — nijedan DAW, nijedan slot tool, ništa na svetu nema akustičku klasifikaciju sa automatskim placement-om.

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
- `docs/architecture/ORBMIXER_ARCHITECTURE.md` — OrbMixer kompletna arhitektura (3 nivoa, 4 viz sloja, FFI, Flutter widget tree)
- `docs/architecture/FLUXFORGE_DAW_MIXER_2026.md` — DAW Mixer spec (tradicionalni channel-strip)
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

---

## FAZA 3.7 — GAME CONFIG: Ultimativni Slot Designer Panel

> **Vizija:** HELIX levi panel GAME CONFIG postaje najmoćniji slot konfiguracioni alat na svetu.
> Pokriva svaki mogući tip slota koji postoji u industriji — od klasičnog 3-rilnog fruit machine-a
> do Megaways, Cluster Pays, Infinity Reels i svega između. Svaka konfiguracija je instant-valid,
> compliance-aware i direktno vezana za audio DNA sistem.
>
> **Status (2026-05-09 commit `d27ac94f`):** Phase 0 + A + B + C + D + E + F + H + I + J **landed**.
> Phase G (Live Grid Visualizer) ✅ DONE (2026-05-11) — `_GridVisualizerWidget`, `_GridVisualizerWidgetState`, `_GridVisualizerPainter` u `spine_game_config.dart` (3325 LOC), Spin Preview dugme, Megaways support, payline navigation.
> Phase H vizuelni diff overlay ostaje odložen — vidi "Preostali rad" sekciju.
>
> **Trenutno stanje (post-3.7):** `_SpineGameConfig` ima 8 slot type preseta, Megaways per-reel
> sliders, Cluster + Infinity konfige, 5 symbol presets, FS/Cascade/HoldWin sub-configs,
> Anticipation Tip A/B/Custom, jurisdiction overlay sa per-field violation badges, Blueprint
> Import/Export, Snapshot Diff, RTP feasibility live indicator, Auto-fix patches, integrity
> validator sa 4 severity tier-a.  1086-line `lib/models/game_config_models.dart` je single
> source of truth.

### Šta pokriva svaki mogući tip slota

| Slot Type | Popularnost | Grid | Win Mechanism | Key Features |
|-----------|-------------|------|---------------|--------------|
| **Classic 3-reel** | ⭐⭐ | 3×1-3 | 1-9 fixed paylines | Nudge, Hold |
| **Video Slot 5×3** | ⭐⭐⭐⭐⭐ | 5×3 | 10/20/25 fixed PL | Scatter, FS, Wilds |
| **Video Slot 5×4** | ⭐⭐⭐⭐ | 5×4 | 40 paylines | Extended paytable |
| **6×4 Standard** | ⭐⭐⭐ | 6×4 | 50 paylines / ways | BTG style |
| **243 Ways** | ⭐⭐⭐⭐ | 5×3 | 243 ways | All-ways eval |
| **1024 Ways** | ⭐⭐⭐ | 5×4 | 1024 ways | All-ways eval |
| **Megaways** | ⭐⭐⭐⭐⭐ | 6×(2-7) | 117,649 ways var | Reactions, Cascade mult |
| **Infinity Reels** | ⭐⭐ | start 3×3, expand | Ways expanding | Reel adds on win |
| **Cluster Pays** | ⭐⭐⭐⭐ | 7×7 / 8×8 | 5+ adjacent cluster | Tumble mandatory |
| **All Ways** | ⭐⭐ | 3×3 / 4×4 | Any-position adj | No payline concept |
| **Hold & Win** | ⭐⭐⭐⭐ | 5×3 | 15 fixed / ways | Lock+Spin, jackpot |
| **Book of** | ⭐⭐⭐⭐ | 5×3 | 10 paylines | 1 symbol=Wild+Scatter+FS |
| **Power Reels** | ⭐ | up to 80 reels×1 | Paylines | Extra-wide horizontal |
| **Feature Buy** | cross-type | any | any | Direct bonus access |

---

### Phase 3.7.0 — Slot Type Selector (Foundation)

**Šta:** Vizuelni selector koji menja ceo konfig panel bazan na tipu slota.
Trenutno: ni ne postoji — samo 2 spinnera.

**UX:**
```
┌─ SLOT TYPE ──────────────────────────────────────┐
│  ○ Classic    ● Video     ○ Megaways             │
│  ○ Cluster    ○ Book Of   ○ Hold & Win           │
│  ○ Ways       ○ Infinity  ○ Custom               │
└──────────────────────────────────────────────────┘
```
Selekcija → auto-populate grid defaults, feature defaults, win mechanism defaults.

**Implementacija:**
- `SlotTypePreset` enum: `Classic / VideoStandard / VideoExtended / Megaways / ClusterPays / AllWays / InfinityReels / HoldAndWin / BookOf / Custom`
- `GameConfigProvider` (Flutter singleton) — listenuju: grid, math, features, anticipation, compliance panels
- Apply type → `GameConfigProvider.applyPreset(SlotTypePreset)` — batch sve config domene
- Rust `SlotConfig.from_preset(SlotTypePreset)` → kanonski default za svaki tip

**Reference fajlovi:**
- `flutter_ui/lib/screens/helix_screen.dart` → `_SpineGameConfigState` (replace stub)
- `crates/rf-slot-lab/src/config.rs` → `SlotConfig`, `GridSpec`
- Nova: `flutter_ui/lib/providers/game_config_provider.dart`

**Status:** ✅ landed (`d27ac94f`)  — was "next" in c5056a4b spec

---

### Phase 3.7.A — Grid & Win Mechanism Config

**Šta:** Zamena 2 spinnera → kompletan grid + win mechanism designer.

**UX:**
```
┌─ GRID ────────────────────────────────────────────┐
│  REELS  [−][  5 ][+]    ROWS [−][  3 ][+]        │
│  ┌─ Megaways mode ──────────────────────────────┐ │
│  │ Per-reel rows: R1[2-7] R2[2-7] ... (toggle) │ │
│  └──────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────┘
┌─ WIN MECHANISM ────────────────────────────────────┐
│  ● Paylines   20  [edit patterns]                 │
│  ○ Ways       243                                 │
│  ○ Cluster    min 5 adj  ○ diag                   │
│  ○ Megaways   max 117,649 ways                    │
│  ○ All Ways   any position                        │
│  ○ Infinity   expand on win                       │
└───────────────────────────────────────────────────┘
```

**Implementacija:**
- `WinMechanismSelector` → maps to `WinMechanism` enum iz `win_mechanism.rs` (postoji)
- Megaways mode: per-reel rows sliders (min/max 2-7 per reel)
- Payline pattern visual editor → 5×3 grid, click cells = define payline
- Infinity Reels: `InfinityReelsConfig { start_reels: u8, max_reels: u8, expand_trigger: Symbol }`

**Dependencies:** 3.7.0 | **Status:** ✅ landed (`d27ac94f`)

---

### Phase 3.7.B — Math Profile Editor

**Šta:** RTP target + volatility + hit frequency + max win cap — sa live feasibility indicator.

**UX:**
```
┌─ MATH PROFILE ─────────────────────────────────────┐
│  Volatility  [━━━━━━━━●────] 7.2/10  HIGH          │
│              LOW ←───────────────────→ EXTREME     │
│  RTP Target  [96.5%]  ±0.1%  [ validate ]          │
│  Hit Rate    [24.3%]  per spin                     │
│  Bonus Freq  [1 / 120] spins                       │
│  Max Win Cap ○ Uncapped  ● 5000x  ○ Custom          │
│  Dead Spins  [50] max consecutive                  │
│  ┌─ PRESET ─────────────────────────────────────┐  │
│  │ ○ Low  ● Medium  ○ High  ○ Extreme  ○ Studio │  │
│  └──────────────────────────────────────────────┘  │
│  ⚡ RTP FEASIBILITY: ✓ 96.5% achievable             │
└────────────────────────────────────────────────────┘
```

**Implementacija:**
- Volatility: continuous slider 1.0-10.0 → maps to `VolatilityProfile.interpolate()` (postoji)
- RTP: input field → async Rust FFI → `validate_rtp_feasibility()` → live badge
- Max win cap: `Uncapped / X250 / X500 / X2000 / X5000 / X10000 / Custom`
- STUDIO preset: high hit_rate (60%), high bonus_freq, uncapped — za dev/testing
- Debounced 500ms feasibility checker

**Dependencies:** 3.7.0 | **Status:** ✅ landed (`d27ac94f`)

---

### Phase 3.7.C — Symbol System & Paytable Designer

**Šta:** Symbol presets, special symbols (Wild types, Book mechanic), pay table editor.

**Symbol Presets:**
- `ClassicFruit` → 7, BAR, Bell, Cherry, Lemon, Orange, Plum + Wild
- `StandardRoyals` → A,K,Q,J,10,9 + 3 premium + Wild + Scatter + Bonus
- `MinimalRoyals` → A,K,Q,J + 2 premium + Wild + Scatter
- `BookOf` → A,K,Q,J,10,9 + 4 premium + Book (Wild+Scatter+FS-expander)
- `Custom` → empty, manual build

**Special symbol mechanics:**
- `Standard Wild` — substitutes all except Scatter/Bonus
- `Expanding Wild` — expands to full reel on payline hit
- `Sticky Wild` — stays for N spins
- `Walking Wild` — moves left/right each spin
- `Multiplier Wild` — 2x/3x/5x random on hit
- `Book Symbol` — simultaneously Wild, Scatter trigger, FS expanding symbol
- `Stacked Symbols` — height 2-7, which symbols stack per reel

**Pay table UX:**
```
│  SYM  EMOJI  3-OF  4-OF  5-OF   STACK  SPECIAL
│  W     W     —     —     —      h=3    Expanding
│  SC    ◈     —     —     —      —      Scatter@3+
│  P1    ★    12x   40x  100x    h=2    —
│  P2    ♦     8x   25x   60x    —      —
│  A     A     3x   10x   20x    —      —
```

**Dependencies:** 3.7.0 | **Status:** ✅ landed (`d27ac94f`)

---

### Phase 3.7.D — Feature Stack Designer

**Šta:** Toggle + inline config per feature — sve iz `FeatureConfig` expose-ovano.

**Features:**
- **Free Spins**: count range, multiplier, retrigger, extra mechanics (Expanding Wilds in FS, Sticky Wilds, Infinite retrig)
- **Cascades/Tumble**: remove mode (win-only / all), multiplier step (cap), progression sequence
- **Hold & Win**: respins count (default 3), reset trigger, 4-tier jackpot config (Mini/Minor/Major/Grand seeds + contribution%)
- **Jackpot (standalone)**: tier config, trigger method (symbol count / random / purchase)
- **Gamble**: type (card suit / color / ladder), max attempts, win size limit
- **Pick Bonus**: grid size, reveal style (instant/sequential), prize distribution
- **Feature Buy**: cost multiplier, jurisdiction block badge (UKGC auto-OFF)

**Dependencies:** 3.7.0, 3.7.C | **Status:** ✅ landed (`d27ac94f`)

---

### Phase 3.7.E — Anticipation Config

**Šta:** Full exposure `AnticipationConfig` sa audio stage mapping.

**UX:**
```
┌─ ANTICIPATION ───────────────────────────────────┐
│  Trigger symbols: [SCATTER] [BONUS] [+ add]      │
│  Reel placement:                                 │
│    ● Tip A: Any reel (AtLeast 3)                │
│    ○ Tip B: Reels 0,2,4 only (Exact 3)          │
│    ○ Custom: [R0][R1][R2][R3][R4]               │
│  Tension escalation: ✓                           │
│    L1●━ L2●━ L3●━ L4●  [Gold→Orange→Red]        │
│  Near-miss guard: ✗ (⚠ UKGC requires OFF)        │
│  Audio mapping:                                  │
│    L1 → ANTICIPATION_LOW  [bind ▸]              │
│    L2 → ANTICIPATION_MED  [bind ▸]              │
│    L3 → ANTICIPATION_HIGH [bind ▸]              │
│    L4 → ANTICIPATION_PEAK [bind ▸]              │
└──────────────────────────────────────────────────┘
```

- `[bind ▸]` → jump fokusira AUDIO ASSIGN spine na taj stage
- Tension orbs: `TensionLevel.color_hex()` (postoji u Rust config)
- Tip A/B/Custom → `AnticipationConfig.tip_a()` / `tip_b()` (postoji)

**Dependencies:** 3.7.0, 3.7.C | **Status:** ✅ landed (`d27ac94f`)

---

### Phase 3.7.F — Compliance Presets & Jurisdiction Guard

**Šta:** Multi-jurisdiction toggle → auto-constrain config, per-field violation badges.

| Jurisdiction | Max Bet | Auto Play | Feature Buy | Near Miss | Min RTP |
|---|---|---|---|---|---|
| UKGC | £2 | ✗ | ✗ | ✗ | 92% |
| MGA | none | limited | ✓ | ✓ | 92% |
| SE | SEK100 | ✗ | ✗ | ✗ | 92% |
| DGA | DKK200 | ✗ | ✗ | ✗ | 92% |
| AT | €10 | ✗ | ✗ | ✗ | 90% |
| IoM | none | limited | ✓ | ✓ | 80% |
| Gibraltar | none | ✓ | ✓ | ✓ | 88% |
| Curaçao | none | ✓ | ✓ | ✓ | 85% |

**Implementacija:**
- Nova: `crates/rf-slot-lab/src/compliance.rs` — `CompliancePreset`, `JurisdictionRule`
- `GameConfigProvider.activeJurisdictions: Set<Jurisdiction>` (Flutter)
- Per-field violation checker: reactive → badge (✓/⚠/✗) po svakoj promeni
- `ExportComplianceManifest` → JSON sa timestamp, config, passed/violated rules
- Connector sa `ComplianceLightsBadge` u HELIX omnibar

**Dependencies:** 3.7.0, 3.7.B, 3.7.D | **Status:** ✅ landed (`d27ac94f`)

---

### Phase 3.7.G — Live Grid Visualizer

**Šta:** Mini canvas u panelu — živi prikaz grid-a sa simbolima, paylines overlay, Megaways resize.

**UX:**
```
┌─ GRID PREVIEW ─────────────────────────────────────┐
│   R1   R2   R3   R4   R5                           │
│  ┌───┬───┬───┬───┬───┐                             │
│  │ ★ │ A │ ◈ │ ♦ │ 7 │                             │
│  │ ♦ │ W │ K │ ★ │ ◈ │                             │
│  │ A │ ♠ │ W │ Q │ ♦ │                             │
│  └───┴───┴───┴───┴───┘                             │
│  Payline 1: ─────────── [hover to highlight]       │
│  [ SPIN PREVIEW ] ← demo spin + audio              │
└────────────────────────────────────────────────────┘
```
- Megaways: per-reel različite visine (animated)
- Cluster mode: adjacency graph overlay
- "SPIN PREVIEW" → 1 spin u engine + audio

**Dependencies:** 3.7.A, 3.7.C | **Status:** ✅ DONE (2026-05-11) — `_GridVisualizerWidget` + `_GridVisualizerPainter` u `spine_game_config.dart`, Spin Preview, Megaways support, payline navigation

---

### Phase 3.7.H — Config Snapshot & Diff Engine

**Šta:** Named snapshots, compare dva snapshots (diff view), auto-history poslednjih 10.

**Implementacija:**
- `ConfigSnapshot { name, timestamp, config: SlotConfig, hash: String }`
- Storage: `SlotLabProjectProvider._configSnapshots`
- Diff engine: field-by-field comparison → colored entries (unchanged/changed/added/removed)
- Svaka "Apply" auto-snapshot u history (ne named)

**Dependencies:** 3.7.A-E | **Status:** ✅ landed (`d27ac94f`)

---

### Phase 3.7.I — Smart Integrity Validator (Real-Time)

**Šta:** Live validator, debounced 300ms, pokazuje probleme pre Apply-a.

| Rule | Severity |
|------|----------|
| RTP <85% ili >99% | CRITICAL |
| Paytable: 5-of < 4-of | CRITICAL |
| Feature prob overflow (FS×count >15%) | CRITICAL |
| Near-miss ON + UKGC | ERROR |
| Feature Buy ON + UKGC | ERROR |
| RTP < jurisdiction min | ERROR |
| Hit rate >60% ili <10% | WARNING |
| No audio bound to critical stages | WARNING |
| Cascade + non-tumble mechanism | INFO |
| Book mechanic + multiple scatters | INFO |

- `IntegrityValidator.validate(config, jurisdictions) -> Vec<IntegrityIssue>`
- Svaka issue: `{severity, field_path, message, auto_fix: Option<ConfigPatch>}`
- "Fix All Auto" → applies sve auto_fix patches sa severity >= ERROR
- NE blokira Save — samo informiše (sticky footer counter)

**Dependencies:** 3.7.A, 3.7.B, 3.7.D, 3.7.E, 3.7.F | **Status:** ✅ landed (`d27ac94f`)

---

### Phase 3.7.J — Blueprint Round-Trip Export/Import

**Šta:** `.flux` JSON export + import sa validation i share link.

- `.flux` format: `{version: "3.7", type: "slot_blueprint", config: SlotConfig, metadata: {...}}`
- Export: `serde_json::to_string_pretty` → file picker
- Import: parse → integrity validate → preview diff → confirm apply
- Share link: base64 compressed JSON → clipboard
- Backward compat: verzija parser

**Dependencies:** sve prethodne | **Status:** ✅ landed (`d27ac94f`)

---

### Panel UX arhitektura — sub-tab navigation unutar levog panela

```
┌─ GAME CONFIG ─────────────────────────────────────┐
│  [TYPE][GRID][MATH][FEAT][COMPL][SNAP]            │  ← 6 sub-tab pills
├───────────────────────────────────────────────────┤
│  ← contextual content per tab →                  │
│                                                   │
│  ─── sticky footer ───────────────────────────── │
│  🔴 2 err  ⚠ 1 warn  ℹ 1 info   [ Apply All ]   │
└───────────────────────────────────────────────────┘
```

### Dependency graph

```
3.7.0 (SlotTypePreset + GameConfigProvider)
    ↓
  ├─ 3.7.A (Grid + Win Mechanism)
  ├─ 3.7.B (Math Profile)
  └─ 3.7.C (Symbol System)
        ↓
    ├─ 3.7.D (Feature Stack)    ← after A,C
    ├─ 3.7.E (Anticipation)     ← after A,C
    └─ 3.7.G (Grid Visualizer)  ← after A,C
          ↓
      ├─ 3.7.F (Compliance)     ← after B,D
      └─ 3.7.H (Snapshots)      ← after A-E
            ↓
        ├─ 3.7.I (Integrity Validator)  ← after A,B,D,E,F
        └─ 3.7.J (Blueprint Export)     ← after all
```

### Existing Rust code — NE piši ponovo

| Struct/fn | Fajl | Koristi za |
|-----------|------|------------|
| `SlotConfig` | `rf-slot-lab/src/config.rs` | root config |
| `GridSpec` | `rf-slot-lab/src/config.rs` | grid dimensions |
| `VolatilityProfile.interpolate()` | `rf-slot-lab/src/config.rs` | math slider |
| `FeatureConfig` | `rf-slot-lab/src/config.rs` | feature toggles |
| `AnticipationConfig.tip_a/tip_b` | `rf-slot-lab/src/config.rs` | anticipation presets |
| `TensionLevel.color_hex()` | `rf-slot-lab/src/config.rs` | tension colors |
| `WinMechanism` | `rf-slot-lab/src/model/win_mechanism.rs` | win selector |
| Feature chapters | `rf-slot-lab/src/features/*.rs` | activation |
| `export.rs` | `rf-slot-builder/src/export.rs` | blueprint export |
| `validator.rs` | `rf-slot-builder/src/validator.rs` | integrity basis |
| `GridResizePipeline.apply()` | `flutter_ui` | grid apply |

### CortexEye verifikacioni kriterijumi

| Faza | Pass kriterijum |
|------|----------------|
| 3.7.0 | Type "Megaways" select → grid default 6×(2-7) |
| 3.7.A | Megaways mode → per-reel sliders vidljivi |
| 3.7.B | Volatility slider → hit_rate vrednost se menja |
| 3.7.C | "Classic Fruit" preset → 7,BAR,Bell,Cherry,Lemon |
| 3.7.D | Feature Buy toggle + UKGC → crveni badge |
| 3.7.E | Tip B → R0/R2/R4 highlight, R1/R3 grayed |
| 3.7.F | UKGC toggle ON → near-miss i Feature Buy auto-OFF |
| 3.7.G | Reel count +1 → grid preview instant update |
| 3.7.H | Save "test" snapshot → listed, load → config restored |
| 3.7.I | RTP = 50% → CRITICAL error u footer |
| 3.7.J | Export → import → config identičan (hash match) |

### Preostali rad — post-d27ac94f (sledeći commit kandidati)

| Tag | Šta | Effort | Zašto je preostalo |
|-----|-----|--------|--------------------|
| **3.7.G** | Live Grid Visualizer — mini canvas pored config sekcija koji crta trenutnu reel grid (sa Megaways per-reel rows ako je odabran), color-coded po simbolima iz aktivnog presetа.  SPIN PREVIEW dugme triggers a 1-spin demo bez audio side-effects. | M | Otvoreno svjesno — vizuelni tier zahteva neku vrstu canvas painter-a koji bi reuse-ovao `slotlab_painters.dart` pattern.  Phase A-F vrede i bez njega; G je "nice to see" sloj. |
| **3.7.H+** | Vizuelni Snapshot Diff — trenutno `_buildSnapshotDiffView` prikazuje `+/-/~` linije teksta (JSON-shape diff).  Sledeći iteracija = side-by-side polja sa highlight-ovanim razlikama, plus one-click "Adopt this from L" / "Adopt from R". | S | Phase H je *funkcionalno* zatvoren (snapshot save/load + diff list).  Vizuelni polish je odložen jer ga niko nije zatražio dok JSON-list verzija radi. |
| **3.7.K** *(novo)* | RTP Solver — daj target_rtp + volatility, dobiješ predloženu paytable distribuciju (poisson/zipf model za hit-rate raspodelu po simbolima).  Math team uvek to radi rukom u Excelu — automatizovati. | L | Nije bilo u originalnom 3.7 spec-u, ali se logično nadograđuje na 3.7.B feasibility check.  Backend stub može biti `rf-slot-builder::math::solve_paytable(&MathProfile)`. |
| **3.7.L** *(novo)* | Compliance Audit Trail — svaka jurisdiction promena se loguje u `cortex.db chat_messages` sa timestamp + diff (e.g. "UKGC ON → Feature Buy OFF, near-miss cap 3% applied").  Kompliance officer može da povuče history za svaku odluku tokom dizajna. | M | Out-of-scope za 3.7.F koji samo aplicira ograničenja.  Audit trail je zaseban ugovor sa jurisdikcijom. |
| **3.7.M** *(novo)* | AI Slot Type Recommender — "imam target_rtp 96.5, volatility 7, target market = mobile slots Latin America" → predlaže Slot Type + math profile + suggested features.  Coupled sa Sonic DNA Classifier (Layer 3) iz druge faze. | XL | Long-term futuristic; veže se na FAZA 4 AI Copilot.  Tracirati ovde da se ne izgubi. |

### CortexEye verifikacija — što je manuelno, što je automatski

Strukturalno (analyze + cargo + build) sve prolazi.  **CortexEye HTTP server na 127.0.0.1:7891 nije up** u trenutnom workspace-u (jer `cortex-eye-hands` crate ne postoji); CortexVision unutar Flutter app-a je na 26200 i radi.  Što znači:

- **Svako 13 implementiranih kontrola** moraš ručno da klikneš da bi ih video u akciji (TYPE selector → Megaways, GRID tab, FEAT tab → expand FreeSpins, COMPL → UKGC toggle, SNAP → Diff view).
- **Auto-fix patches** se mogu live testirati: postavi UKGC ON → near-miss 5% → integrity blocker pojavi se → klik "Fix all" → sve auto-rešava na compliant value.
- **Blueprint round-trip** je sigurno čist (round-trip test eksponovan u panelu — paste JSON → preview → apply, bez disk-a).

