# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-21

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- `native_ffi.dart` — 21K+, READ ONLY
- Audio thread: NULA alokacija, NULA lockova

---

## SLEDEĆA SESIJA — WARP MARKERS END-TO-END

**Arch doc:** `.claude/architecture/WARP_MARKERS.md`

### Engine → Dart sync (KRITIČNO — warp se ne vidi bez ovoga)
- [ ] FFI: `clip_get_warp_state` → vraća markers + transients + enabled
- [ ] Dart: nakon detect/add/move/quantize, refreshuj TimelineClip.warpMarkers iz engine-a
- [ ] Automatski sync posle svake warp operacije

### Detect Transients UI
- [ ] Dugme u clip context menu ili clip inspector: "Detect Transients"
- [ ] Poziva `clipDetectTransients()` → refreshuje clip → transients se vide u overlay-u
- [ ] Sensitivity slider (opciono)

### Drag-to-Warp interaction (KRITIČNO — korisnik ne može da pomera markere)
- [ ] GestureDetector/Listener na svakom markeru u clip_widget Stack
- [ ] onPanStart/Update/End → poziva `clipMoveWarpMarker()` FFI
- [ ] Visual feedback tokom drag-a (marker prati kurzor)
- [ ] Double-click na transient → kreira warp marker na toj poziciji

### Warp kontrole u clip inspector
- [ ] Warp on/off toggle (poziva `clipWarpEnable`)
- [ ] Quantize dugme sa grid dropdown (1/4, 1/8, 1/16) + strength slider
- [ ] "Create from Transients" dugme
- [ ] Marker count display

### Elastic/Warp tab integracija
- [ ] Warp tab: kad warp enabled, prikaži marker listu umesto globalnog ratio knoba
- [ ] Elastic tab: pitch shift radi per-segment kad warp aktivan

### Faza 5: Cross-track + Undo
- [ ] Cross-track linked markers (Reaper-style)
- [ ] Undo/redo za sve warp operacije
- [ ] Warp marker copy/paste između klipova

### Ostalo
- [ ] SlotLab CUSTOM Events Tab
