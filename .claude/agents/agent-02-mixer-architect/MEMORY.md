# Agent 2: MixerArchitect — Memory

## Accumulated Knowledge
- mixer_provider.dart is the central mixer state manager
- audio_math.dart contains FaderCurve — the ONLY fader curve implementation
- Default bus volumes: Master=0.85, Music=0.7, SFX=0.9, Ambience=0.5, Voice=0.95
- Routing matrix uses DFS/BFS cycle detection to prevent feedback loops

## Patterns
- All mixer FFI: setChannelVolume(trackId, volume), toggleChannelMute(trackId), toggleChannelSolo(trackId)
- Insert chain: pre-fader slots (index < maxPre) then post-fader slots
- VCA groups: trim propagation must go through MixerProvider
- Floating windows: Timer lifecycle must check mounted before setState

## Decisions
- Single sync point: MixerProvider → _busInserts + Rust
- Pan model: dual independent pan (L/R), not balance
- Automation badge wired to AutomationProvider (BUG #73 fix)
