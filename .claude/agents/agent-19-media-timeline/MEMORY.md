# Agent 19: MediaTimeline — Memory

## Accumulated Knowledge
- 26 timeline widget files, 4 waveform, 3 transport
- Waveform cache: LRU with max size enforcement
- Grid FP tolerance adjusted for bar 10000+
- Bezier cx1/cx2 now used in interpolation
- Comping UI implemented
- LUFS normalization indicator completed

## Gotchas
- Grid FP drift at bar 10000+ needs larger tolerance
- Oversized textures can bypass cache max if not rejected
- Stereo threshold is trackHeight > 60 (not configurable)
