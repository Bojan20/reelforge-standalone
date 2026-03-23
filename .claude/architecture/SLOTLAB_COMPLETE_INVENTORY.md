# SlotLab — Kompletni Inventar Blokova

## Status: Šta postoji, šta radi, šta fali

---

## VIZUELNI BLOKOVI (rendering, animacije, UI)

### 1. Reel Grid + Simboli ✅ POTPUNO
- 5×3 grid sa smooth vertikalnom spinning animacijom
- Per-reel stop timing sinhronizovan sa audio
- Motion blur tokom high-speed spina
- Overshoot + bounce landing (elasticOut)
- Timing profili: normal, turbo, studio
- Simboli sa gradient bojama, glow, oblicima (roundedRect, diamond, circle, octagon, softSquare, hexagon)
- Custom artwork podrška (PNG/JPG umesto gradient fallback-a)
- Symbol shape hijerarhija: Wild=diamond, Scatter=circle, Bonus=octagon, HP=softSquare, LP=roundedRect

### 2. Payline Vizuelizacija ✅ POTPUNO
- CustomPainter crta payline konekcije preko reelova
- Win highlight overlay sa tier-based glow

### 3. Win Prezentacija ✅ POTPUNO
- Animated win counter overlay
- Particle sistem za proslave (object pool, zero GC)
- Rollup counter animacija
- Gamble/Collect izbor posle win-a

### 4. Anticipacija ✅ POTPUNO
- Frame glow vizuelni efekat
- Particle trail sistem (intenzitet eskalira po tension levelu L1-L4)
- Anticipation config: TipA (2+ triggers anywhere), TipB (samo dozvoljeni reelovi)
- Scatter/Bonus/Wild anticipation tipovi

### 5. Scatter Win Overlay ✅ POTPUNO
- Animated scatter win proslava
- Collect animacija

### 6. Wild Expansion ✅ POTPUNO
- Vizuelni layer za wild ekspanziju

### 7. Cascade/Tumble ✅ POTPUNO
- Vizuelni layer za cascade pad simbola

### 8. Free Spins Overlay ✅ POTPUNO
- FS counter (SPINS current/total)
- Progressive multiplier display
- Retrigger overlay

### 9. Hold & Win ✅ POTPUNO
- 5×3 grid sa zaključanim coin simbolima (vrednosti prikazane)
- Remaining respins counter
- Fill progress bar
- Jackpot tip indikatori (Mini/Minor/Major/Grand)
- Real-time state iz Rust FFI

### 10. Bonus Games ✅ POTPUNO
- Pick-and-click grid sa reveal animacijom
- Wheel of Fortune sa spinning animacijom
- Board game trail sa dice roll
- Climbing ladder sa risk/collect
- Jackpot progressive tickers

### 11. Big Win Presenter ✅ POTPUNO
- Rollup counter
- Gamble/Collect choice

### 12. Scene Transitions ✅ POTPUNO
- 6-track timeline editor (FADE, BURST, PLAQUE, GLOW, SHIMMER, AUDIO)
- Draggable handles za phase duration
- Full-screen transition overlay

### 13. Game Flow Overlay ✅ POTPUNO
- Feature status bar
- Scene transition overlay
- Feature queue indicator

### 14. Control Bar ✅ POTPUNO
- Bet controls
- SPIN/STOP/SKIP buttons
- Auto-spin
- Turbo toggle

### 15. Splash Screen ✅ POTPUNO
- Loading screen pre base game

### 16. Scenario Controls ✅ POTPUNO
- Force outcome buttons (Big Win, FS, Near-Miss, Anticipation)
- One-click forced outcome triggering
- Visual spin sequence editor

---

## AUDIO BLOKOVI

### 17. Voice Mixer ✅ POTPUNO (ova sesija)
- Per-layer fader strips
- Stereo dual-pan (L/R knobovi)
- Stereo width (mid/side DSP)
- Input gain (dB trim)
- Phase invert (Ø)
- Real per-voice Rust metering
- Bus routing dropdown
- Context menu
- Drag-drop reorder
- Snapshots save/load
- Batch operations
- Search/filter
- Solo-in-context
- 5 FFI chainova (pan, width, phase, gain, metering)

### 18. Bus Mixer ✅ POTPUNO
- Per-bus faders (Master, Music, SFX, Voice, Ambience)
- Insert chain management
- Aux sends/returns (Reverb A/B, Delay, Chorus)
- Real-time SharedMeterReader metering

### 19. Event System ✅ POTPUNO
- EventRegistry (stage → audio event mapping)
- Composite events sa multi-layer support
- Auto-bind iz foldera (FFNC parser)
- Quick assign (drag-drop)
- Layer timeline sa waveforms

### 20. RTPC ✅ POTPUNO
- 8 parametara (winMultiplier, betLevel, volatility, tension, cascadeDepth, featureProgress, rollupSpeed, jackpotPool)
- Custom curves
- Macros
- DSP binding

---

## LOGIKA / STATE MACHINE BLOKOVI

### 21. Game Flow FSM ✅ IMPLEMENTIRAN (infrastruktura)
**10 stanja:** idle, baseGame, cascading, freeSpins, holdAndWin, bonusGame, gamble, respin, jackpotPresentation, winPresentation

**Transition triggeri:** scatterCount, bonusSymbolCount, coinCount, anyWin, noWin, winTierReached, featureBuy, retrigger, featureComplete, randomTrigger, playerCollect, playerGamble, playerPick, cascadeWin, cascadeNoWin, respinComplete, jackpotTriggered

**Feature Executors registrovani:**
- Free Spins (scatter trigger, retrigger)
- Cascades (win → cascade → no-win exit)
- Hold & Win (coin count trigger)
- Bonus Game (bonus symbol trigger)
- Gambling (player choice)
- Respin (scatter trigger)
- Jackpot (random/collect trigger)

**⚠️ STATUS:** Infrastruktura potpuno implementirana. Feature executors postoje ali **nisu connected po defaultu** — korisnik aktivira features koje želi kroz UI.

### 22. Stage Pipeline ✅ POTPUNO FUNKCIONALNO
```
Rust Engine (generira stage events sa timing)
    ↓
SlotEngineProvider (FFI bridge)
    ↓
SlotLabCoordinator (routing)
    ↓
SlotStageProvider (sekvencijalno puštanje sa Timerima)
    ↓
_triggerStage() (gate: preskače unassigned stages)
    ↓
EventRegistry (lookup po stage imenu)
    ↓
AudioEvent sa layerima
    ↓
AudioPlaybackService → Rust engine playback
```

### 23. Stage Defaults ✅ POTPUNO
- 182+ exact defaults
- 40+ wildcard prefixova
- 5 category defaults
- 1 global fallback
- Tri-tier resolution: exact > wildcard > category > global

---

## ŠTA FALI / GAPS

### GAP 1: GameFlow ↔ Visual povezanost
Game Flow FSM ima sva stanja ali **vizuelni blokovi ne slušaju FSM state**. Npr:
- Kad FSM uđe u `freeSpins` → FS overlay se ne pali automatski
- Kad FSM uđe u `holdAndWin` → H&W grid se ne aktivira automatski
- Vizuelni blokovi su standalone widgeti koji se triggeruju ručno iz scenario kontrola

**Šta treba:** GameFlowProvider.state promene triggeruju vizuelne overlaye automatski.

### GAP 2: Win Tier → Big Win Overlay automatski
Win evaluacija klasifikuje tier (small/medium/big/mega) ali **Big Win overlay se ne pokreće automatski** na tier >= big. Korisnik mora ručno da forsira Big Win iz scenario kontrola.

**Šta treba:** Automatski trigger Big Win overlay kad `spinResult.finalWin / totalBet >= 10`.

### GAP 3: Scatter Count → FS automatski
Scatter detekcija postoji u evaluatoru ali **ne triggeruje FS automatski**. GameFlowProvider ima pravilo `scatterCount >= 3 → freeSpins` ali nije wired do vizuelnog flow-a.

**Šta treba:** Scatter count iz spin resulta → GameFlowProvider transition → FS intro vizuelno.

### GAP 4: FS Loop automatizacija
FS executor postoji sa retrigger ali **auto-spin loop tokom FS-a ne postoji**. U WoO, FS spinovi su automatski sa 500ms delay-om.

**Šta treba:** Kad je u `freeSpins` stanju, auto-spin sa konfigurabilnim delay-om.

### GAP 5: Deferred Big Win posle FS
U WoO, Big Win se prikazuje POSLE FS Summary plaque-a. FluxForge ima deferred game flow (`pendingGameFlowResult → flushGameFlowResult`) ali **Big Win timing nije wired**.

**Šta treba:** FS exit → Summary plaque → Big Win trigger (ako fsTotalWin kvalifikuje) → finalize.

### GAP 6: Music layer crossfade tokom feature transitions
Stage defaults definišu MUSIC_BASE_L1..L5 i MUSIC_FS_L1..L5 ali **crossfade između base i FS muzike nije automatski**. U WoO, base muzika fades out na FS trigger i FS muzika fades in.

**Šta treba:** Feature enter → fade out base music layers → fade in feature music layers (sa crossfade timing-om).

### GAP 7: Reel stop → Win evaluation → Prezentacija pipeline
Reelovi se zaustave i stage events se puštaju, ali **win evaluacija ne pokreće automatski win prezentaciju**. Korisnik vidi reelove ali ne dobija automatsku highlight animaciju za winning linije.

**Šta treba:** Spin complete → evaluate → highlight winning symbols → show win overlay → rollup counter.

---

## REZIME

| Kategorija | Blokova | Status |
|-----------|---------|--------|
| Vizuelni blokovi | 16 | ✅ Svi implementirani |
| Audio blokovi | 4 | ✅ Svi implementirani |
| Logika/FSM | 3 | ✅ Implementirani ali nepovezani |
| **Gaps (povezanost)** | **7** | **⚠️ Vizual ↔ Logika wiring** |

**Zaključak:** Svi BLOKOVI postoje. Problem nije u implementaciji blokova nego u **automatskoj povezanosti** između njih. Korisnik trenutno mora ručno da triggeruje svaki vizuelni overlay iz scenario kontrola umesto da se automatski pokrenu iz game flow stanja.
