/// Cross-Section Validation Panel
///
/// UI for displaying validation results across DAW/Middleware/SlotLab sections.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/cross_section_validator.dart';
import '../../services/event_registry.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../theme/fluxforge_theme.dart';

class CrossSectionValidationPanel extends StatefulWidget {
  const CrossSectionValidationPanel({super.key});

  @override
  State<CrossSectionValidationPanel> createState() => _CrossSectionValidationPanelState();
}

class _CrossSectionValidationPanelState extends State<CrossSectionValidationPanel> {
  CrossSectionValidationResult? _result;
  bool _isValidating = false;
  ValidationSeverity? _filterSeverity;
  String? _filterSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          _buildControls(context),
          const SizedBox(height: 16),
          Expanded(
            child: _result == null
              ? _buildEmptyState(context)
              : _buildResultsView(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          Icons.verified_user,
          size: 28,
          color: FluxForgeTheme.accentBlue,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cross-Section Validation',
              style: theme.textTheme.titleLarge?.copyWith(
                color: FluxForgeTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_result != null)
              Text(
                _result!.summary,
                style: TextStyle(
                  fontSize: 12,
                  color: _result!.hasErrors
                    ? FluxForgeTheme.accentRed
                    : FluxForgeTheme.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    return Row(
      children: [
        ElevatedButton.icon(
          icon: _isValidating
            ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
            : const Icon(Icons.play_arrow),
          label: Text(_isValidating ? 'Validating...' : 'Run Validation'),
          onPressed: _isValidating ? null : _runValidation,
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentBlue,
          ),
        ),
        const SizedBox(width: 12),
        // Severity filter
        DropdownButton<ValidationSeverity?>(
          value: _filterSeverity,
          hint: const Text('All Severities'),
          items: const [
            DropdownMenuItem(value: null, child: Text('All Severities')),
            DropdownMenuItem(value: ValidationSeverity.error, child: Text('Errors')),
            DropdownMenuItem(value: ValidationSeverity.warning, child: Text('Warnings')),
            DropdownMenuItem(value: ValidationSeverity.info, child: Text('Info')),
          ],
          onChanged: (val) => setState(() => _filterSeverity = val),
        ),
        const SizedBox(width: 12),
        // Section filter
        DropdownButton<String?>(
          value: _filterSection,
          hint: const Text('All Sections'),
          items: const [
            DropdownMenuItem(value: null, child: Text('All Sections')),
            DropdownMenuItem(value: 'Middleware', child: Text('Middleware')),
            DropdownMenuItem(value: 'Event Registry', child: Text('Event Registry')),
            DropdownMenuItem(value: 'Stage Config', child: Text('Stage Config')),
            DropdownMenuItem(value: 'Cross-Section', child: Text('Cross-Section')),
          ],
          onChanged: (val) => setState(() => _filterSection = val),
        ),
        const Spacer(),
        if (_result != null) ...[
          TextButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Export Report'),
            onPressed: _exportReport,
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.playlist_add_check,
            size: 64,
            color: FluxForgeTheme.textSecondary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Validation Results',
            style: TextStyle(
              fontSize: 16,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Run Validation" to check for issues',
            style: TextStyle(
              fontSize: 12,
              color: FluxForgeTheme.textSecondary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView(BuildContext context) {
    if (_result == null) return const SizedBox();

    var issues = _result!.issues;

    // Apply filters
    if (_filterSeverity != null) {
      issues = issues.where((i) => i.severity == _filterSeverity).toList();
    }
    if (_filterSection != null) {
      issues = issues.where((i) => i.section == _filterSection).toList();
    }

    if (issues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              size: 64,
              color: FluxForgeTheme.accentGreen,
            ),
            const SizedBox(height: 16),
            Text(
              _result!.isClean ? 'All checks passed!' : 'No issues match filters',
              style: TextStyle(
                fontSize: 16,
                color: FluxForgeTheme.accentGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: issues.length,
      itemBuilder: (context, index) {
        final issue = issues[index];
        return _buildIssueCard(context, issue);
      },
    );
  }

  Widget _buildIssueCard(BuildContext context, ValidationIssue issue) {
    final theme = Theme.of(context);

    Color severityColor;
    IconData severityIcon;

    switch (issue.severity) {
      case ValidationSeverity.error:
        severityColor = FluxForgeTheme.accentRed;
        severityIcon = Icons.error;
        break;
      case ValidationSeverity.warning:
        severityColor = FluxForgeTheme.accentOrange;
        severityIcon = Icons.warning;
        break;
      case ValidationSeverity.info:
        severityColor = FluxForgeTheme.accentCyan;
        severityIcon = Icons.info;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: severityColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(severityIcon, size: 20, color: severityColor),
              const SizedBox(width: 8),
              Text(
                issue.severity.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: severityColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentBlue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: FluxForgeTheme.accentBlue),
                ),
                child: Text(
                  issue.section,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: FluxForgeTheme.accentBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentCyan.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  issue.category,
                  style: const TextStyle(
                    fontSize: 10,
                    color: FluxForgeTheme.accentCyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Message
          Text(
            issue.message,
            style: TextStyle(
              fontSize: 13,
              color: FluxForgeTheme.textPrimary,
            ),
          ),
          if (issue.eventId != null) ...[
            const SizedBox(height: 4),
            Text(
              'Event ID: ${issue.eventId}',
              style: TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (issue.suggestedFix != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.accentGreen.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: FluxForgeTheme.accentGreen,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      issue.suggestedFix!,
                      style: TextStyle(
                        fontSize: 12,
                        color: FluxForgeTheme.accentGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _runValidation() async {
    setState(() => _isValidating = true);

    try {
      final middlewareProvider = context.read<MiddlewareProvider>();
      final eventRegistry = EventRegistry.instance;

      final result = await CrossSectionValidator.instance.validate(
        middlewareProvider: middlewareProvider,
        eventRegistry: eventRegistry,
      );

      setState(() {
        _result = result;
        _isValidating = false;
      });
    } catch (e) {
      setState(() => _isValidating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Validation failed: $e'),
            backgroundColor: FluxForgeTheme.accentRed,
          ),
        );
      }
    }
  }

  void _exportReport() {
    if (_result == null) return;

    // TODO: Implement report export (CSV/JSON)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report export not yet implemented'),
      ),
    );
  }
}
