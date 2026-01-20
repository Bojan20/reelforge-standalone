# Slot Lab Ultimate System — Architecture Document

## Verzija: 1.0 (Draft)
## Status: PLANNING PHASE

---

## 1. EXECUTIVE SUMMARY

Slot Lab Ultimate je sistem za **automatizovanu produkciju slot igara** koji iz minimalnog GDD inputa generiše:

1. **Slot Mockup UI** — Interaktivni vizuelni prototip
2. **State Machine** — Kompletna logika toka igre
3. **Feature Chapters** — Modularni feature sistemi
4. **Demo Scenarios** — Scripted sekvence za prezentaciju
5. **Math-Driven Simulator** — Realistična distribucija za audio dizajn

---

## 2. DVA REŽIMA RADA

### 2.1 GDD-Only Mode (Scripted Mockup)

**Svrha:** Brza izrada prototipa BEZ matematike — samo skripta.

```
┌─────────────────────────────────────────────────────────────┐
│                    GDD-ONLY MODE                             │
├─────────────────────────────────────────────────────────────┤
│  INPUT:  GDD dokument (JSON/YAML/parsed)                    │
│                                                              │
│  OUTPUT:                                                     │
│    ├── Slot Mockup UI (vizuelni prototip)                   │
│    ├── State Machine (deterministički tok)                  │
│    ├── Demo Scenarios (scripted sekvence)                   │
│    └── Audio Hooks (stage → event mapiranje)                │
│                                                              │
│  KARAKTERISTIKE:                                             │
│    • Nema RNG-a — sve je skriptirano                        │
│    • Forced outcomes samo                                    │
│    • Idealno za klijent prezentacije                        │
│    • Brza iteracija bez math modela                         │
└─────────────────────────────────────────────────────────────┘
```

**Use Cases:**
- Pitch za klijenta pre math implementacije
- Audio dizajn sa poznatim scenarijima
- UI/UX testiranje bez matematike
- Brzi prototip za game design validaciju

### 2.2 Math-Driven Mode (Realistic Simulator)

**Svrha:** Realistična distribucija sa pravom matematikom.

```
┌─────────────────────────────────────────────────────────────┐
│                   MATH-DRIVEN MODE                           │
├─────────────────────────────────────────────────────────────┤
│  INPUT:  GDD + Math Model (PAR sheet / RTP config)          │
│                                                              │
│  OUTPUT:                                                     │
│    ├── Slot Mockup UI (vizuelni prototip)                   │
│    ├── State Machine (probabilistički tok)                  │
│    ├── Statistical Simulator (RTP validation)               │
│    ├── Realistic Stage Distribution                         │
│    └── Audio Hooks sa weighted probability                  │
│                                                              │
│  KARAKTERISTIKE:                                             │
│    • Prava matematika (symbol weights, hit freq)            │
│    • RTP/volatility simulacija                              │
│    • Realistična frekvencija feature trigera                │
│    • Audio dizajn sa pravom distribucijom                   │
└─────────────────────────────────────────────────────────────┘
```

**Use Cases:**
- Audio dizajn sa realističnom distribucijom
- Feature frequency testing
- Win distribution analysis
- Production-ready audio timing

---

## 3. FEATURE REGISTRY — Modularni Feature Sistem

### 3.1 Koncept

Feature Registry je **biblioteka modularnih feature chapter-a** koje se mogu kombinovati.

```
┌─────────────────────────────────────────────────────────────┐
│                    FEATURE REGISTRY                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ FreeSpins   │  │ HoldAndWin  │  │  Cascades   │         │
│  │  Chapter    │  │   Chapter   │  │   Loop      │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Jackpot    │  │   Gamble    │  │  Expanding  │         │
│  │   Wheel     │  │   Feature   │  │   Wilds     │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Progressive │  │   Mystery   │  │   Bonus    │          │
│  │   Jackpot   │  │   Symbol    │  │   Wheel    │          │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Feature Chapter Interface

Svaki Feature Chapter implementira standardni interface:

```rust
pub trait FeatureChapter: Send + Sync {
    /// Unique identifier
    fn id(&self) -> &str;

    /// Human-readable name
    fn name(&self) -> &str;

    /// Feature category
    fn category(&self) -> FeatureCategory;

    /// Required GDD fields for this feature
    fn required_gdd_fields(&self) -> Vec<GddField>;

    /// Optional GDD fields
    fn optional_gdd_fields(&self) -> Vec<GddField>;

    /// Validate GDD config for this feature
    fn validate_config(&self, config: &FeatureConfig) -> Result<(), ValidationError>;

    /// Generate state machine fragment
    fn generate_state_machine(&self, config: &FeatureConfig) -> StateMachineFragment;

    /// Generate stages for this feature
    fn generate_stages(&self, context: &FeatureContext) -> Vec<StageEvent>;

    /// Audio hooks this feature can trigger
    fn audio_hooks(&self) -> Vec<AudioHook>;

    /// UI components needed
    fn ui_components(&self) -> Vec<UiComponent>;
}
```

### 3.3 Predefinisani Feature Chapters

| Chapter | Opis | Stages |
|---------|------|--------|
| **FreeSpinsChapter** | Standard free spins feature | FS_TRIGGER, FS_INTRO, FS_SPIN, FS_RETRIGGER, FS_OUTRO |
| **HoldAndWinChapter** | Hold & Win / Cash Collect | HAW_TRIGGER, HAW_HOLD, HAW_SPIN, HAW_COLLECT, HAW_JACKPOT |
| **CascadesLoop** | Tumble/Avalanche mechanics | CASCADE_WIN, CASCADE_REMOVE, CASCADE_REFILL, CASCADE_CHECK |
| **JackpotWheel** | Wheel-based jackpot | JP_TRIGGER, JP_WHEEL_SPIN, JP_WHEEL_STOP, JP_AWARD |
| **ExpandingWilds** | Wild expansion feature | WILD_LAND, WILD_EXPAND, WILD_PAYOUT |
| **MysterySymbol** | Mystery/Transform symbols | MYSTERY_LAND, MYSTERY_REVEAL, MYSTERY_PAYOUT |
| **GambleFeature** | Double-or-nothing gamble | GAMBLE_OFFER, GAMBLE_CHOICE, GAMBLE_RESULT |
| **BonusWheel** | Bonus wheel feature | BONUS_TRIGGER, BONUS_SPIN, BONUS_AWARD |
| **ProgressiveJackpot** | Progressive meter system | PJ_CONTRIBUTE, PJ_TRIGGER, PJ_AWARD |
| **Multipliers** | Multiplier mechanics | MULT_ACTIVATE, MULT_INCREASE, MULT_APPLY |

### 3.4 Kompozicija Feature-a

Game može kombinovati više Feature Chapters:

```rust
pub struct GameFeatureSet {
    /// Selected features for this game
    pub features: Vec<Box<dyn FeatureChapter>>,

    /// Feature interaction rules
    pub interactions: Vec<FeatureInteraction>,

    /// Feature priority (for concurrent triggers)
    pub priority_order: Vec<String>,
}

pub enum FeatureInteraction {
    /// One feature can trigger another
    CanTrigger { source: String, target: String },

    /// Features are mutually exclusive
    MutuallyExclusive { features: Vec<String> },

    /// Features can run concurrently
    Concurrent { features: Vec<String> },

    /// Feature modifies another
    Modifies { source: String, target: String, effect: ModifyEffect },
}
```

---

## 4. GAME MODEL — Centralna Definicija Igre

### 4.1 GameModel Structure

```rust
pub struct GameModel {
    /// Basic game info
    pub info: GameInfo,

    /// Grid configuration
    pub grid: GridConfig,

    /// Symbol definitions
    pub symbols: SymbolSet,

    /// Paytable
    pub paytable: Paytable,

    /// Paylines or ways
    pub win_mechanism: WinMechanism,

    /// Active features
    pub features: GameFeatureSet,

    /// Base game stages
    pub base_stages: Vec<StageDefinition>,

    /// Win tiers
    pub win_tiers: WinTierConfig,

    /// Timing profiles
    pub timing: TimingConfig,

    /// Audio mapping
    pub audio_map: AudioStageMap,

    /// Mode (GDD-only or Math-driven)
    pub mode: GameMode,

    /// Math model (optional, for Math-driven mode)
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

pub struct GridConfig {
    pub reels: usize,
    pub rows: usize,
    pub expanding_reels: bool,
    pub megaways: bool,
    pub cluster_pays: bool,
}

pub enum WinMechanism {
    Paylines { lines: Vec<Payline> },
    Ways { max_ways: u64 },
    ClusterPays { min_cluster: usize },
    AllPays,
}

pub enum GameMode {
    GddOnly,
    MathDriven,
}
```

### 4.2 GDD Parsing

GDD dokument se parsira u GameModel:

```rust
pub struct GddParser {
    /// Supported GDD formats
    pub formats: Vec<GddFormat>,

    /// Feature registry reference
    pub feature_registry: Arc<FeatureRegistry>,
}

impl GddParser {
    /// Parse GDD into GameModel
    pub fn parse(&self, input: GddInput) -> Result<GameModel, GddParseError> {
        // 1. Detect format
        // 2. Extract game info
        // 3. Parse grid config
        // 4. Parse symbols
        // 5. Parse paytable
        // 6. Identify features from registry
        // 7. Build GameModel
    }
}

pub enum GddInput {
    Json(String),
    Yaml(String),
    Markdown(String),
    Structured(StructuredGdd),
}
```

---

## 5. STATE MACHINE GENERATOR

### 5.1 Koncept

State Machine se automatski generiše iz GameModel i Feature Chapters.

```
┌─────────────────────────────────────────────────────────────┐
│                   STATE MACHINE GENERATOR                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  GameModel + Features → Composite State Machine              │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                    BASE GAME                         │    │
│  │  IDLE → SPIN_START → REEL_SPIN → REEL_STOP →        │    │
│  │  → WIN_EVAL → [NO_WIN|SMALL|BIG|MEGA|FEATURE] →     │    │
│  │  → WIN_PRESENT → COLLECT → IDLE                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                         │                                    │
│                         ▼                                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │               FEATURE BRANCHES                       │    │
│  │  ┌───────────┐ ┌───────────┐ ┌───────────┐         │    │
│  │  │ FreeSpins │ │HoldAndWin │ │  Cascades │         │    │
│  │  │   FSM     │ │    FSM    │ │    FSM    │         │    │
│  │  └───────────┘ └───────────┘ └───────────┘         │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 State Machine Structure

```rust
pub struct GameStateMachine {
    /// All states in the machine
    pub states: HashMap<StateId, GameState>,

    /// All transitions
    pub transitions: Vec<StateTransition>,

    /// Initial state
    pub initial_state: StateId,

    /// Current state
    pub current_state: StateId,

    /// State history (for debugging/replay)
    pub history: Vec<StateHistoryEntry>,
}

pub struct GameState {
    pub id: StateId,
    pub name: String,
    pub category: StateCategory,

    /// Stage events to emit on enter
    pub on_enter_stages: Vec<StageEvent>,

    /// Stage events to emit on exit
    pub on_exit_stages: Vec<StageEvent>,

    /// Allowed transitions from this state
    pub allowed_transitions: Vec<TransitionId>,

    /// Timeout (auto-transition after duration)
    pub timeout: Option<Duration>,

    /// Auto-advance condition
    pub auto_advance: Option<AutoAdvanceCondition>,
}

pub struct StateTransition {
    pub id: TransitionId,
    pub from: StateId,
    pub to: StateId,
    pub trigger: TransitionTrigger,
    pub condition: Option<TransitionCondition>,
    pub stages: Vec<StageEvent>,
}

pub enum TransitionTrigger {
    /// User action (spin button, etc.)
    UserAction(UserAction),

    /// Automatic after previous state completes
    Auto,

    /// Condition-based
    Condition(TransitionCondition),

    /// Timeout
    Timeout(Duration),

    /// External event
    External(String),
}
```

---

## 6. DEMO SCENARIO SYSTEM

### 6.1 Koncept

Demo Scenarios su **skriptirane sekvence** za prezentacije.

```rust
pub struct DemoScenario {
    pub id: String,
    pub name: String,
    pub description: String,

    /// Sequence of scripted outcomes
    pub sequence: Vec<ScriptedSpin>,

    /// Whether to loop
    pub loop_mode: LoopMode,

    /// Timing overrides
    pub timing: Option<TimingProfile>,
}

pub struct ScriptedSpin {
    /// What outcome to force
    pub outcome: ForcedOutcome,

    /// Optional delay before this spin
    pub delay_before: Option<Duration>,

    /// Optional note/annotation
    pub note: Option<String>,

    /// Optional audio cue override
    pub audio_override: Option<AudioOverride>,
}

pub enum ForcedOutcome {
    /// Predefined outcomes
    Lose,
    SmallWin,
    MediumWin,
    BigWin,
    MegaWin,
    EpicWin,
    UltraWin,

    /// Feature triggers
    TriggerFreeSpins { count: u32 },
    TriggerHoldAndWin,
    TriggerBonus,
    TriggerJackpot { tier: JackpotTier },

    /// Specific grid
    SpecificGrid { symbols: Vec<Vec<Symbol>> },

    /// Near miss
    NearMiss { feature: String },

    /// Cascade chain
    CascadeChain { wins: u32 },
}

pub enum LoopMode {
    /// Play once
    Once,

    /// Loop forever
    Forever,

    /// Loop N times
    Count(u32),

    /// Ping-pong (forward then backward)
    PingPong,
}
```

### 6.2 Predefined Demo Scenarios

| Scenario | Opis | Sekvenca |
|----------|------|----------|
| **WinShowcase** | All win tiers | Lose → Small → Medium → Big → Mega → Epic |
| **FeatureDemo** | Feature trigger showcase | Base → FS Trigger → FS Spins → FS Retrigger → FS End |
| **JackpotDemo** | Jackpot sequence | Base → JP Trigger → Wheel → Grand |
| **CascadeDemo** | Cascade chain | Win → Cascade → Win → Cascade → ... |
| **NearMissDemo** | Anticipation showcase | Near miss → Base → Near miss → Feature |
| **FullGame** | Complete flow | All features in sequence |

---

## 7. OUTPUT GENERATION

### 7.1 UI Mockup Generator

```rust
pub struct UiMockupGenerator {
    pub game_model: Arc<GameModel>,
}

impl UiMockupGenerator {
    /// Generate Flutter widget tree for mockup
    pub fn generate(&self) -> UiMockupSpec {
        UiMockupSpec {
            grid: self.generate_grid_widget(),
            symbols: self.generate_symbol_set(),
            paytable_display: self.generate_paytable_widget(),
            feature_ui: self.generate_feature_widgets(),
            win_display: self.generate_win_display(),
            animations: self.generate_animation_spec(),
        }
    }
}
```

### 7.2 Audio Hook Generator

```rust
pub struct AudioHookGenerator {
    pub game_model: Arc<GameModel>,
}

impl AudioHookGenerator {
    /// Generate audio stage map
    pub fn generate(&self) -> AudioStageMap {
        let mut map = AudioStageMap::new();

        // Base game hooks
        map.add_hook("SPIN_START", AudioHook::new("spin_start"));
        map.add_hook("REEL_SPIN", AudioHook::new("reel_spin_loop"));

        for i in 0..self.game_model.grid.reels {
            map.add_hook(&format!("REEL_STOP_{}", i),
                AudioHook::new(&format!("reel_stop_{}", i)));
        }

        // Win tier hooks
        for tier in &self.game_model.win_tiers.tiers {
            map.add_hook(&format!("{}_WIN", tier.name.to_uppercase()),
                AudioHook::new(&tier.audio_event));
        }

        // Feature hooks from chapters
        for feature in &self.game_model.features.features {
            for hook in feature.audio_hooks() {
                map.add_hook(&hook.stage, hook);
            }
        }

        map
    }
}
```

### 7.3 Scenario Pack Generator

```rust
pub struct ScenarioPackGenerator {
    pub game_model: Arc<GameModel>,
}

impl ScenarioPackGenerator {
    /// Generate standard scenario pack
    pub fn generate(&self) -> ScenarioPack {
        ScenarioPack {
            win_showcase: self.generate_win_showcase(),
            feature_demos: self.generate_feature_demos(),
            stress_test: self.generate_stress_test(),
            edge_cases: self.generate_edge_cases(),
            custom: vec![],
        }
    }

    fn generate_win_showcase(&self) -> DemoScenario {
        DemoScenario {
            id: "win_showcase".into(),
            name: "Win Tier Showcase".into(),
            description: "Shows all win tiers from lose to max win".into(),
            sequence: vec![
                ScriptedSpin { outcome: ForcedOutcome::Lose, .. },
                ScriptedSpin { outcome: ForcedOutcome::SmallWin, .. },
                ScriptedSpin { outcome: ForcedOutcome::MediumWin, .. },
                ScriptedSpin { outcome: ForcedOutcome::BigWin, .. },
                ScriptedSpin { outcome: ForcedOutcome::MegaWin, .. },
                ScriptedSpin { outcome: ForcedOutcome::EpicWin, .. },
            ],
            loop_mode: LoopMode::Once,
            timing: None,
        }
    }
}
```

---

## 8. MINIMUM GDD STANDARD

### 8.1 Obavezna Polja

```yaml
# Minimum GDD za GDD-Only mode
game:
  name: "Game Name"
  id: "game_id"

grid:
  reels: 5
  rows: 3

symbols:
  - id: "wild"
    name: "Wild"
    type: "wild"
  - id: "scatter"
    name: "Scatter"
    type: "scatter"
  - id: "h1"
    name: "High 1"
    type: "high"
  # ... minimum 6 symbols

win_mechanism: "paylines"  # or "ways", "cluster"

features:
  - type: "free_spins"
    trigger: "3+ scatter"
    count: 10

win_tiers:
  - name: "small"
    multiplier_max: 5
  - name: "big"
    multiplier_min: 20
  - name: "mega"
    multiplier_min: 50
```

### 8.2 Opcionalna Polja (za Math-Driven)

```yaml
# Dodatna polja za Math-Driven mode
math:
  target_rtp: 96.5
  volatility: "high"

  symbol_weights:
    wild: [0, 2, 2, 2, 0]  # per reel
    scatter: [3, 3, 3, 3, 3]
    h1: [5, 5, 5, 5, 5]
    # ...

  feature_frequency:
    free_spins: 0.01  # 1 in 100 spins

  paytable:
    - symbol: "wild"
      pays: [0, 0, 50, 100, 500]  # 3/4/5 of a kind
    # ...
```

---

## 9. WORKFLOW — Dynamic Mode Switching

```
┌─────────────────────────────────────────────────────────────┐
│                     SLOT LAB WORKFLOW                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐                                            │
│  │   GDD DOC   │──────┐                                     │
│  └─────────────┘      │                                     │
│                       ▼                                     │
│              ┌─────────────────┐                            │
│              │   GDD PARSER    │                            │
│              └────────┬────────┘                            │
│                       │                                     │
│                       ▼                                     │
│              ┌─────────────────┐                            │
│              │   GAME MODEL    │                            │
│              └────────┬────────┘                            │
│                       │                                     │
│         ┌─────────────┴─────────────┐                       │
│         ▼                           ▼                       │
│  ┌─────────────┐             ┌─────────────┐               │
│  │  GDD-ONLY   │             │MATH-DRIVEN  │               │
│  │    MODE     │◄───────────►│    MODE     │               │
│  └─────────────┘   Switch    └─────────────┘               │
│         │                           │                       │
│         ▼                           ▼                       │
│  ┌─────────────┐             ┌─────────────┐               │
│  │  Scripted   │             │ Probabilist │               │
│  │  Outcomes   │             │  Outcomes   │               │
│  └─────────────┘             └─────────────┘               │
│         │                           │                       │
│         └───────────┬───────────────┘                       │
│                     ▼                                       │
│           ┌─────────────────┐                               │
│           │  STAGE EVENTS   │                               │
│           └────────┬────────┘                               │
│                    │                                        │
│         ┌──────────┼──────────┐                             │
│         ▼          ▼          ▼                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                    │
│  │ UI Mock  │ │  Audio   │ │  State   │                    │
│  │   up     │ │  Hooks   │ │ Machine  │                    │
│  └──────────┘ └──────────┘ └──────────┘                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 10. IMPLEMENTATION PHASES

### Phase 1: Core Infrastructure
- [ ] FeatureChapter trait definition
- [ ] GameModel structure
- [ ] Basic GDD parser (JSON/YAML)
- [ ] State machine generator (base game only)

### Phase 2: Feature Registry
- [ ] FreeSpinsChapter
- [ ] CascadesLoop
- [ ] HoldAndWinChapter
- [ ] Feature composition system

### Phase 3: Output Generators
- [ ] UI Mockup generator
- [ ] Audio hook generator
- [ ] Demo scenario generator
- [ ] Scenario playback engine

### Phase 4: Math Integration
- [ ] Math model parser
- [ ] Probabilistic outcome generator
- [ ] RTP simulator
- [ ] Distribution analyzer

### Phase 5: Polish & Tools
- [ ] GDD validation wizard
- [ ] Feature picker UI
- [ ] Scenario editor
- [ ] Export/import formats

---

## 11. FILE STRUCTURE (Proposed)

```
crates/
├── rf-slot-lab/
│   ├── src/
│   │   ├── lib.rs
│   │   ├── engine.rs           # Core engine (existing, to modify)
│   │   ├── model/
│   │   │   ├── mod.rs
│   │   │   ├── game_model.rs   # GameModel struct
│   │   │   ├── grid.rs         # Grid config
│   │   │   ├── symbols.rs      # Symbol definitions
│   │   │   └── win_tiers.rs    # Win tier config
│   │   ├── features/
│   │   │   ├── mod.rs
│   │   │   ├── registry.rs     # Feature registry
│   │   │   ├── chapter.rs      # FeatureChapter trait
│   │   │   ├── free_spins.rs   # FreeSpinsChapter
│   │   │   ├── cascades.rs     # CascadesLoop
│   │   │   ├── hold_and_win.rs # HoldAndWinChapter
│   │   │   └── ...
│   │   ├── state_machine/
│   │   │   ├── mod.rs
│   │   │   ├── generator.rs    # SM generator
│   │   │   ├── state.rs        # State definitions
│   │   │   └── transition.rs   # Transitions
│   │   ├── scenario/
│   │   │   ├── mod.rs
│   │   │   ├── demo.rs         # Demo scenarios
│   │   │   ├── scripted.rs     # Scripted outcomes
│   │   │   └── playback.rs     # Playback engine
│   │   ├── parser/
│   │   │   ├── mod.rs
│   │   │   ├── gdd.rs          # GDD parser
│   │   │   ├── json.rs         # JSON format
│   │   │   └── yaml.rs         # YAML format
│   │   └── output/
│   │       ├── mod.rs
│   │       ├── ui_mockup.rs    # UI generator
│   │       ├── audio_hooks.rs  # Audio hook generator
│   │       └── scenario_pack.rs # Scenario generator

flutter_ui/lib/
├── widgets/slot_lab/
│   ├── game_model_editor.dart    # GDD editor
│   ├── feature_picker.dart       # Feature selection
│   ├── scenario_editor.dart      # Scenario editor
│   ├── mode_switcher.dart        # GDD/Math mode toggle
│   └── ...
```

---

## 12. CURRENT STATE vs TARGET STATE

### Trenutno Implementirano (rf-slot-lab)

| Komponenta | Status | Napomena |
|------------|--------|----------|
| SyntheticSlotEngine | ✅ | Basic engine sa fixed gridom |
| ForcedOutcome | ✅ | 10 predefinisanih outcome-a |
| StageEvent generation | ✅ | 20+ stage tipova |
| Cascades | ✅ | Basic cascade loop |
| Free Spins | ✅ | Basic free spins |
| FFI Bridge | ✅ | Kompletan bridge za Flutter |

### Nedostaje za Ultimate

| Komponenta | Status | Prioritet |
|------------|--------|-----------|
| FeatureChapter trait | ❌ | P0 |
| Feature Registry | ❌ | P0 |
| GameModel | ❌ | P0 |
| GDD Parser | ❌ | P1 |
| State Machine Generator | ❌ | P1 |
| Demo Scenario System | ❌ | P1 |
| Math Mode | ❌ | P2 |
| UI Mockup Generator | ❌ | P2 |

---

## 13. NEXT STEPS

1. **Definisati FeatureChapter trait** — Interface za sve feature module
2. **Kreirati GameModel** — Centralna struktura igre
3. **Refaktorisati engine.rs** — Odvojiti features u chapters
4. **Implementirati FreeSpinsChapter** — Kao prvi chapter primer
5. **Dodati State Machine Generator** — Za base game
6. **GDD Parser (JSON)** — Minimalni GDD parsing

---

*Dokument kreiran: 2026-01-20*
*Status: DRAFT — čeka review i finalizaciju*
