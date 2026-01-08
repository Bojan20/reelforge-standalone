/// ReelForge Professional Transient Shaper Panel
///
/// Modify attack and sustain characteristics independently.
/// Similar to SPL Transient Designer.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

/// Professional Transient Shaper Panel Widget
class TransientPanel extends StatefulWidget {
  /// Track ID to process
  final int trackId;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const TransientPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<TransientPanel> createState() => _TransientPanelState();
}

class _TransientPanelState extends State<TransientPanel> {
  // Parameters
  double _attack = 0.0;        // -100 to +100
  double _sustain = 0.0;       // -100 to +100
  double _attackSpeed = 15.0;  // ms
  double _sustainSpeed = 50.0; // ms
  double _outputGain = 0.0;    // dB
  double _mix = 1.0;           // 0-1

  // State
  bool _initialized = false;
  bool _bypassed = false;

  // Envelope for metering
  double _attackEnvelope = 0.0;
  double _sustainEnvelope = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeProcessor();
  }

  @override
  void dispose() {
    NativeFFI.instance.transientShaperRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessor() {
    final success = NativeFFI.instance.transientShaperCreate(
      widget.trackId,
      sampleRate: widget.sampleRate,
    );

    if (success) {
      setState(() => _initialized = true);
      _applyAllSettings();
    }
  }

  void _applyAllSettings() {
    if (!_initialized) return;

    NativeFFI.instance.transientShaperSetAttack(widget.trackId, _attack);
    NativeFFI.instance.transientShaperSetSustain(widget.trackId, _sustain);
    NativeFFI.instance.transientShaperSetAttackSpeed(widget.trackId, _attackSpeed);
    NativeFFI.instance.transientShaperSetSustainSpeed(widget.trackId, _sustainSpeed);
    NativeFFI.instance.transientShaperSetOutputGain(widget.trackId, _outputGain);
    NativeFFI.instance.transientShaperSetMix(widget.trackId, _mix);

    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          _buildMainControls(),
          const SizedBox(height: 16),
          _buildEnvelopeDisplay(),
          const SizedBox(height: 16),
          _buildSpeedControls(),
          const SizedBox(height: 16),
          _buildOutputControls(),
          const SizedBox(height: 16),
          _buildPresets(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.flash_on, color: ReelForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'Transient',
          style: TextStyle(
            color: ReelForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _bypassed = !_bypassed),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _bypassed
                  ? Colors.orange.withValues(alpha: 0.3)
                  : ReelForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _bypassed ? Colors.orange : ReelForgeTheme.border,
              ),
            ),
            child: Text(
              'BYPASS',
              style: TextStyle(
                color: _bypassed ? Colors.orange : ReelForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _initialized
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _initialized ? 'Ready' : 'Init...',
            style: TextStyle(
              color: _initialized ? Colors.green : Colors.red,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainControls() {
    return Row(
      children: [
        Expanded(child: _buildKnobControl(
          label: 'ATTACK',
          value: _attack,
          color: Colors.orange,
          onChanged: (v) {
            setState(() => _attack = v);
            NativeFFI.instance.transientShaperSetAttack(widget.trackId, v);
            widget.onSettingsChanged?.call();
          },
        )),
        const SizedBox(width: 32),
        Expanded(child: _buildKnobControl(
          label: 'SUSTAIN',
          value: _sustain,
          color: Colors.cyan,
          onChanged: (v) {
            setState(() => _sustain = v);
            NativeFFI.instance.transientShaperSetSustain(widget.trackId, v);
            widget.onSettingsChanged?.call();
          },
        )),
      ],
    );
  }

  Widget _buildKnobControl({
    required String label,
    required double value,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 100,
          height: 100,
          child: CustomPaint(
            painter: _KnobPainter(value: value, color: color),
            child: GestureDetector(
              onPanUpdate: (details) {
                final delta = -details.delta.dy * 0.5;
                final newValue = (value + delta).clamp(-100.0, 100.0);
                onChanged(newValue);
              },
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${value >= 0 ? "+" : ""}${value.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      value > 0 ? 'Boost' : (value < 0 ? 'Cut' : ''),
                      style: TextStyle(
                        color: ReelForgeTheme.textSecondary,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnvelopeDisplay() {
    return Container(
      height: 60,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Attack', style: TextStyle(color: Colors.orange, fontSize: 10)),
                    Text('${(_attackEnvelope * 100).toStringAsFixed(0)}%',
                        style: TextStyle(color: Colors.orange, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: _attackEnvelope.clamp(0.0, 1.0),
                      backgroundColor: ReelForgeTheme.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sustain', style: TextStyle(color: Colors.cyan, fontSize: 10)),
                    Text('${(_sustainEnvelope * 100).toStringAsFixed(0)}%',
                        style: TextStyle(color: Colors.cyan, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: _sustainEnvelope.clamp(0.0, 1.0),
                      backgroundColor: ReelForgeTheme.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.cyan),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedControls() {
    return Column(
      children: [
        _buildParameterRow(
          label: 'Attack Speed',
          value: '${_attackSpeed.toStringAsFixed(1)} ms',
          child: _buildSlider(
            value: _attackSpeed / 200,
            color: Colors.orange,
            onChanged: (v) {
              setState(() => _attackSpeed = v * 200);
              NativeFFI.instance.transientShaperSetAttackSpeed(widget.trackId, _attackSpeed);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),
        _buildParameterRow(
          label: 'Sustain Speed',
          value: '${_sustainSpeed.toStringAsFixed(0)} ms',
          child: _buildSlider(
            value: _sustainSpeed / 500,
            color: Colors.cyan,
            onChanged: (v) {
              setState(() => _sustainSpeed = v * 500);
              NativeFFI.instance.transientShaperSetSustainSpeed(widget.trackId, _sustainSpeed);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOutputControls() {
    return Column(
      children: [
        _buildParameterRow(
          label: 'Output',
          value: '${_outputGain >= 0 ? "+" : ""}${_outputGain.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_outputGain + 24) / 48,
            onChanged: (v) {
              setState(() => _outputGain = v * 48 - 24);
              NativeFFI.instance.transientShaperSetOutputGain(widget.trackId, _outputGain);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),
        _buildParameterRow(
          label: 'Mix',
          value: '${(_mix * 100).toStringAsFixed(0)}%',
          child: _buildSlider(
            value: _mix,
            onChanged: (v) {
              setState(() => _mix = v);
              NativeFFI.instance.transientShaperSetMix(widget.trackId, _mix);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPresets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Presets',
          style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPresetButton('Punch', attack: 50, sustain: 0),
            _buildPresetButton('Snap', attack: 80, sustain: -30),
            _buildPresetButton('Smooth', attack: -40, sustain: 20),
            _buildPresetButton('Drums', attack: 60, sustain: -20),
            _buildPresetButton('Sustain', attack: 0, sustain: 60),
            _buildPresetButton('Tame', attack: -50, sustain: 0),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetButton(String label, {required double attack, required double sustain}) {
    final isActive = (_attack - attack).abs() < 1 && (_sustain - sustain).abs() < 1;
    return GestureDetector(
      onTap: () {
        setState(() {
          _attack = attack;
          _sustain = sustain;
        });
        NativeFFI.instance.transientShaperSetAttack(widget.trackId, attack);
        NativeFFI.instance.transientShaperSetSustain(widget.trackId, sustain);
        widget.onSettingsChanged?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
              : ReelForgeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildParameterRow({
    required String label,
    required String value,
    required Widget child,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(child: child),
        SizedBox(
          width: 60,
          child: Text(
            value,
            style: TextStyle(
              color: ReelForgeTheme.accentBlue,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required double value,
    required ValueChanged<double> onChanged,
    Color? color,
    double min = 0.0,
    double max = 1.0,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: color ?? ReelForgeTheme.accentBlue,
        inactiveTrackColor: ReelForgeTheme.surface,
        thumbColor: color ?? ReelForgeTheme.accentBlue,
        overlayColor: (color ?? ReelForgeTheme.accentBlue).withValues(alpha: 0.2),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}

// =============================================================================
// KNOB PAINTER
// =============================================================================

class _KnobPainter extends CustomPainter {
  final double value; // -100 to +100
  final Color color;

  _KnobPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    // Background arc
    final bgPaint = Paint()
      ..color = ReelForgeTheme.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    const startAngle = 135 * math.pi / 180;
    const sweepAngle = 270 * math.pi / 180;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Calculate sweep from center (0 is at top, -100 is left, +100 is right)
    final normalizedValue = value / 100; // -1 to +1
    final centerAngle = 270 * math.pi / 180;
    final valueSweep = normalizedValue * 135 * math.pi / 180;

    if (value >= 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        centerAngle,
        valueSweep,
        false,
        valuePaint,
      );
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        centerAngle + valueSweep,
        -valueSweep,
        false,
        valuePaint,
      );
    }

    // Center marker
    final centerMarkerPaint = Paint()
      ..color = ReelForgeTheme.textSecondary
      ..strokeWidth = 2;

    final markerStart = Offset(
      center.dx + (radius - 12) * math.cos(centerAngle),
      center.dy + (radius - 12) * math.sin(centerAngle),
    );
    final markerEnd = Offset(
      center.dx + (radius + 4) * math.cos(centerAngle),
      center.dy + (radius + 4) * math.sin(centerAngle),
    );
    canvas.drawLine(markerStart, markerEnd, centerMarkerPaint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}
