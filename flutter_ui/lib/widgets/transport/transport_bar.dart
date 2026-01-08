/// TransportBar - Professional DAW transport controls
///
/// Play, Stop, Record, Rewind, Forward with micro-interactions
/// Time display (bars:beats, timecode, samples)
/// Tempo, loop, metronome controls
/// DSD/GPU status indicators

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/reelforge_theme.dart';
import '../dsp/dsd_indicator.dart';
import '../dsp/gpu_settings_panel.dart';

enum TimeDisplayMode { bars, timecode, samples }

class TransportBar extends StatelessWidget {
  final bool isPlaying;
  final bool isRecording;
  final bool loopEnabled;
  final bool metronomeEnabled;
  final double currentTime; // seconds
  final double tempo;
  final TimeDisplayMode timeDisplayMode;

  // DSD status
  final DsdRate dsdRate;
  final DsdPlaybackMode dsdMode;
  final bool isDsdLoaded;

  // GPU status
  final GpuProcessingMode gpuMode;
  final double gpuUtilization;

  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;
  final VoidCallback? onLoopToggle;
  final VoidCallback? onMetronomeToggle;
  final VoidCallback? onTimeDisplayModeChange;
  final ValueChanged<double>? onTempoChange;
  final VoidCallback? onDsdTap;
  final VoidCallback? onGpuTap;

  const TransportBar({
    super.key,
    this.isPlaying = false,
    this.isRecording = false,
    this.loopEnabled = false,
    this.metronomeEnabled = false,
    this.currentTime = 0,
    this.tempo = 120,
    this.timeDisplayMode = TimeDisplayMode.bars,
    this.dsdRate = DsdRate.none,
    this.dsdMode = DsdPlaybackMode.none,
    this.isDsdLoaded = false,
    this.gpuMode = GpuProcessingMode.cpuOnly,
    this.gpuUtilization = 0,
    this.onPlay,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onForward,
    this.onLoopToggle,
    this.onMetronomeToggle,
    this.onTimeDisplayModeChange,
    this.onTempoChange,
    this.onDsdTap,
    this.onGpuTap,
  });

  String _formatTime() {
    switch (timeDisplayMode) {
      case TimeDisplayMode.bars:
        final beats = (currentTime * tempo / 60);
        final bar = (beats / 4).floor() + 1;
        final beat = (beats % 4).floor() + 1;
        final tick = ((beats % 1) * 480).floor();
        return '$bar.$beat.${tick.toString().padLeft(3, '0')}';

      case TimeDisplayMode.timecode:
        final hours = (currentTime / 3600).floor();
        final minutes = ((currentTime % 3600) / 60).floor();
        final seconds = (currentTime % 60).floor();
        final frames = ((currentTime % 1) * 30).floor(); // 30fps
        return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';

      case TimeDisplayMode.samples:
        final samples = (currentTime * 48000).floor();
        return samples.toString().padLeft(10, '0');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          // Transport controls
          _TransportButtonGroup(
            isPlaying: isPlaying,
            isRecording: isRecording,
            onPlay: onPlay,
            onStop: onStop,
            onRecord: onRecord,
            onRewind: onRewind,
            onForward: onForward,
          ),

          const SizedBox(width: 24),

          // Time display
          _TimeDisplay(
            time: _formatTime(),
            mode: timeDisplayMode,
            onTap: onTimeDisplayModeChange,
          ),

          const SizedBox(width: 24),

          // Tempo
          _TempoControl(
            tempo: tempo,
            onChanged: onTempoChange,
          ),

          const Spacer(),

          // DSD Indicator (shows only when DSD content loaded)
          DsdIndicator(
            rate: dsdRate,
            mode: dsdMode,
            isDsdLoaded: isDsdLoaded,
            onTap: onDsdTap,
          ),

          const SizedBox(width: 8),

          // GPU Indicator (shows only when GPU processing active)
          GpuIndicator(
            mode: gpuMode,
            utilization: gpuUtilization,
            onTap: onGpuTap,
          ),

          const SizedBox(width: 16),

          // Loop & Metronome
          _ToggleButton(
            icon: Icons.repeat_rounded,
            label: 'LOOP',
            isActive: loopEnabled,
            onTap: onLoopToggle,
            activeColor: ReelForgeTheme.accentCyan,
          ),

          const SizedBox(width: 8),

          _ToggleButton(
            icon: Icons.music_note_rounded,
            label: 'CLICK',
            isActive: metronomeEnabled,
            onTap: onMetronomeToggle,
            activeColor: ReelForgeTheme.accentOrange,
          ),
        ],
      ),
    );
  }
}

class _TransportButtonGroup extends StatelessWidget {
  final bool isPlaying;
  final bool isRecording;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;

  const _TransportButtonGroup({
    required this.isPlaying,
    required this.isRecording,
    this.onPlay,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onForward,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rewind
          _TransportButton(
            icon: Icons.fast_rewind_rounded,
            onTap: onRewind,
            tooltip: 'Rewind (,)',
          ),

          // Stop
          _TransportButton(
            icon: Icons.stop_rounded,
            onTap: onStop,
            tooltip: 'Stop (.)',
          ),

          // Play/Pause
          _TransportButton(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            onTap: onPlay,
            isActive: isPlaying,
            activeColor: ReelForgeTheme.accentGreen,
            tooltip: isPlaying ? 'Pause (Space)' : 'Play (Space)',
            large: true,
          ),

          // Record
          _TransportButton(
            icon: Icons.fiber_manual_record_rounded,
            onTap: onRecord,
            isActive: isRecording,
            activeColor: ReelForgeTheme.accentRed,
            tooltip: 'Record (R)',
          ),

          // Forward
          _TransportButton(
            icon: Icons.fast_forward_rounded,
            onTap: onForward,
            tooltip: 'Forward (/)',
          ),
        ],
      ),
    );
  }
}

class _TransportButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? activeColor;
  final String? tooltip;
  final bool large;

  const _TransportButton({
    required this.icon,
    this.onTap,
    this.isActive = false,
    this.activeColor,
    this.tooltip,
    this.large = false,
  });

  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.large ? 36.0 : 28.0;
    final iconSize = widget.large ? 22.0 : 18.0;
    final color = widget.isActive
        ? (widget.activeColor ?? ReelForgeTheme.accentBlue)
        : ReelForgeTheme.textSecondary;

    Widget button = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _isHovered
                ? ReelForgeTheme.bgHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: widget.isActive
                ? ReelForgeTheme.glowShadow(color, intensity: 0.3)
                : null,
          ),
          transform: Matrix4.identity()..scale(_isPressed ? 0.9 : 1.0),
          child: Icon(
            widget.icon,
            size: iconSize,
            color: _isHovered ? ReelForgeTheme.textPrimary : color,
          ),
        ),
      ),
    );

    // Add pulse animation when active (playing/recording)
    if (widget.isActive && widget.icon == Icons.fiber_manual_record_rounded) {
      button = button
          .animate(onPlay: (c) => c.repeat())
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.1, 1.1),
            duration: 600.ms,
            curve: Curves.easeInOut,
          )
          .then()
          .scale(
            begin: const Offset(1.1, 1.1),
            end: const Offset(1, 1),
            duration: 600.ms,
            curve: Curves.easeInOut,
          );
    }

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}

class _TimeDisplay extends StatelessWidget {
  final String time;
  final TimeDisplayMode mode;
  final VoidCallback? onTap;

  const _TimeDisplay({
    required this.time,
    required this.mode,
    this.onTap,
  });

  String get _modeLabel {
    switch (mode) {
      case TimeDisplayMode.bars:
        return 'BARS';
      case TimeDisplayMode.timecode:
        return 'TC';
      case TimeDisplayMode.samples:
        return 'SMPLS';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: ReelForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _modeLabel,
              style: ReelForgeTheme.label.copyWith(
                color: ReelForgeTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              time,
              style: ReelForgeTheme.mono.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: ReelForgeTheme.accentGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TempoControl extends StatelessWidget {
  final double tempo;
  final ValueChanged<double>? onChanged;

  const _TempoControl({
    required this.tempo,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ReelForgeTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('BPM', style: ReelForgeTheme.label),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              tempo.toStringAsFixed(1),
              style: ReelForgeTheme.mono.copyWith(
                fontSize: 14,
                color: ReelForgeTheme.accentOrange,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final Color activeColor;

  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.isActive,
    this.onTap,
    required this.activeColor,
  });

  @override
  State<_ToggleButton> createState() => _ToggleButtonState();
}

class _ToggleButtonState extends State<_ToggleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: ReelForgeTheme.fastDuration,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.activeColor.withValues(alpha: 0.2)
                : _isHovered
                    ? ReelForgeTheme.bgHover
                    : ReelForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isActive
                  ? widget.activeColor
                  : ReelForgeTheme.borderSubtle,
            ),
            boxShadow: widget.isActive
                ? ReelForgeTheme.glowShadow(widget.activeColor, intensity: 0.2)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isActive
                    ? widget.activeColor
                    : ReelForgeTheme.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: ReelForgeTheme.label.copyWith(
                  color: widget.isActive
                      ? widget.activeColor
                      : ReelForgeTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
