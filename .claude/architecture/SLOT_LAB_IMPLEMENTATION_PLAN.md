# Slot Lab Ultimate — Implementation Plan

## Status: READY FOR IMPLEMENTATION
## Created: 2026-01-20

---

## CURRENT STATE ANALYSIS

### Existing rf-slot-lab Structure

```
crates/rf-slot-lab/src/
├── lib.rs          # Module exports
├── config.rs       # GridSpec, VolatilityProfile, FeatureConfig, SlotConfig
├── engine.rs       # SyntheticSlotEngine (826 LOC) — MONOLITHIC
├── paytable.rs     # PayTable, Payline, LineWin, ScatterWin, EvaluationResult
├── spin.rs         # SpinResult, ForcedOutcome, stage generation
├── symbols.rs      # Symbol, SymbolType, ReelStrip, StandardSymbolSet
└── timing.rs       # TimingProfile, TimingConfig, TimestampGenerator
```

### Strengths (Keep)
- ✅ `GridSpec`, `VolatilityProfile`, `SlotConfig` — dobro dizajnirane strukture
- ✅ `PayTable` i `EvaluationResult` — solidna win evaluacija
- ✅ `TimingConfig` sa audio latency compensation — odlično
- ✅ `SpinResult.generate_stages()` — već generiše stage evente
- ✅ `ForcedOutcome` enum — dobra osnova za scripted outcomes

### Problems (Fix)
- ❌ `engine.rs` je MONOLITHIC — 826 LOC, sve u jednom fajlu
- ❌ Free Spins i Cascades su hardkodirani u `SyntheticSlotEngine`
- ❌ Nema razdvajanja GDD-only vs Math-driven mode
- ❌ Nema Feature Registry — features nisu modularne
- ❌ Nema Demo Scenario system — samo pojedinačni forced outcomes

---

## TRANSFORMATION PLAN

### Phase 1: Core Infrastructure (P0)

#### 1.1 Create `model/` Module

```
rf-slot-lab/src/model/
├── mod.rs
├── game_model.rs      # GameModel central struct
├── game_info.rs       # GameInfo, GameMode enum
├── win_mechanism.rs   # WinMechanism enum (Paylines, Ways, Cluster)
└── win_tiers.rs       # WinTierConfig, WinTier
```

**GameModel** će biti centralna definicija igre:

```rust
// game_model.rs
pub struct GameModel {
    pub info: GameInfo,
    pub grid: GridSpec,           // from config.rs
    pub symbols: SymbolSet,       // enhanced from symbols.rs
    pub paytable: PayTable,       // from paytable.rs
    pub win_mechanism: WinMechanism,
    pub features: Vec<FeatureId>,  // references to Feature Registry
    pub win_tiers: WinTierConfig,
    pub timing: TimingConfig,     // from timing.rs
    pub mode: GameMode,
    pub math: Option<MathModel>,  // only for Math-driven mode
}

pub enum GameMode {
    GddOnly,      // Scripted, no RNG
    MathDriven,   // Real probability distribution
}
```

#### 1.2 Create `features/` Module — Feature Registry

```
rf-slot-lab/src/features/
├── mod.rs
├── registry.rs        # FeatureRegistry singleton
├── chapter.rs         # FeatureChapter trait
├── free_spins.rs      # FreeSpinsChapter
├── cascades.rs        # CascadesChapter
├── hold_and_win.rs    # HoldAndWinChapter
├── jackpot.rs         # JackpotChapter
└── gamble.rs          # GambleChapter
```

**FeatureChapter Trait:**

```rust
// chapter.rs
pub trait FeatureChapter: Send + Sync {
    /// Unique identifier
    fn id(&self) -> FeatureId;

    /// Human-readable name
    fn name(&self) -> &str;

    /// Category (FreeSpins, Bonus, Cascade, etc.)
    fn category(&self) -> FeatureCategory;

    /// Stages this feature can emit
    fn stage_types(&self) -> Vec<Stage>;

    /// Configure from GDD
    fn configure(&mut self, config: FeatureGddConfig) -> Result<(), ConfigError>;

    /// Generate state machine fragment
    fn state_machine_fragment(&self) -> StateMachineFragment;

    /// Process a spin within this feature context
    fn process_spin(&mut self, context: &mut FeatureContext) -> FeatureStepResult;

    /// Generate stages for current state
    fn generate_stages(&self, context: &FeatureContext, timing: &mut TimestampGenerator) -> Vec<StageEvent>;

    /// Is feature currently active?
    fn is_active(&self) -> bool;

    /// Reset feature state
    fn reset(&mut self);
}
```

**Feature Registry:**

```rust
// registry.rs
pub struct FeatureRegistry {
    chapters: HashMap<FeatureId, Box<dyn FeatureChapter>>,
}

impl FeatureRegistry {
    pub fn new() -> Self {
        let mut registry = Self { chapters: HashMap::new() };

        // Register built-in features
        registry.register(Box::new(FreeSpinsChapter::new()));
        registry.register(Box::new(CascadesChapter::new()));
        registry.register(Box::new(HoldAndWinChapter::new()));
        registry.register(Box::new(JackpotChapter::new()));
        registry.register(Box::new(GambleChapter::new()));

        registry
    }

    pub fn get(&self, id: &FeatureId) -> Option<&dyn FeatureChapter>;
    pub fn get_mut(&mut self, id: &FeatureId) -> Option<&mut dyn FeatureChapter>;
    pub fn configure_for_game(&mut self, features: &[FeatureGddConfig]);
}
```

#### 1.3 Refactor `engine.rs` → Use Feature Registry

Current engine.rs has hardcoded:
- Free spins logic (lines 400-500)
- Cascade logic (lines 500-600)
- Feature trigger logic (lines 300-400)

**Refactor to:**

```rust
// engine.rs (refactored)
pub struct SyntheticSlotEngine {
    pub config: SlotConfig,
    pub model: GameModel,
    pub registry: FeatureRegistry,
    pub state: EngineState,
    // ... existing fields
}

impl SyntheticSlotEngine {
    pub fn spin(&mut self) -> SpinResult {
        // 1. Generate grid
        let grid = self.generate_grid();

        // 2. Evaluate wins via PayTable
        let eval = self.model.paytable.evaluate(&grid, self.bet);

        // 3. Delegate to active features
        for feature_id in &self.model.features {
            if let Some(chapter) = self.registry.get_mut(feature_id) {
                if chapter.is_active() {
                    let result = chapter.process_spin(&mut self.context);
                    // Handle result
                }
            }
        }

        // 4. Check for feature triggers
        self.check_feature_triggers(&eval);

        // 5. Build SpinResult
        self.build_result(grid, eval)
    }
}
```

### Phase 2: Scenario System (P1)

#### 2.1 Create `scenario/` Module

```
rf-slot-lab/src/scenario/
├── mod.rs
├── demo.rs            # DemoScenario, ScriptedSpin
├── playback.rs        # ScenarioPlayback engine
├── presets.rs         # Built-in scenario presets
└── builder.rs         # Scenario builder API
```

**DemoScenario:**

```rust
// demo.rs
pub struct DemoScenario {
    pub id: String,
    pub name: String,
    pub description: String,
    pub sequence: Vec<ScriptedSpin>,
    pub loop_mode: LoopMode,
    pub timing_override: Option<TimingConfig>,
}

pub struct ScriptedSpin {
    pub outcome: ScriptedOutcome,
    pub delay_before_ms: Option<f64>,
    pub note: Option<String>,
}

pub enum ScriptedOutcome {
    // Win tiers
    Lose,
    SmallWin { target_ratio: f64 },
    MediumWin { target_ratio: f64 },
    BigWin { target_ratio: f64 },
    MegaWin { target_ratio: f64 },
    EpicWin { target_ratio: f64 },
    UltraWin { target_ratio: f64 },

    // Features
    TriggerFreeSpins { count: u32, multiplier: f64 },
    TriggerHoldAndWin,
    TriggerBonus,
    TriggerJackpot { tier: JackpotTier },

    // Special
    NearMiss { feature: String },
    CascadeChain { wins: u32 },
    SpecificGrid { grid: Vec<Vec<u32>> },

    // Reference another scenario
    SubScenario { scenario_id: String },
}

pub enum LoopMode {
    Once,
    Forever,
    Count(u32),
    PingPong,
}
```

**Scenario Playback:**

```rust
// playback.rs
pub struct ScenarioPlayback {
    scenario: DemoScenario,
    current_index: usize,
    loop_count: u32,
    direction: PlayDirection,
}

impl ScenarioPlayback {
    pub fn new(scenario: DemoScenario) -> Self;
    pub fn next_outcome(&mut self) -> Option<ScriptedOutcome>;
    pub fn reset(&mut self);
    pub fn is_complete(&self) -> bool;
    pub fn progress(&self) -> (usize, usize); // (current, total)
}
```

**Built-in Presets:**

```rust
// presets.rs
impl DemoScenario {
    /// All win tiers from lose to ultra
    pub fn win_showcase() -> Self;

    /// Free spins trigger and complete sequence
    pub fn free_spins_demo() -> Self;

    /// Cascade chain demonstration
    pub fn cascade_demo() -> Self;

    /// Jackpot wheel sequence
    pub fn jackpot_demo() -> Self;

    /// Near miss anticipation showcase
    pub fn near_miss_demo() -> Self;

    /// Full game flow (all features)
    pub fn full_game_flow() -> Self;

    /// Stress test (rapid fire all events)
    pub fn stress_test() -> Self;
}
```

### Phase 3: GDD Parser (P1)

#### 3.1 Create `parser/` Module

```
rf-slot-lab/src/parser/
├── mod.rs
├── gdd.rs             # GddInput, GddParser
├── json.rs            # JSON format parser
├── yaml.rs            # YAML format parser
└── validation.rs      # GDD validation
```

**GDD Parser:**

```rust
// gdd.rs
pub struct GddParser {
    registry: Arc<FeatureRegistry>,
}

impl GddParser {
    pub fn parse(&self, input: GddInput) -> Result<GameModel, GddParseError> {
        match input {
            GddInput::Json(s) => self.parse_json(&s),
            GddInput::Yaml(s) => self.parse_yaml(&s),
            GddInput::Struct(gdd) => self.from_struct(gdd),
        }
    }
}

pub enum GddInput {
    Json(String),
    Yaml(String),
    Struct(StructuredGdd),
}

/// Minimum GDD structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StructuredGdd {
    pub game: GameGdd,
    pub grid: GridGdd,
    pub symbols: Vec<SymbolGdd>,
    pub win_mechanism: String,
    pub features: Vec<FeatureGdd>,
    pub win_tiers: Vec<WinTierGdd>,
    #[serde(default)]
    pub math: Option<MathGdd>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameGdd {
    pub name: String,
    pub id: String,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub volatility: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureGdd {
    #[serde(rename = "type")]
    pub feature_type: String,
    pub trigger: String,
    #[serde(flatten)]
    pub params: HashMap<String, serde_json::Value>,
}
```

### Phase 4: State Machine Generator (P2)

#### 4.1 Create `state_machine/` Module

```
rf-slot-lab/src/state_machine/
├── mod.rs
├── generator.rs       # StateMachineGenerator
├── state.rs           # GameState, StateId
├── transition.rs      # StateTransition
└── executor.rs        # StateMachineExecutor
```

**State Machine:**

```rust
// state.rs
pub struct GameStateMachine {
    pub states: HashMap<StateId, GameState>,
    pub transitions: Vec<StateTransition>,
    pub initial_state: StateId,
    pub current_state: StateId,
}

pub struct GameState {
    pub id: StateId,
    pub name: String,
    pub on_enter_stages: Vec<Stage>,
    pub on_exit_stages: Vec<Stage>,
    pub timeout: Option<Duration>,
}

// generator.rs
pub struct StateMachineGenerator;

impl StateMachineGenerator {
    pub fn generate(model: &GameModel, registry: &FeatureRegistry) -> GameStateMachine {
        let mut sm = GameStateMachine::new();

        // Add base game states
        sm.add_base_game_states();

        // Add feature-specific states from chapters
        for feature_id in &model.features {
            if let Some(chapter) = registry.get(feature_id) {
                let fragment = chapter.state_machine_fragment();
                sm.merge_fragment(fragment);
            }
        }

        sm
    }
}
```

### Phase 5: Mode Switching (P2)

#### 5.1 Add Mode-Aware Spin

```rust
// engine.rs
impl SyntheticSlotEngine {
    pub fn spin(&mut self) -> SpinResult {
        match self.model.mode {
            GameMode::GddOnly => self.spin_scripted(),
            GameMode::MathDriven => self.spin_probabilistic(),
        }
    }

    fn spin_scripted(&mut self) -> SpinResult {
        // Use scenario playback for outcomes
        if let Some(ref mut playback) = self.scenario_playback {
            if let Some(outcome) = playback.next_outcome() {
                return self.spin_forced_outcome(outcome);
            }
        }
        // Fallback to random in GDD-only (demo mode)
        self.generate_random_spin()
    }

    fn spin_probabilistic(&mut self) -> SpinResult {
        // Use math model for real probability distribution
        if let Some(ref math) = self.model.math {
            self.spin_with_math(math)
        } else {
            self.generate_random_spin()
        }
    }
}
```

---

## FILE CHANGES SUMMARY

### New Files to Create

| File | Purpose | LOC Est |
|------|---------|---------|
| `model/mod.rs` | Module exports | 20 |
| `model/game_model.rs` | GameModel struct | 150 |
| `model/game_info.rs` | GameInfo, GameMode | 80 |
| `model/win_mechanism.rs` | WinMechanism enum | 60 |
| `model/win_tiers.rs` | WinTierConfig | 80 |
| `features/mod.rs` | Module exports | 30 |
| `features/registry.rs` | FeatureRegistry | 150 |
| `features/chapter.rs` | FeatureChapter trait | 100 |
| `features/free_spins.rs` | FreeSpinsChapter | 250 |
| `features/cascades.rs` | CascadesChapter | 200 |
| `features/hold_and_win.rs` | HoldAndWinChapter | 200 |
| `features/jackpot.rs` | JackpotChapter | 150 |
| `features/gamble.rs` | GambleChapter | 100 |
| `scenario/mod.rs` | Module exports | 20 |
| `scenario/demo.rs` | DemoScenario structs | 200 |
| `scenario/playback.rs` | ScenarioPlayback | 150 |
| `scenario/presets.rs` | Built-in scenarios | 300 |
| `parser/mod.rs` | Module exports | 20 |
| `parser/gdd.rs` | GddParser | 200 |
| `parser/json.rs` | JSON parsing | 150 |
| `parser/validation.rs` | Validation | 100 |
| `state_machine/mod.rs` | Module exports | 20 |
| `state_machine/generator.rs` | SM Generator | 200 |
| `state_machine/state.rs` | State structs | 150 |

**Total New: ~2,860 LOC**

### Files to Modify

| File | Changes |
|------|---------|
| `lib.rs` | Add new module exports |
| `engine.rs` | Refactor to use FeatureRegistry, add mode switching |
| `config.rs` | Minor additions for feature config |
| `spin.rs` | Extend ForcedOutcome for scripted scenarios |

---

## IMPLEMENTATION ORDER

```
Week 1: Core Infrastructure
├── Day 1-2: model/ module (GameModel, GameInfo, etc.)
├── Day 3-4: features/ module (trait, registry)
└── Day 5: Refactor engine.rs to use registry

Week 2: Feature Chapters
├── Day 1-2: FreeSpinsChapter (extract from engine.rs)
├── Day 3: CascadesChapter
└── Day 4-5: HoldAndWinChapter, JackpotChapter

Week 3: Scenario System
├── Day 1-2: scenario/ module (DemoScenario, playback)
├── Day 3: Built-in presets
└── Day 4-5: Integration with engine

Week 4: GDD Parser & Polish
├── Day 1-2: parser/ module (JSON format)
├── Day 3: Validation and error handling
├── Day 4: Flutter UI integration
└── Day 5: Testing and documentation
```

---

## FLUTTER UI CHANGES

### New Widgets Needed

| Widget | Purpose |
|--------|---------|
| `GameModelEditor` | Visual GDD editor |
| `FeaturePicker` | Select features from registry |
| `ScenarioEditor` | Edit/create demo scenarios |
| `ScenarioPlayer` | Playback controls for scenarios |
| `ModeSwitcher` | Toggle GDD-only ↔ Math-driven |

### Provider Changes

```dart
// slot_lab_provider.dart additions

class SlotLabProvider extends ChangeNotifier {
  // Existing...

  // NEW: Mode switching
  GameMode _mode = GameMode.gddOnly;
  GameMode get mode => _mode;

  void setMode(GameMode mode) {
    _mode = mode;
    // Notify Rust engine
    notifyListeners();
  }

  // NEW: Scenario playback
  DemoScenario? _activeScenario;
  int _scenarioIndex = 0;

  void loadScenario(String scenarioId);
  void playScenario();
  void pauseScenario();
  void resetScenario();
  (int, int) get scenarioProgress;

  // NEW: Feature registry
  List<FeatureInfo> get availableFeatures;
  void enableFeature(String featureId);
  void disableFeature(String featureId);
}
```

---

## FFI BRIDGE ADDITIONS

```rust
// rf-bridge/src/slot_lab_ffi.rs additions

#[no_mangle]
pub extern "C" fn slot_lab_set_mode(mode: i32) -> i32;

#[no_mangle]
pub extern "C" fn slot_lab_load_scenario(scenario_id: *const c_char) -> i32;

#[no_mangle]
pub extern "C" fn slot_lab_play_scenario() -> i32;

#[no_mangle]
pub extern "C" fn slot_lab_get_scenario_progress() -> *mut c_char; // JSON

#[no_mangle]
pub extern "C" fn slot_lab_get_available_features() -> *mut c_char; // JSON

#[no_mangle]
pub extern "C" fn slot_lab_enable_feature(feature_id: *const c_char) -> i32;

#[no_mangle]
pub extern "C" fn slot_lab_parse_gdd(gdd_json: *const c_char) -> *mut c_char; // Returns GameModel JSON or error
```

---

## TESTING STRATEGY

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    // Feature Registry
    #[test]
    fn test_registry_registers_builtin_features();
    #[test]
    fn test_free_spins_chapter_stages();
    #[test]
    fn test_cascades_chapter_multiplier();

    // Scenario
    #[test]
    fn test_scenario_playback_sequence();
    #[test]
    fn test_scenario_loop_modes();

    // GDD Parser
    #[test]
    fn test_parse_minimal_gdd();
    #[test]
    fn test_parse_full_gdd_with_math();
    #[test]
    fn test_validation_errors();

    // State Machine
    #[test]
    fn test_base_game_state_machine();
    #[test]
    fn test_feature_state_merge();
}
```

### Integration Tests

```rust
#[test]
fn test_full_game_flow_gdd_only();

#[test]
fn test_full_game_flow_math_driven();

#[test]
fn test_scenario_generates_correct_stages();
```

---

## SUCCESS CRITERIA

1. **GDD-Only Mode Works**
   - Load minimal GDD JSON → Game runs with scripted outcomes
   - Demo scenarios play through correctly
   - All stages emit at correct times

2. **Feature Registry Works**
   - Features are modular and independently configurable
   - New features can be added without touching engine.rs
   - Features compose correctly (FS + Cascades)

3. **Scenarios Work**
   - Built-in presets (win_showcase, etc.) work correctly
   - Custom scenarios can be created and played
   - Loop modes work (once, forever, ping-pong)

4. **Math-Driven Mode Works**
   - Same GDD + Math model → Realistic distribution
   - RTP approximates target over many spins
   - Feature frequency matches config

5. **Flutter Integration Works**
   - Mode can be switched from UI
   - Scenarios can be selected and played
   - Features can be enabled/disabled

---

*Plan created: 2026-01-20*
*Ready for implementation*
