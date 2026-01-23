/// Workspace Preset Dropdown Widget (M3.2)
///
/// Dropdown for selecting and managing workspace presets in the lower zone.
/// Supports built-in and custom presets with create/delete actions.

import 'package:flutter/material.dart';
import '../../models/workspace_preset.dart';
import '../../services/workspace_preset_service.dart';
import 'lower_zone_types.dart';

/// Callback for when a preset is applied
typedef OnPresetApplied = void Function(WorkspacePreset preset);

/// Compact workspace preset dropdown for lower zone header
class WorkspacePresetDropdown extends StatefulWidget {
  /// Current workspace section
  final WorkspaceSection section;

  /// Accent color for styling
  final Color accentColor;

  /// Callback when preset is applied
  final OnPresetApplied? onPresetApplied;

  /// Callback to get current workspace state for saving
  final WorkspacePreset Function()? getCurrentState;

  const WorkspacePresetDropdown({
    super.key,
    required this.section,
    required this.accentColor,
    this.onPresetApplied,
    this.getCurrentState,
  });

  @override
  State<WorkspacePresetDropdown> createState() => _WorkspacePresetDropdownState();
}

class _WorkspacePresetDropdownState extends State<WorkspacePresetDropdown> {
  final _service = WorkspacePresetService.instance;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final activePreset = _service.getActivePreset(widget.section);
    final presets = _service.getPresetsForSection(widget.section);

    return PopupMenuButton<_PresetAction>(
      onSelected: _handleAction,
      offset: const Offset(0, 28),
      color: LowerZoneColors.bgDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: LowerZoneColors.border),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: LowerZoneColors.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: LowerZoneColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dashboard_customize,
              size: 12,
              color: activePreset != null
                  ? widget.accentColor
                  : LowerZoneColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              activePreset?.name ?? 'Layout',
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeLabel,
                color: activePreset != null
                    ? widget.accentColor
                    : LowerZoneColors.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: LowerZoneColors.textMuted,
            ),
          ],
        ),
      ),
      itemBuilder: (context) {
        final items = <PopupMenuEntry<_PresetAction>>[];

        // Built-in presets section
        final builtInPresets = presets.where((p) => p.isBuiltIn).toList();
        if (builtInPresets.isNotEmpty) {
          items.add(const PopupMenuItem(
            enabled: false,
            height: 24,
            child: Text(
              'BUILT-IN',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: LowerZoneColors.textMuted,
              ),
            ),
          ));
          for (final preset in builtInPresets) {
            items.add(_buildPresetItem(preset, activePreset));
          }
        }

        // Custom presets section
        final customPresets = presets.where((p) => !p.isBuiltIn).toList();
        if (customPresets.isNotEmpty) {
          items.add(const PopupMenuDivider());
          items.add(const PopupMenuItem(
            enabled: false,
            height: 24,
            child: Text(
              'CUSTOM',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: LowerZoneColors.textMuted,
              ),
            ),
          ));
          for (final preset in customPresets) {
            items.add(_buildPresetItem(preset, activePreset));
          }
        }

        // Actions
        items.add(const PopupMenuDivider());
        items.add(PopupMenuItem(
          value: _PresetAction(type: _ActionType.saveNew),
          child: Row(
            children: [
              Icon(Icons.add, size: 14, color: widget.accentColor),
              const SizedBox(width: 8),
              Text(
                'Save Current Layout...',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.accentColor,
                ),
              ),
            ],
          ),
        ));

        // Clear active preset option
        if (activePreset != null) {
          items.add(PopupMenuItem(
            value: _PresetAction(type: _ActionType.clear),
            child: const Row(
              children: [
                Icon(Icons.clear, size: 14, color: LowerZoneColors.textSecondary),
                SizedBox(width: 8),
                Text(
                  'Clear Selection',
                  style: TextStyle(
                    fontSize: 12,
                    color: LowerZoneColors.textSecondary,
                  ),
                ),
              ],
            ),
          ));
        }

        return items;
      },
    );
  }

  PopupMenuItem<_PresetAction> _buildPresetItem(
    WorkspacePreset preset,
    WorkspacePreset? activePreset,
  ) {
    final isActive = activePreset?.id == preset.id;

    return PopupMenuItem(
      value: _PresetAction(type: _ActionType.apply, preset: preset),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.check : Icons.dashboard,
            size: 14,
            color: isActive ? widget.accentColor : LowerZoneColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              preset.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? widget.accentColor : LowerZoneColors.textPrimary,
              ),
            ),
          ),
          if (!preset.isBuiltIn)
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(preset);
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.delete_outline,
                  size: 14,
                  color: LowerZoneColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleAction(_PresetAction action) {
    switch (action.type) {
      case _ActionType.apply:
        if (action.preset != null) {
          _service.applyPreset(action.preset!);
          widget.onPresetApplied?.call(action.preset!);
        }
        break;
      case _ActionType.saveNew:
        _showSaveDialog();
        break;
      case _ActionType.clear:
        _service.setActivePreset(widget.section, null);
        break;
    }
  }

  void _showSaveDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LowerZoneColors.bgDeep,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: LowerZoneColors.border),
        ),
        title: Text(
          'Save Layout Preset',
          style: TextStyle(
            color: LowerZoneColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(color: LowerZoneColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                labelText: 'Preset Name',
                labelStyle: const TextStyle(color: LowerZoneColors.textSecondary, fontSize: 11),
                filled: true,
                fillColor: LowerZoneColors.bgMid,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: LowerZoneColors.border),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              style: const TextStyle(color: LowerZoneColors.textPrimary, fontSize: 12),
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: const TextStyle(color: LowerZoneColors.textSecondary, fontSize: 11),
                filled: true,
                fillColor: LowerZoneColors.bgMid,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: LowerZoneColors.border),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: LowerZoneColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;

              final currentState = widget.getCurrentState?.call();
              await _service.createPreset(
                name: nameController.text.trim(),
                description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                section: widget.section,
                activeTabs: currentState?.activeTabs ?? [],
                expandedCategories: currentState?.expandedCategories ?? [],
                lowerZoneHeight: currentState?.lowerZoneHeight ?? 300,
                lowerZoneExpanded: currentState?.lowerZoneExpanded ?? true,
              );

              if (mounted) Navigator.pop(context);
            },
            child: Text('Save', style: TextStyle(color: widget.accentColor)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(WorkspacePreset preset) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LowerZoneColors.bgDeep,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: LowerZoneColors.border),
        ),
        title: const Text(
          'Delete Preset?',
          style: TextStyle(
            color: LowerZoneColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${preset.name}"? This cannot be undone.',
          style: const TextStyle(color: LowerZoneColors.textSecondary, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: LowerZoneColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              await _service.deletePreset(preset.id);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

enum _ActionType { apply, saveNew, clear }

class _PresetAction {
  final _ActionType type;
  final WorkspacePreset? preset;

  _PresetAction({required this.type, this.preset});
}
