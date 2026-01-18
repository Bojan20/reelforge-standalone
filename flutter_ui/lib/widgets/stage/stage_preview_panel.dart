/// FluxForge Studio — Ultimate Stage Preview Panel
///
/// Professional real-time visualization of stage events:
/// - Timeline view with animated stage transitions
/// - Category-based color coding
/// - Payload inspector with JSON viewer
/// - Stage flow diagram
/// - Performance metrics
/// - Recording and playback
/// - Filter and search
/// - Zoom and pan
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/stage_models.dart';
import '../../providers/stage_provider.dart';
import '../../theme/fluxforge_theme.dart';

// =============================================================================
// CONSTANTS
// =============================================================================

const double _kTimelineHeight = 200.0;
const double _kMinStageWidth = 80.0;
const double _kMaxStageWidth = 200.0;
const double _kLaneHeight = 32.0;
const double _kTimeRulerHeight = 24.0;
const int _kMaxVisibleEvents = 500;

// =============================================================================
// STAGE PREVIEW PANEL
// =============================================================================

/// Ultimate Stage Preview Panel with full visualization
class StagePreviewPanel extends StatefulWidget {
  final bool showInspector;
  final bool showFlowDiagram;
  final bool showMetrics;

  const StagePreviewPanel({
    super.key,
    this.showInspector = true,
    this.showFlowDiagram = false,
    this.showMetrics = true,
  });

  @override
  State<StagePreviewPanel> createState() => _StagePreviewPanelState();
}

class _StagePreviewPanelState extends State<StagePreviewPanel>
    with TickerProviderStateMixin {
  // --- View State ---
  _ViewMode _viewMode = _ViewMode.timeline;
  double _zoom = 1.0;
  double _scrollOffset = 0.0;
  StageEvent? _selectedEvent;
  Set<StageCategory> _visibleCategories = Set.from(StageCategory.values);
  String _searchQuery = '';
  bool _autoScroll = true;
  bool _showPayloads = false;

  // --- Animation ---
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // --- Controllers ---
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  // --- Stats ---
  int _totalEvents = 0;
  double _avgLatency = 0.0;
  DateTime? _sessionStart;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _sessionStart = DateTime.now();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<StageProvider>(
      builder: (context, provider, _) {
        final events = _getFilteredEvents(provider);
        _totalEvents = provider.liveEvents.length;

        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: Container(
            decoration: BoxDecoration(
              color: FluxForgeTheme.bgDeep,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FluxForgeTheme.borderSubtle),
            ),
            child: Column(
              children: [
                // Header with controls
                _PreviewHeader(
                  viewMode: _viewMode,
                  onViewModeChanged: (m) => setState(() => _viewMode = m),
                  zoom: _zoom,
                  onZoomChanged: (z) => setState(() => _zoom = z),
                  autoScroll: _autoScroll,
                  onAutoScrollChanged: (v) => setState(() => _autoScroll = v),
                  searchController: _searchController,
                  onSearchChanged: (q) => setState(() => _searchQuery = q),
                  isConnected: provider.isConnected,
                  isRecording: provider.isRecording,
                  onStartRecording: provider.startRecording,
                  onStopRecording: () { provider.stopRecording(); },
                ),

                // Category filters
                _CategoryFilters(
                  visibleCategories: _visibleCategories,
                  onToggle: _toggleCategory,
                  events: provider.liveEvents,
                ),

                // Main content area
                Expanded(
                  child: Row(
                    children: [
                      // Timeline/Flow view
                      Expanded(
                        flex: widget.showInspector ? 2 : 1,
                        child: _viewMode == _ViewMode.timeline
                            ? _TimelineView(
                                events: events,
                                zoom: _zoom,
                                scrollOffset: _scrollOffset,
                                onScrollChanged: (o) => setState(() => _scrollOffset = o),
                                selectedEvent: _selectedEvent,
                                onEventSelected: (e) => setState(() => _selectedEvent = e),
                                autoScroll: _autoScroll,
                                showPayloads: _showPayloads,
                                pulseAnimation: _pulseAnimation,
                              )
                            : _FlowDiagramView(
                                events: events,
                                selectedEvent: _selectedEvent,
                                onEventSelected: (e) => setState(() => _selectedEvent = e),
                              ),
                      ),

                      // Inspector panel
                      if (widget.showInspector && _selectedEvent != null)
                        Container(
                          width: 320,
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(color: FluxForgeTheme.borderSubtle),
                            ),
                          ),
                          child: _EventInspector(
                            event: _selectedEvent!,
                            onClose: () => setState(() => _selectedEvent = null),
                          ),
                        ),
                    ],
                  ),
                ),

                // Metrics bar
                if (widget.showMetrics)
                  _MetricsBar(
                    totalEvents: _totalEvents,
                    filteredEvents: events.length,
                    avgLatency: _avgLatency,
                    sessionStart: _sessionStart,
                    isConnected: provider.isConnected,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<StageEvent> _getFilteredEvents(StageProvider provider) {
    var events = provider.liveEvents;

    // Filter by category
    events = events.where((e) => _visibleCategories.contains(e.stage.category)).toList();

    // Filter by search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      events = events.where((e) {
        return e.stage.typeName.toLowerCase().contains(query) ||
            e.stage.category.displayName.toLowerCase().contains(query) ||
            (e.sourceEvent?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    // Limit visible events for performance
    if (events.length > _kMaxVisibleEvents) {
      events = events.sublist(events.length - _kMaxVisibleEvents);
    }

    return events;
  }

  void _toggleCategory(StageCategory category) {
    setState(() {
      if (_visibleCategories.contains(category)) {
        _visibleCategories.remove(category);
      } else {
        _visibleCategories.add(category);
      }
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Zoom controls
    if (event.logicalKey == LogicalKeyboardKey.equal ||
        event.logicalKey == LogicalKeyboardKey.add) {
      setState(() => _zoom = (_zoom * 1.2).clamp(0.5, 4.0));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.minus) {
      setState(() => _zoom = (_zoom / 1.2).clamp(0.5, 4.0));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit0 &&
        HardwareKeyboard.instance.isMetaPressed) {
      setState(() => _zoom = 1.0);
      return KeyEventResult.handled;
    }

    // Toggle auto-scroll
    if (event.logicalKey == LogicalKeyboardKey.keyA &&
        HardwareKeyboard.instance.isMetaPressed) {
      setState(() => _autoScroll = !_autoScroll);
      return KeyEventResult.handled;
    }

    // Toggle payloads
    if (event.logicalKey == LogicalKeyboardKey.keyP) {
      setState(() => _showPayloads = !_showPayloads);
      return KeyEventResult.handled;
    }

    // Clear selection
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _selectedEvent = null);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}

// =============================================================================
// VIEW MODE
// =============================================================================

enum _ViewMode {
  timeline,
  flow;

  IconData get icon => switch (this) {
        timeline => Icons.view_timeline,
        flow => Icons.account_tree,
      };

  String get label => switch (this) {
        timeline => 'Timeline',
        flow => 'Flow',
      };
}

// =============================================================================
// HEADER
// =============================================================================

class _PreviewHeader extends StatelessWidget {
  final _ViewMode viewMode;
  final ValueChanged<_ViewMode> onViewModeChanged;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final bool autoScroll;
  final ValueChanged<bool> onAutoScrollChanged;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool isConnected;
  final bool isRecording;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;

  const _PreviewHeader({
    required this.viewMode,
    required this.onViewModeChanged,
    required this.zoom,
    required this.onZoomChanged,
    required this.autoScroll,
    required this.onAutoScrollChanged,
    required this.searchController,
    required this.onSearchChanged,
    required this.isConnected,
    required this.isRecording,
    required this.onStartRecording,
    required this.onStopRecording,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          // Title with connection indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected
                  ? FluxForgeTheme.accentGreen
                  : FluxForgeTheme.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Stage Preview',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: FluxForgeTheme.textPrimary,
            ),
          ),

          const SizedBox(width: 16),

          // View mode toggle
          _ViewModeToggle(
            selected: viewMode,
            onChanged: onViewModeChanged,
          ),

          const Spacer(),

          // Search
          SizedBox(
            width: 200,
            height: 32,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              style: const TextStyle(fontSize: 12, color: FluxForgeTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search stages...',
                hintStyle: const TextStyle(color: FluxForgeTheme.textMuted),
                prefixIcon: const Icon(Icons.search, size: 16, color: FluxForgeTheme.textMuted),
                filled: true,
                fillColor: FluxForgeTheme.bgDeep,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Zoom controls
          _ZoomControls(
            zoom: zoom,
            onChanged: onZoomChanged,
          ),

          const SizedBox(width: 8),

          // Auto-scroll toggle
          Tooltip(
            message: 'Auto-scroll (⌘A)',
            child: IconButton(
              onPressed: () => onAutoScrollChanged(!autoScroll),
              icon: Icon(
                autoScroll ? Icons.vertical_align_bottom : Icons.pause,
                size: 18,
              ),
              color: autoScroll ? FluxForgeTheme.accentBlue : FluxForgeTheme.textMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),

          // Recording button
          Tooltip(
            message: isRecording ? 'Stop Recording' : 'Start Recording',
            child: IconButton(
              onPressed: isRecording ? () => onStopRecording() : onStartRecording,
              icon: Icon(
                isRecording ? Icons.stop : Icons.fiber_manual_record,
                size: 18,
              ),
              color: isRecording ? FluxForgeTheme.accentRed : FluxForgeTheme.textMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  final _ViewMode selected;
  final ValueChanged<_ViewMode> onChanged;

  const _ViewModeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: _ViewMode.values.map((mode) {
          final isSelected = mode == selected;
          return GestureDetector(
            onTap: () => onChanged(mode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isSelected ? FluxForgeTheme.accentBlue.withValues(alpha: 0.2) : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    mode.icon,
                    size: 14,
                    color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? FluxForgeTheme.accentBlue : FluxForgeTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final double zoom;
  final ValueChanged<double> onChanged;

  const _ZoomControls({required this.zoom, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => onChanged((zoom / 1.2).clamp(0.5, 4.0)),
          icon: const Icon(Icons.remove, size: 16),
          color: FluxForgeTheme.textMuted,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
        Container(
          width: 48,
          alignment: Alignment.center,
          child: Text(
            '${(zoom * 100).toInt()}%',
            style: const TextStyle(
              fontSize: 11,
              color: FluxForgeTheme.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
        ),
        IconButton(
          onPressed: () => onChanged((zoom * 1.2).clamp(0.5, 4.0)),
          icon: const Icon(Icons.add, size: 16),
          color: FluxForgeTheme.textMuted,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }
}

// =============================================================================
// CATEGORY FILTERS
// =============================================================================

class _CategoryFilters extends StatelessWidget {
  final Set<StageCategory> visibleCategories;
  final void Function(StageCategory) onToggle;
  final List<StageEvent> events;

  const _CategoryFilters({
    required this.visibleCategories,
    required this.onToggle,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    // Count events per category
    final counts = <StageCategory, int>{};
    for (final event in events) {
      counts[event.stage.category] = (counts[event.stage.category] ?? 0) + 1;
    }

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgDeep,
        border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: StageCategory.values.map((category) {
          final count = counts[category] ?? 0;
          final isVisible = visibleCategories.contains(category);
          final color = _getCategoryColor(category);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onToggle(category),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isVisible ? color.withValues(alpha: 0.15) : FluxForgeTheme.bgMid,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isVisible ? color.withValues(alpha: 0.5) : FluxForgeTheme.borderSubtle,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isVisible ? color : FluxForgeTheme.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      category.displayName,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: isVisible ? color : FluxForgeTheme.textMuted,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: isVisible ? color.withValues(alpha: 0.3) : FluxForgeTheme.bgSurface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          count.toString(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: isVisible ? color : FluxForgeTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================================
// TIMELINE VIEW
// =============================================================================

class _TimelineView extends StatefulWidget {
  final List<StageEvent> events;
  final double zoom;
  final double scrollOffset;
  final ValueChanged<double> onScrollChanged;
  final StageEvent? selectedEvent;
  final ValueChanged<StageEvent> onEventSelected;
  final bool autoScroll;
  final bool showPayloads;
  final Animation<double> pulseAnimation;

  const _TimelineView({
    required this.events,
    required this.zoom,
    required this.scrollOffset,
    required this.onScrollChanged,
    required this.selectedEvent,
    required this.onEventSelected,
    required this.autoScroll,
    required this.showPayloads,
    required this.pulseAnimation,
  });

  @override
  State<_TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<_TimelineView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      widget.onScrollChanged(_scrollController.offset);
    });
  }

  @override
  void didUpdateWidget(_TimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Auto-scroll to latest event
    if (widget.autoScroll &&
        widget.events.isNotEmpty &&
        widget.events.length != oldWidget.events.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) {
      return _buildEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          painter: _TimelinePainter(
            events: widget.events,
            zoom: widget.zoom,
            scrollOffset: _scrollController.hasClients
                ? _scrollController.offset
                : 0,
            viewportWidth: constraints.maxWidth,
            selectedEvent: widget.selectedEvent,
            pulseValue: widget.pulseAnimation.value,
          ),
          child: GestureDetector(
            onTapDown: (details) => _handleTap(details, constraints),
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: widget.events.length,
              itemExtent: _kMinStageWidth * widget.zoom,
              itemBuilder: (context, index) {
                final event = widget.events[index];
                return _TimelineEvent(
                  event: event,
                  isSelected: event == widget.selectedEvent,
                  onTap: () => widget.onEventSelected(event),
                  showPayload: widget.showPayloads,
                  zoom: widget.zoom,
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: widget.pulseAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: widget.pulseAnimation.value,
                child: const Icon(
                  Icons.timeline,
                  size: 48,
                  color: FluxForgeTheme.textMuted,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Waiting for stage events...',
            style: TextStyle(
              fontSize: 14,
              color: FluxForgeTheme.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect to an engine or import a recording',
            style: TextStyle(
              fontSize: 12,
              color: FluxForgeTheme.textDisabled,
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(TapDownDetails details, BoxConstraints constraints) {
    // Calculate which event was tapped based on position
    final x = details.localPosition.dx + (_scrollController.hasClients ? _scrollController.offset : 0);
    final eventWidth = _kMinStageWidth * widget.zoom;
    final index = (x / eventWidth).floor();

    if (index >= 0 && index < widget.events.length) {
      widget.onEventSelected(widget.events[index]);
    }
  }
}

class _TimelineEvent extends StatelessWidget {
  final StageEvent event;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showPayload;
  final double zoom;

  const _TimelineEvent({
    required this.event,
    required this.isSelected,
    required this.onTap,
    required this.showPayload,
    required this.zoom,
  });

  @override
  Widget build(BuildContext context) {
    final color = _getCategoryColor(event.stage.category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : FluxForgeTheme.bgMid,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category indicator
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),

            // Event name
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.stage.typeName,
                    style: TextStyle(
                      fontSize: 11 * math.sqrt(zoom),
                      fontWeight: FontWeight.w600,
                      color: FluxForgeTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${event.timestampMs.toStringAsFixed(0)}ms',
                    style: TextStyle(
                      fontSize: 9 * math.sqrt(zoom),
                      color: FluxForgeTheme.textMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),

            // Payload preview
            if (showPayload)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: FluxForgeTheme.bgDeep,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getPayloadPreview(),
                    style: const TextStyle(
                      fontSize: 8,
                      color: FluxForgeTheme.textMuted,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getPayloadPreview() {
    final stage = event.stage;
    return switch (stage) {
      ReelStop(reelIndex: final idx, symbols: final sym) =>
        'reel: $idx\nsym: ${sym.take(3).join(",")}',
      WinPresent(winAmount: final amt, lineCount: final lines) =>
        'win: $amt\nlines: $lines',
      BigWinTierStage(tier: final t, amount: final amt) =>
        'tier: ${t.name}\namt: $amt',
      FeatureEnter(featureType: final ft, totalSteps: final s) =>
        'type: ${ft.name}\nsteps: $s',
      _ => event.stage.toJson().entries.take(2).map((e) => '${e.key}: ${e.value}').join('\n'),
    };
  }
}

// =============================================================================
// TIMELINE PAINTER
// =============================================================================

class _TimelinePainter extends CustomPainter {
  final List<StageEvent> events;
  final double zoom;
  final double scrollOffset;
  final double viewportWidth;
  final StageEvent? selectedEvent;
  final double pulseValue;

  _TimelinePainter({
    required this.events,
    required this.zoom,
    required this.scrollOffset,
    required this.viewportWidth,
    required this.selectedEvent,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (events.isEmpty) return;

    // Draw time ruler at bottom
    _drawTimeRuler(canvas, size);

    // Draw connection lines between events
    _drawConnections(canvas, size);
  }

  void _drawTimeRuler(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.borderSubtle
      ..strokeWidth = 1;

    final rulerY = size.height - _kTimeRulerHeight;
    canvas.drawLine(
      Offset(0, rulerY),
      Offset(size.width, rulerY),
      paint,
    );

    // Draw time markers
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final eventWidth = _kMinStageWidth * zoom;
    final firstVisibleIndex = (scrollOffset / eventWidth).floor();
    final lastVisibleIndex = ((scrollOffset + viewportWidth) / eventWidth).ceil();

    for (int i = firstVisibleIndex; i <= lastVisibleIndex && i < events.length; i++) {
      if (i % 5 == 0) {
        // Major tick every 5 events
        final x = i * eventWidth - scrollOffset;
        final event = events[i];

        canvas.drawLine(
          Offset(x, rulerY),
          Offset(x, rulerY + 8),
          paint,
        );

        textPainter.text = TextSpan(
          text: '${event.timestampMs.toStringAsFixed(0)}ms',
          style: const TextStyle(
            fontSize: 9,
            color: FluxForgeTheme.textMuted,
            fontFamily: 'monospace',
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x + 4, rulerY + 8));
      }
    }
  }

  void _drawConnections(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FluxForgeTheme.borderSubtle.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final eventWidth = _kMinStageWidth * zoom;
    final firstVisibleIndex = (scrollOffset / eventWidth).floor().clamp(0, events.length - 1);
    final lastVisibleIndex =
        ((scrollOffset + viewportWidth) / eventWidth).ceil().clamp(0, events.length - 1);

    for (int i = firstVisibleIndex; i < lastVisibleIndex && i < events.length - 1; i++) {
      final x1 = (i + 1) * eventWidth - scrollOffset - eventWidth / 2;
      final x2 = (i + 2) * eventWidth - scrollOffset - eventWidth / 2;
      final y = size.height / 2;

      // Draw arrow
      final path = Path()
        ..moveTo(x1, y)
        ..lineTo(x2 - 8, y);

      canvas.drawPath(path, paint);

      // Arrow head
      final arrowPath = Path()
        ..moveTo(x2 - 8, y - 4)
        ..lineTo(x2, y)
        ..lineTo(x2 - 8, y + 4);

      canvas.drawPath(arrowPath, paint..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) {
    return events != oldDelegate.events ||
        zoom != oldDelegate.zoom ||
        scrollOffset != oldDelegate.scrollOffset ||
        selectedEvent != oldDelegate.selectedEvent ||
        pulseValue != oldDelegate.pulseValue;
  }
}

// =============================================================================
// FLOW DIAGRAM VIEW
// =============================================================================

class _FlowDiagramView extends StatelessWidget {
  final List<StageEvent> events;
  final StageEvent? selectedEvent;
  final ValueChanged<StageEvent> onEventSelected;

  const _FlowDiagramView({
    required this.events,
    required this.selectedEvent,
    required this.onEventSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(
        child: Text(
          'No events to display',
          style: TextStyle(color: FluxForgeTheme.textMuted),
        ),
      );
    }

    // Group events by category
    final grouped = <StageCategory, List<StageEvent>>{};
    for (final event in events) {
      grouped.putIfAbsent(event.stage.category, () => []).add(event);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: grouped.entries.map((entry) {
          final category = entry.key;
          final categoryEvents = entry.value;
          final color = _getCategoryColor(category);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category header
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    category.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${categoryEvents.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Event chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categoryEvents.take(20).map((event) {
                  final isSelected = event == selectedEvent;
                  return GestureDetector(
                    onTap: () => onEventSelected(event),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withValues(alpha: 0.2)
                            : FluxForgeTheme.bgMid,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? color : FluxForgeTheme.borderSubtle,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            event.stage.typeName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: FluxForgeTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${event.timestampMs.toStringAsFixed(0)}ms',
                            style: const TextStyle(
                              fontSize: 9,
                              color: FluxForgeTheme.textMuted,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// =============================================================================
// EVENT INSPECTOR
// =============================================================================

class _EventInspector extends StatelessWidget {
  final StageEvent event;
  final VoidCallback onClose;

  const _EventInspector({required this.event, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final color = _getCategoryColor(event.stage.category);

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: FluxForgeTheme.bgMid,
            border: Border(bottom: BorderSide(color: FluxForgeTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.stage.typeName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FluxForgeTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
                color: FluxForgeTheme.textMuted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Basic info
                _InfoSection(
                  title: 'Basic Info',
                  children: [
                    _InfoRow('Category', event.stage.category.displayName),
                    _InfoRow('Timestamp', '${event.timestampMs.toStringAsFixed(2)}ms'),
                    if (event.sourceEvent != null)
                      _InfoRow('Source', event.sourceEvent!),
                    _InfoRow('Looping', event.stage.isLooping ? 'Yes' : 'No'),
                    _InfoRow('Duck Music', event.stage.shouldDuckMusic ? 'Yes' : 'No'),
                  ],
                ),

                const SizedBox(height: 16),

                // Stage data
                _InfoSection(
                  title: 'Stage Data',
                  children: _buildStageData(),
                ),

                const SizedBox(height: 16),

                // Payload
                if (_hasPayload())
                  _InfoSection(
                    title: 'Payload',
                    children: _buildPayloadData(),
                  ),

                const SizedBox(height: 16),

                // Tags
                if (event.tags.isNotEmpty)
                  _InfoSection(
                    title: 'Tags',
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: event.tags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: FluxForgeTheme.accentBlue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                fontSize: 11,
                                color: FluxForgeTheme.accentBlue,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),

                const SizedBox(height: 16),

                // Raw JSON
                _InfoSection(
                  title: 'Raw JSON',
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: FluxForgeTheme.bgDeep,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SelectableText(
                        _formatJson(event.toJson()),
                        style: const TextStyle(
                          fontSize: 10,
                          color: FluxForgeTheme.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Actions
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyToClipboard(context),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy JSON'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FluxForgeTheme.textSecondary,
                    side: const BorderSide(color: FluxForgeTheme.borderSubtle),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildStageData() {
    final stage = event.stage;
    return switch (stage) {
      ReelStop(reelIndex: final idx, symbols: final sym) => [
          _InfoRow('Reel Index', idx.toString()),
          _InfoRow('Symbols', sym.join(', ')),
        ],
      ReelSpinning(reelIndex: final idx) => [
          _InfoRow('Reel Index', idx.toString()),
        ],
      WinPresent(winAmount: final amt, lineCount: final lines) => [
          _InfoRow('Win Amount', amt.toStringAsFixed(2)),
          _InfoRow('Line Count', lines.toString()),
        ],
      BigWinTierStage(tier: final t, amount: final amt) => [
          _InfoRow('Tier', t.displayName),
          _InfoRow('Amount', amt.toStringAsFixed(2)),
          _InfoRow('Min Ratio', '${t.minRatio}x'),
        ],
      FeatureEnter(featureType: final ft, totalSteps: final s, multiplier: final m) => [
          _InfoRow('Feature Type', ft.displayName),
          if (s != null) _InfoRow('Total Steps', s.toString()),
          _InfoRow('Multiplier', '${m}x'),
        ],
      FeatureStep(stepIndex: final idx, stepsRemaining: final rem, currentMultiplier: final m) => [
          _InfoRow('Step Index', idx.toString()),
          if (rem != null) _InfoRow('Remaining', rem.toString()),
          _InfoRow('Multiplier', '${m}x'),
        ],
      JackpotTrigger(tier: final t) => [
          _InfoRow('Tier', t.displayName),
          _InfoRow('Level', t.level.toString()),
        ],
      JackpotPresent(tier: final t, amount: final amt) => [
          _InfoRow('Tier', t.displayName),
          _InfoRow('Amount', amt.toStringAsFixed(2)),
        ],
      AnticipationOn(reelIndex: final idx, reason: final r) => [
          _InfoRow('Reel Index', idx.toString()),
          if (r != null) _InfoRow('Reason', r),
        ],
      _ => [
          ...stage.toJson().entries.where((e) => e.key != 'type').map(
                (e) => _InfoRow(
                  e.key.replaceAll('_', ' ').capitalize(),
                  e.value.toString(),
                ),
              ),
        ],
    };
  }

  bool _hasPayload() {
    final p = event.payload;
    return p.winAmount != null ||
        p.betAmount != null ||
        p.featureName != null ||
        p.multiplier != null ||
        (p.custom?.isNotEmpty ?? false);
  }

  List<Widget> _buildPayloadData() {
    final p = event.payload;
    final items = <Widget>[];

    if (p.winAmount != null) items.add(_InfoRow('Win Amount', p.winAmount!.toStringAsFixed(2)));
    if (p.betAmount != null) items.add(_InfoRow('Bet Amount', p.betAmount!.toStringAsFixed(2)));
    if (p.winRatio != null) items.add(_InfoRow('Win Ratio', '${p.winRatio!.toStringAsFixed(2)}x'));
    if (p.featureName != null) items.add(_InfoRow('Feature', p.featureName!));
    if (p.multiplier != null) items.add(_InfoRow('Multiplier', '${p.multiplier}x'));
    if (p.spinsRemaining != null) items.add(_InfoRow('Spins Left', p.spinsRemaining.toString()));
    if (p.balance != null) items.add(_InfoRow('Balance', p.balance!.toStringAsFixed(2)));

    if (p.winLines.isNotEmpty) {
      items.add(_InfoRow('Win Lines', p.winLines.length.toString()));
    }

    return items;
  }

  String _formatJson(Map<String, dynamic> json) {
    String result = '';
    void write(Map<String, dynamic> obj, int indent) {
      obj.forEach((key, value) {
        final padding = '  ' * indent;
        if (value is Map<String, dynamic>) {
          result += '$padding$key:\n';
          write(value, indent + 1);
        } else {
          result += '$padding$key: $value\n';
        }
      });
    }
    write(json, 0);
    return result.trim();
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _formatJson(event.toJson())));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FluxForgeTheme.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                color: FluxForgeTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// METRICS BAR
// =============================================================================

class _MetricsBar extends StatelessWidget {
  final int totalEvents;
  final int filteredEvents;
  final double avgLatency;
  final DateTime? sessionStart;
  final bool isConnected;

  const _MetricsBar({
    required this.totalEvents,
    required this.filteredEvents,
    required this.avgLatency,
    required this.sessionStart,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final sessionDuration = sessionStart != null
        ? DateTime.now().difference(sessionStart!)
        : Duration.zero;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: FluxForgeTheme.bgMid,
        border: Border(top: BorderSide(color: FluxForgeTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          _MetricChip(
            icon: Icons.event,
            label: 'Events',
            value: filteredEvents != totalEvents
                ? '$filteredEvents / $totalEvents'
                : totalEvents.toString(),
          ),
          const SizedBox(width: 16),
          _MetricChip(
            icon: Icons.timer,
            label: 'Session',
            value: _formatDuration(sessionDuration),
          ),
          const SizedBox(width: 16),
          _MetricChip(
            icon: Icons.speed,
            label: 'Avg Latency',
            value: '${avgLatency.toStringAsFixed(1)}ms',
          ),
          const Spacer(),
          Text(
            isConnected ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isConnected ? FluxForgeTheme.accentGreen : FluxForgeTheme.textMuted,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    } else {
      return '${d.inSeconds}s';
    }
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: FluxForgeTheme.textMuted),
        const SizedBox(width: 4),
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 10,
            color: FluxForgeTheme.textMuted,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: FluxForgeTheme.textSecondary,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// UTILITIES
// =============================================================================

Color _getCategoryColor(StageCategory category) => switch (category) {
      StageCategory.spinLifecycle => FluxForgeTheme.accentBlue,
      StageCategory.anticipation => FluxForgeTheme.accentOrange,
      StageCategory.winLifecycle => FluxForgeTheme.accentGreen,
      StageCategory.feature => const Color(0xFFff40ff),
      StageCategory.cascade => FluxForgeTheme.accentCyan,
      StageCategory.bonus => const Color(0xFFffff40),
      StageCategory.gamble => FluxForgeTheme.accentRed,
      StageCategory.jackpot => const Color(0xFFffd700),
      StageCategory.ui => FluxForgeTheme.textMuted,
      StageCategory.special => const Color(0xFFc040ff),
    };

extension StringCapitalize on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
