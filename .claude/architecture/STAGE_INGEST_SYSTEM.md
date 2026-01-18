# FluxForge Universal Stage Ingest System

> **Definitivni model za sve slot engine-e**
> Verzija: 4.0 | Datum: 2026-01-16

---

## Ekspertska Analiza po Ulogama

Ovaj dokument je analiziran i dopunjen iz perspektive svih uloga definisanih u CLAUDE.md:

| Uloga | Status | Fokus |
|-------|--------|-------|
| **Chief Audio Architect** | ✅ Reviewed | Audio pipeline, ducking, musik tranzicije |
| **Lead DSP Engineer** | ✅ Reviewed | Real-time processing, SIMD, latency |
| **Engine Architect** | ✅ Reviewed | Memory, concurrency, lock-free |
| **Technical Director** | ✅ Reviewed | Architecture, tech decisions |
| **UI/UX Expert** | ✅ Reviewed | Workflow, wizard UX |
| **Graphics Engineer** | ✅ Reviewed | Visualization, stage preview |
| **Security Expert** | ✅ Reviewed | Input validation, sandbox |

---

## Sadržaj

1. [Filozofija](#filozofija)
2. [Stage FSM — Validacija Tranzicija](#2-stage-fsm--validacija-tranzicija)
3. [Hijerarhijski Stagevi](#3-hijerarhijski-stagevi)
4. [Confidence Scoring](#4-confidence-scoring)
5. [Kanonska Stage Taksonomija](#5-kanonska-stage-taksonomija-v2)
6. [Tri Sloja Ingesta](#6-tri-sloja-ingesta)
7. [Adapter Sistem](#7-adapter-sistem)
8. [YAML Adapter Config](#8-yaml-adapter-config-preporučeni-format)
9. [Unity SDK](#10-unity-sdk)
10. [Unreal SDK](#11-unreal-sdk)
11. [Timing Resolver](#12-timing-resolver)
12. [Adapter Wizard](#13-adapter-wizard--automatska-detekcija)
13. [Audio Engine Integracija](#14-audio-engine-integracija)
14. [Crate Struktura](#15-crate-struktura)
15. [Real-Time Constraints](#17-real-time-constraints-dsp-engineer)
16. [Security & Validation](#18-security--validation)
17. [Stage Visualization](#19-stage-visualization-graphics)
18. [Workflow & UX](#20-workflow--ux)
19. [Sledeći Koraci](#16-sledeći-koraci)

---

## Filozofija

FluxForge Studio **ne razume** "engine događaje" direktno.
FluxForge razume samo **kanonske faze toka igre — STAGES**.

Sve spoljašnje strukture, nazivi, formati, JSON šeme i naming konvencije različitih kompanija se **prevode u jedan jezik**.

### Zašto je ovo superiorno

| Tradicionalni pristup | FluxForge pristup |
|-----------------------|-------------------|
| Event bridging (1:1 mapiranje) | Semantička normalizacija |
| Nova firma = nova integracija | Nova firma = novi adapter config |
| Audio zavisi od engine-a | Audio zavisi SAMO od STAGES |
| Promene u engine-u = refaktoring | Promene u engine-u = adapter update |

---

## 1. STAGES — Jedini Univerzalni Jezik

### Semantička istina

Slot igre mogu imati:
- Različite animacije
- Različite trajanja
- Različite JSON strukture
- Različite nazive događaja

**Ali SVE igre prolaze kroz iste faze:**

```
Spin je pokrenut       → SPIN_START
Reels se okreću        → REEL_SPIN (loop audio)
Reels staju            → REEL_STOP (generički) ili REEL_STOP_0..4 (per-reel)
Anticipation aktivan   → ANTICIPATION_ON
Rezultat je poznat     → EVALUATE_WINS
Dobitak se prikazuje   → WIN_PRESENT
Rollup se dešava       → ROLLUP_START / ROLLUP_END
Big win pragovi        → BIGWIN_TIER
Feature se aktivira    → FEATURE_ENTER
Feature ima korake     → FEATURE_STEP
Feature se završava    → FEATURE_EXIT
Cascade/Respin         → CASCADE_STEP
Spin je završen        → SPIN_END
```

### Per-Reel REEL_STOP (IMPLEMENTIRANO)

Za preciznu audio kontrolu svakog reel-a:

| Stage | Opis |
|-------|------|
| `REEL_STOP_0` | Prvi reel stao |
| `REEL_STOP_1` | Drugi reel stao |
| `REEL_STOP_2` | Treći reel stao |
| `REEL_STOP_3` | Četvrti reel stao |
| `REEL_STOP_4` | Peti reel stao |
| `REEL_STOP` | Fallback ako nema per-reel eventa |

### REEL_SPIN Loop (IMPLEMENTIRANO)

- Automatski se trigeruje na `SPIN_START`
- Loop audio dok se rilovi vrte
- Automatski se zaustavlja na `REEL_STOP_4` (poslednji reel)

**STAGE nije animacija.**
**STAGE nije event iz engine-a.**
**STAGE je ZNAČENJE trenutka u toku igre.**

---

## 2. Stage FSM — Validacija Tranzicija

STAGES nisu proizvoljni — postoje **legitimne sekvence**. FSM (Finite State Machine) validira da adapter ne generiše nemoguće tranzicije.

### State Machine Definicija

```rust
pub struct StageFSM {
    current_state: FsmState,
    feature_stack: Vec<FeatureType>,
    valid_transitions: HashMap<FsmState, HashSet<FsmState>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FsmState {
    Idle,
    SpinActive,
    ReelsSpinning,
    ReelsStopping,
    Anticipation,
    WinEvaluation,
    WinPresentation,
    Rollup,
    BigWinCelebration,
    FeatureActive,
    CascadeActive,
    BonusActive,
    GambleActive,
    JackpotActive,
}

impl StageFSM {
    pub fn new() -> Self {
        let mut valid_transitions = HashMap::new();

        // Idle → SpinActive (jedina dozvoljena tranzicija iz Idle)
        valid_transitions.insert(FsmState::Idle, hashset![
            FsmState::SpinActive,
        ]);

        // SpinActive → ReelsSpinning
        valid_transitions.insert(FsmState::SpinActive, hashset![
            FsmState::ReelsSpinning,
        ]);

        // ReelsSpinning → ReelsStopping | Anticipation
        valid_transitions.insert(FsmState::ReelsSpinning, hashset![
            FsmState::ReelsStopping,
            FsmState::Anticipation,
        ]);

        // Anticipation → ReelsStopping
        valid_transitions.insert(FsmState::Anticipation, hashset![
            FsmState::ReelsStopping,
        ]);

        // ReelsStopping → WinEvaluation | ReelsSpinning (za cascade)
        valid_transitions.insert(FsmState::ReelsStopping, hashset![
            FsmState::WinEvaluation,
            FsmState::CascadeActive,
        ]);

        // WinEvaluation → Idle | WinPresentation | FeatureActive
        valid_transitions.insert(FsmState::WinEvaluation, hashset![
            FsmState::Idle,
            FsmState::WinPresentation,
            FsmState::FeatureActive,
            FsmState::BonusActive,
            FsmState::JackpotActive,
        ]);

        // WinPresentation → Rollup | BigWinCelebration | Idle
        valid_transitions.insert(FsmState::WinPresentation, hashset![
            FsmState::Rollup,
            FsmState::BigWinCelebration,
            FsmState::Idle,
            FsmState::GambleActive,
        ]);

        // Rollup → BigWinCelebration | Idle | GambleActive
        valid_transitions.insert(FsmState::Rollup, hashset![
            FsmState::BigWinCelebration,
            FsmState::Idle,
            FsmState::GambleActive,
        ]);

        // BigWinCelebration → Idle | GambleActive
        valid_transitions.insert(FsmState::BigWinCelebration, hashset![
            FsmState::Idle,
            FsmState::GambleActive,
        ]);

        // FeatureActive → SpinActive | Idle (feature završen)
        valid_transitions.insert(FsmState::FeatureActive, hashset![
            FsmState::SpinActive,
            FsmState::Idle,
        ]);

        // CascadeActive → WinEvaluation | Idle
        valid_transitions.insert(FsmState::CascadeActive, hashset![
            FsmState::WinEvaluation,
            FsmState::Idle,
        ]);

        // BonusActive → Idle
        valid_transitions.insert(FsmState::BonusActive, hashset![
            FsmState::Idle,
        ]);

        // GambleActive → Idle | WinPresentation (ako dobije)
        valid_transitions.insert(FsmState::GambleActive, hashset![
            FsmState::Idle,
            FsmState::WinPresentation,
        ]);

        // JackpotActive → Idle
        valid_transitions.insert(FsmState::JackpotActive, hashset![
            FsmState::Idle,
        ]);

        Self {
            current_state: FsmState::Idle,
            feature_stack: Vec::new(),
            valid_transitions,
        }
    }

    /// Pokušaj tranzicije — vraća grešku ako nije validna
    pub fn transition(&mut self, stage: &Stage) -> Result<(), FsmError> {
        let target_state = self.stage_to_fsm_state(stage);

        if let Some(valid) = self.valid_transitions.get(&self.current_state) {
            if valid.contains(&target_state) {
                self.current_state = target_state;
                Ok(())
            } else {
                Err(FsmError::InvalidTransition {
                    from: self.current_state,
                    to: target_state,
                    stage: stage.clone(),
                })
            }
        } else {
            Err(FsmError::NoTransitionsFrom(self.current_state))
        }
    }

    fn stage_to_fsm_state(&self, stage: &Stage) -> FsmState {
        match stage {
            Stage::SpinStart => FsmState::SpinActive,
            Stage::ReelSpinning { .. } => FsmState::ReelsSpinning,
            Stage::ReelStop { .. } => FsmState::ReelsStopping,
            Stage::AnticipationOn { .. } => FsmState::Anticipation,
            Stage::AnticipationOff { .. } => FsmState::ReelsStopping,
            Stage::EvaluateWins => FsmState::WinEvaluation,
            Stage::WinPresent | Stage::WinLineShow { .. } => FsmState::WinPresentation,
            Stage::RollupStart | Stage::RollupTick | Stage::RollupEnd => FsmState::Rollup,
            Stage::BigWinTier { .. } => FsmState::BigWinCelebration,
            Stage::FeatureEnter { .. } | Stage::FeatureStep { .. } | Stage::FeatureExit => FsmState::FeatureActive,
            Stage::CascadeStart | Stage::CascadeStep { .. } | Stage::CascadeEnd => FsmState::CascadeActive,
            Stage::BonusEnter | Stage::BonusChoice | Stage::BonusReveal | Stage::BonusExit => FsmState::BonusActive,
            Stage::GambleStart | Stage::GambleChoice | Stage::GambleResult { .. } | Stage::GambleEnd => FsmState::GambleActive,
            Stage::JackpotTrigger { .. } | Stage::JackpotPresent | Stage::JackpotEnd => FsmState::JackpotActive,
            Stage::SpinEnd | Stage::IdleStart | Stage::IdleLoop => FsmState::Idle,
            _ => FsmState::Idle,
        }
    }
}

#[derive(Debug, Clone)]
pub enum FsmError {
    InvalidTransition {
        from: FsmState,
        to: FsmState,
        stage: Stage,
    },
    NoTransitionsFrom(FsmState),
}
```

### Dijagram tranzicija

```
                    ┌────────────────────────────────────────────────┐
                    │                                                │
                    ▼                                                │
              ┌──────────┐                                           │
              │   IDLE   │◄──────────────────────────────────────────┤
              └────┬─────┘                                           │
                   │ SpinStart                                       │
                   ▼                                                 │
            ┌─────────────┐                                          │
            │ SpinActive  │                                          │
            └──────┬──────┘                                          │
                   │                                                 │
                   ▼                                                 │
          ┌────────────────┐                                         │
          │ ReelsSpinning  │◄─────┐                                  │
          └───────┬────────┘      │                                  │
                  │               │ (cascade restart)                │
         ┌────────┴────────┐      │                                  │
         │                 │      │                                  │
         ▼                 ▼      │                                  │
┌────────────────┐  ┌─────────────┴───┐                              │
│  Anticipation  │  │  ReelsStopping  │                              │
└───────┬────────┘  └────────┬────────┘                              │
        │                    │                                       │
        └──────────┬─────────┘                                       │
                   │                                                 │
                   ▼                                                 │
          ┌────────────────┐                                         │
          │ WinEvaluation  │──────┬──────────────────────────────────┤
          └───────┬────────┘      │                                  │
                  │               │                                  │
     ┌────────────┼───────────┐   │                                  │
     │            │           │   │                                  │
     ▼            ▼           ▼   ▼                                  │
┌─────────┐ ┌──────────┐ ┌────────────┐ ┌──────────────┐             │
│ Feature │ │  Bonus   │ │  Jackpot   │ │WinPresentation│            │
│ Active  │ │  Active  │ │  Active    │ └──────┬───────┘             │
└────┬────┘ └────┬─────┘ └─────┬──────┘        │                     │
     │           │             │               ▼                     │
     │           │             │        ┌────────────┐               │
     │           │             │        │   Rollup   │               │
     │           │             │        └──────┬─────┘               │
     │           │             │               │                     │
     │           │             │               ▼                     │
     │           │             │      ┌───────────────────┐          │
     │           │             │      │ BigWinCelebration │          │
     │           │             │      └─────────┬─────────┘          │
     │           │             │                │                    │
     │           │             │                ▼                    │
     │           │             │         ┌────────────┐              │
     │           │             │         │   Gamble   │──────────────┤
     │           │             │         │   Active   │              │
     │           │             │         └────────────┘              │
     │           │             │                                     │
     └───────────┴─────────────┴─────────────────────────────────────┘
```

---

## 3. Hijerarhijski Stagevi

Osnovni Stage enum ima samo top-level faze. Za preciznije audio trigere, koristimo **hijerarhijske podtipove**.

### Koncept

```
STAGE                    SUB-TYPE                    AUDIO
───────────────────────────────────────────────────────────────
FEATURE_ENTER            .freespins                  freespins_fanfare.wav
FEATURE_ENTER            .pickem                     pickem_intro.wav
FEATURE_ENTER            .wheel                      wheel_whoosh.wav

BIGWIN_TIER              .win                        win_sting.wav
BIGWIN_TIER              .bigwin                     bigwin_fanfare.wav
BIGWIN_TIER              .megawin                    megawin_epic.wav
BIGWIN_TIER              .epicwin                    epicwin_orchestra.wav

REEL_STOP                .scatter                    scatter_land.wav
REEL_STOP                .wild                       wild_land.wav
REEL_STOP                .high_value                 highsym_land.wav
```

### Rust Implementacija

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct HierarchicalStage {
    pub base: Stage,
    pub sub_type: Option<String>,
    pub qualifiers: Vec<StageQualifier>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum StageQualifier {
    /// Reel index za ReelStop, Anticipation
    ReelIndex(u8),

    /// Symbol za ReelStop
    Symbol(String),

    /// Win multiplier za BigWin
    Multiplier(f64),

    /// Feature type za FeatureEnter
    FeatureType(FeatureType),

    /// Tier za BigWin, Jackpot
    Tier(String),

    /// Pozicija (red, kolona)
    Position(u8, u8),

    /// Custom tag
    Tag(String),
}

impl HierarchicalStage {
    /// Parsira string format "STAGE.subtype:qualifier=value"
    pub fn parse(input: &str) -> Result<Self, ParseError> {
        // Primeri:
        // "FEATURE_ENTER.freespins"
        // "REEL_STOP:reel=3:symbol=WILD"
        // "BIGWIN_TIER.mega:multiplier=75"

        let parts: Vec<&str> = input.split(':').collect();
        let stage_part = parts[0];

        // Parse base stage i subtype
        let (base_str, sub_type) = if let Some(dot_pos) = stage_part.find('.') {
            (&stage_part[..dot_pos], Some(stage_part[dot_pos+1..].to_string()))
        } else {
            (stage_part, None)
        };

        let base = Stage::from_str(base_str)?;

        // Parse qualifiers
        let mut qualifiers = Vec::new();
        for part in parts.iter().skip(1) {
            if let Some((key, value)) = part.split_once('=') {
                qualifiers.push(StageQualifier::parse(key, value)?);
            }
        }

        Ok(Self { base, sub_type, qualifiers })
    }

    /// Match pattern za audio triggering
    pub fn matches(&self, pattern: &StagePattern) -> bool {
        // Base stage mora da se poklapa
        if !pattern.matches_base(&self.base) {
            return false;
        }

        // Subtype (ako je specificiran u pattern-u)
        if let Some(ref pattern_sub) = pattern.sub_type {
            if self.sub_type.as_ref() != Some(pattern_sub) {
                return false;
            }
        }

        // Qualifiers (svi iz pattern-a moraju postojati)
        for req in &pattern.required_qualifiers {
            if !self.qualifiers.iter().any(|q| q.matches(req)) {
                return false;
            }
        }

        true
    }
}

/// Pattern za matching hijerarhijskih stageva
#[derive(Debug, Clone)]
pub struct StagePattern {
    pub base: Option<Stage>,           // None = any
    pub sub_type: Option<String>,      // None = any
    pub required_qualifiers: Vec<QualifierPattern>,
}

impl StagePattern {
    /// Parsira pattern string
    /// Primeri:
    /// - "REEL_STOP.*:symbol=WILD" — bilo koji reel stop sa WILD simbolom
    /// - "BIGWIN_TIER.mega" — samo mega win tier
    /// - "*:symbol=SCATTER" — bilo koji stage sa SCATTER simbolom
    pub fn parse(input: &str) -> Result<Self, ParseError> {
        // Implementacija slična HierarchicalStage::parse
        // sa podrškom za wildcard "*"
        todo!()
    }
}
```

### Audio Mapping sa Hijerarhijom

```yaml
# audio_config.yaml
triggers:
  - pattern: "REEL_STOP:symbol=WILD"
    sound: "wild_land"
    priority: high

  - pattern: "REEL_STOP:symbol=SCATTER"
    sound: "scatter_land"
    priority: critical  # Uvek se čuje

  - pattern: "REEL_STOP:reel=4"  # Poslednji reel
    sound: "final_reel_stop"
    priority: normal

  - pattern: "FEATURE_ENTER.freespins"
    sound: "freespins_intro"
    music_transition: "freespins_music"
    duck_rule: "feature_duck"

  - pattern: "BIGWIN_TIER.megawin"
    sound: "megawin_fanfare"
    music_transition: "bigwin_celebration"
    duck_rule: "bigwin_duck_heavy"

  - pattern: "BIGWIN_TIER.*:multiplier>=100"
    sound: "ultrawin_epic"
    override_tier_sound: true  # Zamenjuje default tier sound
```

---

## 4. Confidence Scoring

Adapteri mogu izraziti **nesigurnost** u interpretaciji. Ovo je ključno za Layer 2 i Layer 3 ingest.

### Koncept

```rust
#[derive(Debug, Clone)]
pub struct StageEventWithConfidence {
    pub event: StageEvent,
    pub confidence: f64,  // 0.0 - 1.0
    pub alternatives: Vec<(Stage, f64)>,  // Alternativne interpretacije
    pub reasoning: Option<String>,  // Debug info
}

impl StageEventWithConfidence {
    pub fn certain(event: StageEvent) -> Self {
        Self {
            event,
            confidence: 1.0,
            alternatives: vec![],
            reasoning: None,
        }
    }

    pub fn probable(event: StageEvent, confidence: f64, reasoning: &str) -> Self {
        Self {
            event,
            confidence,
            alternatives: vec![],
            reasoning: Some(reasoning.to_string()),
        }
    }

    pub fn ambiguous(
        primary: StageEvent,
        primary_confidence: f64,
        alternatives: Vec<(Stage, f64)>,
        reasoning: &str,
    ) -> Self {
        Self {
            event: primary,
            confidence: primary_confidence,
            alternatives,
            reasoning: Some(reasoning.to_string()),
        }
    }
}
```

### Primena u Adapterima

```rust
impl EngineAdapter for GenericSlotAdapter {
    fn parse_event(&self, event: &serde_json::Value) -> Result<StageEventWithConfidence, AdapterError> {
        let event_name = event["name"].as_str().unwrap_or("");

        // Layer 1: Direct mapping — visok confidence
        if let Some(stage) = self.config.event_mapping.get(event_name) {
            return Ok(StageEventWithConfidence::certain(StageEvent {
                stage: stage.clone(),
                timestamp_ms: event["time"].as_f64().unwrap_or(0.0),
                payload: self.extract_payload(event),
                source_event: Some(event_name.to_string()),
                tags: vec![],
            }));
        }

        // Layer 2: Heuristic matching — srednji confidence
        if event_name.to_lowercase().contains("win") {
            if event_name.contains("big") {
                return Ok(StageEventWithConfidence::probable(
                    StageEvent {
                        stage: Stage::BigWinTier { tier: BigWinTier::BigWin },
                        timestamp_ms: event["time"].as_f64().unwrap_or(0.0),
                        payload: self.extract_payload(event),
                        source_event: Some(event_name.to_string()),
                        tags: vec![],
                    },
                    0.75,
                    "Matched 'big' and 'win' keywords",
                ));
            }

            // Moglo bi biti WinPresent ili RollupStart
            return Ok(StageEventWithConfidence::ambiguous(
                StageEvent {
                    stage: Stage::WinPresent,
                    timestamp_ms: event["time"].as_f64().unwrap_or(0.0),
                    payload: self.extract_payload(event),
                    source_event: Some(event_name.to_string()),
                    tags: vec![],
                },
                0.6,
                vec![
                    (Stage::RollupStart, 0.3),
                    (Stage::WinLineShow { line_index: 0 }, 0.1),
                ],
                "Event contains 'win' but unclear type",
            ));
        }

        // Layer 3: Unknown event — nizak confidence
        Ok(StageEventWithConfidence::probable(
            StageEvent {
                stage: Stage::IdleLoop,  // Default fallback
                timestamp_ms: event["time"].as_f64().unwrap_or(0.0),
                payload: StagePayload::default(),
                source_event: Some(event_name.to_string()),
                tags: vec!["unknown".to_string()],
            },
            0.2,
            &format!("Unknown event '{}', defaulting to IdleLoop", event_name),
        ))
    }
}
```

### Confidence Thresholds

```rust
pub struct ConfidencePolicy {
    /// Minimum confidence za automatski audio trigger
    pub auto_trigger_threshold: f64,  // default: 0.8

    /// Confidence ispod ove vrednosti se loguje kao warning
    pub warning_threshold: f64,  // default: 0.5

    /// Ispod ovog se event ignorise
    pub ignore_threshold: f64,  // default: 0.2
}

impl AudioTriggerSystem {
    pub fn process_with_confidence(&mut self, event: &StageEventWithConfidence) {
        if event.confidence < self.policy.ignore_threshold {
            log::debug!("Ignoring low-confidence event: {:?}", event);
            return;
        }

        if event.confidence < self.policy.warning_threshold {
            log::warn!(
                "Low confidence stage: {:?} ({}%) - {}",
                event.event.stage,
                (event.confidence * 100.0) as u32,
                event.reasoning.as_deref().unwrap_or("no reason")
            );
        }

        if event.confidence >= self.policy.auto_trigger_threshold {
            // Automatski trigger
            self.process_stage(&event.event);
        } else {
            // Trigger sa smanjenim volumenom/prioritetom
            self.process_stage_attenuated(&event.event, event.confidence);
        }
    }
}
```

---

## 5. Kanonska Stage Taksonomija V2

### Core Stages

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Stage {
    // ═══ SPIN LIFECYCLE ═══
    SpinStart,
    ReelSpinning { reel_index: u8 },
    ReelStop { reel_index: u8 },
    EvaluateWins,
    SpinEnd,

    // ═══ ANTICIPATION ═══
    AnticipationOn { reel_index: u8 },
    AnticipationOff { reel_index: u8 },

    // ═══ WIN LIFECYCLE ═══
    WinPresent,
    WinLineShow { line_index: u8 },
    RollupStart,
    RollupTick,  // Za granularni rollup audio
    RollupEnd,
    BigWinTier { tier: BigWinTier },

    // ═══ FEATURE LIFECYCLE ═══
    FeatureEnter { feature_type: FeatureType },
    FeatureStep { step_index: u32 },
    FeatureExit,

    // ═══ CASCADE / TUMBLE ═══
    CascadeStart,
    CascadeStep { step_index: u32 },
    CascadeEnd,

    // ═══ BONUS / GAMBLE ═══
    BonusEnter,
    BonusChoice,
    BonusReveal,
    BonusExit,
    GambleStart,
    GambleChoice,
    GambleResult { won: bool },
    GambleEnd,

    // ═══ JACKPOT ═══
    JackpotTrigger { tier: JackpotTier },
    JackpotPresent,
    JackpotEnd,

    // ═══ UI / IDLE ═══
    IdleStart,
    IdleLoop,
    MenuOpen,
    MenuClose,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BigWinTier {
    Win,        // 10-15x bet
    BigWin,     // 15-25x bet
    MegaWin,    // 25-50x bet
    EpicWin,    // 50-100x bet
    UltraWin,   // 100x+ bet
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FeatureType {
    FreeSpins,
    BonusGame,
    PickBonus,
    WheelBonus,
    Respin,
    HoldAndSpin,
    ExpandingWilds,
    StickyWilds,
    Multiplier,
    Custom(u32),  // Za custom feature-e
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JackpotTier {
    Mini,
    Minor,
    Major,
    Grand,
    Custom(u32),
}
```

### StageEvent — Puni event sa metapodacima

```rust
#[derive(Debug, Clone)]
pub struct StageEvent {
    /// Kanonski stage
    pub stage: Stage,

    /// Timestamp (od početka spina, u ms)
    pub timestamp_ms: f64,

    /// Opcioni payload
    pub payload: StagePayload,

    /// Originalni event name (za debugging)
    pub source_event: Option<String>,

    /// Custom tags
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Default)]
pub struct StagePayload {
    /// Win amount (za WinPresent, RollupStart, BigWinTier)
    pub win_amount: Option<f64>,

    /// Bet amount (za normalizaciju win tiers)
    pub bet_amount: Option<f64>,

    /// Symbol info (za ReelStop)
    pub symbol_id: Option<u32>,
    pub symbol_name: Option<String>,

    /// Feature info
    pub feature_name: Option<String>,
    pub feature_spins_remaining: Option<u32>,
    pub feature_multiplier: Option<f64>,

    /// Line info (za WinLineShow)
    pub line_positions: Option<Vec<(u8, u8)>>,

    /// Arbitrary JSON (za custom data)
    pub custom: Option<serde_json::Value>,
}
```

### StageTrace — Kompletan tok jednog spina

```rust
#[derive(Debug, Clone)]
pub struct StageTrace {
    /// Unique spin ID
    pub spin_id: String,

    /// Svi eventi u hronološkom redu
    pub events: Vec<StageEvent>,

    /// Metadata
    pub game_id: String,
    pub session_id: Option<String>,
    pub recorded_at: chrono::DateTime<chrono::Utc>,

    /// Timing profile korišćen
    pub timing_profile: TimingProfile,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TimingProfile {
    Normal,
    Turbo,
    Mobile,
    Studio,  // Za preview sa custom timing-om
    Instant, // Zero delay (za testing)
}
```

---

## 6. Tri Sloja Ingesta

### Layer 1 — Direct Event Ingest

Ako engine ima event log sa imenima:

```json
{
  "events": [
    { "name": "spin_start", "time": 0 },
    { "name": "reel_stop_0", "time": 500, "symbol": "WILD" },
    { "name": "reel_stop_1", "time": 600, "symbol": "CHERRY" },
    { "name": "show_win", "time": 1200, "amount": 50.0 }
  ]
}
```

Adapter:
1. Čita listu događaja
2. Mapira imena na STAGES (via config)
3. Izvlači payload
4. Generiše StageTrace

**Pokriva: 70% industrije**

### Layer 2 — Snapshot Diff Derivation

Ako engine ima samo stanje pre/posle:

```json
{
  "before": {
    "reels": [null, null, null, null, null],
    "total_win": 0,
    "feature_active": false
  },
  "after": {
    "reels": ["WILD", "CHERRY", "CHERRY", "BELL", "7"],
    "total_win": 150.0,
    "feature_active": true
  }
}
```

Sistem poredi:
- `reels` promena → `ReelStop` za svaki reel
- `total_win` 0→150 → `WinPresent`
- `feature_active` false→true → `FeatureEnter`

**Pokriva: Zatvoreni engine-i, minimalni API-ji**

### Layer 3 — Rule-Based Reconstruction

Ako su eventi generički ("STATE_UPDATED", "DATA_CHANGED"):

```json
{
  "event": "STATE_UPDATED",
  "data": { "reels": [...], "win": 50 }
}
```

Pravila zaključuju semantiku:
- Ako `reels` ima vrednosti i prethodno nije → `ReelStop`
- Ako `win > 0` i prethodno `win == 0` → `WinPresent`
- Kombinacija heuristika + domain knowledge

**Pokriva: Black-box sistemi**

---

## 7. Adapter Sistem

### Adapter Trait

```rust
pub trait EngineAdapter: Send + Sync {
    /// Adapter identifier
    fn adapter_id(&self) -> &str;

    /// Company name
    fn company_name(&self) -> &str;

    /// Supported ingest layers
    fn supported_layers(&self) -> Vec<IngestLayer>;

    /// Parse raw JSON into StageTrace
    fn parse_json(&self, json: &serde_json::Value) -> Result<StageTrace, AdapterError>;

    /// Parse event stream (for live mode)
    fn parse_event(&self, event: &serde_json::Value) -> Result<Option<StageEvent>, AdapterError>;

    /// Validate adapter config
    fn validate_config(&self, config: &AdapterConfig) -> Result<(), AdapterError>;
}

pub enum IngestLayer {
    DirectEvent,
    SnapshotDiff,
    RuleBased,
}
```

---

## 8. YAML Adapter Config (Preporučeni Format)

YAML format je čitljiviji od TOML-a za kompleksne mapping konfiguracije.

### Puna Specifikacija

```yaml
# adapter_config.yaml — IGT AVP Example

adapter:
  id: igt-avp
  company: IGT
  version: "2.0"
  description: "IGT AVP platform adapter"
  layers:
    - direct_event
    - snapshot_diff

# ═══════════════════════════════════════════════════════════════════
# EVENT MAPPING — Direct 1:1 mapiranje
# ═══════════════════════════════════════════════════════════════════
event_mapping:
  # Spin lifecycle
  cmd_spin_start: SpinStart
  cmd_spin_complete: SpinEnd

  # Reel events (sa parametrima)
  reel_spinning_0: "ReelSpinning { reel_index: 0 }"
  reel_spinning_1: "ReelSpinning { reel_index: 1 }"
  reel_spinning_2: "ReelSpinning { reel_index: 2 }"
  reel_spinning_3: "ReelSpinning { reel_index: 3 }"
  reel_spinning_4: "ReelSpinning { reel_index: 4 }"

  reel_landed_0: "ReelStop { reel_index: 0 }"
  reel_landed_1: "ReelStop { reel_index: 1 }"
  reel_landed_2: "ReelStop { reel_index: 2 }"
  reel_landed_3: "ReelStop { reel_index: 3 }"
  reel_landed_4: "ReelStop { reel_index: 4 }"

  # Anticipation (sa variable extraction)
  anticipation_start: "AnticipationOn { reel_index: $reel }"
  anticipation_end: "AnticipationOff { reel_index: $reel }"

  # Win presentation
  show_win_celebration: WinPresent
  show_win_line: "WinLineShow { line_index: $line }"
  rollup_start: RollupStart
  rollup_tick: RollupTick
  rollup_end: RollupEnd

  # Big win tiers
  big_win_standard: "BigWinTier { tier: Win }"
  big_win_big: "BigWinTier { tier: BigWin }"
  big_win_mega: "BigWinTier { tier: MegaWin }"
  big_win_epic: "BigWinTier { tier: EpicWin }"
  big_win_ultra: "BigWinTier { tier: UltraWin }"

  # Features
  enter_free_spins: "FeatureEnter { feature_type: FreeSpins }"
  free_spin_step: "FeatureStep { step_index: $step }"
  exit_free_spins: FeatureExit

  enter_bonus_game: BonusEnter
  bonus_choice_made: BonusChoice
  bonus_reveal: BonusReveal
  exit_bonus_game: BonusExit

  # Cascade/Tumble
  cascade_start: CascadeStart
  cascade_step: "CascadeStep { step_index: $step }"
  cascade_end: CascadeEnd

  # Jackpot
  jackpot_trigger_mini: "JackpotTrigger { tier: Mini }"
  jackpot_trigger_minor: "JackpotTrigger { tier: Minor }"
  jackpot_trigger_major: "JackpotTrigger { tier: Major }"
  jackpot_trigger_grand: "JackpotTrigger { tier: Grand }"
  jackpot_presentation: JackpotPresent
  jackpot_complete: JackpotEnd

  # Gamble
  gamble_start: GambleStart
  gamble_choice: GambleChoice
  gamble_win: "GambleResult { won: true }"
  gamble_lose: "GambleResult { won: false }"
  gamble_end: GambleEnd

# ═══════════════════════════════════════════════════════════════════
# PAYLOAD EXTRACTION — JSONPath izrazi za izvlačenje podataka
# ═══════════════════════════════════════════════════════════════════
payload_extraction:
  # Core amounts
  win_amount: "$.result.total_win"
  bet_amount: "$.bet.total_bet"

  # Symbol info
  symbol_id: "$.reel_data.symbol_id"
  symbol_name: "$.reel_data.symbol_name"

  # Feature info
  feature_name: "$.feature.name"
  feature_spins_remaining: "$.feature.spins_remaining"
  feature_multiplier: "$.feature.current_multiplier"

  # Line info
  line_index: "$.win_line.index"
  line_positions: "$.win_line.positions"

  # Reel index (za parametrizovane evente)
  reel_index: "$.reel.index"
  step_index: "$.step"

# ═══════════════════════════════════════════════════════════════════
# SNAPSHOT DIFF — Za Layer 2 ingest
# ═══════════════════════════════════════════════════════════════════
snapshot_diff:
  paths:
    reels: "$.game_state.reels"
    total_win: "$.game_state.win"
    feature_active: "$.game_state.in_feature"
    feature_type: "$.game_state.feature_type"
    multiplier: "$.game_state.multiplier"
    jackpot_active: "$.game_state.jackpot_pending"

  # Pravila za derivaciju stageva iz diff-a
  rules:
    - condition: "reels changed from null"
      stage: ReelStop
      extract_reel_index: true

    - condition: "total_win changed from 0"
      stage: WinPresent

    - condition: "feature_active changed to true"
      stage: FeatureEnter
      use_field: feature_type

    - condition: "feature_active changed to false"
      stage: FeatureExit

    - condition: "multiplier increased"
      stage: "FeatureStep { step_index: $step }"

# ═══════════════════════════════════════════════════════════════════
# BIGWIN THRESHOLDS — Automatska detekcija tier-a
# ═══════════════════════════════════════════════════════════════════
bigwin_thresholds:
  win: 10.0       # 10x bet → Win
  big_win: 15.0   # 15x bet → BigWin
  mega_win: 25.0  # 25x bet → MegaWin
  epic_win: 50.0  # 50x bet → EpicWin
  ultra_win: 100.0 # 100x bet → UltraWin

# ═══════════════════════════════════════════════════════════════════
# TIMING OVERRIDES — Custom timing za ovaj engine
# ═══════════════════════════════════════════════════════════════════
timing:
  reel_stop_interval_ms: 120  # Brži od default-a
  anticipation_hold_ms: 2000
  win_line_interval_ms: 250
  rollup_credits_per_second: 150

# ═══════════════════════════════════════════════════════════════════
# VALIDATION — FSM constraints
# ═══════════════════════════════════════════════════════════════════
validation:
  strict_fsm: true
  allow_unknown_events: false
  log_unmapped_events: true
  min_confidence_threshold: 0.5

# ═══════════════════════════════════════════════════════════════════
# HEURISTICS — Za Layer 3 fallback
# ═══════════════════════════════════════════════════════════════════
heuristics:
  patterns:
    - keywords: ["spin", "start", "begin"]
      stage: SpinStart
      confidence: 0.9

    - keywords: ["reel", "stop", "land"]
      stage: ReelStop
      confidence: 0.85

    - keywords: ["win", "celebration", "show"]
      stage: WinPresent
      confidence: 0.8

    - keywords: ["free", "spin"]
      stage: "FeatureEnter { feature_type: FreeSpins }"
      confidence: 0.85

    - keywords: ["bonus", "enter", "trigger"]
      stage: BonusEnter
      confidence: 0.8
```

### TOML Alternativa (Originalni Format)

```toml
[adapter]
id = "igt-avp"
company = "IGT"
version = "1.0"
layers = ["direct_event", "snapshot_diff"]

[event_mapping]
"cmd_spin_start" = "SpinStart"
"reel_landed_0" = "ReelStop { reel_index: 0 }"
"reel_landed_1" = "ReelStop { reel_index: 1 }"
"reel_landed_2" = "ReelStop { reel_index: 2 }"
"reel_landed_3" = "ReelStop { reel_index: 3 }"
"reel_landed_4" = "ReelStop { reel_index: 4 }"
"anticipation_start" = "AnticipationOn { reel_index: $reel }"
"anticipation_end" = "AnticipationOff { reel_index: $reel }"
"show_win_celebration" = "WinPresent"
"rollup_start" = "RollupStart"
"rollup_end" = "RollupEnd"
"big_win_tier" = "BigWinTier { tier: $tier }"
"enter_free_spins" = "FeatureEnter { feature_type: FreeSpins }"
"free_spin_step" = "FeatureStep { step_index: $step }"
"exit_free_spins" = "FeatureExit"
"spin_complete" = "SpinEnd"

[payload_extraction]
win_amount = "$.result.total_win"
bet_amount = "$.bet.total_bet"
symbol_id = "$.reel_data.symbol_id"
feature_spins = "$.feature.spins_remaining"

[snapshot_paths]
reels = "$.game_state.reels"
total_win = "$.game_state.win"
feature_active = "$.game_state.in_feature"

[bigwin_thresholds]
win = 10.0       # 10x bet
big_win = 15.0   # 15x bet
mega_win = 25.0  # 25x bet
epic_win = 50.0  # 50x bet
ultra_win = 100.0 # 100x bet
```

### Adapter Registry

```rust
pub struct AdapterRegistry {
    adapters: HashMap<String, Arc<dyn EngineAdapter>>,
}

impl AdapterRegistry {
    pub fn register(&mut self, adapter: Arc<dyn EngineAdapter>) {
        self.adapters.insert(adapter.adapter_id().to_string(), adapter);
    }

    pub fn get(&self, adapter_id: &str) -> Option<Arc<dyn EngineAdapter>> {
        self.adapters.get(adapter_id).cloned()
    }

    pub fn list_adapters(&self) -> Vec<&str> {
        self.adapters.keys().map(|s| s.as_str()).collect()
    }

    /// Auto-detect adapter from JSON structure
    pub fn detect_adapter(&self, json: &serde_json::Value) -> Option<Arc<dyn EngineAdapter>> {
        for adapter in self.adapters.values() {
            if adapter.validate_config(&AdapterConfig::default()).is_ok() {
                // Try to parse, if successful this is likely the right adapter
                if adapter.parse_json(json).is_ok() {
                    return Some(adapter.clone());
                }
            }
        }
        None
    }
}
```

---

## 10. Unity SDK

Za Unity engine, FluxForge pruža native C# SDK koji se integriše direktno u igru.

### Instalacija

```bash
# Via Unity Package Manager
# Add to Packages/manifest.json:
{
  "dependencies": {
    "com.fluxforge.stage-ingest": "https://github.com/fluxforge/unity-sdk.git#v2.0.0"
  }
}
```

### Core API

```csharp
// FluxForge.StageIngest namespace

using FluxForge.StageIngest;

public class SlotGameController : MonoBehaviour
{
    private FluxForgeClient _fluxForge;

    void Awake()
    {
        // Inicijalizacija — konektuje se na FluxForge Studio
        _fluxForge = new FluxForgeClient(new FluxForgeConfig
        {
            StudioHost = "localhost",
            StudioPort = 9876,
            GameId = "my-slot-game",
            AdapterId = "custom-unity",  // Ili "unity-generic" za auto-detection
            EnableLivePreview = true,
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    // SPIN LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════

    public void OnSpinButtonPressed()
    {
        _fluxForge.EmitStage(Stage.SpinStart);
    }

    public void OnReelStartSpinning(int reelIndex)
    {
        _fluxForge.EmitStage(Stage.ReelSpinning, new StagePayload
        {
            ReelIndex = reelIndex
        });
    }

    public void OnReelStopped(int reelIndex, string symbolName)
    {
        _fluxForge.EmitStage(Stage.ReelStop, new StagePayload
        {
            ReelIndex = reelIndex,
            SymbolName = symbolName
        });
    }

    public void OnAllReelsStopped()
    {
        _fluxForge.EmitStage(Stage.EvaluateWins);
    }

    // ═══════════════════════════════════════════════════════════════════
    // ANTICIPATION
    // ═══════════════════════════════════════════════════════════════════

    public void OnAnticipationStart(int reelIndex)
    {
        _fluxForge.EmitStage(Stage.AnticipationOn, new StagePayload
        {
            ReelIndex = reelIndex
        });
    }

    public void OnAnticipationEnd(int reelIndex)
    {
        _fluxForge.EmitStage(Stage.AnticipationOff, new StagePayload
        {
            ReelIndex = reelIndex
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    // WIN PRESENTATION
    // ═══════════════════════════════════════════════════════════════════

    public void OnWinCalculated(decimal winAmount, decimal betAmount)
    {
        _fluxForge.EmitStage(Stage.WinPresent, new StagePayload
        {
            WinAmount = winAmount,
            BetAmount = betAmount
        });

        // Auto-detect big win tier
        var multiplier = winAmount / betAmount;
        if (multiplier >= 10)
        {
            var tier = _fluxForge.CalculateBigWinTier(multiplier);
            _fluxForge.EmitStage(Stage.BigWinTier, new StagePayload
            {
                Tier = tier,
                WinAmount = winAmount,
                Multiplier = (float)multiplier
            });
        }
    }

    public void OnWinLineShow(int lineIndex, List<Vector2Int> positions)
    {
        _fluxForge.EmitStage(Stage.WinLineShow, new StagePayload
        {
            LineIndex = lineIndex,
            LinePositions = positions
        });
    }

    public void OnRollupStart()
    {
        _fluxForge.EmitStage(Stage.RollupStart);
    }

    public void OnRollupTick(decimal currentValue)
    {
        _fluxForge.EmitStage(Stage.RollupTick, new StagePayload
        {
            CurrentRollupValue = currentValue
        });
    }

    public void OnRollupEnd()
    {
        _fluxForge.EmitStage(Stage.RollupEnd);
    }

    // ═══════════════════════════════════════════════════════════════════
    // FEATURES
    // ═══════════════════════════════════════════════════════════════════

    public void OnFreeSpinsTriggered(int totalSpins)
    {
        _fluxForge.EmitStage(Stage.FeatureEnter, new StagePayload
        {
            FeatureType = FeatureType.FreeSpins,
            FeatureName = "Free Spins",
            FeatureSpinsTotal = totalSpins
        });
    }

    public void OnFreeSpinStep(int stepIndex, int remaining)
    {
        _fluxForge.EmitStage(Stage.FeatureStep, new StagePayload
        {
            StepIndex = stepIndex,
            FeatureSpinsRemaining = remaining
        });
    }

    public void OnFreeSpinsComplete()
    {
        _fluxForge.EmitStage(Stage.FeatureExit);
    }

    public void OnBonusGameTriggered(string bonusType)
    {
        _fluxForge.EmitStage(Stage.BonusEnter, new StagePayload
        {
            FeatureName = bonusType
        });
    }

    // ═══════════════════════════════════════════════════════════════════
    // SPIN END
    // ═══════════════════════════════════════════════════════════════════

    public void OnSpinComplete()
    {
        _fluxForge.EmitStage(Stage.SpinEnd);
    }
}
```

### Attribute-Based Auto-Emit

Za jednostavniji workflow, koristi atribute:

```csharp
using FluxForge.StageIngest.Attributes;

public class ReelController : MonoBehaviour
{
    [EmitStage(Stage.ReelSpinning, PayloadField = "reelIndex")]
    public void StartSpinning(int reelIndex)
    {
        // Automatski emituje ReelSpinning kada se metoda pozove
        _reelAnimator.Play("spin");
    }

    [EmitStage(Stage.ReelStop)]
    public void StopReel()
    {
        _reelAnimator.Play("stop");
    }
}
```

### ScriptableObject Config

```csharp
[CreateAssetMenu(fileName = "FluxForgeConfig", menuName = "FluxForge/Config")]
public class FluxForgeConfigAsset : ScriptableObject
{
    public string studioHost = "localhost";
    public int studioPort = 9876;
    public string gameId;
    public string adapterId = "unity-generic";

    [Header("Big Win Thresholds")]
    public float winThreshold = 10f;
    public float bigWinThreshold = 15f;
    public float megaWinThreshold = 25f;
    public float epicWinThreshold = 50f;
    public float ultraWinThreshold = 100f;

    [Header("Debug")]
    public bool logAllStages = false;
    public bool enableLivePreview = true;
}
```

---

## 11. Unreal SDK

Za Unreal Engine, FluxForge pruža C++ plugin sa Blueprint support-om.

### Instalacija

```
1. Download FluxForgeStageIngest plugin
2. Copy to YourProject/Plugins/
3. Enable in Edit → Plugins → FluxForge Stage Ingest
4. Restart Editor
```

### C++ API

```cpp
// FluxForgeStageIngest/Public/FluxForgeClient.h

#pragma once

#include "CoreMinimal.h"
#include "FluxForgeTypes.h"
#include "FluxForgeClient.generated.h"

UCLASS(BlueprintType)
class FLUXFORGESTAGEINGEST_API UFluxForgeClient : public UObject
{
    GENERATED_BODY()

public:
    // Initialize connection to FluxForge Studio
    UFUNCTION(BlueprintCallable, Category = "FluxForge")
    void Initialize(const FFluxForgeConfig& Config);

    // Emit a stage event
    UFUNCTION(BlueprintCallable, Category = "FluxForge")
    void EmitStage(EFluxForgeStage Stage, const FStagePayload& Payload);

    // Convenience methods
    UFUNCTION(BlueprintCallable, Category = "FluxForge|Spin")
    void EmitSpinStart();

    UFUNCTION(BlueprintCallable, Category = "FluxForge|Spin")
    void EmitReelSpinning(int32 ReelIndex);

    UFUNCTION(BlueprintCallable, Category = "FluxForge|Spin")
    void EmitReelStop(int32 ReelIndex, const FString& SymbolName);

    UFUNCTION(BlueprintCallable, Category = "FluxForge|Spin")
    void EmitSpinEnd();

    UFUNCTION(BlueprintCallable, Category = "FluxForge|Win")
    void EmitWinPresent(float WinAmount, float BetAmount);

    UFUNCTION(BlueprintCallable, Category = "FluxForge|Win")
    void EmitBigWinTier(EBigWinTier Tier, float Multiplier);

    UFUNCTION(BlueprintCallable, Category = "FluxForge|Feature")
    void EmitFeatureEnter(EFeatureType FeatureType, const FString& FeatureName);

    UFUNCTION(BlueprintCallable, Category = "FluxForge|Feature")
    void EmitFeatureStep(int32 StepIndex);

    UFUNCTION(BlueprintCallable, Category = "FluxForge|Feature")
    void EmitFeatureExit();

private:
    TSharedPtr<FFluxForgeConnection> Connection;
    FFluxForgeConfig CurrentConfig;
};
```

### Blueprint Integration

```cpp
// Example: ReelActor.cpp

#include "FluxForgeClient.h"

void AReelActor::StartSpinning()
{
    // Get FluxForge client from game instance
    UFluxForgeClient* FluxForge = GetGameInstance()->GetSubsystem<UFluxForgeSubsystem>()->GetClient();

    FluxForge->EmitReelSpinning(ReelIndex);

    // Start spin animation
    SpinTimeline->PlayFromStart();
}

void AReelActor::OnReelStopped()
{
    UFluxForgeClient* FluxForge = GetGameInstance()->GetSubsystem<UFluxForgeSubsystem>()->GetClient();

    FString SymbolName = GetCurrentSymbol()->GetName();
    FluxForge->EmitReelStop(ReelIndex, SymbolName);
}
```

### Data Asset Config

```cpp
// FluxForgeConfigDataAsset.h

UCLASS(BlueprintType)
class UFluxForgeConfigDataAsset : public UDataAsset
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Connection")
    FString StudioHost = TEXT("localhost");

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Connection")
    int32 StudioPort = 9876;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Game")
    FString GameId;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Game")
    FString AdapterId = TEXT("unreal-generic");

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Big Win Thresholds")
    float WinThreshold = 10.0f;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Big Win Thresholds")
    float BigWinThreshold = 15.0f;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Big Win Thresholds")
    float MegaWinThreshold = 25.0f;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Big Win Thresholds")
    float EpicWinThreshold = 50.0f;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Big Win Thresholds")
    float UltraWinThreshold = 100.0f;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Debug")
    bool bLogAllStages = false;

    UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Debug")
    bool bEnableLivePreview = true;
};
```

### Blueprint Example (Visual Scripting)

```
[Event BeginPlay]
    │
    ▼
[Get Game Instance] → [Get Subsystem: FluxForgeSubsystem] → [Get Client] → [Store in Variable: FluxForge]

[Event: On Spin Button Clicked]
    │
    ▼
[FluxForge] → [Emit Spin Start]
    │
    ▼
[For Each Reel (0-4)]
    │
    ▼
[FluxForge] → [Emit Reel Spinning] ← [Reel Index]

[Event: On Reel Stopped (ReelIndex, Symbol)]
    │
    ▼
[FluxForge] → [Emit Reel Stop] ← [Reel Index, Symbol Name]

[Event: On Win Calculated (WinAmount, BetAmount)]
    │
    ▼
[FluxForge] → [Emit Win Present] ← [Win Amount, Bet Amount]
    │
    ▼
[Branch: WinAmount / BetAmount >= 10]
    │
    ├─► [True] → [Calculate Big Win Tier] → [Emit Big Win Tier]
    │
    └─► [False] → (continue)
```

---

## 12. Timing Resolver

STAGES nemaju vreme. Timing Resolver dodaje vremensku dimenziju.

```rust
pub struct TimingResolver {
    profiles: HashMap<TimingProfile, TimingConfig>,
}

#[derive(Debug, Clone)]
pub struct TimingConfig {
    /// Base delays per stage (ms)
    pub stage_delays: HashMap<Stage, f64>,

    /// Reel stop timing
    pub reel_stop_interval: f64,  // Time between each reel stop
    pub reel_stop_base: f64,      // Time before first reel stops

    /// Win presentation
    pub win_line_interval: f64,   // Time between win line highlights
    pub rollup_speed: f64,        // Credits per second

    /// Big win timing
    pub bigwin_tier_duration: HashMap<BigWinTier, f64>,

    /// Feature timing
    pub feature_enter_delay: f64,
    pub feature_step_interval: f64,
}

impl TimingResolver {
    pub fn resolve(&self, trace: &StageTrace, profile: TimingProfile) -> TimedStageTrace {
        let config = self.profiles.get(&profile).unwrap_or(&self.default_config());

        let mut timed_events = Vec::new();
        let mut current_time = 0.0;

        for event in &trace.events {
            let delay = config.get_delay(&event.stage);
            current_time += delay;

            timed_events.push(TimedStageEvent {
                event: event.clone(),
                absolute_time_ms: current_time,
            });
        }

        TimedStageTrace {
            spin_id: trace.spin_id.clone(),
            events: timed_events,
            total_duration_ms: current_time,
            profile,
        }
    }
}

// Primeri profila
impl Default for TimingConfig {
    fn default() -> Self {
        Self {
            stage_delays: hashmap! {
                Stage::SpinStart => 0.0,
                Stage::ReelStop { reel_index: 0 } => 500.0,
                Stage::WinPresent => 200.0,
                Stage::RollupStart => 100.0,
                Stage::FeatureEnter { .. } => 500.0,
            },
            reel_stop_interval: 150.0,
            reel_stop_base: 800.0,
            win_line_interval: 300.0,
            rollup_speed: 100.0,
            bigwin_tier_duration: hashmap! {
                BigWinTier::Win => 3000.0,
                BigWinTier::BigWin => 5000.0,
                BigWinTier::MegaWin => 8000.0,
                BigWinTier::EpicWin => 12000.0,
                BigWinTier::UltraWin => 15000.0,
            },
            feature_enter_delay: 1000.0,
            feature_step_interval: 500.0,
        }
    }
}
```

---

## 13. Adapter Wizard — Automatska Detekcija

### Algoritam

```rust
pub struct AdapterWizard {
    heuristics: Vec<Box<dyn EventHeuristic>>,
}

impl AdapterWizard {
    pub fn analyze_samples(&self, samples: Vec<serde_json::Value>) -> WizardResult {
        // 1. Extract all unique event names
        let event_names = self.extract_event_names(&samples);

        // 2. Apply heuristics to each event name
        let mut mappings = Vec::new();
        for name in event_names {
            let mut best_match = None;
            let mut best_confidence = 0.0;

            for heuristic in &self.heuristics {
                if let Some((stage, confidence)) = heuristic.match_event(&name) {
                    if confidence > best_confidence {
                        best_confidence = confidence;
                        best_match = Some((stage, confidence));
                    }
                }
            }

            mappings.push(EventMapping {
                source_name: name,
                suggested_stage: best_match.map(|(s, _)| s),
                confidence: best_confidence,
            });
        }

        // 3. Validate coverage
        let coverage = self.validate_coverage(&mappings);

        WizardResult {
            mappings,
            coverage,
            warnings: self.generate_warnings(&mappings),
        }
    }
}

// Heuristike
pub trait EventHeuristic {
    fn match_event(&self, event_name: &str) -> Option<(Stage, f64)>;
}

// Primer: Keyword-based heuristic
pub struct KeywordHeuristic {
    patterns: Vec<(Vec<&'static str>, Stage, f64)>,
}

impl EventHeuristic for KeywordHeuristic {
    fn match_event(&self, event_name: &str) -> Option<(Stage, f64)> {
        let lower = event_name.to_lowercase();

        for (keywords, stage, base_confidence) in &self.patterns {
            let matches = keywords.iter().filter(|k| lower.contains(*k)).count();
            if matches > 0 {
                let confidence = base_confidence * (matches as f64 / keywords.len() as f64);
                return Some((*stage, confidence));
            }
        }
        None
    }
}

// Default patterns
impl Default for KeywordHeuristic {
    fn default() -> Self {
        Self {
            patterns: vec![
                (vec!["spin", "start", "begin"], Stage::SpinStart, 0.95),
                (vec!["reel", "stop", "land"], Stage::ReelStop { reel_index: 0 }, 0.90),
                (vec!["reel", "spin"], Stage::ReelSpinning { reel_index: 0 }, 0.85),
                (vec!["anticip"], Stage::AnticipationOn { reel_index: 0 }, 0.92),
                (vec!["win", "show", "present", "display"], Stage::WinPresent, 0.88),
                (vec!["rollup", "count"], Stage::RollupStart, 0.90),
                (vec!["big", "win"], Stage::BigWinTier { tier: BigWinTier::BigWin }, 0.85),
                (vec!["mega", "win"], Stage::BigWinTier { tier: BigWinTier::MegaWin }, 0.88),
                (vec!["epic", "win"], Stage::BigWinTier { tier: BigWinTier::EpicWin }, 0.88),
                (vec!["free", "spin", "enter", "trigger"], Stage::FeatureEnter { feature_type: FeatureType::FreeSpins }, 0.85),
                (vec!["feature", "enter", "start"], Stage::FeatureEnter { feature_type: FeatureType::Custom(0) }, 0.80),
                (vec!["feature", "exit", "end", "complete"], Stage::FeatureExit, 0.85),
                (vec!["bonus", "enter", "start"], Stage::BonusEnter, 0.85),
                (vec!["cascade", "tumble", "avalanche"], Stage::CascadeStep { step_index: 0 }, 0.90),
                (vec!["spin", "end", "complete", "finish"], Stage::SpinEnd, 0.92),
                (vec!["jackpot", "trigger"], Stage::JackpotTrigger { tier: JackpotTier::Major }, 0.90),
            ],
        }
    }
}
```

---

## 14. Audio Engine Integracija

Audio engine prima **SAMO StageEvent**, nikada raw engine events.

```rust
// U rf-engine/src/audio_trigger.rs

pub struct AudioTriggerSystem {
    stage_rx: Consumer<StageEvent>,
    sound_bank: SoundBank,
    ducking_matrix: DuckingMatrix,
    music_system: MusicSystem,
}

impl AudioTriggerSystem {
    pub fn process_stage(&mut self, event: &StageEvent) {
        match event.stage {
            Stage::SpinStart => {
                self.sound_bank.play("spin_start");
                self.music_system.transition_to_segment("gameplay");
            }

            Stage::ReelStop { reel_index } => {
                self.sound_bank.play(&format!("reel_stop_{}", reel_index));
            }

            Stage::AnticipationOn { reel_index } => {
                self.sound_bank.play("anticipation_start");
                self.ducking_matrix.activate_rule("anticipation_duck");
                self.music_system.crossfade_to("tension_loop", 500.0);
            }

            Stage::AnticipationOff { .. } => {
                self.ducking_matrix.deactivate_rule("anticipation_duck");
                self.music_system.crossfade_to("gameplay", 300.0);
            }

            Stage::WinPresent => {
                if let Some(amount) = event.payload.win_amount {
                    // Dynamic win sound based on amount
                    let intensity = self.calculate_win_intensity(amount, event.payload.bet_amount);
                    self.sound_bank.play_with_params("win_present", &[
                        ("intensity", intensity),
                    ]);
                }
            }

            Stage::RollupStart => {
                self.sound_bank.play_loop("rollup_loop");
            }

            Stage::RollupEnd => {
                self.sound_bank.stop("rollup_loop");
                self.sound_bank.play("rollup_end");
            }

            Stage::BigWinTier { tier } => {
                self.music_system.play_stinger(match tier {
                    BigWinTier::Win => "win_stinger",
                    BigWinTier::BigWin => "bigwin_stinger",
                    BigWinTier::MegaWin => "megawin_stinger",
                    BigWinTier::EpicWin => "epicwin_stinger",
                    BigWinTier::UltraWin => "ultrawin_stinger",
                });
                self.ducking_matrix.activate_rule("bigwin_duck");
            }

            Stage::FeatureEnter { feature_type } => {
                self.music_system.transition_to_segment("feature");
                self.sound_bank.play("feature_enter");
                self.ducking_matrix.activate_rule("feature_duck");
            }

            Stage::FeatureStep { step_index } => {
                self.sound_bank.play(&format!("feature_step_{}", step_index % 4));
            }

            Stage::FeatureExit => {
                self.music_system.transition_to_segment("gameplay");
                self.ducking_matrix.deactivate_rule("feature_duck");
                self.sound_bank.play("feature_exit");
            }

            Stage::SpinEnd => {
                // Reset all transient states
                self.ducking_matrix.deactivate_all_transient();
            }

            _ => {}
        }
    }
}
```

---

## 15. Crate Struktura

```
crates/
├── rf-stage/                 # Stage definitions
│   ├── src/
│   │   ├── lib.rs
│   │   ├── stage.rs          # Stage enum
│   │   ├── event.rs          # StageEvent, StagePayload
│   │   ├── trace.rs          # StageTrace
│   │   ├── timing.rs         # TimingResolver, profiles
│   │   └── taxonomy.rs       # BigWinTier, FeatureType, etc.
│   └── Cargo.toml
│
├── rf-ingest/                # Universal Ingest System
│   ├── src/
│   │   ├── lib.rs
│   │   ├── adapter.rs        # EngineAdapter trait
│   │   ├── registry.rs       # AdapterRegistry
│   │   ├── config.rs         # AdapterConfig (TOML)
│   │   ├── layer_event.rs    # Layer 1: Direct event
│   │   ├── layer_snapshot.rs # Layer 2: Snapshot diff
│   │   ├── layer_rules.rs    # Layer 3: Rule-based
│   │   └── wizard/
│   │       ├── mod.rs
│   │       ├── analyzer.rs   # Sample analyzer
│   │       ├── heuristics.rs # Event heuristics
│   │       └── generator.rs  # Config generator
│   └── Cargo.toml
│
└── adapters/                 # Per-company adapters
    ├── rf-adapter-igt/
    ├── rf-adapter-aristocrat/
    ├── rf-adapter-novomatic/
    ├── rf-adapter-scientific-games/
    └── rf-adapter-generic/   # Fallback adapter
```

---

## 17. Real-Time Constraints (Lead DSP Engineer)

### Audio Thread Safety

Sve Stage event processing mora poštovati **ZERO ALLOCATION** pravilo u audio thread-u.

```rust
// ❌ ZABRANJENO u audio callback-u
fn process_stage_WRONG(&mut self, event: StageEvent) {
    // String alokacija — BLOKIRAJUĆE
    let sound_name = format!("reel_stop_{}", event.reel_index);

    // Vec push — POTENCIJALNO BLOKIRAJUĆE
    self.active_sounds.push(sound);

    // HashMap lookup sa String key — HEAP ALOKACIJA
    self.sounds.get(&event.stage.to_string());
}

// ✅ ISPRAVNO — Zero-alloc audio thread
fn process_stage_CORRECT(&mut self, event: &StageEvent) {
    // Pre-computed lookup table sa fixed indices
    let sound_idx = self.stage_to_sound_idx[event.stage as usize];

    // Fixed-size ring buffer, pre-alocirano
    self.sound_queue.try_push(sound_idx);

    // Atomic state za UI feedback
    self.last_stage.store(event.stage as u8, Ordering::Release);
}
```

### Lock-Free Stage Queue

```rust
use rtrb::{Consumer, Producer};

/// Stage events od UI/Network thread-a ka Audio thread-u
pub struct StageEventQueue {
    /// Producer (UI/Network thread)
    tx: Producer<StageEventCompact>,

    /// Consumer (Audio thread)
    rx: Consumer<StageEventCompact>,
}

/// Kompaktna reprezentacija — STACK ONLY
#[derive(Clone, Copy)]
#[repr(C, align(64))]  // Cache line aligned
pub struct StageEventCompact {
    pub stage_id: u16,       // Stage enum as u16
    pub timestamp_ms: f32,   // Relative timestamp
    pub reel_index: u8,      // For reel events
    pub tier: u8,            // For bigwin/jackpot
    pub win_amount: f32,     // Normalized 0.0-1.0
    pub confidence: f32,     // 0.0-1.0
    pub _padding: [u8; 2],   // Align to 24 bytes
}

impl StageEventQueue {
    pub fn new() -> Self {
        // Pre-allocate 256 events — covers worst case spin
        let (tx, rx) = rtrb::RingBuffer::new(256);
        Self { tx, rx }
    }

    /// UI thread: push event (non-blocking)
    #[inline]
    pub fn push(&mut self, event: StageEventCompact) -> bool {
        self.tx.push(event).is_ok()
    }

    /// Audio thread: drain all pending (non-blocking)
    #[inline]
    pub fn drain(&mut self, buffer: &mut [StageEventCompact; 32]) -> usize {
        let mut count = 0;
        while count < 32 {
            match self.rx.pop() {
                Ok(event) => {
                    buffer[count] = event;
                    count += 1;
                }
                Err(_) => break,
            }
        }
        count
    }
}
```

### Latency Budget

```
┌─────────────────────────────────────────────────────────────────┐
│                    STAGE → AUDIO LATENCY BUDGET                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Engine Event → WebSocket/TCP ────────────────────► ~5-15ms     │
│                       │                                          │
│                       ▼                                          │
│  Network Thread → Parse JSON ─────────────────────► ~0.5ms      │
│                       │                                          │
│                       ▼                                          │
│  Adapter → Stage Mapping ─────────────────────────► ~0.1ms      │
│                       │                                          │
│                       ▼                                          │
│  Ring Buffer → Audio Thread ──────────────────────► ~0.01ms     │
│                       │                                          │
│                       ▼                                          │
│  Audio Trigger → Sound Start ─────────────────────► ~0.05ms     │
│                       │                                          │
│                       ▼                                          │
│  Audio Callback → DAC Output ─────────────────────► ~3ms @128   │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│  TOTAL END-TO-END: ~10-20ms (acceptable for slot audio)         │
│  TARGET: < 50ms perceived latency                               │
└─────────────────────────────────────────────────────────────────┘
```

### SIMD Stage Batch Processing

```rust
#[cfg(target_arch = "x86_64")]
use std::arch::x86_64::*;

/// Process multiple stage events in parallel using SIMD
/// Used for batch-processing recorded traces
#[target_feature(enable = "avx2")]
unsafe fn batch_process_stages_avx2(
    stages: &[StageEventCompact],
    sound_volumes: &mut [f32],
    ducking_levels: &[f32; 32],
) {
    // Process 8 stages at once using AVX2
    let chunks = stages.chunks_exact(8);

    for (i, chunk) in chunks.enumerate() {
        // Load 8 confidence values
        let confidences = _mm256_set_ps(
            chunk[7].confidence, chunk[6].confidence,
            chunk[5].confidence, chunk[4].confidence,
            chunk[3].confidence, chunk[2].confidence,
            chunk[1].confidence, chunk[0].confidence,
        );

        // Load ducking levels for these stage types
        let duck_indices: [usize; 8] = std::array::from_fn(|j| chunk[j].stage_id as usize % 32);
        let ducking = _mm256_set_ps(
            ducking_levels[duck_indices[7]], ducking_levels[duck_indices[6]],
            ducking_levels[duck_indices[5]], ducking_levels[duck_indices[4]],
            ducking_levels[duck_indices[3]], ducking_levels[duck_indices[2]],
            ducking_levels[duck_indices[1]], ducking_levels[duck_indices[0]],
        );

        // volume = confidence * (1.0 - ducking)
        let one = _mm256_set1_ps(1.0);
        let inv_duck = _mm256_sub_ps(one, ducking);
        let volumes = _mm256_mul_ps(confidences, inv_duck);

        // Store results
        _mm256_storeu_ps(sound_volumes.as_mut_ptr().add(i * 8), volumes);
    }
}
```

---

## 18. Security & Validation (Security Expert)

### Input Validation — KRITIČNO

Svi eksterni inputi (JSON, WebSocket, TCP) moraju proći striktnu validaciju.

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ValidationError {
    #[error("Event name too long: {0} chars (max 128)")]
    EventNameTooLong(usize),

    #[error("Payload too large: {0} bytes (max 64KB)")]
    PayloadTooLarge(usize),

    #[error("Invalid JSON structure: {0}")]
    InvalidJson(String),

    #[error("Untrusted field in payload: {0}")]
    UntrustedField(String),

    #[error("Win amount out of range: {0} (max 1e12)")]
    WinAmountOverflow(f64),

    #[error("Timestamp in future: {0}ms")]
    FutureTimestamp(f64),

    #[error("Too many events in batch: {0} (max 1000)")]
    BatchTooLarge(usize),

    #[error("Invalid reel index: {0} (max 9)")]
    InvalidReelIndex(u8),

    #[error("Malformed stage string: {0}")]
    MalformedStage(String),
}

/// Security-first input validator
pub struct InputValidator {
    max_event_name_len: usize,
    max_payload_size: usize,
    max_batch_size: usize,
    max_win_amount: f64,
    allowed_fields: HashSet<&'static str>,
}

impl InputValidator {
    pub fn strict() -> Self {
        Self {
            max_event_name_len: 128,
            max_payload_size: 64 * 1024,  // 64KB
            max_batch_size: 1000,
            max_win_amount: 1e12,  // $1 trillion cap
            allowed_fields: hashset![
                "name", "time", "timestamp", "reel_index", "symbol",
                "win_amount", "bet_amount", "feature_type", "tier",
                "step", "line_index", "multiplier", "positions"
            ],
        }
    }

    pub fn validate_json(&self, json: &serde_json::Value) -> Result<(), ValidationError> {
        // Check total size
        let size = json.to_string().len();
        if size > self.max_payload_size {
            return Err(ValidationError::PayloadTooLarge(size));
        }

        // Validate event name if present
        if let Some(name) = json.get("name").and_then(|v| v.as_str()) {
            if name.len() > self.max_event_name_len {
                return Err(ValidationError::EventNameTooLong(name.len()));
            }
            // Check for injection patterns
            if name.contains('\0') || name.contains("${") || name.contains("{{") {
                return Err(ValidationError::MalformedStage(name.to_string()));
            }
        }

        // Validate events array
        if let Some(events) = json.get("events").and_then(|v| v.as_array()) {
            if events.len() > self.max_batch_size {
                return Err(ValidationError::BatchTooLarge(events.len()));
            }
            for event in events {
                self.validate_event(event)?;
            }
        }

        Ok(())
    }

    fn validate_event(&self, event: &serde_json::Value) -> Result<(), ValidationError> {
        // Check for untrusted fields (potential injection vectors)
        if let Some(obj) = event.as_object() {
            for key in obj.keys() {
                if !self.allowed_fields.contains(key.as_str()) {
                    // Log but don't fail — just ignore unknown fields
                    log::warn!("Ignoring untrusted field: {}", key);
                }
            }
        }

        // Validate win amount
        if let Some(win) = event.get("win_amount").and_then(|v| v.as_f64()) {
            if win < 0.0 || win > self.max_win_amount || !win.is_finite() {
                return Err(ValidationError::WinAmountOverflow(win));
            }
        }

        // Validate timestamp (not in future by more than 1 second)
        if let Some(ts) = event.get("time").and_then(|v| v.as_f64()) {
            // Relative timestamps — should be positive and bounded
            if ts < 0.0 || ts > 3600000.0 {  // Max 1 hour
                return Err(ValidationError::FutureTimestamp(ts));
            }
        }

        // Validate reel index
        if let Some(reel) = event.get("reel_index").and_then(|v| v.as_u64()) {
            if reel > 9 {
                return Err(ValidationError::InvalidReelIndex(reel as u8));
            }
        }

        Ok(())
    }
}
```

### Sandbox za Custom Adapters

```rust
/// Sandboxed adapter execution environment
pub struct AdapterSandbox {
    /// Maximum execution time per event (ms)
    max_exec_time_ms: u64,

    /// Maximum memory allocation (bytes)
    max_memory: usize,

    /// Allowed JSONPath depth
    max_jsonpath_depth: usize,

    /// Rate limiter (events per second)
    rate_limit: u32,

    /// Execution counter for rate limiting
    exec_count: AtomicU32,
    last_reset: AtomicU64,
}

impl AdapterSandbox {
    pub fn new() -> Self {
        Self {
            max_exec_time_ms: 100,      // 100ms timeout per event
            max_memory: 16 * 1024 * 1024, // 16MB max
            max_jsonpath_depth: 10,
            rate_limit: 1000,           // 1000 events/sec max
            exec_count: AtomicU32::new(0),
            last_reset: AtomicU64::new(0),
        }
    }

    /// Execute adapter with timeout and resource limits
    pub fn execute<F, R>(&self, f: F) -> Result<R, SandboxError>
    where
        F: FnOnce() -> R + Send + 'static,
        R: Send + 'static,
    {
        // Rate limiting
        self.check_rate_limit()?;

        // Execute with timeout
        let (tx, rx) = std::sync::mpsc::channel();
        let handle = std::thread::spawn(move || {
            let result = f();
            let _ = tx.send(result);
        });

        match rx.recv_timeout(Duration::from_millis(self.max_exec_time_ms)) {
            Ok(result) => {
                handle.join().ok();
                Ok(result)
            }
            Err(_) => {
                // Timeout — can't easily kill thread, but we can ignore result
                Err(SandboxError::Timeout)
            }
        }
    }

    fn check_rate_limit(&self) -> Result<(), SandboxError> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let last = self.last_reset.load(Ordering::Relaxed);
        if now > last {
            self.last_reset.store(now, Ordering::Relaxed);
            self.exec_count.store(0, Ordering::Relaxed);
        }

        let count = self.exec_count.fetch_add(1, Ordering::Relaxed);
        if count >= self.rate_limit {
            Err(SandboxError::RateLimited)
        } else {
            Ok(())
        }
    }
}
```

### WebSocket Security

```rust
/// Secure WebSocket connection handler
pub struct SecureConnection {
    /// TLS required in production
    require_tls: bool,

    /// Origin validation
    allowed_origins: Vec<String>,

    /// Message size limit
    max_message_size: usize,

    /// Connection timeout
    idle_timeout: Duration,

    /// Authentication token validator
    token_validator: Box<dyn TokenValidator>,
}

impl SecureConnection {
    pub fn validate_connection(&self, request: &Request) -> Result<(), SecurityError> {
        // Check TLS
        if self.require_tls && !request.is_secure() {
            return Err(SecurityError::TlsRequired);
        }

        // Check origin
        if let Some(origin) = request.headers().get("Origin") {
            let origin_str = origin.to_str().unwrap_or("");
            if !self.allowed_origins.iter().any(|o| o == origin_str) {
                return Err(SecurityError::InvalidOrigin(origin_str.to_string()));
            }
        }

        // Validate auth token
        if let Some(auth) = request.headers().get("Authorization") {
            self.token_validator.validate(auth.to_str().unwrap_or(""))?;
        } else {
            return Err(SecurityError::MissingAuth);
        }

        Ok(())
    }
}
```

---

## 19. Stage Visualization (Graphics Engineer)

### Real-Time Stage Timeline Renderer

```rust
use wgpu;

/// GPU-accelerated stage event visualization
pub struct StageTimelineRenderer {
    /// WGPU device and queue
    device: wgpu::Device,
    queue: wgpu::Queue,

    /// Vertex buffer for stage markers
    vertex_buffer: wgpu::Buffer,

    /// Instance buffer for stage instances
    instance_buffer: wgpu::Buffer,

    /// Shader pipeline
    pipeline: wgpu::RenderPipeline,

    /// Stage color lookup texture
    color_lut: wgpu::Texture,
}

/// Vertex data for stage marker
#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct StageVertex {
    position: [f32; 2],
}

/// Instance data per stage event
#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct StageInstance {
    /// X position (time) normalized 0-1
    time_pos: f32,

    /// Stage type index (for color lookup)
    stage_type: u32,

    /// Confidence (affects opacity)
    confidence: f32,

    /// Height multiplier (for win amount)
    height: f32,
}

impl StageTimelineRenderer {
    /// Render stage trace on timeline
    pub fn render(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        target: &wgpu::TextureView,
        trace: &StageTrace,
        viewport: &Viewport,
    ) {
        // Convert StageTrace to instance data
        let instances: Vec<StageInstance> = trace.events.iter().map(|e| {
            StageInstance {
                time_pos: (e.timestamp_ms / trace.total_duration_ms()) as f32,
                stage_type: e.stage.to_type_index(),
                confidence: e.confidence.unwrap_or(1.0) as f32,
                height: self.calculate_height(&e.stage, &e.payload),
            }
        }).collect();

        // Upload instances
        self.queue.write_buffer(
            &self.instance_buffer,
            0,
            bytemuck::cast_slice(&instances),
        );

        // Render pass
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("Stage Timeline"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: target,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Load,  // Don't clear, overlay on timeline
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            ..Default::default()
        });

        pass.set_pipeline(&self.pipeline);
        pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
        pass.set_vertex_buffer(1, self.instance_buffer.slice(..));
        pass.draw(0..4, 0..instances.len() as u32);  // Quad per instance
    }

    fn calculate_height(&self, stage: &Stage, payload: &StagePayload) -> f32 {
        match stage {
            Stage::BigWinTier { tier } => match tier {
                BigWinTier::Win => 0.4,
                BigWinTier::BigWin => 0.6,
                BigWinTier::MegaWin => 0.8,
                BigWinTier::EpicWin => 0.9,
                BigWinTier::UltraWin => 1.0,
            },
            Stage::JackpotTrigger { .. } => 1.0,
            Stage::FeatureEnter { .. } => 0.7,
            Stage::AnticipationOn { .. } => 0.5,
            Stage::ReelStop { .. } => 0.3,
            _ => 0.2,
        }
    }
}
```

### Stage Color Palette

```rust
/// Stage type colors matching FluxForge theme
pub const STAGE_COLORS: &[(Stage, [f32; 4])] = &[
    // Spin lifecycle — Cyan
    (Stage::SpinStart, [0.25, 0.78, 1.0, 1.0]),
    (Stage::ReelSpinning { reel_index: 0 }, [0.25, 0.78, 1.0, 0.7]),
    (Stage::ReelStop { reel_index: 0 }, [0.25, 0.78, 1.0, 1.0]),
    (Stage::SpinEnd, [0.25, 0.78, 1.0, 0.5]),

    // Anticipation — Orange
    (Stage::AnticipationOn { reel_index: 0 }, [1.0, 0.56, 0.25, 1.0]),
    (Stage::AnticipationOff { reel_index: 0 }, [1.0, 0.56, 0.25, 0.5]),

    // Win — Green
    (Stage::WinPresent, [0.25, 1.0, 0.56, 1.0]),
    (Stage::WinLineShow { line_index: 0 }, [0.25, 1.0, 0.56, 0.7]),
    (Stage::RollupStart, [0.25, 1.0, 0.56, 0.8]),
    (Stage::RollupEnd, [0.25, 1.0, 0.56, 0.6]),

    // Big Win — Gold gradient
    (Stage::BigWinTier { tier: BigWinTier::Win }, [1.0, 0.85, 0.25, 1.0]),
    (Stage::BigWinTier { tier: BigWinTier::BigWin }, [1.0, 0.75, 0.25, 1.0]),
    (Stage::BigWinTier { tier: BigWinTier::MegaWin }, [1.0, 0.65, 0.25, 1.0]),
    (Stage::BigWinTier { tier: BigWinTier::EpicWin }, [1.0, 0.55, 0.25, 1.0]),
    (Stage::BigWinTier { tier: BigWinTier::UltraWin }, [1.0, 0.45, 0.25, 1.0]),

    // Feature — Purple
    (Stage::FeatureEnter { feature_type: FeatureType::FreeSpins }, [0.56, 0.25, 1.0, 1.0]),
    (Stage::FeatureStep { step_index: 0 }, [0.56, 0.25, 1.0, 0.7]),
    (Stage::FeatureExit, [0.56, 0.25, 1.0, 0.5]),

    // Jackpot — Red
    (Stage::JackpotTrigger { tier: JackpotTier::Grand }, [1.0, 0.25, 0.38, 1.0]),
    (Stage::JackpotPresent, [1.0, 0.25, 0.38, 0.8]),

    // Bonus — Magenta
    (Stage::BonusEnter, [1.0, 0.25, 0.78, 1.0]),
    (Stage::BonusExit, [1.0, 0.25, 0.78, 0.5]),
];
```

---

## 20. Workflow & UX (UI/UX Expert)

### Adapter Wizard UX Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     ADAPTER WIZARD WORKFLOW                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  STEP 1: Import                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  📁 Drop JSON file here                                    │  │
│  │                                                             │  │
│  │  ─────────── OR ───────────                                │  │
│  │                                                             │  │
│  │  🔗 Connect to live engine: ws://localhost:9876            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                          │                                       │
│                          ▼                                       │
│  STEP 2: Analyze                                                 │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Detected 47 unique event types                            │  │
│  │  ════════════════════════════════════════════════════════  │  │
│  │  ✅ spin_start          → SpinStart         (98%)          │  │
│  │  ✅ reel_stop_0         → ReelStop[0]       (95%)          │  │
│  │  ✅ reel_stop_1         → ReelStop[1]       (95%)          │  │
│  │  ⚠️ show_result         → WinPresent?       (72%)          │  │
│  │  ⚠️ celebration_start   → BigWinTier?       (65%)          │  │
│  │  ❓ state_update        → ???               (0%)           │  │
│  │  ════════════════════════════════════════════════════════  │  │
│  │  Coverage: 38/47 events (81%)                              │  │
│  └────────────────────────────────────────────────────────────┘  │
│                          │                                       │
│                          ▼                                       │
│  STEP 3: Refine                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Event: show_result                                        │  │
│  │  ──────────────────────────────────────────────────────────│  │
│  │  Sample data: { "win": 150, "lines": [...] }               │  │
│  │                                                             │  │
│  │  Suggested: WinPresent (72%)                               │  │
│  │  Alternatives:                                              │  │
│  │    ○ RollupStart (18%)                                     │  │
│  │    ○ WinLineShow (10%)                                     │  │
│  │                                                             │  │
│  │  Your choice:  [WinPresent ▾]                              │  │
│  │                                                             │  │
│  │  Extract payload:                                           │  │
│  │    win_amount: $.win                                        │  │
│  │    line_positions: $.lines                                  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                          │                                       │
│                          ▼                                       │
│  STEP 4: Preview                                                 │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Timeline Preview                                          │  │
│  │  ──────────────────────────────────────────────────────────│  │
│  │  │    │    │    │    │    │    │    │                      │  │
│  │  │ ▲  │  ▲ │  ▲ │  ▲ │  ▲ │    │    │  ← Stage markers     │  │
│  │  │ │  │  │ │  │ │  │ │  │ │    │    │                      │  │
│  │  ├─●──┼──●─┼──●─┼──●─┼──●─┼────┼────┤  ← Event timeline    │  │
│  │  0s   1s   2s   3s   4s   5s   6s   7s                     │  │
│  │                                                             │  │
│  │  ▶ Play with Audio    ⏹ Stop                               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                          │                                       │
│                          ▼                                       │
│  STEP 5: Export                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Adapter Config: my-slot-game.yaml                         │  │
│  │                                                             │  │
│  │  ☑ Include heuristics for unknown events                   │  │
│  │  ☑ Enable FSM validation                                    │  │
│  │  ☐ Strict mode (fail on unmapped)                          │  │
│  │                                                             │  │
│  │  [Export YAML]  [Copy to Clipboard]  [Save to Project]     │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl + O` | Open JSON file |
| `Cmd/Ctrl + S` | Save adapter config |
| `Space` | Play/Pause preview |
| `←/→` | Navigate events |
| `Enter` | Confirm mapping |
| `Tab` | Next unmapped event |
| `Shift+Tab` | Previous unmapped event |
| `Cmd/Ctrl + Z` | Undo mapping change |
| `Cmd/Ctrl + E` | Export adapter |

### Error States UX

```dart
/// Wizard error display widget
class WizardErrorState extends StatelessWidget {
  final WizardError error;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border.all(
          color: error.severity == Severity.critical
            ? Colors.red
            : Colors.orange,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                error.severity == Severity.critical
                  ? Icons.error
                  : Icons.warning,
                color: error.severity == Severity.critical
                  ? Colors.red
                  : Colors.orange,
              ),
              SizedBox(width: 8),
              Text(error.title, style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: 8),
          Text(error.message),
          SizedBox(height: 8),
          if (error.suggestion != null)
            Text(
              'Suggestion: ${error.suggestion}',
              style: TextStyle(color: FluxForgeTheme.textSecondary),
            ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (error.canSkip)
                TextButton(onPressed: onSkip, child: Text('Skip')),
              ElevatedButton(onPressed: onRetry, child: Text('Retry')),
            ],
          ),
        ],
      ),
    );
  }
}
```

---

## 16. Sledeći Koraci

### Faza 1 — Core Infrastructure
1. **rf-stage** crate — Stage enum, StageEvent, StageTrace, FSM validacija
2. **rf-ingest** crate — Adapter trait, registry, 3 ingest layers

### Faza 2 — Adapter System
3. **YAML Parser** — Parsiranje adapter config fajlova
4. **Adapter Wizard** — Heuristics, automatska detekcija, config generator
5. **Generic Adapter** — Fallback adapter za nepoznate engine-e

### Faza 3 — SDK Development
6. **Unity SDK** — C# package za Unity Package Manager
7. **Unreal SDK** — C++ plugin sa Blueprint support-om
8. **JavaScript SDK** — Za web-based slot engine-e

### Faza 4 — Flutter Integration
9. **Wizard UI Panel** — Drag-drop mapping editor
10. **Live Preview** — Real-time stage visualization
11. **Adapter Manager** — Browse, import, export adaptera

### Faza 5 — Audio Integration
12. **Stage → Audio Trigger** — Binding StageEvent sa sound bank-om
13. **Hierarchical Pattern Matching** — Wildcard patterns za audio triggers
14. **Confidence-Based Volume** — Dinamički volume based on confidence

---

## Appendix A — Primer Kompletnog Workflow-a

```
1. Developer ubaci JSON log iz slot igre u FluxForge
2. Adapter Wizard analizira event names
3. Wizard predlaže mapiranje sa confidence scorevima
4. Developer potvrđuje/koriguje mapiranja
5. FluxForge generiše StageTrace
6. Audio designer kreira sound bank baziran na STAGES
7. Live preview reprodukuje igru sa audio
8. Export adapter config za production
```

## Appendix B — Supported Engine Formats

| Engine/Platform | Adapter | Ingest Layer | Status |
|-----------------|---------|--------------|--------|
| IGT AVP | igt-avp | Direct Event | Planned |
| Aristocrat | aristocrat-mk7 | Direct Event | Planned |
| Novomatic | novomatic-v2 | Snapshot Diff | Planned |
| Scientific Games | sg-alpha | Direct Event | Planned |
| Unity (generic) | unity-generic | Direct Event | Planned |
| Unreal (generic) | unreal-generic | Direct Event | Planned |
| Custom JSON | json-generic | Heuristic | Planned |
| WebSocket stream | ws-realtime | Direct Event | Planned |

---

**Verzija:** 3.0
**Poslednje ažuriranje:** 2026-01-16
**Autor:** FluxForge Team + Claude
