/// Automation Curve Editor — P2-DAW-3
///
/// Visual bezier curve editor for DAW automation:
/// - Multi-point selection with drag
/// - Curve type presets (linear, exponential, logarithmic, S-curve)
/// - Real-time preview with playhead
/// - Copy/paste automation curves
///
/// Usage:
///   AutomationCurveEditor(
///     points: automationPoints,
///     onPointsChanged: (points) => updateAutomation(points),
///     curveType: AutomationCurveType.sCurve,
///   )
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION CURVE TYPES
// ═══════════════════════════════════════════════════════════════════════════

/// Types of automation curves
enum AutomationCurveType {
  linear('Linear', 'Straight line between points'),
  exponential('Exp', 'Exponential curve'),
  logarithmic('Log', 'Logarithmic curve'),
  sCurve('S-Curve', 'Smooth S-shaped curve'),
  hold('Hold', 'Hold value until next point'),
  custom('Custom', 'Custom bezier curve');

  final String name;
  final String description;

  const AutomationCurveType(this.name, this.description);
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION POINT
// ═══════════════════════════════════════════════════════════════════════════

/// A single point in the automation curve
class AutomationPoint {
  final String id;
  final double time; // 0.0-1.0 normalized position
  final double value; // 0.0-1.0 normalized value
  final AutomationCurveType curveType;
  final double tension; // For bezier curves, 0.0-1.0
  final bool selected;

  const AutomationPoint({
    required this.id,
    required this.time,
    required this.value,
    this.curveType = AutomationCurveType.linear,
    this.tension = 0.5,
    this.selected = false,
  });

  AutomationPoint copyWith({
    double? time,
    double? value,
    AutomationCurveType? curveType,
    double? tension,
    bool? selected,
  }) {
    return AutomationPoint(
      id: id,
      time: time ?? this.time,
      value: value ?? this.value,
      curveType: curveType ?? this.curveType,
      tension: tension ?? this.tension,
      selected: selected ?? this.selected,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time,
        'value': value,
        'curveType': curveType.index,
        'tension': tension,
      };

  factory AutomationPoint.fromJson(Map<String, dynamic> json) {
    return AutomationPoint(
      id: json['id'] as String,
      time: (json['time'] as num).toDouble(),
      value: (json['value'] as num).toDouble(),
      curveType: AutomationCurveType.values[json['curveType'] as int? ?? 0],
      tension: (json['tension'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTOMATION CURVE EDITOR WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Visual automation curve editor with bezier support
class AutomationCurveEditor extends StatefulWidget {
  final List<AutomationPoint> points;
  final ValueChanged<List<AutomationPoint>> onPointsChanged;
  final AutomationCurveType defaultCurveType;
  final double playheadPosition; // 0.0-1.0
  final bool showPlayhead;
  final bool showGrid;
  final Color curveColor;
  final Color pointColor;
  final Color selectedColor;
  final double minValue;
  final double maxValue;
  final String? valueLabel;
  final String Function(double)? valueFormatter;

  const AutomationCurveEditor({
    super.key,
    required this.points,
    required this.onPointsChanged,
    this.defaultCurveType = AutomationCurveType.linear,
    this.playheadPosition = 0.0,
    this.showPlayhead = true,
    this.showGrid = true,
    this.curveColor = const Color(0xFF4A9EFF),
    this.pointColor = const Color(0xFF40FF90),
    this.selectedColor = const Color(0xFFFF9040),
    this.minValue = 0.0,
    this.maxValue = 1.0,
    this.valueLabel,
    this.valueFormatter,
  });

  @override
  State<AutomationCurveEditor> createState() => _AutomationCurveEditorState();
}

class _AutomationCurveEditorState extends State<AutomationCurveEditor> {
  // Selection state
  final Set<String> _selectedIds = {};
  Rect? _selectionRect;
  Offset? _dragStart;
  bool _isDraggingPoint = false;
  String? _draggingPointId;

  // Clipboard
  static List<AutomationPoint>? _clipboard;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onDoubleTapDown: _handleDoubleTapDown,
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: _handlePanEnd,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CustomPaint(
            painter: _AutomationCurvePainter(
              points: widget.points,
              selectedIds: _selectedIds,
              selectionRect: _selectionRect,
              curveColor: widget.curveColor,
              pointColor: widget.pointColor,
              selectedColor: widget.selectedColor,
              playheadPosition: widget.playheadPosition,
              showPlayhead: widget.showPlayhead,
              showGrid: widget.showGrid,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Delete selected points
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelectedPoints();
      return KeyEventResult.handled;
    }

    // Select all
    if (event.logicalKey == LogicalKeyboardKey.keyA &&
        HardwareKeyboard.instance.isMetaPressed) {
      setState(() {
        _selectedIds.clear();
        _selectedIds.addAll(widget.points.map((p) => p.id));
      });
      return KeyEventResult.handled;
    }

    // Copy
    if (event.logicalKey == LogicalKeyboardKey.keyC &&
        HardwareKeyboard.instance.isMetaPressed) {
      _copySelected();
      return KeyEventResult.handled;
    }

    // Paste
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isMetaPressed) {
      _paste();
      return KeyEventResult.handled;
    }

    // Escape - deselect
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _selectedIds.clear());
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _handleTapDown(TapDownDetails details) {
    final size = context.size;
    if (size == null) return;

    final point = _findPointAt(details.localPosition, size);

    if (point != null) {
      // Toggle selection with Shift, replace otherwise
      setState(() {
        if (HardwareKeyboard.instance.isShiftPressed) {
          if (_selectedIds.contains(point.id)) {
            _selectedIds.remove(point.id);
          } else {
            _selectedIds.add(point.id);
          }
        } else {
          _selectedIds.clear();
          _selectedIds.add(point.id);
        }
      });
    } else {
      // Click on empty area - deselect
      if (!HardwareKeyboard.instance.isShiftPressed) {
        setState(() => _selectedIds.clear());
      }
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    final size = context.size;
    if (size == null) return;

    final existingPoint = _findPointAt(details.localPosition, size);

    if (existingPoint != null) {
      // Double-tap on point - cycle curve type
      _cycleCurveType(existingPoint.id);
    } else {
      // Double-tap on empty area - add point
      _addPoint(details.localPosition, size);
    }
  }

  void _handlePanStart(DragStartDetails details) {
    final size = context.size;
    if (size == null) return;

    final point = _findPointAt(details.localPosition, size);

    if (point != null && (_selectedIds.contains(point.id) || _selectedIds.isEmpty)) {
      // Start dragging point(s)
      _isDraggingPoint = true;
      _draggingPointId = point.id;

      // If dragging an unselected point, select only it
      if (!_selectedIds.contains(point.id)) {
        setState(() {
          _selectedIds.clear();
          _selectedIds.add(point.id);
        });
      }
    } else {
      // Start selection rectangle
      _dragStart = details.localPosition;
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final size = context.size;
    if (size == null) return;

    if (_isDraggingPoint) {
      // Move selected points
      _moveSelectedPoints(details.delta, size);
    } else if (_dragStart != null) {
      // Update selection rectangle
      setState(() {
        _selectionRect = Rect.fromPoints(_dragStart!, details.localPosition);
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_selectionRect != null) {
      // Select points in rectangle
      _selectPointsInRect();
    }

    setState(() {
      _isDraggingPoint = false;
      _draggingPointId = null;
      _selectionRect = null;
      _dragStart = null;
    });
  }

  AutomationPoint? _findPointAt(Offset position, Size size) {
    const hitRadius = 10.0;

    for (final point in widget.points) {
      final px = point.time * size.width;
      final py = (1.0 - point.value) * size.height;
      final distance = (Offset(px, py) - position).distance;

      if (distance <= hitRadius) {
        return point;
      }
    }
    return null;
  }

  void _addPoint(Offset position, Size size) {
    final time = (position.dx / size.width).clamp(0.0, 1.0);
    final value = (1.0 - position.dy / size.height).clamp(0.0, 1.0);

    final newPoint = AutomationPoint(
      id: 'ap_${DateTime.now().millisecondsSinceEpoch}',
      time: time,
      value: value,
      curveType: widget.defaultCurveType,
    );

    final newPoints = List<AutomationPoint>.from(widget.points)
      ..add(newPoint)
      ..sort((a, b) => a.time.compareTo(b.time));

    widget.onPointsChanged(newPoints);

    setState(() {
      _selectedIds.clear();
      _selectedIds.add(newPoint.id);
    });
  }

  void _deleteSelectedPoints() {
    if (_selectedIds.isEmpty) return;

    final newPoints = widget.points
        .where((p) => !_selectedIds.contains(p.id))
        .toList();

    widget.onPointsChanged(newPoints);
    setState(() => _selectedIds.clear());
  }

  void _moveSelectedPoints(Offset delta, Size size) {
    final timeDelta = delta.dx / size.width;
    final valueDelta = -delta.dy / size.height;

    final newPoints = widget.points.map((p) {
      if (_selectedIds.contains(p.id)) {
        return p.copyWith(
          time: (p.time + timeDelta).clamp(0.0, 1.0),
          value: (p.value + valueDelta).clamp(0.0, 1.0),
        );
      }
      return p;
    }).toList();

    newPoints.sort((a, b) => a.time.compareTo(b.time));
    widget.onPointsChanged(newPoints);
  }

  void _selectPointsInRect() {
    if (_selectionRect == null) return;
    final size = context.size;
    if (size == null) return;

    final newSelection = <String>{};

    for (final point in widget.points) {
      final px = point.time * size.width;
      final py = (1.0 - point.value) * size.height;

      if (_selectionRect!.contains(Offset(px, py))) {
        newSelection.add(point.id);
      }
    }

    setState(() {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _selectedIds.addAll(newSelection);
      } else {
        _selectedIds.clear();
        _selectedIds.addAll(newSelection);
      }
    });
  }

  void _cycleCurveType(String pointId) {
    final index = widget.points.indexWhere((p) => p.id == pointId);
    if (index < 0) return;

    final point = widget.points[index];
    final types = AutomationCurveType.values;
    final nextType = types[(point.curveType.index + 1) % types.length];

    final newPoints = List<AutomationPoint>.from(widget.points);
    newPoints[index] = point.copyWith(curveType: nextType);

    widget.onPointsChanged(newPoints);
  }

  void _copySelected() {
    if (_selectedIds.isEmpty) return;

    _clipboard = widget.points
        .where((p) => _selectedIds.contains(p.id))
        .map((p) => p.copyWith(selected: false))
        .toList();
  }

  void _paste() {
    if (_clipboard == null || _clipboard!.isEmpty) return;

    // Find the time offset for pasting
    final minTime = _clipboard!.map((p) => p.time).reduce(math.min);
    final pasteTime = widget.playheadPosition;
    final offset = pasteTime - minTime;

    final pastedPoints = _clipboard!.map((p) {
      return AutomationPoint(
        id: 'ap_${DateTime.now().millisecondsSinceEpoch}_${p.id}',
        time: (p.time + offset).clamp(0.0, 1.0),
        value: p.value,
        curveType: p.curveType,
        tension: p.tension,
      );
    }).toList();

    final newPoints = List<AutomationPoint>.from(widget.points)
      ..addAll(pastedPoints)
      ..sort((a, b) => a.time.compareTo(b.time));

    widget.onPointsChanged(newPoints);

    setState(() {
      _selectedIds.clear();
      _selectedIds.addAll(pastedPoints.map((p) => p.id));
    });
  }

  /// Apply a curve preset to selected points
  void applyCurveType(AutomationCurveType type) {
    if (_selectedIds.isEmpty) return;

    final newPoints = widget.points.map((p) {
      if (_selectedIds.contains(p.id)) {
        return p.copyWith(curveType: type);
      }
      return p;
    }).toList();

    widget.onPointsChanged(newPoints);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _AutomationCurvePainter extends CustomPainter {
  final List<AutomationPoint> points;
  final Set<String> selectedIds;
  final Rect? selectionRect;
  final Color curveColor;
  final Color pointColor;
  final Color selectedColor;
  final double playheadPosition;
  final bool showPlayhead;
  final bool showGrid;

  _AutomationCurvePainter({
    required this.points,
    required this.selectedIds,
    this.selectionRect,
    required this.curveColor,
    required this.pointColor,
    required this.selectedColor,
    required this.playheadPosition,
    required this.showPlayhead,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = FluxForgeTheme.surfaceDark,
    );

    // Grid
    if (showGrid) {
      _paintGrid(canvas, size);
    }

    // Curve
    if (points.length >= 2) {
      _paintCurve(canvas, size);
    }

    // Points
    for (final point in points) {
      _paintPoint(canvas, size, point);
    }

    // Playhead
    if (showPlayhead) {
      _paintPlayhead(canvas, size);
    }

    // Selection rectangle
    if (selectionRect != null) {
      _paintSelectionRect(canvas);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.border.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Vertical lines (time)
    for (int i = 0; i <= 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Horizontal lines (value)
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _paintCurve(Canvas canvas, Size size) {
    final curvePaint = Paint()
      ..color = curveColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final sortedPoints = List<AutomationPoint>.from(points)
      ..sort((a, b) => a.time.compareTo(b.time));

    for (int i = 0; i < sortedPoints.length; i++) {
      final point = sortedPoints[i];
      final x = point.time * size.width;
      final y = (1.0 - point.value) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final prevPoint = sortedPoints[i - 1];
        final prevX = prevPoint.time * size.width;
        final prevY = (1.0 - prevPoint.value) * size.height;

        switch (prevPoint.curveType) {
          case AutomationCurveType.linear:
            path.lineTo(x, y);
            break;

          case AutomationCurveType.exponential:
            // Exponential curve using quadratic bezier
            final cpX = x;
            final cpY = prevY;
            path.quadraticBezierTo(cpX, cpY, x, y);
            break;

          case AutomationCurveType.logarithmic:
            // Logarithmic curve using quadratic bezier
            final cpX = prevX;
            final cpY = y;
            path.quadraticBezierTo(cpX, cpY, x, y);
            break;

          case AutomationCurveType.sCurve:
            // S-curve using cubic bezier
            final midX = (prevX + x) / 2;
            path.cubicTo(midX, prevY, midX, y, x, y);
            break;

          case AutomationCurveType.hold:
            // Hold value then jump
            path.lineTo(x, prevY);
            path.lineTo(x, y);
            break;

          case AutomationCurveType.custom:
            // Custom with tension
            final tension = prevPoint.tension;
            final dx = x - prevX;
            final cp1x = prevX + dx * tension;
            final cp2x = x - dx * tension;
            path.cubicTo(cp1x, prevY, cp2x, y, x, y);
            break;
        }
      }
    }

    canvas.drawPath(path, curvePaint);
  }

  void _paintPoint(Canvas canvas, Size size, AutomationPoint point) {
    final x = point.time * size.width;
    final y = (1.0 - point.value) * size.height;
    final isSelected = selectedIds.contains(point.id);

    // Outer ring
    final outerPaint = Paint()
      ..color = isSelected ? selectedColor : pointColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(Offset(x, y), 6, outerPaint);

    // Inner fill
    final innerPaint = Paint()
      ..color = isSelected
          ? selectedColor.withValues(alpha: 0.5)
          : pointColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(x, y), 4, innerPaint);
  }

  void _paintPlayhead(Canvas canvas, Size size) {
    final x = playheadPosition * size.width;

    final playheadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1;

    canvas.drawLine(Offset(x, 0), Offset(x, size.height), playheadPaint);

    // Triangle at top
    final trianglePath = Path()
      ..moveTo(x - 5, 0)
      ..lineTo(x + 5, 0)
      ..lineTo(x, 8)
      ..close();

    canvas.drawPath(
      trianglePath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
  }

  void _paintSelectionRect(Canvas canvas) {
    if (selectionRect == null) return;

    // Fill
    canvas.drawRect(
      selectionRect!,
      Paint()..color = curveColor.withValues(alpha: 0.1),
    );

    // Border
    canvas.drawRect(
      selectionRect!,
      Paint()
        ..color = curveColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_AutomationCurvePainter oldDelegate) {
    return points != oldDelegate.points ||
        selectedIds != oldDelegate.selectedIds ||
        selectionRect != oldDelegate.selectionRect ||
        playheadPosition != oldDelegate.playheadPosition;
  }
}
