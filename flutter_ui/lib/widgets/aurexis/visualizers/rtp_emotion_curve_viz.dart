import 'package:flutter/material.dart';
import '../aurexis_theme.dart';

/// RTP-to-Emotion pacing curve visualizer.
///
/// Shows the build/hold/release pacing profile for the current RTP,
/// with time markers and the current position indicator.
class RtpEmotionCurveViz extends StatelessWidget {
  final double rtp;
  final double reverbSendBias;
  final double reverbTailExtensionMs;
  final double height;

  const RtpEmotionCurveViz({
    super.key,
    required this.rtp,
    this.reverbSendBias = 0.0,
    this.reverbTailExtensionMs = 0.0,
    this.height = 70,
  });

  @override
  Widget build(BuildContext context) {
    // Derive pacing from RTP
    final intensity = 1.0 - ((rtp - 85.0) / 14.5).clamp(0.0, 1.0);

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('RTP Pacing', style: AurexisTextStyles.paramLabel),
              const Spacer(),
              Text(
                'RTP ${rtp.toStringAsFixed(1)}%',
                style: AurexisTextStyles.paramValue.copyWith(
                  color: AurexisColors.music,
                  fontSize: 9,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CustomPaint(
                painter: _RtpCurvePainter(
                  intensity: intensity,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Reverb stats
          Row(
            children: [
              Text('Rev Bias', style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel)),
              const SizedBox(width: 4),
              Text(
                '${reverbSendBias >= 0 ? '+' : ''}${reverbSendBias.toStringAsFixed(2)}',
                style: AurexisTextStyles.badge.copyWith(color: AurexisColors.music),
              ),
              const Spacer(),
              Text('Tail', style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel)),
              const SizedBox(width: 4),
              Text(
                '+${reverbTailExtensionMs.toStringAsFixed(0)}ms',
                style: AurexisTextStyles.badge.copyWith(color: AurexisColors.music),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RtpCurvePainter extends CustomPainter {
  final double intensity;

  _RtpCurvePainter({required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      Paint()..color = AurexisColors.bgInput,
    );

    // Pacing curve: Build → Hold → Release
    // Higher intensity = faster build, longer hold, steeper peak
    final buildEnd = 0.15 + (1.0 - intensity) * 0.25; // 15-40% of width
    final holdEnd = buildEnd + 0.1 + intensity * 0.15; // 10-25% hold duration
    final peakHeight = 0.4 + intensity * 0.5; // 40-90% of height

    final path = Path();
    path.moveTo(0, size.height);

    // Build phase (curve up)
    final buildX = buildEnd * size.width;
    final peakY = size.height * (1.0 - peakHeight);
    path.quadraticBezierTo(
      buildX * 0.5, size.height,
      buildX, peakY,
    );

    // Hold phase (plateau)
    final holdX = holdEnd * size.width;
    path.lineTo(holdX, peakY);

    // Release phase (curve down)
    path.quadraticBezierTo(
      holdX + (size.width - holdX) * 0.3, peakY,
      size.width, size.height * (1.0 - peakHeight * 0.15),
    );

    // Stroke
    final strokePaint = Paint()
      ..color = AurexisColors.music
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, strokePaint);

    // Fill
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AurexisColors.music.withValues(alpha: 0.2),
          AurexisColors.music.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    // Phase labels
    final labelStyle = AurexisTextStyles.badge.copyWith(
      color: AurexisColors.textLabel.withValues(alpha: 0.4),
      fontSize: 6,
    );
    _drawText(canvas, 'BUILD', Offset(4, size.height - 10), labelStyle);
    _drawText(canvas, 'HOLD', Offset(buildX + 4, peakY - 10), labelStyle);
    _drawText(canvas, 'RELEASE', Offset(holdX + 4, peakY + 4), labelStyle);

    // Phase boundary markers
    final markerPaint = Paint()
      ..color = AurexisColors.borderSubtle
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(buildX, 0), Offset(buildX, size.height), markerPaint);
    canvas.drawLine(Offset(holdX, 0), Offset(holdX, size.height), markerPaint);
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_RtpCurvePainter old) => old.intensity != intensity;
}
