//! Ambisonic format conversion - normalization and channel ordering

use super::AmbisonicOrder;

/// Normalization scheme
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Normalization {
    /// SN3D (Schmidt semi-normalized) - AmbiX standard
    SN3D,
    /// N3D (fully normalized)
    N3D,
    /// FuMa (Furse-Malham) - legacy
    FuMa,
    /// MaxN (maximum normalized)
    MaxN,
}

/// Channel ordering
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChannelOrdering {
    /// ACN (Ambisonic Channel Number) - AmbiX standard
    ACN,
    /// FuMa ordering - legacy
    FuMa,
    /// SID (Single Index Designation)
    SID,
}

/// Complete Ambisonic format specification
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AmbisonicFormat {
    /// Normalization scheme
    pub normalization: Normalization,
    /// Channel ordering
    pub ordering: ChannelOrdering,
}

impl AmbisonicFormat {
    /// AmbiX format (ACN + SN3D) - modern standard
    pub fn ambix() -> Self {
        Self {
            normalization: Normalization::SN3D,
            ordering: ChannelOrdering::ACN,
        }
    }

    /// FuMa format (legacy)
    pub fn fuma() -> Self {
        Self {
            normalization: Normalization::FuMa,
            ordering: ChannelOrdering::FuMa,
        }
    }

    /// N3D + ACN (common in research)
    pub fn n3d_acn() -> Self {
        Self {
            normalization: Normalization::N3D,
            ordering: ChannelOrdering::ACN,
        }
    }
}

impl Default for AmbisonicFormat {
    fn default() -> Self {
        Self::ambix()
    }
}

/// Format converter
pub struct FormatConverter {
    /// Source format
    source: AmbisonicFormat,
    /// Target format
    target: AmbisonicFormat,
    /// Order
    order: AmbisonicOrder,
    /// Normalization conversion gains
    norm_gains: Vec<f32>,
    /// Channel reordering map (source index -> target index)
    reorder_map: Vec<usize>,
}

impl FormatConverter {
    /// Create new converter
    pub fn new(source: AmbisonicFormat, target: AmbisonicFormat, order: AmbisonicOrder) -> Self {
        let _num_channels = order.channel_count();
        let norm_gains =
            Self::compute_norm_gains(source.normalization, target.normalization, order);
        let reorder_map = Self::compute_reorder_map(source.ordering, target.ordering, order);

        Self {
            source,
            target,
            order,
            norm_gains,
            reorder_map,
        }
    }

    /// Convert format
    pub fn convert(&self, input: &[Vec<f32>]) -> Vec<Vec<f32>> {
        let num_channels = self.order.channel_count();
        let samples = input.get(0).map(|v| v.len()).unwrap_or(0);
        let mut output = vec![vec![0.0f32; samples]; num_channels];

        for (src_ch, &target_ch) in self.reorder_map.iter().enumerate() {
            if src_ch < input.len() && target_ch < output.len() {
                let gain = self.norm_gains.get(src_ch).copied().unwrap_or(1.0);
                for (i, &s) in input[src_ch].iter().enumerate() {
                    output[target_ch][i] = s * gain;
                }
            }
        }

        output
    }

    /// Compute normalization conversion gains
    fn compute_norm_gains(
        source: Normalization,
        target: Normalization,
        order: AmbisonicOrder,
    ) -> Vec<f32> {
        let num_channels = order.channel_count();
        let mut gains = vec![1.0f32; num_channels];

        if source == target {
            return gains;
        }

        // Get source and target normalization factors
        let source_factors = Self::norm_factors(source, order);
        let target_factors = Self::norm_factors(target, order);

        for ch in 0..num_channels {
            if source_factors[ch].abs() > 1e-10 {
                gains[ch] = target_factors[ch] / source_factors[ch];
            }
        }

        gains
    }

    /// Get normalization factors for each channel
    fn norm_factors(norm: Normalization, order: AmbisonicOrder) -> Vec<f32> {
        let num_channels = order.channel_count();
        let mut factors = vec![1.0f32; num_channels];

        match norm {
            Normalization::SN3D => {
                // SN3D normalization factors
                for ch in 0..num_channels {
                    let (l, m) = super::acn_to_order_degree(ch);
                    factors[ch] = Self::sn3d_factor(l, m);
                }
            }
            Normalization::N3D => {
                // N3D = SN3D * sqrt(2l+1)
                for ch in 0..num_channels {
                    let (l, m) = super::acn_to_order_degree(ch);
                    factors[ch] = Self::sn3d_factor(l, m) * ((2 * l + 1) as f32).sqrt();
                }
            }
            Normalization::FuMa => {
                // FuMa factors (first order only accurate here)
                factors[0] = 1.0 / 2.0_f32.sqrt(); // W
                if num_channels > 1 {
                    factors[1] = 1.0;
                } // Y
                if num_channels > 2 {
                    factors[2] = 1.0;
                } // Z
                if num_channels > 3 {
                    factors[3] = 1.0;
                } // X
                  // Higher orders have different FuMa factors
            }
            Normalization::MaxN => {
                // MaxN: all channels have max value of 1
                for ch in 0..num_channels {
                    let (l, _m) = super::acn_to_order_degree(ch);
                    factors[ch] = 1.0 / Self::max_sh_value(l);
                }
            }
        }

        factors
    }

    /// SN3D normalization factor
    fn sn3d_factor(l: i32, m: i32) -> f32 {
        let m_abs = m.abs();
        let delta = if m == 0 { 1.0 } else { 0.0 };

        let num = (2.0 - delta) * Self::factorial((l - m_abs) as u32) as f32;
        let den = Self::factorial((l + m_abs) as u32) as f32;

        (num / den).sqrt()
    }

    /// Maximum value of spherical harmonic of order l
    fn max_sh_value(l: i32) -> f32 {
        // Approximate maximum
        ((2 * l + 1) as f32 / (4.0 * std::f32::consts::PI)).sqrt()
    }

    /// Factorial
    fn factorial(n: u32) -> u32 {
        (1..=n).product::<u32>().max(1)
    }

    /// Compute channel reordering map
    fn compute_reorder_map(
        source: ChannelOrdering,
        target: ChannelOrdering,
        order: AmbisonicOrder,
    ) -> Vec<usize> {
        let num_channels = order.channel_count();

        if source == target {
            return (0..num_channels).collect();
        }

        let source_to_acn = Self::ordering_to_acn(source, order);
        let acn_to_target = Self::acn_to_ordering(target, order);

        let mut map = vec![0usize; num_channels];
        for (src_idx, &acn) in source_to_acn.iter().enumerate() {
            if acn < acn_to_target.len() {
                map[src_idx] = acn_to_target[acn];
            }
        }

        map
    }

    /// Get mapping from ordering to ACN
    fn ordering_to_acn(ordering: ChannelOrdering, order: AmbisonicOrder) -> Vec<usize> {
        let num_channels = order.channel_count();

        match ordering {
            ChannelOrdering::ACN => (0..num_channels).collect(),
            ChannelOrdering::FuMa => {
                // FuMa order: W, X, Y, Z, R, S, T, U, V, ...
                // ACN order: W, Y, Z, X, V, T, R, S, U, ...
                let mut map = vec![0usize; num_channels];
                let fuma_to_acn = [0, 3, 1, 2, 8, 6, 4, 5, 7]; // First and second order

                for (fuma, &acn) in fuma_to_acn.iter().enumerate().take(num_channels) {
                    map[fuma] = acn;
                }

                // Higher orders default to identity
                for i in fuma_to_acn.len()..num_channels {
                    map[i] = i;
                }

                map
            }
            ChannelOrdering::SID => {
                // SID is same as ACN for most practical purposes
                (0..num_channels).collect()
            }
        }
    }

    /// Get mapping from ACN to ordering
    fn acn_to_ordering(ordering: ChannelOrdering, order: AmbisonicOrder) -> Vec<usize> {
        let num_channels = order.channel_count();
        let to_acn = Self::ordering_to_acn(ordering, order);

        // Invert the mapping
        let mut map = vec![0usize; num_channels];
        for (idx, &acn) in to_acn.iter().enumerate() {
            if acn < map.len() {
                map[acn] = idx;
            }
        }

        map
    }
}

/// Convert between AmbiX and FuMa
pub fn ambix_to_fuma(input: &[Vec<f32>], order: AmbisonicOrder) -> Vec<Vec<f32>> {
    let converter = FormatConverter::new(AmbisonicFormat::ambix(), AmbisonicFormat::fuma(), order);
    converter.convert(input)
}

/// Convert between FuMa and AmbiX
pub fn fuma_to_ambix(input: &[Vec<f32>], order: AmbisonicOrder) -> Vec<Vec<f32>> {
    let converter = FormatConverter::new(AmbisonicFormat::fuma(), AmbisonicFormat::ambix(), order);
    converter.convert(input)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_identity_conversion() {
        let converter = FormatConverter::new(
            AmbisonicFormat::ambix(),
            AmbisonicFormat::ambix(),
            AmbisonicOrder::First,
        );

        let input = vec![vec![1.0; 10], vec![0.5; 10], vec![0.3; 10], vec![0.7; 10]];

        let output = converter.convert(&input);

        for ch in 0..4 {
            for s in 0..10 {
                assert!((output[ch][s] - input[ch][s]).abs() < 0.001);
            }
        }
    }

    #[test]
    fn test_fuma_ambix_roundtrip() {
        let input = vec![vec![1.0; 10], vec![0.5; 10], vec![0.3; 10], vec![0.7; 10]];

        let fuma = ambix_to_fuma(&input, AmbisonicOrder::First);
        let back = fuma_to_ambix(&fuma, AmbisonicOrder::First);

        for ch in 0..4 {
            for s in 0..10 {
                assert!(
                    (back[ch][s] - input[ch][s]).abs() < 0.01,
                    "Channel {} sample {}: {} vs {}",
                    ch,
                    s,
                    back[ch][s],
                    input[ch][s]
                );
            }
        }
    }
}
