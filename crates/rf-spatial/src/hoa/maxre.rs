//! Max-rE (maximum energy vector) weighting for Ambisonic decoding
//!
//! Max-rE weights attenuate higher spherical-harmonic orders so that the
//! reproduced sound field has the largest possible energy-vector magnitude.
//! This improves perceived localisation — especially for headphone/binaural
//! playback — at the cost of some spatial blur.
//!
//! Weights are standardised for the SN3D/ACN convention and are derived from
//! the Legendre polynomial `P_l(cos θ_E)` where `θ_E` is the optimal energy
//! angle for the truncation order.
//!
//! References:
//! * Daniel (2001) "Représentation de champs acoustiques"
//! * Zotter, Frank & Pomberger (2012) "Energy-Preserving Ambisonic Decoding"

use super::AmbisonicOrder;
use ndarray::Array2;

/// Max-rE weight table.
///
/// Row `N` (0-based) gives the per-degree weights for an Ambisonic signal
/// truncated at order `N+1`.  Column `l` (0-based) is the weight for SH
/// degree `l`.  Weights for `l > N` are zero.
///
/// Values are `P_l(cos θ_E)` where θ_E is the energy-vector maximising
/// angle for order `N`:
///   N=1 → θ=90.0°   N=2 → θ=55.5°   N=3 → θ=39.2°
///   N=4 → θ=30.6°   N=5 → θ=25.0°   N=6 → θ=21.3°
///   N=7 → θ=18.6°
const MAXRE_TABLE: [[f32; 8]; 7] = [
    // Order 1 (N=1):  [l=0,   l=1,   l=2,   l=3,   l=4,   l=5,   l=6,   l=7  ]
    [1.0,   0.577_350, 0.0,       0.0,       0.0,       0.0,       0.0,       0.0      ],
    // Order 2
    [1.0,   0.774_597, 0.400_000, 0.0,       0.0,       0.0,       0.0,       0.0      ],
    // Order 3
    [1.0,   0.861_136, 0.612_372, 0.306_186, 0.0,       0.0,       0.0,       0.0      ],
    // Order 4
    [1.0,   0.906_180, 0.731_109, 0.518_321, 0.248_213, 0.0,       0.0,       0.0      ],
    // Order 5
    [1.0,   0.935_414, 0.822_192, 0.671_693, 0.498_428, 0.224_863, 0.0,       0.0      ],
    // Order 6
    [1.0,   0.955_189, 0.888_459, 0.785_667, 0.653_720, 0.472_689, 0.208_658, 0.0      ],
    // Order 7
    [1.0,   0.969_200, 0.936_106, 0.872_187, 0.776_527, 0.651_218, 0.464_809, 0.202_651],
];

/// Max-rE weight applier.
#[derive(Debug, Clone)]
pub struct MaxReWeights {
    weights: Vec<f32>,
    order: AmbisonicOrder,
}

impl MaxReWeights {
    /// Create weight table for the given order.
    pub fn new(order: AmbisonicOrder) -> Self {
        let idx = order.as_usize().saturating_sub(1).min(MAXRE_TABLE.len() - 1);
        let num_channels = order.channel_count();
        let mut weights = vec![0.0f32; num_channels];

        for ch in 0..num_channels {
            let (l, _m) = super::acn_to_order_degree(ch);
            let l_usize = l as usize;
            weights[ch] = if l_usize < MAXRE_TABLE[idx].len() {
                MAXRE_TABLE[idx][l_usize]
            } else {
                0.0
            };
        }

        Self { weights, order }
    }

    /// Get the Max-rE weight for a specific ACN channel.
    #[inline]
    pub fn weight(&self, acn: usize) -> f32 {
        self.weights.get(acn).copied().unwrap_or(0.0)
    }

    /// Get the weight for a given spherical-harmonic degree `l`.
    #[inline]
    pub fn weight_for_degree(&self, l: usize) -> f32 {
        let idx = self.order.as_usize().saturating_sub(1).min(MAXRE_TABLE.len() - 1);
        MAXRE_TABLE[idx].get(l).copied().unwrap_or(0.0)
    }

    /// Apply weights to an Ambisonic channel vector in-place.
    pub fn apply_to_signal(&self, channels: &mut [f32]) {
        for (ch, w) in self.weights.iter().enumerate() {
            if ch < channels.len() {
                channels[ch] *= w;
            }
        }
    }

    /// Apply weights to a decoding matrix `[speakers × channels]` in-place.
    ///
    /// Each column (Ambisonic channel) is multiplied by the Max-rE weight
    /// for that channel's SH degree.
    pub fn apply_to_decoder_matrix(&self, matrix: &mut Array2<f32>) {
        let ncols = matrix.ncols();
        for _ch in 0..ncols.min(self.weights.len()) {
            // Per-column scaling happens in the manual loop below.
        }
        // Manual column-wise iteration to avoid ndarray axis confusion
        let (nrows, ncols) = matrix.dim();
        for r in 0..nrows {
            for c in 0..ncols.min(self.weights.len()) {
                matrix[[r, c]] *= self.weights[c];
            }
        }
    }

    /// Build a diagonal weight matrix as `Array2`.
    pub fn as_diagonal_matrix(&self) -> Array2<f32> {
        let n = self.weights.len();
        let mut diag = Array2::<f32>::zeros((n, n));
        for i in 0..n {
            diag[[i, i]] = self.weights[i];
        }
        diag
    }

    /// Per-channel weights slice.
    #[inline]
    pub fn weights(&self) -> &[f32] {
        &self.weights
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_maxre_first_order() {
        let w = MaxReWeights::new(AmbisonicOrder::First);
        assert!((w.weight_for_degree(0) - 1.0).abs() < 1e-5);
        assert!((w.weight_for_degree(1) - 0.577350).abs() < 1e-5);
    }

    #[test]
    fn test_maxre_fifth_order() {
        let w = MaxReWeights::new(AmbisonicOrder::Fifth);
        assert!((w.weight_for_degree(0) - 1.0).abs() < 1e-5);
        assert!((w.weight_for_degree(1) - 0.935414).abs() < 1e-5);
        assert!((w.weight_for_degree(5) - 0.224863).abs() < 1e-5);
    }

    #[test]
    fn test_maxre_channel_weights_match_degree() {
        let w = MaxReWeights::new(AmbisonicOrder::Third);
        // ACN 0 → l=0, ACN 1→3 → l=1, ACN 4→8 → l=2, ACN 9→15 → l=3
        assert!((w.weight(0) - 1.0).abs() < 1e-5);
        assert!((w.weight(1) - w.weight_for_degree(1)).abs() < 1e-5);
        assert!((w.weight(4) - w.weight_for_degree(2)).abs() < 1e-5);
        assert!((w.weight(9) - w.weight_for_degree(3)).abs() < 1e-5);
    }

    #[test]
    fn test_apply_to_signal() {
        let w = MaxReWeights::new(AmbisonicOrder::Second);
        let mut sig = vec![1.0f32; 9];
        w.apply_to_signal(&mut sig);
        assert!((sig[0] - 1.0).abs() < 1e-5);
        assert!((sig[1] - 0.774597).abs() < 1e-5);
        assert!((sig[4] - 0.400000).abs() < 1e-5);
    }
}
