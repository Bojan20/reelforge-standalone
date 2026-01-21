/// Bus Meters Panel — Live Audio Level Visualization
///
/// Real-time audio bus meters for SlotLab:
/// - Per-bus level meters (SFX, Music, Voice, Ambience, Master)
/// - Peak hold indicators
/// - Clip indicators
/// - RMS and Peak modes
/// - Stereo L/R meters for master
///
/// Based on SLOTLAB_AUTO_EVENT_BUILDER_FINAL.md Section 15.6
///
/// Connected to MeterProvider for real-time FFI metering data.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/meter_provider.dart';
import '../../../theme/fluxforge_theme.dart';

/// Bus configuration
class BusConfig {
  final String id;
  final String name;
  final String shortName;
  final IconData icon;
  final Color color;
  final bool isStereo;

  const BusConfig({
    required this.id,
    required this.name,
    required this.shortName,
    required this.icon,
    required this.color,
    this.isStereo = false,
  });
}

/// Standard bus configurations
class StandardBuses {
  static const sfx = BusConfig(
    id: 'sfx',
    name: 'Sound Effects',
    shortName: 'SFX',
    icon: Icons.surround_sound,
    color: Color(0xFF4A9EFF),
  );

  static const music = BusConfig(
    id: 'music',
    name: 'Music',
    shortName: 'MUS',
    icon: Icons.music_note,
    color: Color(0xFFFF9040),
  );

  static const voice = BusConfig(
    id: 'voice',
    name: 'Voice',
    shortName: 'VO',
    icon: Icons.mic,
    color: Color(0xFF40FF90),
  );

  static const ambience = BusConfig(
    id: 'ambience',
    name: 'Ambience',
    shortName: 'AMB',
    icon: Icons.waves,
    color: Color(0xFF40C8FF),
  );

  static const master = BusConfig(
    id: 'master',
    name: 'Master',
    shortName: 'MST',
    icon: Icons.speaker,
    color: Color(0xFFE0E0E0),
    isStereo: true,
  );

  static const all = [sfx, music, voice, ambience, master];
}

class BusMetersPanel extends StatefulWidget {
  const BusMetersPanel({super.key});

  @override
  State<BusMetersPanel> createState() => _BusMetersPanelState();
}

class _BusMetersPanelState extends State<BusMetersPanel> {
  final Map<String, _MeterState> _localStates = {};
  bool _showPeakHold = true;
  bool _showRms = true;

  // Bus index mapping: sfx=0, music=1, voice=2, ambience=3, aux=4, master=5
  static const _busIndexMap = {
    'sfx': 0,
    'music': 1,
    'voice': 2,
    'ambience': 3,
    'master': 5,
  };

  @override
  void initState() {
    super.initState();
    // Initialize local state for peak hold tracking
    for (final bus in StandardBuses.all) {
      _localStates[bus.id] = _MeterState();
      if (bus.isStereo) {
        _localStates['${bus.id}_r'] = _MeterState();
      }
    }
  }

  /// Convert MeterProvider data to local _MeterState for visualization
  void _syncFromProvider(MeterProvider provider) {
    for (final bus in StandardBuses.all) {
      final busIndex = _busIndexMap[bus.id] ?? 0;
      final providerState = provider.getBusState(busIndex);

      // Update local state with provider values
      final localState = _localStates[bus.id]!;
      localState.updateFromProvider(
        providerState.peak,
        providerState.rms,
        providerState.peakHold,
      );

      if (bus.isStereo) {
        final localStateR = _localStates['${bus.id}_r']!;
        localStateR.updateFromProvider(
          providerState.peakR,
          providerState.rmsR,
          providerState.peakHoldR,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Try to get MeterProvider, fall back to static meters if not available
    MeterProvider? meterProvider;
    try {
      meterProvider = context.watch<MeterProvider>();
      _syncFromProvider(meterProvider);
    } catch (_) {
      // MeterProvider not available in this context
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          _Header(
            showPeakHold: _showPeakHold,
            showRms: _showRms,
            onTogglePeakHold: () => setState(() => _showPeakHold = !_showPeakHold),
            onToggleRms: () => setState(() => _showRms = !_showRms),
            onResetPeaks: _resetPeaks,
            isConnected: meterProvider != null,
          ),

          const SizedBox(height: 12),

          // Meters
          Expanded(
            child: Row(
              children: [
                // Bus meters
                for (final bus in StandardBuses.all.where((b) => !b.isStereo)) ...[
                  Expanded(
                    child: _BusMeter(
                      config: bus,
                      state: _localStates[bus.id]!,
                      showPeakHold: _showPeakHold,
                      showRms: _showRms,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Separator before master
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: FluxForgeTheme.borderSubtle,
                ),

                // Master stereo meters
                Expanded(
                  flex: 2,
                  child: _StereoMeter(
                    config: StandardBuses.master,
                    leftState: _localStates['master']!,
                    rightState: _localStates['master_r']!,
                    showPeakHold: _showPeakHold,
                    showRms: _showRms,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _resetPeaks() {
    setState(() {
      for (final state in _localStates.values) {
        state.resetPeak();
      }
    });
  }
}

// =============================================================================
// METER STATE
// =============================================================================

class _MeterState {
  double level = 0.0;
  double rms = 0.0;
  double peak = 0.0;
  double peakHold = 0.0;
  int peakHoldFrames = 0;
  bool isClipping = false;

  static const peakHoldDuration = 60; // frames (~1 second at 60fps)
  static const peakDecay = 0.002;
  static const levelSmoothing = 0.3;
  static const rmsSmoothing = 0.1;

  /// Update from MeterProvider values (already normalized 0-1)
  void updateFromProvider(double newPeak, double newRms, double newPeakHold) {
    // Smooth the incoming values
    level = level + (newPeak - level) * levelSmoothing;
    rms = rms + (newRms - rms) * rmsSmoothing;
    peak = newPeak;
    peakHold = newPeakHold;

    // Check clipping (provider values are normalized 0-1)
    isClipping = newPeak > 0.95;
  }

  /// Update with simulated value (fallback when no provider)
  void update(double newLevel) {
    // Smooth level
    level = level + (newLevel - level) * levelSmoothing;

    // Calculate RMS (simplified)
    rms = rms + (newLevel * newLevel - rms) * rmsSmoothing;

    // Update peak
    if (newLevel > peak) {
      peak = newLevel;
    } else {
      peak = math.max(0, peak - peakDecay);
    }

    // Update peak hold
    if (newLevel > peakHold) {
      peakHold = newLevel;
      peakHoldFrames = 0;
    } else {
      peakHoldFrames++;
      if (peakHoldFrames > peakHoldDuration) {
        peakHold = math.max(0, peakHold - peakDecay * 2);
      }
    }

    // Check clipping
    isClipping = newLevel > 0.95;
  }

  void resetPeak() {
    peakHold = 0.0;
    peakHoldFrames = 0;
  }

  double get rmsLevel => math.sqrt(rms);
}

// =============================================================================
// HEADER
// =============================================================================

class _Header extends StatelessWidget {
  final bool showPeakHold;
  final bool showRms;
  final VoidCallback onTogglePeakHold;
  final VoidCallback onToggleRms;
  final VoidCallback onResetPeaks;
  final bool isConnected;

  const _Header({
    required this.showPeakHold,
    required this.showRms,
    required this.onTogglePeakHold,
    required this.onToggleRms,
    required this.onResetPeaks,
    this.isConnected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.equalizer,
          size: 16,
          color: FluxForgeTheme.accentGreen.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 8),
        Text(
          'Bus Meters',
          style: TextStyle(
            color: FluxForgeTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),

        // Connection indicator
        const SizedBox(width: 8),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isConnected ? FluxForgeTheme.accentGreen : FluxForgeTheme.textMuted,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          isConnected ? 'LIVE' : 'OFFLINE',
          style: TextStyle(
            color: isConnected ? FluxForgeTheme.accentGreen : FluxForgeTheme.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),

        const Spacer(),

        // Toggle buttons
        _ToggleChip(
          label: 'Peak Hold',
          isActive: showPeakHold,
          onTap: onTogglePeakHold,
        ),
        const SizedBox(width: 6),
        _ToggleChip(
          label: 'RMS',
          isActive: showRms,
          onTap: onToggleRms,
        ),
        const SizedBox(width: 12),

        // Reset peaks
        Tooltip(
          message: 'Reset peak hold',
          child: InkWell(
            onTap: onResetPeaks,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxForgeTheme.bgDeep,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: FluxForgeTheme.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 12, color: FluxForgeTheme.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Reset',
                    style: TextStyle(
                      color: FluxForgeTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2)
              : FluxForgeTheme.bgDeep,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? FluxForgeTheme.accentBlue.withValues(alpha: 0.5)
                : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textMuted,
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// BUS METER
// =============================================================================

class _BusMeter extends StatelessWidget {
  final BusConfig config;
  final _MeterState state;
  final bool showPeakHold;
  final bool showRms;

  const _BusMeter({
    required this.config,
    required this.state,
    required this.showPeakHold,
    required this.showRms,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Bus icon
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: config.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(config.icon, size: 14, color: config.color.withValues(alpha: 0.8)),
        ),

        const SizedBox(height: 8),

        // Meter bar
        Expanded(
          child: _MeterBar(
            level: state.level,
            rmsLevel: showRms ? state.rmsLevel : null,
            peakHold: showPeakHold ? state.peakHold : null,
            isClipping: state.isClipping,
            color: config.color,
          ),
        ),

        const SizedBox(height: 8),

        // Label
        Text(
          config.shortName,
          style: TextStyle(
            color: FluxForgeTheme.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// STEREO METER
// =============================================================================

class _StereoMeter extends StatelessWidget {
  final BusConfig config;
  final _MeterState leftState;
  final _MeterState rightState;
  final bool showPeakHold;
  final bool showRms;

  const _StereoMeter({
    required this.config,
    required this.leftState,
    required this.rightState,
    required this.showPeakHold,
    required this.showRms,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Master icon
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: config.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(config.icon, size: 14, color: config.color.withValues(alpha: 0.8)),
            ),
            const SizedBox(width: 8),
            Text(
              'MASTER',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // Stereo meters
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Left meter
              SizedBox(
                width: 20,
                child: _MeterBar(
                  level: leftState.level,
                  rmsLevel: showRms ? leftState.rmsLevel : null,
                  peakHold: showPeakHold ? leftState.peakHold : null,
                  isClipping: leftState.isClipping,
                  color: config.color,
                ),
              ),
              const SizedBox(width: 4),
              // Right meter
              SizedBox(
                width: 20,
                child: _MeterBar(
                  level: rightState.level,
                  rmsLevel: showRms ? rightState.rmsLevel : null,
                  peakHold: showPeakHold ? rightState.peakHold : null,
                  isClipping: rightState.isClipping,
                  color: config.color,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // L/R labels
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('L', style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 9)),
            const SizedBox(width: 16),
            Text('R', style: TextStyle(color: FluxForgeTheme.textMuted, fontSize: 9)),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// METER BAR
// =============================================================================

class _MeterBar extends StatelessWidget {
  final double level;
  final double? rmsLevel;
  final double? peakHold;
  final bool isClipping;
  final Color color;

  const _MeterBar({
    required this.level,
    this.rmsLevel,
    this.peakHold,
    required this.isClipping,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: isClipping
                  ? FluxForgeTheme.accentRed
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // dB scale (background)
              Positioned.fill(
                child: CustomPaint(
                  painter: _DbScalePainter(),
                ),
              ),

              // RMS level (darker)
              if (rmsLevel != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: height * rmsLevel!.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.3),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(1)),
                    ),
                  ),
                ),

              // Peak level (brighter)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: height * level.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        color.withValues(alpha: 0.9),
                        color.withValues(alpha: 0.7),
                        _getTopColor(level),
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(1)),
                  ),
                ),
              ),

              // Peak hold indicator
              if (peakHold != null && peakHold! > 0.01)
                Positioned(
                  bottom: height * peakHold!.clamp(0.0, 1.0) - 2,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 2,
                    color: peakHold! > 0.95 ? FluxForgeTheme.accentRed : color,
                  ),
                ),

              // Clip indicator
              if (isClipping)
                Positioned(
                  top: 2,
                  left: 2,
                  right: 2,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentRed,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Color _getTopColor(double level) {
    if (level > 0.95) return FluxForgeTheme.accentRed;
    if (level > 0.8) return const Color(0xFFFFFF40); // Yellow
    return color.withValues(alpha: 0.5);
  }
}

class _DbScalePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1;

    // Draw scale lines at 0dB, -6dB, -12dB, -18dB, -24dB
    final positions = [0.0, 0.25, 0.5, 0.75, 1.0];
    for (final pos in positions) {
      final y = size.height * (1 - pos);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
