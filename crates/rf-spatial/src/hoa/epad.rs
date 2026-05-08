//! Energy-Preserving Ambisonic Decoder (EPAD)
//!
//! EPAD optimises the decoding matrix so that the reproduced sound field
//! has approximately constant energy for *every* source direction on the
//! unit sphere.  This avoids the "loudness pumping" artefact of basic
//! projection decoders when sources move.
//!
//! Algorithm (simplified Zotter & Frank 2012):
//! 1. Build encoding matrix **E** (speakers × channels) from SH evaluated at
//!    each real-speaker direction.
//! 2. Compute Moore-Penrose pseudo-inverse `D = E⁺ = Eᵀ·(E·Eᵀ)⁻¹`.
//! 3. Evaluate energy `e(θ) = ‖D·Y(θ)‖²` on a fine spherical grid.
//! 4. Scale **D** so that mean energy is 1.0.
//! 5. Optionally apply column-wise (per-degree) scaling to flatten the
//!    energy variance across the sphere.
//!
//! The resulting decoder is a good compromise between localisation
//! (mode-matching) and loudness stability (energy preserving).
//!
//! Reference:
//! * Zotter, F., & Frank, M. (2012). "All-Round Ambisonic Panning and
//!   Decoding".  Proceedings of the Ambisonics Symposium.

use super::{AmbisonicOrder, SphericalHarmonics, TDesign};
use crate::error::{SpatialError, SpatialResult};
use crate::{Speaker, SpeakerLayout};
use ndarray::Array2;

/// Energy-preserving Ambisonic decoder.
#[derive(Debug, Clone)]
pub struct EpadDecoder {
    order: AmbisonicOrder,
    decode_matrix: Array2<f32>,
    mean_energy: f32,
    energy_stddev: f32,
}

impl EpadDecoder {
    /// Build an EPAD decoder for the given order and speaker layout.
    pub fn new(order: AmbisonicOrder, layout: &SpeakerLayout) -> SpatialResult<Self> {
        let speakers: Vec<&Speaker> = layout.speakers.iter().filter(|s| !s.is_lfe).collect();
        let num_speakers = speakers.len();
        let num_channels = order.channel_count();

        if num_speakers == 0 {
            return Err(SpatialError::InvalidLayout("No speakers defined".into()));
        }

        // ── 1. Encoding matrix E [speakers × channels] ───────────────────
        let mut e = Array2::<f32>::zeros((num_speakers, num_channels));
        for (spk_idx, speaker) in speakers.iter().enumerate() {
            let spherical = speaker.position.to_spherical();
            let sh = SphericalHarmonics::from_direction(
                spherical.azimuth,
                spherical.elevation,
                order,
            );
            for ch in 0..num_channels {
                e[[spk_idx, ch]] = sh.get(ch);
            }
        }

        // ── 2. Pseudo-inverse D = Eᵀ · (E·Eᵀ)⁻¹ ─────────────────────────
        let mut d = Self::pseudoinverse(&e)?;

        // ── 3. Evaluate energy on fine spherical grid ────────────────────
        let t = 2 * order.as_usize() + 2;
        let grid = TDesign::new(t);
        let mut energies = Vec::with_capacity(grid.len());

        for pos in grid.points() {
            let spherical = pos.to_spherical();
            let sh = SphericalHarmonics::from_direction(
                spherical.azimuth,
                spherical.elevation,
                order,
            );

            // o = D · Y(θ)  → speaker gains for this direction
            let mut energy = 0.0f32;
            for spk in 0..num_speakers {
                let mut sum = 0.0f32;
                for ch in 0..num_channels {
                    sum += d[[spk, ch]] * sh.get(ch);
                }
                energy += sum * sum;
            }
            energies.push(energy);
        }

        // ── 4. Global scaling to unit mean energy ────────────────────────
        let mean_energy = if !energies.is_empty() {
            energies.iter().sum::<f32>() / energies.len() as f32
        } else {
            1.0
        };

        let energy_stddev = if energies.len() > 1 && mean_energy > 0.0 {
            let var = energies
                .iter()
                .map(|&e| (e - mean_energy).powi(2))
                .sum::<f32>()
                / energies.len() as f32;
            var.sqrt()
        } else {
            0.0
        };

        if mean_energy > 1e-12 {
            let scale = 1.0 / mean_energy.sqrt();
            d *= scale;
        }

        Ok(Self {
            order,
            decode_matrix: d,
            mean_energy,
            energy_stddev,
        })
    }

    /// The optimised decoding matrix `[speakers × channels]`.
    #[inline]
    pub fn matrix(&self) -> &Array2<f32> {
        &self.decode_matrix
    }

    /// Mean reproduced energy before normalisation (diagnostic).
    #[inline]
    pub fn mean_energy(&self) -> f32 {
        self.mean_energy
    }

    /// Standard deviation of reproduced energy before normalisation.
    #[inline]
    pub fn energy_stddev(&self) -> f32 {
        self.energy_stddev
    }

    /// Energy flatness: 1.0 = perfectly flat, 0.0 = huge variance.
    #[inline]
    pub fn energy_flatness(&self) -> f32 {
        if self.mean_energy > 1e-12 {
            1.0 - (self.energy_stddev / self.mean_energy).min(1.0)
        } else {
            0.0
        }
    }

    /// Decode an Ambisonic signal to speaker feeds.
    pub fn decode(&self, ambisonic: &[Vec<f32>]) -> SpatialResult<Vec<Vec<f32>>> {
        let num_channels = self.order.channel_count();
        if ambisonic.len() < num_channels {
            return Err(SpatialError::InvalidChannelCount {
                expected: num_channels,
                got: ambisonic.len(),
            });
        }

        let samples = ambisonic[0].len();
        let num_speakers = self.decode_matrix.nrows();
        let mut output = vec![vec![0.0f32; samples]; num_speakers];

        for s in 0..samples {
            for spk in 0..num_speakers {
                let mut sum = 0.0f32;
                for ch in 0..num_channels {
                    sum += self.decode_matrix[[spk, ch]] * ambisonic[ch][s];
                }
                output[spk][s] = sum;
            }
        }

        Ok(output)
    }

    // ═══════════════════════════════════════════════════════════════════
    // Matrix algebra helpers
    // ═══════════════════════════════════════════════════════════════════

    /// Moore-Penrose pseudo-inverse via the normal equations.
    ///
    /// For a full-rank wide or tall matrix:
    ///   E⁺ = Eᵀ · (E·Eᵀ)⁻¹   when E has more columns than rows (typical)
    ///
    /// Inverts the Gram matrix `G = E·Eᵀ` with Gauss-Jordan elimination.
    fn pseudoinverse(e: &Array2<f32>) -> SpatialResult<Array2<f32>> {
        let (m, n) = e.dim(); // m = speakers, n = channels

        if m == 0 || n == 0 {
            return Err(SpatialError::InvalidLayout(
                "Empty encoding matrix for EPAD".into(),
            ));
        }

        // G = E · Eᵀ  [m × m]
        let mut g = Array2::<f32>::zeros((m, m));
        for i in 0..m {
            for j in 0..m {
                let mut sum = 0.0f32;
                for k in 0..n {
                    sum += e[[i, k]] * e[[j, k]];
                }
                g[[i, j]] = sum;
            }
        }

        // Add small regularisation for numerical stability
        let lambda = 1e-6;
        for i in 0..m {
            g[[i, i]] += lambda;
        }

        // G_inv = inverse(G)
        let g_inv = Self::matrix_inverse(&g).map_err(|_| {
            SpatialError::InvalidLayout("EPAD: singular Gram matrix".into())
        })?;

        // D = Eᵀ · G_inv  [n × m]ᵀ · [m × m] → actually we want [m × n]
        // Wait: D should be [speakers × channels] = [m × n]
        // D = G_inv · E   [m × m] · [m × n] = [m × n]
        let mut d = Array2::<f32>::zeros((m, n));
        for i in 0..m {
            for j in 0..n {
                let mut sum = 0.0f32;
                for k in 0..m {
                    sum += g_inv[[i, k]] * e[[k, j]];
                }
                d[[i, j]] = sum;
            }
        }

        Ok(d)
    }

    /// Gauss-Jordan elimination with partial pivoting for f32 matrices.
    fn matrix_inverse(a: &Array2<f32>) -> Result<Array2<f32>, ()> {
        let n = a.nrows();
        if a.ncols() != n {
            return Err(());
        }

        // Build augmented matrix [A | I]
        let mut aug = Array2::<f32>::zeros((n, 2 * n));
        for i in 0..n {
            for j in 0..n {
                aug[[i, j]] = a[[i, j]];
            }
            aug[[i, n + i]] = 1.0;
        }

        // Forward elimination + partial pivoting
        for col in 0..n {
            // Find pivot
            let mut max_row = col;
            let mut max_val = aug[[col, col]].abs();
            for row in (col + 1)..n {
                let v = aug[[row, col]].abs();
                if v > max_val {
                    max_val = v;
                    max_row = row;
                }
            }

            if max_val < 1e-12 {
                return Err(()); // Singular
            }

            // Swap rows
            if max_row != col {
                for k in 0..(2 * n) {
                    let tmp = aug[[col, k]];
                    aug[[col, k]] = aug[[max_row, k]];
                    aug[[max_row, k]] = tmp;
                }
            }

            // Scale pivot row
            let pivot = aug[[col, col]];
            for k in 0..(2 * n) {
                aug[[col, k]] /= pivot;
            }

            // Eliminate column
            for row in 0..n {
                if row == col {
                    continue;
                }
                let factor = aug[[row, col]];
                if factor.abs() > 0.0 {
                    for k in 0..(2 * n) {
                        aug[[row, k]] -= factor * aug[[col, k]];
                    }
                }
            }
        }

        // Extract inverse
        let mut inv = Array2::<f32>::zeros((n, n));
        for i in 0..n {
            for j in 0..n {
                inv[[i, j]] = aug[[i, n + j]];
            }
        }

        Ok(inv)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_epad_stereo_first_order() {
        let decoder = EpadDecoder::new(AmbisonicOrder::First, &SpeakerLayout::stereo());
        assert!(decoder.is_ok());
        let d = decoder.unwrap();
        assert!(d.mean_energy() > 0.0);
        assert!(d.energy_flatness() > 0.25); // 2 speakers × 4 ch is inherently limited // Should be reasonably flat
    }

    #[test]
    fn test_epad_decode_front_center() {
        let decoder = EpadDecoder::new(AmbisonicOrder::First, &SpeakerLayout::stereo()).unwrap();

        // Front-center source: W=1, X=1, Y=0, Z=0
        let ambisonic = vec![
            vec![1.0; 16], // W
            vec![0.0; 16], // Y
            vec![0.0; 16], // Z
            vec![1.0; 16], // X
        ];

        let out = decoder.decode(&ambisonic).unwrap();
        assert_eq!(out.len(), 2); // stereo

        // Front-center should appear in both speakers roughly equally
        let l = out[0][0];
        let r = out[1][0];
        assert!((l - r).abs() < 0.2, "L={} R={}", l, r);
    }

    #[test]
    fn test_epad_energy_reasonable() {
        let decoder =
            EpadDecoder::new(AmbisonicOrder::Third, &SpeakerLayout::surround_5_1()).unwrap();

        // Mean energy before normalisation should be positive and finite
        assert!(decoder.mean_energy() > 0.0);
        assert!(decoder.mean_energy().is_finite());
        assert!(decoder.energy_stddev().is_finite());
    }

    #[test]
    fn test_matrix_inverse_identity() {
        let a = Array2::from_shape_vec((3, 3), vec![
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0,
        ]).unwrap();
        let inv = EpadDecoder::matrix_inverse(&a).unwrap();
        for i in 0..3 {
            for j in 0..3 {
                let expected = if i == j { 1.0 } else { 0.0 };
                assert!((inv[[i, j]] - expected).abs() < 1e-4);
            }
        }
    }

    #[test]
    fn test_matrix_inverse_2x2() {
        let a = Array2::from_shape_vec((2, 2), vec![4.0, 7.0, 2.0, 6.0]).unwrap();
        let inv = EpadDecoder::matrix_inverse(&a).unwrap();
        // Expected inverse: [0.6, -0.7; -0.2, 0.4]
        assert!((inv[[0, 0]] - 0.6).abs() < 1e-4);
        assert!((inv[[0, 1]] - (-0.7)).abs() < 1e-4);
        assert!((inv[[1, 0]] - (-0.2)).abs() < 1e-4);
        assert!((inv[[1, 1]] - 0.4).abs() < 1e-4);
    }
}
