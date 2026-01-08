// Pultec EQP-1A Emulation Widget
//
// Skeuomorphic recreation of the legendary Pultec passive tube EQ
// Features:
// - Authentic "boost and cut" low frequency design
// - Separate low/high frequency sections
// - Vintage VU meter with needle animation
// - Tube glow effect
// - True passive filter modeling in backend

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pultec EQP-1A parameter set
class PultecParams {
  // Low Frequency Section
  final double lowBoost;      // 0-10 (dB)
  final double lowAtten;      // 0-10 (dB)
  final int lowFreq;          // 20, 30, 60, 100 Hz

  // High Frequency Section
  final double highBoost;     // 0-10 (dB)
  final int highBoostFreq;    // 3k, 4k, 5k, 8k, 10k, 12k, 16k Hz
  final double highAtten;     // 0-10 (dB)
  final int highAttenFreq;    // 5k, 10k, 20k Hz

  // Bandwidth
  final double bandwidth;     // 0-10 (Q inverse - wider at higher values)

  // Global
  final bool bypass;
  final double outputLevel;   // -12 to +12 dB

  const PultecParams({
    this.lowBoost = 0,
    this.lowAtten = 0,
    this.lowFreq = 60,
    this.highBoost = 0,
    this.highBoostFreq = 8000,
    this.highAtten = 0,
    this.highAttenFreq = 10000,
    this.bandwidth = 5,
    this.bypass = false,
    this.outputLevel = 0,
  });

  PultecParams copyWith({
    double? lowBoost,
    double? lowAtten,
    int? lowFreq,
    double? highBoost,
    int? highBoostFreq,
    double? highAtten,
    int? highAttenFreq,
    double? bandwidth,
    bool? bypass,
    double? outputLevel,
  }) {
    return PultecParams(
      lowBoost: lowBoost ?? this.lowBoost,
      lowAtten: lowAtten ?? this.lowAtten,
      lowFreq: lowFreq ?? this.lowFreq,
      highBoost: highBoost ?? this.highBoost,
      highBoostFreq: highBoostFreq ?? this.highBoostFreq,
      highAtten: highAtten ?? this.highAtten,
      highAttenFreq: highAttenFreq ?? this.highAttenFreq,
      bandwidth: bandwidth ?? this.bandwidth,
      bypass: bypass ?? this.bypass,
      outputLevel: outputLevel ?? this.outputLevel,
    );
  }
}

/// Pultec EQP-1A Widget
class PultecEq extends StatefulWidget {
  final PultecParams initialParams;
  final ValueChanged<PultecParams>? onParamsChanged;
  final double? vuLevel; // -60 to 0 dB for VU meter

  const PultecEq({
    super.key,
    this.initialParams = const PultecParams(),
    this.onParamsChanged,
    this.vuLevel,
  });

  @override
  State<PultecEq> createState() => _PultecEqState();
}

class _PultecEqState extends State<PultecEq> with SingleTickerProviderStateMixin {
  late PultecParams _params;
  late AnimationController _glowController;

  // VU needle animation
  double _needleAngle = -45; // degrees from center

  @override
  void initState() {
    super.initState();
    _params = widget.initialParams;
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PultecEq oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vuLevel != null) {
      // Animate needle to new position
      final targetAngle = _vuToAngle(widget.vuLevel!);
      setState(() => _needleAngle = targetAngle);
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  double _vuToAngle(double db) {
    // VU meter: -20 to +3 dB, maps to -45 to +45 degrees
    final normalized = ((db + 20) / 23).clamp(0.0, 1.0);
    return -45 + normalized * 90;
  }

  void _updateParams(PultecParams newParams) {
    setState(() => _params = newParams);
    widget.onParamsChanged?.call(newParams);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF4A4540), // Cream/beige top
            Color(0xFF3A3530), // Darker bottom
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2520), width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(128),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Title and VU meter
          _buildHeader(),

          // Main controls
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Low Frequency Section
                  Expanded(child: _buildLowSection()),

                  const SizedBox(width: 24),

                  // Bandwidth control
                  _buildBandwidthSection(),

                  const SizedBox(width: 24),

                  // High Frequency Section
                  Expanded(child: _buildHighSection()),
                ],
              ),
            ),
          ),

          // Bottom controls (bypass, output)
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // PULTEC logo
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PULTEC',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFD4C5A0),
                  shadows: [
                    Shadow(
                      color: Colors.black.withAlpha(128),
                      offset: const Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
              const Text(
                'PROGRAM EQUALIZER',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: Color(0xFF8A8070),
                ),
              ),
            ],
          ),

          const Spacer(),

          // VU Meter
          _buildVuMeter(),

          const Spacer(),

          // Model number
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              Text(
                'EQP-1A',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD4C5A0),
                ),
              ),
              Text(
                'TUBE PROGRAM EQ',
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 1,
                  color: Color(0xFF8A8070),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVuMeter() {
    return Container(
      width: 160,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0E0),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2520), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(64),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // VU scale
          CustomPaint(
            size: const Size(160, 60),
            painter: _VuScalePainter(),
          ),

          // Needle
          Center(
            child: Transform.rotate(
              angle: _needleAngle * math.pi / 180,
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 2,
                height: 35,
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1510),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(1)),
                ),
              ),
            ),
          ),

          // VU label
          const Positioned(
            bottom: 4,
            left: 0,
            right: 0,
            child: Text(
              'VU',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4A4540),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLowSection() {
    return Column(
      children: [
        const Text(
          'LOW FREQUENCY',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            color: Color(0xFFD4C5A0),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // Low frequency selector
        _buildFreqSelector(
          label: 'CPS',
          frequencies: const [20, 30, 60, 100],
          selected: _params.lowFreq,
          onChanged: (f) => _updateParams(_params.copyWith(lowFreq: f)),
        ),

        const SizedBox(height: 16),

        // Boost and Atten knobs side by side
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKnob(
              label: 'BOOST',
              value: _params.lowBoost,
              min: 0,
              max: 10,
              color: const Color(0xFF4A8040), // Green
              onChanged: (v) => _updateParams(_params.copyWith(lowBoost: v)),
            ),
            const SizedBox(width: 16),
            _buildKnob(
              label: 'ATTEN',
              value: _params.lowAtten,
              min: 0,
              max: 10,
              color: const Color(0xFFB04040), // Red
              onChanged: (v) => _updateParams(_params.copyWith(lowAtten: v)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBandwidthSection() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'BANDWIDTH',
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 1,
            color: Color(0xFFD4C5A0),
          ),
        ),
        const SizedBox(height: 8),
        _buildKnob(
          label: '',
          value: _params.bandwidth,
          min: 0,
          max: 10,
          color: const Color(0xFF6080A0), // Blue-gray
          size: 60,
          onChanged: (v) => _updateParams(_params.copyWith(bandwidth: v)),
        ),

        const SizedBox(height: 24),

        // Tube glow indicator
        AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            final glow = 0.3 + _glowController.value * 0.4;
            return Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  const Color(0xFF402010),
                  const Color(0xFFFF8040),
                  _params.bypass ? 0 : glow,
                ),
                boxShadow: _params.bypass ? null : [
                  BoxShadow(
                    color: const Color(0xFFFF8040).withAlpha((glow * 128).toInt()),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        const Text(
          'TUBE',
          style: TextStyle(
            fontSize: 7,
            color: Color(0xFF8A8070),
          ),
        ),
      ],
    );
  }

  Widget _buildHighSection() {
    return Column(
      children: [
        const Text(
          'HIGH FREQUENCY',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 2,
            color: Color(0xFFD4C5A0),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        // High boost section
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              children: [
                _buildFreqSelector(
                  label: 'KCS',
                  frequencies: const [3000, 4000, 5000, 8000, 10000, 12000, 16000],
                  selected: _params.highBoostFreq,
                  displayDivider: 1000,
                  onChanged: (f) => _updateParams(_params.copyWith(highBoostFreq: f)),
                ),
                const SizedBox(height: 8),
                _buildKnob(
                  label: 'BOOST',
                  value: _params.highBoost,
                  min: 0,
                  max: 10,
                  color: const Color(0xFF4A8040),
                  size: 50,
                  onChanged: (v) => _updateParams(_params.copyWith(highBoost: v)),
                ),
              ],
            ),

            const SizedBox(width: 16),

            // High atten section
            Column(
              children: [
                _buildFreqSelector(
                  label: 'KCS',
                  frequencies: const [5000, 10000, 20000],
                  selected: _params.highAttenFreq,
                  displayDivider: 1000,
                  onChanged: (f) => _updateParams(_params.copyWith(highAttenFreq: f)),
                ),
                const SizedBox(height: 8),
                _buildKnob(
                  label: 'ATTEN',
                  value: _params.highAtten,
                  min: 0,
                  max: 10,
                  color: const Color(0xFFB04040),
                  size: 50,
                  onChanged: (v) => _updateParams(_params.copyWith(highAtten: v)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFreqSelector({
    required String label,
    required List<int> frequencies,
    required int selected,
    int displayDivider = 1,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2520),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF1A1510)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              color: Color(0xFF8A8070),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selected,
              isDense: true,
              dropdownColor: const Color(0xFF2A2520),
              style: const TextStyle(
                color: Color(0xFFD4C5A0),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              items: frequencies.map((f) {
                final display = displayDivider > 1 ? '${f ~/ displayDivider}' : '$f';
                return DropdownMenuItem(
                  value: f,
                  child: Text(display),
                );
              }).toList(),
              onChanged: (v) => onChanged(v!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKnob({
    required String label,
    required double value,
    required double min,
    required double max,
    required Color color,
    double size = 70,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        GestureDetector(
          onVerticalDragUpdate: (details) {
            final delta = -details.delta.dy / 100;
            final newValue = (value + delta * (max - min)).clamp(min, max);
            onChanged(newValue);
          },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Color.lerp(color, Colors.white, 0.3)!,
                  color,
                  Color.lerp(color, Colors.black, 0.3)!,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              border: Border.all(
                color: const Color(0xFF1A1510),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(64),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Knob pointer
                Transform.rotate(
                  angle: ((value - min) / (max - min) * 270 - 135) * math.pi / 180,
                  child: Align(
                    alignment: const Alignment(0, -0.7),
                    child: Container(
                      width: 4,
                      height: size * 0.2,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F0E0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),

                // Value display
                Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: size * 0.18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFF5F0E0),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFFD4C5A0),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Bypass toggle
          GestureDetector(
            onTap: () => _updateParams(_params.copyWith(bypass: !_params.bypass)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _params.bypass ? const Color(0xFFB04040) : const Color(0xFF2A2520),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF1A1510)),
              ),
              child: Text(
                'BYPASS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _params.bypass ? Colors.white : const Color(0xFF8A8070),
                ),
              ),
            ),
          ),

          const Spacer(),

          // Output level
          Row(
            children: [
              const Text(
                'OUTPUT',
                style: TextStyle(
                  fontSize: 9,
                  color: Color(0xFF8A8070),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: Slider(
                  value: _params.outputLevel,
                  min: -12,
                  max: 12,
                  onChanged: (v) => _updateParams(_params.copyWith(outputLevel: v)),
                  activeColor: const Color(0xFFD4C5A0),
                  inactiveColor: const Color(0xFF2A2520),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  '${_params.outputLevel >= 0 ? '+' : ''}${_params.outputLevel.toStringAsFixed(1)} dB',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFD4C5A0),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// VU meter scale painter
class _VuScalePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1510)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height - 5);
    final radius = size.height - 15;

    // Draw scale arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.75,
      math.pi * 0.5,
      false,
      paint,
    );

    // Draw scale marks and labels
    final marks = ['-20', '-10', '-7', '-5', '-3', '-1', '0', '+1', '+2', '+3'];
    for (int i = 0; i < marks.length; i++) {
      final angle = -math.pi * 0.75 + (i / (marks.length - 1)) * math.pi * 0.5;
      final innerRadius = radius - 8;
      final outerRadius = radius;

      final inner = Offset(
        center.dx + math.cos(angle) * innerRadius,
        center.dy + math.sin(angle) * innerRadius,
      );
      final outer = Offset(
        center.dx + math.cos(angle) * outerRadius,
        center.dy + math.sin(angle) * outerRadius,
      );

      canvas.drawLine(inner, outer, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
