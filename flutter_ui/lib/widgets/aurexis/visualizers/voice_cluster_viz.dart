import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../aurexis_theme.dart';

/// Stereo field voice cluster visualizer.
///
/// Shows a horizontal stereo field (L—C—R) with voice positions,
/// collision zones, and center occupancy indicators.
class VoiceClusterViz extends StatelessWidget {
  final int centerOccupancy;
  final int voicesRedistributed;
  final double duckingBiasDb;
  final double stereoWidth;
  final double panDrift;
  final double height;

  const VoiceClusterViz({
    super.key,
    required this.centerOccupancy,
    required this.voicesRedistributed,
    required this.duckingBiasDb,
    this.stereoWidth = 1.0,
    this.panDrift = 0.0,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Column(
        children: [
          // Stereo field visualization
          Expanded(
            child: CustomPaint(
              painter: _StereoFieldPainter(
                centerOccupancy: centerOccupancy,
                stereoWidth: stereoWidth,
                panDrift: panDrift,
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: 4),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat(
                'Center',
                '$centerOccupancy/2',
                centerOccupancy >= 2 ? AurexisColors.fatigueHigh : AurexisColors.accent,
              ),
              _buildStat(
                'Redist',
                '$voicesRedistributed',
                voicesRedistributed > 0 ? AurexisColors.variation : AurexisColors.textLabel,
              ),
              _buildStat(
                'Duck',
                '${duckingBiasDb.toStringAsFixed(1)}',
                duckingBiasDb < -1.0 ? AurexisColors.dynamics : AurexisColors.textLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel)),
        Text(value, style: AurexisTextStyles.paramValue.copyWith(color: color, fontSize: 10)),
      ],
    );
  }
}

class _StereoFieldPainter extends CustomPainter {
  final int centerOccupancy;
  final double stereoWidth;
  final double panDrift;

  _StereoFieldPainter({
    required this.centerOccupancy,
    required this.stereoWidth,
    required this.panDrift,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Background
    final bgPaint = Paint()..color = AurexisColors.bgInput;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      bgPaint,
    );

    // Center zone indicator
    final centerZoneWidth = size.width * 0.15;
    final centerZonePaint = Paint()
      ..color = centerOccupancy >= 2
          ? AurexisColors.fatigueHigh.withValues(alpha: 0.15)
          : AurexisColors.accent.withValues(alpha: 0.05);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(centerX, centerY), width: centerZoneWidth, height: size.height),
      centerZonePaint,
    );

    // L-C-R labels
    final labelPaint = TextPainter(textDirection: TextDirection.ltr);
    for (final (text, x) in [('L', 8.0), ('C', centerX), ('R', size.width - 8)]) {
      labelPaint
        ..text = TextSpan(
          text: text,
          style: AurexisTextStyles.badge.copyWith(
            color: AurexisColors.textLabel.withValues(alpha: 0.5),
            fontSize: 7,
          ),
        )
        ..layout();
      labelPaint.paint(canvas, Offset(x - labelPaint.width / 2, 2));
    }

    // Center line
    final centerLinePaint = Paint()
      ..color = AurexisColors.borderSubtle
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(centerX, 12),
      Offset(centerX, size.height - 4),
      centerLinePaint,
    );

    // Stereo width indicator (arc)
    final widthRadius = (stereoWidth / 2.0).clamp(0.0, 1.0) * (size.width / 2 - 8);
    final widthPaint = Paint()
      ..color = AurexisColors.spatial.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(centerX + panDrift * (size.width / 2), centerY),
        width: widthRadius * 2,
        height: size.height * 0.6,
      ),
      -math.pi * 0.8,
      math.pi * 1.6,
      false,
      widthPaint,
    );

    // Center occupancy dots
    final dotRadius = 4.0;
    for (int i = 0; i < centerOccupancy.clamp(0, 4); i++) {
      final dotPaint = Paint()
        ..color = i < 2 ? AurexisColors.accent : AurexisColors.fatigueHigh;
      final offsetX = centerX + (i - (centerOccupancy - 1) / 2) * 10;
      canvas.drawCircle(Offset(offsetX, centerY), dotRadius, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_StereoFieldPainter old) =>
      old.centerOccupancy != centerOccupancy ||
      old.stereoWidth != stereoWidth ||
      old.panDrift != panDrift;
}
