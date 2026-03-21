# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## SLEDEĆA SESIJA

### SlotLab CUSTOM Events Tab
- [ ] Custom Events sistem u CUSTOM tabu
- [ ] ID format: `custom_<name>`

---

## IMPLEMENTIRANO (reference, ne za rad)

- **Signalsmith Stretch** — `audio_stretcher.rs`, zamena za PV, MIT ~Élastique kvalitet
- **Warp Markers** — `ClipWarpState` u track_manager.rs, per-segment stretch, 15 testova
- **Transient Detection** — `transient_detector.rs`, spectral flux, 8 testova
- **Warp UI** — `_WarpOverlayPainter`, `_WarpMarkerDragHandle`, drag+undo, cross-track
- **Warp Inspector** — toggle, detect, quantize dugmad u clip inspector
- **Dep Upgrade Faza 3+4** — cpal 0.17, wgpu 28, objc2 0.6, Edition 2024
- **SRC Quality** — 7 nivoa dropdown, adaptive diagnostics
- **Arch docs** — `PITCH_SHIFT_TIME_STRETCH.md`, `WARP_MARKERS.md`
