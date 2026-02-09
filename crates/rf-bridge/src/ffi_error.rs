/// FluxForge FFI Error System — Ultimate Error Propagation
///
/// Replaces bool/null returns with rich error information:
/// - Error codes (categorized)
/// - Error messages (human-readable)
/// - Stack context (for debugging)
/// - Recovery suggestions
///
/// CRITICAL: All FFI functions should return FFIResult<T> instead of
/// raw T, bool, or null pointers for proper error handling.
use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString, c_char};
use std::fmt;

// =============================================================================
// ERROR CATEGORIES
// =============================================================================

/// Error category for grouping related errors
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum FFIErrorCategory {
    /// Invalid input parameters (validation failed)
    InvalidInput = 1,
    /// Out of bounds access (array index, buffer overflow)
    OutOfBounds = 2,
    /// Engine not initialized or in invalid state
    InvalidState = 3,
    /// Resource not found (event, track, bus, etc.)
    NotFound = 4,
    /// Resource limit exceeded (voice pool, memory, etc.)
    ResourceExhausted = 5,
    /// File I/O error (path not found, permission denied)
    IOError = 6,
    /// Serialization/deserialization error (JSON, binary)
    SerializationError = 7,
    /// Audio processing error (DSP, playback)
    AudioError = 8,
    /// Thread synchronization error (lock timeout)
    SyncError = 9,
    /// Unknown or uncategorized error
    Unknown = 255,
}

impl fmt::Display for FFIErrorCategory {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            FFIErrorCategory::InvalidInput => write!(f, "Invalid Input"),
            FFIErrorCategory::OutOfBounds => write!(f, "Out of Bounds"),
            FFIErrorCategory::InvalidState => write!(f, "Invalid State"),
            FFIErrorCategory::NotFound => write!(f, "Not Found"),
            FFIErrorCategory::ResourceExhausted => write!(f, "Resource Exhausted"),
            FFIErrorCategory::IOError => write!(f, "I/O Error"),
            FFIErrorCategory::SerializationError => write!(f, "Serialization Error"),
            FFIErrorCategory::AudioError => write!(f, "Audio Error"),
            FFIErrorCategory::SyncError => write!(f, "Synchronization Error"),
            FFIErrorCategory::Unknown => write!(f, "Unknown Error"),
        }
    }
}

// =============================================================================
// ERROR STRUCT
// =============================================================================

/// Comprehensive FFI error with context
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FFIError {
    /// Error category for programmatic handling
    pub category: FFIErrorCategory,
    /// Numeric error code (unique per category)
    pub code: u16,
    /// Human-readable error message
    pub message: String,
    /// Optional context (function name, file path, etc.)
    pub context: Option<String>,
    /// Optional recovery suggestion
    pub suggestion: Option<String>,
}

impl FFIError {
    /// Create new error
    pub fn new(category: FFIErrorCategory, code: u16, message: impl Into<String>) -> Self {
        Self {
            category,
            code,
            message: message.into(),
            context: None,
            suggestion: None,
        }
    }

    /// Add context information
    pub fn with_context(mut self, context: impl Into<String>) -> Self {
        self.context = Some(context.into());
        self
    }

    /// Add recovery suggestion
    pub fn with_suggestion(mut self, suggestion: impl Into<String>) -> Self {
        self.suggestion = Some(suggestion.into());
        self
    }

    /// Convert to JSON string for Dart consumption
    pub fn to_json_string(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| {
            format!(
                r#"{{"category":{},"code":{},"message":"{}"}}"#,
                self.category as u8, self.code, self.message
            )
        })
    }

    /// Convert to C string for FFI return
    pub fn to_c_string(&self) -> CString {
        CString::new(self.to_json_string()).unwrap_or_else(|_| {
            CString::new(r#"{"category":255,"code":0,"message":"Failed to serialize error"}"#)
                .unwrap()
        })
    }

    /// Get full error code (category << 16 | code)
    pub fn full_code(&self) -> u32 {
        ((self.category as u32) << 16) | (self.code as u32)
    }
}

impl fmt::Display for FFIError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{}:{}] {}", self.category, self.code, self.message)?;
        if let Some(ref ctx) = self.context {
            write!(f, " (context: {})", ctx)?;
        }
        if let Some(ref sug) = self.suggestion {
            write!(f, " — {}", sug)?;
        }
        Ok(())
    }
}

impl std::error::Error for FFIError {}

// =============================================================================
// RESULT TYPE
// =============================================================================

/// FFI result type for comprehensive error handling
pub type FFIResult<T> = Result<T, FFIError>;

// =============================================================================
// COMMON ERROR CONSTRUCTORS
// =============================================================================

impl FFIError {
    /// Create invalid input error
    pub fn invalid_input(code: u16, message: impl Into<String>) -> Self {
        Self::new(FFIErrorCategory::InvalidInput, code, message)
    }

    /// Create out-of-bounds error
    pub fn out_of_bounds(code: u16, message: impl Into<String>) -> Self {
        Self::new(FFIErrorCategory::OutOfBounds, code, message)
    }

    /// Create invalid state error
    pub fn invalid_state(code: u16, message: impl Into<String>) -> Self {
        Self::new(FFIErrorCategory::InvalidState, code, message)
    }

    /// Create not found error
    pub fn not_found(code: u16, message: impl Into<String>) -> Self {
        Self::new(FFIErrorCategory::NotFound, code, message)
    }

    /// Create resource exhausted error
    pub fn resource_exhausted(code: u16, message: impl Into<String>) -> Self {
        Self::new(FFIErrorCategory::ResourceExhausted, code, message)
    }

    /// Create I/O error
    pub fn io_error(code: u16, message: impl Into<String>) -> Self {
        Self::new(FFIErrorCategory::IOError, code, message)
    }

    /// Create serialization error
    pub fn serialization_error(code: u16, message: impl Into<String>) -> Self {
        Self::new(FFIErrorCategory::SerializationError, code, message)
    }

    /// Create audio error
    pub fn audio_error(code: u16, message: impl Into<String>) -> Self {
        Self::new(FFIErrorCategory::AudioError, code, message)
    }
}

// =============================================================================
// FFI C INTERFACE — ERROR HANDLING
// =============================================================================

/// Get last error as JSON string (C FFI compatible)
/// CALLER MUST FREE using ffi_error_free_string()
///
/// Returns null pointer if no error occurred
#[unsafe(no_mangle)]
pub extern "C" fn ffi_get_last_error_json() -> *mut c_char {
    // TODO: Implement thread-local error storage
    std::ptr::null_mut()
}

/// Free error string returned by FFI functions
#[unsafe(no_mangle)]
pub extern "C" fn ffi_error_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// Parse error category from full error code
#[unsafe(no_mangle)]
pub extern "C" fn ffi_error_get_category(full_code: u32) -> u8 {
    ((full_code >> 16) & 0xFF) as u8
}

/// Parse error code from full error code
#[unsafe(no_mangle)]
pub extern "C" fn ffi_error_get_code(full_code: u32) -> u16 {
    (full_code & 0xFFFF) as u16
}

// =============================================================================
// HELPER MACROS
// =============================================================================

/// Macro for converting Rust Result to FFI-safe return value
///
/// Usage:
/// ```rust,ignore
/// #[unsafe(no_mangle)]
/// pub extern "C" fn my_ffi_function() -> i32 {
///     ffi_try!(do_something(), -1)  // Returns -1 on error
/// }
/// ```
#[macro_export]
macro_rules! ffi_try {
    ($expr:expr, $error_value:expr) => {
        match $expr {
            Ok(val) => val,
            Err(err) => {
                log::error!("FFI error: {}", err);
                return $error_value;
            }
        }
    };
}

/// Macro for returning FFI error as JSON string
///
/// Usage:
/// ```rust,ignore
/// #[unsafe(no_mangle)]
/// pub extern "C" fn my_ffi_function() -> *mut c_char {
///     ffi_try_json!(do_something())
/// }
/// ```
#[macro_export]
macro_rules! ffi_try_json {
    ($expr:expr) => {
        match $expr {
            Ok(val) => val,
            Err(err) => {
                log::error!("FFI error: {}", err);
                return err.to_c_string().into_raw();
            }
        }
    };
}

// =============================================================================
// TESTING
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_creation() {
        let err = FFIError::invalid_input(100, "Test error");
        assert_eq!(err.category, FFIErrorCategory::InvalidInput);
        assert_eq!(err.code, 100);
        assert_eq!(err.message, "Test error");
    }

    #[test]
    fn test_error_with_context() {
        let err = FFIError::invalid_input(100, "Test error")
            .with_context("my_function")
            .with_suggestion("Try passing valid parameters");

        assert!(err.context.is_some());
        assert!(err.suggestion.is_some());
    }

    #[test]
    fn test_error_json_serialization() {
        let err = FFIError::invalid_input(100, "Test error");
        let json = err.to_json_string();
        assert!(
            json.contains("InvalidInput"),
            "JSON should contain variant name: {json}"
        );
        assert!(
            json.contains("Test error"),
            "JSON should contain message: {json}"
        );
    }

    #[test]
    fn test_full_error_code() {
        let err = FFIError::invalid_input(256, "Test");
        let full_code = err.full_code();

        // Category (1) in high 16 bits, code (256) in low 16 bits
        assert_eq!(full_code, (1 << 16) | 256);
    }

    #[test]
    fn test_error_code_parsing() {
        let full_code = (FFIErrorCategory::OutOfBounds as u32) << 16 | 500;

        let category = ffi_error_get_category(full_code);
        let code = ffi_error_get_code(full_code);

        assert_eq!(category, FFIErrorCategory::OutOfBounds as u8);
        assert_eq!(code, 500);
    }
}
