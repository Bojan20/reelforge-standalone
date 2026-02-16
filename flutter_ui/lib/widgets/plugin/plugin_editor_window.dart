// Plugin Editor Window Widget
//
// Floating window for hosting plugin GUI editors
// Supports VST3/CLAP/AU native GUI embedding

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/plugin_provider.dart';
import '../../src/rust/native_ffi.dart';
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
    final provider = context.read<PluginProvider>();
    final params = provider.getPluginParams(instance.instanceId);

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
      child: params.isEmpty
          ? _buildNoParamsPlaceholder(instance)
          : _buildParameterGrid(instance, provider, params, width),
    );
  }

  Widget _buildNoParamsPlaceholder(PluginInstance instance) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension, size: 48,
              color: FluxForgeTheme.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text(instance.name, style: TextStyle(
            color: FluxForgeTheme.textSecondary.withOpacity(0.7),
            fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('No parameters exposed', style: TextStyle(
            color: FluxForgeTheme.textSecondary.withOpacity(0.4),
            fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildParameterGrid(
    PluginInstance instance,
    PluginProvider provider,
    List<NativePluginParamInfo> params,
    double width,
  ) {
    return Column(
      children: [
        // Parameter count header
        Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: FluxForgeTheme.bgMid.withOpacity(0.5),
          child: Row(
            children: [
              Text('${params.length} Parameters',
                style: TextStyle(color: FluxForgeTheme.textSecondary.withOpacity(0.6),
                  fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              const Spacer(),
              GestureDetector(
                onTap: () => _resetAllParams(provider, instance.instanceId, params),
                child: Text('Reset All', style: TextStyle(
                  color: FluxForgeTheme.accentBlue.withOpacity(0.7), fontSize: 10)),
              ),
            ],
          ),
        ),
        // Scrollable parameter list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            itemCount: params.length,
            itemBuilder: (context, index) {
              final param = params[index];
              return _PluginParamSlider(
                key: ValueKey('param_${param.id}'),
                param: param,
                instanceId: instance.instanceId,
                provider: provider,
                accentColor: _getFormatColor(instance.format),
              );
            },
          ),
        ),
      ],
    );
  }

  void _resetAllParams(PluginProvider provider, String instanceId, List<NativePluginParamInfo> params) {
    for (final param in params) {
      provider.setPluginParam(instanceId, param.id, param.defaultValue);
    }
    setState(() {});
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
    PluginInstance instance,
    PluginProvider provider,
  ) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Load Preset: Use File > Load Preset to browse')),
    );
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

/// Single parameter slider row for generic plugin editor
class _PluginParamSlider extends StatefulWidget {
  final NativePluginParamInfo param;
  final String instanceId;
  final PluginProvider provider;
  final Color accentColor;

  const _PluginParamSlider({
    super.key,
    required this.param,
    required this.instanceId,
    required this.provider,
    required this.accentColor,
  });

  @override
  State<_PluginParamSlider> createState() => _PluginParamSliderState();
}

class _PluginParamSliderState extends State<_PluginParamSlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.param.value;
  }

  @override
  void didUpdateWidget(covariant _PluginParamSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.param.value != widget.param.value) {
      _value = widget.param.value;
    }
  }

  String _formatValue(double v) {
    final range = widget.param.max - widget.param.min;
    if (range == 0) return v.toStringAsFixed(2);
    if (range <= 1.0) return v.toStringAsFixed(3);
    if (range <= 100) return v.toStringAsFixed(1);
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.param;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            // Parameter name
            SizedBox(
              width: 120,
              child: Text(
                p.name,
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary.withOpacity(0.8),
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Slider
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: widget.accentColor,
                  inactiveTrackColor: FluxForgeTheme.bgSurface,
                  thumbColor: widget.accentColor,
                ),
                child: Slider(
                  value: _value.clamp(p.min, p.max),
                  min: p.min,
                  max: p.max,
                  onChanged: (v) {
                    setState(() => _value = v);
                    widget.provider.setPluginParam(widget.instanceId, p.id, v);
                  },
                ),
              ),
            ),
            // Value display
            SizedBox(
              width: 50,
              child: Text(
                '${_formatValue(_value)}${p.unit.isNotEmpty ? ' ${p.unit}' : ''}',
                style: TextStyle(
                  color: FluxForgeTheme.textPrimary.withOpacity(0.7),
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Reset button
            GestureDetector(
              onTap: () {
                setState(() => _value = p.defaultValue);
                widget.provider.setPluginParam(widget.instanceId, p.id, p.defaultValue);
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.restart_alt, size: 12,
                  color: FluxForgeTheme.textSecondary.withOpacity(0.4)),
              ),
            ),
          ],
        ),
      ),
    );
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
