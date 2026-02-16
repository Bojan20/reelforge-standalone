// Beat Detective Panel — FabFilter-style DAW Lower Zone EDIT tab
// Transient detection (real FFI), beat quantization, groove extraction

import 'package:flutter/material.dart';
import '../../../../services/beat_detective_service.dart';
import '../../../../src/rust/native_ffi.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_knob.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class BeatDetectivePanel extends StatefulWidget {
  final int? selectedTrackId;
  final double tempo;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const BeatDetectivePanel({
    super.key,
    this.selectedTrackId,
    this.tempo = 120.0,
    this.onAction,
  });

  @override
  State<BeatDetectivePanel> createState() => _BeatDetectivePanelState();
}

class _BeatDetectivePanelState extends State<BeatDetectivePanel> {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  double _sensitivity = 0.5;
  int _algorithmIndex = 0; // 0=Enhanced, 1=HighEmphasis, 2=LowEmphasis, 3=SpectralFlux, 4=ComplexDomain
  int _quantizeGridIndex = 2; // default 1/4
  double _quantizeStrength = 1.0; // 0.0 - 1.0
  bool _showTransients = true;
  bool _isAnalyzing = false;
  bool _isStateB = false;
  bool _bypassed = false;
  bool _showExpert = false;
  List<Transient> _detectedTransients = [];

  static const _gridLabels = ['1/1', '1/2', '1/4', '1/8', '1/16', '1/32'];
  static const _algoLabels = ['ENH', 'HI', 'LO', 'SPF', 'CDM'];

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: FabFilterColors.bgDeep),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          // Content
          Expanded(
            child: widget.selectedTrackId == null
                ? _buildNoSelection()
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER — FabCompactHeader with yellow/amber accent
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return FabCompactHeader(
      title: 'FF BEAT',
      accentColor: FabFilterColors.yellow,
      isStateB: _isStateB,
      onToggleAB: () => setState(() => _isStateB = !_isStateB),
      bypassed: _bypassed,
      onToggleBypass: () => setState(() => _bypassed = !_bypassed),
      showExpert: _showExpert,
      onToggleExpert: () => setState(() => _showExpert = !_showExpert),
      onClose: () => widget.onAction?.call('close', null),
      statusWidget: _detectedTransients.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: FabFilterColors.yellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                    color: FabFilterColors.yellow.withValues(alpha: 0.4)),
              ),
              child: Text(
                '${_detectedTransients.length}',
                style: FabFilterText.paramValue(FabFilterColors.yellow)
                    .copyWith(fontSize: 9),
              ),
            )
          : null,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NO SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNoSelection() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq, size: 28,
              color: FabFilterColors.textTertiary.withValues(alpha: 0.3)),
          const SizedBox(height: 6),
          Text('Select a clip for Beat Detective',
              style: FabFilterText.paramLabel
                  .copyWith(color: FabFilterColors.textTertiary)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAIN CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          // Top row: Sensitivity knob + Algorithm + BPM
          _buildControlsRow(),
          const SizedBox(height: 6),
          // Transient display
          Expanded(child: _buildTransientDisplay()),
          const SizedBox(height: 6),
          // Bottom row: Quantize grid + strength + groove + actions
          _buildBottomRow(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTROLS ROW — Knob + Algorithm selector + BPM + Show toggle
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildControlsRow() {
    return SizedBox(
      height: 86,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sensitivity knob
          FabFilterKnob(
            value: _sensitivity,
            label: 'SENS',
            display: '${(_sensitivity * 100).toInt()}%',
            color: FabFilterColors.yellow,
            size: 56,
            defaultValue: 0.5,
            onChanged: (v) => setState(() => _sensitivity = v),
          ),
          const SizedBox(width: 12),
          // Right column: Algorithm + BPM + Show toggle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Algorithm selector
                FabEnumSelector(
                  label: 'ALG',
                  value: _algorithmIndex,
                  options: _algoLabels,
                  onChanged: (v) => setState(() => _algorithmIndex = v),
                  color: FabFilterColors.yellow,
                ),
                const SizedBox(height: 4),
                // BPM display + Show transients toggle
                Row(
                  children: [
                    // BPM badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: FabFilterColors.bgMid,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: FabFilterColors.border),
                      ),
                      child: Text(
                        '${widget.tempo.toStringAsFixed(1)} BPM',
                        style: FabFilterText.paramLabel.copyWith(
                          fontSize: 8,
                          color: FabFilterColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    FabCompactToggle(
                      label: 'SHOW',
                      active: _showTransients,
                      onToggle: () =>
                          setState(() => _showTransients = !_showTransients),
                      color: FabFilterColors.yellow,
                    ),
                    const Spacer(),
                    // Detect button
                    _buildActionButton(
                      label: _isAnalyzing ? 'WAIT' : 'DETECT',
                      icon: _isAnalyzing
                          ? Icons.hourglass_empty
                          : Icons.search,
                      color: FabFilterColors.yellow,
                      filled: true,
                      onTap: _isAnalyzing ? null : _analyzeClip,
                    ),
                  ],
                ),
                if (_showExpert) ...[
                  const SizedBox(height: 4),
                  // Sensitivity presets row
                  Row(
                    children: [
                      _buildPresetChip('Low', 0.2),
                      const SizedBox(width: 3),
                      _buildPresetChip('Med', 0.5),
                      const SizedBox(width: 3),
                      _buildPresetChip('High', 0.8),
                      const SizedBox(width: 3),
                      _buildPresetChip('Ultra', 0.95),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, double value) {
    final isActive = (_sensitivity - value).abs() < 0.05;
    return GestureDetector(
      onTap: () => setState(() => _sensitivity = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: isActive
              ? FabFilterColors.yellow.withValues(alpha: 0.2)
              : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive ? FabFilterColors.yellow : FabFilterColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? FabFilterColors.yellow
                : FabFilterColors.textTertiary,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSIENT DISPLAY — FabFilter-style dark canvas with yellow markers
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTransientDisplay() {
    return Container(
      decoration: FabFilterDecorations.display(),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _FabTransientPainter(
          transients: _detectedTransients,
          showTransients: _showTransients,
          tempo: widget.tempo,
          quantizeGrid: _gridLabels[_quantizeGridIndex],
          accentColor: FabFilterColors.yellow,
        ),
        size: Size.infinite,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM ROW — Quantize grid + strength + groove + quantize button
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomRow() {
    return Column(
      children: [
        // Quantize grid selector
        Row(
          children: [
            FabEnumSelector(
              label: 'GRID',
              value: _quantizeGridIndex,
              options: _gridLabels,
              onChanged: (v) => setState(() => _quantizeGridIndex = v),
              color: FabFilterColors.cyan,
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Strength slider + groove + quantize
        Row(
          children: [
            // Quantize strength
            Expanded(
              child: FabMiniSlider(
                label: 'STR',
                value: _quantizeStrength,
                display: '${(_quantizeStrength * 100).toInt()}%',
                onChanged: (v) => setState(() => _quantizeStrength = v),
                activeColor: FabFilterColors.cyan,
              ),
            ),
            const SizedBox(width: 6),
            // Groove extract
            FabCompactToggle(
              label: 'EXTRACT',
              active: false,
              onToggle: () {
                if (_detectedTransients.isNotEmpty) {
                  widget.onAction?.call('extractGroove', {
                    'transients': _detectedTransients
                        .map((t) => {
                              'position': t.position,
                              'strength': t.strength
                            })
                        .toList(),
                    'tempo': widget.tempo,
                  });
                }
              },
              color: FabFilterColors.green,
            ),
            const SizedBox(width: 3),
            FabCompactToggle(
              label: 'APPLY',
              active: false,
              onToggle: () =>
                  widget.onAction?.call('applyGroove', null),
              color: FabFilterColors.purple,
            ),
            const SizedBox(width: 6),
            // Quantize button
            _buildActionButton(
              label: 'QUANTIZE',
              icon: Icons.straighten,
              color: FabFilterColors.cyan,
              filled: false,
              onTap: _detectedTransients.isNotEmpty ? _quantize : null,
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION BUTTON — FabFilter-styled button (no ElevatedButton)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool filled,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final effectiveColor =
        enabled ? color : FabFilterColors.textDisabled;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: filled && enabled
              ? color.withValues(alpha: 0.25)
              : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: enabled
                ? (filled
                    ? color.withValues(alpha: 0.6)
                    : FabFilterColors.borderMedium)
                : FabFilterColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: effectiveColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: FabFilterText.button.copyWith(
                fontSize: 9,
                color: effectiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REAL FFI TRANSIENT DETECTION
  // ═══════════════════════════════════════════════════════════════════════════

  void _analyzeClip() {
    if (widget.selectedTrackId == null) return;
    setState(() => _isAnalyzing = true);

    try {
      final ffi = NativeFFI.instance;
      final sampleRate = ffi.getClipSampleRate(widget.selectedTrackId!);

      final results = ffi.detectClipTransients(
        widget.selectedTrackId!,
        sensitivity: _sensitivity,
        algorithm: _algorithmIndex,
        maxCount: 500,
      );

      final sr = sampleRate > 0 ? sampleRate.toDouble() : 44100.0;
      setState(() {
        _detectedTransients = results
            .map((r) => Transient(
                  position: r.position / sr,
                  strength: r.strength.clamp(0.0, 1.0),
                ))
            .toList();
      });
    } catch (e) {
      debugPrint('[BeatDetective] FFI detection failed: $e');
      // Clear stale results on failure
      setState(() => _detectedTransients = []);
    }

    setState(() => _isAnalyzing = false);
  }

  void _quantize() {
    widget.onAction?.call('quantizeTransients', {
      'trackId': widget.selectedTrackId,
      'grid': _gridLabels[_quantizeGridIndex],
      'strength': _quantizeStrength,
      'transientCount': _detectedTransients.length,
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TRANSIENT PAINTER — FabFilter visual style
// ═══════════════════════════════════════════════════════════════════════════════

class _FabTransientPainter extends CustomPainter {
  final List<Transient> transients;
  final bool showTransients;
  final double tempo;
  final String quantizeGrid;
  final Color accentColor;

  _FabTransientPainter({
    required this.transients,
    required this.showTransients,
    required this.tempo,
    required this.quantizeGrid,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background fill
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = FabFilterColors.bgVoid,
    );

    if (transients.isEmpty) {
      _paintEmptyState(canvas, size);
      return;
    }

    final maxTime = transients.last.position + 0.5;

    // Beat grid lines
    _paintBeatGrid(canvas, size, maxTime);

    // Quantize grid (sub-beats)
    _paintQuantizeGrid(canvas, size, maxTime);

    // Transient markers
    if (showTransients) {
      _paintTransients(canvas, size, maxTime);
    }
  }

  void _paintEmptyState(Canvas canvas, Size size) {
    // Center line
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = FabFilterColors.grid
        ..strokeWidth = 0.5,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: 'Click DETECT to analyze transients',
        style: TextStyle(
          fontSize: 9,
          color: FabFilterColors.textTertiary.withValues(alpha: 0.5),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(size.width / 2 - tp.width / 2, y - tp.height / 2));
  }

  void _paintBeatGrid(Canvas canvas, Size size, double maxTime) {
    final beatDuration = 60.0 / tempo;
    final gridPaint = Paint()
      ..color = FabFilterColors.grid
      ..strokeWidth = 0.5;
    final strongGridPaint = Paint()
      ..color = FabFilterColors.grid.withValues(alpha: 0.8)
      ..strokeWidth = 1.0;

    int beatIndex = 0;
    for (double t = 0; t < maxTime; t += beatDuration) {
      final x = (t / maxTime) * size.width;
      final isBar = beatIndex % 4 == 0;
      canvas.drawLine(
          Offset(x, 0), Offset(x, size.height), isBar ? strongGridPaint : gridPaint);
      beatIndex++;
    }
  }

  void _paintQuantizeGrid(Canvas canvas, Size size, double maxTime) {
    // Parse grid value to fraction
    final gridFraction = _parseGrid(quantizeGrid);
    if (gridFraction <= 0) return;

    final beatDuration = 60.0 / tempo;
    final gridDuration = beatDuration * 4.0 * gridFraction; // whole note * fraction

    final gridPaint = Paint()
      ..color = FabFilterColors.cyan.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    for (double t = 0; t < maxTime; t += gridDuration) {
      final x = (t / maxTime) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  void _paintTransients(Canvas canvas, Size size, double maxTime) {
    for (final t in transients) {
      final x = (t.position / maxTime) * size.width;
      final h = t.strength * size.height * 0.9;
      final alpha = 0.5 + t.strength * 0.5;

      // Glow behind marker
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: alpha * 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawLine(
          Offset(x, size.height), Offset(x, size.height - h), glowPaint);

      // Main marker line
      final markerPaint = Paint()
        ..color = accentColor.withValues(alpha: alpha)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(x, size.height), Offset(x, size.height - h), markerPaint);

      // Dot at top
      canvas.drawCircle(
        Offset(x, size.height - h),
        2.0,
        Paint()..color = accentColor,
      );

      // Strength bar at bottom (thin)
      canvas.drawRect(
        Rect.fromLTWH(x - 0.5, size.height - 2, 1.0, 2.0),
        Paint()..color = accentColor.withValues(alpha: 0.8),
      );
    }
  }

  double _parseGrid(String grid) {
    switch (grid) {
      case '1/1':
        return 1.0;
      case '1/2':
        return 0.5;
      case '1/4':
        return 0.25;
      case '1/8':
        return 0.125;
      case '1/16':
        return 0.0625;
      case '1/32':
        return 0.03125;
      default:
        return 0.25;
    }
  }

  @override
  bool shouldRepaint(covariant _FabTransientPainter old) =>
      old.transients.length != transients.length ||
      old.showTransients != showTransients ||
      old.tempo != tempo ||
      old.quantizeGrid != quantizeGrid;
}
