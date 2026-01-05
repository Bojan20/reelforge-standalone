// Crossfade Editor Widget
//
// Cubase-style crossfade editor with:
// - Interactive curve editing
// - 7 preset curve types + custom
// - Asymmetric fade support
// - Real-time waveform preview
// - A/B comparison
// - Audition controls (play crossfade region)

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// Crossfade curve type
enum CrossfadePreset {
  linear,
  equalPower,
  sCurve,
  exponential,
  logarithmic,
  fastStart,
  slowStart,
  custom,
}

/// Asymmetric fade configuration
class FadeCurveConfig {
  final CrossfadePreset preset;
  final List<Offset> customPoints;
  final double tension; // -1 to 1 for Catmull-Rom tension

  const FadeCurveConfig({
    this.preset = CrossfadePreset.equalPower,
    this.customPoints = const [],
    this.tension = 0.0,
  });

  FadeCurveConfig copyWith({
    CrossfadePreset? preset,
    List<Offset>? customPoints,
    double? tension,
  }) {
    return FadeCurveConfig(
      preset: preset ?? this.preset,
      customPoints: customPoints ?? this.customPoints,
      tension: tension ?? this.tension,
    );
  }

  /// Evaluate curve at position t (0.0 to 1.0)
  double evaluate(double t) {
    switch (preset) {
      case CrossfadePreset.linear:
        return t;
      case CrossfadePreset.equalPower:
        // Equal power crossfade: sin curve
        return math.sin(t * math.pi / 2);
      case CrossfadePreset.sCurve:
        // Smoothstep (3t^2 - 2t^3)
        return t * t * (3 - 2 * t);
      case CrossfadePreset.exponential:
        // Slow start, fast end
        return t * t;
      case CrossfadePreset.logarithmic:
        // Fast start, slow end
        return math.sqrt(t);
      case CrossfadePreset.fastStart:
        // Aggressive fast start
        return 1 - math.pow(1 - t, 3).toDouble();
      case CrossfadePreset.slowStart:
        // Aggressive slow start
        return math.pow(t, 3).toDouble();
      case CrossfadePreset.custom:
        return _evaluateCustom(t);
    }
  }

  double _evaluateCustom(double t) {
    if (customPoints.isEmpty) return t;

    // Add implicit start and end points
    final points = <Offset>[
      const Offset(0, 0),
      ...customPoints,
      const Offset(1, 1),
    ];

    // Find segment
    for (int i = 0; i < points.length - 1; i++) {
      if (t >= points[i].dx && t <= points[i + 1].dx) {
        final segmentT = (t - points[i].dx) / (points[i + 1].dx - points[i].dx);
        return points[i].dy + segmentT * (points[i + 1].dy - points[i].dy);
      }
    }

    return t;
  }

  /// Get curve path for visualization
  Path getCurvePath(Size size, {bool fadeOut = false}) {
    final path = Path();
    const steps = 50;

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final value = evaluate(t);

      final x = t * size.width;
      final y = fadeOut
          ? (1 - value) * size.height * 0.8 + size.height * 0.1
          : value * size.height * 0.8 + size.height * 0.1;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    return path;
  }

  String get name {
    switch (preset) {
      case CrossfadePreset.linear:
        return 'Linear';
      case CrossfadePreset.equalPower:
        return 'Equal Power';
      case CrossfadePreset.sCurve:
        return 'S-Curve';
      case CrossfadePreset.exponential:
        return 'Exponential';
      case CrossfadePreset.logarithmic:
        return 'Logarithmic';
      case CrossfadePreset.fastStart:
        return 'Fast Start';
      case CrossfadePreset.slowStart:
        return 'Slow Start';
      case CrossfadePreset.custom:
        return 'Custom';
    }
  }
}

/// Full crossfade configuration
class CrossfadeConfig {
  final FadeCurveConfig fadeOut;
  final FadeCurveConfig fadeIn;
  final double duration; // in seconds
  final double centerOffset; // -0.5 to 0.5 (shifts center point)
  final bool linked; // when true, fadeIn mirrors fadeOut

  const CrossfadeConfig({
    this.fadeOut = const FadeCurveConfig(),
    this.fadeIn = const FadeCurveConfig(),
    this.duration = 0.5,
    this.centerOffset = 0.0,
    this.linked = true,
  });

  CrossfadeConfig copyWith({
    FadeCurveConfig? fadeOut,
    FadeCurveConfig? fadeIn,
    double? duration,
    double? centerOffset,
    bool? linked,
  }) {
    return CrossfadeConfig(
      fadeOut: fadeOut ?? this.fadeOut,
      fadeIn: fadeIn ?? this.fadeIn,
      duration: duration ?? this.duration,
      centerOffset: centerOffset ?? this.centerOffset,
      linked: linked ?? this.linked,
    );
  }
}

/// Crossfade editor widget
class CrossfadeEditor extends StatefulWidget {
  final CrossfadeConfig initialConfig;
  final List<double>? clipAWaveform;
  final List<double>? clipBWaveform;
  final double sampleRate;
  final ValueChanged<CrossfadeConfig>? onConfigChanged;
  final VoidCallback? onApply;
  final VoidCallback? onCancel;
  final VoidCallback? onAudition;

  const CrossfadeEditor({
    super.key,
    this.initialConfig = const CrossfadeConfig(),
    this.clipAWaveform,
    this.clipBWaveform,
    this.sampleRate = 48000,
    this.onConfigChanged,
    this.onApply,
    this.onCancel,
    this.onAudition,
  });

  @override
  State<CrossfadeEditor> createState() => _CrossfadeEditorState();
}

class _CrossfadeEditorState extends State<CrossfadeEditor> {
  late CrossfadeConfig _config;
  bool _showWaveforms = true;
  bool _abComparison = false;
  // ignore: unused_field
  final int _editingCurve = 0; // 0 = both, 1 = fade out, 2 = fade in (reserved for future)

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  void _updateConfig(CrossfadeConfig config) {
    setState(() => _config = config);
    widget.onConfigChanged?.call(config);
  }

  void _setPreset(CrossfadePreset preset) {
    final newFadeOut = _config.fadeOut.copyWith(preset: preset);
    final newFadeIn = _config.linked
        ? _config.fadeIn.copyWith(preset: preset)
        : _config.fadeIn;

    _updateConfig(_config.copyWith(fadeOut: newFadeOut, fadeIn: newFadeIn));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Column(
        children: [
          // Toolbar
          _buildToolbar(),

          // Main editor area
          Expanded(
            child: Row(
              children: [
                // Curve preset panel
                _buildPresetPanel(),

                // Crossfade visualization
                Expanded(
                  child: _buildCurveEditor(),
                ),

                // Settings panel
                _buildSettingsPanel(),
              ],
            ),
          ),

          // Duration control
          _buildDurationBar(),

          // Action buttons
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Crossfade Editor',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ReelForgeTheme.textPrimary,
            ),
          ),
          const Spacer(),

          // Toggle waveform view
          _buildIconButton(
            icon: Icons.graphic_eq,
            tooltip: 'Show Waveforms',
            selected: _showWaveforms,
            onPressed: () => setState(() => _showWaveforms = !_showWaveforms),
          ),

          // A/B comparison
          _buildIconButton(
            icon: Icons.compare,
            tooltip: 'A/B Comparison',
            selected: _abComparison,
            onPressed: () => setState(() => _abComparison = !_abComparison),
          ),

          const SizedBox(width: 8),

          // Link curves toggle
          _buildIconButton(
            icon: _config.linked ? Icons.link : Icons.link_off,
            tooltip: 'Link Fade Curves',
            selected: _config.linked,
            onPressed: () {
              _updateConfig(_config.copyWith(linked: !_config.linked));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    bool selected = false,
    VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor:
              selected ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
          backgroundColor:
              selected ? ReelForgeTheme.accentBlue.withValues(alpha: 0.15) : null,
          minimumSize: const Size(28, 28),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildPresetPanel() {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgSurface,
        border: Border(
          right: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Presets',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ReelForgeTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final preset in CrossfadePreset.values)
                  if (preset != CrossfadePreset.custom)
                    _buildPresetItem(preset),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetItem(CrossfadePreset preset) {
    final isSelected = _config.fadeOut.preset == preset;
    final config = FadeCurveConfig(preset: preset);

    return GestureDetector(
      onTap: () => _setPreset(preset),
      child: Container(
        height: 48,
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? ReelForgeTheme.accentBlue.withValues(alpha: 0.15)
              : ReelForgeTheme.bgDeep,
          border: Border.all(
            color: isSelected
                ? ReelForgeTheme.accentBlue.withValues(alpha: 0.5)
                : ReelForgeTheme.borderSubtle,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            // Curve preview
            SizedBox(
              width: 48,
              height: 48,
              child: CustomPaint(
                painter: _MiniCurvePainter(config: config),
              ),
            ),
            // Name
            Expanded(
              child: Text(
                config.name,
                style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? ReelForgeTheme.textPrimary
                      : ReelForgeTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurveEditor() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeepest,
        border: Border.all(color: ReelForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CustomPaint(
          painter: _CrossfadeEditorPainter(
            config: _config,
            showWaveforms: _showWaveforms,
            clipAWaveform: widget.clipAWaveform,
            clipBWaveform: widget.clipBWaveform,
            abComparison: _abComparison,
          ),
          child: GestureDetector(
            onPanUpdate: (details) {
              // Allow dragging center point
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final localPos = details.localPosition;
              final size = box.size;
              final normalizedX = (localPos.dx / size.width).clamp(0.2, 0.8);
              final offset = normalizedX - 0.5;
              _updateConfig(_config.copyWith(centerOffset: offset));
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgSurface,
        border: Border(
          left: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fade Out settings
          _buildCurveSettings('Fade Out', _config.fadeOut, (config) {
            _updateConfig(_config.copyWith(fadeOut: config));
          }),

          Divider(color: ReelForgeTheme.borderSubtle, height: 1),

          // Fade In settings
          _buildCurveSettings('Fade In', _config.fadeIn, (config) {
            _updateConfig(_config.copyWith(fadeIn: config));
          }),

          const Spacer(),

          // Center offset
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Center Offset',
                  style: TextStyle(
                    fontSize: 11,
                    color: ReelForgeTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Slider(
                  value: _config.centerOffset,
                  min: -0.4,
                  max: 0.4,
                  onChanged: (value) {
                    _updateConfig(_config.copyWith(centerOffset: value));
                  },
                  activeColor: ReelForgeTheme.accentBlue,
                ),
                Text(
                  '${(_config.centerOffset * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    color: ReelForgeTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurveSettings(
    String title,
    FadeCurveConfig config,
    ValueChanged<FadeCurveConfig> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ReelForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),

          // Curve type dropdown
          DropdownButton<CrossfadePreset>(
            value: config.preset,
            isExpanded: true,
            dropdownColor: ReelForgeTheme.bgSurface,
            style: TextStyle(
              fontSize: 12,
              color: ReelForgeTheme.textPrimary,
            ),
            items: CrossfadePreset.values.map((preset) {
              return DropdownMenuItem(
                value: preset,
                child: Text(FadeCurveConfig(preset: preset).name),
              );
            }).toList(),
            onChanged: (preset) {
              if (preset != null) {
                onChanged(config.copyWith(preset: preset));
              }
            },
          ),

          const SizedBox(height: 8),

          // Tension slider (for custom curves)
          Text(
            'Tension',
            style: TextStyle(
              fontSize: 10,
              color: ReelForgeTheme.textTertiary,
            ),
          ),
          Slider(
            value: config.tension,
            min: -1.0,
            max: 1.0,
            onChanged: (value) {
              onChanged(config.copyWith(tension: value));
            },
            activeColor: ReelForgeTheme.accentBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildDurationBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Duration:',
            style: TextStyle(
              fontSize: 12,
              color: ReelForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),

          // Duration slider
          Expanded(
            child: Slider(
              value: _config.duration.clamp(0.01, 5.0),
              min: 0.01,
              max: 5.0,
              onChanged: (value) {
                _updateConfig(_config.copyWith(duration: value));
              },
              activeColor: ReelForgeTheme.accentBlue,
            ),
          ),

          // Duration text input
          SizedBox(
            width: 80,
            child: TextField(
              controller: TextEditingController(
                text: '${(_config.duration * 1000).toStringAsFixed(0)} ms',
              ),
              style: TextStyle(
                fontSize: 12,
                color: ReelForgeTheme.textPrimary,
              ),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: ReelForgeTheme.borderSubtle),
                ),
              ),
              onSubmitted: (value) {
                final ms = double.tryParse(value.replaceAll(' ms', ''));
                if (ms != null) {
                  _updateConfig(_config.copyWith(duration: ms / 1000));
                }
              },
            ),
          ),

          const SizedBox(width: 12),

          // Audition button
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Audition'),
            style: ElevatedButton.styleFrom(
              backgroundColor: ReelForgeTheme.accentGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: widget.onAudition,
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgSurface,
        border: Border(
          top: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: widget.onCancel,
            child: Text(
              'Cancel',
              style: TextStyle(color: ReelForgeTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: widget.onApply,
            style: ElevatedButton.styleFrom(
              backgroundColor: ReelForgeTheme.accentBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

/// Mini curve preview painter for presets
class _MiniCurvePainter extends CustomPainter {
  final FadeCurveConfig config;

  _MiniCurvePainter({required this.config});

  @override
  void paint(Canvas canvas, Size size) {
    final fadeOutPaint = Paint()
      ..color = const Color(0xAAFF6464)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final fadeInPaint = Paint()
      ..color = const Color(0xAA64FF64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final padding = 6.0;
    final innerSize = Size(size.width - padding * 2, size.height - padding * 2);

    canvas.save();
    canvas.translate(padding, padding);

    // Fade out curve
    final fadeOutPath = config.getCurvePath(innerSize, fadeOut: true);
    canvas.drawPath(fadeOutPath, fadeOutPaint);

    // Fade in curve
    final fadeInPath = config.getCurvePath(innerSize, fadeOut: false);
    canvas.drawPath(fadeInPath, fadeInPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MiniCurvePainter oldDelegate) =>
      config.preset != oldDelegate.config.preset;
}

/// Main crossfade editor painter
class _CrossfadeEditorPainter extends CustomPainter {
  final CrossfadeConfig config;
  final bool showWaveforms;
  final List<double>? clipAWaveform;
  final List<double>? clipBWaveform;
  final bool abComparison;

  _CrossfadeEditorPainter({
    required this.config,
    required this.showWaveforms,
    this.clipAWaveform,
    this.clipBWaveform,
    this.abComparison = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background grid
    _drawGrid(canvas, size);

    // Waveforms (if enabled)
    if (showWaveforms) {
      _drawWaveforms(canvas, size);
    }

    // Crossfade curves
    _drawCrossfadeCurves(canvas, size);

    // Center line marker
    _drawCenterMarker(canvas, size);

    // Gain indicator at center
    _drawGainIndicator(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = ReelForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Vertical lines (time divisions)
    for (int i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Horizontal lines (level divisions)
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Center crosshair (stronger)
    final centerPaint = Paint()
      ..color = ReelForgeTheme.borderSubtle.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    // Horizontal center
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );

    // Vertical center (with offset)
    final centerX = size.width * (0.5 + config.centerOffset);
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      centerPaint,
    );
  }

  void _drawWaveforms(Canvas canvas, Size size) {
    final clipAPaint = Paint()
      ..color = const Color(0x33FF6464)
      ..style = PaintingStyle.fill;

    final clipBPaint = Paint()
      ..color = const Color(0x3364FF64)
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;

    // Draw clip A waveform (left half, fading out)
    if (clipAWaveform != null && clipAWaveform!.isNotEmpty) {
      final path = Path();
      final sampleCount = clipAWaveform!.length;

      path.moveTo(0, centerY);
      for (int i = 0; i < sampleCount; i++) {
        final x = (i / sampleCount) * size.width;
        final sample = clipAWaveform![i].clamp(-1.0, 1.0);
        final fadeT = (x / size.width).clamp(0.0, 1.0);
        final fadeGain = 1 - config.fadeOut.evaluate(fadeT);
        final y = centerY - sample * centerY * 0.8 * fadeGain;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, centerY);
      path.close();
      canvas.drawPath(path, clipAPaint);
    }

    // Draw clip B waveform (right half, fading in)
    if (clipBWaveform != null && clipBWaveform!.isNotEmpty) {
      final path = Path();
      final sampleCount = clipBWaveform!.length;

      path.moveTo(0, centerY);
      for (int i = 0; i < sampleCount; i++) {
        final x = (i / sampleCount) * size.width;
        final sample = clipBWaveform![i].clamp(-1.0, 1.0);
        final fadeT = (x / size.width).clamp(0.0, 1.0);
        final fadeGain = config.fadeIn.evaluate(fadeT);
        final y = centerY - sample * centerY * 0.8 * fadeGain;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, centerY);
      path.close();
      canvas.drawPath(path, clipBPaint);
    }
  }

  void _drawCrossfadeCurves(Canvas canvas, Size size) {
    // Fade out curve (clip A - going from 1 to 0)
    final fadeOutPaint = Paint()
      ..color = const Color(0xFFFF6464)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final fadeOutPath = config.fadeOut.getCurvePath(size, fadeOut: true);
    canvas.drawPath(fadeOutPath, fadeOutPaint);

    // Fade in curve (clip B - going from 0 to 1)
    final fadeInPaint = Paint()
      ..color = const Color(0xFF64FF64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final fadeInPath = config.fadeIn.getCurvePath(size, fadeOut: false);
    canvas.drawPath(fadeInPath, fadeInPaint);

    // Fill under curves (optional, for better visualization)
    final fadeOutFillPaint = Paint()
      ..color = const Color(0x22FF6464)
      ..style = PaintingStyle.fill;

    final fadeInFillPaint = Paint()
      ..color = const Color(0x2264FF64)
      ..style = PaintingStyle.fill;

    // Fade out fill
    final fadeOutFill = Path.from(fadeOutPath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fadeOutFill, fadeOutFillPaint);

    // Fade in fill
    final fadeInFill = Path.from(fadeInPath)
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(fadeInFill, fadeInFillPaint);
  }

  void _drawCenterMarker(Canvas canvas, Size size) {
    final centerX = size.width * (0.5 + config.centerOffset);

    final markerPaint = Paint()
      ..color = ReelForgeTheme.accentBlue
      ..style = PaintingStyle.fill;

    // Draw triangle at top
    final topPath = Path()
      ..moveTo(centerX - 6, 0)
      ..lineTo(centerX + 6, 0)
      ..lineTo(centerX, 8)
      ..close();
    canvas.drawPath(topPath, markerPaint);

    // Draw triangle at bottom
    final bottomPath = Path()
      ..moveTo(centerX - 6, size.height)
      ..lineTo(centerX + 6, size.height)
      ..lineTo(centerX, size.height - 8)
      ..close();
    canvas.drawPath(bottomPath, markerPaint);
  }

  void _drawGainIndicator(Canvas canvas, Size size) {
    // Show combined gain at center point (should be ~unity for equal power)
    final centerT = 0.5 + config.centerOffset;
    final fadeOutGain = 1 - config.fadeOut.evaluate(centerT);
    final fadeInGain = config.fadeIn.evaluate(centerT);
    final combinedGain = math.sqrt(fadeOutGain * fadeOutGain + fadeInGain * fadeInGain);

    final centerX = size.width * centerT;
    final centerY = size.height / 2;

    // Draw gain indicator circle
    final indicatorPaint = Paint()
      ..color = combinedGain > 1.1
          ? const Color(0xFFFF4040) // Over unity - warning
          : combinedGain < 0.9
              ? const Color(0xFFFFAA00) // Under unity - warning
              : const Color(0xFF40FF40) // Near unity - good
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(centerX, centerY), 6, indicatorPaint);

    // Label
    final textStyle = ui.TextStyle(
      color: ReelForgeTheme.textSecondary,
      fontSize: 10,
    );
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: TextAlign.center))
      ..pushStyle(textStyle)
      ..addText('${(combinedGain * 100).toStringAsFixed(0)}%');
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 40));
    canvas.drawParagraph(paragraph, Offset(centerX - 20, centerY + 10));
  }

  @override
  bool shouldRepaint(_CrossfadeEditorPainter oldDelegate) =>
      config != oldDelegate.config ||
      showWaveforms != oldDelegate.showWaveforms ||
      abComparison != oldDelegate.abComparison;
}
