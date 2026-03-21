# Live Server Integration — Ultimate Architecture

**Created:** 2026-03-21
**Status:** Architecture ready, implementation next

---

## Kompetitivna prednost nad Wwise/FMOD

| Limitacija Wwise/FMOD | FluxForge rešenje |
|------------------------|-------------------|
| Nema native RGS integraciju | WebSocket → RGS bridge <5ms |
| Nema server-side audio triggering | JSON event → lokalni trigger |
| Offline authoring samo | Live preview sa serverom |
| Nema player behavior adaptation | AI-driven RTPC iz server analytics |
| Nema per-player personalizacija | Player profil → audio prilagođavanje |
| Nema event ordering garancija | Sequence numbering + jitter buffer |
| Nema reconnect resilience | Exponential backoff + state recovery |
| Nema audio analytics | Telemetry → retention korelacija |

---

## WebSocket Protocol — Sve rupe pokrivene

### Heartbeat (KRITIČNO)
- Ping/pong svake 20s (industry standard)
- Pong timeout: 10s → connection dead
- Firewall/NAT idle timeout: 60s → heartbeat čuva konekciju
- Browser limitation: nema native ping API → custom ping frame

### Reconnect (KRITIČNO)
- Exponential backoff: 1s → 2s → 4s → 8s → 16s → max 30s
- Jitter: random ±25% na svaki interval (sprečava thundering herd)
- Max retry: beskonačno (server može biti offline satima)
- State recovery posle reconnect: server šalje current_state snapshot
- Auth token refresh pre reconnect-a (JWT expiry)

### Event Ordering (KRITIČNO za audio)
- Svaki event ima `seq: u64` monotoni brojač
- Klijent detektuje gap: `received_seq > expected_seq + 1` → request missing events
- Out-of-order tolerance: 50ms jitter buffer
- Duplicate detection: set poslednjih 100 seq brojeva

### Latency Target
- Audio event trigger: <20ms end-to-end (ideal)
- RTPC parameter change: <50ms (smooth interpolation maskira latenciju)
- State change: <100ms (acceptable za game state transitions)

### Graceful Shutdown
- SIGTERM → drain current events → close WebSocket → flush audio

---

## Protocol Format (JSON over WSS)

### Server → FluxForge

```json
{"type":"trigger","seq":1042,"ts":1711234567890,
 "event":"REEL_STOP","params":{"reel":2,"symbol":"WILD"}}

{"type":"rtpc","seq":1043,"ts":1711234567891,
 "param":"anticipation","value":0.8,"interpolation":"linear","duration_ms":500}

{"type":"state","seq":1044,"ts":1711234567892,
 "group":"game_phase","state":"FREE_SPINS","params":{"spins_remaining":10}}

{"type":"batch","seq":1045,"ts":1711234567893,
 "events":[
   {"type":"trigger","event":"REEL_STOP","params":{"reel":0}},
   {"type":"trigger","event":"REEL_STOP","params":{"reel":1}},
   {"type":"trigger","event":"REEL_STOP","params":{"reel":2}}
 ]}

{"type":"snapshot","seq":0,
 "state":{"game_phase":"BASE","anticipation":0.0,"music_intensity":0.5},
 "comment":"Full state recovery after reconnect"}
```

### FluxForge → Server

```json
{"type":"ack","seq":1042}

{"type":"audio_complete","event":"BIG_WIN","duration_ms":3500}

{"type":"ready","assets_loaded":true,"latency_ms":12}

{"type":"error","code":"EVENT_NOT_FOUND","event":"UNKNOWN_EVENT"}
```

---

## RTPC System (Real-Time Parameter Control)

### Problem sa naivnim pristupom
- Server šalje `value=0.8`, audio thread odmah setuje → čujan skok/klik
- Network jitter: vrednosti stižu neravnomerno → stutter

### Rešenje: Interpolation + Jitter Buffer

```
Server value ──→ Jitter Buffer (50ms) ──→ Smoother ──→ Audio Engine
                  (reorders,              (linear/exp
                   deduplicates)           interpolation)
```

- **Jitter buffer**: čuva poslednje 3-5 vrednosti, sortira po timestamp-u
- **Smoother**: interpolira od trenutne do ciljne vrednosti
  - Linear: `current += (target - current) * speed * dt`
  - Exponential: `current = current * 0.95 + target * 0.05` (per audio frame)
  - Timed: dostiže target za `duration_ms` (server specificira)
- **Audio thread**: čita interpoliranu vrednost (AtomicF64, zero lock)

### Parametri
| Param | Range | Default | Opis |
|-------|-------|---------|------|
| `anticipation` | 0-1 | 0 | Near-win uzbuđenje |
| `celebration` | 0-1 | 0 | Win intenzitet |
| `tension` | 0-1 | 0.3 | Bazična napetost |
| `music_intensity` | 0-1 | 0.5 | Muzika glasnoća/tempo |
| `sfx_intensity` | 0-1 | 0.7 | SFX glasnoća |
| `player_excitement` | 0-1 | 0.5 | AI-procenjena uzbuđenost |

### Mapiranje na Audio Engine
- `anticipation` → reverb wet %, filter cutoff, tremolo speed
- `celebration` → master volume boost, sparkle SFX trigger, confetti sound
- `tension` → low-pass filter, sub bass level, heartbeat tempo
- `music_intensity` → bus volume, tempo BPM multiplier
- `player_excitement` → varijacija choice (više varijacija za uzbuđene)

---

## Trigger Modes

| Mode | Izvor | Latency | Reliability |
|------|-------|---------|-------------|
| manual | UI klik | 0ms | 100% |
| server | WebSocket event | 5-50ms | 99.9% (TCP) |
| position | Playhead polling | <5ms | 100% |
| marker | Timeline marker cross | <5ms | 100% |
| midi | MIDI input (midir) | <2ms | 100% |
| osc | UDP packet | <5ms | 95% (UDP) |
| rgs | RGS game event | 10-100ms | 99.99% |

---

## Sve rupe koje moramo pokriti

### Network
- [ ] Connection drop mid-event → audio continues playing lokalno, reconnect u pozadini
- [ ] Server restart → klijent reconnect sa state recovery
- [ ] Firewall blocks WSS → fallback na HTTP long-polling
- [ ] High latency (>200ms) → jitter buffer automatski raste
- [ ] Packet duplication → seq dedup
- [ ] Man-in-the-middle → WSS (TLS 1.3), auth token per session

### Audio
- [ ] Event stiže ali audio nije učitan → queue + play kad loaded
- [ ] Isti event trigerovan 2x brzo → overlap ili replace (konfigurisano po eventu)
- [ ] RTPC se menja tokom fade-out → smooth transition, ne restart
- [ ] Server šalje event za nepostojeći zvuk → graceful error, ne crash
- [ ] Audio buffer underrun tokom network spike → silence, ne glitch

### State
- [ ] Game state mismatch posle reconnect → server snapshot overrides local
- [ ] Concurrent RTPC updates za isti param → last-write-wins sa timestamp
- [ ] Server šalje stale event (old seq) → drop silently

---

## Implementacioni plan

### Faza 1: WebSocket Bridge (engine)
- [ ] `ServerBridge` struct u rf-engine: tokio + tokio-tungstenite
- [ ] Connect/disconnect/reconnect sa exponential backoff + jitter
- [ ] Heartbeat ping/pong (20s interval, 10s timeout)
- [ ] JSON parser: trigger, rtpc, state, batch, snapshot, ack
- [ ] Seq tracking + gap detection + dedup
- [ ] EventRegistry integracija: server trigger → audio
- [ ] Error handling: unknown event, missing audio, invalid params
- [ ] FFI: server_connect(url), server_disconnect(), server_status()
- [ ] Dart UI: connection status indicator + URL config

### Faza 2: RTPC System (engine)
- [ ] `RtpcManager` struct: HashMap<String, RtpcParam>
- [ ] `RtpcParam`: current, target, interpolation mode, duration
- [ ] Audio-thread read: `AtomicU64` per param (f64 bits)
- [ ] UI-thread write: set_target() sa interpolation
- [ ] Smoother: linear/exponential/timed per param per audio frame
- [ ] Jitter buffer: 50ms, reorder by timestamp
- [ ] Mapping config: param → bus volume, filter, tempo, etc.
- [ ] FFI: rtpc_set(name, value), rtpc_get(name), rtpc_list()
- [ ] Dart UI: RTPC monitor panel (real-time param values)

### Faza 3: Advanced Triggers (engine + UI)
- [ ] Position trigger: per-clip triggerPosition, playhead poll per buffer
- [ ] Marker trigger: bind event to TimelineMarker ID
- [ ] MIDI trigger: midir crate, note → event mapping
- [ ] OSC trigger: rosc crate, UDP listener, address → event mapping
- [ ] Cooldown timer per event (AtomicU64 last_trigger_time)
- [ ] Dart UI: trigger config per custom event

---

## Reference

- [WebSocket Heartbeat Best Practices](https://www.videosdk.live/developer-hub/websocket/ping-pong-frame-websocket)
- [WebSocket Reconnection](https://oneuptime.com/blog/post/2026-01-27-websocket-reconnection-logic/view)
- [tokio-tungstenite](https://github.com/snapview/tokio-tungstenite)
- [Snapshot Interpolation (Gaffer On Games)](https://gafferongames.com/post/snapshot_interpolation/)
- [UDP vs TCP for Games](https://gafferongames.com/post/udp_vs_tcp/)
- [RGS Architecture](https://www.reelsoft.com/news/what-is-a-remote-gaming-server)
- [iGaming Audio Trends 2025](https://igaming.whimsygames.co/blog/immersive-sound-design-in-game-slots-creating-atmosphere/)
- [Adaptive Audio & Player Behavior](https://www.thedubrovniktimes.com/lifestyle/feature/item/18845-music-and-sound-in-gambling-how-audio-shapes-betting-behavior-in-2025)
