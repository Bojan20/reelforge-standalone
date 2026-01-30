/// P0 WF-08: Test Template Panel (2026-01-30)
///
/// UI for managing and executing test templates.
/// Provides systematic QA workflow for slot audio testing.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/test_template.dart';
import '../../services/test_template_service.dart';
import '../../services/event_registry.dart';
import '../../theme/fluxforge_theme.dart';

/// Test Template Panel widget
class TestTemplatePanel extends StatefulWidget {
  final EventRegistry eventRegistry;

  const TestTemplatePanel({
    super.key,
    required this.eventRegistry,
  });

  @override
  State<TestTemplatePanel> createState() => _TestTemplatePanelState();
}

class _TestTemplatePanelState extends State<TestTemplatePanel> {
  TestTemplateCategory? _selectedCategory;
  String? _selectedTemplateId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: TestTemplateService.instance,
      child: Consumer<TestTemplateService>(
        builder: (context, service, _) {
          return Column(
            children: [
              _buildToolbar(service),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  children: [
                    // Category list
                    SizedBox(
                      width: 200,
                      child: _buildCategoryList(service),
                    ),
                    const VerticalDivider(width: 1),
                    // Template list
                    Expanded(
                      child: _buildTemplateList(service),
                    ),
                    const VerticalDivider(width: 1),
                    // Detail panel
                    SizedBox(
                      width: 320,
                      child: _buildDetailPanel(service),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar(TestTemplateService service) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.science, size: 16, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 8),
          Text(
            'TEST TEMPLATES',
            style: FluxForgeTheme.label.copyWith(
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (service.isExecuting) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: service.progress,
                color: FluxForgeTheme.accentGreen,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(service.progress * 100).toInt()}%',
              style: FluxForgeTheme.bodySmall.copyWith(
                color: FluxForgeTheme.accentGreen,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.stop, size: 16),
              color: FluxForgeTheme.accentRed,
              tooltip: 'Stop execution',
              onPressed: () => service.stopExecution(),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            color: FluxForgeTheme.accentGreen,
            tooltip: 'Create custom template',
            onPressed: () => _showCreateTemplateDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.history, size: 16),
            color: FluxForgeTheme.textSecondary,
            tooltip: 'View result history',
            onPressed: () => _showResultHistory(service),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryList(TestTemplateService service) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _buildCategoryItem(null, 'All Templates', Icons.folder, FluxForgeTheme.textSecondary),
        const Divider(height: 16),
        ...TestTemplateCategory.values.map(
          (cat) => _buildCategoryItem(cat, cat.displayName, cat.icon, cat.color),
        ),
      ],
    );
  }

  Widget _buildCategoryItem(
    TestTemplateCategory? category,
    String name,
    IconData icon,
    Color color,
  ) {
    final isSelected = _selectedCategory == category;

    return InkWell(
      onTap: () => setState(() => _selectedCategory = category),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: isSelected ? 1.5 : 0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? color : FluxForgeTheme.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: FluxForgeTheme.bodySmall.copyWith(
                  color: isSelected ? color : FluxForgeTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateList(TestTemplateService service) {
    final templates = _selectedCategory == null
        ? service.getAllTemplates()
        : service.getTemplatesByCategory(_selectedCategory!);

    if (templates.isEmpty) {
      return Center(
        child: Text(
          'No templates in this category',
          style: FluxForgeTheme.bodySmall.copyWith(color: FluxForgeTheme.textTertiary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final template = templates[index];
        final isSelected = template.id == _selectedTemplateId;
        final lastResult = service.getLatestResult(template.id);

        return InkWell(
          onTap: () => setState(() => _selectedTemplateId = template.id),
          child: Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSelected ? FluxForgeTheme.bgMid : FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? template.category.color : FluxForgeTheme.borderSubtle,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      template.category.icon,
                      size: 16,
                      color: template.category.color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        template.name,
                        style: FluxForgeTheme.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: FluxForgeTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (lastResult != null)
                      Icon(
                        lastResult.passed ? Icons.check_circle : Icons.error,
                        size: 16,
                        color: lastResult.passed ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  template.description,
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _buildInfoChip('${template.actions.length} actions', Icons.playlist_play),
                    _buildInfoChip('${(template.estimatedDurationMs / 1000).toStringAsFixed(1)}s', Icons.timer),
                    ...template.tags.map((tag) => _buildTagChip(tag)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailPanel(TestTemplateService service) {
    if (_selectedTemplateId == null) {
      return Center(
        child: Text(
          'Select a template to view details',
          style: FluxForgeTheme.bodySmall.copyWith(color: FluxForgeTheme.textTertiary),
        ),
      );
    }

    final template = service.getAllTemplates().firstWhere((t) => t.id == _selectedTemplateId);
    final lastResult = service.getLatestResult(template.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Execute button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: service.isExecuting
                  ? null
                  : () => _executeTemplate(template, service),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Execute Template'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FluxForgeTheme.accentGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Actions timeline
          _buildActionsList(template),
          const SizedBox(height: 16),
          // Last result
          if (lastResult != null) _buildLastResult(lastResult),
        ],
      ),
    );
  }

  Widget _buildActionsList(TestTemplate template) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ACTIONS',
          style: FluxForgeTheme.label.copyWith(
            color: FluxForgeTheme.textTertiary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: template.actions.asMap().entries.map((entry) {
              final index = entry.key;
              final action = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: template.category.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: FluxForgeTheme.bodySmall.copyWith(
                            color: template.category.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.stage,
                            style: FluxForgeTheme.bodySmall.copyWith(
                              color: FluxForgeTheme.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (action.delayMs > 0)
                            Text(
                              '+${action.delayMs}ms',
                              style: FluxForgeTheme.bodySmall.copyWith(
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
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLastResult(TestTemplateResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LAST RESULT',
          style: FluxForgeTheme.label.copyWith(
            color: FluxForgeTheme.textTertiary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: result.passed
                ? FluxForgeTheme.accentGreen.withValues(alpha: 0.1)
                : FluxForgeTheme.accentRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: result.passed ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    result.passed ? Icons.check_circle : Icons.error,
                    size: 20,
                    color: result.passed ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    result.passed ? 'PASSED' : 'FAILED',
                    style: FluxForgeTheme.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: result.passed ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${result.duration.inMilliseconds}ms',
                    style: FluxForgeTheme.bodySmall.copyWith(
                      color: FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildResultStat('Success', '${result.successCount}/${result.actionCount}'),
              _buildResultStat('Success Rate', '${(result.successRate * 100).toInt()}%'),
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'ERRORS:',
                  style: FluxForgeTheme.label.copyWith(
                    color: FluxForgeTheme.accentRed,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 4),
                ...result.errors.map((err) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text(
                    err,
                    style: FluxForgeTheme.bodySmall.copyWith(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                )),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: FluxForgeTheme.bodySmall.copyWith(
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          Text(
            value,
            style: FluxForgeTheme.bodySmall.copyWith(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: FluxForgeTheme.textTertiary),
          const SizedBox(width: 4),
          Text(
            label,
            style: FluxForgeTheme.bodySmall.copyWith(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3)),
      ),
      child: Text(
        tag,
        style: FluxForgeTheme.bodySmall.copyWith(
          color: FluxForgeTheme.accentBlue,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _executeTemplate(TestTemplate template, TestTemplateService service) async {
    try {
      final result = await service.executeTemplate(template, widget.eventRegistry);

      if (!mounted) return;

      // Show result dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: FluxForgeTheme.bgDeep,
          title: Row(
            children: [
              Icon(
                result.passed ? Icons.check_circle : Icons.error,
                color: result.passed ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
              ),
              const SizedBox(width: 8),
              Text(
                result.passed ? 'Test Passed' : 'Test Failed',
                style: FluxForgeTheme.body.copyWith(
                  color: FluxForgeTheme.textPrimary,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                template.name,
                style: FluxForgeTheme.body.copyWith(
                  color: FluxForgeTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text('Success: ${result.successCount}/${result.actionCount}'),
              Text('Duration: ${result.duration.inMilliseconds}ms'),
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Errors:', style: TextStyle(color: FluxForgeTheme.accentRed)),
                ...result.errors.map((e) => Text('  • $e')),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Execution failed: $e')),
      );
    }
  }

  void _showCreateTemplateDialog() {
    // TODO: Implement custom template creation dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Custom template creation coming soon')),
    );
  }

  void _showResultHistory(TestTemplateService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgDeep,
        title: Text(
          'Test Result History',
          style: FluxForgeTheme.body.copyWith(color: FluxForgeTheme.textPrimary),
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: ListView.builder(
            itemCount: service.resultHistory.length,
            itemBuilder: (context, index) {
              final result = service.resultHistory[index];
              return ListTile(
                leading: Icon(
                  result.passed ? Icons.check_circle : Icons.error,
                  color: result.passed ? FluxForgeTheme.accentGreen : FluxForgeTheme.accentRed,
                ),
                title: Text(
                  result.templateId,
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
                subtitle: Text(
                  '${result.successCount}/${result.actionCount} • ${result.duration.inMilliseconds}ms',
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                trailing: Text(
                  _formatTimestamp(result.startTime),
                  style: FluxForgeTheme.bodySmall.copyWith(
                    color: FluxForgeTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              service.clearHistory();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
