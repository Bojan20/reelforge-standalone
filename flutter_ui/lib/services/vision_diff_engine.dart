/// Vision Diff Engine — Detects visual changes between captures
///
/// Compares consecutive snapshots of the same region to detect:
/// - Changed pixel count and percentage
/// - Whether a region is frozen (no change across N captures)
/// - Change velocity (rate of visual change over time)
///
/// Uses raw PNG byte comparison for speed.
/// Does NOT decode to pixel data (too expensive for real-time).
/// Instead uses file size delta + byte-level sampling.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'cortex_vision_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DIFF RESULT
// ═══════════════════════════════════════════════════════════════════════════

/// Result of comparing two consecutive snapshots
class VisionDiffResult {
  final String regionName;
  final DateTime timestamp;
  final double changePercent; // 0.0 = identical, 1.0 = completely different
  final int changedPixels; // Estimated changed pixels
  final int totalPixels;
  final int computeTimeMs;
  final bool isFrozen; // Same as previous N captures

  const VisionDiffResult({
    required this.regionName,
    required this.timestamp,
    required this.changePercent,
    required this.changedPixels,
    required this.totalPixels,
    required this.computeTimeMs,
    required this.isFrozen,
  });

  @override
  String toString() =>
      'VisionDiff($regionName: ${(changePercent * 100).toStringAsFixed(1)}% changed, '
      '${isFrozen ? "FROZEN" : "active"})';
}

// ═══════════════════════════════════════════════════════════════════════════
// VISION DIFF ENGINE
// ═══════════════════════════════════════════════════════════════════════════

class VisionDiffEngine extends ChangeNotifier {
  VisionDiffEngine._();
  static final instance = VisionDiffEngine._();

  /// Previous snapshot bytes per region (for comparison)
  final Map<String, Uint8List> _previousBytes = {};

  /// Latest diff result per region
  final Map<String, VisionDiffResult> _latestDiffs = {};

  /// Frozen counter per region (how many consecutive identical captures)
  final Map<String, int> _frozenCount = {};

  /// Threshold: how many identical captures = "frozen"
  static const int frozenThreshold = 3;

  /// Sample stride for byte comparison (compare every Nth byte for speed)
  static const int sampleStride = 64;

  // ─── Getters ───────────────────────────────────────────────────────

  VisionDiffResult? latestDiffFor(String regionName) => _latestDiffs[regionName];
  Map<String, VisionDiffResult> get allDiffs => Map.unmodifiable(_latestDiffs);
  bool isRegionFrozen(String regionName) =>
      (_frozenCount[regionName] ?? 0) >= frozenThreshold;

  /// Get regions that appear frozen
  List<String> get frozenRegions => _frozenCount.entries
      .where((e) => e.value >= frozenThreshold)
      .map((e) => e.key)
      .toList();

  // ─── Diff Computation ─────────────────────────────────────────────

  /// Compute diff for a region using its latest snapshot
  VisionDiffResult? computeDiff(String regionName) {
    final vision = CortexVisionService.instance;
    final snapshots = vision.snapshots
        .where((s) => s.regionName == regionName)
        .take(2)
        .toList();

    if (snapshots.isEmpty) return null;

    final latest = snapshots.first;
    return computeDiffFromSnapshot(latest);
  }

  /// Compute diff from a specific snapshot vs previous
  VisionDiffResult? computeDiffFromSnapshot(VisionSnapshot snapshot) {
    final stopwatch = Stopwatch()..start();
    final regionName = snapshot.regionName;

    try {
      final file = File(snapshot.filePath);
      if (!file.existsSync()) return null;

      final currentBytes = file.readAsBytesSync();
      final previousBytes = _previousBytes[regionName];

      double changePercent;
      int changedPixels;
      final totalPixels = snapshot.width * snapshot.height;

      if (previousBytes == null) {
        // First capture — 100% change (everything is new)
        changePercent = 1.0;
        changedPixels = totalPixels;
        _frozenCount[regionName] = 0;
      } else {
        // Compare bytes using sampling
        final result = _compareBytes(previousBytes, currentBytes);
        changePercent = result.changeRatio;
        changedPixels = (totalPixels * changePercent).round();

        if (changePercent < 0.001) {
          // Essentially identical
          _frozenCount[regionName] = (_frozenCount[regionName] ?? 0) + 1;
        } else {
          _frozenCount[regionName] = 0;
        }
      }

      // Store current as previous for next comparison
      _previousBytes[regionName] = Uint8List.fromList(currentBytes);

      stopwatch.stop();

      final result = VisionDiffResult(
        regionName: regionName,
        timestamp: DateTime.now(),
        changePercent: changePercent,
        changedPixels: changedPixels,
        totalPixels: totalPixels,
        computeTimeMs: stopwatch.elapsedMilliseconds,
        isFrozen: (_frozenCount[regionName] ?? 0) >= frozenThreshold,
      );

      _latestDiffs[regionName] = result;
      notifyListeners();
      return result;
    } catch (e) {
      debugPrint('[VisionDiff] Error computing diff for $regionName: $e');
      return null;
    }
  }

  /// Compute diffs for ALL regions
  void computeAllDiffs() {
    final vision = CortexVisionService.instance;
    for (final name in vision.regions.keys) {
      computeDiff(name);
    }
    // Also diff full_window
    computeDiff('full_window');
  }

  /// Compare two byte arrays using sampling for speed
  _ByteCompareResult _compareBytes(Uint8List a, Uint8List b) {
    // Fast path: identical length check
    if (a.length == b.length && a.length == 0) {
      return const _ByteCompareResult(0, 0);
    }

    // Size difference is itself a change indicator
    final sizeDelta = (a.length - b.length).abs();
    if (sizeDelta > a.length * 0.1) {
      // >10% size change = significant visual change
      return _ByteCompareResult(
        sizeDelta.toDouble() / a.length.clamp(1, a.length),
        sizeDelta,
      );
    }

    // Sample-based comparison
    final minLen = a.length < b.length ? a.length : b.length;
    int diffCount = 0;
    int sampleCount = 0;

    for (int i = 0; i < minLen; i += sampleStride) {
      sampleCount++;
      if (a[i] != b[i]) {
        diffCount++;
      }
    }

    if (sampleCount == 0) return const _ByteCompareResult(0, 0);

    final changeRatio = diffCount / sampleCount;
    return _ByteCompareResult(changeRatio, diffCount);
  }

  /// Clear all cached data
  void reset() {
    _previousBytes.clear();
    _latestDiffs.clear();
    _frozenCount.clear();
    notifyListeners();
  }
}

class _ByteCompareResult {
  final double changeRatio;
  final int diffSamples;
  const _ByteCompareResult(this.changeRatio, this.diffSamples);
}
