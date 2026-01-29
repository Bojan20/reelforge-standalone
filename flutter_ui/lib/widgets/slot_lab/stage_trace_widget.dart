/// Stage Trace Visualization Widget
///
/// Animated visual trace through stage events during spin playback:
/// - Horizontal timeline with stage markers
/// - Animated playhead that follows current stage
/// - Color-coded stage zones
/// - Pulse effects on active stages
/// - Mini progress indicator
/// - Drag & drop audio assignment to stages
/// - Waveform preview on hover (P0.1)
library;

import 'dart:async';
import 'dart:convert'; // P0.11: Export stage trace
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // P0.5: Keyboard focus
import '../../providers/slot_lab_provider.dart';
import '../../providers/subsystems/event_profiler_provider.dart'; // P0.7
import '../../services/audio_playback_service.dart'; // P1.4: A/B compare
import '../../services/event_registry.dart';
import '../../services/service_locator.dart'; // P0.7
import '../../src/rust/native_ffi.dart';
import '../../config/stage_config.dart'; // P1.16 + P1.17
import '../../theme/fluxforge_theme.dart';
import 'audio_hover_preview.dart';
import 'package:file_picker/file_picker.dart'; // P2.1: Batch assign file picker

// ═══════════════════════════════════════════════════════════════════════════
// P2.3: STAGE SEQUENCE TEMPLATES
// ═══════════════════════════════════════════════════════════════════════════

/// P2.3: Stage template for common slot game sequences
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

/// P2.3: Built-in stage templates
class StageTemplates {
  static const List<StageTemplate> all = [
    StageTemplate(
      id: 'basic_spin',
      name: 'Basic Spin',
      description: 'Standard spin flow: start → stops → end',
      icon: Icons.play_circle_outline,
      stages: ['spin_start', 'reel_stop_0', 'reel_stop_1', 'reel_stop_2', 'reel_stop_3', 'reel_stop_4', 'spin_end'],
    ),
    StageTemplate(
      id: 'spin_with_anticipation',
      name: 'Spin + Anticipation',
      description: 'Spin with anticipation on last reels',
      icon: Icons.trending_up,
      stages: ['spin_start', 'reel_stop_0', 'reel_stop_1', 'reel_stop_2', 'anticipation_on', 'reel_stop_3', 'reel_stop_4', 'anticipation_off', 'spin_end'],
    ),
    StageTemplate(
      id: 'small_win',
      name: 'Small Win',
      description: 'Basic win presentation without rollup',
      icon: Icons.celebration,
      stages: ['win_present', 'win_line_show', 'win_line_hide'],
    ),
    StageTemplate(
      id: 'big_win',
      name: 'Big Win Flow',
      description: 'Full big win with rollup and celebration',
      icon: Icons.stars,
      stages: ['win_present', 'bigwin_tier', 'rollup_start', 'rollup_tick', 'rollup_end', 'win_line_show', 'win_line_hide'],
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
// STAGE TRACE WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// P1.19: Stage trace visualization widget for slot game audio design.
///
/// Displays an animated timeline of stage events during spin playback,
/// allowing audio designers to:
/// - See real-time stage progression with animated playhead
/// - Assign audio files to stages via drag & drop
/// - Preview waveforms on hover
/// - Compare A/B audio variants
/// - Multi-select stages for batch operations
///
/// ## Features
/// - **Animated timeline**: Horizontal view with color-coded stage markers
/// - **Zoom & pan**: Mouse wheel to zoom, drag to pan (P0.2)
/// - **Keyboard navigation**: Arrow keys to navigate, Space to play (P0.5)
/// - **Latency metering**: Real-time latency monitoring (P0.7)
/// - **Inline waveforms**: Optional waveform display (P1.8)
/// - **Multi-select**: Ctrl/Cmd+click for batch operations (P1.6)
///
/// ## Usage
/// ```dart
/// StageTraceWidget(
///   provider: slotLabProvider,
///   height: 120,
///   showMiniProgress: true,
///   onAudioDropped: (audio, stageType) {
///     // Handle audio assignment
///   },
/// )
/// ```
///
/// ## See Also
/// - [StageProgressBar] — Compact progress indicator
/// - [StageConfig] — Stage color and icon configuration
/// - [SlotLabProvider] — Stage event data source
class StageTraceWidget extends StatefulWidget {
  /// The SlotLab provider that supplies stage event data.
  ///
  /// Must be a valid [SlotLabProvider] instance. The widget listens
  /// to provider changes and updates the timeline accordingly.
  final SlotLabProvider provider;

  /// Height of the timeline widget in pixels.
  ///
  /// Defaults to 80. Larger values show more detail but consume
  /// more vertical space. Recommended range: 60-200.
  final double height;

  /// Whether to show the mini progress indicator.
  ///
  /// When true, displays a compact progress bar at the bottom.
  /// Defaults to true.
  final bool showMiniProgress;

  /// Callback when audio is dropped on a stage.
  ///
  /// Called with the dropped [AudioFileInfo] and the target stage type.
  /// Use this to handle audio assignment to stages.
  final Function(AudioFileInfo audio, String stageType)? onAudioDropped;

  /// P2.3: Callback when a stage template is applied.
  ///
  /// Called with the list of stage types from the selected template.
  /// Use this to create placeholder events for the template stages.
  final Function(StageTemplate template)? onTemplateApplied;

  /// Creates a stage trace visualization widget.
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

  // P0.5: Keyboard focus state
  int? _focusedStageIndex;
  final FocusNode _timelineFocusNode = FocusNode();

  // Waveform preview state (P0.1)
  final Map<String, Float32List?> _stageWaveformCache = {};
  final Map<String, String?> _stageAudioPathCache = {};

  // Zoom/Pan state (P0.2)
  double _zoomLevel = 1.0;  // 1.0 = fit all, 2.0 = 2x zoom, etc.
  double _panOffset = 0.0;  // Horizontal pan offset (0.0 - 1.0)
  final ScrollController _scrollController = ScrollController();
  // P1.21: Static const for performance
  static const double _minZoom = 1.0;
  static const double _maxZoom = 4.0;
  static const double _zoomStep = 0.25;
  static const Duration _animDuration150 = Duration(milliseconds: 150);
  static const Duration _animDuration200 = Duration(milliseconds: 200);
  static const EdgeInsets _markerPadding = EdgeInsets.symmetric(horizontal: 4, vertical: 2);

  // P0.7: Latency metering
  EventProfilerProvider? _profiler;
  double _avgLatencyMs = 0.0;
  double _maxLatencyMs = 0.0;
  static const double _latencyWarningThreshold = 10.0; // ms

  // P1.7: Reduced motion accessibility
  bool _reduceMotion = false;

  // P1.4: A/B Comparison state
  bool _abCompareEnabled = false;
  String? _abSelectedStage;      // Stage being compared
  String? _abVariantA;           // Audio path for variant A
  String? _abVariantB;           // Audio path for variant B
  String? _abCurrentVariant;     // 'A' or 'B'
  bool _abIsPlaying = false;

  // P1.6: Multi-select state
  final Set<int> _selectedStageIndices = {};
  int? _lastSelectedIndex;       // For shift-click range selection

  // P1.2: Drag preview state (supports multi-file from AudioPoolPanel)
  List<AudioFileInfo>? _draggedAudioFiles;
  Offset? _dragPosition;
  Float32List? _dragWaveformCache;

  // P1.8: Inline waveform display
  bool _showInlineWaveform = false;
  final Map<int, ({String stageType, double start, double duration, Float32List? waveform})> _inlineWaveformData = {};
  bool _isLoadingInlineWaveforms = false;

  // P2.2: High contrast mode for accessibility
  bool _highContrastMode = false;

  // P2.4: Parallel lane visualization for overlapping stages
  bool _parallelLanesEnabled = true;  // Enable by default
  Map<int, int> _stageLaneAssignments = {};  // stageIndex → laneNumber (0-based)
  int _maxLanes = 1;  // Maximum number of lanes detected
  static const double _laneHeight = 16.0;  // Height per lane
  static const double _overlapThresholdMs = 50.0;  // Stages within this ms are "overlapping"

  // P1.3: Stage grouping
  static const Map<String, String> _stageGroups = {
    'spin_start': 'spin',
    'reel_spinning': 'spin',
    'reel_stop': 'spin',
    'spin_end': 'spin',
    'anticipation_on': 'anticipation',
    'anticipation_off': 'anticipation',
    'evaluate_wins': 'win',
    'win_present': 'win',
    'win_line_show': 'win',
    'win_line_hide': 'win',
    'rollup_start': 'rollup',
    'rollup_tick': 'rollup',
    'rollup_end': 'rollup',
    'bigwin_tier': 'bigwin',
    'feature_enter': 'feature',
    'feature_step': 'feature',
    'feature_exit': 'feature',
    'cascade_start': 'cascade',
    'cascade_step': 'cascade',
    'cascade_end': 'cascade',
    'jackpot_trigger': 'jackpot',
    'jackpot_present': 'jackpot',
  };

  static const Map<String, Color> _groupColors = {
    'spin': Color(0xFF4A9EFF),
    'anticipation': Color(0xFFFF9040),
    'win': Color(0xFF40FF90),
    'rollup': Color(0xFFFFD700),
    'bigwin': Color(0xFFFF4080),
    'feature': Color(0xFF40C8FF),
    'cascade': Color(0xFFE040FB),
    'jackpot': Color(0xFFFFD700),
  };

  // P1.16 + P1.17: Stage colors and icons now managed by StageConfig
  // See: lib/config/stage_config.dart

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

    // P0.7: Initialize profiler for latency metering
    _initProfiler();
  }

  /// P0.7: Initialize latency profiler
  void _initProfiler() {
    try {
      _profiler = sl<EventProfilerProvider>();
      _profiler?.addListener(_onProfilerUpdate);
      _updateLatencyMetrics();
    } catch (e) {
      debugPrint('[StageTrace] Profiler not available: $e');
    }
  }

  /// P0.7: Handle profiler updates
  void _onProfilerUpdate() {
    _updateLatencyMetrics();
  }

  /// P0.7: Update latency metrics from profiler
  void _updateLatencyMetrics() {
    if (_profiler == null) return;
    setState(() {
      _avgLatencyMs = _profiler!.avgLatencyMs;
      _maxLatencyMs = _profiler!.maxLatencyMs;
    });
  }

  /// P2.4: Calculate lane assignments for overlapping stages
  ///
  /// Uses a greedy algorithm to assign stages to lanes:
  /// - Stages are processed in chronological order
  /// - Each stage is assigned to the first available lane
  /// - A lane is "available" if its last stage ended before the current stage starts
  void _calculateStageLanes() {
    if (!_parallelLanesEnabled || _stages.isEmpty) {
      _stageLaneAssignments = {};
      _maxLanes = 1;
      return;
    }

    final laneEndTimes = <int, double>{};  // laneIndex → end timestamp
    final assignments = <int, int>{};       // stageIndex → laneIndex
    var maxLane = 0;

    for (var i = 0; i < _stages.length; i++) {
      final stage = _stages[i];
      final stageStart = stage.timestampMs.toDouble();

      // Find the first available lane
      var assignedLane = 0;
      var foundLane = false;

      for (var lane = 0; lane <= maxLane; lane++) {
        final laneEnd = laneEndTimes[lane] ?? 0.0;
        // Lane is available if its end time + threshold is before this stage's start
        if (laneEnd + _overlapThresholdMs <= stageStart) {
          assignedLane = lane;
          foundLane = true;
          break;
        }
      }

      // If no existing lane is available, create a new one
      if (!foundLane) {
        maxLane++;
        assignedLane = maxLane;
      }

      // Assign this stage to the lane
      assignments[i] = assignedLane;

      // Update lane end time (stage is a point event, so end = start + small duration)
      // Using 100ms as a visual "duration" for lane calculation
      laneEndTimes[assignedLane] = stageStart + 100.0;
    }

    _stageLaneAssignments = assignments;
    _maxLanes = maxLane + 1;  // +1 because lanes are 0-indexed
  }

  /// P2.4: Get the vertical offset for a stage based on its lane
  double _getStageLaneOffset(int stageIndex) {
    if (!_parallelLanesEnabled || _maxLanes <= 1) return 0.0;

    final lane = _stageLaneAssignments[stageIndex] ?? 0;
    // Center all lanes vertically, with lane 0 at top
    final totalLaneHeight = _maxLanes * _laneHeight;
    final baseOffset = (44 - totalLaneHeight) / 2;  // 44 is the touch target height
    return baseOffset + (lane * _laneHeight);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderUpdate);
    _profiler?.removeListener(_onProfilerUpdate); // P0.7
    _pulseController.dispose();
    _playheadController.dispose();
    _playbackTimer?.cancel();
    _scrollController.dispose();
    _timelineFocusNode.dispose(); // P0.5
    super.dispose();
  }

  void _onProviderUpdate() {
    if (!mounted) return;

    final newStages = widget.provider.lastStages;
    final isPlaying = widget.provider.isPlayingStages;
    final currentIndex = widget.provider.currentStageIndex;

    // P2.4: Only recalculate lanes if stages changed
    final stagesChanged = newStages.length != _stages.length;

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

      // P2.4: Recalculate lane assignments when stages change
      if (stagesChanged) {
        _calculateStageLanes();
      }
    });
  }

  // P1.16: Get stage color from centralized config
  Color _getStageColor(String stageType) {
    return StageConfig.instance.getColor(stageType);
  }

  // P1.17: Get stage icon from centralized config
  IconData _getStageIcon(String stageType) {
    return StageConfig.instance.getIcon(stageType);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.12: STAGE TYPE SANITIZATION (Security)
  // ═══════════════════════════════════════════════════════════════════════════

  /// P0.12: Sanitize stageType to prevent injection attacks
  /// Allows only alphanumeric, underscore, hyphen; max 64 chars
  static final _stageTypePattern = RegExp(r'[^a-zA-Z0-9_\-]');
  static const _maxStageTypeLength = 64;

  String _sanitizeStageType(String stageType) {
    // Remove any non-safe characters
    var sanitized = stageType.replaceAll(_stageTypePattern, '');
    // Limit length
    if (sanitized.length > _maxStageTypeLength) {
      sanitized = sanitized.substring(0, _maxStageTypeLength);
    }
    // Fallback to 'UNKNOWN' if empty
    return sanitized.isEmpty ? 'UNKNOWN' : sanitized;
  }

  String _formatStageName(String stageType) {
    final sanitized = _sanitizeStageType(stageType);
    return sanitized
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.1: WAVEFORM PREVIEW HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if a stage has audio assigned via EventRegistry
  bool _stageHasAudio(String stageType) {
    final normalizedStage = stageType.toUpperCase();
    return eventRegistry.hasEventForStage(normalizedStage);
  }

  /// Get audio info for a stage (returns first layer's audio path)
  String? _getStageAudioPath(String stageType) {
    // Check cache first
    if (_stageAudioPathCache.containsKey(stageType)) {
      return _stageAudioPathCache[stageType];
    }

    final normalizedStage = stageType.toUpperCase();
    final event = eventRegistry.getEventForStage(normalizedStage);
    if (event != null && event.layers.isNotEmpty) {
      final path = event.layers.first.audioPath;
      _stageAudioPathCache[stageType] = path;
      return path;
    }
    _stageAudioPathCache[stageType] = null;
    return null;
  }

  /// Get layer count for a stage
  int _getStageLayerCount(String stageType) {
    final normalizedStage = stageType.toUpperCase();
    final event = eventRegistry.getEventForStage(normalizedStage);
    return event?.layers.length ?? 0;
  }

  /// Load waveform data for a stage's audio (async, cached)
  Future<Float32List?> _loadStageWaveform(String stageType) async {
    // Check cache first
    if (_stageWaveformCache.containsKey(stageType)) {
      return _stageWaveformCache[stageType];
    }

    final audioPath = _getStageAudioPath(stageType);
    if (audioPath == null) {
      _stageWaveformCache[stageType] = null;
      return null;
    }

    try {
      // Generate waveform via FFI
      final cacheKey = 'stage_preview_${stageType.hashCode}';
      final json = NativeFFI.instance.generateWaveformFromFile(audioPath, cacheKey);
      if (json != null && json.isNotEmpty) {
        final waveform = _parseWaveformJson(json);
        _stageWaveformCache[stageType] = waveform;
        return waveform;
      }
    } catch (e) {
      debugPrint('[StageTrace] Waveform load error for $stageType: $e');
    }

    _stageWaveformCache[stageType] = null;
    return null;
  }

  /// Parse waveform JSON to Float32List (simplified peak extraction)
  Float32List? _parseWaveformJson(String json) {
    try {
      // Simple regex extraction of peak values from JSON
      // Format: {"lods":[{"left":[{"min":-0.5,"max":0.5},...],...}]}
      final peaks = <double>[];
      final maxPattern = RegExp(r'"max"\s*:\s*(-?[\d.]+)');
      final matches = maxPattern.allMatches(json);

      for (final match in matches) {
        final value = double.tryParse(match.group(1) ?? '0') ?? 0;
        peaks.add(value.abs());
        if (peaks.length >= 64) break; // Limit to 64 samples for mini preview
      }

      if (peaks.isEmpty) return null;

      // Downsample to 32 points for mini waveform
      final downsampled = Float32List(32);
      final step = peaks.length / 32;
      for (int i = 0; i < 32; i++) {
        final idx = (i * step).floor().clamp(0, peaks.length - 1);
        downsampled[i] = peaks[idx].clamp(0.0, 1.0);
      }
      return downsampled;
    } catch (e) {
      return null;
    }
  }

  /// Clear waveform cache (call when events change)
  void _clearWaveformCache() {
    _stageWaveformCache.clear();
    _stageAudioPathCache.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.2: ZOOM/PAN HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  void _zoomIn() {
    setState(() {
      _zoomLevel = (_zoomLevel + _zoomStep).clamp(_minZoom, _maxZoom);
      _constrainPan();
    });
  }

  void _zoomOut() {
    setState(() {
      _zoomLevel = (_zoomLevel - _zoomStep).clamp(_minZoom, _maxZoom);
      _constrainPan();
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomLevel = 1.0;
      _panOffset = 0.0;
    });
  }

  void _constrainPan() {
    // Pan offset should be 0 to (1 - 1/zoomLevel)
    final maxPan = 1.0 - (1.0 / _zoomLevel);
    _panOffset = _panOffset.clamp(0.0, maxPan.clamp(0.0, 1.0));
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double totalWidth) {
    if (_zoomLevel <= 1.0) return;
    setState(() {
      // Pan based on drag delta (inverted for natural scrolling)
      final panDelta = -details.delta.dx / (totalWidth * _zoomLevel);
      _panOffset += panDelta;
      _constrainPan();
    });
  }

  /// Get visible range (0.0-1.0) based on zoom and pan
  (double start, double end) _getVisibleRange() {
    final visibleWidth = 1.0 / _zoomLevel;
    final start = _panOffset;
    final end = (start + visibleWidth).clamp(0.0, 1.0);
    return (start, end);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.5: CONTEXT MENU (Right-click actions)
  // ═══════════════════════════════════════════════════════════════════════════

  /// P1.5: Show context menu for a stage marker
  void _showStageContextMenu(
    BuildContext context,
    Offset position,
    SlotLabStageEvent stage,
    int index,
  ) {
    final hasAudio = _stageHasAudio(stage.stageType);
    final audioPath = _getStageAudioPath(stage.stageType);
    final layerCount = _getStageLayerCount(stage.stageType);

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      color: FluxForgeTheme.bgMid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FluxForgeTheme.borderSubtle),
      ),
      items: [
        // Play stage audio
        if (hasAudio)
          PopupMenuItem<String>(
            value: 'play',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.play_arrow, size: 16, color: FluxForgeTheme.accentGreen),
                const SizedBox(width: 8),
                Text('Play Audio', style: TextStyle(color: Colors.white, fontSize: 12)),
                const Spacer(),
                Text('$layerCount layer(s)', style: TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ),
        // Trigger stage (even without audio)
        PopupMenuItem<String>(
          value: 'trigger',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.bolt, size: 16, color: FluxForgeTheme.accentBlue),
              const SizedBox(width: 8),
              Text('Trigger Stage', style: TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
        // Divider
        const PopupMenuDivider(),
        // Assign audio
        PopupMenuItem<String>(
          value: 'assign',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, size: 16, color: FluxForgeTheme.accentOrange),
              const SizedBox(width: 8),
              Text(hasAudio ? 'Replace Audio' : 'Assign Audio',
                   style: TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
        // Edit event (only if has audio)
        if (hasAudio)
          PopupMenuItem<String>(
            value: 'edit',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.edit, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Text('Edit Event', style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        // P1.4: A/B Compare (only if has audio and A/B mode enabled)
        if (hasAudio && _abCompareEnabled)
          PopupMenuItem<String>(
            value: 'ab_compare',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.compare_arrows, size: 16, color: FluxForgeTheme.accentBlue),
                const SizedBox(width: 8),
                Text('A/B Compare', style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        // Remove audio (only if has audio)
        if (hasAudio) ...[
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'remove',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.remove_circle_outline, size: 16, color: FluxForgeTheme.accentRed),
                const SizedBox(width: 8),
                Text('Remove Audio', style: TextStyle(color: FluxForgeTheme.accentRed, fontSize: 12)),
              ],
            ),
          ),
        ],
        // Divider
        const PopupMenuDivider(),
        // Copy stage info
        PopupMenuItem<String>(
          value: 'copy',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.copy, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              Text('Copy Stage Info', style: TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleContextMenuAction(value, stage, index);
    });
  }

  /// P1.5: Handle context menu action
  void _handleContextMenuAction(String action, SlotLabStageEvent stage, int index) {
    switch (action) {
      case 'play':
        widget.provider.triggerStageManually(index);
        break;
      case 'trigger':
        widget.provider.triggerStageManually(index);
        break;
      case 'assign':
        _showAssignAudioFilePicker(stage.stageType);
        break;
      case 'edit':
        // TODO: Navigate to event editor with this stage
        _showEditEventHint(stage.stageType);
        break;
      case 'remove':
        _confirmRemoveAudio(stage.stageType);
        break;
      case 'copy':
        _copyStageInfo(stage);
        break;
      case 'ab_compare':
        // P1.4: Start A/B comparison for this stage
        _startAbCompare(stage.stageType);
        break;
    }
  }

  /// P1.5: Show file picker for assigning audio to a single stage
  Future<void> _showAssignAudioFilePicker(String stageType) async {
    // Use file_picker to select audio file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'ogg', 'flac', 'aiff'],
      dialogTitle: 'Select audio for ${_formatStageName(stageType)}',
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    // Create AudioFileInfo from picked file
    final audioInfo = AudioFileInfo(
      id: 'assign_${DateTime.now().millisecondsSinceEpoch}',
      path: file.path!,
      name: file.name,
      duration: Duration.zero, // Placeholder — actual duration loaded on playback
      format: file.extension?.toUpperCase() ?? 'WAV',
    );

    // Assign audio to stage via callback
    widget.onAudioDropped?.call(audioInfo, stageType);
    _showDropFeedback(stageType, audioInfo.name);

    // Clear waveform cache so UI updates
    _clearWaveformCache();
  }

  /// P1.5: Show hint for editing event
  void _showEditEventHint(String stageType) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline, color: FluxForgeTheme.accentBlue, size: 16),
            const SizedBox(width: 8),
            Text('Go to Events tab to edit ${_formatStageName(stageType)}'),
          ],
        ),
        backgroundColor: FluxForgeTheme.bgMid,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// P1.5: Confirm and remove audio from stage
  void _confirmRemoveAudio(String stageType) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FluxForgeTheme.bgMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: FluxForgeTheme.accentRed),
            const SizedBox(width: 8),
            Text('Remove Audio', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Text(
          'Remove audio from ${_formatStageName(stageType)}?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Actually remove via EventRegistry/MiddlewareProvider
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Audio removed from ${_formatStageName(stageType)}'),
                  backgroundColor: FluxForgeTheme.accentRed,
                ),
              );
              // Clear cache so UI updates
              _stageWaveformCache.remove(stageType);
              _stageAudioPathCache.remove(stageType);
              if (mounted) setState(() {});
            },
            child: Text('Remove', style: TextStyle(color: FluxForgeTheme.accentRed)),
          ),
        ],
      ),
    );
  }

  /// P1.5: Copy stage info to clipboard
  void _copyStageInfo(SlotLabStageEvent stage) {
    final hasAudio = _stageHasAudio(stage.stageType);
    final buffer = StringBuffer();
    buffer.writeln('Stage: ${stage.stageType}');
    buffer.writeln('Time: ${stage.timestampMs}ms');
    if (hasAudio) {
      final audioPath = _getStageAudioPath(stage.stageType);
      final layerCount = _getStageLayerCount(stage.stageType);
      buffer.writeln('Audio: ${audioPath?.split('/').last ?? 'unknown'}');
      buffer.writeln('Layers: $layerCount');
    }
    if (stage.payload.isNotEmpty) {
      buffer.writeln('Payload: ${stage.payload}');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text('Stage info copied to clipboard'),
            ],
          ),
          backgroundColor: FluxForgeTheme.accentGreen,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.5: KEYBOARD FOCUS NAVIGATION
  // ═══════════════════════════════════════════════════════════════════════════

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_stages.isEmpty) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _moveFocus(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _moveFocus(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
        _triggerFocusedStage();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _focusFirst();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _focusLast();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _moveFocus(int delta) {
    setState(() {
      if (_focusedStageIndex == null) {
        _focusedStageIndex = delta > 0 ? 0 : _stages.length - 1;
      } else {
        _focusedStageIndex = (_focusedStageIndex! + delta).clamp(0, _stages.length - 1);
      }
    });
  }

  void _focusFirst() {
    setState(() => _focusedStageIndex = 0);
  }

  void _focusLast() {
    setState(() => _focusedStageIndex = _stages.length - 1);
  }

  void _triggerFocusedStage() {
    if (_focusedStageIndex != null && _focusedStageIndex! < _stages.length) {
      widget.provider.triggerStageManually(_focusedStageIndex!);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.6: ENHANCED TOOLTIP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Build detailed tooltip message for a stage marker
  String _buildStageTooltip(SlotLabStageEvent stage) {
    final buffer = StringBuffer();

    // Stage name (formatted)
    buffer.writeln('Stage: ${_formatStageName(stage.stageType)}');

    // Timing info
    buffer.writeln('Time: ${stage.timestampMs}ms');

    // Audio info if assigned
    final hasAudio = _stageHasAudio(stage.stageType);
    if (hasAudio) {
      final audioPath = _getStageAudioPath(stage.stageType);
      final layerCount = _getStageLayerCount(stage.stageType);
      if (audioPath != null) {
        final fileName = audioPath.split('/').last;
        buffer.writeln('Audio: $fileName');
      }
      buffer.writeln('Layers: $layerCount');

      // Bus info from event registry
      final normalizedStage = stage.stageType.toUpperCase();
      final event = eventRegistry.getEventForStage(normalizedStage);
      if (event != null && event.layers.isNotEmpty) {
        final busName = _getBusName(event.layers.first.busId);
        buffer.writeln('Bus: $busName');
      }
    } else {
      buffer.writeln('Audio: Not assigned');
      buffer.write('Drop audio here to assign');
    }

    return buffer.toString().trim();
  }

  /// Get human-readable bus name
  String _getBusName(int busId) {
    const busNames = {
      0: 'Master',
      1: 'Music',
      2: 'SFX',
      3: 'Voice',
      4: 'Ambience',
      5: 'Aux',
    };
    return busNames[busId] ?? 'Bus $busId';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.9: BUS COLOR CODING
  // ═══════════════════════════════════════════════════════════════════════════

  /// P1.9: Bus color mapping for visual indicators
  static const Map<int, Color> _busColors = {
    0: Color(0xFFFFFFFF), // Master - White
    1: Color(0xFF40C8FF), // Music - Cyan
    2: Color(0xFFFF9040), // SFX - Orange
    3: Color(0xFF40FF90), // Voice - Green
    4: Color(0xFF8B5CF6), // Ambience - Purple
    5: Color(0xFFFFD700), // Aux - Gold
  };

  /// P1.9: Get bus color for a stage
  Color? _getStageBusColor(String stageType) {
    final normalizedStage = stageType.toUpperCase();
    final event = eventRegistry.getEventForStage(normalizedStage);
    if (event != null && event.layers.isNotEmpty) {
      final busId = event.layers.first.busId;
      return _busColors[busId];
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.4: A/B COMPARISON SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// P1.4: Build A/B toggle button for header
  Widget _buildAbToggleButton() {
    return Tooltip(
      message: _abCompareEnabled ? 'Disable A/B Compare' : 'Enable A/B Compare',
      child: InkWell(
        onTap: _toggleAbCompare,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _abCompareEnabled
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: _abCompareEnabled
                  ? FluxForgeTheme.accentBlue
                  : FluxForgeTheme.borderSubtle,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.compare_arrows,
                size: 10,
                color: _abCompareEnabled
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'A/B',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: _abCompareEnabled
                      ? FluxForgeTheme.accentBlue
                      : FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// P1.4: Toggle A/B compare mode
  void _toggleAbCompare() {
    setState(() {
      _abCompareEnabled = !_abCompareEnabled;
      if (!_abCompareEnabled) {
        _abSelectedStage = null;
        _abVariantA = null;
        _abVariantB = null;
        _abCurrentVariant = null;
        _abIsPlaying = false;
      }
    });
  }

  /// P1.4: Start A/B comparison for a stage
  void _startAbCompare(String stageType) {
    final audioPath = _getStageAudioPath(stageType);
    if (audioPath == null) {
      _showAbHint('No audio assigned to this stage');
      return;
    }

    setState(() {
      _abSelectedStage = stageType;
      _abVariantA = audioPath;
      _abVariantB = null; // User needs to assign variant B
      _abCurrentVariant = 'A';
    });

    _showAbHint('Variant A loaded. Drop another audio for variant B.');
  }

  /// P1.4: Set variant B for A/B comparison
  void _setAbVariantB(String audioPath) {
    setState(() {
      _abVariantB = audioPath;
    });
    _showAbHint('Variant B set. Use A/B buttons to compare.');
  }

  /// P1.4: Play variant A
  void _playVariantA() {
    if (_abVariantA == null) return;
    setState(() {
      _abCurrentVariant = 'A';
      _abIsPlaying = true;
    });
    // Trigger playback via AudioPlaybackService
    AudioPlaybackService.instance.playFileToBus(
      _abVariantA!,
      busId: 2, // SFX bus
      source: PlaybackSource.slotlab,
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _abIsPlaying = false);
      }
    });
  }

  /// P1.4: Play variant B
  void _playVariantB() {
    if (_abVariantB == null) return;
    setState(() {
      _abCurrentVariant = 'B';
      _abIsPlaying = true;
    });
    // Trigger playback via AudioPlaybackService
    AudioPlaybackService.instance.playFileToBus(
      _abVariantB!,
      busId: 2, // SFX bus
      source: PlaybackSource.slotlab,
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _abIsPlaying = false);
      }
    });
  }

  /// P1.4: Apply selected variant (commit A or B as the stage audio)
  void _applyAbVariant(String variant) {
    final path = variant == 'A' ? _abVariantA : _abVariantB;
    if (path == null || _abSelectedStage == null) return;

    // TODO: Update EventRegistry with selected path
    // For now, just show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied variant $variant to ${_formatStageName(_abSelectedStage!)}'),
        duration: const Duration(seconds: 2),
        backgroundColor: FluxForgeTheme.accentGreen,
      ),
    );

    // Clear A/B state
    setState(() {
      _abSelectedStage = null;
      _abVariantA = null;
      _abVariantB = null;
      _abCurrentVariant = null;
    });
  }

  /// P1.4: Show A/B hint message
  void _showAbHint(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: FluxForgeTheme.accentBlue,
      ),
    );
  }

  /// P1.4: Build A/B comparison panel (shown when A/B mode is active and stage is selected)
  Widget _buildAbComparePanel() {
    if (!_abCompareEnabled || _abSelectedStage == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid.withOpacity(0.9),
        border: Border(
          top: BorderSide(color: FluxForgeTheme.accentBlue.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          // Stage name
          Text(
            _formatStageName(_abSelectedStage!),
            style: const TextStyle(
              color: FluxForgeTheme.textPrimary,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 12),
          // Variant A button
          _buildVariantButton('A', _abVariantA != null, _abCurrentVariant == 'A'),
          const SizedBox(width: 4),
          // Variant B button
          _buildVariantButton('B', _abVariantB != null, _abCurrentVariant == 'B'),
          const Spacer(),
          // Apply buttons
          if (_abVariantA != null && _abVariantB != null) ...[
            _buildApplyButton('A'),
            const SizedBox(width: 4),
            _buildApplyButton('B'),
            const SizedBox(width: 8),
          ],
          // Close button
          InkWell(
            onTap: () => setState(() {
              _abSelectedStage = null;
              _abVariantA = null;
              _abVariantB = null;
            }),
            child: const Icon(
              Icons.close,
              size: 12,
              color: FluxForgeTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// P1.4: Build A or B variant button
  Widget _buildVariantButton(String label, bool hasAudio, bool isActive) {
    final color = isActive ? FluxForgeTheme.accentBlue : FluxForgeTheme.textSecondary;
    final bgColor = isActive ? FluxForgeTheme.accentBlue.withOpacity(0.2) : Colors.transparent;

    return InkWell(
      onTap: hasAudio
          ? (label == 'A' ? _playVariantA : _playVariantB)
          : null,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: hasAudio ? color : FluxForgeTheme.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: hasAudio ? color : FluxForgeTheme.textSecondary.withOpacity(0.5),
              ),
            ),
            if (isActive && _abIsPlaying) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.volume_up,
                size: 10,
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// P1.4: Build apply button for A or B
  Widget _buildApplyButton(String variant) {
    return InkWell(
      onTap: () => _applyAbVariant(variant),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: FluxForgeTheme.accentGreen.withOpacity(0.1),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: FluxForgeTheme.accentGreen.withOpacity(0.5),
            width: 0.5,
          ),
        ),
        child: Text(
          'Use $variant',
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: FluxForgeTheme.accentGreen,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.6: MULTI-SELECT SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// P1.6: Check if stage at index is selected
  bool _isStageSelected(int index) => _selectedStageIndices.contains(index);

  /// P1.6: Handle stage click with modifier keys
  void _handleStageClick(int index, {bool shiftPressed = false, bool ctrlPressed = false}) {
    setState(() {
      if (shiftPressed && _lastSelectedIndex != null) {
        // Range selection: select all between last and current
        final start = _lastSelectedIndex! < index ? _lastSelectedIndex! : index;
        final end = _lastSelectedIndex! > index ? _lastSelectedIndex! : index;
        for (var i = start; i <= end; i++) {
          _selectedStageIndices.add(i);
        }
      } else if (ctrlPressed) {
        // Toggle selection
        if (_selectedStageIndices.contains(index)) {
          _selectedStageIndices.remove(index);
        } else {
          _selectedStageIndices.add(index);
        }
        _lastSelectedIndex = index;
      } else {
        // Single selection: clear and select only this one
        _selectedStageIndices.clear();
        _selectedStageIndices.add(index);
        _lastSelectedIndex = index;
      }
    });
  }

  /// P1.6: Clear all selections
  void _clearSelection() {
    setState(() {
      _selectedStageIndices.clear();
      _lastSelectedIndex = null;
    });
  }

  /// P1.6: Select all stages
  void _selectAllStages() {
    setState(() {
      _selectedStageIndices.clear();
      for (var i = 0; i < _stages.length; i++) {
        _selectedStageIndices.add(i);
      }
    });
  }

  /// P1.6: Get list of selected stage types
  List<String> _getSelectedStageTypes() {
    return _selectedStageIndices
        .where((i) => i < _stages.length)
        .map((i) => _stages[i].stageType)
        .toList();
  }

  /// P1.6: Batch action on selected stages
  void _batchActionOnSelected(String action) {
    if (_selectedStageIndices.isEmpty) return;

    final selectedTypes = _getSelectedStageTypes();

    switch (action) {
      case 'trigger':
        // Trigger all selected stages
        for (final index in _selectedStageIndices) {
          if (index < _stages.length) {
            widget.provider.triggerStageManually(index);
          }
        }
        break;
      case 'clear':
        _clearSelection();
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Batch $action: ${selectedTypes.length} stages'),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.1: BATCH ASSIGN AUDIO TO MULTIPLE STAGES
  // ═══════════════════════════════════════════════════════════════════════════

  /// P2.1: Handle batch audio drop onto selected stages
  ///
  /// When multiple stages are selected and audio is dropped on any of them,
  /// the audio is assigned to ALL selected stages.
  void _handleBatchAudioDrop(List<AudioFileInfo> audioFiles) {
    if (_selectedStageIndices.isEmpty || audioFiles.isEmpty) return;

    final selectedTypes = _getSelectedStageTypes();
    final audio = audioFiles.first; // Use first file for stage assignment

    // Call onAudioDropped for each selected stage
    for (final stageType in selectedTypes) {
      widget.onAudioDropped?.call(audio, stageType);
    }

    // Show batch feedback
    _showBatchDropFeedback(selectedTypes, audioFiles.length > 1 ? "${audio.name} (+${audioFiles.length - 1} more)" : audio.name);

    // Clear selection after batch assign
    _clearSelection();

    // Clear caches so UI updates
    _clearWaveformCache();
  }

  /// P2.1: Check if batch assign should be used (multiple stages selected)
  bool get _shouldUseBatchAssign => _selectedStageIndices.length > 1;

  /// P2.1: Show feedback for batch audio assignment
  void _showBatchDropFeedback(List<String> stageTypes, String audioName) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: FluxForgeTheme.accentGreen, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assigned "$audioName" to ${stageTypes.length} stages',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stageTypes.take(3).map(_formatStageName).join(', ') +
                        (stageTypes.length > 3 ? ' +${stageTypes.length - 3} more' : ''),
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: FluxForgeTheme.bgMid,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// P2.1: Show file picker for batch assign via button
  Future<void> _showBatchAssignFilePicker() async {
    if (_selectedStageIndices.isEmpty) return;

    // Use file_picker to select audio file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'ogg', 'flac', 'aiff'],
      dialogTitle: 'Select audio for ${_selectedStageIndices.length} stages',
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    // Create AudioFileInfo from picked file
    // Note: Duration will be populated when file is loaded by audio system
    final audioInfo = AudioFileInfo(
      id: 'batch_${DateTime.now().millisecondsSinceEpoch}',
      path: file.path!,
      name: file.name,
      duration: Duration.zero, // Placeholder — actual duration loaded on playback
      format: file.extension?.toUpperCase() ?? 'WAV',
    );

    // Perform batch assign
    _handleBatchAudioDrop([audioInfo]);
  }

  /// P1.6: Build multi-select action bar (shown when stages are selected)
  Widget _buildMultiSelectActionBar() {
    if (_selectedStageIndices.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.accentBlue.withOpacity(0.1),
        border: Border(
          top: BorderSide(color: FluxForgeTheme.accentBlue.withOpacity(0.3)),
        ),
      ),
      child: Row(
        children: [
          // Selection count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.accentBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '${_selectedStageIndices.length} selected',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: FluxForgeTheme.accentBlue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Trigger All button
          _buildBatchActionButton('Trigger All', Icons.bolt, () => _batchActionOnSelected('trigger')),
          const SizedBox(width: 8),
          // P2.1: Assign Audio button — opens file picker for batch assign
          _buildBatchActionButton('Assign Audio', Icons.add_circle_outline, _showBatchAssignFilePicker),
          const Spacer(),
          // Select All button
          _buildBatchActionButton('All', Icons.select_all, _selectAllStages),
          const SizedBox(width: 4),
          // Clear selection button
          _buildBatchActionButton('Clear', Icons.close, _clearSelection),
        ],
      ),
    );
  }

  /// P1.6: Build batch action button
  Widget _buildBatchActionButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: FluxForgeTheme.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: FluxForgeTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 8,
                color: FluxForgeTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.2: DRAG PREVIEW SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// P1.2: Handle global drag enter to show ghost preview (supports multi-file)
  void _onDragEnterTimeline(List<AudioFileInfo> audioFiles, Offset position) {
    if (audioFiles.isEmpty) return;
    setState(() {
      _draggedAudioFiles = audioFiles;
      _dragPosition = position;
    });
    // Show waveform preview for first file
    _loadDragWaveform(audioFiles.first.path);
  }

  /// P1.2: Update drag position for ghost preview
  void _onDragUpdateTimeline(Offset position) {
    setState(() {
      _dragPosition = position;
    });
  }

  /// P1.2: Clear drag preview on leave/accept
  void _onDragLeaveTimeline() {
    setState(() {
      _draggedAudioFiles = null;
      _dragPosition = null;
      _dragWaveformCache = null;
    });
  }

  /// P1.2: Load waveform for dragged audio file
  Future<void> _loadDragWaveform(String audioPath) async {
    try {
      final cacheKey = 'drag_preview_${audioPath.hashCode}';
      final json = NativeFFI.instance.generateWaveformFromFile(audioPath, cacheKey);
      if (json != null && json.isNotEmpty && mounted) {
        final waveform = _parseWaveformJson(json);
        setState(() {
          _dragWaveformCache = waveform;
        });
      }
    } catch (e) {
      debugPrint('[StageTrace] Drag waveform load error: $e');
    }
  }

  /// P1.2: Build ghost waveform preview overlay
  Widget _buildDragPreview() {
    if (_draggedAudioFiles == null || _draggedAudioFiles!.isEmpty || _dragPosition == null) {
      return const SizedBox.shrink();
    }
    final firstFile = _draggedAudioFiles!.first;
    final fileCount = _draggedAudioFiles!.length;

    return Positioned(
      left: _dragPosition!.dx - 40, // Center the 80px wide preview
      top: _dragPosition!.dy - 50,   // Position above cursor
      child: IgnorePointer(
        child: Container(
          width: 80,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgMid.withOpacity(0.95),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: FluxForgeTheme.accentBlue.withOpacity(0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Waveform preview
              if (_dragWaveformCache != null)
                SizedBox(
                  width: 72,
                  height: 24,
                  child: CustomPaint(
                    painter: _MiniWaveformPainter(
                      waveform: _dragWaveformCache!,
                      color: FluxForgeTheme.accentBlue,
                    ),
                  ),
                )
              else
                SizedBox(
                  width: 72,
                  height: 24,
                  child: Center(
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1,
                        valueColor: AlwaysStoppedAnimation(FluxForgeTheme.accentBlue),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 2),
              // File name (with multi-file badge)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fileCount > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$fileCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 6,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      firstFile.name.length > 12
                          ? '${firstFile.name.substring(0, 10)}...'
                          : firstFile.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.3: STAGE GROUPING SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// P1.3: Get group name for a stage type
  String? _getStageGroup(String stageType) {
    final normalized = stageType.toLowerCase();
    // Direct match
    if (_stageGroups.containsKey(normalized)) {
      return _stageGroups[normalized];
    }
    // Prefix match (e.g., reel_stop_0 -> reel_stop -> spin)
    for (final entry in _stageGroups.entries) {
      if (normalized.startsWith(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// P1.3: Get color for a stage group
  Color _getGroupColor(String? group) {
    if (group == null) return Colors.grey;
    return _groupColors[group] ?? Colors.grey;
  }

  /// P1.3: Build stage group indicators for mini progress
  Widget _buildStageGroupIndicators() {
    if (_stages.isEmpty) return const SizedBox.shrink();

    // Calculate group spans
    final groupSpans = <({String group, int start, int end})>[];
    String? currentGroup;
    int groupStart = 0;

    for (int i = 0; i < _stages.length; i++) {
      final group = _getStageGroup(_stages[i].stageType);
      if (group != currentGroup) {
        if (currentGroup != null) {
          groupSpans.add((group: currentGroup, start: groupStart, end: i - 1));
        }
        currentGroup = group;
        groupStart = i;
      }
    }
    if (currentGroup != null) {
      groupSpans.add((group: currentGroup, start: groupStart, end: _stages.length - 1));
    }

    return Container(
      height: 12,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: groupSpans.map((span) {
          final color = _getGroupColor(span.group);
          final width = (span.end - span.start + 1) / _stages.length;
          final isActive = _currentStageIndex >= span.start && _currentStageIndex <= span.end;

          return Flexible(
            flex: ((span.end - span.start + 1) * 100).toInt(),
            child: Tooltip(
              message: '${span.group.toUpperCase()} (${span.end - span.start + 1} stages)',
              child: Container(
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: isActive ? color : color.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(3),
                  border: isActive
                      ? Border.all(color: Colors.white.withOpacity(0.5), width: 0.5)
                      : null,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// P1.3: Build group legend (for header)
  Widget _buildGroupLegend() {
    final activeGroups = <String>{};
    for (final stage in _stages) {
      final group = _getStageGroup(stage.stageType);
      if (group != null) activeGroups.add(group);
    }

    if (activeGroups.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: activeGroups.take(4).map((group) {
        final color = _getGroupColor(group);
        final isCurrentGroup = _currentStageIndex >= 0 &&
            _currentStageIndex < _stages.length &&
            _getStageGroup(_stages[_currentStageIndex].stageType) == group;

        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: isCurrentGroup ? color.withOpacity(0.3) : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: color.withOpacity(isCurrentGroup ? 1.0 : 0.4),
                width: 0.5,
              ),
            ),
            child: Text(
              group.substring(0, 1).toUpperCase() + group.substring(1, (group.length).clamp(0, 4)),
              style: TextStyle(
                color: color.withOpacity(isCurrentGroup ? 1.0 : 0.6),
                fontSize: 7,
                fontWeight: isCurrentGroup ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P1.8: INLINE WAVEFORM STRIP SYSTEM
  // ═══════════════════════════════════════════════════════════════════════════

  /// P1.8: Toggle inline waveform display
  void _toggleInlineWaveform() {
    setState(() {
      _showInlineWaveform = !_showInlineWaveform;
      if (_showInlineWaveform && _inlineWaveformData.isEmpty) {
        _loadInlineWaveforms();
      }
    });
  }

  /// P1.8: Load waveforms for all stages with audio
  Future<void> _loadInlineWaveforms() async {
    if (_isLoadingInlineWaveforms || _stages.isEmpty) return;

    setState(() => _isLoadingInlineWaveforms = true);

    final totalDuration = _stages.last.timestampMs - _stages.first.timestampMs;
    if (totalDuration <= 0) {
      setState(() => _isLoadingInlineWaveforms = false);
      return;
    }

    final newData = <int, ({String stageType, double start, double duration, Float32List? waveform})>{};

    for (int i = 0; i < _stages.length; i++) {
      final stage = _stages[i];
      if (!_stageHasAudio(stage.stageType)) continue;

      // Calculate normalized start position (0-1)
      final startPos = (stage.timestampMs - _stages.first.timestampMs) / totalDuration;

      // Estimate duration to next stage or end
      double durationMs = 500.0; // Default 500ms
      if (i + 1 < _stages.length) {
        durationMs = (_stages[i + 1].timestampMs - stage.timestampMs).toDouble();
      }
      final normalizedDuration = durationMs / totalDuration;

      // Load waveform
      final waveform = await _loadStageWaveform(stage.stageType);

      newData[i] = (
        stageType: stage.stageType,
        start: startPos,
        duration: normalizedDuration.clamp(0.01, 0.5), // Clamp duration
        waveform: waveform,
      );
    }

    if (mounted) {
      setState(() {
        _inlineWaveformData.clear();
        _inlineWaveformData.addAll(newData);
        _isLoadingInlineWaveforms = false;
      });
    }
  }

  /// P1.8: Clear inline waveform cache (call when stages change)
  void _clearInlineWaveformCache() {
    _inlineWaveformData.clear();
    if (_showInlineWaveform) {
      _loadInlineWaveforms();
    }
  }

  /// P1.8: Build inline waveform toggle button for header
  Widget _buildInlineWaveformToggle() {
    return Tooltip(
      message: _showInlineWaveform ? 'Hide audio strip' : 'Show audio strip',
      child: InkWell(
        onTap: _toggleInlineWaveform,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _showInlineWaveform
                ? FluxForgeTheme.accentOrange.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: _showInlineWaveform
                  ? FluxForgeTheme.accentOrange
                  : FluxForgeTheme.borderSubtle,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq,
                size: 10,
                color: _showInlineWaveform
                    ? FluxForgeTheme.accentOrange
                    : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 3),
              Text(
                'Audio',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: _showInlineWaveform
                      ? FluxForgeTheme.accentOrange
                      : FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P2.2: HIGH CONTRAST MODE TOGGLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// P2.2: Build high contrast mode toggle button
  Widget _buildHighContrastToggle() {
    return Tooltip(
      message: _highContrastMode ? 'Disable high contrast' : 'Enable high contrast',
      child: InkWell(
        onTap: _toggleHighContrastMode,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _highContrastMode
                ? FluxForgeTheme.accentCyan.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: _highContrastMode
                  ? FluxForgeTheme.accentCyan
                  : FluxForgeTheme.borderSubtle,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.contrast,
                size: 10,
                color: _highContrastMode
                    ? FluxForgeTheme.accentCyan
                    : FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 3),
              Text(
                'HC',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: _highContrastMode
                      ? FluxForgeTheme.accentCyan
                      : FluxForgeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// P2.2: Toggle high contrast mode
  void _toggleHighContrastMode() {
    setState(() {
      _highContrastMode = !_highContrastMode;
      // Sync with global StageConfig
      StageConfig.instance.setHighContrastMode(_highContrastMode);
    });
  }

  /// P2.4: Build parallel lanes toggle button
  Widget _buildParallelLanesToggle() {
    return Tooltip(
      message: _parallelLanesEnabled
          ? 'Disable parallel lanes (${_maxLanes} lanes)'
          : 'Enable parallel lanes for overlapping stages',
      child: InkWell(
        onTap: _toggleParallelLanes,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: _parallelLanesEnabled
                ? FluxForgeTheme.accentBlue.withOpacity(0.2)
                : FluxForgeTheme.bgMid.withOpacity(0.6),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _parallelLanesEnabled
                  ? FluxForgeTheme.accentBlue.withOpacity(0.5)
                  : FluxForgeTheme.borderSubtle.withOpacity(0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.view_agenda_outlined,
                size: 12,
                color: _parallelLanesEnabled
                    ? FluxForgeTheme.accentBlue
                    : FluxForgeTheme.textSecondary,
              ),
              if (_parallelLanesEnabled && _maxLanes > 1) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.accentBlue.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '$_maxLanes',
                    style: const TextStyle(
                      color: FluxForgeTheme.accentBlue,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// P2.4: Toggle parallel lanes visualization
  void _toggleParallelLanes() {
    setState(() {
      _parallelLanesEnabled = !_parallelLanesEnabled;
      _calculateStageLanes();  // Recalculate with new setting
    });
  }

  /// P2.3: Build stage template selector dropdown
  Widget _buildTemplateSelector() {
    return PopupMenuButton<StageTemplate>(
      tooltip: 'Apply stage template',
      offset: const Offset(0, 24),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(maxWidth: 280),
      onSelected: _applyTemplate,
      itemBuilder: (context) => StageTemplates.all.map((template) {
        return PopupMenuItem<StageTemplate>(
          value: template,
          height: 56,
          child: Row(
            children: [
              Icon(
                template.icon,
                size: 18,
                color: FluxForgeTheme.accentCyan,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      template.name,
                      style: const TextStyle(
                        color: FluxForgeTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      template.description,
                      style: TextStyle(
                        color: FluxForgeTheme.textSecondary.withOpacity(0.7),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentOrange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${template.stages.length}',
                  style: const TextStyle(
                    color: FluxForgeTheme.accentOrange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: FluxForgeTheme.bgMid.withOpacity(0.6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluxForgeTheme.borderSubtle.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.playlist_add,
              size: 14,
              color: FluxForgeTheme.accentCyan,
            ),
            const SizedBox(width: 4),
            const Text(
              'Templates',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: FluxForgeTheme.textSecondary.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }

  /// P2.3: Apply selected stage template
  void _applyTemplate(StageTemplate template) {
    // Notify parent via callback
    widget.onTemplateApplied?.call(template);

    // Show confirmation snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(template.icon, color: Colors.white, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Applied "${template.name}" template (${template.stages.length} stages)',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: FluxForgeTheme.accentCyan.withOpacity(0.9),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  /// P1.8: Build inline waveform strip with stage markers
  Widget _buildInlineWaveformStrip(double totalWidth, double totalDuration) {
    if (!_showInlineWaveform) return const SizedBox.shrink();

    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep.withOpacity(0.8),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FluxForgeTheme.borderSubtle.withOpacity(0.5)),
      ),
      child: Stack(
        children: [
          // Loading indicator
          if (_isLoadingInlineWaveforms)
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(FluxForgeTheme.accentOrange),
                ),
              ),
            ),
          // Waveform segments with stage markers
          if (!_isLoadingInlineWaveforms)
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CustomPaint(
                size: Size(totalWidth - 16, 38),
                painter: _InlineWaveformStripPainter(
                  stages: _stages,
                  waveformData: _inlineWaveformData,
                  currentStageIndex: _currentStageIndex,
                  playheadPosition: _playheadPosition,
                  isPlaying: _isPlaying,
                  zoomLevel: _zoomLevel,
                  panOffset: _panOffset,
                  getStageColor: _getStageColor,
                ),
              ),
            ),
          // Stage position markers (vertical lines)
          if (!_isLoadingInlineWaveforms)
            ..._buildInlineStageMarkers(totalWidth - 16, totalDuration),
          // Playhead
          if (_isPlaying && !_isLoadingInlineWaveforms)
            Positioned(
              left: (((_playheadPosition - _panOffset) * _zoomLevel) * (totalWidth - 16)).clamp(0, totalWidth - 16),
              top: 0,
              bottom: 0,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: FluxForgeTheme.accentGreen,
                  boxShadow: [
                    BoxShadow(
                      color: FluxForgeTheme.accentGreen.withOpacity(0.6),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// P1.8: Build vertical stage markers for inline waveform strip
  List<Widget> _buildInlineStageMarkers(double width, double totalDuration) {
    if (_stages.isEmpty || totalDuration <= 0) return [];

    return _stages.asMap().entries.map((entry) {
      final index = entry.key;
      final stage = entry.value;
      final position = (stage.timestampMs - _stages.first.timestampMs) / totalDuration;
      final zoomedPosition = (position - _panOffset) * _zoomLevel;

      // Skip markers outside visible area
      if (zoomedPosition < -0.05 || zoomedPosition > 1.05) {
        return const SizedBox.shrink();
      }

      final x = (zoomedPosition * width).clamp(0.0, width);
      final color = _getStageColor(stage.stageType);
      final isActive = index == _currentStageIndex;
      final hasAudio = _stageHasAudio(stage.stageType);

      return Positioned(
        left: x,
        top: 0,
        bottom: 0,
        child: Tooltip(
          message: '${_formatStageName(stage.stageType)}${hasAudio ? ' 🎵' : ''}',
          child: Container(
            width: isActive ? 3 : 1,
            decoration: BoxDecoration(
              color: color.withOpacity(isActive ? 1.0 : 0.6),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.5),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
            child: hasAudio
                ? Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: FluxForgeTheme.bgDeep, width: 1),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // P1.7: Check system preference for reduced motion
    _reduceMotion = MediaQuery.of(context).disableAnimations;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
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
              // P1.4: A/B Comparison panel (shown when active)
              _buildAbComparePanel(),
              // P1.6: Multi-select action bar (shown when stages are selected)
              _buildMultiSelectActionBar(),
              // Timeline (P0.5: Wrapped with Focus for keyboard navigation)
              Expanded(
                child: Focus(
                  focusNode: _timelineFocusNode,
                  onKeyEvent: _handleKeyEvent,
                  child: _buildTimeline(),
                ),
              ),
              // P1.8: Inline waveform strip (below timeline)
              if (_showInlineWaveform && _stages.isNotEmpty)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final totalWidth = constraints.maxWidth;
                    final totalDuration = _stages.last.timestampMs - _stages.first.timestampMs;
                    return _buildInlineWaveformStrip(totalWidth, totalDuration.toDouble());
                  },
                ),
              // P1.3: Stage group indicators
              if (widget.showMiniProgress && _stages.isNotEmpty) _buildStageGroupIndicators(),
              // Mini progress
              if (widget.showMiniProgress) _buildMiniProgress(),
            ],
          ),
        ),
        // P1.2: Drag preview overlay
        _buildDragPreview(),
      ],
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
              // P1.7: Reduced motion - static opacity
              final pulseOpacity = _reduceMotion ? 1.0 : _pulseAnimation.value;
              return Icon(
                Icons.timeline,
                size: 12,
                color: _isPlaying
                    ? FluxForgeTheme.accentGreen.withOpacity(pulseOpacity)
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
          // P1.3: Group legend
          if (_stages.isNotEmpty) _buildGroupLegend(),
          // P1.8: Inline waveform toggle
          if (_stages.isNotEmpty) ...[
            const SizedBox(width: 8),
            _buildInlineWaveformToggle(),
          ],
          // P1.4: A/B comparison toggle
          if (_stages.isNotEmpty) ...[
            const SizedBox(width: 8),
            _buildAbToggleButton(),
          ],
          // P0.11: Export button for regression testing
          if (_stages.isNotEmpty) ...[
            const SizedBox(width: 8),
            _buildExportButton(),
          ],
          // P2.3: Stage template selector
          const SizedBox(width: 8),
          _buildTemplateSelector(),
          // P2.2: High contrast toggle
          const SizedBox(width: 8),
          _buildHighContrastToggle(),
          // P2.4: Parallel lanes toggle
          const SizedBox(width: 8),
          _buildParallelLanesToggle(),
          // P0.7: Latency metering
          const SizedBox(width: 8),
          _buildLatencyIndicator(),
          // P0.2: Zoom controls
          const SizedBox(width: 8),
          _buildZoomControls(),
        ],
      ),
    );
  }

  /// P0.7: Build latency indicator badge
  Widget _buildLatencyIndicator() {
    final isWarning = _avgLatencyMs > _latencyWarningThreshold;
    final color = isWarning ? FluxForgeTheme.accentRed : FluxForgeTheme.accentGreen;

    return Tooltip(
      message: 'Audio latency\\n'
          'Avg: ${_avgLatencyMs.toStringAsFixed(1)}ms\\n'
          'Max: ${_maxLatencyMs.toStringAsFixed(1)}ms',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withOpacity(0.5), width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWarning ? Icons.warning_amber : Icons.speed,
              size: 10,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              '${_avgLatencyMs.toStringAsFixed(1)}ms',
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // P0.11: EXPORT STAGE TRACE FOR REGRESSION TESTING
  // ═══════════════════════════════════════════════════════════════════════════

  /// P0.11: Build export button for QA regression testing
  Widget _buildExportButton() {
    return Tooltip(
      message: 'Export stage trace to clipboard (JSON)',
      child: InkWell(
        onTap: _exportStageTrace,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: FluxForgeTheme.bgDeep,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: FluxForgeTheme.borderSubtle,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download,
                size: 10,
                color: FluxForgeTheme.textSecondary,
              ),
              const SizedBox(width: 3),
              Text(
                'Export',
                style: TextStyle(
                  color: FluxForgeTheme.textSecondary,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// P0.11: Export stage trace to clipboard as JSON for regression testing
  Future<void> _exportStageTrace() async {
    if (_stages.isEmpty) return;

    final provider = widget.provider;

    // Build export data structure
    final exportData = {
      'version': '1.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'spinId': provider.lastResult?.spinId ?? 'unknown',
      'totalDurationMs': _stages.isNotEmpty
          ? _stages.map((s) => s.timestampMs).reduce((a, b) => a > b ? a : b)
          : 0,
      'stageCount': _stages.length,
      'latencyMetrics': {
        'avgMs': _avgLatencyMs,
        'maxMs': _maxLatencyMs,
        'warningThreshold': _latencyWarningThreshold,
      },
      'validationIssues': provider.lastValidationIssues.map((i) => i.toJson()).toList(),
      'stages': _stages.map((stage) => <String, dynamic>{
          'type': stage.stageType,
          'timestampMs': stage.timestampMs,
          'payload': stage.payload,
        }).toList(),
    };

    // Convert to formatted JSON
    final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);

    // Copy to clipboard
    await Clipboard.setData(ClipboardData(text: jsonString));

    // Show feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text('Stage trace exported (${_stages.length} stages)'),
            ],
          ),
          backgroundColor: FluxForgeTheme.accentGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// P0.2: Build zoom control buttons
  Widget _buildZoomControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Zoom out
        _buildZoomButton(
          icon: Icons.remove,
          onTap: _zoomLevel > _minZoom ? _zoomOut : null,
          tooltip: 'Zoom out',
        ),
        // Zoom level indicator
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text(
            '${(_zoomLevel * 100).round()}%',
            style: TextStyle(
              color: _zoomLevel > 1.0
                  ? FluxForgeTheme.accentBlue
                  : FluxForgeTheme.textSecondary,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // Zoom in
        _buildZoomButton(
          icon: Icons.add,
          onTap: _zoomLevel < _maxZoom ? _zoomIn : null,
          tooltip: 'Zoom in',
        ),
        const SizedBox(width: 4),
        // Reset zoom
        _buildZoomButton(
          icon: Icons.fit_screen,
          onTap: _zoomLevel != 1.0 ? _resetZoom : null,
          tooltip: 'Fit to view',
        ),
      ],
    );
  }

  Widget _buildZoomButton({
    required IconData icon,
    VoidCallback? onTap,
    required String tooltip,
  }) {
    final isEnabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: isEnabled
                ? FluxForgeTheme.bgDeep
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isEnabled
                  ? FluxForgeTheme.borderSubtle
                  : Colors.transparent,
              width: 0.5,
            ),
          ),
          child: Icon(
            icon,
            size: 10,
            color: isEnabled
                ? FluxForgeTheme.textSecondary
                : FluxForgeTheme.textSecondary.withOpacity(0.3),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    if (_stages.isEmpty) {
      // Empty state - but still accept drops for pre-assignment
      return DragTarget<List<AudioFileInfo>>(
        onWillAcceptWithDetails: (details) {
          setState(() => _isDraggingOver = true);
          // P1.2: Show drag preview
          _onDragEnterTimeline(details.data, details.offset);
          return true;
        },
        onMove: (details) {
          // P1.2: Update drag position
          _onDragUpdateTimeline(details.offset);
        },
        onLeave: (_) {
          setState(() => _isDraggingOver = false);
          // P1.2: Clear drag preview
          _onDragLeaveTimeline();
        },
        onAcceptWithDetails: (details) {
          setState(() => _isDraggingOver = false);
          // P1.2: Clear drag preview
          _onDragLeaveTimeline();
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

        // P0.2: Calculate zoomed width and visible range
        final zoomedWidth = totalWidth * _zoomLevel;
        final (visibleStart, visibleEnd) = _getVisibleRange();

        return GestureDetector(
          // P0.2: Pan gesture for zoomed timeline
          onHorizontalDragUpdate: _zoomLevel > 1.0
              ? (details) => _onHorizontalDragUpdate(details, totalWidth)
              : null,
          // P0.2: Mouse scroll to zoom
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                if (event.scrollDelta.dy < 0) {
                  _zoomIn();
                } else if (event.scrollDelta.dy > 0) {
                  _zoomOut();
                }
              }
            },
            child: Stack(
              clipBehavior: Clip.hardEdge,
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

                // P0.2: Visible range indicator when zoomed
                if (_zoomLevel > 1.0)
                  Positioned(
                    left: 8 + (totalWidth * visibleStart),
                    top: 20,
                    child: Container(
                      width: totalWidth * (visibleEnd - visibleStart),
                      height: 4,
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.accentBlue.withOpacity(0.3),
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

                  // P0.2: Apply zoom transformation
                  final zoomedPosition = (position - _panOffset) * _zoomLevel;
                  final x = 8 + (totalWidth * zoomedPosition);

                  // P0.2: Skip markers outside visible area (with padding for partial visibility)
                  if (zoomedPosition < -0.1 || zoomedPosition > 1.1) {
                    return const SizedBox.shrink();
                  }

                  final isActive = index == _currentStageIndex;
                  final isPast = index < _currentStageIndex;
                  final isHovered = _hoveredStageIndex == index;
                  final color = _getStageColor(stage.stageType);

                  // P2.4: Calculate lane offset for overlapping stages
                  final laneOffset = _getStageLaneOffset(index);

              // P0.4: Larger touch targets (44px minimum)
              return Positioned(
                left: x - 22, // Center 44px touch target
                top: laneOffset, // P2.4: Offset by lane for parallel visualization
                child: SizedBox(
                  width: 44,
                  height: 44, // P0.4: Minimum touch target size
                  child: DragTarget<List<AudioFileInfo>>(
                  onWillAcceptWithDetails: (details) {
                    setState(() => _hoveredStageIndex = index);
                    // P1.2: Show drag preview
                    _onDragEnterTimeline(details.data, details.offset);
                    return true;
                  },
                  onMove: (details) {
                    // P1.2: Update drag position
                    _onDragUpdateTimeline(details.offset);
                  },
                  onLeave: (_) {
                    setState(() {
                      if (_hoveredStageIndex == index) _hoveredStageIndex = null;
                    });
                    // P1.2: Clear drag preview
                    _onDragLeaveTimeline();
                  },
                  onAcceptWithDetails: (details) {
                    setState(() => _hoveredStageIndex = null);
                    // P1.2: Clear drag preview
                    _onDragLeaveTimeline();

                    // P2.1: Check if batch assign should be used
                    if (_shouldUseBatchAssign && _selectedStageIndices.contains(index)) {
                      // Batch assign to all selected stages
                      _handleBatchAudioDrop(details.data);
                    } else {
                      // Single stage assign (original behavior)
                      widget.onAudioDropped?.call(details.data.first, stage.stageType);
                      _showDropFeedback(stage.stageType, details.data.first.name);
                    }
                  },
                  builder: (context, candidateData, rejectedData) {
                    final isDragTarget = candidateData.isNotEmpty;
                    final isMouseHovered = _mouseHoverIndex == index;
                    final isFocused = _focusedStageIndex == index; // P0.5
                    final isSelected = _isStageSelected(index); // P1.6

                    // P2.5: RepaintBoundary to isolate marker repaints
                    // P0.6: Enhanced tooltip with stage + audio + bus info
                    return RepaintBoundary(
                      child: Tooltip(
                      message: _buildStageTooltip(stage),
                      preferBelow: false,
                      verticalOffset: 24,
                      waitDuration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgMid.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: FluxForgeTheme.borderSubtle),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        height: 1.4,
                      ),
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _mouseHoverIndex = index),
                        onExit: (_) => setState(() {
                          if (_mouseHoverIndex == index) _mouseHoverIndex = null;
                        }),
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            // P1.6: Multi-select support with modifier keys
                            final shiftPressed = HardwareKeyboard.instance.isShiftPressed;
                            final ctrlPressed = HardwareKeyboard.instance.isControlPressed ||
                                HardwareKeyboard.instance.isMetaPressed; // Cmd on Mac

                            if (shiftPressed || ctrlPressed) {
                              _handleStageClick(index, shiftPressed: shiftPressed, ctrlPressed: ctrlPressed);
                            } else {
                              // Normal click: trigger the stage and clear selection
                              _selectedStageIndices.clear();
                              widget.provider.triggerStageManually(index);
                            }
                          },
                          // P1.5: Right-click context menu
                          onSecondaryTapUp: (details) {
                            _showStageContextMenu(
                              context,
                              details.globalPosition,
                              stage,
                              index,
                            );
                          },
                          child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          // P1.7: Reduced motion - use static values
                          final scale = _reduceMotion
                              ? (isActive ? 1.1 : (isDragTarget ? 1.2 : 1.0))
                              : isActive
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
                                mainAxisAlignment: MainAxisAlignment.center, // P0.4: Center in touch target
                                children: [
                                  // Stage dot/icon with drop indicator and play button
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // P1.6: Selection ring indicator
                                      if (isSelected)
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: FluxForgeTheme.accentBlue,
                                                width: 2,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: FluxForgeTheme.accentBlue.withOpacity(0.4),
                                                  blurRadius: 6,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      // P1.9: Bus color indicator ring (bottom)
                                      if (_stageHasAudio(stage.stageType) && !isDragTarget)
                                        Positioned(
                                          bottom: -2,
                                          child: Container(
                                            width: 8,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: _getStageBusColor(stage.stageType) ?? Colors.grey,
                                              borderRadius: BorderRadius.circular(2),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: (_getStageBusColor(stage.stageType) ?? Colors.grey)
                                                      .withOpacity(0.5),
                                                  blurRadius: 4,
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      // P0.1: Audio indicator badge
                                      if (_stageHasAudio(stage.stageType) && !isDragTarget)
                                        Positioned(
                                          right: -4,
                                          top: -4,
                                          child: Container(
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: FluxForgeTheme.accentGreen,
                                              shape: BoxShape.circle,
                                              border: Border.all(color: FluxForgeTheme.bgDeep, width: 1.5),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '${_getStageLayerCount(stage.stageType)}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 7,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      AnimatedContainer(
                                        duration: _animDuration150, // P1.21
                                        width: isDragTarget ? 28 : (isFocused || isMouseHovered ? 24 : 20),
                                        height: isDragTarget ? 28 : (isFocused || isMouseHovered ? 24 : 20),
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
                                            // P0.5: Focus ring uses accent blue
                                            color: isFocused
                                                ? FluxForgeTheme.accentBlue
                                                : isDragTarget
                                                    ? FluxForgeTheme.accentGreen
                                                    : isMouseHovered
                                                        ? Colors.white
                                                        : color,
                                            width: isFocused ? 2.5 : (isDragTarget ? 3 : (isActive || isMouseHovered ? 2 : 1)),
                                          ),
                                          boxShadow: (isActive || isDragTarget || isMouseHovered || isFocused)
                                              ? [
                                                  BoxShadow(
                                                    // P0.5: Focus uses blue glow
                                                    color: (isFocused
                                                            ? FluxForgeTheme.accentBlue
                                                            : isDragTarget
                                                                ? FluxForgeTheme.accentGreen
                                                                : color)
                                                        .withOpacity(0.6),
                                                    blurRadius: isFocused ? 10 : (isDragTarget ? 12 : (isMouseHovered ? 10 : 8)),
                                                    spreadRadius: isFocused ? 3 : (isDragTarget ? 4 : (isMouseHovered ? 3 : 2)),
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
                                  // P0.1: Waveform preview on hover
                                  if (isMouseHovered && _stageHasAudio(stage.stageType))
                                    FutureBuilder<Float32List?>(
                                      future: _loadStageWaveform(stage.stageType),
                                      builder: (context, snapshot) {
                                        if (snapshot.hasData && snapshot.data != null) {
                                          return Container(
                                            width: 48,
                                            height: 20,
                                            margin: const EdgeInsets.only(top: 2),
                                            decoration: BoxDecoration(
                                              color: FluxForgeTheme.bgDeep.withOpacity(0.9),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: color.withOpacity(0.5),
                                                width: 0.5,
                                              ),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(3),
                                              child: CustomPaint(
                                                size: const Size(48, 20),
                                                painter: _MiniWaveformPainter(
                                                  waveform: snapshot.data!,
                                                  color: color,
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                        // Loading indicator
                                        return Container(
                                          width: 48,
                                          height: 20,
                                          margin: const EdgeInsets.only(top: 2),
                                          decoration: BoxDecoration(
                                            color: FluxForgeTheme.bgDeep.withOpacity(0.9),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Center(
                                            child: SizedBox(
                                              width: 10,
                                              height: 10,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 1,
                                                valueColor: AlwaysStoppedAnimation(color),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
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
                      ), // Close GestureDetector
                    ), // Close MouseRegion
                    ), // Close Tooltip
                    ); // P2.5: Close RepaintBoundary + return
                  },
                ),
                ), // Close SizedBox for P0.4
              );
            }),

                // Playhead (P0.2: Apply zoom to playhead position)
                if (_isPlaying)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 50),
                    left: 8 + (totalWidth * ((_playheadPosition - _panOffset) * _zoomLevel)) - 1,
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
            ),
          ),
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

  void _showStageSelectionDialog(List<AudioFileInfo> audioFiles) {
    if (audioFiles.isEmpty) return;
    final audio = audioFiles.first; // Use first file for stage selection
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

/// P1.19: Compact horizontal stage progress bar.
///
/// A lightweight alternative to [StageTraceWidget] for use in headers,
/// footers, or space-constrained layouts. Shows:
/// - Playing indicator (green dot)
/// - Stage segments with progress colors
/// - Current stage highlighted
///
/// ## Usage
/// ```dart
/// StageProgressBar(
///   provider: slotLabProvider,
///   height: 24,
/// )
/// ```
///
/// ## See Also
/// - [StageTraceWidget] — Full-featured timeline widget
/// - [StageConfig] — Stage color configuration
class StageProgressBar extends StatelessWidget {
  /// The SlotLab provider that supplies stage event data.
  final SlotLabProvider provider;

  /// Height of the progress bar in pixels.
  ///
  /// Defaults to 24. Recommended range: 16-32.
  final double height;

  /// Creates a compact stage progress bar.
  const StageProgressBar({
    super.key,
    required this.provider,
    this.height = 24,
  });

  // P1.16: Stage colors now managed by StageConfig
  Color _getStageColor(String stageType) {
    return StageConfig.instance.getColor(stageType);
  }

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
                    final color = _getStageColor(stage.stageType);
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
                    color: _getStageColor(stages[currentIndex].stageType),
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

// ═══════════════════════════════════════════════════════════════════════════
// P0.1: MINI WAVEFORM PAINTER
// ═══════════════════════════════════════════════════════════════════════════

/// P2.6: Custom painter for mini waveform preview in stage markers with caching
class _MiniWaveformPainter extends CustomPainter {
  final Float32List waveform;
  final Color color;

  // P2.6: Cache for computed path
  static Path? _cachedPath;
  static Float32List? _cachedWaveform;
  static Size? _cachedSize;

  _MiniWaveformPainter({
    required this.waveform,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;

    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;
    final barWidth = size.width / waveform.length;

    // P2.6: Use cached path if waveform and size haven't changed
    Path path;
    if (_cachedPath != null &&
        _cachedWaveform == waveform &&
        _cachedSize == size) {
      path = _cachedPath!;
    } else {
      // Build new path and cache it
      path = Path();
      path.moveTo(0, centerY);

      for (int i = 0; i < waveform.length; i++) {
        final x = i * barWidth + barWidth / 2;
        final amplitude = waveform[i] * (size.height / 2 - 2);
        path.lineTo(x, centerY - amplitude);
      }

      // Complete the path by going back along the bottom
      for (int i = waveform.length - 1; i >= 0; i--) {
        final x = i * barWidth + barWidth / 2;
        final amplitude = waveform[i] * (size.height / 2 - 2);
        path.lineTo(x, centerY + amplitude);
      }

      path.close();

      // P2.6: Cache the computed path
      _cachedPath = path;
      _cachedWaveform = waveform;
      _cachedSize = size;
    }

    canvas.drawPath(path, fillPaint);

    // Draw center line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = color.withOpacity(0.3)
        ..strokeWidth = 0.5,
    );

    // Draw waveform bars
    for (int i = 0; i < waveform.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final amplitude = waveform[i] * (size.height / 2 - 2);

      if (amplitude > 0.5) {
        canvas.drawLine(
          Offset(x, centerY - amplitude),
          Offset(x, centerY + amplitude),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MiniWaveformPainter oldDelegate) {
    return waveform != oldDelegate.waveform || color != oldDelegate.color;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// P1.8: INLINE WAVEFORM STRIP PAINTER
// ═══════════════════════════════════════════════════════════════════════════

/// P1.8: Paints inline waveform strip with color-coded stage segments
/// P2.6: Added caching for static elements
class _InlineWaveformStripPainter extends CustomPainter {
  final List<SlotLabStageEvent> stages;
  final Map<int, ({String stageType, double start, double duration, Float32List? waveform})> waveformData;
  final int currentStageIndex;
  final double playheadPosition;
  final bool isPlaying;
  final double zoomLevel;
  final double panOffset;
  final Color Function(String) getStageColor;

  // P2.6: Cache for static paints (reused across frames)
  static final Paint _bgPaint = Paint()
    ..color = const Color(0xFF0A0A0C)
    ..style = PaintingStyle.fill;

  static final Paint _centerLinePaint = Paint()
    ..color = Colors.white.withOpacity(0.1)
    ..strokeWidth = 0.5;

  static final Paint _gridPaint = Paint()
    ..color = Colors.white.withOpacity(0.05)
    ..strokeWidth = 0.5;

  // P2.6: Cache key for waveform data hash
  int? _lastWaveformHash;
  static final Map<int, List<Offset>> _waveformPointsCache = {};

  _InlineWaveformStripPainter({
    required this.stages,
    required this.waveformData,
    required this.currentStageIndex,
    required this.playheadPosition,
    required this.isPlaying,
    required this.zoomLevel,
    required this.panOffset,
    required this.getStageColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (stages.isEmpty) return;

    final centerY = size.height / 2;

    // P2.6: Draw background using cached paint
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), _bgPaint);

    // P2.6: Draw center line using cached paint
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      _centerLinePaint,
    );

    // Draw waveform segments for each stage with audio
    for (final entry in waveformData.entries) {
      final index = entry.key;
      final data = entry.value;
      final waveform = data.waveform;

      if (waveform == null || waveform.isEmpty) continue;

      // Calculate zoomed position
      final zoomedStart = (data.start - panOffset) * zoomLevel;
      final zoomedDuration = data.duration * zoomLevel;

      // Skip segments outside visible area
      if (zoomedStart + zoomedDuration < 0 || zoomedStart > 1) continue;

      final segmentX = (zoomedStart * size.width).clamp(0.0, size.width);
      final segmentWidth = (zoomedDuration * size.width).clamp(8.0, size.width - segmentX);

      final color = getStageColor(data.stageType);
      final isActive = index == currentStageIndex;

      // Draw segment background
      final segmentBgPaint = Paint()
        ..color = color.withOpacity(isActive ? 0.3 : 0.15)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(segmentX, 2, segmentWidth, size.height - 4),
          const Radius.circular(2),
        ),
        segmentBgPaint,
      );

      // Draw waveform within segment
      final waveformPaint = Paint()
        ..color = color.withOpacity(isActive ? 0.9 : 0.6)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round;

      final samplesPerPixel = waveform.length / segmentWidth;
      final maxAmplitude = (size.height / 2) - 4;

      for (int i = 0; i < segmentWidth.toInt(); i++) {
        final sampleIndex = (i * samplesPerPixel).floor().clamp(0, waveform.length - 1);
        final amplitude = waveform[sampleIndex] * maxAmplitude;

        if (amplitude > 0.5) {
          final x = segmentX + i;
          canvas.drawLine(
            Offset(x, centerY - amplitude),
            Offset(x, centerY + amplitude),
            waveformPaint,
          );
        }
      }

      // Draw active glow
      if (isActive) {
        final glowPaint = Paint()
          ..color = color.withOpacity(0.4)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(segmentX, 2, segmentWidth, size.height - 4),
            const Radius.circular(2),
          ),
          glowPaint,
        );
      }
    }

    // P2.6: Draw grid lines for timing reference using cached paint
    for (int i = 1; i < 10; i++) {
      final x = (i / 10) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _gridPaint);
    }
  }

  @override
  bool shouldRepaint(_InlineWaveformStripPainter oldDelegate) {
    return stages != oldDelegate.stages ||
        waveformData != oldDelegate.waveformData ||
        currentStageIndex != oldDelegate.currentStageIndex ||
        playheadPosition != oldDelegate.playheadPosition ||
        isPlaying != oldDelegate.isPlaying ||
        zoomLevel != oldDelegate.zoomLevel ||
        panOffset != oldDelegate.panOffset;
  }
}
