/// FluxForge Path Validator — Ultimate Security Layer
///
/// Multi-layer defense against path traversal attacks:
/// 1. Canonicalization — Resolve all symlinks, `..`, `.` components
/// 2. Sandbox validation — Ensure path is within allowed directories
/// 3. Extension whitelist — Only allow approved audio formats
/// 4. Character blacklist — Block dangerous characters
/// 5. Length limits — Prevent buffer overflow attacks
///
/// Zero tolerance for security vulnerabilities.

import 'dart:io';
import 'package:path/path.dart' as p;

/// Result of path validation with detailed error information
class PathValidationResult {
  final bool isValid;
  final String? error;
  final String? sanitizedPath;

  const PathValidationResult({
    required this.isValid,
    this.error,
    this.sanitizedPath,
  });

  factory PathValidationResult.valid(String sanitizedPath) {
    return PathValidationResult(
      isValid: true,
      sanitizedPath: sanitizedPath,
    );
  }

  factory PathValidationResult.invalid(String error) {
    return PathValidationResult(
      isValid: false,
      error: error,
    );
  }
}

/// Ultimate path validator with military-grade security
class PathValidator {
  // =============================================================================
  // CONFIGURATION
  // =============================================================================

  /// Allowed audio file extensions (lowercase, no dot)
  /// This is the SINGLE SOURCE OF TRUTH for all audio format support.
  /// Other files should reference PathValidator.allowedExtensions.
  static const Set<String> _allowedExtensions = {
    // ── Uncompressed / PCM ──
    'wav', 'wave',           // Microsoft WAV / RIFF
    'aiff', 'aif', 'aifc',  // Apple AIFF / AIFF-C
    'au', 'snd',             // Sun/NeXT AU
    'raw', 'pcm',            // Raw PCM (headerless)
    'caf',                   // Apple Core Audio Format
    'w64',                   // Sony Wave64
    'rf64',                  // EBU RF64 (>4GB WAV)
    'bwf',                   // Broadcast Wave Format
    'sd2',                   // Sound Designer II
    'voc',                   // Creative Voice
    'avr',                   // Audio Visual Research
    'pvf',                   // Portable Voice Format
    'ircam', 'sf',           // IRCAM/BICSF
    'htk',                   // Hidden Markov Model Toolkit
    'sph', 'nist',           // NIST/SPHERE
    'svx', '8svx',           // Amiga IFF/8SVX
    'paf',                   // Ensoniq PARIS
    'fap',                   // FAAD raw AAC

    // ── Lossless Compressed ──
    'flac',                  // Free Lossless Audio Codec
    'alac',                  // Apple Lossless (also in .m4a)
    'ape',                   // Monkey's Audio
    'wv',                    // WavPack
    'tta',                   // True Audio
    'tak',                   // Tom's lossless Audio Kompressor
    'ofr', 'ofs',            // OptimFROG
    'wma',                   // Windows Media Audio (lossless variant)
    'shn',                   // Shorten
    'la',                    // Lossless Audio
    'mlp',                   // Meridian Lossless Packing

    // ── Lossy Compressed ──
    'mp3',                   // MPEG-1/2 Audio Layer III
    'ogg', 'oga',            // Ogg Vorbis
    'opus',                  // Opus (in Ogg container)
    'm4a', 'aac',            // AAC / MPEG-4 Audio
    'mp4',                   // MPEG-4 (audio-only)
    'mp2',                   // MPEG-1 Audio Layer II
    'mp1',                   // MPEG-1 Audio Layer I
    'mpc', 'mp+', 'mpp',    // Musepack
    'spx',                   // Speex
    'ac3',                   // Dolby Digital AC-3
    'eac3', 'ec3',           // Enhanced AC-3 (Dolby Digital Plus)
    'dts',                   // DTS Coherent Acoustics
    'ra', 'ram',             // RealAudio
    'amr',                   // Adaptive Multi-Rate (mobile voice)
    'awb',                   // AMR-WB (wideband)
    'gsm',                   // GSM 06.10
    'adts',                  // Audio Data Transport Stream (raw AAC)

    // ── DSD (Direct Stream Digital) ──
    'dsf',                   // DSD Stream File
    'dff',                   // DSDIFF
    'dsd',                   // Generic DSD

    // ── Module / Tracker ──
    'mid', 'midi',           // Standard MIDI
    'mod',                   // Amiga ProTracker
    'xm',                    // FastTracker 2
    'it',                    // Impulse Tracker
    's3m',                   // Scream Tracker 3
    'stm',                   // Scream Tracker 2

    // ── Web / Streaming ──
    'webm',                  // WebM (Vorbis/Opus)
    'weba',                  // WebM Audio
    'mka',                   // Matroska Audio

    // ── Game Audio ──
    'wem',                   // Wwise Encoded Media
    'bnk',                   // Wwise SoundBank
    'fsb',                   // FMOD Sound Bank
    'xwm', 'xwma',          // Xbox WMA
    'brstm',                 // BRSTM (Nintendo)
    'bcstm',                 // BCSTM (Nintendo 3DS)
    'bfstm',                 // BFSTM (Nintendo Wii U/Switch)
    'adx',                   // CRI ADX
    'hca',                   // CRI HCA
    'at3', 'at9',            // Sony ATRAC3/ATRAC9
    'vag',                   // PlayStation VAG
    'xma', 'xma2',          // Xbox XMA/XMA2
  };

  /// Maximum path length (prevent buffer overflows)
  static const int _maxPathLength = 4096;

  /// Maximum filename length
  static const int _maxFilenameLength = 255;

  /// Dangerous characters that are NEVER allowed in paths
  static const Set<int> _dangerousCharacters = {
    0x00, // NULL
    0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, // Control chars
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
    0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
    0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
    0x7F, // DEL
  };

  /// Sandbox roots — paths MUST be within one of these directories
  static final List<String> _sandboxRoots = [];

  // =============================================================================
  // SANDBOX CONFIGURATION
  // =============================================================================

  /// Initialize sandbox with allowed directories
  /// MUST be called at app startup before any file operations
  static void initializeSandbox({
    required String projectRoot,
    List<String>? additionalRoots,
  }) {
    _sandboxRoots.clear();

    // Canonicalize project root (resolve all symlinks)
    try {
      final canonicalProjectRoot = Directory(projectRoot).resolveSymbolicLinksSync();
      _sandboxRoots.add(canonicalProjectRoot);
    } catch (e) {
      throw StateError('Failed to canonicalize project root: $e');
    }

    // Add additional roots if provided
    if (additionalRoots != null) {
      for (final root in additionalRoots) {
        try {
          final canonicalRoot = Directory(root).resolveSymbolicLinksSync();
          _sandboxRoots.add(canonicalRoot);
        } catch (e) {
          // Log warning but continue
          print('[PathValidator] Warning: Failed to canonicalize root "$root": $e');
        }
      }
    }

    print('[PathValidator] Sandbox initialized with ${_sandboxRoots.length} root(s):');
    for (final root in _sandboxRoots) {
      print('[PathValidator]   - $root');
    }
  }

  /// Check if sandbox is initialized
  static bool get isInitialized => _sandboxRoots.isNotEmpty;

  // =============================================================================
  // VALIDATION METHODS
  // =============================================================================

  /// Ultimate validation — all security checks in one call
  static PathValidationResult validate(String path) {
    // 1. Sandbox check
    if (!isInitialized) {
      return PathValidationResult.invalid(
        'Sandbox not initialized. Call PathValidator.initializeSandbox() first.',
      );
    }

    // 2. Null/empty check
    if (path.isEmpty) {
      return PathValidationResult.invalid('Path is empty');
    }

    // 3. Length checks
    if (path.length > _maxPathLength) {
      return PathValidationResult.invalid(
        'Path exceeds maximum length ($_maxPathLength characters)',
      );
    }

    final filename = p.basename(path);
    if (filename.length > _maxFilenameLength) {
      return PathValidationResult.invalid(
        'Filename exceeds maximum length ($_maxFilenameLength characters)',
      );
    }

    // 4. Dangerous character check
    for (int i = 0; i < path.length; i++) {
      final charCode = path.codeUnitAt(i);
      if (_dangerousCharacters.contains(charCode)) {
        return PathValidationResult.invalid(
          'Path contains dangerous character (code: $charCode)',
        );
      }
    }

    // 5. Extension whitelist check
    final ext = p.extension(path).toLowerCase();
    final extWithoutDot = ext.isNotEmpty ? ext.substring(1) : '';

    if (!_allowedExtensions.contains(extWithoutDot)) {
      return PathValidationResult.invalid(
        'File extension "$ext" is not allowed. Allowed: ${_allowedExtensions.join(", ")}',
      );
    }

    // 6. Canonicalization — resolve ALL symlinks and .. components
    String canonicalPath;
    try {
      // First check if file exists
      final file = File(path);
      if (!file.existsSync()) {
        return PathValidationResult.invalid('File does not exist: $path');
      }

      // Resolve to canonical path (follows all symlinks)
      canonicalPath = file.resolveSymbolicLinksSync();
    } catch (e) {
      return PathValidationResult.invalid('Failed to canonicalize path: $e');
    }

    // 7. Sandbox containment check — CRITICAL SECURITY CHECK
    bool isWithinSandbox = false;
    for (final root in _sandboxRoots) {
      // Use path package for robust path comparison
      final relativePath = p.relative(canonicalPath, from: root);

      // If relative path doesn't start with "..", it's within the sandbox
      if (!relativePath.startsWith('..')) {
        isWithinSandbox = true;
        break;
      }
    }

    if (!isWithinSandbox) {
      return PathValidationResult.invalid(
        'Path is outside sandbox. Canonical path: $canonicalPath',
      );
    }

    // 8. Additional sanity checks
    if (canonicalPath.contains('\\..\\') ||
        canonicalPath.contains('/../') ||
        canonicalPath.endsWith('/..') ||
        canonicalPath.endsWith('\\..')) {
      return PathValidationResult.invalid(
        'Path contains unresolved parent directory reference after canonicalization',
      );
    }

    // ALL CHECKS PASSED
    return PathValidationResult.valid(canonicalPath);
  }

  /// Quick validation for trusted paths (e.g., from file picker)
  /// Still validates extension and length, but skips sandbox check
  static PathValidationResult validateTrusted(String path) {
    // Length checks
    if (path.isEmpty) {
      return PathValidationResult.invalid('Path is empty');
    }

    if (path.length > _maxPathLength) {
      return PathValidationResult.invalid(
        'Path exceeds maximum length ($_maxPathLength characters)',
      );
    }

    // Extension check
    final ext = p.extension(path).toLowerCase();
    final extWithoutDot = ext.isNotEmpty ? ext.substring(1) : '';

    if (!_allowedExtensions.contains(extWithoutDot)) {
      return PathValidationResult.invalid(
        'File extension "$ext" is not allowed',
      );
    }

    // Canonicalize for consistency
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return PathValidationResult.invalid('File does not exist');
      }

      final canonicalPath = file.resolveSymbolicLinksSync();
      return PathValidationResult.valid(canonicalPath);
    } catch (e) {
      return PathValidationResult.invalid('Failed to canonicalize path: $e');
    }
  }

  /// Validate batch of paths (e.g., multi-select import)
  static Map<String, PathValidationResult> validateBatch(List<String> paths) {
    final results = <String, PathValidationResult>{};

    for (final path in paths) {
      results[path] = validate(path);
    }

    return results;
  }

  // =============================================================================
  // UTILITY METHODS
  // =============================================================================

  /// Check if path is within sandbox WITHOUT full validation
  /// Useful for UI hints before actual validation
  static bool isWithinSandbox(String path) {
    if (!isInitialized) return false;

    try {
      final canonicalPath = File(path).resolveSymbolicLinksSync();

      for (final root in _sandboxRoots) {
        final relativePath = p.relative(canonicalPath, from: root);
        if (!relativePath.startsWith('..')) {
          return true;
        }
      }
    } catch (_) {
      return false;
    }

    return false;
  }

  /// Get sanitized filename (removes dangerous characters)
  static String sanitizeFilename(String filename) {
    // Remove path separators
    var sanitized = filename.replaceAll(RegExp(r'[/\\]'), '_');

    // Remove control characters
    sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

    // Remove other dangerous characters
    sanitized = sanitized.replaceAll(RegExp(r'[<>:"|?*]'), '_');

    // Trim whitespace
    sanitized = sanitized.trim();

    // Ensure not empty
    if (sanitized.isEmpty) {
      sanitized = 'unnamed';
    }

    return sanitized;
  }

  /// Get list of allowed extensions for display
  static List<String> get allowedExtensions => _allowedExtensions.toList();

  /// Get list of sandbox roots (for debugging)
  static List<String> get sandboxRoots => List.unmodifiable(_sandboxRoots);
}
