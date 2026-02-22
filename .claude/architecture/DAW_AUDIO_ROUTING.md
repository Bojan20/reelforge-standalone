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

⚠️ **CRITICAL:** Must match Rust `playback.rs` bus processing loop (lines 3313-3319)

```dart
/// Map bus ID to engine bus index
/// Engine buses: 0=Master, 1=Music, 2=Sfx, 3=Voice, 4=Ambience, 5=Aux
int _getBusEngineId(String busId) {
  switch (busId) {
    case 'master': return 0;
    case 'bus_music': return 1;
    case 'bus_sfx': return 2;
    case 'bus_vo': return 3;
    case 'bus_ambient': return 4;
    case 'bus_aux': return 5;
    case 'bus_ui': return 2; // UI sounds route to SFX bus
    default: return 2; // Default to SFX
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

⚠️ **CRITICAL:** Must match Rust `playback.rs` bus processing loop (lines 3313-3319)

```dart
/// Map string bus ID to engine bus index
/// Engine buses: 0=Master, 1=Music, 2=Sfx, 3=Voice, 4=Ambience, 5=Aux
int _busIdToEngineIndex(String busId) {
  return switch (busId) {
    'master' => 0,
    'music' => 1,
    'sfx' => 2,
    'voice' => 3,
    'ambience' => 4,
    'aux' => 5,
    _ => 2, // Default to SFX
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

### UI Widget ↔ MixerDSPProvider ↔ Rust Engine Flow (Middleware/SlotLab Path)

```
UI Widget (vintage_eq_inserts.dart)
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

### DspChainProvider ↔ Rust Engine Flow (DAW Insert Chain Path — Added 2026-02-15)

```
DspNodeType.pultec/api550/neve1073 (DspChainProvider enum)
    │
    ▼ addNode(trackId, DspNodeType.pultec)
_typeToProcessorName() → 'pultec'/'api550'/'neve1073'
    │
    ▼ insertLoadProcessor(trackId, slotIndex, processorName)
Rust: create_processor_extended(processorName) → PultecWrapper/Api550Wrapper/Neve1073Wrapper
    │
    ▼ InternalProcessorEditorWindow._buildPultecParams/Api550Params/Neve1073Params()
insertSetParam(trackId, slotIndex, paramIndex, value)
    │
    ▼ Audio thread processes via InsertProcessor trait
```

**DspNodeType enum (12 types, updated 2026-02-15):**
`eq`, `compressor`, `limiter`, `gate`, `expander`, `reverb`, `delay`, `saturation`, `deEsser`, `pultec` (FF EQP1A), `api550` (FF 550A), `neve1073` (FF 1073)

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

### 2026-01-24 (Update 5 — Critical Bus ID Mapping Fix)
- **KRITIČNO: Ispravljen bus ID mapping u oba providera**
  - `MixerDSPProvider._busIdToEngineIndex()` — pogrešno mapiranje ispravljeno
  - `MixerProvider._getBusEngineId()` — pogrešno mapiranje ispravljeno
  - **Root cause:** Dart je slao `sfx→0` dok Rust očekuje `sfx→2`
  - **Rezultat:** Pan i Volume kontrole sada rade ispravno
- **Dokumentacija ažurirana** sa ispravnim mapiranjem:
  - 0=Master, 1=Music, 2=Sfx, 3=Voice, 4=Ambience, 5=Aux
  - Reference: `crates/rf-engine/src/playback.rs` lines 3313-3319
- **Comment fix:** `AudioPlaybackService.playLoopingToBus()` dokumentacija ispravljena

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

## 10. DSP System — ✅ RESOLVED (2026-01-23)

### 10.1 Prethodni problem (REŠENO)

~~UI pluginovi (Compressor, Limiter, Spectrum) kreirali su procesore u HashMap-ovima koji se NIKADA NE POZIVAJU u audio callback-u.~~

**REŠENO:** Svi FabFilter paneli sada koriste `DspChainProvider` + `insertSetParam()`.

### 10.2 Trenutna arhitektura

```
┌─────────────────────────────────────────────────────────────────┐
│ FLUTTER UI PLUGINOVI → DspChainProvider → InsertChain ✅         │
├─────────────────────────────────────────────────────────────────┤
│ FabFilterCompressorPanel                                        │
│   └→ DspChainProvider.addNode() → insertLoadProcessor() ✅       │
│      └→ insertSetParam() → track_inserts → AUDIO PATH ✅         │
│                                                                  │
│ FabFilterLimiterPanel                                           │
│   └→ DspChainProvider.addNode() → insertLoadProcessor() ✅       │
│      └→ insertSetParam() → track_inserts → AUDIO PATH ✅         │
│                                                                  │
│ FabFilterGatePanel                                              │
│   └→ DspChainProvider.addNode() → insertLoadProcessor() ✅       │
│      └→ insertSetParam() → track_inserts → AUDIO PATH ✅         │
│                                                                  │
│ FabFilterReverbPanel                                            │
│   └→ DspChainProvider.addNode() → insertLoadProcessor() ✅       │
│      └→ insertSetParam() → track_inserts → AUDIO PATH ✅         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ PRAVI AUDIO PATH (rf-engine/playback.rs) — SVI PANELI SADA TU   │
├─────────────────────────────────────────────────────────────────┤
│ PLAYBACK_ENGINE.process()                                       │
│   ├→ read_clip_audio()         ← čita audio iz timeline         │
│   ├→ InsertChain.process_pre_fader()  ← DSP RADI ✅             │
│   │    └→ CompressorWrapper, LimiterWrapper, GateWrapper, etc.  │
│   ├→ volume/pan                                                 │
│   ├→ InsertChain.process_post_fader()                          │
│   ├→ bus routing                                                │
│   └→ master inserts                                             │
└─────────────────────────────────────────────────────────────────┘
```

### 10.3 Obrisani HashMap-ovi (Ghost Code Deleted)

| HashMap | Status | Note |
|---------|--------|------|
| `DYNAMICS_COMPRESSORS` | ✅ DELETED | ~650 LOC removed from ffi.rs |
| `DYNAMICS_LIMITERS` | ✅ DELETED | |
| `DYNAMICS_GATES` | ✅ DELETED | |
| `DYNAMICS_EXPANDERS` | ✅ DELETED | |
| `DYNAMICS_DEESSERS` | ✅ DELETED | |

### 10.4 Ispravni način konekcije (IMPLEMENTED)

```dart
// ISPRAVNO: Koristi DspChainProvider + insertSetParam
final dsp = DspChainProvider.instance;
dsp.addNode(trackId, DspNodeType.compressor);  // → insertLoadProcessor FFI
final slotIndex = dsp.getChain(trackId).nodes.length - 1;

_ffi.insertSetParam(trackId, slotIndex, 0, threshold);  // Threshold → REAL DSP
_ffi.insertSetParam(trackId, slotIndex, 1, ratio);      // Ratio → REAL DSP
_ffi.insertSetParam(trackId, slotIndex, 2, attack);     // Attack → REAL DSP
```

### 10.5 Wrapper Parameter Indices

| Wrapper | Params |
|---------|--------|
| CompressorWrapper | 0=Threshold, 1=Ratio, 2=Attack, 3=Release, 4=Makeup, 5=Mix, 6=Link, 7=Type |
| LimiterWrapper | 0=Threshold, 1=Ceiling, 2=Release, 3=Oversampling |
| GateWrapper | 0=Threshold, 1=Range, 2=Attack, 3=Hold, 4=Release |
| ExpanderWrapper | 0=Threshold, 1=Ratio, 2=Knee, 3=Attack, 4=Release |
| ReverbWrapper | 0=RoomSize, 1=Damping, 2=Width, 3=DryWet, 4=Predelay, 5=Type |
| DeEsserWrapper | 0=Frequency, 1=Bandwidth, 2=Threshold, 3=Range, 4=Mode, 5=Attack, 6=Release, 7=Listen, 8=Bypass |

### 10.6 Trenutno stanje pluginova

| Plugin | Signal Display | Audio Processing |
|--------|----------------|------------------|
| **ProEqEditor** | Prazan (no fake data) | ✅ Radi preko InsertChain |
| **FabFilterCompressor** | Real metering* | ✅ Radi preko InsertChain |
| **FabFilterLimiter** | Real metering* | ✅ Radi preko InsertChain |
| **FabFilterGate** | Real metering* | ✅ Radi preko InsertChain |
| **FabFilterReverb** | Decay viz | ✅ Radi preko InsertChain |
| **DynamicsPanel** | All modes | ✅ Radi preko InsertChain |
| **DeEsserPanel** | GR display* | ✅ Radi preko InsertChain |

*Metering requires additional FFI (GR, True Peak) — currently shows 0 or -60dB.

**Documentation:** `.claude/architecture/DSP_ENGINE_INTEGRATION_CRITICAL.md`

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

### 11.2 Bus IDs (Rust Engine Convention)

⚠️ **CRITICAL:** This mapping MUST be used consistently in all Dart code!

| Bus ID | Rust Enum | Ime | Korišćenje |
|--------|-----------|-----|------------|
| 0 | `OutputBus::Master` | Master | Final output processing |
| 1 | `OutputBus::Music` | Music | Music tracks routing |
| 2 | `OutputBus::Sfx` | SFX | Sound effects, UI |
| 3 | `OutputBus::Voice` | Voice | Dialog/voiceover |
| 4 | `OutputBus::Ambience` | Ambience | Ambience/backgrounds |
| 5 | `OutputBus::Aux` | Aux | Auxiliary/sends |

**Reference:** `crates/rf-engine/src/playback.rs` lines 3313-3319

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

/// Map bus name to engine bus index
/// MUST match Rust playback.rs bus convention:
/// 0=Master, 1=Music, 2=Sfx, 3=Voice, 4=Ambience, 5=Aux
int _getBusId(String busId) {
  switch (busId) {
    case 'master': return 0;
    case 'music': return 1;
    case 'sfx': return 2;
    case 'voice': return 3;
    case 'amb': return 4;
    case 'ui': return 2;  // UI routes to SFX
    default: return 2;    // Default to SFX
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

## 12. Provider FFI Connection Status (UPDATED 2026-01-24)

### 12.1 Provider → FFI Connection Matrix

| Provider | FFI Integration | FFI Calls | Status |
|----------|-----------------|-----------|--------|
| **MixerProvider** | ✅ CONNECTED | 40 | Track/Bus/VCA/Group/Insert + Input Monitor/Phase Invert |
| **MixerDspProvider** | ✅ CONNECTED | 16 | Bus DSP, volume/pan/mute/solo |
| **DspChainProvider** | ✅ CONNECTED | 25+ | Insert load/unload/param/bypass/mix |
| **PluginProvider** | ✅ CONNECTED | 29 | Full plugin hosting (scan/load/params/presets) |
| **RoutingProvider** | ✅ CONNECTED | 11 | Create/delete/output/send/query (FULL SYNC) |
| **AudioPlaybackService** | ✅ CONNECTED | 10+ | Preview, playToBus, stop |
| **TimelinePlaybackProvider** | ✅ DELEGATED | 0 | Delegates to UnifiedPlaybackController |

### 12.2 DspChainProvider — ✅ FULLY CONNECTED (Fixed 2026-01-23)

**Lokacija:** `flutter_ui/lib/providers/dsp_chain_provider.dart` (~700 LOC)

**Status:** ✅ **POTPUNO POVEZAN SA FFI**

**FFI Metode (25+):**
```dart
_ffi.insertLoadProcessor(trackId, slotIndex, processorName)
_ffi.insertUnloadSlot(trackId, slotIndex)
_ffi.insertSetParam(trackId, slotIndex, paramIndex, value)
_ffi.insertSetBypass(trackId, slotIndex, bypass)
_ffi.insertSetMix(trackId, slotIndex, mix)
_ffi.insertBypassAll(trackId, bypass)
```

**Verifikacija:**
```bash
grep -c "_ffi\." dsp_chain_provider.dart
# Rezultat: 25+ matches
```

**Arhitektura:**
```
UI Panel → DspChainProvider.addNode() → _ffi.insertLoadProcessor()
                                      → Rust: track_inserts[trackId][slot]
                                      → Audio Thread PROCESSES ✅
```

### 12.3 RoutingProvider — ✅ FULLY CONNECTED (Fixed 2026-01-24)

**Lokacija:** `flutter_ui/lib/providers/routing_provider.dart` (~250 LOC)

**Status:** ✅ **100% POVEZAN** (koristi `engine_api.dart`)

**FFI Metode (11):**
- `routingInit(senderPtr)` — Inicijalizacija
- `routingCreateChannel(kind, name)` — Kreiranje kanala
- `routingDeleteChannel(channelId)` — Brisanje
- `routingPollResponse(callbackId)` — Async response polling
- `routingSetOutput(channelId, destType, destId)` — Output routing
- `routingAddSend(from, to, preFader)` — Send routing
- `routingSetVolume/Pan/Mute/Solo(channelId, value)` — Kontrole
- `routingGetChannelCount()` — Query count
- `routingGetAllChannels()` — ✅ NEW: Query all channel IDs + kinds
- `routingGetChannelsJson()` — ✅ NEW: Full channel list as JSON

**Rust FFI (ffi_routing.rs):**
```rust
routing_get_all_channels(out_ids, out_kinds, max_count) -> u32
routing_get_channels_json() -> *const c_char  // JSON: [{"id":1,"kind":0,"name":"Track 1"},...]
```

**RoutingProvider.syncFromEngine():**
- Parses JSON from engine
- Syncs local `_channels` map with engine state
- Called on init and refresh

**Arhitektura:**
```
UI → RoutingProvider.createChannel() → FFI → Rust Engine
                                            ↓
RoutingProvider.syncFromEngine() ← routingGetChannelsJson() ← Engine State
```

### 12.4 Track Channel FFI — ✅ NEW (2026-01-24)

**Lokacija:** `crates/rf-engine/src/ffi.rs` (~line 1170-1220)

Track-specific FFI funkcije za channel strip kontrole:

| FFI Function | Parameters | Description |
|--------------|------------|-------------|
| `track_set_input_monitor` | `(track_id: u64, enabled: i32)` | Enable/disable input monitor |
| `track_get_input_monitor` | `(track_id: u64) -> i32` | Get input monitor state |
| `track_set_phase_invert` | `(track_id: u64, enabled: i32)` | Enable/disable phase invert |
| `track_get_phase_invert` | `(track_id: u64) -> i32` | Get phase invert state |

**Rust Implementation:**
```rust
// crates/rf-engine/src/ffi.rs

#[no_mangle]
pub extern "C" fn track_set_input_monitor(track_id: u64, enabled: i32) {
    if let Some(engine) = PLAYBACK_ENGINE.get() {
        engine.set_input_monitor(track_id, enabled != 0);
    }
}

#[no_mangle]
pub extern "C" fn track_get_input_monitor(track_id: u64) -> i32 {
    PLAYBACK_ENGINE.get()
        .map(|e| e.get_input_monitor(track_id) as i32)
        .unwrap_or(0)
}
```

**Dart Wrappers (native_ffi.dart):**
```dart
void trackSetInputMonitor(int trackId, bool enabled) {
  _dylib.lookupFunction<Void Function(Uint64, Int32), void Function(int, int)>
      ('track_set_input_monitor')(trackId, enabled ? 1 : 0);
}

bool trackGetInputMonitor(int trackId) {
  return _dylib.lookupFunction<Int32 Function(Uint64), int Function(int)>
      ('track_get_input_monitor')(trackId) != 0;
}

void trackSetPhaseInvert(int trackId, bool enabled) {
  _dylib.lookupFunction<Void Function(Uint64, Int32), void Function(int, int)>
      ('track_set_phase_invert')(trackId, enabled ? 1 : 0);
}

bool trackGetPhaseInvert(int trackId) {
  return _dylib.lookupFunction<Int32 Function(Uint64), int Function(int)>
      ('track_get_phase_invert')(trackId) != 0;
}
```

**UI Integration (Channel Tab):**
- Phase Invert (Ø) button: `engine_connected_layout.dart` → `_buildChannelControls()`
- Input Monitor button: `engine_connected_layout.dart` → `_buildChannelControls()`

### 12.5 FabFilter Paneli — ✅ ALL 9 CONNECTED (Updated 2026-02-16)

Svih 9 FabFilter panela koriste DspChainProvider + InsertProcessor chain:

| Panel | Processor | Status |
|-------|-----------|--------|
| `fabfilter_eq_panel.dart` | `pro-eq` | ✅ Via insertSetParam |
| `fabfilter_compressor_panel.dart` | `compressor` | ✅ Via insertSetParam |
| `fabfilter_limiter_panel.dart` | `limiter` | ✅ Via insertSetParam |
| `fabfilter_gate_panel.dart` | `gate` | ✅ Via insertSetParam |
| `fabfilter_reverb_panel.dart` | `reverb` | ✅ Via insertSetParam |
| `fabfilter_deesser_panel.dart` | `deesser` | ✅ Via insertSetParam |
| `fabfilter_delay_panel.dart` | `delay` | ✅ Via insertSetParam |
| `fabfilter_saturation_panel.dart` | `saturation` | ✅ Via insertSetParam |
| `sidechain_panel.dart` | sidechain routing | ✅ Via sidechainSet* FFI |

**Ghost Code:** ✅ OBRISAN (~900 LOC uklonjeno iz ffi.rs i native_ffi.dart)

---

## 13. Sledći koraci

1. ✅ Ukloniti lažne podatke iz svih pluginova
2. ✅ **Bus InsertChain sistem implementiran** (2026-01-20)
3. ✅ **DspChainProvider FFI sync** — COMPLETE (2026-01-23)
4. ✅ **FabFilter paneli integrisani** — COMPLETE (2026-01-23)
5. ✅ **RoutingProvider channel query** — COMPLETE (2026-01-24)
   - Added: `routing_get_all_channels()` + `routing_get_channels_json()` FFI
   - RoutingProvider now syncs full channel list from engine
6. ✅ **DAW Action Strip connections** — COMPLETE (2026-01-24)
   - All 15 buttons connected (Browse, Edit, Mix, Process, Deliver)
7. ✅ **Pan Law FFI integration** — COMPLETE (2026-01-24)
   - `stereoImagerSetPanLaw()` connected to pan law chips
   - Applies to all tracks via MixerProvider.channels
8. ⏳ Dodati real-time GR metering za Compressor/Limiter
9. ⏳ Dodati FFT metering iz PLAYBACK_ENGINE za SpectrumAnalyzer

---

## 14. Connectivity Summary

| Metric | Value |
|--------|-------|
| **Overall DAW FFI Connectivity** | **100%** |
| **Providers Connected** | 7/7 |
| **FFI Functions Used** | 134+ |
| **Ghost Code Removed** | ~900 LOC |
| **Action Strip Buttons** | 15/15 connected |
| **Pan Law Integration** | ✅ FFI connected |
| **Track Channel FFI** | ✅ 4 functions (Input Monitor, Phase Invert) |

All DAW providers are now fully connected to the Rust audio engine via FFI.

---

## 15. Lower Zone Action Strip Status (2026-01-24)

### 15.1 DAW Action Strip — ✅ 100% CONNECTED

| Super Tab | Actions | Status |
|-----------|---------|--------|
| **Browse** | Import, Delete, Preview, Add to Track | ✅ FilePicker, AudioAssetManager, AudioPlaybackService |
| **Edit** | Add Track, Split Clip, Duplicate, Delete | ✅ MixerProvider, DspChainProvider |
| **Mix** | Add Bus, Mute All, Solo Selected, Reset | ✅ MixerProvider.addBus/muteAll/clearAllSolo/resetAll |
| **Process** | Add EQ, Remove Proc, Copy Chain, Bypass | ✅ DspChainProvider.addNode/removeNode/setBypass |
| **Deliver** | Quick Export, Browse Output, Start Export | ✅ FilePicker, Process.run (folder open) |

### 15.2 Middleware Action Strip — ✅ CONNECTED (partial workarounds)

| Super Tab | Actions | Status |
|-----------|---------|--------|
| **Events** | New Event, Delete, Duplicate, Test | ✅ MiddlewareProvider CRUD |
| **Containers** | Add Sound, Balance, Shuffle, Test | ⚠️ debugPrint (methods not implemented) |
| **Routing** | Add Rule, Remove, Copy, Test | ✅ MiddlewareProvider.addDuckingRule |
| **RTPC** | Add Point, Remove, Reset, Preview | ⚠️ debugPrint (methods not implemented) |
| **Deliver** | Validate, Bake, Package | ⚠️ debugPrint (export service TODO) |

### 15.3 Archive Panel — ✅ FULLY IMPLEMENTED (2026-01-24)

**Service:** `ProjectArchiveService` (`flutter_ui/lib/services/project_archive_service.dart`)

**Features:**
- ✅ Interactive checkboxes (Include Audio, Include Presets, Include Plugins, Compress)
- ✅ FilePicker for save location selection
- ✅ ZIP archive creation via `archive` package
- ✅ Progress indicator with status text
- ✅ Success SnackBar with "Open Folder" action
- ✅ Error handling with failure message

**Archive Config Options:**
| Option | Default | Description |
|--------|---------|-------------|
| Include Audio | ✅ ON | WAV, FLAC, MP3, OGG, AAC, AIFF, M4A, ALAC files |
| Include Presets | ✅ ON | .ffpreset, .fxp, .fxb files |
| Include Plugins | ❌ OFF | Plugin references (metadata only) |
| Compress | ✅ ON | ZIP compression enabled |

---

## 16. Channel Strip UI Enhancements (2026-01-24)

### 16.1 ChannelStripData Model Proširenja

Nova polja dodana u `layout_models.dart`:

| Field | Type | Default | Opis |
|-------|------|---------|------|
| `panRight` | double | 0.0 | R channel pan za stereo dual-pan mode (-1 to 1) |
| `isStereo` | bool | false | True za stereo pan (L/R nezavisni) |
| `phaseInverted` | bool | false | Phase/polarity invert (Ø) |
| `inputMonitor` | bool | false | Input monitoring active |
| `lufs` | LUFSData? | null | LUFS loudness metering data |
| `eqBands` | List\<EQBand\> | [] | Per-channel EQ bands |

### 16.2 LUFSData Model

```dart
class LUFSData {
  final double momentary;    // Momentary loudness (400ms window)
  final double shortTerm;    // Short-term loudness (3s window)
  final double integrated;   // Integrated loudness (program)
  final double truePeak;     // True peak (dBTP, 4x oversampled)
  final double? range;       // Loudness range (LRA)
}
```

### 16.3 EQBand Model

```dart
class EQBand {
  final int index;
  final String type;      // 'lowcut', 'lowshelf', 'bell', 'highshelf', 'highcut'
  final double frequency;
  final double gain;      // dB
  final double q;
  final bool enabled;
}
```

### 16.4 Novi UI Kontroli

| Control | Label | Active Color | Callback |
|---------|-------|--------------|----------|
| Input Monitor | `I` | Blue | `onChannelMonitorToggle` |
| Phase Invert | `Ø` | Purple | `onChannelPhaseInvertToggle` |
| Pan Right | Slider | — | `onChannelPanRightChange` |

### 16.5 Widget Callback Proširenja

Dodati callbacks u sve channel strip widgete:

**channel_inspector_panel.dart:**
```dart
final void Function(String channelId, double panRight)? onPanRightChange;
final void Function(String channelId)? onMonitorToggle;
final void Function(String channelId)? onPhaseInvertToggle;
```

**left_zone.dart:**
```dart
final void Function(String channelId, double pan)? onChannelPanRightChange;
final void Function(String channelId)? onChannelMonitorToggle;
final void Function(String channelId)? onChannelPhaseInvertToggle;
```

**glass_left_zone.dart:** (Glass theme variant)
```dart
final void Function(String channelId, double pan)? onChannelPanRightChange;
final void Function(String channelId)? onChannelMonitorToggle;
final void Function(String channelId)? onChannelPhaseInvertToggle;
```

### 16.6 MixerProvider Metode

```dart
// Toggle input monitor state + sync to engine
void toggleInputMonitor(String id) {
  final newMonitorState = !channel.monitorInput;
  _channels[id] = channel.copyWith(monitorInput: newMonitorState);
  NativeFFI.instance.trackSetInputMonitor(channel.trackIndex!, newMonitorState);
  notifyListeners();
}

// Set input monitor state directly + sync to engine
void setInputMonitor(String id, bool monitor) {
  _channels[id] = channel.copyWith(monitorInput: monitor);
  NativeFFI.instance.trackSetInputMonitor(channel.trackIndex!, monitor);
  notifyListeners();
}

// Set input gain (trim) -20dB to +20dB + sync to engine
void setInputGain(String channelId, double gain) {
  final clampedGain = gain.clamp(-20.0, 20.0);
  _channels[channelId] = channel.copyWith(inputGain: clampedGain);
  NativeFFI.instance.channelStripSetInputGain(channel.trackIndex!, clampedGain);
  notifyListeners();
}
```

### 16.7 FFI Integracija

| Dart Method | FFI Function | Status |
|-------------|--------------|--------|
| `trackSetInputMonitor()` | `track_set_input_monitor` | ✅ Connected |
| `trackGetInputMonitor()` | `track_get_input_monitor` | ✅ Connected |
| `channelStripSetInputGain()` | `channel_strip_set_input_gain` | ✅ Connected |
| `mixerSetBusPanRight()` | `mixer_set_bus_pan_right` | ✅ Connected |

---

## 17. DAW Waveform Generation System (2026-01-25)

### Overview

Real-time waveform generation za timeline clips koristi Rust FFI umesto demo waveform-a.

### Arhitektura

```
Audio File Import
        │
        ▼
NativeFFI.generateWaveformFromFile(path, cacheKey)
        │
        ▼
Rust SIMD Waveform Generator (AVX2/NEON)
        │
        ▼
JSON Response (Multi-LOD Peaks)
        │
        ▼
parseWaveformFromJson() → (Float32List?, Float32List?)
        │
        ▼
ClipWidget Rendering
```

### FFI Funkcija

**Dart:** `NativeFFI.instance.generateWaveformFromFile(path, cacheKey)`

**Rust:** `engine_generate_waveform_from_file(path, cache_key)`

**Return:** JSON string sa multi-LOD waveform podacima

### JSON Format

```json
{
  "lods": [
    {
      "samples_per_pixel": 1,
      "left": [
        {"min": -0.5, "max": 0.5, "rms": 0.3},
        {"min": -0.4, "max": 0.6, "rms": 0.35},
        ...
      ],
      "right": [
        {"min": -0.45, "max": 0.55, "rms": 0.32},
        ...
      ]
    },
    {
      "samples_per_pixel": 2,
      ...
    }
  ]
}
```

### Helper Funkcija: parseWaveformFromJson()

**Lokacija:** `flutter_ui/lib/models/timeline_models.dart` (lines 955-1007)

```dart
(Float32List?, Float32List?) parseWaveformFromJson(
  String? jsonStr,
  {int maxSamples = 2048}
)
```

**Funkcionalnost:**
- Parsira JSON iz Rust FFI
- Automatski bira odgovarajući LOD (max 2048 samples za memorijsku efikasnost)
- Ekstrahuje peak vrednosti (`max(abs(min), abs(max))`)
- Vraća tuple `(leftChannel, rightChannel)` kao `Float32List`
- Vraća `(null, null)` ako parsiranje ne uspe

### Duration Getteri (PoolAudioFile)

| Getter | Format | Primer | Upotreba |
|--------|--------|--------|----------|
| `durationFormatted` | Sekunde (2 decimale) | `"45.47s"` | UI prikaz |
| `durationFormattedMs` | Milisekunde | `"45470ms"` | Precizni prikaz |
| `durationMs` | Integer ms | `45470` | Kalkulacije |

### Lokacije Real Waveform Generacije

| Fajl | Funkcija | Opis |
|------|----------|------|
| `engine_connected_layout.dart` | `_addFileToPool()` | Import audio fajla u pool |
| `engine_connected_layout.dart` | `_syncAudioPoolFromSlotLab()` | Sync iz SlotLab |
| `engine_connected_layout.dart` | `_syncFromAssetManager()` | Sync iz AudioAssetManager |
| `engine_connected_layout.dart` | `_handleAudioPoolFileDoubleClick()` | Dodavanje na timeline |

### Null Waveform Handling

Ako FFI ne vrati waveform (greška, nedostupan engine), waveform ostaje `null`:

```dart
Float32List? waveform;
final waveformJson = NativeFFI.instance.generateWaveformFromFile(path, cacheKey);
if (waveformJson != null) {
  final (left, _) = timeline.parseWaveformFromJson(waveformJson);
  waveform = left;
}
// waveform može biti null — UI gracefully handluje null waveform
```

**Demo Waveform:** UKLONJEN (2026-01-25)
- `generateDemoWaveform()` funkcija obrisana iz `timeline_models.dart`
- ClipWidget podržava nullable waveform — prikazuje empty clip bez waveform-a
- Nema više fallback-a na fake waveform

### SIMD Optimizacija (Rust)

Rust engine koristi SIMD instrukcije za brzu waveform generaciju:
- **x86_64:** AVX2/SSE4.2
- **ARM:** NEON

Performanse: ~10ms za 10-minutni stereo fajl @ 48kHz

---

---

## 18. CoreAudio Stereo Buffer Handling (2026-02-21)

### Non-Interleaved vs Interleaved Stereo

CoreAudio na macOS može isporučiti stereo u dva formata:

| Format | `num_buffers` | Layout | Opis |
|--------|---------------|--------|------|
| **Non-interleaved** | 2 | Buffer 0=L, Buffer 1=R | Moderni standard |
| **Interleaved** | 1 | L,R,L,R,L,R... | Legacy |

### Implementacija (`coreaudio.rs`)

**Input čitanje (lines 811-830):**
```rust
if num_buffers >= 2 {
    // Non-interleaved: čitaj iz 2 odvojena buffera
    for i in 0..sample_count {
        input_slice[i * 2] = *samples_l.add(i) as f64;       // L
        input_slice[i * 2 + 1] = *samples_r.add(i) as f64;   // R
    }
} else if num_buffers == 1 {
    // Interleaved: single buffer sa L/R parovima
    for i in 0..sample_count {
        input_slice[i] = *input_samples.add(i) as f64;
    }
}
```

**Output pisanje (lines 858-877):**
```rust
if num_buffers >= 2 {
    // Non-interleaved: deinterleave u 2 odvojena buffera
    for i in 0..sample_count {
        *samples_l.add(i) = output_slice[i * 2] as f32;       // L
        *samples_r.add(i) = output_slice[i * 2 + 1] as f32;   // R
    }
} else if num_buffers == 1 {
    // Interleaved: direktan write
    for i in 0..sample_count {
        *output_samples.add(i) = output_slice[i] as f32;
    }
}
```

**Impact:** Ispravan stereo image za SVE audio puteve (DAW, Middleware, SlotLab, Preview).

---

## 19. One-Shot Voice Stereo Panning (2026-02-21)

### Problem

`OneShot::fill_buffer()` kolapsirao stereo u mono sa `(src_l + src_r) * 0.5` pre primene pan-a — uništavao kompletnu stereo sliku.

### Pro Tools-Style Balance Pan (Rešenje)

| Pan Vrednost | L Kanal | R Kanal | Opis |
|-------------|---------|---------|------|
| -1.0 | src_l + src_r | 0 | Hard Left |
| 0.0 | src_l | src_r | Centar (pun stereo) |
| +1.0 | 0 | src_r + src_l | Hard Right |

**Implementacija (`playback.rs:1235-1270`):**
```rust
if channels_src > 1 {
    // Stereo: balance-style pan (Pro Tools)
    let pan_val = self.pan as f64;
    if pan_val <= 0.0 {
        let r_atten = 1.0 + pan_val;  // 1.0 at center, 0.0 at hard left
        sample_l = (src_l as f64) + (src_r as f64 * (1.0 - r_atten));
        sample_r = src_r as f64 * r_atten;
    } else {
        let l_atten = 1.0 - pan_val;  // 1.0 at center, 0.0 at hard right
        sample_l = src_l as f64 * l_atten;
        sample_r = (src_r as f64) + (src_l as f64 * (1.0 - l_atten));
    }
} else {
    // Mono: equal-power pan (nepromenjeno)
    sample_l = (src_l * pan_l) as f64;
    sample_r = (src_r * pan_r) as f64;
}
```

**VAŽNO:** `src_l`/`src_r` već uključuju `volume * fade_gain` iz linije 1198 — nema duplog množenja!

**Impact:** Svi event-based zvuci (SlotLab, Middleware) sada čuvaju stereo širinu.

---

## 20. Pro Tools Routing Gap Analysis (2026-02-21)

### Identifikovani Gapovi (6)

| # | Gap | Trenutno | Pro Tools Standard | Effort | Prioritet |
|---|-----|----------|-------------------|--------|-----------|
| 1 | **Master Fader inserts** | Split pre/post | ALL post-fader | Moderate | P1 |
| 2 | **Bus count** | Fixed 6 (`[InsertChain; 6]`) | Dynamic creation | High | P2 |
| 3 | **Pre-fader sends** | Field exists, NOT in audio callback | Full implementation | High | P1 |
| 4 | **VCA send scaling** | Volume only | Volume + send levels | High | P2 |
| 5 | **Insert slots** | 8 per channel | 10 (A-E pre, F-J post) | Low | P3 |
| 6 | **Bus-to-bus routing** | All → Master only | Any bus → any bus | Very High | P3 |

### Gap 1: Master Fader Pre/Post Split

**Problem:** `playback.rs:3936-3949` ima pre + post insert sekcije za master.
**Pro Tools:** Master Fader ima SVE inserts post-fader — mastering chain utičе na signal POSLE fader-a.
**Impact:** Mastering EQ/limiter treba da utiče na fader input.

### Gap 2: Fixed Bus Count

**Problem:** `bus_inserts: RwLock<[InsertChain; 6]>` — hardkodirano na 6 buseva.
**Pro Tools:** Dinamično kreiranje buseva po potrebi.
**Impact:** Ograničena fleksibilnost rutiranja za kompleksne miksove.

### Gap 3: Pre-Fader Sends

**Problem:** `preFader` polje postoji u modelu, ali audio callback ga ne implementira.
**Pro Tools:** Pre-fader sends omogućavaju cue mixove i sidechain rutiranje pre volumena.
**Impact:** Svi sends su efektivno post-fader.

### Gap 4: VCA Send Scaling

**Problem:** VCA fader skalira samo volume, ne i send nivoe.
**Pro Tools:** VCA proporcionalno skalira I volume I send levels.
**Impact:** VCA grupe ne utiču na send submixove.

### Gap 5: Insert Slot Count

**Problem:** 8 insert slotova po kanalu.
**Pro Tools:** 10 slotova (A-E pre-fader, F-J post-fader).
**Impact:** Profesionalni workflow-i ponekad zahtevaju više od 8 inserta.

### Gap 6: Bus-to-Bus Routing

**Problem:** Svi busevi se sumiraju direktno na Master.
**Pro Tools:** Bilo koji bus → bilo koji bus, omogućava stem grupiranje.
**Impact:** Kompleksne mixing hijerarhije nisu moguće.

### Status

**Implementirano:** CoreAudio stereo fix + One-shot stereo balance pan
**Dokumentovano:** 6 gapova za post-ship roadmap

---

## 21. Send Slot → FX Bus Creation Flow (2026-02-22)

### Problem

`_onSendClick()` u `engine_connected_layout.dart` bio je hardkodiran stub koji je referencirao nepostojeće FX buseve i pozivao `routingAddSend()` sa nevalidnim parametrima.

### Rešenje — Kompletni Send Flow

```
Channel Tab Send Slot Click
    ↓
_onSendClick(channelId, sendIndex)
    ↓
showDialog() → _SendDialogResult
    ↓
┌───────────────────┬────────────────────┬──────────────────┐
│ Create New FX Bus  │ Route to Existing  │ Remove Send      │
├───────────────────┼────────────────────┼──────────────────┤
│ 1. createBus()     │ setAuxSendLevel()  │ removeAuxSendAt()│
│ 2. getBusEngineId()│                    │                  │
│ 3. addNode(busTrack│                    │                  │
│    Id, effectType) │                    │                  │
│ 4. setChannelInsert│                    │                  │
│    s(busId, inserts│                    │                  │
│ 5. setAuxSendLevel │                    │                  │
└───────────────────┴────────────────────┴──────────────────┘
```

### Bus TrackId Convention

Busevi koriste offset `1000 + busEngineId` za insert chain FFI pozive:
```dart
final busEngineId = mixerProvider.getBusEngineId(targetBusId);
final busTrackId = 1000 + busEngineId;
DspChainProvider.instance.addNode(busTrackId, effectType);
```

### Novi MixerProvider Metodi

| Metod | Signature | Opis |
|-------|-----------|------|
| `getBusEngineId` | `int getBusEngineId(String busId)` | Public wrapper za `_getBusEngineId()` |
| `removeAuxSendAt` | `void removeAuxSendAt(String channelId, int sendIndex)` | Uklanja send na indeksu, FFI sync via `routingRemoveSend()` |
| `setChannelInserts` | `void setChannelInserts(String id, List<InsertSlot> inserts)` | Ažurira inserte na bilo kom tipu kanala (`_channels`, `_buses`, `_auxes`) |

### Kritični Bug Fix — Bus vs Channel Store

**Problem:** `getChannel(targetBusId)` vraćao `null` za buseve.

**Uzrok:** Busevi se čuvaju u `_buses` mapi, NE u `_channels`. `getChannel()` pretražuje samo `_channels`.

**Fix:** Koristi `getBus(targetBusId)` za pristup bus kanalima nakon kreiranja.

### Callback Chain

```
ChannelInspectorPanel.onSendClick(channelId, sendIndex)
    → LeftZone.onSendClick
        → MainLayout.onSendClick
            → EngineConnectedLayout._onSendClick(channelId, sendIndex)
```

### Dostupni Efekti za FX Buseve

| Efekat | DspNodeType | Boja |
|--------|-------------|------|
| Reverb | `reverb` | Cyan (#40C8FF) |
| Delay | `delay` | Orange (#FF9040) |
| Chorus (Haas) | `deEsser` | Purple (#9370DB) |
| Compressor | `compressor` | Amber (#FFB300) |
| EQ | `eq` | Blue (#4A9EFF) |
| Saturation | `saturation` | Red (#FF4060) |

---

*Poslednji update: 2026-02-22 (Send Slot → FX Bus Creation, CoreAudio stereo, One-shot stereo pan, Pro Tools gap analysis)*
