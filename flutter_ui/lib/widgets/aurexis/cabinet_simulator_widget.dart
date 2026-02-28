import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/aurexis_cabinet.dart';
import 'aurexis_theme.dart';

/// Cabinet Simulator widget — monitoring-only speaker & ambient preview.
///
/// Shows speaker profile selection, frequency response curve,
/// ambient noise control, and simulation status.
/// Does NOT process audio — purely informational for authoring.
class CabinetSimulatorWidget extends StatefulWidget {
  final CabinetSimulatorState state;
  final ValueChanged<CabinetSimulatorState> onStateChanged;
  final double height;

  const CabinetSimulatorWidget({
    super.key,
    required this.state,
    required this.onStateChanged,
    this.height = 240,
  });

  @override
  State<CabinetSimulatorWidget> createState() => _CabinetSimulatorWidgetState();
}

class _CabinetSimulatorWidgetState extends State<CabinetSimulatorWidget> {
  void _updateState(CabinetSimulatorState Function(CabinetSimulatorState) updater) {
    widget.onStateChanged(updater(widget.state));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final response = state.effectiveResponse;

    return SizedBox(
      height: widget.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with enable toggle
          _buildHeader(state),
          const SizedBox(height: 4),
          // Speaker profile dropdown
          _buildSpeakerSelector(state),
          const SizedBox(height: 4),
          // Speaker info row
          _buildSpeakerInfo(response),
          const SizedBox(height: 4),
          // Frequency response display
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CustomPaint(
                painter: _FrequencyResponsePainter(
                  response: response,
                  enabled: state.enabled,
                ),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Ambient noise control
          _buildAmbientControl(state),
        ],
      ),
    );
  }

  Widget _buildHeader(CabinetSimulatorState state) {
    return Row(
      children: [
        Text(
          'CABINET SIM',
          style: AurexisTextStyles.sectionTitle.copyWith(fontSize: 8),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: AurexisColors.bgInput,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            'MONITOR',
            style: AurexisTextStyles.badge.copyWith(
              color: AurexisColors.textLabel,
              fontSize: 6,
            ),
          ),
        ),
        const Spacer(),
        // Enable toggle
        GestureDetector(
          onTap: () => _updateState((s) => s.copyWith(enabled: !s.enabled)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: state.enabled
                  ? AurexisColors.accent.withValues(alpha: 0.15)
                  : Colors.transparent,
              border: Border.all(
                color: state.enabled ? AurexisColors.accent : AurexisColors.borderSubtle,
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              state.enabled ? 'ON' : 'OFF',
              style: AurexisTextStyles.badge.copyWith(
                color: state.enabled ? AurexisColors.accent : AurexisColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeakerSelector(CabinetSimulatorState state) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AurexisColors.bgInput,
        borderRadius: BorderRadius.circular(AurexisDimens.borderRadius),
        border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<CabinetSpeakerProfile>(
          value: state.speakerProfile,
          isExpanded: true,
          isDense: true,
          dropdownColor: AurexisColors.bgSection,
          style: AurexisTextStyles.paramLabel.copyWith(fontSize: 9),
          icon: const Icon(Icons.unfold_more, size: 12, color: AurexisColors.textSecondary),
          items: CabinetSpeakerProfile.values.map((p) {
            return DropdownMenuItem(
              value: p,
              child: Text(
                p.label,
                style: AurexisTextStyles.paramLabel.copyWith(fontSize: 9),
              ),
            );
          }).toList(),
          onChanged: (p) {
            if (p != null) {
              _updateState((s) => s.copyWith(speakerProfile: p));
            }
          },
        ),
      ),
    );
  }

  Widget _buildSpeakerInfo(CabinetSpeakerResponse response) {
    return Row(
      children: [
        // Speaker config
        Text(
          response.profile.speakerConfig,
          style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel),
        ),
        const Spacer(),
        // Frequency range
        Text(
          '${response.lowCutHz.toStringAsFixed(0)}-${response.highCutHz.toStringAsFixed(0)} Hz',
          style: AurexisTextStyles.badge.copyWith(color: AurexisColors.spatial),
        ),
        const SizedBox(width: 6),
        // Stereo indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: response.stereoWidth > 0
                ? AurexisColors.spatial.withValues(alpha: 0.15)
                : AurexisColors.dynamics.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            response.stereoWidth > 0 ? 'STEREO' : 'MONO',
            style: AurexisTextStyles.badge.copyWith(
              color: response.stereoWidth > 0 ? AurexisColors.spatial : AurexisColors.dynamics,
              fontSize: 6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAmbientControl(CabinetSimulatorState state) {
    return Row(
      children: [
        // Ambient preset dropdown
        Text('Ambient:', style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel)),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AurexisColors.bgInput,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CabinetAmbientPreset>(
                value: state.ambient.preset,
                isExpanded: true,
                isDense: true,
                dropdownColor: AurexisColors.bgSection,
                style: AurexisTextStyles.badge.copyWith(fontSize: 8),
                icon: const Icon(Icons.unfold_more, size: 10, color: AurexisColors.textSecondary),
                items: CabinetAmbientPreset.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(
                      p.label,
                      style: AurexisTextStyles.badge.copyWith(fontSize: 8),
                    ),
                  );
                }).toList(),
                onChanged: (p) {
                  if (p != null) {
                    _updateState((s) => s.copyWith(
                          ambient: s.ambient.copyWith(preset: p),
                        ));
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // SPL indicator
        if (state.ambient.preset != CabinetAmbientPreset.silent &&
            state.ambient.preset != CabinetAmbientPreset.custom)
          Text(
            '~${state.ambient.preset.splDb.toStringAsFixed(0)} dB',
            style: AurexisTextStyles.badge.copyWith(
              color: state.ambient.preset.splDb > 70
                  ? AurexisColors.fatigueHigh
                  : AurexisColors.textSecondary,
            ),
          ),
        // Custom level slider
        if (state.ambient.preset == CabinetAmbientPreset.custom)
          SizedBox(
            width: 60,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                activeTrackColor: AurexisColors.accent,
                inactiveTrackColor: AurexisColors.bgSlider,
                thumbColor: AurexisColors.accent,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: state.ambient.customLevel,
                onChanged: (v) {
                  _updateState((s) => s.copyWith(
                        ambient: s.ambient.copyWith(customLevel: v),
                      ));
                },
              ),
            ),
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FREQUENCY RESPONSE PAINTER
// ═════════════════════════════════════════════════════════════════════════════

class _FrequencyResponsePainter extends CustomPainter {
  final CabinetSpeakerResponse response;
  final bool enabled;

  _FrequencyResponsePainter({
    required this.response,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = AurexisColors.bgInput,
    );

    // Frequency grid lines (log scale: 20Hz - 20kHz)
    _drawGrid(canvas, size);

    // Compute and draw frequency response curve
    _drawResponseCurve(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AurexisColors.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    final labelStyle = AurexisTextStyles.badge.copyWith(
      color: AurexisColors.textLabel.withValues(alpha: 0.4),
      fontSize: 6,
    );

    // Frequency lines (log scale)
    final frequencies = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
    final labels = ['20', '50', '100', '200', '500', '1k', '2k', '5k', '10k', '20k'];

    for (int i = 0; i < frequencies.length; i++) {
      final x = _freqToX(frequencies[i].toDouble(), size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);

      // Label every other
      if (i % 2 == 0 || i == frequencies.length - 1) {
        _drawText(canvas, labels[i], Offset(x - 6, size.height - 10), labelStyle);
      }
    }

    // dB lines
    final dbValues = [-12.0, -6.0, 0.0, 6.0, 12.0];
    for (final db in dbValues) {
      final y = _dbToY(db, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      if (db == 0) {
        // 0 dB reference line slightly brighter
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = AurexisColors.borderSubtle.withValues(alpha: 0.6)
            ..strokeWidth = 0.5,
        );
      }
    }
  }

  void _drawResponseCurve(Canvas canvas, Size size) {
    final path = Path();
    const steps = 256;
    final minFreq = 20.0;
    final maxFreq = 20000.0;

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final freq = minFreq * math.pow(maxFreq / minFreq, t);
      final db = _computeResponseAtFreq(freq);
      final x = t * size.width;
      final y = _dbToY(db, size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Stroke
    final curveColor = enabled ? AurexisColors.accent : AurexisColors.textSecondary;
    final strokePaint = Paint()
      ..color = curveColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, strokePaint);

    // Fill under curve (relative to 0 dB line)
    final zeroY = _dbToY(0, size.height);
    final fillPath = Path.from(path)
      ..lineTo(size.width, zeroY)
      ..lineTo(0, zeroY)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          curveColor.withValues(alpha: 0.15),
          curveColor.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    // Low/high cut markers
    final lowX = _freqToX(response.lowCutHz, size.width);
    final highX = _freqToX(response.highCutHz, size.width);
    final cutPaint = Paint()
      ..color = AurexisColors.dynamics.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(lowX, 0), Offset(lowX, size.height), cutPaint);
    canvas.drawLine(Offset(highX, 0), Offset(highX, size.height), cutPaint);

    // Shaded out-of-range areas
    final shadePaint = Paint()..color = AurexisColors.bgPanel.withValues(alpha: 0.5);
    canvas.drawRect(Rect.fromLTWH(0, 0, lowX, size.height), shadePaint);
    canvas.drawRect(Rect.fromLTWH(highX, 0, size.width - highX, size.height), shadePaint);
  }

  /// Compute the combined frequency response of all EQ bands at a given frequency.
  double _computeResponseAtFreq(double freq) {
    double totalDb = 0.0;

    for (final band in response.bands) {
      totalDb += _bandResponseAt(freq, band);
    }

    // Add resonance if present
    if (response.resonanceHz > 0 && response.resonanceGainDb != 0) {
      totalDb += _bandResponseAt(
        freq,
        CabinetEqBand(
          frequencyHz: response.resonanceHz,
          gainDb: response.resonanceGainDb,
          q: response.resonanceQ,
        ),
      );
    }

    return totalDb.clamp(-24.0, 12.0);
  }

  /// Approximate biquad filter magnitude response at a given frequency.
  double _bandResponseAt(double freq, CabinetEqBand band) {
    final ratio = freq / band.frequencyHz;

    switch (band.type) {
      case CabinetBandType.highPass:
        if (freq < band.frequencyHz) {
          final attenuation = 20 * math.log(ratio) / math.ln10;
          return (band.gainDb + attenuation * 2).clamp(-24.0, 0.0);
        }
        return 0;

      case CabinetBandType.lowPass:
        if (freq > band.frequencyHz) {
          final attenuation = 20 * math.log(1 / ratio) / math.ln10;
          return (band.gainDb + attenuation * 2).clamp(-24.0, 0.0);
        }
        return 0;

      case CabinetBandType.highShelf:
        if (freq > band.frequencyHz) {
          final transitionWidth = 1.0 / band.q;
          final blend = ((math.log(ratio) / math.ln10) / transitionWidth).clamp(0.0, 1.0);
          return band.gainDb * blend;
        }
        return 0;

      case CabinetBandType.lowShelf:
        if (freq < band.frequencyHz) {
          final transitionWidth = 1.0 / band.q;
          final blend = ((math.log(1 / ratio) / math.ln10) / transitionWidth).clamp(0.0, 1.0);
          return band.gainDb * blend;
        }
        return 0;

      case CabinetBandType.peaking:
        // Bell curve approximation
        final logRatio = math.log(ratio) / math.ln10;
        final bandwidth = 1.0 / band.q;
        final gaussian = math.exp(-(logRatio * logRatio) / (2.0 * bandwidth * bandwidth));
        return band.gainDb * gaussian;
    }
  }

  double _freqToX(double freq, double width) {
    const minFreq = 20.0;
    const maxFreq = 20000.0;
    final t = math.log(freq / minFreq) / math.log(maxFreq / minFreq);
    return t.clamp(0.0, 1.0) * width;
  }

  double _dbToY(double db, double height) {
    // Range: -24 dB to +12 dB, centered at 0
    const minDb = -24.0;
    const maxDb = 12.0;
    final normalized = (db - minDb) / (maxDb - minDb);
    return height * (1.0 - normalized.clamp(0.0, 1.0));
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_FrequencyResponsePainter old) =>
      old.response.profile != response.profile ||
      old.enabled != enabled;
}
