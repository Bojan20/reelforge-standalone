/// Strip Silence Panel — FabFilter-style DAW Lower Zone EDIT subtab
///
/// Professional silence detection and removal with:
/// - FabFilter visual design (dark pro audio knobs, meters, toggles)
/// - Real FFI wiring via NativeFFI transient detection + clip metadata
/// - Threshold knob with dB presets
/// - Padding / Fades mini-sliders
/// - Waveform-style region visualizer (cyan on void)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../services/strip_silence_service.dart';
import '../../../../src/rust/native_ffi.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_knob.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class StripSilencePanel extends StatefulWidget {
  final int? selectedTrackId;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const StripSilencePanel({super.key, this.selectedTrackId, this.onAction});

  @override
  State<StripSilencePanel> createState() => _StripSilencePanelState();
}

class _StripSilencePanelState extends State<StripSilencePanel> {
  final _service = StripSilenceService.instance;

  // ── Parameters ──────────────────────────────────────────────────────────
  double _thresholdDb = -40.0;
  double _minDurationMs = 100.0;
  double _padBeforeMs = 10.0;
  double _padAfterMs = 20.0;
  double _fadeInMs = 5.0;
  double _fadeOutMs = 10.0;

  // ── State ───────────────────────────────────────────────────────────────
  List<SilentRegion> _detectedRegions = [];
  bool _isAnalyzing = false;
  bool _previewMode = false;
  bool _isStateB = false;
  bool _bypassed = false;
  bool _showExpert = false;

  // ── FFI clip metadata ──────────────────────────────────────────────────
  int _clipSampleRate = 0;
  int _clipTotalFrames = 0;

  @override
  void didUpdateWidget(covariant StripSilencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedTrackId != oldWidget.selectedTrackId) {
      _detectedRegions = [];
      _fetchClipMetadata();
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchClipMetadata();
  }

  void _fetchClipMetadata() {
    if (widget.selectedTrackId == null) return;
    try {
      final ffi = NativeFFI.instance;
      // Resolve track index → clip ID (IMPORTED_AUDIO is keyed by ClipId, not track index)
      final clipId = ffi.getFirstClipId(widget.selectedTrackId!);
      if (clipId == 0) return;
      _clipSampleRate = ffi.getClipSampleRate(clipId);
      _clipTotalFrames = ffi.getClipTotalFrames(clipId);
    } catch (_) {
      _clipSampleRate = 0;
      _clipTotalFrames = 0;
    }
  }

  // ── Threshold ↔ knob value (0.0–1.0) mapping ──────────────────────────
  // Knob value 0.0 = -96 dB, 1.0 = 0 dB
  double get _thresholdKnobValue => (_thresholdDb + 96.0) / 96.0;

  void _setThresholdFromKnob(double v) {
    setState(() => _thresholdDb = (v * 96.0 - 96.0).clamp(-96.0, 0.0));
  }

  // ── Min Duration ↔ knob value mapping ──────────────────────────────────
  // Logarithmic: 10 ms → 5000 ms
  double get _durationKnobValue {
    // log scale: v = log(ms/10) / log(500)
    if (_minDurationMs <= 10) return 0.0;
    return (math.log(_minDurationMs / 10.0) / math.log(500.0)).clamp(0.0, 1.0);
  }

  void _setDurationFromKnob(double v) {
    setState(() {
      _minDurationMs = (10.0 * math.pow(500.0, v)).clamp(10.0, 5000.0);
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (widget.selectedTrackId == null) return _buildNoSelection();

    return Container(
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildKnobRow(),
                    const SizedBox(height: 10),
                    _buildThresholdPresets(),
                    const SizedBox(height: 10),
                    _buildPaddingSection(),
                    const SizedBox(height: 8),
                    _buildFadesSection(),
                    if (_showExpert) ...[
                      const SizedBox(height: 8),
                      _buildExpertSection(),
                    ],
                    const SizedBox(height: 10),
                    _buildRegionDisplay(),
                    const SizedBox(height: 10),
                    _buildActions(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // NO SELECTION
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildNoSelection() {
    return Container(
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.content_cut, size: 28, color: FabFilterColors.cyan.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text('Select a clip for Strip Silence',
                style: FabFilterText.paramLabel.copyWith(
                    color: FabFilterColors.textTertiary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HEADER — FabCompactHeader
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return FabCompactHeader(
      title: 'FF STRIP',
      accentColor: FabFilterColors.cyan,
      isStateB: _isStateB,
      onToggleAB: () => setState(() => _isStateB = !_isStateB),
      bypassed: _bypassed,
      onToggleBypass: () => setState(() => _bypassed = !_bypassed),
      showExpert: _showExpert,
      onToggleExpert: () => setState(() => _showExpert = !_showExpert),
      onClose: () => widget.onAction?.call('close', null),
      statusWidget: _detectedRegions.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: FabFilterColors.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.4)),
              ),
              child: Text('${_detectedRegions.length}',
                  style: FabFilterText.paramValue(FabFilterColors.cyan).copyWith(fontSize: 9)),
            )
          : null,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // KNOB ROW — Threshold + Min Duration
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildKnobRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Threshold Knob (72px)
        FabFilterKnob(
          value: _thresholdKnobValue,
          label: 'THRESHOLD',
          display: '${_thresholdDb.toStringAsFixed(1)} dB',
          color: FabFilterColors.cyan,
          size: 72,
          defaultValue: (_thresholdDb == -40.0) ? _thresholdKnobValue : ((-40.0 + 96.0) / 96.0),
          onChanged: _setThresholdFromKnob,
        ),
        const SizedBox(width: 24),
        // Min Duration Knob (56px)
        FabFilterKnob(
          value: _durationKnobValue,
          label: 'MIN DUR',
          display: _minDurationMs >= 1000
              ? '${(_minDurationMs / 1000).toStringAsFixed(1)}s'
              : '${_minDurationMs.toStringAsFixed(0)}ms',
          color: FabFilterColors.cyan,
          size: 56,
          defaultValue: (math.log(100.0 / 10.0) / math.log(500.0)).clamp(0.0, 1.0),
          onChanged: _setDurationFromKnob,
        ),
        const SizedBox(width: 24),
        // Preview toggle
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => setState(() => _previewMode = !_previewMode),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _previewMode
                      ? FabFilterColors.cyan.withValues(alpha: 0.2)
                      : FabFilterColors.bgSurface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _previewMode ? FabFilterColors.cyan : FabFilterColors.borderMedium,
                  ),
                ),
                child: Icon(
                  _previewMode ? Icons.visibility : Icons.visibility_off,
                  size: 14,
                  color: _previewMode ? FabFilterColors.cyan : FabFilterColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('PREVIEW', style: FabFilterText.paramLabel),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // THRESHOLD PRESETS — quick-select dB values
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildThresholdPresets() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPresetButton('-60', -60.0),
        const SizedBox(width: 3),
        _buildPresetButton('-48', -48.0),
        const SizedBox(width: 3),
        _buildPresetButton('-40', -40.0),
        const SizedBox(width: 3),
        _buildPresetButton('-30', -30.0),
        const SizedBox(width: 3),
        _buildPresetButton('-20', -20.0),
      ],
    );
  }

  Widget _buildPresetButton(String label, double dbValue) {
    final isActive = (_thresholdDb - dbValue).abs() < 1;
    return GestureDetector(
      onTap: () => setState(() => _thresholdDb = dbValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: isActive
            ? FabFilterDecorations.toggleActive(FabFilterColors.cyan)
            : FabFilterDecorations.toggleInactive(),
        child: Text(label,
            style: TextStyle(
              color: isActive ? FabFilterColors.cyan : FabFilterColors.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PADDING SECTION
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPaddingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FabSectionLabel('PADDING'),
        FabMiniSlider(
          label: 'BEF',
          value: _padBeforeMs / 200.0,
          display: '${_padBeforeMs.toStringAsFixed(0)}ms',
          activeColor: FabFilterColors.cyan,
          labelWidth: 26,
          displayWidth: 34,
          onChanged: (v) => setState(() => _padBeforeMs = (v * 200.0).clamp(0.0, 200.0)),
        ),
        const SizedBox(height: 2),
        FabMiniSlider(
          label: 'AFT',
          value: _padAfterMs / 200.0,
          display: '${_padAfterMs.toStringAsFixed(0)}ms',
          activeColor: FabFilterColors.cyan,
          labelWidth: 26,
          displayWidth: 34,
          onChanged: (v) => setState(() => _padAfterMs = (v * 200.0).clamp(0.0, 200.0)),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FADES SECTION
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildFadesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FabSectionLabel('FADES'),
        FabMiniSlider(
          label: 'IN',
          value: _fadeInMs / 100.0,
          display: '${_fadeInMs.toStringAsFixed(0)}ms',
          activeColor: FabFilterColors.green,
          labelWidth: 26,
          displayWidth: 34,
          onChanged: (v) => setState(() => _fadeInMs = (v * 100.0).clamp(0.0, 100.0)),
        ),
        const SizedBox(height: 2),
        FabMiniSlider(
          label: 'OUT',
          value: _fadeOutMs / 100.0,
          display: '${_fadeOutMs.toStringAsFixed(0)}ms',
          activeColor: FabFilterColors.green,
          labelWidth: 26,
          displayWidth: 34,
          onChanged: (v) => setState(() => _fadeOutMs = (v * 100.0).clamp(0.0, 100.0)),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // EXPERT SECTION — extra options visible in expert mode
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildExpertSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FabSectionLabel('CLIP INFO'),
        if (_clipSampleRate > 0 && _clipTotalFrames > 0) ...[
          _buildInfoRow('Sample Rate', '$_clipSampleRate Hz'),
          _buildInfoRow('Total Frames', '$_clipTotalFrames'),
          _buildInfoRow('Duration', _formatDuration(_clipTotalFrames / _clipSampleRate)),
        ] else
          Text('No clip data available',
              style: FabFilterText.paramLabel.copyWith(color: FabFilterColors.textDisabled)),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: FabFilterText.paramLabel),
          ),
          Text(value, style: FabFilterText.paramValue(FabFilterColors.textSecondary).copyWith(fontSize: 9)),
        ],
      ),
    );
  }

  String _formatDuration(double seconds) {
    if (seconds < 1) return '${(seconds * 1000).toStringAsFixed(0)} ms';
    if (seconds < 60) return '${seconds.toStringAsFixed(2)}s';
    final mins = (seconds / 60).floor();
    final secs = seconds - mins * 60;
    return '${mins}m ${secs.toStringAsFixed(1)}s';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // REGION DISPLAY — timeline + list
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildRegionDisplay() {
    if (_detectedRegions.isEmpty && !_isAnalyzing) return const SizedBox.shrink();

    if (_isAnalyzing) {
      return Container(
        height: 40,
        decoration: FabFilterDecorations.display(),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FabFilterColors.cyan,
                ),
              ),
              const SizedBox(width: 8),
              Text('Analyzing...', style: FabFilterText.paramLabel.copyWith(color: FabFilterColors.cyan)),
            ],
          ),
        ),
      );
    }

    final totalDuration = _detectedRegions.isEmpty
        ? 10.0
        : _detectedRegions.last.endTime + 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const FabSectionLabel('DETECTED REGIONS'),
            const Spacer(),
            Text('${_detectedRegions.length} found',
                style: FabFilterText.paramLabel.copyWith(color: FabFilterColors.cyan)),
          ],
        ),
        const SizedBox(height: 4),
        // Visual timeline
        Container(
          height: 36,
          decoration: FabFilterDecorations.display(),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: _FabSilenceRegionPainter(
              regions: _detectedRegions,
              totalDuration: totalDuration,
              previewMode: _previewMode,
            ),
            size: const Size(double.infinity, 36),
          ),
        ),
        const SizedBox(height: 6),
        // Region list (compact, max 6 visible)
        ...(_detectedRegions.length > 6
                ? _detectedRegions.take(6).toList()
                : _detectedRegions)
            .map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Container(
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: FabFilterColors.bgMid,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: FabFilterColors.cyan.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${r.startTime.toStringAsFixed(2)}s \u2014 ${r.endTime.toStringAsFixed(2)}s',
                          style: FabFilterText.paramLabel.copyWith(
                              fontSize: 8, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                        const Spacer(),
                        Text('${r.duration.toStringAsFixed(0)}ms',
                            style: FabFilterText.paramLabel.copyWith(
                                fontSize: 8, color: FabFilterColors.textDisabled)),
                      ],
                    ),
                  ),
                )),
        if (_detectedRegions.length > 6)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('\u2026 and ${_detectedRegions.length - 6} more',
                style: FabFilterText.paramLabel.copyWith(color: FabFilterColors.textDisabled)),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // ACTIONS — Detect + Strip buttons
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(child: _buildActionButton(
          label: _isAnalyzing ? 'ANALYZING\u2026' : 'DETECT',
          icon: _isAnalyzing ? Icons.hourglass_top : Icons.search,
          color: FabFilterColors.cyan,
          filled: true,
          enabled: !_isAnalyzing,
          onTap: _detectSilence,
        )),
        const SizedBox(width: 6),
        Expanded(child: _buildActionButton(
          label: 'STRIP',
          icon: Icons.content_cut,
          color: FabFilterColors.orange,
          filled: false,
          enabled: _detectedRegions.isNotEmpty,
          onTap: _applySilenceStrip,
        )),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool filled,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final effectiveColor = enabled ? color : FabFilterColors.textDisabled;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: filled && enabled
              ? effectiveColor.withValues(alpha: 0.2)
              : FabFilterColors.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: effectiveColor.withValues(alpha: enabled ? 0.6 : 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: effectiveColor),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              color: effectiveColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            )),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DETECTION — Real FFI via transient detection + clip metadata
  // ═══════════════════════════════════════════════════════════════════════

  void _detectSilence() {
    if (widget.selectedTrackId == null) return;
    setState(() {
      _isAnalyzing = true;
      _detectedRegions = [];
    });

    _service.setThreshold(_thresholdDb);
    _service.setMinDuration(_minDurationMs);

    try {
      final ffi = NativeFFI.instance;
      // Resolve track index → clip ID (IMPORTED_AUDIO is keyed by ClipId, not track index)
      final clipId = ffi.getFirstClipId(widget.selectedTrackId!);
      if (clipId == 0) {
        debugPrint('[StripSilence] No clip found for track ${widget.selectedTrackId}');
        setState(() => _isAnalyzing = false);
        return;
      }
      final sampleRate = ffi.getClipSampleRate(clipId);
      final totalFrames = ffi.getClipTotalFrames(clipId);

      if (sampleRate > 0 && totalFrames > 0) {
        _clipSampleRate = sampleRate;
        _clipTotalFrames = totalFrames;

        // Use transient detection as a proxy: areas WITHOUT transients are likely silent.
        // Very low sensitivity catches only significant energy bursts.
        final transients = ffi.detectClipTransients(
          clipId,
          sensitivity: 0.1,
          algorithm: 0,
          minGapMs: _minDurationMs * 0.5,
          maxCount: 500,
        );

        final totalSeconds = totalFrames / sampleRate;
        _detectedRegions = _deriveSilentRegionsFromTransients(
          transients,
          totalSeconds,
          sampleRate.toDouble(),
        );
      }
    } catch (e) {
      debugPrint('[StripSilence] FFI detection failed: $e');
    }

    // If FFI returned nothing (no clip loaded, or no silence found), the list stays empty.
    setState(() => _isAnalyzing = false);

    widget.onAction?.call('detectSilence', {
      'trackId': widget.selectedTrackId,
      'threshold': _thresholdDb,
      'minDuration': _minDurationMs,
      'regions': _detectedRegions.length,
    });
  }

  /// Derive silent regions by inverting transient-active regions.
  /// Transient positions mark where audio IS active; gaps between them are silence candidates.
  List<SilentRegion> _deriveSilentRegionsFromTransients(
    List<({int position, double strength})> transients,
    double totalSeconds,
    double sampleRate,
  ) {
    if (transients.isEmpty) {
      // No transients at all — entire clip is below detection threshold
      if (totalSeconds > _minDurationMs / 1000.0) {
        return [SilentRegion(startTime: 0.0, endTime: totalSeconds)];
      }
      return [];
    }

    final regions = <SilentRegion>[];
    final minGapSeconds = _minDurationMs / 1000.0;

    // Convert threshold from dB to a strength comparison value.
    // Transient strengths are 0.0–1.0 normalized; we use an energy-based threshold.
    final thresholdLinear = _thresholdDb <= -96.0 ? 0.0 : math.pow(10, _thresholdDb / 20.0);

    // Filter transients by strength relative to our threshold
    final activePositions = transients
        .where((t) => t.strength > thresholdLinear * 0.5)
        .map((t) => t.position / sampleRate)
        .toList();

    if (activePositions.isEmpty) {
      if (totalSeconds > minGapSeconds) {
        return [SilentRegion(startTime: 0.0, endTime: totalSeconds)];
      }
      return [];
    }

    // Leading silence (before first active point)
    final firstActive = activePositions.first;
    if (firstActive > minGapSeconds) {
      regions.add(SilentRegion(startTime: 0.0, endTime: firstActive));
    }

    // Gaps between active points
    for (int i = 0; i < activePositions.length - 1; i++) {
      // Each transient represents a brief burst; estimate ~50ms of active audio around it
      final gapStart = activePositions[i] + 0.05;
      final gapEnd = activePositions[i + 1] - 0.05;
      if (gapEnd - gapStart >= minGapSeconds) {
        regions.add(SilentRegion(startTime: gapStart, endTime: gapEnd));
      }
    }

    // Trailing silence (after last active point)
    final lastActive = activePositions.last + 0.05;
    if (totalSeconds - lastActive > minGapSeconds) {
      regions.add(SilentRegion(startTime: lastActive, endTime: totalSeconds));
    }

    return regions;
  }

  void _applySilenceStrip() {
    widget.onAction?.call('stripSilence', {
      'trackId': widget.selectedTrackId,
      'regions': _detectedRegions
          .map((r) => {
                'start': r.startTime,
                'end': r.endTime,
              })
          .toList(),
      'padBefore': _padBeforeMs,
      'padAfter': _padAfterMs,
      'fadeIn': _fadeInMs,
      'fadeOut': _fadeOutMs,
      'preview': _previewMode,
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — FabFilter-styled silence region visualization
// ═══════════════════════════════════════════════════════════════════════════

class _FabSilenceRegionPainter extends CustomPainter {
  final List<SilentRegion> regions;
  final double totalDuration;
  final bool previewMode;

  _FabSilenceRegionPainter({
    required this.regions,
    required this.totalDuration,
    required this.previewMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (totalDuration <= 0) return;

    // Background: audio waveform area (subtle fill)
    final bgPaint = Paint()..color = FabFilterColors.bgVoid;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Audio regions (between silence): subtle indication
    final audioPaint = Paint()
      ..color = FabFilterColors.cyan.withValues(alpha: 0.06);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), audioPaint);

    // Grid lines (time markers)
    final gridPaint = Paint()
      ..color = FabFilterColors.grid.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    final gridInterval = _calculateGridInterval(totalDuration, size.width);
    if (gridInterval > 0) {
      for (double t = gridInterval; t < totalDuration; t += gridInterval) {
        final x = (t / totalDuration) * size.width;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
    }

    // Silent regions
    for (final region in regions) {
      final x1 = (region.startTime / totalDuration) * size.width;
      final x2 = (region.endTime / totalDuration) * size.width;
      final regionRect = Rect.fromLTRB(x1, 0, x2, size.height);

      // Fill
      canvas.drawRect(
        regionRect,
        Paint()
          ..color = previewMode
              ? FabFilterColors.red.withValues(alpha: 0.15)
              : FabFilterColors.cyan.withValues(alpha: 0.15),
      );

      // Top/bottom edge highlight
      final edgeColor = previewMode
          ? FabFilterColors.red.withValues(alpha: 0.4)
          : FabFilterColors.cyan.withValues(alpha: 0.4);
      final edgePaint = Paint()
        ..color = edgeColor
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x1, 0), Offset(x1, size.height), edgePaint);
      canvas.drawLine(Offset(x2, 0), Offset(x2, size.height), edgePaint);

      // Crosshatch pattern for preview mode (indicates removal)
      if (previewMode) {
        final hatchPaint = Paint()
          ..color = FabFilterColors.red.withValues(alpha: 0.12)
          ..strokeWidth = 0.5;
        for (double hx = x1; hx < x2; hx += 4) {
          canvas.drawLine(Offset(hx, size.height), Offset(hx + size.height, 0), hatchPaint);
        }
      }
    }
  }

  double _calculateGridInterval(double duration, double width) {
    if (duration <= 0 || width <= 0) return 0;
    // Target ~40px per grid line
    final pixelsPerSecond = width / duration;
    final targetInterval = 40.0 / pixelsPerSecond;
    // Snap to nice values: 0.1, 0.25, 0.5, 1, 2, 5, 10...
    const niceValues = [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0];
    for (final v in niceValues) {
      if (v >= targetInterval) return v;
    }
    return 60.0;
  }

  @override
  bool shouldRepaint(covariant _FabSilenceRegionPainter old) =>
      old.regions.length != regions.length ||
      old.totalDuration != totalDuration ||
      old.previewMode != previewMode;
}
