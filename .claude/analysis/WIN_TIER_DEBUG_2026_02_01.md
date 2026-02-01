# Win Tier Debug Analysis — 2026-02-01

## Reported Issues

1. **Counteri ne rade kako treba**
2. **Big Win se javlja kada ne treba**
3. **Logika nije tačna**
4. **Brzina countera prespora**
5. **Win thresholdi ne pokazuju pravu plaketu**

---

## Default Configuration

### Big Win Threshold
```dart
BigWinConfig.defaultConfig():
  threshold: 20.0x  // 20× bet = Big Win starts
```

### Big Win Tiers
| Tier | Range | Label | Duration | Tick Rate |
|------|-------|-------|----------|-----------|
| 1 | 20x - 50x | "BIG WIN TIER 1" | 4000ms | 12 ticks/s |
| 2 | 50x - 100x | "BIG WIN TIER 2" | 4000ms | 10 ticks/s |
| 3 | 100x - 250x | "BIG WIN TIER 3" | 4000ms | 8 ticks/s |
| 4 | 250x - 500x | "BIG WIN TIER 4" | 4000ms | 6 ticks/s |
| 5 | 500x+ | "BIG WIN TIER 5" | 4000ms | 4 ticks/s |

### Regular Win Tiers
| Tier | Range | Label | Duration | Tick Rate |
|------|-------|-------|----------|-----------|
| -1 | < 1x | "" | 0ms | 0 |
| 0 | = 1x | "PUSH" | 500ms | 20 |
| 1 | 1x - 2x | "WIN 1" | 1000ms | 15 |
| 2 | 2x - 4x | "WIN 2" | 1500ms | 13 |
| 3 | 4x - 8x | "WIN 3" | 2000ms | 12 |
| 4 | 8x - 13x | "WIN 4" | 3000ms | 10 |
| 5 | 13x - 20x | "WIN 5" | 4000ms | 8 |

---

## Test Scenarios

### Scenario 1: Regular Win (5x bet)
```
Bet: $1.00
Win: $5.00
Multiplier: 5x

Expected:
  ✅ Tier: WIN_3 (4x - 8x range)
  ✅ Plaque: "WIN 3"
  ✅ Duration: 2000ms
  ✅ Tick Rate: 12 ticks/second

Actual: ???
```

### Scenario 2: Big Win Tier 1 (25x bet)
```
Bet: $1.00
Win: $25.00
Multiplier: 25x

Expected:
  ✅ isBigWin: true
  ✅ Tier: BIG_WIN_TIER_1 (20x - 50x range)
  ✅ Plaque: "BIG WIN TIER 1"
  ✅ Duration: 4000ms
  ✅ Tick Rate: 12 ticks/second

Actual: ???
```

### Scenario 3: Edge Case (Exactly 20x)
```
Bet: $1.00
Win: $20.00
Multiplier: 20x

Expected:
  ✅ isBigWin: true (multiplier >= 20)
  ✅ Tier: BIG_WIN_TIER_1
  ✅ Plaque: "BIG WIN TIER 1"

Actual: ???
```

### Scenario 4: Just Below Big Win (19.5x)
```
Bet: $1.00
Win: $19.50
Multiplier: 19.5x

Expected:
  ✅ isBigWin: false
  ✅ Tier: WIN_5 (13x - 20x range)
  ✅ Plaque: "WIN 5"

Actual: ???
```

---

## Debug Checklist

### Code Paths to Verify

**1. Tier Calculation:**
```dart
// slot_lab_project_provider.dart:1139
WinTierResult? getWinTierForAmount(double winAmount, double betAmount)
  ├─ Check: multiplier = winAmount / betAmount
  ├─ Check: isBigWin = multiplier >= threshold (20.0)
  └─ Return: WinTierResult(isBigWin, multiplier, tier)
```

**2. Tier String ID Mapping:**
```dart
// slot_preview_widget.dart:2216
String _getP5WinTierStringId(double totalWin)
  ├─ Get: tierResult = projectProvider.getWinTierForAmount()
  ├─ If isBigWin: return 'BIG_WIN_TIER_1..5' based on maxTier
  └─ If regular: return regularTier.stageName ('WIN_1', 'WIN_2', etc.)
```

**3. Plaque Label Retrieval:**
```dart
// slot_preview_widget.dart:2257
String _getP5TierLabel(String tierStringId)
  ├─ If BIG_WIN_TIER_X: get from bigWins.getTierById()
  └─ If WIN_X: get from regularWins.tiers
```

**4. Rollup Speed:**
```dart
// slot_preview_widget.dart:2472
_startRollupTicks()
  ├─ Tick interval: 100ms (10 ticks/second)
  ├─ Total ticks: calculated from duration and tick rate
  └─ Counter increment per tick
```

---

## Potential Issues

### Issue 1: Multiplier Calculation
```dart
// Check if betAmount is being set correctly
widget.provider.betAmount  // Should match UI bet amount
```

### Issue 2: Threshold Comparison
```dart
// Edge case: exactly 20.0x
multiplier >= threshold  // Should be true for 20.0
```

### Issue 3: Tier Range Gaps
```dart
// Regular WIN_5: 13x - 20x
// Big WIN_TIER_1: 20x - 50x
// Gap at 20x? Should go to Big Win
```

### Issue 4: Rollup Tick Count
```dart
// Tick count calculation:
_rollupTicksTotal = (duration / 1000) * tickRate
// Example: 4000ms, 12 ticks/s = 48 ticks
// Counter increment = totalWin / 48 per tick
```

---

## Debugging Steps

1. **Add Debug Logs:**
```dart
debugPrint('[WIN DEBUG] Bet: $betAmount, Win: $totalWin, Multiplier: ${totalWin/betAmount}');
debugPrint('[WIN DEBUG] isBigWin: ${tierResult.isBigWin}, Tier: ${tierResult.bigWinMaxTier}');
debugPrint('[WIN DEBUG] Display Label: ${_getP5TierLabel(tierId)}');
debugPrint('[WIN DEBUG] Rollup: duration=${duration}ms, tickRate=$tickRate, totalTicks=$totalTicks');
```

2. **Test Specific Scenarios:**
- 5x win → Should show WIN_3
- 20x win → Should show BIG_WIN_TIER_1
- 50x win → Should show BIG_WIN_TIER_2

3. **Verify Configuration:**
```dart
// Print current config
final config = projectProvider.winConfiguration;
debugPrint('BigWin threshold: ${config.bigWins.threshold}');
debugPrint('Regular tiers: ${config.regularWins.tiers.length}');
debugPrint('Big tiers: ${config.bigWins.tiers.length}');
```

---

## Next Steps

Need user to provide:
1. **Specific example:** Bet amount + Win amount where issue occurs
2. **Expected behavior:** What should happen
3. **Actual behavior:** What actually happens
4. **Screenshots/logs:** If available

Then can pinpoint exact issue in code.

---

*Created: 2026-02-01*
*Status: Awaiting specific test case*
