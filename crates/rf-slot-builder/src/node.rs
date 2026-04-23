//! StageNode — the atomic unit of the Slot Construction Kit
//!
//! A `StageNode` is a self-contained game phase with:
//! - **What happens** (math logic binding)
//! - **What sounds** (HELIX audio binding)
//! - **What the regulator sees** (compliance rules)
//! - **How it connects** (typed transitions to other nodes)
//!
//! Nodes are assembled into a [`StageFlow`] directed graph.

use std::cmp::Reverse;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::binding::{AudioBinding, MathBinding};

/// Stable unique identifier for a node within a blueprint.
/// Uses UUID v4 for marketplace sharing and cross-blueprint references.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct NodeId(pub Uuid);

impl NodeId {
    pub fn new() -> Self {
        Self(Uuid::new_v4())
    }

    /// Human-readable shorthand (first 8 chars of UUID)
    pub fn short(&self) -> String {
        self.0.to_string()[..8].to_string()
    }

    /// Create from a static string (for built-in template nodes)
    pub fn from_static(s: &str) -> Self {
        Self(Uuid::new_v5(&Uuid::NAMESPACE_OID, s.as_bytes()))
    }
}

impl Default for NodeId {
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Display for NodeId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.short())
    }
}

// ─── Node category ───────────────────────────────────────────────────────────

/// High-level category for grouping and UI display
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NodeCategory {
    /// Game is waiting for user action
    Idle,
    /// Spin lifecycle (press → spin → stop → evaluate)
    Spin,
    /// Win presentation (present → rollup → bigwin)
    Win,
    /// Free spins or feature game
    Feature,
    /// Cascading/tumbling reels
    Cascade,
    /// Pick bonus, wheel bonus, etc.
    Bonus,
    /// Gamble / double-or-nothing
    Gamble,
    /// Jackpot sequence
    Jackpot,
    /// UI / menu
    UI,
    /// Flow control only (branch, merge, loop counter)
    FlowControl,
    /// Custom user-defined
    Custom,
}

// ─── Compliance rule ─────────────────────────────────────────────────────────

/// Regulatory rule attached to a node.
/// These are checked by the [`Validator`] and used to generate compliance reports.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComplianceRule {
    /// Unique rule identifier (e.g. "UKGC-RTS-13-near-miss")
    pub rule_id: String,

    /// Human description
    pub description: String,

    /// Jurisdiction(s) this rule applies to
    pub jurisdictions: Vec<String>,

    /// The actual constraint
    pub constraint: ComplianceConstraint,

    /// Severity if violated
    pub severity: ComplianceSeverity,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ComplianceConstraint {
    /// Audio excitement must not exceed this level (0.0-1.0) on near-miss stages
    MaxAudioExcitement { level: f32 },
    /// Stage must not play for longer than this many milliseconds
    MaxDurationMs { ms: u64 },
    /// Stage must fire a specific audit event to the compliance bus
    RequiresAuditEvent { event_name: String },
    /// Stage must NOT be reachable without a preceding player action
    RequiresPlayerAction,
    /// Win must be presented for at minimum N ms before user can dismiss
    MinDisplayMs { ms: u64 },
    /// Big win screen must be skippable within N ms (some markets forbid forced delays)
    MaxForcedDelayMs { ms: u64 },
    /// Near-miss audio must be the same as any other no-win outcome
    NearMissAudioParity,
    /// Gamble feature must show RTP on screen
    GambleRtpDisplay,
    /// Free spins cannot be retriggered more than N times
    MaxRetriggerCount { count: u8 },
    /// Custom rule (evaluated by external validator plugin)
    Custom { validator_id: String, params: serde_json::Value },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ComplianceSeverity {
    /// Will block certification
    Critical,
    /// Should be fixed before submission
    Warning,
    /// Informational only
    Info,
}

// ─── Visual metadata ─────────────────────────────────────────────────────────

/// Position and appearance in the node graph editor.
/// Purely cosmetic — does not affect execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeVisualMeta {
    /// X position in the canvas (pixels)
    pub x: f32,
    /// Y position in the canvas
    pub y: f32,
    /// Display color (hex)
    pub color: String,
    /// Custom label (overrides auto-generated label)
    pub label: Option<String>,
    /// Width in canvas (default: 200)
    pub width: f32,
    /// Collapsed in editor
    pub collapsed: bool,
    /// User notes / comments
    pub notes: Option<String>,
}

impl Default for NodeVisualMeta {
    fn default() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            color: "#4a90d9".to_string(),
            label: None,
            width: 200.0,
            collapsed: false,
            notes: None,
        }
    }
}

// ─── Transition ───────────────────────────────────────────────────────────────

/// Priority determines evaluation order when multiple transitions could match.
/// Higher priority transitions are evaluated first.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct TransitionPriority(pub u8);

impl Default for TransitionPriority {
    fn default() -> Self {
        Self(128) // mid-range
    }
}

/// A directed edge from one node to another, with a typed condition.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StageTransition {
    /// Unique ID for this transition (for UI wiring)
    pub id: Uuid,

    /// Target node
    pub to: NodeId,

    /// Condition that must be true to take this transition.
    /// If condition is `Always`, it acts as an unconditional (default) edge.
    pub condition: TransitionCondition,

    /// Evaluation priority (higher = evaluated first)
    pub priority: TransitionPriority,

    /// Optional delay before entering next node (ms)
    pub delay_ms: u32,

    /// Human label shown on the edge in the editor
    pub label: Option<String>,
}

impl StageTransition {
    /// Create a simple unconditional transition to a target node
    pub fn always(to: NodeId) -> Self {
        Self {
            id: Uuid::new_v4(),
            to,
            condition: TransitionCondition::Always,
            priority: TransitionPriority::default(),
            delay_ms: 0,
            label: None,
        }
    }

    pub fn on_win(to: NodeId, min_amount: Option<f64>) -> Self {
        Self {
            id: Uuid::new_v4(),
            to,
            condition: TransitionCondition::WinAmount {
                min: min_amount.unwrap_or(0.01),
                max: None,
            },
            priority: TransitionPriority(200),
            delay_ms: 0,
            label: Some("WIN".to_string()),
        }
    }

    pub fn on_no_win(to: NodeId) -> Self {
        Self {
            id: Uuid::new_v4(),
            to,
            condition: TransitionCondition::NoWin,
            priority: TransitionPriority(200),
            delay_ms: 0,
            label: Some("NO WIN".to_string()),
        }
    }

    pub fn on_feature(to: NodeId, feature_id: Option<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            to,
            condition: TransitionCondition::FeatureTriggered { feature_id },
            priority: TransitionPriority(220),
            delay_ms: 0,
            label: Some("FEATURE".to_string()),
        }
    }

    pub fn with_delay(mut self, ms: u32) -> Self {
        self.delay_ms = ms;
        self
    }

    pub fn with_label(mut self, label: impl Into<String>) -> Self {
        self.label = Some(label.into());
        self
    }
}

/// Typed condition for a transition edge.
/// The executor evaluates these against the current [`SpinOutcome`] / game state.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum TransitionCondition {
    // ── Unconditional ────────────────────────────────────────────────────
    /// Always take this transition (default/fallback edge)
    Always,

    // ── Win conditions ────────────────────────────────────────────────────
    /// No win occurred (total_win == 0)
    NoWin,
    /// Win amount is within [min, max] (max=None means unbounded)
    WinAmount { min: f64, max: Option<f64> },
    /// Win multiplier relative to bet is within range
    WinMultiplier { min: f64, max: Option<f64> },
    /// Big win tier was triggered
    BigWinTier { tier: BigWinTierCondition },
    /// Jackpot of specific tier was triggered
    JackpotTier { tier: JackpotTierCondition },

    // ── Feature / bonus triggers ─────────────────────────────────────────
    /// A feature was triggered (free spins, bonus, etc.)
    FeatureTriggered { feature_id: Option<String> },
    /// Scatter count threshold reached
    ScatterCount { min: u8, max: Option<u8> },
    /// Buy feature was activated by user
    BuyFeature,

    // ── Cascade conditions ────────────────────────────────────────────────
    /// A cascade/tumble occurred (symbols removed, new ones dropped)
    CascadeOccurred,
    /// No more cascades possible (settle)
    NoCascade,
    /// Specific cascade multiplier reached
    CascadeMultiplier { min: f64 },

    // ── Retrigger conditions ──────────────────────────────────────────────
    /// Feature was retriggered (scatters during free spins)
    Retrigger,
    /// Retrigger count reached limit
    RetriggerLimitReached { max_count: u8 },

    // ── Counter / loop control ────────────────────────────────────────────
    /// Internal counter has reached a target value
    CounterReached { counter_id: String, target: u32 },
    /// Counter has NOT yet reached target
    CounterNotReached { counter_id: String, target: u32 },

    // ── User interaction ──────────────────────────────────────────────────
    /// User confirmed (OK, collect, etc.)
    UserConfirm,
    /// User made a specific pick choice
    UserPick { pick_index: Option<u8> },
    /// Autoplay is active
    AutoplayActive,
    /// Gamble choice — higher card / red / etc.
    GambleChoice { choice: GambleChoice },
    /// Gamble result
    GambleResult { outcome: GambleOutcome },

    // ── Time-based ────────────────────────────────────────────────────────
    /// Elapsed time in current node exceeds threshold
    TimeoutMs { ms: u64 },

    // ── Compliance / regulatory ───────────────────────────────────────────
    /// Player has exceeded responsible gambling limit
    RGLimitReached,
    /// Current session duration exceeds limit
    SessionDurationExceeded { minutes: u32 },

    // ── Custom ────────────────────────────────────────────────────────────
    /// Evaluated by external plugin / script
    Custom { evaluator_id: String, params: serde_json::Value },

    // ── Boolean combinators ───────────────────────────────────────────────
    /// All of the given conditions must be true
    And { conditions: Vec<TransitionCondition> },
    /// At least one of the given conditions must be true
    Or { conditions: Vec<TransitionCondition> },
    /// The given condition must be false
    Not { condition: Box<TransitionCondition> },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BigWinTierCondition {
    Any,
    AtLeast { min_multiplier: f64 },
    Exact { tier: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum JackpotTierCondition {
    Any,
    Mini,
    Minor,
    Major,
    Grand,
    Mega,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GambleChoice {
    Any,
    Higher,
    Lower,
    Red,
    Black,
    Custom(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GambleOutcome {
    Win,
    Lose,
    Draw,
}

// ─── StageNode ────────────────────────────────────────────────────────────────

/// A node in the slot flow graph — one game phase.
///
/// Each node is self-contained: it knows what stage it represents,
/// how to fire audio, what math drives it, and what compliance rules apply.
/// Its transitions define all possible exits from this phase.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StageNode {
    /// Stable unique ID (survives renames)
    pub id: NodeId,

    /// Human-readable name (used in editor + exports)
    pub name: String,

    /// High-level category
    pub category: NodeCategory,

    /// The rf-stage Stage type this node emits on entry.
    /// Stored as a type name string for flexibility; executor resolves to Stage enum.
    pub stage_type: String,

    /// Additional stage fields / parameters (merged with stage_type at runtime)
    pub stage_params: serde_json::Value,

    /// Audio binding — which HELIX events to fire and how
    pub audio: AudioBinding,

    /// Math binding — which math model parameters drive this node's behavior
    pub math: MathBinding,

    /// Compliance rules declared on this node
    pub compliance: Vec<ComplianceRule>,

    /// Outgoing transitions (evaluated in priority order, first match wins)
    pub transitions: Vec<StageTransition>,

    /// Is this the entry point of the flow? (only one node can be entry)
    pub is_entry: bool,

    /// Is this a terminal node? (flow ends here, ready for next spin press)
    pub is_terminal: bool,

    /// Can this node be interrupted? (e.g. autoplay skip, turbo mode)
    pub interruptible: bool,

    /// Minimum time to display this node before allowing transitions (ms)
    pub min_display_ms: u32,

    /// Maximum time before forcing a transition via timeout (ms, 0 = no timeout)
    pub max_display_ms: u32,

    /// Tags for filtering, grouping, and Marketplace search
    pub tags: Vec<String>,

    /// Editor visual metadata
    pub visual: NodeVisualMeta,

    /// Schema version this node was authored against
    pub schema_version: String,
}

impl StageNode {
    /// Create a new node with sensible defaults
    pub fn new(name: impl Into<String>, stage_type: impl Into<String>) -> Self {
        Self {
            id: NodeId::new(),
            name: name.into(),
            category: NodeCategory::Custom,
            stage_type: stage_type.into(),
            stage_params: serde_json::Value::Object(serde_json::Map::new()),
            audio: AudioBinding::default(),
            math: MathBinding::default(),
            compliance: Vec::new(),
            transitions: Vec::new(),
            is_entry: false,
            is_terminal: false,
            interruptible: false,
            min_display_ms: 0,
            max_display_ms: 0,
            tags: Vec::new(),
            visual: NodeVisualMeta::default(),
            schema_version: "1.0.0".to_string(),
        }
    }

    /// Override the auto-generated ID with a specific one (required for templates)
    pub fn with_id(mut self, id: NodeId) -> Self {
        self.id = id;
        self
    }

    pub fn with_category(mut self, cat: NodeCategory) -> Self {
        self.category = cat;
        self
    }

    pub fn as_entry(mut self) -> Self {
        self.is_entry = true;
        self
    }

    pub fn as_terminal(mut self) -> Self {
        self.is_terminal = true;
        self
    }

    pub fn interruptible(mut self) -> Self {
        self.interruptible = true;
        self
    }

    pub fn with_min_display(mut self, ms: u32) -> Self {
        self.min_display_ms = ms;
        self
    }

    pub fn with_max_display(mut self, ms: u32) -> Self {
        self.max_display_ms = ms;
        self
    }

    pub fn add_transition(mut self, t: StageTransition) -> Self {
        self.transitions.push(t);
        self
    }

    pub fn with_tags(mut self, tags: impl IntoIterator<Item = impl Into<String>>) -> Self {
        self.tags = tags.into_iter().map(Into::into).collect();
        self
    }

    pub fn with_visual(mut self, x: f32, y: f32, color: impl Into<String>) -> Self {
        self.visual.x = x;
        self.visual.y = y;
        self.visual.color = color.into();
        self
    }

    pub fn with_audio(mut self, audio: AudioBinding) -> Self {
        self.audio = audio;
        self
    }

    pub fn with_math(mut self, math: MathBinding) -> Self {
        self.math = math;
        self
    }

    /// Add a UKGC near-miss compliance rule
    pub fn with_near_miss_compliance(mut self) -> Self {
        self.compliance.push(ComplianceRule {
            rule_id: "UKGC-RTS-13-NM-AUDIO".to_string(),
            description: "Near-miss audio must be identical to regular no-win".to_string(),
            jurisdictions: vec!["GB".to_string(), "UKGC".to_string()],
            constraint: ComplianceConstraint::NearMissAudioParity,
            severity: ComplianceSeverity::Critical,
        });
        self
    }

    /// Sorted transitions by priority (desc) for evaluation
    pub fn sorted_transitions(&self) -> Vec<&StageTransition> {
        let mut t: Vec<&StageTransition> = self.transitions.iter().collect();
        t.sort_by_key(|x| Reverse(x.priority));
        t
    }

    /// Check if this node has any outgoing transition
    pub fn has_exit(&self) -> bool {
        !self.transitions.is_empty() || self.is_terminal
    }
}
