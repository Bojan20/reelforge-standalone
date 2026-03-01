/// FluxMacro Report Viewer — FM-40
///
/// In-app report viewer for FluxMacro run results.
/// Split pane layout: report content left, metrics summary right.
/// Supports viewing QA results, artifacts list, and warnings/errors.
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../providers/fluxmacro_provider.dart';
import '../../../../theme/fluxforge_theme.dart';

class MacroReportViewer extends StatefulWidget {
  const MacroReportViewer({super.key});

  @override
  State<MacroReportViewer> createState() => _MacroReportViewerState();
}

class _MacroReportViewerState extends State<MacroReportViewer> {
  final _provider = GetIt.instance<FluxMacroProvider>();
  int _selectedTab = 0; // 0=Summary, 1=QA, 2=Artifacts, 3=Warnings

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final result = _provider.lastResult;

    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.bgHover),
          if (result == null)
            Expanded(child: _buildEmpty())
          else
            Expanded(child: _buildReport(result)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: FluxForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.assessment, size: 14, color: FluxForgeTheme.accentPink),
          const SizedBox(width: 6),
          const Text(
            'REPORTS',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Tab selector
          ...['Summary', 'QA', 'Artifacts', 'Warnings'].asMap().entries.map((e) {
            final idx = e.key;
            final label = e.value;
            final selected = idx == _selectedTab;
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: GestureDetector(
                onTap: () => setState(() => _selectedTab = idx),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? FluxForgeTheme.accentPink.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? FluxForgeTheme.accentPink
                          : FluxForgeTheme.textTertiary,
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.article_outlined,
            size: 32,
            color: FluxForgeTheme.textTertiary.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 8),
          const Text(
            'No report available',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            'Run a macro to generate a report',
            style: TextStyle(
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReport(FluxMacroRunResult result) {
    return Row(
      children: [
        // Left — Report content
        Expanded(
          flex: 3,
          child: _buildReportContent(result),
        ),
        const VerticalDivider(width: 1, color: FluxForgeTheme.bgHover),
        // Right — Metrics sidebar
        SizedBox(
          width: 200,
          child: _buildMetricsSidebar(result),
        ),
      ],
    );
  }

  Widget _buildReportContent(FluxMacroRunResult result) {
    return switch (_selectedTab) {
      0 => _buildSummaryTab(result),
      1 => _buildQaTab(result),
      2 => _buildArtifactsTab(result),
      3 => _buildWarningsTab(result),
      _ => _buildSummaryTab(result),
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUMMARY TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSummaryTab(FluxMacroRunResult result) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (result.success ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: (result.success ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed)
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  result.success ? Icons.check_circle : Icons.error,
                  size: 16,
                  color: result.success ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                ),
                const SizedBox(width: 6),
                Text(
                  result.success ? 'ALL CHECKS PASSED' : 'CHECKS FAILED',
                  style: TextStyle(
                    color: result.success ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Info rows
          _buildInfoRow('Game', result.gameId),
          _buildInfoRow('Seed', result.seed.toString()),
          _buildInfoRow('Hash', result.runHash),
          _buildInfoRow('Duration', '${result.durationMs}ms'),
          _buildInfoRow('QA Results', '${result.qaPassed}/${result.qaTotal} passed'),
          _buildInfoRow('Artifacts', '${result.artifacts.length} generated'),
          if (result.warnings.isNotEmpty)
            _buildInfoRow('Warnings', '${result.warnings.length}'),
          if (result.errors.isNotEmpty)
            _buildInfoRow('Errors', '${result.errors.length}'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QA TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQaTab(FluxMacroRunResult result) {
    final qaResults = _provider.getQaResults();

    if (qaResults == null) {
      return const Center(
        child: Text(
          'No QA results available',
          style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    final tests = qaResults['tests'] as List<dynamic>? ?? [];

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tests.length,
      itemBuilder: (context, index) {
        final test = tests[index] as Map<String, dynamic>;
        final passed = test['passed'] as bool? ?? false;
        final name = test['name'] as String? ?? 'Unknown';
        final detail = test['detail'] as String? ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              Icon(
                passed ? Icons.check_circle : Icons.cancel,
                size: 14,
                color: passed ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        style: const TextStyle(
                          color: FluxForgeTheme.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ARTIFACTS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildArtifactsTab(FluxMacroRunResult result) {
    if (result.artifacts.isEmpty) {
      return const Center(
        child: Text(
          'No artifacts generated',
          style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: result.artifacts.length,
      itemBuilder: (context, index) {
        final artifact = result.artifacts[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              const Icon(Icons.insert_drive_file, size: 14, color: FluxForgeTheme.accentCyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  artifact,
                  style: const TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WARNINGS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildWarningsTab(FluxMacroRunResult result) {
    final items = [
      ...result.warnings.map((w) => (w, false)),
      ...result.errors.map((e) => (e, true)),
    ];

    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No warnings or errors',
          style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final (message, isError) = items[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isError ? FluxForgeTheme.accentRed : FluxForgeTheme.accentOrange)
                .withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: (isError ? FluxForgeTheme.accentRed : FluxForgeTheme.accentOrange)
                  .withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.warning_amber,
                size: 14,
                color: isError ? FluxForgeTheme.accentRed : FluxForgeTheme.accentOrange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: isError
                        ? FluxForgeTheme.accentRed.withValues(alpha: 0.9)
                        : FluxForgeTheme.accentOrange.withValues(alpha: 0.9),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // METRICS SIDEBAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMetricsSidebar(FluxMacroRunResult result) {
    return Container(
      color: FluxForgeTheme.bgMid,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'METRICS',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            _buildMetric('Status', result.success ? 'PASS' : 'FAIL',
                result.success ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed),
            _buildMetric('Duration', '${result.durationMs}ms', FluxForgeTheme.textSecondary),
            _buildMetric('QA Pass', '${result.qaPassed}', FluxForgeTheme.accentGreen),
            _buildMetric('QA Fail', '${result.qaFailed}', FluxForgeTheme.accentRed),
            _buildMetric('Artifacts', '${result.artifacts.length}', FluxForgeTheme.accentCyan),
            _buildMetric('Warnings', '${result.warnings.length}', FluxForgeTheme.accentOrange),
            _buildMetric('Errors', '${result.errors.length}', FluxForgeTheme.accentRed),
            const SizedBox(height: 16),
            const Text(
              'HASH',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              result.runHash,
              style: const TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 9,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: FluxForgeTheme.textTertiary,
              fontSize: 10,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ],
      ),
    );
  }
}
