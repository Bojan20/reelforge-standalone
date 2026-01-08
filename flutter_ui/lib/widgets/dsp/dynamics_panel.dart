/// ReelForge Professional Dynamics Panel
///
/// Multi-mode dynamics processor with Compressor, Limiter, Gate, and Expander.

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/reelforge_theme.dart';

/// Dynamics processing mode
enum DynamicsMode {
  compressor,
  limiter,
  gate,
  expander,
}

/// Professional Dynamics Panel Widget
class DynamicsPanel extends StatefulWidget {
  /// Track ID to process
  final int trackId;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const DynamicsPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<DynamicsPanel> createState() => _DynamicsPanelState();
}

class _DynamicsPanelState extends State<DynamicsPanel> {
  // Mode selection
  DynamicsMode _mode = DynamicsMode.compressor;

  // Compressor parameters
  CompressorType _compressorType = CompressorType.vca;
  double _compThreshold = -20.0;
  double _compRatio = 4.0;
  double _compAttack = 10.0;
  double _compRelease = 100.0;
  double _compKnee = 6.0;
  double _compMakeupGain = 0.0;
  double _compDryWet = 1.0;
  bool _compAutoMakeup = false;

  // Limiter parameters
  double _limThreshold = -1.0;
  double _limRelease = 50.0;
  double _limCeiling = -0.3;
  double _limLookahead = 5.0;

  // Gate parameters
  double _gateThreshold = -40.0;
  double _gateRange = -80.0;
  double _gateAttack = 0.5;
  double _gateHold = 50.0;
  double _gateRelease = 100.0;

  // Expander parameters
  double _expThreshold = -30.0;
  double _expRatio = 2.0;
  double _expAttack = 5.0;
  double _expRelease = 50.0;
  double _expKnee = 3.0;

  // State
  bool _initialized = false;
  bool _bypassed = false;

  // Metering
  double _gainReduction = 0.0;
  double _inputLevel = -60.0;
  double _outputLevel = -60.0;

  @override
  void initState() {
    super.initState();
    _initializeProcessors();
  }

  @override
  void dispose() {
    NativeFFI.instance.compressorRemove(widget.trackId);
    NativeFFI.instance.limiterRemove(widget.trackId);
    NativeFFI.instance.gateRemove(widget.trackId);
    NativeFFI.instance.expanderRemove(widget.trackId);
    super.dispose();
  }

  void _initializeProcessors() {
    // Create all processor types
    final compSuccess = NativeFFI.instance.compressorCreate(
      widget.trackId,
      sampleRate: widget.sampleRate,
    );
    final limSuccess = NativeFFI.instance.limiterCreate(
      widget.trackId,
      sampleRate: widget.sampleRate,
    );
    final gateSuccess = NativeFFI.instance.gateCreate(
      widget.trackId,
      sampleRate: widget.sampleRate,
    );
    final expSuccess = NativeFFI.instance.expanderCreate(
      widget.trackId,
      sampleRate: widget.sampleRate,
    );

    if (compSuccess || limSuccess || gateSuccess || expSuccess) {
      setState(() => _initialized = true);
      _applyAllSettings();
    }
  }

  void _applyAllSettings() {
    if (!_initialized) return;

    // Apply compressor settings
    NativeFFI.instance.compressorSetType(widget.trackId, _compressorType);
    NativeFFI.instance.compressorSetThreshold(widget.trackId, _compThreshold);
    NativeFFI.instance.compressorSetRatio(widget.trackId, _compRatio);
    NativeFFI.instance.compressorSetAttack(widget.trackId, _compAttack);
    NativeFFI.instance.compressorSetRelease(widget.trackId, _compRelease);
    NativeFFI.instance.compressorSetKnee(widget.trackId, _compKnee);
    NativeFFI.instance.compressorSetMakeup(widget.trackId, _compMakeupGain);
    NativeFFI.instance.compressorSetMix(widget.trackId, _compDryWet);

    // Apply limiter settings
    NativeFFI.instance.limiterSetThreshold(widget.trackId, _limThreshold);
    NativeFFI.instance.limiterSetRelease(widget.trackId, _limRelease);
    NativeFFI.instance.limiterSetCeiling(widget.trackId, _limCeiling);

    // Apply gate settings
    NativeFFI.instance.gateSetThreshold(widget.trackId, _gateThreshold);
    NativeFFI.instance.gateSetRange(widget.trackId, _gateRange);
    NativeFFI.instance.gateSetAttack(widget.trackId, _gateAttack);
    NativeFFI.instance.gateSetHold(widget.trackId, _gateHold);
    NativeFFI.instance.gateSetRelease(widget.trackId, _gateRelease);

    // Apply expander settings
    NativeFFI.instance.expanderSetThreshold(widget.trackId, _expThreshold);
    NativeFFI.instance.expanderSetRatio(widget.trackId, _expRatio);
    NativeFFI.instance.expanderSetTimes(widget.trackId, _expAttack, _expRelease);
    NativeFFI.instance.expanderSetKnee(widget.trackId, _expKnee);

    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 16),

          // Mode selector
          _buildModeSelector(),
          const SizedBox(height: 16),

          // Gain reduction meter
          _buildGainReductionMeter(),
          const SizedBox(height: 16),

          // Mode-specific controls
          _buildModeControls(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.compress, color: ReelForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'Dynamics',
          style: TextStyle(
            color: ReelForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        // Bypass button
        GestureDetector(
          onTap: () => setState(() => _bypassed = !_bypassed),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _bypassed
                  ? Colors.orange.withValues(alpha: 0.3)
                  : ReelForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _bypassed ? Colors.orange : ReelForgeTheme.border,
              ),
            ),
            child: Text(
              'BYPASS',
              style: TextStyle(
                color: _bypassed ? Colors.orange : ReelForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Status indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _initialized
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _initialized ? 'Ready' : 'Init...',
            style: TextStyle(
              color: _initialized ? Colors.green : Colors.red,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Row(
      children: [
        _buildModeButton('Comp', DynamicsMode.compressor, Icons.compress),
        const SizedBox(width: 4),
        _buildModeButton('Limit', DynamicsMode.limiter, Icons.vertical_align_top),
        const SizedBox(width: 4),
        _buildModeButton('Gate', DynamicsMode.gate, Icons.door_sliding),
        const SizedBox(width: 4),
        _buildModeButton('Expand', DynamicsMode.expander, Icons.expand),
      ],
    );
  }

  Widget _buildModeButton(String label, DynamicsMode mode, IconData icon) {
    final isActive = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
                : ReelForgeTheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGainReductionMeter() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ReelForgeTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: ReelForgeTheme.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'GR',
                style: TextStyle(
                  color: ReelForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_gainReduction.toStringAsFixed(1)} dB',
                style: TextStyle(
                  color: _gainReduction < -1 ? Colors.orange : ReelForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (_gainReduction.abs() / 24.0).clamp(0.0, 1.0),
              backgroundColor: ReelForgeTheme.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                _gainReduction < -6 ? Colors.orange : Colors.green,
              ),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeControls() {
    switch (_mode) {
      case DynamicsMode.compressor:
        return _buildCompressorControls();
      case DynamicsMode.limiter:
        return _buildLimiterControls();
      case DynamicsMode.gate:
        return _buildGateControls();
      case DynamicsMode.expander:
        return _buildExpanderControls();
    }
  }

  Widget _buildCompressorControls() {
    return Column(
      children: [
        // Compressor type selector
        _buildCompressorTypeSelector(),
        const SizedBox(height: 16),

        // Threshold
        _buildParameterRow(
          label: 'Threshold',
          value: '${_compThreshold.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_compThreshold + 60) / 60,
            onChanged: (v) {
              setState(() => _compThreshold = v * 60 - 60);
              NativeFFI.instance.compressorSetThreshold(widget.trackId, _compThreshold);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Ratio
        _buildParameterRow(
          label: 'Ratio',
          value: '${_compRatio.toStringAsFixed(1)}:1',
          child: _buildSlider(
            value: (_compRatio - 1) / 19,
            onChanged: (v) {
              setState(() => _compRatio = v * 19 + 1);
              NativeFFI.instance.compressorSetRatio(widget.trackId, _compRatio);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Attack
        _buildParameterRow(
          label: 'Attack',
          value: '${_compAttack.toStringAsFixed(1)} ms',
          child: _buildSlider(
            value: _compAttack / 200,
            onChanged: (v) {
              setState(() => _compAttack = v * 200);
              NativeFFI.instance.compressorSetAttack(widget.trackId, _compAttack);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Release
        _buildParameterRow(
          label: 'Release',
          value: '${_compRelease.toStringAsFixed(0)} ms',
          child: _buildSlider(
            value: _compRelease / 2000,
            onChanged: (v) {
              setState(() => _compRelease = v * 2000);
              NativeFFI.instance.compressorSetRelease(widget.trackId, _compRelease);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Knee
        _buildParameterRow(
          label: 'Knee',
          value: '${_compKnee.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: _compKnee / 24,
            onChanged: (v) {
              setState(() => _compKnee = v * 24);
              NativeFFI.instance.compressorSetKnee(widget.trackId, _compKnee);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Makeup Gain
        _buildParameterRow(
          label: 'Makeup',
          value: '${_compMakeupGain.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_compMakeupGain + 12) / 36,
            onChanged: (v) {
              setState(() => _compMakeupGain = v * 36 - 12);
              NativeFFI.instance.compressorSetMakeup(widget.trackId, _compMakeupGain);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Dry/Wet (parallel compression)
        _buildParameterRow(
          label: 'Mix',
          value: '${(_compDryWet * 100).toStringAsFixed(0)}%',
          child: _buildSlider(
            value: _compDryWet,
            onChanged: (v) {
              setState(() => _compDryWet = v);
              NativeFFI.instance.compressorSetMix(widget.trackId, _compDryWet);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompressorTypeSelector() {
    return Row(
      children: [
        Text(
          'Type',
          style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Row(
            children: [
              _buildTypeChip('VCA', CompressorType.vca),
              const SizedBox(width: 8),
              _buildTypeChip('Opto', CompressorType.opto),
              const SizedBox(width: 8),
              _buildTypeChip('FET', CompressorType.fet),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChip(String label, CompressorType type) {
    final isActive = _compressorType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _compressorType = type);
          NativeFFI.instance.compressorSetType(widget.trackId, type);
          widget.onSettingsChanged?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? ReelForgeTheme.accentBlue.withValues(alpha: 0.2)
                : ReelForgeTheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? ReelForgeTheme.accentBlue : ReelForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLimiterControls() {
    return Column(
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(8),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'True Peak Limiter with ITU-R BS.1770-4 compliant oversampling',
                  style: TextStyle(color: Colors.blue, fontSize: 10),
                ),
              ),
            ],
          ),
        ),

        // Threshold
        _buildParameterRow(
          label: 'Threshold',
          value: '${_limThreshold.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_limThreshold + 20) / 20,
            onChanged: (v) {
              setState(() => _limThreshold = v * 20 - 20);
              NativeFFI.instance.limiterSetThreshold(widget.trackId, _limThreshold);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Ceiling
        _buildParameterRow(
          label: 'Ceiling',
          value: '${_limCeiling.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_limCeiling + 6) / 6,
            onChanged: (v) {
              setState(() => _limCeiling = v * 6 - 6);
              NativeFFI.instance.limiterSetCeiling(widget.trackId, _limCeiling);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Release
        _buildParameterRow(
          label: 'Release',
          value: '${_limRelease.toStringAsFixed(0)} ms',
          child: _buildSlider(
            value: _limRelease / 500,
            onChanged: (v) {
              setState(() => _limRelease = v * 500);
              NativeFFI.instance.limiterSetRelease(widget.trackId, _limRelease);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Lookahead
        _buildParameterRow(
          label: 'Lookahead',
          value: '${_limLookahead.toStringAsFixed(1)} ms',
          child: _buildSlider(
            value: _limLookahead / 10,
            onChanged: (v) {
              setState(() => _limLookahead = v * 10);
              // Note: lookahead typically set at init
              widget.onSettingsChanged?.call();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGateControls() {
    return Column(
      children: [
        // Threshold
        _buildParameterRow(
          label: 'Threshold',
          value: '${_gateThreshold.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_gateThreshold + 80) / 80,
            onChanged: (v) {
              setState(() => _gateThreshold = v * 80 - 80);
              NativeFFI.instance.gateSetThreshold(widget.trackId, _gateThreshold);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Range
        _buildParameterRow(
          label: 'Range',
          value: '${_gateRange.toStringAsFixed(0)} dB',
          child: _buildSlider(
            value: (_gateRange + 80) / 80,
            onChanged: (v) {
              setState(() => _gateRange = v * 80 - 80);
              NativeFFI.instance.gateSetRange(widget.trackId, _gateRange);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Attack
        _buildParameterRow(
          label: 'Attack',
          value: '${_gateAttack.toStringAsFixed(1)} ms',
          child: _buildSlider(
            value: _gateAttack / 50,
            onChanged: (v) {
              setState(() => _gateAttack = v * 50);
              NativeFFI.instance.gateSetAttack(widget.trackId, _gateAttack);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Hold
        _buildParameterRow(
          label: 'Hold',
          value: '${_gateHold.toStringAsFixed(0)} ms',
          child: _buildSlider(
            value: _gateHold / 500,
            onChanged: (v) {
              setState(() => _gateHold = v * 500);
              NativeFFI.instance.gateSetHold(widget.trackId, _gateHold);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Release
        _buildParameterRow(
          label: 'Release',
          value: '${_gateRelease.toStringAsFixed(0)} ms',
          child: _buildSlider(
            value: _gateRelease / 1000,
            onChanged: (v) {
              setState(() => _gateRelease = v * 1000);
              NativeFFI.instance.gateSetRelease(widget.trackId, _gateRelease);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExpanderControls() {
    return Column(
      children: [
        // Threshold
        _buildParameterRow(
          label: 'Threshold',
          value: '${_expThreshold.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_expThreshold + 60) / 60,
            onChanged: (v) {
              setState(() => _expThreshold = v * 60 - 60);
              NativeFFI.instance.expanderSetThreshold(widget.trackId, _expThreshold);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Ratio
        _buildParameterRow(
          label: 'Ratio',
          value: '1:${_expRatio.toStringAsFixed(1)}',
          child: _buildSlider(
            value: (_expRatio - 1) / 9,
            onChanged: (v) {
              setState(() => _expRatio = v * 9 + 1);
              NativeFFI.instance.expanderSetRatio(widget.trackId, _expRatio);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Attack
        _buildParameterRow(
          label: 'Attack',
          value: '${_expAttack.toStringAsFixed(1)} ms',
          child: _buildSlider(
            value: _expAttack / 100,
            onChanged: (v) {
              setState(() => _expAttack = v * 100);
              NativeFFI.instance.expanderSetTimes(widget.trackId, _expAttack, _expRelease);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Release
        _buildParameterRow(
          label: 'Release',
          value: '${_expRelease.toStringAsFixed(0)} ms',
          child: _buildSlider(
            value: _expRelease / 500,
            onChanged: (v) {
              setState(() => _expRelease = v * 500);
              NativeFFI.instance.expanderSetTimes(widget.trackId, _expAttack, _expRelease);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Knee
        _buildParameterRow(
          label: 'Knee',
          value: '${_expKnee.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: _expKnee / 12,
            onChanged: (v) {
              setState(() => _expKnee = v * 12);
              NativeFFI.instance.expanderSetKnee(widget.trackId, _expKnee);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildParameterRow({
    required String label,
    required String value,
    required Widget child,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(color: ReelForgeTheme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(child: child),
        SizedBox(
          width: 70,
          child: Text(
            value,
            style: TextStyle(
              color: ReelForgeTheme.accentBlue,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0.0,
    double max = 1.0,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: ReelForgeTheme.accentBlue,
        inactiveTrackColor: ReelForgeTheme.surface,
        thumbColor: ReelForgeTheme.accentBlue,
        overlayColor: ReelForgeTheme.accentBlue.withValues(alpha: 0.2),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}
