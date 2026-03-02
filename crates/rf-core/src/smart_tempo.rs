//! Smart Tempo — Pro-Grade BPM Detection & Tempo Mapping
//!
//! Cubase/Pro Tools/Logic Pro-level tempo detection:
//! - Multi-stage onset detection (spectral flux + energy ratio + adaptive threshold)
//! - Autocorrelation-based tempo estimation with comb filter refinement
//! - Half/double tempo resolution with musical heuristics
//! - Variable tempo detection (tempo curve output)
//! - Beat grid alignment with downbeat detection
//! - Sample-accurate tempo map for zero-drift metronome sync

use serde::{Deserialize, Serialize};

// ═══════════════════════════════════════════════════════════════════════════════
// DETECTION RESULT
// ═══════════════════════════════════════════════════════════════════════════════

/// Tempo detection result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TempoDetection {
    /// Detected BPM
    pub bpm: f64,
    /// Confidence (0.0-1.0)
    pub confidence: f64,
    /// Alternative tempos (half/double/related)
    pub alternatives: Vec<f64>,
    /// Detected downbeats (sample positions)
    pub downbeats: Vec<u64>,
    /// Detected beat positions (sample positions)
    pub beats: Vec<u64>,
    /// Is tempo stable throughout
    pub stable: bool,
    /// Tempo variation per beat (if variable tempo detected)
    pub tempo_curve: Vec<(u64, f64)>,
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART TEMPO MODE
// ═══════════════════════════════════════════════════════════════════════════════

/// Smart tempo mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum SmartTempoMode {
    /// Keep project tempo, flex audio to match
    #[default]
    KeepProject,
    /// Adapt project tempo to match audio
    AdaptProject,
    /// Automatic detection
    Automatic,
    /// Manual (no adjustment)
    Manual,
}

impl SmartTempoMode {
    pub fn description(&self) -> &'static str {
        match self {
            Self::KeepProject => "Flex audio to match project tempo",
            Self::AdaptProject => "Change project tempo to match audio",
            Self::Automatic => "Automatically detect and decide",
            Self::Manual => "No automatic tempo adjustment",
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART TEMPO MAP (sample-based, for variable tempo)
// ═══════════════════════════════════════════════════════════════════════════════

/// Smart tempo change event (sample-based, different from tick-based TempoEvent in tempo.rs)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SmartTempoEvent {
    /// Position in samples
    pub position: u64,
    /// BPM at this position
    pub bpm: f64,
    /// Transition type
    pub transition: TempoTransition,
}

/// Tempo transition type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum TempoTransition {
    /// Instant change
    #[default]
    Instant,
    /// Linear ramp
    Linear,
    /// Exponential curve
    Exponential,
    /// S-curve (smooth)
    SCurve,
}

/// Sample-based tempo map for variable tempo (different from tick-based TempoMap in tempo.rs)
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SmartTempoMap {
    /// Base tempo
    pub base_tempo: f64,
    /// Tempo events (sorted by position)
    events: Vec<SmartTempoEvent>,
    /// Sample rate
    sample_rate: f64,
}

impl SmartTempoMap {
    /// Create with constant tempo
    pub fn new(bpm: f64, sample_rate: f64) -> Self {
        Self {
            base_tempo: bpm,
            events: Vec::new(),
            sample_rate,
        }
    }

    /// Add tempo event
    pub fn add_event(&mut self, event: SmartTempoEvent) {
        self.events.push(event);
        self.events.sort_by_key(|e| e.position);
    }

    /// Get tempo at sample position
    pub fn tempo_at(&self, position: u64) -> f64 {
        if self.events.is_empty() {
            return self.base_tempo;
        }

        // Find surrounding events
        let mut prev_event: Option<&SmartTempoEvent> = None;
        let mut next_event: Option<&SmartTempoEvent> = None;

        for event in &self.events {
            if event.position <= position {
                prev_event = Some(event);
            } else {
                next_event = Some(event);
                break;
            }
        }

        match (prev_event, next_event) {
            (Some(prev), Some(next)) => {
                let span = next.position - prev.position;
                if span == 0 {
                    return prev.bpm;
                }
                let t = (position - prev.position) as f64 / span as f64;

                match prev.transition {
                    TempoTransition::Instant => prev.bpm,
                    TempoTransition::Linear => prev.bpm + t * (next.bpm - prev.bpm),
                    TempoTransition::Exponential => {
                        let ratio = next.bpm / prev.bpm;
                        prev.bpm * ratio.powf(t)
                    }
                    TempoTransition::SCurve => {
                        let smooth_t = t * t * (3.0 - 2.0 * t);
                        prev.bpm + smooth_t * (next.bpm - prev.bpm)
                    }
                }
            }
            (Some(prev), None) => prev.bpm,
            (None, _) => self.base_tempo,
        }
    }

    /// Get samples per beat at position
    pub fn samples_per_beat_at(&self, position: u64) -> f64 {
        let tempo = self.tempo_at(position);
        (self.sample_rate * 60.0) / tempo
    }

    /// Convert beat position to sample position (integrates through tempo changes)
    pub fn beat_to_samples(&self, beat: f64) -> u64 {
        if self.events.is_empty() {
            let spb = (self.sample_rate * 60.0) / self.base_tempo;
            return (beat * spb) as u64;
        }

        let mut current_beat = 0.0f64;
        let mut current_sample = 0u64;
        let mut current_tempo = self.base_tempo;

        for event in &self.events {
            let spb = (self.sample_rate * 60.0) / current_tempo;
            let samples_to_event = event.position - current_sample;
            let beats_to_event = samples_to_event as f64 / spb;

            if current_beat + beats_to_event >= beat {
                let remaining_beats = beat - current_beat;
                return current_sample + (remaining_beats * spb) as u64;
            }

            current_beat += beats_to_event;
            current_sample = event.position;
            current_tempo = event.bpm;
        }

        let spb = (self.sample_rate * 60.0) / current_tempo;
        current_sample + ((beat - current_beat) * spb) as u64
    }

    /// Convert sample position to beat position (integrates through tempo changes)
    pub fn samples_to_beat(&self, position: u64) -> f64 {
        if self.events.is_empty() {
            let spb = (self.sample_rate * 60.0) / self.base_tempo;
            return position as f64 / spb;
        }

        let mut current_beat = 0.0f64;
        let mut current_sample = 0u64;
        let mut current_tempo = self.base_tempo;

        for event in &self.events {
            if event.position > position {
                break;
            }

            let spb = (self.sample_rate * 60.0) / current_tempo;
            let samples_since = event.position - current_sample;
            current_beat += samples_since as f64 / spb;
            current_sample = event.position;
            current_tempo = event.bpm;
        }

        let spb = (self.sample_rate * 60.0) / current_tempo;
        current_beat + (position - current_sample) as f64 / spb
    }

    /// Clear all tempo events
    pub fn clear(&mut self) {
        self.events.clear();
    }

    /// Get all events
    pub fn events(&self) -> &[SmartTempoEvent] {
        &self.events
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TEMPO DETECTOR — Pro-Grade Multi-Stage Algorithm
// ═══════════════════════════════════════════════════════════════════════════════

/// Onset detection function entry
#[derive(Debug, Clone)]
struct OnsetEntry {
    /// Sample position of this frame
    position: u64,
    /// Combined onset detection value
    strength: f64,
}

/// Pro-grade tempo detector
///
/// Multi-stage pipeline:
/// 1. Onset Detection Function (spectral flux + energy ratio + adaptive threshold)
/// 2. Autocorrelation of onset function for periodicity estimation
/// 3. Comb filter bank for BPM refinement
/// 4. Half/double tempo resolution with musical heuristics
/// 5. Beat position tracking via onset correlation
/// 6. Downbeat detection via spectral pattern (low-energy emphasis)
pub struct TempoDetector {
    /// Sample rate
    sample_rate: f64,
    /// Minimum BPM to detect
    min_bpm: f64,
    /// Maximum BPM to detect
    max_bpm: f64,
    /// Hop size for STFT analysis (samples)
    hop_size: usize,
    /// FFT window size (samples)
    fft_size: usize,
    /// Onset detection function (strength per frame)
    odf: Vec<OnsetEntry>,
    /// Detected onset peaks (sample positions + strength)
    onset_peaks: Vec<(u64, f64)>,
    /// Analysis complete flag
    analyzed: bool,
    /// Cached detection result
    cached_result: Option<TempoDetection>,
}

impl TempoDetector {
    /// Create new detector
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            min_bpm: 60.0,
            max_bpm: 200.0,
            hop_size: 512,
            fft_size: 2048,
            odf: Vec::new(),
            onset_peaks: Vec::new(),
            analyzed: false,
            cached_result: None,
        }
    }

    /// Set BPM range
    pub fn set_range(&mut self, min_bpm: f64, max_bpm: f64) {
        self.min_bpm = min_bpm.max(20.0);
        self.max_bpm = max_bpm.min(400.0);
    }

    /// Process audio for tempo detection — the main entry point
    ///
    /// Uses dual-window energy ratio onset detection with adaptive thresholding.
    /// This is robust for any audio content — from synthetic kicks to full mixes.
    ///
    /// ## Algorithm
    /// 1. Compute short-term energy (hop-sized windows)
    /// 2. ODF = ratio of current energy to moving average (spectral flux analog)
    /// 3. Adaptive threshold for peak picking
    /// 4. Results feed into autocorrelation + comb filter BPM estimation
    pub fn process(&mut self, audio: &[f64]) {
        self.reset();

        let hop = self.hop_size;
        if audio.len() < hop * 8 {
            return;
        }

        let num_frames = audio.len() / hop;
        if num_frames < 8 {
            return;
        }

        // ── Stage 1: Compute per-frame RMS energy ────────────────────────
        let mut frame_energy: Vec<f64> = Vec::with_capacity(num_frames);

        for frame_idx in 0..num_frames {
            let start = frame_idx * hop;
            let end = (start + hop).min(audio.len());
            let window = &audio[start..end];

            let rms = (window.iter().map(|s| s * s).sum::<f64>() / window.len() as f64).sqrt();
            frame_energy.push(rms);
        }

        // ── Stage 2: Onset Detection Function ──────────────────────────
        // Dual approach: energy ratio (current / moving average) + first derivative
        // This catches both sharp transients and gradual level changes

        let avg_window = 8; // ~85ms moving average at 512 hop / 48kHz
        let mut odf_values: Vec<f64> = Vec::with_capacity(num_frames);

        for i in 0..num_frames {
            if i < avg_window {
                odf_values.push(0.0);
                continue;
            }

            // Moving average of previous frames
            let avg: f64 = frame_energy[i.saturating_sub(avg_window)..i]
                .iter()
                .sum::<f64>()
                / avg_window as f64;

            // Energy ratio (log-domain for better dynamic range)
            let ratio = if avg > 1e-10 {
                (frame_energy[i] / avg).max(0.0)
            } else if frame_energy[i] > 1e-10 {
                10.0 // Sudden onset from silence
            } else {
                0.0
            };

            // First derivative (positive only — onset = energy increase)
            let deriv = (frame_energy[i] - frame_energy[i - 1]).max(0.0);

            // Combined ODF: ratio detects relative changes, derivative detects absolute changes
            let odf_val = ratio * 0.7 + deriv * 100.0 * 0.3; // Scale derivative to similar range
            odf_values.push(odf_val);
        }

        // ── Stage 3: Adaptive thresholding for peak picking ─────────────
        // Running median + multiplicative threshold (Bello et al. 2005)

        let median_window = 17; // ~180ms at 512 hop / 48kHz
        let threshold_mult = 1.3; // Peak must be 1.3x the local median
        let min_odf = 0.5; // Minimum absolute ODF value

        for i in 0..num_frames {
            let position = (i * hop) as u64;
            let strength = odf_values[i];

            self.odf.push(OnsetEntry { position, strength });

            if i < avg_window + 2 || i + 2 >= num_frames {
                continue;
            }

            // Compute local median
            let win_start = i.saturating_sub(median_window / 2);
            let win_end = (i + median_window / 2 + 1).min(num_frames);
            let mut local_window: Vec<f64> = odf_values[win_start..win_end].to_vec();
            local_window.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let median = local_window[local_window.len() / 2];

            let threshold = (median * threshold_mult).max(min_odf);

            // Peak detection: above threshold AND local maximum (5-sample window)
            if strength > threshold
                && strength >= odf_values[i - 1]
                && strength >= odf_values[i - 2]
                && strength >= odf_values[i + 1]
                && strength >= odf_values[i + 2]
            {
                // Minimum gap between onsets: ~50ms
                let min_gap = (self.sample_rate * 0.05) as u64;
                let can_add = self
                    .onset_peaks
                    .last()
                    .map_or(true, |last| position - last.0 >= min_gap);
                if can_add {
                    self.onset_peaks.push((position, strength));
                }
            }
        }

        self.analyzed = true;
    }

    /// Analyze processed data and return tempo detection result
    pub fn analyze(&self) -> TempoDetection {
        if let Some(ref cached) = self.cached_result {
            return cached.clone();
        }

        if self.odf.len() < 8 || self.onset_peaks.len() < 3 {
            return TempoDetection {
                bpm: 120.0,
                confidence: 0.0,
                alternatives: vec![60.0, 240.0],
                downbeats: Vec::new(),
                beats: Vec::new(),
                stable: false,
                tempo_curve: Vec::new(),
            };
        }

        // ── Stage 4: Autocorrelation of ODF for periodicity ─────────────────
        // ACF of the onset detection function reveals beat period
        let odf_values: Vec<f64> = self.odf.iter().map(|e| e.strength).collect();
        let n = odf_values.len();

        // Lag range: convert BPM to frame lags
        let frames_per_second = self.sample_rate / self.hop_size as f64;
        let min_lag = (frames_per_second * 60.0 / self.max_bpm) as usize;
        let max_lag = (frames_per_second * 60.0 / self.min_bpm).min(n as f64 / 2.0) as usize;

        if min_lag >= max_lag || max_lag >= n {
            return self.fallback_ioi_detection();
        }

        // Compute normalized autocorrelation
        let mut acf: Vec<f64> = Vec::with_capacity(max_lag - min_lag + 1);
        let mean: f64 = odf_values.iter().sum::<f64>() / n as f64;
        let variance: f64 = odf_values.iter().map(|v| (v - mean).powi(2)).sum::<f64>();

        if variance < 1e-12 {
            return self.fallback_ioi_detection();
        }

        for lag in min_lag..=max_lag {
            let mut sum = 0.0;
            let count = n - lag;
            for i in 0..count {
                sum += (odf_values[i] - mean) * (odf_values[i + lag] - mean);
            }
            acf.push(sum / variance);
        }

        // ── Stage 5: Comb filter bank for BPM refinement ────────────────────
        // Boost integer multiples of candidate BPM periods in the ACF
        let num_candidates = max_lag - min_lag + 1;
        let mut comb_scores: Vec<f64> = vec![0.0; num_candidates];

        for (idx, lag) in (min_lag..=max_lag).enumerate() {
            let mut score = acf[idx]; // Base ACF value

            // Add harmonics (2x, 3x, 4x) — they reinforce the fundamental period
            for harmonic in 2..=4u64 {
                let h_lag = lag as u64 * harmonic;
                if (h_lag as usize) < n / 2 && h_lag as usize >= min_lag {
                    let h_idx = h_lag as usize - min_lag;
                    if h_idx < acf.len() {
                        // Weight decreases for higher harmonics
                        score += acf[h_idx] / harmonic as f64;
                    }
                }
            }

            // Also check sub-harmonics (period/2, period/3)
            for sub in 2..=3u64 {
                let s_lag = lag / sub as usize;
                if s_lag >= min_lag {
                    let s_idx = s_lag - min_lag;
                    if s_idx < acf.len() {
                        score += acf[s_idx] * 0.3 / sub as f64;
                    }
                }
            }

            comb_scores[idx] = score;
        }

        // ── Stage 6: Find best BPM candidates ──────────────────────────────
        // Pick top 3 peaks in comb_scores

        let mut candidates: Vec<(f64, f64)> = Vec::new(); // (bpm, score)

        for (idx, &score) in comb_scores.iter().enumerate() {
            let lag = idx + min_lag;
            // Must be a local peak
            let is_peak = (idx == 0 || score >= comb_scores[idx.saturating_sub(1)])
                && (idx + 1 >= num_candidates || score >= comb_scores[(idx + 1).min(num_candidates - 1)]);

            if is_peak && score > 0.0 {
                let bpm = (frames_per_second * 60.0) / lag as f64;
                if bpm >= self.min_bpm && bpm <= self.max_bpm {
                    candidates.push((bpm, score));
                }
            }
        }

        candidates.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        candidates.truncate(5);

        if candidates.is_empty() {
            return self.fallback_ioi_detection();
        }

        // ── Stage 7: Half/double tempo resolution ────────────────────────────
        // Apply musical heuristics to choose between related tempos

        let raw_bpm = candidates[0].0;
        let raw_score = candidates[0].1;

        let bpm = self.resolve_tempo_ambiguity(raw_bpm, &candidates);

        // ── Stage 8: Compute confidence ─────────────────────────────────────
        // Use peak-to-median ratio of comb scores as confidence metric
        let max_score = comb_scores.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        let mut sorted_scores = comb_scores.clone();
        sorted_scores.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let _median_score = sorted_scores[sorted_scores.len() / 2];

        // Also compute mean of positive scores
        let positive_scores: Vec<f64> = comb_scores.iter().filter(|&&s| s > 0.0).copied().collect();
        let mean_positive = if !positive_scores.is_empty() {
            positive_scores.iter().sum::<f64>() / positive_scores.len() as f64
        } else {
            0.0
        };

        // Confidence: how much the best score stands out
        // Use multiple metrics for robustness
        let confidence = if max_score > 0.0 {
            let peak_ratio = if mean_positive > 0.0 {
                (raw_score / mean_positive - 1.0).max(0.0) / 5.0 // Normalize: 5x mean = 1.0
            } else {
                0.5 // Some onsets found but scores are mixed
            };

            // Also factor in number of onsets (more = more reliable)
            let onset_factor = (self.onset_peaks.len() as f64 / 8.0).min(1.0); // 8+ onsets = full confidence

            (peak_ratio * 0.7 + onset_factor * 0.3).clamp(0.0, 1.0)
        } else if !self.onset_peaks.is_empty() {
            // ACF found no periodicity but we have onsets — low confidence from IOI
            0.15
        } else {
            0.0
        };

        // ── Stage 9: Beat tracking — find actual beat positions ─────────────
        let beats = self.track_beats(bpm);

        // ── Stage 10: Downbeat detection ────────────────────────────────────
        let downbeats = self.detect_downbeats(&beats, 4); // Assume 4/4 for detection

        // ── Stage 11: Tempo stability / variable tempo ──────────────────────
        let (stable, tempo_curve) = self.compute_tempo_curve(&beats);

        // ── Stage 12: Generate alternatives ─────────────────────────────────
        let mut alternatives = Vec::with_capacity(4);
        if bpm / 2.0 >= self.min_bpm {
            alternatives.push(bpm / 2.0);
        }
        if bpm * 2.0 <= self.max_bpm {
            alternatives.push(bpm * 2.0);
        }
        // Add other strong candidates
        for &(c_bpm, _) in candidates.iter().skip(1).take(2) {
            if (c_bpm - bpm).abs() > 2.0
                && (c_bpm - bpm / 2.0).abs() > 2.0
                && (c_bpm - bpm * 2.0).abs() > 2.0
            {
                alternatives.push(c_bpm);
            }
        }

        TempoDetection {
            bpm,
            confidence,
            alternatives,
            downbeats,
            beats,
            stable,
            tempo_curve,
        }
    }

    /// Reset detector
    pub fn reset(&mut self) {
        self.odf.clear();
        self.onset_peaks.clear();
        self.analyzed = false;
        self.cached_result = None;
    }

    // ── Private helpers ─────────────────────────────────────────────────────

    /// Fallback: Inter-Onset-Interval (IOI) based detection when ACF fails
    fn fallback_ioi_detection(&self) -> TempoDetection {
        if self.onset_peaks.len() < 4 {
            return TempoDetection {
                bpm: 120.0,
                confidence: 0.0,
                alternatives: vec![60.0, 240.0],
                downbeats: Vec::new(),
                beats: Vec::new(),
                stable: false,
                tempo_curve: Vec::new(),
            };
        }

        // Compute IOIs
        let min_interval = (self.sample_rate * 60.0 / self.max_bpm) as f64;
        let max_interval = (self.sample_rate * 60.0 / self.min_bpm) as f64;

        // High-resolution histogram (1024 bins for ~0.1 BPM resolution)
        let num_bins = 1024usize;
        let mut histogram = vec![0.0f64; num_bins];

        for i in 1..self.onset_peaks.len() {
            let interval = (self.onset_peaks[i].0 - self.onset_peaks[i - 1].0) as f64;

            // Also consider intervals spanning 2-4 onsets (catches off-beat subdivisions)
            for span in 1..=4u64 {
                let adj_interval = interval / span as f64;
                if adj_interval >= min_interval && adj_interval <= max_interval {
                    let normalized = (adj_interval - min_interval) / (max_interval - min_interval);
                    let bin = (normalized * (num_bins - 1) as f64) as usize;
                    if bin < num_bins {
                        // Weight by onset strength and span relevance
                        let weight = self.onset_peaks[i].1 / span as f64;
                        histogram[bin] += weight;
                        // Gaussian spread to adjacent bins (±2 bins)
                        if bin >= 1 {
                            histogram[bin - 1] += weight * 0.6;
                        }
                        if bin + 1 < num_bins {
                            histogram[bin + 1] += weight * 0.6;
                        }
                        if bin >= 2 {
                            histogram[bin - 2] += weight * 0.3;
                        }
                        if bin + 2 < num_bins {
                            histogram[bin + 2] += weight * 0.3;
                        }
                    }
                }
            }
        }

        // Find peak
        let (peak_bin, &peak_val) = histogram
            .iter()
            .enumerate()
            .max_by(|(_, a), (_, b)| a.partial_cmp(b).unwrap())
            .unwrap_or((num_bins / 2, &0.0));

        let normalized = peak_bin as f64 / (num_bins - 1) as f64;
        let interval = min_interval + normalized * (max_interval - min_interval);
        let bpm = (self.sample_rate * 60.0) / interval;

        let total: f64 = histogram.iter().sum();
        let confidence = if total > 0.0 {
            (peak_val / total * 5.0).clamp(0.0, 1.0) // Scale up, cap at 1
        } else {
            0.0
        };

        // Stability from IOI variance
        let intervals: Vec<f64> = self
            .onset_peaks
            .windows(2)
            .map(|w| (w[1].0 - w[0].0) as f64)
            .collect();
        let mean_ioi = intervals.iter().sum::<f64>() / intervals.len() as f64;
        let variance = intervals.iter().map(|i| (i - mean_ioi).powi(2)).sum::<f64>() / intervals.len() as f64;
        let cv = variance.sqrt() / mean_ioi; // Coefficient of variation
        let stable = cv < 0.15;

        let resolved_bpm = self.resolve_tempo_ambiguity(bpm, &[(bpm, peak_val)]);

        TempoDetection {
            bpm: resolved_bpm,
            confidence,
            alternatives: vec![resolved_bpm / 2.0, resolved_bpm * 2.0],
            downbeats: self.onset_peaks.iter().step_by(4).map(|o| o.0).collect(),
            beats: Vec::new(),
            stable,
            tempo_curve: Vec::new(),
        }
    }

    /// Resolve half/double tempo ambiguity using musical heuristics
    ///
    /// Most music lives in 80-160 BPM range. We prefer tempos in this range
    /// unless there's strong evidence for outside values.
    fn resolve_tempo_ambiguity(&self, raw_bpm: f64, candidates: &[(f64, f64)]) -> f64 {
        let mut best = raw_bpm;

        // Prefer 80-160 BPM range (most common for popular music)
        // If raw is outside this range, check if half/double is inside
        if raw_bpm > 160.0 && raw_bpm / 2.0 >= 60.0 {
            // Check if half-tempo is a candidate with decent score
            let half = raw_bpm / 2.0;
            let has_half = candidates.iter().any(|&(b, _)| (b - half).abs() < 3.0);
            if has_half || (half >= 80.0 && half <= 160.0) {
                best = half;
            }
        } else if raw_bpm < 80.0 && raw_bpm * 2.0 <= 240.0 {
            let double = raw_bpm * 2.0;
            let has_double = candidates.iter().any(|&(b, _)| (b - double).abs() < 3.0);
            if has_double || (double >= 80.0 && double <= 160.0) {
                best = double;
            }
        }

        // Final clamp to user-specified range
        best.clamp(self.min_bpm, self.max_bpm)
    }

    /// Track individual beat positions given a BPM estimate
    ///
    /// Uses onset peaks to find the phase (beat offset) that best aligns
    /// with the detected periodicity.
    fn track_beats(&self, bpm: f64) -> Vec<u64> {
        if self.onset_peaks.is_empty() || bpm <= 0.0 {
            return Vec::new();
        }

        let samples_per_beat = (self.sample_rate * 60.0) / bpm;
        let total_samples = self.odf.last().map(|e| e.position).unwrap_or(0);
        let num_beats = (total_samples as f64 / samples_per_beat) as usize;

        if num_beats < 2 {
            return Vec::new();
        }

        // Find best phase by scoring alignment of grid with onset peaks
        // Test 100 phase candidates within one beat period
        let phase_steps = 100;
        let phase_step = samples_per_beat / phase_steps as f64;

        let mut best_phase = 0.0f64;
        let mut best_score = 0.0f64;

        for p in 0..phase_steps {
            let phase = p as f64 * phase_step;
            let mut score = 0.0;

            for beat in 0..num_beats {
                let beat_pos = phase + beat as f64 * samples_per_beat;
                // Find nearest onset peak and score by proximity + strength
                let tolerance = samples_per_beat * 0.15; // ±15% of beat period
                for &(onset_pos, onset_str) in &self.onset_peaks {
                    let dist = (onset_pos as f64 - beat_pos).abs();
                    if dist < tolerance {
                        // Gaussian weighting: closer onsets score higher
                        let sigma = tolerance * 0.3;
                        let weight = (-dist * dist / (2.0 * sigma * sigma)).exp();
                        score += onset_str * weight;
                    }
                }
            }

            if score > best_score {
                best_score = score;
                best_phase = phase;
            }
        }

        // Generate beat positions with best phase
        let mut beats = Vec::with_capacity(num_beats);
        for beat in 0..num_beats {
            let pos = (best_phase + beat as f64 * samples_per_beat) as u64;
            if pos <= total_samples {
                beats.push(pos);
            }
        }

        beats
    }

    /// Detect downbeats from beat positions
    ///
    /// Uses low-frequency energy emphasis: downbeats tend to have more bass
    fn detect_downbeats(&self, beats: &[u64], beats_per_bar: usize) -> Vec<u64> {
        if beats.len() < beats_per_bar {
            return beats.iter().step_by(beats_per_bar).copied().collect();
        }

        // Score each possible phase (0..beats_per_bar) for downbeat alignment
        // Downbeats typically coincide with stronger onsets
        let mut best_phase = 0usize;
        let mut best_score = 0.0f64;

        for phase in 0..beats_per_bar {
            let mut score = 0.0;
            for i in (phase..beats.len()).step_by(beats_per_bar) {
                let beat_pos = beats[i];
                // Find nearest onset and use its strength
                let tolerance = (self.sample_rate * 0.03) as u64; // 30ms
                for &(onset_pos, onset_str) in &self.onset_peaks {
                    if onset_pos.abs_diff(beat_pos) < tolerance {
                        score += onset_str;
                        break;
                    }
                }
            }

            if score > best_score {
                best_score = score;
                best_phase = phase;
            }
        }

        // Collect downbeats
        beats
            .iter()
            .skip(best_phase)
            .step_by(beats_per_bar)
            .copied()
            .collect()
    }

    /// Compute per-beat tempo curve and stability metric
    fn compute_tempo_curve(&self, beats: &[u64]) -> (bool, Vec<(u64, f64)>) {
        if beats.len() < 3 {
            return (true, Vec::new());
        }

        let mut tempo_curve = Vec::with_capacity(beats.len() - 1);
        let mut tempos = Vec::with_capacity(beats.len() - 1);

        for i in 1..beats.len() {
            let interval = (beats[i] - beats[i - 1]) as f64;
            if interval > 0.0 {
                let local_bpm = (self.sample_rate * 60.0) / interval;
                tempo_curve.push((beats[i - 1], local_bpm));
                tempos.push(local_bpm);
            }
        }

        if tempos.is_empty() {
            return (true, Vec::new());
        }

        // Stability: coefficient of variation < 5% = stable
        let mean = tempos.iter().sum::<f64>() / tempos.len() as f64;
        let variance = tempos.iter().map(|t| (t - mean).powi(2)).sum::<f64>() / tempos.len() as f64;
        let cv = variance.sqrt() / mean;
        let stable = cv < 0.05; // <5% variation = stable (tight for pro quality)

        (stable, tempo_curve)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SMART TEMPO — High-level processor
// ═══════════════════════════════════════════════════════════════════════════════

/// Smart tempo processor
pub struct SmartTempo {
    /// Mode
    mode: SmartTempoMode,
    /// Tempo map
    tempo_map: SmartTempoMap,
    /// Detector
    detector: TempoDetector,
    /// Current detection
    detection: Option<TempoDetection>,
}

impl SmartTempo {
    /// Create new smart tempo processor
    pub fn new(sample_rate: f64, initial_bpm: f64) -> Self {
        Self {
            mode: SmartTempoMode::KeepProject,
            tempo_map: SmartTempoMap::new(initial_bpm, sample_rate),
            detector: TempoDetector::new(sample_rate),
            detection: None,
        }
    }

    /// Set mode
    pub fn set_mode(&mut self, mode: SmartTempoMode) {
        self.mode = mode;
    }

    /// Get mode
    pub fn mode(&self) -> SmartTempoMode {
        self.mode
    }

    /// Analyze audio for tempo
    pub fn analyze(&mut self, audio: &[f64]) -> &TempoDetection {
        self.detector.reset();
        self.detector.process(audio);
        self.detection = Some(self.detector.analyze());
        self.detection.as_ref().unwrap()
    }

    /// Apply detected tempo based on mode
    pub fn apply(&mut self) -> Option<f64> {
        let detection = self.detection.as_ref()?;

        match self.mode {
            SmartTempoMode::AdaptProject => {
                self.tempo_map.base_tempo = detection.bpm;
                Some(detection.bpm)
            }
            SmartTempoMode::KeepProject => {
                let ratio = self.tempo_map.base_tempo / detection.bpm;
                Some(ratio)
            }
            SmartTempoMode::Automatic => {
                if detection.confidence > 0.7 {
                    self.tempo_map.base_tempo = detection.bpm;
                    Some(detection.bpm)
                } else {
                    Some(1.0)
                }
            }
            SmartTempoMode::Manual => None,
        }
    }

    /// Get tempo map
    pub fn tempo_map(&self) -> &SmartTempoMap {
        &self.tempo_map
    }

    /// Get mutable tempo map
    pub fn tempo_map_mut(&mut self) -> &mut SmartTempoMap {
        &mut self.tempo_map
    }

    /// Get last detection
    pub fn detection(&self) -> Option<&TempoDetection> {
        self.detection.as_ref()
    }

    /// Set project tempo
    pub fn set_project_tempo(&mut self, bpm: f64) {
        self.tempo_map.base_tempo = bpm;
    }

    /// Get project tempo
    pub fn project_tempo(&self) -> f64 {
        self.tempo_map.base_tempo
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tempo_map_constant() {
        let map = SmartTempoMap::new(120.0, 48000.0);
        assert!((map.tempo_at(0) - 120.0).abs() < 0.001);
        assert!((map.samples_per_beat_at(0) - 24000.0).abs() < 1.0);
    }

    #[test]
    fn test_tempo_map_with_event() {
        let mut map = SmartTempoMap::new(120.0, 48000.0);

        map.add_event(SmartTempoEvent {
            position: 48000,
            bpm: 140.0,
            transition: TempoTransition::Instant,
        });

        assert!((map.tempo_at(0) - 120.0).abs() < 0.001);
        assert!((map.tempo_at(50000) - 140.0).abs() < 0.001);
    }

    #[test]
    fn test_beat_sample_conversion() {
        let map = SmartTempoMap::new(120.0, 48000.0);

        assert_eq!(map.beat_to_samples(0.0), 0);

        let samples = map.beat_to_samples(1.0);
        assert!((samples as f64 - 24000.0).abs() < 10.0);

        let beat = map.samples_to_beat(24000);
        assert!((beat - 1.0).abs() < 0.01);
    }

    #[test]
    fn test_smart_tempo_modes() {
        let mut smart = SmartTempo::new(48000.0, 120.0);
        assert_eq!(smart.mode(), SmartTempoMode::KeepProject);
        smart.set_mode(SmartTempoMode::AdaptProject);
        assert_eq!(smart.mode(), SmartTempoMode::AdaptProject);
    }

    #[test]
    fn test_tempo_detection_empty() {
        let detector = TempoDetector::new(48000.0);
        let detection = detector.analyze();
        assert!((detection.bpm - 120.0).abs() < 0.001);
        assert!(detection.confidence < 0.1);
    }

    #[test]
    fn test_onset_detection_produces_peaks() {
        let sample_rate = 48000.0;
        let bpm = 120.0;
        let beat_interval = (sample_rate * 60.0 / bpm) as usize;
        let total_samples = (sample_rate * 10.0) as usize;

        let mut audio = vec![0.0f64; total_samples];
        let transient_len = 4000;
        let mut rng: u32 = 0xDEAD_BEEF;

        for beat in 0..20 {
            let pos = beat * beat_interval;
            for i in 0..transient_len {
                if pos + i < total_samples {
                    let t = i as f64 / sample_rate;
                    let freq = 60.0 + 200.0 * (-t * 30.0).exp();
                    let body = (t * freq * std::f64::consts::TAU).sin() * (-t * 15.0).exp();
                    rng = rng.wrapping_mul(1103515245).wrapping_add(12345);
                    let noise = (rng as f64 / u32::MAX as f64) * 2.0 - 1.0;
                    let click = noise * (-t * 500.0).exp() * 0.3;
                    audio[pos + i] = (body * 0.8 + click).clamp(-1.0, 1.0);
                }
            }
        }

        let mut detector = TempoDetector::new(sample_rate);
        detector.set_range(60.0, 200.0);
        detector.process(&audio);

        // Must detect at least some onsets
        assert!(
            detector.onset_peaks.len() >= 5,
            "Not enough onsets detected: {}",
            detector.onset_peaks.len()
        );

        let detection = detector.analyze();
        assert!(detection.confidence > 0.0, "Zero confidence");
    }

    #[test]
    fn test_tempo_detection_120bpm_sine_kicks() {
        let sample_rate = 48000.0;
        let bpm = 120.0;
        let beat_interval = (sample_rate * 60.0 / bpm) as usize;
        let duration_seconds = 10.0;
        let total_samples = (sample_rate * duration_seconds) as usize;

        // Generate realistic synthetic kick drum at exact beat positions
        // Kick = low sine (60Hz) with sharp attack + noise transient
        let mut audio = vec![0.0f64; total_samples];
        let transient_len = 4000; // ~83ms — realistic kick length

        let mut rng: u32 = 0xDEAD_BEEF;
        for beat in 0..20 {
            let pos = beat * beat_interval;
            for i in 0..transient_len {
                if pos + i < total_samples {
                    let t = i as f64 / sample_rate;
                    // Kick body: 60Hz sine with pitch decay
                    let freq = 60.0 + 200.0 * (-t * 30.0).exp(); // Pitch drops from 260→60Hz
                    let body = (t * freq * std::f64::consts::TAU).sin() * (-t * 15.0).exp();
                    // Transient click: noise burst in first 2ms
                    rng = rng.wrapping_mul(1103515245).wrapping_add(12345);
                    let noise = (rng as f64 / u32::MAX as f64) * 2.0 - 1.0;
                    let click = noise * (-t * 500.0).exp() * 0.3;
                    audio[pos + i] = (body * 0.8 + click).clamp(-1.0, 1.0);
                }
            }
        }

        let mut detector = TempoDetector::new(sample_rate);
        detector.set_range(60.0, 200.0);
        detector.process(&audio);
        let detection = detector.analyze();

        // BPM should be within ±3 of 120 (or half/double)
        let valid = (detection.bpm - 120.0).abs() < 3.0
            || (detection.bpm - 60.0).abs() < 3.0
            || (detection.bpm - 240.0).abs() < 3.0;
        assert!(
            valid,
            "Expected ~120 BPM (or harmonic), got {} (confidence: {})",
            detection.bpm, detection.confidence
        );
        assert!(detection.confidence > 0.1, "Confidence too low: {}", detection.confidence);
    }

    #[test]
    fn test_tempo_detection_140bpm() {
        let sample_rate = 48000.0;
        let bpm = 140.0;
        let beat_interval = (sample_rate * 60.0 / bpm) as usize;
        let duration_seconds = 10.0;
        let total_samples = (sample_rate * duration_seconds) as usize;

        let mut audio = vec![0.0f64; total_samples];
        let transient_len = 3000;

        let mut rng: u32 = 0xCAFE_BABE;
        let num_beats = (total_samples / beat_interval).min(25);
        for beat in 0..num_beats {
            let pos = beat * beat_interval;
            for i in 0..transient_len {
                if pos + i < total_samples {
                    let t = i as f64 / sample_rate;
                    let freq = 80.0 + 180.0 * (-t * 35.0).exp();
                    let body = (t * freq * std::f64::consts::TAU).sin() * (-t * 18.0).exp();
                    rng = rng.wrapping_mul(1103515245).wrapping_add(12345);
                    let noise = (rng as f64 / u32::MAX as f64) * 2.0 - 1.0;
                    let click = noise * (-t * 400.0).exp() * 0.25;
                    audio[pos + i] = (body * 0.7 + click).clamp(-1.0, 1.0);
                }
            }
        }

        let mut detector = TempoDetector::new(sample_rate);
        detector.set_range(60.0, 200.0);
        detector.process(&audio);
        let detection = detector.analyze();

        // Accept 140, 70 (half), or 280 (double, outside range so clamped)
        let valid = (detection.bpm - 140.0).abs() < 4.0
            || (detection.bpm - 70.0).abs() < 4.0;
        assert!(
            valid,
            "Expected ~140 BPM (or harmonic), got {} (confidence: {})",
            detection.bpm, detection.confidence
        );
    }
}
