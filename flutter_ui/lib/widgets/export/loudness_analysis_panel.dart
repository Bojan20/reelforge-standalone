/// Loudness Analysis Panel — Pre-Export Analysis UI
///
/// P3.7: Loudness analysis pre-export.
///
/// Features:
/// - Real-time LUFS meters (integrated, short-term, momentary)
/// - True peak display with clip indicator
/// - Target presets with compliance status
/// - Loudness range visualization
/// - Recommended gain calculation
library;

import 'package:flutter/material.dart';

import '../../services/loudness_analysis_service.dart';
import '../lower_zone/lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// LOUDNESS ANALYSIS PANEL
// ═══════════════════════════════════════════════════════════════════════════════

/// Complete loudness analysis panel for pre-export workflow
class LoudnessAnalysisPanel extends StatefulWidget {
  final Color accentColor;
  final LoudnessResult? result;
  final bool isAnalyzing;
  final double progress;
  final VoidCallback? onAnalyze;
  final void Function(LoudnessTarget)? onTargetChanged;
  final LoudnessTarget initialTarget;

  const LoudnessAnalysisPanel({
    super.key,
    this.accentColor = LowerZoneColors.dawAccent,
    this.result,
    this.isAnalyzing = false,
    this.progress = 0.0,
    this.onAnalyze,
    this.onTargetChanged,
    this.initialTarget = LoudnessTarget.streaming,
  });

  @override
  State<LoudnessAnalysisPanel> createState() => _LoudnessAnalysisPanelState();
}

class _LoudnessAnalysisPanelState extends State<LoudnessAnalysisPanel> {
  late LoudnessTarget _selectedTarget;

  @override
  void initState() {
    super.initState();
    _selectedTarget = widget.initialTarget;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Meters
                Expanded(
                  flex: 3,
                  child: _buildMeters(),
                ),
                const SizedBox(width: 12),
                // Center: Target & Compliance
                Expanded(
                  flex: 2,
                  child: _buildTargetSection(),
                ),
                const SizedBox(width: 12),
                // Right: Actions
                SizedBox(
                  width: 100,
                  child: _buildActions(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.graphic_eq, size: 16, color: widget.accentColor),
        const SizedBox(width: 8),
        Text(
          'LOUDNESS ANALYSIS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: widget.accentColor,
            letterSpacing: 1.0,
          ),
        ),
        const Spacer(),
        if (widget.result != null) ...[
          _buildStatusBadge(),
        ],
      ],
    );
  }

  Widget _buildStatusBadge() {
    final compliance = _selectedTarget.checkCompliance(widget.result!);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: compliance.isCompliant
            ? LowerZoneColors.success.withValues(alpha: 0.2)
            : LowerZoneColors.error.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: compliance.isCompliant ? LowerZoneColors.success : LowerZoneColors.error,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            compliance.isCompliant ? Icons.check_circle : Icons.warning,
            size: 12,
            color: compliance.isCompliant ? LowerZoneColors.success : LowerZoneColors.error,
          ),
          const SizedBox(width: 4),
          Text(
            compliance.isCompliant ? 'COMPLIANT' : 'NON-COMPLIANT',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: compliance.isCompliant ? LowerZoneColors.success : LowerZoneColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeters() {
    if (widget.isAnalyzing) {
      return _buildAnalyzingState();
    }

    if (widget.result == null || !widget.result!.isValid) {
      return _buildEmptyState();
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LUFS Meters
          Row(
            children: [
              Expanded(child: _buildLufsMeter(
                'Integrated',
                widget.result!.integratedLufs,
                _selectedTarget.targetLufs,
                isPrimary: true,
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildLufsMeter(
                'Short-term',
                widget.result!.shortTermLufs,
                null,
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildLufsMeter(
                'Momentary',
                widget.result!.momentaryLufs,
                null,
              )),
            ],
          ),
          const SizedBox(height: 12),
          // Peak Meters
          Row(
            children: [
              Expanded(child: _buildPeakMeter(
                'True Peak',
                widget.result!.truePeak,
                _selectedTarget.truePeakLimit,
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildPeakMeter(
                'Sample Peak',
                widget.result!.samplePeak,
                0.0,
              )),
              const SizedBox(width: 8),
              Expanded(child: _buildLraMeter()),
            ],
          ),
          const Spacer(),
          // Duration
          Row(
            children: [
              const Icon(Icons.timer, size: 12, color: LowerZoneColors.textMuted),
              const SizedBox(width: 4),
              Text(
                'Duration: ${_formatDuration(widget.result!.duration)}',
                style: const TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzingState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: widget.accentColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: widget.progress,
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation(widget.accentColor),
              backgroundColor: LowerZoneColors.bgMid,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Analyzing audio...',
            style: TextStyle(fontSize: 11, color: widget.accentColor),
          ),
          const SizedBox(height: 4),
          Text(
            '${(widget.progress * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: widget.accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.graphic_eq,
            size: 48,
            color: LowerZoneColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          const Text(
            'No Analysis',
            style: TextStyle(fontSize: 11, color: LowerZoneColors.textMuted),
          ),
          const SizedBox(height: 4),
          const Text(
            'Click Analyze to measure loudness',
            style: TextStyle(fontSize: 9, color: LowerZoneColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLufsMeter(String label, double value, double? target, {bool isPrimary = false}) {
    final normalizedValue = _normalizeLufs(value);
    final normalizedTarget = target != null ? _normalizeLufs(target) : null;
    final isAtTarget = target != null && (value - target).abs() <= 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                color: isPrimary ? widget.accentColor : LowerZoneColors.textMuted,
                fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const Spacer(),
            Text(
              LoudnessResult.formatLufs(value),
              style: TextStyle(
                fontSize: isPrimary ? 11 : 9,
                color: isPrimary ? widget.accentColor : LowerZoneColors.textPrimary,
                fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: isPrimary ? 16 : 12,
          child: CustomPaint(
            size: const Size(double.infinity, 16),
            painter: _LufsMeterPainter(
              value: normalizedValue,
              target: normalizedTarget,
              accentColor: widget.accentColor,
              isAtTarget: isAtTarget,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeakMeter(String label, double value, double limit) {
    final isClipping = value > limit;
    final normalizedValue = _normalizePeak(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
            const Spacer(),
            Text(
              LoudnessResult.formatPeak(value),
              style: TextStyle(
                fontSize: 9,
                color: isClipping ? LowerZoneColors.error : LowerZoneColors.textPrimary,
                fontWeight: isClipping ? FontWeight.bold : FontWeight.normal,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 12,
          child: CustomPaint(
            size: const Size(double.infinity, 12),
            painter: _PeakMeterPainter(
              value: normalizedValue,
              isClipping: isClipping,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLraMeter() {
    final lra = widget.result!.loudnessRange;
    final normalizedLra = (lra / 20.0).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('LRA', style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
            const Spacer(),
            Text(
              LoudnessResult.formatLra(lra),
              style: const TextStyle(
                fontSize: 9,
                color: LowerZoneColors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: LowerZoneColors.bgMid,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: normalizedLra,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade400, Colors.teal.shade700],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTargetSection() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: LowerZoneColors.bgDeepest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: LowerZoneColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TARGET',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: widget.accentColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          // Target selector
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: LoudnessTarget.values
                .where((t) => t != LoudnessTarget.custom)
                .map((t) => _buildTargetChip(t))
                .toList(),
          ),
          const SizedBox(height: 12),
          // Target info
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgMid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedTarget.name,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: widget.accentColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _selectedTarget.description,
                  style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
                ),
                const SizedBox(height: 8),
                _buildTargetRow('Target LUFS', '${_selectedTarget.targetLufs.toStringAsFixed(1)} LUFS'),
                _buildTargetRow('True Peak Limit', '${_selectedTarget.truePeakLimit.toStringAsFixed(1)} dBTP'),
              ],
            ),
          ),
          const Spacer(),
          // Compliance details
          if (widget.result != null && widget.result!.isValid) ...[
            _buildComplianceDetails(),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetChip(LoudnessTarget target) {
    final isSelected = _selectedTarget == target;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedTarget = target);
        widget.onTargetChanged?.call(target);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? widget.accentColor.withValues(alpha: 0.2) : null,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? widget.accentColor : LowerZoneColors.border,
          ),
        ),
        child: Text(
          target.name,
          style: TextStyle(
            fontSize: 9,
            color: isSelected ? widget.accentColor : LowerZoneColors.textMuted,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTargetRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 9,
              color: LowerZoneColors.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplianceDetails() {
    final compliance = _selectedTarget.checkCompliance(widget.result!);
    final service = LoudnessAnalysisService.instance;
    final recommendedGain = service.getRecommendedGain(widget.result!, _selectedTarget);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: compliance.isCompliant
            ? LowerZoneColors.success.withValues(alpha: 0.1)
            : LowerZoneColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: compliance.isCompliant ? LowerZoneColors.success : LowerZoneColors.warning,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildComplianceRow('LUFS', compliance.lufsStatus, compliance.lufsCompliant),
          _buildComplianceRow('Peak', compliance.peakStatus, compliance.peakCompliant),
          if (!compliance.isCompliant) ...[
            const Divider(height: 12, color: LowerZoneColors.border),
            Row(
              children: [
                const Text(
                  'Recommended Gain:',
                  style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
                ),
                const Spacer(),
                Text(
                  '${recommendedGain >= 0 ? '+' : ''}${recommendedGain.toStringAsFixed(1)} dB',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: widget.accentColor,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComplianceRow(String label, String status, bool isOk) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle : Icons.error,
            size: 10,
            color: isOk ? LowerZoneColors.success : LowerZoneColors.warning,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
          ),
          const Spacer(),
          Text(
            status,
            style: TextStyle(
              fontSize: 9,
              color: isOk ? LowerZoneColors.success : LowerZoneColors.warning,
              fontWeight: isOk ? FontWeight.normal : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        // Analyze button
        Expanded(
          child: GestureDetector(
            onTap: widget.isAnalyzing ? null : widget.onAnalyze,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: widget.isAnalyzing
                      ? [LowerZoneColors.bgMid, LowerZoneColors.bgDeepest]
                      : [
                          widget.accentColor.withValues(alpha: 0.2),
                          widget.accentColor.withValues(alpha: 0.1),
                        ],
                ),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: widget.isAnalyzing ? LowerZoneColors.border : widget.accentColor,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.analytics,
                    size: 32,
                    color: widget.isAnalyzing ? LowerZoneColors.textMuted : widget.accentColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isAnalyzing ? 'ANALYZING...' : 'ANALYZE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: widget.isAnalyzing ? LowerZoneColors.textMuted : widget.accentColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _normalizeLufs(double lufs) {
    // Normalize LUFS to 0-1 range (-40 to 0 LUFS)
    return ((lufs + 40) / 40).clamp(0.0, 1.0);
  }

  double _normalizePeak(double peak) {
    // Normalize peak to 0-1 range (-40 to 0 dB)
    return ((peak + 40) / 40).clamp(0.0, 1.0);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final ms = d.inMilliseconds % 1000;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${(ms ~/ 10).toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════════════════════════

class _LufsMeterPainter extends CustomPainter {
  final double value;
  final double? target;
  final Color accentColor;
  final bool isAtTarget;

  _LufsMeterPainter({
    required this.value,
    required this.target,
    required this.accentColor,
    required this.isAtTarget,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = LowerZoneColors.bgMid,
    );

    // Value bar
    final valueRect = Rect.fromLTWH(0, 0, size.width * value, size.height);
    final gradient = LinearGradient(
      colors: isAtTarget
          ? [Colors.green.shade400, Colors.green.shade600]
          : [accentColor, accentColor.withValues(alpha: 0.7)],
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(valueRect, const Radius.circular(2)),
      Paint()..shader = gradient.createShader(valueRect),
    );

    // Target line
    if (target != null) {
      final targetX = size.width * target!;
      canvas.drawLine(
        Offset(targetX, 0),
        Offset(targetX, size.height),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LufsMeterPainter oldDelegate) {
    return value != oldDelegate.value ||
        target != oldDelegate.target ||
        isAtTarget != oldDelegate.isAtTarget;
  }
}

class _PeakMeterPainter extends CustomPainter {
  final double value;
  final bool isClipping;

  _PeakMeterPainter({
    required this.value,
    required this.isClipping,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = LowerZoneColors.bgMid,
    );

    // Value bar with gradient (green -> yellow -> red)
    final valueRect = Rect.fromLTWH(0, 0, size.width * value, size.height);
    final gradient = LinearGradient(
      colors: isClipping
          ? [Colors.red.shade400, Colors.red.shade700]
          : [Colors.green.shade400, Colors.yellow.shade400, Colors.orange.shade400],
      stops: isClipping ? null : const [0.0, 0.7, 1.0],
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(valueRect, const Radius.circular(2)),
      Paint()..shader = gradient.createShader(rect),
    );

    // Clip indicator
    if (isClipping) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - 4, 0, 4, size.height),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.red,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PeakMeterPainter oldDelegate) {
    return value != oldDelegate.value || isClipping != oldDelegate.isClipping;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// COMPACT LOUDNESS BADGE
// ═══════════════════════════════════════════════════════════════════════════════

/// Compact badge showing loudness status for lists/panels
class LoudnessBadge extends StatelessWidget {
  final LoudnessResult? result;
  final LoudnessTarget target;
  final bool compact;

  const LoudnessBadge({
    super.key,
    this.result,
    this.target = LoudnessTarget.streaming,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (result == null || !result!.isValid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgMid,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'N/A',
          style: TextStyle(fontSize: 8, color: LowerZoneColors.textMuted),
        ),
      );
    }

    final compliance = target.checkCompliance(result!);

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: compliance.isCompliant
              ? LowerZoneColors.success.withValues(alpha: 0.2)
              : LowerZoneColors.warning.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${result!.integratedLufs.toStringAsFixed(1)}',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: compliance.isCompliant ? LowerZoneColors.success : LowerZoneColors.warning,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: compliance.isCompliant
            ? LowerZoneColors.success.withValues(alpha: 0.2)
            : LowerZoneColors.warning.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: compliance.isCompliant ? LowerZoneColors.success : LowerZoneColors.warning,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            compliance.isCompliant ? Icons.check : Icons.warning,
            size: 10,
            color: compliance.isCompliant ? LowerZoneColors.success : LowerZoneColors.warning,
          ),
          const SizedBox(width: 4),
          Text(
            LoudnessResult.formatLufs(result!.integratedLufs),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: compliance.isCompliant ? LowerZoneColors.success : LowerZoneColors.warning,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '/ ${result!.truePeak.toStringAsFixed(1)} dBTP',
            style: const TextStyle(
              fontSize: 8,
              color: LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
