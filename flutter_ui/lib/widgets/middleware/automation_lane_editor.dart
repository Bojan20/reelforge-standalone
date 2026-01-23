/// FluxForge Studio Automation Lane Editor
///
/// P4.8: Automation Lane Editor
/// - Timeline-based automation editing
/// - Multiple lanes per parameter
/// - Control point editing (add, move, delete)
/// - Curve interpolation between points
/// - Snap to grid
/// - Copy/paste automation
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/middleware_models.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION DATA MODELS
// ═══════════════════════════════════════════════════════════════════════════════

/// A single automation point
class AutomationPoint {
  final double time; // Seconds
  final double value; // 0.0 - 1.0 normalized
  final RtpcCurveShape curve; // Interpolation to next point

  const AutomationPoint({
    required this.time,
    required this.value,
    this.curve = RtpcCurveShape.linear,
  });

  AutomationPoint copyWith({
    double? time,
    double? value,
    RtpcCurveShape? curve,
  }) {
    return AutomationPoint(
      time: time ?? this.time,
      value: value ?? this.value,
      curve: curve ?? this.curve,
    );
  }
}

/// An automation lane for a single parameter
class AutomationLane {
  final String id;
  final String name;
  final RtpcTargetParameter target;
  final List<AutomationPoint> points;
  final Color color;
  final bool visible;
  final bool locked;
  final double minValue;
  final double maxValue;

  const AutomationLane({
    required this.id,
    required this.name,
    required this.target,
    this.points = const [],
    this.color = const Color(0xFF4A9EFF),
    this.visible = true,
    this.locked = false,
    this.minValue = 0.0,
    this.maxValue = 1.0,
  });

  AutomationLane copyWith({
    String? id,
    String? name,
    RtpcTargetParameter? target,
    List<AutomationPoint>? points,
    Color? color,
    bool? visible,
    bool? locked,
    double? minValue,
    double? maxValue,
  }) {
    return AutomationLane(
      id: id ?? this.id,
      name: name ?? this.name,
      target: target ?? this.target,
      points: points ?? this.points,
      color: color ?? this.color,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
    );
  }

  /// Evaluate automation at given time
  double evaluate(double time) {
    if (points.isEmpty) return (minValue + maxValue) / 2;
    if (points.length == 1) return points.first.value;

    // Find surrounding points
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];

      if (time >= p0.time && time <= p1.time) {
        final t = (time - p0.time) / (p1.time - p0.time);
        return _interpolate(p0.value, p1.value, t, p0.curve);
      }
    }

    // Outside range
    if (time < points.first.time) return points.first.value;
    return points.last.value;
  }

  double _interpolate(double v0, double v1, double t, RtpcCurveShape curve) {
    final shaped = _applyShape(t, curve);
    return v0 + (v1 - v0) * shaped;
  }

  double _applyShape(double t, RtpcCurveShape shape) {
    switch (shape) {
      case RtpcCurveShape.linear:
        return t;
      case RtpcCurveShape.log3:
        return 1.0 - math.pow(1.0 - t, 3).toDouble();
      case RtpcCurveShape.log1:
        return 1.0 - math.pow(1.0 - t, 1.5).toDouble();
      case RtpcCurveShape.sine:
        return 0.5 - 0.5 * math.cos(t * math.pi);
      case RtpcCurveShape.exp1:
        return t == 0 ? 0.0 : math.pow(2, 10 * t - 10).toDouble();
      case RtpcCurveShape.exp3:
        return math.pow(t, 3).toDouble();
      case RtpcCurveShape.sCurve:
        return t < 0.5 ? 2.0 * t * t : 1.0 - math.pow(-2.0 * t + 2.0, 2).toDouble() / 2.0;
      case RtpcCurveShape.invSCurve:
        return t < 0.5 ? math.pow(2 * t, 2).toDouble() / 2.0 : 1.0 - math.pow(-2.0 * t + 2.0, 2).toDouble() / 2.0;
      case RtpcCurveShape.constant:
        return t < 0.5 ? 0.0 : 1.0;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AUTOMATION LANE EDITOR
// ═══════════════════════════════════════════════════════════════════════════════

class AutomationLaneEditor extends StatefulWidget {
  final List<AutomationLane> lanes;
  final double duration; // Total duration in seconds
  final double currentTime; // Playhead position
  final ValueChanged<List<AutomationLane>>? onLanesChanged;
  final ValueChanged<double>? onSeek;
  final double height;
  final double laneHeight;

  const AutomationLaneEditor({
    super.key,
    required this.lanes,
    required this.duration,
    this.currentTime = 0.0,
    this.onLanesChanged,
    this.onSeek,
    this.height = 300,
    this.laneHeight = 80,
  });

  @override
  State<AutomationLaneEditor> createState() => _AutomationLaneEditorState();
}

class _AutomationLaneEditorState extends State<AutomationLaneEditor> {
  late List<AutomationLane> _lanes;
  int? _selectedLaneIndex;
  int? _selectedPointIndex;
  int? _hoveredPointIndex;
  int? _hoveredLaneIndex;
  double _zoom = 100.0; // Pixels per second
  double _scrollOffset = 0.0;
  bool _snapToGrid = true;
  double _gridSize = 0.25; // Seconds

  // Drag state
  bool _isDragging = false;
  Offset? _dragStartPosition;
  double? _dragStartTime;
  double? _dragStartValue;

  @override
  void initState() {
    super.initState();
    _lanes = List.from(widget.lanes);
  }

  @override
  void didUpdateWidget(AutomationLaneEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lanes != oldWidget.lanes) {
      _lanes = List.from(widget.lanes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Toolbar
          _buildToolbar(),
          // Lanes
          Expanded(
            child: Row(
              children: [
                // Lane labels (left)
                SizedBox(
                  width: 120,
                  child: _buildLaneLabels(),
                ),
                // Divider
                Container(width: 1, color: FluxForgeTheme.borderSubtle),
                // Timeline + lanes (right)
                Expanded(
                  child: _buildTimelineArea(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          // Add lane
          IconButton(
            icon: Icon(Icons.add, size: 18, color: FluxForgeTheme.accent),
            tooltip: 'Add Lane',
            onPressed: _addLane,
          ),
          const SizedBox(width: 8),
          // Snap toggle
          IconButton(
            icon: Icon(
              Icons.grid_on,
              size: 18,
              color: _snapToGrid ? FluxForgeTheme.accent : FluxForgeTheme.textMuted,
            ),
            tooltip: 'Snap to Grid',
            onPressed: () => setState(() => _snapToGrid = !_snapToGrid),
          ),
          // Grid size
          PopupMenuButton<double>(
            initialValue: _gridSize,
            tooltip: 'Grid Size',
            onSelected: (size) => setState(() => _gridSize = size),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                _formatGridSize(_gridSize),
                style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
              ),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 0.0625, child: Text('1/16')),
              const PopupMenuItem(value: 0.125, child: Text('1/8')),
              const PopupMenuItem(value: 0.25, child: Text('1/4')),
              const PopupMenuItem(value: 0.5, child: Text('1/2')),
              const PopupMenuItem(value: 1.0, child: Text('1 bar')),
            ],
          ),
          const Spacer(),
          // Zoom controls
          IconButton(
            icon: Icon(Icons.remove, size: 18, color: FluxForgeTheme.textMuted),
            tooltip: 'Zoom Out',
            onPressed: () => setState(() => _zoom = (_zoom * 0.8).clamp(20.0, 500.0)),
          ),
          Text(
            '${(_zoom / 100 * 100).toStringAsFixed(0)}%',
            style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 11),
          ),
          IconButton(
            icon: Icon(Icons.add, size: 18, color: FluxForgeTheme.textMuted),
            tooltip: 'Zoom In',
            onPressed: () => setState(() => _zoom = (_zoom * 1.2).clamp(20.0, 500.0)),
          ),
          const SizedBox(width: 8),
          // Delete selected
          if (_selectedLaneIndex != null && _selectedPointIndex != null)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: FluxForgeTheme.errorRed),
              tooltip: 'Delete Point',
              onPressed: _deleteSelectedPoint,
            ),
        ],
      ),
    );
  }

  Widget _buildLaneLabels() {
    return ListView.builder(
      itemCount: _lanes.length,
      itemBuilder: (context, index) {
        final lane = _lanes[index];
        final isSelected = index == _selectedLaneIndex;

        return GestureDetector(
          onTap: () => setState(() => _selectedLaneIndex = index),
          child: Container(
            height: widget.laneHeight,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? FluxForgeTheme.surface : Colors.transparent,
              border: Border(
                bottom: BorderSide(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Color indicator
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: lane.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Name
                    Expanded(
                      child: Text(
                        lane.name,
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Target
                Text(
                  lane.target.displayName,
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 9,
                  ),
                ),
                const Spacer(),
                // Controls
                Row(
                  children: [
                    // Visibility toggle
                    IconButton(
                      icon: Icon(
                        lane.visible ? Icons.visibility : Icons.visibility_off,
                        size: 14,
                        color: lane.visible ? FluxForgeTheme.accent : FluxForgeTheme.textMuted,
                      ),
                      onPressed: () => _toggleLaneVisibility(index),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(width: 8),
                    // Lock toggle
                    IconButton(
                      icon: Icon(
                        lane.locked ? Icons.lock : Icons.lock_open,
                        size: 14,
                        color: lane.locked ? FluxForgeTheme.errorRed : FluxForgeTheme.textMuted,
                      ),
                      onPressed: () => _toggleLaneLock(index),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                    const Spacer(),
                    // Delete lane
                    IconButton(
                      icon: Icon(Icons.close, size: 14, color: FluxForgeTheme.textMuted),
                      onPressed: () => _deleteLane(index),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimelineArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final totalWidth = widget.duration * _zoom;

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _scrollOffset = (_scrollOffset - details.delta.dx).clamp(0.0, math.max(0, totalWidth - width));
            });
          },
          child: Stack(
            children: [
              // Grid
              CustomPaint(
                size: Size(width, constraints.maxHeight),
                painter: _GridPainter(
                  scrollOffset: _scrollOffset,
                  zoom: _zoom,
                  duration: widget.duration,
                  gridSize: _gridSize,
                  laneHeight: widget.laneHeight,
                  laneCount: _lanes.length,
                ),
              ),
              // Lanes
              ...List.generate(_lanes.length, (laneIndex) {
                final lane = _lanes[laneIndex];
                if (!lane.visible) return const SizedBox.shrink();

                return Positioned(
                  top: laneIndex * widget.laneHeight,
                  left: 0,
                  right: 0,
                  height: widget.laneHeight,
                  child: _buildLaneContent(laneIndex, lane, width),
                );
              }),
              // Playhead
              Positioned(
                left: (widget.currentTime * _zoom) - _scrollOffset,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: FluxForgeTheme.errorRed,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLaneContent(int laneIndex, AutomationLane lane, double viewWidth) {
    return GestureDetector(
      onTapDown: (details) {
        if (lane.locked) return;
        final time = _xToTime(details.localPosition.dx);
        final value = _yToValue(details.localPosition.dy, widget.laneHeight);

        // Check if clicking on existing point
        final pointIndex = _findPointAt(lane, details.localPosition, viewWidth);
        if (pointIndex != null) {
          setState(() {
            _selectedLaneIndex = laneIndex;
            _selectedPointIndex = pointIndex;
          });
        } else {
          // Add new point
          _addPoint(laneIndex, time, value);
        }
      },
      onPanStart: (details) {
        if (lane.locked) return;
        final pointIndex = _findPointAt(lane, details.localPosition, viewWidth);
        if (pointIndex != null) {
          setState(() {
            _isDragging = true;
            _selectedLaneIndex = laneIndex;
            _selectedPointIndex = pointIndex;
            _dragStartPosition = details.localPosition;
            _dragStartTime = lane.points[pointIndex].time;
            _dragStartValue = lane.points[pointIndex].value;
          });
        }
      },
      onPanUpdate: (details) {
        if (!_isDragging || _selectedPointIndex == null) return;
        _moveSelectedPoint(details.localPosition, widget.laneHeight);
      },
      onPanEnd: (_) {
        setState(() => _isDragging = false);
      },
      child: CustomPaint(
        size: Size(viewWidth, widget.laneHeight),
        painter: _AutomationLanePainter(
          lane: lane,
          scrollOffset: _scrollOffset,
          zoom: _zoom,
          laneHeight: widget.laneHeight,
          selectedPointIndex: _selectedLaneIndex == laneIndex ? _selectedPointIndex : null,
          hoveredPointIndex: _hoveredLaneIndex == laneIndex ? _hoveredPointIndex : null,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════════

  void _addLane() {
    final newLane = AutomationLane(
      id: 'lane_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Lane ${_lanes.length + 1}',
      target: RtpcTargetParameter.volume,
      color: _getRandomColor(),
    );
    setState(() {
      _lanes = [..._lanes, newLane];
    });
    _notifyChange();
  }

  void _deleteLane(int index) {
    setState(() {
      _lanes = [..._lanes]..removeAt(index);
      if (_selectedLaneIndex == index) {
        _selectedLaneIndex = null;
        _selectedPointIndex = null;
      }
    });
    _notifyChange();
  }

  void _toggleLaneVisibility(int index) {
    final lane = _lanes[index];
    setState(() {
      _lanes = [..._lanes]..[index] = lane.copyWith(visible: !lane.visible);
    });
    _notifyChange();
  }

  void _toggleLaneLock(int index) {
    final lane = _lanes[index];
    setState(() {
      _lanes = [..._lanes]..[index] = lane.copyWith(locked: !lane.locked);
    });
    _notifyChange();
  }

  void _addPoint(int laneIndex, double time, double value) {
    final lane = _lanes[laneIndex];
    final snappedTime = _snapToGrid ? _snapTime(time) : time;
    final newPoint = AutomationPoint(time: snappedTime, value: value);

    // Insert in sorted order
    final newPoints = [...lane.points, newPoint]..sort((a, b) => a.time.compareTo(b.time));

    setState(() {
      _lanes = [..._lanes]..[laneIndex] = lane.copyWith(points: newPoints);
      _selectedLaneIndex = laneIndex;
      _selectedPointIndex = newPoints.indexOf(newPoint);
    });
    _notifyChange();
  }

  void _deleteSelectedPoint() {
    if (_selectedLaneIndex == null || _selectedPointIndex == null) return;

    final lane = _lanes[_selectedLaneIndex!];
    final newPoints = [...lane.points]..removeAt(_selectedPointIndex!);

    setState(() {
      _lanes = [..._lanes]..[_selectedLaneIndex!] = lane.copyWith(points: newPoints);
      _selectedPointIndex = null;
    });
    _notifyChange();
  }

  void _moveSelectedPoint(Offset position, double laneHeight) {
    if (_selectedLaneIndex == null || _selectedPointIndex == null) return;

    final lane = _lanes[_selectedLaneIndex!];
    var time = _xToTime(position.dx);
    var value = _yToValue(position.dy, laneHeight);

    if (_snapToGrid) {
      time = _snapTime(time);
    }

    time = time.clamp(0.0, widget.duration);
    value = value.clamp(0.0, 1.0);

    final newPoints = [...lane.points];
    newPoints[_selectedPointIndex!] = newPoints[_selectedPointIndex!].copyWith(
      time: time,
      value: value,
    );

    // Keep sorted
    newPoints.sort((a, b) => a.time.compareTo(b.time));

    setState(() {
      _lanes = [..._lanes]..[_selectedLaneIndex!] = lane.copyWith(points: newPoints);
      // Update selected index after sort
      _selectedPointIndex = newPoints.indexWhere((p) => p.time == time && p.value == value);
    });
    _notifyChange();
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════════

  double _xToTime(double x) {
    return (x + _scrollOffset) / _zoom;
  }

  double _yToValue(double y, double laneHeight) {
    return 1.0 - (y / laneHeight).clamp(0.0, 1.0);
  }

  double _snapTime(double time) {
    return (time / _gridSize).round() * _gridSize;
  }

  int? _findPointAt(AutomationLane lane, Offset position, double viewWidth) {
    const hitRadius = 8.0;

    for (int i = 0; i < lane.points.length; i++) {
      final point = lane.points[i];
      final px = (point.time * _zoom) - _scrollOffset;
      final py = (1.0 - point.value) * widget.laneHeight;

      final distance = (Offset(px, py) - position).distance;
      if (distance < hitRadius) {
        return i;
      }
    }
    return null;
  }

  String _formatGridSize(double size) {
    if (size == 1.0) return '1 bar';
    if (size == 0.5) return '1/2';
    if (size == 0.25) return '1/4';
    if (size == 0.125) return '1/8';
    if (size == 0.0625) return '1/16';
    return '${size}s';
  }

  Color _getRandomColor() {
    final colors = [
      const Color(0xFF4A9EFF),
      const Color(0xFFFF9040),
      const Color(0xFF40FF90),
      const Color(0xFFFF4060),
      const Color(0xFF40C8FF),
      const Color(0xFF9040FF),
    ];
    return colors[math.Random().nextInt(colors.length)];
  }

  void _notifyChange() {
    widget.onLanesChanged?.call(_lanes);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _GridPainter extends CustomPainter {
  final double scrollOffset;
  final double zoom;
  final double duration;
  final double gridSize;
  final double laneHeight;
  final int laneCount;

  _GridPainter({
    required this.scrollOffset,
    required this.zoom,
    required this.duration,
    required this.gridSize,
    required this.laneHeight,
    required this.laneCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final majorGridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    final minorGridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.2)
      ..strokeWidth = 0.5;

    final laneDividerPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    // Vertical grid lines
    final startTime = (scrollOffset / zoom / gridSize).floor() * gridSize;
    final endTime = ((scrollOffset + size.width) / zoom / gridSize).ceil() * gridSize;

    for (double t = startTime; t <= endTime; t += gridSize) {
      final x = (t * zoom) - scrollOffset;
      final isMajor = (t % 1.0).abs() < 0.001;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? majorGridPaint : minorGridPaint,
      );
    }

    // Horizontal lane dividers
    for (int i = 0; i <= laneCount; i++) {
      final y = i * laneHeight;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        laneDividerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      scrollOffset != oldDelegate.scrollOffset ||
      zoom != oldDelegate.zoom ||
      gridSize != oldDelegate.gridSize ||
      laneCount != oldDelegate.laneCount;
}

class _AutomationLanePainter extends CustomPainter {
  final AutomationLane lane;
  final double scrollOffset;
  final double zoom;
  final double laneHeight;
  final int? selectedPointIndex;
  final int? hoveredPointIndex;

  _AutomationLanePainter({
    required this.lane,
    required this.scrollOffset,
    required this.zoom,
    required this.laneHeight,
    this.selectedPointIndex,
    this.hoveredPointIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (lane.points.isEmpty) return;

    // Draw curve
    final path = Path();
    bool started = false;

    // Sample curve at regular intervals
    for (double t = 0; t <= lane.points.last.time + 0.01; t += 0.01) {
      final x = (t * zoom) - scrollOffset;
      if (x < -10 || x > size.width + 10) continue;

      final value = lane.evaluate(t);
      final y = (1.0 - value) * laneHeight;

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    // Fill under curve
    final fillPath = Path.from(path);
    if (started && lane.points.isNotEmpty) {
      final lastX = (lane.points.last.time * zoom) - scrollOffset;
      fillPath.lineTo(lastX, laneHeight);
      final firstX = (lane.points.first.time * zoom) - scrollOffset;
      fillPath.lineTo(firstX, laneHeight);
      fillPath.close();

      final fillPaint = Paint()
        ..color = lane.color.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, fillPaint);
    }

    // Draw curve line
    final curvePaint = Paint()
      ..color = lane.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, curvePaint);

    // Draw points
    for (int i = 0; i < lane.points.length; i++) {
      final point = lane.points[i];
      final x = (point.time * zoom) - scrollOffset;
      if (x < -20 || x > size.width + 20) continue;

      final y = (1.0 - point.value) * laneHeight;
      final isSelected = i == selectedPointIndex;
      final isHovered = i == hoveredPointIndex;

      // Point circle
      final pointPaint = Paint()
        ..color = isSelected ? Colors.white : lane.color
        ..style = PaintingStyle.fill;

      final outlinePaint = Paint()
        ..color = lane.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3 : 2;

      final radius = isSelected ? 7.0 : (isHovered ? 6.0 : 5.0);

      canvas.drawCircle(Offset(x, y), radius, pointPaint);
      canvas.drawCircle(Offset(x, y), radius, outlinePaint);
    }
  }

  @override
  bool shouldRepaint(_AutomationLanePainter oldDelegate) =>
      lane != oldDelegate.lane ||
      scrollOffset != oldDelegate.scrollOffset ||
      zoom != oldDelegate.zoom ||
      selectedPointIndex != oldDelegate.selectedPointIndex ||
      hoveredPointIndex != oldDelegate.hoveredPointIndex;
}
