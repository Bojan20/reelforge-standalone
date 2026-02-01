# EmbeddedSlotMockup — Animation Race Condition Fix (V2 ULTIMATE)

**Datum:** 2026-02-01
**Fajl:** `flutter_ui/lib/widgets/slot_lab/embedded_slot_mockup.dart`
**Problem:** Četvrti ril (i bilo koji ril) nastavio animaciju nakon što su svi rilovi vizuelno stali

---

## Problem

### Simptomi
- Svi rilovi su vizuelno zaustavljeni
- Ali spin se ne završava — `GameState` ostaje u `anticipation` ili `spinning`
- Anticipation glow ili druge animacije se nastavljaju na zaustavlјenim rilovima
- Spin završava tek nakon ~2000ms (trajanje `_reelController`)
- **ČETVRTI RIL** posebno problematičan — nastavlja da "treperi" nakon zaustavljanja

### Root Cause

Dva **NEZAVISNA** mehanizma kontrolisala su spin:

1. **`_reelController` (AnimationController)**
   - Trajanje: 2000ms (normal) / 800ms (turbo)
   - `_reelController.forward().then(() => _revealResult())`
   - Poziva `_revealResult()` tek kada animacija završi

2. **`_scheduleReelStops()` (Timer-based)**
   - Zadnji reel staje nakon ~1250ms (5 × 250ms)
   - Samo postavlјa `_reelStopped[i] = true`
   - **NE MENJA `_gameState`** (komentar: "let _revealResult handle it")

**Race Condition:**
```
0ms     - SPIN_START, _reelController.forward() pokrenut
250ms   - Reel 0 stao
500ms   - Reel 1 stao
750ms   - Reel 2 stao
1000ms  - Reel 3 stao (anticipation započinje)
1250ms  - Reel 4 stao — SVI RILOVI VIZUELNO STALI
        ↓
        _gameState JOŠ UVEK = 'anticipation' ili 'spinning'!
        AnimatedBuilder nastavlјa rebuilde
        Vizuelni efekti (glow, itd.) se nastavljaju
        ↓
2000ms  - _reelController.then() → _revealResult()
        ↓
        TEK SADA _gameState = 'revealing'
```

**Gap od 750ms** (1250ms → 2000ms) gde rilovi vizuelno stoje ali animacije se nastavljaju.

---

## Rešenje

### 1. Immediate State Transition

U `_scheduleReelStops()`, kada SVI rilovi stanu, odmah prelazimo u `revealing`:

```dart
// Check if ALL reels have stopped
if (_reelStopped.every((stopped) => stopped)) {
  // ═══════════════════════════════════════════════════════════════════
  // CRITICAL FIX: Immediately transition to revealing state
  // This prevents ANY lingering animations after all reels stop
  // ═══════════════════════════════════════════════════════════════════
  setState(() {
    _anticipationReelIndex = -1;
    // CRITICAL: Change state to revealing IMMEDIATELY when all reels stop
    // Don't wait for _reelController to finish!
    if (_gameState == GameState.spinning || _gameState == GameState.anticipation) {
      _gameState = GameState.revealing;
    }
  });
  widget.onAnticipationEnd?.call();

  // Stop the reel animation controller early since all reels are visually stopped
  if (_reelController.isAnimating) {
    _reelController.stop();
  }
}
```

### 2. Guard Flag za Double Reveal

Dodajemo `_revealProcessed` flag da sprečimo dvostruko izvršavanje `_revealResult()`:

```dart
// Instance variable (linija ~221)
bool _revealProcessed = false;

// Reset u obe spin metode
void _startSpin() {
  _revealProcessed = false;
  // ...
}

void _startForcedSpin(ForcedOutcome outcome) {
  _revealProcessed = false;
  // ...
}

// Guard u _revealResult()
void _revealResult({ForcedOutcome? forcedOutcome}) {
  // Guard: Don't process reveal twice
  if (_revealProcessed) return;
  if (_gameState == GameState.celebrating || _gameState == GameState.idle) return;

  _revealProcessed = true;
  // ... ostatak metode
}
```

### 3. Anticipation Phase Check u `_buildReel()`

Dodajemo proveru da li smo ZAISTA u anticipation fazi pre prikazivanja glow-a:

```dart
Widget _buildReel(int reelIdx, double cellSize) {
  // CRITICAL: Only show anticipation effects if we're still in spinning/anticipation state
  // This prevents "ghost" anticipation glow after all reels have stopped
  final isInAnticipationPhase = _gameState == GameState.anticipation;

  // Anticipation reel has glow ONLY during anticipation phase
  final isAnticipationReel = _anticipationReelIndex == reelIdx && isInAnticipationPhase;

  // ...

  // Add glow for anticipation reel - only during anticipation phase
  boxShadow: isAnticipationReel && !isStopped
      ? [BoxShadow(color: _T.jpMajor.withOpacity(0.6), blurRadius: 20, spreadRadius: 2)]
      : null,
}
```

---

## Rezultat

### Pre Fix-a
```
1250ms - All reels stopped visually
         GameState = anticipation (WRONG!)
         Effects continue on stopped reels
2000ms - _revealResult() called
         GameState = revealing
```

### Posle Fix-a
```
1250ms - All reels stopped visually
         GameState = revealing (CORRECT!)
         _reelController.stop() called
         All effects stop immediately
```

---

## Izmenjene Linije

| Lokacija | Opis |
|----------|------|
| Linija ~221 | Dodato `bool _revealProcessed = false;` instance variable |
| Linija ~288 | `_revealProcessed = false;` reset u `_startSpin()` |
| Linija ~316 | `_revealProcessed = false;` reset u `_startForcedSpin()` |
| Linije 448-470 | Immediate state transition + `_reelController.stop()` |
| Linije 476-483 | Guard check u `_revealResult()` |
| Linije 861-869 | `isInAnticipationPhase` check za glow efekte |

---

## Pouka

**Nikad ne dozvoliti da animacija kontroliše logiku!**

Pravilna arhitektura:
1. **Timer/Logic** kontroliše KADA se šta dešava
2. **AnimationController** kontroliše samo VIZUALNU interpolaciju
3. Kada logika kaže "završeno" → animacija se **odmah** zaustavlјa
4. Ne čekati da animacija završi da bismo promenili state

**Pattern za budućnost:**
```dart
// LOŠE - logika čeka animaciju
controller.forward().then(() => changeState());

// DOBRO - logika kontroliše animaciju
if (allReelsStopped) {
  controller.stop();  // Odmah zaustavi
  changeState();      // Odmah promeni state
}
```

---

---

## V2 ULTIMATE FIX (2026-02-01)

### Prethodni Fix (V1) — NIJE RADIO

V1 fix je pokušao da reši problem promenom `_gameState` i zaustavljanjem `_reelController`:
- Dodao `_revealProcessed` guard flag
- Promenio `_gameState = revealing` kada svi rilovi stanu
- Pozvao `_reelController.stop()` rano

**Zašto V1 nije radio:**
- `AnimatedBuilder` NASTAVLJA da rebuild-uje čak i nakon `stop()` poziva!
- `_reelController.value` ostaje na poslednjoj vrednosti (nije reset)
- Svaki rebuild u `AnimatedBuilder` trigeruje novi random `displayId`
- Rezultat: "shimmer" efekat na zaustavlјenom rilu

### Root Cause — AnimatedBuilder Continuous Rebuild

**Problem u kodu (linija 958-1026):**

```dart
return AnimatedBuilder(
  animation: _reelController,  // ← PROBLEM: Nastavlja rebuild
  builder: (context, _) {
    // Ovaj builder se poziva KONTINUALNO dok je controller aktivan
    // Čak i nakon stop() — jer controller.value != 0 && != 1

    final displayId = !isStopped && isSpinning
        ? (_rng.nextInt(10) + (_reelController.value * 100).toInt()) % 10
        : symbolId;
    // ↑ Random simboli se generišu svaki rebuild — vizuelni "shimmer"
  },
);
```

**Flutter AnimatedBuilder ponašanje:**
1. `AnimatedBuilder` sluša `animation.addListener()`
2. Kada se listener trigeruje → rebuild widget
3. `AnimationController.stop()` NE uklanja listener-e
4. Controller ostaje "active" (nije disposed)
5. Rebuildi nastavljaju do dispose-a

### V2 Ultimate Solution

**Razdvajanje statičnog i animiranog renderinga:**

```dart
Widget _buildReel(int reelIdx, double cellSize) {
  final isActivelySpinning = (_gameState == GameState.spinning ||
                              _gameState == GameState.anticipation) &&
                             !isStopped;

  // ═══════════════════════════════════════════════════════════════════
  // CRITICAL: Don't use AnimatedBuilder when not actively spinning!
  // ═══════════════════════════════════════════════════════════════════
  if (!isActivelySpinning) {
    return _buildStaticReel(reelIdx, cellSize, borderColor, borderWidth);
  }

  // Only use AnimatedBuilder for actively spinning reels
  return AnimatedBuilder(
    animation: _reelController,
    builder: (context, _) {
      // Double-check inside builder (race condition guard)
      final stillSpinning = (_gameState == GameState.spinning ||
                             _gameState == GameState.anticipation) &&
                            !_reelStopped[reelIdx];

      if (!stillSpinning) {
        return _buildStaticReel(reelIdx, cellSize, _T.border, 1);
      }
      // ... spinning rendering
    },
  );
}

/// Static reel — NO AnimatedBuilder, NO continuous rebuilds
Widget _buildStaticReel(int reelIdx, double cellSize, Color borderColor, double borderWidth) {
  // Direktan Container bez AnimatedBuilder wrapper-a
  // Koristi _symbols[reelIdx][rowIdx] — fiksne vrednosti, nema random
}
```

### Ključne Promene (V2)

| Linija | Promena |
|--------|---------|
| 926-977 | Nova `_buildReel()` logika sa early return za statične rilove |
| 974-976 | `if (!isActivelySpinning) return _buildStaticReel()` |
| 985-992 | Double-check unutar AnimatedBuilder za race conditions |
| 1029-1082 | Nova `_buildStaticReel()` metoda |

### Rezultat V2

**Pre V2:**
```
Reel stopped → AnimatedBuilder continues → random displayId → shimmer
```

**Posle V2:**
```
Reel stopped → isActivelySpinning = false → _buildStaticReel() → stable
```

---

## Lekcija — AnimatedBuilder Anti-Pattern

**NIKADA** koristiti AnimatedBuilder za widget koji može biti i statičan i animiran!

**Loše:**
```dart
AnimatedBuilder(
  animation: controller,
  builder: (ctx, _) {
    if (shouldAnimate) {
      return AnimatedWidget();
    } else {
      return StaticWidget();  // ← OPASNO! Rebuildi nastavljaju
    }
  },
)
```

**Dobro:**
```dart
if (shouldAnimate) {
  return AnimatedBuilder(
    animation: controller,
    builder: (ctx, _) => AnimatedWidget(),
  );
} else {
  return StaticWidget();  // ← BEZBEDNO! Nema AnimatedBuilder
}
```

---

## Povezani Dokumenti

- [EMBEDDED_SLOT_MOCKUP_ULTIMATE_ANALYSIS.md](../reviews/EMBEDDED_SLOT_MOCKUP_ULTIMATE_ANALYSIS.md) — Kompletna analiza widgeta
- [ANTICIPATION_SYSTEM.md](../architecture/ANTICIPATION_SYSTEM.md) — Industry-standard anticipation
- [EVENT_SYNC_SYSTEM.md](../architecture/EVENT_SYNC_SYSTEM.md) — Stage→Audio sinhronizacija
