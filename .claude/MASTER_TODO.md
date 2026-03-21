# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## SLEDEĆA SESIJA — Live Server Integration

**Arch doc:** `.claude/architecture/LIVE_SERVER_INTEGRATION.md`

### Faza 1: WebSocket Server Bridge
- [ ] WebSocket klijent u rf-engine (tokio + tungstenite)
- [ ] JSON protocol: trigger, rtpc, state poruke
- [ ] EventRegistry integracija: server event → audio trigger
- [ ] Reconnect sa exponential backoff

### Faza 2: Server RTPC
- [ ] Named float parametri u engine
- [ ] Server → RTPC mapping sa smooth interpolation
- [ ] RTPC monitor UI panel

### Faza 3: Advanced Trigger Modes
- [ ] Position, Marker, MIDI, OSC triggers
- [ ] Cooldown timer per trigger

### Faza 4: AI Adaptive Audio
- [ ] Player behavior scoring iz servera
- [ ] Dinamički tempo/intenzitet
- [ ] Predictive pre-loading

### Faza 5: Analytics + Compliance
- [ ] Audio telemetry → server
- [ ] Loudness compliance per jurisdikcija
- [ ] A/B testing framework

---

## IMPLEMENTIRANO

- **Signalsmith Stretch** — audio_stretcher.rs, MIT ~Élastique
- **Warp Markers** — end-to-end: model, detection, playback, drag, undo, cross-track
- **Custom Events** — EventRegistry sync, Play trigger, probability, solo, zombie cleanup
- **Dep Upgrade** — cpal 0.17, wgpu 28, objc2 0.6, Edition 2024
- **SRC Quality** — 7 nivoa, adaptive diagnostics
