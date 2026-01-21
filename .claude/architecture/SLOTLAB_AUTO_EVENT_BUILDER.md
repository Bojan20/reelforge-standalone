# SLOT LAB: Drag & Drop → Auto Event Builder (ULTIMATE SPEC)

**Date:** 2026-01-21
**Status:** SPECIFICATION
**Priority:** P0 — Core SlotLab Feature

---

## 0) Cilj

U SlotLab sekciji imaš mockup slot (reels + HUD + dugmad + overlays).
Ti prevučeš zvuk (asset) na element (npr. Spin dugme) i SlotLab automatski:

1. Kreira ili nadogradi Event (FluxForge event model)
2. Kreira Binding (event ↔ target ↔ stage ↔ trigger)
3. Dodeli Bus routing + Preset params + Voice limiting + Cooldown + Variation policy
4. Upisuje sve u manifest i radi odmah preview/audition u mockupu

**Sve ostaje data-driven** (DropRules.json + Presets.json), bez hardcoded if/else u runtime-u.

---

## 1) Core koncepti (objekti koji MORAJU da postoje)

### 1.1 Asset (audio fajl / set fajlova)

Asset Registry mora da zna:

| Field | Type | Description |
|-------|------|-------------|
| `assetId` | String | Unique identifier |
| `path` | String | File path |
| `assetType` | Enum | `SFX` \| `MUSIC` \| `VO` \| `AMB` |
| `tags` | List | npr. `click`, `whoosh`, `impact`, `loop`, `stinger`, `tick`, `reel`, `stop`, `anticipation` |
| `isLoop` | bool | Whether asset loops |
| `durationMs` | int | Duration (or `durationClass`: short/mid/long) |
| `variants` | List | Auto-detection (npr. `spin_click_01..05`) |
| `loudnessInfo` | Object? | Optional, za later |

SlotLab može automatski tagovati asset heuristikom na osnovu imena, foldera i dužine, ali uvek ostaje editabilno.

### 1.2 Target (drop zona na mockupu)

Svaki element na mockupu ima:

| Field | Type | Description |
|-------|------|-------------|
| `targetId` | String | npr. `ui.spin`, `hud.winMeter`, `reel.1`, `symbol.scatter`, `overlay.bigWin` |
| `targetType` | Enum | See below |
| `targetTags` | List | `primary`, `secondary`, `cta`, `reels`, `wins`, `featureIntro`, `bigWin`, `jackpot`, … |
| `stageContext` | Enum | `BaseGame` \| `FreeSpins` \| `Bonus:<id>` \| `Global` |
| `interactionSemantics` | List | Lista triggera koje target podržava |

**Target Types:**
- `ui_button`
- `ui_toggle`
- `hud_counter`
- `hud_meter`
- `reel_surface`
- `reel_stop_zone`
- `symbol`
- `overlay`
- `feature_container`
- `screen_zone` (npr. "bg music zone")

### 1.3 Event (kanonski)

Event je "šta se dešava":

| Field | Type | Description |
|-------|------|-------------|
| `eventId` | String | Unique ID |
| `intent` | String | Standardizovan naziv namere |
| `actions` | List | Najčešće play asset, ali može chain |
| `bus` | String | Bus routing |
| `presetId` | String | Param template |
| `voiceLimitGroup` | String | Voice limiting group |
| `variationPolicy` | Enum | `random` \| `round_robin` \| `shuffle_bag` |
| `tags` | List | Za QA/analytics |

### 1.4 Binding (kontekst)

Binding je "gde i kad se pali":

| Field | Type | Description |
|-------|------|-------------|
| `bindingId` | String | Unique ID |
| `eventId` | String | Reference to Event |
| `targetId` | String | Reference to Target |
| `stageId` | String | Stage context |
| `trigger` | String | Trigger type |
| `paramOverrides` | Object? | Optional overrides |
| `enabled` | bool | Whether active |

**Ključ:** Event se može deliti, ali binding je po stage-u/target-u.

---

## 2) Naming Policy (da nema haosa)

### 2.1 Standard

**eventId format:**
```
{domain}.{targetKey}.{intentKey}
```

**Primeri:**
- `ui.spin.click_primary`
- `ui.turbo.toggle_on`
- `reel.r1.spin_loop`
- `reel.r3.stop`
- `win.countup.tick`
- `overlay.bigwin.tier2`
- `music.base.layer1`
- `feature.fs.intro`

### 2.2 targetKey normalizacija

| targetId | targetKey |
|----------|-----------|
| `ui.spin` | `spin` |
| `reel.1` | `r1` |
| `hud.winMeter` | `winMeter` |
| `overlay.bigWin` | `bigwin` |

---

## 3) Trigger Vocabulary (standardizovano)

### 3.1 UI

| Trigger | Description |
|---------|-------------|
| `press` | Button pressed |
| `release` | Button released |
| `hover` | Mouse hover (desktop) |
| `disabledPress` | Press when disabled |
| `toggleOn` | Toggle switched on |
| `toggleOff` | Toggle switched off |

### 3.2 Gameplay / Reels

| Trigger | Description |
|---------|-------------|
| `onSpinRequest` | Spin requested |
| `onSpinStart` | Spin started |
| `onReelStart(reelIndex)` | Specific reel starts |
| `onReelStop(reelIndex)` | Specific reel stops |
| `onAllReelsStop` | All reels stopped |
| `onAnticipationStart(reelIndex)` | Anticipation begins |
| `onAnticipationEnd(reelIndex)` | Anticipation ends |

### 3.3 Win System

| Trigger | Description |
|---------|-------------|
| `onWinStart` | Win presentation starts |
| `onWinTick` | Win counter tick |
| `onWinEnd` | Win presentation ends |
| `onBigWinTier(tier)` | Big win tier reached |
| `onJackpot(type)` | Jackpot won |

### 3.4 Feature

| Trigger | Description |
|---------|-------------|
| `onStageEnter` | Enter stage |
| `onStageExit` | Exit stage |
| `onFeatureIntro(featureId)` | Feature intro plays |
| `onFeatureStart(featureId)` | Feature gameplay starts |
| `onFeatureEnd(featureId)` | Feature ends |

---

## 4) Bus Map (mix routing)

### Standard Buses

| Bus | Purpose |
|-----|---------|
| `SFX/UI` | UI interactions |
| `SFX/Reels` | Reel sounds |
| `SFX/Symbols` | Symbol sounds |
| `SFX/Wins` | Win sounds |
| `SFX/Features` | Feature sounds |
| `MUSIC/Base` | Base game music |
| `MUSIC/Feature` | Feature music |
| `VO` | Voice over |
| `AMB` | Ambience |
| `MASTER` | Master output |

### Bus Rules

| Drop Target | Bus |
|-------------|-----|
| UI drop | `SFX/UI` |
| Reel drop | `SFX/Reels` |
| Symbol drop | `SFX/Symbols` |
| Win meter/counter | `SFX/Wins` |
| Feature overlay | `SFX/Features` |
| Music zone (base) | `MUSIC/Base` |
| Music zone (feature) | `MUSIC/Feature` |
| VO zone | `VO` |
| Ambience zone | `AMB` |

---

## 5) Preset Library (FULL) — Param Templates

Ovo je "srce" sistema: svako pravilo bira preset.
Sve brojke su default i uvek editabilne.

### 5.1 UI Presets

#### `ui_click_primary`
```json
{
  "polyphony": 2,
  "voiceLimitGroup": "UI_PRIMARY",
  "cooldownMs": 60,
  "priority": 70,
  "pitchRandCents": 10,
  "volRandDb": 0.5,
  "fadeInMs": 0,
  "fadeOutMs": 10,
  "ducking": "none"
}
```

#### `ui_click_secondary`
```json
{
  "polyphony": 2,
  "voiceLimitGroup": "UI_SECONDARY",
  "cooldownMs": 80,
  "priority": 55,
  "pitchRandCents": 8,
  "volRandDb": 0.5
}
```

#### `ui_hover`
```json
{
  "polyphony": 1,
  "voiceLimitGroup": "UI_HOVER",
  "cooldownMs": 120,
  "priority": 40,
  "pitchRandCents": 5,
  "volRandDb": 0.3
}
```

#### `ui_toggle`
```json
{
  "polyphony": 1,
  "voiceLimitGroup": "UI_TOGGLE",
  "cooldownMs": 100,
  "priority": 60
}
```

#### `ui_error`
```json
{
  "polyphony": 1,
  "voiceLimitGroup": "UI_ERROR",
  "cooldownMs": 250,
  "priority": 90,
  "ducking": "small on MUSIC/* for 150ms"
}
```

### 5.2 Reel Presets

#### `reel_spin_start`
```json
{
  "polyphony": 5,
  "voiceLimitGroup": "REEL_START",
  "cooldownMs": 0,
  "priority": 85,
  "pitchRandCents": 5,
  "volRandDb": 0.5
}
```

#### `reel_spin_loop`
```json
{
  "polyphony": 5,
  "voiceLimitGroup": "REEL_LOOP",
  "loop": true,
  "fadeInMs": 30,
  "fadeOutMs": 60,
  "priority": 80,
  "ducking": "none",
  "stopPolicy": "stop on onReelStop(reelIndex) or onAllReelsStop"
}
```

#### `reel_stop`
```json
{
  "polyphony": 5,
  "voiceLimitGroup": "REEL_STOP",
  "cooldownMs": 0,
  "priority": 95,
  "pitchRandCents": 6,
  "volRandDb": 0.4
}
```

#### `anticipation_loop`
```json
{
  "polyphony": 2,
  "voiceLimitGroup": "ANTICIPATION",
  "loop": true,
  "fadeInMs": 40,
  "fadeOutMs": 80,
  "priority": 92,
  "ducking": "light on MUSIC/* while active"
}
```

### 5.3 Symbol Presets

#### `symbol_land_lp`
```json
{
  "polyphony": 4,
  "voiceLimitGroup": "SYMBOL_LP",
  "cooldownMs": 0,
  "priority": 70,
  "pitchRandCents": 7
}
```

#### `symbol_land_hp`
```json
{
  "polyphony": 4,
  "voiceLimitGroup": "SYMBOL_HP",
  "priority": 80,
  "pitchRandCents": 4
}
```

#### `symbol_special`
```json
{
  "polyphony": 2,
  "voiceLimitGroup": "SYMBOL_SPECIAL",
  "priority": 95,
  "cooldownMs": 0
}
```

### 5.4 Win Presets

#### `win_tick`
```json
{
  "polyphony": 1,
  "voiceLimitGroup": "WIN_TICK",
  "cooldownMs": 30,
  "priority": 75,
  "pitchRandCents": 6
}
```

#### `line_win_stinger`
```json
{
  "polyphony": 2,
  "voiceLimitGroup": "WIN_STINGER",
  "priority": 88,
  "cooldownMs": 80
}
```

#### `bigwin_tier1`
```json
{
  "polyphony": 1,
  "voiceLimitGroup": "BIGWIN",
  "priority": 98,
  "ducking": "medium on MUSIC/* for duration",
  "cooldownMs": 0
}
```

#### `bigwin_tier2`
Same as tier1, stronger priority/ducking.

#### `bigwin_tier3`
Same as tier1, strongest priority/ducking.

#### `jackpot`
```json
{
  "polyphony": 1,
  "voiceLimitGroup": "JACKPOT",
  "priority": 100,
  "ducking": "strong on MUSIC/*"
}
```

### 5.5 Feature Presets

#### `feature_intro_stinger`
```json
{
  "polyphony": 1,
  "voiceLimitGroup": "FEATURE_INTRO",
  "priority": 95,
  "cooldownMs": 0
}
```

#### `feature_loop`
```json
{
  "polyphony": 1,
  "voiceLimitGroup": "FEATURE_LOOP",
  "loop": true,
  "fadeInMs": 200,
  "fadeOutMs": 300,
  "priority": 85
}
```

### 5.6 Music Presets

#### `music_layer`
```json
{
  "polyphony": 1,
  "voiceLimitGroup": "MUSIC",
  "loop": true,
  "fadeInMs": 1000,
  "fadeOutMs": 1000,
  "priority": 50,
  "quantizePolicy": "bar",
  "transitionPolicy": "sync_to_bar"
}
```

#### `music_stinger`
```json
{
  "polyphony": 1,
  "voiceLimitGroup": "MUSIC_STINGER",
  "priority": 90,
  "ducking": "light on MUSIC/*"
}
```

---

## 6) Variation Policy

Ako asset ima `variants.length > 1`:
- **default:** `random_container`
- **opcije:** `round_robin`, `shuffle_bag`

Ako user dropuje single asset, ali kasnije doda još:
- SlotLab nudi "Convert to container".

---

## 7) DropRules.json (FULL) — Kompletna pravila

### 7.1 Global Defaults

**defaultTrigger by targetType:**

| targetType | defaultTrigger |
|------------|----------------|
| `ui_button` | `press` |
| `ui_toggle` | `toggleOn` |
| `reel_surface` | `onSpinStart` |
| `reel_stop_zone` | `onReelStop` |
| `hud_counter` | `onWinTick` |
| `hud_meter` | `onWinTick` |
| `overlay` | `onStageEnter` |
| `feature_container` | `onFeatureStart` |
| `screen_zone(bg_music_zone)` | `onStageEnter` |

**defaultDropMode:**

| Target | Mode |
|--------|------|
| UI button | `replace` |
| reels/symbols | `add_layer` |
| win | `replace` (tick) + `add_layer` (stinger) |
| overlay bigwin | `replace` |

### 7.2 Rules (priority order)

#### (A) UI Rules

**Rule: UI_PRIMARY_CLICK** (priority: 1000)
```yaml
when:
  targetType: ui_button
  targetId: contains "spin" OR targetTags includes "primary"
  assetType: SFX
create:
  domain: ui
  intent: click_primary
  bus: SFX/UI
  presetId: ui_click_primary
  trigger: press
  eventId: ui.{targetKey}.click_primary
  variation: auto container if variants > 1
constraints:
  defaultDropMode: replace
  maxBindingsPerStage: 1
```

**Rule: UI_SECONDARY_CLICK** (priority: 950)
```yaml
when:
  targetType: ui_button
  assetType: SFX
create:
  intent: click_secondary
  presetId: ui_click_secondary
  bus: SFX/UI
  trigger: press
  eventId: ui.{targetKey}.click_secondary
```

**Rule: UI_HOVER** (priority: 900)
```yaml
when:
  targetType: ui_button
  assetType: SFX
  assetTags: includes "hover" OR name contains "hover"
create:
  intent: hover
  presetId: ui_hover
  trigger: hover
  eventId: ui.{targetKey}.hover
```

**Rule: UI_TOGGLE** (priority: 890)
```yaml
when:
  targetType: ui_toggle
  assetType: SFX
create:
  intent: toggle
  presetId: ui_toggle
  triggers: [toggleOn, toggleOff]  # QuickSheet asks: On or Off?
  eventId: ui.{targetKey}.toggle_{on|off}
```

**Rule: UI_ERROR** (priority: 880)
```yaml
when:
  targetType: ui_button
  assetType: SFX
  assetTags: includes "error" OR name contains "error"
create:
  intent: error
  presetId: ui_error
  trigger: disabledPress
  eventId: ui.{targetKey}.error
```

#### (B) Reel Rules

**Rule: REEL_SPIN_LOOP** (priority: 820)
```yaml
when:
  targetType: reel_surface
  assetType: SFX
  assetTags: includes "loop" OR isLoop=true OR name contains "loop"
create:
  domain: reel
  intent: spin_loop
  presetId: reel_spin_loop
  bus: SFX/Reels
  trigger: onReelStart
  eventId: reel.{targetKey}.spin_loop
stopBinding:
  trigger: onReelStop
  action: stop same voice/container
```

**Rule: REEL_SPIN_START** (priority: 810)
```yaml
when:
  targetType: reel_surface
  assetType: SFX
  assetTags: includes "start" OR name contains "start"
create:
  intent: spin_start
  presetId: reel_spin_start
  trigger: onReelStart
  eventId: reel.{targetKey}.spin_start
```

**Rule: REEL_STOP** (priority: 800)
```yaml
when:
  targetType: reel_stop_zone OR (targetType=reel_surface AND assetTags includes "stop")
  assetType: SFX
create:
  intent: stop
  presetId: reel_stop
  trigger: onReelStop
  eventId: reel.{targetKey}.stop
```

#### (C) Anticipation Rules

**Rule: ANTICIPATION_LOOP** (priority: 770)
```yaml
when:
  targetType: [reel_surface, overlay, feature_container]
  assetType: SFX
  assetTags: includes "anticipation" OR name contains "anticip"
  isLoop: true OR assetTags includes "loop"
create:
  domain: reel
  intent: anticipation_loop
  presetId: anticipation_loop
  trigger: onAnticipationStart
  eventId: reel.{targetKey}.anticipation_loop
stopBinding:
  trigger: onAnticipationEnd
```

#### (D) Symbol Rules

**Rule: SYMBOL_SPECIAL_SCATTER** (priority: 740)
```yaml
when:
  targetType: symbol
  targetId: contains "scatter"
  assetType: SFX
create:
  domain: symbol
  intent: scatter_hit
  presetId: symbol_special
  bus: SFX/Symbols
  trigger: onSymbolLand
  eventId: symbol.scatter.hit
```

**Rule: SYMBOL_SPECIAL_WILD** (priority: 735)
```yaml
when:
  targetType: symbol
  targetId: contains "wild"
  assetType: SFX
create:
  intent: wild_hit
  presetId: symbol_special
  eventId: symbol.wild.hit
```

**Rule: SYMBOL_HP** (priority: 720)
```yaml
when:
  targetType: symbol
  targetTags: includes "hp" OR assetTags includes "hp"
  assetType: SFX
create:
  intent: hp_hit
  presetId: symbol_land_hp
  eventId: symbol.{targetKey}.hit_hp
```

**Rule: SYMBOL_LP** (priority: 710)
```yaml
when:
  targetType: symbol
  assetType: SFX
create:
  intent: lp_land
  presetId: symbol_land_lp
  eventId: symbol.{targetKey}.land
```

#### (E) Win Rules

**Rule: WIN_TICK** (priority: 690)
```yaml
when:
  targetType: [hud_counter, hud_meter]
  assetType: SFX
  assetTags: includes "tick" OR name contains "tick" OR name contains "count"
create:
  domain: win
  intent: tick
  presetId: win_tick
  bus: SFX/Wins
  trigger: onWinTick
  eventId: win.countup.tick
constraints:
  defaultDropMode: replace
  maxBindingsPerStage: 1
```

**Rule: WIN_STINGER** (priority: 680)
```yaml
when:
  targetType: [hud_counter, hud_meter, overlay]
  assetType: SFX
  assetTags: includes "stinger" OR name contains "stinger" OR name contains "win"
create:
  intent: win_stinger
  presetId: line_win_stinger
  trigger: onWinStart
  eventId: win.stinger
```

#### (F) Big Win Rules

**Rule: BIGWIN_TIER1** (priority: 660)
```yaml
when:
  targetType: overlay
  targetTags: includes "bigWin"
  assetType: [SFX, MUSIC]
  assetTags: includes "tier1" OR name contains "tier1"
create:
  domain: overlay
  intent: bigwin_tier1
  presetId: bigwin_tier1
  trigger: onBigWinTier(1)
  bus: SFX/Wins  # or MUSIC/Feature if music
  eventId: overlay.bigwin.tier1
```

**Rule: BIGWIN_TIER2** (priority: 659) — same pattern, tier2

**Rule: BIGWIN_TIER3** (priority: 658) — same pattern, tier3

#### (G) Jackpot Rules

**Rule: JACKPOT** (priority: 640)
```yaml
when:
  targetType: overlay
  targetTags: includes "jackpot"
  assetType: [SFX, MUSIC]
create:
  domain: overlay
  intent: jackpot
  presetId: jackpot
  trigger: onJackpot(type)  # QuickSheet asks: mini/minor/major/grand
  eventId: overlay.jackpot.{type}
```

#### (H) Feature Rules

**Rule: FEATURE_INTRO** (priority: 620)
```yaml
when:
  targetType: [feature_container, overlay]
  assetType: [SFX, MUSIC]
  assetTags: includes "intro" OR name contains "intro"
create:
  domain: feature
  intent: intro
  presetId: feature_intro_stinger
  trigger: onFeatureIntro(featureId)
  bus: SFX/Features  # or MUSIC/Feature
  eventId: feature.{featureId}.intro
```

**Rule: FEATURE_LOOP** (priority: 610)
```yaml
when:
  targetType: [feature_container, overlay]
  assetType: [SFX, MUSIC]
  isLoop: true OR assetTags includes "loop"
create:
  intent: loop
  presetId: feature_loop  # or music_layer if assetType=MUSIC
  trigger: onFeatureStart(featureId)
  stop: onFeatureEnd(featureId)
  eventId: feature.{featureId}.loop
```

#### (I) Music Rules

**Rule: MUSIC_BASE** (priority: 580)
```yaml
when:
  targetType: screen_zone
  targetTags: includes "bg_music_zone"
  stageContext: BaseGame
  assetType: MUSIC
create:
  domain: music
  intent: base_layer
  presetId: music_layer
  bus: MUSIC/Base
  trigger: onStageEnter
  stop: onStageExit
  eventId: music.base.{layerKey}  # QuickSheet asks layer 1/2/3/4/5
```

**Rule: MUSIC_FEATURE** (priority: 570)
```yaml
when:
  targetType: screen_zone
  targetTags: includes "bg_music_zone"
  stageContext: != BaseGame
  assetType: MUSIC
create:
  intent: feature_layer
  presetId: music_layer
  bus: MUSIC/Feature
  trigger: onStageEnter
  stop: onStageExit
  eventId: music.{stageKey}.{layerKey}
```

#### (J) Fallback Rules

**Rule: FALLBACK_SFX** (priority: 10)
```yaml
when:
  assetType: SFX
create:
  domain: misc
  intent: play
  presetId: ui_click_secondary  # safe default
  bus: SFX/UI
  trigger: defaultTriggerFromTargetType
  eventId: misc.{targetKey}.play
```

**Rule: FALLBACK_MUSIC** (priority: 9)
```yaml
when:
  assetType: MUSIC
create:
  presetId: music_layer
  bus: MUSIC/Base or MUSIC/Feature (by stage)
  trigger: onStageEnter
  stop: onStageExit
  eventId: music.{stageKey}.layer1
```

---

## 8) Quick Sheet UX

Kad dropuješ asset, SlotLab otvara mali panel sa:

| Field | Options |
|-------|---------|
| **Trigger** | Default iz rule-a, ali menjiv |
| **Stage scope** | This stage only / Apply to: Base + FS + Bonus... |
| **Drop mode** | Replace / Add variation / Add layer |
| **Variation policy** | Random / Round robin / Shuffle bag |
| **Bus** | Readonly ili dropdown |
| **Preset** | Dropdown |
| **Create/Apply** | Commit button |

**Nema komplikacija: 1 klik i gotovo.**

---

## 9) Stage Overrides

### 9.1 Pravilo

Event je isti, ali binding ima overrides.

**Primer:** `ui.spin.click_primary` u Base i u FS:
- Base: volume 0dB, pitchRand ±10
- FS: volume +1.5dB (da probije preko FS muzike)

**Rešenje:**
- Event ostaje jedan
- Binding u FS nosi `paramOverrides: { volumeDb: +1.5 }`

---

## 10) Audition / Preview

| Action | Result |
|--------|--------|
| Click target in mockup | Preview svih bindinga za taj stage |
| Ctrl/Cmd + click | Preview "solo" (mute ostalo) |
| Target badge | Broj eventova |

**Inspector prikazuje:**
- Lista bindinga po stage-u
- "Jump to event" dugme
- "Jump to preset" dugme

---

## 11) QA / Validation Layer

### Auto-checks pri kreiranju:

| Rule | Validation |
|------|------------|
| UI click | `cooldown >= 40ms` |
| tick | `polyphony <= 1` |
| music | `voiceLimitGroup = MUSIC (1)` |
| loop | Must have stop trigger defined |
| bus | Must exist |
| stage | Must be valid |
| eventId | Must be unique (or merge policy) |

### Conflict Resolution:

Ako konflikt, SlotLab nudi:
1. **Merge into existing event** (recommended)
2. **Create new with suffix `_v2`** (allowed, ali upozorenje)

---

## 12) Export to Runtime Manifest

Export model mora biti trivijalno čitljiv:

```json
{
  "events": [],
  "bindings": [],
  "presets": [],
  "busMap": [],
  "assets": []
}
```

**Runtime adapter radi:**
> "Kad se desi trigger X na target Y u stage Z → pusti event".

Ništa drugo.

---

## 13) Batch Drop (super moć)

Podržati:
- Drop na `reels_group` → "apply to reels 1–5"
- Drop na `symbols_group_hp` → apply to all HP symbols
- Drop na `stage_zone` → apply to stage layers

---

## 14) Standard Target Map

### Obavezni targeti u SlotLab mockupu:

| targetId | targetType | Tags |
|----------|------------|------|
| `ui.spin` | `ui_button` | `primary` |
| `ui.turbo` | `ui_toggle` | |
| `ui.auto` | `ui_toggle` | |
| `ui.betPlus` | `ui_button` | `secondary` |
| `ui.betMinus` | `ui_button` | `secondary` |
| `reel.1..5` | `reel_surface` | `reels` |
| `reelStop.1..5` | `reel_stop_zone` | |
| `hud.counterBar` | `hud_counter` | |
| `hud.winMeter` | `hud_meter` | |
| `overlay.bigWin` | `overlay` | `bigWin` |
| `overlay.jackpot` | `overlay` | `jackpot` |
| `feature.freeSpins` | `feature_container` | stage FS |
| `screen.baseMusicZone` | `screen_zone` | `bg_music_zone`, stage Base |
| `screen.fsMusicZone` | `screen_zone` | `bg_music_zone`, stage FS |
| `symbol.wild` | `symbol` | `special` |
| `symbol.scatter` | `symbol` | `special` |
| `symbols.hpGroup` | group target | |
| `symbols.lpGroup` | group target | |

---

## 15) Implementation Components

### 15.1 SlotLab UI

- **Drag sources:** Asset Browser
- **Drop targets:** Mockup render elementi
- **Quick Sheet:** Popover form
- **Target Inspector:** Panel za pregled bindinga
- **Event list:** Search/filter
- **Preset editor:** Optional, ali recommended

### 15.2 Generator Module

```dart
Rule matchRule(Target target, Asset asset);
EventBlueprint buildEventBlueprint(Rule rule, Target target, Asset asset, Stage stage);
MergeResult mergePolicy(Event? existing, EventBlueprint newBlueprint);
```

### 15.3 Validation Module

```dart
ValidationResult validate(Event event, Binding binding, Preset preset, BusMap busMap);
List<LintWarning> lint(Manifest manifest);
List<AutoFix> suggestFixes(List<LintWarning> warnings);
```

### 15.4 Export Module

- Deterministic ordering (sort events/bindings by id)
- Stable IDs
- Stable output

---

## 16) Default Decisions (finalne)

| Decision | Value |
|----------|-------|
| UI button drop mode | `replace` |
| Reel/symbol drop mode | `add_layer` |
| Variants | `random_container` |
| Music | `loop` + stage enter/exit |
| Tick | `polyphony 1` + `cooldown 30ms` |
| Bigwin/jackpot | `voiceLimitGroup 1` |
| All loops | Must have stop trigger (mandatory) |
| Stage overrides | Go in binding (mandatory design) |

---

## 17) Command Builder (Pro Workflow)

### Drop = "Create Draft", ne "Commit"

Kad dropuješ asset na bilo koji stage/target, SlotLab uradi samo ovo:
1. Napravi **Draft** (privremeni objekat)
2. Popuni ga heuristikom (predlog), ali ništa ne upisuje u manifest
3. Otvori centralni panel: **Command Builder (Draft)**
4. Ti klikneš **Commit** kad si zadovoljan

### Command Builder Blocks

#### A) Context Block (zaključan iz dropa)
- Stage: BaseGame / FS / Bonus / Overlay:BigWin…
- Target: ui.spin / reel.3 / overlay.bigWin…
- Trigger: default predložen, ali menjiv
- Asset: koji si dropovao

#### B) Action Block (ti biraš šta se generiše)

**Dropdown: Create…**
- ✅ Event + Binding
- ✅ Command line only (komanda u timeline/graph, bez novog eventa)
- ✅ Add as Variation
- ✅ Add as Layer
- ✅ Create Loop pair (Start/Stop)
- ✅ Create Takeover Music (Enter/Exit)
- ✅ Create Stinger + Duck
- ✅ Map to Existing Event (ne pravi novo, nego bind)

#### C) Parameters Block (svi FluxForge parametri)

- bus
- preset
- volume, pitch rand
- polyphony
- voice limit group
- cooldown/retrigger
- fade in/out
- ducking sends/receives
- priority
- quantize/sync (muzika)
- stop behavior (ako loop)
- stage overrides

#### D) Preview Block

- Audition this draft
- Simulate trigger
- Show voice meter / bus meter

#### E) Commit / Cancel

- **Commit** (upis u manifest)
- **Cancel** (baci draft)

### Command Templates

Templates popunjavaju formu (data-driven):

| Template | Auto-fills |
|----------|------------|
| UI Click (primary/secondary) | trigger: press, bus: SFX/UI, preset: ui_click_* |
| Reel Start / Reel Stop | trigger: onReelStart/Stop, bus: SFX/Reels |
| Anticipation Loop start/stop | loop: true, stop trigger |
| Win Tick | polyphony: 1, cooldown: 30ms |
| BigWin Tier takeover music | ducking, priority |
| Feature Intro stinger | priority: 95 |
| Base music bed | loop: true, stage enter/exit |
| Overlay takeover | crossfade/pause/stop under |

Templates dolaze iz `CommandTemplates.json`.

### Command Line Display

Drop generiše jednu liniju koja se vidi/edituje:

```
ON press(ui.spin) -> PLAY sfx(ui_spin_click) VIA SFX/UI PRESET ui_click_primary
ON overlayEnter(BigWin) -> TAKEOVER music(bigwin_loop) MODE crossfade_under
ON stageEnter(BaseGame) -> START bed(music_base_L1) LOOP
```

### Two Modes

| Mode | Behavior |
|------|----------|
| **Fast Commit** | Drop → mini quick sheet (2–3 opcije) → Commit |
| **Pro Draft** | Drop → otvara central Command Builder |

Setting: `Default drop behavior: Fast | Pro`

---

## 18) Core Objects

```dart
class DraftCommand {
  String id;
  Target target;
  Asset asset;
  Stage stage;
  String trigger;
  CommandTemplate template;
  Map<String, dynamic> params;
  bool committed;
}

class CommandTemplate {
  String id;
  String name;
  String actionType;  // event+binding, loop_pair, takeover, etc.
  Map<String, dynamic> defaults;
}

class RuleMatch {
  Rule rule;
  int priority;
  CommandTemplate suggestedTemplate;
}

class CommitEngine {
  Event? createEvent(DraftCommand draft);
  Binding? createBinding(DraftCommand draft, Event event);
  void applyToManifest(Event event, Binding binding);
}
```

---

## Summary

> **Drop uvek pravi Draft u centralnom Command Builderu, sa predloženim template-om, a ti biraš šta se generiše (event/binding/command/loop/takeover) i tek onda Commit.**

To je najčistije, najprofesionalnije i 100% uklanja hardcoding.

---

**Last Updated:** 2026-01-21
