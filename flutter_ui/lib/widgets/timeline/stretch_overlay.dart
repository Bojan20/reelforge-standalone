/// Stretch Overlay Widget
///
/// Professional time stretch visualization for timeline clips:
/// - Color-coded stretch regions (cyan=compress, orange=expand)
/// - Flex/warp marker display with handles
/// - Transient markers
/// - Stretch ratio indicators
///
/// Visual style matches rf-viz/stretch_overlay.rs GPU renderer

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Stretch region for visualization
class StretchRegion {
  /// Start time relative to clip (seconds)
  final double startTime;
  /// End time relative to clip (seconds)
  final double endTime;
  /// Stretch ratio (1.0 = no stretch, <1.0 = compress, >1.0 = expand)
  final double ratio;

  const StretchRegion({
    required this.startTime,
    required this.endTime,
    required this.ratio,
  });

  /// Check if stretch is significant (not unity)
  bool get isSignificant => (ratio - 1.0).abs() > 0.01;
}

/// Flex marker type
enum FlexMarkerType {
  /// Auto-detected transient
  transient,
  /// User-placed warp marker
  warpMarker,
  /// Beat grid marker
  beatMarker,
  /// Anchor point (locked)
  anchor,
}

/// Flex marker for visualization
class FlexMarker {
  /// Time position relative to clip (seconds)
  final double time;
  /// Marker type
  final FlexMarkerType type;
  /// Detection confidence (0.0 - 1.0)
  final double confidence;
  /// Is marker selected
  final bool selected;
  /// Is marker locked
  final bool locked;

  const FlexMarker({
    required this.time,
    required this.type,
    this.confidence = 1.0,
    this.selected = false,
    this.locked = false,
  });
}

/// Stretch overlay data for a clip
class ClipStretchData {
  /// Stretch regions
  final List<StretchRegion> regions;
  /// Flex markers
  final List<FlexMarker> markers;
  /// Overall stretch factor
  final double overallStretch;
  /// Is clip being edited for stretch
  final bool isEditing;

  const ClipStretchData({
    this.regions = const [],
    this.markers = const [],
    this.overallStretch = 1.0,
    this.isEditing = false,
  });

  static const empty = ClipStretchData();

  bool get hasStretch => regions.isNotEmpty || (overallStretch - 1.0).abs() > 0.01;
}

// ═══════════════════════════════════════════════════════════════════════════
// STRETCH OVERLAY WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Stretch overlay widget for timeline clips
class StretchOverlay extends StatelessWidget {
  /// Stretch data
  final ClipStretchData data;

  /// Clip duration (seconds)
  final double duration;

  /// Zoom (pixels per second)
  final double zoom;

  /// Height of the overlay
  final double height;

  /// Called when marker is tapped
  final ValueChanged<FlexMarker>? onMarkerTap;

  /// Called when marker is moved
  final void Function(FlexMarker marker, double newTime)? onMarkerMove;

  /// Called when new warp marker is created (double-click)
  final ValueChanged<double>? onCreateMarker;

  /// Show transient markers
  final bool showTransients;

  /// Show stretch ratio labels
  final bool showRatioLabels;

  const StretchOverlay({
    super.key,
    required this.data,
    required this.duration,
    required this.zoom,
    this.height = 60,
    this.onMarkerTap,
    this.onMarkerMove,
    this.onCreateMarker,
    this.showTransients = true,
    this.showRatioLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!data.hasStretch && data.markers.isEmpty && !data.isEditing) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: height,
      child: GestureDetector(
        onDoubleTapDown: onCreateMarker != null
            ? (details) {
                final time = details.localPosition.dx / zoom;
                if (time >= 0 && time <= duration) {
                  onCreateMarker!(time);
                }
              }
            : null,
        child: CustomPaint(
          painter: _StretchOverlayPainter(
            data: data,
            duration: duration,
            zoom: zoom,
            showTransients: showTransients,
            showRatioLabels: showRatioLabels,
          ),
          size: Size(duration * zoom, height),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STRETCH OVERLAY PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _StretchOverlayPainter extends CustomPainter {
  final ClipStretchData data;
  final double duration;
  final double zoom;
  final bool showTransients;
  final bool showRatioLabels;

  _StretchOverlayPainter({
    required this.data,
    required this.duration,
    required this.zoom,
    required this.showTransients,
    required this.showRatioLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Draw stretch regions first (background)
    _drawStretchRegions(canvas, size);

    // Draw markers on top
    _drawMarkers(canvas, size);

    // Draw overall stretch indicator if significant
    if ((data.overallStretch - 1.0).abs() > 0.01) {
      _drawOverallStretchBadge(canvas, size);
    }
  }

  void _drawStretchRegions(Canvas canvas, Size size) {
    for (final region in data.regions) {
      if (!region.isSignificant) continue;

      final startX = (region.startTime / duration) * size.width;
      final endX = (region.endTime / duration) * size.width;
      final regionWidth = endX - startX;

      if (regionWidth < 1) continue;

      // Color based on stretch/compress
      final color = _getRegionColor(region.ratio);

      // Draw region rectangle
      final regionPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromLTWH(startX, 0, regionWidth, size.height),
        regionPaint,
      );

      // Draw top/bottom borders for visibility
      final borderPaint = Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      canvas.drawLine(
        Offset(startX, 0),
        Offset(endX, 0),
        borderPaint,
      );
      canvas.drawLine(
        Offset(startX, size.height),
        Offset(endX, size.height),
        borderPaint,
      );

      // Draw ratio label if enabled and region is wide enough
      if (showRatioLabels && regionWidth > 30) {
        _drawRatioLabel(canvas, startX, regionWidth, size.height, region.ratio);
      }
    }
  }

  Color _getRegionColor(double ratio) {
    if (ratio < 0.99) {
      // Compression - cyan/teal (matches rf-viz)
      final intensity = (1.0 - ratio).clamp(0.0, 1.0);
      return Color.lerp(
        FluxForgeTheme.accentCyan.withValues(alpha: 0.15),
        FluxForgeTheme.accentCyan.withValues(alpha: 0.4),
        intensity,
      )!;
    } else if (ratio > 1.01) {
      // Expansion - orange (matches rf-viz)
      final intensity = ((ratio - 1.0) * 2.0).clamp(0.0, 1.0);
      return Color.lerp(
        FluxForgeTheme.accentOrange.withValues(alpha: 0.15),
        FluxForgeTheme.accentOrange.withValues(alpha: 0.4),
        intensity,
      )!;
    } else {
      return Colors.transparent;
    }
  }

  void _drawRatioLabel(Canvas canvas, double x, double width, double height, double ratio) {
    final text = ratio < 1.0
        ? '${(ratio * 100).toStringAsFixed(0)}%'
        : '${(ratio * 100).toStringAsFixed(0)}%';

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: ratio < 1.0
              ? FluxForgeTheme.accentCyan
              : FluxForgeTheme.accentOrange,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFamily: 'JetBrains Mono',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Center in region
    final textX = x + (width - textPainter.width) / 2;
    final textY = (height - textPainter.height) / 2;

    // Background for readability
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(textX - 2, textY - 1, textPainter.width + 4, textPainter.height + 2),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      bgRect,
      Paint()..color = FluxForgeTheme.bgDeepest.withValues(alpha: 0.8),
    );

    textPainter.paint(canvas, Offset(textX, textY));
  }

  void _drawMarkers(Canvas canvas, Size size) {
    for (final marker in data.markers) {
      // Skip transients if not showing them
      if (marker.type == FlexMarkerType.transient && !showTransients) continue;

      final x = (marker.time / duration) * size.width;
      if (x < 0 || x > size.width) continue;

      final color = _getMarkerColor(marker);
      final lineWidth = _getMarkerWidth(marker);

      // Draw marker line
      final linePaint = Paint()
        ..color = color
        ..strokeWidth = lineWidth;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        linePaint,
      );

      // Draw handle/diamond at top for warp markers
      if (marker.type == FlexMarkerType.warpMarker ||
          marker.type == FlexMarkerType.anchor) {
        _drawMarkerHandle(canvas, x, color, marker);
      }

      // Draw triangle for transients (subtle)
      if (marker.type == FlexMarkerType.transient) {
        _drawTransientIndicator(canvas, x, size.height, color, marker.confidence);
      }
    }
  }

  Color _getMarkerColor(FlexMarker marker) {
    final baseAlpha = marker.selected ? 1.0 : (0.4 + marker.confidence * 0.4);

    switch (marker.type) {
      case FlexMarkerType.transient:
        return FluxForgeTheme.textTertiary.withValues(alpha: baseAlpha * 0.6);
      case FlexMarkerType.warpMarker:
        return marker.selected
            ? FluxForgeTheme.accentOrange
            : FluxForgeTheme.accentOrange.withValues(alpha: baseAlpha);
      case FlexMarkerType.beatMarker:
        return FluxForgeTheme.accentBlue.withValues(alpha: baseAlpha);
      case FlexMarkerType.anchor:
        return FluxForgeTheme.accentRed.withValues(alpha: baseAlpha);
    }
  }

  double _getMarkerWidth(FlexMarker marker) {
    final base = switch (marker.type) {
      FlexMarkerType.transient => 1.0,
      FlexMarkerType.warpMarker => 2.0,
      FlexMarkerType.beatMarker => 1.0,
      FlexMarkerType.anchor => 2.5,
    };
    return marker.selected ? base * 1.5 : base;
  }

  void _drawMarkerHandle(Canvas canvas, double x, Color color, FlexMarker marker) {
    final handlePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Diamond shape for warp markers, square for anchors
    final path = Path();
    final size = marker.selected ? 8.0 : 6.0;

    if (marker.type == FlexMarkerType.anchor) {
      // Square for anchor
      path.addRect(Rect.fromCenter(
        center: Offset(x, size / 2 + 2),
        width: size,
        height: size,
      ));

      // Lock icon (simplified)
      if (marker.locked) {
        canvas.drawCircle(
          Offset(x, size / 2 + 2),
          size * 0.3,
          Paint()..color = FluxForgeTheme.bgDeepest,
        );
      }
    } else {
      // Diamond for warp marker
      path.moveTo(x, 2);
      path.lineTo(x + size / 2, 2 + size / 2);
      path.lineTo(x, 2 + size);
      path.lineTo(x - size / 2, 2 + size / 2);
      path.close();
    }

    canvas.drawPath(path, handlePaint);

    // Border for selected
    if (marker.selected) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  void _drawTransientIndicator(Canvas canvas, double x, double height, Color color, double confidence) {
    // Small triangle at bottom indicating transient
    final triangleSize = 4.0 + confidence * 2.0;

    final path = Path()
      ..moveTo(x, height)
      ..lineTo(x - triangleSize / 2, height - triangleSize)
      ..lineTo(x + triangleSize / 2, height - triangleSize)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.3 + confidence * 0.3)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawOverallStretchBadge(Canvas canvas, Size size) {
    final isCompress = data.overallStretch < 1.0;
    final percentage = (data.overallStretch * 100).toStringAsFixed(0);
    final text = '$percentage%';
    final color = isCompress ? FluxForgeTheme.accentCyan : FluxForgeTheme.accentOrange;

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'JetBrains Mono',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // Position at top-right
    const padding = 4.0;
    final x = size.width - textPainter.width - padding - 4;
    final y = padding;

    // Background
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x - 4, y - 2, textPainter.width + 8, textPainter.height + 4),
      const Radius.circular(3),
    );

    canvas.drawRRect(
      bgRect,
      Paint()..color = color.withValues(alpha: 0.2),
    );
    canvas.drawRRect(
      bgRect,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    textPainter.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(_StretchOverlayPainter oldDelegate) =>
      data != oldDelegate.data ||
      duration != oldDelegate.duration ||
      zoom != oldDelegate.zoom ||
      showTransients != oldDelegate.showTransients ||
      showRatioLabels != oldDelegate.showRatioLabels;
}

// ═══════════════════════════════════════════════════════════════════════════
// STRETCH INDICATOR BADGE (for clip header)
// ═══════════════════════════════════════════════════════════════════════════

/// Compact stretch indicator badge for clip headers
class StretchIndicatorBadge extends StatelessWidget {
  final double stretchRatio;
  final VoidCallback? onTap;

  const StretchIndicatorBadge({
    super.key,
    required this.stretchRatio,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if ((stretchRatio - 1.0).abs() < 0.01) {
      return const SizedBox.shrink();
    }

    final isCompress = stretchRatio < 1.0;
    final color = isCompress ? FluxForgeTheme.accentCyan : FluxForgeTheme.accentOrange;
    final icon = isCompress ? Icons.compress : Icons.expand;
    final text = '${(stretchRatio * 100).toStringAsFixed(0)}%';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 2),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
