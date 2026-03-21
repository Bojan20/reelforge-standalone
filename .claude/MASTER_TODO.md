# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova
- RTPC: production-ready (35 params, 9 curves, macros, DSP) — NE MENJATI
- WebSocket: POSTOJI (websocket_client.dart) — UPGRADE, ne od nule
- MIDI: POSTOJI (midir 0.10) — samo treba event mapping

---

## SLEDEĆA SESIJA — Live Server (5 faza)

**Arch doc:** `.claude/architecture/LIVE_SERVER_INTEGRATION.md`

### Faza 1: WebSocket Production Bridge
- [ ] WSS + JWT auth + token refresh + origin validation
- [ ] Reconnect (exp backoff+jitter) + heartbeat (20s/10s)
- [ ] Seq ordering + gap detection + dedup
- [ ] State recovery (snapshot posle reconnect)
- [ ] Failover: local fallback, multi-server, circuit breaker
- [ ] Security: rate limit 100msg/s, 64KB max, TLS 1.3
- [ ] Connection state machine (6 states)

### Faza 2: Server → Audio Bridge
- [ ] Server trigger → EventRegistry (+ overlap policy, priority)
- [ ] Server rtpc → postojeći rtpcSystemProvider (+ jitter buffer)
- [ ] Game state machine (state → RTPC preset, crossfade transition)
- [ ] Asset pre-load/unload na zahtev servera

### Faza 3: Advanced Triggers
- [ ] MIDI: note→event, velocity→volume, CC→RTPC, learn mode
- [ ] OSC: rosc crate, UDP listener, address→event mapping
- [ ] Position + Marker triggers sa hysteresis
- [ ] Cooldown timer (AtomicU64 per event)

### Faza 4: Monitoring & Diagnostics
- [ ] Connection monitor (status, latency, msg rate, gaps)
- [ ] RTPC monitor (sparklines, local vs server source)
- [ ] Event log (scrollable, filterable, exportable)
- [ ] Audio telemetry → server (opt-in, GDPR)

### Faza 5: Production Hardening
- [ ] Error handling: NIKAD crash, graceful za SVE edge case
- [ ] Mock server za testiranje
- [ ] Stress/latency/reconnect/recovery testovi
- [ ] Structured logging + rotation + remote shipping
- [ ] All config in project settings (ne hardkodirano)

---

## IMPLEMENTIRANO

- **37 Rust crate-ova** | **69 providera** | **168 servisa**
- Signalsmith Stretch, Warp Markers, Custom Events, RTPC (35 params)
- Dep Upgrade (cpal 0.17, wgpu 28, objc2 0.6, Edition 2024)
- SRC Quality (7 nivoa), Adaptive Diagnostics
- 15 QA rundi, 55+ bugova fiksirano, 447 testova
