/// DAW Automation Panel (P0.1 Extracted)
///
/// Interactive automation curve editor:
/// - Mode selection (Read, Write, Touch)
/// - Parameter selection (Volume, Pan, Send, EQ, Comp)
/// - Point-based curve editing with gestures
/// - Cubic bezier interpolation for smooth curves
/// - Visual grid and value labels
///
/// Extracted from daw_lower_zone_widget.dart (2026-01-26)
/// Lines 1764-2017 + 3226-3379 (~407 LOC total)
library;

import 'package:flutter/material.dart';
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
  String _automationMode = 'Read';
  String _automationParameter = 'Volume';
  List<Offset> _automationPoints = [];
  int? _selectedAutomationPointIndex;

  @override
  Widget build(BuildContext context) {
    final selectedTrackName = widget.selectedTrackId != null
        ? 'Track ${widget.selectedTrackId}'
        : 'No Track Selected';

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
                    color: widget.selectedTrackId != null
                        ? LowerZoneColors.textPrimary
                        : LowerZoneColors.textMuted,
                  ),
                ),
              ),
              const Spacer(),
              _buildAutomationModeChip('Read', _automationMode == 'Read'),
              _buildAutomationModeChip('Write', _automationMode == 'Write'),
              _buildAutomationModeChip('Touch', _automationMode == 'Touch'),
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
                onPressed: widget.selectedTrackId != null
                    ? () => setState(() => _automationPoints.clear())
                    : null,
                icon: const Icon(Icons.clear, size: 14, color: LowerZoneColors.textMuted),
                label: const Text(
                  'Clear',
                  style: TextStyle(fontSize: 10, color: LowerZoneColors.textMuted),
                ),
              ),
              const Spacer(),
              // Point count
              if (_automationPoints.isNotEmpty)
                Text(
                  '${_automationPoints.length} points',
                  style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Automation curve editor
          Expanded(
            child: widget.selectedTrackId == null
                ? _buildNoTrackAutomationPlaceholder()
                : _buildInteractiveAutomationEditor(),
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

  Widget _buildInteractiveAutomationEditor() {
    return GestureDetector(
      onTapDown: (details) {
        if (_automationMode != 'Read') {
          setState(() {
            _automationPoints.add(details.localPosition);
            _automationPoints.sort((a, b) => a.dx.compareTo(b.dx));
          });
        }
      },
      onPanStart: (details) {
        // Find if we're near a point
        for (int i = 0; i < _automationPoints.length; i++) {
          if ((details.localPosition - _automationPoints[i]).distance < 12) {
            setState(() => _selectedAutomationPointIndex = i);
            break;
          }
        }
      },
      onPanUpdate: (details) {
        if (_selectedAutomationPointIndex != null && _automationMode != 'Read') {
          setState(() {
            _automationPoints[_selectedAutomationPointIndex!] = details.localPosition;
          });
        }
      },
      onPanEnd: (_) {
        if (_selectedAutomationPointIndex != null) {
          setState(() {
            _automationPoints.sort((a, b) => a.dx.compareTo(b.dx));
            _selectedAutomationPointIndex = null;
          });
        }
      },
      onDoubleTap: () {
        // Delete last point on double tap
        if (_automationPoints.isNotEmpty && _automationMode != 'Read') {
          setState(() => _automationPoints.removeLast());
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: LowerZoneColors.bgDeepest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: CustomPaint(
          painter: AutomationCurvePainter(
            color: LowerZoneColors.dawAccent,
            points: _automationPoints,
            selectedIndex: _selectedAutomationPointIndex,
            isEditable: _automationMode != 'Read',
          ),
        ),
      ),
    );
  }

  Widget _buildAutomationModeChip(String label, bool isActive) {
    return GestureDetector(
      onTap: () => setState(() => _automationMode = label),
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
              ? 'Click to add automation points\nDouble-click to delete last point'
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
