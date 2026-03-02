// SmartTempo Panel — Logic Pro X style auto-detect BPM
// FFI-based tempo detection with confidence scoring, alternatives, downbeats

import 'package:flutter/material.dart';
import '../../../../src/rust/native_ffi.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_knob.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class SmartTempoPanel extends StatefulWidget {
  final int? selectedTrackId;
  final double currentTempo;
  final void Function(double newTempo)? onTempoChange;
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const SmartTempoPanel({
    super.key,
    this.selectedTrackId,
    this.currentTempo = 120.0,
    this.onTempoChange,
    this.onAction,
  });

  @override
  State<SmartTempoPanel> createState() => _SmartTempoPanelState();
}

class _SmartTempoPanelState extends State<SmartTempoPanel> {
  // State
  double _minBpm = 60.0;
  double _maxBpm = 200.0;
  bool _isAnalyzing = false;
  bool _isStateB = false;
  bool _bypassed = false;
  bool _showExpert = false;
  TempoDetectionResult? _result;
  int _selectedAltIndex = -1; // -1 = primary, 0+ = alternative

  // Detection mode
  int _modeIndex = 0; // 0=Automatic, 1=AdaptProject, 2=KeepProject
  static const _modeLabels = ['AUTO', 'ADAPT', 'KEEP'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: FabFilterColors.bgDeep),
      child: Column(
        children: [
          _buildHeader(),
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
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return FabCompactHeader(
      title: 'FF TEMPO',
      accentColor: FabFilterColors.cyan,
      isStateB: _isStateB,
      onToggleAB: () => setState(() => _isStateB = !_isStateB),
      bypassed: _bypassed,
      onToggleBypass: () => setState(() => _bypassed = !_bypassed),
      showExpert: _showExpert,
      onToggleExpert: () => setState(() => _showExpert = !_showExpert),
      onClose: () => widget.onAction?.call('close', null),
      statusWidget: _result != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: _confidenceColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: _confidenceColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                '${(_result!.confidence * 100).toInt()}%',
                style: FabFilterText.paramValue(_confidenceColor).copyWith(fontSize: 9),
              ),
            )
          : null,
    );
  }

  Color get _confidenceColor {
    if (_result == null) return FabFilterColors.textTertiary;
    if (_result!.confidence >= 0.8) return FabFilterColors.green;
    if (_result!.confidence >= 0.5) return FabFilterColors.yellow;
    return FabFilterColors.red;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NO SELECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNoSelection() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speed, size: 28,
              color: FabFilterColors.textTertiary.withValues(alpha: 0.3)),
          const SizedBox(height: 6),
          Text('Select a clip for Tempo Detection',
              style: FabFilterText.paramLabel
                  .copyWith(color: FabFilterColors.textTertiary)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          _buildControlsRow(),
          const SizedBox(height: 8),
          Expanded(child: _buildResultDisplay()),
          const SizedBox(height: 6),
          _buildActionRow(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTROLS ROW — Range knobs + Mode + Detect button
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildControlsRow() {
    return SizedBox(
      height: 86,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Min BPM knob
          FabFilterKnob(
            value: (_minBpm - 30) / 170, // normalize 30-200 to 0-1
            label: 'MIN',
            display: '${_minBpm.toInt()}',
            color: FabFilterColors.cyan,
            size: 56,
            defaultValue: (60 - 30) / 170,
            onChanged: (v) {
              final bpm = (30 + v * 170).roundToDouble();
              if (bpm < _maxBpm - 10) {
                setState(() => _minBpm = bpm);
              }
            },
          ),
          const SizedBox(width: 8),
          // Max BPM knob
          FabFilterKnob(
            value: (_maxBpm - 30) / 270, // normalize 30-300 to 0-1
            label: 'MAX',
            display: '${_maxBpm.toInt()}',
            color: FabFilterColors.cyan,
            size: 56,
            defaultValue: (200 - 30) / 270,
            onChanged: (v) {
              final bpm = (30 + v * 270).roundToDouble();
              if (bpm > _minBpm + 10) {
                setState(() => _maxBpm = bpm);
              }
            },
          ),
          const SizedBox(width: 12),
          // Mode selector + detect button
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FabEnumSelector(
                  label: 'MODE',
                  value: _modeIndex,
                  options: _modeLabels,
                  onChanged: (v) => setState(() => _modeIndex = v),
                  color: FabFilterColors.cyan,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Current project tempo
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: FabFilterColors.bgMid,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: FabFilterColors.borderSubtle),
                      ),
                      child: Text(
                        '${widget.currentTempo.toStringAsFixed(1)} BPM',
                        style: FabFilterText.paramValue(FabFilterColors.textSecondary).copyWith(fontSize: 10),
                      ),
                    ),
                    const Spacer(),
                    // DETECT button
                    _buildDetectButton(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectButton() {
    return GestureDetector(
      onTap: _isAnalyzing ? null : _runDetection,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _isAnalyzing
              ? FabFilterColors.cyan.withValues(alpha: 0.3)
              : FabFilterColors.cyan.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _isAnalyzing
                ? FabFilterColors.cyan.withValues(alpha: 0.6)
                : FabFilterColors.cyan.withValues(alpha: 0.5),
          ),
        ),
        child: _isAnalyzing
            ? SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(FabFilterColors.cyan),
                ),
              )
            : Text(
                'DETECT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: FabFilterColors.cyan,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESULT DISPLAY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildResultDisplay() {
    if (_result == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed, size: 48,
                color: FabFilterColors.cyan.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            Text('Press DETECT to analyze audio tempo',
                style: FabFilterText.paramLabel
                    .copyWith(color: FabFilterColors.textTertiary)),
          ],
        ),
      );
    }

    final r = _result!;
    final displayBpm = _selectedAltIndex >= 0 && _selectedAltIndex < r.alternatives.length
        ? r.alternatives[_selectedAltIndex]
        : r.bpm;

    return Column(
      children: [
        // Big BPM display
        GestureDetector(
          onTap: () => setState(() => _selectedAltIndex = -1),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: FabFilterColors.bgMid,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _confidenceColor.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                Text(
                  displayBpm.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w300,
                    color: _confidenceColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'BPM',
                  style: TextStyle(
                    fontSize: 11,
                    color: FabFilterColors.textTertiary,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Confidence + Stability + Alternatives row
        Row(
          children: [
            // Confidence meter
            _buildInfoBadge(
              'CONFIDENCE',
              '${(r.confidence * 100).toInt()}%',
              _confidenceColor,
            ),
            const SizedBox(width: 6),
            // Stability
            _buildInfoBadge(
              'STABILITY',
              r.stable ? 'STABLE' : 'VARIABLE',
              r.stable ? FabFilterColors.green : FabFilterColors.yellow,
            ),
            const SizedBox(width: 6),
            // Downbeats
            _buildInfoBadge(
              'DOWNBEATS',
              '${r.downbeats.length}',
              FabFilterColors.cyan,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Alternative tempos
        if (r.alternatives.isNotEmpty)
          Row(
            children: [
              Text('ALT: ', style: FabFilterText.paramLabel.copyWith(fontSize: 9)),
              ...r.alternatives.asMap().entries.map((entry) {
                final isSelected = _selectedAltIndex == entry.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedAltIndex = isSelected ? -1 : entry.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? FabFilterColors.cyan.withValues(alpha: 0.2)
                            : FabFilterColors.bgMid,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: isSelected
                              ? FabFilterColors.cyan.withValues(alpha: 0.6)
                              : FabFilterColors.borderSubtle,
                        ),
                      ),
                      child: Text(
                        '${entry.value.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelected ? FabFilterColors.cyan : FabFilterColors.textSecondary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
      ],
    );
  }

  Widget _buildInfoBadge(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 8, color: FabFilterColors.textTertiary, letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION ROW — Apply to project + Re-detect
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionRow() {
    final hasResult = _result != null && _result!.bpm > 0;
    final displayBpm = hasResult
        ? (_selectedAltIndex >= 0 && _selectedAltIndex < _result!.alternatives.length
            ? _result!.alternatives[_selectedAltIndex]
            : _result!.bpm)
        : 0.0;

    return Row(
      children: [
        // APPLY button — set project tempo to detected
        Expanded(
          child: GestureDetector(
            onTap: hasResult ? () => _applyTempo(displayBpm) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: hasResult
                    ? FabFilterColors.green.withValues(alpha: 0.15)
                    : FabFilterColors.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: hasResult
                      ? FabFilterColors.green.withValues(alpha: 0.5)
                      : FabFilterColors.borderSubtle,
                ),
              ),
              child: Text(
                hasResult ? 'APPLY ${displayBpm.toStringAsFixed(1)} BPM' : 'APPLY',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: hasResult ? FabFilterColors.green : FabFilterColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // HALF / DOUBLE tempo quick buttons
        if (hasResult) ...[
          _buildQuickTempoButton('÷2', displayBpm / 2),
          const SizedBox(width: 4),
          _buildQuickTempoButton('×2', displayBpm * 2),
        ],
      ],
    );
  }

  Widget _buildQuickTempoButton(String label, double bpm) {
    return GestureDetector(
      onTap: () => _applyTempo(bpm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: FabFilterColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FabFilterColors.borderSubtle),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FabFilterColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DETECTION LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _runDetection() async {
    final trackId = widget.selectedTrackId;
    if (trackId == null) return;

    setState(() {
      _isAnalyzing = true;
      _result = null;
      _selectedAltIndex = -1;
    });

    // Run FFI on isolate-friendly delay to let UI update
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final ffi = NativeFFI.instance;
      // Get first clip ID for this track
      final clipId = ffi.getFirstClipId(trackId);
      if (clipId <= 0) {
        setState(() => _isAnalyzing = false);
        return;
      }

      final result = ffi.detectClipTempo(
        clipId,
        minBpm: _minBpm,
        maxBpm: _maxBpm,
      );

      setState(() {
        _result = result;
        _isAnalyzing = false;
      });

      // Auto-apply in Automatic mode with high confidence
      if (_modeIndex == 0 && result.confidence >= 0.7 && result.bpm > 0) {
        _applyTempo(result.bpm);
      }
    } catch (e) {
      setState(() => _isAnalyzing = false);
    }
  }

  void _applyTempo(double bpm) {
    if (bpm <= 0) return;
    widget.onTempoChange?.call(bpm);
    widget.onAction?.call('setTempo', {'bpm': bpm});
  }
}
