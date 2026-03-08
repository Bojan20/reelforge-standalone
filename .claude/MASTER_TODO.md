# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-08

## Status Summary

| System | Status |
|--------|--------|
| AUREXIS (88), Middleware (19), Core (129) | Done |
| FluxMacro (53), ICF (8), RTE (5), CTR (5), PPL (8) | Done |
| Unified SlotLab, Win Tier, StageCategory | Done |
| Config Panel Enhancements | Done |
| Config Undo/Redo + Visual Transition Editor | Done |
| **REVERB ULTIMATE — Valhalla-tier upgrade** | **TODO (0/47)** |

Analyzer: 0 errors, 0 warnings

---

## REVERB ULTIMATE — Valhalla-Tier Algorithmic Reverb

**Goal:** Podići AlgorithmicReverb na nivo Valhalla Room/VintageVerb/Plate kvaliteta.
**Scope:** Rust DSP (rf-dsp/src/reverb.rs), FFI (rf-engine), Flutter UI (fabfilter_reverb_panel.dart)
**Referenca:** Valhalla Room, VintageVerb, Plate, SuperMassive, FabFilter Pro-R 2

### FAZA 1 — Modulacija (Valhalla Velvet Noise) [0/5]

Trenutno: sinusni LFO 0.3Hz, fiksna dubina 0.0001-0.0031 — zvuči statično, periodičan chorus artefakt.
Cilj: Velvet noise modulacija (Sean Costello trademark) — eliminiše periodičnost, živ prostor.

- [ ] **R1.1** Velvet noise generator — sparse random impulse train (density 200-2000 impulses/sec)
- [ ] **R1.2** Per-delay-line nezavisni velvet noise (8 nezavisnih generatora, svaki sa random seed)
- [ ] **R1.3** Kubna interpolacija u FDNDelayLine::read_modulated() (zameni linearnu — eliminiše zipper noise)
- [ ] **R1.4** Spin + Wander razdvojeni parametri (Spin=brza modulacija 1-5Hz, Wander=spora 0.05-0.5Hz)
- [ ] **R1.5** Modulation depth range proširen: 0.0-0.01 (10× više od trenutnog 0.003 max)

### FAZA 2 — Early Reflections (ER Density Upgrade) [0/6]

Trenutno: 8 fiksnih tapova, prime-distributed [7-67]ms, fiksni gain. Siromašan prostorni osećaj.
Cilj: 24 tapa, per-style ER pattern, stereo ER dekorelacija, ER/Late mix kontrola.

- [ ] **R2.1** Proširiti ERTap array: 8 → 24 tapa sa prime-distributed delays [3-150]ms
- [ ] **R2.2** Per-style ER pattern: Room (kratki, gusti), Hall (široki, retki), Plate (ultra-gusti, bez gap-a), Chamber (mid-range), Spring (bounce pattern sa nelinearnim spacing-om)
- [ ] **R2.3** Stereo ER dekorelacija: L/R tapovi sa offset delays (ne isti pattern za oba kanala)
- [ ] **R2.4** ER → Late crossfade zona: smooth prelaz umesto hard cutoff (50ms crossfade window)
- [ ] **R2.5** ER Level parametar (param 15): nezavisna kontrola ranog signala -inf do +6dB
- [ ] **R2.6** Late Level parametar (param 16): nezavisna kontrola FDN repa -inf do +6dB

### FAZA 3 — Diffusion Network Upgrade [0/5]

Trenutno: 6 serial allpass, fiksni prime delays, feedback 0.35-0.60. Schroeder-basic.
Cilj: Nested allpass topologija (Lexicon-style), per-style diffusion network.

- [ ] **R3.1** Nested allpass: allpass-within-allpass (2 nivoa dubine) za gušći diffusion sa manje stepeni
- [ ] **R3.2** Lattice allpass struktura kao alternativni mod (VintageVerb-style)
- [ ] **R3.3** Per-style diffusion topologija: Plate=max density, Hall=medium+nested, Room=light serial, Spring=spring-line emulacija
- [ ] **R3.4** Diffusion allpass modulacija: LFO na delay lengths unutar allpass-a (sprečava metallic buildup)
- [ ] **R3.5** Diffusion feedback range proširen: 0.20-0.75 (trenutno 0.35-0.60 — preuzak za plate)

### FAZA 4 — Multi-Band Decay Shaping (3-4 banda) [0/5]

Trenutno: 2 benda (LP@250Hz, HP@4kHz), fiksni crossover. Gruba kontrola.
Cilj: 4 benda sa podešivim crossoverima, per-band decay time u sekundama.

- [ ] **R4.1** 4-band crossover: Low (20-250Hz), LowMid (250-2kHz), HighMid (2k-8kHz), High (8k-20kHz)
- [ ] **R4.2** Podešivi crossover frekvencije: 3 crossover pointa (parametri 17, 18, 19)
- [ ] **R4.3** Per-band decay multiplikator: 4 nezavisna (parametri: low, lowmid, highmid, high)
- [ ] **R4.4** Biquad crossover filteri (zameni one-pole) — TDF-II za stabilnost, 12dB/oct Linkwitz-Riley
- [ ] **R4.5** Decay time u sekundama (0.1s - 100s) umesto normalized 0-1 → korisnicima intuitivniji

### FAZA 5 — Output Processing [0/5]

Trenutno: samo M/S width + ducking. Nema output EQ, nema limiter.
Cilj: Integrisani output EQ + soft limiter + BPM sync predelay.

- [ ] **R5.1** Output EQ: 2-band shelf (Low shelf 80-500Hz ±12dB, High shelf 2k-16kHz ±12dB)
- [ ] **R5.2** Output EQ: parametric mid band (200Hz-8kHz, Q 0.5-5.0, ±12dB) — parametri 20-22
- [ ] **R5.3** Soft limiter na reverb output-u (threshold -1dBFS, ratio ∞:1, tanh) — sprečava clipping
- [ ] **R5.4** Pre-delay BPM sync opcija: quantize predelay na note values (1/4, 1/8, 1/16, dotted, triplet)
- [ ] **R5.5** Pre-delay feedback (0-50%): echo-style repeated predelay taps (ValhallaDelay-inspired)

### FAZA 6 — FDN Core Upgrade [0/6]

Trenutno: fiksni 8×8 Hadamard, prime delays, linearna interpolacija. Funkcionalan ali basic.
Cilj: Višestruke mixing matrice, FDN size opcija, delay line quality.

- [ ] **R6.1** Householder matrica kao alternativa Hadamard-u (bolja za manje FDN veličine)
- [ ] **R6.2** FDN size opcija: 4×4 (CPU-light), 8×8 (default), 16×16 (luxury dense) — param 23
- [ ] **R6.3** Allpass-in-feedback: mala allpass sekcija unutar svake FDN delay linije (gušći tail)
- [ ] **R6.4** Delay line jitter: ±2-5 samples random offset po liniji (sprečava comb-filter coloration)
- [ ] **R6.5** Feedback ceiling adaptive: decay 0-0.5 → max 0.94, decay 0.5-1.0 → max 0.98 (duži repovi bez instabiliteta)
- [ ] **R6.6** Chorus mode u feedback-u: pitch-shift ±cents u 2 linije (Shimmer-lite, SuperMassive-inspired)

### FAZA 7 — Nove Topologije / Stilovi [0/5]

Trenutno: 5 stilova (Room/Hall/Plate/Chamber/Spring) sa scaling faktorima. Svi ista topologija.
Cilj: Per-style topološke razlike + novi stilovi.

- [ ] **R7.1** Ambient stil: ultra-dugi diffusion, minimalne ER, max FDN size, mod depth cranked
- [ ] **R7.2** Shimmer stil: pitch-shifted feedback (+12st, octave up) u 2 od 8 FDN linija
- [ ] **R7.3** Nonlinear stil: waveshaping u feedback (tanh drive, bitcrusher option) za lo-fi character
- [ ] **R7.4** Vintage stil: emulacija Lexicon 224/480 (specifični delay ratios, lower diffusion, subtle modulation)
- [ ] **R7.5** Gated stil: envelope gate na reverb tail (attack, hold, release) — 80s drum reverb

### FAZA 8 — Flutter UI Upgrade [0/7]

Trenutno: 15 parametara u FabFilter panelu. Nema vizualizaciju decay EQ-a, nema ER prikaz.
Cilj: Pro-R 2 nivo vizualizacije + novi parametri u UI.

- [ ] **R8.1** Decay EQ vizualizacija: spektar sa decay vremenom po frekvenciji (CustomPainter, 4 benda)
- [ ] **R8.2** ER vizualizacija: stem plot sa 24 tapa, time × gain, stereo L/R boja
- [ ] **R8.3** Spin/Wander kontrole: dva nova knoba u Character sekciji
- [ ] **R8.4** ER Level / Late Level: dva nova knoba u main sekciji
- [ ] **R8.5** Output EQ sekcija: 3-band EQ sa grafičkim drag-and-drop čvorovima
- [ ] **R8.6** BPM sync toggle + note value picker za predelay
- [ ] **R8.7** FDN size picker (4/8/16) i matrix type picker (Hadamard/Householder) u Advanced sekciji

### FAZA 9 — FFI + ReverbWrapper Update [0/3]

- [ ] **R9.1** Proširiti ReverbWrapper: 15 → ~28 parametara (ER level, late level, crossovers, output EQ, spin, wander, FDN size)
- [ ] **R9.2** FFI setteri za sve nove parametre u native_ffi.dart
- [ ] **R9.3** Preset sistem: 20+ factory preseta (Small Room, Large Hall, Vocal Plate, Drum Room, Cathedral, Shimmer Pad, 80s Gated, Lo-Fi, Ambient Wash, Spring Vintage...)

---

### Rezime faza

| Faza | Opis | Taskova | Impact na zvuk |
|------|------|---------|----------------|
| F1 | Velvet Noise modulacija | 5 | ★★★★★ (najveći) |
| F2 | ER Density 8→24 | 6 | ★★★★☆ |
| F3 | Nested Allpass diffusion | 5 | ★★★★☆ |
| F4 | 4-band decay shaping | 5 | ★★★☆☆ |
| F5 | Output processing | 5 | ★★★☆☆ |
| F6 | FDN core upgrade | 6 | ★★★★☆ |
| F7 | Novi stilovi | 5 | ★★★☆☆ |
| F8 | UI vizualizacija | 7 | ★★☆☆☆ (visual) |
| F9 | FFI + preseti | 3 | ★★☆☆☆ (wiring) |
| **TOTAL** | | **47** | |

**Prioritet implementacije:** F1 → F2 → F3 → F6 → F4 → F7 → F5 → F9 → F8

---

## Previous (Complete)

### Config Undo/Redo + Visual Transition Editor (2026-03-08)
- ConfigUndoManager: 100-step snapshot stack, 500ms merge window
- TransitionTimelineEditor: 6-track CustomPaint
- Per-phase audio stage pickers

### Config Panel Enhancements
- Win tier: freeze fix, RangeSliders, chaining, accordion, validation, simulator
- Scene transitions: durationMs scaling, 5 styles, TEST preview, audio stage picker
- Symbol art: mini-reel preview, batch import, undo wired
