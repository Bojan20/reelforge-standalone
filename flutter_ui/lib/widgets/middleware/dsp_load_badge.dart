/// DSP Load Badge — Compact CPU Meter for Status Bars
///
/// Displays real-time DSP CPU load in a compact format:
/// - Visual bar meter
/// - Percentage display
/// - Health color coding (green → yellow → orange → red)
/// - Tooltip with stage breakdown
///
/// Uses Rust FFI for real engine data with simulation fallback.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';
import '../../src/rust/native_ffi.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// DSP LOAD BADGE — Compact Status Bar Widget
// ═══════════════════════════════════════════════════════════════════════════════

class DspLoadBadge extends StatefulWidget {
  final Duration refreshInterval;
  final bool showPercentage;
  final bool showMeter;

  const DspLoadBadge({
    super.key,
    this.refreshInterval = const Duration(milliseconds: 100),
    this.showPercentage = true,
    this.showMeter = true,
  });

  @override
  State<DspLoadBadge> createState() => _DspLoadBadgeState();
}

class _DspLoadBadgeState extends State<DspLoadBadge> {
  double _currentLoad = 0.0;
  double _peakLoad = 0.0;
  bool _isRustAvailable = false;
  Timer? _updateTimer;
  Map<String, double> _stageBreakdown = {};

  // For simulation when FFI not available
  int _simulationTick = 0;

  @override
  void initState() {
    super.initState();
    _checkRustFFI();
    _updateTimer = Timer.periodic(widget.refreshInterval, (_) => _updateLoad());
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _checkRustFFI() {
    try {
      NativeFFI.instance.profilerGetCurrentLoad();
      _isRustAvailable = true;
    } catch (e) {
      _isRustAvailable = false;
    }
  }

  void _updateLoad() {
    if (!mounted) return;

    if (_isRustAvailable) {
      try {
        final load = NativeFFI.instance.profilerGetCurrentLoad();
        final breakdown = NativeFFI.instance.profilerGetStageBreakdown();

        setState(() {
          _currentLoad = load;
          if (load > _peakLoad) _peakLoad = load;
          _stageBreakdown = breakdown;
        });
      } catch (e) {
        // FFI error - switch to simulation
        _isRustAvailable = false;
      }
    } else {
      // Simulation fallback
      _simulationTick++;
      final simLoad = 12.0 +
          ((_simulationTick % 50) * 0.2) +
          ((_simulationTick ~/ 10) % 5) * 2.0;

      setState(() {
        _currentLoad = simLoad.clamp(0.0, 100.0);
        if (_currentLoad > _peakLoad) _peakLoad = _currentLoad;
        _stageBreakdown = {
          'input': simLoad * 0.1,
          'mixing': simLoad * 0.3,
          'effects': simLoad * 0.35,
          'metering': simLoad * 0.15,
          'output': simLoad * 0.1,
        };
      });
    }
  }

  Color _getLoadColor(double load) {
    if (load >= 90) return FluxForgeTheme.accentRed;
    if (load >= 70) return FluxForgeTheme.accentOrange;
    if (load >= 50) return FluxForgeTheme.accentYellow;
    return FluxForgeTheme.accentGreen;
  }

  String _getHealthStatus(double load) {
    if (load >= 90) return 'Critical';
    if (load >= 70) return 'Warning';
    if (load >= 50) return 'Elevated';
    return 'Healthy';
  }

  @override
  Widget build(BuildContext context) {
    final color = _getLoadColor(_currentLoad);

    return Tooltip(
      message: _buildTooltipText(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: color.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // CPU icon
            Icon(
              Icons.memory,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 6),

            // Meter bar
            if (widget.showMeter) ...[
              SizedBox(
                width: 40,
                height: 8,
                child: _buildMeterBar(color),
              ),
              const SizedBox(width: 6),
            ],

            // Percentage
            if (widget.showPercentage)
              Text(
                '${_currentLoad.toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeterBar(Color color) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        borderRadius: BorderRadius.circular(2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth * (_currentLoad / 100).clamp(0.0, 1.0);
          return Stack(
            children: [
              // Peak indicator
              if (_peakLoad > 0)
                Positioned(
                  left: (constraints.maxWidth * (_peakLoad / 100).clamp(0.0, 1.0)) - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    color: color.withValues(alpha: 0.5),
                  ),
                ),
              // Current load bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: width,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.7),
                      color,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _buildTooltipText() {
    final lines = <String>[
      'DSP Load: ${_currentLoad.toStringAsFixed(1)}%',
      'Peak: ${_peakLoad.toStringAsFixed(1)}%',
      'Status: ${_getHealthStatus(_currentLoad)}',
      '',
      'Stage Breakdown:',
    ];

    for (final entry in _stageBreakdown.entries) {
      final stageName = entry.key[0].toUpperCase() + entry.key.substring(1);
      lines.add('  $stageName: ${entry.value.toStringAsFixed(1)}%');
    }

    if (!_isRustAvailable) {
      lines.add('');
      lines.add('(Simulated - FFI not connected)');
    }

    return lines.join('\n');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DSP LOAD INLINE STATS — Text-Only for Tight Spaces
// ═══════════════════════════════════════════════════════════════════════════════

class DspLoadInlineStats extends StatefulWidget {
  final Duration refreshInterval;

  const DspLoadInlineStats({
    super.key,
    this.refreshInterval = const Duration(milliseconds: 200),
  });

  @override
  State<DspLoadInlineStats> createState() => _DspLoadInlineStatsState();
}

class _DspLoadInlineStatsState extends State<DspLoadInlineStats> {
  double _currentLoad = 0.0;
  Timer? _updateTimer;
  bool _isRustAvailable = false;
  int _simulationTick = 0;

  @override
  void initState() {
    super.initState();
    _checkRustFFI();
    _updateTimer = Timer.periodic(widget.refreshInterval, (_) => _updateLoad());
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _checkRustFFI() {
    try {
      NativeFFI.instance.profilerGetCurrentLoad();
      _isRustAvailable = true;
    } catch (e) {
      _isRustAvailable = false;
    }
  }

  void _updateLoad() {
    if (!mounted) return;

    if (_isRustAvailable) {
      try {
        final load = NativeFFI.instance.profilerGetCurrentLoad();
        setState(() => _currentLoad = load);
      } catch (e) {
        _isRustAvailable = false;
      }
    } else {
      _simulationTick++;
      final simLoad = 12.0 + ((_simulationTick % 50) * 0.2);
      setState(() => _currentLoad = simLoad.clamp(0.0, 100.0));
    }
  }

  Color _getLoadColor(double load) {
    if (load >= 90) return FluxForgeTheme.accentRed;
    if (load >= 70) return FluxForgeTheme.accentOrange;
    if (load >= 50) return FluxForgeTheme.accentYellow;
    return FluxForgeTheme.accentGreen;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getLoadColor(_currentLoad);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'DSP: ${_currentLoad.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DSP LOAD MICRO BADGE — Minimal Version for Cramped Spaces
// ═══════════════════════════════════════════════════════════════════════════════

class DspLoadMicroBadge extends StatefulWidget {
  final Duration refreshInterval;

  const DspLoadMicroBadge({
    super.key,
    this.refreshInterval = const Duration(milliseconds: 200),
  });

  @override
  State<DspLoadMicroBadge> createState() => _DspLoadMicroBadgeState();
}

class _DspLoadMicroBadgeState extends State<DspLoadMicroBadge> {
  double _currentLoad = 0.0;
  Timer? _updateTimer;
  bool _isRustAvailable = false;
  int _simulationTick = 0;

  @override
  void initState() {
    super.initState();
    _checkRustFFI();
    _updateTimer = Timer.periodic(widget.refreshInterval, (_) => _updateLoad());
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _checkRustFFI() {
    try {
      NativeFFI.instance.profilerGetCurrentLoad();
      _isRustAvailable = true;
    } catch (e) {
      _isRustAvailable = false;
    }
  }

  void _updateLoad() {
    if (!mounted) return;

    if (_isRustAvailable) {
      try {
        final load = NativeFFI.instance.profilerGetCurrentLoad();
        setState(() => _currentLoad = load);
      } catch (e) {
        _isRustAvailable = false;
      }
    } else {
      _simulationTick++;
      final simLoad = 12.0 + ((_simulationTick % 50) * 0.2);
      setState(() => _currentLoad = simLoad.clamp(0.0, 100.0));
    }
  }

  Color _getLoadColor(double load) {
    if (load >= 90) return FluxForgeTheme.accentRed;
    if (load >= 70) return FluxForgeTheme.accentOrange;
    if (load >= 50) return FluxForgeTheme.accentYellow;
    return FluxForgeTheme.accentGreen;
  }

  @override
  Widget build(BuildContext context) {
    final color = _getLoadColor(_currentLoad);

    return Tooltip(
      message: 'DSP Load: ${_currentLoad.toStringAsFixed(1)}%',
      child: Container(
        width: 24,
        height: 12,
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth * (_currentLoad / 100).clamp(0.0, 1.0);
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: width,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
