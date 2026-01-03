//! rf-plugin: ReelForge Plugin Wrapper
//!
//! Provides VST3/CLAP plugin exports using nih-plug framework.
//!
//! ## Plugins
//! - `ReelForgeEQ` - 64-band parametric EQ
//! - `ReelForgeDynamics` - Compressor/Limiter/Gate
//! - `ReelForgeChannel` - Complete channel strip

mod eq_plugin;
mod dynamics_plugin;
mod channel_plugin;
mod params;

pub use eq_plugin::ReelForgeEQ;
pub use dynamics_plugin::ReelForgeDynamics;
pub use channel_plugin::ReelForgeChannel;

// Export plugins for VST3/CLAP
nih_plug::nih_export_vst3!(ReelForgeEQ);
nih_plug::nih_export_clap!(
    ReelForgeEQ,
    ReelForgeDynamics,
    ReelForgeChannel
);
