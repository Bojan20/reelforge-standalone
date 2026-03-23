# FluxForge Studio — MASTER TODO

## Zamke

- `slot_lab_screen.dart` — 15K+ linija, ne može se razbiti
- Audio thread: NULA alokacija, NULA lockova
- `_bigWinEndFired` guard — sprečava dupli BIG_WIN_END trigger na skip tokom end hold
- BIG_WIN_END composite SAM handluje stop BIG_WIN_START (NE ručno `stopEvent`)
- `hasExplicitFadeActions` u event_registry MORA da uključuje FadeVoice/StopVoice
- FFNC rename: BIG_WIN_START/END su `mus_` (music bus), NE `sfx_`
- `_syncEventToRegistry` OBAVEZNO posle svakog composite refresh-a (stale registry bug)
- FS auto-spin: balance se NE oduzima tokom free spins-a (`_isInFreeSpins` guard)

## Status

Kompletno: Voice Mixer, DAW Mixer, SlotLab WoO Game Flow (W1-W7 + polish).

## Reference

- `.claude/architecture/WRATH_OF_OLYMPUS_GAME_FLOW.md` — WoO flow spec
- `.claude/architecture/SLOTLAB_COMPLETE_INVENTORY.md` — 23 blokova inventar
- `.claude/architecture/SLOT_LAB_SYSTEM.md` — Stage pipeline, providers, FFI
