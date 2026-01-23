/// Waveform Cache Service — Disk storage for waveform peak data
///
/// Provides fast disk caching for waveform visualization data.
/// Waveforms are expensive to compute (FFI call + audio decode),
/// so caching to disk significantly improves load times.
///
/// Storage location: ~/Library/Application Support/FluxForge Studio/waveform_cache/
/// File format: Binary (4-byte float per sample for compact storage)
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Service for caching waveform data to disk
class WaveformCacheService {
  // Singleton
  static final WaveformCacheService _instance = WaveformCacheService._();
  static WaveformCacheService get instance => _instance;

  WaveformCacheService._();

  // State
  String? _cacheDirectory;
  bool _initialized = false;

  // In-memory LRU cache (hot cache)
  // P1.4 FIX: Use LinkedHashSet for O(1) remove instead of List O(n)
  // P1.9 FIX: Store as Float32List internally (50% memory savings)
  final Map<String, Float32List> _memoryCache = {};
  final LinkedHashSet<String> _lruOrder = LinkedHashSet<String>();
  static const int maxMemoryCacheSize = 100; // Max waveforms in memory

  /// P2.15 FIX: Maximum waveform samples to store (downsampled for 95% memory reduction)
  /// UI displays waveforms at most ~2048 pixels wide, so 2048 peak values is sufficient
  static const int maxWaveformSamples = 2048;

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.2 FIX: Disk cache quota (2GB limit)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Maximum disk cache size in bytes (2GB)
  static const int maxDiskCacheBytes = 2 * 1024 * 1024 * 1024;

  /// Target size after cleanup (80% of max = 1.6GB to avoid constant eviction)
  static const int targetDiskCacheBytes = 1717986918; // 1.6 GB (80% of 2GB)

  /// Disk LRU tracking - maps cache key to last access time
  final Map<String, DateTime> _diskLruMap = {};

  /// Current estimated disk cache size (updated on put/remove)
  int _estimatedDiskSize = 0;

  /// Flag to prevent concurrent cleanup operations
  bool _isCleaningDisk = false;

  // Statistics
  int _diskHits = 0;
  int _diskMisses = 0;
  int _memoryHits = 0;
  int _diskEvictions = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize cache directory
  Future<void> init() async {
    if (_initialized) return;

    try {
      _cacheDirectory = await _getCacheDirectory();
      _initialized = true;

      // P0.2: Load existing disk cache metadata for LRU tracking
      await _loadDiskCacheMetadata();

      debugPrint('[WaveformCache] Initialized: $_cacheDirectory '
          '(${(_estimatedDiskSize / 1024 / 1024).toStringAsFixed(1)} MB, '
          '${_diskLruMap.length} files)');
    } catch (e) {
      debugPrint('[WaveformCache] Init failed: $e');
    }
  }

  /// P0.2: Load existing disk cache metadata for quota enforcement
  Future<void> _loadDiskCacheMetadata() async {
    if (_cacheDirectory == null) return;

    _diskLruMap.clear();
    _estimatedDiskSize = 0;

    try {
      final dir = Directory(_cacheDirectory!);
      if (!await dir.exists()) return;

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.wfm')) {
          final stat = await entity.stat();
          final key = p.basenameWithoutExtension(entity.path);
          _diskLruMap[key] = stat.accessed;
          _estimatedDiskSize += stat.size;
        }
      }

      // Check if we're over quota and cleanup if needed
      if (_estimatedDiskSize > maxDiskCacheBytes) {
        debugPrint('[WaveformCache] Over quota on init: '
            '${(_estimatedDiskSize / 1024 / 1024 / 1024).toStringAsFixed(2)} GB > '
            '${(maxDiskCacheBytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB');
        await _enforceDiskQuota();
      }
    } catch (e) {
      debugPrint('[WaveformCache] Metadata load error: $e');
    }
  }

  /// Get cache directory path
  Future<String> _getCacheDirectory() async {
    String basePath;
    if (Platform.isMacOS) {
      basePath = '${Platform.environment['HOME']}/Library/Application Support/FluxForge Studio';
    } else if (Platform.isWindows) {
      basePath = '${Platform.environment['APPDATA']}/FluxForge Studio';
    } else {
      basePath = '${Platform.environment['HOME']}/.config/fluxforge-studio';
    }

    final cacheDir = p.join(basePath, 'waveform_cache');

    // Create directory if it doesn't exist
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      debugPrint('[WaveformCache] Created cache directory: $cacheDir');
    }

    return cacheDir;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CACHE KEY GENERATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate cache key from audio path
  /// Uses MD5 hash of path for safe filename
  String _getCacheKey(String audioPath) {
    final bytes = utf8.encode(audioPath);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// Get cache file path for an audio path
  String _getCacheFilePath(String audioPath) {
    final key = _getCacheKey(audioPath);
    return p.join(_cacheDirectory!, '$key.wfm');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GET / PUT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get waveform from cache (memory first, then disk)
  /// P1.9: Internal storage is `Float32List`, returns `List<double>` for API compatibility
  Future<List<double>?> get(String audioPath) async {
    if (!_initialized) await init();
    if (_cacheDirectory == null) return null;

    // Check memory cache first
    if (_memoryCache.containsKey(audioPath)) {
      _memoryHits++;
      _touchLru(audioPath);
      // P1.9: Convert Float32List to List<double> only on retrieval (lazy conversion)
      final cached = _memoryCache[audioPath];
      if (cached != null) {
        return List<double>.from(cached);
      }
      return null;
    }

    // Check disk cache
    try {
      final filePath = _getCacheFilePath(audioPath);
      final file = File(filePath);

      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final waveform = _bytesToWaveformFloat32(bytes);

        if (waveform.isNotEmpty) {
          _diskHits++;
          // Add to memory cache (as Float32List)
          _putMemoryFloat32(audioPath, waveform);
          debugPrint('[WaveformCache] Disk hit: $audioPath (${waveform.length} samples)');
          // Return as List<double> for API compatibility
          return List<double>.from(waveform);
        }
      }
    } catch (e) {
      debugPrint('[WaveformCache] Read error: $e');
    }

    _diskMisses++;
    return null;
  }

  /// Check if waveform exists in cache (sync, memory only)
  bool containsKey(String audioPath) {
    return _memoryCache.containsKey(audioPath);
  }

  /// Check if waveform exists in disk cache
  Future<bool> existsOnDisk(String audioPath) async {
    if (!_initialized) await init();
    if (_cacheDirectory == null) return false;

    try {
      final filePath = _getCacheFilePath(audioPath);
      return await File(filePath).exists();
    } catch (_) {
      return false;
    }
  }

  /// Put waveform into cache (memory + disk)
  /// P2.15: Automatically downsamples large waveforms for 95% memory reduction
  Future<void> put(String audioPath, List<double> waveform) async {
    if (!_initialized) await init();
    if (_cacheDirectory == null || waveform.isEmpty) return;

    // P2.15 FIX: Downsample large waveforms to maxWaveformSamples
    final downsampledWaveform = _downsampleWaveform(waveform);

    // Add to memory cache (downsampled)
    _putMemory(audioPath, downsampledWaveform);

    // Save to disk with quota enforcement (downsampled)
    try {
      final filePath = _getCacheFilePath(audioPath);
      final bytes = _waveformToBytes(downsampledWaveform);
      final key = _getCacheKey(audioPath);

      // P0.2: Check if adding this file would exceed quota
      final fileSize = bytes.length;
      if (_estimatedDiskSize + fileSize > maxDiskCacheBytes) {
        // Need to make room - run cleanup asynchronously
        await _enforceDiskQuota(additionalBytesNeeded: fileSize);
      }

      await File(filePath).writeAsBytes(bytes);

      // Update LRU tracking
      _diskLruMap[key] = DateTime.now();
      _estimatedDiskSize += fileSize;

      debugPrint('[WaveformCache] Saved: $audioPath '
          '(${waveform.length} samples, ${(fileSize / 1024).toStringAsFixed(1)} KB, '
          'total: ${(_estimatedDiskSize / 1024 / 1024).toStringAsFixed(1)} MB)');
    } catch (e) {
      debugPrint('[WaveformCache] Write error: $e');
    }
  }

  /// P0.2: Enforce disk quota by evicting oldest files
  Future<void> _enforceDiskQuota({int additionalBytesNeeded = 0}) async {
    if (_isCleaningDisk || _cacheDirectory == null) return;
    _isCleaningDisk = true;

    try {
      final targetSize = targetDiskCacheBytes - additionalBytesNeeded;

      if (_estimatedDiskSize <= targetSize) {
        _isCleaningDisk = false;
        return;
      }

      debugPrint('[WaveformCache] Enforcing quota: '
          '${(_estimatedDiskSize / 1024 / 1024).toStringAsFixed(1)} MB → '
          '${(targetSize / 1024 / 1024).toStringAsFixed(1)} MB');

      // Sort by access time (oldest first)
      final sortedEntries = _diskLruMap.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      int freedBytes = 0;
      int evictedCount = 0;

      for (final entry in sortedEntries) {
        if (_estimatedDiskSize - freedBytes <= targetSize) break;

        final filePath = p.join(_cacheDirectory!, '${entry.key}.wfm');
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final stat = await file.stat();
            await file.delete();
            freedBytes += stat.size;
            evictedCount++;
            _diskLruMap.remove(entry.key);
          }
        } catch (e) {
          debugPrint('[WaveformCache] Eviction error for ${entry.key}: $e');
        }
      }

      _estimatedDiskSize -= freedBytes;
      _diskEvictions += evictedCount;

      debugPrint('[WaveformCache] Evicted $evictedCount files, '
          'freed ${(freedBytes / 1024 / 1024).toStringAsFixed(1)} MB, '
          'now: ${(_estimatedDiskSize / 1024 / 1024).toStringAsFixed(1)} MB');
    } finally {
      _isCleaningDisk = false;
    }
  }

  /// Put waveform into memory cache only (for sync access)
  /// P1.4 FIX: Use `LinkedHashSet` O(1) operations instead of `List` O(n)
  /// P1.9: Accepts `List<double>` and converts to `Float32List` for storage
  void _putMemory(String audioPath, List<double> waveform) {
    final float32 = Float32List.fromList(waveform.map((v) => v.toDouble()).toList());
    _putMemoryFloat32(audioPath, float32);
  }

  /// P1.9: Put Float32List directly into memory cache (no conversion)
  void _putMemoryFloat32(String audioPath, Float32List waveform) {
    // Evict oldest if at capacity
    while (_lruOrder.length >= maxMemoryCacheSize) {
      // LinkedHashSet.first is O(1), remove is O(1)
      final oldest = _lruOrder.first;
      _lruOrder.remove(oldest);
      _memoryCache.remove(oldest);
    }

    _memoryCache[audioPath] = waveform;
    _touchLru(audioPath);
  }

  /// Update LRU order
  /// P1.4 FIX: LinkedHashSet.remove() and add() are both O(1)
  void _touchLru(String audioPath) {
    _lruOrder.remove(audioPath);  // O(1) with LinkedHashSet
    _lruOrder.add(audioPath);     // O(1) - adds to end, maintains insertion order
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.15 WAVEFORM DOWNSAMPLING
  // ═══════════════════════════════════════════════════════════════════════════

  /// P2.15: Downsample waveform to maxWaveformSamples using peak detection
  /// Preserves visual fidelity by keeping min/max peaks per bucket
  /// 48000 samples (1s @ 48kHz) → 2048 samples = 95% memory reduction
  List<double> _downsampleWaveform(List<double> waveform) {
    if (waveform.length <= maxWaveformSamples) {
      return waveform; // Already small enough
    }

    final result = <double>[];
    final bucketSize = waveform.length / maxWaveformSamples;

    for (int i = 0; i < maxWaveformSamples; i++) {
      final start = (i * bucketSize).floor();
      final end = ((i + 1) * bucketSize).floor().clamp(start + 1, waveform.length);

      // Find min and max in this bucket
      double minVal = waveform[start];
      double maxVal = waveform[start];
      for (int j = start + 1; j < end; j++) {
        if (waveform[j] < minVal) minVal = waveform[j];
        if (waveform[j] > maxVal) maxVal = waveform[j];
      }

      // Store the value with larger absolute magnitude (preserves peaks)
      result.add(minVal.abs() > maxVal.abs() ? minVal : maxVal);
    }

    debugPrint('[WaveformCache] P2.15: Downsampled ${waveform.length} → ${result.length} samples '
        '(${((1 - result.length / waveform.length) * 100).toStringAsFixed(1)}% reduction)');

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BINARY CONVERSION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convert waveform to bytes (Float32 array)
  Uint8List _waveformToBytes(List<double> waveform) {
    final floatList = Float32List.fromList(waveform.map((v) => v.toDouble()).toList());
    return floatList.buffer.asUint8List();
  }

  /// Convert bytes to waveform (legacy, returns `List<double>`)
  List<double> _bytesToWaveform(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length % 4 != 0) return [];

    final floatList = Float32List.view(bytes.buffer);
    return floatList.map((v) => v.toDouble()).toList();
  }

  /// P1.9: Convert bytes to Float32List (no double conversion, zero-copy view)
  Float32List _bytesToWaveformFloat32(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length % 4 != 0) return Float32List(0);
    // Zero-copy view of the byte buffer as Float32
    return Float32List.view(bytes.buffer);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CACHE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Clear all caches (memory + disk)
  Future<void> clearAll() async {
    // Clear memory
    _memoryCache.clear();
    _lruOrder.clear();

    // Clear disk
    if (_cacheDirectory != null) {
      try {
        final dir = Directory(_cacheDirectory!);
        if (await dir.exists()) {
          await for (final entity in dir.list()) {
            if (entity is File && entity.path.endsWith('.wfm')) {
              await entity.delete();
            }
          }
        }
        debugPrint('[WaveformCache] Cleared all cache');
      } catch (e) {
        debugPrint('[WaveformCache] Clear error: $e');
      }
    }

    // P0.2: Clear disk LRU tracking
    _diskLruMap.clear();
    _estimatedDiskSize = 0;

    _diskHits = 0;
    _diskMisses = 0;
    _memoryHits = 0;
    _diskEvictions = 0;
  }

  /// Clear memory cache only
  void clearMemory() {
    _memoryCache.clear();
    _lruOrder.clear();
    _memoryHits = 0;
    debugPrint('[WaveformCache] Cleared memory cache');
  }

  /// Remove specific entry from cache
  Future<void> remove(String audioPath) async {
    _memoryCache.remove(audioPath);
    _lruOrder.remove(audioPath);

    if (_cacheDirectory != null) {
      try {
        final filePath = _getCacheFilePath(audioPath);
        final key = _getCacheKey(audioPath);
        final file = File(filePath);
        if (await file.exists()) {
          // P0.2: Update disk tracking before delete
          final stat = await file.stat();
          await file.delete();
          _diskLruMap.remove(key);
          _estimatedDiskSize -= stat.size;
        }
      } catch (e) {
        debugPrint('[WaveformCache] Remove error: $e');
      }
    }
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    return {
      'memorySize': _memoryCache.length,
      'memoryHits': _memoryHits,
      'diskHits': _diskHits,
      'diskMisses': _diskMisses,
      'diskEvictions': _diskEvictions,
      'diskSizeBytes': _estimatedDiskSize,
      'diskSizeMB': (_estimatedDiskSize / 1024 / 1024).toStringAsFixed(1),
      'diskQuotaMB': (maxDiskCacheBytes / 1024 / 1024).toStringAsFixed(0),
      'diskUsagePercent': maxDiskCacheBytes > 0
          ? ((_estimatedDiskSize / maxDiskCacheBytes) * 100).toStringAsFixed(1)
          : '0.0',
      'hitRate': _diskHits + _diskMisses > 0
          ? (_diskHits / (_diskHits + _diskMisses) * 100).toStringAsFixed(1)
          : '0.0',
    };
  }

  /// Get disk cache size in bytes
  Future<int> getDiskCacheSize() async {
    if (_cacheDirectory == null) return 0;

    int totalSize = 0;
    try {
      final dir = Directory(_cacheDirectory!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.wfm')) {
            totalSize += await entity.length();
          }
        }
      }
    } catch (e) {
      debugPrint('[WaveformCache] Size calc error: $e');
    }
    return totalSize;
  }

  /// Get number of cached waveforms on disk
  Future<int> getDiskCacheCount() async {
    if (_cacheDirectory == null) return 0;

    int count = 0;
    try {
      final dir = Directory(_cacheDirectory!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.wfm')) {
            count++;
          }
        }
      }
    } catch (e) {
      debugPrint('[WaveformCache] Count error: $e');
    }
    return count;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BULK OPERATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Preload waveforms for a list of audio paths
  Future<void> preload(List<String> audioPaths) async {
    if (!_initialized) await init();

    int loaded = 0;
    for (final path in audioPaths) {
      if (!_memoryCache.containsKey(path)) {
        final waveform = await get(path);
        if (waveform != null) loaded++;
      }
    }

    debugPrint('[WaveformCache] Preloaded $loaded/${audioPaths.length} waveforms');
  }

  /// Export memory cache to provider format
  /// P1.9: Converts `Float32List` back to `List<double>` for API compatibility
  Map<String, List<double>> exportMemoryCache() {
    final result = <String, List<double>>{};
    for (final entry in _memoryCache.entries) {
      result[entry.key] = List<double>.from(entry.value);
    }
    return result;
  }

  /// Import waveforms from provider cache
  Future<void> importFromProvider(Map<String, List<double>> providerCache) async {
    if (!_initialized) await init();

    int saved = 0;
    for (final entry in providerCache.entries) {
      if (entry.value.isNotEmpty) {
        await put(entry.key, entry.value);
        saved++;
      }
    }

    debugPrint('[WaveformCache] Imported $saved waveforms from provider');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GETTERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool get initialized => _initialized;
  String? get cacheDirectory => _cacheDirectory;
  int get memoryCacheSize => _memoryCache.length;
}
