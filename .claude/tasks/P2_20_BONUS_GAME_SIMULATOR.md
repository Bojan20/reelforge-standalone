# P2.20 Bonus Game Simulator — Architecture Document

**Date:** 2026-01-22
**Status:** ✅ COMPLETED
**Completed:** 2026-01-23
**Priority:** P2 (Medium)

---

## Executive Summary

Implement complete bonus game simulation UI for SlotLab, building on existing 95% complete backend.

### Final State

| Feature | Backend | FFI | UI Config | UI Sim | Overall |
|---------|---------|-----|-----------|--------|---------|
| Free Spins | ✅ | ✅ | ✅ | ✅ | 100% |
| Hold & Win | ✅ | ✅ | ✅ | ✅ | 100% |
| Cascades | ✅ | ✅ | ✅ | ✅ | 100% |
| Jackpot | ✅ | ✅ | ✅ | ✅ | 100% |
| Gamble | ✅ | ✅ | ✅ | ✅ | 100% |
| Pick Bonus | ✅ | ✅ | ✅ | ✅ | 100% |
| Wheel Bonus | ❌ | ❌ | ❌ | ❌ | 0% (optional) |

### Implementation Summary

**Phase 1: Hold & Win** — ✅ Complete (already implemented)
- 12 FFI functions in `slot_lab_ffi.rs`
- `HoldAndWinVisualizer` widget (688 LOC)

**Phase 2: Pick Bonus FFI** — ✅ Complete
- Rust: `pick_bonus.rs` integrated in engine_v2.rs
- FFI: 9 functions added (`pick_bonus_is_active`, `make_pick`, `get_state_json`, etc.)
- Dart: `NativeFFI` bindings for Pick Bonus

**Phase 3: Gamble FFI** — ✅ Complete
- Rust: Gamble methods in engine_v2.rs
- FFI: 7 functions added (`gamble_is_active`, `make_choice`, `collect`, etc.)
- Dart: `NativeFFI` bindings for Gamble

**Phase 4: Unified Panel** — ✅ Complete
- `BonusSimulatorPanel` (780 LOC) — tabbed interface for all bonus types
- Quick trigger buttons, status badges
- FFI-driven state display

---

## Implementation Plan

### Phase 1: Hold & Win Simulator (1 day)

**1A. FFI Extensions** (`crates/rf-bridge/src/slot_lab_ffi.rs`)

```rust
#[no_mangle]
pub extern "C" fn slot_lab_get_hold_and_win_state_json() -> *mut c_char

#[no_mangle]
pub extern "C" fn slot_lab_hold_and_win_remaining_respins() -> i32

#[no_mangle]
pub extern "C" fn slot_lab_hold_and_win_fill_percentage() -> f64
```

**1B. Dart FFI Bindings** (`native_ffi.dart`)

```dart
String? getHoldAndWinStateJson()
int getHoldAndWinRespins()
double getHoldAndWinFillPercentage()
```

**1C. Hold & Win Grid Visualizer Widget**

```dart
// flutter_ui/lib/widgets/slot_lab/bonus/hold_and_win_visualizer.dart
class HoldAndWinVisualizer extends StatefulWidget {
  // Shows 3x5 grid with locked symbols
  // Tier badges (Mini/Minor/Major/Grand)
  // Respins counter with animation
  // Fill progress bar
}
```

### Phase 2: Pick Bonus Simulator (2 days)

**2A. Pick Bonus Chapter** (`crates/rf-slot-lab/src/features/pick_bonus.rs`)

```rust
pub struct PickBonusConfig {
    pub pick_count: u8,          // 3, 5, or 12 picks
    pub reveal_mode: RevealMode, // Instant, OneByOne, All
    pub prizes: Vec<PickPrize>,  // Multipliers, coins, FS, etc.
    pub poison_enabled: bool,    // End bonus early
}

pub enum PickPrize {
    Multiplier(f64),
    Coins(u64),
    FreeSpins(u8),
    AdvanceToNext,  // Next tier
    Poison,         // End bonus
}
```

**2B. Pick Bonus FFI**

```rust
#[no_mangle]
pub extern "C" fn slot_lab_pick_bonus_get_state_json() -> *mut c_char

#[no_mangle]
pub extern "C" fn slot_lab_pick_bonus_make_pick(index: i32) -> *mut c_char

#[no_mangle]
pub extern "C" fn slot_lab_pick_bonus_reveal_all() -> *mut c_char
```

**2C. Pick Bonus UI Widget**

```dart
// flutter_ui/lib/widgets/slot_lab/bonus/pick_bonus_panel.dart
class PickBonusPanel extends StatefulWidget {
  // Grid of clickable pick items (cards, gems, boxes)
  // Reveal animation with audio trigger
  // Prize accumulator display
  // Auto-pick option for testing
}
```

### Phase 3: Gamble Simulator (1 day)

**3A. Gamble UI in Game Model Editor**

Add to `game_model_editor.dart`:

```dart
Widget _buildGambleConfig(Map<String, dynamic> feature, int index) {
  // Game type selector (CardColor, CardSuit, CoinFlip, Ladder)
  // Max attempts slider (1-5)
  // Win multiplier input
  // Win cap input
}
```

**3B. Gamble Simulator Widget**

```dart
// flutter_ui/lib/widgets/slot_lab/bonus/gamble_simulator.dart
class GambleSimulator extends StatefulWidget {
  // Visual card/coin display
  // Choice buttons (Red/Black, Heads/Tails, etc.)
  // Stake display with animations
  // History ladder visualization
}
```

### Phase 4: Unified Bonus Panel (1 day)

**4A. Bonus Simulator Panel**

```dart
// flutter_ui/lib/widgets/slot_lab/bonus/bonus_simulator_panel.dart
class BonusSimulatorPanel extends StatefulWidget {
  // Tab bar: Free Spins | Hold & Win | Pick | Gamble | Wheel
  // Active bonus detection (auto-switch)
  // Manual trigger buttons
  // Audio event log filtered to bonus
}
```

**4B. Lower Zone Integration**

Add to `slotlab_lower_zone_controller.dart`:

```dart
enum SlotLabLowerZoneTab {
  // ... existing ...
  bonusSimulator,  // New tab (keyboard: B)
}
```

### Phase 5: Wheel Bonus (Optional, +2 days)

**5A. Wheel Bonus Chapter**

```rust
// crates/rf-slot-lab/src/features/wheel_bonus.rs
pub struct WheelBonusConfig {
    pub segments: Vec<WheelSegment>,
    pub spin_duration_ms: u32,
    pub pointer_position: PointerPosition,
}
```

**5B. Wheel Widget**

```dart
// flutter_ui/lib/widgets/slot_lab/bonus/wheel_bonus_widget.dart
class WheelBonusWidget extends StatefulWidget {
  // Animated spinning wheel
  // Segment highlight on land
  // Audio sync with rotation
}
```

---

## File Structure

```
flutter_ui/lib/widgets/slot_lab/bonus/
├── bonus_simulator_panel.dart      // Main tabbed panel
├── hold_and_win_visualizer.dart    // H&W grid + respins
├── pick_bonus_panel.dart           // Pick game UI
├── gamble_simulator.dart           // Gamble card/coin UI
├── wheel_bonus_widget.dart         // Spinning wheel (optional)
└── bonus_widgets.dart              // Shared widgets (prize badge, etc.)

crates/rf-slot-lab/src/features/
├── mod.rs                          // Feature exports
├── free_spins.rs                   // ✅ Already complete
├── hold_and_win.rs                 // ✅ Already complete
├── cascades.rs                     // ✅ Already complete
├── jackpot.rs                      // ✅ Already complete
├── gamble.rs                       // ✅ Already complete
├── pick_bonus.rs                   // NEW: Pick bonus logic
└── wheel_bonus.rs                  // NEW: Wheel bonus logic

crates/rf-bridge/src/slot_lab_ffi.rs
└── + Hold & Win state functions
└── + Pick bonus functions
└── + Gamble choice functions
```

---

## Audio Integration

### Stage Events for Bonus Games

| Bonus | Stages | Audio Events |
|-------|--------|--------------|
| Hold & Win | `hold_lock`, `hold_respin`, `hold_fill`, `hold_complete` | Lock sound, respin whoosh, tier achieve, celebration |
| Pick | `pick_select`, `pick_reveal`, `pick_prize`, `pick_poison` | Tap sound, reveal fanfare, prize ding, fail sound |
| Gamble | `gamble_choice`, `gamble_win`, `gamble_lose` | Card flip, win fanfare, lose buzzer |
| Wheel | `wheel_start`, `wheel_tick`, `wheel_slow`, `wheel_land` | Spin whoosh, tick per segment, decel, land thud |

### Bus Routing

```dart
// Bonus audio goes to SFX bus with possible ducking
static const int bonusBus = BusId.sfx;  // Bus 2

// Ducking: Bonus audio ducks music by -6dB
duckingRules.add(DuckingRule(
  sourceBus: BusId.sfx,
  targetBus: BusId.music,
  duckAmount: -6.0,
  attackMs: 50,
  releaseMs: 200,
));
```

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `B` | Open Bonus Simulator panel |
| `1-5` | Quick trigger: FS, H&W, Pick, Gamble, Wheel |
| `Space` | Spin/Pick/Gamble (context-aware) |
| `R` | Respin (H&W) / Reveal All (Pick) |
| `C` | Collect (Gamble) |

---

## Dependencies

### Rust
- `rf-slot-lab` — Feature chapters
- `rf-bridge` — FFI functions
- `rf-stage` — Stage events

### Flutter
- `slot_lab_provider.dart` — State management
- `event_registry.dart` — Audio event triggering
- `lower_zone_controller.dart` — Tab integration

---

## Testing Checklist

- [ ] Hold & Win grid shows correct locked positions
- [ ] Pick bonus reveals prizes correctly
- [ ] Gamble win/lose outcomes match probability
- [ ] Audio triggers at correct moments
- [ ] Keyboard shortcuts work in bonus panel
- [ ] Tab switching preserves bonus state
- [ ] Feature abort works mid-bonus

---

## Timeline

| Day | Tasks |
|-----|-------|
| 1 | Phase 1: H&W FFI + Grid Visualizer |
| 2-3 | Phase 2: Pick Bonus Chapter + UI |
| 4 | Phase 3: Gamble Config + Simulator |
| 5 | Phase 4: Unified Panel + Integration |
| 6-7 | Phase 5: Wheel Bonus (optional) |

---

*Generated by Claude Code — Principal Engineer Mode*
