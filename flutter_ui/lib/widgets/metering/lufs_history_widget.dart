/// LUFS History Graph Widget — Pro Tools-Level Loudness Analysis
///
/// Visualizes EBU R128 loudness trends with:
/// - Three series: Integrated (blue), Short-Term (orange), Momentary (green)
/// - Industry reference lines (-14, -16, -23 LUFS)
/// - Zoom/pan controls
/// - CSV export
///
/// CustomPainter-optimized for 60fps rendering.

import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ═══════════════════════════════════════════════════════════════════════════

/// Single LUFS measurement snapshot
class LufsSnapshot {
  /// Seconds from recording start
  final double timestamp;

  /// Integrated LUFS (full session average)
  final double integrated;

  /// Short-term LUFS (3s window)
  final double shortTerm;

  /// Momentary LUFS (400ms window)
  final double momentary;

  const LufsSnapshot({
    required this.timestamp,
    required this.integrated,
    required this.shortTerm,
    required this.momentary,
  });

  /// Check if all values are silent
  bool get isSilent =>
      integrated <= -60 && shortTerm <= -60 && momentary <= -60;

  /// CSV row format
  String toCsvRow() =>
      '${timestamp.toStringAsFixed(3)},${integrated.toStringAsFixed(1)},${shortTerm.toStringAsFixed(1)},${momentary.toStringAsFixed(1)}';

  @override
  String toString() =>
      'LufsSnapshot(t=${timestamp.toStringAsFixed(2)}s, I=${integrated.toStringAsFixed(1)}, S=${shortTerm.toStringAsFixed(1)}, M=${momentary.toStringAsFixed(1)})';
}

// ═══════════════════════════════════════════════════════════════════════════
// REFERENCE TARGETS
// ═══════════════════════════════════════════════════════════════════════════

/// Industry loudness targets
enum LufsTarget {
  spotify(-14.0, 'Spotify/Apple Music', Color(0xFF1DB954)),
  youtube(-16.0, 'YouTube', Color(0xFFFF0000)),
  broadcast(-23.0, 'EBU R128 Broadcast', Color(0xFFFFAA00));

  final double lufs;
  final String label;
  final Color color;
  const LufsTarget(this.lufs, this.label, this.color);
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class LufsHistoryGraph extends StatefulWidget {
  /// LUFS history data from MeterProvider
  final List<LufsSnapshot> history;

  /// Currently visible time range in seconds (for zoom)
  final double visibleDuration;

  /// Time offset for pan (seconds from start)
  final double timeOffset;

  /// Show reference target lines
  final bool showTargets;

  /// Show grid lines
  final bool showGrid;

  /// Show fill gradient under momentary
  final bool showFill;

  /// Callback for export action
  final VoidCallback? onExport;

  /// Callback when zoom/pan changes
  final void Function(double duration, double offset)? onViewChanged;

  const LufsHistoryGraph({
    super.key,
    required this.history,
    this.visibleDuration = 60.0,
    this.timeOffset = 0.0,
    this.showTargets = true,
    this.showGrid = true,
    this.showFill = true,
    this.onExport,
    this.onViewChanged,
  });

  @override
  State<LufsHistoryGraph> createState() => _LufsHistoryGraphState();
}

class _LufsHistoryGraphState extends State<LufsHistoryGraph> {
  // View state
  late double _visibleDuration;
  late double _timeOffset;

  // Interaction
  double? _hoverX;
  LufsSnapshot? _hoverSnapshot;
  bool _isPanning = false;
  double _panStartX = 0;
  double _panStartOffset = 0;

  @override
  void initState() {
    super.initState();
    _visibleDuration = widget.visibleDuration;
    _timeOffset = widget.timeOffset;
  }

  @override
  void didUpdateWidget(LufsHistoryGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visibleDuration != oldWidget.visibleDuration) {
      _visibleDuration = widget.visibleDuration;
    }
    if (widget.timeOffset != oldWidget.timeOffset) {
      _timeOffset = widget.timeOffset;
    }
  }

  void _handleZoom(double delta, double focalX, double width) {
    final zoomFactor = delta > 0 ? 0.9 : 1.1;
    final newDuration = (_visibleDuration * zoomFactor).clamp(5.0, 300.0);

    // Zoom towards focal point
    final focalRatio = focalX / width;
    final focalTime = _timeOffset + focalRatio * _visibleDuration;
    final newOffset = focalTime - focalRatio * newDuration;

    setState(() {
      _visibleDuration = newDuration;
      _timeOffset = newOffset.clamp(0.0, _maxOffset);
    });

    widget.onViewChanged?.call(_visibleDuration, _timeOffset);
  }

  void _handlePanStart(double x) {
    _isPanning = true;
    _panStartX = x;
    _panStartOffset = _timeOffset;
  }

  void _handlePanUpdate(double x, double width) {
    if (!_isPanning) return;

    final dx = x - _panStartX;
    final timeDelta = -dx / width * _visibleDuration;
    setState(() {
      _timeOffset = (_panStartOffset + timeDelta).clamp(0.0, _maxOffset);
    });

    widget.onViewChanged?.call(_visibleDuration, _timeOffset);
  }

  void _handlePanEnd() {
    _isPanning = false;
  }

  void _handleHover(double x, double width) {
    if (widget.history.isEmpty) {
      setState(() {
        _hoverX = null;
        _hoverSnapshot = null;
      });
      return;
    }

    final time = _timeOffset + (x / width) * _visibleDuration;

    // Find closest snapshot
    LufsSnapshot? closest;
    double minDist = double.infinity;
    for (final snap in widget.history) {
      final dist = (snap.timestamp - time).abs();
      if (dist < minDist) {
        minDist = dist;
        closest = snap;
      }
    }

    setState(() {
      _hoverX = x;
      _hoverSnapshot = closest;
    });
  }

  void _handleHoverExit() {
    setState(() {
      _hoverX = null;
      _hoverSnapshot = null;
    });
  }

  double get _maxOffset {
    if (widget.history.isEmpty) return 0;
    final maxTime = widget.history.last.timestamp;
    return (maxTime - _visibleDuration).clamp(0.0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with controls
        _buildHeader(),
        const SizedBox(height: 4),
        // Graph
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeepest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: MouseRegion(
                onHover: (e) => _handleHover(e.localPosition.dx, context.size?.width ?? 200),
                onExit: (_) => _handleHoverExit(),
                child: GestureDetector(
                  onScaleStart: (d) => _handlePanStart(d.localFocalPoint.dx),
                  onScaleUpdate: (d) {
                    if (d.scale != 1.0) {
                      // Pinch zoom
                      _handleZoom(
                        d.scale > 1.0 ? 1 : -1,
                        d.localFocalPoint.dx,
                        context.size?.width ?? 200,
                      );
                    } else {
                      // Pan
                      _handlePanUpdate(d.localFocalPoint.dx, context.size?.width ?? 200);
                    }
                  },
                  onScaleEnd: (_) => _handlePanEnd(),
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        _handleZoom(
                          event.scrollDelta.dy,
                          event.localPosition.dx,
                          context.size?.width ?? 200,
                        );
                      }
                    },
                    child: CustomPaint(
                      painter: _LufsHistoryPainter(
                        history: widget.history,
                        visibleDuration: _visibleDuration,
                        timeOffset: _timeOffset,
                        showTargets: widget.showTargets,
                        showGrid: widget.showGrid,
                        showFill: widget.showFill,
                        hoverX: _hoverX,
                        hoverSnapshot: _hoverSnapshot,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Legend
        _buildLegend(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Text(
            'LUFS HISTORY',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          // Zoom controls
          _buildIconButton(
            icon: Icons.zoom_out,
            onTap: () => _handleZoom(-1, 100, 200),
            tooltip: 'Zoom Out',
          ),
          const SizedBox(width: 4),
          Text(
            '${_visibleDuration.toInt()}s',
            style: const TextStyle(
              color: FluxForgeTheme.textTertiary,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 4),
          _buildIconButton(
            icon: Icons.zoom_in,
            onTap: () => _handleZoom(1, 100, 200),
            tooltip: 'Zoom In',
          ),
          const SizedBox(width: 8),
          // Export button
          _buildIconButton(
            icon: Icons.download,
            onTap: widget.onExport,
            tooltip: 'Export CSV',
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    VoidCallback? onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 14,
            color: onTap != null
                ? FluxForgeTheme.textSecondary
                : FluxForgeTheme.textDisabled,
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _buildLegendItem(
            'Integrated',
            FluxForgeTheme.accentBlue,
            _hoverSnapshot?.integrated,
          ),
          const SizedBox(width: 12),
          _buildLegendItem(
            'Short-Term (3s)',
            FluxForgeTheme.accentOrange,
            _hoverSnapshot?.shortTerm,
          ),
          const SizedBox(width: 12),
          _buildLegendItem(
            'Momentary (400ms)',
            FluxForgeTheme.accentGreen,
            _hoverSnapshot?.momentary,
          ),
          const Spacer(),
          if (_hoverSnapshot != null)
            Text(
              't=${_hoverSnapshot!.timestamp.toStringAsFixed(1)}s',
              style: const TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 9,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, double? value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 9,
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: 4),
          Text(
            '${value.toStringAsFixed(1)} LUFS',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — 60fps Optimized
// ═══════════════════════════════════════════════════════════════════════════

class _LufsHistoryPainter extends CustomPainter {
  final List<LufsSnapshot> history;
  final double visibleDuration;
  final double timeOffset;
  final bool showTargets;
  final bool showGrid;
  final bool showFill;
  final double? hoverX;
  final LufsSnapshot? hoverSnapshot;

  // LUFS axis range
  static const double lufsMin = -40.0;
  static const double lufsMax = 0.0;

  _LufsHistoryPainter({
    required this.history,
    required this.visibleDuration,
    required this.timeOffset,
    required this.showTargets,
    required this.showGrid,
    required this.showFill,
    this.hoverX,
    this.hoverSnapshot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Background
    canvas.drawRect(rect, Paint()..color = FluxForgeTheme.bgDeepest);

    // Grid
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    // Reference targets (dashed lines)
    if (showTargets) {
      _drawTargets(canvas, size);
    }

    // Data series
    if (history.isNotEmpty) {
      // Fill gradient under momentary
      if (showFill) {
        _drawFill(canvas, size);
      }

      // Lines (integrated, short-term, momentary)
      _drawSeries(canvas, size, (s) => s.integrated, FluxForgeTheme.accentBlue, 2.0);
      _drawSeries(canvas, size, (s) => s.shortTerm, FluxForgeTheme.accentOrange, 1.5);
      _drawSeries(canvas, size, (s) => s.momentary, FluxForgeTheme.accentGreen, 1.0);
    }

    // Crosshair
    if (hoverX != null && hoverSnapshot != null) {
      _drawCrosshair(canvas, size);
    }

    // Axis labels
    _drawAxisLabels(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 0.5;

    final minorGridPaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 0.5;

    // Horizontal grid (LUFS) - major every 10dB, minor every 2dB
    for (double lufs = lufsMin; lufs <= lufsMax; lufs += 2) {
      final y = _lufsToY(lufs, size.height);
      final isMajor = lufs % 10 == 0;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        isMajor ? gridPaint : minorGridPaint,
      );
    }

    // Vertical grid (time)
    final majorInterval = _getMajorTimeInterval();
    final minorInterval = majorInterval / 5;

    final startTime = (timeOffset / minorInterval).floor() * minorInterval;
    final endTime = timeOffset + visibleDuration;

    for (double t = startTime; t <= endTime; t += minorInterval) {
      if (t < timeOffset) continue;
      final x = _timeToX(t, size.width);
      final isMajor = (t % majorInterval).abs() < 0.01;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? gridPaint : minorGridPaint,
      );
    }
  }

  void _drawTargets(Canvas canvas, Size size) {
    for (final target in LufsTarget.values) {
      final y = _lufsToY(target.lufs, size.height);

      // Dashed line
      final dashPaint = Paint()
        ..color = target.color.withOpacity(0.6)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;

      const dashWidth = 6.0;
      const dashSpace = 4.0;
      double startX = 0;

      while (startX < size.width) {
        canvas.drawLine(
          Offset(startX, y),
          Offset(math.min(startX + dashWidth, size.width), y),
          dashPaint,
        );
        startX += dashWidth + dashSpace;
      }

      // Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${target.lufs.toInt()} LUFS',
          style: TextStyle(
            color: target.color.withOpacity(0.8),
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(size.width - textPainter.width - 4, y - 10));
    }
  }

  void _drawFill(Canvas canvas, Size size) {
    final path = Path();
    bool started = false;

    for (final snap in history) {
      if (snap.timestamp < timeOffset ||
          snap.timestamp > timeOffset + visibleDuration) {
        continue;
      }

      final x = _timeToX(snap.timestamp, size.width);
      final y = _lufsToY(snap.momentary, size.height);

      if (!started) {
        path.moveTo(x, size.height);
        path.lineTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    if (started) {
      // Find last visible point
      LufsSnapshot? lastVisible;
      for (final snap in history.reversed) {
        if (snap.timestamp >= timeOffset &&
            snap.timestamp <= timeOffset + visibleDuration) {
          lastVisible = snap;
          break;
        }
      }

      if (lastVisible != null) {
        final lastX = _timeToX(lastVisible.timestamp, size.width);
        path.lineTo(lastX, size.height);
        path.close();

        final gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FluxForgeTheme.accentGreen.withOpacity(0.3),
            FluxForgeTheme.accentGreen.withOpacity(0.0),
          ],
        );

        canvas.drawPath(
          path,
          Paint()..shader = gradient.createShader(Offset.zero & size),
        );
      }
    }
  }

  void _drawSeries(
    Canvas canvas,
    Size size,
    double Function(LufsSnapshot) getValue,
    Color color,
    double strokeWidth,
  ) {
    final path = Path();
    bool started = false;

    for (final snap in history) {
      if (snap.timestamp < timeOffset ||
          snap.timestamp > timeOffset + visibleDuration) {
        continue;
      }

      final value = getValue(snap);
      if (value <= -60) continue; // Skip silent values

      final x = _timeToX(snap.timestamp, size.width);
      final y = _lufsToY(value, size.height);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    if (started) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _drawCrosshair(Canvas canvas, Size size) {
    if (hoverX == null || hoverSnapshot == null) return;

    final x = hoverX!;
    final snap = hoverSnapshot!;

    // Vertical line
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..strokeWidth = 1,
    );

    // Value dots
    _drawValueDot(canvas, x, _lufsToY(snap.integrated, size.height), FluxForgeTheme.accentBlue);
    _drawValueDot(canvas, x, _lufsToY(snap.shortTerm, size.height), FluxForgeTheme.accentOrange);
    _drawValueDot(canvas, x, _lufsToY(snap.momentary, size.height), FluxForgeTheme.accentGreen);
  }

  void _drawValueDot(Canvas canvas, double x, double y, Color color) {
    // Glow
    canvas.drawCircle(
      Offset(x, y),
      6,
      Paint()
        ..color = color.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Dot
    canvas.drawCircle(
      Offset(x, y),
      4,
      Paint()..color = color,
    );

    // Center
    canvas.drawCircle(
      Offset(x, y),
      2,
      Paint()..color = Colors.white,
    );
  }

  void _drawAxisLabels(Canvas canvas, Size size) {
    // LUFS labels (left)
    for (double lufs = lufsMin; lufs <= lufsMax; lufs += 10) {
      final y = _lufsToY(lufs, size.height);
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${lufs.toInt()}',
          style: const TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 8,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(2, y - textPainter.height / 2));
    }

    // Time labels (bottom)
    final majorInterval = _getMajorTimeInterval();
    final startTime = (timeOffset / majorInterval).ceil() * majorInterval;
    final endTime = timeOffset + visibleDuration;

    for (double t = startTime; t <= endTime; t += majorInterval) {
      final x = _timeToX(t, size.width);
      final label = _formatTime(t);

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: FluxForgeTheme.textTertiary,
            fontSize: 8,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, size.height - textPainter.height - 2),
      );
    }
  }

  double _timeToX(double time, double width) {
    return (time - timeOffset) / visibleDuration * width;
  }

  double _lufsToY(double lufs, double height) {
    final normalized = (lufs - lufsMax) / (lufsMin - lufsMax);
    return normalized.clamp(0.0, 1.0) * height;
  }

  double _getMajorTimeInterval() {
    if (visibleDuration <= 10) return 1.0;
    if (visibleDuration <= 30) return 5.0;
    if (visibleDuration <= 60) return 10.0;
    if (visibleDuration <= 120) return 20.0;
    if (visibleDuration <= 300) return 60.0;
    return 60.0;
  }

  String _formatTime(double seconds) {
    if (seconds < 60) {
      return '${seconds.toInt()}s';
    }
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).toInt();
    return '${mins}m${secs.toString().padLeft(2, '0')}s';
  }

  @override
  bool shouldRepaint(_LufsHistoryPainter oldDelegate) {
    return history != oldDelegate.history ||
        visibleDuration != oldDelegate.visibleDuration ||
        timeOffset != oldDelegate.timeOffset ||
        showTargets != oldDelegate.showTargets ||
        showGrid != oldDelegate.showGrid ||
        showFill != oldDelegate.showFill ||
        hoverX != oldDelegate.hoverX ||
        hoverSnapshot != oldDelegate.hoverSnapshot;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CSV EXPORT UTILITIES
// ═══════════════════════════════════════════════════════════════════════════

/// Generate CSV content from LUFS history
String generateLufsCsv(List<LufsSnapshot> history) {
  final buffer = StringBuffer();
  buffer.writeln('timestamp_s,integrated_lufs,short_term_lufs,momentary_lufs');
  for (final snap in history) {
    buffer.writeln(snap.toCsvRow());
  }
  return buffer.toString();
}

/// Copy LUFS history to clipboard as CSV
Future<void> copyLufsHistoryToClipboard(List<LufsSnapshot> history) async {
  final csv = generateLufsCsv(history);
  await Clipboard.setData(ClipboardData(text: csv));
}
