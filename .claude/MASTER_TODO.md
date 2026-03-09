# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-09

## All Implemented Systems

### Core Engine (Rust)
- Audio engine (rf-engine) — sample-accurate playback, crossfades, loop, scrub
- FFI bridge (rf-bridge) — Flutter↔Rust, lock-free ring buffers
- DSP: 6× Ultimate (Reverb/EQ/Delay/Compressor/Limiter/Saturator)
- Time Stretch (NSGT, RTPGHI, STN, WORLD)
- SIMD metering (8x True Peak, Zwicker loudness)
- GPU DSP, Convolution Ultra, DSD, Advanced Formats
- ML/Spatial/Restore/Master/Pitch engines (API stubs)

### DAW (Flutter UI)
- Timeline: clips, regions, crossfades, markers, tempo track
- Mixer: dynamic track/bus routing, insert chains (8 pre+post), sends
- Waveform: GPU-accelerated, stereo, LOD, cache system
- Recording: FFI + transport UI
- Automation: lanes, items (pooled), clip envelopes (pitch/rate/vol/pan)
- Audio Pool, Audio Editor, Sample Editor
- Track headers: M/S/I/R, color sync, lock/mute
- Export: batch render, region render matrix, bounce FFI

### DAW Features (#1-#22)
| # | Feature |
|---|---------|
| 1 | Region Render Matrix — batch export |
| 2 | Clip Envelopes — per-item pitch/playrate/volume/pan |
| 3 | Automation Items — pooled containerized automation |
| 4 | Pin Connector — per-plugin channel routing matrix |
| 5 | Parallel FX — inline FxContainer + FFI |
| 6 | Razor Edits — merged-range processing |
| 7 | Mix Snapshots — selective capture/recall |
| 8 | Metadata Browser — BWF/iXML/ID3v2/RIFF parsing + search |
| 9 | Screensets — 10 UI state slots |
| 10 | Project Tabs — multi-project tab system |
| 11 | Sub-Projects — nested .rfproj on timeline |
| 12 | Command Palette — fuzzy search, 85+ commands, 9 categories |
| 13 | Dynamic Split — transient/gate/silence detection |
| 14 | Auto-Color Rules — regex pattern → color/icon |
| 18 | Auto-Color Rules (expanded) |
| 19 | Dynamic Split Workflow |
| 20 | UCS Naming System |
| 21 | Stem Manager — batch render, multi-format |
| 22 | Loudness Report — LUFS analysis, HTML export |

### Power User Features (#25-#34)
| # | Feature |
|---|---------|
| 25 | Cycle Actions — sequential cycling with conditionals |
| 26 | Region Playlist — non-linear playback |
| 27 | Marker Actions — position-triggered actions |
| 28 | Granular Synthesis — 4-voice grain engine |
| 29 | Network Audio — ReaStream-style LAN streaming |
| 30 | DSP Scripting — JSFX-style sample-level FX |
| 31 | Video Processor FX — text overlay, audio-reactive visuals |
| 32 | Host-level Wet/Dry per-FX |
| 33 | Package Manager — marketplace for scripts/effects/themes |
| 34 | Extension SDK — rf-plugin crate + Flutter SDK panel |

### #35 System Improvements
- Comping: per-take FX chain, pitch (-24/+24st), playrate (0.25-4x), envelopes
- Stretch markers: per-segment pitch, purple badge, 11 presets
- Clip properties: snap offset, channel mode (6 modes), notes field
- Glue items: GlueRecord/GlueHistory, reversible un-glue
- Nudge: NudgeConfig, 5 unit types, primary+fine, presets
- Media browser: preview bus routing, history, tempo match
- SlotLab CUSTOM Events: CustomEventProvider, CRUD, layers, drag & drop, triggers

### SlotLab (Slot Game Audio)
- SlotLabCoordinator (decomposed: Engine/Stage/Audio providers)
- EventRegistry — stage→audio mapping (JEDAN put registracije)
- MiddlewareProvider — composite events, states, switches, RTPC, ducking
- AUREXIS™ — intelligent DSP orchestration, 12 profiles
- GameFlow FSM — modular slot machine state machine
- Win Tier Config — data-driven tiers
- Diagnostics — live monitoring (EventFlow, TimingDrift, AudioVoice)
- Behavior Trees, State Gates, Emotional State, Priority Engine
- Orchestration, Simulation, Error Prevention, Undo
- Templates, Export, Feature Composer, Pacing Engine
- GAD (Gameplay-Aware DAW), SSS (Scale & Stability)
- FluxMacro orchestration, Stage Flow Editor
- Custom Events tab (CustomEventProvider)

### Video System
- VideoProvider, VideoExportService, VideoPlaybackService

### Services
- GetIt DI (service_locator.dart) — 50+ singletons
- Unified Search, Recent/Favorites, Analytics
- Plugin State, Missing Plugin Detector
- Session Persistence, Workspace Presets
- Waveform Cache, Audio Asset Manager
- Diagnostics (6 monitors/checkers)

Analyzer: 0 errors, 0 warnings

---

## Remaining / Planned

_(dodaj nove taskove ovde)_
