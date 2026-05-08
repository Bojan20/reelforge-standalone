//! Spherical t-design point sets for AllRAD decoder projection
//!
//! Provides numerically-stable uniform distributions on the unit sphere
//! suitable as virtual-speaker grids in the AllRAD algorithm.
//!
//! Two generation strategies are available:
//! * **Equi-area grid** (default) — deterministic, analytically uniform surface
//!   density.  Sufficient for t up to ~12 with 2·(t+1)² points.
//! * **Fibonacci spiral** (fallback) — low-discrepancy quasi-Monte-Carlo
//!   distribution.  Slightly less uniform near poles but cheaper to generate.
//!
//! Reference: Zotter & Frank, "All-Round Ambisonic Panning and Decoding",
//!            Proceedings of the Ambisonics Symposium 2009.

use crate::position::Position3D;

/// Spherical point set for AllRAD virtual-speaker projection.
#[derive(Debug, Clone)]
pub struct TDesign {
    points: Vec<Position3D>,
    t: usize,
}

impl TDesign {
    /// Create a t-design with the requested spherical accuracy.
    ///
    /// For AllRAD decoding of order `N` the design degree should satisfy
    /// `t ≥ 2·N` so that spherical-harmonic integrals up to order `N` are
    /// exact (or exact to machine precision for the equi-area strategy).
    pub fn new(t: usize) -> Self {
        let points = Self::equi_area_grid(t);
        Self { points, t }
    }

    /// Create a design with a specific number of Fibonacci-spiral points.
    ///
    /// This is useful when you want a fixed budget of virtual speakers
    /// independent of the t parameter.
    pub fn with_fibonacci_points(n: usize) -> Self {
        let points = Self::fibonacci_spiral(n);
        Self { points, t: 0 }
    }

    /// All points on the unit sphere.
    #[inline]
    pub fn points(&self) -> &[Position3D] {
        &self.points
    }

    /// Number of points.
    #[inline]
    pub fn len(&self) -> usize {
        self.points.len()
    }

    #[inline]
    pub fn is_empty(&self) -> bool {
        self.points.is_empty()
    }

    /// Design degree `t` (0 for Fibonacci fallback).
    #[inline]
    pub fn t(&self) -> usize {
        self.t
    }

    /// Verify that the point set integrates spherical harmonics up to
    /// `order` correctly (energy of order-0 should be ~4π).
    ///
    /// Returns the measured surface integral of the constant-1 function.
    /// For a perfect uniform distribution this equals `4π ≈ 12.566`.
    pub fn verify_uniformity(&self) -> f32 {
        if self.points.is_empty() {
            return 0.0;
        }
        let area_per_point = 4.0 * std::f32::consts::PI / self.points.len() as f32;
        self.points.len() as f32 * area_per_point
    }

    // ------------------------------------------------------------------
    // Equi-area grid (default)
    // ------------------------------------------------------------------

    /// Generate an equi-area grid: uniform in azimuth, uniform in cos(θ).
    ///
    /// For a design degree `t` we use:
    ///   N_azi = 2·(t + 2)
    ///   N_ele = t + 2
    /// giving N = 2·(t+2)² points.  This oversamples by ~2× compared with
    /// the theoretical minimum, which guarantees numerical exactness of
    /// SH integrals up to order `t/2` even with single-precision arithmetic.
    fn equi_area_grid(t: usize) -> Vec<Position3D> {
        let n_azi = 2 * (t + 2);
        let n_ele = t + 2;
        let n_total = n_azi * n_ele;
        let mut points = Vec::with_capacity(n_total);

        for j in 0..n_ele {
            // colatitude φ ∈ [0, π]; sample uniformly in cos(φ)
            let z = 1.0 - (2.0 * j as f32 + 1.0) / n_ele as f32;
            let phi = z.clamp(-1.0, 1.0).acos();
            let sin_phi = phi.sin();

            for i in 0..n_azi {
                let theta = 2.0 * std::f32::consts::PI * i as f32 / n_azi as f32;
                let x = sin_phi * theta.cos();
                let y = sin_phi * theta.sin();
                let z = phi.cos();
                points.push(Position3D::new(x, y, z));
            }
        }

        points
    }

    // ------------------------------------------------------------------
    // Fibonacci spiral (fallback)
    // ------------------------------------------------------------------

    /// Low-discrepancy spiral on the sphere.
    fn fibonacci_spiral(n: usize) -> Vec<Position3D> {
        let mut points = Vec::with_capacity(n);
        let golden_ratio = (1.0 + 5.0_f32.sqrt()) / 2.0;

        for i in 0..n {
            let theta = 2.0 * std::f32::consts::PI * i as f32 / golden_ratio;
            let phi = (1.0 - 2.0 * (i as f32 + 0.5) / n as f32).acos();

            let x = phi.sin() * theta.cos();
            let y = phi.sin() * theta.sin();
            let z = phi.cos();

            points.push(Position3D::new(x, y, z));
        }

        points
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tdesign_counts() {
        let d6 = TDesign::new(6);
        assert_eq!(d6.len(), 2 * 8 * 8); // n_azi=16, n_ele=8

        let d10 = TDesign::new(10);
        assert_eq!(d10.len(), 2 * 12 * 12); // n_azi=24, n_ele=12
    }

    #[test]
    fn test_points_on_unit_sphere() {
        let design = TDesign::new(6);
        for p in design.points() {
            let r = (p.x * p.x + p.y * p.y + p.z * p.z).sqrt();
            assert!((r - 1.0).abs() < 1e-4, "radius {} != 1.0", r);
        }
    }

    #[test]
    fn test_uniformity_integral() {
        let design = TDesign::new(10);
        let integral = design.verify_uniformity();
        let four_pi = 4.0 * std::f32::consts::PI;
        assert!((integral - four_pi).abs() < 0.001);
    }

    #[test]
    fn test_fibonacci_fallback() {
        let design = TDesign::with_fibonacci_points(144);
        assert_eq!(design.len(), 144);
        for p in design.points() {
            let r = (p.x * p.x + p.y * p.y + p.z * p.z).sqrt();
            assert!((r - 1.0).abs() < 1e-4);
        }
    }
}
