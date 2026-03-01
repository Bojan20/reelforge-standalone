/// FluxMacro Run History — FM-42
///
/// Displays run history list with:
/// - Timestamp, macro name, game ID, status (pass/fail)
/// - Duration, run hash
/// - Compare mode: select two runs to diff
library;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../../providers/fluxmacro_provider.dart';
import '../../../../theme/fluxforge_theme.dart';

class MacroHistory extends StatefulWidget {
  const MacroHistory({super.key});

  @override
  State<MacroHistory> createState() => _MacroHistoryState();
}

class _MacroHistoryState extends State<MacroHistory> {
  final _provider = GetIt.instance<FluxMacroProvider>();
  String? _selectedRunId;
  String? _compareRunId;
  bool _compareMode = false;
  Map<String, dynamic>? _runDetail;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
    // Load history for default working dir
    _provider.loadHistory('/tmp/fluxmacro');
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
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.bgHover),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: FluxForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.history, size: 14, color: FluxForgeTheme.accentCyan),
          const SizedBox(width: 6),
          const Text(
            'HISTORY',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Compare mode toggle
          GestureDetector(
            onTap: () {
              setState(() {
                _compareMode = !_compareMode;
                if (!_compareMode) {
                  _compareRunId = null;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _compareMode
                    ? FluxForgeTheme.accentCyan.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'COMPARE',
                style: TextStyle(
                  color: _compareMode
                      ? FluxForgeTheme.accentCyan
                      : FluxForgeTheme.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Refresh
          GestureDetector(
            onTap: () => _provider.loadHistory('/tmp/fluxmacro'),
            child: const Icon(Icons.refresh, size: 14, color: FluxForgeTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CONTENT
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContent() {
    final history = _provider.history;

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 32,
              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 8),
            const Text(
              'No run history',
              style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              'Run a macro to build history',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        // Left: history list
        SizedBox(
          width: 320,
          child: _buildHistoryList(history),
        ),
        const VerticalDivider(width: 1, color: FluxForgeTheme.bgHover),
        // Right: detail or compare
        Expanded(
          child: _compareMode && _selectedRunId != null && _compareRunId != null
              ? _buildCompareView()
              : _runDetail != null
                  ? _buildDetailView()
                  : _buildDetailPlaceholder(),
        ),
      ],
    );
  }

  Widget _buildHistoryList(List<FluxMacroHistoryEntry> history) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final entry = history[index];
        final isSelected = entry.runId == _selectedRunId;
        final isCompare = entry.runId == _compareRunId;

        return GestureDetector(
          onTap: () => _selectRun(entry),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1)
                  : isCompare
                      ? FluxForgeTheme.accentCyan.withValues(alpha: 0.08)
                      : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? FluxForgeTheme.accentBlue.withValues(alpha: 0.3)
                    : isCompare
                        ? FluxForgeTheme.accentCyan.withValues(alpha: 0.3)
                        : FluxForgeTheme.bgHover,
              ),
            ),
            child: Row(
              children: [
                // Status icon
                Icon(
                  entry.success ? Icons.check_circle : Icons.error,
                  size: 14,
                  color: entry.success ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                ),
                const SizedBox(width: 8),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            entry.macroName,
                            style: const TextStyle(
                              color: FluxForgeTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${entry.durationMs}ms',
                            style: const TextStyle(
                              color: FluxForgeTheme.textTertiary,
                              fontSize: 10,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            entry.gameId,
                            style: const TextStyle(
                              color: FluxForgeTheme.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            entry.timestamp.length > 16
                                ? entry.timestamp.substring(0, 16)
                                : entry.timestamp,
                            style: TextStyle(
                              color: FluxForgeTheme.textTertiary.withValues(alpha: 0.6),
                              fontSize: 9,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectRun(FluxMacroHistoryEntry entry) {
    setState(() {
      if (_compareMode && _selectedRunId != null && _selectedRunId != entry.runId) {
        _compareRunId = entry.runId;
      } else {
        _selectedRunId = entry.runId;
        _compareRunId = null;
        // Load detail
        _runDetail = _provider.getRunDetail('/tmp/fluxmacro', entry.runId);
      }
    });
  }

  Widget _buildDetailPlaceholder() {
    return const Center(
      child: Text(
        'Select a run to view details',
        style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
      ),
    );
  }

  Widget _buildDetailView() {
    final detail = _runDetail!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow('Run ID', detail['run_id']?.toString() ?? ''),
          _buildDetailRow('Macro', detail['macro_name']?.toString() ?? ''),
          _buildDetailRow('Game', detail['game_id']?.toString() ?? ''),
          _buildDetailRow('Seed', detail['seed']?.toString() ?? ''),
          _buildDetailRow('Hash', detail['run_hash']?.toString() ?? ''),
          _buildDetailRow('Status', (detail['success'] == true) ? 'PASS' : 'FAIL'),
          _buildDetailRow('Duration', '${detail['duration_ms'] ?? 0}ms'),
          _buildDetailRow('Timestamp', detail['timestamp']?.toString() ?? ''),
          const SizedBox(height: 12),
          // Steps executed
          if (detail['steps'] != null) ...[
            const Text(
              'STEPS',
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            ...(detail['steps'] as List<dynamic>).map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '  $s',
                    style: const TextStyle(
                      color: FluxForgeTheme.textTertiary,
                      fontSize: 10,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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

  Widget _buildCompareView() {
    final detail1 = _provider.getRunDetail('/tmp/fluxmacro', _selectedRunId!);
    final detail2 = _provider.getRunDetail('/tmp/fluxmacro', _compareRunId!);

    if (detail1 == null || detail2 == null) {
      return const Center(
        child: Text(
          'Cannot load run details for comparison',
          style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'COMPARE RUNS',
            style: TextStyle(
              color: FluxForgeTheme.accentCyan,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          // Header row
          Row(
            children: [
              const SizedBox(width: 80),
              Expanded(
                child: Text(
                  'Run A',
                  style: TextStyle(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'Run B',
                  style: TextStyle(
                    color: FluxForgeTheme.accentCyan.withValues(alpha: 0.8),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildCompareRow('Status',
              (detail1['success'] == true) ? 'PASS' : 'FAIL',
              (detail2['success'] == true) ? 'PASS' : 'FAIL'),
          _buildCompareRow('Seed',
              detail1['seed']?.toString() ?? '',
              detail2['seed']?.toString() ?? ''),
          _buildCompareRow('Hash',
              _shortHash(detail1['run_hash']?.toString() ?? ''),
              _shortHash(detail2['run_hash']?.toString() ?? '')),
          _buildCompareRow('Duration',
              '${detail1['duration_ms'] ?? 0}ms',
              '${detail2['duration_ms'] ?? 0}ms'),
        ],
      ),
    );
  }

  Widget _buildCompareRow(String label, String valueA, String valueB) {
    final match = valueA == valueB;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valueA,
              style: TextStyle(
                color: match ? FluxForgeTheme.textSecondary : FluxForgeTheme.accentOrange,
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
          Expanded(
            child: Text(
              valueB,
              style: TextStyle(
                color: match ? FluxForgeTheme.textSecondary : FluxForgeTheme.accentOrange,
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
          Icon(
            match ? Icons.check : Icons.compare_arrows,
            size: 12,
            color: match ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentOrange,
          ),
        ],
      ),
    );
  }

  String _shortHash(String hash) {
    return hash.length >= 16 ? hash.substring(0, 16) : hash;
  }
}
