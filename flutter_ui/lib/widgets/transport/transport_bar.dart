/// TransportBar - Professional DAW transport controls
///
/// Play, Stop, Record, Rewind, Forward with micro-interactions
/// Time display (bars:beats, timecode, samples)
/// Tempo, loop, metronome controls
/// DSD/GPU status indicators

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/fluxforge_theme.dart';
import '../dsp/dsd_indicator.dart';
import '../dsp/gpu_settings_panel.dart';

enum TimeDisplayMode { bars, timecode, samples }

/// Punch recording mode
enum PunchMode { off, punchIn, punchOut, punchInOut }

class TransportBar extends StatelessWidget {
  final bool isPlaying;
  final bool isRecording;
  final bool loopEnabled;
  final bool metronomeEnabled;
  final double currentTime; // seconds
  final double tempo;
  final TimeDisplayMode timeDisplayMode;

  // Punch In/Out
  final PunchMode punchMode;
  final double? punchInTime;  // seconds
  final double? punchOutTime; // seconds

  // Pre-roll / Post-roll
  final bool preRollEnabled;
  final double preRollBars; // bars before punch/locator
  final bool postRollEnabled;
  final double postRollBars; // bars after punch/locator

  // Countdown
  final bool countInEnabled;
  final int countInBars;

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

  // Punch callbacks
  final ValueChanged<PunchMode>? onPunchModeChange;
  final ValueChanged<double>? onPunchInChange;
  final ValueChanged<double>? onPunchOutChange;
  final VoidCallback? onSetPunchInAtCursor;
  final VoidCallback? onSetPunchOutAtCursor;

  // Pre-roll callbacks
  final VoidCallback? onPreRollToggle;
  final ValueChanged<double>? onPreRollBarsChange;
  final VoidCallback? onPostRollToggle;
  final ValueChanged<double>? onPostRollBarsChange;

  // Count-in callback
  final VoidCallback? onCountInToggle;
  final ValueChanged<int>? onCountInBarsChange;

  const TransportBar({
    super.key,
    this.isPlaying = false,
    this.isRecording = false,
    this.loopEnabled = false,
    this.metronomeEnabled = false,
    this.currentTime = 0,
    this.tempo = 120,
    this.timeDisplayMode = TimeDisplayMode.bars,
    // Punch defaults
    this.punchMode = PunchMode.off,
    this.punchInTime,
    this.punchOutTime,
    // Pre-roll defaults
    this.preRollEnabled = false,
    this.preRollBars = 2,
    this.postRollEnabled = false,
    this.postRollBars = 1,
    // Count-in defaults
    this.countInEnabled = false,
    this.countInBars = 2,
    // DSD/GPU
    this.dsdRate = DsdRate.none,
    this.dsdMode = DsdPlaybackMode.none,
    this.isDsdLoaded = false,
    this.gpuMode = GpuProcessingMode.cpuOnly,
    this.gpuUtilization = 0,
    // Callbacks
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
    this.onPunchModeChange,
    this.onPunchInChange,
    this.onPunchOutChange,
    this.onSetPunchInAtCursor,
    this.onSetPunchOutAtCursor,
    this.onPreRollToggle,
    this.onPreRollBarsChange,
    this.onPostRollToggle,
    this.onPostRollBarsChange,
    this.onCountInToggle,
    this.onCountInBarsChange,
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
        color: FluxForgeTheme.bgDeep,
        border: Border(
          bottom: BorderSide(color: FluxForgeTheme.borderSubtle),
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

          // Punch In/Out
          _PunchControl(
            mode: punchMode,
            punchInTime: punchInTime,
            punchOutTime: punchOutTime,
            tempo: tempo,
            onModeChange: onPunchModeChange,
            onSetPunchIn: onSetPunchInAtCursor,
            onSetPunchOut: onSetPunchOutAtCursor,
          ),

          const SizedBox(width: 8),

          // Pre-Roll
          _ToggleButton(
            icon: Icons.skip_previous_rounded,
            label: 'PRE',
            isActive: preRollEnabled,
            onTap: onPreRollToggle,
            activeColor: FluxForgeTheme.accentBlue,
          ),

          const SizedBox(width: 4),

          // Count-In
          _ToggleButton(
            icon: Icons.timer_rounded,
            label: 'COUNT',
            isActive: countInEnabled,
            onTap: onCountInToggle,
            activeColor: FluxForgeTheme.accentOrange,
          ),

          const SizedBox(width: 8),

          // Loop & Metronome
          _ToggleButton(
            icon: Icons.repeat_rounded,
            label: 'LOOP',
            isActive: loopEnabled,
            onTap: onLoopToggle,
            activeColor: FluxForgeTheme.accentCyan,
          ),

          const SizedBox(width: 8),

          _ToggleButton(
            icon: Icons.music_note_rounded,
            label: 'CLICK',
            isActive: metronomeEnabled,
            onTap: onMetronomeToggle,
            activeColor: FluxForgeTheme.accentOrange,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PUNCH CONTROL
// ═══════════════════════════════════════════════════════════════════════════════

class _PunchControl extends StatelessWidget {
  final PunchMode mode;
  final double? punchInTime;
  final double? punchOutTime;
  final double tempo;
  final ValueChanged<PunchMode>? onModeChange;
  final VoidCallback? onSetPunchIn;
  final VoidCallback? onSetPunchOut;

  const _PunchControl({
    required this.mode,
    this.punchInTime,
    this.punchOutTime,
    required this.tempo,
    this.onModeChange,
    this.onSetPunchIn,
    this.onSetPunchOut,
  });

  String _formatTimeShort(double? time) {
    if (time == null) return '--:--';
    final beats = (time * tempo / 60);
    final bar = (beats / 4).floor() + 1;
    final beat = (beats % 4).floor() + 1;
    return '$bar.$beat';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = mode != PunchMode.off;
    final isPunchIn = mode == PunchMode.punchIn || mode == PunchMode.punchInOut;
    final isPunchOut = mode == PunchMode.punchOut || mode == PunchMode.punchInOut;

    return PopupMenuButton<PunchMode>(
      initialValue: mode,
      onSelected: onModeChange,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: PunchMode.off,
          child: Row(
            children: [
              Icon(Icons.block, size: 16),
              SizedBox(width: 8),
              Text('Off'),
            ],
          ),
        ),
        PopupMenuItem(
          value: PunchMode.punchIn,
          child: Row(
            children: [
              Icon(Icons.first_page, size: 16,
                color: isPunchIn ? FluxForgeTheme.accentRed : null),
              const SizedBox(width: 8),
              const Text('Punch In'),
              const Spacer(),
              Text(_formatTimeShort(punchInTime),
                style: TextStyle(
                  fontSize: 11,
                  color: FluxForgeTheme.textTertiary,
                  fontFamily: 'JetBrains Mono',
                )),
            ],
          ),
        ),
        PopupMenuItem(
          value: PunchMode.punchOut,
          child: Row(
            children: [
              Icon(Icons.last_page, size: 16,
                color: isPunchOut ? FluxForgeTheme.accentRed : null),
              const SizedBox(width: 8),
              const Text('Punch Out'),
              const Spacer(),
              Text(_formatTimeShort(punchOutTime),
                style: TextStyle(
                  fontSize: 11,
                  color: FluxForgeTheme.textTertiary,
                  fontFamily: 'JetBrains Mono',
                )),
            ],
          ),
        ),
        PopupMenuItem(
          value: PunchMode.punchInOut,
          child: Row(
            children: [
              Icon(Icons.swap_horiz, size: 16,
                color: mode == PunchMode.punchInOut ? FluxForgeTheme.accentRed : null),
              const SizedBox(width: 8),
              const Text('Punch In/Out'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          onTap: onSetPunchIn,
          child: Row(
            children: [
              const Icon(Icons.keyboard_tab, size: 16),
              const SizedBox(width: 8),
              const Text('Set Punch In'),
              const Spacer(),
              Text('I', style: TextStyle(
                fontSize: 11, color: FluxForgeTheme.textTertiary)),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: onSetPunchOut,
          child: Row(
            children: [
              const Icon(Icons.keyboard_tab, size: 16),
              const SizedBox(width: 8),
              const Text('Set Punch Out'),
              const Spacer(),
              Text('O', style: TextStyle(
                fontSize: 11, color: FluxForgeTheme.textTertiary)),
            ],
          ),
        ),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? FluxForgeTheme.accentRed.withValues(alpha: 0.2)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive
                ? FluxForgeTheme.accentRed
                : FluxForgeTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode == PunchMode.punchInOut
                  ? Icons.swap_horiz
                  : isPunchIn
                      ? Icons.first_page
                      : isPunchOut
                          ? Icons.last_page
                          : Icons.block,
              size: 14,
              color: isActive
                  ? FluxForgeTheme.accentRed
                  : FluxForgeTheme.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              'PUNCH',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: isActive
                    ? FluxForgeTheme.accentRed
                    : FluxForgeTheme.textTertiary,
              ),
            ),
          ],
        ),
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
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
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
            activeColor: FluxForgeTheme.accentGreen,
            tooltip: isPlaying ? 'Pause (Space)' : 'Play (Space)',
            large: true,
          ),

          // Record
          _TransportButton(
            icon: Icons.fiber_manual_record_rounded,
            onTap: onRecord,
            isActive: isRecording,
            activeColor: FluxForgeTheme.accentRed,
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
        ? (widget.activeColor ?? FluxForgeTheme.accentBlue)
        : FluxForgeTheme.textSecondary;

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
                ? FluxForgeTheme.bgHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: widget.isActive
                ? FluxForgeTheme.glowShadow(color, intensity: 0.3)
                : null,
          ),
          transform: Matrix4.identity()..scale(_isPressed ? 0.9 : 1.0),
          child: Icon(
            widget.icon,
            size: iconSize,
            color: _isHovered ? FluxForgeTheme.textPrimary : color,
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
          color: FluxForgeTheme.bgDeepest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FluxForgeTheme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _modeLabel,
              style: FluxForgeTheme.label.copyWith(
                color: FluxForgeTheme.accentBlue,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              time,
              style: FluxForgeTheme.mono.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: FluxForgeTheme.accentGreen,
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
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('BPM', style: FluxForgeTheme.label),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              tempo.toStringAsFixed(1),
              style: FluxForgeTheme.mono.copyWith(
                fontSize: 14,
                color: FluxForgeTheme.accentOrange,
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
          duration: FluxForgeTheme.fastDuration,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.activeColor.withValues(alpha: 0.2)
                : _isHovered
                    ? FluxForgeTheme.bgHover
                    : FluxForgeTheme.bgMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isActive
                  ? widget.activeColor
                  : FluxForgeTheme.borderSubtle,
            ),
            boxShadow: widget.isActive
                ? FluxForgeTheme.glowShadow(widget.activeColor, intensity: 0.2)
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
                    : FluxForgeTheme.textTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: FluxForgeTheme.label.copyWith(
                  color: widget.isActive
                      ? widget.activeColor
                      : FluxForgeTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
