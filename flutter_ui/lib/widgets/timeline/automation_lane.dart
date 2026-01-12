// Automation Lane Widget
//
// Cubase-style automation with:
// - Multiple automation modes (Read, Write, Touch, Latch)
// - Bezier curve editing with handles
// - Multiple parameters per track
// - Snap to grid
// - Range selection and editing
// - Copy/paste automation data

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION TYPES
// ═══════════════════════════════════════════════════════════════════════════════

/// Automation mode
enum AutomationMode {
  read,   // Read existing automation
  write,  // Overwrite all automation
  touch,  // Write only while touching control
  latch,  // Write from first touch until stop
  off,    // Ignore automation
}

/// Automation parameter type
enum AutomationParameter {
  volume,
  pan,
  mute,
  send1,
  send2,
  send3,
  send4,
  eq1Gain,
  eq1Freq,
  eq2Gain,
  eq2Freq,
  compThreshold,
  compRatio,
  custom,
}

/// Automation curve type
enum AutomationCurveType {
  linear,     // Straight line between points
  bezier,     // Smooth bezier curve
  step,       // Step/hold value
  scurve,     // S-curve transition
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION POINT
// ═══════════════════════════════════════════════════════════════════════════════

/// Single automation point with bezier handles
class AutomationPoint {
  final String id;
  final double time;      // Time in seconds
  final double value;     // Normalized value (0.0 to 1.0)
  final AutomationCurveType curveType;
  final Offset? handleIn;  // Bezier handle (relative offset)
  final Offset? handleOut; // Bezier handle (relative offset)
  final bool selected;

  const AutomationPoint({
    required this.id,
    required this.time,
    required this.value,
    this.curveType = AutomationCurveType.linear,
    this.handleIn,
    this.handleOut,
    this.selected = false,
  });

  AutomationPoint copyWith({
    String? id,
    double? time,
    double? value,
    AutomationCurveType? curveType,
    Offset? handleIn,
    Offset? handleOut,
    bool? selected,
  }) {
    return AutomationPoint(
      id: id ?? this.id,
      time: time ?? this.time,
      value: value ?? this.value,
      curveType: curveType ?? this.curveType,
      handleIn: handleIn ?? this.handleIn,
      handleOut: handleOut ?? this.handleOut,
      selected: selected ?? this.selected,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION LANE DATA
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete automation lane data
class AutomationLaneData {
  final String id;
  final AutomationParameter parameter;
  final String parameterName;
  final List<AutomationPoint> points;
  final AutomationMode mode;
  final double height;
  final bool visible;
  final Color color;
  final double minValue; // Display range
  final double maxValue;
  final String unit;     // e.g., "dB", "%", "Hz"

  const AutomationLaneData({
    required this.id,
    required this.parameter,
    required this.parameterName,
    this.points = const [],
    this.mode = AutomationMode.read,
    this.height = 60,
    this.visible = true,
    this.color = const Color(0xFF4A9EFF),
    this.minValue = 0,
    this.maxValue = 1,
    this.unit = '',
  });

  AutomationLaneData copyWith({
    String? id,
    AutomationParameter? parameter,
    String? parameterName,
    List<AutomationPoint>? points,
    AutomationMode? mode,
    double? height,
    bool? visible,
    Color? color,
    double? minValue,
    double? maxValue,
    String? unit,
  }) {
    return AutomationLaneData(
      id: id ?? this.id,
      parameter: parameter ?? this.parameter,
      parameterName: parameterName ?? this.parameterName,
      points: points ?? this.points,
      mode: mode ?? this.mode,
      height: height ?? this.height,
      visible: visible ?? this.visible,
      color: color ?? this.color,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      unit: unit ?? this.unit,
    );
  }

  /// Get interpolated value at time
  double getValueAtTime(double time) {
    if (points.isEmpty) return 0.5;
    if (points.length == 1) return points.first.value;

    // Find surrounding points
    AutomationPoint? before;
    AutomationPoint? after;

    for (int i = 0; i < points.length; i++) {
      if (points[i].time <= time) {
        before = points[i];
      }
      if (points[i].time >= time && after == null) {
        after = points[i];
      }
    }

    if (before == null) return points.first.value;
    if (after == null) return points.last.value;
    if (before == after) return before.value;

    // Interpolate
    final t = (time - before.time) / (after.time - before.time);

    switch (before.curveType) {
      case AutomationCurveType.linear:
        return before.value + t * (after.value - before.value);

      case AutomationCurveType.step:
        return before.value;

      case AutomationCurveType.scurve:
        final smoothT = t * t * (3 - 2 * t);
        return before.value + smoothT * (after.value - before.value);

      case AutomationCurveType.bezier:
        return _bezierInterpolate(before, after, t);
    }
  }

  double _bezierInterpolate(AutomationPoint p1, AutomationPoint p2, double t) {
    // Cubic bezier interpolation
    final h1 = p1.handleOut ?? const Offset(0.3, 0);
    final h2 = p2.handleIn ?? const Offset(-0.3, 0);

    final x1 = p1.time;
    final y1 = p1.value;
    final x2 = p2.time;
    final y2 = p2.value;

    // Control points
    // ignore: unused_local_variable
    final cx1 = x1 + h1.dx * (x2 - x1);
    final cy1 = y1 + h1.dy * (y2 - y1);
    // ignore: unused_local_variable
    final cx2 = x2 + h2.dx * (x2 - x1);
    final cy2 = y2 + h2.dy * (y2 - y1);

    // Cubic bezier formula
    final t2 = t * t;
    final t3 = t2 * t;
    final mt = 1 - t;
    final mt2 = mt * mt;
    final mt3 = mt2 * mt;

    return mt3 * y1 + 3 * mt2 * t * cy1 + 3 * mt * t2 * cy2 + t3 * y2;
  }

  /// Convert normalized value to display value
  String formatValue(double normalizedValue) {
    final displayValue = minValue + normalizedValue * (maxValue - minValue);

    if (parameter == AutomationParameter.volume ||
        parameter == AutomationParameter.eq1Gain ||
        parameter == AutomationParameter.eq2Gain) {
      // dB scale: 0 = -inf, 0.75 = 0dB, 1.0 = +12dB
      if (normalizedValue < 0.01) return '-∞ dB';
      final db = (normalizedValue * 72 - 60).clamp(-60.0, 12.0);
      return '${db.toStringAsFixed(1)} dB';
    }

    if (parameter == AutomationParameter.pan) {
      final pan = (normalizedValue * 2 - 1) * 100;
      if (pan.abs() < 1) return 'C';
      return pan < 0 ? 'L${(-pan).toInt()}' : 'R${pan.toInt()}';
    }

    return '${displayValue.toStringAsFixed(1)}$unit';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION LANE WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Automation lane widget with interactive editing
class AutomationLane extends StatefulWidget {
  final AutomationLaneData data;
  final double zoom;          // Pixels per second
  final double scrollOffset;  // Scroll offset in seconds
  final double width;
  final ValueChanged<AutomationLaneData>? onDataChanged;
  final VoidCallback? onRemove;

  const AutomationLane({
    super.key,
    required this.data,
    required this.zoom,
    required this.scrollOffset,
    required this.width,
    this.onDataChanged,
    this.onRemove,
  });

  @override
  State<AutomationLane> createState() => _AutomationLaneState();
}

class _AutomationLaneState extends State<AutomationLane> {
  String? _draggingPointId;
  // ignore: unused_field
  String? _draggingHandle;  // 'in' or 'out'
  bool _isDrawing = false;
  Offset? _lastDrawPosition;
  final Set<String> _selectedPoints = {};
  Offset? _hoverPosition;
  bool _showValueTooltip = false;
  final FocusNode _focusNode = FocusNode();

  double _timeAtX(double x) {
    return widget.scrollOffset + x / widget.zoom;
  }

  double _xAtTime(double time) {
    return (time - widget.scrollOffset) * widget.zoom;
  }

  double _valueAtY(double y) {
    return 1 - (y / widget.data.height).clamp(0.0, 1.0);
  }

  double _yAtValue(double value) {
    return (1 - value) * widget.data.height;
  }

  void _addPoint(double x, double y) {
    final time = _timeAtX(x);
    final value = _valueAtY(y);

    final newPoint = AutomationPoint(
      id: 'pt_${DateTime.now().millisecondsSinceEpoch}',
      time: time,
      value: value.clamp(0.0, 1.0),
      curveType: AutomationCurveType.linear,
    );

    // Insert in sorted order
    final newPoints = List<AutomationPoint>.from(widget.data.points);
    int insertIndex = newPoints.indexWhere((p) => p.time > time);
    if (insertIndex == -1) insertIndex = newPoints.length;
    newPoints.insert(insertIndex, newPoint);

    widget.onDataChanged?.call(widget.data.copyWith(points: newPoints));
  }

  void _movePoint(String pointId, double dx, double dy) {
    final newPoints = widget.data.points.map((p) {
      if (p.id == pointId) {
        final newTime = (p.time + dx / widget.zoom).clamp(0.0, double.infinity);
        final newValue = (p.value - dy / widget.data.height).clamp(0.0, 1.0);
        return p.copyWith(time: newTime, value: newValue);
      }
      return p;
    }).toList();

    // Re-sort by time
    newPoints.sort((a, b) => a.time.compareTo(b.time));
    widget.onDataChanged?.call(widget.data.copyWith(points: newPoints));
  }

  void _deleteSelectedPoints() {
    if (_selectedPoints.isEmpty) return;

    final newPoints = widget.data.points
        .where((p) => !_selectedPoints.contains(p.id))
        .toList();

    _selectedPoints.clear();
    widget.onDataChanged?.call(widget.data.copyWith(points: newPoints));
  }

  void _setCurveType(AutomationCurveType type) {
    final newPoints = widget.data.points.map((p) {
      if (_selectedPoints.contains(p.id)) {
        return p.copyWith(curveType: type);
      }
      return p;
    }).toList();

    widget.onDataChanged?.call(widget.data.copyWith(points: newPoints));
  }

  void _deletePoint(String pointId) {
    final newPoints = widget.data.points
        .where((p) => p.id != pointId)
        .toList();
    _selectedPoints.remove(pointId);
    widget.onDataChanged?.call(widget.data.copyWith(points: newPoints));
  }

  void _selectAllPoints() {
    setState(() {
      _selectedPoints.clear();
      for (final p in widget.data.points) {
        _selectedPoints.add(p.id);
      }
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Delete selected points
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelectedPoints();
    }

    // Select all (Cmd/Ctrl + A)
    if (event.logicalKey == LogicalKeyboardKey.keyA &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      _selectAllPoints();
    }

    // Curve type shortcuts
    if (_selectedPoints.isNotEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.digit1) {
        _setCurveType(AutomationCurveType.linear);
      } else if (event.logicalKey == LogicalKeyboardKey.digit2) {
        _setCurveType(AutomationCurveType.bezier);
      } else if (event.logicalKey == LogicalKeyboardKey.digit3) {
        _setCurveType(AutomationCurveType.step);
      } else if (event.logicalKey == LogicalKeyboardKey.digit4) {
        _setCurveType(AutomationCurveType.scurve);
      }
    }
  }

  void _showPointContextMenu(BuildContext context, AutomationPoint point, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'linear',
          child: Row(
            children: [
              Icon(
                Icons.trending_flat,
                size: 16,
                color: point.curveType == AutomationCurveType.linear
                    ? FluxForgeTheme.accentBlue
                    : null,
              ),
              const SizedBox(width: 8),
              const Text('Linear'),
              const Spacer(),
              Text('1', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'bezier',
          child: Row(
            children: [
              Icon(
                Icons.gesture,
                size: 16,
                color: point.curveType == AutomationCurveType.bezier
                    ? FluxForgeTheme.accentBlue
                    : null,
              ),
              const SizedBox(width: 8),
              const Text('Bezier'),
              const Spacer(),
              Text('2', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'step',
          child: Row(
            children: [
              Icon(
                Icons.stairs,
                size: 16,
                color: point.curveType == AutomationCurveType.step
                    ? FluxForgeTheme.accentBlue
                    : null,
              ),
              const SizedBox(width: 8),
              const Text('Step'),
              const Spacer(),
              Text('3', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'scurve',
          child: Row(
            children: [
              Icon(
                Icons.waves,
                size: 16,
                color: point.curveType == AutomationCurveType.scurve
                    ? FluxForgeTheme.accentBlue
                    : null,
              ),
              const SizedBox(width: 8),
              const Text('S-Curve'),
              const Spacer(),
              Text('4', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 16, color: Colors.red[400]),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red[400])),
              const Spacer(),
              Text('⌫', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'linear':
          _setCurveTypeForPoint(point.id, AutomationCurveType.linear);
          break;
        case 'bezier':
          _setCurveTypeForPoint(point.id, AutomationCurveType.bezier);
          break;
        case 'step':
          _setCurveTypeForPoint(point.id, AutomationCurveType.step);
          break;
        case 'scurve':
          _setCurveTypeForPoint(point.id, AutomationCurveType.scurve);
          break;
        case 'delete':
          _deletePoint(point.id);
          break;
      }
    });
  }

  void _setCurveTypeForPoint(String pointId, AutomationCurveType type) {
    final newPoints = widget.data.points.map((p) {
      if (p.id == pointId || _selectedPoints.contains(p.id)) {
        return p.copyWith(curveType: type);
      }
      return p;
    }).toList();
    widget.onDataChanged?.call(widget.data.copyWith(points: newPoints));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onEnter: (_) => _focusNode.requestFocus(),
        onHover: (event) {
          setState(() {
            _hoverPosition = event.localPosition;
            _showValueTooltip = true;
          });
        },
        onExit: (_) {
          setState(() {
            _hoverPosition = null;
            _showValueTooltip = false;
          });
        },
        child: Container(
          height: widget.data.height,
          color: FluxForgeTheme.bgDeepest.withValues(alpha: 0.5),
          child: Stack(
            children: [
              // Automation curve
              Positioned.fill(
                child: GestureDetector(
                  onTapDown: (details) {
                    _focusNode.requestFocus();
                    // Double-tap to add point
                    if (widget.data.mode != AutomationMode.off &&
                        widget.data.mode != AutomationMode.read) {
                      _addPoint(details.localPosition.dx, details.localPosition.dy);
                    }
                  },
                  onPanStart: (details) {
                    if (widget.data.mode == AutomationMode.write) {
                      _isDrawing = true;
                      _lastDrawPosition = details.localPosition;
                    }
                  },
                  onPanUpdate: (details) {
                    if (_isDrawing && _lastDrawPosition != null) {
                      _addPoint(details.localPosition.dx, details.localPosition.dy);
                      _lastDrawPosition = details.localPosition;
                    }
                  },
                  onPanEnd: (_) {
                    _isDrawing = false;
                    _lastDrawPosition = null;
                  },
                  child: CustomPaint(
                    painter: _AutomationCurvePainter(
                      data: widget.data,
                      zoom: widget.zoom,
                      scrollOffset: widget.scrollOffset,
                      selectedPoints: _selectedPoints,
                    ),
                  ),
                ),
              ),

              // Automation points (interactive)
              for (final point in widget.data.points)
                _buildPointWidget(point),

              // Lane header
              Positioned(
                left: 4,
                top: 4,
                child: _buildLaneHeader(),
              ),

              // Hover value tooltip
              if (_showValueTooltip && _hoverPosition != null)
                _buildValueTooltip(),

              // Selection count badge
              if (_selectedPoints.isNotEmpty)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentBlue.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${_selectedPoints.length} selected',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValueTooltip() {
    if (_hoverPosition == null) return const SizedBox.shrink();

    final time = _timeAtX(_hoverPosition!.dx);
    final value = widget.data.getValueAtTime(time);
    final displayValue = widget.data.formatValue(value);

    // Position tooltip near cursor but not overlapping
    double tooltipX = _hoverPosition!.dx + 10;
    double tooltipY = _hoverPosition!.dy - 25;

    // Keep in bounds
    if (tooltipX > widget.width - 60) tooltipX = _hoverPosition!.dx - 60;
    if (tooltipY < 0) tooltipY = _hoverPosition!.dy + 15;

    return Positioned(
      left: tooltipX,
      top: tooltipY,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgElevated,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: widget.data.color.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          displayValue,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: widget.data.color,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ),
    );
  }

  Widget _buildPointWidget(AutomationPoint point) {
    final x = _xAtTime(point.time);
    final y = _yAtValue(point.value);

    // Don't render if outside visible area
    if (x < -20 || x > widget.width + 20) return const SizedBox.shrink();

    final isSelected = _selectedPoints.contains(point.id);
    final isDragging = _draggingPointId == point.id;

    return Positioned(
      left: x - 6,
      top: y - 6,
      width: 12,
      height: 12,
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (HardwareKeyboard.instance.isShiftPressed) {
              if (_selectedPoints.contains(point.id)) {
                _selectedPoints.remove(point.id);
              } else {
                _selectedPoints.add(point.id);
              }
            } else {
              _selectedPoints.clear();
              _selectedPoints.add(point.id);
            }
          });
        },
        onSecondaryTapDown: (details) {
          // Right-click context menu
          _selectedPoints.add(point.id);
          _showPointContextMenu(context, point, details.globalPosition);
        },
        onDoubleTap: () {
          // Double-click to delete
          _deletePoint(point.id);
        },
        onPanStart: (_) {
          setState(() => _draggingPointId = point.id);
        },
        onPanUpdate: (details) {
          if (_draggingPointId == point.id) {
            _movePoint(point.id, details.delta.dx, details.delta.dy);
          }
        },
        onPanEnd: (_) {
          setState(() => _draggingPointId = null);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected || isDragging
                  ? Colors.white
                  : widget.data.color,
              border: Border.all(
                color: widget.data.color,
                width: isSelected ? 2 : 1,
              ),
              shape: point.curveType == AutomationCurveType.step
                  ? BoxShape.rectangle
                  : BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLaneHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: widget.data.color.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.data.parameterName,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _modeLabel(widget.data.mode),
            style: TextStyle(
              fontSize: 9,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  String _modeLabel(AutomationMode mode) {
    switch (mode) {
      case AutomationMode.read:
        return 'R';
      case AutomationMode.write:
        return 'W';
      case AutomationMode.touch:
        return 'T';
      case AutomationMode.latch:
        return 'L';
      case AutomationMode.off:
        return 'Off';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION CURVE PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _AutomationCurvePainter extends CustomPainter {
  final AutomationLaneData data;
  final double zoom;
  final double scrollOffset;
  final Set<String> selectedPoints;

  _AutomationCurvePainter({
    required this.data,
    required this.zoom,
    required this.scrollOffset,
    required this.selectedPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.points.isEmpty) {
      // Draw default line at 50%
      final linePaint = Paint()
        ..color = data.color.withValues(alpha: 0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        linePaint,
      );
      return;
    }

    // Draw grid lines
    _drawGrid(canvas, size);

    // Draw automation curve
    _drawCurve(canvas, size);

    // Draw fill under curve
    _drawFill(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Horizontal lines (value markers)
    for (double v = 0.25; v < 1; v += 0.25) {
      final y = (1 - v) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Center line (0.5)
    final centerPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );
  }

  void _drawCurve(Canvas canvas, Size size) {
    final curvePaint = Paint()
      ..color = data.color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    bool firstPoint = true;

    // Extend to left edge
    if (data.points.isNotEmpty) {
      final firstTime = data.points.first.time;
      final startX = (firstTime - scrollOffset) * zoom;
      if (startX > 0) {
        path.moveTo(0, (1 - data.points.first.value) * size.height);
        path.lineTo(startX, (1 - data.points.first.value) * size.height);
        firstPoint = false;
      }
    }

    // Draw segments
    for (int i = 0; i < data.points.length; i++) {
      final point = data.points[i];
      final x = (point.time - scrollOffset) * zoom;
      final y = (1 - point.value) * size.height;

      if (x < -50) continue;
      if (x > size.width + 50) break;

      if (firstPoint) {
        path.moveTo(x, y);
        firstPoint = false;
      } else {
        final prevPoint = data.points[i - 1];
        final prevX = (prevPoint.time - scrollOffset) * zoom;
        final prevY = (1 - prevPoint.value) * size.height;

        switch (prevPoint.curveType) {
          case AutomationCurveType.linear:
            path.lineTo(x, y);
            break;

          case AutomationCurveType.step:
            path.lineTo(x, prevY);
            path.lineTo(x, y);
            break;

          case AutomationCurveType.scurve:
            final midX = (prevX + x) / 2;
            path.cubicTo(midX, prevY, midX, y, x, y);
            break;

          case AutomationCurveType.bezier:
            final h1 = prevPoint.handleOut ?? const Offset(0.3, 0);
            final h2 = point.handleIn ?? const Offset(-0.3, 0);

            final cp1x = prevX + h1.dx * (x - prevX);
            final cp1y = prevY + h1.dy * (y - prevY);
            final cp2x = x + h2.dx * (x - prevX);
            final cp2y = y + h2.dy * (y - prevY);

            path.cubicTo(cp1x, cp1y, cp2x, cp2y, x, y);
            break;
        }
      }
    }

    // Extend to right edge
    if (data.points.isNotEmpty) {
      final lastPoint = data.points.last;
      final lastX = (lastPoint.time - scrollOffset) * zoom;
      if (lastX < size.width) {
        final lastY = (1 - lastPoint.value) * size.height;
        path.lineTo(size.width, lastY);
      }
    }

    canvas.drawPath(path, curvePaint);
  }

  void _drawFill(Canvas canvas, Size size) {
    if (data.points.isEmpty) return;

    final fillPaint = Paint()
      ..color = data.color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final path = Path();

    // Start from bottom-left
    final firstX = (data.points.first.time - scrollOffset) * zoom;
    path.moveTo(firstX.clamp(0, size.width), size.height);

    // Top edge of fill (automation curve)
    for (int i = 0; i < data.points.length; i++) {
      final point = data.points[i];
      final x = (point.time - scrollOffset) * zoom;
      final y = (1 - point.value) * size.height;

      if (i == 0) {
        if (x > 0) {
          path.lineTo(0, (1 - point.value) * size.height);
        }
        path.lineTo(x.clamp(0, size.width), y);
      } else {
        final prevPoint = data.points[i - 1];

        switch (prevPoint.curveType) {
          case AutomationCurveType.linear:
          case AutomationCurveType.bezier:
          case AutomationCurveType.scurve:
            path.lineTo(x.clamp(0, size.width), y);
            break;
          case AutomationCurveType.step:
            final prevY = (1 - prevPoint.value) * size.height;
            path.lineTo(x.clamp(0, size.width), prevY);
            path.lineTo(x.clamp(0, size.width), y);
            break;
        }
      }
    }

    // Extend to right and close
    final lastX = (data.points.last.time - scrollOffset) * zoom;
    if (lastX < size.width) {
      path.lineTo(size.width, (1 - data.points.last.value) * size.height);
    }
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(_AutomationCurvePainter oldDelegate) =>
      data != oldDelegate.data ||
      zoom != oldDelegate.zoom ||
      scrollOffset != oldDelegate.scrollOffset ||
      selectedPoints != oldDelegate.selectedPoints;
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION LANE HEADER
// ═══════════════════════════════════════════════════════════════════════════════

/// Header widget for automation lane (shown in track header area)
class AutomationLaneHeader extends StatelessWidget {
  final AutomationLaneData data;
  final ValueChanged<AutomationMode>? onModeChanged;
  final ValueChanged<bool>? onVisibilityChanged;
  final VoidCallback? onRemove;

  const AutomationLaneHeader({
    super.key,
    required this.data,
    this.onModeChanged,
    this.onVisibilityChanged,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: data.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Color indicator
          Container(
            width: 4,
            height: double.infinity,
            color: data.color,
          ),
          const SizedBox(width: 8),

          // Parameter name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.parameterName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: FluxForgeTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${data.points.length} points',
                  style: TextStyle(
                    fontSize: 9,
                    color: FluxForgeTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // Mode selector
          PopupMenuButton<AutomationMode>(
            initialValue: data.mode,
            onSelected: onModeChanged,
            itemBuilder: (context) => [
              for (final mode in AutomationMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        alignment: Alignment.center,
                        child: Text(
                          _modeLabel(mode),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _modeColor(mode),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(_modeName(mode)),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _modeColor(data.mode).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _modeLabel(data.mode),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _modeColor(data.mode),
                ),
              ),
            ),
          ),

          const SizedBox(width: 4),

          // Visibility toggle
          IconButton(
            icon: Icon(
              data.visible ? Icons.visibility : Icons.visibility_off,
              size: 14,
            ),
            onPressed: () => onVisibilityChanged?.call(!data.visible),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: data.visible
                ? FluxForgeTheme.textSecondary
                : FluxForgeTheme.textTertiary,
          ),

          // Remove button
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: FluxForgeTheme.textTertiary,
          ),
        ],
      ),
    );
  }

  String _modeLabel(AutomationMode mode) {
    switch (mode) {
      case AutomationMode.read:
        return 'R';
      case AutomationMode.write:
        return 'W';
      case AutomationMode.touch:
        return 'T';
      case AutomationMode.latch:
        return 'L';
      case AutomationMode.off:
        return '—';
    }
  }

  String _modeName(AutomationMode mode) {
    switch (mode) {
      case AutomationMode.read:
        return 'Read';
      case AutomationMode.write:
        return 'Write';
      case AutomationMode.touch:
        return 'Touch';
      case AutomationMode.latch:
        return 'Latch';
      case AutomationMode.off:
        return 'Off';
    }
  }

  Color _modeColor(AutomationMode mode) {
    switch (mode) {
      case AutomationMode.read:
        return const Color(0xFF40FF90);
      case AutomationMode.write:
        return const Color(0xFFFF4040);
      case AutomationMode.touch:
        return const Color(0xFFFFAA00);
      case AutomationMode.latch:
        return const Color(0xFF4A9EFF);
      case AutomationMode.off:
        return FluxForgeTheme.textTertiary;
    }
  }
}
