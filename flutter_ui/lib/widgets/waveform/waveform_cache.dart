/// Waveform Texture Cache System
///
/// Caches rendered waveforms as ui.Image textures for instant re-rendering.
/// Implements LRU eviction with configurable memory limits.
///
/// Performance boost: 10-100x faster than re-rendering every frame.

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CACHE ENTRY
// ═══════════════════════════════════════════════════════════════════════════

class _WaveformCacheEntry {
  final ui.Image image;
  final int sizeBytes;
  final DateTime lastAccessed;

  _WaveformCacheEntry({
    required this.image,
    required this.sizeBytes,
    required this.lastAccessed,
  });

  _WaveformCacheEntry touch() {
    return _WaveformCacheEntry(
      image: image,
      sizeBytes: sizeBytes,
      lastAccessed: DateTime.now(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CACHE KEY
// ═══════════════════════════════════════════════════════════════════════════

/// Cache key for unique waveform identity
class WaveformCacheKey {
  final String clipId;
  final int width;
  final int height;
  final double zoom;
  final int lodLevel;
  final bool isStereo;
  final int style; // WaveformStyle.index

  const WaveformCacheKey({
    required this.clipId,
    required this.width,
    required this.height,
    required this.zoom,
    required this.lodLevel,
    required this.isStereo,
    required this.style,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaveformCacheKey &&
          runtimeType == other.runtimeType &&
          clipId == other.clipId &&
          width == other.width &&
          height == other.height &&
          zoom == other.zoom &&
          lodLevel == other.lodLevel &&
          isStereo == other.isStereo &&
          style == other.style;

  @override
  int get hashCode =>
      clipId.hashCode ^
      width.hashCode ^
      height.hashCode ^
      zoom.hashCode ^
      lodLevel.hashCode ^
      isStereo.hashCode ^
      style.hashCode;

  @override
  String toString() =>
      'WaveformCacheKey($clipId, ${width}x$height, z$zoom, lod$lodLevel, stereo:$isStereo, style:$style)';
}

// ═══════════════════════════════════════════════════════════════════════════
// WAVEFORM TEXTURE CACHE (Singleton)
// ═══════════════════════════════════════════════════════════════════════════

class WaveformTextureCache {
  static final WaveformTextureCache _instance = WaveformTextureCache._();
  static WaveformTextureCache get instance => _instance;

  WaveformTextureCache._();

  /// Cache storage (LRU)
  final Map<WaveformCacheKey, _WaveformCacheEntry> _cache = {};

  /// Max cache size in bytes (default 100MB)
  int maxCacheSizeBytes = 100 * 1024 * 1024;

  /// Current cache size
  int _currentCacheSizeBytes = 0;

  /// Cache hit/miss stats
  int _hits = 0;
  int _misses = 0;

  /// Get cached image or null if not cached
  ui.Image? get(WaveformCacheKey key) {
    final entry = _cache[key];
    if (entry != null) {
      _cache[key] = entry.touch(); // Update access time
      _hits++;
      return entry.image;
    }
    _misses++;
    return null;
  }

  /// Put image in cache
  void put(WaveformCacheKey key, ui.Image image) {
    // Calculate image size (width * height * 4 bytes per pixel RGBA)
    final sizeBytes = image.width * image.height * 4;

    // Evict old entries if needed
    while (_currentCacheSizeBytes + sizeBytes > maxCacheSizeBytes && _cache.isNotEmpty) {
      _evictOldest();
    }

    // Add new entry
    _cache[key] = _WaveformCacheEntry(
      image: image,
      sizeBytes: sizeBytes,
      lastAccessed: DateTime.now(),
    );
    _currentCacheSizeBytes += sizeBytes;

  }

  /// Remove specific entry
  void remove(WaveformCacheKey key) {
    final entry = _cache.remove(key);
    if (entry != null) {
      _currentCacheSizeBytes -= entry.sizeBytes;
      entry.image.dispose();
    }
  }

  /// Invalidate all entries for a specific clip ID
  void invalidateClip(String clipId) {
    final keysToRemove = _cache.keys.where((k) => k.clipId == clipId).toList();
    for (final key in keysToRemove) {
      remove(key);
    }
  }

  /// Clear entire cache
  void clear() {
    for (final entry in _cache.values) {
      entry.image.dispose();
    }
    _cache.clear();
    _currentCacheSizeBytes = 0;
    _hits = 0;
    _misses = 0;
  }

  /// Evict oldest (LRU) entry
  void _evictOldest() {
    if (_cache.isEmpty) return;

    // Find oldest entry
    final oldest = _cache.entries.reduce(
      (a, b) => a.value.lastAccessed.isBefore(b.value.lastAccessed) ? a : b,
    );

    remove(oldest.key);
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    final total = _hits + _misses;
    final hitRate = total > 0 ? (_hits / total * 100) : 0;

    return {
      'entries': _cache.length,
      'size_bytes': _currentCacheSizeBytes,
      'size_formatted': _formatBytes(_currentCacheSizeBytes),
      'max_size_bytes': maxCacheSizeBytes,
      'max_size_formatted': _formatBytes(maxCacheSizeBytes),
      'usage_percent': ((_currentCacheSizeBytes / maxCacheSizeBytes) * 100).toStringAsFixed(1),
      'hits': _hits,
      'misses': _misses,
      'hit_rate_percent': hitRate.toStringAsFixed(1),
    };
  }

  /// Format bytes for human-readable output
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Print cache stats
  void printStats() {
    final stats = getStats();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CACHED WAVEFORM RENDERER
// ═══════════════════════════════════════════════════════════════════════════

/// Helper to render waveform to ui.Image texture
class WaveformTextureRenderer {
  /// Render waveform to texture
  static Future<ui.Image> renderToTexture({
    required CustomPainter painter,
    required Size size,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, size);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    picture.dispose();

    return image;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CACHED WAVEFORM WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Waveform widget with automatic texture caching
class CachedWaveform extends StatefulWidget {
  final WaveformCacheKey cacheKey;
  final CustomPainter painter;
  final Size size;

  const CachedWaveform({
    super.key,
    required this.cacheKey,
    required this.painter,
    required this.size,
  });

  @override
  State<CachedWaveform> createState() => _CachedWaveformState();
}

class _CachedWaveformState extends State<CachedWaveform> {
  ui.Image? _cachedImage;
  bool _isRendering = false;

  @override
  void initState() {
    super.initState();
    _loadOrRender();
  }

  @override
  void didUpdateWidget(CachedWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cacheKey != oldWidget.cacheKey) {
      _loadOrRender();
    }
  }

  Future<void> _loadOrRender() async {
    // Try cache first
    final cached = WaveformTextureCache.instance.get(widget.cacheKey);
    if (cached != null) {
      setState(() => _cachedImage = cached);
      return;
    }

    // Render to texture
    if (_isRendering) return;
    _isRendering = true;

    try {
      final image = await WaveformTextureRenderer.renderToTexture(
        painter: widget.painter,
        size: widget.size,
      );

      // Cache the result
      WaveformTextureCache.instance.put(widget.cacheKey, image);

      if (mounted) {
        setState(() => _cachedImage = image);
      }
    } finally {
      _isRendering = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedImage == null) {
      // First render: show placeholder or direct paint
      return CustomPaint(
        painter: widget.painter,
        size: widget.size,
      );
    }

    // Cached render: paint texture (10-100x faster!)
    return CustomPaint(
      painter: _CachedImagePainter(_cachedImage!),
      size: widget.size,
    );
  }

  @override
  void dispose() {
    // Don't dispose image - cache owns it
    super.dispose();
  }
}

/// Painter for cached image
class _CachedImagePainter extends CustomPainter {
  final ui.Image image;

  _CachedImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    // Paint cached texture (instant!)
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_CachedImagePainter oldDelegate) => image != oldDelegate.image;
}
