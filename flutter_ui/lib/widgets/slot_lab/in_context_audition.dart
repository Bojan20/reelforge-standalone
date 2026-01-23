/// In-Context Auditioning Panel
///
/// Audition audio events within simulated slot gameplay context:
/// - Timeline presets (spin, win, big win, free spins)
/// - A/B comparison mode
/// - Playhead scrubbing
/// - Visual timeline with stage markers

import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/fluxforge_theme.dart';

/// Audition context presets
enum AuditionContext {
  spin('Spin', Icons.refresh, Duration(milliseconds: 2500)),
  smallWin('Small Win', Icons.star_border, Duration(milliseconds: 3500)),
  bigWin('Big Win', Icons.star, Duration(milliseconds: 6000)),
  megaWin('Mega Win', Icons.auto_awesome, Duration(milliseconds: 10000)),
  freeSpins('Free Spins', Icons.card_giftcard, Duration(milliseconds: 15000)),
  cascade('Cascade', Icons.waterfall_chart, Duration(milliseconds: 5000)),
  bonus('Bonus', Icons.celebration, Duration(milliseconds: 8000));

  final String label;
  final IconData icon;
  final Duration defaultDuration;

  const AuditionContext(this.label, this.icon, this.defaultDuration);
}

/// Stage event in the audition timeline
class AuditionStage {
  final String stageName;
  final Duration offset;
  final Duration duration;
  final Color color;

  const AuditionStage({
    required this.stageName,
    required this.offset,
    this.duration = const Duration(milliseconds: 100),
    this.color = Colors.blue,
  });
}

/// Timeline data for a context
class AuditionTimeline {
  final AuditionContext context;
  final List<AuditionStage> stages;
  final Duration totalDuration;

  const AuditionTimeline({
    required this.context,
    required this.stages,
    required this.totalDuration,
  });

  /// Generate timeline for a context
  factory AuditionTimeline.forContext(AuditionContext context) {
    switch (context) {
      case AuditionContext.spin:
        return AuditionTimeline(
          context: context,
          totalDuration: context.defaultDuration,
          stages: [
            AuditionStage(
              stageName: 'SPIN_START',
              offset: Duration.zero,
              color: Colors.green,
            ),
            AuditionStage(
              stageName: 'REEL_SPIN',
              offset: const Duration(milliseconds: 100),
              duration: const Duration(milliseconds: 1500),
              color: Colors.blue,
            ),
            AuditionStage(
              stageName: 'REEL_STOP_0',
              offset: const Duration(milliseconds: 1600),
              color: Colors.orange,
            ),
            AuditionStage(
              stageName: 'REEL_STOP_1',
              offset: const Duration(milliseconds: 1800),
              color: Colors.orange,
            ),
            AuditionStage(
              stageName: 'REEL_STOP_2',
              offset: const Duration(milliseconds: 2000),
              color: Colors.orange,
            ),
            AuditionStage(
              stageName: 'SPIN_END',
              offset: const Duration(milliseconds: 2400),
              color: Colors.green,
            ),
          ],
        );
      case AuditionContext.smallWin:
        return AuditionTimeline(
          context: context,
          totalDuration: context.defaultDuration,
          stages: [
            AuditionStage(
              stageName: 'WIN_PRESENT',
              offset: Duration.zero,
              color: Colors.amber,
            ),
            AuditionStage(
              stageName: 'WIN_LINE_SHOW',
              offset: const Duration(milliseconds: 200),
              color: Colors.amber,
            ),
            AuditionStage(
              stageName: 'ROLLUP_START',
              offset: const Duration(milliseconds: 500),
              color: Colors.green,
            ),
            AuditionStage(
              stageName: 'ROLLUP_TICK',
              offset: const Duration(milliseconds: 800),
              duration: const Duration(milliseconds: 2000),
              color: Colors.green,
            ),
            AuditionStage(
              stageName: 'ROLLUP_END',
              offset: const Duration(milliseconds: 3000),
              color: Colors.green,
            ),
          ],
        );
      case AuditionContext.bigWin:
        return AuditionTimeline(
          context: context,
          totalDuration: context.defaultDuration,
          stages: [
            AuditionStage(
              stageName: 'BIGWIN_START',
              offset: Duration.zero,
              color: Colors.amber,
            ),
            AuditionStage(
              stageName: 'BIGWIN_MUSIC',
              offset: const Duration(milliseconds: 200),
              duration: const Duration(milliseconds: 4000),
              color: Colors.purple,
            ),
            AuditionStage(
              stageName: 'ROLLUP_START',
              offset: const Duration(milliseconds: 500),
              color: Colors.green,
            ),
            AuditionStage(
              stageName: 'ROLLUP_TICK',
              offset: const Duration(milliseconds: 800),
              duration: const Duration(milliseconds: 4000),
              color: Colors.green,
            ),
            AuditionStage(
              stageName: 'BIGWIN_END',
              offset: const Duration(milliseconds: 5500),
              color: Colors.amber,
            ),
          ],
        );
      case AuditionContext.megaWin:
        return AuditionTimeline(
          context: context,
          totalDuration: context.defaultDuration,
          stages: [
            AuditionStage(
              stageName: 'MEGAWIN_START',
              offset: Duration.zero,
              color: Colors.deepPurple,
            ),
            AuditionStage(
              stageName: 'MEGAWIN_MUSIC',
              offset: const Duration(milliseconds: 200),
              duration: const Duration(milliseconds: 8000),
              color: Colors.purple,
            ),
            AuditionStage(
              stageName: 'ROLLUP_START',
              offset: const Duration(milliseconds: 500),
              color: Colors.green,
            ),
            AuditionStage(
              stageName: 'MEGAWIN_END',
              offset: const Duration(milliseconds: 9500),
              color: Colors.deepPurple,
            ),
          ],
        );
      case AuditionContext.freeSpins:
        return AuditionTimeline(
          context: context,
          totalDuration: context.defaultDuration,
          stages: [
            AuditionStage(
              stageName: 'FREESPIN_TRIGGER',
              offset: Duration.zero,
              color: Colors.pink,
            ),
            AuditionStage(
              stageName: 'FREESPIN_INTRO',
              offset: const Duration(milliseconds: 500),
              duration: const Duration(milliseconds: 2000),
              color: Colors.pink,
            ),
            AuditionStage(
              stageName: 'FREESPIN_SPIN_1',
              offset: const Duration(milliseconds: 3000),
              color: Colors.blue,
            ),
            AuditionStage(
              stageName: 'FREESPIN_SPIN_2',
              offset: const Duration(milliseconds: 6000),
              color: Colors.blue,
            ),
            AuditionStage(
              stageName: 'FREESPIN_SPIN_3',
              offset: const Duration(milliseconds: 9000),
              color: Colors.blue,
            ),
            AuditionStage(
              stageName: 'FREESPIN_END',
              offset: const Duration(milliseconds: 14000),
              color: Colors.pink,
            ),
          ],
        );
      case AuditionContext.cascade:
        return AuditionTimeline(
          context: context,
          totalDuration: context.defaultDuration,
          stages: [
            AuditionStage(
              stageName: 'CASCADE_START',
              offset: Duration.zero,
              color: Colors.cyan,
            ),
            AuditionStage(
              stageName: 'CASCADE_STEP',
              offset: const Duration(milliseconds: 500),
              color: Colors.cyan,
            ),
            AuditionStage(
              stageName: 'CASCADE_STEP',
              offset: const Duration(milliseconds: 1500),
              color: Colors.cyan,
            ),
            AuditionStage(
              stageName: 'CASCADE_STEP',
              offset: const Duration(milliseconds: 2500),
              color: Colors.cyan,
            ),
            AuditionStage(
              stageName: 'CASCADE_END',
              offset: const Duration(milliseconds: 4500),
              color: Colors.cyan,
            ),
          ],
        );
      case AuditionContext.bonus:
        return AuditionTimeline(
          context: context,
          totalDuration: context.defaultDuration,
          stages: [
            AuditionStage(
              stageName: 'BONUS_TRIGGER',
              offset: Duration.zero,
              color: Colors.orange,
            ),
            AuditionStage(
              stageName: 'BONUS_INTRO',
              offset: const Duration(milliseconds: 500),
              duration: const Duration(milliseconds: 2000),
              color: Colors.orange,
            ),
            AuditionStage(
              stageName: 'BONUS_PICK',
              offset: const Duration(milliseconds: 3000),
              color: Colors.amber,
            ),
            AuditionStage(
              stageName: 'BONUS_REVEAL',
              offset: const Duration(milliseconds: 5000),
              color: Colors.amber,
            ),
            AuditionStage(
              stageName: 'BONUS_END',
              offset: const Duration(milliseconds: 7500),
              color: Colors.orange,
            ),
          ],
        );
    }
  }
}

/// In-Context Auditioning Panel
class InContextAuditionPanel extends StatefulWidget {
  /// Callback to trigger a stage event
  final Function(String stageName)? onTriggerStage;

  const InContextAuditionPanel({
    super.key,
    this.onTriggerStage,
  });

  @override
  State<InContextAuditionPanel> createState() => _InContextAuditionPanelState();
}

class _InContextAuditionPanelState extends State<InContextAuditionPanel> {
  AuditionContext _selectedContext = AuditionContext.spin;
  AuditionTimeline? _timeline;
  bool _isPlaying = false;
  Duration _playheadPosition = Duration.zero;
  Timer? _playbackTimer;
  int _triggeredStageIndex = -1;

  // A/B Comparison
  bool _abMode = false;
  AuditionContext? _contextA;
  AuditionContext? _contextB;
  bool _playingA = true;

  @override
  void initState() {
    super.initState();
    _timeline = AuditionTimeline.forContext(_selectedContext);
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _selectContext(AuditionContext context) {
    setState(() {
      _selectedContext = context;
      _timeline = AuditionTimeline.forContext(context);
      _playheadPosition = Duration.zero;
      _triggeredStageIndex = -1;
      _stop();
    });
  }

  void _play() {
    if (_isPlaying) return;

    setState(() {
      _isPlaying = true;
      _triggeredStageIndex = -1;
    });

    _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || _timeline == null) {
        timer.cancel();
        return;
      }

      setState(() {
        _playheadPosition += const Duration(milliseconds: 50);

        // Check for stages to trigger
        final stages = _timeline!.stages;
        for (int i = _triggeredStageIndex + 1; i < stages.length; i++) {
          if (_playheadPosition >= stages[i].offset) {
            _triggeredStageIndex = i;
            widget.onTriggerStage?.call(stages[i].stageName);
          }
        }

        // Stop at end
        if (_playheadPosition >= _timeline!.totalDuration) {
          _stop();
        }
      });
    });
  }

  void _stop() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  void _reset() {
    _stop();
    setState(() {
      _playheadPosition = Duration.zero;
      _triggeredStageIndex = -1;
    });
  }

  void _seekTo(Duration position) {
    setState(() {
      final maxDuration = _timeline?.totalDuration ?? Duration.zero;
      _playheadPosition = position < Duration.zero
          ? Duration.zero
          : (position > maxDuration ? maxDuration : position);
      // Reset triggered index based on position
      _triggeredStageIndex = -1;
      if (_timeline != null) {
        for (int i = 0; i < _timeline!.stages.length; i++) {
          if (_timeline!.stages[i].offset <= _playheadPosition) {
            _triggeredStageIndex = i;
          }
        }
      }
    });
  }

  void _toggleABMode() {
    setState(() {
      _abMode = !_abMode;
      if (_abMode) {
        _contextA = _selectedContext;
        _contextB = AuditionContext.values[(AuditionContext.values.indexOf(_selectedContext) + 1) % AuditionContext.values.length];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FluxForgeTheme.bgDeep,
      child: Column(
        children: [
          _buildHeader(),
          _buildContextSelector(),
          if (_abMode) _buildABSelector(),
          Expanded(child: _buildTimeline()),
          _buildTransport(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.bgDeep)),
      ),
      child: Row(
        children: [
          Icon(Icons.play_circle, size: 16, color: FluxForgeTheme.accentBlue),
          const SizedBox(width: 8),
          Text(
            'In-Context Auditioning',
            style: TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // A/B toggle
          TextButton.icon(
            onPressed: _toggleABMode,
            icon: Icon(
              _abMode ? Icons.compare : Icons.compare_arrows,
              size: 14,
              color: _abMode ? FluxForgeTheme.accentOrange : FluxForgeTheme.textSecondary,
            ),
            label: Text(
              'A/B',
              style: TextStyle(
                color: _abMode ? FluxForgeTheme.accentOrange : FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextSelector() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: AuditionContext.values.map((ctx) {
          final isSelected = ctx == _selectedContext;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(ctx.icon, size: 14),
                  const SizedBox(width: 4),
                  Text(ctx.label),
                ],
              ),
              selected: isSelected,
              onSelected: (_) => _selectContext(ctx),
              backgroundColor: FluxForgeTheme.bgMid,
              selectedColor: FluxForgeTheme.accentBlue.withOpacity(0.3),
              labelStyle: TextStyle(
                color: isSelected ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
                fontSize: 12,
              ),
              side: BorderSide(
                color: isSelected ? FluxForgeTheme.accentBlue : Colors.transparent,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildABSelector() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: FluxForgeTheme.bgMid.withOpacity(0.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildABButton('A', _contextA, _playingA, () {
            setState(() => _playingA = true);
            if (_contextA != null) _selectContext(_contextA!);
          }),
          const SizedBox(width: 16),
          _buildABButton('B', _contextB, !_playingA, () {
            setState(() => _playingA = false);
            if (_contextB != null) _selectContext(_contextB!);
          }),
        ],
      ),
    );
  }

  Widget _buildABButton(String label, AuditionContext? ctx, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? FluxForgeTheme.accentBlue.withOpacity(0.3) : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? FluxForgeTheme.accentBlue : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? FluxForgeTheme.textPrimary : FluxForgeTheme.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (ctx != null)
              Text(
                ctx.label,
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    if (_timeline == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final totalMs = _timeline!.totalDuration.inMilliseconds.toDouble();
        final playheadX = (_playheadPosition.inMilliseconds / totalMs) * width;

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            final pos = details.localPosition.dx / width;
            final newPosition = Duration(milliseconds: (pos * totalMs).round());
            _seekTo(newPosition);
          },
          onTapDown: (details) {
            final pos = details.localPosition.dx / width;
            final newPosition = Duration(milliseconds: (pos * totalMs).round());
            _seekTo(newPosition);
          },
          child: Container(
            color: FluxForgeTheme.bgDeep,
            child: Stack(
              children: [
                // Stage markers
                ..._timeline!.stages.asMap().entries.map((entry) {
                  final index = entry.key;
                  final stage = entry.value;
                  final stageX = (stage.offset.inMilliseconds / totalMs) * width;
                  final stageW = (stage.duration.inMilliseconds / totalMs) * width;
                  final isTriggered = index <= _triggeredStageIndex;

                  return Positioned(
                    left: stageX,
                    top: 20,
                    bottom: 20,
                    width: stageW > 4 ? stageW : 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: stage.color.withOpacity(isTriggered ? 0.5 : 0.2),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: stage.color.withOpacity(isTriggered ? 1 : 0.5),
                        ),
                      ),
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: -1,
                          child: Text(
                            stage.stageName,
                            style: TextStyle(
                              color: isTriggered ? Colors.white : FluxForgeTheme.textSecondary,
                              fontSize: 9,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                // Playhead
                Positioned(
                  left: playheadX - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: FluxForgeTheme.accentOrange,
                  ),
                ),

                // Playhead handle
                Positioned(
                  left: playheadX - 6,
                  top: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: FluxForgeTheme.accentOrange,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransport() {
    final position = _formatDuration(_playheadPosition);
    final total = _formatDuration(_timeline?.totalDuration ?? Duration.zero);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(top: BorderSide(color: FluxForgeTheme.bgDeep)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Reset
          IconButton(
            icon: const Icon(Icons.skip_previous),
            onPressed: _reset,
            iconSize: 20,
          ),
          const SizedBox(width: 8),
          // Play/Stop
          IconButton(
            icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
            onPressed: _isPlaying ? _stop : _play,
            iconSize: 32,
            color: FluxForgeTheme.accentBlue,
          ),
          const SizedBox(width: 16),
          // Time display
          Text(
            '$position / $total',
            style: TextStyle(
              color: FluxForgeTheme.textSecondary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final ms = d.inMilliseconds;
    final secs = (ms / 1000).floor();
    final millis = ms % 1000;
    return '${secs.toString().padLeft(2, '0')}.${(millis ~/ 100).toString()}';
  }
}

/// Quick audition button for toolbar integration
class QuickAuditionButton extends StatelessWidget {
  final AuditionContext context;
  final VoidCallback? onPlay;

  const QuickAuditionButton({
    super.key,
    required this.context,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Quick Audition: ${this.context.label}',
      child: IconButton(
        icon: Icon(this.context.icon, size: 18),
        onPressed: onPlay,
        color: FluxForgeTheme.accentBlue,
      ),
    );
  }
}
