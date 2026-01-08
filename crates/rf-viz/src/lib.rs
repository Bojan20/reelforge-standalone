//! rf-viz: GPU-Accelerated Visualizations for ReelForge
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

pub mod waveform;
pub mod common;
pub mod spectrogram;
pub mod eq_spectrum;
pub mod gpu_filter;
pub mod plugin_browser;
pub mod plugin_chain;
pub mod stretch_overlay;

pub use waveform::{WaveformRenderer, WaveformData, WaveformConfig};
pub use common::{GpuContext, VizError, VizResult};
pub use spectrogram::{
    SpectrogramConfig,
    SpectrogramData,
    SpectrogramFrame,
    SpectrogramVertex,
    ColorMap,
    FrequencyScale,
    DisplayMode,
    WindowFunction,
    generate_3d_mesh,
};
pub use eq_spectrum::{
    EqSpectrumConfig,
    EqSpectrumData,
    BandHandle,
    CollisionZone,
    SpectrumVertex,
    generate_spectrum_mesh,
    generate_curve_mesh,
    generate_band_handles,
    generate_grid,
    generate_piano_roll,
    generate_collision_zones,
    x_to_frequency,
    frequency_to_x,
    y_to_db,
    db_to_y,
};
pub use gpu_filter::{
    GpuFilterProcessor,
    GpuFilterParams,
    GpuFilterState,
    GpuProcessConfig,
    GpuStereoConfig,
    GpuSaturationConfig,
    GpuDynamicBand,
    GpuEqBuilder,
    SaturationMode,
    MAX_GPU_BANDS,
    MAX_BUFFER_SIZE,
};
pub use plugin_browser::{
    PluginBrowserConfig,
    PluginBrowserState,
    PluginBrowserItem,
    BrowserViewMode,
    SortCriteria,
    PluginCategoryFilter,
    PluginFormat,
    PluginValidationStatus,
    BrowserLayout,
    BrowserVertex,
    format_color,
    status_color,
};
pub use plugin_chain::{
    PluginChainConfig,
    PluginChainState,
    ChainSlotState,
    ChainLayout,
    ChainVertex,
    slot_color,
    latency_color,
    cpu_color,
};
