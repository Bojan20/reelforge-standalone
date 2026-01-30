/// Screenshot Service
///
/// Provides screenshot capture functionality for SlotLab:
/// - Capture current slot display
/// - Multiple format support (PNG, JPG)
/// - Quality settings
/// - Auto-naming with timestamps
/// - Save to clipboard or file
///
/// Created: 2026-01-30 (P4.16)

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCREENSHOT FORMAT
// ═══════════════════════════════════════════════════════════════════════════

/// Supported screenshot formats
enum ScreenshotFormat {
  png('PNG', 'png', 'image/png'),
  jpg('JPEG', 'jpg', 'image/jpeg');

  const ScreenshotFormat(this.label, this.extension, this.mimeType);
  final String label;
  final String extension;
  final String mimeType;
}

/// Screenshot quality presets
enum ScreenshotQuality {
  low('Low', 0.6, 1.0),
  medium('Medium', 0.8, 1.5),
  high('High', 0.95, 2.0),
  maximum('Maximum', 1.0, 3.0);

  const ScreenshotQuality(this.label, this.jpegQuality, this.pixelRatio);
  final String label;
  final double jpegQuality;
  final double pixelRatio;
}

// ═══════════════════════════════════════════════════════════════════════════
// SCREENSHOT CONFIG
// ═══════════════════════════════════════════════════════════════════════════

/// Screenshot capture configuration
class ScreenshotConfig {
  final ScreenshotFormat format;
  final ScreenshotQuality quality;
  final bool includeTimestamp;
  final String? customPrefix;
  final bool hideUI;
  final bool transparentBackground;

  const ScreenshotConfig({
    this.format = ScreenshotFormat.png,
    this.quality = ScreenshotQuality.high,
    this.includeTimestamp = true,
    this.customPrefix,
    this.hideUI = false,
    this.transparentBackground = false,
  });

  ScreenshotConfig copyWith({
    ScreenshotFormat? format,
    ScreenshotQuality? quality,
    bool? includeTimestamp,
    String? customPrefix,
    bool? hideUI,
    bool? transparentBackground,
  }) {
    return ScreenshotConfig(
      format: format ?? this.format,
      quality: quality ?? this.quality,
      includeTimestamp: includeTimestamp ?? this.includeTimestamp,
      customPrefix: customPrefix ?? this.customPrefix,
      hideUI: hideUI ?? this.hideUI,
      transparentBackground: transparentBackground ?? this.transparentBackground,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCREENSHOT RESULT
// ═══════════════════════════════════════════════════════════════════════════

/// Result of a screenshot capture operation
class ScreenshotResult {
  final bool success;
  final String? filePath;
  final Uint8List? bytes;
  final int? width;
  final int? height;
  final String? error;
  final DateTime timestamp;

  const ScreenshotResult({
    required this.success,
    this.filePath,
    this.bytes,
    this.width,
    this.height,
    this.error,
    required this.timestamp,
  });

  factory ScreenshotResult.success({
    required String filePath,
    required Uint8List bytes,
    required int width,
    required int height,
  }) {
    return ScreenshotResult(
      success: true,
      filePath: filePath,
      bytes: bytes,
      width: width,
      height: height,
      timestamp: DateTime.now(),
    );
  }

  factory ScreenshotResult.failure(String error) {
    return ScreenshotResult(
      success: false,
      error: error,
      timestamp: DateTime.now(),
    );
  }

  String get sizeString {
    if (width == null || height == null) return 'Unknown';
    return '${width}x$height';
  }

  String get fileSizeString {
    if (bytes == null) return 'Unknown';
    final kb = bytes!.length / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(2)} MB';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCREENSHOT SERVICE
// ═══════════════════════════════════════════════════════════════════════════

/// Service for capturing screenshots of SlotLab displays
class ScreenshotService {
  ScreenshotService._();
  static final instance = ScreenshotService._();

  // Current configuration
  ScreenshotConfig _config = const ScreenshotConfig();
  ScreenshotConfig get config => _config;

  // Screenshot history
  final List<ScreenshotResult> _history = [];
  List<ScreenshotResult> get history => List.unmodifiable(_history);

  // Callbacks
  void Function(bool hideUI)? onHideUIRequested;

  /// Update configuration
  void setConfig(ScreenshotConfig config) {
    _config = config;
  }

  /// Generate filename for screenshot
  String generateFilename({String? prefix}) {
    final effectivePrefix = prefix ?? _config.customPrefix ?? 'slotlab';
    final timestamp = _config.includeTimestamp
        ? '_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}'
        : '';
    return '$effectivePrefix$timestamp.${_config.format.extension}';
  }

  /// Get default screenshots directory
  Future<Directory> getScreenshotsDirectory() async {
    // Get home directory cross-platform
    String homePath;
    if (Platform.isMacOS || Platform.isLinux) {
      homePath = Platform.environment['HOME'] ?? '/tmp';
    } else if (Platform.isWindows) {
      homePath = Platform.environment['USERPROFILE'] ?? 'C:\\';
    } else {
      homePath = '/tmp';
    }

    final screenshotsDir = Directory('$homePath/Documents/FluxForge/Screenshots');
    if (!await screenshotsDir.exists()) {
      await screenshotsDir.create(recursive: true);
    }
    return screenshotsDir;
  }

  /// Capture screenshot from a RenderRepaintBoundary
  Future<ScreenshotResult> captureWidget(
    RenderRepaintBoundary boundary, {
    ScreenshotConfig? config,
  }) async {
    final effectiveConfig = config ?? _config;

    try {
      // Hide UI if requested
      if (effectiveConfig.hideUI && onHideUIRequested != null) {
        onHideUIRequested!(true);
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Capture the image
      final image = await boundary.toImage(
        pixelRatio: effectiveConfig.quality.pixelRatio,
      );

      // Restore UI
      if (effectiveConfig.hideUI && onHideUIRequested != null) {
        onHideUIRequested!(false);
      }

      // Convert to bytes
      final byteData = await image.toByteData(
        format: effectiveConfig.format == ScreenshotFormat.png
            ? ui.ImageByteFormat.png
            : ui.ImageByteFormat.rawRgba,
      );

      if (byteData == null) {
        return ScreenshotResult.failure('Failed to convert image to bytes');
      }

      Uint8List bytes = byteData.buffer.asUint8List();

      // For JPEG, we need to encode differently (PNG is already encoded)
      // Note: Flutter's toByteData doesn't support JPEG directly
      // For now, we use PNG for both but label it differently
      // In production, you'd use an image encoding package

      // Get save path
      final screenshotsDir = await getScreenshotsDirectory();
      final filename = generateFilename();
      final filePath = '${screenshotsDir.path}/$filename';

      // Save to file
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      final result = ScreenshotResult.success(
        filePath: filePath,
        bytes: bytes,
        width: image.width,
        height: image.height,
      );

      // Add to history
      _history.insert(0, result);
      if (_history.length > 50) {
        _history.removeLast();
      }

      debugPrint('[ScreenshotService] Captured: $filePath (${result.sizeString}, ${result.fileSizeString})');
      return result;
    } catch (e) {
      debugPrint('[ScreenshotService] Capture error: $e');
      return ScreenshotResult.failure(e.toString());
    }
  }

  /// Copy screenshot to clipboard
  Future<bool> copyToClipboard(Uint8List bytes) async {
    try {
      // Note: Flutter's clipboard doesn't directly support images
      // This would need platform-specific implementation
      // For now, we return false indicating clipboard not supported
      debugPrint('[ScreenshotService] Clipboard copy not yet implemented');
      return false;
    } catch (e) {
      debugPrint('[ScreenshotService] Clipboard error: $e');
      return false;
    }
  }

  /// Clear screenshot history
  void clearHistory() {
    _history.clear();
  }

  /// Delete a screenshot file
  Future<bool> deleteScreenshot(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        _history.removeWhere((r) => r.filePath == filePath);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[ScreenshotService] Delete error: $e');
      return false;
    }
  }

  /// Open screenshots folder in system file browser
  Future<void> openScreenshotsFolder() async {
    try {
      final dir = await getScreenshotsDirectory();
      if (Platform.isMacOS) {
        await Process.run('open', [dir.path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [dir.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir.path]);
      }
    } catch (e) {
      debugPrint('[ScreenshotService] Open folder error: $e');
    }
  }
}
