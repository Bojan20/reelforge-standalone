//! FFI Roundtrip Tests for rf-bridge
//!
//! Tests data integrity across the FFI boundary:
//! - Error system (FFIError, categories, codes)
//! - Bounds checking (index, range, buffer, pointer offset)
//! - Safe access helpers (safe_get, safe_slice)
//! - DSP command types (FilterType, FilterSlope, PhaseMode conversions)
//! - Command queue (lock-free producer/consumer)
//! - String handling (UTF-8, CString, null pointers)
//! - JSON serialization through container FFI
//! - Parameter bounds (NaN, Inf, extreme values)

use std::ffi::{CStr, CString};

use rf_bridge::{
    COMMAND_QUEUE_SIZE,
    // Command Queue
    CommandQueueManager,
    // DSP Command Types
    dsp_commands::{
        AnalyzerMode, DspCommand, FilterSlope, FilterType, PhaseMode, StereoPlacement,
        next_command_id,
    },
    // FFI Bounds Checking
    ffi_bounds::{
        BoundsCheckResult, check_buffer_size, check_index, check_pointer_offset, check_range,
        safe_get, safe_get_mut, safe_slice,
    },
    // FFI Error System
    ffi_error::{FFIError, FFIErrorCategory, ffi_error_get_category, ffi_error_get_code},
};

// ═══════════════════════════════════════════════════════════════════════════════
// FFI ERROR SYSTEM TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_ffi_error_creation_all_categories() {
    let categories = [
        (FFIErrorCategory::InvalidInput, 1u8),
        (FFIErrorCategory::OutOfBounds, 2),
        (FFIErrorCategory::InvalidState, 3),
        (FFIErrorCategory::NotFound, 4),
        (FFIErrorCategory::ResourceExhausted, 5),
        (FFIErrorCategory::IOError, 6),
        (FFIErrorCategory::SerializationError, 7),
        (FFIErrorCategory::AudioError, 8),
        (FFIErrorCategory::SyncError, 9),
        (FFIErrorCategory::Unknown, 255),
    ];

    for (cat, expected_val) in categories {
        let err = FFIError::new(cat, 42, "test message");
        assert_eq!(err.category, cat);
        assert_eq!(err.code, 42);
        assert_eq!(err.message, "test message");
        assert_eq!(err.category as u8, expected_val);
    }
}

#[test]
fn test_ffi_error_with_context_and_suggestion() {
    let err = FFIError::invalid_input(100, "bad param")
        .with_context("my_function")
        .with_suggestion("pass a valid value");

    assert_eq!(err.category, FFIErrorCategory::InvalidInput);
    assert_eq!(err.code, 100);
    assert_eq!(err.context.as_deref(), Some("my_function"));
    assert_eq!(err.suggestion.as_deref(), Some("pass a valid value"));
}

#[test]
fn test_ffi_error_full_code_roundtrip() {
    // Test that full_code encoding and ffi_error_get_category/code decode correctly
    let test_cases: Vec<(FFIErrorCategory, u16)> = vec![
        (FFIErrorCategory::InvalidInput, 0),
        (FFIErrorCategory::InvalidInput, 1),
        (FFIErrorCategory::InvalidInput, 65535),
        (FFIErrorCategory::OutOfBounds, 500),
        (FFIErrorCategory::InvalidState, 1000),
        (FFIErrorCategory::NotFound, 256),
        (FFIErrorCategory::ResourceExhausted, 42),
        (FFIErrorCategory::IOError, 0),
        (FFIErrorCategory::SerializationError, 100),
        (FFIErrorCategory::AudioError, 200),
        (FFIErrorCategory::SyncError, 300),
        (FFIErrorCategory::Unknown, 999),
    ];

    for (category, code) in test_cases {
        let err = FFIError::new(category, code, "test");
        let full_code = err.full_code();

        // Decode using the C FFI functions
        let decoded_category = ffi_error_get_category(full_code);
        let decoded_code = ffi_error_get_code(full_code);

        assert_eq!(
            decoded_category, category as u8,
            "Category mismatch for {:?} code {}",
            category, code
        );
        assert_eq!(
            decoded_code, code,
            "Code mismatch for {:?} code {}",
            category, code
        );
    }
}

#[test]
fn test_ffi_error_json_serialization_roundtrip() {
    let err = FFIError::invalid_input(42, "test error")
        .with_context("test_func")
        .with_suggestion("fix it");

    let json = err.to_json_string();

    // Verify JSON contains expected fields
    assert!(json.contains("42"), "JSON should contain code: {}", json);
    assert!(
        json.contains("test error"),
        "JSON should contain message: {}",
        json
    );
    assert!(
        json.contains("test_func"),
        "JSON should contain context: {}",
        json
    );
    assert!(
        json.contains("fix it"),
        "JSON should contain suggestion: {}",
        json
    );

    // Verify it's valid JSON by parsing with serde_json
    let parsed: serde_json::Value =
        serde_json::from_str(&json).expect("FFIError JSON should be valid");
    assert_eq!(parsed["code"], 42);
    assert_eq!(parsed["message"], "test error");
}

#[test]
fn test_ffi_error_c_string_conversion() {
    let err = FFIError::audio_error(99, "buffer underrun");
    let cstring = err.to_c_string();

    // Verify CString is valid and contains expected content
    let as_str = cstring.to_str().expect("CString should be valid UTF-8");
    assert!(as_str.contains("buffer underrun"));
    assert!(as_str.contains("99"));
}

#[test]
fn test_ffi_error_display_format() {
    let err = FFIError::not_found(404, "track not found")
        .with_context("get_track")
        .with_suggestion("check track ID");

    let display = format!("{}", err);
    assert!(display.contains("Not Found"));
    assert!(display.contains("404"));
    assert!(display.contains("track not found"));
    assert!(display.contains("get_track"));
    assert!(display.contains("check track ID"));
}

#[test]
fn test_ffi_error_convenience_constructors() {
    let e1 = FFIError::invalid_input(1, "a");
    assert_eq!(e1.category, FFIErrorCategory::InvalidInput);

    let e2 = FFIError::out_of_bounds(2, "b");
    assert_eq!(e2.category, FFIErrorCategory::OutOfBounds);

    let e3 = FFIError::invalid_state(3, "c");
    assert_eq!(e3.category, FFIErrorCategory::InvalidState);

    let e4 = FFIError::not_found(4, "d");
    assert_eq!(e4.category, FFIErrorCategory::NotFound);

    let e5 = FFIError::resource_exhausted(5, "e");
    assert_eq!(e5.category, FFIErrorCategory::ResourceExhausted);

    let e6 = FFIError::io_error(6, "f");
    assert_eq!(e6.category, FFIErrorCategory::IOError);

    let e7 = FFIError::serialization_error(7, "g");
    assert_eq!(e7.category, FFIErrorCategory::SerializationError);

    let e8 = FFIError::audio_error(8, "h");
    assert_eq!(e8.category, FFIErrorCategory::AudioError);
}

#[test]
fn test_ffi_error_special_characters_in_message() {
    // Test that special characters survive serialization
    let special_msgs = [
        "error with \"quotes\"",
        "error with \\ backslash",
        "error with / forward slash",
        "error with unicode: \u{00e9}\u{00e8}\u{00ea}",
        "error with newline\nin message",
        "", // empty string
    ];

    for msg in special_msgs {
        let err = FFIError::invalid_input(1, msg);
        let json = err.to_json_string();
        // Verify it's valid JSON (won't panic if parsing succeeds)
        let _: serde_json::Value = serde_json::from_str(&json)
            .unwrap_or_else(|e| panic!("Failed to parse JSON for message '{}': {}", msg, e));
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FFI BOUNDS CHECKING TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_check_index_valid_range() {
    // All valid indices for a length-10 array
    for i in 0..10i64 {
        assert_eq!(
            check_index(i, 10),
            BoundsCheckResult::Valid,
            "Index {} should be valid for len 10",
            i
        );
    }
}

#[test]
fn test_check_index_boundary_exact() {
    // Index == len is out of bounds (0-indexed)
    assert!(matches!(
        check_index(10, 10),
        BoundsCheckResult::OutOfBounds { .. }
    ));
    assert!(matches!(
        check_index(0, 0),
        BoundsCheckResult::OutOfBounds { .. }
    ));
    assert_eq!(check_index(0, 1), BoundsCheckResult::Valid);
}

#[test]
fn test_check_index_negative_values() {
    assert!(matches!(
        check_index(-1, 10),
        BoundsCheckResult::NegativeIndex { index: -1 }
    ));
    assert!(matches!(
        check_index(-100, 10),
        BoundsCheckResult::NegativeIndex { index: -100 }
    ));
    assert!(matches!(
        check_index(i64::MIN, 10),
        BoundsCheckResult::NegativeIndex { .. }
    ));
}

#[test]
fn test_check_index_large_values() {
    // Very large index
    assert!(matches!(
        check_index(i64::MAX, 10),
        BoundsCheckResult::OutOfBounds { .. }
    ));
    // Large but valid
    assert_eq!(check_index(999, 1000), BoundsCheckResult::Valid);
    assert!(matches!(
        check_index(1000, 1000),
        BoundsCheckResult::OutOfBounds { .. }
    ));
}

#[test]
fn test_check_range_valid() {
    assert_eq!(check_range(0, 10, 10), BoundsCheckResult::Valid);
    assert_eq!(check_range(0, 0, 10), BoundsCheckResult::Valid); // empty range
    assert_eq!(check_range(5, 5, 10), BoundsCheckResult::Valid); // empty range
    assert_eq!(check_range(3, 7, 10), BoundsCheckResult::Valid);
}

#[test]
fn test_check_range_invalid_inverted() {
    // start > end
    assert!(matches!(
        check_range(5, 3, 10),
        BoundsCheckResult::InvalidRange { start: 5, end: 3 }
    ));
    assert!(matches!(
        check_range(10, 0, 10),
        BoundsCheckResult::InvalidRange { .. }
    ));
}

#[test]
fn test_check_range_out_of_bounds() {
    assert!(matches!(
        check_range(0, 11, 10),
        BoundsCheckResult::RangeOutOfBounds { .. }
    ));
    assert!(matches!(
        check_range(5, 15, 10),
        BoundsCheckResult::RangeOutOfBounds { .. }
    ));
}

#[test]
fn test_check_range_negative() {
    assert!(matches!(
        check_range(-1, 5, 10),
        BoundsCheckResult::NegativeIndex { index: -1 }
    ));
    assert!(matches!(
        check_range(0, -1, 10),
        BoundsCheckResult::NegativeIndex { index: -1 }
    ));
    assert!(matches!(
        check_range(-5, -1, 10),
        BoundsCheckResult::NegativeIndex { .. }
    ));
}

#[test]
fn test_check_buffer_size_match() {
    assert_eq!(check_buffer_size(0, 0), BoundsCheckResult::Valid);
    assert_eq!(check_buffer_size(100, 100), BoundsCheckResult::Valid);
    assert_eq!(
        check_buffer_size(usize::MAX, usize::MAX),
        BoundsCheckResult::Valid
    );
}

#[test]
fn test_check_buffer_size_mismatch() {
    let result = check_buffer_size(100, 50);
    assert!(matches!(
        result,
        BoundsCheckResult::BufferSizeMismatch {
            expected: 100,
            actual: 50
        }
    ));

    let result = check_buffer_size(50, 100);
    assert!(matches!(
        result,
        BoundsCheckResult::BufferSizeMismatch {
            expected: 50,
            actual: 100
        }
    ));
}

#[test]
fn test_check_pointer_offset_valid() {
    assert_eq!(check_pointer_offset(0, 4, 100), BoundsCheckResult::Valid);
    assert_eq!(check_pointer_offset(96, 4, 100), BoundsCheckResult::Valid);
}

#[test]
fn test_check_pointer_offset_overflow() {
    // Offset + element_size > buffer_len
    assert!(matches!(
        check_pointer_offset(97, 4, 100),
        BoundsCheckResult::OutOfBounds { .. }
    ));
    assert!(matches!(
        check_pointer_offset(100, 1, 100),
        BoundsCheckResult::OutOfBounds { .. }
    ));
}

#[test]
fn test_check_pointer_offset_negative() {
    assert!(matches!(
        check_pointer_offset(-1, 4, 100),
        BoundsCheckResult::NegativeIndex { .. }
    ));
}

#[test]
fn test_bounds_check_result_is_valid() {
    assert!(BoundsCheckResult::Valid.is_valid());
    assert!(!BoundsCheckResult::NegativeIndex { index: -1 }.is_valid());
    assert!(!BoundsCheckResult::OutOfBounds { index: 10, len: 5 }.is_valid());
    assert!(!BoundsCheckResult::InvalidRange { start: 5, end: 3 }.is_valid());
    assert!(
        !BoundsCheckResult::BufferSizeMismatch {
            expected: 10,
            actual: 5
        }
        .is_valid()
    );
}

#[test]
fn test_bounds_check_result_to_result() {
    assert!(BoundsCheckResult::Valid.to_result().is_ok());
    assert!(
        BoundsCheckResult::NegativeIndex { index: -1 }
            .to_result()
            .is_err()
    );

    let err = BoundsCheckResult::OutOfBounds { index: 10, len: 5 }.to_result();
    assert!(err.is_err());
    let err_msg = err.unwrap_err();
    assert!(
        err_msg.contains("10"),
        "Error should mention index: {}",
        err_msg
    );
    assert!(
        err_msg.contains("5"),
        "Error should mention len: {}",
        err_msg
    );
}

#[test]
fn test_bounds_check_result_display() {
    let display = format!("{}", BoundsCheckResult::Valid);
    assert_eq!(display, "Valid");

    let display = format!("{}", BoundsCheckResult::NegativeIndex { index: -42 });
    assert!(display.contains("-42"));

    let display = format!("{}", BoundsCheckResult::OutOfBounds { index: 10, len: 5 });
    assert!(display.contains("10") && display.contains("5"));

    let display = format!(
        "{}",
        BoundsCheckResult::RangeOutOfBounds {
            start: 3,
            end: 15,
            len: 10
        }
    );
    assert!(display.contains("3") && display.contains("15") && display.contains("10"));

    let display = format!("{}", BoundsCheckResult::InvalidRange { start: 5, end: 3 });
    assert!(display.contains("5") && display.contains("3"));

    let display = format!(
        "{}",
        BoundsCheckResult::BufferSizeMismatch {
            expected: 100,
            actual: 50
        }
    );
    assert!(display.contains("100") && display.contains("50"));
}

// ═══════════════════════════════════════════════════════════════════════════════
// SAFE ACCESS HELPER TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_safe_get_valid_indices() {
    let data = vec![10, 20, 30, 40, 50];
    assert_eq!(safe_get(&data, 0), Some(&10));
    assert_eq!(safe_get(&data, 2), Some(&30));
    assert_eq!(safe_get(&data, 4), Some(&50));
}

#[test]
fn test_safe_get_invalid_indices() {
    let data = vec![10, 20, 30];
    assert_eq!(safe_get(&data, -1), None);
    assert_eq!(safe_get(&data, 3), None);
    assert_eq!(safe_get(&data, 100), None);
    assert_eq!(safe_get(&data, i64::MAX), None);
    assert_eq!(safe_get(&data, i64::MIN), None);
}

#[test]
fn test_safe_get_empty_slice() {
    let data: Vec<i32> = vec![];
    assert_eq!(safe_get(&data, 0), None);
    assert_eq!(safe_get(&data, -1), None);
}

#[test]
fn test_safe_get_mut_modifies_in_place() {
    let mut data = vec![10, 20, 30];

    if let Some(val) = safe_get_mut(&mut data, 1) {
        *val = 99;
    }
    assert_eq!(data, vec![10, 99, 30]);

    // Invalid index should return None and not modify
    assert!(safe_get_mut(&mut data, -1).is_none());
    assert!(safe_get_mut(&mut data, 3).is_none());
    assert_eq!(data, vec![10, 99, 30]);
}

#[test]
fn test_safe_slice_valid() {
    let data = vec![1, 2, 3, 4, 5];

    assert_eq!(safe_slice(&data, 0, 5), Some(&[1, 2, 3, 4, 5][..]));
    assert_eq!(safe_slice(&data, 1, 4), Some(&[2, 3, 4][..]));
    assert_eq!(safe_slice(&data, 0, 0), Some(&[][..])); // empty slice
    assert_eq!(safe_slice(&data, 3, 3), Some(&[][..])); // empty slice
}

#[test]
fn test_safe_slice_invalid() {
    let data = vec![1, 2, 3];

    assert_eq!(safe_slice(&data, -1, 2), None);
    assert_eq!(safe_slice(&data, 0, 4), None); // end > len
    assert_eq!(safe_slice(&data, 2, 1), None); // start > end
    assert_eq!(safe_slice(&data, 0, -1), None);
}

// ═══════════════════════════════════════════════════════════════════════════════
// DSP COMMAND TYPE CONVERSION TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_filter_type_from_u8_roundtrip() {
    let expected = [
        (0u8, FilterType::Bell),
        (1, FilterType::LowShelf),
        (2, FilterType::HighShelf),
        (3, FilterType::LowCut),
        (4, FilterType::HighCut),
        (5, FilterType::Notch),
        (6, FilterType::Bandpass),
        (7, FilterType::TiltShelf),
        (8, FilterType::Allpass),
        (9, FilterType::Brickwall),
    ];

    for (val, expected_type) in expected {
        let converted = FilterType::from(val);
        assert_eq!(
            converted, expected_type,
            "FilterType::from({}) should be {:?}",
            val, expected_type
        );
    }
}

#[test]
fn test_filter_type_from_u8_invalid_defaults_to_bell() {
    // Invalid values should default to Bell
    assert_eq!(FilterType::from(10), FilterType::Bell);
    assert_eq!(FilterType::from(100), FilterType::Bell);
    assert_eq!(FilterType::from(255), FilterType::Bell);
}

#[test]
fn test_filter_slope_from_u8_roundtrip() {
    let expected = [
        (0u8, FilterSlope::Db6),
        (1, FilterSlope::Db12),
        (2, FilterSlope::Db18),
        (3, FilterSlope::Db24),
        (4, FilterSlope::Db36),
        (5, FilterSlope::Db48),
        (6, FilterSlope::Db72),
        (7, FilterSlope::Db96),
    ];

    for (val, expected_slope) in expected {
        let converted = FilterSlope::from(val);
        assert_eq!(
            converted, expected_slope,
            "FilterSlope::from({}) should be {:?}",
            val, expected_slope
        );
    }
}

#[test]
fn test_filter_slope_from_u8_invalid_defaults_to_db12() {
    assert_eq!(FilterSlope::from(8), FilterSlope::Db12);
    assert_eq!(FilterSlope::from(255), FilterSlope::Db12);
}

#[test]
fn test_phase_mode_from_u8_roundtrip() {
    assert_eq!(PhaseMode::from(0), PhaseMode::ZeroLatency);
    assert_eq!(PhaseMode::from(1), PhaseMode::Natural);
    assert_eq!(PhaseMode::from(2), PhaseMode::Linear);
    assert_eq!(PhaseMode::from(3), PhaseMode::Hybrid);
    // Invalid defaults to ZeroLatency
    assert_eq!(PhaseMode::from(4), PhaseMode::ZeroLatency);
    assert_eq!(PhaseMode::from(255), PhaseMode::ZeroLatency);
}

#[test]
fn test_stereo_placement_from_u8_roundtrip() {
    assert_eq!(StereoPlacement::from(0), StereoPlacement::Stereo);
    assert_eq!(StereoPlacement::from(1), StereoPlacement::Left);
    assert_eq!(StereoPlacement::from(2), StereoPlacement::Right);
    assert_eq!(StereoPlacement::from(3), StereoPlacement::Mid);
    assert_eq!(StereoPlacement::from(4), StereoPlacement::Side);
    // Invalid defaults to Stereo
    assert_eq!(StereoPlacement::from(5), StereoPlacement::Stereo);
    assert_eq!(StereoPlacement::from(255), StereoPlacement::Stereo);
}

#[test]
fn test_analyzer_mode_from_u8_roundtrip() {
    assert_eq!(AnalyzerMode::from(0), AnalyzerMode::Off);
    assert_eq!(AnalyzerMode::from(1), AnalyzerMode::PreEq);
    assert_eq!(AnalyzerMode::from(2), AnalyzerMode::PostEq);
    assert_eq!(AnalyzerMode::from(3), AnalyzerMode::Sidechain);
    assert_eq!(AnalyzerMode::from(4), AnalyzerMode::Delta);
    // Invalid defaults to Off
    assert_eq!(AnalyzerMode::from(5), AnalyzerMode::Off);
    assert_eq!(AnalyzerMode::from(255), AnalyzerMode::Off);
}

// ═══════════════════════════════════════════════════════════════════════════════
// DSP COMMAND CONSTRUCTION TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_dsp_command_eq_set_band() {
    let cmd = DspCommand::EqSetBand {
        track_id: 0,
        band_index: 5,
        freq: 1000.0,
        gain_db: 3.0,
        q: 1.41,
        filter_type: FilterType::Bell,
        slope: FilterSlope::Db12,
        stereo: StereoPlacement::Stereo,
    };

    // Verify all fields via pattern match
    if let DspCommand::EqSetBand {
        track_id,
        band_index,
        freq,
        gain_db,
        q,
        filter_type,
        slope,
        stereo,
    } = cmd
    {
        assert_eq!(track_id, 0);
        assert_eq!(band_index, 5);
        assert!((freq - 1000.0).abs() < f64::EPSILON);
        assert!((gain_db - 3.0).abs() < f64::EPSILON);
        assert!((q - 1.41).abs() < f64::EPSILON);
        assert_eq!(filter_type, FilterType::Bell);
        assert_eq!(slope, FilterSlope::Db12);
        assert_eq!(stereo, StereoPlacement::Stereo);
    } else {
        panic!("Expected EqSetBand command");
    }
}

#[test]
fn test_dsp_command_extreme_parameter_values() {
    // DSP commands should accept extreme values without panicking
    // (clamping happens at a different layer)
    let cmd_nan = DspCommand::EqSetFrequency {
        track_id: 0,
        band_index: 0,
        freq: f64::NAN,
    };
    // Just verify construction doesn't panic
    let _ = format!("{:?}", cmd_nan);

    let cmd_inf = DspCommand::EqSetGain {
        track_id: 0,
        band_index: 0,
        gain_db: f64::INFINITY,
    };
    let _ = format!("{:?}", cmd_inf);

    let cmd_neg_inf = DspCommand::EqSetGain {
        track_id: 0,
        band_index: 0,
        gain_db: f64::NEG_INFINITY,
    };
    let _ = format!("{:?}", cmd_neg_inf);

    let cmd_min = DspCommand::EqSetQ {
        track_id: 0,
        band_index: 0,
        q: f64::MIN,
    };
    let _ = format!("{:?}", cmd_min);

    let cmd_max = DspCommand::EqSetQ {
        track_id: 0,
        band_index: 0,
        q: f64::MAX,
    };
    let _ = format!("{:?}", cmd_max);
}

#[test]
fn test_command_id_uniqueness() {
    let id1 = next_command_id();
    let id2 = next_command_id();
    let id3 = next_command_id();

    assert_ne!(id1, id2);
    assert_ne!(id2, id3);
    assert_ne!(id1, id3);
    // Monotonically increasing
    assert!(id2 > id1);
    assert!(id3 > id2);
}

#[test]
fn test_command_id_sequential() {
    let id1 = next_command_id();
    let id2 = next_command_id();
    // IDs should be sequential (difference of 1)
    assert_eq!(id2 - id1, 1);
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMMAND QUEUE TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_command_queue_creation() {
    let queue = CommandQueueManager::new();
    // Just verify it doesn't panic
    let _ = queue;
}

#[test]
fn test_command_queue_split_and_send() {
    let queue = CommandQueueManager::new();
    let (mut ui_handle, mut audio_handle) = queue.split();

    // Send a command from UI side
    let cmd = DspCommand::EqEnableBand {
        track_id: 0,
        band_index: 3,
        enabled: true,
    };
    let sent = ui_handle.send(cmd);
    assert!(sent, "Command should be sent successfully");

    // Receive on audio side via poll_commands iterator
    let received = audio_handle.poll_commands().next();
    assert!(received.is_some(), "Should receive the command");

    if let Some(DspCommand::EqEnableBand {
        track_id,
        band_index,
        enabled,
    }) = received
    {
        assert_eq!(track_id, 0);
        assert_eq!(band_index, 3);
        assert!(enabled);
    } else {
        panic!("Received wrong command type");
    }
}

#[test]
fn test_command_queue_empty_receive() {
    let queue = CommandQueueManager::new();
    let (_ui_handle, mut audio_handle) = queue.split();

    // No commands sent, poll should return None
    let received = audio_handle.poll_commands().next();
    assert!(received.is_none(), "Empty queue should return None");
}

#[test]
fn test_command_queue_multiple_commands_fifo() {
    let queue = CommandQueueManager::new();
    let (mut ui_handle, mut audio_handle) = queue.split();

    // Send 3 commands
    ui_handle.send(DspCommand::EqSetFrequency {
        track_id: 0,
        band_index: 0,
        freq: 100.0,
    });
    ui_handle.send(DspCommand::EqSetFrequency {
        track_id: 0,
        band_index: 1,
        freq: 200.0,
    });
    ui_handle.send(DspCommand::EqSetFrequency {
        track_id: 0,
        band_index: 2,
        freq: 300.0,
    });

    // Receive in FIFO order via poll_commands iterator
    if let Some(DspCommand::EqSetFrequency { freq, .. }) = audio_handle.poll_commands().next() {
        assert!((freq - 100.0).abs() < f64::EPSILON);
    } else {
        panic!("Expected first command");
    }

    if let Some(DspCommand::EqSetFrequency { freq, .. }) = audio_handle.poll_commands().next() {
        assert!((freq - 200.0).abs() < f64::EPSILON);
    } else {
        panic!("Expected second command");
    }

    if let Some(DspCommand::EqSetFrequency { freq, .. }) = audio_handle.poll_commands().next() {
        assert!((freq - 300.0).abs() < f64::EPSILON);
    } else {
        panic!("Expected third command");
    }

    // Queue should now be empty
    assert!(audio_handle.poll_commands().next().is_none());
}

#[test]
fn test_command_queue_capacity_constant() {
    // Verify the queue capacity is a reasonable power of 2
    assert!(COMMAND_QUEUE_SIZE > 0);
    assert!(
        COMMAND_QUEUE_SIZE.is_power_of_two(),
        "Queue size {} should be power of 2",
        COMMAND_QUEUE_SIZE
    );
    assert!(
        COMMAND_QUEUE_SIZE >= 1024,
        "Queue should have at least 1024 slots, has {}",
        COMMAND_QUEUE_SIZE
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// STRING HANDLING TESTS (C FFI Boundary)
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_cstring_basic_ascii() {
    let rust_str = "Hello, World!";
    let cstring = CString::new(rust_str).expect("CString creation failed");
    let back_to_str = cstring.to_str().expect("CString to str failed");
    assert_eq!(back_to_str, rust_str);
}

#[test]
fn test_cstring_utf8_characters() {
    let test_strings = [
        "cafe\u{0301}",                                                    // combining accent
        "\u{00e9}\u{00e8}\u{00ea}\u{00eb}",                                // precomposed accents
        "\u{4e16}\u{754c}",                                                // CJK characters
        "\u{1f3b5}",                                                       // music note emoji
        "Greetings from \u{0420}\u{043e}\u{0441}\u{0441}\u{0438}\u{044f}", // Cyrillic
        "\u{0639}\u{0631}\u{0628}\u{064a}",                                // Arabic
    ];

    for s in test_strings {
        let cstring = CString::new(s).expect(&format!("CString creation failed for '{}'", s));
        let back = cstring.to_str().expect("CString to str failed");
        assert_eq!(back, s, "UTF-8 roundtrip failed for '{}'", s);
    }
}

#[test]
fn test_cstring_empty() {
    let cstring = CString::new("").expect("Empty CString creation failed");
    let back = cstring.to_str().expect("Empty CString to str failed");
    assert_eq!(back, "");
}

#[test]
fn test_cstring_with_interior_nul_fails() {
    // CString cannot contain interior NUL bytes
    let result = CString::new("hello\0world");
    assert!(result.is_err(), "CString with interior NUL should fail");
}

#[test]
fn test_cstr_from_ptr_roundtrip() {
    let original = "test string for FFI";
    let cstring = CString::new(original).unwrap();
    let ptr = cstring.as_ptr();

    // Simulate receiving a C string pointer
    let recovered = unsafe { CStr::from_ptr(ptr) };
    let recovered_str = recovered.to_str().unwrap();
    assert_eq!(recovered_str, original);
}

#[test]
fn test_cstring_long_string() {
    // Test with a very long string (simulate large JSON payload)
    let long_string: String = "a".repeat(100_000);
    let cstring = CString::new(long_string.as_str()).expect("Long CString creation failed");
    let back = cstring.to_str().expect("Long CString to str failed");
    assert_eq!(back.len(), 100_000);
    assert_eq!(back, long_string);
}

// ═══════════════════════════════════════════════════════════════════════════════
// JSON SERIALIZATION THROUGH FFI TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_json_container_blend_format() {
    // Test that the expected JSON format for blend containers is valid
    let json = serde_json::json!({
        "id": 1,
        "name": "Test Blend",
        "curve": 0,
        "children": [
            {
                "id": 1,
                "name": "Child A",
                "audio_path": "/path/to/a.wav",
                "rtpc_min": 0.0,
                "rtpc_max": 50.0,
                "volume": 1.0
            },
            {
                "id": 2,
                "name": "Child B",
                "audio_path": "/path/to/b.wav",
                "rtpc_min": 50.0,
                "rtpc_max": 100.0,
                "volume": 0.8
            }
        ]
    });

    let json_str = serde_json::to_string(&json).unwrap();
    // Verify it can roundtrip through CString
    let cstring = CString::new(json_str.as_str()).unwrap();
    let back = cstring.to_str().unwrap();
    let parsed: serde_json::Value = serde_json::from_str(back).unwrap();
    assert_eq!(parsed["id"], 1);
    assert_eq!(parsed["name"], "Test Blend");
    assert_eq!(parsed["children"].as_array().unwrap().len(), 2);
}

#[test]
fn test_json_container_random_format() {
    let json = serde_json::json!({
        "id": 2,
        "name": "Test Random",
        "mode": 0,
        "children": [
            {
                "id": 1,
                "name": "Variant A",
                "audio_path": "/path/to/a.wav",
                "weight": 60
            },
            {
                "id": 2,
                "name": "Variant B",
                "audio_path": "/path/to/b.wav",
                "weight": 40
            }
        ]
    });

    let json_str = serde_json::to_string(&json).unwrap();
    let cstring = CString::new(json_str.as_str()).unwrap();
    let back = cstring.to_str().unwrap();
    let parsed: serde_json::Value = serde_json::from_str(back).unwrap();
    assert_eq!(parsed["id"], 2);
    assert_eq!(parsed["mode"], 0);
}

#[test]
fn test_json_special_characters_in_paths() {
    // Audio paths may contain special characters
    let special_paths = [
        "/path/with spaces/file.wav",
        "/path/with-dashes/file_underscore.wav",
        "/path/with(parens)/file.wav",
        "/unicode/\u{00e9}t\u{00e9}/sound.wav",
        "/deeply/nested/path/to/some/audio/file/in/a/directory/sound.wav",
    ];

    for path in special_paths {
        let json = serde_json::json!({
            "id": 1,
            "name": "test",
            "audio_path": path,
        });
        let json_str = serde_json::to_string(&json).unwrap();
        let cstring = CString::new(json_str.as_str()).unwrap();
        let back = cstring.to_str().unwrap();
        let parsed: serde_json::Value = serde_json::from_str(back).unwrap();
        assert_eq!(
            parsed["audio_path"], path,
            "Path roundtrip failed for: {}",
            path
        );
    }
}

#[test]
fn test_json_numeric_precision() {
    // Verify floating-point values survive JSON roundtrip
    let values = [
        0.0f64,
        1.0,
        -1.0,
        0.5,
        0.001,
        1e-10,
        1e10,
        std::f64::consts::PI,
        f64::MIN_POSITIVE,
    ];

    for val in values {
        let json = serde_json::json!({ "value": val });
        let json_str = serde_json::to_string(&json).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json_str).unwrap();
        let roundtripped = parsed["value"].as_f64().unwrap();
        assert!(
            (roundtripped - val).abs() < 1e-15,
            "Precision lost for {}: got {}",
            val,
            roundtripped
        );
    }
}

#[test]
fn test_json_nan_inf_handling() {
    // JSON spec does not support NaN/Inf - verify serde behavior
    let nan_result = serde_json::to_string(&serde_json::json!(f64::NAN));
    // serde_json will error on NaN
    assert!(
        nan_result.is_err() || {
            let s = nan_result.unwrap();
            s.contains("null") || s.contains("NaN")
        }
    );

    let inf_result = serde_json::to_string(&serde_json::json!(f64::INFINITY));
    assert!(
        inf_result.is_err() || {
            let s = inf_result.unwrap();
            s.contains("null") || s.contains("Infinity")
        }
    );
}

// ═══════════════════════════════════════════════════════════════════════════════
// PARAMETER BOUNDS & EDGE CASE TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_filter_type_repr_u8_matches() {
    // Verify repr(u8) values match expected enum discriminants
    assert_eq!(FilterType::Bell as u8, 0);
    assert_eq!(FilterType::LowShelf as u8, 1);
    assert_eq!(FilterType::HighShelf as u8, 2);
    assert_eq!(FilterType::LowCut as u8, 3);
    assert_eq!(FilterType::HighCut as u8, 4);
    assert_eq!(FilterType::Notch as u8, 5);
    assert_eq!(FilterType::Bandpass as u8, 6);
    assert_eq!(FilterType::TiltShelf as u8, 7);
    assert_eq!(FilterType::Allpass as u8, 8);
    assert_eq!(FilterType::Brickwall as u8, 9);
}

#[test]
fn test_filter_slope_repr_u8_matches() {
    assert_eq!(FilterSlope::Db6 as u8, 0);
    assert_eq!(FilterSlope::Db12 as u8, 1);
    assert_eq!(FilterSlope::Db18 as u8, 2);
    assert_eq!(FilterSlope::Db24 as u8, 3);
    assert_eq!(FilterSlope::Db36 as u8, 4);
    assert_eq!(FilterSlope::Db48 as u8, 5);
    assert_eq!(FilterSlope::Db72 as u8, 6);
    assert_eq!(FilterSlope::Db96 as u8, 7);
}

#[test]
fn test_error_category_repr_u8_matches() {
    assert_eq!(FFIErrorCategory::InvalidInput as u8, 1);
    assert_eq!(FFIErrorCategory::OutOfBounds as u8, 2);
    assert_eq!(FFIErrorCategory::InvalidState as u8, 3);
    assert_eq!(FFIErrorCategory::NotFound as u8, 4);
    assert_eq!(FFIErrorCategory::ResourceExhausted as u8, 5);
    assert_eq!(FFIErrorCategory::IOError as u8, 6);
    assert_eq!(FFIErrorCategory::SerializationError as u8, 7);
    assert_eq!(FFIErrorCategory::AudioError as u8, 8);
    assert_eq!(FFIErrorCategory::SyncError as u8, 9);
    assert_eq!(FFIErrorCategory::Unknown as u8, 255);
}

#[test]
fn test_full_u8_range_filter_type_no_panic() {
    // Verify that every u8 value converts without panicking
    for i in 0u8..=255 {
        let _ = FilterType::from(i);
    }
}

#[test]
fn test_full_u8_range_filter_slope_no_panic() {
    for i in 0u8..=255 {
        let _ = FilterSlope::from(i);
    }
}

#[test]
fn test_full_u8_range_phase_mode_no_panic() {
    for i in 0u8..=255 {
        let _ = PhaseMode::from(i);
    }
}

#[test]
fn test_full_u8_range_stereo_placement_no_panic() {
    for i in 0u8..=255 {
        let _ = StereoPlacement::from(i);
    }
}

#[test]
fn test_full_u8_range_analyzer_mode_no_panic() {
    for i in 0u8..=255 {
        let _ = AnalyzerMode::from(i);
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// STRESS / COMBINED TESTS
// ═══════════════════════════════════════════════════════════════════════════════

#[test]
fn test_bounds_check_stress_sequential() {
    // Stress test: check many indices rapidly
    let len = 1000;
    for i in 0..len as i64 {
        assert!(check_index(i, len).is_valid());
    }
    // All out of bounds
    for i in len as i64..(len as i64 + 100) {
        assert!(!check_index(i, len).is_valid());
    }
}

#[test]
fn test_error_creation_stress() {
    // Create many errors and verify they don't leak or corrupt
    let mut errors = Vec::with_capacity(1000);
    for i in 0..1000u16 {
        let err = FFIError::new(
            FFIErrorCategory::AudioError,
            i,
            format!("Error number {}", i),
        );
        errors.push(err);
    }

    for (i, err) in errors.iter().enumerate() {
        assert_eq!(err.code, i as u16);
        assert_eq!(err.message, format!("Error number {}", i));
    }
}

#[test]
fn test_command_queue_high_throughput() {
    let queue = CommandQueueManager::new();
    let (mut ui_handle, mut audio_handle) = queue.split();

    // Send many commands rapidly
    let count = 1000;
    for i in 0..count {
        let cmd = DspCommand::EqSetFrequency {
            track_id: 0,
            band_index: (i % 64) as u8,
            freq: i as f64 * 10.0,
        };
        assert!(ui_handle.send(cmd), "Failed to send command {}", i);
    }

    // Receive all and verify order via poll_commands
    for i in 0..count {
        let received = audio_handle.poll_commands().next();
        assert!(received.is_some(), "Missing command at index {}", i);
        if let Some(DspCommand::EqSetFrequency { freq, .. }) = received {
            let expected = i as f64 * 10.0;
            assert!(
                (freq - expected).abs() < f64::EPSILON,
                "Command {} has wrong freq: expected {}, got {}",
                i,
                expected,
                freq
            );
        }
    }

    // Queue should be empty
    assert!(audio_handle.poll_commands().next().is_none());
}

#[test]
fn test_json_large_payload_roundtrip() {
    // Simulate a large container with many children
    let children: Vec<serde_json::Value> = (0..100)
        .map(|i| {
            serde_json::json!({
                "id": i,
                "name": format!("Child_{}", i),
                "audio_path": format!("/audio/variant_{}.wav", i),
                "weight": (i % 10) + 1,
                "volume": 0.5 + (i as f64 * 0.005),
            })
        })
        .collect();

    let json = serde_json::json!({
        "id": 999,
        "name": "Massive Container",
        "mode": 0,
        "children": children,
    });

    let json_str = serde_json::to_string(&json).unwrap();
    assert!(
        json_str.len() > 5000,
        "JSON should be substantial: {} bytes",
        json_str.len()
    );

    // Roundtrip through CString
    let cstring = CString::new(json_str.as_str()).unwrap();
    let back = cstring.to_str().unwrap();
    let parsed: serde_json::Value = serde_json::from_str(back).unwrap();
    assert_eq!(parsed["children"].as_array().unwrap().len(), 100);
    assert_eq!(parsed["id"], 999);
}

#[test]
fn test_safe_access_with_various_types() {
    // Test safe_get with different element types
    let floats = vec![1.0f64, 2.0, 3.0, 4.0];
    assert_eq!(safe_get(&floats, 0), Some(&1.0));
    assert_eq!(safe_get(&floats, 3), Some(&4.0));
    assert_eq!(safe_get(&floats, 4), None);

    let strings = vec!["hello", "world", "test"];
    assert_eq!(safe_get(&strings, 1), Some(&"world"));
    assert_eq!(safe_get(&strings, -1), None);

    let bools = vec![true, false, true];
    assert_eq!(safe_get(&bools, 2), Some(&true));
    assert_eq!(safe_get(&bools, 3), None);
}

#[test]
fn test_ffi_error_category_display() {
    let categories = [
        (FFIErrorCategory::InvalidInput, "Invalid Input"),
        (FFIErrorCategory::OutOfBounds, "Out of Bounds"),
        (FFIErrorCategory::InvalidState, "Invalid State"),
        (FFIErrorCategory::NotFound, "Not Found"),
        (FFIErrorCategory::ResourceExhausted, "Resource Exhausted"),
        (FFIErrorCategory::IOError, "I/O Error"),
        (FFIErrorCategory::SerializationError, "Serialization Error"),
        (FFIErrorCategory::AudioError, "Audio Error"),
        (FFIErrorCategory::SyncError, "Synchronization Error"),
        (FFIErrorCategory::Unknown, "Unknown Error"),
    ];

    for (cat, expected_display) in categories {
        let display = format!("{}", cat);
        assert_eq!(
            display, expected_display,
            "Display for {:?} should be '{}'",
            cat, expected_display
        );
    }
}
