# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## DONE: Mixer Unification — Complete

- [x] F1-F3: Core Voice Mixer (provider, widget, MIX tab integracija)
- [x] M1: Stereo dual-pan full chain (Rust → FFI → Dart → UI)
- [x] M2.1: Bus routing dropdown u DAW mixer (availableOutputRoutes populated)
- [x] M2.2: Activity indicator u DAW mixer (green glow dot)
- [x] M2.3: Audition prep u DAW mixer (Alt+Click)
- [x] M3.1: Drag-drop reorder u SlotLab mixer
- [x] M3.3: Input section — gain trim + phase invert
- [x] M3.4: Stereo width kontrola
- [x] M3.5: Channel context menu
- [x] M3.7: Narrow/Regular strip toggle
- [x] M4.1: Snapshot save/load
- [x] M4.2: Batch operations (Ctrl+click multi-select, batch mute/solo/volume)
- [x] M4.3: Search/filter
- [x] M4.4: Solo in context (per-bus SIC)
- [x] M5.1: Rust — per-voice peak metering (meter_peak_l/r in OneShotVoice fill_buffer)
- [x] M5.2: FFI — getVoicePeakStereo export
- [x] M5.3: Dart — real per-voice peaks replace approximate bus metering
- [x] All stage defaults unity + stereo pan defaults
- [x] 7+ QA rundi, 20+ bug fixeva

---

## PENDING: Remaining

### M3: SlotLab Mixer ← DAW Features (remaining)

- [ ] **M3.2: Send slotovi** — per-layer aux sends, pre/post fader
- [ ] **M3.6: View presets** — Compact/Full/Custom saved views

---

## IMPLEMENTIRANO

- **37 crate-ova** | **71 providera** | **170+ servisa** | **3500+ networking linija**
- SlotLab Voice Mixer (complete: per-layer mixer, dual-pan, width, input, context menu, drag-drop, snapshots, batch ops, search, solo-in-context, real per-voice Rust metering)
- Stereo Dual-Pan Chain (Rust OneShotVoice pan_right → FFI → Dart → UI knobs)
- Per-Voice Metering (Rust meter_peak_l/r → FFI getVoicePeakStereo → Dart ticker)
- DAW Mixer Enhancements (bus routing dropdown, activity indicator, audition prep)
- Signalsmith Stretch (audio_stretcher.rs, MIT ~Élastique)
- Warp Markers (15 testova, end-to-end: model→detection→playback→UI→undo)
- Custom Events (EventRegistry sync, Play, probability, solo, zombie cleanup)
- RTPC (35 params, 9 curves, macros, DSP binding)
- Server Audio Bridge (trigger/rtpc/state/batch/snapshot + jitter + circuit breaker)
- MIDI Trigger (note→event, CC→RTPC, learn mode, live buffer)
- OSC Trigger (rosc crate, UDP server, address→event/RTPC)
- TriggerManager (position, marker, cooldown, seek hysteresis)
- Mock Game Server (echo/auto mode, slot cycle simulation)
- Connection Monitor Panel (bridge/MIDI/OSC stats)
- Dep Upgrade Faza 3+4 (cpal 0.17, wgpu 28, objc2 0.6, Edition 2024)
- 22 QA rundi, 70+ bugova, 447 testova, 0 issues
