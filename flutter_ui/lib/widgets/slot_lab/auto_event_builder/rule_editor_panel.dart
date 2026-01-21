/// Rule Editor Panel — Custom Drop Rule Creation
///
/// UI for creating and editing custom DropRules:
/// - Match conditions (asset type, target type, tags)
/// - Output templates (event ID, intent, bus, trigger)
/// - Priority and preset assignment
/// - Rule testing preview
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md Section 5
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/auto_event_builder_models.dart';
import '../../../providers/auto_event_builder_provider.dart';
import '../../../theme/fluxforge_theme.dart';

class RuleEditorPanel extends StatefulWidget {
  final DropRule? initialRule;
  final VoidCallback? onClose;

  const RuleEditorPanel({
    super.key,
    this.initialRule,
    this.onClose,
  });

  @override
  State<RuleEditorPanel> createState() => _RuleEditorPanelState();
}

class _RuleEditorPanelState extends State<RuleEditorPanel> {
  late TextEditingController _nameController;
  late TextEditingController _eventIdTemplateController;
  late TextEditingController _intentTemplateController;
  late TextEditingController _defaultBusController;
  late TextEditingController _defaultTriggerController;

  int _priority = 50;
  AssetType? _assetType;
  TargetType? _targetType;
  List<String> _assetTags = [];
  List<String> _targetTags = [];
  String _defaultPresetId = 'ui_click_secondary';

  bool _isEditing = false;

  // For tag input
  final TextEditingController _assetTagController = TextEditingController();
  final TextEditingController _targetTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _eventIdTemplateController = TextEditingController(text: '{target}.{asset}');
    _intentTemplateController = TextEditingController(text: '{target}.triggered');
    _defaultBusController = TextEditingController(text: 'SFX');
    _defaultTriggerController = TextEditingController(text: 'press');

    if (widget.initialRule != null) {
      _loadRule(widget.initialRule!);
      _isEditing = true;
    }
  }

  void _loadRule(DropRule rule) {
    _nameController.text = rule.name;
    _eventIdTemplateController.text = rule.eventIdTemplate;
    _intentTemplateController.text = rule.intentTemplate;
    _defaultBusController.text = rule.defaultBus;
    _defaultTriggerController.text = rule.defaultTrigger;
    _priority = rule.priority;
    _assetType = rule.assetType;
    _targetType = rule.targetType;
    _assetTags = List.from(rule.assetTags);
    _targetTags = List.from(rule.targetTags);
    _defaultPresetId = rule.defaultPresetId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _eventIdTemplateController.dispose();
    _intentTemplateController.dispose();
    _defaultBusController.dispose();
    _defaultTriggerController.dispose();
    _assetTagController.dispose();
    _targetTagController.dispose();
    super.dispose();
  }

  DropRule _buildRule() {
    final name = _nameController.text.trim();
    final id = name.isEmpty
        ? 'custom_rule_${DateTime.now().millisecondsSinceEpoch}'
        : 'custom_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    return DropRule(
      ruleId: widget.initialRule?.ruleId ?? id,
      name: name.isEmpty ? 'Custom Rule' : name,
      priority: _priority,
      assetType: _assetType,
      targetType: _targetType,
      assetTags: _assetTags,
      targetTags: _targetTags,
      eventIdTemplate: _eventIdTemplateController.text,
      intentTemplate: _intentTemplateController.text,
      defaultPresetId: _defaultPresetId,
      defaultBus: _defaultBusController.text,
      defaultTrigger: _defaultTriggerController.text,
    );
  }

  void _saveRule() {
    final provider = context.read<AutoEventBuilderProvider>();
    final rule = _buildRule();

    if (_isEditing && widget.initialRule != null) {
      provider.removeRule(widget.initialRule!.ruleId);
    }
    provider.addRule(rule);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Rule "${rule.name}" saved'),
        backgroundColor: FluxForgeTheme.bgMid,
        duration: const Duration(seconds: 2),
      ),
    );

    widget.onClose?.call();
  }

  void _addAssetTag() {
    final tag = _assetTagController.text.trim().toLowerCase();
    if (tag.isNotEmpty && !_assetTags.contains(tag)) {
      setState(() {
        _assetTags.add(tag);
        _assetTagController.clear();
      });
    }
  }

  void _addTargetTag() {
    final tag = _targetTagController.text.trim().toLowerCase();
    if (tag.isNotEmpty && !_targetTags.contains(tag)) {
      setState(() {
        _targetTags.add(tag);
        _targetTagController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _Header(
            isEditing: _isEditing,
            onClose: widget.onClose,
            onSave: _saveRule,
          ),

          const SizedBox(height: 16),

          // Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name & Priority
                  _SectionHeader(title: 'General'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _TextField(
                          label: 'Rule Name',
                          controller: _nameController,
                          hint: 'My Custom Rule',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PriorityField(
                          value: _priority,
                          onChanged: (v) => setState(() => _priority = v),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Match Conditions
                  _SectionHeader(title: 'Match Conditions'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DropdownField<AssetType?>(
                          label: 'Asset Type',
                          value: _assetType,
                          items: [null, ...AssetType.values],
                          itemLabel: (v) => v?.displayName ?? 'Any',
                          onChanged: (v) => setState(() => _assetType = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DropdownField<TargetType?>(
                          label: 'Target Type',
                          value: _targetType,
                          items: [null, ...TargetType.values],
                          itemLabel: (v) => v?.displayName ?? 'Any',
                          onChanged: (v) => setState(() => _targetType = v),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Asset Tags
                  _TagsField(
                    label: 'Asset Tags (match any)',
                    tags: _assetTags,
                    controller: _assetTagController,
                    onAdd: _addAssetTag,
                    onRemove: (tag) => setState(() => _assetTags.remove(tag)),
                    suggestions: AssetTags.all,
                  ),

                  const SizedBox(height: 12),

                  // Target Tags
                  _TagsField(
                    label: 'Target Tags (match any)',
                    tags: _targetTags,
                    controller: _targetTagController,
                    onAdd: _addTargetTag,
                    onRemove: (tag) => setState(() => _targetTags.remove(tag)),
                    suggestions: const ['primary', 'secondary', 'cta', 'spin', 'win', 'feature'],
                  ),

                  const SizedBox(height: 20),

                  // Output Templates
                  _SectionHeader(title: 'Output Templates'),
                  const SizedBox(height: 8),
                  _TextField(
                    label: 'Event ID Template',
                    controller: _eventIdTemplateController,
                    hint: '{target}.{asset}',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Placeholders: {target}, {asset}, {type}',
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted.withValues(alpha: 0.6),
                      fontSize: 9,
                    ),
                  ),

                  const SizedBox(height: 8),
                  _TextField(
                    label: 'Intent Template',
                    controller: _intentTemplateController,
                    hint: '{target}.triggered',
                  ),

                  const SizedBox(height: 20),

                  // Defaults
                  _SectionHeader(title: 'Defaults'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _TextField(
                          label: 'Default Bus',
                          controller: _defaultBusController,
                          hint: 'SFX',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TextField(
                          label: 'Default Trigger',
                          controller: _defaultTriggerController,
                          hint: 'press',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _PresetDropdown(
                    value: _defaultPresetId,
                    onChanged: (v) => setState(() => _defaultPresetId = v),
                  ),

                  const SizedBox(height: 20),

                  // Preview
                  _RulePreview(rule: _buildRule()),
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
// HEADER
// =============================================================================

class _Header extends StatelessWidget {
  final bool isEditing;
  final VoidCallback? onClose;
  final VoidCallback onSave;

  const _Header({
    required this.isEditing,
    this.onClose,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.rule,
          size: 18,
          color: FluxForgeTheme.accentCyan,
        ),
        const SizedBox(width: 8),
        Text(
          isEditing ? 'Edit Rule' : 'New Rule',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (onClose != null)
          IconButton(
            icon: Icon(Icons.close, size: 18, color: FluxForgeTheme.textMuted),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.save, size: 16),
          label: const Text('Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: FluxForgeTheme.accentGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// SECTION HEADER
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentCyan,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// FORM FIELDS
// =============================================================================

class _TextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;

  const _TextField({
    required this.label,
    required this.controller,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: TextField(
            controller: controller,
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: InputBorder.none,
              hintText: hint,
              hintStyle: TextStyle(color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ],
    );
  }
}

class _PriorityField extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _PriorityField({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Priority',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '$value',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: FluxForgeTheme.accentCyan,
            inactiveTrackColor: FluxForgeTheme.bgMid,
            thumbColor: FluxForgeTheme.accentCyan,
          ),
          child: Slider(
            value: value.toDouble(),
            min: 1,
            max: 100,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: FluxForgeTheme.bgMid,
              style: TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 12,
              ),
              icon: Icon(Icons.expand_more, size: 16, color: FluxForgeTheme.textMuted),
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(itemLabel(item)),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _TagsField extends StatelessWidget {
  final String label;
  final List<String> tags;
  final TextEditingController controller;
  final VoidCallback onAdd;
  final void Function(String) onRemove;
  final List<String> suggestions;

  const _TagsField({
    required this.label,
    required this.tags,
    required this.controller,
    required this.onAdd,
    required this.onRemove,
    required this.suggestions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),

        // Tag input
        Container(
          height: 32,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluxForgeTheme.borderSubtle),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: InputBorder.none,
                    hintText: 'Add tag...',
                    hintStyle: TextStyle(color: FluxForgeTheme.textMuted.withValues(alpha: 0.5)),
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add, size: 16, color: FluxForgeTheme.accentBlue),
                onPressed: onAdd,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        // Current tags
        if (tags.isNotEmpty)
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: tags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: FluxForgeTheme.accentBlue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tag,
                      style: TextStyle(
                        color: FluxForgeTheme.accentBlue,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => onRemove(tag),
                      child: Icon(
                        Icons.close,
                        size: 12,
                        color: FluxForgeTheme.accentBlue.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),

        // Suggestions
        if (tags.length < 3 && suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: suggestions
                  .where((s) => !tags.contains(s))
                  .take(6)
                  .map((s) {
                return GestureDetector(
                  onTap: () {
                    controller.text = s;
                    onAdd();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeep,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: FluxForgeTheme.borderSubtle),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        color: FluxForgeTheme.textMuted,
                        fontSize: 9,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

class _PresetDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _PresetDropdown({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AutoEventBuilderProvider>(
      builder: (context, provider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Default Preset',
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  dropdownColor: FluxForgeTheme.bgMid,
                  style: TextStyle(
                    color: FluxForgeTheme.textPrimary,
                    fontSize: 12,
                  ),
                  icon: Icon(Icons.expand_more, size: 16, color: FluxForgeTheme.textMuted),
                  items: provider.presets.map((p) {
                    return DropdownMenuItem(
                      value: p.presetId,
                      child: Text(p.name),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) onChanged(v);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// RULE PREVIEW
// =============================================================================

class _RulePreview extends StatelessWidget {
  final DropRule rule;

  const _RulePreview({required this.rule});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.preview, size: 14, color: FluxForgeTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                'Preview',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Match conditions
          _PreviewRow(
            label: 'Matches',
            value: _buildMatchDescription(),
          ),

          // Generated event ID
          _PreviewRow(
            label: 'Event ID',
            value: rule.eventIdTemplate,
            isMonospace: true,
          ),

          // Defaults
          _PreviewRow(
            label: 'Defaults',
            value: 'Bus: ${rule.defaultBus}, Trigger: ${rule.defaultTrigger}',
          ),
        ],
      ),
    );
  }

  String _buildMatchDescription() {
    final parts = <String>[];

    if (rule.assetType != null) {
      parts.add('${rule.assetType!.displayName} assets');
    }
    if (rule.targetType != null) {
      parts.add('on ${rule.targetType!.displayName}');
    }
    if (rule.assetTags.isNotEmpty) {
      parts.add('with tags [${rule.assetTags.join(', ')}]');
    }
    if (rule.targetTags.isNotEmpty) {
      parts.add('target has [${rule.targetTags.join(', ')}]');
    }

    if (parts.isEmpty) {
      return 'Any asset on any target';
    }

    return parts.join(' ');
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isMonospace;

  const _PreviewRow({
    required this.label,
    required this.value,
    this.isMonospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontFamily: isMonospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
