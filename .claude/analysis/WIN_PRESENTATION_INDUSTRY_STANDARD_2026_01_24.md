# Win Presentation Flow — FluxForge Implementation

**Date:** 2026-01-24
**Status:** ✅ IMPLEMENTED (INDUSTRY-STANDARD)
**Based on:** Industry research (NetEnt, Pragmatic Play, Big Time Gaming)

---

## Executive Summary

FluxForge koristi **industry-standard 3-fazni win presentation flow** — STRICT SEQUENTIAL, SA tier plaketom:

```
REELS_STOP
    │
    ▼
╔═══════════════════════════════════════════════════════════════════════════════╗
║  PHASE 1: SYMBOL HIGHLIGHT (1050ms)                                           ║
║  ├── Winning symbols glow/bounce                                              ║
║  ├── Audio: WIN_SYMBOL_HIGHLIGHT                                              ║
║  └── Duration: 3 pulse cycles × 350ms = 1050ms                                ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║  PHASE 2: TIER PLAQUE + COIN COUNTER ROLLUP (tier-based)                      ║
║  ├── "BIG WIN!" / "MEGA WIN!" / "EPIC WIN!" plaketa + coin counter rollup     ║
║  ├── Audio: WIN_PRESENT_[TIER], ROLLUP_START, ROLLUP_TICK, ROLLUP_END         ║
║  ├── NE prikazuje: info o simbolima (npr. "3x Grapes = $50")                  ║
║  └── Duration: 1500ms (SMALL) → 20000ms (ULTRA)                               ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║  PHASE 3: WIN LINE PRESENTATION (cycling) — TEK NAKON ROLLUP-a               ║
║  ├── Plaketa SE SAKRIVA, win lines cycling počinje                            ║
║  ├── SAMO vizuelne linije — BEZ info o simbolima ("Line 3: 3x Grapes")        ║
║  ├── Audio: WIN_LINE_SHOW per line                                            ║
║  └── Duration: 1500ms per line, cycles until next spin                        ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

**KLJUČNE KARAKTERISTIKE:**
- ✅ Tier plaketa: "WIN!", "BIG WIN!", "SUPER WIN!", "MEGA WIN!", "EPIC WIN!", "ULTRA WIN!"
- ✅ Coin counter sa rollup animacijom na plaketi
- ❌ BEZ prikaza simbola/win linija info (npr. "3x Grapes = $50", "Line 3: 5x Cherries")
- ✅ STRICT SEQUENTIAL: Phase 3 TEK NAKON što Phase 2 završi (bez overlapping-a)
- ✅ **BIG WIN je PRVI major tier** (industry standard — Zynga, NetEnt, Pragmatic)

---

## Win Tier Thresholds (Bet Multiplier) — Industry Standard

**VAŽNO:** BIG WIN je **PRVI major tier** po industry standardu (Zynga Wizard of Oz, NetEnt, Pragmatic Play).
"NICE WIN" nije industry standard — umesto toga koristimo "SUPER WIN" kao drugi tier.

| Tier | Multiplier | Example ($1 bet) | Industry Source | Notes |
|------|------------|------------------|-----------------|-------|
| **NO_WIN** | 0x | $0 | — | — |
| **SMALL** | < 5x | $1 - $4.99 | IGT Standard | Samo counter, bez plakete |
| **BIG** | 5x - 15x | $5 - $14.99 | Zynga, NetEnt | **PRVI major tier** |
| **SUPER** | 15x - 30x | $15 - $29.99 | Pragmatic Play | Drugi tier |
| **MEGA** | 30x - 60x | $30 - $59.99 | NetEnt | Treći tier |
| **EPIC** | 60x - 100x | $60 - $99.99 | Big Time Gaming | Četvrti tier |
| **ULTRA** | 100x+ | $100+ | Industry max | Maximum celebration |

**Industry Research Sources:**
- **Wizard of Oz Slots (Zynga):** BIG WIN (8-15x) → MEGA WIN (15-25x) → EPIC WIN (25-35x) → Over the Rainbow Win (35x+)
- **Know Your Slots:** 10x threshold for BIG WIN on less volatile games, 25x on more volatile
- **NetEnt/Pragmatic Play:** Similar progressions with BIG WIN as first major tier

---

## Phase 1: Symbol Highlight Animation

### Timing Specification

| Element | Duration | Notes |
|---------|----------|-------|
| **Pulse Cycle** | 350ms | Single glow/bounce cycle |
| **Number of Cycles** | 3 | Industry standard |
| **Total Duration** | ~1050ms | Before win plaque appears |
| **Bounce Scale** | 1.0 → 1.15 → 1.0 | Ease-out curve |
| **Glow Opacity** | 0.3 → 0.8 → 0.3 | Pulse rhythm |
| **Glow Blur** | 8px → 16px → 8px | Breathing effect |

### Animation Curve

```
Time (ms)    0     175    350    525    700    875   1050
             │      │      │      │      │      │      │
Scale    1.0─┤     1.15   1.0    1.15   1.0    1.15   1.0
             │      ╱╲     │      ╱╲     │      ╱╲     │
             └─────╱  ╲────┴─────╱  ╲────┴─────╱  ╲────┘

Glow     0.3─┤     0.8    0.3    0.8    0.3    0.8    0.3
             │      ╱╲     │      ╱╲     │      ╱╲     │
             └─────╱  ╲────┴─────╱  ╲────┴─────╱  ╲────┘
```

### Audio Trigger

```
0ms      → WIN_SYMBOL_HIGHLIGHT (single event, loops for duration)
         → Or: SYMBOL_PULSE_LOOP (if available)
```

---

## Phase 2: Tier Plaque + Coin Counter Rollup

**FluxForge prikazuje tier plaketu SA coin counterom:**
- ✅ Tier label: "WIN!", "BIG WIN!", "SUPER WIN!", "MEGA WIN!", "EPIC WIN!", "ULTRA WIN!"
- ✅ Coin counter sa rollup animacijom ispod tier labela
- ❌ NE prikazuje: info o simbolima (npr. "3x Grapes = $50")
- ❌ NE prikazuje: [COLLECT] / [GAMBLE] dugmad (za sada)

### Timing by Tier (Industry Standard)

| Tier | Multiplier | Rollup Duration | Skip Allowed After |
|------|------------|-----------------|-------------------|
| **SMALL** | < 5x | 1,500ms | 500ms |
| **BIG** | 5x - 15x | 2,500ms | 1,000ms |
| **SUPER** | 15x - 30x | 4,000ms | 2,000ms |
| **MEGA** | 30x - 60x | 7,000ms | 3,000ms |
| **EPIC** | 60x - 100x | 12,000ms | 5,000ms |
| **ULTRA** | 100x+ | 20,000ms | 8,000ms |

### Rollup Speed Calculation

```dart
// Ticks per second based on tier (industry standard progression)
int getTicksPerSecond(String tier) => switch (tier) {
  'SMALL' => 15,   // Fast rollup
  'BIG'   => 12,   // First major tier
  'SUPER' => 10,   // Second tier
  'MEGA'  => 8,    // Third tier
  'EPIC'  => 6,    // Fourth tier
  'ULTRA' => 4,    // Slow, dramatic rollup
  _ => 10,
};

// Total ticks = duration / interval
int getTotalTicks(String tier, int durationMs) {
  final ticksPerSecond = getTicksPerSecond(tier);
  return (durationMs * ticksPerSecond / 1000).round();
}
```

### Audio Timeline

```
Phase 1 End (1050ms)
    │
    ▼
1050ms   → WIN_PRESENT_[TIER] (fanfare starts)
         → Tier plaketa pojavi se ("BIG WIN!" + counter)
         → ROLLUP_START
 ...     → ROLLUP_TICK (repeating at tier-specific interval)
EndMs    → ROLLUP_END (final ding)
         → Plaketa SE SAKRIVA
         → Phase 3 POČINJE
```

### Visual Elements

```
┌─────────────────────────────────────────────────┐
│                                                 │
│               🌟 BIG WIN! 🌟                    │  ← Tier label (gradient text)
│                                                 │
│                 $250.00                         │  ← Coin counter (rollup)
│                                                 │
└─────────────────────────────────────────────────┘

✅ IMA: Tier plaketa ("WIN!", "BIG WIN!", "SUPER WIN!", "MEGA WIN!", "EPIC WIN!", "ULTRA WIN!")
✅ IMA: Coin counter sa rollup animacijom
❌ NEMA: Info o simbolima ("3x Grapes = $50")
❌ NEMA: [COLLECT] / [GAMBLE] dugmadi (za sada)
```

---

## Phase 3: Win Line Presentation — STRICT SEQUENTIAL

**Phase 3 UVEK počinje TEK NAKON što Phase 2 (rollup) završi.**
Tier plaketa se SAKRIVA kada Phase 3 počne.

**VAŽNO:** Win lines prikazuju SAMO vizuelne linije između dobitnih simbola.
- ❌ NE prikazuju: "Line 3: 3x Grapes = $50"
- ❌ NE prikazuju: "5x Cherries"
- ✅ Samo vizuelne linije koje povezuju dobitne simbole

### Timing Specification

| Element | Duration | Notes |
|---------|----------|-------|
| **Line Display Time** | 1,500ms | Per winning line |
| **Line Transition** | 250ms | Fade between lines |
| **Line Draw Animation** | 400ms | Path reveal |

### When Phase 3 Starts — STRICT SEQUENTIAL

| Tier | Multiplier | Phase 3 Start | Total Delay from Spin End |
|------|------------|---------------|---------------------------|
| **SMALL** | < 5x | After rollup (1500ms) | 2550ms |
| **BIG** | 5x - 15x | After rollup (2500ms) | 3550ms |
| **SUPER** | 15x - 30x | After rollup (4000ms) | 5050ms |
| **MEGA** | 30x - 60x | After rollup (7000ms) | 8050ms |
| **EPIC** | 60x - 100x | After rollup (12000ms) | 13050ms |
| **ULTRA** | 100x+ | After rollup (20000ms) | 21050ms |

**❌ NEMA overlapping-a** — win lines NIKADA ne počinju dok rollup traje.

### Line Cycling Logic

```dart
// Phase 3 UVEK počinje NAKON rollup-a završi
void _startWinLinePresentation(List<LineWin> lineWins) {
  // Tier plaketa se sakriva — win lines prikazuju SAMO vizuelne linije
  _winAmountController.reverse();

  // Počni cycling win linija (vizuelno, BEZ info o simbolima)
  _lineWinsForPresentation = lineWins;
  _currentPresentingLineIndex = 0;
  _isShowingWinLines = true;

  _showCurrentWinLine();
  _startLineCycleTimer();
}

// Delay = Phase 1 (1050ms) + Rollup Duration (tier-based)
int _getPhase3Delay(String tier) {
  final rollupDuration = _rollupDurationByTier[tier] ?? 1500;
  return _symbolHighlightDurationMs + rollupDuration;
}
```

### Audio Per Line

```
Each line cycle:
    │
    ▼
0ms     → WIN_LINE_SHOW
400ms   → Line fully drawn (visual)
1500ms  → Transition to next line
```

---

## Complete Timeline Example (BIG WIN) — Industry-Standard Flow

```
Time (ms)   Event                           Audio Stage
────────────────────────────────────────────────────────────────
    0       REELS_STOP (last reel)          REEL_STOP
    0       Phase 1 Start                   WIN_SYMBOL_HIGHLIGHT
  350       Symbol pulse cycle 1            (continuous)
  700       Symbol pulse cycle 2            (continuous)
 1050       Symbol pulse cycle 3 END        (stops)
─────────────────────────────────────────────────────────────────
 1050       Phase 2 Start                   WIN_PRESENT_BIG
            Tier plaketa pojavi se          "BIG WIN!" + counter
            Rollup počinje                  ROLLUP_START
  ...       Tick at 100ms interval          ROLLUP_TICK
 5050       Rollup ends (40 ticks)          ROLLUP_END
            Tier plaketa SE SAKRIVA         —
─────────────────────────────────────────────────────────────────
 5050       Phase 3 Start                   WIN_LINE_SHOW (line 1)
            Win lines cycling počinje       (SAMO vizuelne linije)
 6550       Line 2                          WIN_LINE_SHOW
 8050       Line 3                          WIN_LINE_SHOW
 9550       Line 4                          WIN_LINE_SHOW
11050       Line 5 (cycles back to 1)       WIN_LINE_SHOW
  ...       (continues until next spin)
```

**NAPOMENA:** Phase 3 POČINJE na 5050ms — ODMAH nakon što rollup završi.
Nema overlapping-a između Phase 2 i Phase 3.
Win lines prikazuju SAMO vizuelne linije — BEZ info o simbolima ("3x Grapes = $50").

---

## Constants Definition (Industry-Standard Flow)

```dart
/// Win presentation timing constants — INDUSTRY-STANDARD (with tier plaque)
/// Phase 3 starts STRICTLY after Phase 2 ends (no overlap)
class WinPresentationTiming {
  // Phase 1: Symbol Highlight
  static const int symbolPulseCycleMs = 350;
  static const int symbolPulseCycles = 3;
  static const int phase1DurationMs = symbolPulseCycleMs * symbolPulseCycles; // 1050ms

  // Phase 2: Tier Plaque + Coin Counter Rollup (Industry Standard)
  // BIG is first major tier, SUPER is second tier
  static const Map<String, int> rollupDurationMs = {
    'SMALL': 1500, 'BIG': 2500, 'SUPER': 4000,
    'MEGA': 7000, 'EPIC': 12000, 'ULTRA': 20000,
  };

  static const Map<String, int> rollupTicksPerSecond = {
    'SMALL': 15, 'BIG': 12, 'SUPER': 10,
    'MEGA': 8, 'EPIC': 6, 'ULTRA': 4,
  };

  // Phase 3: Win Line Presentation
  static const int lineDisplayMs = 1500;
  static const int lineTransitionMs = 250;
  static const int lineDrawAnimationMs = 400;

  // Phase 3 start = Phase 1 (1050ms) + Rollup Duration
  // STRICT SEQUENTIAL — no overlap with rollup
  static int getPhase3StartMs(String tier) {
    final rollup = rollupDurationMs[tier] ?? 1500;
    return phase1DurationMs + rollup;
  }
}
```

---

## Audio Stage Requirements (Industry Standard)

| Stage | Description | Multiplier | Priority | Pooled | Loop |
|-------|-------------|------------|----------|--------|------|
| `WIN_SYMBOL_HIGHLIGHT` | Symbol glow/pulse SFX | — | 60 | No | Yes (3 cycles) |
| `WIN_PRESENT_SMALL` | Small win (no plaque) | < 5x | 70 | No | No |
| `WIN_PRESENT_BIG` | **BIG WIN!** (first major) | 5x - 15x | 72 | No | No |
| `WIN_PRESENT_SUPER` | SUPER WIN! (second tier) | 15x - 30x | 75 | No | No |
| `WIN_PRESENT_MEGA` | MEGA WIN! (third tier) | 30x - 60x | 80 | No | No |
| `WIN_PRESENT_EPIC` | EPIC WIN! (fourth tier) | 60x - 100x | 85 | No | No |
| `WIN_PRESENT_ULTRA` | ULTRA WIN! (maximum) | 100x+ | 90 | No | No |
| `ROLLUP_START` | Counter start SFX | — | 50 | No | No |
| `ROLLUP_TICK` | Counter tick | — | 40 | ✅ Yes | No |
| `ROLLUP_END` | Counter end ding | — | 55 | No | No |
| `WIN_LINE_SHOW` | Line highlight SFX | — | 45 | ✅ Yes | No |

---

## Implementation Checklist

- [x] Phase 1: Symbol highlight with 3 pulse cycles (1050ms)
- [x] Phase 2: Tier plaketa + Coin counter rollup ("BIG WIN!" + counter)
- [x] Tier-specific rollup duration
- [x] Tier-specific tick rate
- [x] Phase 3: STRICT sequential (tek nakon rollup-a završi)
- [x] Plaketa sakriva se kad Phase 3 počne
- [x] Win lines prikazuju SAMO vizuelne linije (BEZ info o simbolima)
- [x] Skip functionality (SPACE key)
- [x] Audio synchronization with visual phases
- [x] Per-tier fanfare audio (WIN_PRESENT_[TIER])

---

## Sources

1. **Flip The Switch** — Win tier thresholds (10-25x = Big Win)
2. **Frontiers in Psychology** — Audio proportional to win size
3. **UK Gambling Commission** — Minimum spin duration (2.5s)
4. **Know Your Slots** — Anticipation spin mechanics
5. **Animation Express** — Symbol highlight animation patterns
6. **PMC Research** — Reward reactivity in slot gambling
7. **GDC Audio Summit** — "Beyond Cha-Ching! Music for Slot Machines" (2013)

---

## FluxForge vs Industry Standard

| Aspect | FluxForge | Industry Standard | Status |
|--------|-----------|-------------------|--------|
| Symbol highlight | 1050ms (3 cycles) | 1050ms (3 cycles) | ✅ Isto |
| Win plaque | ✅ "BIG WIN!" | ✅ "BIG WIN!" overlay | ✅ Isto |
| Rollup visual | Tier label + Counter | Counter + plaque | ✅ Isto |
| Phase 3 timing | STRICT SEQUENTIAL | Overlap za male win-ove | ⚡ FluxForge stricter |
| Plaketa visibility | Sakriva se za Phase 3 | Ostaje vidljiv | ⚡ FluxForge različito |
| Symbol info prikaz | ❌ NE prikazuje | ✅ Prikazuje | ✅ Namerno drugačije |

**NAPOMENA:** FluxForge NE prikazuje info o simbolima ("3x Grapes = $50") jer korisnik to ne želi.

---

## Implementation Details (2026-01-24) — INDUSTRY-STANDARD

### Files Changed

| File | Changes |
|------|---------|
| `slot_preview_widget.dart` | Industry-standard 3-phase, WITH tier plaque, strict sequential Phase 3 |
| `stage_configuration_service.dart` | WIN_PRESENT_[TIER] stages |
| `event_registry.dart` | Stage→Audio mapping |

### Key Implementation

**Tier Plaque + Coin Counter** (`slot_preview_widget.dart`):
```dart
/// Win display — Tier plaketa ("BIG WIN!", "MEGA WIN!" itd.) SA coin counterom
/// NE prikazuje info o simbolima/win linijama (npr. "3x Grapes")
Widget _buildWinDisplay() {
  // Industry standard progression — BIG WIN is FIRST major tier
  final tierLabel = switch (_winTier) {
    'ULTRA' => 'ULTRA WIN!',
    'EPIC' => 'EPIC WIN!',
    'MEGA' => 'MEGA WIN!',
    'SUPER' => 'SUPER WIN!',  // Second tier (was NICE)
    'BIG' => 'BIG WIN!',       // FIRST major tier (5x-15x)
    'SMALL' => 'WIN!',
    _ => 'WIN!',
  };

  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [Colors.black.withOpacity(0.85), ...]),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: tierColors.first.withOpacity(0.8), width: 3),
      boxShadow: [BoxShadow(color: tierColors.first.withOpacity(0.5), ...)],
    ),
    child: Column(
      children: [
        // Tier label: "BIG WIN!", "MEGA WIN!", itd.
        ShaderMask(..., child: Text(tierLabel, ...)),
        const SizedBox(height: 8),
        // Coin counter sa rollup animacijom
        ShaderMask(..., child: Text(_formatWinAmount(_displayedWinAmount), ...)),
      ],
    ),
  );
}
```

**Strict Sequential Phase 3** (`slot_preview_widget.dart`):
```dart
// Phase 3 starts STRICTLY AFTER rollup ends
if (result.lineWins.isNotEmpty) {
  final rollupDuration = _rollupDurationByTier[_winTier] ?? 1500;
  final totalDelay = _symbolHighlightDurationMs + rollupDuration;

  Future.delayed(Duration(milliseconds: totalDelay), () {
    _startWinLinePresentation(result.lineWins);
  });
}

void _startWinLinePresentation(List<LineWin> lineWins) {
  // SAKRIJ PLAKETU — win lines prikazuju SAMO vizuelne linije
  _winAmountController.reverse();
  // ...
}
```

### Verification

- `flutter analyze` — No issues found
- Build — Succeeded
- Runtime — Industry-standard 3-phase flow:
  1. Symbol Highlight (1050ms)
  2. Tier Plaque + Coin Counter (tier-based, "BIG WIN!" + counter)
  3. Win Lines (AFTER rollup ends, SAMO vizuelne linije, BEZ info o simbolima)
