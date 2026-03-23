# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## DONE: SlotLab Voice Mixer — Core + M1 + M3

- [x] F1-F3: Core (provider, widget, integracija, MIX tab voices sub-tab)
- [x] M1: Stereo dual-pan full chain (Rust → FFI → Dart → UI) — panRight u OneShotVoice, DSP dual-pan, sve bindinzi
- [x] M3.3: Input section — gain trim + phase invert per layer
- [x] M3.4: Stereo width kontrola — 0-200%, slider, mono/wide coloring
- [x] M3.5: Channel context menu — audition, reset pan/volume, phase, remove
- [x] M3.7: Narrow/Regular strip toggle — 56px vs 68px
- [x] M4.3: Search/filter — text filter po imenu/stage/bus
- [x] Channel selection highlight — left border glow
- [x] All stage defaults unity (1.0 / 0dB) + stereo pan defaults (L=-1, R=+1)
- [x] QA: 5 rundi, 15+ bug fixeva

---

## PENDING: Remaining Mixer Unification

### M2: DAW Mixer ← SlotLab Features

- [ ] **M2.1: Bus routing dropdown u DAW mixer** — output selector dropdown
- [ ] **M2.2: Activity indicator u DAW mixer** — glow dot kad track svira
- [ ] **M2.3: Audition u DAW mixer** — Alt+Click preview

### M3: SlotLab Mixer ← DAW Features (remaining)

- [ ] **M3.1: Drag-drop reorder kanala** — custom drag, sync sa layer order
- [ ] **M3.2: Send slotovi** — per-layer aux sends, pre/post fader
- [ ] **M3.6: View presets** — Compact/Full/Custom saved views

### M4: Smart Features (oba mixera)

- [ ] **M4.1: Snapshot save/load** — snimi mixer state, primeni kasnije
- [ ] **M4.2: Batch operations** — Ctrl+click multi-select, batch mute/solo/volume
- [ ] **M4.4: Solo in context** — solo kanal ali bus efekti čujni

### M5: Real Per-Voice Metering (Rust)

- [ ] **M5.1: Rust — AtomicF64 peak per voice**
- [ ] **M5.2: FFI — getVoicePeakStereo**
- [ ] **M5.3: Dart — poll voice peaks u ticker**

---

## IMPLEMENTIRANO

- **37 crate-ova** | **71 providera** | **170+ servisa** | **3500+ networking linija**
- SlotLab Voice Mixer (F1-F3 + M1 + M3: full per-layer mixer sa dual-pan, width, input, context menu)
- Stereo Dual-Pan Chain (Rust OneShotVoice pan_right → FFI → Dart → UI knobs)
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
