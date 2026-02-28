import 'package:flutter/material.dart';
import '../aurexis_theme.dart';

/// Vertical fatigue index meter with history sparkline.
///
/// Shows current fatigue level as a vertical bar (0-100%)
/// with color zones and a trailing sparkline of recent values.
class FatigueMeterViz extends StatefulWidget {
  final double fatigueIndex;
  final double sessionDurationS;
  final double rmsAvgDb;
  final double hfCumulative;
  final double height;

  const FatigueMeterViz({
    super.key,
    required this.fatigueIndex,
    this.sessionDurationS = 0,
    this.rmsAvgDb = -60,
    this.hfCumulative = 0,
    this.height = 120,
  });

  @override
  State<FatigueMeterViz> createState() => _FatigueMeterVizState();
}

class _FatigueMeterVizState extends State<FatigueMeterViz> {
  final List<double> _history = [];
  static const int _maxHistory = 60;

  @override
  void didUpdateWidget(FatigueMeterViz oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fatigueIndex != widget.fatigueIndex) {
      _history.add(widget.fatigueIndex);
      if (_history.length > _maxHistory) {
        _history.removeAt(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          // Vertical meter
          SizedBox(
            width: 24,
            child: CustomPaint(
              painter: _FatigueMeterPainter(
                value: widget.fatigueIndex,
              ),
              size: Size(24, widget.height),
            ),
          ),
          const SizedBox(width: 6),
          // Sparkline + stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sparkline
                Expanded(
                  child: CustomPaint(
                    painter: _SparklinePainter(
                      values: _history,
                      color: _fatigueColor(widget.fatigueIndex),
                    ),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 4),
                // Stats
                Text(
                  '${(widget.fatigueIndex * 100).toStringAsFixed(0)}%',
                  style: AurexisTextStyles.paramValue.copyWith(
                    color: _fatigueColor(widget.fatigueIndex),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _formatDuration(widget.sessionDurationS),
                  style: AurexisTextStyles.badge.copyWith(
                    color: AurexisColors.textLabel,
                  ),
                ),
                Text(
                  'RMS: ${widget.rmsAvgDb.toStringAsFixed(1)} dB',
                  style: AurexisTextStyles.badge.copyWith(
                    color: AurexisColors.textLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Color _fatigueColor(double index) {
    if (index < 0.2) return AurexisColors.fatigueFresh;
    if (index < 0.4) return AurexisColors.fatigueMild;
    if (index < 0.6) return AurexisColors.fatigueModerate;
    if (index < 0.8) return AurexisColors.fatigueHigh;
    return AurexisColors.fatigueCritical;
  }
}

class _FatigueMeterPainter extends CustomPainter {
  final double value;

  _FatigueMeterPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = AurexisColors.bgSlider;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      bgPaint,
    );

    // Draw zone indicators
    final zones = [
      (0.0, 0.2, AurexisColors.fatigueFresh),
      (0.2, 0.4, AurexisColors.fatigueMild),
      (0.4, 0.6, AurexisColors.fatigueModerate),
      (0.6, 0.8, AurexisColors.fatigueHigh),
      (0.8, 1.0, AurexisColors.fatigueCritical),
    ];

    for (final (start, end, color) in zones) {
      final y1 = size.height * (1.0 - end);
      final y2 = size.height * (1.0 - start);
      final fillAmount = value.clamp(start, end) - start;
      final zoneSize = end - start;
      final fillRatio = fillAmount / zoneSize;

      if (fillRatio > 0) {
        final fillPaint = Paint()..color = color.withValues(alpha: 0.6);
        final fillHeight = (y2 - y1) * fillRatio;
        canvas.drawRect(
          Rect.fromLTWH(2, y2 - fillHeight, size.width - 4, fillHeight),
          fillPaint,
        );
      }

      // Zone boundary line
      final linePaint = Paint()
        ..color = AurexisColors.borderSubtle
        ..strokeWidth = 0.5;
      canvas.drawLine(Offset(0, y1), Offset(size.width, y1), linePaint);
    }

    // Current value indicator
    final indicatorY = size.height * (1.0 - value.clamp(0.0, 1.0));
    final indicatorPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(0, indicatorY),
      Offset(size.width, indicatorY),
      indicatorPaint,
    );
  }

  @override
  bool shouldRepaint(_FatigueMeterPainter old) => old.value != value;
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final path = Path();
    final step = size.width / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height * (1.0 - values[i].clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paint);

    // Fill under the line
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values.length != values.length || old.color != color;
}
