import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../providers/slot_spatial_provider.dart';

/// Slot Spatial Audio™ Panel — 3D Positional Audio Visualizer.
///
/// Real-time spatial scene view powered by rf-slot-spatial Rust engine via FFI.
/// Shows 3D source positions, gain radii, scene overview.
class SpatialAudioPanel extends StatefulWidget {
  const SpatialAudioPanel({super.key});

  @override
  State<SpatialAudioPanel> createState() => _SpatialAudioPanelState();
}

class _SpatialAudioPanelState extends State<SpatialAudioPanel> {
  late final SlotSpatialProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = GetIt.instance<SlotSpatialProvider>();
    _provider.addListener(_onUpdate);
    if (!_provider.initialized) {
      _provider.init();
    }
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          Expanded(child: _buildSceneView()),
          const SizedBox(height: 6),
          _buildSourceList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.surround_sound, size: 14, color: Color(0xFF40C8FF)),
        const SizedBox(width: 4),
        Text(
          '3D Spatial Audio',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A4A),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${_provider.sourceCount} sources',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 9,
            ),
          ),
        ),
        const Spacer(),
        Text(
          _provider.gameId,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 9,
          ),
        ),
      ],
    );
  }

  /// Top-down 2D projection of the 3D scene.
  Widget _buildSceneView() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF12121F),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scene = _provider.sceneSnapshot;
          if (scene == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.spatial_audio_off,
                      size: 32, color: Colors.white.withValues(alpha: 0.15)),
                  const SizedBox(height: 8),
                  Text(
                    'No spatial scene loaded',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                  ),
                ],
              ),
            );
          }

          return CustomPaint(
            painter: _SpatialScenePainter(scene),
            size: Size(constraints.maxWidth, constraints.maxHeight),
          );
        },
      ),
    );
  }

  Widget _buildSourceList() {
    final scene = _provider.sceneSnapshot;
    final sources = (scene?['sources'] as List?) ?? [];

    if (sources.isEmpty) {
      return Text(
        'No sources in scene',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 9),
      );
    }

    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: sources.length,
        itemBuilder: (context, index) {
          final src = sources[index] as Map<String, dynamic>;
          final eventId = src['event_id'] as String? ?? '?';
          return Container(
            width: 100,
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E36),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF3A3A5C), width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventId,
                  style: const TextStyle(
                    color: Color(0xFF40C8FF),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Text(
                  'pos: (${_fmt(src['x'])}, ${_fmt(src['y'])}, ${_fmt(src['z'])})',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5), fontSize: 8),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmt(dynamic v) => (v as num?)?.toStringAsFixed(1) ?? '0';
}

/// Custom painter for top-down 2D spatial view.
class _SpatialScenePainter extends CustomPainter {
  final Map<String, dynamic> scene;

  _SpatialScenePainter(this.scene);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = size.shortestSide / 4;

    // Grid
    final gridPaint = Paint()
      ..color = const Color(0xFF2A2A4A)
      ..strokeWidth = 0.5;

    for (int i = -2; i <= 2; i++) {
      canvas.drawLine(
        Offset(center.dx + i * scale, 0),
        Offset(center.dx + i * scale, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, center.dy + i * scale),
        Offset(size.width, center.dy + i * scale),
        gridPaint,
      );
    }

    // Listener (center)
    final listenerPaint = Paint()..color = const Color(0xFF40C8FF);
    canvas.drawCircle(center, 6, listenerPaint);

    // Sources
    final sources = (scene['sources'] as List?) ?? [];
    final srcPaint = Paint()..color = const Color(0xFFFF6B6B);
    final radiusPaint = Paint()
      ..color = const Color(0xFFFF6B6B).withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    for (final src in sources) {
      if (src is! Map<String, dynamic>) continue;
      final x = (src['x'] as num?)?.toDouble() ?? 0;
      final z = (src['z'] as num?)?.toDouble() ?? 0;
      final radius = (src['radius'] as num?)?.toDouble() ?? 1.0;

      final pos = Offset(center.dx + x * scale, center.dy - z * scale);
      canvas.drawCircle(pos, radius * scale, radiusPaint);
      canvas.drawCircle(pos, 4, srcPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpatialScenePainter oldDelegate) =>
      oldDelegate.scene != scene;
}
