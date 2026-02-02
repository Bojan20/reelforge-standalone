/// Layer DSP Chain Widget (P12.1.5)
///
/// Per-layer DSP insert chain for composite events.
/// Provides mini DSP chain per audio layer with EQ, Compressor, Reverb, Delay.
///
/// Use case: Layer 1 has bright EQ, Layer 2 has dark EQ (different tonal color per layer).
///
/// Features:
/// - Add/remove DSP processors to specific layers
/// - Expandable section in layer inspector
/// - Parameter editing via sliders
/// - Bypass toggle per processor
/// - Wet/dry mix control
library;

import 'package:flutter/material.dart';
import '../../models/slot_audio_events.dart';
import '../../theme/fluxforge_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LAYER DSP CHAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Expandable DSP chain editor for a single layer
class LayerDspChain extends StatefulWidget {
  final SlotEventLayer layer;
  final ValueChanged<SlotEventLayer> onLayerChanged;
  final bool initiallyExpanded;

  const LayerDspChain({
    super.key,
    required this.layer,
    required this.onLayerChanged,
    this.initiallyExpanded = false,
  });

  @override
  State<LayerDspChain> createState() => _LayerDspChainState();
}

class _LayerDspChainState extends State<LayerDspChain> {
  bool _isExpanded = false;
  String? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  void _addProcessor(LayerDspType type) {
    final newNode = LayerDspNode.create(type);
    final updatedLayer = widget.layer.copyWith(
      dspChain: [...widget.layer.dspChain, newNode],
    );
    widget.onLayerChanged(updatedLayer);
    setState(() {
      _selectedNodeId = newNode.id;
    });
  }

  void _removeProcessor(String nodeId) {
    final updatedChain = widget.layer.dspChain.where((n) => n.id != nodeId).toList();
    final updatedLayer = widget.layer.copyWith(dspChain: updatedChain);
    widget.onLayerChanged(updatedLayer);
    if (_selectedNodeId == nodeId) {
      setState(() {
        _selectedNodeId = null;
      });
    }
  }

  void _toggleBypass(String nodeId) {
    final updatedChain = widget.layer.dspChain.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(bypass: !n.bypass);
      }
      return n;
    }).toList();
    final updatedLayer = widget.layer.copyWith(dspChain: updatedChain);
    widget.onLayerChanged(updatedLayer);
  }

  void _updateNodeParams(String nodeId, Map<String, dynamic> params) {
    final updatedChain = widget.layer.dspChain.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(params: {...n.params, ...params});
      }
      return n;
    }).toList();
    final updatedLayer = widget.layer.copyWith(dspChain: updatedChain);
    widget.onLayerChanged(updatedLayer);
  }

  void _updateNodeWetDry(String nodeId, double wetDry) {
    final updatedChain = widget.layer.dspChain.map((n) {
      if (n.id == nodeId) {
        return n.copyWith(wetDry: wetDry.clamp(0.0, 1.0));
      }
      return n;
    }).toList();
    final updatedLayer = widget.layer.copyWith(dspChain: updatedChain);
    widget.onLayerChanged(updatedLayer);
  }

  @override
  Widget build(BuildContext context) {
    final hasProcessors = widget.layer.dspChain.isNotEmpty;
    final activeCount = widget.layer.activeDspNodes.length;

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasProcessors
              ? FluxForgeTheme.accentPurple.withValues(alpha: 0.3)
              : FluxForgeTheme.bgSurface,
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildHeader(hasProcessors, activeCount),

          // Expanded content
          if (_isExpanded) ...[
            const Divider(height: 1, color: FluxForgeTheme.bgSurface),
            _buildContent(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(bool hasProcessors, int activeCount) {
    return InkWell(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            // Expand icon
            Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 6),

            // DSP icon
            Icon(
              Icons.tune,
              size: 14,
              color: hasProcessors
                  ? FluxForgeTheme.accentPurple
                  : FluxForgeTheme.textSecondary,
            ),
            const SizedBox(width: 6),

            // Title
            Text(
              'Layer DSP',
              style: TextStyle(
                color: hasProcessors
                    ? FluxForgeTheme.textPrimary
                    : FluxForgeTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),

            const Spacer(),

            // Active count badge
            if (hasProcessors)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentPurple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$activeCount/${widget.layer.dspChain.length}',
                  style: const TextStyle(
                    color: FluxForgeTheme.accentPurple,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Processor chain
          if (widget.layer.dspChain.isNotEmpty) ...[
            _buildProcessorChain(),
            const SizedBox(height: 8),
          ],

          // Add processor buttons
          _buildAddProcessorRow(),

          // Selected processor editor
          if (_selectedNodeId != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: FluxForgeTheme.bgSurface),
            const SizedBox(height: 8),
            _buildProcessorEditor(),
          ],
        ],
      ),
    );
  }

  Widget _buildProcessorChain() {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: widget.layer.dspChain.map((node) {
        final isSelected = _selectedNodeId == node.id;
        final color = _getTypeColor(node.type);

        return GestureDetector(
          onTap: () => setState(() {
            _selectedNodeId = isSelected ? null : node.id;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? color : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: node.bypass ? 0.1 : 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    node.type.shortName,
                    style: TextStyle(
                      color: node.bypass
                          ? FluxForgeTheme.textDisabled
                          : color,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // Bypass toggle
                GestureDetector(
                  onTap: () => _toggleBypass(node.id),
                  child: Icon(
                    Icons.power_settings_new,
                    size: 12,
                    color: node.bypass
                        ? FluxForgeTheme.textDisabled
                        : FluxForgeTheme.accentGreen,
                  ),
                ),
                const SizedBox(width: 2),

                // Remove button
                GestureDetector(
                  onTap: () => _removeProcessor(node.id),
                  child: const Icon(
                    Icons.close,
                    size: 12,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAddProcessorRow() {
    return Row(
      children: [
        const Text(
          'Add:',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
        const SizedBox(width: 6),
        ...LayerDspType.values.map((type) {
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _AddProcessorButton(
              type: type,
              onTap: () => _addProcessor(type),
              color: _getTypeColor(type),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildProcessorEditor() {
    final node = widget.layer.dspChain.firstWhere(
      (n) => n.id == _selectedNodeId,
      orElse: () => LayerDspNode.create(LayerDspType.eq),
    );

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _getTypeColor(node.type).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  node.type.fullName,
                  style: TextStyle(
                    color: _getTypeColor(node.type),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              // Wet/Dry control
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Mix',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 60,
                    child: Slider(
                      value: node.wetDry,
                      min: 0,
                      max: 1,
                      onChanged: (v) => _updateNodeWetDry(node.id, v),
                      activeColor: FluxForgeTheme.accentCyan,
                      inactiveColor: FluxForgeTheme.bgDeep,
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${(node.wetDry * 100).toInt()}%',
                      style: const TextStyle(
                        color: FluxForgeTheme.textSecondary,
                        fontSize: 9,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Parameters
          _buildParamsForType(node),
        ],
      ),
    );
  }

  Widget _buildParamsForType(LayerDspNode node) {
    switch (node.type) {
      case LayerDspType.eq:
        return _buildEqParams(node);
      case LayerDspType.compressor:
        return _buildCompressorParams(node);
      case LayerDspType.reverb:
        return _buildReverbParams(node);
      case LayerDspType.delay:
        return _buildDelayParams(node);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EQ PARAMETERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEqParams(LayerDspNode node) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Low band
        _ParamRow(
          label: 'Low',
          children: [
            _ParamSlider(
              value: (node.params['lowGain'] as num?)?.toDouble() ?? 0.0,
              min: -12,
              max: 12,
              unit: 'dB',
              width: 80,
              onChanged: (v) => _updateNodeParams(node.id, {'lowGain': v}),
            ),
            const SizedBox(width: 8),
            _FreqDisplay(
              value: (node.params['lowFreq'] as num?)?.toDouble() ?? 100.0,
            ),
          ],
        ),
        const SizedBox(height: 4),

        // Mid band
        _ParamRow(
          label: 'Mid',
          children: [
            _ParamSlider(
              value: (node.params['midGain'] as num?)?.toDouble() ?? 0.0,
              min: -12,
              max: 12,
              unit: 'dB',
              width: 80,
              onChanged: (v) => _updateNodeParams(node.id, {'midGain': v}),
            ),
            const SizedBox(width: 8),
            _FreqDisplay(
              value: (node.params['midFreq'] as num?)?.toDouble() ?? 1000.0,
            ),
          ],
        ),
        const SizedBox(height: 4),

        // High band
        _ParamRow(
          label: 'High',
          children: [
            _ParamSlider(
              value: (node.params['highGain'] as num?)?.toDouble() ?? 0.0,
              min: -12,
              max: 12,
              unit: 'dB',
              width: 80,
              onChanged: (v) => _updateNodeParams(node.id, {'highGain': v}),
            ),
            const SizedBox(width: 8),
            _FreqDisplay(
              value: (node.params['highFreq'] as num?)?.toDouble() ?? 8000.0,
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPRESSOR PARAMETERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCompressorParams(LayerDspNode node) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamRow(
          label: 'Thresh',
          children: [
            _ParamSlider(
              value: (node.params['threshold'] as num?)?.toDouble() ?? -20.0,
              min: -60,
              max: 0,
              unit: 'dB',
              width: 100,
              onChanged: (v) => _updateNodeParams(node.id, {'threshold': v}),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _ParamRow(
          label: 'Ratio',
          children: [
            _ParamSlider(
              value: (node.params['ratio'] as num?)?.toDouble() ?? 4.0,
              min: 1,
              max: 20,
              unit: ':1',
              width: 100,
              onChanged: (v) => _updateNodeParams(node.id, {'ratio': v}),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _ParamRow(
                label: 'Atk',
                children: [
                  _ParamSlider(
                    value: (node.params['attack'] as num?)?.toDouble() ?? 10.0,
                    min: 0.1,
                    max: 100,
                    unit: 'ms',
                    width: 60,
                    onChanged: (v) => _updateNodeParams(node.id, {'attack': v}),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _ParamRow(
                label: 'Rel',
                children: [
                  _ParamSlider(
                    value: (node.params['release'] as num?)?.toDouble() ?? 100.0,
                    min: 10,
                    max: 1000,
                    unit: 'ms',
                    width: 60,
                    onChanged: (v) => _updateNodeParams(node.id, {'release': v}),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _ParamRow(
          label: 'Gain',
          children: [
            _ParamSlider(
              value: (node.params['makeupGain'] as num?)?.toDouble() ?? 0.0,
              min: 0,
              max: 24,
              unit: 'dB',
              width: 100,
              onChanged: (v) => _updateNodeParams(node.id, {'makeupGain': v}),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REVERB PARAMETERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReverbParams(LayerDspNode node) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamRow(
          label: 'Decay',
          children: [
            _ParamSlider(
              value: (node.params['decay'] as num?)?.toDouble() ?? 2.0,
              min: 0.1,
              max: 10,
              unit: 's',
              width: 100,
              onChanged: (v) => _updateNodeParams(node.id, {'decay': v}),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _ParamRow(
          label: 'Pre-Dly',
          children: [
            _ParamSlider(
              value: (node.params['preDelay'] as num?)?.toDouble() ?? 20.0,
              min: 0,
              max: 200,
              unit: 'ms',
              width: 100,
              onChanged: (v) => _updateNodeParams(node.id, {'preDelay': v}),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _ParamRow(
                label: 'Damp',
                children: [
                  _ParamSlider(
                    value: (node.params['damping'] as num?)?.toDouble() ?? 0.5,
                    min: 0,
                    max: 1,
                    unit: '',
                    width: 60,
                    onChanged: (v) => _updateNodeParams(node.id, {'damping': v}),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _ParamRow(
                label: 'Size',
                children: [
                  _ParamSlider(
                    value: (node.params['size'] as num?)?.toDouble() ?? 0.7,
                    min: 0,
                    max: 1,
                    unit: '',
                    width: 60,
                    onChanged: (v) => _updateNodeParams(node.id, {'size': v}),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DELAY PARAMETERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDelayParams(LayerDspNode node) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamRow(
          label: 'Time',
          children: [
            _ParamSlider(
              value: (node.params['time'] as num?)?.toDouble() ?? 250.0,
              min: 1,
              max: 2000,
              unit: 'ms',
              width: 100,
              onChanged: (v) => _updateNodeParams(node.id, {'time': v}),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _ParamRow(
          label: 'Feedback',
          children: [
            _ParamSlider(
              value: (node.params['feedback'] as num?)?.toDouble() ?? 0.3,
              min: 0,
              max: 0.95,
              unit: '',
              width: 100,
              onChanged: (v) => _updateNodeParams(node.id, {'feedback': v}),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _ParamRow(
                label: 'HiCut',
                children: [
                  _ParamSlider(
                    value: (node.params['highCut'] as num?)?.toDouble() ?? 8000.0,
                    min: 500,
                    max: 20000,
                    unit: 'Hz',
                    width: 60,
                    onChanged: (v) => _updateNodeParams(node.id, {'highCut': v}),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _ParamRow(
                label: 'LoCut',
                children: [
                  _ParamSlider(
                    value: (node.params['lowCut'] as num?)?.toDouble() ?? 80.0,
                    min: 20,
                    max: 500,
                    unit: 'Hz',
                    width: 60,
                    onChanged: (v) => _updateNodeParams(node.id, {'lowCut': v}),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Color _getTypeColor(LayerDspType type) {
    switch (type) {
      case LayerDspType.eq:
        return FluxForgeTheme.accentCyan;
      case LayerDspType.compressor:
        return FluxForgeTheme.accentOrange;
      case LayerDspType.reverb:
        return FluxForgeTheme.accentBlue;
      case LayerDspType.delay:
        return FluxForgeTheme.accentPurple;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _AddProcessorButton extends StatelessWidget {
  final LayerDspType type;
  final VoidCallback onTap;
  final Color color;

  const _AddProcessorButton({
    required this.type,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 10, color: color),
            const SizedBox(width: 2),
            Text(
              type.shortName,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _ParamRow({
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _ParamSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final String unit;
  final double width;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.width,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: 20,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: FluxForgeTheme.accentCyan,
              inactiveTrackColor: FluxForgeTheme.bgDeep,
              thumbColor: FluxForgeTheme.accentCyan,
              overlayColor: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 40,
          child: Text(
            _formatValue(),
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 9,
              fontFamily: 'JetBrains Mono',
            ),
          ),
        ),
      ],
    );
  }

  String _formatValue() {
    if (unit == 'dB') {
      return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}';
    } else if (unit == ':1') {
      return '${value.toStringAsFixed(1)}:1';
    } else if (unit == 'Hz') {
      if (value >= 1000) {
        return '${(value / 1000).toStringAsFixed(1)}k';
      }
      return '${value.toInt()}';
    } else if (unit == 'ms' || unit == 's') {
      return '${value.toStringAsFixed(0)}$unit';
    } else if (unit.isEmpty) {
      return '${(value * 100).toInt()}%';
    }
    return value.toStringAsFixed(1);
  }
}

class _FreqDisplay extends StatelessWidget {
  final double value;

  const _FreqDisplay({required this.value});

  @override
  Widget build(BuildContext context) {
    final display = value >= 1000
        ? '${(value / 1000).toStringAsFixed(1)}kHz'
        : '${value.toInt()}Hz';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        display,
        style: const TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 8,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT LAYER DSP BADGE
// ═══════════════════════════════════════════════════════════════════════════

/// Compact badge showing layer DSP status (for use in layer list items)
class LayerDspBadge extends StatelessWidget {
  final SlotEventLayer layer;
  final VoidCallback? onTap;

  const LayerDspBadge({
    super.key,
    required this.layer,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!layer.hasDsp) {
      return const SizedBox.shrink();
    }

    final activeCount = layer.activeDspNodes.length;
    final totalCount = layer.dspChain.length;

    return Tooltip(
      message: 'Layer DSP: $activeCount/$totalCount active',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: FluxForgeTheme.accentPurple.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: FluxForgeTheme.accentPurple.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.tune,
                size: 10,
                color: FluxForgeTheme.accentPurple,
              ),
              const SizedBox(width: 3),
              Text(
                '$activeCount',
                style: const TextStyle(
                  color: FluxForgeTheme.accentPurple,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
