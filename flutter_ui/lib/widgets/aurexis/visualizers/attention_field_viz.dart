import 'package:flutter/material.dart';
import '../aurexis_theme.dart';

/// 2D attention gravity field visualizer.
///
/// Shows where the audio focus is on screen based on
/// attention_x/y coordinates and focus weight.
class AttentionFieldViz extends StatelessWidget {
  final double attentionX;
  final double attentionY;
  final double attentionWeight;
  final double height;

  const AttentionFieldViz({
    super.key,
    required this.attentionX,
    required this.attentionY,
    required this.attentionWeight,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Attention Field', style: AurexisTextStyles.paramLabel),
              const Spacer(),
              Text(
                'Focus: ${(attentionWeight * 100).toStringAsFixed(0)}%',
                style: AurexisTextStyles.badge.copyWith(
                  color: attentionWeight > 0.5 ? AurexisColors.accent : AurexisColors.textLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CustomPaint(
                painter: _AttentionFieldPainter(
                  x: attentionX,
                  y: attentionY,
                  weight: attentionWeight,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionFieldPainter extends CustomPainter {
  final double x;
  final double y;
  final double weight;

  _AttentionFieldPainter({
    required this.x,
    required this.y,
    required this.weight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = AurexisColors.bgInput,
    );

    // Grid
    final gridPaint = Paint()
      ..color = AurexisColors.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Crosshair at center
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    // Attention point position (normalized -1..1 to canvas coords)
    final px = (x + 1.0) / 2.0 * size.width;
    final py = (1.0 - (y + 1.0) / 2.0) * size.height;

    // Glow based on weight
    if (weight > 0.01) {
      final glowRadius = 10.0 + weight * 25.0;
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            AurexisColors.accent.withValues(alpha: weight * 0.4),
            AurexisColors.accent.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: Offset(px, py), radius: glowRadius),
        );
      canvas.drawCircle(Offset(px, py), glowRadius, glowPaint);
    }

    // Focus ring
    final ringPaint = Paint()
      ..color = AurexisColors.accent.withValues(alpha: 0.5 + weight * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(px, py), 4.0 + weight * 3.0, ringPaint);

    // Center dot
    final dotPaint = Paint()..color = AurexisColors.accent;
    canvas.drawCircle(Offset(px, py), 2.5, dotPaint);

    // Corner labels
    final labelStyle = AurexisTextStyles.badge.copyWith(
      color: AurexisColors.textLabel.withValues(alpha: 0.3),
      fontSize: 6,
    );
    _drawText(canvas, 'TL', Offset(3, 2), labelStyle);
    _drawText(canvas, 'TR', Offset(size.width - 14, 2), labelStyle);
    _drawText(canvas, 'BL', Offset(3, size.height - 10), labelStyle);
    _drawText(canvas, 'BR', Offset(size.width - 14, size.height - 10), labelStyle);
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_AttentionFieldPainter old) =>
      old.x != x || old.y != y || old.weight != weight;
}
