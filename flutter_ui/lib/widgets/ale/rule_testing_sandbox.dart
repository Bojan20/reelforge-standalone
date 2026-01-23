/// Rule Testing Sandbox — Interactive ALE Rule Debugging
///
/// Features:
/// - Interactive signal simulation
/// - Rule evaluation visualization
/// - Condition breakdown display
/// - Action preview
/// - History timeline
/// - Rule firing log

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Rule evaluation result
class RuleEvaluationResult {
  final String ruleId;
  final String ruleName;
  final bool conditionMet;
  final String conditionDetails;
  final AleActionType action;
  final int? actionValue;
  final DateTime timestamp;

  RuleEvaluationResult({
    required this.ruleId,
    required this.ruleName,
    required this.conditionMet,
    required this.conditionDetails,
    required this.action,
    this.actionValue,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Test signal state
class TestSignalState {
  final String signalId;
  double currentValue;
  double? previousValue;
  final List<double> history;

  TestSignalState({
    required this.signalId,
    required this.currentValue,
    this.previousValue,
    List<double>? history,
  }) : history = history ?? [];

  void update(double value) {
    previousValue = currentValue;
    currentValue = value;
    history.add(value);
    if (history.length > 100) {
      history.removeAt(0);
    }
  }

  double get delta => currentValue - (previousValue ?? currentValue);
  bool get isRising => delta > 0;
  bool get isFalling => delta < 0;
}

class RuleTestingSandbox extends StatefulWidget {
  final double height;

  const RuleTestingSandbox({
    super.key,
    this.height = 500,
  });

  @override
  State<RuleTestingSandbox> createState() => _RuleTestingSandboxState();
}

class _RuleTestingSandboxState extends State<RuleTestingSandbox>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Test state
  final Map<String, TestSignalState> _testSignals = {};
  final List<RuleEvaluationResult> _evaluationHistory = [];
  final List<AleRule> _testRules = [];

  // Simulation
  bool _isSimulating = false;
  Timer? _simulationTimer;
  int _simulationStep = 0;

  // Selected rule for detail view
  String? _selectedRuleId;

  // Current simulated level
  int _simulatedLevel = 1;
  final int _maxLevel = 5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeTestSignals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _simulationTimer?.cancel();
    super.dispose();
  }

  void _initializeTestSignals() {
    const signals = [
      'winTier',
      'winXbet',
      'consecutiveWins',
      'consecutiveLosses',
      'featureProgress',
      'multiplier',
      'nearMissIntensity',
      'momentum',
    ];

    for (final signal in signals) {
      _testSignals[signal] = TestSignalState(
        signalId: signal,
        currentValue: 0.0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSignalsTab(),
                _buildRulesTab(),
                _buildSimulationTab(),
                _buildHistoryTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.science, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                'Rule Testing Sandbox',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              _buildLevelIndicator(),
              const SizedBox(width: 16),
              _buildSimulationControls(),
            ],
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabController,
            labelColor: FluxForgeTheme.accent,
            unselectedLabelColor: FluxForgeTheme.textMuted,
            indicatorColor: FluxForgeTheme.accent,
            tabs: const [
              Tab(text: 'Signals'),
              Tab(text: 'Rules'),
              Tab(text: 'Simulate'),
              Tab(text: 'History'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLevelIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _getLevelColor(_simulatedLevel).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _getLevelColor(_simulatedLevel)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'L$_simulatedLevel',
            style: TextStyle(
              color: _getLevelColor(_simulatedLevel),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          ...List.generate(_maxLevel, (i) {
            final level = i + 1;
            return Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: level <= _simulatedLevel
                    ? _getLevelColor(level)
                    : FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSimulationControls() {
    return Row(
      children: [
        IconButton(
          icon: Icon(
            _isSimulating ? Icons.pause : Icons.play_arrow,
            color: _isSimulating ? Colors.orange : Colors.green,
          ),
          tooltip: _isSimulating ? 'Pause' : 'Start Simulation',
          onPressed: _toggleSimulation,
        ),
        IconButton(
          icon: const Icon(Icons.replay, color: FluxForgeTheme.textMuted),
          tooltip: 'Reset',
          onPressed: _resetSimulation,
        ),
        IconButton(
          icon: const Icon(Icons.skip_next, color: FluxForgeTheme.textMuted),
          tooltip: 'Step',
          onPressed: _stepSimulation,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SIGNALS TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSignalsTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Test Signal Values',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.restore, size: 14),
                label: const Text('Reset All'),
                onPressed: _resetAllSignals,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _testSignals.length,
              itemBuilder: (context, index) {
                final entry = _testSignals.entries.elementAt(index);
                return _buildSignalSlider(entry.key, entry.value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalSlider(String signalId, TestSignalState state) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  signalId,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
              ),
              // Delta indicator
              if (state.previousValue != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: state.isRising
                        ? Colors.green.withValues(alpha: 0.2)
                        : state.isFalling
                            ? Colors.red.withValues(alpha: 0.2)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.isRising
                            ? Icons.arrow_upward
                            : state.isFalling
                                ? Icons.arrow_downward
                                : Icons.remove,
                        size: 10,
                        color: state.isRising
                            ? Colors.green
                            : state.isFalling
                                ? Colors.red
                                : FluxForgeTheme.textMuted,
                      ),
                      Text(
                        state.delta.abs().toStringAsFixed(2),
                        style: TextStyle(
                          color: state.isRising
                              ? Colors.green
                              : state.isFalling
                                  ? Colors.red
                                  : FluxForgeTheme.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                state.currentValue.toStringAsFixed(2),
                style: TextStyle(
                  color: FluxForgeTheme.accent,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: state.currentValue,
                    min: 0,
                    max: _getSignalMax(signalId),
                    activeColor: _getSignalColor(signalId),
                    onChanged: (value) {
                      setState(() {
                        state.update(value);
                      });
                      _evaluateAllRules();
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildQuickButton('0', () => _setSignal(signalId, 0)),
                    _buildQuickButton('½', () => _setSignal(signalId, _getSignalMax(signalId) / 2)),
                    _buildQuickButton('M', () => _setSignal(signalId, _getSignalMax(signalId))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickButton(String label, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 9,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RULES TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRulesTab() {
    return Consumer<AleProvider>(
      builder: (context, ale, _) {
        final rules = ale.profile?.rules ?? [];

        if (rules.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.rule, size: 48, color: FluxForgeTheme.textMuted),
                const SizedBox(height: 8),
                Text(
                  'No rules defined',
                  style: TextStyle(color: FluxForgeTheme.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  'Load an ALE profile to test rules',
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        return Row(
          children: [
            // Rule list
            Expanded(
              flex: 2,
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: rules.length,
                itemBuilder: (context, index) {
                  final rule = rules[index];
                  return _buildRuleTile(rule);
                },
              ),
            ),
            Container(width: 1, color: FluxForgeTheme.borderSubtle),
            // Rule details
            Expanded(
              flex: 3,
              child: _selectedRuleId != null
                  ? _buildRuleDetails(rules.where((r) => r.id == _selectedRuleId).firstOrNull)
                  : Center(
                      child: Text(
                        'Select a rule to view details',
                        style: TextStyle(color: FluxForgeTheme.textMuted),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRuleTile(AleRule rule) {
    final isSelected = _selectedRuleId == rule.id;
    final evaluation = _evaluateRule(rule);

    return GestureDetector(
      onTap: () => setState(() => _selectedRuleId = rule.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accent.withValues(alpha: 0.2)
              : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? FluxForgeTheme.accent
                : evaluation
                    ? Colors.green.withValues(alpha: 0.5)
                    : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: evaluation
                    ? Colors.green
                    : rule.enabled
                        ? FluxForgeTheme.textMuted
                        : FluxForgeTheme.errorRed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.name,
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _buildConditionString(rule),
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 9,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            // Action badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getActionColor(rule.action).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _getActionLabel(rule.action),
                style: TextStyle(
                  color: _getActionColor(rule.action),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleDetails(AleRule? rule) {
    if (rule == null) {
      return Center(
        child: Text(
          'Rule not found',
          style: TextStyle(color: FluxForgeTheme.textMuted),
        ),
      );
    }

    final evaluation = _evaluateRule(rule);
    final signalValue = rule.signalId != null
        ? _testSignals[rule.signalId]?.currentValue ?? 0.0
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: evaluation ? Colors.green : FluxForgeTheme.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rule.name,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: evaluation
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  evaluation ? 'WOULD FIRE' : 'NOT MET',
                  style: TextStyle(
                    color: evaluation ? Colors.green : Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Condition breakdown
          _buildSectionHeader('Condition'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rule.signalId != null) ...[
                  _buildConditionRow(
                    'Signal',
                    rule.signalId!,
                    true,
                  ),
                  _buildConditionRow(
                    'Current Value',
                    signalValue.toStringAsFixed(3),
                    true,
                  ),
                  _buildConditionRow(
                    'Operator',
                    _getOpLabel(rule.op),
                    true,
                  ),
                  if (rule.value != null)
                    _buildConditionRow(
                      'Threshold',
                      rule.value!.toStringAsFixed(3),
                      true,
                    ),
                  const Divider(color: FluxForgeTheme.borderSubtle),
                  _buildConditionRow(
                    'Result',
                    evaluation ? 'TRUE' : 'FALSE',
                    evaluation,
                    isResult: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Action preview
          _buildSectionHeader('Action'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildActionRow('Type', _getActionLabel(rule.action)),
                if (rule.actionValue != null)
                  _buildActionRow('Value', rule.actionValue.toString()),
                const Divider(color: FluxForgeTheme.borderSubtle),
                _buildActionPreview(rule),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Test buttons
          _buildSectionHeader('Quick Test'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTestButton('Force Fire', () => _forceFire(rule)),
              if (rule.signalId != null) ...[
                _buildTestButton('Set to Threshold', () {
                  if (rule.value != null) {
                    _setSignal(rule.signalId!, rule.value!);
                  }
                }),
                _buildTestButton('Set Above', () {
                  if (rule.value != null) {
                    _setSignal(rule.signalId!, rule.value! + 0.1);
                  }
                }),
                _buildTestButton('Set Below', () {
                  if (rule.value != null) {
                    _setSignal(rule.signalId!, rule.value! - 0.1);
                  }
                }),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: FluxForgeTheme.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildConditionRow(String label, String value, bool result, {bool isResult = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isResult
                    ? (result ? Colors.green : Colors.orange)
                    : FluxForgeTheme.textPrimary,
                fontSize: 11,
                fontWeight: isResult ? FontWeight.bold : FontWeight.normal,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (!isResult)
            Icon(
              result ? Icons.check_circle : Icons.remove_circle_outline,
              size: 14,
              color: result ? Colors.green : FluxForgeTheme.textMuted,
            ),
        ],
      ),
    );
  }

  Widget _buildActionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPreview(AleRule rule) {
    String preview;
    int newLevel = _simulatedLevel;

    switch (rule.action) {
      case AleActionType.stepUp:
        newLevel = (_simulatedLevel + 1).clamp(1, _maxLevel);
        preview = 'L$_simulatedLevel → L$newLevel';
      case AleActionType.stepDown:
        newLevel = (_simulatedLevel - 1).clamp(1, _maxLevel);
        preview = 'L$_simulatedLevel → L$newLevel';
      case AleActionType.setLevel:
        newLevel = (rule.actionValue ?? 1).clamp(1, _maxLevel);
        preview = 'L$_simulatedLevel → L$newLevel';
      case AleActionType.hold:
        preview = 'Hold at L$_simulatedLevel for ${rule.actionValue ?? 2000}ms';
      case AleActionType.release:
        preview = 'Release hold on L$_simulatedLevel';
      case AleActionType.pulse:
        preview = 'Pulse to L${rule.actionValue ?? _maxLevel} and return';
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_arrow, size: 14, color: Colors.green),
          const SizedBox(width: 8),
          Text(
            preview,
            style: TextStyle(
              color: Colors.green,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SIMULATION TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSimulationTab() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Presets
          Text(
            'Simulation Presets',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPresetButton('Losing Streak', _simulateLosingStreak),
              _buildPresetButton('Winning Streak', _simulateWinningStreak),
              _buildPresetButton('Big Win', _simulateBigWin),
              _buildPresetButton('Near Miss', _simulateNearMiss),
              _buildPresetButton('Feature Progress', _simulateFeatureProgress),
              _buildPresetButton('Random Chaos', _simulateRandomChaos),
            ],
          ),
          const SizedBox(height: 16),

          // Manual level control
          Text(
            'Manual Level Control',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(_maxLevel, (i) {
              final level = i + 1;
              final isActive = _simulatedLevel == level;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _simulatedLevel = level),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? _getLevelColor(level)
                          : FluxForgeTheme.bgSurface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isActive
                            ? _getLevelColor(level)
                            : FluxForgeTheme.borderSubtle,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'L$level',
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : FluxForgeTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Simulation step info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  _isSimulating ? Icons.play_circle : Icons.pause_circle,
                  color: _isSimulating ? Colors.green : FluxForgeTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  'Step: $_simulationStep',
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Text(
                  'Rules Fired: ${_evaluationHistory.where((e) => e.conditionMet).length}',
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: FluxForgeTheme.bgSurface,
        foregroundColor: FluxForgeTheme.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HISTORY TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHistoryTab() {
    if (_evaluationHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: FluxForgeTheme.textMuted),
            const SizedBox(height: 8),
            Text(
              'No evaluation history',
              style: TextStyle(color: FluxForgeTheme.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              'Run a simulation to see rule firing history',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Text(
                '${_evaluationHistory.length} evaluations',
                style: TextStyle(
                  color: FluxForgeTheme.textMuted,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.clear_all, size: 14),
                label: const Text('Clear'),
                onPressed: () => setState(() => _evaluationHistory.clear()),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _evaluationHistory.length,
            itemBuilder: (context, index) {
              final reversed = _evaluationHistory.length - 1 - index;
              final result = _evaluationHistory[reversed];
              return _buildHistoryTile(result);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTile(RuleEvaluationResult result) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: result.conditionMet
              ? Colors.green.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: result.conditionMet ? Colors.green : FluxForgeTheme.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.ruleName,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
                Text(
                  result.conditionDetails,
                  style: TextStyle(
                    color: FluxForgeTheme.textMuted,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          if (result.conditionMet)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getActionColor(result.action).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _getActionLabel(result.action),
                style: TextStyle(
                  color: _getActionColor(result.action),
                  fontSize: 8,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Text(
            _formatTime(result.timestamp),
            style: TextStyle(
              color: FluxForgeTheme.textMuted,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  bool _evaluateRule(AleRule rule) {
    if (!rule.enabled) return false;
    if (rule.signalId == null || rule.op == null) return false;

    final state = _testSignals[rule.signalId];
    if (state == null) return false;

    final value = state.currentValue;
    final threshold = rule.value ?? 0.0;

    return switch (rule.op!) {
      ComparisonOp.eq => value == threshold,
      ComparisonOp.ne => value != threshold,
      ComparisonOp.lt => value < threshold,
      ComparisonOp.lte => value <= threshold,
      ComparisonOp.gt => value > threshold,
      ComparisonOp.gte => value >= threshold,
      ComparisonOp.rising => state.isRising,
      ComparisonOp.falling => state.isFalling,
      ComparisonOp.changed => state.delta.abs() > 0.001,
      _ => false, // TODO: Implement other ops
    };
  }

  void _evaluateAllRules() {
    final ale = context.read<AleProvider>();
    final rules = ale.profile?.rules ?? [];

    for (final rule in rules) {
      final result = _evaluateRule(rule);
      if (result) {
        _applyAction(rule);
        _evaluationHistory.add(RuleEvaluationResult(
          ruleId: rule.id,
          ruleName: rule.name,
          conditionMet: true,
          conditionDetails: _buildConditionString(rule),
          action: rule.action,
          actionValue: rule.actionValue,
        ));
      }
    }
  }

  void _applyAction(AleRule rule) {
    setState(() {
      switch (rule.action) {
        case AleActionType.stepUp:
          _simulatedLevel = (_simulatedLevel + 1).clamp(1, _maxLevel);
        case AleActionType.stepDown:
          _simulatedLevel = (_simulatedLevel - 1).clamp(1, _maxLevel);
        case AleActionType.setLevel:
          _simulatedLevel = (rule.actionValue ?? 1).clamp(1, _maxLevel);
        default:
          break;
      }
    });
  }

  void _forceFire(AleRule rule) {
    _applyAction(rule);
    _evaluationHistory.add(RuleEvaluationResult(
      ruleId: rule.id,
      ruleName: rule.name,
      conditionMet: true,
      conditionDetails: 'FORCED',
      action: rule.action,
      actionValue: rule.actionValue,
    ));
    setState(() {});
  }

  void _setSignal(String signalId, double value) {
    final state = _testSignals[signalId];
    if (state != null) {
      setState(() {
        state.update(value.clamp(0, _getSignalMax(signalId)));
      });
      _evaluateAllRules();
    }
  }

  void _resetAllSignals() {
    setState(() {
      for (final state in _testSignals.values) {
        state.update(0);
      }
    });
  }

  void _toggleSimulation() {
    setState(() {
      _isSimulating = !_isSimulating;
    });

    if (_isSimulating) {
      _simulationTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _stepSimulation();
      });
    } else {
      _simulationTimer?.cancel();
    }
  }

  void _resetSimulation() {
    setState(() {
      _isSimulating = false;
      _simulationStep = 0;
      _simulatedLevel = 1;
      _evaluationHistory.clear();
      _resetAllSignals();
    });
    _simulationTimer?.cancel();
  }

  void _stepSimulation() {
    setState(() {
      _simulationStep++;
    });
  }

  void _simulateLosingStreak() {
    _setSignal('consecutiveLosses', 5);
    _setSignal('consecutiveWins', 0);
    _setSignal('winTier', 0);
    _setSignal('momentum', -0.8);
  }

  void _simulateWinningStreak() {
    _setSignal('consecutiveWins', 5);
    _setSignal('consecutiveLosses', 0);
    _setSignal('winTier', 2);
    _setSignal('momentum', 0.8);
  }

  void _simulateBigWin() {
    _setSignal('winTier', 4);
    _setSignal('winXbet', 50);
    _setSignal('multiplier', 10);
  }

  void _simulateNearMiss() {
    _setSignal('nearMissIntensity', 0.9);
    _setSignal('winTier', 0);
  }

  void _simulateFeatureProgress() {
    _setSignal('featureProgress', 0.8);
  }

  void _simulateRandomChaos() {
    for (final state in _testSignals.values) {
      final max = _getSignalMax(state.signalId);
      state.update((DateTime.now().millisecondsSinceEpoch % 1000) / 1000 * max);
    }
    setState(() {});
    _evaluateAllRules();
  }

  String _buildConditionString(AleRule rule) {
    if (rule.signalId == null) return 'No condition';
    final opStr = _getOpSymbol(rule.op);
    final valStr = rule.value?.toStringAsFixed(2) ?? '?';
    return '${rule.signalId} $opStr $valStr';
  }

  String _getOpSymbol(ComparisonOp? op) {
    return switch (op) {
      ComparisonOp.eq => '==',
      ComparisonOp.ne => '!=',
      ComparisonOp.lt => '<',
      ComparisonOp.lte => '<=',
      ComparisonOp.gt => '>',
      ComparisonOp.gte => '>=',
      ComparisonOp.rising => '↑',
      ComparisonOp.falling => '↓',
      ComparisonOp.changed => '≠prev',
      _ => '?',
    };
  }

  String _getOpLabel(ComparisonOp? op) {
    return switch (op) {
      ComparisonOp.eq => 'Equal',
      ComparisonOp.ne => 'Not Equal',
      ComparisonOp.lt => 'Less Than',
      ComparisonOp.lte => 'Less or Equal',
      ComparisonOp.gt => 'Greater Than',
      ComparisonOp.gte => 'Greater or Equal',
      ComparisonOp.rising => 'Rising',
      ComparisonOp.falling => 'Falling',
      ComparisonOp.changed => 'Changed',
      ComparisonOp.stable => 'Stable',
      ComparisonOp.inRange => 'In Range',
      ComparisonOp.outOfRange => 'Out of Range',
      ComparisonOp.aboveFor => 'Above For',
      ComparisonOp.belowFor => 'Below For',
      ComparisonOp.crossed => 'Crossed',
      null => 'None',
    };
  }

  String _getActionLabel(AleActionType action) {
    return switch (action) {
      AleActionType.stepUp => 'STEP UP',
      AleActionType.stepDown => 'STEP DOWN',
      AleActionType.setLevel => 'SET LEVEL',
      AleActionType.hold => 'HOLD',
      AleActionType.release => 'RELEASE',
      AleActionType.pulse => 'PULSE',
    };
  }

  Color _getActionColor(AleActionType action) {
    return switch (action) {
      AleActionType.stepUp => Colors.green,
      AleActionType.stepDown => Colors.orange,
      AleActionType.setLevel => Colors.blue,
      AleActionType.hold => Colors.purple,
      AleActionType.release => Colors.cyan,
      AleActionType.pulse => Colors.pink,
    };
  }

  Color _getLevelColor(int level) {
    return switch (level) {
      1 => Colors.blue,
      2 => Colors.green,
      3 => Colors.yellow,
      4 => Colors.orange,
      5 => Colors.red,
      _ => FluxForgeTheme.textMuted,
    };
  }

  Color _getSignalColor(String signalId) {
    return switch (signalId) {
      'winTier' || 'winXbet' => Colors.amber,
      'consecutiveWins' || 'consecutiveLosses' => Colors.green,
      'featureProgress' || 'multiplier' => Colors.purple,
      'nearMissIntensity' => Colors.orange,
      'momentum' => Colors.pink,
      _ => FluxForgeTheme.accent,
    };
  }

  double _getSignalMax(String signalId) {
    return switch (signalId) {
      'winTier' => 5.0,
      'winXbet' => 100.0,
      'consecutiveWins' || 'consecutiveLosses' => 20.0,
      'featureProgress' || 'nearMissIntensity' => 1.0,
      'multiplier' => 50.0,
      'momentum' => 1.0,
      _ => 1.0,
    };
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
