/// Logical Editor Panel - Cubase-style batch operations UI
///
/// Full-featured logical editor for:
/// - MIDI event filtering and transformation
/// - Audio clip batch operations
/// - Preset management
/// - Real-time preview

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/logical_editor_provider.dart';
import '../../theme/fluxforge_theme.dart';

class LogicalEditorPanel extends StatefulWidget {
  const LogicalEditorPanel({super.key});

  @override
  State<LogicalEditorPanel> createState() => _LogicalEditorPanelState();
}

class _LogicalEditorPanelState extends State<LogicalEditorPanel> {
  @override
  Widget build(BuildContext context) {
    return Consumer<LogicalEditorProvider>(
      builder: (context, provider, _) {
        return Container(
          color: FluxForgeTheme.bgDeep,
          child: Column(
            children: [
              // Header with preset selector
              _buildHeader(provider),

              // Main content
              Expanded(
                child: Row(
                  children: [
                    // Filter conditions (left)
                    Expanded(
                      flex: 1,
                      child: _buildFilterSection(provider),
                    ),

                    // Divider
                    Container(
                      width: 1,
                      color: FluxForgeTheme.borderSubtle,
                    ),

                    // Actions (right)
                    Expanded(
                      flex: 1,
                      child: _buildActionSection(provider),
                    ),
                  ],
                ),
              ),

              // Footer with apply/preview buttons
              _buildFooter(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(LogicalEditorProvider provider) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Title
          const Icon(Icons.filter_list, size: 16, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 8),
          Text(
            'Logical Editor',
            style: FluxForgeTheme.label.copyWith(
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
            ),
          ),

          const SizedBox(width: 16),

          // Preset dropdown
          _buildPresetDropdown(provider),

          const Spacer(),

          // Combine mode toggle
          _buildCombineModeToggle(provider),
        ],
      ),
    );
  }

  Widget _buildPresetDropdown(LogicalEditorProvider provider) {
    final presets = provider.allPresets;
    final currentName = provider.currentPreset.name;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: null, // Current preset is always "custom" until loaded
          hint: Text(
            currentName,
            style: const TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary),
          ),
          isDense: true,
          dropdownColor: FluxForgeTheme.bgElevated,
          style: const TextStyle(fontSize: 11, color: FluxForgeTheme.textPrimary),
          items: [
            const DropdownMenuItem<String>(
              value: '__new__',
              child: Text('-- New --'),
            ),
            ...presets.map((p) => DropdownMenuItem<String>(
              value: p.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p.isFactory)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.lock, size: 10, color: FluxForgeTheme.textSecondary),
                    ),
                  Text(p.name),
                ],
              ),
            )),
          ],
          onChanged: (id) {
            if (id == '__new__') {
              provider.resetPreset();
            } else if (id != null) {
              provider.loadPreset(id);
            }
          },
        ),
      ),
    );
  }

  Widget _buildCombineModeToggle(LogicalEditorProvider provider) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Combine:',
          style: TextStyle(fontSize: 10, color: FluxForgeTheme.textSecondary),
        ),
        const SizedBox(width: 4),
        _buildCombineChip(provider, FilterCombineMode.and, 'AND'),
        const SizedBox(width: 2),
        _buildCombineChip(provider, FilterCombineMode.or, 'OR'),
      ],
    );
  }

  Widget _buildCombineChip(LogicalEditorProvider provider, FilterCombineMode mode, String label) {
    final isSelected = provider.filterMode == mode;

    return GestureDetector(
      onTap: () => provider.setFilterMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentOrange.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? FluxForgeTheme.accentOrange : FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection(LogicalEditorProvider provider) {
    final filters = provider.filters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
          child: Row(
            children: [
              Text(
                'FILTER CONDITIONS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              _buildIconButton(
                Icons.add,
                'Add Filter',
                () => _showAddFilterDialog(provider),
              ),
            ],
          ),
        ),

        // Filter list
        Expanded(
          child: filters.isEmpty
              ? _buildEmptyState('No filters', 'Click + to add filter conditions')
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filters.length,
                  itemBuilder: (context, index) => _buildFilterCard(provider, filters[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildFilterCard(LogicalEditorProvider provider, FilterCondition filter) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Enable toggle
              GestureDetector(
                onTap: () => provider.toggleFilterEnabled(filter.id),
                child: Icon(
                  filter.enabled ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16,
                  color: filter.enabled ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  filter.property.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: FluxForgeTheme.accentCyan,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _getOperatorDisplayName(filter.operator),
                style: TextStyle(
                  fontSize: 11,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              const Spacer(),
              _buildIconButton(
                Icons.close,
                'Remove',
                () => provider.removeFilter(filter.id),
                size: 14,
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Value display
          Text(
            _formatFilterValue(filter),
            style: TextStyle(
              fontSize: 12,
              color: filter.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionSection(LogicalEditorProvider provider) {
    final actions = provider.actions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
          child: Row(
            children: [
              Text(
                'ACTIONS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: FluxForgeTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              _buildIconButton(
                Icons.add,
                'Add Action',
                () => _showAddActionDialog(provider),
              ),
            ],
          ),
        ),

        // Action list
        Expanded(
          child: actions.isEmpty
              ? _buildEmptyState('No actions', 'Click + to add actions')
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: actions.length,
                  itemBuilder: (context, index) => _buildActionCard(provider, actions[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildActionCard(LogicalEditorProvider provider, LogicalAction action) {
    final actionColor = _getActionColor(action.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: actionColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              // Enable toggle
              GestureDetector(
                onTap: () => provider.toggleActionEnabled(action.id),
                child: Icon(
                  action.enabled ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 16,
                  color: action.enabled ? actionColor : FluxForgeTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  action.type.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: actionColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                action.target.name,
                style: TextStyle(
                  fontSize: 11,
                  color: FluxForgeTheme.textSecondary,
                ),
              ),
              const Spacer(),
              _buildIconButton(
                Icons.close,
                'Remove',
                () => provider.removeAction(action.id),
                size: 14,
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Value display
          Text(
            action.displayString,
            style: TextStyle(
              fontSize: 12,
              color: action.enabled ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(LogicalEditorProvider provider) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Stats
          Text(
            '${provider.filters.length} filters, ${provider.actions.length} actions',
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textSecondary,
            ),
          ),

          if (provider.lastMatchCount > 0 || provider.lastAffectedCount > 0) ...[
            const SizedBox(width: 16),
            Text(
              'Last: ${provider.lastMatchCount} matched, ${provider.lastAffectedCount} affected',
              style: TextStyle(
                fontSize: 10,
                color: FluxForgeTheme.accentGreen,
              ),
            ),
          ],

          const Spacer(),

          // Save preset button
          _buildButton(
            'Save',
            Icons.save,
            () => _showSavePresetDialog(provider),
            secondary: true,
          ),

          const SizedBox(width: 8),

          // Clear button
          _buildButton(
            'Clear',
            Icons.delete_sweep,
            () {
              provider.clearFilters();
              provider.clearActions();
            },
            secondary: true,
          ),

          const SizedBox(width: 8),

          // Apply button
          _buildButton(
            'Apply',
            Icons.play_arrow,
            provider.filters.isEmpty || provider.actions.isEmpty
                ? null
                : () {
                    // TODO: Apply to selection
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logical Editor applied')),
                    );
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_list_off,
            size: 32,
            color: FluxForgeTheme.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: FluxForgeTheme.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, String tooltip, VoidCallback onTap, {double size = 16}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: size, color: FluxForgeTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _buildButton(String label, IconData icon, VoidCallback? onTap, {bool secondary = false}) {
    final isDisabled = onTap == null;
    final color = secondary ? FluxForgeTheme.textSecondary : FluxForgeTheme.accentBlue;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: secondary
                ? FluxForgeTheme.bgDeep
                : FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: secondary ? FluxForgeTheme.borderSubtle : FluxForgeTheme.accentBlue,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getOperatorDisplayName(FilterOperator op) {
    switch (op) {
      case FilterOperator.equals:
        return '=';
      case FilterOperator.notEquals:
        return '≠';
      case FilterOperator.greaterThan:
        return '>';
      case FilterOperator.lessThan:
        return '<';
      case FilterOperator.greaterOrEqual:
        return '≥';
      case FilterOperator.lessOrEqual:
        return '≤';
      case FilterOperator.inRange:
        return 'in range';
      case FilterOperator.notInRange:
        return 'not in range';
      case FilterOperator.contains:
        return 'contains';
      case FilterOperator.startsWith:
        return 'starts with';
      case FilterOperator.endsWith:
        return 'ends with';
    }
  }

  String _formatFilterValue(FilterCondition filter) {
    if (filter.operator == FilterOperator.inRange || filter.operator == FilterOperator.notInRange) {
      return '${filter.value1} - ${filter.value2}';
    }
    return filter.value1?.toString() ?? '';
  }

  Color _getActionColor(LogicalActionType type) {
    switch (type) {
      case LogicalActionType.set:
        return FluxForgeTheme.accentBlue;
      case LogicalActionType.add:
      case LogicalActionType.subtract:
      case LogicalActionType.multiply:
      case LogicalActionType.divide:
        return FluxForgeTheme.accentGreen;
      case LogicalActionType.random:
        return FluxForgeTheme.accentCyan;
      case LogicalActionType.delete:
        return FluxForgeTheme.errorRed;
      case LogicalActionType.mute:
      case LogicalActionType.unmute:
        return FluxForgeTheme.accentOrange;
      case LogicalActionType.select:
      case LogicalActionType.deselect:
        return FluxForgeTheme.accentCyan;
      case LogicalActionType.quantize:
      case LogicalActionType.legato:
      case LogicalActionType.fixedLength:
        return FluxForgeTheme.accentBlue;
    }
  }

  void _showAddFilterDialog(LogicalEditorProvider provider) {
    showDialog(
      context: context,
      builder: (context) => _AddFilterDialog(provider: provider),
    );
  }

  void _showAddActionDialog(LogicalEditorProvider provider) {
    showDialog(
      context: context,
      builder: (context) => _AddActionDialog(provider: provider),
    );
  }

  void _showSavePresetDialog(LogicalEditorProvider provider) {
    final controller = TextEditingController(text: provider.currentPreset.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgElevated,
        title: const Text('Save Preset', style: TextStyle(fontSize: 14)),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Preset name',
            isDense: true,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.savePreset(name: controller.text);
                Navigator.pop(context);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text('Preset "${controller.text}" saved')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ADD FILTER DIALOG
// ════════════════════════════════════════════════════════════════════════════

class _AddFilterDialog extends StatefulWidget {
  final LogicalEditorProvider provider;

  const _AddFilterDialog({required this.provider});

  @override
  State<_AddFilterDialog> createState() => _AddFilterDialogState();
}

class _AddFilterDialogState extends State<_AddFilterDialog> {
  FilterProperty _property = FilterProperty.pitch;
  FilterOperator _operator = FilterOperator.equals;
  final _valueController = TextEditingController();
  final _value2Controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final needsSecondValue = _operator == FilterOperator.inRange ||
                             _operator == FilterOperator.notInRange;

    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgElevated,
      title: const Text('Add Filter Condition', style: TextStyle(fontSize: 14)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Property dropdown
            DropdownButtonFormField<FilterProperty>(
              value: _property,
              decoration: const InputDecoration(
                labelText: 'Property',
                isDense: true,
              ),
              items: FilterProperty.values
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                  .toList(),
              onChanged: (v) => setState(() => _property = v!),
            ),

            const SizedBox(height: 12),

            // Operator dropdown
            DropdownButtonFormField<FilterOperator>(
              value: _operator,
              decoration: const InputDecoration(
                labelText: 'Operator',
                isDense: true,
              ),
              items: FilterOperator.values
                  .map((o) => DropdownMenuItem(value: o, child: Text(o.name)))
                  .toList(),
              onChanged: (v) => setState(() => _operator = v!),
            ),

            const SizedBox(height: 12),

            // Value input
            TextField(
              controller: _valueController,
              decoration: InputDecoration(
                labelText: needsSecondValue ? 'Min Value' : 'Value',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
            ),

            // Second value for range
            if (needsSecondValue) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _value2Controller,
                decoration: const InputDecoration(
                  labelText: 'Max Value',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_valueController.text.isEmpty) return;

            final value1 = _parseValue(_valueController.text);
            final value2 = needsSecondValue && _value2Controller.text.isNotEmpty
                ? _parseValue(_value2Controller.text)
                : null;

            widget.provider.addFilter(
              property: _property,
              operator: _operator,
              value1: value1,
              value2: value2,
            );
            Navigator.pop(context);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  dynamic _parseValue(String text) {
    // Try int first, then double, then keep as string
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;

    final asDouble = double.tryParse(text);
    if (asDouble != null) return asDouble;

    return text;
  }

  @override
  void dispose() {
    _valueController.dispose();
    _value2Controller.dispose();
    super.dispose();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ADD ACTION DIALOG
// ════════════════════════════════════════════════════════════════════════════

class _AddActionDialog extends StatefulWidget {
  final LogicalEditorProvider provider;

  const _AddActionDialog({required this.provider});

  @override
  State<_AddActionDialog> createState() => _AddActionDialogState();
}

class _AddActionDialogState extends State<_AddActionDialog> {
  LogicalActionType _actionType = LogicalActionType.set;
  ActionTarget _target = ActionTarget.velocity;
  final _valueController = TextEditingController();
  final _value2Controller = TextEditingController();

  bool get _needsValue {
    return _actionType != LogicalActionType.delete &&
           _actionType != LogicalActionType.select &&
           _actionType != LogicalActionType.deselect &&
           _actionType != LogicalActionType.mute &&
           _actionType != LogicalActionType.unmute &&
           _actionType != LogicalActionType.legato;
  }

  bool get _needsSecondValue {
    return _actionType == LogicalActionType.random;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgElevated,
      title: const Text('Add Action', style: TextStyle(fontSize: 14)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Action type dropdown
            DropdownButtonFormField<LogicalActionType>(
              value: _actionType,
              decoration: const InputDecoration(
                labelText: 'Action',
                isDense: true,
              ),
              items: LogicalActionType.values
                  .map((a) => DropdownMenuItem(value: a, child: Text(a.name)))
                  .toList(),
              onChanged: (v) => setState(() => _actionType = v!),
            ),

            const SizedBox(height: 12),

            // Target dropdown
            DropdownButtonFormField<ActionTarget>(
              value: _target,
              decoration: const InputDecoration(
                labelText: 'Target',
                isDense: true,
              ),
              items: ActionTarget.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.name)))
                  .toList(),
              onChanged: (v) => setState(() => _target = v!),
            ),

            // Value input (not for all actions)
            if (_needsValue) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _valueController,
                decoration: InputDecoration(
                  labelText: _needsSecondValue ? 'Min Value' : 'Value',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ],

            // Second value for random
            if (_needsSecondValue) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _value2Controller,
                decoration: const InputDecoration(
                  labelText: 'Max Value',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            dynamic value1;
            dynamic value2;

            if (_needsValue && _valueController.text.isNotEmpty) {
              value1 = _parseValue(_valueController.text);
            }

            if (_needsSecondValue && _value2Controller.text.isNotEmpty) {
              value2 = _parseValue(_value2Controller.text);
            }

            widget.provider.addAction(
              type: _actionType,
              target: _target,
              value1: value1,
              value2: value2,
            );
            Navigator.pop(context);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }

  dynamic _parseValue(String text) {
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;

    final asDouble = double.tryParse(text);
    if (asDouble != null) return asDouble;

    return text;
  }

  @override
  void dispose() {
    _valueController.dispose();
    _value2Controller.dispose();
    super.dispose();
  }
}
