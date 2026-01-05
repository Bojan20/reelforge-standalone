/// Tab Placeholder Widgets
///
/// Placeholder widgets for all lower zone tabs.
/// To be replaced with full implementations.

import 'package:flutter/material.dart';
import '../../theme/reelforge_theme.dart';

/// Base placeholder widget
class _TabPlaceholder extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;
  final Color? accentColor;

  const _TabPlaceholder({
    required this.title,
    required this.icon,
    required this.description,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 48,
              color: accentColor ?? ReelForgeTheme.accentBlue,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ReelForgeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: ReelForgeTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ DAW Mode Tabs ============

/// Timeline tab placeholder
class TimelineTabPlaceholder extends StatelessWidget {
  const TimelineTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(
      title: 'Timeline',
      icon: Icons.view_timeline,
      description: 'Arrange clips on timeline tracks',
    );
  }
}

/// Clip Editor tab placeholder
class ClipEditorTabPlaceholder extends StatelessWidget {
  const ClipEditorTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(
      title: 'Clip Editor',
      icon: Icons.edit,
      description: 'Edit waveforms, fades, and clip properties',
    );
  }
}

/// Layered Music tab placeholder
class LayeredMusicTabPlaceholder extends StatelessWidget {
  const LayeredMusicTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(
      title: 'Layered Music',
      icon: Icons.layers,
      description: 'Create interactive layered music systems',
    );
  }
}

// ============ Slot Mode Tabs ============

/// Spin Cycle tab placeholder
class SpinCycleTabPlaceholder extends StatelessWidget {
  const SpinCycleTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return _TabPlaceholder(
      title: 'Spin Cycle',
      icon: Icons.casino,
      description: 'Configure spin cycle audio states',
      accentColor: ReelForgeTheme.warningOrange,
    );
  }
}

/// Win Tiers tab placeholder
class WinTiersTabPlaceholder extends StatelessWidget {
  const WinTiersTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return _TabPlaceholder(
      title: 'Win Tiers',
      icon: Icons.emoji_events,
      description: 'Configure win celebration audio tiers',
      accentColor: ReelForgeTheme.warningOrange,
    );
  }
}

/// Reel Sequencer tab placeholder
class ReelSequencerTabPlaceholder extends StatelessWidget {
  const ReelSequencerTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return _TabPlaceholder(
      title: 'Reel Sequencer',
      icon: Icons.timer,
      description: 'Sequence reel stop timing and sounds',
      accentColor: ReelForgeTheme.warningOrange,
    );
  }
}

/// Slot Studio tab placeholder
class SlotStudioTabPlaceholder extends StatelessWidget {
  const SlotStudioTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return _TabPlaceholder(
      title: 'Slot Studio',
      icon: Icons.headphones,
      description: 'Comprehensive slot audio workspace',
      accentColor: ReelForgeTheme.warningOrange,
    );
  }
}

// ============ DSP Tabs ============

/// Sidechain tab placeholder
class SidechainTabPlaceholder extends StatelessWidget {
  const SidechainTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return _TabPlaceholder(
      title: 'Sidechain Router',
      icon: Icons.link,
      description: 'Configure sidechain routing between buses',
      accentColor: ReelForgeTheme.accentCyan,
    );
  }
}

/// Multiband Compressor tab placeholder
class MultibandTabPlaceholder extends StatelessWidget {
  const MultibandTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return _TabPlaceholder(
      title: 'Multiband Compressor',
      icon: Icons.equalizer,
      description: 'Multi-band dynamics processing',
      accentColor: ReelForgeTheme.accentCyan,
    );
  }
}

/// FX Presets tab placeholder
class FXPresetsTabPlaceholder extends StatelessWidget {
  const FXPresetsTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return _TabPlaceholder(
      title: 'FX Presets',
      icon: Icons.auto_fix_high,
      description: 'Browse and apply effect presets',
      accentColor: ReelForgeTheme.accentCyan,
    );
  }
}

// ============ Media Tabs ============

/// Audio Browser tab placeholder
class AudioBrowserTabPlaceholder extends StatelessWidget {
  const AudioBrowserTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(
      title: 'Audio Browser',
      icon: Icons.folder_open,
      description: 'Browse and import audio files',
    );
  }
}

/// Audio Pool tab placeholder
class AudioPoolTabPlaceholder extends StatelessWidget {
  const AudioPoolTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(
      title: 'Audio Pool',
      icon: Icons.library_music,
      description: 'Manage project audio assets',
    );
  }
}

// ============ Common Tabs ============

/// Console tab placeholder
class ConsoleTabPlaceholder extends StatelessWidget {
  final List<String> messages;
  final VoidCallback? onClear;

  const ConsoleTabPlaceholder({
    super.key,
    this.messages = const [],
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeepest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Console toolbar
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: ReelForgeTheme.bgMid,
              border: Border(
                bottom: BorderSide(color: ReelForgeTheme.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Console',
                  style: TextStyle(
                    fontSize: 11,
                    color: ReelForgeTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                if (onClear != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 14),
                    onPressed: onClear,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    color: ReelForgeTheme.textSecondary,
                  ),
              ],
            ),
          ),
          // Console content
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages',
                      style: TextStyle(
                        fontSize: 12,
                        color: ReelForgeTheme.textTertiary,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          messages[index],
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: ReelForgeTheme.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Validation tab placeholder
class ValidationTabPlaceholder extends StatelessWidget {
  const ValidationTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ReelForgeTheme.bgDeep,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: ReelForgeTheme.accentGreen,
            ),
            const SizedBox(height: 16),
            Text(
              'Project Validation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ReelForgeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No issues found',
              style: TextStyle(
                fontSize: 12,
                color: ReelForgeTheme.accentGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ Feature Tabs ============

/// Audio Features tab placeholder
class AudioFeaturesTabPlaceholder extends StatelessWidget {
  const AudioFeaturesTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(
      title: 'Audio Features',
      icon: Icons.tune,
      description: 'Configure audio processing features',
    );
  }
}

/// Pro Features tab placeholder
class ProFeaturesTabPlaceholder extends StatelessWidget {
  const ProFeaturesTabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return _TabPlaceholder(
      title: 'Pro Features',
      icon: Icons.star,
      description: 'Advanced professional audio tools',
      accentColor: ReelForgeTheme.warningOrange,
    );
  }
}

// ============ Debug/Demo Tabs ============

/// Drag & Drop Lab placeholder
class DragDropLabPlaceholder extends StatelessWidget {
  const DragDropLabPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(
      title: 'Drag & Drop Lab',
      icon: Icons.pan_tool,
      description: 'Test drag and drop functionality',
    );
  }
}

/// Loading States placeholder
class LoadingStatesPlaceholder extends StatelessWidget {
  const LoadingStatesPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _TabPlaceholder(
      title: 'Loading States',
      icon: Icons.hourglass_empty,
      description: 'Demo loading state animations',
    );
  }
}
