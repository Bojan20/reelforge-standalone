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
| **REVERB ULTIMATE** (52/52) | **DONE** |
| **EQ ULTIMATE** (52/52) | **DONE** |
| **DELAY ULTIMATE** (55/55) | **DONE** |
| **COMPRESSOR ULTIMATE** (48/48) | **DONE** |
| **LIMITER ULTIMATE** (42/42) | **DONE** |
| **SATURATOR ULTIMATE** (46/46) | **DONE** |

Analyzer: 0 errors, 0 warnings

---

## Completed Systems Reference

### Reverb Ultimate (ValhallaVintageVerb tier) — 52/52
F1 velvet noise modulation (16 generators, Hermite cubic interp, spin+wander split, 0.0001-0.01 depth range), F2 ER density (24 taps, 5 styles), F3 diffusion network, F4 4-band Linkwitz-Riley crossover decay, F5 output EQ, F6 FDN core (4/8/16 size, Hadamard/Householder, chorus, jitter), F7 styles (shimmer/ambient/gated/nonlinear/vintage), F8 UI visualization, F9 FFI+presets.

### EQ Ultimate (Pro-Q 4 tier) — 52/52
E1 biquad H(z) curves, E2 spectrum analyzer (pre/post/freeze/tilt/M-S), E3 Pro-Q 4 interaction (Q ring, alt+drag solo, context menu, shortcuts), E4 phase+group delay, E5 undo/presets/export, E6 EQ match, E7 oversampling+auto-listen, E8 visual polish (waterfall, node glow, spring physics), E9 analog modes+room correction.

### Delay Ultimate (Timeless 3 tier) — 55/55
D1 feedback filter+saturation, D2 dual LFO+envelope, D3 tempo sync+swing, D4 16-tap engine+patterns, D5 stereo routing+spatial, D6 freeze+glitch+reverse, D7 vintage modes (tape/BBD/oil can/lo-fi), D8 tap timeline+filter viz+mod routing, D9 58-param wrapper+30 presets, D10 sidechain+MIDI trigger+smoothing.

### Compressor Ultimate (Pro-C 2 tier) — 48/48
C1 animated transfer curve+signal dot+knee highlight+range viz, C2 SC filter response+node visuals+audition, C3 VariMu/AllButtons/SslBus DSP (Rust), C4 LUFS/crest/DR/correlation+segmented GR, C5 lookahead window viz, C6 multiband UI, C7 parallel mix curve+NY button, C8 undo/redo+20 presets+GR reset, C9 FFI wiring, C10 limiter/gate polish.

### Limiter Ultimate (Pro-L 2 tier) — 42/42
L1 ISP indicator+counter, L2 LUFS timeline+loudness targets (8 platforms)+GR histogram+PLR+clip counter+crest+stereo correlation, L3 zoom/scroll waveform+dual-layer GR+delta mode+pre/post overlay, L4 style info panel, L5 clipper toggle, L6 unity gain+ABCD slots+gain match, L8 undo/redo+stats export+20 presets, L9 peak hold decay selector, L10 oversampling picker+CPU meter.

### Saturator Ultimate (Saturn 2 tier) — 46/46
S1 type indicators+formula info, S4 LFO+envelope follower UI, S5 crossover band display+mini waveform+solo, S6 Bezier transfer curve+signal dot+harmonic spectrum+pre/post spectrum (6 waveshapers), S7 auto-gain+transient shaper, S9 band copy/paste+undo/redo+randomize+19 presets, S10 oversampling+CPU display.

---

## Planned: SlotLab CUSTOM Events Tab

**Status:** Placeholder (tab renamed BROWSE → CUSTOM, sadržaj zastareo)

**Šta treba da radi:**
- Custom event kreiranje van predefinisanog stage sistema (ASSIGN tab)
- Korisnik definiše potpuno nove evente: custom ime, custom triggerStages, layere, looping, maxInstances
- Use case: game-specifični zvučni efekti koji ne spadaju ni u jednu od 7 faza (npr. branded bonus mehanika, story-driven audio, custom mini-game zvukovi)
- Drag & drop audio iz POOL-a (desni panel) na custom event layere
- CRUD: kreiranje, editovanje, brisanje custom evenata
- Custom eventi se registruju u MiddlewareProvider i EventRegistry isto kao ASSIGN eventi
- ID format: `custom_<user_defined_name>` (razlikuje se od `audio_<STAGE>` formata)

**Razlika ASSIGN vs CUSTOM:**
- ASSIGN = predefinisani slotovi (500+ stage-ova po industriji), 1 audio po slotu, automatski kreira composite event
- CUSTOM = korisnik sam kreira evente od nule, višeslojni (multi-layer), potpuna kontrola nad svim parametrima

**Implementacija:**
1. Novi UI: lista custom evenata + "New Event" dugme + inline editor
2. Custom event model (ime, kategorija, triggerStages[], layers[], looping, maxInstances, bus routing)
3. Persitencija u SlotLabProjectProvider (kao audioAssignments)
4. EventRegistry + MiddlewareProvider sinhronizacija
5. Brisanje BROWSE tab legacy koda (_buildEventsLeftPanel → zamena novim sistemom)
