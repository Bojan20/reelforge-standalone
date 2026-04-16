//! rf-copilot — AI Co-Pilot™ Context-Aware Suggestion Engine (T5.1–T5.4)
//!
//! Rule-based, deterministic suggestion engine that analyzes a slot audio project
//! and produces actionable recommendations based on industry best practices.
//!
//! ## Architecture
//!
//! ```text
//! AudioProject  →  SuggestionEngine  →  CopilotReport
//!                         ↑
//!                  IndustryBenchmarks (embedded)
//! ```
//!
//! The engine is entirely rule-based (no ML). Rules are organized by domain:
//! - Voice budget (Little's Law projection)
//! - Event coverage (required events per game type)
//! - Win tier calibration (proportional win sounds)
//! - Feature audio requirements
//! - Responsible Gaming compliance
//! - Loop coverage (spin sounds)
//! - Priority ordering
//! - Industry standard duration benchmarks

pub mod benchmarks;
pub mod engine;
pub mod project;
pub mod suggestions;

pub use benchmarks::{IndustryBenchmark, SlotCategory};
pub use engine::SuggestionEngine;
pub use project::{AudioEventSpec, AudioProjectSpec};
pub use suggestions::{CopilotReport, CopilotSuggestion, SuggestionCategory, SuggestionSeverity};
