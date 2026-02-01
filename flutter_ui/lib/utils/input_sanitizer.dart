/// FluxForge Input Sanitizer — Defense Against Injection Attacks
///
/// Ultimate sanitization for all user inputs:
/// - Event names
/// - Project names
/// - File paths
/// - JSON payloads
/// - SQL-like queries (future)
///
/// Prevents:
/// - XSS attacks (HTML/JS injection)
/// - Path traversal
/// - Command injection
/// - Buffer overflows

import 'dart:convert';

/// Result of sanitization with detailed information
class SanitizationResult {
  final String sanitized;
  final bool wasModified;
  final List<String> removedPatterns;

  const SanitizationResult({
    required this.sanitized,
    required this.wasModified,
    required this.removedPatterns,
  });
}

/// Ultimate input sanitizer with zero-tolerance for malicious input
class InputSanitizer {
  // =============================================================================
  // CONFIGURATION
  // =============================================================================

  /// Maximum string length (prevent memory exhaustion)
  static const int _maxStringLength = 1024;

  /// Maximum event name length (UX-friendly)
  static const int _maxEventNameLength = 128;

  /// Maximum project name length
  static const int _maxProjectNameLength = 64;

  /// Dangerous HTML/JS patterns (case-insensitive)
  static final List<RegExp> _htmlJsPatterns = [
    RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false),
    RegExp(r'<iframe[^>]*>.*?</iframe>', caseSensitive: false),
    RegExp(r'<object[^>]*>.*?</object>', caseSensitive: false),
    RegExp(r'<embed[^>]*>', caseSensitive: false),
    RegExp(r'<link[^>]*>', caseSensitive: false),
    RegExp(r'javascript:', caseSensitive: false),
    RegExp(r'on\w+\s*=', caseSensitive: false), // onclick=, onerror=, etc.
    RegExp(r'<\?php', caseSensitive: false),
    RegExp(r'<%', caseSensitive: false), // ASP/JSP
    RegExp(r'\${', caseSensitive: false), // Template injection
  ];

  /// HTML entity patterns
  static final RegExp _htmlEntityPattern = RegExp(r'&[a-zA-Z0-9#]+;');

  /// Path traversal patterns
  static final List<RegExp> _pathTraversalPatterns = [
    RegExp(r'\.\.[\\/]'), // ../
    RegExp(r'[\\/]\.\.'), // /..
    RegExp(r'\.\.'), // .. (any occurrence)
    RegExp(r'~[\\/]'), // ~/
    RegExp(r'%2e%2e', caseSensitive: false), // URL-encoded ..
    RegExp(r'%252e', caseSensitive: false), // Double URL-encoded .
  ];

  /// Control characters (0x00-0x1F, 0x7F)
  static final RegExp _controlCharPattern = RegExp(r'[\x00-\x1F\x7F]');

  // =============================================================================
  // EVENT NAME SANITIZATION
  // =============================================================================

  /// Sanitize event name (used in EventRegistry, MiddlewareProvider, etc.)
  ///
  /// Rules:
  /// - Max 128 characters
  /// - No HTML/JS
  /// - No control characters
  /// - No path traversal patterns
  /// - Allow: A-Z, a-z, 0-9, space, -, _, (), []
  static SanitizationResult sanitizeEventName(String input) {
    if (input.isEmpty) {
      return SanitizationResult(
        sanitized: 'Unnamed Event',
        wasModified: true,
        removedPatterns: ['empty input'],
      );
    }

    final removedPatterns = <String>[];
    var sanitized = input;

    // 1. Length limit
    if (sanitized.length > _maxEventNameLength) {
      sanitized = sanitized.substring(0, _maxEventNameLength);
      removedPatterns.add('truncated to $_maxEventNameLength chars');
    }

    // 2. Remove HTML/JS
    for (final pattern in _htmlJsPatterns) {
      if (pattern.hasMatch(sanitized)) {
        sanitized = sanitized.replaceAll(pattern, '');
        removedPatterns.add('HTML/JS pattern: ${pattern.pattern}');
      }
    }

    // 3. Remove HTML entities
    if (_htmlEntityPattern.hasMatch(sanitized)) {
      sanitized = sanitized.replaceAll(_htmlEntityPattern, '');
      removedPatterns.add('HTML entities');
    }

    // 4. Remove path traversal
    for (final pattern in _pathTraversalPatterns) {
      if (pattern.hasMatch(sanitized)) {
        sanitized = sanitized.replaceAll(pattern, '');
        removedPatterns.add('Path traversal: ${pattern.pattern}');
      }
    }

    // 5. Remove control characters
    if (_controlCharPattern.hasMatch(sanitized)) {
      sanitized = sanitized.replaceAll(_controlCharPattern, '');
      removedPatterns.add('Control characters');
    }

    // 6. Whitelist: Allow only safe characters
    // A-Z, a-z, 0-9, space, -, _, (), []
    final whitelistPattern = RegExp(r'[^A-Za-z0-9\s\-_\(\)\[\]]');
    if (whitelistPattern.hasMatch(sanitized)) {
      sanitized = sanitized.replaceAll(whitelistPattern, '_');
      removedPatterns.add('Non-whitelisted characters');
    }

    // 7. Collapse multiple spaces
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ');

    // 8. Trim
    sanitized = sanitized.trim();

    // 9. Ensure not empty after sanitization
    if (sanitized.isEmpty) {
      sanitized = 'Unnamed Event';
      removedPatterns.add('empty after sanitization');
    }

    return SanitizationResult(
      sanitized: sanitized,
      wasModified: sanitized != input,
      removedPatterns: removedPatterns,
    );
  }

  // =============================================================================
  // PROJECT NAME SANITIZATION
  // =============================================================================

  /// Sanitize project name (stricter than event names)
  ///
  /// Rules:
  /// - Max 64 characters
  /// - A-Z, a-z, 0-9, -, _ only (no spaces, no special chars)
  /// - Must start with letter or number
  static SanitizationResult sanitizeProjectName(String input) {
    if (input.isEmpty) {
      return SanitizationResult(
        sanitized: 'Untitled_Project',
        wasModified: true,
        removedPatterns: ['empty input'],
      );
    }

    final removedPatterns = <String>[];
    var sanitized = input;

    // 1. Length limit
    if (sanitized.length > _maxProjectNameLength) {
      sanitized = sanitized.substring(0, _maxProjectNameLength);
      removedPatterns.add('truncated to $_maxProjectNameLength chars');
    }

    // 2. Convert spaces to underscores
    if (sanitized.contains(' ')) {
      sanitized = sanitized.replaceAll(' ', '_');
      removedPatterns.add('spaces converted to underscores');
    }

    // 3. Whitelist: A-Z, a-z, 0-9, -, _ only
    final whitelistPattern = RegExp(r'[^A-Za-z0-9\-_]');
    if (whitelistPattern.hasMatch(sanitized)) {
      sanitized = sanitized.replaceAll(whitelistPattern, '_');
      removedPatterns.add('Non-whitelisted characters');
    }

    // 4. Ensure starts with letter or number
    if (sanitized.isNotEmpty && !RegExp(r'^[A-Za-z0-9]').hasMatch(sanitized)) {
      sanitized = 'P_$sanitized';
      removedPatterns.add('prepended prefix (must start with alphanumeric)');
    }

    // 5. Collapse multiple underscores
    sanitized = sanitized.replaceAll(RegExp(r'_+'), '_');

    // 6. Trim underscores/hyphens from ends
    sanitized = sanitized.replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');

    // 7. Ensure not empty
    if (sanitized.isEmpty) {
      sanitized = 'Untitled_Project';
      removedPatterns.add('empty after sanitization');
    }

    return SanitizationResult(
      sanitized: sanitized,
      wasModified: sanitized != input,
      removedPatterns: removedPatterns,
    );
  }

  // =============================================================================
  // GENERAL STRING SANITIZATION
  // =============================================================================

  /// Sanitize generic user input (descriptions, notes, etc.)
  ///
  /// Rules:
  /// - Max 1024 characters
  /// - Remove HTML/JS
  /// - Remove control characters
  /// - Allow most printable characters
  static SanitizationResult sanitizeString(String input, {int? maxLength}) {
    final limit = maxLength ?? _maxStringLength;
    final removedPatterns = <String>[];
    var sanitized = input;

    // 1. Length limit
    if (sanitized.length > limit) {
      sanitized = sanitized.substring(0, limit);
      removedPatterns.add('truncated to $limit chars');
    }

    // 2. Remove HTML/JS
    for (final pattern in _htmlJsPatterns) {
      if (pattern.hasMatch(sanitized)) {
        sanitized = sanitized.replaceAll(pattern, '');
        removedPatterns.add('HTML/JS pattern: ${pattern.pattern}');
      }
    }

    // 3. Remove HTML entities
    if (_htmlEntityPattern.hasMatch(sanitized)) {
      sanitized = sanitized.replaceAll(_htmlEntityPattern, '');
      removedPatterns.add('HTML entities');
    }

    // 4. Remove path traversal
    for (final pattern in _pathTraversalPatterns) {
      if (pattern.hasMatch(sanitized)) {
        sanitized = sanitized.replaceAll(pattern, '');
        removedPatterns.add('Path traversal: ${pattern.pattern}');
      }
    }

    // 5. Remove control characters (except newlines and tabs for multiline text)
    final controlCharsExceptNewlines = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');
    if (controlCharsExceptNewlines.hasMatch(sanitized)) {
      sanitized = sanitized.replaceAll(controlCharsExceptNewlines, '');
      removedPatterns.add('Control characters');
    }

    // 6. Trim
    sanitized = sanitized.trim();

    return SanitizationResult(
      sanitized: sanitized,
      wasModified: sanitized != input,
      removedPatterns: removedPatterns,
    );
  }

  // =============================================================================
  // JSON SANITIZATION
  // =============================================================================

  /// Sanitize JSON string before parsing
  /// Prevents injection attacks via malformed JSON
  static String sanitizeJson(String jsonString) {
    // Basic validation: try parsing, if fails return empty object
    try {
      json.decode(jsonString);
      return jsonString;
    } catch (e) {
      return '{}';
    }
  }

  // =============================================================================
  // BATCH OPERATIONS
  // =============================================================================

  /// Sanitize batch of event names (e.g., multi-select operations)
  static Map<String, SanitizationResult> sanitizeEventNamesBatch(
    List<String> inputs,
  ) {
    final results = <String, SanitizationResult>{};

    for (final input in inputs) {
      results[input] = sanitizeEventName(input);
    }

    return results;
  }

  // =============================================================================
  // UTILITY METHODS
  // =============================================================================

  /// Check if string contains dangerous patterns WITHOUT sanitizing
  /// Useful for validation before save
  static bool hasDangerousPatterns(String input) {
    // Check HTML/JS
    for (final pattern in _htmlJsPatterns) {
      if (pattern.hasMatch(input)) return true;
    }

    // Check path traversal
    for (final pattern in _pathTraversalPatterns) {
      if (pattern.hasMatch(input)) return true;
    }

    // Check control characters
    if (_controlCharPattern.hasMatch(input)) return true;

    return false;
  }

  /// Escape string for safe display in UI (prevents rendering issues)
  static String escapeForDisplay(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }
}
