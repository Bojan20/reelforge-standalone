/// FluxForge Studio Ducking Matrix Panel
///
/// Visual matrix editor for automatic volume ducking between buses.
/// Source bus triggers → Target bus volume reduction.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/middleware_models.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Ducking Matrix Panel Widget
class DuckingMatrixPanel extends StatefulWidget {
  const DuckingMatrixPanel({super.key});

  @override
  State<DuckingMatrixPanel> createState() => _DuckingMatrixPanelState();
}

class _DuckingMatrixPanelState extends State<DuckingMatrixPanel> {
  int? _selectedRuleId;
  bool _showAddDialog = false;

  @override
  Widget build(BuildContext context) {
    return Selector<MiddlewareProvider, List<DuckingRule>>(
      selector: (_, p) => p.duckingRules,
      builder: (context, rules, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FluxForgeTheme.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildMatrixView(rules),
              const SizedBox(height: 16),
              if (_selectedRuleId != null)
                _buildRuleEditor(rules),
              if (_showAddDialog)
                _buildAddDialog(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.grid_on, color: FluxForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'Ducking Matrix',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        _buildHeaderButton(
          icon: Icons.add,
          label: 'Add Rule',
          onTap: () => setState(() => _showAddDialog = true),
        ),
      ],
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.accentBlue),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: FluxForgeTheme.accentBlue),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.accentBlue,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatrixView(List<DuckingRule> rules) {
    if (rules.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: FluxForgeTheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FluxForgeTheme.border),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.grid_off, size: 48, color: FluxForgeTheme.textSecondary),
              const SizedBox(height: 8),
              Text(
                'No ducking rules configured',
                style: TextStyle(color: FluxForgeTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                'Add a rule to duck one bus when another plays',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: FluxForgeTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                _buildMatrixHeader('Source', flex: 2),
                _buildMatrixHeader('→', flex: 1),
                _buildMatrixHeader('Target', flex: 2),
                _buildMatrixHeader('Amount', flex: 1),
                _buildMatrixHeader('Attack', flex: 1),
                _buildMatrixHeader('Release', flex: 1),
                _buildMatrixHeader('', flex: 1),
              ],
            ),
          ),
          // Rules
          ...rules.map((rule) => _buildRuleRow(rule)),
        ],
      ),
    );
  }

  Widget _buildMatrixHeader(String label, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRuleRow(DuckingRule rule) {
    final isSelected = _selectedRuleId == rule.id;

    return GestureDetector(
      onTap: () => setState(() {
        _selectedRuleId = isSelected ? null : rule.id;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: FluxForgeTheme.border.withValues(alpha: 0.5)),
            left: isSelected
                ? BorderSide(color: FluxForgeTheme.accentBlue, width: 2)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            // Source bus
            Expanded(
              flex: 2,
              child: _buildBusChip(rule.sourceBus, Colors.orange),
            ),
            // Arrow
            Expanded(
              flex: 1,
              child: Icon(
                Icons.arrow_forward,
                size: 16,
                color: rule.enabled
                    ? FluxForgeTheme.textSecondary
                    : FluxForgeTheme.textSecondary.withValues(alpha: 0.3),
              ),
            ),
            // Target bus
            Expanded(
              flex: 2,
              child: _buildBusChip(rule.targetBus, Colors.cyan),
            ),
            // Amount
            Expanded(
              flex: 1,
              child: Text(
                '${rule.duckAmountDb.toStringAsFixed(1)} dB',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: rule.enabled
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Attack
            Expanded(
              flex: 1,
              child: Text(
                '${rule.attackMs.toStringAsFixed(0)}ms',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
            // Release
            Expanded(
              flex: 1,
              child: Text(
                '${rule.releaseMs.toStringAsFixed(0)}ms',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
            // Enable toggle
            Expanded(
              flex: 1,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    context.read<MiddlewareProvider>().saveDuckingRule(
                      rule.copyWith(enabled: !rule.enabled),
                    );
                  },
                  child: Container(
                    width: 32,
                    height: 18,
                    decoration: BoxDecoration(
                      color: rule.enabled
                          ? Colors.green.withValues(alpha: 0.3)
                          : FluxForgeTheme.surface,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: rule.enabled ? Colors.green : FluxForgeTheme.border,
                      ),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 150),
                      alignment: rule.enabled
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: rule.enabled ? Colors.green : FluxForgeTheme.textSecondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusChip(String bus, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        bus,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRuleEditor(List<DuckingRule> rules) {
    final rule = rules.where((r) => r.id == _selectedRuleId).firstOrNull;
    if (rule == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Edit Rule: ${rule.sourceBus} → ${rule.targetBus}',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  context.read<MiddlewareProvider>().removeDuckingRule(rule.id);
                  setState(() => _selectedRuleId = null);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.delete, size: 16, color: Colors.red),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _selectedRuleId = null),
                child: Icon(Icons.close, size: 16, color: FluxForgeTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Duck Amount
          _buildSliderRow(
            label: 'Duck Amount',
            value: '${rule.duckAmountDb.toStringAsFixed(1)} dB',
            sliderValue: (rule.duckAmountDb + 48) / 48,
            onChanged: (v) {
              context.read<MiddlewareProvider>().saveDuckingRule(
                rule.copyWith(duckAmountDb: v * 48 - 48),
              );
            },
          ),
          const SizedBox(height: 8),
          // Attack
          _buildSliderRow(
            label: 'Attack',
            value: '${rule.attackMs.toStringAsFixed(0)} ms',
            sliderValue: rule.attackMs / 500,
            onChanged: (v) {
              context.read<MiddlewareProvider>().saveDuckingRule(
                rule.copyWith(attackMs: v * 500),
              );
            },
          ),
          const SizedBox(height: 8),
          // Release
          _buildSliderRow(
            label: 'Release',
            value: '${rule.releaseMs.toStringAsFixed(0)} ms',
            sliderValue: rule.releaseMs / 2000,
            onChanged: (v) {
              context.read<MiddlewareProvider>().saveDuckingRule(
                rule.copyWith(releaseMs: v * 2000),
              );
            },
          ),
          const SizedBox(height: 8),
          // Threshold
          _buildSliderRow(
            label: 'Threshold',
            value: rule.threshold.toStringAsFixed(3),
            sliderValue: rule.threshold,
            onChanged: (v) {
              context.read<MiddlewareProvider>().saveDuckingRule(
                rule.copyWith(threshold: v),
              );
            },
          ),
          const SizedBox(height: 8),
          // Curve selector
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  'Curve',
                  style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                ),
              ),
              Expanded(
                child: Row(
                  children: DuckingCurve.values.map((curve) {
                    final isActive = rule.curve == curve;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          context.read<MiddlewareProvider>().saveDuckingRule(rule.copyWith(curve: curve));
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive
                                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                                : FluxForgeTheme.surface,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isActive
                                  ? FluxForgeTheme.accentBlue
                                  : FluxForgeTheme.border,
                            ),
                          ),
                          child: Text(
                            curve.displayName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isActive
                                  ? FluxForgeTheme.accentBlue
                                  : FluxForgeTheme.textSecondary,
                              fontSize: 9,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String value,
    required double sliderValue,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: FluxForgeTheme.accentBlue,
              inactiveTrackColor: FluxForgeTheme.surface,
              thumbColor: FluxForgeTheme.accentBlue,
            ),
            child: Slider(
              value: sliderValue.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 70,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: FluxForgeTheme.accentBlue,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddDialog() {
    return _AddDuckingRuleDialog(
      onAdd: (sourceBus, targetBus) {
        context.read<MiddlewareProvider>().addDuckingRule(
          sourceBus: sourceBus,
          sourceBusId: kAllBuses.indexOf(sourceBus),
          targetBus: targetBus,
          targetBusId: kAllBuses.indexOf(targetBus),
        );
        setState(() => _showAddDialog = false);
      },
      onCancel: () => setState(() => _showAddDialog = false),
    );
  }
}

class _AddDuckingRuleDialog extends StatefulWidget {
  final void Function(String sourceBus, String targetBus) onAdd;
  final VoidCallback onCancel;

  const _AddDuckingRuleDialog({
    required this.onAdd,
    required this.onCancel,
  });

  @override
  State<_AddDuckingRuleDialog> createState() => _AddDuckingRuleDialogState();
}

class _AddDuckingRuleDialogState extends State<_AddDuckingRuleDialog> {
  String _sourceBus = 'VO';
  String _targetBus = 'Music';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.accentBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add Ducking Rule',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Source Bus (Trigger)',
                      style: TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildBusDropdown(
                      value: _sourceBus,
                      color: Colors.orange,
                      onChanged: (v) => setState(() => _sourceBus = v!),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(
                  Icons.arrow_forward,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target Bus (Ducked)',
                      style: TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _buildBusDropdown(
                      value: _targetBus,
                      color: Colors.cyan,
                      onChanged: (v) => setState(() => _targetBus = v!),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: widget.onCancel,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxForgeTheme.border),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => widget.onAdd(_sourceBus, _targetBus),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Add Rule',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBusDropdown({
    required String value,
    required Color color,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: FluxForgeTheme.surfaceDark,
        style: TextStyle(color: color, fontSize: 12),
        items: kAllBuses.map((bus) {
          return DropdownMenuItem(
            value: bus,
            child: Text(bus),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
