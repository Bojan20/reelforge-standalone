use crate::core::parameter_map::EscalationCurveType;

/// Evaluates an escalation curve at a given input (0.0-1.0+).
pub struct EscalationCurve;

impl EscalationCurve {
    /// Evaluate the curve at the given input value.
    ///
    /// input: normalized escalation input (0.0 = no win, 1.0+ = big win multiplier).
    /// Returns: scaled output value (same range semantics).
    pub fn evaluate(input: f64, curve_type: EscalationCurveType) -> f64 {
        let x = input.max(0.0);
        match curve_type {
            EscalationCurveType::Linear => x,
            EscalationCurveType::Exponential => {
                // Exponential: slow start, rapid growth
                // e^(x*2) - 1 normalized so f(1) = 1
                let scale = (2.0_f64).exp() - 1.0;
                ((x * 2.0).exp() - 1.0) / scale
            }
            EscalationCurveType::Logarithmic => {
                // Logarithmic: fast start, diminishing returns
                // ln(1 + x*e) / ln(1+e) normalized so f(1) = 1
                let e = std::f64::consts::E;
                (1.0 + x * e).ln() / (1.0 + e).ln()
            }
            EscalationCurveType::SCurve => {
                // S-curve: slow start and end, fast middle
                // smoothstep: 3x² - 2x³ (for x in 0-1), linear beyond 1
                if x <= 1.0 {
                    x * x * (3.0 - 2.0 * x)
                } else {
                    1.0 + (x - 1.0) // linear beyond saturation
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_linear() {
        assert!((EscalationCurve::evaluate(0.0, EscalationCurveType::Linear) - 0.0).abs() < 1e-10);
        assert!((EscalationCurve::evaluate(0.5, EscalationCurveType::Linear) - 0.5).abs() < 1e-10);
        assert!((EscalationCurve::evaluate(1.0, EscalationCurveType::Linear) - 1.0).abs() < 1e-10);
    }

    #[test]
    fn test_exponential_endpoints() {
        assert!(
            (EscalationCurve::evaluate(0.0, EscalationCurveType::Exponential) - 0.0).abs() < 0.01
        );
        assert!(
            (EscalationCurve::evaluate(1.0, EscalationCurveType::Exponential) - 1.0).abs() < 0.01
        );
    }

    #[test]
    fn test_exponential_convex() {
        // Exponential should be below linear at midpoint
        let mid = EscalationCurve::evaluate(0.5, EscalationCurveType::Exponential);
        assert!(
            mid < 0.5,
            "Exponential should be convex (below linear at mid): {mid}"
        );
    }

    #[test]
    fn test_logarithmic_concave() {
        // Logarithmic should be above linear at midpoint
        let mid = EscalationCurve::evaluate(0.5, EscalationCurveType::Logarithmic);
        assert!(
            mid > 0.5,
            "Logarithmic should be concave (above linear at mid): {mid}"
        );
    }

    #[test]
    fn test_s_curve_midpoint() {
        let mid = EscalationCurve::evaluate(0.5, EscalationCurveType::SCurve);
        assert!(
            (mid - 0.5).abs() < 0.01,
            "S-curve midpoint should be ~0.5: {mid}"
        );
    }

    #[test]
    fn test_s_curve_beyond_one() {
        let val = EscalationCurve::evaluate(1.5, EscalationCurveType::SCurve);
        assert!(
            (val - 1.5).abs() < 0.01,
            "S-curve beyond 1.0 should be linear"
        );
    }

    #[test]
    fn test_negative_input_clamped() {
        let val = EscalationCurve::evaluate(-1.0, EscalationCurveType::Linear);
        assert!(val >= 0.0);
    }
}
