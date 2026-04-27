/// Global Waveform Cache with Multi-Resolution LOD
///
/// Cubase/Logic Pro style waveform caching:
/// - Pre-computed peak data at multiple zoom levels (mipmaps)
/// - Each level stores min/max pairs per window
/// - O(width) render time regardless of audio length
/// - LRU eviction for memory management
///
/// LOD Levels (Rust SIMD — 11 levels from 4 to 4096 samples/bucket):
///   Level 0:  4 samples per peak     (ultra zoom)
///   Level 1:  8 samples per peak
///   Level 2:  16 samples per peak
///   Level 3:  32 samples per peak
///   Level 4:  64 samples per peak
///   Level 5:  128 samples per peak
///   Level 6:  256 samples per peak
///   Level 7:  512 samples per peak
///   Level 8:  1024 samples per peak
///   Level 9:  2048 samples per peak
///   Level 10: 4096 samples per peak  (zoomed out)
///
/// SIMD Optimization (AVX2/NEON):
/// - Rust-side LOD generation is 10-20x faster than Dart
/// - Uses rayon for parallel multi-LOD computation
/// - Zero-copy memory operations

import 'dart:convert';
import 'dart:typed_data';
import 'dart:collection';
import 'dart:math' as math;
import '../widgets/waveform/ultimate_waveform.dart';
import '../src/rust/native_ffi.dart';

/// Peak data for a single LOD level
class PeakLevel {
  /// Min values for this level
  final Float32List minPeaks;
  /// Max values for this level
  final Float32List maxPeaks;
  /// Samples per peak at this level
  final int samplesPerPeak;

  const PeakLevel({
    required this.minPeaks,
    required this.maxPeaks,
    required this.samplesPerPeak,
  });

  int get length => minPeaks.length;
}

/// Multi-resolution waveform data for a single clip
class MultiResWaveform {
  /// Left channel peak levels (indexed by LOD level)
  final List<PeakLevel> leftLevels;
  /// Right channel peak levels (null for mono)
  final List<PeakLevel>? rightLevels;
  /// Original sample count
  final int totalSamples;
  /// Sample rate
  final int sampleRate;
  /// Is stereo
  bool get isStereo => rightLevels != null;

  const MultiResWaveform({
    required this.leftLevels,
    this.rightLevels,
    required this.totalSamples,
    required this.sampleRate,
  });

  /// Get the best LOD level for a given zoom (pixels per second)
  /// Supports 11 LOD levels from Rust (4 to 4096 samples/bucket)
  int getBestLodLevel(double zoom) {
    // Higher zoom = need finer detail = lower level index
    // Rust LOD levels: 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096
    final maxLevel = leftLevels.length - 1;
    if (zoom > 2000) return 0;                           // 4 samples/bucket
    if (zoom > 1000) return math.min(1, maxLevel);       // 8 samples/bucket
    if (zoom > 500) return math.min(2, maxLevel);        // 16 samples/bucket
    if (zoom > 250) return math.min(3, maxLevel);        // 32 samples/bucket
    if (zoom > 125) return math.min(4, maxLevel);        // 64 samples/bucket
    if (zoom > 60) return math.min(5, maxLevel);         // 128 samples/bucket
    if (zoom > 30) return math.min(6, maxLevel);         // 256 samples/bucket
    if (zoom > 15) return math.min(7, maxLevel);         // 512 samples/bucket
    if (zoom > 7) return math.min(8, maxLevel);          // 1024 samples/bucket
    if (zoom > 3) return math.min(9, maxLevel);          // 2048 samples/bucket
    return maxLevel;                                      // 4096 samples/bucket
  }

  /// Get peak level for given LOD
  PeakLevel getLevel(int lod) {
    return leftLevels[lod.clamp(0, leftLevels.length - 1)];
  }

  /// Get right channel peak level (returns left if mono)
  PeakLevel getRightLevel(int lod) {
    if (rightLevels == null) return getLevel(lod);
    return rightLevels![lod.clamp(0, rightLevels!.length - 1)];
  }
}

/// Global singleton cache for waveform data
class WaveformCache {
  static final WaveformCache _instance = WaveformCache._internal();
  factory WaveformCache() => _instance;
  WaveformCache._internal();

  /// Cache storage: clipId -> cached waveform data
  final LinkedHashMap<String, _CachedWaveform> _cache = LinkedHashMap();

  /// Multi-res cache: clipId -> multi-resolution peaks
  final LinkedHashMap<String, MultiResWaveform> _multiResCache = LinkedHashMap();

  /// Maximum cache size (number of clips). Kept as a coarse upper
  /// bound; the byte budget below is the real constraint.
  static const int _maxCacheSize = 100;

  /// Maximum samples to store per clip for legacy cache
  static const int _maxSamplesPerClip = 2000;

  /// FLUX_MASTER_TODO 2.2.5 — byte budget for the multi-res cache.
  /// The previous count-only LRU (100 clips) was the wrong unit: 100
  /// short SFX clips and 100 6-minute music tracks both fit in "100
  /// entries", but the second case can pin ~1.5 GB of waveform peaks
  /// in memory and trigger Flutter's image-asset OOM (BUG #46
  /// "oversized images"). Now we track an estimated byte cost per
  /// entry and evict whichever LRU oldest until total drops below
  /// budget, regardless of count.
  ///
  /// 256 MB is comfortable for a typical session: a 6-minute stereo
  /// 48 kHz track at 11 LOD levels generates roughly 8 MB of f32
  /// peaks; the budget therefore holds ~32 long tracks plus dozens
  /// of short SFX, well above any realistic project working set.
  static const int _maxMultiResBytes = 256 * 1024 * 1024;

  /// Estimated total bytes in `_multiResCache`. Updated incrementally
  /// on insert/evict so we don't have to walk every entry per check.
  int _multiResTotalBytes = 0;

  /// Estimate the heap footprint of a `MultiResWaveform`. Each PeakLevel
  /// holds two `Float32List`s (min + max) per channel; size = sum of
  /// `length * 4` across all levels and channels, plus a tiny per-level
  /// overhead absorbed into the constant 32.
  static int _estimateBytes(MultiResWaveform w) {
    int bytes = 0;
    for (final level in w.leftLevels) {
      bytes += level.minPeaks.lengthInBytes + level.maxPeaks.lengthInBytes + 32;
    }
    final right = w.rightLevels;
    if (right != null) {
      for (final level in right) {
        bytes += level.minPeaks.lengthInBytes + level.maxPeaks.lengthInBytes + 32;
      }
    }
    return bytes;
  }

  /// Evict LRU entries until both byte budget AND count cap are
  /// satisfied. Caller is expected to have already accounted for the
  /// incoming entry's bytes so the post-condition holds.
  void _evictMultiResUntilWithinBudget() {
    while (_multiResCache.isNotEmpty &&
        (_multiResTotalBytes > _maxMultiResBytes ||
            _multiResCache.length > _maxCacheSize)) {
      final oldestKey = _multiResCache.keys.first;
      final removed = _multiResCache.remove(oldestKey);
      if (removed != null) {
        _multiResTotalBytes -= _estimateBytes(removed);
        if (_multiResTotalBytes < 0) _multiResTotalBytes = 0;
      } else {
        break;
      }
    }
  }

  /// LOD level configurations: samples per peak
  static const List<int> _lodSamplesPerPeak = [256, 512, 1024, 2048, 4096, 8192];

  // ═══════════════════════════════════════════════════════════════════════════
  // RUST SIMD MULTI-RESOLUTION API (10-20x faster than Dart)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get or compute multi-resolution peaks from audio FILE PATH using Rust SIMD
  /// This is the PREFERRED API — 10-20x faster than Dart computation
  ///
  /// Uses Rust's AVX2/NEON SIMD + rayon parallel LOD generation
  MultiResWaveform? getOrComputeMultiResFromPath(String clipId, String audioPath) {
    // Check cache first
    if (_multiResCache.containsKey(clipId)) {
      // LRU: move to end
      final cached = _multiResCache.remove(clipId)!;
      _multiResCache[clipId] = cached;
      return cached;
    }

    // Generate via Rust FFI (SIMD optimized)
    final json = NativeFFI.instance.generateWaveformFromFile(audioPath, clipId);
    if (json == null) return null;

    // Parse JSON response from Rust
    final data = _parseRustWaveformJson(json);
    if (data == null) return null;

    // Track byte cost of incoming entry, then evict LRU until both
    // byte and count budgets hold. (FLUX_MASTER_TODO 2.2.5 / BUG #46.)
    _multiResTotalBytes += _estimateBytes(data);
    _multiResCache[clipId] = data;
    _evictMultiResUntilWithinBudget();
    return data;
  }

  /// Parse Rust waveform JSON into MultiResWaveform
  /// JSON format from Rust:
  /// {
  ///   "sample_rate": 48000,
  ///   "total_samples": 1234567,
  ///   "channels": 2,
  ///   "lod_levels": [
  ///     {
  ///       "samples_per_bucket": 4,
  ///       "left": [{"min": -0.5, "max": 0.5, "rms": 0.3}, ...],
  ///       "right": [{"min": -0.5, "max": 0.5, "rms": 0.3}, ...]
  ///     },
  ///     ...
  ///   ]
  /// }
  MultiResWaveform? _parseRustWaveformJson(String json) {
    try {
      final Map<String, dynamic> data = jsonDecode(json);
      final int sampleRate = data['sample_rate'] ?? 48000;
      final int totalSamples = data['total_samples'] ?? 0;
      final int channels = data['channels'] ?? 1;
      final List<dynamic> lodLevels = data['lod_levels'] ?? [];

      if (lodLevels.isEmpty) return null;

      final leftLevels = <PeakLevel>[];
      List<PeakLevel>? rightLevels;
      if (channels >= 2) {
        rightLevels = <PeakLevel>[];
      }

      for (final level in lodLevels) {
        final int samplesPerBucket = level['samples_per_bucket'] ?? 256;
        final List<dynamic> leftBuckets = level['left'] ?? [];
        final List<dynamic>? rightBuckets = level['right'];

        // Parse left channel
        final leftMins = Float32List(leftBuckets.length);
        final leftMaxs = Float32List(leftBuckets.length);
        for (int i = 0; i < leftBuckets.length; i++) {
          final bucket = leftBuckets[i];
          leftMins[i] = (bucket['min'] as num).toDouble();
          leftMaxs[i] = (bucket['max'] as num).toDouble();
        }
        leftLevels.add(PeakLevel(
          minPeaks: leftMins,
          maxPeaks: leftMaxs,
          samplesPerPeak: samplesPerBucket,
        ));

        // Parse right channel if stereo
        if (rightLevels != null && rightBuckets != null) {
          final rightMins = Float32List(rightBuckets.length);
          final rightMaxs = Float32List(rightBuckets.length);
          for (int i = 0; i < rightBuckets.length; i++) {
            final bucket = rightBuckets[i];
            rightMins[i] = (bucket['min'] as num).toDouble();
            rightMaxs[i] = (bucket['max'] as num).toDouble();
          }
          rightLevels.add(PeakLevel(
            minPeaks: rightMins,
            maxPeaks: rightMaxs,
            samplesPerPeak: samplesPerBucket,
          ));
        }
      }

      return MultiResWaveform(
        leftLevels: leftLevels,
        rightLevels: rightLevels,
        totalSamples: totalSamples,
        sampleRate: sampleRate,
      );
    } catch (e) {
      // Fallback: return null, caller should use Dart fallback
      return null;
    }
  }

  /// Invalidate Rust-side waveform cache for a clip
  void invalidateRustCache(String clipId) {
    NativeFFI.instance.invalidateWaveformCache(clipId);
    final removed = _multiResCache.remove(clipId);
    if (removed != null) {
      _multiResTotalBytes -= _estimateBytes(removed);
      if (_multiResTotalBytes < 0) _multiResTotalBytes = 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DART FALLBACK MULTI-RESOLUTION API (for when samples are already loaded)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get or compute multi-resolution peaks for a clip (Dart fallback)
  /// Use getOrComputeMultiResFromPath() when possible — it's 10-20x faster
  MultiResWaveform getOrComputeMultiRes(
    String clipId,
    Float32List waveform,
    Float32List? waveformRight,
    int sampleRate,
  ) {
    // Check cache first
    if (_multiResCache.containsKey(clipId)) {
      // LRU: move to end
      final cached = _multiResCache.remove(clipId)!;
      _multiResCache[clipId] = cached;
      return cached;
    }

    // Compute all LOD levels (Dart fallback — slower than Rust)
    final data = _computeMultiResPeaks(waveform, waveformRight, sampleRate);

    // Track byte cost + LRU evict (BUG #46).
    _multiResTotalBytes += _estimateBytes(data);
    _multiResCache[clipId] = data;
    _evictMultiResUntilWithinBudget();
    return data;
  }

  /// Get cached multi-res data without generating (read-only lookup)
  /// Used by TimelineWaveformPainter for instant rendering from shared cache
  MultiResWaveform? getMultiRes(String clipId) {
    final cached = _multiResCache[clipId];
    if (cached != null) {
      // LRU: move to end
      _multiResCache.remove(clipId);
      _multiResCache[clipId] = cached;
    }
    return cached;
  }

  /// Check if multi-res data is cached
  bool hasMultiRes(String clipId) => _multiResCache.containsKey(clipId);

  /// Remove multi-res data from cache
  void removeMultiRes(String clipId) {
    final removed = _multiResCache.remove(clipId);
    if (removed != null) {
      _multiResTotalBytes -= _estimateBytes(removed);
      if (_multiResTotalBytes < 0) _multiResTotalBytes = 0;
    }
  }

  /// Clear multi-res cache
  void clearMultiRes() {
    _multiResCache.clear();
    _multiResTotalBytes = 0;
  }

  /// Total estimated bytes currently held by the multi-res cache.
  /// Exposed for diagnostics + the regression test.
  int get multiResTotalBytes => _multiResTotalBytes;

  /// Compute all LOD levels for audio data
  MultiResWaveform _computeMultiResPeaks(
    Float32List waveform,
    Float32List? waveformRight,
    int sampleRate,
  ) {
    final totalSamples = waveform.length;

    // Build left channel levels
    final leftLevels = <PeakLevel>[];
    for (final samplesPerPeak in _lodSamplesPerPeak) {
      final level = _computePeakLevel(waveform, samplesPerPeak);
      leftLevels.add(level);
      // Stop if we're down to very few peaks
      if (level.length < 10) break;
    }

    // Build right channel levels if stereo
    List<PeakLevel>? rightLevels;
    if (waveformRight != null && waveformRight.isNotEmpty) {
      rightLevels = <PeakLevel>[];
      for (final samplesPerPeak in _lodSamplesPerPeak) {
        final level = _computePeakLevel(waveformRight, samplesPerPeak);
        rightLevels.add(level);
        if (level.length < 10) break;
      }
    }

    return MultiResWaveform(
      leftLevels: leftLevels,
      rightLevels: rightLevels,
      totalSamples: totalSamples,
      sampleRate: sampleRate,
    );
  }

  /// Compute min/max peaks for a single LOD level
  PeakLevel _computePeakLevel(Float32List samples, int samplesPerPeak) {
    final numPeaks = (samples.length / samplesPerPeak).ceil();
    final minPeaks = Float32List(numPeaks);
    final maxPeaks = Float32List(numPeaks);

    for (int i = 0; i < numPeaks; i++) {
      final start = i * samplesPerPeak;
      final end = math.min(start + samplesPerPeak, samples.length);

      double minVal = samples[start];
      double maxVal = minVal;

      for (int j = start + 1; j < end; j++) {
        final s = samples[j];
        if (s < minVal) minVal = s;
        if (s > maxVal) maxVal = s;
      }

      minPeaks[i] = minVal;
      maxPeaks[i] = maxVal;
    }

    return PeakLevel(
      minPeaks: minPeaks,
      maxPeaks: maxPeaks,
      samplesPerPeak: samplesPerPeak,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LEGACY API (for backward compatibility)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get cached waveform data for a clip
  /// Returns null if not cached - caller should compute and add
  UltimateWaveformData? get(String clipId) {
    final cached = _cache[clipId];
    if (cached != null) {
      // Move to end (LRU)
      _cache.remove(clipId);
      _cache[clipId] = cached;
      return cached.data;
    }
    return null;
  }

  /// Check if clip is cached
  bool has(String clipId) => _cache.containsKey(clipId);

  /// Add waveform data to cache
  void put(String clipId, UltimateWaveformData data) {
    // Evict oldest if at capacity
    while (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[clipId] = _CachedWaveform(data);
  }

  /// Remove specific clip from cache
  void remove(String clipId) {
    _cache.remove(clipId);
    final removed = _multiResCache.remove(clipId);
    if (removed != null) {
      _multiResTotalBytes -= _estimateBytes(removed);
      if (_multiResTotalBytes < 0) _multiResTotalBytes = 0;
    }
  }

  /// Clear entire cache
  void clear() {
    _cache.clear();
    _multiResCache.clear();
    _multiResTotalBytes = 0;
  }

  /// Compute and cache waveform data from raw samples
  /// This is the main entry point - handles all optimization internally
  UltimateWaveformData getOrCompute(
    String clipId,
    Float32List waveform,
    Float32List? waveformRight,
  ) {
    // Check cache first
    final cached = get(clipId);
    if (cached != null) return cached;

    // Compute optimized waveform data
    final data = _computeWaveformData(waveform, waveformRight);

    // Cache it
    put(clipId, data);

    return data;
  }

  /// Internal: compute optimized waveform data with downsampling
  UltimateWaveformData _computeWaveformData(
    Float32List waveform,
    Float32List? waveformRight,
  ) {
    if (waveform.isEmpty) {
      return UltimateWaveformData.empty();
    }

    final waveformLength = waveform.length;
    List<double> leftSamples;
    List<double>? rightSamples;

    if (waveformLength > _maxSamplesPerClip) {
      // Fast downsampling with min/max preservation
      final step = waveformLength ~/ _maxSamplesPerClip;
      if (step == 0) {
        leftSamples = waveform.map((s) => s.toDouble()).toList();
      } else {
        leftSamples = List<double>.filled(_maxSamplesPerClip, 0);
        for (int i = 0; i < _maxSamplesPerClip; i++) {
          final start = i * step;
          if (start >= waveformLength) break;
          final end = (start + step).clamp(0, waveformLength);
          double minVal = waveform[start];
          double maxVal = minVal;
          for (int j = start + 1; j < end; j++) {
            final s = waveform[j];
            if (s < minVal) minVal = s;
            else if (s > maxVal) maxVal = s;
          }
          // Alternate min/max for accurate representation
          leftSamples[i] = i.isEven ? minVal.toDouble() : maxVal.toDouble();
        }
      }

      // Right channel
      if (waveformRight != null && waveformRight.isNotEmpty) {
        final rightLength = waveformRight.length;
        final rightStep = rightLength ~/ _maxSamplesPerClip;
        if (rightStep == 0) {
          rightSamples = waveformRight.map((s) => s.toDouble()).toList();
        } else {
          rightSamples = List<double>.filled(_maxSamplesPerClip, 0);
          for (int i = 0; i < _maxSamplesPerClip; i++) {
            final start = i * rightStep;
            if (start >= rightLength) break;
            final end = (start + rightStep).clamp(0, rightLength);
            double minVal = waveformRight[start];
            double maxVal = minVal;
            for (int j = start + 1; j < end; j++) {
              final s = waveformRight[j];
              if (s < minVal) minVal = s;
              else if (s > maxVal) maxVal = s;
            }
            rightSamples[i] = i.isEven ? minVal.toDouble() : maxVal.toDouble();
          }
        }
      }
    } else {
      leftSamples = waveform.map((s) => s.toDouble()).toList();
      rightSamples = waveformRight?.map((s) => s.toDouble()).toList();
    }

    // Use fast factory for timeline clips (1 LOD level only)
    return UltimateWaveformData.fromSamples(
      leftSamples,
      rightChannelSamples: rightSamples,
      sampleRate: 48000,
      maxSamples: _maxSamplesPerClip,
    );
  }

  /// Get cache statistics for debugging
  Map<String, dynamic> get stats => {
    'legacySize': _cache.length,
    'multiResSize': _multiResCache.length,
    'maxSize': _maxCacheSize,
    'legacyClipIds': _cache.keys.toList(),
    'multiResClipIds': _multiResCache.keys.toList(),
  };
}

/// Internal cached waveform entry
class _CachedWaveform {
  final UltimateWaveformData data;
  final DateTime createdAt;

  _CachedWaveform(this.data) : createdAt = DateTime.now();
}

// ═══════════════════════════════════════════════════════════════════════════════
// TILE-BASED WAVEFORM CACHE (Cubase instant zoom)
// ═══════════════════════════════════════════════════════════════════════════════

/// Tile key for LRU cache
class WaveformTileKey {
  final int clipId;
  final int tileX; // Tile index at current zoom
  final int zoomLevel; // Quantized zoom level (prevents cache explosion)

  const WaveformTileKey(this.clipId, this.tileX, this.zoomLevel);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveformTileKey &&
          clipId == other.clipId &&
          tileX == other.tileX &&
          zoomLevel == other.zoomLevel;

  @override
  int get hashCode => Object.hash(clipId, tileX, zoomLevel);

  @override
  String toString() => 'Tile($clipId, x=$tileX, z=$zoomLevel)';
}

/// Cached tile data (min/max/rms per pixel column)
class WaveformTileData {
  final Float32List mins;
  final Float32List maxs;
  final Float32List rms;
  final int startFrame;
  final int endFrame;

  const WaveformTileData({
    required this.mins,
    required this.maxs,
    required this.rms,
    required this.startFrame,
    required this.endFrame,
  });

  bool get isEmpty => mins.isEmpty;
  int get pixelCount => mins.length;
}

/// Tile-based waveform cache for instant zoom
/// Uses LRU eviction and quantized zoom levels
class WaveformTileCache {
  static final WaveformTileCache _instance = WaveformTileCache._internal();
  factory WaveformTileCache() => _instance;
  WaveformTileCache._internal();

  /// Tile width in pixels
  static const int tileWidth = 256;

  /// Maximum number of tiles in cache
  static const int maxTiles = 2000;

  /// LRU cache: key -> tile data
  final LinkedHashMap<WaveformTileKey, WaveformTileData> _tiles = LinkedHashMap();

  /// Get tile from cache (moves to end for LRU)
  WaveformTileData? get(WaveformTileKey key) {
    final tile = _tiles[key];
    if (tile != null) {
      // Move to end (most recently used)
      _tiles.remove(key);
      _tiles[key] = tile;
    }
    return tile;
  }

  /// Put tile into cache with LRU eviction
  void put(WaveformTileKey key, WaveformTileData tile) {
    // Evict oldest if at capacity
    while (_tiles.length >= maxTiles) {
      _tiles.remove(_tiles.keys.first);
    }
    _tiles[key] = tile;
  }

  /// Check if tile is cached
  bool has(WaveformTileKey key) => _tiles.containsKey(key);

  /// Clear all tiles for a clip
  void clearClip(int clipId) {
    _tiles.removeWhere((key, _) => key.clipId == clipId);
  }

  /// Clear entire cache
  void clear() => _tiles.clear();

  /// Get cache stats
  Map<String, dynamic> get stats => {
    'tileCount': _tiles.length,
    'maxTiles': maxTiles,
  };

  /// Quantize zoom to prevent cache explosion
  /// Returns a level index (0-15) that groups similar zooms together
  static int quantizeZoom(double framesPerPixel) {
    // Log scale quantization: each level is 2x the previous
    // Level 0: framesPerPixel < 32
    // Level 1: 32-64
    // Level 2: 64-128
    // etc.
    if (framesPerPixel < 32) return 0;
    if (framesPerPixel < 64) return 1;
    if (framesPerPixel < 128) return 2;
    if (framesPerPixel < 256) return 3;
    if (framesPerPixel < 512) return 4;
    if (framesPerPixel < 1024) return 5;
    if (framesPerPixel < 2048) return 6;
    if (framesPerPixel < 4096) return 7;
    if (framesPerPixel < 8192) return 8;
    if (framesPerPixel < 16384) return 9;
    if (framesPerPixel < 32768) return 10;
    if (framesPerPixel < 65536) return 11;
    if (framesPerPixel < 131072) return 12;
    if (framesPerPixel < 262144) return 13;
    if (framesPerPixel < 524288) return 14;
    return 15;
  }

  /// Calculate tile parameters for a given view
  /// Returns (firstTileX, lastTileX, pixelOffsetInFirstTile)
  static (int, int, int) calculateTileRange({
    required int startFrame,
    required int endFrame,
    required double framesPerPixel,
  }) {
    final totalPixels = ((endFrame - startFrame) / framesPerPixel).ceil();
    final firstTileX = 0;
    final lastTileX = (totalPixels / tileWidth).ceil() - 1;
    return (firstTileX, math.max(0, lastTileX), 0);
  }
}
