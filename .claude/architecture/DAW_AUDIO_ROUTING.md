# DAW Audio Routing Architecture

## Overview

FluxForge Studio ima dve odvojene mixer arhitekture koje služe različitim sektorima aplikacije:

| Provider | Sektor | FFI Povezanost | Namena |
|----------|--------|----------------|--------|
| **MixerProvider** | DAW | ✅ Potpuno | Timeline playback, track routing |
| **MixerDSPProvider** | Middleware/SlotLab | ✅ Potpuno | Event-based audio, bus mixing |

---

## 1. MixerProvider (DAW Section)

**Lokacija:** `flutter_ui/lib/providers/mixer_provider.dart`

### Funkcionalnost

Profesionalni DAW mixer sa:
- Dinamički kreirani kanali (tracks)
- 6 buseva (UI, SFX, Music, VO, Ambient, Master)
- Aux sends/returns
- VCA faders
- Groups
- Real-time metering

### FFI Konekcije

```dart
// Track volume → Rust engine
NativeFFI.instance.setTrackVolume(trackIndex, volume);

// Bus volume → Rust engine
engine.setBusVolume(busEngineId, volume);

// Bus pan → Rust engine
engine.setBusPan(busEngineId, pan);

// Track mute/solo → Rust engine
NativeFFI.instance.setTrackMute(trackIndex, muted);
NativeFFI.instance.setTrackSolo(trackIndex, solo);

// Bus mute/solo → Rust engine
NativeFFI.instance.mixerSetBusMute(busEngineId, muted);
NativeFFI.instance.mixerSetBusSolo(busEngineId, solo);

// Master volume → Rust engine
engine.setMasterVolume(volume);
```

### Bus Engine ID Mapping

```dart
int _getBusEngineId(String busId) {
  switch (busId) {
    case 'bus_ui': return 0;
    case 'bus_sfx': return 1;
    case 'bus_music': return 2;
    case 'bus_vo': return 3;
    case 'bus_ambient': return 4;
    case 'master': return 5;
    default: return 1; // Default to SFX
  }
}
```

---

## 2. MixerDSPProvider (Middleware/SlotLab Section)

**Lokacija:** `flutter_ui/lib/providers/mixer_dsp_provider.dart`

### Funkcionalnost

Event-based audio mixing za:
- Slot Lab preview
- Middleware event triggering
- Bus volume/pan control
- Insert chain management

### FFI Konekcije (UPDATED 2026-01-20)

```dart
// Bus volume → Rust engine
_ffi.setBusVolume(engineIdx, volume);

// Bus pan → Rust engine
_ffi.setBusPan(engineIdx, pan);

// Bus mute → Rust engine
_ffi.setBusMute(engineIdx, muted);

// Bus solo → Rust engine
_ffi.setBusSolo(engineIdx, solo);
```

### Bus Engine ID Mapping

```dart
int _busIdToEngineIndex(String busId) {
  return switch (busId) {
    'sfx' => 0,
    'music' => 1,
    'voice' => 2,
    'ambience' => 3,
    'aux' => 4,
    'master' => 5,
    _ => 0, // Default to SFX
  };
}
```

### Default Buses

```dart
const List<MixerBus> kDefaultBuses = [
  MixerBus(id: 'master', name: 'Master', volume: 0.85),
  MixerBus(id: 'music', name: 'Music', volume: 0.7),
  MixerBus(id: 'sfx', name: 'SFX', volume: 0.9),
  MixerBus(id: 'ambience', name: 'Ambience', volume: 0.5),
  MixerBus(id: 'voice', name: 'Voice', volume: 0.95),
];
```

---

## 3. Audio Playback Flow

### DAW Timeline Playback

```
Track → MixerProvider.channel → NativeFFI.setTrackVolume()
                              → NativeFFI.setTrackPan()
                              → Engine applies processing
                              → Master bus → Audio output
```

### Event Registry (Middleware/SlotLab)

```
Stage Event → EventRegistry.triggerStage()
           → AudioPlaybackService.playFileToBus()
           → NativeFFI.playbackPlayToBus(path, volume, pan, busId)
           → Engine routes to bus
           → MixerDSPProvider bus settings applied
           → Master bus → Audio output
```

---

## 4. Rust FFI Functions

### Bus Control (native_ffi.dart:5565-5620)

| Dart Method | FFI Function | Parameters |
|-------------|--------------|------------|
| `setBusVolume(idx, vol)` | `engine_set_bus_volume` | int busIdx, double volume |
| `setBusPan(idx, pan)` | `engine_set_bus_pan` | int busIdx, double pan |
| `setBusMute(idx, muted)` | `engine_set_bus_mute` | int busIdx, bool muted |
| `setBusSolo(idx, solo)` | `engine_set_bus_solo` | int busIdx, bool solo |

### Playback to Bus

| Dart Method | FFI Function | Parameters |
|-------------|--------------|------------|
| `playbackPlayToBus()` | `playback_play_to_bus` | path, volume, pan, busId |
| `playbackPlayLoopingToBus()` | `playback_play_looping_to_bus` | path, volume, pan, busId |
| `playbackStopOneShot()` | `playback_stop_one_shot` | voiceId |

---

## 5. Insert Chain Architecture

Svaki kanal ima 8 insert slotova:
- **Pre-fader (0-3):** Procesiranje pre volume fadera
- **Post-fader (4-7):** Procesiranje posle volume fadera

### MixerDSPProvider Insert Management (UPDATED 2026-01-20)

Insert management je sada potpuno povezan sa Rust engine-om:

```dart
// addInsert() — kreira processor u engine-u
_ffi.insertCreateChain(trackId);
_ffi.insertLoadProcessor(trackId, slotIndex, processorName);

// removeInsert() — unload-uje processor
_ffi.insertUnloadSlot(trackId, slotIndex);

// toggleBypass() — bypass state
_ffi.insertSetBypass(trackId, slotIndex, bypassed);

// updateInsertParams() — parameter sync
_ffi.insertSetParam(trackId, slotIndex, paramIndex, value);
```

### Plugin ID to Processor Name Mapping

```dart
const mapping = {
  // Modern Digital
  'rf-eq': 'pro-eq',
  'rf-compressor': 'compressor',
  'rf-limiter': 'limiter',
  'rf-reverb': 'reverb',
  'rf-delay': 'delay',
  'rf-gate': 'gate',
  'rf-saturator': 'saturator',
  'rf-deesser': 'deesser',
  // Vintage Analog EQs
  'rf-pultec': 'pultec',
  'rf-api550': 'api550',
  'rf-neve1073': 'neve1073',
};
```

### Dostupni Plugins

| Plugin ID | Rust Processor | Kategorija | Opis |
|-----------|----------------|------------|------|
| `rf-eq` | `pro-eq` | EQ | 64-band parametric |
| `rf-pultec` | `pultec` | EQ | Pultec EQP-1A tube EQ |
| `rf-api550` | `api550` | EQ | API 550A discrete EQ |
| `rf-neve1073` | `neve1073` | EQ | Neve 1073 inductor EQ |
| `rf-compressor` | `compressor` | Dynamics | Transparent compressor |
| `rf-limiter` | `limiter` | Dynamics | True peak limiter |
| `rf-reverb` | `reverb` | Time | Algorithmic reverb |
| `rf-delay` | `delay` | Time | Tempo-synced delay |
| `rf-gate` | `gate` | Dynamics | Noise gate |
| `rf-saturator` | `saturator` | Distortion | Tape saturation |
| `rf-deesser` | `deesser` | Dynamics | Sibilance control |

---

## 5.1 Vintage Analog EQ Architecture (ADDED 2026-01-20)

Tri vintage EQ emulacije sa potpunom FFI integracijom kroz InsertProcessor sistem:

### Pultec EQP-1A

**Rust:** `rf-dsp/src/eq_analog.rs` → `PultecEqp1a`
**Wrapper:** `rf-engine/src/dsp_wrappers.rs` → `PultecWrapper`

| Parameter | Index | Range | Opis |
|-----------|-------|-------|------|
| `lowBoost` | 0 | 0-10 dB | Low frequency boost |
| `lowAtten` | 1 | 0-10 dB | Low frequency attenuation |
| `highBoost` | 2 | 0-10 dB | High frequency boost |
| `highAtten` | 3 | 0-10 dB | High frequency attenuation |

**Karakteristike:**
- Passive tube design (12AX7 saturation)
- Simultaneous boost+cut (legendary "Pultec trick")
- Output transformer saturation
- 20/30/60/100 Hz low freq selection
- 3/4/5/8/10/12/16 kHz high freq selection

### API 550A

**Rust:** `rf-dsp/src/eq_analog.rs` → `Api550`
**Wrapper:** `rf-engine/src/dsp_wrappers.rs` → `Api550Wrapper`

| Parameter | Index | Range | Opis |
|-----------|-------|-------|------|
| `lowGain` | 0 | ±12 dB | Low band gain |
| `midGain` | 1 | ±12 dB | Mid band gain |
| `highGain` | 2 | ±12 dB | High band gain |

**Karakteristike:**
- Proportional Q (bandwidth narrows with gain)
- Discrete 2520 op-amp saturation
- 5 selectable frequencies per band
- Low: 50/100/200/400/800 Hz
- Mid: 200/400/800/1.5k/3k Hz
- High: 2.5k/5k/7.5k/10k/12.5k Hz

### Neve 1073

**Rust:** `rf-dsp/src/eq_analog.rs` → `Neve1073`
**Wrapper:** `rf-engine/src/dsp_wrappers.rs` → `Neve1073Wrapper`

| Parameter | Index | Range | Opis |
|-----------|-------|-------|------|
| `hpEnabled` | 0 | 0/1 | High-pass filter on/off |
| `lowGain` | 1 | ±16 dB | Low shelf gain |
| `highGain` | 2 | ±16 dB | High shelf gain |

**Karakteristike:**
- Inductor-based filters (LC resonance)
- Dual transformer saturation (input + output)
- Iron core saturation modeling
- HP: 50/80/160/300 Hz
- Low shelf: 35/60/110/220 Hz
- High shelf: 10k/12k Hz

### Vintage EQ Signal Flow

```
Input → HP Filter (Neve only) → Low Band → Mid Band → High Band → Tube/Transformer Saturation → Output
```

### UI Widget ↔ MixerDSPProvider ↔ Rust Engine Flow

```
UI Widget (pultec_eq.dart)
    │
    ▼ onParamsChanged(params)
MixerDSPProvider.updateInsertParams(busId, insertId, params)
    │
    ▼ _getParamIndexMapping() → index
    ▼ _ffi.insertSetParam(trackId, slotIndex, paramIndex, value)
Rust InsertProcessor.set_param(index, value)
    │
    ▼ PultecWrapper/Api550Wrapper/Neve1073Wrapper
DSP Processing (eq_analog.rs)
```

---

## 6. Signal Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        FLUTTER UI                                │
├─────────────────────────────────────────────────────────────────┤
│  MixerProvider (DAW)        │  MixerDSPProvider (Middleware)    │
│  - Track channels           │  - Bus controls                   │
│  - Bus routing              │  - Insert chains                  │
│  - VCA/Groups               │  - Event mixing                   │
├─────────────────────────────────────────────────────────────────┤
│                         FFI BRIDGE                               │
│  NativeFFI.setBusVolume()   │  NativeFFI.playbackPlayToBus()    │
│  NativeFFI.setBusPan()      │  NativeFFI.playbackStopOneShot()  │
│  NativeFFI.setBusMute()     │                                   │
├─────────────────────────────────────────────────────────────────┤
│                      RUST ENGINE                                 │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐            │
│  │ Track 1 │→ │ Bus SFX │→ │ Inserts │→ │         │            │
│  └─────────┘  └─────────┘  └─────────┘  │         │            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  │ MASTER  │→ OUTPUT    │
│  │ Track 2 │→ │Bus Music│→ │ Inserts │→ │         │            │
│  └─────────┘  └─────────┘  └─────────┘  │         │            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  │         │            │
│  │ OneShot │→ │ Bus VO  │→ │ Inserts │→ │         │            │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 7. Metering Integration

MixerProvider se pretplaćuje na metering stream iz Rust engine-a:

```dart
void _subscribeToMetering() {
  _meteringSub = engine.meteringStream.listen(_updateMeters);
}

void _updateMeters(MeteringState metering) {
  // Update master meters
  _master = _master.copyWith(
    peakL: _dbToLinear(metering.masterPeakL),
    peakR: _dbToLinear(metering.masterPeakR),
    rmsL: _dbToLinear(metering.masterRmsL),
    rmsR: _dbToLinear(metering.masterRmsR),
  );

  // Update channel meters from bus metering
  for (final channel in _channels.values) {
    if (channel.trackIndex != null) {
      final trackMeter = metering.buses[channel.trackIndex!];
      _channels[channel.id] = channel.copyWith(
        peakL: _dbToLinear(trackMeter.peakL),
        peakR: _dbToLinear(trackMeter.peakR),
      );
    }
  }
}
```

---

## 8. Changelog

### 2026-01-20 (Update 4 — Plugin Fake Data Removal)
- **KRITIČNO: Uklonjeni svi simulirani/lažni podaci iz pluginova**
  - `FabFilterCompressorPanel._updateMeters()` — uklonjen `math.Random()` za input level
  - `FabFilterLimiterPanel._updateMeters()` — uklonjen `math.Random()` za input/LUFS
  - `SpectrumAnalyzerDemo` — pretvoren u empty analyzer (nema fake spektra)
  - `ProEqEditor._updateSpectrum()` — uklonjen FALLBACK simulirani spektar
- **Dokumentovana arhitektonska disconnect** (sekcija 10)
  - COMPRESSORS, LIMITERS, PRO_EQS HashMap-ovi NISU u audio path-u
  - Jedini pravi audio processing: PLAYBACK_ENGINE InsertChain
  - Pluginovi će prikazivati podatke tek kada budu spojeni sa InsertChain

### 2026-01-20 (Update 3 — Lower Zone EQ Fix)
- **KRITIČNO: Lower Zone EQ sada procesira audio**
  - `_buildProEqContent()` prepravljen da koristi `NativeFFI.eqSetBand*()` umesto `engineApi.proEqSetBand*()`
  - Stari sistem (`PRO_EQS` HashMap) se nikad nije procesirao u audio thread-u
  - Novi sistem koristi `PLAYBACK_ENGINE.set_track_insert_param()` → lock-free ring buffer → audio callback
  - TrackId 0 = Master channel za Lower Zone EQ
- **Dokumentovana sva tri EQ sistema** (sekcija 9)
  - PLAYBACK_ENGINE InsertChain (PREPORUČENO)
  - DspCommand Queue (alternativa)
  - PRO_EQS HashMap (DEPRECIRAN — ne koristiti!)

### 2026-01-20 (Update 2)
- **Vintage Analog EQ integracija u MixerDSPProvider**
  - Dodati Pultec EQP-1A, API 550A, Neve 1073 u `kAvailablePlugins`
  - `_pluginIdToProcessorName()` prošireno: rf-pultec→pultec, rf-api550→api550, rf-neve1073→neve1073
  - `_getParamIndexMapping()` dodato za sve vintage EQ parametre
  - `_getDefaultParams()` dodato sa default vrednostima
  - Potpuna FFI integracija kroz InsertProcessor sistem

### 2026-01-20
- **MixerDSPProvider povezan sa Rust FFI**
  - `setBusVolume()` → `engine_set_bus_volume`
  - `setBusPan()` → `engine_set_bus_pan`
  - `toggleMute()` → `engine_set_bus_mute`
  - `toggleSolo()` → `engine_set_bus_solo`
  - `connect()` sada sinhronizuje sve buseve sa engine-om

### Prethodno
- MixerProvider potpuno funkcionalan
- Insert chain arhitektura implementirana
- Metering integracija aktivna

---

## 9. EQ Processing Systems — KRITIČNA DOKUMENTACIJA

⚠️ **UPOZORENJE**: Postoje **TRI ODVOJENA EQ SISTEMA** u codebase-u! Korišćenje pogrešnog sistema znači da EQ neće procesirati audio.

### 9.1 Pregled sistema

| Sistem | Lokacija | Audio Processing | Korišćenje |
|--------|----------|------------------|------------|
| **PLAYBACK_ENGINE InsertChain** | `rf-engine/src/playback.rs` | ✅ DA | Lower Zone EQ, DAW track inserts |
| **DspCommand Queue** | `rf-bridge/src/playback.rs` | ✅ DA | EqProvider (alternativni pristup) |
| **PRO_EQS HashMap** | `rf-engine/src/ffi.rs` | ❌ NE | DEPRECIRAN - NE KORISTITI! |

### 9.2 PLAYBACK_ENGINE InsertChain (PREPORUČENO)

**Lokacija:** `crates/rf-engine/src/playback.rs`

Ovo je **glavni sistem** za DAW audio processing. Koristi lock-free ring buffer za UI→Audio komunikaciju.

```rust
// UI Thread (Flutter via FFI)
PLAYBACK_ENGINE.set_track_insert_param(track_id, slot_index, param_index, value);
    ↓
// Ring Buffer (rtrb)
InsertParamChange pushed to queue
    ↓
// Audio Thread
consume_insert_param_changes() → applies to InsertChain
    ↓
// Audio Processing
InsertChain.process() → ProEqWrapper.process_stereo()
```

**FFI Funkcije (rf-engine/src/ffi.rs:4880-4974):**

| FFI Function | Param Index | Opis |
|--------------|-------------|------|
| `eq_set_band_enabled(track, band, enabled)` | band*11+3 | Enable/disable band |
| `eq_set_band_frequency(track, band, freq)` | band*11+0 | Set frequency Hz |
| `eq_set_band_gain(track, band, gain)` | band*11+1 | Set gain dB |
| `eq_set_band_q(track, band, q)` | band*11+2 | Set Q factor |
| `eq_set_band_shape(track, band, shape)` | band*11+4 | Set filter shape |
| `eq_set_bypass(track, bypass)` | - | Global bypass |

**Dart Wrappers (native_ffi.dart:4303-4337):**
```dart
NativeFFI.instance.eqSetBandEnabled(trackId, bandIndex, enabled);
NativeFFI.instance.eqSetBandFrequency(trackId, bandIndex, freq);
NativeFFI.instance.eqSetBandGain(trackId, bandIndex, gain);
NativeFFI.instance.eqSetBandQ(trackId, bandIndex, q);
NativeFFI.instance.eqSetBandShape(trackId, bandIndex, shape);
NativeFFI.instance.eqSetBypass(trackId, bypass);
```

**TrackId Mapping:**
- `0` = Master channel (koristi se za Lower Zone)
- `1-N` = Individual tracks

### 9.3 DspCommand Queue (ALTERNATIVA)

**Lokacija:** `crates/rf-bridge/src/command_queue.rs`, `crates/rf-bridge/src/playback.rs`

Drugi sistem koji koristi `DspCommand` enum i `DspStorage` → `TrackDsp` → `ProEqWrapper`.

```rust
// UI Thread
send_command(DspCommand::EqSetGain { track_id, band_index, gain_db });
    ↓
// Command Queue (rtrb)
UiCommandHandle.command_producer.push(cmd)
    ↓
// Audio Thread (rf-bridge/src/playback.rs:1790-1802)
audio_command_handle().poll_commands()
    ↓
dsp_storage.process_command(cmd)
    ↓
TrackDsp.pro_eq.set_param(...)
    ↓
// Audio Processing (rf-bridge/src/playback.rs:1887-1892)
master_dsp.process(left, right)
```

**Dart (EqProvider koristi ovo):**
```dart
// flutter_ui/lib/providers/eq_provider.dart:373-378
ffi.eqSetBandEnabled(trackId, i, band.enabled);
ffi.eqSetBandFrequency(trackId, i, band.frequency);
ffi.eqSetBandGain(trackId, i, band.gainDb);
ffi.eqSetBandQ(trackId, i, band.q);
ffi.eqSetBandShape(trackId, i, band.filterType.index);
```

### 9.4 PRO_EQS HashMap (⚠️ DEPRECIRAN — NE KORISTITI!)

**Lokacija:** `crates/rf-engine/src/ffi.rs:9374-9796`

```rust
lazy_static! {
    static ref PRO_EQS: RwLock<HashMap<u32, ProEq>> = ...;
}
```

**PROBLEM**: Ovaj sistem **NIKAD ne procesira audio**! Funkcije `pro_eq_set_band_*` samo ažuriraju HashMap, ali `pro_eq_process()` se **NIKAD ne poziva** iz audio callback-a.

**Depreciran FFI (NE KORISTITI):**
```dart
// ❌ OVO NE RADI - audio se ne procesira!
engineApi.proEqSetBandEnabled(trackId, bandIndex, enabled);
engineApi.proEqSetBandFrequency(trackId, bandIndex, freq);
engineApi.proEqSetBandGain(trackId, bandIndex, gain);
// ...
```

### 9.5 Lower Zone EQ Implementation (FIXED 2026-01-20)

**Lokacija:** `flutter_ui/lib/screens/engine_connected_layout.dart:8315-8388`

Lower Zone EQ (`_buildProEqContent`) sada koristi **PLAYBACK_ENGINE InsertChain** sistem:

```dart
Widget _buildProEqContent(dynamic metering, bool isPlaying) {
  final ffi = NativeFFI.instance;

  return ProEqEditor(
    trackId: 'master',
    onBandChange: (bandIndex, {enabled, freq, gain, q, filterType, ...}) {
      const trackId = 0;  // Master in InsertChain
      if (enabled != null) ffi.eqSetBandEnabled(trackId, bandIndex, enabled);
      if (freq != null) ffi.eqSetBandFrequency(trackId, bandIndex, freq);
      if (gain != null) ffi.eqSetBandGain(trackId, bandIndex, gain);
      if (q != null) ffi.eqSetBandQ(trackId, bandIndex, q);
      if (filterType != null) ffi.eqSetBandShape(trackId, bandIndex, filterType);
    },
    onBypassChange: (bypass) => ffi.eqSetBypass(0, bypass),
  );
}
```

### 9.6 Kada koji sistem koristiti

| Use Case | Sistem | Primer |
|----------|--------|--------|
| **Lower Zone EQ** | PLAYBACK_ENGINE | `ffi.eqSetBandGain(0, band, gain)` |
| **DAW Track Inserts** | PLAYBACK_ENGINE | `ffi.eqSetBandGain(trackId, band, gain)` |
| **EqProvider state** | DspCommand | Interno preko `eqSetBand*` FFI |
| **Middleware Inserts** | MixerDSPProvider | `insertSetParam()` |

### 9.7 Debugging EQ Issues

1. **EQ ne procesira audio?**
   - Proveri da li koristiš `eqSetBand*` (radi) umesto `proEqSetBand*` (ne radi)
   - TrackId 0 = master, 1+ = tracks

2. **Promena parametara nema efekat?**
   - Proveri da li je audio playing (EQ se procesira samo za aktivan audio)
   - Proveri konzolu za `[EQ] Queued param:` log poruke

3. **Signal level u Lower Zone ali nema zvuka?**
   - Koristiš pogrešan sistem (PRO_EQS umesto InsertChain)

---

## 10. Verifikacija

Za testiranje FFI konekcije:

1. Pokreni app
2. Otvori Middleware sekciju
3. Pomeri bus volume slider
4. Proveri konzolu za `[MixerDSPProvider]` log poruke
5. Zvuk bi trebalo da se promeni u skladu sa slider-om

Za testiranje Lower Zone EQ:

1. Pokreni app
2. Importuj audio u DAW
3. Pokreni playback
4. Otvori Lower Zone → Process → EQ
5. Dodaj band, pomeri gain
6. Audio bi trebalo da se menja
7. Konzola: `[EQ] Queued param: track=0, slot=0, param=X, value=Y`

---

## 10. DSP System Disconnect — KRITIČNA ARHITEKTONSKA DOKUMENTACIJA

⚠️ **UPOZORENJE**: Postoje **PARALELNI DSP SISTEMI** koji nisu povezani!

### 10.1 Pregled problema

UI pluginovi (Compressor, Limiter, Spectrum) kreiraju procesore u **HashMap-ovima** koji se **NIKADA NE POZIVAJU** u audio callback-u.

```
┌─────────────────────────────────────────────────────────────────┐
│ FLUTTER UI PLUGINOVI → HashMap-ovi (NE PROCESIRAJU AUDIO!)      │
├─────────────────────────────────────────────────────────────────┤
│ FabFilterCompressorPanel                                        │
│   └→ compressorCreate() → COMPRESSORS HashMap                   │
│      └→ NIKAD se ne poziva u audio callback                     │
│                                                                  │
│ FabFilterLimiterPanel                                           │
│   └→ limiterCreate() → LIMITERS HashMap                         │
│      └→ NIKAD se ne poziva u audio callback                     │
│                                                                  │
│ ProEqEditor (stari sistem)                                      │
│   └→ proEqSetBand*() → PRO_EQS HashMap                         │
│      └→ NIKAD se ne poziva u audio callback                     │
│                                                                  │
│ SpectrumAnalyzerDemo                                            │
│   └→ Generisao RANDOM FAKE spektar (sada uklonjeno)            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ PRAVI AUDIO PATH (rf-engine/playback.rs)                        │
├─────────────────────────────────────────────────────────────────┤
│ PLAYBACK_ENGINE.process()                                       │
│   ├→ read_clip_audio()         ← čita audio iz timeline         │
│   ├→ InsertChain.process_pre_fader()  ← JEDINI DSP KOJI RADI   │
│   ├→ volume/pan                                                 │
│   ├→ InsertChain.process_post_fader()                          │
│   ├→ bus routing                                                │
│   └→ master inserts                                             │
│                                                                  │
│ PLAYBACK_ENGINE InsertChain:                                    │
│   - Koristi set_track_insert_param() za update parametre        │
│   - Lock-free ring buffer za UI→Audio komunikaciju              │
│   - Procesori učitani preko load_track_insert()                │
└─────────────────────────────────────────────────────────────────┘
```

### 10.2 Nepovezani HashMap-ovi

| HashMap | Lokacija | Kreiran od | U Audio Path? |
|---------|----------|------------|---------------|
| `COMPRESSORS` | `ffi.rs:8044` | FabFilterCompressorPanel | ❌ NE |
| `LIMITERS` | `ffi.rs:8046` | FabFilterLimiterPanel | ❌ NE |
| `PRO_EQS` | `ffi.rs:9374` | ProEqEditor (stari) | ❌ NE |
| `MULTIBAND_COMPRESSORS` | `ffi.rs:8834` | — | ❌ NE |
| `MULTIBAND_LIMITERS` | `ffi.rs:8836` | — | ❌ NE |
| `SPECTRAL_COMPRESSORS` | `ffi.rs:10303` | — | ❌ NE |

### 10.3 Posledice

1. **Signal bez playback-a**: Pluginovi su koristili `math.Random()` za simulaciju (sada uklonjeno)
2. **Nema efekta na audio**: Parametri se čuvaju ali nikad ne procesiraju
3. **Metering bez veze**: UI čita metering iz PLAYBACK_ENGINE ali pluginovi nisu u tom path-u

### 10.4 Ispravni način konekcije

Za pluginove koji trebaju procesirati audio:

```dart
// ISPRAVNO: Koristi InsertChain sistem
final ffi = NativeFFI.instance;
ffi.eqSetBandGain(trackId, bandIndex, gain);  // → InsertChain

// POGREŠNO: Ide u HashMap koji se ne procesira
ffi.compressorCreate(trackId, sampleRate);    // → COMPRESSORS HashMap
ffi.compressorSetThreshold(trackId, db);      // → čuva se, ne procesira
```

### 10.5 Buduće rešenje

Da bi Compressor/Limiter/itd. zaista procesirali audio:

1. **Opcija A**: Spojiti HashMap-ove sa InsertChain
   - Pozivati `COMPRESSORS.process()` u `InsertChain.process()`
   - Kompleksna refaktorizacija

2. **Opcija B**: Koristiti InsertChain DSP Wrapper
   - Kreirati `CompressorWrapper` kao `InsertProcessor`
   - Učitati ga u `InsertChain` preko `load_track_insert()`
   - Parametri idu kroz `set_track_insert_param()`

3. **Opcija C**: Middleware DSP sistem
   - MixerDSPProvider već koristi InsertChain
   - Dodati Compressor/Limiter kao middleware inserts

### 10.6 Trenutno stanje pluginova

| Plugin | Signal Display | Audio Processing |
|--------|----------------|------------------|
| **ProEqEditor** | Prazan (no fake data) | ✅ Radi preko InsertChain |
| **FabFilterCompressor** | -60dB (silence) | ❌ HashMap nije u path-u |
| **FabFilterLimiter** | -60dB (silence) | ❌ HashMap nije u path-u |
| **SpectrumAnalyzer** | Prazan | ❌ Nema FFT metering iz engine-a |

---

## 11. Bus InsertChain System (ADDED 2026-01-20)

### 11.1 Pregled

Busevi sada imaju vlastite InsertChain nizove, odvojene od track InsertChain-ova:

```rust
// playback.rs
pub struct PlaybackEngine {
    // Track inserts (per track)
    insert_chains: RwLock<HashMap<u64, InsertChain>>,

    // Bus inserts (6 buses: 0=Master, 1=Music, 2=Sfx, 3=Voice, 4=Amb, 5=Aux)
    bus_inserts: RwLock<[InsertChain; 6]>,

    // Master insert (separate for backward compat)
    master_insert: RwLock<InsertChain>,
}
```

### 11.2 Bus IDs

| Bus ID | Ime | Korišćenje |
|--------|-----|------------|
| 0 | Master | Final output processing |
| 1 | Music | Music tracks routing |
| 2 | SFX | Sound effects |
| 3 | Voice | Dialog/voiceover |
| 4 | Amb | Ambience/backgrounds |
| 5 | Aux/UI | UI sounds, auxiliary |

### 11.3 FFI Funkcije za Bus InsertChain

**Rust FFI (rf-engine/src/ffi.rs):**

| FFI Function | Parametri | Opis |
|--------------|-----------|------|
| `bus_insert_load_processor` | bus_id, slot, name | Učitaj DSP processor |
| `bus_insert_unload_slot` | bus_id, slot | Ukloni processor iz slota |
| `bus_insert_set_param` | bus_id, slot, param, value | Postavi parametar |
| `bus_insert_get_param` | bus_id, slot, param | Čitaj parametar |
| `bus_insert_set_bypass` | bus_id, slot, bypass | Toggle bypass |
| `bus_insert_set_mix` | bus_id, slot, mix | Dry/wet mix |
| `bus_insert_is_loaded` | bus_id, slot | Proveri da li je processor učitan |

**Dart Wrappers (native_ffi.dart):**

```dart
// Load processor into bus slot
NativeFFI.instance.busInsertLoadProcessor(busId, slotIndex, 'pro-eq');

// Set parameter
NativeFFI.instance.busInsertSetParam(busId, slotIndex, paramIndex, value);

// Toggle bypass
NativeFFI.instance.busInsertSetBypass(busId, slotIndex, true);

// Check if loaded
bool isLoaded = NativeFFI.instance.busInsertIsLoaded(busId, slotIndex);
```

### 11.4 Audio Callback Processing

```rust
// Audio callback (playback.rs ~line 1450)
fn audio_callback(&self, data: &mut [f32], channels: usize) {
    // 1. Process tracks
    for (track_id, track) in tracks {
        // Track InsertChain pre-fader
        insert_chain.process_pre_fader(&mut left, &mut right);
        // Volume/pan
        apply_volume_pan(&mut left, &mut right, volume, pan);
        // Track InsertChain post-fader
        insert_chain.process_post_fader(&mut left, &mut right);
        // Route to bus
        bus_buffers[bus_id].add(left, right);
    }

    // 2. Process bus InsertChains
    for bus_id in 0..6 {
        let bus_insert = &mut bus_inserts[bus_id];
        // Pre-fader
        bus_insert.process_pre_fader(&mut bus_l, &mut bus_r);
        // Bus volume/pan
        apply_bus_volume_pan(&mut bus_l, &mut bus_r);
        // Post-fader
        bus_insert.process_post_fader(&mut bus_l, &mut bus_r);
        // Sum to master
        master_l += bus_l;
        master_r += bus_r;
    }

    // 3. Master insert processing
    master_insert.process(&mut master_l, &mut master_r);
}
```

### 11.5 UI Routing (engine_connected_layout.dart)

UI koristi helper funkcije za rutiranje na odgovarajuće FFI:

```dart
bool _isBusChannel(String busId) {
  return busId == 'master' || busId == 'sfx' || busId == 'music' ||
         busId == 'voice' || busId == 'amb' || busId == 'ui';
}

int _getBusId(String busId) {
  switch (busId) {
    case 'master': return 0;
    case 'music': return 1;
    case 'sfx': return 2;
    case 'voice': return 3;
    case 'amb': return 4;
    case 'ui': return 5;
    default: return 0;
  }
}

// Usage in EQ routing
void _routeEqParam(String channelId, int slot, int param, double value) {
  if (_isBusChannel(channelId)) {
    final busId = _getBusId(channelId);
    NativeFFI.instance.busInsertSetParam(busId, slot, param, value);
  } else {
    final trackId = _busIdToTrackId(channelId);
    NativeFFI.instance.insertSetParam(trackId, slot, param, value);
  }
}
```

### 11.6 Signal Flow sa Bus InsertChain

```
┌─────────────────────────────────────────────────────────────────┐
│                    COMPLETE SIGNAL FLOW                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Audio Files → Track Clips → Track InsertChain (pre/post)       │
│                    │                                             │
│                    ▼ Route to Bus                                │
│  ┌─────────────────────────────────────────────┐                │
│  │            BUS INSERTCHAIN                   │                │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐           │                │
│  │  │Slot0│→│Slot1│→│Slot2│→│Slot3│ (Pre)     │                │
│  │  └─────┘ └─────┘ └─────┘ └─────┘           │                │
│  │            │                                 │                │
│  │            ▼ Bus Volume/Pan                  │                │
│  │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐           │                │
│  │  │Slot4│→│Slot5│→│Slot6│→│Slot7│ (Post)    │                │
│  │  └─────┘ └─────┘ └─────┘ └─────┘           │                │
│  └─────────────────────────────────────────────┘                │
│                    │                                             │
│                    ▼ Sum to Master                               │
│  ┌─────────────────────────────────────────────┐                │
│  │         MASTER INSERTCHAIN                   │                │
│  │  EQ → Compressor → Limiter → Output         │                │
│  └─────────────────────────────────────────────┘                │
│                    │                                             │
│                    ▼                                             │
│              AUDIO OUTPUT                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 12. Sledći koraci

1. ✅ Ukloniti lažne podatke iz svih pluginova
2. ✅ **Bus InsertChain sistem implementiran** (2026-01-20)
   - Rust: bus_inserts array, FFI functions, audio callback processing
   - Dart: FFI bindings (busInsertXxx methods)
   - UI: Routing logic za bus vs track channels
3. ⏳ Spojiti Compressor/Limiter sa InsertChain sistemom
4. ⏳ Dodati FFT metering iz PLAYBACK_ENGINE za SpectrumAnalyzer
5. ⏳ Unificirati sve DSP u jedan InsertChain sistem
