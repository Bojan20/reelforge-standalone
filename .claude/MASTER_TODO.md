# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-09

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

## Reaper DAW Feature Parity — Implementation Tracker

> Referenca: `REAPER_FEATURES_ANALYSIS.md` (30 feature-a, 5 faza)
> Cilj: Učiniti FluxForge konkurentnim sa Reaper-om za sound design i audio tehničare

### Faza 1: Sound Design Foundation (P0 — CRITICAL) ✅ DONE

| # | Feature | Status | Grana/Commit | Detalji |
|---|---------|--------|--------------|---------|
| 1 | **Item-Level FX** | ✅ DONE | `feature/item-level-fx-stateful-processing` | Per-clip stateful DSP (ClipFxProcessorBank), 6 tipova FX, bypass fade, wet/dry, I/O gain. `clip_fx_processor.rs` ~700 linija |
| 2 | **Region Render Matrix** | ✅ DONE | `main` (2a000f91) | Batch export engine, rayon parallel, cooperative cancel, wildcard naming. `render_matrix.rs` ~947 linija, 19 FFI fn, 8 testova |
| 3 | **Wildcard Tokens za render** | ✅ DONE | Deo #2 | $region, $preset, $date, $tag, $index + prefix/suffix + subdirs |

### Faza 2: Creative Tools (P1 — HIGH)

| # | Feature | Status | Opis | Složenost |
|---|---------|--------|------|-----------|
| 4 | **Per-item Pitch Envelope** | ✅ DONE | ClipEnvelope sa relativnim pozicijama (premešta se sa clipom). ±24 semitona, 6 curve types (Linear/Bezier/Exp/Log/Step/SCurve). Trapezoidal integration za source poziciju. 12 unit testova, 10 FFI fn. | Visoka |
| 5 | **Per-item Playrate Envelope** | ✅ DONE | ClipEnvelope playrate (0.1x–4.0x). Multiplicative sa stretch_ratio. Varispeed mode (pitch follows rate). Incremental per-block akumulacija, full integral samo na seek. Zero-alloc audio thread. | Visoka |
| 6 | **Automation Items (pooled)** | ✅ DONE | AutomationItem+AutomationItemManager+AutomationPool. 7 LFO shapes (Sine/Triangle/Square/SawUp/SawDown/Random/S&H), custom points, looping, stacking (additive), pooling (edit-one-update-all), stretch, baseline/amplitude. 13 FFI fn, 11 testova. `automation.rs` ~700 novih linija | Vrlo visoka |
| 7 | **Pin Connector** | ✅ DONE | `pin_connector.rs` ~760 linija. 64-ch routing matrix, 5 režima (Normal/MultiMono/MidSide/Surround/Custom), gain matrix, M/S encode/decode, zero-alloc audio thread. Integrisano u InsertSlot. 6 FFI fn, 11 testova. | Vrlo visoka |
| 8 | **Parallel FX (inline)** | ✅ DONE | `FxContainerProcessor` wrapper: FxContainer implementira InsertProcessor, loaduje se u InsertSlot. 7 FFI fn (container lifecycle, path management, blend modes, macros). InsertProcessor trait proširen sa is_fx_container/as_fx_container_mut. | Srednja |
| 9 | **FX Containers** | ✅ DONE | Pokriveno sa P8 — FxContainer (8 parallel paths, 16 macros, 4 blend modes) + FxContainerProcessor wrapper. Nestanje inherentno (InsertChain u path-u može sadržati FxContainerProcessor). | Visoka |
| 10 | **Per-item Automation** | ✅ DONE | Pokriveno sa P4/P5 — ClipEnvelope sistem (pitch, playrate, volume, pan) sa relativnim pozicijama. Premešta se sa clipom. Nezavisno od track automatizacije (multiplikativno u playback.rs). | Visoka |

### Faza 3: Workflow Acceleration (P2 — MEDIUM)

| # | Feature | Status | Opis | Složenost |
|---|---------|--------|------|-----------|
| 11 | **Razor Edits** | ✅ DONE | RazorArea model + RazorContent filter (Media/Envelope/Both). 10 operacija sa merged-range processing (no double-processing). 14 FFI, 16 testova. | Visoka |
| 12 | **Mix Snapshots** | ✅ DONE | 10 kategorija, selective capture/recall sa category+track filter, solo clear on recall, atomic update, JSON serialization. 8 FFI, 12 testova. | Srednja |
| 13 | **Metadata Browser + Search** | ✅ DONE | BWF/iXML/ID3v2/RIFF INFO/Vorbis Comment/FLAC metadata parsing. Boolean search (AND/OR/NOT, field:value, "phrases", groups). Batch editing. 3 FFI, 12 testova. | Srednja |
| 14 | **Screensets** | ✅ DONE | 10 slotova za kompletno UI stanje (pozicije prozora, veličine, zoom, scroll, dock stanje). Instant prebacivanje jednim tasterom. Per-project. Rust: Screenset model, TrackManager 8 metoda, JSON serialization, 6 testova. FFI: 8 funkcija. | Srednja |
| 15 | **Project Tabs** | ❌ TODO | Više projekata u tabovima. Copy/paste itema između tabova. Drag-and-drop transfer. Per-tab undo history. | Visoka |
| 16 | **Sub-Projects** | ❌ TODO | .rpp fajl kao media item na timeline-u. Dupli klik → otvori u novom tabu. Auto-render proxy audio. Nestable. | Vrlo visoka |
| 17 | **Command Palette / Console** | ❌ TODO | Fuzzy search za sve akcije (3000+). Instant izvršavanje. History. Ctrl+P / `?` shortcut. Relativno laka implementacija, visok impakt. | Niska |
| 18 | **Auto-Color Rules** | ❌ TODO | Regex pattern → boja/ikona. Automatski pri kreiranju traka ili batch na postojeće. Import/export pravila. | Niska |
| 19 | **Dynamic Split Workflow** | ❌ TODO | Automatsko sečenje po transijentima/gate threshold/tišini. Opcija: dodaj stretch markere umesto rezova. Preview pre primene. "Send items to sampler" workflow. | Srednja |
| 20 | **UCS Naming System** | ❌ TODO | Universal Category System: `CATsub_VENdor_Project_Descriptor_####`. Auto-generisanje iz regiona/trakova. Industrijski standard za game audio. | Niska |

### Faza 4: Game Audio Pipeline (P2-P3)

| # | Feature | Status | Opis | Složenost |
|---|---------|--------|------|-----------|
| 21 | **Stem Manager** | ❌ TODO | Save/recall solo/mute konfiguracija. Batch render svih stem konfiguracija. Render queue. Multi-format (WAV+OGG istovremeno). | Srednja |
| 22 | **Loudness Report** | ❌ TODO | HTML interaktivni izveštaj: Integrated LUFS, Short-term graf, True Peak, LRA, clipping detection. Dry run (analiza bez renderovanja). | Srednja |
| 23 | **Wwise Direct Integration** | ❌ TODO | ReaWwise-style: kreiranje object hierarchy u Wwise-u iz FluxForge-a. Wildcard recipe za Object Path. | Visoka |
| 24 | **FMOD Direct Integration** | ❌ TODO | API-based transfer asseta. Shared folder monitoring. | Srednja |

### Faza 5: Power User Features (P3-P4)

| # | Feature | Status | Opis | Složenost |
|---|---------|--------|------|-----------|
| 25 | **Cycle Actions** | ❌ TODO | Svaki poziv izvršava sledeći korak u ciklusu. Kondicionalni (if/then). Proširenje FluxMacro. | Niska |
| 26 | **Region Playlist** | ❌ TODO | Non-linearni playback. Definiši redosled regiona nezavisno od timeline pozicije. Loop per-region. Smooth seek. | Srednja |
| 27 | **Marker Actions** | ❌ TODO | Akcije vezane za timeline pozicije. Trigger kad play cursor pređe marker. `!` + action ID u imenu markera. | Niska |
| 28 | **Granular Synthesis** | ❌ TODO | ReaGranular-style: 4 grain-a, min/max size, per-grain pan/level, random varijacije, freeze mode. `rf-dsp` ima koncept ali nije expozovan. | Srednja |
| 29 | **ReaStream (Network Audio)** | ❌ TODO | Host-to-host streaming audio/MIDI na LAN-u. UDP broadcast. Multi-channel. | Visoka |
| 30 | **JSFX-style DSP Scripting** | ❌ TODO | User-scriptable audio efekti sa sample-level processing. Instant kompilacija. Custom GUI. FluxMacro je workflow automation, ovo je DSP scripting. | Vrlo visoka |
| 31 | **Video Processor FX** | ❌ TODO | Built-in video processor: text overlay, audio-reaktivni vizuali, FFT frequency display. `rf-video` crate postoji. | Srednja |
| 32 | **Host-level Wet/Dry per-FX** | ⚠️ PARTIAL | Naši Ultimate procesori imaju mix knob. Host-level wet/dry za SVE plugin-e (čak i bez ugrađenog mix knoba). | Niska |
| 33 | **Package Manager** | ❌ TODO | Marketplace za skripte, efekte, teme. Auto-update. Custom repositories. | Visoka |
| 34 | **Extension SDK** | ⚠️ PARTIAL | `rf-plugin` crate postoji. Otvoreni SDK za third-party development. | Visoka |

### Postojeći sistemi koji treba proveriti/proširiti

| Feature | FluxForge status | Šta fali |
|---------|-----------------|----------|
| Sidechain routing | ✅ u Compressor Ultimate | Drag-and-drop sidechain iz routing matrice |
| FX Chains Save/Load | ✅ Insert chains | Save/load chain presets (.rfxchain ekvivalent) |
| Comping lanes | ⚠️ Postoji | Per-take FX, per-take envelopes, per-take pitch/playrate |
| Stretch markers | ⚠️ Warp handles | Per-segment pitch kontrola |
| Clip properties | ⚠️ Postoji | Snap offset, channel mode selection, notes polje |
| Glue items | ⚠️ Bounce | Reversible un-glue |
| Nudge system | ⚠️ Delimično | Konfigurabilan nudge amount (samples/ms/frames/beats) |
| Media browser | ⚠️ Audio pool | Preview routing, tempo matching, favorites, history |
| Feedback loops | ⚠️ Routing postoji | Provera da li dozvoljava feedback routing |
| Spectral editor | ✅ Postoji | Spectral peaks hybrid view, per-item spectral editing |

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
