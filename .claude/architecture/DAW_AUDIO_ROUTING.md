# DAW Audio Routing Architecture

## 1. Dual Mixer Architecture

| Provider | Sektor | Namena |
|----------|--------|--------|
| **MixerProvider** | DAW | Timeline playback, track routing, VCA/Groups |
| **MixerDSPProvider** | Middleware/SlotLab | Event-based audio, bus mixing |

### 1.1 MixerProvider (DAW)

**Lokacija:** `flutter_ui/lib/providers/mixer_provider.dart`

- Dinamički kanali (tracks), 6 buseva, Aux sends/returns, VCA faders, Groups, Real-time metering
- FFI: `NativeFFI.instance.setTrackVolume/Pan/Mute/Solo()`, `engine.setBusVolume/Pan()`, `mixerSetBusMute/Solo()`

### 1.2 MixerDSPProvider (Middleware/SlotLab)

**Lokacija:** `flutter_ui/lib/providers/mixer_dsp_provider.dart`

- Bus volume/pan/mute/solo, Insert chain management
- FFI: `_ffi.setBusVolume/Pan/Mute/Solo(engineIdx, value)`
- Default buses: Master(0.85), Music(0.7), SFX(0.9), Ambience(0.5), Voice(0.95)

### 1.3 Bus Engine ID Mapping

**CRITICAL:** Must match Rust `playback.rs` bus processing loop (lines 3313-3319)

| Engine ID | Bus | Note |
|-----------|-----|------|
| 0 | Master | Final output |
| 1 | Music | Music tracks |
| 2 | SFX | Sound effects (UI routes here too) |
| 3 | Voice | Dialog/voiceover |
| 4 | Ambience | Backgrounds |
| 5 | Aux | Auxiliary/sends |

Both providers use identical mapping. Default fallback = 2 (SFX).

---

## 2. Audio Playback Flow

**DAW:** Track → MixerProvider.channel → NativeFFI.setTrackVolume/Pan() → Engine → Master → Output

**Middleware/SlotLab:** Stage Event → EventRegistry.triggerStage() → AudioPlaybackService.playFileToBus() → NativeFFI.playbackPlayToBus() → MixerDSPProvider bus settings → Master → Output

### FFI Functions

| Category | Dart Method | FFI Function |
|----------|-------------|--------------|
| Bus | `setBusVolume(idx, vol)` | `engine_set_bus_volume` |
| Bus | `setBusPan(idx, pan)` | `engine_set_bus_pan` |
| Bus | `setBusMute(idx, muted)` | `engine_set_bus_mute` |
| Bus | `setBusSolo(idx, solo)` | `engine_set_bus_solo` |
| Playback | `playbackPlayToBus()` | `playback_play_to_bus` |
| Playback | `playbackPlayLoopingToBus()` | `playback_play_looping_to_bus` |
| Playback | `playbackStopOneShot()` | `playback_stop_one_shot` |

---

## 3. Insert Chain Architecture

8 insert slotova po kanalu: **Pre-fader (0-3)**, **Post-fader (4-7)**

### 3.1 MixerDSPProvider Insert FFI

```dart
_ffi.insertCreateChain(trackId);
_ffi.insertLoadProcessor(trackId, slotIndex, processorName);
_ffi.insertUnloadSlot(trackId, slotIndex);
_ffi.insertSetBypass(trackId, slotIndex, bypassed);
_ffi.insertSetParam(trackId, slotIndex, paramIndex, value);
```

### 3.2 Plugin ID → Processor Name Mapping

| Plugin ID | Processor | Category |
|-----------|-----------|----------|
| `rf-eq` | `pro-eq` | EQ (64-band parametric) |
| `rf-pultec` | `pultec` | EQ (Pultec EQP-1A tube) |
| `rf-api550` | `api550` | EQ (API 550A discrete) |
| `rf-neve1073` | `neve1073` | EQ (Neve 1073 inductor) |
| `rf-compressor` | `compressor` | Dynamics |
| `rf-limiter` | `limiter` | Dynamics |
| `rf-gate` | `gate` | Dynamics |
| `rf-saturator` | `saturator` | Distortion |
| `rf-deesser` | `deesser` | Dynamics |
| `rf-reverb` | `reverb` | Time |
| `rf-delay` | `delay` | Time |

### 3.3 DspNodeType Enum (12 types)

`eq`, `compressor`, `limiter`, `gate`, `expander`, `reverb`, `delay`, `saturation`, `deEsser`, `pultec`, `api550`, `neve1073`

### 3.4 Wrapper Parameter Indices

| Wrapper | Params |
|---------|--------|
| CompressorWrapper | 0=Threshold, 1=Ratio, 2=Attack, 3=Release, 4=Makeup, 5=Mix, 6=Link, 7=Type |
| LimiterWrapper | 0=Threshold, 1=Ceiling, 2=Release, 3=Oversampling |
| GateWrapper | 0=Threshold, 1=Range, 2=Attack, 3=Hold, 4=Release |
| ExpanderWrapper | 0=Threshold, 1=Ratio, 2=Knee, 3=Attack, 4=Release |
| ReverbWrapper | 0=RoomSize, 1=Damping, 2=Width, 3=DryWet, 4=Predelay, 5=Type |
| DeEsserWrapper | 0=Frequency, 1=Bandwidth, 2=Threshold, 3=Range, 4=Mode, 5=Attack, 6=Release, 7=Listen, 8=Bypass |

---

## 4. Vintage Analog EQ Architecture

Tri emulacije u `rf-dsp/src/eq_analog.rs`, wrapperi u `rf-engine/src/dsp_wrappers.rs`.

**Pultec EQP-1A:** Params 0-3 (lowBoost, lowAtten, highBoost, highAtten), 0-10 dB. Passive tube, simultaneous boost+cut, output transformer saturation.

**API 550A:** Params 0-2 (lowGain, midGain, highGain), ±12 dB. Proportional Q, discrete 2520 op-amp, 5 selectable freqs per band.

**Neve 1073:** Params 0-2 (hpEnabled, lowGain, highGain), ±16 dB. Inductor LC filters, dual transformer saturation.

**Signal flow:** Input → HP Filter (Neve only) → Low → Mid → High → Tube/Transformer Saturation → Output

**Two UI paths:**
- **Middleware/SlotLab:** UI Widget → MixerDSPProvider.updateInsertParams() → `_ffi.insertSetParam()` → Rust
- **DAW:** DspChainProvider.addNode() → `insertLoadProcessor()` → InternalProcessorEditorWindow → `insertSetParam()`

---

## 5. EQ Processing Systems

**UPOZORENJE:** Tri odvojena EQ sistema — korišćenje pogrešnog = nema audio processing.

| Sistem | Audio Processing | Korišćenje |
|--------|------------------|------------|
| **PLAYBACK_ENGINE InsertChain** | ✅ DA | Lower Zone EQ, DAW track inserts (PREPORUČENO) |
| **DspCommand Queue** | ✅ DA | EqProvider (alternativni pristup) |
| **PRO_EQS HashMap** | ❌ NE | DEPRECIRAN — NE KORISTITI! |

### 5.1 PLAYBACK_ENGINE InsertChain (PREPORUČENO)

Lock-free ring buffer za UI→Audio: `set_track_insert_param()` → `InsertParamChange` → `consume_insert_param_changes()` → `InsertChain.process()`

EQ FFI (param index = band*11+offset): `eqSetBandEnabled/Frequency/Gain/Q/Shape(trackId, bandIndex, value)`, `eqSetBypass(trackId, bypass)`

TrackId: 0=Master (Lower Zone), 1-N=Individual tracks.

### 5.2 DspCommand Queue (alternativa)

`DspCommand::EqSetGain{...}` → `rtrb` queue → `poll_commands()` → `dsp_storage.process_command()` → `TrackDsp.pro_eq.set_param()`

### 5.3 PRO_EQS HashMap (DEPRECIRAN)

`lazy_static! { static ref PRO_EQS: RwLock<HashMap<u32, ProEq>> }` — `pro_eq_process()` se NIKAD ne poziva iz audio callback-a. **NE KORISTITI.**

### 5.4 Kada koji sistem

| Use Case | Sistem |
|----------|--------|
| Lower Zone EQ | PLAYBACK_ENGINE (`ffi.eqSetBandGain(0, band, gain)`) |
| DAW Track Inserts | PLAYBACK_ENGINE (`ffi.eqSetBandGain(trackId, band, gain)`) |
| EqProvider state | DspCommand (interno preko `eqSetBand*` FFI) |
| Middleware Inserts | MixerDSPProvider (`insertSetParam()`) |

---

## 6. Bus InsertChain System

```rust
pub struct PlaybackEngine {
    insert_chains: RwLock<HashMap<u64, InsertChain>>,  // Track inserts
    bus_inserts: RwLock<[InsertChain; 6]>,              // Bus inserts (0-5)
    master_insert: RwLock<InsertChain>,                 // Master (backward compat)
}
```

### 6.1 Bus Insert FFI

| FFI Function | Opis |
|--------------|------|
| `bus_insert_load_processor(bus_id, slot, name)` | Učitaj DSP processor |
| `bus_insert_unload_slot(bus_id, slot)` | Ukloni processor |
| `bus_insert_set_param(bus_id, slot, param, value)` | Postavi parametar |
| `bus_insert_set_bypass(bus_id, slot, bypass)` | Toggle bypass |
| `bus_insert_set_mix(bus_id, slot, mix)` | Dry/wet mix |
| `bus_insert_is_loaded(bus_id, slot)` | Proveri učitanost |

### 6.2 Audio Callback Processing Order

1. **Tracks:** Track InsertChain pre-fader → volume/pan → post-fader → route to bus
2. **Buses (0-5):** Bus InsertChain pre-fader → bus volume/pan → post-fader → sum to master
3. **Master:** Master InsertChain → output

### 6.3 UI Routing (engine_connected_layout.dart)

`_isBusChannel()` detektuje bus vs track. `_routeEqParam()` šalje na `busInsertSetParam()` ili `insertSetParam()` zavisno od tipa.

---

## 7. Provider FFI Connection Matrix

| Provider | FFI Calls | Status |
|----------|-----------|--------|
| MixerProvider | 40 | ✅ Track/Bus/VCA/Group/Insert + Input Monitor/Phase Invert |
| MixerDspProvider | 16 | ✅ Bus DSP, volume/pan/mute/solo |
| DspChainProvider | 25+ | ✅ Insert load/unload/param/bypass/mix |
| PluginProvider | 29 | ✅ Full plugin hosting |
| RoutingProvider | 11 | ✅ Create/delete/output/send/query |
| AudioPlaybackService | 10+ | ✅ Preview, playToBus, stop |
| TimelinePlaybackProvider | 0 | ✅ Delegates to UnifiedPlaybackController |

### 7.1 DspChainProvider

**Lokacija:** `flutter_ui/lib/providers/dsp_chain_provider.dart` (~700 LOC)

Potpuno povezan: `_ffi.insertLoadProcessor/UnloadSlot/SetParam/SetBypass/SetMix/BypassAll()`

Flow: UI Panel → `addNode()` → `insertLoadProcessor()` → Rust `track_inserts[trackId][slot]` → Audio Thread

### 7.2 RoutingProvider

**Lokacija:** `flutter_ui/lib/providers/routing_provider.dart` (~250 LOC)

11 FFI metoda: `routingInit`, `routingCreateChannel`, `routingDeleteChannel`, `routingSetOutput`, `routingAddSend`, `routingSetVolume/Pan/Mute/Solo`, `routingGetChannelCount`, `routingGetAllChannels`, `routingGetChannelsJson`

`syncFromEngine()` parsira JSON iz engine-a i sinhronizuje `_channels` mapu.

### 7.3 Track Channel FFI

| FFI Function | Opis |
|--------------|------|
| `track_set_input_monitor(track_id, enabled)` | Enable/disable input monitor |
| `track_get_input_monitor(track_id)` | Get input monitor state |
| `track_set_phase_invert(track_id, enabled)` | Enable/disable phase invert |
| `track_get_phase_invert(track_id)` | Get phase invert state |

### 7.4 FabFilter Paneli — All 9 Connected

eq, compressor, limiter, gate, reverb, deesser, delay, saturation, sidechain — svi koriste DspChainProvider + InsertProcessor chain. Ghost code (~900 LOC) obrisan iz ffi.rs.

---

## 8. Metering Integration

MixerProvider pretplaćen na `engine.meteringStream` — ažurira master peak/RMS i per-channel peak iz bus metering podataka. Konverzija: `_dbToLinear()`.

---

## 9. CoreAudio Stereo Buffer Handling

CoreAudio isporučuje stereo u dva formata:
- **Non-interleaved** (num_buffers=2): Buffer 0=L, Buffer 1=R (moderni standard)
- **Interleaved** (num_buffers=1): L,R,L,R... (legacy)

`coreaudio.rs` detektuje format i pravilno čita/piše za oba slučaja.

---

## 10. One-Shot Voice Stereo Panning

**Pro Tools-style balance pan** (`playback.rs:1235-1270`):
- Pan 0.0 = pun stereo (src_l→L, src_r→R)
- Pan -1.0 = hard left (src_l+src_r→L, 0→R)
- Pan +1.0 = hard right (0→L, src_r+src_l→R)
- Mono sources: equal-power pan (nepromenjeno)

`src_l`/`src_r` već uključuju `volume * fade_gain` — nema duplog množenja.

---

## 11. OutputBus Enum Index Fix

**Problem:** Dart enum `OutputBus { master, music, sfx, ambience, voice }` — `.index` daje 3=ambience, 4=voice, ali Rust očekuje 3=voice, 4=ambience.

**Rešenje:** `OutputBusExtension.engineIndex` getter. **NIKADA** koristiti `.index` za FFI — UVEK `.engineIndex`.

---

## 12. Send Slot → FX Bus Creation Flow

`_onSendClick()` → dialog → tri opcije: Create New FX Bus, Route to Existing, Remove Send.

**Bus TrackId Convention:** `1000 + busEngineId` za insert chain FFI pozive.

**Novi MixerProvider metodi:** `getBusEngineId()`, `removeAuxSendAt()`, `setChannelInserts()`

**VAŽNO:** Busevi su u `_buses` mapi, NE u `_channels`. Koristiti `getBus()` za pristup.

---

## 13. Legacy vs Modern MixerProvider Methods

| Operacija | Legacy (NE KORISTITI) | Modern (KORISTITI) |
|-----------|----------------------|-------------------|
| Volume | `setVolume()` | `setChannelVolume()` |
| Mute | `toggleMute()` | `toggleChannelMute()` |
| Solo | `toggleSolo()` | `toggleChannelSolo()` |

Modern metode propagiraju na rutirane trackove: `_applyBusVolumeToRoutedTracks()`, `_applyBusMuteToRoutedTracks()`, `_applySoloInPlace()`.

`createChannelFromTrack()` prima `outputBus` parametar (default 'master').

---

## 14. Channel Strip UI

Nova polja u `ChannelStripData` (`layout_models.dart`): `panRight`, `isStereo`, `phaseInverted`, `inputMonitor`, `lufs` (LUFSData), `eqBands` (List<EQBand>).

MixerProvider metode: `toggleInputMonitor()`, `setInputMonitor()`, `setInputGain()` — sve sa FFI sync.

---

## 15. DAW Waveform Generation

`NativeFFI.generateWaveformFromFile(path, cacheKey)` → Rust SIMD (AVX2/NEON) → JSON multi-LOD peaks → `parseWaveformFromJson()` → `(Float32List?, Float32List?)`. ~10ms za 10min stereo @ 48kHz. Demo waveform uklonjen.

---

## 16. Pro Tools Routing Gap Analysis

| # | Gap | Effort | Prioritet |
|---|-----|--------|-----------|
| 1 | Master Fader inserts: split pre/post vs all post-fader | Moderate | P1 |
| 2 | Fixed 6 buses vs dynamic creation | High | P2 |
| 3 | Pre-fader sends: field exists, NOT in audio callback | High | P1 |
| 4 | VCA send scaling: volume only vs volume+send levels | High | P2 |
| 5 | Insert slots: 8 vs 10 (A-E pre, F-J post) | Low | P3 |
| 6 | Bus-to-bus routing: all→Master vs any→any | Very High | P3 |

---

## 17. Action Strip Status

**DAW:** ✅ 100% — Browse, Edit, Mix, Process, Deliver (15/15 buttons connected)
**Middleware:** ✅ partial — Events/Routing connected, Containers/RTPC/Deliver have stubs
**Archive Panel:** ✅ Full — ZIP creation via `ProjectArchiveService`, FilePicker, progress indicator

---

## 18. Connectivity Summary

| Metric | Value |
|--------|-------|
| Overall DAW FFI Connectivity | 100% |
| Providers Connected | 7/7 |
| FFI Functions Used | 134+ |
| Ghost Code Removed | ~900 LOC |

---

## 19. Remaining TODOs

- ⏳ Real-time GR metering za Compressor/Limiter
- ⏳ FFT metering iz PLAYBACK_ENGINE za SpectrumAnalyzer

---

*Poslednji update: 2026-02-23 (OutputBus enum fix, legacy vs modern bus methods, createChannelFromTrack outputBus)*
*Condensed: 2026-03-09*
