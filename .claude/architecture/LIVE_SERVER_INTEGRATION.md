# Live Server Integration — Ultimate Architecture

**Created:** 2026-03-21
**Status:** Architecture ready

---

## Šta Wwise/FMOD NE MOGU (naša prednost)

| Limitacija Wwise/FMOD | FluxForge rešenje |
|------------------------|-------------------|
| Nema native RGS integraciju | WebSocket → RGS bridge sa <5ms latencijom |
| Nema server-side audio triggering | Server šalje JSON event → engine triggeruje lokalno |
| Offline authoring samo | Real-time authoring + live preview sa serverom |
| Nema player behavior audio adaptation | AI-driven RTPC iz server analytics-a |
| Nema per-player personalizacija | Server šalje player profil → audio se prilagođava |
| Closed source, skupa licenca | Open, custom, FluxForge-native |
| Generic game audio | Specijalizovan za iGaming/slots sa domain znanjem |

---

## Trigger Modes (Advanced)

### 1. Manual (✅ Implementirano)
Korisnik klikne PLAY → event se triggeruje.

### 2. Position Trigger
- Event se triggeruje kad playhead pređe zadatu timeline poziciju
- Korisnik definiše `triggerPosition: f64` (sekunde)
- Engine polling: svaki audio buffer proveri `playhead >= triggerPosition`
- One-shot ili loop trigger

### 3. Marker Trigger
- Event se triggeruje kad playhead pređe timeline marker
- Koristi postojeći `TimelineMarker` sistem
- Bind: `customEvent.triggerMarkerId = "marker_123"`
- Engine: kad marker pređe → `eventRegistry.triggerEvent()`

### 4. MIDI Trigger
- Event se triggeruje na MIDI note input
- `triggerMidiNote: int` (0-127), `triggerMidiChannel: int` (1-16)
- Koristi CPAL MIDI input ili `midir` crate (već u Cargo.toml)
- Velocity → volume mapping

### 5. OSC Trigger
- Event se triggeruje na OSC poruku sa mreže
- `triggerOscAddress: String` (npr. `/slot/reel_stop`)
- UDP listener na konfigurisanom portu
- Unreal/Unity/game server šalje OSC → FluxForge reaguje

### 6. WebSocket Trigger (NOVO — ne postoji u Wwise/FMOD)
- Event se triggeruje na WebSocket poruku od servera
- `triggerWsEvent: String` (npr. `SPIN_RESULT`)
- Bidirekciona komunikacija: server ↔ FluxForge
- JSON payload sa kontekstom (win amount, multiplier, etc.)
- RTPC parametri iz server podataka (win_tier → volume/pitch/bus)

### 7. RGS Bridge Trigger (ULTIMATIVNO — nijedan DAW nema ovo)
- Direktna integracija sa Remote Gaming Server-om
- RGS šalje game event (SPIN, WIN, BONUS, FREE_SPINS) → FluxForge triggeruje audio
- Latencija <5ms (WebSocket, isti data centar)
- Payload: `{ event: "WIN", tier: 3, amount: 150.0, multiplier: 5 }`
- FluxForge mapira na: bus routing, volume, pitch, event selection
- **Ovo ne postoji nigde** — Wwise/FMOD nemaju RGS awareness

---

## Live Server Protocol

```
FluxForge Studio ←→ WebSocket ←→ Game Server / RGS
                                    ↓
                              Game Logic (RNG, math model)
                                    ↓
                              Event: { type: "REEL_STOP", reel: 2, symbol: "WILD" }
                                    ↓
                              FluxForge receives → triggers audio_REEL_STOP
                              with RTPC: reel_index=2, symbol_type=WILD
```

### Protocol Format (JSON over WebSocket)

**Server → FluxForge:**
```json
{
  "type": "trigger",
  "event": "REEL_STOP",
  "params": {
    "reel_index": 2,
    "symbol": "WILD",
    "win_amount": 0
  }
}
```

```json
{
  "type": "rtpc",
  "param": "anticipation_level",
  "value": 0.8
}
```

```json
{
  "type": "state",
  "group": "game_state",
  "state": "FREE_SPINS"
}
```

**FluxForge → Server:**
```json
{
  "type": "audio_complete",
  "event": "BIG_WIN_CELEBRATION",
  "duration_ms": 3500
}
```

```json
{
  "type": "ready",
  "status": "all_assets_loaded"
}
```

---

## AI-Driven Adaptive Audio (ULTIMATIVNO)

### Player Behavior Audio Adaptation
- Server šalje player metriku: `session_duration`, `bet_size`, `win_rate`, `excitement_score`
- FluxForge prilagođava:
  - **Tempo** muzike (brži za uzbuđene igrače)
  - **Intenzitet** zvučnih efekata (louder za high-roller)
  - **Varijacija** (više varijacija za duže sesije, sprečava zamor)
  - **Near-miss feedback** intenzitet (41% veći engagement po istraživanjima)

### Personalizovani Audio Profili
- Server šalje `player_audio_profile`:
  - Preferred music genre (electronic/orchestral/ambient)
  - Volume preference (loud/medium/quiet)
  - Effect intensity (dramatic/subtle)
- FluxForge bira odgovarajući audio set per profil

### Real-Time Parameter Control (RTPC) iz Servera
- Isti koncept kao Wwise RTPC ali sa server-side izvorom
- Parametri: `excitement`, `anticipation`, `tension`, `celebration`
- Mapiraju se na: volume, pitch, filter cutoff, reverb wet, bus balance
- Interpolacija: smooth transition (ne skok) kad se RTPC menja

---

## Šta ne postoji nigde (naša inovacija)

| Feature | Status industrije | FluxForge |
|---------|------------------|-----------|
| **RGS-native audio engine** | Niko nema | Direktna integracija sa game math |
| **Server-driven RTPC** | Wwise ima RTPC ali lokalno | Server šalje RTPC remote |
| **Player-adaptive audio** | Samo istraživanja | Implementirano sa AI scoring |
| **Cross-session audio memory** | Ne postoji | Server pamti player preference |
| **Predictive audio** | Ne postoji | ML predviđa sledeći event → pre-load audio |
| **Audio analytics** | Osnovno u Wwise | Server-side: koji zvukovi koreliraju sa retention |
| **Multi-player sync audio** | FMOD ima basic | Server koordinira audio između igrača u realnom vremenu |
| **Regulatory audio compliance** | Manual | Automatska provera glasnoće po jurisdikciji |

---

## Implementacioni plan

### Faza 1: WebSocket Server Bridge
- [ ] WebSocket klijent u rf-engine (tokio + tungstenite)
- [ ] JSON protocol parser: trigger, rtpc, state poruke
- [ ] EventRegistry integracija: server event → audio trigger
- [ ] Reconnect logika sa exponential backoff

### Faza 2: RTPC iz Servera
- [ ] RTPC parameter system u engine (named params, float values)
- [ ] Server RTPC → engine parameter mapping
- [ ] Smooth interpolation (ne skok) za RTPC promene
- [ ] UI: RTPC monitor panel (real-time vrednosti)

### Faza 3: Advanced Trigger Modes
- [ ] Position trigger: playhead polling
- [ ] Marker trigger: timeline marker event binding
- [ ] MIDI trigger: midir input → event mapping
- [ ] OSC trigger: UDP listener → event mapping
- [ ] Cooldown timer per trigger

### Faza 4: AI Adaptive Audio
- [ ] Player behavior scoring (server → FluxForge)
- [ ] Audio profile selection based on player metrics
- [ ] Dynamic music tempo/intensity based on excitement
- [ ] Predictive pre-loading based on game state ML model

### Faza 5: Analytics + Compliance
- [ ] Audio event telemetry → server (which sounds played when)
- [ ] Retention correlation: which audio → longer sessions
- [ ] Loudness compliance per jurisdiction (UK, Malta, NJ, etc.)
- [ ] A/B testing framework: compare audio sets on player metrics

---

## Reference

- [Wwise vs FMOD](https://www.thegameaudioco.com/wwise-or-fmod-a-guide-to-choosing-the-right-audio-tool-for-every-game-developer)
- [RGS Architecture - Reelsoft](https://www.reelsoft.com/news/what-is-a-remote-gaming-server)
- [iGaming Audio Trends 2025](https://igaming.whimsygames.co/blog/immersive-sound-design-in-game-slots-creating-atmosphere/)
- [Adaptive Audio & Player Behavior](https://www.thedubrovniktimes.com/lifestyle/feature/item/18845-music-and-sound-in-gambling-how-audio-shapes-betting-behavior-in-2025)
- [Slot Game Audio Innovation 2026](https://gametyrant.com/news/the-evolution-of-slot-themes-in-2026-is-all-about-cinematic-realism)
- [Casino Games API Integration](https://www.groovetech.com/game-aggregation/single-api)
