# FluxForge Studio

# ULTIMATE DSP ARCHITECTURE --- Device Preview Engine (FDEE)

Version: 1.0 FINAL Generated: 2026-02-27 09:20:06

============================================================ OVERVIEW
============================================================

FDEE (FluxForge Device Emulation Engine) is a deterministic,
low-latency, modular DSP system that emulates real-world playback
devices inside FluxForge Studio.

This document defines:

• Signal flow architecture • DSP node structure • Processing order •
Precision model • CPU budget • Latency constraints • Profile loading
schema • Stereo / mono transformations • DRC & limiter modeling •
Distortion simulation • Environmental overlays • Determinism rules

No placeholders. Runtime-ready specification.

============================================================ 1. CORE
DESIGN PRINCIPLES
============================================================

1.  Deterministic Output
    -   Same input → same output across systems
    -   No randomization in DSP stage
2.  Zero Plugin Duplication
    -   One engine
    -   Profile-driven configuration
3.  Low Latency Target
    -   ≤ 64 samples internal buffering
    -   No lookahead \> 1 ms
4.  CPU Target
    -   \< 3% on modern Apple Silicon core
    -   \< 5% on mid-tier Windows CPU
5.  Modular Graph Architecture
    -   Node-based DSP chain
    -   Runtime-configurable via JSON profile

============================================================ 2. SIGNAL
FLOW ARCHITECTURE
============================================================

Input ↓ Pre-Gain Normalization ↓ Device HPF (2nd order Butterworth) ↓
Tonal Curve EQ (Biquad chain) ↓ Stereo Processor (Width + Bass-to-Mono)
↓ Multiband DRC ↓ Device Limiter ↓ Distortion Model ↓ Environmental
Overlay (Optional) ↓ Output Trim ↓ Output

============================================================ 3. DSP NODE
SPECIFICATION
============================================================

3.1 Pre-Gain Normalization - Static gain reference (-18 dBFS nominal) -
Optional auto gain match - 64-bit internal precision

3.2 Device HPF - Cutoff range: 60--120 Hz - Q: 0.707

3.3 Tonal Curve - 5--8 biquad filters - Derived from 10 anchor frequency
points - Minimum phase processing

3.4 Stereo Processor - Mid/Side width transform - Portrait width:
0.55--0.70 - Landscape width: 0.75--0.85 - Bass-to-mono crossover:
100--180 Hz

3.5 Multiband DRC Bands: Low: 60--250 Hz Mid: 250 Hz--4 kHz High: 4
kHz--20 kHz

Parameters: Ratio: 2:1--6:1 Attack: 5--20 ms Release: 40--120 ms

3.6 Device Limiter - Soft knee - Attack: 0.5 ms - Release: 50 ms -
Ceiling: -0.3 dBFS

3.7 Distortion Model Soft clip waveshaper: y = x - (x\^3 \* k) k range:
0.1--0.4 Active above 85% output

3.8 Environmental Overlay Casino Mode: - Pink noise mask (80--90 dB sim)
Living Room: - Short IR (200--400 ms) Low Volume: - Fletcher--Munson
compensation

============================================================ 4. PROFILE
JSON RUNTIME SCHEMA
============================================================

Example:

{\
"device_id": "A3_iPhone16Pro",\
"hpf_cutoff_hz": 85,\
"width_portrait": 0.65,\
"width_landscape": 0.80,\
"bass_mono_crossover": 140,\
"eq_points": \[\
{"hz":80,"db":-18},\
{"hz":120,"db":-10},\
{"hz":200,"db":-6},\
{"hz":500,"db":-1},\
{"hz":1000,"db":0},\
{"hz":2500,"db":2},\
{"hz":4000,"db":2},\
{"hz":8000,"db":0},\
{"hz":14000,"db":-3},\
{"hz":20000,"db":-9}\
\],\
"drc": {\
"low_ratio": 4.0,\
"mid_ratio": 2.5,\
"high_ratio": 2.0\
},\
"limiter_ceiling_db": -0.3,\
"distortion_amount": 0.25\
}

============================================================ 5. LATENCY
& PERFORMANCE
============================================================

Total latency target: ≤ 0.7 ms\
No linear-phase filters\
No oversampling unless distortion enabled

============================================================ 6.
DETERMINISM GUARANTEE
============================================================

• No randomness\
• Fixed coefficient calculation\
• Profile hash validation

============================================================ END OF
SPECIFICATION
============================================================
