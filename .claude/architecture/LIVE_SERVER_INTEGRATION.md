# Live Server Integration — Ultimate Production Architecture

**Created:** 2026-03-21 | **Updated:** 2026-03-22
**Status:** Architecture finalized

---

## Šta mora da radi kad se povežeš na server kompanije

Ovo nije demo. Ovo je production sistem koji mora da radi 24/7, sa milionima igrača, u regulisanim tržištima. Svaka rupa = lost revenue ili regulatorna kazna.

---

## FAZA 1: WebSocket Production Bridge

### 1.1 Connection Lifecycle
- [ ] WSS (TLS 1.3) — NIKADA plain WS u produkciji
- [ ] JWT auth na handshake (token u query param ili first message)
- [ ] Token refresh pre isteka (JWT exp claim monitoring)
- [ ] Origin validation (whitelist dozvoljenih servera)
- [ ] Reconnect: exponential backoff (1→2→4→8→16→30s max) + random jitter ±25%
- [ ] Heartbeat: ping svake 20s, pong timeout 10s → dead connection
- [ ] Max reconnect attempts: beskonačno (server može biti offline satima, igra mora da nastavi)
- [ ] Connection state machine: CONNECTING → AUTHENTICATING → READY → ACTIVE → RECONNECTING → DISCONNECTED
- [ ] Graceful shutdown: drain pending events → close → flush audio

### 1.2 Message Protocol
- [ ] Seq numbering (monotoni u64) na SVAKOJ poruci
- [ ] Gap detection: `received > expected + 1` → request missing
- [ ] Duplicate detection: set poslednjih 1000 seq brojeva
- [ ] Timestamp na svakoj poruci (server clock, ms precision)
- [ ] Batch messages: `type: "batch"` sa nizom sub-events
- [ ] Ack system: klijent potvrđuje kritične poruke
- [ ] Message types: trigger, rtpc, state, batch, snapshot, ack, error, ping, config

### 1.3 State Recovery (posle reconnect)
- [ ] Server šalje `snapshot` sa kompletnim stanjem (game phase, svi RTPC, active events)
- [ ] Klijent primenjuje snapshot atomski (ne parcijalno)
- [ ] Pending local events se flush-uju ili replay-uju zavisno od tipa
- [ ] Audio continuity: ako je muzika svirala pre disconnect-a, nastavlja posle

### 1.4 Failover & Degradation
- [ ] Server disconnect → audio nastavlja lokalno (poslednje poznato stanje)
- [ ] Fallback mode: ako nema servera 30s+, koristi lokalne default-e
- [ ] Multi-server support: primary + fallback URL lista
- [ ] Health check endpoint: HTTP GET /health pre WebSocket-a
- [ ] Circuit breaker: ako 5 reconnect-a za 60s fali → pause 5min → retry

### 1.5 Security
- [ ] WSS only (TLS 1.3)
- [ ] JWT validation (signature, exp, iss, aud claims)
- [ ] Rate limiting: max 100 msg/s per connection
- [ ] Message size limit: max 64KB per message
- [ ] Origin whitelist
- [ ] No sensitive data u audio event payload-u (player balance, real money amounts)

---

## FAZA 2: Server → Audio Bridge

### 2.1 Event Triggering
- [ ] Server `trigger` → EventRegistry.triggerEvent()
- [ ] Server `trigger` sa params → RTPC set BEFORE trigger (anticipation level, win tier)
- [ ] Event not found → graceful error log (ne crash)
- [ ] Event audio not loaded → queue, play kad loaded, timeout 5s
- [ ] Overlap policy per event: replace (default), overlap, queue, reject
- [ ] Priority system: critical events preempt lower priority

### 2.2 RTPC Bridge (ka POSTOJEĆEM sistemu)
- [ ] Server `rtpc` → rtpcSystemProvider.setRtpc(id, value, interpolationMs)
- [ ] Name→ID mapping config (server šalje "anticipation", mi mapiramo na RTPC ID 42)
- [ ] Jitter buffer 50ms: reorder po timestamp, deduplicate
- [ ] Interpolation: server specificira `duration_ms` → smooth transition
- [ ] Batch RTPC: server `state` → grupa RTPC promena odjednom (game phase change)
- [ ] Clamp: server vrednost van range-a → clamp + warning log

### 2.3 Game State Machine
- [ ] Server `state` poruka: `{ group: "game_phase", state: "FREE_SPINS", params: {...} }`
- [ ] State → predefinisani RTPC preset (FREE_SPINS = tension:0.8, music:0.3, sfx:1.0)
- [ ] State transitions: fade between presets (crossfade duration konfigurisana)
- [ ] State history: pamti poslednja 3 stanja za undo/debug
- [ ] Invalid state → ignore + log (ne crash)

### 2.4 Audio Asset Management
- [ ] Server može da zatraži pre-load specifičnih asseta (`type: "preload"`)
- [ ] Server može da kaže koji asseti NEĆE biti potrebni (`type: "unload"`)
- [ ] Asset loading progress → server (`type: "progress"`)
- [ ] `type: "ready"` → server zna da može da šalje evente

---

## FAZA 3: Advanced Triggers

### 3.1 MIDI Trigger (midir POSTOJI)
- [ ] MIDI note → custom event mapping (konfigurisano u UI)
- [ ] Velocity → volume mapping (0-127 → 0.0-1.0)
- [ ] Channel filter (slušaj samo channel 1-16)
- [ ] CC → RTPC mapping (MIDI CC#1 → RTPC "modulation")
- [ ] Learn mode: klikni "Learn" → sviraj notu → auto-bind

### 3.2 OSC Trigger (NOVO — rosc crate)
- [ ] UDP listener na konfigurisanom portu (default 8000)
- [ ] OSC address → event mapping (`/slot/reel_stop` → trigger REEL_STOP)
- [ ] OSC argument → RTPC value (`/slot/anticipation 0.8` → RTPC set)
- [ ] Multi-client: prihvata od bilo kog IP-ja (production: whitelist)

### 3.3 Position Trigger
- [ ] Per-event `triggerPosition: f64` (seconds on timeline)
- [ ] Playhead poll svaki audio buffer (~5ms resolution)
- [ ] One-shot ili repeating
- [ ] Hysteresis: ne triggeruj ponovo ako se playhead vrati nazad pa opet prođe

### 3.4 Marker Trigger
- [ ] Bind custom event → TimelineMarker ID
- [ ] Kad playhead pređe marker → trigger event
- [ ] Marker create → auto-suggest event binding

### 3.5 Cooldown System (svi trigger modes)
- [ ] Per-event cooldown timer (seconds)
- [ ] AtomicU64 last_trigger_timestamp
- [ ] Cooldown ne blokira — samo preskače trigger

---

## FAZA 4: Monitoring & Diagnostics

### 4.1 Connection Monitor UI
- [ ] Status indicator: 🟢 Connected / 🟡 Reconnecting / 🔴 Disconnected
- [ ] Latency display (roundtrip ms)
- [ ] Message rate (msg/s in + out)
- [ ] Seq gap counter
- [ ] Last error message

### 4.2 RTPC Monitor
- [ ] Real-time prikaz svih server-driven RTPC vrednosti
- [ ] Sparkline grafik za svaki parametar (poslednje 30s)
- [ ] Source indicator: LOCAL vs SERVER

### 4.3 Event Log
- [ ] Scrollable log svih server events (trigger, rtpc, state)
- [ ] Timestamp + seq + payload
- [ ] Filter po tipu
- [ ] Export za debugging

### 4.4 Audio Telemetry → Server
- [ ] Šaljemo nazad: koji eventi su odsvirani, trajanje, latencija
- [ ] Server koristi za analytics (koji zvukovi → bolji retention)
- [ ] Opt-in (GDPR compliant — nema player PII u telemetriji)

---

## FAZA 5: Production Hardening

### 5.1 Error Handling
- [ ] Svaka FFI/WebSocket greška → graceful recovery, NIKAD crash
- [ ] Unknown message type → log + ignore
- [ ] Malformed JSON → log + ignore
- [ ] Server šalje event za nepostojeći audio → log + ignore
- [ ] Memory pressure → unload oldest cached audio
- [ ] CPU spike → reduce SRC quality (adaptive, VEĆ POSTOJI)

### 5.2 Testing
- [ ] Mock server za lokalno testiranje (Echo mode: šalje nazad iste evente)
- [ ] Stress test: 1000 msg/s burst → verify no drops
- [ ] Latency test: measure roundtrip za svaki message type
- [ ] Reconnect test: kill connection → verify recovery
- [ ] State recovery test: disconnect → reconnect → verify snapshot restore

### 5.3 Logging
- [ ] Structured logging (JSON format) za server-side ingest
- [ ] Log levels: ERROR, WARN, INFO, DEBUG, TRACE
- [ ] Rotation: max 10MB per log file, keep 5 files
- [ ] Remote log shipping (optional — za production debugging)

### 5.4 Configuration
- [ ] Server URL(s) konfigurisane u project settings (ne hardkodirane)
- [ ] RTPC name→ID mapping editable u UI
- [ ] Trigger mappings (MIDI/OSC) savable per project
- [ ] All config serializable u project file

---

## Reference

- [WebSocket Security Hardening](https://websocket.org/guides/security/)
- [WebSocket Authentication with JWT](https://www.videosdk.live/developer-hub/websocket/websocket-authentication)
- [Failover Mechanisms](https://www.geeksforgeeks.org/system-design/failover-mechanisms-in-system-design/)
- [GLI iGaming Certification](https://gaminglabs.com/services/digital-igaming/)
- [WebSocket DDoS Prevention](https://arunangshudas.com/blog/securing-node-js-websockets-prevention-of-ddos-and-bruteforce-attacks/)
