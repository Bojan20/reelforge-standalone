//! Audio Formats Module
//!
//! Support for advanced audio formats:
//! - MQA (Master Quality Authenticated) - detection and core decode
//! - TrueHD/Atmos - detection and passthrough

pub mod mqa;
pub mod truehd;

pub use mqa::{MqaCoreDecoder, MqaDecodeChain, MqaDecodeStage, MqaDetector, MqaInfo, MqaRenderer};
pub use truehd::{AtmosPassthrough, MatWrapper, TrueHdHandler, TrueHdInfo, TrueHdMajorSync};
