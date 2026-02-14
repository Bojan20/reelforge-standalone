/// FluxForge Studio Events Folder Panel (Browser)
///
/// Event browser for listing, searching, creating and managing composite events.
/// Shows event metadata, layers, trigger stages — NO timeline, NO waveform.
/// Timeline editing belongs in CompositeEditorPanel (Editor tab).

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/slot_audio_events.dart';
import '../../providers/middleware_provider.dart';
import '../../services/audio_playback_service.dart';
import '../../services/event_registry.dart' show ContainerType;
import '../../theme/fluxforge_theme.dart';
import '../common/audio_waveform_picker_dialog.dart';
import '../common/fluxforge_search_field.dart';

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

// =============================================================================
// EVENTS FOLDER PANEL
// =============================================================================

class EventsFolderPanel extends StatefulWidget {
  const EventsFolderPanel({super.key});

  @override
  State<EventsFolderPanel> createState() => _EventsFolderPanelState();
}

class _EventsFolderPanelState extends State<EventsFolderPanel> {
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String? _editingEventId; // For inline rename
  final TextEditingController _renameController = TextEditingController();

  final ScrollController _folderScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _folderScrollController.dispose();
    _searchController.dispose();
    _renameController.dispose();
    super.dispose();
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
              // Header with count + create button
              _buildHeader(events),
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
                    // Event detail panel (right side)
                    Expanded(
                      child: selectedEvent != null
                          ? _buildEventDetailPanel(context, data, selectedEvent)
                          : _buildEmptyState(),
                    ),
                  ],
                ),
              ),
              // Action strip at bottom
              if (selectedEvent != null)
                _buildActionStrip(context, data, selectedEvent),
            ],
          ),
        ),
        );
      },
    );
  }

  // ==========================================================================
  // HEADER
  // ==========================================================================

  Widget _buildHeader(List<SlotCompositeEvent> events) {
    return Container(
      height: 32,
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
            'EVENTS BROWSER',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.7),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: events.isEmpty ? Colors.orange.withValues(alpha: 0.2) : FluxforgeColors.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${events.length}',
              style: TextStyle(
                fontSize: 9,
                color: events.isEmpty ? Colors.orange : FluxforgeColors.accent,
              ),
            ),
          ),
          // Trigger conditions count
          if (events.any((e) => e.triggerConditions.isNotEmpty)) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9040).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt, size: 10, color: Color(0xFFFF9040)),
                  const SizedBox(width: 2),
                  Text(
                    '${events.where((e) => e.triggerConditions.isNotEmpty).length}',
                    style: const TextStyle(fontSize: 9, color: Color(0xFFFF9040)),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          // Create Event button
          SizedBox(
            height: 24,
            child: TextButton.icon(
              onPressed: () => _showCreateEventDialog(context),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('New Event', style: TextStyle(fontSize: 10)),
              style: TextButton.styleFrom(
                foregroundColor: FluxforgeColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // KEYBOARD SHORTCUTS
  // ==========================================================================

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
      return KeyEventResult.handled;
    }

    // Delete/Backspace - Delete selected
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (data.selectedLayerCount > 0) {
        middleware.deleteSelectedLayers(selectedEvent.id);
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
      if (data.selectedLayerCount > 0) {
        final firstSelected = data.selectedLayerIds.first;
        middleware.copyLayer(selectedEvent.id, firstSelected);
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
    if (event.logicalKey == LogicalKeyboardKey.keyM && !isMod) {
      if (data.selectedLayerCount > 0) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          middleware.muteSelectedLayers(selectedEvent.id, false);
        } else {
          middleware.muteSelectedLayers(selectedEvent.id, true);
        }
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

  // ==========================================================================
  // LEFT: EVENT FOLDER
  // ==========================================================================

  Widget _buildEventFolder(
    BuildContext context,
    Map<String, List<SlotCompositeEvent>> grouped,
  ) {
    return Column(
      children: [
        _buildSearchBar(),
        _buildCategoryChips(grouped.keys.toSet()),
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
      child: FluxForgeSearchField(
        controller: _searchController,
        hintText: 'Search events...',
        onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
        onCleared: () => setState(() => _searchQuery = ''),
        style: FluxForgeSearchFieldStyle(
          backgroundColor: FluxforgeColors.deepBg,
          borderColor: FluxforgeColors.divider,
          focusBorderColor: FluxforgeColors.accent,
        ),
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
    final isEditing = _editingEventId == event.id;

    return InkWell(
      onTap: () {
        middleware.selectCompositeEvent(event.id);
        setState(() => _editingEventId = null);
      },
      onDoubleTap: () {
        setState(() {
          _editingEventId = event.id;
          _renameController.text = event.name;
        });
      },
      onSecondaryTapDown: (details) {
        _showEventContextMenu(context, event, details.globalPosition);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: isSelected
            ? FluxforgeColors.accent.withValues(alpha: 0.2)
            : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 36,
                  decoration: BoxDecoration(
                    color: event.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isEditing)
                        SizedBox(
                          height: 22,
                          child: TextField(
                            controller: _renameController,
                            autofocus: true,
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              filled: true,
                              fillColor: FluxforgeColors.deepBg,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(3),
                                borderSide: BorderSide(color: FluxforgeColors.accent),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(3),
                                borderSide: BorderSide(color: FluxforgeColors.accent),
                              ),
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                middleware.updateCompositeEvent(
                                  event.copyWith(name: value.trim()),
                                );
                              }
                              setState(() => _editingEventId = null);
                            },
                            onEditingComplete: () {
                              final value = _renameController.text.trim();
                              if (value.isNotEmpty) {
                                middleware.updateCompositeEvent(
                                  event.copyWith(name: value),
                                );
                              }
                              setState(() => _editingEventId = null);
                            },
                          ),
                        )
                      else
                        Text(
                          event.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: Colors.white,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '${event.layers.length} layer${event.layers.length != 1 ? 's' : ''}'
                            ' • ${event.totalDurationSeconds.toStringAsFixed(1)}s',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                          if (event.containerType != ContainerType.none) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: _containerColor(event.containerType).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                event.containerType.name.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: _containerColor(event.containerType),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.play_arrow, size: 18, color: FluxforgeColors.accent),
                  onPressed: () => _playEvent(event),
                  tooltip: 'Preview',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            // Trigger stages
            if (event.triggerStages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: event.triggerStages.map((stage) {
                    return GestureDetector(
                      onSecondaryTap: () {
                        final updated = event.triggerStages.where((s) => s != stage).toList();
                        middleware.updateCompositeEvent(
                          event.copyWith(triggerStages: updated),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: FluxforgeColors.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: FluxforgeColors.accent.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt, size: 9, color: FluxforgeColors.accent),
                            const SizedBox(width: 3),
                            Text(
                              stage,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: FluxforgeColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            // Trigger conditions
            if (event.triggerConditions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 3),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: event.triggerConditions.entries.map((entry) {
                    return GestureDetector(
                      onSecondaryTap: () {
                        final updated = Map<String, String>.from(event.triggerConditions);
                        updated.remove(entry.key);
                        middleware.updateCompositeEvent(
                          event.copyWith(triggerConditions: updated),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9040).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: const Color(0xFFFF9040).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${entry.key} ${entry.value}',
                          style: const TextStyle(
                            fontSize: 8,
                            color: Color(0xFFFF9040),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // RIGHT: EVENT DETAIL PANEL
  // ==========================================================================

  Widget _buildEventDetailPanel(BuildContext context, EventsFolderData data, SlotCompositeEvent event) {
    return Container(
      color: const Color(0xFF1a1a24),
      child: Column(
        children: [
          // Event header bar
          Container(
            height: 36,
            color: event.color.withValues(alpha: 0.2),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(color: event.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Preview event
                if (event.layers.isNotEmpty)
                  _EventPreviewButton(event: event),
                const SizedBox(width: 8),
                // Add layer
                TextButton.icon(
                  onPressed: () => _showAddLayerDialog(context, event),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add Layer', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: FluxforgeColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                ),
              ],
            ),
          ),
          // Content: metadata + layers list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Metadata section
                _buildMetadataSection(event),
                const SizedBox(height: 12),
                // Trigger stages section
                _buildTriggerStagesSection(context, event),
                const SizedBox(height: 12),
                // Trigger conditions section
                _buildTriggerConditionsSection(context, event),
                const SizedBox(height: 16),
                // Layers list section
                _buildLayersListSection(context, data, event),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Metadata: category, duration, container type
  Widget _buildMetadataSection(SlotCompositeEvent event) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxforgeColors.surfaceBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxforgeColors.divider),
      ),
      child: Row(
        children: [
          // Category badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _colorForCategory(event.category).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _colorForCategory(event.category).withValues(alpha: 0.4)),
            ),
            child: Text(
              event.category.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: _colorForCategory(event.category),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Duration
          Icon(Icons.timer_outlined, size: 14, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Text(
            '${event.totalDurationSeconds.toStringAsFixed(2)}s',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
          ),
          const SizedBox(width: 12),
          // Layers count
          Icon(Icons.layers, size: 14, color: Colors.white.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Text(
            '${event.layers.length}',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.7)),
          ),
          // Container type
          if (event.containerType != ContainerType.none) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _containerColor(event.containerType).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                event.containerType.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: _containerColor(event.containerType),
                ),
              ),
            ),
          ],
          // Looping
          if (event.looping) ...[
            const SizedBox(width: 12),
            Icon(Icons.loop, size: 14, color: Colors.green.withValues(alpha: 0.7)),
            const SizedBox(width: 4),
            Text('Loop', style: TextStyle(fontSize: 10, color: Colors.green.withValues(alpha: 0.7))),
          ],
        ],
      ),
    );
  }

  /// Trigger stages section with add button
  Widget _buildTriggerStagesSection(BuildContext context, SlotCompositeEvent event) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxforgeColors.surfaceBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxforgeColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, size: 14, color: FluxforgeColors.accent),
              const SizedBox(width: 6),
              Text(
                'TRIGGER STAGES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.6),
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _showAddTriggerStageDialog(context, event),
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 12, color: FluxforgeColors.accent),
                      const SizedBox(width: 2),
                      Text('Add', style: TextStyle(fontSize: 10, color: FluxforgeColors.accent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (event.triggerStages.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No trigger stages assigned',
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3), fontStyle: FontStyle.italic),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: event.triggerStages.map((stage) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: FluxforgeColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FluxforgeColors.accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, size: 10, color: FluxforgeColors.accent),
                      const SizedBox(width: 4),
                      Text(
                        stage,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: FluxforgeColors.accent),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          final updated = event.triggerStages.where((s) => s != stage).toList();
                          context.read<MiddlewareProvider>().updateCompositeEvent(
                            event.copyWith(triggerStages: updated),
                          );
                        },
                        child: Icon(Icons.close, size: 12, color: FluxforgeColors.accent.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// Trigger conditions section with add button
  Widget _buildTriggerConditionsSection(BuildContext context, SlotCompositeEvent event) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FluxforgeColors.surfaceBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FluxforgeColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, size: 14, color: Color(0xFFFF9040)),
              const SizedBox(width: 6),
              Text(
                'CONDITIONS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.6),
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _showAddConditionDialog(context, event),
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 12, color: Color(0xFFFF9040)),
                      const SizedBox(width: 2),
                      const Text('Add', style: TextStyle(fontSize: 10, color: Color(0xFFFF9040))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (event.triggerConditions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No conditions',
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3), fontStyle: FontStyle.italic),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: event.triggerConditions.entries.map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9040).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFFF9040).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${entry.key} ${entry.value}',
                        style: const TextStyle(fontSize: 10, color: Color(0xFFFF9040)),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          final updated = Map<String, String>.from(event.triggerConditions);
                          updated.remove(entry.key);
                          context.read<MiddlewareProvider>().updateCompositeEvent(
                            event.copyWith(triggerConditions: updated),
                          );
                        },
                        child: Icon(Icons.close, size: 12, color: const Color(0xFFFF9040).withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// Layers list — simple list view, NOT timeline tracks
  Widget _buildLayersListSection(BuildContext context, EventsFolderData data, SlotCompositeEvent event) {
    final middleware = context.read<MiddlewareProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(Icons.layers, size: 14, color: event.color),
            const SizedBox(width: 6),
            Text(
              'LAYERS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white.withValues(alpha: 0.6),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${event.layers.length}',
              style: TextStyle(fontSize: 10, color: event.color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Layers
        if (event.layers.isEmpty)
          _buildAddLayerHint(context, event)
        else
          ...event.layers.map((layer) {
            final isSelected = data.selectedLayerIds.contains(layer.id);
            return _buildLayerItem(context, event, layer, isSelected, middleware);
          }),
      ],
    );
  }

  Widget _buildLayerItem(
    BuildContext context,
    SlotCompositeEvent event,
    SlotEventLayer layer,
    bool isSelected,
    MiddlewareProvider middleware,
  ) {
    final filename = layer.audioPath.isNotEmpty
        ? layer.audioPath.split('/').last
        : 'No audio';

    return GestureDetector(
      onTap: () {
        final isMod = HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed;
        if (isMod) {
          middleware.toggleLayerSelection(layer.id);
        } else {
          middleware.selectLayer(layer.id);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? FluxforgeColors.accent.withValues(alpha: 0.15)
              : FluxforgeColors.surfaceBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? FluxforgeColors.accent.withValues(alpha: 0.5) : FluxforgeColors.divider,
          ),
        ),
        child: Row(
          children: [
            // Color bar
            Container(
              width: 3, height: 32,
              decoration: BoxDecoration(
                color: event.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            // Preview button
            _LayerPreviewButton(layer: layer, accentColor: event.color),
            const SizedBox(width: 4),
            // Mute
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
            // Solo
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
            // Layer info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    layer.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: layer.muted ? Colors.white38 : Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      // Filename
                      Flexible(
                        child: Text(
                          filename,
                          style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.4)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Duration
                      if (layer.durationSeconds != null)
                        Text(
                          '${layer.durationSeconds!.toStringAsFixed(2)}s',
                          style: TextStyle(fontSize: 9, color: event.color.withValues(alpha: 0.7)),
                        ),
                      // Offset
                      if (layer.offsetMs > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '+${layer.offsetMs.round()}ms',
                          style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.4)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Volume badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${(layer.volume * 100).round()}%',
                style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
            const SizedBox(width: 4),
            // Bus badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                _busName(layer.busId ?? 0),
                style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
            const SizedBox(width: 4),
            // Delete layer
            IconButton(
              icon: Icon(Icons.close, size: 14, color: Colors.white.withValues(alpha: 0.3)),
              onPressed: () {
                middleware.removeLayerFromEvent(event.id, layer.id);
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              tooltip: 'Remove layer',
            ),
          ],
        ),
      ),
    );
  }

  String _busName(int busId) {
    return switch (busId) {
      0 => 'Master',
      1 => 'Music',
      2 => 'SFX',
      3 => 'Voice',
      4 => 'UI',
      5 => 'Amb',
      _ => 'Bus$busId',
    };
  }

  Widget _buildAddLayerHint(BuildContext context, SlotCompositeEvent event) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: FluxforgeColors.deepBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FluxforgeColors.accent.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: () => _showAddLayerDialog(context, event),
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, size: 20, color: FluxforgeColors.accent.withValues(alpha: 0.6)),
              const SizedBox(width: 10),
              Text(
                'Add audio layer',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // EMPTY STATE
  // ==========================================================================

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.audio_file_outlined, size: 64, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(
            'Select an event to view details',
            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the Editor tab for timeline editing',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.3)),
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
      if (_selectedCategory != 'All' && event.category != _selectedCategory) {
        return false;
      }
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

  Color _containerColor(ContainerType type) {
    return switch (type) {
      ContainerType.blend => const Color(0xFF9370DB),
      ContainerType.random => const Color(0xFFFFBF00),
      ContainerType.sequence => const Color(0xFF40C8FF),
      ContainerType.none => Colors.grey,
    };
  }

  void _playEvent(SlotCompositeEvent event) {
    AudioPlaybackService.instance.previewCompositeEvent(event);
  }

  void _toggleLayerMute(BuildContext context, SlotCompositeEvent event, SlotEventLayer layer) {
    final middleware = context.read<MiddlewareProvider>();
    final updatedLayers = event.layers.map((l) {
      if (l.id == layer.id) return l.copyWith(muted: !l.muted);
      return l;
    }).toList();
    middleware.updateCompositeEvent(event.copyWith(layers: updatedLayers));
  }

  void _toggleLayerSolo(BuildContext context, SlotCompositeEvent event, SlotEventLayer layer) {
    final middleware = context.read<MiddlewareProvider>();
    final updatedLayers = event.layers.map((l) {
      if (l.id == layer.id) return l.copyWith(solo: !l.solo);
      return l;
    }).toList();
    middleware.updateCompositeEvent(event.copyWith(layers: updatedLayers));
  }

  // ==========================================================================
  // DIALOGS
  // ==========================================================================

  void _showCreateEventDialog(BuildContext context) {
    final middleware = context.read<MiddlewareProvider>();
    final nameController = TextEditingController(text: 'New Event');
    String selectedCategory = 'general';

    final categories = [
      'general', 'spin', 'reelstop', 'win', 'bigwin',
      'feature', 'bonus', 'anticipation', 'cascade', 'music',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a24),
          title: const Row(
            children: [
              Icon(Icons.add_circle, color: FluxforgeColors.accent, size: 20),
              SizedBox(width: 10),
              Text('Create Event', style: TextStyle(fontSize: 15, color: Colors.white)),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Event Name',
                    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF0a0a0c),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Category',
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: categories.map((cat) {
                    final isActive = selectedCategory == cat;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedCategory = cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isActive
                              ? _colorForCategory(cat).withValues(alpha: 0.3)
                              : const Color(0xFF0a0a0c),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isActive ? _colorForCategory(cat) : Colors.white24,
                          ),
                        ),
                        child: Text(
                          cat.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isActive ? _colorForCategory(cat) : Colors.white54,
                          ),
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  final event = middleware.createCompositeEvent(
                    name: name,
                    category: selectedCategory,
                    color: _colorForCategory(selectedCategory),
                  );
                  middleware.selectCompositeEvent(event.id);
                  Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: FluxforgeColors.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTriggerStageDialog(BuildContext context, SlotCompositeEvent event) {
    final middleware = context.read<MiddlewareProvider>();
    final stageController = TextEditingController();

    final commonStages = [
      'SPIN_START', 'SPIN_END', 'REEL_STOP', 'REEL_SPIN_LOOP',
      'WIN_PRESENT', 'WIN_LINE_SHOW', 'ROLLUP_START', 'ROLLUP_TICK', 'ROLLUP_END',
      'ANTICIPATION_ON', 'ANTICIPATION_OFF',
      'CASCADE_START', 'CASCADE_STEP', 'CASCADE_END',
      'FEATURE_ENTER', 'FEATURE_EXIT',
      'FREESPIN_START', 'FREESPIN_END',
      'BONUS_ENTER', 'BONUS_EXIT',
      'JACKPOT_TRIGGER', 'JACKPOT_AWARD',
    ];

    final available = commonStages
        .where((s) => !event.triggerStages.contains(s))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Row(
          children: [
            Icon(Icons.bolt, color: FluxforgeColors.accent, size: 18),
            SizedBox(width: 8),
            Text('Add Trigger Stage', style: TextStyle(fontSize: 14, color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: stageController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Type stage name or select below...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0a0a0c),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Common stages',
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 160,
                child: ListView(
                  children: available.map((stage) {
                    return InkWell(
                      onTap: () {
                        stageController.text = stage;
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                        child: Row(
                          children: [
                            Icon(Icons.bolt, size: 12, color: FluxforgeColors.accent.withValues(alpha: 0.6)),
                            const SizedBox(width: 6),
                            Text(stage, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final stage = stageController.text.trim().toUpperCase();
              if (stage.isNotEmpty && !event.triggerStages.contains(stage)) {
                final updatedStages = [...event.triggerStages, stage];
                middleware.updateCompositeEvent(
                  event.copyWith(triggerStages: updatedStages),
                );
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: FluxforgeColors.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddConditionDialog(BuildContext context, SlotCompositeEvent event) {
    final middleware = context.read<MiddlewareProvider>();
    final paramController = TextEditingController();
    final valueController = TextEditingController();

    final commonParams = [
      'winXbet > ', 'winTier >= ', 'consecutiveWins >= ',
      'balanceTrend > ', 'multiplier >= ', 'cascadeDepth >= ',
      'nearMissIntensity > ', 'anticipationLevel >= ',
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a24),
        title: const Row(
          children: [
            Icon(Icons.tune, color: Color(0xFFFF9040), size: 18),
            SizedBox(width: 8),
            Text('Add Trigger Condition', style: TextStyle(fontSize: 14, color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: paramController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Parameter',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                  hintText: 'e.g. winXbet',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0a0a0c),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: valueController,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Condition',
                  labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                  hintText: 'e.g. >= 5.0',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0a0a0c),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Quick presets',
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: commonParams.map((preset) {
                  return GestureDetector(
                    onTap: () {
                      final parts = preset.trim().split(' ');
                      paramController.text = parts.first;
                      valueController.text = parts.length > 1 ? parts.sublist(1).join(' ') : '';
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0a0a0c),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        preset.trim(),
                        style: const TextStyle(fontSize: 9, color: Colors.white54),
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final param = paramController.text.trim();
              final value = valueController.text.trim();
              if (param.isNotEmpty && value.isNotEmpty) {
                final updatedConditions = Map<String, String>.from(event.triggerConditions);
                updatedConditions[param] = value;
                middleware.updateCompositeEvent(
                  event.copyWith(triggerConditions: updatedConditions),
                );
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9040),
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddLayerDialog(BuildContext context, SlotCompositeEvent event) {
    final middleware = context.read<MiddlewareProvider>();
    showDialog(
      context: context,
      builder: (ctx) => _AddLayerDialog(
        event: event,
        onAdd: (String name, String audioPath) {
          middleware.addLayerToEvent(
            event.id,
            audioPath: audioPath,
            name: name,
          );
        },
      ),
    );
  }

  // ==========================================================================
  // ACTION STRIP
  // ==========================================================================

  Widget _buildActionStrip(
    BuildContext context,
    EventsFolderData data,
    SlotCompositeEvent selectedEvent,
  ) {
    final middleware = context.read<MiddlewareProvider>();

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FluxforgeColors.surfaceBg,
        border: Border(top: BorderSide(color: FluxforgeColors.divider)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => _previewEvent(selectedEvent),
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('PREVIEW', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: FluxforgeColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _deleteEvent(context, middleware, selectedEvent),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('REMOVE', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.withValues(alpha: 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => middleware.duplicateCompositeEvent(selectedEvent.id),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('DUPLICATE', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
          ),
          const Spacer(),
          if (data.selectedLayerCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: FluxforgeColors.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${data.selectedLayerCount} selected',
                style: const TextStyle(fontSize: 10, color: FluxforgeColors.accent),
              ),
            ),
        ],
      ),
    );
  }

  void _previewEvent(SlotCompositeEvent event) {
    AudioPlaybackService.instance.previewCompositeEvent(event);
  }

  void _deleteEvent(BuildContext context, MiddlewareProvider middleware, SlotCompositeEvent event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FluxforgeColors.surfaceBg,
        title: const Text('Delete Event?'),
        content: Text(
          'Are you sure you want to delete "${event.name}"?\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              middleware.deleteCompositeEvent(event.id);
              Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // CONTEXT MENU
  // ==========================================================================

  void _showEventContextMenu(
    BuildContext context,
    SlotCompositeEvent event,
    Offset globalPosition,
  ) {
    final middleware = context.read<MiddlewareProvider>();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: FluxforgeColors.surfaceBg,
      items: [
        PopupMenuItem(
          value: 'preview',
          child: Row(
            children: [
              Icon(Icons.play_arrow, size: 16, color: FluxforgeColors.accent),
              const SizedBox(width: 8),
              const Text('Preview Event'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              const Icon(Icons.edit, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              const Text('Rename'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              const Text('Duplicate'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'addTrigger',
          child: Row(
            children: [
              Icon(Icons.bolt, size: 16, color: FluxforgeColors.accent),
              const SizedBox(width: 8),
              const Text('Add Trigger Stage'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'addCondition',
          child: Row(
            children: [
              const Icon(Icons.tune, size: 16, color: Color(0xFFFF9040)),
              const SizedBox(width: 8),
              const Text('Add Condition'),
            ],
          ),
        ),
        if (event.triggerStages.isNotEmpty || event.triggerConditions.isNotEmpty) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'clearTriggers',
            child: Row(
              children: [
                Icon(Icons.clear_all, size: 16, color: Colors.orange.withValues(alpha: 0.8)),
                const SizedBox(width: 8),
                const Text('Clear All Triggers'),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 16, color: Colors.red),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'preview':
          _previewEvent(event);
        case 'rename':
          setState(() {
            _editingEventId = event.id;
            _renameController.text = event.name;
          });
        case 'duplicate':
          middleware.duplicateCompositeEvent(event.id);
        case 'addTrigger':
          _showAddTriggerStageDialog(context, event);
        case 'addCondition':
          _showAddConditionDialog(context, event);
        case 'clearTriggers':
          middleware.updateCompositeEvent(
            event.copyWith(
              triggerStages: const [],
              triggerConditions: const {},
            ),
          );
        case 'delete':
          _deleteEvent(context, middleware, event);
      }
    });
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
  bool _isPreviewing = false;
  int? _previewVoiceId;
  List<double>? _waveformData;
  double? _audioDuration;

  @override
  void initState() {
    super.initState();
    _nameController.text = 'Layer ${widget.event.layers.length + 1}';
  }

  @override
  void dispose() {
    _stopPreview();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAudioFile() async {
    setState(() => _isPickingFile = true);

    try {
      final path = await AudioWaveformPickerDialog.show(
        context,
        title: 'Select Audio File',
      );

      if (path != null && mounted) {
        setState(() {
          _selectedAudioPath = path;
          final filename = path.split('/').last;
          final nameWithoutExt = filename.contains('.')
              ? filename.substring(0, filename.lastIndexOf('.'))
              : filename;
          _nameController.text = nameWithoutExt;
        });

        _loadWaveformData(path);
      }
    } catch (_) {
      // Ignore file picking errors
    } finally {
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  void _loadWaveformData(String path) {
    if (mounted) {
      setState(() {
        _waveformData = _generateSimpleWaveform(64);
        _audioDuration = 2.0;
      });
    }
  }

  List<double> _generateSimpleWaveform(int samples) {
    final random = math.Random();
    return List.generate(samples, (i) {
      final progress = i / samples;
      final envelope = math.sin(progress * math.pi);
      return (0.3 + random.nextDouble() * 0.7) * envelope;
    });
  }

  void _togglePreview() {
    if (_isPreviewing) {
      _stopPreview();
    } else {
      _startPreview();
    }
  }

  void _startPreview() {
    if (_selectedAudioPath == null) return;

    final voiceId = AudioPlaybackService.instance.previewFile(_selectedAudioPath!);
    if (voiceId > 0) {
      setState(() {
        _isPreviewing = true;
        _previewVoiceId = voiceId;
      });

      if (_audioDuration != null) {
        Future.delayed(Duration(milliseconds: (_audioDuration! * 1000).toInt()), () {
          if (mounted && _isPreviewing) {
            _stopPreview();
          }
        });
      }
    }
  }

  void _stopPreview() {
    if (_previewVoiceId != null) {
      AudioPlaybackService.instance.stopVoice(_previewVoiceId!);
    }
    if (mounted) {
      setState(() {
        _isPreviewing = false;
        _previewVoiceId = null;
      });
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
          Expanded(
            child: Text(
              'Add Layer to "${widget.event.name}"',
              style: const TextStyle(fontSize: 16, color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Row(
              children: [
                Text(
                  'Audio File',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.7)),
                ),
                const SizedBox(width: 8),
                if (_selectedAudioPath != null && _audioDuration != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.event.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_audioDuration!.toStringAsFixed(2)}s',
                      style: TextStyle(fontSize: 10, color: widget.event.color, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _isPickingFile ? null : _pickAudioFile,
                    borderRadius: BorderRadius.circular(4),
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
                            _selectedAudioPath != null ? Icons.audio_file : Icons.folder_open,
                            size: 20,
                            color: _selectedAudioPath != null ? widget.event.color : Colors.white54,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedAudioPath != null
                                  ? _selectedAudioPath!.split('/').last
                                  : 'Click to select audio file...',
                              style: TextStyle(
                                fontSize: 12,
                                color: _selectedAudioPath != null ? Colors.white : Colors.white54,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isPickingFile)
                            const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_selectedAudioPath != null) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: _isPreviewing ? widget.event.color : const Color(0xFF0a0a0c),
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      onTap: _togglePreview,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _isPreviewing ? widget.event.color : Colors.white24,
                          ),
                        ),
                        child: Icon(
                          _isPreviewing ? Icons.stop : Icons.play_arrow,
                          color: _isPreviewing ? Colors.white : widget.event.color,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_selectedAudioPath != null && _waveformData != null) ...[
              const SizedBox(height: 12),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF0a0a0c),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CustomPaint(
                    painter: _WaveformPreviewPainter(
                      waveformData: _waveformData!,
                      color: widget.event.color,
                      isPlaying: _isPreviewing,
                    ),
                    size: const Size(double.infinity, 48),
                  ),
                ),
              ),
            ],
            if (_selectedAudioPath != null) ...[
              const SizedBox(height: 8),
              Text(
                _selectedAudioPath!,
                style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.4)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _stopPreview();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _nameController.text.trim().isNotEmpty && _selectedAudioPath != null
              ? () {
                  _stopPreview();
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
// WAVEFORM PREVIEW PAINTER (for Add Layer dialog only)
// =============================================================================

class _WaveformPreviewPainter extends CustomPainter {
  final List<double> waveformData;
  final Color color;
  final bool isPlaying;

  _WaveformPreviewPainter({
    required this.waveformData,
    required this.color,
    this.isPlaying = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    final paint = Paint()
      ..color = isPlaying ? color : color.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final centerY = size.height / 2;
    final barWidth = size.width / waveformData.length;

    for (var i = 0; i < waveformData.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final amplitude = waveformData[i] * (size.height / 2 - 4);

      canvas.drawLine(
        Offset(x, centerY - amplitude),
        Offset(x, centerY + amplitude),
        paint,
      );
    }

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPreviewPainter oldDelegate) {
    return oldDelegate.isPlaying != isPlaying ||
        oldDelegate.color != color;
  }
}

// =============================================================================
// LAYER PREVIEW BUTTON
// =============================================================================

class _LayerPreviewButton extends StatefulWidget {
  final SlotEventLayer layer;
  final Color accentColor;

  const _LayerPreviewButton({
    required this.layer,
    required this.accentColor,
  });

  @override
  State<_LayerPreviewButton> createState() => _LayerPreviewButtonState();
}

class _LayerPreviewButtonState extends State<_LayerPreviewButton> {
  bool _isPlaying = false;
  int? _voiceId;

  @override
  void dispose() {
    _stopPreview();
    super.dispose();
  }

  void _togglePreview() {
    if (_isPlaying) {
      _stopPreview();
    } else {
      _startPreview();
    }
  }

  void _startPreview() {
    if (widget.layer.audioPath.isEmpty) return;

    final voiceId = AudioPlaybackService.instance.previewFile(widget.layer.audioPath);
    if (voiceId > 0) {
      setState(() {
        _isPlaying = true;
        _voiceId = voiceId;
      });

      final duration = widget.layer.durationSeconds ?? 5.0;
      Future.delayed(Duration(milliseconds: (duration * 1000).toInt()), () {
        if (mounted && _isPlaying) {
          _stopPreview();
        }
      });
    }
  }

  void _stopPreview() {
    if (_voiceId != null) {
      AudioPlaybackService.instance.stopVoice(_voiceId!);
    }
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _voiceId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = widget.layer.audioPath.isNotEmpty;

    return IconButton(
      icon: Icon(
        _isPlaying ? Icons.stop : Icons.play_arrow,
        size: 14,
        color: !hasAudio
            ? Colors.white24
            : _isPlaying
                ? widget.accentColor
                : Colors.white54,
      ),
      onPressed: hasAudio ? _togglePreview : null,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      tooltip: _isPlaying ? 'Stop Preview' : 'Preview Layer',
    );
  }
}

// =============================================================================
// EVENT PREVIEW BUTTON
// =============================================================================

class _EventPreviewButton extends StatefulWidget {
  final SlotCompositeEvent event;

  const _EventPreviewButton({required this.event});

  @override
  State<_EventPreviewButton> createState() => _EventPreviewButtonState();
}

class _EventPreviewButtonState extends State<_EventPreviewButton> {
  bool _isPlaying = false;
  final List<int> _activeVoiceIds = [];

  @override
  void dispose() {
    _stopPreview();
    super.dispose();
  }

  void _togglePreview() {
    if (_isPlaying) {
      _stopPreview();
    } else {
      _startPreview();
    }
  }

  void _startPreview() {
    if (widget.event.layers.isEmpty) return;

    double maxDuration = 0;
    for (final layer in widget.event.layers) {
      if (layer.muted || layer.audioPath.isEmpty) continue;

      final delay = layer.offsetMs;
      final duration = (layer.durationSeconds ?? 1.0) + (delay / 1000);
      if (duration > maxDuration) maxDuration = duration;

      if (delay > 0) {
        Future.delayed(Duration(milliseconds: delay.toInt()), () {
          if (mounted && _isPlaying) {
            _playLayer(layer);
          }
        });
      } else {
        _playLayer(layer);
      }
    }

    setState(() => _isPlaying = true);

    Future.delayed(Duration(milliseconds: (maxDuration * 1000).toInt() + 100), () {
      if (mounted && _isPlaying) {
        _stopPreview();
      }
    });
  }

  void _playLayer(SlotEventLayer layer) {
    final voiceId = AudioPlaybackService.instance.previewFile(
      layer.audioPath,
      volume: layer.volume,
    );
    if (voiceId > 0) {
      _activeVoiceIds.add(voiceId);
    }
  }

  void _stopPreview() {
    for (final voiceId in _activeVoiceIds) {
      AudioPlaybackService.instance.stopVoice(voiceId);
    }
    _activeVoiceIds.clear();
    if (mounted) {
      setState(() => _isPlaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _togglePreview,
      icon: Icon(
        _isPlaying ? Icons.stop : Icons.play_arrow,
        size: 14,
        color: _isPlaying ? Colors.white : widget.event.color,
      ),
      label: Text(
        _isPlaying ? 'Stop' : 'Preview',
        style: TextStyle(
          fontSize: 11,
          color: _isPlaying ? Colors.white : widget.event.color,
        ),
      ),
      style: TextButton.styleFrom(
        backgroundColor: _isPlaying
            ? widget.event.color
            : widget.event.color.withValues(alpha: 0.15),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }
}
