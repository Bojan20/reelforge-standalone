# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova
- RTPC: production-ready — NE MENJATI
- WebSocket: 3010+ linija PRODUCTION — bridge + hardening DONE

---

## SLEDEĆA SESIJA — Faza 2: Advanced Triggers

### MIDI Trigger
- [ ] MIDI note → custom event mapping (config per event)
- [ ] Velocity → volume (0-127 → 0.0-1.0)
- [ ] CC → RTPC mapping
- [ ] Learn mode: klik "Learn" → sviraj notu → auto-bind

### OSC Trigger
- [ ] rosc crate (UDP listener)
- [ ] OSC address → event mapping
- [ ] OSC argument → RTPC value

### Position + Marker Trigger
- [ ] Per-event triggerPosition, playhead poll per buffer
- [ ] Timeline marker → event bind
- [ ] Hysteresis (ne triggeruj ponovo pri rewind)

### Cooldown System
- [ ] Per-event cooldown timer (seconds)
- [ ] AtomicU64 last_trigger (ili DateTime u Dart)

---

## IMPLEMENTIRANO

- 37 crate-ova | 69 providera | 168 servisa | 3010+ networking
- Server Audio Bridge (trigger/rtpc/state/batch/snapshot + jitter buffer)
- WebSocket hardening (seq gap/dedup, circuit breaker, reconnect reset)
- Signalsmith Stretch, Warp Markers (15 testova), Custom Events
- RTPC (35 params, 9 curves, macros, DSP binding)
- 17 QA rundi, 60+ bugova, 447 testova
