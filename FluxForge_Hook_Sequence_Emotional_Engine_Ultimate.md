# FLUXFORGE SLOT LAB
# HOOK-SEQUENCE EMOTIONAL ENGINE
# ULTIMATE ENTERPRISE SPECIFICATION v1.0
# Generated: 2026-02-24

---
# 0. PURPOSE

Complete deterministic Emotional Engine model for FluxForge SlotLab.
Input: Engine hook sequence only.
No RTP. No metadata. No randomness. Fully bakeable.

---
# 1. RUNTIME INPUT MODEL

Example hook sequence:

onBaseGameStart
onSpinStart
onReelStop_r1
onReelStop_r2
onReelStop_r3
onReelStop_r4
onReelStop_r5
onWinEvaluate
onSpinEnd

Hook order is the only truth.

---
# 2. DETERMINISTIC COUNTERS

GLOBAL
- spin_index
- session_spin_counter

WIN/LOSS
- consecutive_no_win_spins
- consecutive_win_spins
- last_win_spin_index

CASCADE
- current_cascade_depth
- max_cascade_depth_this_spin

REEL
- reel_stop_counter

All reset on onBaseGameStart.

---
# 3. COUNTER UPDATE RULES

onBaseGameStart:
  spin_index = 0
  consecutive_no_win_spins = 0
  consecutive_win_spins = 0
  emotional_state = "NEUTRAL"
  emotional_intensity = 0.0

onSpinStart:
  spin_index += 1
  reel_stop_counter = 0
  current_cascade_depth = 0

onReelStop_rX:
  reel_stop_counter += 1

onCascadeStep:
  current_cascade_depth += 1

onWinEvaluate:
  if win_detected:
    consecutive_win_spins += 1
    consecutive_no_win_spins = 0
    last_win_spin_index = spin_index
  else:
    consecutive_no_win_spins += 1
    consecutive_win_spins = 0

---
# 4. EMOTIONAL STATES

NEUTRAL
BUILD
TENSION
NEAR_WIN
PEAK
AFTERGLOW
RECOVERY

---
# 5. STATE TRANSITIONS

NEUTRAL → BUILD
if consecutive_no_win_spins >= 2

BUILD → TENSION
if consecutive_no_win_spins >= 3
and reel_stop_counter == TOTAL_REELS

TENSION → PEAK
if current_cascade_depth >= 2
or consecutive_win_spins >= 2

PEAK → AFTERGLOW
if win_detected == true and onSpinEnd

AFTERGLOW → RECOVERY
if spin_index - last_win_spin_index >= 1

RECOVERY → NEUTRAL
if consecutive_no_win_spins == 0

---
# 6. INTENSITY FORMULA

base_intensity =
  (consecutive_no_win_spins * 0.08) +
  (current_cascade_depth * 0.15) +
  (consecutive_win_spins * 0.20)

Clamp to 1.0

---
# 7. DETERMINISTIC DECAY

Decay applied once per spin:

emotional_intensity = emotional_intensity * 0.85

No time-based decay.

---
# 8. ORCHESTRATION INTEGRATION

REEL_STOP:
  gain_bias = intensity * 0.4
  stereo_width = 1.0 + (intensity * 0.3)
  delay_ms = intensity * 20

WIN_BIG:
  transient_boost = intensity * 0.6
  center_focus = intensity

---
# 9. BAKE OUTPUT FILES

hook_to_behavior_map.json
behavior_properties.json
emotional_transition_table.json
orchestration_matrix.json
voice_allocation_table.json
decay_config.json

---
# 10. SAMPLE emotional_transition_table.json

{
  "states": ["NEUTRAL","BUILD","TENSION","NEAR_WIN","PEAK","AFTERGLOW","RECOVERY"],
  "transitions": [
    {"from":"NEUTRAL","to":"BUILD","rule":"consecutive_no_win_spins>=2"},
    {"from":"BUILD","to":"TENSION","rule":"consecutive_no_win_spins>=3 && reel_stop_counter==TOTAL_REELS"},
    {"from":"TENSION","to":"PEAK","rule":"current_cascade_depth>=2 || consecutive_win_spins>=2"}
  ]
}

---
# 11. SAMPLE decay_config.json

{
  "decay_factor_per_spin": 0.85,
  "min_intensity_threshold": 0.05,
  "reset_on_base_game_start": true
}

---
# 12. SAMPLE orchestration_matrix.json

{
  "REEL_STOP": {
    "gain_multiplier": 0.4,
    "width_multiplier": 0.3,
    "delay_multiplier_ms": 20
  },
  "WIN_BIG": {
    "transient_multiplier": 0.6,
    "center_focus_multiplier": 1.0
  }
}

---
# 13. DETERMINISM GUARANTEE

Identical hook sequence → identical audio result.

No randomness.
No real-time clock.
Fully QA reproducible.

---
# END
