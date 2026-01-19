/// Playback Section Indicator Widget
///
/// Shows which section currently controls playback and interruption status.
/// Part of the Unified Playback System (Phase 3).
///
/// Usage:
/// ```dart
/// PlaybackSectionIndicator(
///   currentSection: PlaybackSection.daw,
///   showInterruptionBanner: true,
/// )
/// ```

import 'package:flutter/material.dart';
import '../../services/unified_playback_controller.dart';

// =============================================================================
// PLAYBACK SECTION INDICATOR
// =============================================================================

/// Compact indicator showing active playback section
class PlaybackSectionIndicator extends StatelessWidget {
  /// Which section this indicator belongs to
  final PlaybackSection currentSection;

  /// Whether to show "Paused by X" banner when interrupted
  final bool showInterruptionBanner;

  /// Custom colors (optional)
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? interruptedColor;

  const PlaybackSectionIndicator({
    super.key,
    required this.currentSection,
    this.showInterruptionBanner = true,
    this.activeColor,
    this.inactiveColor,
    this.interruptedColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UnifiedPlaybackController.instance,
      builder: (context, _) {
        final controller = UnifiedPlaybackController.instance;
        final isActive = controller.activeSection == currentSection;
        final wasInterrupted = controller.wasSectionInterrupted(currentSection);
        final interruptingSection = controller.getInterruptingSection(currentSection);

        // Colors
        final active = activeColor ?? const Color(0xFF40FF90);
        final inactive = inactiveColor ?? const Color(0xFF666666);
        final interrupted = interruptedColor ?? const Color(0xFFFF9040);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status dot with label
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? active
                        : wasInterrupted
                            ? interrupted
                            : inactive,
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: active.withValues(alpha: 0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                // Status label
                Text(
                  isActive
                      ? 'Active'
                      : wasInterrupted
                          ? 'Paused'
                          : 'Idle',
                  style: TextStyle(
                    fontSize: 11,
                    color: isActive
                        ? active
                        : wasInterrupted
                            ? interrupted
                            : inactive,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),

            // Interruption banner
            if (showInterruptionBanner && wasInterrupted && interruptingSection != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: interrupted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: interrupted.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.pause_circle_outline,
                        size: 14,
                        color: interrupted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Paused by ${_sectionName(interruptingSection)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: interrupted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Dismiss button
                      GestureDetector(
                        onTap: () {
                          UnifiedPlaybackController.instance.clearInterruption();
                        },
                        child: Icon(
                          Icons.close,
                          size: 12,
                          color: interrupted.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _sectionName(PlaybackSection section) {
    return switch (section) {
      PlaybackSection.daw => 'DAW',
      PlaybackSection.slotLab => 'Slot Lab',
      PlaybackSection.middleware => 'Middleware',
      PlaybackSection.browser => 'Browser',
    };
  }
}

// =============================================================================
// GLOBAL PLAYBACK STATUS BAR
// =============================================================================

/// Full-width status bar showing global playback state
class GlobalPlaybackStatusBar extends StatelessWidget {
  const GlobalPlaybackStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UnifiedPlaybackController.instance,
      builder: (context, _) {
        final controller = UnifiedPlaybackController.instance;
        final activeSection = controller.activeSection;
        final isPlaying = controller.isPlaying;
        final isRecording = controller.isRecording;

        // Colors
        const active = Color(0xFF40FF90);
        const recording = Color(0xFFFF4040);
        const idle = Color(0xFF444444);

        return Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A20),
            border: Border(
              bottom: BorderSide(
                color: isRecording
                    ? recording.withValues(alpha: 0.5)
                    : isPlaying
                        ? active.withValues(alpha: 0.3)
                        : idle,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Playback state icon
              Icon(
                isRecording
                    ? Icons.fiber_manual_record
                    : isPlaying
                        ? Icons.play_arrow
                        : Icons.stop,
                size: 14,
                color: isRecording
                    ? recording
                    : isPlaying
                        ? active
                        : idle,
              ),
              const SizedBox(width: 6),

              // Status text
              Text(
                isRecording
                    ? 'Recording'
                    : isPlaying
                        ? 'Playing'
                        : 'Stopped',
                style: TextStyle(
                  fontSize: 11,
                  color: isRecording
                      ? recording
                      : isPlaying
                          ? active
                          : const Color(0xFF888888),
                  fontWeight: FontWeight.w500,
                ),
              ),

              // Active section
              if (activeSection != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A9EFF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _sectionName(activeSection),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF4A9EFF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              const Spacer(),

              // Position display
              Text(
                _formatTime(controller.position),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF888888),
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _sectionName(PlaybackSection section) {
    return switch (section) {
      PlaybackSection.daw => 'DAW',
      PlaybackSection.slotLab => 'Slot Lab',
      PlaybackSection.middleware => 'Middleware',
      PlaybackSection.browser => 'Browser',
    };
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    final ms = ((seconds % 1) * 100).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${ms.toString().padLeft(2, '0')}';
  }
}

// =============================================================================
// SECTION CONTROL BUTTON
// =============================================================================

/// Play/Pause button that respects section ownership
class SectionPlayButton extends StatelessWidget {
  final PlaybackSection section;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final double size;

  const SectionPlayButton({
    super.key,
    required this.section,
    this.onPlay,
    this.onPause,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UnifiedPlaybackController.instance,
      builder: (context, _) {
        final controller = UnifiedPlaybackController.instance;
        final isThisSectionActive = controller.activeSection == section;
        final isPlaying = controller.isPlaying && isThisSectionActive;

        return IconButton(
          iconSize: size,
          icon: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: isThisSectionActive
                ? const Color(0xFF40FF90)
                : const Color(0xFFCCCCCC),
          ),
          onPressed: () {
            if (isPlaying) {
              onPause?.call();
            } else {
              onPlay?.call();
            }
          },
        );
      },
    );
  }
}
