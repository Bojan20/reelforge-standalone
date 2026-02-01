/// FluxForge FFI Error Handler — Dart-Side Error Management
///
/// Parses and handles errors from Rust FFI layer.
///
/// Error JSON format from Rust:
/// ```json
/// {
///   "category": 1,
///   "code": 100,
///   "message": "Invalid parameter",
///   "context": "function_name",
///   "suggestion": "Try passing valid values"
/// }
/// ```

import 'dart:convert';

/// Error category matching Rust FFIErrorCategory
enum FFIErrorCategory {
  invalidInput(1),
  outOfBounds(2),
  invalidState(3),
  notFound(4),
  resourceExhausted(5),
  ioError(6),
  serializationError(7),
  audioError(8),
  syncError(9),
  unknown(255);

  final int value;
  const FFIErrorCategory(this.value);

  static FFIErrorCategory fromValue(int value) {
    return FFIErrorCategory.values.firstWhere(
      (c) => c.value == value,
      orElse: () => FFIErrorCategory.unknown,
    );
  }

  String get displayName {
    switch (this) {
      case FFIErrorCategory.invalidInput:
        return 'Invalid Input';
      case FFIErrorCategory.outOfBounds:
        return 'Out of Bounds';
      case FFIErrorCategory.invalidState:
        return 'Invalid State';
      case FFIErrorCategory.notFound:
        return 'Not Found';
      case FFIErrorCategory.resourceExhausted:
        return 'Resource Exhausted';
      case FFIErrorCategory.ioError:
        return 'I/O Error';
      case FFIErrorCategory.serializationError:
        return 'Serialization Error';
      case FFIErrorCategory.audioError:
        return 'Audio Error';
      case FFIErrorCategory.syncError:
        return 'Synchronization Error';
      case FFIErrorCategory.unknown:
        return 'Unknown Error';
    }
  }
}

/// Parsed FFI error from Rust
class FFIError {
  final FFIErrorCategory category;
  final int code;
  final String message;
  final String? context;
  final String? suggestion;

  const FFIError({
    required this.category,
    required this.code,
    required this.message,
    this.context,
    this.suggestion,
  });

  /// Parse error from JSON string returned by Rust FFI
  factory FFIError.fromJson(String jsonString) {
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      return FFIError(
        category: FFIErrorCategory.fromValue(json['category'] as int),
        code: json['code'] as int,
        message: json['message'] as String,
        context: json['context'] as String?,
        suggestion: json['suggestion'] as String?,
      );
    } catch (e) {
      // Fallback if JSON parsing fails
      return FFIError(
        category: FFIErrorCategory.unknown,
        code: 0,
        message: 'Failed to parse error JSON: $e',
        context: 'FFIError.fromJson',
      );
    }
  }

  /// Create error from full error code (u32)
  /// High 16 bits = category, low 16 bits = code
  factory FFIError.fromFullCode(int fullCode, String message) {
    final category = (fullCode >> 16) & 0xFF;
    final code = fullCode & 0xFFFF;

    return FFIError(
      category: FFIErrorCategory.fromValue(category),
      code: code,
      message: message,
    );
  }

  /// Get full error code for FFI communication
  int get fullCode => (category.value << 16) | code;

  /// Get display-friendly error message
  String get displayMessage {
    final buffer = StringBuffer();
    buffer.write('[${category.displayName}:$code] $message');

    if (context != null) {
      buffer.write(' (in $context)');
    }

    if (suggestion != null) {
      buffer.write('\n💡 $suggestion');
    }

    return buffer.toString();
  }

  /// Check if error is recoverable
  bool get isRecoverable {
    switch (category) {
      case FFIErrorCategory.invalidInput:
      case FFIErrorCategory.notFound:
        return true; // User can correct input or retry

      case FFIErrorCategory.outOfBounds:
      case FFIErrorCategory.resourceExhausted:
        return true; // Can retry with valid parameters

      case FFIErrorCategory.invalidState:
      case FFIErrorCategory.syncError:
        return false; // Requires restart or reset

      case FFIErrorCategory.ioError:
      case FFIErrorCategory.serializationError:
      case FFIErrorCategory.audioError:
      case FFIErrorCategory.unknown:
        return false; // System-level issues
    }
  }

  @override
  String toString() => displayMessage;
}

/// Exception thrown for FFI errors
class FFIException implements Exception {
  final FFIError error;

  const FFIException(this.error);

  @override
  String toString() => 'FFIException: ${error.displayMessage}';
}

// =============================================================================
// ERROR HANDLER UTILITY
// =============================================================================

/// Centralized FFI error handling
class FFIErrorHandler {
  /// Parse error from FFI function result
  ///
  /// For functions returning error as JSON string:
  /// ```dart
  /// final errorJson = nativeFFI.someFunction();
  /// if (errorJson != null) {
  ///   final error = FFIErrorHandler.parseError(errorJson);
  ///   // Handle error
  /// }
  /// ```
  static FFIError? parseError(String? errorJson) {
    if (errorJson == null || errorJson.isEmpty) {
      return null;
    }

    try {
      return FFIError.fromJson(errorJson);
    } catch (e) {
      // Fallback: treat as generic error message
      return FFIError(
        category: FFIErrorCategory.unknown,
        code: 0,
        message: errorJson,
      );
    }
  }

  /// Handle error with optional callback
  ///
  /// Returns true if error was handled, false otherwise
  static bool handleError(
    FFIError error, {
    void Function(FFIError)? onError,
    bool throwOnError = false,
  }) {
    // Log error
    print('[FFIErrorHandler] ${error.displayMessage}');

    // Call custom handler if provided
    onError?.call(error);

    // Throw exception if requested
    if (throwOnError) {
      throw FFIException(error);
    }

    return true;
  }

  /// Check FFI function result and handle errors
  ///
  /// For functions returning JSON error string on failure:
  /// ```dart
  /// final result = FFIErrorHandler.checkResult(
  ///   nativeFFI.someFunction(),
  ///   onError: (err) => showSnackBar(err.message),
  /// );
  /// ```
  static T? checkResult<T>(
    T? result, {
    String? errorJson,
    void Function(FFIError)? onError,
    bool throwOnError = false,
  }) {
    if (errorJson != null) {
      final error = parseError(errorJson);
      if (error != null) {
        handleError(error, onError: onError, throwOnError: throwOnError);
        return null;
      }
    }

    return result;
  }
}

// =============================================================================
// COMMON ERROR CODES
// =============================================================================

/// Common FFI error codes by category
class FFIErrorCodes {
  // Invalid Input (1xx)
  static const int invalidInputGeneric = 100;
  static const int invalidInputNegativeIndex = 101;
  static const int invalidInputNullPointer = 102;
  static const int invalidInputInvalidRange = 103;
  static const int invalidInputInvalidEnum = 104;

  // Out of Bounds (2xx)
  static const int outOfBoundsArrayIndex = 200;
  static const int outOfBoundsBufferOverflow = 201;
  static const int outOfBoundsPointerOffset = 202;

  // Invalid State (3xx)
  static const int invalidStateNotInitialized = 300;
  static const int invalidStateAlreadyInitialized = 301;
  static const int invalidStateEngineNotRunning = 302;
  static const int invalidStateEngineShutdown = 303;

  // Not Found (4xx)
  static const int notFoundEvent = 400;
  static const int notFoundTrack = 401;
  static const int notFoundBus = 402;
  static const int notFoundPlugin = 403;
  static const int notFoundFile = 404;

  // Resource Exhausted (5xx)
  static const int resourceExhaustedVoicePool = 500;
  static const int resourceExhaustedMemory = 501;
  static const int resourceExhaustedCPU = 502;

  // I/O Error (6xx)
  static const int ioErrorFileNotFound = 600;
  static const int ioErrorPermissionDenied = 601;
  static const int ioErrorReadFailure = 602;
  static const int ioErrorWriteFailure = 603;

  // Serialization Error (7xx)
  static const int serializationJsonParseError = 700;
  static const int serializationJsonEncodeError = 701;
  static const int serializationBinaryParseError = 702;

  // Audio Error (8xx)
  static const int audioErrorPlaybackFailed = 800;
  static const int audioErrorDeviceNotFound = 801;
  static const int audioErrorBufferUnderrun = 802;
  static const int audioErrorFormatNotSupported = 803;
}
