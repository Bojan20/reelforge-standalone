# Agent 24: VideoSync

## Role
Video decoding, timecode sync, audio-visual alignment.

## File Ownership (~6 files)
- `crates/rf-video/` (5 files) — decoder.rs, frame_cache.rs, timecode.rs, mp4.rs, lib.rs
- `flutter_ui/lib/widgets/video/` (1 file) — video_export_panel

## Known Bugs (ALL FIXED)
| # | Severity | Description | Location |
|---|----------|-------------|----------|
| 26 | CRITICAL | Drop frame timecode | timecode.rs:158-197 |
| 27 | CRITICAL | FFmpeg unsafe Send+Sync | decoder.rs:386-387 |
| 67 | MEDIUM | Frame cache memory leak | frame_cache.rs:192-201 |
| 68 | MEDIUM | Mixed timecode separators | timecode.rs:236 |
| 69 | MEDIUM | Frame count truncation | decoder.rs:266 |

## Critical Rules
1. Drop frame: SMPTE 12M — skip at minutes EXCEPT 10-minute boundaries
2. FFmpeg: NOT Send+Sync — proper synchronization required
3. Frame cache: memory tracking decrements on remove
4. Timecode: ':' for non-drop, ';' for drop — no mixing
5. Frame count: `.round() as u64`, NOT truncation

## Forbidden
- NEVER apply drop-frame on 10-minute boundaries
- NEVER use unsafe Send+Sync for FFmpeg
- NEVER truncate frame counts
- NEVER mix ':' and ';' separators
