/// Loudness History Graph (P2-18)
/// Real-time LUFS history sparkline

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

class LoudnessHistoryGraph extends StatelessWidget {
  final List<double> lufsHistory;
  final double targetLufs;

  const LoudnessHistoryGraph({
    super.key,
    required this.lufsHistory,
    this.targetLufs = -14.0,
  });

  @override
  Widget build(BuildContext context) {
    if (lufsHistory.isEmpty) {
      return const Center(child: Text('No data', style: TextStyle(color: FluxForgeTheme.textSecondary)));
    }

    return CustomPaint(
      painter: _LoudnessGraphPainter(lufsHistory, targetLufs),
      child: Container(),
    );
  }
}

class _LoudnessGraphPainter extends CustomPainter {
  final List<double> data;
  final double target;

  _LoudnessGraphPainter(this.data, this.target);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = FluxForgeTheme.accentCyan
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final step = size.width / (data.length - 1);

    for (var i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height * (1 - (data[i] + 60) / 60); // -60 to 0 LUFS
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Target line
    final targetY = size.height * (1 - (target + 60) / 60);
    canvas.drawLine(
      Offset(0, targetY),
      Offset(size.width, targetY),
      Paint()..color = FluxForgeTheme.accentOrange.withOpacity(0.5)..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_LoudnessGraphPainter old) => data != old.data;
}
