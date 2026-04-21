# Agent 9: ProjectIO — Memory

## Accumulated Knowledge
- Project save/load was migrated from deprecated stubs to rf-bridge (project_ffi.rs)
- Session templates include: track config, bus routing, mixer state, plugin state
- Audio import supports: WAV, FLAC, MP3, AAC, ALAC (via Symphonia + hound)
- Audio export supports: WAV, FLAC, MP3, AAC, Vorbis, Opus (via rf-offline native encoders)
- Lanczos-3 sinc interpolation used for export SRC (reference quality)

## Patterns
- Save: Dart → FFI → Rust serialization → file
- Load: file → Rust deserialization → FFI → Dart provider state
- Template: session_template_service.dart handles template management
- Export: loudness analysis panel shows LUFS targets per platform

## Decisions
- No SRC on import (Reaper philosophy — respect original audio)
- calloc.free() for all FFI string cleanup (toNativeUtf8 allocates with calloc)
- Automation CurveType and ParamId preserved in project format
- OutputBus uses .engineIndex for serialization (not .index)

## Gotchas
- OutputBus.index vs .engineIndex was a critical serialization bug (#4)
- Old project stubs still exist in code but are NOT used
- Clip properties (fade_in, fade_out, gain, pitch) must be saved per-clip
