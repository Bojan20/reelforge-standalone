/// Transport Bar Widget
///
/// DAW transport controls: play, stop, record, rewind, forward,
/// loop, metronome, and snap-to-grid.

import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

class TransportBar extends StatelessWidget {
  final bool isPlaying;
  final bool isRecording;
  final bool transportDisabled;
  final bool loopEnabled;
  final bool metronomeEnabled;
  final bool snapEnabled;
  final double snapValue;
  final int armedCount;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onRecord;
  final VoidCallback? onRewind;
  final VoidCallback? onForward;
  final VoidCallback? onLoopToggle;
  final VoidCallback? onMetronomeToggle;
  final VoidCallback? onSnapToggle;
  final ValueChanged<double>? onSnapValueChange;

  const TransportBar({
    super.key,
    this.isPlaying = false,
    this.isRecording = false,
    this.transportDisabled = false,
    this.loopEnabled = false,
    this.metronomeEnabled = false,
    this.snapEnabled = true,
    this.snapValue = 1,
    this.armedCount = 0,
    this.onPlay,
    this.onStop,
    this.onRecord,
    this.onRewind,
    this.onForward,
    this.onLoopToggle,
    this.onMetronomeToggle,
    this.onSnapToggle,
    this.onSnapValueChange,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TransportButton(
          icon: Icons.skip_previous,
          onPressed: onRewind,
          tooltip: 'Rewind (,)',
        ),
        _TransportButton(
          icon: Icons.stop,
          onPressed: onStop,
          tooltip: 'Stop (.)',
        ),
        _TransportButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          onPressed: transportDisabled ? null : onPlay,
          tooltip: transportDisabled ? 'Timeline playback disabled' : 'Play/Pause (Space)',
          isActive: isPlaying,
          activeColor: FluxForgeTheme.accentGreen,
        ),
        _RecordButton(
          isRecording: isRecording,
          armedCount: armedCount,
          onPressed: onRecord,
        ),
        _TransportButton(
          icon: Icons.skip_next,
          onPressed: onForward,
          tooltip: 'Forward (/)',
        ),
        const SizedBox(width: 8),
        _Divider(),
        const SizedBox(width: 8),
        _TransportButton(
          icon: Icons.repeat,
          onPressed: onLoopToggle,
          tooltip: 'Loop (L)',
          isActive: loopEnabled,
          size: 18,
        ),
        _TransportButton(
          icon: Icons.music_note,
          onPressed: onMetronomeToggle,
          tooltip: 'Metronome (K)',
          isActive: metronomeEnabled,
          size: 18,
        ),
        const SizedBox(width: 8),
        _Divider(),
        const SizedBox(width: 8),
        _TransportButton(
          icon: Icons.grid_on,
          onPressed: onSnapToggle,
          tooltip: 'Snap to Grid (G)',
          isActive: snapEnabled,
          size: 16,
        ),
        if (snapEnabled && onSnapValueChange != null)
          _SnapSelector(value: snapValue, onChanged: onSnapValueChange!),
      ],
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool isActive;
  final Color? activeColor;
  final double size;

  const _TransportButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isActive = false,
    this.activeColor,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? (activeColor ?? FluxForgeTheme.accentBlue)
        : FluxForgeTheme.textSecondary;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: size,
            color: onPressed == null
                ? FluxForgeTheme.textSecondary.withValues(alpha: 0.4)
                : color,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 24, color: FluxForgeTheme.borderSubtle);
  }
}

class _RecordButton extends StatefulWidget {
  final bool isRecording;
  final int armedCount;
  final VoidCallback? onPressed;

  const _RecordButton({
    required this.isRecording,
    required this.armedCount,
    this.onPressed,
  });

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isRecording) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_RecordButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !oldWidget.isRecording) {
      _controller.repeat(reverse: true);
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.armedCount == 0 && !widget.isRecording;

    return Tooltip(
      message: isDisabled
          ? 'No tracks armed for recording'
          : widget.isRecording
              ? 'Stop Recording (R)\n${widget.armedCount} track(s) recording'
              : 'Start Recording (R)\n${widget.armedCount} track(s) armed',
      child: InkWell(
        onTap: isDisabled ? null : widget.onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: widget.isRecording
                    ? FluxForgeTheme.errorRed.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Icon(
                    Icons.fiber_manual_record,
                    size: 20,
                    color: isDisabled
                        ? FluxForgeTheme.textSecondary.withValues(alpha: 0.4)
                        : widget.isRecording
                            ? FluxForgeTheme.errorRed.withValues(alpha: _animation.value)
                            : widget.armedCount > 0
                                ? FluxForgeTheme.errorRed.withValues(alpha: 0.7)
                                : FluxForgeTheme.textSecondary,
                  );
                },
              ),
            ),
            // Armed count badge
            if (widget.armedCount > 0 && !widget.isRecording)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.errorRed,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                  child: Text(
                    '${widget.armedCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SnapSelector extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _SnapSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: DropdownButton<double>(
        value: value,
        isDense: true,
        underline: const SizedBox(),
        dropdownColor: FluxForgeTheme.bgElevated,
        style: const TextStyle(color: FluxForgeTheme.textPrimary, fontSize: 10),
        items: const [
          DropdownMenuItem(value: 0.25, child: Text('1/16')),
          DropdownMenuItem(value: 0.5, child: Text('1/8')),
          DropdownMenuItem(value: 1.0, child: Text('1/4')),
          DropdownMenuItem(value: 2.0, child: Text('1/2')),
          DropdownMenuItem(value: 4.0, child: Text('Bar')),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
