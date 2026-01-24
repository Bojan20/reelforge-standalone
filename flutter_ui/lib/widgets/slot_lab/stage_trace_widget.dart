/// Stage Trace Visualization Widget
///
/// Animated visual trace through stage events during spin playback:
/// - Horizontal timeline with stage markers
/// - Animated playhead that follows current stage
/// - Color-coded stage zones
/// - Pulse effects on active stages
/// - Mini progress indicator
/// - Drag & drop audio assignment to stages
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../providers/slot_lab_provider.dart';
import '../../src/rust/native_ffi.dart';
import '../../theme/fluxforge_theme.dart';
import 'audio_hover_preview.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STAGE TRACE WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class StageTraceWidget extends StatefulWidget {
  final SlotLabProvider provider;
  final double height;
  final bool showMiniProgress;
  final Function(AudioFileInfo audio, String stageType)? onAudioDropped;

  const StageTraceWidget({
    super.key,
    required this.provider,
    this.height = 80,
    this.showMiniProgress = true,
    this.onAudioDropped,
  });

  @override
  State<StageTraceWidget> createState() => _StageTraceWidgetState();
}

class _StageTraceWidgetState extends State<StageTraceWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _playheadController;
  late Animation<double> _pulseAnimation;

  List<SlotLabStageEvent> _stages = [];
  int _currentStageIndex = -1;
  double _playheadPosition = 0.0;
  bool _isPlaying = false;
  Timer? _playbackTimer;

  // Drag & drop state
  int? _hoveredStageIndex;
  bool _isDraggingOver = false;

  // Mouse hover state (separate from drag hover)
  int? _mouseHoverIndex;

  // Stage colors by type
  static const Map<String, Color> _stageColors = {
    'spin_start': Color(0xFF4A9EFF),
    'reel_spinning': Color(0xFF6B7280),
    'reel_stop': Color(0xFF8B5CF6),
    'anticipation_on': Color(0xFFFF9040),
    'anticipation_off': Color(0xFFFF9040),
    'evaluate_wins': Color(0xFF6B7280),
    'win_present': Color(0xFF40FF90),
    'win_line_show': Color(0xFF40FF90),
    'rollup_start': Color(0xFFFFD700),
    'rollup_tick': Color(0xFFFFD700),
    'rollup_end': Color(0xFFFFD700),
    'bigwin_tier': Color(0xFFFF4080),
    'feature_enter': Color(0xFF40C8FF),
    'feature_step': Color(0xFF40C8FF),
    'feature_exit': Color(0xFF40C8FF),
    'cascade_start': Color(0xFFE040FB),
    'cascade_step': Color(0xFFE040FB),
    'cascade_end': Color(0xFFE040FB),
    'jackpot_trigger': Color(0xFFFFD700),
    'jackpot_present': Color(0xFFFFD700),
    'spin_end': Color(0xFF4A9EFF),
  };

  // Stage icons by type
  static const Map<String, IconData> _stageIcons = {
    'spin_start': Icons.play_circle_outline,
    'reel_spinning': Icons.sync,
    'reel_stop': Icons.stop_circle_outlined,
    'anticipation_on': Icons.warning_amber,
    'anticipation_off': Icons.warning_amber,
    'win_present': Icons.stars,
    'rollup_start': Icons.trending_up,
    'rollup_end': Icons.check_circle_outline,
    'bigwin_tier': Icons.emoji_events,
    'feature_enter': Icons.auto_awesome,
    'jackpot_trigger': Icons.diamond,
    'spin_end': Icons.stop,
  };

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _playheadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    widget.provider.addListener(_onProviderUpdate);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderUpdate);
    _pulseController.dispose();
    _playheadController.dispose();
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;

    final newStages = widget.provider.lastStages;
    final isPlaying = widget.provider.isPlayingStages;
    final currentIndex = widget.provider.currentStageIndex;

    setState(() {
      _stages = newStages;
      _isPlaying = isPlaying;
      _currentStageIndex = currentIndex;

      if (_stages.isNotEmpty && currentIndex >= 0) {
        final totalDuration = _stages.last.timestampMs - _stages.first.timestampMs;
        if (totalDuration > 0) {
          final currentTime = _stages[currentIndex].timestampMs - _stages.first.timestampMs;
          _playheadPosition = currentTime / totalDuration;
        }
      }
    });
  }

  Color _getStageColor(String stageType) {
    return _stageColors[stageType] ?? const Color(0xFF6B7280);
  }

  IconData _getStageIcon(String stageType) {
    return _stageIcons[stageType] ?? Icons.circle;
  }

  String _formatStageName(String stageType) {
    return stageType
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          // Timeline
          Expanded(child: _buildTimeline()),
          // Mini progress
          if (widget.showMiniProgress) _buildMiniProgress(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Icon(
                Icons.timeline,
                size: 12,
                color: _isPlaying
                    ? FluxForgeTheme.accentGreen.withOpacity(_pulseAnimation.value)
                    : FluxForgeTheme.accentBlue,
              );
            },
          ),
          const SizedBox(width: 6),
          Text(
            'STAGE TRACE',
            style: TextStyle(
              color: _isPlaying ? FluxForgeTheme.accentGreen : FluxForgeTheme.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          if (_stages.isNotEmpty) ...[
            Text(
              '${_currentStageIndex + 1}/${_stages.length}',
              style: const TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 9,
              ),
            ),
            const SizedBox(width: 8),
            if (_currentStageIndex >= 0 && _currentStageIndex < _stages.length)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _getStageColor(_stages[_currentStageIndex].stageType).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: _getStageColor(_stages[_currentStageIndex].stageType),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  _formatStageName(_stages[_currentStageIndex].stageType),
                  style: TextStyle(
                    color: _getStageColor(_stages[_currentStageIndex].stageType),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ] else
            const Text(
              'No stages',
              style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 9),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    if (_stages.isEmpty) {
      // Empty state - but still accept drops for pre-assignment
      return DragTarget<AudioFileInfo>(
        onWillAcceptWithDetails: (details) {
          setState(() => _isDraggingOver = true);
          return true;
        },
        onLeave: (_) => setState(() => _isDraggingOver = false),
        onAcceptWithDetails: (details) {
          setState(() => _isDraggingOver = false);
          // Show stage selection dialog for empty timeline
          _showStageSelectionDialog(details.data);
        },
        builder: (context, candidateData, rejectedData) {
          return Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _isDraggingOver
                    ? FluxForgeTheme.accentBlue.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: _isDraggingOver
                    ? Border.all(color: FluxForgeTheme.accentBlue, width: 2)
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isDraggingOver ? Icons.add_circle : Icons.hourglass_empty,
                    size: 16,
                    color: _isDraggingOver ? FluxForgeTheme.accentBlue : Colors.white24,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isDraggingOver ? 'Drop to assign audio' : 'Spin to see stage trace',
                    style: TextStyle(
                      color: _isDraggingOver ? FluxForgeTheme.accentBlue : Colors.white38,
                      fontSize: 10,
                      fontWeight: _isDraggingOver ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth - 16;
        final totalDuration = _stages.last.timestampMs - _stages.first.timestampMs;

        return Stack(
          children: [
            // Background track with global drop zone
            Positioned(
              left: 8,
              right: 8,
              top: 20,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Stage markers with individual drop targets
            ..._stages.asMap().entries.map((entry) {
              final index = entry.key;
              final stage = entry.value;
              final position = totalDuration > 0
                  ? (stage.timestampMs - _stages.first.timestampMs) / totalDuration
                  : 0.0;
              final x = 8 + (totalWidth * position);
              final isActive = index == _currentStageIndex;
              final isPast = index < _currentStageIndex;
              final isHovered = _hoveredStageIndex == index;
              final color = _getStageColor(stage.stageType);

              return Positioned(
                left: x - 16,
                top: 4,
                child: DragTarget<AudioFileInfo>(
                  onWillAcceptWithDetails: (details) {
                    setState(() => _hoveredStageIndex = index);
                    return true;
                  },
                  onLeave: (_) => setState(() {
                    if (_hoveredStageIndex == index) _hoveredStageIndex = null;
                  }),
                  onAcceptWithDetails: (details) {
                    setState(() => _hoveredStageIndex = null);
                    widget.onAudioDropped?.call(details.data, stage.stageType);
                    _showDropFeedback(stage.stageType, details.data.name);
                  },
                  builder: (context, candidateData, rejectedData) {
                    final isDragTarget = candidateData.isNotEmpty;
                    final isMouseHovered = _mouseHoverIndex == index;

                    return MouseRegion(
                      onEnter: (_) => setState(() => _mouseHoverIndex = index),
                      onExit: (_) => setState(() {
                        if (_mouseHoverIndex == index) _mouseHoverIndex = null;
                      }),
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => widget.provider.triggerStageManually(index),
                        child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          final scale = isActive
                              ? (0.9 + 0.2 * _pulseAnimation.value)
                              : isDragTarget
                                  ? 1.2
                                  : 1.0;
                          final opacity = isPast ? 0.5 : 1.0;

                          return Transform.scale(
                            scale: scale,
                            child: Opacity(
                              opacity: opacity,
                              child: Column(
                                children: [
                                  // Stage dot/icon with drop indicator and play button
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 150),
                                        width: isDragTarget ? 28 : (isMouseHovered ? 24 : 20),
                                        height: isDragTarget ? 28 : (isMouseHovered ? 24 : 20),
                                        decoration: BoxDecoration(
                                          color: isDragTarget
                                              ? FluxForgeTheme.accentGreen.withOpacity(0.8)
                                              : isMouseHovered
                                                  ? color.withOpacity(0.8)
                                                  : isActive
                                                      ? color
                                                      : color.withOpacity(0.3),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isDragTarget
                                                ? FluxForgeTheme.accentGreen
                                                : isMouseHovered
                                                    ? Colors.white
                                                    : color,
                                            width: isDragTarget ? 3 : (isActive || isMouseHovered ? 2 : 1),
                                          ),
                                          boxShadow: (isActive || isDragTarget || isMouseHovered)
                                              ? [
                                                  BoxShadow(
                                                    color: (isDragTarget
                                                            ? FluxForgeTheme.accentGreen
                                                            : color)
                                                        .withOpacity(0.6),
                                                    blurRadius: isDragTarget ? 12 : (isMouseHovered ? 10 : 8),
                                                    spreadRadius: isDragTarget ? 4 : (isMouseHovered ? 3 : 2),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Icon(
                                          isDragTarget
                                              ? Icons.add
                                              : isMouseHovered
                                                  ? Icons.play_arrow  // Play button on hover
                                                  : _getStageIcon(stage.stageType),
                                          size: isDragTarget ? 14 : (isMouseHovered ? 14 : 10),
                                          color: isDragTarget
                                              ? Colors.white
                                              : isMouseHovered
                                                  ? Colors.white
                                                  : (isActive ? Colors.white : color),
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Connector line
                                  Container(
                                    width: 1,
                                    height: isDragTarget ? 8 : 6,
                                    color: (isDragTarget ? FluxForgeTheme.accentGreen : color)
                                        .withOpacity(isDragTarget ? 0.8 : 0.5),
                                  ),
                                  // Drop hint label
                                  if (isDragTarget)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: FluxForgeTheme.accentGreen,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        _formatStageName(stage.stageType),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 7,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                        ),
                      ),
                    );
                  },
                ),
              );
            }),

            // Playhead
            if (_isPlaying)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 50),
                left: 8 + (totalWidth * _playheadPosition) - 1,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentGreen,
                    boxShadow: [
                      BoxShadow(
                        color: FluxForgeTheme.accentGreen.withOpacity(0.5),
                        blurRadius: 4,
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

  void _showDropFeedback(String stageType, String audioName) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: FluxForgeTheme.accentGreen, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Assigned "$audioName" to ${_formatStageName(stageType)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        backgroundColor: FluxForgeTheme.bgMid,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showStageSelectionDialog(AudioFileInfo audio) {
    if (!mounted) return;

    // Common stage types for pre-assignment
    final commonStages = [
      'spin_start',
      'reel_stop',
      'win_present',
      'bigwin_tier',
      'rollup_start',
      'feature_enter',
      'jackpot_trigger',
      'anticipation_on',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.audiotrack, color: FluxForgeTheme.accentBlue),
            const SizedBox(width: 8),
            Text(
              'Assign Audio',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assign "${audio.name}" to stage:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: commonStages.map((stage) {
                  final color = _getStageColor(stage);
                  return InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      widget.onAudioDropped?.call(audio, stage);
                      _showDropFeedback(stage, audio.name);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getStageIcon(stage), size: 12, color: color),
                          const SizedBox(width: 4),
                          Text(
                            _formatStageName(stage),
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniProgress() {
    return Container(
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          // Stage type chips
          if (_stages.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _getUniqueStageTypes().map((type) {
                    final color = _getStageColor(type);
                    final isActive = _currentStageIndex >= 0 &&
                        _currentStageIndex < _stages.length &&
                        _stages[_currentStageIndex].stageType == type;

                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: isActive ? color.withOpacity(0.3) : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color: color.withOpacity(isActive ? 1.0 : 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          type.replaceAll('_', '').substring(0, 3).toUpperCase(),
                          style: TextStyle(
                            color: color.withOpacity(isActive ? 1.0 : 0.5),
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<String> _getUniqueStageTypes() {
    final types = <String>[];
    for (final stage in _stages) {
      if (!types.contains(stage.stageType)) {
        types.add(stage.stageType);
      }
    }
    return types;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// COMPACT STAGE PROGRESS BAR
// ═══════════════════════════════════════════════════════════════════════════

/// Compact horizontal stage progress bar for header/footer use
class StageProgressBar extends StatelessWidget {
  final SlotLabProvider provider;
  final double height;

  const StageProgressBar({
    super.key,
    required this.provider,
    this.height = 24,
  });

  static const Map<String, Color> _stageColors = {
    'spin_start': Color(0xFF4A9EFF),
    'reel_stop': Color(0xFF8B5CF6),
    'anticipation_on': Color(0xFFFF9040),
    'win_present': Color(0xFF40FF90),
    'rollup_start': Color(0xFFFFD700),
    'bigwin_tier': Color(0xFFFF4080),
    'feature_enter': Color(0xFF40C8FF),
    'jackpot_trigger': Color(0xFFFFD700),
    'spin_end': Color(0xFF4A9EFF),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, child) {
        final stages = provider.lastStages;
        final currentIndex = provider.currentStageIndex;
        final isPlaying = provider.isPlayingStages;

        if (stages.isEmpty) {
          return SizedBox(height: height);
        }

        return Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isPlaying ? FluxForgeTheme.accentGreen : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),

              // Stage segments
              Expanded(
                child: Row(
                  children: stages.asMap().entries.map((entry) {
                    final index = entry.key;
                    final stage = entry.value;
                    final color = _stageColors[stage.stageType] ?? Colors.grey;
                    final isActive = index == currentIndex;
                    final isPast = index < currentIndex;

                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 0.5),
                        decoration: BoxDecoration(
                          color: isActive
                              ? color
                              : isPast
                                  ? color.withOpacity(0.6)
                                  : color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(width: 8),

              // Current stage label
              if (currentIndex >= 0 && currentIndex < stages.length)
                Text(
                  stages[currentIndex].stageType.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: _stageColors[stages[currentIndex].stageType] ?? Colors.grey,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
