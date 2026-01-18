/// FluxForge Studio Events Folder Panel
///
/// Displays composite events from both Slot Lab and Middleware
/// with timeline tracks for each audio layer.
///
/// Two-way sync:
/// - Events created in Slot Lab appear here automatically
/// - Changes made here sync back to Slot Lab

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../theme/fluxforge_theme.dart';

// =============================================================================
// THEME SHORTCUTS
// =============================================================================

/// Shorthand for FluxForgeTheme colors
class FluxforgeColors {
  static const Color deepBg = FluxForgeTheme.bgDeepest;
  static const Color surfaceBg = FluxForgeTheme.bgSurface;
  static const Color divider = FluxForgeTheme.bgMid;
  static const Color accent = FluxForgeTheme.accentBlue;
}

// =============================================================================
// CONSTANTS
// =============================================================================

const double _kFolderWidth = 260.0;
const double _kTrackHeight = 56.0;
const double _kHeaderHeight = 40.0;
const double _kTimelineRulerHeight = 24.0;
const double _kPixelsPerSecond = 100.0;

// =============================================================================
// EVENTS FOLDER PANEL
// =============================================================================

class EventsFolderPanel extends StatefulWidget {
  const EventsFolderPanel({super.key});

  @override
  State<EventsFolderPanel> createState() => _EventsFolderPanelState();
}

class _EventsFolderPanelState extends State<EventsFolderPanel> {
  String? _selectedEventId;
  String? _selectedLayerId;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  double _zoom = 1.0;
  double _scrollOffset = 0.0;

  final ScrollController _folderScrollController = ScrollController();
  final ScrollController _timelineScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _folderScrollController.dispose();
    _timelineScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MiddlewareProvider>(
      builder: (context, middleware, _) {
        final events = middleware.compositeEvents;
        final filteredEvents = _filterEvents(events);

        // Group by category
        final grouped = <String, List<SlotCompositeEvent>>{};
        for (final event in filteredEvents) {
          final cat = event.category;
          grouped.putIfAbsent(cat, () => []).add(event);
        }

        return Container(
          color: FluxforgeColors.deepBg,
          child: Column(
            children: [
              // Header with count
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: FluxforgeColors.surfaceBg,
                  border: Border(bottom: BorderSide(color: FluxforgeColors.divider)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_special, size: 14, color: Colors.white70),
                    const SizedBox(width: 8),
                    Text(
                      'EVENTS FOLDER',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withValues(alpha: 0.7),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: events.isEmpty ? Colors.orange.withValues(alpha: 0.2) : FluxforgeColors.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${events.length} events',
                        style: TextStyle(
                          fontSize: 9,
                          color: events.isEmpty ? Colors.orange : FluxforgeColors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Main content
              Expanded(
                child: Row(
                  children: [
                    // Events folder tree
                    SizedBox(
                      width: _kFolderWidth,
                      child: _buildEventFolder(grouped, middleware),
                    ),
                    // Divider
                    Container(width: 1, color: FluxforgeColors.divider),
                    // Timeline area
                    Expanded(
                      child: _selectedEventId != null
                          ? _buildTimelineView(middleware)
                          : _buildEmptyState(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEventFolder(
    Map<String, List<SlotCompositeEvent>> grouped,
    MiddlewareProvider middleware,
  ) {
    return Column(
      children: [
        // Search bar
        _buildSearchBar(),
        // Category filter
        _buildCategoryChips(grouped.keys.toSet()),
        // Events list
        Expanded(
          child: ListView(
            controller: _folderScrollController,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: grouped.entries.map((entry) {
              return _buildCategorySection(entry.key, entry.value, middleware);
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: FluxforgeColors.surfaceBg,
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: 12, color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search events...',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          prefixIcon: Icon(Icons.search, size: 18, color: Colors.white.withValues(alpha: 0.5)),
          filled: true,
          fillColor: FluxforgeColors.deepBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildCategoryChips(Set<String> categories) {
    final allCategories = ['All', ...categories];
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: allCategories.map((cat) {
          final isSelected = _selectedCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilterChip(
              label: Text(
                cat,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategory = cat),
              backgroundColor: FluxforgeColors.deepBg,
              selectedColor: FluxforgeColors.accent.withValues(alpha: 0.3),
              checkmarkColor: FluxforgeColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              labelPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              side: BorderSide(
                color: isSelected ? FluxforgeColors.accent : Colors.white24,
                width: 1,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCategorySection(
    String category,
    List<SlotCompositeEvent> events,
    MiddlewareProvider middleware,
  ) {
    final color = _colorForCategory(category);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              category.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.7),
                letterSpacing: 0.5,
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
                '${events.length}',
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        children: events.map((event) => _buildEventTile(event, middleware)).toList(),
      ),
    );
  }

  Widget _buildEventTile(SlotCompositeEvent event, MiddlewareProvider middleware) {
    final isSelected = _selectedEventId == event.id;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedEventId = event.id;
          _selectedLayerId = null;
        });
        middleware.selectCompositeEvent(event.id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: isSelected
            ? FluxforgeColors.accent.withValues(alpha: 0.2)
            : Colors.transparent,
        child: Row(
          children: [
            // Color indicator
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: event.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            // Event info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${event.layers.length} layer${event.layers.length != 1 ? 's' : ''}'
                    ' • ${event.totalDurationSeconds.toStringAsFixed(1)}s',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            // Play button
            IconButton(
              icon: Icon(Icons.play_arrow, size: 18, color: FluxforgeColors.accent),
              onPressed: () => _playEvent(event),
              tooltip: 'Preview',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineView(MiddlewareProvider middleware) {
    final event = middleware.compositeEvents
        .where((e) => e.id == _selectedEventId)
        .firstOrNull;

    if (event == null) return _buildEmptyState();

    return Column(
      children: [
        // Toolbar
        _buildTimelineToolbar(event, middleware),
        // Timeline ruler
        _buildTimelineRuler(event),
        // Tracks
        Expanded(
          child: _buildTracksList(event, middleware),
        ),
      ],
    );
  }

  Widget _buildTimelineToolbar(SlotCompositeEvent event, MiddlewareProvider middleware) {
    return Container(
      height: _kHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxforgeColors.surfaceBg,
        border: Border(
          bottom: BorderSide(color: FluxforgeColors.divider),
        ),
      ),
      child: Row(
        children: [
          // Event name
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: event.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            event.name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          // Stage trigger
          if (event.triggerStages.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: FluxforgeColors.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                event.triggerStages.first,
                style: TextStyle(
                  fontSize: 10,
                  color: FluxforgeColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const Spacer(),
          // Zoom controls
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => setState(() => _zoom = (_zoom * 0.8).clamp(0.25, 4.0)),
            tooltip: 'Zoom out',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          Text(
            '${(_zoom * 100).round()}%',
            style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.7)),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => setState(() => _zoom = (_zoom * 1.25).clamp(0.25, 4.0)),
            tooltip: 'Zoom in',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          const SizedBox(width: 8),
          // Add layer button
          TextButton.icon(
            onPressed: () => _showAddLayerDialog(event, middleware),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add Layer', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: FluxforgeColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineRuler(SlotCompositeEvent event) {
    final duration = math.max(event.totalDurationSeconds, 2.0);
    final totalWidth = duration * _kPixelsPerSecond * _zoom;

    return Container(
      height: _kTimelineRulerHeight,
      color: FluxforgeColors.deepBg,
      child: SingleChildScrollView(
        controller: _timelineScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth + 100,
          child: CustomPaint(
            painter: _TimelineRulerPainter(
              duration: duration,
              zoom: _zoom,
              pixelsPerSecond: _kPixelsPerSecond,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTracksList(SlotCompositeEvent event, MiddlewareProvider middleware) {
    final duration = math.max(event.totalDurationSeconds, 2.0);
    final totalWidth = duration * _kPixelsPerSecond * _zoom;

    return ListView.builder(
      itemCount: event.layers.length,
      itemBuilder: (context, index) {
        final layer = event.layers[index];
        final isSelected = _selectedLayerId == layer.id;

        return _buildTrack(
          layer: layer,
          event: event,
          middleware: middleware,
          isSelected: isSelected,
          totalWidth: totalWidth,
          duration: duration,
        );
      },
    );
  }

  Widget _buildTrack({
    required SlotEventLayer layer,
    required SlotCompositeEvent event,
    required MiddlewareProvider middleware,
    required bool isSelected,
    required double totalWidth,
    required double duration,
  }) {
    return Container(
      height: _kTrackHeight,
      decoration: BoxDecoration(
        color: isSelected
            ? FluxforgeColors.accent.withValues(alpha: 0.1)
            : FluxforgeColors.surfaceBg,
        border: Border(
          bottom: BorderSide(color: FluxforgeColors.divider.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Track header (fixed width)
          GestureDetector(
            onTap: () => setState(() => _selectedLayerId = layer.id),
            child: Container(
              width: 160,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: FluxforgeColors.deepBg,
                border: Border(
                  right: BorderSide(color: FluxforgeColors.divider),
                ),
              ),
              child: Row(
                children: [
                  // Mute/Solo
                  IconButton(
                    icon: Icon(
                      layer.muted ? Icons.volume_off : Icons.volume_up,
                      size: 14,
                      color: layer.muted ? Colors.red : Colors.white54,
                    ),
                    onPressed: () => _toggleLayerMute(event, layer, middleware),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    tooltip: 'Mute',
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.headphones,
                      size: 14,
                      color: layer.solo ? FluxforgeColors.accent : Colors.white54,
                    ),
                    onPressed: () => _toggleLayerSolo(event, layer, middleware),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    tooltip: 'Solo',
                  ),
                  const SizedBox(width: 4),
                  // Layer name
                  Expanded(
                    child: Text(
                      layer.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: layer.muted ? Colors.white38 : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Track timeline
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth + 100,
                child: Stack(
                  children: [
                    // Layer region
                    Positioned(
                      left: (layer.offsetMs / 1000) * _kPixelsPerSecond * _zoom,
                      top: 4,
                      child: _buildLayerRegion(layer, event),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerRegion(SlotEventLayer layer, SlotCompositeEvent event) {
    final regionDuration = layer.durationSeconds ?? 1.0;
    final width = regionDuration * _kPixelsPerSecond * _zoom;

    return GestureDetector(
      onTap: () => setState(() => _selectedLayerId = layer.id),
      child: Container(
        width: width.clamp(20.0, 2000.0),
        height: _kTrackHeight - 8,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              event.color.withValues(alpha: 0.8),
              event.color.withValues(alpha: 0.5),
            ],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: _selectedLayerId == layer.id
                ? Colors.white
                : event.color.withValues(alpha: 0.8),
            width: _selectedLayerId == layer.id ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              layer.name,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${regionDuration.toStringAsFixed(2)}s',
              style: TextStyle(
                fontSize: 9,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.audio_file_outlined,
            size: 64,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'Select an event to view timeline',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Events created in Slot Lab will appear here',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // ACTIONS
  // ==========================================================================

  List<SlotCompositeEvent> _filterEvents(List<SlotCompositeEvent> events) {
    return events.where((event) {
      // Category filter
      if (_selectedCategory != 'All' && event.category != _selectedCategory) {
        return false;
      }
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return event.name.toLowerCase().contains(query) ||
            event.category.toLowerCase().contains(query) ||
            event.triggerStages.any((s) => s.toLowerCase().contains(query));
      }
      return true;
    }).toList();
  }

  Color _colorForCategory(String category) {
    return switch (category.toLowerCase()) {
      'spin' => const Color(0xFF4A9EFF),
      'reelstop' => const Color(0xFF9B59B6),
      'anticipation' => const Color(0xFFE74C3C),
      'win' => const Color(0xFFF1C40F),
      'bigwin' => const Color(0xFFFF9040),
      'feature' => const Color(0xFF40FF90),
      'bonus' => const Color(0xFFFF40FF),
      'general' => const Color(0xFF888888),
      _ => const Color(0xFF888888),
    };
  }

  void _playEvent(SlotCompositeEvent event) {
    debugPrint('[EventsFolder] Play event: ${event.name}');
    // TODO: Integrate with PreviewEngine
  }

  void _toggleLayerMute(
    SlotCompositeEvent event,
    SlotEventLayer layer,
    MiddlewareProvider middleware,
  ) {
    final updatedLayers = event.layers.map((l) {
      if (l.id == layer.id) {
        return l.copyWith(muted: !l.muted);
      }
      return l;
    }).toList();

    middleware.updateCompositeEvent(event.copyWith(layers: updatedLayers));
  }

  void _toggleLayerSolo(
    SlotCompositeEvent event,
    SlotEventLayer layer,
    MiddlewareProvider middleware,
  ) {
    final updatedLayers = event.layers.map((l) {
      if (l.id == layer.id) {
        return l.copyWith(solo: !l.solo);
      }
      return l;
    }).toList();

    middleware.updateCompositeEvent(event.copyWith(layers: updatedLayers));
  }

  void _showAddLayerDialog(SlotCompositeEvent event, MiddlewareProvider middleware) {
    // TODO: Show file picker dialog to add audio layer
    debugPrint('[EventsFolder] Add layer to event: ${event.name}');
  }
}

// =============================================================================
// TIMELINE RULER PAINTER
// =============================================================================

class _TimelineRulerPainter extends CustomPainter {
  final double duration;
  final double zoom;
  final double pixelsPerSecond;

  _TimelineRulerPainter({
    required this.duration,
    required this.zoom,
    required this.pixelsPerSecond,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw tick marks
    final pps = pixelsPerSecond * zoom;
    final interval = _getTickInterval();

    for (double t = 0; t <= duration; t += interval) {
      final x = t * pps;

      // Major tick
      canvas.drawLine(
        Offset(x, size.height - 12),
        Offset(x, size.height),
        paint,
      );

      // Label
      textPainter.text = TextSpan(
        text: _formatTime(t),
        style: TextStyle(
          fontSize: 9,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 2, 2));

      // Minor ticks
      if (interval >= 1.0) {
        for (int i = 1; i < 4; i++) {
          final minorX = x + (i * interval / 4) * pps;
          if (minorX <= duration * pps) {
            canvas.drawLine(
              Offset(minorX, size.height - 6),
              Offset(minorX, size.height),
              paint..color = Colors.white12,
            );
          }
        }
      }
    }
  }

  double _getTickInterval() {
    if (zoom > 2.0) return 0.25;
    if (zoom > 1.0) return 0.5;
    if (zoom > 0.5) return 1.0;
    return 2.0;
  }

  String _formatTime(double seconds) {
    if (seconds < 1) return '${(seconds * 1000).round()}ms';
    return '${seconds.toStringAsFixed(1)}s';
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) {
    return duration != oldDelegate.duration ||
        zoom != oldDelegate.zoom ||
        pixelsPerSecond != oldDelegate.pixelsPerSecond;
  }
}
