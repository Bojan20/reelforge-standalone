# Slot Lab — Premium Fullscreen Preview Mode

**Status:** UPGRADED TO PREMIUM (2026-01-21)
**Priority:** HIGH
**Created:** 2026-01-20
**Last Updated:** 2026-01-21 (v2 - Jackpot logic, UI polish)

---

## Overview

Sound designer radi u Slot Lab sekciji — mapira evente, podešava RTPC krive, importuje audio. Ali pravi test audio dizajna je **celokupno iskustvo igrača**.

**Premium Preview Mode** omogućava:
- Fullscreen slot mašina sa **svim industry-standard elementima**
- Jackpot zone sa 4-tier progressive tickers
- Win Presenter sa rollup animacijom i coin particles
- Bet controls (lines, coin, bet level)
- Auto-spin i Turbo mode
- Settings panel (audio, video, quality)
- Session stats i recent wins history

---

## Widget Files

| File | Description |
|------|-------------|
| `lib/widgets/slot_lab/premium_slot_preview.dart` | **NEW** — Full premium slot UI |
| `lib/widgets/slot_lab/fullscreen_slot_preview.dart` | Legacy basic preview (deprecated) |
| `lib/widgets/slot_lab/slot_preview_widget.dart` | Reusable slot grid component |

---

## UI Zones

### A. Header Zone
```
┌─────────────────────────────────────────────────────────────────┐
│ [≡]  FLUXFORGE    💰 $1,234.56    ⭐VIP 3    🎵 🔊 ⚙️ ⛶ ✕   │
└─────────────────────────────────────────────────────────────────┘
```
- Menu button (hamburger)
- Game logo (FLUXFORGE)
- Balance display (animated with glow on win/loss)
- VIP/Level badge (colored by tier)
- Music toggle
- SFX toggle
- Settings gear → Opens settings panel
- Fullscreen toggle
- Exit/Close button

### B. Jackpot Zone
```
┌─────────────────────────────────────────────────────────────────┐
│   MINI        MINOR        MAJOR          GRAND    CONTRIBUTION │
│   $125.50     $1,250.00    $12,500.00     $125K      $0.12      │
└─────────────────────────────────────────────────────────────────┘
```
- 4 jackpot tickers (Mini, Minor, Major, Grand) — **horizontal layout**
- Optional Mystery jackpot (shows "???")
- Progressive contribution display (inline)
- **Realistic jackpot growth** — jackpots grow based on player bets:
  - MINI: +0.5% of bet per spin
  - MINOR: +0.3% of bet per spin
  - MAJOR: +0.2% of bet per spin
  - GRAND: +0.1% of bet per spin
- **Jackpot wins** — triggered on big wins with probability:
  - ULTRA win (100x+): 1% GRAND, 5% MAJOR
  - EPIC win (50x+): 2% MAJOR, 8% MINOR
  - MEGA win (25x+): 5% MINOR, 15% MINI
  - BIG win (10x+): 10% MINI
- Won jackpots reset to seed value and add to balance

### C. Main Game Zone
- Reel frame (5x3 configurable) — **MAXIMIZED: 80% width, 85% height**
- Symbol grid with animations
- Payline visualizer (gold lines over grid)
- Win highlight overlay (pulsing border)
- Anticipation frame (orange glow)
- Wild expansion layer
- Scatter collection layer
- Cascade/tumble layer
- Background theme gradient
- Ambient particle layer (40 floating particles)
- **Gold border frame** with glossy overlay
- Enhanced shadow/glow effects

### D. Win Presenter
```
┌─────────────────────────────────────────────────────────────────┐
│                    ★ ★ MEGA WIN! ★ ★                           │
│                                                                 │
│                      $12,500.00                                 │
│                      5x MULTIPLIER                              │
│                                                                 │
│                  [COLLECT]    [GAMBLE]                          │
└─────────────────────────────────────────────────────────────────┘
```
- Win amount with rollup animation
- Win tier badge (ULTRA/EPIC/MEGA/BIG/SMALL)
- Multiplier display
- Coin burst particles (3D rotation)
- Collect button
- Gamble button (optional)

### E. Feature Indicators
```
┌──────────────────────────────────────────────────────────────┐
│  ⭐ FREE SPINS 8/10   🎁 BONUS ████░░ 65%   ✕ 3x MULTIPLIER   │
└──────────────────────────────────────────────────────────────┘
```
- Free spin counter
- Bonus meter (progress bar)
- Feature progress bar
- Multiplier trail badge
- Cascade counter
- Special symbol counter

### F. Control Bar
```
┌─────────────────────────────────────────────────────────────────┐
│ LINES    COIN      BET     TOTAL BET                            │
│ ◀ 25 ▶  ◀ 0.10 ▶  ◀ 5 ▶    $12.50                              │
│                                                                 │
│        [MAX BET]  [STOP 45]  [⚡TURBO]     (  SPIN  )           │
└─────────────────────────────────────────────────────────────────┘
```
- Lines selector (◀ ▶)
- Coin value selector (◀ ▶)
- Bet level selector (◀ ▶)
- Total bet display
- Max Bet button (gold gradient)
- Auto-spin button — shows "STOP {count}" when active, "AUTO SPIN" when inactive
- Turbo toggle
- Spin button (88px circle, pulsing)
- Stop button (during spin, red)
- **Compact layout** — reduced button sizes (54px) for more reel space

### G. Info Panels (Left Side)
```
┌──────┐
│ 📊   │  PAY  — Paytable panel
│ ℹ️   │  INFO — Rules panel
│ 📜   │  HIST — Recent wins history
│ 📈   │  STAT — Session stats + RTP
└──────┘
```

### H. Audio/Visual Settings Panel
```
┌─────────────────────────────────┐
│ ⚙️ SETTINGS                  ✕ │
├─────────────────────────────────┤
│ MASTER VOLUME                   │
│ 🔊 ═══════════●═══ 80%         │
│                                 │
│ [🎵 Music ON]  [🔊 SFX ON]     │
│                                 │
│ GRAPHICS QUALITY                │
│ [LOW] [MED] [HIGH]              │
│                                 │
│ [✓] Animations Enabled          │
└─────────────────────────────────┘
```

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `SPACE` | Spin |
| `ESC` | Exit preview / Close panel |
| `M` | Music toggle |
| `S` | Stats panel toggle |
| `T` | Turbo mode toggle |
| `A` | Auto-spin toggle |
| `1-7` | Forced outcomes (debug mode only) |

### Forced Outcomes (Debug Mode)
| Key | Outcome |
|-----|---------|
| `1` | Lose |
| `2` | Small Win |
| `3` | Big Win |
| `4` | Mega Win |
| `5` | Epic Win |
| `6` | Free Spins |
| `7` | Jackpot Grand |

---

## State Management

### Session State (in widget)
```dart
// Balance & betting
double _balance = 1000.0;
int _lines = 25;
double _coinValue = 0.10;
int _betLevel = 5;

// Jackpots (simulated progressive)
double _miniJackpot = 125.50;
double _minorJackpot = 1250.00;
double _majorJackpot = 12500.00;
double _grandJackpot = 125000.00;

// Features
int _freeSpins = 0;
int _freeSpinsRemaining = 0;
double _bonusMeter = 0.0;
int _multiplier = 1;

// Auto-spin
bool _isAutoSpin = false;
int _autoSpinRemaining = 0;

// Settings
bool _isTurbo = false;
bool _isMusicOn = true;
bool _isSfxOn = true;
double _masterVolume = 0.8;
int _graphicsQuality = 2; // 0=Low, 1=Med, 2=High
```

### Preserved State (via Provider)
- Event Registry mappings
- Audio pool contents
- RTPC curve settings
- Composite events
- Undo/redo stack

---

## Visual Theme

### Colors
```dart
class _SlotTheme {
  // Background
  static const bgDeep = Color(0xFF0a0a12);
  static const bgDark = Color(0xFF121218);
  static const bgMid = Color(0xFF1a1a24);
  static const bgSurface = Color(0xFF242432);
  static const bgPanel = Color(0xFF1e1e2a);

  // Jackpot tiers
  static const jackpotGrand = Color(0xFFFFD700); // Gold
  static const jackpotMajor = Color(0xFFFF4080); // Magenta
  static const jackpotMinor = Color(0xFF8B5CF6); // Purple
  static const jackpotMini = Color(0xFF4CAF50);  // Green

  // Win tiers
  static const winUltra = Color(0xFFFF4080);
  static const winEpic = Color(0xFFE040FB);
  static const winMega = Color(0xFFFFD700);
  static const winBig = Color(0xFF40FF90);
  static const winSmall = Color(0xFF40C8FF);
}
```

### Win Tier Thresholds
| Tier | Multiplier | Icon |
|------|------------|------|
| ULTRA | 100x+ | auto_awesome |
| EPIC | 50x+ | bolt |
| MEGA | 25x+ | stars |
| BIG | 10x+ | celebration |
| SMALL | >0x | check_circle |

---

## Implementation Details

### Entry Point
```dart
// slot_lab_screen.dart
if (_isPreviewMode) {
  return PremiumSlotPreview(
    key: ValueKey('fullscreen_slot_${_reelCount}x$_rowCount'),
    onExit: () => setState(() => _isPreviewMode = false),
    reels: _reelCount,
    rows: _rowCount,
  );
}
```

### GDD Import → Fullscreen Preview (V8.1)

When user imports GDD and clicks "Apply Configuration", fullscreen preview opens automatically:

```dart
// slot_lab_screen.dart:_handleGddImport()
if (confirmed == true && mounted) {
  projectProvider.importGdd(result.gdd, generatedSymbols: result.generatedSymbols);

  setState(() {
    _slotLabSettings = _slotLabSettings.copyWith(
      reels: newReels,
      rows: newRows,
      volatility: _volatilityFromGdd(result.gdd.math.volatility),
    );
    _isPreviewMode = true;  // ← Opens fullscreen with new grid
  });
}
```

**Flow:**
1. User clicks GDD Import button
2. GddPreviewDialog shows parsed GDD with grid preview
3. User clicks "Apply Configuration"
4. Grid settings applied + `_isPreviewMode = true`
5. Fullscreen slot machine opens with new dimensions

**ValueKey:** Widget uses `ValueKey('fullscreen_slot_${reels}x${rows}')` to force rebuild when dimensions change.

### Component Hierarchy
```
PremiumSlotPreview
├── _HeaderZone
│   ├── _HeaderIconButton (×8)
│   ├── _BalanceDisplay
│   └── _VipBadge
├── _JackpotZone
│   ├── _JackpotTicker (×4-5)
│   └── _ProgressiveMeter
├── _FeatureIndicators
│   ├── _FeatureBadge
│   └── _FeatureMeter
├── _MainGameZone
│   ├── SlotPreviewWidget
│   ├── _PaylineVisualizer
│   ├── _WinHighlightOverlay
│   └── _AmbientParticlePainter
├── _ControlBar
│   ├── _BetSelector (×3)
│   ├── _TotalBetDisplay
│   ├── _ControlButton (×3)
│   └── _SpinButton
├── _InfoPanels (positioned left)
│   ├── _InfoButton (×4)
│   ├── _RecentWinsPanel
│   └── _SessionStatsPanel
├── _WinPresenter (overlay)
│   └── _CoinParticlePainter
└── _AudioVisualPanel (overlay)
    ├── _SettingToggle
    └── _QualityButton
```

---

## Audio Integration

Preview Mode koristi iste audio pathove kao Slot Lab:

```
SyntheticSlotEngine.spin()
        │
        ▼
    StageEvents
        │
        ▼
SlotLabProvider.playStages()
        │
        ▼
EventRegistry.trigger(stage)
        │
        ▼
AudioPlaybackService.playEvent()
```

---

## Performance

| Aspect | Target | Actual |
|--------|--------|--------|
| Enter/exit transition | < 100ms | ~50ms |
| Frame rate | 60fps | 60fps |
| Particle count | 40 | 40 |
| Jackpot tick rate | 100ms | 100ms (contribution-based) |
| Rollup duration | 1.5s | 1.5s |
| Reel area | 80% width | 80% width, 85% height |
| Header height | 48px | 48px (compact) |
| Control bar height | ~70px | ~70px (compact) |

---

## Future Enhancements

1. **Paytable Panel** — Visual symbol payouts
2. **Symbol Legend** — All symbols with descriptions
3. **Multi-Game Preview** — Switch between configurations
4. **Recording Mode** — Capture gameplay for demo
5. **Remote Preview** — Stream to another device
6. **Tournament Mode** — Leaderboard simulation

---

## Related Documentation

- `.claude/architecture/SLOT_LAB_SYSTEM.md` — SlotLab architecture
- `.claude/architecture/EVENT_SYNC_SYSTEM.md` — Event sync
- `.claude/architecture/UNIFIED_PLAYBACK_SYSTEM.md` — Playback system
