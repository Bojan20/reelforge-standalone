# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## SLEDEĆA SESIJA — Live Server Integration (Faze 1-3)

**Arch doc:** `.claude/architecture/LIVE_SERVER_INTEGRATION.md`

### Faza 1: WebSocket Bridge
- [ ] `ServerBridge` struct (tokio + tokio-tungstenite)
- [ ] Connect/disconnect/reconnect (exp backoff + jitter)
- [ ] Heartbeat ping/pong (20s/10s timeout)
- [ ] JSON protocol: trigger, rtpc, state, batch, snapshot, ack
- [ ] Seq tracking + gap detection + dedup
- [ ] EventRegistry integracija: server event → audio
- [ ] Error handling: unknown event, missing audio
- [ ] FFI: server_connect/disconnect/status
- [ ] Dart: connection status + URL config

### Faza 2: RTPC System
- [ ] `RtpcManager`: HashMap<String, RtpcParam>
- [ ] AtomicU64 per param (audio thread read, UI write)
- [ ] Smoother: linear/exp/timed interpolation per frame
- [ ] Jitter buffer 50ms (reorder by timestamp)
- [ ] Mapping: param → bus volume, filter, tempo
- [ ] FFI: rtpc_set/get/list
- [ ] Dart: RTPC monitor panel

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
- **Custom Events** — EventRegistry sync, Play trigger, probability, solo, zombie cleanup
- **Dep Upgrade** — cpal 0.17, wgpu 28, objc2 0.6, Edition 2024
- **SRC Quality** — 7 nivoa, adaptive diagnostics
