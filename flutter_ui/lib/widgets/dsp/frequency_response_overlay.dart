// frequency_response_overlay.dart
// Real-time frequency response visualization overlay for channel strips

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui' as ui;
import '../../services/frequency_analyzer.dart';

class FrequencyResponseOverlay extends StatefulWidget {
  final int trackId;
  final List<EqBandConfig> eqBands;
  final double width;
  final double height;
  final bool showPhase;
  final bool showGrid;

  const FrequencyResponseOverlay({
    Key? key,
    required this.trackId,
    required this.eqBands,
    this.width = 400,
    this.height = 200,
    this.showPhase = false,
    this.showGrid = true,
  }) : super(key: key);

  @override
  State<FrequencyResponseOverlay> createState() => _FrequencyResponseOverlayState();
}

class _FrequencyResponseOverlayState extends State<FrequencyResponseOverlay> {
  final _analyzer = FrequencyAnalyzer();
  List<FrequencyPoint>? _magnitudeResponse;
  List<FrequencyPoint>? _phaseResponse;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _updateResponse();

    // Update every 100ms for real-time feel
    _updateTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        _updateResponse();
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(FrequencyResponseOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.eqBands != oldWidget.eqBands) {
      _updateResponse();
    }
  }

  void _updateResponse() {
    if (widget.eqBands.isEmpty) {
      setState(() {
        _magnitudeResponse = null;
        _phaseResponse = null;
      });
      return;
    }

    final magnitude = _analyzer.calculateEqResponse(bands: widget.eqBands);
    List<FrequencyPoint>? phase;

    if (widget.showPhase) {
      phase = _analyzer.calculatePhaseResponse(bands: widget.eqBands);
    }

    setState(() {
      _magnitudeResponse = magnitude;
      _phaseResponse = phase;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: CustomPaint(
        painter: _FrequencyResponsePainter(
          magnitudeResponse: _magnitudeResponse,
          phaseResponse: _phaseResponse,
          analyzer: _analyzer,
          showGrid: widget.showGrid,
        ),
      ),
    );
  }
}

class _FrequencyResponsePainter extends CustomPainter {
  final List<FrequencyPoint>? magnitudeResponse;
  final List<FrequencyPoint>? phaseResponse;
  final FrequencyAnalyzer analyzer;
  final bool showGrid;

  const _FrequencyResponsePainter({
    required this.magnitudeResponse,
    required this.phaseResponse,
    required this.analyzer,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    if (magnitudeResponse != null && magnitudeResponse!.isNotEmpty) {
      _drawMagnitudeResponse(canvas, size);
    }

    if (phaseResponse != null && phaseResponse!.isNotEmpty) {
      _drawPhaseResponse(canvas, size);
    }

    _drawCenterLine(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final labelStyle = const TextStyle(
      color: Colors.white38,
      fontSize: 9,
    );

    // Frequency grid (vertical lines)
    final freqGrid = analyzer.generateFrequencyGrid();
    for (final freq in freqGrid) {
      final x = _frequencyToX(freq, size.width);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );

      // Label major frequencies
      if ([100.0, 1000.0, 10000.0].contains(freq)) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: analyzer.formatFrequency(freq),
            style: labelStyle,
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, size.height - textPainter.height - 2),
        );
      }
    }

    // dB grid (horizontal lines)
    final dbGrid = analyzer.generateDbGrid();
    for (final db in dbGrid) {
      final y = _dbToY(db, size.height);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );

      // Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: analyzer.formatDb(db),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(4, y - textPainter.height / 2),
      );
    }
  }

  void _drawCenterLine(Canvas canvas, Size size) {
    final centerPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final y = _dbToY(0.0, size.height);
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      centerPaint,
    );
  }

  void _drawMagnitudeResponse(Canvas canvas, Size size) {
    final path = analyzer.createResponsePath(
      points: magnitudeResponse!,
      width: size.width,
      height: size.height,
    );

    // Glow effect
    final glowPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.3)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    canvas.drawPath(path, glowPaint);

    // Main curve
    final curvePaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, curvePaint);

    // Fill under curve
    final fillPath = ui.Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height),
        [
          Colors.blueAccent.withOpacity(0.3),
          Colors.blueAccent.withOpacity(0.0),
        ],
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
  }

  void _drawPhaseResponse(Canvas canvas, Size size) {
    final path = analyzer.createResponsePath(
      points: phaseResponse!,
      width: size.width,
      height: size.height,
      minDb: -180.0,
      maxDb: 180.0,
    );

    final phasePaint = Paint()
      ..color = Colors.orange.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, phasePaint);
  }

  double _frequencyToX(double freq, double width) {
    const minFreq = 20.0;
    const maxFreq = 20000.0;
    final logMin = 1.301; // log10(20)
    final logMax = 4.301; // log10(20000)
    final logFreq = _log10(freq);
    return ((logFreq - logMin) / (logMax - logMin)) * width;
  }

  double _dbToY(double db, double height) {
    const minDb = -24.0;
    const maxDb = 24.0;
    final normalized = (db - minDb) / (maxDb - minDb);
    return height - (normalized * height);
  }

  double _log10(double x) {
    return 0.43429448190325182 * x; // log(x) / ln(10)
  }

  @override
  bool shouldRepaint(_FrequencyResponsePainter oldDelegate) {
    return magnitudeResponse != oldDelegate.magnitudeResponse ||
        phaseResponse != oldDelegate.phaseResponse;
  }
}

/// Compact frequency response widget for channel strip
class CompactFrequencyResponse extends StatelessWidget {
  final int trackId;
  final List<EqBandConfig> eqBands;

  const CompactFrequencyResponse({
    Key? key,
    required this.trackId,
    required this.eqBands,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: FrequencyResponseOverlay(
          trackId: trackId,
          eqBands: eqBands,
          width: 120,
          height: 60,
          showGrid: false,
        ),
      ),
    );
  }
}

/// Full-size frequency response panel
class FrequencyResponsePanel extends StatefulWidget {
  final int trackId;
  final List<EqBandConfig> eqBands;

  const FrequencyResponsePanel({
    Key? key,
    required this.trackId,
    required this.eqBands,
  }) : super(key: key);

  @override
  State<FrequencyResponsePanel> createState() => _FrequencyResponsePanelState();
}

class _FrequencyResponsePanelState extends State<FrequencyResponsePanel> {
  bool _showPhase = false;
  bool _showGrid = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.graphic_eq, size: 20, color: Colors.blueAccent),
              const SizedBox(width: 8),
              const Text(
                'FREQUENCY RESPONSE',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              // Options
              Row(
                children: [
                  Checkbox(
                    value: _showGrid,
                    onChanged: (value) => setState(() => _showGrid = value!),
                  ),
                  const Text('Grid', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 12),
                  Checkbox(
                    value: _showPhase,
                    onChanged: (value) => setState(() => _showPhase = value!),
                  ),
                  const Text('Phase', style: TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Response graph
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: FrequencyResponseOverlay(
                  trackId: widget.trackId,
                  eqBands: widget.eqBands,
                  width: double.infinity,
                  height: double.infinity,
                  showPhase: _showPhase,
                  showGrid: _showGrid,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
