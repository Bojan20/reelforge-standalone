/// GDD Validator Panel
///
/// Comprehensive Game Design Document validation panel for SlotLab.
/// Runs structural, mathematical, symbol, feature, audio, paytable,
/// and consistency checks against the imported GDD.
///
/// Displays results grouped by category with collapsible sections,
/// severity indicators, and an overall health score.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../providers/slot_lab_project_provider.dart';
import '../../../../services/gdd_validator_service.dart';
import '../../../../services/gdd_import_service.dart';
import '../../../../theme/fluxforge_theme.dart';

// =============================================================================
// CONSTANTS
// =============================================================================

const Color _colorPassed = Color(0xFF40FF90);
const Color _colorError = Color(0xFFFF4060);
const Color _colorWarning = Color(0xFFFF9040);
const Color _colorInfo = FluxForgeTheme.accentCyan;

// =============================================================================
// GDD VALIDATOR PANEL
// =============================================================================

class GddValidatorPanel extends StatefulWidget {
  const GddValidatorPanel({super.key});

  @override
  State<GddValidatorPanel> createState() => _GddValidatorPanelState();
}

class _GddValidatorPanelState extends State<GddValidatorPanel> {
  GddValidationResult? _result;
  final Set<GddValidationCategory> _collapsed = {};
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runIfGddAvailable();
    });
  }

  void _runIfGddAvailable() {
    final provider = context.read<SlotLabProjectProvider>();
    if (provider.hasImportedGdd) {
      _runValidation(provider.importedGdd!);
    }
  }

  void _runValidation(GameDesignDocument gdd) {
    setState(() => _isRunning = true);
    final result = GddValidatorService.instance.validateDocument(gdd);
    setState(() {
      _result = result;
      _isRunning = false;
    });
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Consumer<SlotLabProjectProvider>(
      builder: (context, provider, _) {
        if (!provider.hasImportedGdd) {
          return _buildEmptyState();
        }
        return _buildContent(provider);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // EMPTY STATE
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 40,
            color: FluxForgeTheme.textDisabled,
          ),
          const SizedBox(height: 12),
          Text(
            'No GDD imported',
            style: FluxForgeTheme.h3.copyWith(color: FluxForgeTheme.textTertiary),
          ),
          const SizedBox(height: 6),
          Text(
            'Import a Game Design Document to run validation',
            style: FluxForgeTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN CONTENT
  // ---------------------------------------------------------------------------

  Widget _buildContent(SlotLabProjectProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(provider),
        const SizedBox(height: 2),
        Expanded(
          child: _result == null
              ? Center(
                  child: Text(
                    'Press "Run Validation" to check your GDD',
                    style: FluxForgeTheme.bodySmall,
                  ),
                )
              : _buildCategoryList(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER BAR
  // ---------------------------------------------------------------------------

  Widget _buildHeader(SlotLabProjectProvider provider) {
    final score = _result?.score ?? 0.0;
    final errors = _result?.errorCount ?? 0;
    final warnings = _result?.warningCount ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Title
          Icon(
            _result != null && _result!.isValid
                ? Icons.check_circle_outline
                : Icons.policy_outlined,
            size: 14,
            color: _result != null && _result!.isValid
                ? _colorPassed
                : FluxForgeTheme.accentCyan,
          ),
          const SizedBox(width: 6),
          Text(
            'GDD VALIDATOR',
            style: FluxForgeTheme.label.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: FluxForgeTheme.textSecondary,
            ),
          ),

          const SizedBox(width: 12),

          // Score badge
          if (_result != null) ...[
            _buildScoreBadge(score),
            const SizedBox(width: 8),
            if (errors > 0)
              _buildCountBadge(errors, 'Error${errors > 1 ? "s" : ""}', _colorError),
            if (errors > 0 && warnings > 0)
              const SizedBox(width: 6),
            if (warnings > 0)
              _buildCountBadge(warnings, 'Warning${warnings > 1 ? "s" : ""}', _colorWarning),
          ],

          const Spacer(),

          // Run button
          SizedBox(
            height: 24,
            child: TextButton.icon(
              onPressed: _isRunning
                  ? null
                  : () => _runValidation(provider.importedGdd!),
              icon: _isRunning
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(FluxForgeTheme.accentCyan),
                      ),
                    )
                  : Icon(Icons.play_arrow, size: 14, color: FluxForgeTheme.accentCyan),
              label: Text(
                _isRunning ? 'Running...' : 'Run Validation',
                style: FluxForgeTheme.label.copyWith(color: FluxForgeTheme.accentCyan),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(
                    color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreBadge(double score) {
    final Color color;
    if (score > 80) {
      color = _colorPassed;
    } else if (score >= 50) {
      color = _colorWarning;
    } else {
      color = _colorError;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Score: ${score.toInt()}/100',
        style: FluxForgeTheme.label.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildCountBadge(int count, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$count $label',
          style: FluxForgeTheme.label.copyWith(color: color),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // CATEGORY LIST
  // ---------------------------------------------------------------------------

  Widget _buildCategoryList() {
    final result = _result!;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: GddValidationCategory.values.length,
      itemBuilder: (context, index) {
        final category = GddValidationCategory.values[index];
        final issues = result.byCategory(category);
        return _buildCategorySection(category, issues, result.totalChecks);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // CATEGORY SECTION
  // ---------------------------------------------------------------------------

  Widget _buildCategorySection(
    GddValidationCategory category,
    List<GddValidationIssue> issues,
    int totalChecks,
  ) {
    final isCollapsed = _collapsed.contains(category);
    final errors = issues.where((i) => i.severity == GddValidationSeverity.error).length;
    final warnings = issues.where((i) => i.severity == GddValidationSeverity.warning).length;
    final infos = issues.where((i) => i.severity == GddValidationSeverity.info).length;
    final hasProblems = errors > 0 || warnings > 0;

    // Determine category status icon and color
    final Color statusColor;
    final IconData statusIcon;
    if (errors > 0) {
      statusColor = _colorError;
      statusIcon = Icons.cancel;
    } else if (warnings > 0) {
      statusColor = _colorWarning;
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = _colorPassed;
      statusIcon = Icons.check_circle;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Category header (clickable)
          InkWell(
            onTap: () {
              setState(() {
                if (isCollapsed) {
                  _collapsed.remove(category);
                } else {
                  _collapsed.add(category);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: hasProblems
                      ? statusColor.withValues(alpha: 0.2)
                      : FluxForgeTheme.borderSubtle.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  // Expand/collapse indicator
                  Icon(
                    isCollapsed
                        ? Icons.chevron_right
                        : Icons.expand_more,
                    size: 14,
                    color: FluxForgeTheme.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  // Category name
                  Text(
                    _categoryDisplayName(category),
                    style: FluxForgeTheme.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Issue count summary
                  if (errors > 0) ...[
                    _buildMiniCount(errors, _colorError),
                    const SizedBox(width: 4),
                  ],
                  if (warnings > 0) ...[
                    _buildMiniCount(warnings, _colorWarning),
                    const SizedBox(width: 4),
                  ],
                  if (infos > 0)
                    _buildMiniCount(infos, _colorInfo),
                  const Spacer(),
                  // Status icon
                  Icon(statusIcon, size: 14, color: statusColor),
                ],
              ),
            ),
          ),

          // Issues list (when expanded and has issues)
          if (!isCollapsed && issues.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 18, top: 1),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: statusColor.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: issues.map((issue) => _buildIssueRow(issue)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniCount(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          fontFamily: FluxForgeTheme.monoFontFamily,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ISSUE ROW
  // ---------------------------------------------------------------------------

  Widget _buildIssueRow(GddValidationIssue issue) {
    final Color severityColor;
    final IconData severityIcon;
    switch (issue.severity) {
      case GddValidationSeverity.error:
        severityColor = _colorError;
        severityIcon = Icons.close;
      case GddValidationSeverity.warning:
        severityColor = _colorWarning;
        severityIcon = Icons.warning_amber;
      case GddValidationSeverity.info:
        severityColor = _colorInfo;
        severityIcon = Icons.info_outline;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main issue message
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(severityIcon, size: 11, color: severityColor),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  issue.message,
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ),
              // Field badge
              if (issue.field != null)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgElevated,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    issue.field!,
                    style: TextStyle(
                      fontSize: 8,
                      fontFamily: FluxForgeTheme.monoFontFamily,
                      color: FluxForgeTheme.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
          // Suggestion (indented, dimmer)
          if (issue.suggestion != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '->',
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: FluxForgeTheme.monoFontFamily,
                      color: FluxForgeTheme.textDisabled,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      issue.suggestion!,
                      style: FluxForgeTheme.bodySmall.copyWith(
                        color: FluxForgeTheme.textTertiary,
                        fontStyle: FontStyle.italic,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  String _categoryDisplayName(GddValidationCategory category) {
    switch (category) {
      case GddValidationCategory.structure:
        return 'Structure';
      case GddValidationCategory.grid:
        return 'Grid';
      case GddValidationCategory.symbols:
        return 'Symbols';
      case GddValidationCategory.math:
        return 'Math Model';
      case GddValidationCategory.features:
        return 'Features';
      case GddValidationCategory.audio:
        return 'Audio Readiness';
      case GddValidationCategory.paytable:
        return 'Paytable';
      case GddValidationCategory.consistency:
        return 'Consistency';
    }
  }
}
