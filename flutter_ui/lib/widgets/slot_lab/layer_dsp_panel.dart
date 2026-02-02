/// Layer DSP Panel (P12.1.5)
///
/// Compact DSP chain editor for individual event layers.
/// Provides add/remove/reorder nodes, per-node parameter sliders,
/// bypass toggles, and preset browser.
///
/// Used in SlotLab Lower Zone when editing composite event layers.
library;

import 'package:flutter/material.dart';
import '../../models/slot_audio_events.dart';
import '../../services/layer_dsp_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LAYER DSP PANEL
// ═══════════════════════════════════════════════════════════════════════════

/// Compact panel for editing a layer's DSP chain
class LayerDspPanel extends StatefulWidget {
  /// The layer to edit
  final SlotEventLayer layer;

  /// Callback when DSP chain changes
  final ValueChanged<List<LayerDspNode>> onChainChanged;

  /// Optional accent color
  final Color? accentColor;

  /// Compact mode (less padding, smaller controls)
  final bool compact;

  const LayerDspPanel({
    super.key,
    required this.layer,
    required this.onChainChanged,
    this.accentColor,
    this.compact = false,
  });

  @override
  State<LayerDspPanel> createState() => _LayerDspPanelState();
}

class _LayerDspPanelState extends State<LayerDspPanel> {
  late List<LayerDspNode> _chain;
  int? _selectedNodeIndex;
  bool _showPresets = false;

  @override
  void initState() {
    super.initState();
    _chain = List.from(widget.layer.dspChain);
  }

  @override
  void didUpdateWidget(LayerDspPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer.id != widget.layer.id) {
      _chain = List.from(widget.layer.dspChain);
      _selectedNodeIndex = null;
    }
  }

  Color get _accent => widget.accentColor ?? const Color(0xFF4A9EFF);
  LayerDspService get _service => LayerDspService.instance;

  void _notifyChange() {
    widget.onChainChanged(_chain);
  }

  void _addNode(LayerDspType type) {
    if (_chain.length >= LayerDspService.maxProcessorsPerLayer) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Max ${LayerDspService.maxProcessorsPerLayer} processors per layer'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _chain.add(LayerDspNode.create(type));
      _selectedNodeIndex = _chain.length - 1;
    });
    _notifyChange();
  }

  void _removeNode(int index) {
    setState(() {
      _chain.removeAt(index);
      if (_selectedNodeIndex == index) {
        _selectedNodeIndex = _chain.isEmpty ? null : (_chain.length - 1).clamp(0, _chain.length - 1);
      } else if (_selectedNodeIndex != null && _selectedNodeIndex! > index) {
        _selectedNodeIndex = _selectedNodeIndex! - 1;
      }
    });
    _notifyChange();
  }

  void _toggleBypass(int index) {
    setState(() {
      final node = _chain[index];
      _chain[index] = node.copyWith(bypass: !node.bypass);
    });
    _notifyChange();
  }

  void _updateNodeParam(int index, String paramName, double value) {
    setState(() {
      final node = _chain[index];
      final newParams = Map<String, dynamic>.from(node.params);
      newParams[paramName] = value;
      _chain[index] = node.copyWith(params: newParams);
    });
    _notifyChange();
  }

  void _updateWetDry(int index, double value) {
    setState(() {
      _chain[index] = _chain[index].copyWith(wetDry: value.clamp(0.0, 1.0));
    });
    _notifyChange();
  }

  void _moveNode(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    if (newIndex == oldIndex) return;

    setState(() {
      final node = _chain.removeAt(oldIndex);
      _chain.insert(newIndex, node);
      if (_selectedNodeIndex == oldIndex) {
        _selectedNodeIndex = newIndex;
      }
    });
    _notifyChange();
  }

  void _applyPreset(LayerDspPreset preset) {
    setState(() {
      _chain = _service.applyPreset(preset.id);
      _selectedNodeIndex = _chain.isEmpty ? null : 0;
      _showPresets = false;
    });
    _notifyChange();
  }

  void _clearChain() {
    setState(() {
      _chain.clear();
      _selectedNodeIndex = null;
    });
    _notifyChange();
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.compact ? 8.0 : 12.0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildHeader(padding),

          // Content
          if (_showPresets)
            _buildPresetBrowser(padding)
          else ...[
            // Chain display
            _buildChainDisplay(padding),

            // Selected node editor
            if (_selectedNodeIndex != null && _selectedNodeIndex! < _chain.length)
              _buildNodeEditor(_chain[_selectedNodeIndex!], _selectedNodeIndex!, padding),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(double padding) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: padding * 0.75),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, size: 16, color: _accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Layer DSP',
              style: TextStyle(
                color: _accent,
                fontWeight: FontWeight.w600,
                fontSize: widget.compact ? 12 : 13,
              ),
            ),
          ),
          // Chain count badge
          if (_chain.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_chain.length}/${LayerDspService.maxProcessorsPerLayer}',
                style: TextStyle(
                  color: _accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 8),
          // Presets button
          _buildIconButton(
            icon: _showPresets ? Icons.close : Icons.folder_special,
            tooltip: _showPresets ? 'Close Presets' : 'Presets',
            onTap: () => setState(() => _showPresets = !_showPresets),
          ),
          // Add button
          if (!_showPresets)
            _buildAddButton(),
          // Clear button
          if (_chain.isNotEmpty && !_showPresets)
            _buildIconButton(
              icon: Icons.delete_sweep,
              tooltip: 'Clear All',
              onTap: _clearChain,
              color: Colors.red.shade300,
            ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: color ?? Colors.grey.shade400),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return PopupMenuButton<LayerDspType>(
      tooltip: 'Add Processor',
      icon: Icon(Icons.add, size: 16, color: _accent),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      itemBuilder: (context) => LayerDspType.values.map((type) {
        return PopupMenuItem(
          value: type,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_getTypeIcon(type), size: 16),
              const SizedBox(width: 8),
              Text(type.fullName),
            ],
          ),
        );
      }).toList(),
      onSelected: _addNode,
    );
  }

  Widget _buildChainDisplay(double padding) {
    if (_chain.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(padding * 2),
        child: Center(
          child: Text(
            'No DSP processors.\nAdd one or select a preset.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(padding),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: _chain.length,
        onReorder: _moveNode,
        itemBuilder: (context, index) {
          final node = _chain[index];
          final isSelected = _selectedNodeIndex == index;

          return _buildNodeChip(node, index, isSelected);
        },
      ),
    );
  }

  Widget _buildNodeChip(LayerDspNode node, int index, bool isSelected) {
    return Container(
      key: ValueKey(node.id),
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? _accent.withOpacity(0.2) : const Color(0xFF242430),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () => setState(() => _selectedNodeIndex = index),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? _accent : Colors.transparent,
                width: 1,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                // Drag handle
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 6),
                // Type icon
                Icon(
                  _getTypeIcon(node.type),
                  size: 14,
                  color: node.bypass ? Colors.grey.shade600 : _getTypeColor(node.type),
                ),
                const SizedBox(width: 6),
                // Name
                Expanded(
                  child: Text(
                    node.type.shortName,
                    style: TextStyle(
                      color: node.bypass ? Colors.grey.shade600 : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      decoration: node.bypass ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                // Wet/Dry indicator
                if (node.wetDry < 1.0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${(node.wetDry * 100).round()}%',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 9,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                // Bypass toggle
                _buildMiniToggle(
                  active: !node.bypass,
                  onTap: () => _toggleBypass(index),
                  tooltip: node.bypass ? 'Enable' : 'Bypass',
                ),
                const SizedBox(width: 4),
                // Remove button
                InkWell(
                  onTap: () => _removeNode(index),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 12, color: Colors.grey.shade500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniToggle({
    required bool active,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: active ? _accent.withOpacity(0.3) : Colors.grey.shade800,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? _accent : Colors.grey.shade600,
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.power_settings_new,
              size: 10,
              color: active ? _accent : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNodeEditor(LayerDspNode node, int index, double padding) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        border: Border(top: BorderSide(color: Colors.grey.shade800)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Node header
          Row(
            children: [
              Icon(_getTypeIcon(node.type), size: 14, color: _getTypeColor(node.type)),
              const SizedBox(width: 6),
              Text(
                node.type.fullName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Wet/Dry slider
              SizedBox(
                width: 100,
                child: Row(
                  children: [
                    Text(
                      'Mix:',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        ),
                        child: Slider(
                          value: node.wetDry,
                          onChanged: (v) => _updateWetDry(index, v),
                          activeColor: _accent,
                          inactiveColor: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${(node.wetDry * 100).round()}%',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Parameters
          ..._buildParameterSliders(node, index),
        ],
      ),
    );
  }

  List<Widget> _buildParameterSliders(LayerDspNode node, int index) {
    switch (node.type) {
      case LayerDspType.eq:
        return [
          _buildParamRow('Low', [
            _buildParamSlider('lowFreq', 20, 500, node.params, index, suffix: 'Hz'),
            _buildParamSlider('lowGain', -12, 12, node.params, index, suffix: 'dB'),
          ]),
          _buildParamRow('Mid', [
            _buildParamSlider('midFreq', 200, 8000, node.params, index, suffix: 'Hz'),
            _buildParamSlider('midGain', -12, 12, node.params, index, suffix: 'dB'),
            _buildParamSlider('midQ', 0.1, 10, node.params, index, suffix: 'Q'),
          ]),
          _buildParamRow('High', [
            _buildParamSlider('highFreq', 2000, 20000, node.params, index, suffix: 'Hz'),
            _buildParamSlider('highGain', -12, 12, node.params, index, suffix: 'dB'),
          ]),
        ];

      case LayerDspType.compressor:
        return [
          _buildParamRow('Dynamics', [
            _buildParamSlider('threshold', -60, 0, node.params, index, suffix: 'dB'),
            _buildParamSlider('ratio', 1, 20, node.params, index, suffix: ':1'),
          ]),
          _buildParamRow('Timing', [
            _buildParamSlider('attack', 0.1, 100, node.params, index, suffix: 'ms'),
            _buildParamSlider('release', 10, 1000, node.params, index, suffix: 'ms'),
          ]),
          _buildParamRow('Output', [
            _buildParamSlider('makeupGain', 0, 24, node.params, index, suffix: 'dB'),
          ]),
        ];

      case LayerDspType.reverb:
        return [
          _buildParamRow('Space', [
            _buildParamSlider('decay', 0.1, 10, node.params, index, suffix: 's'),
            _buildParamSlider('size', 0, 1, node.params, index, suffix: ''),
          ]),
          _buildParamRow('Character', [
            _buildParamSlider('preDelay', 0, 200, node.params, index, suffix: 'ms'),
            _buildParamSlider('damping', 0, 1, node.params, index, suffix: ''),
          ]),
        ];

      case LayerDspType.delay:
        return [
          _buildParamRow('Timing', [
            _buildParamSlider('time', 1, 2000, node.params, index, suffix: 'ms'),
            _buildParamSlider('feedback', 0, 0.95, node.params, index, suffix: ''),
          ]),
          _buildParamRow('Filter', [
            _buildParamSlider('lowCut', 20, 500, node.params, index, suffix: 'Hz'),
            _buildParamSlider('highCut', 500, 20000, node.params, index, suffix: 'Hz'),
          ]),
        ];
    }
  }

  Widget _buildParamRow(String label, List<Widget> sliders) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: sliders.map((s) => Expanded(child: s)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamSlider(
    String paramName,
    double min,
    double max,
    Map<String, dynamic> params,
    int nodeIndex, {
    String suffix = '',
  }) {
    final value = (params[paramName] as num?)?.toDouble() ?? (min + max) / 2;
    final displayValue = _formatParamValue(value, paramName);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatParamName(paramName),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 8),
              ),
              Text(
                '$displayValue$suffix',
                style: TextStyle(color: _accent, fontSize: 8),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (v) => _updateNodeParam(nodeIndex, paramName, v),
              activeColor: _accent,
              inactiveColor: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  String _formatParamName(String name) {
    // Convert camelCase to Title Case
    return name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (m) => ' ${m.group(0)}',
    ).trim();
  }

  String _formatParamValue(double value, String paramName) {
    if (paramName.contains('Freq') || paramName.contains('Cut')) {
      if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
      return value.round().toString();
    }
    if (paramName == 'ratio') {
      return value.toStringAsFixed(1);
    }
    if (paramName == 'decay' || paramName == 'size' || paramName == 'damping' || paramName == 'feedback') {
      return value.toStringAsFixed(2);
    }
    if (value.abs() < 10) {
      return value.toStringAsFixed(1);
    }
    return value.round().toString();
  }

  Widget _buildPresetBrowser(double padding) {
    final categories = LayerDspPresets.categories;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.all(padding),
        itemCount: categories.length,
        itemBuilder: (context, catIndex) {
          final category = categories[catIndex];
          final presets = LayerDspPresets.getByCategory(category);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  category,
                  style: TextStyle(
                    color: _accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: presets.map((preset) {
                  return InkWell(
                    onTap: () => _applyPreset(preset),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF242430),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade700),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            preset.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (preset.description.isNotEmpty)
                            Text(
                              preset.description,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 9,
                              ),
                            ),
                          Text(
                            '${preset.chain.length} processor(s)',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  IconData _getTypeIcon(LayerDspType type) {
    return switch (type) {
      LayerDspType.eq => Icons.equalizer,
      LayerDspType.compressor => Icons.compress,
      LayerDspType.reverb => Icons.blur_on,
      LayerDspType.delay => Icons.schedule,
    };
  }

  Color _getTypeColor(LayerDspType type) {
    return switch (type) {
      LayerDspType.eq => const Color(0xFF4A9EFF),
      LayerDspType.compressor => const Color(0xFFFF9040),
      LayerDspType.reverb => const Color(0xFF40C8FF),
      LayerDspType.delay => const Color(0xFF40FF90),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT LAYER DSP BADGE
// ═══════════════════════════════════════════════════════════════════════════

/// Compact badge showing layer DSP status, opens panel on tap
class LayerDspBadge extends StatelessWidget {
  final List<LayerDspNode> chain;
  final VoidCallback? onTap;
  final Color? accentColor;

  const LayerDspBadge({
    super.key,
    required this.chain,
    this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    if (chain.isEmpty) {
      return const SizedBox.shrink();
    }

    final accent = accentColor ?? const Color(0xFF4A9EFF);
    final activeCount = chain.where((n) => !n.bypass).length;

    return Tooltip(
      message: '${chain.length} DSP processor(s) ($activeCount active)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: accent.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 10, color: accent),
              const SizedBox(width: 4),
              ...chain.take(4).map((node) => Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Icon(
                      _getTypeIcon(node.type),
                      size: 10,
                      color: node.bypass ? Colors.grey : _getTypeColor(node.type),
                    ),
                  )),
              if (chain.length > 4)
                Text(
                  '+${chain.length - 4}',
                  style: TextStyle(color: accent, fontSize: 9),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getTypeIcon(LayerDspType type) {
    return switch (type) {
      LayerDspType.eq => Icons.equalizer,
      LayerDspType.compressor => Icons.compress,
      LayerDspType.reverb => Icons.blur_on,
      LayerDspType.delay => Icons.schedule,
    };
  }

  Color _getTypeColor(LayerDspType type) {
    return switch (type) {
      LayerDspType.eq => const Color(0xFF4A9EFF),
      LayerDspType.compressor => const Color(0xFFFF9040),
      LayerDspType.reverb => const Color(0xFF40C8FF),
      LayerDspType.delay => const Color(0xFF40FF90),
    };
  }
}
