/// Anchor Monitor — Visualize registered UI anchors
///
/// Features:
/// - List all registered anchors
/// - Visual position map
/// - Confidence indicators
/// - Real-time updates

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auto_spatial_provider.dart';
import '../../spatial/auto_spatial.dart';

/// Anchor Monitor widget
class AnchorMonitor extends StatefulWidget {
  const AnchorMonitor({super.key});

  @override
  State<AnchorMonitor> createState() => _AnchorMonitorState();
}

class _AnchorMonitorState extends State<AnchorMonitor> {
  Timer? _refreshTimer;
  String? _selectedAnchorId;

  @override
  void initState() {
    super.initState();
    // Refresh at 10Hz for real-time updates
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoSpatialProvider>(
      builder: (context, provider, _) {
        final anchorIds = provider.anchorIds.toList();

        return Row(
          children: [
            // Left: Anchor list
            SizedBox(
              width: 200,
              child: _buildAnchorList(provider, anchorIds),
            ),

            const VerticalDivider(width: 1, color: Color(0xFF3a3a4a)),

            // Center: Visual map
            Expanded(
              flex: 2,
              child: _buildVisualMap(provider, anchorIds),
            ),

            const VerticalDivider(width: 1, color: Color(0xFF3a3a4a)),

            // Right: Details panel
            SizedBox(
              width: 220,
              child: _selectedAnchorId != null
                  ? _buildDetailsPanel(provider, _selectedAnchorId!)
                  : _buildTestPanel(provider),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnchorList(AutoSpatialProvider provider, List<String> anchorIds) {
    return Column(
      children: [
        // Header
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              const Icon(Icons.anchor, color: Colors.white54, size: 14),
              const SizedBox(width: 6),
              const Text(
                'Registered Anchors',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF4a9eff).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${anchorIds.length}',
                  style: const TextStyle(
                    color: Color(0xFF4a9eff),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, color: Color(0xFF3a3a4a)),

        // Anchor list
        Expanded(
          child: anchorIds.isEmpty
              ? const Center(
                  child: Text(
                    'No anchors registered',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  itemCount: anchorIds.length,
                  itemBuilder: (context, index) {
                    final id = anchorIds[index];
                    final frame = provider.getAnchorFrame(id);
                    final isSelected = _selectedAnchorId == id;

                    return _AnchorListTile(
                      id: id,
                      frame: frame,
                      isSelected: isSelected,
                      onTap: () => setState(() {
                        _selectedAnchorId = isSelected ? null : id;
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildVisualMap(AutoSpatialProvider provider, List<String> anchorIds) {
    return Container(
      color: const Color(0xFF121216),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Grid lines
              CustomPaint(
                painter: _GridPainter(),
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),

              // Anchor markers
              for (final id in anchorIds)
                if (provider.getAnchorFrame(id) != null)
                  _buildAnchorMarker(
                    id,
                    provider.getAnchorFrame(id)!,
                    constraints,
                    id == _selectedAnchorId,
                  ),

              // Labels
              Positioned(
                left: 8,
                top: 8,
                child: Text(
                  'Screen Space',
                  style: TextStyle(
                    color: Colors.white24,
                    fontSize: 10,
                  ),
                ),
              ),
              Positioned(
                left: 8,
                bottom: 8,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF40ff90),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Visible',
                      style: TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFFff4060),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Hidden',
                      style: TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnchorMarker(
    String id,
    AnchorFrame frame,
    BoxConstraints constraints,
    bool isSelected,
  ) {
    final x = frame.xNorm * constraints.maxWidth;
    final y = frame.yNorm * constraints.maxHeight;
    final w = frame.wNorm * constraints.maxWidth;
    final h = frame.hNorm * constraints.maxHeight;

    final color = frame.visible
        ? const Color(0xFF40ff90)
        : const Color(0xFFff4060);

    final alpha = (frame.confidence * 0.8 + 0.2).clamp(0.2, 1.0);

    return Positioned(
      left: x - w / 2,
      top: y - h / 2,
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedAnchorId = isSelected ? null : id;
        }),
        child: Container(
          width: w.clamp(20.0, 200.0),
          height: h.clamp(20.0, 200.0),
          decoration: BoxDecoration(
            color: color.withValues(alpha: alpha * 0.2),
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : color.withValues(alpha: alpha),
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            children: [
              // Center dot
              Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Velocity vector
              if (frame.vxNormPerS.abs() > 0.01 ||
                  frame.vyNormPerS.abs() > 0.01)
                CustomPaint(
                  painter: _VelocityPainter(
                    vx: frame.vxNormPerS * 50,
                    vy: frame.vyNormPerS * 50,
                    color: color,
                  ),
                  size: Size(w.clamp(20.0, 200.0), h.clamp(20.0, 200.0)),
                ),

              // Label
              Positioned(
                left: 4,
                top: 2,
                child: Text(
                  id.length > 12 ? '${id.substring(0, 10)}...' : id,
                  style: TextStyle(
                    color: color,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsPanel(AutoSpatialProvider provider, String anchorId) {
    final frame = provider.getAnchorFrame(anchorId);
    if (frame == null) return const SizedBox.shrink();

    final ageMs = DateTime.now().millisecondsSinceEpoch - frame.timestampMs;
    final spatial = frame.toSpatialPosition();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  anchorId,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => _selectedAnchorId = null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: Colors.white54,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status
          _DetailRow(
            label: 'Status',
            value: frame.visible ? 'Visible' : 'Hidden',
            valueColor:
                frame.visible ? const Color(0xFF40ff90) : const Color(0xFFff4060),
          ),
          _DetailRow(
            label: 'Confidence',
            value: '${(frame.confidence * 100).toStringAsFixed(1)}%',
          ),
          _DetailRow(
            label: 'Age',
            value: '${ageMs}ms',
            valueColor: ageMs > 500 ? Colors.orange : null,
          ),
          const SizedBox(height: 12),

          // Screen Position
          const Text(
            'Screen Position',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          _DetailRow(label: 'X', value: frame.xNorm.toStringAsFixed(3)),
          _DetailRow(label: 'Y', value: frame.yNorm.toStringAsFixed(3)),
          _DetailRow(label: 'Width', value: frame.wNorm.toStringAsFixed(3)),
          _DetailRow(label: 'Height', value: frame.hNorm.toStringAsFixed(3)),
          const SizedBox(height: 12),

          // Spatial Position
          const Text(
            'Spatial Position',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          _DetailRow(
            label: 'Pan',
            value: spatial.x.toStringAsFixed(3),
            valueColor: spatial.x < 0
                ? const Color(0xFF4a9eff)
                : const Color(0xFFff9040),
          ),
          _DetailRow(label: 'Y', value: spatial.y.toStringAsFixed(3)),
          _DetailRow(label: 'Z', value: spatial.z.toStringAsFixed(3)),
          const SizedBox(height: 12),

          // Velocity
          const Text(
            'Velocity',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          _DetailRow(
            label: 'VX',
            value: '${frame.vxNormPerS.toStringAsFixed(2)}/s',
          ),
          _DetailRow(
            label: 'VY',
            value: '${frame.vyNormPerS.toStringAsFixed(2)}/s',
          ),
          const SizedBox(height: 16),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('Unregister', style: TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () {
                    provider.unregisterAnchor(anchorId);
                    setState(() => _selectedAnchorId = null);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTestPanel(AutoSpatialProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Test Anchors',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create test anchors to visualize spatial positioning.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 16),

          // Quick test buttons
          _TestAnchorButton(
            label: 'Center',
            x: 0.5,
            y: 0.5,
            provider: provider,
          ),
          _TestAnchorButton(
            label: 'Top-Left',
            x: 0.1,
            y: 0.1,
            provider: provider,
          ),
          _TestAnchorButton(
            label: 'Top-Right',
            x: 0.9,
            y: 0.1,
            provider: provider,
          ),
          _TestAnchorButton(
            label: 'Bottom-Left',
            x: 0.1,
            y: 0.9,
            provider: provider,
          ),
          _TestAnchorButton(
            label: 'Bottom-Right',
            x: 0.9,
            y: 0.9,
            provider: provider,
          ),
          const SizedBox(height: 16),

          // Reel anchors
          const Text(
            'Reel Anchors',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(5, (i) {
              final x = 0.2 + (i * 0.15);
              return _TestAnchorChip(
                label: 'Reel ${i + 1}',
                id: 'reel_${i + 1}',
                x: x,
                y: 0.5,
                provider: provider,
              );
            }),
          ),
          const SizedBox(height: 16),

          // Clear all
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.clear_all, size: 14),
              label: const Text('Clear All Test Anchors', style: TextStyle(fontSize: 10)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: const BorderSide(color: Colors.white24),
              ),
              onPressed: () {
                for (final id in provider.anchorIds.toList()) {
                  if (id.startsWith('test_') || id.startsWith('reel_')) {
                    provider.unregisterAnchor(id);
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Anchor list tile
class _AnchorListTile extends StatelessWidget {
  final String id;
  final AnchorFrame? frame;
  final bool isSelected;
  final VoidCallback onTap;

  const _AnchorListTile({
    required this.id,
    required this.frame,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = frame?.visible == true
        ? const Color(0xFF40ff90)
        : const Color(0xFFff4060);

    return Material(
      color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  id,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (frame != null) ...[
                Text(
                  '${(frame!.confidence * 100).round()}%',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Detail row
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white70,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Test anchor button
class _TestAnchorButton extends StatelessWidget {
  final String label;
  final double x;
  final double y;
  final AutoSpatialProvider provider;

  const _TestAnchorButton({
    required this.label,
    required this.x,
    required this.y,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final id = 'test_${label.toLowerCase().replaceAll('-', '_')}';
    final exists = provider.anchorRegistry.hasAnchor(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        width: double.infinity,
        height: 28,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: exists ? const Color(0xFF40ff90) : Colors.white70,
            side: BorderSide(
              color: exists ? const Color(0xFF40ff90) : Colors.white24,
            ),
            padding: EdgeInsets.zero,
          ),
          onPressed: () {
            if (exists) {
              provider.unregisterAnchor(id);
            } else {
              provider.registerAnchor(
                id: id,
                xNorm: x,
                yNorm: y,
                wNorm: 0.1,
                hNorm: 0.1,
              );
            }
          },
          child: Text(
            exists ? '$label (active)' : label,
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ),
    );
  }
}

/// Test anchor chip
class _TestAnchorChip extends StatelessWidget {
  final String label;
  final String id;
  final double x;
  final double y;
  final AutoSpatialProvider provider;

  const _TestAnchorChip({
    required this.label,
    required this.id,
    required this.x,
    required this.y,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    final exists = provider.anchorRegistry.hasAnchor(id);
    final color = exists ? const Color(0xFF40ff90) : Colors.white54;

    return GestureDetector(
      onTap: () {
        if (exists) {
          provider.unregisterAnchor(id);
        } else {
          provider.registerAnchor(
            id: id,
            xNorm: x,
            yNorm: y,
            wNorm: 0.08,
            hNorm: 0.15,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 9),
        ),
      ),
    );
  }
}

/// Grid painter for visual map
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1;

    // Vertical lines
    for (var i = 0; i <= 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (var i = 0; i <= 10; i++) {
      final y = size.height * i / 10;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Center crosshair
    final centerPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centerPaint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Velocity vector painter
class _VelocityPainter extends CustomPainter {
  final double vx;
  final double vy;
  final Color color;

  _VelocityPainter({
    required this.vx,
    required this.vy,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX + vx, centerY + vy),
      paint,
    );

    // Arrow head
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(centerX + vx, centerY + vy)
      ..lineTo(centerX + vx - 4, centerY + vy - 2)
      ..lineTo(centerX + vx - 4, centerY + vy + 2)
      ..close();

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _VelocityPainter oldDelegate) {
    return vx != oldDelegate.vx || vy != oldDelegate.vy;
  }
}
