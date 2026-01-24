// Internal Processor Editor Window
//
// Floating window for editing internal DSP processor parameters
// Used for EQ, Compressor, Limiter, Gate, etc.

import 'package:flutter/material.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';

/// Floating editor window for internal DSP processors
class InternalProcessorEditorWindow extends StatefulWidget {
  final int trackId;
  final int slotIndex;
  final DspNode node;
  final VoidCallback? onClose;

  const InternalProcessorEditorWindow({
    super.key,
    required this.trackId,
    required this.slotIndex,
    required this.node,
    this.onClose,
  });

  /// Show the editor as a floating overlay
  static OverlayEntry? show({
    required BuildContext context,
    required int trackId,
    required int slotIndex,
    required DspNode node,
  }) {
    final overlay = Overlay.of(context);
    OverlayEntry? entry;

    entry = OverlayEntry(
      builder: (context) => InternalProcessorEditorWindow(
        trackId: trackId,
        slotIndex: slotIndex,
        node: node,
        onClose: () => entry?.remove(),
      ),
    );

    overlay.insert(entry);
    return entry;
  }

  @override
  State<InternalProcessorEditorWindow> createState() =>
      _InternalProcessorEditorWindowState();
}

class _InternalProcessorEditorWindowState
    extends State<InternalProcessorEditorWindow> {
  Offset _position = const Offset(100, 100);
  bool _isDragging = false;
  late Map<String, dynamic> _params;

  @override
  void initState() {
    super.initState();
    _params = Map<String, dynamic>.from(widget.node.params);
  }

  void _updateParam(String key, dynamic value, int paramIndex) {
    setState(() {
      _params[key] = value;
    });

    // Send to FFI
    if (value is num) {
      NativeFFI.instance.insertSetParam(
        widget.trackId,
        widget.slotIndex,
        paramIndex,
        value.toDouble(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Material(
        elevation: 16,
        borderRadius: BorderRadius.circular(8),
        color: FluxForgeTheme.bgDeep,
        child: Container(
          width: 400,
          decoration: BoxDecoration(
            border: Border.all(color: FluxForgeTheme.bgSurface, width: 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTitleBar(),
              _buildContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
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
        height: 36,
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
            // Type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getTypeColor(widget.node.type).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.node.type.shortName,
                style: TextStyle(
                  color: _getTypeColor(widget.node.type),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Name
            Expanded(
              child: Text(
                widget.node.name,
                style: const TextStyle(
                  color: FluxForgeTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Bypass toggle
            IconButton(
              icon: Icon(
                Icons.power_settings_new,
                size: 18,
                color: widget.node.bypass
                    ? FluxForgeTheme.textDisabled
                    : FluxForgeTheme.accentGreen,
              ),
              tooltip: widget.node.bypass ? 'Enable' : 'Bypass',
              onPressed: () {
                // Toggle bypass via provider
                DspChainProvider.instance.toggleNodeBypass(
                  widget.trackId,
                  widget.node.id,
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),

            // Close button
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: FluxForgeTheme.textSecondary,
              tooltip: 'Close',
              onPressed: widget.onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(7),
          bottomRight: Radius.circular(7),
        ),
      ),
      child: _buildParamsForType(),
    );
  }

  Widget _buildParamsForType() {
    switch (widget.node.type) {
      case DspNodeType.eq:
        return _buildEqParams();
      case DspNodeType.compressor:
        return _buildCompressorParams();
      case DspNodeType.limiter:
        return _buildLimiterParams();
      case DspNodeType.gate:
        return _buildGateParams();
      case DspNodeType.expander:
        return _buildExpanderParams();
      case DspNodeType.reverb:
        return _buildReverbParams();
      case DspNodeType.delay:
        return _buildDelayParams();
      case DspNodeType.saturation:
        return _buildSaturationParams();
      case DspNodeType.deEsser:
        return _buildDeEsserParams();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPRESSOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCompressorParams() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamSlider(
          label: 'Threshold',
          value: (_params['threshold'] as num?)?.toDouble() ?? -20.0,
          min: -60,
          max: 0,
          unit: 'dB',
          onChanged: (v) => _updateParam('threshold', v, 0),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Ratio',
          value: (_params['ratio'] as num?)?.toDouble() ?? 4.0,
          min: 1,
          max: 20,
          unit: ':1',
          onChanged: (v) => _updateParam('ratio', v, 1),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Attack',
          value: (_params['attack'] as num?)?.toDouble() ?? 10.0,
          min: 0.1,
          max: 100,
          unit: 'ms',
          onChanged: (v) => _updateParam('attack', v, 2),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Release',
          value: (_params['release'] as num?)?.toDouble() ?? 100.0,
          min: 10,
          max: 1000,
          unit: 'ms',
          onChanged: (v) => _updateParam('release', v, 3),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Knee',
          value: (_params['knee'] as num?)?.toDouble() ?? 6.0,
          min: 0,
          max: 24,
          unit: 'dB',
          onChanged: (v) => _updateParam('knee', v, 4),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Makeup Gain',
          value: (_params['makeupGain'] as num?)?.toDouble() ?? 0.0,
          min: 0,
          max: 24,
          unit: 'dB',
          onChanged: (v) => _updateParam('makeupGain', v, 5),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // LIMITER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLimiterParams() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamSlider(
          label: 'Ceiling',
          value: (_params['ceiling'] as num?)?.toDouble() ?? -0.3,
          min: -12,
          max: 0,
          unit: 'dB',
          onChanged: (v) => _updateParam('ceiling', v, 0),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Release',
          value: (_params['release'] as num?)?.toDouble() ?? 50.0,
          min: 1,
          max: 500,
          unit: 'ms',
          onChanged: (v) => _updateParam('release', v, 1),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Lookahead',
          value: (_params['lookahead'] as num?)?.toDouble() ?? 5.0,
          min: 0,
          max: 10,
          unit: 'ms',
          onChanged: (v) => _updateParam('lookahead', v, 2),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GATE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildGateParams() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamSlider(
          label: 'Threshold',
          value: (_params['threshold'] as num?)?.toDouble() ?? -40.0,
          min: -80,
          max: 0,
          unit: 'dB',
          onChanged: (v) => _updateParam('threshold', v, 0),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Attack',
          value: (_params['attack'] as num?)?.toDouble() ?? 0.5,
          min: 0.01,
          max: 50,
          unit: 'ms',
          onChanged: (v) => _updateParam('attack', v, 1),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Release',
          value: (_params['release'] as num?)?.toDouble() ?? 50.0,
          min: 5,
          max: 500,
          unit: 'ms',
          onChanged: (v) => _updateParam('release', v, 2),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Range',
          value: (_params['range'] as num?)?.toDouble() ?? -80.0,
          min: -80,
          max: 0,
          unit: 'dB',
          onChanged: (v) => _updateParam('range', v, 3),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXPANDER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildExpanderParams() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamSlider(
          label: 'Threshold',
          value: (_params['threshold'] as num?)?.toDouble() ?? -30.0,
          min: -60,
          max: 0,
          unit: 'dB',
          onChanged: (v) => _updateParam('threshold', v, 0),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Ratio',
          value: (_params['ratio'] as num?)?.toDouble() ?? 2.0,
          min: 1,
          max: 10,
          unit: ':1',
          onChanged: (v) => _updateParam('ratio', v, 1),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Attack',
          value: (_params['attack'] as num?)?.toDouble() ?? 5.0,
          min: 0.1,
          max: 100,
          unit: 'ms',
          onChanged: (v) => _updateParam('attack', v, 2),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Release',
          value: (_params['release'] as num?)?.toDouble() ?? 50.0,
          min: 5,
          max: 500,
          unit: 'ms',
          onChanged: (v) => _updateParam('release', v, 3),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Knee',
          value: (_params['knee'] as num?)?.toDouble() ?? 3.0,
          min: 0,
          max: 12,
          unit: 'dB',
          onChanged: (v) => _updateParam('knee', v, 4),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REVERB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReverbParams() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamSlider(
          label: 'Decay',
          value: (_params['decay'] as num?)?.toDouble() ?? 2.0,
          min: 0.1,
          max: 10,
          unit: 's',
          onChanged: (v) => _updateParam('decay', v, 0),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Pre-Delay',
          value: (_params['preDelay'] as num?)?.toDouble() ?? 20.0,
          min: 0,
          max: 200,
          unit: 'ms',
          onChanged: (v) => _updateParam('preDelay', v, 1),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Damping',
          value: (_params['damping'] as num?)?.toDouble() ?? 0.5,
          min: 0,
          max: 1,
          unit: '',
          onChanged: (v) => _updateParam('damping', v, 2),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Size',
          value: (_params['size'] as num?)?.toDouble() ?? 0.7,
          min: 0,
          max: 1,
          unit: '',
          onChanged: (v) => _updateParam('size', v, 3),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DELAY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDelayParams() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamSlider(
          label: 'Time',
          value: (_params['time'] as num?)?.toDouble() ?? 250.0,
          min: 1,
          max: 2000,
          unit: 'ms',
          onChanged: (v) => _updateParam('time', v, 0),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Feedback',
          value: (_params['feedback'] as num?)?.toDouble() ?? 0.3,
          min: 0,
          max: 0.95,
          unit: '',
          onChanged: (v) => _updateParam('feedback', v, 1),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'High Cut',
          value: (_params['highCut'] as num?)?.toDouble() ?? 8000.0,
          min: 500,
          max: 20000,
          unit: 'Hz',
          onChanged: (v) => _updateParam('highCut', v, 2),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Low Cut',
          value: (_params['lowCut'] as num?)?.toDouble() ?? 80.0,
          min: 20,
          max: 500,
          unit: 'Hz',
          onChanged: (v) => _updateParam('lowCut', v, 3),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SATURATION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSaturationParams() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamSlider(
          label: 'Drive',
          value: (_params['drive'] as num?)?.toDouble() ?? 0.3,
          min: 0,
          max: 1,
          unit: '',
          onChanged: (v) => _updateParam('drive', v, 0),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Mix',
          value: (_params['mix'] as num?)?.toDouble() ?? 0.5,
          min: 0,
          max: 1,
          unit: '',
          onChanged: (v) => _updateParam('mix', v, 1),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DE-ESSER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDeEsserParams() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ParamSlider(
          label: 'Frequency',
          value: (_params['frequency'] as num?)?.toDouble() ?? 6000.0,
          min: 2000,
          max: 12000,
          unit: 'Hz',
          onChanged: (v) => _updateParam('frequency', v, 0),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Threshold',
          value: (_params['threshold'] as num?)?.toDouble() ?? -20.0,
          min: -40,
          max: 0,
          unit: 'dB',
          onChanged: (v) => _updateParam('threshold', v, 1),
        ),
        const SizedBox(height: 12),
        _ParamSlider(
          label: 'Range',
          value: (_params['range'] as num?)?.toDouble() ?? -10.0,
          min: -24,
          max: 0,
          unit: 'dB',
          onChanged: (v) => _updateParam('range', v, 2),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EQ (simplified - 5 bands)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEqParams() {
    final bands = _params['bands'] as List<dynamic>? ?? [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Parametric EQ',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        ...bands.asMap().entries.map((entry) {
          final idx = entry.key;
          final band = entry.value as Map<String, dynamic>;
          return _buildEqBand(idx, band);
        }),
      ],
    );
  }

  Widget _buildEqBand(int index, Map<String, dynamic> band) {
    final freq = (band['freq'] as num?)?.toDouble() ?? 1000.0;
    final gain = (band['gain'] as num?)?.toDouble() ?? 0.0;
    final type = band['type'] as String? ?? 'bell';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Band type indicator
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              type,
              style: const TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          // Frequency
          Expanded(
            child: Text(
              '${freq.toStringAsFixed(0)} Hz',
              style: const TextStyle(
                color: FluxForgeTheme.textPrimary,
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ),
          // Gain slider
          SizedBox(
            width: 120,
            child: Slider(
              value: gain.clamp(-12.0, 12.0),
              min: -12,
              max: 12,
              onChanged: (v) {
                // Update band gain
                final bands =
                    List<Map<String, dynamic>>.from(_params['bands'] as List);
                bands[index] = {...bands[index], 'gain': v};
                setState(() {
                  _params['bands'] = bands;
                });
                // EQ band params sent as packed index
                // paramIndex = band_index * 4 + param_offset (gain=1)
                NativeFFI.instance.insertSetParam(
                  widget.trackId,
                  widget.slotIndex,
                  index * 4 + 1,
                  v,
                );
              },
              activeColor: FluxForgeTheme.accentCyan,
              inactiveColor: FluxForgeTheme.bgMid,
            ),
          ),
          // Gain value
          SizedBox(
            width: 50,
            child: Text(
              '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              style: TextStyle(
                color: gain.abs() > 0.5
                    ? FluxForgeTheme.accentCyan
                    : FluxForgeTheme.textSecondary,
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(DspNodeType type) {
    switch (type) {
      case DspNodeType.eq:
        return FluxForgeTheme.accentCyan;
      case DspNodeType.compressor:
        return FluxForgeTheme.accentOrange;
      case DspNodeType.limiter:
        return FluxForgeTheme.accentRed;
      case DspNodeType.gate:
        return FluxForgeTheme.accentYellow;
      case DspNodeType.expander:
        return FluxForgeTheme.accentGreen;
      case DspNodeType.reverb:
        return FluxForgeTheme.accentBlue;
      case DspNodeType.delay:
        return FluxForgeTheme.accentPurple;
      case DspNodeType.saturation:
        return FluxForgeTheme.accentPink;
      case DspNodeType.deEsser:
        return FluxForgeTheme.accentCyan;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PARAM SLIDER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class _ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: FluxForgeTheme.accentCyan,
              inactiveTrackColor: FluxForgeTheme.bgMid,
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
        SizedBox(
          width: 65,
          child: Text(
            _formatValue(),
            style: const TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 11,
              fontFamily: 'JetBrains Mono',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  String _formatValue() {
    if (unit == 'dB') {
      return '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} $unit';
    } else if (unit == ':1') {
      return '${value.toStringAsFixed(1)}$unit';
    } else if (unit == 'Hz') {
      if (value >= 1000) {
        return '${(value / 1000).toStringAsFixed(1)} kHz';
      }
      return '${value.toStringAsFixed(0)} $unit';
    } else if (unit == 'ms' || unit == 's') {
      return '${value.toStringAsFixed(1)} $unit';
    } else if (unit.isEmpty) {
      return value.toStringAsFixed(2);
    }
    return '${value.toStringAsFixed(1)} $unit';
  }
}
