/// FluxForge Studio Professional De-Esser Panel
///
/// Sibilance control processor with:
/// - Variable frequency detection (2-16 kHz)
/// - Wideband or split-band modes
/// - Listen mode for sidechain monitoring
/// - Real-time gain reduction metering

import 'dart:async';
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

/// Professional De-Esser Panel Widget
class DeEsserPanel extends StatefulWidget {
  /// Track ID to process
  final int trackId;

  /// Sample rate
  final double sampleRate;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const DeEsserPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<DeEsserPanel> createState() => _DeEsserPanelState();
}

class _DeEsserPanelState extends State<DeEsserPanel> {
  // Parameters
  double _frequency = 6000.0;
  double _bandwidth = 1.0;
  double _threshold = -20.0;
  double _range = 12.0;
  DeEsserMode _mode = DeEsserMode.wideband;
  double _attack = 0.5;
  double _release = 50.0;
  bool _listen = false;
  bool _bypass = false;

  // State
  bool _initialized = false;
  double _gainReduction = 0.0;
  Timer? _meterTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    NativeFFI.instance.deesserRemove(widget.trackId);
    super.dispose();
  }

  void _initialize() {
    final success = NativeFFI.instance.deesserCreate(
      widget.trackId,
      sampleRate: widget.sampleRate,
    );

    if (success) {
      setState(() => _initialized = true);
      _applyAllSettings();
      _startMetering();
    }
  }

  void _startMetering() {
    _meterTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_initialized) return;
      final gr = NativeFFI.instance.deesserGetGainReduction(widget.trackId);
      if (mounted && gr != _gainReduction) {
        setState(() => _gainReduction = gr);
      }
    });
  }

  void _applyAllSettings() {
    if (!_initialized) return;

    NativeFFI.instance.deesserSetFrequency(widget.trackId, _frequency);
    NativeFFI.instance.deesserSetBandwidth(widget.trackId, _bandwidth);
    NativeFFI.instance.deesserSetThreshold(widget.trackId, _threshold);
    NativeFFI.instance.deesserSetRange(widget.trackId, _range);
    NativeFFI.instance.deesserSetMode(widget.trackId, _mode);
    NativeFFI.instance.deesserSetAttack(widget.trackId, _attack);
    NativeFFI.instance.deesserSetRelease(widget.trackId, _release);
    NativeFFI.instance.deesserSetListen(widget.trackId, _listen);
    NativeFFI.instance.deesserSetBypass(widget.trackId, _bypass);

    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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

          // Parameters
          _buildParameters(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text(
          'De-Esser',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),

        // Listen button
        GestureDetector(
          onTap: () {
            setState(() => _listen = !_listen);
            NativeFFI.instance.deesserSetListen(widget.trackId, _listen);
            widget.onSettingsChanged?.call();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _listen
                  ? FluxForgeTheme.accentCyan.withValues(alpha: 0.3)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _listen ? FluxForgeTheme.accentCyan : FluxForgeTheme.border,
              ),
            ),
            child: Text(
              'LISTEN',
              style: TextStyle(
                color: _listen ? FluxForgeTheme.accentCyan : FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Bypass button
        GestureDetector(
          onTap: () {
            setState(() => _bypass = !_bypass);
            NativeFFI.instance.deesserSetBypass(widget.trackId, _bypass);
            widget.onSettingsChanged?.call();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _bypass
                  ? Colors.orange.withValues(alpha: 0.3)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _bypass ? Colors.orange : FluxForgeTheme.border,
              ),
            ),
            child: Text(
              'BYPASS',
              style: TextStyle(
                color: _bypass ? Colors.orange : FluxForgeTheme.textSecondary,
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
        Text(
          'Mode',
          style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Row(
            children: [
              _buildModeChip('Wideband', DeEsserMode.wideband),
              const SizedBox(width: 8),
              _buildModeChip('Split-Band', DeEsserMode.splitBand),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeChip(String label, DeEsserMode mode) {
    final isActive = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _mode = mode);
          NativeFFI.instance.deesserSetMode(widget.trackId, _mode);
          widget.onSettingsChanged?.call();
        },
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
                'Gain Reduction',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '-${_gainReduction.toStringAsFixed(1)} dB',
                style: TextStyle(
                  color: _gainReduction > 3 ? Colors.orange : FluxForgeTheme.textSecondary,
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
              value: (_gainReduction / 24.0).clamp(0.0, 1.0),
              backgroundColor: FluxForgeTheme.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                _gainReduction > 6 ? Colors.orange : FluxForgeTheme.accentCyan,
              ),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameters() {
    return Column(
      children: [
        // Detection section header
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Detection',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Frequency (2000-16000 Hz)
        _buildParameterRow(
          label: 'Frequency',
          value: '${(_frequency / 1000).toStringAsFixed(1)} kHz',
          child: _buildSlider(
            value: (_frequency - 2000) / 14000,
            onChanged: (v) {
              setState(() => _frequency = v * 14000 + 2000);
              NativeFFI.instance.deesserSetFrequency(widget.trackId, _frequency);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Bandwidth (0.25-4.0 octaves)
        _buildParameterRow(
          label: 'Bandwidth',
          value: '${_bandwidth.toStringAsFixed(2)} oct',
          child: _buildSlider(
            value: (_bandwidth - 0.25) / 3.75,
            onChanged: (v) {
              setState(() => _bandwidth = v * 3.75 + 0.25);
              NativeFFI.instance.deesserSetBandwidth(widget.trackId, _bandwidth);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 16),

        // Dynamics section header
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Dynamics',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Threshold (-60 to 0 dB)
        _buildParameterRow(
          label: 'Threshold',
          value: '${_threshold.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: (_threshold + 60) / 60,
            onChanged: (v) {
              setState(() => _threshold = v * 60 - 60);
              NativeFFI.instance.deesserSetThreshold(widget.trackId, _threshold);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Range (0-24 dB)
        _buildParameterRow(
          label: 'Range',
          value: '${_range.toStringAsFixed(1)} dB',
          child: _buildSlider(
            value: _range / 24,
            onChanged: (v) {
              setState(() => _range = v * 24);
              NativeFFI.instance.deesserSetRange(widget.trackId, _range);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Attack (0.1-50 ms)
        _buildParameterRow(
          label: 'Attack',
          value: '${_attack.toStringAsFixed(1)} ms',
          child: _buildSlider(
            value: (_attack - 0.1) / 49.9,
            onChanged: (v) {
              setState(() => _attack = v * 49.9 + 0.1);
              NativeFFI.instance.deesserSetAttack(widget.trackId, _attack);
              widget.onSettingsChanged?.call();
            },
          ),
        ),
        const SizedBox(height: 8),

        // Release (10-500 ms)
        _buildParameterRow(
          label: 'Release',
          value: '${_release.toStringAsFixed(0)} ms',
          child: _buildSlider(
            value: (_release - 10) / 490,
            onChanged: (v) {
              setState(() => _release = v * 490 + 10);
              NativeFFI.instance.deesserSetRelease(widget.trackId, _release);
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
