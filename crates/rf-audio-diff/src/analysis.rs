//! Audio analysis combining time and frequency domain

use crate::config::DiffConfig;
use crate::loader::AudioData;
use crate::metrics::*;
use crate::spectral::{a_weight, spectral_centroid, spectral_flatness, to_db, SpectralAnalyzer};
use crate::Result;
use rayon::prelude::*;

/// Complete audio analysis
#[derive(Debug, Clone)]
pub struct AudioAnalysis {
    /// Analyzed audio data
    pub audio: AudioData,

    /// Peak level per channel
    pub peak_levels: Vec<f64>,

    /// RMS level per channel
    pub rms_levels: Vec<f64>,

    /// Peak level in dB
    pub peak_db: f64,

    /// RMS level in dB
    pub rms_db: f64,

    /// Average spectral centroid (Hz)
    pub avg_centroid: f64,

    /// Average spectral flatness (0-1)
    pub avg_flatness: f64,

    /// DC offset per channel
    pub dc_offset: Vec<f64>,

    /// Crest factor (peak/RMS)
    pub crest_factor: f64,
}

impl AudioAnalysis {
    /// Analyze audio data
    pub fn new(audio: AudioData, config: &DiffConfig) -> Result<Self> {
        let peak_levels: Vec<f64> = audio.channels.iter()
            .map(|ch| ch.iter().map(|s| s.abs()).fold(0.0, f64::max))
            .collect();

        let rms_levels: Vec<f64> = audio.channels.iter()
            .map(|ch| {
                let sum_sq: f64 = ch.iter().map(|s| s * s).sum();
                (sum_sq / ch.len() as f64).sqrt()
            })
            .collect();

        let dc_offset: Vec<f64> = audio.channels.iter()
            .map(|ch| ch.iter().sum::<f64>() / ch.len() as f64)
            .collect();

        let peak = peak_levels.iter().copied().fold(0.0, f64::max);
        let rms = rms_levels.iter().copied().fold(0.0, f64::max);

        let peak_db = to_db(peak);
        let rms_db = to_db(rms);

        let crest_factor = if rms > 0.0 { peak / rms } else { 0.0 };

        // Spectral analysis on mono mix
        let mono = audio.to_mono();
        let analyzer = SpectralAnalyzer::new(config.fft_size, config.hop_size, audio.sample_rate)?;
        let frames = analyzer.analyze(&mono);

        let avg_centroid = if !frames.is_empty() {
            frames.iter().map(spectral_centroid).sum::<f64>() / frames.len() as f64
        } else {
            0.0
        };

        let avg_flatness = if !frames.is_empty() {
            frames.iter().map(spectral_flatness).sum::<f64>() / frames.len() as f64
        } else {
            0.0
        };

        Ok(Self {
            audio,
            peak_levels,
            rms_levels,
            peak_db,
            rms_db,
            avg_centroid,
            avg_flatness,
            dc_offset,
            crest_factor,
        })
    }
}

/// Compare two audio analyses and compute metrics
pub fn compute_comparison_metrics(
    reference: &AudioAnalysis,
    test: &AudioAnalysis,
    config: &DiffConfig,
) -> Result<ComparisonMetrics> {
    let sample_rate = reference.audio.sample_rate;

    // Time-domain metrics (per channel, then averaged)
    let time_metrics = compute_time_domain_metrics(reference, test, config);

    // Spectral metrics
    let spectral_metrics = compute_spectral_metrics(reference, test, config)?;

    // Perceptual metrics
    let perceptual_metrics = compute_perceptual_metrics(reference, test, config)?;

    // Correlation metrics
    let correlation_metrics = compute_correlation_metrics(reference, test);

    let duration_diff = reference.audio.duration - test.audio.duration;

    Ok(ComparisonMetrics {
        time_domain: time_metrics,
        spectral: spectral_metrics,
        perceptual: perceptual_metrics,
        correlation: correlation_metrics,
        duration_diff,
        sample_rate,
        num_channels: reference.audio.num_channels,
    })
}

fn compute_time_domain_metrics(
    reference: &AudioAnalysis,
    test: &AudioAnalysis,
    config: &DiffConfig,
) -> TimeDomainMetrics {
    if config.compare_mono {
        let ref_mono = reference.audio.to_mono();
        let test_mono = test.audio.to_mono();
        TimeDomainMetrics::calculate(&ref_mono, &test_mono)
    } else {
        // Per-channel analysis, then aggregate
        let channel_metrics: Vec<TimeDomainMetrics> = reference.audio.channels.iter()
            .zip(test.audio.channels.iter())
            .map(|(ref_ch, test_ch)| TimeDomainMetrics::calculate(ref_ch, test_ch))
            .collect();

        if channel_metrics.is_empty() {
            return TimeDomainMetrics::calculate(&[], &[]);
        }

        // Aggregate: max of peaks, RMS of RMS values
        let peak_diff = channel_metrics.iter().map(|m| m.peak_diff).fold(0.0, f64::max);
        let peak_diff_sample = channel_metrics.iter()
            .max_by(|a, b| a.peak_diff.partial_cmp(&b.peak_diff).unwrap())
            .map(|m| m.peak_diff_sample)
            .unwrap_or(0);

        let rms_sum_sq: f64 = channel_metrics.iter().map(|m| m.rms_diff * m.rms_diff).sum();
        let rms_diff = (rms_sum_sq / channel_metrics.len() as f64).sqrt();

        let mean_abs_diff = channel_metrics.iter().map(|m| m.mean_abs_diff).sum::<f64>()
            / channel_metrics.len() as f64;

        TimeDomainMetrics {
            peak_diff,
            rms_diff,
            mean_abs_diff,
            peak_diff_sample,
            peak_diff_db: to_db(peak_diff),
            rms_diff_db: to_db(rms_diff),
        }
    }
}

fn compute_spectral_metrics(
    reference: &AudioAnalysis,
    test: &AudioAnalysis,
    config: &DiffConfig,
) -> Result<SpectralMetrics> {
    let sample_rate = reference.audio.sample_rate;
    let analyzer = SpectralAnalyzer::new(config.fft_size, config.hop_size, sample_rate)?;

    let ref_mono = reference.audio.to_mono();
    let test_mono = test.audio.to_mono();

    let ref_frames = analyzer.analyze(&ref_mono);
    let test_frames = analyzer.analyze(&test_mono);

    let num_frames = ref_frames.len().min(test_frames.len());
    if num_frames == 0 {
        return Ok(SpectralMetrics::zero(config.num_bands));
    }

    // Frequency range bins
    let min_bin = analyzer.freq_to_bin(config.freq_range.0);
    let max_bin = analyzer.freq_to_bin(config.freq_range.1);

    // Per-frame spectral comparison (parallel)
    let frame_diffs: Vec<(f64, f64, f64, f64, usize)> = (0..num_frames)
        .into_par_iter()
        .map(|i| {
            let ref_frame = &ref_frames[i];
            let test_frame = &test_frames[i];

            let mut sum_diff_db = 0.0;
            let mut max_diff_db = 0.0;
            let mut max_diff_bin = 0;
            let mut sum_phase_diff = 0.0;
            let mut count = 0;

            for bin in min_bin..=max_bin.min(ref_frame.magnitude.len() - 1) {
                let ref_mag = ref_frame.magnitude[bin];
                let test_mag = test_frame.magnitude[bin];

                // Skip below noise floor
                if ref_mag < 1e-10 && test_mag < 1e-10 {
                    continue;
                }

                let ref_db = to_db(ref_mag.max(1e-10));
                let test_db = to_db(test_mag.max(1e-10));

                if ref_db < config.noise_floor_db && test_db < config.noise_floor_db {
                    continue;
                }

                let mut diff_db = (ref_db - test_db).abs();

                // A-weighting
                if config.use_a_weighting {
                    let freq = analyzer.bin_to_freq(bin);
                    let weight = a_weight(freq);
                    diff_db *= weight;
                }

                sum_diff_db += diff_db;
                if diff_db > max_diff_db {
                    max_diff_db = diff_db;
                    max_diff_bin = bin;
                }

                // Phase difference (wrapped to -π to π)
                let phase_diff = (ref_frame.phase[bin] - test_frame.phase[bin])
                    .sin().atan2((ref_frame.phase[bin] - test_frame.phase[bin]).cos())
                    .abs();
                sum_phase_diff += phase_diff;

                count += 1;
            }

            let avg_diff = if count > 0 { sum_diff_db / count as f64 } else { 0.0 };
            let avg_phase = if count > 0 { sum_phase_diff / count as f64 } else { 0.0 };

            (avg_diff, max_diff_db, avg_phase, analyzer.bin_to_freq(max_diff_bin), max_diff_bin)
        })
        .collect();

    // Aggregate across frames
    let avg_spectral_diff_db = frame_diffs.iter().map(|(avg, _, _, _, _)| avg).sum::<f64>()
        / num_frames as f64;
    let (_, max_spectral_diff_db, _, max_diff_freq, _) = frame_diffs.iter()
        .max_by(|(_, a, _, _, _), (_, b, _, _, _)| a.partial_cmp(b).unwrap())
        .copied()
        .unwrap_or((0.0, 0.0, 0.0, 0.0, 0));
    let avg_phase_diff = frame_diffs.iter().map(|(_, _, phase, _, _)| phase).sum::<f64>()
        / num_frames as f64;
    let max_phase_diff = frame_diffs.iter().map(|(_, _, phase, _, _)| *phase).fold(0.0, f64::max);

    // Spectral correlation
    let spectral_correlation = compute_spectral_correlation(&ref_frames, &test_frames, min_bin, max_bin);

    // Band-by-band analysis
    let (band_diffs_db, band_centers) = compute_band_diffs(
        &ref_frames, &test_frames,
        config.num_bands, sample_rate, config,
    );

    Ok(SpectralMetrics {
        avg_spectral_diff_db,
        max_spectral_diff_db,
        max_diff_freq,
        avg_phase_diff,
        max_phase_diff,
        spectral_correlation,
        band_diffs_db,
        band_centers,
    })
}

fn compute_spectral_correlation(
    ref_frames: &[crate::spectral::SpectralFrame],
    test_frames: &[crate::spectral::SpectralFrame],
    min_bin: usize,
    max_bin: usize,
) -> f64 {
    let num_frames = ref_frames.len().min(test_frames.len());
    if num_frames == 0 {
        return 1.0;
    }

    let mut sum_corr = 0.0;
    for i in 0..num_frames {
        let ref_frame = &ref_frames[i];
        let test_frame = &test_frames[i];

        let ref_slice: Vec<f64> = (min_bin..=max_bin.min(ref_frame.power.len() - 1))
            .map(|b| ref_frame.power[b])
            .collect();
        let test_slice: Vec<f64> = (min_bin..=max_bin.min(test_frame.power.len() - 1))
            .map(|b| test_frame.power[b])
            .collect();

        let corr = CorrelationMetrics::calculate(&ref_slice, &test_slice);
        sum_corr += corr.pearson;
    }

    sum_corr / num_frames as f64
}

fn compute_band_diffs(
    ref_frames: &[crate::spectral::SpectralFrame],
    test_frames: &[crate::spectral::SpectralFrame],
    num_bands: usize,
    sample_rate: u32,
    config: &DiffConfig,
) -> (Vec<f64>, Vec<f64>) {
    let num_frames = ref_frames.len().min(test_frames.len());
    if num_frames == 0 || ref_frames[0].magnitude.is_empty() {
        return (vec![0.0; num_bands], vec![0.0; num_bands]);
    }

    let freq_resolution = ref_frames[0].freq_resolution;
    let num_bins = ref_frames[0].magnitude.len();

    // Logarithmic band distribution
    let min_freq = config.freq_range.0.max(20.0);
    let max_freq = config.freq_range.1.min(sample_rate as f64 / 2.0);

    let band_edges: Vec<f64> = (0..=num_bands)
        .map(|i| min_freq * (max_freq / min_freq).powf(i as f64 / num_bands as f64))
        .collect();

    let band_centers: Vec<f64> = (0..num_bands)
        .map(|i| (band_edges[i] * band_edges[i + 1]).sqrt())
        .collect();

    let mut band_diffs = vec![0.0; num_bands];

    for frame_idx in 0..num_frames {
        let ref_frame = &ref_frames[frame_idx];
        let test_frame = &test_frames[frame_idx];

        for (band_idx, (low, high)) in band_edges.iter().zip(band_edges.iter().skip(1)).enumerate() {
            let low_bin = (*low / freq_resolution).floor() as usize;
            let high_bin = ((*high / freq_resolution).ceil() as usize).min(num_bins - 1);

            let mut ref_power = 0.0;
            let mut test_power = 0.0;

            for bin in low_bin..=high_bin {
                ref_power += ref_frame.power.get(bin).copied().unwrap_or(0.0);
                test_power += test_frame.power.get(bin).copied().unwrap_or(0.0);
            }

            let ref_db = to_db(ref_power.sqrt().max(1e-10));
            let test_db = to_db(test_power.sqrt().max(1e-10));

            band_diffs[band_idx] += (ref_db - test_db).abs();
        }
    }

    // Average across frames
    for diff in &mut band_diffs {
        *diff /= num_frames as f64;
    }

    (band_diffs, band_centers)
}

fn compute_perceptual_metrics(
    reference: &AudioAnalysis,
    test: &AudioAnalysis,
    config: &DiffConfig,
) -> Result<PerceptualMetrics> {
    let sample_rate = reference.audio.sample_rate;
    let analyzer = SpectralAnalyzer::new(config.fft_size, config.hop_size, sample_rate)?;

    let ref_mono = reference.audio.to_mono();
    let test_mono = test.audio.to_mono();

    let ref_frames = analyzer.analyze(&ref_mono);
    let test_frames = analyzer.analyze(&test_mono);

    let num_frames = ref_frames.len().min(test_frames.len());

    // A-weighted RMS difference
    let mut a_weighted_diff_sq = 0.0;
    let mut total_samples = 0;

    for i in 0..num_frames {
        let ref_frame = &ref_frames[i];
        let test_frame = &test_frames[i];

        for bin in 0..ref_frame.magnitude.len().min(test_frame.magnitude.len()) {
            let freq = analyzer.bin_to_freq(bin);
            if freq < config.freq_range.0 || freq > config.freq_range.1 {
                continue;
            }

            let weight = a_weight(freq);
            let diff = (ref_frame.magnitude[bin] - test_frame.magnitude[bin]) * weight;
            a_weighted_diff_sq += diff * diff;
            total_samples += 1;
        }
    }

    let a_weighted_rms_diff = if total_samples > 0 {
        (a_weighted_diff_sq / total_samples as f64).sqrt()
    } else {
        0.0
    };

    // Centroid difference
    let centroid_diff_hz = (reference.avg_centroid - test.avg_centroid).abs();

    // Flatness difference
    let flatness_diff = (reference.avg_flatness - test.avg_flatness).abs();

    // Simplified loudness difference (using RMS as proxy)
    let loudness_diff_lufs = reference.rms_db - test.rms_db;

    Ok(PerceptualMetrics {
        a_weighted_rms_diff,
        a_weighted_rms_diff_db: to_db(a_weighted_rms_diff),
        loudness_diff_lufs,
        centroid_diff_hz,
        flatness_diff,
    })
}

fn compute_correlation_metrics(
    reference: &AudioAnalysis,
    test: &AudioAnalysis,
) -> CorrelationMetrics {
    let ref_mono = reference.audio.to_mono();
    let test_mono = test.audio.to_mono();
    CorrelationMetrics::calculate(&ref_mono, &test_mono)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_test_audio(samples: Vec<f64>) -> AudioData {
        let len = samples.len();
        AudioData {
            channels: vec![samples],
            sample_rate: 44100,
            num_channels: 1,
            num_samples: len,
            duration: len as f64 / 44100.0,
            source_path: "test.wav".into(),
        }
    }

    #[test]
    fn test_identical_audio() {
        let samples: Vec<f64> = (0..4096)
            .map(|i| (2.0 * std::f64::consts::PI * 440.0 * i as f64 / 44100.0).sin())
            .collect();

        let audio = make_test_audio(samples);
        let config = DiffConfig::default();

        let analysis1 = AudioAnalysis::new(audio.clone(), &config).unwrap();
        let analysis2 = AudioAnalysis::new(audio, &config).unwrap();

        let metrics = compute_comparison_metrics(&analysis1, &analysis2, &config).unwrap();

        assert!(metrics.time_domain.peak_diff < 1e-10);
        assert!(metrics.time_domain.rms_diff < 1e-10);
        assert!((metrics.correlation.pearson - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_audio_analysis() {
        let samples: Vec<f64> = (0..4096)
            .map(|i| 0.5 * (2.0 * std::f64::consts::PI * 1000.0 * i as f64 / 44100.0).sin())
            .collect();

        let audio = make_test_audio(samples);
        let config = DiffConfig::default();
        let analysis = AudioAnalysis::new(audio, &config).unwrap();

        assert!((analysis.peak_levels[0] - 0.5).abs() < 0.01);
        assert!(analysis.avg_centroid > 900.0 && analysis.avg_centroid < 1100.0);
    }
}
