/// Simple, fast, deterministic hash function.
/// Uses FNV-1a variant for portability (no xxhash dependency needed for core).
/// Guarantees identical output on all platforms for the same input.
pub fn aurexis_hash(data: &[u8]) -> u64 {
    // FNV-1a 64-bit
    const FNV_OFFSET: u64 = 14695981039346656037;
    const FNV_PRIME: u64 = 1099511628211;

    let mut hash = FNV_OFFSET;
    for &byte in data {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(FNV_PRIME);
    }
    hash
}

/// Hash multiple u64 seed components into a single deterministic seed.
pub fn combine_seeds(sprite_id: u64, event_time: u64, game_state: u64, session_index: u64) -> u64 {
    let mut buf = [0u8; 32];
    buf[0..8].copy_from_slice(&sprite_id.to_le_bytes());
    buf[8..16].copy_from_slice(&event_time.to_le_bytes());
    buf[16..24].copy_from_slice(&game_state.to_le_bytes());
    buf[24..32].copy_from_slice(&session_index.to_le_bytes());
    aurexis_hash(&buf)
}

/// Map a seed to a value in the range [min, max] deterministically.
/// Uses sub-seeding with offset to produce independent values from the same base seed.
pub fn seed_to_range(seed: u64, offset: u32, min: f64, max: f64) -> f64 {
    let mut buf = [0u8; 12];
    buf[0..8].copy_from_slice(&seed.to_le_bytes());
    buf[8..12].copy_from_slice(&offset.to_le_bytes());
    let sub_seed = aurexis_hash(&buf);
    let normalized = (sub_seed as f64) / (u64::MAX as f64); // 0.0-1.0
    min + normalized * (max - min)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_determinism() {
        let a = aurexis_hash(b"test input 12345");
        let b = aurexis_hash(b"test input 12345");
        assert_eq!(a, b, "Same input must produce same hash");
    }

    #[test]
    fn test_different_inputs() {
        let a = aurexis_hash(b"input A");
        let b = aurexis_hash(b"input B");
        assert_ne!(a, b, "Different inputs should produce different hashes");
    }

    #[test]
    fn test_combine_seeds_deterministic() {
        let a = combine_seeds(42, 1000, 7, 0);
        let b = combine_seeds(42, 1000, 7, 0);
        assert_eq!(a, b);
    }

    #[test]
    fn test_combine_seeds_different() {
        let a = combine_seeds(42, 1000, 7, 0);
        let b = combine_seeds(42, 1000, 7, 1); // different session index
        assert_ne!(a, b);
    }

    #[test]
    fn test_seed_to_range_bounds() {
        for offset in 0..100 {
            let val = seed_to_range(12345, offset, -0.05, 0.05);
            assert!(
                val >= -0.05 && val <= 0.05,
                "Value {val} out of range at offset={offset}"
            );
        }
    }

    #[test]
    fn test_seed_to_range_deterministic() {
        let a = seed_to_range(99999, 3, -1.0, 1.0);
        let b = seed_to_range(99999, 3, -1.0, 1.0);
        assert_eq!(a, b);
    }

    #[test]
    fn test_seed_to_range_different_offsets() {
        let a = seed_to_range(12345, 0, -1.0, 1.0);
        let b = seed_to_range(12345, 1, -1.0, 1.0);
        // Should be different (independent sub-seeds)
        assert!(
            (a - b).abs() > 0.001,
            "Different offsets should give different values"
        );
    }

    #[test]
    fn test_distribution_rough_uniformity() {
        // Check that values are roughly uniformly distributed
        let mut sum = 0.0;
        let n = 10000;
        for i in 0..n {
            let val = seed_to_range(i as u64, 0, 0.0, 1.0);
            sum += val;
        }
        let mean = sum / n as f64;
        // Should be roughly 0.5
        assert!((mean - 0.5).abs() < 0.05, "Mean should be ~0.5, got {mean}");
    }
}
