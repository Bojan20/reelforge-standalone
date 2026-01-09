//! rf-file: Audio File I/O
//!
//! Provides import/export for various audio formats:
#![allow(dead_code)]
//! - WAV (via hound) - native, lossless
//! - FLAC (via symphonia) - compressed, lossless
//! - MP3 (via symphonia) - compressed, lossy
//! - OGG Vorbis (via symphonia) - compressed, lossy
//! - AAC (via symphonia) - compressed, lossy
//!
//! Also handles:
//! - Project files (.rfproj)
//! - Session files (.rfsession)
//! - Preset files (.rfpreset)
//! - Audio recording with disk streaming

mod audio_file;
mod bounce;
mod error;
mod project;
pub mod recording;

pub use audio_file::*;
pub use bounce::*;
pub use error::*;
pub use project::*;
pub use recording::*;
