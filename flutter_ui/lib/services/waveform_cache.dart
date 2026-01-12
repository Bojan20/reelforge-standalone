/// Global Waveform Cache with Multi-Resolution LOD
///
/// Cubase/Logic Pro style waveform caching:
/// - Pre-computed peak data at multiple zoom levels (mipmaps)
/// - Each level stores min/max pairs per window
/// - O(width) render time regardless of audio length
/// - LRU eviction for memory management
///
/// LOD Levels:
///   Level 0: 256 samples per peak
///   Level 1: 512 samples per peak
///   Level 2: 1024 samples per peak
///   Level 3: 2048 samples per peak
///   Level 4: 4096 samples per peak
///   Level 5: 8192 samples per peak
///
/// Zoom -> LOD mapping:
///   zoom > 500 px/sec  -> Level 0 (finest)
///   zoom 200-500       -> Level 1
///   zoom 50-200        -> Level 2
///   zoom 20-50         -> Level 3
///   zoom 5-20          -> Level 4
///   zoom < 5           -> Level 5 (coarsest)

import 'dart:typed_data';
import 'dart:collection';
import 'dart:math' as math;
import '../widgets/waveform/ultimate_waveform.dart';

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
  int getBestLodLevel(double zoom) {
    // Higher zoom = need finer detail = lower level index
    if (zoom > 500) return 0;
    if (zoom > 200) return math.min(1, leftLevels.length - 1);
    if (zoom > 50) return math.min(2, leftLevels.length - 1);
    if (zoom > 20) return math.min(3, leftLevels.length - 1);
    if (zoom > 5) return math.min(4, leftLevels.length - 1);
    return leftLevels.length - 1; // Coarsest
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

  /// Maximum cache size (number of clips)
  static const int _maxCacheSize = 100;

  /// Maximum samples to store per clip for legacy cache
  static const int _maxSamplesPerClip = 2000;

  /// LOD level configurations: samples per peak
  static const List<int> _lodSamplesPerPeak = [256, 512, 1024, 2048, 4096, 8192];

  // ═══════════════════════════════════════════════════════════════════════════
  // MULTI-RESOLUTION API (Cubase-style)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get or compute multi-resolution peaks for a clip
  /// This is the preferred API for zoom-instant rendering
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

    // Compute all LOD levels
    final data = _computeMultiResPeaks(waveform, waveformRight, sampleRate);

    // Evict oldest if at capacity
    while (_multiResCache.length >= _maxCacheSize) {
      _multiResCache.remove(_multiResCache.keys.first);
    }

    _multiResCache[clipId] = data;
    return data;
  }

  /// Check if multi-res data is cached
  bool hasMultiRes(String clipId) => _multiResCache.containsKey(clipId);

  /// Remove multi-res data from cache
  void removeMultiRes(String clipId) {
    _multiResCache.remove(clipId);
  }

  /// Clear multi-res cache
  void clearMultiRes() {
    _multiResCache.clear();
  }

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
    _multiResCache.remove(clipId);
  }

  /// Clear entire cache
  void clear() {
    _cache.clear();
    _multiResCache.clear();
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
