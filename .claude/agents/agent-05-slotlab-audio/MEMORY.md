# Agent 5: SlotLabAudio — Memory

## Accumulated Knowledge
- 16 subsystem providers extracted from monolithic MiddlewareProvider (P1.7 decomposition)
- Voice pool prevents audio pile-up during rapid-fire events (e.g., cascade wins)
- Ducking matrix: each bus pair has configurable ducking (e.g., SFX ducks Music)
- RTPC system: real-time parameter control (e.g., game_tension → reverb wet, filter cutoff)
- Music segments can cross-fade with configurable transition times

## Patterns
- Bus hierarchy: Master → Music/SFX/Ambience/Voice (SlotLab-specific, not DAW buses)
- Audio triggering: Event → Composite → Middleware → FFI → Rust engine
- Attenuation curves: configurable per-bus (linear, logarithmic, S-curve)
- State groups: only one state per group active (e.g., GameState: Menu|Playing|Paused)

## Gotchas
- bus_hierarchy_panel reads real FFT data from engine (not simulated)
- network_audio_service and server_audio_bridge are for live server integration
- audio_pool uses pre-allocated players for low-latency triggering
