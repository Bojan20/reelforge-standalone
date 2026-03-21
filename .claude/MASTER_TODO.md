# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## SLEDEĆA SESIJA

### Advanced Trigger Modes za Custom Events
- [ ] Position trigger: fire event at timeline position
- [ ] Marker trigger: fire event when playhead crosses marker
- [ ] MIDI trigger: fire event on MIDI note input
- [ ] OSC trigger: fire event on OSC message
- [ ] Cooldown timer između trigger-a

---

## IMPLEMENTIRANO

- **Signalsmith Stretch** — audio_stretcher.rs, MIT ~Élastique
- **Warp Markers** — end-to-end: data model, transient detection, per-segment playback, drag UI, undo, cross-track, quantize
- **Custom Events** — EventRegistry sync, Play trigger, probability, zombie cleanup
- **Dep Upgrade** — cpal 0.17, wgpu 28, objc2 0.6, Edition 2024
- **SRC Quality** — 7 nivoa, adaptive diagnostics
