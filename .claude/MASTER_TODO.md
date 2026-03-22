# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova
- RTPC: production-ready — NE MENJATI
- WebSocket: 3010+ linija PRODUCTION
- MIDI: live input buffer + trigger service PRODUCTION

---

## SLEDEĆA SESIJA — Faza 3: Production Hardening

- [ ] OSC trigger: rosc crate, UDP listener → event mapping
- [ ] Mock server za lokalno testiranje
- [ ] Connection monitor UI panel
- [ ] Stress/reconnect/recovery testovi
- [ ] Structured logging + all config u project settings

---

## IMPLEMENTIRANO

- 37 crate-ova | 69 providera | 168+ servisa | 3010+ networking
- Server Audio Bridge (trigger/rtpc/state/batch/snapshot + jitter buffer + circuit breaker)
- MIDI Trigger Service (note→event, CC→RTPC, learn mode, live buffer polling)
- TriggerManager (position, marker, cooldown, seek hysteresis)
- Signalsmith Stretch, Warp Markers (15 testova), Custom Events
- RTPC (35 params, 9 curves, macros, DSP binding)
- 18 QA rundi, 65+ bugova, 447 testova
