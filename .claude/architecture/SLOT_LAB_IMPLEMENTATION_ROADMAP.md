# Slot Lab Ultimate — Implementation Roadmap

## Status: MASTER IMPLEMENTATION PLAN
## Created: 2026-01-20

---

# EXECUTIVE SUMMARY

Ovaj dokument definiše **tačan redosled implementacije** Slot Lab Ultimate sistema.
Svaka faza ima jasne deliverable-e, dependencies i acceptance criteria.

**Ukupno: 6 faza, ~45 taskova, ~4,500 LOC novog koda**

---

# PHASE 0: FOUNDATION (Pre-requisites)

> **Cilj:** Pripremiti infrastrukturu za nove module

## 0.1 Kreirati folder strukturu

```
crates/rf-slot-lab/src/
├── model/          # NEW
├── features/       # NEW
├── scenario/       # NEW
├── parser/         # NEW
└── (existing files)
```

**Tasks:**
- [ ] Kreirati `model/mod.rs`
- [ ] Kreirati `features/mod.rs`
- [ ] Kreirati `scenario/mod.rs`
- [ ] Kreirati `parser/mod.rs`
- [ ] Ažurirati `lib.rs` sa novim modulima

**LOC:** ~50
**Dependencies:** None
**Acceptance:** `cargo build` prolazi

---

# PHASE 1: CORE DATA STRUCTURES

> **Cilj:** Definisati osnovne tipove i strukture

## 1.1 GameModel i GameInfo

**File:** `model/game_model.rs`, `model/game_info.rs`

```rust
pub struct GameModel {
    pub info: GameInfo,
    pub grid: GridSpec,
    pub symbols: SymbolSet,
    pub paytable: PayTableConfig,
    pub win_mechanism: WinMechanism,
    pub features: Vec<FeatureId>,
    pub win_tiers: WinTierConfig,
    pub timing: TimingConfig,
    pub mode: GameMode,
    pub math: Option<MathModel>,
}

pub struct GameInfo {
    pub name: String,
    pub id: String,
    pub version: String,
    pub provider: String,
    pub volatility: Volatility,
    pub target_rtp: f64,
}

pub enum GameMode {
    GddOnly,
    MathDriven,
}

pub enum Volatility {
    Low,
    MediumLow,
    Medium,
    MediumHigh,
    High,
    VeryHigh,
}
```

**Tasks:**
- [ ] Kreirati `model/game_info.rs` — GameInfo, GameMode, Volatility
- [ ] Kreirati `model/game_model.rs` — GameModel struct
- [ ] Kreirati `model/win_mechanism.rs` — WinMechanism enum (Paylines, Ways, Cluster)
- [ ] Kreirati `model/win_tiers.rs` — WinTierConfig, WinTier
- [ ] Kreirati `model/math_model.rs` — MathModel (optional, za Math mode)
- [ ] Kreirati `model/mod.rs` — re-exports
- [ ] Unit tests za sve strukture

**LOC:** ~400
**Dependencies:** Phase 0
**Acceptance:** Svi tipovi kompajliraju, tests prolaze

---

## 1.2 FeatureChapter Trait

**File:** `features/chapter.rs`

```rust
pub trait FeatureChapter: Send + Sync {
    fn id(&self) -> FeatureId;
    fn name(&self) -> &str;
    fn category(&self) -> FeatureCategory;
    fn stage_types(&self) -> Vec<Stage>;
    fn configure(&mut self, config: &FeatureConfig) -> Result<(), ConfigError>;
    fn is_active(&self) -> bool;
    fn activate(&mut self, context: &ActivationContext);
    fn deactivate(&mut self);
    fn process_spin(&mut self, context: &mut SpinContext) -> FeatureResult;
    fn generate_stages(&self, timing: &mut TimestampGenerator) -> Vec<StageEvent>;
    fn reset(&mut self);
}

pub struct FeatureId(pub String);

pub enum FeatureCategory {
    FreeSpins,
    Cascade,
    HoldAndWin,
    Jackpot,
    Bonus,
    Gamble,
    Multiplier,
    Wild,
    Other,
}

pub struct FeatureConfig {
    pub params: HashMap<String, serde_json::Value>,
}

pub struct FeatureResult {
    pub continue_feature: bool,
    pub stages: Vec<StageEvent>,
    pub win_contribution: f64,
    pub trigger_other: Option<FeatureId>,
}
```

**Tasks:**
- [ ] Kreirati `features/chapter.rs` — FeatureChapter trait
- [ ] Kreirati `features/types.rs` — FeatureId, FeatureCategory, FeatureConfig
- [ ] Kreirati `features/context.rs` — SpinContext, ActivationContext
- [ ] Kreirati `features/result.rs` — FeatureResult
- [ ] Kreirati `features/mod.rs` — re-exports

**LOC:** ~300
**Dependencies:** Phase 1.1
**Acceptance:** Trait kompajlira, može se implementirati

---

## 1.3 Feature Registry

**File:** `features/registry.rs`

```rust
pub struct FeatureRegistry {
    chapters: HashMap<FeatureId, Box<dyn FeatureChapter>>,
    categories: HashMap<FeatureCategory, Vec<FeatureId>>,
}

impl FeatureRegistry {
    pub fn new() -> Self;
    pub fn register(&mut self, chapter: Box<dyn FeatureChapter>);
    pub fn get(&self, id: &FeatureId) -> Option<&dyn FeatureChapter>;
    pub fn get_mut(&mut self, id: &FeatureId) -> Option<&mut dyn FeatureChapter>;
    pub fn list_all(&self) -> Vec<&FeatureId>;
    pub fn list_by_category(&self, cat: FeatureCategory) -> Vec<&FeatureId>;
    pub fn configure_for_game(&mut self, configs: &[FeatureConfig]) -> Result<(), ConfigError>;
}
```

**Tasks:**
- [ ] Kreirati `features/registry.rs` — FeatureRegistry
- [ ] Dodati thread-safe verziju (Arc<RwLock<>>)
- [ ] Unit tests za registry operacije

**LOC:** ~200
**Dependencies:** Phase 1.2
**Acceptance:** Registry može registrovati i dohvatiti features

---

# PHASE 2: FEATURE CHAPTERS

> **Cilj:** Implementirati konkretne feature chapter-e

## 2.1 FreeSpinsChapter

**File:** `features/free_spins.rs`

Ekstrahovati free spins logiku iz postojećeg `engine.rs`.

```rust
pub struct FreeSpinsChapter {
    config: FreeSpinsConfig,
    state: FreeSpinsState,
}

pub struct FreeSpinsConfig {
    pub trigger_count: u8,          // scatters needed
    pub spins_range: (u32, u32),    // min, max spins
    pub multiplier: f64,            // win multiplier
    pub retrigger_enabled: bool,
    pub retrigger_spins: u32,
}

pub struct FreeSpinsState {
    pub is_active: bool,
    pub spins_remaining: u32,
    pub spins_played: u32,
    pub total_win: f64,
    pub current_multiplier: f64,
}
```

**Tasks:**
- [ ] Kreirati `features/free_spins.rs`
- [ ] Implementirati FeatureChapter trait
- [ ] Ekstrahovati logiku iz engine.rs (linije ~400-500)
- [ ] Stage generation: FS_TRIGGER, FS_INTRO, FS_SPIN, FS_RETRIGGER, FS_OUTRO
- [ ] Unit tests
- [ ] Integration test sa engine

**LOC:** ~350
**Dependencies:** Phase 1.3
**Acceptance:** Free spins rade identično kao pre, ali kroz Chapter

---

## 2.2 CascadesChapter

**File:** `features/cascades.rs`

```rust
pub struct CascadesChapter {
    config: CascadesConfig,
    state: CascadesState,
}

pub struct CascadesConfig {
    pub max_steps: u32,
    pub multiplier_progression: MultiplierProgression,
    pub remove_animation_ms: f64,
    pub refill_animation_ms: f64,
}

pub enum MultiplierProgression {
    None,
    Additive(f64),      // +1x per cascade
    Multiplicative(f64), // *1.5x per cascade
    Custom(Vec<f64>),    // [1x, 2x, 3x, 5x, ...]
}
```

**Tasks:**
- [ ] Kreirati `features/cascades.rs`
- [ ] Implementirati FeatureChapter trait
- [ ] Ekstrahovati logiku iz engine.rs
- [ ] Stage generation: CASCADE_START, CASCADE_STEP, CASCADE_REMOVE, CASCADE_REFILL
- [ ] Multiplier progression logic
- [ ] Unit tests

**LOC:** ~300
**Dependencies:** Phase 1.3
**Acceptance:** Cascades rade kroz Chapter sistem

---

## 2.3 HoldAndWinChapter

**File:** `features/hold_and_win.rs`

```rust
pub struct HoldAndWinChapter {
    config: HoldAndWinConfig,
    state: HoldAndWinState,
}

pub struct HoldAndWinConfig {
    pub trigger_count: u8,
    pub initial_respins: u32,
    pub reset_on_hit: bool,
    pub jackpot_positions: u8,  // positions needed for jackpot
}
```

**Tasks:**
- [ ] Kreirati `features/hold_and_win.rs`
- [ ] Implementirati FeatureChapter trait
- [ ] Stage generation: HAW_TRIGGER, HAW_HOLD, HAW_RESPIN, HAW_COLLECT
- [ ] Jackpot integration
- [ ] Unit tests

**LOC:** ~300
**Dependencies:** Phase 1.3
**Acceptance:** Hold & Win feature radi

---

## 2.4 JackpotChapter

**File:** `features/jackpot.rs`

```rust
pub struct JackpotChapter {
    config: JackpotConfig,
    state: JackpotState,
}

pub struct JackpotConfig {
    pub tiers: Vec<JackpotTierConfig>,
    pub trigger_type: JackpotTriggerType,
}

pub struct JackpotTierConfig {
    pub tier: JackpotTier,
    pub seed_value: f64,
    pub contribution_rate: f64,
}
```

**Tasks:**
- [ ] Kreirati `features/jackpot.rs`
- [ ] Implementirati FeatureChapter trait
- [ ] Stage generation: JP_TRIGGER, JP_WHEEL_SPIN, JP_WHEEL_STOP, JP_AWARD
- [ ] Tier selection logic
- [ ] Unit tests

**LOC:** ~250
**Dependencies:** Phase 1.3
**Acceptance:** Jackpot feature radi

---

## 2.5 GambleChapter

**File:** `features/gamble.rs`

```rust
pub struct GambleChapter {
    config: GambleConfig,
    state: GambleState,
}

pub struct GambleConfig {
    pub max_attempts: u32,
    pub win_chance: f64,  // 0.5 = 50/50
    pub multiplier: f64,   // 2.0 = double or nothing
}
```

**Tasks:**
- [ ] Kreirati `features/gamble.rs`
- [ ] Implementirati FeatureChapter trait
- [ ] Stage generation: GAMBLE_OFFER, GAMBLE_CHOICE, GAMBLE_WIN, GAMBLE_LOSE
- [ ] Unit tests

**LOC:** ~150
**Dependencies:** Phase 1.3
**Acceptance:** Gamble feature radi

---

## 2.6 Registracija Built-in Features

**Tasks:**
- [ ] Ažurirati `FeatureRegistry::new()` da registruje sve built-in features
- [ ] Dodati feature discovery/listing

**LOC:** ~50
**Dependencies:** Phase 2.1-2.5
**Acceptance:** Svi features dostupni kroz registry

---

# PHASE 3: SCENARIO SYSTEM

> **Cilj:** Implementirati Demo Scenario sistem

## 3.1 DemoScenario Strukture

**File:** `scenario/demo.rs`

```rust
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
    Lose,
    SmallWin { ratio: f64 },
    MediumWin { ratio: f64 },
    BigWin { ratio: f64 },
    MegaWin { ratio: f64 },
    EpicWin { ratio: f64 },
    UltraWin { ratio: f64 },
    TriggerFreeSpins { count: u32, multiplier: f64 },
    TriggerHoldAndWin,
    TriggerJackpot { tier: JackpotTier },
    NearMiss { feature: String },
    CascadeChain { wins: u32 },
    SpecificGrid { grid: Vec<Vec<u32>> },
}

pub enum LoopMode {
    Once,
    Forever,
    Count(u32),
    PingPong,
}
```

**Tasks:**
- [ ] Kreirati `scenario/demo.rs`
- [ ] Kreirati `scenario/outcome.rs` — ScriptedOutcome enum
- [ ] Serde serialization/deserialization
- [ ] Unit tests

**LOC:** ~250
**Dependencies:** Phase 1.1
**Acceptance:** Scenario strukture kompajliraju

---

## 3.2 ScenarioPlayback Engine

**File:** `scenario/playback.rs`

```rust
pub struct ScenarioPlayback {
    scenario: DemoScenario,
    current_index: usize,
    loop_count: u32,
    direction: PlayDirection,
    state: PlaybackState,
}

impl ScenarioPlayback {
    pub fn new(scenario: DemoScenario) -> Self;
    pub fn next(&mut self) -> Option<&ScriptedSpin>;
    pub fn peek(&self) -> Option<&ScriptedSpin>;
    pub fn reset(&mut self);
    pub fn is_complete(&self) -> bool;
    pub fn progress(&self) -> (usize, usize);
    pub fn skip_to(&mut self, index: usize);
    pub fn set_loop_mode(&mut self, mode: LoopMode);
}
```

**Tasks:**
- [ ] Kreirati `scenario/playback.rs`
- [ ] Implementirati playback logiku
- [ ] Loop mode handling (Once, Forever, Count, PingPong)
- [ ] Unit tests za sve loop modes

**LOC:** ~200
**Dependencies:** Phase 3.1
**Acceptance:** Playback engine radi sa svim loop modes

---

## 3.3 Built-in Scenario Presets

**File:** `scenario/presets.rs`

```rust
impl DemoScenario {
    pub fn win_showcase() -> Self;
    pub fn free_spins_demo() -> Self;
    pub fn cascade_demo() -> Self;
    pub fn jackpot_demo() -> Self;
    pub fn near_miss_demo() -> Self;
    pub fn full_game_flow() -> Self;
    pub fn stress_test() -> Self;
    pub fn all_presets() -> Vec<Self>;
}
```

**Tasks:**
- [ ] Kreirati `scenario/presets.rs`
- [ ] Implementirati `win_showcase()` — svi win tiers
- [ ] Implementirati `free_spins_demo()` — FS trigger + spins + retrigger
- [ ] Implementirati `cascade_demo()` — cascade chain
- [ ] Implementirati `jackpot_demo()` — jackpot sequence
- [ ] Implementirati `near_miss_demo()` — anticipation showcase
- [ ] Implementirati `full_game_flow()` — kompletan tok igre
- [ ] Implementirati `stress_test()` — rapid fire events

**LOC:** ~400
**Dependencies:** Phase 3.2
**Acceptance:** Svi presets rade korektno

---

# PHASE 4: GDD PARSER

> **Cilj:** Parsirati GDD dokumente u GameModel

## 4.1 GDD JSON Schema

**File:** `parser/schema.rs`

```rust
#[derive(Debug, Serialize, Deserialize)]
pub struct GddDocument {
    pub game: GddGame,
    pub grid: GddGrid,
    pub symbols: Vec<GddSymbol>,
    pub win_mechanism: String,
    pub features: Vec<GddFeature>,
    pub win_tiers: Vec<GddWinTier>,
    #[serde(default)]
    pub math: Option<GddMath>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GddGame {
    pub name: String,
    pub id: String,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub volatility: Option<String>,
    #[serde(default)]
    pub target_rtp: Option<f64>,
}
```

**Tasks:**
- [ ] Kreirati `parser/schema.rs` — GDD struct definitions
- [ ] Dodati serde annotations
- [ ] Validation attributes

**LOC:** ~200
**Dependencies:** Phase 1.1
**Acceptance:** Schema kompajlira, može se deserijalizovati

---

## 4.2 GDD Parser

**File:** `parser/gdd.rs`

```rust
pub struct GddParser {
    registry: Arc<FeatureRegistry>,
    validator: GddValidator,
}

impl GddParser {
    pub fn new(registry: Arc<FeatureRegistry>) -> Self;
    pub fn parse_json(&self, json: &str) -> Result<GameModel, GddParseError>;
    pub fn parse_yaml(&self, yaml: &str) -> Result<GameModel, GddParseError>;
    pub fn validate(&self, doc: &GddDocument) -> Result<(), ValidationError>;
}
```

**Tasks:**
- [ ] Kreirati `parser/gdd.rs` — GddParser
- [ ] Implementirati `parse_json()`
- [ ] Konverzija GddDocument → GameModel
- [ ] Feature matching sa registry
- [ ] Error handling sa detaljnim porukama

**LOC:** ~300
**Dependencies:** Phase 4.1, Phase 1.3
**Acceptance:** JSON GDD se uspešno parsira u GameModel

---

## 4.3 GDD Validator

**File:** `parser/validator.rs`

```rust
pub struct GddValidator {
    limits: GddLimits,
}

pub struct GddLimits {
    pub max_name_length: usize,
    pub max_symbols: usize,
    pub max_paylines: usize,
    pub max_features: usize,
    pub max_reels: usize,
    pub max_rows: usize,
    pub max_pay_value: f64,
}

impl GddValidator {
    pub fn validate(&self, doc: &GddDocument) -> Result<(), ValidationError>;
}
```

**Tasks:**
- [ ] Kreirati `parser/validator.rs`
- [ ] String sanitization (no injection)
- [ ] Numeric bounds checking
- [ ] Required field validation
- [ ] Cross-field validation (e.g., paylines <= reels * rows)

**LOC:** ~200
**Dependencies:** Phase 4.1
**Acceptance:** Invalid GDD vraća jasne error poruke

---

# PHASE 5: ENGINE REFACTOR

> **Cilj:** Refaktorisati engine da koristi nove sisteme

## 5.1 Integracija Feature Registry

**File:** `engine.rs` (modify existing)

**Tasks:**
- [ ] Dodati `FeatureRegistry` u `SyntheticSlotEngine`
- [ ] Zameniti hardcoded free spins sa `FreeSpinsChapter`
- [ ] Zameniti hardcoded cascades sa `CascadesChapter`
- [ ] Dodati feature activation/deactivation
- [ ] Ažurirati spin() da delegira feature-ima

**LOC:** ~200 (changes)
**Dependencies:** Phase 2.6
**Acceptance:** Engine koristi Feature Registry umesto hardcoded logike

---

## 5.2 Integracija GameModel

**Tasks:**
- [ ] Dodati `GameModel` u engine
- [ ] Koristiti GameModel.grid umesto hardcoded
- [ ] Koristiti GameModel.symbols
- [ ] Koristiti GameModel.win_tiers

**LOC:** ~150 (changes)
**Dependencies:** Phase 5.1
**Acceptance:** Engine se konfiguriše kroz GameModel

---

## 5.3 Mode Switching

**Tasks:**
- [ ] Implementirati `spin_gdd_only()` — scripted mode
- [ ] Implementirati `spin_math_driven()` — probabilistic mode
- [ ] Dodati mode switching API
- [ ] Integracija sa ScenarioPlayback

**LOC:** ~200
**Dependencies:** Phase 5.2, Phase 3.2
**Acceptance:** Oba moda rade korektno

---

# PHASE 6: FFI & FLUTTER INTEGRATION

> **Cilj:** Expose nove funkcionalnosti kroz FFI

## 6.1 FFI Bridge Extensions

**File:** `rf-bridge/src/slot_lab_ffi.rs` (modify)

**New Functions:**
```rust
// Mode
pub extern "C" fn slot_lab_set_mode(mode: i32) -> i32;
pub extern "C" fn slot_lab_get_mode() -> i32;

// GDD
pub extern "C" fn slot_lab_load_gdd(json: *const c_char) -> *mut c_char;
pub extern "C" fn slot_lab_get_game_model() -> *mut c_char;

// Scenarios
pub extern "C" fn slot_lab_get_scenarios() -> *mut c_char;
pub extern "C" fn slot_lab_load_scenario(id: *const c_char) -> i32;
pub extern "C" fn slot_lab_scenario_next() -> *mut c_char;
pub extern "C" fn slot_lab_scenario_reset() -> i32;
pub extern "C" fn slot_lab_scenario_progress() -> *mut c_char;

// Features
pub extern "C" fn slot_lab_get_features() -> *mut c_char;
pub extern "C" fn slot_lab_enable_feature(id: *const c_char) -> i32;
pub extern "C" fn slot_lab_disable_feature(id: *const c_char) -> i32;
```

**Tasks:**
- [ ] Implementirati mode funkcije
- [ ] Implementirati GDD funkcije
- [ ] Implementirati scenario funkcije
- [ ] Implementirati feature funkcije
- [ ] Error handling i JSON responses

**LOC:** ~400
**Dependencies:** Phase 5.3
**Acceptance:** Sve FFI funkcije rade

---

## 6.2 Flutter Provider Updates

**File:** `flutter_ui/lib/providers/slot_lab_provider.dart` (modify)

**Tasks:**
- [ ] Dodati mode switching (gddOnly / mathDriven)
- [ ] Dodati scenario loading i playback
- [ ] Dodati feature management
- [ ] Dodati GDD loading
- [ ] Update UI bindings

**LOC:** ~300
**Dependencies:** Phase 6.1
**Acceptance:** Flutter može koristiti sve nove funkcije

---

## 6.3 New Flutter Widgets

**Tasks:**
- [ ] `mode_switcher.dart` — Toggle GDD-only ↔ Math
- [ ] `scenario_selector.dart` — Dropdown sa presets
- [ ] `scenario_progress.dart` — Progress indicator
- [ ] `feature_picker.dart` — Enable/disable features
- [ ] `gdd_loader.dart` — Load GDD file

**LOC:** ~500
**Dependencies:** Phase 6.2
**Acceptance:** UI widgets rade sa provider-om

---

# SUMMARY TABLE

| Phase | Name | Tasks | LOC | Dependencies |
|-------|------|-------|-----|--------------|
| **0** | Foundation | 5 | ~50 | None |
| **1** | Core Data Structures | 15 | ~900 | Phase 0 |
| **2** | Feature Chapters | 12 | ~1,400 | Phase 1 |
| **3** | Scenario System | 10 | ~850 | Phase 1 |
| **4** | GDD Parser | 6 | ~700 | Phase 1, 3 |
| **5** | Engine Refactor | 6 | ~550 | Phase 2, 3, 4 |
| **6** | FFI & Flutter | 8 | ~1,200 | Phase 5 |
| | **TOTAL** | **62** | **~5,650** | |

---

# DEPENDENCY GRAPH

```
Phase 0: Foundation
    │
    ▼
Phase 1: Core Data Structures
    │
    ├─────────────────┬─────────────────┐
    ▼                 ▼                 ▼
Phase 2:          Phase 3:          Phase 4:
Features          Scenarios         GDD Parser
    │                 │                 │
    └────────┬────────┴────────┬────────┘
             │                 │
             ▼                 ▼
         Phase 5: Engine Refactor
                   │
                   ▼
         Phase 6: FFI & Flutter
```

---

# RECOMMENDED ORDER

```
1. Phase 0  → 1 sat
2. Phase 1.1 (GameModel) → 2-3 sata
3. Phase 1.2 (FeatureChapter trait) → 2 sata
4. Phase 1.3 (Registry) → 1-2 sata
5. Phase 2.1 (FreeSpins) → 3 sata
6. Phase 2.2 (Cascades) → 2 sata
7. Phase 3.1-3.2 (Scenario core) → 3 sata
8. Phase 3.3 (Presets) → 2 sata
9. Phase 4.1-4.3 (GDD Parser) → 4 sata
10. Phase 5 (Engine refactor) → 4 sata
11. Phase 6.1 (FFI) → 3 sata
12. Phase 6.2-6.3 (Flutter) → 4 sata
```

**Total estimated: ~30 sati rada**

---

# CRITICAL: PRESERVE EXISTING FLOWS

> ⚠️ **NE MENJAJ POSTOJEĆE INTEGRACIJE — SAMO DODAJ!**

## Postojeći Flow koji MORA ostati netaknut:

### 1. SlotLab → Middleware Flow

```
SlotLabProvider.spin()
    │
    ├─► FFI: slot_lab_spin() → SpinResult + Stages
    │
    ├─► _playStagesSequentially()
    │       │
    │       └─► Za svaki StageEvent:
    │               │
    │               └─► MiddlewareProvider.triggerStageEvent(stage)
    │                       │
    │                       └─► EventRegistry.trigger(stage) → Audio playback
    │
    └─► Update UI (StageTrace, SlotPreview, EventLog)
```

**NIKAD NE MENJAJ:**
- `SlotLabProvider._playStagesSequentially()` logiku
- `MiddlewareProvider.triggerStageEvent()` interface
- `EventRegistry` stage→audio mapping
- FFI funkcije: `slot_lab_spin()`, `slot_lab_get_stages_json()`

### 2. SlotLab → DAW Flow

```
SlotLabProvider
    │
    ├─► AudioPoolProvider (shared audio files)
    │
    ├─► MiddlewareProvider
    │       │
    │       └─► EventRegistry → PreviewEngine (audio playback)
    │
    └─► Timeline integration (future: export to DAW tracks)
```

**NIKAD NE MENJAJ:**
- `AudioPoolProvider` interface
- `PreviewEngine` playback API
- Shared audio file references

### 3. Middleware → DAW Flow

```
MiddlewareProvider
    │
    ├─► Bus routing (6 buses + master)
    │
    ├─► RTPC parameters
    │
    ├─► State/Switch groups
    │
    └─► DAW mixer strip integration
```

**NIKAD NE MENJAJ:**
- Bus structure i routing
- RTPC binding interface
- State/Switch group logic

## Šta MOŽEŠ menjati:

1. **DODAJ** nove module u rf-slot-lab (model/, features/, scenario/, parser/)
2. **DODAJ** nove FFI funkcije (slot_lab_set_mode, slot_lab_load_scenario, etc.)
3. **DODAJ** nove Provider metode (loadScenario, setMode, etc.)
4. **DODAJ** nove widgets (ScenarioSelector, ModeSwitcher, etc.)
5. **REFAKTORIŠI** engine.rs interno — ALI zadrži isti output format
6. **PROŠIRI** StageEvent sa novim tipovima — ALI zadrži postojeće

## Pravilo #1: OUTPUT COMPATIBILITY

```rust
// STARI format MORA raditi:
pub struct SpinResult {
    pub spin_id: String,
    pub grid: Vec<Vec<u8>>,
    pub total_win: f64,
    // ... existing fields
}

// MOŽEŠ dodati NOVA polja:
pub struct SpinResult {
    // ... existing fields (UNCHANGED)

    // NEW optional fields:
    #[serde(default)]
    pub scenario_step: Option<u32>,
    #[serde(default)]
    pub game_mode: Option<String>,
}
```

## Pravilo #2: FFI BACKWARD COMPATIBILITY

```rust
// STARE funkcije MORAJU raditi identično:
slot_lab_init()           // UNCHANGED
slot_lab_spin()           // UNCHANGED
slot_lab_spin_forced()    // UNCHANGED
slot_lab_get_stages_json() // UNCHANGED

// NOVE funkcije DODAJEŠ:
slot_lab_set_mode()       // NEW
slot_lab_load_scenario()  // NEW
slot_lab_scenario_next()  // NEW
```

## Pravilo #3: PROVIDER BACKWARD COMPATIBILITY

```dart
// STARE metode MORAJU raditi:
slotLabProvider.spin()           // UNCHANGED
slotLabProvider.spinForced()     // UNCHANGED
slotLabProvider.lastStages       // UNCHANGED

// NOVE metode DODAJEŠ:
slotLabProvider.setMode()        // NEW
slotLabProvider.loadScenario()   // NEW
slotLabProvider.scenarioNext()   // NEW
```

---

# NEXT IMMEDIATE STEP

**Početi sa Phase 0 i Phase 1.1:**

1. Kreirati folder strukturu
2. Kreirati `model/game_model.rs`
3. Kreirati `model/game_info.rs`
4. `cargo build` za verifikaciju

**CHECKPOINT pre svakog commit-a:**
- [ ] `cargo build --release` prolazi
- [ ] `flutter analyze` nema errors
- [ ] Postojeći SlotLab flow radi (spin → stages → audio)

---

*Document created: 2026-01-20*
*Updated: 2026-01-20 — Added PRESERVE EXISTING FLOWS section*
*Status: READY FOR IMPLEMENTATION*
