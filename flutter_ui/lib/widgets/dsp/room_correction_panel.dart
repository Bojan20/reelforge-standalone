/// Room Correction EQ Panel
///
/// Automatic room correction EQ with:
/// - Target curves: Flat, Harman, B&K, BBC, X-Curve, Custom
/// - Max correction limit (3-24 dB)
/// - Cut-only mode option
/// - Measurement integration placeholder

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

/// Room Correction EQ Panel Widget
class RoomCorrectionPanel extends StatefulWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const RoomCorrectionPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<RoomCorrectionPanel> createState() => _RoomCorrectionPanelState();
}

class _RoomCorrectionPanelState extends State<RoomCorrectionPanel> {
  final _ffi = NativeFFI.instance;
  bool _initialized = false;
  bool _enabled = true;

  RoomTargetCurve _targetCurve = RoomTargetCurve.harman;
  double _maxCorrection = 12.0;
  bool _cutOnly = false;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    _ffi.roomEqDestroy(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = _ffi.roomEqCreate(widget.trackId, sampleRate: widget.sampleRate);
    if (success) {
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgVoid,
        border: Border.all(color: ReelForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Divider(height: 1, color: ReelForgeTheme.borderSubtle),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(child: _buildCurveVisualization()),
                  const SizedBox(height: 16),
                  _buildTargetCurveSelector(),
                  const SizedBox(height: 16),
                  _buildSettings(),
                  const SizedBox(height: 16),
                  _buildMeasurementSection(),
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
          Icon(Icons.home, color: ReelForgeTheme.accentCyan, size: 20),
          const SizedBox(width: 8),
          Text(
            'ROOM CORRECTION',
            style: TextStyle(
              color: ReelForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          _buildEnableButton(),
        ],
      ),
    );
  }

  Widget _buildEnableButton() {
    return GestureDetector(
      onTap: () {
        setState(() => _enabled = !_enabled);
        _ffi.roomEqSetEnabled(widget.trackId, _enabled);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _enabled
              ? ReelForgeTheme.accentGreen.withValues(alpha: 0.3)
              : ReelForgeTheme.accentRed.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _enabled ? ReelForgeTheme.accentGreen : ReelForgeTheme.accentRed,
          ),
        ),
        child: Text(
          _enabled ? 'ACTIVE' : 'BYPASS',
          style: TextStyle(
            color: _enabled ? ReelForgeTheme.accentGreen : ReelForgeTheme.accentRed,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildCurveVisualization() {
    return Container(
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: CustomPaint(
        painter: _RoomCorrectionCurvePainter(
          targetCurve: _targetCurve,
          maxCorrection: _maxCorrection,
          cutOnly: _cutOnly,
          enabled: _enabled,
        ),
      ),
    );
  }

  Widget _buildTargetCurveSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TARGET CURVE',
          style: TextStyle(
            color: ReelForgeTheme.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: RoomTargetCurve.values.map((curve) {
            final isSelected = curve == _targetCurve;
            final (label, color) = _getCurveInfo(curve);
            return GestureDetector(
              onTap: () {
                setState(() => _targetCurve = curve);
                _ffi.roomEqSetTargetCurve(widget.trackId, curve);
                widget.onSettingsChanged?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.3) : ReelForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? color : ReelForgeTheme.borderMedium,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? color : ReelForgeTheme.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getCurveDescription(curve),
                      style: TextStyle(
                        color: isSelected ? color.withValues(alpha: 0.7) : ReelForgeTheme.textTertiary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  (String, Color) _getCurveInfo(RoomTargetCurve curve) {
    return switch (curve) {
      RoomTargetCurve.flat => ('FLAT', ReelForgeTheme.accentCyan),
      RoomTargetCurve.harman => ('HARMAN', ReelForgeTheme.accentGreen),
      RoomTargetCurve.bAndK => ('B&K', ReelForgeTheme.accentOrange),
      RoomTargetCurve.bbc => ('BBC', ReelForgeTheme.accentYellow),
      RoomTargetCurve.xCurve => ('X-CURVE', ReelForgeTheme.accentPink),
      RoomTargetCurve.custom => ('CUSTOM', ReelForgeTheme.textTertiary),
    };
  }

  String _getCurveDescription(RoomTargetCurve curve) {
    return switch (curve) {
      RoomTargetCurve.flat => 'Linear response',
      RoomTargetCurve.harman => 'Hi-Fi preference',
      RoomTargetCurve.bAndK => 'Studio reference',
      RoomTargetCurve.bbc => 'Broadcast standard',
      RoomTargetCurve.xCurve => 'Cinema calibration',
      RoomTargetCurve.custom => 'User defined',
    };
  }

  Widget _buildSettings() {
    return Row(
      children: [
        // Max correction slider
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'MAX CORRECTION',
                    style: TextStyle(
                      color: ReelForgeTheme.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_maxCorrection.toStringAsFixed(1)} dB',
                    style: TextStyle(
                      color: ReelForgeTheme.accentCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 6,
                  activeTrackColor: ReelForgeTheme.accentCyan,
                  inactiveTrackColor: ReelForgeTheme.borderSubtle,
                  thumbColor: ReelForgeTheme.accentCyan,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayColor: ReelForgeTheme.accentCyan.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: _maxCorrection,
                  min: 3,
                  max: 24,
                  divisions: 21,
                  onChanged: (v) {
                    setState(() => _maxCorrection = v);
                    _ffi.roomEqSetMaxCorrection(widget.trackId, v);
                    widget.onSettingsChanged?.call();
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Cut only toggle
        GestureDetector(
          onTap: () {
            setState(() => _cutOnly = !_cutOnly);
            _ffi.roomEqSetCutOnly(widget.trackId, _cutOnly);
            widget.onSettingsChanged?.call();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _cutOnly
                  ? ReelForgeTheme.accentOrange.withValues(alpha: 0.3)
                  : ReelForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _cutOnly ? ReelForgeTheme.accentOrange : ReelForgeTheme.borderMedium,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.content_cut,
                  color: _cutOnly ? ReelForgeTheme.accentOrange : ReelForgeTheme.textTertiary,
                  size: 20,
                ),
                const SizedBox(height: 4),
                Text(
                  'CUT ONLY',
                  style: TextStyle(
                    color: _cutOnly ? ReelForgeTheme.accentOrange : ReelForgeTheme.textTertiary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMeasurementSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, color: ReelForgeTheme.textTertiary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ROOM MEASUREMENT',
                  style: TextStyle(
                    color: ReelForgeTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _initialized ? 'Ready to measure' : 'Initializing...',
                  style: TextStyle(
                    color: ReelForgeTheme.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _initialized ? _startMeasurement : null,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('MEASURE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ReelForgeTheme.accentCyan,
              foregroundColor: ReelForgeTheme.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.refresh, color: ReelForgeTheme.textTertiary, size: 20),
            onPressed: () {
              _ffi.roomEqReset(widget.trackId);
              widget.onSettingsChanged?.call();
            },
            tooltip: 'Reset correction',
          ),
        ],
      ),
    );
  }

  void _startMeasurement() {
    // TODO: Implement measurement workflow
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Measurement feature coming soon'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _RoomCorrectionCurvePainter extends CustomPainter {
  final RoomTargetCurve targetCurve;
  final double maxCorrection;
  final bool cutOnly;
  final bool enabled;

  _RoomCorrectionCurvePainter({
    required this.targetCurve,
    required this.maxCorrection,
    required this.cutOnly,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawTargetCurve(canvas, size);
    _drawCorrectionLimits(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()..color = ReelForgeTheme.borderSubtle..strokeWidth = 1;

    // Frequency lines
    for (final freq in [100.0, 1000.0, 10000.0]) {
      final x = _freqToX(freq, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

      // Labels
      final textPainter = TextPainter(
        text: TextSpan(
          text: freq < 1000 ? '${freq.toInt()}Hz' : '${(freq / 1000).toInt()}kHz',
          style: TextStyle(color: ReelForgeTheme.textTertiary, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, size.height - 14));
    }

    // 0 dB line
    final centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paint..color = ReelForgeTheme.borderMedium);
  }

  void _drawTargetCurve(Canvas canvas, Size size) {
    if (!enabled) return;

    final path = Path();
    final centerY = size.height / 2;

    for (int i = 0; i <= size.width.toInt(); i++) {
      final x = i.toDouble();
      final freq = _xToFreq(x, size.width);
      final db = _getTargetCurveDb(freq);
      final y = centerY - (db / 24) * (size.height / 2);

      if (i == 0) {
        path.moveTo(x, y.clamp(0, size.height));
      } else {
        path.lineTo(x, y.clamp(0, size.height));
      }
    }

    final color = _getCurveColor();

    // Fill
    final fillPath = Path.from(path)
      ..lineTo(size.width, centerY)
      ..lineTo(0, centerY)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.1));

    // Stroke
    canvas.drawPath(path, Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);
  }

  double _getTargetCurveDb(double freq) {
    // Simplified target curve approximations
    return switch (targetCurve) {
      RoomTargetCurve.flat => 0.0,
      RoomTargetCurve.harman => _harmanCurve(freq),
      RoomTargetCurve.bAndK => _bkCurve(freq),
      RoomTargetCurve.bbc => _bbcCurve(freq),
      RoomTargetCurve.xCurve => _xCurve(freq),
      RoomTargetCurve.custom => 0.0,
    };
  }

  double _harmanCurve(double freq) {
    // Bass boost, slight treble roll-off
    if (freq < 120) return 3.0;
    if (freq < 200) return 2.0;
    if (freq > 8000) return -2.0;
    if (freq > 12000) return -4.0;
    return 0.0;
  }

  double _bkCurve(double freq) {
    // Slight low-end emphasis, high frequency roll-off
    if (freq < 100) return 2.0;
    if (freq > 6000) return -3.0;
    if (freq > 10000) return -5.0;
    return 0.0;
  }

  double _bbcCurve(double freq) {
    // BBC house curve - slight presence dip
    if (freq > 2000 && freq < 5000) return -2.0;
    if (freq > 8000) return -3.0;
    return 0.0;
  }

  double _xCurve(double freq) {
    // X-Curve for cinema - significant HF roll-off
    if (freq > 2000) {
      return -3.0 * ((freq / 2000).clamp(1.0, 10.0) - 1);
    }
    return 0.0;
  }

  void _drawCorrectionLimits(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final limitPaint = Paint()
      ..color = ReelForgeTheme.accentOrange.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Upper limit
    final upperY = centerY - (maxCorrection / 24) * (size.height / 2);
    canvas.drawLine(Offset(0, upperY), Offset(size.width, upperY), limitPaint);

    // Lower limit (only if not cut-only)
    if (!cutOnly) {
      final lowerY = centerY + (maxCorrection / 24) * (size.height / 2);
      canvas.drawLine(Offset(0, lowerY), Offset(size.width, lowerY), limitPaint);
    }
  }

  Color _getCurveColor() {
    return switch (targetCurve) {
      RoomTargetCurve.flat => ReelForgeTheme.accentCyan,
      RoomTargetCurve.harman => ReelForgeTheme.accentGreen,
      RoomTargetCurve.bAndK => ReelForgeTheme.accentOrange,
      RoomTargetCurve.bbc => ReelForgeTheme.accentYellow,
      RoomTargetCurve.xCurve => ReelForgeTheme.accentPink,
      RoomTargetCurve.custom => ReelForgeTheme.textTertiary,
    };
  }

  double _freqToX(double freq, double width) {
    const minLog = 1.301; // log10(20)
    const maxLog = 4.301; // log10(20000)
    final logFreq = freq.clamp(20.0, 20000.0).log10();
    return ((logFreq - minLog) / (maxLog - minLog)) * width;
  }

  double _xToFreq(double x, double width) {
    const minLog = 1.301;
    const maxLog = 4.301;
    return _pow10(minLog + (x / width) * (maxLog - minLog));
  }

  double _pow10(double x) => _exp(x * 2.302585092994046);

  double _exp(double x) {
    double sum = 1.0;
    double term = 1.0;
    for (int i = 1; i < 15; i++) {
      term *= x / i;
      sum += term;
    }
    return sum;
  }

  @override
  bool shouldRepaint(covariant _RoomCorrectionCurvePainter oldDelegate) {
    return targetCurve != oldDelegate.targetCurve ||
           maxCorrection != oldDelegate.maxCorrection ||
           cutOnly != oldDelegate.cutOnly ||
           enabled != oldDelegate.enabled;
  }
}

extension on double {
  double log10() => this > 0 ? (this.log() / 2.302585092994046) : 0;
  double log() {
    if (this <= 0) return 0;
    double x = this;
    int k = 0;
    while (x > 2) { x /= 2; k++; }
    while (x < 1) { x *= 2; k--; }
    x -= 1;
    // Taylor series for ln(1+x)
    double sum = 0;
    double term = x;
    for (int i = 1; i < 20; i++) {
      sum += term / i * (i % 2 == 1 ? 1 : -1);
      term *= x;
    }
    return sum + k * 0.693147180559945;
  }
}
