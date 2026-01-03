//! Visualization bridge for Flutter
//!
//! Provides FFT data and spectrum analysis for GPU rendering in Flutter.

use std::sync::Arc;
use parking_lot::RwLock;
use once_cell::sync::Lazy;

/// Shared FFT data buffer for spectrum visualization
static FFT_DATA: Lazy<Arc<RwLock<FftData>>> = Lazy::new(|| {
    Arc::new(RwLock::new(FftData::default()))
});

/// FFT magnitude data for spectrum analyzer
#[derive(Debug, Clone)]
pub struct FftData {
    /// Magnitude bins (linear, not dB)
    pub magnitudes: Vec<f32>,
    /// Peak hold values
    pub peaks: Vec<f32>,
    /// FFT size used
    pub fft_size: usize,
    /// Sample rate
    pub sample_rate: f32,
    /// Timestamp for animation sync
    pub timestamp: f64,
}

impl Default for FftData {
    fn default() -> Self {
        let fft_size = 4096;
        let bin_count = fft_size / 2 + 1;
        Self {
            magnitudes: vec![0.0; bin_count],
            peaks: vec![0.0; bin_count],
            fft_size,
            sample_rate: 48000.0,
            timestamp: 0.0,
        }
    }
}

/// Update FFT data from audio engine
pub fn update_fft_data(magnitudes: &[f32], sample_rate: f32, timestamp: f64) {
    let mut data = FFT_DATA.write();

    // Resize if needed
    if data.magnitudes.len() != magnitudes.len() {
        data.magnitudes.resize(magnitudes.len(), 0.0);
        data.peaks.resize(magnitudes.len(), 0.0);
        data.fft_size = (magnitudes.len() - 1) * 2;
    }

    // Update magnitudes with smoothing
    const ATTACK: f32 = 0.8;  // Fast attack
    const RELEASE: f32 = 0.95; // Slow release

    for (i, &mag) in magnitudes.iter().enumerate() {
        let old = data.magnitudes[i];
        if mag > old {
            data.magnitudes[i] = old + (mag - old) * ATTACK;
        } else {
            data.magnitudes[i] = old * RELEASE;
        }

        // Peak hold with decay
        if mag > data.peaks[i] {
            data.peaks[i] = mag;
        } else {
            data.peaks[i] *= 0.995; // Slow decay
        }
    }

    data.sample_rate = sample_rate;
    data.timestamp = timestamp;
}

/// Get current FFT data for rendering
#[flutter_rust_bridge::frb(sync)]
pub fn viz_get_fft_magnitudes() -> Vec<f32> {
    FFT_DATA.read().magnitudes.clone()
}

/// Get peak hold values
#[flutter_rust_bridge::frb(sync)]
pub fn viz_get_fft_peaks() -> Vec<f32> {
    FFT_DATA.read().peaks.clone()
}

/// Get FFT configuration
#[flutter_rust_bridge::frb(sync)]
pub fn viz_get_fft_config() -> (usize, f32) {
    let data = FFT_DATA.read();
    (data.fft_size, data.sample_rate)
}

/// Reset peak hold values
#[flutter_rust_bridge::frb(sync)]
pub fn viz_reset_peaks() {
    let mut data = FFT_DATA.write();
    data.peaks.fill(0.0);
}

/// Waveform data for display
#[derive(Debug, Clone, Default)]
pub struct WaveformData {
    /// Min values per display column
    pub min_values: Vec<f32>,
    /// Max values per display column
    pub max_values: Vec<f32>,
    /// RMS values per display column
    pub rms_values: Vec<f32>,
    /// Sample rate of source audio
    pub sample_rate: f32,
    /// Start sample position
    pub start_sample: u64,
    /// Samples per pixel
    pub samples_per_pixel: f64,
}

static WAVEFORM_DATA: Lazy<Arc<RwLock<WaveformData>>> = Lazy::new(|| {
    Arc::new(RwLock::new(WaveformData::default()))
});

/// Update waveform display data
pub fn update_waveform_data(
    min_values: Vec<f32>,
    max_values: Vec<f32>,
    rms_values: Vec<f32>,
    sample_rate: f32,
    start_sample: u64,
    samples_per_pixel: f64,
) {
    let mut data = WAVEFORM_DATA.write();
    data.min_values = min_values;
    data.max_values = max_values;
    data.rms_values = rms_values;
    data.sample_rate = sample_rate;
    data.start_sample = start_sample;
    data.samples_per_pixel = samples_per_pixel;
}

/// Get waveform min/max values for rendering
#[flutter_rust_bridge::frb(sync)]
pub fn viz_get_waveform() -> (Vec<f32>, Vec<f32>, Vec<f32>) {
    let data = WAVEFORM_DATA.read();
    (
        data.min_values.clone(),
        data.max_values.clone(),
        data.rms_values.clone(),
    )
}

/// Meter data for VU/PPM/LUFS meters
#[derive(Debug, Clone, Default)]
pub struct MeterData {
    /// Peak levels per channel (dB)
    pub peaks: Vec<f32>,
    /// RMS levels per channel (dB)
    pub rms: Vec<f32>,
    /// LUFS momentary
    pub lufs_m: f32,
    /// LUFS short-term
    pub lufs_s: f32,
    /// LUFS integrated
    pub lufs_i: f32,
    /// True peak (dB)
    pub true_peak: f32,
    /// Peak hold values
    pub peak_hold: Vec<f32>,
    /// Clip indicators
    pub clipping: Vec<bool>,
}

static METER_DATA: Lazy<Arc<RwLock<MeterData>>> = Lazy::new(|| {
    Arc::new(RwLock::new(MeterData::default()))
});

/// Update meter data
pub fn update_meter_data(
    peaks: Vec<f32>,
    rms: Vec<f32>,
    lufs_m: f32,
    lufs_s: f32,
    lufs_i: f32,
    true_peak: f32,
) {
    let mut data = METER_DATA.write();

    // Update clipping detection
    let clipping: Vec<bool> = peaks.iter().map(|&p| p > -0.1).collect();

    // Peak hold with decay
    if data.peak_hold.len() != peaks.len() {
        data.peak_hold.resize(peaks.len(), -100.0);
    }
    for (i, &peak) in peaks.iter().enumerate() {
        if peak > data.peak_hold[i] {
            data.peak_hold[i] = peak;
        } else {
            data.peak_hold[i] -= 0.05; // 50dB/sec decay
        }
    }

    data.peaks = peaks;
    data.rms = rms;
    data.lufs_m = lufs_m;
    data.lufs_s = lufs_s;
    data.lufs_i = lufs_i;
    data.true_peak = true_peak;
    data.clipping = clipping;
}

/// Get meter data for rendering
#[flutter_rust_bridge::frb(sync)]
pub fn viz_get_meters() -> (Vec<f32>, Vec<f32>, Vec<f32>, f32, f32, f32, f32) {
    let data = METER_DATA.read();
    (
        data.peaks.clone(),
        data.rms.clone(),
        data.peak_hold.clone(),
        data.lufs_m,
        data.lufs_s,
        data.lufs_i,
        data.true_peak,
    )
}

/// Check if any channel is clipping
#[flutter_rust_bridge::frb(sync)]
pub fn viz_is_clipping() -> bool {
    METER_DATA.read().clipping.iter().any(|&c| c)
}

/// Reset all meter peak holds and clip indicators
#[flutter_rust_bridge::frb(sync)]
pub fn viz_reset_meters() {
    let mut data = METER_DATA.write();
    data.peak_hold.fill(-100.0);
    data.clipping.fill(false);
}
