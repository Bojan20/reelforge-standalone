/// P2-SL-1: Visual Regression Service (2026-02-02)
///
/// Comprehensive visual regression testing for SlotLab slot machine states.
/// Captures screenshots, compares with golden images, and generates diff reports.
///
/// Features:
/// - Screenshot capture of slot machine states
/// - Pixel-perfect comparison with configurable tolerance
/// - Golden image storage and management
/// - Diff visualization (red overlay highlighting differences)
/// - HTML report generation
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

// ═══════════════════════════════════════════════════════════════════════════════
// CONFIGURATION
// ═══════════════════════════════════════════════════════════════════════════════

/// Configuration for visual regression tests
class VisualRegressionConfig {
  /// Directory for golden images
  final String goldenDirectory;

  /// Directory for captured screenshots
  final String captureDirectory;

  /// Directory for diff images
  final String diffDirectory;

  /// Maximum allowed pixel difference percentage (0.0 - 1.0)
  final double maxDiffThreshold;

  /// Device pixel ratio for captures
  final double pixelRatio;

  /// Default capture size
  final Size defaultSize;

  /// Whether to auto-update goldens when missing
  final bool autoUpdateMissingGoldens;

  /// Whether to generate HTML reports
  final bool generateHtmlReport;

  const VisualRegressionConfig({
    this.goldenDirectory = 'test/visual_regression/goldens/slotlab',
    this.captureDirectory = 'test/visual_regression/captures',
    this.diffDirectory = 'test/visual_regression/diffs',
    this.maxDiffThreshold = 0.001, // 0.1% tolerance
    this.pixelRatio = 2.0,
    this.defaultSize = const Size(1280, 720),
    this.autoUpdateMissingGoldens = false,
    this.generateHtmlReport = true,
  });

  /// Strict config for CI
  static const VisualRegressionConfig ci = VisualRegressionConfig(
    maxDiffThreshold: 0.0005, // 0.05%
    autoUpdateMissingGoldens: false,
    generateHtmlReport: true,
  );

  /// Lenient config for local development
  static const VisualRegressionConfig local = VisualRegressionConfig(
    maxDiffThreshold: 0.01, // 1%
    autoUpdateMissingGoldens: true,
    generateHtmlReport: false,
  );

  /// Config for updating golden images
  static const VisualRegressionConfig update = VisualRegressionConfig(
    autoUpdateMissingGoldens: true,
    generateHtmlReport: false,
  );

  VisualRegressionConfig copyWith({
    String? goldenDirectory,
    String? captureDirectory,
    String? diffDirectory,
    double? maxDiffThreshold,
    double? pixelRatio,
    Size? defaultSize,
    bool? autoUpdateMissingGoldens,
    bool? generateHtmlReport,
  }) {
    return VisualRegressionConfig(
      goldenDirectory: goldenDirectory ?? this.goldenDirectory,
      captureDirectory: captureDirectory ?? this.captureDirectory,
      diffDirectory: diffDirectory ?? this.diffDirectory,
      maxDiffThreshold: maxDiffThreshold ?? this.maxDiffThreshold,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      defaultSize: defaultSize ?? this.defaultSize,
      autoUpdateMissingGoldens: autoUpdateMissingGoldens ?? this.autoUpdateMissingGoldens,
      generateHtmlReport: generateHtmlReport ?? this.generateHtmlReport,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SLOT STATE DEFINITIONS
// ═══════════════════════════════════════════════════════════════════════════════

/// Predefined slot machine states for visual regression
enum SlotMachineState {
  /// Idle state - reels stopped, no action
  idle('idle', 'Slot machine idle state'),

  /// Spinning state - reels in motion
  spinning('spinning', 'Reels spinning'),

  /// Reel stopping - sequential reel stop animation
  reelStopping('reel_stopping', 'Reels stopping sequentially'),

  /// Win presentation - small win display
  winSmall('win_small', 'Small win presentation'),

  /// Win presentation - big win with celebration
  winBig('win_big', 'Big win celebration'),

  /// Win presentation - mega win with effects
  winMega('win_mega', 'Mega win with effects'),

  /// Free spins trigger
  freeSpinsTrigger('freespins_trigger', 'Free spins feature triggered'),

  /// Free spins active
  freeSpinsActive('freespins_active', 'Free spins in progress'),

  /// Anticipation state - scatter symbols building tension
  anticipation('anticipation', 'Anticipation animation'),

  /// Cascade/tumble - symbols falling
  cascade('cascade', 'Cascade/tumble animation'),

  /// Hold & Win - coin collection
  holdAndWin('hold_win', 'Hold & Win feature'),

  /// Jackpot trigger
  jackpotTrigger('jackpot_trigger', 'Jackpot triggered'),

  /// Jackpot celebration
  jackpotCelebration('jackpot_celebration', 'Jackpot celebration'),

  /// Gamble feature
  gamble('gamble', 'Gamble feature active'),

  /// Menu open
  menuOpen('menu_open', 'Menu panel open'),

  /// Paytable view
  paytable('paytable', 'Paytable displayed');

  const SlotMachineState(this.id, this.description);
  final String id;
  final String description;

  /// Get golden file name for this state
  String get goldenFileName => '$id.png';

  /// Get golden file name with variant
  String goldenFileNameWithVariant(String variant) => '${id}_$variant.png';
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPARISON RESULTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Result of comparing two images
class ImageComparisonResult {
  /// Name of the test/comparison
  final String testName;

  /// Whether the comparison passed
  final bool passed;

  /// Percentage of pixels that differ (0.0 - 1.0)
  final double diffPercent;

  /// Number of pixels that differ
  final int diffPixelCount;

  /// Total number of pixels
  final int totalPixelCount;

  /// Path to golden image
  final String? goldenPath;

  /// Path to captured image
  final String? capturePath;

  /// Path to diff image (if generated)
  final String? diffPath;

  /// Error message if comparison failed
  final String? errorMessage;

  /// Timestamp of comparison
  final DateTime timestamp;

  /// Max diff color component found
  final int maxColorDiff;

  const ImageComparisonResult({
    required this.testName,
    required this.passed,
    required this.diffPercent,
    required this.diffPixelCount,
    required this.totalPixelCount,
    this.goldenPath,
    this.capturePath,
    this.diffPath,
    this.errorMessage,
    required this.timestamp,
    this.maxColorDiff = 0,
  });

  /// Create a failed result
  factory ImageComparisonResult.failed({
    required String testName,
    required String errorMessage,
  }) {
    return ImageComparisonResult(
      testName: testName,
      passed: false,
      diffPercent: 1.0,
      diffPixelCount: 0,
      totalPixelCount: 0,
      errorMessage: errorMessage,
      timestamp: DateTime.now(),
    );
  }

  /// Create a passed result (no differences)
  factory ImageComparisonResult.identical({
    required String testName,
    required int totalPixels,
    String? goldenPath,
    String? capturePath,
  }) {
    return ImageComparisonResult(
      testName: testName,
      passed: true,
      diffPercent: 0.0,
      diffPixelCount: 0,
      totalPixelCount: totalPixels,
      goldenPath: goldenPath,
      capturePath: capturePath,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'testName': testName,
        'passed': passed,
        'diffPercent': diffPercent,
        'diffPixelCount': diffPixelCount,
        'totalPixelCount': totalPixelCount,
        'goldenPath': goldenPath,
        'capturePath': capturePath,
        'diffPath': diffPath,
        'errorMessage': errorMessage,
        'timestamp': timestamp.toIso8601String(),
        'maxColorDiff': maxColorDiff,
      };

  factory ImageComparisonResult.fromJson(Map<String, dynamic> json) {
    return ImageComparisonResult(
      testName: json['testName'] as String,
      passed: json['passed'] as bool,
      diffPercent: (json['diffPercent'] as num).toDouble(),
      diffPixelCount: json['diffPixelCount'] as int,
      totalPixelCount: json['totalPixelCount'] as int,
      goldenPath: json['goldenPath'] as String?,
      capturePath: json['capturePath'] as String?,
      diffPath: json['diffPath'] as String?,
      errorMessage: json['errorMessage'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      maxColorDiff: json['maxColorDiff'] as int? ?? 0,
    );
  }

  @override
  String toString() {
    if (passed) {
      return 'PASS: $testName (${(diffPercent * 100).toStringAsFixed(4)}% diff)';
    } else {
      return 'FAIL: $testName - ${errorMessage ?? "${(diffPercent * 100).toStringAsFixed(4)}% diff"}';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TEST SESSION
// ═══════════════════════════════════════════════════════════════════════════════

/// A visual regression test session containing multiple comparisons
class VisualRegressionSession {
  final String sessionId;
  final DateTime startTime;
  DateTime? endTime;
  final VisualRegressionConfig config;
  final List<ImageComparisonResult> results = [];

  VisualRegressionSession({
    String? sessionId,
    required this.config,
  })  : sessionId = sessionId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        startTime = DateTime.now();

  void addResult(ImageComparisonResult result) {
    results.add(result);
  }

  void complete() {
    endTime = DateTime.now();
  }

  int get totalTests => results.length;
  int get passedTests => results.where((r) => r.passed).length;
  int get failedTests => results.where((r) => !r.passed).length;
  double get passRate => totalTests > 0 ? passedTests / totalTests : 1.0;
  bool get allPassed => failedTests == 0;

  Duration? get duration => endTime?.difference(startTime);

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'totalTests': totalTests,
        'passedTests': passedTests,
        'failedTests': failedTests,
        'passRate': passRate,
        'results': results.map((r) => r.toJson()).toList(),
      };
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN SERVICE
// ═══════════════════════════════════════════════════════════════════════════════

/// Visual Regression Service - Singleton for SlotLab visual testing
class VisualRegressionService extends ChangeNotifier {
  static final VisualRegressionService instance = VisualRegressionService._();
  VisualRegressionService._();

  // Configuration
  VisualRegressionConfig _config = const VisualRegressionConfig();
  VisualRegressionConfig get config => _config;

  // Current session
  VisualRegressionSession? _currentSession;
  VisualRegressionSession? get currentSession => _currentSession;

  // History
  final List<VisualRegressionSession> _sessionHistory = [];
  List<VisualRegressionSession> get sessionHistory => List.unmodifiable(_sessionHistory);
  static const int _maxHistorySize = 20;

  // State
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  double _progress = 0.0;
  double get progress => _progress;

  String? _currentTest;
  String? get currentTest => _currentTest;

  /// Configure the service
  void configure(VisualRegressionConfig config) {
    _config = config;
    notifyListeners();
  }

  /// Start a new test session
  VisualRegressionSession startSession({String? sessionId}) {
    if (_isRunning) {
      throw StateError('Session already in progress');
    }

    _currentSession = VisualRegressionSession(
      sessionId: sessionId,
      config: _config,
    );
    _isRunning = true;
    _progress = 0.0;
    notifyListeners();

    return _currentSession!;
  }

  /// End the current session
  void endSession() {
    if (_currentSession != null) {
      _currentSession!.complete();
      _sessionHistory.insert(0, _currentSession!);

      if (_sessionHistory.length > _maxHistorySize) {
        _sessionHistory.removeLast();
      }

      _currentSession = null;
    }

    _isRunning = false;
    _progress = 1.0;
    _currentTest = null;
    notifyListeners();
  }

  /// Capture a screenshot from a RenderRepaintBoundary
  Future<Uint8List?> captureScreenshot(
    RenderRepaintBoundary boundary, {
    double? pixelRatio,
  }) async {
    try {
      final ratio = pixelRatio ?? _config.pixelRatio;
      final image = await boundary.toImage(pixelRatio: ratio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  /// Capture screenshot from a GlobalKey
  Future<Uint8List?> captureFromKey(
    GlobalKey key, {
    double? pixelRatio,
  }) async {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      return null;
    }
    return captureScreenshot(boundary, pixelRatio: pixelRatio);
  }

  /// Compare captured image with golden image
  Future<ImageComparisonResult> compareWithGolden({
    required String testName,
    required Uint8List capturedImage,
    String? variant,
  }) async {
    _currentTest = testName;
    notifyListeners();

    final goldenFileName = variant != null ? '${testName}_$variant.png' : '$testName.png';
    final goldenPath = path.join(_config.goldenDirectory, goldenFileName);
    final goldenFile = File(goldenPath);

    // Check if golden exists
    if (!goldenFile.existsSync()) {
      if (_config.autoUpdateMissingGoldens) {
        // Create golden from captured
        await _saveImage(capturedImage, goldenPath);

        final result = ImageComparisonResult.identical(
          testName: testName,
          totalPixels: 0,
          goldenPath: goldenPath,
        );
        _currentSession?.addResult(result);
        return result;
      } else {
        final result = ImageComparisonResult.failed(
          testName: testName,
          errorMessage: 'Golden image not found: $goldenPath',
        );
        _currentSession?.addResult(result);
        return result;
      }
    }

    // Load golden image
    final goldenBytes = await goldenFile.readAsBytes();

    // Compare images
    final result = await _compareImages(
      testName: testName,
      goldenBytes: goldenBytes,
      capturedBytes: capturedImage,
      goldenPath: goldenPath,
    );

    _currentSession?.addResult(result);
    return result;
  }

  /// Compare two image byte arrays
  Future<ImageComparisonResult> _compareImages({
    required String testName,
    required Uint8List goldenBytes,
    required Uint8List capturedBytes,
    required String goldenPath,
  }) async {
    try {
      // Decode images
      final goldenCodec = await ui.instantiateImageCodec(goldenBytes);
      final goldenFrame = await goldenCodec.getNextFrame();
      final goldenImage = goldenFrame.image;

      final capturedCodec = await ui.instantiateImageCodec(capturedBytes);
      final capturedFrame = await capturedCodec.getNextFrame();
      final capturedImage = capturedFrame.image;

      // Check dimensions
      if (goldenImage.width != capturedImage.width ||
          goldenImage.height != capturedImage.height) {
        return ImageComparisonResult.failed(
          testName: testName,
          errorMessage: 'Size mismatch: golden(${goldenImage.width}x${goldenImage.height}) '
              'vs captured(${capturedImage.width}x${capturedImage.height})',
        );
      }

      // Get pixel data
      final goldenData = await goldenImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      final capturedData = await capturedImage.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (goldenData == null || capturedData == null) {
        return ImageComparisonResult.failed(
          testName: testName,
          errorMessage: 'Failed to get pixel data',
        );
      }

      // Compare pixels
      final totalPixels = goldenImage.width * goldenImage.height;
      int diffPixels = 0;
      int maxDiff = 0;

      // Create diff image data
      final diffData = Uint8List(goldenData.lengthInBytes);

      for (int i = 0; i < goldenData.lengthInBytes; i += 4) {
        final gr = goldenData.getUint8(i);
        final gg = goldenData.getUint8(i + 1);
        final gb = goldenData.getUint8(i + 2);
        final ga = goldenData.getUint8(i + 3);

        final cr = capturedData.getUint8(i);
        final cg = capturedData.getUint8(i + 1);
        final cb = capturedData.getUint8(i + 2);
        final ca = capturedData.getUint8(i + 3);

        final dr = (gr - cr).abs();
        final dg = (gg - cg).abs();
        final db = (gb - cb).abs();
        final da = (ga - ca).abs();

        final pixelDiff = dr + dg + db + da;
        maxDiff = pixelDiff > maxDiff ? pixelDiff : maxDiff;

        if (pixelDiff > 0) {
          diffPixels++;
          // Red overlay for diff visualization
          diffData[i] = 255; // R
          diffData[i + 1] = 0; // G
          diffData[i + 2] = 0; // B
          diffData[i + 3] = (pixelDiff * 2).clamp(50, 255); // A based on diff intensity
        } else {
          // Dimmed original for non-diff
          diffData[i] = (cr * 0.3).round();
          diffData[i + 1] = (cg * 0.3).round();
          diffData[i + 2] = (cb * 0.3).round();
          diffData[i + 3] = 255;
        }
      }

      final diffPercent = diffPixels / totalPixels;
      final passed = diffPercent <= _config.maxDiffThreshold;

      // Save capture and diff if failed
      String? capturePath;
      String? diffPath;

      if (!passed || _config.generateHtmlReport) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        capturePath = path.join(_config.captureDirectory, '${testName}_$timestamp.png');
        await _saveImage(capturedBytes, capturePath);

        if (!passed) {
          diffPath = path.join(_config.diffDirectory, '${testName}_${timestamp}_diff.png');
          await _saveDiffImage(
            diffData,
            goldenImage.width,
            goldenImage.height,
            diffPath,
          );
        }
      }

      return ImageComparisonResult(
        testName: testName,
        passed: passed,
        diffPercent: diffPercent,
        diffPixelCount: diffPixels,
        totalPixelCount: totalPixels,
        goldenPath: goldenPath,
        capturePath: capturePath,
        diffPath: diffPath,
        timestamp: DateTime.now(),
        maxColorDiff: maxDiff,
      );
    } catch (e) {
      return ImageComparisonResult.failed(
        testName: testName,
        errorMessage: 'Comparison error: $e',
      );
    }
  }

  /// Save image bytes to file
  Future<void> _saveImage(Uint8List bytes, String filePath) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  /// Save diff image from raw RGBA data
  Future<void> _saveDiffImage(
    Uint8List rgbaData,
    int width,
    int height,
    String filePath,
  ) async {
    try {
      // Create image from raw data
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgbaData,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );

      final image = await completer.future;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        await _saveImage(byteData.buffer.asUint8List(), filePath);
      }
    } catch (e) { /* ignored */ }
  }

  /// Update golden image
  Future<void> updateGolden({
    required String testName,
    required Uint8List image,
    String? variant,
  }) async {
    final goldenFileName = variant != null ? '${testName}_$variant.png' : '$testName.png';
    final goldenPath = path.join(_config.goldenDirectory, goldenFileName);
    await _saveImage(image, goldenPath);
  }

  /// Run visual regression test for a slot machine state
  Future<ImageComparisonResult> testSlotState({
    required SlotMachineState state,
    required GlobalKey captureKey,
    String? variant,
  }) async {
    final image = await captureFromKey(captureKey);

    if (image == null) {
      final result = ImageComparisonResult.failed(
        testName: state.id,
        errorMessage: 'Failed to capture screenshot',
      );
      _currentSession?.addResult(result);
      return result;
    }

    return compareWithGolden(
      testName: state.id,
      capturedImage: image,
      variant: variant,
    );
  }

  /// Run all predefined slot state tests
  Future<List<ImageComparisonResult>> runAllSlotStateTests({
    required GlobalKey captureKey,
    required Future<void> Function(SlotMachineState state) prepareState,
    List<SlotMachineState>? statesToTest,
  }) async {
    final states = statesToTest ?? SlotMachineState.values;
    final results = <ImageComparisonResult>[];

    for (int i = 0; i < states.length; i++) {
      final state = states[i];
      _progress = (i + 1) / states.length;
      _currentTest = state.id;
      notifyListeners();

      try {
        // Prepare the state
        await prepareState(state);

        // Wait for rendering
        await Future.delayed(const Duration(milliseconds: 100));

        // Run test
        final result = await testSlotState(
          state: state,
          captureKey: captureKey,
        );
        results.add(result);
      } catch (e) {
        results.add(ImageComparisonResult.failed(
          testName: state.id,
          errorMessage: 'Test error: $e',
        ));
      }
    }

    return results;
  }

  /// Generate HTML report for a session
  Future<String> generateHtmlReport(VisualRegressionSession session) async {
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html><head>');
    buffer.writeln('<title>Visual Regression Report - ${session.sessionId}</title>');
    buffer.writeln('<style>');
    buffer.writeln(_getReportCss());
    buffer.writeln('</style>');
    buffer.writeln('</head><body>');

    // Header
    buffer.writeln('<div class="header">');
    buffer.writeln('<h1>Visual Regression Report</h1>');
    buffer.writeln('<p>Session: ${session.sessionId}</p>');
    buffer.writeln('<p>Date: ${session.startTime.toIso8601String()}</p>');
    buffer.writeln('</div>');

    // Summary
    buffer.writeln('<div class="summary">');
    buffer.writeln('<h2>Summary</h2>');
    buffer.writeln('<div class="stats">');
    buffer.writeln('<div class="stat"><span class="value">${session.totalTests}</span><span class="label">Total</span></div>');
    buffer.writeln('<div class="stat passed"><span class="value">${session.passedTests}</span><span class="label">Passed</span></div>');
    buffer.writeln('<div class="stat failed"><span class="value">${session.failedTests}</span><span class="label">Failed</span></div>');
    buffer.writeln('<div class="stat"><span class="value">${(session.passRate * 100).toStringAsFixed(1)}%</span><span class="label">Pass Rate</span></div>');
    buffer.writeln('</div>');
    buffer.writeln('</div>');

    // Results
    buffer.writeln('<div class="results">');
    buffer.writeln('<h2>Test Results</h2>');

    for (final result in session.results) {
      buffer.writeln('<div class="result ${result.passed ? 'passed' : 'failed'}">');
      buffer.writeln('<div class="result-header">');
      buffer.writeln('<span class="status">${result.passed ? 'PASS' : 'FAIL'}</span>');
      buffer.writeln('<span class="name">${result.testName}</span>');
      buffer.writeln('<span class="diff">${(result.diffPercent * 100).toStringAsFixed(4)}% diff</span>');
      buffer.writeln('</div>');

      if (!result.passed) {
        buffer.writeln('<div class="result-details">');
        if (result.errorMessage != null) {
          buffer.writeln('<p class="error">${result.errorMessage}</p>');
        }
        buffer.writeln('<p>Diff pixels: ${result.diffPixelCount} / ${result.totalPixelCount}</p>');

        if (result.goldenPath != null) {
          buffer.writeln('<div class="images">');
          buffer.writeln('<div class="image"><p>Golden</p><img src="${result.goldenPath}" /></div>');
          if (result.capturePath != null) {
            buffer.writeln('<div class="image"><p>Captured</p><img src="${result.capturePath}" /></div>');
          }
          if (result.diffPath != null) {
            buffer.writeln('<div class="image"><p>Diff</p><img src="${result.diffPath}" /></div>');
          }
          buffer.writeln('</div>');
        }
        buffer.writeln('</div>');
      }

      buffer.writeln('</div>');
    }

    buffer.writeln('</div>');
    buffer.writeln('</body></html>');

    final reportPath = path.join(
      _config.diffDirectory,
      'report_${session.sessionId}.html',
    );
    await _saveReportToFile(buffer.toString(), reportPath);

    return buffer.toString();
  }

  String _getReportCss() {
    return '''
      body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #1a1a20; color: #fff; margin: 0; padding: 20px; }
      .header { background: #242430; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
      h1 { margin: 0; color: #4a9eff; }
      .summary { background: #242430; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
      .stats { display: flex; gap: 20px; }
      .stat { background: #1a1a20; padding: 15px 20px; border-radius: 6px; text-align: center; }
      .stat .value { display: block; font-size: 24px; font-weight: bold; }
      .stat .label { font-size: 12px; color: #888; }
      .stat.passed .value { color: #40ff90; }
      .stat.failed .value { color: #ff4060; }
      .results { background: #242430; padding: 20px; border-radius: 8px; }
      .result { margin-bottom: 15px; background: #1a1a20; border-radius: 6px; overflow: hidden; }
      .result-header { display: flex; align-items: center; gap: 15px; padding: 12px 15px; }
      .result.passed .status { color: #40ff90; }
      .result.failed .status { color: #ff4060; }
      .status { font-weight: bold; width: 50px; }
      .name { flex: 1; }
      .diff { color: #888; font-size: 14px; }
      .result-details { padding: 15px; border-top: 1px solid #333; }
      .error { color: #ff4060; }
      .images { display: flex; gap: 15px; margin-top: 15px; }
      .image { flex: 1; }
      .image img { max-width: 100%; border-radius: 4px; }
      .image p { margin: 0 0 8px; font-size: 12px; color: #888; }
    ''';
  }

  Future<void> _saveReportToFile(String html, String filePath) async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(html);
  }

  /// Export session results to JSON
  Future<void> exportSessionToJson(VisualRegressionSession session, String filePath) async {
    final json = const JsonEncoder.withIndent('  ').convert(session.toJson());
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(json);
  }

  /// Clear all history
  void clearHistory() {
    _sessionHistory.clear();
    notifyListeners();
  }

  /// Get latest session
  VisualRegressionSession? get latestSession =>
      _sessionHistory.isNotEmpty ? _sessionHistory.first : null;
}
