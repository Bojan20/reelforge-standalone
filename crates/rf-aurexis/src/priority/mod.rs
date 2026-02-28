//! DPM — Dynamic Priority Matrix
//!
//! Computes per-voice priority scores using a 5-factor formula:
//! `PriorityScore = BaseWeight × EmotionalWeight × ProfileWeight × EnergyWeight × ContextModifier`
//!
//! Then applies voice survival logic: sort → retain → attenuate → suppress.

pub mod dpm;

pub use dpm::{
    DynamicPriorityMatrix, EventType, EmotionalState, VoicePriority, VoiceSurvivalResult,
    SurvivalAction, DpmOutput,
};
