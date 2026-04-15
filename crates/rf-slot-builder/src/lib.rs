//! # rf-slot-builder — FluxForge Slot Construction Kit
//!
//! The modular architecture that powers the FluxForge Slot Builder platform.
//!
//! ## Core concepts
//!
//! ```text
//! SlotBlueprint
//! ├── metadata     (name, version, jurisdiction, rtp target)
//! ├── math_config  (reel strips, paytable, volatility params)
//! ├── StageFlow    (directed graph of game phases)
//! │   ├── StageNode (each game phase: spin, win, feature, bonus...)
//! │   │   ├── stage_type   (what Stage enum variant this maps to)
//! │   │   ├── audio_binding (which HELIX events to fire)
//! │   │   ├── math_binding  (which math params drive this node)
//! │   │   ├── compliance    (per-node regulatory rules)
//! │   │   └── transitions  → [StageTransition → next NodeId]
//! │   └── ...more nodes
//! ├── audio_dna    (brand sonic identity config)
//! └── visual_meta  (node positions for graph editor)
//! ```
//!
//! ## Stage Flow execution model
//!
//! The [`FlowExecutor`] is a deterministic state machine:
//! 1. Starts at the designated `entry_node`
//! 2. Emits `Stage` events to the HELIX Bus on node entry
//! 3. Waits for an external event (spin result, win eval, user input)
//! 4. Evaluates [`TransitionCondition`]s to pick next node
//! 5. Fires exit events, moves to next node
//! 6. Repeats until reaching a terminal node
//!
//! ## Example — Classic 5×3 slot
//!
//! ```rust,no_run
//! use rf_slot_builder::template::SlotTemplate;
//! use rf_slot_builder::executor::FlowExecutor;
//!
//! let blueprint = SlotTemplate::Classic5x3.build();
//! let mut executor = FlowExecutor::new(blueprint);
//! executor.start();
//! ```

pub mod binding;
pub mod blueprint;
pub mod executor;
pub mod export;
pub mod flow;
pub mod node;
pub mod template;
pub mod validator;

// Re-export primary types
pub use binding::{AudioBinding, AudioEventRef, MathBinding, MathParamRef};
pub use blueprint::{
    AudioDna, BlueprintMeta, ComplianceConfig, JurisdictionProfile, MathConfig, ReelStrip,
    SlotBlueprint,
};
pub use executor::{ExecutorState, FlowEvent, FlowExecutor, SpinOutcome, WinData};
pub use export::{BlueprintExport, ExportFormat};
pub use flow::{StageFlow, ValidationError as FlowValidationError};
pub use node::{
    ComplianceRule, NodeId, NodeVisualMeta, StageNode, StageTransition, TransitionCondition,
    TransitionPriority,
};
pub use template::SlotTemplate;
pub use validator::{BlueprintReport, ValidationSeverity, Validator};
