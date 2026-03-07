/// Stage Trace Timeline — DAW-style horizontal stage visualization
///
/// Shows triggered stages as a horizontal timeline with:
/// - Stage rows grouped by category (Spin, Win, Feature, Music, etc.)
/// - Audio clip regions with waveforms per stage
/// - Time ruler at the top
/// - Playhead following current stage
/// - Drag & drop audio assignment
/// - Color-coded by stage group
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../providers/slot_lab/slot_lab_coordinator.dart';
import '../../services/event_registry.dart';
import '../../src/rust/native_ffi.dart';
import '../../config/stage_config.dart';
import '../../services/waveform_thumbnail_cache.dart';
import '../../theme/fluxforge_theme.dart';
import 'audio_hover_preview.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STAGE SEQUENCE TEMPLATES
// ═══════════════════════════════════════════════════════════════════════════

class StageTemplate {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final List<String> stages;

  const StageTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.stages,
  });
}

class StageTemplates {
  static const List<StageTemplate> all = [
    StageTemplate(
      id: 'basic_spin',
      name: 'Basic Spin',
      description: 'Standard spin flow: start → stops → end',
      icon: Icons.play_circle_outline,
      stages: ['ui_spin_press', 'reel_stop_0', 'reel_stop_1', 'reel_stop_2', 'reel_stop_3', 'reel_stop_4', 'spin_end'],
    ),
    StageTemplate(
      id: 'spin_with_anticipation',
      name: 'Spin + Anticipation',
      description: 'Spin with anticipation on last reels',
      icon: Icons.trending_up,
      stages: ['ui_spin_press', 'reel_stop_0', 'reel_stop_1', 'reel_stop_2', 'anticipation_on', 'reel_stop_3', 'reel_stop_4', 'anticipation_off', 'spin_end'],
    ),
    StageTemplate(
      id: 'regular_win',
      name: 'Regular Win',
      description: 'Basic win presentation without rollup',
      icon: Icons.celebration,
      stages: ['win_present_1', 'win_line_show', 'win_line_hide'],
    ),
    StageTemplate(
      id: 'big_win',
      name: 'Big Win Flow',
      description: 'Full big win with rollup and celebration',
      icon: Icons.stars,
      stages: ['big_win_trigger', 'big_win_intro', 'big_win_tier_1', 'rollup_start', 'rollup_tick', 'rollup_end', 'big_win_end'],
    ),
    StageTemplate(
      id: 'free_spins_trigger',
      name: 'Free Spins Trigger',
      description: 'Feature trigger sequence',
      icon: Icons.card_giftcard,
      stages: ['feature_trigger', 'feature_retrigger', 'feature_enter', 'fs_spin_start', 'fs_spin_end', 'feature_exit'],
    ),
    StageTemplate(
      id: 'cascade_sequence',
      name: 'Cascade/Tumble',
      description: 'Cascading reels sequence',
      icon: Icons.water_drop,
      stages: ['cascade_start', 'cascade_step', 'cascade_step', 'cascade_step', 'cascade_end'],
    ),
    StageTemplate(
      id: 'jackpot_sequence',
      name: 'Jackpot',
      description: 'Full jackpot celebration',
      icon: Icons.diamond,
      stages: ['jackpot_trigger', 'jackpot_buildup', 'jackpot_reveal', 'jackpot_present', 'jackpot_celebration', 'jackpot_end'],
    ),
    StageTemplate(
      id: 'bonus_game',
      name: 'Bonus Game',
      description: 'Pick bonus game flow',
      icon: Icons.touch_app,
      stages: ['bonus_trigger', 'bonus_enter', 'pick_bonus_start', 'pick_bonus_pick', 'pick_bonus_end', 'bonus_exit'],
    ),
    StageTemplate(
      id: 'gamble_feature',
      name: 'Gamble Feature',
      description: 'Gamble/double-up sequence',
      icon: Icons.casino,
      stages: ['gamble_start', 'gamble_win', 'gamble_lose', 'gamble_collect'],
    ),
    StageTemplate(
      id: 'music_transitions',
      name: 'Music Transitions',
      description: 'Music layer transitions',
      icon: Icons.music_note,
      stages: ['music_base', 'music_feature', 'music_bigwin', 'ambient_loop'],
    ),
  ];

  static StageTemplate? getById(String id) {
    return all.cast<StageTemplate?>().firstWhere(
      (t) => t?.id == id,
      orElse: () => null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE TRACE WIDGET — DAW-style timeline
// ═══════════════════════════════════════════════════════════════════════════

class StageTraceWidget extends StatefulWidget {
  final SlotLabProvider provider;
  final double height;
  final bool showMiniProgress;
  final Function(AudioFileInfo audio, String stageType)? onAudioDropped;
  final Function(StageTemplate template)? onTemplateApplied;

  const StageTraceWidget({
    super.key,
    required this.provider,
    this.height = 80,
    this.showMiniProgress = true,
    this.onAudioDropped,
    this.onTemplateApplied,
  });

  @override
  State<StageTraceWidget> createState() => _StageTraceWidgetState();
}

class _StageTraceWidgetState extends State<StageTraceWidget>
    with SingleTickerProviderStateMixin {
  List<SlotLabStageEvent> _stages = [];
  int _currentStageIndex = -1;
  bool _isPlaying = false;

  // Waveform cache per stage type
  final Map<String, Float32List?> _waveformCache = {};

  // Scroll controller for timeline
  final ScrollController _verticalScroll = ScrollController();
  final ScrollController _horizontalScroll = ScrollController();

  // Playhead animation
  late AnimationController _playheadPulse;

  // Group definitions
  static const Map<String, String> _stageToGroup = {
    'ui_spin_press': 'Spin',
    'reel_spinning': 'Spin',
    'reel_stop': 'Spin', // prefix match
    'spin_end': 'Spin',
    'anticipation_on': 'Anticipation',
    'anticipation_off': 'Anticipation',
    'evaluate_wins': 'Win',
    'win_present': 'Win',
    'win_line_show': 'Win',
    'win_line_hide': 'Win',
    'rollup_start': 'Rollup',
    'rollup_tick': 'Rollup',
    'rollup_end': 'Rollup',
    'big_win': 'Big Win',
    'bigwin': 'Big Win',
    'feature_trigger': 'Feature',
    'feature_retrigger': 'Feature',
    'feature_enter': 'Feature',
    'feature_step': 'Feature',
    'feature_exit': 'Feature',
    'fs_spin': 'Free Spins',
    'cascade_start': 'Cascade',
    'cascade_step': 'Cascade',
    'cascade_end': 'Cascade',
    'jackpot': 'Jackpot',
    'music_base': 'Music',
    'music_feature': 'Music',
    'music_bigwin': 'Music',
    'ambient': 'Music',
    'game_start': 'Music',
    'bonus': 'Bonus',
    'gamble': 'Gamble',
  };

  static const Map<String, Color> _groupColors = {
    'Spin': Color(0xFF4A9EFF),
    'Anticipation': Color(0xFFFF9040),
    'Win': Color(0xFF40FF90),
    'Rollup': Color(0xFFFFD700),
    'Big Win': Color(0xFFFF4080),
    'Feature': Color(0xFF40C8FF),
    'Free Spins': Color(0xFFE040FB),
    'Cascade': Color(0xFFA0A0FF),
    'Jackpot': Color(0xFFFFD700),
    'Music': Color(0xFF80FF80),
    'Bonus': Color(0xFFFF80C0),
    'Gamble': Color(0xFFFFAA00),
  };

  static const Map<String, IconData> _groupIcons = {
    'Spin': Icons.play_arrow,
    'Anticipation': Icons.trending_up,
    'Win': Icons.emoji_events,
    'Rollup': Icons.speed,
    'Big Win': Icons.stars,
    'Feature': Icons.card_giftcard,
    'Free Spins': Icons.autorenew,
    'Cascade': Icons.water_drop,
    'Jackpot': Icons.diamond,
    'Music': Icons.music_note,
    'Bonus': Icons.touch_app,
    'Gamble': Icons.casino,
  };

  @override
  void initState() {
    super.initState();
    widget.provider.addListener(_onProviderUpdate);
    _playheadPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    // Load initial data
    _onProviderUpdate();
  }

  @override
  void didUpdateWidget(StageTraceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      oldWidget.provider.removeListener(_onProviderUpdate);
      widget.provider.addListener(_onProviderUpdate);
    }
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderUpdate);
    _playheadPulse.dispose();
    _verticalScroll.dispose();
    _horizontalScroll.dispose();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;
    final newStages = widget.provider.lastStages;
    setState(() {
      _stages = newStages;
      _isPlaying = widget.provider.isPlayingStages;
      _currentStageIndex = widget.provider.currentStageIndex;
    });
    // Preload waveforms for new stages
    for (final stage in newStages) {
      if (!_waveformCache.containsKey(stage.stageType)) {
        _loadWaveform(stage.stageType);
      }
    }
  }

  void _loadWaveform(String stageType) {
    try {
      final audioPath = _getAudioForStage(stageType);
      if (audioPath == null) return;

      final cache = WaveformThumbnailCache.instance;
      final cached = cache.get(audioPath);
      if (cached != null) {
        _waveformCache[stageType] = cached.peaks;
        return;
      }

      cache.generateAsync(audioPath, (data) {
        if (mounted && data != null) {
          setState(() => _waveformCache[stageType] = data.peaks);
        }
      });
    } catch (_) {}
  }

  String _getGroupForStage(String stageType) {
    final lower = stageType.toLowerCase();
    // Exact match first
    if (_stageToGroup.containsKey(lower)) return _stageToGroup[lower]!;
    // Prefix match
    for (final entry in _stageToGroup.entries) {
      if (lower.startsWith(entry.key)) return entry.value;
    }
    return 'Other';
  }

  Color _getGroupColor(String group) => _groupColors[group] ?? const Color(0xFF808088);
  IconData _getGroupIcon(String group) => _groupIcons[group] ?? Icons.circle;

  String? _getAudioForStage(String stageType) {
    final registry = EventRegistry.instance;
    final event = registry.getEventForStage(stageType.toUpperCase());
    if (event == null || event.layers.isEmpty) return null;
    return event.layers.first.audioPath;
  }

  String _formatTime(double ms) {
    if (ms < 1000) return '${ms.toInt()}ms';
    return '${(ms / 1000).toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A32)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _stages.isEmpty ? _buildEmptyState() : _buildTimeline(),
          ),
          if (widget.showMiniProgress && _stages.isNotEmpty)
            _buildProgressBar(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF111118),
        borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A32))),
      ),
      child: Row(
        children: [
          Icon(
            _isPlaying ? Icons.play_arrow : Icons.timeline,
            size: 12,
            color: _isPlaying ? FluxForgeTheme.accentGreen : const Color(0xFF808088),
          ),
          const SizedBox(width: 4),
          Text(
            'STAGE TRACE',
            style: TextStyle(
              color: _isPlaying ? FluxForgeTheme.accentGreen : const Color(0xFFD0D0D8),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          if (_stages.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF4A9EFF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${_stages.length} stages',
                style: const TextStyle(color: Color(0xFF4A9EFF), fontSize: 8, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            if (_currentStageIndex >= 0 && _currentStageIndex < _stages.length)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: StageConfig.instance.getColor(_stages[_currentStageIndex].stageType).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _stages[_currentStageIndex].stageType.toUpperCase().replaceAll('_', ' '),
                  style: TextStyle(
                    color: StageConfig.instance.getColor(_stages[_currentStageIndex].stageType),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
          const Spacer(),
          if (_stages.isNotEmpty) ...[
            // Total duration
            Text(
              _formatTime(_stages.last.timestampMs - _stages.first.timestampMs),
              style: const TextStyle(color: Color(0xFF606068), fontSize: 8, fontFamily: 'monospace'),
            ),
            const SizedBox(width: 8),
            // Clear
            GestureDetector(
              onTap: () => setState(() {
                _stages = [];
                _currentStageIndex = -1;
                _waveformCache.clear();
              }),
              child: const Icon(Icons.clear_all, size: 14, color: Color(0xFF606068)),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EMPTY STATE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timeline, size: 28, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 8),
          const Text(
            'No stage trace yet',
            style: TextStyle(color: Color(0xFF606068), fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          const Text(
            'Spin the slot to record a stage trace',
            style: TextStyle(color: Color(0xFF404048), fontSize: 9),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DAW-STYLE TIMELINE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTimeline() {
    if (_stages.isEmpty) return const SizedBox.shrink();

    final startMs = _stages.first.timestampMs;
    final endMs = _stages.last.timestampMs;
    final totalDuration = endMs - startMs;
    if (totalDuration <= 0) return _buildSingleStageView();

    // Group stages by category
    final grouped = <String, List<_StageEntry>>{};
    for (int i = 0; i < _stages.length; i++) {
      final stage = _stages[i];
      final group = _getGroupForStage(stage.stageType);
      grouped.putIfAbsent(group, () => []).add(_StageEntry(
        index: i,
        event: stage,
        startNorm: (stage.timestampMs - startMs) / totalDuration,
      ));
    }

    // Calculate clip durations — each stage lasts until the next stage in its group
    for (final entries in grouped.values) {
      for (int i = 0; i < entries.length; i++) {
        if (i + 1 < entries.length) {
          entries[i].durationNorm = entries[i + 1].startNorm - entries[i].startNorm;
        } else {
          // Last in group — give it a small visible duration
          entries[i].durationNorm = (1.0 - entries[i].startNorm).clamp(0.02, 0.15);
        }
        // Minimum visible width
        if (entries[i].durationNorm < 0.01) entries[i].durationNorm = 0.01;
      }
    }

    // Sort groups by first appearance
    final sortedGroups = grouped.entries.toList()
      ..sort((a, b) => a.value.first.event.timestampMs.compareTo(b.value.first.event.timestampMs));

    const headerWidth = 100.0;
    const rowHeight = 36.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final timelineWidth = constraints.maxWidth - headerWidth;

        return Column(
          children: [
            // Time ruler
            _buildTimeRuler(headerWidth, timelineWidth, totalDuration),
            // Stage rows
            Expanded(
              child: ListView.builder(
                controller: _verticalScroll,
                padding: EdgeInsets.zero,
                itemCount: sortedGroups.length,
                itemBuilder: (context, groupIndex) {
                  final entry = sortedGroups[groupIndex];
                  final group = entry.key;
                  final stages = entry.value;
                  final color = _getGroupColor(group);
                  final icon = _getGroupIcon(group);

                  return SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: [
                        // Track header
                        Container(
                          width: headerWidth,
                          height: rowHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.06),
                            border: Border(
                              bottom: BorderSide(color: const Color(0xFF2A2A32).withValues(alpha: 0.5)),
                              right: const BorderSide(color: Color(0xFF2A2A32)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(icon, size: 10, color: color.withValues(alpha: 0.7)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  group.toUpperCase(),
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${stages.length}',
                                style: TextStyle(
                                  color: color.withValues(alpha: 0.4),
                                  fontSize: 7,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Timeline region
                        Expanded(
                          child: Container(
                            height: rowHeight,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E0E14),
                              border: Border(
                                bottom: BorderSide(color: const Color(0xFF2A2A32).withValues(alpha: 0.5)),
                              ),
                            ),
                            child: Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                // Playhead
                                if (_currentStageIndex >= 0 && _currentStageIndex < _stages.length)
                                  _buildPlayhead(timelineWidth, startMs, totalDuration),
                                // Stage clips
                                ...stages.map((stageEntry) => _buildStageClip(
                                  stageEntry, color, timelineWidth, totalDuration, startMs,
                                )),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSingleStageView() {
    final stage = _stages.first;
    final color = StageConfig.instance.getColor(stage.stageType);
    final audioPath = _getAudioForStage(stage.stageType);
    final fileName = audioPath?.split('/').last ?? 'No audio';

    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.stageType.toUpperCase(),
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                ),
                Text(
                  fileName,
                  style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIME RULER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildTimeRuler(double headerWidth, double timelineWidth, double totalDuration) {
    // Calculate tick interval
    final tickCount = (timelineWidth / 60).floor().clamp(3, 20);
    final tickInterval = totalDuration / tickCount;

    return Container(
      height: 18,
      decoration: const BoxDecoration(
        color: Color(0xFF111118),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A32))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: headerWidth,
            child: const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text('TIME', style: TextStyle(
                color: Color(0xFF404048), fontSize: 7, fontWeight: FontWeight.w600,
              )),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, 18),
                  painter: _TimeRulerPainter(
                    totalDuration: totalDuration,
                    tickCount: tickCount,
                    tickInterval: tickInterval,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STAGE CLIP
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStageClip(
    _StageEntry entry,
    Color color,
    double timelineWidth,
    double totalDuration,
    double startMs,
  ) {
    final left = entry.startNorm * timelineWidth;
    final width = (entry.durationNorm * timelineWidth).clamp(4.0, timelineWidth);
    final isActive = entry.index == _currentStageIndex;
    final isPast = entry.index < _currentStageIndex;
    final audioPath = _getAudioForStage(entry.event.stageType);
    final hasAudio = audioPath != null;
    final waveform = _waveformCache[entry.event.stageType];
    final fileName = audioPath?.split('/').last;

    return Positioned(
      left: left,
      top: 2,
      child: GestureDetector(
        onTap: () {
          widget.provider.triggerStageManually(entry.index);
        },
        child: Tooltip(
          message: '${entry.event.stageType.toUpperCase()}\n'
              '${_formatTime(entry.event.timestampMs - startMs)}'
              '${hasAudio ? '\n$fileName' : '\nNo audio assigned'}',
          waitDuration: const Duration(milliseconds: 400),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: width,
            height: 32,
            decoration: BoxDecoration(
              color: isActive
                  ? color.withValues(alpha: 0.4)
                  : isPast
                      ? color.withValues(alpha: 0.15)
                      : color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: isActive
                    ? color
                    : isPast
                        ? color.withValues(alpha: 0.3)
                        : color.withValues(alpha: 0.15),
                width: isActive ? 1.5 : 0.5,
              ),
              boxShadow: isActive ? [
                BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6),
              ] : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  // Waveform
                  if (hasAudio && waveform != null && width > 20)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ClipWaveformPainter(
                          waveform: waveform,
                          color: color,
                          isActive: isActive,
                          isPast: isPast,
                        ),
                      ),
                    ),
                  // No audio indicator
                  if (!hasAudio)
                    Center(
                      child: Icon(
                        Icons.volume_off,
                        size: 10,
                        color: color.withValues(alpha: 0.3),
                      ),
                    ),
                  // Stage label
                  if (width > 30)
                    Positioned(
                      left: 3,
                      top: 1,
                      child: Text(
                        entry.event.stageType.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : color.withValues(alpha: isPast ? 0.5 : 0.7),
                          fontSize: 6,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  // Audio file label
                  if (hasAudio && width > 40)
                    Positioned(
                      left: 3,
                      bottom: 1,
                      right: 3,
                      child: Text(
                        fileName ?? '',
                        style: TextStyle(
                          color: color.withValues(alpha: 0.35),
                          fontSize: 6,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  // Active pulse dot
                  if (isActive)
                    Positioned(
                      right: 3,
                      top: 3,
                      child: AnimatedBuilder(
                        animation: _playheadPulse,
                        builder: (context, child) => Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.5 + 0.5 * _playheadPulse.value),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PLAYHEAD
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPlayhead(double timelineWidth, double startMs, double totalDuration) {
    if (_currentStageIndex < 0 || _currentStageIndex >= _stages.length) {
      return const SizedBox.shrink();
    }
    final currentMs = _stages[_currentStageIndex].timestampMs;
    final position = (currentMs - startMs) / totalDuration;
    final x = position * timelineWidth;

    return Positioned(
      left: x - 0.5,
      top: 0,
      bottom: 0,
      child: Container(
        width: 1,
        color: Colors.white.withValues(alpha: 0.6),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROGRESS BAR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildProgressBar() {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF111118),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(5)),
        border: Border(top: BorderSide(color: Color(0xFF2A2A32))),
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(
              color: _isPlaying ? FluxForgeTheme.accentGreen : const Color(0xFF404048),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          // Stage segments
          Expanded(
            child: Row(
              children: _stages.asMap().entries.map((entry) {
                final index = entry.key;
                final stage = entry.value;
                final color = StageConfig.instance.getColor(stage.stageType);
                final isActive = index == _currentStageIndex;
                final isPast = index < _currentStageIndex;

                return Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                    decoration: BoxDecoration(
                      color: isActive
                          ? color
                          : isPast
                              ? color.withValues(alpha: 0.5)
                              : color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 6),
          // Current stage label
          if (_currentStageIndex >= 0 && _currentStageIndex < _stages.length)
            SizedBox(
              width: 80,
              child: Text(
                _stages[_currentStageIndex].stageType.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(
                  color: StageConfig.instance.getColor(_stages[_currentStageIndex].stageType),
                  fontSize: 7,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE ENTRY HELPER
// ═══════════════════════════════════════════════════════════════════════════

class _StageEntry {
  final int index;
  final SlotLabStageEvent event;
  final double startNorm; // 0..1 normalized position
  double durationNorm;    // 0..1 normalized duration

  _StageEntry({
    required this.index,
    required this.event,
    required this.startNorm,
    this.durationNorm = 0.05,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// TIME RULER PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _TimeRulerPainter extends CustomPainter {
  final double totalDuration;
  final int tickCount;
  final double tickInterval;

  _TimeRulerPainter({
    required this.totalDuration,
    required this.tickCount,
    required this.tickInterval,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2A2A32)
      ..strokeWidth = 0.5;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );

    for (int i = 0; i <= tickCount; i++) {
      final x = (i / tickCount) * size.width;
      final ms = i * tickInterval;

      // Tick mark
      canvas.drawLine(Offset(x, size.height - 4), Offset(x, size.height), paint);

      // Label
      final label = ms < 1000 ? '${ms.toInt()}ms' : '${(ms / 1000).toStringAsFixed(1)}s';
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(color: Color(0xFF404048), fontSize: 7, fontFamily: 'monospace'),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 2, 1));
    }
  }

  @override
  bool shouldRepaint(_TimeRulerPainter oldDelegate) =>
      totalDuration != oldDelegate.totalDuration || tickCount != oldDelegate.tickCount;
}

// ═══════════════════════════════════════════════════════════════════════════
// CLIP WAVEFORM PAINTER
// ═══════════════════════════════════════════════════════════════════════════

class _ClipWaveformPainter extends CustomPainter {
  final Float32List waveform;
  final Color color;
  final bool isActive;
  final bool isPast;

  _ClipWaveformPainter({
    required this.waveform,
    required this.color,
    required this.isActive,
    required this.isPast,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;

    final alpha = isActive ? 0.7 : (isPast ? 0.25 : 0.4);
    final paint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;

    final midY = size.height / 2;
    final samplesPerPixel = waveform.length / size.width;

    final path = Path();
    path.moveTo(0, midY);

    // Top half
    for (double x = 0; x < size.width; x += 1) {
      final sampleIndex = (x * samplesPerPixel).toInt().clamp(0, waveform.length - 1);
      final sample = waveform[sampleIndex].abs();
      final y = midY - (sample * midY * 0.9);
      path.lineTo(x, y);
    }

    // Bottom half (mirror)
    for (double x = size.width - 1; x >= 0; x -= 1) {
      final sampleIndex = (x * samplesPerPixel).toInt().clamp(0, waveform.length - 1);
      final sample = waveform[sampleIndex].abs();
      final y = midY + (sample * midY * 0.9);
      path.lineTo(x, y);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ClipWaveformPainter old) =>
      color != old.color || isActive != old.isActive || isPast != old.isPast;
}

// ═══════════════════════════════════════════════════════════════════════════
// STAGE PROGRESS BAR (standalone, compact)
// ═══════════════════════════════════════════════════════════════════════════

class StageProgressBar extends StatelessWidget {
  final SlotLabProvider provider;
  final double height;

  const StageProgressBar({
    super.key,
    required this.provider,
    this.height = 24,
  });

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
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: isPlaying ? FluxForgeTheme.accentGreen : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: stages.asMap().entries.map((entry) {
                    final index = entry.key;
                    final stage = entry.value;
                    final color = StageConfig.instance.getColor(stage.stageType);
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
                                  ? color.withValues(alpha: 0.6)
                                  : color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 8),
              if (currentIndex >= 0 && currentIndex < stages.length)
                Text(
                  stages[currentIndex].stageType.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: StageConfig.instance.getColor(stages[currentIndex].stageType),
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
