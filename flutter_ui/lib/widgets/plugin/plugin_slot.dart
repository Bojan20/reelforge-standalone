// Plugin Slot Widget
//
// Insert slot for mixer channel strips
// Supports drag-drop, context menu, bypass

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/plugin_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Plugin insert slot for channel strips
class PluginSlot extends StatelessWidget {
  final int trackId;
  final int slotIndex;
  final String? instanceId;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onRemove;

  const PluginSlot({
    super.key,
    required this.trackId,
    required this.slotIndex,
    this.instanceId,
    this.onTap,
    this.onDoubleTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginProvider>(
      builder: (context, provider, _) {
        final instance =
            instanceId != null ? provider.getInstance(instanceId!) : null;

        if (instance == null) {
          return _buildEmptySlot(context, provider);
        }

        return _buildFilledSlot(context, provider, instance);
      },
    );
  }

  Widget _buildEmptySlot(BuildContext context, PluginProvider provider) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        height: 24,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: FluxForgeTheme.bgSurface.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            '+ Insert ${slotIndex + 1}',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilledSlot(
    BuildContext context,
    PluginProvider provider,
    PluginInstance instance,
  ) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: () {
        // Open editor on double-tap
        if (instance.hasEditor) {
          provider.openEditor(instance.instanceId);
        }
      },
      onSecondaryTap: () => _showContextMenu(context, provider, instance),
      child: Container(
        height: 24,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _getFormatColor(instance.format).withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Format indicator
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: _getFormatColor(instance.format),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  bottomLeft: Radius.circular(3),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Plugin name
            Expanded(
              child: Text(
                instance.name,
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Bypass button
            _BypassButton(
              instanceId: instance.instanceId,
              trackId: trackId,
              slotIndex: slotIndex,
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    PluginProvider provider,
    PluginInstance instance,
  ) {
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset position = box.localToGlobal(Offset.zero, ancestor: overlay);

    final items = <PopupMenuEntry<void>>[
      if (instance.hasEditor)
        PopupMenuItem<void>(
          child: const Row(
            children: [
              Icon(Icons.tune, size: 16),
              SizedBox(width: 8),
              Text('Open Editor'),
            ],
          ),
          onTap: () => provider.openEditor(instance.instanceId),
        ),
      PopupMenuItem<void>(
        child: const Row(
          children: [
            Icon(Icons.save, size: 16),
            SizedBox(width: 8),
            Text('Save Preset...'),
          ],
        ),
        onTap: () => _savePreset(context, provider, instance),
      ),
      PopupMenuItem<void>(
        child: const Row(
          children: [
            Icon(Icons.folder_open, size: 16),
            SizedBox(width: 8),
            Text('Load Preset...'),
          ],
        ),
        onTap: () => _loadPreset(context, provider, instance),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<void>(
        child: const Row(
          children: [
            Icon(Icons.copy, size: 16),
            SizedBox(width: 8),
            Text('Copy'),
          ],
        ),
      ),
      PopupMenuItem<void>(
        child: const Row(
          children: [
            Icon(Icons.content_paste, size: 16),
            SizedBox(width: 8),
            Text('Paste'),
          ],
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<void>(
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 16, color: FluxForgeTheme.accentRed),
            const SizedBox(width: 8),
            Text('Remove', style: TextStyle(color: FluxForgeTheme.accentRed)),
          ],
        ),
        onTap: () {
          provider.unloadPlugin(instance.instanceId);
          onRemove?.call();
        },
      ),
    ];

    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + box.size.height,
        position.dx + box.size.width,
        position.dy + box.size.height + 200,
      ),
      items: items,
    );
  }

  Future<void> _savePreset(
    BuildContext context,
    PluginProvider provider,
    PluginInstance instance,
  ) async {
    final nameController = TextEditingController(text: instance.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Preset'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Preset Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      final path = '${instance.pluginId}_$name.ffpreset';
      await provider.savePluginPreset(instance.instanceId, path, name);
    }
  }

  Future<void> _loadPreset(
    BuildContext context,
    PluginProvider provider,
    PluginInstance instance,
  ) async {
    // Use file picker to select a preset file
    // For now, show a placeholder dialog
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Load Preset: Use File > Load Preset to browse')),
    );
  }

  Color _getFormatColor(PluginFormat format) {
    switch (format) {
      case PluginFormat.vst3:
        return FluxForgeTheme.accentBlue;
      case PluginFormat.clap:
        return FluxForgeTheme.accentOrange;
      case PluginFormat.audioUnit:
        return FluxForgeTheme.accentGreen;
      case PluginFormat.lv2:
        return FluxForgeTheme.accentRed;
      case PluginFormat.internal:
        return FluxForgeTheme.accentCyan;
    }
  }
}

/// Bypass button for plugin slot
class _BypassButton extends StatefulWidget {
  final String instanceId;
  final int trackId;
  final int slotIndex;

  const _BypassButton({
    required this.instanceId,
    required this.trackId,
    required this.slotIndex,
  });

  @override
  State<_BypassButton> createState() => _BypassButtonState();
}

class _BypassButtonState extends State<_BypassButton> {
  bool _bypassed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final newState = !_bypassed;
        setState(() => _bypassed = newState);
        context.read<PluginProvider>().setInsertBypass(
          widget.trackId,
          widget.slotIndex,
          newState,
        );
      },
      child: Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: _bypassed
              ? FluxForgeTheme.accentOrange.withOpacity(0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Icon(
          _bypassed ? Icons.power_off : Icons.power,
          size: 12,
          color: _bypassed
              ? FluxForgeTheme.accentOrange
              : FluxForgeTheme.textSecondary.withOpacity(0.5),
        ),
      ),
    );
  }
}

/// Plugin insert rack (multiple slots)
class PluginInsertRack extends StatelessWidget {
  final int trackId;
  final int slotCount;
  final List<String?> instanceIds;
  final void Function(int slotIndex)? onSlotTap;
  final void Function(int slotIndex)? onAddPlugin;

  const PluginInsertRack({
    super.key,
    required this.trackId,
    this.slotCount = 8,
    this.instanceIds = const [],
    this.onSlotTap,
    this.onAddPlugin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text(
                'INSERTS',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary.withOpacity(0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              Text(
                '${instanceIds.where((id) => id != null).length}/$slotCount',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary.withOpacity(0.5),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),

        // Slots
        ...List.generate(slotCount, (index) {
          final instanceId = index < instanceIds.length ? instanceIds[index] : null;
          return PluginSlot(
            trackId: trackId,
            slotIndex: index,
            instanceId: instanceId,
            onTap: () => onSlotTap?.call(index),
            onDoubleTap: () => onAddPlugin?.call(index),
          );
        }),
      ],
    );
  }
}
