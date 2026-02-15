/// Stereo Imager Panel
///
/// Professional stereo field control with:
/// - Stereo width (0-200%)
/// - Pan with law selection
/// - L/R Balance
/// - Mid/Side gain control
/// - Stereo rotation
/// - Correlation meter
/// - Visual goniometer

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Stereo Imager Panel Widget
class StereoImagerPanel extends StatefulWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const StereoImagerPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<StereoImagerPanel> createState() => _StereoImagerPanelState();
}

class _StereoImagerPanelState extends State<StereoImagerPanel> {
  final _ffi = NativeFFI.instance;
  bool _initialized = false;

  // Width processing
  bool _widthEnabled = true;
  double _width = 1.0; // 0.0 - 2.0 (100% = unity)

  // Panner
  bool _pannerEnabled = false;
  double _pan = 0.0; // -1 to 1
  PanLaw _panLaw = PanLaw.linear;

  // Balance
  bool _balanceEnabled = false;
  double _balance = 0.0; // -1 to 1

  // Mid/Side
  bool _msEnabled = false;
  double _midGain = 0.0; // dB
  double _sideGain = 0.0; // dB

  // Rotation
  bool _rotationEnabled = false;
  double _rotation = 0.0; // -180 to 180 degrees

  // Metering
  double _correlation = 1.0;
  Timer? _meterTimer;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    _ffi.stereoImagerRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    // Do NOT auto-create stereo imager — must be created externally
  }

  void _startMetering() {
    _meterTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && _initialized) {
        final correlation = _ffi.stereoImagerGetCorrelation(widget.trackId);
        setState(() => _correlation = correlation);
      }
    });
  }

  void _updateWidth() {
    _ffi.stereoImagerSetWidth(widget.trackId, _width);
    widget.onSettingsChanged?.call();
  }

  void _updatePan() {
    _ffi.stereoImagerSetPan(widget.trackId, _pan);
    widget.onSettingsChanged?.call();
  }

  void _updatePanLaw() {
    _ffi.stereoImagerSetPanLaw(widget.trackId, _panLaw);
    widget.onSettingsChanged?.call();
  }

  void _updateBalance() {
    _ffi.stereoImagerSetBalance(widget.trackId, _balance);
    widget.onSettingsChanged?.call();
  }

  void _updateMidGain() {
    _ffi.stereoImagerSetMidGain(widget.trackId, _midGain);
    widget.onSettingsChanged?.call();
  }

  void _updateSideGain() {
    _ffi.stereoImagerSetSideGain(widget.trackId, _sideGain);
    widget.onSettingsChanged?.call();
  }

  void _updateRotation() {
    _ffi.stereoImagerSetRotation(widget.trackId, _rotation);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgVoid,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Stereo visualization
                  _buildStereoScope(),
                  const SizedBox(height: 16),
                  // Correlation meter
                  _buildCorrelationMeter(),
                  const SizedBox(height: 24),
                  // Width section
                  _buildWidthSection(),
                  const SizedBox(height: 16),
                  // Pan section
                  _buildPanSection(),
                  const SizedBox(height: 16),
                  // Balance section
                  _buildBalanceSection(),
                  const SizedBox(height: 16),
                  // Mid/Side section
                  _buildMSSection(),
                  const SizedBox(height: 16),
                  // Rotation section
                  _buildRotationSection(),
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
          const Icon(Icons.spatial_audio, color: FluxForgeTheme.accentCyan, size: 20),
          const SizedBox(width: 8),
          const Text(
            'STEREO IMAGER',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (!_initialized)
            const Text(
              'Initializing...',
              style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
            )
          else
            GestureDetector(
              onTap: () {
                _ffi.stereoImagerReset(widget.trackId);
                setState(() {
                  _width = 1.0;
                  _pan = 0.0;
                  _balance = 0.0;
                  _midGain = 0.0;
                  _sideGain = 0.0;
                  _rotation = 0.0;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'RESET',
                  style: TextStyle(
                    color: FluxForgeTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStereoScope() {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: CustomPaint(
        painter: _StereoScopePainter(
          width: _width,
          pan: _pan,
          rotation: _rotation,
          correlation: _correlation,
        ),
        size: Size.infinite,
      ),
    );
  }

  Widget _buildCorrelationMeter() {
    final correlationColor = _correlation >= 0.5
        ? FluxForgeTheme.accentGreen
        : _correlation >= 0
            ? FluxForgeTheme.accentYellow
            : FluxForgeTheme.accentRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'CORRELATION',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              _correlation.toStringAsFixed(2),
              style: TextStyle(
                color: correlationColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Stack(
            children: [
              // Scale marks
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('-1', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 8)),
                    Text('0', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 8)),
                    Text('+1', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 8)),
                  ],
                ),
              ),
              // Correlation bar
              Positioned(
                left: ((_correlation + 1) / 2) * 200, // Approximate
                top: 2,
                child: Container(
                  width: 4,
                  height: 8,
                  decoration: BoxDecoration(
                    color: correlationColor,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('Out of Phase', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9)),
            Text('Mono', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9)),
            Text('In Phase', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9)),
          ],
        ),
      ],
    );
  }

  Widget _buildWidthSection() {
    return _buildSection(
      title: 'STEREO WIDTH',
      enabled: _widthEnabled,
      onToggle: (v) {
        setState(() => _widthEnabled = v);
        _ffi.stereoImagerEnableWidth(widget.trackId, v);
        widget.onSettingsChanged?.call();
      },
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Width', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
              Text(
                '${(_width * 100).round()}%',
                style: TextStyle(
                  color: _width == 1.0 ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: _sliderTheme(),
            child: Slider(
              value: _width,
              min: 0.0,
              max: 2.0,
              onChanged: _widthEnabled
                  ? (v) {
                      setState(() => _width = v);
                      _updateWidth();
                    }
                  : null,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Mono', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9)),
              Text('Stereo', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9)),
              Text('Wide', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanSection() {
    return _buildSection(
      title: 'PAN',
      enabled: _pannerEnabled,
      onToggle: (v) {
        setState(() => _pannerEnabled = v);
        _ffi.stereoImagerEnablePanner(widget.trackId, v);
        widget.onSettingsChanged?.call();
      },
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Position', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
              Text(
                _pan == 0 ? 'C' : _pan < 0 ? 'L${(_pan.abs() * 100).round()}' : 'R${(_pan * 100).round()}',
                style: TextStyle(
                  color: _pan == 0 ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: _sliderTheme(),
            child: Slider(
              value: _pan,
              min: -1.0,
              max: 1.0,
              onChanged: _pannerEnabled
                  ? (v) {
                      setState(() => _pan = v);
                      _updatePan();
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Pan Law', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
              DropdownButton<PanLaw>(
                value: _panLaw,
                dropdownColor: FluxForgeTheme.bgMid,
                style: const TextStyle(color: Color(0xFF40C8FF), fontSize: 11),
                underline: const SizedBox(),
                items: PanLaw.values.map((law) {
                  return DropdownMenuItem(
                    value: law,
                    child: Text(_panLawName(law)),
                  );
                }).toList(),
                onChanged: _pannerEnabled
                    ? (v) {
                        if (v != null) {
                          setState(() => _panLaw = v);
                          _updatePanLaw();
                        }
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _panLawName(PanLaw law) {
    switch (law) {
      case PanLaw.linear:
        return 'Linear (0dB)';
      case PanLaw.constantPower:
        return 'Constant Power (-3dB)';
      case PanLaw.compromise:
        return 'Compromise (-4.5dB)';
      case PanLaw.noCenterAttenuation:
        return 'No Attenuation';
    }
  }

  Widget _buildBalanceSection() {
    return _buildSection(
      title: 'BALANCE',
      enabled: _balanceEnabled,
      onToggle: (v) {
        setState(() => _balanceEnabled = v);
        _ffi.stereoImagerEnableBalance(widget.trackId, v);
        widget.onSettingsChanged?.call();
      },
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('L/R Balance', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
              Text(
                _balance == 0 ? 'C' : _balance < 0 ? 'L${(_balance.abs() * 100).round()}' : 'R${(_balance * 100).round()}',
                style: TextStyle(
                  color: _balance == 0 ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: _sliderTheme(),
            child: Slider(
              value: _balance,
              min: -1.0,
              max: 1.0,
              onChanged: _balanceEnabled
                  ? (v) {
                      setState(() => _balance = v);
                      _updateBalance();
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMSSection() {
    return _buildSection(
      title: 'MID/SIDE',
      enabled: _msEnabled,
      onToggle: (v) {
        setState(() => _msEnabled = v);
        _ffi.stereoImagerEnableMs(widget.trackId, v);
        widget.onSettingsChanged?.call();
      },
      child: Row(
        children: [
          Expanded(
            child: _buildKnob(
              label: 'MID',
              value: _midGain,
              min: -24.0,
              max: 12.0,
              format: (v) => '${v >= 0 ? "+" : ""}${v.toStringAsFixed(1)} dB',
              enabled: _msEnabled,
              onChanged: (v) {
                setState(() => _midGain = v);
                _updateMidGain();
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildKnob(
              label: 'SIDE',
              value: _sideGain,
              min: -24.0,
              max: 12.0,
              format: (v) => '${v >= 0 ? "+" : ""}${v.toStringAsFixed(1)} dB',
              enabled: _msEnabled,
              onChanged: (v) {
                setState(() => _sideGain = v);
                _updateSideGain();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRotationSection() {
    return _buildSection(
      title: 'STEREO ROTATION',
      enabled: _rotationEnabled,
      onToggle: (v) {
        setState(() => _rotationEnabled = v);
        _ffi.stereoImagerEnableRotation(widget.trackId, v);
        widget.onSettingsChanged?.call();
      },
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Angle', style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11)),
              Text(
                '${_rotation.round()}°',
                style: TextStyle(
                  color: _rotation == 0 ? FluxForgeTheme.textTertiary : FluxForgeTheme.accentCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: _sliderTheme(),
            child: Slider(
              value: _rotation,
              min: -180.0,
              max: 180.0,
              onChanged: _rotationEnabled
                  ? (v) {
                      setState(() => _rotation = v);
                      _updateRotation();
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled ? FluxForgeTheme.bgDeep : FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled ? FluxForgeTheme.borderMedium : FluxForgeTheme.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: enabled ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              GestureDetector(
                onTap: () => onToggle(!enabled),
                child: Container(
                  width: 36,
                  height: 18,
                  decoration: BoxDecoration(
                    color: enabled ? FluxForgeTheme.accentCyan : FluxForgeTheme.borderSubtle,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 150),
                    alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.textPrimary,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: enabled ? 1.0 : 0.4,
            child: AbsorbPointer(
              absorbing: !enabled,
              child: child,
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
    required String Function(double) format,
    required bool enabled,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF808090),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onVerticalDragUpdate: enabled
              ? (details) {
                  final delta = -details.delta.dy * (max - min) / 200;
                  onChanged((value + delta).clamp(min, max));
                }
              : null,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: FluxForgeTheme.bgMid,
              border: Border.all(color: FluxForgeTheme.borderMedium, width: 2),
            ),
            child: CustomPaint(
              painter: _KnobPainter(
                value: (value - min) / (max - min),
                enabled: enabled,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          format(value),
          style: TextStyle(
            color: enabled ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  SliderThemeData _sliderTheme() {
    return const SliderThemeData(
      trackHeight: 4,
      activeTrackColor: Color(0xFF40C8FF),
      inactiveTrackColor: Color(0xFF2A2A30),
      thumbColor: FluxForgeTheme.textPrimary,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
      overlayColor: Color(0x2040C8FF),
    );
  }
}

class _StereoScopePainter extends CustomPainter {
  final double width;
  final double pan;
  final double rotation;
  final double correlation;

  _StereoScopePainter({
    required this.width,
    required this.pan,
    required this.rotation,
    required this.correlation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 20;

    // Background grid
    final gridPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Concentric circles
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, gridPaint);
    }

    // Cross
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      gridPaint,
    );

    // Diagonal (L/R axes)
    canvas.drawLine(
      Offset(center.dx - radius * 0.7, center.dy - radius * 0.7),
      Offset(center.dx + radius * 0.7, center.dy + radius * 0.7),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx + radius * 0.7, center.dy - radius * 0.7),
      Offset(center.dx - radius * 0.7, center.dy + radius * 0.7),
      gridPaint,
    );

    // Labels
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    void drawLabel(String text, Offset pos) {
      textPainter.text = TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF606070), fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, pos - Offset(textPainter.width / 2, textPainter.height / 2));
    }

    drawLabel('L', Offset(center.dx - radius - 12, center.dy));
    drawLabel('R', Offset(center.dx + radius + 12, center.dy));
    drawLabel('M', Offset(center.dx, center.dy - radius - 12));
    drawLabel('S', Offset(center.dx, center.dy + radius + 12));

    // Stereo field visualization
    final rotRad = rotation * math.pi / 180;
    final widthScale = width.clamp(0.1, 2.0);

    // Draw stereo field as a cone
    final fieldPaint = Paint()
      ..color = FluxForgeTheme.accentCyan.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final leftAngle = math.pi / 2 + rotRad - (math.pi / 4 * widthScale);
    final rightAngle = math.pi / 2 + rotRad + (math.pi / 4 * widthScale);

    final path = Path()
      ..moveTo(center.dx + pan * radius * 0.3, center.dy)
      ..lineTo(
        center.dx + math.cos(leftAngle) * radius * 0.9,
        center.dy - math.sin(leftAngle) * radius * 0.9,
      )
      ..lineTo(
        center.dx + math.cos(rightAngle) * radius * 0.9,
        center.dy - math.sin(rightAngle) * radius * 0.9,
      )
      ..close();

    canvas.drawPath(path, fieldPaint);

    // Outline
    final outlinePaint = Paint()
      ..color = FluxForgeTheme.accentCyan
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, outlinePaint);

    // Center point (pan position)
    final centerPaint = Paint()..color = FluxForgeTheme.accentCyan;
    canvas.drawCircle(
      Offset(center.dx + pan * radius * 0.3, center.dy),
      6,
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _StereoScopePainter oldDelegate) {
    return width != oldDelegate.width ||
        pan != oldDelegate.pan ||
        rotation != oldDelegate.rotation ||
        correlation != oldDelegate.correlation;
  }
}

class _KnobPainter extends CustomPainter {
  final double value;
  final bool enabled;

  _KnobPainter({required this.value, required this.enabled});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;

    // Arc background
    final bgPaint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = 0.75 * math.pi;
    const sweepAngle = 1.5 * math.pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Value arc
    if (enabled) {
      final valuePaint = Paint()
        ..color = FluxForgeTheme.accentCyan
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * value,
        false,
        valuePaint,
      );
    }

    // Indicator line
    final indicatorAngle = startAngle + sweepAngle * value;
    final indicatorPaint = Paint()
      ..color = enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      Offset(
        center.dx + math.cos(indicatorAngle) * (radius - 8),
        center.dy + math.sin(indicatorAngle) * (radius - 8),
      ),
      indicatorPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return value != oldDelegate.value || enabled != oldDelegate.enabled;
  }
}
