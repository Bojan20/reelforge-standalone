# OrbMixer — Radijalni Audio Mixer Architecture

Status: ✅ PHASES 1-10 KOMPLETNO IMPLEMENTIRANO (2026-04-22)
Scope: SlotLab + HELIX Audio Panel + Live Play Companion overlay
Target: Kompaktan futuristički mixer — 60/120/200px LOD modes
Date: 2026-04-22
Last updated: 2026-04-22 (Phase 10e — Problems Inbox)

## IMPLEMENTACIONI STATUS

| Faza | LOC | Status | Commit |
|------|-----|--------|--------|
| Phase 1: Bus Routing (BusReturnNode) | ~120 | ✅ DONE | — |
| Phase 2: Nivo 1 (Orbit View + gestures) | 514+745+894 | ✅ DONE | — |
| Phase 3: Nivo 2 (bus expand, voice dots, FFI) | ~498 | ✅ DONE | — |
| Phase 4: Nivo 3 (per-voice arc sliders) | ~350 | ✅ DONE | — |
| Phase 5: Visual Layers (trails/snap/heatmap/scrub) | ~343 | ✅ DONE | — |
| **Phase 6: HPF/LPF/Send Engine Wire-up** | ~147 | ✅ DONE | `37d65489` |
| **Phase 7: Real-time RMS metering per voice** | — | ✅ DONE (pre-existing, audit confirmed) | — |
| **Phase 8: Live FFT Heatmap (master 32-band)** | ~34 | ✅ DONE | `2ba2ce1f` |
| **Phase 9: Live Play Companion Mode** | ~372 + 175 fix | ✅ DONE | `717703d1` + `4c850c33` |
| **Phase 10 foundation: categories + ghosts + filters + culprit** | ~461 | ✅ DONE | `ae2a6df7` |
| **Phase 10 rendering: voice ghosts + category buckets** | ~143 | ✅ DONE | `c436a67a` |
| **Phase 10 UX: quick filter chips + auto-focus button** | ~162 | ✅ DONE | `3e607545` |
| **Phase 10d: Live Alerts (clip/headroom/phase/masking)** | ~357 | ✅ DONE | `6395f0f3` |
| **Phase 10e: Problems Inbox (capture + review panel)** | ~836 | ✅ DONE | `f9d68183` |
| QA: UI placement + canonical fix | ~30 | ✅ DONE | — |
| **UKUPNO** | **~5700+ LOC** | **✅ Phases 1-10e** | **9 novih commits 2026-04-22** |

**Fajlovi (2026-04-22 session):**
- `flutter_ui/lib/widgets/slot_lab/orb_mixer.dart` (+15 — `onProviderReady` callback)
- `flutter_ui/lib/widgets/slot_lab/orb_mixer_painter.dart` (+229 — ghosts, buckets, alerts)
- `flutter_ui/lib/providers/orb_mixer_provider.dart` (+140 — filters, culprit, alerts, history, buckets)
- `flutter_ui/lib/widgets/slot_lab/live_play_orb_overlay.dart` (NEW — 657 LOC)
- `flutter_ui/lib/services/voice_category_resolver.dart` (NEW — 217 LOC)
- `flutter_ui/lib/services/voice_history_buffer.dart` (NEW — 142 LOC)
- `flutter_ui/lib/services/orb_mixer_alerts.dart` (NEW — 252 LOC)
- `flutter_ui/lib/services/problems_inbox_service.dart` (NEW — 189 LOC)
- `flutter_ui/lib/widgets/slot_lab/problems_inbox_panel.dart` (NEW — 382 LOC)
- `flutter_ui/lib/models/mix_problem.dart` (NEW — 133 LOC)
- `crates/rf-engine/src/playback.rs` (+113 — SetHpf/SetLpf/SetSend, 4 × BiquadTDF2 per voice, render integration)
- `crates/rf-dsp/src/biquad.rs` (+14 — `reset()`, `sample_rate()` helpers)
- `flutter_ui/lib/screens/helix_screen.dart` (+65 — slot_load_sample / slot_spin* / orb_* / fsm_* eye-actions)
- `flutter_ui/lib/services/cortex_eye_server.dart` (+47 — `GET /eye/fsm_state` endpoint)

**Preostalo (sledeće sesije):**
- **Phase 10e-2**: Rust FFI for 5s master audio ring buffer export → Problems Inbox replay actual audio
- **Per-bus FFT** (masking upgrade): precise 1/3-oct band overlap instead of broad-region heuristic
- **Performance isolate**: for VoiceHistoryBuffer when > 100 concurrent voices

**Legacy fajlovi (Phases 1-5):**
- `crates/rf-engine/src/hook_graph/dsp_nodes/bus_return.rs` (~120 LOC)
- `crates/rf-engine/src/ffi.rs` — `orb_get_active_voices` + `orb_set_voice_param`
- `flutter_ui/lib/widgets/slot_lab/audio_coverage_widget.dart` (665 LOC)

---

## 0. PURPOSE

OrbMixer zamenjuje tradicionalni DAW channel-strip mixer sa radijalnom (polarnom) vizualizacijom.
Sve audio kontrole u jednom krugu — volume, pan, solo, mute, per-voice params — bez fader-a i strip-ova.

**Ovo ne postoji NIGDE** — ni Wwise, ni FMOD, ni Pro Tools, ni bilo koji DAW ili game audio tool.

---

## 1. KONCEPT

Jedan krug (120×120px). Svaki audio bus je tačka na orbiti. Centar = Master.

```
         🟢 Music
        ╱    ╲
   🔵 Amb ─── ◉ Master ─── 🟡 SFX
        ╲    ╱
    🟣 VO    🔴 UI
```

| Vizuelni parametar | Značenje |
|--------------------|----------|
| Udaljenost od centra | Volume (centar = -inf, orbit ring = 0dB, van = >0dB) |
| Ugao (kružna pozicija) | Pan L/R |
| Veličina tačke | Peak meter (real-time, 60fps) |
| Boja | Bus kategorija (fiksna po bus tipu) |
| Pulsiranje | Real-time peak aktivnost |
| Glow (aureola) | Solo aktivan |
| Dim (50% opacity) | Muted |

---

## 2. TRI NIVOA INTERAKCIJE

### Nivo 1: Orbit View (default)

6 bus tačaka + Master centar. Vidljivo uvek.

**Gestovi:**

| Gest | Akcija | Latencija |
|------|--------|-----------|
| Drag tačku radijalno | Volume (bliže centru = tiše) | 0ms |
| Drag tačku kružno | Pan L/R | 0ms |
| Click tačku | Solo toggle | 1 click |
| Right-click tačku | Mute toggle | 1 click |
| Scroll na tački | Fine volume (0.5dB koraci) | 0ms |
| Double-click centar | Master volume popup | 1 click |
| Hover tačku | Tooltip: name, dB, peak, bus routing | 0ms |

**Master (centar ◉):**
- Veličina = master volume
- Boja = overall peak (zelena→žuta→crvena)
- Click = master mute
- Scroll = master volume

**Auto-layout (fiksne pozicije):**
- Music: 90° (gore)
- SFX: 0° (desno)
- Ambience: 180° (levo)
- VO: 270° (dole)
- UI: 135° (gore-levo)
- Master: centar

### Nivo 2: Bus Expand (drill-down u individualne zvukove)

Tap na bus dot → dot "eksplodira" u mini-orbit. Svi aktivni zvukovi (voice-ovi) tog busa se pojave kao manje tačke oko centra gde je bio bus dot.

```
Pre tapa:              Posle tapa na SFX:

   ●Mus                    ●Mus
 ●SFX    ●Amb           ○reel_stop_0
   ●VO                 ○spin_press  ○reel_stop_1
 ●UI     ●Mst            ○win_small
                        ●VO     ●Amb
                      ●UI      ●Mst
```

Svaka mala tačka (○) = jedan aktivni zvuk (VoiceId u Rust engine-u).

| Parametar | Mapiranje |
|-----------|-----------|
| Udaljenost | Voice volume |
| Ugao | Voice pan |
| Veličina | Voice peak level |
| Boja | Status: playing=zelena, fading=žuta, queued=siva |

Tap spolja (van expanded zone) = vrati se na Nivo 1.

### Nivo 3: Sound Detail (per-voice parametri)

Long-press na voice tačku → popup ring sa arc slider-ima:

```
        HPF ◐
    EQ ◐       ◐ LPF
  Comp ◐   ○   ◐ Pan
    Vol ◐       ◐ Pitch
        Send ◐
```

Svaki parametar je arc slider oko zvuka. Rotiraš prstom oko tačke — menja vrednost.

**Parametri (param enum):**

| param | Vrednost | Opseg |
|-------|----------|-------|
| 0 | Volume | 0.0 — 2.0 (0dB = 1.0) |
| 1 | Pan | -1.0 (L) — +1.0 (R) |
| 2 | Pitch | 0.5 — 2.0 (semitone steps) |
| 3 | HPF cutoff | 20Hz — 20kHz (log scale) |
| 4 | LPF cutoff | 20Hz — 20kHz (log scale) |
| 5 | Send level | 0.0 — 1.0 |

---

## 3. VIZUELNI SLOJEVI

### 3.1 Ghost Trails

Svaka tačka ostavlja bledi trag kad je pomeriš — rep koji pokazuje prethodnu poziciju (poslednjih 2s).

- Vizual: transparentni gradient od trenutne do prethodne pozicije
- Undo: dupli tap na ghost trail → tačka se vrati na ghost poziciju
- Implementacija: circular buffer sa 120 pozicija (60fps × 2s)

### 3.2 Magnetic Snap Groups

Drži dva zvuka blizu → magnetski se spoje u klaster.

- Vizual: tačke se spoje sa tankom linijom, zajednički border
- Pomeranje: pomeri jednu → sve u klasteru se pomeraju proporcionalno
- Razdvajanje: pinch gest
- Korisno za: linked stereo parove, muzika+ambient koji idu zajedno

### 3.3 Frequency Heatmap pozadina

Umesto crne pozadine, orb ima živu heatmapu ukupnog spektra:

- Centar = bass (crveno kad je loud)
- Sredina = mid (narandžasto)
- Ivica = treble (plavo)
- Izvor: `metering_get_master_spectrum` FFI (već postoji)
- 30fps update (svaki drugi frame, za performanse)

### 3.4 Timeline Scrub Ring

Spoljašnji prsten oko orba = timeline (poslednjih 30s).

- Rotiraš ring → vidiš kako se mix menjao kroz vreme
- Svaka tačka se animira gde je bila u tom trenutku
- Replay tvog mixa kao animacija
- Implementacija: circular buffer sa 900 snapshota (30fps × 30s), svaki snapshot = {bus_id, volume, pan}

---

## 4. SLOT-SPECIFIC OPTIMIZACIJE

| Feature | Okidač | Vizual |
|---------|--------|--------|
| Win escalation glow | Big win event | Music tačka pulsira jače, SFX dobija aureolu |
| Anticipation visualizer | Anticipation stage | Orbit ring se steže (tension visual) |
| Idle dimming | Bus bez aktivnosti >2s | Tačka se dimuje na 30% opacity |
| Feature transition | FeatureEnter stage | Bus tačke blago menjaju poziciju (new mix state) |

---

## 5. PROŠIRENI MOD (hover)

Kad hover-uješ ceo orb, blago se proširi (120→180px) i pokaže:

- dB vrednosti pored svake tačke (`-3.2 dB`)
- Tanke linije od svake tačke do master centra (routing vizualizacija, opacity = volume)
- Mini waveform ring oko svake tačke (poslednje 2s audio iz peak buffera)

---

## 6. INTEGRISANJE U UI

| Mod | Dimenzije | Lokacija | Ponašanje |
|-----|-----------|----------|-----------|
| Floating | 120×120px | Ćošak SlotLab editora | Overlay, draggable, always-on-top |
| Docked | 80×80px | HELIX toolbar | Compact mod, hover expand |
| Embedded | 120×120px | HELIX AUDIO panel | Inline, full interaction |
| Expanded | 180×180px | Isti prostor (hover) | Animirano proširenje |

---

## 7. TEHNIČKA ARHITEKTURA (Flutter)

```
OrbMixer (StatefulWidget, 120x120)
├── CustomPainter (60fps via Ticker)
│   ├── _paintFrequencyHeatmap()     // Layer 0: pozadina
│   ├── _paintTimelineScrubRing()    // Layer 1: spoljašnji prsten
│   ├── _paintOrbitRing()            // Layer 2: referentni 0dB krug
│   ├── _paintRoutingLines()         // Layer 3: tačka → centar, opacity = volume
│   ├── _paintGhostTrails()          // Layer 4: bledi repovi
│   ├── _paintBusDots()              // Layer 5: bus tačke
│   │   ├── radius = peak_meter * scale
│   │   ├── color = category_color
│   │   ├── glow = solo ? bloom_shader : none
│   │   └── opacity = muted ? 0.5 : 1.0
│   ├── _paintVoiceDots()            // Layer 6: voice tačke (Nivo 2)
│   ├── _paintParamRing()            // Layer 7: arc slideri (Nivo 3)
│   └── _paintMasterDot()            // Layer 8: centar, pulsira sa peak
│
├── GestureDetector (per-dot hit testing)
│   ├── onPanStart → determine target (bus dot, voice dot, param arc)
│   ├── onPanUpdate → radial drag = volume, angular drag = pan
│   ├── onTap → solo toggle / bus expand (Nivo 2)
│   ├── onSecondaryTap → mute toggle
│   ├── onLongPress → sound detail ring (Nivo 3)
│   └── onScaleUpdate → fine volume (scroll wheel)
│
├── MagneticSnapController
│   ├── detectProximity(dotA, dotB) → bool
│   ├── createCluster([dotA, dotB])
│   └── breakCluster(pinchGesture)
│
├── GhostTrailBuffer (circular, 120 entries per dot)
│
├── TimelineSnapshotBuffer (circular, 900 entries)
│
└── HoverOverlay (AnimatedContainer 120→180px)
    ├── dB labels (positioned per dot)
    ├── routing lines (CustomPaint, opacity = volume)
    └── mini waveform rings (peak buffer last 2s)
```

### State Management

```dart
class OrbMixerProvider extends ChangeNotifier {
  // Nivo 1: Bus state
  final Map<BusId, OrbBusState> _busStates;  // volume, pan, solo, mute, peak
  
  // Nivo 2: Active voices (from FFI)
  final Map<BusId, List<OrbVoiceState>> _activeVoices;
  
  // Nivo 3: Voice params
  void setVoiceParam(int voiceId, int param, double value);
  
  // Vizuelni slojevi
  BusId? expandedBus;       // null = Nivo 1, non-null = Nivo 2
  int? detailVoiceId;       // null = no detail, non-null = Nivo 3
  List<Set<BusId>> clusters; // magnetic snap groups
  
  // Timeline scrub
  int scrubPosition;  // 0-899 index u snapshot buffer
  bool isScrubbing;
}

class OrbBusState {
  final BusId id;
  double volume;     // 0.0 — 2.0
  double pan;        // -1.0 — +1.0
  bool solo;
  bool mute;
  double peakL;      // real-time
  double peakR;      // real-time
  Offset position;   // computed from volume + pan → polar coords
}

class OrbVoiceState {
  final int voiceId;
  final String assetId;
  final BusId bus;
  double volume;
  double pan;
  double peakL;
  double peakR;
  VoiceStatus status; // playing, fading, queued
}
```

---

## 8. RUST FFI (potrebno)

### Per-voice kontrola

```rust
// U crates/rf-bridge/src/orb_mixer_ffi.rs

/// Set individual voice parameter
#[no_mangle]
pub extern "C" fn slot_lab_set_voice_param(
    voice_id: u32,
    param: u8,    // 0=vol, 1=pan, 2=pitch, 3=hpf, 4=lpf, 5=send
    value: f32,
) -> i32;

/// Get all active voices as JSON
/// Returns: [{voice_id, asset_id, bus, peak_l, peak_r, state}]
#[no_mangle]
pub extern "C" fn slot_lab_get_active_voices() -> *mut c_char;

/// Free string returned by get_active_voices
#[no_mangle]
pub extern "C" fn slot_lab_free_orb_string(ptr: *mut c_char);
```

### Engine-side (crates/rf-engine/src/voice_control.rs)

```rust
pub struct VoiceControl {
    pub volume: f32,
    pub pan: f32,
    pub pitch: f32,
    pub hpf_cutoff: f32,
    pub lpf_cutoff: f32,
    pub send_level: f32,
}

impl PlaybackEngine {
    pub fn set_voice_param(&mut self, voice_id: u32, param: u8, value: f32) {
        // Lock-free: send command via rtrb ring buffer
        // Audio thread picks up on next process() call
    }
    
    pub fn get_active_voices(&self) -> Vec<ActiveVoiceInfo> {
        // Read from atomic voice registry
        // Zero-alloc on audio thread — UI thread does the allocation
    }
}
```

---

## 9. PREDUSLOV: BUS ROUTING WIREUP

OrbMixer Nivo 1 radi sa postojećim MixerProvider state-om.
Nivo 2 i 3 zahtevaju funkcionalan bus routing u engine-u.

**Trenutni status:**
- ⚠️ BusSendNode je stub (samo gain, ne rutira audio)
- ❌ BusReturnNode ne postoji
- ⚠️ send_return.rs nije integrisan u hook_graph
- ⚠️ Dart bus hijerarhija se ne propagira na Rust

**Redosled implementacije:**

```
Phase 1: Bus Routing Fix
  1.1 BusSendNode — stvarno rutira audio do destination busa
  1.2 BusReturnNode — sumira sve sendove
  1.3 Integriši send_return.rs u hook_graph rendering
  1.4 Sinhronizuj Dart hijerarhiju → Rust

Phase 2: OrbMixer Nivo 1
  2.1 OrbMixer widget (CustomPainter + gestures)
  2.2 Wire do MixerProvider (volume/pan/solo/mute)
  2.3 Peak metering iz FFI

Phase 3: OrbMixer Nivo 2
  3.1 FFI: slot_lab_get_active_voices()
  3.2 Bus expand animation + voice dots
  3.3 Per-voice drag = volume/pan

Phase 4: OrbMixer Nivo 3
  4.1 FFI: slot_lab_set_voice_param()
  4.2 Long-press → param ring
  4.3 Arc slider interaction

Phase 5: Vizuelni slojevi
  5.1 Ghost trails
  5.2 Magnetic snap groups
  5.3 Frequency heatmap (metering_get_master_spectrum FFI)
  5.4 Timeline scrub ring
```

---

## 10. FAJLOVI (planirani)

| Fajl | LOC (procena) | Sadržaj |
|------|---------------|---------|
| `flutter_ui/lib/widgets/slot_lab/orb_mixer.dart` | ~800 | Widget + gesture handling + state transitions |
| `flutter_ui/lib/widgets/slot_lab/orb_mixer_painter.dart` | ~500 | CustomPainter sa 8 slojeva |
| `flutter_ui/lib/providers/orb_mixer_provider.dart` | ~300 | State: bus, voices, clusters, scrub |
| `crates/rf-bridge/src/orb_mixer_ffi.rs` | ~150 | FFI: voice params + active voices |
| `crates/rf-engine/src/voice_control.rs` | ~200 | Per-voice parameter control, lock-free |

**Ukupno:** ~1950 LOC

---

## 11. POREĐENJE SA INDUSTRIJSKIM STANDARDOM

| Aspekt | DAW Mixer | Wwise/FMOD | OrbMixer |
|--------|-----------|------------|----------|
| Prostor | 300-600px širine | 200-400px | **120×120px** |
| Volume | Nađi strip → drag fader | Nađi bus → slider | **Drag tačku** |
| Pan | Nađi strip → drag knob | Separate pan control | **Kružni drag iste tačke** |
| Solo | Nađi strip → click S | Button | **Click tačku** |
| Vizualni pregled | Čitaj 6 fader pozicija | Čitaj listu | **Jedan pogled** |
| Per-voice control | ❌ Ne postoji | Ograničeno | **Drill-down u individualne zvukove** |
| Ghost trails | ❌ | ❌ | ✅ |
| Frequency heatmap | Separate analyzer | ❌ | ✅ Integrisano |
| Timeline replay | ❌ | ❌ | ✅ Scrub ring |
| Gaming feel | ❌ Studio alat | Polovina | ✅ **HUD element** |
