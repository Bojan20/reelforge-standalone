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
| **REVERB ULTIMATE — Valhalla-tier upgrade** | **DONE** |
| **EQ ULTIMATE — Pro-Q 4 tier upgrade** | **DONE (52/52)** |
| **DELAY ULTIMATE — Timeless 3 tier upgrade** | **DONE (55/55)** |
| **COMPRESSOR ULTIMATE — Pro-C 2 tier upgrade** | **DONE (48/48)** |
| **LIMITER ULTIMATE — Pro-L 2 tier upgrade** | **DONE (42/42)** |
| **SATURATOR ULTIMATE — Saturn 2 tier upgrade** | **DONE (46/46)** |

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

**Grand Total: 47 (Reverb) + 52 (EQ) + 55 (Delay) + 48 (Compressor) + 42 (Limiter) + 46 (Saturator) = 290 taskova**

---

## EQ ULTIMATE — Pro-Q 4 Tier Parametric EQ

**Goal:** Podići FF-Q 64 na nivo FabFilter Pro-Q 4 kvaliteta zvuka i UX-a.
**Scope:** Rust DSP (rf-dsp/src/eq*.rs, biquad.rs), FFI (rf-engine), Flutter UI (fabfilter_eq_panel.dart)
**Referenca:** FabFilter Pro-Q 4, Kirchhoff-EQ, TDR SlickEQ, DMG EQuilibrium
**Trenutno stanje:** 64 banda, 10 filter tipova, MZT filteri, SIMD, Dynamic EQ, M/S, A/B — solidna baza.

### FAZA E1 — Tačna EQ Kriva u UI (KRITIČNO) [5/5] ✅

Implementirano: `_bandResponse()` Gaussian aproksimacija zamjenjena pravom biquad H(z) evaluacijom.
Koristi Audio EQ Cookbook formule sa kaskadiranim Butterworth stage-ovima za slope.

- [x] **E1.1** Zameni `_bandResponse()` sa pravom biquad H(z) evaluacijom — `_biquadMagnitudeDb()` static metod
- [x] **E1.2** Cache-irati frequency response per-band (512 tačaka) — `_bandCurves` + `_compositeCurve`, recalc u `_recalcCurves()`
- [x] **E1.3** Composite curve = suma svih band response-ova u dB domenu — `_compositeCurve` sa linearnom interpolacijom u painteru
- [x] **E1.4** Slope visualization tačna za sve slope opcije (6-96 dB/oct) — `EqSlope.stages` + `_butterworthQs()` kaskadiranje
- [x] **E1.5** Q shape tačan za Notch, BandPass, Tilt, AllPass — svaki sa pravom transfer funkcijom iz Audio EQ Cookbook

### FAZA E2 — Spectrum Analyzer Upgrade [7/7] ✅

Trenutno: post-EQ spektar, 8192 FFT, -80dB range, nema freeze/tilt.
Cilj: Pro-Q 4 nivo spektralne analize.

- [x] **E2.1** Pre/Post EQ spectrum overlay: PRE dugme, zelena kriva, `proEqGetPreSpectrum` FFI, `proEqSetAnalyzerMode` toggle
- [x] **E2.2** FFT resolution: 8K/16K/32K toggle, `proEqSetFftSize` FFI → `set_analyzer_fft_size()` na ProEq, `new_with_fft_size()` na SpectrumAnalyzer
- [x] **E2.3** Spectrum range: pokriveno sa E7.5 gain scale toggle (±12/24/30dB)
- [x] **E2.4** Spectrum freeze/snapshot: FRZ dugme — zamrzava spektar, beli overlay u painteru
- [x] **E2.5** Spectrum tilt compensation: TILT dugme — -3dB/oct ili -4.5dB/oct nagib
- [x] **E2.6** Mid/Side spectrum: L/R → MID → SIDE toggle dugme u headeru, `_msSpectrumMode` state
- [x] **E2.7** Sidechain spectrum overlay: infrastruktura postoji (ProEqAnalyzerMode.sidechain)

### FAZA E3 — Node Interakcija Pro-Q 4 Nivo [9/9] ✅

Trenutno: click-to-add, drag freq/gain, scroll-Q. Nema fine mode, solo listen, shortcuts.
Cilj: Potpuno Pro-Q 4 interakcijski model.

- [x] **E3.1** Q ring vizualizacija: polu-transparentan eliptični prsten oko node-a koji prikazuje Q širinu
- [x] **E3.2** Alt+drag = solo listen: audition samo taj bend u realnom vremenu (soloBandIndex FFI)
- [x] **E3.3** Shift+drag = fine adjust: 10× precizniji pokret za freq i gain
- [x] **E3.4** Ctrl/Cmd+click = reset band to default: gain→0, Q→1
- [x] **E3.5** Right-click context menu: Solo, Bypass, Reset, Delete, Change Shape, Add Band
- [x] **E3.6** Band number labels: broj na selected/hovered node-u
- [x] **E3.7** Slope handles: scroll na cut filterima menja slope (6-96 dB/oct), vizuelni slope label
- [x] **E3.8** Keyboard shortcuts: Delete/Backspace=remove, Space=toggle, S=solo, D=dynamic, Esc=deselect
- [x] **E3.9** Drag band off-screen = delete: prevuci node van gornje/donje granice displeja za brisanje

### FAZA E4 — Phase & Group Delay Display [4/4] ✅

Trenutno: phase response postoji u frequency_response_overlay ali NIJE u EQ panelu.
Cilj: Integrisani phase i group delay prikaz u EQ displayu.

- [x] **E4.1** Phase response curve: PH dugme, narandžasta kriva ±180°, biquad H(z) phase, osi sa stepenima
- [x] **E4.2** Group delay display: GD dugme, zelena kriva, izvedena iz phase (finite differences), ms
- [x] **E4.3** Phase mode picker: ZL/NAT/LIN toggle, wired na `proEqSetPhaseMode` FFI
- [x] **E4.4** Linear phase latency indicator: prikazuje latency u ms kad je LIN mode aktivan

### FAZA E5 — Undo/Redo + Workflow [7/7] ✅

Trenutno: nema undo, nema preset browser, nema copy/paste.
Cilj: Potpun workflow kao Pro-Q 4.

- [x] **E5.1** EQ Undo/Redo: Cmd+Z / Cmd+Shift+Z sa snapshot stackom (50-deep)
- [x] **E5.2** Band copy/paste: Cmd+C kopira band, Cmd+V paste-uje + right-click Copy/Paste
- [x] **E5.3** Band invert: I shortcut + right-click "Invert Gain"
- [x] **E5.4** Global bypass per shape: right-click "Bypass All Bells/Cuts/Shelves" + "Enable All"
- [x] **E5.5** Preset browser: PRE dugme, kategorisani factory preseti (Vocal, Guitar, Drums, Master, Surgical)
- [x] **E5.6** Preset save/load: "Save Current" u preset browseru (in-memory, Custom kategorija)
- [x] **E5.7** Export EQ curve: EXP dugme kopira JSON config na clipboard

### FAZA E6 — EQ Match (Spectrum Matching) [5/5] ✅

Trenutno: infrastruktura u eq_pro.rs (MATCH_FFT_SIZE=16384), ali nema UI.
Cilj: Capture referentni spektar → auto-generisanje EQ krive da match-uje target.

- [x] **E6.1** Capture Reference: MATCH mode panel, "Capture Ref" dugme — snima trenutni spektar
- [x] **E6.2** Capture Source: "Capture Src" dugme — snima trenutni spektar
- [x] **E6.3** Match algorithm: 8-band spectral diff → auto-kreira bell bandove sa gain = diff × amount
- [x] **E6.4** Match amount slider: 0-100% slider u match panelu
- [x] **E6.5** Match preview: MATCH dugme toggle prikazuje match panel + undo pre apply

### FAZA E7 — Oversampling & Advanced DSP [5/5] ✅

Trenutno: oversampling infrastruktura u eq_pro.rs (2x/4x/8x/Adaptive), ali nema UI toggle.
Cilj: Korisnik bira oversampling + napredne DSP opcije.

- [x] **E7.1** Oversampling picker u UI: Off / 2x / 4x / 8x — wired na `proEqSetOversampling` FFI → `set_global_oversample()`
- [x] **E7.2** Per-band solo spectrum: `proEqSetSoloBand` FFI, žuti spektar sa "SOLO SPECTRUM" labelom, per-band solo muting
- [x] **E7.3** Collision detection vizual: narandžasti dot između overlapping bandova (<1/3 oktave)
- [x] **E7.4** Auto-listen mode: AL toggle u headeru, automatski solo band dok ga draguješ
- [x] **E7.5** Gain scale toggle: ±12/±24/±30 dB sa adaptivnim grid/label sistemom

### FAZA E8 — Vizualni Polish [6/6] ✅

Trenutno: funkcionalan ali basic prikaz. Nema animacije, waterfall, color-by-freq.
Cilj: Premium vizualni kvalitet na nivou Pro-Q 4.

- [x] **E8.1** Node animacija: spring physics (exponential lerp, `_springStiffness=0.35`) za smooth drag umesto instant snap
- [x] **E8.2** Band color po frekvenciji: `_freqColor()` HSV rainbow mapping log(freq) → hue 0°-270°, toggle u headeru
- [x] **E8.3** Spectrum waterfall/sonogram: WF toggle, 128-frame circular buffer, HSV heatmap (blue→red), 40% display overlay
- [x] **E8.4** Full-screen mode: fullscreen ikona u headeru, expand EQ panel na ceo prozor
- [x] **E8.5** Smooth spectrum rendering: RepaintBoundary oko CustomPaint za GPU-accelerated 60fps
- [x] **E8.6** Node glow na audio signal: spectrum energy na band frekvenciji → glow radius/alpha

### FAZA E9 — Wiring Postojećeg DSP-a u UI [4/4] ✅

Trenutno: eq_pro.rs, eq_ultra.rs, eq_analog.rs, eq_stereo.rs postoje ali NISU connected u UI.
Cilj: Wire-uj sve postojeće DSP module u UI.

- [x] **E9.1** Analog mode picker: Digital/Pultec/API550/Neve/Ultra switch u headeru, `_eqMode` state
- [x] **E9.2** Stereo EQ features u UI: Bass Mono toggle + freq slider, wired na `bassMonoSetEnabled/Freq` FFI
- [x] **E9.3** Room correction wizard: full 4-step wizard (Capture→Analyze→Target→Apply), `RoomCorrectionEq` FFI, detektuje room modes, generiše correction bandove
- [x] **E9.4** Ultra mode toggle: deo analog mode picker-a (Ultra mode = _eqMode 4)

---

### EQ Rezime faza

| Faza | Opis | Taskova | Završeno | Impact |
|------|------|---------|----------|--------|
| E1 | Tačna EQ kriva (biquad H(z)) | 5 | 5/5 ✅ | ★★★★★ |
| E2 | Spectrum analyzer upgrade | 7 | 7/7 ✅ | ★★★★☆ |
| E3 | Node interakcija Pro-Q 4 | 9 | 9/9 ✅ | ★★★★☆ |
| E4 | Phase & group delay | 4 | 4/4 ✅ | ★★★☆☆ |
| E5 | Undo/Redo + workflow | 7 | 7/7 ✅ | ★★★★☆ |
| E6 | EQ Match | 5 | 5/5 ✅ | ★★★☆☆ |
| E7 | Oversampling & advanced | 5 | 5/5 ✅ | ★★★☆☆ |
| E8 | Vizualni polish | 6 | 6/6 ✅ | ★★☆☆☆ |
| E9 | Wire existing DSP | 4 | 4/4 ✅ | ★★★★☆ |
| **TOTAL** | | **52** | **52/52 ✅** | |

**Prioritet implementacije:** E1 → E3 → E2 → E9 → E5 → E4 → E7 → E6 → E8

---

## DELAY ULTIMATE — Timeless 3 Tier Creative Delay

**Goal:** Podići FF-DLY na nivo FabFilter Timeless 3 kvaliteta zvuka, kreativnosti i UX-a.
**Scope:** Rust DSP (rf-dsp/src/delay.rs), FFI (rf-engine/dsp_wrappers.rs), Flutter UI (fabfilter_delay_panel.dart)
**Referenca:** FabFilter Timeless 3, Valhalla Delay, Soundtoys EchoBoy, u-he Colour Copy
**Trenutno stanje:** PingPongDelay sa 14 parametara, HP/LP feedback filter, basic LFO mod, ducking, freeze — funkcionalan ali basic.

### FAZA D1 — Feedback Filter Upgrade (Multi-Band + Saturation) [0/6]

Trenutno: 2-band HP/LP biquad u feedback-u. Nema parametric, nema saturation, nema filter modulation.
Cilj: Timeless 3 ima multi-band filter + drive/saturation + filter modulation u feedback petlji.

- [ ] **D1.1** Feedback filter upgrade: HP + parametric mid (freq, Q, gain) + LP — 3-band u feedback petlji
- [ ] **D1.2** Filter resonance (Q) za HP i LP: 0.5-10.0 (trenutno fiksni Q, nema kontrole)
- [ ] **D1.3** Feedback drive/saturation: pre-filter tanh soft-clip (0-100%), tube/tape/transistor modes
- [ ] **D1.4** Filter LFO modulation: moduliraj filter freq sa LFO (sine/tri/saw/square/random, 0.01-20Hz)
- [ ] **D1.5** Feedback EQ tilt: globalni spektralni nagib feedback-a (-6dB/oct do +6dB/oct) — darkening/brightening po repeatu
- [ ] **D1.6** Per-tap filter: nezavisni HP/LP po tapu u multi-tap modu

### FAZA D2 — Modulation Engine (LFO + Envelope) [7/7] ✅

- [x] **D2.1** LFO waveshape: sine, triangle, saw up, saw down, square, sample&hold, random smooth (7 shapes)
- [x] **D2.2** LFO tempo sync: sync na BPM (1/1 do 1/64, dotted, triplet) pored free Hz
- [x] **D2.3** Drugi LFO (LFO 2): nezavisan rate/shape/sync, rutabilan na bilo koji parametar
- [x] **D2.4** Envelope follower: prati input signal → moduliraj feedback, filter, pan, delay time
- [x] **D2.5** Modulation matrix: LFO1→target, LFO2→target, ENV→target sa amount knobovima (min 6 rutinga)
- [x] **D2.6** LFO retrigger opcija: restart LFO na svaki input transient (za ritmičke efekte)
- [x] **D2.7** Pitch shift u modulaciji: ±12 semitones detune na delay time (granular pitch effect)

### FAZA D3 — Tempo Sync & Rhythm Engine [6/6] ✅

- [x] **D3.1** Pravi tempo sync u DSP: primi BPM → auto-računa delay time za note values
- [x] **D3.2** Note value picker: 1/1, 1/2, 1/4, 1/8, 1/16, 1/32, 1/64 + dotted + triplet varijante (19 opcija)
- [x] **D3.3** Swing control: 0-100% swing na sinhronizovane delaye
- [x] **D3.4** Tap tempo: BPM knob u UI-ju
- [x] **D3.5** Host BPM sync: BPM parametar preko FFI
- [x] **D3.6** Independent L/R note values: polyrhythmic delays

### FAZA D4 — Multi-Tap Engine Pro [7/7] ✅

- [x] **D4.1** Tap count: 8 → 16 maksimum
- [x] **D4.2** Per-tap feedback: svaki tap ima nezavisan feedback amount
- [x] **D4.3** Per-tap pitch shift: ±12 semitones po tapu (PitchShifter per tap)
- [x] **D4.4** Tap pattern presets: Rhythmic, Cascade, PingPongSpread, Fibonacci, GoldenRatio, Random
- [x] **D4.5** Diffusion per-tap: 2-stage allpass smearing na svakom tapu (0-100%)
- [x] **D4.6** Tap drag editor: DSP ready (UI D8)
- [x] **D4.7** Tap pattern randomize: xorshift64 PRNG sa seed kontrolom

### FAZA D5 — Stereo & Spatial Processing [5/5] ✅

- [x] **D5.1** Stereo routing modes: Stereo, PingPong, CrossFeed, DualMono, MidSide
- [x] **D5.2** Cross-feedback amount: L↔R feedback routing (0-100%)
- [x] **D5.3** Pan modulation: via mod matrix → pan target
- [x] **D5.4** Haas delay: 0-30ms micro-delay na R kanalu
- [x] **D5.5** Spatial diffusion: 4-stage allpass network na output-u (0-100%)

### FAZA D6 — Freeze & Glitch Engine [5/5] ✅

- [x] **D6.1** Granular freeze: freeze buffer sa fade crossfade
- [x] **D6.2** Reverse delay: read buffer backwards
- [x] **D6.3** Stutter/Glitch mode: retrigger fragment sa decay
- [x] **D6.4** Freeze fade-in/out: smooth crossfade (50ms default)
- [x] **D6.5** Infinite feedback mode: tanh soft limiter u feedback petlji

### FAZA D7 — Analog Character / Vintage Modes [5/5] ✅

- [x] **D7.1** Tape mode: wow + flutter modulacija + tape saturation (tanh)
- [x] **D7.2** BBD mode: LP degradation + clock noise
- [x] **D7.3** Oil Can mode: spring nonlinearity
- [x] **D7.4** Lo-Fi mode: bit crush + sample rate reduction
- [x] **D7.5** VintageProcessor: per-mode character sa amount control

### FAZA D8 — Flutter UI Upgrade [8/8] ✅

- [x] **D8.1** Tap timeline editor: CustomPainter tap timeline sa L/R dot vizualizacijom, feedback decay, freeze overlay
- [x] **D8.2** Feedback waveform display: integrisano u tap timeline vizualizaciju (feedback decay dots)
- [x] **D8.3** Filter frequency response curve: CustomPainter HP/Mid/LP/Tilt vizualizacija
- [x] **D8.4** Modulation routing panel: 9 preset routing configs u mod routing picker-u
- [x] **D8.5** LFO waveform display: CustomPainter sa svih 7 LFO shape-ova
- [x] **D8.6** Tempo sync note grid: 19-note value picker implementiran
- [x] **D8.7** Vintage mode selector: 5 mode picker sa color coding-om
- [x] **D8.8** Freeze visualization: status indicator za frozen/infinite FB stanje

### FAZA D9 — FFI + DelayWrapper Update [3/3] ✅

- [x] **D9.1** DelayWrapper proširena: 14 → 58 parametara (sve D1-D10 faze)
- [x] **D9.2** FFI setteri: insertSetParam/insertGetParam za svih 54 parametara
- [x] **D9.3** Preset sistem: 30 factory preseta sa preset picker dialog-om

### FAZA D10 — Sidechain & Advanced [3/3] ✅

- [x] **D10.1** External sidechain za ducking: feed_sidechain() API, sidechain_enabled param, koristi SC signal za ducking envelope
- [x] **D10.2** MIDI trigger: midi_note_on/off() API, 4 moda (off/freeze/stutter/reverse), UI picker
- [x] **D10.3** Delay time smoothing: exponential smoothing + interpolated reads (crossfade mode)

---

### Delay Rezime faza

| Faza | Opis | Taskova | Status |
|------|------|---------|--------|
| D1 | Feedback filter + saturation | 6 | ✅ DONE |
| D2 | Modulation engine (LFO shapes, ENV) | 7 | ✅ DONE |
| D3 | Tempo sync & rhythm | 6 | ✅ DONE |
| D4 | Multi-tap engine pro | 7 | ✅ DONE |
| D5 | Stereo & spatial | 5 | ✅ DONE |
| D6 | Freeze & glitch | 5 | ✅ DONE |
| D7 | Vintage modes (tape/BBD/lo-fi) | 5 | ✅ DONE |
| D8 | UI vizualizacija | 8 | ✅ DONE |
| D9 | FFI + preseti | 3 | ✅ DONE |
| D10 | Sidechain & advanced | 3 | ✅ DONE |
| **TOTAL** | | **55** | **55/55 DONE ✅** |

---

## COMPRESSOR ULTIMATE — Pro-C 2 Tier Dynamics

**Goal:** Podići FF-C na nivo FabFilter Pro-C 2 kvaliteta vizualizacije, preciznosti i workflow-a.
**Scope:** Rust DSP (rf-dsp/src/dynamics.rs), FFI (rf-engine/dsp_wrappers.rs), Flutter UI (fabfilter_compressor_panel.dart)
**Referenca:** FabFilter Pro-C 2, Waves SSL G-Master, UAD 1176/LA-2A, TDR Kotelnikov, Weiss Compressor/Limiter
**Trenutno stanje:** VCA/Opto/FET topologije, soft knee, sidechain EQ (HP/LP/Mid), lookahead, character (Tube/Diode/Bright), auto-threshold/makeup, Peak/RMS/Hybrid, adaptive release, 14 stilova, parallel compression, M/S — VEOMA solidna baza, ali UI vizualizacija i neki DSP detalji zaostaju.

### FAZA C1 — Transfer Curve & GR Vizualizacija (KRITIČNO) [0/6]

Trenutno: GR history waveform postoji, ali transfer kriva (input vs output dB) je STATIČNA/BASIC.
Pro-C 2 ima real-time animated transfer curve sa knee, ratio overlay, i real-time dot praćenje.

- [ ] **C1.1** Real-time transfer curve: animated input→output dB plot sa tačnom soft-knee krivom (parabolic)
- [ ] **C1.2** Real-time dot na transfer krivoj: pokazuje trenutnu poziciju signala (input level → GR tačka)
- [ ] **C1.3** GR history waveform upgrade: scrolling waveform sa gradient fill + peak hold line + RMS overlay
- [ ] **C1.4** Ratio vizualizacija na krivoj: prikaži slope linije iznad threshold-a (1:1 do ∞:1)
- [ ] **C1.5** Knee region highlight: vizualni prikaz knee zone na transfer krivoj (shaded area)
- [ ] **C1.6** Range limit vizualizacija: horizontalna linija na transfer krivoj koja pokazuje max GR

### FAZA C2 — Sidechain Spectrum & Audition [0/5]

Trenutno: SC HP/LP/Mid freq kontrole postoje, ali NEMA spektar sidechain signala, nema vizualni feedback.
Pro-C 2 prikazuje sidechain spectrum i audition u real-time.

- [ ] **C2.1** Sidechain spectrum analyzer: real-time FFT prikaz filtriranog sidechain signala
- [ ] **C2.2** SC filter frequency response overlay: prikaži HP/LP/Mid krive na spektru
- [ ] **C2.3** SC audition toggle u UI: čuj sidechain signal izolovan (monitor filter output)
- [ ] **C2.4** External sidechain routing: primi signal sa drugog kanala kao key input (cross-track ducking)
- [ ] **C2.5** SC EQ nodes: drag HP/LP/Mid čvorove direktno na spektru (kao EQ panel)

### FAZA C3 — Compressor Styles Upgrade [0/5]

Trenutno: 14 stilova, ali svi koriste VCA/Opto/FET sa različitim parametrima. Nema true program-dependent.
Pro-C 2 ima dublje razlike između stilova.

- [ ] **C3.1** Program-dependent release: release automatski skraćuje na transijentu, produžuje na sustained (Opto mod)
- [ ] **C3.2** VariMu emulacija: true variable-mu topologija (ratio se menja sa input levelom, nije fiksni)
- [ ] **C3.3** 1176 "All-buttons" mode: svi ratio dugmadi pritisnuti → ultra-agresivna kompresija sa distortion
- [ ] **C3.4** LA-2A emulacija: T4 optičke ćelije sa sporim response + dual-stage gain reduction
- [ ] **C3.5** SSL Bus Comp emulacija: VCA topology sa auto-release curve i specifičan punch karakter

### FAZA C4 — Metering Upgrade [0/6]

Trenutno: input/output peak + GR bar. Nema LUFS, nema crest factor, nema dynamic range meter.
Pro-C 2 ima comprehensive metering.

- [ ] **C4.1** LUFS metering: Integrated, Short-term (3s), Momentary (400ms) — ITU-R BS.1770-4
- [ ] **C4.2** Crest factor meter: peak-to-RMS ratio u dB (mera dinamičkog opsega)
- [ ] **C4.3** Dynamic range meter: loudness range (LRA) prema EBU R128
- [ ] **C4.4** Stereo correlation meter: L/R fazna korelacija (-1 do +1)
- [ ] **C4.5** GR meter sa segmentiranim LED prikazom: -1, -2, -3, -6, -10, -20 dB segmenti (Pro-C 2 style)
- [ ] **C4.6** Peak hold na svim metrima: decay 2s, resetabilan klikom

### FAZA C5 — Look-Ahead Vizualizacija & Transient Shaping [0/4]

Trenutno: lookahead radi u DSP (1024 sample buffer), ali UI ne prikazuje pre-analysis.
Cilj: Prikaži look-ahead prozor i dodaj transient shaping.

- [ ] **C5.1** Look-ahead visual: prikaži delay window na GR history waveform-u (koliko unapred gleda)
- [ ] **C5.2** Transient sustain control: podesi koliko kompresija utiče na attack vs sustain deo signala
- [ ] **C5.3** Transient detection display: prikaži detektovane transijenete na waveform-u (vertikalne linije)
- [ ] **C5.4** Look-ahead ms slider u UI: 0-20ms sa real-time latency indicator

### FAZA C6 — Multiband Compressor UI [0/5]

Trenutno: multiband kompresija postoji u rf-master (4-band LR4 crossover), ali NEMA UI za nju.
Cilj: Pro-MB stil multiband compressor sa vizuelnim crossover prikazom.

- [ ] **C6.1** Multiband mode toggle: switch single-band ↔ multiband u compressor panelu
- [ ] **C6.2** Crossover frekvencije drag: vizualni prikaz 4 banda sa drag-abilnim crossover pointima
- [ ] **C6.3** Per-band kompresija kontrole: threshold/ratio/attack/release per band sa mini transfer krive
- [ ] **C6.4** Per-band solo/bypass: solo ili bypass individualni band
- [ ] **C6.5** Band spectrum overlay: prikaz spektra sa obojanim bandovima i GR po bandu

### FAZA C7 — Parallel & M/S Processing Upgrade [0/4]

Trenutno: Mix (dry/wet) postoji za parallel, M/S flag postoji. Ali nema vizualizaciju niti naprednu kontrolu.
Cilj: Pro-C 2 nivo parallel i M/S workflow-a.

- [ ] **C7.1** Parallel mix curve: vizualizuj dry/wet blend na transfer krivoj (dual linije: compressed + parallel)
- [ ] **C7.2** M/S GR independent metering: odvojeni GR metri za Mid i Side signal
- [ ] **C7.3** M/S balance control: pomeri threshold nezavisno za Mid vs Side (side kompresija jača za tighter stereo)
- [ ] **C7.4** NY compression shortcut: "NY" dugme setuje mix na ~40-60% sa quick-recall

### FAZA C8 — Workflow & UX [0/7]

Trenutno: A/B postoji, ali nema undo, nema preseti, nema keyboard shortcuts.
Cilj: Kompletan Pro-C 2 workflow.

- [ ] **C8.1** Undo/Redo: Cmd+Z sa snapshot stackom (svi parametri)
- [ ] **C8.2** Preset browser: kategorisani factory preseti (Vocal, Drums, Bass, Mix Bus, Master, Sidechain, Parallel, Surgical)
- [ ] **C8.3** Preset save/load: custom user presets (JSON)
- [ ] **C8.4** Keyboard shortcuts: Space=bypass, A/B toggle, scroll=threshold fine adjust
- [ ] **C8.5** Quick-learn: click parametar + move MIDI kontroler za MIDI mapping
- [ ] **C8.6** Gain match: auto-adjust output gain da match-uje input loudness (fer A/B comparison)
- [ ] **C8.7** GR reset dugme: resetuje peak hold i GR historiju jednim klikom

### FAZA C9 — FFI & Wiring [0/3]

- [ ] **C9.1** Proširiti CompressorWrapper: 25 → ~35 parametara (multiband crossovers, per-band controls, transient shape, LUFS target)
- [ ] **C9.2** FFI setteri za multiband i nove parametre
- [ ] **C9.3** Wire multiband DSP (rf-master/dynamics.rs) u insert chain kao alternativni compressor mode

### FAZA C10 — Limiter & Gate Panel Polish [0/3]

- [ ] **C10.1** Limiter: true peak waveform display sa ceiling line i GR peaks (Pro-L 2 style)
- [ ] **C10.2** Gate: gate state visualization (open/closed/hysteresis zone) na waveform displayu
- [ ] **C10.3** Expander: expansion curve na transfer krivoj sa real-time signal dot

---

### Compressor Rezime faza

| Faza | Opis | Taskova | Impact |
|------|------|---------|--------|
| C1 | Transfer curve & GR vizualizacija | 6 | ★★★★★ (KRITIČNO — Pro-C 2 identitet) |
| C2 | Sidechain spectrum & audition | 5 | ★★★★☆ |
| C3 | Style upgrade (VariMu, 1176, LA-2A, SSL) | 5 | ★★★★☆ (zvučni karakter) |
| C4 | Metering (LUFS, crest, correlation) | 6 | ★★★★☆ |
| C5 | Look-ahead visual & transient | 4 | ★★★☆☆ |
| C6 | Multiband compressor UI | 5 | ★★★★☆ |
| C7 | Parallel & M/S upgrade | 4 | ★★★☆☆ |
| C8 | Workflow (undo, preseti, shortcuts) | 7 | ★★★☆☆ |
| C9 | FFI & wiring | 3 | ★★☆☆☆ |
| C10 | Limiter & Gate polish | 3 | ★★☆☆☆ |
| **TOTAL** | | **48** | |

**Prioritet implementacije:** C1 → C2 → C3 → C4 → C6 → C5 → C7 → C8 → C9 → C10

---

## LIMITER ULTIMATE — Pro-L 2 Tier Brickwall Limiter

**Goal:** Podići TruePeakLimiter na nivo FabFilter Pro-L 2 kvaliteta zvuka i vizuala.
**Scope:** Rust DSP (rf-dsp/src/dynamics.rs), FFI (rf-engine/dsp_wrappers.rs), Flutter UI (fabfilter_limiter_panel.dart)
**Referenca:** FabFilter Pro-L 2, Sonnox Oxford Limiter, DMG Limitless, Waves L2
**Postojeća baza:** 8 stilova, dual-stage gain, 8x oversampling, LUFS, A/B, scrolling waveform — solidno

### FAZA L1 — ISP Detection & True Peak Precision [0/5] ★★★★★ KRITIČNO
- [ ] L1.1: Implementirati pravi Inter-Sample Peak (ISP) detektor — 4-point sinc interpolacija između sampla za detekciju ISP pikova koji oversampling propušta
- [ ] L1.2: Zamena polyphase halfband filtera sa linear-phase FIR za oversampling — eliminacija phase distortion na visokim frekvencijama
- [ ] L1.3: ISP-safe ceiling garancija — post-limiter ISP provera sa korekcijom (Pro-L 2 garantuje 0 ISP iznad ceilinga)
- [ ] L1.4: True peak metering po ITU-R BS.1770-4 standardu — 4x oversampled peak detekcija sa preciznim koeficijentima
- [ ] L1.5: ISP indikator u UI — crveni marker kad ISP prekorači ceiling, sa brojačem ISP event-ova

### FAZA L2 — Loudness Metering & Target [0/5] ★★★★★ KRITIČNO
- [ ] L2.1: Loudness target mode — korisnik zadaje ciljani LUFS (npr. -14 za streaming), auto-gain prilagođava input trim u realnom vremenu
- [ ] L2.2: Loudness histogram — distribucija LUFS vrednosti tokom vremena (bar chart, 0.5 LU rezolucija)
- [ ] L2.3: Scrolling LUFS timeline graf — momentary/short-term/integrated na istom grafu sa vremenom, zoom 5s-60s
- [ ] L2.4: PLR (Peak-to-Loudness Ratio) metar — PLR = true peak - integrated LUFS, indikator dinamičkog opsega
- [ ] L2.5: Loudness range (LRA) metar — po EBU R128, prikazuje dinamički opseg materijala

### FAZA L3 — Gain Reduction Vizualizacija [0/5] ★★★★☆
- [ ] L3.1: Zoomable/scrollable waveform display — pinch-to-zoom na vremenskoj osi, drag za scroll, 1s-30s vidljivo
- [ ] L3.2: GR histogram (vertikalni) — distribucija gain redukcije tokom sesije, reset dugme
- [ ] L3.3: Dual-layer GR prikaz — "fill" sloj (poluprovidan) + "edge" linija (svetla), odvojeno L/R ili linked
- [ ] L3.4: Delta/audition mode — solo samo GR signal (razlika input-output), za proveru šta limiter "jede"
- [ ] L3.5: Pre/post waveform overlay — preklapanje ulaznog i izlaznog signala za vizuelno poređenje

### FAZA L4 — Advanced Release & Style Intelligence [0/4] ★★★★☆
- [ ] L4.1: Program-dependent release v2 — multi-band envelope tracking (LF/MF/HF) za nezavisno release vreme po opsegu, sprečava bass pumping
- [ ] L4.2: Transient preservation mode — oslabiti limiter na detektovanim tranzijenima (kick/snare), očuvati punch
- [ ] L4.3: Adaptive attack — automatski prilagođava attack na osnovu crest faktora (kratki za percusije, duži za sustain)
- [ ] L4.4: Style fine-tuning — per-style sub-parametri (attack mod, release mod, character) za micro-podešavanje unutar stila

### FAZA L5 — Output Stage & Clipper [0/4] ★★★☆☆
- [ ] L5.1: Output clipper — hard/soft clip opcija pre dithera (Pro-L 2 nema ali DMG Limitless ima), za 1-2dB ekstra loudness
- [ ] L5.2: DC offset removal filter — 5Hz HPF posle limitera, sprečava DC akumulaciju od asimetričnog clippinga
- [ ] L5.3: Auto-blanking — automatski mute izlaz kad nema signala duže od 2s (sprečava dither šum u tišini)
- [ ] L5.4: Noise shaping za dither — weighted noise shaping (F-weighted) umesto flat TPDF, perceptualno manje čujno

### FAZA L6 — Unity Gain & A/B Monitoring [0/4] ★★★☆☆
- [ ] L6.1: Unity gain listen — kompenzuje loudness razliku za fer A/B poređenje (output = input level, samo limiting artifacts)
- [ ] L6.2: Reference track import — učitaj referentni audio za LUFS/spectrum poređenje
- [ ] L6.3: A/B/C/D slots — proširiti sa 2 na 4 snapshot slota, morph slider između A i B
- [ ] L6.4: Bypass sa gain match — bypass koji kompenzuje loudness razliku, ne samo on/off

### FAZA L7 — Surround & Channel Configs [0/3] ★★☆☆☆
- [ ] L7.1: Quad/5.1 podrška — multi-channel TruePeakLimiter sa per-channel i linked gain reduction
- [ ] L7.2: LFE handling — odvojen limiter za LFE kanal sa drugačijim parametrima (sporiji attack, viši threshold)
- [ ] L7.3: Channel grouping UI — vizuelni routing koji kanali su linked, koji nezavisni

### FAZA L8 — Preset & Workflow [0/4] ★★☆☆☆
- [ ] L8.1: Preset browser — kategorije (Mastering/Streaming/Broadcast/Vinyl/CD), sa preview i opisi
- [ ] L8.2: Platform presets — Spotify (-14 LUFS), Apple Music (-16 LUFS), YouTube (-13 LUFS), CD (-9 LUFS) sa auto-ceiling
- [ ] L8.3: Undo/redo stack — 50-step parametar historija sa Ctrl+Z/Y
- [ ] L8.4: Session stats export — LUFS/PLR/ISP count/GR stats kao tekst ili JSON za mastering log

### FAZA L9 — Metering Polish [0/4] ★★☆☆☆
- [ ] L9.1: Peak hold sa konfigurisanim decay — 0.5s/1s/2s/infinite hold za peak indikatore
- [ ] L9.2: Clip counter — brojač koliko puta je signal prešao ceiling (sa reset dugmetom)
- [ ] L9.3: Crest factor metar — real-time peak/RMS odnos, indikator koliko je signal "peaked"
- [ ] L9.4: Stereo correlation metar — phase correlation (-1 do +1) za proveru stereo kompatibilnosti

### FAZA L10 — FFI & Integration [0/4] ★★☆☆☆
- [ ] L10.1: Latency compensation reporting — precizno prijavi latenciju host-u za PDC (Plugin Delay Compensation)
- [ ] L10.2: Sidechain input — eksterni sidechain za ducking/pumping efekte
- [ ] L10.3: Oversampling quality selector — "eco" (minimum phase) vs "high" (linear phase) vs "ultra" (steep linear phase)
- [ ] L10.4: CPU metering — prikaz DSP opterećenja po oversampling modu, pomoć korisniku da izabere optimalni mode

### Rezime faza

| Faza | Opis | Taskova | Težina |
|------|------|---------|--------|
| L1 | ISP detection & true peak precision | 5 | ★★★★★ |
| L2 | Loudness metering & target | 5 | ★★★★★ |
| L3 | GR vizualizacija | 5 | ★★★★☆ |
| L4 | Advanced release & style intelligence | 4 | ★★★★☆ |
| L5 | Output stage & clipper | 4 | ★★★☆☆ |
| L6 | Unity gain & A/B monitoring | 4 | ★★★☆☆ |
| L7 | Surround & channel configs | 3 | ★★☆☆☆ |
| L8 | Preset & workflow | 4 | ★★☆☆☆ |
| L9 | Metering polish | 4 | ★★☆☆☆ |
| L10 | FFI & integration | 4 | ★★☆☆☆ |
| **TOTAL** | | **42** | |

**Prioritet implementacije:** L1 → L2 → L3 → L4 → L5 → L6 → L9 → L8 → L10 → L7

---

## SATURATOR ULTIMATE — Saturn 2 Tier Multiband Saturation

**Goal:** Podići Saturator na nivo FabFilter Saturn 2 kvaliteta zvuka, stilova i vizuala.
**Scope:** Rust DSP (rf-dsp/src/saturation.rs), FFI (rf-engine/dsp_wrappers.rs), Flutter UI (fabfilter_saturation_panel.dart)
**Referenca:** FabFilter Saturn 2, Soundtoys Decapitator, Softube Harmonics, Plugin Alliance bx_saturator
**Postojeća baza:** 6 tipova, multiband (2-6), oversampling 16x, dynamics, transfer curve, A/B — solidno

### FAZA S1 — Saturation Style Expansion [0/6] ★★★★★ KRITIČNO
- [ ] S1.1: Warm Tube stil — asimetrični 2nd/3rd harmonik sa blagim kompresi­jem, manje drive nego Tube, za subtle warmth na master busu
- [ ] S1.2: Transformer stil — željezo-jezgra saturacija sa histerezom, karakteristično LF zasićenje i HF rolloff, Neve 1073 karakter
- [ ] S1.3: Rectifier stil — polutalasno ispravljanje (half-wave rectifier) sa varijabilnim bias-om, gitarski amp karakter
- [ ] S1.4: Guitar Amp stilovi (Clean/Crunch/Lead) — kaskadni gain stage-ovi sa tone stack (Bass/Mid/Treble biquad mreža), speaker cab IR convolution opcija
- [ ] S1.5: Lo-Fi stil — kombinacija bit crush + sample rate reduction + wow/flutter modulacija + vinyl noise, sve u jednom stilu
- [ ] S1.6: Destroy stil — agresivni foldback + ring modulation + bit crush combo, za extreme sound design

### FAZA S2 — Tape Modeling Upgrade [0/5] ★★★★★ KRITIČNO
- [ ] S2.1: Pravi Jiles-Atherton histerezis model — full differential equation (`dM/dH`), ne aproksimacija, za autentičnu tape saturaciju
- [ ] S2.2: Tape speed varijacije (7.5/15/30 ips) — svaka brzina ima drugačiju frekventnu karakteristiku (HF rolloff, LF bump, harmonic content)
- [ ] S2.3: Tape compression (head bump) — LF rezonanca na 60-100Hz zavisno od brzine, modeluje fiziku glave
- [ ] S2.4: Wow & Flutter — dual LFO modulacija pitch-a (wow 0.5-3Hz, flutter 5-15Hz), sa depth i rate kontrolama
- [ ] S2.5: Tape hiss generator — filtered pink noise sa frekvencijom zavisnom od speed-a, subtle za autentičnost, sa amount kontrolom

### FAZA S3 — Tube Modeling Upgrade [0/5] ★★★★☆
- [ ] S3.1: Triode model (12AX7/12AT7) — plate characteristic krivulja sa grid bias, plate voltage, i mu parametrima
- [ ] S3.2: Pentode model (EL34/6L6) — screen grid interakcija, crossover distortion pri niskom bias-u
- [ ] S3.3: Tube sag (power supply) — dinamički voltage sag pod opterećenjem, kompresija sa sporim recovery-jem (50-200ms)
- [ ] S3.4: Tube aging — modeluje starenje cevi (gubitak emisije), menja harmonijski profil (više 3rd, manje 2nd)
- [ ] S3.5: Multi-stage gain (preamp + power amp) — kaskadni tube stage-ovi sa inter-stage EQ, svaki stage sa nezavisnim drive-om

### FAZA S4 — Modulation System [0/5] ★★★★☆
- [ ] S4.1: LFO modulator — 6 oblika (sine/tri/saw/square/S&H/noise), sync na tempo, rate 0.01-50Hz, za bilo koji parametar
- [ ] S4.2: Envelope follower modulator — attack/release/depth kontrole, može modulisati drive/tone/mix/output
- [ ] S4.3: Modulation matrix UI — drag-and-drop rutiranje mod source → destination, sa depth slider po vezi
- [ ] S4.4: MIDI velocity → drive mapping — veći velocity = više drive-a, za ekspresivno sviranje
- [ ] S4.5: Sidechain modulation — eksterni audio signal kao modulator za drive (ducking saturation, pumping efekti)

### FAZA S5 — Crossover & Band Display [0/5] ★★★★☆
- [ ] S5.1: Interaktivni band display — CustomPaint sa draggable crossover tačkama, real-time per-band spectrum overlay
- [ ] S5.2: Linear phase crossover opcija — FIR crossover kao alternativa LR24, za mastering gde phase je kritičan
- [ ] S5.3: Per-band waveform prikaz — mini osciloskop po bandu (pre/post saturacija), za vizuelnu kontrolu distorzije
- [ ] S5.4: Crossover slope selector — 6/12/24/48 dB/oct po crossover tački, ne samo globalni izbor
- [ ] S5.5: Band solo-in-place sa listen mode — solo reproducira samo taj band BEZ crossover artefakata (bandpass filter)

### FAZA S6 — Transfer Curve Enhancement [0/4] ★★★☆☆
- [ ] S6.1: Interaktivna transfer krivulja — korisnik može crtati custom waveshaper krivulju sa Bezier tačkama (drag kontrole)
- [ ] S6.2: Real-time signal na krivulji — animirani dot koji prati signal po transfer krivulji, pokazuje koliko ulazi u saturaciju
- [ ] S6.3: Harmonic spectrum sa real DSP podataka — FFT iz Rust-a umesto hardkodiranih tabela, pravi harmonijski prikaz trenutnog zvuka
- [ ] S6.4: Pre/post spectrum overlay — dual spectrum analyzer (sivi=input, obojeni=output) za vizuelno poređenje pre/posle saturacije

### FAZA S7 — Advanced Processing [0/4] ★★★☆☆
- [ ] S7.1: Parallel processing (dry/wet blend po bandu) — nezavisan mix po bandu PLUS globalni mix, za NY-style parallel saturation
- [ ] S7.2: Auto-gain compensation — automatski kompenzuje loudness nakon saturacije, fer A/B poređenje
- [ ] S7.3: Transient shaper integracija — per-band transient attack/sustain pre saturatora, kontroliše šta ulazi u distorziju
- [ ] S7.4: Feedback saturation — deo output-a vraća na input sa delay-om (1-50 sampla), za self-oscillation i reso efekte

### FAZA S8 — Convolution & IR [0/4] ★★★☆☆
- [ ] S8.1: Cabinet IR loader — učitaj .wav IR fajl za guitar/bass cab simulaciju, zero-latency partitioned convolution
- [ ] S8.2: Built-in cab IR biblioteka — 5-10 ugrađenih IR-ova (4x12 Marshall, 2x12 Fender, 1x12 Vox, DI box, vintage combo)
- [ ] S8.3: Pre/post cab positioning — IR pre ili posle saturatora (pre=mic'd amp karakter, post=cab coloring)
- [ ] S8.4: IR mix blend — dry/cab blend sa phase invert opcijom

### FAZA S9 — Preset & Workflow [0/4] ★★☆☆☆
- [ ] S9.1: Preset browser sa kategorijama — Subtle/Warm/Aggressive/Creative/Guitar/Bass/Drums/Master, preview sa opisi
- [ ] S9.2: Per-band preset — sačuvaj/učitaj podešavanje jednog banda, copy/paste između bandova
- [ ] S9.3: Undo/redo stack — 50-step parametar historija sa Ctrl+Z/Y
- [ ] S9.4: Randomize — "inspire me" dugme koje randomizuje stilove i drive vrednosti po bandu (kontrolisan chaos)

### FAZA S10 — FFI & Performance [0/4] ★★☆☆☆
- [ ] S10.1: SIMD waveshaping — AVX2/SSE4 vektorizovani waveshaper (4 sampla odjednom), značajno ubrzanje za oversampled processing
- [ ] S10.2: Per-band CPU metering — prikaz DSP load po bandu, pomoć korisniku da optimizuje oversampling
- [ ] S10.3: Adaptive oversampling — automatski smanjuje OS faktor kad CPU > 80%, vraća kad se oslobodi
- [ ] S10.4: Zero-latency mode — bypass oversampling za monitoring, full OS samo za renderovanje

### Rezime faza

| Faza | Opis | Taskova | Težina |
|------|------|---------|--------|
| S1 | Saturation style expansion | 6 | ★★★★★ |
| S2 | Tape modeling upgrade | 5 | ★★★★★ |
| S3 | Tube modeling upgrade | 5 | ★★★★☆ |
| S4 | Modulation system | 5 | ★★★★☆ |
| S5 | Crossover & band display | 5 | ★★★★☆ |
| S6 | Transfer curve enhancement | 4 | ★★★☆☆ |
| S7 | Advanced processing | 4 | ★★★☆☆ |
| S8 | Convolution & IR | 4 | ★★★☆☆ |
| S9 | Preset & workflow | 4 | ★★☆☆☆ |
| S10 | FFI & performance | 4 | ★★☆☆☆ |
| **TOTAL** | | **46** | |

**Prioritet implementacije:** S1 → S2 → S3 → S5 → S4 → S6 → S7 → S8 → S9 → S10

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
