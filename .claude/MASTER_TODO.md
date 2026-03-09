# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-09

## Status Summary

| System | Status |
|--------|--------|
| Core, Middleware, AUREXIS, FluxMacro, ICF, RTE, CTR, PPL | Done |
| SlotLab, Config Panel, Config Undo/Redo, Transition Editor | Done |
| 6× Ultimate DSP (Reverb/EQ/Delay/Compressor/Limiter/Saturator) | Done |
| Reaper Faza 1 (#1-3), Faza 2 (#4-10), Faza 3 (#11-17) | Done |

Analyzer: 0 errors, 0 warnings

---

## Reaper DAW Feature Parity — Remaining

### Faza 3: Workflow Acceleration (remaining)

| # | Feature | Status | Opis | Složenost |
|---|---------|--------|------|-----------|
| 18 | **Auto-Color Rules** | ✅ DONE | Regex pattern → boja/ikona. Automatski pri kreiranju traka ili batch na postojeće. Import/export pravila. | Niska |
| 19 | **Dynamic Split Workflow** | ✅ DONE | Automatsko sečenje po transijentima/gate threshold/tišini. Opcija: dodaj stretch markere umesto rezova. Preview pre primene. "Send items to sampler" workflow. | Srednja |
| 20 | **UCS Naming System** | ✅ DONE | Universal Category System: `CATsub_VENdor_Project_Descriptor_####`. Auto-generisanje iz regiona/trakova. Industrijski standard za game audio. | Niska |

### Faza 4: Game Audio Pipeline (P2-P3)

| # | Feature | Status | Opis | Složenost |
|---|---------|--------|------|-----------|
| 21 | **Stem Manager** | ✅ DONE | Save/recall solo/mute konfiguracija. Batch render svih stem konfiguracija. Render queue. Multi-format (WAV+OGG istovremeno). | Srednja |
| 22 | **Loudness Report** | ✅ DONE | HTML interaktivni izveštaj: Integrated LUFS, Short-term graf, True Peak, LRA, clipping detection. Dry run (analiza bez renderovanja). | Srednja |

### Faza 5: Power User Features (P3-P4)

| # | Feature | Status | Opis | Složenost |
|---|---------|--------|------|-----------|
| 25 | **Cycle Actions** | ✅ DONE | Svaki poziv izvršava sledeći korak u ciklusu. Kondicionalni (if/then). Proširenje FluxMacro. | Niska |
| 26 | **Region Playlist** | ✅ DONE | Non-linearni playback. Definiši redosled regiona nezavisno od timeline pozicije. Loop per-region. Smooth seek. | Srednja |
| 27 | **Marker Actions** | ✅ DONE | Akcije vezane za timeline pozicije. Trigger kad play cursor pređe marker. `!` + action ID u imenu markera. | Niska |
| 28 | **Granular Synthesis** | ✅ DONE | ReaGranular-style: 4 grain-a, min/max size, per-grain pan/level, random varijacije, freeze mode. | Srednja |
| 29 | **ReaStream (Network Audio)** | ✅ DONE | Host-to-host streaming audio/MIDI na LAN-u. UDP broadcast. Multi-channel. | Visoka |
| 30 | **JSFX-style DSP Scripting** | ❌ TODO | User-scriptable audio efekti sa sample-level processing. Instant kompilacija. Custom GUI. | Vrlo visoka |
| 31 | **Video Processor FX** | ❌ TODO | Built-in video processor: text overlay, audio-reaktivni vizuali, FFT frequency display. | Srednja |
| 32 | **Host-level Wet/Dry per-FX** | ⚠️ PARTIAL | Host-level wet/dry za SVE plugin-e (čak i bez ugrađenog mix knoba). | Niska |
| 33 | **Package Manager** | ❌ TODO | Marketplace za skripte, efekte, teme. Auto-update. Custom repositories. | Visoka |
| 34 | **Extension SDK** | ⚠️ PARTIAL | `rf-plugin` crate postoji. Otvoreni SDK za third-party development. | Visoka |

### Postojeći sistemi koji treba proširiti

| Feature | Status | Šta fali |
|---------|--------|----------|
| Sidechain routing | ✅ | Drag-and-drop sidechain iz routing matrice |
| Comping lanes | ⚠️ | Per-take FX, per-take envelopes, per-take pitch/playrate |
| Stretch markers | ⚠️ | Per-segment pitch kontrola |
| Clip properties | ⚠️ | Snap offset, channel mode selection, notes polje |
| Glue items | ⚠️ | Reversible un-glue |
| Nudge system | ⚠️ | Konfigurabilan nudge amount (samples/ms/frames/beats) |
| Media browser | ⚠️ | Preview routing, tempo matching, favorites, history |

---

## Planned: SlotLab CUSTOM Events Tab

**Status:** Placeholder (tab renamed BROWSE → CUSTOM, sadržaj zastareo)

- Custom event kreiranje van predefinisanog stage sistema
- ID format: `custom_<name>` (razlikuje se od `audio_<STAGE>`)
- CRUD + drag & drop audio iz POOL-a
- EventRegistry + MiddlewareProvider sinhronizacija
- Detalji u MEMORY.md
