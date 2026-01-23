/// Waveform Trim Editor Widget (M3.2)
///
/// Professional waveform editing widget with:
/// - Draggable trim handles (start/end)
/// - Fade in/out curve handles
/// - Non-destructive editing (stores offsets)
/// - Right-click context menu
/// - Visual feedback during drag
///
/// Inspired by Pro Tools/Cubase clip editing.

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';
import '../waveform/waveform_painter.dart';

/// Callback for trim/fade changes
typedef TrimChangeCallback = void Function({
  double? trimStartMs,
  double? trimEndMs,
  double? fadeInMs,
  double? fadeOutMs,
});

/// Handle type for dragging
enum _HandleType {
  trimStart,
  trimEnd,
  fadeIn,
  fadeOut,
}

/// Waveform Trim Editor Widget
class WaveformTrimEditor extends StatefulWidget {
  /// Waveform data points
  final List<WaveformPoint> waveformData;

  /// Total duration of the audio in milliseconds
  final double durationMs;

  /// Current trim start position in milliseconds
  final double trimStartMs;

  /// Current trim end position in milliseconds (0 = no trim, use full length)
  final double trimEndMs;

  /// Fade in duration in milliseconds
  final double fadeInMs;

  /// Fade out duration in milliseconds
  final double fadeOutMs;

  /// Track/layer color
  final Color color;

  /// Height of the widget
  final double height;

  /// Callback when trim/fade values change
  final TrimChangeCallback? onChanged;

  /// Callback when editing starts (for undo grouping)
  final VoidCallback? onEditStart;

  /// Callback when editing ends (for undo grouping)
  final VoidCallback? onEditEnd;

  /// Whether editing is enabled
  final bool enabled;

  /// Show fade curve visualization
  final bool showFadeCurves;

  /// Minimum trim region width in milliseconds
  final double minTrimWidthMs;

  const WaveformTrimEditor({
    super.key,
    required this.waveformData,
    required this.durationMs,
    this.trimStartMs = 0.0,
    this.trimEndMs = 0.0,
    this.fadeInMs = 0.0,
    this.fadeOutMs = 0.0,
    this.color = const Color(0xFF4A9EFF),
    this.height = 80,
    this.onChanged,
    this.onEditStart,
    this.onEditEnd,
    this.enabled = true,
    this.showFadeCurves = true,
    this.minTrimWidthMs = 50.0,
  });

  @override
  State<WaveformTrimEditor> createState() => _WaveformTrimEditorState();
}

class _WaveformTrimEditorState extends State<WaveformTrimEditor> {
  _HandleType? _activeHandle;
  double _dragStartValue = 0;
  bool _isHoveringTrimStart = false;
  bool _isHoveringTrimEnd = false;
  bool _isHoveringFadeIn = false;
  bool _isHoveringFadeOut = false;

  /// Effective trim end (0 means use full duration)
  double get _effectiveTrimEndMs =>
      widget.trimEndMs > 0 ? widget.trimEndMs : widget.durationMs;

  /// Handle width for hit testing
  static const double _handleWidth = 12.0;

  /// Fade handle size
  static const double _fadeHandleSize = 10.0;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _getCursor(),
      onHover: _onHover,
      onExit: (_) => setState(() {
        _isHoveringTrimStart = false;
        _isHoveringTrimEnd = false;
        _isHoveringFadeIn = false;
        _isHoveringFadeOut = false;
      }),
      child: GestureDetector(
        onHorizontalDragStart: widget.enabled ? _onDragStart : null,
        onHorizontalDragUpdate: widget.enabled ? _onDragUpdate : null,
        onHorizontalDragEnd: widget.enabled ? _onDragEnd : null,
        onSecondaryTapDown: widget.enabled ? _showContextMenu : null,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _WaveformTrimPainter(
              waveformData: widget.waveformData,
              durationMs: widget.durationMs,
              trimStartMs: widget.trimStartMs,
              trimEndMs: _effectiveTrimEndMs,
              fadeInMs: widget.fadeInMs,
              fadeOutMs: widget.fadeOutMs,
              color: widget.color,
              showFadeCurves: widget.showFadeCurves,
              isHoveringTrimStart: _isHoveringTrimStart || _activeHandle == _HandleType.trimStart,
              isHoveringTrimEnd: _isHoveringTrimEnd || _activeHandle == _HandleType.trimEnd,
              isHoveringFadeIn: _isHoveringFadeIn || _activeHandle == _HandleType.fadeIn,
              isHoveringFadeOut: _isHoveringFadeOut || _activeHandle == _HandleType.fadeOut,
              enabled: widget.enabled,
            ),
            size: Size(double.infinity, widget.height),
          ),
        ),
      ),
    );
  }

  MouseCursor _getCursor() {
    if (!widget.enabled) return SystemMouseCursors.basic;

    if (_activeHandle != null) {
      return SystemMouseCursors.resizeColumn;
    }
    if (_isHoveringTrimStart || _isHoveringTrimEnd) {
      return SystemMouseCursors.resizeColumn;
    }
    if (_isHoveringFadeIn || _isHoveringFadeOut) {
      return SystemMouseCursors.resizeColumn;
    }
    return SystemMouseCursors.basic;
  }

  void _onHover(PointerHoverEvent event) {
    if (!widget.enabled) return;

    final box = context.findRenderObject() as RenderBox;
    final localX = event.localPosition.dx;
    final localY = event.localPosition.dy;
    final width = box.size.width;
    final height = box.size.height;

    // Calculate handle positions
    final trimStartX = (widget.trimStartMs / widget.durationMs) * width;
    final trimEndX = (_effectiveTrimEndMs / widget.durationMs) * width;

    // Fade handles are positioned at the top of the waveform
    final fadeInEndX = trimStartX + (widget.fadeInMs / widget.durationMs) * width;
    final fadeOutStartX = trimEndX - (widget.fadeOutMs / widget.durationMs) * width;

    setState(() {
      // Check trim handles
      _isHoveringTrimStart = (localX - trimStartX).abs() < _handleWidth;
      _isHoveringTrimEnd = (localX - trimEndX).abs() < _handleWidth;

      // Check fade handles (only in top portion)
      if (localY < height * 0.4) {
        _isHoveringFadeIn = !_isHoveringTrimStart &&
            localX > trimStartX &&
            (localX - fadeInEndX).abs() < _fadeHandleSize;
        _isHoveringFadeOut = !_isHoveringTrimEnd &&
            localX < trimEndX &&
            (localX - fadeOutStartX).abs() < _fadeHandleSize;
      } else {
        _isHoveringFadeIn = false;
        _isHoveringFadeOut = false;
      }
    });
  }

  void _onDragStart(DragStartDetails details) {
    final box = context.findRenderObject() as RenderBox;
    final localX = details.localPosition.dx;
    final localY = details.localPosition.dy;
    final width = box.size.width;
    final height = box.size.height;

    // Calculate positions
    final trimStartX = (widget.trimStartMs / widget.durationMs) * width;
    final trimEndX = (_effectiveTrimEndMs / widget.durationMs) * width;
    final fadeInEndX = trimStartX + (widget.fadeInMs / widget.durationMs) * width;
    final fadeOutStartX = trimEndX - (widget.fadeOutMs / widget.durationMs) * width;

    // Determine which handle is being dragged
    _HandleType? handle;

    // Priority: trim handles first
    if ((localX - trimStartX).abs() < _handleWidth) {
      handle = _HandleType.trimStart;
      _dragStartValue = widget.trimStartMs;
    } else if ((localX - trimEndX).abs() < _handleWidth) {
      handle = _HandleType.trimEnd;
      _dragStartValue = _effectiveTrimEndMs;
    } else if (localY < height * 0.4) {
      // Fade handles only in top portion
      if (localX > trimStartX && (localX - fadeInEndX).abs() < _fadeHandleSize) {
        handle = _HandleType.fadeIn;
        _dragStartValue = widget.fadeInMs;
      } else if (localX < trimEndX && (localX - fadeOutStartX).abs() < _fadeHandleSize) {
        handle = _HandleType.fadeOut;
        _dragStartValue = widget.fadeOutMs;
      }
    }

    if (handle != null) {
      setState(() => _activeHandle = handle);
      widget.onEditStart?.call();
      HapticFeedback.lightImpact();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_activeHandle == null) return;

    final box = context.findRenderObject() as RenderBox;
    final width = box.size.width;
    final deltaMs = (details.delta.dx / width) * widget.durationMs;

    switch (_activeHandle!) {
      case _HandleType.trimStart:
        final newTrimStart = (widget.trimStartMs + deltaMs)
            .clamp(0.0, _effectiveTrimEndMs - widget.minTrimWidthMs);
        widget.onChanged?.call(trimStartMs: newTrimStart);
        break;

      case _HandleType.trimEnd:
        final newTrimEnd = (_effectiveTrimEndMs + deltaMs)
            .clamp(widget.trimStartMs + widget.minTrimWidthMs, widget.durationMs);
        widget.onChanged?.call(trimEndMs: newTrimEnd);
        break;

      case _HandleType.fadeIn:
        final maxFadeIn = _effectiveTrimEndMs - widget.trimStartMs - widget.fadeOutMs;
        final newFadeIn = (widget.fadeInMs + deltaMs).clamp(0.0, maxFadeIn);
        widget.onChanged?.call(fadeInMs: newFadeIn);
        break;

      case _HandleType.fadeOut:
        final maxFadeOut = _effectiveTrimEndMs - widget.trimStartMs - widget.fadeInMs;
        final newFadeOut = (widget.fadeOutMs - deltaMs).clamp(0.0, maxFadeOut);
        widget.onChanged?.call(fadeOutMs: newFadeOut);
        break;
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (_activeHandle != null) {
      widget.onEditEnd?.call();
      HapticFeedback.mediumImpact();
    }
    setState(() => _activeHandle = null);
  }

  void _showContextMenu(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox;
    final globalPosition = box.localToGlobal(details.localPosition);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      items: [
        const PopupMenuItem(
          value: 'reset_trim',
          child: Row(
            children: [
              Icon(Icons.restore, size: 16),
              SizedBox(width: 8),
              Text('Reset Trim'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'reset_fades',
          child: Row(
            children: [
              Icon(Icons.show_chart, size: 16),
              SizedBox(width: 8),
              Text('Reset Fades'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'fade_in_100',
          child: Text('Fade In: 100ms'),
        ),
        const PopupMenuItem(
          value: 'fade_in_250',
          child: Text('Fade In: 250ms'),
        ),
        const PopupMenuItem(
          value: 'fade_out_100',
          child: Text('Fade Out: 100ms'),
        ),
        const PopupMenuItem(
          value: 'fade_out_250',
          child: Text('Fade Out: 250ms'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'trim_to_selection',
          child: Row(
            children: [
              Icon(Icons.content_cut, size: 16),
              SizedBox(width: 8),
              Text('Trim to Selection'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;

      widget.onEditStart?.call();

      switch (value) {
        case 'reset_trim':
          widget.onChanged?.call(trimStartMs: 0.0, trimEndMs: 0.0);
          break;
        case 'reset_fades':
          widget.onChanged?.call(fadeInMs: 0.0, fadeOutMs: 0.0);
          break;
        case 'fade_in_100':
          widget.onChanged?.call(fadeInMs: 100.0);
          break;
        case 'fade_in_250':
          widget.onChanged?.call(fadeInMs: 250.0);
          break;
        case 'fade_out_100':
          widget.onChanged?.call(fadeOutMs: 100.0);
          break;
        case 'fade_out_250':
          widget.onChanged?.call(fadeOutMs: 250.0);
          break;
        case 'trim_to_selection':
          // Keep current trim (no-op if no selection)
          break;
      }

      widget.onEditEnd?.call();
    });
  }
}

/// Custom painter for waveform with trim/fade visualization
class _WaveformTrimPainter extends CustomPainter {
  final List<WaveformPoint> waveformData;
  final double durationMs;
  final double trimStartMs;
  final double trimEndMs;
  final double fadeInMs;
  final double fadeOutMs;
  final Color color;
  final bool showFadeCurves;
  final bool isHoveringTrimStart;
  final bool isHoveringTrimEnd;
  final bool isHoveringFadeIn;
  final bool isHoveringFadeOut;
  final bool enabled;

  _WaveformTrimPainter({
    required this.waveformData,
    required this.durationMs,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.color,
    required this.showFadeCurves,
    required this.isHoveringTrimStart,
    required this.isHoveringTrimEnd,
    required this.isHoveringFadeIn,
    required this.isHoveringFadeOut,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty || durationMs <= 0) return;

    final centerY = size.height / 2;
    final halfHeight = size.height / 2 - 4;

    // Background
    final bgPaint = Paint()
      ..color = FluxForgeTheme.bgDeepest
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Calculate trim positions
    final trimStartX = (trimStartMs / durationMs) * size.width;
    final trimEndX = (trimEndMs / durationMs) * size.width;

    // Draw trimmed-out regions (dimmed)
    _drawTrimmedRegion(canvas, size, 0, trimStartX);
    _drawTrimmedRegion(canvas, size, trimEndX, size.width);

    // Draw active waveform region
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(trimStartX, 0, trimEndX, size.height));
    _drawWaveform(canvas, size, centerY, halfHeight);
    canvas.restore();

    // Draw fade curves
    if (showFadeCurves) {
      _drawFadeCurves(canvas, size, trimStartX, trimEndX);
    }

    // Draw trim handles
    _drawTrimHandle(canvas, size, trimStartX, true, isHoveringTrimStart);
    _drawTrimHandle(canvas, size, trimEndX, false, isHoveringTrimEnd);

    // Draw fade handles
    if (fadeInMs > 0 || isHoveringFadeIn) {
      final fadeInEndX = trimStartX + (fadeInMs / durationMs) * size.width;
      _drawFadeHandle(canvas, fadeInEndX, 12, isHoveringFadeIn);
    }
    if (fadeOutMs > 0 || isHoveringFadeOut) {
      final fadeOutStartX = trimEndX - (fadeOutMs / durationMs) * size.width;
      _drawFadeHandle(canvas, fadeOutStartX, 12, isHoveringFadeOut);
    }

    // Border
    final borderPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, borderPaint);
  }

  void _drawTrimmedRegion(Canvas canvas, Size size, double startX, double endX) {
    if (endX <= startX) return;

    final dimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTRB(startX, 0, endX, size.height), dimPaint);

    // Diagonal stripes pattern for trimmed regions
    final stripePaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    const spacing = 8.0;
    for (double x = startX; x < endX + size.height; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height, size.height),
        stripePaint,
      );
    }
  }

  void _drawWaveform(Canvas canvas, Size size, double centerY, double halfHeight) {
    if (waveformData.isEmpty) return;

    final samplesPerPixel = waveformData.length / size.width;
    final path = Path();
    bool firstPoint = true;

    // Draw max values
    for (double x = 0; x < size.width; x++) {
      final sampleIndex = (x * samplesPerPixel).floor();
      if (sampleIndex >= waveformData.length) break;

      final endIndex = math.min(sampleIndex + samplesPerPixel.ceil(), waveformData.length);
      double maxVal = -1;

      for (int i = sampleIndex; i < endIndex; i++) {
        maxVal = math.max(maxVal, waveformData[i].max);
      }

      final maxY = centerY - maxVal * halfHeight;
      if (firstPoint) {
        path.moveTo(x, maxY);
        firstPoint = false;
      } else {
        path.lineTo(x, maxY);
      }
    }

    // Draw min values (reverse)
    for (double x = size.width - 1; x >= 0; x--) {
      final sampleIndex = (x * samplesPerPixel).floor();
      if (sampleIndex >= waveformData.length) continue;

      final endIndex = math.min(sampleIndex + samplesPerPixel.ceil(), waveformData.length);
      double minVal = 1;

      for (int i = sampleIndex; i < endIndex; i++) {
        minVal = math.min(minVal, waveformData[i].min);
      }

      final minY = centerY - minVal * halfHeight;
      path.lineTo(x, minY);
    }

    path.close();

    // Fill
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, strokePaint);
  }

  void _drawFadeCurves(Canvas canvas, Size size, double trimStartX, double trimEndX) {
    // Fade in curve
    if (fadeInMs > 0) {
      final fadeInEndX = trimStartX + (fadeInMs / durationMs) * size.width;
      _drawFadeCurve(canvas, size, trimStartX, fadeInEndX, true);
    }

    // Fade out curve
    if (fadeOutMs > 0) {
      final fadeOutStartX = trimEndX - (fadeOutMs / durationMs) * size.width;
      _drawFadeCurve(canvas, size, fadeOutStartX, trimEndX, false);
    }
  }

  void _drawFadeCurve(Canvas canvas, Size size, double startX, double endX, bool isFadeIn) {
    final path = Path();
    const steps = 30;

    path.moveTo(startX, 0);

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = startX + (endX - startX) * t;

      // S-curve for natural fade
      double curve;
      if (isFadeIn) {
        curve = 1.0 - (1.0 - t) * (1.0 - t); // Ease out
      } else {
        curve = t * t; // Ease in
      }

      final y = size.height * (isFadeIn ? (1.0 - curve) : curve);
      path.lineTo(x, y);
    }

    path.lineTo(endX, size.height);
    path.lineTo(startX, size.height);
    path.close();

    // Gradient fill
    final fadePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fadePaint);

    // Curve line
    final curvePath = Path();
    curvePath.moveTo(startX, isFadeIn ? size.height : 0);

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = startX + (endX - startX) * t;
      double curve;
      if (isFadeIn) {
        curve = 1.0 - (1.0 - t) * (1.0 - t);
      } else {
        curve = t * t;
      }
      final y = size.height * (isFadeIn ? (1.0 - curve) : curve);
      curvePath.lineTo(x, y);
    }

    final curveLinePaint = Paint()
      ..color = FluxForgeTheme.accentOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(curvePath, curveLinePaint);
  }

  void _drawTrimHandle(Canvas canvas, Size size, double x, bool isStart, bool isHovering) {
    final handleColor = isHovering
        ? FluxForgeTheme.accentBlue
        : FluxForgeTheme.textSecondary;

    // Handle line
    final linePaint = Paint()
      ..color = handleColor
      ..strokeWidth = isHovering ? 3 : 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Handle grip (triangle)
    final gripPaint = Paint()
      ..color = handleColor
      ..style = PaintingStyle.fill;

    final gripPath = Path();
    const gripSize = 8.0;

    if (isStart) {
      // Left-pointing triangle at top
      gripPath.moveTo(x, 0);
      gripPath.lineTo(x + gripSize, 0);
      gripPath.lineTo(x, gripSize);
      gripPath.close();
      // Bottom grip
      gripPath.moveTo(x, size.height);
      gripPath.lineTo(x + gripSize, size.height);
      gripPath.lineTo(x, size.height - gripSize);
      gripPath.close();
    } else {
      // Right-pointing triangle at top
      gripPath.moveTo(x, 0);
      gripPath.lineTo(x - gripSize, 0);
      gripPath.lineTo(x, gripSize);
      gripPath.close();
      // Bottom grip
      gripPath.moveTo(x, size.height);
      gripPath.lineTo(x - gripSize, size.height);
      gripPath.lineTo(x, size.height - gripSize);
      gripPath.close();
    }

    canvas.drawPath(gripPath, gripPaint);
  }

  void _drawFadeHandle(Canvas canvas, double x, double y, bool isHovering) {
    final handleColor = isHovering
        ? FluxForgeTheme.accentOrange
        : FluxForgeTheme.accentOrange.withValues(alpha: 0.7);

    // Diamond shape
    final paint = Paint()
      ..color = handleColor
      ..style = PaintingStyle.fill;

    const size = 6.0;
    final path = Path()
      ..moveTo(x, y - size)
      ..lineTo(x + size, y)
      ..lineTo(x, y + size)
      ..lineTo(x - size, y)
      ..close();

    canvas.drawPath(path, paint);

    // Border
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(_WaveformTrimPainter oldDelegate) =>
      waveformData != oldDelegate.waveformData ||
      durationMs != oldDelegate.durationMs ||
      trimStartMs != oldDelegate.trimStartMs ||
      trimEndMs != oldDelegate.trimEndMs ||
      fadeInMs != oldDelegate.fadeInMs ||
      fadeOutMs != oldDelegate.fadeOutMs ||
      color != oldDelegate.color ||
      isHoveringTrimStart != oldDelegate.isHoveringTrimStart ||
      isHoveringTrimEnd != oldDelegate.isHoveringTrimEnd ||
      isHoveringFadeIn != oldDelegate.isHoveringFadeIn ||
      isHoveringFadeOut != oldDelegate.isHoveringFadeOut;
}
