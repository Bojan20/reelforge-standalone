//! SAMCL — Spectral Allocation & Masking Control Layer
//!
//! 10 spectral roles, masking resolution, SCI collision index.
//! Deterministic spectral allocation for slot audio voices.

pub mod roles;
pub mod allocation;
pub mod masking;

pub use roles::{SpectralRole, SpectralBand};
pub use allocation::{SpectralAllocator, SpectralAssignment, SpectralAllocationOutput};
pub use masking::{MaskingResolver, MaskingStrategy, MaskingAction, SciAdvanced};
