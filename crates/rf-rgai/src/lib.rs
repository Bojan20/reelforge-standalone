//! rf-rgai — Responsible Gaming Audio Intelligence (RGAI™)
//!
//! Quantitative compliance analysis engine that scores every audio asset and
//! game configuration against responsible-gaming regulations worldwide.
//!
//! ## Core Metrics
//!
//! | Metric                     | Range | What it measures                              |
//! |----------------------------|-------|-----------------------------------------------|
//! | Arousal Coefficient        | 0–1   | Stimulatory intensity of audio                |
//! | Near-Miss Deception Index  | 0–1   | How much near-miss audio fakes a win          |
//! | Loss-Disguise Score        | 0–1   | How much loss sounds like a win (LDW)         |
//! | Temporal Distortion Factor | 0–1   | Whether audio warps time perception           |
//! | Addiction Risk Rating      | enum  | Composite: LOW / MEDIUM / HIGH / PROHIBITED   |
//!
//! ## Supported Jurisdictions
//!
//! UKGC, MGA Malta, Ontario iGaming, Sweden Spelinspektionen,
//! Denmark Spillemyndigheden, Netherlands KSA, Australia ACMA.
//!
//! ## Export Gate
//!
//! The [`ExportGate`] blocks export if any metric exceeds jurisdiction thresholds.
//! No manual override — compliance is non-negotiable.

pub mod analysis;
pub mod export_gate;
pub mod jurisdiction;
pub mod metrics;
pub mod remediation;
pub mod report;
pub mod session;

pub use analysis::RgaiAnalyzer;
pub use export_gate::ExportGate;
pub use jurisdiction::{Jurisdiction, JurisdictionProfile};
pub use metrics::{
    AddictionRiskRating, ArousalCoefficient, LossDisguiseScore, NearMissDeceptionIndex,
    RgaiMetrics, TemporalDistortionFactor,
};
pub use remediation::{RemediationAction, RemediationPlan};
pub use report::{RgarFinding, RgarReport, RgarSection, Severity};
pub use session::{AudioAssetProfile, GameAudioSession, SessionAnalysis};
