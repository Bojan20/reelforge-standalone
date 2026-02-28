import 'package:flutter/material.dart';
import '../aurexis_theme.dart';

/// Energy density sparkline graph.
///
/// Shows energy density over time as a filled sparkline,
/// with current value overlay.
class EnergyDensityViz extends StatefulWidget {
  final double energyDensity;
  final double escalationMultiplier;
  final double height;

  const EnergyDensityViz({
    super.key,
    required this.energyDensity,
    this.escalationMultiplier = 1.0,
    this.height = 60,
  });

  @override
  State<EnergyDensityViz> createState() => _EnergyDensityVizState();
}

class _EnergyDensityVizState extends State<EnergyDensityViz> {
  final List<double> _history = [];
  static const int _maxHistory = 80;

  @override
  void didUpdateWidget(EnergyDensityViz oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.energyDensity != widget.energyDensity) {
      _history.add(widget.energyDensity);
      if (_history.length > _maxHistory) {
        _history.removeAt(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text('Energy Density', style: AurexisTextStyles.paramLabel),
              const Spacer(),
              Text(
                widget.energyDensity.toStringAsFixed(2),
                style: AurexisTextStyles.paramValue.copyWith(
                  color: _energyColor(widget.energyDensity),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Sparkline
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CustomPaint(
                painter: _EnergySparklinePainter(
                  values: _history,
                  currentValue: widget.energyDensity,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Escalation indicator
          Row(
            children: [
              Text('Escalation', style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel)),
              const SizedBox(width: 4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(
                    value: ((widget.escalationMultiplier - 1.0) / 3.0).clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: AurexisColors.bgSlider,
                    valueColor: AlwaysStoppedAnimation(AurexisColors.dynamics),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${widget.escalationMultiplier.toStringAsFixed(1)}x',
                style: AurexisTextStyles.badge.copyWith(color: AurexisColors.dynamics),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _energyColor(double density) {
    if (density < 0.3) return AurexisColors.spatial;
    if (density < 0.6) return AurexisColors.accent;
    if (density < 0.8) return AurexisColors.variation;
    return AurexisColors.dynamics;
  }
}

class _EnergySparklinePainter extends CustomPainter {
  final List<double> values;
  final double currentValue;

  _EnergySparklinePainter({required this.values, required this.currentValue});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(Offset.zero & size, Paint()..color = AurexisColors.bgInput);

    if (values.isEmpty) return;

    final path = Path();
    final step = values.length > 1 ? size.width / (values.length - 1) : size.width;

    for (int i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height * (1.0 - values[i].clamp(0.0, 1.0));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Stroke
    final strokePaint = Paint()
      ..color = AurexisColors.accent
      ..strokeWidth = 1.0
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
          AurexisColors.accent.withValues(alpha: 0.25),
          AurexisColors.accent.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    // Current value horizontal line
    final lineY = size.height * (1.0 - currentValue.clamp(0.0, 1.0));
    final linePaint = Paint()
      ..color = AurexisColors.accent.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(0, lineY), Offset(size.width, lineY), linePaint);
  }

  @override
  bool shouldRepaint(_EnergySparklinePainter old) =>
      old.values.length != values.length || old.currentValue != currentValue;
}
