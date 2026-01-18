# FluxForge Slot Lab — Complete System Documentation

> Synthetic Slot Engine za audio dizajn i testiranje slot igara.

---

## Overview

Slot Lab je fullscreen audio sandbox za slot game audio dizajn. Kombinuje:
- **Synthetic Slot Engine** (rf-slot-lab) — Generisanje slot spinova, wins, stages
- **Stage-Based Audio Triggering** — Automatski audio eventi na osnovu stage-ova
- **Wwise/FMOD-Style Middleware** — Bus routing, RTPC, State/Switch
- **Premium UI/UX** — Casino-grade vizuali, animacije, real-time feedback

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        FLUTTER UI (Slot Lab Screen)                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐│
│  │ StageTrace  │  │ SlotPreview │  │ EventLog    │  │ ForcedOutcomePanel ││
│  │ Widget      │  │ Widget      │  │ Panel       │  │                     ││
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘│
│         │                │                │                     │           │
│         └────────────────┴────────────────┴─────────────────────┤           │
│                                                                 │           │
│  ┌──────────────────────────────────────────────────────────────▼─────────┐│
│  │                     SlotLabProvider (ChangeNotifier)                    ││
│  │  - spin() / spinForced()                                                ││
│  │  - lastResult: SlotLabSpinResult                                        ││
│  │  - lastStages: List<SlotLabStageEvent>                                  ││
│  │  - isPlayingStages / currentStageIndex                                  ││
│  │  - _playStagesSequentially() → triggers MiddlewareProvider              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                      │                                       │
└──────────────────────────────────────┼───────────────────────────────────────┘
                                       │ FFI
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        RUST (rf-bridge/slot_lab_ffi.rs)                      │
│  - slot_lab_init() / slot_lab_shutdown()                                     │
│  - slot_lab_spin() / slot_lab_spin_forced(outcome)                           │
│  - slot_lab_get_spin_result_json() → SlotLabSpinResult                       │
│  - slot_lab_get_stages_json() → List<SlotLabStageEvent>                      │
│  - Global state: SLOT_ENGINE, LAST_RESULT, LAST_STAGES                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RUST (rf-slot-lab crate)                             │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────────────────┐ │
│  │ engine.rs  │  │ symbols.rs │  │ paytable.rs│  │ timing.rs              │ │
│  │ - spin()   │  │ - SymbolSet│  │ - evaluate │  │ - TimingProfile        │ │
│  │ - forced   │  │ - ReelStrip│  │ - LineWin  │  │ - generate_timestamps  │ │
│  └────────────┘  └────────────┘  └────────────┘  └────────────────────────┘ │
│  ┌────────────┐  ┌────────────┐  ┌────────────────────────────────────────┐ │
│  │ config.rs  │  │ spin.rs    │  │ stages.rs                              │ │
│  │ - GridSpec │  │ - SpinResult│ │ - StageEvent enum                      │ │
│  │ - Volatility│ │ - SpinInput│  │ - generate_stages()                    │ │
│  └────────────┘  └────────────┘  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Rust Crate: rf-slot-lab

### Location
```
crates/rf-slot-lab/
├── Cargo.toml
└── src/
    ├── lib.rs           # Public exports
    ├── engine.rs        # SyntheticSlotEngine — main logic
    ├── config.rs        # GridSpec, VolatilityProfile
    ├── symbols.rs       # SymbolSet, ReelStrip, Symbol
    ├── paytable.rs      # Paytable, Payline, LineWin
    ├── timing.rs        # TimingProfile, timestamp generation
    ├── spin.rs          # SpinResult, SpinInput
    └── stages.rs        # StageEvent enum, stage generation
```

### Key Types

```rust
/// Synthetic Slot Engine
pub struct SyntheticSlotEngine {
    config: SlotConfig,
    symbols: SymbolSet,
    paytable: Paytable,
    timing: TimingProfile,
    rng: StdRng,
    stats: SessionStats,
}

/// Spin result with all data
pub struct SpinResult {
    pub spin_id: String,
    pub grid: Vec<Vec<u8>>,           // [reel][row] symbol IDs
    pub bet: f64,
    pub total_win: f64,
    pub win_ratio: f64,
    pub line_wins: Vec<LineWin>,
    pub big_win_tier: Option<WinTier>,
    pub feature_triggered: Option<FeatureType>,
    pub near_miss: bool,
    pub cascades: Vec<CascadeStep>,
    pub free_spin_info: Option<FreeSpinInfo>,
    pub multiplier: f64,
}

/// Stage event for audio triggering
pub struct StageEvent {
    pub stage_type: StageType,
    pub timestamp_ms: f64,
    pub payload: HashMap<String, serde_json::Value>,
}

/// Stage types
pub enum StageType {
    SpinStart,
    ReelSpinning { reel_index: u8 },
    ReelStop { reel_index: u8, symbols: Vec<u8> },
    AnticipationOn { reel_index: u8 },
    AnticipationOff { reel_index: u8 },
    EvaluateWins,
    WinPresent { amount: f64, line_count: u8 },
    WinLineShow { line_index: u8, symbol_count: u8 },
    RollupStart { amount: f64 },
    RollupTick { current: f64, target: f64 },
    RollupEnd { amount: f64 },
    BigWinTier { tier: WinTier },
    FeatureEnter { feature: FeatureType },
    FeatureStep { step: u8 },
    FeatureExit,
    CascadeStart,
    CascadeStep { step: u8 },
    CascadeEnd { total_steps: u8 },
    JackpotTrigger { tier: JackpotTier },
    JackpotPresent { amount: f64 },
    SpinEnd,
}

/// Forced outcome for testing
pub enum ForcedOutcome {
    Lose,
    SmallWin,
    MediumWin,
    BigWin,
    MegaWin,
    EpicWin,
    UltraWin,
    FreeSpins,
    JackpotMini,
    JackpotMinor,
    JackpotMajor,
    JackpotGrand,
    NearMiss,
    Cascade,
}
```

### Volatility Profiles

```rust
pub struct VolatilityProfile {
    pub name: String,
    pub rtp: f64,                    // 0.92 - 0.97
    pub hit_rate: f64,               // 0.20 - 0.40
    pub big_win_threshold: f64,      // 10x bet
    pub mega_win_threshold: f64,     // 25x bet
    pub epic_win_threshold: f64,     // 50x bet
    pub max_win_cap: f64,            // 5000x - 25000x
    pub near_miss_frequency: f64,    // 0.05 - 0.15
    pub feature_frequency: f64,      // 0.01 - 0.05
}

// Presets
VolatilityProfile::low()     // RTP 96%, Hit 35%, Max 5000x
VolatilityProfile::medium()  // RTP 95%, Hit 28%, Max 10000x
VolatilityProfile::high()    // RTP 94%, Hit 22%, Max 25000x
VolatilityProfile::studio()  // RTP 100%, Hit 50%, Max 1000x (testing)
```

### Timing Profiles

```rust
pub struct TimingProfile {
    pub name: String,
    pub spin_start_delay_ms: u32,
    pub reel_spin_duration_ms: u32,
    pub reel_stop_interval_ms: u32,
    pub anticipation_duration_ms: u32,
    pub win_present_delay_ms: u32,
    pub rollup_speed_per_100_ms: f64,
    pub feature_enter_delay_ms: u32,
}

// Presets
TimingProfile::normal()  // Standard casino timing
TimingProfile::turbo()   // 2x speed
TimingProfile::mobile()  // Shorter animations
TimingProfile::studio()  // Minimal delays for audio testing
```

---

## FFI Bridge: slot_lab_ffi.rs

### Location
```
crates/rf-bridge/src/slot_lab_ffi.rs
```

### Global State

```rust
static INITIALIZED: AtomicBool = AtomicBool::new(false);
static SPIN_COUNT: AtomicU64 = AtomicU64::new(0);

static SLOT_ENGINE: Lazy<RwLock<Option<SyntheticSlotEngine>>> =
    Lazy::new(|| RwLock::new(None));

static LAST_RESULT: Lazy<RwLock<Option<SpinResult>>> =
    Lazy::new(|| RwLock::new(None));

static LAST_STAGES: Lazy<RwLock<Vec<StageEvent>>> =
    Lazy::new(|| RwLock::new(Vec::new()));
```

### Exported Functions

```rust
// Lifecycle
pub extern "C" fn slot_lab_init() -> i32
pub extern "C" fn slot_lab_init_audio_test() -> i32  // Studio profile
pub extern "C" fn slot_lab_shutdown()
pub extern "C" fn slot_lab_is_initialized() -> i32

// Spin
pub extern "C" fn slot_lab_spin() -> i32
pub extern "C" fn slot_lab_spin_forced(outcome: i32) -> i32

// Results
pub extern "C" fn slot_lab_get_spin_result_json() -> *mut c_char
pub extern "C" fn slot_lab_get_stages_json() -> *mut c_char
pub extern "C" fn slot_lab_get_stats_json() -> *mut c_char

// Accessors
pub extern "C" fn slot_lab_last_spin_is_win() -> i32
pub extern "C" fn slot_lab_last_spin_total_win() -> f64
pub extern "C" fn slot_lab_last_spin_win_ratio() -> f64
pub extern "C" fn slot_lab_last_spin_cascade_count() -> i32

// Configuration
pub extern "C" fn slot_lab_set_bet(amount: f64)
pub extern "C" fn slot_lab_set_volatility(level: i32)
pub extern "C" fn slot_lab_set_timing_profile(profile: i32)

// Memory
pub extern "C" fn slot_lab_free_string(ptr: *mut c_char)
```

### Outcome Mapping (i32 → ForcedOutcome)

```
0  → Lose
1  → SmallWin
2  → MediumWin
3  → BigWin
4  → MegaWin
5  → EpicWin
6  → UltraWin
7  → FreeSpins
8  → JackpotMini
9  → JackpotMinor
10 → JackpotMajor
11 → JackpotGrand
12 → NearMiss
13 → Cascade
```

---

## Flutter: SlotLabProvider

### Location
```
flutter_ui/lib/providers/slot_lab_provider.dart
```

### Key State

```dart
class SlotLabProvider extends ChangeNotifier {
  // Engine state
  bool _initialized = false;
  bool _isSpinning = false;

  // Last spin data
  SlotLabSpinResult? _lastResult;
  List<SlotLabStageEvent> _lastStages = [];

  // Stage playback
  int _currentStageIndex = 0;
  bool _isPlayingStages = false;
  Timer? _stagePlaybackTimer;

  // Configuration
  double _betAmount = 1.0;
  bool _autoTriggerAudio = true;

  // Connected providers
  MiddlewareProvider? _middleware;
  StageAudioMapper? _audioMapper;

  // Stats
  SlotLabStats? _stats;
}
```

### Public API

```dart
// Lifecycle
bool initialize({bool audioTestMode = false})
void shutdown()

// Spinning
Future<SlotLabSpinResult?> spin()
Future<SlotLabSpinResult?> spinForced(ForcedOutcome outcome)

// Configuration
void setBetAmount(double amount)
void setVolatility(int level)  // 0-3
void setTimingProfile(int profile)  // 0-3

// Connection
void connectMiddleware(MiddlewareProvider middleware)
void connectAudioMapper(StageAudioMapper mapper)

// Manual control
void triggerStageManually(int stageIndex)
void stopStagePlayback()

// Getters
SlotLabSpinResult? get lastResult
List<SlotLabStageEvent> get lastStages
bool get isPlayingStages
int get currentStageIndex
List<List<int>>? get currentGrid
bool get lastSpinWasWin
double get lastWinAmount
SlotLabWinTier? get lastBigWinTier
SlotLabStats? get stats
```

### Stage Playback Flow

```
spin() called
    ↓
FFI: slot_lab_spin()
    ↓
_lastResult = slotLabGetSpinResult()
_lastStages = slotLabGetStages()
    ↓
if (_autoTriggerAudio):
    _playStagesSequentially()
        ↓
    for each stage:
        _triggerStage(stage)
            ↓
        _middleware.postEvent(eventId, context)
        _audioMapper.mapAndTrigger(stageEvent)
            ↓
        wait for (nextStage.timestamp - currentStage.timestamp)
```

---

## Flutter: Data Models

### Location
```
flutter_ui/lib/src/rust/native_ffi.dart (lines 13860-14300)
```

### SlotLabSpinResult

```dart
class SlotLabSpinResult {
  final String spinId;
  final List<List<int>> grid;        // [reel][row] symbol IDs
  final double bet;
  final double totalWin;
  final double winRatio;
  final List<LineWin> lineWins;
  final SlotLabWinTier? bigWinTier;
  final bool featureTriggered;
  final bool nearMiss;
  final bool isFreeSpins;
  final int? freeSpinIndex;
  final double multiplier;
  final int cascadeCount;

  bool get isWin => totalWin > 0;
}
```

### SlotLabStageEvent

```dart
class SlotLabStageEvent {
  final String stageType;            // 'spin_start', 'reel_stop', etc.
  final double timestampMs;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> rawStage;
}
```

### LineWin

```dart
class LineWin {
  final int lineIndex;
  final int symbolId;
  final String symbolName;
  final int matchCount;
  final double winAmount;
  final List<List<int>> positions;   // [[reel, row], ...]
}
```

### ForcedOutcome Enum

```dart
enum ForcedOutcome {
  lose(0),
  smallWin(1),
  mediumWin(2),
  bigWin(3),
  megaWin(4),
  epicWin(5),
  ultraWin(6),
  freeSpins(7),
  jackpotMini(8),
  jackpotMinor(9),
  jackpotMajor(10),
  jackpotGrand(11),
  nearMiss(12),
  cascade(13);
}
```

---

## UI Widgets

### Location
```
flutter_ui/lib/widgets/slot_lab/
├── stage_trace_widget.dart
├── slot_preview_widget.dart
├── event_log_panel.dart
├── audio_hover_preview.dart
├── forced_outcome_panel.dart
├── rtpc_editor_panel.dart
├── bus_hierarchy_panel.dart
├── profiler_panel.dart
├── volatility_dial.dart
├── scenario_controls.dart
├── resources_panel.dart
└── aux_sends_panel.dart
```

### StageTraceWidget

Animirana vizualizacija stage eventa tokom spin playback-a.

```dart
class StageTraceWidget extends StatefulWidget {
  final SlotLabProvider provider;
  final double height;
  final bool showMiniProgress;
}
```

**Features:**
- Horizontalna timeline sa stage markerima
- Animirana playhead pozicija
- Color-coded stage zone
- Pulse efekti na aktivnim stages
- Klik na marker za manuelni trigger

**Stage Colors:**
```dart
'spin_start': Color(0xFF4A9EFF),     // Blue
'reel_stop': Color(0xFF8B5CF6),       // Purple
'anticipation_on': Color(0xFFFF9040), // Orange
'win_present': Color(0xFF40FF90),     // Green
'rollup_start': Color(0xFFFFD700),    // Gold
'bigwin_tier': Color(0xFFFF4080),     // Pink
'feature_enter': Color(0xFF40C8FF),   // Cyan
'jackpot_trigger': Color(0xFFFFD700), // Gold
```

### SlotPreviewWidget

Premium slot machine preview sa animacijama.

```dart
class SlotPreviewWidget extends StatefulWidget {
  final SlotLabProvider provider;
  final int reels;
  final int rows;
  final double reelWidth;
  final double symbolHeight;
  final bool showPaylines;
  final bool showWinAmount;
}
```

**Features:**
- Grafički simboli sa gradient ikonama
- Animated reel spinning sa blur efektom
- Win line highlight overlay (payline vizualizacija)
- Anticipation shake efekti
- Animated win amount countup

**Symbol Definitions:**
```dart
SlotSymbol.symbols = {
  0: WILD   (Icons.stars, gold gradient),
  1: SCATTER (Icons.scatter_plot, purple gradient),
  2: BONUS  (Icons.card_giftcard, cyan gradient),
  3: SEVEN  (Icons.filter_7, pink gradient),
  4: BAR    (Icons.view_headline, green gradient),
  5: BELL   (Icons.notifications, yellow gradient),
  6: CHERRY (Icons.local_florist, orange gradient),
  7: LEMON  (Icons.brightness_5, lime gradient),
  8: ORANGE (Icons.circle, orange gradient),
  9: GRAPE  (Icons.blur_circular, purple gradient),
}
```

### SlotMiniPreview

Kompaktni preview za header (100px).

```dart
class SlotMiniPreview extends StatelessWidget {
  final SlotLabProvider provider;
  final double size;
}
```

### EventLogPanel

Real-time log svih triggered audio eventa.

```dart
class EventLogPanel extends StatefulWidget {
  final SlotLabProvider slotLabProvider;
  final MiddlewareProvider middlewareProvider;
  final double height;
  final int maxEntries;  // Default 500
}
```

**Features:**
- Timestamped entries (HH:MM:SS.mmm)
- Color-coded tipovi (Stage, Middleware, RTPC, State, Audio, Error)
- Filter po event tipu
- Search funkcionalnost
- Auto-scroll sa pause opcijom
- Export to clipboard

**Event Types:**
```dart
enum EventLogType {
  stage,      // Blue
  middleware, // Orange
  rtpc,       // Green
  state,      // Purple
  audio,      // Cyan
  error,      // Red
}
```

### ForcedOutcomePanel

Prominentni test buttons za forced outcomes.

```dart
class ForcedOutcomePanel extends StatefulWidget {
  final SlotLabProvider provider;
  final double height;
  final bool showHistory;
  final bool compact;
}
```

**Features:**
- Vizualni outcome selectors sa gradient ikonama
- 10 outcome tipova: LOSE, SMALL, BIG, MEGA, EPIC, FREE SPINS, JACKPOT, NEAR MISS, CASCADE, ULTRA
- One-click testing
- Keyboard shortcuts (1-0)
- History prikaz sa win amounts

**Keyboard Shortcuts:**
```
1 → Lose
2 → Small Win
3 → Big Win
4 → Mega Win
5 → Epic Win
6 → Free Spins
7 → Jackpot (Grand)
8 → Near Miss
9 → Cascade
0 → Ultra Win
```

### QuickOutcomeBar

Kompaktna horizontalna verzija za brzi pristup.

```dart
class QuickOutcomeBar extends StatelessWidget {
  final SlotLabProvider provider;
  final double height;
}
```

### AudioBrowserItem / AudioBrowserPanel

Audio browser sa hover preview.

```dart
class AudioBrowserItem extends StatefulWidget {
  final AudioFileInfo audioInfo;
  final bool isSelected;
  final bool isPlaying;
  // ...callbacks
}

class AudioBrowserPanel extends StatefulWidget {
  final List<AudioFileInfo> audioFiles;
  // ...callbacks
}
```

**Features:**
- Mini waveform display
- Play on hover (500ms delay)
- Quick play/stop controls
- Duration i format info
- Drag-to-timeline support
- Search i format filter

---

## Stage → Audio Event Mapping

### Stage to Middleware Event IDs

```dart
// In SlotLabProvider._mapStageToEventId()
'spin_start'      → 'slot_spin_start'
'reel_spinning'   → 'slot_reel_spin'
'reel_stop'       → 'slot_reel_stop'
'anticipation_on' → 'slot_anticipation'
'win_present'     → 'slot_win_present'
'win_line_show'   → 'slot_win_line'
'rollup_start'    → 'slot_rollup_start'
'rollup_tick'     → 'slot_rollup_tick'
'rollup_end'      → 'slot_rollup_end'
'bigwin_tier'     → 'slot_bigwin_{tier}'
'feature_enter'   → 'slot_feature_enter'
'feature_step'    → 'slot_feature_step'
'feature_exit'    → 'slot_feature_exit'
'cascade_start'   → 'slot_cascade_start'
'cascade_step'    → 'slot_cascade_step'
'cascade_end'     → 'slot_cascade_end'
'jackpot_trigger' → 'slot_jackpot_trigger'
'jackpot_present' → 'slot_jackpot_present'
'spin_end'        → 'slot_spin_end'
```

### Context Data Passed to Middleware

```dart
Map<String, dynamic> _buildStageContext(SlotLabStageEvent stage) {
  return {
    'stage_type': stage.stageType,
    'timestamp_ms': stage.timestampMs,
    'win_amount': _lastResult?.totalWin,
    'win_ratio': _lastResult?.winRatio,
    'is_win': _lastResult?.isWin,
    'bet_amount': _betAmount,
    ...stage.payload,
  };
}
```

---

## Integration Points

### Slot Lab Screen Integration

```dart
// In slot_lab_screen.dart

// Header - Mini preview
SlotMiniPreview(provider: _slotLabProvider, size: 100)

// Center - Stage progress bar above slot
StageProgressBar(provider: _slotLabProvider, height: 28)

// Bottom Panel - Timeline tab
StageTraceWidget(provider: _slotLabProvider, height: 100)
ForcedOutcomePanel(provider: _slotLabProvider)

// Bottom Panel - Event Log tab
EventLogPanel(
  slotLabProvider: _slotLabProvider,
  middlewareProvider: middleware,
)
```

### Provider Registration

```dart
// In main.dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => SlotLabProvider()),
    ChangeNotifierProvider(create: (_) => MiddlewareProvider()),
    // ...
  ],
)
```

---

## Testing

### Rust Tests

```bash
cargo test -p rf-slot-lab
# 20 tests:
# - engine::tests::test_basic_spin
# - engine::tests::test_forced_win
# - engine::tests::test_forced_loss
# - engine::tests::test_stage_generation
# - engine::tests::test_volatility_slider
# - engine::tests::test_free_spins_trigger
# - engine::tests::test_session_stats
# - paytable::tests::test_paytable_evaluate
# - paytable::tests::test_payline_straight
# - symbols::tests::test_standard_symbol_set
# - symbols::tests::test_reel_strip_wrap
# - symbols::tests::test_symbol_pay
# - timing::tests::test_timing_profiles
# - timing::tests::test_timestamp_generator
# - timing::tests::test_rollup_duration
# - config::tests::test_grid_spec
# - config::tests::test_volatility_interpolate
# - spin::tests::test_spin_result_stages
# - spin::tests::test_forced_outcome
```

### FFI Tests

```bash
cargo test -p rf-bridge slot_lab
# 2 tests:
# - test_slot_lab_lifecycle
# - test_forced_outcomes
```

### Flutter Analyze

```bash
cd flutter_ui && flutter analyze
# Expected: 0 errors, 2 info (unrelated to slot lab)
```

---

## Usage Example

### Basic Spin Flow

```dart
// 1. Initialize
final provider = context.read<SlotLabProvider>();
provider.initialize(audioTestMode: true);

// 2. Connect middleware for audio
provider.connectMiddleware(context.read<MiddlewareProvider>());

// 3. Spin
await provider.spin();

// 4. Access results
final result = provider.lastResult;
print('Win: ${result?.totalWin}');
print('Stages: ${provider.lastStages.length}');

// 5. Stages play automatically with audio triggers
// Or manually:
provider.triggerStageManually(0);
```

### Forced Outcome Testing

```dart
// Test specific outcomes
await provider.spinForced(ForcedOutcome.bigWin);
await provider.spinForced(ForcedOutcome.freeSpins);
await provider.spinForced(ForcedOutcome.jackpotGrand);
await provider.spinForced(ForcedOutcome.nearMiss);
```

---

## Future Enhancements

- [ ] Audio waveform preview in browser
- [ ] Drag audio to timeline regions
- [ ] Custom timing profile editor
- [ ] Volatility curve visualization
- [ ] Session statistics graphs
- [ ] Export spin log to CSV
- [ ] A/B audio comparison mode
- [ ] RTPC curve live preview
- [ ] State machine visualizer
- [ ] WebSocket live connection to game engines

---

## Related Documentation

- [STAGE_INGEST_SYSTEM.md](.claude/architecture/STAGE_INGEST_SYSTEM.md) — Universal stage language
- [ENGINE_INTEGRATION_SYSTEM.md](.claude/architecture/ENGINE_INTEGRATION_SYSTEM.md) — Game engine integration
- [fluxforge-studio.md](.claude/project/fluxforge-studio.md) — Full project spec
