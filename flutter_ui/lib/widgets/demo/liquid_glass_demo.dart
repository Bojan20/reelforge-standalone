/// Liquid Glass Design Demo
///
/// macOS Tahoe-style glassmorphism for FluxForge Studio.
/// Features:
/// - Frosted glass blur with subtle tint
/// - Specular highlights and reflections
/// - Soft shadows and depth
/// - Adaptive transparency based on content behind

import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

class LiquidGlassDemo extends StatelessWidget {
  const LiquidGlassDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Gradient background to show glass effect
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1a1a2e), // Deep navy
              Color(0xFF16213e), // Dark blue
              Color(0xFF0f0f23), // Near black
              Color(0xFF1a1a2e), // Deep navy
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Ambient color orbs (background decoration)
            Positioned(
              top: 50,
              left: 100,
              child: _ColorOrb(
                color: const Color(0xFF4a9eff).withValues(alpha: 0.3),
                size: 200,
              ),
            ),
            Positioned(
              top: 200,
              right: 150,
              child: _ColorOrb(
                color: const Color(0xFFff9040).withValues(alpha: 0.25),
                size: 180,
              ),
            ),
            Positioned(
              bottom: 100,
              left: 200,
              child: _ColorOrb(
                color: const Color(0xFF40ff90).withValues(alpha: 0.2),
                size: 220,
              ),
            ),
            Positioned(
              bottom: 150,
              right: 100,
              child: _ColorOrb(
                color: const Color(0xFFaa40ff).withValues(alpha: 0.25),
                size: 160,
              ),
            ),

            // Main content
            Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  const Text(
                    'Liquid Glass Demo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'macOS Tahoe-inspired glassmorphism for FluxForge Studio',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Demo panels
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column - Mixer channel strip
                        _buildMixerStrip(),
                        const SizedBox(width: 24),

                        // Center - Transport & Controls
                        Expanded(
                          child: Column(
                            children: [
                              _buildTransportBar(),
                              const SizedBox(height: 24),
                              Expanded(
                                child: Row(
                                  children: [
                                    // EQ Panel
                                    Expanded(child: _buildEQPanel()),
                                    const SizedBox(width: 24),
                                    // Metering
                                    _buildMeteringPanel(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 24),
                        // Right - Inspector
                        _buildInspectorPanel(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMixerStrip() {
    return LiquidGlassContainer(
      width: 80,
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Track name
          Text(
            'MASTER',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),

          // Pan knob
          _GlassKnob(value: 0.5, size: 40, label: 'PAN'),
          const SizedBox(height: 20),

          // Meter
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(child: _GlassMeter(value: 0.7, peak: 0.85)),
                  const SizedBox(width: 4),
                  Expanded(child: _GlassMeter(value: 0.65, peak: 0.82)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Fader value
          Text(
            '-3.2 dB',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),

          // Mute/Solo buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _GlassButton(label: 'M', isActive: false, color: Colors.red),
              const SizedBox(width: 4),
              _GlassButton(label: 'S', isActive: true, color: Colors.amber),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildTransportBar() {
    return LiquidGlassContainer(
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: 20),
          // Time display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: const Text(
              '00:02:34.156',
              style: TextStyle(
                color: Color(0xFF40ff90),
                fontSize: 20,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 24),

          // Transport controls
          _TransportButton(icon: Icons.skip_previous, onTap: () {}),
          const SizedBox(width: 8),
          _TransportButton(icon: Icons.stop, onTap: () {}),
          const SizedBox(width: 8),
          _TransportButton(
            icon: Icons.play_arrow,
            onTap: () {},
            isActive: true,
            activeColor: const Color(0xFF40ff90),
          ),
          const SizedBox(width: 8),
          _TransportButton(
            icon: Icons.fiber_manual_record,
            onTap: () {},
            activeColor: Colors.red,
          ),
          const SizedBox(width: 8),
          _TransportButton(icon: Icons.skip_next, onTap: () {}),

          const Spacer(),

          // Tempo
          Text(
            '120.00 BPM',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 16),

          // Time signature
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              '4/4',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 20),
        ],
      ),
    );
  }

  Widget _buildEQPanel() {
    return LiquidGlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.equalizer,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'PARAMETRIC EQ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                _GlassToggle(label: 'Linear Phase', isOn: false),
              ],
            ),
          ),

          // EQ curve display
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: CustomPaint(
                painter: _EQCurvePainter(),
                size: Size.infinite,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // EQ band controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _EQBandControl(freq: '80 Hz', gain: '+2.5', q: '0.7', color: const Color(0xFFff6b6b)),
                _EQBandControl(freq: '250 Hz', gain: '-1.8', q: '1.2', color: const Color(0xFFffa94d)),
                _EQBandControl(freq: '1.2 kHz', gain: '+0.5', q: '0.9', color: const Color(0xFF69db7c)),
                _EQBandControl(freq: '4 kHz', gain: '+3.2', q: '1.5', color: const Color(0xFF4dabf7)),
                _EQBandControl(freq: '12 kHz', gain: '+1.0', q: '0.6', color: const Color(0xFFda77f2)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildMeteringPanel() {
    return LiquidGlassContainer(
      width: 120,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'LOUDNESS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
          ),

          // LUFS display
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF4a9eff).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Text(
                  '-14.2',
                  style: TextStyle(
                    color: const Color(0xFF4a9eff),
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'LUFS',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Other meters
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _MeterRow(label: 'Short', value: '-12.8', unit: 'LUFS'),
                  _MeterRow(label: 'Range', value: '8.2', unit: 'LU'),
                  _MeterRow(label: 'Peak', value: '-1.2', unit: 'dBTP'),
                  const Spacer(),
                  _MeterRow(label: 'PLR', value: '13.0', unit: 'dB'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildInspectorPanel() {
    return LiquidGlassContainer(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'INSPECTOR',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),

          // Track info section
          _InspectorSection(
            title: 'Track',
            children: [
              _InspectorRow(label: 'Name', value: 'Lead Vocal'),
              _InspectorRow(label: 'Type', value: 'Audio'),
              _InspectorRow(label: 'Color', value: 'Orange', showColor: const Color(0xFFff9040)),
            ],
          ),

          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),

          // Clip info section
          _InspectorSection(
            title: 'Clip',
            children: [
              _InspectorRow(label: 'Name', value: 'vocal_take_03'),
              _InspectorRow(label: 'Start', value: '00:01:24.000'),
              _InspectorRow(label: 'Length', value: '00:00:32.450'),
              _InspectorRow(label: 'Gain', value: '+2.5 dB'),
            ],
          ),

          Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),

          // Quick controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QUICK CONTROLS',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _GlassKnob(value: 0.6, size: 36, label: 'Vol'),
                    _GlassKnob(value: 0.5, size: 36, label: 'Pan'),
                    _GlassKnob(value: 0.3, size: 36, label: 'Send'),
                  ],
                ),
              ],
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }
}

// ============================================================================
// LIQUID GLASS CONTAINER
// ============================================================================

class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final double borderRadius;
  final double blurAmount;
  final Color tintColor;
  final double tintOpacity;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.borderRadius = 16,
    this.blurAmount = 24,
    this.tintColor = Colors.white,
    this.tintOpacity = 0.08,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        // Outer glow
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.05),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
          child: Container(
            decoration: BoxDecoration(
              // Glass fill
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tintColor.withValues(alpha: tintOpacity + 0.04),
                  tintColor.withValues(alpha: tintOpacity),
                  tintColor.withValues(alpha: tintOpacity - 0.02),
                ],
              ),
              // Specular highlight border
              border: Border.all(
                width: 1,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Stack(
              children: [
                // Top specular highlight
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.3),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Content
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// GLASS COMPONENTS
// ============================================================================

class _ColorOrb extends StatelessWidget {
  final Color color;
  final double size;

  const _ColorOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _GlassKnob extends StatelessWidget {
  final double value;
  final double size;
  final String label;

  const _GlassKnob({
    required this.value,
    required this.size,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.15),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _KnobPainter(value: value),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 9,
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

    // Draw indicator line
    const startAngle = 2.4; // ~135 degrees
    const sweepRange = 4.3; // ~245 degrees
    final angle = startAngle + (sweepRange * value);

    final indicatorPaint = Paint()
      ..color = const Color(0xFF4a9eff)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final start = Offset(
      center.dx + (radius * 0.4) * -sin(angle),
      center.dy + (radius * 0.4) * cos(angle),
    );
    final end = Offset(
      center.dx + radius * -sin(angle),
      center.dy + radius * cos(angle),
    );

    canvas.drawLine(start, end, indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _GlassMeter extends StatelessWidget {
  final double value;
  final double peak;

  const _GlassMeter({required this.value, required this.peak});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Meter fill
              Container(
                height: constraints.maxHeight * value,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: const LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xFF40c8ff),
                      Color(0xFF40ff90),
                      Color(0xFFffff40),
                      Color(0xFFff9040),
                      Color(0xFFff4040),
                    ],
                    stops: [0.0, 0.5, 0.7, 0.85, 1.0],
                  ),
                ),
              ),
              // Peak indicator
              Positioned(
                bottom: constraints.maxHeight * peak - 2,
                child: Container(
                  width: double.infinity,
                  height: 2,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color color;

  const _GlassButton({
    required this.label,
    required this.isActive,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 22,
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? color : Colors.white.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final Color? activeColor;

  const _TransportButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? (activeColor ?? Colors.white) : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive
              ? color.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.15),
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: isActive ? color : Colors.white.withValues(alpha: 0.7),
          size: 20,
        ),
      ),
    );
  }
}

class _GlassToggle extends StatelessWidget {
  final String label;
  final bool isOn;

  const _GlassToggle({required this.label, required this.isOn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isOn
            ? const Color(0xFF4a9eff).withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isOn
              ? const Color(0xFF4a9eff).withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isOn ? const Color(0xFF4a9eff) : Colors.white.withValues(alpha: 0.6),
          fontSize: 11,
        ),
      ),
    );
  }
}

class _EQCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    // Horizontal grid (dB)
    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical grid (frequency)
    for (int i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // 0dB line
    final zeroPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    final zeroY = size.height / 2;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);

    // EQ curve
    final curvePath = Path();
    curvePath.moveTo(0, zeroY);

    // Simulated EQ curve with some boosts/cuts
    final points = <Offset>[
      Offset(0, zeroY),
      Offset(size.width * 0.08, zeroY - 15), // Low shelf boost
      Offset(size.width * 0.15, zeroY + 8),  // Cut at 250Hz
      Offset(size.width * 0.35, zeroY - 5),  // Slight boost
      Offset(size.width * 0.5, zeroY + 3),   // Slight cut
      Offset(size.width * 0.7, zeroY - 20),  // Presence boost
      Offset(size.width * 0.9, zeroY - 8),   // Air boost
      Offset(size.width, zeroY - 5),
    ];

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      curvePath.quadraticBezierTo(controlX, p0.dy, (p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
    }
    curvePath.lineTo(size.width, points.last.dy);

    // Fill under curve
    final fillPath = Path.from(curvePath);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF4a9eff).withValues(alpha: 0.3),
          const Color(0xFF4a9eff).withValues(alpha: 0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Draw curve line
    final curvePaint = Paint()
      ..color = const Color(0xFF4a9eff)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(curvePath, curvePaint);

    // Draw band points
    final bandPositions = [0.08, 0.15, 0.45, 0.7, 0.9];
    final bandColors = [
      const Color(0xFFff6b6b),
      const Color(0xFFffa94d),
      const Color(0xFF69db7c),
      const Color(0xFF4dabf7),
      const Color(0xFFda77f2),
    ];

    for (int i = 0; i < bandPositions.length; i++) {
      final x = size.width * bandPositions[i];
      // Find Y on curve (approximation)
      final idx = (bandPositions[i] * (points.length - 1)).round().clamp(0, points.length - 1);
      final y = points[idx].dy;

      // Glow
      final glowPaint = Paint()
        ..color = bandColors[i].withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(Offset(x, y), 8, glowPaint);

      // Point
      final pointPaint = Paint()..color = bandColors[i];
      canvas.drawCircle(Offset(x, y), 5, pointPaint);

      // Inner highlight
      final innerPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);
      canvas.drawCircle(Offset(x - 1, y - 1), 2, innerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EQBandControl extends StatelessWidget {
  final String freq;
  final String gain;
  final String q;
  final Color color;

  const _EQBandControl({
    required this.freq,
    required this.gain,
    required this.q,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          freq,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          gain,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MeterRow extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _MeterRow({
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
            ),
          ),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InspectorSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InspectorSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InspectorRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? showColor;

  const _InspectorRow({
    required this.label,
    required this.value,
    this.showColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
          Row(
            children: [
              if (showColor != null) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: showColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                value,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
