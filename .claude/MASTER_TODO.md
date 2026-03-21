# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova
- RTPC: postojeći sistem je production-ready (35 params, 9 curves, macros, DSP binding) — NE MENJATI, samo bridgovati

---

## SLEDEĆA SESIJA — Live Server Integration

**Arch doc:** `.claude/architecture/LIVE_SERVER_INTEGRATION.md`

### Faza 1: WebSocket Bridge
- [ ] `ServerBridge` struct (tokio + tokio-tungstenite)
- [ ] Connect/disconnect/reconnect (exp backoff + jitter)
- [ ] Heartbeat ping/pong (20s/10s timeout)
- [ ] JSON protocol: trigger, rtpc, state, batch, snapshot, ack
- [ ] Seq tracking + gap detection + dedup
- [ ] EventRegistry integracija: server trigger → audio
- [ ] FFI: server_connect/disconnect/status
- [ ] Dart: connection status + URL config

### Faza 2: Server → RTPC Bridge (NE novi RTPC — bridge ka postojećem)
- [ ] Server JSON `rtpc` poruka → `rtpcSystemProvider.setRtpc(id, value, interpolationMs)`
- [ ] Server RTPC name → local RTPC ID mapping (config)
- [ ] Jitter buffer 50ms za RTPC poruke (reorder by timestamp)
- [ ] Server `state` poruka → batch RTPC update (game phase transitions)
- [ ] Dart: server RTPC mapping editor panel

### Faza 3: Advanced Triggers
- [ ] Position trigger (playhead poll per buffer)
- [ ] Marker trigger (timeline marker → event bind)
- [ ] MIDI trigger (midir, note → event)
- [ ] OSC trigger (rosc, UDP → event)
- [ ] Cooldown timer per event
- [ ] Dart: trigger config per custom event

---

## IMPLEMENTIRANO

- **Signalsmith Stretch** — audio_stretcher.rs, MIT ~Élastique
- **Warp Markers** — end-to-end: model, detection, playback, drag, undo, cross-track
- **Custom Events** — EventRegistry sync, Play, probability, solo, zombie cleanup
- **RTPC System** — 35 params, 9 curves, macros, DSP binding, automation, morph (KOMPLETNO)
- **Dep Upgrade** — cpal 0.17, wgpu 28, objc2 0.6, Edition 2024
- **SRC Quality** — 7 nivoa, adaptive diagnostics
