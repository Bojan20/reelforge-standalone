/// Sidechain Routing FFI (P0.5)
///
/// FFI exports for sidechain input routing:
/// - Set sidechain source track for compressor/gate
/// - Get current sidechain source
/// - Enable/disable external sidechain
///
/// Created: 2026-01-26

use std::ffi::{c_char, c_int, CString};
use std::ptr;

// ═══════════════════════════════════════════════════════════════════════════
// SIDECHAIN ROUTING
// ═══════════════════════════════════════════════════════════════════════════

/// Set sidechain input source for a processor
///
/// # Arguments
/// * `track_id` - Target track with compressor/gate
/// * `slot_index` - Insert slot index (0-7)
/// * `source_track_id` - Source track to use as sidechain input (-1 = disable external)
///
/// # Returns
/// 0 on success, -1 on error
#[unsafe(no_mangle)]
pub extern "C" fn insert_set_sidechain_source(
    _track_id: u64,
    slot_index: u64,
    source_track_id: i64,
) -> c_int {
    // TODO: Implement actual sidechain routing in rf-engine
    // For now, return success (placeholder)

    // Validate inputs
    if slot_index >= 8 {
        return -1; // Invalid slot
    }

    // -1 means disable external sidechain (use internal)
    if source_track_id < -1 || source_track_id >= 1024 {
        return -1; // Invalid source track
    }

    // Store sidechain routing (would integrate with rf-engine InsertChain)
    // engine.set_sidechain_source(track_id, slot_index, source_track_id);

    0 // Success
}

/// Get current sidechain source for a processor
///
/// # Returns
/// Source track ID, or -1 if no external sidechain (using internal)
#[unsafe(no_mangle)]
pub extern "C" fn insert_get_sidechain_source(
    _track_id: u64,
    slot_index: u64,
) -> i64 {
    // TODO: Implement actual query
    // For now, return -1 (internal sidechain)

    if slot_index >= 8 {
        return -2; // Error: invalid slot
    }

    // Query engine for sidechain source
    // engine.get_sidechain_source(track_id, slot_index)

    -1 // Internal sidechain (default)
}

/// Enable/disable sidechain for a processor
///
/// # Returns
/// 0 on success, -1 on error
#[unsafe(no_mangle)]
pub extern "C" fn insert_set_sidechain_enabled(
    _track_id: u64,
    slot_index: u64,
    _enabled: c_int,
) -> c_int {
    // TODO: Implement

    if slot_index >= 8 {
        return -1;
    }

    // engine.set_sidechain_enabled(track_id, slot_index, enabled != 0);

    0
}

// ═══════════════════════════════════════════════════════════════════════════
// TESTS
// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_set_sidechain_source_valid() {
        let result = insert_set_sidechain_source(0, 0, 5);
        assert_eq!(result, 0);
    }

    #[test]
    fn test_set_sidechain_source_disable() {
        let result = insert_set_sidechain_source(0, 0, -1);
        assert_eq!(result, 0);
    }

    #[test]
    fn test_set_sidechain_source_invalid_slot() {
        let result = insert_set_sidechain_source(0, 10, 5);
        assert_eq!(result, -1);
    }

    #[test]
    fn test_get_sidechain_source_default() {
        let result = insert_get_sidechain_source(0, 0);
        assert_eq!(result, -1); // Default: internal
    }

    #[test]
    fn test_set_sidechain_enabled() {
        let result = insert_set_sidechain_enabled(0, 0, 1);
        assert_eq!(result, 0);
    }
}
