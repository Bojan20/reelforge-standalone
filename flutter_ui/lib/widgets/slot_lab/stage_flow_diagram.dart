/// Stage Flow Diagram — P12.1.8
///
/// Stage sequence timeline visualization showing the flow of stages
/// during slot game playback. Color-coded by category with timing
/// visualization and interactive markers.
///
/// Features:
/// - Stage sequence timeline
/// - Color-coded by category (spin, win, feature, etc.)
/// - Timing visualization with millisecond precision
/// - Interactive markers for navigation
/// - Zoom and pan controls
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/stage_configuration_service.dart';
import '../../theme/fluxforge_theme.dart';

// =============================================================================
// STAGE FLOW EVENT MODEL
// =============================================================================

/// A stage event with timing information for the flow diagram
class StageFlowEvent {
  final String id;
  final String stageName;
  final StageCategory category;
  final int timestampMs;
  final int? durationMs;
  final bool hasAudio;
  final Map<String, dynamic>? metadata;

  const StageFlowEvent({
    required this.id,
    required this.stageName,
    required this.category,
    required this.timestampMs,
    this.durationMs,
    this.hasAudio = false,
    this.metadata,
  });

  StageFlowEvent copyWith({
    String? id,
    String? stageName,
    StageCategory? category,
    int? timestampMs,
    int? durationMs,
    bool? hasAudio,
    Map<String, dynamic>? metadata,
  }) {
    return StageFlowEvent(
      id: id ?? this.id,
      stageName: stageName ?? this.stageName,
      category: category ?? this.category,
      timestampMs: timestampMs ?? this.timestampMs,
      durationMs: durationMs ?? this.durationMs,
      hasAudio: hasAudio ?? this.hasAudio,
      metadata: metadata ?? this.metadata,
    );
  }
}

// =============================================================================
// STAGE FLOW DIAGRAM WIDGET
// =============================================================================

/// Visual timeline showing stage flow during slot game playback
class StageFlowDiagram extends StatefulWidget {
  /// Stage events to display in chronological order
  final List<StageFlowEvent> events;

  /// Current playhead position in milliseconds
  final int? playheadMs;

  /// Callback when a stage marker is tapped
  final ValueChanged<StageFlowEvent>? onStageTapped;

  /// Callback when playhead position changes via scrub
  final ValueChanged<int>? onPlayheadScrub;

  /// Whether the diagram is currently playing
  final bool isPlaying;

  /// Total duration in milliseconds (for scale)
  final int? totalDurationMs;

  /// Accent color for highlights
  final Color accentColor;

  const StageFlowDiagram({
    super.key,
    required this.events,
    this.playheadMs,
    this.onStageTapped,
    this.onPlayheadScrub,
    this.isPlaying = false,
    this.totalDurationMs,
    this.accentColor = const Color(0xFF4A9EFF),
  });

  @override
  State<StageFlowDiagram> createState() => _StageFlowDiagramState();
}

class _StageFlowDiagramState extends State<StageFlowDiagram>
    with SingleTickerProviderStateMixin {
  // View state
  double _scale = 1.0;
  double _scrollOffset = 0.0;
  String? _hoveredEventId;
  String? _selectedEventId;

  // Animation
  late AnimationController _playheadController;

  // Layout constants
  static const double _headerHeight = 32.0;
  static const double _timelineHeight = 60.0;
  static const double _markerRadius = 8.0;
  static const double _pixelsPerMs = 0.15;
  static const double _minScale = 0.25;
  static const double _maxScale = 4.0;

  // Scroll controller
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _playheadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat();
  }

  @override
  void dispose() {
    _playheadController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int get _totalDuration {
    if (widget.totalDurationMs != null) return widget.totalDurationMs!;
    if (widget.events.isEmpty) return 5000;
    final maxTime = widget.events.map((e) => e.timestampMs + (e.durationMs ?? 0)).reduce(math.max);
    return maxTime + 1000; // Add 1 second padding
  }

  double get _timelineWidth => _totalDuration * _pixelsPerMs * _scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FluxForgeTheme.borderSubtle),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _buildTimeline(),
          ),
          _buildCategoryLegend(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Row(
        children: [
          Icon(Icons.timeline, size: 16, color: widget.accentColor),
          const SizedBox(width: 8),
          const Text(
            'Stage Flow',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          // Stats
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${widget.events.length} stages',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgSurface,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(_totalDuration / 1000).toStringAsFixed(1)}s',
              style: TextStyle(
                color: FluxForgeTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
          const Spacer(),
          // Zoom controls
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 16),
            onPressed: () => setState(() => _scale = (_scale / 1.5).clamp(_minScale, _maxScale)),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Text(
            '${(_scale * 100).round()}%',
            style: TextStyle(color: FluxForgeTheme.textSecondary, fontSize: 10),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 16),
            onPressed: () => setState(() => _scale = (_scale * 1.5).clamp(_minScale, _maxScale)),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen, size: 16),
            onPressed: _fitToView,
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Fit to view',
          ),
        ],
      ),
    );
  }

  void _fitToView() {
    final containerWidth = context.size?.width ?? 800;
    final requiredWidth = _totalDuration * _pixelsPerMs;
    setState(() {
      _scale = (containerWidth - 100) / requiredWidth;
      _scale = _scale.clamp(_minScale, _maxScale);
    });
  }

  Widget _buildTimeline() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            // Scrub playhead
            final localX = details.localPosition.dx + _scrollController.offset;
            final ms = (localX / (_pixelsPerMs * _scale)).round();
            widget.onPlayheadScrub?.call(ms.clamp(0, _totalDuration));
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _timelineWidth + 100, // Extra padding
              height: constraints.maxHeight,
              child: CustomPaint(
                painter: _TimelinePainter(
                  events: widget.events,
                  scale: _scale,
                  pixelsPerMs: _pixelsPerMs,
                  totalDurationMs: _totalDuration,
                  playheadMs: widget.playheadMs,
                  hoveredEventId: _hoveredEventId,
                  selectedEventId: _selectedEventId,
                  isPlaying: widget.isPlaying,
                  playheadPulse: _playheadController.value,
                  accentColor: widget.accentColor,
                ),
                child: Stack(
                  children: [
                    // Event markers (as widgets for interaction)
                    for (final event in widget.events)
                      _buildEventMarker(event),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEventMarker(StageFlowEvent event) {
    final x = event.timestampMs * _pixelsPerMs * _scale;
    final isHovered = event.id == _hoveredEventId;
    final isSelected = event.id == _selectedEventId;
    final color = Color(event.category.color);

    return Positioned(
      left: x - _markerRadius,
      top: _timelineHeight - _markerRadius - 4,
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedEventId = event.id);
          widget.onStageTapped?.call(event);
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hoveredEventId = event.id),
          onExit: (_) => setState(() => _hoveredEventId = null),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tooltip on hover
              if (isHovered || isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgSurface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: color),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        event.stageName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${event.timestampMs}ms',
                        style: TextStyle(
                          color: FluxForgeTheme.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                      if (event.hasAudio)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.audiotrack, size: 10, color: FluxForgeTheme.accentGreen),
                            const SizedBox(width: 2),
                            Text(
                              'Has audio',
                              style: TextStyle(
                                color: FluxForgeTheme.accentGreen,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              // Marker dot
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: (isHovered || isSelected) ? _markerRadius * 2.5 : _markerRadius * 2,
                height: (isHovered || isSelected) ? _markerRadius * 2.5 : _markerRadius * 2,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: (isHovered || isSelected)
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: event.hasAudio
                    ? Icon(
                        Icons.audiotrack,
                        size: (isHovered || isSelected) ? 10 : 8,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryLegend() {
    // Get unique categories from events
    final categories = widget.events.map((e) => e.category).toSet().toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgMid,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final category in categories) ...[
            _buildLegendItem(category),
            if (category != categories.last) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(StageCategory category) {
    final count = widget.events.where((e) => e.category == category).length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Color(category.color),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${category.label} ($count)',
          style: TextStyle(
            color: FluxForgeTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// TIMELINE PAINTER
// =============================================================================

class _TimelinePainter extends CustomPainter {
  final List<StageFlowEvent> events;
  final double scale;
  final double pixelsPerMs;
  final int totalDurationMs;
  final int? playheadMs;
  final String? hoveredEventId;
  final String? selectedEventId;
  final bool isPlaying;
  final double playheadPulse;
  final Color accentColor;

  _TimelinePainter({
    required this.events,
    required this.scale,
    required this.pixelsPerMs,
    required this.totalDurationMs,
    this.playheadMs,
    this.hoveredEventId,
    this.selectedEventId,
    required this.isPlaying,
    required this.playheadPulse,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final timelineY = 60.0;
    final rulerY = 20.0;

    // Draw background timeline
    final timelinePaint = Paint()
      ..color = FluxForgeTheme.bgSurface
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, timelineY - 2, size.width, 4),
        const Radius.circular(2),
      ),
      timelinePaint,
    );

    // Draw time ruler
    _drawTimeRuler(canvas, size, rulerY);

    // Draw event duration bars
    for (final event in events) {
      if (event.durationMs != null && event.durationMs! > 0) {
        final x = event.timestampMs * pixelsPerMs * scale;
        final width = event.durationMs! * pixelsPerMs * scale;
        final color = Color(event.category.color);

        final barPaint = Paint()
          ..color = color.withOpacity(0.3)
          ..style = PaintingStyle.fill;

        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, timelineY - 6, width, 12),
            const Radius.circular(4),
          ),
          barPaint,
        );
      }
    }

    // Draw playhead
    if (playheadMs != null) {
      final playheadX = playheadMs! * pixelsPerMs * scale;
      final playheadPaint = Paint()
        ..color = accentColor.withOpacity(isPlaying ? (0.6 + playheadPulse * 0.4) : 1.0)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawLine(
        Offset(playheadX, rulerY),
        Offset(playheadX, size.height - 8),
        playheadPaint,
      );

      // Playhead triangle
      final trianglePath = Path()
        ..moveTo(playheadX - 6, rulerY)
        ..lineTo(playheadX + 6, rulerY)
        ..lineTo(playheadX, rulerY + 8)
        ..close();

      canvas.drawPath(
        trianglePath,
        Paint()..color = accentColor,
      );
    }
  }

  void _drawTimeRuler(Canvas canvas, Size size, double y) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Calculate tick interval based on scale
    int tickIntervalMs = 1000; // 1 second default
    if (scale < 0.5) tickIntervalMs = 2000;
    if (scale < 0.25) tickIntervalMs = 5000;
    if (scale > 2) tickIntervalMs = 500;
    if (scale > 3) tickIntervalMs = 250;

    final tickPaint = Paint()
      ..color = FluxForgeTheme.textSecondary.withOpacity(0.5)
      ..strokeWidth = 1;

    for (int ms = 0; ms <= totalDurationMs; ms += tickIntervalMs) {
      final x = ms * pixelsPerMs * scale;

      // Draw tick
      canvas.drawLine(
        Offset(x, y),
        Offset(x, y + 8),
        tickPaint,
      );

      // Draw label
      final label = '${(ms / 1000).toStringAsFixed(ms % 1000 == 0 ? 0 : 1)}s';
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          color: FluxForgeTheme.textSecondary,
          fontSize: 9,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - 14));
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) {
    return events != oldDelegate.events ||
        scale != oldDelegate.scale ||
        playheadMs != oldDelegate.playheadMs ||
        hoveredEventId != oldDelegate.hoveredEventId ||
        selectedEventId != oldDelegate.selectedEventId ||
        isPlaying != oldDelegate.isPlaying ||
        playheadPulse != oldDelegate.playheadPulse;
  }
}
