# SlotLab Bug Fixes — 2026-01-25

**Status:** ✅ ALL FIXED
**Flutter Analyze:** 0 errors (1 info-level warning only)

---

## Bug Summary

| # | Bug | Root Cause | Fix | Status |
|---|-----|------------|-----|--------|
| 1 | Win plaque not showing for small wins | Line 2128 condition `if (_winTier.isNotEmpty)` | Changed to `if (_winTier.isNotEmpty \|\| _targetWinAmount > 0)` | ✅ Fixed |
| 2 | Win line presentation not showing | Missing `setState()` in `_startWinLinePresentation()` | Added `setState()` and new `_showCurrentWinLineWithSetState()` method | ✅ Fixed |
| 3 | Anticipation animation not triggering | Hardcoded `_scatterSymbolId = 1` but Rust uses `SymbolType::Scatter = 2` | Changed to `_scatterSymbolId = 2` | ✅ Fixed |

---

## Detailed Analysis

### BUG #1: Win Plaque Not Showing for Small Wins

**Symptoms:**
- Win symbol animation plays correctly
- Total win counter never appears for small wins (< 5x bet)
- "WIN!" plaque is invisible

**Root Cause:**
```dart
// slot_preview_widget.dart:2128 (BEFORE)
if (_winTier.isNotEmpty)
  Positioned.fill(
    child: _buildWinOverlay(constraints),
  ),
```

For small wins, `_getWinTier()` returns empty string (`''`), so the overlay widget was never added to the tree.

**Fix:**
```dart
// slot_preview_widget.dart:2128 (AFTER)
if (_winTier.isNotEmpty || _targetWinAmount > 0)
  Positioned.fill(
    child: _buildWinOverlay(constraints),
  ),
```

Now the overlay shows for ANY win (small or big). The overlay itself handles visibility via `_winAmountOpacity.value`.

---

### BUG #2: Win Line Presentation Not Showing

**Symptoms:**
- Win plaque shows and fades
- Win lines never appear
- Debug log shows `_startWinLinePresentation()` is called

**Root Cause:**
```dart
// _startWinLinePresentation() - BEFORE
void _startWinLinePresentation(List<LineWin> lineWins) {
  _lineWinsForPresentation = lineWins;        // NO setState!
  _currentPresentingLineIndex = 0;            // NO setState!
  _isShowingWinLines = true;                  // NO setState!

  _winAmountController.reverse();
  _showCurrentWinLine();  // Also modifies _currentLinePositions without setState
  // ...
}
```

State variables were modified but `setState()` was never called, so the widget never rebuilt to show the win lines.

**Fix:**
```dart
// _startWinLinePresentation() - AFTER
void _startWinLinePresentation(List<LineWin> lineWins) {
  setState(() {
    _lineWinsForPresentation = lineWins;
    _currentPresentingLineIndex = 0;
    _isShowingWinLines = true;
  });

  _winAmountController.reverse();
  _showCurrentWinLineWithSetState();  // New method with setState
  // ...
}
```

Also added new method `_showCurrentWinLineWithSetState()` that wraps `_currentLinePositions` update in `setState()`.

---

### BUG #3: Anticipation Animation Not Triggering

**Symptoms:**
- 2+ scatter symbols land on reels
- Anticipation animation never activates on remaining reels
- Debug log shows scatter detection but no anticipation trigger

**Root Cause:**
```dart
// slot_preview_widget.dart:188 (BEFORE)
static const int _scatterSymbolId = 1; // SCATTER symbol ID
```

But in Rust (`crates/rf-slot-lab/src/symbols.rs:14`):
```rust
pub enum SymbolType {
    // ...
    Scatter = 2,  // Rust uses 2, not 1!
    // ...
}
```

The scatter detection was checking for symbol ID 1, but the Rust engine uses ID 2 for scatter symbols.

**Fix:**
```dart
// slot_preview_widget.dart:188 (AFTER)
static const int _scatterSymbolId = 2; // SCATTER symbol ID (matches Rust SymbolType::Scatter = 2)
```

---

## Files Modified

| File | Changes |
|------|---------|
| `flutter_ui/lib/widgets/slot_lab/slot_preview_widget.dart` | All 3 bug fixes |

**Line References:**
- Line 188: `_scatterSymbolId = 2` (BUG #3)
- Lines ~1118-1132: `setState()` added to `_startWinLinePresentation()` (BUG #2)
- Lines ~1203-1228: New `_showCurrentWinLineWithSetState()` method (BUG #2)
- Lines ~2128-2133: Changed overlay condition (BUG #1)

---

## Verification

```bash
cd flutter_ui && flutter analyze
# Result: 0 errors, 1 info-level warning (unnecessary_underscores in unrelated file)
```

---

## Related Documentation

- `.claude/architecture/SLOT_ANIMATION_INDUSTRY_STANDARD.md` — Animation timing spec
- `.claude/architecture/SLOTLAB_DROP_ZONE_SPEC.md` — Drop zone system (updated to v1.1)
- `crates/rf-slot-lab/src/symbols.rs` — Rust symbol type definitions

---

**END OF DOCUMENT**
