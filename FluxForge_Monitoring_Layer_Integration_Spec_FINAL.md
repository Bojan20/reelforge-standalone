# FluxForge Studio

# MONITORING LAYER INTEGRATION SPECIFICATION

# Device Preview Engine --- FINAL ARCHITECTURE

Generated: 2026-02-27 09:26:21

================================================================
ABSOLUTE FINAL DOCUMENT --- NO STANDALONE MODE
================================================================

This specification defines how the Device Preview Engine is integrated
INSIDE FluxForge Studio as a monitoring-only layer.

This is NOT a plugin. This is NOT an insert. This is NOT part of runtime
export.

It is a post-master monitoring transform.

================================================================ 1.
ARCHITECTURAL POSITION
================================================================

Full Studio Signal Flow:

Asset → Clip Gain → Insert Chain → Bus Routing → Ducking Engine → Master
Bus → Monitoring Layer → Hardware Output

Device Preview exists ONLY inside Monitoring Layer.

================================================================ 2.
MONITORING LAYER STRUCTURE
================================================================

FluxForgeCore ├── AudioGraph ├── InsertNodes ├── BusNodes ├── MasterNode
├── MonitoringLayer │ ├── DevicePreviewNode │ ├── EnvironmentNode │ ├──
LevelMatchNode │ └── BypassRouter └── OutputDriver

MonitoringLayer properties:

• Not serialized into project export • Not included in runtime JSON
build • Not rendered into bounce/export • Active only during Studio
monitoring

================================================================ 3.
DEVICE PREVIEW NODE RESPONSIBILITY
================================================================

DevicePreviewNode performs:

1.  Tonal Curve Transform
2.  Stereo Width Transform
3.  Bass-to-Mono Folding
4.  Multiband DRC Emulation
5.  Device Limiter Emulation
6.  Harmonic Distortion Modeling

Constraints:

• Zero lookahead processing • Max internal buffer: 32 samples •
Deterministic math only • No random modulation • No OS-dependent DSP
branches

================================================================ 4.
EXPORT SAFETY GUARANTEE
================================================================

When exporting:

IF (RenderMode == Export \|\| RenderMode == RuntimeBuild)
MonitoringLayer = Bypassed DevicePreviewNode = Not Instantiated

Export pipeline must confirm:

assert(MonitoringLayer.active == false)

Fail-safe rule: If MonitoringLayer state cannot be verified → export
aborts.

================================================================ 5.
PROFILE MANAGEMENT
================================================================

Profiles stored in:

/FluxForge/Profiles/Device/

At load:

• Profile parsed • Hash generated • Hash stored in session memory •
Coefficients generated once • No runtime recalculation per block

Profile cannot modify:

• Global gain staging • Master limiter • Bus routing • SlotLab logic

================================================================ 6.
PERFORMANCE REQUIREMENTS
================================================================

Target latency contribution: ≤ 0.7 ms

CPU Budget: ≤ 3% single Apple Silicon core ≤ 5% mid-tier Windows CPU

No linear-phase filters. No oversampling unless distortion enabled. No
dynamic allocation inside audio thread.

================================================================ 7. UI
INTEGRATION
================================================================

Device Preview is controlled via Studio Top Bar:

\[ Device ▼ \] \[ Orientation Toggle \] \[ Environment ▼ \] \[ Level
Match \] \[ Bypass \]

UI must not create new plugin windows. No floating panels. No additional
mixer channel.

================================================================ 8.
DETERMINISM POLICY
================================================================

• Same input buffer → identical output buffer • Fixed floating precision
(defined by core) • No denormal drift • No time-dependent behavior •
Coefficients computed outside audio thread

================================================================ 9.
THREAD MODEL
================================================================

Audio Thread: • Executes DevicePreviewNode.process()

UI Thread: • Loads profile • Computes coefficients • Sends atomic update
flag

No locking allowed inside audio callback.

================================================================ 10.
FUTURE EXPANSION RULES
================================================================

Allowed future additions:

• Measured hardware IR convolution • Codec simulation layer • Thermal
compression model • Device aging simulation

Forbidden:

• Standalone plugin mode • Insert-level usage • Export inclusion •
Randomized speaker modeling

================================================================ 11.
FINAL DECLARATION
================================================================

Device Preview inside FluxForge is:

• Monitoring-only • Post-master • Deterministic • Export-safe • CPU
bounded • Architecturally isolated

This document supersedes all previous Device Preview concepts.

================================================================ END OF
FINAL INTEGRATION SPECIFICATION
================================================================
