//! rf-cloud-sync — Git-like Project Versioning Engine (T7.1)
//!
//! Content-addressed snapshot history for FluxForge projects.
//! Designed to work fully offline; cloud sync is a transport layer
//! on top of this store — implement HTTP push/pull separately.
//!
//! ## Architecture
//!
//! ```text
//! SyncHistory ──► [Snapshot_0] ──► [Snapshot_1] ──► ... ──► [Snapshot_N]
//!                      ▲                 ▲
//!                  (root)           parent_id = Snapshot_0.id
//! ```
//!
//! Every snapshot is a full copy of the project JSON plus metadata.
//! Diffs are computed on demand — storage is simple, diffs are fast.

pub mod diff;
pub mod history;
pub mod snapshot;
pub mod sync;

pub use diff::{DiffEntry, DiffOp, ProjectDiff};
pub use history::{ProjectHistory, SnapshotSummary};
pub use snapshot::ProjectSnapshot;
pub use sync::{SyncManager, SyncConfig};
