/// Workspace Layout Preset Dropdown (P1.1)
library;

import 'package:flutter/material.dart';
import 'lower_zone_types.dart';
import 'daw_lower_zone_controller.dart';
import '../../services/workspace_layout_service.dart';
import '../../models/workspace_layout_preset.dart';

class WorkspaceLayoutDropdown extends StatelessWidget {
  final DawLowerZoneController controller;

  const WorkspaceLayoutDropdown({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WorkspaceLayoutService.instance,
      builder: (context, _) {
        final service = WorkspaceLayoutService.instance;
        final presets = service.allPresets;

        return PopupMenuButton<WorkspaceLayoutPreset>(
          tooltip: 'Workspace Presets',
          offset: const Offset(0, 30),
          color: LowerZoneColors.bgMid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: const BorderSide(color: LowerZoneColors.border),
          ),
          onSelected: (preset) => service.applyPreset(preset, controller),
          itemBuilder: (context) => [
            const PopupMenuItem(
              enabled: false,
              child: Text(
                'BUILT-IN PRESETS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: LowerZoneColors.textMuted,
                ),
              ),
            ),
            ...WorkspaceLayoutPreset.builtIn.map((preset) => PopupMenuItem(
              value: preset,
              child: Row(
                children: [
                  Icon(_iconForPreset(preset), size: 14, color: LowerZoneColors.dawAccent),
                  const SizedBox(width: 8),
                  Text(preset.name),
                ],
              ),
            )),
            if (service.customPresets.isNotEmpty) ...[
              const PopupMenuDivider(),
              const PopupMenuItem(
                enabled: false,
                child: Text(
                  'CUSTOM PRESETS',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: LowerZoneColors.textMuted,
                  ),
                ),
              ),
              ...service.customPresets.map((preset) => PopupMenuItem(
                value: preset,
                child: Row(
                  children: [
                    const Icon(Icons.bookmark, size: 14, color: LowerZoneColors.warning),
                    const SizedBox(width: 8),
                    Text(preset.name),
                  ],
                ),
              )),
            ],
            const PopupMenuDivider(),
            PopupMenuItem(
              child: Row(
                children: [
                  const Icon(Icons.add, size: 14, color: LowerZoneColors.success),
                  const SizedBox(width: 8),
                  const Text('Save Current...'),
                ],
              ),
              onTap: () => _showSaveDialog(context),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.dashboard_customize, size: 12, color: LowerZoneColors.textSecondary),
                SizedBox(width: 4),
                Text('Layout', style: TextStyle(fontSize: 10, color: LowerZoneColors.textSecondary)),
                SizedBox(width: 2),
                Icon(Icons.arrow_drop_down, size: 14, color: LowerZoneColors.textMuted),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _iconForPreset(WorkspaceLayoutPreset preset) {
    return switch (preset.id) {
      'mixing' => Icons.tune,
      'mastering' => Icons.graphic_eq,
      'editing' => Icons.piano,
      'tracking' => Icons.fiber_manual_record,
      _ => Icons.bookmark,
    };
  }

  void _showSaveDialog(BuildContext context) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LowerZoneColors.bgDeep,
        title: const Text('Save Workspace Preset', style: TextStyle(color: LowerZoneColors.textPrimary)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: LowerZoneColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Preset Name',
            labelStyle: TextStyle(color: LowerZoneColors.textMuted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final preset = WorkspaceLayoutService.instance
                    .createFromCurrentState(name, controller);
                WorkspaceLayoutService.instance.savePreset(preset);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
