/// Glass Mixer Widget
///
/// Liquid Glass styled mixer that wraps ProDawMixer with glass effects.
/// Provides theme-aware rendering based on ThemeModeProvider.

import 'dart:math' show log, ln10, pow;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/liquid_glass_theme.dart';
import '../../providers/theme_mode_provider.dart';
import '../../providers/mixer_provider.dart' show MixerProvider, MixerChannel, ChannelType, VcaFader;
import '../mixer/pro_daw_mixer.dart';
import 'glass_widgets.dart';

/// Convert linear peak (0-1) to dB
double _peakToDb(double peak) {
  if (peak <= 0.0001) return -60;
  return 20 * log(peak) / ln10;
}

/// Theme-aware mixer that switches between Glass and Classic styles
class ThemeAwareMixer extends StatelessWidget {
  final bool compact;
  final VoidCallback? onAddBus;
  final VoidCallback? onAddAux;
  final VoidCallback? onAddVca;

  const ThemeAwareMixer({
    super.key,
    this.compact = false,
    this.onAddBus,
    this.onAddAux,
    this.onAddVca,
  });

  @override
  Widget build(BuildContext context) {
    final isGlassMode = context.watch<ThemeModeProvider>().isGlassMode;

    if (isGlassMode) {
      return GlassMixer(
        compact: compact,
        onAddBus: onAddBus,
        onAddAux: onAddAux,
        onAddVca: onAddVca,
      );
    }

    return ProDawMixer(
      compact: compact,
      onAddBus: onAddBus,
      onAddAux: onAddAux,
      onAddVca: onAddVca,
    );
  }
}

/// Glass-styled mixer with backdrop blur and glass effects
class GlassMixer extends StatefulWidget {
  final bool compact;
  final VoidCallback? onAddBus;
  final VoidCallback? onAddAux;
  final VoidCallback? onAddVca;

  const GlassMixer({
    super.key,
    this.compact = false,
    this.onAddBus,
    this.onAddAux,
    this.onAddVca,
  });

  @override
  State<GlassMixer> createState() => _GlassMixerState();
}

class _GlassMixerState extends State<GlassMixer> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MixerProvider>(
      builder: (context, mixer, child) {
        final stripWidth = widget.compact ? 60.0 : 80.0;

        return ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: LiquidGlassTheme.blurLight,
              sigmaY: LiquidGlassTheme.blurLight,
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Column(
                children: [
                  // Glass Toolbar
                  _buildGlassToolbar(context, mixer),

                  // Mixer strips with glass styling
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Channel strips
                          if (mixer.channels.isNotEmpty) ...[
                            _buildGlassSectionLabel('TRACKS'),
                            ...mixer.channels.map((ch) => RepaintBoundary(
                              key: ValueKey('glass_rb_${ch.id}'),
                              child: _GlassChannelStrip(
                                key: ValueKey('glass_${ch.id}'),
                                channel: ch,
                                width: stripWidth,
                                compact: widget.compact,
                                onVolumeChange: (v) => mixer.setChannelVolume(ch.id, v),
                                onPanChange: (p) => mixer.setChannelPan(ch.id, p),
                                onMuteToggle: () => mixer.toggleChannelMute(ch.id),
                                onSoloToggle: () => mixer.toggleChannelSolo(ch.id),
                                onArmToggle: () => mixer.toggleChannelArm(ch.id),
                                onOutputChange: (busId) => mixer.setChannelOutput(ch.id, busId),
                                availableBuses: mixer.buses.isEmpty ? null : mixer.buses,
                                hasSoloedChannels: mixer.hasSoloedChannels,
                              ),
                            )),
                            const _GlassSectionDivider(),
                          ],

                          // Aux returns
                          if (mixer.auxes.isNotEmpty) ...[
                            _buildGlassSectionLabel('AUX'),
                            ...mixer.auxes.map((aux) => RepaintBoundary(
                              key: ValueKey('glass_rb_${aux.id}'),
                              child: _GlassChannelStrip(
                                key: ValueKey('glass_${aux.id}'),
                                channel: aux,
                                width: stripWidth,
                                compact: widget.compact,
                                onVolumeChange: (v) => mixer.setChannelVolume(aux.id, v),
                                onPanChange: (p) => mixer.setChannelPan(aux.id, p),
                                onMuteToggle: () => mixer.toggleChannelMute(aux.id),
                                onSoloToggle: () => mixer.toggleChannelSolo(aux.id),
                                hasSoloedChannels: mixer.hasSoloedChannels,
                              ),
                            )),
                            const _GlassSectionDivider(),
                          ],

                          // Buses
                          if (mixer.buses.isNotEmpty) ...[
                            _buildGlassSectionLabel('BUSES'),
                            ...mixer.buses.map((bus) => RepaintBoundary(
                              key: ValueKey('glass_rb_${bus.id}'),
                              child: _GlassChannelStrip(
                                key: ValueKey('glass_${bus.id}'),
                                channel: bus,
                                width: stripWidth,
                                compact: widget.compact,
                                onVolumeChange: (v) => mixer.setChannelVolume(bus.id, v),
                                onPanChange: (p) => mixer.setChannelPan(bus.id, p),
                                onMuteToggle: () => mixer.toggleChannelMute(bus.id),
                                onSoloToggle: () => mixer.toggleChannelSolo(bus.id),
                                hasSoloedChannels: mixer.hasSoloedChannels,
                              ),
                            )),
                            const _GlassSectionDivider(),
                          ],

                          // VCAs
                          if (mixer.vcas.isNotEmpty) ...[
                            _buildGlassSectionLabel('VCA'),
                            ...mixer.vcas.map((vca) => RepaintBoundary(
                              key: ValueKey('glass_rb_${vca.id}'),
                              child: _GlassVcaStrip(
                                key: ValueKey('glass_${vca.id}'),
                                vca: vca,
                                width: stripWidth,
                                compact: widget.compact,
                                onLevelChange: (l) => mixer.setVcaLevel(vca.id, l),
                                onMuteToggle: () => mixer.toggleVcaMute(vca.id),
                              ),
                            )),
                            const _GlassSectionDivider(),
                          ],

                          // Master
                          _buildGlassSectionLabel('MASTER'),
                          _GlassMasterStrip(
                            master: mixer.master,
                            width: stripWidth + 20,
                            compact: widget.compact,
                            onVolumeChange: (v) => mixer.setMasterVolume(v),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassToolbar(BuildContext context, MixerProvider mixer) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // Add buttons
          GlassIconButton(
            icon: Icons.add,
            onTap: widget.onAddBus,
            tooltip: 'Add Bus',
            size: 28,
          ),
          const SizedBox(width: 4),
          GlassIconButton(
            icon: Icons.call_split,
            onTap: widget.onAddAux,
            tooltip: 'Add Aux',
            size: 28,
          ),
          const SizedBox(width: 4),
          GlassIconButton(
            icon: Icons.tune,
            onTap: widget.onAddVca,
            tooltip: 'Add VCA',
            size: 28,
          ),

          const Spacer(),

          // View options
          Text(
            '${mixer.channels.length} tracks',
            style: TextStyle(
              color: LiquidGlassTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassSectionLabel(String label) {
    return Container(
      width: 20,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border(
          right: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child: Text(
            label,
            style: TextStyle(
              color: LiquidGlassTheme.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// GLASS CHANNEL STRIP
// =============================================================================

class _GlassChannelStrip extends StatelessWidget {
  final MixerChannel channel;
  final double width;
  final bool compact;
  final ValueChanged<double>? onVolumeChange;
  final ValueChanged<double>? onPanChange;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onSoloToggle;
  final VoidCallback? onArmToggle;
  final ValueChanged<String>? onOutputChange;
  final List<MixerChannel>? availableBuses;
  final bool hasSoloedChannels;

  const _GlassChannelStrip({
    super.key,
    required this.channel,
    required this.width,
    this.compact = false,
    this.onVolumeChange,
    this.onPanChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onArmToggle,
    this.onOutputChange,
    this.availableBuses,
    this.hasSoloedChannels = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMuted = channel.muted || (hasSoloedChannels && !channel.soloed);

    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: channel.soloed
              ? LiquidGlassTheme.accentYellow.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          // Channel name
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: _getChannelColor().withValues(alpha: 0.2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Center(
              child: Text(
                channel.name,
                style: TextStyle(
                  color: LiquidGlassTheme.textPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Fader and meter area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  // Meter (use peakL for mono display)
                  Expanded(
                    child: _GlassMeter(
                      level: isMuted ? -60 : _peakToDb(channel.peakL),
                      peak: _peakToDb(channel.peakL),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Fader
                  SizedBox(
                    width: 24,
                    child: _GlassFader(
                      value: channel.volume,
                      onChanged: onVolumeChange,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Pan
          if (!compact)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _GlassPanKnob(
                value: channel.pan,
                onChanged: onPanChange,
              ),
            ),

          // Control buttons
          Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _GlassStripButton(
                  label: 'M',
                  isActive: channel.muted,
                  activeColor: LiquidGlassTheme.accentRed,
                  onTap: onMuteToggle,
                ),
                _GlassStripButton(
                  label: 'S',
                  isActive: channel.soloed,
                  activeColor: LiquidGlassTheme.accentYellow,
                  onTap: onSoloToggle,
                ),
                if (channel.type == ChannelType.audio && onArmToggle != null)
                  _GlassStripButton(
                    label: 'R',
                    isActive: channel.armed,
                    activeColor: LiquidGlassTheme.accentRed,
                    onTap: onArmToggle,
                  ),
              ],
            ),
          ),

          // Volume display
          Container(
            height: 18,
            margin: const EdgeInsets.only(bottom: 4),
            child: Center(
              child: Text(
                channel.volume <= -60 ? '-inf' : '${channel.volume.toStringAsFixed(1)} dB',
                style: TextStyle(
                  color: LiquidGlassTheme.textSecondary,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getChannelColor() {
    switch (channel.type) {
      case ChannelType.audio:
      case ChannelType.instrument:
        return LiquidGlassTheme.accentBlue;
      case ChannelType.bus:
        return LiquidGlassTheme.accentOrange;
      case ChannelType.aux:
        return LiquidGlassTheme.accentCyan;
      case ChannelType.vca:
        return LiquidGlassTheme.accentPurple;
      case ChannelType.master:
        return LiquidGlassTheme.accentGreen;
    }
  }
}

// =============================================================================
// GLASS VCA STRIP
// =============================================================================

class _GlassVcaStrip extends StatelessWidget {
  final VcaFader vca;
  final double width;
  final bool compact;
  final ValueChanged<double>? onLevelChange;
  final VoidCallback? onMuteToggle;

  const _GlassVcaStrip({
    super.key,
    required this.vca,
    required this.width,
    this.compact = false,
    this.onLevelChange,
    this.onMuteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            LiquidGlassTheme.accentPurple.withValues(alpha: 0.15),
            LiquidGlassTheme.accentPurple.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: LiquidGlassTheme.accentPurple.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // VCA name
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: LiquidGlassTheme.accentPurple.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Center(
              child: Text(
                vca.name,
                style: TextStyle(
                  color: LiquidGlassTheme.textPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Fader
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _GlassFader(
                value: vca.level,
                onChanged: onLevelChange,
                color: LiquidGlassTheme.accentPurple,
              ),
            ),
          ),

          // Mute button
          Padding(
            padding: const EdgeInsets.all(4),
            child: _GlassStripButton(
              label: 'M',
              isActive: vca.muted,
              activeColor: LiquidGlassTheme.accentRed,
              onTap: onMuteToggle,
            ),
          ),

          // Level display
          Container(
            height: 18,
            margin: const EdgeInsets.only(bottom: 4),
            child: Center(
              child: Text(
                _levelToDbString(vca.level),
                style: TextStyle(
                  color: LiquidGlassTheme.textSecondary,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Convert linear level (0-1.5) to dB string
String _levelToDbString(double level) {
  if (level <= 0.0001) return '-inf';
  final db = 20 * log(level) / ln10;
  return '${db.toStringAsFixed(1)} dB';
}

/// Convert linear level (0-1.5) to dB
double _levelToDb(double level) {
  if (level <= 0.0001) return -60;
  return 20 * log(level) / ln10;
}

/// Convert dB to linear level
double _dbToLevel(double db) {
  if (db <= -60) return 0;
  return pow(10, db / 20).toDouble();
}

// =============================================================================
// GLASS MASTER STRIP
// =============================================================================

class _GlassMasterStrip extends StatelessWidget {
  final MixerChannel master;
  final double width;
  final bool compact;
  final ValueChanged<double>? onVolumeChange;

  const _GlassMasterStrip({
    required this.master,
    required this.width,
    this.compact = false,
    this.onVolumeChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            LiquidGlassTheme.accentGreen.withValues(alpha: 0.15),
            LiquidGlassTheme.accentGreen.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: LiquidGlassTheme.accentGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          // Master label
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: LiquidGlassTheme.accentGreen.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: const Center(
              child: Text(
                'MASTER',
                style: TextStyle(
                  color: LiquidGlassTheme.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),

          // Stereo meter + fader
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  // Left meter
                  Expanded(
                    child: _GlassMeter(
                      level: _peakToDb(master.peakL),
                      peak: _peakToDb(master.peakL),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Fader (volume is linear 0-1.5, convert for display)
                  SizedBox(
                    width: 28,
                    child: _GlassFader(
                      value: _levelToDb(master.volume),
                      onChanged: onVolumeChange != null
                          ? (db) => onVolumeChange!(_dbToLevel(db))
                          : null,
                      color: LiquidGlassTheme.accentGreen,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Right meter
                  Expanded(
                    child: _GlassMeter(
                      level: _peakToDb(master.peakR),
                      peak: _peakToDb(master.peakR),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Volume display
          Container(
            height: 24,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                _levelToDbString(master.volume),
                style: TextStyle(
                  color: LiquidGlassTheme.accentGreen,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// GLASS COMPONENTS
// =============================================================================

class _GlassSectionDivider extends StatelessWidget {
  const _GlassSectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.2),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _GlassMeter extends StatelessWidget {
  final double level;
  final double peak;

  const _GlassMeter({
    required this.level,
    required this.peak,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedLevel = ((level + 60) / 66).clamp(0.0, 1.0);
    final normalizedPeak = ((peak + 60) / 66).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // Level bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: constraints.maxHeight * normalizedLevel,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LiquidGlassTheme.meterGradient,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Peak indicator
              Positioned(
                bottom: constraints.maxHeight * normalizedPeak - 2,
                left: 0,
                right: 0,
                height: 2,
                child: Container(
                  color: normalizedPeak > 0.95
                      ? LiquidGlassTheme.accentRed
                      : LiquidGlassTheme.accentYellow,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlassFader extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final Color? color;

  const _GlassFader({
    required this.value,
    this.onChanged,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Convert dB (-60 to +6) to normalized (0 to 1)
    final normalized = ((value + 60) / 66).clamp(0.0, 1.0);
    final effectiveColor = color ?? LiquidGlassTheme.accentBlue;

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (onChanged != null) {
          final delta = -details.delta.dy / 200;
          final newValue = (value + delta * 66).clamp(-60.0, 6.0);
          onChanged!(newValue);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final thumbHeight = 20.0;
            final trackHeight = constraints.maxHeight - thumbHeight;
            final thumbTop = trackHeight * (1 - normalized);

            return Stack(
              children: [
                // Track
                Positioned(
                  bottom: 0,
                  left: constraints.maxWidth * 0.3,
                  right: constraints.maxWidth * 0.3,
                  height: constraints.maxHeight * normalized,
                  child: Container(
                    decoration: BoxDecoration(
                      color: effectiveColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Thumb
                Positioned(
                  top: thumbTop,
                  left: 2,
                  right: 2,
                  height: thumbHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.3),
                          Colors.white.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: effectiveColor.withValues(alpha: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: effectiveColor.withValues(alpha: 0.3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 12,
                        height: 2,
                        color: effectiveColor,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GlassPanKnob extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;

  const _GlassPanKnob({
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'L',
            style: TextStyle(
              color: value < 0
                  ? LiquidGlassTheme.accentBlue
                  : LiquidGlassTheme.textTertiary,
              fontSize: 8,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: LiquidGlassTheme.glassSliderTheme(),
              child: Slider(
                value: value,
                min: -1,
                max: 1,
                onChanged: onChanged,
              ),
            ),
          ),
          Text(
            'R',
            style: TextStyle(
              color: value > 0
                  ? LiquidGlassTheme.accentBlue
                  : LiquidGlassTheme.textTertiary,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassStripButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback? onTap;

  const _GlassStripButton({
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: LiquidGlassTheme.animFast,
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? activeColor.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.1),
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? activeColor : LiquidGlassTheme.textTertiary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
