/// Validation Panel Dialog — shows all audio assignment warnings in a scrollable list.
///
/// Grouped by severity (errors → warnings → info).
/// Each row is clickable — navigates to the stage in ASSIGN tab.

import 'package:flutter/material.dart';
import '../../services/ffnc/assignment_validator.dart';
import '../../theme/fluxforge_theme.dart';

class ValidationPanelDialog extends StatelessWidget {
  final List<AssignmentWarning> warnings;
  final void Function(String stage)? onNavigateToStage;

  const ValidationPanelDialog({
    super.key,
    required this.warnings,
    this.onNavigateToStage,
  });

  @override
  Widget build(BuildContext context) {
    final errors = warnings.where((w) => w.severity == WarningSeverity.error).toList();
    final warns = warnings.where((w) => w.severity == WarningSeverity.warning).toList();
    final infos = warnings.where((w) => w.severity == WarningSeverity.info).toList();

    return Dialog(
      backgroundColor: FluxForgeTheme.bgDeep,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Row(
                children: [
                  Icon(
                    warnings.isEmpty ? Icons.check_circle : Icons.warning,
                    color: warnings.isEmpty ? FluxForgeTheme.accentGreen
                        : errors.isNotEmpty ? FluxForgeTheme.accentRed
                        : FluxForgeTheme.accentOrange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    warnings.isEmpty ? 'Validation Passed' : 'Validation Results',
                    style: FluxForgeTheme.dockSans(size: 14, weight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Summary counts
              Row(
                children: [
                  if (errors.isNotEmpty) _buildCountBadge(errors.length, 'errors', FluxForgeTheme.accentRed),
                  if (errors.isNotEmpty) const SizedBox(width: 8),
                  if (warns.isNotEmpty) _buildCountBadge(warns.length, 'warnings', FluxForgeTheme.accentOrange),
                  if (warns.isNotEmpty) const SizedBox(width: 8),
                  if (infos.isNotEmpty) _buildCountBadge(infos.length, 'info', Colors.white38),
                  if (warnings.isEmpty)
                    Text('No issues found', style: FluxForgeTheme.dockSans(size: 11, color: FluxForgeTheme.accentGreen)),
                ],
              ),
              const SizedBox(height: 12),

              // Warning list
              Expanded(
                child: warnings.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline, color: FluxForgeTheme.accentGreen, size: 40),
                            const SizedBox(height: 8),
                            Text('All stages configured correctly',
                                style: FluxForgeTheme.dockSans(size: 11, color: Colors.white38)),
                          ],
                        ),
                      )
                    : ListView(
                        children: [
                          if (errors.isNotEmpty) ...[
                            _buildSectionHeader('ERRORS', FluxForgeTheme.accentRed),
                            ...errors.map((w) => _buildWarningRow(context, w)),
                            const SizedBox(height: 8),
                          ],
                          if (warns.isNotEmpty) ...[
                            _buildSectionHeader('WARNINGS', FluxForgeTheme.accentOrange),
                            ...warns.map((w) => _buildWarningRow(context, w)),
                            const SizedBox(height: 8),
                          ],
                          if (infos.isNotEmpty) ...[
                            _buildSectionHeader('INFO', Colors.white38),
                            ...infos.map((w) => _buildWarningRow(context, w)),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 12),

              // Footer
              Row(
                children: [
                  if (warnings.isNotEmpty)
                    Text(
                      'Click any row to jump to that stage',
                      style: FluxForgeTheme.dockSans(size: 9, color: Colors.white24),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Close', style: FluxForgeTheme.dockSans(color: Colors.white54)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountBadge(int count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$count $label',
        style: FluxForgeTheme.dockSans(size: 10, weight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: Text(title, style: FluxForgeTheme.dockSans(size: 10, weight: FontWeight.w700, letterSpacing: 0.5, color: color)),
    );
  }

  Widget _buildWarningRow(BuildContext context, AssignmentWarning warning) {
    final icon = switch (warning.severity) {
      WarningSeverity.error => Icons.error_outline,
      WarningSeverity.warning => Icons.warning_amber,
      WarningSeverity.info => Icons.info_outline,
    };
    final color = switch (warning.severity) {
      WarningSeverity.error => FluxForgeTheme.accentRed,
      WarningSeverity.warning => FluxForgeTheme.accentOrange,
      WarningSeverity.info => Colors.white38,
    };

    return InkWell(
      onTap: () {
        onNavigateToStage?.call(warning.stage);
        Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 6),
            SizedBox(
              width: 130,
              child: Text(
                warning.stage,
                style: FluxForgeTheme.dockMono(size: 9, weight: FontWeight.w600, color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                warning.message,
                style: FluxForgeTheme.dockSans(size: 9, color: Colors.white54),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
