/// Glass Transport Bar
///
/// Liquid Glass styled transport controls:
/// - Play/Stop/Record
/// - Time display
/// - Tempo/Time signature
/// - Loop/Metronome toggles

import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/liquid_glass_theme.dart';
import 'glass_widgets.dart';

/// Time display modes
enum GlassTimeDisplayMode { bars, timecode, samples }

/// Glass transport bar widget
class GlassTransportBar extends StatelessWidget {
  final bool isPlaying;
  final bool isRecording;
  final bool loopEnabled;
  final bool metronomeEnabled;
  final double tempo;
  final int timeSigNum;
  final int timeSigDenom;
  final double currentTime;
  final GlassTimeDisplayMode timeDisplayMode;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;
  final VoidCallback? onLoopToggle;
  final VoidCallback? onMetronomeToggle;
  final VoidCallback? onTimeDisplayTap;
  final ValueChanged<double>? onTempoChange;

  const GlassTransportBar({
    super.key,
    this.isPlaying = false,
    this.isRecording = false,
    this.loopEnabled = false,
    this.metronomeEnabled = false,
    this.tempo = 120.0,
    this.timeSigNum = 4,
    this.timeSigDenom = 4,
    this.currentTime = 0.0,
    this.timeDisplayMode = GlassTimeDisplayMode.bars,
    this.onPlay,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onForward,
    this.onLoopToggle,
    this.onMetronomeToggle,
    this.onTimeDisplayTap,
    this.onTempoChange,
  });

  String get _formattedTime {
    switch (timeDisplayMode) {
      case GlassTimeDisplayMode.bars:
        return _formatBarsBeats();
      case GlassTimeDisplayMode.timecode:
        return _formatTimecode();
      case GlassTimeDisplayMode.samples:
        return _formatSamples();
    }
  }

  String _formatBarsBeats() {
    final beatsPerSecond = tempo / 60;
    final totalBeats = currentTime * beatsPerSecond;
    final beatsPerBar = timeSigNum;
    final bars = (totalBeats / beatsPerBar).floor() + 1;
    final beats = (totalBeats % beatsPerBar).floor() + 1;
    final ticks = ((totalBeats % 1) * 480).floor();
    return '${bars.toString().padLeft(3, ' ')}.${beats}.${ticks.toString().padLeft(3, '0')}';
  }

  String _formatTimecode() {
    final hrs = (currentTime / 3600).floor();
    final mins = ((currentTime % 3600) / 60).floor();
    final secs = (currentTime % 60).floor();
    final frames = ((currentTime % 1) * 30).floor();
    return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
  }

  String _formatSamples() {
    final samples = (currentTime * 48000).floor();
    return samples.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: LiquidGlassTheme.blurAmount,
          sigmaY: LiquidGlassTheme.blurAmount,
        ),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.1),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: Stack(
            children: [
              // Specular highlight
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.3),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Time display
                    _buildTimeDisplay(),
                    const SizedBox(width: 24),

                    // Transport buttons
                    _buildTransportControls(),

                    const Spacer(),

                    // Tempo & Time Signature
                    _buildTempoSection(),
                    const SizedBox(width: 16),

                    // Loop & Metronome
                    _buildToggles(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeDisplay() {
    return GestureDetector(
      onTap: onTimeDisplayTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: LiquidGlassTheme.accentGreen.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: LiquidGlassTheme.accentGreen.withValues(alpha: 0.1),
              blurRadius: 12,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Text(
          _formattedTime,
          style: TextStyle(
            color: isPlaying
                ? LiquidGlassTheme.accentGreen
                : LiquidGlassTheme.textPrimary,
            fontSize: 22,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildTransportControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rewind
        _TransportButton(
          icon: Icons.skip_previous,
          onTap: onRewind,
          tooltip: 'Rewind',
        ),
        const SizedBox(width: 4),

        // Stop
        _TransportButton(
          icon: Icons.stop,
          onTap: onStop,
          tooltip: 'Stop',
        ),
        const SizedBox(width: 4),

        // Play
        _TransportButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          onTap: onPlay,
          isActive: isPlaying,
          activeColor: LiquidGlassTheme.accentGreen,
          tooltip: isPlaying ? 'Pause' : 'Play',
          size: 44,
        ),
        const SizedBox(width: 4),

        // Record
        _TransportButton(
          icon: Icons.fiber_manual_record,
          onTap: onRecord,
          isActive: isRecording,
          activeColor: LiquidGlassTheme.accentRed,
          tooltip: 'Record',
        ),
        const SizedBox(width: 4),

        // Forward
        _TransportButton(
          icon: Icons.skip_next,
          onTap: onForward,
          tooltip: 'Forward',
        ),
      ],
    );
  }

  Widget _buildTempoSection() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tempo
        GestureDetector(
          onVerticalDragUpdate: (details) {
            if (onTempoChange != null) {
              final delta = -details.delta.dy * 0.5;
              onTempoChange!((tempo + delta).clamp(20, 999));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tempo.toStringAsFixed(2),
                  style: const TextStyle(
                    color: LiquidGlassTheme.textPrimary,
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'BPM',
                  style: TextStyle(
                    color: LiquidGlassTheme.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Time Signature
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$timeSigNum/$timeSigDenom',
            style: const TextStyle(
              color: LiquidGlassTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggles() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Loop
        GlassIconButton(
          icon: Icons.repeat,
          isActive: loopEnabled,
          activeColor: LiquidGlassTheme.accentCyan,
          onTap: onLoopToggle,
          tooltip: 'Loop',
          size: 32,
        ),
        const SizedBox(width: 4),

        // Metronome
        GlassIconButton(
          icon: Icons.timer,
          isActive: metronomeEnabled,
          activeColor: LiquidGlassTheme.accentOrange,
          onTap: onMetronomeToggle,
          tooltip: 'Metronome',
          size: 32,
        ),
      ],
    );
  }
}

class _TransportButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? activeColor;
  final String? tooltip;
  final double size;

  const _TransportButton({
    required this.icon,
    this.onTap,
    this.isActive = false,
    this.activeColor,
    this.tooltip,
    this.size = 38,
  });

  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.activeColor ?? Colors.white;
    final isActive = widget.isActive;

    Widget button = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: LiquidGlassTheme.animFast,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.25)
                : _isHovered
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(widget.size / 4),
            border: Border.all(
              color: isActive
                  ? color.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.15),
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            widget.icon,
            size: widget.size * 0.5,
            color: isActive ? color : LiquidGlassTheme.textSecondary,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }
    return button;
  }
}
