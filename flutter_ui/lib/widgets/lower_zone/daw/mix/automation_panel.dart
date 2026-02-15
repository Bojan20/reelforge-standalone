/// DAW Automation Panel — Connected to AutomationProvider + FFI
///
/// Interactive automation curve editor:
/// - Mode selection (Read, Write, Touch, Latch, Trim)
/// - Parameter selection (Volume, Pan, Send, EQ, Comp)
/// - Point-based curve editing with gestures → FFI sync
/// - Cubic bezier interpolation for smooth curves
/// - Visual grid and value labels
library;

import 'package:flutter/material.dart';
import '../../../../providers/automation_provider.dart';
import '../../../../services/service_locator.dart';
import '../../lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION PANEL
// ═══════════════════════════════════════════════════════════════════════════

class AutomationPanel extends StatefulWidget {
  /// Currently selected track ID
  final int? selectedTrackId;

  const AutomationPanel({super.key, this.selectedTrackId});

  @override
  State<AutomationPanel> createState() => _AutomationPanelState();
}

class _AutomationPanelState extends State<AutomationPanel> {
  final AutomationProvider _provider = sl<AutomationProvider>();
  String _automationParameter = 'Volume';
  int? _selectedPointIndex;

  // Duration of visible timeline in samples (default 10 seconds at 48kHz)
  int get _visibleDurationSamples => (_provider.sampleRate * 10).round();

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  // ─── Coordinate Conversion ─────────────────────────────────────────────

  /// Convert pixel X to time in samples
  int _xToTimeSamples(double x, double width) {
    return (x / width * _visibleDurationSamples).round().clamp(0, _visibleDurationSamples);
  }

  /// Convert pixel Y to automation value (0.0-1.0, top=1.0, bottom=0.0)
  double _yToValue(double y, double height) {
    return (1.0 - (y / height)).clamp(0.0, 1.0);
  }

  /// Convert time in samples to pixel X
  double _timeSamplesToX(int timeSamples, double width) {
    return timeSamples / _visibleDurationSamples * width;
  }

  /// Convert automation value to pixel Y
  double _valueToY(double value, double height) {
    return (1.0 - value) * height;
  }

  /// Convert provider points to pixel Offsets for the painter
  List<Offset> _pointsToOffsets(List<AutomationPoint> points, Size size) {
    return points.map((p) => Offset(
      _timeSamplesToX(p.timeSamples, size.width),
      _valueToY(p.value, size.height),
    )).toList();
  }

  // ─── Provider Mode Mapping ─────────────────────────────────────────────

  AutomationMode _labelToMode(String label) {
    return switch (label) {
      'Read' => AutomationMode.read,
      'Write' => AutomationMode.write,
      'Touch' => AutomationMode.touch,
      'Latch' => AutomationMode.latch,
      'Trim' => AutomationMode.trim,
      _ => AutomationMode.read,
    };
  }

  String _modeToLabel(AutomationMode mode) {
    return switch (mode) {
      AutomationMode.read => 'Read',
      AutomationMode.write => 'Write',
      AutomationMode.touch => 'Touch',
      AutomationMode.latch => 'Latch',
      AutomationMode.trim => 'Trim',
    };
  }

  bool get _isEditable => _provider.mode != AutomationMode.read;

  @override
  Widget build(BuildContext context) {
    final trackId = widget.selectedTrackId;
    final selectedTrackName = trackId != null
        ? 'Track $trackId'
        : 'No Track Selected';

    final lane = trackId != null
        ? _provider.getLane(trackId, _automationParameter)
        : null;
    final pointCount = lane?.points.length ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.auto_graph, size: 16, color: LowerZoneColors.dawAccent),
              const SizedBox(width: 8),
              const Text(
                'AUTOMATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.dawAccent,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 12),
              // Track indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: LowerZoneColors.bgSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  selectedTrackName,
                  style: TextStyle(
                    fontSize: 9,
                    color: trackId != null
                        ? LowerZoneColors.textPrimary
                        : LowerZoneColors.textMuted,
                  ),
                ),
              ),
              const Spacer(),
              _buildAutomationModeChip('Read'),
              _buildAutomationModeChip('Write'),
              _buildAutomationModeChip('Touch'),
            ],
          ),
          const SizedBox(height: 8),
          // Parameter selection row
          Row(
            children: [
              const Text(
                'Parameter:',
                style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                initialValue: _automationParameter,
                onSelected: (value) => setState(() => _automationParameter = value),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: LowerZoneColors.bgSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: LowerZoneColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _automationParameter,
                        style: const TextStyle(
                          fontSize: 10,
                          color: LowerZoneColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 14, color: LowerZoneColors.textMuted),
                    ],
                  ),
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'Volume', child: Text('Volume')),
                  PopupMenuItem(value: 'Pan', child: Text('Pan')),
                  PopupMenuItem(value: 'Mute', child: Text('Mute')),
                  PopupMenuItem(value: 'Send 1', child: Text('Send 1')),
                  PopupMenuItem(value: 'Send 2', child: Text('Send 2')),
                  PopupMenuItem(value: 'EQ Gain', child: Text('EQ Gain')),
                  PopupMenuItem(value: 'EQ Freq', child: Text('EQ Freq')),
                  PopupMenuItem(value: 'Comp Threshold', child: Text('Comp Threshold')),
                ],
              ),
              const SizedBox(width: 16),
              // Clear button
              TextButton.icon(
                onPressed: trackId != null
                    ? () => _provider.clearLane(trackId, _automationParameter)
                    : null,
                icon: const Icon(Icons.clear, size: 14, color: LowerZoneColors.textMuted),
                label: const Text(
                  'Clear',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                ),
              ),
              const Spacer(),
              // Point count
              if (pointCount > 0)
                Text(
                  '$pointCount points',
                  style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Automation curve editor
          Expanded(
            child: trackId == null
                ? _buildNoTrackAutomationPlaceholder()
                : _buildInteractiveAutomationEditor(trackId, lane),
          ),
        ],
      ),
    );
  }

  // ─── UI Builders ───────────────────────────────────────────────────────────

  Widget _buildNoTrackAutomationPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.timeline,
              size: 40,
              color: LowerZoneColors.textMuted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select a track to edit automation',
              style: TextStyle(
                fontSize: 11,
                color: LowerZoneColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveAutomationEditor(int trackId, AutomationLane? lane) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final points = lane?.points ?? [];
        final offsets = _pointsToOffsets(points, size);

        return GestureDetector(
          onTapDown: (details) {
            if (_isEditable) {
              final timeSamples = _xToTimeSamples(details.localPosition.dx, size.width);
              final value = _yToValue(details.localPosition.dy, size.height);
              _provider.addPoint(trackId, _automationParameter, timeSamples, value);
            }
          },
          onPanStart: (details) {
            // Find if we're near a point
            for (int i = 0; i < offsets.length; i++) {
              if ((details.localPosition - offsets[i]).distance < 12) {
                setState(() => _selectedPointIndex = i);
                break;
              }
            }
          },
          onPanUpdate: (details) {
            if (_selectedPointIndex != null && _isEditable && _selectedPointIndex! < points.length) {
              final timeSamples = _xToTimeSamples(details.localPosition.dx, size.width);
              final value = _yToValue(details.localPosition.dy, size.height);
              _provider.movePoint(
                trackId,
                _automationParameter,
                _selectedPointIndex!,
                timeSamples,
                value,
              );
            }
          },
          onPanEnd: (_) {
            setState(() => _selectedPointIndex = null);
          },
          onDoubleTapDown: (details) {
            if (_isEditable && points.isNotEmpty) {
              // Find nearest point to double-tap and remove it
              int? nearestIdx;
              double nearestDist = double.infinity;
              for (int i = 0; i < offsets.length; i++) {
                final dist = (details.localPosition - offsets[i]).distance;
                if (dist < 20 && dist < nearestDist) {
                  nearestDist = dist;
                  nearestIdx = i;
                }
              }
              if (nearestIdx != null) {
                _provider.removePoint(trackId, _automationParameter, nearestIdx);
              }
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: LowerZoneColors.bgDeepest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: CustomPaint(
              size: size,
              painter: AutomationCurvePainter(
                color: LowerZoneColors.dawAccent,
                points: offsets,
                selectedIndex: _selectedPointIndex,
                isEditable: _isEditable,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAutomationModeChip(String label) {
    final isActive = _modeToLabel(_provider.mode) == label;
    return GestureDetector(
      onTap: () => _provider.setMode(_labelToMode(label)),
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isActive
              ? LowerZoneColors.dawAccent.withValues(alpha: 0.2)
              : LowerZoneColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? LowerZoneColors.dawAccent : LowerZoneColors.textMuted,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class AutomationCurvePainter extends CustomPainter {
  final Color color;
  final List<Offset> points;
  final int? selectedIndex;
  final bool isEditable;

  const AutomationCurvePainter({
    required this.color,
    required this.points,
    this.selectedIndex,
    this.isEditable = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw grid
    _drawGrid(canvas, size);

    // Draw value labels
    _drawValueLabels(canvas, size);

    if (points.isEmpty) {
      // Draw placeholder text
      final textPainter = TextPainter(
        text: TextSpan(
          text: isEditable
              ? 'Click to add automation points\nDouble-click point to delete'
              : 'Switch to Write or Touch mode to edit',
          style: TextStyle(
            color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
      return;
    }

    final curvePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    // Draw curve with fill
    if (points.length >= 2) {
      final path = Path();
      final fillPath = Path();

      path.moveTo(points[0].dx, points[0].dy);
      fillPath.moveTo(points[0].dx, size.height);
      fillPath.lineTo(points[0].dx, points[0].dy);

      for (int i = 1; i < points.length; i++) {
        // Cubic bezier for smooth curve
        final cp1x = points[i - 1].dx + (points[i].dx - points[i - 1].dx) / 2;
        final cp1y = points[i - 1].dy;
        final cp2x = points[i - 1].dx + (points[i].dx - points[i - 1].dx) / 2;
        final cp2y = points[i].dy;
        path.cubicTo(cp1x, cp1y, cp2x, cp2y, points[i].dx, points[i].dy);
        fillPath.cubicTo(cp1x, cp1y, cp2x, cp2y, points[i].dx, points[i].dy);
      }

      fillPath.lineTo(points.last.dx, size.height);
      fillPath.close();

      canvas.drawPath(fillPath, fillPaint);
      canvas.drawPath(path, curvePaint);
    }

    // Draw points
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final selectedPointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final pointOutlinePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final isSelected = i == selectedIndex;

      if (isSelected) {
        canvas.drawCircle(point, 8, selectedPointPaint);
        canvas.drawCircle(point, 8, pointOutlinePaint);
      } else {
        canvas.drawCircle(point, 5, pointPaint);
      }
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = LowerZoneColors.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Horizontal lines (value grid)
    for (int i = 0; i <= 4; i++) {
      final y = i * size.height / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical lines (time grid)
    for (int i = 0; i <= 8; i++) {
      final x = i * size.width / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  void _drawValueLabels(Canvas canvas, Size size) {
    const labels = ['100%', '75%', '50%', '25%', '0%'];
    for (int i = 0; i < labels.length; i++) {
      final y = i * size.height / 4;
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
            fontSize: 8,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(4, y + 2));
    }
  }

  @override
  bool shouldRepaint(covariant AutomationCurvePainter oldDelegate) {
    return points != oldDelegate.points ||
        selectedIndex != oldDelegate.selectedIndex ||
        isEditable != oldDelegate.isEditable;
  }
}
