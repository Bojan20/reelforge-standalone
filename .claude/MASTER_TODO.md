# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova
- RTPC: production-ready — NE MENJATI
- WebSocket: 2552 linija POSTOJI (3 fajla) — samo bridge + hardening
- MIDI: POSTOJI (midir 0.10)

---

## SLEDEĆA SESIJA — Live Server (samo ono što FALI)

**Arch doc:** `.claude/architecture/LIVE_SERVER_INTEGRATION.md`
**Postojeći kod:** `websocket_client.dart` (1512), `websocket_connector.dart` (559), `live_engine_service.dart` (481)

### Faza 1: Bridge + Hardening (proširenje postojećeg)
- [ ] Seq gap detection + dedup u websocket_client.dart
- [ ] State snapshot recovery posle reconnect
- [ ] Circuit breaker (5 fail/60s → pause 5min)
- [ ] Rate limiting (100 msg/s)
- [ ] Server trigger → EventRegistry.triggerEvent() bridge
- [ ] Server rtpc → rtpcSystemProvider.setRtpc() bridge
- [ ] Server state → batch RTPC preset transition
- [ ] Connection monitor UI panel

### Faza 2: Advanced Triggers
- [ ] MIDI trigger: midir → custom event mapping + learn mode
- [ ] OSC trigger: rosc crate, UDP → event mapping
- [ ] Position + Marker triggers
- [ ] Cooldown timer per event

### Faza 3: Production Hardening
- [ ] Error handling: NIKAD crash, graceful za SVE
- [ ] Mock server za testiranje
- [ ] Stress/reconnect/recovery testovi
- [ ] Structured logging + config u project settings

---

## IMPLEMENTIRANO

- 37 Rust crate-ova | 69 providera | 168 servisa | 2552 linija networking
- Signalsmith Stretch, Warp Markers, Custom Events, RTPC (35 params)
- WebSocket (state machine, backoff, heartbeat, queue, JWT, TCP fallback)
- 15 QA rundi, 55+ bugova, 447 testova
