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
  final Map<String, List<double>> _memoryCache = {};
  final List<String> _lruOrder = [];
  static const int maxMemoryCacheSize = 100; // Max waveforms in memory

  // Statistics
  int _diskHits = 0;
  int _diskMisses = 0;
  int _memoryHits = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Initialize cache directory
  Future<void> init() async {
    if (_initialized) return;

    try {
      _cacheDirectory = await _getCacheDirectory();
      _initialized = true;
      debugPrint('[WaveformCache] Initialized: $_cacheDirectory');
    } catch (e) {
      debugPrint('[WaveformCache] Init failed: $e');
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
  Future<List<double>?> get(String audioPath) async {
    if (!_initialized) await init();
    if (_cacheDirectory == null) return null;

    // Check memory cache first
    if (_memoryCache.containsKey(audioPath)) {
      _memoryHits++;
      _touchLru(audioPath);
      return _memoryCache[audioPath];
    }

    // Check disk cache
    try {
      final filePath = _getCacheFilePath(audioPath);
      final file = File(filePath);

      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        final waveform = _bytesToWaveform(bytes);

        if (waveform.isNotEmpty) {
          _diskHits++;
          // Add to memory cache
          _putMemory(audioPath, waveform);
          debugPrint('[WaveformCache] Disk hit: $audioPath (${waveform.length} samples)');
          return waveform;
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
  Future<void> put(String audioPath, List<double> waveform) async {
    if (!_initialized) await init();
    if (_cacheDirectory == null || waveform.isEmpty) return;

    // Add to memory cache
    _putMemory(audioPath, waveform);

    // Save to disk asynchronously
    try {
      final filePath = _getCacheFilePath(audioPath);
      final bytes = _waveformToBytes(waveform);
      await File(filePath).writeAsBytes(bytes);
      debugPrint('[WaveformCache] Saved: $audioPath (${waveform.length} samples, ${bytes.length} bytes)');
    } catch (e) {
      debugPrint('[WaveformCache] Write error: $e');
    }
  }

  /// Put waveform into memory cache only (for sync access)
  void _putMemory(String audioPath, List<double> waveform) {
    // Evict oldest if at capacity
    while (_lruOrder.length >= maxMemoryCacheSize) {
      final oldest = _lruOrder.removeAt(0);
      _memoryCache.remove(oldest);
    }

    _memoryCache[audioPath] = waveform;
    _touchLru(audioPath);
  }

  /// Update LRU order
  void _touchLru(String audioPath) {
    _lruOrder.remove(audioPath);
    _lruOrder.add(audioPath);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BINARY CONVERSION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Convert waveform to bytes (Float32 array)
  Uint8List _waveformToBytes(List<double> waveform) {
    final floatList = Float32List.fromList(waveform.map((v) => v.toDouble()).toList());
    return floatList.buffer.asUint8List();
  }

  /// Convert bytes to waveform
  List<double> _bytesToWaveform(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length % 4 != 0) return [];

    final floatList = Float32List.view(bytes.buffer);
    return floatList.map((v) => v.toDouble()).toList();
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

    _diskHits = 0;
    _diskMisses = 0;
    _memoryHits = 0;
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
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
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
  Map<String, List<double>> exportMemoryCache() {
    return Map.from(_memoryCache);
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
