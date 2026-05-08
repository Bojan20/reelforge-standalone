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

import 'vision_diff_engine.dart';
import '../src/rust/native_ffi.dart';

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

  /// Pixel ratio for explicit / API captures (2.0 = Retina quality)
  double pixelRatio = 2.0;

  // ─── Disk budget (H-006 fix) ───────────────────────────────────────────
  //
  // Background:  prior to 2026-05-08 the service wrote a Retina-resolution
  // PNG every 10s for every registered region (default 6 captures/tick → 36/min
  // → ~50 000 fragments/day) and `cleanupOldSnapshots` was NEVER invoked.
  // The result was a silent ~80 GB / 33 271-file leak in
  // `~/Library/Application Support/FluxForge Studio/CortexVision/`.
  //
  // The fix has four orthogonal lines of defence:
  //   1. Startup purge of files older than `maxAgeDays`.
  //   2. Hard disk-budget ceiling (`maxDiskBytes`) enforced on every write.
  //   3. Skipping frozen regions during auto-observe.
  //   4. Lower pixel ratio + slower interval for auto-observe.
  // Everything is configurable so tests / power users can tune it.

  /// Hard ceiling for total bytes kept on disk under `_outputDir`.
  /// Default 500 MB.  Once exceeded, oldest files are deleted until we are
  /// back below the cap.
  int maxDiskBytes = 500 * 1024 * 1024;

  /// Files older than this are purged at startup and on each scheduled
  /// cleanup tick.  Default 7 days.
  Duration maxAge = const Duration(days: 7);

  /// Run a scheduled cleanup every N writes (cheap counter, avoids walking
  /// the directory on every capture).  Default 100.
  int purgeEveryNCaptures = 100;

  /// When true, auto-observe skips regions that VisionDiffEngine has
  /// classified as frozen (no pixel changes for several captures).
  /// Frozen regions still get a single "freshness" snapshot every
  /// `_frozenRefreshEvery` ticks so the diff engine never starves.
  bool skipFrozenInAutoObserve = true;
  static const int _frozenRefreshEvery = 12; // ≈ 6 minutes at 30 s tick

  /// Pixel ratio used during auto-observe captures (independent of the
  /// public `pixelRatio` field, which API consumers control).
  double autoObservePixelRatio = 1.0;

  /// Internal: rolling counter, used by `purgeEveryNCaptures` and by
  /// `_frozenRefreshEvery`.
  int _captureCounter = 0;

  /// Internal: cached current disk usage so we don't `stat` every time.
  /// Kept in sync by `_writeAndAccount` and `_runDiskBudgetCleanup`.
  int _diskUsageBytes = 0;

  /// True while a cleanup is in flight; prevents two cleanups from racing.
  bool _cleanupInFlight = false;

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

    // H-006: startup purge — delete files older than `maxAge`, then size-cap
    // the rest under `maxDiskBytes`.  This recovers any disk previously
    // leaked by the un-bounded auto-observer and gets the in-memory accumulator
    // in sync with reality.
    await _purgeStartup();
  }

  /// Purge old files on startup and rebuild the disk-usage accumulator.
  /// Errors during enumeration are logged but never thrown — the rest of
  /// the app must come up even if a stat() fails on a stray symlink.
  Future<void> _purgeStartup() async {
    try {
      final cutoff = DateTime.now().subtract(maxAge);
      int purged = 0;
      int total = 0;
      for (final subDir in const ['snapshots', 'regions', 'diffs']) {
        final dir = Directory('$_outputDir/$subDir');
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          try {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
              purged++;
              continue;
            }
            total += stat.size;
          } catch (_) {
            // Skip files that vanish or can't be stat'd.
          }
        }
      }
      _diskUsageBytes = total;
      if (purged > 0 || total > 0) {
        debugPrint(
          '[CortexVision] startup: purged $purged stale, '
          '${(total / (1024 * 1024)).toStringAsFixed(1)} MB on disk',
        );
      }
      // Enforce budget on whatever survived the age cut.
      if (_diskUsageBytes > maxDiskBytes) {
        await _runDiskBudgetCleanup();
      }
    } catch (e) {
      debugPrint('[CortexVision] startup purge failed: $e');
    }
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

  /// Internal: capture from a GlobalKey pointing to a RepaintBoundary.
  ///
  /// `pixelRatioOverride` lets the auto-observer use a smaller ratio than
  /// the public `pixelRatio` field so the on-disk footprint of background
  /// captures stays small without affecting on-demand API captures.
  Future<VisionSnapshot?> _captureFromKey(
    GlobalKey key,
    String name, {
    Map<String, dynamic> metadata = const {},
    double? pixelRatioOverride,
  }) async {
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('[CortexVision] No RenderRepaintBoundary for: $name');
        return null;
      }

      // Capture to image
      final ratio = pixelRatioOverride ?? pixelRatio;
      final ui.Image image = await boundary.toImage(pixelRatio: ratio);

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

      // Write to disk + account for disk budget.
      await _writeAndAccount(filePath, bytes);

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

  /// Write bytes to disk and update the running disk-usage tally.
  /// Triggers cleanups when budget is exceeded or on the periodic counter.
  Future<void> _writeAndAccount(String filePath, Uint8List bytes) async {
    await File(filePath).writeAsBytes(bytes);
    _diskUsageBytes += bytes.length;
    _captureCounter++;

    // Two independent triggers — whichever fires first.
    final overBudget = _diskUsageBytes > maxDiskBytes;
    final scheduled =
        purgeEveryNCaptures > 0 && _captureCounter % purgeEveryNCaptures == 0;
    if (overBudget || scheduled) {
      // Run cleanup async; never block the capture path.
      // ignore: discarded_futures
      _runDiskBudgetCleanup();
    }
  }

  /// Walk the output directory and delete oldest files (snapshots, regions,
  /// diffs) until we are below `maxDiskBytes` and no file is older than
  /// `maxAge`.  Idempotent + reentrancy-guarded.
  Future<void> _runDiskBudgetCleanup() async {
    if (_cleanupInFlight) return;
    _cleanupInFlight = true;
    try {
      final cutoff = DateTime.now().subtract(maxAge);

      // Collect every file with stat + age.
      final all = <_FileEntry>[];
      for (final subDir in const ['snapshots', 'regions', 'diffs']) {
        final dir = Directory('$_outputDir/$subDir');
        if (!await dir.exists()) continue;
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          try {
            final stat = await entity.stat();
            all.add(_FileEntry(entity, stat.size, stat.modified));
          } catch (_) {}
        }
      }

      // Phase A — drop everything past the age cutoff.
      int totalBytes = 0;
      final survivors = <_FileEntry>[];
      for (final f in all) {
        if (f.modified.isBefore(cutoff)) {
          try {
            await f.file.delete();
          } catch (_) {}
          continue;
        }
        survivors.add(f);
        totalBytes += f.size;
      }

      // Phase B — if still over budget, delete oldest first.
      if (totalBytes > maxDiskBytes) {
        survivors.sort((a, b) => a.modified.compareTo(b.modified)); // oldest first
        for (final f in survivors) {
          if (totalBytes <= maxDiskBytes) break;
          try {
            await f.file.delete();
            totalBytes -= f.size;
          } catch (_) {}
        }
      }

      _diskUsageBytes = totalBytes;
    } catch (e) {
      debugPrint('[CortexVision] disk-budget cleanup failed: $e');
    } finally {
      _cleanupInFlight = false;
    }
  }

  /// Current accounting (exposed for tests / diagnostics).
  int get diskUsageBytes => _diskUsageBytes;
  int get captureCounter => _captureCounter;

  // ─── Auto-Observation ──────────────────────────────────────────────────

  /// Start periodic observation (CORTEX watches the app).
  ///
  /// Default interval was raised from 10 s → 30 s as part of the H-006
  /// disk-leak fix (combined with the disk-budget cap and frozen-region
  /// skipping, on-disk footprint drops by ~30×).
  void startObserving({
    Duration interval = const Duration(seconds: 30),
    bool fullWindowOnly = false,
  }) {
    stopObserving();
    _observeTimer = Timer.periodic(interval, (_) async {
      if (fullWindowOnly) {
        await _captureFromKey(
          rootBoundaryKey,
          'full_window',
          metadata: const {'type': 'auto_observe'},
          pixelRatioOverride: autoObservePixelRatio,
        );
      } else {
        await _autoObserveAll();
      }

      // Compute visual diffs after capture
      VisionDiffEngine.instance.computeAllDiffs();

      // Detect frozen regions and emit anomaly events
      final frozen = VisionDiffEngine.instance.frozenRegions;
      for (final region in frozen) {
        _addEvent(VisionEvent(
          type: VisionEventType.errorVisible,
          description: 'Region "$region" appears frozen (no visual change)',
          timestamp: DateTime.now(),
        ));
      }

      // Report vision telemetry to Rust CORTEX (updates awareness dimension)
      try {
        final ffi = NativeFFI.instance;
        if (ffi.isLoaded) {
          ffi.cortexReportVision(frozen.length, frozen.length, _regions.length);
        }
      } catch (_) {
        // FFI not available (e.g., test mode)
      }

      _addEvent(VisionEvent(
        type: VisionEventType.healthCheck,
        description: 'Periodic observation: ${_regions.length} regions'
            '${frozen.isNotEmpty ? ', ${frozen.length} frozen' : ''}'
            ', disk=${(_diskUsageBytes / (1024 * 1024)).toStringAsFixed(1)}MB',
        timestamp: DateTime.now(),
      ));
    });
  }

  /// Auto-observe pass that respects `skipFrozenInAutoObserve` and uses
  /// `autoObservePixelRatio` instead of the public `pixelRatio` field.
  /// Frozen regions still get a refresh capture every `_frozenRefreshEvery`
  /// observe ticks so the diff engine never deadlocks on a region.
  Future<void> _autoObserveAll() async {
    final diff = VisionDiffEngine.instance;
    final allowFrozenRefresh =
        skipFrozenInAutoObserve && (_captureCounter % _frozenRefreshEvery == 0);

    for (final name in _regions.keys) {
      if (skipFrozenInAutoObserve &&
          diff.isRegionFrozen(name) &&
          !allowFrozenRefresh) {
        continue;
      }
      final region = _regions[name];
      if (region == null) continue;
      await _captureFromKey(
        region.boundaryKey,
        name,
        metadata: const {'type': 'auto_observe'},
        pixelRatioOverride: autoObservePixelRatio,
      );
    }

    // Always grab a full-window snapshot so we have a global reference.
    await _captureFromKey(
      rootBoundaryKey,
      'full_window',
      metadata: const {'type': 'auto_observe'},
      pixelRatioOverride: autoObservePixelRatio,
    );
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

// ═══════════════════════════════════════════════════════════════════════════
// INTERNAL — file accounting helper for cleanup pass
// ═══════════════════════════════════════════════════════════════════════════

class _FileEntry {
  final File file;
  final int size;
  final DateTime modified;
  const _FileEntry(this.file, this.size, this.modified);
}
