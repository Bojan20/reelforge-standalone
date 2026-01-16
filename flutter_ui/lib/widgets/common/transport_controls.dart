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
import '../../theme/fluxforge_theme.dart';

// ============ Types ============

class TransportState {
  final bool isPlaying;
  final bool isPaused;
  final double currentTime;
  final double duration;
  final bool looping;
  final double volume;
  final String? currentAssetId;

  // ═══════════════════════════════════════════════════════════════════════════
  // PRO DAW FEATURES: Metronome, Pre-roll, Count-in, Tempo
  // ═══════════════════════════════════════════════════════════════════════════
  final bool metronomeEnabled;
  final double metronomeVolume;
  final bool preRollEnabled;
  final int preRollBars;
  final bool countInEnabled;
  final int countInBars;
  final double tempo;
  final bool isRecording;

  const TransportState({
    this.isPlaying = false,
    this.isPaused = false,
    this.currentTime = 0,
    this.duration = 60,
    this.looping = false,
    this.volume = 1,
    this.currentAssetId,
    // Pro features
    this.metronomeEnabled = false,
    this.metronomeVolume = 0.8,
    this.preRollEnabled = false,
    this.preRollBars = 2,
    this.countInEnabled = false,
    this.countInBars = 1,
    this.tempo = 120.0,
    this.isRecording = false,
  });

  TransportState copyWith({
    bool? isPlaying,
    bool? isPaused,
    double? currentTime,
    double? duration,
    bool? looping,
    double? volume,
    String? currentAssetId,
    bool? metronomeEnabled,
    double? metronomeVolume,
    bool? preRollEnabled,
    int? preRollBars,
    bool? countInEnabled,
    int? countInBars,
    double? tempo,
    bool? isRecording,
  }) {
    return TransportState(
      isPlaying: isPlaying ?? this.isPlaying,
      isPaused: isPaused ?? this.isPaused,
      currentTime: currentTime ?? this.currentTime,
      duration: duration ?? this.duration,
      looping: looping ?? this.looping,
      volume: volume ?? this.volume,
      currentAssetId: currentAssetId ?? this.currentAssetId,
      metronomeEnabled: metronomeEnabled ?? this.metronomeEnabled,
      metronomeVolume: metronomeVolume ?? this.metronomeVolume,
      preRollEnabled: preRollEnabled ?? this.preRollEnabled,
      preRollBars: preRollBars ?? this.preRollBars,
      countInEnabled: countInEnabled ?? this.countInEnabled,
      countInBars: countInBars ?? this.countInBars,
      tempo: tempo ?? this.tempo,
      isRecording: isRecording ?? this.isRecording,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // PRO DAW CALLBACKS
  // ═══════════════════════════════════════════════════════════════════════════
  final VoidCallback? onMetronomeToggle;
  final ValueChanged<double>? onMetronomeVolumeChange;
  final VoidCallback? onPreRollToggle;
  final VoidCallback? onCountInToggle;
  final ValueChanged<double>? onTempoChange;
  final VoidCallback? onTapTempo;
  final VoidCallback? onRecord;

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
    // Pro callbacks
    this.onMetronomeToggle,
    this.onMetronomeVolumeChange,
    this.onPreRollToggle,
    this.onCountInToggle,
    this.onTempoChange,
    this.onTapTempo,
    this.onRecord,
  });

  @override
  State<TransportControls> createState() => _TransportControlsState();
}

class _TransportControlsState extends State<TransportControls> {
  bool _isDragging = false;
  double _dragTime = 0;
  final FocusNode _focusNode = FocusNode();

  // Tap Tempo tracking
  final List<DateTime> _tapTimes = [];
  static const int _maxTaps = 4;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Handle tap tempo — calculate BPM from tap intervals
  void _handleTapTempo() {
    final now = DateTime.now();

    // Remove old taps (older than 2 seconds)
    _tapTimes.removeWhere((t) => now.difference(t).inMilliseconds > 2000);

    _tapTimes.add(now);

    if (_tapTimes.length >= 2) {
      // Calculate average interval
      double totalMs = 0;
      for (int i = 1; i < _tapTimes.length; i++) {
        totalMs += _tapTimes[i].difference(_tapTimes[i - 1]).inMilliseconds;
      }
      final avgMs = totalMs / (_tapTimes.length - 1);
      final bpm = 60000.0 / avgMs;

      // Clamp to reasonable range
      final clampedBpm = bpm.clamp(20.0, 300.0);
      widget.onTempoChange?.call(clampedBpm);
    }

    // Keep only last N taps
    while (_tapTimes.length > _maxTaps) {
      _tapTimes.removeAt(0);
    }

    widget.onTapTempo?.call();
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
      case LogicalKeyboardKey.keyM:
        widget.onMetronomeToggle?.call();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        widget.onRecord?.call();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyT:
        _handleTapTempo();
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
          color: FluxForgeTheme.bgMid,
          border: Border(
            bottom: BorderSide(
              color: FluxForgeTheme.borderSubtle,
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
            const SizedBox(width: 12),

            // Tempo display with tap tempo
            _buildTempoDisplay(),
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
    final isRecording = widget.state.isRecording;

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

        // Record
        _TransportButton(
          icon: Icons.fiber_manual_record,
          onPressed: widget.disabled ? null : widget.onRecord,
          tooltip: 'Record (R)',
          active: isRecording,
          recordButton: true,
        ),
        const SizedBox(width: 4),

        // Loop
        _TransportButton(
          icon: Icons.loop,
          onPressed: widget.disabled ? null : widget.onLoopToggle,
          tooltip: 'Loop (L)',
          active: widget.state.looping,
        ),
        const SizedBox(width: 8),

        // Separator
        Container(width: 1, height: 24, color: FluxForgeTheme.borderSubtle),
        const SizedBox(width: 8),

        // Metronome
        _TransportButton(
          icon: Icons.timer,
          onPressed: widget.disabled ? null : widget.onMetronomeToggle,
          tooltip: 'Metronome (M)',
          active: widget.state.metronomeEnabled,
          small: true,
        ),
        const SizedBox(width: 4),

        // Pre-roll
        _TransportButton(
          icon: Icons.skip_previous,
          onPressed: widget.disabled ? null : widget.onPreRollToggle,
          tooltip: 'Pre-roll (${widget.state.preRollBars} bars)',
          active: widget.state.preRollEnabled,
          small: true,
        ),
        const SizedBox(width: 4),

        // Count-in
        _TransportButton(
          icon: Icons.timer_outlined,
          onPressed: widget.disabled ? null : widget.onCountInToggle,
          tooltip: 'Count-in (${widget.state.countInBars} bars)',
          active: widget.state.countInEnabled,
          small: true,
        ),
      ],
    );
  }

  Widget _buildTimeDisplay() {
    final isRecording = widget.state.isRecording;
    final timeColor = isRecording ? FluxForgeTheme.accentRed : FluxForgeTheme.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isRecording
            ? FluxForgeTheme.accentRed.withValues(alpha: 0.15)
            : FluxForgeTheme.bgVoid,
        borderRadius: BorderRadius.circular(4),
        border: isRecording
            ? Border.all(color: FluxForgeTheme.accentRed.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Recording indicator
          if (isRecording) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: FluxForgeTheme.accentRed,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            _formatTime(_displayTime),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: timeColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            ' / ${_formatTime(widget.state.duration)}',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Tempo display with tap tempo button
  Widget _buildTempoDisplay() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Tempo value (editable on tap)
        GestureDetector(
          onTap: _handleTapTempo,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgVoid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.speed,
                  size: 14,
                  color: FluxForgeTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  '${widget.state.tempo.toStringAsFixed(1)} BPM',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: FluxForgeTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),

        // Tap tempo button
        Tooltip(
          message: 'Tap Tempo (T)',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _handleTapTempo,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.bgSurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: FluxForgeTheme.borderSubtle),
                ),
                child: Text(
                  'TAP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: FluxForgeTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
              color: FluxForgeTheme.bgVoid,
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
                    color: FluxForgeTheme.accentBlue.withOpacity(0.3),
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
                      color: FluxForgeTheme.accentBlue,
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
              activeTrackColor: FluxForgeTheme.accentBlue,
              inactiveTrackColor: FluxForgeTheme.bgElevated,
              thumbColor: FluxForgeTheme.textPrimary,
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
          color: FluxForgeTheme.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          widget.state.currentAssetId!,
          style: TextStyle(
            fontSize: 12,
            color: FluxForgeTheme.textSecondary,
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
  final bool recordButton;

  const _TransportButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.active = false,
    this.primary = false,
    this.small = false,
    this.recordButton = false,
  });

  @override
  Widget build(BuildContext context) {
    // Record button uses red accent color
    final accentColor = recordButton ? FluxForgeTheme.accentRed : FluxForgeTheme.accentBlue;

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
                  ? accentColor.withValues(alpha: 0.2)
                  : FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: active ? accentColor : FluxForgeTheme.borderSubtle,
              ),
            ),
            child: Icon(
              icon,
              size: small ? 16 : 20,
              color: active
                  ? accentColor
                  : recordButton
                      ? FluxForgeTheme.accentRed.withValues(alpha: 0.6)
                      : primary
                          ? FluxForgeTheme.textPrimary
                          : FluxForgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
