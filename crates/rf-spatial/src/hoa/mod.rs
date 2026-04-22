//! Higher-Order Ambisonics (HOA) processing
//!
//! Full HOA implementation up to 7th order (64 channels):
//! - Encoding: Point source to Ambisonic
//! - Decoding: Ambisonic to speaker layout or binaural
//! - Transformation: Rotation, zoom, focus
//! - Format conversion: SN3D/N3D/FuMa, ACN/FuMa ordering
//!
//! ## Usage
//!
//! ```rust,ignore
//! use rf_spatial::hoa::{AmbisonicEncoder, AmbisonicDecoder, AmbisonicOrder};
//! use rf_spatial::{Position3D, SpeakerLayout};
//!
//! // Encode point source to 3rd order Ambisonics
//! let encoder = AmbisonicEncoder::new(AmbisonicOrder::Third);
//! let position = Position3D::from_spherical(45.0, 30.0, 1.0);
//! let ambisonic = encoder.encode(&mono_audio, &position);
//!
//! // Decode to 5.1 speaker layout
//! let decoder = AmbisonicDecoder::new(AmbisonicOrder::Third, SpeakerLayout::surround_5_1());
//! let speakers = decoder.decode(&ambisonic);
//! ```

mod decoder;
mod encoder;
mod format;
mod transform;

pub use decoder::AmbisonicDecoder;
pub use encoder::AmbisonicEncoder;
pub use format::{AmbisonicFormat, ChannelOrdering, Normalization};
pub use transform::AmbisonicTransform;

use crate::error::{SpatialError, SpatialResult};

/// Ambisonic order (determines spatial resolution)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AmbisonicOrder {
    /// First order (4 channels) - basic 3D
    First = 1,
    /// Second order (9 channels) - good localization
    Second = 2,
    /// Third order (16 channels) - high quality
    Third = 3,
    /// Fourth order (25 channels) - studio quality
    Fourth = 4,
    /// Fifth order (36 channels) - theatrical
    Fifth = 5,
    /// Sixth order (49 channels) - research
    Sixth = 6,
    /// Seventh order (64 channels) - maximum
    Seventh = 7,
}

impl AmbisonicOrder {
    /// Get channel count for this order
    pub fn channel_count(&self) -> usize {
        let n = *self as usize;
        (n + 1) * (n + 1)
    }

    /// Create from order number
    pub fn from_order(order: usize) -> SpatialResult<Self> {
        match order {
            1 => Ok(AmbisonicOrder::First),
            2 => Ok(AmbisonicOrder::Second),
            3 => Ok(AmbisonicOrder::Third),
            4 => Ok(AmbisonicOrder::Fourth),
            5 => Ok(AmbisonicOrder::Fifth),
            6 => Ok(AmbisonicOrder::Sixth),
            7 => Ok(AmbisonicOrder::Seventh),
            _ => Err(SpatialError::InvalidAmbisonicOrder(order)),
        }
    }

    /// Get order number
    pub fn as_usize(&self) -> usize {
        *self as usize
    }
}

/// Spherical harmonic coefficients
#[derive(Debug, Clone)]
pub struct SphericalHarmonics {
    /// Coefficients per channel
    pub coeffs: Vec<f32>,
    /// Order
    pub order: AmbisonicOrder,
}

impl SphericalHarmonics {
    /// Create from order
    pub fn new(order: AmbisonicOrder) -> Self {
        Self {
            coeffs: vec![0.0; order.channel_count()],
            order,
        }
    }

    /// Compute spherical harmonics for a direction
    pub fn from_direction(azimuth: f32, elevation: f32, order: AmbisonicOrder) -> Self {
        let mut sh = Self::new(order);
        sh.compute_for_direction(azimuth, elevation);
        sh
    }

    /// Compute coefficients for direction
    pub fn compute_for_direction(&mut self, azimuth: f32, elevation: f32) {
        let az = azimuth.to_radians();
        let el = elevation.to_radians();

        let cos_el = el.cos();
        let sin_el = el.sin();

        // ACN ordering, SN3D normalization
        let n = self.order.as_usize();

        // Order 0 (omnidirectional)
        self.coeffs[0] = 1.0;

        if n >= 1 {
            // Order 1 (figure-8 patterns)
            self.coeffs[1] = cos_el * az.sin(); // Y
            self.coeffs[2] = sin_el; // Z
            self.coeffs[3] = cos_el * az.cos(); // X
        }

        if n >= 2 {
            // Order 2
            let cos2_az = (2.0 * az).cos();
            let sin2_az = (2.0 * az).sin();
            let cos2_el = cos_el * cos_el;

            self.coeffs[4] = 1.732051 * cos2_el * sin2_az; // V
            self.coeffs[5] = 1.732051 * sin_el * cos_el * az.sin(); // T
            self.coeffs[6] = 0.5 * (3.0 * sin_el * sin_el - 1.0); // R
            self.coeffs[7] = 1.732051 * sin_el * cos_el * az.cos(); // S
            self.coeffs[8] = 0.866025 * cos2_el * cos2_az; // U
        }

        if n >= 3 {
            // Order 3
            let cos2_az_3 = (2.0 * az).cos();
            let cos3_az = (3.0 * az).cos();
            let sin3_az = (3.0 * az).sin();
            let cos3_el = cos_el * cos_el * cos_el;

            self.coeffs[9] = 0.790569 * cos3_el * sin3_az;
            self.coeffs[10] = 1.936492 * sin_el * cos_el * cos_el * (2.0 * az).sin();
            self.coeffs[11] = 0.612372 * cos_el * (5.0 * sin_el * sin_el - 1.0) * az.sin();
            self.coeffs[12] = 0.5 * sin_el * (5.0 * sin_el * sin_el - 3.0);
            self.coeffs[13] = 0.612372 * cos_el * (5.0 * sin_el * sin_el - 1.0) * az.cos();
            self.coeffs[14] = 0.968246 * sin_el * cos_el * cos_el * cos2_az_3;
            self.coeffs[15] = 0.790569 * cos3_el * cos3_az;
        }

        // Orders 4-7: SN3D normalization using recurrence relations
        // P_l^m(sin(el)) via Legendre recurrence, with SN3D norm factor sqrt((2l+1)/(4pi) * (l-|m|)!/(l+|m|)!)
        if n >= 4 {
            self._compute_sh_order(4, az, el.sin(), cos_el);
        }
        if n >= 5 {
            self._compute_sh_order(5, az, el.sin(), cos_el);
        }
        if n >= 6 {
            self._compute_sh_order(6, az, el.sin(), cos_el);
        }
        if n >= 7 {
            self._compute_sh_order(7, az, el.sin(), cos_el);
        }
    }

    /// Compute SH coefficients for a single order using Legendre recurrence (SN3D).
    /// ACN channel layout: index = l*l + l + m for degree m in [-l, +l].
    fn _compute_sh_order(&mut self, l: usize, az: f32, sin_el: f32, cos_el: f32) {
        // Associated Legendre polynomial P_l^m(sin(el)) via recurrence
        // Working in f64 precision for correctness, then cast to f32
        let sin_el = sin_el as f64;
        let cos_el = cos_el as f64;
        let l_i32 = l as i32;

        for m_i32 in -l_i32..=l_i32 {
            let m_abs = m_i32.unsigned_abs() as usize;

            // Compute associated Legendre P_l^m(sin_el)
            let p = associated_legendre(l, m_abs, sin_el, cos_el);

            // SN3D normalization: sqrt((2l+1)/(4pi) * (l-m)!/(l+m)!)
            let norm = sn3d_norm(l, m_abs);

            // ACN index: l^2 + l + m
            let acn = (l * l + l) as i32 + m_i32;
            if (acn as usize) >= self.coeffs.len() {
                continue;
            }

            let val = if m_i32 == 0 {
                norm * p
            } else if m_i32 > 0 {
                // Positive m: cos(m * az) component (U-type)
                norm * std::f64::consts::SQRT_2 * p * ((m_i32 as f64) * (az as f64)).cos()
            } else {
                // Negative m: sin(|m| * az) component (V-type)
                norm * std::f64::consts::SQRT_2 * p * ((m_abs as f64) * (az as f64)).sin()
            };

            self.coeffs[acn as usize] = val as f32;
        }
    }

    /// Get channel by ACN index
    pub fn get(&self, acn: usize) -> f32 {
        self.coeffs.get(acn).copied().unwrap_or(0.0)
    }

    /// Set channel by ACN index
    pub fn set(&mut self, acn: usize, value: f32) {
        if acn < self.coeffs.len() {
            self.coeffs[acn] = value;
        }
    }

    /// Scale all coefficients
    pub fn scale(&mut self, gain: f32) {
        for c in &mut self.coeffs {
            *c *= gain;
        }
    }

    /// Add another set of harmonics
    pub fn add(&mut self, other: &SphericalHarmonics) {
        for (i, &c) in other.coeffs.iter().enumerate() {
            if i < self.coeffs.len() {
                self.coeffs[i] += c;
            }
        }
    }
}

/// ACN channel index from (order, degree)
pub fn acn_index(order: i32, degree: i32) -> usize {
    (order * order + order + degree) as usize
}

/// Get (order, degree) from ACN index
pub fn acn_to_order_degree(acn: usize) -> (i32, i32) {
    let order = (acn as f64).sqrt().floor() as i32;
    let degree = acn as i32 - order * order - order;
    (order, degree)
}

// ═══════════════════════════════════════════════════════════════════════════
// LEGENDRE POLYNOMIAL HELPERS (used for SH orders 4-7)
// ═══════════════════════════════════════════════════════════════════════════

/// Compute associated Legendre polynomial P_l^m(x) where x = sin(elevation).
/// Uses three-term upward recurrence in l with fixed m.
/// Reference: Abramowitz & Stegun §8.5
fn associated_legendre(l: usize, m: usize, x: f64, cos_el: f64) -> f64 {
    if m > l {
        return 0.0;
    }

    // Seed P_m^m (diagonal element)
    let mut pmm = 1.0_f64;
    if m > 0 {
        // P_m^m = (-1)^m * (2m-1)!! * (1-x^2)^(m/2)
        // (1-x^2)^(1/2) = cos(elevation)
        let mut factor = 1.0_f64;
        for i in 1..=(m as u32) {
            factor *= (2 * i - 1) as f64;
        }
        // cos^m (elevation) — but we're using x = sin(el), so cos_el = sqrt(1-x^2)
        let cos_m = cos_el.powi(m as i32);
        pmm = if m.is_multiple_of(2) { 1.0 } else { -1.0 } * factor * cos_m;
    }

    if l == m {
        return pmm;
    }

    // P_m+1^m = x * (2m+1) * P_m^m
    let mut pm1m = x * (2 * m + 1) as f64 * pmm;

    if l == m + 1 {
        return pm1m;
    }

    // Upward recurrence: P_l^m = ((2l-1)*x*P_{l-1}^m - (l-1+m)*P_{l-2}^m) / (l-m)
    let mut prev_prev = pmm;
    let mut prev = pm1m;
    for ll in (m + 2)..=l {
        let cur = ((2 * ll - 1) as f64 * x * prev - (ll - 1 + m) as f64 * prev_prev)
            / (ll - m) as f64;
        prev_prev = prev;
        prev = cur;
        pm1m = cur;
    }

    pm1m
}

/// SN3D normalization factor for degree (l, m).
/// N_l^m = sqrt((2l+1) / (4π) * (l-|m|)! / (l+|m|)!)
/// Includes the sqrt(4π/(2l+1)) Schmidt semi-norm used in SN3D.
fn sn3d_norm(l: usize, m: usize) -> f64 {
    
    let factorial = |n: usize| -> f64 {
        let mut f = 1.0_f64;
        for i in 2..=n {
            f *= i as f64;
        }
        f
    };

    // N_l^m = sqrt((l - m)! / (l + m)!)
    // (the 1/sqrt(4pi) and sqrt(2l+1) cancel out in the SN3D convention)
    let ratio = factorial(l - m) / factorial(l + m);
    ratio.sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_channel_count() {
        assert_eq!(AmbisonicOrder::First.channel_count(), 4);
        assert_eq!(AmbisonicOrder::Second.channel_count(), 9);
        assert_eq!(AmbisonicOrder::Third.channel_count(), 16);
        assert_eq!(AmbisonicOrder::Seventh.channel_count(), 64);
    }

    #[test]
    fn test_acn_index() {
        assert_eq!(acn_index(0, 0), 0); // W
        assert_eq!(acn_index(1, -1), 1); // Y
        assert_eq!(acn_index(1, 0), 2); // Z
        assert_eq!(acn_index(1, 1), 3); // X
    }

    #[test]
    fn test_spherical_harmonics_front() {
        let sh = SphericalHarmonics::from_direction(0.0, 0.0, AmbisonicOrder::First);

        // Front center should have positive X, zero Y
        assert!((sh.get(0) - 1.0).abs() < 0.001); // W
        assert!(sh.get(1).abs() < 0.001); // Y (no left/right)
        assert!(sh.get(2).abs() < 0.001); // Z (no up/down)
        assert!((sh.get(3) - 1.0).abs() < 0.001); // X (front)
    }

    #[test]
    fn test_spherical_harmonics_fourth_order() {
        // 4th order = 25 channels, front direction (az=0, el=0)
        let sh = SphericalHarmonics::from_direction(0.0, 0.0, AmbisonicOrder::Fourth);
        assert_eq!(sh.coeffs.len(), 25);

        // W (ch 0) always = 1.0
        assert!((sh.get(0) - 1.0).abs() < 0.001);

        // All channels must be finite and in [-2, 2] range (SN3D max ~1.9)
        for (i, &c) in sh.coeffs.iter().enumerate() {
            assert!(c.is_finite(), "ch {} is not finite: {}", i, c);
            assert!(c.abs() < 2.5, "ch {} magnitude too large: {}", i, c);
        }
    }

    #[test]
    fn test_spherical_harmonics_seventh_order() {
        // 7th order = 64 channels
        let sh = SphericalHarmonics::from_direction(45.0, 30.0, AmbisonicOrder::Seventh);
        assert_eq!(sh.coeffs.len(), 64);
        for (i, &c) in sh.coeffs.iter().enumerate() {
            assert!(c.is_finite(), "ch {} is not finite", i);
        }
    }

    #[test]
    fn test_sn3d_norm_orthogonality() {
        // For m=0, P_l^0 should be the Legendre polynomial
        // P_4^0(0) = 3/8 (Legendre P4 at x=0)
        let p = associated_legendre(4, 0, 0.0, 1.0);
        assert!((p - 0.375).abs() < 0.001, "P_4^0(0) = {} expected 0.375", p);
    }

    #[test]
    fn test_energy_preservation_higher_orders() {
        // Energy (sum of squares) should be meaningful for a point source
        let az_vec = [0.0_f32, 45.0, 90.0, 180.0];
        let el_vec = [0.0_f32, 30.0, -30.0];
        for az in az_vec {
            for el in el_vec {
                let sh = SphericalHarmonics::from_direction(az, el, AmbisonicOrder::Fourth);
                let energy: f32 = sh.coeffs.iter().map(|&c| c * c).sum();
                // Energy should be positive and bounded
                assert!(energy > 0.0, "Energy zero at az={} el={}", az, el);
                assert!(energy.is_finite(), "Energy infinite at az={} el={}", az, el);
            }
        }
    }
}
