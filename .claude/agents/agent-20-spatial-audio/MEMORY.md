# Agent 20: SpatialAudio — Memory

## Fixed Issues
- VBAP now uses proper triangulation (not nearest-speaker)
- HRTF uses spherical interpolation (not bilinear fallback)
- Binaural: proper bounds checking on input_pos
- Atmos: gain smoothing synchronized
- Room: first-order reflections only (multi-bounce = future)
- HOA up to 4th order; higher needs Wigner-D

## Patterns
- Spatial: per-object position → VBAP gains → speaker feeds
- HOA: encode → rotate → decode to speaker layout
- Binaural: HRTF convolution per source → L/R sum
