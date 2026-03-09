/// Granular Synth Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// #28: ReaGranular-style granular synthesis with 4 grain voices,
/// min/max size, per-grain pan/level, random variations, freeze mode.
///
/// Features:
/// - Global grain parameters (size, density, position, window shape)
/// - 4 grain voices with individual level/pan/pitch/delay
/// - Random variation controls (size, pan, pitch)
/// - Freeze mode toggle
/// - Preset management (save/load/factory)
library;

import 'package:flutter/material.dart';
import '../../../../services/granular_synth_service.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class GranularSynthPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const GranularSynthPanel({super.key, this.onAction});

  @override
  State<GranularSynthPanel> createState() => _GranularSynthPanelState();
}

class _GranularSynthPanelState extends State<GranularSynthPanel> {
  final _service = GranularSynthService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 240, child: _buildGrainParams()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        Expanded(flex: 2, child: _buildVoicesPanel()),
        const VerticalDivider(width: 1, color: FabFilterColors.border),
        SizedBox(width: 200, child: _buildPresetsPanel()),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // LEFT: Grain Parameters
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildGrainParams() {
    final c = _service.current;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with freeze + processing toggle
          Row(children: [
            FabSectionLabel('GRAIN ENGINE'),
            const Spacer(),
            _freezeButton(),
            const SizedBox(width: 4),
            _processToggle(),
          ]),
          const SizedBox(height: 8),

          // Grain size range
          FabSectionLabel('GRAIN SIZE'),
          const SizedBox(height: 4),
          _paramSlider('Min', c.grainSizeMinMs, 1, 500, 'ms',
            (v) => _service.setGrainSize(minMs: v)),
          _paramSlider('Max', c.grainSizeMaxMs, 1, 500, 'ms',
            (v) => _service.setGrainSize(maxMs: v)),
          const SizedBox(height: 6),

          // Density
          FabSectionLabel('DENSITY'),
          const SizedBox(height: 4),
          _paramSlider('Rate', c.density, 0.5, 100, 'g/s',
            (v) => _service.setDensity(v)),
          const SizedBox(height: 6),

          // Source position
          FabSectionLabel('SOURCE'),
          const SizedBox(height: 4),
          _paramSlider('Position', c.sourcePosition, 0, 1, '',
            (v) => _service.setSourcePosition(v)),
          _paramSlider('Jitter', c.positionJitter, 0, 1, '',
            (v) => _service.setPositionJitter(v)),
          const SizedBox(height: 6),

          // Window shape
          FabSectionLabel('WINDOW'),
          const SizedBox(height: 4),
          _windowShapeSelector(),
          const SizedBox(height: 6),

          // Variation
          FabSectionLabel('RANDOM'),
          const SizedBox(height: 4),
          _paramSlider('Size', c.sizeVariation, 0, 1, '',
            (v) => _service.setVariation(size: v)),
          _paramSlider('Pan', c.panVariation, 0, 1, '',
            (v) => _service.setVariation(pan: v)),
          _paramSlider('Pitch', c.pitchVariation, 0, 1, '',
            (v) => _service.setVariation(pitch: v)),
          const SizedBox(height: 6),

          // Global pitch + output
          FabSectionLabel('OUTPUT'),
          const SizedBox(height: 4),
          _paramSlider('Pitch', c.globalPitch, -24, 24, 'st',
            (v) => _service.setGlobalPitch(v)),
          _paramSlider('Level', c.outputLevel, 0, 2, '',
            (v) => _service.setOutputLevel(v)),
        ],
      ),
    );
  }

  Widget _paramSlider(String label, double value, double min, double max,
      String unit, ValueChanged<double> onChanged) {
    final displayVal = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(label, style: const TextStyle(
            fontSize: 10, color: FabFilterColors.textTertiary))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                activeTrackColor: FabFilterColors.cyan,
                inactiveTrackColor: FabFilterColors.bgMid,
                thumbColor: FabFilterColors.cyan,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(width: 44, child: Text('$displayVal$unit',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 9, color: FabFilterColors.textSecondary))),
        ],
      ),
    );
  }

  Widget _freezeButton() {
    final frozen = _service.current.frozen;
    return GestureDetector(
      onTap: () => _service.toggleFreeze(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: frozen ? FabFilterColors.cyan.withValues(alpha: 0.3) : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: frozen ? FabFilterColors.cyan : FabFilterColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.ac_unit, size: 10,
            color: frozen ? FabFilterColors.cyan : FabFilterColors.textTertiary),
          const SizedBox(width: 3),
          Text('FREEZE', style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w600,
            color: frozen ? FabFilterColors.cyan : FabFilterColors.textTertiary,
          )),
        ]),
      ),
    );
  }

  Widget _processToggle() {
    final active = _service.processing;
    return GestureDetector(
      onTap: () => _service.toggleProcessing(),
      child: Container(
        width: 16, height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? FabFilterColors.green.withValues(alpha: 0.3) : FabFilterColors.bgMid,
          border: Border.all(color: active ? FabFilterColors.green : FabFilterColors.border),
        ),
        child: active
            ? const Icon(Icons.check, size: 10, color: FabFilterColors.green)
            : null,
      ),
    );
  }

  Widget _windowShapeSelector() {
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: GrainWindowShape.values.map((shape) {
        final active = _service.current.windowShape == shape;
        return GestureDetector(
          onTap: () => _service.setWindowShape(shape),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: active ? FabFilterColors.orange.withValues(alpha: 0.2) : FabFilterColors.bgMid,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: active ? FabFilterColors.orange : FabFilterColors.border),
            ),
            child: Text(shape.label, style: TextStyle(
              fontSize: 9,
              color: active ? FabFilterColors.orange : FabFilterColors.textTertiary,
            )),
          ),
        );
      }).toList(),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTER: Voice Details
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildVoicesPanel() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FabSectionLabel('GRAIN VOICES (4)'),
          const SizedBox(height: 8),
          // Voice headers
          _voiceHeader(),
          const SizedBox(height: 4),
          // Voice rows
          for (int i = 0; i < 4; i++) ...[
            _buildVoiceRow(i),
            if (i < 3) const SizedBox(height: 2),
          ],
          const SizedBox(height: 12),

          // Visual representation
          FabSectionLabel('GRAIN VISUALIZATION'),
          const SizedBox(height: 8),
          Expanded(child: _buildGrainVisualization()),
        ],
      ),
    );
  }

  Widget _voiceHeader() {
    const style = TextStyle(fontSize: 9, color: FabFilterColors.textTertiary,
      fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        const SizedBox(width: 24), // active toggle
        const SizedBox(width: 30, child: Text('Voice', style: style)),
        const Expanded(flex: 2, child: Text('Level', style: style)),
        const Expanded(flex: 2, child: Text('Pan', style: style)),
        const Expanded(flex: 2, child: Text('Pitch', style: style)),
        const Expanded(flex: 2, child: Text('Delay', style: style)),
      ]),
    );
  }

  Widget _buildVoiceRow(int index) {
    final voice = _service.voices[index];
    final colors = [FabFilterColors.cyan, FabFilterColors.green,
      FabFilterColors.orange, FabFilterColors.red];
    final color = colors[index];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: voice.active ? color.withValues(alpha: 0.05) : Colors.transparent,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: voice.active ? color.withValues(alpha: 0.2) : FabFilterColors.border),
      ),
      child: Row(
        children: [
          // Active toggle
          GestureDetector(
            onTap: () => _service.toggleVoice(index),
            child: Container(
              width: 16, height: 16,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: voice.active ? color.withValues(alpha: 0.3) : FabFilterColors.bgMid,
                border: Border.all(color: voice.active ? color : FabFilterColors.border),
              ),
              child: Center(child: Text('${index + 1}', style: TextStyle(
                fontSize: 8, fontWeight: FontWeight.w600,
                color: voice.active ? color : FabFilterColors.textDisabled,
              ))),
            ),
          ),
          const SizedBox(width: 10),
          // Level
          Expanded(flex: 2, child: _voiceSlider(
            voice.level, 0, 1, color, voice.active,
            (v) => _service.setVoiceLevel(index, v),
          )),
          // Pan
          Expanded(flex: 2, child: _voiceSlider(
            voice.pan, -1, 1, color, voice.active,
            (v) => _service.setVoicePan(index, v),
          )),
          // Pitch
          Expanded(flex: 2, child: _voiceSlider(
            voice.pitchOffset, -24, 24, color, voice.active,
            (v) => _service.setVoicePitch(index, v),
          )),
          // Delay
          Expanded(flex: 2, child: _voiceSlider(
            voice.delayMs, 0, 500, color, voice.active,
            (v) => _service.setVoiceDelay(index, v),
          )),
        ],
      ),
    );
  }

  Widget _voiceSlider(double value, double min, double max, Color color,
      bool active, ValueChanged<double> onChanged) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
        activeTrackColor: active ? color : FabFilterColors.textDisabled,
        inactiveTrackColor: FabFilterColors.bgMid,
        thumbColor: active ? color : FabFilterColors.textDisabled,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: active ? onChanged : null,
      ),
    );
  }

  Widget _buildGrainVisualization() {
    final c = _service.current;
    return Container(
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.border),
      ),
      child: CustomPaint(
        painter: _GrainVisualizationPainter(
          sourcePosition: c.sourcePosition,
          positionJitter: c.positionJitter,
          grainSizeMin: c.grainSizeMinMs,
          grainSizeMax: c.grainSizeMaxMs,
          voices: c.voices,
          frozen: c.frozen,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // RIGHT: Presets
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildPresetsPanel() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            FabSectionLabel('PRESETS'),
            const Spacer(),
            _iconBtn(Icons.add, 'Save current as preset', () {
              _service.savePreset('Preset ${_service.presetCount + 1}');
            }),
            _iconBtn(Icons.auto_fix_high, 'Load factory presets', () {
              _service.loadFactoryPresets();
            }),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: _service.presets.isEmpty
                ? Center(child: Text(
                    'No presets saved.\n\nTap + to save current\nsettings as a preset.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: FabFilterColors.textTertiary),
                  ))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _service.presets.length,
                    itemBuilder: (_, i) {
                      final preset = _service.presets[i];
                      return _buildPresetItem(preset);
                    },
                  ),
          ),
          const SizedBox(height: 8),
          // Current preset info
          FabSectionLabel('CURRENT'),
          const SizedBox(height: 4),
          Text(_service.current.name, style: const TextStyle(
            fontSize: 11, color: FabFilterColors.textPrimary,
            fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            'Size: ${_service.current.grainSizeMinMs.toInt()}-${_service.current.grainSizeMaxMs.toInt()} ms\n'
            'Density: ${_service.current.density.toStringAsFixed(1)} g/s\n'
            'Window: ${_service.current.windowShape.label}\n'
            'Voices: ${_service.voices.where((v) => v.active).length}/4\n'
            'Freeze: ${_service.current.frozen ? "ON" : "OFF"}',
            style: const TextStyle(fontSize: 10, color: FabFilterColors.textTertiary, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetItem(GranularPreset preset) {
    return InkWell(
      onTap: () => _service.loadPreset(preset.id),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: FabFilterColors.bgMid,
        ),
        child: Row(children: [
          Expanded(child: Text(preset.name, style: const TextStyle(
            fontSize: 10, color: FabFilterColors.textPrimary),
            overflow: TextOverflow.ellipsis)),
          if (preset.frozen)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.ac_unit, size: 10, color: FabFilterColors.cyan),
            ),
          GestureDetector(
            onTap: () => _service.deletePreset(preset.id),
            child: Icon(Icons.close, size: 12, color: FabFilterColors.textDisabled),
          ),
        ]),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════════════

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return SizedBox(
      width: 24, height: 24,
      child: IconButton(
        icon: Icon(icon, size: 14),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: FabFilterColors.textSecondary,
        disabledColor: FabFilterColors.textDisabled,
        onPressed: onPressed,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// GRAIN VISUALIZATION PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _GrainVisualizationPainter extends CustomPainter {
  final double sourcePosition;
  final double positionJitter;
  final double grainSizeMin;
  final double grainSizeMax;
  final List<GrainVoice> voices;
  final bool frozen;

  _GrainVisualizationPainter({
    required this.sourcePosition,
    required this.positionJitter,
    required this.grainSizeMin,
    required this.grainSizeMax,
    required this.voices,
    required this.frozen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background waveform representation
    final wavePaint = Paint()
      ..color = FabFilterColors.textDisabled.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final wavePath = Path();
    for (double x = 0; x < w; x += 2) {
      final normalized = x / w;
      final amplitude = (h * 0.3) *
          (0.5 + 0.5 * (normalized * 3.14159 * 4).clamp(-1, 1));
      final y = h / 2 + amplitude * (x.toInt() % 4 < 2 ? 1 : -1) * 0.3;
      if (x == 0) {
        wavePath.moveTo(x, y);
      } else {
        wavePath.lineTo(x, y);
      }
    }
    canvas.drawPath(wavePath, wavePaint);

    // Source position indicator
    final posX = sourcePosition * w;
    final posPaint = Paint()
      ..color = frozen ? FabFilterColors.cyan : FabFilterColors.orange
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(posX, 0), Offset(posX, h), posPaint);

    // Jitter range
    final jitterPaint = Paint()
      ..color = (frozen ? FabFilterColors.cyan : FabFilterColors.orange)
          .withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    final jitterRange = positionJitter * w * 0.5;
    canvas.drawRect(
      Rect.fromLTRB(posX - jitterRange, 0, posX + jitterRange, h),
      jitterPaint,
    );

    // Grain markers for each active voice
    final colors = [FabFilterColors.cyan, FabFilterColors.green,
      FabFilterColors.orange, FabFilterColors.red];

    for (int i = 0; i < voices.length; i++) {
      final voice = voices[i];
      if (!voice.active) continue;

      final grainPaint = Paint()
        ..color = colors[i].withValues(alpha: 0.4)
        ..style = PaintingStyle.fill;

      // Draw a few representative grains
      for (int g = 0; g < 3; g++) {
        final grainX = posX + (g - 1) * jitterRange * 0.6;
        final grainW = (grainSizeMin + (grainSizeMax - grainSizeMin) * (g / 3)) * w / 1000;
        final yOffset = (i - 1.5) * (h * 0.15);

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(grainX, h / 2 + yOffset),
              width: grainW.clamp(4, w * 0.3),
              height: h * 0.1 * voice.level,
            ),
            const Radius.circular(2),
          ),
          grainPaint,
        );
      }
    }

    // Freeze overlay
    if (frozen) {
      final freezePaint = Paint()
        ..color = FabFilterColors.cyan.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), freezePaint);

      // Snowflake icon position
      final iconPaint = Paint()
        ..color = FabFilterColors.cyan.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(Offset(w - 16, 16), 8, iconPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GrainVisualizationPainter oldDelegate) {
    if (sourcePosition != oldDelegate.sourcePosition ||
        positionJitter != oldDelegate.positionJitter ||
        grainSizeMin != oldDelegate.grainSizeMin ||
        grainSizeMax != oldDelegate.grainSizeMax ||
        frozen != oldDelegate.frozen) {
      return true;
    }
    for (int i = 0; i < voices.length; i++) {
      if (voices[i].active != oldDelegate.voices[i].active ||
          voices[i].level != oldDelegate.voices[i].level) {
        return true;
      }
    }
    return false;
  }
}
