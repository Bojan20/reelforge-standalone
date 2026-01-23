// Visual Regression Tests for FluxForge Widgets
//
// Run with: flutter test test/visual_regression/widget_golden_tests.dart
// Update goldens: flutter test test/visual_regression/widget_golden_tests.dart --update-goldens

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'visual_test_helper.dart';

void main() {
  group('Visual Regression Tests', () {
    group('Basic Widgets', () {
      testWidgets('Knob widget renders correctly', (tester) async {
        await tester.pumpGolden(
          _buildKnobWidget(),
          size: const Size(200, 200),
        );

        await tester.expectGolden('knob_default');
      });

      testWidgets('Fader widget renders correctly', (tester) async {
        await tester.pumpGolden(
          _buildFaderWidget(),
          size: const Size(100, 400),
        );

        await tester.expectGolden('fader_default');
      });

      testWidgets('Meter widget renders correctly', (tester) async {
        await tester.pumpGolden(
          _buildMeterWidget(),
          size: const Size(40, 300),
        );

        await tester.expectGolden('meter_default');
      });
    });

    group('Color Theme', () {
      testWidgets('Dark theme palette', (tester) async {
        await tester.pumpGolden(
          _buildColorPalette(),
          size: const Size(600, 400),
        );

        await tester.expectGolden('color_palette_dark');
      });
    });

    group('Complex Components', () {
      testWidgets('EQ band control', (tester) async {
        await tester.pumpGolden(
          _buildEqBandControl(),
          size: const Size(300, 200),
        );

        await tester.expectGolden('eq_band_control');
      });

      testWidgets('Waveform display', (tester) async {
        await tester.pumpGolden(
          _buildWaveformDisplay(),
          size: const Size(600, 150),
        );

        await tester.expectGolden('waveform_display');
      });
    });
  });
}

// Test widget builders

Widget _buildKnobWidget() {
  return Center(
    child: _TestKnob(
      value: 0.7,
      label: 'Volume',
    ),
  );
}

Widget _buildFaderWidget() {
  return Center(
    child: _TestFader(
      value: 0.75,
      label: 'Main',
    ),
  );
}

Widget _buildMeterWidget() {
  return Center(
    child: _TestMeter(
      level: 0.8,
      peak: 0.95,
    ),
  );
}

Widget _buildColorPalette() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FluxForge Color Palette',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        _buildColorRow('Backgrounds', [
          _ColorSwatch('Deep', const Color(0xFF0A0A0C)),
          _ColorSwatch('Surface', const Color(0xFF1A1A20)),
          _ColorSwatch('Mid', const Color(0xFF242430)),
        ]),
        const SizedBox(height: 12),
        _buildColorRow('Accents', [
          _ColorSwatch('Blue', const Color(0xFF4A9EFF)),
          _ColorSwatch('Orange', const Color(0xFFFF9040)),
          _ColorSwatch('Green', const Color(0xFF40FF90)),
          _ColorSwatch('Red', const Color(0xFFFF4060)),
          _ColorSwatch('Cyan', const Color(0xFF40C8FF)),
        ]),
        const SizedBox(height: 12),
        _buildColorRow('Metering', [
          _ColorSwatch('-∞', const Color(0xFF40C8FF)),
          _ColorSwatch('-12', const Color(0xFF40FF90)),
          _ColorSwatch('-6', const Color(0xFFFFFF40)),
          _ColorSwatch('-3', const Color(0xFFFF9040)),
          _ColorSwatch('0', const Color(0xFFFF4040)),
        ]),
      ],
    ),
  );
}

Widget _buildColorRow(String label, List<_ColorSwatch> swatches) {
  return Row(
    children: [
      SizedBox(
        width: 100,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
      ...swatches.map((s) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 40,
              decoration: BoxDecoration(
                color: s.color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.name,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      )),
    ],
  );
}

Widget _buildEqBandControl() {
  return Center(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Band 3: 1.0 kHz',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TestKnob(value: 0.5, label: 'Freq', size: 60),
              const SizedBox(width: 16),
              _TestKnob(value: 0.65, label: 'Gain', size: 60),
              const SizedBox(width: 16),
              _TestKnob(value: 0.3, label: 'Q', size: 60),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _buildWaveformDisplay() {
  return Container(
    color: const Color(0xFF0A0A0C),
    padding: const EdgeInsets.all(8),
    child: CustomPaint(
      size: const Size(584, 134),
      painter: _WaveformPainter(),
    ),
  );
}

// Helper widgets for testing

class _TestKnob extends StatelessWidget {
  final double value;
  final String label;
  final double size;

  const _TestKnob({
    required this.value,
    required this.label,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: _KnobPainter(value: value),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double value;

  _KnobPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background arc
    final bgPaint = Paint()
      ..color = const Color(0xFF242430)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const startAngle = 2.4;
    const sweepAngle = 4.3;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = const Color(0xFF4A9EFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * value,
      false,
      valuePaint,
    );

    // Center dot
    final dotPaint = Paint()..color = const Color(0xFF4A9EFF);
    canvas.drawCircle(center, 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _TestFader extends StatelessWidget {
  final double value;
  final String label;

  const _TestFader({
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 60,
          height: 300,
          child: CustomPaint(
            painter: _FaderPainter(value: value),
          ),
        ),
      ],
    );
  }
}

class _FaderPainter extends CustomPainter {
  final double value;

  _FaderPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final trackWidth = 8.0;
    final trackLeft = (size.width - trackWidth) / 2;

    // Track background
    final trackPaint = Paint()
      ..color = const Color(0xFF242430)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackLeft, 20, trackWidth, size.height - 40),
        const Radius.circular(4),
      ),
      trackPaint,
    );

    // Track fill
    final fillHeight = (size.height - 40) * value;
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          const Color(0xFF40C8FF),
          const Color(0xFF4A9EFF),
        ],
      ).createShader(Rect.fromLTWH(trackLeft, size.height - 20 - fillHeight, trackWidth, fillHeight));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackLeft, size.height - 20 - fillHeight, trackWidth, fillHeight),
        const Radius.circular(4),
      ),
      fillPaint,
    );

    // Handle
    final handleY = size.height - 20 - fillHeight;
    final handlePaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, handleY),
          width: 30,
          height: 20,
        ),
        const Radius.circular(4),
      ),
      handlePaint,
    );

    // Handle line
    final linePaint = Paint()
      ..color = const Color(0xFF4A9EFF)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(size.width / 2 - 8, handleY),
      Offset(size.width / 2 + 8, handleY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _TestMeter extends StatelessWidget {
  final double level;
  final double peak;

  const _TestMeter({
    required this.level,
    required this.peak,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(24, 280),
      painter: _MeterPainter(level: level, peak: peak),
    );
  }
}

class _MeterPainter extends CustomPainter {
  final double level;
  final double peak;

  _MeterPainter({required this.level, required this.peak});

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    final bgPaint = Paint()..color = const Color(0xFF0A0A0C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(4),
      ),
      bgPaint,
    );

    // Meter gradient
    final meterHeight = size.height * level;
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: const [
        Color(0xFF40C8FF),
        Color(0xFF40FF90),
        Color(0xFFFFFF40),
        Color(0xFFFF9040),
        Color(0xFFFF4040),
      ],
      stops: const [0.0, 0.4, 0.65, 0.85, 1.0],
    );

    final meterPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(
        2, size.height - meterHeight, size.width - 4, meterHeight,
      ));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2, size.height - meterHeight, size.width - 4, meterHeight),
        const Radius.circular(2),
      ),
      meterPaint,
    );

    // Peak indicator
    final peakY = size.height - (size.height * peak);
    final peakPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(2, peakY),
      Offset(size.width - 2, peakY),
      peakPaint,
    );

    // Scale markers
    final scalePaint = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1;

    for (final db in [-6, -12, -18, -24, -36, -48]) {
      final y = size.height * (1 - (db + 60) / 60);
      canvas.drawLine(
        Offset(0, y),
        Offset(4, y),
        scalePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ColorSwatch {
  final String name;
  final Color color;

  const _ColorSwatch(this.name, this.color);
}

class _WaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4A9EFF)
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;

    // Draw simulated waveform
    for (var x = 0.0; x < size.width; x += 2) {
      // Simulate audio waveform with varying amplitude
      final normalized = x / size.width;
      final envelope = (1 - (normalized - 0.5).abs() * 1.5).clamp(0.0, 1.0);
      final noise = ((x * 0.1).remainder(1.0) - 0.5) * 0.5;
      final amplitude = (envelope * 0.8 + noise * 0.2) * size.height * 0.4;

      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: 1.5,
          height: amplitude,
        ),
        paint,
      );
    }

    // Center line
    final linePaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
