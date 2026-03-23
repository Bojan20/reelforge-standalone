# SlotLab Voice Mixer — Ultimativna Arhitektura

## Vizija

Per-layer mixer za SlotLab — svaki zvuk koji je assignovan na event ima permanentni fader strip
u MIX lower zone-u. Mixer kanali se kreiraju automatski kad se audio assignuje na event
(auto-bind, drag-drop, FFNC multi-layer), i nestaju kad se zvuk ukloni. Dok slot mašina radi,
meteri se pale kad odgovarajuća voice instanca svira. Sound designer miksuje SVE zvukove
odjednom — može solo-ovati jedan zvuk, pustiti spin, čuti samo njega.

**Superiornost nad Wwise/FMOD:**
- Wwise: Actor-Mixer ima per-sound properties ali prikazuje ih kao tree/property view, NE kao fader stripove. Mixer prikazuje samo buseve.
- FMOD: Event je interni mixer ali opet nema globalni per-sound fader view.
- FluxForge: Per-layer fader stripovi grupisani po busu = Actor-Mixer + Master-Mixer u jednom view-u.

---

## Izvor podataka — Single Source of Truth

**`MiddlewareProvider.compositeEvents`** → `List<SlotCompositeEvent>`

Svaki `SlotCompositeEvent` sadrži `List<SlotEventLayer>` — to je lista zvukova.
Svaki `SlotEventLayer` = **jedan mixer kanal**.

Polja iz `SlotEventLayer` relevantna za mixer:
```
id              → channel ID
name            → display name
audioPath       → za tooltip, waveform, preview
volume          → fader value (0.0-1.0)
pan             → pan knob (-1.0 to +1.0)
muted           → mute button
solo            → solo button
loop            → loop indicator
busId           → bus routing (0=Master, 1=Music, 2=SFX, 3=Voice, 4=Ambience)
fadeInMs         → envelope display
fadeOutMs        → envelope display
dspChain        → per-layer insert chain (LayerDspNode lista)
actionType      → "Play", "Stop", "FadeOut" — samo "Play" prikazuje strip
```

### Kako se kanali kreiraju (4 code path-a)

1. **Quick Assign** → `_ensureCompositeEventForStage()` → dodaje layer
2. **Manual drag-drop** → `onAudioAssign` callback → isti flow
3. **Auto-bind (FFNC)** → `_ensureCompositeEventForStage()` + FFNC enrichment
4. **Add layer** → `CompositeEventSystemProvider.addLayerToEvent()`

Svi putevi rezultuju promenom `MiddlewareProvider` → `notifyListeners()` sa
`changeCompositeEvents` flagom.

### Kako se kanali uklanjaju

- `CompositeEventSystemProvider.removeLayerFromEvent()`
- Brisanje celog composite eventa

---

## Arhitektura

### Novi fajlovi

```
flutter_ui/lib/providers/slot_lab/slot_voice_mixer_provider.dart
flutter_ui/lib/widgets/slot_lab/slot_voice_mixer.dart
```

### Modifikacije

```
flutter_ui/lib/widgets/lower_zone/lower_zone_types.dart          → novi sub-tab
flutter_ui/lib/widgets/lower_zone/slotlab_lower_zone_widget.dart  → wire sub-tab
flutter_ui/lib/services/service_locator.dart                      → register provider
flutter_ui/lib/main.dart                                          → expose provider
```

### Rust: NEMA promena
Sve FFI metode već postoje: setVoiceVolume, setVoicePan, setVoiceMute, isVoiceActive.

---

## Faza 1: SlotVoiceMixerProvider

### Model

```dart
class SlotMixerChannel {
  final String layerId;         // SlotEventLayer.id
  final String eventId;         // parent SlotCompositeEvent.id
  final String stageName;       // parsed from eventId ("audio_REEL_STOP_0" → "REEL_STOP_0")
  final String displayName;     // human-readable (parsed from audioPath)
  final String audioPath;       // full path za tooltip/preview
  final int busId;              // routing (0-7)
  final String busName;         // "SFX", "Music"...
  final Color busColor;         // za header
  final bool isLooping;         // loop indicator
  final String actionType;      // "Play" only shown as strip

  // Controllable — bidirekcioni sync sa SlotEventLayer
  double volume;                // 0.0-1.5 (fader)
  double pan;                   // -1.0 to +1.0 (pan knob)
  bool muted;                   // M button
  bool soloed;                  // S button (local-only logic)

  // Real-time — iz AudioPlaybackService active voices
  bool isPlaying;               // has active voice instance
  int? activeVoiceId;           // current voice ID
  double peakL;                 // metering
  double peakR;
  double peakHoldL;             // peak hold (1500ms decay)
  double peakHoldR;

  // Layer DSP chain (per-layer inserts)
  List<LayerDspNode> dspChain;
}
```

### Provider logika

```dart
class SlotVoiceMixerProvider extends ChangeNotifier {
  // Kanali grupisani po busu, sortirani po eventId/layerId
  List<SlotMixerChannel> _channels = [];

  // Bus master strips (iz MixerDSPProvider)
  // Re-used, NE duplicirani — samo reference

  // Ticker za metering (30fps)
  Ticker? _meterTicker;

  // Listeners
  MiddlewareProvider _middleware;        // composite events source
  AudioPlaybackService _playback;       // active voices
  SharedMeterReader _meterReader;       // bus-level metering
}
```

### Rebuild logika (kad se composite events promene)

```
_onMiddlewareChanged():
  1. Čitaj middleware.compositeEvents
  2. Flatten: za svaki event, za svaki layer gde actionType == "Play":
     → kreiraj/update SlotMixerChannel
  3. Sortiraj po busId, pa po stageName, pa po layerId
  4. Diff sa postojećom _channels listom:
     - Novi layeri → dodaj kanal sa default values iz layer-a
     - Obrisani layeri → ukloni kanal
     - Postojeći → update metadata (audioPath, busId, etc.) ALI ZADRŽI
       user-modified volume/pan/mute/solo AKO su promenjeni iz mixera
  5. notifyListeners()
```

### Voice mapping logika (30fps ticker)

```
_onMeterTick():
  1. Čitaj _playback.activeVoices
  2. Za svaku active voice sa layerId != null:
     → Nađi odgovarajući SlotMixerChannel po layerId
     → Postavi isPlaying = true, activeVoiceId = voice.voiceId
  3. Za kanale bez active voice:
     → isPlaying = false, activeVoiceId = null
  4. Čitaj SharedMeterReader za bus peaks
  5. Za playing kanale: approximate metering
     → peakL = busPeakL * (channel.volume / totalBusVolume)
     → peakR = busPeakR * (channel.volume / totalBusVolume)
  6. Peak hold decay (1500ms hold, linear decay)
  7. notifyListeners() samo ako se nešto promenilo
```

### Bidirekcioni sync — KRITIČNO

**Mixer → Composite Event (kad user pomeri fader):**
```
setChannelVolume(layerId, newVolume):
  1. Update _channels[layerId].volume
  2. Nađi parent composite event u middleware
  3. Update SlotEventLayer.volume u composite event via
     CompositeEventSystemProvider._updateEventLayerInternal()
     → Ovo automatski poziva _syncCompositeToMiddleware()
     → Što automatski poziva _syncEventToRegistry() via listener
  4. Ako voice trenutno svira (activeVoiceId != null):
     → AudioPlaybackService.setVoiceVolume(voiceId, newVolume)
     → REAL-TIME FFI, čuje se odmah
  5. notifyListeners()
```

**Composite Event → Mixer (kad se layer promeni iz drugog UI-ja):**
```
_onMiddlewareChanged():
  → Rebuild kanale iz composite events
  → Zadrži volume/pan/mute/solo ako je source == mixer (flag)
  → Ako je source != mixer, preuzmi nove vrednosti iz layer-a
```

### Solo logika (lokalna, NE persistira u layer)

```
toggleSolo(layerId):
  1. Toggle _channels[layerId].soloed
  2. Proveri: hasSoloActive = _channels.any((c) => c.soloed)
  3. Za svaku active voice:
     if hasSoloActive:
       → voice.soloed ? setVoiceMute(voiceId, false) : setVoiceMute(voiceId, true)
     else:
       → setVoiceMute(voiceId, channel.muted)  // restore original mute state
```

---

## Faza 2: SlotVoiceMixer Widget

### Layout specifikacija

```
┌─────────────────────────────────────────────────────────────────────────┐
│ SLOT VOICE MIXER                                         [🔍] [≡]     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│ ┌── SFX ──────────────────────┐ ┌── MUSIC ────────────┐ ┌── MST ──┐  │
│ │┌────┐┌────┐┌────┐┌────┐┌───┐│ │┌────┐┌────┐┌────┐  │ │┌──────┐ │  │
│ ││reel││reel││win ││anti││rol│| ││base││feat││free│   │ ││MASTER│ │  │
│ ││spin││stop││pres││cip ││lup│| ││game││ure ││spin│   │ ││      │ │  │
│ ││    ││    ││ent ││ati ││   │| ││    ││    ││    │   │ ││ INS  │ │  │
│ ││INS ││INS ││INS ││INS ││INS│| ││INS ││INS ││INS │   │ ││[LIM] │ │  │
│ ││[1] ││[1] ││[1] ││[1] ││[1]│| ││[1] ││[1] ││[1] │   │ ││[TPK] │ │  │
│ ││[2] ││[2] ││[2] ││[2] ││[2]│| ││[2] ││[2] ││[2] │   │ ││      │ │  │
│ ││    ││    ││    ││    ││   │| ││    ││    ││    │   │ ││ PAN  │ │  │
│ ││PAN ││PAN ││PAN ││PAN ││PAN│| ││PAN ││PAN ││PAN │   │ ││[─●─] │ │  │
│ ││[●─]││[─●]││[●──]│[──●]│[●─]| ││[─●─]│[─●─]│[─●─]│   │ ││      │ │  │
│ ││    ││    ││    ││    ││   │| ││    ││    ││    │   │ ││ ▐▌▐▌ │ │  │
│ ││▐▌▐▌││    ││    ││    ││   │| ││▐█▐█││    ││    │   │ ││ ▐█▐█ │ │  │
│ ││▐█▐█││    ││    ││    ││   │| ││▐█▐█││    ││    │   │ ││ ▐█▐█ │ │  │
│ ││═╤══││═╤══││═╤══││═╤══││═╤═│| ││═╤══││═╤══││═╤══│   │ ││══╤══│ │  │
│ ││ │  ││ │  ││ │  ││ │  ││ │ │| ││ │  ││ │  ││ │  │   │ ││  │  │ │  │
│ ││-6dB││0dB ││-3dB││-12 ││0dB│| ││-1dB││-inf││-inf│   │ ││0.0dB│ │  │
│ ││[M]S││[M]S││[M]S││[M]S││M S│| ││[M]S││[M]S││[M]S│   │ ││[M][S]│ │  │
│ ││SFX ││SFX ││SFX ││SFX ││SFX│| ││Mus ││Mus ││Mus │   │ ││OUT  │ │  │
│ ││ 🔄 ││    ││    ││    ││ 🔄│| ││ 🔄 ││    ││ 🔄 │   │ ││ 1-2 │ │  │
│ │└────┘└────┘└────┘└────┘└───┘│ │└────┘└────┘└────┘  │ │└──────┘ │  │
│ └─────────────────────────────┘ └─────────────────────┘ └─────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Header bar

```
[SLOT VOICE MIXER]  [channel count: 15]  [playing: 3]  [🔍 search]  [≡ group by bus/stage]
```

- Channel count: ukupno kanala
- Playing count: koliko trenutno svira (živo)
- Search: filter kanale po imenu
- Group toggle: grupiši po busu (default) ili po stage-u

### Per-channel strip — identičan kvalitet kao DAW UltimateMixer

Širina: 64px (regular), 56px (narrow mode)

Od vrha ka dnu:
1. **Color header** (24px) — bus boja + skraćeno ime + activity dot (zeleni puls kad svira)
2. **Insert section** (opciono, collapsible) — per-layer DSP chain slots
3. **Pan control** (28px) — horizontalni slider sa center indicator, dB readout, double-tap = center
4. **Fader + Meter** (expanded) — vertikalni fader sa FaderCurve + stereo L/R meter bars
5. **dB readout** (20px) — numeric display, crveni kad hot
6. **M/S buttons** (26px) — Mute (crveni) + Solo (žuti)
7. **Output label** (20px) — bus name + loop ikona ako looping

### Bus group separator

Vertikalna linija (2px) + bus name label iznad, između grupa kanala.
Master strip uvek poslednji, širi (80px).

### Activity indicator

Kad `isPlaying == true`:
- Header background pulsira (subtle glow animation)
- Meter bars se pale (real-time levels)
- dB readout prikazuje peak dB umesto fader dB

Kad `isPlaying == false`:
- Header statičan
- Meter bars prazni (tamna pozadina)
- dB readout prikazuje fader position

### Interactions

- **Fader drag** → `setChannelVolume()` → real-time FFI + composite sync
- **Pan drag** → `setChannelPan()` → real-time FFI + composite sync
- **Double-tap fader** → reset to 0dB (volume = 1.0)
- **Double-tap pan** → reset to center (pan = 0.0)
- **M button** → toggle mute → real-time FFI + composite sync
- **S button** → toggle solo → real-time FFI (local only, NE persistira)
- **Click header** → audition (preview zvuk jednom)
- **Right-click header** → context menu: rename, change bus, remove from event
- **Ctrl+click** → multi-select za batch operations

---

## Faza 3: Integracija u MIX Tab

### Modifikacija lower_zone_types.dart

```dart
// BEFORE:
enum SlotLabMixSubTab { buses, sends, pan, meter, hierarchy, ducking }

// AFTER:
enum SlotLabMixSubTab { voices, buses, sends, pan, meter, hierarchy, ducking }
```

`voices` je PRVI sub-tab (Q shortcut) — najvažniji, default kad se otvori MIX.

Extension update:
```dart
extension SlotLabMixSubTabX on SlotLabMixSubTab {
  String get label => ['Voices', 'Buses', 'Sends', 'Pan', 'Meter', 'Hierarchy', 'Ducking'][index];
  String get shortcut => ['Q', 'W', 'E', 'R', 'T', 'Y', 'U'][index];
  String get tooltip => [
    'Voice mixer — per-sound faders, mute/solo, real-time metering',
    'Bus mixer — per-bus faders, mute/solo',
    ...
  ][index];
}
```

### Wire u slotlab_lower_zone_widget.dart

```dart
// U _buildMixContent() switch:
SlotLabMixSubTab.voices => const SlotVoiceMixer(),
```

---

## Faza 4: Approximate Per-Voice Metering

Bez Rust promena. Aproksimacija:

```
Za svaki playing kanal na busu B:
  busPeakL = SharedMeterReader.channelPeaks[busIndex * 2]
  busPeakR = SharedMeterReader.channelPeaks[busIndex * 2 + 1]

  totalBusVoiceVolume = sum(channel.volume for channel in busChannels where isPlaying)

  channelPeakL = busPeakL * (channel.volume / max(totalBusVoiceVolume, 0.001))
  channelPeakR = busPeakR * (channel.volume / max(totalBusVoiceVolume, 0.001))
```

Peak hold: 1500ms hold, linear decay 0.02/frame — identično kao slotlab_bus_mixer.dart.

---

## Faza 5: Smart Features

### Audition Mode
- Click na channel header → `AudioPlaybackService.playFileToBus(audioPath, busId: channel.busId)`
- Pusti jednom za preview, nezavisno od slot mašine

### Snapshot Save/Load
```dart
class MixerSnapshot {
  Map<String, double> volumes;   // layerId → volume
  Map<String, double> pans;      // layerId → pan
  Map<String, bool> mutes;       // layerId → muted
  String name;
  DateTime created;
}
```
- Save: snapshot trenutnog stanja svih kanala
- Load: primeni snapshot — update composite events + active voices

### Solo in Context
- Solo kanal ali bus efekti (reverb, delay) i dalje čujni
- Implementacija: mute-uj samo druge voice-ove na ISTOM busu, ne sve

### Batch Operations
- Ctrl+click multi-select kanala
- Batch mute/solo/volume/pan change
- "Select all on bus" shortcut

### Search/Filter
- Text search u header baru — filter kanale po imenu
- Bus filter dropdown — prikaži samo SFX kanale, samo Music, etc.

---

## Faza 6 (Opciono): Real Per-Voice Metering (Rust upgrade)

### playback.rs promene:
```rust
pub struct OneShotVoice {
    // ... existing fields ...
    pub meter_peak_l: AtomicF64,  // NEW
    pub meter_peak_r: AtomicF64,  // NEW
}

// U audio callback, nakon voice procesiranja:
for voice in &mut self.voices {
    if voice.active {
        let peak_l = voice.output_l.iter().fold(0.0f32, |a, &b| a.max(b.abs()));
        let peak_r = voice.output_r.iter().fold(0.0f32, |a, &b| a.max(b.abs()));
        voice.meter_peak_l.store(peak_l as f64);
        voice.meter_peak_r.store(peak_l as f64);
    }
}
```

### ffi.rs nova funkcija:
```rust
#[no_mangle]
pub extern "C" fn engine_get_voice_peak_stereo(voice_id: u64, peak_l: *mut f64, peak_r: *mut f64) -> i32
```

### Dart FFI:
```dart
(double, double) getVoicePeakStereo(int voiceId)
```

---

## Redosled implementacije

| # | Faza | Opis | Fajlovi | Kompleksnost |
|---|------|------|---------|--------------|
| 1 | Provider | SlotVoiceMixerProvider — model, rebuild, sync, metering | 1 novi | Visoka |
| 2 | Widget | SlotVoiceMixer — strip UI, fader, pan, M/S, meters | 1 novi | Visoka |
| 3 | Integracija | MIX tab sub-tab + wire | 2 modifikacije | Niska |
| 4 | Metering | Approximate per-voice metering | U provideru | Srednja |
| 5 | Features | Audition, snapshot, solo-in-context, batch, search | U widgetu | Srednja |
| 6 | Rust metering | Real per-voice peaks (opciono) | 3 Rust fajla | Srednja |

---

## Kritična pravila

1. **NE mešati sa DAW mixerom** — ovo je potpuno odvojen sistem. DAW koristi MixerProvider + UltimateMixer. SlotLab koristi SlotVoiceMixerProvider + SlotVoiceMixer. Jedino deljeno: MixerDSPProvider za bus-level kontrolu i SharedMeterReader za metering.

2. **Source of truth = MiddlewareProvider.compositeEvents** — mixer ČITA layere odatle i PIŠE nazad kroz CompositeEventSystemProvider._updateEventLayerInternal().

3. **Solo je lokalni** — NE persistira u SlotEventLayer. Služi samo za real-time audition tokom miksovanja.

4. **Samo "Play" action layers** dobijaju strip — "Stop", "FadeOut", "SetVolume" su control actions, ne zvukovi.

5. **GetIt singleton pattern** — SlotVoiceMixerProvider se registruje kao lazy singleton u ServiceLocator, expose-uje preko ChangeNotifierProvider.value() u main.dart.

6. **Existing MIX sub-tabovi ostaju** — buses, sends, pan, meter, hierarchy, ducking. Voices je DODATAK, ne zamena.

7. **Bus master strip u voice mixeru** — poslednji strip (Master) iz MixerDSPProvider, širi, sa limiter/true peak. Služi kao referenca za ukupni nivo.
