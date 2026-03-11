/// Loudness Report Panel — DELIVER tab
///
/// #22: Interactive loudness report with dry run analysis.
///
/// Features:
/// - Dry run analysis (analyze without rendering)
/// - Summary cards: Integrated LUFS, True Peak, LRA, clipping
/// - Short-term LUFS mini-graph
/// - Target compliance table
/// - Generate HTML report + open in browser
library;

import 'dart:io';

import 'package:flutter/material.dart';
import '../../../../services/loudness_report_service.dart';
import '../../../../services/loudness_analysis_service.dart';
import '../../../fabfilter/fabfilter_theme.dart';
import '../../../fabfilter/fabfilter_widgets.dart';

class LoudnessReportPanel extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? params)? onAction;

  const LoudnessReportPanel({
    super.key,
    this.onAction,
  });

  @override
  State<LoudnessReportPanel> createState() => _LoudnessReportPanelState();
}

class _LoudnessReportPanelState extends State<LoudnessReportPanel> {
  final _service = LoudnessReportService.instance;
  LoudnessTarget _selectedTarget = LoudnessTarget.streaming;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          Expanded(
            child: _service.isAnalyzing
                ? _buildAnalyzingState()
                : _service.lastReport != null
                    ? _buildReportView()
                    : _buildEmptyState(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.assessment, size: 14, color: FabFilterColors.cyan),
        const SizedBox(width: 6),
        const Text(
          'LOUDNESS REPORT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: FabFilterColors.cyan,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 12),
        _buildTargetDropdown(),
        const Spacer(),
        if (_service.lastReport != null) ...[
          _buildActionButton('EXPORT HTML', Icons.open_in_browser, _exportHtml),
          const SizedBox(width: 6),
        ],
        _buildActionButton(
          _service.isAnalyzing ? 'CANCEL' : 'DRY RUN',
          _service.isAnalyzing ? Icons.stop : Icons.analytics,
          _service.isAnalyzing ? _cancelAnalysis : _startDryRun,
        ),
      ],
    );
  }

  Widget _buildTargetDropdown() {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: FabFilterColors.bgMid,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<LoudnessTarget>(
          value: _selectedTarget,
          isDense: true,
          dropdownColor: FabFilterColors.bgSurface,
          style: const TextStyle(fontSize: 10, color: FabFilterColors.textPrimary),
          items: LoudnessTarget.values
              .where((t) => t != LoudnessTarget.custom)
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text('${t.name} (${t.targetLufs.toStringAsFixed(0)} LUFS)'),
                  ))
              .toList(),
          onChanged: (t) {
            if (t != null) setState(() => _selectedTarget = t);
          },
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: FabFilterColors.cyan.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: FabFilterColors.cyan.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: FabFilterColors.cyan),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: FabFilterColors.cyan,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EMPTY STATE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assessment_outlined,
            size: 48,
            color: FabFilterColors.textMuted.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          const Text(
            'No Loudness Report',
            style: TextStyle(fontSize: 12, color: FabFilterColors.textMuted),
          ),
          const SizedBox(height: 4),
          const Text(
            'Click DRY RUN to analyze audio without rendering',
            style: TextStyle(fontSize: 9, color: FabFilterColors.textDisabled),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ANALYZING STATE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAnalyzingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: _service.progress,
              strokeWidth: 4,
              valueColor: const AlwaysStoppedAnimation(FabFilterColors.cyan),
              backgroundColor: FabFilterColors.bgMid,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Analyzing... ${(_service.progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 12, color: FabFilterColors.cyan),
          ),
          const SizedBox(height: 4),
          const Text(
            'Dry run — no audio will be rendered',
            style: TextStyle(fontSize: 9, color: FabFilterColors.textMuted),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REPORT VIEW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReportView() {
    final report = _service.lastReport!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _buildSummaryCards(report)),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Column(
            children: [
              Expanded(flex: 3, child: _buildShortTermGraph(report)),
              const SizedBox(height: 8),
              Expanded(flex: 2, child: _buildClippingSection(report)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: _buildComplianceTable(report)),
      ],
    );
  }

  Widget _buildSummaryCards(LoudnessReportData report) {
    final a = report.analysis;
    final compliance = _selectedTarget.checkCompliance(a);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FabSectionLabel('SUMMARY'),
          const SizedBox(height: 8),
          _buildMetricRow('Integrated', LoudnessResult.formatLufs(a.integratedLufs),
              _lufsColor(a.integratedLufs), true),
          _buildMetricRow('True Peak', LoudnessResult.formatPeak(a.truePeak),
              a.truePeak > -1.0 ? FabFilterColors.red : FabFilterColors.green, false),
          _buildMetricRow('Sample Peak', '${a.samplePeak.toStringAsFixed(1)} dBFS',
              a.samplePeak > -0.1 ? FabFilterColors.red : FabFilterColors.textPrimary, false),
          _buildMetricRow('LRA', LoudnessResult.formatLra(a.loudnessRange),
              FabFilterColors.blue, false),
          _buildMetricRow('Max ST', LoudnessResult.formatLufs(a.maxShortTerm),
              FabFilterColors.textSecondary, false),
          _buildMetricRow('Min ST', LoudnessResult.formatLufs(a.minShortTerm),
              FabFilterColors.textSecondary, false),
          _buildMetricRow('Duration', report.durationFormatted,
              FabFilterColors.textMuted, false),
          _buildMetricRow('Clipping', report.hasClipping ? '${report.clipCount} events' : 'None',
              report.hasClipping ? FabFilterColors.red : FabFilterColors.green, false),
          const Spacer(),
          // Compliance badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: compliance.isCompliant
                  ? FabFilterColors.green.withValues(alpha: 0.15)
                  : FabFilterColors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: compliance.isCompliant ? FabFilterColors.green : FabFilterColors.red,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      compliance.isCompliant ? Icons.check_circle : Icons.warning,
                      size: 14,
                      color: compliance.isCompliant ? FabFilterColors.green : FabFilterColors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      compliance.isCompliant ? 'COMPLIANT' : 'NON-COMPLIANT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: compliance.isCompliant ? FabFilterColors.green : FabFilterColors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_selectedTarget.name} (${_selectedTarget.targetLufs.toStringAsFixed(0)} LUFS)',
                  style: const TextStyle(fontSize: 8, color: FabFilterColors.textMuted),
                ),
                if (!compliance.lufsCompliant) ...[
                  const SizedBox(height: 2),
                  Text(
                    'LUFS: ${compliance.lufsStatus}',
                    style: const TextStyle(fontSize: 8, color: FabFilterColors.orange),
                  ),
                ],
                if (!compliance.peakCompliant) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Peak: ${compliance.peakStatus}',
                    style: const TextStyle(fontSize: 8, color: FabFilterColors.red),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, Color valueColor, bool isPrimary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isPrimary ? 10 : 9,
              color: isPrimary ? FabFilterColors.cyan : FabFilterColors.textMuted,
              fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: isPrimary ? 13 : 10,
              fontWeight: isPrimary ? FontWeight.bold : FontWeight.normal,
              color: valueColor,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHORT-TERM GRAPH
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildShortTermGraph(LoudnessReportData report) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FabSectionLabel('SHORT-TERM LUFS'),
              const Spacer(),
              Text(
                '${report.shortTermHistory.length} readings',
                style: const TextStyle(fontSize: 8, color: FabFilterColors.textDisabled),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: report.shortTermHistory.isEmpty
                ? const Center(
                    child: Text('No data', style: TextStyle(fontSize: 9, color: FabFilterColors.textMuted)),
                  )
                : CustomPaint(
                    size: Size.infinite,
                    painter: _ShortTermGraphPainter(
                      readings: report.shortTermHistory,
                      integratedLufs: report.analysis.integratedLufs,
                      targetLufs: _selectedTarget.targetLufs,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLIPPING SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildClippingSection(LoudnessReportData report) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: report.hasClipping
              ? FabFilterColors.red.withValues(alpha: 0.5)
              : FabFilterColors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                report.hasClipping ? Icons.warning : Icons.check_circle,
                size: 12,
                color: report.hasClipping ? FabFilterColors.red : FabFilterColors.green,
              ),
              const SizedBox(width: 4),
              FabSectionLabel(
                report.hasClipping
                    ? 'CLIPPING: ${report.clipCount} EVENTS'
                    : 'NO CLIPPING',
              ),
            ],
          ),
          if (report.hasClipping) ...[
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: report.clipEvents.length > 20 ? 20 : report.clipEvents.length,
                itemBuilder: (_, i) {
                  final e = report.clipEvents[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 60,
                          child: Text(
                            _formatTime(e.timeSec),
                            style: const TextStyle(
                              fontSize: 9,
                              color: FabFilterColors.textSecondary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 50,
                          child: Text(
                            '${e.peakDb.toStringAsFixed(1)} dB',
                            style: const TextStyle(
                              fontSize: 9,
                              color: FabFilterColors.red,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        Text(
                          e.channel,
                          style: const TextStyle(fontSize: 9, color: FabFilterColors.textMuted),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (report.clipCount > 20)
              Text(
                '... +${report.clipCount - 20} more (see HTML report)',
                style: const TextStyle(fontSize: 8, color: FabFilterColors.textDisabled),
              ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPLIANCE TABLE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildComplianceTable(LoudnessReportData report) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FabFilterColors.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FabFilterColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FabSectionLabel('TARGET COMPLIANCE'),
          const SizedBox(height: 8),
          // Header row
          Row(
            children: [
              Expanded(flex: 3, child: Text('Target', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: FabFilterColors.cyan))),
              Expanded(flex: 2, child: Text('LUFS', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: FabFilterColors.cyan))),
              SizedBox(width: 40, child: Text('Result', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: FabFilterColors.cyan))),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              itemCount: report.complianceMap.length,
              itemBuilder: (_, i) {
                final entry = report.complianceMap.entries.elementAt(i);
                final target = entry.key;
                final compliance = entry.value;
                final isSelected = target == _selectedTarget;

                return GestureDetector(
                  onTap: () => setState(() => _selectedTarget = target),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? FabFilterColors.cyan.withValues(alpha: 0.1) : null,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            target.name,
                            style: TextStyle(
                              fontSize: 9,
                              color: isSelected ? FabFilterColors.cyan : FabFilterColors.textSecondary,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${target.targetLufs.toStringAsFixed(0)} LUFS',
                            style: const TextStyle(fontSize: 9, color: FabFilterColors.textMuted, fontFamily: 'monospace'),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Row(
                            children: [
                              Icon(
                                compliance.isCompliant ? Icons.check_circle : Icons.cancel,
                                size: 10,
                                color: compliance.isCompliant ? FabFilterColors.green : FabFilterColors.red,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                compliance.isCompliant ? 'PASS' : 'FAIL',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: compliance.isCompliant ? FabFilterColors.green : FabFilterColors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Recommended gain
          if (!_selectedTarget.checkCompliance(report.analysis).isCompliant) ...[
            Divider(height: 12, color: FabFilterColors.borderSubtle),
            Row(
              children: [
                const Text('Rec. Gain:', style: TextStyle(fontSize: 8, color: FabFilterColors.textMuted)),
                const Spacer(),
                Text(
                  _recommendedGain(report),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: FabFilterColors.orange,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _startDryRun() {
    widget.onAction?.call('loudnessDryRun', {
      'target': _selectedTarget.name,
    });
  }

  void _cancelAnalysis() {
    _service.cancelAnalysis();
  }

  Future<void> _exportHtml() async {
    final html = _service.lastHtml;
    if (html == null) return;

    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final dir = Directory('$home/Library/Application Support/FluxForge Studio/Reports');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final timestamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
      final filePath = '${dir.path}/FluxForge_Loudness_$timestamp.html';
      await File(filePath).writeAsString(html);

      // Open in default browser
      await Process.run('open', [filePath]);

      widget.onAction?.call('loudnessReportExported', {'path': filePath});
    } catch (_) {
      // Silently fail — no console output per CLAUDE.md
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Color _lufsColor(double lufs) {
    if (lufs > -8.0) return FabFilterColors.red;
    if (lufs > -14.0) return FabFilterColors.orange;
    return FabFilterColors.green;
  }

  String _formatTime(double sec) {
    final m = (sec / 60).floor();
    final s = (sec % 60).floor();
    final ms = ((sec % 1) * 100).round();
    return '$m:${s.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }

  String _recommendedGain(LoudnessReportData report) {
    final service = LoudnessAnalysisService.instance;
    final gain = service.getRecommendedGain(report.analysis, _selectedTarget);
    return '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHORT-TERM GRAPH PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _ShortTermGraphPainter extends CustomPainter {
  final List<ShortTermReading> readings;
  final double integratedLufs;
  final double targetLufs;

  _ShortTermGraphPainter({
    required this.readings,
    required this.integratedLufs,
    required this.targetLufs,
  });

  static const _minLufs = -50.0;
  static const _maxLufs = 0.0;

  double _lufsToY(double lufs, double h) {
    return ((_maxLufs - lufs.clamp(_minLufs, _maxLufs)) / (_maxLufs - _minLufs)) * h;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (readings.isEmpty) return;

    final w = size.width;
    final h = size.height;
    final maxTime = readings.last.timeSec;
    if (maxTime <= 0) return;

    // Grid lines
    final gridPaint = Paint()
      ..color = FabFilterColors.borderSubtle
      ..strokeWidth = 0.5;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (double lufs = -50; lufs <= 0; lufs += 10) {
      final y = _lufsToY(lufs, h);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);

      textPainter.text = TextSpan(
        text: '${lufs.toInt()}',
        style: const TextStyle(fontSize: 8, color: FabFilterColors.textDisabled),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(2, y - 10));
    }

    // Short-term line
    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < readings.length; i++) {
      final x = (readings[i].timeSec / maxTime) * w;
      final y = _lufsToY(readings[i].lufs, h);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, h);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Fill
    fillPath.lineTo((readings.last.timeSec / maxTime) * w, h);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          FabFilterColors.cyan.withValues(alpha: 0.3),
          FabFilterColors.cyan.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // Line
    canvas.drawPath(
      path,
      Paint()
        ..color = FabFilterColors.cyan
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Integrated LUFS line
    if (integratedLufs > _minLufs) {
      final iy = _lufsToY(integratedLufs, h);
      final dashPaint = Paint()
        ..color = FabFilterColors.green
        ..strokeWidth = 1.0;

      const dashLen = 6.0;
      const gapLen = 4.0;
      double x = 0;
      while (x < w) {
        canvas.drawLine(Offset(x, iy), Offset((x + dashLen).clamp(0, w), iy), dashPaint);
        x += dashLen + gapLen;
      }

      textPainter.text = TextSpan(
        text: 'INT: ${integratedLufs.toStringAsFixed(1)}',
        style: const TextStyle(fontSize: 8, color: FabFilterColors.green),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(w - textPainter.width - 4, iy - 12));
    }

    // Target LUFS line
    if (targetLufs > _minLufs) {
      final ty = _lufsToY(targetLufs, h);
      final dashPaint = Paint()
        ..color = FabFilterColors.orange.withValues(alpha: 0.6)
        ..strokeWidth = 1.0;

      double x = 0;
      while (x < w) {
        canvas.drawLine(Offset(x, ty), Offset((x + 4.0).clamp(0, w), ty), dashPaint);
        x += 8.0;
      }

      textPainter.text = TextSpan(
        text: 'TGT: ${targetLufs.toStringAsFixed(0)}',
        style: TextStyle(fontSize: 8, color: FabFilterColors.orange.withValues(alpha: 0.8)),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(4, ty + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ShortTermGraphPainter old) {
    return readings != old.readings ||
        integratedLufs != old.integratedLufs ||
        targetLufs != old.targetLufs;
  }
}
