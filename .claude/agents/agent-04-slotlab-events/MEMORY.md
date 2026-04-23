# Agent 4: SlotLabEvents — Memory

## Accumulated Knowledge
- EventRegistry uses _stageToEvent map: ONE event per stage
- Two conflicting registration paths cause mutual erasure → freeze + no audio
- Composite events are the single source of truth
- FFNC naming: sfx_ → SFX bus, mus_ → Music bus

## Patterns
- Event registration: composite refresh → _syncEventToRegistry() → _syncCompositeToMiddleware()
- Event ID format: event.id property directly (e.g., "audio_REEL_STOP")

## Gotchas
- "composite_${id}_${STAGE}" format anywhere is a bug — fix to event.id
- _stageToEvent map overwrites on duplicate stage → last writer wins
- notifyListeners cascade from dual registration causes O(n²) performance
- _onAudioDroppedOnStage() was dead code — removed (BUG #9)
