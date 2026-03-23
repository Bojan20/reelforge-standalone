# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## DONE: Mixer Unification — COMPLETE

Svi taskovi implementirani, QA-ovani, pushani.

### Core
- [x] F1-F3: Voice Mixer (provider, widget, MIX tab integracija)

### M1: Stereo Dual-Pan Chain (Rust → FFI → Dart → UI)
- [x] pan_right u OneShotVoice, DSP dual-pan (equal-power per channel)
- [x] FFI + Dart bindings + UI knobs connected

### M2: DAW Mixer ← SlotLab Features
- [x] M2.1: Bus routing dropdown (availableOutputRoutes populated)
- [x] M2.2: Activity indicator (green glow dot)
- [x] M2.3: Audition prep (Alt+Click)

### M3: SlotLab Mixer ← DAW Features
- [x] M3.1: Drag-drop reorder (LongPressDraggable + custom order persistence)
- [x] M3.2: Send slotovi (bus-level aux sends in strip, drag level, pre/post toggle)
- [x] M3.3: Input section (gain drag + phase invert Ø button)
- [x] M3.4: Stereo width (mid/side DSP, 0-200%, Rust chain)
- [x] M3.5: Context menu (audition, reset, phase, remove)
- [x] M3.6: View presets (Full/Compact)
- [x] M3.7: Narrow/Regular toggle (56px/68px)

### M4: Smart Features
- [x] M4.1: Snapshot save/load
- [x] M4.2: Batch operations (Ctrl+click multi-select, batch mute/solo/volume)
- [x] M4.3: Search/filter
- [x] M4.4: Solo in context (per-bus SIC)

### M5: Real Per-Voice Metering (Rust)
- [x] M5.1: meter_peak_l/r in OneShotVoice fill_buffer
- [x] M5.2: FFI getVoicePeakStereo
- [x] M5.3: Dart ticker real peaks (replaces approximate)

### Full FFI Chains
- [x] Stereo dual-pan (pan_right): Rust → FFI → Dart → UI
- [x] Stereo width: Rust mid/side DSP → FFI → Dart → UI
- [x] Phase invert: Rust sample negation → FFI → Dart → UI
- [x] Input gain: Rust pre-fader multiplier → FFI → Dart → UI (dB→linear conversion)
- [x] Per-voice metering: Rust peak tracking → FFI → Dart ticker

### QA
- [x] 10+ QA rundi, 30+ bug fixeva
- [x] All stage defaults unity (1.0/0dB) + stereo pan (-1/+1)
- [x] Metering throttle (~30fps)
- [x] Filter cache optimization
- [x] Custom order persistence across rebuilds
- [x] Null safety (firstOrNull)
- [x] Pan knob double-tap undo commit
- [x] Audition applies all channel settings
- [x] Snapshot restores phaseInvert
- [x] Batch concurrent modification safety

---

## NEMA PENDING TASKOVA

Sve planirano je implementirano i QA-ovano.

---

## IMPLEMENTIRANO

- **37 crate-ova** | **71 providera** | **170+ servisa** | **3500+ networking linija**
- SlotLab Voice Mixer (complete: per-layer mixer, dual-pan, width, input, phase, sends, context menu, drag-drop, snapshots, batch ops, search, solo-in-context, real per-voice Rust metering, view presets)
- 5 Full FFI Chains (pan_right, stereo_width, phase_invert, input_gain, voice_peak metering)
- DAW Mixer Enhancements (bus routing dropdown, activity indicator, audition)
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
- 22+ QA rundi, 100+ bugova fixovano, 447 testova, 0 issues
