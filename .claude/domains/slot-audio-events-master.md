# Slot Audio Events - Master Catalog

**Version:** 1.0
**Last Updated:** 2026-01-20
**Total Events:** 350+

Kompletna lista svih audio eventa koji mogu da se dese u slot igri.
Organizovano po kategorijama sa prioritetom, trajanjem i opisom.

---

## Event Naming Convention

```
CATEGORY_ACTION_DETAIL
```

Primeri:
- `REEL_STOP_0` — Reel 0 se zaustavio
- `WIN_TIER_MEGA` — Mega win nivo
- `FS_RETRIGGER_3` — Free spins retrigger sa 3 scattera

---

## 1. UI EVENTS (25 events)

Interakcija sa interfejsom. Najniži prioritet.

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `UI_BUTTON_PRESS` | LOW | 20-50ms | Generic button click |
| `UI_BUTTON_HOVER` | LOW | 10-30ms | Mouse hover over button |
| `UI_BUTTON_DISABLED` | LOW | 30ms | Click on disabled button |
| `UI_SPIN_BUTTON` | MEDIUM | 100-150ms | Main spin button press |
| `UI_SPIN_BUTTON_HOLD` | MEDIUM | Loop | Holding spin for turbo |
| `UI_BET_UP` | LOW | 50ms | Increase bet |
| `UI_BET_DOWN` | LOW | 50ms | Decrease bet |
| `UI_BET_MAX` | LOW | 100ms | Max bet button |
| `UI_BET_CHANGE_LOOP` | LOW | Loop | Rapid bet change |
| `UI_AUTOPLAY_START` | LOW | 150ms | Autoplay activated |
| `UI_AUTOPLAY_STOP` | LOW | 150ms | Autoplay deactivated |
| `UI_AUTOPLAY_SPIN` | LOW | 50ms | Each autoplay spin |
| `UI_MENU_OPEN` | LOW | 200ms | Menu/settings open |
| `UI_MENU_CLOSE` | LOW | 150ms | Menu/settings close |
| `UI_TAB_SWITCH` | LOW | 50ms | Tab navigation |
| `UI_PAYTABLE_OPEN` | LOW | 200ms | Paytable opened |
| `UI_PAYTABLE_CLOSE` | LOW | 150ms | Paytable closed |
| `UI_PAYTABLE_PAGE` | LOW | 100ms | Paytable page turn |
| `UI_SETTINGS_CHANGE` | LOW | 100ms | Settings toggle |
| `UI_VOLUME_CHANGE` | LOW | 50ms | Volume slider |
| `UI_MUTE_ON` | LOW | 50ms | Sound muted |
| `UI_MUTE_OFF` | LOW | 50ms | Sound unmuted |
| `UI_ERROR` | MEDIUM | 200ms | Error/invalid action |
| `UI_SUCCESS` | LOW | 150ms | Successful action |
| `UI_NOTIFICATION` | LOW | 300ms | System notification |

---

## 2. SPIN EVENTS (20 events)

Pokretanje i osnovna spin mehanika.

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `SPIN_START` | HIGH | 100-200ms | Spin initiated |
| `SPIN_BUTTON_PRESS` | HIGH | 50ms | Physical button feedback |
| `SPIN_ANTICIPATION` | MEDIUM | Variable | Pre-spin buildup |
| `SPIN_TURBO_START` | HIGH | 50ms | Turbo mode spin |
| `SPIN_QUICK_STOP` | MEDIUM | 100ms | Quick stop triggered |
| `SPIN_AUTO_START` | MEDIUM | 100ms | Autoplay spin start |
| `SPIN_INSUFFICIENT_FUNDS` | MEDIUM | 200ms | Not enough balance |
| `SPIN_BET_CONFIRM` | LOW | 50ms | Bet locked for spin |

### Reel Spin Sounds

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `REEL_SPIN_START` | HIGH | 200ms | All reels begin spinning |
| `REEL_SPIN_LOOP` | MEDIUM | Loop | Continuous spin sound |
| `REEL_SPIN_LOOP_0` | MEDIUM | Loop | Reel 0 specific spin |
| `REEL_SPIN_LOOP_1` | MEDIUM | Loop | Reel 1 specific spin |
| `REEL_SPIN_LOOP_2` | MEDIUM | Loop | Reel 2 specific spin |
| `REEL_SPIN_LOOP_3` | MEDIUM | Loop | Reel 3 specific spin |
| `REEL_SPIN_LOOP_4` | MEDIUM | Loop | Reel 4 specific spin |
| `REEL_SPIN_LOOP_5` | MEDIUM | Loop | Reel 5 specific spin (6-reel) |
| `REEL_SPIN_ACCELERATE` | MEDIUM | 200ms | Reels speeding up |
| `REEL_SPIN_DECELERATE` | MEDIUM | 300ms | Reels slowing down |
| `REEL_SPIN_TURBO` | MEDIUM | Loop | Turbo spin sound |

---

## 3. REEL STOP EVENTS (35 events)

Zaustavljanje rilova — kritično za timing.

### Standard Reel Stops

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `REEL_STOP` | HIGH | 50-100ms | Generic reel stop |
| `REEL_STOP_0` | HIGH | 50-100ms | Reel 0 stops |
| `REEL_STOP_1` | HIGH | 50-100ms | Reel 1 stops |
| `REEL_STOP_2` | HIGH | 50-100ms | Reel 2 stops |
| `REEL_STOP_3` | HIGH | 50-100ms | Reel 3 stops |
| `REEL_STOP_4` | HIGH | 50-100ms | Reel 4 stops |
| `REEL_STOP_5` | HIGH | 50-100ms | Reel 5 stops (6-reel) |
| `REEL_STOP_FINAL` | HIGH | 100ms | Last reel stops |
| `REEL_SLAM` | HIGH | 150ms | Heavy slam stop |
| `REEL_SLAM_0` | HIGH | 150ms | Reel 0 slam |
| `REEL_SLAM_1` | HIGH | 150ms | Reel 1 slam |
| `REEL_SLAM_2` | HIGH | 150ms | Reel 2 slam |
| `REEL_SLAM_3` | HIGH | 150ms | Reel 3 slam |
| `REEL_SLAM_4` | HIGH | 150ms | Reel 4 slam |

### Enhanced Reel Stops

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `REEL_STOP_SOFT` | MEDIUM | 30ms | Soft/quiet stop |
| `REEL_STOP_HEAVY` | HIGH | 100ms | Heavy impact stop |
| `REEL_STOP_BOUNCE` | MEDIUM | 150ms | Stop with bounce |
| `REEL_STOP_TICK` | LOW | 20ms | Click/tick stop |
| `REEL_QUICK_STOP` | MEDIUM | 30ms | Turbo mode stop |
| `REEL_ALL_STOP` | HIGH | 100ms | All reels stop together |

### Reel Modifiers

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `REEL_NUDGE` | MEDIUM | 100ms | Reel nudges one position |
| `REEL_NUDGE_UP` | MEDIUM | 100ms | Nudge upward |
| `REEL_NUDGE_DOWN` | MEDIUM | 100ms | Nudge downward |
| `REEL_RESPIN` | MEDIUM | 200ms | Single reel respin |
| `REEL_RESPIN_START` | MEDIUM | 150ms | Respin begins |
| `REEL_RESPIN_STOP` | MEDIUM | 100ms | Respin ends |
| `REEL_EXPAND` | HIGH | 300ms | Reel expands (more rows) |
| `REEL_SYNC` | MEDIUM | 200ms | Reels synchronize |
| `REEL_SYNC_LOCK` | MEDIUM | 150ms | Sync lock sound |

---

## 4. SYMBOL EVENTS (50 events)

Eventi vezani za simbole.

### Symbol Landing

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `SYMBOL_LAND` | LOW | 30ms | Generic symbol lands |
| `SYMBOL_LAND_LOW` | LOW | 20ms | Low-pay symbol lands |
| `SYMBOL_LAND_MID` | LOW | 30ms | Mid-pay symbol lands |
| `SYMBOL_LAND_HIGH` | MEDIUM | 50ms | High-pay symbol lands |
| `SYMBOL_LAND_PREMIUM` | MEDIUM | 80ms | Premium symbol lands |

### Wild Symbols

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `WILD_LAND` | HIGH | 200-400ms | Wild symbol lands |
| `WILD_LAND_0` | HIGH | 200ms | Wild on reel 0 |
| `WILD_LAND_1` | HIGH | 200ms | Wild on reel 1 |
| `WILD_LAND_2` | HIGH | 200ms | Wild on reel 2 |
| `WILD_LAND_3` | HIGH | 200ms | Wild on reel 3 |
| `WILD_LAND_4` | HIGH | 200ms | Wild on reel 4 |
| `WILD_EXPAND` | HIGH | 300-700ms | Wild expands to cover reel |
| `WILD_EXPAND_START` | HIGH | 200ms | Expansion begins |
| `WILD_EXPAND_COMPLETE` | HIGH | 200ms | Expansion complete |
| `WILD_STICK` | MEDIUM | 150ms | Wild becomes sticky |
| `WILD_STICK_LOCK` | MEDIUM | 100ms | Sticky lock sound |
| `WILD_WALK` | MEDIUM | 200ms | Walking wild moves |
| `WILD_WALK_LEFT` | MEDIUM | 200ms | Wild walks left |
| `WILD_WALK_RIGHT` | MEDIUM | 200ms | Wild walks right |
| `WILD_MULTIPLY` | HIGH | 300ms | Multiplier wild activates |
| `WILD_MULTIPLY_2X` | HIGH | 300ms | 2x multiplier wild |
| `WILD_MULTIPLY_3X` | HIGH | 400ms | 3x multiplier wild |
| `WILD_MULTIPLY_5X` | HIGH | 500ms | 5x multiplier wild |
| `WILD_TRANSFORM` | HIGH | 400ms | Symbol transforms to wild |
| `WILD_COLOSSAL` | HIGH | 500ms | Large wild (2x2, 3x3) lands |
| `WILD_STACK` | HIGH | 300ms | Stacked wild lands |
| `WILD_STACK_FULL` | HIGH | 500ms | Full reel of wilds |

### Scatter Symbols

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `SCATTER_LAND` | HIGH | 200-500ms | Scatter symbol lands |
| `SCATTER_LAND_1` | HIGH | 200ms | First scatter |
| `SCATTER_LAND_2` | HIGH | 300ms | Second scatter (+anticipation) |
| `SCATTER_LAND_3` | HIGHEST | 500ms | Third scatter (TRIGGER!) |
| `SCATTER_LAND_4` | HIGHEST | 600ms | Fourth scatter (bonus) |
| `SCATTER_LAND_5` | HIGHEST | 700ms | Fifth scatter (max bonus) |
| `SCATTER_HIGHLIGHT` | MEDIUM | Loop | Scatter glow/pulse |
| `SCATTER_COLLECT` | HIGH | 300ms | Scatters collected |

### Bonus Symbols

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `BONUS_LAND` | HIGH | 300ms | Bonus symbol lands |
| `BONUS_LAND_1` | HIGH | 200ms | First bonus symbol |
| `BONUS_LAND_2` | HIGH | 300ms | Second bonus symbol |
| `BONUS_LAND_3` | HIGHEST | 500ms | Third bonus (TRIGGER!) |
| `BONUS_HIGHLIGHT` | MEDIUM | Loop | Bonus symbol glow |

### Special Symbols

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `COIN_LAND` | HIGH | 150ms | Coin/money symbol lands |
| `COIN_VALUE_REVEAL` | HIGH | 200ms | Coin value shown |
| `MYSTERY_LAND` | HIGH | 200ms | Mystery symbol lands |
| `MYSTERY_REVEAL` | HIGH | 400ms | Mystery transforms |
| `MYSTERY_REVEAL_ALL` | HIGH | 600ms | All mysteries reveal |
| `COLLECTOR_LAND` | HIGH | 200ms | Collector symbol lands |
| `COLLECTOR_ACTIVATE` | HIGH | 500ms | Collector collects values |
| `PAYER_LAND` | HIGH | 200ms | Payer symbol lands |
| `PAYER_ACTIVATE` | HIGH | 500ms | Payer pays all symbols |
| `MULTIPLIER_SYMBOL_LAND` | HIGH | 250ms | Symbol with multiplier |

---

## 5. ANTICIPATION & TENSION (25 events)

Gradnja napetosti i near-miss.

### Anticipation

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `ANTICIPATION_ON` | HIGH | Variable | Anticipation starts |
| `ANTICIPATION_OFF` | MEDIUM | 100ms | Anticipation ends |
| `ANTICIPATION_BUILD` | HIGH | Loop | Building tension |
| `ANTICIPATION_BUILD_LOW` | MEDIUM | Loop | Low intensity build |
| `ANTICIPATION_BUILD_MID` | HIGH | Loop | Medium intensity |
| `ANTICIPATION_BUILD_HIGH` | HIGH | Loop | High intensity |
| `ANTICIPATION_PEAK` | HIGH | 500ms | Maximum tension |
| `ANTICIPATION_RELEASE_WIN` | HIGH | 200ms | Tension releases to win |
| `ANTICIPATION_RELEASE_MISS` | MEDIUM | 300ms | Tension releases to miss |
| `ANTICIPATION_REEL_SLOW` | HIGH | Variable | Final reel slows down |
| `ANTICIPATION_HEARTBEAT` | MEDIUM | Loop | Heartbeat pulse |
| `ANTICIPATION_DRONE` | LOW | Loop | Low tension drone |

### Near Miss

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `NEAR_MISS` | MEDIUM | 500-1500ms | Near miss detected |
| `NEAR_MISS_SYMBOL` | MEDIUM | 300ms | Symbol just missed |
| `NEAR_MISS_SCATTER` | MEDIUM | 500ms | Scatter near miss |
| `NEAR_MISS_BONUS` | MEDIUM | 500ms | Bonus near miss |
| `NEAR_MISS_JACKPOT` | MEDIUM | 800ms | Jackpot near miss |
| `NEAR_MISS_RESOLVE` | MEDIUM | 200ms | Near miss resolution |

### Tension Elements

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `TENSION_RISING` | MEDIUM | Loop | Rising pitch/intensity |
| `TENSION_HOLD` | MEDIUM | Loop | Sustained tension |
| `TENSION_DROP` | MEDIUM | 200ms | Tension release |
| `SUSPENSE_HIT` | HIGH | 100ms | Suspense accent |
| `DRAMATIC_PAUSE` | MEDIUM | 500ms | Silence before reveal |

---

## 6. WIN EVALUATION (15 events)

Evaluacija dobitka pre celebracije.

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `WIN_EVAL` | LOW | 0-50ms | Win evaluation (internal) |
| `WIN_DETECTED` | HIGH | 100ms | Win found |
| `NO_WIN` | LOW | 500ms | No win (silence or subtle) |
| `WIN_LINE_EVAL` | LOW | 50ms | Evaluating line |
| `WIN_LINE_FLASH` | MEDIUM | 100-200ms | Line flashes |
| `WIN_LINE_TRACE` | MEDIUM | Variable | Line traced |
| `WIN_SYMBOL_HIGHLIGHT` | MEDIUM | 50-100ms | Symbol highlighted |
| `WIN_WAYS_COUNT` | LOW | 100ms | Ways counted |
| `WIN_CLUSTER_HIGHLIGHT` | MEDIUM | 200ms | Cluster highlighted |
| `WIN_CLUSTER_TRACE` | MEDIUM | Variable | Cluster traced |
| `WIN_TOTAL_CALC` | LOW | 50ms | Total calculated |
| `LDW_SOUND` | MEDIUM | 500ms | Loss disguised as win |
| `WIN_MULTIPLIED` | HIGH | 300ms | Multiplier applied |
| `WIN_MULTIPLIER_COMBINE` | HIGH | 400ms | Multipliers combine |
| `WIN_STACK` | MEDIUM | 200ms | Multiple wins stack |

---

## 7. WIN CELEBRATION TIERS (40 events)

Proslava dobitka po nivoima.

### Win Tiers

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `WIN_MICRO` | MEDIUM | 200-300ms | Micro win (< 1x) |
| `WIN_TIER_0` | MEDIUM | 300-500ms | Tier 0 (1x-2x) |
| `WIN_TIER_1_SMALL` | MEDIUM | 500-1000ms | Small win (2x-5x) |
| `WIN_TIER_2_MEDIUM` | HIGH | 1000-2000ms | Medium win (5x-10x) |
| `WIN_TIER_3_BIG` | HIGH | 3000-5000ms | Big win (10x-25x) |
| `WIN_TIER_4_MEGA` | HIGHEST | 5000-10000ms | Mega win (25x-50x) |
| `WIN_TIER_5_SUPER` | HIGHEST | 10000-15000ms | Super win (50x-100x) |
| `WIN_TIER_6_EPIC` | HIGHEST | 15000-30000ms | Epic win (100x-500x) |
| `WIN_TIER_7_ULTRA` | HIGHEST | 30000-60000ms | Ultra win (500x+) |

### Win Components

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `WIN_PRESENT` | HIGH | Variable | Win presentation start |
| `WIN_JINGLE_SHORT` | MEDIUM | 500ms | Short win jingle |
| `WIN_JINGLE_MEDIUM` | HIGH | 1500ms | Medium win jingle |
| `WIN_JINGLE_LONG` | HIGHEST | 3000ms | Long win jingle |
| `WIN_FANFARE_INTRO` | HIGHEST | 1000-2000ms | Fanfare introduction |
| `WIN_FANFARE_LOOP` | HIGHEST | Loop | Fanfare main section |
| `WIN_FANFARE_OUTRO` | HIGHEST | 1000ms | Fanfare conclusion |
| `WIN_COINS_BURST` | MEDIUM | 500ms | Coin burst effect |
| `WIN_COINS_LOOP` | MEDIUM | Loop | Continuous coins |
| `WIN_COINS_SHOWER` | HIGH | Loop | Coin shower |
| `WIN_SPARKLE` | LOW | 200ms | Sparkle effect |
| `WIN_FIREWORK` | HIGH | 500ms | Firework burst |
| `WIN_FIREWORKS_LOOP` | HIGH | Loop | Continuous fireworks |
| `WIN_CROWD_CHEER` | HIGH | Variable | Crowd cheering |
| `WIN_APPLAUSE` | HIGH | Variable | Applause |
| `WIN_CELEBRATION_END` | MEDIUM | 500ms | Celebration ends |

### Rollup Counter

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `ROLLUP_START` | HIGH | 100ms | Counter starts |
| `ROLLUP_TICK` | MEDIUM | 16-33ms | Each tick |
| `ROLLUP_TICK_SLOW` | MEDIUM | 50ms | Slow tick |
| `ROLLUP_TICK_FAST` | MEDIUM | 16ms | Fast tick |
| `ROLLUP_LOOP` | MEDIUM | Loop | Continuous rolling |
| `ROLLUP_MILESTONE_25` | HIGH | 200ms | 25% milestone |
| `ROLLUP_MILESTONE_50` | HIGH | 300ms | 50% milestone |
| `ROLLUP_MILESTONE_75` | HIGH | 400ms | 75% milestone |
| `ROLLUP_SLAM` | HIGH | 200-300ms | Final slam |
| `ROLLUP_END` | HIGH | 200ms | Rollup complete |
| `ROLLUP_SKIP` | MEDIUM | 100ms | Player skipped rollup |

---

## 8. CASCADE / TUMBLE (25 events)

Cascade/Avalanche/Tumble mehanika.

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `CASCADE_WIN` | HIGH | 200ms | Cascade win detected |
| `CASCADE_START` | HIGH | 100ms | Cascade begins |
| `CASCADE_SYMBOL_POP` | MEDIUM | 50-100ms | Symbol pops/explodes |
| `CASCADE_SYMBOL_POP_0` | MEDIUM | 50ms | First symbol pops |
| `CASCADE_SYMBOLS_FALL` | MEDIUM | 200-400ms | Symbols falling |
| `CASCADE_SYMBOLS_LAND` | MEDIUM | 100ms | New symbols land |
| `CASCADE_EVAL` | LOW | 50ms | Evaluating cascade |
| `CASCADE_COMBO_1` | MEDIUM | 200ms | First cascade |
| `CASCADE_COMBO_2` | HIGH | 300ms | Second cascade |
| `CASCADE_COMBO_3` | HIGH | 400ms | Third cascade |
| `CASCADE_COMBO_4` | HIGH | 500ms | Fourth cascade |
| `CASCADE_COMBO_5` | HIGHEST | 600ms | Fifth cascade |
| `CASCADE_COMBO_6_PLUS` | HIGHEST | 700ms | 6+ cascades |
| `CASCADE_MULTIPLIER_UP` | HIGH | 300ms | Multiplier increases |
| `CASCADE_END` | MEDIUM | 200ms | Cascade sequence ends |
| `TUMBLE_START` | HIGH | 100ms | Tumble begins |
| `TUMBLE_DROP` | MEDIUM | 200ms | Symbols tumble down |
| `TUMBLE_LAND` | MEDIUM | 100ms | Symbols land |
| `AVALANCHE_RUMBLE` | MEDIUM | Loop | Avalanche rumble |
| `AVALANCHE_START` | HIGH | 200ms | Avalanche begins |
| `AVALANCHE_END` | MEDIUM | 200ms | Avalanche ends |
| `REACTION_START` | HIGH | 100ms | Reaction begins |
| `REACTION_CHAIN` | HIGH | Variable | Chain reaction |
| `GRAVITY_SHIFT` | MEDIUM | 300ms | Gravity changes |
| `SYMBOLS_DESTROY` | HIGH | 200ms | Symbols destroyed |

---

## 9. FREE SPINS (40 events)

Free spins feature kompletno.

### Trigger & Entry

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `FS_TRIGGER` | HIGHEST | 1500ms | Free spins triggered |
| `FS_TRIGGER_VOICE` | HIGHEST | 1000ms | "Free Spins!" voice |
| `FS_AWARD_SPINS` | HIGHEST | Variable | Spins being awarded |
| `FS_AWARD_SPIN_TICK` | HIGH | 100ms | Each spin awarded |
| `FS_AWARD_TOTAL` | HIGHEST | 500ms | Total spins shown |
| `FS_TRANSITION_IN` | HIGHEST | 500-1000ms | Transition to FS |
| `FS_SCREEN_CHANGE` | HIGH | 300ms | Screen transforms |
| `FS_ENTER` | HIGHEST | 500ms | Entering free spins |

### Free Spins Gameplay

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `FS_MUSIC_START` | HIGH | 500ms | FS music begins |
| `FS_MUSIC_LOOP` | MEDIUM | Loop | FS background music |
| `FS_MUSIC_INTENSITY_1` | MEDIUM | Loop | Low intensity layer |
| `FS_MUSIC_INTENSITY_2` | MEDIUM | Loop | Medium intensity |
| `FS_MUSIC_INTENSITY_3` | HIGH | Loop | High intensity |
| `FS_SPIN_START` | HIGH | 100ms | FS spin begins |
| `FS_SPIN` | MEDIUM | Variable | Free spin |
| `FS_SPIN_COUNTER` | MEDIUM | 100ms | Counter updates |
| `FS_REEL_STOP` | HIGH | 100ms | FS reel stops |
| `FS_WIN` | HIGH | Variable | Win during FS |
| `FS_WIN_ENHANCED` | HIGH | Variable | Enhanced FS win |
| `FS_NO_WIN` | LOW | 300ms | No win in FS |

### Free Spins Specials

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `FS_RETRIGGER` | HIGHEST | 2000ms | Free spins retrigger |
| `FS_RETRIGGER_SCATTER_1` | HIGH | 200ms | First retrigger scatter |
| `FS_RETRIGGER_SCATTER_2` | HIGH | 300ms | Second retrigger scatter |
| `FS_RETRIGGER_SCATTER_3` | HIGHEST | 500ms | Third (retrigger!) |
| `FS_RETRIGGER_AWARD` | HIGHEST | Variable | Additional spins |
| `FS_MULTIPLIER_UP` | HIGH | 300ms | FS multiplier increases |
| `FS_MULTIPLIER_MAX` | HIGHEST | 500ms | Max multiplier reached |
| `FS_STICKY_WILD` | HIGH | 200ms | Sticky wild in FS |
| `FS_EXPANDING_REEL` | HIGH | 400ms | Reel expands in FS |
| `FS_SYMBOL_UPGRADE` | HIGH | 300ms | Symbol upgraded |
| `FS_SYMBOL_REMOVE` | MEDIUM | 200ms | Low symbol removed |

### Free Spins End

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `FS_LAST_SPIN` | HIGH | 200ms | Last spin indicator |
| `FS_LAST_SPIN_ANNOUNCE` | HIGH | 500ms | "Last Spin!" voice |
| `FS_END` | HIGH | 300ms | Free spins ending |
| `FS_SUMMARY_START` | HIGHEST | 500ms | Summary begins |
| `FS_SUMMARY_ROLLUP` | HIGHEST | Variable | Total win rollup |
| `FS_SUMMARY_END` | HIGHEST | 500ms | Summary ends |
| `FS_TRANSITION_OUT` | HIGH | 500ms | Return to base |
| `FS_EXIT` | HIGH | 300ms | Exiting free spins |

---

## 10. HOLD & SPIN / RESPIN (35 events)

Lightning Link style features.

### Trigger & Entry

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `HOLD_TRIGGER` | HIGHEST | 1000ms | Hold & Spin triggered |
| `HOLD_TRIGGER_VOICE` | HIGHEST | 800ms | Voice announcement |
| `HOLD_GRID_TRANSFORM` | HIGHEST | 500ms | Grid transforms |
| `HOLD_ENTER` | HIGHEST | 500ms | Enter Hold & Spin |

### Hold & Spin Gameplay

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `HOLD_MUSIC_LOOP` | MEDIUM | Loop | Hold & Spin music |
| `HOLD_SYMBOL_LOCK` | HIGH | 150ms | Symbol locks in place |
| `HOLD_SYMBOL_LOCK_VALUE` | HIGH | 200ms | Value revealed |
| `HOLD_RESPIN` | HIGH | 200ms | Respin occurs |
| `HOLD_RESPIN_START` | HIGH | 150ms | Respin begins |
| `HOLD_RESPIN_STOP` | HIGH | 100ms | Respin ends |
| `HOLD_RESPIN_COUNTER_3` | HIGH | 150ms | 3 spins remaining |
| `HOLD_RESPIN_COUNTER_2` | HIGH | 200ms | 2 spins remaining |
| `HOLD_RESPIN_COUNTER_1` | HIGH | 300ms | 1 spin remaining (tension!) |
| `HOLD_COUNTER_RESET` | HIGH | 200ms | Counter resets to 3 |
| `HOLD_NEW_SYMBOL` | HIGHEST | 300ms | New symbol lands! |
| `HOLD_NO_SYMBOL` | LOW | 200ms | No new symbol |

### Special Symbols

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `HOLD_SPECIAL_COLLECTOR` | HIGHEST | 500ms | Collector activates |
| `HOLD_SPECIAL_PAYER` | HIGHEST | 500ms | Payer activates |
| `HOLD_SPECIAL_MULTIPLIER` | HIGHEST | 400ms | Multiplier applies |
| `HOLD_SPECIAL_PERSISTENT` | HIGH | 300ms | Persistent symbol |
| `HOLD_SPECIAL_UPGRADER` | HIGH | 400ms | Upgrader activates |
| `HOLD_SPECIAL_LINKER` | HIGH | 400ms | Linker connects |

### Grid & Level

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `HOLD_GRID_EXPAND` | HIGH | 400ms | Grid expands |
| `HOLD_GRID_FULL` | HIGHEST | 1000ms | Grid completely full |
| `HOLD_LEVEL_UP` | HIGHEST | 500ms | Level advances |
| `HOLD_JACKPOT_SYMBOL` | HIGHEST | 500ms | Jackpot symbol lands |

### End & Summary

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `HOLD_FINAL_SPIN` | HIGH | 300ms | Final spin |
| `HOLD_END` | HIGH | 300ms | Hold & Spin ends |
| `HOLD_COLLECT` | HIGHEST | Variable | Values collected |
| `HOLD_SUMMARY` | HIGHEST | Variable | Summary shown |
| `HOLD_EXIT` | HIGH | 300ms | Exit Hold & Spin |

---

## 11. BONUS GAMES (45 events)

Pick bonusi, wheel bonusi, trail bonusi.

### Pick Bonus

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `BONUS_TRIGGER` | HIGHEST | 1000ms | Bonus triggered |
| `BONUS_ENTER` | HIGHEST | 500ms | Enter bonus game |
| `BONUS_MUSIC_LOOP` | MEDIUM | Loop | Bonus music |
| `PICK_REVEAL_OPTIONS` | HIGH | 500ms | Options revealed |
| `PICK_HOVER` | LOW | 50ms | Hovering over option |
| `PICK_SELECT` | HIGH | 150ms | Option selected |
| `PICK_REVEAL_SMALL` | MEDIUM | 200ms | Small prize revealed |
| `PICK_REVEAL_MEDIUM` | HIGH | 400ms | Medium prize revealed |
| `PICK_REVEAL_LARGE` | HIGHEST | 600ms | Large prize revealed |
| `PICK_REVEAL_JACKPOT` | HIGHEST | 1000ms | Jackpot revealed |
| `PICK_REVEAL_MULTIPLIER` | HIGH | 400ms | Multiplier revealed |
| `PICK_REVEAL_EXTRA_PICK` | HIGH | 500ms | Extra pick revealed |
| `PICK_REVEAL_END` | MEDIUM | 300ms | End/Collect revealed |
| `PICK_LEVEL_UP` | HIGHEST | 500ms | Advance to next level |
| `PICK_COLLECT` | HIGH | 500ms | Collect prize |

### Wheel Bonus

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `WHEEL_APPEAR` | HIGHEST | 500ms | Wheel appears |
| `WHEEL_SPIN_START` | HIGH | 200ms | Wheel begins spinning |
| `WHEEL_SPIN_LOOP` | MEDIUM | Loop | Spinning sound |
| `WHEEL_TICK` | LOW | 20ms | Each tick |
| `WHEEL_TICK_FAST` | LOW | 10ms | Fast ticks |
| `WHEEL_TICK_SLOW` | MEDIUM | 50ms | Slowing ticks |
| `WHEEL_SLOW_DOWN` | MEDIUM | Variable | Wheel slowing |
| `WHEEL_NEAR_STOP` | HIGH | 100ms | Almost stopping |
| `WHEEL_LAND` | HIGHEST | 200ms | Wheel stops |
| `WHEEL_PRIZE_REVEAL` | HIGHEST | Variable | Prize revealed |
| `WHEEL_RESPIN` | HIGH | 300ms | Wheel respins |
| `WHEEL_MULTI_OUTER` | HIGH | 200ms | Outer wheel |
| `WHEEL_MULTI_INNER` | HIGH | 200ms | Inner wheel |
| `WHEEL_ADVANCE` | HIGHEST | 500ms | Advance to bigger wheel |

### Trail Bonus

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `TRAIL_ENTER` | HIGHEST | 500ms | Enter trail bonus |
| `TRAIL_MUSIC_LOOP` | MEDIUM | Loop | Trail music |
| `TRAIL_DICE_ROLL` | HIGH | 300ms | Dice rolling |
| `TRAIL_DICE_LAND` | HIGH | 150ms | Dice lands |
| `TRAIL_MOVE_START` | MEDIUM | 100ms | Piece starts moving |
| `TRAIL_MOVE_STEP` | MEDIUM | 100ms | Each step |
| `TRAIL_MOVE_END` | MEDIUM | 150ms | Piece stops |
| `TRAIL_LAND_PRIZE` | HIGH | 300ms | Land on prize |
| `TRAIL_LAND_MULTIPLIER` | HIGH | 400ms | Land on multiplier |
| `TRAIL_LAND_ADVANCE` | HIGH | 500ms | Land on advance |
| `TRAIL_LAND_COLLECT` | MEDIUM | 300ms | Land on collect |
| `TRAIL_LAND_HAZARD` | MEDIUM | 400ms | Land on hazard |
| `TRAIL_END` | HIGH | 300ms | Trail ends |

---

## 12. JACKPOT (30 events)

Progresivni i fiksni jackpotovi.

### Jackpot Trigger

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `JACKPOT_TRIGGER` | HIGHEST | 2000ms | Jackpot triggered |
| `JACKPOT_TRIGGER_SILENCE` | HIGHEST | 500ms | Dramatic silence |
| `JACKPOT_BUILD` | HIGHEST | Variable | Building anticipation |
| `JACKPOT_REVEAL_TIER` | HIGHEST | Variable | Tier being revealed |

### Jackpot Tiers

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `JACKPOT_MINI` | HIGH | 1000-2000ms | Mini jackpot |
| `JACKPOT_MINOR` | HIGH | 2000-3000ms | Minor jackpot |
| `JACKPOT_MAJOR` | HIGHEST | 5000-10000ms | Major jackpot |
| `JACKPOT_GRAND` | HIGHEST | 10000-30000ms | Grand jackpot |
| `JACKPOT_MEGA` | HIGHEST | 30000-60000ms | Mega jackpot |

### Jackpot Celebration

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `JACKPOT_FANFARE` | HIGHEST | Variable | Main fanfare |
| `JACKPOT_MUSIC_LOOP` | HIGHEST | Loop | Celebration music |
| `JACKPOT_COINS` | HIGH | Loop | Coin sounds |
| `JACKPOT_FIREWORKS` | HIGH | Loop | Fireworks |
| `JACKPOT_CROWD` | HIGH | Loop | Crowd cheering |
| `JACKPOT_VOICE` | HIGHEST | Variable | Voice announcement |
| `JACKPOT_ROLLUP` | HIGHEST | Variable | Amount rollup |
| `JACKPOT_ROLLUP_MILESTONE` | HIGHEST | 500ms | Rollup milestone |
| `JACKPOT_SLAM` | HIGHEST | 500ms | Final amount |
| `JACKPOT_RESOLUTION` | HIGHEST | 1000ms | Celebration ends |
| `JACKPOT_HAND_PAY` | HIGHEST | 2000ms | Hand pay notification |

### Progressive Meter

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `PROGRESSIVE_TICK` | LOW | 50ms | Meter ticks up |
| `PROGRESSIVE_APPROACHING` | MEDIUM | Loop | Near must-hit |
| `PROGRESSIVE_CONTRIBUTION` | LOW | 20ms | Contribution sound |
| `MUST_HIT_WARNING` | HIGH | 500ms | Must-hit approaching |

---

## 13. MULTIPLIER (20 events)

Multiplier eventi.

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `MULT_LAND` | HIGH | 250ms | Multiplier symbol lands |
| `MULT_REVEAL` | HIGH | 300ms | Multiplier revealed |
| `MULT_APPLY` | HIGH | 200ms | Multiplier applied to win |
| `MULT_INCREASE` | HIGH | 300ms | Multiplier increases |
| `MULT_DECREASE` | MEDIUM | 200ms | Multiplier decreases |
| `MULT_RESET` | MEDIUM | 200ms | Multiplier resets |
| `MULT_2X` | HIGH | 300ms | 2x multiplier |
| `MULT_3X` | HIGH | 350ms | 3x multiplier |
| `MULT_5X` | HIGH | 400ms | 5x multiplier |
| `MULT_10X` | HIGHEST | 500ms | 10x multiplier |
| `MULT_25X` | HIGHEST | 600ms | 25x multiplier |
| `MULT_50X` | HIGHEST | 700ms | 50x multiplier |
| `MULT_100X` | HIGHEST | 800ms | 100x multiplier |
| `MULT_COMBINE` | HIGHEST | 500ms | Multipliers combine |
| `MULT_MAX` | HIGHEST | 1000ms | Maximum multiplier |
| `MULT_RANDOM` | HIGH | 400ms | Random multiplier |
| `MULT_WILD` | HIGH | 350ms | Wild multiplier |
| `MULT_PROGRESSIVE` | HIGH | 300ms | Progressive multiplier |
| `MULT_ANNOUNCE` | HIGH | Variable | Voice "2x!", "5x!" etc |
| `MULT_CELEBRATE` | HIGH | Variable | Multiplier celebration |

---

## 14. MODIFIERS & RANDOM FEATURES (25 events)

Random trigeri i modifikatori.

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `MODIFIER_TRIGGER` | HIGH | 300ms | Modifier activated |
| `RANDOM_FEATURE` | HIGH | 500ms | Random feature triggered |
| `RANDOM_WILD` | HIGH | 400ms | Random wilds added |
| `RANDOM_MULTIPLIER` | HIGH | 400ms | Random multiplier added |
| `RANDOM_SYMBOL_TRANSFORM` | HIGH | 500ms | Random transform |
| `RANDOM_MEGA_SYMBOL` | HIGH | 600ms | Random mega symbol |
| `RANDOM_INSTANT_PRIZE` | HIGHEST | 500ms | Instant prize |
| `GOD_APPEAR` | HIGHEST | 800ms | God/character appears |
| `GOD_BLESSING` | HIGHEST | Variable | Blessing given |
| `WILD_INJECT` | HIGH | 400ms | Wilds injected |
| `SYMBOL_UPGRADE_ALL` | HIGH | 500ms | All symbols upgrade |
| `REEL_SYNC_ACTIVATE` | HIGH | 300ms | Reels sync |
| `XNUDGE_STEP` | HIGH | 200ms | xNudge step |
| `XNUDGE_COMPLETE` | HIGH | 400ms | xNudge complete |
| `XWAYS_EXPAND` | HIGH | 400ms | xWays expansion |
| `XBOMB_EXPLODE` | HIGHEST | 500ms | xBomb explosion |
| `XBOMB_CHAIN` | HIGHEST | Variable | Chain explosions |
| `TWIN_SYNC` | HIGH | 300ms | Twin reels sync |
| `TWIN_EXPAND` | HIGH | 400ms | Twins expand |
| `MEGA_STACK_LAND` | HIGH | 500ms | Mega stacks land |
| `COLOSSAL_REVEAL` | HIGH | 600ms | Colossal symbol |
| `QUAD_MERGE` | HIGHEST | 800ms | Megaquads merge |
| `SPLIT_SYMBOL` | HIGH | 300ms | Symbol splits |
| `UPGRADE_SYMBOL` | HIGH | 300ms | Symbol upgrades |
| `REMOVE_SYMBOL` | MEDIUM | 200ms | Symbol removed |

---

## 15. GAMBLE / DOUBLE-UP (15 events)

Gamble feature.

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `GAMBLE_OFFER` | HIGH | 500ms | Gamble offered |
| `GAMBLE_ACCEPT` | HIGH | 200ms | Gamble accepted |
| `GAMBLE_DECLINE` | MEDIUM | 150ms | Gamble declined |
| `GAMBLE_CARD_DEAL` | HIGH | 200ms | Card dealt |
| `GAMBLE_CARD_FLIP` | HIGH | 300ms | Card flipping |
| `GAMBLE_REVEAL` | HIGH | 200ms | Card revealed |
| `GAMBLE_WIN` | HIGHEST | 500ms | Gamble won |
| `GAMBLE_LOSE` | MEDIUM | 500ms | Gamble lost |
| `GAMBLE_DOUBLE` | HIGH | 400ms | Win doubled |
| `GAMBLE_LADDER_UP` | HIGH | 300ms | Ladder advances |
| `GAMBLE_LADDER_DOWN` | MEDIUM | 300ms | Ladder drops |
| `GAMBLE_COLLECT` | HIGH | 300ms | Collect winnings |
| `GAMBLE_MAX_WIN` | HIGHEST | 500ms | Max gamble win |
| `GAMBLE_HISTORY` | LOW | 100ms | History shown |
| `GAMBLE_EXIT` | MEDIUM | 200ms | Exit gamble |

---

## 16. AMBIENT & MUSIC (25 events)

Pozadinska muzika i ambient.

### Background Music

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `MUSIC_BASE_LOOP` | LOWEST | Loop | Base game music |
| `MUSIC_BASE_INTRO` | LOW | Variable | Music intro |
| `MUSIC_BASE_OUTRO` | LOW | Variable | Music outro |
| `MUSIC_INTENSITY_1` | LOW | Loop | Low intensity |
| `MUSIC_INTENSITY_2` | LOW | Loop | Medium intensity |
| `MUSIC_INTENSITY_3` | MEDIUM | Loop | High intensity |
| `MUSIC_CROSSFADE` | LOW | 500-2000ms | Music crossfade |
| `MUSIC_TRANSITION` | LOW | 300ms | Music transition |
| `MUSIC_FEATURE` | MEDIUM | Loop | Feature music |
| `MUSIC_WIN` | MEDIUM | Loop | Win music |
| `MUSIC_JACKPOT` | HIGH | Loop | Jackpot music |

### Ambient

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `AMBIENT_CASINO` | LOWEST | Loop | Casino ambience |
| `AMBIENT_THEME` | LOWEST | Loop | Theme-specific ambient |
| `AMBIENT_LAYER_1` | LOWEST | Loop | Ambient layer 1 |
| `AMBIENT_LAYER_2` | LOWEST | Loop | Ambient layer 2 |
| `AMBIENT_VARIATION` | LOWEST | Variable | Ambient variation |

### Attract Mode

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `ATTRACT_START` | LOW | 500ms | Attract mode begins |
| `ATTRACT_LOOP` | LOW | Loop | Attract music/demo |
| `ATTRACT_HIGHLIGHT` | LOW | Variable | Feature highlight |
| `ATTRACT_END` | LOW | 300ms | Attract ends |
| `IDLE_REMINDER` | LOW | 200ms | Idle reminder |
| `IDLE_VARIATION` | LOWEST | Variable | Idle sound change |
| `DEMO_START` | LOW | 300ms | Demo mode start |
| `DEMO_END` | LOW | 200ms | Demo mode end |

---

## 17. SYSTEM & RESPONSIBLE GAMING (20 events)

Sistemski eventi i odgovorno igranje.

### System

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `SYSTEM_ERROR` | HIGH | 300ms | System error |
| `SYSTEM_RECOVERY` | MEDIUM | 200ms | System recovered |
| `CONNECTION_LOST` | HIGH | 300ms | Connection lost |
| `CONNECTION_RESTORED` | MEDIUM | 200ms | Connection restored |
| `SESSION_START` | LOW | 200ms | Session starts |
| `SESSION_END` | LOW | 200ms | Session ends |
| `GAME_LOAD` | LOW | 300ms | Game loading |
| `GAME_READY` | LOW | 200ms | Game ready |
| `AUDIO_RESUME` | LOW | 100ms | Audio resumes |

### Responsible Gaming

| Event ID | Priority | Duration | Description |
|----------|----------|----------|-------------|
| `REALITY_CHECK` | MEDIUM | 500ms | Reality check popup |
| `TIME_WARNING` | MEDIUM | 400ms | Time limit warning |
| `TIME_LIMIT_REACHED` | HIGH | 500ms | Time limit reached |
| `LOSS_WARNING` | MEDIUM | 400ms | Loss limit warning |
| `LOSS_LIMIT_REACHED` | HIGH | 500ms | Loss limit reached |
| `DEPOSIT_WARNING` | MEDIUM | 400ms | Deposit limit warning |
| `DEPOSIT_LIMIT_REACHED` | HIGH | 500ms | Deposit limit reached |
| `COOL_OFF_START` | MEDIUM | 300ms | Cool-off period |
| `SELF_EXCLUDE` | HIGH | 500ms | Self-exclusion |
| `SESSION_SUMMARY` | MEDIUM | 300ms | Session summary |
| `BREAK_REMINDER` | MEDIUM | 300ms | Break reminder |

---

## Summary Statistics

| Category | Event Count |
|----------|-------------|
| UI Events | 25 |
| Spin Events | 20 |
| Reel Stop Events | 35 |
| Symbol Events | 50 |
| Anticipation & Tension | 25 |
| Win Evaluation | 15 |
| Win Celebration | 40 |
| Cascade/Tumble | 25 |
| Free Spins | 40 |
| Hold & Spin | 35 |
| Bonus Games | 45 |
| Jackpot | 30 |
| Multiplier | 20 |
| Modifiers | 25 |
| Gamble | 15 |
| Ambient & Music | 25 |
| System | 20 |
| **TOTAL** | **~490 events** |

---

## Priority Levels

| Priority | Use Case | Example |
|----------|----------|---------|
| LOWEST | Background, never interrupts | Ambient |
| LOW | UI feedback, minor | Button hover |
| MEDIUM | Gameplay, moderate | Reel stop |
| HIGH | Important feedback | Win, Wild land |
| HIGHEST | Critical moments | Jackpot, Feature trigger |

---

## Event Naming Rules

1. **UPPERCASE** sa **UNDERSCORES**
2. Format: `CATEGORY_ACTION_DETAIL`
3. Numbered variants: `_0`, `_1`, `_2` etc.
4. Tiers: `_SMALL`, `_MEDIUM`, `_BIG`, `_MEGA`, `_EPIC`, `_ULTRA`
5. States: `_START`, `_LOOP`, `_END`
6. Directions: `_UP`, `_DOWN`, `_LEFT`, `_RIGHT`

---

## ✅ IMPLEMENTACIJA U EventRegistry (2026-01-20)

Svi eventi iz ovog kataloga su implementirani u `flutter_ui/lib/services/event_registry.dart`.

### Implementirane funkcije:

| Funkcija | Opis | Status |
|----------|------|--------|
| `_pooledEventStages` | Set rapid-fire eventa za voice pooling | ✅ 50+ eventa |
| `_stageToPriority()` | Vraća prioritet 0-100 za stage | ✅ Kompletan |
| `_stageToBus()` | Mapira stage na SpatialBus | ✅ Kompletan |
| `_stageToIntent()` | Mapira stage na spatial intent | ✅ 300+ mapiranja |

### Pooled Events (rapid-fire, voice pooling):

```dart
const _pooledEventStages = {
  // Reel stops
  'REEL_STOP', 'REEL_STOP_0-5', 'REEL_STOP_SOFT', 'REEL_QUICK_STOP',
  // Cascade
  'CASCADE_STEP', 'CASCADE_SYMBOL_POP', 'TUMBLE_DROP', 'TUMBLE_LAND',
  // Rollup
  'ROLLUP_TICK', 'ROLLUP_TICK_SLOW', 'ROLLUP_TICK_FAST',
  // Win eval
  'WIN_LINE_FLASH', 'WIN_LINE_TRACE', 'WIN_SYMBOL_HIGHLIGHT',
  // UI
  'UI_BUTTON_PRESS', 'UI_BUTTON_HOVER', 'UI_BET_UP', 'UI_BET_DOWN',
  // Symbol lands
  'SYMBOL_LAND', 'SYMBOL_LAND_LOW', 'SYMBOL_LAND_MID', 'SYMBOL_LAND_HIGH',
  // Wheel/Trail
  'WHEEL_TICK', 'WHEEL_TICK_FAST', 'WHEEL_TICK_SLOW', 'TRAIL_MOVE_STEP',
  // Progressive
  'PROGRESSIVE_TICK', 'PROGRESSIVE_CONTRIBUTION',
};
```

### Priority Mapping (0-100):

| Range | Level | Examples |
|-------|-------|----------|
| 80-100 | HIGHEST | JACKPOT_*, WIN_TIER_6/7, FS_TRIGGER, BONUS_TRIGGER |
| 60-79 | HIGH | SPIN_START, REEL_STOP, WILD_*, SCATTER_*, WIN_BIG |
| 40-59 | MEDIUM | REEL_SPIN_LOOP, WIN_SMALL, CASCADE_SYMBOL, FS_SPIN |
| 20-39 | LOW | UI_*, SYMBOL_LAND, ROLLUP_TICK, WHEEL_TICK |
| 0-19 | LOWEST | MUSIC_BASE, AMBIENT_*, ATTRACT_*, IDLE_* |

### Bus Routing:

| SpatialBus | Stage Prefixes |
|------------|----------------|
| `reels` | REEL_*, SPIN_*, SYMBOL_LAND |
| `sfx` | WIN_*, JACKPOT_*, CASCADE_*, WILD_*, SCATTER_*, MULT_* |
| `music` | MUSIC_*, FS_MUSIC, HOLD_MUSIC, ATTRACT_* |
| `vo` | *_VOICE, *_VO, *_ANNOUNCE |
| `ui` | UI_*, SYSTEM_*, CONNECTION_* |
| `ambience` | AMBIENT_*, IDLE_*, DEMO_* |

### Spatial Intent Mapping:

Stage → Intent za AutoSpatialEngine pozicioniranje:

- `REEL_STOP_0-4` → per-reel panning (left to right)
- `WIN_TIER_*` → WIN_SMALL/MEDIUM/BIG/MEGA/EPIC
- `SCATTER_LAND_3` → FREE_SPIN_TRIGGER
- `JACKPOT_*` → JACKPOT_TRIGGER
- `FS_TRIGGER` → FREE_SPIN_TRIGGER
- `HOLD_TRIGGER` → FEATURE_ENTER
- `CASCADE_COMBO_*` → WIN_SMALL → WIN_EPIC (progressive)

---

### ✅ Stage Triggering Fix (2026-01-20)

**Problem:** Eventi nisu trigerovali zvuk jer su `triggerStages` bili prazni.

**Root Cause:**
1. `SlotCompositeEvent` default ima prazan `triggerStages: []`
2. `_getEventStage()` je vraćao prazan string `''`
3. `EventRegistry._stageToEvent['']` nije mogao da pronađe event

**Rešenje u `slot_lab_screen.dart`:**

```dart
/// _getEventStage sada vraća derived stage iz kategorije ako su triggerStages prazni
String _getEventStage(SlotCompositeEvent event) {
  if (event.triggerStages.isNotEmpty) {
    return event.triggerStages.first;
  }
  // Fallback: derive stage from category
  return switch (event.category.toLowerCase()) {
    'spin' => 'SPIN_START',
    'reelstop' => 'REEL_STOP',
    'anticipation' => 'ANTICIPATION_ON',
    'win' => 'WIN_PRESENT',
    'bigwin' => 'BIGWIN_TIER',
    'feature' => 'FEATURE_ENTER',
    'bonus' => 'BONUS_ENTER',
    _ => event.name.toUpperCase().replaceAll(' ', '_'),
  };
}
```

**Dodatno:** `_onMiddlewareChanged()` sada poziva `_syncEventToRegistry()` za svaki event, osiguravajući da se EventRegistry ažurira kad god se layer doda/ukloni.

---

### ✅ Per-Reel REEL_STOP Fix (2026-01-20)

**Problem:** `REEL_STOP_0`, `REEL_STOP_1`, `REEL_STOP_2`, `REEL_STOP_3`, `REEL_STOP_4` nisu radili — trigerovao se samo generički `REEL_STOP`.

**Root Cause:**
1. Rust `rf-stage` šalje JSON strukturu:
   ```json
   {
     "stage": { "type": "reel_stop", "reel_index": 0, "symbols": [...] },
     "timestamp_ms": 500,
     "payload": { "win_amount": null, ... }
   }
   ```
2. `SlotLabStageEvent.fromJson` parsira:
   - `stageType` → iz `stage.type`
   - `payload` → iz `json['payload']`
   - `rawStage` → iz `json['stage']` (sadrži `reel_index`, `symbols`, `reason`)
3. Kod je čitao `stage.payload['reel_index']` umesto `stage.rawStage['reel_index']`

**Rešenje u `slot_lab_provider.dart`:**

```dart
// CRITICAL: reel_index and symbols are in rawStage (from stage JSON), not payload
final reelIndex = stage.rawStage['reel_index'];
Map<String, dynamic> context = {...stage.payload, ...stage.rawStage};

// Za symbols i has_wild/has_scatter takođe:
final symbols = stage.rawStage['symbols'] as List<dynamic>?;
final hasWild = stage.rawStage['has_wild'] as bool? ?? _containsWild(symbols);
```

**Izmenjene metode:**
- `_triggerStage()` — čita `reelIndex` i `symbols` iz `rawStage`
- `_triggerAudioOnly()` — isto
- `_handleReelStopUIOnly()` — isto
- `_calculateAnticipationEscalation()` — čita `reel_index` i `reason` iz `rawStage`

**Data Flow:**
```
Rust rf-stage → JSON → SlotLabStageEvent.fromJson → rawStage['reel_index']
                                                  → REEL_STOP_$reelIndex
                                                  → EventRegistry.triggerStage()
```

---

*Ovaj katalog služi kao master referenca za FluxForge EventRegistry implementaciju.*
