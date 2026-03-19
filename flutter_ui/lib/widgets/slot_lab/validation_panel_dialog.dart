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
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
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
                    const Text('No issues found', style: TextStyle(color: FluxForgeTheme.accentGreen, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 12),

              // Warning list
              Expanded(
                child: warnings.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, color: FluxForgeTheme.accentGreen, size: 40),
                            SizedBox(height: 8),
                            Text('All stages configured correctly',
                                style: TextStyle(color: Colors.white38, fontSize: 11)),
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
                    const Text(
                      'Click any row to jump to that stage',
                      style: TextStyle(color: Colors.white24, fontSize: 9),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close', style: TextStyle(color: Colors.white54)),
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
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
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
                style: TextStyle(color: color, fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                warning.message,
                style: const TextStyle(color: Colors.white54, fontSize: 9),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
