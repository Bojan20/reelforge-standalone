/// Mini Mixer View — Condensed mixer for quick adjustments
///
/// P3.5: Compact mixer view showing only essential controls:
/// - Faders with real-time meters
/// - Mute/Solo buttons
/// - Channel name on hover
/// - Double-click to expand temporarily
///
/// Features:
/// - 40px channel width (vs 70px compact mode)
/// - Toggle between Full/Mini view
/// - Horizontal scrolling for many channels
/// - Master channel always visible (right side)
/// - Real-time metering from engine

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../theme/fluxforge_theme.dart';
import '../../../../utils/audio_math.dart';
import '../../../mixer/ultimate_mixer.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════

const double kMiniStripWidth = 40.0;
const double kMiniMasterWidth = 56.0;
const double kMiniFaderHeight = 120.0;
const double kMiniMeterWidth = 6.0;

// ═══════════════════════════════════════════════════════════════════════════
// MINI MIXER VIEW
// ═══════════════════════════════════════════════════════════════════════════

/// Condensed mixer view with only faders and meters
class MiniMixerView extends StatefulWidget {
  final List<UltimateMixerChannel> channels;
  final List<UltimateMixerChannel> buses;
  final UltimateMixerChannel master;

  // Callbacks
  final void Function(String channelId, double volume)? onVolumeChange;
  final void Function(String channelId)? onMuteToggle;
  final void Function(String channelId)? onSoloToggle;
  final ValueChanged<String>? onChannelSelect;
  final VoidCallback? onSwitchToFullView;

  const MiniMixerView({
    super.key,
    required this.channels,
    required this.buses,
    required this.master,
    this.onVolumeChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onChannelSelect,
    this.onSwitchToFullView,
  });

  @override
  State<MiniMixerView> createState() => _MiniMixerViewState();
}

class _MiniMixerViewState extends State<MiniMixerView> {
  String? _hoveredChannel;
  String? _expandedChannel; // Double-clicked channel for temporary expansion
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          // Header with view toggle
          _buildHeader(),
          const Divider(height: 1, color: FluxForgeTheme.borderSubtle),
          // Mixer strips
          Expanded(
            child: Row(
              children: [
                // Scrollable channels and buses
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Audio channels
                        ...widget.channels.map((ch) => _buildMiniStrip(ch)),
                        // Bus separator
                        if (widget.buses.isNotEmpty) ...[
                          _buildSeparator(),
                          ...widget.buses.map((bus) => _buildMiniStrip(bus)),
                        ],
                      ],
                    ),
                  ),
                ),
                // Master strip (always visible)
                _buildSeparator(),
                _buildMasterStrip(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: FluxForgeTheme.bgMid,
      child: Row(
        children: [
          const Icon(Icons.view_compact, size: 14, color: FluxForgeTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            'MINI MIXER',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: FluxForgeTheme.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Channel count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '${widget.channels.length + widget.buses.length + 1}',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: FluxForgeTheme.accentBlue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Switch to full view
          if (widget.onSwitchToFullView != null)
            Tooltip(
              message: 'Switch to Full Mixer (double-click any channel)',
              child: InkWell(
                onTap: widget.onSwitchToFullView,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: FluxForgeTheme.borderSubtle),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full, size: 12, color: FluxForgeTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'FULL',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: FluxForgeTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniStrip(UltimateMixerChannel channel) {
    final isHovered = _hoveredChannel == channel.id;
    final isExpanded = _expandedChannel == channel.id;

    // Use expanded width when double-clicked
    final width = isExpanded ? kStripWidthCompact : kMiniStripWidth;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredChannel = channel.id),
      onExit: (_) => setState(() => _hoveredChannel = null),
      child: GestureDetector(
        onTap: () => widget.onChannelSelect?.call(channel.id),
        onDoubleTap: () {
          if (_expandedChannel == channel.id) {
            setState(() => _expandedChannel = null);
          } else {
            setState(() => _expandedChannel = channel.id);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          decoration: BoxDecoration(
            color: isHovered
                ? FluxForgeTheme.bgMid
                : FluxForgeTheme.bgDeep,
            border: Border(
              right: BorderSide(
                color: FluxForgeTheme.borderSubtle,
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Channel name (shown on hover or expanded)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 100),
                opacity: (isHovered || isExpanded) ? 1.0 : 0.0,
                child: _buildChannelName(channel),
              ),
              // Mute/Solo (compact)
              _buildMuteSolo(channel, compact: !isExpanded),
              const SizedBox(height: 4),
              // Fader + Meter
              Expanded(
                child: _buildFaderWithMeter(channel, isExpanded: isExpanded),
              ),
              const SizedBox(height: 4),
              // Volume readout
              _buildVolumeReadout(channel),
              const SizedBox(height: 4),
              // Color indicator
              _buildColorBar(channel),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelName(UltimateMixerChannel channel) {
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Center(
        child: Text(
          channel.name,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w500,
            color: FluxForgeTheme.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildMuteSolo(UltimateMixerChannel channel, {bool compact = true}) {
    if (compact) {
      // Single row with tiny M/S buttons
      return SizedBox(
        height: 16,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTinyButton(
              label: 'M',
              active: channel.muted,
              activeColor: FluxForgeTheme.accentRed,
              onTap: () => widget.onMuteToggle?.call(channel.id),
            ),
            const SizedBox(width: 2),
            _buildTinyButton(
              label: 'S',
              active: channel.soloed,
              activeColor: FluxForgeTheme.accentGreen,
              onTap: () => widget.onSoloToggle?.call(channel.id),
            ),
          ],
        ),
      );
    }

    // Expanded view - larger buttons
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: _buildMiniButton(
              label: 'M',
              active: channel.muted,
              activeColor: FluxForgeTheme.accentRed,
              onTap: () => widget.onMuteToggle?.call(channel.id),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _buildMiniButton(
              label: 'S',
              active: channel.soloed,
              activeColor: FluxForgeTheme.accentGreen,
              onTap: () => widget.onSoloToggle?.call(channel.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTinyButton({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: active ? activeColor : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.bold,
              color: active ? Colors.white : FluxForgeTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniButton({
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 18,
        decoration: BoxDecoration(
          color: active ? activeColor : FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active ? activeColor : FluxForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: active ? Colors.white : FluxForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFaderWithMeter(UltimateMixerChannel channel, {bool isExpanded = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isExpanded ? 6 : 4),
      child: Row(
        children: [
          // Left meter
          _buildMeter(channel.peakL, channel.rmsL),
          const SizedBox(width: 2),
          // Fader
          Expanded(
            child: _buildFader(channel),
          ),
          const SizedBox(width: 2),
          // Right meter
          _buildMeter(channel.peakR, channel.rmsR),
        ],
      ),
    );
  }

  Widget _buildMeter(double peak, double rms) {
    return Container(
      width: kMiniMeterWidth,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgSurface,
        borderRadius: BorderRadius.circular(2),
      ),
      child: CustomPaint(
        painter: _MiniMeterPainter(peak: peak, rms: rms),
      ),
    );
  }

  Widget _buildFader(UltimateMixerChannel channel) {
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        // Calculate new volume from drag (Cubase-style curve)
        final RenderBox box = context.findRenderObject() as RenderBox;
        final localPos = box.globalToLocal(details.globalPosition);
        final height = kMiniFaderHeight;
        final pos = 1.0 - (localPos.dy / height).clamp(0.0, 1.0);
        final newVolume = FaderCurve.positionToLinear(pos);
        widget.onVolumeChange?.call(channel.id, newVolume);
      },
      child: Container(
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgSurface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: FluxForgeTheme.borderSubtle,
            width: 1,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final faderPosition = (1.0 - FaderCurve.linearToPosition(channel.volume)) * (height - 12);

            return Stack(
              children: [
                // Track fill (below fader)
                Positioned(
                  left: 2,
                  right: 2,
                  top: faderPosition + 10,
                  bottom: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: channel.color.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Unity gain line
                Positioned(
                  left: 0,
                  right: 0,
                  top: height * (1.0 - 1.0/1.5) - 1,
                  child: Container(
                    height: 1,
                    color: FluxForgeTheme.textMuted.withOpacity(0.5),
                  ),
                ),
                // Fader cap
                Positioned(
                  left: 2,
                  right: 2,
                  top: faderPosition,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: channel.color,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: channel.color.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
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

  Widget _buildVolumeReadout(UltimateMixerChannel channel) {
    return Text(
      FaderCurve.linearToDbString(channel.volume),
      style: TextStyle(
        fontSize: 8,
        fontFamily: FluxForgeTheme.monoFontFamily,
        color: channel.volume > 1.0
            ? FluxForgeTheme.accentOrange
            : FluxForgeTheme.textSecondary,
      ),
    );
  }

  Widget _buildColorBar(UltimateMixerChannel channel) {
    return Container(
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: channel.color,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildSeparator() {
    return Container(
      width: 1,
      color: FluxForgeTheme.borderSubtle,
    );
  }

  Widget _buildMasterStrip() {
    final master = widget.master;

    return Container(
      width: kMiniMasterWidth,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(
          left: BorderSide(color: FluxForgeTheme.accentOrange, width: 2),
        ),
      ),
      child: Column(
        children: [
          // Master label
          Container(
            height: 18,
            child: Center(
              child: Text(
                'MASTER',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: FluxForgeTheme.accentOrange,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          // Mute only (no solo on master)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _buildMiniButton(
              label: 'M',
              active: master.muted,
              activeColor: FluxForgeTheme.accentRed,
              onTap: () => widget.onMuteToggle?.call(master.id),
            ),
          ),
          const SizedBox(height: 4),
          // Fader + Meter (larger for master)
          Expanded(
            child: _buildFaderWithMeter(master, isExpanded: true),
          ),
          const SizedBox(height: 4),
          // Volume readout
          _buildVolumeReadout(master),
          const SizedBox(height: 4),
          // Color indicator
          Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentOrange,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// MINI METER PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _MiniMeterPainter extends CustomPainter {
  final double peak;
  final double rms;

  _MiniMeterPainter({required this.peak, required this.rms});

  @override
  void paint(Canvas canvas, Size size) {
    final peakDb = _linearToDb(peak);
    final rmsDb = _linearToDb(rms);

    // Scale: -60dB to 0dB
    final peakHeight = ((peakDb + 60) / 60).clamp(0.0, 1.0) * size.height;
    final rmsHeight = ((rmsDb + 60) / 60).clamp(0.0, 1.0) * size.height;

    // RMS bar (darker)
    if (rmsHeight > 0) {
      final rmsRect = Rect.fromLTWH(
        0,
        size.height - rmsHeight,
        size.width,
        rmsHeight,
      );

      final rmsPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFF40FF90), // Green
            Color(0xFF40C8FF), // Cyan
          ],
        ).createShader(rmsRect);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rmsRect, const Radius.circular(1)),
        rmsPaint,
      );
    }

    // Peak line
    if (peakHeight > 0) {
      final peakY = size.height - peakHeight;
      final peakColor = peakDb > -3
          ? FluxForgeTheme.accentRed
          : (peakDb > -12 ? FluxForgeTheme.accentOrange : FluxForgeTheme.accentGreen);

      canvas.drawLine(
        Offset(0, peakY),
        Offset(size.width, peakY),
        Paint()
          ..color = peakColor
          ..strokeWidth = 1.5,
      );
    }
  }

  double _linearToDb(double linear) {
    if (linear <= 0.001) return -60.0;
    return 20.0 * math.log(linear) / math.ln10;
  }

  @override
  bool shouldRepaint(covariant _MiniMeterPainter oldDelegate) {
    return peak != oldDelegate.peak || rms != oldDelegate.rms;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MINI MIXER TOGGLE BUTTON
// ═══════════════════════════════════════════════════════════════════════════

/// Button to toggle between Mini and Full mixer views
class MixerViewToggle extends StatelessWidget {
  final bool isMiniView;
  final VoidCallback onToggle;

  const MixerViewToggle({
    super.key,
    required this.isMiniView,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isMiniView ? 'Switch to Full Mixer' : 'Switch to Mini Mixer',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgSurface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isMiniView
                  ? FluxForgeTheme.accentBlue
                  : FluxForgeTheme.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isMiniView ? Icons.view_compact : Icons.view_column,
                size: 14,
                color: isMiniView
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                isMiniView ? 'MINI' : 'FULL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isMiniView
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MIXER VIEW WRAPPER
// ═══════════════════════════════════════════════════════════════════════════

/// Wrapper that toggles between Mini and Full mixer views
class MixerViewWrapper extends StatefulWidget {
  final Widget Function(bool isMiniView, VoidCallback onToggle) fullMixerBuilder;
  final List<UltimateMixerChannel> channels;
  final List<UltimateMixerChannel> buses;
  final UltimateMixerChannel master;
  final void Function(String channelId, double volume)? onVolumeChange;
  final void Function(String channelId)? onMuteToggle;
  final void Function(String channelId)? onSoloToggle;
  final ValueChanged<String>? onChannelSelect;
  final bool initialMiniView;

  const MixerViewWrapper({
    super.key,
    required this.fullMixerBuilder,
    required this.channels,
    required this.buses,
    required this.master,
    this.onVolumeChange,
    this.onMuteToggle,
    this.onSoloToggle,
    this.onChannelSelect,
    this.initialMiniView = false,
  });

  @override
  State<MixerViewWrapper> createState() => _MixerViewWrapperState();
}

class _MixerViewWrapperState extends State<MixerViewWrapper> {
  late bool _isMiniView;

  @override
  void initState() {
    super.initState();
    _isMiniView = widget.initialMiniView;
  }

  void _toggle() {
    setState(() => _isMiniView = !_isMiniView);
  }

  @override
  Widget build(BuildContext context) {
    if (_isMiniView) {
      return MiniMixerView(
        channels: widget.channels,
        buses: widget.buses,
        master: widget.master,
        onVolumeChange: widget.onVolumeChange,
        onMuteToggle: widget.onMuteToggle,
        onSoloToggle: widget.onSoloToggle,
        onChannelSelect: widget.onChannelSelect,
        onSwitchToFullView: _toggle,
      );
    }

    return widget.fullMixerBuilder(_isMiniView, _toggle);
  }
}
