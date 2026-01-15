// Plugin Editor Window Widget
//
// Floating window for hosting plugin GUI editors
// Supports VST3/CLAP/AU native GUI embedding

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/plugin_provider.dart';
import '../../theme/fluxforge_theme.dart';

/// Floating plugin editor window
class PluginEditorWindow extends StatefulWidget {
  final String instanceId;
  final VoidCallback? onClose;

  const PluginEditorWindow({
    super.key,
    required this.instanceId,
    this.onClose,
  });

  @override
  State<PluginEditorWindow> createState() => _PluginEditorWindowState();
}

class _PluginEditorWindowState extends State<PluginEditorWindow> {
  Offset _position = const Offset(100, 100);
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginProvider>(
      builder: (context, provider, _) {
        final instance = provider.getInstance(widget.instanceId);
        if (instance == null) {
          return const SizedBox.shrink();
        }

        final width = instance.editorWidth?.toDouble() ?? 600;
        final height = instance.editorHeight?.toDouble() ?? 400;

        return Positioned(
          left: _position.dx,
          top: _position.dy,
          child: Material(
            elevation: 16,
            borderRadius: BorderRadius.circular(8),
            color: FluxForgeTheme.bgDeep,
            child: Container(
              width: width + 2,
              decoration: BoxDecoration(
                border: Border.all(color: FluxForgeTheme.bgSurface, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title bar
                  _buildTitleBar(instance, provider),

                  // Plugin content area
                  _buildEditorArea(instance, width, height),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitleBar(PluginInstance instance, PluginProvider provider) {
    return GestureDetector(
      onPanStart: (_) => setState(() => _isDragging = true),
      onPanUpdate: (details) {
        if (_isDragging) {
          setState(() {
            _position = Offset(
              _position.dx + details.delta.dx,
              _position.dy + details.delta.dy,
            );
          });
        }
      },
      onPanEnd: (_) => setState(() => _isDragging = false),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(7),
            topRight: Radius.circular(7),
          ),
        ),
        child: Row(
          children: [
            // Plugin format badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getFormatColor(instance.format).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _getFormatName(instance.format),
                style: TextStyle(
                  color: _getFormatColor(instance.format),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Plugin name
            Expanded(
              child: Text(
                instance.name,
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Preset dropdown (placeholder)
            IconButton(
              icon: const Icon(Icons.list, size: 16),
              color: FluxForgeTheme.textSecondary,
              tooltip: 'Presets',
              onPressed: () => _showPresetMenu(context, instance, provider),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),

            // Close button
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              color: FluxForgeTheme.textSecondary,
              tooltip: 'Close Editor',
              onPressed: () {
                provider.closeEditor(widget.instanceId);
                widget.onClose?.call();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorArea(PluginInstance instance, double width, double height) {
    // In a real implementation, this would host the native plugin GUI
    // using platform views or embedding native windows
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(7),
          bottomRight: Radius.circular(7),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.extension,
              size: 64,
              color: FluxForgeTheme.textSecondary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              instance.name,
              style: TextStyle(
                color: FluxForgeTheme.textSecondary.withOpacity(0.7),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Native plugin GUI embedding',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary.withOpacity(0.5),
                fontSize: 12,
              ),
            ),
            Text(
              '(requires platform view implementation)',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary.withOpacity(0.4),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPresetMenu(
    BuildContext context,
    PluginInstance instance,
    PluginProvider provider,
  ) {
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        _position.dx + 200,
        _position.dy + 32,
        _position.dx + 300,
        _position.dy + 132,
      ),
      items: <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          child: const Text('Save Preset...'),
          onTap: () => _savePreset(context, instance, provider),
        ),
        PopupMenuItem<void>(
          child: const Text('Load Preset...'),
          onTap: () => _loadPreset(context, instance, provider),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<void>(
          enabled: false,
          child: Text('Factory Presets'),
        ),
      ],
    );
  }

  Future<void> _savePreset(
    BuildContext context,
    PluginInstance instance,
    PluginProvider provider,
  ) async {
    // In real implementation, show file save dialog
    debugPrint('[PluginEditor] Save preset for ${instance.name}');
  }

  Future<void> _loadPreset(
    BuildContext context,
    PluginInstance instance,
    PluginProvider provider,
  ) async {
    // In real implementation, show file open dialog
    debugPrint('[PluginEditor] Load preset for ${instance.name}');
  }

  String _getFormatName(PluginFormat format) {
    switch (format) {
      case PluginFormat.vst3:
        return 'VST3';
      case PluginFormat.clap:
        return 'CLAP';
      case PluginFormat.audioUnit:
        return 'AU';
      case PluginFormat.lv2:
        return 'LV2';
      case PluginFormat.internal:
        return 'RF';
    }
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

/// Manager for multiple plugin editor windows
class PluginEditorManager extends StatefulWidget {
  final Widget child;

  const PluginEditorManager({
    super.key,
    required this.child,
  });

  @override
  State<PluginEditorManager> createState() => _PluginEditorManagerState();
}

class _PluginEditorManagerState extends State<PluginEditorManager> {
  final Set<String> _openEditors = {};

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginProvider>(
      builder: (context, provider, _) {
        // Sync open editors with provider state
        final openInstanceIds = provider.instances.values
            .where((i) => i.isEditorOpen)
            .map((i) => i.instanceId)
            .toSet();

        return Stack(
          children: [
            widget.child,
            ...openInstanceIds.map((id) => PluginEditorWindow(
                  key: ValueKey(id),
                  instanceId: id,
                  onClose: () => setState(() => _openEditors.remove(id)),
                )),
          ],
        );
      },
    );
  }
}
