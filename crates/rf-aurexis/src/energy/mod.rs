//! Global Energy Governance (GEG)
//!
//! Controls energy budget across 5 domains per tick.
//! Formula: `FinalCap = min(1.0, EI × SP × SM)`

pub mod escalation;
pub mod governance;
pub mod session_memory;
pub mod slot_profiles;

pub use escalation::{GegCurveType, GegEscalationCurve};
pub use governance::{EnergyBudget, EnergyDomain, EnergyGovernor, VoiceBudget};
pub use session_memory::SessionMemory;
pub use slot_profiles::{SLOT_PROFILES, SlotProfile, SlotProfileData};
