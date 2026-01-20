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
  'rf-eq': 'pro-eq',
  'rf-compressor': 'compressor',
  'rf-limiter': 'limiter',
  'rf-reverb': 'reverb',
  'rf-delay': 'delay',
  'rf-gate': 'gate',
  'rf-saturator': 'saturator',
  'rf-deesser': 'deesser',
};
```

### Dostupni Plugins

| Plugin ID | Rust Processor | Kategorija |
|-----------|----------------|------------|
| `rf-eq` | `pro-eq` | EQ |
| `rf-compressor` | `compressor` | Dynamics |
| `rf-limiter` | `limiter` | Dynamics |
| `rf-reverb` | `reverb` | Time |
| `rf-delay` | `delay` | Time |
| `rf-gate` | `gate` | Dynamics |
| `rf-saturator` | `saturator` | Distortion |
| `rf-deesser` | `deesser` | Dynamics |

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

## 9. Verifikacija

Za testiranje FFI konekcije:

1. Pokreni app
2. Otvori Middleware sekciju
3. Pomeri bus volume slider
4. Proveri konzolu za `[MixerDSPProvider]` log poruke
5. Zvuk bi trebalo da se promeni u skladu sa slider-om
