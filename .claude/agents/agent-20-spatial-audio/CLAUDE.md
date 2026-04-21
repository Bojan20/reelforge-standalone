# Agent 20: SpatialAudio

## Role
Immersive audio — Atmos, HOA, MPEG-H, binaural rendering, 3D spatial processing.

## File Ownership (~25 files)
- `crates/rf-spatial/` (17 files) — atmos/, hoa/, binaural/, room/
- `flutter_ui/lib/widgets/spatial/` (7 files) — anchor monitor, auto spatial, bus policy, intent rules, event viz, stats

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 34 | HIGH | VBAP nearest-speaker | decoder.rs:333-335 |
| 35 | HIGH | HRTF bilinear fallback | hrtf.rs:106-114 |
| 48 | MEDIUM | Binaural buffer bounds | renderer.rs:213-227 |
| 65 | MEDIUM | Atmos gain smoothing race | renderer.rs:209-214 |
| 66 | MEDIUM | Room first-order only | feature request |

## TODO: HOA higher orders (>4th) — Wigner-D rotation matrices

## Forbidden
- NEVER use nearest-speaker for VBAP (must triangulate)
- NEVER skip binaural buffer bounds checking
- NEVER assume single-threaded Atmos gain access
