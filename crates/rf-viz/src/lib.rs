//! rf-viz: GPU-Accelerated Visualizations for FluxForge Studio
//!
//! Provides wgpu-based rendering for:
//! - Waveform display (LOD, min/max/RMS)
//! - Spectrum analyzer (GPU FFT)
//! - 3D Spectrogram (waterfall, mountain view)
//! - EQ curve visualization (Pro-Q style)
//! - Meters and level displays
//! - GPU filter processing (compute shaders)
//! - Plugin browser (Phase 5.1)
//! - Plugin chain visualization (Phase 5.1)
//!
//! All renderers are designed for 60fps+ performance.

pub mod common;
pub mod eq_spectrum;
pub mod gpu_filter;
pub mod plugin_browser;
pub mod plugin_chain;
pub mod spectrogram;
pub mod stretch_overlay;
pub mod waveform;

pub use common::{GpuContext, VizError, VizResult};
pub use eq_spectrum::{
    BandHandle, CollisionZone, EqSpectrumConfig, EqSpectrumData, SpectrumVertex, db_to_y,
    frequency_to_x, generate_band_handles, generate_collision_zones, generate_curve_mesh,
    generate_grid, generate_piano_roll, generate_spectrum_mesh, x_to_frequency, y_to_db,
};
pub use gpu_filter::{
    GpuDynamicBand, GpuEqBuilder, GpuFilterParams, GpuFilterProcessor, GpuFilterState,
    GpuProcessConfig, GpuSaturationConfig, GpuStereoConfig, MAX_BUFFER_SIZE, MAX_GPU_BANDS,
    SaturationMode,
};
pub use plugin_browser::{
    BrowserLayout, BrowserVertex, BrowserViewMode, PluginBrowserConfig, PluginBrowserItem,
    PluginBrowserState, PluginCategoryFilter, PluginFormat, PluginValidationStatus, SortCriteria,
    format_color, status_color,
};
pub use plugin_chain::{
    ChainLayout, ChainSlotState, ChainVertex, PluginChainConfig, PluginChainState, cpu_color,
    latency_color, slot_color,
};
pub use spectrogram::{
    ColorMap, DisplayMode, FrequencyScale, SpectrogramConfig, SpectrogramData, SpectrogramFrame,
    SpectrogramVertex, WindowFunction, generate_3d_mesh,
};
pub use waveform::{WaveformConfig, WaveformData, WaveformRenderer};
