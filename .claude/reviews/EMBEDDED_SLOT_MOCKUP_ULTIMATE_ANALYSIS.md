# EmbeddedSlotMockup — Ultimativna Analiza

**Datum:** 2026-01-24
**Verzija:** V3 (Visual-Sync Callbacks)
**Fajl:** `flutter_ui/lib/widgets/slot_lab/embedded_slot_mockup.dart` (~1164 LOC)

---

## SADRŽAJ

1. [Vizuelna Struktura](#1-vizuelna-struktura)
2. [State Machine](#2-state-machine)
3. [Simboli i Reels](#3-simboli-i-reels)
4. [Audio Flow — Kompletna Mapa](#4-audio-flow--kompletna-mapa)
5. [Visual-Sync Callbacks](#5-visual-sync-callbacks)
6. [Analiza po Ulogama (9 Uloga)](#6-analiza-po-ulogama)
7. [Šta je Implementirano](#7-šta-je-implementirano)
8. [Šta Nedostaje](#8-šta-nedostaje)
9. [Preporuke za Poboljšanja](#9-preporuke-za-poboljšanja)

---

## 1. VIZUELNA STRUKTURA

### 1.1 Layout Hijerarhija

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HEADER (72px)                                │
│  [Balance: $10,000.00]    FLUXFORGE SLOTS    [State: READY]         │
├─────────────────────────────────────────────────────────────────────┤
│                      JACKPOT BAR (100px)                            │
│  [MINI $1.2K] [MINOR $12.3K] [MAJOR $123.4K] [★ GRAND ★ $1.23M]     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│                        REEL AREA (Expanded)                         │
│                                                                     │
│     ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐                           │
│     │ ⭐│   │ 🍒│   │ 7️⃣│   │ 💎│   │ 🔔│    ← Row 0               │
│     ├───┤   ├───┤   ├───┤   ├───┤   ├───┤                           │
│     │ 🍋│   │ 💰│   │ 🍇│   │ 🎰│   │ 🍊│    ← Row 1               │
│     ├───┤   ├───┤   ├───┤   ├───┤   ├───┤                           │
│     │ 🍊│   │ ⭐│   │ 🍒│   │ 7️⃣│   │ 💎│    ← Row 2               │
│     └───┘   └───┘   └───┘   └───┘   └───┘                           │
│     Reel0   Reel1   Reel2   Reel3   Reel4                           │
│                                                                     │
│                    [WIN OVERLAY - ako celebrating]                  │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                        INFO BAR (52px)                              │
│  LINES: 25 │ BET/LINE: $0.10 │ TOTAL BET: $2.50 │ LAST WIN: -       │
├─────────────────────────────────────────────────────────────────────┤
│                      CONTROL BAR (100px)                            │
│  [AUTO][TURBO]  [-$0.10+]         [SPIN]        [BIG][MEGA][EPIC][JP]│
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 Tema — Casino Grade Dark Premium

```dart
class _T {
  // Backgrounds (darkest to lightest)
  static const bg1 = Color(0xFF030308);   // Deepest black
  static const bg2 = Color(0xFF080810);   // Deep
  static const bg3 = Color(0xFF101018);   // Mid
  static const bg4 = Color(0xFF181822);   // Surface
  static const bg5 = Color(0xFF20202C);   // Controls

  // Metals
  static const gold = Color(0xFFFFD700);        // Primary gold
  static const goldBright = Color(0xFFFFE966);  // Highlight
  static const goldDark = Color(0xFFB8860B);    // Shadow
  static const silver = Color(0xFFB0B0B8);      // Secondary

  // Jackpots (color-coded by tier)
  static const jpGrand = Color(0xFFFFD700);   // Gold
  static const jpMajor = Color(0xFFFF1744);   // Red
  static const jpMinor = Color(0xFF7C4DFF);   // Purple
  static const jpMini = Color(0xFF00E676);    // Green

  // Win Tiers (color-coded by multiplier)
  static const winSmall = Color(0xFF42A5F5);  // Blue (< 10x)
  static const winMedium = Color(0xFF66BB6A); // Green (10-50x)
  static const winBig = Color(0xFFFFCA28);    // Yellow (50-100x)
  static const winMega = Color(0xFFFF7043);   // Orange (100-500x)
  static const winEpic = Color(0xFFE040FB);   // Purple (> 500x)

  // UI Elements
  static const spin = Color(0xFF00E676);       // Main CTA
  static const spinBright = Color(0xFF69F0AE); // Hover/Active
  static const border = Color(0xFF303040);     // Borders
  static const text = Colors.white;            // Primary text
  static const textDim = Color(0xFF808090);    // Secondary text
}
```

### 1.3 Widget Sections

| Sekcija | Visina | Opis |
|---------|--------|------|
| **Header** | 72px | Balance, naslov, state indicator |
| **Jackpot Bar** | 100px | 4 jackpot tickers (Mini/Minor/Major/Grand) |
| **Reel Area** | Expanded | 5x3 grid simbola, win overlay |
| **Info Bar** | 52px | Lines, bet, total bet, last win |
| **Control Bar** | 100px | Auto/Turbo, bet control, spin, forced outcomes |

---

## 2. STATE MACHINE

### 2.1 GameState Enum

```dart
enum GameState {
  idle,         // 0 - Čeka spin
  spinning,     // 1 - Reels se vrte
  anticipation, // 2 - Zadnji reel, moguć win
  revealing,    // 3 - Prikazivanje rezultata
  celebrating,  // 4 - Win animacija
  bonusGame,    // 5 - Bonus igra aktivna
}
```

### 2.2 State Flow Diagram

```
                    ┌─────────────┐
                    │    IDLE     │◄────────────────────────┐
                    │   (READY)   │                         │
                    └──────┬──────┘                         │
                           │                                │
                     [SPIN pressed]                         │
                           │                                │
                           ▼                                │
                    ┌─────────────┐                         │
           ┌───────►│  SPINNING   │                         │
           │        │ (reels spin)│                         │
           │        └──────┬──────┘                         │
           │               │                                │
           │        [Reel 3 stops]                          │
           │               │                                │
           │         ┌─────┴─────┐                          │
           │         │20% chance │                          │
           │         ▼           ▼                          │
           │  ┌─────────────┐    │                          │
           │  │ANTICIPATION │    │                          │
           │  │ (tension!)  │    │                          │
           │  └──────┬──────┘    │                          │
           │         │           │                          │
           │         ▼           ▼                          │
           │        [All reels stop]                        │
           │               │                                │
           │               ▼                                │
           │        ┌─────────────┐                         │
           │        │  REVEALING  │                         │
           │        │ (show result)│                        │
           │        └──────┬──────┘                         │
           │               │                                │
           │         ┌─────┴─────┐                          │
           │         │           │                          │
           │      [Win > 0]   [No win]                      │
           │         │           │                          │
           │         ▼           │                          │
           │  ┌─────────────┐    │                          │
           │  │ CELEBRATING │    │                          │
           │  │ (win anim)  │    │                          │
           │  └──────┬──────┘    │                          │
           │         │           │                          │
           │      [3 sec]     [300ms]                       │
           │         │           │                          │
           │         ▼           ▼                          │
           │         └───────────┴──────────────────────────┘
           │
           │
           └─────[AUTO mode: auto-restart]
```

### 2.3 WinType Enum

```dart
enum WinType {
  noWin,       // 0 - No win
  smallWin,    // 1 - < 10x bet
  mediumWin,   // 2 - 10-50x bet
  bigWin,      // 3 - 50-100x bet
  megaWin,     // 4 - 100-500x bet
  epicWin,     // 5 - > 500x bet
}
```

**Win Tier Mapping:**

| Multiplier | WinType | Color | Label |
|------------|---------|-------|-------|
| 0x | noWin | textDim | - |
| 0.1-9.9x | smallWin | Blue | "WIN" |
| 10-49.9x | mediumWin | Green | "NICE WIN" |
| 50-99.9x | bigWin | Yellow | "BIG WIN" |
| 100-499x | megaWin | Orange | "MEGA WIN" |
| 500x+ | epicWin | Purple | "EPIC WIN" |

---

## 3. SIMBOLI I REELS

### 3.1 Symbol Definitions

```dart
class _Sym {
  final String icon;     // Emoji
  final Color c1, c2;    // Gradient colors
  final bool isWild;     // Wild symbol
  final bool isScatter;  // Scatter symbol
  final bool isBonus;    // Bonus symbol

  static const list = [
    _Sym('⭐', gold, gold, isWild: true),      // 0: WILD
    _Sym('💎', purple, purple, isScatter: true), // 1: SCATTER
    _Sym('🎰', red, red, isBonus: true),        // 2: BONUS
    _Sym('7️⃣', red, red),                       // 3: SEVEN
    _Sym('🔔', yellow, yellow),                 // 4: BELL
    _Sym('🍒', orange, orange),                 // 5: CHERRY
    _Sym('🍋', lime, lime),                     // 6: LEMON
    _Sym('🍊', orange, orange),                 // 7: ORANGE
    _Sym('🍇', purple, purple),                 // 8: GRAPE
    _Sym('💰', gold, gold),                     // 9: MONEY
  ];
}
```

### 3.2 Reel Data Structure

```dart
// 2D grid: [reel][row]
List<List<int>> _symbols = [
  [0, 3, 7],  // Reel 0: rows 0-2
  [5, 9, 0],  // Reel 1
  [3, 8, 5],  // Reel 2
  [1, 2, 3],  // Reel 3
  [4, 7, 1],  // Reel 4
];

// Stop state per reel
List<bool> _reelStopped = [true, true, true, true, true];
```

### 3.3 Reel Stop Timing (Staggered)

```dart
void _scheduleReelStops() {
  final baseDelay = _turbo ? 100 : 250;  // Turbo: 100ms, Normal: 250ms

  for (int i = 0; i < widget.reels; i++) {
    Future.delayed(Duration(milliseconds: baseDelay * (i + 1)), () {
      _reelStopped[i] = true;
      widget.onReelStop?.call(i);  // VISUAL-SYNC callback

      // Anticipation check on second-to-last reel
      if (i == widget.reels - 2 && random < 0.2) {
        _gameState = GameState.anticipation;
        widget.onAnticipation?.call();
      }
    });
  }
}
```

**Normal Mode Timing:**
| Event | Time (ms) |
|-------|-----------|
| SPIN_START | 0 |
| REEL_STOP_0 | 250 |
| REEL_STOP_1 | 500 |
| REEL_STOP_2 | 750 |
| REEL_STOP_3 | 1000 |
| (ANTICIPATION?) | 1000 |
| REEL_STOP_4 | 1250 |
| SPIN_END | 1250 |

**Turbo Mode Timing:**
| Event | Time (ms) |
|-------|-----------|
| SPIN_START | 0 |
| REEL_STOP_0 | 100 |
| REEL_STOP_1 | 200 |
| REEL_STOP_2 | 300 |
| REEL_STOP_3 | 400 |
| (ANTICIPATION?) | 400 |
| REEL_STOP_4 | 500 |
| SPIN_END | 500 |

---

## 4. AUDIO FLOW — KOMPLETNA MAPA

### 4.1 Stage → Audio Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        VISUAL EVENT                                         │
│                  (EmbeddedSlotMockup)                                       │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    VISUAL-SYNC CALLBACK                                     │
│                                                                             │
│   onSpinStart()    → 'SPIN_START'                                           │
│   onReelStop(0)    → 'REEL_STOP_0'                                          │
│   onReelStop(1)    → 'REEL_STOP_1'                                          │
│   ...                                                                       │
│   onAnticipation() → 'ANTICIPATION_ON'                                      │
│   onReveal()       → 'SPIN_END'                                             │
│   onWinStart()     → 'WIN_SMALL/MEDIUM/BIG/MEGA/EPIC' + 'ROLLUP_START'      │
│   onWinEnd()       → 'WIN_END'                                              │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SlotLabScreen._triggerVisualStage()                      │
│                                                                             │
│   eventRegistry.triggerStage(stage, context: {...})                         │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         EventRegistry                                       │
│                                                                             │
│   1. Input validation (empty, length, characters)                           │
│   2. Case-insensitive stage lookup                                          │
│   3. Find matching AudioEvent                                               │
│   4. Container check (Blend/Random/Sequence)                                │
│   5. For each AudioLayer:                                                   │
│      - Apply delay/offset                                                   │
│      - Apply RTPC modulation                                                │
│      - Apply spatial positioning (AutoSpatialEngine)                        │
│      - Check voice pooling eligibility                                      │
│      - Determine PlaybackSource (daw/slotlab/middleware/browser)            │
└────────────────────────────┬────────────────────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
      ┌───────────┐  ┌───────────┐  ┌───────────┐
      │ AudioPool │  │AudioPlayback│  │ Container │
      │(rapid-fire)│ │  Service   │  │  Service  │
      └─────┬─────┘  └─────┬─────┘  └─────┬─────┘
            │              │              │
            └──────────────┼──────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      Rust PlaybackEngine (FFI)                              │
│                                                                             │
│   NativeFFI.playbackPlayOneShot() → voice_id                                │
│   NativeFFI.playbackPlayToBus() → voice_id                                  │
│   NativeFFI.playbackPlayLooping() → voice_id                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Stage Categories i Audio Bus Routing

| Stage Prefix | Category | Bus | Priority | Pooled |
|--------------|----------|-----|----------|--------|
| `SPIN_*` | spin | sfx | 70 | No |
| `REEL_STOP_*` | spin | reels | 65 | **Yes** |
| `ANTICIPATION_*` | spin | sfx | 75 | No |
| `WIN_*` | win | sfx | 60-80 | No |
| `ROLLUP_*` | win | sfx | 55 | **Yes** |
| `BIGWIN_*` | win | sfx | 80 | No |
| `JACKPOT_*` | jackpot | sfx | 95 | No |
| `CASCADE_*` | cascade | sfx | 60 | **Yes** |
| `SYMBOL_LAND_*` | symbol | reels | 50 | **Yes** |
| `UI_*` | ui | ui | 30 | **Yes** |
| `MUSIC_*` | music | music | 20 | No |

### 4.3 Voice Pooling (Rapid-Fire Events)

```dart
const _pooledEventStages = {
  // Reel stops
  'REEL_STOP', 'REEL_STOP_0'..'REEL_STOP_5',

  // Cascade/Tumble
  'CASCADE_STEP', 'CASCADE_SYMBOL_POP',

  // Rollup counter
  'ROLLUP_TICK', 'ROLLUP_TICK_SLOW', 'ROLLUP_TICK_FAST',

  // Win evaluation
  'WIN_LINE_SHOW', 'WIN_SYMBOL_HIGHLIGHT',

  // UI clicks
  'UI_BUTTON_PRESS', 'UI_BUTTON_HOVER',

  // Symbol lands
  'SYMBOL_LAND', 'SYMBOL_LAND_LOW', 'SYMBOL_LAND_MID', 'SYMBOL_LAND_HIGH',

  // Wheel ticks
  'WHEEL_TICK', 'WHEEL_TICK_FAST', 'WHEEL_TICK_SLOW',
};
```

### 4.4 Spatial Audio Positioning

```dart
// Per-reel pan values (left to right)
final reelPan = {
  'REEL_STOP_0': -0.8,  // Far left
  'REEL_STOP_1': -0.4,  // Left
  'REEL_STOP_2':  0.0,  // Center
  'REEL_STOP_3': +0.4,  // Right
  'REEL_STOP_4': +0.8,  // Far right
};
```

---

## 5. VISUAL-SYNC CALLBACKS

### 5.1 Callback Definitions

```dart
class EmbeddedSlotMockup extends StatefulWidget {
  // VISUAL-SYNC CALLBACKS — Trigger stages exactly when visual events occur

  /// Called when SPIN button is pressed (visual spin start)
  final VoidCallback? onSpinStart;

  /// Called when each reel visually stops (reelIndex: 0-4)
  final void Function(int reelIndex)? onReelStop;

  /// Called when anticipation state begins (last reel)
  final VoidCallback? onAnticipation;

  /// Called when all reels have stopped and result is revealing
  final VoidCallback? onReveal;

  /// Called when win celebration starts (with win tier)
  final void Function(WinType winType, double amount)? onWinStart;

  /// Called when win celebration ends
  final VoidCallback? onWinEnd;
}
```

### 5.2 Callback Usage u SlotLabScreen

```dart
EmbeddedSlotMockup(
  provider: _slotLabProvider,
  reels: _reelCount,
  rows: _rowCount,

  // VISUAL-SYNC callbacks → EventRegistry
  onSpinStart: () => _triggerVisualStage('SPIN_START'),
  onReelStop: (reelIdx) => _triggerVisualStage(
    'REEL_STOP_$reelIdx',
    context: {'reel_index': reelIdx}
  ),
  onAnticipation: () => _triggerVisualStage('ANTICIPATION_ON'),
  onReveal: () => _triggerVisualStage('SPIN_END'),
  onWinStart: (winType, amount) => _triggerWinStage(winType, amount),
  onWinEnd: () => _triggerVisualStage('WIN_END'),
),
```

### 5.3 Helper Methods

```dart
void _triggerVisualStage(String stage, {Map<String, dynamic>? context}) {
  eventRegistry.triggerStage(stage, context: context);
  debugPrint('[SlotLab] VISUAL-SYNC: $stage ${context ?? ''}');
}

void _triggerWinStage(WinType winType, double amount) {
  final winStage = switch (winType) {
    WinType.noWin => null,
    WinType.smallWin => 'WIN_SMALL',
    WinType.mediumWin => 'WIN_MEDIUM',
    WinType.bigWin => 'WIN_BIG',
    WinType.megaWin => 'WIN_MEGA',
    WinType.epicWin => 'WIN_EPIC',
  };

  if (winStage != null) {
    final multiplier = _bet > 0 ? amount / _bet : 0.0;
    eventRegistry.triggerStage(winStage, context: {
      'win_amount': amount,
      'win_multiplier': multiplier,
      'win_type': winType.name,
    });
    eventRegistry.triggerStage('ROLLUP_START', context: {
      'win_amount': amount,
      'win_multiplier': multiplier,
    });
  }
}
```

---

## 6. ANALIZA PO ULOGAMA (9 Uloga)

### 6.1 🎮 Slot Game Designer

**Šta koristi:**
- EmbeddedSlotMockup za vizualni preview
- Forced outcome buttons (BIG, MEGA, EPIC, JP)
- GameState i WinType za definisanje flow-a

**Šta unosi:**
- Grid konfiguracija (5x3)
- Symbol definicije (emoji, boje, tipovi)
- Win tier thresholds (10x, 50x, 100x, 500x)
- Jackpot seed values

**Šta očekuje:**
- Vizuelno veran prikaz slot mašine
- Accurate timing za reel stops
- Win overlay koji odgovara tieru

**Friction:**
- ❌ Nema paytable editora
- ❌ Nema payline vizualizacije
- ❌ Symbol weight-i su hardcoded (random)
- ❌ Nema RTP kalkulatora

**Preporuke:**
1. Dodati Paytable Editor panel
2. Dodati Payline Visualizer
3. Symbol Weight Editor sa RTP preview-om
4. Math Model Import (GDD JSON)

---

### 6.2 🎵 Audio Designer / Composer

**Šta koristi:**
- Visual-Sync callbacks za precizni timing
- Stage → Event mapping
- EventRegistry za audio triggering
- Container System (Blend/Random/Sequence)

**Šta unosi:**
- Audio fajlovi (.wav, .mp3)
- Volume/Pan per layer
- Delay/Offset timing
- Container konfiguracjia

**Šta očekuje:**
- Instant audio feedback na vizuelni event
- Per-reel pan positioning
- Layered win sounds
- Seamless looping za spin

**Friction:**
- ❌ Nema waveform preview u mockup-u
- ❌ Nema A/B testing za različite zvukove
- ❌ Nema real-time mixer view
- ❌ Rollup tick rate nije vizuelno prikazan

**Preporuke:**
1. Mini-waveform u stage trace
2. A/B Audio Comparison mode
3. Inline Volume Meters
4. Rollup Speed Visualizer

---

### 6.3 🧠 Audio Middleware Architect

**Šta koristi:**
- EventRegistry arhitektura
- Stage → Event → Layer hijerarhija
- Container delegation (Blend/Random/Sequence)
- StageConfigurationService

**Šta unosi:**
- Stage definicije
- Priority mappings
- Bus routing rules
- RTPC bindings

**Šta očekuje:**
- Čist, predvidljiv audio flow
- Determinističko ponašanje
- Latency < 3ms
- Voice management

**Friction:**
- ❌ Stage naming nije enforced (case-insensitive workaround)
- ❌ Nema stage validation u UI
- ❌ Container→Event veza nije vidljiva u mockup-u
- ❌ RTPC modulacija nije vizualizovana

**Preporuke:**
1. Stage Validation u EventRegistry
2. Visual Container→Event Flow Diagram
3. RTPC Debug Overlay
4. Priority Collision Detection

---

### 6.4 🛠 Engine / Runtime Developer

**Šta koristi:**
- Rust PlaybackEngine via FFI
- Voice pooling (AudioPool)
- Bus routing (MixerDSPProvider)
- PlaybackSource enum

**Šta unosi:**
- FFI bindings
- Voice allocation strategy
- Buffer size configuration
- SIMD optimizations

**Šta očekuje:**
- Zero-allocation audio path
- Lock-free communication
- < 3ms latency @ 128 samples
- Deterministic playback

**Friction:**
- ❌ No real-time latency display
- ❌ No voice count overlay
- ❌ No buffer underrun indicator
- ❌ No SIMD path indicator

**Preporuke:**
1. Latency Meter Widget
2. Voice Pool Stats Overlay
3. Buffer Health Indicator
4. DSP Load per Stage

---

### 6.5 🧩 Tooling / Editor Developer

**Šta koristi:**
- Flutter widgets (EmbeddedSlotMockup)
- AnimationController for reels
- Timer for jackpot tickers
- GestureDetector for controls

**Šta unosi:**
- Widget kompozicija
- Animation curves
- Touch/Mouse handling
- Theme constants

**Šta očekuje:**
- 60fps rendering
- Responsive layout
- Consistent theming
- Reusable components

**Friction:**
- ❌ Theme hardcoded (ne koristi ThemeModeProvider)
- ❌ Nema ResponsiveLayoutBuilder
- ❌ Symbol emoji render issues na nekim OS
- ❌ No dark/light theme toggle

**Preporuke:**
1. Extract theme to ThemeModeProvider
2. Add ResponsiveLayoutBuilder
3. Use custom symbol icons (not emoji)
4. Add theme preview toggle

---

### 6.6 🎨 UX / UI Designer

**Šta koristi:**
- Visual hierarchy (Header → Jackpot → Reels → Info → Controls)
- Color coding (wins, jackpots, states)
- Animation feedback (spin, stop, win)
- Control grouping (bet, toggles, spin)

**Šta unosi:**
- Layout spacing
- Color palette
- Typography
- Animation timing

**Šta očekuje:**
- Clear visual hierarchy
- Instant feedback on actions
- Consistent color language
- Accessible controls

**Friction:**
- ❌ No accessibility labels (screen reader)
- ❌ No keyboard navigation
- ❌ Forced outcome buttons za testing, ne za UX
- ❌ No hover states na touch devices

**Preporuke:**
1. Add Semantics labels
2. Add keyboard shortcuts
3. Hide forced outcome buttons u production
4. Touch-first hover alternatives

---

### 6.7 🧪 QA / Determinism Engineer

**Šta koristi:**
- ForcedOutcome enum za repeatable tests
- GameState tracking
- Win tier validation
- Audio trigger verification

**Šta unosi:**
- Test scenarios
- Expected outcomes
- Timing requirements
- Audio validation rules

**Šta očekuje:**
- Reproducible spins
- Deterministic audio
- Timing within tolerance
- No flaky behavior

**Friction:**
- ❌ Random seed nije exposed
- ❌ Nema seed replay
- ❌ Audio latency nije measured
- ❌ No automated test hooks

**Preporuke:**
1. Expose RNG seed
2. Add seed capture/replay
3. Latency measurement hooks
4. TestDriver integration

---

### 6.8 🧬 DSP / Audio Processing Engineer

**Šta koristi:**
- Rust rf-dsp crate
- SIMD optimized processors
- Bus routing with effects
- Real-time metering

**Šta unosi:**
- DSP algorithms
- Filter coefficients
- Dynamics settings
- Metering config

**Šta očekuje:**
- Low-latency processing
- SIMD acceleration
- Quality audio output
- CPU efficiency

**Friction:**
- ❌ No DSP chain visible per bus
- ❌ No spectrum analyzer u mockup
- ❌ No true peak indicator
- ❌ No dynamics visualization

**Preporuke:**
1. Mini spectrum analyzer
2. True peak meter
3. DSP load per bus
4. Dynamics GR meter

---

### 6.9 🧭 Producer / Product Owner

**Šta koristi:**
- High-level mockup overview
- Feature completeness check
- User flow validation
- Demo capability

**Šta unosi:**
- Feature requirements
- Priority decisions
- Timeline constraints
- Stakeholder feedback

**Šta očekuje:**
- Demo-ready mockup
- Feature parity with specs
- Smooth user experience
- Measurable metrics

**Friction:**
- ❌ No session recording
- ❌ No usage analytics
- ❌ No A/B testing framework
- ❌ No export for stakeholders

**Preporuke:**
1. Session recording/replay
2. Analytics integration
3. A/B test framework
4. Video export for demos

---

## 7. ŠTA JE IMPLEMENTIRANO

### 7.1 ✅ Core Gameplay
- [x] 5x3 reel grid
- [x] 10 symbol types (3 special: Wild, Scatter, Bonus)
- [x] Staggered reel stops (left to right)
- [x] Turbo mode (faster spins)
- [x] Auto mode (continuous spins)

### 7.2 ✅ Win System
- [x] 6 win tiers (noWin → epicWin)
- [x] Win overlay with tier label
- [x] Rollup animation
- [x] Multiplier display

### 7.3 ✅ Jackpots
- [x] 4-tier jackpot display (Mini/Minor/Major/Grand)
- [x] Smooth value increment (no rolling digits)
- [x] Forced jackpot outcomes

### 7.4 ✅ Controls
- [x] Bet adjustment (+/-)
- [x] Auto/Turbo toggles
- [x] Main SPIN button
- [x] Forced outcome buttons

### 7.5 ✅ Audio Integration
- [x] Visual-Sync callbacks (6 callback types)
- [x] Per-reel REEL_STOP_0..4
- [x] Win tier mapping
- [x] Anticipation trigger
- [x] EventRegistry integration

### 7.6 ✅ State Management
- [x] GameState enum (6 states)
- [x] WinType enum (6 tiers)
- [x] Balance tracking
- [x] Bet management

---

## 8. ŠTA NEDOSTAJE

### 8.1 ❌ Critical (P0)

| Missing Feature | Impact | Effort |
|-----------------|--------|--------|
| Payline Visualization | Nema prikaz winning combinations | Medium |
| Symbol Animation | Symbols statični, nema land/win anim | High |
| REEL_SPIN loop | Spin zvuk se ne loopuje | Low |
| Near Miss Detection | Nema NEAR_MISS stage | Low |

### 8.2 ❌ High Priority (P1)

| Missing Feature | Impact | Effort |
|-----------------|--------|--------|
| Win Line Trace Animation | Nema vizuelno crtanje linije | Medium |
| Symbol Pop/Highlight | Winning symbols ne reaguju | Medium |
| Cascade/Tumble Mode | Samo standard spins | High |
| Free Spins Counter | Nema FS UI | Low |

### 8.3 ❌ Medium Priority (P2)

| Missing Feature | Impact | Effort |
|-----------------|--------|--------|
| Gamble Feature | Nema double-up | Medium |
| Hold & Win | Nema respin mechanic | High |
| Multiplier Display | Samo u win overlay | Low |
| Progressive Jackpot Contribution | Contribution meter | Low |

### 8.4 ❌ Lower Priority (P3)

| Missing Feature | Impact | Effort |
|-----------------|--------|--------|
| Particle Effects | Nema coin shower | Medium |
| Screen Shake | Nema impact feedback | Low |
| Win Amount Popup | Samo overlay | Low |
| Sound Settings | Nema mute/volume | Low |

---

## 9. PREPORUKE ZA POBOLJŠANJA

### 9.1 Immediate (Next Sprint)

```dart
// 1. Add REEL_SPIN looping callback
final VoidCallback? onReelSpinStart;  // When reels start spinning (loop audio)
final VoidCallback? onReelSpinEnd;    // When all reels stopped (stop loop)

// 2. Add Near Miss detection
void _scheduleReelStops() {
  // ... existing code ...

  // After last reel stops, check for near miss
  if (i == widget.reels - 1) {
    if (_detectNearMiss()) {
      widget.onNearMiss?.call();
    }
  }
}

// 3. Add Symbol Land callbacks
final void Function(int reelIndex, int rowIndex, int symbolId)? onSymbolLand;
```

### 9.2 Short Term (Next 2 Sprints)

1. **Payline Visualization:**
   - CustomPainter za crtanje linija
   - Animated path drawing
   - Per-line color coding

2. **Symbol Animations:**
   - Land bounce animation
   - Win pulse/glow effect
   - Wild expand animation

3. **Cascade Mode:**
   - Symbol pop animation
   - Fall-down animation
   - Re-evaluation loop

### 9.3 Long Term (Roadmap)

1. **Full Feature Support:**
   - Free Spins with counter
   - Hold & Win grid
   - Gamble card/ladder
   - Wheel bonus

2. **Audio Enhancements:**
   - Per-symbol land sounds
   - Dynamic music layers
   - Spatial audio per reel
   - Adaptive win music

3. **Polish:**
   - Particle systems
   - Screen shake
   - Haptic feedback
   - Accessibility

---

## ZAKLJUČAK

EmbeddedSlotMockup V3 je solidan foundation za slot audio dizajn sa:

**Strengths:**
- Clean Visual-Sync callback arhitektura
- Proper state machine (GameState)
- Full EventRegistry integration
- Per-reel timing support

**Weaknesses:**
- No payline visualization
- No symbol animations
- No cascade/tumble support
- Limited feature coverage

**Priority Path:**
1. P0: REEL_SPIN loop, Near Miss
2. P1: Paylines, Symbol animations
3. P2: Cascade, Free Spins
4. P3: Effects, Polish

**Estimated Effort:** ~3-4 sprints for full feature parity sa production slot mašinom.
