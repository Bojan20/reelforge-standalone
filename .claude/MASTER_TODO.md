# FluxForge Studio — MASTER TODO

## Active Traps

- `slot_lab_screen.dart` — 13K+, NE MOŽE se razbiti
- Audio thread: NULA alokacija, NULA lockova

---

## DONE: Voice Mixer + Mixer Unification

Kompletno — 5 FFI chainova, 40+ bug fixeva, 12+ QA rundi. Svi poznati limiti fixovani.

---

## DONE: SlotLab Game Flow Wiring (WoO Reference)

W1-W7 wiring kompletiran. Automatski flow: spin → win eval → prezentacija → scatter
→ FS entry plaque → FS auto-spin loop → FS exit plaque → base game. Music crossfade
i vizuelni overlaji automatski via GameFlowProvider FSM.

**Reference:** `.claude/architecture/WRATH_OF_OLYMPUS_GAME_FLOW.md`
**Inventar:** `.claude/architecture/SLOTLAB_COMPLETE_INVENTORY.md`

### W1: Reel Stop → Win Evaluation → Prezentacija Pipeline ✅ DONE
- [x] Spin complete → automatski evaluate grid (scatter count, line wins, win tier)
  - `_onAllReelsStoppedVisual()` → `_finalizeSpin()` automatski
  - Scatter: `result.featureTriggered` → scatter highlight 2.5s → flush game flow
- [x] Highlight winning simbole na gridu (tier-based glow)
  - Symbol pulse animation, per-symbol audio (HP1_WIN, WILD_WIN, etc.)
  - Wild priority rule: WILD overrides other symbol audio
- [x] Win overlay sa rollup counter animacijom
  - P5 WinTierConfig tier-based rollup duration
  - Phase 2 plaque sa counter animation (`_winAmountController`)
- [x] Per-line highlight sekvenca (jedan po jedan)
  - `_startWinLinePresentation()` cycling timer (1500ms default)
  - WIN_LINE_SHOW audio per line
- [x] Skip/abort support
  - `_executeSkipFadeOut()` — fade out + stop all audio + END stages
  - `requestSkipPresentation()` → provider skip flow
- [x] Timing: preshow 1050ms (3×350ms symbol highlight), tier-based rollup, 1500ms/line
  - Konfigurabilno preko WinTierConfig

### W2: Win Tier → Big Win Overlay Automatski ✅ DONE
- [x] `finalWin / totalBet >= 10` → automatski Big Win overlay
  - `_isBigWinTier()` → `_startTierProgression()` u slot_preview_widget.dart
- [x] Tier-ovi: P5 WinTierConfig data-driven (konfigurabilno)
- [x] Rollup sa tier upgrade animacijom (4s po tieru)
  - `_advanceTierProgression()` → `_tierDisplayDurationMs`
- [x] End celebration: BIG_WIN_END (4s hold) + COIN_SHOWER_END
- [x] Skip support (guard na svakom koraku za `skipRequested`)
- [x] Audio: BIG_WIN_START/END, COIN_SHOWER, per-tier stages, ROLLUP

### W3: Scatter Count → Free Spins Automatski ✅ DONE
- [x] 3+ scattera → scatter highlight (2.5s pauza sa golden glow)
  - `_startScatterHighlight()` u slot_preview_widget.dart
- [x] Trigger FS intro overlay (scene transition plaque sa brojem spinova)
  - `flushGameFlowResult()` → GameFlowProvider → scene transition
- [x] Awards: konfigurabilno u FreeSpinsExecutor (default 10/15/20)
- [x] GameFlowProvider transition: baseGame → freeSpins
- [x] Audio: SCATTER_WIN, FS_HOLD_INTRO (scene transition)

### W4: Free Spins Complete Loop ✅ WIRED
- [x] FS intro → scene transition plaque → dismiss → auto-spin start
  - `GameFlowIntegration._onTransitionDismissed` → `startFsAutoLoop()`
- [x] Auto-spin loop (500ms delay između spinova)
  - `GameFlowProvider._scheduleNextFsSpin()` → `onRequestAutoSpin` → `_handleSpin`
- [x] Progresivni multiplier (+1× na svaki winning spin, max 10×)
  - FreeSpinsExecutor.step() → `_updateMultiplier()`
- [x] FS counter (SPINS X/Y + MULTIPLIER + TOTAL WIN)
  - `_FreeSpinsOverlay` u game_flow_overlay.dart
- [x] Retrigger (3+ scattera = +spins)
  - FreeSpinsExecutor.step() → scatter count check → addSpins
- [ ] Multiplier display bump animacija (TODO: animate)
- [ ] Mercy mehanika (TODO: engine-level wild injection)
- [ ] Safety caps (TODO: FEATURE_LOOP_CAP, MAX_WIN_CAP)
- [x] Audio: MUSIC_FS_L1 (on plaque dismiss), FS_MULTIPLIER_INCREASE, FS_RETRIGGER

### W5: FS Exit → Summary → Base Game ✅ WIRED
- [x] FS complete plaque ("FREE SPINS COMPLETE" + total win)
  - `_exitCurrentFeature()` → `_startExitTransition()` sa exitWin
- [x] Outro transition: scene transition overlay
- [x] Finalize: activeMode=idle, reset FS state
- [x] Audio: FS_END, MUSIC_FS_END → base music fade-in
- [ ] Deferred Big Win overlay posle FS (TODO: ako fsTotalWin kvalifikuje)
- [ ] Balance crediting UI (TODO: animated balance update)

### W6: Music Layer Crossfade na Feature Transitions ✅ DONE
- [x] Base → FS: fadeOutBaseGameLayers(fadeMs: 500) → FS music
  - `GameFlowIntegration._onTransitionStart(entering, FS)`
- [x] FS → Base: stop FS music → MUSIC_FS_END → restartBaseGameLayersSilent
  - `GameFlowIntegration._onTransitionStart(exiting, FS)`
- [x] Big Win: fadeOutBaseGameLayers → BIG_WIN_START (loop)
  - `_startTierProgression()` u slot_preview_widget.dart
- [x] Big Win End: BIG_WIN_END → restartBaseGameLayersSilent → resetMusicLayerToBase
  - `_finishTierProgression()` u slot_preview_widget.dart
- [x] Timing sinhronizovan sa scene transitions

### W7: GameFlow FSM ↔ Visual Overlay Auto-Trigger ✅ DONE
- [x] GameFlowProvider.state → Consumer u PremiumSlotPreview
  - `GameFlowOverlay` widget sa Consumer<GameFlowProvider>
- [x] freeSpins state → FS overlay ON (_FreeSpinsOverlay)
- [x] holdAndWin state → H&W overlay ON (_HoldAndWinOverlay)
- [x] bonusGame state → Bonus panel dispatch (_BonusGameOverlay)
- [x] gamble state → Gamble panel ON (_GambleOverlay)
- [x] jackpotPresentation → Jackpot overlay ON
- [x] Scene transitions → fullscreen overlay (_SceneTransitionOverlay)
- [x] baseGame/idle → sve overlaye OFF (Consumer rebuilds with empty stack)

---

## REMAINING TODO (Polish)

- [ ] W4: Multiplier display bump animacija tokom FS
- [ ] W4: Mercy mehanika (10 consecutive misses → inject wild)
- [ ] W4: Safety caps (FEATURE_LOOP_CAP, MAX_WIN_CAP)
- [ ] W5: Deferred Big Win overlay posle FS exit (ako fsTotalWin kvalifikuje)
- [ ] W5: Balance crediting UI (animated balance update)

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
- WoO-style Game Flow Wiring (W1-W7): FS auto-spin loop, music crossfade, scene transitions
- 22+ QA rundi, 100+ bugova fixovano, 447 testova
