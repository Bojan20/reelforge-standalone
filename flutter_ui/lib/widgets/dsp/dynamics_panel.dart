/// FluxForge Studio Professional Dynamics Panel
///
/// Multi-mode dynamics processor with Compressor, Limiter, Gate, and Expander.
///
/// ARCHITECTURE (2026-01-23):
/// Uses DspChainProvider for proper audio engine integration.
/// All processors are loaded into the insert chain and parameters
/// are set via insertSetParam() FFI calls.

import 'package:flutter/material.dart';
import '../../providers/dsp_chain_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

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
  // FFI reference
  final NativeFFI _ffi = NativeFFI.instance;

  // DspChainProvider slot indices for each processor type
  int _compressorSlot = -1;
  int _limiterSlot = -1;
  int _gateSlot = -1;
  int _expanderSlot = -1;

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
  // ignore: unused_field
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
  // ignore: unused_field
  double _inputLevel = -60.0;
  // ignore: unused_field
  double _outputLevel = -60.0;

  @override
  void initState() {
    super.initState();
    _initializeProcessors();
  }

  @override
  void dispose() {
    // Note: DspChainProvider manages processor lifecycle.
    // We don't remove processors on dispose - they stay in the chain
    // until explicitly removed via DspChainProvider.removeNode().
    // This is intentional - processors should persist across widget rebuilds.
    super.dispose();
  }

  void _initializeProcessors() {
    // Use DspChainProvider to add processors to the insert chain
    final dsp = DspChainProvider.instance;
    var chain = dsp.getChain(widget.trackId);

    // Helper to find or add a processor and return its slot index
    int findOrAddProcessor(DspNodeType type) {
      // Check if processor of this type already exists
      for (int i = 0; i < chain.nodes.length; i++) {
        if (chain.nodes[i].type == type) {
          return i;
        }
      }
      // Not found, add it
      dsp.addNode(widget.trackId, type);
      chain = dsp.getChain(widget.trackId); // Refresh chain
      return chain.nodes.length - 1;
    }

    // Add all processor types
    _compressorSlot = findOrAddProcessor(DspNodeType.compressor);
    chain = dsp.getChain(widget.trackId); // Refresh after each add
    _limiterSlot = findOrAddProcessor(DspNodeType.limiter);
    chain = dsp.getChain(widget.trackId);
    _gateSlot = findOrAddProcessor(DspNodeType.gate);
    chain = dsp.getChain(widget.trackId);
    _expanderSlot = findOrAddProcessor(DspNodeType.expander);

    final success = _compressorSlot >= 0 || _limiterSlot >= 0 || _gateSlot >= 0 || _expanderSlot >= 0;
    if (success) {
      setState(() => _initialized = true);
      _applyAllSettings();
    }
  }

  void _applyAllSettings() {
    if (!_initialized) return;

    // Apply compressor settings via insertSetParam
    // CompressorWrapper: 0=Threshold, 1=Ratio, 2=Attack, 3=Release, 4=Makeup, 5=Mix, 6=Link, 7=Type
    if (_compressorSlot >= 0) {
      _ffi.insertSetParam(widget.trackId, _compressorSlot, 0, _compThreshold);
      _ffi.insertSetParam(widget.trackId, _compressorSlot, 1, _compRatio);
      _ffi.insertSetParam(widget.trackId, _compressorSlot, 2, _compAttack);
      _ffi.insertSetParam(widget.trackId, _compressorSlot, 3, _compRelease);
      _ffi.insertSetParam(widget.trackId, _compressorSlot, 4, _compMakeupGain);
      _ffi.insertSetParam(widget.trackId, _compressorSlot, 5, _compDryWet);
      _ffi.insertSetParam(widget.trackId, _compressorSlot, 7, _compressorType.index.toDouble());
      // Note: Knee is not exposed via CompressorWrapper param indices
    }

    // Apply limiter settings via insertSetParam
    // TruePeakLimiterWrapper: 0=Threshold, 1=Ceiling, 2=Release, 3=Oversampling
    if (_limiterSlot >= 0) {
      _ffi.insertSetParam(widget.trackId, _limiterSlot, 0, _limThreshold);
      _ffi.insertSetParam(widget.trackId, _limiterSlot, 1, _limCeiling);
      _ffi.insertSetParam(widget.trackId, _limiterSlot, 2, _limRelease);
      // Note: Lookahead is not exposed via TruePeakLimiterWrapper param indices
    }

    // Apply gate settings via insertSetParam
    // GateWrapper: 0=Threshold, 1=Range, 2=Attack, 3=Hold, 4=Release
    if (_gateSlot >= 0) {
      _ffi.insertSetParam(widget.trackId, _gateSlot, 0, _gateThreshold);
      _ffi.insertSetParam(widget.trackId, _gateSlot, 1, _gateRange);
      _ffi.insertSetParam(widget.trackId, _gateSlot, 2, _gateAttack);
      _ffi.insertSetParam(widget.trackId, _gateSlot, 3, _gateHold);
      _ffi.insertSetParam(widget.trackId, _gateSlot, 4, _gateRelease);
    }

    // Apply expander settings via insertSetParam
    // ExpanderWrapper: 0=Threshold, 1=Ratio, 2=Knee, 3=Attack, 4=Release
    if (_expanderSlot >= 0) {
      _ffi.insertSetParam(widget.trackId, _expanderSlot, 0, _expThreshold);
      _ffi.insertSetParam(widget.trackId, _expanderSlot, 1, _expRatio);
      _ffi.insertSetParam(widget.trackId, _expanderSlot, 2, _expKnee);
      _ffi.insertSetParam(widget.trackId, _expanderSlot, 3, _expAttack);
      _ffi.insertSetParam(widget.trackId, _expanderSlot, 4, _expRelease);
    }

    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surfaceDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
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
        Icon(Icons.compress, color: FluxForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'Dynamics',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
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
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _bypassed ? Colors.orange : FluxForgeTheme.border,
              ),
            ),
            child: Text(
              'BYPASS',
              style: TextStyle(
                color: _bypassed ? Colors.orange : FluxForgeTheme.textSecondary,
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
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                : FluxForgeTheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
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
        color: FluxForgeTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'GR',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_gainReduction.toStringAsFixed(1)} dB',
                style: TextStyle(
                  color: _gainReduction < -1 ? Colors.orange : FluxForgeTheme.textSecondary,
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
              backgroundColor: FluxForgeTheme.surface,
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
              if (_compressorSlot >= 0) _ffi.insertSetParam(widget.trackId, _compressorSlot, 0, _compThreshold);
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
              if (_compressorSlot >= 0) _ffi.insertSetParam(widget.trackId, _compressorSlot, 1, _compRatio);
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
              if (_compressorSlot >= 0) _ffi.insertSetParam(widget.trackId, _compressorSlot, 2, _compAttack);
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
              if (_compressorSlot >= 0) _ffi.insertSetParam(widget.trackId, _compressorSlot, 3, _compRelease);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Knee (UI-only - not exposed via CompressorWrapper param indices)
        _buildParameterRow(
          label: 'Knee',
          value: '${_compKnee.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: _compKnee / 24,
            onChanged: (v) {
              setState(() => _compKnee = v * 24);
              // Note: Knee is UI-only - CompressorWrapper doesn't expose it via param index
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
              if (_compressorSlot >= 0) _ffi.insertSetParam(widget.trackId, _compressorSlot, 4, _compMakeupGain);
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
              if (_compressorSlot >= 0) _ffi.insertSetParam(widget.trackId, _compressorSlot, 5, _compDryWet);
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
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
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
          // CompressorWrapper param index 7 = Type
          if (_compressorSlot >= 0) _ffi.insertSetParam(widget.trackId, _compressorSlot, 7, type.index.toDouble());
          widget.onSettingsChanged?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
                : FluxForgeTheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
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
              // TruePeakLimiterWrapper param index 0 = Threshold
              if (_limiterSlot >= 0) _ffi.insertSetParam(widget.trackId, _limiterSlot, 0, _limThreshold);
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
              // TruePeakLimiterWrapper param index 1 = Ceiling
              if (_limiterSlot >= 0) _ffi.insertSetParam(widget.trackId, _limiterSlot, 1, _limCeiling);
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
              // TruePeakLimiterWrapper param index 2 = Release
              if (_limiterSlot >= 0) _ffi.insertSetParam(widget.trackId, _limiterSlot, 2, _limRelease);
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
              // GateWrapper param index 0 = Threshold
              if (_gateSlot >= 0) _ffi.insertSetParam(widget.trackId, _gateSlot, 0, _gateThreshold);
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
              // GateWrapper param index 1 = Range
              if (_gateSlot >= 0) _ffi.insertSetParam(widget.trackId, _gateSlot, 1, _gateRange);
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
              // GateWrapper param index 2 = Attack
              if (_gateSlot >= 0) _ffi.insertSetParam(widget.trackId, _gateSlot, 2, _gateAttack);
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
              // GateWrapper param index 3 = Hold
              if (_gateSlot >= 0) _ffi.insertSetParam(widget.trackId, _gateSlot, 3, _gateHold);
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
              // GateWrapper param index 4 = Release
              if (_gateSlot >= 0) _ffi.insertSetParam(widget.trackId, _gateSlot, 4, _gateRelease);
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
              // ExpanderWrapper param index 0 = Threshold
              if (_expanderSlot >= 0) _ffi.insertSetParam(widget.trackId, _expanderSlot, 0, _expThreshold);
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
              // ExpanderWrapper param index 1 = Ratio
              if (_expanderSlot >= 0) _ffi.insertSetParam(widget.trackId, _expanderSlot, 1, _expRatio);
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
              // ExpanderWrapper param index 3 = Attack
              if (_expanderSlot >= 0) _ffi.insertSetParam(widget.trackId, _expanderSlot, 3, _expAttack);
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
              // ExpanderWrapper param index 4 = Release
              if (_expanderSlot >= 0) _ffi.insertSetParam(widget.trackId, _expanderSlot, 4, _expRelease);
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
              // ExpanderWrapper param index 2 = Knee
              if (_expanderSlot >= 0) _ffi.insertSetParam(widget.trackId, _expanderSlot, 2, _expKnee);
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
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
          ),
        ),
        Expanded(child: child),
        SizedBox(
          width: 70,
          child: Text(
            value,
            style: TextStyle(
              color: FluxForgeTheme.accentBlue,
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
        activeTrackColor: FluxForgeTheme.accentBlue,
        inactiveTrackColor: FluxForgeTheme.surface,
        thumbColor: FluxForgeTheme.accentBlue,
        overlayColor: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
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
