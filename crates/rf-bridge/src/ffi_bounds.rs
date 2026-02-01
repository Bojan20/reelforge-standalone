/// FluxForge FFI Bounds Checker — Ultimate Safety Layer
///
/// Prevents array-out-of-bounds crashes at FFI boundary:
/// - Validates all array indices before access
/// - Validates buffer sizes before copy
/// - Validates pointer offsets
/// - Zero tolerance for out-of-bounds access
///
/// CRITICAL: All FFI functions MUST use these validators before
/// accessing Rust collections from Dart indices.

use std::fmt;

/// Result type for bounds checking operations
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BoundsCheckResult {
    /// Index/range is valid
    Valid,
    /// Index is negative
    NegativeIndex { index: i64 },
    /// Index exceeds array length
    OutOfBounds { index: usize, len: usize },
    /// Range exceeds array length
    RangeOutOfBounds { start: usize, end: usize, len: usize },
    /// Invalid range (start > end)
    InvalidRange { start: usize, end: usize },
    /// Buffer size mismatch
    BufferSizeMismatch { expected: usize, actual: usize },
}

impl fmt::Display for BoundsCheckResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BoundsCheckResult::Valid => write!(f, "Valid"),
            BoundsCheckResult::NegativeIndex { index } => {
                write!(f, "Negative index: {}", index)
            }
            BoundsCheckResult::OutOfBounds { index, len } => {
                write!(f, "Index {} out of bounds (len: {})", index, len)
            }
            BoundsCheckResult::RangeOutOfBounds { start, end, len } => {
                write!(f, "Range [{}..{}) out of bounds (len: {})", start, end, len)
            }
            BoundsCheckResult::InvalidRange { start, end } => {
                write!(f, "Invalid range: start ({}) > end ({})", start, end)
            }
            BoundsCheckResult::BufferSizeMismatch { expected, actual } => {
                write!(f, "Buffer size mismatch: expected {}, got {}", expected, actual)
            }
        }
    }
}

impl BoundsCheckResult {
    /// Check if result indicates validity
    pub fn is_valid(&self) -> bool {
        matches!(self, BoundsCheckResult::Valid)
    }

    /// Convert to Result type for easier error propagation
    pub fn to_result(self) -> Result<(), String> {
        if self.is_valid() {
            Ok(())
        } else {
            Err(self.to_string())
        }
    }
}

// =============================================================================
// VALIDATOR FUNCTIONS
// =============================================================================

/// Validate single index against array length
///
/// # Arguments
/// * `index` - Index from Dart (may be negative, which is invalid in Rust)
/// * `len` - Length of the Rust array/vector
///
/// # Returns
/// * `BoundsCheckResult::Valid` if index is within bounds
/// * Error variant otherwise
#[inline]
pub fn check_index(index: i64, len: usize) -> BoundsCheckResult {
    if index < 0 {
        return BoundsCheckResult::NegativeIndex { index };
    }

    let index_usize = index as usize;

    if index_usize >= len {
        return BoundsCheckResult::OutOfBounds {
            index: index_usize,
            len,
        };
    }

    BoundsCheckResult::Valid
}

/// Validate range [start..end) against array length
///
/// # Arguments
/// * `start` - Start index (inclusive)
/// * `end` - End index (exclusive)
/// * `len` - Length of the Rust array/vector
///
/// # Returns
/// * `BoundsCheckResult::Valid` if range is within bounds
/// * Error variant otherwise
#[inline]
pub fn check_range(start: i64, end: i64, len: usize) -> BoundsCheckResult {
    // Check for negative indices
    if start < 0 {
        return BoundsCheckResult::NegativeIndex { index: start };
    }
    if end < 0 {
        return BoundsCheckResult::NegativeIndex { index: end };
    }

    let start_usize = start as usize;
    let end_usize = end as usize;

    // Check for invalid range
    if start_usize > end_usize {
        return BoundsCheckResult::InvalidRange {
            start: start_usize,
            end: end_usize,
        };
    }

    // Check bounds
    if end_usize > len {
        return BoundsCheckResult::RangeOutOfBounds {
            start: start_usize,
            end: end_usize,
            len,
        };
    }

    BoundsCheckResult::Valid
}

/// Validate buffer size for copy operations
///
/// # Arguments
/// * `expected` - Expected buffer size
/// * `actual` - Actual buffer size provided
///
/// # Returns
/// * `BoundsCheckResult::Valid` if sizes match
/// * Error variant otherwise
#[inline]
pub fn check_buffer_size(expected: usize, actual: usize) -> BoundsCheckResult {
    if expected != actual {
        return BoundsCheckResult::BufferSizeMismatch { expected, actual };
    }

    BoundsCheckResult::Valid
}

/// Validate pointer offset against buffer size
///
/// # Arguments
/// * `offset` - Byte offset from pointer
/// * `element_size` - Size of each element in bytes
/// * `buffer_len` - Total buffer length in bytes
///
/// # Returns
/// * `BoundsCheckResult::Valid` if offset is within bounds
/// * Error variant otherwise
#[inline]
pub fn check_pointer_offset(offset: i64, element_size: usize, buffer_len: usize) -> BoundsCheckResult {
    if offset < 0 {
        return BoundsCheckResult::NegativeIndex { index: offset };
    }

    let offset_usize = offset as usize;
    let required_size = offset_usize + element_size;

    if required_size > buffer_len {
        return BoundsCheckResult::OutOfBounds {
            index: required_size,
            len: buffer_len,
        };
    }

    BoundsCheckResult::Valid
}

// =============================================================================
// SAFE ACCESS HELPERS
// =============================================================================

/// Safely get element from slice with bounds checking
///
/// # Arguments
/// * `slice` - Slice to access
/// * `index` - Index from FFI (i64 from Dart)
///
/// # Returns
/// * `Some(&T)` if index is valid
/// * `None` if index is out of bounds
#[inline]
pub fn safe_get<T>(slice: &[T], index: i64) -> Option<&T> {
    if check_index(index, slice.len()).is_valid() {
        slice.get(index as usize)
    } else {
        None
    }
}

/// Safely get mutable element from slice with bounds checking
///
/// # Arguments
/// * `slice` - Mutable slice to access
/// * `index` - Index from FFI (i64 from Dart)
///
/// # Returns
/// * `Some(&mut T)` if index is valid
/// * `None` if index is out of bounds
#[inline]
pub fn safe_get_mut<T>(slice: &mut [T], index: i64) -> Option<&mut T> {
    if check_index(index, slice.len()).is_valid() {
        slice.get_mut(index as usize)
    } else {
        None
    }
}

/// Safely get subslice with bounds checking
///
/// # Arguments
/// * `slice` - Slice to access
/// * `start` - Start index (inclusive)
/// * `end` - End index (exclusive)
///
/// # Returns
/// * `Some(&[T])` if range is valid
/// * `None` if range is out of bounds
#[inline]
pub fn safe_slice<T>(slice: &[T], start: i64, end: i64) -> Option<&[T]> {
    if check_range(start, end, slice.len()).is_valid() {
        Some(&slice[start as usize..end as usize])
    } else {
        None
    }
}

// =============================================================================
// TESTING UTILITIES
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_check_index_valid() {
        let result = check_index(5, 10);
        assert_eq!(result, BoundsCheckResult::Valid);
    }

    #[test]
    fn test_check_index_negative() {
        let result = check_index(-1, 10);
        assert!(matches!(result, BoundsCheckResult::NegativeIndex { .. }));
    }

    #[test]
    fn test_check_index_out_of_bounds() {
        let result = check_index(10, 10);
        assert!(matches!(result, BoundsCheckResult::OutOfBounds { .. }));
    }

    #[test]
    fn test_check_range_valid() {
        let result = check_range(2, 5, 10);
        assert_eq!(result, BoundsCheckResult::Valid);
    }

    #[test]
    fn test_check_range_invalid() {
        let result = check_range(5, 2, 10);
        assert!(matches!(result, BoundsCheckResult::InvalidRange { .. }));
    }

    #[test]
    fn test_check_range_out_of_bounds() {
        let result = check_range(5, 15, 10);
        assert!(matches!(result, BoundsCheckResult::RangeOutOfBounds { .. }));
    }

    #[test]
    fn test_safe_get_valid() {
        let data = vec![1, 2, 3, 4, 5];
        let result = safe_get(&data, 2);
        assert_eq!(result, Some(&3));
    }

    #[test]
    fn test_safe_get_out_of_bounds() {
        let data = vec![1, 2, 3];
        let result = safe_get(&data, 10);
        assert_eq!(result, None);
    }

    #[test]
    fn test_safe_get_negative() {
        let data = vec![1, 2, 3];
        let result = safe_get(&data, -1);
        assert_eq!(result, None);
    }

    #[test]
    fn test_safe_slice_valid() {
        let data = vec![1, 2, 3, 4, 5];
        let result = safe_slice(&data, 1, 4);
        assert_eq!(result, Some(&[2, 3, 4][..]));
    }

    #[test]
    fn test_safe_slice_invalid() {
        let data = vec![1, 2, 3];
        let result = safe_slice(&data, 1, 10);
        assert_eq!(result, None);
    }

    #[test]
    fn test_buffer_size_check() {
        let result = check_buffer_size(100, 100);
        assert_eq!(result, BoundsCheckResult::Valid);

        let result = check_buffer_size(100, 50);
        assert!(matches!(result, BoundsCheckResult::BufferSizeMismatch { .. }));
    }

    #[test]
    fn test_pointer_offset_check() {
        let result = check_pointer_offset(10, 4, 100);
        assert_eq!(result, BoundsCheckResult::Valid);

        let result = check_pointer_offset(100, 10, 100);
        assert!(matches!(result, BoundsCheckResult::OutOfBounds { .. }));
    }
}
