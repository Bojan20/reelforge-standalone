# P1.2: Win Line Presentation Cycle Analysis

**Date:** 2026-01-24
**Status:** ✅ VERIFIED WORKING
**Priority:** P1 (High)

---

## Executive Summary

The win line presentation system is **fully functional**. Lines cycle correctly, the timer operates at 1500ms intervals, and the painter coordinates match the reel table layout precisely.

---

## System Architecture

```
SpinResult.lineWins (List<LineWin>)
         │
         ▼
_startWinLinePresentation()
         │
         ├── Store lineWins in _lineWinsForPresentation
         ├── Set _currentPresentingLineIndex = 0
         ├── _showCurrentWinLine() — display first line
         │
         └── Start Timer.periodic(1500ms)
                      │
                      ▼ (every 1500ms)
               _advanceToNextWinLine()
                      │
                      ├── _currentPresentingLineIndex = (index + 1) % count
                      └── _showCurrentWinLine()
                                   │
                                   ▼
                      Update _currentLinePositions (Set<String>)
                                   │
                                   ▼
                      Widget rebuild → CustomPaint → _WinLinePainter
```

---

## Key Components

### 1. State Variables

**File:** `slot_preview_widget.dart` (lines 187-192)

```dart
List<LineWin> _lineWinsForPresentation = [];
int _currentPresentingLineIndex = 0;
bool _isShowingWinLines = false;
Timer? _winLineCycleTimer;
Set<String> _currentLinePositions = {}; // e.g., "0,1", "1,1", "2,1"
static const Duration _winLineCycleDuration = Duration(milliseconds: 1500);
```

### 2. Presentation Control

| Method | Purpose |
|--------|---------|
| `_startWinLinePresentation(lineWins)` | Initiates cycling with list of LineWin |
| `_stopWinLinePresentation()` | Cancels timer, resets state |
| `_advanceToNextWinLine()` | Increments index with modulo wrap |
| `_showCurrentWinLine()` | Updates `_currentLinePositions` for painter |

### 3. Timer Implementation

**File:** `slot_preview_widget.dart` (lines 621-640)

```dart
void _startWinLinePresentation(List<LineWin> lineWins) {
  _lineWinsForPresentation = lineWins;
  _currentPresentingLineIndex = 0;
  _isShowingWinLines = true;

  // Show first line immediately
  _showCurrentWinLine();

  // Start cycling timer
  _winLineCycleTimer?.cancel();
  _winLineCycleTimer = Timer.periodic(_winLineCycleDuration, (_) {
    if (!mounted || !_isShowingWinLines) {
      _winLineCycleTimer?.cancel();
      return;
    }
    _advanceToNextWinLine();
  });
}
```

---

## Coordinate Calculation

### Reel Table Layout (`_buildReelTable`)

**File:** `slot_preview_widget.dart` (lines 1173-1191)

```dart
Widget _buildReelTable(double availableWidth, double availableHeight) {
  // Calculate SQUARE cell size - leave space on sides for other elements
  final cellWidth = availableWidth / widget.reels;
  final cellHeight = availableHeight / widget.rows;
  final cellSize = math.min(cellWidth, cellHeight) * 0.82; // Smaller to leave space L/R

  return Center(
    child: Table(
      defaultColumnWidth: FixedColumnWidth(cellSize),
      children: List.generate(widget.rows, (rowIndex) {
        return TableRow(
          children: List.generate(widget.reels, (reelIndex) {
            return _buildSymbolCell(reelIndex, rowIndex, cellSize);
          }),
        );
      }),
    ),
  );
}
```

### Win Line Painter Coordinates

**File:** `slot_preview_widget.dart` (lines 1943-1971)

```dart
// Must match _buildReelTable logic
// Available space = size - padding (4*2=8) - border (2*2=4) = size - 12
final availableWidth = size.width - 12;
final availableHeight = size.height - 12;
final cellWidth = availableWidth / reelCount;
final cellHeight = availableHeight / rowCount;
final cellSize = math.min(cellWidth, cellHeight) * 0.82;

// Center offset calculation
final tableWidth = cellSize * reelCount;
final tableHeight = cellSize * rowCount;
final offsetX = (size.width - tableWidth) / 2;
final offsetY = (size.height - tableHeight) / 2;

// Cell center calculation
final x = offsetX + (reelIndex + 0.5) * cellSize;
final y = offsetY + (rowIndex + 0.5) * cellSize;
```

### Verification

| Calculation | _buildReelTable | _WinLinePainter | Match |
|-------------|-----------------|-----------------|-------|
| `cellSize` factor | `0.82` | `0.82` | ✅ |
| Available space | `availableWidth/Height` | `size - 12` | ✅ |
| Center offset | implicit via `Center()` | `(size - tableSize) / 2` | ✅ |
| Cell center | N/A (Table handles) | `(index + 0.5) * cellSize` | ✅ |

**Note:** The `_buildReelTable` receives pre-subtracted dimensions (`constraints.maxWidth - 12, constraints.maxHeight - 12`), while the painter subtracts 12 internally from the full size. Both approaches yield identical results.

**Result:** ✅ Coordinates match perfectly

---

## Visual Rendering

### _WinLinePainter Drawing Layers

**File:** `slot_preview_widget.dart` (lines 1927-2038)

```
Layer 1: GLOW (outer)
├── Color: lineColor @ 0.3 + pulseValue * 0.2 opacity
├── StrokeWidth: 14 + pulseValue * 4
└── MaskFilter: blur(8px)

Layer 2: MAIN LINE
├── Color: lineColor @ 0.8 + pulseValue * 0.2 opacity
├── StrokeWidth: 5 + pulseValue * 2
└── StrokeCap/Join: round

Layer 3: HIGHLIGHT (inner)
├── Color: white @ 0.4 + pulseValue * 0.3 opacity
├── StrokeWidth: 2
└── StrokeCap/Join: round

Layer 4: POSITION DOTS
├── Glow dot: 12 + pulseValue * 4 radius, blur(6px)
├── Main dot: 8 + pulseValue * 2 radius
└── Center dot: 3 + pulseValue radius (white @ 0.8 opacity)
```

### Pulse Animation

Tied to `_winPulseAnimation` (0.0 → 1.0 repeating):
- Line width pulses: 5-7px stroke
- Dot size pulses: 8-10px radius
- Opacity pulses: 0.3-0.5 for glow

---

## LineWin Data Structure

```dart
class LineWin {
  final int lineNumber;           // Payline number (1-based)
  final int symbolId;             // Winning symbol ID
  final String symbolName;        // Symbol display name
  final int matchCount;           // 3, 4, or 5 of a kind
  final double winAmount;         // Win amount in credits
  final List<List<int>> positions; // [[reel, row], [reel, row], ...]
}

// Example:
// LineWin(
//   lineNumber: 1,
//   symbolId: 5,
//   symbolName: "WILD",
//   matchCount: 3,
//   winAmount: 100.0,
//   positions: [[0, 1], [1, 1], [2, 1]],
// )
```

---

## Cycle Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ Line 1 of 5: WILD x3 = 100                                      │
│                                                                  │
│   ┌─────┬─────┬─────┬─────┬─────┐                               │
│   │     │     │     │     │     │  row 0                        │
│   ├─────┼─────┼─────┼─────┼─────┤                               │
│   │ ●───●───● │     │     │     │  row 1 (LINE DRAWN)          │
│   ├─────┼─────┼─────┼─────┼─────┤                               │
│   │     │     │     │     │     │  row 2                        │
│   └─────┴─────┴─────┴─────┴─────┘                               │
│     R0    R1    R2    R3    R4                                  │
└─────────────────────────────────────────────────────────────────┘
        │
        │ 1500ms
        ▼
┌─────────────────────────────────────────────────────────────────┐
│ Line 2 of 5: SCATTER x4 = 50                                    │
│                                                                  │
│   ┌─────┬─────┬─────┬─────┬─────┐                               │
│   │ ●   │     │     │     │ ●   │  row 0                        │
│   ├─────┼─────┼─────┼─────┼─────┤                               │
│   │     │ ●   │     │ ●   │     │  row 1 (V-SHAPE LINE)        │
│   ├─────┼─────┼─────┼─────┼─────┤                               │
│   │     │     │     │     │     │  row 2                        │
│   └─────┴─────┴─────┴─────┴─────┘                               │
│     R0    R1    R2    R3    R4                                  │
└─────────────────────────────────────────────────────────────────┘
        │
        │ 1500ms
        ▼
      ... (cycles through all lines, then wraps to Line 1)
```

---

## UI Info Badge

**File:** `slot_preview_widget.dart` (lines 1114-1170)

Displays current line info during presentation:

```
┌──────────────────────────────────────┐
│ [1/5] WILD x3 = $100.00             │
└──────────────────────────────────────┘
   │     │         │
   │     │         └── Win amount
   │     └── Match count
   └── Line index / total lines
```

---

## Cleanup

Timer is properly cancelled in:
- `_stopWinLinePresentation()` — called on new spin
- `dispose()` — widget lifecycle

```dart
@override
void dispose() {
  widget.provider.removeListener(_onProviderUpdate);
  _winLineCycleTimer?.cancel();  // ✅ Prevents memory leak
  _disposeControllers();
  super.dispose();
}
```

---

## Verification Checklist

- [x] Timer cycles at 1500ms intervals
- [x] Index wraps correctly with modulo
- [x] Painter coordinates match table layout
- [x] Glow/line/dots render correctly
- [x] Pulse animation is smooth
- [x] Line info badge shows correct data
- [x] Timer cancelled on dispose

---

## Known Issues (NONE)

The win line presentation cycle is complete and working as designed.

---

## Files Involved

| File | Role | Lines |
|------|------|-------|
| `slot_preview_widget.dart` | Main widget with timer, state, painter | 2106 total |
| `slot_lab_provider.dart` | Provides `SpinResult.lineWins` | N/A |

### Key Line Ranges (slot_preview_widget.dart)

| Component | Lines |
|-----------|-------|
| State variables | 187-192 |
| `_startWinLinePresentation()` | 621-640 |
| `_stopWinLinePresentation()` | 643-650 |
| `_advanceToNextWinLine()` | 653-664 |
| `_showCurrentWinLine()` | 667-682 |
| `_buildCurrentLineInfo()` | 1114-1170 |
| `_buildReelTable()` | 1173-1191 |
| `_WinLinePainter` class | 1927-2038 |

---

## Recommendation

No fixes required. The system is functioning correctly.
