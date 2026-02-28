//! GEG-3: Escalation Curves — 5 curve types for energy scaling.
//!
//! Extends the existing 4-curve EscalationCurveType with GEG-specific
//! CappedExponential and Step curves.

use serde::{Deserialize, Serialize};

/// 5 GEG escalation curve types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum GegCurveType {
    /// f(x) = x
    Linear,
    /// ln(1 + x*e) / ln(1+e) — fast start, diminishing returns
    Logarithmic,
    /// (e^(x*2) - 1) / (e^2 - 1) — slow start, rapid growth
    Exponential,
    /// Exponential with hard cap at 1.0 — prevents overshoot
    CappedExponential,
    /// Step function with 5 discrete levels
    Step,
    /// Smoothstep: 3x² - 2x³ — S-shaped
    SCurve,
}

/// Evaluates GEG escalation curves.
pub struct GegEscalationCurve;

impl GegEscalationCurve {
    /// Evaluate the curve at input value x (≥ 0.0).
    /// Output: scaled value, typically 0.0–1.0 but can exceed for Linear/Exponential.
    pub fn evaluate(x: f64, curve: GegCurveType) -> f64 {
        let x = x.max(0.0);
        match curve {
            GegCurveType::Linear => x,

            GegCurveType::Logarithmic => {
                let e = std::f64::consts::E;
                (1.0 + x * e).ln() / (1.0 + e).ln()
            }

            GegCurveType::Exponential => {
                let scale = (2.0_f64).exp() - 1.0;
                ((x * 2.0).exp() - 1.0) / scale
            }

            GegCurveType::CappedExponential => {
                let scale = (2.0_f64).exp() - 1.0;
                let raw = ((x * 2.0).exp() - 1.0) / scale;
                raw.min(1.0)
            }

            GegCurveType::Step => {
                // 5 discrete levels: 0.0, 0.25, 0.50, 0.75, 1.0
                if x < 0.2 {
                    0.0
                } else if x < 0.4 {
                    0.25
                } else if x < 0.6 {
                    0.50
                } else if x < 0.8 {
                    0.75
                } else {
                    1.0
                }
            }

            GegCurveType::SCurve => {
                if x <= 1.0 {
                    x * x * (3.0 - 2.0 * x)
                } else {
                    1.0 + (x - 1.0)
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_linear_identity() {
        assert!((GegEscalationCurve::evaluate(0.0, GegCurveType::Linear)).abs() < 1e-10);
        assert!((GegEscalationCurve::evaluate(0.5, GegCurveType::Linear) - 0.5).abs() < 1e-10);
        assert!((GegEscalationCurve::evaluate(1.0, GegCurveType::Linear) - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_logarithmic_concave() {
        let mid = GegEscalationCurve::evaluate(0.5, GegCurveType::Logarithmic);
        assert!(mid > 0.5, "Log should be above linear at midpoint: {mid}");
    }

    #[test]
    fn test_exponential_convex() {
        let mid = GegEscalationCurve::evaluate(0.5, GegCurveType::Exponential);
        assert!(mid < 0.5, "Exp should be below linear at midpoint: {mid}");
    }

    #[test]
    fn test_capped_exponential_never_exceeds_one() {
        assert!(GegEscalationCurve::evaluate(0.5, GegCurveType::CappedExponential) <= 1.0);
        assert!((GegEscalationCurve::evaluate(1.0, GegCurveType::CappedExponential) - 1.0).abs() < 0.01);
        assert_eq!(GegEscalationCurve::evaluate(2.0, GegCurveType::CappedExponential), 1.0);
        assert_eq!(GegEscalationCurve::evaluate(10.0, GegCurveType::CappedExponential), 1.0);
    }

    #[test]
    fn test_step_discrete_levels() {
        assert_eq!(GegEscalationCurve::evaluate(0.0, GegCurveType::Step), 0.0);
        assert_eq!(GegEscalationCurve::evaluate(0.1, GegCurveType::Step), 0.0);
        assert_eq!(GegEscalationCurve::evaluate(0.3, GegCurveType::Step), 0.25);
        assert_eq!(GegEscalationCurve::evaluate(0.5, GegCurveType::Step), 0.50);
        assert_eq!(GegEscalationCurve::evaluate(0.7, GegCurveType::Step), 0.75);
        assert_eq!(GegEscalationCurve::evaluate(0.9, GegCurveType::Step), 1.0);
    }

    #[test]
    fn test_s_curve_midpoint() {
        let mid = GegEscalationCurve::evaluate(0.5, GegCurveType::SCurve);
        assert!((mid - 0.5).abs() < 0.01, "S-curve midpoint should be ~0.5: {mid}");
    }

    #[test]
    fn test_negative_input_clamped() {
        for curve in [GegCurveType::Linear, GegCurveType::Logarithmic, GegCurveType::Exponential,
                      GegCurveType::CappedExponential, GegCurveType::Step, GegCurveType::SCurve] {
            assert!(GegEscalationCurve::evaluate(-1.0, curve) >= 0.0);
        }
    }
}
