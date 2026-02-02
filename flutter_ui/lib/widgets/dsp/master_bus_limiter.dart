/// Master Bus Limiter Widget — P2-DAW-4
///
/// Professional true peak limiter for the master bus:
/// - True peak limiting with 8x oversampling
/// - ISP-safe ceiling (-0.1 to -3.0 dB)
/// - Multiple release modes (auto, fast, medium, slow)
/// - Real-time gain reduction metering
///
/// Usage:
///   MasterBusLimiter(
///     trackId: 0, // Master bus
///     onSettingsChanged: () => updateMix(),
///   )
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';

extension _LogExtension on double {
  double log10() => math.log(this) / math.ln10;
}

// ═══════════════════════════════════════════════════════════════════════════
// RELEASE MODE
// ═══════════════════════════════════════════════════════════════════════════

/// Limiter release mode
enum LimiterReleaseMode {
  auto('Auto', 'Automatic release based on material'),
  fast('Fast', '50ms release'),
  medium('Medium', '150ms release'),
  slow('Slow', '400ms release'),
  ultraSlow('Ultra Slow', '800ms release');

  final String name;
  final String description;

  const LimiterReleaseMode(this.name, this.description);

  double get releaseMs {
    switch (this) {
      case LimiterReleaseMode.auto:
        return -1; // Auto mode indicator
      case LimiterReleaseMode.fast:
        return 50;
      case LimiterReleaseMode.medium:
        return 150;
      case LimiterReleaseMode.slow:
        return 400;
      case LimiterReleaseMode.ultraSlow:
        return 800;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// OVERSAMPLING MODE
// ═══════════════════════════════════════════════════════════════════════════

/// Oversampling factor
enum OversamplingMode {
  none(1, 'Off', 'No oversampling'),
  x2(2, '2x', '2x oversampling'),
  x4(4, '4x', '4x oversampling'),
  x8(8, '8x', '8x true peak (recommended)');

  final int factor;
  final String name;
  final String description;

  const OversamplingMode(this.factor, this.name, this.description);
}

// ═══════════════════════════════════════════════════════════════════════════
// MASTER BUS LIMITER WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Professional master bus limiter with true peak detection
class MasterBusLimiter extends StatefulWidget {
  /// Track ID (0 for master bus)
  final int trackId;

  /// Callback when settings change
  final VoidCallback? onSettingsChanged;

  const MasterBusLimiter({
    super.key,
    this.trackId = 0,
    this.onSettingsChanged,
  });

  @override
  State<MasterBusLimiter> createState() => _MasterBusLimiterState();
}

class _MasterBusLimiterState extends State<MasterBusLimiter> {
  final NativeFFI _ffi = NativeFFI.instance;

  // Parameters
  double _threshold = -1.0; // dB
  double _ceiling = -0.3; // dB (ISP safe)
  LimiterReleaseMode _releaseMode = LimiterReleaseMode.auto;
  double _customRelease = 150.0; // ms
  OversamplingMode _oversampling = OversamplingMode.x8;
  double _lookahead = 5.0; // ms
  bool _enabled = true;
  bool _linkStereo = true;

  // Metering
  double _gainReduction = 0.0;
  double _truePeakL = -60.0;
  double _truePeakR = -60.0;
  double _maxTruePeak = -60.0;
  Timer? _meterTimer;

  // State
  int _limiterSlot = -1;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeLimiter();
    _startMetering();
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    super.dispose();
  }

  void _initializeLimiter() {
    // Find or create limiter slot on track
    // In a real implementation, this would use DspChainProvider
    _limiterSlot = 0; // Assume slot 0 for master limiter
    _initialized = true;
    _applyAllSettings();
    setState(() {});
  }

  void _startMetering() {
    _meterTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || !_initialized) return;

      // Get true peak from FFI
      final truePeak = _ffi.advancedGetTruePeak8x();

      // Get stereo peak meters for L/R display
      final (peakL, peakR) = _ffi.getPeakMeters();
      final peakLDb = peakL > 1e-10 ? 20.0 * (peakL).log10() : -60.0;
      final peakRDb = peakR > 1e-10 ? 20.0 * (peakR).log10() : -60.0;

      setState(() {
        _truePeakL = peakLDb;
        _truePeakR = peakRDb;
        _maxTruePeak = truePeak.maxDbtp;

        // Get gain reduction
        _gainReduction = _ffi.channelStripGetLimiterGr(widget.trackId);
      });
    });
  }

  void _applyAllSettings() {
    if (!_initialized || _limiterSlot < 0) return;

    // Apply settings via FFI
    // TruePeakLimiterWrapper: 0=Threshold, 1=Ceiling, 2=Release, 3=Oversampling
    _ffi.insertSetParam(widget.trackId, _limiterSlot, 0, _threshold);
    _ffi.insertSetParam(widget.trackId, _limiterSlot, 1, _ceiling);
    _ffi.insertSetParam(widget.trackId, _limiterSlot, 2, _effectiveRelease);
    _ffi.insertSetParam(widget.trackId, _limiterSlot, 3, _oversampling.factor.toDouble());

    // Bypass state
    _ffi.insertSetBypass(widget.trackId, _limiterSlot, !_enabled);

    widget.onSettingsChanged?.call();
  }

  double get _effectiveRelease {
    if (_releaseMode == LimiterReleaseMode.auto) {
      return -1; // Auto mode
    }
    return _customRelease;
  }

  void _resetMaxPeak() {
    setState(() => _maxTruePeak = -60.0);
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(),
          const SizedBox(height: 16),

          // Meters
          _buildMeters(),
          const SizedBox(height: 16),

          // Threshold & Ceiling
          _buildMainControls(),
          const SizedBox(height: 16),

          // Release mode
          _buildReleaseSection(),
          const SizedBox(height: 16),

          // Oversampling
          _buildOversamplingSection(),
          const SizedBox(height: 12),

          // Additional options
          _buildOptions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.shield, color: FluxForgeTheme.accentBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          'Master Limiter',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        // Enable toggle
        GestureDetector(
          onTap: () {
            setState(() => _enabled = !_enabled);
            _applyAllSettings();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _enabled
                  ? Colors.green.withValues(alpha: 0.2)
                  : FluxForgeTheme.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _enabled ? Colors.green : FluxForgeTheme.border,
              ),
            ),
            child: Text(
              _enabled ? 'ON' : 'OFF',
              style: TextStyle(
                color: _enabled ? Colors.green : FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMeters() {
    final isClipping = _maxTruePeak > _ceiling;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isClipping ? Colors.red : FluxForgeTheme.border,
        ),
      ),
      child: Column(
        children: [
          // Gain Reduction
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  'GR',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: _buildMeterBar(_gainReduction.abs(), 24, Colors.orange),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${_gainReduction.toStringAsFixed(1)} dB',
                  style: TextStyle(
                    color: _gainReduction < -1 ? Colors.orange : FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // True Peak L
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  'TP L',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
              Expanded(
                child: _buildMeterBar(
                  _truePeakL + 60,
                  60,
                  _truePeakL > _ceiling ? Colors.red : Colors.cyan,
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${_truePeakL.toStringAsFixed(1)} dB',
                  style: TextStyle(
                    color: _truePeakL > _ceiling ? Colors.red : FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // True Peak R
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  'TP R',
                  style: TextStyle(
                    color: FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
              Expanded(
                child: _buildMeterBar(
                  _truePeakR + 60,
                  60,
                  _truePeakR > _ceiling ? Colors.red : Colors.cyan,
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  '${_truePeakR.toStringAsFixed(1)} dB',
                  style: TextStyle(
                    color: _truePeakR > _ceiling ? Colors.red : FluxForgeTheme.textSecondary,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Max True Peak (with reset)
          Row(
            children: [
              Text(
                'MAX TP: ',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
              Text(
                '${_maxTruePeak.toStringAsFixed(2)} dBTP',
                style: TextStyle(
                  color: isClipping ? Colors.red : Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _resetMaxPeak,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.surface,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'RESET',
                    style: TextStyle(
                      color: FluxForgeTheme.textSecondary,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeterBar(double value, double maxValue, Color color) {
    final percentage = (value / maxValue).clamp(0.0, 1.0);

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: percentage,
        backgroundColor: FluxForgeTheme.surfaceDark,
        valueColor: AlwaysStoppedAnimation<Color>(color),
        minHeight: 8,
      ),
    );
  }

  Widget _buildMainControls() {
    return Row(
      children: [
        // Threshold
        Expanded(
          child: _buildKnobControl(
            label: 'Threshold',
            value: _threshold,
            min: -20.0,
            max: 0.0,
            unit: 'dB',
            onChanged: (v) {
              setState(() => _threshold = v);
              _applyAllSettings();
            },
          ),
        ),
        const SizedBox(width: 16),
        // Ceiling
        Expanded(
          child: _buildKnobControl(
            label: 'Ceiling',
            value: _ceiling,
            min: -3.0,
            max: -0.1,
            unit: 'dB',
            onChanged: (v) {
              setState(() => _ceiling = v);
              _applyAllSettings();
            },
            isISPSafe: true,
          ),
        ),
      ],
    );
  }

  Widget _buildKnobControl({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
    bool isISPSafe = false,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(1)} $unit',
          style: TextStyle(
            color: FluxForgeTheme.accentBlue,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (isISPSafe)
          Text(
            'ISP Safe',
            style: TextStyle(
              color: Colors.green,
              fontSize: 9,
            ),
          ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: FluxForgeTheme.accentBlue,
            inactiveTrackColor: FluxForgeTheme.surface,
            thumbColor: FluxForgeTheme.accentBlue,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildReleaseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Release Mode',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: LimiterReleaseMode.values.map((mode) {
            final isActive = _releaseMode == mode;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _releaseMode = mode;
                  if (mode != LimiterReleaseMode.auto) {
                    _customRelease = mode.releaseMs;
                  }
                });
                _applyAllSettings();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                  mode.name,
                  style: TextStyle(
                    color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildOversamplingSection() {
    return Row(
      children: [
        Text(
          'Oversampling',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 11,
          ),
        ),
        const Spacer(),
        ...OversamplingMode.values.map((mode) {
          final isActive = _oversampling == mode;
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: () {
                setState(() => _oversampling = mode);
                _applyAllSettings();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  mode.name,
                  style: TextStyle(
                    color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildOptions() {
    return Row(
      children: [
        // Link Stereo
        GestureDetector(
          onTap: () {
            setState(() => _linkStereo = !_linkStereo);
            _applyAllSettings();
          },
          child: Row(
            children: [
              Icon(
                _linkStereo ? Icons.link : Icons.link_off,
                size: 14,
                color: _linkStereo ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'Link Stereo',
                style: TextStyle(
                  color: _linkStereo ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Lookahead
        Text(
          'Lookahead: ${_lookahead.toStringAsFixed(1)}ms',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
