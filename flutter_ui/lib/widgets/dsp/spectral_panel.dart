/// Spectral Processing Panel
///
/// Professional spectral tools:
/// - Noise Gate (adaptive noise reduction)
/// - Spectral Freeze
/// - Spectral Compressor
/// - De-click

import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

enum SpectralMode { noiseGate, freeze, compressor, declick }

class SpectralPanel extends StatefulWidget {
  final int trackId;
  final double sampleRate;
  final VoidCallback? onSettingsChanged;

  const SpectralPanel({
    super.key,
    required this.trackId,
    this.sampleRate = 48000.0,
    this.onSettingsChanged,
  });

  @override
  State<SpectralPanel> createState() => _SpectralPanelState();
}

class _SpectralPanelState extends State<SpectralPanel> {
  final _ffi = NativeFFI.instance;

  SpectralMode _mode = SpectralMode.noiseGate;

  // Noise Gate settings
  double _gateThreshold = -40.0;
  double _gateReduction = -60.0;
  double _gateAttack = 10.0;
  double _gateRelease = 100.0;
  bool _learningNoise = false;

  // Freeze settings
  bool _frozen = false;
  double _freezeMix = 1.0;

  // Compressor settings
  double _compThreshold = -20.0;
  double _compRatio = 4.0;
  double _compAttack = 10.0;
  double _compRelease = 100.0;

  // De-click settings
  double _declickThreshold = 6.0;
  int _declickInterpLength = 16;

  @override
  void initState() {
    super.initState();
    // Create all processors
    _ffi.spectralGateCreate(widget.trackId, sampleRate: widget.sampleRate);
    _ffi.spectralFreezeCreate(widget.trackId, sampleRate: widget.sampleRate);
    _ffi.spectralCompressorCreate(widget.trackId, sampleRate: widget.sampleRate);
    _ffi.declickCreate(widget.trackId, sampleRate: widget.sampleRate);
    _syncAllToEngine();
  }

  @override
  void dispose() {
    _ffi.spectralGateDestroy(widget.trackId);
    _ffi.spectralFreezeDestroy(widget.trackId);
    _ffi.spectralCompressorDestroy(widget.trackId);
    _ffi.declickDestroy(widget.trackId);
    super.dispose();
  }

  void _syncAllToEngine() {
    // Gate
    _ffi.spectralGateSetThreshold(widget.trackId, _gateThreshold);
    _ffi.spectralGateSetReduction(widget.trackId, _gateReduction);
    _ffi.spectralGateSetAttack(widget.trackId, _gateAttack);
    _ffi.spectralGateSetRelease(widget.trackId, _gateRelease);
    // Freeze
    _ffi.spectralFreezeSetMix(widget.trackId, _freezeMix);
    // Compressor
    _ffi.spectralCompressorSetThreshold(widget.trackId, _compThreshold);
    _ffi.spectralCompressorSetRatio(widget.trackId, _compRatio);
    _ffi.spectralCompressorSetAttack(widget.trackId, _compAttack);
    _ffi.spectralCompressorSetRelease(widget.trackId, _compRelease);
    // De-click
    _ffi.declickSetThreshold(widget.trackId, _declickThreshold);
    _ffi.declickSetInterpLength(widget.trackId, _declickInterpLength);
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgVoid,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          _buildModeSelector(),
          Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          Expanded(child: _buildModeContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.waves, color: FluxForgeTheme.accentCyan, size: 20),
          const SizedBox(width: 8),
          Text(
            'SPECTRAL',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Text(
            _modeName(_mode),
            style: TextStyle(
              color: FluxForgeTheme.accentCyan,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _modeName(SpectralMode mode) {
    switch (mode) {
      case SpectralMode.noiseGate: return 'NOISE GATE';
      case SpectralMode.freeze: return 'FREEZE';
      case SpectralMode.compressor: return 'COMPRESSOR';
      case SpectralMode.declick: return 'DE-CLICK';
    }
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: SpectralMode.values.map((mode) {
          final isSelected = mode == _mode;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => setState(() => _mode = mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? FluxForgeTheme.accentCyan : FluxForgeTheme.bgMid,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? FluxForgeTheme.accentCyan : FluxForgeTheme.borderMedium,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _modeIcon(mode),
                      style: TextStyle(
                        color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _modeIcon(SpectralMode mode) {
    switch (mode) {
      case SpectralMode.noiseGate: return 'NR';
      case SpectralMode.freeze: return 'FZ';
      case SpectralMode.compressor: return 'SC';
      case SpectralMode.declick: return 'DC';
    }
  }

  Widget _buildModeContent() {
    switch (_mode) {
      case SpectralMode.noiseGate: return _buildNoiseGateContent();
      case SpectralMode.freeze: return _buildFreezeContent();
      case SpectralMode.compressor: return _buildCompressorContent();
      case SpectralMode.declick: return _buildDeclickContent();
    }
  }

  Widget _buildNoiseGateContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Learn noise button
          GestureDetector(
            onTap: () {
              setState(() => _learningNoise = !_learningNoise);
              if (_learningNoise) {
                _ffi.spectralGateLearnNoiseStart(widget.trackId);
              } else {
                _ffi.spectralGateLearnNoiseStop(widget.trackId);
              }
              widget.onSettingsChanged?.call();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _learningNoise ? FluxForgeTheme.accentOrange : FluxForgeTheme.bgMid,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: _learningNoise ? FluxForgeTheme.accentOrange : FluxForgeTheme.borderMedium,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _learningNoise ? Icons.stop : Icons.mic,
                    color: _learningNoise ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _learningNoise ? 'LEARNING...' : 'LEARN NOISE PROFILE',
                    style: TextStyle(
                      color: _learningNoise ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSlider('THRESHOLD', _gateThreshold, -80, 0, 'dB', (v) {
            setState(() => _gateThreshold = v);
            _ffi.spectralGateSetThreshold(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 16),
          _buildSlider('REDUCTION', _gateReduction, -80, 0, 'dB', (v) {
            setState(() => _gateReduction = v);
            _ffi.spectralGateSetReduction(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 16),
          _buildSlider('ATTACK', _gateAttack, 0.1, 100, 'ms', (v) {
            setState(() => _gateAttack = v);
            _ffi.spectralGateSetAttack(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 16),
          _buildSlider('RELEASE', _gateRelease, 1, 1000, 'ms', (v) {
            setState(() => _gateRelease = v);
            _ffi.spectralGateSetRelease(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
        ],
      ),
    );
  }

  Widget _buildFreezeContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Freeze button
          GestureDetector(
            onTap: () {
              setState(() => _frozen = !_frozen);
              _ffi.spectralFreezeToggle(widget.trackId);
              widget.onSettingsChanged?.call();
            },
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _frozen ? FluxForgeTheme.accentCyan : FluxForgeTheme.bgMid,
                border: Border.all(
                  color: _frozen ? FluxForgeTheme.accentCyan : FluxForgeTheme.borderMedium,
                  width: 3,
                ),
                boxShadow: _frozen ? [
                  BoxShadow(
                    color: FluxForgeTheme.accentCyan.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ] : null,
              ),
              child: Center(
                child: Icon(
                  _frozen ? Icons.ac_unit : Icons.pause,
                  color: _frozen ? FluxForgeTheme.textPrimary : FluxForgeTheme.textTertiary,
                  size: 48,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _frozen ? 'FROZEN' : 'TAP TO FREEZE',
            style: TextStyle(
              color: _frozen ? FluxForgeTheme.accentCyan : FluxForgeTheme.textTertiary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 32),
          _buildSlider('MIX', _freezeMix * 100, 0, 100, '%', (v) {
            setState(() => _freezeMix = v / 100);
            _ffi.spectralFreezeSetMix(widget.trackId, _freezeMix);
            widget.onSettingsChanged?.call();
          }),
        ],
      ),
    );
  }

  Widget _buildCompressorContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSlider('THRESHOLD', _compThreshold, -60, 0, 'dB', (v) {
            setState(() => _compThreshold = v);
            _ffi.spectralCompressorSetThreshold(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 16),
          _buildSlider('RATIO', _compRatio, 1, 20, ':1', (v) {
            setState(() => _compRatio = v);
            _ffi.spectralCompressorSetRatio(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 16),
          _buildSlider('ATTACK', _compAttack, 0.1, 500, 'ms', (v) {
            setState(() => _compAttack = v);
            _ffi.spectralCompressorSetAttack(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 16),
          _buildSlider('RELEASE', _compRelease, 1, 5000, 'ms', (v) {
            setState(() => _compRelease = v);
            _ffi.spectralCompressorSetRelease(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
        ],
      ),
    );
  }

  Widget _buildDeclickContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Automatically detects and removes clicks, pops, and crackles.',
            style: TextStyle(color: FluxForgeTheme.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 24),
          _buildSlider('SENSITIVITY', _declickThreshold, 1, 20, 'dB', (v) {
            setState(() => _declickThreshold = v);
            _ffi.declickSetThreshold(widget.trackId, v);
            widget.onSettingsChanged?.call();
          }),
          const SizedBox(height: 16),
          _buildSlider('INTERP LENGTH', _declickInterpLength.toDouble(), 4, 128, 'samples', (v) {
            setState(() => _declickInterpLength = v.round());
            _ffi.declickSetInterpLength(widget.trackId, _declickInterpLength);
            widget.onSettingsChanged?.call();
          }),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, String unit, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: FluxForgeTheme.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            Text(
              '${value.toStringAsFixed(1)} $unit',
              style: TextStyle(
                color: FluxForgeTheme.accentCyan,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: FluxForgeTheme.accentCyan,
            inactiveTrackColor: FluxForgeTheme.borderSubtle,
            thumbColor: FluxForgeTheme.accentCyan,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayColor: FluxForgeTheme.accentCyan.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
