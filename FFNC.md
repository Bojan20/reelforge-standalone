# FluxForge Audio Naming Convention (FFNC)

**Version:** 1.0
**Date:** 2026-03-19

---

## Overview

FFNC is the standard naming convention for audio files used in FluxForge Studio SlotLab.
Files named according to FFNC are recognized by Auto-Bind with 100% accuracy — zero guessing, zero manual assignment needed.

Files that do NOT follow FFNC still work through the legacy alias matching system (~80% accuracy).

---

## Format

```
<prefix>_<name>.wav
```

- **Lowercase** letters only
- **Underscore** between words
- **No spaces**, no capital letters
- **No extra prefixes** (not: `004_sfx_...`)
- **No extra suffixes** (not: `..._final`, `..._v2`, `..._new`)
- **Numbers start from 1** (reel 1 = first reel, tier 1 = lowest tier)

---

## Prefixes

Every audio file starts with one of six prefixes that identifies its category and determines default bus routing:

| Prefix | Category | Default Bus | Description |
|--------|----------|-------------|-------------|
| `sfx_` | Sound Effects | sfx (engine ID 2) | All gameplay sounds — spins, stops, wins, impacts, cascades, features |
| `mus_` | Music | music (engine ID 1) | All music — base game, free spins, bonus, tension, stingers |
| `amb_` | Ambience | ambience (engine ID 4) | Background loops — ambient atmosphere, attract mode, idle |
| `trn_` | Transitions | sfx (engine ID 2) | Scene transition sounds — swooshes, impacts, reveals |
| `ui_` | Interface | sfx (engine ID 2) | All UI sounds — buttons, menus, bet controls, navigation |
| `vo_` | Voice-Over | voice (engine ID 3) | All voice recordings — win announcements, narrator |

### Engine Bus IDs

The audio engine has 6 hardware buses. Smart Defaults map each stage to the correct engine bus:

| Engine Bus | ID | Used By |
|------------|-----|---------|
| master | 0 | Master output (all audio routes through this) |
| music | 1 | `mus_` files |
| sfx | 2 | `sfx_` files, `trn_` files, `ui_` files |
| voice | 3 | `vo_` files |
| ambience | 4 | `amb_` files |
| aux | 5 | Auxiliary (reserved for future use) |

Note: Smart Defaults use logical bus names (reels, wins, anticipation, ui) in documentation for clarity. These are sub-categories that all route to engine bus `sfx` (ID 2) unless otherwise specified.

---

## Multi-Layer Events

When a single event needs multiple sounds playing **simultaneously**, use `_layerN` suffix:

```
sfx_spin_start_layer1.wav       ← whoosh sound
sfx_spin_start_layer2.wav       ← reel mechanism click
```

**Result:** Both sounds play at the same time when SPIN_START triggers.

Rules:
- Layer numbers start from 1
- If there is only one file (no `_layerN` suffix), it is the only layer
- All layers of the same event trigger simultaneously
- Each layer can have its own volume, bus, and fade settings (configured in ASSIGN tab)

---

## Variants (Round-Robin Pool)

When a single event should randomly pick from multiple alternatives, use `_variant_x` suffix:

```
sfx_reel_stop_2_variant_a.wav   ← thud
sfx_reel_stop_2_variant_b.wav   ← clank
sfx_reel_stop_2_variant_c.wav   ← slam
```

**Result:** Each time REEL_STOP for reel 2 triggers, the system randomly picks one variant.

Rules:
- Variant letters are lowercase: `_variant_a`, `_variant_b`, `_variant_c`, etc.
- If there is only one file (no `_variant_x` suffix), there is no randomization
- Variants are never played simultaneously — only one is chosen per trigger

---

## Multi-Layer + Variants Combined

Layers and variants can be combined for complex events:

```
sfx_big_win_tier_1_layer1.wav               ← impact (always plays)
sfx_big_win_tier_1_layer2.wav               ← music hit (always plays)
sfx_big_win_tier_1_layer3_variant_a.wav     ← crowd cheer v1 (random pick)
sfx_big_win_tier_1_layer3_variant_b.wav     ← crowd cheer v2 (random pick)
sfx_big_win_tier_1_layer3_variant_c.wav     ← crowd roar (random pick)
```

**Result:** Layer 1 + Layer 2 always play. Layer 3 randomly picks one variant. All three layers sound together.

---

## Parser Logic

The FFNC parser processes filenames in this order:

1. Strip file extension (`.wav`, `.mp3`, `.ogg`, `.flac`, `.aiff`)
2. Extract `_variant_x` suffix if present → store variant letter
3. Extract `_layerN` suffix if present → store layer number
4. Identify prefix (`sfx_`, `mus_`, `amb_`, `trn_`, `ui_`, `vo_`)
5. Transform remaining name to internal stage name (see Transformation Rules)

```
sfx_big_win_tier_1_layer2_variant_a.wav
│    │              │       │
│    │              │       └─ variant: a
│    │              └───────── layer: 2
│    └──────────────────────── name: big_win_tier_1
└───────────────────────────── prefix: sfx_ (strip for stage)

→ Internal stage: BIG_WIN_TIER_1, layer 2, variant A
```

---

## Transformation Rules

### sfx_ → strip prefix, uppercase

| FFNC Name | Internal Stage |
|-----------|----------------|
| `sfx_spin_start` | `SPIN_START` |
| `sfx_reel_stop_3` | `REEL_STOP_2` (1-based → 0-based) |
| `sfx_big_win_tier_1` | `BIG_WIN_TIER_1` |
| `sfx_feature_enter` | `FEATURE_ENTER` |

### mus_ → replace with MUSIC_, uppercase

| FFNC Name | Internal Stage |
|-----------|----------------|
| `mus_base_game_l1` | `MUSIC_BASE_L1` (base_game → BASE) |
| `mus_base_game_intro` | `MUSIC_BASE_INTRO` |
| `mus_freespin_l1` | `MUSIC_FS_L1` (freespin → FS) |
| `mus_freespin_intro` | `MUSIC_FS_INTRO` |
| `mus_bonus_l1` | `MUSIC_BONUS_L1` |
| `mus_tension_high` | `MUSIC_TENSION_HIGH` |
| `mus_stinger_win` | `MUSIC_STINGER_WIN` |
| `mus_big_win` | `MUSIC_BIGWIN` |

### amb_ → replace with AMBIENT_ or direct, uppercase

| FFNC Name | Internal Stage |
|-----------|----------------|
| `amb_base_game` | `AMBIENT_BASE` (base_game → BASE) |
| `amb_freespin` | `AMBIENT_FS` (freespin → FS) |
| `amb_bonus` | `AMBIENT_BONUS` |
| `amb_hold` | `AMBIENT_HOLD` |
| `amb_big_win` | `AMBIENT_BIGWIN` |
| `amb_jackpot` | `AMBIENT_JACKPOT` |
| `amb_gamble` | `AMBIENT_GAMBLE` |
| `amb_attract_loop` | `ATTRACT_LOOP` |
| `amb_attract_exit` | `ATTRACT_EXIT` |
| `amb_idle_loop` | `IDLE_LOOP` |
| `amb_idle_to_active` | `IDLE_TO_ACTIVE` |

### trn_ → replace with TRANSITION_, uppercase

| FFNC Name | Internal Stage |
|-----------|----------------|
| `trn_to_freespin` | `TRANSITION_TO_FREESPINS` |
| `trn_to_base` | `TRANSITION_TO_BASE` |
| `trn_swoosh` | `TRANSITION_SWOOSH` |
| `trn_impact` | `TRANSITION_IMPACT` |

### ui_ → direct uppercase

| FFNC Name | Internal Stage |
|-----------|----------------|
| `ui_spin_press` | `UI_SPIN_PRESS` |
| `ui_bet_up` | `UI_BET_UP` |
| `ui_menu_open` | `UI_MENU_OPEN` |

### vo_ → direct uppercase

| FFNC Name | Internal Stage |
|-----------|----------------|
| `vo_big_win` | `VO_BIG_WIN` |
| `vo_win_1` | `VO_WIN_1` |
| `vo_congratulations` | `VO_CONGRATULATIONS` |

### Summary of All Transformations

| FFNC Pattern | Internal Pattern | Rule |
|---|---|---|
| `sfx_reel_stop_N` | `REEL_STOP_(N-1)` | Reel index: 1-based → 0-based |
| `sfx_win_tier_N` | `WIN_PRESENT_N` | `win_tier` → `WIN_PRESENT` |
| `mus_base_game_*` | `MUSIC_BASE_*` | `base_game` → `BASE` |
| `mus_freespin_*` | `MUSIC_FS_*` | `freespin` → `FS` |
| `amb_base_game` | `AMBIENT_BASE` | `base_game` → `BASE` |
| `amb_freespin` | `AMBIENT_FS` | `freespin` → `FS` |
| `amb_big_win` | `AMBIENT_BIGWIN` | `big_win` → `BIGWIN` |
| `amb_attract_*` / `amb_idle_*` | `ATTRACT_*` / `IDLE_*` | Strip `amb_` prefix |
| Everything else | Strip prefix + uppercase | Direct mapping |

---

## 1-Based Numbering

FFNC uses **1-based numbering** everywhere. Reel 1 is the first (leftmost) reel.

The internal system uses 0-based indexing for `REEL_STOP` only. The parser handles conversion automatically:

| FFNC File | Internal Stage | Conversion |
|-----------|----------------|------------|
| `sfx_reel_stop_1.wav` | `REEL_STOP_0` | −1 |
| `sfx_reel_stop_2.wav` | `REEL_STOP_1` | −1 |
| `sfx_reel_stop_3.wav` | `REEL_STOP_2` | −1 |
| `sfx_reel_stop_4.wav` | `REEL_STOP_3` | −1 |
| `sfx_reel_stop_5.wav` | `REEL_STOP_4` | −1 |
| `sfx_scatter_land_1.wav` | `SCATTER_LAND_1` | none (already 1-based) |
| `sfx_win_tier_1.wav` | `WIN_PRESENT_1` | none (already 1-based) |
| `sfx_big_win_tier_1.wav` | `BIG_WIN_TIER_1` | none (already 1-based) |
| `sfx_cascade_step_1.wav` | `CASCADE_STEP_1` | none (already 1-based) |

Only `REEL_STOP` requires conversion. All other indexed stages are already 1-based internally.

---

## Smart Defaults

When Auto-Bind processes FFNC files, it applies intelligent default parameters based on the stage category. These defaults determine volume, bus routing, fade times, and looping — so the designer does not need to configure them manually.

Parameters set in the ASSIGN tab always override smart defaults.

### Spin Lifecycle

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `SPIN_START` | 0.70 | sfx | — | — | — |
| `REEL_SPIN_LOOP` | 0.60 | reels | — | — | ✓ |
| `REEL_STOP_*` | 0.80 | reels | — | 100ms | — |
| `SPIN_END` | 0.50 | sfx | — | — | — |
| `SLAM_STOP` | 0.90 | reels | — | — | — |
| `QUICK_STOP` | 0.85 | reels | — | — | — |

### Anticipation

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `ANTICIPATION_TENSION` | 0.50 | anticipation | 300ms | — | ✓ |
| `ANTICIPATION_TENSION_R*` | 0.50–0.70 | anticipation | 300ms | — | ✓ |
| `ANTICIPATION_OFF` | 0.50 | anticipation | — | 200ms | — |
| `ANTICIPATION_MISS` | 0.50 | sfx | — | — | — |

### Wins

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `WIN_PRESENT_LOW` | 0.40 | wins | — | — | — |
| `WIN_PRESENT_EQUAL` | 0.50 | wins | — | — | — |
| `WIN_PRESENT_1` | 0.55 | wins | — | — | — |
| `WIN_PRESENT_2` | 0.60 | wins | — | — | — |
| `WIN_PRESENT_3` | 0.65 | wins | — | — | — |
| `WIN_PRESENT_4` | 0.70 | wins | — | — | — |
| `WIN_PRESENT_5` | 0.75 | wins | — | — | — |
| `WIN_PRESENT_6` | 0.78 | wins | — | — | — |
| `WIN_PRESENT_7` | 0.80 | wins | — | — | — |
| `WIN_PRESENT_8` | 0.82 | wins | — | — | — |
| `ROLLUP_START` | 0.45 | wins | — | — | — |
| `ROLLUP_TICK` | 0.40 | wins | — | — | — |
| `ROLLUP_TICK_FAST` | 0.45 | wins | — | — | — |
| `ROLLUP_END` | 0.50 | wins | — | — | — |

### Big Wins

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `BIG_WIN_START` | 1.00 | wins | — | — | — |
| `BIG_WIN_TIER_1` | 0.90 | wins | 50ms | — | — |
| `BIG_WIN_TIER_2` | 0.92 | wins | 50ms | — | — |
| `BIG_WIN_TIER_3` | 0.94 | wins | 50ms | — | — |
| `BIG_WIN_TIER_4` | 0.96 | wins | 50ms | — | — |
| `BIG_WIN_TIER_5` | 0.98 | wins | 50ms | — | — |
| `BIG_WIN_TIER_6` | 1.00 | wins | 50ms | — | — |
| `BIG_WIN_TIER_7` | 1.00 | wins | 50ms | — | — |
| `BIG_WIN_TIER_8` | 1.00 | wins | 50ms | — | — |
| `BIG_WIN_END` | 0.80 | wins | — | 500ms | — |
| `COIN_SHOWER` | 0.60 | sfx | — | — | — |

### Scatter & Wild

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `SCATTER_LAND` | 0.80 | sfx | — | — | — |
| `SCATTER_LAND_*` | 0.80 | sfx | — | — | — |
| `WILD_LAND` | 0.70 | sfx | — | — | — |
| `WILD_EXPAND` | 0.75 | sfx | — | — | — |
| `WILD_STICKY` | 0.70 | sfx | — | — | — |
| `WILD_WALK` | 0.65 | sfx | — | — | — |

### Features

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `FEATURE_ENTER` | 0.80 | sfx | 100ms | — | — |
| `FEATURE_EXIT` | 0.70 | sfx | — | 200ms | — |
| `FREESPIN_TRIGGER` | 0.90 | sfx | — | — | — |
| `FREESPIN_START` | 0.85 | sfx | — | — | — |
| `FREESPIN_END` | 0.75 | sfx | — | 200ms | — |
| `FREESPIN_RETRIGGER` | 0.90 | sfx | — | — | — |

### Cascade

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `CASCADE_START` | 0.65 | sfx | — | — | — |
| `CASCADE_STEP` | 0.60 | sfx | — | — | — |
| `CASCADE_STEP_*` | 0.60 | sfx | — | — | — |
| `CASCADE_POP` | 0.50 | sfx | — | — | — |
| `CASCADE_END` | 0.55 | sfx | — | — | — |

### Multiplier

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `MULTIPLIER_INCREASE` | 0.70 | sfx | — | — | — |
| `MULTIPLIER_APPLY` | 0.75 | sfx | — | — | — |
| `MULTIPLIER_X*` | 0.80 | sfx | — | — | — |

### Hold & Win

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `HOLD_TRIGGER` | 0.80 | sfx | — | — | — |
| `HOLD_START` | 0.75 | sfx | — | — | — |
| `HOLD_END` | 0.70 | sfx | — | 200ms | — |
| `PRIZE_REVEAL` | 0.80 | sfx | — | — | — |
| `PRIZE_UPGRADE` | 0.85 | sfx | — | — | — |

### Gamble

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `GAMBLE_START` | 0.60 | sfx | — | — | — |
| `GAMBLE_WIN` | 0.80 | wins | — | — | — |
| `GAMBLE_LOSE` | 0.50 | sfx | — | — | — |
| `GAMBLE_COLLECT` | 0.70 | sfx | — | — | — |

### Jackpot

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `JACKPOT_TRIGGER` | 0.85 | wins | — | — | — |
| `JACKPOT_REVEAL` | 0.90 | wins | — | — | — |
| `JACKPOT_MINI` | 0.80 | wins | — | — | — |
| `JACKPOT_MINOR` | 0.85 | wins | — | — | — |
| `JACKPOT_MAJOR` | 0.90 | wins | — | — | — |
| `JACKPOT_GRAND` | 1.00 | wins | — | — | — |
| `JACKPOT_MEGA` | 1.00 | wins | — | — | — |
| `JACKPOT_CELEBRATION` | 0.90 | wins | — | — | — |

### Bonus

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `BONUS_TRIGGER` | 0.80 | sfx | — | — | — |
| `BONUS_ENTER` | 0.75 | sfx | 100ms | — | — |
| `BONUS_EXIT` | 0.70 | sfx | — | 200ms | — |
| `BONUS_WIN` | 0.80 | wins | — | — | — |

### Near Miss

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `NEAR_MISS` | 0.60 | sfx | — | — | — |
| `NEAR_MISS_SCATTER` | 0.65 | sfx | — | — | — |
| `NEAR_MISS_BONUS` | 0.65 | sfx | — | — | — |
| `NEAR_MISS_WILD` | 0.60 | sfx | — | — | — |

### Respin

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `RESPIN_TRIGGER` | 0.75 | sfx | — | — | — |
| `RESPIN_START` | 0.70 | sfx | — | — | — |
| `RESPIN_END` | 0.65 | sfx | — | — | — |
| `RESPIN_RETRIGGER` | 0.80 | sfx | — | — | — |

### Pick Bonus

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `PICK_REVEAL` | 0.70 | sfx | — | — | — |
| `PICK_GOOD` | 0.75 | sfx | — | — | — |
| `PICK_BAD` | 0.55 | sfx | — | — | — |
| `PICK_COLLECT` | 0.70 | sfx | — | — | — |

### Wheel

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `WHEEL_SPIN` | 0.70 | sfx | — | — | — |
| `WHEEL_TICK` | 0.50 | sfx | — | — | — |
| `WHEEL_LAND` | 0.80 | sfx | — | — | — |
| `WHEEL_PRIZE` | 0.85 | wins | — | — | — |

### Collect & Coins

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `COIN_BURST` | 0.65 | sfx | — | — | — |
| `COIN_DROP` | 0.55 | sfx | — | — | — |
| `COIN_COLLECT` | 0.60 | sfx | — | — | — |
| `COLLECT_TRIGGER` | 0.70 | sfx | — | — | — |
| `COLLECT_COMPLETE` | 0.75 | sfx | — | — | — |

### Celebration & VFX

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `SCREEN_SHAKE` | 0.60 | sfx | — | — | — |
| `LIGHT_FLASH` | 0.55 | sfx | — | — | — |
| `CONFETTI_BURST` | 0.50 | sfx | — | — | — |
| `FIREWORKS_LAUNCH` | 0.65 | sfx | — | — | — |
| `FIREWORKS_EXPLODE` | 0.70 | sfx | — | — | — |
| `WIN_FANFARE` | 0.80 | sfx | — | — | — |
| `GAME_READY` | 0.60 | sfx | — | — | — |

### Ambience

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `AMBIENT_BASE` | 0.40 | ambience | 500ms | — | ✓ |
| `AMBIENT_FS` | 0.40 | ambience | 500ms | — | ✓ |
| `AMBIENT_BONUS` | 0.40 | ambience | 500ms | — | ✓ |
| `AMBIENT_HOLD` | 0.40 | ambience | 500ms | — | ✓ |
| `AMBIENT_BIGWIN` | 0.45 | ambience | 300ms | — | ✓ |
| `AMBIENT_JACKPOT` | 0.45 | ambience | 300ms | — | ✓ |
| `AMBIENT_GAMBLE` | 0.35 | ambience | 500ms | — | ✓ |
| `ATTRACT_LOOP` | 0.35 | ambience | 1000ms | — | ✓ |
| `ATTRACT_EXIT` | 0.40 | ambience | — | 300ms | — |
| `IDLE_LOOP` | 0.30 | ambience | 1000ms | — | ✓ |
| `IDLE_TO_ACTIVE` | 0.40 | ambience | — | 200ms | — |
| Any other `AMBIENT_*` | 0.40 | ambience | 500ms | — | ✓ |

### Music

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `MUSIC_BASE_L1` | 1.00 | music | — | — | ✓ |
| `MUSIC_BASE_L2` | 0.00 | music | — | — | ✓ |
| `MUSIC_BASE_L3` | 0.00 | music | — | — | ✓ |
| `MUSIC_BASE_L4` | 0.00 | music | — | — | ✓ |
| `MUSIC_BASE_L5` | 0.00 | music | — | — | ✓ |
| `MUSIC_BASE_INTRO` | 0.80 | music | 200ms | — | — |
| `MUSIC_BASE_OUTRO` | 0.80 | music | — | 500ms | — |
| `MUSIC_FS_L1` | 1.00 | music | — | — | ✓ |
| `MUSIC_FS_L2+` | 0.00 | music | — | — | ✓ |
| `MUSIC_FS_INTRO` | 0.80 | music | 200ms | — | — |
| `MUSIC_FS_OUTRO` | 0.80 | music | — | 500ms | — |
| `MUSIC_BONUS_L1` | 1.00 | music | — | — | ✓ |
| `MUSIC_BONUS_L2+` | 0.00 | music | — | — | ✓ |
| `MUSIC_HOLD_L1` | 1.00 | music | — | — | ✓ |
| `MUSIC_HOLD_L2+` | 0.00 | music | — | — | ✓ |
| `MUSIC_JACKPOT_L1` | 1.00 | music | — | — | ✓ |
| `MUSIC_JACKPOT_L2+` | 0.00 | music | — | — | ✓ |
| `MUSIC_GAMBLE_L1` | 1.00 | music | — | — | ✓ |
| `MUSIC_GAMBLE_L2+` | 0.00 | music | — | — | ✓ |
| `MUSIC_REVEAL_L1` | 1.00 | music | — | — | ✓ |
| `MUSIC_REVEAL_L2+` | 0.00 | music | — | — | ✓ |
| `MUSIC_TENSION_LOW` | 0.50 | music | 300ms | — | ✓ |
| `MUSIC_TENSION_MED` | 0.60 | music | 300ms | — | ✓ |
| `MUSIC_TENSION_HIGH` | 0.70 | music | 300ms | — | ✓ |
| `MUSIC_TENSION_MAX` | 0.80 | music | 300ms | — | ✓ |
| `MUSIC_BUILDUP` | 0.70 | music | 200ms | — | — |
| `MUSIC_CLIMAX` | 0.85 | music | — | — | — |
| `MUSIC_RESOLVE` | 0.60 | music | — | 500ms | — |
| `MUSIC_STINGER_*` | 0.75 | music | — | — | — |
| `MUSIC_BIGWIN` | 0.85 | music | — | — | ✓ |

### Music — Layer Volume Rule

For all music contexts (base game, free spins, bonus, hold, jackpot, gamble, reveal):
- **Layer 1** starts at volume **1.0** (audible)
- **Layer 2–5** start at volume **0.0** (silent, ready for crossfade)

This enables the Music Layer Controller to crossfade between layers based on win intensity.

### Transitions

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `TRANSITION_TO_BASE` | 0.70 | sfx | — | — | — |
| `TRANSITION_TO_FREESPINS` | 0.75 | sfx | — | — | — |
| `TRANSITION_TO_BONUS` | 0.75 | sfx | — | — | — |
| `TRANSITION_TO_FEATURE` | 0.75 | sfx | — | — | — |
| `TRANSITION_TO_JACKPOT` | 0.80 | sfx | — | — | — |
| `TRANSITION_TO_GAMBLE` | 0.70 | sfx | — | — | — |
| `TRANSITION_FADE_IN` | 0.65 | sfx | — | — | — |
| `TRANSITION_FADE_OUT` | 0.65 | sfx | — | — | — |
| `TRANSITION_SWOOSH` | 0.70 | sfx | — | — | — |
| `TRANSITION_IMPACT` | 0.80 | sfx | — | — | — |
| `TRANSITION_REVEAL` | 0.70 | sfx | — | — | — |
| `TRANSITION_STINGER` | 0.75 | sfx | — | — | — |

### UI

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `UI_SPIN_PRESS` | 0.55 | ui | — | — | — |
| `UI_SPIN_HOVER` | 0.35 | ui | — | — | — |
| `UI_BET_UP` | 0.50 | ui | — | — | — |
| `UI_BET_DOWN` | 0.50 | ui | — | — | — |
| `UI_BET_MAX` | 0.55 | ui | — | — | — |
| `UI_BET_MIN` | 0.45 | ui | — | — | — |
| `UI_MENU_OPEN` | 0.50 | ui | — | — | — |
| `UI_MENU_CLOSE` | 0.45 | ui | — | — | — |
| `UI_AUTOPLAY_START` | 0.50 | ui | — | — | — |
| `UI_AUTOPLAY_STOP` | 0.50 | ui | — | — | — |
| `UI_TURBO_ON` | 0.50 | ui | — | — | — |
| `UI_TURBO_OFF` | 0.50 | ui | — | — | — |
| `UI_SETTINGS_OPEN` | 0.45 | ui | — | — | — |
| `UI_SETTINGS_CLOSE` | 0.45 | ui | — | — | — |
| `UI_FULLSCREEN_ENTER` | 0.40 | ui | — | — | — |
| `UI_FULLSCREEN_EXIT` | 0.40 | ui | — | — | — |
| `UI_NOTIFICATION` | 0.50 | ui | — | — | — |
| `UI_ERROR` | 0.55 | ui | — | — | — |
| Any other `UI_*` | 0.50 | ui | — | — | — |

### Voice-Over

| Stage | Volume | Bus | Fade In | Fade Out | Loop |
|-------|--------|-----|---------|----------|------|
| `VO_WIN_*` | 0.80 | voice | — | — | — |
| `VO_BIG_WIN` | 0.85 | voice | — | — | — |
| `VO_CONGRATULATIONS` | 0.80 | voice | — | — | — |
| `VO_INCREDIBLE` | 0.85 | voice | — | — | — |
| `VO_SENSATIONAL` | 0.85 | voice | — | — | — |
| `VO_BONUS` | 0.80 | voice | — | — | — |
| Any other `VO_*` | 0.80 | voice | — | — | — |

### Default Priority

When resolving parameters for a stage, the system uses this priority (highest first):

1. **ASSIGN tab settings** — designer manually set volume/bus/fade
2. **Exact stage default** — e.g., `REEL_STOP_0` has specific defaults
3. **Wildcard stage default** — e.g., `REEL_STOP_*` matches any reel index
4. **Category default** — e.g., any `UI_*` stage gets volume 0.50, bus ui
5. **Global fallback** — volume 1.0, bus sfx, no fade, no loop

---

## Complete Stage Reference

### SFX Stages (sfx_ prefix)

#### Spin Lifecycle
```
sfx_spin_start                  sfx_reel_spin_loop
sfx_reel_stop_1 .. _5           sfx_spin_end
sfx_slam_stop                   sfx_quick_stop
sfx_spin_acceleration           sfx_spin_deceleration
sfx_reel_shake                  sfx_reel_wiggle
sfx_reel_slow_stop              sfx_reel_nudge
sfx_spin_cancel
```

#### Anticipation
```
sfx_anticipation_tension        sfx_anticipation_off
sfx_anticipation_miss
sfx_anticipation_tension_r3     sfx_anticipation_tension_r4
```

#### Wins
```
sfx_win_low                     sfx_win_equal
sfx_win_tier_1 .. _8            sfx_win_end
sfx_rollup_start                sfx_rollup_tick
sfx_rollup_tick_fast            sfx_rollup_tick_slow
sfx_rollup_acceleration         sfx_rollup_deceleration
sfx_rollup_end                  sfx_rollup_skip
sfx_win_line_show               sfx_win_line_hide
sfx_win_line_cycle              sfx_win_symbol_highlight
```

#### Big Wins
```
sfx_big_win_start               sfx_big_win_end
sfx_big_win_tier_1 .. _8
sfx_big_win_trigger             sfx_big_win_tick_start
sfx_big_win_tick_end
sfx_coin_shower_start           sfx_coin_shower_end
```

#### Scatter & Wild
```
sfx_scatter_land                sfx_scatter_land_1 .. _5
sfx_wild_land                   sfx_wild_expand
sfx_wild_expand_start           sfx_wild_expand_step
sfx_wild_expand_end             sfx_wild_expand_fill
sfx_wild_sticky                 sfx_wild_sticky_land
sfx_wild_walk_left              sfx_wild_walk_right
sfx_wild_transform              sfx_wild_multiply
sfx_wild_spread                 sfx_wild_nudge
sfx_wild_stack                  sfx_wild_upgrade
sfx_wild_collect                sfx_wild_random
```

#### Features
```
sfx_feature_enter               sfx_feature_exit
sfx_feature_step
sfx_freespin_trigger            sfx_freespin_start
sfx_freespin_end                sfx_freespin_retrigger
```

#### Cascade / Tumble
```
sfx_cascade_start               sfx_cascade_end
sfx_cascade_step                sfx_cascade_step_1 .. _6
sfx_cascade_pop                 sfx_cascade_symbol_pop
sfx_cascade_symbol_drop         sfx_cascade_symbol_land
sfx_cascade_chain_start         sfx_cascade_chain_end
sfx_cascade_anticipation        sfx_cascade_mega
```

#### Multiplier
```
sfx_multiplier_increase         sfx_multiplier_apply
sfx_multiplier_x2               sfx_multiplier_x3
sfx_multiplier_x5               sfx_multiplier_x10
sfx_multiplier_x25              sfx_multiplier_x50
sfx_multiplier_x100
sfx_multiplier_land             sfx_multiplier_max
sfx_multiplier_reset            sfx_multiplier_stack
```

#### Hold & Win
```
sfx_hold_trigger                sfx_hold_start
sfx_hold_end                    sfx_hold_win_total
sfx_prize_reveal                sfx_prize_upgrade
sfx_grand_trigger
```

#### Gamble
```
sfx_gamble_start                sfx_gamble_enter
sfx_gamble_offer                sfx_gamble_win
sfx_gamble_lose                 sfx_gamble_double
sfx_gamble_half                 sfx_gamble_collect
sfx_gamble_exit
sfx_gamble_card_flip            sfx_gamble_color_pick
sfx_gamble_suit_pick            sfx_gamble_ladder_step
sfx_gamble_ladder_fall
```

#### Jackpot
```
sfx_jackpot_trigger             sfx_jackpot_eligible
sfx_jackpot_progress            sfx_jackpot_buildup
sfx_jackpot_reveal
sfx_jackpot_mini                sfx_jackpot_minor
sfx_jackpot_major               sfx_jackpot_grand
sfx_jackpot_mega                sfx_jackpot_ultra
sfx_jackpot_present             sfx_jackpot_award
sfx_jackpot_rollup              sfx_jackpot_bells
sfx_jackpot_sirens              sfx_jackpot_celebration
sfx_jackpot_collect             sfx_jackpot_end
```

#### Bonus
```
sfx_bonus_trigger               sfx_bonus_enter
sfx_bonus_exit                  sfx_bonus_win
sfx_bonus_step                  sfx_bonus_summary
sfx_bonus_total
```

#### Near Miss
```
sfx_near_miss                   sfx_near_miss_scatter
sfx_near_miss_bonus             sfx_near_miss_wild
sfx_near_miss_jackpot           sfx_near_miss_feature
```

#### Respin
```
sfx_respin_trigger              sfx_respin_start
sfx_respin_spin                 sfx_respin_stop
sfx_respin_end                  sfx_respin_reset
sfx_respin_retrigger            sfx_respin_last
```

#### Pick Bonus
```
sfx_pick_bonus_start            sfx_pick_bonus_end
sfx_pick_reveal                 sfx_pick_collect
sfx_pick_hover                  sfx_pick_chest_open
sfx_pick_good                   sfx_pick_bad
sfx_pick_multiplier             sfx_pick_upgrade
```

#### Wheel
```
sfx_wheel_start                 sfx_wheel_spin
sfx_wheel_tick                  sfx_wheel_slow
sfx_wheel_land                  sfx_wheel_anticipation
sfx_wheel_near_miss             sfx_wheel_celebration
sfx_wheel_prize                 sfx_wheel_bonus
sfx_wheel_multiplier            sfx_wheel_jackpot_land
```

#### Collect & Coins
```
sfx_coin_burst                  sfx_coin_drop
sfx_coin_land                   sfx_coin_collect
sfx_coin_collect_all            sfx_coin_rain
sfx_coin_shower                 sfx_coin_upgrade
sfx_coin_value_reveal           sfx_coin_lock
sfx_collect_trigger             sfx_collect_coin
sfx_collect_symbol              sfx_collect_meter_fill
sfx_collect_meter_full          sfx_collect_payout
sfx_collect_fly_to              sfx_collect_impact
sfx_collect_upgrade             sfx_collect_complete
```

#### Megaways
```
sfx_megaways_reveal             sfx_megaways_expand
sfx_megaways_shift              sfx_megaways_max
sfx_megaways_row_add            sfx_megaways_row_remove
sfx_megaways_top_reel           sfx_megaways_mystery
```

#### Symbol Wins (per pay level)
```
sfx_hp1_win .. sfx_hp4_win      (high pay symbols)
sfx_mp1_win .. sfx_mp5_win      (medium pay symbols)
sfx_lp1_win .. sfx_lp6_win      (low pay symbols)
```

#### Celebration & VFX
```
sfx_screen_shake                sfx_light_flash
sfx_confetti_burst              sfx_win_fanfare
sfx_fireworks_launch            sfx_fireworks_explode
sfx_game_ready                  sfx_game_start
```

### MUS Stages (mus_ prefix)

```
mus_base_game_l1 .. l5          mus_base_game_intro
mus_base_game_outro

mus_freespin_l1 .. l5           mus_freespin_intro
mus_freespin_outro              mus_freespin_end

mus_bonus_l1 .. l5              mus_bonus_intro
mus_bonus_outro

mus_hold_l1 .. l5               mus_hold_intro
mus_hold_outro

mus_jackpot_l1 .. l5            mus_jackpot_intro
mus_jackpot_outro

mus_gamble_l1 .. l5             mus_gamble_intro
mus_gamble_outro

mus_reveal_l1 .. l5             mus_reveal_intro
mus_reveal_outro

mus_tension_low                 mus_tension_med
mus_tension_high                mus_tension_max
mus_buildup                     mus_climax
mus_resolve                     mus_wind_down

mus_stinger_win                 mus_stinger_feature
mus_stinger_jackpot             mus_stinger_bonus
mus_stinger_alert

mus_big_win
```

### AMB Stages (amb_ prefix)

```
amb_base_game                   amb_freespin
amb_bonus                       amb_hold
amb_big_win                     amb_jackpot
amb_gamble

amb_attract_loop                amb_attract_exit
amb_idle_loop                   amb_idle_to_active
```

### TRN Stages (trn_ prefix)

```
trn_to_base                     trn_to_freespin
trn_to_bonus                    trn_to_feature
trn_to_jackpot                  trn_to_gamble
trn_fade_in                     trn_fade_out
trn_swoosh                      trn_impact
trn_reveal                      trn_stinger
```

### UI Stages (ui_ prefix)

```
ui_spin_press                   ui_spin_hover
ui_spin_release                 ui_stop_press
ui_bet_up                       ui_bet_down
ui_bet_max                      ui_bet_min
ui_menu_open                    ui_menu_close
ui_menu_hover                   ui_menu_select
ui_tab_switch                   ui_page_flip
ui_scroll
ui_autoplay_start               ui_autoplay_stop
ui_turbo_on                     ui_turbo_off
ui_settings_open                ui_settings_close
ui_paytable_open                ui_paytable_close
ui_rules_open                   ui_help_open
ui_fullscreen_enter             ui_fullscreen_exit
ui_button_press                 ui_button_hover
ui_info_press
ui_notification                 ui_alert
ui_error                        ui_warning
ui_popup_open                   ui_popup_close
ui_tooltip_show                 ui_tooltip_hide
ui_checkbox_on                  ui_checkbox_off
ui_slider_drag                  ui_slider_release
ui_sound_on                     ui_sound_off
ui_volume_change
```

### VO Stages (vo_ prefix)

```
vo_win_1 .. _5                  vo_big_win
vo_congratulations              vo_incredible
vo_sensational                  vo_bonus
```

---

## Example Project Folder

A complete 5-reel slot game "Zeus Thunderbolt" with 50+ audio files:

```
zeus_thunderbolt_audio/
│
│── sfx_spin_start.wav
│── sfx_reel_spin_loop.wav
│── sfx_reel_stop_1.wav
│── sfx_reel_stop_2_variant_a.wav
│── sfx_reel_stop_2_variant_b.wav
│── sfx_reel_stop_2_variant_c.wav
│── sfx_reel_stop_3.wav
│── sfx_reel_stop_4.wav
│── sfx_reel_stop_5.wav
│── sfx_spin_end.wav
│── sfx_slam_stop.wav
│── sfx_quick_stop.wav
│
│── sfx_anticipation_tension.wav
│── sfx_anticipation_tension_r3.wav
│── sfx_anticipation_tension_r4.wav
│── sfx_anticipation_off.wav
│
│── sfx_win_tier_1.wav
│── sfx_win_tier_2.wav
│── sfx_win_tier_3.wav
│── sfx_win_tier_4.wav
│── sfx_win_tier_5.wav
│── sfx_rollup_tick_variant_a.wav
│── sfx_rollup_tick_variant_b.wav
│── sfx_rollup_tick_variant_c.wav
│── sfx_rollup_tick_variant_d.wav
│── sfx_rollup_end.wav
│
│── sfx_big_win_start_layer1.wav
│── sfx_big_win_start_layer2.wav
│── sfx_big_win_tier_1.wav
│── sfx_big_win_tier_2.wav
│── sfx_big_win_tier_3.wav
│── sfx_big_win_end.wav
│
│── sfx_scatter_land.wav
│── sfx_scatter_land_3.wav
│── sfx_scatter_land_4.wav
│── sfx_wild_land.wav
│── sfx_wild_expand.wav
│
│── sfx_feature_enter.wav
│── sfx_feature_exit.wav
│── sfx_freespin_trigger.wav
│── sfx_freespin_start.wav
│── sfx_freespin_end.wav
│
│── sfx_cascade_step_variant_a.wav
│── sfx_cascade_step_variant_b.wav
│── sfx_cascade_step_variant_c.wav
│── sfx_cascade_pop.wav
│
│── mus_base_game_l1.wav
│── mus_base_game_l2.wav
│── mus_base_game_l3.wav
│── mus_freespin_l1.wav
│── mus_freespin_l2.wav
│── mus_big_win.wav
│── mus_tension_high.wav
│
│── amb_base_game.wav
│── amb_freespin.wav
│── amb_attract_loop.wav
│── amb_idle_loop.wav
│
│── trn_to_freespin.wav
│── trn_to_base.wav
│── trn_swoosh.wav
│
│── ui_spin_press.wav
│── ui_bet_up.wav
│── ui_bet_down.wav
│── ui_menu_open.wav
│── ui_menu_close.wav
│
│── vo_big_win_variant_a.wav
│── vo_big_win_variant_b.wav
└── vo_big_win_variant_c.wav
```

---

## Rename Tool

FluxForge Studio includes a **Rename Tool** that converts non-FFNC filenames to FFNC format.

### How It Works

1. Select a source folder with original audio files
2. The tool uses the existing 150+ alias system to identify each file's stage
3. Generates FFNC-compliant names with the correct prefix
4. Shows a preview table for review and manual corrections
5. Copies files to an output folder with new names (originals are never modified)

### Example

| Original | FFNC Name |
|----------|-----------|
| `004_ReelStop_2.wav` | `sfx_reel_stop_2.wav` |
| `BG_Music_Level3.wav` | `mus_base_game_l3.wav` |
| `big win loop.wav` | `sfx_big_win_start.wav` |
| `SFX_SpinButton_Click.wav` | `ui_spin_press.wav` |
| `scatter_land_reel3.wav` | `sfx_scatter_land_3.wav` |
| `FS_active_1.wav` | `mus_freespin_l1.wav` |
| `coins_small.wav` | `sfx_win_tier_1.wav` |
| `tension_build_long.wav` | `sfx_anticipation_tension_r4.wav` |
| `bg_ambient_loop.wav` | `amb_base_game.wav` |
| `attract_mode.wav` | `amb_attract_loop.wav` |

Unmatched files are flagged for manual assignment via a dropdown stage selector.

---

## FFNC Detection

The parser determines if a file uses FFNC format by checking for a known prefix:

```
Starts with sfx_ → FFNC
Starts with mus_ → FFNC
Starts with amb_ → FFNC
Starts with trn_ → FFNC
Starts with ui_  → FFNC
Starts with vo_  → FFNC
Anything else    → Legacy (use alias matching)
```

Legacy files continue to work through the existing 150+ alias fuzzy matching system. FFNC and legacy files can coexist in the same folder.

---

## Audio Format Support

FFNC applies to the filename only. The following audio formats are supported:

- `.wav` (recommended)
- `.mp3`
- `.ogg`
- `.flac`
- `.aiff` / `.aif`
