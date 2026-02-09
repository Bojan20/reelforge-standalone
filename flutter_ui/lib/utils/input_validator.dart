/// Input Validation Utility (P0.3)
///
/// Security utilities for validating and sanitizing user input.
///
/// CRITICAL: All file paths, user names, and FFI parameters MUST be validated
/// before use to prevent:
/// - Path traversal attacks (../, ../../etc/passwd)
/// - Injection attacks (HTML/JS in names)
/// - Buffer overflows (invalid FFI parameters)
///
/// Created: 2026-01-26
library;

import 'dart:io';

// ═══════════════════════════════════════════════════════════════════════════
// PATH VALIDATOR
// ═══════════════════════════════════════════════════════════════════════════

/// Validates and sanitizes file paths
class PathValidator {
  /// Allowed audio file extensions — ALL known audio formats.
  /// Keep in sync with PathValidator._allowedExtensions (SSoT).
  static const allowedAudioExtensions = [
    // Uncompressed / PCM
    'wav', 'wave', 'aiff', 'aif', 'aifc', 'au', 'snd', 'raw', 'pcm',
    'caf', 'w64', 'rf64', 'bwf', 'sd2', 'voc', 'avr', 'pvf',
    'ircam', 'sf', 'htk', 'sph', 'nist', 'svx', '8svx', 'paf', 'fap',
    // Lossless Compressed
    'flac', 'alac', 'ape', 'wv', 'tta', 'tak', 'ofr', 'ofs',
    'wma', 'shn', 'la', 'mlp',
    // Lossy Compressed
    'mp3', 'ogg', 'oga', 'opus', 'm4a', 'aac', 'mp4', 'mp2', 'mp1',
    'mpc', 'mp+', 'mpp', 'spx', 'ac3', 'eac3', 'ec3', 'dts',
    'ra', 'ram', 'amr', 'awb', 'gsm', 'adts',
    // DSD
    'dsf', 'dff', 'dsd',
    // Module / Tracker
    'mid', 'midi', 'mod', 'xm', 'it', 's3m', 'stm',
    // Web / Streaming
    'webm', 'weba', 'mka',
    // Game Audio
    'wem', 'bnk', 'fsb', 'xwm', 'xwma', 'brstm', 'bcstm', 'bfstm',
    'adx', 'hca', 'at3', 'at9', 'vag', 'xma', 'xma2',
  ];

  /// Allowed project file extensions
  static const allowedProjectExtensions = [
    'ffproj',
    'json',
    'ffbank',
    'ffstate',
    'ffxcontainer',
  ];

  /// Validate audio file path
  ///
  /// Checks:
  /// - No path traversal (..)
  /// - Canonical path within project root (if provided)
  /// - Extension whitelist
  /// - File exists (optional)
  ///
  /// Returns null if valid, error message otherwise.
  static String? validate(
    String path, {
    String? projectRoot,
    bool checkExists = false,
  }) {
    if (path.isEmpty) {
      return 'Path cannot be empty';
    }

    // 1. Check for path traversal
    if (path.contains('..')) {
      return 'Invalid path: parent directory traversal not allowed';
    }

    // 2. Check for dangerous characters (cross-platform)
    if (path.contains(RegExp(r'[<>:"|?*]'))) {
      return 'Invalid path: contains illegal characters';
    }

    // 3. Canonicalize path
    final file = File(path);
    final canonical = file.absolute.path;

    // 4. Check if within project root (if provided)
    if (projectRoot != null && projectRoot.isNotEmpty) {
      final rootCanonical = Directory(projectRoot).absolute.path;
      if (!canonical.startsWith(rootCanonical)) {
        return 'Invalid path: outside project directory ($projectRoot)';
      }
    }

    // 5. Check file extension whitelist
    final ext = path.split('.').last.toLowerCase();
    if (!allowedAudioExtensions.contains(ext)) {
      return 'Invalid file type: $ext not supported (allowed: ${allowedAudioExtensions.join(", ")})';
    }

    // 6. Check file exists (optional)
    if (checkExists && !file.existsSync()) {
      return 'File does not exist: $path';
    }

    return null; // Valid
  }

  /// Validate project file path
  static String? validateProjectPath(
    String path, {
    bool checkExists = false,
  }) {
    if (path.isEmpty) return 'Path cannot be empty';
    if (path.contains('..')) return 'Invalid path: traversal not allowed';

    final ext = path.split('.').last.toLowerCase();
    if (!allowedProjectExtensions.contains(ext)) {
      return 'Invalid project file type: $ext (allowed: ${allowedProjectExtensions.join(", ")})';
    }

    if (checkExists && !File(path).existsSync()) {
      return 'Project file does not exist: $path';
    }

    return null;
  }

  /// Sanitize path by removing dangerous characters
  static String sanitizePath(String path) {
    // Remove dangerous characters (cross-platform)
    String sanitized = path.replaceAll(RegExp(r'[<>:"|?*]'), '');
    // Normalize slashes (use platform-specific separator)
    sanitized = sanitized.replaceAll('\\', Platform.pathSeparator);
    sanitized = sanitized.replaceAll('/', Platform.pathSeparator);
    return sanitized.trim();
  }

  /// Check if file extension is audio
  static bool isAudioFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return allowedAudioExtensions.contains(ext);
  }

  /// Get canonical absolute path (safe)
  static String? getCanonicalPath(String path) {
    try {
      return File(path).absolute.path;
    } catch (e) {
      return null; // Invalid path
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// INPUT SANITIZER
// ═══════════════════════════════════════════════════════════════════════════

/// Sanitizes and validates user text input (names, labels, etc.)
class InputSanitizer {
  /// Regex for valid names (alphanumeric + spaces + dashes + underscores)
  static final _nameRegex = RegExp(r'^[a-zA-Z0-9_\- ]{1,64}$');

  /// Regex for valid identifiers (no spaces, stricter)
  static final _identifierRegex = RegExp(r'^[a-zA-Z0-9_\-]{1,64}$');

  /// Validate name input (track names, preset names, etc.)
  ///
  /// Allowed: Letters, numbers, spaces, dashes, underscores
  /// Max length: 64 characters
  ///
  /// Returns null if valid, error message otherwise.
  static String? validateName(String input) {
    if (input.isEmpty) {
      return 'Name cannot be empty';
    }

    if (input.length > 64) {
      return 'Name too long (max 64 characters)';
    }

    if (!_nameRegex.hasMatch(input)) {
      return 'Invalid characters (only letters, numbers, spaces, dashes, underscores allowed)';
    }

    // Check for all spaces/dashes
    if (input.trim().isEmpty) {
      return 'Name cannot be only spaces';
    }

    return null; // Valid
  }

  /// Validate identifier (stricter than name, no spaces)
  static String? validateIdentifier(String input) {
    if (input.isEmpty) {
      return 'Identifier cannot be empty';
    }

    if (input.length > 64) {
      return 'Identifier too long (max 64 characters)';
    }

    if (!_identifierRegex.hasMatch(input)) {
      return 'Invalid identifier (only letters, numbers, dashes, underscores allowed)';
    }

    return null;
  }

  /// Sanitize name by removing dangerous characters
  static String sanitizeName(String input) {
    // Remove all non-alphanumeric except spaces, dashes, underscores
    String sanitized = input.replaceAll(RegExp(r'[^\w\s\-]'), '');
    // Collapse multiple spaces
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ');
    // Trim and limit length
    sanitized = sanitized.trim();
    if (sanitized.length > 64) {
      sanitized = sanitized.substring(0, 64);
    }
    return sanitized;
  }

  /// Sanitize identifier (stricter, no spaces)
  static String sanitizeIdentifier(String input) {
    // Remove all non-alphanumeric except dashes, underscores
    String sanitized = input.replaceAll(RegExp(r'[^\w\-]'), '');
    // Trim and limit length
    if (sanitized.length > 64) {
      sanitized = sanitized.substring(0, 64);
    }
    return sanitized;
  }

  /// Check if input contains potentially dangerous characters
  static bool hasDangerousCharacters(String input) {
    // HTML/JS injection attempts
    if (input.contains(RegExp(r'''[<>"']'''))) return true;
    // SQL-like injection
    if (input.contains(RegExp(r'[;\\]'))) return true;
    // Path traversal
    if (input.contains('..')) return true;
    return false;
  }

  /// Remove HTML/XSS characters
  static String removeHtml(String input) {
    return input
        .replaceAll('<', '')
        .replaceAll('>', '')
        .replaceAll('"', '')
        .replaceAll("'", '');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FFI BOUNDS CHECKER
// ═══════════════════════════════════════════════════════════════════════════

/// Validates FFI function parameters before calling Rust
class FFIBoundsChecker {
  /// Max tracks (Rust engine limit)
  static const int maxTracks = 1024;

  /// Max insert slots per track
  static const int maxInsertSlots = 8;

  /// Max buses
  static const int maxBuses = 64;

  /// Validate track ID
  static bool validateTrackId(int trackId) {
    return trackId >= 0 && trackId < maxTracks;
  }

  /// Validate bus ID
  static bool validateBusId(int busId) {
    return busId >= 0 && busId < maxBuses;
  }

  /// Validate insert slot index
  static bool validateSlotIndex(int slotIndex) {
    return slotIndex >= 0 && slotIndex < maxInsertSlots;
  }

  /// Validate volume (linear 0.0-4.0, or 0dB to +12dB)
  static bool validateVolume(double volume) {
    if (volume.isNaN || volume.isInfinite) return false;
    return volume >= 0.0 && volume <= 4.0;
  }

  /// Validate pan (-1.0 = full left, +1.0 = full right)
  static bool validatePan(double pan) {
    if (pan.isNaN || pan.isInfinite) return false;
    return pan >= -1.0 && pan <= 1.0;
  }

  /// Validate gain (dB, typically -60 to +20)
  static bool validateGainDb(double gainDb) {
    if (gainDb.isNaN || gainDb.isInfinite) return false;
    return gainDb >= -60.0 && gainDb <= 20.0;
  }

  /// Validate frequency (Hz, 20-20000)
  static bool validateFrequency(double freq) {
    if (freq.isNaN || freq.isInfinite) return false;
    return freq >= 20.0 && freq <= 20000.0;
  }

  /// Validate Q factor (0.1-100)
  static bool validateQ(double q) {
    if (q.isNaN || q.isInfinite) return false;
    return q >= 0.1 && q <= 100.0;
  }

  /// Validate time (ms, 0-10000)
  static bool validateTimeMs(double timeMs) {
    if (timeMs.isNaN || timeMs.isInfinite) return false;
    return timeMs >= 0.0 && timeMs <= 10000.0;
  }

  /// Validate ratio (1.0-100.0)
  static bool validateRatio(double ratio) {
    if (ratio.isNaN || ratio.isInfinite) return false;
    return ratio >= 1.0 && ratio <= 100.0;
  }

  /// Validate sample rate (Hz)
  static bool validateSampleRate(int sampleRate) {
    const validRates = [44100, 48000, 88200, 96000, 176400, 192000, 384000];
    return validRates.contains(sampleRate);
  }

  /// Validate buffer size (samples, power of 2)
  static bool validateBufferSize(int bufferSize) {
    if (bufferSize < 16 || bufferSize > 8192) return false;
    // Check if power of 2
    return (bufferSize & (bufferSize - 1)) == 0;
  }

  /// Get error message for invalid parameter
  static String getErrorMessage(String paramName, dynamic value) {
    return 'Invalid $paramName: $value (out of bounds or NaN/Infinite)';
  }

  /// Clamp volume to safe range
  static double clampVolume(double volume) {
    if (volume.isNaN || volume.isInfinite) return 0.0;
    return volume.clamp(0.0, 4.0);
  }

  /// Clamp pan to safe range
  static double clampPan(double pan) {
    if (pan.isNaN || pan.isInfinite) return 0.0;
    return pan.clamp(-1.0, 1.0);
  }

  /// Clamp gain to safe range
  static double clampGainDb(double gainDb) {
    if (gainDb.isNaN || gainDb.isInfinite) return 0.0;
    return gainDb.clamp(-60.0, 20.0);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SAFE FFI EXTENSIONS (Optional Wrappers)
// ═══════════════════════════════════════════════════════════════════════════

/// Extension methods for safe FFI calls with bounds checking
///
/// Usage:
/// ```dart
/// // Instead of:
/// NativeFFI.instance.setTrackVolume(trackId, volume);
///
/// // Use:
/// NativeFFI.instance.setTrackVolumeSafe(trackId, volume);
/// ```
extension SafeFFI on Object {
  // Note: This is a placeholder pattern for future safe wrappers.
  // Actual implementation would require extending NativeFFI class directly.
  // For now, use FFIBoundsChecker.validateXxx() before FFI calls.
}

// ═══════════════════════════════════════════════════════════════════════════
// VALIDATION RESULT
// ═══════════════════════════════════════════════════════════════════════════

/// Result of validation operation
class ValidationResult {
  final bool isValid;
  final String? errorMessage;
  final dynamic sanitizedValue;

  const ValidationResult({
    required this.isValid,
    this.errorMessage,
    this.sanitizedValue,
  });

  /// Success result
  factory ValidationResult.success({dynamic value}) {
    return ValidationResult(
      isValid: true,
      sanitizedValue: value,
    );
  }

  /// Failure result
  factory ValidationResult.failure(String error) {
    return ValidationResult(
      isValid: false,
      errorMessage: error,
    );
  }

  /// Throw if invalid
  void throwIfInvalid() {
    if (!isValid && errorMessage != null) {
      throw ArgumentError(errorMessage);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// USAGE EXAMPLES (for documentation)
// ═══════════════════════════════════════════════════════════════════════════

/// Example 1: Validate file path before import
/// ```dart
/// final error = PathValidator.validate(
///   filePath,
///   projectRoot: '/path/to/project',
///   checkExists: true,
/// );
/// if (error != null) {
///   showErrorDialog(error);
///   return;
/// }
/// // Safe to import
/// AudioAssetManager.instance.importFiles([filePath]);
/// ```
///
/// Example 2: Validate track name before creation
/// ```dart
/// final error = InputSanitizer.validateName(trackName);
/// if (error != null) {
///   showErrorDialog(error);
///   return;
/// }
/// // Safe to create
/// mixerProvider.createChannel(name: trackName);
/// ```
///
/// Example 3: Validate FFI parameters before call
/// ```dart
/// if (!FFIBoundsChecker.validateTrackId(trackId)) {
///   debugPrint('Invalid track ID: $trackId');
///   return;
/// }
/// if (!FFIBoundsChecker.validateVolume(volume)) {
///   debugPrint('Invalid volume: $volume');
///   return;
/// }
/// // Safe to call FFI
/// NativeFFI.instance.setTrackVolume(trackId, volume);
/// ```
///
/// Example 4: Sanitize user input
/// ```dart
/// // User types: "My<Track>Name!@#$"
/// final sanitized = InputSanitizer.sanitizeName(userInput);
/// // Result: "MyTrackName"
/// mixerProvider.createChannel(name: sanitized);
/// ```
