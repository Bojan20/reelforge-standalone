# EmbeddedSlotMockup — Animation Race Condition Fix (V4 ULTIMATE)

**Datum:** 2026-02-01
**Fajl:** `flutter_ui/lib/widgets/slot_lab/embedded_slot_mockup.dart`
**Problem:** Četvrti ril (i bilo koji ril) nastavio animaciju nakon što su svi rilovi vizuelno stali

---

## Problem

### Simptomi
- Svi rilovi su vizuelno zaustavljeni
- Ali spin se ne završava — `GameState` ostaje u `anticipation` ili `spinning`
- Anticipation glow ili druge animacije se nastavljaju na zaustavljenim rilovima
- Spin završava tek nakon ~2000ms (trajanje `_reelController`)
- **ČETVRTI RIL** posebno problematičan — nastavlja da "treperi" / ima "dimovanje" nakon zaustavljanja

### Root Cause

Dva **NEZAVISNA** mehanizma kontrolisala su spin:

1. **`_reelController` (AnimationController)**
   - Trajanje: 2000ms (normal) / 800ms (turbo)
   - `_reelController.forward().then(() => _revealResult())`
   - Poziva `_revealResult()` tek kada animacija završi

2. **`_scheduleReelStops()` (Timer-based)**
   - Zadnji reel staje nakon ~1250ms (5 × 250ms)
   - Samo postavlja `_reelStopped[i] = true`
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
        AnimatedBuilder nastavlja rebuilde
        Vizuelni efekti (glow, itd.) se nastavljaju
        ↓
2000ms  - _reelController.then() → _revealResult()
        ↓
        TEK SADA _gameState = 'revealing'
```

**Gap od 750ms** (1250ms → 2000ms) gde rilovi vizuelno stoje ali animacije se nastavljaju.

---

## V1 Fix — NIJE RADIO

V1 fix je pokušao da reši problem promenom `_gameState` i zaustavljanjem `_reelController`:
- Dodao `_revealProcessed` guard flag
- Promenio `_gameState = revealing` kada svi rilovi stanu
- Pozvao `_reelController.stop()` rano

**Zašto V1 nije radio:**
- `AnimatedBuilder` NASTAVLJA da rebuild-uje čak i nakon `stop()` poziva!
- `_reelController.value` ostaje na poslednjoj vrednosti (nije reset)
- Svaki rebuild u `AnimatedBuilder` trigeruje novi random `displayId`
- Rezultat: "shimmer" efekat na zaustavljenom rilu

---

## V2 Fix — Razdvajanje statičnog i animiranog renderinga

**Rešenje:** Koristiti `AnimatedBuilder` SAMO za aktivno spinning rilove.

```dart
Widget _buildReel(int reelIdx, double cellSize) {
  final isActivelySpinning = (_gameState == GameState.spinning ||
                              _gameState == GameState.anticipation) &&
                             !isStopped;

  // CRITICAL: Don't use AnimatedBuilder when not actively spinning!
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

**Status:** V2 rešio shimmer efekat, ALI nije rešio win prezentaciju koja počinje dok se rilovi još okreću!

---

## V3 Fix — Controller Callback Removal (2026-02-01)

### Novi Problem (nakon V2)

Korisnik prijavio: **Win prezentacija počinje dok se rilovi još okreću sa anticipacijom!**

Simptomi:
- Anticipacija na rilu 4, ril 5 se normalno okreće
- Čim ril 4 završi anticipaciju, glow momentalno prelazi na ril 5
- **KRITIČNO:** Animacija simbola, win plaketa i win linije se pojavljuju dok ril 5 JOŠ UVEK VRTI!

### Root Cause (V3)

**Problem:** Sa anticipacijom, ukupno vreme za sve rilove PREMAŠUJE trajanje `_reelController`!

Bez anticipacije (250ms × 5 = 1250ms):
```
Reel 0: 250ms
Reel 1: 500ms
Reel 2: 750ms
Reel 3: 1000ms
Reel 4: 1250ms  ← Svi rilovi stali
_reelController: 2000ms ← Controller završi POSLE rilova — OK
```

SA anticipacijom (250ms × 2 + 800ms × 3 = 2900ms):
```
Reel 0: 250ms
Reel 1: 500ms
Reel 2 (antic): 1300ms
Reel 3 (antic): 2100ms
Reel 4 (antic): 2900ms  ← Svi rilovi stali
_reelController: 2000ms ← Controller završi PRE rilova — PROBLEM!
```

**`_reelController.then(() => _revealResult())` se poziva na 2000ms, dok ril 4 i 5 još uvek vrte sa anticipacijom!**

### V3 Rešenje

**Ukloniti `_revealResult()` iz controller callback-a. Pozivati ga SAMO kada SVI rilovi stanu.**

```dart
// STARO (LOŠE):
_reelController.forward(from: 0).then((_) {
  _revealResult();  // ← Može da se pozove PRE nego što svi rilovi stanu!
});

// NOVO (V3 FIX):
_reelController.forward(from: 0);  // Nema callback!
```

**Status:** V3 rešio win prezentaciju timing, ALI četvrti ril još uvek ima "dimovanje" problem!

---

## V4 Fix — ULTIMATE Robust Anticipation Handling (2026-02-01)

### Novi Problem (nakon V3)

Korisnik prijavio: **"Dimovanje" na četvrtom rilu i spin se ne završava dok se taj ril ne završi, iako je vizuelno stao.**

### Root Cause (V4)

**Problem:** Timer-i za različite rilove mogu da fire-uju u nepredvidivom redosledu zbog Flutter Timer nepreciznosti.

Stara logika:
```dart
if (i == _anticipationReelIndex) {
  // Move to next reel
  _anticipationReelIndex = i + 1;
}
```

**Problem:** Ako timer za ril 4 fire-uje pre nego što se `_anticipationReelIndex` ažurira sa rila 3, onda:
- `i = 4`, `_anticipationReelIndex = 3`
- `i == _anticipationReelIndex` → `4 == 3` → false
- Anticipation handling se **PRESKAČE**!

Rezultat: `_anticipationReelIndex` ostaje na 3, a ril 3 ima anticipation glow čak i kad je stao.

### V4 Rešenje

**Robustnija provera: `_anticipationReelIndex <= i` umesto `== i`**

```dart
// V4 FIX: Check if anticipation needs to move, not just if this is THE anticipation reel
// This handles race conditions where timers fire slightly out of order
if (_anticipationReelIndex >= 0 && _anticipationReelIndex <= i) {
  // Find the NEXT spinning reel (if any)
  int nextSpinningReel = -1;
  for (int j = i + 1; j < widget.reels; j++) {
    if (!_reelStopped[j]) {
      nextSpinningReel = j;
      break;
    }
  }

  if (nextSpinningReel >= 0) {
    // Move anticipation glow to next spinning reel
    setState(() {
      _anticipationReelIndex = nextSpinningReel;
    });
    widget.onAnticipationMove?.call(nextSpinningReel);
  } else {
    // No more spinning reels — END anticipation completely
    setState(() {
      _anticipationReelIndex = -1;
    });
    widget.onAnticipationEnd?.call();
  }
}
```

### Ključne Promene (V4)

| Aspekt | V3 | V4 |
|--------|----|----|
| Uslov za anticipation update | `i == _anticipationReelIndex` | `_anticipationReelIndex <= i` |
| Sledeći ril | `i + 1` (hardcoded) | Dinamičko traženje prvog spinning rila |
| Race condition handling | Nije | Hvata kasne timer fire-ove |
| Završetak anticipacije | `i == widget.reels - 1` | Kada nema više spinning rilova |

### Rezultat V4

**Pre V4:**
```
Timer timing može varirati ±10-20ms
Ril 3 timer fire → _anticipationReelIndex = 3, proverava 3 == 3 → OK
Ril 4 timer fire BRZO → _anticipationReelIndex = 4, proverava 4 == 4 → OK

ALI ako Ril 4 timer fire KASNO:
Ril 3 timer fire → _anticipationReelIndex = 3, proverava 3 == 3 → move to 4
[rebuild]
Ril 4 timer fire → _anticipationReelIndex = 4, ALI sad proverava 4 == 4 sa starim state → possible miss
```

**Posle V4:**
```
Bilo koji redosled timera:
Ril N timer fire → proverava _anticipationReelIndex <= N
Ako da → traži sledeći spinning ril → ažurira ili završava anticipaciju
UVEK ROBUSTNO!
```

---

## Lekcija — Timer Race Conditions

**NIKAD ne pretpostavljati redosled Timer callback-ova!**

```dart
// LOŠE - pretpostavlja tačan redosled
if (i == expectedIndex) {
  expectedIndex++;
}

// DOBRO - robustno na bilo koji redosled
if (expectedIndex <= i) {
  expectedIndex = findNextValid(i);
}
```

**Pattern:**
- Timer-i NISU garantovano precizni
- Uvek koristiti `<=` ili `>=` umesto `==` za sekvencijalne provere
- Dinamički tražiti sledeće validno stanje umesto hardcoding-a

---

## Kompletna Hronologija Fix-ova

| Verzija | Problem | Rešenje | Status |
|---------|---------|---------|--------|
| V1 | Shimmer na zaustavljenim rilovima | Guard flag + gameState change | ❌ Nije radilo |
| V2 | AnimatedBuilder nastavlja rebuild | Razdvajanje static/animated | ✅ Rešeno |
| V3 | Win prezentacija pre nego što svi rilovi stanu | Uklonjen controller callback | ✅ Rešeno |
| V4 | "Dimovanje" / zaglavljeno stanje na četvrtom rilu | Robustniji anticipation handling sa `<=` i dinamičkim traženjem | 🔄 Testiranje |

---

## Debug Logging (V4)

Za dijagnostiku, dodati debug logging:

```dart
debugPrint('[V4 DEBUG] Reel $i STOPPING...');
debugPrint('[V4 DEBUG] After reel $i stop: _reelStopped=$_reelStopped, gameState=$_gameState');
debugPrint('[V4 RENDER] Reel $reelIdx → STATIC/ANIMATED (details...)');
```

Očekivani output za ispravan flow:
```
[V4 DEBUG] Reel 0 STOPPING...
[V4 DEBUG] Reel 0 STOPPED, _reelStopped=[true, false, false, false, false]
[V4 RENDER] Reel 0 → STATIC
...
[V4 DEBUG] Reel 4 STOPPING...
[V4 DEBUG] Reel 4 STOPPED, _reelStopped=[true, true, true, true, true]
[V4 DEBUG] ✅ ALL REELS STOPPED! Calling _revealResult()...
```

---

## Povezani Dokumenti

- [EMBEDDED_SLOT_MOCKUP_ULTIMATE_ANALYSIS.md](../reviews/EMBEDDED_SLOT_MOCKUP_ULTIMATE_ANALYSIS.md) — Kompletna analiza widgeta
- [ANTICIPATION_SYSTEM.md](../architecture/ANTICIPATION_SYSTEM.md) — Industry-standard anticipation
- [EVENT_SYNC_SYSTEM.md](../architecture/EVENT_SYNC_SYSTEM.md) — Stage→Audio sinhronizacija
