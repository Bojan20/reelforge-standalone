/// CORTEX Vision Service — The Eyes of the Organism
///
/// Enables CORTEX to SEE what the application displays:
/// - Full window capture at any moment
/// - Individual widget/region capture via RepaintBoundary keys
/// - Automatic periodic snapshots for visual understanding
/// - Visual diff detection (what changed between frames)
/// - Screenshot-based testing integration
///
/// Philosophy: CORTEX doesn't just read code — it SEES what users see.
/// Every UI state, every animation frame, every visual change is observable.
///
/// Created: 2026-04-05 (CORTEX Eyes)

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// ═══════════════════════════════════════════════════════════════════════════
// VISION REGION — Named capture targets
// ═══════════════════════════════════════════════════════════════════════════

/// A named region of the UI that CORTEX can observe
class VisionRegion {
  final String name;
  final String description;
  final GlobalKey boundaryKey;
  final DateTime registeredAt;

  VisionRegion({
    required this.name,
    required this.description,
    GlobalKey? key,
  })  : boundaryKey = key ?? GlobalKey(debugLabel: 'cortex_vision_$name'),
        registeredAt = DateTime.now();
}

// ═══════════════════════════════════════════════════════════════════════════
// VISION SNAPSHOT — A captured moment in time
// ═══════════════════════════════════════════════════════════════════════════

/// A visual snapshot captured by CORTEX
class VisionSnapshot {
  final String regionName;
  final DateTime capturedAt;
  final String filePath;
  final int width;
  final int height;
  final int byteSize;
  final Map<String, dynamic> metadata;

  const VisionSnapshot({
    required this.regionName,
    required this.capturedAt,
    required this.filePath,
    required this.width,
    required this.height,
    required this.byteSize,
    this.metadata = const {},
  });

  String get resolution => '${width}x$height';
  String get sizeKB => '${(byteSize / 1024).toStringAsFixed(1)} KB';

  @override
  String toString() => 'VisionSnapshot($regionName, $resolution, $sizeKB)';
}

// ═══════════════════════════════════════════════════════════════════════════
// VISION EVENT — What CORTEX observed changing
// ═══════════════════════════════════════════════════════════════════════════

/// Types of visual events CORTEX can detect
enum VisionEventType {
  /// UI state changed (new screen, panel opened/closed)
  stateChange,

  /// Animation completed
  animationComplete,

  /// User interaction triggered visual change
  userInteraction,

  /// Error state visible in UI
  errorVisible,

  /// Periodic health check snapshot
  healthCheck,

  /// Manual capture requested
  manualCapture,
}

/// A visual event observed by CORTEX
class VisionEvent {
  final VisionEventType type;
  final String description;
  final VisionSnapshot? snapshot;
  final DateTime timestamp;

  const VisionEvent({
    required this.type,
    required this.description,
    this.snapshot,
    required this.timestamp,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// CORTEX VISION SERVICE — The seeing eye
// ═══════════════════════════════════════════════════════════════════════════

/// CORTEX Vision Service — gives the organism eyes.
///
/// Usage:
/// 1. Register regions: `CortexVisionService.instance.registerRegion(...)`
/// 2. Wrap widgets: `RepaintBoundary(key: region.boundaryKey, child: ...)`
/// 3. Capture: `await CortexVisionService.instance.capture('timeline')`
/// 4. Auto-observe: `CortexVisionService.instance.startObserving()`
class CortexVisionService extends ChangeNotifier {
  CortexVisionService._();
  static final instance = CortexVisionService._();

  // ─── State ─────────────────────────────────────────────────────────────

  /// Registered vision regions
  final Map<String, VisionRegion> _regions = {};
  Map<String, VisionRegion> get regions => Map.unmodifiable(_regions);

  /// The root app boundary key — captures EVERYTHING
  final GlobalKey rootBoundaryKey = GlobalKey(debugLabel: 'cortex_vision_root');

  /// Snapshot history (most recent first)
  final List<VisionSnapshot> _snapshots = [];
  List<VisionSnapshot> get snapshots => List.unmodifiable(_snapshots);

  /// Event log
  final List<VisionEvent> _events = [];
  List<VisionEvent> get events => List.unmodifiable(_events);

  /// Auto-observation timer
  Timer? _observeTimer;
  bool get isObserving => _observeTimer != null;

  /// Output directory for captures
  String _outputDir = '';

  /// Maximum snapshots to keep in memory
  static const int _maxSnapshots = 200;
  static const int _maxEvents = 500;

  /// Pixel ratio for captures (2.0 = Retina quality)
  double pixelRatio = 2.0;

  // ─── Initialization ────────────────────────────────────────────────────

  /// Initialize the vision system
  Future<void> init() async {
    final home = Platform.environment['HOME'] ?? '/tmp';
    _outputDir = '$home/Library/Application Support/FluxForge Studio/CortexVision';
    await Directory(_outputDir).create(recursive: true);

    // Create subdirectories
    await Directory('$_outputDir/snapshots').create(recursive: true);
    await Directory('$_outputDir/regions').create(recursive: true);
    await Directory('$_outputDir/diffs').create(recursive: true);
  }

  // ─── Region Management ─────────────────────────────────────────────────

  /// Register a UI region for observation
  VisionRegion registerRegion({
    required String name,
    required String description,
    GlobalKey? key,
  }) {
    final region = VisionRegion(name: name, description: description, key: key);
    _regions[name] = region;
    return region;
  }

  /// Unregister a region
  void unregisterRegion(String name) {
    _regions.remove(name);
  }

  /// Get a registered region
  VisionRegion? getRegion(String name) => _regions[name];

  // ─── Capture ───────────────────────────────────────────────────────────

  /// Capture the full application window
  Future<VisionSnapshot?> captureFullWindow({
    Map<String, dynamic> metadata = const {},
  }) async {
    return _captureFromKey(rootBoundaryKey, 'full_window', metadata: metadata);
  }

  /// Capture a specific named region
  Future<VisionSnapshot?> capture(
    String regionName, {
    Map<String, dynamic> metadata = const {},
  }) async {
    final region = _regions[regionName];
    if (region == null) {
      debugPrint('[CortexVision] Region not found: $regionName');
      return null;
    }
    return _captureFromKey(region.boundaryKey, regionName, metadata: metadata);
  }

  /// Capture ALL registered regions at once
  Future<List<VisionSnapshot>> captureAll({
    Map<String, dynamic> metadata = const {},
  }) async {
    final results = <VisionSnapshot>[];
    for (final name in _regions.keys) {
      final snapshot = await capture(name, metadata: metadata);
      if (snapshot != null) results.add(snapshot);
    }

    // Also capture full window
    final fullWindow = await captureFullWindow(metadata: metadata);
    if (fullWindow != null) results.add(fullWindow);

    return results;
  }

  /// Internal: capture from a GlobalKey pointing to a RepaintBoundary
  Future<VisionSnapshot?> _captureFromKey(
    GlobalKey key,
    String name, {
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('[CortexVision] No RenderRepaintBoundary for: $name');
        return null;
      }

      // Capture to image
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);

      // Convert to PNG bytes
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        image.dispose();
        return null;
      }

      final Uint8List bytes = byteData.buffer.asUint8List();

      // Generate filename with timestamp
      final ts = DateTime.now();
      final tsStr = '${ts.year}${_pad(ts.month)}${_pad(ts.day)}'
          '_${_pad(ts.hour)}${_pad(ts.minute)}${_pad(ts.second)}'
          '_${ts.millisecond}';
      final subDir = name == 'full_window' ? 'snapshots' : 'regions';
      final filePath = '$_outputDir/$subDir/${name}_$tsStr.png';

      // Write to disk
      await File(filePath).writeAsBytes(bytes);

      final snapshot = VisionSnapshot(
        regionName: name,
        capturedAt: ts,
        filePath: filePath,
        width: image.width,
        height: image.height,
        byteSize: bytes.length,
        metadata: metadata,
      );

      // Store in history
      _snapshots.insert(0, snapshot);
      if (_snapshots.length > _maxSnapshots) {
        _snapshots.removeLast();
      }

      image.dispose();

      notifyListeners();
      return snapshot;
    } catch (e) {
      debugPrint('[CortexVision] Capture failed for $name: $e');
      return null;
    }
  }

  // ─── Auto-Observation ──────────────────────────────────────────────────

  /// Start periodic observation (CORTEX watches the app)
  void startObserving({
    Duration interval = const Duration(seconds: 10),
    bool fullWindowOnly = false,
  }) {
    stopObserving();
    _observeTimer = Timer.periodic(interval, (_) async {
      if (fullWindowOnly) {
        await captureFullWindow(metadata: {'type': 'auto_observe'});
      } else {
        await captureAll(metadata: {'type': 'auto_observe'});
      }

      _addEvent(VisionEvent(
        type: VisionEventType.healthCheck,
        description: 'Periodic observation: ${_regions.length} regions',
        timestamp: DateTime.now(),
      ));
    });
  }

  /// Stop periodic observation
  void stopObserving() {
    _observeTimer?.cancel();
    _observeTimer = null;
  }

  // ─── Event Logging ─────────────────────────────────────────────────────

  /// Record a visual event
  void recordEvent({
    required VisionEventType type,
    required String description,
    VisionSnapshot? snapshot,
  }) {
    _addEvent(VisionEvent(
      type: type,
      description: description,
      snapshot: snapshot,
      timestamp: DateTime.now(),
    ));
  }

  void _addEvent(VisionEvent event) {
    _events.insert(0, event);
    if (_events.length > _maxEvents) {
      _events.removeLast();
    }
    notifyListeners();
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────

  /// Clean up old snapshots from disk (keep last N)
  Future<int> cleanupOldSnapshots({int keepLast = 50}) async {
    int deleted = 0;
    for (final subDir in ['snapshots', 'regions']) {
      final dir = Directory('$_outputDir/$subDir');
      if (!await dir.exists()) continue;

      final files = await dir.list().where((e) => e is File).toList();
      files.sort((a, b) => b.path.compareTo(a.path)); // newest first

      for (var i = keepLast; i < files.length; i++) {
        await files[i].delete();
        deleted++;
      }
    }
    return deleted;
  }

  /// Get the latest snapshot for a region
  VisionSnapshot? latestFor(String regionName) {
    return _snapshots.where((s) => s.regionName == regionName).firstOrNull;
  }

  /// Get the output directory path
  String get outputDirectory => _outputDir;

  // ─── Helpers ───────────────────────────────────────────────────────────

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  void dispose() {
    stopObserving();
    super.dispose();
  }
}
