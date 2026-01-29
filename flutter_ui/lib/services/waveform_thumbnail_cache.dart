/// Waveform Thumbnail Cache (P2.5)
///
/// Lightweight 80x24px waveform thumbnails for file browsers.
///
/// Features:
/// - Fixed 80x24 pixel output (optimal for file list items)
/// - LRU cache with 500 entry limit
/// - Async generation with placeholder
/// - Uses existing Rust FFI for speed
///
/// Created: 2026-01-29
library;

import 'dart:collection';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../src/rust/native_ffi.dart';
import '../theme/fluxforge_theme.dart';

/// Thumbnail dimensions
const int kThumbnailWidth = 80;
const int kThumbnailHeight = 24;

/// Cached thumbnail data (min/max peaks for 80 columns)
class WaveformThumbnailData {
  /// Peak values (80 min/max pairs = 160 floats)
  final Float32List peaks;

  /// Is this a mono or stereo file
  final bool isStereo;

  /// Duration in seconds
  final double durationSeconds;

  const WaveformThumbnailData({
    required this.peaks,
    required this.isStereo,
    required this.durationSeconds,
  });

  /// Empty placeholder
  static WaveformThumbnailData empty() => WaveformThumbnailData(
        peaks: Float32List(kThumbnailWidth * 2),
        isStereo: false,
        durationSeconds: 0,
      );

  /// Get min/max pair at index
  (double min, double max) getPeakAt(int index) {
    if (index < 0 || index >= kThumbnailWidth) return (0, 0);
    return (peaks[index * 2], peaks[index * 2 + 1]);
  }
}

/// Singleton cache for waveform thumbnails
class WaveformThumbnailCache {
  static final WaveformThumbnailCache _instance =
      WaveformThumbnailCache._internal();
  factory WaveformThumbnailCache() => _instance;
  static WaveformThumbnailCache get instance => _instance;
  WaveformThumbnailCache._internal();

  /// Cache: file path → thumbnail data
  final LinkedHashMap<String, WaveformThumbnailData> _cache = LinkedHashMap();

  /// Pending generations (to avoid duplicate work)
  final Set<String> _pending = {};

  /// Maximum cache size
  static const int _maxCacheSize = 500;

  /// Get cached thumbnail (null if not cached)
  WaveformThumbnailData? get(String filePath) {
    final cached = _cache[filePath];
    if (cached != null) {
      // LRU: move to end
      _cache.remove(filePath);
      _cache[filePath] = cached;
    }
    return cached;
  }

  /// Check if thumbnail is cached
  bool has(String filePath) => _cache.containsKey(filePath);

  /// Check if generation is pending
  bool isPending(String filePath) => _pending.contains(filePath);

  /// Generate thumbnail (sync, uses Rust FFI)
  /// Returns null if file cannot be processed
  WaveformThumbnailData? generate(String filePath) {
    // Already cached?
    if (_cache.containsKey(filePath)) {
      return get(filePath);
    }

    // Mark as pending
    _pending.add(filePath);

    try {
      // Use existing FFI to get waveform data
      final cacheKey = 'thumb_${filePath.hashCode}';
      final json = NativeFFI.instance.generateWaveformFromFile(filePath, cacheKey);

      if (json == null) {
        _pending.remove(filePath);
        return null;
      }

      // Parse JSON and downsample to 80 points
      final thumbnail = _parseAndDownsample(json);

      if (thumbnail != null) {
        // Evict oldest if at capacity
        while (_cache.length >= _maxCacheSize) {
          _cache.remove(_cache.keys.first);
        }
        _cache[filePath] = thumbnail;
      }

      _pending.remove(filePath);
      return thumbnail;
    } catch (e) {
      _pending.remove(filePath);
      return null;
    }
  }

  /// Parse waveform JSON and downsample to 80 points
  WaveformThumbnailData? _parseAndDownsample(String json) {
    try {
      final Map<String, dynamic> data = jsonDecode(json);
      final int sampleRate = data['sample_rate'] ?? 48000;
      final int totalSamples = data['total_samples'] ?? 0;
      final int channels = data['channels'] ?? 1;
      final List<dynamic> lodLevels = data['lod_levels'] ?? [];

      if (lodLevels.isEmpty) return null;

      // Use the coarsest LOD level for thumbnails
      final level = lodLevels.last;
      final List<dynamic> leftBuckets = level['left'] ?? [];

      if (leftBuckets.isEmpty) return null;

      // Downsample to 80 points
      final peaks = Float32List(kThumbnailWidth * 2);
      final bucketCount = leftBuckets.length;
      final samplesPerPoint = (bucketCount / kThumbnailWidth).ceil();

      for (int i = 0; i < kThumbnailWidth; i++) {
        final start = i * samplesPerPoint;
        final end = ((i + 1) * samplesPerPoint).clamp(0, bucketCount);

        double minVal = 0;
        double maxVal = 0;

        for (int j = start; j < end && j < bucketCount; j++) {
          final bucket = leftBuckets[j];
          final bMin = (bucket['min'] as num?)?.toDouble() ?? 0;
          final bMax = (bucket['max'] as num?)?.toDouble() ?? 0;
          if (bMin < minVal) minVal = bMin;
          if (bMax > maxVal) maxVal = bMax;
        }

        peaks[i * 2] = minVal;
        peaks[i * 2 + 1] = maxVal;
      }

      final durationSeconds = totalSamples / sampleRate;

      return WaveformThumbnailData(
        peaks: peaks,
        isStereo: channels >= 2,
        durationSeconds: durationSeconds,
      );
    } catch (e) {
      return null;
    }
  }

  /// Remove from cache
  void remove(String filePath) {
    _cache.remove(filePath);
  }

  /// Clear all cache
  void clear() {
    _cache.clear();
    _pending.clear();
  }

  /// Cache stats
  Map<String, dynamic> get stats => {
        'size': _cache.length,
        'pending': _pending.length,
        'maxSize': _maxCacheSize,
      };
}

/// Waveform Thumbnail Widget (80x24px)
///
/// Usage:
/// ```dart
/// WaveformThumbnail(
///   filePath: '/path/to/audio.wav',
///   width: 80,
///   height: 24,
/// )
/// ```
class WaveformThumbnail extends StatefulWidget {
  /// Audio file path
  final String filePath;

  /// Widget width (default 80)
  final double width;

  /// Widget height (default 24)
  final double height;

  /// Waveform color
  final Color? color;

  /// Background color
  final Color? backgroundColor;

  const WaveformThumbnail({
    super.key,
    required this.filePath,
    this.width = 80,
    this.height = 24,
    this.color,
    this.backgroundColor,
  });

  @override
  State<WaveformThumbnail> createState() => _WaveformThumbnailState();
}

class _WaveformThumbnailState extends State<WaveformThumbnail> {
  WaveformThumbnailData? _data;
  bool _loading = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(WaveformThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _loadThumbnail();
    }
  }

  void _loadThumbnail() {
    final cache = WaveformThumbnailCache.instance;

    // Check cache first
    final cached = cache.get(widget.filePath);
    if (cached != null) {
      setState(() {
        _data = cached;
        _loading = false;
        _error = false;
      });
      return;
    }

    // Generate in background
    setState(() {
      _loading = true;
      _error = false;
    });

    // Use Future.microtask to not block UI
    Future.microtask(() {
      if (!mounted) return;

      final data = cache.generate(widget.filePath);

      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
          _error = data == null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? FluxForgeTheme.bgDeep;
    final waveColor = widget.color ?? FluxForgeTheme.accentBlue;

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(2),
      ),
      child: _loading
          ? _buildLoadingPlaceholder()
          : _error
              ? _buildErrorPlaceholder()
              : _data != null
                  ? CustomPaint(
                      size: Size(widget.width, widget.height),
                      painter: _WaveformThumbnailPainter(
                        data: _data!,
                        color: waveColor,
                      ),
                    )
                  : _buildEmptyPlaceholder(),
    );
  }

  Widget _buildLoadingPlaceholder() {
    return Center(
      child: SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation(FluxForgeTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Center(
      child: Icon(
        Icons.error_outline,
        size: 12,
        color: FluxForgeTheme.textSecondary,
      ),
    );
  }

  Widget _buildEmptyPlaceholder() {
    return Center(
      child: Icon(
        Icons.audio_file,
        size: 12,
        color: FluxForgeTheme.textSecondary,
      ),
    );
  }
}

/// Custom painter for waveform thumbnail
class _WaveformThumbnailPainter extends CustomPainter {
  final WaveformThumbnailData data;
  final Color color;

  _WaveformThumbnailPainter({
    required this.data,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.peaks.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final centerY = size.height / 2;
    final halfHeight = size.height / 2 - 1; // Leave 1px margin

    final path = Path();
    bool first = true;

    // Draw waveform as filled shape
    for (int i = 0; i < kThumbnailWidth; i++) {
      final x = (i / kThumbnailWidth) * size.width;
      final (minVal, maxVal) = data.getPeakAt(i);

      // Scale to widget height
      final yMin = centerY - (maxVal * halfHeight);
      final yMax = centerY - (minVal * halfHeight);

      if (first) {
        path.moveTo(x, yMin);
        first = false;
      } else {
        path.lineTo(x, yMin);
      }
    }

    // Draw bottom half (reversed)
    for (int i = kThumbnailWidth - 1; i >= 0; i--) {
      final x = (i / kThumbnailWidth) * size.width;
      final (minVal, _) = data.getPeakAt(i);
      final yMax = centerY - (minVal * halfHeight);
      path.lineTo(x, yMax);
    }

    path.close();

    // Fill with semi-transparent color
    final fillPaint = Paint()
      ..color = color.withAlpha(100)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Stroke outline
    canvas.drawPath(path, paint);

    // Draw center line
    final centerPaint = Paint()
      ..color = color.withAlpha(40)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(_WaveformThumbnailPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}
