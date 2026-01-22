/// Real-Time Bus Meters Widget
///
/// P1.4: Professional bus metering with FFI integration.
/// Zero-latency push model from SharedMeterReader.
///
/// Features:
/// - 60fps smooth animation via vsync ticker
/// - Peak hold with configurable decay
/// - RMS + Peak display per channel
/// - Gradient coloring with clip indicators
/// - dB scale markings
/// - Bus labels with solo/mute indicators

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../services/shared_meter_reader.dart';
import 'lower_zone_types.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

/// Peak hold time before decay starts (ms)
const int kPeakHoldMs = 1500;

/// Peak decay rate (units per frame at 60fps)
const double kPeakDecayRate = 0.02;

/// Meter refresh rate (target 60fps)
const Duration kMeterRefreshInterval = Duration(milliseconds: 16);

/// Bus configuration
class BusConfig {
  final String name;
  final int channelIndex; // Index into SharedMeterSnapshot.channelPeaks
  final Color color;
  final bool isMaster;

  const BusConfig({
    required this.name,
    required this.channelIndex,
    required this.color,
    this.isMaster = false,
  });
}

/// Default bus layout for SlotLab (6 buses)
const List<BusConfig> kSlotLabBuses = [
  BusConfig(name: 'SFX', channelIndex: 0, color: LowerZoneColors.slotLabAccent),
  BusConfig(name: 'Music', channelIndex: 1, color: Color(0xFF40FF90)),
  BusConfig(name: 'Voice', channelIndex: 2, color: Color(0xFFFFD040)),
  BusConfig(name: 'Ambient', channelIndex: 3, color: Color(0xFF9060FF)),
  BusConfig(name: 'Aux', channelIndex: 4, color: Color(0xFFFF6090)),
  BusConfig(name: 'Master', channelIndex: 5, color: Color(0xFFFFFFFF), isMaster: true),
];

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Real-time bus meters with FFI integration
class RealTimeBusMeters extends StatefulWidget {
  /// Bus configurations to display
  final List<BusConfig> buses;

  /// Accent color for UI elements
  final Color accentColor;

  /// Whether to show dB scale on left
  final bool showScale;

  /// Whether to show peak hold indicators
  final bool showPeakHold;

  /// Whether to show RMS level (inner bar)
  final bool showRms;

  /// Callback when a bus is tapped (for solo/mute)
  final void Function(int busIndex)? onBusTap;

  const RealTimeBusMeters({
    super.key,
    this.buses = kSlotLabBuses,
    this.accentColor = LowerZoneColors.slotLabAccent,
    this.showScale = true,
    this.showPeakHold = true,
    this.showRms = true,
    this.onBusTap,
  });

  @override
  State<RealTimeBusMeters> createState() => _RealTimeBusMetersState();
}

class _RealTimeBusMetersState extends State<RealTimeBusMeters>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  SharedMeterSnapshot _snapshot = SharedMeterSnapshot.empty;
  bool _initialized = false;
  String? _error;

  // Peak hold state per channel (index * 2 + L/R)
  final Map<int, double> _peakHold = {};
  final Map<int, int> _peakHoldTime = {};

  @override
  void initState() {
    super.initState();
    _initializeMetering();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _initializeMetering() async {
    try {
      final success = await SharedMeterReader.instance.initialize();
      if (mounted) {
        setState(() {
          _initialized = success;
          _error = success ? null : 'FFI metering not available';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _initialized = false;
          _error = 'Failed to initialize: $e';
        });
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (!_initialized) return;

    // Only update if data changed
    if (SharedMeterReader.instance.hasChanged) {
      final newSnapshot = SharedMeterReader.instance.readMeters();

      // Update peak hold
      if (widget.showPeakHold) {
        _updatePeakHold(newSnapshot);
      }

      setState(() {
        _snapshot = newSnapshot;
      });
    } else {
      // Still decay peak hold even without new data
      if (widget.showPeakHold && _decayPeakHold()) {
        setState(() {});
      }
    }
  }

  void _updatePeakHold(SharedMeterSnapshot snapshot) {
    final now = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < snapshot.channelPeaks.length; i++) {
      final level = snapshot.channelPeaks[i];
      final currentPeak = _peakHold[i] ?? 0.0;

      if (level >= currentPeak) {
        _peakHold[i] = level;
        _peakHoldTime[i] = now;
      }
    }
  }

  bool _decayPeakHold() {
    final now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;

    for (final entry in _peakHold.entries.toList()) {
      final holdTime = _peakHoldTime[entry.key] ?? 0;
      if (now - holdTime > kPeakHoldMs) {
        final newPeak = entry.value - kPeakDecayRate;
        if (newPeak > 0) {
          _peakHold[entry.key] = newPeak;
          changed = true;
        } else {
          _peakHold.remove(entry.key);
          _peakHoldTime.remove(entry.key);
          changed = true;
        }
      }
    }

    return changed;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: _error != null
                ? _buildErrorState()
                : _buildMetersRow(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.bar_chart, size: 16, color: widget.accentColor),
        const SizedBox(width: 8),
        Text(
          'BUS METERS',
          style: TextStyle(
            fontSize: LowerZoneTypography.sizeLabel,
            fontWeight: FontWeight.bold,
            color: widget.accentColor,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        // Status indicator
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _initialized ? LowerZoneColors.success : LowerZoneColors.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          _initialized ? 'LIVE' : 'OFFLINE',
          style: TextStyle(
            fontSize: LowerZoneTypography.sizeTiny,
            color: _initialized ? LowerZoneColors.success : LowerZoneColors.error,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        // LUFS display
        if (_initialized && _snapshot.lufsShort > -60)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: LowerZoneColors.bgDeepest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: LowerZoneColors.border),
            ),
            child: Text(
              '${_snapshot.lufsShort.toStringAsFixed(1)} LUFS',
              style: TextStyle(
                fontSize: LowerZoneTypography.sizeBadge,
                color: _snapshot.lufsShort > -14
                    ? LowerZoneColors.warning
                    : LowerZoneColors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorState() {
    return LowerZoneEmptyState(
      title: 'Metering Unavailable',
      subtitle: _error,
      icon: Icons.bar_chart,
      accentColor: widget.accentColor,
      actionLabel: 'Retry',
      onAction: _initializeMetering,
    );
  }

  Widget _buildMetersRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // dB scale on left
        if (widget.showScale)
          SizedBox(
            width: 24,
            child: _buildDbScale(),
          ),
        // Bus meters
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int i = 0; i < widget.buses.length; i++)
                Expanded(
                  flex: widget.buses[i].isMaster ? 2 : 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _buildBusMeter(widget.buses[i]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDbScale() {
    const marks = [0, -6, -12, -18, -24, -36, -48, -60];
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return Stack(
          children: [
            for (final db in marks)
              Positioned(
                top: _dbToPosition(db.toDouble(), height) - 6,
                left: 0,
                right: 0,
                child: Text(
                  '$db',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 8,
                    color: db == 0
                        ? LowerZoneColors.error
                        : LowerZoneColors.textMuted,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBusMeter(BusConfig bus) {
    // Get L/R peaks for this bus (channelIndex * 2 for L, +1 for R)
    final leftIndex = bus.channelIndex * 2;
    final rightIndex = leftIndex + 1;

    double leftPeak = 0;
    double rightPeak = 0;
    double leftRms = 0;
    double rightRms = 0;

    if (_initialized && leftIndex < _snapshot.channelPeaks.length) {
      leftPeak = _snapshot.channelPeaks[leftIndex];
      rightPeak = rightIndex < _snapshot.channelPeaks.length
          ? _snapshot.channelPeaks[rightIndex]
          : leftPeak;

      // For master, use masterRms values
      if (bus.isMaster) {
        leftRms = _snapshot.masterRmsL;
        rightRms = _snapshot.masterRmsR;
      } else {
        // Estimate RMS as peak * 0.7 for non-master (approximation)
        leftRms = leftPeak * 0.7;
        rightRms = rightPeak * 0.7;
      }
    }

    final leftPeakHold = _peakHold[leftIndex] ?? 0.0;
    final rightPeakHold = _peakHold[rightIndex] ?? 0.0;

    return GestureDetector(
      onTap: widget.onBusTap != null
          ? () => widget.onBusTap!(bus.channelIndex)
          : null,
      child: Column(
        children: [
          // Stereo meter bars
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildMeterBar(
                  peak: leftPeak,
                  rms: leftRms,
                  peakHold: leftPeakHold,
                  color: bus.color,
                  width: bus.isMaster ? 12 : 8,
                ),
                SizedBox(width: bus.isMaster ? 3 : 2),
                _buildMeterBar(
                  peak: rightPeak,
                  rms: rightRms,
                  peakHold: rightPeakHold,
                  color: bus.color,
                  width: bus.isMaster ? 12 : 8,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Peak readout
          Text(
            _formatDb(leftPeak > rightPeak ? leftPeak : rightPeak),
            style: TextStyle(
              fontSize: 8,
              color: (leftPeak > 0.9 || rightPeak > 0.9)
                  ? LowerZoneColors.error
                  : bus.color,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          // Bus name
          Text(
            bus.name,
            style: TextStyle(
              fontSize: LowerZoneTypography.sizeTiny,
              fontWeight: bus.isMaster ? FontWeight.bold : FontWeight.normal,
              color: bus.isMaster ? bus.color : LowerZoneColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeterBar({
    required double peak,
    required double rms,
    required double peakHold,
    required Color color,
    required double width,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;

        return Container(
          width: width,
          decoration: BoxDecoration(
            color: LowerZoneColors.bgDeepest,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Background gradient marks
              _buildMeterBackground(height),

              // RMS level (inner, darker)
              if (widget.showRms)
                _buildLevelBar(
                  level: rms,
                  height: height,
                  width: width * 0.5,
                  color: color.withValues(alpha: 0.4),
                ),

              // Peak level (outer)
              _buildLevelBar(
                level: peak,
                height: height,
                width: width,
                color: color,
                isGradient: true,
              ),

              // Peak hold indicator
              if (widget.showPeakHold && peakHold > 0.01)
                Positioned(
                  bottom: _levelToPosition(peakHold, height) - 1,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: peakHold > 0.9 ? LowerZoneColors.error : color,
                      boxShadow: [
                        BoxShadow(
                          color: (peakHold > 0.9 ? LowerZoneColors.error : color)
                              .withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),

              // Clip indicator at top
              if (peak >= 1.0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: LowerZoneColors.error,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMeterBackground(double height) {
    // Mark positions at -6, -12, -18 dB
    return Stack(
      children: [
        for (final db in [-6, -12, -18, -24])
          Positioned(
            bottom: _levelToPosition(_dbToLevel(db.toDouble()), height),
            left: 0,
            right: 0,
            child: Container(
              height: 1,
              color: LowerZoneColors.border.withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }

  Widget _buildLevelBar({
    required double level,
    required double height,
    required double width,
    required Color color,
    bool isGradient = false,
  }) {
    final barHeight = _levelToPosition(level, height);

    if (isGradient) {
      return Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          height: barHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                level > 0.9 ? LowerZoneColors.error : (level > 0.7 ? LowerZoneColors.warning : color),
                color.withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }

    return Positioned(
      bottom: 0,
      child: Container(
        width: width,
        height: barHeight,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  // Utility functions
  double _levelToPosition(double level, double height) {
    // Level is 0-1 linear, convert to visual position
    // Use log scale for more natural meter response
    if (level <= 0) return 0;
    final db = 20 * _log10(level);
    return _dbToPosition(db, height);
  }

  double _dbToPosition(double db, double height) {
    // Map -60 to 0 dB to 0 to height
    const minDb = -60.0;
    const maxDb = 0.0;
    final normalized = ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
    return normalized * height;
  }

  double _dbToLevel(double db) {
    // Convert dB to linear 0-1
    return _pow10(db / 20);
  }

  String _formatDb(double level) {
    if (level <= 0.001) return '-∞';
    final db = 20 * _log10(level);
    if (db >= -0.1) return '0.0';
    return db.toStringAsFixed(1);
  }

  // Math helpers (avoid importing dart:math for these simple ops)
  static double _log10(double x) => x > 0 ? _ln(x) / _ln(10) : -60;
  static double _pow10(double x) => _exp(x * _ln(10));
  static double _ln(double x) {
    // Natural log approximation
    if (x <= 0) return -100;
    double result = 0;
    double y = (x - 1) / (x + 1);
    double y2 = y * y;
    double term = y;
    for (int i = 1; i < 20; i += 2) {
      result += term / i;
      term *= y2;
    }
    return 2 * result;
  }
  static double _exp(double x) {
    // Exponential approximation
    double result = 1;
    double term = 1;
    for (int i = 1; i < 20; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }
}
