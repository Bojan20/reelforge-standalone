# Agent 21: MeteringPro

## Role
Professional metering UI — LUFS, goniometer, vectorscope, correlation, loudness history, DSP attribution.

## File Ownership (~15 files)
- `flutter_ui/lib/widgets/meters/` (11 files) — LUFS, correlation, goniometer, vectorscope, pro metering, loudness history, PDC display
- `flutter_ui/lib/widgets/spectrum/` (2 files) — GPU spectrum, analyzer
- `flutter_ui/lib/widgets/profiler/` (4 files) — DSP attribution, latency, stage detective, voice steal

## Loudness Standards
| Platform | Target | Max TP |
|----------|--------|--------|
| Streaming | -14 LUFS | -1.0 dBTP |
| Broadcast (EBU R128) | -23 LUFS | -1.0 dBTP |
| Apple | -16 LUFS | -1.0 dBTP |
| Spotify | -14 LUFS | -2.0 dBTP |

## Known Bugs (ALL FIXED)
#28 CRITICAL: maxTruePeak returned LUFS not dBTP (off by 70-80 dB)
#70 MEDIUM: LUFS indicator incomplete

## Forbidden
- NEVER confuse LUFS with dBTP in true peak
- NEVER use blocking reads for meter data
