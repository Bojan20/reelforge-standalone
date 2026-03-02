//! SAMCL — Spectral Allocation & Masking Control Layer
//!
//! 10 spectral roles, masking resolution, SCI collision index.
//! Deterministic spectral allocation for slot audio voices.

pub mod allocation;
pub mod masking;
pub mod roles;

pub use allocation::{SpectralAllocationOutput, SpectralAllocator, SpectralAssignment};
pub use masking::{MaskingAction, MaskingResolver, MaskingStrategy, SciAdvanced};
pub use roles::{SpectralBand, SpectralRole};
