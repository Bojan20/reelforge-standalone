/// Mini Mixer Panel (P3.5) — Condensed mixer view
///
/// Ultra-compact mixer showing only:
/// - Narrow channel strips (40px vs 80px normal)
/// - Volume faders
/// - Peak meters
/// - Mute/Solo buttons
///
/// No inserts, sends, or input section visible.
/// Useful for quick level monitoring in limited screen space.
///
/// Created: 2026-01-29
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../theme/fluxforge_theme.dart';
import '../../../../providers/mixer_provider.dart';
import '../../../../utils/audio_math.dart';

/// Mini mixer strip width
const double kMiniStripWidth = 40.0;

/// Mini meter height
const double kMiniMeterHeight = 100.0;

/// Mini fader height
const double kMiniFaderHeight = 80.0;

/// Mini Mixer Panel - Ultra-compact view
class MiniMixerPanel extends StatefulWidget {
  /// Show master bus
  final bool showMaster;

  /// Show buses section
  final bool showBuses;

  /// Callback when full mixer is requested
  final VoidCallback? onExpandRequested;

  const MiniMixerPanel({
    super.key,
    this.showMaster = true,
    this.showBuses = true,
    this.onExpandRequested,
  });

  @override
  State<MiniMixerPanel> createState() => _MiniMixerPanelState();
}

class _MiniMixerPanelState extends State<MiniMixerPanel> {
  Timer? _meterTimer;

  @override
  void initState() {
    super.initState();
    // Update meters at 30fps
    _meterTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MixerProvider mixerProvider;
    try {
      mixerProvider = context.watch<MixerProvider>();
    } catch (_) {
      return _buildNoProviderPanel();
    }

    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeepest,
        border: Border.all(color: FluxForgeTheme.borderSubtle),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Mixer strips
          Expanded(
            child: Row(
              children: [
                // Audio channels
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: mixerProvider.channels.length,
                    itemBuilder: (context, index) {
                      final channel = mixerProvider.channels[index];
                      return _MiniChannelStrip(
                        id: channel.id,
                        name: channel.name,
                        color: channel.color,
                        volume: channel.volume,
                        muted: channel.muted,
                        soloed: channel.soloed,
                        peakL: channel.peakL,
                        peakR: channel.peakR,
                        onVolumeChange: (v) => mixerProvider.setChannelVolumeWithUndo(channel.id, v),
                        onMuteToggle: () => mixerProvider.toggleChannelMuteWithUndo(channel.id),
                        onSoloToggle: () => mixerProvider.toggleChannelSoloWithUndo(channel.id),
                      );
                    },
                  ),
                ),

                // Separator
                if (widget.showBuses && mixerProvider.buses.isNotEmpty) ...[
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    color: FluxForgeTheme.borderSubtle,
                  ),

                  // Buses
                  ...mixerProvider.buses.map((bus) => _MiniChannelStrip(
                    id: bus.id,
                    name: bus.name,
                    color: bus.color.withAlpha(200),
                    volume: bus.volume,
                    muted: bus.muted,
                    soloed: bus.soloed,
                    peakL: bus.peakL,
                    peakR: bus.peakR,
                    onVolumeChange: (v) => mixerProvider.setChannelVolumeWithUndo(bus.id, v),
                    onMuteToggle: () => mixerProvider.toggleChannelMuteWithUndo(bus.id),
                    onSoloToggle: () => mixerProvider.toggleChannelSoloWithUndo(bus.id),
                    isBus: true,
                  )),
                ],

                // Master separator
                if (widget.showMaster) ...[
                  Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: FluxForgeTheme.accentOrange.withAlpha(100),
                  ),

                  // Master
                  _MiniChannelStrip(
                    id: mixerProvider.master.id,
                    name: 'M',
                    color: FluxForgeTheme.accentOrange,
                    volume: mixerProvider.master.volume,
                    muted: mixerProvider.master.muted,
                    soloed: false,
                    peakL: mixerProvider.master.peakL,
                    peakR: mixerProvider.master.peakR,
                    onVolumeChange: (v) => mixerProvider.setMasterVolumeWithUndo(v),
                    onMuteToggle: () => mixerProvider.toggleChannelMuteWithUndo(mixerProvider.master.id),
                    isMaster: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.tune,
            size: 12,
            color: FluxForgeTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            'MINI MIXER',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),

          // Expand button
          if (widget.onExpandRequested != null)
            InkWell(
              onTap: widget.onExpandRequested,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Text(
                      'FULL',
                      style: TextStyle(
                        fontSize: 8,
                        color: FluxForgeTheme.accentBlue,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.open_in_full,
                      size: 10,
                      color: FluxForgeTheme.accentBlue,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNoProviderPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          'MixerProvider not available',
          style: TextStyle(
            fontSize: 11,
            color: FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Mini channel strip - fader + meter only
class _MiniChannelStrip extends StatelessWidget {
  final String id;
  final String name;
  final Color color;
  final double volume;
  final bool muted;
  final bool soloed;
  final double peakL;
  final double peakR;
  final ValueChanged<double> onVolumeChange;
  final VoidCallback onMuteToggle;
  final VoidCallback? onSoloToggle;
  final bool isBus;
  final bool isMaster;

  const _MiniChannelStrip({
    required this.id,
    required this.name,
    required this.color,
    required this.volume,
    required this.muted,
    required this.soloed,
    required this.peakL,
    required this.peakR,
    required this.onVolumeChange,
    required this.onMuteToggle,
    this.onSoloToggle,
    this.isBus = false,
    this.isMaster = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kMiniStripWidth,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: FluxForgeTheme.borderSubtle.withAlpha(50)),
        ),
      ),
      child: Column(
        children: [
          // Track color indicator
          Container(
            height: 3,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: muted ? Colors.grey : color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),

          // Channel name
          Container(
            height: 14,
            alignment: Alignment.center,
            child: Text(
              name.length > 4 ? name.substring(0, 4) : name,
              style: TextStyle(
                fontSize: 8,
                fontWeight: isMaster ? FontWeight.bold : FontWeight.normal,
                color: muted
                    ? FluxForgeTheme.textSecondary.withAlpha(100)
                    : FluxForgeTheme.textPrimary,
              ),
              overflow: TextOverflow.clip,
            ),
          ),

          const SizedBox(height: 4),

          // Meter + Fader row
          Expanded(
            child: Row(
              children: [
                // Meter (left side)
                _MiniMeter(
                  peakL: peakL,
                  peakR: peakR,
                  muted: muted,
                  color: color,
                ),

                const SizedBox(width: 2),

                // Fader (right side)
                Expanded(
                  child: _MiniFader(
                    value: volume,
                    muted: muted,
                    onChanged: onVolumeChange,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // M/S buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MiniButton(
                label: 'M',
                isActive: muted,
                activeColor: Colors.red,
                onTap: onMuteToggle,
              ),
              const SizedBox(width: 2),
              if (!isMaster)
                _MiniButton(
                  label: 'S',
                  isActive: soloed,
                  activeColor: Colors.amber,
                  onTap: onSoloToggle,
                ),
            ],
          ),

          const SizedBox(height: 2),

          // dB value
          Text(
            _volumeToDb(volume),
            style: TextStyle(
              fontSize: 7,
              fontFamily: 'monospace',
              color: muted
                  ? FluxForgeTheme.textSecondary.withAlpha(100)
                  : FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _volumeToDb(double vol) => FaderCurve.linearToDbString(vol);
}

/// Mini peak meter
class _MiniMeter extends StatelessWidget {
  final double peakL;
  final double peakR;
  final bool muted;
  final Color color;

  const _MiniMeter({
    required this.peakL,
    required this.peakR,
    required this.muted,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      child: Row(
        children: [
          // Left channel
          Expanded(child: _buildBar(peakL)),
          const SizedBox(width: 1),
          // Right channel
          Expanded(child: _buildBar(peakR)),
        ],
      ),
    );
  }

  Widget _buildBar(double peak) {
    final level = muted ? 0.0 : peak.clamp(0.0, 1.0);
    final isClipping = peak > 0.95;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final fillHeight = height * level;

        return Container(
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeepest,
            borderRadius: BorderRadius.circular(1),
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Fill
              Container(
                height: fillHeight,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      FluxForgeTheme.accentGreen,
                      level > 0.7
                          ? (isClipping ? Colors.red : Colors.amber)
                          : FluxForgeTheme.accentGreen,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Mini vertical fader
class _MiniFader extends StatelessWidget {
  final double value;
  final bool muted;
  final ValueChanged<double> onChanged;

  const _MiniFader({
    required this.value,
    required this.muted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final faderPos = FaderCurve.linearToPosition(value);
        final thumbPosition = height * (1 - faderPos);

        return GestureDetector(
          onVerticalDragUpdate: (details) {
            final pos = 1.0 - (details.localPosition.dy / height).clamp(0.0, 1.0);
            final newValue = FaderCurve.positionToLinear(pos);
            onChanged(newValue);
          },
          child: Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgMid,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Stack(
              children: [
                // Track
                Positioned(
                  left: 6,
                  right: 6,
                  top: 4,
                  bottom: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.bgDeepest,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),

                // Unity gain marker (0 dB)
                Positioned(
                  left: 4,
                  right: 4,
                  top: height * (1 - FaderCurve.linearToPosition(1.0)) - 0.5,
                  child: Container(
                    height: 1,
                    color: FluxForgeTheme.textSecondary.withAlpha(50),
                  ),
                ),

                // Thumb
                Positioned(
                  left: 2,
                  right: 2,
                  top: thumbPosition - 4,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: muted
                          ? FluxForgeTheme.textSecondary.withAlpha(100)
                          : FluxForgeTheme.accentBlue,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(80),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Mini mute/solo button
class _MiniButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _MiniButton({
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: isActive ? activeColor : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isActive ? activeColor : FluxForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : FluxForgeTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
