/// Transport Controls Widget
///
/// DAW-style transport bar with:
/// - Play/Pause/Stop
/// - Time display
/// - Loop toggle
/// - Volume control
/// - Playhead position slider

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/reelforge_theme.dart';

// ============ Types ============

class TransportState {
  final bool isPlaying;
  final bool isPaused;
  final double currentTime;
  final double duration;
  final bool looping;
  final double volume;
  final String? currentAssetId;

  const TransportState({
    this.isPlaying = false,
    this.isPaused = false,
    this.currentTime = 0,
    this.duration = 60,
    this.looping = false,
    this.volume = 1,
    this.currentAssetId,
  });

  TransportState copyWith({
    bool? isPlaying,
    bool? isPaused,
    double? currentTime,
    double? duration,
    bool? looping,
    double? volume,
    String? currentAssetId,
  }) {
    return TransportState(
      isPlaying: isPlaying ?? this.isPlaying,
      isPaused: isPaused ?? this.isPaused,
      currentTime: currentTime ?? this.currentTime,
      duration: duration ?? this.duration,
      looping: looping ?? this.looping,
      volume: volume ?? this.volume,
      currentAssetId: currentAssetId ?? this.currentAssetId,
    );
  }
}

// ============ Widget ============

class TransportControls extends StatefulWidget {
  final TransportState state;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onStop;
  final ValueChanged<double>? onSeek;
  final ValueChanged<double>? onVolumeChange;
  final VoidCallback? onLoopToggle;
  final bool disabled;
  final bool compact;

  const TransportControls({
    super.key,
    required this.state,
    this.onPlay,
    this.onPause,
    this.onStop,
    this.onSeek,
    this.onVolumeChange,
    this.onLoopToggle,
    this.disabled = false,
    this.compact = false,
  });

  @override
  State<TransportControls> createState() => _TransportControlsState();
}

class _TransportControlsState extends State<TransportControls> {
  bool _isDragging = false;
  double _dragTime = 0;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        if (widget.state.isPlaying && !widget.state.isPaused) {
          widget.onPause?.call();
        } else {
          widget.onPlay?.call();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        widget.onStop?.call();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        widget.onLoopToggle?.call();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  double get _displayTime => _isDragging ? _dragTime : widget.state.currentTime;

  double get _progress =>
      widget.state.duration > 0 ? _displayTime / widget.state.duration : 0;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (_, event) => _handleKeyEvent(event),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: widget.compact ? 6 : 10,
        ),
        decoration: BoxDecoration(
          color: ReelForgeTheme.bgMid,
          border: Border(
            bottom: BorderSide(
              color: ReelForgeTheme.borderSubtle,
            ),
          ),
        ),
        child: Row(
          children: [
            // Transport buttons
            _buildTransportButtons(),
            const SizedBox(width: 16),

            // Time display
            _buildTimeDisplay(),
            const SizedBox(width: 16),

            // Seek bar
            Expanded(child: _buildSeekBar()),
            const SizedBox(width: 16),

            // Volume control
            _buildVolumeControl(),

            // Now playing
            if (widget.state.currentAssetId != null) ...[
              const SizedBox(width: 16),
              _buildNowPlaying(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransportButtons() {
    final isPlaying = widget.state.isPlaying && !widget.state.isPaused;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stop
        _TransportButton(
          icon: Icons.stop,
          onPressed: widget.disabled ? null : widget.onStop,
          tooltip: 'Stop (Esc)',
        ),
        const SizedBox(width: 4),

        // Play/Pause
        _TransportButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          onPressed: widget.disabled
              ? null
              : (isPlaying ? widget.onPause : widget.onPlay),
          tooltip: isPlaying ? 'Pause (Space)' : 'Play (Space)',
          active: isPlaying,
          primary: true,
        ),
        const SizedBox(width: 4),

        // Loop
        _TransportButton(
          icon: Icons.loop,
          onPressed: widget.disabled ? null : widget.onLoopToggle,
          tooltip: 'Loop (L)',
          active: widget.state.looping,
        ),
      ],
    );
  }

  Widget _buildTimeDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ReelForgeTheme.bgVoid,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatTime(_displayTime),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: ReelForgeTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            ' / ${_formatTime(widget.state.duration)}',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: ReelForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar() {
    return GestureDetector(
      onHorizontalDragStart: (details) {
        if (widget.state.duration <= 0) return;
        setState(() => _isDragging = true);
        _updateDragPosition(details.localPosition);
      },
      onHorizontalDragUpdate: (details) {
        if (!_isDragging) return;
        _updateDragPosition(details.localPosition);
      },
      onHorizontalDragEnd: (_) {
        if (_isDragging) {
          widget.onSeek?.call(_dragTime);
          setState(() => _isDragging = false);
        }
      },
      onTapDown: (details) {
        if (widget.state.duration <= 0) return;
        _updateDragPosition(details.localPosition);
        widget.onSeek?.call(_dragTime);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            height: 32,
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgVoid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Fill
                AnimatedContainer(
                  duration: _isDragging
                      ? Duration.zero
                      : const Duration(milliseconds: 50),
                  width: constraints.maxWidth * _progress.clamp(0.0, 1.0),
                  height: 32,
                  decoration: BoxDecoration(
                    color: ReelForgeTheme.accentBlue.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Thumb
                Positioned(
                  left: (constraints.maxWidth * _progress.clamp(0.0, 1.0)) - 8,
                  child: Container(
                    width: 16,
                    height: 24,
                    decoration: BoxDecoration(
                      color: ReelForgeTheme.accentBlue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _updateDragPosition(Offset localPosition) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    // Find the seek bar bounds (approximate)
    final seekBarWidth = box.size.width * 0.5; // Rough estimate
    final percent = (localPosition.dx / seekBarWidth).clamp(0.0, 1.0);
    setState(() {
      _dragTime = percent * widget.state.duration;
    });
  }

  Widget _buildVolumeControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TransportButton(
          icon: widget.state.volume <= 0
              ? Icons.volume_off
              : widget.state.volume < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
          onPressed: () {
            widget.onVolumeChange?.call(widget.state.volume > 0 ? 0 : 1);
          },
          tooltip: widget.state.volume > 0 ? 'Mute' : 'Unmute',
          small: true,
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: ReelForgeTheme.accentBlue,
              inactiveTrackColor: ReelForgeTheme.bgElevated,
              thumbColor: ReelForgeTheme.textPrimary,
            ),
            child: Slider(
              value: widget.state.volume,
              onChanged: widget.disabled ? null : widget.onVolumeChange,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNowPlaying() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          widget.state.isPlaying && !widget.state.isPaused
              ? Icons.graphic_eq
              : Icons.pause,
          size: 16,
          color: ReelForgeTheme.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          widget.state.currentAssetId!,
          style: TextStyle(
            fontSize: 12,
            color: ReelForgeTheme.textSecondary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 100).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }
}

// ============ Transport Button ============

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool active;
  final bool primary;
  final bool small;

  const _TransportButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.active = false,
    this.primary = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: small ? 28 : 36,
            height: small ? 28 : 36,
            decoration: BoxDecoration(
              color: active
                  ? ReelForgeTheme.accentBlue.withOpacity(0.2)
                  : ReelForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: active
                    ? ReelForgeTheme.accentBlue
                    : ReelForgeTheme.borderSubtle,
              ),
            ),
            child: Icon(
              icon,
              size: small ? 16 : 20,
              color: active
                  ? ReelForgeTheme.accentBlue
                  : primary
                      ? ReelForgeTheme.textPrimary
                      : ReelForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
