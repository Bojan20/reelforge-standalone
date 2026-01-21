/// Advanced Event Configuration Widgets (Sprint 3 + Sprint 4)
///
/// UI components for:
/// - D.1: Event dependencies editor
/// - D.2: Conditional trigger editor
/// - D.3: RTPC binding editor
/// - D.7: Music crossfade config
/// - D.4: Template inheritance tree view (Sprint 4)
/// - D.5: Batch drop panel (Sprint 4)
/// - D.6: Binding graph visualization (Sprint 4)
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md specification.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/auto_event_builder_models.dart';
import '../../../providers/auto_event_builder_provider.dart';
import '../../../theme/fluxforge_theme.dart';

// =============================================================================
// EVENT DEPENDENCY EDITOR (D.1)
// =============================================================================

/// Editor for managing event dependencies
class EventDependencyEditor extends StatefulWidget {
  final String eventId;

  const EventDependencyEditor({
    super.key,
    required this.eventId,
  });

  @override
  State<EventDependencyEditor> createState() => _EventDependencyEditorState();
}

class _EventDependencyEditorState extends State<EventDependencyEditor> {
  String? _selectedTargetEventId;
  DependencyType _selectedType = DependencyType.after;
  int _delayMs = 0;
  bool _required = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        final event = provider.events.firstWhere(
          (e) => e.eventId == widget.eventId,
          orElse: () => throw ArgumentError('Event not found'),
        );

        final availableEvents = provider.events
            .where((e) =>
                e.eventId != widget.eventId &&
                !provider.hasCircularDependency(widget.eventId, e.eventId))
            .toList();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 16,
                    color: FluxForgeTheme.accentBlue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Dependencies',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${event.dependencies.length} linked',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Existing dependencies list
              if (event.dependencies.isNotEmpty) ...[
                ...event.dependencies.map((dep) => _DependencyChip(
                      dependency: dep,
                      onRemove: () => provider.removeEventDependency(
                          widget.eventId, dep.targetEventId),
                    )),
                const SizedBox(height: 12),
              ],

              // Add new dependency
              if (availableEvents.isNotEmpty) ...[
                Row(
                  children: [
                    // Target event selector
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _selectedTargetEventId,
                        hint: Text(
                          'Select event...',
                          style: TextStyle(
                            color: FluxForgeTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide:
                                BorderSide(color: FluxForgeTheme.borderSubtle),
                          ),
                          filled: true,
                          fillColor: FluxForgeTheme.bgDeep,
                        ),
                        dropdownColor: FluxForgeTheme.bgMid,
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 12,
                        ),
                        items: availableEvents.map((e) {
                          return DropdownMenuItem(
                            value: e.eventId,
                            child: Text(
                              e.eventId,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedTargetEventId = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Dependency type selector
                    Expanded(
                      child: DropdownButtonFormField<DependencyType>(
                        value: _selectedType,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide:
                                BorderSide(color: FluxForgeTheme.borderSubtle),
                          ),
                          filled: true,
                          fillColor: FluxForgeTheme.bgDeep,
                        ),
                        dropdownColor: FluxForgeTheme.bgMid,
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 12,
                        ),
                        items: DependencyType.values.map((t) {
                          return DropdownMenuItem(
                            value: t,
                            child: Text(t.displayName),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedType = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Add button
                    IconButton(
                      icon: Icon(
                        Icons.add_circle_outline,
                        color: FluxForgeTheme.accentGreen,
                        size: 20,
                      ),
                      onPressed: _selectedTargetEventId == null
                          ? null
                          : () {
                              provider.addEventDependency(
                                widget.eventId,
                                EventDependency(
                                  targetEventId: _selectedTargetEventId!,
                                  type: _selectedType,
                                  delayMs: _delayMs,
                                  required: _required,
                                ),
                              );
                              setState(() => _selectedTargetEventId = null);
                            },
                    ),
                  ],
                ),
              ] else
                Text(
                  'No available events for dependencies',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DependencyChip extends StatelessWidget {
  final EventDependency dependency;
  final VoidCallback onRemove;

  const _DependencyChip({
    required this.dependency,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = switch (dependency.type) {
      DependencyType.after => FluxForgeTheme.accentBlue,
      DependencyType.with_ => FluxForgeTheme.accentGreen,
      DependencyType.stopOnStart => FluxForgeTheme.accentOrange,
      DependencyType.stopOnStop => FluxForgeTheme.accentCyan,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: typeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              dependency.type.displayName,
              style: TextStyle(
                color: typeColor,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              dependency.targetEventId,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (dependency.delayMs > 0) ...[
            const SizedBox(width: 4),
            Text(
              '+${dependency.delayMs}ms',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 9,
              ),
            ),
          ],
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 14,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CONDITIONAL TRIGGER EDITOR (D.2)
// =============================================================================

/// Editor for conditional triggers
class ConditionalTriggerEditor extends StatefulWidget {
  final String eventId;

  const ConditionalTriggerEditor({
    super.key,
    required this.eventId,
  });

  @override
  State<ConditionalTriggerEditor> createState() =>
      _ConditionalTriggerEditorState();
}

class _ConditionalTriggerEditorState extends State<ConditionalTriggerEditor> {
  String _paramName = '';
  ConditionOperator _operator = ConditionOperator.equals;
  String _valueText = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        final event = provider.events.firstWhere(
          (e) => e.eventId == widget.eventId,
          orElse: () => throw ArgumentError('Event not found'),
        );

        final trigger = event.conditionalTrigger;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.rule_outlined,
                    size: 16,
                    color: FluxForgeTheme.accentOrange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Conditions',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (trigger != null)
                    _LogicToggle(
                      value: trigger.logic,
                      onChanged: (logic) {
                        provider.setConditionalTrigger(
                          widget.eventId,
                          trigger.copyWith(logic: logic),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Existing conditions
              if (trigger != null && trigger.conditions.isNotEmpty) ...[
                ...trigger.conditions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final condition = entry.value;
                  return _ConditionChip(
                    condition: condition,
                    showLogic: index > 0,
                    logic: trigger.logic,
                    onRemove: () =>
                        provider.removeTriggerCondition(widget.eventId, index),
                  );
                }),
                const SizedBox(height: 12),
              ],

              // Add new condition
              Row(
                children: [
                  // Parameter name
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _paramName = v),
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Parameter',
                        hintStyle: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 12,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: FluxForgeTheme.borderSubtle),
                        ),
                        filled: true,
                        fillColor: FluxForgeTheme.bgDeep,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Operator
                  SizedBox(
                    width: 60,
                    child: DropdownButtonFormField<ConditionOperator>(
                      value: _operator,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: FluxForgeTheme.borderSubtle),
                        ),
                        filled: true,
                        fillColor: FluxForgeTheme.bgDeep,
                      ),
                      dropdownColor: FluxForgeTheme.bgMid,
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 11,
                      ),
                      items: ConditionOperator.values.map((op) {
                        return DropdownMenuItem(
                          value: op,
                          child: Text(op.symbol),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _operator = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Value
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _valueText = v),
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 12,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Value',
                        hintStyle: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 12,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: FluxForgeTheme.borderSubtle),
                        ),
                        filled: true,
                        fillColor: FluxForgeTheme.bgDeep,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Add button
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: FluxForgeTheme.accentGreen,
                      size: 20,
                    ),
                    onPressed: _paramName.isEmpty || _valueText.isEmpty
                        ? null
                        : () {
                            // Parse value (number or string)
                            dynamic value = _valueText;
                            final numVal = num.tryParse(_valueText);
                            if (numVal != null) value = numVal;

                            provider.addTriggerCondition(
                              widget.eventId,
                              TriggerCondition(
                                paramName: _paramName,
                                operator: _operator,
                                value: value,
                              ),
                            );
                            setState(() {
                              _paramName = '';
                              _valueText = '';
                            });
                          },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogicToggle extends StatelessWidget {
  final ConditionLogic value;
  final ValueChanged<ConditionLogic> onChanged;

  const _LogicToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(ConditionLogic.and, 'AND'),
          _buildButton(ConditionLogic.or, 'OR'),
        ],
      ),
    );
  }

  Widget _buildButton(ConditionLogic logic, String label) {
    final isSelected = value == logic;
    return InkWell(
      onTap: () => onChanged(logic),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color:
              isSelected ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? FluxForgeTheme.accentBlue
                : FluxForgeTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  final TriggerCondition condition;
  final bool showLogic;
  final ConditionLogic logic;
  final VoidCallback onRemove;

  const _ConditionChip({
    required this.condition,
    required this.showLogic,
    required this.logic,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLogic)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                logic == ConditionLogic.and ? 'AND' : 'OR',
                style: TextStyle(
                  color: FluxForgeTheme.accentBlue,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: FluxForgeTheme.accentOrange.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    condition.paramName,
                    style: TextStyle(
                      color: FluxForgeTheme.accentOrange,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    ' ${condition.operator.symbol} ',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    condition.value.toString(),
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: onRemove,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: FluxForgeTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// RTPC BINDING EDITOR (D.3)
// =============================================================================

/// Editor for RTPC bindings
class RtpcBindingEditor extends StatefulWidget {
  final String eventId;

  const RtpcBindingEditor({
    super.key,
    required this.eventId,
  });

  @override
  State<RtpcBindingEditor> createState() => _RtpcBindingEditorState();
}

class _RtpcBindingEditorState extends State<RtpcBindingEditor> {
  String _rtpcName = '';
  String _eventParam = 'volume';
  RtpcCurveType _curveType = RtpcCurveType.linear;

  static const _commonRtpcs = [
    'winAmount',
    'spinSpeed',
    'anticipation',
    'cascadeLevel',
    'featureProgress',
    'balance',
  ];

  static const _eventParams = [
    'volume',
    'pitch',
    'pan',
    'lpf',
    'hpf',
    'delay',
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        final event = provider.events.firstWhere(
          (e) => e.eventId == widget.eventId,
          orElse: () => throw ArgumentError('Event not found'),
        );

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.tune_outlined,
                    size: 16,
                    color: FluxForgeTheme.accentCyan,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'RTPC Bindings',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${event.rtpcBindings.length} active',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Existing bindings
              if (event.rtpcBindings.isNotEmpty) ...[
                ...event.rtpcBindings.map((binding) => _RtpcBindingChip(
                      binding: binding,
                      onRemove: () => provider.removeRtpcBinding(
                        widget.eventId,
                        binding.rtpcName,
                        binding.eventParam,
                      ),
                    )),
                const SizedBox(height: 12),
              ],

              // Add new binding
              Row(
                children: [
                  // RTPC name
                  Expanded(
                    child: Autocomplete<String>(
                      optionsBuilder: (textValue) {
                        return _commonRtpcs.where((rtpc) => rtpc
                            .toLowerCase()
                            .contains(textValue.text.toLowerCase()));
                      },
                      onSelected: (v) => setState(() => _rtpcName = v),
                      fieldViewBuilder:
                          (context, controller, focusNode, onSubmit) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (v) => setState(() => _rtpcName = v),
                          style: TextStyle(
                            color: FluxForgeTheme.textPrimary,
                            fontSize: 12,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'RTPC Name',
                            hintStyle: TextStyle(
                              color: FluxForgeTheme.textSecondary,
                              fontSize: 12,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                              borderSide:
                                  BorderSide(color: FluxForgeTheme.borderSubtle),
                            ),
                            filled: true,
                            fillColor: FluxForgeTheme.bgDeep,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Arrow
                  Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: FluxForgeTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),

                  // Event param
                  SizedBox(
                    width: 80,
                    child: DropdownButtonFormField<String>(
                      value: _eventParam,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: FluxForgeTheme.borderSubtle),
                        ),
                        filled: true,
                        fillColor: FluxForgeTheme.bgDeep,
                      ),
                      dropdownColor: FluxForgeTheme.bgMid,
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 12,
                      ),
                      items: _eventParams.map((p) {
                        return DropdownMenuItem(
                          value: p,
                          child: Text(p),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _eventParam = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Curve type
                  SizedBox(
                    width: 80,
                    child: DropdownButtonFormField<RtpcCurveType>(
                      value: _curveType,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: FluxForgeTheme.borderSubtle),
                        ),
                        filled: true,
                        fillColor: FluxForgeTheme.bgDeep,
                      ),
                      dropdownColor: FluxForgeTheme.bgMid,
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 11,
                      ),
                      items: RtpcCurveType.values.map((c) {
                        return DropdownMenuItem(
                          value: c,
                          child: Text(c.displayName),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _curveType = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Add button
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: FluxForgeTheme.accentGreen,
                      size: 20,
                    ),
                    onPressed: _rtpcName.isEmpty
                        ? null
                        : () {
                            provider.addRtpcBinding(
                              widget.eventId,
                              RtpcBinding(
                                rtpcName: _rtpcName,
                                eventParam: _eventParam,
                                curveType: _curveType,
                              ),
                            );
                            setState(() => _rtpcName = '');
                          },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RtpcBindingChip extends StatelessWidget {
  final RtpcBinding binding;
  final VoidCallback onRemove;

  const _RtpcBindingChip({
    required this.binding,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentCyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.accentCyan.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(
            binding.rtpcName,
            style: TextStyle(
              color: FluxForgeTheme.accentCyan,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.arrow_forward,
            size: 12,
            color: FluxForgeTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            binding.eventParam,
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              binding.curveType.displayName,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 9,
              ),
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: onRemove,
            child: Icon(
              Icons.close,
              size: 14,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MUSIC CROSSFADE CONFIG (D.7)
// =============================================================================

/// Editor for music crossfade configuration
class MusicCrossfadeEditor extends StatelessWidget {
  final String eventId;

  const MusicCrossfadeEditor({
    super.key,
    required this.eventId,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        final event = provider.events.firstWhere(
          (e) => e.eventId == eventId,
          orElse: () => throw ArgumentError('Event not found'),
        );

        final config = event.crossfadeConfig ?? const MusicCrossfadeConfig();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.music_note_outlined,
                    size: 16,
                    color: const Color(0xFF9333EA),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Music Crossfade',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  // Enable toggle
                  Switch(
                    value: event.crossfadeConfig != null,
                    onChanged: (enabled) {
                      provider.setMusicCrossfadeConfig(
                        eventId,
                        enabled ? const MusicCrossfadeConfig() : null,
                      );
                    },
                    activeColor: const Color(0xFF9333EA),
                  ),
                ],
              ),

              if (event.crossfadeConfig != null) ...[
                const SizedBox(height: 12),

                // Preset buttons
                Row(
                  children: [
                    _PresetButton(
                      label: 'Equal Power',
                      isSelected: config == MusicCrossfadeConfig.equalPower,
                      onTap: () => provider.setMusicCrossfadeConfig(
                          eventId, MusicCrossfadeConfig.equalPower),
                    ),
                    const SizedBox(width: 8),
                    _PresetButton(
                      label: 'Quick Cut',
                      isSelected: config == MusicCrossfadeConfig.quickCut,
                      onTap: () => provider.setMusicCrossfadeConfig(
                          eventId, MusicCrossfadeConfig.quickCut),
                    ),
                    const SizedBox(width: 8),
                    _PresetButton(
                      label: 'Smooth',
                      isSelected: config == MusicCrossfadeConfig.smoothBlend,
                      onTap: () => provider.setMusicCrossfadeConfig(
                          eventId, MusicCrossfadeConfig.smoothBlend),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Duration slider
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        'Duration',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: config.durationMs.toDouble(),
                        min: 100,
                        max: 8000,
                        divisions: 79,
                        activeColor: const Color(0xFF9333EA),
                        onChanged: (v) {
                          provider.setMusicCrossfadeConfig(
                            eventId,
                            config.copyWith(durationMs: v.round()),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 50,
                      child: Text(
                        '${config.durationMs}ms',
                        style: TextStyle(
                          color: FluxForgeTheme.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),

                // Curves row
                Row(
                  children: [
                    // Out curve
                    Expanded(
                      child: _CurveSelector(
                        label: 'Out',
                        value: config.outCurve,
                        onChanged: (curve) {
                          provider.setMusicCrossfadeConfig(
                            eventId,
                            config.copyWith(outCurve: curve),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // In curve
                    Expanded(
                      child: _CurveSelector(
                        label: 'In',
                        value: config.inCurve,
                        onChanged: (curve) {
                          provider.setMusicCrossfadeConfig(
                            eventId,
                            config.copyWith(inCurve: curve),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Options row
                Row(
                  children: [
                    // Sync to beat
                    Checkbox(
                      value: config.syncToBeat,
                      onChanged: (v) {
                        provider.setMusicCrossfadeConfig(
                          eventId,
                          config.copyWith(syncToBeat: v ?? true),
                        );
                      },
                      activeColor: const Color(0xFF9333EA),
                    ),
                    Text(
                      'Sync to beat',
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Overlap
                    Text(
                      'Overlap: ',
                      style: TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    DropdownButton<CrossfadeOverlap>(
                      value: config.overlap,
                      dropdownColor: FluxForgeTheme.bgMid,
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 11,
                      ),
                      underline: const SizedBox(),
                      items: CrossfadeOverlap.values.map((o) {
                        return DropdownMenuItem(
                          value: o,
                          child: Text(o.displayName),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          provider.setMusicCrossfadeConfig(
                            eventId,
                            config.copyWith(overlap: v),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF9333EA).withValues(alpha: 0.2)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF9333EA)
                : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? const Color(0xFF9333EA)
                : FluxForgeTheme.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _CurveSelector extends StatelessWidget {
  final String label;
  final CrossfadeCurve value;
  final ValueChanged<CrossfadeCurve> onChanged;

  const _CurveSelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<CrossfadeCurve>(
            value: value,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
              filled: true,
              fillColor: FluxForgeTheme.bgDeep,
            ),
            dropdownColor: FluxForgeTheme.bgMid,
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
            ),
            items: CrossfadeCurve.values.map((c) {
              return DropdownMenuItem(
                value: c,
                child: Text(c.displayName),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// COMBINED ADVANCED CONFIG PANEL
// =============================================================================

/// Combined panel showing all advanced config options for an event
class AdvancedEventConfigPanel extends StatelessWidget {
  final String eventId;
  final bool showDependencies;
  final bool showConditions;
  final bool showRtpc;
  final bool showCrossfade;

  const AdvancedEventConfigPanel({
    super.key,
    required this.eventId,
    this.showDependencies = true,
    this.showConditions = true,
    this.showRtpc = true,
    this.showCrossfade = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDependencies) ...[
          EventDependencyEditor(eventId: eventId),
          const SizedBox(height: 12),
        ],
        if (showConditions) ...[
          ConditionalTriggerEditor(eventId: eventId),
          const SizedBox(height: 12),
        ],
        if (showRtpc) ...[
          RtpcBindingEditor(eventId: eventId),
          const SizedBox(height: 12),
        ],
        if (showCrossfade) MusicCrossfadeEditor(eventId: eventId),
      ],
    );
  }
}

// =============================================================================
// SPRINT 4: TEMPLATE INHERITANCE EDITOR (D.4)
// =============================================================================

/// Tree view for inheritable presets
class PresetInheritanceTreeView extends StatefulWidget {
  final ValueChanged<String>? onPresetSelected;
  final String? selectedPresetId;

  const PresetInheritanceTreeView({
    super.key,
    this.onPresetSelected,
    this.selectedPresetId,
  });

  @override
  State<PresetInheritanceTreeView> createState() => _PresetInheritanceTreeViewState();
}

class _PresetInheritanceTreeViewState extends State<PresetInheritanceTreeView> {
  final Set<String> _expandedNodes = {};
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        final tree = provider.getPresetTree();
        final filteredTree = _searchQuery.isEmpty
            ? tree
            : tree.where((item) =>
                item.preset.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                item.preset.presetId.toLowerCase().contains(_searchQuery.toLowerCase())
              ).toList();

        return Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      size: 16,
                      color: FluxForgeTheme.accentOrange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Preset Inheritance',
                      style: TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    // Add preset button
                    IconButton(
                      icon: Icon(
                        Icons.add_circle_outline,
                        size: 18,
                        color: FluxForgeTheme.accentGreen,
                      ),
                      tooltip: 'Create New Preset',
                      onPressed: () => _showCreatePresetDialog(context, provider),
                    ),
                  ],
                ),
              ),

              // Search
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search presets...',
                    hintStyle: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 12,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 16,
                      color: FluxForgeTheme.textSecondary,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                    ),
                    filled: true,
                    fillColor: FluxForgeTheme.bgDeep,
                  ),
                ),
              ),

              // Tree
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filteredTree.length,
                  itemBuilder: (context, index) {
                    final item = filteredTree[index];
                    return _PresetTreeNode(
                      preset: item.preset,
                      depth: item.depth,
                      hasChildren: item.hasChildren,
                      isExpanded: _expandedNodes.contains(item.preset.presetId),
                      isSelected: widget.selectedPresetId == item.preset.presetId,
                      onTap: () => widget.onPresetSelected?.call(item.preset.presetId),
                      onExpandToggle: () {
                        setState(() {
                          if (_expandedNodes.contains(item.preset.presetId)) {
                            _expandedNodes.remove(item.preset.presetId);
                          } else {
                            _expandedNodes.add(item.preset.presetId);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreatePresetDialog(BuildContext context, AutoEventBuilderProvider provider) {
    showDialog(
      context: context,
      builder: (context) => _CreatePresetDialog(provider: provider),
    );
  }
}

class _PresetTreeNode extends StatelessWidget {
  final InheritablePreset preset;
  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onExpandToggle;

  const _PresetTreeNode({
    required this.preset,
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
    required this.isSelected,
    required this.onTap,
    required this.onExpandToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: EdgeInsets.only(
          left: 8.0 + depth * 16.0,
          right: 8,
          top: 6,
          bottom: 6,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.15)
              : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            // Expand/collapse
            if (hasChildren)
              InkWell(
                onTap: onExpandToggle,
                child: Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: FluxForgeTheme.textSecondary,
                ),
              )
            else
              const SizedBox(width: 16),

            const SizedBox(width: 4),

            // Icon
            Icon(
              preset.isAbstract ? Icons.category_outlined : Icons.description_outlined,
              size: 14,
              color: preset.isSealed
                  ? FluxForgeTheme.accentOrange
                  : preset.isAbstract
                      ? FluxForgeTheme.textSecondary
                      : FluxForgeTheme.accentBlue,
            ),
            const SizedBox(width: 8),

            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: TextStyle(
                      color: isSelected
                          ? FluxForgeTheme.accentBlue
                          : FluxForgeTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (preset.extendsPresetId != null)
                    Text(
                      'extends ${preset.extendsPresetId}',
                      style: TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 9,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),

            // Badges
            if (preset.isSealed)
              _Badge(label: 'SEALED', color: FluxForgeTheme.accentOrange),
            if (preset.isAbstract)
              _Badge(label: 'ABSTRACT', color: FluxForgeTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CreatePresetDialog extends StatefulWidget {
  final AutoEventBuilderProvider provider;

  const _CreatePresetDialog({required this.provider});

  @override
  State<_CreatePresetDialog> createState() => _CreatePresetDialogState();
}

class _CreatePresetDialogState extends State<_CreatePresetDialog> {
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  String? _parentId;
  String _category = 'General';
  bool _isAbstract = false;
  bool _isSealed = false;

  @override
  Widget build(BuildContext context) {
    final presets = widget.provider.inheritanceResolver.allPresets;
    final availableParents = presets.where((p) => !p.isSealed).toList();

    return AlertDialog(
      backgroundColor: FluxForgeTheme.bgMid,
      title: Text(
        'Create Inheritable Preset',
        style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Name
            TextField(
              controller: _nameController,
              style: TextStyle(color: FluxForgeTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                // Auto-generate ID from name
                _idController.text = v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
              },
            ),
            const SizedBox(height: 12),

            // ID
            TextField(
              controller: _idController,
              style: TextStyle(color: FluxForgeTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Preset ID',
                labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Parent (extends)
            DropdownButtonFormField<String?>(
              value: _parentId,
              decoration: InputDecoration(
                labelText: 'Extends (parent)',
                labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
                border: const OutlineInputBorder(),
              ),
              dropdownColor: FluxForgeTheme.bgMid,
              style: TextStyle(color: FluxForgeTheme.textPrimary),
              items: [
                const DropdownMenuItem(value: null, child: Text('(None - Root Preset)')),
                ...availableParents.map((p) =>
                  DropdownMenuItem(value: p.presetId, child: Text(p.name)),
                ),
              ],
              onChanged: (v) => setState(() => _parentId = v),
            ),
            const SizedBox(height: 12),

            // Category
            TextFormField(
              initialValue: _category,
              style: TextStyle(color: FluxForgeTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Category',
                labelStyle: TextStyle(color: FluxForgeTheme.textSecondary),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 12),

            // Flags
            Row(
              children: [
                Checkbox(
                  value: _isAbstract,
                  onChanged: (v) => setState(() => _isAbstract = v ?? false),
                  activeColor: FluxForgeTheme.accentBlue,
                ),
                Text('Abstract', style: TextStyle(color: FluxForgeTheme.textPrimary)),
                const SizedBox(width: 24),
                Checkbox(
                  value: _isSealed,
                  onChanged: (v) => setState(() => _isSealed = v ?? false),
                  activeColor: FluxForgeTheme.accentOrange,
                ),
                Text('Sealed', style: TextStyle(color: FluxForgeTheme.textPrimary)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: FluxForgeTheme.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _nameController.text.isEmpty || _idController.text.isEmpty
              ? null
              : () {
                  final preset = InheritablePreset(
                    presetId: _idController.text,
                    name: _nameController.text,
                    extendsPresetId: _parentId,
                    category: _category,
                    isAbstract: _isAbstract,
                    isSealed: _isSealed,
                    createdAt: DateTime.now(),
                  );
                  widget.provider.registerInheritablePreset(preset);
                  Navigator.pop(context);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentBlue,
          ),
          child: const Text('Create'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }
}

// =============================================================================
// SPRINT 4: BATCH DROP PANEL (D.5)
// =============================================================================

/// Panel for configuring and executing batch drops
class BatchDropPanel extends StatefulWidget {
  final AudioAsset? selectedAsset;
  final VoidCallback? onDropComplete;

  const BatchDropPanel({
    super.key,
    this.selectedAsset,
    this.onDropComplete,
  });

  @override
  State<BatchDropPanel> createState() => _BatchDropPanelState();
}

class _BatchDropPanelState extends State<BatchDropPanel> {
  BatchDropConfig _config = BatchDropConfig.reelStopsConfig;
  bool _showAdvanced = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.grid_view_outlined,
                    size: 16,
                    color: FluxForgeTheme.accentGreen,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Batch Drop',
                    style: TextStyle(
                      color: FluxForgeTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (widget.selectedAsset != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.selectedAsset!.displayName,
                        style: TextStyle(
                          color: FluxForgeTheme.accentBlue,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Preset buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _BatchPresetButton(
                    label: 'Reel Stops',
                    isSelected: _config == BatchDropConfig.reelStopsConfig,
                    onTap: () => setState(() => _config = BatchDropConfig.reelStopsConfig),
                  ),
                  _BatchPresetButton(
                    label: 'Cascade',
                    isSelected: _config == BatchDropConfig.cascadeConfig,
                    onTap: () => setState(() => _config = BatchDropConfig.cascadeConfig),
                  ),
                  _BatchPresetButton(
                    label: 'Win Tiers',
                    isSelected: _config == BatchDropConfig.winTiersConfig,
                    onTap: () => setState(() => _config = BatchDropConfig.winTiersConfig),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Group type selector
              Row(
                children: [
                  Text(
                    'Target Group:',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<GroupTargetType>(
                      value: _config.groupType,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                        ),
                        filled: true,
                        fillColor: FluxForgeTheme.bgDeep,
                      ),
                      dropdownColor: FluxForgeTheme.bgMid,
                      style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                      items: GroupTargetType.values.map((t) {
                        return DropdownMenuItem(
                          value: t,
                          child: Text(t.displayName),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _config = _config.copyWith(groupType: v));
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Spatial mode selector
              Row(
                children: [
                  Text(
                    'Spatial:',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<SpatialDistributionMode>(
                      value: _config.spatialMode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                        ),
                        filled: true,
                        fillColor: FluxForgeTheme.bgDeep,
                      ),
                      dropdownColor: FluxForgeTheme.bgMid,
                      style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                      items: SpatialDistributionMode.values.map((m) {
                        return DropdownMenuItem(
                          value: m,
                          child: Text(m.displayName),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _config = _config.copyWith(spatialMode: v));
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Variation mode
              Row(
                children: [
                  Text(
                    'Variation:',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<ParameterVariationMode>(
                      value: _config.variationMode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                        ),
                        filled: true,
                        fillColor: FluxForgeTheme.bgDeep,
                      ),
                      dropdownColor: FluxForgeTheme.bgMid,
                      style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                      items: ParameterVariationMode.values.map((m) {
                        return DropdownMenuItem(
                          value: m,
                          child: Text(m.displayName),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _config = _config.copyWith(variationMode: v));
                        }
                      },
                    ),
                  ),
                ],
              ),

              // Advanced toggle
              InkWell(
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvanced ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: FluxForgeTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Advanced Options',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Advanced options
              if (_showAdvanced) ...[
                // Stagger
                Row(
                  children: [
                    Text(
                      'Stagger:',
                      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                    ),
                    Expanded(
                      child: Slider(
                        value: _config.staggerMs.toDouble(),
                        min: 0,
                        max: 500,
                        divisions: 50,
                        activeColor: FluxForgeTheme.accentGreen,
                        onChanged: (v) {
                          setState(() => _config = _config.copyWith(staggerMs: v.round()));
                        },
                      ),
                    ),
                    SizedBox(
                      width: 50,
                      child: Text(
                        '${_config.staggerMs}ms',
                        style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                      ),
                    ),
                  ],
                ),

                // Create dependencies
                Row(
                  children: [
                    Checkbox(
                      value: _config.createDependencies,
                      onChanged: (v) {
                        setState(() => _config = _config.copyWith(createDependencies: v ?? false));
                      },
                      activeColor: FluxForgeTheme.accentGreen,
                    ),
                    Text(
                      'Create dependencies between events',
                      style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                    ),
                  ],
                ),

                // Event ID prefix
                Row(
                  children: [
                    Text(
                      'ID Prefix:',
                      style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                          ),
                          filled: true,
                          fillColor: FluxForgeTheme.bgDeep,
                        ),
                        controller: TextEditingController(text: _config.eventIdPrefix),
                        onChanged: (v) {
                          setState(() => _config = _config.copyWith(eventIdPrefix: v));
                        },
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // Preview info
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgDeep,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: FluxForgeTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Will create ${_config.getTargetIds().length} events',
                      style: TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Execute button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.selectedAsset == null
                      ? null
                      : () {
                          final result = provider.executeBatchDrop(
                            widget.selectedAsset!,
                            _config,
                          );
                          if (result.allSucceeded) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Created ${result.count} events'),
                                backgroundColor: FluxForgeTheme.accentGreen,
                              ),
                            );
                            widget.onDropComplete?.call();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Errors: ${result.errors.join(", ")}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: const Text('Execute Batch Drop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FluxForgeTheme.accentGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BatchPresetButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BatchPresetButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxForgeTheme.accentGreen.withValues(alpha: 0.2)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? FluxForgeTheme.accentGreen : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? FluxForgeTheme.accentGreen : FluxForgeTheme.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SPRINT 4: BINDING GRAPH VISUALIZATION (D.6)
// =============================================================================

/// Interactive binding graph visualization
class BindingGraphView extends StatefulWidget {
  final String? focusEventId;
  final Set<GraphNodeType>? filterNodeTypes;
  final Set<GraphEdgeType>? filterEdgeTypes;

  const BindingGraphView({
    super.key,
    this.focusEventId,
    this.filterNodeTypes,
    this.filterEdgeTypes,
  });

  @override
  State<BindingGraphView> createState() => _BindingGraphViewState();
}

class _BindingGraphViewState extends State<BindingGraphView> {
  late BindingGraph _graph;
  String? _hoveredNodeId;
  String? _selectedNodeId;
  double _zoom = 1.0;
  Offset _pan = Offset.zero;
  String _searchQuery = '';
  GraphLayoutAlgorithm _layoutAlgorithm = GraphLayoutAlgorithm.hierarchical;

  @override
  void initState() {
    super.initState();
    _buildGraph();
  }

  void _buildGraph() {
    final provider = context.read<AutoEventBuilderProvider>();

    if (widget.focusEventId != null) {
      _graph = provider.getEventSubgraph(widget.focusEventId!, depth: 2);
    } else if (widget.filterNodeTypes != null || widget.filterEdgeTypes != null) {
      _graph = provider.getFilteredBindingGraph(
        includeNodeTypes: widget.filterNodeTypes,
        includeEdgeTypes: widget.filterEdgeTypes,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
    } else {
      _graph = provider.buildBindingGraph();
    }

    provider.applyGraphLayout(_graph, algorithm: _layoutAlgorithm);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        return Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Column(
            children: [
              // Toolbar
              _GraphToolbar(
                onRefresh: () {
                  setState(() => _buildGraph());
                },
                onLayoutChange: (algorithm) {
                  setState(() {
                    _layoutAlgorithm = algorithm;
                    _buildGraph();
                  });
                },
                currentLayout: _layoutAlgorithm,
                onSearchChange: (query) {
                  setState(() {
                    _searchQuery = query;
                    _buildGraph();
                  });
                },
                onExportDot: () {
                  final dot = provider.exportGraphToDot(_graph);
                  // In production: save to file or copy to clipboard
                  debugPrint(dot);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('DOT exported to console')),
                  );
                },
                stats: _graph.getStatistics(),
              ),

              // Graph canvas
              Expanded(
                child: GestureDetector(
                  onScaleStart: (details) {
                    // Store initial scale
                  },
                  onScaleUpdate: (details) {
                    setState(() {
                      _zoom = (_zoom * details.scale).clamp(0.3, 3.0);
                      _pan += details.focalPointDelta;
                    });
                  },
                  child: ClipRect(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _GraphPainter(
                        graph: _graph,
                        zoom: _zoom,
                        pan: _pan,
                        hoveredNodeId: _hoveredNodeId,
                        selectedNodeId: _selectedNodeId,
                      ),
                      child: MouseRegion(
                        onHover: (event) {
                          final nodeId = _hitTestNode(event.localPosition);
                          if (nodeId != _hoveredNodeId) {
                            setState(() => _hoveredNodeId = nodeId);
                          }
                        },
                        onExit: (_) {
                          if (_hoveredNodeId != null) {
                            setState(() => _hoveredNodeId = null);
                          }
                        },
                        child: GestureDetector(
                          onTapUp: (details) {
                            final nodeId = _hitTestNode(details.localPosition);
                            setState(() => _selectedNodeId = nodeId);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Node info panel
              if (_selectedNodeId != null)
                _NodeInfoPanel(
                  node: _graph.getNode(_selectedNodeId!)!,
                  connectedNodes: _graph.getConnectedNodes(_selectedNodeId!),
                  incomingEdges: _graph.getIncomingEdges(_selectedNodeId!),
                  outgoingEdges: _graph.getOutgoingEdges(_selectedNodeId!),
                  onClose: () => setState(() => _selectedNodeId = null),
                ),
            ],
          ),
        );
      },
    );
  }

  String? _hitTestNode(Offset localPosition) {
    // Simple hit testing - in production use RTree or similar
    final size = context.size ?? const Size(400, 400);
    for (final node in _graph.nodes) {
      final nodePos = Offset(
        node.x * size.width * _zoom + _pan.dx,
        node.y * size.height * _zoom + _pan.dy,
      );
      if ((localPosition - nodePos).distance < 20 * _zoom) {
        return node.nodeId;
      }
    }
    return null;
  }
}

class _GraphToolbar extends StatelessWidget {
  final VoidCallback onRefresh;
  final ValueChanged<GraphLayoutAlgorithm> onLayoutChange;
  final GraphLayoutAlgorithm currentLayout;
  final ValueChanged<String> onSearchChange;
  final VoidCallback onExportDot;
  final Map<String, int> stats;

  const _GraphToolbar({
    required this.onRefresh,
    required this.onLayoutChange,
    required this.currentLayout,
    required this.onSearchChange,
    required this.onExportDot,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Search
          SizedBox(
            width: 150,
            child: TextField(
              onChanged: onSearchChange,
              style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search...',
                hintStyle: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 11),
                prefixIcon: Icon(Icons.search, size: 14, color: FluxForgeTheme.textSecondary),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: FluxForgeTheme.borderSubtle),
                ),
                filled: true,
                fillColor: FluxForgeTheme.bgDeep,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Layout selector
          DropdownButton<GraphLayoutAlgorithm>(
            value: currentLayout,
            dropdownColor: FluxForgeTheme.bgMid,
            style: TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 11),
            underline: const SizedBox(),
            items: GraphLayoutAlgorithm.values.map((l) {
              return DropdownMenuItem(
                value: l,
                child: Text(l.name),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) onLayoutChange(v);
            },
          ),
          const SizedBox(width: 8),

          // Refresh
          IconButton(
            icon: Icon(Icons.refresh, size: 16, color: FluxForgeTheme.textSecondary),
            tooltip: 'Refresh',
            onPressed: onRefresh,
          ),

          // Export
          IconButton(
            icon: Icon(Icons.download, size: 16, color: FluxForgeTheme.textSecondary),
            tooltip: 'Export DOT',
            onPressed: onExportDot,
          ),

          const Spacer(),

          // Stats
          Text(
            '${stats['totalNodes']} nodes • ${stats['totalEdges']} edges',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final BindingGraph graph;
  final double zoom;
  final Offset pan;
  final String? hoveredNodeId;
  final String? selectedNodeId;

  _GraphPainter({
    required this.graph,
    required this.zoom,
    required this.pan,
    this.hoveredNodeId,
    this.selectedNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw edges
    for (final edge in graph.edges) {
      final source = graph.getNode(edge.sourceId);
      final target = graph.getNode(edge.targetId);
      if (source == null || target == null) continue;

      final p1 = Offset(
        source.x * size.width * zoom + pan.dx,
        source.y * size.height * zoom + pan.dy,
      );
      final p2 = Offset(
        target.x * size.width * zoom + pan.dx,
        target.y * size.height * zoom + pan.dy,
      );

      final paint = Paint()
        ..color = _getEdgeColor(edge.edgeType).withValues(alpha: 0.6)
        ..strokeWidth = 1.5 * zoom
        ..style = PaintingStyle.stroke;

      if (edge.edgeType.lineStyle == 'dashed') {
        // Draw dashed line
        _drawDashedLine(canvas, p1, p2, paint);
      } else {
        canvas.drawLine(p1, p2, paint);
      }

      // Draw arrowhead
      _drawArrowhead(canvas, p1, p2, paint.color, zoom);
    }

    // Draw nodes
    for (final node in graph.nodes) {
      final pos = Offset(
        node.x * size.width * zoom + pan.dx,
        node.y * size.height * zoom + pan.dy,
      );

      final isHovered = node.nodeId == hoveredNodeId;
      final isSelected = node.nodeId == selectedNodeId;
      final radius = (isHovered || isSelected ? 18 : 14) * zoom;

      // Node background
      final bgPaint = Paint()
        ..color = _getNodeColor(node.nodeType)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, radius, bgPaint);

      // Node border
      if (isSelected) {
        final borderPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * zoom;
        canvas.drawCircle(pos, radius, borderPaint);
      }

      // Highlighted nodes
      if (node.isHighlighted) {
        final glowPaint = Paint()
          ..color = Colors.yellow.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pos, radius + 4 * zoom, glowPaint);
      }

      // Label
      final textSpan = TextSpan(
        text: node.label.length > 10 ? '${node.label.substring(0, 10)}...' : node.label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 9 * zoom,
          fontWeight: FontWeight.w500,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy + radius + 4 * zoom),
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashLength = 5.0;
    const gapLength = 3.0;
    final direction = (p2 - p1).direction;
    final distance = (p2 - p1).distance;

    var current = 0.0;
    while (current < distance) {
      final start = Offset(
        p1.dx + current * (p2.dx - p1.dx) / distance,
        p1.dy + current * (p2.dy - p1.dy) / distance,
      );
      final end = Offset(
        p1.dx + (current + dashLength).clamp(0, distance) * (p2.dx - p1.dx) / distance,
        p1.dy + (current + dashLength).clamp(0, distance) * (p2.dy - p1.dy) / distance,
      );
      canvas.drawLine(start, end, paint);
      current += dashLength + gapLength;
    }
  }

  void _drawArrowhead(Canvas canvas, Offset from, Offset to, Color color, double zoom) {
    final direction = (to - from).direction;
    final arrowSize = 8 * zoom;
    final arrowAngle = 0.5;

    final path = Path();
    path.moveTo(to.dx, to.dy);
    path.lineTo(
      to.dx - arrowSize * math.cos(direction - arrowAngle),
      to.dy - arrowSize * math.sin(direction - arrowAngle),
    );
    path.lineTo(
      to.dx - arrowSize * math.cos(direction + arrowAngle),
      to.dy - arrowSize * math.sin(direction + arrowAngle),
    );
    path.close();

    canvas.drawPath(path, Paint()..color = color);
  }

  Color _getNodeColor(GraphNodeType type) {
    switch (type) {
      case GraphNodeType.event: return const Color(0xFF4A9EFF);
      case GraphNodeType.target: return const Color(0xFF40FF90);
      case GraphNodeType.preset: return const Color(0xFFFF9040);
      case GraphNodeType.bus: return const Color(0xFF40C8FF);
      case GraphNodeType.rtpc: return const Color(0xFFFFD700);
      case GraphNodeType.condition: return const Color(0xFFFF4060);
    }
  }

  Color _getEdgeColor(GraphEdgeType type) {
    switch (type) {
      case GraphEdgeType.binding: return const Color(0xFF4A9EFF);
      case GraphEdgeType.dependency: return const Color(0xFFFF9040);
      case GraphEdgeType.usesPreset: return const Color(0xFF888888);
      case GraphEdgeType.routesToBus: return const Color(0xFF40C8FF);
      case GraphEdgeType.rtpcBinding: return const Color(0xFFFFD700);
      case GraphEdgeType.conditionalTrigger: return const Color(0xFFFF4060);
      case GraphEdgeType.inherits: return const Color(0xFF9333EA);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.graph != graph ||
        oldDelegate.zoom != zoom ||
        oldDelegate.pan != pan ||
        oldDelegate.hoveredNodeId != hoveredNodeId ||
        oldDelegate.selectedNodeId != selectedNodeId;
  }
}

class _NodeInfoPanel extends StatelessWidget {
  final GraphNode node;
  final List<GraphNode> connectedNodes;
  final List<GraphEdge> incomingEdges;
  final List<GraphEdge> outgoingEdges;
  final VoidCallback onClose;

  const _NodeInfoPanel({
    required this.node,
    required this.connectedNodes,
    required this.incomingEdges,
    required this.outgoingEdges,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          top: BorderSide(color: FluxForgeTheme.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getNodeColor(node.nodeType).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  node.nodeType.displayName,
                  style: TextStyle(
                    color: _getNodeColor(node.nodeType),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.label,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: FluxForgeTheme.textSecondary),
                onPressed: onClose,
              ),
            ],
          ),
          if (node.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              node.subtitle!,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${incomingEdges.length} incoming',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
              ),
              const SizedBox(width: 12),
              Text(
                '${outgoingEdges.length} outgoing',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
              ),
              const SizedBox(width: 12),
              Text(
                '${connectedNodes.length} connected',
                style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getNodeColor(GraphNodeType type) {
    switch (type) {
      case GraphNodeType.event: return const Color(0xFF4A9EFF);
      case GraphNodeType.target: return const Color(0xFF40FF90);
      case GraphNodeType.preset: return const Color(0xFFFF9040);
      case GraphNodeType.bus: return const Color(0xFF40C8FF);
      case GraphNodeType.rtpc: return const Color(0xFFFFD700);
      case GraphNodeType.condition: return const Color(0xFFFF4060);
    }
  }
}

// =============================================================================
// COMBINED SPRINT 4 PANEL
// =============================================================================

/// Combined panel for all Sprint 4 features
class Sprint4FeaturesPanel extends StatefulWidget {
  final String? selectedEventId;
  final AudioAsset? selectedAsset;

  const Sprint4FeaturesPanel({
    super.key,
    this.selectedEventId,
    this.selectedAsset,
  });

  @override
  State<Sprint4FeaturesPanel> createState() => _Sprint4FeaturesPanelState();
}

class _Sprint4FeaturesPanelState extends State<Sprint4FeaturesPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          // Tab bar
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: FluxForgeTheme.accentBlue,
              unselectedLabelColor: FluxForgeTheme.textSecondary,
              indicatorColor: FluxForgeTheme.accentBlue,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Inheritance', icon: Icon(Icons.account_tree_outlined, size: 16)),
                Tab(text: 'Batch Drop', icon: Icon(Icons.grid_view_outlined, size: 16)),
                Tab(text: 'Graph View', icon: Icon(Icons.hub_outlined, size: 16)),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // D.4: Template Inheritance
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: PresetInheritanceTreeView(
                    onPresetSelected: (presetId) {
                      // Handle preset selection
                    },
                  ),
                ),

                // D.5: Batch Drop
                SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: BatchDropPanel(
                    selectedAsset: widget.selectedAsset,
                  ),
                ),

                // D.6: Binding Graph
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: BindingGraphView(
                    focusEventId: widget.selectedEventId,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
