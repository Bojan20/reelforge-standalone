//! # rf-connector — FluxForge Engine Connector
//!
//! Live connection to game engines via WebSocket/TCP.
//!
//! ## Features
//!
//! - Real-time stage event streaming
//! - Bidirectional control (FluxForge → Engine commands)
//! - Automatic reconnection
//! - Multiple protocol support

pub mod connector;
pub mod protocol;
pub mod commands;

pub use connector::*;
pub use protocol::*;
pub use commands::*;
