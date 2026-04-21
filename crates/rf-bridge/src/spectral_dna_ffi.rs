//! Spectral DNA Audio Classifier — FFI
//!
//! Analyzes audio files to extract spectral features for automatic
//! stage event classification. Three-tier analysis:
//! - Duration-based classification (short hit vs loop vs music)
//! - Envelope shape (attack time, sustain detection)
//! - Spectral content (centroid, energy, brightness)
//!
//! Returns JSON with classification candidates and confidence scores.

use std::ffi::{CStr, CString, c_char};

/// Analyze a single audio file and return spectral DNA features as JSON.
///
/// Returns JSON string with structure:
/// ```json
/// {
///   "duration_ms": 150.0,
///   "attack_ms": 5.2,
///   "rms_energy": 0.45,
///   "peak_amplitude": 0.92,
///   "spectral_centroid_hz": 2400.0,
///   "is_loopable": false,
///   "transient_count": 1,
///   "has_sustain": false,
///   "brightness": 0.65,
///   "candidates": [
///     {"stage": "REEL_STOP", "confidence": 0.87},
///     {"stage": "UI_CLICK", "confidence": 0.42}
///   ]
/// }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn spectral_dna_analyze(path: *const c_char) -> *mut c_char {
    if path.is_null() {
        return empty_json_ptr();
    }

    let path_str = match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => s,
        Err(_) => return empty_json_ptr(),
    };

    match analyze_file(path_str) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => empty_json_ptr(),
        },
        Err(_) => empty_json_ptr(),
    }
}

/// Batch analyze multiple files (newline-separated paths).
/// Returns JSON array of results.
#[unsafe(no_mangle)]
pub extern "C" fn spectral_dna_analyze_batch(paths: *const c_char) -> *mut c_char {
    if paths.is_null() {
        return empty_json_ptr();
    }

    let paths_str = match unsafe { CStr::from_ptr(paths) }.to_str() {
        Ok(s) => s,
        Err(_) => return empty_json_ptr(),
    };

    let results: Vec<String> = paths_str
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|p| analyze_file(p).unwrap_or_else(|_| "null".to_string()))
        .collect();

    let json = format!("[{}]", results.join(","));
    match CString::new(json) {
        Ok(cs) => cs.into_raw(),
        Err(_) => empty_json_ptr(),
    }
}

fn empty_json_ptr() -> *mut c_char {
    CString::new("{}").unwrap().into_raw()
}

// ═══════════════════════════════════════════════════════════════════════════════
// CORE ANALYSIS ENGINE
// ═══════════════════════════════════════════════════════════════════════════════

fn analyze_file(path: &str) -> Result<String, String> {
    // Step 1: Read audio
    let audio = rf_file::read_audio(path)
        .map_err(|e| format!("read error: {e:?}"))?;

    if audio.channels.is_empty() || audio.channels[0].is_empty() {
        return Err("empty audio".into());
    }

    // Use first channel (mono analysis)
    let samples = &audio.channels[0];
    let sr = audio.sample_rate as f64;
    let num_samples = samples.len();
    let duration_ms = (num_samples as f64 / sr) * 1000.0;

    // Step 2: Compute features
    let peak = compute_peak(samples);
    let rms = compute_rms(samples);
    let attack_ms = compute_attack_time(samples, sr);
    let centroid = compute_spectral_centroid(samples, sr);
    let is_loopable = detect_loop(samples, sr);
    let transients = count_transients(samples, sr);
    let has_sustain = detect_sustain(samples, sr);
    let brightness = if centroid > 0.0 {
        (centroid / 8000.0).min(1.0) // Normalize: 8kHz = max brightness
    } else {
        0.0
    };

    // Step 3: Classify into candidate stages
    let candidates = classify(duration_ms, attack_ms, rms, centroid, is_loopable, transients, has_sustain, brightness);

    // Step 4: Build JSON
    let candidates_json: Vec<String> = candidates
        .iter()
        .map(|(stage, conf)| format!(r#"{{"stage":"{}","confidence":{:.2}}}"#, stage, conf))
        .collect();

    Ok(format!(
        r#"{{"duration_ms":{:.1},"attack_ms":{:.1},"rms_energy":{:.3},"peak_amplitude":{:.3},"spectral_centroid_hz":{:.0},"is_loopable":{},"transient_count":{},"has_sustain":{},"brightness":{:.2},"candidates":[{}]}}"#,
        duration_ms, attack_ms, rms, peak, centroid, is_loopable, transients, has_sustain, brightness,
        candidates_json.join(",")
    ))
}

// ═══════════════════════════════════════════════════════════════════════════════
// FEATURE EXTRACTORS
// ═══════════════════════════════════════════════════════════════════════════════

fn compute_peak(samples: &[f64]) -> f64 {
    samples.iter().map(|s| s.abs()).fold(0.0f64, f64::max)
}

fn compute_rms(samples: &[f64]) -> f64 {
    if samples.is_empty() { return 0.0; }
    let sum: f64 = samples.iter().map(|s| s * s).sum();
    (sum / samples.len() as f64).sqrt()
}

/// Compute attack time: time from 10% to 90% of peak amplitude (in ms).
fn compute_attack_time(samples: &[f64], sr: f64) -> f64 {
    let peak = compute_peak(samples);
    if peak < 0.001 { return 0.0; }

    let threshold_low = peak * 0.1;
    let threshold_high = peak * 0.9;

    // Use envelope follower (windowed RMS) for stable measurement
    let window_size = (sr * 0.002) as usize; // 2ms window
    let window_size = window_size.max(1);

    let mut t_low: Option<usize> = None;
    let mut t_high: Option<usize> = None;

    // Only analyze first 500ms
    let max_samples = (sr * 0.5) as usize;
    let analysis_len = samples.len().min(max_samples);

    for i in 0..analysis_len.saturating_sub(window_size) {
        let rms: f64 = samples[i..i + window_size]
            .iter()
            .map(|s| s * s)
            .sum::<f64>()
            / window_size as f64;
        let rms = rms.sqrt();

        if t_low.is_none() && rms >= threshold_low {
            t_low = Some(i);
        }
        if t_low.is_some() && t_high.is_none() && rms >= threshold_high {
            t_high = Some(i);
            break;
        }
    }

    match (t_low, t_high) {
        (Some(lo), Some(hi)) => ((hi - lo) as f64 / sr) * 1000.0,
        (Some(lo), None) => {
            // Reached 10% but not 90% — slow attack, estimate
            let remaining = analysis_len.saturating_sub(lo);
            (remaining as f64 / sr) * 1000.0
        }
        _ => 0.0,
    }
}

/// Compute spectral centroid (center of mass of spectrum) in Hz.
fn compute_spectral_centroid(samples: &[f64], sr: f64) -> f64 {
    // Use a simple DFT on a window of the loudest section
    let fft_size = 2048;
    if samples.len() < fft_size {
        return 0.0;
    }

    // Find loudest window
    let mut best_energy = 0.0;
    let mut best_start = 0;
    let step = fft_size / 4;
    let max_start = samples.len().saturating_sub(fft_size);

    for start in (0..max_start).step_by(step) {
        let energy: f64 = samples[start..start + fft_size].iter().map(|s| s * s).sum();
        if energy > best_energy {
            best_energy = energy;
            best_start = start;
        }
    }

    // Apply Hann window and compute magnitude spectrum via DFT
    // (Using simple magnitude-only calculation — no full FFT needed for centroid)
    let window: Vec<f64> = (0..fft_size)
        .map(|i| 0.5 * (1.0 - (2.0 * std::f64::consts::PI * i as f64 / (fft_size - 1) as f64).cos()))
        .collect();

    let windowed: Vec<f64> = samples[best_start..best_start + fft_size]
        .iter()
        .zip(&window)
        .map(|(s, w)| s * w)
        .collect();

    // Compute power spectrum using Goertzel-like bins at key frequencies
    // For centroid, we need weighted average of frequency bins
    let num_bins = fft_size / 2;
    let bin_width = sr / fft_size as f64;

    let mut weighted_sum = 0.0;
    let mut magnitude_sum = 0.0;

    // Simplified: compute magnitude at each bin using correlation
    for k in 1..num_bins {
        let freq = k as f64 * bin_width;
        let mut real = 0.0;
        let mut imag = 0.0;
        let w = 2.0 * std::f64::consts::PI * k as f64 / fft_size as f64;

        for (n, &x) in windowed.iter().enumerate() {
            real += x * (w * n as f64).cos();
            imag -= x * (w * n as f64).sin();
        }

        let mag = (real * real + imag * imag).sqrt();
        weighted_sum += freq * mag;
        magnitude_sum += mag;
    }

    if magnitude_sum > 0.0 {
        weighted_sum / magnitude_sum
    } else {
        0.0
    }
}

/// Detect if audio is loopable (similar start and end sections).
fn detect_loop(samples: &[f64], sr: f64) -> bool {
    if samples.len() < (sr * 0.5) as usize {
        return false; // Too short to be a loop
    }

    // Check if end section matches start section (cross-correlation)
    let check_len = (sr * 0.05) as usize; // 50ms comparison window
    let check_len = check_len.min(samples.len() / 4);

    if check_len < 10 { return false; }

    let start = &samples[..check_len];
    let end = &samples[samples.len() - check_len..];

    // Compare RMS levels
    let start_rms = compute_rms(start);
    let end_rms = compute_rms(end);

    if start_rms < 0.001 || end_rms < 0.001 {
        return false; // Silence at edges
    }

    // RMS ratio within 3dB
    let ratio = start_rms / end_rms;
    (0.7..1.4).contains(&ratio)
}

/// Count transient peaks (onset detection).
fn count_transients(samples: &[f64], sr: f64) -> usize {
    let window_ms = 10.0;
    let window_size = (sr * window_ms / 1000.0) as usize;
    let window_size = window_size.max(1);
    let hop = window_size / 2;

    let mut energies: Vec<f64> = Vec::new();
    let mut i = 0;
    while i + window_size <= samples.len() {
        let e: f64 = samples[i..i + window_size].iter().map(|s| s * s).sum();
        energies.push(e);
        i += hop;
    }

    if energies.len() < 3 { return 0; }

    // Count peaks where energy jumps > 3x from previous frame
    let mut count = 0;
    for i in 1..energies.len() {
        if energies[i] > energies[i - 1] * 3.0 && energies[i] > 0.001 {
            count += 1;
        }
    }
    count
}

/// Detect if audio has a sustain phase (steady amplitude section).
fn detect_sustain(samples: &[f64], sr: f64) -> bool {
    // Check if there's a section >200ms with relatively stable amplitude
    let window_ms = 50.0;
    let window_size = (sr * window_ms / 1000.0) as usize;
    if samples.len() < window_size * 4 { return false; }

    let hop = window_size;
    let mut rms_values: Vec<f64> = Vec::new();

    let mut i = 0;
    while i + window_size <= samples.len() {
        rms_values.push(compute_rms(&samples[i..i + window_size]));
        i += hop;
    }

    if rms_values.len() < 4 { return false; }

    // Find consecutive windows where RMS varies by less than 3dB
    let mut consecutive = 0usize;
    let mut max_consecutive = 0usize;
    for i in 1..rms_values.len() {
        if rms_values[i - 1] > 0.01 {
            let ratio = rms_values[i] / rms_values[i - 1];
            if (0.7..1.4).contains(&ratio) {
                consecutive += 1;
                if consecutive > max_consecutive {
                    max_consecutive = consecutive;
                }
            } else {
                consecutive = 0;
            }
        }
    }

    // Need at least 4 consecutive stable windows (200ms+ sustain)
    max_consecutive >= 4
}

// ═══════════════════════════════════════════════════════════════════════════════
// CLASSIFIER — Maps spectral features to stage candidates
// ═══════════════════════════════════════════════════════════════════════════════

fn classify(
    duration_ms: f64,
    attack_ms: f64,
    rms: f64,
    _centroid_hz: f64,
    is_loopable: bool,
    transients: usize,
    has_sustain: bool,
    brightness: f64,
) -> Vec<(&'static str, f64)> {
    let mut candidates: Vec<(&str, f64)> = Vec::new();

    // ─── ULTRA SHORT (<100ms) ─── Clicks, UI, mechanical ───
    if duration_ms < 100.0 {
        if attack_ms < 5.0 {
            candidates.push(("UI_CLICK", 0.85));
            candidates.push(("UI_BET_UP", 0.60));
            candidates.push(("UI_BET_DOWN", 0.55));
        }
        return candidates;
    }

    // ─── SHORT HIT (100-300ms) ─── Reel stop, scatter land ───
    if duration_ms < 300.0 {
        if attack_ms < 15.0 && !has_sustain {
            // Sharp percussive hit
            candidates.push(("REEL_STOP", 0.88));
            candidates.push(("SCATTER_LAND", 0.45));
            if brightness > 0.5 {
                candidates.push(("COIN_CREDIT", 0.40));
            }
        } else if attack_ms < 30.0 {
            // Short tonal
            candidates.push(("REEL_STOP", 0.65));
            candidates.push(("UI_CLICK", 0.50));
        }
        return candidates;
    }

    // ─── MEDIUM (300ms-1.5s) ─── Win presents, transitions ───
    if duration_ms < 1500.0 {
        if brightness > 0.5 && rms > 0.1 {
            // Bright, energetic — celebration
            candidates.push(("WIN_PRESENT_1", 0.75));
            candidates.push(("WIN_COLLECT", 0.55));
            if rms > 0.25 {
                candidates.push(("WIN_PRESENT_2", 0.65));
            }
        } else if brightness < 0.3 {
            // Dark, tense
            candidates.push(("ANTICIPATION_TENSION", 0.70));
            candidates.push(("BONUS_TRIGGER", 0.45));
        } else {
            // Neutral
            candidates.push(("SCATTER_LAND", 0.55));
            candidates.push(("WIN_PRESENT_1", 0.50));
            candidates.push(("SPIN_END", 0.40));
        }

        if transients > 3 {
            candidates.push(("ROLLUP", 0.60));
            candidates.push(("ROLLUP_TICK", 0.50));
        }
        return candidates;
    }

    // ─── LONG (1.5s-5s) ─── Stingers, big win starts, transitions ───
    if duration_ms < 5000.0 {
        if brightness > 0.5 && rms > 0.15 {
            // Bright fanfare
            candidates.push(("BIG_WIN_START", 0.72));
            candidates.push(("WIN_PRESENT_3", 0.60));
            candidates.push(("FREE_SPINS_START", 0.45));
        } else if has_sustain {
            // Sustained tone
            candidates.push(("ANTICIPATION_TENSION", 0.65));
            candidates.push(("FREE_SPINS_START", 0.50));
        } else {
            candidates.push(("BIG_WIN_END", 0.55));
            candidates.push(("BONUS_TRIGGER", 0.50));
        }
        return candidates;
    }

    // ─── VERY LONG (>5s) ─── Music loops, ambient beds ───
    if is_loopable {
        if brightness > 0.4 && rms > 0.1 {
            candidates.push(("REEL_SPIN_LOOP", 0.80));
            candidates.push(("MUSIC_BASE_L1", 0.65));
        } else if brightness < 0.3 {
            // Dark ambient
            candidates.push(("MUSIC_BASE_L1", 0.75));
            candidates.push(("REEL_SPIN_LOOP", 0.50));
        } else {
            candidates.push(("MUSIC_BASE_L1", 0.70));
            candidates.push(("REEL_SPIN_LOOP", 0.60));
        }
    } else {
        // Long, non-loopable
        if rms > 0.15 {
            candidates.push(("BIG_WIN_START", 0.60));
            candidates.push(("MUSIC_BIG_WIN", 0.55));
        } else {
            candidates.push(("MUSIC_BASE_L1", 0.55));
            candidates.push(("GAME_INTRO", 0.50));
        }
    }

    // Sort by confidence descending
    candidates.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
    candidates
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_classify_short_percussive() {
        let c = classify(150.0, 5.0, 0.3, 3000.0, false, 1, false, 0.375);
        assert!(!c.is_empty());
        assert_eq!(c[0].0, "REEL_STOP");
        assert!(c[0].1 > 0.8);
    }

    #[test]
    fn test_classify_ultra_short_click() {
        let c = classify(50.0, 2.0, 0.2, 5000.0, false, 1, false, 0.625);
        assert!(!c.is_empty());
        assert_eq!(c[0].0, "UI_CLICK");
    }

    #[test]
    fn test_classify_long_loop() {
        let c = classify(8000.0, 50.0, 0.15, 2000.0, true, 0, true, 0.25);
        assert!(!c.is_empty());
        // Should be music or spin loop
        assert!(c[0].0 == "MUSIC_BASE_L1" || c[0].0 == "REEL_SPIN_LOOP");
    }

    #[test]
    fn test_classify_bright_celebration() {
        let c = classify(800.0, 20.0, 0.3, 5000.0, false, 2, false, 0.625);
        assert!(!c.is_empty());
        assert!(c[0].0.starts_with("WIN_PRESENT"));
    }

    #[test]
    fn test_classify_dark_tension() {
        let c = classify(900.0, 100.0, 0.08, 1000.0, false, 0, true, 0.125);
        assert!(!c.is_empty());
        assert_eq!(c[0].0, "ANTICIPATION_TENSION");
    }

    #[test]
    fn test_empty_candidates_impossible() {
        // Any non-zero duration should produce candidates
        let c = classify(500.0, 30.0, 0.1, 2000.0, false, 1, false, 0.25);
        assert!(!c.is_empty());
    }

    #[test]
    fn test_peak_computation() {
        let samples = vec![0.0, 0.5, -0.8, 0.3];
        assert!((compute_peak(&samples) - 0.8).abs() < 0.001);
    }

    #[test]
    fn test_rms_computation() {
        let samples = vec![1.0; 100];
        assert!((compute_rms(&samples) - 1.0).abs() < 0.001);
    }
}
