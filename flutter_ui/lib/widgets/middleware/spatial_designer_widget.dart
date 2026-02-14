// Spatial Designer Widget — Middleware Routing Spatial tab
// Interactive 2D spatial positioning editor with listener position,
// source placement, bus spatial policies, and distance attenuation

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

class SpatialPosition {
  final double x, y, z;
  const SpatialPosition({required this.x, required this.y, required this.z});
}

class SpatialDesignerWidget extends StatefulWidget {
  final SpatialPosition position;
  final ValueChanged<SpatialPosition>? onPositionChanged;
  const SpatialDesignerWidget(
      {super.key, required this.position, this.onPositionChanged});

  @override
  State<SpatialDesignerWidget> createState() => _SpatialDesignerWidgetState();
}

class _SpatialDesignerWidgetState extends State<SpatialDesignerWidget> {
  late double _x;
  late double _y;
  late double _z;
  bool _showGrid = true;
  _SpatialMode _mode = _SpatialMode.position;

  // Source positions for visualization
  final List<_SpatialSource> _sources = [
    _SpatialSource('Reels', -0.6, 0.0, const Color(0xFF4A9EFF)),
    _SpatialSource('SFX', 0.3, 0.2, const Color(0xFFFF9040)),
    _SpatialSource('Music', 0.0, -0.5, const Color(0xFF40FF90)),
    _SpatialSource('UI', 0.0, 0.8, const Color(0xFF9370DB)),
    _SpatialSource('Ambience', -0.4, -0.6, const Color(0xFF40C8FF)),
  ];

  @override
  void initState() {
    super.initState();
    _x = widget.position.x;
    _y = widget.position.y;
    _z = widget.position.z;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                // 2D spatial canvas
                Expanded(
                  flex: 3,
                  child: _buildSpatialCanvas(),
                ),
                const SizedBox(width: 8),
                // Controls panel
                SizedBox(
                  width: 180,
                  child: _buildControlsPanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.surround_sound, size: 16, color: FluxForgeTheme.accentCyan),
        const SizedBox(width: 6),
        Text('SPATIAL DESIGNER',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: FluxForgeTheme.accentCyan,
                letterSpacing: 1.0)),
        const Spacer(),
        ..._SpatialMode.values.map((m) {
          final active = _mode == m;
          return Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(
              onTap: () => setState(() => _mode = m),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: active ? FluxForgeTheme.accentCyan.withOpacity(0.15) : null,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                      color: active
                          ? FluxForgeTheme.accentCyan.withOpacity(0.4)
                          : Colors.white12),
                ),
                child: Text(m.label,
                    style: TextStyle(
                        fontSize: 9,
                        color: active ? FluxForgeTheme.accentCyan : Colors.white38)),
              ),
            ),
          );
        }),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => setState(() => _showGrid = !_showGrid),
          child: Icon(Icons.grid_on,
              size: 14, color: _showGrid ? FluxForgeTheme.accentCyan : Colors.white24),
        ),
      ],
    );
  }

  Widget _buildSpatialCanvas() {
    return GestureDetector(
      onPanUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final size = box.size;
        setState(() {
          _x = ((details.localPosition.dx / (size.width * 0.7)) * 2 - 1).clamp(-1.0, 1.0);
          _y = ((details.localPosition.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
        });
        widget.onPositionChanged
            ?.call(SpatialPosition(x: _x, y: _y, z: _z));
      },
      child: Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CustomPaint(
            painter: _SpatialCanvasPainter(
              listenerX: _x,
              listenerY: _y,
              sources: _sources,
              showGrid: _showGrid,
              mode: _mode,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  Widget _buildControlsPanel() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Listener position
          _buildSectionHeader('LISTENER', Icons.headset),
          const SizedBox(height: 4),
          _buildSliderControl('X', _x, -1, 1, (v) {
            setState(() => _x = v);
            widget.onPositionChanged
                ?.call(SpatialPosition(x: _x, y: _y, z: _z));
          }),
          _buildSliderControl('Y', _y, -1, 1, (v) {
            setState(() => _y = v);
            widget.onPositionChanged
                ?.call(SpatialPosition(x: _x, y: _y, z: _z));
          }),
          _buildSliderControl('Z (Height)', _z, -1, 1, (v) {
            setState(() => _z = v);
            widget.onPositionChanged
                ?.call(SpatialPosition(x: _x, y: _y, z: _z));
          }),
          const SizedBox(height: 12),

          // Sources
          _buildSectionHeader('SOURCES', Icons.speaker),
          const SizedBox(height: 4),
          ..._sources.map((s) => _buildSourceItem(s)),
          const SizedBox(height: 12),

          // Distance info
          _buildSectionHeader('DISTANCES', Icons.straighten),
          const SizedBox(height: 4),
          ..._sources.map((s) {
            final dx = s.x - _x;
            final dy = s.y - _y;
            final dist = math.sqrt(dx * dx + dy * dy);
            final pan = s.x.clamp(-1.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: s.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(s.name,
                        style:
                            const TextStyle(fontSize: 9, color: Colors.white54)),
                  ),
                  Text('${dist.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 9, color: s.color)),
                  const SizedBox(width: 8),
                  Text('Pan: ${pan.toStringAsFixed(1)}',
                      style:
                          const TextStyle(fontSize: 8, color: Colors.white38)),
                ],
              ),
            );
          }),

          const SizedBox(height: 12),
          // Reset button
          GestureDetector(
            onTap: () {
              setState(() {
                _x = 0;
                _y = 0;
                _z = 0;
              });
              widget.onPositionChanged
                  ?.call(const SpatialPosition(x: 0, y: 0, z: 0));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.white12),
              ),
              child: const Center(
                child: Text('Reset to Center',
                    style: TextStyle(fontSize: 9, color: Colors.white54)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 12, color: FluxForgeTheme.accentCyan),
        const SizedBox(width: 4),
        Text(title,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: FluxForgeTheme.accentCyan,
                letterSpacing: 0.8)),
      ],
    );
  }

  Widget _buildSliderControl(
      String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
              width: 50,
              child: Text(label,
                  style: const TextStyle(fontSize: 9, color: Colors.white38))),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                activeTrackColor: FluxForgeTheme.accentCyan,
                inactiveTrackColor: Colors.white12,
                thumbColor: FluxForgeTheme.accentCyan,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(value.toStringAsFixed(2),
                style: const TextStyle(fontSize: 8, color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceItem(_SpatialSource source) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: source.color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: source.color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: source.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(source.name,
                  style: TextStyle(fontSize: 9, color: source.color)),
            ),
            Text(
                '(${source.x.toStringAsFixed(1)}, ${source.y.toStringAsFixed(1)})',
                style: const TextStyle(fontSize: 8, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}

enum _SpatialMode {
  position,
  attenuation,
  cones;

  String get label => switch (this) {
        position => 'Position',
        attenuation => 'Atten.',
        cones => 'Cones',
      };
}

class _SpatialSource {
  final String name;
  final double x, y;
  final Color color;
  const _SpatialSource(this.name, this.x, this.y, this.color);
}

class _SpatialCanvasPainter extends CustomPainter {
  final double listenerX, listenerY;
  final List<_SpatialSource> sources;
  final bool showGrid;
  final _SpatialMode mode;

  _SpatialCanvasPainter({
    required this.listenerX,
    required this.listenerY,
    required this.sources,
    required this.showGrid,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(cx, cy) - 8;

    // Grid
    if (showGrid) {
      final gridPaint = Paint()
        ..color = Colors.white.withOpacity(0.04)
        ..strokeWidth = 0.5;
      for (int i = 1; i < 4; i++) {
        final r = radius * i / 4;
        canvas.drawCircle(Offset(cx, cy), r, gridPaint..style = PaintingStyle.stroke);
      }
      canvas.drawLine(Offset(cx - radius, cy), Offset(cx + radius, cy), gridPaint);
      canvas.drawLine(Offset(cx, cy - radius), Offset(cx, cy + radius), gridPaint);
    }

    // Attenuation rings
    if (mode == _SpatialMode.attenuation) {
      for (int i = 1; i <= 3; i++) {
        final ringPaint = Paint()
          ..color = const Color(0xFF40FF90).withOpacity(0.08 * (4 - i))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawCircle(Offset(cx, cy), radius * i / 3, ringPaint);
      }
    }

    // Sources
    for (final src in sources) {
      final sx = cx + src.x * radius;
      final sy = cy + src.y * radius;

      // Connection line to listener
      final lx = cx + listenerX * radius;
      final ly = cy + listenerY * radius;
      final linePaint = Paint()
        ..color = src.color.withOpacity(0.15)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(sx, sy), Offset(lx, ly), linePaint);

      // Source dot
      canvas.drawCircle(
        Offset(sx, sy),
        5,
        Paint()..color = src.color.withOpacity(0.3),
      );
      canvas.drawCircle(
        Offset(sx, sy),
        3,
        Paint()..color = src.color,
      );

      // Cone visualization
      if (mode == _SpatialMode.cones) {
        final angle = math.atan2(ly - sy, lx - sx);
        final conePath = Path()
          ..moveTo(sx, sy)
          ..lineTo(sx + math.cos(angle - 0.4) * 25, sy + math.sin(angle - 0.4) * 25)
          ..lineTo(sx + math.cos(angle + 0.4) * 25, sy + math.sin(angle + 0.4) * 25)
          ..close();
        canvas.drawPath(
          conePath,
          Paint()
            ..color = src.color.withOpacity(0.1)
            ..style = PaintingStyle.fill,
        );
      }
    }

    // Listener
    final lx = cx + listenerX * radius;
    final ly = cy + listenerY * radius;

    // Listener glow
    canvas.drawCircle(
      Offset(lx, ly),
      12,
      Paint()..color = Colors.white.withOpacity(0.05),
    );
    // Listener body
    canvas.drawCircle(
      Offset(lx, ly),
      6,
      Paint()..color = Colors.white.withOpacity(0.8),
    );
    canvas.drawCircle(
      Offset(lx, ly),
      4,
      Paint()..color = const Color(0xFF4A9EFF),
    );

    // Direction indicator
    final dirLen = 15.0;
    canvas.drawLine(
      Offset(lx, ly),
      Offset(lx, ly - dirLen),
      Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SpatialCanvasPainter old) =>
      old.listenerX != listenerX ||
      old.listenerY != listenerY ||
      old.showGrid != showGrid ||
      old.mode != mode;
}
