# Agent 12: TimelineEngine — Memory

## Accumulated Knowledge
- playback.rs: main audio callback (~5000+ lines)
- track_manager.rs: all clip operations and warp markers
- tempo_state.rs: Phase 1-3 complete, Dart wiring done
- All 15 razor actions in track_manager.rs + ffi.rs
- Warp Markers Phase 4-5 still TODO
- Smart Tool 9-zone detection complete (13 zones)

## Patterns
- Clip op: Rust fn → FFI export → Dart typedef + binding → provider method
- ID extraction: RegExp(r'\d+').firstMatch(id)?.group(0) ?? '0'
- CoW: Arc::make_mut for non-destructive until commit

## Gotchas
- engine_api.dart had mixed ID parsing — now unified via _parseClipId
- Fade baking must clear metadata to prevent double-apply
