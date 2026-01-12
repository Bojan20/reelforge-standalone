// Sidechain Routing Visualization Panel
//
// Professional sidechain routing display with:
// - Visual connection lines between source and target
// - Drag-and-drop routing
// - Activity indicators
// - Gain reduction meter
// - Quick enable/disable
// - Multiple sidechain sources

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Sidechain connection data
class SidechainConnection {
  final String id;
  final String sourceId;
  final String sourceName;
  final String targetId;
  final String targetName;
  final String pluginId;
  final String pluginName;
  final bool isActive;
  final double gainReduction; // dB (negative)

  SidechainConnection({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    required this.targetId,
    required this.targetName,
    required this.pluginId,
    required this.pluginName,
    this.isActive = true,
    this.gainReduction = 0,
  });

  SidechainConnection copyWith({
    bool? isActive,
    double? gainReduction,
  }) {
    return SidechainConnection(
      id: id,
      sourceId: sourceId,
      sourceName: sourceName,
      targetId: targetId,
      targetName: targetName,
      pluginId: pluginId,
      pluginName: pluginName,
      isActive: isActive ?? this.isActive,
      gainReduction: gainReduction ?? this.gainReduction,
    );
  }
}

/// Channel for sidechain routing
class RoutingChannel {
  final String id;
  final String name;
  final Color color;
  final bool canBeSource;
  final bool canBeTarget;
  final List<String> availableInputs;

  RoutingChannel({
    required this.id,
    required this.name,
    required this.color,
    this.canBeSource = true,
    this.canBeTarget = true,
    this.availableInputs = const [],
  });
}

/// Sidechain Routing Panel Widget
class SidechainRoutingPanel extends StatefulWidget {
  final List<SidechainConnection> connections;
  final List<RoutingChannel> channels;
  final void Function(String sourceId, String targetId, String pluginId)? onCreateConnection;
  final void Function(String connectionId)? onDeleteConnection;
  final void Function(String connectionId, bool active)? onToggleConnection;

  const SidechainRoutingPanel({
    super.key,
    required this.connections,
    required this.channels,
    this.onCreateConnection,
    this.onDeleteConnection,
    this.onToggleConnection,
  });

  @override
  State<SidechainRoutingPanel> createState() => _SidechainRoutingPanelState();
}

class _SidechainRoutingPanelState extends State<SidechainRoutingPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  String? _hoveredConnection;
  String? _draggingFromChannel;
  Offset? _dragPosition;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          Expanded(
            child: widget.connections.isEmpty
                ? _buildEmptyState()
                : _buildRoutingView(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: FluxForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.call_split, color: FluxForgeTheme.accentCyan, size: 18),
          const SizedBox(width: 8),
          const Text(
            'SIDECHAIN ROUTING',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            '${widget.connections.length} connections',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call_split, size: 48, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          const Text(
            'No sidechain connections',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add a compressor/gate with sidechain input\nto create connections',
            style: TextStyle(color: Colors.white24, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRoutingView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Connection lines
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _ConnectionLinesPainter(
                connections: widget.connections,
                channels: widget.channels,
                hoveredConnection: _hoveredConnection,
                animation: _pulseController,
              ),
            ),
            // Connection list
            ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.connections.length,
              itemBuilder: (context, index) => _buildConnectionCard(widget.connections[index]),
            ),
            // Drag indicator
            if (_dragPosition != null && _draggingFromChannel != null)
              Positioned(
                left: _dragPosition!.dx - 20,
                top: _dragPosition!.dy - 20,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(color: FluxForgeTheme.accentCyan, width: 2),
                  ),
                  child: const Icon(Icons.call_split, size: 20, color: FluxForgeTheme.accentCyan),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildConnectionCard(SidechainConnection connection) {
    final isHovered = _hoveredConnection == connection.id;
    final grColor = connection.gainReduction < -6
        ? FluxForgeTheme.accentRed
        : connection.gainReduction < -3
            ? FluxForgeTheme.accentOrange
            : FluxForgeTheme.accentGreen;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredConnection = connection.id),
      onExit: (_) => setState(() => _hoveredConnection = null),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isHovered
              ? FluxForgeTheme.accentCyan.withValues(alpha: 0.1)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isHovered
                ? FluxForgeTheme.accentCyan
                : connection.isActive
                    ? FluxForgeTheme.borderSubtle
                    : FluxForgeTheme.borderSubtle.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Source
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.volume_up, size: 12, color: FluxForgeTheme.accentBlue),
                  const SizedBox(width: 4),
                  Text(
                    connection.sourceName,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            // Arrow with animation
            Expanded(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(double.infinity, 20),
                    painter: _ArrowPainter(
                      isActive: connection.isActive,
                      progress: connection.isActive ? _pulseController.value : 0,
                    ),
                  );
                },
              ),
            ),
            // Target with plugin
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentOrange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.accentOrange.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.graphic_eq, size: 12, color: FluxForgeTheme.accentOrange),
                      const SizedBox(width: 4),
                      Text(
                        connection.targetName,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  Text(
                    connection.pluginName,
                    style: const TextStyle(color: Colors.white54, fontSize: 9),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Gain reduction meter
            if (connection.isActive)
              Container(
                width: 40,
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${connection.gainReduction.toStringAsFixed(1)}',
                      style: TextStyle(color: grColor, fontSize: 10, fontFamily: 'JetBrains Mono'),
                    ),
                    Text(
                      'GR',
                      style: TextStyle(color: grColor.withValues(alpha: 0.6), fontSize: 7),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            // Toggle
            GestureDetector(
              onTap: () => widget.onToggleConnection?.call(connection.id, !connection.isActive),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: connection.isActive
                      ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
                      : FluxForgeTheme.bgDeep,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: connection.isActive ? FluxForgeTheme.accentGreen : Colors.white24,
                  ),
                ),
                child: Icon(
                  connection.isActive ? Icons.power : Icons.power_off,
                  size: 12,
                  color: connection.isActive ? FluxForgeTheme.accentGreen : Colors.white38,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Delete
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              color: Colors.white38,
              onPressed: () => widget.onDeleteConnection?.call(connection.id),
              tooltip: 'Remove',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionLinesPainter extends CustomPainter {
  final List<SidechainConnection> connections;
  final List<RoutingChannel> channels;
  final String? hoveredConnection;
  final Animation<double> animation;

  _ConnectionLinesPainter({
    required this.connections,
    required this.channels,
    this.hoveredConnection,
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    // Background grid
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1;

    for (var x = 0.0; x < size.width; x += 20) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 20) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionLinesPainter oldDelegate) {
    return hoveredConnection != oldDelegate.hoveredConnection;
  }
}

class _ArrowPainter extends CustomPainter {
  final bool isActive;
  final double progress;

  _ArrowPainter({required this.isActive, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isActive
          ? FluxForgeTheme.accentCyan.withValues(alpha: 0.6)
          : Colors.white24
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final y = size.height / 2;
    final startX = 8.0;
    final endX = size.width - 8;

    // Draw dashed line
    const dashWidth = 6.0;
    const gapWidth = 4.0;
    var x = startX;
    while (x < endX - 10) {
      final dashEnd = math.min(x + dashWidth, endX - 10);
      canvas.drawLine(Offset(x, y), Offset(dashEnd, y), paint);
      x += dashWidth + gapWidth;
    }

    // Draw arrow head
    final arrowPath = Path()
      ..moveTo(endX - 8, y - 4)
      ..lineTo(endX, y)
      ..lineTo(endX - 8, y + 4);
    canvas.drawPath(arrowPath, paint);

    // Draw animated pulse if active
    if (isActive) {
      final pulseX = startX + (endX - startX) * progress;
      final pulsePaint = Paint()
        ..color = FluxForgeTheme.accentCyan.withValues(alpha: 1 - progress)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(pulseX, y), Offset(pulseX + 10, y), pulsePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) {
    return isActive != oldDelegate.isActive || progress != oldDelegate.progress;
  }
}
