# Anticipation False Trigger Fix — Near Miss Control

**Datum:** 2026-02-01
**Commit:** `6e0b115b`
**Status:** ✅ RESOLVED

---

## Problem Statement

Anticipation audio se čuo na reel 3 i 4 **BEZ scatter ili bonus simbola**.

**User Report:** "Ubacio sam zvuk u anticipaci, i desilo se da se cula na cetvrtom i peton relu, a nije bilo uslova za aniticipaciju"

**Simptomi:**
- Anticipation triggered na reels 3-4
- Scatter count = 0
- Bonus count = 0
- No visual indicators for anticipation trigger

---

## Root Cause Analysis (7-Role Investigation)

### 🎮 Role 1: Slot Game Designer

**Expected:** Anticipation ONLY when 2+ scatters on first 2-3 reels
**Actual:** Anticipation triggered with NO scatters

### 🧠 Role 2: Audio Middleware Architect

**Analysis:** EventRegistry received `ANTICIPATION_ON` stages from provider
**Question:** Why did Rust engine generate anticipation without scatters?

### 🛠 Role 3: Engine Developer

**Investigation:** Checked `engine.rs` anticipation generation logic

**Found TWO anticipation paths:**

#### Path 1: Scatter-Based (engine.rs:604-618)
```rust
if let Some(ref scatter) = result.scatter_win {
    if scatter.count >= antic_config.min_trigger_count {
        if antic_config.is_trigger_symbol(self.paytable.scatter_id) {
            result.anticipation = AnticipationInfo::from_trigger_positions_with_config(...);
        }
    }
}
```
✅ **This path is CORRECT** — only triggers with scatters

#### Path 2: Near Miss (engine.rs:577-585) — **ROOT CAUSE**
```rust
// Near miss detection
if !result.is_win() {
    let near_miss_roll: f64 = self.rng.r#gen::<f64>();
    if near_miss_roll < vol.near_miss_frequency {  // 15-30% chance!
        result.near_miss = true;
        result.anticipation = Some(AnticipationInfo::from_reels(
            vec![3, 4],  // ← HARDCODED reels 3-4
            AnticipationReason::NearMiss,
            ...
        ));
    }
}
```
❌ **This path ALWAYS runs** — no config control!

**Near Miss Frequency (VolatilityProfile):**
- Low: 15%
- Medium: 20%
- High: 25%
- Very High: 30%

### 🔬 Role 4: QA Engineer

**Reproduction:**
1. Spin slot machine
2. Result: NO WIN (no scatters)
3. Random roll: < 0.15 (near miss triggered)
4. Engine sets `anticipation = Some([3, 4])`
5. Provider broadcasts `ANTICIPATION_ON` for reels 3-4
6. Audio plays on reels 3-4 WITHOUT any visual scatter triggers

**Frequency:** ~15-30% of all no-win spins

---

## Ultimate Solution (4-Layer Control)

### Layer 1: Config Flag (Rust)

**File:** `crates/rf-slot-lab/src/config.rs:385-394`

```rust
pub struct AnticipationConfig {
    // ... existing fields

    /// Enable near miss anticipation (2026-02-01)
    /// When false, near miss will NOT trigger anticipation effects
    /// When true, near miss uses volatility.near_miss_frequency (15-30% chance)
    /// Default: false (only scatter/bonus trigger anticipation)
    #[serde(default)]
    pub enable_near_miss_anticipation: bool,
}

impl Default for AnticipationConfig {
    fn default() -> Self {
        Self {
            // ... existing defaults
            enable_near_miss_anticipation: false,  // ← DISABLED by default
        }
    }
}
```

### Layer 2: Engine Logic (Rust)

**File:** `crates/rf-slot-lab/src/engine.rs`

**Location 1: Random Near Miss (lines 577-589)**
```rust
// Near miss detection (2026-02-01: Respects anticipation config)
if !result.is_win() {
    let near_miss_roll: f64 = self.rng.r#gen::<f64>();
    if near_miss_roll < vol.near_miss_frequency {
        result.near_miss = true;
        // Only set anticipation if enabled in config
        if self.config.anticipation.enable_near_miss_anticipation {
            result.anticipation = Some(AnticipationInfo::from_reels(...));
        }
    }
}
```

**Location 2: Forced Near Miss (lines 522-531)**
```rust
// Apply near miss flag (2026-02-01: Respects anticipation config)
if matches!(outcome, ForcedOutcome::NearMiss) {
    result.near_miss = true;
    // Only set anticipation if enabled in config
    if self.config.anticipation.enable_near_miss_anticipation {
        result.anticipation = Some(AnticipationInfo::from_reels(...));
    }
}
```

### Layer 3: Default Behavior

**All configs now have `enable_near_miss_anticipation: false`:**
- `AnticipationConfig::default()` → false
- `AnticipationConfig::tip_a()` → false
- `AnticipationConfig::tip_b()` → false

### Layer 4: Separation of Concerns

**Near miss flag vs Anticipation:**
- `result.near_miss = true` — STILL sets (for analytics, stats)
- `result.anticipation = None` — NOT set (no audio/visual effects)

---

## Behavior Matrix

| Condition | `enable_near_miss_anticipation` | `near_miss` flag | `anticipation` object | Audio/Visual |
|-----------|----------------------------------|------------------|-----------------------|--------------|
| No scatter, no near miss | N/A | false | None | No anticipation |
| No scatter, near miss (flag=false) | **false** | **true** | **None** | No anticipation ✓ |
| No scatter, near miss (flag=true) | **true** | **true** | **Some([3,4])** | Anticipation plays |
| 2+ scatters | N/A | N/A | Some([...]) | Anticipation plays ✓ |

---

## Verification

**Rust Tests:**
```bash
cargo test -p rf-slot-lab
# Result: 110 tests passed ✓
```

**Build:**
```bash
cargo build --release
# Result: Success ✓
```

**User Verification Required:**
- Spin without scatters → NO anticipation audio/visual
- Spin with 2+ scatters → anticipation triggers normally

---

## Files Modified

| File | Changes | Description |
|------|---------|-------------|
| `config.rs` | +8 lines | Added `enable_near_miss_anticipation` flag + defaults |
| `engine.rs` | +6 lines | Conditional anticipation creation |

---

## All 41 _END Stages

Auto fade-out system covers:

```
ANTICIPATION_BUILD_END, ANTICIPATION_END, BIGWIN_END, BIG_WIN_END,
BONUS_END, BONUS_INTRO_END, BONUS_MUSIC_END, CASCADE_CHAIN_END, CASCADE_END,
COLLECT_FLY_END, COLLECT_REWARD_END, EPICWIN_END, FEATURE_END,
FREESPINS_END, FREESPIN_END, FREESPIN_SPIN_END, FS_END, FS_INTRO_END,
FS_OUTRO_END, FS_SPIN_END, GAMBLE_END, GAMBLE_MUSIC_END, GAMBLE_SUSPENSE_END,
HOLD_COLLECT_END, HOLD_END, HOLD_RESPIN_END, IDLE_END, JACKPOT_BUILDUP_END,
JACKPOT_CELEBRATION_END, JACKPOT_COIN_SHOWER_END, JACKPOT_END,
JACKPOT_TICKER_END, MEGAWIN_END, MUSIC_CROSSFADE_END, MUSIC_DUCK_END,
RESPIN_END, ROLLUP_END, SESSION_END, UI_LOADING_END, WILD_EXPAND_END, WIN_END
```

**Exception:** `SPIN_END` (manual user control)

---

## Related Documentation

- `.claude/architecture/ANTICIPATION_SYSTEM.md` — Updated with near miss control
- `.claude/architecture/EVENT_SYNC_SYSTEM.md` — Auto fade-out system documentation
- `.claude/architecture/SLOT_LAB_AUDIO_FEATURES.md` — P0.6 anticipation features
