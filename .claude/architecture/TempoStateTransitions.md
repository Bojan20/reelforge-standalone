# Tempo State Transitions — Architecture Blueprint

## Koncept

Wwise Interactive Music pristup: isti muzicki materijal, razlicit tempo po game state-u.
Tranzicija sincronizovana na beat grid sa crossfade-om.

FluxForge prednost: phase vocoder time-stretching vec postoji — nema potrebe za dupliciranjem audio fajlova.

## Arhitektura: TempoStateEngine

```
+---------------------------------------------+
|          TempoStateEngine (Rust)             |
+---------------------------------------------+
|                                              |
|  MusicSegment --> BeatGridTracker            |
|    - source_bpm: 120                         |
|    - beats_per_bar: 4                        |
|    - loop_region                             |
|                                              |
|  TempoState[] --> PhaseVocoder               |
|    - "base_game":  100 BPM (stretch 0.83x)   |
|    - "free_spins": 130 BPM (stretch 1.08x)   |
|    - "bonus":      160 BPM (stretch 1.33x)   |
|                                              |
|  TransitionRule[] --> CrossfadeProcessor     |
|    - sync_to: bar | beat | phrase            |
|    - type: crossfade | stinger_bridge        |
|    - duration: 2 bars                        |
|    - curve: sCurve                           |
|    - tempo_ramp: linear | instant | sCurve   |
|                                              |
|  +---------------+    +---------------+      |
|  | Voice A       |    | Voice B       |      |
|  | @100 BPM      | X  | @130 BPM      |      |
|  | (playing)     |    | (fading in)   |      |
|  +---------------+    +---------------+      |
|         +------- crossfade -------+          |
|                    |                         |
|                    v                         |
|              output bus                      |
+---------------------------------------------+
```

## Postojece komponente

### Rust DSP (IMPLEMENTIRANO)
- `crates/rf-dsp/src/time_stretch.rs` — SimplePhaseVocoder, match_duration(), 0.25x-4.0x
- `crates/rf-dsp/src/elastic.rs` — ElasticAudio sa warp markerima, 8 algoritama
- `crates/rf-dsp/src/pitch.rs` — YIN pitch detekcija + korekcija

### Dart konfiguracija (MODELIRANO, bez engine execution)
- `blocks/music_states_block.dart` — MusicContext, LayerLevel, TransitionSyncMode, FadeCurve, stingeri
- `providers/slot_lab/transition_system_provider.dart` — TransitionRule model (skeleton)
- `providers/subsystems/music_system_provider.dart` — MusicSegment model sa tempo/beats_per_bar
- `models/middleware_models.dart` — setState, setSwitch, setRTPC (Wwise pattern)
- `widgets/timeline/tempo_track.dart` — TempoRampType: instant, linear, sCurve

## Nedostajuce komponente

| Komponenta | Lokacija | Opis |
|---|---|---|
| TempoStateEngine | `rf-engine` (novo) | Centralni orkestar za tempo tranzicije |
| BeatGridTracker | `rf-dsp` (novo) | Audio thread beat/bar pozicije, atomic read |
| CrossfadeProcessor | `rf-dsp` (novo) | Equal-power / S-curve crossfade izmedju voice-ova |
| SegmentSequencer | `rf-engine` (novo) | Queue + seamless loop za MusicSegment |
| FFI bindings | `rf-bridge` (extend) | Wire Dart -> Rust za sve gore |
| TransitionSystemProvider | `flutter_ui` (wire) | Povezati skeleton sa FFI pozivima |

## Dva pristupa za tempo tranziciju

### A) Dual-Voice Crossfade (Wwise nacin)
- Dva playback voice-a sa istim audio materialom
- Voice A svira @100BPM (time-stretched), Voice B @130BPM
- Na tranziciji: cekaj sync point (sledeci bar), crossfade A->B
- Prednost: cist, provereno radi
- Mana: dupla CPU cena tokom crossfade-a

### B) Real-Time Tempo Ramp (napredniji)
- Jedan voice, postepeno menja stretch factor
- 100 BPM -> 130 BPM tokom 2 bara (linear/sCurve interpolacija)
- Beat grid se dinamicki azurira tokom rampe
- Prednost: manji CPU, glatka tranzicija
- Mana: beat grid drift, kompleksnije

### Preporuka: Hibridni pristup
1. Instant/Beat sync -> Dual-Voice Crossfade (cistiji rez)
2. Bar/Phrase sync -> Real-Time Tempo Ramp (muzikalniji)
3. Stinger Bridge -> Exit stinger maskira tempo promenu

## FFI interfejs

```rust
// TempoStateEngine FFI
fn tempo_state_add(segment_id: u32, state_name: *const c_char, target_bpm: f64);
fn tempo_state_set_transition(
    from: *const c_char, to: *const c_char,
    sync_mode: u32,       // 0=immediate, 1=beat, 2=bar, 3=phrase
    duration_bars: u32,
    ramp_type: u32,       // 0=instant, 1=linear, 2=sCurve
    fade_curve: u32,      // 0=linear, 1=equalPower, 2=sCurve
);
fn tempo_state_trigger(state_name: *const c_char);  // async, ceka sync point
fn tempo_state_get_current_bpm() -> f64;             // atomic read
fn tempo_state_get_beat_position() -> f64;           // beats od pocetka bara
```

## Integracija sa postojecim sistemom

- `MusicStatesBlock` vec ima `TransitionSyncMode` i `FadeCurve` — dodati `targetBpm` po kontekstu
- `TransitionRule` vec ima `transitionType` i `fadeDuration` — dodati `tempoRampType`
- `MusicSegment` vec ima `tempo` polje — to postaje source BPM
- `SimplePhaseVocoder` iz rf-dsp je osnova za real-time stretching

## Implementacioni plan

### Faza 1: BeatGridTracker + CrossfadeProcessor (rf-dsp)
- Beat pozicija iz tempo + sample_rate + playhead
- Equal-power crossfade sa konfigurisanim krivama

### Faza 2: TempoStateEngine (rf-engine)
- State registracija sa target BPM
- Transition rule evaluacija
- Dual-voice management sa PhaseVocoder instancama

### Faza 3: FFI + Dart wiring
- rf-bridge FFI bindings
- TransitionSystemProvider -> FFI pozivi
- MusicSystemProvider.addMusicSegment() -> stvarni FFI segment

### Faza 4: UI integracija
- Tempo state konfiguracija u MusicStatesBlock
- Transition preview sa real-time vizualizacijom
- Beat grid overlay na timeline
