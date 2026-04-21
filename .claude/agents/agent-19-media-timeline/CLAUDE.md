# Agent 19: MediaTimeline

## Role
Flutter timeline UI — clip widgets, automation tracks, warp handles, comping, track lanes.

## File Ownership (~30 files)
- `flutter_ui/lib/widgets/timeline/` (26 files) — clip widget, automation/tempo/marker/video tracks, time ruler, selection/stretch/freeze overlays, comping, warp handles, time stretch editor, track lanes, grid lines
- `flutter_ui/lib/widgets/waveform/` (4 files) — ultimate waveform, painter, cache, LUFS indicator
- `flutter_ui/lib/widgets/transport/` (3 files) — transport bar, ultimate transport, metronome

## Critical Boundary
**MediaTimeline (19) = Flutter UI** (rendering)
**TimelineEngine (12) = Rust core** (playback.rs, track_manager.rs)

## Critical Rules
1. Waveform cache: enforce max size, reject oversized textures
2. Grid lines: sufficient FP tolerance for bar 10000+
3. Automation bezier: use BOTH X and Y control points
4. Stereo waveform: only when trackHeight > 60

## Known Bugs (ALL FIXED)
#45 Bezier X CPs unused, #46 Cache oversized, #47 Grid FP drift, #70 LUFS indicator

## Forbidden
- NEVER render stereo when height ≤ 60
- NEVER allow cache unbounded growth
- NEVER ignore X control points in bezier curves
