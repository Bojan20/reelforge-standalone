# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-21

## Key File Map

| System | Entry Point | Big Files |
|--------|------------|-----------|
| DAW UI | `main_layout.dart` | `timeline_screen.dart` |
| SlotLab | `slot_lab_screen.dart` (13K+) | `slot_lab_coordinator.dart` |
| Engine | `playback.rs` (7600+) | `sinc_table.rs` |
| r8brain | `crates/rf-r8brain/` (6 modula, 1713 linija) | offline render SRC |
| FFI | `native_ffi.dart` (21K+) | `crates/rf-bridge/src/lib.rs` |

## Active Traps

- `slot_lab_screen.dart` — 13K+ lines, NE MOŽE se razbiti
- `native_ffi.dart` — 21K+, auto-generated, READ ONLY
- `desktop_drop` 0.5 — MainFlutterWindow.swift hack, NE DIRATI
- Audio thread: NULA alokacija u `fill_buffer()` / `process_one_shot_voices()`

---

## SLEDEĆA SESIJA — KRITIČAN PRIORITET

### 1. ★ Signalsmith Stretch integracija (zamena za Phase Vocoder)

**Zašto:** Naš Phase Vocoder zvuči loše — metallic artefakti, phase incoherence, smearing.
Svi profesionalni DAW-ovi (Cubase, Pro Tools, Ableton) koriste specijalizovane algoritme (Élastique, Radius, proprietary). Naše rešenje: **Signalsmith Stretch** — MIT licenca, Rust bindovi postoje (`ssstretch` crate), kvalitet blizu Élastique Pro, real-time capable.

**Detaljan plan:** `.claude/architecture/PITCH_SHIFT_TIME_STRETCH.md`

- [ ] Dodaj `ssstretch` crate u rf-engine/Cargo.toml
- [ ] Napravi `SignalsmithStretcher` wrapper (pre-alloc na UI thread, zero-alloc audio)
- [ ] Zameni PhaseVocoder u `process_clip_with_crossfade_pv` sa Signalsmith
- [ ] Warp tab: ratio menja brzinu, Signalsmith čuva pitch
- [ ] Elastic tab: Signalsmith menja pitch, čuva brzinu (isti input/output length)
- [ ] Ukloni `phase_vocoder.rs` (ili arhiviraj)
- [ ] Runtime test: pitch shift bez artefakata, time stretch bez promene pitcha
- [ ] QA: cargo build + flutter analyze + 425 testova

### 2. Dep Upgrade Faza 4

- [ ] `objc` 0.2 → `objc2` 0.5+ (rf-plugin, rf-plugin-host)
- [ ] Edition 2021 → 2024 (7 crate-ova)
- [ ] Ukloni `wee_alloc` iz rf-wasm

### 3. SlotLab CUSTOM Events Tab

- [ ] Custom Events sistem u CUSTOM tabu (levi panel)
- [ ] ID format: `custom_<name>`

---

## ZAKLJUČAK IZ ISTRAŽIVANJA (2026-03-21)

### Phase Vocoder je NEADEKVATAN za produkcijski DAW

- Basic PV (phase-only): NE MENJA PITCH — magnitude ostaju u istim binovima
- Frequency bin resampling PV: MENJA PITCH ali sa teškim artefaktima (metallic, phasey, smeared)
- Svi veliki DAW-ovi koriste specijalizovane algoritme, ne basic PV
- FluxForge treba Signalsmith Stretch (MIT, Rust bindovi, blizu Élastique kvaliteta)

### Audio path discovery

- `process_clip_simple` (unified routing) se NE KORISTI u produkciji — samo u examples/
- `process_clip_with_crossfade` je PRAVI audio path koji CPAL callback poziva
- PV wiring u process_clip_simple bio je mrtav kod — nikad se nije izvršavao
- Dodata `process_clip_with_crossfade_pv` koja RADI ali PV kvalitet je neprihvatljiv

---

## ZAVRŠENO (2026-03-21, sesije 1-3)

- RT-1 through RT-4: Sinc resampler, adaptive quality, preserve_pitch, phase vocoder core
- Dep Upgrade Faza 3: cpal 0.17, wgpu 28, wide 1.2, glam 0.32, candle 0.9, freezed 3.0
- Flutter UI: Rate/Pitch sliders, SRC dropdown, Adaptive diagnostics, clip model fields
- QA: 15+ bagova pronađeno i fiksirano kroz 3 QA runde
- Phase vocoder wiring u process_clip_with_crossfade_pv (funkcionalno ali loš kvalitet)
- elastic_pro_set_ratio/pitch ne zavise više od ELASTIC_PROS instance
- Debug dijagnostika u Elastic i Warp panelima
- Istraživanje pitch/time stretch algoritama (dokument u architecture/)
