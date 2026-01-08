/// Surround Panner Panel
///
/// VBAP-based surround panning with:
/// - 3D position control (XY pad + height slider)
/// - Surround layouts: Stereo, 5.1, 7.1, 7.1.4, 9.1.6
/// - LFE level
/// - Spread control
/// - Distance attenuation

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../src/rust/native_ffi.dart';

/// Surround Panner Panel Widget
class SurroundPannerPanel extends StatefulWidget {
  final int trackId;
  final VoidCallback? onSettingsChanged;

  const SurroundPannerPanel({
    super.key,
    required this.trackId,
    this.onSettingsChanged,
  });

  @override
  State<SurroundPannerPanel> createState() => _SurroundPannerPanelState();
}

class _SurroundPannerPanelState extends State<SurroundPannerPanel> {
  final _ffi = NativeFFI.instance;
  bool _initialized = false;

  // Position (Cartesian -1 to 1)
  double _x = 0.0; // L/R
  double _y = 0.0; // Front/Back
  double _z = 0.0; // Height

  // Settings
  SurroundChannelLayout _layout = SurroundChannelLayout.surround51;
  double _spread = 0.0; // 0-180 degrees
  double _lfeLevel = -10.0; // dB
  double _distance = 1.0; // 0-1

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _ffi.surroundPannerRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = _ffi.surroundPannerCreate(widget.trackId, _layout);
    if (success) {
      setState(() => _initialized = true);
    }
  }

  void _updatePosition() {
    _ffi.surroundPannerSetPosition(widget.trackId, _x, _y, _z);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0C),
        border: Border.all(color: const Color(0xFF2A2A30)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFF2A2A30)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildLayoutSelector(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildSurroundPad()),
                  const SizedBox(height: 16),
                  _buildHeightSlider(),
                  const SizedBox(height: 16),
                  _buildControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.surround_sound, color: Color(0xFF40C8FF), size: 20),
          const SizedBox(width: 8),
          const Text(
            'SURROUND PANNER',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (!_initialized)
            const Text(
              'Initializing...',
              style: TextStyle(color: Color(0xFF808090), fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _buildLayoutSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final layout in SurroundChannelLayout.values)
          _buildLayoutButton(layout),
      ],
    );
  }

  Widget _buildLayoutButton(SurroundChannelLayout layout) {
    final isSelected = layout == _layout;
    final label = switch (layout) {
      SurroundChannelLayout.stereo => '2.0',
      SurroundChannelLayout.surround51 => '5.1',
      SurroundChannelLayout.surround71 => '7.1',
      SurroundChannelLayout.atmos714 => '7.1.4',
      SurroundChannelLayout.atmos916 => '9.1.6',
    };

    return GestureDetector(
      onTap: () {
        _ffi.surroundPannerRemove(widget.trackId);
        setState(() => _layout = layout);
        _ffi.surroundPannerCreate(widget.trackId, layout);
        _updatePosition();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF40C8FF) : const Color(0xFF1A1A20),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? const Color(0xFF40C8FF) : const Color(0xFF3A3A40),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF808090),
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSurroundPad() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: GestureDetector(
            onPanStart: (details) => _handlePan(details.localPosition, size),
            onPanUpdate: (details) => _handlePan(details.localPosition, size),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A20),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF3A3A40), width: 2),
              ),
              child: CustomPaint(
                painter: _SurroundPadPainter(
                  x: _x,
                  y: _y,
                  z: _z,
                  layout: _layout,
                  spread: _spread,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handlePan(Offset position, double size) {
    final center = size / 2;
    final dx = (position.dx - center) / center;
    final dy = (center - position.dy) / center; // Invert Y

    // Clamp to circle
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist > 1.0) {
      final scale = 1.0 / dist;
      setState(() {
        _x = dx * scale;
        _y = dy * scale;
      });
    } else {
      setState(() {
        _x = dx;
        _y = dy;
      });
    }
    _updatePosition();
  }

  Widget _buildHeightSlider() {
    final hasHeight = _layout == SurroundChannelLayout.atmos714 ||
                      _layout == SurroundChannelLayout.atmos916;

    return AnimatedOpacity(
      opacity: hasHeight ? 1.0 : 0.3,
      duration: const Duration(milliseconds: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'HEIGHT',
                style: TextStyle(
                  color: Color(0xFF808090),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                _z >= 0 ? '+${(_z * 100).toInt()}%' : '${(_z * 100).toInt()}%',
                style: const TextStyle(
                  color: Color(0xFF40C8FF),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 8,
              activeTrackColor: const Color(0xFF40C8FF),
              inactiveTrackColor: const Color(0xFF2A2A30),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayColor: const Color(0xFF40C8FF).withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _z,
              min: -1.0,
              max: 1.0,
              onChanged: hasHeight ? (v) {
                setState(() => _z = v);
                _updatePosition();
              } : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        Expanded(
          child: _buildControlColumn('SPREAD', '${_spread.toInt()}°', _spread, 0, 180, (v) {
            setState(() => _spread = v);
            _ffi.surroundPannerSetSpread(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildControlColumn('LFE', '${_lfeLevel.toStringAsFixed(1)} dB', _lfeLevel, -60, 0, (v) {
            setState(() => _lfeLevel = v);
            _ffi.surroundPannerSetLfeLevel(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildControlColumn('DISTANCE', '${(_distance * 100).toInt()}%', _distance, 0, 1, (v) {
            setState(() => _distance = v);
            _ffi.surroundPannerSetDistance(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
        ),
      ],
    );
  }

  Widget _buildControlColumn(String label, String value, double current, double min, double max, void Function(double) onChanged) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF808090),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF40C8FF),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: const SliderThemeData(
            trackHeight: 4,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: current.clamp(min, max),
            min: min,
            max: max,
            activeColor: const Color(0xFF40C8FF),
            inactiveColor: const Color(0xFF2A2A30),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SurroundPadPainter extends CustomPainter {
  final double x;
  final double y;
  final double z;
  final SurroundChannelLayout layout;
  final double spread;

  _SurroundPadPainter({
    required this.x,
    required this.y,
    required this.z,
    required this.layout,
    required this.spread,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw grid
    final gridPaint = Paint()
      ..color = const Color(0xFF2A2A30)
      ..strokeWidth = 1;

    // Concentric circles
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, gridPaint..style = PaintingStyle.stroke);
    }

    // Cross lines
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), gridPaint);

    // Draw speaker positions based on layout
    final speakerPaint = Paint()..color = const Color(0xFF606070);
    final speakers = _getSpeakerPositions();
    for (final pos in speakers) {
      final speakerOffset = Offset(
        center.dx + pos.dx * radius * 0.85,
        center.dy - pos.dy * radius * 0.85,
      );
      canvas.drawCircle(speakerOffset, 6, speakerPaint);
    }

    // Draw spread arc if applicable
    if (spread > 0) {
      final spreadPaint = Paint()
        ..color = const Color(0xFF40C8FF).withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;

      final angle = math.atan2(y, x);
      final spreadRad = spread * math.pi / 180;

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius * 0.7),
          -angle - spreadRad / 2 - math.pi / 2,
          spreadRad,
          false,
        )
        ..close();

      canvas.drawPath(path, spreadPaint);
    }

    // Draw source position
    final sourceOffset = Offset(
      center.dx + x * radius * 0.85,
      center.dy - y * radius * 0.85,
    );

    // Height indicator (glow size)
    final heightGlow = 8.0 + z.abs() * 12.0;
    final glowPaint = Paint()
      ..color = (z >= 0 ? const Color(0xFF40C8FF) : const Color(0xFFFF9040)).withValues(alpha: 0.3);
    canvas.drawCircle(sourceOffset, heightGlow, glowPaint);

    // Main source dot
    final sourcePaint = Paint()
      ..color = const Color(0xFF40C8FF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(sourceOffset, 10, sourcePaint);

    // Height ring
    if (z != 0) {
      final ringPaint = Paint()
        ..color = z >= 0 ? const Color(0xFF40C8FF) : const Color(0xFFFF9040)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(sourceOffset, 14 + z.abs() * 4, ringPaint);
    }

    // Center dot
    final centerDot = Paint()..color = Colors.white;
    canvas.drawCircle(sourceOffset, 4, centerDot);
  }

  List<Offset> _getSpeakerPositions() {
    return switch (layout) {
      SurroundChannelLayout.stereo => const [
        Offset(-0.7, 0.7),  // L
        Offset(0.7, 0.7),   // R
      ],
      SurroundChannelLayout.surround51 => const [
        Offset(-0.7, 0.7),  // L
        Offset(0, 1),       // C
        Offset(0.7, 0.7),   // R
        Offset(-0.9, -0.5), // Ls
        Offset(0.9, -0.5),  // Rs
      ],
      SurroundChannelLayout.surround71 => const [
        Offset(-0.7, 0.7),  // L
        Offset(0, 1),       // C
        Offset(0.7, 0.7),   // R
        Offset(-1, 0),      // Lss
        Offset(1, 0),       // Rss
        Offset(-0.8, -0.6), // Lrs
        Offset(0.8, -0.6),  // Rrs
      ],
      SurroundChannelLayout.atmos714 || SurroundChannelLayout.atmos916 => const [
        Offset(-0.7, 0.7),  // L
        Offset(0, 1),       // C
        Offset(0.7, 0.7),   // R
        Offset(-1, 0),      // Lss
        Offset(1, 0),       // Rss
        Offset(-0.8, -0.6), // Lrs
        Offset(0.8, -0.6),  // Rrs
        // Height speakers shown smaller
      ],
    };
  }

  @override
  bool shouldRepaint(covariant _SurroundPadPainter oldDelegate) {
    return x != oldDelegate.x || y != oldDelegate.y || z != oldDelegate.z ||
           layout != oldDelegate.layout || spread != oldDelegate.spread;
  }
}
