/// Visual State Machine Graph
///
/// Node-based visual editor for state groups:
/// - Nodes represent states
/// - Arrows show possible transitions
/// - Current state highlighted
/// - Click to change state
/// - Zoom/pan canvas

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/middleware_models.dart';
import '../../theme/fluxforge_theme.dart';

/// Visual state machine graph widget
class StateMachineGraph extends StatefulWidget {
  /// The state group to display
  final StateGroup? stateGroup;

  /// Callback when user requests a state change
  final Function(int groupId, int stateId)? onStateChangeRequested;

  /// Whether to show transition arrows
  final bool showTransitions;

  const StateMachineGraph({
    super.key,
    this.stateGroup,
    this.onStateChangeRequested,
    this.showTransitions = true,
  });

  @override
  State<StateMachineGraph> createState() => _StateMachineGraphState();
}

class _StateMachineGraphState extends State<StateMachineGraph>
    with SingleTickerProviderStateMixin {
  // Canvas transformation
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  // Node positions (calculated on layout)
  Map<int, Offset> _nodePositions = {};

  // Selected state
  int? _selectedStateId;

  // Animation for transition arrows
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _calculateNodePositions();
  }

  @override
  void didUpdateWidget(StateMachineGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stateGroup?.id != widget.stateGroup?.id ||
        oldWidget.stateGroup?.states.length !=
            widget.stateGroup?.states.length) {
      _calculateNodePositions();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _calculateNodePositions() {
    final group = widget.stateGroup;
    if (group == null || group.states.isEmpty) {
      _nodePositions = {};
      return;
    }

    // Circular layout
    const double radius = 150.0;
    const double centerX = 200.0;
    const double centerY = 200.0;

    _nodePositions = {};
    for (int i = 0; i < group.states.length; i++) {
      final angle = (2 * math.pi * i) / group.states.length - math.pi / 2;
      final x = centerX + radius * math.cos(angle);
      final y = centerY + radius * math.sin(angle);
      _nodePositions[group.states[i].id] = Offset(x, y);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.stateGroup;

    if (group == null) {
      return _buildEmptyState();
    }

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(group),
          Expanded(
            child: _buildCanvas(group),
          ),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 48,
              color: FluxForgeTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'Select a State Group',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(StateGroup group) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.bgDeep),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_tree,
            size: 16,
            color: FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 8),
          Text(
            group.name,
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentGreen.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Current: ${group.currentStateName}',
              style: TextStyle(
                color: FluxForgeTheme.accentGreen,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 16),
            onPressed: () => setState(() => _scale = (_scale - 0.1).clamp(0.5, 2.0)),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Text(
            '${(_scale * 100).round()}%',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 16),
            onPressed: () => setState(() => _scale = (_scale + 0.1).clamp(0.5, 2.0)),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong, size: 16),
            onPressed: () => setState(() {
              _scale = 1.0;
              _offset = Offset.zero;
            }),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Reset view',
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(StateGroup group) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _offset += details.delta;
        });
      },
      child: ClipRect(
        child: CustomPaint(
          painter: _GraphPainter(
            states: group.states,
            positions: _nodePositions,
            currentStateId: group.currentStateId,
            selectedStateId: _selectedStateId,
            defaultStateId: group.defaultStateId,
            scale: _scale,
            offset: _offset,
            showTransitions: widget.showTransitions,
            animationValue: _animationController.value,
          ),
          child: Stack(
            children: [
              // State nodes
              for (final state in group.states)
                if (_nodePositions.containsKey(state.id))
                  _buildStateNode(group, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateNode(StateGroup group, StateDefinition state) {
    final position = _nodePositions[state.id]!;
    final isCurrent = state.id == group.currentStateId;
    final isSelected = state.id == _selectedStateId;
    final isDefault = state.id == group.defaultStateId;

    return Positioned(
      left: (position.dx - 40) * _scale + _offset.dx,
      top: (position.dy - 25) * _scale + _offset.dy,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedStateId = state.id);
        },
        onDoubleTap: () {
          widget.onStateChangeRequested?.call(group.id, state.id);
        },
        child: Container(
          width: 80 * _scale,
          height: 50 * _scale,
          decoration: BoxDecoration(
            color: isCurrent
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8 * _scale),
            border: Border.all(
              color: isSelected
                  ? FluxForgeTheme.accentOrange
                  : isCurrent
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.bgSurface,
              width: isSelected || isCurrent ? 2 : 1,
            ),
            boxShadow: isCurrent
                ? [
                    BoxShadow(
                      color: FluxForgeTheme.accentBlue.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isDefault)
                Icon(
                  Icons.star,
                  size: 10 * _scale,
                  color: FluxForgeTheme.accentOrange,
                ),
              Text(
                state.name,
                style: TextStyle(
                  color: isCurrent
                      ? FluxForgeTheme.textPrimary
                      : FluxForgeTheme.textSecondary,
                  fontSize: 11 * _scale,
                  fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.bgDeep),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem(FluxForgeTheme.accentBlue, 'Current'),
          const SizedBox(width: 16),
          _buildLegendItem(FluxForgeTheme.accentOrange, 'Selected'),
          const SizedBox(width: 16),
          _buildLegendItem(FluxForgeTheme.bgSurface, 'Inactive'),
          const SizedBox(width: 16),
          Icon(Icons.star, size: 12, color: FluxForgeTheme.accentOrange),
          const SizedBox(width: 4),
          Text(
            'Default',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<StateDefinition> states;
  final Map<int, Offset> positions;
  final int currentStateId;
  final int? selectedStateId;
  final int defaultStateId;
  final double scale;
  final Offset offset;
  final bool showTransitions;
  final double animationValue;

  _GraphPainter({
    required this.states,
    required this.positions,
    required this.currentStateId,
    this.selectedStateId,
    required this.defaultStateId,
    required this.scale,
    required this.offset,
    required this.showTransitions,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!showTransitions || states.length < 2) return;

    // Draw transition arrows between all states (simplified - all states can transition to any other)
    final paint = Paint()
      ..color = FluxForgeTheme.textSecondary.withOpacity(0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < states.length; i++) {
      final fromId = states[i].id;
      final toId = states[(i + 1) % states.length].id;

      final from = positions[fromId];
      final to = positions[toId];
      if (from == null || to == null) continue;

      // Transform positions
      final transformedFrom = from * scale + offset;
      final transformedTo = to * scale + offset;

      // Draw curved arrow
      _drawArrow(canvas, transformedFrom, transformedTo, paint);
    }

    // Highlight current state transitions
    if (positions.containsKey(currentStateId)) {
      final activePaint = Paint()
        ..color = FluxForgeTheme.accentBlue.withOpacity(0.5)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final from = positions[currentStateId]! * scale + offset;

      // Draw animated arrows from current state
      for (final state in states) {
        if (state.id == currentStateId) continue;
        final to = positions[state.id];
        if (to == null) continue;

        final transformedTo = to * scale + offset;
        _drawAnimatedArrow(canvas, from, transformedTo, activePaint);
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    final path = Path();

    // Calculate control point for curve
    final mid = (from + to) / 2;
    final perpendicular = Offset(-(to.dy - from.dy), to.dx - from.dx).normalized * 20;
    final control = mid + perpendicular;

    path.moveTo(from.dx, from.dy);
    path.quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);

    canvas.drawPath(path, paint);

    // Draw arrowhead
    final direction = (to - control).normalized;
    final arrowSize = 8.0;
    final arrowPoint1 = to - direction * arrowSize + Offset(-direction.dy, direction.dx) * arrowSize / 2;
    final arrowPoint2 = to - direction * arrowSize - Offset(-direction.dy, direction.dx) * arrowSize / 2;

    final arrowPath = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(arrowPoint1.dx, arrowPoint1.dy)
      ..lineTo(arrowPoint2.dx, arrowPoint2.dy)
      ..close();

    canvas.drawPath(arrowPath, paint..style = PaintingStyle.fill);
  }

  void _drawAnimatedArrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    // Draw dash with animation offset
    final path = Path();

    final mid = (from + to) / 2;
    final perpendicular = Offset(-(to.dy - from.dy), to.dx - from.dx).normalized * 25;
    final control = mid + perpendicular;

    path.moveTo(from.dx, from.dy);
    path.quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);

    // Animate dash offset
    final dashLength = 10.0;
    final dashOffset = animationValue * dashLength * 2;

    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      var distance = dashOffset;
      while (distance < metric.length) {
        final extractPath = metric.extractPath(distance, distance + dashLength);
        canvas.drawPath(extractPath, paint);
        distance += dashLength * 2;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.currentStateId != currentStateId ||
        oldDelegate.selectedStateId != selectedStateId ||
        oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.animationValue != animationValue;
  }
}

extension _OffsetNormalized on Offset {
  Offset get normalized {
    final length = distance;
    if (length == 0) return Offset.zero;
    return this / length;
  }
}
