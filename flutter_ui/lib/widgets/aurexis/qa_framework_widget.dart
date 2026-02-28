import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import '../../models/aurexis_qa.dart';
import '../../models/aurexis_models.dart';
import '../../providers/aurexis_provider.dart';
import '../../providers/aurexis_profile_provider.dart';
import 'aurexis_theme.dart';

/// AUREXIS™ QA Framework Widget.
///
/// Runs automated quality checks against current AUREXIS state
/// and displays pass/warn/fail results by category.
class QaFrameworkWidget extends StatefulWidget {
  const QaFrameworkWidget({super.key});

  @override
  State<QaFrameworkWidget> createState() => _QaFrameworkWidgetState();
}

class _QaFrameworkWidgetState extends State<QaFrameworkWidget> {
  QaReport? _report;
  QaCategory? _filterCategory;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AurexisColors.bgSection,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          if (_report != null) ...[
            _buildSummary(),
            _buildCategoryFilter(),
            _buildCheckList(),
            _buildActions(),
          ] else
            _buildNoReport(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AurexisColors.bgSectionHeader,
        border: Border(
          bottom: BorderSide(color: AurexisColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            'QA FRAMEWORK',
            style: AurexisTextStyles.sectionTitle.copyWith(fontSize: 9),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _runQa,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AurexisColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: AurexisColors.accent.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow, size: 10, color: AurexisColors.accent),
                  const SizedBox(width: 2),
                  Text(
                    'RUN QA',
                    style: AurexisTextStyles.badge.copyWith(color: AurexisColors.accent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final r = _report!;
    final statusColor = r.allPassed ? AurexisColors.fatigueFresh : AurexisColors.fatigueCritical;

    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // Overall status
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withValues(alpha: 0.15),
              border: Border.all(color: statusColor, width: 1.5),
            ),
            child: Center(
              child: Text(
                '${(r.passPercent * 100).toStringAsFixed(0)}',
                style: AurexisTextStyles.paramValue.copyWith(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Counts
          Expanded(
            child: Row(
              children: [
                _buildCountBadge('PASS', r.passCount, AurexisColors.fatigueFresh),
                const SizedBox(width: 4),
                _buildCountBadge('WARN', r.warnCount, AurexisColors.fatigueModerate),
                const SizedBox(width: 4),
                _buildCountBadge('FAIL', r.failCount, AurexisColors.fatigueCritical),
                const SizedBox(width: 4),
                _buildCountBadge('SKIP', r.skipCount, AurexisColors.textLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: count > 0 ? color.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: count > 0 ? color.withValues(alpha: 0.3) : AurexisColors.borderSubtle,
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: AurexisTextStyles.paramValue.copyWith(
              color: count > 0 ? color : AurexisColors.textLabel,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: AurexisTextStyles.badge.copyWith(
              color: AurexisColors.textLabel,
              fontSize: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _buildCatChip(null, 'All'),
          for (final cat in QaCategory.values)
            _buildCatChip(cat, cat.label),
        ],
      ),
    );
  }

  Widget _buildCatChip(QaCategory? cat, String label) {
    final isSelected = _filterCategory == cat;
    return GestureDetector(
      onTap: () => setState(() => _filterCategory = cat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AurexisColors.accent.withValues(alpha: 0.15)
              : AurexisColors.bgInput,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? AurexisColors.accent : AurexisColors.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: AurexisTextStyles.badge.copyWith(
            color: isSelected ? AurexisColors.accent : AurexisColors.textSecondary,
            fontSize: 7,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckList() {
    final checks = _filterCategory != null
        ? _report!.byCategory(_filterCategory!)
        : _report!.checks;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final check in checks) _buildCheckRow(check),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildCheckRow(QaCheck check) {
    final color = switch (check.result) {
      QaResult.pass => AurexisColors.fatigueFresh,
      QaResult.warn => AurexisColors.fatigueModerate,
      QaResult.fail => AurexisColors.fatigueCritical,
      QaResult.skip => AurexisColors.textLabel,
    };

    final icon = switch (check.result) {
      QaResult.pass => Icons.check_circle_outline,
      QaResult.warn => Icons.warning_amber,
      QaResult.fail => Icons.error_outline,
      QaResult.skip => Icons.skip_next,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.15), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  check.name,
                  style: AurexisTextStyles.paramLabel.copyWith(fontSize: 9),
                ),
                if (check.detail.isNotEmpty)
                  Text(
                    check.detail,
                    style: AurexisTextStyles.badge.copyWith(
                      color: AurexisColors.textLabel,
                      fontSize: 7,
                    ),
                  ),
                if (check.expected != null && check.actual != null)
                  Text(
                    'Expected: ${check.expected} | Got: ${check.actual}',
                    style: AurexisTextStyles.badge.copyWith(
                      color: AurexisColors.textLabel,
                      fontSize: 6,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              check.result.label,
              style: AurexisTextStyles.badge.copyWith(
                color: color,
                fontSize: 7,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AurexisColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${_report!.timestamp.hour.toString().padLeft(2, '0')}:'
            '${_report!.timestamp.minute.toString().padLeft(2, '0')}:'
            '${_report!.timestamp.second.toString().padLeft(2, '0')}',
            style: AurexisTextStyles.badge.copyWith(
              color: AurexisColors.textLabel,
              fontSize: 7,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _report!.toJsonString()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('QA report copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AurexisColors.bgInput,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy, size: 10, color: AurexisColors.textSecondary),
                  const SizedBox(width: 2),
                  Text('JSON', style: AurexisTextStyles.badge.copyWith(fontSize: 7)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoReport() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined, size: 20, color: AurexisColors.textLabel),
            const SizedBox(height: 4),
            Text(
              'Press RUN QA to execute the\nquality assurance test suite.',
              textAlign: TextAlign.center,
              style: AurexisTextStyles.paramLabel.copyWith(
                color: AurexisColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _runQa() {
    final engine = GetIt.instance<AurexisProvider>();
    final profile = GetIt.instance<AurexisProfileProvider>();
    final params = engine.parameters;

    final report = AurexisQaEngine.runFullSuite(
      engineInitialized: engine.initialized,
      rtp: engine.rtp,
      fatigueIndex: params.fatigueIndex,
      escalationMultiplier: params.escalationMultiplier,
      energyDensity: params.energyDensity,
      voiceCount: params.centerOccupancy,
      stereoWidth: params.stereoWidth,
      memoryUsedMb: 0.0, // Will be populated by audio asset manager
      memoryBudgetMb: switch (engine.platform) {
        AurexisPlatform.mobile => 4.0,
        AurexisPlatform.cabinet => 3.0,
        _ => 6.0,
      },
      isDeterministic: true,
      jurisdictionCode: profile.jurisdiction.code,
      profileId: profile.activeProfile.id,
    );

    setState(() => _report = report);
  }
}
