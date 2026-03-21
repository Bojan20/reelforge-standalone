# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-21

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- `native_ffi.dart` — 21K+, READ ONLY
- Audio thread: NULA alokacija, NULA lockova

---

## SLEDEĆA SESIJA — WARP MARKERS

**Arch doc:** `.claude/architecture/WARP_MARKERS.md`

### Faza 1: Data model + markers (engine)
- [ ] `WarpMarker` struct (source_pos, timeline_pos, type, locked)
- [ ] `ClipWarpState` per clip (markers, transients, enabled)
- [ ] `compute_segment_ratios()` per-segment stretch
- [ ] FFI: clip_add/remove/move_warp_marker
- [ ] Serialize za project save

### Faza 2: Transient detection
- [ ] `aubio-rs` dependency
- [ ] Spectral flux onset detection
- [ ] FFI: clip_detect_transients (async)
- [ ] Auto-create markers na transientima

### Faza 3: Per-segment stretch u playback
- [ ] `process_clip_with_crossfade` sa ClipWarpState
- [ ] Binary search segment lookup O(log N)
- [ ] Per-segment Signalsmith instanca
- [ ] Latency compensation

### Faza 4: Flutter UI
- [ ] Marker vizuelizacija u clip_widget
- [ ] Drag-to-warp interaction
- [ ] Transient display + quantize button
- [ ] Warp on/off per clip

### Faza 5: Quantize + cross-track
- [ ] Grid snap (1/4, 1/8, 1/16, triplet)
- [ ] Strength 0-100%
- [ ] Cross-track linked markers
- [ ] Undo/redo

### Ostalo
- [ ] SlotLab CUSTOM Events Tab
