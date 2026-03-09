/// Dynamic Split Panel — FabFilter-style DAW Lower Zone EDIT tab
///
/// Reaper-style Dynamic Split: detect transients / gate / silence,
/// preview split points on waveform, adjust parameters, then apply.
///
/// Modes:
/// - TRANSIENT: onset detection via Rust FFI (5 algorithms)
/// - GATE: splits when signal drops below threshold (noise gate)
/// - SILENCE: removes silent regions, keeps audible content
///
/// Actions: Split clips, add stretch markers, or create regions.
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../services/dynamic_split_service.dart';
import '../../../../src/rust/native_ffi.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_knob.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class DynamicSplitPanel extends StatefulWidget {
  final int? selectedTrackId;
  final double tempo;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const DynamicSplitPanel({
    super.key,
    this.selectedTrackId,
    this.tempo = 120.0,
    this.onAction,
  });

  @override
  State<DynamicSplitPanel> createState() => _DynamicSplitPanelState();
}

class _DynamicSplitPanelState extends State<DynamicSplitPanel> {
  // ═══════════════════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════════════════

  final _service = DynamicSplitService.instance;
  bool _showExpert = false;
  bool _isAnalyzing = false;
  bool _previewActive = true;
  Float32List? _waveformMins;
  Float32List? _waveformMaxs;
  int _waveformPixels = 0;
  int _waveformClipId = 0;

  static const _modeLabels = ['TRANS', 'GATE', 'SIL'];
  static const _actionLabels = ['SPLIT', 'STRCH', 'RGN'];
  static const _algoLabels = ['ENH', 'HI', 'LO', 'SPF', 'CDM'];

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void didUpdateWidget(covariant DynamicSplitPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedTrackId != oldWidget.selectedTrackId) {
      _waveformMins = null;
      _waveformMaxs = null;
      _waveformPixels = 0;
      _waveformClipId = 0;
      _service.clear();
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: FabFilterColors.bgDeep),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _hasClip
                ? _buildContent()
                : _buildNoSelection(),
          ),
        ],
      ),
    );
  }

  bool get _hasClip =>
      widget.selectedTrackId != null && widget.selectedTrackId! > 0;

  int _resolveClipId() {
    if (widget.selectedTrackId == null || widget.selectedTrackId! <= 0) return 0;
    return NativeFFI.instance.getFirstClipId(widget.selectedTrackId!);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        border: Border(
            bottom: BorderSide(
                color: FabFilterColors.orange.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Text('FF SPLIT',
              style: FabFilterText.sectionHeader.copyWith(
                color: FabFilterColors.orange,
                fontSize: 10,
                letterSpacing: 1.2,
              )),
          const SizedBox(width: 8),
          // Split point count badge
          if (_service.splitPointCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: FabFilterColors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                    color: FabFilterColors.orange.withValues(alpha: 0.4)),
              ),
              child: Text(
                '${_service.splitPointCount} pts → ${_service.estimatedClipCount} clips',
                style: FabFilterText.paramValue(FabFilterColors.orange)
                    .copyWith(fontSize: 9),
              ),
            ),
          const Spacer(),
          // Preview toggle
          FabCompactToggle(
            label: 'PREV',
            active: _previewActive,
            onToggle: () => setState(() => _previewActive = !_previewActive),
            color: FabFilterColors.green,
          ),
          const SizedBox(width: 6),
          // Expert mode
          FabMiniButton(
            label: 'E',
            active: _showExpert,
            onTap: () => setState(() => _showExpert = !_showExpert),
            accentColor: FabFilterColors.orange,
          ),
          const SizedBox(width: 6),
          // Close
          GestureDetector(
            onTap: () => widget.onAction?.call('close', null),
            child: const Icon(Icons.close,
                size: 14, color: FabFilterColors.textTertiary),
          ),
        ],
      ),
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
          Icon(Icons.content_cut,
              size: 28,
              color: FabFilterColors.textTertiary.withValues(alpha: 0.3)),
          const SizedBox(height: 6),
          Text('Select a clip for Dynamic Split',
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
          // Mode + Action selector row
          _buildModeRow(),
          const SizedBox(height: 6),
          // Main controls row (knobs + parameters)
          _buildControlsRow(),
          const SizedBox(height: 6),
          // Waveform display with split markers
          Expanded(child: _buildWaveformDisplay()),
          const SizedBox(height: 6),
          // Bottom: pad/fade + action buttons
          _buildBottomRow(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODE ROW — Detection mode + Action type
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildModeRow() {
    return Row(
      children: [
        Expanded(
          child: FabEnumSelector(
            label: 'MODE',
            value: _service.mode.index,
            options: _modeLabels,
            onChanged: (v) =>
                _service.setMode(SplitDetectionMode.values[v]),
            color: FabFilterColors.orange,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: FabEnumSelector(
            label: 'ACT',
            value: _service.action.index,
            options: _actionLabels,
            onChanged: (v) =>
                _service.setAction(SplitAction.values[v]),
            color: FabFilterColors.cyan,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTROLS ROW — mode-specific parameters
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildControlsRow() {
    return SizedBox(
      height: _showExpert ? 110 : 86,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary knob (Sensitivity or Threshold)
          Expanded(child: _buildPrimaryKnob()),
          const SizedBox(width: 12),
          // Right column: secondary controls
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSecondaryControls(),
                const SizedBox(height: 4),
                // Detect button row
                Row(
                  children: [
                    _buildActionButton(
                      label: _isAnalyzing ? 'WAIT' : 'DETECT',
                      icon:
                          _isAnalyzing ? Icons.hourglass_empty : Icons.search,
                      color: FabFilterColors.orange,
                      filled: true,
                      onTap: _isAnalyzing ? null : _analyzeClip,
                    ),
                    const SizedBox(width: 6),
                    // Reset button
                    _buildActionButton(
                      label: 'RESET',
                      icon: Icons.refresh,
                      color: FabFilterColors.textTertiary,
                      filled: false,
                      onTap: () {
                        _service.resetDefaults();
                        _analyzeClip();
                      },
                    ),
                  ],
                ),
                if (_showExpert) ...[
                  const SizedBox(height: 4),
                  _buildExpertControls(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryKnob() {
    if (_service.mode == SplitDetectionMode.transient) {
      return FabFilterKnob(
        value: _service.sensitivity,
        label: 'SENS',
        display: '${(_service.sensitivity * 100).toInt()}%',
        color: FabFilterColors.orange,
        size: 56,
        adaptive: true,
        defaultValue: 0.5,
        onChanged: (v) => _service.setSensitivity(v),
      );
    } else {
      // Gate / Silence: threshold knob
      final normalized =
          ((_service.thresholdDb + 96.0) / 96.0).clamp(0.0, 1.0);
      return FabFilterKnob(
        value: normalized,
        label: 'THRESH',
        display: '${_service.thresholdDb.toStringAsFixed(1)} dB',
        color: FabFilterColors.yellow,
        size: 56,
        adaptive: true,
        defaultValue: ((-40.0 + 96.0) / 96.0),
        onChanged: (v) => _service.setThresholdDb(v * 96.0 - 96.0),
      );
    }
  }

  Widget _buildSecondaryControls() {
    if (_service.mode == SplitDetectionMode.transient) {
      return FabEnumSelector(
        label: 'ALG',
        value: _service.algorithm,
        options: _algoLabels,
        onChanged: (v) => _service.setAlgorithm(v),
        color: FabFilterColors.orange,
      );
    } else {
      // Gate / Silence: min silence + min length sliders
      return Column(
        children: [
          FabMiniSlider(
            label: 'SIL',
            value: (_service.minSilenceMs / 1000.0).clamp(0.0, 1.0),
            display: '${_service.minSilenceMs.toInt()}ms',
            onChanged: (v) => _service.setMinSilenceMs(v * 1000.0),
            activeColor: FabFilterColors.yellow,
            displayWidth: 36,
          ),
          const SizedBox(height: 2),
          FabMiniSlider(
            label: 'MIN',
            value: (_service.minLengthMs / 500.0).clamp(0.0, 1.0),
            display: '${_service.minLengthMs.toInt()}ms',
            onChanged: (v) => _service.setMinLengthMs(v * 500.0),
            activeColor: FabFilterColors.yellow,
            displayWidth: 36,
          ),
        ],
      );
    }
  }

  Widget _buildExpertControls() {
    if (_service.mode == SplitDetectionMode.transient) {
      return Row(
        children: [
          _buildPresetChip('Low', 0.2),
          const SizedBox(width: 3),
          _buildPresetChip('Med', 0.5),
          const SizedBox(width: 3),
          _buildPresetChip('High', 0.8),
          const SizedBox(width: 3),
          _buildPresetChip('Ultra', 0.95),
        ],
      );
    } else {
      return Row(
        children: [
          _buildThreshPresetChip('-20 dB', -20.0),
          const SizedBox(width: 3),
          _buildThreshPresetChip('-40 dB', -40.0),
          const SizedBox(width: 3),
          _buildThreshPresetChip('-60 dB', -60.0),
          const SizedBox(width: 3),
          _buildThreshPresetChip('-80 dB', -80.0),
        ],
      );
    }
  }

  Widget _buildPresetChip(String label, double value) {
    final isActive = (_service.sensitivity - value).abs() < 0.05;
    return GestureDetector(
      onTap: () => _service.setSensitivity(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: isActive
              ? FabFilterColors.orange.withValues(alpha: 0.2)
              : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color:
                isActive ? FabFilterColors.orange : FabFilterColors.border,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: isActive
                  ? FabFilterColors.orange
                  : FabFilterColors.textTertiary,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            )),
      ),
    );
  }

  Widget _buildThreshPresetChip(String label, double dbValue) {
    final isActive = (_service.thresholdDb - dbValue).abs() < 1.0;
    return GestureDetector(
      onTap: () => _service.setThresholdDb(dbValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: isActive
              ? FabFilterColors.yellow.withValues(alpha: 0.2)
              : FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color:
                isActive ? FabFilterColors.yellow : FabFilterColors.border,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: isActive
                  ? FabFilterColors.yellow
                  : FabFilterColors.textTertiary,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            )),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WAVEFORM DISPLAY — waveform + split point markers + region overlays
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildWaveformDisplay() {
    return Container(
      decoration: FabFilterDecorations.display(),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Load waveform if needed at current width or clip changed
          final pixelWidth = constraints.maxWidth.toInt();
          final currentClipId = _resolveClipId();
          if (_waveformMins == null || _waveformPixels != pixelWidth || _waveformClipId != currentClipId) {
            _loadWaveformAtWidth(pixelWidth);
          }
          return CustomPaint(
            painter: _DynamicSplitPainter(
              waveformMins: _waveformMins,
              waveformMaxs: _waveformMaxs,
              splitPoints: _previewActive ? _service.splitPoints : [],
              regions: _previewActive ? _service.regions : [],
              clipDuration: _service.clipDuration,
              mode: _service.mode,
              thresholdDb: _service.thresholdDb,
              accentColor: FabFilterColors.orange,
            ),
            size: Size(constraints.maxWidth, constraints.maxHeight),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM ROW — Pad, Fade, Apply
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildBottomRow() {
    return Column(
      children: [
        // Pad before/after + Fade in/out
        Row(
          children: [
            Expanded(
              child: FabMiniSlider(
                label: 'PAD<',
                value: (_service.padBeforeMs / 100.0).clamp(0.0, 1.0),
                display: '${_service.padBeforeMs.toStringAsFixed(0)}ms',
                onChanged: (v) => _service.setPadBeforeMs(v * 100.0),
                activeColor: FabFilterColors.cyan,
                displayWidth: 32,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: FabMiniSlider(
                label: 'PAD>',
                value: (_service.padAfterMs / 100.0).clamp(0.0, 1.0),
                display: '${_service.padAfterMs.toStringAsFixed(0)}ms',
                onChanged: (v) => _service.setPadAfterMs(v * 100.0),
                activeColor: FabFilterColors.cyan,
                displayWidth: 32,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: FabMiniSlider(
                label: 'FD IN',
                value: (_service.fadeInMs / 100.0).clamp(0.0, 1.0),
                display: '${_service.fadeInMs.toStringAsFixed(0)}ms',
                onChanged: (v) => _service.setFadeInMs(v * 100.0),
                activeColor: FabFilterColors.green,
                displayWidth: 32,
                labelWidth: 32,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: FabMiniSlider(
                label: 'FD OUT',
                value: (_service.fadeOutMs / 100.0).clamp(0.0, 1.0),
                display: '${_service.fadeOutMs.toStringAsFixed(0)}ms',
                onChanged: (v) => _service.setFadeOutMs(v * 100.0),
                activeColor: FabFilterColors.green,
                displayWidth: 32,
                labelWidth: 36,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Action buttons row
        Row(
          children: [
            // Min clip length
            if (_showExpert) ...[
              Expanded(
                child: FabMiniSlider(
                  label: 'MIN',
                  value: (_service.minClipLengthMs / 200.0).clamp(0.0, 1.0),
                  display: '${_service.minClipLengthMs.toInt()}ms',
                  onChanged: (v) =>
                      _service.setMinClipLengthMs(v * 200.0),
                  activeColor: FabFilterColors.purple,
                  displayWidth: 32,
                ),
              ),
              const SizedBox(width: 6),
            ],
            const Spacer(),
            // Apply button
            _buildActionButton(
              label: 'APPLY',
              icon: Icons.check,
              color: FabFilterColors.green,
              filled: true,
              onTap: _service.splitPointCount > 0 ? _applySplit : null,
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION BUTTON
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool filled,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final effectiveColor = enabled ? color : FabFilterColors.textDisabled;

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
            Text(label,
                style: FabFilterText.button.copyWith(
                  fontSize: 9,
                  color: effectiveColor,
                )),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYSIS
  // ═══════════════════════════════════════════════════════════════════════════

  void _loadWaveformAtWidth(int pixelWidth) {
    final clipId = _resolveClipId();
    if (clipId == 0 || pixelWidth <= 0) return;

    final ffi = NativeFFI.instance;
    final totalFrames = ffi.getClipTotalFrames(clipId);
    if (totalFrames <= 0) return;

    final data = ffi.queryWaveformPixels(clipId, 0, totalFrames, pixelWidth);
    if (data != null) {
      _waveformMins = data.mins;
      _waveformMaxs = data.maxs;
      _waveformPixels = pixelWidth;
      _waveformClipId = clipId;
    }
  }

  void _analyzeClip() {
    final clipId = _resolveClipId();
    if (clipId == 0) return;
    setState(() => _isAnalyzing = true);

    try {
      _service.analyze(clipId);
    } catch (_) {
      _service.clear();
    }

    setState(() => _isAnalyzing = false);
  }

  void _applySplit() {
    widget.onAction?.call('dynamicSplit', {
      'clipId': _resolveClipId(),
      'trackId': widget.selectedTrackId,
      'mode': _service.mode.name,
      'action': _service.action.name,
      'splitPoints': _service.splitPoints
          .map((p) => {'time': p.timeSeconds, 'strength': p.strength})
          .toList(),
      'regions': _service.regions
          .where((r) => r.isAudible)
          .map((r) => {'start': r.startTime, 'end': r.endTime})
          .toList(),
      'fadeInMs': _service.fadeInMs,
      'fadeOutMs': _service.fadeOutMs,
      'minClipLengthMs': _service.minClipLengthMs,
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WAVEFORM + SPLIT POINT PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _DynamicSplitPainter extends CustomPainter {
  final Float32List? waveformMins;
  final Float32List? waveformMaxs;
  final List<SplitPoint> splitPoints;
  final List<AudioRegionResult> regions;
  final double clipDuration;
  final SplitDetectionMode mode;
  final double thresholdDb;
  final Color accentColor;

  _DynamicSplitPainter({
    required this.waveformMins,
    required this.waveformMaxs,
    required this.splitPoints,
    required this.regions,
    required this.clipDuration,
    required this.mode,
    required this.thresholdDb,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = FabFilterColors.bgVoid,
    );

    if (clipDuration <= 0) {
      _paintEmptyState(canvas, size);
      return;
    }

    // Paint region overlays (gate/silence modes)
    if (regions.isNotEmpty) {
      _paintRegions(canvas, size);
    }

    // Paint waveform
    if (waveformMins != null && waveformMins!.isNotEmpty) {
      _paintWaveform(canvas, size);
    }

    // Paint threshold line (gate/silence modes)
    if (mode != SplitDetectionMode.transient) {
      _paintThresholdLine(canvas, size);
    }

    // Paint split point markers
    if (splitPoints.isNotEmpty) {
      _paintSplitMarkers(canvas, size);
    }
  }

  void _paintEmptyState(Canvas canvas, Size size) {
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
        text: 'Click DETECT to analyze audio',
        style: TextStyle(
          fontSize: 9,
          color: FabFilterColors.textTertiary.withValues(alpha: 0.5),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
        canvas, Offset(size.width / 2 - tp.width / 2, y - tp.height / 2));
  }

  void _paintWaveform(Canvas canvas, Size size) {
    final mins = waveformMins!;
    final maxs = waveformMaxs;
    final midY = size.height / 2;
    final ampScale = size.height * 0.45;
    final pixelCount = mins.length.clamp(0, size.width.toInt());

    // Fill between min and max envelope
    final fillPath = Path();
    for (int i = 0; i < pixelCount; i++) {
      final x = i.toDouble();
      final maxVal = (maxs != null && i < maxs.length) ? maxs[i] : mins[i].abs();
      final yTop = midY - maxVal.abs() * ampScale;
      if (i == 0) {
        fillPath.moveTo(x, yTop);
      } else {
        fillPath.lineTo(x, yTop);
      }
    }
    for (int i = pixelCount - 1; i >= 0; i--) {
      final x = i.toDouble();
      final minVal = mins[i];
      final yBot = midY - minVal * ampScale; // mins are negative → goes below midY
      fillPath.lineTo(x, yBot);
    }
    fillPath.close();

    canvas.drawPath(fillPath, Paint()
      ..color = FabFilterColors.cyan.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill);

    // Stroke outlines
    final wavePaint = Paint()
      ..color = FabFilterColors.cyan.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Top envelope (maxs)
    final topPath = Path();
    for (int i = 0; i < pixelCount; i++) {
      final x = i.toDouble();
      final maxVal = (maxs != null && i < maxs.length) ? maxs[i] : mins[i].abs();
      final y = midY - maxVal.abs() * ampScale;
      if (i == 0) topPath.moveTo(x, y); else topPath.lineTo(x, y);
    }
    canvas.drawPath(topPath, wavePaint);

    // Bottom envelope (mins)
    final botPath = Path();
    for (int i = 0; i < pixelCount; i++) {
      final x = i.toDouble();
      final y = midY - mins[i] * ampScale;
      if (i == 0) botPath.moveTo(x, y); else botPath.lineTo(x, y);
    }
    canvas.drawPath(botPath, wavePaint);
  }

  void _paintThresholdLine(Canvas canvas, Size size) {
    // Convert dB threshold to linear amplitude (0-1)
    final linearThreshold = thresholdDb <= -96.0
        ? 0.0
        : _pow10(thresholdDb / 20.0);
    final midY = size.height / 2;
    final ampScale = size.height * 0.45;

    final threshY1 = midY - linearThreshold * ampScale;
    final threshY2 = midY + linearThreshold * ampScale;

    final threshPaint = Paint()
      ..color = FabFilterColors.yellow.withValues(alpha: 0.4)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Dashed line effect
    const dashWidth = 4.0;
    const gapWidth = 4.0;
    for (double x = 0; x < size.width; x += dashWidth + gapWidth) {
      final endX = (x + dashWidth).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, threshY1), Offset(endX, threshY1), threshPaint);
      canvas.drawLine(Offset(x, threshY2), Offset(endX, threshY2), threshPaint);
    }

    // Label
    final tp = TextPainter(
      text: TextSpan(
        text: '${thresholdDb.toStringAsFixed(0)} dB',
        style: TextStyle(
          fontSize: 7,
          color: FabFilterColors.yellow.withValues(alpha: 0.7),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(2, threshY1 - tp.height - 1));
  }

  void _paintRegions(Canvas canvas, Size size) {
    for (final r in regions) {
      final x1 = (r.startTime / clipDuration) * size.width;
      final x2 = (r.endTime / clipDuration) * size.width;

      if (r.isAudible) {
        // Green tint for audible regions
        canvas.drawRect(
          Rect.fromLTRB(x1, 0, x2, size.height),
          Paint()
            ..color = FabFilterColors.green.withValues(alpha: 0.06),
        );
        // Region border
        canvas.drawLine(
          Offset(x1, 0),
          Offset(x1, size.height),
          Paint()
            ..color = FabFilterColors.green.withValues(alpha: 0.3)
            ..strokeWidth = 1.0,
        );
        canvas.drawLine(
          Offset(x2, 0),
          Offset(x2, size.height),
          Paint()
            ..color = FabFilterColors.green.withValues(alpha: 0.3)
            ..strokeWidth = 1.0,
        );
      } else {
        // Red/dark tint for silence
        canvas.drawRect(
          Rect.fromLTRB(x1, 0, x2, size.height),
          Paint()
            ..color = FabFilterColors.red.withValues(alpha: 0.05),
        );
      }
    }
  }

  void _paintSplitMarkers(Canvas canvas, Size size) {
    for (final sp in splitPoints) {
      final x = (sp.timeSeconds / clipDuration) * size.width;
      final alpha = 0.5 + sp.strength * 0.5;

      // Glow
      final glowPaint = Paint()
        ..color = accentColor.withValues(alpha: alpha * 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), glowPaint);

      // Main marker
      final markerPaint = Paint()
        ..color = accentColor.withValues(alpha: alpha)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), markerPaint);

      // Arrow/triangle at top
      final arrowPath = Path()
        ..moveTo(x - 3, 0)
        ..lineTo(x + 3, 0)
        ..lineTo(x, 5)
        ..close();
      canvas.drawPath(
          arrowPath, Paint()..color = accentColor.withValues(alpha: alpha));
    }
  }

  static double _pow10(double x) {
    final lnResult = x * 2.302585092994046;
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 20; i++) {
      term *= lnResult / i;
      result += term;
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _DynamicSplitPainter old) =>
      old.waveformMins != waveformMins ||
      old.waveformMaxs != waveformMaxs ||
      old.splitPoints.length != splitPoints.length ||
      old.regions.length != regions.length ||
      old.clipDuration != clipDuration ||
      old.mode != mode ||
      old.thresholdDb != thresholdDb;
}
