/// Computes the n-th Fibonacci number iteratively.
/// Returns None on overflow (n > 186 for u128).
pub fn fibonacci(n: u64) -> Option<u128> {
    match n {
        0 => Some(0),
        1 => Some(1),
        _ => {
            let mut a: u128 = 0;
            let mut b: u128 = 1;
            for _ in 2..=n {
                let next = a.checked_add(b)?;
                a = b;
                b = next;
            }
            Some(b)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_cases() {
        assert_eq!(fibonacci(0), Some(0));
        assert_eq!(fibonacci(1), Some(1));
    }

    #[test]
    fn known_values() {
        assert_eq!(fibonacci(10), Some(55));
        assert_eq!(fibonacci(20), Some(6765));
        assert_eq!(fibonacci(50), Some(12586269025));
    }

    #[test]
    fn overflow_returns_none() {
        // u128 max ~ 3.4e38, Fibonacci overflows around n=187
        assert_eq!(fibonacci(187), None);
    }
}