# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## DONE: SlotLab Voice Mixer — Core (F1-F3)

- [x] F1: SlotVoiceMixerProvider — model, rebuild, bidirekcioni sync, voice mapping, metering
- [x] F2: SlotVoiceMixer widget — strips, faders, knobs, meters, M/S, bus routing, fixed master
- [x] F3: MIX tab integracija — voices sub-tab, enum, controller, service locator, main.dart

---

## PENDING: Mixer Unification — DAW ↔ SlotLab Cross-Pollination

Cilj: oba mixera imaju iste feature-e. DAW dobija SlotLab inovacije, SlotLab dobija DAW profesionalnost.

### M1: Stereo Dual-Pan Lanac (Rust → FFI → Dart → UI)

**Blocker za stereo pan u SlotLab voice mixeru.**

- [ ] **M1.1: Rust — panRight u OneShotVoice** — dodaj `pan_right: f32` field, `SetPanRight` command variant, `set_voice_pan_right()` metod, DSP processing za dual-pan L/R channel gains
- [ ] **M1.2: FFI — engine_set_voice_pan_right** — export u ffi.rs, bridge u api.rs/lib.rs
- [ ] **M1.3: Dart FFI — setVoicePanRight()** — NativeFFI binding, typedef, lookup
- [ ] **M1.4: Model — panRight u SlotEventLayer** — novo polje, copyWith, JSON serialization, default 0.0 mono / 1.0 stereo
- [ ] **M1.5: Service — AudioPlaybackService panRight** — updateLayerPanRight(), playFileToBus panRight param
- [ ] **M1.6: Provider — CompositeEventSystemProvider** — setLayerPanRightContinuous/Final, _updateEventLayerInternal panRight sync
- [ ] **M1.7: Provider — SlotVoiceMixerProvider** — setChannelPanRight(), bidirekcioni sync
- [ ] **M1.8: Widget — SlotVoiceMixer R knob connected** — onChanged → setChannelPanRight real-time FFI
- [ ] **M1.9: QA + Build + Test** — flutter analyze, cargo build, xcodebuild, visual test

### M2: DAW Mixer ← SlotLab Features

- [ ] **M2.1: Bus routing dropdown u DAW mixer** — output selector sa dropdown popup (iz UltimateMixer strip-a), promeni bus → MixerProvider.setChannelOutput
- [ ] **M2.2: Activity indicator u DAW mixer** — glow dot kad track svira (iz MeterProvider peak data)
- [ ] **M2.3: Audition u DAW mixer** — Alt+Click na header = preview track audio jednom

### M3: SlotLab Mixer ← DAW Features

- [ ] **M3.1: Drag-drop reorder kanala** — ReorderableListView ili custom drag, sync sa composite event layer order
- [ ] **M3.2: Send slotovi** — per-layer aux sends (iz AuxSendsPanel pattern), pre/post fader toggle
- [ ] **M3.3: Input section** — gain trim + phase invert per layer
- [ ] **M3.4: Stereo width kontrola** — per-layer width knob (0=mono, 1=normal, 2=wide)
- [ ] **M3.5: Channel context menu** — right-click: rename, change bus, remove, duplicate, copy settings
- [ ] **M3.6: View presets** — Compact/Full/Buses Only/Custom saved views
- [ ] **M3.7: Narrow/Regular strip toggle** — 56px vs 68px mode

### M4: Smart Features (oba mixera)

- [ ] **M4.1: Snapshot save/load** — snimi mixer state, primeni kasnije
- [ ] **M4.2: Batch operations** — Ctrl+click multi-select, batch mute/solo/volume
- [ ] **M4.3: Search/filter** — text filter kanala po imenu ili busu
- [ ] **M4.4: Solo in context** — solo kanal ali bus efekti čujni

### M5: Real Per-Voice Metering (Rust)

- [ ] **M5.1: Rust — AtomicF64 peak per voice** — meter_peak_l/r u OneShotVoice, update u audio callback
- [ ] **M5.2: FFI — getVoicePeakStereo** — export, bridge
- [ ] **M5.3: Dart — poll voice peaks** — u SlotVoiceMixerProvider ticker, zameni approximate metering

---

## IMPLEMENTIRANO

- **37 crate-ova** | **70 providera** | **170+ servisa** | **3500+ networking linija**
- SlotLab Voice Mixer (F1-F3: provider, widget, integracija)
- Signalsmith Stretch (audio_stretcher.rs, MIT ~Élastique)
- Warp Markers (15 testova, end-to-end: model→detection→playback→UI→undo)
- Custom Events (EventRegistry sync, Play, probability, solo, zombie cleanup)
- RTPC (35 params, 9 curves, macros, DSP binding — VEĆ POSTOJEĆI)
- Server Audio Bridge (trigger/rtpc/state/batch/snapshot + jitter + circuit breaker)
- MIDI Trigger (note→event, CC→RTPC, learn mode, live buffer)
- OSC Trigger (rosc crate, UDP server, address→event/RTPC)
- TriggerManager (position, marker, cooldown, seek hysteresis)
- Mock Game Server (echo/auto mode, slot cycle simulation)
- Connection Monitor Panel (bridge/MIDI/OSC stats)
- Dep Upgrade Faza 3+4 (cpal 0.17, wgpu 28, objc2 0.6, Edition 2024)
- 22 QA rundi, 70+ bugova, 447 testova, 0 issues
