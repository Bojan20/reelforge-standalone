//! # Real-Time Phase Gradient Heap Integration (RTPGHI)
//!
//! State-of-the-art phase reconstruction algorithm that automatically
//! maintains both horizontal and vertical phase coherence.
//!
//! ## References
//!
//! - Průša, Z., & Holighaus, N. (2022): "Phase Vocoder Done Right"
//! - Ltfat.org phaseret toolbox

use std::cmp::Ordering;
use std::collections::BinaryHeap;
use std::f64::consts::PI;

// ═══════════════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Priority queue entry for heap-based phase integration
#[derive(Clone, Copy)]
struct HeapEntry {
    /// Frame index
    frame: usize,
    /// Frequency bin index
    bin: usize,
    /// Magnitude (priority)
    magnitude: f64,
}

impl PartialEq for HeapEntry {
    fn eq(&self, other: &Self) -> bool {
        self.magnitude == other.magnitude
    }
}

impl Eq for HeapEntry {}

impl PartialOrd for HeapEntry {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for HeapEntry {
    fn cmp(&self, other: &Self) -> Ordering {
        // Max-heap: higher magnitude = higher priority
        self.magnitude
            .partial_cmp(&other.magnitude)
            .unwrap_or(Ordering::Equal)
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PHASE GRADIENT HEAP
// ═══════════════════════════════════════════════════════════════════════════════

/// Real-Time Phase Gradient Heap Integration
///
/// Reconstructs phase from magnitude spectrogram using gradient integration
/// with max-heap priority ordering for optimal coherence.
pub struct PhaseGradientHeap {
    /// Sample rate
    sample_rate: f64,
    /// Gaussian window parameter (controls time-frequency tradeoff)
    gamma: f64,
    /// Tolerance for small magnitudes
    tolerance: f64,
    /// Previous frame phase (for streaming)
    prev_phase: Vec<f64>,
    /// Phase accumulator
    phase_accum: Vec<f64>,
}

impl PhaseGradientHeap {
    /// Create new RTPGHI processor
    pub fn new(sample_rate: f64) -> Self {
        Self {
            sample_rate,
            gamma: 25.0, // Default Gaussian parameter
            tolerance: 1e-10,
            prev_phase: Vec::new(),
            phase_accum: Vec::new(),
        }
    }

    /// Create with custom gamma parameter
    pub fn with_gamma(sample_rate: f64, gamma: f64) -> Self {
        Self {
            sample_rate,
            gamma,
            tolerance: 1e-10,
            prev_phase: Vec::new(),
            phase_accum: Vec::new(),
        }
    }

    /// Reconstruct phase from magnitude spectrogram
    ///
    /// Uses the RTPGHI algorithm:
    /// 1. Estimate phase gradients from log-magnitude derivatives
    /// 2. Integrate phases using max-heap priority (most confident first)
    /// 3. Maintains both time and frequency coherence automatically
    pub fn reconstruct(&mut self, magnitude: &[Vec<f64>]) -> Vec<Vec<f64>> {
        if magnitude.is_empty() || magnitude[0].is_empty() {
            return vec![];
        }

        let num_frames = magnitude.len();
        let num_bins = magnitude[0].len();

        // Initialize phase array
        let mut phase = vec![vec![0.0; num_bins]; num_frames];
        let mut visited = vec![vec![false; num_bins]; num_frames];

        // Compute log-magnitude (with small offset for stability)
        let log_mag: Vec<Vec<f64>> = magnitude
            .iter()
            .map(|frame| frame.iter().map(|&m| (m + self.tolerance).ln()).collect())
            .collect();

        // Compute phase gradients
        let (grad_time, grad_freq) = self.compute_gradients(&log_mag);

        // Initialize max-heap with all coefficients
        let mut heap = BinaryHeap::new();
        for frame in 0..num_frames {
            for bin in 0..num_bins {
                heap.push(HeapEntry {
                    frame,
                    bin,
                    magnitude: magnitude[frame][bin],
                });
            }
        }

        // Process in order of decreasing magnitude
        while let Some(entry) = heap.pop() {
            if visited[entry.frame][entry.bin] {
                continue;
            }

            // Get phase from neighbors (if available)
            let estimated_phase = self.estimate_phase_from_neighbors(
                entry.frame,
                entry.bin,
                &phase,
                &visited,
                &grad_time,
                &grad_freq,
            );

            phase[entry.frame][entry.bin] = estimated_phase;
            visited[entry.frame][entry.bin] = true;
        }

        // Unwrap phase to remove discontinuities
        self.unwrap_phase(&mut phase);

        phase
    }

    /// Compute phase gradients from log-magnitude
    fn compute_gradients(&self, log_mag: &[Vec<f64>]) -> (Vec<Vec<f64>>, Vec<Vec<f64>>) {
        let num_frames = log_mag.len();
        let num_bins = if num_frames > 0 { log_mag[0].len() } else { 0 };

        let mut grad_time = vec![vec![0.0; num_bins]; num_frames];
        let mut grad_freq = vec![vec![0.0; num_bins]; num_frames];

        // For Gaussian windows, phase gradients relate to log-magnitude gradients:
        // dφ/dt ≈ -σ² * d(log|X|)/dω
        // dφ/dω ≈ σ² * d(log|X|)/dt
        let sigma_sq = self.gamma;

        for frame in 0..num_frames {
            for bin in 0..num_bins {
                // Time gradient (horizontal): difference between frames
                if frame > 0 && frame < num_frames - 1 {
                    grad_time[frame][bin] =
                        sigma_sq * (log_mag[frame + 1][bin] - log_mag[frame - 1][bin]) / 2.0;
                } else if frame == 0 && num_frames > 1 {
                    grad_time[frame][bin] =
                        sigma_sq * (log_mag[frame + 1][bin] - log_mag[frame][bin]);
                } else if frame == num_frames - 1 && num_frames > 1 {
                    grad_time[frame][bin] =
                        sigma_sq * (log_mag[frame][bin] - log_mag[frame - 1][bin]);
                }

                // Frequency gradient (vertical): difference between bins
                if bin > 0 && bin < num_bins - 1 {
                    grad_freq[frame][bin] =
                        -sigma_sq * (log_mag[frame][bin + 1] - log_mag[frame][bin - 1]) / 2.0;
                } else if bin == 0 && num_bins > 1 {
                    grad_freq[frame][bin] =
                        -sigma_sq * (log_mag[frame][bin + 1] - log_mag[frame][bin]);
                } else if bin == num_bins - 1 && num_bins > 1 {
                    grad_freq[frame][bin] =
                        -sigma_sq * (log_mag[frame][bin] - log_mag[frame][bin - 1]);
                }
            }
        }

        (grad_time, grad_freq)
    }

    /// Estimate phase from already-visited neighbors
    fn estimate_phase_from_neighbors(
        &self,
        frame: usize,
        bin: usize,
        phase: &[Vec<f64>],
        visited: &[Vec<bool>],
        grad_time: &[Vec<f64>],
        grad_freq: &[Vec<f64>],
    ) -> f64 {
        let num_frames = phase.len();
        let num_bins = phase[0].len();

        let mut estimates = Vec::new();
        let mut weights = Vec::new();

        // Check left neighbor (previous frame)
        if frame > 0 && visited[frame - 1][bin] {
            // Phase should increase by expected frequency plus gradient
            let expected_increment = 2.0 * PI * bin as f64 / num_bins as f64;
            let estimate = phase[frame - 1][bin] + expected_increment + grad_time[frame][bin];
            estimates.push(estimate);
            weights.push(1.0);
        }

        // Check right neighbor (next frame)
        if frame < num_frames - 1 && visited[frame + 1][bin] {
            let expected_increment = 2.0 * PI * bin as f64 / num_bins as f64;
            let estimate = phase[frame + 1][bin] - expected_increment - grad_time[frame][bin];
            estimates.push(estimate);
            weights.push(1.0);
        }

        // Check lower neighbor (lower frequency bin)
        if bin > 0 && visited[frame][bin - 1] {
            let estimate = phase[frame][bin - 1] + grad_freq[frame][bin];
            estimates.push(estimate);
            weights.push(0.5); // Lower weight for frequency neighbors
        }

        // Check upper neighbor (higher frequency bin)
        if bin < num_bins - 1 && visited[frame][bin + 1] {
            let estimate = phase[frame][bin + 1] - grad_freq[frame][bin];
            estimates.push(estimate);
            weights.push(0.5);
        }

        if estimates.is_empty() {
            // No neighbors: use linear phase (pure tone assumption)
            return 2.0 * PI * bin as f64 * frame as f64 / num_bins as f64;
        }

        // Weighted average with circular mean
        self.circular_mean(&estimates, &weights)
    }

    /// Compute circular mean of angles
    fn circular_mean(&self, angles: &[f64], weights: &[f64]) -> f64 {
        let mut sum_sin = 0.0;
        let mut sum_cos = 0.0;
        let mut total_weight = 0.0;

        for (&angle, &weight) in angles.iter().zip(weights.iter()) {
            sum_sin += weight * angle.sin();
            sum_cos += weight * angle.cos();
            total_weight += weight;
        }

        if total_weight > 0.0 {
            (sum_sin / total_weight).atan2(sum_cos / total_weight)
        } else {
            0.0
        }
    }

    /// Unwrap phase to remove 2π discontinuities
    fn unwrap_phase(&self, phase: &mut [Vec<f64>]) {
        for frame in phase.iter_mut() {
            let mut prev = 0.0;
            for p in frame.iter_mut() {
                while *p - prev > PI {
                    *p -= 2.0 * PI;
                }
                while *p - prev < -PI {
                    *p += 2.0 * PI;
                }
                prev = *p;
            }
        }
    }

    /// Streaming mode: process single frame using previous frame's phase
    pub fn process_frame(&mut self, magnitude: &[f64]) -> Vec<f64> {
        let num_bins = magnitude.len();

        // Initialize if needed
        if self.prev_phase.len() != num_bins {
            self.prev_phase = vec![0.0; num_bins];
            self.phase_accum = vec![0.0; num_bins];
        }

        let mut phase = vec![0.0; num_bins];
        let log_mag: Vec<f64> = magnitude
            .iter()
            .map(|&m| (m + self.tolerance).ln())
            .collect();

        // Estimate instantaneous frequency from log-magnitude derivative
        for bin in 0..num_bins {
            // Expected phase increment for this bin
            let expected_increment = 2.0 * PI * bin as f64 / num_bins as f64;

            // Phase gradient from log-magnitude (simplified for single frame)
            let grad = if bin > 0 && bin < num_bins - 1 {
                self.gamma * (log_mag[bin + 1] - log_mag[bin - 1]) / 2.0
            } else {
                0.0
            };

            // Accumulate phase
            self.phase_accum[bin] += expected_increment + grad;
        }

        // Copy accumulated phases
        phase.copy_from_slice(&self.phase_accum[..num_bins]);

        self.prev_phase = phase.clone();
        phase
    }

    /// Reset internal state
    pub fn reset(&mut self) {
        self.prev_phase.clear();
        self.phase_accum.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rtpghi_creation() {
        let rtpghi = PhaseGradientHeap::new(44100.0);
        assert!((rtpghi.sample_rate - 44100.0).abs() < 1e-6);
    }

    #[test]
    fn test_empty_input() {
        let mut rtpghi = PhaseGradientHeap::new(44100.0);
        let result = rtpghi.reconstruct(&[]);
        assert!(result.is_empty());
    }

    #[test]
    fn test_single_frame() {
        let mut rtpghi = PhaseGradientHeap::new(44100.0);

        // Single frame with some magnitudes
        let magnitude = vec![vec![1.0, 0.5, 0.25, 0.1, 0.05]];
        let phase = rtpghi.reconstruct(&magnitude);

        assert_eq!(phase.len(), 1);
        assert_eq!(phase[0].len(), 5);
    }

    #[test]
    fn test_multiple_frames() {
        let mut rtpghi = PhaseGradientHeap::new(44100.0);

        // Multiple frames
        let magnitude = vec![
            vec![1.0, 0.5, 0.25],
            vec![0.9, 0.6, 0.3],
            vec![0.8, 0.7, 0.35],
        ];
        let phase = rtpghi.reconstruct(&magnitude);

        assert_eq!(phase.len(), 3);
        assert_eq!(phase[0].len(), 3);
    }

    #[test]
    fn test_streaming_mode() {
        let mut rtpghi = PhaseGradientHeap::new(44100.0);

        let frame1 = vec![1.0, 0.5, 0.25, 0.1];
        let phase1 = rtpghi.process_frame(&frame1);
        assert_eq!(phase1.len(), 4);

        let frame2 = vec![0.9, 0.6, 0.3, 0.15];
        let phase2 = rtpghi.process_frame(&frame2);
        assert_eq!(phase2.len(), 4);

        // Phase should have progressed
        for (p1, p2) in phase1.iter().zip(phase2.iter()) {
            assert!(p2.abs() >= p1.abs() || (p2 - p1).abs() < 2.0 * PI);
        }
    }

    #[test]
    fn test_circular_mean() {
        let rtpghi = PhaseGradientHeap::new(44100.0);

        // Two angles at 0 and 0 should give 0
        let angles = vec![0.0, 0.0];
        let weights = vec![1.0, 1.0];
        let mean = rtpghi.circular_mean(&angles, &weights);
        assert!(mean.abs() < 0.01);

        // Two angles at π/2 and -π/2 should give ~0
        let angles2 = vec![PI / 2.0, -PI / 2.0];
        let mean2 = rtpghi.circular_mean(&angles2, &weights);
        assert!(mean2.abs() < 0.01);
    }
}
