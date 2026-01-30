/// P0 WF-10: Stage Coverage Panel (2026-01-30)
///
/// Visual coverage tracking panel for stage testing.
/// Shows tested vs untested stages with progress metrics.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/stage_coverage_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Stage Coverage Panel widget
class CoveragePanel extends StatefulWidget {
  const CoveragePanel({super.key});

  @override
  State<CoveragePanel> createState() => _CoveragePanelState();
}

class _CoveragePanelState extends State<CoveragePanel> {
  CoverageStatus _filterStatus = CoverageStatus.untested;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: StageCoverageService.instance,
      child: Consumer<StageCoverageService>(
        builder: (context, service, _) {
          final stats = service.getStats();

          return Column(
            children: [
              _buildHeader(service, stats),
              const SizedBox(height: 8),
              _buildStatsBar(stats),
              const SizedBox(height: 8),
              _buildFilterTabs(),
              const SizedBox(height: 8),
              Expanded(
                child: _buildStageList(service),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(StageCoverageService service, CoverageStats stats) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.checklist, size: 16, color: FluxForgeTheme.accentGreen),
          const SizedBox(width: 8),
          Text(
            'STAGE COVERAGE',
            style: FluxForgeTheme.label.copyWith(
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Big coverage percentage
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _getCoverageColor(stats.coverage).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _getCoverageColor(stats.coverage)),
            ),
            child: Text(
              '${(stats.coverage * 100).toInt()}%',
              style: FluxForgeTheme.body.copyWith(
                color: _getCoverageColor(stats.coverage),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${stats.testedStages + stats.verifiedStages}/${stats.totalStages}',
            style: FluxForgeTheme.bodySmall.copyWith(
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: Icon(
              service.isRecording ? Icons.fiber_manual_record : Icons.stop_circle,
              size: 16,
              color: service.isRecording ? FluxForgeTheme.accentRed : FluxForgeTheme.textTertiary,
            ),
            tooltip: service.isRecording ? 'Recording enabled' : 'Recording disabled',
            onPressed: () => service.setRecording(!service.isRecording),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            color: FluxForgeTheme.textSecondary,
            tooltip: 'Reset coverage',
            onPressed: () => _confirmReset(service),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar(CoverageStats stats) {
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: _buildStatSegment(
              'Verified',
              stats.verifiedStages,
              FluxForgeTheme.accentGreen,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildStatSegment(
              'Tested',
              stats.testedStages,
              FluxForgeTheme.accentBlue,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildStatSegment(
              'Untested',
              stats.untestedStages,
              FluxForgeTheme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatSegment(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: FluxForgeTheme.bodySmall.copyWith(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: FluxForgeTheme.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _buildFilterTab(CoverageStatus.untested, 'Untested', Icons.warning),
          const SizedBox(width: 4),
          _buildFilterTab(CoverageStatus.tested, 'Tested', Icons.check),
          const SizedBox(width: 4),
          _buildFilterTab(CoverageStatus.verified, 'Verified', Icons.verified),
        ],
      ),
    );
  }

  Widget _buildFilterTab(CoverageStatus status, String label, IconData icon) {
    final isSelected = _filterStatus == status;
    final color = _getStatusColor(status);

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _filterStatus = status),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? color : FluxForgeTheme.borderSubtle,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? color : FluxForgeTheme.textTertiary),
              const SizedBox(width: 6),
              Text(
                label,
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: isSelected ? color : FluxForgeTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageList(StageCoverageService service) {
    final entries = service.coverage.values
        .where((e) => e.status == _filterStatus)
        .toList()
      ..sort((a, b) => a.stage.compareTo(b.stage));

    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _filterStatus == CoverageStatus.untested ? Icons.check_circle : Icons.warning,
              size: 48,
              color: _filterStatus == CoverageStatus.untested
                  ? FluxForgeTheme.accentGreen
                  : FluxForgeTheme.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              _filterStatus == CoverageStatus.untested
                  ? 'All stages tested!'
                  : 'No stages in this category',
              style: FluxForgeTheme.bodySmall.copyWith(
                color: FluxForgeTheme.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _buildStageItem(entry, service);
      },
    );
  }

  Widget _buildStageItem(StageCoverageEntry entry, StageCoverageService service) {
    final color = _getStatusColor(entry.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.stage,
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (entry.triggerCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${entry.triggerCount}x',
                    style: FluxForgeTheme.bodySmall.copyWith(
                      color: FluxForgeTheme.accentBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 16, color: FluxForgeTheme.textTertiary),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'verify',
                    child: Row(
                      children: [
                        Icon(Icons.verified, size: 16),
                        SizedBox(width: 8),
                        Text('Mark as Verified'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'untested',
                    child: Row(
                      children: [
                        Icon(Icons.refresh, size: 16),
                        SizedBox(width: 8),
                        Text('Mark as Untested'),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'verify') {
                    service.markVerified(entry.stage);
                  } else if (value == 'untested') {
                    service.markUntested(entry.stage);
                  }
                },
              ),
            ],
          ),
          if (entry.lastTriggered != null) ...[
            const SizedBox(height: 6),
            Text(
              'Last: ${_formatTimestamp(entry.lastTriggered!)}',
              style: FluxForgeTheme.bodySmall.copyWith(
                color: FluxForgeTheme.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getCoverageColor(double coverage) {
    if (coverage >= 0.8) return FluxForgeTheme.accentGreen;
    if (coverage >= 0.5) return FluxForgeTheme.accentOrange;
    return FluxForgeTheme.accentRed;
  }

  Color _getStatusColor(CoverageStatus status) {
    switch (status) {
      case CoverageStatus.verified:
        return FluxForgeTheme.accentGreen;
      case CoverageStatus.tested:
        return FluxForgeTheme.accentBlue;
      case CoverageStatus.untested:
        return FluxForgeTheme.textTertiary;
    }
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _confirmReset(StageCoverageService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: Text(
          'Reset Coverage?',
          style: FluxForgeTheme.body.copyWith(color: FluxForgeTheme.textPrimary),
        ),
        content: Text(
          'This will mark all stages as untested and clear trigger history.',
          style: FluxForgeTheme.bodySmall.copyWith(color: FluxForgeTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              service.reset();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: FluxForgeTheme.accentRed),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
