# Slot Lab Ultimate — Architecture Documentation

## Overview

Slot Lab Ultimate is a comprehensive automated slot game production system that transforms Game Design Documents (GDD) into fully functional audio-ready slot simulations.

## Two Operating Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **GDD-Only** | Scripted outcomes from scenarios | Demos, presentations, audio sync testing |
| **Math-Driven** | Real probability distribution with RTP targeting | Production simulation, statistical analysis |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GDD Document                              │
│  (JSON: game info, symbols, grid, features, win tiers, math)    │
└────────────────────────────┬────────────────────────────────────┘
                             │ GddParser
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                        GameModel                                 │
│  ├── GameInfo (name, id, volatility)                            │
│  ├── GridSpec (reels, rows)                                     │
│  ├── SymbolSet (symbols with payouts)                           │
│  ├── WinMechanism (ways/paylines)                               │
│  ├── FeatureRef[] (feature configurations)                      │
│  ├── WinTierConfig (tier thresholds)                            │
│  ├── TimingProfile (animation speeds)                           │
│  └── MathModel (RTP, hit rate, symbol weights)                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SlotEngineV2                                │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  FeatureRegistry                         │   │
│  │  ├── FreeSpinsChapter                                   │   │
│  │  ├── CascadesChapter                                    │   │
│  │  ├── HoldAndWinChapter                                  │   │
│  │  ├── JackpotChapter                                     │   │
│  │  └── GambleChapter                                      │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│  spin() / spin_forced() → SpinResult + Vec<StageEvent>          │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Scenario System                               │
│  ├── DemoScenario (scripted spin sequences)                     │
│  ├── ScenarioPlayback (playback state machine)                  │
│  └── ScenarioRegistry (8 built-in presets)                      │
└─────────────────────────────────────────────────────────────────┘
```

## Module Structure

### `crates/rf-slot-lab/src/`

```
rf-slot-lab/
├── lib.rs              # Module exports and re-exports
├── engine.rs           # Original SyntheticSlotEngine (v1)
├── engine_v2.rs        # NEW: GameModel-driven SlotEngineV2
├── spin.rs             # SpinResult, ForcedOutcome
├── config.rs           # GridSpec, VolatilityProfile
├── symbols.rs          # SymbolSet, ReelStrip
├── paytable.rs         # Paytable, Payline evaluation
├── timing.rs           # TimingProfile, TimestampGenerator
│
├── model/              # NEW: Game Model system
│   ├── mod.rs
│   ├── game_model.rs   # GameModel struct
│   ├── game_info.rs    # GameInfo, Volatility
│   ├── win_mechanism.rs # WinMechanism (Ways/Paylines)
│   ├── win_tiers.rs    # WinTierConfig, WinTier
│   └── math_model.rs   # MathModel, SymbolWeights
│
├── features/           # NEW: Feature Chapter system
│   ├── mod.rs
│   ├── chapter.rs      # FeatureChapter trait
│   ├── registry.rs     # FeatureRegistry
│   ├── types.rs        # FeatureId, FeatureResult, FeatureState
│   ├── context.rs      # SpinContext, ActivationContext
│   ├── free_spins.rs   # FreeSpinsChapter
│   ├── cascades.rs     # CascadesChapter
│   ├── hold_and_win.rs # HoldAndWinChapter
│   ├── jackpot.rs      # JackpotChapter
│   └── gamble.rs       # GambleChapter
│
├── scenario/           # NEW: Scenario system
│   ├── mod.rs          # DemoScenario, ScenarioPlayback, ScenarioRegistry
│   └── presets.rs      # 8 built-in scenario presets
│
└── parser/             # NEW: GDD Parser
    └── mod.rs          # GddParser, GddDocument, validation
```

## Key Types

### GameModel

Central game definition parsed from GDD:

```rust
pub struct GameModel {
    pub info: GameInfo,           // name, id, volatility
    pub grid: GridSpec,           // reels, rows
    pub symbols: SymbolSet,       // symbol definitions
    pub win_mechanism: WinMechanism, // ways or paylines
    pub features: Vec<FeatureRef>,   // feature configs
    pub win_tiers: WinTierConfig,    // tier thresholds
    pub timing: TimingProfile,       // animation speeds
    pub mode: GameMode,              // GddOnly or MathDriven
    pub math: Option<MathModel>,     // RTP, hit rate (MathDriven only)
}
```

### FeatureChapter Trait

Modular feature implementation:

```rust
pub trait FeatureChapter: Send + Sync {
    fn id(&self) -> FeatureId;
    fn name(&self) -> &str;
    fn category(&self) -> FeatureCategory;

    fn can_activate(&self, context: &ActivationContext) -> bool;
    fn activate(&mut self, context: &ActivationContext);
    fn deactivate(&mut self);

    fn process_spin(&mut self, context: &mut SpinContext) -> FeatureResult;
    fn generate_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent>;
}
```

### DemoScenario

Scripted outcome sequence:

```rust
pub struct DemoScenario {
    pub id: String,
    pub name: String,
    pub description: String,
    pub sequence: Vec<ScriptedSpin>,
    pub loop_mode: LoopMode,  // Once, Forever, Count(n), PingPong
}

pub enum ScriptedOutcome {
    Lose,
    SmallWin { ratio: f64 },
    BigWin { ratio: f64 },
    TriggerFreeSpins { count: u32, multiplier: f64 },
    TriggerJackpot { tier: String },
    CascadeChain { wins: u32 },
    // ...
}
```

## Built-in Scenario Presets

| ID | Name | Description |
|----|------|-------------|
| `win_showcase` | Win Showcase | All win tiers from lose to ultra |
| `free_spins_demo` | Free Spins Demo | Trigger and play through free spins |
| `cascade_demo` | Cascade Demo | Cascade chains with multipliers |
| `jackpot_demo` | Jackpot Demo | Mini → Minor → Major → Grand |
| `hold_and_win_demo` | Hold & Win Demo | Respin feature sequence |
| `stress_test` | Stress Test | 100 rapid spins for performance |
| `audio_test` | Audio Test | Designed for audio sync testing |
| `near_miss_showcase` | Near Miss Showcase | Anticipation scenarios |

## FFI Bridge

### Engine V2 Functions

```c
// Lifecycle
int32_t slot_lab_v2_init();
int32_t slot_lab_v2_init_with_model_json(const char* json);
int32_t slot_lab_v2_init_from_gdd(const char* gdd_json);
void    slot_lab_v2_shutdown();
int32_t slot_lab_v2_is_initialized();

// Spin execution
uint64_t slot_lab_v2_spin();
uint64_t slot_lab_v2_spin_forced(int32_t outcome);

// Results
char* slot_lab_v2_get_spin_result_json();
char* slot_lab_v2_get_stages_json();
char* slot_lab_v2_get_model_json();
char* slot_lab_v2_get_stats_json();
char* slot_lab_v2_last_win_tier();

// Configuration
void slot_lab_v2_set_mode(int32_t mode);  // 0=GddOnly, 1=MathDriven
void slot_lab_v2_set_bet(double bet);
void slot_lab_v2_seed(uint64_t seed);
void slot_lab_v2_reset_stats();
```

### Scenario Functions

```c
// List and load
char*   slot_lab_scenario_list_json();
int32_t slot_lab_scenario_load(const char* id);
int32_t slot_lab_scenario_is_loaded();

// Playback
char*   slot_lab_scenario_next_spin_json();
char*   slot_lab_scenario_progress();  // "current,total"
int32_t slot_lab_scenario_is_complete();
void    slot_lab_scenario_reset();
void    slot_lab_scenario_unload();

// Custom scenarios
int32_t slot_lab_scenario_register_json(const char* json);
char*   slot_lab_scenario_get_json(const char* id);
```

### GDD Parser Functions

```c
char* slot_lab_gdd_validate(const char* gdd_json);
// Returns: {"valid": true/false, "errors": [...]}

char* slot_lab_gdd_to_model(const char* gdd_json);
// Returns: GameModel JSON or {"error": "..."}
```

## GDD JSON Schema

```json
{
  "game": {
    "name": "Mystic Treasures",
    "id": "mystic_treasures",
    "volatility": "high"
  },
  "grid": {
    "reels": 5,
    "rows": 3
  },
  "symbols": [
    {"id": 0, "name": "Wild", "type": "wild", "pays": [0, 0, 50, 200, 1000]},
    {"id": 1, "name": "Scatter", "type": "scatter"},
    {"id": 2, "name": "High1", "type": "regular", "pays": [0, 0, 20, 100, 500]}
  ],
  "win_mechanism": {
    "type": "ways",
    "ways_count": 243
  },
  "features": [
    {"type": "free_spins", "params": {"trigger_count": 3, "spins_awarded": 10}},
    {"type": "cascades", "params": {"multiplier_progression": [1, 2, 3, 5]}}
  ],
  "win_tiers": {
    "tiers": [
      {"name": "small", "min_ratio": 1.0, "max_ratio": 5.0},
      {"name": "big", "min_ratio": 10.0, "max_ratio": 25.0},
      {"name": "mega", "min_ratio": 25.0, "max_ratio": 50.0}
    ],
    "display_threshold": 1.0
  },
  "timing": "normal",
  "math": {
    "target_rtp": 96.5,
    "hit_rate": 0.28
  }
}
```

## Test Coverage

- **rf-slot-lab:** 78 tests
  - Engine V2: 6 tests
  - Feature Chapters: 15 tests
  - Scenario System: 9 tests
  - GDD Parser: 2 tests
  - Model types: 20 tests
  - Legacy engine: 26 tests

## Usage Flow

### 1. GDD-Only Mode (Demo/Presentation)

```
Load GDD → Parse to GameModel → Initialize Engine V2
→ Load Scenario → Play scripted sequence → Audio triggers
```

### 2. Math-Driven Mode (Production)

```
Load GDD with math section → Parse to GameModel
→ Initialize Engine V2 in MathDriven mode
→ Random spins with real probability distribution
```

## Integration Points

- **Existing Slot Lab UI** — Unchanged, works with legacy engine
- **Middleware** — Stage events trigger audio via EventRegistry
- **DAW Timeline** — Stage trace visualization unchanged
- **New V2 UI** — Can use Engine V2 with GameModel features

## Files Modified/Created

### New Files (Phase 0-5)
- `crates/rf-slot-lab/src/engine_v2.rs`
- `crates/rf-slot-lab/src/model/*.rs` (6 files)
- `crates/rf-slot-lab/src/features/*.rs` (10 files)
- `crates/rf-slot-lab/src/scenario/*.rs` (2 files)
- `crates/rf-slot-lab/src/parser/mod.rs`

### Modified Files (Phase 5-6)
- `crates/rf-slot-lab/src/lib.rs` — Added module exports
- `crates/rf-slot-lab/src/spin.rs` — Added `win_tier_name` field
- `crates/rf-bridge/src/slot_lab_ffi.rs` — Added 30+ FFI functions

## Phase 7 — Flutter UI Integration (COMPLETED)

### Dart FFI Bindings

**File:** `flutter_ui/lib/src/rust/slot_lab_v2_ffi.dart` (800 LOC)

Extension on `NativeFFI` providing typed Dart wrappers for all V2 FFI functions:

```dart
extension SlotLabV2FFI on NativeFFI {
  // Engine V2 Lifecycle
  bool slotLabV2Init();
  bool slotLabV2InitWithModel(String modelJson);
  bool slotLabV2InitFromGdd(String gddJson);
  void slotLabV2Shutdown();
  bool slotLabV2IsInitialized();

  // Spin Execution
  int slotLabV2Spin();
  int slotLabV2SpinForced(int outcome);

  // Results (returns parsed JSON)
  Map<String, dynamic>? slotLabV2GetSpinResultJson();
  List<Map<String, dynamic>>? slotLabV2GetStagesJson();
  Map<String, dynamic>? slotLabV2GetModelJson();
  Map<String, dynamic>? slotLabV2GetStatsJson();
  String? slotLabV2LastWinTier();

  // Configuration
  void slotLabV2SetMode(int mode);
  void slotLabV2SetBet(double bet);
  void slotLabV2Seed(int seed);
  void slotLabV2ResetStats();

  // Scenario Management
  List<Map<String, dynamic>>? slotLabScenarioListJson();
  bool slotLabScenarioLoad(String id);
  bool slotLabScenarioIsLoaded();
  Map<String, dynamic>? slotLabScenarioNextSpinJson();
  (int, int)? slotLabScenarioProgress();
  bool slotLabScenarioIsComplete();
  void slotLabScenarioReset();
  void slotLabScenarioUnload();
  bool slotLabScenarioRegister(String json);
  Map<String, dynamic>? slotLabScenarioGetJson(String id);

  // GDD Parser
  Map<String, dynamic>? slotLabGddValidate(String gddJson);
  Map<String, dynamic>? slotLabGddToModel(String gddJson);
}
```

### UI Widgets

#### Game Model Editor

**File:** `flutter_ui/lib/widgets/slot_lab/game_model_editor.dart` (1671 LOC)

Visual editor for creating and editing GameModel definitions:

| Section | Features |
|---------|----------|
| **Game Info** | Name, ID, volatility selector |
| **Grid Config** | Reels/rows input with presets (5x3, 6x4, etc.) |
| **Symbol Editor** | Add/remove/reorder symbols, payout tables |
| **Win Mechanism** | Ways vs Paylines toggle, configuration |
| **Feature Config** | Feature type selector, parameter editors |
| **Win Tiers** | Tier thresholds, display settings |
| **Timing Profile** | Normal/Turbo/Mobile/Studio presets |
| **Math Model** | Target RTP, hit rate (MathDriven mode) |

Features:
- Real-time JSON preview
- Import/Export JSON
- Validation with error display
- Copy to clipboard

#### Scenario Editor

**File:** `flutter_ui/lib/widgets/slot_lab/scenario_editor.dart` (1168 LOC)

Visual editor for creating and managing DemoScenarios:

| Section | Features |
|---------|----------|
| **Scenario List** | Built-in presets + custom scenarios |
| **Sequence Editor** | Add/remove/reorder scripted spins |
| **Outcome Selector** | Visual outcome type picker |
| **Loop Mode** | Once/Forever/Count(n)/PingPong |
| **Preview** | Live spin preview with stage trace |

Features:
- Drag-and-drop reordering
- Duplicate/delete spins
- JSON import/export
- Playback controls

#### GDD Import Panel

**File:** `flutter_ui/lib/widgets/slot_lab/gdd_import_panel.dart` (634 LOC)

File-based GDD import with validation:

| Feature | Description |
|---------|-------------|
| **File Picker** | Load .json GDD files |
| **Drag & Drop** | Drop GDD files onto panel |
| **Validation** | Real-time GDD validation with error display |
| **Preview** | Parsed GameModel preview |
| **Import** | One-click import to Engine V2 |

### SlotLabProvider Integration

**File:** `flutter_ui/lib/providers/slot_lab_provider.dart`

Added Engine V2 and Scenario state management:

```dart
// State
bool _engineV2Initialized = false;
Map<String, dynamic>? _currentGameModel;
List<ScenarioInfo> _availableScenarios = [];
String? _loadedScenarioId;

// Getters
bool get engineV2Initialized;
Map<String, dynamic>? get currentGameModel;
List<ScenarioInfo> get availableScenarios;
String? get loadedScenarioId;
(int, int)? get scenarioProgress;
bool get scenarioIsComplete;

// Engine V2 Methods
bool initEngineV2();
bool initEngineFromGdd(String gddJson);
bool updateGameModel(Map<String, dynamic> model);
void shutdownEngineV2();

// Scenario Methods
bool loadScenario(String scenarioId);
void unloadScenario();
bool registerScenario(Map<String, dynamic> scenarioJson);
bool registerScenarioFromDemoScenario(DemoScenario scenario);
```

### Slot Lab Screen Integration

**File:** `flutter_ui/lib/screens/slot_lab_screen.dart`

Added three new tabs to bottom panel:

```dart
enum _BottomPanelTab {
  timeline,
  busHierarchy,
  profiler,
  rtpc,
  resources,
  auxSends,
  eventLog,
  gameModel,    // NEW
  scenarios,    // NEW
  gddImport,    // NEW
}
```

Tab content builders:
- `_buildGameModelContent()` — GameModelEditor with onModelChanged callback
- `_buildScenariosContent()` — ScenarioEditorPanel with selection/change callbacks
- `_buildGddImportContent()` — GddImportPanel with import callback

## Test Results

```
flutter analyze:     ✅ PASS (0 errors)
cargo build --release: ✅ PASS
cargo test -p rf-slot-lab: ✅ PASS (78 tests)
cargo clippy:        ✅ PASS (warnings only)
```

## Complete File List

### Rust (Phases 0-6)
| File | LOC | Description |
|------|-----|-------------|
| `engine_v2.rs` | 450 | GameModel-driven engine |
| `model/game_model.rs` | 180 | GameModel struct |
| `model/game_info.rs` | 80 | GameInfo, Volatility |
| `model/win_mechanism.rs` | 120 | Ways/Paylines |
| `model/win_tiers.rs` | 150 | WinTierConfig |
| `model/math_model.rs` | 200 | MathModel, weights |
| `features/chapter.rs` | 100 | FeatureChapter trait |
| `features/registry.rs` | 150 | FeatureRegistry |
| `features/types.rs` | 120 | FeatureId, FeatureResult |
| `features/context.rs` | 100 | SpinContext, ActivationContext |
| `features/free_spins.rs` | 280 | FreeSpinsChapter |
| `features/cascades.rs` | 250 | CascadesChapter |
| `features/hold_and_win.rs` | 300 | HoldAndWinChapter |
| `features/jackpot.rs` | 220 | JackpotChapter |
| `features/gamble.rs` | 180 | GambleChapter |
| `scenario/mod.rs` | 350 | DemoScenario, ScenarioPlayback |
| `scenario/presets.rs` | 200 | 8 built-in presets |
| `parser/mod.rs` | 400 | GddParser, validation |

### Dart (Phase 7)
| File | LOC | Description |
|------|-----|-------------|
| `slot_lab_v2_ffi.dart` | 800 | FFI extension bindings |
| `game_model_editor.dart` | 1671 | Visual GameModel editor |
| `scenario_editor.dart` | 1168 | Visual scenario editor |
| `gdd_import_panel.dart` | 634 | GDD file import panel |

### Total: ~6,000 LOC Rust + ~4,300 LOC Dart

## Status: ✅ COMPLETE

All planned features implemented:
- ✅ GameModel system
- ✅ Feature Chapter architecture
- ✅ Scenario system with 8 presets
- ✅ GDD parser with validation
- ✅ FFI bridge (30+ functions)
- ✅ Dart FFI bindings
- ✅ Game Model Editor UI
- ✅ Scenario Editor UI
- ✅ GDD Import Panel
- ✅ SlotLabProvider integration
- ✅ Slot Lab Screen tabs

---

## Related Architecture Documents

| Document | Description |
|----------|-------------|
| [ADAPTIVE_LAYER_ENGINE.md](ADAPTIVE_LAYER_ENGINE.md) | Data-driven, context-aware, metric-reactive music layer system |
| [SLOT_LAB_AUDIO_FEATURES.md](SLOT_LAB_AUDIO_FEATURES.md) | P0-P1 audio improvements (latency, panning, cascades, RTPC) |
| [SLOT_LAB_SYSTEM.md](SLOT_LAB_SYSTEM.md) | Core Slot Lab architecture and stage events |

---

## Phase 8 — Adaptive Layer Engine (PLANNED)

Universal, data-driven layer engine for dynamic game music.

**Core Concepts:**

| Concept | Description |
|---------|-------------|
| **Context** | Game chapter (BASE, FREESPINS, HOLDWIN, etc.) — defines which layers are available |
| **Layer** | Intensity level L1-L5 — energy degree, not a specific audio file |
| **Metrics** | Runtime signals (winTier, winXbet, momentum, etc.) that drive layer transitions |
| **Rules** | Conditions that trigger layer changes (e.g., "if winXbet > 10 → step_up") |

**Key Benefits:**

- **Game-agnostic** — Works with any slot, no hardcoded logic
- **Data-driven** — All behavior defined in JSON, not code
- **Metric-reactive** — Responds to game state changes in real-time
- **Smooth transitions** — Beat-synced, phrase-synced, or immediate

**Architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│                     Adaptive Layer Engine                        │
├─────────────────────────────────────────────────────────────────┤
│  INPUTS (Metrics)              OUTPUTS (Audio State)            │
│  ├── winTier: u8               ├── currentContext: String       │
│  ├── winXbet: f64              ├── currentLevel: u8             │
│  ├── consecutiveWins: u8       ├── targetLevel: u8              │
│  ├── spinsSinceWin: u8         ├── transitionProgress: f64      │
│  ├── featureProgress: f64      └── activeLayerAudioPaths: []    │
│  ├── momentum: f64                                               │
│  └── playerSpeedMode: enum                                       │
└─────────────────────────────────────────────────────────────────┘
```

**Stability Mechanisms:**

- **Cooldown** — Minimum time between level changes
- **Hysteresis** — Different thresholds for up vs down
- **Hold Time** — Condition must persist for N ms before transition
- **Level Inertia** — Higher levels are "stickier" (harder to drop)

**See:** `.claude/architecture/ADAPTIVE_LAYER_ENGINE.md` for complete specification
