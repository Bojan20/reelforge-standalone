# Agent 24: VideoSync — Memory

## Fixed Issues
- Drop frame was wrong: applied on ALL minutes (should skip 10-min boundaries)
- FFmpeg unsafe Send+Sync removed, properly synchronized
- Frame cache memory tracking fixed
- Timecode separator enforcement
- Frame count uses .round() not truncation

## Gotchas
- SMPTE 12M: skip frames 0,1 at each minute EXCEPT 0,10,20,30,40,50
- FFmpeg context is NOT thread-safe
- 23.976fps at 3600s: truncation loses ~86 frames vs rounding
