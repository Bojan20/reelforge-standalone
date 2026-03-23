# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## DONE: Voice Mixer + Mixer Unification

Kompletno — 5 FFI chainova, 40+ bug fixeva, 12+ QA rundi. Svi poznati limiti fixovani.

---

## PENDING: SlotLab Game Flow Wiring (WoO Reference)

Cilj: Svi blokovi su implementirani ali NEPOVEZANI. Treba ih wire-ovati tako da
slot mašina radi identično kao Wrath of Olympus — automatski, bez ručnog triggerovanja.

**Reference:** `.claude/architecture/WRATH_OF_OLYMPUS_GAME_FLOW.md`
**Inventar:** `.claude/architecture/SLOTLAB_COMPLETE_INVENTORY.md`

### W1: Reel Stop → Win Evaluation → Prezentacija Pipeline
- [ ] Spin complete → automatski evaluate grid (scatter count, line wins, win tier)
- [ ] Highlight winning simbole na gridu (tier-based glow)
- [ ] Win overlay sa rollup counter animacijom
- [ ] Per-line highlight sekvenca (jedan po jedan)
- [ ] Skip/abort support
- [ ] Timing: preshow 400-800ms, rollup 300-400ms, line highlight 500-600ms/line

### W2: Win Tier → Big Win Overlay Automatski
- [ ] `finalWin / totalBet >= 10` → automatski Big Win overlay
- [ ] 3 tiera: BIG (10×), MEGA (25×), EPIC (50×)
- [ ] Rollup sa tier upgrade animacijom (4s po tieru)
- [ ] End celebration (7s hold, coin shower, confetti za tier 3)
- [ ] Skip support (skoči na END fazu)
- [ ] Audio: BIG_WIN_START (loop music), BIG_WIN_TIER1-3 (SFX), BIG_WIN_END

### W3: Scatter Count → Free Spins Automatski
- [ ] 3+ scattera → scatter highlight (2s pauza sa golden glow)
- [ ] Trigger FS intro overlay (plaque sa brojem spinova)
- [ ] Awards: 3S=14, 4S=16, 5S=18 free spins
- [ ] GameFlowProvider transition: baseGame → freeSpins
- [ ] Audio: SCATTER_LAND, FEATURE_ENTER

### W4: Free Spins Complete Loop
- [ ] FS intro → čekaj user input ili 2s auto-start
- [ ] Auto-spin loop (500ms delay između spinova)
- [ ] Progresivni multiplier (+1× na svaki winning spin, max 10×)
- [ ] Multiplier display sa bump animacijom
- [ ] FS counter (SPINS X/Y + MULTIPLIER + TOTAL WIN)
- [ ] Retrigger (3+ scattera = +14/16/18 spinova, overlay 2s)
- [ ] Mercy mehanika (10 consecutive misses → inject wild)
- [ ] Safety caps (FEATURE_LOOP_CAP, MAX_WIN_CAP)
- [ ] Audio: MUSIC_FS_L1..L5 (loop), MULTIPLIER_INCREASE, FREESPIN_RETRIGGER

### W5: FS Exit → Summary → Optional Big Win → Base Game
- [ ] FS complete plaque ("FREE SPINS COMPLETE" + total win)
- [ ] Outro transition (FS atmosphere → base atmosphere)
- [ ] Restore trigger grid (base game simboli)
- [ ] Ako fsTotalWin kvalifikuje → Big Win overlay PRE base game return-a
- [ ] Finalize: activeMode=base, reset sav FS state
- [ ] Audio: FEATURE_EXIT, BIG_WIN_START/END (ako kvalifikuje)
- [ ] Balance crediting: fsTotalWin + triggerResult.finalWin

### W6: Music Layer Crossfade na Feature Transitions
- [ ] Base → FS: fade out MUSIC_BASE_L1..L5, fade in MUSIC_FS_L1..L5 (500ms crossfade)
- [ ] FS → Base: fade out FS music, fade in base music
- [ ] Big Win: fade out sve, play BIG_WIN_START (loop)
- [ ] Big Win End: stop big win music, restore previous music
- [ ] Timing sinhronizovan sa vizuelnim transitions

### W7: GameFlow FSM ↔ Visual Overlay Auto-Trigger
- [ ] GameFlowProvider.state listener na vizuelnim overlay widgetima
- [ ] freeSpins state → FS overlay ON
- [ ] holdAndWin state → H&W grid ON
- [ ] bonusGame state → Bonus panel dispatch
- [ ] gamble state → Gamble panel ON
- [ ] jackpotPresentation → Jackpot sequence ON
- [ ] winPresentation → Big Win overlay ON
- [ ] baseGame/idle → sve overlaye OFF

---

## IMPLEMENTIRANO

- **37 crate-ova** | **71 providera** | **170+ servisa** | **3500+ networking linija**
- SlotLab Voice Mixer (complete: 5 FFI chains, 23 features, 40+ bug fixes)
- DAW Mixer Enhancements (bus routing, activity indicator, audition)
- 23 SlotLab blokova (16 vizuelnih, 4 audio, 3 logika)
- Wrath of Olympus game flow analiza (486 linija dokumentacije)
- SlotLab kompletni inventar (230 linija, 7 gap-ova identifikovanih)
- Signalsmith Stretch, Warp Markers, Custom Events, RTPC
- Server Audio Bridge, MIDI/OSC Trigger, TriggerManager
- Mock Game Server, Connection Monitor, Dep Upgrade
- 22+ QA rundi, 100+ bugova fixovano, 447 testova
