# FluxForge Studio — MASTER TODO

**Updated:** 2026-03-08

## Status: ALL COMPLETE — 208/208 tasks + all P-systems + Undo/Redo + Visual Editor

| System | Status |
|--------|--------|
| AUREXIS (88), Middleware (19), Core (129) | Done |
| FluxMacro (53), ICF (8), RTE (5), CTR (5), PPL (8) | Done |
| Unified SlotLab, Win Tier, StageCategory | Done |
| Config Panel Enhancements | Done |
| Config Undo/Redo + Visual Transition Editor | Done |

Analyzer: 0 errors, 0 warnings

## Recent: Config Undo/Redo + Visual Transition Editor (2026-03-08)

### Config Undo/Redo System
- ConfigUndoManager: 100-step snapshot stack, 500ms merge window (category+description scoped)
- Snapshot captures: win config + transition configs + symbol artwork (full JSON)
- Undo wired: ALL win tier mutations, ALL transition mutations, ALL symbol artwork mutations
- UNDO/REDO toolbar in CONFIG tab header (ListenableBuilder, auto-show/hide)
- Cmd+Z / Cmd+Shift+Z keyboard shortcut (CONFIG tab only)
- Timeline drag batching: single undo entry per drag (onDragStart/onDragEnd)

### Visual Transition Editor
- SceneTransitionConfig: 20+ new fields (per-phase timing, stagger delays, layer visibility/intensity, per-phase audio)
- TransitionTimelineEditor: 6-track CustomPaint (FADE/BURST/PLAQUE/GLOW/SHIMMER/AUDIO)
- Drag handles for delay + duration, ruler with ms markers, intensity bars
- Overlay wired: showBurst/showGlow/showShimmer guards, burstIntensity, glowIntensity, shimmerIntensity
- burstRayCount configurable, per-phase audio (burstAudioStage, plaqueAudioStage)
- Layer toggles + intensity sliders + ray count picker in config panel
- Per-phase audio stage pickers (BURST/PLAQUE) with EventRegistry dropdown

### Previous: Config Panel Enhancements
- Win tier: freeze fix, RangeSliders, chaining, accordion, validation, simulator
- Scene transitions: durationMs scaling, 5 styles, TEST preview, audio stage picker
- Symbol art: mini-reel preview, batch import, undo wired
