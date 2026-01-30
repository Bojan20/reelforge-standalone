/// Test Automation Panel
///
/// UI for managing and running automated tests:
/// - Scenario browser with categories
/// - Test runner with live progress
/// - Result viewer with pass/fail details
/// - Quick actions for common test tasks
///
/// Created: 2026-01-30 (P4.11)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/test_automation_models.dart';
import '../../providers/slot_lab_provider.dart';
import '../../services/event_registry.dart';
import '../../services/test_automation_service.dart';
import '../../theme/fluxforge_theme.dart';

/// Main test automation panel
class TestAutomationPanel extends StatefulWidget {
  final double height;

  const TestAutomationPanel({
    super.key,
    this.height = 500,
  });

  @override
  State<TestAutomationPanel> createState() => _TestAutomationPanelState();
}

class _TestAutomationPanelState extends State<TestAutomationPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Services
  final _runner = TestRunner.instance;
  final _storage = TestStorage.instance;

  // State
  List<TestScenario> _scenarios = [];
  List<TestScenarioResult> _recentResults = [];
  TestScenario? _selectedScenario;
  TestScenarioResult? _lastResult;
  final List<String> _logMessages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // Initialize runner
    _runner.onLog = _onLog;
    _runner.onStepCompleted = _onStepCompleted;
    _runner.onScenarioCompleted = _onScenarioCompleted;
    _runner.addListener(_onRunnerChanged);

    _initializeServices();
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize with providers
      final slotLabProvider = context.read<SlotLabProvider>();
      _runner.init(
        slotLabProvider: slotLabProvider,
        eventRegistry: eventRegistry,
      );

      await _storage.init();
      await _loadData();
    } catch (e) {
      debugPrint('[TestAutomationPanel] Init error: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    final scenarios = await _storage.loadAllScenarios();
    final results = await _storage.loadResults(limit: 10);

    // Add built-in scenarios if none exist
    if (scenarios.isEmpty) {
      scenarios.addAll(BuiltInTestScenarios.all());
    }

    if (mounted) {
      setState(() {
        _scenarios = scenarios;
        _recentResults = results;
      });
    }
  }

  void _onLog(String message) {
    if (mounted) {
      setState(() {
        _logMessages.add('[${DateTime.now().toIso8601String().split('T').last.split('.').first}] $message');
        if (_logMessages.length > 100) {
          _logMessages.removeAt(0);
        }
      });
    }
  }

  void _onStepCompleted(TestStepResult result) {
    if (mounted) setState(() {});
  }

  void _onScenarioCompleted(TestScenarioResult result) {
    if (mounted) {
      setState(() {
        _lastResult = result;
        _recentResults.insert(0, result);
        if (_recentResults.length > 10) {
          _recentResults.removeLast();
        }
      });
      // Save result
      _storage.saveResult(result);
    }
  }

  void _onRunnerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _runner.removeListener(_onRunnerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border.all(color: FluxForgeTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildScenariosTab(),
                _buildRunnerTab(),
                _buildResultsTab(),
                _buildLogTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.border),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.science, size: 16, color: Color(0xFF9370DB)),
          const SizedBox(width: 8),
          const Text(
            'TEST AUTOMATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          if (_runner.isRunning) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Color(0xFF40FF90)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Running: ${_runner.currentStep?.name ?? ""}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF40FF90)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.stop, size: 16, color: Color(0xFFFF4060)),
              onPressed: _runner.stop,
              tooltip: 'Stop Test',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
          const SizedBox(width: 8),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: const Color(0xFF4A9EFF),
            unselectedLabelColor: Colors.white54,
            indicatorSize: TabBarIndicatorSize.label,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: const [
              Tab(text: 'Scenarios', height: 32),
              Tab(text: 'Runner', height: 32),
              Tab(text: 'Results', height: 32),
              Tab(text: 'Log', height: 32),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScenariosTab() {
    final categories = TestCategory.values;

    return Row(
      children: [
        // Category list
        SizedBox(
          width: 140,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: FluxForgeTheme.border),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _buildCategoryItem(null, 'All', Icons.list),
                const Divider(),
                for (final category in categories)
                  _buildCategoryItem(
                    category,
                    category.label,
                    _getCategoryIcon(category),
                  ),
              ],
            ),
          ),
        ),
        // Scenario list
        Expanded(
          child: Column(
            children: [
              _buildScenarioActions(),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _scenarios.length,
                  itemBuilder: (context, index) {
                    final scenario = _scenarios[index];
                    return _ScenarioCard(
                      scenario: scenario,
                      isSelected: scenario == _selectedScenario,
                      onTap: () => setState(() => _selectedScenario = scenario),
                      onRun: () => _runScenario(scenario),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Scenario details
        if (_selectedScenario != null)
          SizedBox(
            width: 280,
            child: _ScenarioDetails(
              scenario: _selectedScenario!,
              onRun: () => _runScenario(_selectedScenario!),
              onDelete: () => _deleteScenario(_selectedScenario!),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryItem(TestCategory? category, String label, IconData icon) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 16),
      title: Text(label, style: const TextStyle(fontSize: 12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
    );
  }

  IconData _getCategoryIcon(TestCategory category) {
    return switch (category) {
      TestCategory.smoke => Icons.local_fire_department,
      TestCategory.regression => Icons.replay,
      TestCategory.audio => Icons.audiotrack,
      TestCategory.performance => Icons.speed,
      TestCategory.feature => Icons.star,
      TestCategory.integration => Icons.integration_instructions,
      TestCategory.custom => Icons.edit,
    };
  }

  Widget _buildScenarioActions() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New'),
            onPressed: _createScenario,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.file_upload, size: 16),
            label: const Text('Import'),
            onPressed: _importScenario,
          ),
          const Spacer(),
          if (_scenarios.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Run All'),
              onPressed: _runner.isRunning ? null : _runAllScenarios,
            ),
        ],
      ),
    );
  }

  Widget _buildRunnerTab() {
    if (!_runner.isRunning && _lastResult == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.science, size: 48, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'No test running',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _scenarios.isNotEmpty ? () => _runScenario(_scenarios.first) : null,
              child: const Text('Run a Test'),
            ),
          ],
        ),
      );
    }

    final scenario = _runner.currentScenario ?? _lastResult?.scenario;
    final steps = scenario?.steps ?? [];
    final results = _runner.stepResults;

    return Column(
      children: [
        // Progress header
        Container(
          padding: const EdgeInsets.all(12),
          color: FluxForgeTheme.bgDeep,
          child: Row(
            children: [
              Text(
                scenario?.name ?? 'Test',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${results.length}/${steps.length} steps',
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(width: 16),
              if (_lastResult != null)
                _StatusBadge(status: _lastResult!.status),
            ],
          ),
        ),
        // Progress bar
        LinearProgressIndicator(
          value: steps.isNotEmpty ? results.length / steps.length : 0,
          backgroundColor: FluxForgeTheme.border,
          valueColor: AlwaysStoppedAnimation(
            _lastResult?.passed ?? true
                ? const Color(0xFF40FF90)
                : const Color(0xFFFF4060),
          ),
        ),
        // Step list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: steps.length,
            itemBuilder: (context, index) {
              final step = steps[index];
              final result = index < results.length ? results[index] : null;
              final isCurrent = _runner.isRunning && index == _runner.currentStepIndex;

              return _StepItem(
                step: step,
                result: result,
                isCurrent: isCurrent,
                index: index,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultsTab() {
    if (_recentResults.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: Colors.white24),
            SizedBox(height: 16),
            Text('No test results yet', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _recentResults.length,
      itemBuilder: (context, index) {
        final result = _recentResults[index];
        return _ResultCard(
          result: result,
          onExport: () => _exportResult(result),
        );
      },
    );
  }

  Widget _buildLogTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Text('Test Log', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () => _copyLog(),
                tooltip: 'Copy Log',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: () => setState(() => _logMessages.clear()),
                tooltip: 'Clear Log',
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            padding: const EdgeInsets.all(8),
            child: ListView.builder(
              itemCount: _logMessages.length,
              reverse: true,
              itemBuilder: (context, index) {
                final message = _logMessages[_logMessages.length - 1 - index];
                return Text(
                  message,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: message.contains('PASS')
                        ? const Color(0xFF40FF90)
                        : message.contains('FAIL')
                            ? const Color(0xFFFF4060)
                            : Colors.white70,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // Actions
  Future<void> _runScenario(TestScenario scenario) async {
    if (_runner.isRunning) return;

    setState(() {
      _logMessages.clear();
      _lastResult = null;
    });
    _tabController.animateTo(1); // Switch to Runner tab

    await _runner.runScenario(scenario);
  }

  Future<void> _runAllScenarios() async {
    if (_runner.isRunning) return;

    final suite = TestSuite(
      id: 'all_scenarios',
      name: 'All Scenarios',
      scenarios: _scenarios.where((s) => s.isEnabled).toList(),
      createdAt: DateTime.now(),
    );

    setState(() {
      _logMessages.clear();
    });
    _tabController.animateTo(1);

    await _runner.runSuite(suite);
  }

  void _createScenario() {
    // TODO: Open scenario builder dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scenario builder coming soon')),
    );
  }

  void _importScenario() {
    // TODO: Import from file
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Import coming soon')),
    );
  }

  Future<void> _deleteScenario(TestScenario scenario) async {
    await _storage.deleteScenario(scenario.id);
    setState(() {
      _scenarios.remove(scenario);
      if (_selectedScenario == scenario) {
        _selectedScenario = null;
      }
    });
  }

  void _exportResult(TestScenarioResult result) {
    final markdown = TestReportGenerator.instance.generateMarkdown(result);
    Clipboard.setData(ClipboardData(text: markdown));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report copied to clipboard')),
    );
  }

  void _copyLog() {
    Clipboard.setData(ClipboardData(text: _logMessages.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log copied to clipboard')),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _ScenarioCard extends StatelessWidget {
  final TestScenario scenario;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRun;

  const _ScenarioCard({
    required this.scenario,
    required this.isSelected,
    required this.onTap,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected ? const Color(0xFF4A9EFF).withOpacity(0.2) : FluxForgeTheme.bgMid,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          scenario.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        _CategoryBadge(category: scenario.category),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${scenario.stepCount} steps, ${scenario.assertionCount} assertions',
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow, color: Color(0xFF40FF90)),
                onPressed: onRun,
                tooltip: 'Run Test',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenarioDetails extends StatelessWidget {
  final TestScenario scenario;
  final VoidCallback onRun;
  final VoidCallback onDelete;

  const _ScenarioDetails({
    required this.scenario,
    required this.onRun,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: FluxForgeTheme.border),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scenario.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          _CategoryBadge(category: scenario.category),
          const SizedBox(height: 12),
          if (scenario.description != null) ...[
            Text(
              scenario.description!,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),
          ],
          _buildDetailRow('Steps', scenario.stepCount.toString()),
          _buildDetailRow('Assertions', scenario.assertionCount.toString()),
          _buildDetailRow('Tags', scenario.tags.join(', ')),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Run'),
                  onPressed: onRun,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF40FF90),
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Color(0xFFFF4060)),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 11, color: Colors.white54)),
          Text(value, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final TestStep step;
  final TestStepResult? result;
  final bool isCurrent;
  final int index;

  const _StepItem({
    required this.step,
    required this.result,
    required this.isCurrent,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final status = result?.status ?? (isCurrent ? TestStatus.running : TestStatus.pending);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFF4A9EFF).withOpacity(0.1) : FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: isCurrent
            ? Border.all(color: const Color(0xFF4A9EFF))
            : null,
      ),
      child: Row(
        children: [
          _StatusIcon(status: status),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}. ${step.name}',
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (result != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${result!.passedAssertions}/${result!.assertionResults.length} assertions passed • ${result!.duration.inMilliseconds}ms',
                    style: const TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final TestScenarioResult result;
  final VoidCallback onExport;

  const _ResultCard({
    required this.result,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: FluxForgeTheme.bgMid,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusBadge(status: result.status),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.scenario.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.download, size: 16),
                  onPressed: onExport,
                  tooltip: 'Export Report',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStat('Steps', '${result.passedSteps}/${result.stepResults.length}'),
                const SizedBox(width: 16),
                _buildStat('Assertions', '${result.passedAssertions}/${result.totalAssertions}'),
                const SizedBox(width: 16),
                _buildStat('Duration', '${result.totalDuration.inMilliseconds}ms'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              result.startedAt.toString().split('.').first,
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Text(
      '$label: $value',
      style: const TextStyle(fontSize: 11, color: Colors.white70),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TestStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TestStatus.passed => const Color(0xFF40FF90),
      TestStatus.failed => const Color(0xFFFF4060),
      TestStatus.running => const Color(0xFF4A9EFF),
      TestStatus.error => const Color(0xFFFF9040),
      TestStatus.timeout => const Color(0xFFFF9040),
      _ => Colors.white54,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(
        status.label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final TestStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      TestStatus.passed => const Icon(Icons.check_circle, color: Color(0xFF40FF90), size: 18),
      TestStatus.failed => const Icon(Icons.cancel, color: Color(0xFFFF4060), size: 18),
      TestStatus.running => const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      TestStatus.error => const Icon(Icons.error, color: Color(0xFFFF9040), size: 18),
      TestStatus.timeout => const Icon(Icons.timer_off, color: Color(0xFFFF9040), size: 18),
      TestStatus.skipped => const Icon(Icons.skip_next, color: Colors.white38, size: 18),
      _ => const Icon(Icons.circle_outlined, color: Colors.white38, size: 18),
    };
  }
}

class _CategoryBadge extends StatelessWidget {
  final TestCategory category;

  const _CategoryBadge({required this.category});

  @override
  Widget build(BuildContext context) {
    final color = switch (category) {
      TestCategory.smoke => const Color(0xFFFF9040),
      TestCategory.regression => const Color(0xFF9370DB),
      TestCategory.audio => const Color(0xFF40C8FF),
      TestCategory.performance => const Color(0xFF40FF90),
      TestCategory.feature => const Color(0xFFFFD700),
      TestCategory.integration => const Color(0xFF4A9EFF),
      TestCategory.custom => Colors.white54,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        category.label,
        style: TextStyle(fontSize: 9, color: color),
      ),
    );
  }
}
