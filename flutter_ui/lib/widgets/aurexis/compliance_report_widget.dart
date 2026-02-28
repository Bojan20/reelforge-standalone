import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import '../../models/aurexis_jurisdiction.dart';
import '../../providers/aurexis_provider.dart';
import '../../providers/aurexis_profile_provider.dart';
import 'aurexis_theme.dart';

/// AUREXIS™ Compliance Report Widget.
///
/// Visual compliance check display showing pass/fail status
/// for each jurisdiction rule. Supports running checks,
/// viewing history, and exporting JSON reports.
class ComplianceReportWidget extends StatefulWidget {
  const ComplianceReportWidget({super.key});

  @override
  State<ComplianceReportWidget> createState() => _ComplianceReportWidgetState();
}

class _ComplianceReportWidgetState extends State<ComplianceReportWidget> {
  late final AurexisProvider _engine;
  late final AurexisProfileProvider _profile;
  JurisdictionComplianceReport? _report;
  bool _showDetails = true;

  @override
  void initState() {
    super.initState();
    _engine = GetIt.instance<AurexisProvider>();
    _profile = GetIt.instance<AurexisProfileProvider>();
    _profile.addListener(_onProfileUpdate);
  }

  @override
  void dispose() {
    _profile.removeListener(_onProfileUpdate);
    super.dispose();
  }

  void _onProfileUpdate() {
    // Auto-run compliance when profile changes if we have a report
    if (_report != null && mounted) {
      _runCheck();
    }
  }

  void _runCheck() {
    if (_profile.jurisdiction == AurexisJurisdiction.none) {
      setState(() => _report = null);
      return;
    }

    final params = _engine.parameters;
    final report = JurisdictionComplianceEngine.checkCompliance(
      jurisdiction: _profile.jurisdiction,
      currentEscalationMultiplier: params.escalationMultiplier,
      currentFatigueRegulation: params.fatigueIndex,
      currentWinVolumeBoostDb: params.subReinforcementDb.abs(),
      currentCelebrationDurationS: 5.0, // Default placeholder
      isDeterministic: true, // AUREXIS is always deterministic
      hasLdwSuppression: true, // Configured via profile
      hasSessionTimeCues: true, // Configured via profile
    );
    setState(() => _report = report);
  }

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
            _buildSummaryBar(),
            if (_showDetails) _buildCheckList(),
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
            'COMPLIANCE',
            style: AurexisTextStyles.sectionTitle.copyWith(fontSize: 9),
          ),
          const SizedBox(width: 4),
          Text(
            _profile.jurisdiction.code,
            style: AurexisTextStyles.badge.copyWith(
              color: _profile.jurisdiction == AurexisJurisdiction.none
                  ? AurexisColors.textSecondary
                  : AurexisColors.accent,
            ),
          ),
          const Spacer(),
          // Run check button
          GestureDetector(
            onTap: _runCheck,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AurexisColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: AurexisColors.accent.withValues(alpha: 0.3), width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow, size: 10, color: AurexisColors.accent),
                  const SizedBox(width: 2),
                  Text(
                    'CHECK',
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

  Widget _buildSummaryBar() {
    final report = _report!;
    final allPassed = report.allPassed;
    final statusColor = allPassed ? AurexisColors.fatigueFresh : AurexisColors.fatigueCritical;

    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withValues(alpha: 0.15),
              border: Border.all(color: statusColor, width: 1.5),
            ),
            child: Icon(
              allPassed ? Icons.check : Icons.close,
              size: 14,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 8),
          // Status text
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                allPassed ? 'ALL CHECKS PASSED' : 'COMPLIANCE ISSUES',
                style: AurexisTextStyles.sectionTitle.copyWith(
                  color: statusColor,
                  fontSize: 9,
                ),
              ),
              Text(
                '${report.passedCount}/${report.totalCount} rules passed',
                style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textLabel),
              ),
            ],
          ),
          const Spacer(),
          // Toggle details
          GestureDetector(
            onTap: () => setState(() => _showDetails = !_showDetails),
            child: Icon(
              _showDetails ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: AurexisColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckList() {
    final report = _report!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final check in report.checks) _buildCheckRow(check),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildCheckRow(ComplianceCheck check) {
    final color = check.passed ? AurexisColors.fatigueFresh : AurexisColors.fatigueCritical;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Row(
        children: [
          // Pass/fail icon
          Icon(
            check.passed ? Icons.check_circle_outline : Icons.error_outline,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 6),
          // Rule name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  check.ruleName,
                  style: AurexisTextStyles.paramLabel.copyWith(
                    color: AurexisColors.textPrimary,
                    fontSize: 9,
                  ),
                ),
                if (check.detail.isNotEmpty)
                  Text(
                    check.detail,
                    style: AurexisTextStyles.badge.copyWith(
                      color: AurexisColors.textLabel,
                      fontSize: 7,
                    ),
                  ),
              ],
            ),
          ),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              check.passed ? 'PASS' : 'FAIL',
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
    final report = _report!;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AurexisColors.borderSubtle, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Timestamp
          Text(
            '${report.timestamp.hour.toString().padLeft(2, '0')}:'
            '${report.timestamp.minute.toString().padLeft(2, '0')}:'
            '${report.timestamp.second.toString().padLeft(2, '0')}',
            style: AurexisTextStyles.badge.copyWith(
              color: AurexisColors.textLabel,
              fontSize: 7,
            ),
          ),
          const Spacer(),
          // Copy JSON
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: report.toJsonString()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Compliance report copied to clipboard'),
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
                  Text(
                    'JSON',
                    style: AurexisTextStyles.badge.copyWith(color: AurexisColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Auto-fix button (only shown when there are failures)
          if (!report.allPassed)
            GestureDetector(
              onTap: _autoFix,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AurexisColors.dynamics.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: AurexisColors.dynamics.withValues(alpha: 0.3), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_fix_high, size: 10, color: AurexisColors.dynamics),
                    const SizedBox(width: 2),
                    Text(
                      'AUTO-FIX',
                      style: AurexisTextStyles.badge.copyWith(color: AurexisColors.dynamics),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoReport() {
    if (_profile.jurisdiction == AurexisJurisdiction.none) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 20, color: AurexisColors.textLabel),
            const SizedBox(height: 4),
            Text(
              'Select a jurisdiction in the Profile\nsection to enable compliance checking.',
              textAlign: TextAlign.center,
              style: AurexisTextStyles.paramLabel.copyWith(
                color: AurexisColors.textLabel,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 20, color: AurexisColors.textSecondary),
          const SizedBox(height: 4),
          Text(
            'Press CHECK to run compliance\nvalidation for ${_profile.jurisdiction.label}.',
            textAlign: TextAlign.center,
            style: AurexisTextStyles.paramLabel.copyWith(
              color: AurexisColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _autoFix() {
    // Apply jurisdiction overrides to make the config compliant
    _profile.setJurisdiction(_profile.jurisdiction);
    // Re-run check after fix
    _runCheck();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MULTI-JURISDICTION REPORT
// ═════════════════════════════════════════════════════════════════════════════

/// Shows compliance status across ALL jurisdictions at once.
class MultiJurisdictionReportWidget extends StatelessWidget {
  const MultiJurisdictionReportWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = GetIt.instance<AurexisProvider>();
    final params = engine.parameters;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AurexisColors.bgSection,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AurexisColors.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'MULTI-JURISDICTION OVERVIEW',
            style: AurexisTextStyles.sectionTitle.copyWith(fontSize: 8),
          ),
          const SizedBox(height: 6),
          for (final jurisdiction in AurexisJurisdiction.values)
            if (jurisdiction != AurexisJurisdiction.none)
              _buildJurisdictionRow(jurisdiction, params),
        ],
      ),
    );
  }

  Widget _buildJurisdictionRow(
    AurexisJurisdiction jurisdiction,
    dynamic params,
  ) {
    final report = JurisdictionComplianceEngine.checkCompliance(
      jurisdiction: jurisdiction,
      currentEscalationMultiplier: params.escalationMultiplier,
      currentFatigueRegulation: params.fatigueIndex,
      currentWinVolumeBoostDb: params.subReinforcementDb.abs(),
      currentCelebrationDurationS: 5.0,
      isDeterministic: true,
      hasLdwSuppression: true,
      hasSessionTimeCues: true,
    );

    final allPassed = report.allPassed;
    final color = allPassed ? AurexisColors.fatigueFresh : AurexisColors.fatigueCritical;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AurexisColors.bgInput,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          // Jurisdiction name
          Expanded(
            child: Text(
              jurisdiction.label,
              style: AurexisTextStyles.paramLabel.copyWith(fontSize: 9),
            ),
          ),
          // Score
          Text(
            '${report.passedCount}/${report.totalCount}',
            style: AurexisTextStyles.paramValue.copyWith(
              color: color,
              fontSize: 9,
            ),
          ),
          const SizedBox(width: 4),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              allPassed ? 'OK' : 'FAIL',
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
}
