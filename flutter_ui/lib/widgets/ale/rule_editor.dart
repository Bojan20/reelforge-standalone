/// Rule Editor Widget
///
/// Editor for ALE rules with conditions, actions, and transitions.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ale_provider.dart';

/// Rule list and editor widget
class RuleEditor extends StatefulWidget {
  final String? filterContextId;
  final VoidCallback? onRuleChanged;

  const RuleEditor({
    super.key,
    this.filterContextId,
    this.onRuleChanged,
  });

  @override
  State<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<RuleEditor> {
  String? _selectedRuleId;
  bool _showDisabled = true;
  String _sortBy = 'priority';

  @override
  Widget build(BuildContext context) {
    return Consumer<AleProvider>(
      builder: (context, ale, child) {
        var rules = ale.profile?.rules ?? [];

        // Filter by context if specified
        if (widget.filterContextId != null) {
          rules = rules
              .where((r) =>
                  r.contexts.isEmpty ||
                  r.contexts.contains(widget.filterContextId))
              .toList();
        }

        // Filter disabled
        if (!_showDisabled) {
          rules = rules.where((r) => r.enabled).toList();
        }

        // Sort
        rules = List.from(rules);
        switch (_sortBy) {
          case 'priority':
            rules.sort((a, b) => b.priority.compareTo(a.priority));
            break;
          case 'name':
            rules.sort((a, b) => a.name.compareTo(b.name));
            break;
          case 'signal':
            rules.sort((a, b) =>
                (a.signalId ?? '').compareTo(b.signalId ?? ''));
            break;
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2a2a35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(rules.length, ale.profile?.rules.length ?? 0),

              // Toolbar
              _buildToolbar(),

              // Rule list
              Expanded(
                child: rules.isEmpty
                    ? _buildEmptyState()
                    : _buildRuleList(rules),
              ),

              // Selected rule details
              if (_selectedRuleId != null)
                _buildRuleDetails(
                  rules.firstWhere(
                    (r) => r.id == _selectedRuleId,
                    orElse: () => rules.first,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(int filteredCount, int totalCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.rule, color: Color(0xFFff9040), size: 18),
          const SizedBox(width: 8),
          const Text(
            'Rules',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF2a2a35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              filteredCount == totalCount
                  ? '$totalCount'
                  : '$filteredCount/$totalCount',
              style: const TextStyle(
                color: Color(0xFF888888),
                fontSize: 11,
              ),
            ),
          ),
          const Spacer(),
          _ActionButton(
            icon: Icons.add,
            tooltip: 'Add Rule',
            onPressed: () => _showAddRuleDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF151519),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2a2a35)),
        ),
      ),
      child: Row(
        children: [
          // Sort dropdown
          _ToolbarDropdown(
            value: _sortBy,
            items: const {
              'priority': 'Priority',
              'name': 'Name',
              'signal': 'Signal',
            },
            onChanged: (value) => setState(() => _sortBy = value),
          ),

          const Spacer(),

          // Show disabled toggle
          _ToolbarToggle(
            label: 'Disabled',
            value: _showDisabled,
            onChanged: (value) => setState(() => _showDisabled = value),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.rule_folder,
            color: Color(0xFF666666),
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            widget.filterContextId != null
                ? 'No rules for this context'
                : 'No rules defined',
            style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _showAddRuleDialog(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Rule'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFff9040),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleList(List<AleRule> rules) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: rules.length,
      itemBuilder: (context, index) {
        final rule = rules[index];
        final isSelected = rule.id == _selectedRuleId;

        return _RuleTile(
          rule: rule,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedRuleId = isSelected ? null : rule.id;
            });
          },
          onToggle: (enabled) {
            // TODO: Implement rule enable/disable via FFI
          },
        );
      },
    );
  }

  Widget _buildRuleDetails(AleRule rule) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF121216),
        border: Border(
          top: BorderSide(color: Color(0xFF2a2a35)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rule name and priority
          Row(
            children: [
              Expanded(
                child: Text(
                  rule.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFff9040).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'P${rule.priority}',
                  style: const TextStyle(
                    color: Color(0xFFff9040),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Condition
          _DetailSection(
            title: 'Condition',
            child: _buildConditionDisplay(rule),
          ),

          const SizedBox(height: 8),

          // Action
          _DetailSection(
            title: 'Action',
            child: _buildActionDisplay(rule),
          ),

          const SizedBox(height: 8),

          // Contexts
          if (rule.contexts.isNotEmpty)
            _DetailSection(
              title: 'Contexts',
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: rule.contexts
                    .map((c) => _ContextChip(contextId: c))
                    .toList(),
              ),
            ),

          const SizedBox(height: 12),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _selectedRuleId = null),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF888888),
                ),
                child: const Text('Close'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () {
                  // TODO: Implement rule editing
                },
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4a9eff),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConditionDisplay(AleRule rule) {
    if (rule.signalId == null) {
      return const Text(
        'Always true',
        style: TextStyle(color: Color(0xFF888888), fontSize: 12),
      );
    }

    final opString = _opToString(rule.op);
    final valueString = rule.value?.toStringAsFixed(2) ?? '?';

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF4a9eff).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            rule.signalId!,
            style: const TextStyle(
              color: Color(0xFF4a9eff),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$opString $valueString',
          style: const TextStyle(
            color: Color(0xFFcccccc),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildActionDisplay(AleRule rule) {
    final actionString = _actionToString(rule.action);
    final valueString = rule.actionValue != null ? ' (${rule.actionValue})' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF40ff90).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF40ff90).withValues(alpha: 0.3)),
      ),
      child: Text(
        '$actionString$valueString',
        style: const TextStyle(
          color: Color(0xFF40ff90),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _opToString(ComparisonOp? op) {
    return switch (op) {
      ComparisonOp.eq => '==',
      ComparisonOp.ne => '!=',
      ComparisonOp.lt => '<',
      ComparisonOp.lte => '<=',
      ComparisonOp.gt => '>',
      ComparisonOp.gte => '>=',
      ComparisonOp.inRange => 'in range',
      ComparisonOp.outOfRange => 'out of range',
      ComparisonOp.rising => 'rising',
      ComparisonOp.falling => 'falling',
      ComparisonOp.crossed => 'crossed',
      ComparisonOp.aboveFor => 'above for',
      ComparisonOp.belowFor => 'below for',
      ComparisonOp.changed => 'changed',
      ComparisonOp.stable => 'stable',
      null => '?',
    };
  }

  String _actionToString(AleActionType action) {
    return switch (action) {
      AleActionType.stepUp => 'Step Up',
      AleActionType.stepDown => 'Step Down',
      AleActionType.setLevel => 'Set Level',
      AleActionType.hold => 'Hold',
      AleActionType.release => 'Release',
      AleActionType.pulse => 'Pulse',
    };
  }

  void _showAddRuleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a20),
        title: const Text(
          'Add Rule',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Rule creation wizard coming soon.',
          style: TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Rule list tile
class _RuleTile extends StatelessWidget {
  final AleRule rule;
  final bool isSelected;
  final VoidCallback? onTap;
  final Function(bool)? onToggle;

  const _RuleTile({
    required this.rule,
    this.isSelected = false,
    this.onTap,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final color = rule.enabled
        ? const Color(0xFFff9040)
        : const Color(0xFF666666);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF2a2a35)
                : const Color(0xFF121216),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? color.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              // Priority badge
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${rule.priority}',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Rule info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.name,
                      style: TextStyle(
                        color: rule.enabled
                            ? const Color(0xFFcccccc)
                            : const Color(0xFF666666),
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _buildConditionPreview(),
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Action badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF2a2a35),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _actionShort(rule.action),
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Enable toggle
              if (onToggle != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Switch(
                    value: rule.enabled,
                    onChanged: onToggle,
                    activeColor: const Color(0xFFff9040),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildConditionPreview() {
    if (rule.signalId == null) return 'Always true';
    final op = _opShort(rule.op);
    return '${rule.signalId} $op ${rule.value?.toStringAsFixed(1) ?? "?"}';
  }

  String _opShort(ComparisonOp? op) {
    return switch (op) {
      ComparisonOp.eq => '==',
      ComparisonOp.ne => '!=',
      ComparisonOp.lt => '<',
      ComparisonOp.lte => '<=',
      ComparisonOp.gt => '>',
      ComparisonOp.gte => '>=',
      ComparisonOp.inRange => 'in',
      ComparisonOp.outOfRange => 'out',
      ComparisonOp.rising => '↑',
      ComparisonOp.falling => '↓',
      ComparisonOp.crossed => '×',
      ComparisonOp.aboveFor => '>t',
      ComparisonOp.belowFor => '<t',
      ComparisonOp.changed => 'Δ',
      ComparisonOp.stable => '—',
      null => '?',
    };
  }

  String _actionShort(AleActionType action) {
    return switch (action) {
      AleActionType.stepUp => '↑',
      AleActionType.stepDown => '↓',
      AleActionType.setLevel => '=',
      AleActionType.hold => 'H',
      AleActionType.release => 'R',
      AleActionType.pulse => 'P',
    };
  }
}

/// Detail section widget
class _DetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF888888),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// Context chip
class _ContextChip extends StatelessWidget {
  final String contextId;

  const _ContextChip({required this.contextId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF2a2a35),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        contextId,
        style: const TextStyle(
          color: Color(0xFF888888),
          fontSize: 10,
        ),
      ),
    );
  }
}

/// Small action button
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: const Color(0xFF2a2a35),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: const Color(0xFF888888),
            size: 14,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Toolbar dropdown
class _ToolbarDropdown extends StatelessWidget {
  final String value;
  final Map<String, String> items;
  final Function(String) onChanged;

  const _ToolbarDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2a2a35),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: const Color(0xFF2a2a35),
          style: const TextStyle(
            color: Color(0xFFcccccc),
            fontSize: 11,
          ),
          items: items.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Toolbar toggle
class _ToolbarToggle extends StatelessWidget {
  final String label;
  final bool value;
  final Function(bool) onChanged;

  const _ToolbarToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.visibility : Icons.visibility_off,
              color: value ? const Color(0xFF4a9eff) : const Color(0xFF666666),
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: value ? const Color(0xFFcccccc) : const Color(0xFF666666),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
