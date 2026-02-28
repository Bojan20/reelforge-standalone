//! Global Energy Governance (GEG)
//!
//! Controls energy budget across 5 domains per tick.
//! Formula: `FinalCap = min(1.0, EI × SP × SM)`

pub mod governance;
pub mod slot_profiles;
pub mod escalation;
pub mod session_memory;

pub use governance::{EnergyGovernor, EnergyDomain, EnergyBudget, VoiceBudget};
pub use slot_profiles::{SlotProfile, SlotProfileData, SLOT_PROFILES};
pub use escalation::{GegEscalationCurve, GegCurveType};
pub use session_memory::SessionMemory;
