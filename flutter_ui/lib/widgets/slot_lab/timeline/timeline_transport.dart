// Timeline Transport Controls — Playback Control Bar
//
// Professional transport controls:
// - Play/Pause/Stop/Loop buttons
// - Playhead time display
// - Grid/Snap controls
// - Zoom controls

import 'package:flutter/material.dart';
import '../../../models/timeline/timeline_state.dart';

class TimelineTransport extends StatelessWidget {
  final bool isPlaying;
  final bool isLooping;
  final bool snapEnabled;
  final double playheadPosition;
  final TimeDisplayMode timeDisplayMode;
  final GridMode gridMode;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onStop;
  final VoidCallback? onToggleLoop;
  final VoidCallback? onToggleSnap;
  final Function(GridMode mode)? onGridModeChanged;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomToFit;

  const TimelineTransport({
    super.key,
    required this.isPlaying,
    required this.isLooping,
    required this.snapEnabled,
    required this.playheadPosition,
    this.timeDisplayMode = TimeDisplayMode.seconds,
    this.gridMode = GridMode.millisecond,
    this.onPlay,
    this.onPause,
    this.onStop,
    this.onToggleLoop,
    this.onToggleSnap,
    this.onGridModeChanged,
    this.onZoomIn,
    this.onZoomOut,
    this.onZoomToFit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          // Play/Pause
          IconButton(
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            iconSize: 18,
            color: const Color(0xFF40FF90),
            onPressed: isPlaying ? onPause : onPlay,
            tooltip: 'Play/Pause (Space)',
          ),

          // Stop
          IconButton(
            icon: const Icon(Icons.stop),
            iconSize: 18,
            color: const Color(0xFFFF4060),
            onPressed: onStop,
            tooltip: 'Stop (0)',
          ),

          // Loop
          IconButton(
            icon: const Icon(Icons.repeat),
            iconSize: 18,
            color: isLooping ? const Color(0xFFFF9040) : Colors.white54,
            onPressed: onToggleLoop,
            tooltip: 'Loop (L)',
          ),

          const SizedBox(width: 16),
          const VerticalDivider(width: 1, color: Color(0xFF2A2A35)),
          const SizedBox(width: 16),

          // Playhead time display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A22),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(
              _formatTime(playheadPosition, timeDisplayMode),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),

          const Spacer(),

          // Snap toggle
          IconButton(
            icon: Icon(
              snapEnabled ? Icons.grid_on : Icons.grid_off,
              size: 16,
              color: snapEnabled ? const Color(0xFF40FF90) : Colors.white38,
            ),
            onPressed: onToggleSnap,
            tooltip: 'Snap to Grid (G)',
          ),

          // Grid mode selector
          PopupMenuButton<GridMode>(
            icon: const Icon(Icons.grid_4x4, size: 16, color: Colors.white54),
            tooltip: 'Grid Mode (Shift+G)',
            onSelected: onGridModeChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(value: GridMode.millisecond, child: Text('Milliseconds')),
              PopupMenuItem(value: GridMode.frame, child: Text('Frames')),
              PopupMenuItem(value: GridMode.beat, child: Text('Beats')),
              PopupMenuItem(value: GridMode.free, child: Text('Free')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A22),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _gridModeName(gridMode),
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white54),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),
          const VerticalDivider(width: 1, color: Color(0xFF2A2A35)),
          const SizedBox(width: 8),

          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_in),
            iconSize: 16,
            color: Colors.white54,
            onPressed: onZoomIn,
            tooltip: 'Zoom In (Cmd/Ctrl + =)',
          ),

          IconButton(
            icon: const Icon(Icons.zoom_out),
            iconSize: 16,
            color: Colors.white54,
            onPressed: onZoomOut,
            tooltip: 'Zoom Out (Cmd/Ctrl + -)',
          ),

          IconButton(
            icon: const Icon(Icons.fit_screen),
            iconSize: 16,
            color: Colors.white54,
            onPressed: onZoomToFit,
            tooltip: 'Zoom to Fit (Cmd/Ctrl + 0)',
          ),
        ],
      ),
    );
  }

  String _formatTime(double timeSeconds, TimeDisplayMode mode) {
    switch (mode) {
      case TimeDisplayMode.milliseconds:
        return '${(timeSeconds * 1000).toInt()}ms';
      case TimeDisplayMode.seconds:
        return '${timeSeconds.toStringAsFixed(3)}s';
      case TimeDisplayMode.beats:
        return '1.1.1';
      case TimeDisplayMode.timecode:
        final minutes = (timeSeconds ~/ 60);
        final seconds = (timeSeconds % 60).floor();
        final frames = ((timeSeconds % 1) * 60).floor();
        return '${minutes.toString().padLeft(2, '0')}:'
            '${seconds.toString().padLeft(2, '0')}:'
            '${frames.toString().padLeft(2, '0')}';
    }
  }

  String _gridModeName(GridMode mode) {
    switch (mode) {
      case GridMode.millisecond:
        return 'ms';
      case GridMode.frame:
        return 'frames';
      case GridMode.beat:
        return 'beats';
      case GridMode.free:
        return 'free';
    }
  }
}
