# FluxForge Slot Audio Naming Bible v1.0 (AUREXIS-Ready)
**Scope:** Slot games only • Authoring/Preview/Runtime • SFX + UI + Music + System + Jackpot + Feature mechanics  
**Goal:** 100% machine-parseable, deterministic, scalable to 300–1000+ events, zero ambiguity.  
**Last updated:** 2026-02-24

---

## 0) Non‑Negotiables (Locked Rules)

1. **lowercase only**  
2. **underscore `_` only** as separator (no spaces, no hyphens)  
3. **no ambiguous numbers** (numbers must be prefixed by a meaning token: `r5`, `c3`, `m10`, `p2`, `g6x5`, `t120ms`, etc.)  
4. **no “final”, “new”, “test”, “fix”, “old”** in filenames (use structured tokens)  
5. **no duplicate meaning** (don’t encode reel index twice, don’t encode variant twice)  
6. **stable canonical naming**: once shipped, names are immutable (use version tokens for changes)  
7. **one filename = one intent** (if behavior differs, the name must differ)  
8. **variant ≠ index** (e.g., `r3` is reel index; `v2` is alternate take)  
9. **portable**: names must not rely on OS path semantics or diacritics  
10. **AUREXIS must be able to parse** the intent without opening the file.

---

## 1) Canonical Filename Grammar

### 1.1 Core Structure (Recommended “Ultimate”)

```
<phase>_<system>_<action>_<context>_<modifiers>_<variant>.<ext>
```

- All segments are optional **except**: `phase`, `system`, `action` (for SFX/UI).  
- `context` is strongly recommended whenever it affects behavior (anticipation, last, turbo, etc.).  
- `modifiers` is a **bag** of tokens in a strict order (below).  
- `variant` is optional, used only for alternate takes (v1, v2…).  

### 1.2 Modifier Order (Strict if present)

```
positional → mechanic-depth → level/tier → timing → device → perspective → intensity → seed/uid → version
```

In practice (most common):
```
rX / colX / rowX / pX  → cX / kX / sX → mX / jt_* → tXms / bpmX → mob/desk/head → near/far → iX → uidX → verX
```

### 1.3 Allowed Extensions
Choose per your pipeline, but naming stays identical across formats:
- `.wav` (authoring, source)
- `.ogg`, `.aac`, `.m4a` (runtime, depending on platform)
- `.flac` (optional archival)

**Rule:** the **basename must match** across derived encodes.
Example:
- `base_reel_stop_r3_last_v2.wav`
- `base_reel_stop_r3_last_v2.ogg`
- `base_reel_stop_r3_last_v2.m4a`

---

## 2) Token Dictionaries

### 2.1 PHASE (First token; mandatory)
| Token | Meaning |
|---|---|
| `base` | Base game loop / normal play |
| `feature` | Feature/bonus system (generic) |
| `bonus` | Free spins or bonus mode (explicit) |
| `jackpot` | Jackpot systems & tiers |
| `ui` | UI interactions / menus / overlays |
| `system` | Boot, error, compliance, connectivity |
| `ambient` | Environmental beds / atmos |
| `music` | Music layers, stingers |
| `meta` | Tools/diagnostics-only assets (not shipped) |

> If you must split base modes: use `base` + context (`normal`, `turbo`, `autoplay`).

### 2.2 SYSTEM (Mechanic / subsystem; mandatory)
| Token | Meaning |
|---|---|
| `spin` | Spin cycle / core |
| `reel` | Reel motion / stop / land |
| `cascade` | Tumble/cascade |
| `cluster` | Cluster explode / pay |
| `symbol` | Symbol-specific events |
| `grid` | Grid expansion/shrink |
| `hold` | Hold & Win / lock mechanics |
| `respin` | Respin mode |
| `multiplier` | Multiplier add/stack/collect |
| `collect` | Collector symbols / bank |
| `transform` | Symbol transform / morph |
| `nudge` | Nudge, slide, shift |
| `win` | Win tiers and win logic |
| `countup` | Rollup / counter |
| `feature` | Feature entry/loop/exit |
| `jackpot` | Jackpot flow |
| `ladder` | Progress ladder / meter |
| `reveal` | Mystery reveal, unveil |
| `wheel` | Wheel bonus |
| `pick` | Pick bonus |
| `attract` | Attract mode |
| `voice` | VO lines |
| `music` | Music system hooks |
| `ambient` | Ambient system hooks |

### 2.3 ACTION (Verb; mandatory)
Common verbs (expand as needed, but keep consistent):
`start`, `stop`, `land`, `impact`, `step`, `tick`, `add`, `stack`, `collect`, `reset`, `lock`, `unlock`, `expand`, `shrink`, `explode`, `transform`, `reveal`, `intro`, `loop`, `outro`, `enter`, `exit`, `trigger`, `open`, `close`, `select`, `confirm`, `cancel`, `error`, `notify`, `idle`, `resume`, `pause`

### 2.4 CONTEXT (State / scenario; recommended)
Use when it changes perception/priority:
`normal`, `anticipation`, `tension`, `last`, `final`, `chain`, `combo`, `near`, `max`, `boost`, `super`, `mega`, `ultra`, `turbo`, `slow`, `autoplay`, `manual`, `bonus`, `free`, `locked`, `stacked`, `expanded`, `critical`, `fail`, `success`, `entering`, `exiting`

### 2.5 VARIANT (Alternate take; optional)
- `v1`, `v2`, `v3`… (preferred)
- `alt1`, `alt2`… (only if you need a named family; avoid if possible)

**Rule:** variant is the **last creative token** (before optional `uid/ver`).

---

## 3) Positional / Index Tokens (No ambiguity)

### 3.1 Reel Index (most important)
- `r1`, `r2`, … `r6` (or higher)
Examples:
- `base_reel_stop_r1.wav`
- `base_reel_stop_r5_last.wav`
- `base_reel_land_r3_anticipation_v2.wav`

### 3.2 Grid Coordinates (use only when needed)
- Column: `col1..colN`
- Row: `row1..rowN`
Examples:
- `base_symbol_land_col3_row2.wav`
- `feature_hold_symbol_lock_col5_row1.wav`

### 3.3 Payline / Ways / Cluster Size
- Payline: `p1..p50`
- Cluster size: `k5`, `k12`
Examples:
- `base_win_line_p7.wav`
- `base_cluster_explode_k9.wav`

### 3.4 Step / Chain / Sequence
- Cascade chain depth: `c1..c20`
- Scripted sequence step: `s1..s99`
Examples:
- `base_cascade_step_c3.wav`
- `feature_intro_s2.wav`

### 3.5 Multiplier Level
- `m2`, `m3`, `m5`, `m10`, etc.
Examples:
- `base_multiplier_add_m2.wav`
- `base_multiplier_collect_m10_v2.wav`

### 3.6 Jackpot Tier
- `jt_mini`, `jt_minor`, `jt_major`, `jt_grand`, `jt_mega`
Examples:
- `jackpot_intro_jt_grand.wav`
- `jackpot_loop_jt_major.wav`

### 3.7 Grid Size / Layout
- `g5x3`, `g6x5`, `g7x7`
Examples:
- `base_reel_stop_r5_g5x3.wav`
- `cluster_explode_k12_g6x5.wav`

### 3.8 Time / Tempo (only if needed)
- `t120ms`, `t1s`
- `bpm120`
Examples:
- `countup_tick_t120ms.wav`
- `music_stinger_bpm128.wav`

---

## 4) Slot Coverage: Naming by Mechanic (Complete Scenarios)

### 4.1 Base Spin Cycle + Reels
```
base_spin_start.wav
base_spin_stop.wav

base_reel_start_r1.wav
base_reel_start_r2.wav
base_reel_start_r3.wav
base_reel_start_r4.wav
base_reel_start_r5.wav

base_reel_stop_r1.wav
base_reel_stop_r2.wav
base_reel_stop_r3.wav
base_reel_stop_r4.wav
base_reel_stop_r5_last.wav

base_reel_land_r1_normal.wav
base_reel_land_r2_normal.wav
base_reel_land_r3_normal.wav
base_reel_land_r4_normal.wav
base_reel_land_r5_last.wav

base_reel_land_r3_anticipation.wav
base_reel_land_r4_anticipation.wav
base_reel_land_r5_last_anticipation.wav
```

### 4.2 Cascades / Tumble (with chain depth)
```
base_cascade_start.wav
base_cascade_step_c1.wav
base_cascade_step_c2.wav
base_cascade_step_c3.wav
base_cascade_impact.wav
base_cascade_end.wav
base_cascade_end_final.wav
```

### 4.3 Cluster Explode / Pop (with cluster size)
```
base_cluster_explode_k5.wav
base_cluster_explode_k9.wav
base_cluster_explode_k12.wav
base_cluster_pay_confirm.wav
```

### 4.4 Hold & Win / Lock / Add / Collect (complete state machine)
```
feature_hold_intro.wav
feature_hold_start.wav
feature_hold_symbol_lock.wav
feature_hold_symbol_add.wav
feature_hold_collect.wav
feature_hold_respin_start.wav
feature_hold_respin_end.wav
feature_hold_countdown_tick.wav
feature_hold_end.wav
feature_hold_outro.wav
```

With symbol types:
```
feature_hold_symbol_lock_sym_cash.wav
feature_hold_symbol_lock_sym_collector.wav
```

### 4.5 Respin (generic)
```
feature_respin_intro.wav
feature_respin_start.wav
feature_respin_loop.wav
feature_respin_stop.wav
feature_respin_end.wav
```

### 4.6 Multiplier (levels)
```
base_multiplier_add_m2.wav
base_multiplier_add_m5.wav
base_multiplier_stack.wav
base_multiplier_collect.wav
base_multiplier_reset.wav
```

### 4.7 Mystery Reveal / Transform
```
base_reveal_start.wav
base_reveal_step_s1.wav
base_reveal_step_s2.wav
base_reveal_end.wav

base_transform_sym_mystery_to_sym_wild.wav
base_transform_sym_mystery_to_sym_scatter.wav
```

### 4.8 Grid Expand / Shrink / Upgrade
```
base_grid_expand.wav
base_grid_expand_g6x5.wav
base_grid_shrink.wav
feature_grid_upgrade.wav
```

### 4.9 Nudge / Slide / Shift
```
base_nudge_left_r2.wav
base_nudge_right_r4.wav
base_reel_shift_r3.wav
```

### 4.10 Feature Types (Wheel / Pick / Ladder)
Wheel:
```
feature_wheel_intro.wav
feature_wheel_spin.wav
feature_wheel_stop.wav
feature_wheel_outro.wav
```

Pick:
```
feature_pick_intro.wav
feature_pick_select.wav
feature_pick_reveal.wav
feature_pick_outro.wav
```

Ladder/Meter:
```
feature_ladder_tick.wav
feature_ladder_levelup.wav
feature_ladder_near.wav
feature_ladder_max.wav
```

### 4.11 Jackpot (tiers)
```
jackpot_intro_jt_mini.wav
jackpot_intro_jt_major.wav
jackpot_reveal_jt_grand.wav
jackpot_loop_jt_major.wav
jackpot_outro_jt_grand.wav
```

---

## 5) Win System (tiers + rollup + skip)

### 5.1 Tiered wins
```
base_win_small.wav
base_win_med.wav
base_win_big.wav
base_win_mega.wav
```

### 5.2 Rollup / Countup
```
base_countup_start.wav
base_countup_tick.wav
base_countup_tick_t120ms.wav
base_countup_end.wav
base_countup_skip.wav
```

### 5.3 Impact vs Loop vs Outro (big wins)
```
base_win_big_impact.wav
base_win_big_loop.wav
base_win_big_outro.wav
```

---

## 6) UI (complete, production-safe)

```
ui_button_click.wav
ui_button_click_v2.wav
ui_bet_up.wav
ui_bet_down.wav
ui_autoplay_open.wav
ui_autoplay_start.wav
ui_autoplay_stop.wav
ui_popup_open.wav
ui_popup_close.wav
ui_settings_open.wav
ui_settings_close.wav
ui_paytable_open.wav
ui_paytable_close.wav
ui_confirm.wav
ui_cancel.wav
ui_error_notify.wav
```

---

## 7) System / Compliance / Network

```
system_boot_start.wav
system_boot_ready.wav
system_error_soft.wav
system_error_hard.wav
system_network_drop.wav
system_network_restore.wav
system_audio_mute.wav
system_audio_unmute.wav

system_rg_timeout_warning.wav
system_rg_limit_reached.wav
system_compliance_error.wav
```

---

## 8) Music (layered slot music)

### 8.1 Core loops (3 intensity layers)
```
music_base_l1_loop.wav
music_base_l2_loop.wav
music_base_l3_loop.wav
music_bonus_l1_loop.wav
music_bonus_l2_loop.wav
music_bonus_l3_loop.wav
```

### 8.2 Transitions / Stingers
```
music_transition_base_to_bonus_stinger.wav
music_transition_l1_to_l2_swell.wav
music_transition_l2_to_l3_swell.wav
music_bigwin_stinger_i3.wav
```

### 8.3 Stems (optional)
```
music_base_l2_stem_drums.wav
music_base_l2_stem_bass.wav
music_base_l2_stem_harmony.wav
music_base_l2_stem_melody.wav
```

---

## 9) Advanced Tokens (Use only if you truly need them)

### 9.1 Device profile tokens
- `desk`, `mob`, `head` (desktop/mobile/headphones)
Example:
- `ui_button_click_mob.wav` (only if you ship separate assets)

### 9.2 Perspective tokens
- `near`, `far` (rare in slot, but useful if you do “depth” assets)
Example:
- `base_reel_land_r3_near.wav`

### 9.3 Intensity index (when you need authored scaling tiers)
- `i1..i5`
Example:
- `base_win_big_impact_i4.wav`

### 9.4 UID (tools-only, not hand-authored)
- `uid<hash>` (generated by pipeline)
Example:
- `meta_orphan_uid8f3a12.wav`

---

## 10) “Impossible scenario” policy (What to do when your game invents a new mechanic)

If a mechanic is new:
1. Create a new **system token** (single word)
2. Lock it in the project dictionary
3. Follow the same grammar

Example new mechanic “portal”:
- `feature_portal_open.wav`
- `feature_portal_travel_step_s1.wav`
- `feature_portal_close.wav`

No hacks, no ad-hoc names.

---

## 11) Strict Validator Rules (for your pipeline)

Reject any filename that:
- contains uppercase
- contains spaces or hyphens
- contains digits not preceded by a meaning token
- contains banned words: `final`, `new`, `test`, `temp`, `old`
- has unknown phase token
- has unknown system token (unless explicitly whitelisted in project dictionary)

---

## 12) AUREXIS AutoBind Expectations (How naming maps to left-panel events)

**Your left panel should display design-friendly event keys** that match the `system_action_context_*` shape.
Examples:
- `reel_stop_r1`
- `reel_land_r3_anticipation`
- `cascade_step_c2`
- `hold_symbol_lock`
- `jackpot_reveal_jt_grand`
- `ui_bet_up`

Then AutoBind becomes:
- **string token match** → **behavior group** → **event bind**

---

## 13) Anti-Patterns (Hard No)

- `reelstop1.wav`
- `impact_01.wav`
- `bigwinfinalv3.wav`
- `sound_final.wav`
- `new_click.wav`
- `spin-start.wav`

Replace with canonical names.

---

## 14) Quick Reference (Most common patterns)

### Reels
- `base_reel_stop_rX[_context][_vN].wav`
- `base_reel_land_rX[_context][_vN].wav`

### Cascade
- `base_cascade_step_cX[_context][_vN].wav`

### Multiplier
- `base_multiplier_add_mX[_vN].wav`

### Jackpot
- `jackpot_intro_jt_<tier>[_vN].wav`

### UI
- `ui_<area>_<action>[_context][_vN].wav`

### Music
- `music_<phase>_l<1-3>_loop[_vN].wav`
- `music_transition_<from>_to_<to>_stinger.wav`

---

© FluxForge Studio • AUREXIS-ready Slot Naming Bible v1.0
