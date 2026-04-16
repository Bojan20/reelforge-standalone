//! rf-fingerprint — Neural Fingerprint™ + A/B Analytics (T6.1–T6.5)
//!
//! ## Features
//!
//! ### T6.1 – Audio Fingerprinting
//! Deterministic content-based fingerprint for slot audio export bundles.
//! Used to identify, track, and verify audio packages in distribution.
//! Fingerprint = SHA-256 of sorted canonical event descriptors.
//!
//! ### T6.2–T6.3 – A/B Test Analytics
//! Statistical significance calculator for A/B audio test results.
//! Uses two-proportion z-test (Wilson interval for small samples).
//!
//! ### T6.4 – Fingerprint Verification
//! Re-fingerprint a bundle and compare against stored fingerprint.
//!
//! ### T6.5 – Honeypot Export Mode
//! Inject a unique tracking watermark into export metadata so
//! leaked/pirated packages can be traced back to the recipient.

pub mod ab_test;
pub mod fingerprint;
pub mod honeypot;

pub use ab_test::{AbTestConfig, AbTestReport, AbVariant, StatisticalResult};
pub use fingerprint::{BundleFingerprint, FingerprintSpec, VerificationResult};
pub use honeypot::{HoneypotMarker, HoneypotResult};
