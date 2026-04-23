# Agent 3: SlotLabUI — Memory

## Accumulated Knowledge
- slot_lab_screen.dart is 13000+ lines — cannot be split
- SlotLabCoordinator replaced SlotLabProvider (typedef redirect, old is dead code)
- Context Bar ROW 2 cleaned: removed NOTIF badge, ERRORS badge, preload indicator
- Undo/Redo moved from ASSIGN header to ROW 2
- All async operations check mounted before setState

## Gotchas
- _syncEventToRegistry() is the ONLY allowed path to EventRegistry
- Two registration paths cause: N × delete + register + notifyListeners cascade → freeze + no audio
- _syncCompositeToMiddleware → MiddlewareEvent system, NOT EventRegistry
