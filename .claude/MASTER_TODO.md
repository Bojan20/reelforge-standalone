# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova
- RTPC: production-ready (35 params, 9 curves, macros, DSP) — NE MENJATI
- WebSocket: POSTOJI (websocket_client.dart) — UPGRADE, ne od nule
- MIDI: POSTOJI (midir 0.10) — samo treba event mapping

---

## SLEDEĆA SESIJA — Live Server Integration

**Arch doc:** `.claude/architecture/LIVE_SERVER_INTEGRATION.md`

### Faza 1: Upgrade postojećeg WebSocket-a
- [ ] Upgrade `websocket_client.dart` sa: reconnect backoff+jitter, heartbeat 20s/10s, seq ordering, dedup
- [ ] JSON protocol: trigger, rtpc, state, batch, snapshot, ack
- [ ] Server trigger → EventRegistry.triggerEvent()
- [ ] State recovery posle reconnect (snapshot)
- [ ] Dart UI: connection status indicator

### Faza 2: Server → RTPC Bridge (koristi POSTOJEĆI RTPC)
- [ ] Server `rtpc` JSON → rtpcSystemProvider.setRtpc(id, value, interpolationMs)
- [ ] Server RTPC name → local RTPC ID mapping config
- [ ] Jitter buffer 50ms za RTPC poruke
- [ ] Server `state` → batch RTPC (game phase transitions)

### Faza 3: Advanced Triggers
- [ ] MIDI trigger: midir (POSTOJI) → custom event mapping
- [ ] OSC trigger: dodaj rosc crate, UDP listener → event mapping
- [ ] Position trigger: playhead poll per buffer
- [ ] Marker trigger: timeline marker → event bind
- [ ] Cooldown timer per event

---

## SVE ŠTO POSTOJI (ne treba dirati)

**37 Rust crate-ova** | **69 Flutter providera** | **168 servisa**

Engine: playback, routing, metering, DSP (65 modula), SRC, plugins (5 formata), recording, export, MIDI, video
SlotLab: 43 providera, 7 executora, AUREXIS, ALE, FluxMacro, diagnostics
DAW: recording, mixing, automation, undo/redo, comping, MIDI editing, video sync
Networking: WebSocket (basic), MIDI (midir), JSON-RPC, cloud sync, collaboration
