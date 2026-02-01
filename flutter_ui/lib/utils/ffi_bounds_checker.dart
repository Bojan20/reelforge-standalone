/// FluxForge FFI Bounds Checker — Dart-Side Validation
///
/// Pre-validates parameters before FFI calls to prevent:
/// - Negative indices (Dart int can be negative, Rust usize cannot)
/// - Array out-of-bounds access
/// - Buffer overflows
/// - Integer overflow/underflow
///
/// Complements Rust ffi_bounds module for defense-in-depth.

/// Result of FFI bounds validation
class FFIBoundsResult {
  final bool isValid;
  final String? error;

  const FFIBoundsResult.valid()
      : isValid = true,
        error = null;

  const FFIBoundsResult.invalid(this.error) : isValid = false;

  /// Throw exception if invalid (for critical paths)
  void throwIfInvalid() {
    if (!isValid) {
      throw ArgumentError(error);
    }
  }
}

/// Ultimate FFI bounds checker for Dart→Rust calls
class FFIBoundsChecker {
  // =============================================================================
  // CONFIGURATION
  // =============================================================================

  /// Maximum safe integer for Dart→Rust FFI (i64::MAX)
  static const int maxSafeInt = 9223372036854775807;

  /// Minimum safe integer for Dart→Rust FFI (i64::MIN)
  static const int minSafeInt = -9223372036854775808;

  /// Maximum array index (usize::MAX on 64-bit, but we use conservative limit)
  static const int maxArrayIndex = 2147483647; // 2^31 - 1

  /// Maximum buffer size (prevent memory exhaustion)
  static const int maxBufferSize = 536870912; // 512 MB

  // =============================================================================
  // INDEX VALIDATION
  // =============================================================================

  /// Validate single index for array access
  ///
  /// [index] - Index from Dart (may be negative)
  /// [arrayLength] - Length of Rust array/vector
  ///
  /// Returns valid result if index is within [0, arrayLength)
  static FFIBoundsResult checkIndex(int index, int arrayLength) {
    // Check for negative index
    if (index < 0) {
      return FFIBoundsResult.invalid(
        'Negative index $index (array access requires non-negative)',
      );
    }

    // Check for out-of-bounds
    if (index >= arrayLength) {
      return FFIBoundsResult.invalid(
        'Index $index out of bounds (array length: $arrayLength)',
      );
    }

    // Check for unreasonably large index (potential overflow)
    if (index > maxArrayIndex) {
      return FFIBoundsResult.invalid(
        'Index $index exceeds maximum safe array index ($maxArrayIndex)',
      );
    }

    return const FFIBoundsResult.valid();
  }

  /// Validate range [start, end) for slice access
  ///
  /// [start] - Start index (inclusive)
  /// [end] - End index (exclusive)
  /// [arrayLength] - Length of Rust array/vector
  ///
  /// Returns valid result if range is within [0, arrayLength]
  static FFIBoundsResult checkRange(int start, int end, int arrayLength) {
    // Check for negative indices
    if (start < 0) {
      return FFIBoundsResult.invalid(
        'Negative start index $start',
      );
    }

    if (end < 0) {
      return FFIBoundsResult.invalid(
        'Negative end index $end',
      );
    }

    // Check for invalid range
    if (start > end) {
      return FFIBoundsResult.invalid(
        'Invalid range: start ($start) > end ($end)',
      );
    }

    // Check for out-of-bounds
    if (end > arrayLength) {
      return FFIBoundsResult.invalid(
        'Range [$start, $end) exceeds array length ($arrayLength)',
      );
    }

    return const FFIBoundsResult.valid();
  }

  // =============================================================================
  // INTEGER VALIDATION
  // =============================================================================

  /// Validate integer is within safe FFI range (i64)
  ///
  /// [value] - Integer value to validate
  ///
  /// Returns valid result if value fits in i64
  static FFIBoundsResult checkInt(int value) {
    if (value < minSafeInt || value > maxSafeInt) {
      return FFIBoundsResult.invalid(
        'Integer $value out of safe FFI range [$minSafeInt, $maxSafeInt]',
      );
    }

    return const FFIBoundsResult.valid();
  }

  /// Validate unsigned integer (maps to u64 in Rust)
  ///
  /// [value] - Integer value to validate (must be non-negative)
  ///
  /// Returns valid result if value is non-negative and fits in u64
  static FFIBoundsResult checkUInt(int value) {
    if (value < 0) {
      return FFIBoundsResult.invalid(
        'Unsigned integer cannot be negative (got $value)',
      );
    }

    if (value > maxSafeInt) {
      return FFIBoundsResult.invalid(
        'Unsigned integer $value exceeds u64 range',
      );
    }

    return const FFIBoundsResult.valid();
  }

  // =============================================================================
  // BUFFER VALIDATION
  // =============================================================================

  /// Validate buffer size before FFI transfer
  ///
  /// [bufferSize] - Size of buffer in bytes
  ///
  /// Returns valid result if buffer size is reasonable
  static FFIBoundsResult checkBufferSize(int bufferSize) {
    if (bufferSize < 0) {
      return FFIBoundsResult.invalid(
        'Buffer size cannot be negative (got $bufferSize)',
      );
    }

    if (bufferSize > maxBufferSize) {
      return FFIBoundsResult.invalid(
        'Buffer size $bufferSize exceeds maximum ($maxBufferSize bytes)',
      );
    }

    return const FFIBoundsResult.valid();
  }

  /// Validate buffer sizes match (for copy operations)
  ///
  /// [expected] - Expected buffer size
  /// [actual] - Actual buffer size provided
  ///
  /// Returns valid result if sizes match
  static FFIBoundsResult checkBufferMatch(int expected, int actual) {
    if (expected != actual) {
      return FFIBoundsResult.invalid(
        'Buffer size mismatch: expected $expected, got $actual',
      );
    }

    return const FFIBoundsResult.valid();
  }

  // =============================================================================
  // FLOAT VALIDATION
  // =============================================================================

  /// Validate float is finite (not NaN or Infinity)
  ///
  /// [value] - Double value to validate
  /// [paramName] - Parameter name for error message
  ///
  /// Returns valid result if value is finite
  static FFIBoundsResult checkFinite(double value, String paramName) {
    if (value.isNaN) {
      return FFIBoundsResult.invalid(
        '$paramName is NaN (not a number)',
      );
    }

    if (value.isInfinite) {
      return FFIBoundsResult.invalid(
        '$paramName is infinite',
      );
    }

    return const FFIBoundsResult.valid();
  }

  /// Validate float is within range
  ///
  /// [value] - Double value to validate
  /// [min] - Minimum allowed value (inclusive)
  /// [max] - Maximum allowed value (inclusive)
  /// [paramName] - Parameter name for error message
  ///
  /// Returns valid result if value is within [min, max]
  static FFIBoundsResult checkRange01(double value, double min, double max, String paramName) {
    final finiteCheck = checkFinite(value, paramName);
    if (!finiteCheck.isValid) {
      return finiteCheck;
    }

    if (value < min || value > max) {
      return FFIBoundsResult.invalid(
        '$paramName $value out of range [$min, $max]',
      );
    }

    return const FFIBoundsResult.valid();
  }

  // =============================================================================
  // COMMON AUDIO PARAMETER VALIDATORS
  // =============================================================================

  /// Validate volume parameter (0.0 to 4.0, allowing +12dB boost)
  static FFIBoundsResult checkVolume(double volume) {
    return checkRange01(volume, 0.0, 4.0, 'volume');
  }

  /// Validate pan parameter (-1.0 to +1.0)
  static FFIBoundsResult checkPan(double pan) {
    return checkRange01(pan, -1.0, 1.0, 'pan');
  }

  /// Validate gain in dB (-60dB to +12dB)
  static FFIBoundsResult checkGainDb(double gainDb) {
    return checkRange01(gainDb, -60.0, 12.0, 'gainDb');
  }

  /// Validate frequency (20 Hz to 20 kHz)
  static FFIBoundsResult checkFrequency(double frequency) {
    return checkRange01(frequency, 20.0, 20000.0, 'frequency');
  }

  /// Validate Q factor (0.1 to 10.0)
  static FFIBoundsResult checkQ(double q) {
    return checkRange01(q, 0.1, 10.0, 'q');
  }

  /// Validate sample rate (44.1 kHz to 384 kHz)
  static FFIBoundsResult checkSampleRate(int sampleRate) {
    if (sampleRate < 44100 || sampleRate > 384000) {
      return FFIBoundsResult.invalid(
        'Sample rate $sampleRate out of range [44100, 384000]',
      );
    }
    return const FFIBoundsResult.valid();
  }

  /// Validate buffer size (32 to 4096 samples)
  static FFIBoundsResult checkAudioBufferSize(int bufferSize) {
    if (bufferSize < 32 || bufferSize > 4096) {
      return FFIBoundsResult.invalid(
        'Buffer size $bufferSize out of range [32, 4096]',
      );
    }

    // Must be power of 2
    if (bufferSize & (bufferSize - 1) != 0) {
      return FFIBoundsResult.invalid(
        'Buffer size $bufferSize must be power of 2',
      );
    }

    return const FFIBoundsResult.valid();
  }

  // =============================================================================
  // SLOT LAB SPECIFIC VALIDATORS
  // =============================================================================

  /// Validate reel index (0-9 for up to 10 reels)
  static FFIBoundsResult checkReelIndex(int reelIndex, int totalReels) {
    return checkIndex(reelIndex, totalReels);
  }

  /// Validate row index (0-6 for up to 7 rows)
  static FFIBoundsResult checkRowIndex(int rowIndex, int totalRows) {
    return checkIndex(rowIndex, totalRows);
  }

  /// Validate symbol ID (0-99 for symbol registry)
  static FFIBoundsResult checkSymbolId(int symbolId) {
    const maxSymbols = 100;
    return checkIndex(symbolId, maxSymbols);
  }

  /// Validate tier index (0-6 for win tiers)
  static FFIBoundsResult checkTierIndex(int tierIndex) {
    const maxTiers = 7; // WIN_LOW, WIN_EQUAL, WIN_1..5
    return checkIndex(tierIndex, maxTiers);
  }

  /// Validate big win tier index (0-4 for BIG_WIN_TIER_1..5)
  static FFIBoundsResult checkBigWinTierIndex(int tierIndex) {
    const maxBigWinTiers = 5;
    return checkIndex(tierIndex, maxBigWinTiers);
  }

  /// Validate jackpot tier index (0-4 for Mini/Minor/Major/Mega/Grand)
  static FFIBoundsResult checkJackpotTierIndex(int tierIndex) {
    const maxJackpotTiers = 5;
    return checkIndex(tierIndex, maxJackpotTiers);
  }

  /// Validate gamble choice index (0-99 for various gamble types)
  static FFIBoundsResult checkGambleChoiceIndex(int choiceIndex) {
    const maxChoices = 100;
    return checkIndex(choiceIndex, maxChoices);
  }

  // =============================================================================
  // DSP PARAMETER VALIDATORS
  // =============================================================================

  /// Validate EQ band index (0-63 for 64-band EQ)
  static FFIBoundsResult checkEqBandIndex(int bandIndex) {
    const maxBands = 64;
    return checkIndex(bandIndex, maxBands);
  }

  /// Validate insert slot index (0-7 for 8 insert slots)
  static FFIBoundsResult checkInsertSlotIndex(int slotIndex) {
    const maxInserts = 8;
    return checkIndex(slotIndex, maxInserts);
  }

  /// Validate bus ID (0-15 for 16 buses)
  static FFIBoundsResult checkBusId(int busId) {
    const maxBuses = 16;
    return checkIndex(busId, maxBuses);
  }

  /// Validate track ID (0-255 for 256 tracks)
  static FFIBoundsResult checkTrackId(int trackId) {
    const maxTracks = 256;
    return checkIndex(trackId, maxTracks);
  }

  // =============================================================================
  // BATCH VALIDATION
  // =============================================================================

  /// Validate multiple indices at once
  ///
  /// Returns first error encountered, or valid result if all pass
  static FFIBoundsResult checkIndices(List<int> indices, int arrayLength) {
    for (int i = 0; i < indices.length; i++) {
      final result = checkIndex(indices[i], arrayLength);
      if (!result.isValid) {
        return FFIBoundsResult.invalid(
          'Batch validation failed at index $i: ${result.error}',
        );
      }
    }

    return const FFIBoundsResult.valid();
  }

  // =============================================================================
  // UTILITY METHODS
  // =============================================================================

  /// Clamp index to valid range (safe alternative to throwing error)
  ///
  /// [index] - Potentially invalid index
  /// [arrayLength] - Array length
  ///
  /// Returns clamped index guaranteed to be in [0, arrayLength)
  static int clampIndex(int index, int arrayLength) {
    if (index < 0) return 0;
    if (index >= arrayLength) return arrayLength - 1;
    return index;
  }

  /// Clamp value to range
  ///
  /// [value] - Value to clamp
  /// [min] - Minimum value
  /// [max] - Maximum value
  ///
  /// Returns clamped value in [min, max]
  static double clampDouble(double value, double min, double max) {
    if (value.isNaN) return min;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// Safe integer conversion (prevents overflow on 32-bit platforms)
  ///
  /// [value] - Integer value
  ///
  /// Returns value if safe, throws ArgumentError otherwise
  static int toSafeInt(int value) {
    if (value < minSafeInt || value > maxSafeInt) {
      throw ArgumentError(
        'Integer $value out of safe FFI range [$minSafeInt, $maxSafeInt]',
      );
    }
    return value;
  }
}
