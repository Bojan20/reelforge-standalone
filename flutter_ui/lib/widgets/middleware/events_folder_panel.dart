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
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../services/native_file_picker.dart';
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
  String? _selectedLayerId;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  double _zoom = 1.0;
  double _scrollOffset = 0.0;

  final ScrollController _folderScrollController = ScrollController();
  final ScrollController _timelineScrollController = ScrollController();
  final ScrollController _tracksScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // Track keys for scroll-to-layer
  final Map<String, GlobalKey> _layerKeys = {};

  @override
  void dispose() {
    _folderScrollController.dispose();
    _timelineScrollController.dispose();
    _tracksScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Scroll to selected layer
  void _scrollToLayer(String layerId) {
    final key = _layerKeys[layerId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<MiddlewareProvider, EventsFolderData>(
      selector: (_, p) => (
        events: p.compositeEvents,
        selectedEvent: p.selectedCompositeEvent,
        selectedLayerIds: p.selectedLayerIds,
        selectedLayerCount: p.selectedLayerCount,
        hasLayerInClipboard: p.hasLayerInClipboard,
      ),
      builder: (context, data, _) {
        final events = data.events;
        final selectedEvent = data.selectedEvent;
        final filteredEvents = _filterEvents(events);

        // Group by category
        final grouped = <String, List<SlotCompositeEvent>>{};
        for (final event in filteredEvents) {
          final cat = event.category;
          grouped.putIfAbsent(cat, () => []).add(event);
        }

        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) => _handleKeyEvent(context, event, data, selectedEvent),
          child: Container(
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
                      child: _buildEventFolder(context, grouped),
                    ),
                    // Divider
                    Container(width: 1, color: FluxforgeColors.divider),
                    // Timeline area
                    Expanded(
                      child: selectedEvent != null
                          ? _buildTimelineView(context, data, selectedEvent)
                          : _buildEmptyStateWithDebug(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  /// Handle keyboard shortcuts for multi-select operations
  KeyEventResult _handleKeyEvent(BuildContext context, KeyEvent event, EventsFolderData data, SlotCompositeEvent? selectedEvent) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (selectedEvent == null) return KeyEventResult.ignored;

    final isCmd = HardwareKeyboard.instance.isMetaPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isMod = isCmd || isCtrl;

    final middleware = context.read<MiddlewareProvider>();

    // Cmd/Ctrl+A - Select all
    if (isMod && event.logicalKey == LogicalKeyboardKey.keyA) {
      middleware.selectAllLayers(selectedEvent.id);
      return KeyEventResult.handled;
    }

    // Escape - Clear selection
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      middleware.clearLayerSelection();
      setState(() => _selectedLayerId = null);
      return KeyEventResult.handled;
    }

    // Delete/Backspace - Delete selected
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (data.selectedLayerCount > 0) {
        middleware.deleteSelectedLayers(selectedEvent.id);
        setState(() => _selectedLayerId = null);
        return KeyEventResult.handled;
      }
    }

    // Cmd/Ctrl+D - Duplicate selected
    if (isMod && event.logicalKey == LogicalKeyboardKey.keyD) {
      if (data.selectedLayerCount > 0) {
        middleware.duplicateSelectedLayers(selectedEvent.id);
        return KeyEventResult.handled;
      }
    }

    // Cmd/Ctrl+C - Copy selected
    if (isMod && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (_selectedLayerId != null) {
        middleware.copyLayer(selectedEvent.id, _selectedLayerId!);
        return KeyEventResult.handled;
      }
    }

    // Cmd/Ctrl+V - Paste
    if (isMod && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (data.hasLayerInClipboard) {
        middleware.pasteLayer(selectedEvent.id);
        return KeyEventResult.handled;
      }
    }

    // M - Mute selected
    if (event.logicalKey == LogicalKeyboardKey.keyM) {
      if (data.selectedLayerCount > 0) {
        middleware.muteSelectedLayers(selectedEvent.id, true);
        return KeyEventResult.handled;
      }
    }

    // Shift+M - Unmute selected
    if (HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyM) {
      if (data.selectedLayerCount > 0) {
        middleware.muteSelectedLayers(selectedEvent.id, false);
        return KeyEventResult.handled;
      }
    }

    // S - Solo selected
    if (event.logicalKey == LogicalKeyboardKey.keyS && !isMod) {
      if (data.selectedLayerCount > 0) {
        middleware.soloSelectedLayers(selectedEvent.id, true);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Widget _buildEventFolder(
    BuildContext context,
    Map<String, List<SlotCompositeEvent>> grouped,
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
              return _buildCategorySection(context, entry.key, entry.value);
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
    BuildContext context,
    String category,
    List<SlotCompositeEvent> events,
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
        children: events.map((event) => _buildEventTile(context, event)).toList(),
      ),
    );
  }

  Widget _buildEventTile(BuildContext context, SlotCompositeEvent event) {
    final middleware = context.read<MiddlewareProvider>();
    final isSelected = middleware.selectedCompositeEventId == event.id;

    return InkWell(
      onTap: () {
        middleware.selectCompositeEvent(event.id);
        setState(() {
          _selectedLayerId = null;
        });
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

  Widget _buildTimelineView(BuildContext context, EventsFolderData data, SlotCompositeEvent event) {
    final duration = math.max(event.totalDurationSeconds, 2.0);
    final totalWidth = duration * _kPixelsPerSecond * _zoom;

    return Container(
      color: const Color(0xFF1a1a24), // Visible background
      child: Column(
        children: [
          // Event name banner - ALWAYS visible
          Container(
            height: 32,
            color: event.color.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.event, size: 16, color: event.color),
                const SizedBox(width: 8),
                Text(
                  'EVENT: ${event.name}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  '${event.layers.length} layers',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
          // Toolbar
          _buildTimelineToolbar(context, event),
          // Timeline ruler
          _buildTimelineRuler(event),
          // Tracks - ALWAYS show event header track (even with 0 layers)
          Expanded(
            child: Container(
              color: const Color(0xFF121218),
              child: ListView(
                controller: _tracksScrollController,
                children: [
                  // Event header track (ALWAYS visible)
                  _buildEventHeaderTrack(context, event, totalWidth),
                  // Layer tracks (if any)
                  ...event.layers.map((layer) {
                    // Ensure key exists for scroll-to
                    _layerKeys.putIfAbsent(layer.id, () => GlobalKey());
                    final isSelected = data.selectedLayerIds.contains(layer.id);
                    return _buildTrack(
                      context: context,
                      key: _layerKeys[layer.id],
                      layer: layer,
                      event: event,
                      isSelected: isSelected,
                      totalWidth: totalWidth,
                      duration: duration,
                    );
                  }),
                  // Empty state hint when no layers
                  if (event.layers.isEmpty)
                    _buildAddLayerHint(context, event),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Hint widget shown when event has no layers
  Widget _buildAddLayerHint(BuildContext context, SlotCompositeEvent event) {
    return Container(
      height: 80,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FluxforgeColors.deepBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FluxforgeColors.accent.withValues(alpha: 0.3),
          style: BorderStyle.solid,
        ),
      ),
      child: InkWell(
        onTap: () => _showAddLayerDialog(context, event),
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 24,
                color: FluxforgeColors.accent.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 12),
              Text(
                'Add audio layer to "${event.name}"',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineToolbar(BuildContext context, SlotCompositeEvent event) {
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
            onPressed: () => _showAddLayerDialog(context, event),
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

  /// Event header track - always visible, shows event name and drop zone
  Widget _buildEventHeaderTrack(BuildContext context, SlotCompositeEvent event, double totalWidth) {
    return Container(
      height: _kTrackHeight,
      decoration: BoxDecoration(
        color: event.color.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: event.color.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // Track header (fixed width)
          Container(
            width: 160,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: event.color.withValues(alpha: 0.15),
              border: Border(
                right: BorderSide(color: FluxforgeColors.divider),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: event.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.name,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Add layer button
                IconButton(
                  icon: Icon(Icons.add, size: 16, color: event.color),
                  onPressed: () => _showAddLayerDialog(context, event),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: 'Add layer',
                ),
              ],
            ),
          ),
          // Event region on timeline
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth + 100,
                child: Stack(
                  children: [
                    // Event region bar
                    Positioned(
                      left: 0,
                      top: 8,
                      child: Container(
                        width: math.max(event.totalDurationSeconds, 1.0) * _kPixelsPerSecond * _zoom,
                        height: _kTrackHeight - 16,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              event.color.withValues(alpha: 0.6),
                              event.color.withValues(alpha: 0.3),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: event.color.withValues(alpha: 0.8)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              event.name,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${event.layers.length} layers',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildTrack({
    required BuildContext context,
    Key? key,
    required SlotEventLayer layer,
    required SlotCompositeEvent event,
    required bool isSelected,
    required double totalWidth,
    required double duration,
  }) {
    final middleware = context.read<MiddlewareProvider>();

    return Container(
      key: key,
      height: _kTrackHeight,
      decoration: BoxDecoration(
        color: isSelected
            ? FluxforgeColors.accent.withValues(alpha: 0.1)
            : FluxforgeColors.surfaceBg,
        border: Border(
          bottom: BorderSide(color: FluxforgeColors.divider.withValues(alpha: 0.5)),
          left: isSelected
              ? BorderSide(color: FluxforgeColors.accent, width: 3)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          // Track header (fixed width)
          GestureDetector(
            onTap: () {
              // Multi-select with modifiers
              final isMod = HardwareKeyboard.instance.isMetaPressed ||
                  HardwareKeyboard.instance.isControlPressed;
              final isShift = HardwareKeyboard.instance.isShiftPressed;

              if (isMod) {
                // Cmd/Ctrl+click: toggle selection
                middleware.toggleLayerSelection(layer.id);
              } else if (isShift) {
                // Shift+click: range select
                if (_selectedLayerId != null) {
                  middleware.selectLayerRange(event.id, _selectedLayerId!, layer.id);
                } else {
                  middleware.selectLayer(layer.id);
                }
              } else {
                // Normal click: single select
                middleware.selectLayer(layer.id);
              }
              setState(() => _selectedLayerId = layer.id);
              // Scroll to newly selected layer
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToLayer(layer.id);
              });
            },
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
                    onPressed: () => _toggleLayerMute(context, event, layer),
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
                    onPressed: () => _toggleLayerSolo(context, event, layer),
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

  /// Empty timeline with grid and drop zone for adding layers
  Widget _buildEmptyTimeline(BuildContext context, SlotCompositeEvent event) {
    return Container(
      color: FluxforgeColors.surfaceBg,
      child: Stack(
        children: [
          // Grid background
          CustomPaint(
            size: Size.infinite,
            painter: _TimelineGridPainter(
              zoom: _zoom,
              pixelsPerSecond: _kPixelsPerSecond,
              trackHeight: _kTrackHeight,
            ),
          ),
          // Drop zone hint
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              decoration: BoxDecoration(
                color: FluxforgeColors.deepBg.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: FluxforgeColors.accent.withValues(alpha: 0.3),
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    size: 48,
                    color: FluxforgeColors.accent.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Event: ${event.name}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No audio layers yet',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => _showAddLayerDialog(context, event),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Audio Layer'),
                    style: TextButton.styleFrom(
                      foregroundColor: FluxforgeColors.accent,
                      backgroundColor: FluxforgeColors.accent.withValues(alpha: 0.1),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

  /// Empty state when no event is selected
  Widget _buildEmptyStateWithDebug() {
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
    // TODO: Integrate with PreviewEngine
  }

  void _toggleLayerMute(
    BuildContext context,
    SlotCompositeEvent event,
    SlotEventLayer layer,
  ) {
    final middleware = context.read<MiddlewareProvider>();
    final updatedLayers = event.layers.map((l) {
      if (l.id == layer.id) {
        return l.copyWith(muted: !l.muted);
      }
      return l;
    }).toList();

    middleware.updateCompositeEvent(event.copyWith(layers: updatedLayers));
  }

  void _toggleLayerSolo(
    BuildContext context,
    SlotCompositeEvent event,
    SlotEventLayer layer,
  ) {
    final middleware = context.read<MiddlewareProvider>();
    final updatedLayers = event.layers.map((l) {
      if (l.id == layer.id) {
        return l.copyWith(solo: !l.solo);
      }
      return l;
    }).toList();

    middleware.updateCompositeEvent(event.copyWith(layers: updatedLayers));
  }

  void _showAddLayerDialog(BuildContext context, SlotCompositeEvent event) {
    final middleware = context.read<MiddlewareProvider>();
    showDialog(
      context: context,
      builder: (ctx) => _AddLayerDialog(
        event: event,
        onAdd: (String name, String audioPath) {
          // Add layer with audio via MiddlewareProvider (single source of truth)
          // Duration is auto-detected from audio file
          middleware.addLayerToEvent(
            event.id,
            audioPath: audioPath,
            name: name,
          );
        },
      ),
    );
  }
}

// =============================================================================
// ADD LAYER DIALOG
// =============================================================================

class _AddLayerDialog extends StatefulWidget {
  final SlotCompositeEvent event;
  final void Function(String name, String audioPath) onAdd;

  const _AddLayerDialog({
    required this.event,
    required this.onAdd,
  });

  @override
  State<_AddLayerDialog> createState() => _AddLayerDialogState();
}

class _AddLayerDialogState extends State<_AddLayerDialog> {
  final _nameController = TextEditingController();
  String? _selectedAudioPath;
  bool _isPickingFile = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = 'Layer ${widget.event.layers.length + 1}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAudioFile() async {
    setState(() => _isPickingFile = true);

    try {
      // Use native file picker
      final files = await NativeFilePicker.pickAudioFiles();
      if (files.isNotEmpty) {
        setState(() {
          _selectedAudioPath = files.first;
          // Auto-set name from filename
          final filename = files.first.split('/').last;
          final nameWithoutExt = filename.contains('.')
              ? filename.substring(0, filename.lastIndexOf('.'))
              : filename;
          _nameController.text = nameWithoutExt;
        });
      }
    } catch (_) {
      // Ignore file picking errors
    } finally {
      setState(() => _isPickingFile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a24),
      title: Row(
        children: [
          Icon(Icons.add_circle, color: widget.event.color, size: 24),
          const SizedBox(width: 12),
          Text(
            'Add Layer to "${widget.event.name}"',
            style: const TextStyle(fontSize: 16, color: Colors.white),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Layer name
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Layer Name',
                labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                filled: true,
                fillColor: const Color(0xFF0a0a0c),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Audio file picker
            Text(
              'Audio File (optional)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _isPickingFile ? null : _pickAudioFile,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0a0a0c),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _selectedAudioPath != null
                        ? widget.event.color.withValues(alpha: 0.5)
                        : Colors.white24,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedAudioPath != null
                          ? Icons.audio_file
                          : Icons.folder_open,
                      size: 20,
                      color: _selectedAudioPath != null
                          ? widget.event.color
                          : Colors.white54,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedAudioPath != null
                            ? _selectedAudioPath!.split('/').last
                            : 'Click to select audio file...',
                        style: TextStyle(
                          fontSize: 12,
                          color: _selectedAudioPath != null
                              ? Colors.white
                              : Colors.white54,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isPickingFile)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),
            if (_selectedAudioPath != null) ...[
              const SizedBox(height: 8),
              Text(
                _selectedAudioPath!,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _nameController.text.trim().isNotEmpty && _selectedAudioPath != null
              ? () {
                  widget.onAdd(_nameController.text.trim(), _selectedAudioPath!);
                  Navigator.pop(context);
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.event.color,
            foregroundColor: Colors.white,
          ),
          child: const Text('Add Layer'),
        ),
      ],
    );
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

// =============================================================================
// TIMELINE GRID PAINTER
// =============================================================================

class _TimelineGridPainter extends CustomPainter {
  final double zoom;
  final double pixelsPerSecond;
  final double trackHeight;

  _TimelineGridPainter({
    required this.zoom,
    required this.pixelsPerSecond,
    required this.trackHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    final pps = pixelsPerSecond * zoom;

    // Vertical grid lines (time)
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      x += pps * 0.5; // Every 0.5 seconds
    }

    // Horizontal grid lines (tracks)
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      y += trackHeight;
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineGridPainter oldDelegate) {
    return zoom != oldDelegate.zoom ||
        pixelsPerSecond != oldDelegate.pixelsPerSecond ||
        trackHeight != oldDelegate.trackHeight;
  }
}
