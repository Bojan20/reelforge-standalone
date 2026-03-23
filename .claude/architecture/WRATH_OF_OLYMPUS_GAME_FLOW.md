# Wrath of Olympus — Kompletni Game Flow

**Izvor:** `/Volumes/Bojan - T7/DevVault/Projects/Wrath Of Olympus/`
**Stack:** TS strict, Vite, PixiJS, GSAP, Canvas 2D
**Grid:** 5x3, 10 paylines, Zeus tema
**Features:** Free Spins + Hold & Win + Lightning Multiplier
**Math:** v11.27, 96.009% RTP, 4B validated

---

## Simboli

| Tip | Simboli |
|-----|---------|
| High Pay | Zeus (Z), Hades (H), Poseidon (P) |
| Mid Pay | Helm (HM), Shield (SH), Sword (SW) |
| Low Pay | Lyre (LA), Gold (GM), Amphora (AM), Laurel (LR), Vase (VA) |
| Special | Wild (W), Scatter (S), Bonus Orb (B) |

---

## State Machine

```
BASE ──(spin)──► [SPINNING]
  [SPINNING] ──(all reels stop)──► [EVALUATE + PRESENT WINS]
    [PRESENT WINS] ──(no feature)──► BASE
    [PRESENT WINS] ──(3+ scatters)──► [SCATTER HIGHLIGHT 2s] ──► FS_INTRO
    [PRESENT WINS] ──(6+ bonus orbs)──► [ORB HIGHLIGHT 2.5s] ──► HNW_INTRO

FS_INTRO ──(epic cinematic + plaque)──► FS_RUNNING
FS_RUNNING ──(auto-spin loop)──► FS_RUNNING
FS_RUNNING ──(3+ scatters retrigger)──► FS_RUNNING (+spins)
FS_RUNNING ──(fsRemaining == 0)──► FS_SUMMARY
FS_SUMMARY ──(plaque + outro + optional Big Win)──► BASE

HNW_INTRO ──(orb highlight + transition)──► HNW_RUNNING
HNW_RUNNING ──(respin loop)──► HNW_RUNNING
HNW_RUNNING ──(respins == 0 ili grid full)──► HNW_SUMMARY
HNW_SUMMARY ──(summary + optional Big Win)──► BASE
```

---

## FAZA A: IDLE → SPIN START

### Preduslovi
- `spinning === false`
- `activeMode === 'base'`
- Nema otvorenih modala (`UIStateManager.canSpin()`)
- `balance >= totalBet`
- `featureTriggerAnimating === false`

### Akcije na spin start
1. `spinAbortToken++` (invalidira prethodne async flowove)
2. `winCredited = false`
3. Balans oduzet: `balance -= totalBet`
4. `totalWin = 0`, UI pushed
5. Status bar: `"GOOD LUCK!"`
6. Spin button → STOP ikona
7. Haptic feedback: "light"
8. Spin hints sakriveni

### RNG / Grid generisanje
- Seed iz `currentSeed`, inkrementiran posle upotrebe
- RNG: `mulberry32(seed)`
- Grid: `generateStops(rng)` → `gridFromStops(stops)` (weight-based, 100 total per reel)
- Opciono: forced debug grid ako je `forceNextGrid` setovan

### Pre-kalkulacija
- `evaluateSpin()` odmah — rezultat čuvan u `pendingSpinResult` za slam stop
- Zeus meter proveren za guaranteed lightning (`forceLightning`)
- Storm multiplier reel počinje da se vrti

---

## FAZA B: REEL SPINNING

### Timing profili

| Parametar | Normal | Turbo | Slam |
|-----------|--------|-------|------|
| accelMs | 130 | 70 | 0 |
| steadyMs | 1350 | 450 | 0 |
| decelMs | 300 | 120 | 100 |
| staggerMs | 180 | 45 | 30 |
| bouncePx | 6 | 3 | 0 |
| windupPx | 42 | 18 | 0 |
| windupFrames | 7 (~115ms) | 4 (~65ms) | 0 |
| bounceDecay | 0.3 | 0.2 | 0 |
| bounceCount | 2 | 1 | 0 |

### Animacione faze
1. **Windup** — reelovi se povuku naviše za `windupPx` tokom `windupFrames` frameova
2. **Akceleracija** — `accelMs` trajanje
3. **Steady spin** — `steadyMs` na `speedMul` brzini
4. **Base wait** — `1200ms` pre nego što stopiranje počne

---

## FAZA C: REEL STOP SEKVENCA (1-5, sa anticipacijom)

Posle 1200ms base wait-a, reelovi staju sekvencijalno levo → desno.

### Per-reel stop
1. Proveri abort token (bail ako slam-stopped)
2. Proveri anticipaciju (`shouldAnticipate(grid, r)`)
3. `renderer.stopReel(r, reelSyms)` — deceleration + bounce animacija
4. Stagger delay pre sledećeg reela

### Anticipacija
- **Samo reelovi 2-4** (indeksi 2, 3, 4) mogu imati anticipaciju
- Proverava SAMO ZAUSTAVLJENE reelove (progresivno otkrivanje)
- **Scatter anticipacija**: 2+ scattera vidljivo na stoppiranim reelovima (treba 3 za FS)
- **Bonus anticipacija**: 5+ bonus orbova vidljivo (treba 6 za HNW)

### Anticipacija timing

| Parametar | Normal | Turbo |
|-----------|--------|-------|
| SPIN_DURATION | 2000ms | 800ms |
| PROGRESSIVE_STEP | +500ms/reel | +200ms/reel |

Kad anticipacija triggera:
- `renderer.startAnticipation(type)` — vizuelni efekat
- Svaki anticipirajući reel se vrti `SPIN_DURATION + (reelCount × PROGRESSIVE_STEP)` pre zaustavljanja
- Posle anticipation stop-a: 100ms delay (umesto normalnog staggera)
- Na kraju: `renderer.stopAnticipation()`

### Posle svih stopova
- Storm multiplier reel staje:
  - Ako lightning triggered: `stopStormMultiplierSpin(value)` + proslava
  - Ako win ali nema lightning (15% šansa): `stopStormMultiplierMiss()` (near-miss)
  - Inače: `stopStormMultiplierNeutral()` (čist AAA stop)
- Zeus meter se puni na win-ovima (samo base game)

---

## FAZA D: WIN EVALUACIJA + PREZENTACIJA

### Win klasifikacija

| Tier | Uslov |
|------|-------|
| `none` | win <= 0 |
| `small` | 0 < multiplier < 1× bet |
| `medium` | 1× <= multiplier < 10× bet |
| `big` | multiplier >= 10× bet |

### Prezentacija (PresentationOrchestrator)

Orchestrator gradi red čekanja sortiran po prioritetu.

#### NON-BIG WIN (small/medium)
| Korak | Event | Prioritet | Trajanje |
|-------|-------|-----------|----------|
| 1 | WIN_PRESHOW | 110 | small: 400ms, medium: 600ms |
| 2 | TOTAL_ROLLUP | 100 | 300-400ms |
| 3 | LIGHTNING_ZAP | 90 | 400-800ms (ako triggered) |
| 4 | LINE_HIGHLIGHT | 80 | lineMs × lineCount |
| 5 | FEATURE_SIGNAL | 50 | 0ms (triggeruje FS/HNW) |
| 6 | CLEANUP | 10 | 0ms |

#### BIG WIN (>=10×)
| Korak | Event | Prioritet | Trajanje |
|-------|-------|-----------|----------|
| 1 | SYMBOL_CELEBRATION | 100 | 800ms |
| 2 | LIGHTNING_ZAP | 95 | 400-800ms (ako triggered) |
| 3 | BIG_WIN | 90 | BigWinOverlayController |
| 4 | LINE_HIGHLIGHT | 55 | lineMs × lineCount |
| 5 | FEATURE_SIGNAL | 50 | 0ms |
| 6 | CLEANUP | 10 | 0ms |

### Event detalji
- **WIN_PRESHOW**: Flash/pulse winning symbols
- **TOTAL_ROLLUP**: Status bar counter animira od 0 do win amount (300-400ms). Win trail particles.
- **LIGHTNING_ZAP**: Zeus lightning udara winning cells. Counter "eksplodira" od base do multiplied value.
- **LINE_HIGHLIGHT**: Svaka winning linija jedna po jedna. Highlights winning cells, dims ostale.
- **SYMBOL_CELEBRATION**: Winning simboli animiraju pre Big Win overlay-a
- **FEATURE_SIGNAL**: PROTECTED — pali se čak i na abort (FS/HNW uvek triggeruje)

### Highlight stilovi po win multiplier-u
- `win-small`: < 1.5× bet
- `win-medium`: 1.5-5× bet
- `win-big`: 5-25× bet
- `win-mega`: 25×+ bet

### Balance crediting (base game)
- GSAP rollup animacija: 0.7s normal, 0.4s turbo
- Balance display dobija "balance-updating" glow klasu

---

## FAZA E: SCATTER WIN (3+ scattera = FS trigger)

### Detekcija
`countScatters(grid)` broji "S" simbole na svih 15 pozicija.

### Nagrade

| Scattera | Free Spins |
|----------|-----------|
| 3 | 14 |
| 4 | 16 |
| 5 | 18 |

+ Dodatni credit payout baziran na scatter count (`SCATTER_PAYS × totalBet`)

### Flow posle svih reel stopova
1. Win prezentacija se završi PRVA (ako ima line win-ova) — Big Win kompletira pre FS
2. `featureTriggerAnimating = true` (blokira nove spinove i skip)
3. `renderer.highlightScatters(grid)` — scatter simboli highlighted sa golden glow
4. **2000ms dramatična pauza** — igrač vidi scattere
5. `renderer.clearHighlights()`
6. Poziva `triggerFreeSpins(scatterCount, scatterPositions, result, grid)`

---

## FAZA F: FREE SPINS TRANSITION IN (Base Game → FS)

### State inicijalizacija
- Zeus meter reset i sakriven
- `activeMode = 'fs'` (blokira base spinove)
- Bet zaključan: `fsBetAmount = totalBet`
- `fsTotal/fsRemaining = awarded`, `fsTotalWin = 0`, `fsCurrentMult = 1`
- Trigger result + grid sačuvani za kasniju restauraciju
- `gameState = FS_INTRO`

### Vizuelna tranzicija — Epic Intro
- Animirani storm background sa nebula oblacima
- Zeus lightning udara svaku scatter poziciju
- Animirani "WRATH OF OLYMPUS" naslov sa golden glow
- Particle sistemi (sparks, embers, energy orbs)
- Camera shake + zoom efekti
- Glowing FREE SPINS plaque sa grčkim ornamentima — prikazuje broj spinova

### Grid reset
- Svež FS grid generisan sa `FS_WEIGHTS` (boosted wilds, BEZ bonus orbova, redukovani scatteri)

### Atmosfera
- Base ambient lightning disabled
- FS ambient lightning started (spawns beside/above reels)
- FS atmosphere shown (dark overlay + realistic fire efekti)

### Running state
- `gameState = FS_RUNNING`
- FS counter prikazan (3 panela: SPINS current/total, MULTIPLIER, TOTAL WIN)
- Igrač može kliknuti da počne ili auto-start posle **2000ms**

---

## FAZA G: FREE SPINS GAMEPLAY

### FS Reel Weights vs Base Game
- Wilds: 8-12% (vs 6-8% base) — boosted
- Bonus Orbs: 0% — HNW ne može da se triggeruje tokom FS
- Scatteri: 2-3% — redukovani ali retrigger moguć
- Low pay: povećan da popuni bonus orb void

### Progresivni Multiplier
- Startuje na 1×
- **+1× na svakom WINNING spinu** (ne per linija, nego per spin)
- Maksimum: 10×
- Display update sa bump animacijom

### Mercy Mehanika
- Posle 10 uzastopnih non-winning spinova: Wild injektovan na center pozicije
- Prioritet: center-center (reel 3, row 1) > reel 2 center > reel 4 center
- Resetuje se na bilo koji win

### Pojedinačni FS Spin (`executeFSSpin`)
1. Update FS counter display
2. Grid generisan sa `FS_WEIGHTS`
3. Mercy wild injection ako treba
4. `evaluateSpin()` sa `isFreeSpin: true` (+30% lightning frekvencija)
5. `setSpinningState(true)`
6. Status bar: `"FREE SPIN X / Y"`
7. `renderer.startSpin(sessionId)`
8. Wait 1200ms
9. Stop reelove jedan po jedan sa stagger delay-om
10. **Nema storm multiplier-a** u FS (koristi progresivni multiplier)

### Win Processing u FS
- Ako `baseWin > 0`:
  - `multipliedWin = baseWin × fsCurrentMult`
  - Reelframe dobija `is-win` klasu (400ms glow)
  - Ako multiplier > 1: popup prikazuje `"baseWin × Nx = multipliedWin"`
  - `fsCurrentMult++` (ako < 10)
  - Multiplier display updated sa bump animacijom
  - Win prezentacija se pokrene
  - `fsTotalWin += multipliedWin`

### Retrigger
- Posle svakog spina: proveri `countScatters(grid)`
- Ako 3+ scattera:
  - Dodatni spinovi: ista tabela (14/16/18)
  - Scatter pay primenjeni sa trenutnim progresivnim multiplier-om
  - "RETRIGGER!" overlay prikazan 2000ms (skippable)

### Loop timing
- Između spinova: 500ms normal, 250ms turbo
- Posle poslednjeg spina: 800ms normal, 400ms turbo

### Safety caps
- `FEATURE_LOOP_CAP`: Maksimalne iteracije pre forsiranog kraja
- `MAX_WIN_CAP × totalBet`: Ako total win dosegne cap, FS se odmah završava

---

## FAZA H: FREE SPINS TRANSITION OUT (FS → Base Game)

### Korak 1: Outro Plaque
- "FREE SPINS COMPLETE" plaque sa blur pozadinom
- Prikazuje total win vrednost
- Backdrop ostaje za seamless transition

### Korak 2: Outro Transition
- FS atmosphere sakrivena (dark overlay + fire efekti uklonjeni)
- FS ambient lightning stopiran
- Base ambient lightning ponovo uključen (interval: 8-12s)
- Transition sekvenca:
  1. UI overlay + gameMount fade out (0.3s)
  2. Standalone lightning animacija
  3. Trigger grid restauriran na renderer (base game simboli se pojave)
  4. UI overlay + gameMount fade in (0.3s) — osim ako Big Win dolazi

### Korak 3: Big Win (ako fsTotalWin kvalifikuje)
- Heavy haptic feedback
- `bigWin.show(fsTotalWin, fsBetAmount)`
- Posle Big Win-a: FS klase uklonjene, UI fade in (0.6s)

### Korak 4: Finalize
- `activeMode = 'base'` (unlock base spinove)
- Zeus meter ponovo prikazan
- `gameState = BASE`
- Sav FS state resetovan

### Win crediting
- Total = `fsTotalWin + triggerResult.finalWin` (trigger spin wins deferred)
- Ako nema Big Win: status bar rollup (300-400ms) + balance rollup (0.9s normal, 0.5s turbo)

---

## FAZA I: BIG WIN PREZENTACIJA

### Trigger
`winAmount / betAmount >= 10`

### Tierovi

| Tier | Threshold | Label | Efekti |
|------|-----------|-------|--------|
| 1 | >= 10× | BIG WIN | 3D coin shower, screen shake (6, 300ms) |
| 2 | >= 25× | MEGA WIN | shockwave + particles + shake (12, 400ms) |
| 3 | >= 50× | EPIC WIN | full celebration + confetti + shake (20, 600ms) |

### Faze

#### PREP (500ms)
- Overlay prikazan sa entrance shimmer (1.5s)
- AAA shockwave entrance + golden rays burst
- **Nema skip** — skip requestovi se čiste

#### ROLLUP (4s po tier-u)
- 1 tier (BIG): 4s
- 2 tiera (MEGA): 8s
- 3 tiera (EPIC): 12s
- Counter rolls linearly od 0 do finalne vrednosti
- Tier upgrades na ravnomernim intervalima

Per-tier transition:
- Background image + title text promena sa animacijom
- Tier 2+: shockwave burst, particle efekti
- Screen shake sinhronizovan (PIXI + DOM)
- Zeus character reakcija
- 3D coin shower intenzitet ažuriran

**Skip**: klik/Space → skoči na END fazu odmah

#### END (7s)
- Value celebration animacija
- Tier 3: epic confetti cannons
- Tier 2: confetti burst + gold sparkles
- Coin shower drain (4.5s delay, 6s drain + 1s buffer = 7s)
- Skip tokom END: zatvori odmah

#### EXIT
- Smooth transition: UI restored PRE fade-out
- Overlay fade-out: 750ms (skip: 300ms)
- Cleanup: kill svi GSAP tweeni, release input lock, clear particles

---

## KOMPLETNA TIMING REFERENCA

### Base Spin

| Faza | Normal | Turbo |
|------|--------|-------|
| Spin base wait | 1200ms | 1200ms |
| Reel stagger | 180ms | 45ms |
| Slam stagger | 30ms | 30ms |
| Windup | ~115ms | ~65ms |
| Bounce | 2×, 0.3 decay | 1×, 0.2 decay |

### Anticipacija

| | Normal | Turbo |
|---|--------|-------|
| Base duration | 2000ms | 800ms |
| Progressive step | +500ms/reel | +200ms/reel |
| Post-stop delay | 100ms | 100ms |

### Win Prezentacija

| Event | Small | Medium | Big |
|-------|-------|--------|-----|
| Win preshow | 400ms | 600ms | 800ms |
| Rollup | 300-400ms | 300-400ms | 300-400ms |
| Lightning zap | 400-800ms | 400-800ms | 400-800ms |
| Line highlight | 500ms/line | 600ms/line | 600ms/line |

### Free Spins

| Faza | Trajanje |
|------|----------|
| Scatter highlight pauza | 2000ms |
| Epic intro | Nekoliko sekundi (cinematic) |
| UI fade out/in | 300ms / 600ms |
| Wait for start | 2000ms auto-start |
| Između spinova | 500ms (turbo: 250ms) |
| Posle poslednjeg spina | 800ms (turbo: 400ms) |
| Multiplier popup | 1500ms + 400ms fade |
| Retrigger overlay | 2000ms + 400ms fade |

### Big Win

| Faza | Trajanje |
|------|----------|
| Prep | 500ms |
| Per tier rollup | 4000ms |
| End hold | 6000ms + 1000ms |
| Overlay fade-out | 750ms (skip: 300ms) |
| Entrance shimmer | ~1500ms |

### FS Outro

| Korak | Trajanje |
|-------|----------|
| UI fade out | 300ms |
| Outro lightning | Variable |
| UI fade in (bez BW) | 300ms |
| FS → base crossfade | 600ms |
| Status bar rollup | 300-400ms |
| Balance rollup | 900ms (turbo: 500ms) |

---

## MAPIRANJE NA FLUXFORGE SLOTLAB STAGES

| WoO Faza | FluxForge Stage | Bus | Loop | Notes |
|----------|----------------|-----|------|-------|
| Spin start | SPIN_START | SFX | No | Haptic + button visual |
| Reel spinning | REEL_SPIN_LOOP | SFX | Yes | Per-reel ili single loop |
| Reel stop 1-5 | REEL_STOP_0..4 | SFX | No | Panned L→R |
| Anticipation on | ANTICIPATION_ON | SFX | Yes | Tension buildup |
| Anticipation off | ANTICIPATION_OFF | SFX | No | Resolution |
| Win preshow | WIN_PRESENT | SFX | No | Flash/pulse |
| Win rollup | ROLLUP_START/TICK/END | SFX | Yes/No | Counter animation |
| Lightning zap | LIGHTNING_ZAP | SFX | No | Zeus strike |
| Line highlight | WIN_LINE_SHOW | SFX | No | Per-line |
| Scatter land | SCATTER_LAND | SFX | No | Golden glow |
| FS trigger | FEATURE_ENTER | SFX | No | Epic transition |
| FS music | MUSIC_FS_L1..L5 | Music | Yes | Layered music |
| FS spin | Same as base | SFX | — | Same stages |
| FS multiplier up | MULTIPLIER_INCREASE | SFX | No | Bump animation |
| FS retrigger | FREESPIN_RETRIGGER | SFX | No | +spins overlay |
| FS exit | FEATURE_EXIT | SFX | No | Outro transition |
| Base music | MUSIC_BASE_L1..L5 | Music | Yes | Layered music |
| Big Win start | BIG_WIN_START | Music | Yes | Replaces base music |
| Big Win tier 1-3 | BIG_WIN_TIER1..3 | SFX | No | Shockwave + celebration |
| Big Win rollup | BIG_WIN_TICK_START | SFX | Yes | Counter rolling |
| Big Win end | BIG_WIN_END | SFX | No | Stops big win music |
| Coin shower | COIN_SHOWER_START/END | SFX | No | 3D coins |
| Idle ambient | IDLE_START | SFX | Yes | Background atmosphere |
| Button click | UI_BUTTON | UI | No | Menu interactions |
